-- =====================================================================
-- test-kassa-report.sql — moliya ish rejasi 1a-bosqichi, F1.15 (RP-02, RP-05, RP-06) sinovi:
--   (N) Telegram: kassa ishlatilmaguncha director_daily'da 'kassa' bloki yo'q; ishga tushgach — bor;
--   (R) kunlik hisobot ma'lumoti (kassa_day_book): jamlar = kun varag'i (RP-02 = KO-4); «kimdan / kimga» tomon KALITI bo'yicha;
--       statiya bo'yicha; ichki o'tkazmalar; kanallar; kutilayotganlar; limit;
--   (D) director_daily → 'kassa': kun jamlari kassa_day_book bilan bir xil; nazorat qatori;
--   (C) nazorat ro'yxati (kassa_checks): chop etilmagan KO-4, oflayn yozuvli yopish, limit, hisobdorlar muddati, rahbarga berilgan pul;
--   (M) moslik P1/P4/P5/P8 — toza holatda 0; har buzilish o'z hisoblagichida ko'rinadi;
--   (T) sinov kassasi (CT-20): xarajat va avans orderi «Buxgalteriya» / avans jadvaliga yozilmaydi;
--   (G) rollar;
--   (AV) avans hisoboti va «hisobotsiz yangi avans yo'q» qoidasi;
--   (Z) onlayn kassa (NKM) Z-hisoboti: kiritish, solishtirish (fiskal chekli KO-1, terminal), nazorat, Telegram, kunni tekshirish.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-report.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) then
    raise exception 'test-kassa-report.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
