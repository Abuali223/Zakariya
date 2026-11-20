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
--   (F) ko'rinish huquqlari o'zgarmagan: Direktor, qabulxona, moliya, kassir, sinf xodimi, farzandli / farzandsiz ota-ona, sotuvchi;
--   (G) darvozalar va plpgsql (3-mustaqil tekshiruv, 2026-11-20): yordamchilar plpgsql; o'ramli har SELECT policy darvoza bilan
--       boshlanadi; darvoza yolg'on => policy'ning har InitPlan'i yolg'on (darvoza qatorni yashirmaydi); rollar bo'yicha darvoza
--       matritsasi (kutilayotgan / holatsiz hisob va bog'lanish ham — 4-tekshiruv); huquqsiz foydalanuvchida filtr mos / mos emas —
--       chaqiruvlar soni bir xil; har darvoza — 2 chaqiruv (arzon); rls-initplan darvozani faqat monoton (AND / OR) policy'ga qo'yadi (G07).
--   Har chaqiruv haqiqiy rol bilan (authenticated / anon + JWT sub). Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida,
--   kanonik zanjirdan keyin (dev va jonli zanjir), migration/ papkasidan:
--     bash migration/chain.sh --no-lock-timeout | psql -d fx_sinov -q && (cd migration && psql -d fx_sinov -X -f test-rls-timing.sql)
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Ism / telefonlar to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\set kutilgan 26
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
  ('U_ACC','ac@example.org','Sinov Buxgalter','accountant','active',true,'[]','[]','[]','[]',null),
  ('U_TRE','tr@example.org','Sinov Gaznachi','treasurer','active',true,'[]','[]','[]','[]',null),
  ('U_DIRP','dp@example.org','Sinov Direktor Kutilmoqda','director','pending',false,'[]','[]','[]','[]',null),
  ('U_PARP','pp@example.org','Sinov Ota Kutilmoqda','parent','pending',false,'[]','[]','[]','[]',null),
  ('U_STP','sp@example.org','Sinov Xodim Kutilmoqda',null,'pending',false,'[]','[]','[]','[]',null),
  ('U_PARN','pn@example.org','Sinov Ota Holatsiz','parent','active',true,'[]','[]','[]','[]',null),
  ('U_PARE','pe@example.org','Sinov Ota Bosh holat','parent','active',true,'[]','[]','[]','[]',null);
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
  ('U_PB__IQ-DUP','U_PB','IQ-DUP','CODEX2','active'), ('U_BL__IQ-A','U_BL','IQ-A','CODEA','active'),
  ('U_PARP__IQ-B','U_PARP','IQ-B','','active'), ('U_STP__IQ-B','U_STP','IQ-B','','active'),
  ('U_PARN__IQ-C','U_PARN','IQ-C','',null), ('U_PARE__IQ-C','U_PARE','IQ-C','','');
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
    from unnest(array['U_PA','U_PB','U_BL','U_PAR0','U_SAL','U_DIR','U_TCH','U_PARN','U_PARE','U_PARP','U_STP','U_DIRP']) u, zz_keys;
select zz.chk('E01 my_child_sids / my_student_docs — owns_child / owns_student_doc bilan barcha foydalanuvchi va kalitlarda AYNAN bir xil (oldida — tekshirilgan juftlar)',
  (select count(*) || ':' || coalesce(string_agg(case when e_child <> 'true' or e_doc <> 'true' then u || '/' || k || '=' || e_child || e_doc end, ',' order by u, k), '')
     from zz_eq), '^[0-9]{2,}:$');
select zz.chk('E02 urug'' qiyin holatlarni qamraydi: owns_child — studentId, eski karta, yetim (hujjat «sa» — boshqa o''quvchining studentId''si, yo''q); takroriy studentId — faqat hujjat id; bloklangan — hech narsa | owns_student_doc',
  (select string_agg(u || ':' || (select coalesce(string_agg(k, ',' order by k), '-') from zz_eq e where e.u = x.u and e.orig ~ '^true'), ' ' order by u)
     from (select distinct u from zz_eq where u in ('U_PA', 'U_PB', 'U_BL', 'U_PARN', 'U_PARE')) x) || ' | '
  || (select string_agg(u || ':' || (select coalesce(string_agg(k, ',' order by k), '-') from zz_eq e where e.u = x.u and e.orig ~ 'true$'), ' ' order by u)
     from (select distinct u from zz_eq where u in ('U_PA', 'U_PB', 'U_PARN', 'U_PARE')) x),
  '^U_BL:- U_PA:IQ-A,IQ-L,IQ-ORPH,sl U_PARE:IQ-C,sc U_PARN:IQ-C,sc U_PB:sx2 \| U_PA:IQ-A,IQ-L,IQ-ORPH,sa,sl U_PARE:IQ-C,sc U_PARN:IQ-C,sc U_PB:sx2$');
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
                           and coalesce(app.ann_visible(%1$L::jsonb, %2$L::timestamptz), false)
                             = coalesce(app.rlsg_ann_visible5(app.is_admin() or app.is_zavuch(), app.rls_ann_staff_keys(), app.rls_ann_child_keys(), %1$L::jsonb, %2$L::timestamptz), false))::text', k, e)) as r
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
  + (select count(*) from public.my_nurse_visits where "studentId" >= 'A') + (select count(*) from public.class_announcements where title >= 'S')$q$) as c_pa \gset
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
-- Skan turi (Seq / Index / Bitmap Heap) statistikaga bog'liq — muhimi: darvoza One-Time Filter va jadval skani bajarilmagan.
select zz.chk('R01 sotuvchi: student_phones / my_sick_notes / my_nurse_visits — darvoza (One-Time Filter), jadval ko''rib chiqilmaydi',
  (:'r_ph' ~ 'One-Time Filter' and :'r_ph' ~ 'Scan (using [a-z0-9_]+ )?on student_private[^\n]*\(never executed\)')::text || ' '
  || (:'r_sn' ~ 'One-Time Filter' and :'r_sn' ~ 'Scan (using [a-z0-9_]+ )?on sick_notes[^\n]*\(never executed\)')::text || ' '
  || (:'r_nv' ~ 'One-Time Filter' and :'r_nv' ~ 'Scan (using [a-z0-9_]+ )?on nurse_visits[^\n]*\(never executed\)')::text,
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

-- ========== (G) darvozalar va plpgsql (3-mustaqil tekshiruv, 2026-11-20) ==========
select zz.chk('G01 policy / ko''rinishlardagi SECURITY DEFINER yordamchilar plpgsql (reja keshlanadi; SQL qolgani — faqat users_me: UPDATE, o''z qatori) | o''girilganlar >= 25 | namunalar',
  coalesce((with e as (select coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') as t
                         from pg_policy p join pg_class c on c.oid = p.polrelid where c.relnamespace = 'public'::regnamespace
                       union all
                       select pg_get_viewdef(c.oid) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('v', 'm')),
                 n as (select distinct m[1] as f from e, regexp_matches(e.t, 'app\.([a-z_0-9]+)\(', 'g') m)
            select string_agg(distinct p.proname, ',' order by p.proname) from n join pg_proc p on p.proname = n.f and p.pronamespace = 'app'::regnamespace
             where p.prosecdef and p.prolang = (select oid from pg_language where lanname = 'sql')), '-')
  || ' | ' || (select (count(*) >= 25)::text from pg_proc p
                where p.pronamespace = 'app'::regnamespace and p.prosecdef and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
                  and p.prosrc ~ '^\s*#variable_conflict use_column\s+begin\s+return \(')
  -- namunalar: policy'da bevosita ko'rinmaydigan ichki yordamchilar ham (rls-plpgsql zanjir oxirida bo'lmasa, ular SQL bo'lib qolardi)
  || ' | ' || (select coalesce(string_agg(case when l.lanname <> 'plpgsql' then p.proname end, ',' order by p.proname), '-') || '/' || count(*)
                 from pg_proc p join pg_language l on l.oid = p.prolang
                where p.oid in (select to_regprocedure(f) from unnest(array['app.rls_acl()', 'app.rls_gate_any()', 'app.rls_gate_private()', 'app.my_child_sids()',
                                  'app.my_student_docs()', 'app.my_child_class_keys()', 'app.my_staff_class_keys()', 'app.claim_row(text,text)',
                                  'app.is_teacher_for_class(text)', 'app.is_homeroom_for(text)', 'app.is_kurator_for(text)', 'app.teacher_has_subject(text)',
                                  'app.ann_can_write(jsonb)', 'app.role_set()', 'app.is_admin()']) f)),
  '^users_me \| true \| -/15$');
select zz.chk('G02 rol / to''plam yordamchilari va o''ramlardan (rls_in / rlsg_*) iborat har SELECT policy darvoza bilan BOSHLANADI (darvozasizlar | umumiy darvozalilardan namunalar)',
  coalesce((select string_agg(c.relname || '.' || p.polname, ',' order by c.relname, p.polname) from pg_policy p join pg_class c on c.oid = p.polrelid
             where c.relnamespace = 'public'::regnamespace and p.polcmd in ('r', '*') and pg_get_expr(p.polqual, p.polrelid) ~ 'app\.(rls_in|rlsg_[a-z0-9_]+)\('
               and pg_get_expr(p.polqual, p.polrelid) !~ '^\(\( SELECT app\.rls_gate_[a-z]+\(\) AS rls_gate_[a-z]+\) AND '), '-')
  || ' | ' || (select string_agg(c.relname, ',' order by c.relname) from pg_policy p join pg_class c on c.oid = p.polrelid
                where c.relnamespace = 'public'::regnamespace and pg_get_expr(p.polqual, p.polrelid) ~ '^\(\( SELECT app\.rls_gate_any\(\) AS rls_gate_any\) AND '
                  and c.relname in ('attendance', 'grades', 'class_announcements', 'student_health', 'subject_notes', 'characteristics', 'student_summaries', 'monitoring')),
  '^- \| attendance,characteristics,class_announcements,grades,monitoring,student_health,student_summaries,subject_notes$');
-- G03: darvoza faqat USTMA-UST to'plam: darvozali har policy'ning har InitPlan'i (rol yordamchisi, to'plam) darvozasi yolg'on bo'lgan
--   har foydalanuvchida yolg'on / bo'sh / NULL — demak darvoza hech qachon ko'rinadigan qatorni yashirmaydi (qolgan shart faqat AND / OR).
create temp table zz_gp on commit drop as
  select distinct substring(pg_get_expr(p.polqual, p.polrelid) from '^\(\( SELECT app\.(rls_gate_[a-z]+)\(\)') as gate, m[1] as expr
    from pg_policy p join pg_class c on c.oid = p.polrelid,
         regexp_matches(pg_get_expr(p.polqual, p.polrelid), '\( SELECT ((?:app\.[a-z_0-9]+\(\)|\(app\.is_admin\(\) OR app\.is_zavuch\(\)\)))(?: AS [a-z_0-9]+)?\)', 'g') m
   where c.relnamespace = 'public'::regnamespace and p.polcmd in ('r', '*') and pg_get_expr(p.polqual, p.polrelid) ~ '^\(\( SELECT app\.rls_gate_[a-z]+\(\)';
