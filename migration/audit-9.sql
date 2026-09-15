-- =====================================================================
-- AUDIT-9 — [High A] Money-jadvallariga TO'G'RIDAN-TO'G'RI yozishni toraytirish.
--   Muammo: invoices/student_credit/credit_ledger'ga INSERT/UPDATE kassir (kassir)ga ham
--     ochiq edi (cashier-role.sql / audit-3.sql). Kassir esa to'lovни FAQAT apply_payment
--     RPC (SECURITY DEFINER — RLS'ни chetlab o'tadi) orqali yozadi. To'g'ridan-to'g'ri
--     UPDATE ruxsati => buzilган/xato klient invoice.paidAmount yoki student_credit.credit'ni
--     ixtiyoriy o'zgartirib, to'lov yozuvisiz SOXTA "to'langan"/"avans" yaratishi mumkin edi.
--   Yechim: to'g'ridan-to'g'ri yozishni DIREKTOR/MOLIYA bilan cheklaymiz (billing UI —
--     generate/cancel/recalc — ular uchun kerak). Kassir olib tashlanadi. To'lov qabul qilish
--     BUZILMAYDI (apply_payment/apply_to_invoice/reverse_payment/refund_invoice RPC'lar definer).
-- Idempotent — QAYTA ishga tushirishга xavfsiz. run-all.sql + deploy.sh'да.
-- =====================================================================

-- invoices: INSERT/UPDATE -> direktor/moliya (kassir emas). DELETE allaqachon direktor (rls.sql).
drop policy if exists inv_ins on public.invoices;
create policy inv_ins on public.invoices for insert with check (app.is_admin() or app.is_finance());
drop policy if exists inv_upd on public.invoices;
create policy inv_upd on public.invoices for update using (app.is_admin() or app.is_finance()) with check (app.is_admin() or app.is_finance());

-- student_credit (avans): INSERT/UPDATE -> direktor/moliya (kassir emas).
drop policy if exists sc_credit_ins on public.student_credit;
create policy sc_credit_ins on public.student_credit for insert with check (app.is_admin() or app.is_finance());
drop policy if exists sc_credit_upd on public.student_credit;
create policy sc_credit_upd on public.student_credit for update using (app.is_admin() or app.is_finance()) with check (app.is_admin() or app.is_finance());

-- credit_ledger (avans jurnali): INSERT -> direktor/moliya (kassir emas). apply_payment definer yozadi.
drop policy if exists cl_ins on public.credit_ledger;
create policy cl_ins on public.credit_ledger for insert with check (app.is_admin() or app.is_finance());

notify pgrst, 'reload schema';
