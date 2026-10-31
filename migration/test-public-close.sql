-- =====================================================================
-- test-public-close.sql — public-close.sql (D6/D8/D9, PKG-1) sinovi: child_card, issue_doc_token, verify_doc,
--   ism triggerlari (yutuq/sharh), ism zaxirasi RLS, students_public yo'qligi, storage papka ro'yxati.
--   Har chaqiruv haqiqiy rol bilan (anon yoki authenticated + JWT sub) — RLS va GRANT haqiqiy.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-public-close.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK — bazada hech narsa qolmaydi. O'quvchilar jadvali bo'sh
--   bo'lmasa (jonli baza) — darhol to'xtaydi. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-public-close.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
set local iqror.migrating = '1';   -- urug' change_log'ga yozilmasin
insert into public.users (id, email, role, status) values
  ('U_DIR','d@x','director','active'), ('U_ZAV','z@x','zavuch','active'), ('U_REC','r@x','reception','active'),
  ('U_RECB','rb@x','reception','blocked'), ('U_TEA','t@x','teacher','active'), ('U_KAS','k@x','kassir','active'),
  ('U_HR','h@x','hr','active'), ('U_FIN','f@x','finance_mgr','active'),
  ('U_PA','pa@x','parent','active'), ('U_PB','pb@x','parent','active'), ('U_STU','s@x','student','active'),
  ('U_NOCH','n@x','parent','active'), ('U_PREV','pv@x','parent','active')
on conflict (id) do update set role = excluded.role, status = excluded.status;
update public.users set "assignedClasses" = '["uz-7-A"]'::jsonb, "homeroomClasses" = '["uz-7-A"]'::jsonb where id = 'U_TEA';
-- 7-A (uz): S1 90, S2 95, S3 85, S4 99 (ketgan — sanalmaydi), S5 97 (kelajakda ketadi — sanaladi), S8 ball yo'q.
insert into public.students (id, "studentId", name, grade, "classLetter", lang, score, "payStatus", "stopFrom") values
  ('docS1','IQ-0101','Aziza Karimova',7,'A','uz',90,'',''),
  ('IQ-0102','IQ-0102','Karimova Malika',7,'A','uz',95,'',''),
  ('IQ-0103','IQ-0103','Bekzod Rahimov',7,'A','uz',85,'',''),
  ('IQ-0104','IQ-0104','Ketgan Bola',7,'A','uz',99,'chiqdi','2026-09-01'),
  ('IQ-0105','IQ-0105','Keyin Ketadi',7,'A','uz',97,'chiqdi','2099-01-01'),
  ('IQ-0106','IQ-0106','Boshqa Sinf',7,'B','uz',100,'',''),
  ('IQ-0107','IQ-0107','Rus Sinf',7,'A','ru',100,'',''),
  ('IQ-0108','IQ-0108','Balsiz Bola',7,'A',null,null,'','')
on conflict (id) do nothing;
insert into public.student_private (id, pinfl, health, "parentPhone") values ('docS1','12345678901234','Sog''lom','998900000001')
on conflict (id) do nothing;
insert into public.child_claims (id, uid, "studentId", code, status) values
  ('cc_pa','U_PA','IQ-0101','X','active'), ('cc_pb','U_PB','IQ-0103','X','active'),
  ('cc_stu','U_STU','IQ-0102','X','active'), ('cc_prev','U_PREV','IQ-0101','X','revoked')
on conflict (id) do nothing;
-- storage: Supabase'dagi kabi grantlar va (bucket_id, name) noyobligi (upsert uchun)
grant usage on schema storage to anon, authenticated;
grant all on storage.objects to anon, authenticated;
create unique index if not exists sobj_bucket_name on storage.objects (bucket_id, name);
insert into storage.objects (bucket_id, name) values ('public','images/students/1_a.jpg'), ('public','images/news/2_b.jpg')
on conflict do nothing;
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

