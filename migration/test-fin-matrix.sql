-- =====================================================================
-- test-fin-matrix.sql — moliya ish rejasi 2-bosqichi, F2.5 (fin-matrix.sql) sinovi: RP-09 — barcha to'lov usullari bo'yicha
--   statiya matritsasi va maosh taqsimoti.
--   (A) huquqlar va kirish: kim ko'radi (Direktor, Moliya menejeri, buxgalter), kim ko'rmaydi (kassir, g'aznachi, HR, o'qituvchi, anon);
--       davr tekshiruvi; ichki funksiya yopiq;
--   (L) lavozim -> statiya (app.fin_pos_article): apostrof turlari, bo'shliq, katta-kichik harf, o'qituvchi, aniqlanmagan;
--   (M) o'quv yili: har manba (kassa — sinov kassasi, bekor qilingan, naqd bo'lmagan qator, qayta tasnif; to'lovlar — usullar,
--       kassa orderi bilan bog'langani, o'zaro hisob, biriktirilmagan, qaytarilgan, pul bo'lmaganlar, bo'lingan, Toshkent kuni,
--       orqa sana; xarajatlar — statiya, toifa xaritasi, aniqlanmagan, hisobdor, oy sanadan, ichki o'tkazma; qaytarishlar;
--       maosh va avans to'lovlari; maosh taqsimoti — tasdiqlangan / tasdiqlanmagan vedomost, lavozimlar, nol qator);
--   (N) nazorat: Jami = Σ hujjatlar (har manba), kassa sarlavhasi, maosh taqsimoti ↔ «Maosh» qatori, aniqlanmagan toifalar;
--   (K) kalendar yili: chegaradagi hujjatlar; (F) FD-28 — javobda ism yo'q.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-fin-matrix.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov nomlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) or exists (select 1 from public.payroll_lines) then
    raise exception 'test-fin-matrix.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
create or replace function zz.mx(p_uid text, p_kind text, p_year int) returns text language sql as $$
  select zz.as(p_uid, format('select public.fin_matrix(%L, %s)::text', p_kind, coalesce(p_year::text, 'null'))) $$;
create or replace function zz.n(p numeric) returns text language sql immutable as $$ select coalesce(trim_scale(p)::text, '-') $$;
-- qatorlar: statiya=pul/hisobdor/hisoblash (javobdagi tartibda)
create or replace function zz.rows(j jsonb, p_dir text) returns text language sql as $$
  select coalesce(string_agg(coalesce(r ->> 'articleId', '-') || '=' || zz.n((r ->> 'money')::numeric) || '/' || zz.n((r ->> 'accountable')::numeric)
                             || '/' || zz.n((r ->> 'accrual')::numeric), ',' order by o), '-')
    from jsonb_array_elements(j -> 'rows') with ordinality t(r, o) where r ->> 'dir' = p_dir $$;
-- bitta katak qatori (12 oy) — usul bo'yicha
create or replace function zz.cell(j jsonb, p_dir text, p_art text, p_method text) returns text language sql as $$
  select coalesce((select string_agg(zz.n(x::numeric), ',' order by k)
                     from jsonb_array_elements_text(r -> 'm' -> p_method) with ordinality u(x, k)), '-')
    from jsonb_array_elements(j -> 'rows') r
   where r ->> 'dir' = p_dir and coalesce(r ->> 'articleId', '-') = p_art $$;
-- qator belgilari: usullar ro'yxati; ichki o'tkazma; taxminiy; manbalar
create or replace function zz.flags(j jsonb, p_dir text, p_art text) returns text language sql as $$
  select (select string_agg(k, '+' order by k) from jsonb_object_keys(r -> 'm') k) || ':' || (r ->> 'transfer') || ':' || (r ->> 'approx') || ':'
         || (select string_agg(s, '+' order by s) from jsonb_array_elements_text(r -> 'sources') s)
    from jsonb_array_elements(j -> 'rows') r
   where r ->> 'dir' = p_dir and coalesce(r ->> 'articleId', '-') = p_art $$;
create or replace function zz.srcs(j jsonb) returns text language sql as $$
  select coalesce(string_agg((s ->> 'key') || ':' || (s ->> 'docs') || ':' || zz.n((s ->> 'total')::numeric), ',' order by o), '-')
    from jsonb_array_elements(j -> 'sources') with ordinality t(s, o) $$;
