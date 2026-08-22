-- =====================================================================
-- QO'LDA TO'LOV QABUL QILISH (bank / terminal / naqd / click / uzum) — yagona oqim.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/manual-payments.sql
--
-- Barcha usuldagi to'lov BITTA joyga (payments) yoziladi va idempotent qo'llanadi
-- (applied_payments posboni). Admin panelдан yoziladi.
-- =====================================================================

-- payments: admin qo'lda to'lov yozsin (online — server, offline — admin).
drop policy if exists pay_ins on payments;
create policy pay_ins on payments for insert with check (app.is_admin());
grant insert on payments to authenticated;

-- applied_payments: klient idempotentlik posboni (bir to'lov ikki marta qo'llanmasin).
drop policy if exists ap_sel on applied_payments;
create policy ap_sel on applied_payments for select using (app.is_admin());
drop policy if exists ap_ins on applied_payments;
create policy ap_ins on applied_payments for insert with check (app.is_admin());
drop policy if exists ap_del on applied_payments;
create policy ap_del on applied_payments for delete using (app.is_admin());
grant select, insert, delete on applied_payments to authenticated;

notify pgrst, 'reload schema';
