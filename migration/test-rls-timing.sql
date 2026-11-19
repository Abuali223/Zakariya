-- =====================================================================
-- test-rls-timing.sql — RLS orqali VAQT BO'YICHA SIZISH yopilganini tekshirish (migration/rls-timing.sql, rls-initplan.sql,
--   reports-roles.sql users_upd; mustaqil tekshiruv 2026-11-19, SESSIYA-ISHLARI.md §85):
--   (A) anon — faqat ochiq sayt kontenti (yopiq ro'yxat); maxfiy jadval / ko'rinish — 42501; INSERT (ariza shakllari) — saqlangan;
--   (P) policy va ko'rinishlarda qatorga bog'liq egalik / sinf yordamchilarining XOM chaqiruvi yo'q (hammasi bir martalik o'ramda);
--       users policy'lari InitPlan o'ramida, users_upd o'zini subso'rov bilan o'qimaydi; profilni saqlash ishlaydi, himoya saqlangan;
--   (E) TENGLIK: app.my_child_sids() / app.my_student_docs() — owns_child / owns_student_doc bilan barcha kalitlarda (hujjat id,
--       studentId, eski karta kaliti, takroriy kalit, yetim bog'lanish, kutilayotgan / bekor / bloklangan) AYNAN bir xil; sinf
--       o'ramlari (rls_class_staff / rls_ann_gate darvozasi bilan) — asl funksiyalar bilan barcha rol va sinf kalitlarida bir xil;
--   (C) CHAQIRUVLAR SONI (track_functions = all): sotuvchi / farzandsiz ota-ona / farzandli ota-ona so'rovida qatorga bog'liq
--       SECURITY DEFINER funksiya (owns_child, owns_student_doc, is_homeroom_for, is_kurator_for, is_teacher_for_class,
--       can_write_general, teacher_has_subject, ann_visible) — 0 marta; egalik to'plami — ko'pi bilan 1 marta (InitPlan);
--   (R) REJA: sotuvchida student_phones / my_sick_notes / my_nurse_visits — jadval ko'rib chiqilmaydi (One-Time Filter, «never
--       executed»); student_private / students — darvoza filtrning BIRINCHI sharti (foydalanuvchi filtri hech qachon baholanmaydi);
--   (F) ko'rinish huquqlari o'zgarmagan: Direktor, qabulxona, moliya, kassir, sinf xodimi, farzandli / farzandsiz ota-ona, sotuvchi.
--   Har chaqiruv haqiqiy rol bilan (authenticated / anon + JWT sub). Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida,
--   kanonik zanjirdan keyin (dev va jonli zanjir), migration/ papkasidan:
--     bash migration/chain.sh --no-lock-timeout | psql -d fx_sinov -q && (cd migration && psql -d fx_sinov -X -f test-rls-timing.sql)
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Ism / telefonlar to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\set kutilgan 18
do $g0$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.users) then
    raise exception 'test-rls-timing.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g0$;
begin;
set local track_functions = 'all';
create schema if not exists zz;
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '{"role":"anon"}' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  if p_uid is null then execute 'set local role anon'; else execute 'set local role authenticated'; end if;
  begin
    execute p_q into r;
  exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
-- Reja matni (EXPLAIN ANALYZE) shu rol nomidan, bitta qatorga.
create or replace function zz.plan(p_uid text, p_q text) returns text language plpgsql as $$
declare r record; v text := '';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    for r in execute 'explain (analyze, costs off, timing off, summary off) ' || p_q loop v := v || r."QUERY PLAN" || E'\n'; end loop;
  exception when others then v := 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
end $$;
-- Joriy tranzaksiyada funksiya necha marta chaqirilgani (track_functions = all).
create or replace function zz.calls(p_fn text) returns bigint language sql as $$
  select coalesce(pg_stat_get_xact_function_calls(to_regprocedure(p_fn)), 0) $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, coalesce(p_got, '<NULL>'), p_pat, coalesce(p_got ~ p_pat, false)); end $$;

