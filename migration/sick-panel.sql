-- =====================================================================
-- KASAL BOLALAR PANELI — Ma'muriyat rahbari davomatni O'QIYDI («Bemor» ro'yxati).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/sick-panel.sql
--
-- att_sel siyosatiga is_admin_head qo'shiladi (boshqa ruxsatlar saqlanadi).
-- Idempotent.
-- =====================================================================
drop policy if exists att_sel on attendance;
create policy att_sel on attendance for select using (
  app.is_admin() or app.is_admin_head() or app.owns_child("studentId")
  or app.is_kurator_for("classKey") or app.is_homeroom_for("classKey")
);

notify pgrst, 'reload schema';