-- matritsa jami (pul + hisobdor + hisoblash, ikkala yo'nalish) va manbalar jami
create or replace function zz.tot(j jsonb) returns text language sql as $$
  select zz.n((select sum((r ->> 'money')::numeric + (r ->> 'accountable')::numeric + (r ->> 'accrual')::numeric) from jsonb_array_elements(j -> 'rows') r))
         || '=' || zz.n((select sum((s ->> 'total')::numeric) from jsonb_array_elements(j -> 'sources') s))
         || '=' || zz.n((select sum(x::numeric) from jsonb_array_elements(j -> 'rows') r, jsonb_each(r -> 'm') m(k, a), jsonb_array_elements_text(m.a) x)) $$;
create or replace function zz.pay(j jsonb) returns text language sql as $$
  select coalesce(string_agg((p ->> 'month') || ':' || coalesce(p ->> 'run', '-') || ':' || zz.n((p ->> 'split')::numeric) || ':'
                             || zz.n((p ->> 'accrualRow')::numeric) || ':' || zz.n((p ->> 'diff')::numeric), ',' order by o), '-')
    from jsonb_array_elements(j #> '{payroll,byMonth}') with ordinality t(p, o)
   where p ->> 'run' is not null or p ->> 'accrualRow' is not null $$;
create or replace function zz.pos(j jsonb) returns text language sql as $$
  select coalesce(string_agg((p ->> 'type') || '/' || coalesce(p ->> 'position', '-') || '/' || coalesce(p ->> 'articleId', '-') || '/'
                             || (p ->> 'lines') || '/' || zz.n((p ->> 'total')::numeric), ',' order by o), '-')
    from jsonb_array_elements(j #> '{payroll,positions}') with ordinality t(p, o) $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]'), ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'),
  ('U_TRS','g@x','Sinov Xazinachi','treasurer','active','[]'), ('U_HR','h@x','Sinov Kadrlar','hr','active','[]'),
  ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.cash_days (id, desk, day, status, opening, receipts, payouts, closing, counted, hash, "closedBy", "closedAt", "openedAt") values
  ('cd_main_2026-08-31', 'main', '2026-08-31', 'closed', 100000, 0, 11000, 89000, 89000, 'h0', 'U_KAS', '2026-08-31 18:00+05', '2026-08-31 08:00+05'),
  ('cd_main_2026-10-05', 'main', '2026-10-05', 'closed', 89000, 300000, 120000, 269000, 269000, 'h1', 'U_KAS', '2026-10-05 18:00+05', '2026-10-05 08:00+05'),
  ('cd_main_2026-11-10', 'main', '2026-11-10', 'closed', 269000, 0, 50000, 219000, 219000, 'h2', 'U_KAS', '2026-11-10 18:00+05', '2026-11-10 08:00+05'),
  ('cd_main_2027-01-05', 'main', '2027-01-05', 'closed', 219000, 0, 95000, 124000, 124000, 'h3', 'U_KAS', '2027-01-05 18:00+05', '2027-01-05 08:00+05'),
  ('cd_sinov_2026-10-05', 'sinov', '2026-10-05', 'closed', 100000, 0, 30000, 70000, 70000, 'hs', 'U_KAS', '2026-10-05 18:00+05', '2026-10-05 08:00+05');
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "partyType", "partyId", "partyName", basis,
                              "clientRef", "postedAt", "postedBy", "createdAt") values
  ('k1', 'main', 'KO1', 'in_tuition', 'posted', 2026, 1, '2026-10-05', 'cd_main_2026-10-05', 300000, 'student', 'S1', 'Sinov O''quvchi', 'Oktabr to''lovi', 'r-k1-0001', '2026-10-05 10:00+05', 'U_KAS', '2026-10-05 09:50+05'),
  ('k2', 'main', 'KO2', 'out_expense', 'posted', 2026, 1, '2026-10-05', 'cd_main_2026-10-05', 120000, 'other', null, 'Sinov Shaxs', 'Sinov xarid', 'r-k2-0001', '2026-10-05 11:00+05', 'U_KAS', '2026-10-05 10:50+05'),
  ('k3', 'main', 'KO2', 'out_bank', 'posted', 2026, 2, '2026-11-10', 'cd_main_2026-11-10', 50000, 'bank', null, 'Sinov Bank', 'Bankka topshirish', 'r-k3-0001', '2026-11-10 11:00+05', 'U_KAS', '2026-11-10 10:50+05'),
  ('k4', 'main', 'KO2', 'out_expense', 'void', 2026, 3, '2026-11-10', 'cd_main_2026-11-10', 15000, 'other', null, 'Sinov Shaxs', 'Bekor qilingan', 'r-k4-0001', '2026-11-10 12:00+05', 'U_KAS', '2026-11-10 11:50+05'),
  ('k5', 'sinov', 'KO2', 'out_expense', 'posted', 2026, 1, '2026-10-05', 'cd_sinov_2026-10-05', 30000, 'other', null, 'Sinov Shaxs', 'Sinov kassasi', 'r-k5-0001', '2026-10-05 12:00+05', 'U_KAS', '2026-10-05 11:50+05'),
  ('k6', 'main', 'KO2', 'out_salary', 'posted', 2027, 1, '2027-01-05', 'cd_main_2027-01-05', 70000, 'employee', 'staff:st1', 'Sinov Xodim', 'Dekabr maoshi', 'r-k6-0001', '2027-01-05 11:00+05', 'U_KAS', '2027-01-05 10:50+05'),
  ('k7', 'main', 'KO2', 'out_refund', 'posted', 2027, 2, '2027-01-05', 'cd_main_2027-01-05', 25000, 'student', 'S1', 'Sinov O''quvchi', 'Avans qaytarildi', 'r-k7-0001', '2027-01-05 12:00+05', 'U_KAS', '2027-01-05 11:50+05'),
  ('k8', 'main', 'KO2', 'out_expense', 'posted', 2026, 90, '2026-08-31', 'cd_main_2026-08-31', 11000, 'other', null, 'Sinov Shaxs', 'Avgust xaridi', 'r-k8-0001', '2026-09-01 00:20+05', 'U_KAS', '2026-08-31 23:50+05'),
  ('a1', 'main', 'ACT', 'nc_offset', 'posted', 2027, 1, '2027-01-05', null, 50000, 'employee', 'staff:st1', 'Sinov Xodim', 'O''zaro hisob', 'r-a1-0001', '2027-01-05 13:00+05', 'U_DIR', '2027-01-05 12:50+05'),
  ('a2', 'main', 'ACT', 'nc_adv_report', 'posted', 2027, 1, '2027-01-12', null, 27000, 'employee', 'staff:st1', 'Sinov Xodim', 'Avans hisoboti', 'r-a2-0001', '2027-01-12 13:00+05', 'U_ACC', '2027-01-12 12:50+05');
update public.cash_docs set "voidedAt" = '2026-11-10 15:00+05', "voidedBy" = 'U_KAS', "voidReason" = 'sinov' where id = 'k4';
insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash) values
  ('l1', 'k1', 1, '5010', '4010', 300000, 'IN-01', true), ('l1x', 'k1', 2, '6310', '4010', 40000, 'IN-01', false),
  ('l2a', 'k2', 1, '9420', '5010', 100000, 'EX-32', true), ('l2b', 'k2', 2, '2010', '5010', 20000, 'EX-16', true),
  ('l3', 'k3', 1, '5710', '5010', 50000, 'OP-02', true), ('l4', 'k4', 1, '9420', '5010', 15000, 'EX-32', true),
  ('l5', 'k5', 1, '9420', '5010', 30000, 'EX-32', true), ('l6', 'k6', 1, '6710', '5010', 70000, 'OP-09', true),
  ('l7', 'k7', 1, '6310', '5010', 25000, null, true), ('l8', 'k8', 1, '9420', '5010', 11000, 'EX-32', true),
  ('la1', 'a1', 1, '6710', '4010', 50000, null, false), ('la2', 'a2', 1, '2010', '4230', 27000, 'EX-16', false);
-- k8 — 31-avgust kuni yarim tundan keyin o'tkazilgan (kassa kuni ochiq edi): oy — kassa kuni (avgust), o'tkazilgan vaqt emas
-- F2.13: k2 ning 2-qatori qayta tasniflangan (EX-16 -> EX-17)
insert into public.cash_doc_fixes (id, "docId", desk, status, year, no, "actDay", reason, before, after, "clientRef", "reqHash", "requestedBy",
                                   "requestedByName", "decidedBy", "decidedAt") values
  ('fx1', 'k2', 'main', 'approved', 2026, 1, '2026-10-20', 'Statiya xato tanlangan',
   '{"lines":[{"lineNo":1,"articleId":"EX-32"},{"lineNo":2,"articleId":"EX-16"}]}', '{"lines":[{"lineNo":1,"articleId":"EX-32"},{"lineNo":2,"articleId":"EX-17"}]}',
   'r-fx1-0001', 'h', 'U_ACC', 'Sinov Buxgalter', 'U_DIR', '2026-10-20 10:00+05');
insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw, "createdAt", "cashDocId") values
  ('p1', 'S1', 'click', 200000, 'applied', '', true, '{}', '2026-10-10 12:00+05', null),
  ('p2', 'S1', 'terminal', 150000, 'applied', '', true, '{}', '2026-11-03 12:00+05', null),
  ('p3', 'S1', 'bank', 400000, 'paid', '', true, '{}', '2026-12-01 12:00+05', null),
  ('p4', 'S1', 'cash', 300000, 'applied', '', true, '{"manual":true,"method":"cash","date":"2026-10-05"}', '2026-10-05 10:00+05', 'k1'),
  ('p5', 'S1', 'cash', 60000, 'applied', '', true, '{}', '2026-09-15 12:00+05', null),
  ('p6', 'S1', 'offset', 50000, 'applied', '', true, '{"manual":true,"method":"offset","date":"2027-01-05"}', '2027-01-05 12:00+05', 'a1'),
  ('p7', null, 'click', 35000, 'unmatched', '', false, '{}', '2026-10-20 12:00+05', null),
  ('p8', null, 'click', 45000, 'refunded', '', false, '{}', '2026-11-15 12:00+05', null),
  ('p9', 'S1', 'credit', 0, 'applied', '', true, '{}', '2026-10-11 12:00+05', null),
  ('p9g', 'S1', 'grant', 100, 'applied', '', true, '{}', '2026-10-11 12:00+05', null),
  ('p10', 'S1', 'reattr', 70000, 'applied', '', true, '{}', '2026-10-12 12:00+05', null),
  ('p11', 'S1', 'click', 30000, 'split', '', true, '{}', '2026-10-13 12:00+05', null),
  ('p11:s:1', 'S1', 'click', 10000, 'applied', '', true, '{}', '2026-10-13 12:00+05', null),
  ('p12', 'S1', 'uzum', 25000, 'reversed', '', true, '{}', '2026-10-14 12:00+05', null),
  ('p13', 'S1', 'cash', 80000, 'applied', '', true, '{"manual":true,"method":"cash","date":"2026-08-25"}', '2026-09-02 12:00+05', null),
  ('p14', 'S1', 'payme', 20000, 'pending', '', false, '{}', '2026-10-15 12:00+05', null),
  ('p15', 'S1', 'click', 7000, 'applied', '', true, '{}', '2026-09-01 00:10+05', null),
  ('p16', 'S1', 'click', 9000, 'applied', '', true, '{}', '2026-08-31 23:50+05', null);
