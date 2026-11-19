-- =====================================================================
-- test-audit-11-maosh.sql — audit-11 (H2: maosh, xodimlar, foydalanuvchilar) tuzatishlari sinovi:
--   (A5-01) maosh darvozasi: manfiy summa faqat kassa funksiyasidan (har qanday oyda), o'tish oyidan oldingi oy — faqat Direktor,
--           o'tish oyidan boshlab yozuvdagi maosh / ushlanma / avans — tasdiqlangan vedomostdan; oldingi qoldiq soxta «gross»ga
--           ishonmaydi; xodim avansi — musbat (kassadan tashqari); o'rinbosarlik — dars soni va stavka chegarasi;
--           (r4) avansni o'chirish / kamaytirish / boshqa oy yoki xodimga ko'chirish va maosh berish yozuvini o'chirish — faqat Direktor
--           (kassa funksiyasi bayrog'i va server — mustasno): o'chirib qayta berish va eski oy to'lovini o'chirib qoldiqni oshirish yo'q;
--   (A5-02) qayta ochilib kamroq summa bilan qayta tasdiqlangan oy: ortiqcha berilgani keyingi oyga manfiy qoldiq, 0 so'mlik
--           tuzatish yozuvi qabul qilinadi, yuborishda ortiqcha ko'rsatiladi;
--   (A5-03) kelgusi oy vedomosti yuborilmaydi / tasdiqlanmaydi, tugamagan oyni faqat Direktor tasdiqlaydi; (r4) oy tugamasdan yuborilgan
--           vedomostni oy tugagach ham HR tasdiqlamaydi ('stale') — oy tugagach qayta yuborilgani tasdiqlanadi, Direktor — istalgan payt;
--   (A5-04) login hisobi o'chirilganda kartadagi havola bo'shaydi, osilib qolgan havolalar migratsiyada tozalanadi (fayl qayta
--           ishga tushiriladi — idempotentlik ham tekshiriladi); (r4) tozalash eski qiymatni ham qaytaradi ('teachers/t1→U_LOST');
--   (A5-05) o'z hisobini o'chirish / rolini o'zgartirish va oxirgi faol Direktorni olib tashlash — rad (server — mumkin);
--   (A5-06) «Direktor tasdig'i kerak» belgisi tasdiqlash paytida qayta tekshiriladi;
--   (A5-08) vedomost ishtirokchilari ismi — maosh ko'radigan rollarga, faqat ishtirokchilar, buxgalterga yo'q;
--   (r4) deploy ogohlantirishi: o'tish oyidan oldingi oylar qoldig'i bor xodimlar va oy tugamasdan yuborilgan vedomostlar.
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub) — RLS va GRANT haqiqiy. Sana — sinov soati (app.fin_clock; faqat
--   fx_* / sinov / test nomli bazada): bugun 2026-12-10 (C-bo'limda 2026-12-20 dan 2027-02-01 gacha suriladi), o'tish oyi 2026-09.
--   Sinov qoidalari (r4): (a) yozuv / RPC o'z so'rovida (\gset bilan), natija KEYINGI so'rovda o'qiladi — bitta so'rov ichidagi
--   subselect va STABLE funksiya (app.salary_carry) o'sha so'rov boshidagi holatni ko'radi; (b) NULL natija — FAIL (hisobdan
--   tushib qolmaydi); (c) savepoint ichidagi qiymat \gset bilan olinadi, savepoint qaytarilgach tekshiriladi; (d) oxirida yozilgan
--   tekshiruvlar soni kutilgan son bilan solishtiriladi (yo'qolgan tekshiruv — FAIL).
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin, migration/ papkasidan:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && (cd migration && psql -d sinov -X -f test-audit-11-maosh.sql)
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- yozilishi kerak bo'lgan tekshiruvlar soni (ZZ dan tashqari): yangi tekshiruv qo'shilsa — oshiriladi
\set kutilgan 56
-- Bo'sh baza tekshiruvi — quyidagi ichki deploy seansidan (zz_deploy_out) OLDIN: aks holda u bo'sh bo'lmagan bazada ham yozib,
--   audit-11-maosh.sql'ni ishga tushirardi (qaytarilsa ham — himoya chetlab o'tilardi). Tranzaksiya ichidagi tekshiruv ham qoladi.
do $g0$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-11-maosh.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g0$;
-- Deploy konsoli (N07, pastda tekshiriladi): deploy.sh konsolga faqat «OGOHLANTIRISH|g'ayrioddiy» qatorlarini chiqaradi. Maosh
--   ogohlantirishlarini AYNAN shu filtr bilan ko'rish uchun alohida psql seansi (shu baza): o'z tranzaksiyasida o'tish oyi (2026-09),
--   o'qituvchi kartasi va uning eski oy qoldig'i (IQT-961), kartasi yo'q maosh ID'si qoldig'i (IQT-962) va oy tugamasdan yuborilgan
--   vedomost (2026-10) yaratadi, audit-11-maosh.sql'ni zanjirdagidek ishga tushiradi va ROLLBACK qiladi. Bu sinov tranzaksiyasidan
--   OLDIN — keyin DDL qulflari shu tranzaksiya qulflari bilan to'qnashardi. Fayl: migration/ ichidan ham, repo ildizidan ham topiladi.
\set zz_deploy_out `f=audit-11-maosh.sql; [ -f "$f" ] || f=migration/audit-11-maosh.sql; psql -X -q -v ON_ERROR_STOP=1 -v iqror_chain=1 -h :'HOST' -p :'PORT' -U :'USER' -d :'DBNAME' -c 'begin' -c 'set local session_replication_role = replica' -c 'insert into public.config (id, "payrollApprovalFrom") values ($$finance$$, $$2026-09$$) on conflict (id) do update set "payrollApprovalFrom" = excluded."payrollApprovalFrom"' -c 'insert into public.teachers (id, "teacherId", name) values ($$t_dep$$, $$IQT-961$$, $$Sinov Deploy$$)' -c 'insert into public.salary_payments (id, "teacherId", month, gross, advance, deduction, "subBonus", net, paid, date) values ($$sp_dep1$$, $$IQT-961$$, $$2026-07$$, 3000000, 0, 0, 0, 3000000, 1000000, $$2026-08-01$$), ($$sp_dep2$$, $$IQT-962$$, $$2026-07$$, 1000000, 0, 0, 0, 1000000, 0, $$2026-08-01$$)' -c 'insert into public.payroll_runs (id, status, "preparedBy", "preparedAt", "submittedAt") values ($$2026-10$$, $$submitted$$, $$U_X$$, $$2026-10-20 10:00+05$$, $$2026-10-20 10:00+05$$)' -c 'set local session_replication_role = origin' -f "$f" -c 'rollback' 2>&1 | grep -E "OGOHLANTIRISH|g'ayrioddiy" | sed -E 's/^.*NOTICE: +//'`
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
  ('s1','IQX-901','Sinov Xodim Bir',null), ('s2','IQX-902','Sinov Xodim Ikki','U_X'), ('s3','IQX-903','Sinov Xodim Uch','U_GONE'),
  ('s5','','Sinov Xodim Besh (ID bo''sh)',null);
