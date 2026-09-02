-- =====================================================================
-- Avtomatik CHEGIRMA/IMTIYOZ dvigateli + sinf NARX JADVALI poydevori.
-- Idempotent. Docker orqali:
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/discounts.sql
--
-- MUHIM: sb shim (sb/firebase-firestore.js) noma'lum ustunga yozganda XATO tashlaydi
-- (prep() filtrlamaydi). Shu sabab har bir yangi maydon uchun REAL USTUN kerak —
-- aks holda yozuv jimgina yo'qoladi (masalan avvalgi LTV config/ltv holati).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) config: LTV + moliya sozlamalari (ilgari ustun yo'q edi -> saqlanmayotgan edi)
--    config/ltv    -> tenureYears, monthsPerYear   (LTV persist tuzatildi)
--    config/finance-> "sickRate" (kasal kun stavkasi, default 40000), "flatAmount" (zaxira narx)
-- ---------------------------------------------------------------------
alter table config add column if not exists "tenureYears"   numeric;
alter table config add column if not exists "monthsPerYear" numeric;
alter table config add column if not exists "sickRate"      numeric;
alter table config add column if not exists "flatAmount"    numeric;

-- ---------------------------------------------------------------------
-- 2) student_private: chegirma/imtiyoz maydonlari (MAXFIY — PII bilan birga)
--    specialCategory: '' | 'teacher_child' | 'olympiad' | 'contract'  (eksklyuziv)
--    teacherId:       teacher_child bo'lganda qaysi o'qituvchi (IQT-...)
--    contractAmount:  contract bo'lganda belgilangan oylik summa
--    siblingDiscount: '' | 'Ha'  (aka-uka 10% ni shu farzandga qo'lda tayinlash)
--    referrerId:      shu o'quvchini kim tavsiya qilgan (referrer studentId) — 300k referrerga
--    hearAbout:       bizni qayerdan eshitdingiz (marketing manbasi / referralni aniqlash)
-- ---------------------------------------------------------------------
alter table student_private add column if not exists "specialCategory" text;
alter table student_private add column if not exists "teacherId"       text;
alter table student_private add column if not exists "contractAmount"  numeric;
alter table student_private add column if not exists "siblingDiscount" text;
alter table student_private add column if not exists "referrerId"      text;
alter table student_private add column if not exists "hearAbout"       text;

-- ---------------------------------------------------------------------
-- 3) invoices: chegirma shaffofligi (moliya tahlili net "amount"dan ishlaydi)
--    baseAmount:      chegirmadan oldingi to'liq narx
--    discount:        umumiy chegirma (base - net)
--    discountInfo:    izoh ("O'qituvchi farzandi 50%" / "Monitoring 20% + 2 kasal kun")
--    isGrant:         100% grant (olimpiada) -> amount 0
--    pctApplied:      qo'llangan foiz (0 / 0.10 / 0.20 / 0.50)
--    sickDaysApplied: hisobga olingan kasal kun soni
--    sickAmount:      kasal chegirmasi so'm
--    priceKey:        narx jadvali kaliti (lang-grade-track)
-- ---------------------------------------------------------------------
alter table invoices add column if not exists "baseAmount"      numeric;
alter table invoices add column if not exists "discount"        numeric;
alter table invoices add column if not exists "discountInfo"    text;
alter table invoices add column if not exists "isGrant"         boolean;
alter table invoices add column if not exists "pctApplied"      numeric;
alter table invoices add column if not exists "sickDaysApplied" integer;
alter table invoices add column if not exists "sickAmount"      numeric;
alter table invoices add column if not exists "priceKey"        text;

-- ---------------------------------------------------------------------
-- 4) price_table: sinf/yo'nalish/til bo'yicha oylik narx (numeric)
--    id = "${lang}-${grade}-${track||'-'}"   (masalan: uz-5-IT, uz-0--, ru-9-MED)
--    Chegirma shu asosiy narxdan hisoblanadi. Admin yil boshida to'ldiradi.
-- ---------------------------------------------------------------------
create table if not exists price_table (
  id         text primary key,
  grade      integer,
  track      text,
  lang       text,
  amount     numeric,
  "order"    numeric,
  "updatedAt" timestamptz default now()
);
alter table price_table enable row level security;
drop policy if exists pt_sel on price_table;
drop policy if exists pt_ins on price_table;
drop policy if exists pt_upd on price_table;
drop policy if exists pt_del on price_table;
create policy pt_sel on price_table for select using (app.is_admin() or app.is_zavuch());
create policy pt_ins on price_table for insert with check (app.is_admin());
create policy pt_upd on price_table for update using (app.is_admin()) with check (app.is_admin());
create policy pt_del on price_table for delete using (app.is_admin());
grant select, insert, update, delete on price_table to authenticated;
grant all on price_table to service_role;

-- ---------------------------------------------------------------------
-- 5) referral_ledger: referral 300k idempotentligi + audit
--    id = yangi (olib kelingan) studentId  -> har referral bir marta hisoblanadi
-- ---------------------------------------------------------------------
create table if not exists referral_ledger (
  id           text primary key,        -- = yangi o'quvchi (referred) studentId
  "referrerId" text,                     -- kim olib keldi (referrer studentId)
  amount       numeric,
  month        text,                     -- chegirma qo'llangan oy (YYYY-MM)
  "appliedAt"  timestamptz default now()
);
alter table referral_ledger add column if not exists month text;
alter table referral_ledger enable row level security;
drop policy if exists rl_sel on referral_ledger;
drop policy if exists rl_ins on referral_ledger;
drop policy if exists rl_upd on referral_ledger;
drop policy if exists rl_del on referral_ledger;
create policy rl_sel on referral_ledger for select using (app.is_admin() or app.is_zavuch());
create policy rl_ins on referral_ledger for insert with check (app.is_admin());
create policy rl_upd on referral_ledger for update using (app.is_admin()) with check (app.is_admin());
create policy rl_del on referral_ledger for delete using (app.is_admin());
grant select, insert, update, delete on referral_ledger to authenticated;
grant all on referral_ledger to service_role;

notify pgrst, 'reload schema';
