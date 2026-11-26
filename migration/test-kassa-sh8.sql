-- =====================================================================
-- test-kassa-sh8.sql — buxgalter savollari (shakllar.md, Sh-8) bo'yicha egasi qarorlari (2026-11-26) sinovi:
--   (A) «⚙ Sozlamalar»: bankka topshirish (inkassatsiya) jadvali — fin_org_set depositDays / depositKeep tekshiruvlari va saqlash;
--   (B) «Kassa» holati (kassa_state.deposit): topshirish kuni, topshiriladigan summa (qoldiq − maydalik), bugun topshirilganmi, kassa
--       limiti tavsiyasi (oxirgi 92 kundagi naqd tushum / ishlagan kunlar × topshirish oralig'i; bankdan olingan naqd, bekor qilingan,
--       bugungi va boshqa kassa hujjatlari — yo'q);
--   (C) nazorat ro'yxati (kassa_checks): jadval va oxirgi 30 kunda o'tkazib yuborilgan topshirish kunlari;
--   (D) oylik kassa to'plami (kassa_month_pack): E5 o'zaro hisob (B20, JShDS imtiyozi), E6 xodim farzandi chegirmasi (B20, 2-qism),
--       E7 vedomost va to'lovlar (B19) — Direktorga ismli, 2-ro'yxatga ismsiz (FD-28), sinov kassasi to'plamida E6 / E7 yo'q.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-sh8.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov nomlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) or exists (select 1 from public.payroll_runs) then
    raise exception 'test-kassa-sh8.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
-- p_uid: null — anon; boshqa — authenticated (RLS bilan)
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
-- sozlama (Direktor nomidan yoki boshqa foydalanuvchi)
create or replace function zz.org(p_uid text, p text) returns text language sql as $$
  select zz.as(p_uid, format('select public.fin_org_set(%L::jsonb)::text', p)) $$;
-- sozlamani o'zgartirish (Direktor) — xato bo'lsa sinov to'xtaydi
create or replace function zz.set(p text) returns void language plpgsql as $$
declare r text := zz.org('U_DIR', p);
begin if r like 'ERR%' then raise exception 'zz.set(%): %', p, r; end if; end $$;
-- kassa holatidagi topshirish bloki: kunlar:maydalik:bugunmi:summa:bugun topshirilganmi
create or replace function zz.dep(p_desk text default 'main') returns text language sql as $$
  select (d ->> 'days') || ':' || (d ->> 'keep') || ':' || (d ->> 'today') || ':' || (d ->> 'amount') || ':' || (d ->> 'doneToday')
    from (select zz.js(zz.as('U_KAS', format('select (public.kassa_state(%L) -> ''deposit'')::text', p_desk))) d) q $$;
-- limit tavsiyasi: tushum:kunlar:o'rtacha:oraliq:tavsiya
create or replace function zz.hint(p_desk text default 'main') returns text language sql as $$
  select (h ->> 'receipts') || ':' || (h ->> 'days') || ':' || (h ->> 'avgDaily') || ':' || (h ->> 'interval') || ':' || (h ->> 'suggest')
    from (select zz.js(zz.as('U_KAS', format('select (public.kassa_state(%L) #> ''{deposit,limitHint}'')::text', p_desk))) h) q $$;
-- nazorat ro'yxati: jadval|o'tkazib yuborilgan kunlar
create or replace function zz.miss() returns text language sql as $$
  select zz.as('U_ACC', $q$select (c -> 'deposit')::text || '|' || (c -> 'depositMissed30')::text from public.kassa_checks('main') c$q$) $$;
-- oylik to'plam
create or replace function zz.pack(p_uid text, p_desk text, p_month text) returns jsonb language sql as $$
  select zz.js(zz.as(p_uid, format('select public.kassa_month_pack(%L, %L)::text', p_desk, p_month))) $$;
create or replace function zz.ofs(p jsonb) returns text language sql as $$
  select coalesce((select string_agg((x ->> 'day') || '/' || (x ->> 'no') || '/' || (x ->> 'month') || '/' || coalesce(x ->> 'code', '-') || '/'
                                     || coalesce(x ->> 'partyName', '-') || '/' || coalesce(x ->> 'studentId', '-') || '/' || coalesce(x ->> 'studentName', '-')
                                     || '/' || (x ->> 'amount'), ',' order by o)
                     from jsonb_array_elements(p -> 'offsets') with ordinality t(x, o)), '-') $$;
