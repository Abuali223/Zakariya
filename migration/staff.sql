-- =====================================================================
-- XODIMLAR (staff) — o'qituvchi BO'LMAGAN, maosh oladigan xodimlar.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/staff.sql
--
-- Qorovul, oshpaz, tozalovchi, g'aznachi va h.k. «Maosh berish» / «Xodim avansi» /
-- «Oylik maoshni yozish» da o'qituvchilar bilan BIRGA ro'yxatga tushadi.
-- Boshqaradi: Direktor + HR. O'qiydi: + Moliya (payroll). Idempotent.
-- =====================================================================
create table if not exists public.staff (
  id           text primary key default gen_random_uuid()::text,
  "staffId"    text,
  name         text,
  position     text,                            -- lavozim
  phone        text,
  salary       text,                            -- oylik maosh (matn: "3 000 000" — salaryNum o'qiydi)
  note         text,
  "order"      numeric,
  "createdAt"  timestamptz default now(),
  "updatedAt"  timestamptz
);
create index if not exists staff_order_idx on public.staff("order");

alter table public.staff enable row level security;
grant select, insert, update, delete on public.staff to authenticated;
grant select, insert, update, delete on public.staff to service_role;

drop policy if exists staff_sel on public.staff;
create policy staff_sel on public.staff for select using (app.is_admin() or app.is_hr() or app.is_finance());
drop policy if exists staff_ins on public.staff;
create policy staff_ins on public.staff for insert with check (app.is_admin() or app.is_hr());
drop policy if exists staff_upd on public.staff;
create policy staff_upd on public.staff for update using (app.is_admin() or app.is_hr()) with check (app.is_admin() or app.is_hr());
drop policy if exists staff_del on public.staff;
create policy staff_del on public.staff for delete using (app.is_admin() or app.is_hr());

notify pgrst, 'reload schema';