-- ===== child_card =====
select zz.chk('C01 ota-ona o''z farzandi (studentId) -> rank 3 / size 5', zz.as('U_PA', $q$select public.child_card('IQ-0101')::text$q$), '^\{"rank": 3, "size": 5\}$');
select zz.chk('C02 ota-ona o''z farzandi (doc id bilan)', zz.as('U_PA', $q$select public.child_card('docS1')::text$q$), '^\{"rank": 3, "size": 5\}$');
select zz.chk('C03 o''quvchi o''zi (rank 2: faqat 97 yuqori)', zz.as('U_STU', $q$select public.child_card('IQ-0102')::text$q$), '^\{"rank": 2, "size": 5\}$');
select zz.chk('C04 ota-ona BEGONA bola', zz.as('U_PA', $q$select public.child_card('IQ-0103')::text$q$), '^ERR 42501');
select zz.chk('C05 boshqa ota-ona', zz.as('U_PB', $q$select public.child_card('IQ-0101')::text$q$), '^ERR 42501');
select zz.chk('C06 bekor qilingan bog''lanish', zz.as('U_PREV', $q$select public.child_card('IQ-0101')::text$q$), '^ERR 42501');
select zz.chk('C07 farzandsiz ota-ona', zz.as('U_NOCH', $q$select public.child_card('IQ-0101')::text$q$), '^ERR 42501');
select zz.chk('C08 o''qituvchi (sinf rahbari ham)', zz.as('U_TEA', $q$select public.child_card('IQ-0101')::text$q$), '^ERR 42501');
select zz.chk('C09 direktor (egasi emas)', zz.as('U_DIR', $q$select public.child_card('IQ-0101')::text$q$), '^ERR 42501');
select zz.chk('C10 anon', zz.as(null, $q$select public.child_card('IQ-0101')::text$q$), '^ERR 42501 permission denied');
select zz.chk('C11 bo''sh ID', zz.as('U_PA', $q$select public.child_card('')::text$q$), '^ERR 42501');
select zz.chk('C12 javobda boshqa bola ismi/bali yo''q (faqat rank,size kalitlari)', zz.as('U_PA', $q$select string_agg(k, ',' order by k) from jsonb_object_keys(public.child_card('IQ-0101')) k$q$), '^rank,size$');
-- ball kiritilmagan o'quvchi: rank null (U_PB'ga vaqtincha IQ-0108 bog'lanishi)
insert into public.child_claims (id, uid, "studentId", code, status) values ('cc_tmp','U_PB','IQ-0108','X','active') on conflict do nothing;
select zz.chk('C13 balsiz o''quvchi -> rank null', zz.as('U_PB', $q$select public.child_card('IQ-0108')::text$q$), '^\{"rank": null, "size": 5\}$');
delete from public.child_claims where id = 'cc_tmp';