insert into public.expenses (id, date, month, category, amount, note, method, "cashDocId", "articleId", kind) values
  ('e1', '2026-10-03', '2026-10', 'Ijara', 500000, '', 'bank', null, 'EX-10', 'expense'),
  ('e2', '2026-11-04', '2026-11', 'Kanselyariya', 40000, '', 'card', null, null, 'expense'),
  ('e3', '2026-12-05', '2026-12', 'Noma''lum toifa', 33000, '', null, null, null, 'expense'),
  ('e4', '2026-10-05', '2026-10', 'Kanselyariya', 100000, '', 'cash', 'k2', 'EX-32', 'expense'),
  ('e5', '2027-01-12', '2027-01', 'Xo‘jalik tovarlari', 27000, '', 'accountable', 'a2', 'EX-16', 'expense'),
  ('e7', '2027-02-03', '', 'Internet', 12000, '', 'bank', null, 'EX-14', 'expense'),
  ('e8', '2026-12-06', '2026-12', 'Korporativ karta', 100000, '', 'bank', null, null, 'expense'),
  ('e9', '2026-08-20', '2026-08', 'Ijara', 1000, '', 'bank', null, 'EX-10', 'expense'),
  ('e10', '2026-10-21', '2026-10', 'Ijara', 0, '', 'bank', null, 'EX-10', 'expense'),
  ('payroll__2026-10', '2026-10-01', '2026-10', 'Maosh', 1035000, '', null, null, null, 'accrual'),
  ('payroll__2026-11', '2026-11-01', '2026-11', 'Maosh', 800000, '', null, null, null, 'accrual');