-- ---------- Urug' (triggerlarsiz; to'qima) ----------
set local session_replication_role = replica;
insert into app.fin_clock (id, t) values (1, '2026-11-19 10:00+05') on conflict (id) do update set t = excluded.t;
insert into public.users (id, email, name, role, status, verified, "extraRoles", "homeroomClasses", "assignedClasses", "assignedSubjects", phone) values
  ('U_DIR','d@example.org','Sinov Direktor','director','active',true,'[]','[]','[]','[]',null),
  ('U_SAL','s@example.org','Sinov Sotuvchi','sales','active',true,'[]','[]','[]','["Matematika"]',null),
  ('U_PAR0','p0@example.org','Sinov Ota Farzandsiz','parent','active',true,'[]','[]','[]','[]',null),
  ('U_PA','pa@example.org','Sinov Ota A','parent','active',true,'[]','[]','[]','[]','998001110001'),
  ('U_PB','pb@example.org','Sinov Ota B','parent','active',true,'[]','[]','[]','[]',null),
  ('U_BL','bl@example.org','Sinov Ota Bloklangan',null,'blocked',true,'[]','[]','[]','[]',null),
  ('U_TCH','t@example.org','Sinov Oqituvchi','teacher','active',true,'[]','[]','["uz-5-A"]','["Matematika"]',null),
  ('U_HM','hm@example.org','Sinov Sinf Rahbari','teacher','active',true,'[]','["uz-6-B"]','[]','[]',null),
  ('U_KUR','k@example.org','Sinov Kurator','kurator','active',true,'[]','[]','["uz-7-C"]','[]',null),
  ('U_ZAV','z@example.org','Sinov Oibdo','zavuch','active',true,'[]','[]','[]','[]',null),
  ('U_ADM','ad@example.org','Sinov Mamuriyat','admin','active',true,'[]','["uz-8-D"]','[]','[]',null),
  ('U_HRT','hr@example.org','Sinov Kadrlar Oqituvchi','hr','active',true,'["teacher"]','[]','["uz-5-A"]','["Fizika"]',null),
  ('U_REC','r@example.org','Sinov Qabulxona','reception','active',true,'[]','[]','[]','[]',null),
  ('U_FM','f@example.org','Sinov Moliyachi','finance_mgr','active',true,'[]','[]','[]','[]',null),
  ('U_KAS','ka@example.org','Sinov Kassir','kassir','active',true,'[]','[]','[]','[]',null),
  ('U_NUR','n@example.org','Sinov Hamshira','nurse','active',true,'[]','[]','[]','[]',null),
  ('U_ACC','ac@example.org','Sinov Buxgalter','accountant','active',true,'[]','[]','[]','[]',null);
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus") values
  ('sa','IQ-A','Sinov Bola A',5,'A','uz',''), ('sb','IQ-B','Sinov Bola B',6,'B','uz',''), ('sc','IQ-C','Sinov Bola C',7,'C','uz',''),
  ('sl','IQ-L','Sinov Bola L',5,'A','uz',''),                     -- eski karta: student_private.id = 'IQ-L'
  ('sx1','IQ-DUP','Sinov Bola X1',8,'D','uz',''), ('sx2','IQ-DUP','Sinov Bola X2',8,'D','uz',''),   -- takroriy studentId
  ('sz','sa','Sinov Bola Z',9,'A','uz','');                        -- studentId boshqa o'quvchining hujjat id'siga teng
insert into public.student_codes (id, code) values ('sx1','CODEX1'), ('sx2','CODEX2'), ('sa','CODEA');
insert into public.student_private (id, "fatherName", "parentPhone") values
  ('sa','Sinov Ota A','+998001110001'), ('sb','Sinov Ota B','+998001110002'), ('sc','Sinov Ota C','+998001110003'),
  ('IQ-L','Sinov Ota L','+998001110004'), ('sx1','Sinov Ota X1','+998001110005'), ('sx2','Sinov Ota X2','+998001110006'),
  ('sz','Sinov Ota Z','+998001110007'), ('IQ-ORPH','Sinov Ota Yetim','+998001110008');
