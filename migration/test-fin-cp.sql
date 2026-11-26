-- =====================================================================
-- test-fin-cp.sql — moliya ish rejasi 2-bosqichi, F2.2 (fin-core.sql kontragent ustunlari, fin-cp.sql) sinovi: kontragent kartasi
--   to'liq va RP-10 kontragent ko'chirmasi.
--   (A) huquqlar: kim kartani qo'shadi / o'zgartiradi, kim ko'chirmani ko'radi; jadvalga to'g'ridan-to'g'ri yozish va ichki funksiyalar yopiq;
--   (B) kiritish tekshiruvlari: tur, nom, STIR (9 raqam), hisob raqami (20), MFO (5), bank nomi, shartnoma (raqami + sanasi, muddati), izoh;
--   (C) takror va bir vaqtda tahrirlash: shu karta (dup), shu STIR (ogohlantirish, dupOk), boshqa karta nomiga o'tkazish, versiya (rev);
--   (D) tur tasdig'i va eski fin_counterparty_save bilan moslik (rekvizitlar saqlanadi, STIR tekshiruvi, eski noto'g'ri STIR);
--   (E) RP-10: kassa orderlari, xarajat hujjatlari, eski yozuvlar — davr boshigacha, davr, davr oxirigacha; nima kirmaydi
--       (bekor qilingan, sinov kassasi, pul berilmagan, kassadan ko'chgan qator); davr tekshiruvi; faylda FD-28 bo'yicha ismsiz;
--   (F) o'zgarishlar jurnali va jadval cheklovlari.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-fin-cp.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov nomlari, STIR, hisob raqamlari to'qima (0 bilan boshlanadi — haqiqiy
--   emas). Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.fin_counterparties) or exists (select 1 from public.cash_docs) then
    raise exception 'test-fin-cp.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
