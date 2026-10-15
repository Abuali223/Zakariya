\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-5.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-5 — [P0] Webhook to'lovда ikki marta hisoblash tuzatildi.
--   Muammo: payments/index.cjs webhook (Click/Uzum) atomik BO'LMAGAN JS waterfall'ni
--   ishlatardi; qisman yozuvдан keyin xato bo'lsa applied_payments posboni o'chirilib,
--   provayder qayta yuborganда to'lov QAYTA qo'llanardi (fantom daromad).
--   Yechim: aniq-invoysга ATOMIK + IDEMPOTENT qo'llash RPC (apply_payment kabi, lekin
--   student-waterfall EMAS — aynan berilgan invoysга; Uzum/Click aniq oyni to'laydi va
--   uzReverse ham aynan shu invoysни qaytaradi -> semantika saqlanadi).
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

create or replace function public.apply_to_invoice(p_invoice text, p_amount numeric, p_provider text, p_pay_id text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_claims jsonb;
  v_inserted int := 0;
  v_inv record;
  v_sid text;
  v_newpaid numeric;
  v_full boolean;
  v_overflow numeric;
  v_cr numeric := 0;
  v_provider text;
  v_name text;
begin
  -- Ruxsat: to'lov oluvchilar (kassir/moliya/direktor) yoki server (service_role) — apply_payment bilan bir xil.
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance() or app.is_cashier()
          or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  p_amount := coalesce(p_amount, 0);
  if p_amount < 0 then return jsonb_build_object('ok', false, 'reason', 'neg'); end if;
  v_provider := coalesce(nullif(p_provider, ''), 'click');

  -- 1) AVVAL invoysни qulflab o'qib, notfound/terminal holatlarини QAYTARAMIZ — POSBONNI (idempotentlik)
  --    hali OLMASDAN. Aks holda terminal invoysда posbon "yeyilib", chaqiruvchi fallback (o'quvchi
  --    balansiga _cr kalit bilan) ishlashдан oldin jarayon uzilса, qayta urinishда dup bo'lib pul yo'qolardi.
  --    (for update — bir xil invoysга kelgan parallel callbacklar shu yerда seriyalaydi.)
  --    QULF TARTIBI: AVVAL o'quvchi advisory qulfi, KEYIN qator (apply_payment / reprice_invoice bilan BIR XIL).
  --    Avval teskari (qator -> advisory) edi — bir vaqtda kelgan apply_payment / qayta hisoblash bilan o'zaro
  --    qulflanish (40P01) Click/Uzum to'lovini xato bilan uzardi.
  --    paid: ESKI 'paid' yozuvlarda paidAmount 0 bo'lishi mumkin -> to'langan = amount (admin.html paidOf kabi).
  select "studentId" into v_sid from public.invoices where id = p_invoice;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  -- 2) Shu o'quvchi bo'yicha boshqa to'lovlar bilan seriyalash (apply_payment bilan bir xil advisory lock).
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));
  select id, "studentId", coalesce(amount,0) as amount,
         case when status = 'paid' then greatest(coalesce("paidAmount",0), coalesce(amount,0)) else coalesce("paidAmount",0) end as paid, status
    into v_inv from public.invoices where id = p_invoice for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  if coalesce(v_inv."studentId",'') <> coalesce(v_sid,'') then return jsonb_build_object('ok', false, 'error', 'retry'); end if;
  if v_inv.status in ('reversed','canceled') then return jsonb_build_object('ok', false, 'error', 'terminal'); end if;

  -- 3) Idempotentlik posboni (apply_payment BILAN BIR XIL applied_payments jadvali). Tranzaksiya ichida ->
  --    xato bo'lsa u ham rollback bo'ladi (fantom yo'q); dup bo'lsa QAYTA qo'llanmaydi.
  if p_pay_id is not null and p_pay_id <> '' then
    insert into public.applied_payments(id, "studentId", amount, "createdAt")
      values (p_pay_id, v_sid, p_amount, now())
      on conflict (id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted = 0 then return jsonb_build_object('dup', true); end if;
  end if;

  v_newpaid := v_inv.paid + p_amount;
  v_full := v_newpaid >= v_inv.amount - 0.5;
  v_overflow := greatest(0, v_newpaid - v_inv.amount);
  update public.invoices
     set "paidAmount" = case when v_full then v_inv.amount else v_newpaid end,
         status = case when v_full then 'paid' else 'partial' end,
         provider = v_provider,
         "paidAt" = case when v_full then now() else "paidAt" end
   where id = p_invoice;

  -- Ortiqcha (overflow) -> avansga QO'SHAMIZ (apply_payment yakuniy qiymatni yozadi; bu yerda faqat delta).
  if v_overflow > 0 and v_sid is not null and v_sid <> '' then
    select coalesce(credit,0) into v_cr from public.student_credit where id = v_sid for update;
    if not found then v_cr := 0; end if;
    insert into public.student_credit(id, "studentId", credit, "updatedAt")
      values (v_sid, v_sid, v_cr + v_overflow, now())
      on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();
    select name into v_name from public.students where id = v_sid or "studentId" = v_sid limit 1;
    insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, provider, "at")
      values (gen_random_uuid()::text, v_sid, coalesce(v_name,''), v_overflow, v_cr + v_overflow, 'overpay', v_provider, now());
  end if;

  return jsonb_build_object('ok', true, 'status', case when v_full then 'paid' else 'partial' end,
                            'overflow', v_overflow, 'studentId', coalesce(v_sid,''));
end $$;
revoke all on function public.apply_to_invoice(text, numeric, text, text) from public;
grant execute on function public.apply_to_invoice(text, numeric, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
