-- =====================================================================
-- KANONIK TO'LIQ BAZA QURILISHI (yangi/toza Supabase uchun).
-- Barcha migratsiyalarni TO'G'RI TARTIBDA ishlatadi — schema.sql yolg'iz
-- CHALA baza beradi (feature ustunlari alohida fayllarda). Idempotent.
--
-- Ishlatish (migration papkasidan):
--   cd ~/iqror-repo/migration
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < run-all.sql
-- (\ir = shu fayl joylashgan papkaga nisbatan ulaydi.)
-- =====================================================================
\ir schema.sql
\ir supabase-grants.sql
\ir rls.sql
\ir storage-rls.sql
\ir security-2a.sql
\ir security-2b.sql
\ir security-2c.sql
\ir security-2d.sql
\ir payments-balance.sql
\ir expenses-setup.sql
\ir marketing-setup.sql
\ir discounts.sql
\ir roles.sql
\ir fix-teachers-cameraid.sql
\ir audit-fixes.sql
\ir staff-access.sql
\ir teacher-salary.sql
\ir staff-advances.sql
\ir credit-ledger.sql
\ir manual-payments.sql
\echo '✅ To''liq baza qurildi (barcha migratsiyalar qo''llandi).'