-- ===== issue_doc_token =====
select zz.chk('I01 direktor -> 32 hex', zz.as('U_DIR', $q$select public.issue_doc_token('IQ-0103','profile')$q$), '^[0-9a-f]{32}$');
select zz.chk('I02 direktor qayta -> AYNAN shu kod', (select case when zz.as('U_DIR', $q$select public.issue_doc_token('IQ-0103','profile')$q$) = (select token from public.issued_documents where sid='IQ-0103' and kind='profile') then 'same' else 'diff' end), '^same$');
select zz.chk('I03 O''IBDO'' -> shu kod', (select case when zz.as('U_ZAV', $q$select public.issue_doc_token('IQ-0103','profile')$q$) = (select token from public.issued_documents where sid='IQ-0103' and kind='profile') then 'same' else 'diff' end), '^same$');
select zz.chk('I04 qabulxona certificate -> yangi kod', zz.as('U_REC', $q$select public.issue_doc_token('IQ-0103','certificate')$q$), '^[0-9a-f]{32}$');
select zz.chk('I05 bloklangan qabulxona', zz.as('U_RECB', $q$select public.issue_doc_token('IQ-0103','profile')$q$), '^ERR 42501');
select zz.chk('I06 o''qituvchi', zz.as('U_TEA', $q$select public.issue_doc_token('IQ-0103','profile')$q$), '^ERR 42501');
select zz.chk('I07 kassir', zz.as('U_KAS', $q$select public.issue_doc_token('IQ-0103','profile')$q$), '^ERR 42501');
select zz.chk('I08 HR', zz.as('U_HR', $q$select public.issue_doc_token('IQ-0103','profile')$q$), '^ERR 42501');
select zz.chk('I09 moliya', zz.as('U_FIN', $q$select public.issue_doc_token('IQ-0103','profile')$q$), '^ERR 42501');
select zz.chk('I10 ota-ona o''z farzandi (doc id bilan) profile', zz.as('U_PA', $q$select public.issue_doc_token('docS1','profile')$q$), '^[0-9a-f]{32}$');
select zz.chk('I11 ota-ona kanonik kalit bilan saqlandi (IQ-0101)', (select string_agg(sid, ',') from public.issued_documents where "issuedBy" = 'U_PA'), '^IQ-0101$');
select zz.chk('I12 ota-ona o''z farzandi certificate -> rad', zz.as('U_PA', $q$select public.issue_doc_token('IQ-0101','certificate')$q$), '^ERR 42501');
select zz.chk('I13 ota-ona begona bola', zz.as('U_PA', $q$select public.issue_doc_token('IQ-0103','profile')$q$), '^ERR 42501');
select zz.chk('I14 ota-ona yo''q ID (mavjudligi bilinmasin -> 42501)', zz.as('U_PA', $q$select public.issue_doc_token('IQ-9999','profile')$q$), '^ERR 42501');
select zz.chk('I15 o''quvchi o''zi', zz.as('U_STU', $q$select public.issue_doc_token('IQ-0102','profile')$q$), '^[0-9a-f]{32}$');
select zz.chk('I16 bekor bog''lanish', zz.as('U_PREV', $q$select public.issue_doc_token('IQ-0101','profile')$q$), '^ERR 42501');
select zz.chk('I17 anon', zz.as(null, $q$select public.issue_doc_token('IQ-0103','profile')$q$), '^ERR 42501 permission denied');
select zz.chk('I18 noma''lum tur', zz.as('U_DIR', $q$select public.issue_doc_token('IQ-0103','diplom')$q$), '^ERR 22023');
select zz.chk('I19 direktor yo''q o''quvchi', zz.as('U_DIR', $q$select public.issue_doc_token('IQ-9999','profile')$q$), '^ERR P0002');
select zz.chk('I20 jadvalga to''g''ridan-to''g''ri o''qish (direktor)', zz.as('U_DIR', $q$select count(*)::text from public.issued_documents$q$), '^ERR 42501');
select zz.chk('I21 jadvalga to''g''ridan-to''g''ri yozish (direktor)', zz.as('U_DIR', $q$insert into public.issued_documents (token, sid, kind) values ('00000000000000000000000000000000','IQ-0103','profile') returning 'x'$q$), '^ERR 42501');
select zz.chk('I22 change_log: berilgan hujjat yozildi, kod yashirin', (select string_agg(actor_uid || ':' || (changes->'token'->>0), ',' order by id) from public.change_log where tbl = 'issued_documents'), '^U_DIR:\*\*\*,U_REC:\*\*\*,U_PA:\*\*\*,U_STU:\*\*\*$');

