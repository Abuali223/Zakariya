-- =====================================================================
-- test-audit-11-talim.sql — audit-11-talim.sql va student-archive.sql (student_certificate) sinovi — O'QUV JARAYONI:
--   A3-02 baho / monitoring / xarakteristika / fan izohi / oylik xulosa faqat o'z sinfi o'quvchisiga, o'qituvchi — faqat o'z faniga;
--   A3-01 tasdiqlangan monitoring balli eskirgan sahifadan jim bekor bo'lmaydi; A3-03 ball 0–100; A3-06 noto'g'ri yozuvni o'chirish;
--   A3-07 muallif / sana belgisi matn o'zgarmasa saqlanadi; A3-04 rasmiy profil uchun yig'ma (barcha choraklar, fan izohlari);
--   deploydagi bir martalik tuzatish (joriy davr satrlarining sinf kaliti) va uning deploy.sh konsolida ko'rinadigan xabari (D01).
--   Har chaqiruv haqiqiy rol bilan (anon yoki authenticated + JWT sub) — RLS va GRANT haqiqiy.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-audit-11-talim.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- Deploy xabarlari (D01, pastda tekshiriladi): deploy.sh konsolga faqat «OGOHLANTIRISH|g'ayrioddiy» qatorlarini chiqaradi. Bir martalik
--   tuzatish xabarini AYNAN shu filtr bilan ko'rish uchun alohida psql seansi (shu baza): o'z tranzaksiyasida boshqa sinf kalitli joriy oy
--   satri va 0–100 dan tashqari ball yaratadi, audit-11-talim.sql'ni zanjirdagidek ishga tushiradi va ROLLBACK qiladi. Bu sinov
--   tranzaksiyasidan OLDIN — keyin audit-11-talim.sql DDL qulflari shu tranzaksiya qulflari bilan to'qnashardi. Fayl: migration/ ichidan
--   ham, repo ildizidan ham ishga tushirilganda topiladi.
\set zz_deploy_out `f=audit-11-talim.sql; [ -f "$f" ] || f=migration/audit-11-talim.sql; psql -X -q -v ON_ERROR_STOP=1 -v iqror_chain=1 -h :'HOST' -p :'PORT' -U :'USER' -d :'DBNAME' -c 'begin' -c 'select set_config($$iqror.migrating$$, $$1$$, true)' -c 'insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ($$IQ-0791$$, $$IQ-0791$$, $$Sinov Xabar$$, 7, $$B$$, $$uz$$)' -c 'insert into public.monitoring (id, "studentId", "classKey", subject, period, score, status) select $$IQ-0791__$$ || m || x.slug, $$IQ-0791$$, x.ck, x.subj, m, x.score, $$pending$$ from (select to_char(app.tashkent_now(), $$YYYY-MM$$) m) t, (values ($$__matematika$$, $$uz-5-A$$, $$Matematika$$, 70), ($$__fizika$$, $$uz-7-B$$, $$Fizika$$, 950)) x(slug, ck, subj, score)' -c 'select set_config($$iqror.migrating$$, $$$$, true)' -f "$f" -c 'rollback' 2>&1 | grep -E "OGOHLANTIRISH|g'ayrioddiy" | sed -E 's/^.*NOTICE: +//'`
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-11-talim.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
-- joriy / o'tgan oy va joriy o'quv yili (Toshkent) — audit-11-talim.sql tuzatishi bilan bir xil hisob
select set_config('zz.m',  to_char(app.tashkent_now(), 'YYYY-MM'), true),
       set_config('zz.pm', to_char(app.tashkent_now() - interval '1 month', 'YYYY-MM'), true),
       set_config('zz.nm', to_char(app.tashkent_now() + interval '1 month', 'YYYY-MM'), true),
       set_config('zz.ay', case when extract(month from app.tashkent_now()) >= 9
                               then extract(year from app.tashkent_now())::int || '-' || (extract(year from app.tashkent_now())::int + 1)
                               else (extract(year from app.tashkent_now())::int - 1) || '-' || extract(year from app.tashkent_now())::int end, true),
       set_config('zz.yr', (extract(month from app.tashkent_now()) not in (7, 8))::text, true);
set local iqror.migrating = '1';
insert into public.users (id, email, role, status) values
  ('U_DIR','d@example.org','director','active'), ('U_ZAV','z@example.org','zavuch','active'),
  ('U_T5M','t5m@example.org','teacher','active'), ('U_T5F','t5f@example.org','teacher','active'), ('U_T7M','t7m@example.org','teacher','active'),
  ('U_T5B','t5b@example.org','teacher','active'), ('U_T8','t8@example.org','teacher','active'), ('U_T5X','t5x@example.org','teacher','active'),
  ('U_K5','k5@example.org','kurator','active'), ('U_H7','h7@example.org','teacher','active'),
  ('U_REC','r@example.org','reception','active'), ('U_KAS','k@example.org','kassir','active'), ('U_PA','pa@example.org','parent','active')