insert into public.refunds (id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, method, "cashDocId", "createdAt") values
  ('r1', 'invoice', 'inv1', 'S1', '', 30000, 'sinov', '', '2026-09', null, null, '2026-12-05 12:00+05'),
  ('r2', 'credit', 'S1', 'S1', '', 15000, 'sinov', '', '2027-01', 'bank', null, '2027-01-10 12:00+05'),
  ('r3', 'payment', 'p8', '', '', 45000, 'sinov', '', '', null, null, '2026-11-16 12:00+05'),
  ('r4', 'credit', 'S1', 'S1', '', 25000, 'sinov', '', '', 'cash', 'k7', '2027-01-05 12:00+05');
insert into public.salary_payments (id, "teacherId", "teacherName", month, gross, advance, net, date, "subBonus", paid, method, "cashDocId") values
  ('s1', 'X1', '', '2026-10', 300000, 0, 300000, '2026-11-05', 0, 300000, 'card', null),
  ('s2', 'X1', '', '2026-09', 200000, 0, 200000, '2026-10-02', 10000, null, null, null),
  ('s3', 'X1', '', '2026-12', 50000, 0, 50000, '2027-01-05', 0, 50000, 'offset', 'a1'),
  ('s4', 'X1', '', '2026-12', 70000, 0, 70000, '2027-01-05', 0, 70000, 'cash', 'k6');
insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date, note, method, "cashDocId") values
  ('v1', 'X1', '', 40000, '2026-12', '2026-12-10', '', 'card', null),
  ('v2', 'X1', '', 25000, '2027-01', '', '', '', null),
  ('v3', 'X1', '', 30000, '2027-01', '2027-01-05', '', 'cash', 'k6');
insert into public.staff (id, "staffId", name, position) values
  ('st1', 'X1', 'ZZISM Birinchi', 'Kassir'), ('st2', 'X2', 'ZZISM Ikkinchi', 'Bog‘bon'), ('st3', 'X3', 'ZZISM Uchinchi', ' Qabulxona  xodimi '),
  ('st4', 'X4', 'ZZISM Tortinchi', 'Psixolog'), ('st5', 'X5', 'ZZISM Beshinchi', 'Farrosh');
insert into public.payroll_runs (id, status) values ('2026-10', 'approved'), ('2026-11', 'submitted'), ('2026-12', 'approved');
insert into public.payroll_lines (id, "runId", "personType", "personId", "refId", name, gross, deduction, "subBonus") values
  ('2026-10__teacher__T1', '2026-10', 'teacher', 'T1', 't1', 'ZZISM Muallim', 500000, 20000, 30000),
  ('2026-10__staff__X1', '2026-10', 'staff', 'X1', 'st1', 'ZZISM Birinchi', 300000, 0, 0),
  ('2026-10__staff__X2', '2026-10', 'staff', 'X2', 'st2', 'ZZISM Ikkinchi', 150000, 200000, 5000),
  ('2026-10__staff__X3', '2026-10', 'staff', 'X3', 'st3', 'ZZISM Uchinchi', 100000, 0, 0),
  ('2026-10__staff__X4', '2026-10', 'staff', 'X4', 'st4', 'ZZISM Tortinchi', 120000, 0, 0),
  ('2026-10__staff__X5', '2026-10', 'staff', 'X5', 'st5', 'ZZISM Beshinchi', 0, 0, 0),
  ('2026-11__teacher__T1', '2026-11', 'teacher', 'T1', 't1', 'ZZISM Muallim', 400000, 0, 0),
  ('2026-12__teacher__T1', '2026-12', 'teacher', 'T1', 't1', 'ZZISM Muallim', 450000, 0, 0),
  ('2026-12__staff__X9', '2026-12', 'staff', 'X9', 'st9', 'ZZISM Yoq', 60000, 0, 0);
set local session_replication_role = origin;
select zz.clock('2027-02-10 10:00+05');