-- darvozali ko'rinishlar (student_phones, my_sick_notes, my_nurse_visits) — ularning darvozasi uchun ham xuddi shu ustma-ust to'plam qoidasi
insert into zz_gp
  select distinct substring(v.d from '\( SELECT app\.(rls_gate_[a-z]+)\(\) AS rls_gate_[a-z]+\)'), m[1]
    from (select pg_get_viewdef(c.oid) as d from pg_class c
           where c.relnamespace = 'public'::regnamespace and c.relkind in ('v', 'm') and pg_get_viewdef(c.oid) ~ '\( SELECT app\.rls_gate_[a-z]+\(\) AS rls_gate_[a-z]+\)') v,
         regexp_matches(v.d, '\( SELECT ((?:app\.[a-z_0-9]+\(\)|\(app\.is_admin\(\) OR app\.is_zavuch\(\)\)))(?: AS [a-z_0-9]+)?\)', 'g') m;
delete from zz_gp where expr = 'app.' || gate || '()';
create temp table zz_gv on commit drop as
  select u, g.gate, g.expr, zz.as(u, format('select app.%s()::text', g.gate)) as gv, zz.as(u, format('select coalesce((%s)::text, ''NULL'')', g.expr)) as ev
    from unnest(array['U_DIR','U_SAL','U_PAR0','U_PA','U_PB','U_BL','U_TCH','U_HM','U_KUR','U_ZAV','U_ADM','U_HRT','U_REC','U_FM','U_KAS','U_NUR','U_ACC','U_GHOST',
                      'U_TRE','U_DIRP','U_PARP','U_STP','U_PARN','U_PARE']) u,
         zz_gp g;
