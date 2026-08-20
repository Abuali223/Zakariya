-- =====================================================================
-- To'lov BALANS/QARZDORLIK modeli (erkin Click to'lovlari uchun).
-- Idempotent. Docker orqali:
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/payments-balance.sql
--
-- Model:
--  * invoices."paidAmount" — shu hisob-fakturaga to'langan summa (qisman to'lov).
--    status: 'pending' (0) | 'partial' (0<paid<amount) | 'paid' (>=amount) | canceled | reversed.
--    qarzdorlik = amount - paidAmount (pending/partial uchun).
--  * student_credit — ORTIQCHA to'lov (avans): keyingi to'lov/oyga o'tadi.
--  * applied_payments — idempotentlik: bir tranzaksiya ikki marta hisoblanmasin.
-- =====================================================================

-- 1) Qisman to'lov ustuni
alter table invoices add column if not exists "paidAmount" numeric default 0;

-- 2) Ortiqcha to'lov (avans) — o'quvchi krediti
create table if not exists student_credit(
  id text primary key,                 -- = studentId
  "studentId" text,
  credit numeric default 0,
  "updatedAt" timestamptz default now()
);
alter table student_credit enable row level security;
drop policy if exists sc_credit_sel on student_credit;
drop policy if exists sc_credit_ins on student_credit;
drop policy if exists sc_credit_upd on student_credit;
create policy sc_credit_sel on student_credit for select using (app.is_admin() or app.is_zavuch() or app.owns_child(id));
-- Admin qo'lda biriktirganда (client) kreditни yozishi/yangilashi mumkin.
create policy sc_credit_ins on student_credit for insert with check (app.is_admin());
create policy sc_credit_upd on student_credit for update using (app.is_admin()) with check (app.is_admin());
grant select, insert, update on student_credit to authenticated;
grant select on student_credit to anon;
grant all on student_credit to service_role;

-- payments: admin biriktirilmagan to'lovni o'quvchiga QO'LDA biriktirganда yangilaydi (mark applied).
drop policy if exists pay_upd on payments;
create policy pay_upd on payments for update using (app.is_admin()) with check (app.is_admin());
grant select, update on payments to authenticated;

-- 3) Qo'llangan tranzaksiyalar (idempotentlik — ikki marta hisoblamaslik)
create table if not exists applied_payments(
  id text primary key,                 -- = click/uzum tranzaksiya id
  "studentId" text,
  amount numeric,
  result jsonb,
  "createdAt" timestamptz default now()
);
alter table applied_payments enable row level security;
drop policy if exists ap_sel on applied_payments;
create policy ap_sel on applied_payments for select using (app.is_admin());
grant all on applied_payments to service_role;

-- 4) Erkin to'lovni admin ko'rishi uchun payments'ga qo'shimcha maydonlar
--    (biriktirilmagan to'lovlar ro'yxati uchun). raw jsonb'da qolganlari.
alter table payments add column if not exists "payerName"  text;
alter table payments add column if not exists "payerPhone" text;
alter table payments add column if not exists "payerClass" text;
alter table payments add column if not exists matched boolean;

notify pgrst, 'reload schema';
