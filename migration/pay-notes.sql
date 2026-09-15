-- =====================================================================
-- pay_notes — qarzdorga qo'ng'iroq eslatmasi (ichki). Har o'quvchi uchun bitta
--   matn: "qachon to'layman dedi", va'da sanasi va h.k. FAQAT o'quvchi
--   ma'lumotnomasida ko'rinadi; faqat to'lov bilan ishlovchilar (direktor/moliya/
--   kassir) o'qiydi/yozadi. id = studentId (invoices bilan bir xil kalit).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/pay-notes.sql
-- Idempotent.
-- =====================================================================
create table if not exists public.pay_notes(
  id          text primary key,          -- = studentId
  note        text,
  "updatedAt" timestamptz default now(),
  "by"        text
);
alter table public.pay_notes enable row level security;
grant select, insert, update on public.pay_notes to authenticated;
grant all on public.pay_notes to service_role;

drop policy if exists pn_sel on public.pay_notes;
create policy pn_sel on public.pay_notes for select
  using (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists pn_ins on public.pay_notes;
create policy pn_ins on public.pay_notes for insert
  with check (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists pn_upd on public.pay_notes;
create policy pn_upd on public.pay_notes for update
  using (app.is_admin() or app.is_finance() or app.is_cashier())
  with check (app.is_admin() or app.is_finance() or app.is_cashier());

notify pgrst, 'reload schema';
