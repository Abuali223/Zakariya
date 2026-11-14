\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: refund-rpc.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT (High A / Medium #2) — refund_invoice: to'lovni QAYTARISH ATOMIK + IDEMPOTENT.
--   Muammo: admin.html refund oqimi 2-5 alohida atomik BO'LMAGAN yozuv edi
--     (refunds jurnal + invoice paidAmount↓ + [clawback] refunds + student_credit=0 +
--      credit_ledger). Oraliqда uzilса — invoice kamaygan-u avans clawback chala qolishi,
--     yoki retry'да IKKI marta qaytarish mumkin edi (posbon yo'q edi).
--   Yechim: BITTA tranzaksiya — invoice qulfi + advisory lock + p_ref idempotentlik
--     ('refund:'+ref applied_payments'да). refunds jurnal qatori DOIM shu tranzaksiyaда yoziladi.
--   Ruxsat: FAQAT direktor (refunds_ins = is_admin) yoki server — refund sezgir amal.
--   Kassa moduli o'rnatilgan bazada (moliya rejasi 1a, g8): pul hali berilmagan naqd qaytarish so'rovlari ham hisobga olinadi
--   (kassa:refund_pending — pastda); modul yo'q bazada — avvalgidek.
--   Oyna kaliti (live-1): admin.html qaytarish oynasi p_ref ni oyna ochilganda BIR marta yaratadi. Posbon qatori so'rovni ham saqlaydi
--     (applied_payments.result: target, id, amount, clawback); o'sha kalit BOSHQA ma'lumot bilan (summa, «avans ham», faktura / to'lov)
--     qayta kelsa — {ok:false, reason:'ref_mismatch'} + birinchi yozilgan summa va «avans ham» (avval jim {dup} qaytib, oyna «Allaqachon
--     qaytarilgan ✓» derdi — o'zgartirilgan summa yozilmagan bo'lsa ham). Bir xil ma'lumot — avvalgidek {dup}. Eski posbon qatori
--     (result bo'sh) — faqat summa solishtiriladi. ok:false javoblarda posbon yozilmaydi: rad etilgan so'rovni tuzatib, o'sha kalit bilan
--     qayta yuborsa bo'ladi. Kassa o'rnatilgan bazada shu oynadan naqd so'rov (cash_docs."clientRef" = 'ref_'||kalit) yuborilgan bo'lsa —
--     ref_mismatch (via 'cash'; live-1b: bitta qaytarish ikki usulda yozilmasin).
-- Idempotent (CREATE OR REPLACE). run-all.sql + deploy.sh'да.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================
create or replace function public.refund_invoice(
  p_target text, p_id text, p_amount numeric, p_reason text,
  p_clawback boolean default false, p_by text default '', p_ref text default '')
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_claims jsonb;
  v_inserted int := 0;
  v_inv record;
  v_sid text;
  v_sname text;
  v_month text;
  v_newpaid numeric;
  v_status text;
  v_cr numeric := 0;
  v_pname text;
  v_held numeric := 0;
  v_kassa boolean := to_regclass('public.cash_docs') is not null and coalesce(current_setting('iqror.kassa_rpc', true), '') <> '1';
  v_apamt numeric;      -- live-1: o'sha kalitning posbon qatori (birinchi yozilgan summa va so'rov)
  v_apres jsonb;
  v_viacash boolean := false;
begin
  -- Ruxsat: refund — FAQAT direktor (refunds jadvali ins = is_admin) yoki server.
  --   Kassa (moliya rejasi 1a, kassa-links.sql): Direktor TASDIQLAGAN naqd qaytarishni kassir pulni berayotgan paytda kassa
  --   funksiyasi (kassa_doc_pay) shu funksiya orqali bajaradi — tranzaksiya bayrog'i iqror.kassa_rpc faqat kassa funksiyalari
  --   ichida yoqiladi (mijoz uni o'zi yoqa olmaydi: PostgREST faqat public sxemasidagi funksiyalarni chaqiradi).
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or coalesce(v_claims->>'role','') = 'service_role'
          or coalesce(current_setting('iqror.kassa_rpc', true), '') = '1') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  p_amount := coalesce(p_amount, 0);
  if p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'amount<=0'); end if;
  if coalesce(nullif(p_reason, ''), '') = '' then return jsonb_build_object('ok', false, 'reason', 'reason-required'); end if;

  if p_target = 'invoice' then
    -- 1) Invoysни qulflab o'qib, notfound'ни posbonNI OLMASDAN qaytaramiz.
    -- paid: status 'paid' bo'lgan ESKI yozuvlarda paidAmount bo'lmasligi (0) mumkin — admin.html paidOf kabi
    --   to'langan summa = amount deb olinadi (aks holda qisman qaytarish BUTUN qarzni tiriltirib yuborardi).
    --    QULF TARTIBI: AVVAL advisory, KEYIN qator (apply_payment / reprice_invoice bilan bir xil — 40P01 bo'lmasin).
    select "studentId" into v_sid from public.invoices where id = p_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
    perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));
    select id, "studentId", coalesce(amount,0) as amount, coalesce(status,'') as status,
           case when status = 'paid' then greatest(coalesce("paidAmount",0), coalesce(amount,0)) else coalesce("paidAmount",0) end as paid,
           coalesce("studentName",'') as sname, coalesce(month,'') as month
      into v_inv from public.invoices where id = p_id for update;
    if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
    if coalesce(v_inv."studentId",'') <> coalesce(v_sid,'') then return jsonb_build_object('ok', false, 'error', 'retry'); end if;
    v_sname := v_inv.sname; v_month := v_inv.month;
    -- QULF OSTIDA qayta tekshiruv: eski oyna/ro'yxatdan (shu orada qaytarilgan / holat bo'yicha bekor qilingan /
    --   ikkinchi marta) qaytarish pul harakatlanmasa ham jurnalga «naqd qaytarildi» deb yozilmasin.
    if v_inv.status in ('canceled','reversed') or p_amount > v_inv.paid + 0.5 then
      return jsonb_build_object('ok', false, 'reason', 'exceeds-paid', 'paid', v_inv.paid, 'status', v_inv.status);
    end if;
    -- Moliya rejasi 1a (g8; kassa moduli o'rnatilgan bazada — kassa-links.sql: kassa_refund_request bilan bir xil qoida): shu faktura bo'yicha
    --   pul hali berilmagan NAQD qaytarish so'rovlari (so'rov / tasdiqlangan) + shu summa to'langan summadan oshmasin; avans ham qaytarilsa —
    --   o'quvchi avansi bo'yicha ochiq so'rov bo'lmasin. Aks holda «Naqd» so'rovi yuborilib (javob yo'qolgan), o'sha oynadan «bank» bilan
    --   qayta urinish qisman qaytarishni ikki marta bajarardi. Kassa so'rovi puli berilayotgan payt (iqror.kassa_rpc) — mustasno (so'rov
    --   paytida tekshirilgan). Kassasiz baza — avvalgidek.
    if v_kassa then
      -- Aynan shu qaytarish (o'sha p_ref) allaqachon bajarilgan bo'lsa — qayta urinish {dup}, so'rovlar tekshiruvidan OLDIN: aks holda
      --   bajarilgan qaytarish kutilayotgan naqd so'rov tufayli xato bo'lib ko'rinardi. Faqat o'qish (posbon pastda; shu o'quvchi navbati
      --   va faktura qulfi ostida — reattribute_avans kabi). live-1: o'sha kalit boshqa ma'lumot bilan — ref_mismatch (pastdagi posbon kabi).
      if coalesce(p_ref, '') <> '' then
        select a.amount, a.result into v_apamt, v_apres from public.applied_payments a where a.id = 'refund:' || p_ref;
        if found then
          if v_apamt is distinct from p_amount
             or (v_apres is not null and (v_apres ->> 'target' is distinct from p_target or v_apres ->> 'id' is distinct from p_id
                                          or (v_apres ->> 'clawback')::boolean is distinct from coalesce(p_clawback, false))) then
            return jsonb_build_object('ok', false, 'reason', 'ref_mismatch', 'amount', v_apamt, 'clawback', (v_apres ->> 'clawback')::boolean);
          end if;
          return jsonb_build_object('dup', true, 'ref', p_ref);
        end if;
        -- live-1b: shu oynadan naqd qaytarish so'rovi yuborilgan (javob yo'qolgan bo'lishi mumkin) — naqdsiz usul bilan yana yozilmaydi
        --   (so'rov bekor qilingan bo'lsa ham: boshqa usul — oynani qayta ochib, yangi kalit bilan)
        execute 'select exists (select 1 from public.cash_docs c where c."clientRef" = $1)' into v_viacash using 'ref_' || p_ref;
        if v_viacash then return jsonb_build_object('ok', false, 'reason', 'ref_mismatch', 'via', 'cash'); end if;
      end if;
      execute 'select coalesce(sum((c."sourceSnapshot" ->> ''amount'')::numeric), 0) from public.cash_docs c
                where c.op = ''out_refund'' and c.status in (''draft'', ''approved'') and c."sourceSnapshot" ->> ''target'' = ''invoice''
                  and c."sourceSnapshot" ->> ''targetId'' = $1'
        into v_held using p_id;
      if v_held > 0 and v_held + p_amount > v_inv.paid + 0.5 then
        raise exception 'Bu hisob-faktura bo''yicha pul hali berilmagan naqd qaytarish so''rovi bor (% so''m): yangisi bilan jami to''langan summadan (% so''m) oshadi — avval o''sha so''rovni kassadan bering yoki «Kassa»da bekor qiling',
          trim_scale(v_held), trim_scale(v_inv.paid) using errcode = '22023', hint = 'kassa:refund_pending';
      end if;
      if coalesce(p_clawback, false) and coalesce(v_sid, '') <> '' then
        execute 'select coalesce(sum(case when c."sourceSnapshot" ->> ''target'' = ''credit'' then (c."sourceSnapshot" ->> ''amount'')::numeric
                                          else coalesce((c."sourceSnapshot" ->> ''clawbackAmount'')::numeric, 0) end), 0)
                   from public.cash_docs c
                  where c.op = ''out_refund'' and c.status in (''draft'', ''approved'') and c."sourceSnapshot" ->> ''studentId'' = $1
                    and (c."sourceSnapshot" ->> ''target'' = ''credit'' or coalesce((c."sourceSnapshot" ->> ''clawback'')::boolean, false))'
          into v_held using v_sid;
        if v_held > 0 then
          raise exception 'Bu o''quvchi avansi bo''yicha pul hali berilmagan naqd qaytarish so''rovi bor (% so''m) — avval o''sha so''rovni kassadan bering yoki «Kassa»da bekor qiling',
            trim_scale(v_held) using errcode = '22023', hint = 'kassa:refund_pending';
        end if;
      end if;
    end if;

    -- 2) IDEMPOTENTLIK POSBONI: aynan shu refund faqat BIR marta pulни harakatlantiradi.
    --    live-1: posbon so'rovni ham saqlaydi; o'sha kalit boshqa ma'lumot bilan — ref_mismatch (birinchi yozilgani bilan), bir xil — {dup}.
    if p_ref is not null and p_ref <> '' then
      insert into public.applied_payments(id, "studentId", amount, result, "createdAt")
        values ('refund:' || p_ref, coalesce(v_sid,''), p_amount,
                jsonb_build_object('target', p_target, 'id', p_id, 'amount', p_amount, 'clawback', coalesce(p_clawback, false)), now())
        on conflict (id) do nothing;
      get diagnostics v_inserted = row_count;
      if v_inserted = 0 then
        select a.amount, a.result into v_apamt, v_apres from public.applied_payments a where a.id = 'refund:' || p_ref;
        if v_apamt is distinct from p_amount
           or (v_apres is not null and (v_apres ->> 'target' is distinct from p_target or v_apres ->> 'id' is distinct from p_id
                                        or (v_apres ->> 'clawback')::boolean is distinct from coalesce(p_clawback, false))) then
          return jsonb_build_object('ok', false, 'reason', 'ref_mismatch', 'amount', v_apamt, 'clawback', (v_apres ->> 'clawback')::boolean);
        end if;
        return jsonb_build_object('dup', true, 'ref', p_ref);
      end if;
    end if;

    -- 3) refunds jurnal (pul o'zgarishi hech qachon jurnalsiz qolmasin — bitta tranzaksiyaда).
    insert into public.refunds(id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, "createdAt")
      values (gen_random_uuid()::text, 'invoice', p_id, coalesce(v_sid,''), v_sname, p_amount, p_reason, coalesce(p_by,''), v_month, now());

    -- 4) invoice paidAmount↓ (0 dan past emas) + status qayta hisoblanadi (to'liq qaytsa -> 'pending', qarz tirilaadi).
    v_newpaid := greatest(0, v_inv.paid - p_amount);
    v_status  := case when v_newpaid <= 0 then 'pending'
                      when v_newpaid >= v_inv.amount - 0.5 then 'paid'
                      else 'partial' end;
    update public.invoices set "paidAmount" = v_newpaid, status = v_status, "reversedAt" = now() where id = p_id;

    -- 5) Avans clawback (direktor belgilaган + avans bor bo'lsa): avansни 0 ga tushiramiz (o'quvchi ketyapti).
    if coalesce(p_clawback, false) and v_sid is not null and v_sid <> '' then
      select coalesce(credit,0) into v_cr from public.student_credit where id = v_sid for update;
      if found and v_cr > 0 then
        update public.student_credit set credit = 0, "updatedAt" = now() where id = v_sid;
        insert into public.refunds(id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, "createdAt")
          values (gen_random_uuid()::text, 'credit', v_sid, v_sid, v_sname, v_cr,
                  p_reason || ' · avans 0 ga tushirildi', coalesce(p_by,''), v_month, now());
        insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, note, "at")
          values (gen_random_uuid()::text, v_sid, v_sname, -v_cr, 0, 'manual', 'Refundda avans 0 ga tushirildi', now());
      end if;
    end if;
    return jsonb_build_object('ok', true, 'target', 'invoice', 'newPaid', v_newpaid, 'status', v_status,
                              'clawback', coalesce(v_cr,0), 'studentId', coalesce(v_sid,''));

  elsif p_target = 'payment' then
    -- Biriktirilmagan to'lov: 'refunded' deb belgilanadi + refunds jurnal. (Invoice/avans TEGILMAYDI.)
    --   Qatorni QULFLAB holatini tekshiramiz: faqat hali BIRIKTIRILMAGAN ('unmatched'/'') to'lov qaytariladi.
    --   Aks holda (eski ro'yxatdan) allaqachon o'quvchiga biriktirilgan va fakturaga qo'llangan to'lov ham
    --   'refunded' bo'lib — pul ham qaytarilgan, ham o'qish haqi sifatida hisoblangan bo'lib qolardi
    --   (split_payment bilan bir xil qoida: FOR UPDATE + status in ('unmatched','')).
    declare v_pst text; v_pamt numeric;
    begin
      select coalesce(status,''), coalesce(amount,0) into v_pst, v_pamt from public.payments where id = p_id for update;
      if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
      if v_pst not in ('unmatched','') then return jsonb_build_object('ok', false, 'reason', 'not-unmatched', 'status', v_pst); end if;
      -- Faqat TO'LIQ qaytarish: to'lov butunlay 'refunded' bo'ladi — qisman qaytarishda qolgan pul hech qayerda
      --   ko'rinmay yo'qolardi. Qisman bo'lsa: avval o'quvchiga biriktiring, ortiqchasini avansdan qaytaring.
      if abs(p_amount - v_pamt) > 0.5 then
        return jsonb_build_object('ok', false, 'reason', 'partial-unmatched', 'amount', v_pamt);
      end if;
    end;
    -- g8 (yuqoridagi qoida): shu to'lov bo'yicha pul hali berilmagan naqd qaytarish so'rovi bo'lsa — rad (to'lov faqat to'liq qaytariladi)
    if v_kassa then
      -- live-1b (fakturadagi kabi): shu oynadan naqd so'rov yuborilgan — naqdsiz usul bilan yozilmaydi
      if coalesce(p_ref, '') <> '' then
        execute 'select exists (select 1 from public.cash_docs c where c."clientRef" = $1)' into v_viacash using 'ref_' || p_ref;
        if v_viacash then return jsonb_build_object('ok', false, 'reason', 'ref_mismatch', 'via', 'cash'); end if;
      end if;
      execute 'select coalesce(sum((c."sourceSnapshot" ->> ''amount'')::numeric), 0) from public.cash_docs c
                where c.op = ''out_refund'' and c.status in (''draft'', ''approved'') and c."sourceSnapshot" ->> ''target'' = ''payment''
                  and c."sourceSnapshot" ->> ''targetId'' = $1'
        into v_held using p_id;
      if v_held > 0 then
        raise exception 'Bu to''lov bo''yicha pul hali berilmagan naqd qaytarish so''rovi bor (% so''m) — avval o''sha so''rovni kassadan bering yoki «Kassa»da bekor qiling',
          trim_scale(v_held) using errcode = '22023', hint = 'kassa:refund_pending';
      end if;
    end if;
    if p_ref is not null and p_ref <> '' then   -- posbon (live-1: so'rov bilan; o'sha kalit boshqa to'lov / summa bilan — ref_mismatch)
      insert into public.applied_payments(id, "studentId", amount, result, "createdAt")
        values ('refund:' || p_ref, '', p_amount,
                jsonb_build_object('target', p_target, 'id', p_id, 'amount', p_amount, 'clawback', coalesce(p_clawback, false)), now())
        on conflict (id) do nothing;
      get diagnostics v_inserted = row_count;
      if v_inserted = 0 then
        select a.amount, a.result into v_apamt, v_apres from public.applied_payments a where a.id = 'refund:' || p_ref;
        if v_apamt is distinct from p_amount
           or (v_apres is not null and (v_apres ->> 'target' is distinct from p_target or v_apres ->> 'id' is distinct from p_id
                                        or (v_apres ->> 'clawback')::boolean is distinct from coalesce(p_clawback, false))) then
          return jsonb_build_object('ok', false, 'reason', 'ref_mismatch', 'amount', v_apamt, 'clawback', (v_apres ->> 'clawback')::boolean);
        end if;
        return jsonb_build_object('dup', true, 'ref', p_ref);
      end if;
    end if;
    select coalesce("payerName",'') into v_pname from public.payments where id = p_id;
    insert into public.refunds(id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, "createdAt")
      values (gen_random_uuid()::text, 'payment', p_id, '', coalesce(v_pname,''), p_amount, p_reason, coalesce(p_by,''), '', now());
    update public.payments set status = 'refunded' where id = p_id;
    return jsonb_build_object('ok', true, 'target', 'payment');
  end if;

  return jsonb_build_object('ok', false, 'reason', 'bad-target');
end $$;
revoke all on function public.refund_invoice(text, text, numeric, text, boolean, text, text) from public;
grant execute on function public.refund_invoice(text, text, numeric, text, boolean, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