on conflict (id) do update set role = excluded.role, status = excluded.status;
update public.users set "assignedClasses" = '["uz-5-A"]', "assignedSubjects" = '["Matematika"]' where id = 'U_T5M';
update public.users set "assignedClasses" = '["uz-5-A"]', "assignedSubjects" = '["Fizika"]'     where id = 'U_T5F';
update public.users set "assignedClasses" = '["uz-7-B"]', "assignedSubjects" = '["Matematika"]' where id = 'U_T7M';
update public.users set "assignedClasses" = '["uz-5-B"]', "assignedSubjects" = '["Matematika"]' where id = 'U_T5B';
update public.users set "assignedClasses" = '["uz-8-A","uz-8-B"]', "assignedSubjects" = '["Matematika"]' where id = 'U_T8';
update public.users set "assignedClasses" = '["uz-5-A"]', "assignedSubjects" = '["Matematika","Fizika"]' where id = 'U_T5X';   -- ikki fanli
update public.users set "assignedClasses" = '["uz-5-A"]' where id = 'U_K5';           -- kurator (assignedClasses)
update public.users set "homeroomClasses" = '["uz-7-B"]' where id = 'U_H7';           -- sinf rahbari (o'qituvchi)
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "stopFrom", "exitAt") values
  ('IQ-0501','IQ-0501','Sinov Besh A',5,'A','uz','','',null),
  ('IQ-0502','IQ-0502','Sinov Kochadi',5,'A','uz','','',null),
  ('IQ-0503','IQ-0503','Sinov Chiqqan',5,'A','uz','chiqdi',to_char(app.tashkent_now(), 'YYYY-MM') || '-01',to_char(app.tashkent_now(), 'YYYY-MM') || '-01'),
  ('fbL1','','Sinov Eski Kalit',5,'A','uz','','',null),
  ('IQ-0701','IQ-0701','Sinov Yetti B',7,'B','uz','','',null),
  ('IQ-0702','IQ-0702','Sinov Yetti B Ikki',7,'B','uz','','',null),
  -- eski import to'qnashuvi (test-student-archive.sql bilan bir xil): docK.studentId = boshqa bolaning doc id'si
  ('docK','IQ-0999','Sinov Toqnash A',8,'A','uz','','',null),
  ('IQ-0999','','Sinov Toqnash B',8,'B','uz','','',null)
on conflict (id) do nothing;
insert into public.child_claims (id, uid, "studentId", code, status) values ('cc_pa','U_PA','IQ-0701','X','active') on conflict (id) do nothing;
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
-- got NULL bo'lsa ham FAIL ko'rinsin
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, coalesce(p_got, '<null>'), p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- Holatni o'qish (superuser): VOLATILE — shu buyruqdagi oldingi zz.as amalini ko'radi.
create or replace function zz.q(p_q text) returns text language plpgsql as $$
declare r text; begin execute p_q into r; return coalesce(r, '<null>'); end $$;
-- admin.html yozuvlari bilan bir xil: setDoc(doc(...), {...}, {merge:true}) = upsert (ON CONFLICT id DO UPDATE berilgan ustunlar)
create or replace function zz.gr(p_sid text, p_ck text, p_subj text, p_id text default null, p_year text default null) returns text language sql as $$
  select format($f$with x as (insert into public.grades (id, "studentId", "classKey", year, subjects) values (%L, %L, %L, %L, %L::jsonb)
     on conflict (id) do update set "studentId" = excluded."studentId", "classKey" = excluded."classKey", year = excluded.year, subjects = excluded.subjects
     returning 1) select count(*)::text from x$f$,
    coalesce(p_id, p_sid || '__' || coalesce(p_year, current_setting('zz.ay'))), p_sid, p_ck, coalesce(p_year, current_setting('zz.ay')), p_subj)
$$;
create or replace function zz.mon(p_sid text, p_ck text, p_subj text, p_score text, p_status text default 'pending', p_id text default null, p_period text default null) returns text language sql as $$
  select format($f$with x as (insert into public.monitoring (id, "studentId", "classKey", subject, period, score, status, "updatedAt") values (%L, %L, %L, %L, %L, %s, %L, now())
     on conflict (id) do update set "studentId" = excluded."studentId", "classKey" = excluded."classKey", subject = excluded.subject, period = excluded.period,
       score = excluded.score, status = excluded.status, "updatedAt" = excluded."updatedAt"
     returning 1) select count(*)::text from x$f$,
    coalesce(p_id, p_sid || '__' || coalesce(p_period, current_setting('zz.m')) || '__' || app.mon_slug(p_subj)), p_sid, p_ck, p_subj,
    coalesce(p_period, current_setting('zz.m')), p_score, p_status)
$$;
create or replace function zz.chr(p_sid text, p_ck text, p_text text, p_by text default 'Sinov Muallif', p_id text default null, p_term text default null) returns text language sql as $$
  select format($f$with x as (insert into public.characteristics (id, "studentId", "classKey", year, quarter, term, text, "byUid", "byName", "updatedAt") values (%L, %L, %L, %L, 'q1', %L, %L, 'SOXTA_UID', %L, now() - interval '3 days')
     on conflict (id) do update set "studentId" = excluded."studentId", "classKey" = excluded."classKey", year = excluded.year, quarter = excluded.quarter, term = excluded.term,
       text = excluded.text, "byUid" = excluded."byUid", "byName" = excluded."byName", "updatedAt" = excluded."updatedAt"
     returning 1) select count(*)::text from x$f$,
    coalesce(p_id, p_sid || '__' || coalesce(p_term, current_setting('zz.ay') || '-q1')), p_sid, p_ck, current_setting('zz.ay'), coalesce(p_term, current_setting('zz.ay') || '-q1'), p_text, p_by)
$$;
create or replace function zz.note(p_sid text, p_ck text, p_subj text, p_text text, p_slug text default null, p_id text default null) returns text language sql as $$
  select format($f$with x as (insert into public.subject_notes (id, "studentId", "classKey", subject, slug, year, quarter, term, text, "byUid", "byName") values (%L, %L, %L, %L, %L, %L, 'q1', %L, %L, 'SOXTA_UID', 'Sinov')
     on conflict (id) do update set "studentId" = excluded."studentId", "classKey" = excluded."classKey", subject = excluded.subject, slug = excluded.slug,
       text = excluded.text, "byUid" = excluded."byUid", "byName" = excluded."byName"
     returning 1) select count(*)::text from x$f$,
    coalesce(p_id, p_sid || '__' || current_setting('zz.ay') || '-q1__' || coalesce(p_slug, app.mon_slug(p_subj))), p_sid, p_ck, p_subj, coalesce(p_slug, app.mon_slug(p_subj)),
    current_setting('zz.ay'), current_setting('zz.ay') || '-q1', p_text)
