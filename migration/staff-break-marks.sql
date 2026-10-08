-- =====================================================================
-- staff_break_marks — ish vaqtidagi chiqib-kelishni belgilash (ikki tugma).
--   Xodim/o'qituvchi ish vaqtida chiqib-kiradi. Ma'muriyat/HR kunlik davomatda
--   har xodim qatorida bitta qaror qiladi:
--     • «Sababli»  (type='excused')  -> o'sha kun tanaffus jarimasi YO'Q (oylik kesilmaydi).
--     • «O'z hisobidan» (type='personal', awayMin=qo'lda kiritilgan daqiqa) ->
--        o'sha vaqt oylikdan kesiladi: (awayMin/60 × «tanaffus jarimasi soatiga», Narx jadvali).
--   Belgilanmasa -> kamera aniqlagan oshiqcha tanaffus bo'yicha (eski xatti-harakat).
--   Bitta (xodim, kun) = bitta yozuv. Tugma: qo'shish/o'zgartirish/o'chirish.
--   ORQAGA MOSLIK: eski yozuvlar (type yo'q) -> 'excused' (sababli) deb qaraladi.
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
  type        text default 'excused',        -- 'excused' (sababli) | 'personal' (o'z hisobidan)
  "awayMin"   integer default 0,             -- 'personal' uchun: ish vaqtidan tashqarida bo'lgan daqiqa
  "createdBy" text,
  "createdAt" timestamptz default now()
);
-- Mavjud bazaga ustunlar (idempotent). Eski yozuvlarda type bo'sh -> 'excused' deb qaraladi (frontend).
alter table public.staff_break_marks add column if not exists type      text default 'excused';
alter table public.staff_break_marks add column if not exists "awayMin" integer default 0;
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
