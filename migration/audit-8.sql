\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: audit-8.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-8 — Moliya audit topilmalari: xavfsiz DB-qatlam mustahkamlashlari.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- Idempotent. run-all.sql'да ENG OXIRIDA.
-- =====================================================================

-- ---------------------------------------------------------------------
-- A) [MUHIM] applied_payments — idempotentlik POSBONI mijozga yopiq bo'lsin.
--    Mijoz (admin.html) bu jadvalни HECH QACHON to'g'ridan yozmaydi — u faqat
--    apply_payment / apply_to_invoice / reattribute_avans RPC (SECURITY DEFINER)
--    orqali yoziladi. manual-payments.sql + cashier-role.sql esa authenticated
--    (admin/moliya/kassir) uchun to'g'ridan INSERT/DELETE ochib qo'ygan edi ->
--    posbonни o'chirib (double-count) yoki zaharlab (haqiqiy to'lov "dup" bo'lib
--    tushmay qoladi -> pul yo'qoladi) manipulyatsiya qilish mumkin edi. Yopamiz.
--    RPC'lar egasi (definer) huquqi bilan yozadi -> ular buzilmaydi.
-- ---------------------------------------------------------------------
revoke insert, update, delete on public.applied_payments from anon, authenticated;
drop policy if exists ap_ins on public.applied_payments;
drop policy if exists ap_del on public.applied_payments;
-- ap_sel (o'qish — admin/moliya/kassir) QOLADI: UI idempotentlik izini ko'rsatadi.

-- ---------------------------------------------------------------------
-- B) DB-darajа backstop: balanslar MANFIY bo'lib ketmasin. Mijoz refund/avans
--    yo'llari (hozircha RPC emas) xato yoki takror bo'lса — DB rad etadi
--    (jim manfiy balans yozilmasin). NOT VALID -> faqat YANGI/o'zgargan qatorlar
--    tekshiriladi; mavjud ma'lumot buzilmaydi, migratsiya xato bermaydi.
--    Yuqori chegara (paidAmount<=amount) QO'YILMAYDI: qayta-hisoblashда narx
--    kamaysa to'langan summа vaqtincha ko'p bo'lishi mumkin (reconcile avansга
--    o'tkazadi) — uni bloklab qo'ymaymiz.
-- ---------------------------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_constraint where conname='inv_paid_nonneg_chk') then
    alter table public.invoices add constraint inv_paid_nonneg_chk
      check ("paidAmount" is null or "paidAmount" >= -0.5) not valid;
  end if;
exception when others then null; end $$;
do $$ begin
  if not exists (select 1 from pg_constraint where conname='sc_credit_nonneg_chk') then
    alter table public.student_credit add constraint sc_credit_nonneg_chk
      check (credit is null or credit >= -0.5) not valid;
  end if;
exception when others then null; end $$;

notify pgrst, 'reload schema';