$$;
create or replace function zz.sum(p_sid text, p_ck text, p_text text, p_month text default null, p_id text default null) returns text language sql as $$
  select format($f$with x as (insert into public.student_summaries (id, "studentId", "classKey", month, text, "byUid", "byName") values (%L, %L, %L, %L, %L, 'SOXTA_UID', 'Sinov')
     on conflict (id) do update set "studentId" = excluded."studentId", "classKey" = excluded."classKey", month = excluded.month, text = excluded.text,
       "byUid" = excluded."byUid", "byName" = excluded."byName"
     returning 1) select count(*)::text from x$f$,
    coalesce(p_id, p_sid || '__' || coalesce(p_month, current_setting('zz.m'))), p_sid, p_ck, coalesce(p_month, current_setting('zz.m')), p_text)
$$;
create or replace function zz.upd(p_tbl text, p_set text, p_id text) returns text language sql as $$
  select format($f$with x as (update public.%I set %s where id = %L returning 1) select count(*)::text from x$f$, p_tbl, p_set, p_id)
$$;
create or replace function zz.del(p_tbl text, p_id text) returns text language sql as $$
  select format($f$with x as (delete from public.%I where id = %L returning 1) select count(*)::text from x$f$, p_tbl, p_id)
$$;
select set_config('zz.g1', 'IQ-0501__' || current_setting('zz.ay'), true), set_config('zz.m1', 'IQ-0501__' || current_setting('zz.m') || '__matematika', true);

-- ===== A3-02: baholar — faqat o'z sinfi o'quvchisi, o'qituvchi faqat o'z fani =====
select zz.chk('G01 5-A Matematika o''qituvchisi o''z o''quvchisiga o''z fanini saqlaydi (upsert, butun obyekt)',
  zz.as('U_T5M', zz.gr('IQ-0501', 'uz-5-A', '{"Matematika":{"q1":4}}')), '^1$');
select zz.chk('G02 5-A Fizika o''qituvchisi Fizika qo''shadi (Matematika saqlanadi)',
  zz.as('U_T5F', zz.gr('IQ-0501', 'uz-5-A', '{"Matematika":{"q1":4},"Fizika":{"q1":5}}')) || '|' || zz.q($q$select subjects::text from public.grades where id = current_setting('zz.g1')$q$),
  '^1\|\{"Fizika": \{"q1": 5\}, "Matematika": \{"q1": 4\}\}$');
select zz.chk('G03 Matematika o''qituvchisi Fizika baholarini qayta yozolmaydi va subjects=''{}'' bilan hammasini o''chira olmaydi (avval «updated rows: 1», izsiz)',
  zz.as('U_T5M', zz.upd('grades', $s$subjects = '{"Matematika":{"q1":4},"Fizika":{"q1":2}}'$s$, current_setting('zz.g1')))
  || ' / ' || zz.as('U_T5M', zz.upd('grades', $s$subjects = '{}'$s$, current_setting('zz.g1'))),
  '^ERR 42501 Baholar: «Fizika» fani sizga biriktirilmagan.* / ERR 42501 Baholar: «Fizika» fani sizga biriktirilmagan');
select zz.chk('G04 eskirgan nusxa: Matematika o''qituvchisi butun obyektni eski Fizika bahosi bilan yuboradi — rad (Fizika o''qituvchisining yangi bahosi yo''qolmaydi)',
  zz.as('U_T5M', zz.gr('IQ-0501', 'uz-5-A', '{"Matematika":{"q1":5}}'))
  || '|' || zz.q($q$select subjects::text from public.grades where id = current_setting('zz.g1')$q$),
  '^ERR 42501 Baholar: «Fizika».*\|\{"Fizika": \{"q1": 5\}, "Matematika": \{"q1": 4\}\}$');
select zz.chk('G05 o''z fanidagi o''zgarish (yangi nusxa) — saqlanadi',
  zz.as('U_T5M', zz.gr('IQ-0501', 'uz-5-A', '{"Matematika":{"q1":5,"q2":3},"Fizika":{"q1":5}}')), '^1$');
select zz.chk('G06 5-A o''qituvchisi 7-B o''quvchisiga O''Z sinf kaliti bilan — rad; boshqa sinf kaliti bilan — RLS rad etadi',
  zz.as('U_T5M', zz.gr('IQ-0701', 'uz-5-A', '{"Matematika":{"q1":2}}')) || ' / ' || zz.as('U_T5M', zz.gr('IQ-0701', 'uz-7-B', '{"Matematika":{"q1":2}}')),
  '^ERR 42501 Baholar: «IQ-0701» bu sinf o''quvchisi emas.* / ERR 42501 new row violates row-level security policy');
select zz.chk('G07 kanonik bo''lmagan kalit va noto''g''ri o''quv yili — rad',
  zz.as('U_T5M', zz.gr('IQ-0501', 'uz-5-A', '{"Matematika":{"q1":5}}', 'zzz-soxta')) || ' / ' || zz.as('U_T5M', zz.gr('IQ-0501', 'uz-5-A', '{"Matematika":{"q1":5}}', null, '2026')),
  '^ERR 22023 Baholar: yozuv kaliti.* / ERR 22023 Baholar: o''quv yili');
