-- =====================================================================
-- AVANS HARAKATI JURNALI (credit_ledger): student_credit balansidagi HAR bir
-- o'zgarishни sababi bilan yozadi — "avans qayerdan keldi / qayerga ketdi".
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/credit-ledger.sql
--
-- delta > 0 -> avans QO'SHILDI (ortiqcha to'lov); delta < 0 -> avans ISHLATILDI
-- (hisob-fakturaga qo'llandi). reason: manba (to'lov ortiqchasi, qayta-hisoblash, qo'llandi).
-- =====================================================================
create table if not exists credit_ledger (
  id            text primary key,
  "studentId"   text,
  "studentName" text,
  delta         numeric,     -- + avans qo'shildi, − avans ishlatildi
  "balanceAfter" numeric,    -- o'zgarishdan keyingi avans balansi
  reason        text,        -- 'overpay' | 'recompute' | 'applied' | 'manual'
  provider      text,        -- click | uzum | cash | credit ...
  month         text,
  note          text,
  "at"          timestamptz default now()
);
create index if not exists credit_ledger_sid on credit_ledger("studentId");
alter table credit_ledger enable row level security;
drop policy if exists cl_sel on credit_ledger;
create policy cl_sel on credit_ledger for select using (app.is_admin() or app.owns_child("studentId"));
drop policy if exists cl_ins on credit_ledger;
create policy cl_ins on credit_ledger for insert with check (app.is_admin());
drop policy if exists cl_del on credit_ledger;
create policy cl_del on credit_ledger for delete using (app.is_admin());
grant select, insert, delete on credit_ledger to authenticated;
grant all on credit_ledger to service_role;

notify pgrst, 'reload schema';