create or replace function zz.sd(p jsonb) returns text language sql as $$
  select coalesce((select string_agg(coalesce(x ->> 'employee', '-') || '/' || coalesce(x ->> 'studentId', '-') || '/' || coalesce(x ->> 'employeeName', '-') || '/'
                                     || coalesce(x ->> 'studentName', '-') || '/' || (x ->> 'base') || '/' || (x ->> 'discount') || '/' || (x ->> 'amount') || '/' || (x ->> 'status'),
                                     ',' order by o)
                     from jsonb_array_elements(p -> 'staffDiscounts') with ordinality t(x, o)), '-') $$;
create or replace function zz.pr(p jsonb) returns text language sql as $$
  select coalesce(p #>> '{payroll,status}', 'null') || ':' || ((p #>> '{payroll,approvedAt}') is not null)::text || ':'
      || coalesce((select string_agg((x ->> 'code') || '/' || (x ->> 'type') || '/' || coalesce(x ->> 'name', '-') || '/' || (x ->> 'gross') || '/' || (x ->> 'deduction')
                                     || '/' || (x ->> 'subBonus') || '/' || (x ->> 'advance') || '/' || (x ->> 'carryIn') || '/' || (x ->> 'payable') || '/' || (x ->> 'paidCash')
                                     || '/' || (x ->> 'paidCard') || '/' || (x ->> 'paidOffset') || '/' || (x ->> 'paidOther'), ',' order by o)
                     from jsonb_array_elements(p #> '{payroll,lines}') with ordinality t(x, o)), '-') $$;

-- ---------- Urug' (triggerlarsiz) ----------
--   Bugun — 2027-01-29, juma (ISO hafta kuni 5). Asosiy kassa: yopilgan kunlar 2026-10-01 (92 kunlik oynadan tashqari), 2026-12-25 (juma,
--   30 kunlik oynadan tashqari), 2027-01-07 (payshanba), 2027-01-08 (juma: qoldiq 900 000, bankka topshirish orderi — bekor qilingan),
--   2027-01-15 (juma: topshirilgan), 2027-01-22 (juma: qoldiq 0), 2027-01-28 (payshanba); bugun — ochiq kun (600 000 + 50 000).
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'), ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]'),
  ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.teachers (id, "teacherId", name) values ('t1', 'IQT-1', 'Sinov Muallima');
insert into public.staff (id, "staffId", name) values ('s1', 'IQX-1', 'Sinov Xodima');
insert into public.students (id, "studentId", name) values
  ('st1', 'st1', 'Sinov Bola Bir'), ('st2', 'st2', 'Sinov Bola Ikki'), ('st3', 'st3', 'Sinov Bola Uch'), ('st4', 'st4', 'Sinov Bola To''rt');
insert into public.student_private (id, "specialCategory", "teacherId") values ('st1', 'teacher_child', 'IQT-1'), ('st2', 'teacher_child', 'IQX-1');
insert into public.invoices (id, "studentId", "studentName", month, amount, "baseAmount", discount, "discountInfo", status) values
  ('st1__2027-01', 'st1', 'Sinov Bola Bir', '2027-01', 500000, 1000000, 500000, 'Xodim farzandi 50%', 'paid'),
  ('st2__2027-01', 'st2', 'Sinov Bola Ikki', '2027-01', 400000, 800000, 400000, 'Xodim farzandi 50% + 2 kasal kun', 'partial'),
  ('st4__2027-01', 'st4', 'Sinov Bola To''rt', '2027-01', 450000, 900000, 450000, 'O‘qituvchi farzandi 50%', 'pending'),   -- eski yorliq; bog'lanishsiz
  ('st3__2027-01', 'st3', 'Sinov Bola Uch', '2027-01', 900000, 1000000, 100000, 'Aka-uka 10%', 'pending'),                  -- boshqa chegirma
  ('st1__2026-12', 'st1', 'Sinov Bola Bir', '2026-12', 500000, 1000000, 500000, 'Xodim farzandi 50%', 'paid'),               -- boshqa oy
  ('st2__2027-01c', 'st2', 'Sinov Bola Ikki', '2027-01', 400000, 800000, 400000, 'Xodim farzandi 50%', 'canceled'),
  ('st2__2027-01r', 'st2', 'Sinov Bola Ikki', '2027-01', 400000, 800000, 400000, 'Xodim farzandi 50%', 'reversed');
insert into public.payroll_runs (id, status, "approvedBy", "approvedAt") values ('2027-01', 'approved', 'U_DIR', '2027-01-28 12:00+05');
insert into public.payroll_lines (id, "runId", "personType", "personId", "refId", name, gross, deduction, "subBonus", advance, "carryIn", payable) values
  ('2027-01__teacher__IQT-1', '2027-01', 'teacher', 'IQT-1', 't1', 'Sinov Muallima', 5000000, 100000, 50000, 1000000, 0, 3950000),
  ('2027-01__staff__IQX-1', '2027-01', 'staff', 'IQX-1', 's1', 'Sinov Xodima', 3000000, 0, 0, 500000, -100000, 2400000);
insert into public.salary_payments (id, "teacherId", "teacherName", month, paid, net, method) values
  ('sp1', 'IQT-1', 'Sinov Muallima', '2027-01', 2000000, 2000000, 'cash'),
  ('sp2', 'IQT-1', 'Sinov Muallima', '2027-01', 1000000, 1000000, 'card'),
  ('sp3', 'IQT-1', 'Sinov Muallima', '2027-01', 300000, 300000, 'offset'),
  ('sp4', 'IQT-1', 'Sinov Muallima', '2027-01', null, 999, null),            -- «paid» bo'sh — berilgani 0 (vedomost darvozasi kabi)
  ('sp5', 'IQT-1', 'Sinov Muallima', '2026-12', 777, 777, 'cash'),           -- boshqa oy
  ('sp6', 'IQX-1', 'Sinov Xodima', '2027-01', 2400000, 2400000, null),       -- usuli bo'sh — kassagacha yozilgan naqd
  ('sp7', 'IQX-1', 'Sinov Xodima', '2027-01', 1000, 1000, 'transfer');       -- boshqa usul
insert into public.cash_days (id, desk, day, status, opening, receipts, payouts, closing, counted, hash, "closedBy", "closedAt", "openedAt") values
  ('cd_main_2026-10-01', 'main', '2026-10-01', 'closed', 0, 999000, 0, 999000, 999000, 'h0', 'U_KAS', '2026-10-01 18:00+05', '2026-10-01 08:00+05'),
  ('cd_main_2026-12-25', 'main', '2026-12-25', 'closed', 0, 1200000, 500000, 700000, 700000, 'h1', 'U_KAS', '2026-12-25 18:00+05', '2026-12-25 08:00+05'),
  ('cd_main_2027-01-07', 'main', '2027-01-07', 'closed', 700000, 300000, 100000, 900000, 900000, 'h2', 'U_KAS', '2027-01-07 18:00+05', '2027-01-07 08:00+05'),
  ('cd_main_2027-01-08', 'main', '2027-01-08', 'closed', 900000, 500000, 500000, 900000, 900000, 'h3', 'U_KAS', '2027-01-08 18:00+05', '2027-01-08 08:00+05'),
  ('cd_main_2027-01-15', 'main', '2027-01-15', 'closed', 900000, 0, 800000, 100000, 100000, 'h4', 'U_KAS', '2027-01-15 18:00+05', '2027-01-15 08:00+05'),
  ('cd_main_2027-01-22', 'main', '2027-01-22', 'closed', 100000, 0, 100000, 0, 0, 'h5', 'U_KAS', '2027-01-22 18:00+05', '2027-01-22 08:00+05'),
  ('cd_main_2027-01-28', 'main', '2027-01-28', 'closed', 0, 600000, 0, 600000, 600000, 'h6', 'U_KAS', '2027-01-28 18:00+05', '2027-01-28 08:00+05'),
  ('cd_sinov_2027-01-08', 'sinov', '2027-01-08', 'closed', 0, 100000, 0, 100000, 100000, 'hs', 'U_KAS', '2027-01-08 18:00+05', '2027-01-08 08:00+05');
insert into public.cash_days (id, desk, day, status, opening, "openedAt") values ('cd_main_2027-01-29', 'main', '2027-01-29', 'open', 600000, '2027-01-29 08:00+05');
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "partyType", "partyId", "partyName", basis,
                              "clientRef", "postedAt", "postedBy", "postedByName", "sourceSnapshot", "createdAt") values
  ('k6', 'main', 'KO1', 'in_tuition', 'posted', 2026, 1, '2026-10-01', 'cd_main_2026-10-01', 999000, 'student', 'st3', 'Sinov Bola Uch', 'O''quv haqi', 'r-k6-00001', '2026-10-01 10:00+05', 'U_KAS', 'Sinov Kassir', null, '2026-10-01 10:00+05'),
  ('k1', 'main', 'KO1', 'in_tuition', 'posted', 2026, 2, '2026-12-25', 'cd_main_2026-12-25', 1200000, 'student', 'st1', 'Sinov Bola Bir', 'O''quv haqi', 'r-k1-00001', '2026-12-25 10:00+05', 'U_KAS', 'Sinov Kassir', null, '2026-12-25 10:00+05'),
  ('k2', 'main', 'KO1', 'in_other', 'posted', 2027, 1, '2027-01-07', 'cd_main_2027-01-07', 300000, 'other', null, 'Sinov Mehmon', 'Boshqa kirim', 'r-k2-00001', '2027-01-07 10:00+05', 'U_KAS', 'Sinov Kassir', null, '2027-01-07 10:00+05'),
  ('k3', 'main', 'KO1', 'in_bank', 'posted', 2027, 2, '2027-01-08', 'cd_main_2027-01-08', 500000, 'bank', null, 'Bank', 'Chek', 'r-k3-00001', '2027-01-08 10:00+05', 'U_KAS', 'Sinov Kassir', null, '2027-01-08 10:00+05'),
  ('k4', 'main', 'KO1', 'in_tuition', 'void', 2027, 3, '2027-01-15', 'cd_main_2027-01-15', 200000, 'student', 'st2', 'Sinov Bola Ikki', 'O''quv haqi', 'r-k4-00001', '2027-01-15 10:00+05', 'U_KAS', 'Sinov Kassir', null, '2027-01-15 10:00+05'),
  ('k5', 'main', 'KO1', 'in_tuition', 'posted', 2027, 4, '2027-01-29', 'cd_main_2027-01-29', 50000, 'student', 'st2', 'Sinov Bola Ikki', 'O''quv haqi', 'r-k5-00001', '2027-01-29 09:00+05', 'U_KAS', 'Sinov Kassir', null, '2027-01-29 09:00+05'),
  ('b1', 'main', 'KO2', 'out_bank', 'posted', 2027, 1, '2027-01-15', 'cd_main_2027-01-15', 800000, 'bank', null, 'Bank', 'Topshirish', 'r-b1-00001', '2027-01-15 16:00+05', 'U_KAS', 'Sinov Kassir', null, '2027-01-15 16:00+05'),
  ('b2', 'main', 'KO2', 'out_bank', 'void', 2027, 2, '2027-01-08', 'cd_main_2027-01-08', 900000, 'bank', null, 'Bank', 'Topshirish', 'r-b2-00001', '2027-01-08 16:00+05', 'U_KAS', 'Sinov Kassir', null, '2027-01-08 16:00+05'),
  ('s1', 'sinov', 'KO1', 'in_tuition', 'posted', 2027, 1, '2027-01-08', 'cd_sinov_2027-01-08', 100000, 'student', 'st1', 'Sinov Bola Bir', 'O''quv haqi', 'r-s1-00001', '2027-01-08 10:00+05', 'U_KAS', 'Sinov Kassir', null, '2027-01-08 10:00+05'),
  ('o1', 'main', 'ACT', 'nc_offset', 'posted', 2027, 1, '2027-01-10', null, 300000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ariza', 'r-o1-00001', '2027-01-10 11:00+05', 'U_FM', 'Sinov Moliyachi',
   '{"studentId": "st1", "studentName": "Sinov Bola Bir", "month": "2026-12"}', '2027-01-10 11:00+05'),
  ('o2', 'main', 'ACT', 'nc_offset', 'posted', 2027, 2, '2027-01-20', null, 200000, 'employee', 'staff:s1', 'Sinov Xodima', 'Ariza', 'r-o2-00001', '2027-01-20 11:00+05', 'U_FM', 'Sinov Moliyachi',
   '{"studentId": "st2", "studentName": "Sinov Bola Ikki", "month": "2027-01"}', '2027-01-20 11:00+05'),
  ('o3', 'main', 'ACT', 'nc_offset', 'void', 2027, 3, '2027-01-21', null, 100000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ariza', 'r-o3-00001', '2027-01-21 11:00+05', 'U_FM', 'Sinov Moliyachi',
   '{"studentId": "st1", "studentName": "Sinov Bola Bir", "month": "2027-01"}', '2027-01-21 11:00+05'),
  ('o4', 'main', 'ACT', 'nc_offset', 'posted', 2026, 1, '2026-12-28', null, 50000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ariza', 'r-o4-00001', '2026-12-28 11:00+05', 'U_FM', 'Sinov Moliyachi',
   '{"studentId": "st1", "studentName": "Sinov Bola Bir", "month": "2026-11"}', '2026-12-28 11:00+05'),
  ('o5', 'sinov', 'ACT', 'nc_offset', 'posted', 2027, 1, '2027-01-12', null, 70000, 'employee', 'teachers:t1', 'Sinov Muallima', 'Ariza', 'r-o5-00001', '2027-01-12 11:00+05', 'U_FM', 'Sinov Moliyachi',
   '{"studentId": "st1", "studentName": "Sinov Bola Bir", "month": "2026-12"}', '2027-01-12 11:00+05');
update public.cash_docs set "voidedAt" = "postedAt" + interval '1 hour', "voidedBy" = 'U_KAS', "voidReason" = 'sinov' where status = 'void';
insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash) values
  ('lk6', 'k6', 1, '5010', '4010', 999000, 'IN-01', true), ('lk1', 'k1', 1, '5010', '4010', 1200000, 'IN-01', true),
  ('lk2', 'k2', 1, '5010', '9390', 300000, 'IN-06', true), ('lk3', 'k3', 1, '5010', '5110', 500000, 'OP-01', true),
  ('lk4', 'k4', 1, '5010', '4010', 200000, 'IN-01', true), ('lk5', 'k5', 1, '5010', '4010', 50000, 'IN-01', true),
  ('lb1', 'b1', 1, '5710', '5010', 800000, 'OP-02', true), ('lb2', 'b2', 1, '5710', '5010', 900000, 'OP-02', true),
  ('ls1', 's1', 1, '5010', '4010', 100000, 'IN-01', true);
set local session_replication_role = origin;
select zz.clock('2027-01-29 10:00+05');

-- ---------- (B) kassa holati — jadval kaliti yo'q (standart: juma, maydaliksiz) ----------
select zz.chk('B1 standart jadval: juma, maydalik 0, bugun — topshirish kuni, summa = qoldiq (650 000), hali topshirilmagan', zz.dep(), '^\[5\]:0:true:650000:false$');
select zz.chk('B2 limit tavsiyasi: 92 kunda naqd tushum 1 500 000 (bankdan naqd, bekor qilingan, bugungi, oynadan tashqari va sinov kassasi — yo''q) / 6 kun = 250 000 × 5 = 1 250 000',
  zz.hint(), '^1500000:6:250000:5:1250000$');
select zz.chk('B2b sinov kassasi: o''z tushumi va kunlari bilan (100 000 / 1 kun × 5)', zz.hint('sinov'), '^100000:1:100000:5:500000$');

-- ---------- (C) nazorat ro'yxati — standart jadval ----------
select zz.chk('C1 o''tkazib yuborilgan juma: 08.01 (qoldiq 900 000, bankka topshirish orderi bekor qilingan); 15.01 — topshirilgan, 22.01 — qoldiq 0, 25.12 — 30 kundan oldin, payshanbalar — jadvalda emas, sinov kassasi — alohida',
  zz.miss(), '^\{"days": \[5\], "keep": 0\}\|\["2027-01-08"\]$');

-- ---------- (A) sozlama: tekshiruvlar va saqlash ----------
select zz.chk('A1 faqat Direktor', zz.org('U_FM', '{"depositDays":[5]}'), '^ERR 42501');
select zz.chk('A1b buxgalter ham emas', zz.org('U_ACC', '{"depositKeep":0}'), '^ERR 42501');
select zz.chk('A2 massiv emas', zz.org('U_DIR', '{"depositDays":5}'), '^ERR 22023 .*depositDays — hafta kunlari');
select zz.chk('A2b null', zz.org('U_DIR', '{"depositDays":null}'), '^ERR 22023 .*depositDays');
select zz.chk('A2c obyekt', zz.org('U_DIR', '{"depositDays":{"5":true}}'), '^ERR 22023 .*depositDays');
select zz.chk('A3 matn element', zz.org('U_DIR', '{"depositDays":["5"]}'), '^ERR 22023 .*depositDays');
select zz.chk('A4 0 — hafta kuni emas', zz.org('U_DIR', '{"depositDays":[0]}'), '^ERR 22023 .*depositDays');
select zz.chk('A4b 8 — hafta kuni emas', zz.org('U_DIR', '{"depositDays":[1,8]}'), '^ERR 22023 .*depositDays');
select zz.chk('A4c kasr', zz.org('U_DIR', '{"depositDays":[5.5]}'), '^ERR 22023 .*depositDays');
select zz.chk('A5 takror', zz.org('U_DIR', '{"depositDays":[5,5]}'), '^ERR 22023 .*depositDays');
select zz.chk('A5b 7 dan ko''p', zz.org('U_DIR', '{"depositDays":[1,2,3,4,5,6,7,1]}'), '^ERR 22023 .*depositDays');
select zz.chk('A6 maydalik manfiy', zz.org('U_DIR', '{"depositKeep":-1}'), '^ERR 22023 .*depositKeep noto''g''ri');
select zz.chk('A6b maydalik son emas', zz.org('U_DIR', '{"depositKeep":"abc"}'), '^ERR 22023 .*depositKeep son emas');
select zz.chk('A6c maydalik juda katta', zz.org('U_DIR', '{"depositKeep":1000000000000}'), '^ERR 22023 .*depositKeep noto''g''ri');
select zz.chk('A7 xatolardan keyin sozlama o''zgarmagan', (select coalesce(extra ->> 'depositDays', '-') || ':' || coalesce(extra ->> 'depositKeep', '-') from public.fin_org where id = 'main'), '^-:-$');
select zz.put('A8', zz.org('U_DIR', '{"orgCashMax":150000}'));
select zz.chk('A8 kunlar tartiblanib saqlanadi; boshqa sozlama (orgCashMax) saqlanib qoladi; javobda yangi qiymat',
  (select (j -> 'extra' ->> 'depositDays') || ':' || (j -> 'extra' ->> 'orgCashMax') || ':' || coalesce(j -> 'extra' ->> 'depositKeep', '-')
     from (select zz.js(zz.org('U_DIR', '{"depositDays":[5,2]}')) j) q), '^\[2, 5\]:150000:-$');
select zz.chk('A9 bo''sh ro''yxat — jadval yo''q', (select (zz.js(zz.org('U_DIR', '{"depositDays":[]}')) -> 'extra' ->> 'depositDays')), '^\[\]$');
select zz.chk('A10 maydalik saqlanadi, kunlar o''zgarmaydi', (select (j -> 'extra' ->> 'depositKeep') || ':' || (j -> 'extra' ->> 'depositDays') from (select zz.js(zz.org('U_DIR', '{"depositKeep":100000}')) j) q), '^100000:\[\]$');
select zz.chk('A11 bir chaqiruvda ikkalasi', (select (j -> 'extra' ->> 'depositKeep') || ':' || (j -> 'extra' ->> 'depositDays') || ':' || (j -> 'extra' ->> 'orgCashMax')
     from (select zz.js(zz.org('U_DIR', '{"depositDays":[2,5],"depositKeep":100000}')) j) q), '^100000:\[2, 5\]:150000$');

-- ---------- (B) kassa holati — sozlamadan keyin ----------
select zz.chk('B3 seshanba va juma, maydalik 100 000: bugun topshirish kuni, summa 550 000', zz.dep(), '^\[2, 5\]:100000:true:550000:false$');
select zz.chk('B3b oraliq: 5 ish kuni / 2 = 3 kun → tavsiya 750 000', zz.hint(), '^1500000:6:250000:3:750000$');
select zz.set('{"depositKeep":700000}');
select zz.chk('B4 maydalik qoldiqdan ko''p — topshiriladigan 0', zz.dep(), '^\[2, 5\]:700000:true:0:false$');
select zz.set('{"depositKeep":100000}');
-- bugun bekor qilingan «Bankka topshirish» orderi — topshirilgan hisoblanmaydi
set local session_replication_role = replica;
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "partyType", "partyName", basis, "clientRef", "postedAt", "postedBy", "postedByName",
                              "voidedAt", "voidedBy", "voidReason", "createdAt")
