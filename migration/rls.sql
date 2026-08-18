-- =====================================================================
-- Iqror Academy — PostgreSQL RLS (Firestore Security Rules ekvivalenti)
-- Supabase'да app.uid() -> auth.uid() bilan almashtiriladi.
-- Test'да app.uid GUC orqali (SET app.uid = '<uid>').
-- Yordamchi funksiyalar SECURITY DEFINER — rol tekshiruvлари RLS'ни chetlab
-- users jadvalини o'qiy oladi (rekursiyasiz).
-- =====================================================================
create schema if not exists app;

-- app.uid(): Supabase'да JWT 'sub' (auth.uid) dan, TEST'да app.uid GUC dan o'qiydi.
-- Shu tufayli rls.sql HAM jonli Supabase'да, HAM sinovда o'zgartirishsiz ishlaydi.
create or replace function app.uid() returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif((nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'), ''),
    nullif(current_setting('app.uid', true), '')
  )
$$;
create or replace function app.is_admin() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role = 'admin')
$$;
create or replace function app.is_zavuch() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role = 'zavuch')
$$;
-- owns_child: MAXFIY KOD tizimi (security-2b.sql) — child_claims'dan o'qiydi (users.childIds'ga tayanmaydi).
-- (child_claims/student_codes jadvallari security-2b.sql'da yaratiladi.)
create or replace function app.owns_child(sid text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.child_claims where uid = app.uid() and "studentId" = sid)
$$;
create or replace function app.is_homeroom_for(ck text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('admin','zavuch','kurator','teacher') and coalesce("homeroomClasses",'[]'::jsonb) ? ck)
$$;
create or replace function app.is_kurator_for(ck text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role='kurator' and coalesce("assignedClasses",'[]'::jsonb) ? ck)
$$;
create or replace function app.is_teacher_for_class(ck text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role='teacher' and coalesce("assignedClasses",'[]'::jsonb) ? ck)
$$;
create or replace function app.teacher_has_subject(subj text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and coalesce("assignedSubjects",'[]'::jsonb) ? subj)
$$;
create or replace function app.can_write_general(ck text) returns boolean language sql stable as $$
  select app.is_admin() or app.is_zavuch() or app.is_homeroom_for(ck) or app.is_kurator_for(ck)
$$;
create or replace function app.is_class_staff(ck text) returns boolean language sql stable as $$
  select app.can_write_general(ck) or app.is_teacher_for_class(ck)
$$;

-- ============ students (ommaviy o'qiladi; PII ustunlari YO'Q -> tuzilmaviy himoya) ============
alter table students enable row level security;
create policy students_sel on students for select using (true);
create policy students_ins on students for insert with check (app.is_admin());
create policy students_upd on students for update using (app.is_admin() or app.is_zavuch()) with check (app.is_admin() or app.is_zavuch());
create policy students_del on students for delete using (app.is_admin());
-- Izoh: 'score-only for zavuch' — ustun-darajali GRANT/trigger bilan (keyingi nafislik).

-- ============ student_private (PII — qulflangan) ============
alter table student_private enable row level security;
create policy priv_sel on student_private for select using (app.is_admin() or app.is_zavuch() or app.owns_child(id));
create policy priv_ins on student_private for insert with check (app.is_admin());
create policy priv_upd on student_private for update using (app.is_admin()) with check (app.is_admin());
create policy priv_del on student_private for delete using (app.is_admin());

-- ============ grades ============
alter table grades enable row level security;
create policy grades_sel on grades for select using (app.is_admin() or app.owns_child("studentId") or app.is_teacher_for_class("classKey"));
create policy grades_ins on grades for insert with check (app.is_admin() or app.is_teacher_for_class("classKey"));
create policy grades_upd on grades for update using (app.is_admin() or app.is_teacher_for_class("classKey")) with check (app.is_admin() or app.is_teacher_for_class("classKey"));

-- ============ attendance ============
alter table attendance enable row level security;
create policy att_sel on attendance for select using (app.is_admin() or app.owns_child("studentId") or app.is_kurator_for("classKey") or app.is_homeroom_for("classKey"));
create policy att_ins on attendance for insert with check (app.is_admin() or app.is_kurator_for("classKey") or app.is_homeroom_for("classKey"));
create policy att_upd on attendance for update using (app.is_admin() or app.is_kurator_for("classKey") or app.is_homeroom_for("classKey")) with check (app.is_admin() or app.is_kurator_for("classKey") or app.is_homeroom_for("classKey"));

-- ============ monitoring ============
alter table monitoring enable row level security;
create policy mon_sel on monitoring for select using (app.is_admin() or app.is_zavuch() or app.owns_child("studentId") or app.is_teacher_for_class("classKey"));
create policy mon_ins on monitoring for insert with check (app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject) and status='pending'));
create policy mon_upd on monitoring for update using (app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject))) with check (app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject)));
create policy mon_del on monitoring for delete using (app.is_admin() or app.is_zavuch());

-- ============ characteristics (umumiy xarakteristika) ============
alter table characteristics enable row level security;
create policy char_sel on characteristics for select using (app.is_class_staff("classKey") or app.owns_child("studentId"));
create policy char_ins on characteristics for insert with check (app.can_write_general("classKey"));
create policy char_upd on characteristics for update using (app.can_write_general("classKey")) with check (app.can_write_general("classKey"));
create policy char_del on characteristics for delete using (app.can_write_general("classKey"));

