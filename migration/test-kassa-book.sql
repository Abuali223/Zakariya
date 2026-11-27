-- =====================================================================
-- test-kassa-book.sql — moliya ish rejasi 2-bosqichi, F2.12 (kassa kitobi muqovasi va guvohnomasi, patta QR) sinovi:
--   (A) patta tekshiruv kaliti: kirim orderi (KO-1) o'tkazilganda kalit (32 ta 0-9/a-f, takrorlanmas); dalolatnoma va chiqim orderida
--       yo'q; Direktor ruxsatini kutgan kirimda — faqat o'tkazilgach; kassa_doc_get javobida (vtok); jadval — kassa o'quvchilari
--       (o'qituvchi — 0 qator, mehmon — rad); jadvalga to'g'ridan-to'g'ri yozish — rad;
--   (B) verify_patta (mehmon ham): haqiqiy order — holat, shakl, raqam, yil, sana, summa, tashkilot, sinov kassasi belgisi; ismsiz
--       (faqat ruxsat etilgan kalitlar, to'lovchi / asos / kassir yo'q); kod formati, katta harf va bo'shliq, noma'lum kod, bo'sh;
--       bekor qilingan order — holat va sana;
--   (C) kassa_book_cover — yil muqovasi va guvohnoma: huquqlar (kassa o'quvchilari; o'qituvchi, mehmon — yo'q), yil va kassa
--       tekshiruvi, kunlar, varaqlar (birinchi / oxirgi raqam, soni), KO-1 / KO-2 oralig'i, ochiq kun, yil tugamagan / tugagan,
--       raqamlar uzilishi, to'liq belgisi, sinov kassasi, hali kuni yo'q yil.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-book.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov nomlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) or exists (select 1 from public.cash_days) then
    raise exception 'test-kassa-book.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
create or replace function zz.put(p_k text, p_v text) returns text language plpgsql as $$
begin insert into zz.v (k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; return p_v; end $$;
create or replace function zz.get(p_k text) returns text language sql as $$ select v from zz.v where k = p_k $$;
create or replace function zz.id(p_k text) returns text language sql as $$ select coalesce(zz.js(zz.get(p_k)) ->> 'id', '?') $$;
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
create or replace function zz.rpc(p_uid text, p_fn text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.%I(%L::jsonb)::text', p_fn, p_json)) $$;
create or replace function zz.rcpt(p_uid text, p_json text) returns text language sql as $$ select zz.rpc(p_uid, 'kassa_receipt', p_json) $$;
create or replace function zz.appr(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_approve(%L)::text', p_id)) $$;
create or replace function zz.pay(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_pay(%L)::text', p_id)) $$;
create or replace function zz.tok(p_id text) returns text language sql as $$
  select coalesce((select v.token from public.cash_doc_verify v where v."docId" = p_id), '-') $$;
create or replace function zz.ver(p_uid text, p_tok text) returns text language sql as $$
  select zz.as(p_uid, format('select public.verify_patta(%s)::text', coalesce(quote_literal(p_tok), 'null'))) $$;
create or replace function zz.cov(p_uid text, p_desk text, p_year int) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_book_cover(%L, %s)::text', p_desk, coalesce(p_year::text, 'null'))) $$;
-- muqova qisqachasi: yil tugaganmi / kunlar / yopilgan / ochiq kunlar / varaqlar dan-gacha, soni / uzilishlar / KO-1 / KO-2 / to'liq
create or replace function zz.cs(p text) returns text language sql as $$
  select (j ->> 'yearEnded') || '/' || (j ->> 'days') || '/' || (j ->> 'closedDays') || '/' || (j -> 'openDays')::text || '/'
         || coalesce(j ->> 'sheetFrom', '-') || '-' || coalesce(j ->> 'sheetTo', '-') || ':' || (j ->> 'sheets') || '/' || (j -> 'gaps')::text || '/'
         || coalesce((j -> 'ko1' ->> 'first') || '-' || (j -> 'ko1' ->> 'last') || ':' || (j -> 'ko1' ->> 'count'), '-') || '/'
         || coalesce((j -> 'ko2' ->> 'first') || '-' || (j -> 'ko2' ->> 'last') || ':' || (j -> 'ko2' ->> 'count'), '-') || '/'
         || (j ->> 'complete')
    from (select zz.js(p) as j) x $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'), ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]'),
  ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
update public.fin_org set "nameUz" = '«SINOV MAKTAB» MChJ' where id = 'main';
set local session_replication_role = origin;

-- ---------- 1-kun (2026-12-28): boshlang'ich qoldiq, kirimlar, bekor qilingan kirim, ruxsat kutgan kirim, chiqim ----------
select zz.clock('2026-12-28 10:00+05');
select zz.put('cp_bank', zz.as('U_FM', $q$select public.fin_counterparty_save(null, 'bank', 'Sinov Bank')::text$q$));
select zz.put('cp_fnd', zz.as('U_DIR', $q$select public.fin_counterparty_save(null, 'founder', 'Sinov Ta''sischi')::text$q$));
select zz.put('open', zz.rpc('U_DIR', 'kassa_opening_set', '{"amount":1000000,"startDay":"2026-12-28","note":"Komissiya sanashi","commission":[{"title":"Direktor","name":"Sinov D"},{"title":"Kassir","name":"Sinov K"}]}'));
select zz.put('r1', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":200000,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"bk-r1-0001"}', zz.id('cp_bank'))));
select zz.put('r3', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":10000,"partyType":"bank","partyId":"%s","basis":"Chek 003","clientRef":"bk-r3-0001"}', zz.id('cp_bank'))));
select zz.put('r2', zz.rcpt('U_KAS', format('{"op":"in_funding","amount":50000,"partyType":"founder","partyId":"%s","articleId":"OP-20","basis":"Qaror 2","clientRef":"bk-r2-0001"}', zz.id('cp_fnd'))));

select zz.chk('A1 kirim orderi o''tkazildi — tekshiruv kaliti bor (32 ta 0-9/a-f)',
  (select status || ':' || no from public.cash_docs where id = zz.id('r1')) || '/' || zz.tok(zz.id('r1')), '^posted:1/[0-9a-f]{32}$');
select zz.chk('A2 boshlang''ich qoldiq dalolatnomasi (raqamli, «Д-») — kalit yo''q',
  (select form || ':' || coalesce(no::text, '-') from public.cash_docs where op = 'nc_opening') || '/' || zz.tok((select id from public.cash_docs where op = 'nc_opening')), '^ACT:1/-$');
select zz.chk('A3 Direktor ruxsatini kutgan kirim (raqamsiz so''rov) — kalit hali yo''q',
  (select status || ':' || coalesce(no::text, '-') from public.cash_docs where id = zz.id('r2')) || '/' || zz.tok(zz.id('r2')), '^draft:-/-$');
select zz.put('r2a', zz.appr('U_DIR', zz.id('r2')));
select zz.put('r2p', zz.pay('U_KAS', zz.id('r2')));
select zz.chk('A4 ruxsatdan keyin o''tkazildi (raqam olganda) — kalit yaratildi, boshqa orderlarnikidan farqli',
  (select status || ':' || no from public.cash_docs where id = zz.id('r2')) || '/' || zz.tok(zz.id('r2')) || '/'
    || (zz.tok(zz.id('r2')) <> zz.tok(zz.id('r1')))::text || '/' || (select count(*) = count(distinct token) from public.cash_doc_verify)::text,
  '^posted:3/[0-9a-f]{32}/true/true$');
select zz.put('p1', zz.as('U_KAS', format('select public.kassa_payout_request(%L::jsonb)::text',
  format('{"op":"out_bank","amount":300000,"partyType":"bank","partyId":"%s","basis":"Naqd pul topshirish e''loni № 1","clientRef":"bk-p1-0001"}', zz.id('cp_bank')))));
select zz.put('p1a', zz.appr('U_FM', zz.id('p1')));
select zz.put('p1d', zz.appr('U_DIR', zz.id('p1')));   -- t1 = 0: har KO-2 ga Direktor ham
select zz.put('p1p', zz.pay('U_KAS', zz.id('p1')));
select zz.chk('A5 chiqim orderi (KO-2) o''tkazildi — kalit yo''q',
  (select form || ':' || status || ':' || no from public.cash_docs where id = zz.id('p1')) || '/' || zz.tok(zz.id('p1')), '^KO2:posted:1/-$');
select zz.chk('A6 kassa_doc_get (kassir): javobda kalit (vtok) — jadvaldagi bilan bir xil; chiqim orderida — yo''q',
  ((zz.js(zz.as('U_KAS', format('select public.kassa_doc_get(%L)::text', zz.id('r1')))) #>> '{doc,vtok}') = zz.tok(zz.id('r1')))::text || '/'
    || coalesce(zz.js(zz.as('U_KAS', format('select public.kassa_doc_get(%L)::text', zz.id('p1')))) #>> '{doc,vtok}', 'null'), '^true/null$');
select zz.chk('A7 jadval: kassir va buxgalter o''qiydi; o''qituvchi — 0 qator; mehmon — rad',
  zz.as('U_KAS', 'select count(*)::text from public.cash_doc_verify') || '/' || zz.as('U_ACC', 'select count(*)::text from public.cash_doc_verify') || '/'
    || zz.as('U_TCH', 'select count(*)::text from public.cash_doc_verify') || '/' || zz.as(null, 'select count(*)::text from public.cash_doc_verify'),
  '^3/3/0/ERR 42501');
select zz.chk('A8 jadvalga to''g''ridan-to''g''ri yozish (Direktor ham) — rad',
  zz.as('U_DIR', format('insert into public.cash_doc_verify ("docId", token) values (%L, %L) returning 1', zz.id('p1'), repeat('a', 32))) || ' | '
    || zz.as('U_DIR', format('update public.cash_doc_verify set token = %L where "docId" = %L returning 1', repeat('b', 32), zz.id('r1'))),
  '^ERR 42501 .* \| ERR 42501');

-- ---------- (B) verify_patta ----------
select zz.put('t1', zz.tok(zz.id('r1')));
select zz.chk('B1 mehmon: haqiqiy order — holat, shakl, raqam, yil, sana, summa, tashkilot, sinov emas, bekor sanasi yo''q',
  (select (j ->> 'valid') || '/' || (j ->> 'status') || '/' || (j ->> 'form') || '/' || (j ->> 'no') || '/' || (j ->> 'year') || '/' || (j ->> 'day') || '/'
          || (j ->> 'amount') || '/' || (j ->> 'org') || '/' || (j ->> 'isTest') || '/' || coalesce(j ->> 'voidedAt', 'null')
     from (select zz.js(zz.ver(null, zz.get('t1'))) as j) x),
  '^true/posted/KO1/1/2026/2026-12-28/200000/«SINOV MAKTAB» MChJ/false/null$');
select zz.chk('B2 ismsiz: faqat ruxsat etilgan kalitlar; to''lovchi, asos, kassir, hujjat ID — yo''q',
  (select string_agg(k, ',' order by k) from jsonb_object_keys(zz.js(zz.ver(null, zz.get('t1')))) k) || ' / '
    || (zz.ver(null, zz.get('t1')) ~ '(Sinov Bank|Chek 001|Sinov Kassir|kd_)')::text,
  '^amount,day,form,isTest,no,org,status,valid,voidedAt,year / false$');
select zz.chk('B3 katta harf va chetdagi bo''shliq — o''sha order; tizimga kirgan (o''qituvchi) ham tekshira oladi',
  (zz.js(zz.ver(null, '  ' || upper(zz.get('t1')) || ' ')) ->> 'no') || '/' || (zz.js(zz.ver('U_TCH', zz.get('t1'))) ->> 'valid'), '^1/true$');
select zz.chk('B4 noto''g''ri kod: qisqa, uzun, hex emas, bo''sh, null — {"valid": false}',
  zz.ver(null, left(zz.get('t1'), 31)) || ' | ' || zz.ver(null, zz.get('t1') || 'a') || ' | ' || zz.ver(null, repeat('g', 32)) || ' | '
    || zz.ver(null, '') || ' | ' || zz.ver(null, null),
  '^\{"valid": false\} \| \{"valid": false\} \| \{"valid": false\} \| \{"valid": false\} \| \{"valid": false\}$');
select zz.chk('B5 to''g''ri shakldagi, lekin mavjud bo''lmagan kod — {"valid": false}',
  zz.ver(null, translate(zz.get('t1'), '0123456789abcdef', '123456789abcdef0')), '^\{"valid": false\}$');
select zz.put('v3', zz.as('U_KAS', format('select public.kassa_doc_void(%L, %L)::text', zz.id('r3'), 'Sinov: adashib yozildi')));
select zz.chk('B6 bekor qilingan kirim orderi: kalit qoladi, tekshiruv — holat «void» va bekor qilingan sana (Toshkent kuni)',
  (select status from public.cash_docs where id = zz.id('r3')) || '/'
    || (select (j ->> 'valid') || ':' || (j ->> 'status') || ':' || (j ->> 'no') || ':' || coalesce(j ->> 'voidedAt', 'null')
          from (select zz.js(zz.ver(null, zz.tok(zz.id('r3')))) as j) x),
  '^void/true:void:2:' || to_char(now() at time zone 'Asia/Tashkent', 'YYYY-MM-DD') || '$');   -- bekor qilish vaqti — server soati (now())
set local session_replication_role = replica;
update public.cash_desks set "isTest" = true where id = 'main';
set local session_replication_role = origin;
select zz.chk('B7 sinov kassasi orderi — belgi isTest', zz.js(zz.ver(null, zz.get('t1'))) ->> 'isTest', '^true$');
set local session_replication_role = replica;
update public.cash_desks set "isTest" = false where id = 'main';
set local session_replication_role = origin;

-- ---------- (C) kassa_book_cover ----------
select zz.put('c1', zz.as('U_KAS', format('select public.kassa_day_close(%L::jsonb)::text', '{"day":"2026-12-28","counted":950000,"expected":950000}')));
select zz.clock('2026-12-29 10:00+05');
select zz.put('r4', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":100000,"partyType":"bank","partyId":"%s","basis":"Chek 004","clientRef":"bk-r4-0001"}', zz.id('cp_bank'))));
select zz.put('c2', zz.as('U_KAS', format('select public.kassa_day_close(%L::jsonb)::text', '{"day":"2026-12-29","counted":1050000,"expected":1050000}')));
select zz.chk('C0a yil tugamagan, hamma kun yopilgan — baribir to''liq emas (kitob yil oxirida tikiladi)',
  zz.cs(zz.cov('U_KAS', 'main', 2026)), '^false/2/2/\[\]/1-2:2/\[\]/1-4:4/1-1:1/false$');
select zz.clock('2026-12-30 10:00+05');
select zz.put('r5', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":20000,"partyType":"bank","partyId":"%s","basis":"Chek 005","clientRef":"bk-r5-0001"}', zz.id('cp_bank'))));
select zz.chk('C0 tayyorgarlik: ikki kun yopildi (KO-4 varaqlari 1 va 2), uchinchi kun ochiq',
  (select string_agg(to_char(day, 'MM-DD') || ':' || status || ':' || coalesce("sheetFrom"::text, '-') || '-' || coalesce("sheetTo"::text, '-'), ',' order by day)
     from public.cash_days where desk = 'main'), '^12-28:closed:1-1,12-29:closed:2-2,12-30:open:---$');
select zz.chk('C1 yil tugamagan, ochiq kun bor: yil tugamagan / 3 kun / 2 yopilgan / ochiq 30-dekabr / varaqlar 1–2 (2 ta) / uzilish yo''q / KO-1 1–5 (5) / KO-2 1–1 / to''liq emas',
  zz.cs(zz.cov('U_KAS', 'main', 2026)), '^false/3/2/\["2026-12-30"\]/1-2:2/\[\]/1-5:5/1-1:1/false$');
select zz.chk('C2 javob: kassa nomi, sinov emas, yil, birinchi / oxirgi kun',
  (select (j ->> 'desk') || '/' || (j ->> 'deskName') || '/' || (j ->> 'isTest') || '/' || (j ->> 'year') || '/' || (j ->> 'firstDay') || '/' || (j ->> 'lastDay')
     from (select zz.js(zz.cov('U_DIR', null, 2026)) as j) x), '^main/Asosiy kassa/false/2026/2026-12-28/2026-12-30$');
select zz.chk('C3 huquqlar: kassir, buxgalter, Moliya menejeri, Direktor — ha; o''qituvchi, mehmon — rad',
  (select string_agg(coalesce(zz.js(zz.cov(u, 'main', 2026)) ->> 'ok', left(zz.cov(u, 'main', 2026), 9)), ',' order by o)
     from unnest(array['U_KAS', 'U_ACC', 'U_FM', 'U_DIR', 'U_TCH']) with ordinality t(u, o)) || ',' || left(zz.cov(null, 'main', 2026), 9),
  '^true,true,true,true,ERR 42501,ERR 42501$');
select zz.chk('C4 yil va kassa tekshiruvi: 1999, kelgusi yil (2027 — bugun 2026), null, noma''lum kassa — rad',
  left(zz.cov('U_KAS', 'main', 1999), 27) || ' | ' || left(zz.cov('U_KAS', 'main', 2027), 27) || ' | ' || left(zz.cov('U_KAS', 'main', null), 27) || ' | '
    || left(zz.cov('U_KAS', 'yoq', 2026), 27),
  '^ERR 22023 \[kassa:bad_input\] \| ERR 22023 \[kassa:bad_input\] \| ERR 22023 \[kassa:bad_input\] \| ERR 22023 \[kassa:bad_input\]$');
select zz.clock('2027-01-04 09:00+05');
select zz.chk('C4a yangi yil, lekin 30-dekabr hali yopilmagan — to''liq emas',
  zz.cs(zz.cov('U_KAS', 'main', 2026)), '^true/3/2/\["2026-12-30"\]/1-2:2/\[\]/1-5:5/1-1:1/false$');
select zz.put('c3', zz.as('U_KAS', format('select public.kassa_day_close(%L::jsonb)::text', '{"day":"2026-12-30","counted":1070000,"expected":1070000}')));
select zz.chk('C5 yangi yil, 30-dekabr yopildi: yil tugagan / 3 yopilgan / ochiq yo''q / varaqlar 1–3 (3 ta) / uzilish yo''q / to''liq',
  (select status || ':' || "sheetFrom" from public.cash_days where desk = 'main' and day = '2026-12-30') || ' | ' || zz.cs(zz.cov('U_ACC', 'main', 2026)),
  '^closed:3 \| true/3/3/\[\]/1-3:3/\[\]/1-5:5/1-1:1/true$');
set local session_replication_role = replica;
update public.cash_days set "sheetFrom" = 5, "sheetTo" = 5 where desk = 'main' and day = '2026-12-29';
set local session_replication_role = origin;
select zz.chk('C6 varaq raqamlari uzilgan (29-dekabr 5-varaqdan) — ikki kun uzilishda, to''liq emas',
  zz.cs(zz.cov('U_DIR', 'main', 2026)), '^true/3/3/\[\]/1-5:3/\["2026-12-29", "2026-12-30"\]/1-5:5/1-1:1/false$');
set local session_replication_role = replica;
update public.cash_days set "sheetFrom" = 2, "sheetTo" = 2 where desk = 'main' and day = '2026-12-29';
update public.cash_days set "docCount" = 31 where desk = 'main' and day = '2026-12-28';
set local session_replication_role = origin;
select zz.chk('C7 varaqlar soni hujjatlar soniga mos emas (31 hujjat — 1 varaq, 30 qatorli) — uzilish (kassa-checks 15-band qoidasi)',
  (zz.js(zz.cov('U_DIR', 'main', 2026)) -> 'gaps')::text || '/' || (zz.js(zz.cov('U_DIR', 'main', 2026)) ->> 'complete'), '^\["2026-12-28"\]/false$');
set local session_replication_role = replica;
update public.cash_days set "docCount" = 4 where desk = 'main' and day = '2026-12-28';
set local session_replication_role = origin;
select zz.chk('C8 joriy yil (kuni hali yo''q) va sinov kassasi: kunlar 0, varaqlar 0, birinchi kun — null, to''liq emas',
  zz.cs(zz.cov('U_KAS', 'main', 2027)) || ' | ' || coalesce(zz.js(zz.cov('U_KAS', 'main', 2027)) ->> 'firstDay', 'null') || ' | '
    || (zz.js(zz.cov('U_KAS', 'sinov', 2026)) ->> 'isTest') || ':' || zz.cs(zz.cov('U_KAS', 'sinov', 2026)),
  '^false/0/0/\[\]/---:0/\[\]/-/-/false \| null \| true:true/0/0/\[\]/---:0/\[\]/-/-/false$');

select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(got, '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || case when bool_and(ok) then ' — HAMMASI O''TDI' else ' — XATO BOR' end from zz.res;
rollback;
