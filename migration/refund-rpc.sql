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
begin
  -- Ruxsat: refund — FAQAT direktor (refunds jadvali ins = is_admin) yoki server.
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or coalesce(v_claims->>'role','') = 'service_role') then
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

    -- 2) IDEMPOTENTLIK POSBONI: aynan shu refund faqat BIR marta pulни harakatlantiradi.
    if p_ref is not null and p_ref <> '' then
      insert into public.applied_payments(id, "studentId", amount, "createdAt")
        values ('refund:' || p_ref, coalesce(v_sid,''), p_amount, now()) on conflict (id) do nothing;
      get diagnostics v_inserted = row_count;
      if v_inserted = 0 then return jsonb_build_object('dup', true, 'ref', p_ref); end if;
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
    if p_ref is not null and p_ref <> '' then
      insert into public.applied_payments(id, "studentId", amount, "createdAt")
        values ('refund:' || p_ref, '', p_amount, now()) on conflict (id) do nothing;
      get diagnostics v_inserted = row_count;
      if v_inserted = 0 then return jsonb_build_object('dup', true, 'ref', p_ref); end if;
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
