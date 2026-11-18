-- =====================================================================
-- test-student-archive.sql — student-archive.sql (O'quvchilar arxivi, egasi 2026-11-18) sinovi: student_certificate
--   (ma'lumotnoma uchun o'zlashtirish yig'masi — kim chaqira oladi, to'qnash ID, davomat / monitoring / xarakteristika qoidasi)
--   va students_billing (chiqqan kun + faqat bitiruv belgisi; ichki ketish sababi moliya rollariga ochilmaydi).
--   Har chaqiruv haqiqiy rol bilan (anon yoki authenticated + JWT sub) — RLS va GRANT haqiqiy.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-student-archive.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-student-archive.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
set local iqror.migrating = '1';
insert into public.users (id, email, role, status) values
  ('U_DIR','d@x','director','active'), ('U_ZAV','z@x','zavuch','active'), ('U_REC','r@x','reception','active'),
  ('U_TEA','t@x','teacher','active'), ('U_KAS','k@x','kassir','active'), ('U_PA','pa@x','parent','active'), ('U_NUR','n@x','nurse','active')
on conflict (id) do update set role = excluded.role, status = excluded.status;
update public.users set "assignedClasses" = '["uz-7-A"]'::jsonb, "homeroomClasses" = '["uz-7-A"]'::jsonb where id = 'U_TEA';
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "stopFrom", "exitAt", "exitReason") values
  ('IQ-0201','IQ-0201','Sinov Chiqqan',7,'A','uz','chiqdi','2026-10-31','2026-10-31','soglik'),
  ('IQ-0202','IQ-0202','Sinov Bitirgan',11,'A','uz','chiqdi','2026-05-31','2026-05-31','bitirdi'),
  ('IQ-0203','IQ-0203','Sinov Faol',7,'A','uz','','',null,null),
  -- eski import to'qnashuvi: docK.studentId = boshqa bolaning doc id'si
  ('docK','IQ-0999','Sinov Toqnash A',8,'A','uz','','',null,null),
  ('IQ-0999','','Sinov Toqnash B',8,'B','uz','','',null,null)
on conflict (id) do nothing;
insert into public.child_claims (id, uid, "studentId", code, status) values ('cc_pa','U_PA','IQ-0201','X','active') on conflict (id) do nothing;
insert into public.grades (id, "studentId", "classKey", year, subjects) values
  ('IQ-0201__2026-2027','IQ-0201','uz-7-A','2026-2027','{"Matematika":{"q1":5,"q2":4},"Ona tili":{"q1":4}}'),
  ('IQ-0201__2025-2026','IQ-0201','uz-6-A','2025-2026','{"Matematika":{"q4":5}}');
insert into public.attendance (id, "studentId", "classKey", month, days) values
  ('IQ-0201__2026-10','IQ-0201','uz-7-A','2026-10','{"01":"present","02":"late","03":"absent","04":"sick","05":"excused","06":"present"}'),
  ('IQ-0203__2026-10','IQ-0203','uz-7-A','2026-10','{"01":"absent"}');
insert into public.monitoring (id, "studentId", "classKey", subject, period, score, status) values
  ('IQ-0201__2026-09__mat','IQ-0201','uz-7-A','Matematika','2026-09',90,'approved'),
  ('IQ-0201__2026-10__mat','IQ-0201','uz-7-A','Matematika','2026-10',81,'approved'),
  ('IQ-0201__2026-10__ona','IQ-0201','uz-7-A','Ona tili','2026-10',10,'pending');
insert into public.characteristics (id, "studentId", "classKey", year, quarter, term, text) values
  ('IQ-0201__2026-2027-q1','IQ-0201','uz-7-A','2026-2027','q1','2026-2027-q1','Birinchi chorak'),
  ('IQ-0201__2026-2027-q2','IQ-0201','uz-7-A','2026-2027','q2','2026-2027-q2','Ikkinchi chorak'),
  ('IQ-0201__2026-2027-q3','IQ-0201','uz-7-A','2026-2027','q3','2026-2027-q3','   ');
insert into public.olympiads ("studentId", "classKey", subject, name, level, result, date) values
  ('IQ-0201','uz-7-A','Matematika','Tuman olimpiadasi','tuman','2','2026-10-12');
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

-- ===== student_certificate: kim chaqira oladi =====
select zz.chk('A01 direktor', zz.as('U_DIR', $q$select public.student_certificate('IQ-0201')->>'sid'$q$), '^IQ-0201$');
select zz.chk('A02 O''IBDO''', zz.as('U_ZAV', $q$select public.student_certificate('IQ-0201')->>'sid'$q$), '^IQ-0201$');
select zz.chk('A03 qabulxona (hujjat beradi — baho jadvalini o''zi o''qiy olmasa ham)', zz.as('U_REC', $q$select public.student_certificate('IQ-0201')->>'sid'$q$), '^IQ-0201$');
select zz.chk('A04 qabulxona baho / davomat / monitoring / xarakteristika jadvallarini to''g''ridan-to''g''ri o''qimaydi (D6 o''zgarmagan)',
  zz.as('U_REC', $q$select ((select count(*) from public.grades) + (select count(*) from public.attendance) + (select count(*) from public.monitoring) + (select count(*) from public.characteristics))::text$q$), '^0$');
