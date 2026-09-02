-- =====================================================================
-- KASSIR ROLI (kassir) — FAQAT to'lov qabul qiladi.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/cashier-role.sql
--
-- Kassir: o'quvchini topib to'lov qabul qiladi (invoices/payments/student_credit/
-- applied_payments). MAOSH, XARAJAT, moliya HISOBOTLARI, narx jadvali — YO'Q.
-- run-all.sql da staff-access.sql/manual-payments.sql DAN KEYIN ishlashi shart
-- (shu policilar ustiga is_cashier qo'shadi). Idempotent.
-- =====================================================================
create or replace function app.is_cashier() returns boolean language sql stable security definer as $$
  select coalesce((select role from public.users where id = app.uid()) = 'kassir', false);
$$;

-- students: o'quvchini topib to'lov qabul qilish uchun o'qiydi (PII emas — students jadvali)
drop policy if exists students_sel on students;
create policy students_sel on students for select using (app.is_staff() or app.is_cashier() or app.owns_child(id));

-- invoices: qarzni ko'rish (sel) + to'lovni belgilash (upd: paidAmount/status)
drop policy if exists inv_sel on invoices;
create policy inv_sel on invoices for select
  using (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_marketing() or app.is_cashier() or app.owns_child("studentId"));
drop policy if exists inv_upd on invoices;
create policy inv_upd on invoices for update using (app.is_admin() or app.is_finance() or app.is_cashier()) with check (app.is_admin() or app.is_finance() or app.is_cashier());

-- payments: to'lovni yozish/o'qish/biriktirish
drop policy if exists pay_sel on payments;
create policy pay_sel on payments for select using (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists pay_ins on payments;
create policy pay_ins on payments for insert with check (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists pay_upd on payments;
create policy pay_upd on payments for update using (app.is_admin() or app.is_finance() or app.is_cashier()) with check (app.is_admin() or app.is_finance() or app.is_cashier());

-- student_credit: avans yozish/o'qish (to'lov biriktirishda)
drop policy if exists sc_credit_sel on student_credit;
create policy sc_credit_sel on student_credit for select
  using (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_cashier() or app.owns_child(id));
drop policy if exists sc_credit_ins on student_credit;
create policy sc_credit_ins on student_credit for insert with check (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists sc_credit_upd on student_credit;
create policy sc_credit_upd on student_credit for update using (app.is_admin() or app.is_finance() or app.is_cashier()) with check (app.is_admin() or app.is_finance() or app.is_cashier());

-- applied_payments: klient idempotentlik posboni
drop policy if exists ap_sel on applied_payments;
create policy ap_sel on applied_payments for select using (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists ap_ins on applied_payments;
create policy ap_ins on applied_payments for insert with check (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists ap_del on applied_payments;
create policy ap_del on applied_payments for delete using (app.is_admin() or app.is_finance() or app.is_cashier());

notify pgrst, 'reload schema';