-- ---------- (A) huquqlar va kirish ----------
select zz.chk('A1 kassir — yo''q', zz.mx('U_KAS', 'school', 2026), '^ERR 42501 \[\] Ruxsat yo''q: RP-09');
select zz.chk('A2 g''aznachi — yo''q', zz.mx('U_TRS', 'school', 2026), '^ERR 42501 ');
select zz.chk('A3 HR — yo''q', zz.mx('U_HR', 'school', 2026), '^ERR 42501 ');
select zz.chk('A4 o''qituvchi — yo''q', zz.mx('U_TCH', 'school', 2026), '^ERR 42501 ');
select zz.chk('A5 anon — yo''q', zz.mx(null, 'school', 2026), '^ERR 42501 ');
select zz.chk('A6 huquq birinchi tekshiriladi (noto''g''ri davr bilan ham 42501)', zz.mx('U_KAS', 'xx', 1900), '^ERR 42501 ');
select zz.chk('A7 Direktor, Moliya menejeri, buxgalter — ko''radi',
  (zz.js(zz.mx('U_DIR', 'school', 2026)) ->> 'ok') || '/' || (zz.js(zz.mx('U_FM', 'school', 2026)) ->> 'ok') || '/' || (zz.js(zz.mx('U_ACC', 'school', 2026)) ->> 'ok'),
  '^true/true/true$');
select zz.chk('A8 davr turi noto''g''ri', zz.mx('U_DIR', 'xx', 2026), '^ERR 22023 \[fin:bad_input\]');
select zz.chk('A9 yil 2024 dan oldin — yo''q', zz.mx('U_DIR', 'school', 2023), '^ERR 22023 \[fin:bad_input\]');
select zz.chk('A10 yil keyingi yildan keyin — yo''q (joriy 2027)', zz.mx('U_DIR', 'calendar', 2029), '^ERR 22023 \[fin:bad_input\]');
select zz.chk('A11 yil bo''sh — yo''q', zz.mx('U_DIR', 'school', null), '^ERR 22023 \[fin:bad_input\]');
select zz.chk('A12 keyingi yil — bo''sh matritsa', (select jsonb_array_length(j -> 'rows') || '/' || jsonb_array_length(j -> 'sources') || '/' || (j ->> 'from') || '/' || (j ->> 'to')
     from (select zz.js(zz.mx('U_DIR', 'calendar', 2028)) as j) x), '^0/0/2028-01-01/2028-12-31$');
select zz.chk('A13 tur bo''shliq va katta harf bilan ham',
  (select (j ->> 'kind') || '/' || (j ->> 'from') || '/' || (j ->> 'to') || '/' || (j -> 'months' ->> 0) || '/' || (j -> 'months' ->> 11) || '/' || jsonb_array_length(j -> 'months')
     from (select zz.js(zz.mx('U_DIR', ' School ', 2026)) as j) x), '^school/2026-09-01/2027-08-31/2026-09/2027-08/12$');
select zz.chk('A14 huquqlar: fin_matrix — authenticated (anon emas), fin_pos_article — hech kimga',
  has_function_privilege('authenticated', 'public.fin_matrix(text,int)', 'execute') || '/' || has_function_privilege('anon', 'public.fin_matrix(text,int)', 'execute')
  || '/' || has_function_privilege('authenticated', 'app.fin_pos_article(text,text)', 'execute') || '/' || has_function_privilege('anon', 'app.fin_pos_article(text,text)', 'execute'),
  '^true/false/false/false$');
select zz.chk('A15 security definer, stable, search_path belgilangan',
  (select p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(array_to_string(p.proconfig, ';'), '-') from pg_proc p where p.oid = 'public.fin_matrix(text,int)'::regprocedure),
  '^true/s/search_path=public, app, pg_temp$');

-- ---------- (L) lavozim -> statiya ----------
select zz.chk('L1 o''qituvchilar ro''yxati — EX-01 (lavozimdan qat''i nazar)', coalesce(app.fin_pos_article('teacher', null), '-') || '/' || coalesce(app.fin_pos_article('teacher', 'Direktor'), '-'), '^EX-01/EX-01$');
select zz.chk('L2 o''qituvchi va kurator — EX-01', app.fin_pos_article('staff', 'O‘qituvchi') || '/' || app.fin_pos_article('staff', 'KURATOR'), '^EX-01/EX-01$');
select zz.chk('L3 apostrof turlari (‘ '' ʻ ` ’) — bir xil',
  app.fin_pos_article('staff', 'Bog‘bon') || '/' || app.fin_pos_article('staff', 'Bog''bon') || '/' || app.fin_pos_article('staff', 'Bogʻbon') || '/'
  || app.fin_pos_article('staff', 'Bog`bon') || '/' || app.fin_pos_article('staff', 'Bog’bon'), '^EX-02/EX-02/EX-02/EX-02/EX-02$');
select zz.chk('L4 bo''shliqlar va katta-kichik harf', app.fin_pos_article('staff', '  Xo‘jalik   XODIMI ') || '/' || app.fin_pos_article('staff', 'oshxona xodimi'), '^EX-02/EX-02$');
select zz.chk('L5 ma''muriy — EX-03', app.fin_pos_article('staff', 'Ma’muriyat rahbari') || '/' || app.fin_pos_article('staff', 'O‘IBDO‘') || '/' || app.fin_pos_article('staff', 'G‘aznachi')
  || '/' || app.fin_pos_article('staff', 'HR') || '/' || app.fin_pos_article('staff', 'HR menejer') || '/' || app.fin_pos_article('staff', 'Buxgalter') || '/' || app.fin_pos_article(null, 'Kassir'),
  '^EX-03/EX-03/EX-03/EX-03/EX-03/EX-03/EX-03$');