insert into public.child_claims (id, uid, "studentId", code, status) values
  ('U_PA__IQ-A','U_PA','IQ-A','CODEA','active'), ('U_PA__IQ-L','U_PA','IQ-L','','active'), ('U_PA__IQ-ORPH','U_PA','IQ-ORPH','','active'),
  ('U_PA__IQ-B','U_PA','IQ-B','','pending'), ('U_PA__IQ-C','U_PA','IQ-C','','revoked'),
  ('U_PB__IQ-DUP','U_PB','IQ-DUP','CODEX2','active'), ('U_BL__IQ-A','U_BL','IQ-A','CODEA','active');
insert into public.attendance (id, "studentId", "classKey", month, days)
  select s."studentId" || '__2026-11', s."studentId", 'uz-' || s.grade || '-' || s."classLetter", '2026-11', '{}' from public.students s where s.id <> 'sx2';
insert into public.grades (id, "studentId", "classKey", year, subjects)
  select s."studentId" || '__2026-2027', s."studentId", 'uz-' || s.grade || '-' || s."classLetter", '2026-2027', '{}' from public.students s where s.id <> 'sx2';
insert into public.sick_notes (id, "studentId", "fromDay", "toDay", status) select 'sn_' || s.id, s."studentId", '2026-11-10', '2026-11-11', 'pending' from public.students s where s.id <> 'sx2';
insert into public.nurse_visits (id, "studentId", complaint, action) select 'nv_' || s.id, s."studentId", 'ZZ', 'rest' from public.students s where s.id <> 'sx2';
insert into public.class_announcements (id, "classKeys", title, body) values ('an1','["uz-5-A"]','Sinov','ZZ'), ('an2','["all"]','Sinov','ZZ'), ('an3','["uz-9-Z"]','Sinov','ZZ');
set local session_replication_role = origin;

-- ========== (A) anon ==========
select zz.chk('A01 anon SELECT / UPDATE / DELETE — faqat ochiq sayt kontenti (yopiq ro''yxat)',
  (select string_agg(c.relname, ',' order by c.relname) from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f')
      and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'))),
  '^achievements_school,achievements_students,admission_steps,bus_routes_public,classes,config,events,exam_questions,exams,faq,gallery,news,plans,settings,teachers_public,testimonials$');
select zz.chk('A02 anon: maxfiy jadval / ko''rinish — 42501 (filtr bilan ham); ochiq kontent — o''qiladi; ariza shakllari INSERT — saqlangan',
  zz.as(null, $q$select count(*)::text from public.student_phones where "parentPhone" >= '+9'$q$) || ' | '
  || zz.as(null, $q$select count(*)::text from public.student_private where "parentPhone" >= '+9'$q$) || ' | '
  || zz.as(null, $q$select count(*)::text from public.students where name >= 'S'$q$) || ' | '
  || zz.as(null, $q$select count(*)::text from public.users where phone >= '9'$q$) || ' | '
  || zz.as(null, 'select count(*)::text from public.news') || ' | '
  || has_table_privilege('anon', 'public.enrollments', 'INSERT')::text || has_table_privilege('anon', 'public.applications', 'INSERT')::text,
  '^ERR 42501 [^|]* \| ERR 42501 [^|]* \| ERR 42501 [^|]* \| ERR 42501 [^|]* \| 0 \| truetrue$');

-- ========== (P) policy / ko'rinish tuzilmasi ==========
select zz.chk('P01 policy''larda qatorga bog''liq egalik / sinf yordamchisining XOM chaqiruvi yo''q (USING va WITH CHECK)',
  coalesce((select string_agg(c.relname || '.' || p.polname, ',' order by c.relname, p.polname) from pg_policy p join pg_class c on c.oid = p.polrelid
             where c.relnamespace = 'public'::regnamespace
               and (coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''))
                   ~ '(^|[^A-Za-z0-9_.])app\.(owns_child|owns_student_doc|is_class_staff|can_write_general|is_teacher_for_class|is_homeroom_for|is_kurator_for|teacher_has_subject|ann_can_write|ann_visible)\('), '-'),
  '^-$');
