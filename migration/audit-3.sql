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
-- MAOSH MAXFIYLIGI: o'qituvchi/xodim oyligi FAQAT direktor/moliya/HR va KASSIR ga ko'rinadi.
-- Boshqalar (o'qituvchi/zavuch/kurator/marketing) ko'ra olmaydi.
-- (salary teachers/staff jadvalidagi USTUN -> butun qatorni shu rollardan tashqarига yopamiz;
--  qolganlar/ommaviy sayt maoshsiz `teachers_public` KO'RINISHINI o'qiydi.)
create or replace function app.can_see_salary() returns boolean language sql stable security definer as $$
  select app.is_admin() or app.is_hr() or app.is_finance() or app.is_cashier();
$$;
drop policy if exists teachers_sel on public.teachers;
create policy teachers_sel on public.teachers for select using (app.can_see_salary());
drop policy if exists staff_sel on public.staff;
create policy staff_sel on public.staff for select using (app.can_see_salary());
drop policy if exists salpay_sel on public.salary_payments;
create policy salpay_sel on public.salary_payments for select using (app.can_see_salary());

-- 4) [P0] Kassir to'lov qabul qilganda 42501/403 berardi. Sabab: shim `setDoc` = Supabase UPSERT
--    (INSERT ... ON CONFLICT) -> Postgres INSERT huquqini ham talab qiladi (faktura mavjud bo'lsa ham,
--    INSERT with-check baholanadi). `inv_ins` kassirni qamramagan edi. Kassir/moliya UPSERT qila olsin.
drop policy if exists inv_ins on invoices;
create policy inv_ins on invoices for insert with check (app.is_admin() or app.is_finance() or app.is_cashier());

-- 5) credit_ledger (avans harakati jurnali) — ilgari faqat admin yozardi -> moliya/kassir to'lovlarida
--    jurnal bo'sh qolardi (applyPaymentClient'da try/catch yutardi). Endi to'lov oluvchilar ham yozadi.
drop policy if exists cl_ins on credit_ledger;
create policy cl_ins on credit_ledger for insert with check (app.is_admin() or app.is_finance() or app.is_cashier());

-- 6) refunds — Buxgalteriyada «Qaytarilgan» summani ko'rsatish uchun moliya/zavuch ham O'QIY oladi
--    (YOZISH — refunds_ins — faqat direktor, o'zgarmaydi).
drop policy if exists refunds_sel on public.refunds;
create policy refunds_sel on public.refunds for select using (app.is_admin() or app.is_finance() or app.is_zavuch());

-- 7) KASSIR barcha KIRIM/CHIQIMni bajaradi: xarajatlar (expenses) TO'LIQ CRUD + maosh berish
--    (salary_payments) + xodim avansi (staff_advances). Kirim (payments/invoices) allaqachon kassirda.
drop policy if exists exp_sel on expenses;
create policy exp_sel on expenses for select using (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_marketing() or app.is_cashier());
drop policy if exists exp_ins on expenses;
create policy exp_ins on expenses for insert with check (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_cashier());
drop policy if exists exp_upd on expenses;
create policy exp_upd on expenses for update using (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_cashier()) with check (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_cashier());
drop policy if exists exp_del on expenses;
create policy exp_del on expenses for delete using (app.is_admin() or app.is_cashier());

drop policy if exists salpay_ins on public.salary_payments;
create policy salpay_ins on public.salary_payments for insert with check (app.is_admin() or app.is_hr() or app.is_finance() or app.is_cashier());
drop policy if exists salpay_del on public.salary_payments;
create policy salpay_del on public.salary_payments for delete using (app.is_admin() or app.is_hr() or app.is_finance() or app.is_cashier());

drop policy if exists sa_sel on staff_advances;
create policy sa_sel on staff_advances for select using (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists sa_ins on staff_advances;
create policy sa_ins on staff_advances for insert with check (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists sa_upd on staff_advances;
create policy sa_upd on staff_advances for update using (app.is_admin() or app.is_finance() or app.is_cashier()) with check (app.is_admin() or app.is_finance() or app.is_cashier());
drop policy if exists sa_del on staff_advances;
create policy sa_del on staff_advances for delete using (app.is_admin() or app.is_finance() or app.is_cashier());

notify pgrst, 'reload schema';
