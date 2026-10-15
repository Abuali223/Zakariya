\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: student-status.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- O'QUVCHI HAYOT-SIKL HOLATI + PRORATA SANALARI (billing).
--   Faol / Sinov (to'lovsiz) / Muzlatilgan / Chiqdi + faollashtirish/to'xtatish
--   sanalari -> oy o'rtasida kelgan/ketgan uchun prorata (ish kunlari) hisoblanadi.
--   admin.html formasi bu maydonlarni yozadi; ustunlar bo'lmasa POST 400 beradi.
-- Idempotent. run-all.sql + deploy.sh'da.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

alter table public.students add column if not exists "payStatus"  text;   -- '' | faol | sinov | muzlatilgan | chiqdi
alter table public.students add column if not exists "activeFrom" text;    -- 'YYYY-MM-DD' faollashtirish sanasi
alter table public.students add column if not exists "stopFrom"   text;    -- 'YYYY-MM-DD' to'xtatish/chiqish sanasi
-- TO'XTATILGAN DAVRLAR tarixi: muzlatish/chiqish -> qaytishda activeFrom (asl boshlanish) SAQLANADI, oradagi kunlar
--   shu yerga yoziladi: [{"from":"YYYY-MM-DD","to":"YYYY-MM-DD"}, ...] (ikkala chekka ham to'lanmaydi). Avval qaytishda
--   activeFrom qaytish kuniga o'zgarib, bir oyda muzlatish->qaytishda muzlatishdan OLDINGI kunlar ham, o'tgan oy
--   qayta hisoblansa butun oy ham tushib qolardi. billingInterval() (admin.html) bu kunlarni prorata'dan chiqaradi.
alter table public.students add column if not exists "pauses" jsonb not null default '[]'::jsonb;

notify pgrst, 'reload schema';