select zz.chk('P02 authenticated o''qiydigan ko''rinishlarda ham XOM chaqiruv yo''q (student_phones, my_sick_notes, my_nurse_visits …)',
  coalesce((select string_agg(c.relname, ',' order by c.relname) from pg_class c
             where c.relnamespace = 'public'::regnamespace and c.relkind in ('v', 'm') and has_table_privilege('authenticated', c.oid, 'SELECT')
               and pg_get_viewdef(c.oid) ~ '(^|[^A-Za-z0-9_.])app\.(owns_child|owns_student_doc|is_class_staff|can_write_general|is_teacher_for_class|is_homeroom_for|is_kurator_for|teacher_has_subject|ann_can_write|ann_visible)\('), '-')
  || ' | ' || (select string_agg(c.relname || '=' || coalesce(array_to_string(c.reloptions, ','), '-'), ',' order by c.relname) from pg_class c
                where c.relnamespace = 'public'::regnamespace and c.relname in ('student_phones', 'my_sick_notes', 'my_nurse_visits')),
  '^- \| my_nurse_visits=security_barrier=true,my_sick_notes=security_barrier=true,student_phones=security_barrier=true$');
select zz.chk('P03 users: policy''lar InitPlan o''ramida (har qatorda is_admin yo''q), users_upd users''ni subso''rov bilan o''qimaydi',
  (select string_agg(polname || '=' || (coalesce(pg_get_expr(polqual, polrelid), '') || ' ' || coalesce(pg_get_expr(polwithcheck, polrelid), '')
                                         ~ '(?<!SELECT )app\.(uid|is_admin)\(\)')::text
                     || '/' || (coalesce(pg_get_expr(polwithcheck, polrelid), '') ~ 'FROM (public\.)?users')::text, ',' order by polname)
     from pg_policy where polrelid = 'public.users'::regclass),
  '^users_del=false/false,users_ins=false/false,users_sel=false/false,users_upd=false/false$');
select zz.as('U_PA', $q$with u as (update public.users set name = 'Sinov Ota A yangi' where id = 'U_PA' returning name) select string_agg(name, ',') from u$q$) || ' | '
  || zz.as('U_PA', $q$update public.users set phone = '998009999999' where id = 'U_PA' returning phone$q$) || ' | '
  || zz.as('U_PA', $q$update public.users set "childIds" = '["sb"]' where id = 'U_PA' returning 1$q$) || ' | '
  || zz.as('U_DIR', $q$with u as (update public.users set name = 'Sinov Ota A dir' where id = 'U_PA' returning 1) select count(*)::text from u$q$) as p04 \gset
select zz.chk('P04 profil: o''z ismini saqlaydi (42P17 yo''q); o''z telefoni / bolalar ro''yxati — rad (42501); Direktor tahrirlaydi',
  :'p04', '^Sinov Ota A yangi \| ERR 42501 [^|]* \| ERR 42501 [^|]* \| 1$');

-- ========== (E) tenglik ==========
create temp table zz_keys on commit drop as
  select distinct k from (select id as k from public.students union all select "studentId" from public.students union all select id from public.student_private
                          union all select "studentId" from public.child_claims union all select v from (values (''), ('nope'), ('IQ-ORPH')) x(v)) y;
