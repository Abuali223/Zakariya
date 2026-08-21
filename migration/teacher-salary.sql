-- =====================================================================
-- O'QITUVCHI MAOSHI: asosiy oylik + darajaga qarab avtomatik bonuslar. Idempotent.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/teacher-salary.sql
--
-- Maosh = baseSalary + rus tili + ma'lumot (magistr/PhD) + til sertifikati (A1..C2) + tajriba.
-- Stavkalar config/salary hujjatida (admin panelдан tahrirlanadi).
-- =====================================================================

-- ---- teachers: har o'qituvchi malakasi + hisoblangan maosh ----
alter table teachers add column if not exists "baseSalary"  numeric;   -- asosiy oylik
alter table teachers add column if not exists salary        numeric;   -- JAMI hisoblangan maosh (avtomatik)
alter table teachers add column if not exists "salaryBonus" numeric;   -- bonuslar jami (avtomatik)
alter table teachers add column if not exists degree        text;      -- '', 'bakalavr', 'magistr', 'phd'
alter table teachers add column if not exists category      text;      -- '', '2', '1', 'oliy' (malaka toifasi)
alter table teachers add column if not exists languages     jsonb;     -- ['russian','english'] — bilgan tillari
alter table teachers add column if not exists "otherCerts"  jsonb;     -- [{name,amount}] qo'shimcha sertifikatlar
-- eski (ishlatilmaydigan, saqlab qolinadi): "langLevel", russian
alter table teachers add column if not exists "langLevel"   text;
alter table teachers add column if not exists russian       text;

-- ---- config/salary: bonus stavkalari (barcha o'qituvchilarga umumiy) ----
alter table config add column if not exists "perYear"   numeric;   -- 1 yillik tajriba uchun
alter table config add column if not exists "yearsCap"  numeric;   -- tajriba bonusi cheklovi (yil)
alter table config add column if not exists languages   jsonb;     -- {russian,english} til bonuslari
alter table config add column if not exists degree      jsonb;     -- {bakalavr,magistr,phd}
alter table config add column if not exists category    jsonb;     -- {'2','1','oliy'} malaka toifasi bonuslari
alter table config add column if not exists russian     numeric;   -- eski (ishlatilmaydi)
alter table config add column if not exists "langLevel" jsonb;     -- eski (ishlatilmaydi)

notify pgrst, 'reload schema';
