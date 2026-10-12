-- =====================================================================
-- MAOSH QOLDIG'I (carry-over) + o'rinbosarlik — salary_payments ustunlari.
--   Alohida fayl: RLS policy tartibini (audit-3 cashier) BUZMAYDI — faqat
--   idempotent ALTER (add column if not exists). run-all + deploy.sh'da
--   audit-3.sql'DAN KEYIN ishlaydi.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/salary-carryover.sql
--
-- Maqsad: xodimga HAQIQATDA berilgan summa (paid) hisoblangan oylikdan (net)
--   kam bo'lsa — qoldiq KELASI OYLARGA to'planib boradi.
--   subBonus — o'rinbosarlik (kelmagan o'qituvchi o'rniga dars o'tib berilgani).
--   QOLDIQ formulasi (kod, admin.html): balans = Σ(net + subBonus − coalesce(paid, net+subBonus)).
--   Eski yozuvlarda paid=NULL -> to'liq to'langan deb qaraladi (qoldiq 0, orqaga moslik).
-- =====================================================================

alter table public.salary_payments add column if not exists deduction  numeric;   -- davomat ushlanmasi (chek/ma'lumot)
alter table public.salary_payments add column if not exists "subBonus" numeric;    -- o'rinbosarlik (dars o'tib berib qo'shilgan)
alter table public.salary_payments add column if not exists paid       numeric;    -- HAQIQATDA naqd berilgan summa
alter table public.salary_payments add column if not exists "carryIn"  numeric;    -- payout vaqtida oldingi qoldiq (ma'lumot)
alter table public.salary_payments add column if not exists "carryOut" numeric;    -- payoutdan keyingi qoldiq (ma'lumot)

notify pgrst, 'reload schema';
