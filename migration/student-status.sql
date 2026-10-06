-- =====================================================================
-- O'QUVCHI HAYOT-SIKL HOLATI + PRORATA SANALARI (billing).
--   Faol / Sinov (to'lovsiz) / Muzlatilgan / Chiqdi + faollashtirish/to'xtatish
--   sanalari -> oy o'rtasida kelgan/ketgan uchun prorata (ish kunlari) hisoblanadi.
--   admin.html formasi bu maydonlarni yozadi; ustunlar bo'lmasa POST 400 beradi.
-- Idempotent. run-all.sql + deploy.sh'da.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/student-status.sql
-- =====================================================================

alter table public.students add column if not exists "payStatus"  text;   -- '' | faol | sinov | muzlatilgan | chiqdi
alter table public.students add column if not exists "activeFrom" text;    -- 'YYYY-MM-DD' faollashtirish sanasi
alter table public.students add column if not exists "stopFrom"   text;    -- 'YYYY-MM-DD' to'xtatish/chiqish sanasi

notify pgrst, 'reload schema';
