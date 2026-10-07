-- =====================================================================
-- XODIM/O'QITUVCHI HAYOT-SIKL HOLATI + PRORATA SANALARI (maosh).
--   Faol / Sinov / Muzlatilgan / Chiqdi + faollashtirish(ish boshlagan)/to'xtatish
--   sanalari -> oy o'rtasida ishga kirgan/ketgan uchun MAOSH prorata (ish kunlari).
--   o'quvchilarnikidek, lekin qarz emas — maoshga ta'sir qiladi.
-- Idempotent. run-all.sql + deploy.sh'da.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/staff-status.sql
-- =====================================================================

alter table public.teachers add column if not exists "payStatus"  text;   -- '' | faol | sinov | muzlatilgan | chiqdi
alter table public.teachers add column if not exists "activeFrom" text;    -- 'YYYY-MM-DD' ishga kirgan / faollashtirish sanasi
alter table public.teachers add column if not exists "stopFrom"   text;    -- 'YYYY-MM-DD' to'xtatish/ketish sanasi

alter table public.staff    add column if not exists "payStatus"  text;
alter table public.staff    add column if not exists "activeFrom" text;
alter table public.staff    add column if not exists "stopFrom"   text;

notify pgrst, 'reload schema';
