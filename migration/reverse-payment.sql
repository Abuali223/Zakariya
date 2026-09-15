-- =====================================================================
-- AUDIT (High B) — reverse_payment: to'lovni QAYTARISH (Uzum reverse) ATOMIK + IDEMPOTENT.
--   Muammo: payments/index.cjs uzReverse() atomik BO'LMAGAN JS waterfall edi —
--     (1) invoice.paidAmount kamaytirish, (2) student_credit o'qish, (3) student_credit
--     kamaytirish, (4) credit_ledger yozish — 4 alohida yozuv. Oraliqда jarayon uzilса
--     yoki parallel reverse kelsa: invoice ikki marta kamayishi / avans qaytarilmasligi /
--     jurnalsiz qolishi mumkin edi (balans buziladi).
--   Yechim: apply_to_invoice / reattribute_avans kabi — BITTA tranzaksiya, invoice qulfi
--     + advisory lock + p_ref idempotentlik posboni (applied_payments'да 'reverse:'+ref).
-- Idempotent (CREATE OR REPLACE) — QAYTA ishga tushirishга xavfsiz. run-all.sql + deploy.sh'да.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/reverse-payment.sql
-- =====================================================================
create or replace function public.reverse_payment(p_invoice text, p_amount numeric, p_provider text, p_ref text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_claims jsonb;
  v_inv record;
  v_sid text;
  v_from_invoice numeric;
  v_from_credit numeric;
  v_newpaid numeric;
  v_status text;
  v_cr numeric := 0;
  v_name text;
  v_provider text;
  v_inserted int := 0;
begin
  -- Ruxsat: pulни QAYTARISH — sezgir money-move. Faqat direktor/moliya yoki server (Uzum/Click webhook).
  -- Kassir EMAS (kassir faqat to'lov QABUL qiladi, qaytarmaydi).
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance()
          or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  p_amount := coalesce(p_amount, 0);
  if p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'amount<=0'); end if;
  v_provider := coalesce(nullif(p_provider, ''), 'uzum');

  -- 1) Invoysни qulflab o'qib, notfound holatини posbonNI OLMASDAN qaytaramiz
  --    (apply_to_invoice bilan bir xil xavfsiz tartib). for update -> parallel reverse'lar seriyalanadi.
  select id, "studentId", coalesce(amount,0) as amount, coalesce("paidAmount",0) as paid, status
    into v_inv from public.invoices where id = p_invoice for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  v_sid := v_inv."studentId";

  -- 2) O'quvchi bo'yicha boshqa to'lovlar bilan seriyalash (apply_payment/apply_to_invoice bilan bir xil advisory lock).
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));

  -- 3) IDEMPOTENTLIK POSBONI: aynan shu reverse faqat BIR marta pulни harakatlantiradi. Bir xil
  --    p_ref bilan qayta chaqirilса (webhook retry / crash-recovery) -> {dup:true}, invoice/avans
  --    IKKI marta kamaymaydi. applied_payments'da 'reverse:'+ref namespace (apply bilan to'qnashmaydi).
  if p_ref is not null and p_ref <> '' then
    insert into public.applied_payments(id, "studentId", amount, "createdAt")
      values ('reverse:' || p_ref, coalesce(v_sid,''), p_amount, now())
      on conflict (id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted = 0 then return jsonb_build_object('dup', true, 'ref', p_ref); end if;
  end if;

  -- 4) AYNAN shu tranzaksiya summasini ayiramiz (boshqa to'lovlar saqlanadi): paidAmount'dan
  --    min(summa, paid), qolган ortiqcha (avansга o'tган qism) student_credit'dan qaytariladi.
  v_from_invoice := least(p_amount, v_inv.paid);
  v_from_credit  := greatest(0, p_amount - v_from_invoice);
  v_newpaid := greatest(0, v_inv.paid - v_from_invoice);
  v_status  := case when v_newpaid <= 0 then 'reversed'
                    when v_newpaid >= v_inv.amount - 0.5 then 'paid'
                    else 'partial' end;
  update public.invoices
     set "paidAmount" = v_newpaid, status = v_status, "reversedAt" = now()
   where id = p_invoice;

  -- 5) Avansга o'tган ortiqcha qismни qaytarib olamiz (avans manfiy bo'lmaydi: max(0, …)).
  if v_from_credit > 0 and v_sid is not null and v_sid <> '' then
    select coalesce(credit,0) into v_cr from public.student_credit where id = v_sid for update;
    if not found then v_cr := 0; end if;
    insert into public.student_credit(id, "studentId", credit, "updatedAt")
      values (v_sid, v_sid, greatest(0, v_cr - v_from_credit), now())
      on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();
    select name into v_name from public.students where id = v_sid or "studentId" = v_sid limit 1;
    insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, provider, "at")
      values (gen_random_uuid()::text, v_sid, coalesce(v_name,''), -v_from_credit,
              greatest(0, v_cr - v_from_credit), 'reversed', v_provider, now());
  end if;

  return jsonb_build_object('ok', true, 'status', v_status, 'fromInvoice', v_from_invoice,
                            'fromCredit', v_from_credit, 'newPaid', v_newpaid, 'studentId', coalesce(v_sid,''));
end $$;
revoke all on function public.reverse_payment(text, numeric, text, text) from public;
grant execute on function public.reverse_payment(text, numeric, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