select zz.chk('L6 qabul va marketing — EX-04', app.fin_pos_article('staff', 'Qabulxona xodimi') || '/' || app.fin_pos_article('staff', 'Sotuvchi') || '/' || app.fin_pos_article('staff', 'Marketing menejeri'), '^EX-04/EX-04/EX-04$');
select zz.chk('L7 aniqlanmagan — null', coalesce(app.fin_pos_article('staff', 'Psixolog'), '-') || '/' || coalesce(app.fin_pos_article('staff', null), '-') || '/' || coalesce(app.fin_pos_article('staff', ''), '-')
  || '/' || coalesce(app.fin_pos_article('staff', 'Kassir yordamchisi'), '-'), '^-/-/-/-$');
select zz.chk('L8 «Xodimlar» lavozimlari ro''yxatining hammasi statiyaga tushadi (admin.html STAFF_POSITIONS)',
  (select count(*) filter (where app.fin_pos_article('staff', x) is null) || '/' || count(*)
     from unnest(array['Direktor','Ma‘muriyat rahbari','O‘IBDO‘','HR','Moliya menejeri','Kassir','Marketing menejeri','Sotuvchi','O‘qituvchi','Kurator',
                       'Qabulxona xodimi','G‘aznachi','Xo‘jalik xodimi','Bosh oshpaz','Oshxona xodimi','Tozalov xodimi','Qorovul','Xavfsizlik xodimi',
                       'Hamshira','Laborant','Kutubxonachi','Haydovchi','Farrosh','Bog‘bon']) x), '^0/24$');

-- ---------- (M) o'quv yili 2026/27 ----------
select zz.put('j', zz.mx('U_ACC', 'school', 2026));
select zz.chk('M1 kirim qatorlari: o''quv to''lovi va aniqlanmagan tushum', zz.rows(zz.get('j')::jsonb, 'in'), '^IN-01=1197000/0/0,OP-16=80000/0/0$');
select zz.chk('M2 chiqim qatorlari (statiya tartibida; aniqlanmagan — oxirida)', zz.rows(zz.get('j')::jsonb, 'out'),
  '^EX-01=0/0/960000,EX-02=0/0/5000,EX-03=0/0/300000,EX-04=0/0/100000,EX-10=500000/0/0,EX-14=12000/0/0,EX-16=0/27000/0,EX-17=20000/0/0,EX-32=140000/0/0,OP-02=50000/0/0,OP-04=100000/0/0,OP-08=65000/0/0,OP-09=630000/0/0,OP-15=45000/0/0,OP-16=45000/0/0,-=58000/0/980000$');
select zz.chk('M3 IN-01 naqd: kassagacha (sentyabr) + KO-1 (oktyabr); kassa orderi bilan bog''langan to''lov ikki marta emas; naqd bo''lmagan qator yo''q',
  zz.cell(zz.get('j')::jsonb, 'in', 'IN-01', 'cash'), '^60000,300000,0,0,0,0,0,0,0,0,0,0$');
select zz.chk('M4 IN-01 onlayn: Toshkent kuni (1-sentyabr 00:10), bo''lingan to''lov bir marta; qaytarilgan / qo''llash / grant / ko''chirish / kutilayotgan yo''q',
  zz.cell(zz.get('j')::jsonb, 'in', 'IN-01', 'online'), '^7000,230000,0,0,0,0,0,0,0,0,0,0$');
select zz.chk('M5 IN-01 karta, bank, o''zaro hisob (dalolatnomaga bog''langan — sanaladi)',
  zz.cell(zz.get('j')::jsonb, 'in', 'IN-01', 'card') || '|' || zz.cell(zz.get('j')::jsonb, 'in', 'IN-01', 'bank') || '|' || zz.cell(zz.get('j')::jsonb, 'in', 'IN-01', 'offset'),
  '^0,0,150000,0,0,0,0,0,0,0,0,0\|0,0,0,400000,0,0,0,0,0,0,0,0\|0,0,0,0,50000,0,0,0,0,0,0,0$');
select zz.chk('M6 OP-16 kirim: biriktirilmagan (oktyabr) va qaytarilgan (noyabr) to''lov', zz.cell(zz.get('j')::jsonb, 'in', 'OP-16', 'online'), '^0,35000,45000,0,0,0,0,0,0,0,0,0$');
select zz.chk('M7 OP-16 chiqim: qaytarilgan to''lov (juft)', zz.cell(zz.get('j')::jsonb, 'out', 'OP-16', 'other'), '^0,0,45000,0,0,0,0,0,0,0,0,0$');
select zz.chk('M8 kassa: qayta tasnif (EX-16 -> EX-17), sinov kassasi, bekor qilingan va kassa kuni avgust (o''tkazilgan — sentyabr) bo''lgan order yo''q',
  zz.cell(zz.get('j')::jsonb, 'out', 'EX-17', 'cash') || '|' || zz.cell(zz.get('j')::jsonb, 'out', 'EX-32', 'cash') || '|' || coalesce(zz.cell(zz.get('j')::jsonb, 'out', 'EX-16', 'cash'), 'yoq'),
  '^0,20000,0,0,0,0,0,0,0,0,0,0\|0,100000,0,0,0,0,0,0,0,0,0,0\|-$');
select zz.chk('M9 EX-32: kassa (naqd) + «Buxgalteriya» karta (toifadan — taxminiy)',
  zz.cell(zz.get('j')::jsonb, 'out', 'EX-32', 'card') || '|' || zz.flags(zz.get('j')::jsonb, 'out', 'EX-32'), '^0,0,40000,0,0,0,0,0,0,0,0,0\|card\+cash:false:true:expenses\+kassa$');
