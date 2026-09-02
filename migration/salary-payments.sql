-- =====================================================================
-- MAOSH BERISH JURNALI (salary_payments) — har xodimga oylik berilishi + chek.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/salary-payments.sql
--
-- Bu — TO'LOV/PAYOUT jurnali (kim, qaysi oy, qancha naqd oldi) + chek uchun.
-- «Maosh» XARAJATI esa «Oylik maoshni yozish» (expenses/payroll__oy) orqali yoziladi —
-- shu sabab bu jadval xarajatga QO'SHILMAYDI (ikki marta hisoblanmasin).
-- O'qiydi/yozadi: Direktor / HR / Moliya. Idempotent.
-- =====================================================================
create table if not exists public.salary_payments (
  id            text primary key default gen_random_uuid()::text,
  "teacherId"   text,
  "teacherName" text,
  month         text,                          -- qaysi oy uchun (YYYY-MM)
  gross         numeric,                        -- to'liq maosh
  advance       numeric,                        -- shu oyda berilgan avans
  net           numeric,                        -- naqd berilgan qoldiq (gross - advance)
  date          text,
  "byEmail"     text,
  note          text,
  "createdAt"   timestamptz default now()
);
create index if not exists salpay_teacher_idx on public.salary_payments("teacherId");
create index if not exists salpay_month_idx   on public.salary_payments(month);

alter table public.salary_payments enable row level security;
grant select, insert, update, delete on public.salary_payments to authenticated;
grant select, insert, update, delete on public.salary_payments to service_role;

drop policy if exists salpay_sel on public.salary_payments;
create policy salpay_sel on public.salary_payments for select using (app.is_admin() or app.is_hr() or app.is_finance());
drop policy if exists salpay_ins on public.salary_payments;
create policy salpay_ins on public.salary_payments for insert with check (app.is_admin() or app.is_hr() or app.is_finance());
drop policy if exists salpay_del on public.salary_payments;
create policy salpay_del on public.salary_payments for delete using (app.is_admin() or app.is_hr() or app.is_finance());

notify pgrst, 'reload schema';