values ('b0', 'main', 'KO2', 'out_bank', 'void', 2027, 3, '2027-01-29', 'cd_main_2027-01-29', 550000, 'bank', 'Bank', 'Topshirish', 'r-b0-00001', '2027-01-29 09:10+05', 'U_KAS', 'Sinov Kassir',
        '2027-01-29 09:20+05', 'U_KAS', 'sinov', '2027-01-29 09:10+05');
insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash) values ('lb0', 'b0', 1, '5710', '5010', 550000, 'OP-02', true);
set local session_replication_role = origin;
select zz.chk('B4b bugun bekor qilingan topshirish orderi — topshirilmagan (eslatma qoladi), summa o''zgarmaydi', zz.dep(), '^\[2, 5\]:100000:true:550000:false$');
set local session_replication_role = replica;
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "partyType", "partyName", basis, "clientRef", "postedAt", "postedBy", "postedByName", "createdAt")
values ('b3', 'main', 'KO2', 'out_bank', 'posted', 2027, 4, '2027-01-29', 'cd_main_2027-01-29', 550000, 'bank', 'Bank', 'Topshirish', 'r-b3-00001', '2027-01-29 09:30+05', 'U_KAS', 'Sinov Kassir', '2027-01-29 09:30+05');
insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash) values ('lb3', 'b3', 1, '5710', '5010', 550000, 'OP-02', true);
set local session_replication_role = origin;
select zz.chk('B5 bugun topshirildi: eslatma yo''q (doneToday), qoldiq 100 000 — topshiriladigan 0', zz.dep(), '^\[2, 5\]:100000:true:0:true$');
select zz.set('{"depositDays":[1,2,3,4]}');
select zz.chk('B6 bugun (juma) jadvalda emas', zz.dep(), '^\[1, 2, 3, 4\]:100000:false:0:true$');
select zz.chk('B6b 4 kun → oraliq 2', zz.hint(), '^1500000:6:250000:2:500000$');
select zz.set('{"depositDays":[]}');
select zz.chk('B7 jadval yo''q: bugun emas, oraliq 1 kun', zz.dep() || ' ' || zz.hint(), '^\[\]:100000:false:0:true 1500000:6:250000:1:250000$');