create table if not exists zz.v (k text primary key, v text);
truncate zz.res; truncate zz.v;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
create or replace function zz.put(p_k text, p_v text) returns text language plpgsql as $$
begin insert into zz.v (k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; return p_v; end $$;
create or replace function zz.get(p_k text) returns text language sql as $$ select v from zz.v where k = p_k $$;
create or replace function zz.id(p_k text) returns text language sql as $$ select (v::jsonb ->> 'id') from zz.v where k = p_k $$;
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
create or replace function zz.rpc(p_uid text, p_fn text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.%I(%L::jsonb)::text', p_fn, p_json)) $$;
create or replace function zz.appr(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_approve(%L)::text', p_id)) $$;
create or replace function zz.pay(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_pay(%L)::text', p_id)) $$;
create or replace function zz.void(p_uid text, p_id text, p_reason text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_void(%L, %L)::text', p_id, p_reason)) $$;
-- Qo'lda naqd o'quv to'lovi: (uid, payId, o'quvchi, summa, to'lovchi, fiskal chek №)
create or replace function zz.tui(p_uid text, p_id text, p_sid text, p_amount numeric, p_payer text, p_fiscal text) returns text language sql as $$
  select zz.as(p_uid, format('select public.record_manual_payment(%L, %L, %s, %L, null, %L, %L, %L, null, %L::jsonb)::text',
                             p_id, p_sid, p_amount, 'cash', '', '', p_payer, jsonb_build_object('fiscalNo', p_fiscal)::text)) $$;
-- Kun ma'lumoti (Moliya menejeri nomidan) va undan qism olish
create or replace function zz.book(p_desk text, p_day text) returns jsonb language sql as $$
  select zz.as('U_FM', format('select public.kassa_day_book(%L, %L)::text', p_desk, p_day))::jsonb $$;
create or replace function zz.party(p_book jsonb, p_form text, p_type text, p_id text) returns text language sql as $$
  select string_agg((x ->> 'name') || '|' || (x ->> 'count') || '|' || trim_scale((x ->> 'amount')::numeric) || '|' || (x ->> 'ops'), ' ; ' order by x ->> 'name')
    from jsonb_array_elements(p_book -> 'byParty') x
   where x ->> 'form' = p_form and x ->> 'partyType' = p_type and coalesce(x ->> 'partyId', '') = coalesce(p_id, '') $$;
create or replace function zz.sumof(p_arr jsonb, p_form text) returns text language sql as $$
  select trim_scale(coalesce(sum((x ->> 'amount')::numeric), 0))::text from jsonb_array_elements(p_arr) x where x ->> 'form' = p_form $$;
create or replace function zz.daily(p_day text) returns jsonb language sql as $$
  select zz.as('U_DIR', format('select public.director_daily(%L)::text', p_day))::jsonb $$;
create or replace function zz.checks(p_desk text) returns jsonb language sql as $$
  select zz.as('U_FM', format('select public.kassa_checks(%L)::text', p_desk))::jsonb $$;
create or replace function zz.rec() returns text language sql as $$
  select (c -> 'reconcile' ->> 'live') || ' p1=' || (c -> 'reconcile' -> 'p1' ->> 'pay') || '/' || (c -> 'reconcile' -> 'p1' ->> 'doc')
      || ' p4=' || (c -> 'reconcile' -> 'p4' ->> 'row') || '/' || (c -> 'reconcile' -> 'p4' ->> 'doc')
      || ' p5=' || (c -> 'reconcile' -> 'p5' ->> 'row') || '/' || (c -> 'reconcile' -> 'p5' ->> 'doc')
      || ' p8=' || (c -> 'reconcile' -> 'p8' ->> 'row') || '/' || (c -> 'reconcile' -> 'p8' ->> 'doc')
      || ' jami=' || (c -> 'reconcile' ->> 'total')
    from zz.checks('main') c $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'), ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]'), ('s2','T-2','Sinov B',5,'A','uz','',2,'[]');
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','[]');
insert into public.staff (id, "staffId", name, position) values ('st1','IQX-T1','Sinov Zavxoz','Zavxoz');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('ia','T-1','Sinov A','2027-01',1000000,0,'pending'), ('ib','T-2','Sinov B','2027-01',1000000,0,'pending');
insert into public.fin_counterparties (id, kind, name, stir, active) values
  ('cp_bank','bank','Sinov Bank','',true), ('cp_sup','supplier','Sinov Ta''minot MChJ','',true);
set local session_replication_role = origin;
select zz.clock('2027-01-04 10:00+05');

-- ---------- (N) kassa ishlatilmaguncha ----------
select zz.chk('N0 kassa ishlatilmayapti: director_daily''da kassa bloki yo''q', (zz.daily('2027-01-04') ? 'kassa')::text || ':' || coalesce(app.kassa_daily('2027-01-04')::text, 'null'), '^false:null$');
select zz.chk('N0b moslik: kassa ishga tushmagan', app.kassa_reconcile('2026-12-01', '2027-01-04')::text, '"live": false.*"total": 0|"total": 0.*"live": false');
select zz.chk('N1 ishga tushirish: limit 3 000 000, T1 1 000 000, boshlang''ich qoldiq 2 000 000',
  left(zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-01-04","t1":1000000,"l1":200000,"cashLimit":3000000}')::text$q$), 0)
  || zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":2000000,"startDay":"2027-01-04"}')::text$q$), '"ok": true');
select zz.chk('N2 ishga tushgan, hali hujjat yo''q: blok bor, kun varag''i yo''q, qoldiq 2 000 000',
  (select (k -> 'day')::text || ':' || trim_scale((k ->> 'balance')::numeric) || ':' || (k ->> 'live') || ':' || (k -> 'control' ->> 'reconcile') from (select zz.daily('2027-01-04') -> 'kassa' as k) q),
  '^null:2000000:true:0$');

-- ---------- 1-kun: hujjatlar ----------
select zz.put('P1', zz.tui('U_KAS', 'man_r1_0001', 'T-1', 600000, 'Sinov Ota', '111'));
select zz.put('P2', zz.tui('U_KAS', 'man_r1_0002', 'T-1', 400000, 'Sinov Ona', '112'));
select zz.put('P3', zz.tui('U_KAS', 'man_r1_0003', 'T-2', 500000, 'Sinov Bobo', '113'));
select zz.chk('P1-3 uchta naqd o''quv to''lovi kirim orderi bilan', (select count(*) || ':' || trim_scale(sum(amount)) from public.cash_docs where op = 'in_tuition' and status = 'posted'), '^3:1500000$');
-- naqdsiz to'lov (Click) — kassaga kirmaydi, «kanallar» blokida ko'rinadi
set local session_replication_role = replica;
insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values
  ('clk_1', 'T-2', 'click', 300000, 'applied', true, '{}', '2027-01-04 11:00+05');
set local session_replication_role = origin;
select zz.put('K4', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_bank","amount":1000000,"partyType":"bank","partyId":"cp_bank","basis":"Chek № 12, 04.01.2027","clientRef":"r-k4-0001"}'));
select zz.put('K5', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_other","amount":50000,"partyType":"other","partyName":"Aliyev Vali","articleId":"IN-06","basis":"Tilxat, 04.01.2027","note":"Yo''qolgan kitob uchun","clientRef":"r-k5-0001"}'));
select zz.put('K6', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_other","amount":30000,"partyType":"other","partyName":"ALIYEV  vali ","articleId":"IN-06","basis":"Tilxat, 04.01.2027","note":"Yo''qolgan kitob uchun","clientRef":"r-k6-0001"}'));
select zz.put('C1', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_expense","amount":300000,"partyType":"counterparty","partyId":"cp_sup","basis":"Hisob-faktura № 5","clientRef":"r-c1-0001","lines":[{"articleId":"EX-32","amount":200000},{"articleId":"EX-07","amount":100000}]}'));
select zz.put('C1p', left(zz.appr('U_FM', zz.id('C1')), 0) || zz.pay('U_KAS', zz.id('C1')));
select zz.put('C2', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_accountable","amount":400000,"partyType":"employee","partyId":"staff:st1","basis":"Xo''jalik xaridlari uchun","clientRef":"r-c2-0001"}'));
select zz.put('C2p', left(zz.appr('U_FM', zz.id('C2')), 0) || zz.pay('U_KAS', zz.id('C2')));
select zz.put('K7', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_acc_return","amount":150000,"partyType":"employee","partyId":"staff:st1","basis":"Qaytim","clientRef":"r-k7-0001"}'));
select zz.put('C3', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_bank","amount":1500000,"partyType":"bank","partyId":"cp_bank","basis":"Inkassatsiya, 04.01.2027","clientRef":"r-c3-0001"}'));
select zz.put('C3p', left(zz.appr('U_FM', zz.id('C3')), 0) || left(zz.appr('U_DIR', zz.id('C3')), 0) || zz.pay('U_KAS', zz.id('C3')));
select zz.put('C4', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_expense","amount":50000,"partyType":"other","partyName":"Bozor sotuvchisi","noBasis":true,"clientRef":"r-c4-0001","lines":[{"articleId":"EX-07","amount":50000}]}'));
select zz.put('C4p', left(zz.appr('U_FM', zz.id('C4')), 0) || left(zz.pay('U_KAS', zz.id('C4')), 0) || zz.void('U_FM', zz.id('C4'), 'Xato kiritilgan'));
select zz.put('W1', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_expense","amount":70000,"partyType":"counterparty","partyId":"cp_sup","basis":"Hisob-faktura № 6","clientRef":"r-w1-0001","lines":[{"articleId":"EX-32","amount":70000}]}'));
select zz.put('W2', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_advance","amount":100000,"partyType":"employee","partyId":"teachers:tch1","basis":"Ariza, 04.01.2027","clientRef":"r-w2-0001"}'));
select zz.put('W2a', zz.appr('U_FM', zz.id('W2')));
select zz.chk('H1 1-kun hujjatlari: 7 kirim, 3 chiqim, 1 bekor; so''rovlar: 1 tasdiq kutmoqda, 1 berilishi kerak',
  (select count(*) filter (where form = 'KO1' and status = 'posted') || ':' || count(*) filter (where form = 'KO2' and status = 'posted') || ':' || count(*) filter (where status = 'void')
       || ':' || count(*) filter (where status = 'draft') || ':' || count(*) filter (where status = 'approved') from public.cash_docs where form <> 'ACT'), '^7:3:1:1:1$');

-- ---------- (R) kunlik hisobot ma'lumoti: ochiq kun ----------
select zz.put('B1', zz.book('main', '2027-01-04')::text);
select zz.chk('R1 ochiq kun jamlari: kirim 2 730 000, chiqim 2 200 000, qoldiq 2 530 000',
  (select trim_scale((b -> 'day' ->> 'opening')::numeric) || ':' || trim_scale((b -> 'day' ->> 'receiptsLive')::numeric) || ':' || trim_scale((b -> 'day' ->> 'payoutsLive')::numeric) || ':' || trim_scale((b -> 'day' ->> 'balance')::numeric)
     from (select zz.get('B1')::jsonb as b) q), '^2000000:2730000:2200000:2530000$');
select zz.chk('R2 «kimdan / kimga» va statiya jamlari = kun jamlari (bekor qilingan hujjat kirmaydi)',
  (select zz.sumof(b -> 'byParty', 'KO1') || ':' || zz.sumof(b -> 'byParty', 'KO2') || ':' || zz.sumof(b -> 'byArticle', 'KO1') || ':' || zz.sumof(b -> 'byArticle', 'KO2')
     from (select zz.get('B1')::jsonb as b) q), '^2730000:2200000:2730000:2200000$');
select zz.chk('R3 o''quvchi KALITI bo''yicha: ikki xil to''lovchi — bitta qator (o''quvchi nomi bilan), 2 ta hujjat',
  zz.party(zz.get('B1')::jsonb, 'KO1', 'student', 'T-1') || ' // ' || zz.party(zz.get('B1')::jsonb, 'KO1', 'student', 'T-2'),
  '^Sinov A\|2\|1000000\|\["in_tuition"\] // Sinov B\|1\|500000\|\["in_tuition"\]$');
select zz.chk('R3b «boshqa» tomon: katta-kichik harf va bo''shliq farqi — bitta qator', zz.party(zz.get('B1')::jsonb, 'KO1', 'other', null), '^A[Ll][Ii][Yy][Ee][Vv] +[Vv]ali ?\|2\|80000\|\["in_other"\]$');
select zz.chk('R3c xodim va bank — ma''lumotnomadagi nom bilan',
  zz.party(zz.get('B1')::jsonb, 'KO1', 'employee', 'staff:st1') || ' // ' || zz.party(zz.get('B1')::jsonb, 'KO1', 'bank', 'cp_bank') || ' // ' || zz.party(zz.get('B1')::jsonb, 'KO2', 'employee', 'staff:st1')
    || ' // ' || zz.party(zz.get('B1')::jsonb, 'KO2', 'counterparty', 'cp_sup') || ' // ' || zz.party(zz.get('B1')::jsonb, 'KO2', 'bank', 'cp_bank'),
  '^Sinov Zavxoz\|1\|150000\|\["in_acc_return"\] // Sinov Bank\|1\|1000000\|\["in_bank"\] // Sinov Zavxoz\|1\|400000\|\["out_accountable"\] // Sinov Ta''minot MChJ\|1\|300000\|\["out_expense"\] // Sinov Bank\|1\|1500000\|\["out_bank"\]$');
select zz.chk('R3d bekor qilingan chiqim tomoni ro''yxatda yo''q', coalesce(zz.party(zz.get('B1')::jsonb, 'KO2', 'other', null), 'yo''q'), '^yo''q$');
select zz.chk('R4 ichki o''tkazmalar: bankdan 1 ta 1 000 000, bankka 1 ta 1 500 000',
  (select (t ->> 'inCount') || ':' || trim_scale((t ->> 'inAmount')::numeric) || ':' || (t ->> 'outCount') || ':' || trim_scale((t ->> 'outAmount')::numeric) from (select zz.get('B1')::jsonb -> 'transfers' as t) q),
  '^1:1000000:1:1500000$');
select zz.chk('R4b statiya bo''yicha: o''tkazma belgisi faqat bank qatorlarida; nomlari bilan',
  (select string_agg((x ->> 'form') || ' ' || (x ->> 'articleId') || ' ' || trim_scale((x ->> 'amount')::numeric) || case when (x ->> 'transfer')::boolean then ' T' else '' end
                     || case when coalesce(x ->> 'nameUz', '') <> '' and x ->> 'kind' in ('IN', 'EX', 'OP') then '' else ' ?' end, ', '
                     order by x ->> 'form', x ->> 'articleId', x ->> 'credit', x ->> 'debit')
     from jsonb_array_elements(zz.get('B1')::jsonb -> 'byArticle') x),
  '^KO1 IN-01 1500000, KO1 IN-06 80000, KO1 OP-01 1000000 T, KO1 OP-07 150000, KO2 EX-07 100000, KO2 EX-32 200000, KO2 OP-02 1500000 T, KO2 OP-06 400000$');
select zz.chk('R5 kanallar (ma''lumot): naqd 3 ta 1 500 000 = o''quv to''lovi orderlari; Click 1 ta 300 000',
  (select string_agg((x ->> 'provider') || ' ' || (x ->> 'count') || ' ' || trim_scale((x ->> 'amount')::numeric), ', ' order by x ->> 'provider') from jsonb_array_elements(zz.get('B1')::jsonb -> 'channels') x),
  '^cash 3 1500000, click 1 300000$');
select zz.chk('R6 kutilayotganlar: tasdiq kutmoqda 1 ta 70 000; berilishi kerak 1 ta 100 000',
  (select (p ->> 'waiting') || ':' || trim_scale((p ->> 'waitingSum')::numeric) || ':' || (p ->> 'toPay') || ':' || trim_scale((p ->> 'toPaySum')::numeric) from (select zz.get('B1')::jsonb -> 'pending' as p) q),
  '^1:70000:1:100000$');
select zz.chk('R7 limit 3 000 000 — qoldiq (2 530 000) oshmagan',
  (select trim_scale((l ->> 'cashLimit')::numeric) || ':' || (l ->> 'set') || ':' || (l ->> 'exceeded') from (select zz.get('B1')::jsonb -> 'limit' as l) q), '^3000000:true:false$');
select zz.chk('R8 hujjatlar ro''yxati: bekor qilingani ham (raqami bilan) bor', (select count(*) || ':' || count(*) filter (where x ->> 'status' = 'void') from jsonb_array_elements(zz.get('B1')::jsonb -> 'docs') x), '^11:1$');

-- ---------- (D) Telegram bloki: ochiq kun ----------
select zz.put('D1', (zz.daily('2027-01-04') -> 'kassa')::text);
select zz.chk('D1 kassa bloki = kun varag''i: ochiq, 2 000 000 + 2 730 000 − 2 200 000 = 2 530 000; 7 kirim, 3 chiqim, 1 bekor',
  (select (d ->> 'status') || ':' || trim_scale((d ->> 'opening')::numeric) || ':' || trim_scale((d ->> 'receipts')::numeric) || ':' || trim_scale((d ->> 'payouts')::numeric) || ':' || trim_scale((d ->> 'closing')::numeric)
       || ':' || (d ->> 'n1') || ':' || (d ->> 'n2') || ':' || (d ->> 'voids') || ':' || coalesce(d ->> 'counted', '-')
     from (select zz.get('D1')::jsonb -> 'day' as d) q), '^open:2000000:2730000:2200000:2530000:7:3:1:-$');
select zz.chk('D1b o''tkazmalar bloki ham shu manbadan', (zz.get('D1')::jsonb -> 'day' -> 'transfers')::text, '"inAmount": 1000000.*"outAmount": 1500000|"outAmount": 1500000.*"inAmount": 1000000');
select zz.chk('D2 nazorat qatori: moslik 0, ochiq kun — bugungi (eskirgan emas), 1 tasdiq kutmoqda, 1 berilmagan, limit oshmagan',
  (select (c ->> 'reconcile') || ':' || (c ->> 'openDay') || ':' || coalesce(c ->> 'staleOpenDay', '-') || ':' || (c ->> 'waitingApproval') || ':' || (c ->> 'approvedUnpaid') || ':' || (c ->> 'voids')
       || ':' || (c ->> 'limitExceeded') || ':' || (c ->> 'unverifiedDays') || ':' || (c ->> 'gaps')
     from (select zz.get('D1')::jsonb -> 'control' as c) q), '^0:2027-01-04:-:1:1:1:false:0:0$');
select zz.chk('D3 boshqa bloklar joyida (to''lovlar: naqd + Click)', (zz.daily('2027-01-04') -> 'payments' ->> 'count') || ':' || trim_scale((zz.daily('2027-01-04') -> 'payments' ->> 'sum')::numeric), '^4:1800000$');
select zz.chk('M0 moslik — toza: hammasi 0', zz.rec(), '^true p1=0/0 p4=0/0 p5=0/0 p8=0/0 jami=0$');

-- ---------- 1-kunni yopish (kamomad 5 000) ----------
select zz.put('CL1', zz.as('U_KAS', $q$select public.kassa_day_close('{"desk":"main","day":"2027-01-04","counted":2525000}')::text$q$));
select zz.put('B2', zz.book('main', '2027-01-04')::text);
select zz.chk('R9 yopilgan kun: kirim 2 730 000, chiqim 2 205 000 (kamomad orderi bilan), kun oxiri = sanalgan = 2 525 000, farq −5 000',
  (select (d ->> 'status') || ':' || trim_scale((d ->> 'receipts')::numeric) || ':' || trim_scale((d ->> 'payouts')::numeric) || ':' || trim_scale((d ->> 'closing')::numeric) || ':' || trim_scale((d ->> 'counted')::numeric) || ':' || trim_scale((d ->> 'diff')::numeric)
     from (select zz.get('B2')::jsonb -> 'day' as d) q), '^closed:2730000:2205000:2525000:2525000:-5000$');
select zz.chk('R9b RP-02 = KO-4: tomon va statiya jamlari yopilgan kun jamlariga teng',
  (select zz.sumof(b -> 'byParty', 'KO1') || ':' || zz.sumof(b -> 'byParty', 'KO2') || ':' || zz.sumof(b -> 'byArticle', 'KO1') || ':' || zz.sumof(b -> 'byArticle', 'KO2')
     from (select zz.get('B2')::jsonb as b) q), '^2730000:2205000:2730000:2205000$');
select zz.chk('R9c tizim hujjati (kamomad) alohida «tizim» qatorida', zz.party(zz.get('B2')::jsonb, 'KO2', 'system', null), '^Kassa kamomadi\|1\|5000\|\["out_shortage"\]$');
select zz.put('D4', (zz.daily('2027-01-04') -> 'kassa')::text);
select zz.chk('D4 Telegram = kunlik hisobot (--dry = RP-02): yopilgan, jamlar, sanalgan va farq bir xil',
  (select (d ->> 'status') || ':' || trim_scale((d ->> 'receipts')::numeric) || ':' || trim_scale((d ->> 'payouts')::numeric) || ':' || trim_scale((d ->> 'closing')::numeric) || ':' || trim_scale((d ->> 'counted')::numeric) || ':' || trim_scale((d ->> 'diff')::numeric)
       || ':' || (d ->> 'n1') || ':' || (d ->> 'n2')
     from (select zz.get('D4')::jsonb -> 'day' as d) q), '^closed:2730000:2205000:2525000:2525000:-5000:7:4$');
select zz.chk('D4b nazorat qatori: farq −5 000, qarorsiz kamomad 1, tekshirilmagan kun 1, ochiq kun yo''q',
  (select trim_scale((c ->> 'diff')::numeric) || ':' || (c ->> 'undecidedShortages') || ':' || (c ->> 'unverifiedDays') || ':' || coalesce(c ->> 'openDay', '-') from (select zz.get('D4')::jsonb -> 'control' as c) q),
  '^-5000:1:1:-$');
select zz.chk('C1 nazorat: yopilgan kunning KO-4 varag''i hali chop etilmagan', (zz.checks('main') -> 'unprintedBooks30')::text, '^\["2027-01-04"\]$');
select zz.chk('C1b chop etilgach — ro''yxatdan chiqadi',
  left(zz.as('U_KAS', format('select public.kassa_print_mark(%L, %L)::text', 'book', (select id from public.cash_days where desk = 'main' and day = '2027-01-04'))), 0)
  || (zz.checks('main') -> 'unprintedBooks30')::text, '^\[\]$');
select zz.chk('C2 hisobdor: berilgan 400 000 − qaytim 150 000 = 250 000; muddat hali o''tmagan',
  (select (a ->> 'partyId') || ':' || (a ->> 'name') || ':' || trim_scale((a ->> 'given')::numeric) || ':' || trim_scale((a ->> 'returned')::numeric) || ':' || trim_scale((a ->> 'balance')::numeric) || ':' || (a ->> 'since') || ':' || (a ->> 'workDays') || ':' || (a ->> 'overdue')
     from jsonb_array_elements(zz.checks('main') -> 'accountable') a), '^staff:st1:Sinov Zavxoz:400000:150000:250000:2027-01-04:0:false$');

-- ---------- 2-kun (08.01.2027, juma) ----------
select zz.clock('2027-01-08 10:00+05');
select zz.chk('C3 hisobdor: 4 ish kuni o''tdi (se, cho, pa, ju) — muddati o''tgan',
  (select (a ->> 'workDays') || ':' || (a ->> 'overdue') from jsonb_array_elements(zz.checks('main') -> 'accountable') a), '^4:true$');
select zz.put('K8', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_bank","amount":2000000,"partyType":"bank","partyId":"cp_bank","basis":"Chek № 13, 08.01.2027","clientRef":"r-k8-0001"}'));
select zz.chk('C4 limit: qoldiq 4 525 000 > 3 000 000 — oshgan (nazorat ro''yxati, kun ma''lumoti, Telegram)',
  (zz.checks('main') -> 'limit' ->> 'exceeded') || ':' || trim_scale((zz.checks('main') -> 'limit' ->> 'balance')::numeric) || ':' || (zz.book('main', '2027-01-08') -> 'limit' ->> 'exceeded')
    || ':' || (zz.daily('2027-01-08') -> 'kassa' -> 'control' ->> 'limitExceeded'), '^true:4525000:true:true$');
select zz.put('W2p', zz.pay('U_KAS', zz.id('W2')));
select zz.put('H1', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_handover","amount":500000,"partyType":"employee","partyId":"teachers:tch1","basis":"Direktor topshirig''i","clientRef":"r-h1-0001"}'));
select zz.put('H1p', left(zz.appr('U_FM', zz.id('H1')), 0) || left(zz.appr('U_DIR', zz.id('H1')), 0) || zz.pay('U_KAS', zz.id('H1')));
select zz.chk('C5 rahbarga berilgan pul: shu oyda 1 ta 500 000',
  (select (h ->> 'monthCount') || ':' || trim_scale((h ->> 'monthSum')::numeric) || ':' || (h ->> 'earlierCount') from (select zz.checks('main') -> 'handover' as h) q), '^1:500000:0$');
-- naqd qaytarish: Direktor so'rovi → kassir beradi
select zz.put('RF', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ia","amount":100000,"reason":"sinov qaytarish","payee":"Sinov Ota Onaevich","clientRef":"rf_r1_000001"}'));
select zz.put('RFp', zz.pay('U_KAS', zz.id('RF')));
select zz.chk('H2 2-kun: avans, rahbarga berish va qaytarish o''tkazildi', (select string_agg(op || ':' || status, ',' order by no) from public.cash_docs where "businessDay" = '2027-01-08' and form = 'KO2'),
  '^out_advance:posted,out_handover:posted,out_refund:posted$');
select zz.chk('M1 moslik — hali ham toza (avans, qaytarish, xarajat bog''langan)', zz.rec(), '^true p1=0/0 p4=0/0 p5=0/0 p8=0/0 jami=0$');
select zz.put('CL2', zz.as('U_KAS', $q$select public.kassa_day_close('{"desk":"main","day":"2027-01-08","counted":3835000,"pendingCount":1,"pendingSum":10000}')::text$q$));
select zz.chk('C6 2-kun yopildi (3 825 000 + 10 000 oflayn = sanalgan); nazorat: oflayn yozuvli yopish 1 kun, limitdan oshgan yopilish 1 kun',
  (zz.get('CL2')::jsonb -> 'day' ->> 'status') || ':' || trim_scale((zz.get('CL2')::jsonb -> 'day' ->> 'closing')::numeric) || ':' || trim_scale((zz.get('CL2')::jsonb -> 'day' ->> 'diff')::numeric)
    || ':' || (zz.checks('main') ->> 'pendingDays30') || ':' || (zz.checks('main') -> 'limit' ->> 'days30'), '^closed:3825000:0:1:1$');
select zz.chk('D5 kun varag''i yo''q kunda (07.01): blok bor, kun yo''q, qoldiq — oxirgi yopilgan kun oxiri',
  (select (k -> 'day')::text || ':' || trim_scale((k ->> 'balance')::numeric) from (select zz.daily('2027-01-07') -> 'kassa' as k) q), '^null:3825000$');

-- ---------- (M) moslik: har buzilish o'z hisoblagichida ----------
set local session_replication_role = replica;
insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values
  ('cash_x1', 'T-2', 'cash', 111000, 'applied', true, '{}', '2027-01-08 09:00+05');                                   -- P1: kirim orderisiz naqd to'lov
update public.payments set status = 'canceled' where id = 'man_r1_0003';                                             -- P1: to'lovi yo'q order
insert into public.expenses (id, date, month, category, amount, note) values ('ex_x1', '2027-01-08', '2027-01', 'Boshqa', 5000, 'usulsiz');   -- P4: ordersiz naqd xarajat
delete from public.expenses where id = (select min(id) from public.expenses where "cashDocId" = zz.id('C1'));        -- P4: ko'chmagan xarajat orderi
insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date) values ('sp_x1', 'IQT-T1', 'teachers:tch1', 'Sinov', '2026-12', 1000, '2027-01-08');   -- P5: ordersiz maosh
insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date, method) values ('adv_x1', 'IQX-T1', 'staff:st1', 'Sinov', 2000, '2027-01', '2027-01-08', 'cash'); -- P5: ordersiz naqd avans
delete from public.staff_advances where "cashDocId" = zz.id('W2');                                                    -- P5: yozuvsiz avans orderi
insert into public.refunds (id, target, "targetId", "studentId", amount, reason, method, "createdAt") values ('rf_x1', 'invoice', 'ib', 'T-2', 3000, 'sinov', 'cash', '2027-01-08 09:30+05');   -- P8: ordersiz naqd qaytarish
delete from public.refunds where "cashDocId" = zz.id('RF');                                                           -- P8: yozuvsiz qaytarish orderi
set local session_replication_role = origin;
select zz.chk('M2 moslik: har buzilish alohida sanaladi (P1 1/1, P4 1/1, P5 2/1, P8 1/1 — jami 9)', zz.rec(), '^true p1=1/1 p4=1/1 p5=2/1 p8=1/1 jami=9$');
select zz.chk('M2b kirim orderisiz naqd to''lov summasi', trim_scale((zz.checks('main') -> 'reconcile' -> 'p1' ->> 'paySum')::numeric)::text, '^111000$');
select zz.chk('M3 Telegram nazorat qatori: moslik 9 (oxirgi 7 kun, ishga tushgan kundan)', zz.daily('2027-01-08') -> 'kassa' -> 'control' ->> 'reconcile', '^9$');
select zz.chk('M4 naqdsiz (karta / bank) yozuvlar moslikka kirmaydi',
  left(zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_bank_r1','2027-01-08','2027-01','Boshqa',9000,'bank orqali','bank') returning id) select id from x$q$), 0)
  || zz.rec(), '^true p1=1/1 p4=1/1 p5=2/1 p8=1/1 jami=9$');

-- ---------- (T) sinov kassasi: bog'langan yozuv yo'q (CT-20) ----------
select zz.put('T0', zz.as('U_DIR', $q$select public.kassa_opening_set('{"desk":"sinov","amount":100000,"startDay":"2027-01-08"}')::text$q$));
select zz.put('T1', zz.rpc('U_KAS', 'kassa_payout_request', '{"desk":"sinov","op":"out_expense","amount":20000,"partyType":"counterparty","partyId":"cp_sup","basis":"Sinov hujjati","clientRef":"r-t1-0001","lines":[{"articleId":"EX-07","amount":20000}]}'));
select zz.put('T1p', left(zz.appr('U_FM', zz.id('T1')), 0) || zz.pay('U_KAS', zz.id('T1')));
select zz.chk('T1 sinov kassasida xarajat orderi o''tkazildi, «Buxgalteriya»ga HECH NARSA yozilmadi',
  (zz.get('T1p')::jsonb ->> 'status') || ':' || (zz.get('T1p')::jsonb ->> 'desk') || ':' || (select count(*) from public.expenses where "cashDocId" = zz.id('T1')), '^posted:sinov:0$');
select zz.put('T2', zz.rpc('U_KAS', 'kassa_payout_request', '{"desk":"sinov","op":"out_advance","amount":10000,"partyType":"employee","partyId":"staff:st1","basis":"Sinov avansi","clientRef":"r-t2-0001"}'));
select zz.put('T2p', left(zz.appr('U_FM', zz.id('T2')), 0) || zz.pay('U_KAS', zz.id('T2')));
select zz.chk('T2 sinov kassasida avans orderi: xodim avansi jadvaliga yozilmadi',
  (zz.get('T2p')::jsonb ->> 'status') || ':' || (select count(*) from public.staff_advances where "cashDocId" = zz.id('T2')), '^posted:0$');
select zz.chk('T3 sinov kassasi hujjatini bekor qilish — bog''langan yozuvsiz ham ishlaydi', zz.void('U_FM', zz.id('T1'), 'Sinov tugadi') :: jsonb ->> 'status', '^void$');
select zz.chk('T4 sinov kassasi: kun ma''lumotida kanallar yo''q, «sinov» belgisi bor; nazoratda moslik hisoblanmaydi',
  (zz.book('sinov', '2027-01-08') -> 'channels')::text || ':' || (zz.book('sinov', '2027-01-08') ->> 'isTest') || ':' || (zz.checks('sinov') -> 'reconcile' ->> 'live') || ':' || (zz.checks('sinov') ->> 'isTest'), '^\[\]:true:false:true$');
select zz.chk('T5 asosiy kassa hisobotiga sinov kassasi aralashmaydi (Telegram bloki — faqat asosiy kassa)',
  (zz.daily('2027-01-08') -> 'kassa' -> 'day' ->> 'n2') || ':' || trim_scale((zz.daily('2027-01-08') -> 'kassa' ->> 'balance')::numeric), '^3:3825000$');

-- ---------- (G) rollar ----------
select zz.chk('G1 o''qituvchi kun ma''lumotini va nazorat ro''yxatini ko''ra olmaydi',
  zz.as('U_TCH', $q$select public.kassa_day_book('main', '2027-01-04')::text$q$) || ' | ' || zz.as('U_TCH', $q$select public.kassa_checks('main')::text$q$), '^ERR 42501.* \| ERR 42501');
select zz.chk('G2 kassir director_daily''ni chaqira olmaydi', zz.as('U_KAS', $q$select public.director_daily('2027-01-04')::text$q$), '^ERR 42501');
select zz.chk('G3 ichki funksiyalar mijozga yopiq',
  zz.as('U_DIR', $q$select app.kassa_daily('2027-01-04')::text$q$) || ' | ' || zz.as('U_DIR', $q$select app.kassa_reconcile('2027-01-01', '2027-01-08')::text$q$) || ' | '
  || zz.as('U_DIR', $q$select app.kassa_day_blocks('x')::text$q$) || ' | ' || zz.as('U_DIR', $q$select app.kassa_party_label('student', 'T-1')$q$),
  '^ERR 42501.* \| ERR 42501.* \| ERR 42501.* \| ERR 42501');
select zz.chk('G4 anon hech narsa ko''rmaydi', zz.as(null, $q$select public.kassa_checks('main')::text$q$) || ' | ' || zz.as(null, $q$select public.kassa_day_book('main', '2027-01-04')::text$q$), '^ERR 42501.* \| ERR 42501');
select zz.chk('G5 kassir kun ma''lumotini ko''radi (kunlik hisobot — kassir hisoboti)', zz.as('U_KAS', $q$select (public.kassa_day_book('main', '2027-01-04') -> 'day' ->> 'status')$q$), '^closed$');

-- ---------- (AV) avans hisoboti (АО-1, minimal) va «hisobotsiz yangi avans yo'q» qoidasi ----------
select zz.clock('2027-01-11 10:00+05');   -- dushanba (3-kun): hisobdorda 1-kundan 250 000 hisobot qilinmagan
select zz.put('AVt0', zz.rec());   -- moslik hisoblagichlari shu nuqtada (avvalgi bo'limlardan): AV bo'limi ularni o'zgartirmasligi kerak
select zz.chk('AV0 boshlang''ich holat: hisobdorda 250 000, 5 ish kuni o''tgan — muddati o''tgan',
  (select trim_scale((a ->> 'balance')::numeric) || ':' || (a ->> 'overdue') from jsonb_array_elements(zz.checks('main') -> 'accountable') a where a ->> 'partyId' = 'staff:st1'), '^250000:true$');
select zz.chk('AV1 kassir va o''qituvchi avans hisobotini kirita olmaydi',
  zz.rpc('U_KAS', 'kassa_adv_report', '{"clientRef":"av-r1-0001","partyId":"staff:st1","reportDate":"2027-01-11","lines":[{"articleId":"EX-20","amount":100000,"note":"Chek 15"}]}') || ' | '
  || zz.rpc('U_TCH', 'kassa_adv_report', '{"clientRef":"av-r1-0002","partyId":"staff:st1","reportDate":"2027-01-11","lines":[{"articleId":"EX-20","amount":100000,"note":"Chek 15"}]}'),
  '^ERR 42501.* \| ERR 42501');
select zz.chk('AV2 rad: ish haqi statiyasi, cheksiz qator, kelajak sana, qoldiqdan katta summa, avansi yo''q xodim',
  zz.rpc('U_FM', 'kassa_adv_report', '{"clientRef":"av-r2-0001","partyId":"staff:st1","reportDate":"2027-01-11","lines":[{"articleId":"EX-01","amount":100000,"note":"Chek 15"}]}') || ' | '
  || zz.rpc('U_FM', 'kassa_adv_report', '{"clientRef":"av-r2-0002","partyId":"staff:st1","reportDate":"2027-01-11","lines":[{"articleId":"EX-20","amount":100000,"note":""}]}') || ' | '
  || zz.rpc('U_FM', 'kassa_adv_report', '{"clientRef":"av-r2-0003","partyId":"staff:st1","reportDate":"2027-01-12","lines":[{"articleId":"EX-20","amount":100000,"note":"Chek 15"}]}') || ' | '
  || zz.rpc('U_FM', 'kassa_adv_report', '{"clientRef":"av-r2-0004","partyId":"staff:st1","reportDate":"2027-01-11","lines":[{"articleId":"EX-20","amount":200000,"note":"Chek 15"},{"articleId":"EX-16","amount":60000,"note":"Chek 16"}]}') || ' | '
  || zz.rpc('U_FM', 'kassa_adv_report', '{"clientRef":"av-r2-0005","partyId":"teachers:tch1","reportDate":"2027-01-11","lines":[{"articleId":"EX-20","amount":1000,"note":"Chek 1"}]}'),
  '^ERR 22023 \[kassa:article\].* \| ERR 22023 \[kassa:note\].* \| ERR 22023 \[kassa:basis\].* \| ERR P0001 \[kassa:acc_over\].* \| ERR P0001 \[kassa:acc_none\]');
select zz.put('AV3', zz.rpc('U_FM', 'kassa_adv_report', '{"clientRef":"av-r3-0001","partyId":"staff:st1","reportDate":"2027-01-10","basis":"Oziq-ovqat xaridi","lines":[{"articleId":"EX-20","amount":150000,"note":"Chek 15, 09.01"},{"articleId":"EX-16","amount":50000,"note":"Chek 16, 09.01"}]}'));
select zz.chk('AV3 avans hisoboti: naqdsiz dalolatnoma, Dt 1010 / 2010 Kt 4230, hisobdordagi qoldiq 250 000 → 50 000',
  (zz.get('AV3')::jsonb ->> 'form') || ':' || (zz.get('AV3')::jsonb ->> 'op') || ':' || (zz.get('AV3')::jsonb ->> 'status') || ':' || trim_scale((zz.get('AV3')::jsonb ->> 'amount')::numeric)
  || ':' || (select string_agg((l ->> 'debit') || '>' || (l ->> 'credit') || '=' || trim_scale((l ->> 'amount')::numeric) || '@' || (l ->> 'articleId'), ',' order by (l ->> 'lineNo')::int)
               from jsonb_array_elements(zz.get('AV3')::jsonb -> 'lines') l)
  || ':' || trim_scale((zz.get('AV3')::jsonb ->> 'openBefore')::numeric) || '>' || trim_scale((zz.get('AV3')::jsonb ->> 'openAfter')::numeric),
  '^ACT:nc_adv_report:posted:200000:1010>4230=150000@EX-20,2010>4230=50000@EX-16:250000>50000$');
select zz.chk('AV4 «Buxgalteriya»ga 2 ta xarajat ko''chdi: usul «hisobdor orqali», hujjatga bog''langan, toifa statiyadan; kassa kitobiga kirmaydi',
  (select string_agg(e.category || ':' || trim_scale(e.amount) || ':' || e.method || ':' || e."articleId", ',' order by e.id) from public.expenses e where e."cashDocId" = zz.id('AV3'))
  || ' | ' || (select count(*) from public.cash_doc_lines l where l."docId" = zz.id('AV3') and l.cash),
  '^Oziq-ovqat:150000:accountable:EX-20,Xo‘jalik tovarlari:50000:accountable:EX-16 \| 0$');
select zz.chk('AV5 nazorat: berilgan 400 000 − qaytim 150 000 − hisobot 200 000 = 50 000; p4.adv = 0, boshqa moslik hisoblagichlari o''zgarmagan',
  (select trim_scale((a ->> 'given')::numeric) || ':' || trim_scale((a ->> 'returned')::numeric) || ':' || trim_scale((a ->> 'reported')::numeric) || ':' || trim_scale((a ->> 'balance')::numeric)
     from jsonb_array_elements(zz.checks('main') -> 'accountable') a where a ->> 'partyId' = 'staff:st1')
  || ':' || (zz.checks('main') -> 'reconcile' -> 'p4' ->> 'adv') || ':' || (zz.rec() = zz.get('AVt0'))::text,
  '^400000:150000:200000:50000:0:true$');
select zz.chk('AV6 qayta yuborish — o''sha hujjat (dup), ikkinchi dalolatnoma yo''q',
  (zz.rpc('U_FM', 'kassa_adv_report', '{"clientRef":"av-r3-0001","partyId":"staff:st1","reportDate":"2027-01-10","basis":"Oziq-ovqat xaridi","lines":[{"articleId":"EX-20","amount":150000,"note":"Chek 15, 09.01"},{"articleId":"EX-16","amount":50000,"note":"Chek 16, 09.01"}]}')::jsonb ->> 'dup')
  || ':' || (select count(*) from public.cash_docs where op = 'nc_adv_report'), '^true:1$');
select zz.chk('AV7 «Buxgalteriya»da qo''lda «hisobdor orqali» xarajat — rad; bank xarajati — avvalgidek; uni «hisobdor»ga o''zgartirish — rad',
  zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_av7', '2027-01-11', '2027-01', 'Oziq-ovqat', 1000, 'qo''lda', 'accountable') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_av7b', '2027-01-11', '2027-01', 'Bank', 1000, 'bank', 'bank') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (update public.expenses set method = 'accountable' where id = 'ex_av7b' returning id) select id from x$q$),
  '^ERR 42501 \[kassa:cash_only_kassa\].* \| ex_av7b \| ERR 42501 \[kassa:cash_only_kassa\]');
select zz.put('AV8', zz.as('U_KAS', format('select public.kassa_adv_report_void(%L, %L)::text', zz.id('AV3'), 'Xato kiritilgan hisobot')) || ' | '
  || zz.as('U_FM', format('select public.kassa_adv_report_void(%L, %L)::text', zz.id('AV3'), 'xx')) || ' | '
  || (zz.as('U_FM', format('select public.kassa_adv_report_void(%L, %L)::text', zz.id('AV3'), 'Xato kiritilgan hisobot'))::jsonb ->> 'status') || ':'
  || (zz.as('U_FM', format('select public.kassa_adv_report_void(%L, %L)::text', zz.id('AV3'), 'Xato kiritilgan hisobot'))::jsonb ->> 'dup'));
select zz.chk('AV8 bekor qilish: kassir — rad, sababsiz — rad; Moliya menejeri — xarajatlar olib tashlanadi, qoldiq 250 000 ga qaytadi; qayta — dup',
  zz.get('AV8') || ' | ' || (select count(*) from public.expenses where "cashDocId" = zz.id('AV3')) || ':'
  || (select trim_scale((a ->> 'balance')::numeric) from jsonb_array_elements(zz.checks('main') -> 'accountable') a where a ->> 'partyId' = 'staff:st1'),
  '^ERR 42501.* \| ERR 22023 \[kassa:reason\].* \| void:true \| 0:250000$');
select zz.put('AV9', zz.rpc('U_FM', 'kassa_adv_report', '{"clientRef":"av-r9-0001","partyId":"staff:st1","reportDate":"2027-01-11","lines":[{"articleId":"EX-20","amount":200000,"note":"Cheklar 15-16, 09.01"}]}'));
select zz.put('AV10', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_accountable","amount":100000,"partyType":"employee","partyId":"staff:st1","basis":"Xo''jalik xaridlari uchun","clientRef":"av-c10-0001"}'));
select zz.chk('AV10 hisobotsiz qoldiq (50 000) bor — yangi avans so''rovi Direktor tasdig''ini ham talab qiladi (T1 dan kichik bo''lsa ham)',
  (zz.get('AV9')::jsonb ->> 'status') || ':' || (zz.get('AV10')::jsonb ->> 'needsDirector') || ':' || trim_scale((zz.get('AV10')::jsonb ->> 'accOpen')::numeric) || ':' || (zz.get('AV10')::jsonb ->> 'status'),
  '^posted:true:50000:draft$');
select zz.chk('AV11 faqat moliya tasdig''i bilan — hali tasdiqlanmagan (Direktor kutilmoqda), pul berilmaydi',
  left(zz.appr('U_FM', zz.id('AV10')), 0) || zz.pay('U_KAS', zz.id('AV10')), '^ERR 42501 \[kassa:not_approved\]');
select zz.put('AV12', (left(zz.appr('U_DIR', zz.id('AV10')), 0) || zz.pay('U_KAS', zz.id('AV10')))::jsonb ->> 'status');
select zz.chk('AV12 Direktor tasdig''i bilan — to''lov o''tadi (istisno); qoldiq 50 000 + 100 000 = 150 000',
  zz.get('AV12') || ':' || (select trim_scale(app.kassa_acc_open('staff:st1'))), '^posted:150000$');
select zz.put('AV13a', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_accountable","amount":50000,"partyType":"employee","partyId":"teachers:tch1","basis":"Kanselyariya xaridi","clientRef":"av-c13-0001"}'));
select zz.put('AV13b', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_accountable","amount":60000,"partyType":"employee","partyId":"teachers:tch1","basis":"Kanselyariya xaridi 2","clientRef":"av-c13-0002"}'));
select zz.put('AV13', left(zz.appr('U_FM', zz.id('AV13a')), 0) || left(zz.appr('U_FM', zz.id('AV13b')), 0)
  || (zz.pay('U_KAS', zz.id('AV13a'))::jsonb ->> 'status') || ' | ' || zz.pay('U_KAS', zz.id('AV13b')));
select zz.chk('AV13 ikki tasdiqlangan so''rov (qoldiq yo''q edi): birinchisi beriladi, ikkinchisi — oldingisi hisobotsiz, Direktor tasdig''isiz rad',
  zz.get('AV13') || ' | ' || (zz.get('AV13a')::jsonb ->> 'needsDirector') || ':' || (zz.get('AV13b')::jsonb ->> 'needsDirector'),
  '^posted \| ERR 42501 \[kassa:acc_open\].*Direktorga bormagan.* \| false:false$');
select zz.chk('AV14 moslik: avans hisobotlari va xarajatlar mos (p4.adv = 0), boshqa hisoblagichlar o''zgarmagan',
  (zz.checks('main') -> 'reconcile' -> 'p4' ->> 'adv') || ':' || (zz.rec() = zz.get('AVt0'))::text || ' [' || zz.rec() || ']', '^0:true ');
savepoint av_m;
set local session_replication_role = replica;
delete from public.expenses where "cashDocId" = zz.id('AV9');
set local session_replication_role = origin;
select (zz.checks('main') -> 'reconcile' -> 'p4' ->> 'adv') as av_m_adv \gset
rollback to savepoint av_m;
select zz.chk('AV15 moslik buzilishni topadi: hisobot xarajatlarisiz qolsa — p4.adv = 1', :'av_m_adv', '^1$');
select zz.chk('AV16 ichki funksiya mijozga yopiq', zz.as('U_DIR', $q$select app.kassa_acc_open('staff:st1')::text$q$), '^ERR 42501');

-- ---------- (Z) onlayn kassa (NKM) Z-hisoboti (F1.26, buxgalter ko'rigi M6) ----------
select zz.clock('2027-01-11 18:00+05');
select zz.chk('Z0 1-kun: fiskal chekli kirim bor, Z-hisobot kiritilmagan — izohsiz tekshirilmaydi',
  zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-04', true)::text$q$), '^ERR 22023 \[kassa:z_note\].*kiritilmagan');
select zz.chk('Z1 rad: o''qituvchi; raqamsiz Z; manfiy summa; noto''g''ri sana',
  zz.rpc('U_TCH', 'kassa_day_z', '{"day":"2027-01-04","z":{"no":"1","cash":0,"card":0}}') || ' | '
  || zz.rpc('U_KAS', 'kassa_day_z', '{"day":"2027-01-04","z":{"no":"","cash":0,"card":0}}') || ' | '
  || zz.rpc('U_KAS', 'kassa_day_z', '{"day":"2027-01-04","z":{"no":"Z-1","cash":-5,"card":0}}') || ' | '
  || zz.rpc('U_KAS', 'kassa_day_z', '{"day":"2027-02-30","z":{"no":"Z-1","cash":0,"card":0}}'),
  '^ERR 42501.* \| ERR 22023 \[kassa:z\].* \| ERR 22023 \[kassa:amount\].* \| ERR 22023 \[kassa:bad_input\]');
select zz.chk('Z2a 1-kun: kutilgan naqd — fiskal chekli kirim orderlari (3 ta, 1 500 000), karta 0',
  (select trim_scale((z ->> 'expCash')::numeric) || '/' || (z ->> 'nCash') || ':' || trim_scale((z ->> 'expCard')::numeric) || '/' || (z ->> 'nCard')
     from (select app.kassa_z_state('cd_main_2027-01-04') z) q), '^1500000/3:0/0$');
select zz.put('Z2', zz.rpc('U_KAS', 'kassa_day_z', '{"day":"2027-01-04","z":{"no":"Z-0104","cash":1500000,"card":0}}'));
select zz.chk('Z2 kassir Z-hisobotni keyin kiritdi: tizim bilan mos (farq 0)',
  (select (z ->> 'recorded') || ':' || (z ->> 'ok') || ':' || trim_scale((z ->> 'diffCash')::numeric) || ':' || trim_scale((z ->> 'diffCard')::numeric) || ':' || (j ->> 'dup')
     from (select zz.get('Z2')::jsonb j, zz.get('Z2')::jsonb -> 'day' -> 'z' z) q), '^true:true:0:0:false$');
select zz.chk('Z2b aynan o''sha ma''lumot qayta yuborilsa — yangi yozuv yo''q (dup)',
  zz.rpc('U_KAS', 'kassa_day_z', '{"day":"2027-01-04","z":{"no":"Z-0104","cash":1500000,"card":0}}')::jsonb ->> 'dup', '^true$');
select zz.chk('Z2c kun jurnalida bitta Z yozuvi (kim kiritgani bilan)',
  (select count(*) || ':' || min(e."byUid") from public.cash_day_events e where e."dayId" = 'cd_main_2027-01-04' and e.kind = 'zreport'), '^1:U_KAS$');
select zz.chk('Z3 Z mos — izohsiz tekshirildi', zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-04', true)::text$q$), '"status": "verified"');
select zz.chk('Z4 tekshirilgan kunning Z-hisoboti o''zgarmaydi', zz.rpc('U_KAS', 'kassa_day_z', '{"day":"2027-01-04","z":{"no":"Z-9","cash":0,"card":0}}'), '^ERR P0001 \[kassa:verified\]');
select zz.chk('Z5 2-kun (08.01): fiskal kirim va terminal to''lovi yo''q — Z talab qilinmaydi, izohsiz tekshirildi',
  (app.kassa_z_state('cd_main_2027-01-08') ->> 'needed') || ' | ' || (zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-08', true)::text$q$)::jsonb -> 'day' ->> 'status'),
  '^false \| verified$');
-- 3-kun (11.01, ochiq): fiskal chekli naqd o'quv to'lovi va terminal to'lovi; bekor qilingan terminal va Click — hisobga kirmaydi
select zz.put('Zt1', zz.tui('U_KAS', 'man_z_0001', 'T-2', 300000, 'Sinov Bobo', '211'));
set local session_replication_role = replica;
insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values
  ('trm_z1', 'T-1', 'terminal', 150000, 'applied', true, '{}', '2027-01-11 12:00+05'),
  ('trm_z2', 'T-1', 'terminal', 70000, 'canceled', true, '{}', '2027-01-11 12:10+05'),
  ('clk_z1', 'T-2', 'click', 90000, 'applied', true, '{}', '2027-01-11 12:20+05');
set local session_replication_role = origin;
select zz.chk('Z6 ochiq kunda: Z kerak, hali kiritilmagan; kutilgan summalar ko''rsatilmaydi (kassir Z dagi raqamni yozadi)',
  (select (z ->> 'needed') || ':' || (z ->> 'recorded') || ':' || (z ? 'expCash')::text || ':' || (z ? 'diffCash')::text
     from (select app.kassa_day_json('cd_main_2027-01-11') -> 'z' as z) q), '^true:false:false:false$');
select zz.put('Z7', zz.rpc('U_KAS', 'kassa_day_close', format('{"desk":"main","day":"2027-01-11","counted":%s,"z":{"no":"","cash":290000,"card":150000}}',
                                                             (select app.kassa_day_balance('cd_main_2027-01-11')))));
select zz.chk('Z7 noto''g''ri Z bilan kun yopilmaydi (raqamsiz)', zz.get('Z7') || ' | ' || (select status from public.cash_days where id = 'cd_main_2027-01-11'),
  '^ERR 22023 \[kassa:z\].* \| open$');
select zz.put('Z8', zz.rpc('U_KAS', 'kassa_day_close', format('{"desk":"main","day":"2027-01-11","counted":%s,"z":{"no":"Z-0111","cash":290000,"card":150000}}',
                                                             (select app.kassa_day_balance('cd_main_2027-01-11')))));
select zz.chk('Z8 kun Z bilan yopildi: naqd 10 000 kam (tizimda 300 000, 1 chek), karta mos (150 000, 1 ta)',
  (select (j -> 'day' ->> 'status') || ':' || (z ->> 'recorded') || ':' || (z ->> 'ok') || ':' || trim_scale((z ->> 'expCash')::numeric) || '/' || (z ->> 'nCash')
          || ':' || trim_scale((z ->> 'expCard')::numeric) || '/' || (z ->> 'nCard') || ':' || trim_scale((z ->> 'diffCash')::numeric) || ':' || trim_scale((z ->> 'diffCard')::numeric)
     from (select zz.get('Z8')::jsonb j, zz.get('Z8')::jsonb -> 'day' -> 'z' z) q), '^closed:true:false:300000/1:150000/1:-10000:0$');
select zz.chk('Z8b kunlik hisobot ma''lumotida Z (raqami, summalari)',
  (select (z ->> 'no') || ':' || trim_scale((z ->> 'cash')::numeric) || ':' || trim_scale((z ->> 'card')::numeric) from (select zz.book('main', '2027-01-11') -> 'day' -> 'z' z) q),
  '^Z-0111:290000:150000$');
select zz.chk('Z9 nazorat ro''yxati: tekshirilmagan kundagi Z farqi',
  (select string_agg((x ->> 'day') || ':' || (x ->> 'recorded') || ':' || trim_scale((x ->> 'diffCash')::numeric) || ':' || trim_scale((x ->> 'diffCard')::numeric), ',')
     from jsonb_array_elements(zz.checks('main') -> 'zreport') x), '^2027-01-11:true:-10000:0$');
select zz.chk('Z10 Telegram kassa bloki: shu kun Z farqi',
  (select (z ->> 'ok') || ':' || (z ->> 'recorded') || ':' || trim_scale((z ->> 'diffCash')::numeric) from (select app.kassa_daily('2027-01-11') -> 'control' -> 'z' as z) q),
  '^false:true:-10000$');
select zz.chk('Z11 Z mos emas: izohsiz tekshirilmaydi; izoh bilan — tekshirildi',
  zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-11', true)::text$q$) || ' | '
  || (zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-11', true, 'Bitta chek qaytarilgan, dalolatnoma bor')::text$q$)::jsonb -> 'day' ->> 'status'),
  '^ERR 22023 \[kassa:z_note\].*mos emas.* \| verified$');
select zz.chk('Z11b tekshirilgan kun nazorat ro''yxatidan tushdi', jsonb_array_length(zz.checks('main') -> 'zreport')::text, '^0$');
-- 4-kun (12.01): «Z-hisobot yo'q» — faqat sabab bilan
select zz.clock('2027-01-12 10:00+05');
select zz.put('Zt2', zz.tui('U_KAS', 'man_z_0002', 'T-1', 100000, 'Sinov Ota', '212'));
select zz.put('Z12a', zz.rpc('U_KAS', 'kassa_day_close', format('{"desk":"main","day":"2027-01-12","counted":%s,"z":{"missing":true,"reason":"xx"}}',
                                                               (select app.kassa_day_balance('cd_main_2027-01-12')))));
select zz.put('Z12', zz.rpc('U_KAS', 'kassa_day_close', format('{"desk":"main","day":"2027-01-12","counted":%s,"z":{"missing":true,"reason":"Kassa apparati ishlamadi"}}',
                                                              (select app.kassa_day_balance('cd_main_2027-01-12')))));
select zz.chk('Z12 «Z-hisobot yo''q» sababsiz — rad; sabab bilan — kun yopildi, Z «yo''q»',
  zz.get('Z12a') || ' | ' || (select (j -> 'day' ->> 'status') || ':' || (z ->> 'missing') || ':' || (z ->> 'ok') || ':' || coalesce(z ->> 'reason', '')
                                from (select zz.get('Z12')::jsonb j, zz.get('Z12')::jsonb -> 'day' -> 'z' z) q),
  '^ERR 22023 \[kassa:z\].* \| closed:true:false:Kassa apparati ishlamadi$');
select zz.chk('Z13 «yo''q» deb belgilangan Z: izohsiz tekshirilmaydi; izoh bilan — tekshirildi',
  zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-12', true)::text$q$) || ' | '
  || (zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-12', true, 'Apparat ta''mirda, servis dalolatnomasi bor')::text$q$)::jsonb -> 'day' ->> 'status'),
  '^ERR 22023 \[kassa:z_note\].*yo''q deb belgilangan.* \| verified$');
-- 5-kun (13.01): fiskal kirim ham, terminal ham yo'q — Z so'ralmaydi
select zz.clock('2027-01-13 10:00+05');
select zz.put('Zt3', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_other","amount":20000,"partyType":"other","partyName":"Sinov Mehmon","articleId":"IN-06","basis":"Tilxat, 13.01.2027","note":"Sinov","clientRef":"z-k3-0001"}'));
select zz.put('Z14', zz.rpc('U_KAS', 'kassa_day_close', format('{"desk":"main","day":"2027-01-13","counted":%s}', (select app.kassa_day_balance('cd_main_2027-01-13')))));
select zz.chk('Z14 Z talab qilinmaydigan kun Z siz yopildi va izohsiz tekshirildi',
  (select (j -> 'day' ->> 'status') || ':' || (z ->> 'needed') || ':' || (z ->> 'recorded') || ':' || (z ->> 'ok') from (select zz.get('Z14')::jsonb j, zz.get('Z14')::jsonb -> 'day' -> 'z' z) q)
  || ' | ' || (zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-13', true)::text$q$)::jsonb -> 'day' ->> 'status'),
  '^closed:false:false:true \| verified$');
select zz.chk('Z15 sinov kassasida Z-hisobot yuritilmaydi',
  zz.rpc('U_KAS', 'kassa_day_z', '{"desk":"sinov","day":"2027-01-08","z":{"no":"Z-1","cash":0,"card":0}}') || ' | ' || (app.kassa_z_state('cd_sinov_2027-01-08') ->> 'applies'),
  '^ERR 22023 \[kassa:z\].*Sinov kassasida.* \| false$');
select zz.chk('Z16 ichki Z funksiyalari mijozga yopiq',
  zz.as('U_DIR', $q$select app.kassa_z_state('cd_main_2027-01-11')::text$q$) || ' | ' || zz.as('U_DIR', $q$select app.kassa_z_put('cd_main_2027-01-11', '{}'::jsonb, 'U_DIR')::text$q$),
  '^ERR 42501.* \| ERR 42501');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
