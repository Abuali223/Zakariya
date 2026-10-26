\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: invoice-guards.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- invoice-guards.sql — hisob-faktura / to'lovni o'zgartiruvchi admin amallari TO'LOV QULFI ostida.
--
--   Invariant: invoices.paidAmount / status / student_credit FAQAT qulflangan SECURITY DEFINER RPC'larda
--   o'zgaradi (apply_payment / apply_to_invoice / refund_invoice / reverse_payment — advisory lock
--   'iqror_pay:'||studentId). Admin panelning quyidagi amallari bu invariantni chetlab o'tardi:
--
--   1) «↻ Qayta hisoblash» (recalc) — oy hisob-fakturalarini BIR MARTA o'qib (snapshot), keyin har birini
--      ketma-ket upsert qilardi (paidAmount/status ham). Oraliqda (30–60 s) kelgan Click/naqd to'lov
--      eski snapshot bilan USTIGA YOZILIB yo'qolardi (faktura yana «kutilmoqda», ortiqcha avansga o'tmas).
--      -> reprice_invoice(): qulf ostida JORIY paidAmount bilan qayta hisoblaydi; haqiqatan to'langan
--         faktura narx o'zgarishida tegilmaydi; ortiqcha -> avans (jurnal bilan) — bitta tranzaksiyada.
--         p_cancel: o'quvchi shu oy uchun hisob-faktura talab qilmaydigan holatda (sinov / oy boshidan oldin
--         chiqgan / muzlatilgan / keyinroq faollashtirilgan) — faktura '[holat]' belgisi bilan BEKOR qilinadi,
--         to'langan pul avansga qaytadi. Holat yana mos bo'lsa, keyingi recalc uni qayta tiklaydi.
--   2) «Bekor» / «O'chir» / «To'lanmaganlarni tozalash» — eski ro'yxat asosida SHARTSIZ yozardi: oraliqda
--      to'langan faktura «bekor»/o'chirilib, pul hisobotlardan yo'qolardi.
--      -> cancel_invoice() / delete_unpaid_invoice(): qulf ostida «hali to'lanmagan»ligini tekshiradi.
--   3) «Biriktirish» (biriktirilmagan to'lov -> o'quvchi) — holatni tekshirmasdan yangilab, keyin alohida
--      apply_payment chaqirardi: allaqachon QAYTARILGAN (refund) to'lov ham o'qish haqiga qo'llanib ketardi.
--      -> assign_payment(): qatorni qulflab faqat 'unmatched' bo'lsa biriktiradi + qo'llaydi (atomik).
--   4) Bir martalik (har deployda xavfsiz) kanonlash: telefon/kod bo'yicha biriktirilgan eski Click
--      to'lovlarida payments/refunds."studentId" o'quvchining doc id'si bo'lib qolgan — studentId'ga.
-- Idempotent (run-all.sql zanjirida).
-- =====================================================================

-- ---------- 1) reprice_invoice ----------
create or replace function public.reprice_invoice(p_id text, p_net numeric, p_meta jsonb default '{}'::jsonb,
                                                  p_cancel boolean default false)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_claims jsonb; v_sid text; v_inv record; v_paid numeric; v_net numeric; v_newpaid numeric;
  v_excess numeric := 0; v_status text; v_cr numeric := 0; v_name text; v_stcancel boolean;
  v_meta jsonb := coalesce(p_meta, '{}'::jsonb); v_grant boolean; v_nid text;