-- ---------- (C) nazorat ro'yxati — sozlamadan keyin ----------
select zz.set('{"depositDays":[5],"depositKeep":900000}');
select zz.chk('C2 maydalik 900 000: 08.01 qoldig''i (900 000) undan ko''p emas — o''tkazib yuborilgan yo''q', zz.miss(), '^\{"days": \[5\], "keep": 900000\}\|\[\]$');
select zz.set('{"depositDays":[4],"depositKeep":0}');
select zz.chk('C3 payshanba: 07.01 va 28.01 (bugungi topshirish hisobga olinmaydi)', zz.miss(), '^\{"days": \[4\], "keep": 0\}\|\["2027-01-07", "2027-01-28"\]$');
select zz.set('{"depositDays":[]}');
select zz.chk('C4 jadval yo''q — nazorat ham yo''q', zz.miss(), '^\{"days": \[\], "keep": 0\}\|\[\]$');
select zz.set('{"depositDays":[5],"depositKeep":0}');
select zz.chk('C5 sinov kassasi: jadval va o''tkazib yuborilgan kunlar yo''q (bankka topshirilmaydi; 08.01 sinov kunida qoldiq bor)',
  zz.as('U_ACC', $q$select coalesce((c -> 'deposit')::text, 'null') || '|' || (c -> 'depositMissed30')::text from public.kassa_checks('sinov') c$q$), '^null\|\[\]$');

