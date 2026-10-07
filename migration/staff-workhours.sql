-- =====================================================================
-- XODIM/O'QITUVCHI SHAXSIY ISH VAQTI (davomat jarimasi uchun).
--   workStart/workEnd — 'HH:MM' (masalan '08:00'/'17:00'). Bo'sh bo'lsa UMUMIY standart
--     (SA_RULES: 08:00–17:00) qo'llanadi.
--   workDays — ish kunlari, hafta kunlari raqamlari vergul bilan (JS getDay: Yakshanba=0 …
--     Shanba=6). Masalan '1,2,3,4,5' = Dush–Juma. Bo'sh bo'lsa standart (Dush–Juma).
--   Davomat (kechikish/erta ketish/yo'qlama) SHU shaxsiy vaqt/kunlar bo'yicha hisoblanadi;
--     maosh kunlik stavkasi ham shaxsiy ish kunlariga bo'linadi.
-- Idempotent. run-all.sql + deploy.sh'da.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/staff-workhours.sql
-- =====================================================================

alter table public.teachers add column if not exists "workStart" text;   -- 'HH:MM' | '' (standart)
alter table public.teachers add column if not exists "workEnd"   text;   -- 'HH:MM' | ''
alter table public.teachers add column if not exists "workDays"  text;   -- '1,2,3,4,5' | '' (standart Dush–Juma)

alter table public.staff    add column if not exists "workStart" text;
alter table public.staff    add column if not exists "workEnd"   text;
alter table public.staff    add column if not exists "workDays"  text;

notify pgrst, 'reload schema';