-- ID'si bo'sh xodimning avansi (maosh kaliti — qator id): HR «Yangi noyob ID berish» bilan tuzatganda avans ham ko'chishi kerak (A07)
insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date) values ('a_rk','s5','Sinov Besh',100000,'2027-01','2027-01-05');
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
-- Baza egasi (migratsiya / deploy kabi, JWT'siz): xato — matn bo'lib qaytadi (sinov to'xtamaydi, FAIL bo'lib ko'rinadi).
create or replace function zz.q(p_q text) returns text language plpgsql as $$
declare r text;
begin
  begin execute p_q into r; exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
  return coalesce(r, '<null>');
end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
-- NULL natija — FAIL (got '<NULL>', ok false): hech bir tekshiruv hisobdan jim tushib qolmaydi.
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, coalesce(p_got, '<NULL>'), p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- maosh yozuvi: (id, maosh ID, oy, berilgan, mijoz yuborgan gross, sana)
create or replace function zz.sp(p_id text, p_tid text, p_month text, p_paid numeric, p_gross numeric, p_date text) returns text language sql as $$
  select format($f$with x as (insert into public.salary_payments (id, "teacherId", month, gross, advance, deduction, "subBonus", net, paid, date)
                    values (%L, %L, %L, %s, 0, 0, 0, %s, %s, %L) returning id) select id from x$f$, p_id, p_tid, p_month, p_gross, p_gross, p_paid, p_date) $$;
-- maosh yozuvini o'chirish (o'chirilgan qatorlar soni)
create or replace function zz.spdel(p_id text) returns text language sql as $$
  select format($f$with d as (delete from public.salary_payments where id = %L returning 1) select count(*)::text from d$f$, p_id) $$;
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
select zz.as('U_KAS', zz.sp('g_pay', 'IQX-901', '2026-09', 2000000, 9000000, '2026-10-01')) as g02 \gset
select zz.chk('G02 kassir soxta gross (9 000 000) bilan 2 000 000 beradi — yoziladi, lekin maosh / ushlanma / qoldiq vedomostdan',
  :'g02' || ' ' || zz.row('g_pay'), '^g_pay 2000000/0/0/0/2000000/0/0$');
select zz.chk('G03 oldingi qoldiq soxta gross''ga ishonmaydi (2026-10 uchun 0, avval 7 000 000 bo''lardi)', app.salary_carry('IQX-901', '2026-10')::text, '^0$');
select zz.as('U_KAS', zz.sp('g_zero', 'IQX-901', '2026-09', 0, 9000000, '2026-10-05')) as g04 \gset
select zz.chk('G04 keyinroq sanali soxta 0 so''mlik yozuv (gross 9 000 000) — qabul qilinadi, qoldiq o''zgarmaydi (keyingi so''rovda o''qiladi)',
  :'g04' || ' ' || app.salary_carry('IQX-901', '2026-10'), '^g_zero 0$');
select zz.chk('G05 kassir o''tish oyidan oldingi oyga (2026-08) soxta qator yoza olmaydi — faqat Direktor',
  zz.as('U_KAS', zz.sp('g_old', 'IQX-901', '2026-08', 0, 9000000, '2026-10-01')), '^ERR 42501 .*faqat Direktor yozadi');
select zz.chk('G05b HR va Moliya menejeri ham', zz.as('U_HR', zz.sp('g_old2', 'IQX-901', '2026-08', 0, 9000000, '2026-10-01')) || ' / '
  || zz.as('U_FM', zz.sp('g_old3', 'IQX-901', '2026-08', 0, 9000000, '2026-10-01')), '^ERR 42501 .*faqat Direktor.* / ERR 42501 .*faqat Direktor');
select zz.chk('G06 Direktor eski tartibdagi oy maoshini yozadi (o''zgarishsiz)', zz.as('U_DIR', zz.sp('g_dir', 'IQX-901', '2026-08', 1000000, 1000000, '2026-10-01')), '^g_dir$');
-- G07 — savepoint ichida (o'tish oyi vaqtincha olib tashlanadi): qiymatlar \gset bilan olinadi, tekshiruv savepoint qaytarilgach.
savepoint g7;
set local session_replication_role = replica;
update public.config set "payrollApprovalFrom" = null where id = 'finance';
set local session_replication_role = origin;
select zz.as('U_KAS', zz.sp('g7_neg', 'IQX-901', '2026-05', -1, 1000000, '2026-06-01')) || ' / '
  || zz.as('U_KAS', zz.sp('g7_pay', 'IQX-901', '2026-05', 600000, 1000000, '2026-06-01')) as g07a \gset
select app.salary_carry('IQX-901', '2026-06') as g07b \gset
rollback to savepoint g7;
select zz.chk('G07 o''tish oyi belgilanmagan: manfiy summa baribir rad; eski tartib (kassir yozadi, qoldiq — yozuvlardan) o''zgarmagan',
  :'g07a' || ' / ' || :'g07b', '^ERR 23514 .*manfiy bo''lmaydi.* / g7_pay / 400000$');

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
-- (r4) avansni o'chirish / kamaytirish / boshqa oy yoki xodimga ko'chirish — faqat Direktor (vedomost avansni bazadan ayiradi)
select zz.as('U_FM', $q$with x as (update public.staff_advances set amount = 1 where id = 'a_ok' returning id) select id from x$q$) || ' / '
  || zz.as('U_FM', $q$with x as (delete from public.staff_advances where id = 'a_ok' returning id) select id from x$q$) || ' / '
  || zz.as('U_FM', $q$with x as (update public.staff_advances set month = '2027-03', date = '2027-03-03' where id = 'a_ok' returning id) select id from x$q$) || ' / '
  || zz.as('U_FM', $q$with x as (update public.staff_advances set "teacherId" = 'IQT-909' where id = 'a_ok' returning id) select id from x$q$) as a04 \gset
select zz.chk('A04 Moliya menejeri avansni 1 so''mga tushira ham, o''chira ham, boshqa oy / xodimga ko''chira ham olmaydi; oy avansi o''zgarmagan (300 000 − 100 000)',
  :'a04' || ' | ' || trim_scale(app.payroll_adv('IQX-901', '2027-01')),
  '^ERR 42501 Xodim avansining summasini kamaytirish.*faqat Direktor.* / ERR 42501 Xodim avansini faqat Direktor o''chiradi.* / ERR 42501 Xodim avansining .*faqat Direktor.* / ERR 42501 Xodim avansining .*faqat Direktor.* \| 200000$');
select zz.as('U_FM', $q$with x as (update public.staff_advances set amount = 350000 where id = 'a_ok' returning id) select id from x$q$) || ' / '
  || zz.as('U_FM', $q$with x as (update public.staff_advances set note = 'Sinov izoh', date = '2027-01-10' where id = 'a_ok' returning id) select id from x$q$) as a05 \gset
select zz.chk('A05 summani oshirish, izoh va shu oy ichida sanani tuzatish — Moliya menejeriga avvalgidek mumkin',
  :'a05' || ' | ' || trim_scale(app.payroll_adv('IQX-901', '2027-01')), '^a_ok / a_ok \| 250000$');
select zz.as('U_DIR', $q$with x as (update public.staff_advances set amount = 200000 where id = 'a_ok' returning id) select id from x$q$) || ' / '
  || zz.as('U_DIR', $q$with x as (delete from public.staff_advances where id = 'a_ok' returning id) select id from x$q$) as a06a \gset
select set_config('iqror.kassa_rpc', '1', true);
select zz.as('U_FM', $q$with x as (delete from public.staff_advances where id = 'a_ret' returning id) select id from x$q$) as a06b \gset
select set_config('iqror.kassa_rpc', '', true);
select zz.chk('A06 Direktor avansni kamaytiradi va o''chiradi; kassa funksiyasi (orderni bekor qilish — bayroq) avansni olib tashlaydi',
  :'a06a' || ' / ' || :'a06b' || ' | ' || trim_scale(app.payroll_adv('IQX-901', '2027-01')), '^a_ok / a_ok / a_ret \| 0$');
-- (r4 tekshiruv) HR ID'si bo'sh xodimga yangi ID beradi (rekey_payroll_id) — avansi ham yangi kalitga ko'chadi: avans qo'riqchisi
--   «boshqa xodimga ko'chirish»ni faqat iqror.rekey bayrog'i bilan o'tkazadi (bayroqsiz to'g'ridan-to'g'ri ko'chirish — A04 da rad).
select zz.as('U_HR', $q$select (j->>'advances') || ':' || (j->>'newKey') from (select public.rekey_payroll_id('staff', 's5', '', 'IQX-905') as j) q$q$) as a07 \gset
select zz.chk('A07 HR ID''si bo''sh xodimga yangi ID beradi — avansi yangi kalitga ko''chadi, oy avansi saqlanadi',
  :'a07' || ' | ' || coalesce((select "teacherId" from public.staff_advances where id = 'a_rk'), '-') || ' | ' || trim_scale(app.payroll_adv('IQX-905', '2027-01')),
  '^1:IQX-905 \| IQX-905 \| 100000$');

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
  zz.as('U_FM', $q$select (j->>'payable') || '|' || (j->>'overpaid') || '|' || (j->>'overpaidSum')
                     from (select public.payroll_submit('2026-10', '[{"personType":"staff","personId":"IQX-901","gross":2000000,"deduction":500000}]'::jsonb, null) as j) q$q$),
  '^1500000\|1\|500000$');