-- ---------- (D) oylik kassa to'plami: E5–E7 ----------
select zz.put('PD', zz.pack('U_DIR', 'main', '2027-01')::text);
select zz.put('PF', zz.pack('U_FM', 'main', '2027-01')::text);
select zz.chk('D1 E5 o''zaro hisob (Direktor): o''tkazilgan, shu oy, asosiy kassa — tabel kodi, ism, o''quvchi va ish haqi oyi bilan (bekor qilingan, boshqa oy, sinov kassasi — yo''q)',
  zz.ofs(zz.get('PD')::jsonb), '^2027-01-10/1/2026-12/IQT-1/Sinov Muallima/st1/Sinov Bola Bir/300000,2027-01-20/2/2027-01/IQX-1/Sinov Xodima/st2/Sinov Bola Ikki/200000$');
select zz.chk('D2 E5 ismsiz (Moliya menejeri): kodlar bor, ismlar yo''q', zz.ofs(zz.get('PF')::jsonb), '^2027-01-10/1/2026-12/IQT-1/-/st1/-/300000,2027-01-20/2/2027-01/IQX-1/-/st2/-/200000$');
select zz.chk('D3 E6 xodim farzandi (Direktor): shu oy, bekor qilinmagan, ikkala yorliq (yangi va eski); bog''lanishsizda kod yo''q; boshqa chegirma va oy — yo''q',
  zz.sd(zz.get('PD')::jsonb),
  '^IQT-1/st1/Sinov Muallima/Sinov Bola Bir/1000000/500000/500000/paid,IQX-1/st2/Sinov Xodima/Sinov Bola Ikki/800000/400000/400000/partial,-/st4/-/Sinov Bola To''rt/900000/450000/450000/pending$');