select zz.chk('M10 hisobdor xarajati (avans hisoboti) — alohida ustun, pul jamiga kirmaydi', zz.cell(zz.get('j')::jsonb, 'out', 'EX-16', 'accountable') || '|' || zz.flags(zz.get('j')::jsonb, 'out', 'EX-16'),
  '^0,0,0,0,27000,0,0,0,0,0,0,0\|accountable:false:false:expenses$');
select zz.chk('M11 xarajat oyi sanadan (oy bo''sh) va statiya yozuvdan', zz.cell(zz.get('j')::jsonb, 'out', 'EX-14', 'bank') || '|' || zz.flags(zz.get('j')::jsonb, 'out', 'EX-10'),
  '^0,0,0,0,0,12000,0,0,0,0,0,0\|bank:false:false:expenses$');
select zz.chk('M12 ichki o''tkazma: bankka topshirish (kassa, 5710) va korporativ karta (OP-04, toifadan)',
  zz.flags(zz.get('j')::jsonb, 'out', 'OP-02') || '|' || zz.flags(zz.get('j')::jsonb, 'out', 'OP-04'), '^cash:true:false:kassa\|bank:true:true:expenses$');
select zz.chk('M13 OP-09: kassagacha naqd (net + o''rinbosarlik), karta, o''zaro hisob, KO-2 — bog''langan to''lov ikki marta emas',
  zz.cell(zz.get('j')::jsonb, 'out', 'OP-09', 'cash') || '|' || zz.cell(zz.get('j')::jsonb, 'out', 'OP-09', 'card') || '|' || zz.cell(zz.get('j')::jsonb, 'out', 'OP-09', 'offset')
  || '|' || zz.flags(zz.get('j')::jsonb, 'out', 'OP-09'),
  '^0,210000,0,0,70000,0,0,0,0,0,0,0\|0,0,300000,0,0,0,0,0,0,0,0,0\|0,0,0,0,50000,0,0,0,0,0,0,0\|card\+cash\+offset:false:false:kassa\+salary$');
select zz.chk('M14 OP-08 avans: karta (dekabr), sanasiz — oy bo''yicha (yanvar); KO-2 ga bog''langani yo''q',
  zz.cell(zz.get('j')::jsonb, 'out', 'OP-08', 'card') || '|' || zz.cell(zz.get('j')::jsonb, 'out', 'OP-08', 'cash'), '^0,0,0,40000,0,0,0,0,0,0,0,0\|0,0,0,0,25000,0,0,0,0,0,0,0$');
select zz.chk('M15 OP-15: eski qaytarish — yozilgan oy (faktura oyi emas), usuli noma''lum; bank; kassadagisi ikki marta emas',
  zz.cell(zz.get('j')::jsonb, 'out', 'OP-15', 'other') || '|' || zz.cell(zz.get('j')::jsonb, 'out', 'OP-15', 'bank'), '^0,0,0,30000,0,0,0,0,0,0,0,0\|0,0,0,0,15000,0,0,0,0,0,0,0$');
select zz.chk('M16 aniqlanmagan chiqim: statiyasiz kassa qatori, toifasi yo''q xarajat, taqsimlanmagan maosh va lavozimi aniqlanmagan',
  zz.cell(zz.get('j')::jsonb, 'out', '-', 'cash') || '|' || zz.cell(zz.get('j')::jsonb, 'out', '-', 'other') || '|' || zz.cell(zz.get('j')::jsonb, 'out', '-', 'accrual')
  || '|' || zz.flags(zz.get('j')::jsonb, 'out', '-'),
  '^0,0,0,0,25000,0,0,0,0,0,0,0\|0,0,0,33000,0,0,0,0,0,0,0,0\|0,120000,800000,60000,0,0,0,0,0,0,0,0\|accrual\+cash\+other:false:false:expenses\+kassa\+payroll$');
select zz.chk('M17 maosh taqsimoti: o''qituvchi (maosh − ushlanma + o''rinbosarlik), ushlanma maoshdan ko''p — 0 + o''rinbosarlik',
  zz.cell(zz.get('j')::jsonb, 'out', 'EX-01', 'accrual') || '|' || zz.cell(zz.get('j')::jsonb, 'out', 'EX-02', 'accrual'),
  '^0,510000,0,450000,0,0,0,0,0,0,0,0\|0,5000,0,0,0,0,0,0,0,0,0,0$');
select zz.chk('M18 lavozimlar: statiya bo''yicha; nol qator, tasdiqlanmagan vedomost yo''q; o''chirilgan xodim kartasi — aniqlanmagan',
  zz.pos(zz.get('j')::jsonb), '^teacher/-/EX-01/2/960000,staff/Bog‘bon/EX-02/1/5000,staff/Kassir/EX-03/1/300000,staff/Qabulxona  xodimi/EX-04/1/100000,staff/Psixolog/-/1/120000,staff/-/-/1/60000$');
select zz.chk('M19 javob tarkibi: usullar ro''yxati, vaqt, statiya nomi', (select jsonb_array_length(j -> 'methods') || '/' || (j -> 'methods' ->> 7) || '/' || ((j ->> 'generatedAt') is not null)
     || '/' || (select r ->> 'nameUz' from jsonb_array_elements(j -> 'rows') r where r ->> 'articleId' = 'EX-10') from (select zz.get('j')::jsonb as j) x),
  '^8/accrual/true/Bino ijarasi$');

-- ---------- (N) nazorat: Jami = Σ hujjatlar ----------
select zz.chk('N1 manbalar: hujjatlar soni va jami', zz.srcs(zz.get('j')::jsonb),
  '^kassa:5:565000,payments:9:977000,expenses:6:712000,refunds:3:90000,salary:3:560000,advances:2:65000,payroll:8:2345000$');