select zz.as('U_HR', $q$select public.payroll_decide('2026-10', true, null)->>'status'$q$) as b02 \gset
select zz.chk('B02 HR qayta tasdiqlaydi — ortiqcha 500 000 keyingi oyga MANFIY qoldiq (avval 0 bo''lardi)',
  :'b02' || '|' || app.salary_carry('IQX-901', '2026-11'), '^approved\|-500000$');
select zz.as('U_KAS', zz.sp('b_fix', 'IQX-901', '2026-10', 0, 2000000, '2026-11-20')) as b03 \gset
select zz.chk('B03 0 so''mlik tuzatish yozuvi qabul qilinadi (avval «berish mumkin: 0» deb rad), qoldiq o''zgarmaydi; qatorda qoldiq −500 000 (keyingi so''rovda o''qiladi)',
  :'b03' || ' ' || zz.row('b_fix') || ' ' || app.salary_carry('IQX-901', '2026-11'),
  '^b_fix 2000000/500000/0/0/0/0/-500000 -500000$');
select zz.chk('B04 summa chegarasi saqlanadi: yana 1 so''m ham berilmaydi', zz.as('U_KAS', zz.sp('b_more', 'IQX-901', '2026-10', 1, 2000000, '2026-11-20')),
  '^ERR 23514 .*berish mumkin: 0');