select zz.chk('D4 E6 ismsiz', zz.sd(zz.get('PF')::jsonb), '^IQT-1/st1/-/-/1000000/500000/500000/paid,IQX-1/st2/-/-/800000/400000/400000/partial,-/st4/-/-/900000/450000/450000/pending$');
select zz.chk('D5 E7 vedomost (Direktor): holati, har xodim bo''yicha hisob va to''langan usullar bo''yicha («paid» bo''sh — 0, usuli bo''sh — naqd, boshqa oy — yo''q)',
  zz.pr(zz.get('PD')::jsonb),
  '^approved:true:IQX-1/staff/Sinov Xodima/3000000/0/0/500000/-100000/2400000/2400000/0/0/1000,IQT-1/teacher/Sinov Muallima/5000000/100000/50000/1000000/0/3950000/2000000/1000000/300000/0$');
select zz.chk('D6 E7 ismsiz', zz.pr(zz.get('PF')::jsonb),
  '^approved:true:IQX-1/staff/-/3000000/0/0/500000/-100000/2400000/2400000/0/0/1000,IQT-1/teacher/-/5000000/100000/50000/1000000/0/3950000/2000000/1000000/300000/0$');
select zz.chk('D7 ismsiz to''plamda xodim va o''quvchi ismlari yo''q; masked = true',
  (select (position('Sinov Muallima' in t) = 0 and position('Sinov Xodima' in t) = 0 and position('Sinov Bola' in t) = 0)::text || ':' || (t::jsonb ->> 'masked')
     from (select zz.get('PF') as t) q), '^true:true$');
