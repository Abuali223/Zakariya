-- =====================================================================
-- test-audit-10-qabul.sql — «Qabul» bo'limi (audit 2026-11-18, A1-05 / A1-08 / A1-09) sinovi:
--   * class_seat_stats(): «Sinflar»da yaratilgan, lekin faol o'quvchisi yo'q sinf ham chiqadi (band = 0) — yangi o'quv yili sinfiga
--     sig'im kiritish uchun (A1-08); o'quvchili sinflar soni, takrorsizlik va kim chaqira olishi o'zgarmagan;
--   * admin.html qaysi baza qoidalariga tayanadi (shartnoma): o'quvchi KARTASINI faqat direktor / qabulxona yaratadi — Ma'muriyat
--     rahbari (admin_head) va eski 'admin' — yo'q, lekin ikkalasi murojaatni yangilaydi va sig'im yozadi (A1-05: «✅ Qabul qilish» va
--     canAdmWrite / canAdmSeats); qabulxona maoshli «teachers» jadvalini ko'rmaydi, teachers_public'dan ism oladi (A1-09).
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub) — RLS va GRANT haqiqiy.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-audit-10-qabul.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-10-qabul.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
set local iqror.migrating = '1';
insert into public.users (id, email, role, status) values
  ('U_DIR','d@example.org','director','active'), ('U_REC','r@example.org','reception','active'), ('U_AH','ah@example.org','admin_head','active'),
  ('U_ADM','adm@example.org','admin','active'), ('U_MKT','m@example.org','marketing_mgr','active'), ('U_TEA','t@example.org','teacher','active')
on conflict (id) do update set role = excluded.role, status = excluded.status;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "stopFrom", "exitAt", "exitReason") values
  ('IQ-0301','IQ-0301','Sinov Bir',5,'A','uz','','',null,null),
  ('IQ-0302','IQ-0302','Sinov Ikki',5,'A','uz','sinov','',null,null),
  ('IQ-0303','IQ-0303','Sinov Muzlagan',6,'B','uz','muzlatilgan','2026-10-01',null,null),
  ('IQ-0304','IQ-0304','Sinov Chiqqan',8,'A','uz','chiqdi','2026-10-31','2026-10-31','kochdi'),
  ('IQ-0305','IQ-0305','Sinov Harfsiz',9,'','uz','','',null,null)
on conflict (id) do nothing;
insert into public.classes (id, grade, lang, letter, "order") values
  ('tq_c1', 5, 'uz', 'A', 1),      -- o'quvchili sinf (takrorlanmasin)
  ('tq_c2', 1, 'uz', 'C', 2),      -- yangi o'quv yili sinfi — hali o'quvchisiz
  ('tq_c3', 7, 'ru', 'B', 3),      -- rus sinfi, o'quvchisiz
  ('tq_c4', 6, 'uz', 'B', 4),      -- faqat muzlatilgan o'quvchi bor
  ('tq_c5', 9, 'uz', null, 5)      -- harfsiz sinf: kalit uz-9-- (harfsiz o'quvchi bilan bitta qator)
on conflict (id) do nothing;
insert into public.class_seats (id, capacity) values ('uz-1-C', 24) on conflict (id) do update set capacity = excluded.capacity;
insert into public.enrollments (id, name, phone, grade, direction, status) values ('tq_e1','Sinov Murojaat','+998000880001','5-sinf','Rus sinf','yangi')
on conflict (id) do nothing;
insert into public.teachers (id, "teacherId", name, "subject_uz", "baseSalary", salary) values ('tq_t1','IQT-901','Sinov O''qituvchi','Matematika',5000000,5000000)
on conflict (id) do nothing;
set local iqror.migrating = '';

create schema if not exists zz;
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  if p_uid is null then execute 'set local role anon'; else execute 'set local role authenticated'; end if;
  begin
    execute p_q into r;
  exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, p_got ~ p_pat); end $$;

-- ===== A1-08: class_seat_stats — «Sinflar»dagi o'quvchisiz sinflar ham =====
select zz.chk('S01 qabulxona: yangi 1-sinf «C» (o''quvchisiz, sig''im 24) — band 0',
  zz.as('U_REC', $q$select string_agg("classKey" || '=' || active || '/' || coalesce(capacity::text, '-'), ',') from public.class_seat_stats() where "classKey" = 'uz-1-C'$q$), '^uz-1-C=0/24$');
select zz.chk('S02 rus sinfi (o''quvchisiz, sig''im yo''q) — band 0',
  zz.as('U_REC', $q$select string_agg("classKey" || '=' || active || '/' || coalesce(capacity::text, '-'), ',') from public.class_seat_stats() where "classKey" = 'ru-7-B'$q$), '^ru-7-B=0/-$');