select zz.chk('N2 matritsa jami = manbalar jami = kataklar jami', zz.tot(zz.get('j')::jsonb), '^5314000=5314000=5314000$');
select zz.chk('N3 kassa: order sarlavhalari (kirim / chiqim / soni) = kassa manbasi (qatorlar)',
  (select zz.n((j #>> '{kassaHeader,in}')::numeric) || '/' || zz.n((j #>> '{kassaHeader,out}')::numeric) || '/' || (j #>> '{kassaHeader,docs}') || '|'
          || ((j #>> '{kassaHeader,in}')::numeric + (j #>> '{kassaHeader,out}')::numeric
              = (select (s ->> 'total')::numeric from jsonb_array_elements(j -> 'sources') s where s ->> 'key' = 'kassa'))::text
          || '/' || ((j #>> '{kassaHeader,docs}') = (select s ->> 'docs' from jsonb_array_elements(j -> 'sources') s where s ->> 'key' = 'kassa'))::text
     from (select zz.get('j')::jsonb as j) x), '^300000/265000/5\|true/true$');
select zz.chk('N4 maosh: oy bo''yicha taqsimot ↔ «Maosh» qatori (tasdiqlangan — farq 0; tasdiqlanmagan — taqsimlanmagan; qator yozilmagan)',
  zz.pay(zz.get('j')::jsonb), '^2026-10:approved:1035000:1035000:0,2026-11:submitted:0:800000:-,2026-12:approved:510000:-:-$');
select zz.chk('N5 aniqlanmagan toifalar ro''yxati', (select string_agg((u ->> 'category') || ':' || (u ->> 'rows') || ':' || zz.n((u ->> 'total')::numeric), ',')
     from jsonb_array_elements(zz.get('j')::jsonb -> 'unclassified') u), '^Noma''lum toifa:1:33000$');
select zz.chk('N6 manbalar bo''yicha oylar (kassa)', (select string_agg(zz.n(x::numeric), ',' order by k)
     from jsonb_array_elements(zz.get('j')::jsonb -> 'sources') s, jsonb_array_elements_text(s -> 'byMonth') with ordinality u(x, k) where s ->> 'key' = 'kassa'),
  '^0,420000,50000,0,95000,0,0,0,0,0,0,0$');
select zz.chk('N7 uch rol uchun javob bir xil',
  ((zz.js(zz.mx('U_DIR', 'school', 2026)) - 'generatedAt') = (zz.get('j')::jsonb - 'generatedAt'))::text || '/'
  || ((zz.js(zz.mx('U_FM', 'school', 2026)) - 'generatedAt') = (zz.get('j')::jsonb - 'generatedAt'))::text, '^true/true$');

-- ---------- (K) kalendar yili 2026 ----------
select zz.put('c', zz.mx('U_DIR', 'calendar', 2026));
select zz.chk('K1 avgust: kassa orderi, orqa sanali qo''lda to''lov, 31-avgust 23:50 (Toshkent) to''lovi, avgust xarajati',
  zz.cell(zz.get('c')::jsonb, 'out', 'EX-32', 'cash') || '|' || zz.cell(zz.get('c')::jsonb, 'in', 'IN-01', 'cash') || '|' || zz.cell(zz.get('c')::jsonb, 'in', 'IN-01', 'online')
  || '|' || zz.cell(zz.get('c')::jsonb, 'out', 'EX-10', 'bank'),
  '^0,0,0,0,0,0,0,11000,0,100000,0,0\|0,0,0,0,0,0,0,80000,60000,300000,0,0\|0,0,0,0,0,0,0,9000,7000,230000,0,0\|0,0,0,0,0,0,0,1000,0,500000,0,0$');
select zz.chk('K2 2027 yanvar-fevral hujjatlari kirmaydi', zz.rows(zz.get('c')::jsonb, 'out'),
  '^EX-01=0/0/960000,EX-02=0/0/5000,EX-03=0/0/300000,EX-04=0/0/100000,EX-10=501000/0/0,EX-17=20000/0/0,EX-32=151000/0/0,OP-02=50000/0/0,OP-04=100000/0/0,OP-08=40000/0/0,OP-09=510000/0/0,OP-15=30000/0/0,OP-16=45000/0/0,-=33000/0/980000$');
select zz.chk('K3 manbalar va jami', zz.srcs(zz.get('c')::jsonb) || '|' || zz.tot(zz.get('c')::jsonb),
  '^kassa:4:481000,payments:10:1016000,expenses:5:674000,refunds:2:75000,salary:2:510000,advances:1:40000,payroll:8:2345000\|5141000=5141000=5141000$');

-- ---------- (F) FD-28: javobda ism yo'q ----------
select zz.chk('F1 xodim, o''quvchi va hujjat tomonlari ismlari javobda yo''q (uch rol)',
  (strpos(zz.get('j'), 'ZZISM') = 0 and strpos(zz.get('j'), 'Sinov') = 0 and strpos(zz.get('c'), 'ZZISM') = 0 and strpos(zz.get('c'), 'Sinov') = 0
   and strpos(zz.mx('U_FM', 'school', 2026), 'ZZISM') = 0)::text, '^true$');

-- ---------- Natija ----------
select (case when ok then 'PASS' else 'FAIL' end) || ' ' || name || case when ok then '' else E'\n     got: ' || coalesce(got, '<null>') || E'\n     pat: ' || pat end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
