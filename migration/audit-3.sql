-- =====================================================================
-- AUDIT-3 — jonli ishga tushirish oldidan audit tuzatmalari (2026-09).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/audit-3.sql
-- Idempotent.
-- =====================================================================

-- 1) [P0] config.refundPin — refund PIN saqlanadigan ustun YO'Q edi -> setDoc PGRST204
--    beruvchi -> PIN hech qachon saqlanmasди -> refund PINSIZ o'tardi (himoya o'chiq).
alter table public.config add column if not exists "refundPin" text;

-- 2) [P1] teacher_ratings — "ballot-stuffing": tr_ins/upd faqat uid'ни tekshirardi,
--    id (= uid__teacherId) ни emas -> bir foydalanuvchi turli id bilan cheksiz ovoz
--    kiritib reytingни shishirardi. Endi id MAJBURAN uid__teacherId (PK -> 1 ovoz).
drop policy if exists tr_ins on public.teacher_ratings;
create policy tr_ins on public.teacher_ratings for insert
  with check (uid = app.uid() and id = uid || '__' || "teacherId");
drop policy if exists tr_upd on public.teacher_ratings;
create policy tr_upd on public.teacher_ratings for update
  using (uid = app.uid() and id = uid || '__' || "teacherId")
  with check (uid = app.uid() and id = uid || '__' || "teacherId");

-- 3) [P1] teachers xom jadvali (baseSalary/salary/salaryBonus/phone/cameraId) barcha
--    xodimga (is_staff: teacher/kurator/reception/marketing ham) ochiq edi -> oddiy
--    o'qituvchи hamkasb MAOSHI/telefoni/cameraId'ini o'qiy olardi. Endi faqat
--    admin/HR/moliya/zavuch. Qolgan xodim/anon -> teachers_public (maoshsiz KO'RINISH).
--    (Panelда 'teachers' faqat renderDashboard[director]/loadPayees[hr,finance]/
--     populateDynselects[admin,zavuch] da o'qiladi — barchasi shu ro'yxatда, try/catch bilan.)
drop policy if exists teachers_sel on public.teachers;
create policy teachers_sel on public.teachers for select
  using (app.is_admin() or app.is_hr() or app.is_finance() or app.is_zavuch());

notify pgrst, 'reload schema';