-- ===== (A5-01, r4) maosh berish yozuvini o'chirish — faqat Direktor =====
--   P-bo'lim qoldiqni o'zgartirmaydi (D00 −500 000 ga tayanadi): eski oy (2026-07) ikki bo'lib to'langan — qoldiq 0.
select zz.as('U_DIR', zz.sp('p_i1', 'IQX-901', '2026-07', 1000000, 2000000, '2026-08-01')) || ' / '
  || zz.as('U_DIR', zz.sp('p_i2', 'IQX-901', '2026-07', 1000000, 2000000, '2026-08-05')) || ' / '
  || zz.as('U_KAS', zz.sp('p_z', 'IQX-901', '2026-09', 0, 2000000, '2026-10-06')) as p00 \gset
select zz.chk('P00 Direktor eski oy (2026-07) maoshini ikki bo''lib yozadi (qoldiq 0); kassir tasdiqlangan oyga 0 so''mlik yozuv yozadi',
  :'p00' || ' | ' || app.salary_carry('IQX-901', '2026-08'), '^p_i1 / p_i2 / p_z \| 0$');
select zz.as('U_FM', zz.spdel('g_pay')) || ' / ' || zz.as('U_HR', zz.spdel('g_pay')) || ' / ' || zz.as('U_KAS', zz.spdel('g_pay')) as p01 \gset
select zz.chk('P01 Moliya menejeri va HR tasdiqlangan oy to''lovini (2 000 000) o''chira olmaydi (avval o''chirardi); kassirda o''chirish huquqi yo''q (0 qator)',
  :'p01' || ' | ' || zz.row('g_pay'),
  '^ERR 42501 Maosh berish yozuvini faqat Direktor o''chiradi.* / ERR 42501 Maosh berish yozuvini faqat Direktor o''chiradi.* / 0 \| 2000000/0/0/0/2000000/0/0$');
select zz.as('U_FM', zz.sp('p_again', 'IQX-901', '2026-09', 2000000, 2000000, '2026-10-07')) as p02 \gset
select zz.chk('P02 «o''chirib qayta berish» yo''q: o''sha oyga yana 2 000 000 berilmaydi, daftarda berilgani 2 000 000',
  :'p02' || ' | ' || coalesce((select trim_scale(sum(paid))::text from public.salary_payments where "teacherId" = 'IQX-901' and month = '2026-09'), '-'),
  '^ERR 23514 .*berish mumkin: 0 .* \| 2000000$');
select zz.as('U_HR', zz.spdel('p_i2')) as p03 \gset
select zz.chk('P03 HR eski oy to''lovining bir qismini o''chirib keyingi oy «oldingi qoldig''i»ni oshira olmaydi (avval qoldiq 0 → 1 000 000)',
  :'p03' || ' | ' || app.salary_carry('IQX-901', '2026-08'), '^ERR 42501 Maosh berish yozuvini faqat Direktor o''chiradi.* \| 0$');
select zz.as('U_FM', zz.spdel('p_z')) as p04a \gset
select set_config('iqror.kassa_rpc', '1', true);
select zz.as('U_FM', zz.spdel('p_z')) as p04b \gset
select set_config('iqror.kassa_rpc', '', true);
select zz.as('U_DIR', zz.spdel('g_zero')) as p04c \gset
select zz.chk('P04 0 so''mlik yozuv ham faqat Direktor (yoki kassa funksiyasi — orderni bekor qilish bayrog''i bilan) o''chiradi; qoldiq o''zgarmagan',
  :'p04a' || ' / ' || :'p04b' || ' / ' || :'p04c' || ' | ' || app.salary_carry('IQX-901', '2026-10'),
  '^ERR 42501 Maosh berish yozuvini faqat Direktor o''chiradi.* / 1 / 1 \| 0$');