select zz.chk('G03 darvoza yolg''on => policy''ning har InitPlan''i yolg''on / bo''sh (buzilishlar | juft / darvoza yolg''on | asosiy to''plamlar qamralgan)',
  (select count(*) filter (where gv = 'false' and ev not in ('false', '{}', 'NULL')) || ':'
          || coalesce(string_agg(case when gv = 'false' and ev not in ('false', '{}', 'NULL') then u || '/' || gate || '/' || expr || '=' || ev end, ',' order by u, gate, expr), '')
          || ' | ' || count(*) || '/' || count(*) filter (where gv = 'false')
          || ' | ' || (select count(distinct expr) from zz_gp where expr ~ '^app\.(my_child_sids|my_student_docs|rls_class_staff|rls_ann_child_keys|rls_ann_staff_keys|is_admin|is_reception|is_nurse|is_finance|is_cashier)\(\)$')
     from zz_gv),
  '^0: \| [0-9]{3,}/[0-9]{2,} \| 10$');
select zz.chk('G04 darvozalar (any / private / students / phones / health): huquqsiz — 00000; farzandli ota-ona, Direktor, O''IBDO'' — 11111; qabulxona — 11110; sinf xodimi — 10101; moliya / kassir — 10010; hamshira / buxgalter — 10000',
  (select string_agg(u || '=' || zz.as(u, $q$select app.rls_gate_any()::int::text || app.rls_gate_private()::int::text || app.rls_gate_students()::int::text
                                                     || app.rls_gate_phones()::int::text || app.rls_gate_health()::int::text$q$), ' ' order by u)
     from unnest(array['U_ACC','U_ADM','U_BL','U_DIR','U_FM','U_GHOST','U_HM','U_HRT','U_KAS','U_KUR','U_NUR','U_PA','U_PAR0','U_PB','U_REC','U_SAL','U_TCH','U_ZAV',
                       'U_TRE','U_DIRP','U_PARP','U_STP','U_PARN','U_PARE']) u),
  '^U_ACC=10000 U_ADM=10101 U_BL=00000 U_DIR=11111 U_DIRP=11111 U_FM=10010 U_GHOST=00000 U_HM=10101 U_HRT=10101 U_KAS=10010 U_KUR=10101 U_NUR=10000 U_PA=11111 U_PAR0=00000 U_PARE=11111 U_PARN=11111 U_PARP=11111 U_PB=11111 U_REC=11110 U_SAL=00000 U_STP=11111 U_TCH=10101 U_TRE=10010 U_ZAV=11111$');
