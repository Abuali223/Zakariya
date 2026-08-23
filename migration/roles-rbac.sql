-- =====================================================================
-- RBAC 1-PAKET: Superuser = DIREKTOR; 'admin' = Ma'muriyat rahbari (cheklangan).
-- HR + Ma'muriyat rahbari rollarini ulaydi. Idempotent.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/roles-rbac.sql
--
-- ⚠️ OGOHLANTIRISH — ISHGA TUSHIRISHDAN OLDIN O'QING:
--   Bu is_admin()ni FAQAT 'director'ga cheklaydi. Agar sizning login rolingiz
--   hozir 'admin' bo'lsa, avval o'zingizni DIREKTOR qiling, aks holda superuser
--   huquqini yo'qotasiz:
--       update public.users set role='director' where email='SIZNING_LOGIN@email';
--   (yoki: ... where id='SIZNING_UID';)  — keyin login qilib tekshiring.
-- =====================================================================

-- 1) SUPERUSER = faqat DIREKTOR. 'admin' endi ma'muriyat rahbari (cheklangan).
create or replace function app.is_admin() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role = 'director')
$$;

-- 2) Yangi rol guruhlari.
--    is_admin_head: Ma'muriyat rahbari (admin/admin_head) — qabul, arz-shikoyat, kasal bolalar.
--    is_hr: xodim ma'lumoti + oyliklar + sertifikatlar (tahrir).
--    (Direktor har ikkalasiga ham kiradi — superuser hamma joyda o'tadi.)
create or replace function app.is_admin_head() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('director','admin','admin_head'))
$$;
create or replace function app.is_hr() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('director','hr'))
$$;

-- 3) MOLIYA/MARKETING endi 'admin'ni O'Z ICHIGA OLMAYDI — ma'muriyat rahbari
--    moliyaviy/marketing statistikani KO'RMASIN. (Direktor 'director' orqali ko'radi.)
create or replace function app.is_finance() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('director','finance_mgr','treasurer'))
$$;
create or replace function app.is_marketing() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('director','marketing_mgr'))
$$;

-- 4) HR: xodim (teachers) yozuvlarini TAHRIRLAYDI (o'chirish — faqat direktor).
drop policy if exists teachers_ins on teachers;
create policy teachers_ins on teachers for insert with check (app.is_admin() or app.is_hr());
drop policy if exists teachers_upd on teachers;
create policy teachers_upd on teachers for update using (app.is_admin() or app.is_hr()) with check (app.is_admin() or app.is_hr());

-- HR maosh stavkalarini (config/salary) o'qiydi/tahrirlaydi — boshqa config'ga tegmaydi.
drop policy if exists cfg_salary_hr_sel on config;
create policy cfg_salary_hr_sel on config for select using (app.is_hr() and id = 'salary');
drop policy if exists cfg_salary_hr_ins on config;
create policy cfg_salary_hr_ins on config for insert with check (app.is_hr() and id = 'salary');
drop policy if exists cfg_salary_hr_upd on config;
create policy cfg_salary_hr_upd on config for update using (app.is_hr() and id = 'salary') with check (app.is_hr() and id = 'salary');

-- 5) MA'MURIYAT RAHBARI: QABUL (enrollments) — ko'radi va boshqaradi.
--    (Arz-shikoyat va kasal bolalar — keyingi paketlarда qo'shiladi.)
drop policy if exists enr_sel on enrollments;
create policy enr_sel on enrollments for select using (app.is_admin() or app.is_marketing() or app.is_admin_head());
drop policy if exists enr_upd on enrollments;
create policy enr_upd on enrollments for update using (app.is_admin() or app.is_marketing() or app.is_admin_head());

notify pgrst, 'reload schema';
