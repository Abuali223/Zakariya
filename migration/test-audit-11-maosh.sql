-- =====================================================================
-- test-audit-11-maosh.sql — audit-11 (H2: maosh, xodimlar, foydalanuvchilar) tuzatishlari sinovi:
--   (A5-01) maosh darvozasi: manfiy summa faqat kassa funksiyasidan (har qanday oyda), o'tish oyidan oldingi oy — faqat Direktor,
--           o'tish oyidan boshlab yozuvdagi maosh / ushlanma / avans — tasdiqlangan vedomostdan; oldingi qoldiq soxta «gross»ga
--           ishonmaydi; xodim avansi — musbat (kassadan tashqari); o'rinbosarlik — dars soni va stavka chegarasi;
--   (A5-02) qayta ochilib kamroq summa bilan qayta tasdiqlangan oy: ortiqcha berilgani keyingi oyga manfiy qoldiq, 0 so'mlik
--           tuzatish yozuvi qabul qilinadi, yuborishda ortiqcha ko'rsatiladi;
--   (A5-03) kelgusi oy vedomosti yuborilmaydi / tasdiqlanmaydi, tugamagan oyni faqat Direktor tasdiqlaydi;
--   (A5-04) login hisobi o'chirilganda kartadagi havola bo'shaydi, osilib qolgan havolalar migratsiyada tozalanadi (fayl qayta
--           ishga tushiriladi — idempotentlik ham tekshiriladi);
--   (A5-05) o'z hisobini o'chirish / rolini o'zgartirish va oxirgi faol Direktorni olib tashlash — rad (server — mumkin);
--   (A5-06) «Direktor tasdig'i kerak» belgisi tasdiqlash paytida qayta tekshiriladi;
--   (A5-08) vedomost ishtirokchilari ismi — maosh ko'radigan rollarga, faqat ishtirokchilar, buxgalterga yo'q.
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub) — RLS va GRANT haqiqiy. Sana — sinov soati (app.fin_clock; faqat
--   fx_* / sinov / test nomli bazada): bugun 2026-12-10, o'tish oyi 2026-09.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin, migration/ papkasidan:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && (cd migration && psql -d sinov -X -f test-audit-11-maosh.sql)
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-11-maosh.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, verified, "extraRoles", "staffRefType", "staffRefId") values
  ('U_DIR','d@example.org','Sinov Direktor','director','active',true,'[]',null,null),
  ('U_DIR2','d2@example.org','Sinov Direktor Ikki','director','active',true,'[]',null,null),
  ('U_HR','h@example.org','Sinov Kadrlar','hr','active',true,'[]',null,null),
  ('U_FM','f@example.org','Sinov Moliyachi','finance_mgr','active',true,'[]',null,null),
  ('U_KAS','k@example.org','Sinov Kassir','kassir','active',true,'[]',null,null),
  ('U_ACC','b@example.org','Sinov Buxgalter','accountant','active',true,'[]',null,null),
  ('U_T9','t9@example.org','Sinov Yangi Kadr','teacher','active',true,'[]',null,null),
  ('U_TCH','t@example.org','Sinov Oqituvchi','teacher','active',true,'[]',null,null),
  ('U_X','x@example.org','Sinov Eski Hisob','teacher','active',true,'[]','staff','s2')
on conflict (id) do update set role = excluded.role, status = excluded.status, name = excluded.name;
insert into public.teachers (id, "teacherId", name, "userUid") values
  ('t1','IQT-901','Sinov Oqituvchi Bir',null), ('t9','IQT-909','Sinov Yangi Kadr Kartasi','U_T9');
insert into public.staff (id, "staffId", name, "userUid") values
  ('s1','IQX-901','Sinov Xodim Bir',null), ('s2','IQX-902','Sinov Xodim Ikki','U_X'), ('s3','IQX-903','Sinov Xodim Uch','U_GONE');
insert into public.config (id, "payrollApprovalFrom") values ('finance', '2026-09')
  on conflict (id) do update set "payrollApprovalFrom" = excluded."payrollApprovalFrom";