select zz.chk('A05 o''qituvchi (sinf rahbari ham) — yo''q', zz.as('U_TEA', $q$select public.student_certificate('IQ-0201')::text$q$), '^ERR 42501');
select zz.chk('A06 kassir — yo''q', zz.as('U_KAS', $q$select public.student_certificate('IQ-0201')::text$q$), '^ERR 42501');
select zz.chk('A07 hamshira — yo''q', zz.as('U_NUR', $q$select public.student_certificate('IQ-0201')::text$q$), '^ERR 42501');
select zz.chk('A08 ota-ona (o''z farzandi ham) — yo''q', zz.as('U_PA', $q$select public.student_certificate('IQ-0201')::text$q$), '^ERR 42501');
select zz.chk('A09 anon — yo''q', zz.as(null, $q$select public.student_certificate('IQ-0201')::text$q$), '^ERR 42501');
select zz.chk('A10 to''qnash eski ID — P0002', zz.as('U_DIR', $q$select public.student_certificate('IQ-0999')::text$q$), '^ERR P0002');
select zz.chk('A11 doc id bilan (to''qnash juftning biri) — o''z qatori, kanonik kalit IQ-0999', zz.as('U_DIR', $q$select public.student_certificate('docK')->>'sid'$q$), '^IQ-0999$');
select zz.chk('A12 mavjud emas / bo''sh — P0002', zz.as('U_DIR', $q$select public.student_certificate('IQ-7777')::text$q$) || zz.as('U_DIR', $q$select public.student_certificate('')::text$q$), '^ERR P0002.*ERR P0002');

-- ===== yig'ma qoidalari =====
select zz.chk('B01 baholar — barcha yillar, yil tartibida', zz.as('U_REC', $q$select string_agg(e->>'year' || ':' || (e->'subjects'->'Matematika')::text, ' | ' order by ord) from jsonb_array_elements(public.student_certificate('IQ-0201')->'grades') with ordinality t(e, ord)$q$),
  '^2025-2026:\{"q4": 5\} \| 2026-2027:\{"q1": 5, "q2": 4\}$');
select zz.chk('B02 davomat: kelgan 2, kechikkan 1, kelmagan 1, bemor 1; jami 4 (bemor va sababli kirmaydi)',
  zz.as('U_REC', $q$select a->>'present' || '/' || (a->>'late') || '/' || (a->>'absent') || '/' || (a->>'sick') || '/' || (a->>'total') from (select public.student_certificate('IQ-0201')->'att' a) x$q$), '^2/1/1/1/4$');
select zz.chk('B03 monitoring — faqat tasdiqlangan, fan bo''yicha o''rtacha (90, 81 -> 86); kutilayotgan kirmaydi',
  zz.as('U_REC', $q$select (public.student_certificate('IQ-0201')->'mon')::text$q$), '^\[\{"avg": 86, "subject": "Matematika"\}\]$');
select zz.chk('B04 xarakteristika — oxirgi bo''sh bo''lmagan davr', zz.as('U_REC', $q$select (public.student_certificate('IQ-0201')->'char'->>'term') || ' ' || (public.student_certificate('IQ-0201')->'char'->>'text')$q$), '^2026-2027-q2 Ikkinchi chorak$');
select zz.chk('B05 yutuqlar', zz.as('U_REC', $q$select (public.student_certificate('IQ-0201')->'ach'->0->>'name') || '/' || (public.student_certificate('IQ-0201')->'ach'->0->>'result')$q$), '^Tuman olimpiadasi/2$');
select zz.chk('B06 yozuvsiz o''quvchi — bo''sh ro''yxatlar, davomat nol, xarakteristika yo''q',
  zz.as('U_DIR', $q$select (r->'grades')::text || ' ' || (r->'mon')::text || ' ' || (r->'ach')::text || ' ' || (r->'att'->>'total') || ' ' || coalesce(r->>'char', 'null') from (select public.student_certificate('IQ-0202') r) x$q$), '^\[\] \[\] \[\] 0 null$');
select zz.chk('B07 boshqa o''quvchining davomati qo''shilmaydi', zz.as('U_DIR', $q$select public.student_certificate('IQ-0203')->'att'->>'absent'$q$), '^1$');

-- ===== students_billing: chiqqan kun + faqat bitiruv belgisi =====
select zz.chk('V01 kassir: chiqqan kun ko''rinadi', zz.as('U_KAS', $q$select string_agg(id || ':' || coalesce("exitAt", '-'), ',' order by id) from public.students_billing where id like 'IQ-020%'$q$),
  '^IQ-0201:2026-10-31,IQ-0202:2026-05-31,IQ-0203:-$');
select zz.chk('V02 kassir: ketish sababi yashirin (sog''liq — null), bitiruvchi — ''bitirdi''', zz.as('U_KAS', $q$select string_agg(id || ':' || coalesce("exitReason", 'null'), ',' order by id) from public.students_billing where id like 'IQ-020%'$q$),
  '^IQ-0201:null,IQ-0202:bitirdi,IQ-0203:null$');
select zz.chk('V03 hamshira ham xuddi shunday', zz.as('U_NUR', $q$select coalesce("exitReason", 'null') from public.students_billing where id = 'IQ-0201'$q$), '^null$');
select zz.chk('V04 direktor xom jadvaldan to''liq sababni ko''radi (o''zgarmagan)', zz.as('U_DIR', $q$select "exitReason" from public.students where id = 'IQ-0201'$q$), '^soglik$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