-- ===== (A5-06) yangi oy: vedomost yuborilgandan keyin xodimga HR roli berildi — tasdiqlashda Direktor tasdig'iga o'tadi =====
select zz.as('U_FM', $q$select public.payroll_submit('2026-11', '[{"personType":"staff","personId":"IQX-901","gross":2000000},{"personType":"teacher","personId":"IQT-909","gross":2500000}]'::jsonb, null)->>'count'$q$) as d00 \gset
select zz.chk('D00 2026-11 yuborildi: xodim (qoldiq −500 000 → 1 500 000) va o''qituvchi (karta U_T9 ga bog''langan, hozircha o''qituvchi — tasdiqsiz)',
  :'d00' || '|' || coalesce((select trim_scale("carryIn") || ':' || trim_scale(payable) from public.payroll_lines where "runId" = '2026-11' and "personId" = 'IQX-901'), '-')
  || '|' || coalesce((select "needsDirector"::text from public.payroll_lines where "runId" = '2026-11' and "personId" = 'IQT-909'), '-'), '^2\|-500000:1500000\|false$');
select zz.as('U_DIR', $q$with u as (update public.users set role = 'hr' where id = 'U_T9' returning 1) select count(*)::text from u$q$) as d01a \gset
select zz.as('U_T9', $q$select coalesce(j->>'status', '-') || ':' || coalesce(j->>'moved', '-') from (select public.payroll_decide('2026-11', true, null) as j) q$q$) as d01b \gset
select zz.chk('D01 Direktor U_T9 ni HR qiladi; yangi HR vedomostni tasdiqlaydi — o''z qatori Direktor tasdig''iga o''tkazildi (moved 1)',
  :'d01a' || '|' || :'d01b' || '|' || coalesce((select "needsDirector"::text from public.payroll_lines where "runId" = '2026-11' and "personId" = 'IQT-909'), '-'), '^1\|approved:1\|true$');
select zz.chk('D02 kassir uning maoshini Direktor tasdig''isiz bera olmaydi; boshqa xodimga — beriladi',
  zz.as('U_KAS', zz.sp('d_t9', 'IQT-909', '2026-11', 2500000, 2500000, '2026-12-01')) || ' / ' || zz.as('U_KAS', zz.sp('d_s1', 'IQX-901', '2026-11', 1500000, 2000000, '2026-12-01')),
  '^ERR 23514 .*Direktor tasdig''i kerak / d_s1$');

