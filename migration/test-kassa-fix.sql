-- =====================================================================
-- test-kassa-fix.sql — moliya ish rejasi 2-bosqichi, F2.13 (kassa.sql: cash_doc_fixes; kassa-fix.sql) sinovi: qayta tasnif
--   dalolatnomasi — o'tkazilgan «Xarajat» chiqim orderidagi hisob xatosini (statiya, tomon, asos) Direktor ruxsati bilan tuzatish.
--   (A) huquqlar: kim so'raydi (buxgalter, Moliya menejeri), kim qaror qiladi (Direktor), kim bekor qiladi; jadvalga to'g'ridan-to'g'ri
--       yozish va ichki funksiyalar yopiq;
--   (B) so'rov tekshiruvlari: hujjat turi va holati, ochiq kun, yopilgan davr, statiya qoidasi, qator, tomon, asos, sabab, «o'zgarish yo'q»;
--   (C) oqim: so'rov → takror (dup) / boshqa mazmun → tasdiq (raqam, sana) → «Buxgalteriya» qatori → asl hujjat o'zgarmaydi → amaldagi
--       holat (hujjat javobi, statiya matritsasi, kontragent ko'chirmasi) → ikkinchi dalolatnoma; rad etish; bekor qilish;
--       tasdiqda qayta tekshiruv (kun qayta ochilgan, davr yopilgan, statiya hisobvarag'i o'zgargan / faol emas);
--   (D) himoya: o'zgarmaslik, o'chirilmaslik, bitta kutilayotgan so'rov, o'z so'rovi bo'yicha qaror yo'q, raqamlash, o'zgarishlar tarixi;
--   (E) ro'yxat, bitta dalolatnoma, nazorat ro'yxati va kassa holatidagi sonlar.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-fix.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov nomlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.fin_counterparties) or exists (select 1 from public.cash_docs) then
    raise exception 'test-kassa-fix.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
