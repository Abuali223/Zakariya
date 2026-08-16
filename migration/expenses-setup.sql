-- =====================================================================
-- Iqror Academy — «expenses» (xarajatlar) jadvali — Buxgalteriya bo'limi.
-- Bir marta bazada ishlating (Supabase SQL Editor yoki psql).
-- Idempotent: qayta ishlatsa ham xavfsiz.
--   psql "$PGURL" -f migration/expenses-setup.sql
-- Yoki: Supabase Dashboard → SQL Editor → shu faylni yopishtiring → Run.
-- =====================================================================

-- ---- Jadval (id = tasodifiy UUID; shim addDoc yaratadi) ----
create table if not exists expenses (
  id          text primary key,
  date        text,            -- "YYYY-MM-DD"
  month       text,            -- "YYYY-MM" (oy bo'yicha hisoblash uchun)
  category    text,            -- Oyliklar | Ijara | Kommunal | Soliq | Jihoz / ta'mir | Reklama | Boshqa
  amount      numeric,
  note        text,
  "createdAt" timestamptz default now(),
  "updatedAt" timestamptz default now()
);
create index if not exists idx_exp_month on expenses (month);

-- ---- Grants (RLS baribir cheklaydi; default privileges bo'lsa ortiqcha emas) ----
grant select, insert, update, delete on expenses to anon, authenticated;
grant all on expenses to service_role;

-- ---- RLS — faqat admin/zavuch o'qiydi va yozadi (invoices bilan bir xil) ----
alter table expenses enable row level security;
drop policy if exists exp_sel on expenses;
drop policy if exists exp_ins on expenses;
drop policy if exists exp_upd on expenses;
drop policy if exists exp_del on expenses;
create policy exp_sel on expenses for select using (app.is_admin() or app.is_zavuch());
create policy exp_ins on expenses for insert with check (app.is_admin() or app.is_zavuch());
create policy exp_upd on expenses for update using (app.is_admin() or app.is_zavuch()) with check (app.is_admin() or app.is_zavuch());
create policy exp_del on expenses for delete using (app.is_admin());
