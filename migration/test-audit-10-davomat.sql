-- =====================================================================
-- test-audit-10-davomat.sql — audit-10-davomat.sql, attendance-sync.sql va payer-code-mask.sql (restore_deleted_student) sinovi:
--   A2-01 davomat yozuvi faqat o'z sinfi o'quvchisiga (kurator / sinf rahbari / O'IBDO' / Direktor, sinf o'zgarishi, arxiv, eski kalit),
--   A2-05 «Davomat %» hisoblanadigan kun qolmasa tozalanadi, A2-04 ID yuqori chegarasi va tarix (tibbiyot, so'rovlar, o'chirilganlar),
--   A1-11 tiklash: o'chgan xodimga bog'lanish tiklashni to'xtatmaydi, qayta berilgan ID'da boshqa oilaning arxivi yopishmaydi.
--   Har chaqiruv haqiqiy rol bilan (anon yoki authenticated + JWT sub) — RLS va GRANT haqiqiy.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-audit-10-davomat.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
--   Deploydagi bir martalik tuzatishlar (sinf kalitini tenglash, «Davomat %» backfill) — zanjirdagi AYNAN o'sha fayllarni shu
--   tranzaksiyada qayta ishga tushirib sinaladi (\ir; fayllar idempotent).
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-10-davomat.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
-- joriy / o'tgan / keyingi oy (Toshkent) — sinf o'zgarganda faqat joriy va keyingi oylar ko'chadi
select set_config('zz.m',  to_char(app.tashkent_now(), 'YYYY-MM'), true),
       set_config('zz.pm', to_char(app.tashkent_now() - interval '1 month', 'YYYY-MM'), true),
       set_config('zz.nm', to_char(app.tashkent_now() + interval '1 month', 'YYYY-MM'), true);
set local iqror.migrating = '1';
insert into public.users (id, email, role, status) values
  ('U_DIR','d@example.org','director','active'), ('U_K5A','k5a@example.org','kurator','active'), ('U_K5B','k5b@example.org','kurator','active'),
  ('U_H7B','h7b@example.org','teacher','active'), ('U_ZAV','z@example.org','zavuch','active'), ('U_REC','r@example.org','reception','active'),
  ('U_PA','pa@example.org','parent','active'), ('U_NUR','n@example.org','nurse','active'), ('U_H8B','h8b@example.org','teacher','active')
on conflict (id) do update set role = excluded.role, status = excluded.status;
update public.users set "assignedClasses" = '["uz-5-A"]'::jsonb where id = 'U_K5A';     -- kurator (assignedClasses)
update public.users set "assignedClasses" = '["uz-5-B"]'::jsonb where id = 'U_K5B';
update public.users set "homeroomClasses" = '["uz-7-B"]'::jsonb where id = 'U_H7B';     -- sinf rahbari (o'qituvchi)
update public.users set "homeroomClasses" = '["uz-8-B"]'::jsonb where id = 'U_H8B';
update public.users set "homeroomClasses" = '["uz-5-A"]'::jsonb where id = 'U_ZAV';     -- O'IBDO' sinf rahbarligi bilan
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "stopFrom", "exitAt", attendance) values
  ('IQ-0501','IQ-0501','Sinov Besh A',5,'A','uz','','',null,null),
  ('IQ-0502','IQ-0502','Sinov Kochadi',5,'A','uz','','',null,null),
  ('IQ-0503','IQ-0503','Sinov Chiqqan',5,'A','uz','chiqdi',to_char(app.tashkent_now(), 'YYYY-MM') || '-01',to_char(app.tashkent_now(), 'YYYY-MM') || '-01',null),
  ('IQ-0504','IQ-0504','Sinov Qabulxona Kochiradi',5,'A','uz','','',null,null),
  ('IQ-0505','IQ-0505','Sinov Foiz',5,'A','uz','','',null,null),
  ('IQ-0506','IQ-0506','Sinov Eski Foiz',5,'A','uz','','',null,null),
  ('IQ-0507','IQ-0507','Sinov Satrsiz',5,'A','uz','','',null,77),
  ('IQ-0508','IQ-0508','Sinov Eski Kun Kaliti',5,'A','uz','','',null,null),
  ('fbL1','','Sinov Eski Kalit',5,'A','uz','','',null,null),
  ('IQ-0701','IQ-0701','Sinov Yetti B',7,'B','uz','','',null,null),
  ('IQ-0702','IQ-0702','Sinov Soxta Satr',7,'B','uz','','',null,null),
  -- eski import to'qnashuvi (test-student-archive.sql bilan bir xil): docK.studentId = boshqa bolaning doc id'si
  ('docK','IQ-0999','Sinov Toqnash A',8,'A','uz','','',null,null),
  ('IQ-0999','','Sinov Toqnash B',8,'B','uz','','',null,null)
on conflict (id) do nothing;
insert into public.child_claims (id, uid, "studentId", code, status) values ('cc_pa','U_PA','IQ-0701','X','active') on conflict (id) do nothing;
-- o'tgan oy tarixi (IQ-0502 hali 5-A da edi) va eski import satri (kun kaliti nolsiz — «1»)
insert into public.attendance (id, "studentId", "classKey", month, days) values
  ('IQ-0502__' || current_setting('zz.pm'), 'IQ-0502', 'uz-5-A', current_setting('zz.pm'), '{"03":"present"}'),
  ('IQ-0508__' || current_setting('zz.m'), 'IQ-0508', 'uz-5-A', current_setting('zz.m'), '{"1":"present"}');
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
-- got NULL bo'lsa ham FAIL ko'rinsin (aks holda natija qatori bo'sh chiqib, JAMI'da sanalmasdi)
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, coalesce(p_got, '<null>'), p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- Holatni o'qish (superuser): VOLATILE — shu buyruqdagi oldingi zz.as amalini ko'radi (oddiy subso'rov buyruq boshidagi suratni o'qirdi).
create or replace function zz.q(p_q text) returns text language plpgsql as $$
declare r text; begin execute p_q into r; return coalesce(r, '<null>'); end $$;
-- admin.html «Saqlash» bilan bir xil yozish: setDoc(doc('attendance', `${sid}__${oy}`), {...}, {merge:true}) = upsert (ON CONFLICT id)
create or replace function zz.up(p_sid text, p_ck text, p_days text, p_m text default null, p_id text default null) returns text language sql as $$
  select format($f$with x as (insert into public.attendance (id, "studentId", "classKey", month, days) values (%L, %L, %L, %L, %L::jsonb)
     on conflict (id) do update set "studentId" = excluded."studentId", "classKey" = excluded."classKey", month = excluded.month, days = excluded.days
     returning 1) select count(*)::text from x$f$,
    coalesce(p_id, p_sid || '__' || coalesce(p_m, current_setting('zz.m'))), p_sid, p_ck, coalesce(p_m, current_setting('zz.m')), p_days)
$$;
create or replace function zz.att(p_id text) returns text language sql as $$ select coalesce((select attendance::text from public.students where id = p_id), 'null') $$;

-- ===== A2-01: boshqa sinf o'quvchisiga yozib bo'lmaydi =====
select zz.chk('D01 5-A kuratori 7-B o''quvchisiga O''Z sinf kaliti bilan satr — rad (42501); noto''g''ri kunlar bilan ham — avval sinf xabari',
  zz.as('U_K5A', zz.up('IQ-0701', 'uz-5-A', '{"02":"absent","03":"absent","04":"sick"}'))
  || ' / ' || zz.as('U_K5A', zz.up('IQ-0701', 'uz-5-A', '{"15a":"sick"}')),
  '^ERR 42501 Davomat: «IQ-0701» bu sinf o''quvchisi emas.* / ERR 42501 Davomat: «IQ-0701» bu sinf o''quvchisi emas');
select zz.chk('D02 5-A kuratori ixtiyoriy id bilan qo''shimcha satr — rad',
  zz.as('U_K5A', zz.up('IQ-0701', 'uz-5-A', '{"01":"sick","02":"sick"}', null, 'zzz-fake')), '^ERR 22023 Davomat: yozuv kaliti');
select zz.chk('D03 mavjud bo''lmagan ID — xuddi shu xabar (ID borligi / qaysi sinfda ekani oshkor bo''lmaydi)',
  zz.as('U_K5A', zz.up('IQ-7777', 'uz-5-A', '{"02":"present"}')), '^ERR 42501 Davomat: «IQ-7777» bu sinf o''quvchisi emas');
select zz.chk('D04 boshqa sinf kaliti bilan — trigger emas, RLS rad etadi (xato matni farq bermaydi)',
  zz.as('U_K5A', zz.up('IQ-0701', 'uz-7-B', '{"02":"absent"}')), '^ERR 42501 new row violates row-level security policy');
select zz.chk('D05 rad etilgan urinishlardan keyin: satr yo''q, 7-B o''quvchisining «Davomat %»i o''zgarmagan (NULL)',
  (select count(*)::text from public.attendance where "studentId" = 'IQ-0701') || '|' || zz.att('IQ-0701'), '^0\|null$');
-- o'z o'quvchisi
select zz.chk('D06 5-A kuratori o''z o''quvchisiga — saqlanadi (upsert)', zz.as('U_K5A', zz.up('IQ-0501', 'uz-5-A', '{"02":"present"}')), '^1$');
select zz.chk('D07 ikkinchi «Saqlash» (mavjud kunlar + yangi kun) — saqlanadi', zz.as('U_K5A', zz.up('IQ-0501', 'uz-5-A', '{"02":"present","03":"late"}')), '^1$');
select zz.chk('D08 o''z o''quvchisi satrining studentId''sini boshqa bolaga almashtirish — rad',
  zz.as('U_K5A', format($q$with x as (update public.attendance set "studentId" = 'IQ-0701' where id = %L returning 1) select count(*)::text from x$q$, 'IQ-0501__' || current_setting('zz.m'))),
  '^ERR 42501 Davomat: yozuvning o''quvchisi va oyi o''zgartirilmaydi');
select zz.chk('D09 id yoki oyni almashtirish — rad',
  zz.as('U_K5A', format($q$with x as (update public.attendance set id = 'IQ-0701__' || month where id = %L returning 1) select count(*)::text from x$q$, 'IQ-0501__' || current_setting('zz.m')))
  || ' / ' || zz.as('U_K5A', format($q$with x as (update public.attendance set month = %L where id = %L returning 1) select count(*)::text from x$q$, current_setting('zz.nm'), 'IQ-0501__' || current_setting('zz.m'))),
  '^ERR 42501 .* / ERR 42501 ');
select zz.chk('D10 kun kaliti / belgisi noto''g''ri — rad (eski «Bemor» qoidasida «15a», «1» ham kasal kun bo''lib sanalardi)',
  zz.as('U_K5A', zz.up('IQ-0501', 'uz-5-A', '{"02":"present","03":"late","15a":"sick"}'))
  || ' / ' || zz.as('U_K5A', zz.up('IQ-0501', 'uz-5-A', '{"02":"present","03":"late","04":"kasal"}'))
  || ' / ' || zz.as('U_K5A', zz.up('IQ-0501', 'uz-5-A', '["02"]'))
  || ' / ' || zz.as('U_K5A', zz.up('IQ-0501', 'uz-5-A', '{"02":"present","03":"late","1":"sick"}')),
  '^ERR 22023 Davomat: «15a» .* / ERR 22023 Davomat: «04» .* / ERR 22023 Davomat: kunlar .* / ERR 22023 Davomat: «1» ');
select zz.chk('D11 noto''g''ri oy — rad', zz.as('U_K5A', zz.up('IQ-0501', 'uz-5-A', '{"02":"present"}', '2026-13')), '^ERR 22023 Davomat: oy');
select zz.chk('D12 eski satrdagi o''zgarmagan nostandart kun («1») saqlashni to''xtatmaydi (yangi kun tekshiriladi)',
  zz.as('U_K5A', zz.up('IQ-0508', 'uz-5-A', '{"1":"present","05":"late"}')) || '|' || zz.as('U_K5A', zz.up('IQ-0508', 'uz-5-A', '{"1":"sick","05":"late"}')),
  '^1\|ERR 22023 Davomat: «1» ');
-- haqiqiy 7-B sinf rahbari (o'qituvchi) — o'z o'quvchisi
select zz.chk('D13 7-B sinf rahbari o''z o''quvchisiga — saqlanadi va satrni ko''radi; 5-A kuratori ko''rmaydi',
  zz.as('U_H7B', zz.up('IQ-0701', 'uz-7-B', '{"02":"present","03":"present"}'))
  || '|' || zz.as('U_H7B', $q$select count(*)::text from public.attendance where "studentId" = 'IQ-0701'$q$)
  || '|' || zz.as('U_K5A', $q$select count(*)::text from public.attendance where "studentId" = 'IQ-0701'$q$), '^1\|1\|0$');
select zz.chk('D14 5-A kuratori 7-B satrini yangilay olmaydi (RLS: 0 qator)',
  zz.as('U_K5A', format($q$with x as (update public.attendance set days = '{"02":"absent"}' where id = %L returning 1) select count(*)::text from x$q$, 'IQ-0701__' || current_setting('zz.m'))), '^0$');
select zz.chk('D15 O''IBDO'' (5-A sinf rahbarligi) — o''z sinfiga saqlanadi, 7-B o''quvchisiga — rad',
  zz.as('U_ZAV', zz.up('IQ-0501', 'uz-5-A', '{"02":"present","03":"late","04":"excused"}'))
  || '|' || zz.as('U_ZAV', zz.up('IQ-0702', 'uz-5-A', '{"02":"absent"}')), '^1\|ERR 42501 Davomat: «IQ-0702»');
select zz.chk('D16 Direktor: to''g''ri sinf — saqlanadi; noto''g''ri sinf kaliti — rad (eskirgan sahifa haqiqiy sinf rahbarini bloklamasin)',
  zz.as('U_DIR', zz.up('IQ-0702', 'uz-7-B', '{"02":"present"}'))
  || '|' || zz.as('U_DIR', zz.up('IQ-0702', 'uz-5-A', '{"02":"present","03":"absent"}')), '^1\|ERR 42501 Davomat: «IQ-0702»');
select zz.chk('D17 ota-ona yoza olmaydi (RLS), o''z farzandi satrini o''qiydi',
  zz.as('U_PA', zz.up('IQ-0701', 'uz-7-B', '{"02":"absent"}')) || '|' || zz.as('U_PA', $q$select count(*)::text from public.attendance where "studentId" = 'IQ-0701'$q$),
  '^ERR 42501 new row violates row-level security policy.*\|1$');
select zz.chk('D18 hamshira / qabulxona yoza olmaydi (RLS)',
  zz.as('U_NUR', zz.up('IQ-0501', 'uz-5-A', '{"05":"sick"}')) || '|' || zz.as('U_REC', zz.up('IQ-0501', 'uz-5-A', '{"05":"sick"}')),
  '^ERR 42501 new row violates.*\|ERR 42501 new row violates');
-- arxivdagi o'quvchi (chiqqan kunigacha), eski kalit (doc id), to'qnash ID — avvalgidek ishlaydi
select zz.chk('D19 arxivdagi o''quvchi (chiqdi) — chiqqan kunigacha belgi qo''yiladi (sinfi o''zgarmaydi)',
  zz.as('U_K5A', zz.up('IQ-0503', 'uz-5-A', '{"01":"present"}')), '^1$');
select zz.chk('D20 eski o''quvchi (studentId bo''sh — doc id kalit) — saqlanadi', zz.as('U_K5A', zz.up('fbL1', 'uz-5-A', '{"02":"present"}')), '^1$');
select zz.chk('D21 eski import to''qnashuvi (bitta ID ikki o''quvchida) — avvalgidek: birining sinfi yetarli',
  zz.as('U_H8B', zz.up('IQ-0999', 'uz-8-B', '{"02":"present"}')), '^1$');
-- oy o'rtasida sinf o'zgarishi
select zz.chk('D22 tayyorgarlik: 5-A kuratori IQ-0502 va IQ-0504 ga shu oy belgisi qo''ydi',
  zz.as('U_K5A', zz.up('IQ-0502', 'uz-5-A', '{"02":"present"}')) || zz.as('U_K5A', zz.up('IQ-0504', 'uz-5-A', '{"02":"present"}')), '^11$');
select zz.chk('D23 Direktor IQ-0502 ni 5-B ga, qabulxona IQ-0504 ni 6-A ga o''tkazadi — shu oy satrlari yangi sinfga ko''chadi (qo''riqchi to''xtatmaydi)',
  zz.as('U_DIR', $q$with x as (update public.students set "classLetter" = 'B' where id = 'IQ-0502' returning 1) select count(*)::text from x$q$)
  || zz.as('U_REC', $q$with x as (update public.students set grade = 6 where id = 'IQ-0504' returning 1) select count(*)::text from x$q$)
  || '|' || zz.q($q$select string_agg("studentId" || '=' || "classKey", ',' order by "studentId") from public.attendance where month = current_setting('zz.m') and "studentId" in ('IQ-0502','IQ-0504')$q$),
  '^11\|IQ-0502=uz-5-B,IQ-0504=uz-6-A$');
select zz.chk('D24 yangi sinf (5-B) kuratori saqlaydi; eski (5-A) kuratori shu oy satrini yangilay olmaydi; eskirgan sahifadan yangi oy satri — rad',
  zz.as('U_K5B', zz.up('IQ-0502', 'uz-5-B', '{"02":"present","03":"absent"}'))
  || '|' || zz.as('U_K5A', format($q$with x as (update public.attendance set days = '{"02":"absent"}' where id = %L returning 1) select count(*)::text from x$q$, 'IQ-0502__' || current_setting('zz.m')))
  || '|' || zz.as('U_K5A', zz.up('IQ-0502', 'uz-5-A', '{"01":"present"}', current_setting('zz.nm'))), '^1\|0\|ERR 42501 Davomat: «IQ-0502»');
select zz.chk('D25 o''tgan oy tarixi o''sha (5-A) sinfida qoladi: 5-A kuratori tuzatadi, sinf kaliti o''zgarmaydi',
  zz.as('U_K5A', format($q$with x as (update public.attendance set days = '{"03":"present","04":"late"}' where id = %L returning "classKey") select string_agg("classKey", ',') from x$q$, 'IQ-0502__' || current_setting('zz.pm'))), '^uz-5-A$');

-- Mustaqil tekshiruv (G2 2-raund): eski (obyekt bo'lmagan) kunlar satri Direktorning sinf almashtirishini to'xtatmaydi; kunlar YOZILSA — tekshiriladi
set local iqror.migrating = '1';
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus") values ('IQ-0509','IQ-0509','Sinov Eski Massiv',5,'A','uz','') on conflict (id) do nothing;
insert into public.attendance (id, "studentId", "classKey", month, days) values ('IQ-0509__' || current_setting('zz.m'), 'IQ-0509', 'uz-5-A', current_setting('zz.m'), '[]');
set local iqror.migrating = '';
select zz.chk('D26 eski satr (days = []) — Direktor sinfni almashtiradi, shu oy satri yangi sinfga ko''chadi (avval 22023 bilan to''xtardi)',
  zz.as('U_DIR', $q$with x as (update public.students set "classLetter" = 'B' where id = 'IQ-0509' returning 1) select count(*)::text from x$q$)
  || '|' || zz.q($q$select "classKey" from public.attendance where id = 'IQ-0509__' || current_setting('zz.m')$q$), '^1\|uz-5-B$');
select zz.chk('D27 kunlar yozilganda baribir tekshiriladi: obyekt bo''lmagan qiymat — rad',
  zz.as('U_K5B', format($q$with x as (update public.attendance set days = '"x"' where id = %L returning 1) select count(*)::text from x$q$, 'IQ-0509__' || current_setting('zz.m'))), '^ERR 22023');

-- ===== A2-01: deploydagi bir martalik tuzatish (avvalgi soxta / eskirgan satrlar) =====
-- qo'riqchidan OLDIN yaratilgan holatni tiklaymiz (baza nomidan — qo'riqchi tizimni tekshirmaydi)
set local iqror.migrating = '1';
insert into public.attendance (id, "studentId", "classKey", month, days) values
  ('IQ-0702__' || current_setting('zz.nm'), 'IQ-0702', 'uz-5-A', current_setting('zz.nm'), '{"02":"absent"}'),   -- keyingi oy, boshqa sinf kaliti
  ('IQ-0701__' || current_setting('zz.pm'), 'IQ-0701', 'uz-5-A', current_setting('zz.pm'), '{"02":"absent"}'),   -- o'tgan oy (tarix)
  ('zzz-soxta-1', 'IQ-0702', 'uz-5-A', current_setting('zz.m'), '{"01":"sick"}'),                                -- kanonik emas
  ('IQ-0999__' || current_setting('zz.nm'), 'IQ-0999', 'uz-5-A', current_setting('zz.nm'), '{"02":"absent"}'),   -- to'qnash ID (2 o'quvchi)
  ('yoq-7777__' || current_setting('zz.nm'), 'yoq-7777', 'uz-5-A', current_setting('zz.nm'), '{"02":"absent"}'); -- o'quvchisi yo'q
set local iqror.migrating = '';
select zz.chk('E01 tayyorgarlik: haqiqiy 7-B sinf rahbari keyingi oy satrini saqlay olmaydi (USING)',
  zz.as('U_H7B', zz.up('IQ-0702', 'uz-7-B', '{"02":"present"}', current_setting('zz.nm'))), '^ERR 42501 new row violates row-level security policy \(USING expression\)');
\set iqror_chain 1
\ir audit-10-davomat.sql
select zz.chk('E02 deploy (audit-10-davomat.sql qayta): joriy/keyingi oy satrlari haqiqiy sinfga o''tdi (kanonik bo''lmagani ham); o''tgan oy, to''qnash ID va o''quvchisiz satr tegilmadi',
  (select string_agg(id || '=' || "classKey", ',' order by id) from public.attendance
    where id in ('IQ-0702__' || current_setting('zz.nm'), 'IQ-0701__' || current_setting('zz.pm'), 'zzz-soxta-1', 'IQ-0999__' || current_setting('zz.nm'), 'yoq-7777__' || current_setting('zz.nm'))),
  '^IQ-0701__[0-9-]+=uz-5-A,IQ-0702__[0-9-]+=uz-7-B,IQ-0999__[0-9-]+=uz-5-A,yoq-7777__[0-9-]+=uz-5-A,zzz-soxta-1=uz-7-B$');
select zz.chk('E03 boshqa joriy satrlar (qo''riqchi ostida yozilgan) o''zgarmadi', (select string_agg("studentId" || '=' || "classKey", ',' order by "studentId") from public.attendance
    where month = current_setting('zz.m') and "studentId" in ('IQ-0501','IQ-0502','IQ-0504','fbL1','IQ-0999')), '^IQ-0501=uz-5-A,IQ-0502=uz-5-B,IQ-0504=uz-6-A,IQ-0999=uz-8-B,fbL1=uz-5-A$');
select zz.chk('E04 endi haqiqiy sinf rahbari saqlaydi; kanonik bo''lmagan satr o''chirilmaydi (faqat ogohlantiriladi)',
  zz.as('U_H7B', zz.up('IQ-0702', 'uz-7-B', '{"02":"present"}', current_setting('zz.nm'))) || '|' || zz.q($q$select count(*)::text from public.attendance where id = 'zzz-soxta-1'$q$), '^1\|1$');
select zz.chk('E05 qo''riqchi deploydan keyin ham joyida (qayta yaratildi)', zz.as('U_K5A', zz.up('IQ-0701', 'uz-5-A', '{"02":"absent"}')), '^ERR 42501 Davomat:');

-- ===== A2-05: «Davomat %» hisoblanadigan kun qolmasa tozalanadi =====
select zz.chk('P01 yagona «Yo''q» — 0%', zz.as('U_K5A', zz.up('IQ-0505', 'uz-5-A', '{"16":"absent"}')) || '|' || zz.att('IQ-0505'), '^1\|0$');
select zz.chk('P02 «Bemor»ga tuzatildi — foiz yo''q (NULL), eski 0% qolmaydi', zz.as('U_K5A', zz.up('IQ-0505', 'uz-5-A', '{"16":"sick"}')) || '|' || zz.att('IQ-0505'), '^1\|null$');
select zz.chk('P03 «Sababli» ham — NULL; yana hisoblanadigan kun — foiz qaytadi ((keldi + kech) / jami)',
  zz.as('U_K5A', zz.up('IQ-0505', 'uz-5-A', '{"16":"sick","17":"excused"}')) || '|' || zz.att('IQ-0505')
  || '|' || zz.as('U_K5A', zz.up('IQ-0505', 'uz-5-A', '{"16":"sick","17":"excused","18":"present","19":"late","20":"absent"}')) || '|' || zz.att('IQ-0505'), '^1\|null\|1\|67$');
-- deploy backfill: avval qolib ketgan eski 0% (faqat «Bemor»/«Sababli» satrli o'quvchi) tozalanadi; satrsiz o'quvchiga tegilmaydi
set local iqror.migrating = '1';
insert into public.attendance (id, "studentId", "classKey", month, days) values ('IQ-0506__' || current_setting('zz.pm'), 'IQ-0506', 'uz-5-A', current_setting('zz.pm'), '{"10":"sick","11":"excused"}');
update public.students set attendance = 0 where id = 'IQ-0506';    -- tuzatishdan oldin qolib ketgan qiymat
update public.students set attendance = 95 where id = 'IQ-0701';   -- satrlari bor (hisoblanadigan kun bor) — qayta hisoblanadi
set local iqror.migrating = '';
\ir attendance-sync.sql
select zz.chk('P04 deploy (attendance-sync.sql qayta): faqat «Bemor»/«Sababli» — NULL; hisoblanadigan kunli — qayta hisoblandi',
  zz.att('IQ-0506') || '|' || zz.att('IQ-0701'), '^null\|67$');
select zz.chk('P05 davomat satri yo''q o''quvchiga tegilmaydi (qo''lda kiritilgan qiymat qoladi)', zz.att('IQ-0507'), '^77$');

-- ===== A2-04: ID yuqori chegarasi va tarix =====
--   IQ-2149 — tirik; IQ-2150 — xato yaratilgan (tarixsiz) yozuv; IQ-2160 — eng oxirgi (sinov) bola, hamshira yozuvlari bilan. Ikkalasi o'chiriladi.
set local iqror.migrating = '1';
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus") values
  ('IQ-2149','IQ-2149','Sinov Boshqa',5,'A','uz',''), ('IQ-2150','IQ-2150','Sinov Xato Yaratilgan',5,'A','uz',''), ('IQ-2160','IQ-2160','Sinov Eski Bola',5,'A','uz','sinov');
insert into public.student_private (id, "parentPhone") values ('IQ-2150','+998900002150'), ('IQ-2160','+998900002160') on conflict (id) do nothing;
-- hamshira yozuvlari (o'quvchi bor paytda kiritilgan; triggerlar — fayl / ish kuni tekshiruvi — bu sinov mavzusi emas)
set local session_replication_role = replica;
insert into public.student_health (id, "studentId", allergies, chronic) values ('IQ-2160','IQ-2160','Sinov allergiya','Sinov surunkali'), ('IQ-2149','IQ-2149','Sinov',null);
insert into public.nurse_visits (id, "studentId", complaint, temperature, action, "nurseUid") values ('nv_t1','IQ-2160','Sinov shikoyat',37.9,'parent_call','U_NUR');
insert into public.sick_notes (id, "studentId", "fromDay", "toDay", status) values ('sn_t1','IQ-2160','2026-11-02','2026-11-03','pending');
set local session_replication_role = origin;
set local iqror.migrating = '';
select zz.chk('H01 tirik o''quvchi tarixida tibbiy yozuv (o''chirish oynasi uchun «medical»)',
  zz.as('U_DIR', $q$select (public.student_history('IQ-2149') ->> 'medical')$q$), '^1$');
-- eng katta ID'li ikkala o'quvchi o'chiriladi (panel: students + student_private + student_codes)
select zz.chk('H02 Direktor o''chiradi', zz.as('U_DIR', $q$with a as (delete from public.students where id in ('IQ-2150','IQ-2160') returning 1),
  b as (delete from public.student_private where id in ('IQ-2150','IQ-2160') returning 1), c as (delete from public.student_codes where id in ('IQ-2150','IQ-2160') returning 1)
  select (select count(*) from a)::text$q$), '^2$');
select zz.chk('H03 yuqori chegara o''chirilgan ID''lardan past tushmaydi (o''chirilganlar arxivi + tibbiyot): 2160 — keyingi yangi ID IQ-2161 (avval 2149 -> IQ-2150 qayta berilardi)',
  zz.as('U_DIR', $q$select public.student_id_high_water()::text$q$), '^2160$');
select zz.chk('H04 tarix: tibbiy 3 ta (karta, murojaat, ma''lumotnoma) — Direktorga; other ≥ 1 (tibbiyot — bor/yo''q), arxiv (private) ≥ 1 — yangi ID tekshiruvi rad etadi',
  zz.as('U_DIR', $q$select (h ->> 'medical') || '|' || ((h ->> 'other')::int >= 1)::text || '|' || ((h ->> 'private')::int >= 1)::text from (select public.student_history('IQ-2160') h) x$q$), '^3\|true\|true$');
select zz.chk('H04b boshqa xodim (o''qituvchi) — tibbiy yozuvlar soni ko''rinmaydi (null), «other»da tibbiyot faqat bor/yo''q (1)',
  zz.as('U_H7B', $q$select coalesce(h ->> 'medical', 'null') || '|' || (h ->> 'other') from (select public.student_history('IQ-2149') h) x$q$), '^null\|1$');
select zz.chk('H05 tarixsiz (xato yaratilgan) o''chirilgan o''quvchi — arxiv tufayli «private» ≥ 1 (ID qo''lda ham berilmaydi)',
  zz.as('U_DIR', $q$select ((public.student_history('IQ-2150') ->> 'private')::int >= 1)::text$q$), '^true$');
-- har bir yangi manba alohida: raqam har safar kattaroq, har qo'shilgandan keyin funksiya (Direktor nomidan) shu raqamni qaytarishi kerak
create temp table zz_hw (n int, src text, got int) on commit drop;
do $hw$
declare r record; v int := 3000; g int;
begin
  for r in select * from (values
      ('student_health.id',          $s$insert into public.student_health (id, "studentId") values ('IQ-%1$s','x')$s$),
      ('student_health.studentId',   $s$insert into public.student_health (id, "studentId") values ('h%1$s','IQ-%1$s')$s$),
      ('sick_notes',                 $s$insert into public.sick_notes (id, "studentId", "fromDay", "toDay") values ('s%1$s','IQ-%1$s','2026-11-02','2026-11-02')$s$),
      ('nurse_visits',               $s$insert into public.nurse_visits (id, "studentId") values ('v%1$s','IQ-%1$s')$s$),
      ('discount_requests',          $s$insert into public.discount_requests (id, "studentId", kind) values ('d%1$s','IQ-%1$s','none')$s$),
      ('referral_requests.id',       $s$insert into public.referral_requests (id, "referrerId") values ('IQ-%1$s','x')$s$),
      ('referral_requests.referrer', $s$insert into public.referral_requests (id, "referrerId") values ('r%1$s','IQ-%1$s')$s$),
      ('referral_ledger.id',         $s$insert into public.referral_ledger (id, "referrerId") values ('IQ-%1$s','x')$s$),
      ('referral_ledger.referrer',   $s$insert into public.referral_ledger (id, "referrerId") values ('l%1$s','IQ-%1$s')$s$),
      ('monitoring_bonus',           $s$insert into public.monitoring_bonus (id, "studentId", period) values ('b%1$s','IQ-%1$s','2026-11')$s$),
      ('deleted_records.rowId',      $s$insert into public.deleted_records (tbl, "rowId", row) values ('student_codes','IQ-%1$s','{}')$s$),
      ('deleted_records.studentId',  $s$insert into public.deleted_records (tbl, "rowId", row) values ('students','doc%1$s','{"studentId":"IQ-%1$s"}')$s$)
    ) t(src, q) loop
    v := v + 1;
    perform set_config('session_replication_role', 'replica', true);
    execute format(r.q, v);
    perform set_config('session_replication_role', 'origin', true);
    perform set_config('request.jwt.claims', json_build_object('sub', 'U_DIR', 'role', 'authenticated')::text, true);
    g := public.student_id_high_water();
    perform set_config('request.jwt.claims', '', true);
    insert into zz_hw values (v, r.src, g);
  end loop;
end $hw$;
select zz.chk('H06 yangi manbalarning har biri yuqori chegaraga kiradi (12 ta manba)',
  (select string_agg(src || '=' || (got = n)::text, ',' order by n) from zz_hw),
  '^student_health.id=true,student_health.studentId=true,sick_notes=true,nurse_visits=true,discount_requests=true,referral_requests.id=true,referral_requests.referrer=true,referral_ledger.id=true,referral_ledger.referrer=true,monitoring_bonus=true,deleted_records.rowId=true,deleted_records.studentId=true$');
set local iqror.migrating = '1';
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-12345678901','IQ-12345678901','Sinov Uzun ID',5,'A','uz');
set local iqror.migrating = '';
select zz.chk('H07 10+ xonali xato ID funksiyani buzmaydi (int chegarasi) — e''tiborsiz qoldiriladi',
  zz.as('U_DIR', $q$select public.student_id_high_water()::text$q$), '^3012$');
select zz.chk('H08 xodim bo''lmagan (ota-ona) — 0 va tarix yo''q', zz.as('U_PA', $q$select public.student_id_high_water()::text || '|' || coalesce(public.student_history('IQ-2160')::text, 'null')$q$), '^0\|null$');

-- ===== A1-11: o'chirilgan o'quvchini tiklash =====
set local iqror.migrating = '1';
insert into public.teachers (id, name, "teacherId") values ('t9','Sinov Ustoz Toqqiz','IQT-009'), ('t10','Sinov Ustoz Un','IQT-010');
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values
  ('IQ-0401','IQ-0401','Sinov Xodim Farzandi',4,'A','uz'), ('IQ-0402','IQ-0402','Sinov Xodim Farzandi Ikki',4,'A','uz');
insert into public.student_private (id, "parentPhone", "teacherId") values ('IQ-0401','+998900000401','IQT-009'), ('IQ-0402','+998900000402','IQT-010')
  on conflict (id) do update set "parentPhone" = excluded."parentPhone", "teacherId" = excluded."teacherId";
set local iqror.migrating = '';
select zz.chk('R01 tayyorgarlik: Direktor ikkala xodim farzandini o''chiradi, keyin o''qituvchi IQT-009 ni ham',
  zz.as('U_DIR', $q$with a as (delete from public.students where id in ('IQ-0401','IQ-0402') returning 1), b as (delete from public.student_private where id in ('IQ-0401','IQ-0402') returning 1),
    c as (delete from public.student_codes where id in ('IQ-0401','IQ-0402') returning 1) select (select count(*) from a)::text || (select count(*) from b)::text$q$)
  || '|' || zz.as('U_DIR', $q$with t as (delete from public.teachers where id = 't9' returning 1) select count(*)::text from t$q$), '^22\|1$');
select zz.chk('R02 o''chgan o''qituvchiga bog''langan farzand TIKLANADI: bog''lanish bo''sh, javobda teacherUnlinked, telefon saqlangan',
  zz.as('U_DIR', $q$select (r ->> 'ok') || '/' || (r ->> 'private') || '/' || coalesce(r ->> 'teacherUnlinked', '-') from (select public.restore_deleted_student(
      (select id from public.deleted_records where tbl = 'students' and "rowId" = 'IQ-0401')) r) x$q$)
  || '|' || zz.q($q$select coalesce((select coalesce("teacherId", 'null') || '/' || coalesce("parentPhone", '-') from public.student_private where id = 'IQ-0401'), 'yo''q')$q$),
  '^true/true/IQT-009\|null/\+998900000401$');
select zz.chk('R03 o''qituvchisi bor farzand — bog''lanish saqlanadi (teacherUnlinked yo''q)',
  zz.as('U_DIR', $q$select (r ->> 'ok') || '/' || coalesce(r ->> 'teacherUnlinked', '-') from (select public.restore_deleted_student(
      (select id from public.deleted_records where tbl = 'students' and "rowId" = 'IQ-0402')) r) x$q$)
  || '|' || zz.q($q$select "teacherId" from public.student_private where id = 'IQ-0402'$q$), '^true/-\|IQT-010$');
-- qayta berilgan ID: birinchi oila 2 kun oldin o'chirilgan, keyin shu ID ikkinchi oilaga berilib, u ham o'chirilgan
set local iqror.migrating = '1';
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-0600','IQ-0600','Sinov Birinchi Bola',2,'A','uz');
insert into public.student_private (id, "parentPhone", "fatherName") values ('IQ-0600','+998900000601','Sinov Birinchi Ota')
  on conflict (id) do update set "parentPhone" = excluded."parentPhone", "fatherName" = excluded."fatherName";
update public.student_codes set code = 'AAAAAA000601' where id = 'IQ-0600';
set local iqror.migrating = '';
select zz.chk('R04 tayyorgarlik: birinchi oila o''chirildi', zz.as('U_DIR', $q$with a as (delete from public.students where id = 'IQ-0600' returning 1), b as (delete from public.student_private where id = 'IQ-0600' returning 1),
    c as (delete from public.student_codes where id = 'IQ-0600' returning 1) select (select count(*) from a)::text || (select count(*) from b)::text || (select count(*) from c)::text$q$), '^111$');
update public.deleted_records set "deletedAt" = now() - interval '2 days' where "rowId" = 'IQ-0600';   -- alohida (oldingi) o'chirish
set local iqror.migrating = '1';
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-0600','IQ-0600','Sinov Ikkinchi Bola',7,'B','uz');
insert into public.student_private (id, "parentPhone", "fatherName") values ('IQ-0600','+998900000602','Sinov Ikkinchi Ota')
  on conflict (id) do update set "parentPhone" = excluded."parentPhone", "fatherName" = excluded."fatherName";
update public.student_codes set code = 'BBBBBB000602' where id = 'IQ-0600';
set local iqror.migrating = '';
select zz.chk('R05 tayyorgarlik: ikkinchi oila ham o''chirildi', zz.as('U_DIR', $q$with a as (delete from public.students where id = 'IQ-0600' returning 1), b as (delete from public.student_private where id = 'IQ-0600' returning 1),
    c as (delete from public.student_codes where id = 'IQ-0600' returning 1) select (select count(*) from a)::text || (select count(*) from b)::text || (select count(*) from c)::text$q$), '^111$');
select zz.chk('R06 BIRINCHI oilaning arxivi tiklanadi: o''z telefoni, ota ismi va kodi (ikkinchi oilaniki yopishmaydi)',
  zz.as('U_DIR', $q$select (r ->> 'ok') || '/' || (r ->> 'private') from (select public.restore_deleted_student(
      (select id from public.deleted_records where tbl = 'students' and "rowId" = 'IQ-0600' and row ->> 'name' = 'Sinov Birinchi Bola')) r) x$q$)
  || '|' || zz.q($q$select s.name || '/' || p."parentPhone" || '/' || p."fatherName" from public.students s join public.student_private p on p.id = s.id where s.id = 'IQ-0600'$q$)
  || '|' || zz.q($q$select code from public.student_codes where id = 'IQ-0600'$q$),
  '^true/true\|Sinov Birinchi Bola/\+998900000601/Sinov Birinchi Ota\|AAAAAA000601$');
select zz.chk('R07 ikkinchi oilaning arxivi tegilmagan (tiklanmagan deb qoladi); uni tiklash — ID band, rad',
  zz.q($q$select string_agg(tbl || '=' || ("restoredAt" is null)::text, ',' order by tbl) from public.deleted_records where "rowId" = 'IQ-0600' and "deletedAt" = now()$q$)
  || '|' || zz.as('U_DIR', $q$select public.restore_deleted_student((select id from public.deleted_records where tbl = 'students' and "rowId" = 'IQ-0600' and row ->> 'name' = 'Sinov Ikkinchi Bola')) ->> 'ok'$q$),
  '^student_codes=true,student_private=true,students=true\|false$');
select zz.chk('R08 faqat Direktor tiklaydi', zz.as('U_REC', $q$select public.restore_deleted_student('x')::text$q$), '^ERR 42501');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
