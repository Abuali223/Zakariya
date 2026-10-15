\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: staff-status.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- XODIM/O'QITUVCHI HAYOT-SIKL HOLATI + PRORATA SANALARI (maosh).
--   Faol / Sinov / Muzlatilgan / Chiqdi + faollashtirish(ish boshlagan)/to'xtatish
--   sanalari -> oy o'rtasida ishga kirgan/ketgan uchun MAOSH prorata (ish kunlari).
--   o'quvchilarnikidek, lekin qarz emas — maoshga ta'sir qiladi.
-- Idempotent. run-all.sql + deploy.sh'da.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

alter table public.teachers add column if not exists "payStatus"  text;   -- '' | faol | sinov | muzlatilgan | chiqdi
alter table public.teachers add column if not exists "activeFrom" text;    -- 'YYYY-MM-DD' ishga kirgan / faollashtirish sanasi
alter table public.teachers add column if not exists "stopFrom"   text;    -- 'YYYY-MM-DD' to'xtatish/ketish sanasi

alter table public.staff    add column if not exists "payStatus"  text;
alter table public.staff    add column if not exists "activeFrom" text;
alter table public.staff    add column if not exists "stopFrom"   text;

notify pgrst, 'reload schema';
