\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: manual-payments.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- QO'LDA TO'LOV QABUL QILISH (bank / terminal / naqd / click / uzum) — yagona oqim.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
--
-- Barcha usuldagi to'lov BITTA joyga (payments) yoziladi va idempotent qo'llanadi
-- (applied_payments posboni). Admin panelдан yoziladi.
-- =====================================================================

-- payments: admin/moliya qo'lda to'lov yozsin (online — server, offline — admin/g'aznachi).
drop policy if exists pay_ins on payments;
create policy pay_ins on payments for insert with check (app.is_admin() or app.is_finance());
grant insert on payments to authenticated;

-- applied_payments: klient idempotentlik posboni (bir to'lov ikki marta qo'llanmasin).
drop policy if exists ap_sel on applied_payments;
create policy ap_sel on applied_payments for select using (app.is_admin() or app.is_finance());
drop policy if exists ap_ins on applied_payments;
create policy ap_ins on applied_payments for insert with check (app.is_admin() or app.is_finance());
drop policy if exists ap_del on applied_payments;
create policy ap_del on applied_payments for delete using (app.is_admin() or app.is_finance());
grant select, insert, delete on applied_payments to authenticated;

notify pgrst, 'reload schema';