create temp table zz_eq on commit drop as
  select u, k,
         zz.as(u, format('select (app.owns_child(%L) is not distinct from app.rls_in(app.my_child_sids(), %L))::text', k, k)) as e_child,
         zz.as(u, format('select (app.owns_student_doc(%L) is not distinct from app.rls_in(app.my_student_docs(), %L))::text', k, k)) as e_doc,
         zz.as(u, format('select app.owns_child(%L)::text || app.owns_student_doc(%L)::text', k, k)) as orig
    from unnest(array['U_PA','U_PB','U_BL','U_PAR0','U_SAL','U_DIR','U_TCH']) u, zz_keys;
select zz.chk('E01 my_child_sids / my_student_docs — owns_child / owns_student_doc bilan barcha foydalanuvchi va kalitlarda AYNAN bir xil (oldida — tekshirilgan juftlar)',
  (select count(*) || ':' || coalesce(string_agg(case when e_child <> 'true' or e_doc <> 'true' then u || '/' || k || '=' || e_child || e_doc end, ',' order by u, k), '')
     from zz_eq), '^[0-9]{2,}:$');
select zz.chk('E02 urug'' qiyin holatlarni qamraydi: owns_child — studentId, eski karta, yetim (hujjat «sa» — boshqa o''quvchining studentId''si, yo''q); takroriy studentId — faqat hujjat id; bloklangan — hech narsa | owns_student_doc',
  (select string_agg(u || ':' || (select coalesce(string_agg(k, ',' order by k), '-') from zz_eq e where e.u = x.u and e.orig ~ '^true'), ' ' order by u)
     from (select distinct u from zz_eq where u in ('U_PA', 'U_PB', 'U_BL')) x) || ' | '
  || (select string_agg(u || ':' || (select coalesce(string_agg(k, ',' order by k), '-') from zz_eq e where e.u = x.u and e.orig ~ 'true$'), ' ' order by u)
     from (select distinct u from zz_eq where u in ('U_PA', 'U_PB')) x),
  '^U_BL:- U_PA:IQ-A,IQ-L,IQ-ORPH,sl U_PB:sx2 \| U_PA:IQ-A,IQ-L,IQ-ORPH,sa,sl U_PB:sx2$');
