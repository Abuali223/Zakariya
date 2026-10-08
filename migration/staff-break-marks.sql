-- =====================================================================
-- staff_break_marks — ish vaqtidagi tanaffusni «SABABLI» deb belgilash (bitta tugma).
--   Xodim ish vaqtida chiqib-kirsa, davomat jarimasiga (oshiqcha tanaffus) tushadi.
--   Ma'muriyat/HR bu kunni «sababli» deb belgilasa — o'sha kunning tanaffus jarimasi
--   O'TKAZIB YUBORILADI (oylik kesilmaydi). Belgilanmasa — «o'z hisobidan» (kesiladi).
--   Bitta (xodim, kun) = bitta yozuv; mavjudligi = sababli. Toggle: qo'shish/o'chirish.
-- Idempotent. run-all.sql + deploy.sh'da (staff-leaves.sql kabi).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/staff-break-marks.sql
-- =====================================================================

create table if not exists public.staff_break_marks (
  id          text primary key,              -- '{refType}_{refId}_{YYYY-MM-DD}'
  "refId"     text,
  "refType"   text,                          -- 'staff' | 'teacher'
  "cameraId"  text,
  name        text,
  day         text,                          -- 'YYYY-MM-DD'
  "createdBy" text,
  "createdAt" timestamptz default now()
);
create index if not exists sbm_ref_idx on public.staff_break_marks("refType","refId");
create index if not exists sbm_day_idx on public.staff_break_marks(day);

alter table public.staff_break_marks enable row level security;
grant select, insert, update, delete on public.staff_break_marks to authenticated;
grant all on public.staff_break_marks to service_role;

-- O'qiydi: Ma'muriyat/HR + moliya/kassir (maosh hisobida kerak).
drop policy if exists sbm_sel on public.staff_break_marks;
create policy sbm_sel on public.staff_break_marks for select
  using (app.is_admin() or app.is_hr() or app.is_finance() or app.is_cashier());
-- Belgilaydi/o'chiradi: faqat Ma'muriyat/HR (davomatni boshqaruvchilar).
drop policy if exists sbm_ins on public.staff_break_marks;
create policy sbm_ins on public.staff_break_marks for insert with check (app.is_admin() or app.is_hr());
drop policy if exists sbm_upd on public.staff_break_marks;
create policy sbm_upd on public.staff_break_marks for update using (app.is_admin() or app.is_hr()) with check (app.is_admin() or app.is_hr());
drop policy if exists sbm_del on public.staff_break_marks;
create policy sbm_del on public.staff_break_marks for delete using (app.is_admin() or app.is_hr());

notify pgrst, 'reload schema';