-- G05: huquqsiz foydalanuvchida (sotuvchi, farzandsiz ota-ona, bloklangan, users yozuvi yo'q) filtr yashirin qatorga MOS kelsa ham, kelmasa
--   ham — app funksiyalari chaqiruvlari soni AYNAN bir xil (telefon / ism / matn ustunlari: indeks yo'q). Indeksli kalit (studentId) bo'yicha
--   farq — faqat darvoza (rls_gate_any + rls_acl = 2 chaqiruv; seq scan bo'lsa 0) — hujjatlashtirilgan qoldiq (~40 mks).
create or replace function zz.allcalls() returns bigint language sql as $$
  select coalesce(sum(pg_stat_get_xact_function_calls(p.oid)), 0)::bigint from pg_proc p where p.pronamespace = 'app'::regnamespace $$;
create or replace function zz.det(p_uid text) returns text language plpgsql as $$
declare c0 bigint; c1 bigint; c2 bigint; c3 bigint; c4 bigint; rh text; rm text; ih text; im text;
begin
  c0 := zz.allcalls();
  rh := zz.as(p_uid, $q$select ((select count(*) from public.students where name = 'Sinov Bola A') + (select count(*) from public.student_private where "parentPhone" = '+998001110001')
    + (select count(*) from public.student_phones where "parentPhone" = '+998001110001') + (select count(*) from public.attendance where month = '2026-11')
    + (select count(*) from public.grades where year = '2026-2027') + (select count(*) from public.class_announcements where title = 'Sinov')
    + (select count(*) from public.my_sick_notes where "fromDay" = '2026-11-10') + (select count(*) from public.my_nurse_visits where complaint = 'ZZ'))::text$q$);
  c1 := zz.allcalls();
  rm := zz.as(p_uid, $q$select ((select count(*) from public.students where name = 'Sinov Bola Q') + (select count(*) from public.student_private where "parentPhone" = '+998001119999')
    + (select count(*) from public.student_phones where "parentPhone" = '+998001119999') + (select count(*) from public.attendance where month = '2026-12')
    + (select count(*) from public.grades where year = '2025-2026') + (select count(*) from public.class_announcements where title = 'Yoq')
    + (select count(*) from public.my_sick_notes where "fromDay" = '2026-11-12') + (select count(*) from public.my_nurse_visits where complaint = 'YY'))::text$q$);
  c2 := zz.allcalls();
  ih := zz.as(p_uid, $q$select count(*)::text from public.attendance where "studentId" = 'IQ-A'$q$);
  c3 := zz.allcalls();
  im := zz.as(p_uid, $q$select count(*)::text from public.attendance where "studentId" = 'IQ-NO'$q$);
  c4 := zz.allcalls();
  return rh || '/' || rm || ' ' || ((c1 - c0) = (c2 - c1))::text || ' ' || ih || '/' || im || ' ' || ((c3 - c2) - (c4 - c3))::text;
end $$;
select zz.chk('G05 huquqsizlar: filtr mos / mos emas — chaqiruvlar soni bir xil (0 qator); indeksli kalit — farq faqat darvoza (0 yoki 2)',
  (select string_agg(u || '=' || zz.det(u), ' ' order by u) from unnest(array['U_BL','U_GHOST','U_PAR0','U_SAL']) u),
  '^U_BL=0/0 true 0/0 (0|2) U_GHOST=0/0 true 0/0 (0|2) U_PAR0=0/0 true 0/0 (0|2) U_SAL=0/0 true 0/0 (0|2)$');
-- G06: darvoza arzon — har darvoza AYNAN 2 chaqiruv (o'zi + app.rls_acl, bitta so'rov); avval 6–12 ta ichma-ich chaqiruv edi (~150 mks).
create or replace function zz.gcost(p_uid text, p_gate text) returns bigint language plpgsql as $$
declare c0 bigint; v text;
begin c0 := zz.allcalls(); v := zz.as(p_uid, format('select app.%s()::text', p_gate)); return zz.allcalls() - c0; end $$;
select zz.chk('G06 har darvoza (5 ta) har rolda (sotuvchi, farzandli ota-ona, o''qituvchi, Direktor, users yozuvi yo''q) — 2 chaqiruv',
  (select string_agg(distinct zz.gcost(u, g)::text, ',') from unnest(array['U_SAL','U_PA','U_TCH','U_DIR','U_GHOST']) u,
          unnest(array['rls_gate_any','rls_gate_private','rls_gate_students','rls_gate_phones','rls_gate_health']) g),
  '^2$');

-- G08: oxirgi ta'riflar o'z darvozasi bilan (rls-timing.sql zanjirda barcha boshqa migratsiyalardan keyin; keyingi migratsiya ularni qayta
--   yaratsa — umumiy rls_gate_any yoki darvozasiz bo'lib, vaqt orqali sizish qaytardi; 5-mustaqil tekshiruv).
select zz.chk('G08 priv_sel / students_sel — rls_gate_private / rls_gate_students; student_phones — phones; my_sick_notes / my_nurse_visits — health',
  (select string_agg(c.relname || '.' || p.polname || '=' || coalesce(substring(pg_get_expr(p.polqual, p.polrelid) from '^\(\( SELECT app\.(rls_gate_[a-z]+)\(\)'), '-'), ',' order by c.relname)
     from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relnamespace = 'public'::regnamespace and (c.relname, p.polname) in (('student_private', 'priv_sel'), ('students', 'students_sel')))
  || ' | ' || (select string_agg(c.relname || '=' || coalesce(substring(pg_get_viewdef(c.oid) from 'SELECT app\.(rls_gate_[a-z]+)\(\)'), '-'), ',' order by c.relname)
                from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('student_phones', 'my_sick_notes', 'my_nurse_visits')),
  '^student_private\.priv_sel=rls_gate_private,students\.students_sel=rls_gate_students \| my_nurse_visits=rls_gate_health,my_sick_notes=rls_gate_health,student_phones=rls_gate_phones$');

-- G07: rls-initplan darvozani FAQAT monoton shartga qo'yadi (taniqli atomlarning AND / OR i); NOT / CASE / IS NULL / COALESCE / = false —
--   darvozasiz (aks holda darvoza ko'rinadigan qatorni yashirishi mumkin edi). Sinov jadvali tranzaksiya ichida, oxirida ROLLBACK.
--   Fayl qayta ishga tushirilganda boshqa hech bir policy o'zgarmaydi (idempotent — oxirgi qism; 5-mustaqil tekshiruv).
create temp table zz_pol0 on commit drop as
  select polrelid, polname, pg_get_expr(polqual, polrelid) as q, pg_get_expr(polwithcheck, polrelid) as w from pg_policy;
create table public.zz_np (id text primary key, sid text);
alter table public.zz_np enable row level security;
create policy np_not  on public.zz_np for select using (app.owns_child(sid) or not app.is_staff());
create policy np_case on public.zz_np for select using (case when app.is_staff() then false else app.owns_child(sid) end);
create policy np_null on public.zz_np for select using (app.owns_child(sid) or (app.is_staff() is null));
create policy np_coal on public.zz_np for select using (coalesce(app.owns_child(sid) and app.is_staff(), true));
create policy np_eqf  on public.zz_np for select using (app.owns_child(sid) = false);
create policy np_pos  on public.zz_np for select using (app.owns_child(sid) or app.is_staff());
\set iqror_chain 1
\ir rls-initplan.sql
select zz.chk('G07 rls-initplan: darvoza faqat monoton policy''ga (NOT / CASE / IS NULL / COALESCE / = false — darvozasiz; AND / OR — darvozali); qayta ishga tushirish boshqa policy''ni o''zgartirmaydi',
  (select string_agg(polname || '=' || (pg_get_expr(polqual, polrelid) ~ '^\(\( SELECT app\.rls_gate_')::text, ',' order by polname)
     from pg_policy where polrelid = 'public.zz_np'::regclass)
  || ' | ' || coalesce((select string_agg(o.polrelid::regclass::text || '.' || o.polname, ',' order by 1)
                          from zz_pol0 o join pg_policy p on p.polrelid = o.polrelid and p.polname = o.polname
                         where pg_get_expr(p.polqual, p.polrelid) is distinct from o.q or pg_get_expr(p.polwithcheck, p.polrelid) is distinct from o.w), '-'),
  '^np_case=false,np_coal=false,np_eqf=false,np_not=false,np_null=false,np_pos=true \| -$');
select count(*)::text as yozilgan from zz.res \gset
select zz.chk('ZZ yozilgan tekshiruvlar soni = kutilgan', :'yozilgan', '^' || :'kutilgan' || '$');
select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL (jami ' || count(*) || ')' from zz.res;
rollback;