-- ============ subject_notes (fan izohi — o'qituvchi izolyatsiyasi) ============
alter table subject_notes enable row level security;
create policy note_sel on subject_notes for select using (
  app.can_write_general("classKey")
  or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject))
  or app.owns_child("studentId"));
create policy note_ins on subject_notes for insert with check (
  app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject)));
create policy note_upd on subject_notes for update using (
  app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject)))
  with check (app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject)));
create policy note_del on subject_notes for delete using (
  app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject)));

-- ============ student_summaries (oylik xulosa) ============
alter table student_summaries enable row level security;
create policy sum_sel on student_summaries for select using (app.is_class_staff("classKey") or app.owns_child("studentId"));
create policy sum_ins on student_summaries for insert with check (app.can_write_general("classKey"));
create policy sum_upd on student_summaries for update using (app.can_write_general("classKey")) with check (app.can_write_general("classKey"));
create policy sum_del on student_summaries for delete using (app.can_write_general("classKey"));

-- ============ invoices ============
alter table invoices enable row level security;
create policy inv_sel on invoices for select using (app.is_admin() or app.is_zavuch() or app.owns_child("studentId"));
create policy inv_ins on invoices for insert with check (app.is_admin());
create policy inv_upd on invoices for update using (app.is_admin()) with check (app.is_admin());
create policy inv_del on invoices for delete using (app.is_admin());

-- ============ expenses (buxgalteriya — admin/zavuch) ============
alter table expenses enable row level security;
create policy exp_sel on expenses for select using (app.is_admin() or app.is_zavuch());
create policy exp_ins on expenses for insert with check (app.is_admin() or app.is_zavuch());
create policy exp_upd on expenses for update using (app.is_admin() or app.is_zavuch()) with check (app.is_admin() or app.is_zavuch());
create policy exp_del on expenses for delete using (app.is_admin());

-- ============ users (o'zi/admin) ============
alter table users enable row level security;
create policy users_sel on users for select using (id = app.uid() or app.is_admin());
create policy users_ins on users for insert with check (id = app.uid() and role in ('parent','student') and verified = false);
-- self-update: rol/verified/biriktirilgan sinflarni O'ZGARTIRA OLMAYDI (eski qiymat bilan solishtiramiz)
create policy users_upd on users for update using (app.is_admin() or id = app.uid())
  with check (app.is_admin() or (
     id = app.uid()
     and role     = (select u.role     from public.users u where u.id = app.uid())
     and verified = (select u.verified from public.users u where u.id = app.uid())
     and coalesce("childIds",        '[]'::jsonb) = coalesce((select u."childIds"        from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("homeroomClasses", '[]'::jsonb) = coalesce((select u."homeroomClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedClasses", '[]'::jsonb) = coalesce((select u."assignedClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedSubjects",'[]'::jsonb) = coalesce((select u."assignedSubjects" from public.users u where u.id = app.uid()), '[]'::jsonb)
  ));
create policy users_del on users for delete using (app.is_admin());

-- ============ payments / checkins (server yozadi = service_role; mijoz faqat o'qiydi) ============
alter table payments enable row level security;
create policy pay_sel on payments for select using (app.is_admin());
alter table checkins enable row level security;
create policy chk_sel on checkins for select using (app.is_admin() or app.is_zavuch());

-- ============ enrollments / applications (ochiq yuboriladi; admin o'qiydi) ============
alter table enrollments enable row level security;
create policy enr_ins on enrollments for insert with check (true);
create policy enr_sel on enrollments for select using (app.is_admin());
create policy enr_upd on enrollments for update using (app.is_admin());
create policy enr_del on enrollments for delete using (app.is_admin());
alter table applications enable row level security;
create policy app_ins on applications for insert with check (status = 'submitted');
create policy app_sel on applications for select using (app.is_admin() or app.is_zavuch());
create policy app_upd on applications for update using (app.is_admin() or app.is_zavuch());
create policy app_del on applications for delete using (app.is_admin() or app.is_zavuch());

-- ============ secrets — MIJOZGA UMUMAN YOPIQ (RLS on, policy yo'q) ============
-- Faqat service_role / superuser (RLS'ni chetlab) o'qiydi. Ishlаб chiqarишда
-- Anthropic kaliti bu jadvalда emas, server ENV/vault'да bo'ladi.
alter table secrets enable row level security;

-- ============ Kontent jadvallari: ommaviy o'qiladi, admin yozadi ============
do $$
declare t text;
begin
  foreach t in array array[
    'news','gallery','testimonials','plans','admission_steps','faq','events',
    'achievements_school','achievements_students','classes','teachers','settings','config','exam_questions','timetable','homework'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select using (true)', t||'_sel', t);
    execute format('create policy %I on %I for insert with check (app.is_admin())', t||'_ins', t);
    execute format('create policy %I on %I for update using (app.is_admin()) with check (app.is_admin())', t||'_upd', t);
    execute format('create policy %I on %I for delete using (app.is_admin())', t||'_del', t);
  end loop;
end $$;
-- exam_questions: nomzod savolni o'qishi kerak -> select true (yuqorida shunday).
-- timetable/homework: tizimga kirganlar o'qiydi -> Supabase'да select'ni auth.uid() is not null qilamiz (test'да true).