begin
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance() or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  -- Qulf tartibi apply_payment bilan bir xil: avval o'quvchi (advisory), keyin faktura qatori.
  select "studentId" into v_sid from public.invoices where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));
  select id, coalesce(amount,0) as amount, coalesce("paidAmount",0) as paid0, coalesce(status,'') as status,
         coalesce("discountInfo",'') as info, coalesce(provider,'') as provider, coalesce("isGrant",false) as grant_,
         coalesce(month,'') as month
    into v_inv from public.invoices where id = p_id for update;
  -- Qulf kutilayotganda faktura o'chirilgan bo'lishi mumkin: bo'sh yozuv bilan davom etilsa «paid» qaytib, referral
  --   jurnaliga oy=NULL qator yozilardi (referral abadiy «sarflangan» bo'lib qolardi).
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  v_stcancel := (v_inv.status = 'canceled' and v_inv.info like '[holat]%');
  if v_inv.status = 'reversed' or (v_inv.status = 'canceled' and not v_stcancel) then
    return jsonb_build_object('ok', false, 'reason', 'terminal', 'status', v_inv.status);
  end if;
  -- To'langan summa: eski 'paid' yozuvlarda paidAmount bo'lmasligi mumkin -> amount (grant/0 bundan mustasno).
  v_paid := case when v_inv.status = 'paid' and not v_inv.grant_ and v_inv.provider <> 'grant' and v_inv.amount > 0
                 then greatest(v_inv.paid0, v_inv.amount) else v_inv.paid0 end;
  -- HAQIQATAN to'langan faktura narx o'zgarishida TEGILMAYDI (qarz tiklanmaydi) — snapshotdan KEYIN to'langan
  --   bo'lsa ham shu yerda (qulf ostida) aniqlanadi. Istisnolar: holat bo'yicha bekor (pul avansga qaytadi) va
  --   admin TASDIQLAGAN narx KAMAYISHI (p_meta.paidDecrease=true, 0 < yangi narx < to'langan) — masalan kechikib qo'llangan
  --   aka-uka chegirmasi: ortiqcha to'lov avansga qaytadi, faktura «to'langan» qoladi. Narx oshsa — baribir tegilmaydi;
  --   0 gacha (to'liq grant) tushirilmaydi (keyingi qayta hisoblash uni «naqdsiz grant» deb qarzga aylantirmasin).
  if v_inv.status = 'paid' and v_paid > 0 and not coalesce(p_cancel, false) then
    if not (coalesce(v_meta->>'paidDecrease', '') = 'true' and round(coalesce(p_net, 0)) < v_paid and round(coalesce(p_net, 0)) > 0) then
      return jsonb_build_object('ok', false, 'reason', 'paid');
    end if;
  end if;

  if coalesce(p_cancel, false) then
    v_excess := v_paid; v_newpaid := 0; v_status := 'canceled'; v_net := v_inv.amount;
  else
    v_net := greatest(0, round(coalesce(p_net, 0)));
    v_newpaid := least(v_paid, v_net);
    v_excess := greatest(0, v_paid - v_net);
    v_status := case when v_net <= 0 then 'paid' when v_newpaid >= v_net - 0.5 then 'paid'
                     when v_newpaid > 0 then 'partial' else 'pending' end;
  end if;

  -- Ortiqcha to'lov -> avans (+ jurnal) — faktura bilan BITTA tranzaksiyada (yarim holat yo'q).
  if v_excess > 0 and coalesce(v_sid, '') <> '' then
    select coalesce(credit,0) into v_cr from public.student_credit where id = v_sid for update;
    if not found then v_cr := 0; end if;
    insert into public.student_credit(id, "studentId", credit, "updatedAt") values (v_sid, v_sid, v_cr + v_excess, now())
      on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();
    select name into v_name from public.students where id = v_sid or "studentId" = v_sid limit 1;
    insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, provider, month, note, "at")
      values (gen_random_uuid()::text, v_sid, coalesce(v_name,''), v_excess, v_cr + v_excess, 'recompute', 'recompute', v_inv.month,
              case when coalesce(p_cancel,false) then 'Hisob-faktura holat bo''yicha bekor — to''lov avansga qaytdi'
                   else 'Qayta hisoblash: narx kamaydi, ortiqcha to''lov avansga' end, now());
  end if;

  v_grant := coalesce((v_meta->>'isGrant')::boolean, v_inv.grant_);
  if coalesce(p_cancel, false) then
    update public.invoices
       set status = 'canceled', "paidAmount" = 0, "paidAt" = null,
           "discountInfo" = '[holat] ' || coalesce(nullif(v_meta->>'statusReason',''), 'faol emas') || ' — shu oy hisob-faktura talab qilinmaydi'
     where id = p_id;
  else
    update public.invoices
       set amount = v_net, "paidAmount" = v_newpaid, status = v_status,
           "paidAt" = case when v_status = 'paid' then coalesce("paidAt", now()) else null end,
           provider = case when v_grant and v_newpaid <= 0 then 'grant' when provider = 'grant' then '' else provider end,
           "studentName"     = coalesce(nullif(v_meta->>'studentName',''), "studentName"),
           "classKey"        = coalesce(nullif(v_meta->>'classKey',''), "classKey"),
           "baseAmount"      = coalesce((v_meta->>'baseAmount')::numeric, "baseAmount"),
           discount          = coalesce((v_meta->>'discount')::numeric, discount),
           "discountInfo"    = coalesce(v_meta->>'discountInfo', "discountInfo"),
           "isGrant"         = v_grant,
           "pctApplied"      = coalesce((v_meta->>'pctApplied')::numeric, "pctApplied"),
           "sickDaysApplied" = coalesce((v_meta->>'sickDaysApplied')::int, "sickDaysApplied"),
           "sickAmount"      = coalesce((v_meta->>'sickAmount')::numeric, "sickAmount"),
           "priceKey"        = coalesce(v_meta->>'priceKey', "priceKey"),
           "billedFrom"      = coalesce(v_meta->>'billedFrom', "billedFrom"),
           "billedTo"        = coalesce(v_meta->>'billedTo', "billedTo"),
           "referralUsedIds" = coalesce(v_meta->'referralUsedIds', "referralUsedIds")
     where id = p_id;
    -- Referral jurnali — faktura bilan BIRGA (faktura yangilanmasa referral «sarflanmaydi»).
    if jsonb_typeof(v_meta->'referralUsedIds') = 'array' then
      for v_nid in select value from jsonb_array_elements_text(v_meta->'referralUsedIds') loop
        if coalesce(v_nid,'') = '' then continue; end if;
        insert into public.referral_ledger(id, "referrerId", amount, month, "appliedAt")
          values (v_nid, v_sid, 300000, v_inv.month, now())
          on conflict (id) do update set "referrerId" = excluded."referrerId", amount = excluded.amount, month = excluded.month, "appliedAt" = now();
      end loop;
    end if;
    -- '[holat]' bilan bekor qilingan faktura QAYTA TIKLANDI: bekor qilinganda uning puli avansga o'tgan edi — shu avans
    --   (eng eski qarzdan boshlab, odatiy waterfall) DARHOL qo'llanadi. Aks holda faktura «kutilmoqda» qarz bo'lib
    --   ko'rinib (qarz SMS'i ham ketardi), xuddi shu pul avansda turardi. Bir tranzaksiyada; advisory qulf qayta kiriladi.
    if v_stcancel and coalesce(v_sid,'') <> '' then
      perform public.apply_payment(v_sid, 0, 'credit', null);
      select coalesce("paidAmount",0), coalesce(status,'') into v_newpaid, v_status from public.invoices where id = p_id;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'status', v_status, 'amount', v_net, 'paidAmount', v_newpaid, 'excess', v_excess);