select zz.put('PS', zz.pack('U_DIR', 'sinov', '2027-01')::text);
select zz.chk('D8 sinov kassasi to''plami: faqat o''z o''zaro hisobi; xodim farzandi va vedomost — yo''q',
  zz.ofs(zz.get('PS')::jsonb) || ' | ' || (zz.get('PS')::jsonb ->> 'staffDiscounts') || ' | ' || coalesce(zz.get('PS')::jsonb ->> 'payroll', 'null'),
  '^2027-01-12/1/2026-12/IQT-1/Sinov Muallima/st1/Sinov Bola Bir/70000 \| \[\] \| null$');
select zz.put('P12', zz.pack('U_FM', 'main', '2026-12')::text);
select zz.chk('D9 vedomosti yo''q oy: payroll = null; o''sha oyning o''zaro hisobi va chegirmasi',
  coalesce(zz.get('P12')::jsonb ->> 'payroll', 'null') || ' | ' || zz.ofs(zz.get('P12')::jsonb) || ' | ' || zz.sd(zz.get('P12')::jsonb),
  '^null \| 2026-12-28/1/2026-11/IQT-1/-/st1/-/50000 \| IQT-1/st1/-/-/1000000/500000/500000/paid$');
select zz.chk('D10 kassir va o''qituvchi — to''plam yo''q',
  zz.as('U_KAS', $q$select public.kassa_month_pack('main', '2027-01')::text$q$) || ' | ' || zz.as('U_TCH', $q$select public.kassa_month_pack('main', '2027-01')::text$q$),
  '^ERR 42501 .* \| ERR 42501 ');
select zz.chk('D11 ichki yordamchilar yopiq (kassa_deposit_cfg, kassa_limit_hint)',
  (select string_agg(p.proname || '=' || has_function_privilege('authenticated', p.oid, 'execute'), ',' order by p.proname)
     from pg_proc p where p.pronamespace = 'app'::regnamespace and p.proname in ('kassa_deposit_cfg', 'kassa_limit_hint')),
  '^kassa_deposit_cfg=false,kassa_limit_hint=false$');

-- ---------- Natija ----------
select (case when ok then 'PASS' else 'FAIL' end) || ' ' || name || case when ok then '' else E'\n     got: ' || coalesce(got, '<null>') || E'\n     pat: ' || pat end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