-- Jadval egasi sifatida, kassa bayrog'i bilan (triggerlar ishlaydi; RLS va huquqlar chetlab o'tiladi) — himoyani sinash uchun
create or replace function zz.ownf(p_q text, p_flag boolean default true) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('iqror.kassa_rpc', case when p_flag then '1' else '' end, true);
  begin
    execute p_q into r;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    r := 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
  end;
  perform set_config('iqror.kassa_rpc', '', true);
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
-- so'rov, qaror, bekor qilish
create or replace function zz.rq(p_uid text, p jsonb) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_fix_request(%L::jsonb)::text', p::text)) $$;
create or replace function zz.dc(p_uid text, p_id text, p_ok boolean, p_note text default '') returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_fix_decide(%L, %L, %L)::text', p_id, p_ok, p_note)) $$;
create or replace function zz.cn(p_uid text, p_id text, p_reason text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_fix_cancel(%L, %L)::text', p_id, p_reason)) $$;
create or replace function zz.fb(p_ref text, o jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('docId', 'f1', 'clientRef', p_ref, 'reason', 'Statiya xato tanlangan — hisob-faktura bo''yicha') || o $$;
create or replace function zz.f(p text, k text) returns text language sql as $$ select zz.js(p) ->> k $$;
-- dalolatnoma qisqachasi: holat:raqam:statiyalar(qator=statiya/debet):tomon:asos
create or replace function zz.fx(p_id text) returns text language sql as $$
  select f.status || ':' || coalesce(f.no::text, '-') || ':'
      || (select string_agg((x ->> 'lineNo') || '=' || (x ->> 'articleId') || '/' || (x ->> 'debit'), ',' order by (x ->> 'lineNo')::int)
            from jsonb_array_elements(f.after -> 'lines') x)
      || ':' || coalesce(f.after ->> 'partyType', '') || '/' || coalesce(f.after ->> 'partyId', '-') || '/' || coalesce(f.after ->> 'partyName', '')
      || ':' || coalesce(f.after ->> 'basis', '')
    from public.cash_doc_fixes f where f.id = p_id $$;
-- statiya matritsasi: KO2 statiya=jami (tartibda)
create or replace function zz.mx(p_uid text, p_desk text, p_month text) returns text language sql as $$
  select coalesce((select string_agg((r ->> 'articleId') || '=' || trim_scale((r ->> 'total')::numeric), ',' order by r ->> 'articleId')
                     from jsonb_array_elements(zz.js(zz.as(p_uid, format('select public.kassa_matrix(%L, %L)::text', p_desk, p_month))) -> 'rows') r
                    where r ->> 'form' = 'KO2'), '-') $$;
-- kontragent ko'chirmasi: hujjat:olindi:berildi:statiyalar:asos (tartibda)
create or replace function zz.st(p_uid text, p_id text) returns text language sql as $$
  select coalesce((select string_agg((r ->> 'doc') || ':' || trim_scale((r ->> 'in')::numeric) || ':' || trim_scale((r ->> 'out')::numeric) || ':'
                                     || (select string_agg(a, '+' order by a) from jsonb_array_elements_text(r -> 'arts') a) || ':' || (r ->> 'text'), ',' order by o)
                     from jsonb_array_elements(zz.js(zz.as(p_uid, format('select public.fin_cp_statement(%L, %L::date, %L::date)::text', p_id, '2027-01-01', '2027-02-10'))) -> 'rows')
                          with ordinality t(r, o)), '-') $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'), ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]'),
  ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.fin_counterparties (id, kind, name, stir, active, "createdAt") values
  ('cp1', 'supplier', 'Sinov Ta''minotchi', '000000101', true, '2027-01-01 09:00+05'),
  ('cp2', 'supplier', 'Sinov Ijarachi', '000000102', true, '2027-01-01 09:01+05'),
  ('cp3', 'bank', 'Sinov Bank', '', true, '2027-01-01 09:02+05'),
  ('cp4', 'supplier', 'Nofaol Sinov', '000000104', false, '2027-01-01 09:03+05');
insert into public.cash_days (id, desk, day, status, opening, receipts, payouts, closing, counted, hash, "closedBy", "closedAt", "verifiedBy", "verifiedAt", "openedAt") values
  ('cd_main_2026-12-20', 'main', '2026-12-20', 'closed', 500000, 0, 300000, 200000, 200000, 'h0', 'U_KAS', '2026-12-20 18:00+05', null, null, '2026-12-20 08:00+05'),
  ('cd_main_2027-01-05', 'main', '2027-01-05', 'closed', 1000000, 10000, 650000, 360000, 360000, 'h1', 'U_KAS', '2027-01-05 18:00+05', null, null, '2027-01-05 08:00+05'),
  ('cd_main_2027-01-06', 'main', '2027-01-06', 'verified', 360000, 0, 50000, 310000, 310000, 'h2', 'U_KAS', '2027-01-06 18:00+05', 'U_ACC', '2027-01-07 10:00+05', '2027-01-06 08:00+05'),
  ('cd_sinov_2027-01-05', 'sinov', '2027-01-05', 'closed', 100000, 0, 30000, 70000, 70000, 'hs', 'U_KAS', '2027-01-05 18:00+05', null, null, '2027-01-05 08:00+05');
insert into public.cash_days (id, desk, day, status, opening, "openedAt") values ('cd_main_2027-02-10', 'main', '2027-02-10', 'open', 310000, '2027-02-10 08:00+05');
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "partyType", "partyId", "partyName", basis, "noBasis",
                              "clientRef", "postedAt", "postedBy", "postedByName", "createdAt") values
  ('f1', 'main', 'KO2', 'out_expense', 'posted', 2027, 3, '2027-01-05', 'cd_main_2027-01-05', 600000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Sinov xarid — hisob-faktura № 0-12', false, 'r-f1-0001', '2027-01-05 11:00+05', 'U_KAS', 'Sinov Kassir', '2027-01-05 10:00+05'),
  ('f2', 'main', 'KO2', 'out_expense', 'posted', 2027, 4, '2027-01-06', 'cd_main_2027-01-06', 50000, 'other', null, 'Sinov Shaxs', '', true, 'r-f2-0001', '2027-01-06 11:00+05', 'U_KAS', 'Sinov Kassir', '2027-01-06 10:00+05'),
  ('f3', 'main', 'KO2', 'out_expense', 'posted', 2027, 5, '2027-02-10', 'cd_main_2027-02-10', 20000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Bugungi xarid', false, 'r-f3-0001', '2027-02-10 09:00+05', 'U_KAS', 'Sinov Kassir', '2027-02-10 08:30+05'),
  ('f4', 'main', 'KO1', 'in_other', 'posted', 2027, 1, '2027-01-05', 'cd_main_2027-01-05', 10000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Ortiqcha to''lov qaytdi', false, 'r-f4-0001', '2027-01-05 12:00+05', 'U_KAS', 'Sinov Kassir', '2027-01-05 11:30+05'),
  ('f5', 'main', 'KO2', 'out_expense', 'void', 2027, 6, '2027-01-06', 'cd_main_2027-01-06', 15000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Bekor qilingan', false, 'r-f5-0001', '2027-01-06 12:00+05', 'U_KAS', 'Sinov Kassir', '2027-01-06 11:30+05'),
  ('f6', 'main', 'KO2', 'out_expense', 'posted', 2026, 40, '2026-12-20', 'cd_main_2026-12-20', 300000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Dekabr xaridi', false, 'r-f6-0001', '2026-12-20 11:00+05', 'U_KAS', 'Sinov Kassir', '2026-12-20 10:00+05'),
  ('f7', 'main', 'KO2', 'out_salary', 'posted', 2027, 7, '2027-01-05', 'cd_main_2027-01-05', 50000, 'employee', 'staff:s1', 'Sinov Xodim', 'Yanvar maoshi', false, 'r-f7-0001', '2027-01-05 13:00+05', 'U_KAS', 'Sinov Kassir', '2027-01-05 12:30+05'),
  ('f8', 'sinov', 'KO2', 'out_expense', 'posted', 2027, 1, '2027-01-05', 'cd_sinov_2027-01-05', 30000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Sinov kassasi xaridi', false, 'r-f8-0001', '2027-01-05 14:00+05', 'U_KAS', 'Sinov Kassir', '2027-01-05 13:30+05');
update public.cash_docs set "voidedAt" = '2027-01-06 15:00+05', "voidedBy" = 'U_KAS', "voidReason" = 'sinov' where id = 'f5';
insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash) values
  ('l1a', 'f1', 1, '9420', '5010', 400000, 'EX-32', true), ('l1b', 'f1', 2, '9430', '5010', 200000, 'EX-49', true),
  ('l2', 'f2', 1, '9420', '5010', 50000, 'EX-32', true), ('l3', 'f3', 1, '9420', '5010', 20000, 'EX-32', true),
  ('l4', 'f4', 1, '5010', '9390', 10000, 'IN-06', true), ('l5', 'f5', 1, '9420', '5010', 15000, 'EX-32', true),
  ('l6', 'f6', 1, '9420', '5010', 300000, 'EX-32', true), ('l7', 'f7', 1, '6710', '5010', 50000, 'OP-09', true),
  ('l8', 'f8', 1, '9420', '5010', 30000, 'EX-32', true);
-- «Buxgalteriya»ga ko'chgan qatorlar (kassa_link_paid ko'rinishida)
insert into public.expenses (id, date, month, category, amount, note, method, "cashDocId", "articleId", "counterpartyId", "createdAt")
select 'kx_' || l."docId" || '_' || l."lineNo", to_char(c."businessDay", 'YYYY-MM-DD'), to_char(c."businessDay", 'YYYY-MM'), k.o_category, l.amount,
       'asl izoh (KO-2 № ' || c.no || ')', 'cash', c.id, l."articleId", case when c."partyType" = 'counterparty' then c."partyId" end, c."postedAt"
  from public.cash_doc_lines l join public.cash_docs c on c.id = l."docId" cross join lateral app.kassa_exp_category(l."articleId") k
 where c.op = 'out_expense' and c.status = 'posted';
update public.fin_org set "lockedThrough" = '2026-12-31' where id = 'main';
set local session_replication_role = origin;
select zz.clock('2027-02-10 10:00+05');

-- ---------- (A) huquqlar ----------
select zz.chk('A1 kassir so''ray olmaydi', zz.rq('U_KAS', zz.fb('ref-a1-0001', '{"lines":[{"lineNo":2,"articleId":"EX-16"}]}')), '^ERR 42501 \[kassa:fix_rights\]');
select zz.chk('A2 o''qituvchi so''ray olmaydi', zz.rq('U_TCH', zz.fb('ref-a2-0001', '{"lines":[{"lineNo":2,"articleId":"EX-16"}]}')), '^ERR 42501 \[kassa:fix_rights\]');
select zz.chk('A3 Direktor so''ramaydi (u tasdiqlaydi)', zz.rq('U_DIR', zz.fb('ref-a3-0001', '{"lines":[{"lineNo":2,"articleId":"EX-16"}]}')), '^ERR 42501 \[kassa:fix_rights\]');
select zz.chk('A4 anon — yo''q', zz.as(null, format('select public.kassa_fix_request(%L::jsonb)::text', zz.fb('ref-a4-0001')::text)), '^ERR 42501');
select zz.chk('A5 jadvalga to''g''ridan-to''g''ri yozish — yo''q',
  zz.as('U_ACC', $q$insert into public.cash_doc_fixes (id, "docId", desk, status, reason, before, after, "clientRef", "reqHash", "requestedBy")
                    values ('x', 'f1', 'main', 'pending', 'xxxxxx', '{}', '{}', 'ref-x-0001', 'h', 'U_ACC') returning id$q$), '^ERR 42501 \[\] permission denied');
select zz.chk('A6 ichki funksiyalar yopiq',
  (select string_agg(p.proname || '=' || has_function_privilege('authenticated', p.oid, 'execute'), ',' order by p.proname)
     from pg_proc p where p.pronamespace = 'app'::regnamespace and p.proname in ('kassa_fix_target', 'kassa_fix_state', 'kassa_fix_article', 'kassa_fix_json', 'kassa_fix_guard', 'kassa_eff_art', 'kassa_eff_doc')),
  '^kassa_eff_art=false,kassa_eff_doc=false,kassa_fix_article=false,kassa_fix_guard=false,kassa_fix_json=false,kassa_fix_state=false,kassa_fix_target=false$');
select zz.chk('A7 ro''yxat: kassir — yo''q', zz.as('U_KAS', $q$select public.kassa_fix_list('main', 'pending')::text$q$), '^ERR 42501 \[kassa:fix_rights\]');
select zz.chk('A8 bitta dalolatnoma: o''qituvchi — yo''q', zz.as('U_TCH', $q$select public.kassa_fix_get('x')::text$q$), '^ERR 42501 \[kassa:fix_rights\]');

-- ---------- (B) so'rov tekshiruvlari ----------
select zz.chk('B1 hujjat topilmadi', zz.rq('U_ACC', zz.fb('ref-b1-0001', '{"docId":"yoq","lines":[{"lineNo":1,"articleId":"EX-16"}]}')), '^ERR 22023 \[kassa:not_found\]');
select zz.chk('B2 kirim orderi — yo''q', zz.rq('U_ACC', zz.fb('ref-b2-0001', '{"docId":"f4","basis":"Boshqa asos"}')), '^ERR 22023 \[kassa:fix_kind\]');
select zz.chk('B3 bekor qilingan — yo''q', zz.rq('U_ACC', zz.fb('ref-b3-0001', '{"docId":"f5","lines":[{"lineNo":1,"articleId":"EX-16"}]}')), '^ERR 22023 \[kassa:fix_kind\]');
select zz.chk('B4 maosh orderi — yo''q (faqat «Xarajat»)', zz.rq('U_ACC', zz.fb('ref-b4-0001', '{"docId":"f7","basis":"Boshqa asos"}')), '^ERR 22023 \[kassa:fix_kind\]');
select zz.chk('B5 ochiq kun — kassir bekor qilib qayta yozadi', zz.rq('U_ACC', zz.fb('ref-b5-0001', '{"docId":"f3","lines":[{"lineNo":1,"articleId":"EX-16"}]}')), '^ERR P0001 \[kassa:fix_day_open\]');
select zz.chk('B6 yopilgan davr — yo''q', zz.rq('U_ACC', zz.fb('ref-b6-0001', '{"docId":"f6","lines":[{"lineNo":1,"articleId":"EX-16"}]}')), '^ERR 42501 \[fin:locked\]');
select zz.chk('B7 o''zgarish yo''q (shu statiya, shu tomon, shu asos)',
  zz.rq('U_ACC', zz.fb('ref-b7-0001', '{"lines":[{"lineNo":2,"articleId":"EX-49"}],"party":{"type":"counterparty","id":"cp1"},"basis":"Sinov xarid — hisob-faktura № 0-12"}')), '^ERR 22023 \[kassa:fix_nochange\]');
select zz.chk('B8 sabab qisqa', zz.rq('U_ACC', zz.fb('ref-b8-0001', '{"reason":"xato","lines":[{"lineNo":2,"articleId":"EX-16"}]}')), '^ERR 22023 \[kassa:fix_reason\]');
select zz.chk('B9 kassadan xarajat qilinmaydigan statiya (ish haqi)', zz.rq('U_ACC', zz.fb('ref-b9-0001', '{"lines":[{"lineNo":2,"articleId":"EX-01"}]}')), '^ERR 22023 \[kassa:article\]');
select zz.chk('B10 noma''lum statiya', zz.rq('U_ACC', zz.fb('ref-b10-001', '{"lines":[{"lineNo":2,"articleId":"EX-99"}]}')), '^ERR 22023 \[kassa:article\]');
select zz.chk('B11 statiya bo''sh', zz.rq('U_ACC', zz.fb('ref-b11-001', '{"lines":[{"lineNo":2,"articleId":""}]}')), '^ERR 22023 \[kassa:article\]');
select zz.chk('B12 hujjatda yo''q qator', zz.rq('U_ACC', zz.fb('ref-b12-001', '{"lines":[{"lineNo":9,"articleId":"EX-16"}]}')), '^ERR 22023 \[kassa:fix_line\]');
select zz.chk('B13 bir qator ikki marta', zz.rq('U_ACC', zz.fb('ref-b13-001', '{"lines":[{"lineNo":2,"articleId":"EX-16"},{"lineNo":2,"articleId":"EX-17"}]}')), '^ERR 22023 \[kassa:fix_line\]');
select zz.chk('B14 qator raqami noto''g''ri', zz.rq('U_ACC', zz.fb('ref-b14-001', '{"lines":[{"lineNo":"x","articleId":"EX-16"}]}')), '^ERR 22023 \[kassa:fix_line\]');
select zz.chk('B15 tomon turi mos emas (xodim)', zz.rq('U_ACC', zz.fb('ref-b15-001', '{"party":{"type":"employee","id":"staff:s1"}}')), '^ERR 22023 \[kassa:party\]');
select zz.chk('B15b tomon turi mos emas (bank — operatsiya tomon turlarida yo''q)', zz.rq('U_ACC', zz.fb('ref-b15b-01', '{"party":{"type":"bank","id":"cp3"}}')), '^ERR 22023 \[kassa:party\]');
select zz.chk('B16 bank — «kontragent» sifatida emas', zz.rq('U_ACC', zz.fb('ref-b16-001', '{"party":{"type":"counterparty","id":"cp3"}}')), '^ERR 22023 \[kassa:party\]');
select zz.chk('B17 faol emas kontragent', zz.rq('U_ACC', zz.fb('ref-b17-001', '{"party":{"type":"counterparty","id":"cp4"}}')), '^ERR 22023 \[kassa:party\]');
select zz.chk('B18 «boshqa» tomon nomi qisqa', zz.rq('U_ACC', zz.fb('ref-b18-001', '{"party":{"type":"other","name":"Ab"}}')), '^ERR 22023 \[kassa:party\]');
select zz.chk('B19 asos qisqa', zz.rq('U_ACC', zz.fb('ref-b19-001', '{"basis":"ab"}')), '^ERR 22023 \[kassa:basis\]');
select zz.chk('B20 kalit noto''g''ri', zz.rq('U_ACC', zz.fb('ab', '{"basis":"Yangi asos"}')), '^ERR 22023 \[kassa:bad_input\]');
select zz.chk('B21 qatorlar massiv emas', zz.rq('U_ACC', zz.fb('ref-b21-001', '{"lines":{"lineNo":2}}')), '^ERR 22023 \[kassa:bad_input\]');
select zz.chk('B22 xatolardan keyin dalolatnoma yo''q', (select count(*)::text from public.cash_doc_fixes), '^0$');

-- ---------- (C) oqim ----------
-- C1: buxgalter — 2-qator statiyasi (Boshqa → Xo'jalik vositalari), tomon (Ta'minotchi → Ijarachi), asos
select zz.put('r1', zz.rq('U_ACC', zz.fb('ref-c1-0001', '{"lines":[{"lineNo":2,"articleId":"EX-16"}],"party":{"type":"counterparty","id":"cp2","name":"e''tiborsiz"},"basis":"Ijara shartnomasi № 0-7, hisob-faktura № 0-12"}')));
select zz.put('fx1', zz.f(zz.get('r1'), 'id'));
select zz.chk('C1 so''rov yozildi (kutilmoqda)', zz.fx(zz.get('fx1')),
  '^pending:-:1=EX-32/9420,2=EX-16/2010:counterparty/cp2/Sinov Ijarachi:Ijara shartnomasi № 0-7, hisob-faktura № 0-12$');
select zz.chk('C1b oldingi holat — asl hujjat, so''ragan ismi',
  (select (f.before -> 'lines' -> 1 ->> 'articleId') || '/' || (f.before ->> 'partyId') || '/' || f."requestedByName" || '/' || coalesce(f."baseFixId", '-') || '/' || (f.before -> 'lines' -> 1 ->> 'amount')
     from public.cash_doc_fixes f where f.id = zz.get('fx1')), '^EX-49/cp1/Sinov Buxgalter/-/200000$');
select zz.chk('C2 shu kalit qayta — o''sha so''rov', zz.rq('U_ACC', zz.fb('ref-c1-0001', '{"lines":[{"lineNo":2,"articleId":" EX-16 "}],"party":{"type":"counterparty","id":"cp2","name":"e''tiborsiz"},"basis":" Ijara shartnomasi № 0-7, hisob-faktura № 0-12"}')),
  '"dup": true');
select zz.chk('C2b dup — o''sha id', (zz.f(zz.rq('U_ACC', zz.fb('ref-c1-0001', '{"lines":[{"lineNo":2,"articleId":"EX-16"}],"party":{"type":"counterparty","id":"cp2","name":"e''tiborsiz"},"basis":"Ijara shartnomasi № 0-7, hisob-faktura № 0-12"}')), 'id') = zz.get('fx1'))::text, '^true$');
select zz.chk('C3 shu kalit, boshqa mazmun — rad', zz.rq('U_ACC', zz.fb('ref-c1-0001', '{"lines":[{"lineNo":2,"articleId":"EX-17"}]}')), '^ERR 22023 \[kassa:ref_mismatch\]');
select zz.chk('C3b shu kalit, boshqa xodim — rad', zz.rq('U_FM', zz.fb('ref-c1-0001', '{"lines":[{"lineNo":2,"articleId":"EX-16"}],"party":{"type":"counterparty","id":"cp2","name":"e''tiborsiz"},"basis":"Ijara shartnomasi № 0-7, hisob-faktura № 0-12"}')), '^ERR 22023 \[kassa:ref_mismatch\]');
select zz.chk('C4 kutilayotgan so''rov bor — ikkinchisi yo''q', zz.rq('U_FM', zz.fb('ref-c4-0001', '{"basis":"Boshqa asos matni"}')), '^ERR P0001 \[kassa:fix_pending\]');
select zz.chk('C5 hujjat javobi: kutilmoqda, amaldagi holat yo''q',
  (select (j -> 'fixes' -> 0 ->> 'status') || '/' || jsonb_array_length(j -> 'fixes') || '/' || coalesce(j ->> 'eff', 'null')
     from (select app.kassa_doc_json('f1') as j) x), '^pending/1/null$');
select zz.chk('C6 Moliya menejeri qaror qilmaydi', zz.dc('U_FM', zz.get('fx1'), true), '^ERR 42501 \[kassa:fix_rights\]');
select zz.chk('C6b buxgalter ham', zz.dc('U_ACC', zz.get('fx1'), false, 'yo''q'), '^ERR 42501 \[kassa:fix_rights\]');
select zz.put('d1', zz.dc('U_DIR', zz.get('fx1'), true, 'Roziman'));
select zz.chk('C7 Direktor tasdiqladi: raqam 1, sana — bugun',
  (select f.status || '/' || f.no || '/' || f.year || '/' || f."actDay" || '/' || f."decidedByName" || '/' || f."decisionNote" from public.cash_doc_fixes f where f.id = zz.get('fx1')),
  '^approved/1/2027/2027-02-10/Sinov Direktor/Roziman$');
select zz.chk('C7b javob: hujjat qisqachasi', (zz.js(zz.get('d1')) #>> '{doc,no}') || '/' || (zz.js(zz.get('d1')) ->> 'dup'), '^3/false$');
select zz.chk('C8 qayta tasdiq — dup', zz.dc('U_DIR', zz.get('fx1'), true), '"dup": true');
select zz.chk('C8b tasdiqdan keyin rad — yo''q', zz.dc('U_DIR', zz.get('fx1'), false, 'kech'), '^ERR P0001 \[kassa:bad_status\]');
select zz.chk('C8c tasdiqdan keyin bekor — yo''q', zz.cn('U_ACC', zz.get('fx1'), 'kech qoldi'), '^ERR P0001 \[kassa:bad_status\]');
select zz.chk('C9 «Buxgalteriya»: 2-qator — yangi statiya, toifa, kontragent, izoh',
  (select e."articleId" || '|' || e.category || '|' || e."counterpartyId" || '|' || e.note from public.expenses e where e.id = 'kx_f1_2'),
  '^EX-16\|[^|]+\|cp2\|.*Sinov Ijarachi — Ijara shartnomasi № 0-7, hisob-faktura № 0-12 \(KO-2 № 3; QT-1\)$');
select zz.chk('C9b «Buxgalteriya»: 1-qator — statiya o''sha, kontragent yangi',
  (select e."articleId" || '|' || e."counterpartyId" || '|' || trim_scale(e.amount) || '|' || e.date from public.expenses e where e.id = 'kx_f1_1'), '^EX-32\|cp2\|400000\|2027-01-05$');
select zz.chk('C9c toifa statiya qoidasidan (app.kassa_exp_category)',
  (select (e.category = k.o_category)::text from public.expenses e cross join lateral app.kassa_exp_category('EX-16') k where e.id = 'kx_f1_2'), '^true$');
select zz.chk('C10 asl hujjat va qatorlari o''zgarmadi',
  (select c."partyId" || '/' || c."partyName" || '/' || c.basis || '/' || trim_scale(c.amount) || '/' || c."businessDay" || '/' || c.no
          || '/' || (select string_agg(l."articleId" || '=' || l.debit, ',' order by l."lineNo") from public.cash_doc_lines l where l."docId" = c.id)
     from public.cash_docs c where c.id = 'f1'), '^cp1/Sinov Ta''minotchi/Sinov xarid — hisob-faktura № 0-12/600000/2027-01-05/3/EX-32=9420,EX-49=9430$');
select zz.chk('C11 hujjat javobi: amaldagi holat (QT-1)',
  (select (j #>> '{eff,partyId}') || '/' || (j #>> '{eff,fixNo}') || '/' || (j #>> '{eff,lines,1,articleId}') || '/' || (j -> 'fixes' -> 0 ->> 'status') || '/' || (j -> 'fixes' -> 0 ->> 'no')
     from (select app.kassa_doc_json('f1') as j) x), '^cp2/1/EX-16/approved/1$');
select zz.chk('C12 statiya matritsasi — amaldagi statiya bo''yicha', zz.mx('U_ACC', 'main', '2027-01'), '^EX-16=200000,EX-32=450000,OP-09=50000$');
select zz.chk('C13 ko''chirma: Ijarachida hujjat (QT-1 belgisi, yangi statiya va asos)', zz.st('U_ACC', 'cp2'),
  '^KO-2 № 3 \(QT-1\):0:600000:EX-16\+EX-32:Ijara shartnomasi № 0-7, hisob-faktura № 0-12$');
select zz.chk('C13b ko''chirma: Ta''minotchida endi yo''q', zz.st('U_ACC', 'cp1'), '^KO-1 № 1:10000:0:IN-06:Ortiqcha to''lov qaytdi,KO-2 № 5:0:20000:EX-32:Bugungi xarid$');
-- C14: ikkinchi dalolatnoma (Moliya menejeri): 1-qator — asosiy vosita (0820); oldingi holat — 1-dalolatnomadan keyingi
select zz.put('r2', zz.rq('U_FM', zz.fb('ref-c14-001', '{"lines":[{"lineNo":1,"articleId":"OP-18"}],"reason":"Printer — asosiy vosita (0820), kanselyariya emas"}')));
select zz.put('fx2', zz.f(zz.get('r2'), 'id'));
select zz.chk('C14 ikkinchi so''rov: oldingi holat = QT-1 holati',
  (select ((f.before - 'fixId') = (select x.after from public.cash_doc_fixes x where x.id = zz.get('fx1')))::text || '/' || (f."baseFixId" = zz.get('fx1'))::text
     from public.cash_doc_fixes f where f.id = zz.get('fx2')), '^true/true$');
select zz.put('d2', zz.dc('U_DIR', zz.get('fx2'), true));
select zz.chk('C14b tasdiq: raqam 2, amaldagi — ikkala tuzatish', zz.fx(zz.get('fx2')),
  '^approved:2:1=OP-18/0820,2=EX-16/2010:counterparty/cp2/Sinov Ijarachi:Ijara shartnomasi № 0-7, hisob-faktura № 0-12$');
select zz.chk('C14c matritsa — oxirgi dalolatnoma bo''yicha', zz.mx('U_ACC', 'main', '2027-01'), '^EX-16=200000,EX-32=50000,OP-09=50000,OP-18=400000$');
select zz.chk('C14d hujjat javobi: amaldagi — QT-2', (select (j #>> '{eff,fixNo}') || '/' || jsonb_array_length(j -> 'fixes') from (select app.kassa_doc_json('f1') as j) x), '^2/2$');
-- C15: rad etish
select zz.put('r3', zz.rq('U_ACC', zz.fb('ref-c15-001', '{"docId":"f2","party":{"type":"counterparty","id":"cp1"},"basis":"Chek № 0-55"}')));
select zz.put('fx3', zz.f(zz.get('r3'), 'id'));
select zz.chk('C15 asossiz xarid: «boshqa» → kontragent so''rovi', zz.fx(zz.get('fx3')), '^pending:-:1=EX-32/9420:counterparty/cp1/Sinov Ta''minotchi:Chek № 0-55$');
select zz.chk('C15b rad etish — sababsiz yo''q', zz.dc('U_DIR', zz.get('fx3'), false, ' '), '^ERR 22023 \[kassa:fix_note\]');
select zz.put('d3', zz.dc('U_DIR', zz.get('fx3'), false, 'Chek nusxasi yo''q'));
select zz.chk('C15c rad etildi: raqamsiz, amaldagi holat — asl',
  (select f.status || '/' || coalesce(f.no::text, '-') || '/' || f."decisionNote" || '/' || coalesce(app.kassa_eff_doc('f2')::text, 'null') from public.cash_doc_fixes f where f.id = zz.get('fx3')),
  '^rejected/-/Chek nusxasi yo''q/null$');
select zz.chk('C15d rad etilgandan keyin «Buxgalteriya» o''zgarmadi', (select e."counterpartyId" is null and e.note = 'asl izoh (KO-2 № 4)' from public.expenses e where e.id = 'kx_f2_1')::text, '^true$');
-- C16: bekor qilish
select zz.put('r4', zz.rq('U_ACC', zz.fb('ref-c16-001', '{"docId":"f2","party":{"type":"counterparty","id":"cp2"}}')));
select zz.put('fx4', zz.f(zz.get('r4'), 'id'));
select zz.chk('C16 boshqa 2-ro''yxat xodimi bekor qilmaydi', zz.cn('U_FM', zz.get('fx4'), 'kerak emas'), '^ERR 42501 \[kassa:fix_rights\]');
select zz.chk('C16b kassir ham', zz.cn('U_KAS', zz.get('fx4'), 'kerak emas'), '^ERR 42501 \[kassa:fix_rights\]');
select zz.chk('C16c sababsiz — yo''q', zz.cn('U_ACC', zz.get('fx4'), ''), '^ERR 22023 \[kassa:fix_note\]');
set local session_replication_role = replica;
update public.users set role = 'kassir' where id = 'U_ACC';
set local session_replication_role = origin;
select zz.chk('C16i so''ragan, lekin endi 2-ro''yxatda emas — bekor qilmaydi', zz.cn('U_ACC', zz.get('fx4'), 'Xato tomon'), '^ERR 42501 \[kassa:fix_rights\]');
set local session_replication_role = replica;
update public.users set role = 'accountant' where id = 'U_ACC';
set local session_replication_role = origin;
select zz.put('c4', zz.cn('U_ACC', zz.get('fx4'), 'Xato tomon tanlandi'));
select zz.chk('C16d so''ragan bekor qildi', (select f.status || '/' || f."cancelledBy" || '/' || f."cancelReason" from public.cash_doc_fixes f where f.id = zz.get('fx4')), '^cancelled/U_ACC/Xato tomon tanlandi$');
select zz.chk('C16e qayta bekor — dup', zz.cn('U_ACC', zz.get('fx4'), 'Xato tomon tanlandi'), '"dup": true');
select zz.chk('C16f bekor qilingandan keyin tasdiq — yo''q', zz.dc('U_DIR', zz.get('fx4'), true), '^ERR P0001 \[kassa:bad_status\]');
select zz.put('r5', zz.rq('U_FM', zz.fb('ref-c16-002', '{"docId":"f2","party":{"type":"other","name":"Sinov Boshqa Shaxs"},"reason":"Oluvchi ismi xato yozilgan"}')));
select zz.put('fx5', zz.f(zz.get('r5'), 'id'));
select zz.chk('C16g Direktor ham bekor qiladi', zz.f(zz.cn('U_DIR', zz.get('fx5'), 'Kerak emas'), 'status'), '^cancelled$');
select zz.chk('C16h «boshqa» tomon nomi — so''rovda', (select (f.after ->> 'partyName') || '/' || coalesce(f.after ->> 'partyId', 'null') from public.cash_doc_fixes f where f.id = zz.get('fx5')), '^Sinov Boshqa Shaxs/null$');
-- C17: tasdiqda qayta tekshiruv — kun qayta ochilgan
select zz.put('r6', zz.rq('U_ACC', zz.fb('ref-c17-001', '{"docId":"f8","lines":[{"lineNo":1,"articleId":"EX-16"}]}')));
select zz.put('fx6', zz.f(zz.get('r6'), 'id'));
set local session_replication_role = replica;
update public.cash_days set status = 'open', receipts = null, payouts = null, closing = null, counted = null, hash = null, "closedBy" = null, "closedAt" = null where id = 'cd_sinov_2027-01-05';
set local session_replication_role = origin;
select zz.chk('C17 kun qayta ochilgan — tasdiq yo''q', zz.dc('U_DIR', zz.get('fx6'), true), '^ERR P0001 \[kassa:fix_day_open\]');
set local session_replication_role = replica;
update public.cash_days set status = 'closed', receipts = 0, payouts = 30000, closing = 70000, counted = 70000, hash = 'hs', "closedBy" = 'U_KAS', "closedAt" = '2027-01-05 18:00+05' where id = 'cd_sinov_2027-01-05';
set local session_replication_role = origin;
select zz.chk('C17b kun yopilgach — tasdiq; sinov kassasi o''z raqami bilan', zz.f(zz.dc('U_DIR', zz.get('fx6'), true), 'no') || '/' || (select f.desk from public.cash_doc_fixes f where f.id = zz.get('fx6')), '^1/sinov$');
-- C18: tasdiqda qayta tekshiruv — davr yopilgan
select zz.put('r7', zz.rq('U_FM', zz.fb('ref-c18-001', '{"docId":"f2","lines":[{"lineNo":1,"articleId":"EX-14"}],"reason":"Telefon to''lovi — internet va telefon"}')));
select zz.put('fx7', zz.f(zz.get('r7'), 'id'));
set local session_replication_role = replica;
update public.fin_org set "lockedThrough" = '2027-01-31' where id = 'main';
set local session_replication_role = origin;
select zz.chk('C18 davr yopilgan — tasdiq yo''q', zz.dc('U_DIR', zz.get('fx7'), true), '^ERR 42501 \[fin:locked\]');
set local session_replication_role = replica;
update public.fin_org set "lockedThrough" = '2026-12-31' where id = 'main';
update public.fin_articles set "accountCode" = '9430' where id = 'EX-14';
set local session_replication_role = origin;
select zz.chk('C19 statiya hisobvarag''i o''zgargan — tasdiq yo''q', zz.dc('U_DIR', zz.get('fx7'), true), '^ERR P0001 \[kassa:fix_stale\]');
set local session_replication_role = replica;
update public.fin_articles set "accountCode" = '9420' where id = 'EX-14';
set local session_replication_role = origin;
select zz.chk('C19b qaytgach — tasdiq (raqam 3)', zz.f(zz.dc('U_DIR', zz.get('fx7'), true), 'no'), '^3$');
select zz.put('r8', zz.rq('U_FM', zz.fb('ref-c20-001', '{"lines":[{"lineNo":2,"articleId":"EX-17"}],"reason":"Qo''riqlash xizmati — xo''jalik emas"}')));
select zz.put('fx8', zz.f(zz.get('r8'), 'id'));
set local session_replication_role = replica;
update public.fin_articles set active = false where id = 'EX-17';
set local session_replication_role = origin;
select zz.chk('C20 statiya faolsizlantirilgan — tasdiq yo''q', zz.dc('U_DIR', zz.get('fx8'), true), '^ERR 22023 \[kassa:article\]');
set local session_replication_role = replica;
update public.fin_articles set active = true where id = 'EX-17';
set local session_replication_role = origin;

-- ---------- (D) himoya ----------
select zz.chk('D1 tasdiqlangan dalolatnoma o''zgarmaydi', zz.ownf(format($q$update public.cash_doc_fixes set "decisionNote" = 'x' where id = %L returning id$q$, zz.get('fx1'))), '^ERR 42501 \[kassa:immutable\]');
select zz.chk('D2 kutilayotgan so''rov mazmuni o''zgarmaydi', zz.ownf(format($q$update public.cash_doc_fixes set reason = 'boshqa sabab' where id = %L returning id$q$, zz.get('fx8'))), '^ERR 42501 \[kassa:immutable\]');
select zz.chk('D2b qaror bilan birga mazmun o''zgarmaydi', zz.ownf(format($q$update public.cash_doc_fixes set status = 'cancelled', "cancelledAt" = now(), "cancelledBy" = 'U_FM', "cancelReason" = 'xxx', reason = 'boshqa sabab' where id = %L returning id$q$, zz.get('fx8'))), '^ERR 42501 \[kassa:immutable\] Dalolatnoma mazmuni');
select zz.chk('D3 o''chirilmaydi (kutilayotgani ham, bayroqsiz ham)', zz.ownf(format($q$delete from public.cash_doc_fixes where id = %L returning id$q$, zz.get('fx8')))
  || ' | ' || zz.ownf(format($q$delete from public.cash_doc_fixes where id = %L returning id$q$, zz.get('fx3')), false),
  '^ERR 42501 \[kassa:immutable\] Qayta tasnif dalolatnomasi o''chirilmaydi \| ERR 42501 \[kassa:immutable\] Qayta tasnif dalolatnomasi o''chirilmaydi$');
select zz.chk('D4 bayroqsiz yozish — yo''q', zz.ownf(format($q$update public.cash_doc_fixes set status = 'cancelled', "cancelledAt" = now() where id = %L returning id$q$, zz.get('fx8')), false), '^ERR 42501 \[kassa:rpc_only\]');
select zz.chk('D5 tasdiqlangan holda yaratilmaydi',
  zz.ownf($q$insert into public.cash_doc_fixes (id, "docId", desk, status, year, no, "actDay", reason, before, after, "clientRef", "reqHash", "requestedBy", "decidedBy", "decidedAt")
             values ('fz', 'f2', 'main', 'approved', 2027, 9, '2027-02-10', 'xxxxxx', '{}', '{}', 'ref-fz-0001', 'h', 'U_ACC', 'U_DIR', now()) returning id$q$), '^ERR 22023 \[kassa:bad_doc\]');
select zz.chk('D6 bitta hujjatda ikkinchi kutilayotgan so''rov — yo''q (indeks)',
  zz.ownf($q$insert into public.cash_doc_fixes (id, "docId", desk, status, reason, before, after, "clientRef", "reqHash", "requestedBy")
             values ('fy', 'f1', 'main', 'pending', 'xxxxxx', '{}', '{}', 'ref-fy-0001', 'h', 'U_ACC') returning id$q$), '^ERR 23505');
select zz.chk('D7 o''z so''rovi bo''yicha qaror — cheklov',
  zz.ownf(format($q$update public.cash_doc_fixes set status = 'rejected', "decidedBy" = "requestedBy", "decidedAt" = now(), "decisionNote" = 'yo''q' where id = %L returning id$q$, zz.get('fx8'))), '^ERR 23514');
select zz.chk('D8 hisoblagich: main — 3, sinov — 1 (FIX seriyasi)',
  (select string_agg(c.desk || '=' || c."lastNo", ',' order by c.desk) from public.doc_counters c where c.series = 'FIX' and c.year = 2027), '^main=3,sinov=1$');
select zz.chk('D9 o''zgarishlar tarixi: holat o''zgarishlari yozilgan',
  (select count(*) from public.change_log l where l.tbl = 'cash_doc_fixes' and l.op = 'UPDATE' and l.changes ? 'status')::text, '^[6-9]$');
select zz.chk('D10 RLS: buxgalter jadvalni o''qiydi, o''qituvchi — yo''q',
  zz.as('U_ACC', $q$select count(*)::text from public.cash_doc_fixes$q$) || '/' || zz.as('U_TCH', $q$select count(*)::text from public.cash_doc_fixes$q$), '^8/0$');

-- ---------- (E) ro'yxat, bitta dalolatnoma, sonlar ----------
select zz.chk('E1 kutilayotganlar (main)', (zz.as('U_DIR', $q$select (select string_agg(x ->> 'id', ',') from jsonb_array_elements(public.kassa_fix_list('main', 'pending') -> 'fixes') x)$q$) = zz.get('fx8'))::text, '^true$');
select zz.chk('E2 hujjat bo''yicha hammasi (tartibda)', zz.as('U_FM', $q$select (select string_agg((x ->> 'status') || coalesce('#' || (x ->> 'no'), ''), ',') from jsonb_array_elements(public.kassa_fix_list('main', 'all', 'f1') -> 'fixes') x)$q$),
  '^approved#1,approved#2,pending$');
select zz.chk('E3 barcha (main) — eng yangisi birinchi', zz.as('U_ACC', $q$select jsonb_array_length(public.kassa_fix_list('main', 'all') -> 'fixes')::text$q$), '^7$');
select zz.chk('E4 bitta dalolatnoma: hujjat raqami va sana', zz.as('U_ACC', format($q$select (public.kassa_fix_get(%L) #>> '{fix,doc,no}') || '/' || (public.kassa_fix_get(%L) #>> '{fix,doc,businessDay}') || '/' || (public.kassa_fix_get(%L) ->> 'isTest')$q$, zz.get('fx1'), zz.get('fx1'), zz.get('fx1'))),
  '^3/2027-01-05/false$');
select zz.chk('E5 noto''g''ri holat filtri', zz.as('U_ACC', $q$select public.kassa_fix_list('main', 'x')::text$q$), '^ERR 22023 \[kassa:bad_input\]');
select zz.chk('E6 topilmadi', zz.as('U_ACC', $q$select public.kassa_fix_get('yoq')::text$q$), '^ERR 22023 \[kassa:not_found\]');
select zz.chk('E7 nazorat ro''yxati: kutilmoqda 1, 30 kunda tasdiqlangan 3', zz.as('U_ACC', $q$select (public.kassa_checks('main') ->> 'fixPending') || '/' || (public.kassa_checks('main') ->> 'fixes30')$q$), '^1/3$');
select zz.chk('E8 kassa holati: Direktorga 1, buxgalterga 0', zz.as('U_DIR', $q$select public.kassa_state('main') #>> '{pending,fixToApprove}'$q$) || '/' || zz.as('U_ACC', $q$select public.kassa_state('main') #>> '{pending,fixToApprove}'$q$), '^1/0$');
select zz.chk('E10 hujjat javobida rad etilgan / bekor qilinganlar yo''q (f2: faqat tasdiqlangan QT-3)',
  (select jsonb_array_length(j -> 'fixes') || '/' || (j -> 'fixes' -> 0 ->> 'no') || '/' || (j #>> '{eff,fixNo}') from (select app.kassa_doc_json('f2') as j) x), '^1/3/3$');
select zz.chk('E9 kassa_doc_get: hujjatda tuzatishlar va amaldagi holat', zz.as('U_KAS', $q$select (public.kassa_doc_get('f1') #>> '{doc,eff,fixNo}') || '/' || jsonb_array_length(public.kassa_doc_get('f1') #> '{doc,fixes}')$q$), '^2/3$');

-- ---------- Natija ----------
select (case when ok then 'PASS' else 'FAIL' end) || ' ' || name || case when ok then '' else E'\n     got: ' || coalesce(got, '<null>') || E'\n     pat: ' || pat end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