create temp table zz_ck on commit drop as
  select u, ck,
         zz.as(u, format('select (coalesce(app.is_class_staff(%1$L), false) = coalesce(app.rlsg_is_class_staff(app.rls_class_staff(), %1$L), false)
                           and coalesce(app.can_write_general(%1$L), false) = coalesce(app.rlsg_can_write_general(app.rls_class_staff(), %1$L), false)
                           and coalesce(app.is_teacher_for_class(%1$L), false) = coalesce(app.rlsg_is_teacher_for_class(app.rls_class_staff(), %1$L), false)
                           and coalesce(app.is_homeroom_for(%1$L), false) = coalesce(app.rlsg_is_homeroom_for(app.rls_class_staff(), %1$L), false)
                           and coalesce(app.is_kurator_for(%1$L), false) = coalesce(app.rlsg_is_kurator_for(app.rls_class_staff(), %1$L), false)
                           and coalesce(app.is_teacher_for_class(%1$L) and app.teacher_has_subject(%2$L), false)
                             = coalesce(app.rlsg_is_teacher_for_class(app.rls_class_staff(), %1$L) and app.rlsg_teacher_has_subject(app.rls_class_staff(), %2$L), false))::text
                           || (app.is_class_staff(%1$L) or app.can_write_general(%1$L))::text', ck, 'Matematika')) as r
    from unnest(array['U_DIR','U_SAL','U_PAR0','U_PA','U_TCH','U_HM','U_KUR','U_ZAV','U_ADM','U_HRT','U_REC','U_FM','U_KAS','U_NUR','U_ACC','U_BL']) u,
         unnest(array['uz-5-A','uz-6-B','uz-7-C','uz-8-D','uz-9-Z','']) ck;
create temp table zz_ann on commit drop as
  select u, k, e,
         zz.as(u, format('select (coalesce(app.ann_can_write(%1$L::jsonb), false) = coalesce(app.rlsg_ann_can_write(app.rls_class_staff(), %1$L::jsonb), false)
                           and coalesce(app.ann_visible(%1$L::jsonb, %2$L::timestamptz), false) = coalesce(app.rlsg_ann_visible(app.rls_ann_gate(), %1$L::jsonb, %2$L::timestamptz), false))::text', k, e)) as r
    from unnest(array['U_DIR','U_SAL','U_PAR0','U_PA','U_TCH','U_HM','U_KUR','U_ZAV','U_ADM','U_HRT','U_REC','U_NUR','U_BL']) u,
         unnest(array['["all"]','["uz-5-A"]','["uz-6-B"]','["uz-9-Z"]','[]']) k, unnest(array[null, '2026-01-01 00:00+05', '2027-01-01 00:00+05']) e;
select zz.chk('E03 sinf o''ramlari (darvoza bilan) — asl funksiyalar bilan barcha rol va sinf kalitlarida bir xil; kimdir haqiqatan rost (oldida — juftlar / rostlar)',
  (select count(*) || '/' || count(*) filter (where r ~ 'true$') || ':' || coalesce(string_agg(case when r !~ '^true' then u || '/' || ck || '=' || r end, ',' order by u, ck), '') from zz_ck),
  '^96/[1-9][0-9]*:$');
select zz.chk('E04 e''lon o''ramlari (ann_can_write, ann_visible) — asl bilan bir xil (oldida — juftlar)',
  (select count(*) || ':' || coalesce(string_agg(case when r <> 'true' then u || '/' || k || '/' || coalesce(e, '-') || '=' || r end, ',' order by u, k), '') from zz_ann),
  '^195:$');

-- ========== (C) chaqiruvlar soni ==========
-- Har so'rov alohida (\gset); soni — oldingi / keyingi farq. fns: qatorga bog'liq SECURITY DEFINER yordamchilar.
create temp table zz_fn on commit drop as select unnest(array['app.owns_child(text)', 'app.owns_student_doc(text)', 'app.is_homeroom_for(text)',
  'app.is_kurator_for(text)', 'app.is_teacher_for_class(text)', 'app.teacher_has_subject(text)', 'app.ann_visible(jsonb,timestamp with time zone)',
  'app.ann_can_write(jsonb)']) as fn;
create or replace function zz.rowcalls() returns bigint language sql as $$ select sum(zz.calls(fn))::bigint from zz_fn $$;
create or replace function zz.setcalls() returns text language sql as $$
  select zz.calls('app.my_child_sids()') || '/' || zz.calls('app.my_student_docs()') $$;
create or replace function zz.try_insert_att() returns text language plpgsql as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  insert into public.attendance (id, "studentId", "classKey", month, days)
    select 'IQ-Q' || g || '__2026-11', 'IQ-Q' || g, 'uz-1-A', '2026-11', '{}' from generate_series(1, 100) g;
  perform set_config('session_replication_role', 'origin', true);
  return 'OK';
exception when others then perform set_config('session_replication_role', 'origin', true); return 'ERR ' || sqlerrm; end $$;
create temp table zz_c (step text, rowc bigint, setc text) on commit drop;
insert into zz_c select 'base', zz.rowcalls(), zz.setcalls();
select zz.as('U_SAL', $q$select (select count(*) from public.attendance where "studentId" >= 'A') + (select count(*) from public.grades where "studentId" >= 'A')
  + (select count(*) from public.students where name >= 'S') + (select count(*) from public.student_private where "parentPhone" >= '+9')
  + (select count(*) from public.student_phones where "parentPhone" >= '+9') + (select count(*) from public.my_sick_notes where "studentId" >= 'A')
  + (select count(*) from public.my_nurse_visits where "studentId" >= 'A') + (select count(*) from public.class_announcements where title >= 'S')$q$) as c_sal \gset
insert into zz_c select 'sal', zz.rowcalls(), zz.setcalls();
select zz.as('U_PAR0', $q$select (select count(*) from public.attendance where "studentId" >= 'A') + (select count(*) from public.students where name >= 'S')
  + (select count(*) from public.student_private where "parentPhone" >= '+9') + (select count(*) from public.my_sick_notes where "studentId" >= 'A')
  + (select count(*) from public.class_announcements where title >= 'S')$q$) as c_par0 \gset
insert into zz_c select 'par0', zz.rowcalls(), zz.setcalls();
select zz.as('U_PA', $q$select (select count(*) from public.attendance where "studentId" >= 'A') + (select count(*) from public.grades where "studentId" >= 'A')
  + (select count(*) from public.students where name >= 'S') + (select count(*) from public.student_private where "parentPhone" >= '+9')
  + (select count(*) from public.student_phones where "parentPhone" >= '+9') + (select count(*) from public.my_sick_notes where "studentId" >= 'A')
  + (select count(*) from public.my_nurse_visits where "studentId" >= 'A')$q$) as c_pa \gset
insert into zz_c select 'pa', zz.rowcalls(), zz.setcalls();
select zz.chk('C01 sotuvchi (8 so''rov, hammasi filtr bilan): hech narsa ko''rmaydi; qatorga bog''liq funksiya — 0 marta; egalik to''plami — har so''rovda ko''pi bilan 1',
  :'c_sal' || ' | ' || ((select rowc from zz_c where step = 'sal') - (select rowc from zz_c where step = 'base'))::text,
  '^0 \| 0$');
select zz.chk('C02 farzandsiz ota-ona: hech narsa ko''rmaydi; qatorga bog''liq funksiya — 0',
  :'c_par0' || ' | ' || ((select rowc from zz_c where step = 'par0') - (select rowc from zz_c where step = 'sal'))::text, '^0 \| 0$');
select zz.chk('C03 farzandli ota-ona: o''z farzandlari ko''rinadi (davomat, baho, o''quvchi, karta, telefon, tibbiy); qatorga bog''liq funksiya — 0',
  :'c_pa' || ' | ' || ((select rowc from zz_c where step = 'pa') - (select rowc from zz_c where step = 'par0'))::text, '^[1-9][0-9]* \| 0$');
-- C04: egalik to'plami so'rovda doimiy marta hisoblanadi — jadvaldagi qatorlar 100 taga ko'paysa ham chaqiruvlar soni o'zgarmaydi.
select zz.as('U_PA', $q$select count(*)::text from public.attendance where "studentId" >= 'A'$q$) as c4a \gset
insert into zz_c select 'c4a', zz.rowcalls(), zz.setcalls();
select zz.try_insert_att() as c4i \gset
select zz.as('U_PA', $q$select count(*)::text from public.attendance where "studentId" >= 'A'$q$) as c4b \gset
insert into zz_c select 'c4b', zz.rowcalls(), zz.setcalls();
select zz.chk('C04 egalik to''plami — har so''rovda doimiy (100 ta yangi qator qo''shilganda ham chaqiruvlar soni bir xil); ko''rinadigan qatorlar o''zgarmaydi',
  :'c4a' || '/' || :'c4b' || ' ' || :'c4i' || ' | '
  || (split_part((select setc from zz_c where step = 'c4a'), '/', 1)::int - split_part((select setc from zz_c where step = 'pa'), '/', 1)::int)::text || '='
  || (split_part((select setc from zz_c where step = 'c4b'), '/', 1)::int - split_part((select setc from zz_c where step = 'c4a'), '/', 1)::int)::text || ' '
  || ((select rowc from zz_c where step = 'c4b') - (select rowc from zz_c where step = 'pa'))::text,
  '^2/2 OK \| ([1-9])=\1 0$');

-- ========== (R) reja ==========
select zz.plan('U_SAL', $q$select id from public.student_phones where "parentPhone" >= '+9'$q$) as r_ph \gset
select zz.plan('U_SAL', $q$select id from public.my_sick_notes where "studentId" >= 'A'$q$) as r_sn \gset
select zz.plan('U_SAL', $q$select id from public.my_nurse_visits where "studentId" >= 'A'$q$) as r_nv \gset
select zz.chk('R01 sotuvchi: student_phones / my_sick_notes / my_nurse_visits — darvoza (One-Time Filter), jadval ko''rib chiqilmaydi',
  (:'r_ph' ~ 'One-Time Filter' and :'r_ph' ~ 'Seq Scan on student_private \(never executed\)')::text || ' '
  || (:'r_sn' ~ 'One-Time Filter' and :'r_sn' ~ 'Scan on sick_notes[^\n]*\(never executed\)')::text || ' '
  || (:'r_nv' ~ 'One-Time Filter' and :'r_nv' ~ 'Scan on nurse_visits[^\n]*\(never executed\)')::text,
  '^true true true$');
select zz.plan('U_SAL', $q$select id from public.student_private where "parentPhone" >= '+9'$q$) as r_pr \gset
select zz.plan('U_SAL', $q$select id from public.students where name >= 'S'$q$) as r_st \gset
select zz.chk('R02 sotuvchi: student_private / students — darvoza filtrning BIRINCHI sharti ($0 AND …): foydalanuvchi filtri hech qachon baholanmaydi',
  (:'r_pr' ~ 'Filter: \(\$0 AND ')::text || ' ' || (:'r_st' ~ 'Filter: \(\$0 AND ')::text, '^true true$');

-- ========== (F) ko'rinish huquqlari ==========
select zz.chk('F01 ko''rinish (karta / telefon / o''quvchi): Direktor hammasi; qabulxona karta + telefon; moliya va kassir — telefon; sinf xodimi — o''z sinfi o''quvchilari; ota-ona — o''ziniki; sotuvchi va farzandsiz — 0',
  (select string_agg(u || '=' || zz.as(u, 'select count(*)::text from public.student_private') || '/' || zz.as(u, 'select count(*)::text from public.student_phones')
                     || '/' || zz.as(u, 'select count(*)::text from public.students'), ' ' order by u)
     from unnest(array['U_DIR','U_REC','U_FM','U_KAS','U_TCH','U_HM','U_PA','U_PB','U_SAL','U_PAR0','U_BL','U_NUR','U_ACC']) u),
  '^U_ACC=0/0/0 U_BL=0/0/0 U_DIR=8/8/7 U_FM=0/8/0 U_HM=0/0/1 U_KAS=0/8/0 U_NUR=0/0/0 U_PA=3/3/2 U_PAR0=0/0/0 U_PB=1/1/1 U_REC=8/8/7 U_SAL=0/0/0 U_TCH=0/0/2$');
select zz.chk('F02 davomat / baho / tibbiy / e''lon: ota-ona — farzandlari, fan o''qituvchisi — o''z sinfi bahosi (davomat — sinf rahbari / kurator), sotuvchi — 0',
  (select string_agg(u || '=' || zz.as(u, 'select count(*)::text from public.attendance') || '/' || zz.as(u, 'select count(*)::text from public.grades')
                     || '/' || zz.as(u, 'select count(*)::text from public.my_sick_notes') || '/' || zz.as(u, 'select count(*)::text from public.my_nurse_visits')
                     || '/' || zz.as(u, 'select count(*)::text from public.class_announcements'), ' ' order by u)
     from unnest(array['U_PA','U_TCH','U_HM','U_KUR','U_SAL','U_PAR0']) u),
  '^U_HM=1/0/1/1/[0-9]+ U_KUR=1/0/1/1/[0-9]+ U_PA=2/2/2/2/2 U_PAR0=0/0/0/0/0 U_SAL=0/0/0/0/0 U_TCH=0/2/0/0/[0-9]+$');

select count(*)::text as yozilgan from zz.res \gset
select zz.chk('ZZ yozilgan tekshiruvlar soni = kutilgan', :'yozilgan', '^' || :'kutilgan' || '$');
select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL (jami ' || count(*) || ')' from zz.res;
rollback;
