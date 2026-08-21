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
alter table teachers add column if not exists "langLevel"   text;      -- '', 'A1'..'C2'
alter table teachers add column if not exists russian       text;      -- '', 'ha'
alter table teachers add column if not exists "otherCerts"  jsonb;     -- [{name,amount}] qo'shimcha sertifikatlar

-- ---- config/salary: bonus stavkalari (barcha o'qituvchilarga umumiy) ----
alter table config add column if not exists russian     numeric;   -- rus tili bonusi
alter table config add column if not exists "perYear"   numeric;   -- 1 yillik tajriba uchun
alter table config add column if not exists "yearsCap"  numeric;   -- tajriba bonusi cheklovi (yil)
alter table config add column if not exists degree      jsonb;     -- {bakalavr,magistr,phd}
alter table config add column if not exists "langLevel" jsonb;     -- {A1..C2}

notify pgrst, 'reload schema';
