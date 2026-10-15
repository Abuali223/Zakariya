\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: staff-workhours.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- XODIM/O'QITUVCHI SHAXSIY ISH VAQTI (davomat jarimasi uchun).
--   workStart/workEnd — 'HH:MM' (masalan '08:00'/'17:00'). Bo'sh bo'lsa UMUMIY standart
--     (SA_RULES: 08:00–17:00) qo'llanadi.
--   workDays — ish kunlari, hafta kunlari raqamlari vergul bilan (JS getDay: Yakshanba=0 …
--     Shanba=6). Masalan '1,2,3,4,5' = Dush–Juma. Bo'sh bo'lsa standart (Dush–Juma).
--   Davomat (kechikish/erta ketish/yo'qlama) SHU shaxsiy vaqt/kunlar bo'yicha hisoblanadi;
--     maosh kunlik stavkasi ham shaxsiy ish kunlariga bo'linadi.
-- Idempotent. run-all.sql + deploy.sh'da.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

alter table public.teachers add column if not exists "workStart" text;   -- 'HH:MM' | '' (standart)
alter table public.teachers add column if not exists "workEnd"   text;   -- 'HH:MM' | ''
alter table public.teachers add column if not exists "workDays"  text;   -- '1,2,3,4,5' | '' (standart Dush–Juma)

alter table public.staff    add column if not exists "workStart" text;
alter table public.staff    add column if not exists "workEnd"   text;
alter table public.staff    add column if not exists "workDays"  text;

-- ERKIN ISH SOATI (direktor va aniq jadvali yo'q xodimlar uchun).
--   '1' = erkin -> davomat (kech kelish / erta ketish / yo'qlama) AVTOMATIK kesilmaydi
--     (maktab ishi bilan kech kelsa/uzoq qolsa jarima yo'q). Faqat ma'muriyat qo'lda
--     «O'z hisobidan» belgilasa — o'sha daqiqa soatbay kesiladi. '' | null = oddiy (jadvalli).
alter table public.teachers add column if not exists "flexibleHours" text;
alter table public.staff    add column if not exists "flexibleHours" text;

notify pgrst, 'reload schema';