select zz.chk('G08 satrning o''quvchisi / yilini almashtirish — rad',
  zz.as('U_T5M', zz.upd('grades', $s$"studentId" = 'IQ-0502'$s$, current_setting('zz.g1'))) || ' / ' || zz.as('U_T5M', zz.upd('grades', $s$year = '2030-2031'$s$, current_setting('zz.g1'))),
  '^ERR 42501 Baholar: yozuvning o''quvchisi.* / ERR 42501 ');
select zz.chk('G09 O''IBDO'' va Direktor istalgan fanni o''zgartiradi (huquq o''zgarmagan); Direktor ham noto''g''ri sinf kaliti bilan — rad',
  zz.as('U_ZAV', zz.upd('grades', $s$subjects = subjects || '{"Fizika":{"q1":4}}'$s$, current_setting('zz.g1')))
  || '|' || zz.as('U_DIR', zz.gr('IQ-0701', 'uz-7-B', '{"Tarix":{"q1":5}}')) || '|' || zz.as('U_DIR', zz.gr('IQ-0702', 'uz-5-A', '{"Tarix":{"q1":5}}')),
  '^1\|1\|ERR 42501 Baholar: «IQ-0702» bu sinf o''quvchisi emas');
select zz.chk('G10 kurator, qabulxona, ota-ona baho yoza olmaydi (RLS — avvalgidek)',
  zz.as('U_K5', zz.gr('IQ-0502', 'uz-5-A', '{"Matematika":{"q1":5}}')) || ' / ' || zz.as('U_REC', zz.gr('IQ-0502', 'uz-5-A', '{"Matematika":{"q1":5}}'))
  || ' / ' || zz.as('U_PA', zz.gr('IQ-0701', 'uz-7-B', '{"Matematika":{"q1":5}}')),
  '^ERR 42501 new row violates.* / ERR 42501 new row violates.* / ERR 42501 new row violates');
select zz.chk('G11 eski kalit (studentId bo''sh — doc id), arxivdagi o''quvchi va eski import to''qnashuvi — avvalgidek saqlanadi',
  zz.as('U_T5M', zz.gr('fbL1', 'uz-5-A', '{"Matematika":{"q1":3}}')) || zz.as('U_T5M', zz.gr('IQ-0503', 'uz-5-A', '{"Matematika":{"q1":4}}'))
  || zz.as('U_T8', zz.gr('IQ-0999', 'uz-8-B', '{"Matematika":{"q1":4}}')), '^111$');

-- ===== A3-02 + A3-01 + A3-03: monitoring =====
select zz.chk('M01 5-A Matematika o''qituvchisi o''z o''quvchisiga — kutilmoqda, kiritgan: o''zi',
  zz.as('U_T5M', zz.mon('IQ-0501', 'uz-5-A', 'Matematika', '80')) || '|' || zz.q($q$select status || ' ' || "enteredBy" from public.monitoring where id = current_setting('zz.m1')$q$),
  '^1\|pending U_T5M$');
select zz.chk('M02 5-A o''qituvchisi 7-B o''quvchisiga «uz-5-A» kaliti bilan (100) — rad; haqiqiy 7-B o''qituvchisi saqlaydi (avval 42501 USING olardi)',
  zz.as('U_T5M', zz.mon('IQ-0701', 'uz-5-A', 'Matematika', '100')) || '|' || zz.as('U_T7M', zz.mon('IQ-0701', 'uz-7-B', 'Matematika', '70')),
  '^ERR 42501 Monitoring: «IQ-0701» bu sinf o''quvchisi emas.*\|1$');
select zz.chk('M03 kalitdagi fan boshqa (…__fizika, fan «Matematika») — rad; kanonik bo''lmagan kalit va noto''g''ri oy — rad',
  zz.as('U_T5M', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '80', 'pending', 'IQ-0502__' || current_setting('zz.m') || '__fizika'))
  || ' / ' || zz.as('U_T5M', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '80', 'pending', 'zzz-soxta'))
  || ' / ' || zz.as('U_T5M', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '80', 'pending', 'IQ-0502__2026-13__matematika', '2026-13')),
  '^ERR 42501 Monitoring: yozuv kalitidagi fan.* / ERR 22023 Monitoring: yozuv kaliti.* / ERR 22023 Monitoring: oy');
select zz.chk('M04 O''IBDO'' tasdiqlaydi — tasdiqlagan: O''IBDO''',
  zz.as('U_ZAV', zz.upd('monitoring', $s$status = 'approved'$s$, current_setting('zz.m1'))) || '|' || zz.q($q$select status || ' ' || "approvedBy" from public.monitoring where id = current_setting('zz.m1')$q$),
  '^1\|approved U_ZAV$');
select zz.chk('M05 A3-01: o''qituvchi ochiq qolgan sahifadan xuddi shu ballni ''pending'' bilan qayta yuboradi — o''tkazib yuboriladi (0), tasdiq JOYIDA (avval pending, approvedBy=null)',
  zz.as('U_T5M', zz.mon('IQ-0501', 'uz-5-A', 'Matematika', '80')) || '|' || zz.q($q$select status || ' ' || "approvedBy" from public.monitoring where id = current_setting('zz.m1')$q$),
  '^0\|approved U_ZAV$');
select zz.chk('M06 o''qituvchi tasdiqlangan ballni o''zgartira olmaydi (upsert ham, PATCH ham)',
  zz.as('U_T5M', zz.mon('IQ-0501', 'uz-5-A', 'Matematika', '85')) || ' / ' || zz.as('U_T5M', zz.upd('monitoring', $s$score = 85, status = 'pending'$s$, current_setting('zz.m1')))
  || '|' || zz.q($q$select score::text || ' ' || status from public.monitoring where id = current_setting('zz.m1')$q$),
  '^ERR 42501 Monitoring: «IQ-0501» balli O''IBDO'' tomonidan tasdiqlangan.* / ERR 42501 Monitoring: «IQ-0501» balli O''IBDO''.*\|80 approved$');
