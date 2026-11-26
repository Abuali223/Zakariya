-- =====================================================================
-- test-kassa-paysheet.sql — moliya ish rejasi 2-bosqichi, F2.14 va F2.15 (buxgalter savollari, Sh-8 B17 va B1) sinovi:
--   (A) kassa_pay_sheet — xodimning o'quv yili ish haqi to'lov qaydnomasi: huquqlar (kassa o'quvchilari; o'qituvchi va anon — yo'q),
--       tekshiruvlar (xodim kaliti, topilmagan xodim, o'quv yili), qatorlar — SHU xodimning o'tkazilgan naqd maosh, avans va qaytim
--       orderlari (bekor qilingan, sinov kassasi, boshqa operatsiya va boshqa xodim — yo'q), oy (surat yoki hujjat kuni), o'quv yili
--       chegaralari (sentyabr – avgust; avgust maoshi sentyabrda berilsa — avgust qatori), qaytimlar turi (OP-08 / OP-09), jamlar,
--       kassagacha naqd yozuvlar (legacy), joriy o'quv yili (standart), xodim ma'lumoti (kod, lavozim);
--   (B) kassa_month_pack.postings — E8 provodkalar (1C ga yuklash): shu kassaning o'tkazilgan KO-1 / KO-2 / dalolatnoma qatorlari asl
--       holatda (boshlang'ich qoldiq dalolatnomasi, bekor qilingan, boshqa oy va sinov kassasi — yo'q), tartib, qayta tasnif dalolatnomasi —
--       tuzatish yozuvi (Dt yangi — Kt eski; hisobvaraq o'zgarmagan bo'lsa — yo'q), ismsiz nusxa (FD-28) va Direktor nusxasi.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-paysheet.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov nomlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) or exists (select 1 from public.salary_payments) then
    raise exception 'test-kassa-paysheet.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  if p_uid is null then execute 'set local role anon'; else execute 'set local role authenticated'; end if;
  begin
    execute p_q into r;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    r := 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
create or replace function zz.js(p text) returns jsonb language plpgsql as $$
begin return p::jsonb; exception when others then return null; end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
create table if not exists zz.v (k text primary key, v text);
truncate zz.res; truncate zz.v;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
create or replace function zz.put(p_k text, p_v text) returns void language plpgsql as $$
begin insert into zz.v (k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; end $$;
create or replace function zz.get(p_k text) returns text language sql as $$ select v from zz.v where k = p_k $$;
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
-- qaydnoma (xodim, yil; null — joriy)
create or replace function zz.ps(p_uid text, p_party text, p_year int) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_pay_sheet(%L, %s)::text', p_party, coalesce(p_year::text, 'null'))) $$;
-- qatorlar qisqachasi: oy/tur/seriya-raqam/kun/summa
create or replace function zz.rows(p text) returns text language sql as $$
  select coalesce((select string_agg((r ->> 'month') || '/' || (r ->> 'kind') || '/' || (r ->> 'series') || '-' || (r ->> 'no') || '/' || (r ->> 'day') || '/' || (r ->> 'amount'), ',' order by o)
                     from jsonb_array_elements(zz.js(p) -> 'rows') with ordinality t(r, o)), '-') $$;
-- provodkalar qisqachasi: kun/seriya-raqam/Dt/Kt/summa/statiya/kod/nom/asos
create or replace function zz.pst(p_uid text, p_desk text, p_month text) returns text language sql as $$
  select coalesce((select string_agg((r ->> 'day') || '/' || (r ->> 'series') || '-' || (r ->> 'no') || '/' || (r ->> 'debit') || '/' || (r ->> 'credit') || '/' || (r ->> 'amount')
                                     || '/' || coalesce(r ->> 'articleId', '-') || '/' || coalesce(r ->> 'code', '-') || '/' || coalesce(r ->> 'partyName', '-') || '/' || coalesce(r ->> 'basis', '-'),
                                     ',' order by o)
                     from jsonb_array_elements(zz.js(zz.as(p_uid, format('select public.kassa_month_pack(%L, %L)::text', p_desk, p_month))) -> 'postings') with ordinality t(r, o)), '-') $$;

-- ---------- Urug' (triggerlarsiz) ----------
--   Bugun — 2027-09-10. O'qituvchi t1 (IQT-1): 2026/27 o'quv yilida avans (sentyabr; suratsiz — kun oyi), sentyabr maoshi (oktyabrda
--   berilgan), avans va maosh qaytimi, avgust maoshi (2027-09-05 da berilgan), bekor qilingan maosh, sinov kassasidagi maosh, hisobdorga
--   avans (qaydnomaga kirmaydi), 2025/26 yilidagi va 2027/28 yilidagi maosh; o'qituvchi t2 — o'z maoshi; xodim s1 — avans.
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'), ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]'),
  ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.teachers (id, "teacherId", name) values ('t1', 'IQT-1', 'Sinov Muallima'), ('t2', 'IQT-2', 'Sinov Muallim Ikki');
insert into public.staff (id, "staffId", name, position) values ('s1', 'IQX-1', 'Sinov Xodima', 'Hamshira');
insert into public.fin_counterparties (id, kind, name, stir, active, "createdAt") values ('cp1', 'supplier', 'Sinov Ta''minotchi', '000000101', true, '2026-09-01 09:00+05');
insert into public.cash_days (id, desk, day, status, opening, receipts, payouts, closing, counted, hash, "closedBy", "closedAt", "openedAt")
select 'cd_' || d.desk || '_' || d.day, d.desk, d.day::date, 'closed', 5000000, 0, 0, 5000000, 5000000, 'h', 'U_KAS', (d.day || ' 18:00+05')::timestamptz, (d.day || ' 08:00+05')::timestamptz
  from (values ('main', '2026-08-28'), ('main', '2026-09-15'), ('main', '2026-09-20'), ('main', '2026-10-05'), ('main', '2026-10-06'), ('main', '2026-10-07'),
               ('main', '2026-10-25'), ('main', '2026-11-05'), ('main', '2026-12-01'), ('main', '2027-09-05'), ('main', '2027-09-08'), ('sinov', '2026-10-05')) d(desk, day);
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "partyType", "partyId", "partyName", basis,
                              "clientRef", "postedAt", "postedBy", "postedByName", "sourceSnapshot", "createdAt") values
  ('pa',  'main', 'KO2', 'out_advance', 'posted', 2026, 1, '2026-09-15', 'cd_main_2026-09-15', 500000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Avans', 'r-pa-00001', '2026-09-15 10:00+05', 'U_KAS', 'Sinov Kassir', null, '2026-09-15 10:00+05'),
  ('pb',  'main', 'KO2', 'out_salary', 'posted', 2026, 2, '2026-10-05', 'cd_main_2026-10-05', 2000000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ish haqi: 2026-09', 'r-pb-00001', '2026-10-05 10:00+05', 'U_KAS', 'Sinov Kassir', '{"month": "2026-09", "teacherId": "IQT-1"}', '2026-10-05 10:00+05'),
  ('pc',  'main', 'KO2', 'out_salary', 'posted', 2027, 1, '2027-09-05', 'cd_main_2027-09-05', 2100000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ish haqi: 2027-08', 'r-pc-00001', '2027-09-05 10:00+05', 'U_KAS', 'Sinov Kassir', '{"month": "2027-08", "teacherId": "IQT-1"}', '2027-09-05 10:00+05'),
  ('pd',  'main', 'KO1', 'in_staff_return', 'posted', 2026, 2, '2026-10-07', 'cd_main_2026-10-07', 100000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ortiqcha berilgan', 'r-pd-00001', '2026-10-07 10:00+05', 'U_KAS', 'Sinov Kassir', '{"month": "2026-09"}', '2026-10-07 10:00+05'),
  ('pe',  'main', 'KO1', 'in_staff_return', 'posted', 2026, 1, '2026-09-20', 'cd_main_2026-09-20', 50000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Avans qaytdi', 'r-pe-00001', '2026-09-20 10:00+05', 'U_KAS', 'Sinov Kassir', '{"month": "2026-09"}', '2026-09-20 10:00+05'),
  ('pf',  'main', 'KO2', 'out_salary', 'void', 2026, 3, '2026-11-05', 'cd_main_2026-11-05', 999000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ish haqi: 2026-10', 'r-pf-00001', '2026-11-05 10:00+05', 'U_KAS', 'Sinov Kassir', '{"month": "2026-10"}', '2026-11-05 10:00+05'),
  ('pg',  'main', 'KO2', 'out_salary', 'posted', 2026, 6, '2026-08-28', 'cd_main_2026-08-28', 1800000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ish haqi: 2026-08', 'r-pg-00001', '2026-08-28 10:00+05', 'U_KAS', 'Sinov Kassir', '{"month": "2026-08"}', '2026-08-28 10:00+05'),
  ('ph',  'sinov', 'KO2', 'out_salary', 'posted', 2026, 1, '2026-10-05', 'cd_sinov_2026-10-05', 777000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Sinov', 'r-ph-00001', '2026-10-05 11:00+05', 'U_KAS', 'Sinov Kassir', '{"month": "2026-09"}', '2026-10-05 11:00+05'),
  ('pi',  'main', 'KO2', 'out_salary', 'posted', 2026, 4, '2026-10-05', 'cd_main_2026-10-05', 3000000, 'employee', 'teachers:t2', 'Sinov Muallim Ikki', 'Ish haqi: 2026-09', 'r-pi-00001', '2026-10-05 11:00+05', 'U_KAS', 'Sinov Kassir', '{"month": "2026-09"}', '2026-10-05 11:00+05'),
  ('pj',  'main', 'KO2', 'out_accountable', 'posted', 2026, 5, '2026-10-06', 'cd_main_2026-10-06', 250000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Xarid uchun', 'r-pj-00001', '2026-10-06 09:00+05', 'U_KAS', 'Sinov Kassir', null, '2026-10-06 09:00+05'),
  ('pk',  'main', 'KO2', 'out_salary', 'posted', 2027, 2, '2027-09-08', 'cd_main_2027-09-08', 2200000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ish haqi: 2027-09', 'r-pk-00001', '2027-09-08 10:00+05', 'U_KAS', 'Sinov Kassir', '{"month": "2027-09"}', '2027-09-08 10:00+05'),
  ('ps1', 'main', 'KO2', 'out_advance', 'posted', 2026, 8, '2026-12-01', 'cd_main_2026-12-01', 400000, 'employee', 'staff:s1', 'Sinov Xodima', 'Avans', 'r-ps1-0001', '2026-12-01 10:00+05', 'U_KAS', 'Sinov Kassir', null, '2026-12-01 10:00+05'),
  ('px',  'main', 'KO2', 'out_expense', 'posted', 2026, 7, '2026-10-06', 'cd_main_2026-10-06', 150000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Hisob-faktura № 0-5', 'r-px-00001', '2026-10-06 10:00+05', 'U_KAS', 'Sinov Kassir', null, '2026-10-06 10:00+05'),
  ('pv',  'main', 'KO2', 'out_expense', 'void', 2026, 9, '2026-10-06', 'cd_main_2026-10-06', 60000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Bekor', 'r-pv-00001', '2026-10-06 11:00+05', 'U_KAS', 'Sinov Kassir', null, '2026-10-06 11:00+05');
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "partyType", "partyId", "partyName", basis,
                              "clientRef", "postedAt", "postedBy", "postedByName", "sourceSnapshot", "createdAt") values
  ('po',  'main', 'ACT', 'nc_offset', 'posted', 2026, 1, '2026-10-10', null, 300000, 'employee', 'teachers:t1', 'Sinov Muallima', 'O''zaro hisob', 'r-po-00001', '2026-10-10 10:00+05', 'U_FM', 'Sinov Moliyachi',
   '{"month": "2026-09", "studentId": "st1", "studentName": "Sinov Bola"}', '2026-10-10 10:00+05'),
  ('pn',  'main', 'ACT', 'nc_opening', 'posted', 2026, 1, '2026-10-15', null, 5000000, null, null, '', 'Boshlang''ich qoldiq', 'r-pn-00001', '2026-10-15 10:00+05', 'U_DIR', 'Sinov Direktor', null, '2026-10-15 10:00+05');
update public.cash_docs set "voidedAt" = "postedAt" + interval '1 hour', "voidedBy" = 'U_KAS', "voidReason" = 'sinov' where status = 'void';
insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash) values
  ('la', 'pa', 1, '4210', '5010', 500000, 'OP-08', true), ('lb', 'pb', 1, '6710', '5010', 2000000, 'OP-09', true),
  ('lc', 'pc', 1, '6710', '5010', 2100000, 'OP-09', true), ('ld', 'pd', 1, '5010', '6710', 100000, 'OP-09', true),
  ('le', 'pe', 1, '5010', '4210', 50000, 'OP-08', true), ('lf', 'pf', 1, '6710', '5010', 999000, 'OP-09', true),
  ('lg', 'pg', 1, '6710', '5010', 1800000, 'OP-09', true), ('lh', 'ph', 1, '6710', '5010', 777000, 'OP-09', true),
  ('li', 'pi', 1, '6710', '5010', 3000000, 'OP-09', true), ('lj', 'pj', 1, '4230', '5010', 250000, 'OP-06', true),
  ('lk', 'pk', 1, '6710', '5010', 2200000, 'OP-09', true), ('ls1', 'ps1', 1, '4210', '5010', 400000, 'OP-08', true),
  ('lx1', 'px', 1, '9420', '5010', 100000, 'EX-32', true), ('lx2', 'px', 2, '9420', '5010', 50000, 'EX-32', true),
  ('lv', 'pv', 1, '9420', '5010', 60000, 'EX-32', true),
  ('lo', 'po', 1, '6710', '4010', 300000, 'OP-11', false), ('ln', 'pn', 1, '5010', '0000', 5000000, 'OP-23', true);
-- qayta tasnif (F2.13): QT-1 — px 1-qator EX-32 → EX-16 (9420 → 2010; tuzatish yozuvi bor), 2-qator o'zgarmagan; QT-2 — px 2-qator
--   EX-32 → EX-33 (ikkalasi 9420 — yozuv yo'q); kutilayotgan so'rov — hisobga olinmaydi
insert into public.cash_doc_fixes (id, "docId", desk, status, year, no, "actDay", reason, before, after, "clientRef", "reqHash", "requestedBy", "requestedAt", "decidedBy", "decidedAt") values
  ('fx1', 'px', 'main', 'approved', 2026, 1, '2026-10-25', 'Statiya xato tanlangan',
   '{"partyType": "counterparty", "partyId": "cp1", "partyName": "Sinov Ta''minotchi", "basis": "Hisob-faktura № 0-5", "lines": [{"lineNo": 1, "articleId": "EX-32", "debit": "9420", "amount": 100000}, {"lineNo": 2, "articleId": "EX-32", "debit": "9420", "amount": 50000}]}',
   '{"partyType": "counterparty", "partyId": "cp1", "partyName": "Sinov Ta''minotchi", "basis": "Hisob-faktura № 0-5", "lines": [{"lineNo": 1, "articleId": "EX-16", "debit": "2010", "amount": 100000}, {"lineNo": 2, "articleId": "EX-32", "debit": "9420", "amount": 50000}]}',
   'ref-fx1-001', 'h1', 'U_ACC', '2026-10-20 10:00+05', 'U_DIR', '2026-10-25 10:00+05'),
  ('fx2', 'px', 'main', 'approved', 2026, 2, '2026-10-25', 'Statiya aniqlashtirildi',
   '{"partyType": "counterparty", "partyId": "cp1", "partyName": "Sinov Ta''minotchi", "basis": "Hisob-faktura № 0-5", "lines": [{"lineNo": 1, "articleId": "EX-16", "debit": "2010", "amount": 100000}, {"lineNo": 2, "articleId": "EX-32", "debit": "9420", "amount": 50000}]}',
   '{"partyType": "counterparty", "partyId": "cp1", "partyName": "Sinov Ta''minotchi", "basis": "Hisob-faktura № 0-5", "lines": [{"lineNo": 1, "articleId": "EX-16", "debit": "2010", "amount": 100000}, {"lineNo": 2, "articleId": "EX-33", "debit": "9420", "amount": 50000}]}',
   'ref-fx2-001', 'h2', 'U_ACC', '2026-10-25 09:00+05', 'U_DIR', '2026-10-25 11:00+05'),
  ('fx3', 'pb', 'main', 'pending', null, null, null, 'Kutilayotgan so''rov',
   '{"lines": [{"lineNo": 1, "articleId": "OP-09", "debit": "6710", "amount": 2000000}]}', '{"lines": [{"lineNo": 1, "articleId": "OP-09", "debit": "4210", "amount": 2000000}]}',
   'ref-fx3-001', 'h3', 'U_ACC', '2026-10-26 09:00+05', null, null);
-- kassagacha (kassa hujjatisiz) naqd yozuvlar: maosh (naqd, usulsiz) va avans (+ qaytim); karta, kassa hujjatli va boshqa yil — yo'q
insert into public.salary_payments (id, "teacherId", "teacherName", month, paid, net, method, "cashDocId") values
  ('sl1', 'IQT-1', 'Sinov Muallima', '2026-09', 700000, 700000, null, null),
  ('sl2', 'IQT-1', 'Sinov Muallima', '2026-10', 800000, 800000, 'card', null),
  ('sl3', 'IQT-1', 'Sinov Muallima', '2026-09', 2000000, 2000000, 'cash', 'pb'),
  ('sl4', 'IQT-1', 'Sinov Muallima', '2025-12', 600000, 600000, null, null),
  ('sl5', 'IQT-2', 'Sinov Muallim Ikki', '2026-09', 900000, 900000, null, null);
insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date, method, "cashDocId") values
  ('sa1', 'IQT-1', 'Sinov Muallima', 300000, '2026-10', '2026-10-03', '', null),
  ('sa2', 'IQT-1', 'Sinov Muallima', -100000, '2026-10', '2026-10-04', 'cash', null),
  ('sa3', 'IQT-1', 'Sinov Muallima', 500000, '2026-09', '2026-09-15', 'cash', 'pa'),
  ('sa4', 'IQT-1', 'Sinov Muallima', 200000, '', '2026-08-20', null, null);   -- oy bo'sh — sana oyi (2026-08: oldingi o'quv yili)
set local session_replication_role = origin;
select zz.clock('2027-09-10 10:00+05');

-- ---------- (A) to'lov qaydnomasi ----------
select zz.chk('A1 huquqlar: kassir, Direktor, Moliya menejeri, buxgalter — ha; o''qituvchi va anon — yo''q',
  (select string_agg(coalesce(zz.js(zz.ps(u, 'teachers:t1', 2026)) ->> 'ok', 'X'), ',' order by o) from unnest(array['U_KAS', 'U_DIR', 'U_FM', 'U_ACC']) with ordinality t(u, o))
  || ' | ' || zz.ps('U_TCH', 'teachers:t1', 2026) || ' | ' || zz.as(null, $q$select public.kassa_pay_sheet('teachers:t1', 2026)::text$q$),
  '^true,true,true,true \| ERR 42501 .*to''lov qaydnomasi.* \| ERR 42501');
select zz.chk('A2 xodim kaliti noto''g''ri / topilmagan xodim / yil noto''g''ri',
  zz.ps('U_KAS', 'cp1', 2026) || ' | ' || zz.ps('U_KAS', 'teachers:yoq', 2026) || ' | ' || zz.ps('U_KAS', 'teachers:t1', 1999),
  '^ERR 22023 \[kassa:party\] .* \| ERR 22023 \[kassa:party\] .* \| ERR 22023 \[kassa:bad_input\]');
select zz.put('S1', zz.ps('U_KAS', 'teachers:t1', 2026));
select zz.chk('A3 2026/27 qatorlari: avans (suratsiz — kun oyi), avans qaytimi (OP-08), sentyabr maoshi (oktyabrda), maosh qaytimi (OP-09), avgust maoshi (sentyabrda) — oy, kun, tur tartibida',
  zz.rows(zz.get('S1')),
  '^2026-09/advance/KO2-1/2026-09-15/500000,2026-09/advanceReturn/KO1-1/2026-09-20/50000,2026-09/salary/KO2-2/2026-10-05/2000000,2026-09/salaryReturn/KO1-2/2026-10-07/100000,2027-08/salary/KO2-1/2027-09-05/2100000$');
select zz.chk('A4 yo''q: bekor qilingan, sinov kassasi, hisobdorga avans, o''zaro hisob dalolatnomasi, boshqa yil, boshqa xodim',
  ((select string_agg(x, ',') from unnest(array['pf', 'ph', 'pj', 'po', 'pg', 'pk', 'pi']) x where position('"' || x || '"' in zz.get('S1')) > 0) is null
   and position('3000000' in zz.get('S1')) = 0 and position('Sinov Muallim Ikki' in zz.get('S1')) = 0)::text, '^true$');
select zz.chk('A5 jamlar: maosh, avans, qaytimlar, berildi, qaytdi, sof',
  (select (t ->> 'salary') || '/' || (t ->> 'advance') || '/' || (t ->> 'salaryReturn') || '/' || (t ->> 'advanceReturn') || '/' || (t ->> 'paid') || '/' || (t ->> 'returned') || '/' || (t ->> 'net')
     from (select zz.js(zz.get('S1')) -> 'totals' as t) q), '^4100000/500000/100000/50000/4600000/150000/4450000$');
select zz.chk('A6 kassagacha naqd yozuvlar: maosh (usulsiz) 700 000, avans 300 000 va qaytim −100 000 (karta, kassa hujjatli, boshqa yil, boshqa xodim — yo''q)',
  (select (j -> 'legacy' ->> 'n') || '/' || (j -> 'legacy' ->> 'sum') from (select zz.js(zz.get('S1')) as j) q), '^3/900000$');
select zz.chk('A7 xodim ma''lumoti va davr: kalit, tabel kodi, ism, o''qituvchi; 2026-09 … 2027-08',
  (select (j #>> '{party,id}') || '/' || (j #>> '{party,code}') || '/' || (j #>> '{party,name}') || '/' || (j #>> '{party,kind}') || '/' || coalesce(j #>> '{party,position}', '-')
          || '/' || (j ->> 'year') || '/' || (j ->> 'from') || '/' || (j ->> 'to') from (select zz.js(zz.get('S1')) as j) q),
  '^teachers:t1/IQT-1/Sinov Muallima/teacher/-/2026/2026-09/2027-08$');
select zz.chk('A8 xodim (staff): lavozim, avans; kassagacha yozuv yo''q',
  (select (j #>> '{party,kind}') || '/' || (j #>> '{party,position}') || '/' || (j #>> '{party,code}') || '/' || zz.rows(j::text) || '/' || (j -> 'legacy' ->> 'n')
     from (select zz.js(zz.ps('U_ACC', 'staff:s1', 2026)) as j) q), '^staff/Hamshira/IQX-1/2026-12/advance/KO2-8/2026-12-01/400000/0$');
select zz.chk('A9 2025/26 yili: faqat 2026-08 maoshi; kassagacha yozuvlar — 2025-12 maoshi va 2026-08 avansi (yil chegarasi; oy bo''sh — sana oyi)',
  (select zz.rows(j::text) || '|' || (j -> 'legacy' ->> 'n') || '/' || (j -> 'legacy' ->> 'sum') || '|' || (j #>> '{totals,net}') from (select zz.js(zz.ps('U_DIR', 'teachers:t1', 2025)) as j) q),
  '^2026-08/salary/KO2-6/2026-08-28/1800000\|2/800000\|1800000$');
select zz.chk('A10 yil berilmasa — joriy o''quv yili (bugun 2027-09-10 → 2027/28): 2027-09 maoshi',
  (select (j ->> 'year') || '|' || zz.rows(j::text) from (select zz.js(zz.ps('U_FM', 'teachers:t1', null)) as j) q), '^2027\|2027-09/salary/KO2-2/2027-09-08/2200000$');
select zz.clock('2027-02-10 10:00+05');
select zz.chk('A10b fevralda yil berilmasa — joriy o''quv yili 2026/27 (kalendar yili emas)',
  (select (j ->> 'year') || '|' || (j ->> 'from') || '|' || (j #>> '{totals,net}') from (select zz.js(zz.ps('U_KAS', 'teachers:t1', null)) as j) q), '^2026\|2026-09\|4450000$');
select zz.clock('2027-09-10 10:00+05');
select zz.chk('A11 boshqa xodim (t2): faqat o''z maoshi va o''z kassagacha yozuvi; t1 summalari yo''q',
  (select zz.rows(j::text) || '|' || (j -> 'legacy' ->> 'sum') || '|' || (position('2000000' in j::text) = 0 and position('Sinov Muallima"' in j::text) = 0)::text
     from (select zz.js(zz.ps('U_KAS', 'teachers:t2', 2026)) as j) q), '^2026-09/salary/KO2-4/2026-10-05/3000000\|900000\|true$');
select zz.chk('A13 huquq: anon — chaqira olmaydi (EXECUTE yo''q), authenticated — chaqiradi (tekshiruv funksiya ichida)',
  has_function_privilege('anon', 'public.kassa_pay_sheet(text, int)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.kassa_pay_sheet(text, int)', 'execute')::text,
  '^false/true$');
select zz.chk('A12 to''lovsiz yil: bo''sh qatorlar, jamlar 0',
  (select zz.rows(j::text) || '|' || (j #>> '{totals,net}') || '|' || (j -> 'legacy' ->> 'n') from (select zz.js(zz.ps('U_KAS', 'teachers:t1', 2024)) as j) q), '^-\|0\|0$');

-- ---------- (B) E8 provodkalar (oylik to'plam) ----------
select zz.put('PF', zz.pst('U_FM', 'main', '2026-10'));
select zz.chk('B1 2026-10 (ismsiz): asl qatorlar kun / hujjat / qator tartibida; o''zaro hisob dalolatnomasi (naqdsiz) bor; boshlang''ich qoldiq, bekor qilingan, sinov kassasi — yo''q; QT-1 — tuzatish yozuvi (Dt 2010 — Kt 9420), QT-2 (hisobvaraq o''zgarmagan) va kutilayotgan so''rov — yozuvsiz; jismoniy shaxs — kod, ismsiz va asossiz; yetkazib beruvchi nomi va asosi qoladi',
  zz.get('PF'),
  '^2026-10-05/KO2-2/6710/5010/2000000/OP-09/IQT-1/-/-,2026-10-05/KO2-4/6710/5010/3000000/OP-09/IQT-2/-/-,2026-10-06/KO2-5/4230/5010/250000/OP-06/IQT-1/-/-,2026-10-06/KO2-7/9420/5010/100000/EX-32/cp1/Sinov Ta''minotchi/Hisob-faktura № 0-5,2026-10-06/KO2-7/9420/5010/50000/EX-32/cp1/Sinov Ta''minotchi/Hisob-faktura № 0-5,2026-10-07/KO1-2/5010/6710/100000/OP-09/IQT-1/-/-,2026-10-10/OFS-1/6710/4010/300000/OP-11/IQT-1/-/-,2026-10-25/FIX-1/2010/9420/100000/EX-16/cp1/Sinov Ta''minotchi/-$');
select zz.chk('B2 Direktor nusxasi: o''sha qatorlar ism va asos bilan',
  zz.pst('U_DIR', 'main', '2026-10'),
  '^2026-10-05/KO2-2/6710/5010/2000000/OP-09/IQT-1/Sinov Muallima/Ish haqi: 2026-09,2026-10-05/KO2-4/6710/5010/3000000/OP-09/IQT-2/Sinov Muallim Ikki/Ish haqi: 2026-09,2026-10-06/KO2-5/4230/5010/250000/OP-06/IQT-1/Sinov Muallima/Xarid uchun,');
select zz.chk('B3 tuzatish yozuvi: asl hujjat (seriya, raqam, kun), eski statiya, naqdsiz',
  (select (r ->> 'srcSeries') || '-' || (r ->> 'srcNo') || '/' || (r ->> 'srcDay') || '/' || (r ->> 'fromArticle') || '/' || (r ->> 'cash') || '/' || (r ->> 'fixId')
     from jsonb_array_elements(zz.js(zz.as('U_FM', $q$select public.kassa_month_pack('main', '2026-10')::text$q$)) -> 'postings') r where r ->> 'op' = 'fix'),
  '^KO2-7/2026-10-06/EX-32/false/fx1$');
select zz.chk('B4 jamlar: Kt 5010 = KO-2 lar (bekor qilinganisiz), Dt 5010 = KO-1 lar — matritsa (statiyalar) bilan bir xil',
  (select (sum((r ->> 'amount')::numeric) filter (where r ->> 'credit' = '5010'))::text || '/' || (sum((r ->> 'amount')::numeric) filter (where r ->> 'debit' = '5010'))::text
          || '/' || ((sum((r ->> 'amount')::numeric) filter (where r ->> 'credit' = '5010')) = (p #>> '{matrix,out}')::numeric)::text
          || '/' || ((sum((r ->> 'amount')::numeric) filter (where r ->> 'debit' = '5010')) = (p #>> '{matrix,in}')::numeric)::text
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_month_pack('main', '2026-10')::text$q$)) as p) q, jsonb_array_elements(p -> 'postings') r
    group by p), '^5400000/100000/true/true$');
select zz.chk('B5 sinov kassasi to''plami: faqat o''z hujjati',
  zz.pst('U_DIR', 'sinov', '2026-10'), '^2026-10-05/KO2-1/6710/5010/777000/OP-09/IQT-1/Sinov Muallima/Sinov$');
select zz.chk('B7 keyingi oy (2026-11): o''tkazilgan hujjat yo''q (faqat bekor qilingan) — provodka yo''q; oktyabr QT si — o''z oyida qoladi',
  zz.pst('U_FM', 'main', '2026-11'), '^-$');
select zz.chk('B6 boshqa oy (2026-09): o''sha oy hujjatlari; QT oyi emas — tuzatish yozuvi yo''q',
  zz.pst('U_FM', 'main', '2026-09'), '^2026-09-15/KO2-1/4210/5010/500000/OP-08/IQT-1/-/-,2026-09-20/KO1-1/5010/4210/50000/OP-08/IQT-1/-/-$');

-- ---------- Natija ----------
select (case when ok then 'PASS' else 'FAIL' end) || ' ' || name || case when ok then '' else E'\n     got: ' || coalesce(got, '<null>') || E'\n     pat: ' || pat end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
