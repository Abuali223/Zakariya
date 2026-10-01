-- =====================================================================
-- reception (Qabulxona xodimi) — panelga kirish ruxsati.
--   Muammo: 'reception' roli mavjud (tanlab xodim yaratish mumkin, app.is_staff uni tan oladi),
--   lekin panelга kirish HECH sozlanmagan edi -> «…roli uchun panelga kirish hali sozlanmagan» xatosi.
--   Bu bo'lim (frontend: STAFF + ROLE_TABS['reception']=['enrollments','students']) bilan birga ishlaydi.
--
--   Reception QNIMA qiladi: yangi o'quvchi arizalarini (enrollments) O'QIYDI (o'zgartira/o'chira olmaydi)
--   + o'quvchi ro'yxatини ko'radi (students_sel = is_staff — allaqachon) + ota-ona telefonini (arizada
--   qo'ng'iroq qilish uchun). PII (JSHSHIR/passport), to'lov, moliya — YO'Q.
-- Idempotent — QAYTA ishga tushirishга xavfsiz. run-all.sql + deploy.sh'да.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/reception-access.sql
-- =====================================================================

-- Rol yordamchisi.
create or replace function app.is_reception() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role = 'reception')
$$;
grant execute on function app.is_reception() to anon, authenticated, service_role;

-- Arizalar (enrollments): reception O'QIY oladi (SELECT). Yozish (public form) va update/delete
--   (direktor/marketing) O'ZGARMAYDI — faqat o'qish kengaytiriladi.
drop policy if exists enr_sel on public.enrollments;
create policy enr_sel on public.enrollments for select
  using (app.is_admin() or app.is_marketing() or app.is_admin_head() or app.is_reception());

-- Ota-ona telefoni ko'rinishi (student_phones): reception ham ko'rsin (arizadagi/ro'yxatdagi ota-onaга
--   qo'ng'iroq). PII qolgan qismi (JSHSHIR, passport, vasiy) reception uchun YOPIQ (student_private RLS'i
--   reception'ni o'z ichiga olmaydi; bu view faqat telefon ustunlarini beradi).
create or replace view public.student_phones as
  select id, "parentPhone", "parentPhone2"
  from public.student_private
  where app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_cashier() or app.is_reception() or app.owns_child(id);
grant select on public.student_phones to anon, authenticated;
revoke all on public.student_phones from public;
grant select on public.student_phones to service_role;

-- ---- O'QUVCHI KIRITISH + TAHRIRLASH (reception) ----
-- students: reception yangi o'quvchi QO'SHA (INSERT) va TAHRIRLAY (UPDATE) oladi.
--   O'CHIRISH (students_del) O'ZGARMAYDI — direktorда qoladi (reception o'chira olmaydi).
drop policy if exists students_ins on public.students;
create policy students_ins on public.students for insert with check (app.is_admin() or app.is_reception());
drop policy if exists students_upd on public.students;
create policy students_upd on public.students for update using (app.is_admin() or app.is_zavuch() or app.is_reception())
  with check (app.is_admin() or app.is_zavuch() or app.is_reception());

-- student_private (maxfiy: JSHSHIR, metrika/tug'ilganlik guvohnomasi, manzil, ota-ona…): reception
--   O'QIY (hujjatlar bor-yo'qligini ko'rish + tahrirда qayta o'qish) va YOZA (kiritish/tahrir) oladi.
--   O'CHIRISH (priv_del) O'ZGARMAYDI — direktorда.
drop policy if exists priv_sel on public.student_private;
create policy priv_sel on public.student_private for select
  using (app.is_admin() or app.is_zavuch() or app.is_reception() or app.owns_child(id));
drop policy if exists priv_ins on public.student_private;
create policy priv_ins on public.student_private for insert with check (app.is_admin() or app.is_reception());
drop policy if exists priv_upd on public.student_private;
create policy priv_upd on public.student_private for update using (app.is_admin() or app.is_reception())
  with check (app.is_admin() or app.is_reception());

-- student_codes (ota-onaga biriktirish kodi): reception «Kod» ustunini ko'rsin.
drop policy if exists sc_sel on public.student_codes;
create policy sc_sel on public.student_codes for select using (app.is_admin() or app.is_zavuch() or app.is_reception());

-- ---- UNDIRUV (qarzdorlik + eslatma) ----
-- invoices: reception o'quvchi QARZDORLIGINI ko'rsin (O'quvchilar ro'yxatidagi «To'langan/Qarz»
--   ustuni + ma'lumotnoma). FAQAT O'QISH — yozish (ins/upd/del) O'ZGARMAYDI (direktor/moliya).
--   Mavjud rollarni saqlaymiz (admin/zavuch/finance/marketing/cashier/owns_child) + reception.
drop policy if exists inv_sel on public.invoices;
create policy inv_sel on public.invoices for select
  using (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_marketing() or app.is_cashier()
         or app.is_reception() or app.owns_child("studentId"));

-- pay_notes (📞 undiruv eslatmasi): reception qarzdor bilan qo'ng'iroqda eslatma o'qiydi va yozadi.
drop policy if exists pn_sel on public.pay_notes;
create policy pn_sel on public.pay_notes for select
  using (app.is_admin() or app.is_finance() or app.is_cashier() or app.is_reception());
drop policy if exists pn_ins on public.pay_notes;
create policy pn_ins on public.pay_notes for insert
  with check (app.is_admin() or app.is_finance() or app.is_cashier() or app.is_reception());
drop policy if exists pn_upd on public.pay_notes;
create policy pn_upd on public.pay_notes for update
  using (app.is_admin() or app.is_finance() or app.is_cashier() or app.is_reception())
  with check (app.is_admin() or app.is_finance() or app.is_cashier() or app.is_reception());

notify pgrst, 'reload schema';