select zz.chk('M07 O''IBDO'' «Saqlash» (pending): ball o''zgarmasa — tasdiq qoladi; ball o''zgarsa — qayta tasdiqlashga tushadi (approvedBy tozalanadi)',
  zz.as('U_ZAV', zz.mon('IQ-0501', 'uz-5-A', 'Matematika', '80')) || '|' || zz.q($q$select status from public.monitoring where id = current_setting('zz.m1')$q$)
  || '|' || zz.as('U_ZAV', zz.mon('IQ-0501', 'uz-5-A', 'Matematika', '90')) || '|' || zz.q($q$select score::text || ' ' || status || ' ' || coalesce("approvedBy", 'null') from public.monitoring where id = current_setting('zz.m1')$q$),
  '^0\|approved\|1\|90 pending null$');
select zz.chk('M08 A3-03: 950, -40, 100.5 — rad (o''qituvchi ham, O''IBDO'' ham); 0, 100 va 99.5 — saqlanadi',
  zz.as('U_T5M', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '950')) || ' / ' || zz.as('U_T5M', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '-40'))
  || ' / ' || zz.as('U_ZAV', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '100.5', 'approved'))
  || ' / ' || zz.as('U_T5M', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '0')) || zz.as('U_T5M', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '100'))
  || zz.as('U_T5M', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '99.5')),
  '^ERR 22023 Monitoring: «IQ-0502» balli 0–100 oralig''ida bo''lsin \(kiritilgan: 950\) / ERR 22023 .*-40.* / ERR 22023 .*100.5.* / 111$');