insert into app.fin_clock (id, t) values (1, '2026-12-10 10:00+05') on conflict (id) do update set t = excluded.t;
set local session_replication_role = origin;

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
-- Server: faqat JWT da'vosi (service_role) — lokal bazada service_role RLS'ni chetlab o'tmaydi, shuning uchun postgres nomidan.
create or replace function zz.sys(p_q text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  begin execute p_q into r; exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, p_got ~ p_pat); end $$;
-- maosh yozuvi: (id, maosh ID, oy, berilgan, mijoz yuborgan gross, sana)
create or replace function zz.sp(p_id text, p_tid text, p_month text, p_paid numeric, p_gross numeric, p_date text) returns text language sql as $$
  select format($f$with x as (insert into public.salary_payments (id, "teacherId", month, gross, advance, deduction, "subBonus", net, paid, date)
                    values (%L, %L, %L, %s, 0, 0, 0, %s, %s, %L) returning id) select id from x$f$, p_id, p_tid, p_month, p_gross, p_gross, p_paid, p_date) $$;
create or replace function zz.row(p_id text) returns text language sql as $$
  select coalesce((select trim_scale(gross) || '/' || trim_scale(deduction) || '/' || trim_scale(advance) || '/' || trim_scale("subBonus") || '/'
                          || trim_scale(paid) || '/' || trim_scale("carryIn") || '/' || trim_scale("carryOut")
                     from public.salary_payments where id = p_id), '<yo''q>') $$;

-- ===== (A5-01) maosh darvozasi va oldingi qoldiq — o'tish oyidan (2026-09) =====
select zz.chk('G00 Moliya menejeri 2026-09 vedomostini yuboradi, HR tasdiqlaydi',
  (zz.as('U_FM', $q$select public.payroll_submit('2026-09', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'ok'$q$)) || '|'
  || zz.as('U_HR', $q$select public.payroll_decide('2026-09', true, null)->>'status'$q$), '^true\|approved$');
select zz.chk('G01 kassir tasdiqlangan oyga manfiy summa yoza olmaydi', zz.as('U_KAS', zz.sp('g_neg', 'IQX-901', '2026-09', -1000000, 2000000, '2026-10-01')),
  '^ERR 23514 .*manfiy bo''lmaydi');
select zz.chk('G02 kassir soxta gross (9 000 000) bilan 2 000 000 beradi — yoziladi, lekin maosh / ushlanma / qoldiq vedomostdan',
  zz.as('U_KAS', zz.sp('g_pay', 'IQX-901', '2026-09', 2000000, 9000000, '2026-10-01')) || ' ' || zz.row('g_pay'), '^g_pay 2000000/0/0/0/2000000/0/0$');
select zz.chk('G03 oldingi qoldiq soxta gross''ga ishonmaydi (2026-10 uchun 0, avval 7 000 000 bo''lardi)', app.salary_carry('IQX-901', '2026-10')::text, '^0$');
select zz.chk('G04 keyinroq sanali soxta 0 so''mlik yozuv (gross 9 000 000) — qabul qilinadi, qoldiq o''zgarmaydi',
  zz.as('U_KAS', zz.sp('g_zero', 'IQX-901', '2026-09', 0, 9000000, '2026-10-05')) || ' ' || app.salary_carry('IQX-901', '2026-10'), '^g_zero 0$');
select zz.chk('G05 kassir o''tish oyidan oldingi oyga (2026-08) soxta qator yoza olmaydi — faqat Direktor',
  zz.as('U_KAS', zz.sp('g_old', 'IQX-901', '2026-08', 0, 9000000, '2026-10-01')), '^ERR 42501 .*faqat Direktor yozadi');
select zz.chk('G05b HR va Moliya menejeri ham', zz.as('U_HR', zz.sp('g_old2', 'IQX-901', '2026-08', 0, 9000000, '2026-10-01')) || ' / '
  || zz.as('U_FM', zz.sp('g_old3', 'IQX-901', '2026-08', 0, 9000000, '2026-10-01')), '^ERR 42501 .*faqat Direktor.* / ERR 42501 .*faqat Direktor');
select zz.chk('G06 Direktor eski tartibdagi oy maoshini yozadi (o''zgarishsiz)', zz.as('U_DIR', zz.sp('g_dir', 'IQX-901', '2026-08', 1000000, 1000000, '2026-10-01')), '^g_dir$');
savepoint g7;
set local session_replication_role = replica;
update public.config set "payrollApprovalFrom" = null where id = 'finance';
set local session_replication_role = origin;
select zz.chk('G07 o''tish oyi belgilanmagan: manfiy summa baribir rad; eski tartib (kassir yozadi, qoldiq — yozuvlardan) o''zgarmagan',
  zz.as('U_KAS', zz.sp('g7_neg', 'IQX-901', '2026-05', -1, 1000000, '2026-06-01')) || ' / '
  || zz.as('U_KAS', zz.sp('g7_pay', 'IQX-901', '2026-05', 600000, 1000000, '2026-06-01')) || ' / ' || app.salary_carry('IQX-901', '2026-06'),
  '^ERR 23514 .*manfiy bo''lmaydi.* / g7_pay / 400000$');
rollback to savepoint g7;

-- xodim avansi — musbat (kassa funksiyasidan tashqari)
select zz.chk('A01 Moliya menejeri manfiy va nol avans yoza olmaydi',
  zz.as('U_FM', $q$with x as (insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date) values ('a_neg','IQX-901','Sinov',-500000,'2027-01','2027-01-03') returning id) select id from x$q$) || ' / '
  || zz.as('U_FM', $q$with x as (insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date) values ('a_nol','IQX-901','Sinov',0,'2027-01','2027-01-03') returning id) select id from x$q$),
  '^ERR 23514 .*musbat.* / ERR 23514 .*musbat');
