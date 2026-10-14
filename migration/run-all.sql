-- =====================================================================
-- KANONIK TO'LIQ BAZA ZANJIRI — YAGONA MANBA (toza o'rnatish HAM har bir deploy).
-- Barcha migratsiyalar TO'G'RI TARTIBDA (bog'liqlik: funksiya avval ta'riflanib, keyin ishlatiladi).
--
--   * deploy.sh SHU ro'yxatni (\ir qatorlarini) o'qib, butun zanjirni BITTA tranzaksiyada qo'llaydi —
--     prod holati = toza o'rnatish holati (drift yo'q). YANGI migratsiya qo'shish: faqat shu yerga \ir.
--   * Har bir fayl IDEMPOTENT va ma'lumot uchun XAVFSIZ bo'lishi SHART: qayta ishga tushirilganda xato
--     bermaydi va mavjud ma'lumotni o'zgartirmaydi (policy: drop if exists + create; ustun: add column
--     if not exists; funksiya: create or replace; bir martalik ma'lumot ko'chirish — guard bilan).
--   * Tekshiruv: migration/verify-db.sh (vaqtinchalik bazada shu zanjirni quradi va jonli bazaga
--     solishtiradi; deploy oxirida avtomatik).
--
-- Qo'lda ishlatish (odatda SHART EMAS — deploy.sh o'zi qiladi):
--   bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q
--   (DIQQAT: `docker exec -i ... psql < run-all.sql` ISHLAMAYDI — \ir konteyner ichida fayl qidiradi.
--    Konteynersiz, shu papkadan to'g'ridan-to'g'ri psql bilan: psql -f run-all.sql — ishlaydi.)
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
\ir roles-rbac.sql
\ir feedback.sql
\ir teacher-ratings.sql
\ir sick-panel.sql
\ir exams.sql
\ir olympiads.sql
\ir sms-log.sql
\ir audit-2.sql
\ir cashier-role.sql
\ir refunds.sql
\ir salary-payments.sql
\ir staff.sql
\ir audit-3.sql
\ir audit-4.sql
\ir audit-5.sql
\ir audit-6.sql
\ir bus.sql
\ir audit-7.sql
\ir reattribute-avans.sql
\ir audit-8.sql
\ir pay-notes.sql
\ir reverse-payment.sql
\ir audit-9.sql
\ir refund-rpc.sql
\ir adjust-credit.sql
\ir add-credit.sql
\ir reception-access.sql
\ir split-payment.sql
\ir staff-attendance.sql
\ir staff-leaves.sql
\ir student-status.sql
\ir staff-status.sql
\ir staff-workhours.sql
\ir staff-break-marks.sql
\ir staff-substitutions.sql
\ir salary-carryover.sql
\ir reception-guard.sql
\ir applications-guard.sql
\ir auth-phone.sql
\ir otp-codes.sql
\ir auth-login-attempts.sql
\ir parent-student-links.sql
\ir auth-hardening.sql
\ir staff-user-link.sql
\ir student-arrivals.sql
\ir secdef-searchpath.sql
\echo '✅ To''liq baza qurildi (barcha migratsiyalar qo''llandi).'