end $$;
revoke all on function public.reprice_invoice(text, numeric, jsonb, boolean) from public, anon;
grant execute on function public.reprice_invoice(text, numeric, jsonb, boolean) to authenticated, service_role;

-- ---------- 2) cancel_invoice / delete_unpaid_invoice ----------
create or replace function public.cancel_invoice(p_id text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_claims jsonb; v_sid text; v_inv record;
begin
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance() or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select "studentId" into v_sid from public.invoices where id = p_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));
  select coalesce(status,'') as status, coalesce("paidAmount",0) as paid into v_inv from public.invoices where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  if v_inv.status = 'canceled' then return jsonb_build_object('ok', true, 'dup', true); end if;
  if v_inv.paid > 0 or v_inv.status in ('paid','partial','reversed') then
    return jsonb_build_object('ok', false, 'reason', 'has-payment', 'status', v_inv.status, 'paidAmount', v_inv.paid);
  end if;
  update public.invoices set status = 'canceled' where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.cancel_invoice(text) from public, anon;
grant execute on function public.cancel_invoice(text) to authenticated, service_role;

create or replace function public.delete_unpaid_invoice(p_id text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_claims jsonb; v_sid text; v_inv record;
begin
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select "studentId" into v_sid from public.invoices where id = p_id;
  if not found then return jsonb_build_object('ok', true, 'dup', true); end if;
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));
  select coalesce(status,'') as status, coalesce("paidAmount",0) as paid into v_inv from public.invoices where id = p_id for update;
  if not found then return jsonb_build_object('ok', true, 'dup', true); end if;
  if v_inv.paid > 0 or v_inv.status in ('paid','partial') then
    return jsonb_build_object('ok', false, 'reason', 'has-payment', 'status', v_inv.status, 'paidAmount', v_inv.paid);
  end if;
  delete from public.invoices where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.delete_unpaid_invoice(text) from public, anon;