select zz.chk('A02 musbat avans — yoziladi; summasini manfiyga o''zgartirib bo''lmaydi',
  zz.as('U_FM', $q$with x as (insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date) values ('a_ok','IQX-901','Sinov',300000,'2027-01','2027-01-03') returning id) select id from x$q$) || ' / '
  || zz.as('U_FM', $q$with x as (update public.staff_advances set amount = -300000 where id = 'a_ok' returning id) select id from x$q$),
  '^a_ok / ERR 23514 .*musbat');
select set_config('iqror.kassa_rpc', '1', true);
select zz.chk('A03 kassa funksiyasi ichida (bayroq) manfiy avans — o''tadi (avans qaytimi)',
  zz.as('U_FM', $q$with x as (insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date) values ('a_ret','IQX-901','Sinov',-100000,'2027-01','2027-01-04') returning id) select id from x$q$), '^a_ret$');
select set_config('iqror.kassa_rpc', '', true);

-- o'rinbosarlik — dars soni va stavka chegarasi
select zz.chk('S01 HR 1000 darsli yoki 1 000 000 so''m stavkali o''rinbosarlik yoza olmaydi',
  zz.as('U_HR', $q$with x as (insert into public.staff_substitutions (id, day, month, "absentRefType", "absentRefId", "subRefType", "subRefId", lessons, "ratePerLesson") values ('sb1','2027-01-05','2027-01','teacher','t1','staff','s1',1000,40000) returning id) select id from x$q$) || ' / '
  || zz.as('U_HR', $q$with x as (insert into public.staff_substitutions (id, day, month, "absentRefType", "absentRefId", "subRefType", "subRefId", lessons, "ratePerLesson") values ('sb2','2027-01-05','2027-01','teacher','t1','staff','s1',2,1000000) returning id) select id from x$q$),
  '^ERR 23514 .*dars soni.* / ERR 23514 .*dars haqi');
select zz.chk('S02 me''yordagi yozuv (2 dars × 40 000) va eski format (dars sonisiz) — yoziladi',
  zz.as('U_HR', $q$with x as (insert into public.staff_substitutions (id, day, month, "absentRefType", "absentRefId", "subRefType", "subRefId", lessons, "ratePerLesson") values ('sb3','2027-01-05','2027-01','teacher','t1','staff','s1',2,40000) returning id) select id from x$q$) || ' / '
  || zz.as('U_HR', $q$with x as (insert into public.staff_substitutions (id, day, month, "absentRefType", "absentRefId", "subRefType", "subRefId") values ('sb4','2027-01-06','2027-01','teacher','t1','staff','s1') returning id) select id from x$q$),
  '^sb3 / sb4$');