-- Jadval egasi sifatida (RLS va huquqlar chetlab o'tiladi) — jadval cheklovlarini sinash uchun
create or replace function zz.own(p_q text) returns text language plpgsql as $$
declare r text;
begin
  begin
    execute p_q into r;
  exception when others then
    r := 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
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
-- karta: kontragentni saqlash (fin_cp_save)
create or replace function zz.cs(p_uid text, p jsonb) returns text language sql as $$
  select zz.as(p_uid, format('select public.fin_cp_save(%L::jsonb)::text', p::text)) $$;
-- eski funksiya (KO / xarajat oynasidagi «+ yangi»)
create or replace function zz.old(p_uid text, p_id text, p_kind text, p_name text, p_stir text, p_active boolean default true) returns text language sql as $$
  select zz.as(p_uid, format('select public.fin_counterparty_save(%L, %L, %L, %L, %L, %L)::text', p_id, p_kind, p_name, p_stir, 'izoh', p_active)) $$;
-- ko'chirma
create or replace function zz.st(p_uid text, p_id text, p_from text, p_to text, p_file boolean default false) returns text language sql as $$
  select zz.as(p_uid, format('select public.fin_cp_statement(%L, %L::date, %L::date, %L)::text', p_id, p_from, p_to, p_file)) $$;
create or replace function zz.id(p text) returns text language sql as $$ select zz.js(p) ->> 'id' $$;
-- ko'chirma qatorlari: sana:manba:kalit:olindi:berildi (tartibda)
create or replace function zz.rows(p text) returns text language sql as $$
  select coalesce(string_agg((r ->> 'day') || ':' || (r ->> 'src') || ':' || (r ->> 'ref') || ':' || trim_scale((r ->> 'in')::numeric) || ':'
                             || trim_scale((r ->> 'out')::numeric), ',' order by o), '-')
    from jsonb_array_elements(zz.js(p) -> 'rows') with ordinality as t(r, o) $$;
create or replace function zz.sums(p text) returns text language sql as $$
  select trim_scale((zz.js(p) #>> '{opening,in}')::numeric) || '/' || trim_scale((zz.js(p) #>> '{opening,out}')::numeric) || ' | '
      || trim_scale((zz.js(p) #>> '{totals,in}')::numeric) || '/' || trim_scale((zz.js(p) #>> '{totals,out}')::numeric) || '/' || (zz.js(p) #>> '{totals,n}') || ' | '
      || trim_scale((zz.js(p) #>> '{closing,in}')::numeric) || '/' || trim_scale((zz.js(p) #>> '{closing,out}')::numeric) $$;
-- karta maydonlari
create or replace function zz.card(p_id text) returns text language sql as $$
  select c.kind || ':' || c.name || ':' || c.stir || ':' || c.account || ':' || c.mfo || ':' || c."bankName" || ':' || c."contractNo" || ':'
      || coalesce(c."contractDate"::text, '-') || ':' || coalesce(c."contractUntil"::text, '-') || ':' || c.active || ':r' || c.rev
    from public.fin_counterparties c where c.id = p_id $$;
create or replace function zz.base(o jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object('kind', 'supplier', 'name', 'Sinov Yetkazuvchi', 'stir', '000000201', 'account', '00000000000000000201',
                            'mfo', '00201', 'bankName', 'Sinov bank filiali', 'contractNo', '№ 7', 'contractDate', '2027-01-15',
                            'contractUntil', '2027-12-31', 'note', 'sinov') || o $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'), ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]'),
  ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.fin_counterparties (id, kind, name, stir, active, "createdAt") values
  ('cp1', 'supplier', 'Sinov Ta''minotchi', '000000101', true, '2027-01-01 09:00+05'),
  ('cp2', 'bank', 'Sinov Bank', '', true, '2027-01-01 09:01+05'),
  ('cp3', 'person', 'Sinov YaTT', '', true, '2027-01-01 09:02+05'),
  ('cp4', 'supplier', 'Eski Sinov', '12345678', true, '2027-01-01 09:03+05'),
  ('cp5', 'supplier', 'Nofaol Sinov', '000000101', false, '2027-01-01 09:04+05');
-- kassa orderlari (main — asosiy kassa, sinov — sinov kassasi)
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "partyType", "partyId", "partyName", basis,
                              "clientRef", "postedAt", "createdAt") values
  ('d1', 'main', 'KO2', 'out_expense', 'posted', 2027, 3, '2027-01-05', 'cd_main_2027-01-05', 500000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Sinov xarid', 'r-d1', '2027-01-05 11:00+05', '2027-01-05 10:00+05'),
  ('d2', 'main', 'KO1', 'in_other', 'posted', 2027, 4, '2027-01-06', 'cd_main_2027-01-06', 100000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Ortiqcha to''lov qaytdi', 'r-d2', '2027-01-06 11:00+05', '2027-01-06 10:00+05'),
  ('d3', 'main', 'KO2', 'out_expense', 'void', 2027, 5, '2027-01-06', 'cd_main_2027-01-06', 70000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'bekor', 'r-d3', '2027-01-06 12:00+05', '2027-01-06 10:00+05'),
  ('d4', 'sinov', 'KO2', 'out_expense', 'posted', 2027, 1, '2027-01-06', 'cd_sinov_2027-01-06', 80000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'sinov kassasi', 'r-d4', '2027-01-06 13:00+05', '2027-01-06 10:00+05'),
  ('d5', 'main', 'KO2', 'out_expense', 'approved', null, null, null, null, 90000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'pul berilmagan', 'r-d5', null, '2027-01-07 10:00+05'),
  ('d6', 'main', 'KO2', 'out_bank', 'posted', 2027, 6, '2027-01-07', 'cd_main_2027-01-07', 2000000, 'bank', 'cp2', 'Sinov Bank', 'Tushum bankka', 'r-d6', '2027-01-07 17:00+05', '2027-01-07 16:00+05'),
  ('d7', 'main', 'KO2', 'out_expense', 'posted', 2026, 40, '2026-12-20', 'cd_main_2026-12-20', 300000, 'counterparty', 'cp1', 'Sinov Ta''minotchi', 'Dekabr xaridi', 'r-d7', '2026-12-20 11:00+05', '2026-12-20 10:00+05'),
  ('d8', 'main', 'KO2', 'out_expense', 'posted', 2027, 7, '2027-01-07', 'cd_main_2027-01-07', 40000, 'counterparty', 'cp3', 'Sinov YaTT', 'Xizmat — Sinov Ismli', 'r-d8', '2027-01-07 12:00+05', '2027-01-07 10:00+05');
update public.cash_docs set "voidedAt" = '2027-01-06 15:00+05', "voidReason" = 'sinov' where id = 'd3';
insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash) values
  ('l1', 'd1', 1, '9420', '5010', 500000, 'EX-32', true), ('l2', 'd2', 1, '5010', '9390', 100000, 'IN-06', true),
  ('l6', 'd6', 1, '5710', '5010', 2000000, 'OP-02', true), ('l7', 'd7', 1, '9420', '5010', 300000, 'EX-32', true),
  ('l8', 'd8', 1, '9420', '5010', 40000, 'EX-49', true);
-- «Buxgalteriya» xarajat hujjatlari
insert into public.fin_exp_docs (id, origin, method, date, "counterpartyId", "partyName", "docNo", "docDate", note, amount, lines, status, "clientRef", "createdAt", "voidReason", "voidedAt") values
  ('x1', 'form', 'bank', '2027-01-08', 'cp1', 'Sinov Ta''minotchi', '145', '2027-01-07', 'Yanvar kommunal', 1500000,
   '[{"lineNo":1,"articleId":"EX-11","amount":1200000,"note":""},{"lineNo":2,"articleId":"EX-13","amount":300000,"note":""}]', 'posted', 'ref-x1-00000001', '2027-01-08 10:00+05', null, null),
  ('x2', 'form', 'card', '2027-01-08', 'cp1', 'Sinov Ta''minotchi', '', null, 'bekor', 99000, '[{"lineNo":1,"articleId":"EX-32","amount":99000}]', 'void', 'ref-x2-00000001', '2027-01-08 11:00+05', 'sinov', '2027-01-08 13:00+05'),
  ('x3', 'legacy', 'bank', '2027-01-08', 'cp1', 'Sinov Ta''minotchi', '', null, 'eski', 77000, '[{"lineNo":1,"articleId":"EX-10","amount":77000}]', 'void', 'legacy:e_x', '2027-01-08 12:00+05', 'sinov', '2027-01-08 13:00+05'),
  ('x4', 'form', 'bank', '2027-03-01', 'cp1', 'Sinov Ta''minotchi', '200', null, 'Mart', 600000, '[{"lineNo":1,"articleId":"EX-11","amount":600000}]', 'posted', 'ref-x4-00000001', '2027-03-01 10:00+05', null, null);
insert into public.expenses (id, date, month, category, amount, note, method, "articleId", "counterpartyId", "cashDocId", "expDocId", "createdAt") values
  ('e1', '2027-1-9', '2027-01', 'Ijara', 250000, 'Ijara (eski yozuv)', 'bank', 'EX-10', 'cp1', null, null, '2027-01-09 10:00+05'),
  ('kx_d1_1', '2027-01-05', '2027-01', 'Kanselyariya', 500000, 'KO-2 dan ko''chgan', 'cash', 'EX-32', 'cp1', 'd1', null, '2027-01-05 11:00+05'),
  ('x1_1', '2027-01-08', '2027-01', 'Kommunal', 1200000, 'hujjat qatori', 'bank', 'EX-11', 'cp1', null, 'x1', '2027-01-08 10:00+05'),
  ('x1_2', '2027-01-08', '2027-01', 'Boshqa', 300000, 'hujjat qatori', 'bank', 'EX-13', 'cp1', null, 'x1', '2027-01-08 10:00+05'),
  ('e4', 'xx', '2027-01', 'Boshqa', 10000, 'sanasi noto''g''ri', 'card', null, 'cp1', null, null, '2027-01-20 10:00+05'),
  ('e5', '2027-02-31', '', 'Boshqa', 20000, 'sanasi mavjud emas', null, 'EX-49', 'cp1', null, null, '2027-01-15 10:00+05');
set local session_replication_role = origin;
select zz.clock('2027-02-10 10:00+05');

-- ---------- (A) huquqlar ----------
select zz.chk('A1 karta: anon — funksiya yopiq; o''qituvchi — rad; kassir yangi kartani qo''shadi, mavjudini o''zgartira olmaydi',
  zz.cs(null, zz.base()) || ' | ' || zz.cs('U_TCH', zz.base()) || ' | '
  || coalesce(zz.js(zz.cs('U_KAS', zz.base('{"name":"Kassir qo''shgan","stir":"000000301","account":"","mfo":"","contractNo":"","contractDate":"","contractUntil":""}'::jsonb))) ->> 'createdBy', 'X')
  || ' | ' || zz.cs('U_KAS', zz.base('{"id":"cp2","rev":0,"kind":"bank","name":"Sinov Bank","stir":""}'::jsonb)),
  '^ERR 42501 .*permission denied.* \| ERR 42501 \[fin:cp_rights\].* \| U_KAS \| ERR 42501 \[fin:cp_rights\]');
select zz.chk('A2 ko''chirma: anon — yopiq; o''qituvchi va kassir — rad; Moliya menejeri, buxgalter, Direktor — ko''radi',
  zz.st(null, 'cp1', '2027-01-01', '2027-01-31') || ' | ' || zz.st('U_TCH', 'cp1', '2027-01-01', '2027-01-31') || ' | '
  || zz.st('U_KAS', 'cp1', '2027-01-01', '2027-01-31') || ' | ' || (zz.js(zz.st('U_FM', 'cp1', '2027-01-01', '2027-01-31')) #>> '{cp,id}') || '/'
  || (zz.js(zz.st('U_ACC', 'cp1', '2027-01-01', '2027-01-31')) #>> '{cp,id}') || '/' || (zz.js(zz.st('U_DIR', 'cp1', '2027-01-01', '2027-01-31')) #>> '{cp,id}'),
  '^ERR 42501 .*permission denied.* \| ERR 42501 \[fin:cp_rights\].* \| ERR 42501 \[fin:cp_rights\].* \| cp1/cp1/cp1$');
select zz.chk('A3 jadvalga to''g''ridan-to''g''ri yozib bo''lmaydi (Direktor ham); o''qish — kassa rollari (kassir ham), o''qituvchi — yo''q',
  zz.as('U_DIR', $q$with x as (update public.fin_counterparties set account = '00000000000000000999' where id = 'cp1' returning id) select count(*)::text from x$q$)
  || ' | ' || zz.as('U_KAS', $q$select count(*)::text from public.fin_counterparties$q$) || ' | ' || zz.as('U_TCH', $q$select count(*)::text from public.fin_counterparties$q$),
  '^ERR 42501 .*permission denied.* \| 6 \| (0|ERR 42501.*)$');
select zz.chk('A4 ichki yordamchilar mijozga yopiq',
  zz.as('U_DIR', $q$select app.fin_cp_digits('1 2')$q$) || ' | ' || zz.as('U_FM', $q$select app.fin_cp_stir_check('1', null)::text$q$) || ' | '
  || zz.as('U_FM', $q$select app.fin_cp_day('2027-01-01')::text$q$) || ' | ' || zz.as('U_FM', $q$select app.fin_cp_name_key('a')$q$),
  '^ERR 42501 .*permission denied.* \| ERR 42501 .*permission denied.* \| ERR 42501 .*permission denied.* \| ERR 42501 .*permission denied');

-- ---------- (B) kiritish tekshiruvlari ----------
select zz.chk('B1 tur, nom, so''rov shakli',
  zz.cs('U_FM', zz.base('{"kind":"xodim"}'::jsonb)) || ' | ' || zz.cs('U_FM', zz.base('{"name":" a "}'::jsonb)) || ' | '
  || zz.cs('U_FM', '[1,2]'::jsonb),
  '^ERR 22023 \[fin:cp_kind\].* \| ERR 22023 \[fin:cp_name\].* \| ERR 22023 \[fin:cp_bad\]');
select zz.chk('B2 STIR: 8 raqam, 14 raqam (JShShIR), harf — rad',
  zz.cs('U_FM', zz.base('{"stir":"00000020"}'::jsonb)) || ' | ' || zz.cs('U_FM', zz.base('{"kind":"person","stir":"00000000000201"}'::jsonb)) || ' | '
  || zz.cs('U_FM', zz.base('{"stir":"00000020A"}'::jsonb)),
  '^ERR 22023 \[fin:cp_stir\] STIR — 9 ta raqam.*JShShIR.* \| ERR 22023 \[fin:cp_stir\].* \| ERR 22023 \[fin:cp_stir\]');
select zz.chk('B3 hisob raqami (20 raqam, hozirgi uzunlik xabarda), MFO (5 raqam), hisob raqami MFO''siz, bank nomi 200 belgidan uzun',
  zz.cs('U_FM', zz.base('{"account":"0000000000000000020"}'::jsonb)) || ' | ' || zz.cs('U_FM', zz.base('{"account":"0000000000000000020A"}'::jsonb)) || ' | '
  || zz.cs('U_FM', zz.base('{"mfo":"0020"}'::jsonb)) || ' | ' || zz.cs('U_FM', zz.base('{"mfo":""}'::jsonb)) || ' | '
  || zz.cs('U_FM', zz.base(jsonb_build_object('bankName', repeat('b', 201)))),
  '^ERR 22023 \[fin:cp_account\] Hisob raqami — 20 ta raqam \(hozir: 19\) \| ERR 22023 \[fin:cp_account\].* \| ERR 22023 \[fin:cp_mfo\].* \| ERR 22023 \[fin:cp_mfo\] Hisob raqami bilan.* \| ERR 22023 \[fin:cp_bank\]');
select zz.chk('B4 shartnoma: raqamsiz sana, sanasiz raqam, 60 belgidan uzun raqam, kelajak sana, muddat sanadan oldin, sana shakli, mavjud bo''lmagan sana',
  zz.cs('U_FM', zz.base('{"contractNo":""}'::jsonb)) || ' | ' || zz.cs('U_FM', zz.base('{"contractDate":"","contractUntil":""}'::jsonb)) || ' | '
  || zz.cs('U_FM', zz.base(jsonb_build_object('contractNo', repeat('7', 61)))) || ' | ' || zz.cs('U_FM', zz.base('{"contractDate":"2027-02-11","contractUntil":""}'::jsonb)) || ' | '
  || zz.cs('U_FM', zz.base('{"contractUntil":"2027-01-14"}'::jsonb)) || ' | ' || zz.cs('U_FM', zz.base('{"contractDate":"15.01.2027"}'::jsonb)) || ' | '
  || zz.cs('U_FM', zz.base('{"contractDate":"2027-02-30","contractUntil":""}'::jsonb)),
  '^ERR 22023 \[fin:cp_contract\] Shartnoma raqamini.* \| ERR 22023 \[fin:cp_contract\] Shartnoma sanasini.* \| ERR 22023 \[fin:cp_contract\] Shartnoma raqami 60.* \| ERR 22023 \[fin:cp_contract\] Shartnoma sanasi bugundan.* \| ERR 22023 \[fin:cp_contract\] Shartnoma muddati.* \| ERR 22023 \[fin:cp_contract\] Shartnoma sanasi noto.* \| ERR 22023 \[fin:cp_contract\] Shartnoma sanasi noto');
select zz.chk('B5 izoh 500 belgidan uzun — rad; hech narsa yozilmagan',
  zz.cs('U_FM', zz.base(jsonb_build_object('note', repeat('i', 501)))) || ' | ' || (select count(*) from public.fin_counterparties),
  '^ERR 22023 \[fin:cp_note\].* \| 6$');
select zz.put('B6', zz.cs('U_FM', zz.base('{"stir":"000 000 201","account":"0000 0000 0000 0000 0201","mfo":" 00201 "}'::jsonb)));
select zz.put('B6id', zz.id(zz.get('B6')));
select zz.chk('B6 to''g''ri karta: bo''shliqlar olib tashlanadi, shartnoma №siz, muallif — server; Moliya menejeri — tur tasdiqlanmagan; yuridik shaxs',
  zz.card(zz.get('B6id')) || ' | ' || (zz.js(zz.get('B6')) ->> 'createdBy') || ':' || (zz.js(zz.get('B6')) ->> 'confirmed') || ':'
  || (zz.js(zz.get('B6')) ->> 'org') || ':' || (zz.js(zz.get('B6')) ->> 'dup') || ':' || (zz.get('B6id') ~ '^cp_[0-9a-f]{32}$'),
  '^supplier:Sinov Yetkazuvchi:000000201:00000000000000000201:00201:Sinov bank filiali:7:2027-01-15:2027-12-31:true:r0 \| U_FM:false:true:false:true$');
select zz.chk('B7 bank kontragenti — MFO hisob raqamisiz mumkin; rekvizitsiz karta ham',
  zz.card(zz.id(zz.cs('U_FM', '{"kind":"bank","name":"Sinov Bank filiali","mfo":"00301"}'::jsonb))) || ' | '
  || zz.card(zz.id(zz.cs('U_FM', '{"kind":"other","name":"Sinov Boshqa"}'::jsonb))),
  '^bank:Sinov Bank filiali:::00301:::-:-:true:r0 \| other:Sinov Boshqa::::::-:-:true:r0$');

-- ---------- (C) takror va bir vaqtda tahrirlash ----------
select zz.put('C1', zz.cs('U_ACC', zz.base('{"name":"  sinov  YETKAZUVCHI ","account":"00000000000000000999","mfo":"00999"}'::jsonb)));
select zz.chk('C1 shu tur + nom kaliti + STIR — yangi karta yaratilmaydi, mavjudi qaytadi (rekvizitlari o''zgarmaydi)',
  (zz.id(zz.get('C1')) = zz.get('B6id'))::text || ':' || (zz.js(zz.get('C1')) ->> 'dup') || ' | ' || zz.card(zz.get('B6id')),
  '^true:true \| supplier:Sinov Yetkazuvchi:000000201:00000000000000000201:00201:.*:r0$');
select zz.chk('C2 shu STIR boshqa nom bilan — ogohlantirish (nomi bilan); dupOk bilan — yoziladi',
  zz.cs('U_FM', zz.base('{"name":"Sinov Yetkazuvchi filiali"}'::jsonb)) || ' | '
  || coalesce(zz.card(zz.id(zz.cs('U_FM', zz.base('{"name":"Sinov Yetkazuvchi filiali","dupOk":true}'::jsonb)))), 'X'),
  '^ERR P0001 \[fin:cp_stir_dup\] STIR 000000201 ro''yxatdagi boshqa kontragentda bor: «Sinov Yetkazuvchi» — o''sha emasmi\? \| supplier:Sinov Yetkazuvchi filiali:000000201:.*:r0$');
select zz.put('C3', zz.cs('U_FM', zz.base(jsonb_build_object('id', zz.get('B6id'), 'rev', 0, 'contractNo', '8', 'contractDate', '2027-02-01', 'contractUntil', ''))));
select zz.chk('C3 o''zgartirish (rev 0): versiya 1, kim va qachon o''zgartirgani; shartnoma yangilandi',
  zz.card(zz.get('B6id')) || ' | ' || (zz.js(zz.get('C3')) ->> 'updatedBy') || ':' || ((zz.js(zz.get('C3')) ->> 'updatedAt') is not null) || ':' || (zz.js(zz.get('C3')) ->> 'dup'),
  '^supplier:Sinov Yetkazuvchi:000000201:00000000000000000201:00201:Sinov bank filiali:8:2027-02-01:-:true:r1 \| U_FM:true:false$');
select zz.chk('C4 eskirgan versiya bilan boshqa ma''lumot — rad; o''sha ma''lumot qayta yuborilsa — o''sha karta (versiya o''zgarmaydi); versiyasiz — rad',
  zz.cs('U_ACC', zz.base(jsonb_build_object('id', zz.get('B6id'), 'rev', 0, 'note', 'boshqa'))) || ' | '
  || (zz.js(zz.cs('U_FM', zz.base(jsonb_build_object('id', zz.get('B6id'), 'rev', 0, 'contractNo', '8', 'contractDate', '2027-02-01', 'contractUntil', '')))) ->> 'dup')
  || ':' || (select rev from public.fin_counterparties where id = zz.get('B6id')) || ' | ' || zz.cs('U_FM', zz.base(jsonb_build_object('id', zz.get('B6id')))),
  '^ERR P0001 \[fin:cp_changed\] Kontragent kartasi shu orada.* \| true:1 \| ERR 22023 \[fin:cp_changed\]');
select zz.chk('C5 kartani boshqa faol kartaning tur + nom + STIR''iga o''tkazish — rad; topilmagan karta — rad',
  zz.cs('U_FM', jsonb_build_object('id', 'cp4', 'rev', 0, 'kind', 'supplier', 'name', 'sinov ta’minotchi', 'stir', '000000101')) || ' | '
  || zz.cs('U_FM', zz.base('{"id":"cp_yoq","rev":0}'::jsonb)),
  '^ERR P0001 \[fin:cp_dup\] Bunday kontragent ro''yxatda bor: «Sinov Ta''minotchi» \(STIR 000000101\) \| ERR 22023 \[fin:not_found\]');
select zz.chk('C6 nofaol kartani faollashtirish: STIR boshqa faol kartada — ogohlantirish; dupOk bilan — faol',
  zz.cs('U_FM', '{"id":"cp5","rev":0,"kind":"supplier","name":"Nofaol Sinov","stir":"000000101","active":true}'::jsonb) || ' | '
  || zz.card(zz.id(zz.cs('U_FM', '{"id":"cp5","rev":0,"kind":"supplier","name":"Nofaol Sinov","stir":"000000101","active":true,"dupOk":true}'::jsonb))),
  '^ERR P0001 \[fin:cp_stir_dup\].*«Sinov Ta''minotchi».* \| supplier:Nofaol Sinov:000000101:::::-:-:true:r1$');
select zz.chk('C7 «faol» belgisi berilmasa — o''zgarmaydi; nofaol qilish',
  zz.card(zz.id(zz.cs('U_FM', '{"id":"cp5","rev":1,"kind":"supplier","name":"Nofaol Sinov","stir":"000000101"}'::jsonb))) || ' | '
  || zz.card(zz.id(zz.cs('U_FM', '{"id":"cp5","rev":2,"kind":"supplier","name":"Nofaol Sinov","stir":"000000101","active":false}'::jsonb))),
  '^supplier:Nofaol Sinov:000000101:::::-:-:true:r2 \| supplier:Nofaol Sinov:000000101:::::-:-:false:r3$');

-- ---------- (D) tur tasdig'i va eski funksiya ----------
select zz.put('D1', zz.cs('U_ACC', jsonb_build_object('id', 'cp3', 'rev', 0, 'kind', 'person', 'name', 'Sinov YaTT', 'stir', '000000401',
  'account', '00000000000000000401', 'mfo', '00401')));
select zz.chk('D1 buxgalter saqladi — tur tasdiqlangan (yuridik shaxs emas); Moliya menejeri faqat hisob raqamini o''zgartirdi — tasdiq qoladi',
  (zz.js(zz.get('D1')) ->> 'confirmed') || ':' || (zz.js(zz.get('D1')) ->> 'org') || ':' || (zz.js(zz.get('D1')) ->> 'kindConfirmedBy') || ' | '
  || (zz.js(zz.cs('U_FM', jsonb_build_object('id', 'cp3', 'rev', 1, 'kind', 'person', 'name', 'Sinov YaTT', 'stir', '000000401',
       'account', '00000000000000000402', 'mfo', '00401'))) ->> 'kindConfirmedBy'),
  '^true:false:U_ACC \| U_ACC$');
select zz.put('D2', zz.cs('U_FM', jsonb_build_object('id', 'cp3', 'rev', 2, 'kind', 'person', 'name', 'Sinov YaTT (yangi)', 'stir', '000000401',
  'account', '00000000000000000402', 'mfo', '00401')));
select zz.chk('D2 Moliya menejeri nomini o''zgartirdi — tasdiq bekor (yana yuridik shaxs hisoblanadi)',
  (zz.js(zz.get('D2')) ->> 'confirmed') || ':' || (zz.js(zz.get('D2')) ->> 'org') || ':' || app.kassa_is_org('cp3')::text, '^false:true:true$');
select zz.chk('D3 eski funksiya: STIR noto''g''ri — rad; bo''shliqli to''g''ri STIR — bo''shliqsiz saqlanadi',
  zz.old('U_KAS', null, 'supplier', 'Eski yo''l bilan', '1234') || ' | '
  || coalesce(zz.card(zz.id(zz.old('U_KAS', null, 'supplier', 'Eski yo''l bilan', '000 000 501'))), 'X'),
  '^ERR 22023 \[fin:cp_stir\].* \| supplier:Eski yo''l bilan:000000501:::::-:-:true:r0$');
select zz.chk('D4 eski funksiya bilan o''zgartirish: rekvizitlar va shartnoma saqlanadi, versiya oshadi, kim o''zgartirgani yoziladi',
  coalesce(zz.card(zz.id(zz.old('U_FM', zz.get('B6id'), 'supplier', 'Sinov Yetkazuvchi', '000000201'))), 'X') || ' | '
  || (select "updatedBy" from public.fin_counterparties where id = zz.get('B6id')),
  '^supplier:Sinov Yetkazuvchi:000000201:00000000000000000201:00201:Sinov bank filiali:8:2027-02-01:-:true:r2 \| U_FM$');
select zz.chk('D5 eski noto''g''ri STIR (8 raqam): o''zgarmasa — karta va eski funksiya saqlaydi, tur tasdig''i ishlaydi; o''zgarsa — rad (karta ham, eski funksiya ham)',
  coalesce(zz.card(zz.id(zz.cs('U_FM', '{"id":"cp4","rev":0,"kind":"supplier","name":"Eski Sinov","stir":"12345678","contractNo":"3","contractDate":"2027-01-02"}'::jsonb))), 'X')
  || ' | ' || coalesce(zz.js(zz.old('U_FM', 'cp4', 'supplier', 'Eski Sinov', '12345678')) ->> 'stir', 'X')
  || ' | ' || coalesce(zz.js(zz.as('U_ACC', $q$select public.fin_counterparty_confirm('cp4', 'supplier', 'Eski Sinov')::text$q$)) ->> 'ok', 'X')
  || ' | ' || zz.cs('U_FM', '{"id":"cp4","rev":2,"kind":"supplier","name":"Eski Sinov","stir":"1234567"}'::jsonb)
  || ' | ' || zz.old('U_FM', 'cp4', 'supplier', 'Eski Sinov', '1234'),
  '^supplier:Eski Sinov:12345678::::3:2027-01-02:-:true:r1 \| 12345678 \| true \| ERR 22023 \[fin:cp_stir\].* \| ERR 22023 \[fin:cp_stir\]');
select zz.chk('D6 eski va yangi yo''l bir xil takror kaliti: eski funksiya bilan kartadagi kontragent — o''sha qaytadi',
  (zz.id(zz.old('U_KAS', null, 'supplier', 'SINOV yetkazuvchi', '000000201')) = zz.get('B6id'))::text, '^true$');

-- ---------- (E) RP-10 ko'chirma ----------
select zz.put('E1', zz.st('U_FM', 'cp1', '2027-01-01', '2027-01-31'));
select zz.chk('E1 yanvar: davr boshigacha (dekabr KO-2), davr (kirim / chiqim, soni), davr oxirigacha',
  zz.sums(zz.get('E1')), '^0/300000 \| 100000/2280000/6 \| 100000/2580000$');
select zz.chk('E2 qatorlar tartibi: sana, vaqt; manbalar — kassa orderi, xarajat hujjati, eski yozuv (noto''g''ri sana — oydan / yozilgan kundan)',
  zz.rows(zz.get('E1')),
  '^2027-01-01:legacy:e4:0:10000,2027-01-05:cash:d1:0:500000,2027-01-06:cash:d2:100000:0,2027-01-08:exp:x1:0:1500000,2027-01-09:legacy:e1:0:250000,2027-01-15:legacy:e5:0:20000$');
select zz.chk('E3 hujjat, usul, operatsiya, statiyalar, asos / izoh; statiya nomlari',
  (select string_agg((r ->> 'doc') || '|' || (r ->> 'method') || '|' || (r ->> 'opName') || '|' || (r -> 'arts')::text || '|' || (r ->> 'text'), ' ; ' order by o)
     from jsonb_array_elements(zz.js(zz.get('E1')) -> 'rows') with ordinality as t(r, o) where r ->> 'ref' in ('d1', 'd2', 'x1', 'e1'))
  || ' ## ' || (select string_agg(k, ',' order by k) from jsonb_object_keys(zz.js(zz.get('E1')) -> 'articles') k),
  '^KO-2 № 3\|cash\|Xarajat\|\["EX-32"\]\|Sinov xarid ; KO-1 № 4\|cash\|Boshqa kirim\|\["IN-06"\]\|Ortiqcha to''lov qaytdi ; № 145 · 07.01.2027\|bank\|Xarajat\|\["EX-11", "EX-13"\]\|Yanvar kommunal ; \|bank\|Xarajat\|\["EX-10"\]\|Ijara \(eski yozuv\) ## EX-10,EX-11,EX-13,EX-32,EX-49,IN-06$');
select zz.chk('E4 kirmaydi: bekor qilingan order va hujjat, sinov kassasi, pul berilmagan so''rov, eski yozuv surati, kassadan ko''chgan va hujjat qatorlari',
  (select count(*) from jsonb_array_elements(zz.js(zz.get('E1')) -> 'rows') r where r ->> 'ref' in ('d3', 'd4', 'd5', 'x2', 'x3', 'kx_d1_1', 'x1_1', 'x1_2'))::text,
  '^0$');
select zz.chk('E5 davr oxiridan keyingi hujjat kirmaydi; kengroq davrda — bor; bank kontragenti — «Bankka topshirish»',
  zz.sums(zz.st('U_DIR', 'cp1', '2027-01-01', '2027-03-31')) || ' | '
  || (select string_agg((r ->> 'doc') || '|' || (r ->> 'opName') || '|' || trim_scale((r ->> 'out')::numeric), ';') from jsonb_array_elements(zz.js(zz.st('U_ACC', 'cp2', '2027-01-01', '2027-01-31')) -> 'rows') r),
  '^0/300000 \| 100000/2880000/7 \| 100000/3180000 \| KO-2 № 6\|Bankka topshirish\|2000000$');
select zz.chk('E6 davr tekshiruvi: boshi oxiridan keyin, bo''sh, 3 yildan ortiq; topilmagan kontragent',
  zz.st('U_FM', 'cp1', '2027-02-01', '2027-01-01') || ' | ' || zz.st('U_FM', 'cp1', null, '2027-01-01') || ' | '
  || zz.st('U_FM', 'cp1', '2024-01-01', '2027-01-31') || ' | ' || zz.st('U_FM', 'cp_yoq', '2027-01-01', '2027-01-31'),
  '^ERR 22023 \[fin:period\].* \| ERR 22023 \[fin:period\].* \| ERR 22023 \[fin:period\] Davr 3 yildan.* \| ERR 22023 \[fin:not_found\]');
select zz.put('E7', zz.st('U_FM', 'cp3', '2027-01-01', '2027-01-31', true));
select zz.chk('E7 FD-28: jismoniy shaxs ko''chirmasi faylga — Moliya menejeriga ismsiz (ID; STIR, hisob raqami, asos matni yo''q), summalar o''sha',
  (zz.js(zz.get('E7')) ->> 'masked') || ' | ' || (zz.js(zz.get('E7')) -> 'cp')::text || ' | ' || zz.rows(zz.get('E7')) || ' | '
  || (select string_agg('[' || (r ->> 'text') || ']', '') from jsonb_array_elements(zz.js(zz.get('E7')) -> 'rows') r),
  '^true \| \{"id": "cp3", "kind": "person", "active": true, "contractNo": "", "contractDate": null, "contractUntil": null\} \| 2027-01-07:cash:d8:0:40000 \| \[\]$');
select zz.chk('E8 … Direktorga fayl — to''liq; ekranda (fayl emas) — to''liq; yuridik shaxs fayli — to''liq',
  (zz.js(zz.st('U_DIR', 'cp3', '2027-01-01', '2027-01-31', true)) #>> '{cp,name}') || ':' || (zz.js(zz.st('U_DIR', 'cp3', '2027-01-01', '2027-01-31', true)) #>> '{rows,0,text}')
  || ' | ' || (zz.js(zz.st('U_FM', 'cp3', '2027-01-01', '2027-01-31')) ->> 'masked') || ':' || (zz.js(zz.st('U_FM', 'cp3', '2027-01-01', '2027-01-31')) #>> '{cp,stir}')
  || ' | ' || (zz.js(zz.st('U_ACC', 'cp1', '2027-01-01', '2027-01-31', true)) ->> 'masked') || ':' || (zz.js(zz.st('U_ACC', 'cp1', '2027-01-01', '2027-01-31', true)) #>> '{cp,name}'),
  '^Sinov YaTT \(yangi\):Xizmat — Sinov Ismli \| false:000000401 \| false:Sinov Ta''minotchi$');
select zz.chk('E9 javobda tashkilot, davr va bugungi sana; bo''sh davr — qatorsiz, jamlar 0 emas (davr boshigacha)',
  (zz.js(zz.get('E1')) ? 'org')::text || ':' || (zz.js(zz.get('E1')) ->> 'from') || ':' || (zz.js(zz.get('E1')) ->> 'to') || ':' || (zz.js(zz.get('E1')) ->> 'today')
  || ' | ' || zz.sums(zz.st('U_FM', 'cp1', '2027-02-01', '2027-02-10')) || ':' || zz.rows(zz.st('U_FM', 'cp1', '2027-02-01', '2027-02-10')),
  '^true:2027-01-01:2027-01-31:2027-02-10 \| 100000/2580000 \| 0/0/0 \| 100000/2580000:-$');

-- ---------- (F) o'zgarishlar jurnali va jadval cheklovlari ----------
select zz.chk('F1 o''zgarishlar jurnali: hisob raqami va shartnoma o''zgarishlari (kim)',
  (select string_agg(distinct k, ',' order by k) from public.change_log l, jsonb_object_keys(l.changes) k
    where l.tbl = 'fin_counterparties' and l.row_id = 'cp3' and l.op = 'UPDATE') || ' | '
  || (select count(*) from public.change_log l where l.tbl = 'fin_counterparties' and l.row_id = zz.get('B6id') and l.op = 'UPDATE' and l.changes ? 'contractNo' and l.actor_uid = 'U_FM'),
  '^account,kind[Cc]onfirmed[Bb]y,mfo,name,stir \| 1$');
select zz.chk('F2 jadval cheklovlari (egasi yozsa ham): 19 raqamli hisob, MFO''siz hisob, muddati sanasidan oldin, raqamsiz sana',
  zz.own($q$update public.fin_counterparties set account = '0000000000000000001', mfo = '00001' where id = 'cp2' returning id$q$) || ' | '
  || zz.own($q$update public.fin_counterparties set account = '00000000000000000001', mfo = '' where id = 'cp2' returning id$q$) || ' | '
  || zz.own($q$update public.fin_counterparties set "contractNo" = '1', "contractDate" = '2027-01-10', "contractUntil" = '2027-01-09' where id = 'cp2' returning id$q$) || ' | '
  || zz.own($q$update public.fin_counterparties set "contractDate" = '2027-01-10' where id = 'cp2' returning id$q$),
  '^ERR 23514 .*fin_counterparties_bank_chk.* \| ERR 23514 .*fin_counterparties_bank_chk.* \| ERR 23514 .*fin_counterparties_contract_chk.* \| ERR 23514 .*fin_counterparties_contract_chk');

-- ---------- Natija ----------
select (case when ok then 'PASS' else 'FAIL' end) || ' ' || name || case when ok then '' else E'\n     got: ' || coalesce(got, '<null>') || E'\n     pat: ' || pat end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