grant execute on function public.delete_unpaid_invoice(text) to authenticated, service_role;

-- ---------- 3) assign_payment ----------
create or replace function public.assign_payment(p_pay_id text, p_sid text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_claims jsonb; v_pay record; v_sid text; v_res jsonb;
begin
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance() or app.is_cashier() or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select id, coalesce(amount,0) as amount, coalesce(status,'') as status, coalesce(provider,'') as provider
    into v_pay from public.payments where id = p_pay_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  if v_pay.status not in ('unmatched', '') then
    return jsonb_build_object('ok', false, 'reason', 'not-unmatched', 'status', v_pay.status);
  end if;
  if v_pay.amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'amount<=0'); end if;
  select coalesce(nullif("studentId", ''), id) into v_sid from public.students
   where id = p_sid or "studentId" = p_sid order by (id = p_sid) desc limit 1;
  if v_sid is null then return jsonb_build_object('ok', false, 'reason', 'student-notfound'); end if;
  update public.payments set "studentId" = v_sid, matched = true, status = 'applied' where id = p_pay_id;
  v_res := public.apply_payment(v_sid, v_pay.amount, coalesce(nullif(v_pay.provider, ''), 'click'), p_pay_id);
  return jsonb_build_object('ok', true, 'sid', v_sid, 'apply', v_res);
end $$;
revoke all on function public.assign_payment(text, text) from public, anon;
grant execute on function public.assign_payment(text, text) to authenticated, service_role;

-- ---------- 4) Kanonlash (har deployda xavfsiz: faqat doc id bilan qolganlarni studentId'ga) ----------
--   Indeks AVVAL (parent-link-canon.sql'dagi bilan aynan bir xil; u yerda keyin no-op): 69d33af/815becd'dan birinchi deployda
--   indekssiz quyidagi UPDATE o'quvchi × to'lov bo'lib, qulflar ostida soniyalab davom etardi.
create index if not exists students_studentid_idx on public.students("studentId");
--   To'qnashuv himoyasi: o'quvchining studentId'si BOSHQA o'quvchining id/studentId'siga teng bo'lsa, yoki uning doc id'si
--   BOSHQA o'quvchining studentId'si bo'lsa (import to'qnashuvi; o'sha qiymat — boshqa bolaning kanonik kaliti), to'lov
--   joyida qoladi — aks holda pul jim BOSHQA bolaga o'tib ketardi. (student_keys_unique() zanjirda keyinroq.)
update public.payments p set "studentId" = s."studentId"
  from public.students s
 where p."studentId" = s.id and coalesce(s."studentId", '') <> '' and s."studentId" <> s.id
   and not exists (select 1 from public.students t where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId" or t."studentId" = s.id));
update public.refunds r set "studentId" = s."studentId"
  from public.students s
 where r."studentId" = s.id and coalesce(s."studentId", '') <> '' and s."studentId" <> s.id
   and not exists (select 1 from public.students t where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId" or t."studentId" = s.id));
do $$ declare n int; begin
  select count(*) into n from public.students s
   where coalesce(s."studentId", '') <> '' and s."studentId" <> s.id
     and exists (select 1 from public.students t where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId" or t."studentId" = s.id));
  if n > 0 then raise notice 'OGOHLANTIRISH: % ta o''quvchi kaliti boshqa o''quvchi bilan to''qnashadi — ularning to''lovlari doc id''da qoldirildi (migration/deploy/predeploy-checks.sql, 1-band)', n; end if;
end $$;

notify pgrst, 'reload schema';