select zz.chk('S03 faqat muzlatilgan o''quvchisi bor sinf — «Sinflar»da bo''lgani uchun chiqadi, band 0',
  zz.as('U_REC', $q$select string_agg("classKey" || '=' || active, ',') from public.class_seat_stats() where "classKey" = 'uz-6-B'$q$), '^uz-6-B=0$');
select zz.chk('S04 o''quvchili sinf — faol + sinov (2), «Sinflar»dagi yozuvi bilan takrorlanmaydi',
  zz.as('U_REC', $q$select string_agg("classKey" || '=' || active, ',') from public.class_seat_stats() where "classKey" = 'uz-5-A'$q$), '^uz-5-A=2$');
select zz.chk('S05 harfsiz sinf: o''quvchi va «Sinflar» yozuvi bitta kalitda (uz-9--), band 1',
  zz.as('U_REC', $q$select string_agg("classKey" || '=' || active, ',') from public.class_seat_stats() where "classKey" = 'uz-9--'$q$), '^uz-9--=1$');
select zz.chk('S06 chiqqan o''quvchining (sinfi «Sinflar»da yo''q) sinfi chiqmaydi; takrorlangan kalit yo''q',
  zz.as('U_REC', $q$select (count(*) filter (where "classKey" = 'uz-8-A'))::text || '/' || (count(*) - count(distinct "classKey"))::text from public.class_seat_stats()$q$), '^0/0$');
select zz.chk('S07 marketing va ma''muriyat rahbari ham ko''radi (o''zgarmagan)',
  zz.as('U_MKT', $q$select count(*)::text from public.class_seat_stats() where "classKey" = 'uz-1-C'$q$) || '|' || zz.as('U_AH', $q$select count(*)::text from public.class_seat_stats() where "classKey" = 'uz-1-C'$q$), '^1\|1$');
select zz.chk('S08 o''qituvchi — ruxsat yo''q (o''zgarmagan)', zz.as('U_TEA', $q$select count(*)::text from public.class_seat_stats()$q$), '^ERR 42501');
select zz.chk('S09 anon — ruxsat yo''q', zz.as(null, $q$select count(*)::text from public.class_seat_stats()$q$), '^ERR 42501');

-- ===== A1-05 shartnomasi (admin.html canCreateStudents / canAdmWrite / canAdmSeats shunga mos) =====
select zz.chk('R01 ma''muriyat rahbari o''quvchi kartasini YARATA OLMAYDI (students_ins: direktor / qabulxona)',
  zz.as('U_AH', $q$insert into public.students (id, "studentId", name, grade, lang) values ('IQ-0390','IQ-0390','Sinov AH',1,'uz') returning id$q$), '^ERR 42501');
select zz.chk('R02 eski «admin» roli ham yarata olmaydi',
  zz.as('U_ADM', $q$insert into public.students (id, "studentId", name, grade, lang) values ('IQ-0391','IQ-0391','Sinov ADM',1,'uz') returning id$q$), '^ERR 42501');
select zz.chk('R03 qabulxona yaratadi', zz.as('U_REC', $q$insert into public.students (id, "studentId", name, grade, lang) values ('IQ-0392','IQ-0392','Sinov REC',1,'uz') returning id$q$), '^IQ-0392$');
select zz.chk('R04 eski «admin» murojaatni yangilaydi (enr_upd: is_admin_head) — UI endi yozish rejimida',
  zz.as('U_ADM', $q$update public.enrollments set status = 'boglanildi' where id = 'tq_e1' returning status$q$), '^boglanildi$');
select zz.chk('R05 eski «admin» sig''im yozadi (cs_ins / cs_upd)',
  zz.as('U_ADM', $q$insert into public.class_seats (id, capacity) values ('ru-7-B', 20) on conflict (id) do update set capacity = excluded.capacity returning capacity::text$q$), '^20$');
select zz.chk('R06 qabulxona sig''im yozmaydi (o''zgarmagan)',
  zz.as('U_REC', $q$insert into public.class_seats (id, capacity) values ('uz-4-A', 5) returning capacity::text$q$), '^ERR 42501');

-- ===== A1-09 shartnomasi: sinov darsi o'qituvchilari =====
select zz.chk('T01 qabulxona maoshli «teachers» jadvalini ko''rmaydi (0 qator — xato emas, shuning uchun ro''yxat bo''sh edi)',
  zz.as('U_REC', $q$select count(*)::text from public.teachers$q$), '^0$');
select zz.chk('T02 qabulxona teachers_public''dan ism oladi (maoshsiz)', zz.as('U_REC', $q$select string_agg(name, ',') from public.teachers_public where id = 'tq_t1'$q$), '^Sinov O''qituvchi$');
select zz.chk('T03 teachers_public''da maosh ustuni yo''q', (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'teachers_public' and column_name in ('salary', 'baseSalary', 'phone')), '^0$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