update public.config set "lessonRate" = 50000 where id = 'finance';
select zz.chk('S03 Direktor «1 dars haqi»ni 50 000 qilgan: 50 000 — mumkin, 50 001 — yo''q',
  zz.as('U_HR', $q$with x as (insert into public.staff_substitutions (id, day, month, "absentRefType", "absentRefId", "subRefType", "subRefId", lessons, "ratePerLesson") values ('sb5','2027-01-07','2027-01','teacher','t1','staff','s1',1,50000) returning id) select id from x$q$) || ' / '
  || zz.as('U_HR', $q$with x as (insert into public.staff_substitutions (id, day, month, "absentRefType", "absentRefId", "subRefType", "subRefId", lessons, "ratePerLesson") values ('sb6','2027-01-08','2027-01','teacher','t1','staff','s1',1,50001) returning id) select id from x$q$),
  '^sb5 / ERR 23514 .*50000 so''m');

-- ===== (A5-02) qayta ochilib kamroq summa bilan qayta tasdiqlangan oy =====
select zz.chk('B00 2026-10: yuborildi (2 000 000), tasdiqlandi, kassir 2 000 000 berdi, Direktor qayta ochdi',
  (zz.as('U_FM', $q$select public.payroll_submit('2026-10', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'payable'$q$)) || '|'
  || zz.as('U_HR', $q$select public.payroll_decide('2026-10', true, null)->>'status'$q$) || '|'
  || zz.as('U_KAS', zz.sp('b_pay', 'IQX-901', '2026-10', 2000000, 2000000, '2026-11-01')) || '|'
  || zz.as('U_DIR', $q$select public.payroll_reopen('2026-10', 'Yo''qlama topildi')->>'status'$q$), '^2000000\|approved\|b_pay\|returned$');
select zz.chk('B01 qayta yuborish (ushlanma 500 000): to''lanadigan 1 500 000, ortiqcha berilgani ko''rsatiladi (1 xodim, 500 000)',
  (select (j->>'payable') || '|' || (j->>'overpaid') || '|' || (j->>'overpaidSum')
     from (select zz.as('U_FM', $q$select public.payroll_submit('2026-10', '[{"personType":"staff","personId":"IQX-901","gross":2000000,"deduction":500000}]'::jsonb, null)::text$q$)::jsonb as j) q),
  '^1500000\|1\|500000$');
select zz.as('U_HR', $q$select public.payroll_decide('2026-10', true, null)->>'status'$q$) as b02 \gset
select zz.chk('B02 HR qayta tasdiqlaydi — ortiqcha 500 000 keyingi oyga MANFIY qoldiq (avval 0 bo''lardi)',
  :'b02' || '|' || app.salary_carry('IQX-901', '2026-11'), '^approved\|-500000$');
select zz.chk('B03 0 so''mlik tuzatish yozuvi qabul qilinadi (avval «berish mumkin: 0» deb rad), qoldiq o''zgarmaydi; qatorda qoldiq −500 000',
  zz.as('U_KAS', zz.sp('b_fix', 'IQX-901', '2026-10', 0, 2000000, '2026-11-20')) || ' ' || zz.row('b_fix') || ' ' || app.salary_carry('IQX-901', '2026-11'),
  '^b_fix 2000000/500000/0/0/0/0/-500000 -500000$');
select zz.chk('B04 summa chegarasi saqlanadi: yana 1 so''m ham berilmaydi', zz.as('U_KAS', zz.sp('b_more', 'IQX-901', '2026-10', 1, 2000000, '2026-11-20')),
  '^ERR 23514 .*berish mumkin: 0');

-- ===== (A5-06) yangi oy: vedomost yuborilgandan keyin xodimga HR roli berildi — tasdiqlashda Direktor tasdig'iga o'tadi =====
select zz.chk('D00 2026-11 yuborildi: xodim (qoldiq −500 000 → 1 500 000) va o''qituvchi (karta U_T9 ga bog''langan, hozircha o''qituvchi — tasdiqsiz)',
  (zz.as('U_FM', $q$select public.payroll_submit('2026-11', '[{"personType":"staff","personId":"IQX-901","gross":2000000},{"personType":"teacher","personId":"IQT-909","gross":2500000}]'::jsonb, null)->>'count'$q$))
  || '|' || (select trim_scale("carryIn") || ':' || trim_scale(payable) from public.payroll_lines where "runId" = '2026-11' and "personId" = 'IQX-901')
  || '|' || (select "needsDirector"::text from public.payroll_lines where "runId" = '2026-11' and "personId" = 'IQT-909'), '^2\|-500000:1500000\|false$');
select zz.as('U_DIR', $q$with u as (update public.users set role = 'hr' where id = 'U_T9' returning 1) select count(*)::text from u$q$) as d01a \gset
select coalesce(j->>'status', '-') || ':' || coalesce(j->>'moved', '-') as d01b from (select zz.as('U_T9', $q$select public.payroll_decide('2026-11', true, null)::text$q$)::jsonb as j) q \gset
select zz.chk('D01 Direktor U_T9 ni HR qiladi; yangi HR vedomostni tasdiqlaydi — o''z qatori Direktor tasdig''iga o''tkazildi (moved 1)',
  :'d01a' || '|' || :'d01b' || '|' || (select "needsDirector"::text from public.payroll_lines where "runId" = '2026-11' and "personId" = 'IQT-909'), '^1\|approved:1\|true$');
select zz.chk('D02 kassir uning maoshini Direktor tasdig''isiz bera olmaydi; boshqa xodimga — beriladi',
  zz.as('U_KAS', zz.sp('d_t9', 'IQT-909', '2026-11', 2500000, 2500000, '2026-12-01')) || ' / ' || zz.as('U_KAS', zz.sp('d_s1', 'IQX-901', '2026-11', 1500000, 2000000, '2026-12-01')),
  '^ERR 23514 .*Direktor tasdig''i kerak / d_s1$');

-- ===== (A5-03) kelgusi va tugamagan oy =====
select zz.chk('C01 kelgusi oy (2027-01) vedomosti yuborilmaydi', zz.as('U_FM', $q$select public.payroll_submit('2027-01', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'reason'$q$), '^future$');
select zz.chk('C02 joriy oy (2026-12) — tayyorlanadi; HR oy tugaguncha tasdiqlay olmaydi; Direktor tasdiqlaydi',
  (zz.as('U_FM', $q$select public.payroll_submit('2026-12', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'ok'$q$)) || '|'
  || zz.as('U_HR', $q$select public.payroll_decide('2026-12', true, null)->>'reason'$q$) || '|'
  || (select status from public.payroll_runs where id = '2026-12') || '|'
  || zz.as('U_DIR', $q$select public.payroll_decide('2026-12', true, null)->>'status'$q$), '^true\|not_ended\|submitted\|approved$');
set local session_replication_role = replica;
insert into public.payroll_runs (id, status, "preparedBy", "preparedAt", "submittedAt") values ('2027-02', 'submitted', 'U_FM', now(), now());
set local session_replication_role = origin;
select zz.chk('C03 avval yuborilgan kelgusi oy vedomostini Direktor ham tasdiqlay olmaydi; qaytarish mumkin',
  zz.as('U_DIR', $q$select public.payroll_decide('2027-02', true, null)->>'reason'$q$) || '|' || zz.as('U_HR', $q$select public.payroll_decide('2027-02', false, 'Oy hali kelmagan')->>'status'$q$),
  '^future\|returned$');

-- ===== (A5-08) vedomost ishtirokchilari ismi =====
select zz.chk('H01 HR: tayyorlagan / tasdiqlagan / qayta ochgan ismi va roli; ishtirok etmagan hisob (kassir) — yo''q',
  zz.as('U_HR', $q$select (j->'U_FM'->>'name') || '/' || (j->'U_FM'->>'role') || '|' || (j->'U_HR'->>'name') || '|' || (j->'U_DIR'->>'name') || '|' || (j->'U_T9'->>'name') || '|' || (j ? 'U_KAS')::text
                     from (select public.payroll_actor_names(array['U_FM','U_HR','U_DIR','U_T9','U_KAS']) as j) q$q$),
  '^Sinov Moliyachi/finance_mgr\|Sinov Kadrlar\|Sinov Direktor\|Sinov Yangi Kadr\|false$');
select zz.chk('H02 Moliya menejeri va kassir ekranida ham ism; email / telefon yo''q',
  zz.as('U_FM', $q$select public.payroll_actor_names(array['U_HR'])->'U_HR'->>'name'$q$) || '|' || zz.as('U_KAS', $q$select public.payroll_actor_names(array['U_FM'])->'U_FM'->>'name'$q$)
  || '|' || zz.as('U_FM', $q$select public.payroll_actor_names(array['U_HR'])::text$q$), '^Sinov Kadrlar\|Sinov Moliyachi\|[^@]*$');
select zz.chk('H03 buxgalter va o''qituvchiga — bo''sh; anon — ruxsat yo''q',
  zz.as('U_ACC', $q$select public.payroll_actor_names(array['U_FM','U_HR'])::text$q$) || '|' || zz.as('U_TCH', $q$select public.payroll_actor_names(array['U_FM'])::text$q$)
  || '|' || zz.as(null, $q$select public.payroll_actor_names(array['U_FM'])::text$q$), '^\{\}\|\{\}\|ERR 42501');

-- ===== (A5-04) login hisobi o'chirilganda kartadagi havola =====
select coalesce((select "userUid" from public.staff where id = 's2'), '-') as e01a \gset
select zz.as('U_DIR', $q$with d as (delete from public.users where id = 'U_X' returning 1) select count(*)::text from d$q$) as e01b \gset
select zz.chk('E01 Direktor kartaga bog''langan hisobni o''chiradi — kartadagi havola bo''shaydi (avval eski uid''da qolardi)',
  :'e01a' || '|' || :'e01b' || '|' || coalesce((select "userUid" from public.staff where id = 's2'), '-'), '^U_X\|1\|-$');
\set iqror_chain 1
\ir audit-11-maosh.sql
\unset iqror_chain
select zz.chk('E02 migratsiya qayta ishga tushirildi (idempotent): avvalgi o''chirishdan osilib qolgan havola (U_GONE) tozalandi, bog''langan karta (U_T9) — joyida',
  coalesce((select "userUid" from public.staff where id = 's3'), '-') || '|' || coalesce((select "userUid" from public.teachers where id = 't9'), '-'), '^-\|U_T9$');

-- ===== (A5-05) o'z hisobi va oxirgi faol Direktor =====
select zz.chk('F01 Direktor o''z hisobini o''chira olmaydi va o''z rolini / holatini o''zgartira olmaydi',
  zz.as('U_DIR', $q$with d as (delete from public.users where id = 'U_DIR' returning 1) select count(*)::text from d$q$) || ' / '
  || zz.as('U_DIR', $q$with u as (update public.users set role = 'teacher' where id = 'U_DIR' returning 1) select count(*)::text from u$q$) || ' / '
  || zz.as('U_DIR', $q$with u as (update public.users set status = 'pending' where id = 'U_DIR' returning 1) select count(*)::text from u$q$),
  '^ERR 42501 .*O''z hisobingizni.* / ERR 42501 .*O''z rolingiz.* / ERR 42501 .*O''z rolingiz');
select zz.chk('F02 o''z ismini saqlash — mumkin; ikkinchi Direktorni faol emas qilish — mumkin (biri faol qoladi)',
  zz.as('U_DIR', $q$with u as (update public.users set name = 'Sinov Direktor (yangi)' where id = 'U_DIR' returning 1) select count(*)::text from u$q$) || '|'
  || zz.as('U_DIR', $q$with u as (update public.users set status = 'pending' where id = 'U_DIR2' returning 1) select count(*)::text from u$q$), '^1\|1$');
-- app.is_admin() faqat rolni tekshiradi: faol bo'lmagan (kutilayotgan) Direktor hisobi ham users'ni o'zgartira oladi
select zz.chk('F03 oxirgi FAOL Direktorni faol bo''lmagan Direktor hisobi o''chira ham, pasaytira ham, holatini o''zgartira ham olmaydi',
  zz.as('U_DIR2', $q$with d as (delete from public.users where id = 'U_DIR' returning 1) select count(*)::text from d$q$) || ' / '
  || zz.as('U_DIR2', $q$with u as (update public.users set role = 'hr' where id = 'U_DIR' returning 1) select count(*)::text from u$q$) || ' / '
  || zz.as('U_DIR2', $q$with u as (update public.users set status = 'pending' where id = 'U_DIR' returning 1) select count(*)::text from u$q$),
  '^ERR 42501 .*Oxirgi faol Direktor.* / ERR 42501 .*Oxirgi faol Direktor.* / ERR 42501 .*Oxirgi faol Direktor');
savepoint f4;
select zz.chk('F04 server (service_role) — cheklanmaydi (tiklash uchun)',
  zz.sys($q$with u as (update public.users set status = 'pending' where id = 'U_DIR' returning 1) select count(*)::text from u$q$), '^1$');
rollback to savepoint f4;

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