-- ===== (A5-03) kelgusi va tugamagan oy; oy tugamasdan yuborilgan vedomost =====
select zz.chk('C01 kelgusi oy (2027-01) vedomosti yuborilmaydi', zz.as('U_FM', $q$select public.payroll_submit('2027-01', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'reason'$q$), '^future$');
select zz.as('U_FM', $q$select public.payroll_submit('2026-12', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'ok'$q$) as c02a \gset
select zz.as('U_HR', $q$select public.payroll_decide('2026-12', true, null)->>'reason'$q$) as c02b \gset
select coalesce((select status from public.payroll_runs where id = '2026-12'), '-') as c02c \gset
select zz.as('U_DIR', $q$select public.payroll_decide('2026-12', true, null)->>'status'$q$) as c02d \gset
select zz.chk('C02 joriy oy (2026-12) — tayyorlanadi; HR oy tugaguncha tasdiqlay olmaydi; Direktor tasdiqlaydi',
  :'c02a' || '|' || :'c02b' || '|' || :'c02c' || '|' || :'c02d', '^true\|not_ended\|submitted\|approved$');
set local session_replication_role = replica;
insert into public.payroll_runs (id, status, "preparedBy", "preparedAt", "submittedAt") values ('2027-02', 'submitted', 'U_FM', now(), now());
set local session_replication_role = origin;
select zz.chk('C03 avval yuborilgan kelgusi oy vedomostini Direktor ham tasdiqlay olmaydi; qaytarish mumkin',
  zz.as('U_DIR', $q$select public.payroll_decide('2027-02', true, null)->>'reason'$q$) || '|' || zz.as('U_HR', $q$select public.payroll_decide('2027-02', false, 'Oy hali kelmagan')->>'status'$q$),
  '^future\|returned$');
-- (r4) Direktor 2026-12 ni qayta ochadi; Moliya menejeri 20-dekabrda (oy tugamasdan) qayta yuboradi. 31-dekabr 23:59 — oy tugamagan;
--   1-yanvar 00:01 (Toshkent) — oy tugagan, lekin vedomost 20-dekabr holatida: HR tasdiqlamaydi ('stale'; avval tasdiqlanardi).
select zz.as('U_DIR', $q$select public.payroll_reopen('2026-12', 'Sinov: yo''qlama keyin kiritiladi')->>'status'$q$) as c04a \gset
update app.fin_clock set t = '2026-12-20 10:00+05' where id = 1;
select zz.as('U_FM', $q$select public.payroll_submit('2026-12', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'ok'$q$) as c04b \gset
update app.fin_clock set t = '2026-12-31 23:59+05' where id = 1;
select zz.as('U_HR', $q$select public.payroll_decide('2026-12', true, null)->>'reason'$q$) as c04c \gset
update app.fin_clock set t = '2027-01-01 00:01+05' where id = 1;
select zz.as('U_HR', $q$select coalesce(j->>'reason', j->>'status', '-') || ':' || coalesce(j->>'submittedDay', '-') from (select public.payroll_decide('2026-12', true, null) as j) q$q$) as c04d \gset
select coalesce((select status from public.payroll_runs where id = '2026-12'), '-') as c04e \gset
select zz.chk('C04 oy tugamasdan (20-dekabr) yuborilgan vedomost: 31-dekabr 23:59 — oy tugamagan, 1-yanvar 00:01 — HR baribir tasdiqlamaydi (stale), holati «yuborilgan»',
  :'c04a' || '|' || :'c04b' || '|' || :'c04c' || '|' || :'c04d' || '|' || :'c04e', '^returned\|true\|not_ended\|stale:2026-12-20\|submitted$');
-- (r4) deploy ogohlantirishi: o'tish oyidan oldingi oylar qoldig'i (IQT-901: 3 000 000 dan 1 000 000 berilgan; IQX-902: 500 000 o'rniga
--   700 000; IQX-901: eski oylar to'liq to'langan — ro'yxatda yo'q) va oy tugamasdan yuborilgan vedomost (2026-12).
select zz.as('U_DIR', zz.sp('n_t1', 'IQT-901', '2026-07', 1000000, 3000000, '2026-08-01')) || ' / '
  || zz.as('U_DIR', zz.sp('n_x2', 'IQX-902', '2026-08', 700000, 500000, '2026-09-01')) as n01a \gset
select zz.q($q$select (j->>'from') || ' | ' || (j->'carry')::text || ' | ' || (j->'stale')::text from (select app.payroll_deploy_notice() as j) q$q$) as n01b \gset
select zz.chk('N01 deploy: o''tish oyidan (2026-09) oldingi oylar qoldig''i bor xodimlar (maosh ID) va oy tugamasdan yuborilgan vedomost',
  :'n01a' || ' | ' || :'n01b', '^n_t1 / n_x2 \| 2026-09 \| \["IQT-901", "IQX-902"\] \| \["2026-12"\]$');
-- deploy.sh ko'rsatadigan matn (OGOHLANTIRISH qatorlari) — natijadagi 'notice'
select zz.q($q$select (j->'notice')::text from (select app.payroll_deploy_notice() as j) q$q$) as n04 \gset
select zz.chk('N04 deploy matni: qoldiq vedomostga «oldingi qoldiq» bo''lib o''zi qo''shiladi, eski oyga — faqat Direktor; eskirgan vedomost',
  :'n04', '^\["OGOHLANTIRISH: 2 ta xodim / o''qituvchida maosh tasdig''i o''tish oyidan \(2026-09\) oldingi oylar .*hali birorta tasdiqlangan vedomostga kirmagan — navbatdagi oylik vedomostga «oldingi qoldiq» .*ortiqcha berilgani — ushlanadi.*faqat Direktor .*: IQT-901, IQX-902", "OGOHLANTIRISH: 1 ta oylik vedomost oy tugamasdan yuborilgan .*: 2026-12"\]$');
savepoint n2;
set local session_replication_role = replica;
update public.config set "payrollApprovalFrom" = null where id = 'finance';
set local session_replication_role = origin;
select zz.q($q$select coalesce(j->>'from', 'null') || ' | ' || (j->'carry')::text || ' | ' || (j->'stale')::text from (select app.payroll_deploy_notice() as j) q$q$) as n02a \gset
rollback to savepoint n2;
select zz.chk('N02 o''tish oyi belgilanmagan — qoldiq ro''yxati yo''q (vedomost ogohlantirishi qoladi); mijoz rollari funksiyani chaqira olmaydi',
  :'n02a' || ' | ' || zz.as('U_DIR', $q$select app.payroll_deploy_notice()::text$q$), '^null \| \[\] \| \["2026-12"\] \| ERR 42501 ');
-- HR qaytaradi; Moliya menejeri 31-dekabr 23:59 da qayta yuboradi (hali oy tugamagan) — 1-yanvarda baribir eskirgan; qaytarilib 1-yanvar
--   00:01 da qayta yuborilgani — HR tasdiqlaydi.
update app.fin_clock set t = '2026-12-31 23:59+05' where id = 1;
select zz.as('U_HR', $q$select public.payroll_decide('2026-12', false, 'Oy tugagach qayta yuboring')->>'status'$q$) || '|'
  || zz.as('U_FM', $q$select public.payroll_submit('2026-12', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'ok'$q$) as c05a \gset
update app.fin_clock set t = '2027-01-01 00:01+05' where id = 1;
select zz.as('U_HR', $q$select coalesce(j->>'reason', j->>'status', '-') from (select public.payroll_decide('2026-12', true, null) as j) q$q$) || '|'
  || zz.as('U_HR', $q$select public.payroll_decide('2026-12', false, 'Endi oy tugadi — qayta yuboring')->>'status'$q$) || '|'
  || zz.as('U_FM', $q$select public.payroll_submit('2026-12', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'ok'$q$) as c05b \gset
select zz.as('U_HR', $q$select coalesce(j->>'status', j->>'reason', '-') from (select public.payroll_decide('2026-12', true, null) as j) q$q$) as c05c \gset
select zz.chk('C05 oy oxirgi daqiqasida qayta yuborilgani ham eskirgan; oy tugagach (1-yanvar) qayta yuborilgan vedomostni HR tasdiqlaydi',
  :'c05a' || ' | ' || :'c05b' || ' | ' || :'c05c', '^returned\|true \| stale\|returned\|true \| approved$');
-- (r4) Direktor eskirgan vedomostni ham tasdiqlaydi (masalan maosh oy tugamasdan beriladigan bo'lsa): 2027-01 — 1-yanvarda yuborilgan,
--   1-fevralda HR — stale, Direktor — tasdiqlaydi.
select zz.as('U_FM', $q$select public.payroll_submit('2027-01', '[{"personType":"staff","personId":"IQX-901","gross":2000000}]'::jsonb, null)->>'ok'$q$) as c06a \gset
update app.fin_clock set t = '2027-02-01 00:01+05' where id = 1;
select zz.as('U_HR', $q$select coalesce(j->>'reason', j->>'status', '-') from (select public.payroll_decide('2027-01', true, null) as j) q$q$) || '|'
  || zz.as('U_DIR', $q$select coalesce(j->>'status', j->>'reason', '-') from (select public.payroll_decide('2027-01', true, null) as j) q$q$) as c06b \gset
select zz.chk('C06 oy tugamasdan yuborilgan vedomostni HR tasdiqlamaydi, Direktor — istalgan payt tasdiqlaydi',
  :'c06a' || '|' || :'c06b', '^true\|stale\|approved$');
-- (r4 tekshiruv) o'tish oyidan oldingi qoldiq tasdiqlangan vedomostga «oldingi qoldiq» bo'lib kirgach — deploy ogohlantirishidan chiqadi
--   (aks holda u har deployda qolar edi, Direktor eski oyga yana to'lasa — ortiqchasi keyingi maoshdan ushlanardi). IQT-901: eski qoldiq
--   2 000 000 — 2027-02 vedomostida carryIn; IQX-902 — hali vedomostda yo'q, ro'yxatda qoladi. Savepoint ichida: qiymatlar \gset bilan
--   olinadi, tekshiruv savepoint qaytarilgach.
savepoint n3;
select zz.as('U_FM', $q$select public.payroll_submit('2027-02', '[{"personType":"teacher","personId":"IQT-901","gross":3000000}]'::jsonb, null)->>'ok'$q$) as n03a \gset
select zz.q($q$select (j->'carry')::text from (select app.payroll_deploy_notice() as j) q$q$) as n03s \gset
select zz.as('U_DIR', $q$select public.payroll_decide('2027-02', true, null)->>'status'$q$) as n03b \gset
select coalesce((select trim_scale("carryIn") || ':' || trim_scale(payable) from public.payroll_lines where "runId" = '2027-02' and "personId" = 'IQT-901'), '-') as n03c \gset
select zz.q($q$select (j->'carry')::text from (select app.payroll_deploy_notice() as j) q$q$) as n03d \gset
select zz.as('U_DIR', $q$select public.payroll_reopen('2027-02', 'Sinov: qayta ochildi')->>'status'$q$) as n03e \gset
select zz.q($q$select (j->'carry')::text from (select app.payroll_deploy_notice() as j) q$q$) as n03f \gset
rollback to savepoint n3;
select zz.chk('N03 oldingi qoldiq faqat TASDIQLANGAN vedomostga kirgach (IQT-901: carryIn 2 000 000) ogohlantirishdan chiqadi: yuborilgan (hali tasdiqlanmagan) va qayta ochilgan vedomostda — ro''yxatda; IQX-902 — doim',
  :'n03a' || '|' || :'n03s' || '|' || :'n03b' || '|' || :'n03c' || '|' || :'n03d' || '|' || :'n03e' || '|' || :'n03f',
  '^true\|\["IQT-901", "IQX-902"\]\|approved\|2000000:5000000\|\["IQX-902"\]\|returned\|\["IQT-901", "IQX-902"\]$');
-- (4-raund) o'tish oyidan OLDINGI oyning tasdiqlangan vedomosti qoldiqni o'zlashtirmaydi (app.salary_carry eski oylarni eski tartib bilan
--   hisoblaydi) — xodim ro'yxatda qoladi
savepoint n5;
set local session_replication_role = replica;
insert into public.payroll_runs (id, status) values ('2026-08', 'approved');
insert into public.payroll_lines (id, "runId", "personType", "personId", gross, payable) values ('2026-08__staff__IQX-902', '2026-08', 'staff', 'IQX-902', 500000, 500000);
set local session_replication_role = origin;
select zz.q($q$select (j->'carry')::text from (select app.payroll_deploy_notice() as j) q$q$) as n05 \gset
rollback to savepoint n5;
select zz.chk('N05 o''tish oyidan oldingi oy (2026-08) tasdiqlangan vedomostida qatori bor — baribir ro''yxatda (IQX-902)', :'n05', '^\["IQT-901", "IQX-902"\]$');
-- (4-raund) kartasi yo'q (o'chirilgan) maosh ID'si: qoldig'i vedomostga qo'shilmaydi (payroll_submit kartasiz ID'ni rad etadi) — alohida
--   ogohlantirish, «o'zi qo'shiladi» deyilmaydi
savepoint n6;
set local session_replication_role = replica;
insert into public.salary_payments (id, "teacherId", month, gross, advance, deduction, "subBonus", net, paid, date)
  values ('n_orph', 'IQT-977', '2026-07', 1500000, 0, 0, 0, 1500000, 500000, '2026-08-01');
set local session_replication_role = origin;
select zz.q($q$select (j->'carry')::text || ' | ' || (j->'orphan')::text || ' | ' || (j->'notice'->>1) from (select app.payroll_deploy_notice() as j) q$q$) as n06 \gset
rollback to savepoint n6;
select zz.chk('N06 kartasi yo''q maosh ID''si (IQT-977) — alohida qator: vedomostga qo''shilmaydi, qo''lda hal qilinadi; asosiy ro''yxat o''zgarmagan',
  :'n06', '^\["IQT-901", "IQX-902"\] \| \["IQT-977"\] \| OGOHLANTIRISH: 1 ta maosh ID''sida o''tish oyidan \(2026-09\) .*kartasi yo''q .*hech qaysi vedomostga qo''shilmaydi.*: IQT-977$');
-- (4-raund) deploy.sh konsoli: alohida psql seansi (fayl boshida) AYNAN deploy filtri bilan ko'rgan qatorlar
select zz.chk('N07 deploy.sh konsoli (alohida seans, OGOHLANTIRISH filtri): maosh qoldig''i (IQT-961), kartasi yo''q ID (IQT-962), eskirgan vedomost (2026-10)',
  :'zz_deploy_out', '^OGOHLANTIRISH: 1 ta xodim / o''qituvchida maosh tasdig''i o''tish oyidan \(2026-09\) oldingi oylar .*: IQT-961\nOGOHLANTIRISH: 1 ta maosh ID''sida .*kartasi yo''q .*: IQT-962\nOGOHLANTIRISH: 1 ta oylik vedomost oy tugamasdan yuborilgan .*: 2026-10$');

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
-- (r4) tozalash eski qiymatni ham beradi (NOTICE va natija): karta hisobi adashib o'chirilgan bo'lsa — qayta bog'lash uchun
set local session_replication_role = replica;
update public.teachers set "userUid" = 'U_LOST' where id = 't1';
set local session_replication_role = origin;
select zz.q($q$select (j->>'count') || ' ' || (j->'cleared')::text || ' ' || (j->>'notice') from (select app.users_card_link_repair() as j) q$q$) as e03a \gset
select zz.q($q$select (j->>'count') || ' ' || (j->'cleared')::text || ' ' || (j->>'notice') from (select app.users_card_link_repair() as j) q$q$) as e03b \gset
select zz.chk('E03 osilib qolgan havola tozalanadi va eski qiymati qaytariladi (NOTICE matnida ham: teachers/t1→U_LOST); qayta chaqirilsa — 0; mijoz rollari chaqira olmaydi',
  :'e03a' || ' | ' || coalesce((select "userUid" from public.teachers where id = 't1'), '-') || ' | ' || :'e03b'
  || ' | ' || zz.as('U_DIR', $q$select app.users_card_link_repair()::text$q$),
  '^1 \["teachers/t1→U_LOST"\] OGOHLANTIRISH: 1 ta xodim / o''qituvchi kartasidagi login havolasi .*: teachers/t1→U_LOST \(endi .* \| - \| 0 \[\] Login havolasi: .*\(0\) \| ERR 42501 ');

-- (4-raund) ko'p osilib qolgan havola — hammasi NOTICE matnida («… yana» bilan qisqartirilmaydi: karta→eski hisob ID tiklash uchun kerak)
savepoint e4;
set local session_replication_role = replica;
insert into public.teachers (id, "teacherId", name, "userUid")
  select 'tz' || lpad(g::text, 2, '0'), 'IQT-8' || lpad(g::text, 2, '0'), 'Sinov Ortiqcha ' || g, 'U_LZ' || lpad(g::text, 2, '0') from generate_series(1, 22) g;
set local session_replication_role = origin;
select zz.q($q$select (j->>'count') || ' ' || jsonb_array_length(j->'cleared') || ' ' || ((j->>'notice') like '%teachers/tz01→U_LZ01%')::text || ' '
                     || ((j->>'notice') like '%teachers/tz22→U_LZ22%')::text || ' ' || ((j->>'notice') like '%yana%')::text from (select app.users_card_link_repair() as j) q$q$) as e04 \gset
rollback to savepoint e4;
select zz.chk('E04 22 ta osilib qolgan havola — hammasi (karta→eski hisob ID) NOTICE matnida, «… yana» qisqartirishsiz', :'e04', '^22 22 true true false$');

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
-- F04 — savepoint ichida (Direktor holati qaytariladi): qiymat \gset bilan olinadi, tekshiruv savepoint qaytarilgach.
savepoint f4;
select zz.sys($q$with u as (update public.users set status = 'pending' where id = 'U_DIR' returning 1) select count(*)::text from u$q$) as f04 \gset
rollback to savepoint f4;
select zz.chk('F04 server (service_role) — cheklanmaydi (tiklash uchun)', :'f04', '^1$');

-- har tekshiruv yozildimi (savepoint ichida yo'qolgan yoki bajarilmay qolgan tekshiruv — FAIL)
select count(*)::text as yozilgan from zz.res \gset
select zz.chk('ZZ yozilgan tekshiruvlar soni = kutilgan', :'yozilgan', '^' || :'kutilgan' || '$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL (jami ' || count(*) || ')' from zz.res;
rollback;
