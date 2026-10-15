\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: sick-panel.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- KASAL BOLALAR PANELI — Ma'muriyat rahbari davomatni O'QIYDI («Bemor» ro'yxati).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
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
