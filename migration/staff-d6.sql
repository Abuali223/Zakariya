\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: staff-d6.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- staff-d6.sql — XODIMLAR UCHUN D6 (direktor qarori, 2026-10-30): «O'quvchi ma'lumoti faqat o'quvchiga, ota-onasiga,
--   dars beruvchi ustozlarga, qabulxona xodimlariga, O'IBDO' va Direktorga ko'rinsin.»
--   * students: director, zavuch (O'IBDO'), reception, egasi (ota-ona / o'quvchi) va O'Z SINFI xodimlari (sinf rahbari,
--     kurator, fan o'qituvchisi — users.homeroomClasses / assignedClasses). Ilgari app.is_staff() (HR, marketing,
--     ma'muriyat, moliya, BARCHA o'qituvchilar) hammasini ko'rardi.
--   * students_billing — kassa va moliya uchun: ism, ID, sinf, holat va sanalar (ball, davomat, rasm, Kamera ID yo'q).
--   * camera_owners: Kamera ID band bo'lsa — o'quvchi ismi faqat D6 rollariga (HR «o'quvchida band» degan belgini ko'radi).
--   * staff_checkins: HR / moliya / kassa — faqat o'qituvchi va xodim skanlari (o'quvchi kelish vaqtlari emas).
--   * invoices: marketing olib tashlandi (Marketing bo'limi o'rtacha to'lovni marketing_fee_stats() dan oladi).
--   * attendance: ma'muriyat rahbari olib tashlandi («Kasal bolalar» — hamshira paketida), O'IBDO' qo'shildi.
--   * olympiads: barcha xodim emas — director, O'IBDO', qabulxona, shu sinf xodimi, egasi.
--   * change_log: ota-ona telefonlari o'zgarishi (qiymati yashirin) — aka-uka 10% va Telegram tekshiruvi uchun.
--   Umumiy rol asosi (keyingi tasdiq oqimlari uchun): app.my_role(), app.has_role(text), app.approval_actor().
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Umumiy rol asosi: aniq rol + FAOL holat (ikki kishilik tasdiqlar shu bilan tekshiriladi).
create or replace function app.my_role() returns text
language sql stable security definer set search_path = public, app, pg_temp as $$
  select u.role from public.users u where u.id = app.uid() and coalesce(nullif(u.status, ''), 'active') = 'active'
$$;
create or replace function app.has_role(p_role text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(app.my_role() = p_role, false)
$$;
create or replace function app.approval_actor() returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select jsonb_build_object('uid', u.id, 'role', u.role, 'name', coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), u.phone))
    from public.users u where u.id = app.uid()
$$;
revoke all on function app.my_role(), app.has_role(text), app.approval_actor() from public, anon;
grant execute on function app.my_role(), app.has_role(text), app.approval_actor() to authenticated, service_role;

-- 1b) ESKI usulda bloklangan hisoblar (status 'blocked', rol SAQLANGAN — user-block.sql'dan oldin) to'liq bloklanadi:
--     rol "blockedRole"ga o'tadi (blokdan chiqarilganda qaytadi). Sabab: quyidagi students_sel endi is_staff() (status
--     tekshiradi) emas, is_admin()/is_zavuch()/is_reception() (status tekshirmaydi) bilan. Bir martalik, qayta ishga xavfsiz.
update public.users
   set "blockedRole" = coalesce(nullif(role, ''), nullif("blockedRole", '')), role = null
 where coalesce(status, '') = 'blocked' and coalesce(role, '') <> '';

-- 2) Sinf kaliti — admin.html classKeyOf bilan AYNAN bir xil: ${lang||'uz'}-${Number(grade)||0}-${classLetter||track||'-'}
create or replace function app.student_class_key(p_lang text, p_grade int, p_letter text, p_track text) returns text
language sql immutable as $$
  select coalesce(nullif(p_lang, ''), 'uz') || '-' || coalesce(p_grade, 0)::text || '-' || coalesce(nullif(p_letter, ''), nullif(p_track, ''), '-')
$$;

-- 3) O'quvchilar ro'yxati
drop policy if exists students_sel on public.students;
create policy students_sel on public.students for select using (
  app.is_admin() or app.is_zavuch() or app.is_reception() or app.owns_student_doc(id)
  or app.is_class_staff(app.student_class_key(lang, grade, "classLetter", track))
);

