-- =====================================================================
-- XODIM O'RINBOSARLIGI (staff_substitutions) — kelmagan o'qituvchi o'rniga
--   dars o'tib bergan xodim. Oylik hisobotда «O'rinbosarlik» ustuni:
--   kelmagan o'qituvchining o'sha kungi kunlik maoshi (dailyRate) o'rnini
--   bosgan xodimga QO'SHILADI (o'tmagan odam oyligi — o'tib berganga).
--   Bitta (kelmagan odam, kun) = bitta yozuv.
-- Idempotent. run-all.sql + deploy.sh'da (staff-break-marks.sql kabi).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/staff-substitutions.sql
-- =====================================================================

create table if not exists public.staff_substitutions (
  id              text primary key,            -- '{absentRefType}_{absentRefId}_{YYYY-MM-DD}'
  day             text,                          -- 'YYYY-MM-DD'
  month           text,                          -- 'YYYY-MM' (filtr uchun)
  "absentRefType" text,                          -- 'staff' | 'teacher' (kelmagan)
  "absentRefId"   text,
  "absentCam"     text,
  "absentName"    text,
  "subRefType"    text,                          -- 'staff' | 'teacher' (o'rnini bosgan)
  "subRefId"      text,
  "subCam"        text,
  "subName"       text,
  "createdBy"     text,
  "createdAt"     timestamptz default now()
);
create index if not exists subst_month_idx  on public.staff_substitutions(month);
create index if not exists subst_day_idx    on public.staff_substitutions(day);
create index if not exists subst_sub_idx    on public.staff_substitutions("subRefType","subRefId");
create index if not exists subst_absent_idx on public.staff_substitutions("absentRefType","absentRefId");

alter table public.staff_substitutions enable row level security;
grant select, insert, update, delete on public.staff_substitutions to authenticated;
grant all on public.staff_substitutions to service_role;

-- O'qiydi: Ma'muriyat/HR + moliya/kassir (maosh hisobida kerak — kassir faqat ko'radi).
drop policy if exists subst_sel on public.staff_substitutions;
create policy subst_sel on public.staff_substitutions for select
  using (app.is_admin() or app.is_hr() or app.is_finance() or app.is_cashier());
-- Belgilaydi/o'chiradi: faqat Ma'muriyat/HR (davomatni boshqaruvchilar).
drop policy if exists subst_ins on public.staff_substitutions;
create policy subst_ins on public.staff_substitutions for insert with check (app.is_admin() or app.is_hr());
drop policy if exists subst_upd on public.staff_substitutions;
create policy subst_upd on public.staff_substitutions for update using (app.is_admin() or app.is_hr()) with check (app.is_admin() or app.is_hr());
drop policy if exists subst_del on public.staff_substitutions;
create policy subst_del on public.staff_substitutions for delete using (app.is_admin() or app.is_hr());

notify pgrst, 'reload schema';