-- eski (qo'riqchidan oldingi) noto'g'ri ball — baza nomidan; uni tasdiqlash rad, boshqa ustun (sinf kaliti) o'zgarishi to'xtamaydi
set local iqror.migrating = '1';
insert into public.monitoring (id, "studentId", "classKey", subject, period, score, status) values
  ('IQ-0502__' || current_setting('zz.m') || '__fizika', 'IQ-0502', 'uz-5-A', 'Fizika', current_setting('zz.m'), 950, 'pending')
on conflict (id) do update set "studentId" = excluded."studentId", "classKey" = excluded."classKey", subject = excluded.subject, score = excluded.score, status = excluded.status;
set local iqror.migrating = '';
select zz.chk('M09 eski 950 ballni O''IBDO'' tasdiqlay olmaydi (avval tuzatish kerak)',
  zz.as('U_ZAV', zz.upd('monitoring', $s$status = 'approved'$s$, 'IQ-0502__' || current_setting('zz.m') || '__fizika')), '^ERR 22023 Monitoring: «IQ-0502» balli 0–100');
select zz.chk('M10 ikki fanli o''qituvchi ham yozuvning fanini almashtira olmaydi (kalitdagi fan — matematika; to''lov hisobi kalitdan oladi)',
  zz.as('U_T5X', zz.upd('monitoring', $s$subject = 'Fizika'$s$, 'IQ-0502__' || current_setting('zz.m') || '__matematika')),
  '^ERR 42501 Monitoring: yozuvning fani o''zgartirilmaydi');
select zz.chk('M11 boshqa sinf / fan o''qituvchisi, kurator, qabulxona monitoring yoza olmaydi (RLS — avvalgidek)',
  zz.as('U_T5F', zz.mon('IQ-0501', 'uz-5-A', 'Matematika', '70')) || ' / ' || zz.as('U_K5', zz.mon('IQ-0501', 'uz-5-A', 'Matematika', '70'))
  || ' / ' || zz.as('U_REC', zz.mon('IQ-0501', 'uz-5-A', 'Matematika', '70')),
  '^ERR 42501 new row violates.* / ERR 42501 new row violates.* / ERR 42501 new row violates');
-- A3-06: o'chirish
select zz.chk('M12 tayyorgarlik: Fizika o''qituvchisi IQ-0501 ga (kutilmoqda), Matematika o''qituvchisi fbL1 ga yozadi',
  zz.as('U_T5F', zz.mon('IQ-0501', 'uz-5-A', 'Fizika', '60')) || zz.as('U_T5M', zz.mon('fbL1', 'uz-5-A', 'Matematika', '75')), '^11$');
select zz.chk('M13 A3-06: o''qituvchi O''ZI kiritgan tasdiqlanmagan yozuvni o''chiradi (avval faqat O''IBDO'' / Direktor, UI''siz)',
  zz.as('U_T5M', zz.del('monitoring', 'fbL1__' || current_setting('zz.m') || '__matematika')), '^1$');
select zz.chk('M14 o''qituvchi tasdiqlangan yozuvni ham, boshqa o''qituvchi kiritganini ham o''chira olmaydi; kurator / qabulxona — yo''q',
  zz.as('U_ZAV', zz.upd('monitoring', $s$status = 'approved'$s$, current_setting('zz.m1')))
  || '|' || zz.as('U_T5M', zz.del('monitoring', current_setting('zz.m1')))
  || zz.as('U_T5M', zz.del('monitoring', 'IQ-0501__' || current_setting('zz.m') || '__fizika'))
  || zz.as('U_K5', zz.del('monitoring', 'IQ-0501__' || current_setting('zz.m') || '__fizika'))
  || zz.as('U_REC', zz.del('monitoring', 'IQ-0501__' || current_setting('zz.m') || '__fizika')),
  '^1\|0000$');
select zz.chk('M15 O''IBDO'' istalgan yozuvni o''chiradi (tasdiqlanganini ham); Direktor ham',
  zz.as('U_ZAV', zz.del('monitoring', current_setting('zz.m1'))) || zz.as('U_DIR', zz.del('monitoring', 'IQ-0501__' || current_setting('zz.m') || '__fizika')), '^11$');

-- ===== A3-02 + A3-07: xarakteristika, fan izohi, oylik xulosa =====
select set_config('zz.c1', 'IQ-0501__' || current_setting('zz.ay') || '-q1', true);
select zz.chk('C01 5-A kuratori o''z o''quvchisiga yozadi; muallif ID''si — haqiqiy yozuvchi (mijoz yuborgan SOXTA_UID emas), sana — hozir',
  zz.as('U_K5', zz.chr('IQ-0501', 'uz-5-A', 'Sinov: faol o''quvchi')) || '|' || zz.q($q$select "byUid" || ' ' || ("updatedAt" > now() - interval '1 minute')::text from public.characteristics where id = current_setting('zz.c1')$q$),
  '^1\|U_K5 true$');
select zz.chk('C02 5-A kuratori 7-B o''quvchisiga «Intizomsiz» — rad; haqiqiy 7-B sinf rahbari yozadi (avval 42501 USING olardi)',
  zz.as('U_K5', zz.chr('IQ-0701', 'uz-5-A', 'Intizomsiz')) || '|' || zz.as('U_H7', zz.chr('IQ-0701', 'uz-7-B', 'Sinov: yaxshi')),
  '^ERR 42501 «IQ-0701» bu sinf o''quvchisi emas.*\|1$');
select zz.chk('C03 kanonik bo''lmagan kalit va noto''g''ri chorak — rad',
  zz.as('U_K5', zz.chr('IQ-0501', 'uz-5-A', 'x', 'Sinov', 'zzz-soxta')) || ' / ' || zz.as('U_K5', zz.chr('IQ-0501', 'uz-5-A', 'x', 'Sinov', 'IQ-0501__2026-q1', '2026-q1')),
  '^ERR 22023 Yozuv kaliti.* / ERR 22023 Chorak');
select set_config('zz.c1t', zz.q($q$select "updatedAt"::text from public.characteristics where id = current_setting('zz.c1')$q$), true);
select zz.chk('C04 A3-07: matn o''zgarmagan qayta yuborish (boshqa muallif nomi bilan) — muallif va sana eskicha; matn o''zgarsa — yangi muallif',
  zz.as('U_ZAV', zz.chr('IQ-0501', 'uz-5-A', 'Sinov: faol o''quvchi', 'Sinov OIBDO'))
  || '|' || zz.q($q$select "byUid" || ' ' || "byName" || ' ' || ("updatedAt"::text = current_setting('zz.c1t'))::text from public.characteristics where id = current_setting('zz.c1')$q$)
  || '|' || zz.as('U_ZAV', zz.chr('IQ-0501', 'uz-5-A', 'Sinov: juda faol', 'Sinov OIBDO'))
  || '|' || zz.q($q$select "byUid" || ' ' || "byName" from public.characteristics where id = current_setting('zz.c1')$q$),
  '^1\|U_K5 Sinov Muallif true\|1\|U_ZAV Sinov OIBDO$');
select zz.chk('C05 satrning o''quvchisi / chorakini almashtirish — rad',
  zz.as('U_K5', zz.upd('characteristics', $s$"studentId" = 'IQ-0502'$s$, current_setting('zz.c1'))) || ' / ' || zz.as('U_K5', zz.upd('characteristics', $s$term = 'x'$s$, current_setting('zz.c1'))),
  '^ERR 42501 Yozuvning o''quvchisi.* / ERR 42501 Yozuvning o''quvchisi');
select zz.chk('C06 fan izohi: Matematika o''qituvchisi o''z faniga — saqlanadi; kalitdagi slug fan nomiga mos emas — rad; 7-B o''quvchisiga — rad',
  zz.as('U_T5M', zz.note('IQ-0501', 'uz-5-A', 'Matematika', 'Sinov izoh'))
  || ' / ' || zz.as('U_T5M', zz.note('IQ-0502', 'uz-5-A', 'Matematika', 'Sinov izoh', 'fizika'))
  || ' / ' || zz.as('U_T5M', zz.note('IQ-0701', 'uz-5-A', 'Matematika', 'Sinov izoh')),
  '^1 / ERR 42501 Fan izohi: yozuv kalitidagi fan.* / ERR 42501 «IQ-0701» bu sinf o''quvchisi emas');
select zz.chk('C07 oylik xulosa: 7-B sinf rahbari o''z o''quvchisiga — saqlanadi; 5-A kuratori 7-B o''quvchisiga — rad; noto''g''ri oy — rad',
  zz.as('U_H7', zz.sum('IQ-0701', 'uz-7-B', 'Sinov: oy yaxshi o''tdi')) || ' / ' || zz.as('U_K5', zz.sum('IQ-0701', 'uz-5-A', 'Sinov'))
  || ' / ' || zz.as('U_H7', zz.sum('IQ-0702', 'uz-7-B', 'Sinov', '2026-13')),
  '^1 / ERR 42501 «IQ-0701» bu sinf o''quvchisi emas.* / ERR 22023 Oylik xulosa: oy');
select zz.chk('C08 oylik xulosa: kurator (o''z sinfi), O''IBDO'' va Direktor — saqlanadi; qabulxona, kassir, fan o''qituvchisi — yo''q (RLS, avvalgidek)',
  zz.as('U_K5', zz.sum('IQ-0501', 'uz-5-A', 'Sinov')) || zz.as('U_ZAV', zz.sum('IQ-0502', 'uz-5-A', 'Sinov')) || zz.as('U_DIR', zz.sum('IQ-0702', 'uz-7-B', 'Sinov'))
  || ' / ' || zz.as('U_REC', zz.sum('IQ-0501', 'uz-5-A', 'Sinov')) || ' / ' || zz.as('U_KAS', zz.sum('IQ-0501', 'uz-5-A', 'Sinov'))
  || ' / ' || zz.as('U_T5M', zz.sum('IQ-0501', 'uz-5-A', 'Sinov')),
  '^111 / ERR 42501 new row violates.* / ERR 42501 new row violates.* / ERR 42501 new row violates');

-- ===== sinf o'zgarishi (sync_student_class_rows) qo'riqchilar bilan ishlaydi =====
select zz.chk('K01 tayyorgarlik: IQ-0502 ga joriy davr baho, monitoring, xarakteristika, xulosa bor',
  zz.as('U_T5M', zz.gr('IQ-0502', 'uz-5-A', '{"Matematika":{"q1":5}}')) || zz.as('U_K5', zz.chr('IQ-0502', 'uz-5-A', 'Sinov')), '^11$');
select zz.chk('K02 Direktor IQ-0502 ni 5-B ga o''tkazadi — joriy satrlar yangi sinfga ko''chadi (qo''riqchi to''xtatmaydi; eski 950 ball ham)',
  zz.as('U_DIR', $q$with x as (update public.students set "classLetter" = 'B' where id = 'IQ-0502' returning 1) select count(*)::text from x$q$)
  || '|' || zz.q($q$select string_agg(distinct "classKey", ',') from (select "classKey" from public.monitoring where "studentId" = 'IQ-0502'
       union all select "classKey" from public.student_summaries where "studentId" = 'IQ-0502') t$q$)
  || '|' || zz.q($q$select case when current_setting('zz.yr')::boolean then (select string_agg(distinct "classKey", ',') from (select "classKey" from public.grades where "studentId" = 'IQ-0502'
       union all select "classKey" from public.characteristics where "studentId" = 'IQ-0502') t) else 'uz-5-B' end$q$),
  '^1\|uz-5-B\|uz-5-B$');
select zz.chk('K03 yangi sinf (5-B) o''qituvchisi saqlaydi; eski 5-A o''qituvchisi eskirgan sahifadan — rad',
  zz.as('U_T5B', zz.mon('IQ-0502', 'uz-5-B', 'Matematika', '88')) || ' / ' || zz.as('U_T5M', zz.mon('IQ-0502', 'uz-5-A', 'Matematika', '70', 'pending', null, current_setting('zz.pm'))),
  '^1 / ERR 42501 Monitoring: «IQ-0502» bu sinf o''quvchisi emas');

-- ===== deploydagi bir martalik tuzatish =====
set local iqror.migrating = '1';
insert into public.monitoring (id, "studentId", "classKey", subject, period, score, status) values
  ('IQ-0702__' || current_setting('zz.m') || '__matematika', 'IQ-0702', 'uz-5-A', 'Matematika', current_setting('zz.m'), 100, 'pending'),     -- joriy oy, boshqa sinf
  ('IQ-0702__' || current_setting('zz.pm') || '__matematika', 'IQ-0702', 'uz-5-A', 'Matematika', current_setting('zz.pm'), 90, 'approved'),   -- o'tgan oy (tarix)
  ('IQ-0999__' || current_setting('zz.m') || '__matematika', 'IQ-0999', 'uz-5-A', 'Matematika', current_setting('zz.m'), 90, 'pending')      -- to'qnash ID
on conflict (id) do update set "classKey" = excluded."classKey", score = excluded.score, status = excluded.status;
insert into public.characteristics (id, "studentId", "classKey", year, quarter, term, text) values
  ('IQ-0702__' || current_setting('zz.ay') || '-q1', 'IQ-0702', 'uz-5-A', current_setting('zz.ay'), 'q1', current_setting('zz.ay') || '-q1', 'Intizomsiz')
on conflict (id) do update set "classKey" = excluded."classKey", text = excluded.text;
insert into public.student_summaries (id, "studentId", "classKey", month, text) values
  ('IQ-0701__' || current_setting('zz.nm'), 'IQ-0701', 'uz-5-A', current_setting('zz.nm'), 'Sinov')                                         -- keyingi oy, boshqa sinf
on conflict (id) do update set "classKey" = excluded."classKey", text = excluded.text;
set local iqror.migrating = '';
select zz.chk('R01 tayyorgarlik: haqiqiy 7-B sinf rahbari xarakteristikani saqlay olmaydi (USING)',
  zz.as('U_H7', zz.chr('IQ-0702', 'uz-7-B', 'Sinov: yaxshi')), '^ERR 42501 new row violates row-level security policy \(USING expression\)');
\set iqror_chain 1
\ir audit-11-talim.sql
select zz.chk('R02 deploy (audit-11-talim.sql qayta): joriy monitoring / xulosa (va o''quv yili davomida xarakteristika) haqiqiy sinfga o''tdi; o''tgan oy va to''qnash ID tegilmadi',
  zz.q($q$select string_agg(id || '=' || "classKey", ',' order by id) from public.monitoring where "studentId" in ('IQ-0702','IQ-0999')$q$)
  || '|' || zz.q($q$select "classKey" from public.student_summaries where id = 'IQ-0701__' || current_setting('zz.nm')$q$)
  || '|' || zz.q($q$select case when current_setting('zz.yr')::boolean then "classKey" else 'uz-7-B' end from public.characteristics where id = 'IQ-0702__' || current_setting('zz.ay') || '-q1'$q$),
  '^IQ-0702__[0-9-]+__matematika=uz-5-A,IQ-0702__[0-9-]+__matematika=uz-7-B,IQ-0999__[0-9-]+__matematika=uz-5-A\|uz-7-B\|uz-7-B$');
select zz.chk('R03 tuzatilgan satr matni va belgisi o''zgarmadi; endi haqiqiy sinf rahbari saqlaydi; qo''riqchilar joyida',
  zz.q($q$select text from public.characteristics where id = 'IQ-0702__' || current_setting('zz.ay') || '-q1'$q$)
  || '|' || case when current_setting('zz.yr')::boolean then zz.as('U_H7', zz.chr('IQ-0702', 'uz-7-B', 'Sinov: yaxshi')) else '1' end
  || '|' || zz.as('U_K5', zz.chr('IQ-0701', 'uz-5-A', 'x')),
  '^Intizomsiz\|1\|ERR 42501 «IQ-0701»');
select zz.chk('R04 eski 950 ball deploydan keyin ham o''zgarmagan (faqat ro''yxat bilan ogohlantiriladi)',
  zz.q($q$select score::text from public.monitoring where id = 'IQ-0502__' || current_setting('zz.m') || '__fizika'$q$), '^950$');
-- zz_deploy_out — fayl boshidagi alohida seans chiqishi, deploy.sh filtridan o'tgani (NOTICE prefiksisiz).
select zz.chk('D01 deploy konsoli (deploy.sh filtri): ko''chirilgan satrlar xabari ID''lari bilan ko''rinadi — avval «TUZATILDI:» bilan boshlanib faqat jurnalda qolardi; 0–100 dan tashqari ball xabari ham joyida',
  :'zz_deploy_out',
  '^OGOHLANTIRISH: TUZATILDI: monitoring: 1 ta joriy davr satri o''quvchining haqiqiy sinfiga o''tkazildi \(boshqa sinf kaliti bilan yozilgan edi\): IQ-0791__[0-9]{4}-[0-9]{2}__matematika\nOGOHLANTIRISH: monitoring: 1 ta ball 0–100 oralig''idan tashqarida \(o''zgartirilmadi — tuzating\): IQ-0791__[0-9]{4}-[0-9]{2}__fizika=950$');

-- ===== A3-04: rasmiy profil uchun yig'ma (student_certificate) =====
set local iqror.migrating = '1';
insert into public.characteristics (id, "studentId", "classKey", year, quarter, term, text, "byName", "updatedAt") values
  ('IQ-0701__2025-2026-q4', 'IQ-0701', 'uz-6-B', '2025-2026', 'q4', '2025-2026-q4', 'Sinov: o''tgan yil', 'Sinov Kurator', '2026-05-20T10:00:00+05')
on conflict (id) do nothing;
insert into public.subject_notes (id, "studentId", "classKey", subject, slug, year, quarter, term, text, "byName") values
  ('IQ-0701__2025-2026-q4__fizika', 'IQ-0701', 'uz-6-B', 'Fizika', 'fizika', '2025-2026', 'q4', '2025-2026-q4', 'Sinov: tajribalar', 'Sinov Ustoz')
on conflict (id) do nothing;
set local iqror.migrating = '';
select zz.chk('S01 qabulxona: BARCHA choraklar xarakteristikasi (yangisi birinchi, muallif bilan) — avval faqat oxirgisi',
  zz.as('U_REC', $q$select string_agg((e->>'term') || ':' || (e->>'text') || ':' || coalesce(e->>'by', '-'), ' | ' order by o) from jsonb_array_elements(public.student_certificate('IQ-0701')->'chars') with ordinality t(e, o)$q$),
  '^[0-9]{4}-[0-9]{4}-q1:Sinov: yaxshi:Sinov Muallif \| 2025-2026-q4:Sinov: o''tgan yil:Sinov Kurator$');
select zz.chk('S02 qabulxona: fan izohlari (fan, matn, muallif, sana) — jadvalni o''zi o''qiy olmasa ham',
  zz.as('U_REC', $q$select (n->>'term') || ':' || (n->>'subject') || ':' || (n->>'text') || ':' || (n->>'by') || ':' || ((n->>'at') is not null)::text from (select public.student_certificate('IQ-0701')->'notes'->0 n) x$q$)
  || '|' || zz.as('U_REC', $q$select count(*)::text from public.subject_notes$q$),
  '^2025-2026-q4:Fizika:Sinov: tajribalar:Sinov Ustoz:true\|0$');
select zz.chk('S03 ''char'' (📨 ma''lumotnoma) o''zgarmagan — oxirgi davr; o''qituvchi / kassir / ota-ona — yo''q (rollar o''zgarmagan)',
  zz.as('U_REC', $q$select public.student_certificate('IQ-0701')->'char'->>'text'$q$)
  || '|' || zz.as('U_H7', $q$select public.student_certificate('IQ-0701')::text$q$) || '|' || zz.as('U_KAS', $q$select public.student_certificate('IQ-0701')::text$q$)
  || '|' || zz.as('U_PA', $q$select public.student_certificate('IQ-0701')::text$q$),
  '^Sinov: yaxshi\|ERR 42501.*\|ERR 42501.*\|ERR 42501');

-- ===== yordamchi: fan slug'i (admin.html monSlug bilan bir xil) =====
select zz.chk('U01 app.mon_slug: lotin, o''zbek apostrofi, kirill (katta / kichik), bo''sh -> NULL',
  (select string_agg(coalesce(app.mon_slug(x), '<null>'), ',' order by o) from unnest(array['Ona tili', 'O‘zbek tili', 'Математика', 'ЎЗБЕК ТИЛИ', 'Қалам ҳаёт', ' IT ', '😀', null]) with ordinality t(x, o)),
  '^ona_tili,o_zbek_tili,matematika,ozbek_tili,qalam_hayot,it,<null>,<null>$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