-- 4) Kassa va moliya uchun cheklangan ko'rinish (egasi huquqida; WHERE — kim ko'radi). Yozish yo'q.
create or replace view public.students_billing with (security_barrier = true) as
  select s.id, s."studentId", s.name, s.grade, s."classLetter", s.track, s.lang, s."payStatus", s."activeFrom", s."stopFrom",
         s.pauses, s."order"
    from public.students s
   where (select app.is_admin()) or (select app.is_zavuch()) or (select app.is_reception())
      or (select app.is_finance()) or (select app.is_cashier());
revoke all on public.students_billing from public, anon, authenticated;
grant select on public.students_billing to authenticated, service_role;

-- 5) Kamera ID egasi: o'quvchi ismi faqat D6 rollariga (HR va boshqalar — ismsiz «o'quvchida band»).
create or replace function public.camera_owners(p_cam text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.is_staff() and btrim(coalesce(p_cam, '')) <> '' then coalesce((
    select jsonb_agg(jsonb_build_object('coll', coll, 'id', id,
             'name', case when coll = 'students' and not (app.is_admin() or app.is_zavuch() or app.is_reception()) then null else name end)
           order by coll, id) from (
      select 'students' as coll, s.id, s.name from public.students s where btrim(coalesce(s."cameraId", '')) = btrim(p_cam)
      union all select 'teachers', t.id, t.name from public.teachers t where btrim(coalesce(t."cameraId", '')) = btrim(p_cam)
      union all select 'staff', x.id, x.name from public.staff x where btrim(coalesce(x."cameraId", '')) = btrim(p_cam)) o
  ), '[]'::jsonb) end
$$;

-- 6) Kamera skanlari: HR / moliya / kassa — faqat o'qituvchi va xodim Kamera ID'lari (o'quvchi skanlari — direktor;
--    sinf xodimi o'quvchi kelishini class_arrivals() orqali ko'radi). Subso'rov so'rovda bir marta hisoblanadi (hash).
drop policy if exists sc_chk_sel on public.staff_checkins;
create policy sc_chk_sel on public.staff_checkins for select using (
  app.is_admin()
  or ((app.is_hr() or app.is_finance() or app.is_cashier())
      and btrim(coalesce("personId", '')) in (
        select btrim(t."cameraId") from public.teachers t where btrim(coalesce(t."cameraId", '')) <> ''
        union select btrim(x."cameraId") from public.staff x where btrim(coalesce(x."cameraId", '')) <> ''))
);

-- 7) Hisob-fakturalar: marketing yo'q. Marketing faqat yig'ma sonni oladi.
drop policy if exists inv_sel on public.invoices;
create policy inv_sel on public.invoices for select using (
  app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_cashier() or app.is_reception() or app.owns_child("studentId")
);
create or replace function public.marketing_fee_stats() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not (app.is_admin() or app.is_marketing()) then raise exception 'ruxsat yo''q' using errcode = '42501'; end if;
  return (select jsonb_build_object('paidCount', count(*), 'avgPaid', coalesce(round(avg(amount)), 0))
            from public.invoices where status = 'paid' and coalesce(amount, 0) > 0);
end $$;
revoke all on function public.marketing_fee_stats() from public, anon;
grant execute on function public.marketing_fee_stats() to authenticated, service_role;

-- 8) Davomat: O'IBDO' bor, ma'muriyat rahbari yo'q.
drop policy if exists att_sel on public.attendance;
create policy att_sel on public.attendance for select using (
  app.is_admin() or app.is_zavuch() or app.owns_child("studentId") or app.is_kurator_for("classKey") or app.is_homeroom_for("classKey")
);

-- 9) Olimpiada natijalari (ism bilan): barcha xodim emas.
drop policy if exists oly_sel on public.olympiads;
create policy oly_sel on public.olympiads for select using (
  app.is_admin() or app.is_zavuch() or app.is_reception() or app.is_class_staff("classKey") or app.owns_child("studentId")
);

-- 10) O'zgarishlar tarixi: ota-ona telefonlari (qiymati yashirin — faqat «o'zgardi»), change-log.sql bilan bir xil ro'yxat.
select app.chlog_attach('student_private', 'specialCategory,contractAmount,siblingDiscount,referrerId,teacherId,!parentPhone,!parentPhone2');

notify pgrst, 'reload schema';
