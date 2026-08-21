-- =====================================================================
-- XODIMLARGA PANEL + PII HIMOYASI (idempotent)
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/staff-access.sql
--
-- 1) PII: xom `students`/`teachers` jadvallari endi ommaga ochiq EMAS
--    (cameraId/telefon/attendance sizmaydi). Ommaviy sayt KO'RINISHlarни o'qiydi.
-- 2) Xodim rollari (Moliya menejeri, G'aznachi, Marketing menejeri) o'z
--    bo'limlarini ko'radi: moliya/buxgalteriya/to'lovlar yoki marketing/lidlar.
-- =====================================================================

-- ---------- Yordamchi rol funksiyalari ----------
-- is_staff: panelga kiradigan ofis/boshqaruv xodimlari (o'quvchi ro'yxatini o'qiy oladi).
-- Qorovul/tozalov/oshxona/xavfsizlik kabi rollar KIRMAYDI (ularga roster kerak emas).
create or replace function app.is_staff() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid()
    and role in ('admin','director','zavuch','kurator','teacher',
                 'hr','admin_head','finance_mgr','treasurer','marketing_mgr','reception'))
$$;
-- is_finance: moliya oqimini (invoyslar/xarajatlar/to'lovlar) ko'radigan rollar.
create or replace function app.is_finance() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid()
    and role in ('admin','director','finance_mgr','treasurer'))
$$;
-- is_marketing: marketing/lead oqimini ko'radigan rollar.
create or replace function app.is_marketing() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid()
    and role in ('admin','director','marketing_mgr'))
$$;

-- ---------- PII: xom students jadvali endi FAQAT xodim yoki O'Z farzandiga ----------
-- Ilgari 'app.uid() is not null' edi -> istalgan tizimга kirgan ota-ona BARCHA
-- o'quvchi PII (cameraId, attendance)ni o'qiy olardi. Ommaviy honor board
-- 'students_public' KO'RINISHINI o'qiydi (cameraId/attendance YO'Q, rls.sql'da).
drop policy if exists students_sel on students;
create policy students_sel on students for select using (app.is_staff() or app.owns_child(id));

-- ---------- PII: teachers xom jadvali (telefon/cameraId) endi FAQAT xodimga ----------
-- Ilgari generik kontent-loop (rls.sql) 'teachers_sel using(true)' — telefon/cameraId
-- anonimga ochiq edi. Ommaviy sayt endi 'teachers_public' KO'RINISHINI o'qiydi.
drop policy if exists teachers_sel on teachers;
create policy teachers_sel on teachers for select using (app.is_staff());

create or replace view public.teachers_public as
  select id, name, photo, "subject_uz", "subject_ru",
         rating, years, certs, avg, votes, "order"
  from public.teachers;
grant select on public.teachers_public to anon, authenticated;
revoke all on public.teachers_public from public;
grant select on public.teachers_public to service_role;

-- ---------- Moliya rollari: invoices / expenses / payments / student_credit / price_table ----------
-- inv_sel: marketing ham LTV/o'rtacha to'lov uchun invoyslarni O'QIYDI (yozmaydi).
drop policy if exists inv_sel on invoices;
create policy inv_sel on invoices for select
  using (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_marketing() or app.owns_child("studentId"));
drop policy if exists inv_ins on invoices;
create policy inv_ins on invoices for insert with check (app.is_admin() or app.is_finance());
drop policy if exists inv_upd on invoices;
create policy inv_upd on invoices for update using (app.is_admin() or app.is_finance()) with check (app.is_admin() or app.is_finance());

-- exp_sel: marketing ham CAC uchun «Marketing» xarajatini O'QIYDI (yozmaydi).
drop policy if exists exp_sel on expenses;
create policy exp_sel on expenses for select using (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_marketing());
drop policy if exists exp_ins on expenses;
create policy exp_ins on expenses for insert with check (app.is_admin() or app.is_zavuch() or app.is_finance());
drop policy if exists exp_upd on expenses;
create policy exp_upd on expenses for update using (app.is_admin() or app.is_zavuch() or app.is_finance()) with check (app.is_admin() or app.is_zavuch() or app.is_finance());

drop policy if exists pay_sel on payments;
create policy pay_sel on payments for select using (app.is_admin() or app.is_finance());
-- To'lovni o'quvchiga biriktirish (matched/studentId/status) — g'aznachi/moliya menejeri ham qila olsin.
-- (Mijoz updateDoc = sof PATCH ishlatadi, INSERT talab qilinmaydi — pay_upd yetarli.)
drop policy if exists pay_upd on payments;
create policy pay_upd on payments for update using (app.is_admin() or app.is_finance()) with check (app.is_admin() or app.is_finance());

drop policy if exists sc_credit_sel on student_credit;
create policy sc_credit_sel on student_credit for select
  using (app.is_admin() or app.is_zavuch() or app.is_finance() or app.owns_child(id));
-- Avans (student_credit) — to'lov biriktirishда yoziladi; moliya rollari ham yoza olsin.
drop policy if exists sc_credit_ins on student_credit;
create policy sc_credit_ins on student_credit for insert with check (app.is_admin() or app.is_finance());
drop policy if exists sc_credit_upd on student_credit;
create policy sc_credit_upd on student_credit for update using (app.is_admin() or app.is_finance()) with check (app.is_admin() or app.is_finance());

drop policy if exists pt_sel on price_table;
create policy pt_sel on price_table for select using (app.is_admin() or app.is_zavuch() or app.is_finance());
drop policy if exists pt_ins on price_table;
create policy pt_ins on price_table for insert with check (app.is_admin() or app.is_finance());
drop policy if exists pt_upd on price_table;
create policy pt_upd on price_table for update using (app.is_admin() or app.is_finance()) with check (app.is_admin() or app.is_finance());

-- ---------- Marketing roli: enrollments (lidlar/voronka) ----------
-- enr_ins (ommaviy lead yuborish) O'ZGARMAYDI — faqat o'qish/boshqarish kengaydi.
drop policy if exists enr_sel on enrollments;
create policy enr_sel on enrollments for select using (app.is_admin() or app.is_marketing());
drop policy if exists enr_upd on enrollments;
create policy enr_upd on enrollments for update using (app.is_admin() or app.is_marketing());

notify pgrst, 'reload schema';