-- ===== verify_doc =====
select zz.chk('V01 anon haqiqiy kod -> faqat ruxsat etilgan maydonlar', zz.as(null, format($q$select public.verify_doc(%L)::text$q$, (select token from public.issued_documents where sid='IQ-0103' and kind='profile'))), '^\{"kind": "profile", "name": "Bekzod R\.", "grade": 7, "valid": true, "issuedAt": "\d{4}-\d{2}-\d{2}"\}$');
select zz.chk('V02 kalitlar ro''yxati', zz.as(null, format($q$select string_agg(k, ',' order by k) from jsonb_object_keys(public.verify_doc(%L)) k$q$, (select token from public.issued_documents where sid='IQ-0103' and kind='profile'))), '^grade,issuedAt,kind,name,valid$');
select zz.chk('V03 familiya birinchi yozilgan ism (Karimova Malika -> Malika K.)', zz.as(null, format($q$select public.verify_doc(%L)->>'name'$q$, (select token from public.issued_documents where sid='IQ-0102'))), '^Malika K\.$');
select zz.chk('V04 katta harfli kod ham', zz.as(null, format($q$select public.verify_doc(%L)->>'valid'$q$, upper((select token from public.issued_documents where sid='IQ-0103' and kind='profile')))), '^true$');
select zz.chk('V05 noto''g''ri format', zz.as(null, $q$select public.verify_doc('IQ-0103')::text$q$), '^\{"valid": false\}$');
select zz.chk('V06 to''g''ri format, yo''q kod', zz.as(null, $q$select public.verify_doc('0123456789abcdef0123456789abcdef')::text$q$), '^\{"valid": false\}$');
select zz.chk('V07 null', zz.as(null, $q$select public.verify_doc(null)::text$q$), '^\{"valid": false\}$');
select zz.chk('V08 SQL in''ektsiyaga o''xshash matn', zz.as(null, $q$select public.verify_doc($x$' or 1=1 --$x$)::text$q$), '^\{"valid": false\}$');
update public.issued_documents set "revokedAt" = now(), "revokedBy" = 'U_DIR' where sid = 'IQ-0103' and kind = 'profile';
select zz.chk('V09 bekor qilingan kod -> valid false', zz.as(null, format($q$select public.verify_doc(%L)::text$q$, (select token from public.issued_documents where sid='IQ-0103' and kind='profile'))), '^\{"valid": false\}$');
select zz.chk('V10 bekor qilingandan keyin yangi kod (eskisidan farqli)', (select case when zz.as('U_DIR', $q$select public.issue_doc_token('IQ-0103','profile')$q$) <> (select token from public.issued_documents where sid='IQ-0103' and kind='profile' and "revokedAt" is not null) then 'new' else 'same' end), '^new$');
select zz.chk('V11a direktor IQ-0106 uchun kod', zz.as('U_DIR', $q$select public.issue_doc_token('IQ-0106','profile')$q$), '^[0-9a-f]{32}$');
delete from public.students where id = 'IQ-0106';
select zz.chk('V11 o''chirilgan o''quvchi: valid, ism/sinf yo''q', zz.as(null, format($q$select public.verify_doc(%L)::text$q$, (select token from public.issued_documents where sid='IQ-0106'))), '^\{"kind": "profile", "name": null, "grade": null, "valid": true');

-- ===== Ism triggerlari =====
select zz.chk('N01 direktor yutuq ismi bilan yozsa -> ism saqlanmaydi', zz.as('U_DIR', $q$insert into public.achievements_students (id, name, label, year, text_uz) values ('a_t1','To''qima Ism','7-sinf o''quvchisi',2026,'x') returning coalesce(name,'<null>') || '|' || label$q$), '^<null>\|7-sinf o''quvchisi$');
select zz.chk('N02 UPDATE bilan ism -> yana bo''sh', zz.as('U_DIR', $q$update public.achievements_students set name = 'Yana Ism' where id = 'a_t1' returning coalesce(name,'<null>')$q$), '^<null>$');
select zz.chk('N03 sharh rozilksiz -> ism saqlanmaydi', zz.as('U_DIR', $q$insert into public.testimonials (id, name, role_uz, text_uz) values ('t_t1','Ota Ismi','5-sinf o''quvchisining otasi','zo''r') returning coalesce(name,'<null>') || '|' || "nameConsent"$q$), '^<null>\|false$');
select zz.chk('N04 sharh rozilik bilan -> ism qoladi', zz.as('U_DIR', $q$insert into public.testimonials (id, name, "nameConsent", role_uz, text_uz) values ('t_t2','Ona Ismi',true,'ona','yaxshi') returning coalesce(name,'<null>')$q$), '^Ona Ismi$');
select zz.chk('N05 rozilik olib tashlansa -> ism tozalanadi', zz.as('U_DIR', $q$update public.testimonials set "nameConsent" = false where id = 't_t2' returning coalesce(name,'<null>')$q$), '^<null>$');
select zz.chk('N06 anon yozolmaydi', zz.as(null, $q$insert into public.testimonials (id, name, text_uz) values ('t_t3','x','y') returning 'x'$q$), '^ERR 42501');
select zz.chk('N07 anon sharhlarni o''qiydi (sayt), ism faqat roziliklisida', zz.as(null, $q$select count(*) filter (where name is not null)::text || '/' || count(*)::text from public.testimonials where id in ('t_t1','t_t2')$q$), '^0/2$');

-- ===== Ism zaxirasi RLS =====
select zz.chk('B01 direktor zaxirani o''qiydi', zz.as('U_DIR', $q$select count(*)::text from public.public_names_backup$q$), '^\d+$');
select zz.chk('B02 O''IBDO'' — 0 qator', zz.as('U_ZAV', $q$select count(*)::text from public.public_names_backup$q$), '^0$');
select zz.chk('B03 ota-ona — 0 qator', zz.as('U_PA', $q$select count(*)::text from public.public_names_backup$q$), '^0$');
select zz.chk('B04 anon — ruxsat yo''q', zz.as(null, $q$select count(*)::text from public.public_names_backup$q$), '^ERR 42501');
select zz.chk('B05 direktor yozolmaydi', zz.as('U_DIR', $q$insert into public.public_names_backup (tbl, row_id, name) values ('x','y','z') returning 'x'$q$), '^ERR 42501');

-- ===== students_public / storage =====
select zz.chk('P01 anon ommaviy o''quvchi ko''rinishi — yo''q', zz.as(null, $q$select count(*)::text from public.students_public$q$), '^ERR 42P01');
select zz.chk('P02 anon xom students — ruxsat yo''q/0', zz.as(null, $q$select count(*)::text from public.students$q$), '^(ERR 42501|0$)');
select zz.chk('S01 anon storage ro''yxati -> 0', zz.as(null, $q$select count(*)::text from storage.objects where bucket_id = 'public'$q$), '^0$');
select zz.chk('S02 ota-ona storage ro''yxati -> 0', zz.as('U_PA', $q$select count(*)::text from storage.objects where bucket_id = 'public'$q$), '^0$');
select zz.chk('S03 o''qituvchi (xodim) ro''yxat ko''radi', zz.as('U_TEA', $q$select count(*)::text from storage.objects where bucket_id = 'public'$q$), '^[1-9]');
select zz.chk('S04 direktor upsert (yangi) — RETURNING bilan', zz.as('U_DIR', $q$insert into storage.objects (bucket_id, name) values ('public','images/x/3_c.jpg') on conflict (bucket_id, name) do update set metadata = excluded.metadata returning name$q$), '^images/x/3_c.jpg$');
select zz.chk('S05 direktor upsert (mavjud ustiga)', zz.as('U_DIR', $q$insert into storage.objects (bucket_id, name, metadata) values ('public','images/x/3_c.jpg','{"v":2}') on conflict (bucket_id, name) do update set metadata = excluded.metadata returning metadata::text$q$), '^\{"v": 2\}$');
select zz.chk('S06 HR yangi rasm (upsert, RETURNING)', zz.as('U_HR', $q$insert into storage.objects (bucket_id, name) values ('public','images/t/4_d.jpg') on conflict (bucket_id, name) do update set metadata = excluded.metadata returning name$q$), '^images/t/4_d.jpg$');
select zz.chk('S07 O''IBDO'' yangi rasm', zz.as('U_ZAV', $q$insert into storage.objects (bucket_id, name) values ('public','images/t/5_e.jpg') on conflict (bucket_id, name) do update set metadata = excluded.metadata returning name$q$), '^images/t/5_e.jpg$');
select zz.chk('S08 anon yuklay olmaydi', zz.as(null, $q$insert into storage.objects (bucket_id, name) values ('public','images/z.jpg') returning name$q$), '^ERR 42501');
select zz.chk('S09 ota-ona yuklay olmaydi', zz.as('U_PA', $q$insert into storage.objects (bucket_id, name) values ('public','images/z2.jpg') returning name$q$), '^ERR 42501');
select zz.chk('S10 direktor o''chira oladi (SELECT+DELETE)', zz.as('U_DIR', $q$with d as (delete from storage.objects where bucket_id='public' and name='images/x/3_c.jpg' returning 1) select count(*)::text from d$q$), '^1$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
