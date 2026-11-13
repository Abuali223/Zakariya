-- =====================================================================
-- test-kassa-pay.sql — moliya ish rejasi 1a-bosqichi, F1.4 (kassa-pay.sql + fin-prereq.sql record_manual_payment) sinovi:
--   naqd o'quv to'lovi kassa ishga tushgach SHU TRANZAKSIYADA kassa kirim orderi (KO-1) bilan yoziladi;
--   KO-1 qatorlari to'lov taqsimotidan: Kt 4010 (boshlangan davr), Kt 6310 (kelgusi oy, ortiqcha), naqdsiz Dt 6310 Kt 4010
--   (qo'llangan eski avans); fiskal chek № majburiy; faqat kassa rollari; order o'tmasa to'lov ham yozilmaydi (atomar);
--   qayta yuborish — takror; oflayn yozuv; eski «pending» qatorni tugatish.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-pay.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) then
    raise exception 'test-kassa-pay.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
-- Qo'lda to'lov: (uid, payId, o'quvchi, summa, usul, to'lovchi, olingan payt, qo'shimcha JSON)
create or replace function zz.pay(p_uid text, p_id text, p_sid text, p_amount numeric, p_method text, p_payer text, p_cap text, p_extra text) returns text language sql as $$
  select zz.as(p_uid, format('select public.record_manual_payment(%L, %L, %s, %L, null, %L, %L, %L, %s, %s)::text',
                             p_id, p_sid, p_amount, p_method, '', '', p_payer,
                             case when p_cap is null then 'null' else quote_literal(p_cap) || '::timestamptz' end,
                             case when p_extra is null then 'null' else quote_literal(p_extra) || '::jsonb' end)) $$;
-- Qo'lda to'lov «Sana» bilan (qurilma navbati ham shunday yuboradi): (uid, payId, o'quvchi, summa, usul, sana, olingan payt, qo'shimcha JSON)
create or replace function zz.payd(p_uid text, p_id text, p_sid text, p_amount numeric, p_method text, p_date text, p_cap text, p_extra text) returns text language sql as $$
  select zz.as(p_uid, format('select public.record_manual_payment(%L, %L, %s, %L, %s, %L, %L, %L, %s, %s)::text',
                             p_id, p_sid, p_amount, p_method, case when p_date is null then 'null' else quote_literal(p_date) end, '', '', '',
                             case when p_cap is null then 'null' else quote_literal(p_cap) || '::timestamptz' end,
                             case when p_extra is null then 'null' else quote_literal(p_extra) || '::jsonb' end)) $$;
create or replace function zz.lines(p_pay text) returns text language sql as $$
  select string_agg(l.debit || '>' || l.credit || '=' || trim_scale(l.amount) || case when l.cash then '' else '(naqdsiz)' end
                    || coalesce('@' || (l.analytics ->> 'month'), '') || coalesce('#' || (l.analytics ->> 'kind'), ''), ', ' order by l."lineNo")
    from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id
   where c."sourceTable" = 'payments' and c."sourceId" = p_pay and c.status = 'posted' $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles") values
  ('U_DIR','d@x','director','active','[]'), ('U_FM','f@x','finance_mgr','active','[]'), ('U_KAS','k@x','kassir','active','[]'),
  ('U_TCH','t@x','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]'), ('s2','T-2','Sinov B',5,'A','uz','',2,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('ia','T-1','Sinov A','2026-12',1000000,0,'pending'), ('ib','T-1','Sinov A','2027-01',1000000,0,'pending'),
  ('ic','T-1','Sinov A','2027-02',1000000,0,'pending');
set local session_replication_role = origin;
select zz.clock('2027-01-03 16:00+05');   -- ishga tushirishdan bir kun oldin

-- ---------- Kassa ishga tushguncha: avvalgidek ----------
select zz.put('J1', zz.pay('U_KAS', 'man_j1_0001', 'T-1', 100000, 'cash', 'Sinov Ota', null, null));
select zz.chk('J1 kassa ishga tushmagan: naqd to''lov avvalgidek, KO-1 siz', zz.get('J1'), '"ok": true.*"kassa": null|"kassa": null.*"ok": true');
select zz.chk('J1b to''lov qo''llandi, kassa hujjati yo''q',
  (select status || ':' || coalesce("cashDocId", '-') from public.payments where id = 'man_j1_0001') || ':' || (select count(*) from public.cash_docs), '^applied:-:0$');
select zz.chk('J1c ishga tushadigan kun kassa orderisiz naqd to''lov yozilgan kunga qo''yilmaydi; sozlama o''zgarmaydi',
  zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-01-03"}')::text$q$) || ' | ' || coalesce((select "kassaGoLive"::text from public.fin_org where id = 'main'), 'bo''sh'),
  '^ERR P0001 \[kassa:live_gap\].*o''quv to''lovi: 1.* \| bo''sh$');
select zz.clock('2027-01-04 10:00+05');

-- ---------- Ishga tushirish ----------
select zz.chk('J2 Direktor kassani 04.01.2027 dan ishga tushirdi', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-01-04"}')::text$q$), '"kassaGoLive": "2027-01-04"');
select zz.chk('J2a boshlang''ich qoldiq kiritilmaguncha naqd to''lov rad (to''lov ham yozilmaydi)',
  zz.pay('U_KAS', 'man_j2_0001', 'T-1', 1000, 'cash', '', null, '{"fiscalNo":"F-0"}') || ' / ' , '^ERR P0001 \[kassa:not_started\]');
select zz.chk('J2b atomar: rad etilgan to''lovdan iz yo''q',
  (select count(*)::text from public.payments where id = 'man_j2_0001') || '/' || (select count(*)::text from public.applied_payments where id = 'man_j2_0001')
  || '/' || (select trim_scale("paidAmount")::text from public.invoices where id = 'ia'), '^0/0/100000$');
select zz.chk('J2c boshlang''ich qoldiq 0', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":0,"startDay":"2027-01-04"}')::text$q$), '"ok": true');
select zz.chk('J2d fiskal chek raqamisiz naqd to''lov rad', zz.pay('U_KAS', 'man_j2_0002', 'T-1', 1000, 'cash', '', null, null), '^ERR 22023 \[kassa:fiscal\]');
select zz.chk('J2e atomar: iz yo''q', (select count(*)::text from public.payments where id = 'man_j2_0002') || '/' || (select count(*)::text from public.cash_docs where op = 'in_tuition'), '^0/0$');

-- ---------- crit-1: kassa ishga tushishidan OLDINGI kunning naqd puli (boshlang'ich qoldiq sanashiga kirgan), keyin kelgan ----------
--   Bugun 04.01 10:00 (ishga tushish kuni). Kassa qo'llanadimi — to'lovning O'Z kuni bo'yicha: oldingi kun puli — KO-1 siz va fiskal
--   cheksiz; kassir — faqat ishga tushishdan oldin qurilma navbatiga yozilgan, 48 soatdan eski bo'lmagan to'lov; qolgani — Direktor.
--   Alohida o'quvchi (T-6) — boshqa tekshiruvlar fakturalariga ta'sir qilmaydi.
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values ('s6','T-6','Sinov F',5,'A','uz','',6,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values ('i6','T-6','Sinov F','2026-12',1000000,0,'pending');
set local session_replication_role = origin;
select zz.put('PL1', zz.payd('U_KAS', 'man_pl1_0001', 'T-6', 300000, 'cash', '2027-01-03', '2027-01-03 16:00+05', null));
select zz.chk('PL1 kassir: qurilma navbatidan (03.01 16:00 da olingan, 48 soatdan eski emas) — KO-1 siz, fiskal cheksiz; kun — 03.01',
  (zz.get('PL1')::jsonb ->> 'ok') || ':' || coalesce(zz.get('PL1')::jsonb ->> 'kassa', 'null') || ':' || (zz.get('PL1')::jsonb ->> 'day'), '^true:null:2027-01-03$');
select zz.chk('PL1b to''lov qo''llandi (faktura 300 000), raw.date o''zgarmadi, kassa hujjati ham, kassa kuni ham ochilmadi',
  (select status || ':' || coalesce("cashDocId", '-') || ':' || (raw ->> 'date') from public.payments where id = 'man_pl1_0001') || ':'
  || (select trim_scale("paidAmount")::text from public.invoices where id = 'i6') || ':' || (select count(*) from public.cash_docs where "sourceId" = 'man_pl1_0001')
  || ':' || (select count(*) from public.cash_days), '^applied:-:2027-01-03:300000:0:0$');
select zz.chk('PL1c qayta yuborish (o''sha payId) — takror, KO-1 yo''q', zz.payd('U_KAS', 'man_pl1_0001', 'T-6', 300000, 'cash', '2027-01-03', '2027-01-03 16:00+05', null),
  '"dup": true.*"kassa": null|"kassa": null.*"dup": true');
select zz.chk('PL2 kassir: 48 soatdan oldin olingan (01.01 09:00) — faqat Direktor; to''lov yozilmadi',
  zz.payd('U_KAS', 'man_pl2_0001', 'T-6', 10000, 'cash', '2027-01-01', '2027-01-01 09:00+05', '{"fiscalNo":"F-PL2"}') || ' / ' || (select count(*) from public.payments where id = 'man_pl2_0001'),
  '^ERR 42501 \[kassa:pre_live\].* / 0$');
select zz.chk('PL3 kassir: oldingi «Sana» bilan, navbatsiz (olingan payt yo''q) va bugun olingan — faqat Direktor (KO-1 qoidasini chetlab o''tib bo''lmaydi)',
  zz.payd('U_KAS', 'man_pl3_0001', 'T-6', 10000, 'cash', '2027-01-02', null, null) || ' | ' || zz.payd('U_KAS', 'man_pl3_0002', 'T-6', 10000, 'cash', '2027-01-02', '2027-01-04 09:50+05', null),
  '^ERR 42501 \[kassa:pre_live\].* \| ERR 42501 \[kassa:pre_live\]');
select zz.chk('PL3b kassir: «Sana» olingan kundan keyin (navbatdagi yozuv 02.01 da olingan, sana 03.01) — faqat Direktor',
  zz.payd('U_KAS', 'man_pl3_0003', 'T-6', 10000, 'cash', '2027-01-03', '2027-01-02 12:00+05', null), '^ERR 42501 \[kassa:pre_live\]');
select zz.chk('PL4 Moliya menejeri (kassa operatori emas): o''z navbatidagi 03.01 yozuvi ham — faqat Direktor',
  zz.payd('U_FM', 'man_pl4_0001', 'T-6', 10000, 'cash', '2027-01-03', '2027-01-03 15:00+05', null), '^ERR 42501 \[kassa:pre_live\]');
select zz.put('PL5', zz.payd('U_DIR', 'man_pl5_0001', 'T-6', 200000, 'cash', '2027-01-02', null, null));
select zz.chk('PL5 Direktor: kech kelgan 02.01 to''lovi haqiqiy sanasi bilan — KO-1 siz, fiskal cheksiz, raw.date 02.01',
  coalesce(zz.get('PL5')::jsonb ->> 'kassa', 'null') || ':' || (select (raw ->> 'date') || ':' || coalesce("cashDocId", '-') from public.payments where id = 'man_pl5_0001'),
  '^null:2027-01-02:-$');
select zz.put('PL6q', zz.as('U_DIR', $q$select public.fin_period_lock('2027-01-02', '')::text$q$));
select zz.chk('PL6 davr qulfi baribir: 02.01 gacha yopilgan davrga Direktor ham kassadan oldingi to''lovni kirita olmaydi',
  (zz.get('PL6q')::jsonb ->> 'lockedThrough') || ' | ' || zz.payd('U_DIR', 'man_pl6_0001', 'T-6', 1000, 'cash', '2027-01-02', null, null),
  '^2027-01-02 \| ERR 42501 \[fin:locked\]');
select zz.chk('PL6b qulf olib tashlandi (sabab bilan)',
  coalesce(zz.as('U_DIR', $q$select public.fin_period_lock(null, 'Sinov: qulf olib tashlandi')::text$q$)::jsonb ->> 'lockedThrough', 'yo''q'), '^yo''q$');
select zz.chk('PL7 so''ralgan sana ishga tushishdan oldin va 31 kunlik oraliqdan tashqarida (01.12) — bugungi KO-1 bo''lib ikki marta hisoblanmaydi: rad, iz yo''q',
  zz.payd('U_KAS', 'man_pl7_0001', 'T-6', 10000, 'cash', '2026-12-01', null, '{"fiscalNo":"F-PL7"}') || ' / ' || (select count(*) from public.payments where id = 'man_pl7_0001')
  || '/' || (select count(*) from public.cash_docs where "sourceId" = 'man_pl7_0001'), '^ERR 22023 \[kassa:pre_live_old\].* / 0/0$');
select zz.chk('PL8 nazorat ro''yxati: «ishga tushishdan oldingi naqd yozuvlar (keyin kiritilgan)» — o''quv to''lovi 2 ta, 500 000',
  (select (c -> 'preLive')::text from (select zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)::jsonb as c) q),
  '"goLive": "2027-01-04"') ;
select zz.chk('PL8b ro''yxat mazmuni', (select (c #>> '{preLive,items,0,kind}') || ':' || (c #>> '{preLive,items,0,n}') || ':' || (c #>> '{preLive,items,0,sum}')
  from (select zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)::jsonb as c) q), '^tuition:2:500000$');
select zz.chk('PL9 moslik (ishga tushgan kundan): kassadan oldingi kun to''lovlari P1 ga kirmaydi', (select app.kassa_reconcile(null, null) ->> 'total'), '^0$');

-- ---------- Taqsimot ----------
select zz.put('J3', zz.pay('U_KAS', 'man_j3_0001', 'T-1', 1400000, 'cash', 'Sinov Ota', null, '{"fiscalNo":"F-1"}'));
select zz.chk('J3 naqd 1 400 000: javobda KO-1 № 1, kun 04.01.2027', zz.get('J3'), '"kassa": \{.*"no": 1[,}]');
select zz.chk('J3a javobdagi kun — kassa kuni', (zz.get('J3')::jsonb ->> 'day') || '/' || (zz.get('J3')::jsonb -> 'kassa' ->> 'day'), '^2027-01-04/2027-01-04$');
select zz.chk('J3b qatorlar: dekabr qoldig''i 900 000 va yanvar 500 000 — Kt 4010', zz.lines('man_j3_0001'), '^5010>4010=900000@2026-12, 5010>4010=500000@2027-01$');
select zz.chk('J3c to''lov qatori: order havolasi, fiskal №, kassa kuni, raqam',
  (select status || ':' || ("cashDocId" is not null) || ':' || "fiscalNo" || ':' || (raw ->> 'date') || ':' || (raw ->> 'kassaNo') || ':' || (raw ->> 'fiscalNo') from public.payments where id = 'man_j3_0001'),
  '^applied:true:F-1:2027-01-04:1:F-1$');
select zz.chk('J3d order: o''quvchi (kanonik), to''lovchi ismi, manba, asos',
  (select "partyType" || ':' || "partyId" || ':' || "partyName" || ':' || "sourceTable" || ':' || "sourceId" || ':' || basis || ':' || "postedBy" from public.cash_docs where "sourceId" = 'man_j3_0001'),
  '^student:T-1:Sinov Ota:payments:man_j3_0001:O‘quv to‘lovi: 2026-12, 2027-01:U_KAS$');
select zz.chk('J3e taqsimot yozuvlari', (select string_agg(month || '=' || trim_scale("fromCash") || '/' || trim_scale("fromCredit") || '@' || account, ',' order by month) from public.payment_allocations where "paymentId" = 'man_j3_0001'),
  '^2026-12=900000/0@4010,2027-01=500000/0@4010$');
select zz.put('J4', zz.pay('U_KAS', 'man_j4_0001', 's1', 1600000, 'cash', '', null, '{"fiscalNo":"F-2"}'));
select zz.chk('J4 naqd 1 600 000: yanvar qoldig''i → 4010; fevral (kelgusi oy) va ortiqcha → 6310', zz.lines('man_j4_0001'),
  '^5010>4010=500000@2027-01, 5010>6310=1000000@2027-02, 5010>6310=100000#overpay$');
select zz.chk('J4b avans 100 000; to''lovchi ismi berilmasa — o''quvchi ismi',
  (select trim_scale(credit)::text from public.student_credit where id = 'T-1') || ':' || (select "partyName" from public.cash_docs where "sourceId" = 'man_j4_0001'), '^100000:Sinov A$');
set local session_replication_role = replica;
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values ('id','T-1','Sinov A','2027-01',300000,0,'pending');
set local session_replication_role = origin;
select zz.put('J5', zz.pay('U_KAS', 'man_j5_0001', 'T-1', 50000, 'cash', '', null, '{"fiscalNo":"F-3"}'));
select zz.chk('J5 eski avans avval sarflanadi: naqd 50 000 → Kt 4010; avans 100 000 → naqdsiz Dt 6310 Kt 4010', zz.lines('man_j5_0001'),
  '^5010>4010=50000@2027-01, 6310>4010=100000\(naqdsiz\)@2027-01#credit_applied$');
select zz.chk('J5b order summasi — faqat naqd (50 000); avans 0; faktura 150 000 to''langan',
  (select trim_scale(amount)::text from public.cash_docs where "sourceId" = 'man_j5_0001') || ':' || (select trim_scale(credit)::text from public.student_credit where id = 'T-1')
  || ':' || (select trim_scale("paidAmount")::text from public.invoices where id = 'id'), '^50000:0:150000$');
select zz.chk('J6 qayta yuborish (o''sha payId): takror, o''sha order, yangi hujjat yo''q',
  zz.pay('U_KAS', 'man_j3_0001', 'T-1', 1400000, 'cash', 'Sinov Ota', null, '{"fiscalNo":"F-1"}') || ' / ' || (select count(*) from public.cash_docs where op = 'in_tuition'),
  '"dup": true.*"no": 1[,}].* / 3$|"no": 1[,}].*"dup": true.* / 3$');

-- ---------- Rollar, fiskal chek ----------
select zz.chk('J7 naqdsiz (bank) to''lov: Moliya menejeri, KO-1 siz', zz.pay('U_FM', 'man_j7_0001', 'T-2', 70000, 'bank', '', null, null), '"kassa": null');
select zz.chk('J8 kassa ishga tushgach naqd pulni Moliya menejeri qabul qilmaydi (RF-08)', zz.pay('U_FM', 'man_j8_0001', 'T-2', 1000, 'cash', '', null, '{"fiscalNo":"F-9"}'), '^ERR 42501 \[kassa:cash_role\]');
select zz.chk('J8b atomar: iz yo''q', (select count(*)::text from public.payments where id = 'man_j8_0001'), '^0$');
select zz.chk('J9 fiskal istisnoni kassir so''ray olmaydi', zz.pay('U_KAS', 'man_j9_0001', 'T-2', 10000, 'cash', '', null, '{"fiscalExempt":true}'), '^ERR 22023 \[kassa:fiscal\]');
select zz.put('J9', zz.pay('U_DIR', 'man_j9_0002', 'T-2', 10000, 'cash', '', null, '{"fiscalExempt":true}'));
select zz.chk('J9b Direktor (favqulodda) fiskal istisno bilan: belgilanadi; fakturasi yo''q o''quvchi — hammasi avansga (Kt 6310)',
  (select "fiscalExempt" || ':' || "postedBy" from public.cash_docs where "sourceId" = 'man_j9_0002') || ' / ' || zz.lines('man_j9_0002'), '^true:U_DIR / 5010>6310=10000#overpay$');
select zz.chk('J10 ishlatilgan fiskal chek raqami — rad, to''lov yozilmaydi',
  zz.pay('U_KAS', 'man_j10_001', 'T-2', 5000, 'cash', '', null, '{"fiscalNo":"F-1"}') || ' / ' || (select count(*) from public.payments where id = 'man_j10_001'), '^ERR 22023 \[kassa:fiscal_dup\].* / 0$');
select zz.chk('J11 keyin boshqa pul harakati bo''lgan to''lov bekor qilinmaydi (Direktorning «Qaytarish» amali orqali)',
  zz.as('U_FM', format('select public.kassa_doc_void(%L, %L)::text', (select "cashDocId" from public.payments where id = 'man_j3_0001'), 'Sinov uchun bekor')), '^ERR P0001 \[kassa:later_movement\]');
select zz.chk('J11b kassir boshqa xodim o''tkazgan to''lov orderini bekor qila olmaydi',
  zz.as('U_KAS', format('select public.kassa_doc_void(%L, %L)::text', (select "cashDocId" from public.payments where id = 'man_j9_0002'), 'Sinov uchun bekor')), '^ERR 42501 \[kassa:not_own\]');
select zz.chk('J12 o''qituvchi to''lov kirita olmaydi', zz.pay('U_TCH', 'man_j12_001', 'T-2', 1000, 'cash', '', null, '{"fiscalNo":"F-8"}'), '^ERR 42501');
select zz.chk('J13 mavjud bo''lmagan o''quvchi', zz.pay('U_KAS', 'man_j13_001', 'T-404', 1000, 'cash', '', null, '{"fiscalNo":"F-8"}'), '^ERR 22023');

-- ---------- Eski (3 bosqichli) mijozdan qolgan «pending» qator ----------
set local session_replication_role = replica;
insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values
  ('man_legacy_001','T-2','cash',10000,'pending',true,'{"manual":true}','2027-01-04 09:00+05'),
  ('man_legacy_002','T-2','cash',20000,'pending',true,'{"manual":true}','2027-01-04 09:05+05');
set local session_replication_role = origin;
select zz.put('J14', zz.pay('U_KAS', 'man_legacy_001', 'T-2', 10000, 'cash', '', null, '{"fiscalNo":"F-4"}'));
select zz.chk('J14 yetim «pending» qator tugatiladi: qo''llandi + KO-1', (select status || ':' || ("cashDocId" is not null) from public.payments where id = 'man_legacy_001') || ' / ' || zz.lines('man_legacy_001'),
  '^applied:true / 5010>6310=10000#overpay$');
select zz.put('J15a', zz.as('U_DIR', $q$select public.apply_payment('T-2', 20000, 'cash', 'man_legacy_002')::text$q$));
select zz.put('J15', zz.pay('U_KAS', 'man_legacy_002', 'T-2', 20000, 'cash', '', null, '{"fiscalNo":"F-5"}'));
select zz.chk('J15 balansga avval qo''llangan to''lov: pul ikki marta qo''llanmaydi, KO-1 bitta qator bilan (taqsimot noma''lum — belgilanadi)',
  (zz.get('J15')::jsonb ->> 'dup') || ':' || (zz.get('J15')::jsonb -> 'kassa' ->> 'allocation') || ' / ' || zz.lines('man_legacy_002') || ' / ' ||
  (select trim_scale(credit)::text from public.student_credit where id = 'T-2'), '^true:unknown / 5010>4010=20000 / 110000$');   -- T-2 avansi: 70 000 (bank) + 10 000 + 10 000 + 20 000 — ikki marta qo'shilmagan

-- ---------- Shu kunda bekor qilish (kassir xatosi) ----------
select zz.put('V1', zz.pay('U_KAS', 'man_v1_0001', 'T-1', 30000, 'cash', '', null, '{"fiscalNo":"F-20"}'));
select zz.chk('V1 xato kiritilgan to''lov: faktura 180 000 bo''ldi, xabarnoma navbatda',
  (select trim_scale("paidAmount")::text from public.invoices where id = 'id') || ':' || (zz.get('V1')::jsonb -> 'kassa' ->> 'no') || ':' ||
  coalesce((select status from public.notify_queue where id = 'pay__man_v1_0001'), '-'), '^180000:7:pending$');
select zz.put('V2', zz.as('U_KAS', format('select public.kassa_doc_void(%L, %L)::text', (select "cashDocId" from public.payments where id = 'man_v1_0001'), 'Summa xato kiritildi')));
select zz.chk('V2 kassir shu kunda bekor qildi: order «bekor qilingan», raqami saqlanadi', zz.get('V2'), '"no": 7[,}].*"status": "void"|"status": "void".*"no": 7[,}]');
select zz.chk('V2b faktura va avans to''lovdan oldingi holatga qaytdi; to''lov bekor; xabarnoma to''xtatildi',
  (select trim_scale("paidAmount") || ':' || status from public.invoices where id = 'id') || ':' || (select trim_scale(credit)::text from public.student_credit where id = 'T-1')
  || ':' || (select status from public.payments where id = 'man_v1_0001') || ':' || coalesce((select status from public.notify_queue where id = 'pay__man_v1_0001'), '-'),
  '^150000:partial:0:canceled:skipped$');
select zz.chk('V2c bekor qilingan to''lov kirim hisobotiga kirmaydi',
  (select app.counts_as_receipt(id, status, provider, amount)::text from public.payments where id = 'man_v1_0001'), '^false$');
select zz.chk('V3 qayta bekor qilish — takror', zz.as('U_KAS', format('select public.kassa_doc_void(%L, %L)::text', (select "cashDocId" from public.payments where id = 'man_v1_0001'), 'Summa xato kiritildi')), '"dup": true');
select zz.chk('V4 bekor qilingan to''lov qayta yuborilsa qo''llanmaydi', zz.pay('U_KAS', 'man_v1_0001', 'T-1', 30000, 'cash', '', null, '{"fiscalNo":"F-21"}'), '"ok": false.*"reason": "exists"|"reason": "exists".*"ok": false');
select zz.put('V5', zz.pay('U_KAS', 'man_v5_0001', 'T-2', 7000, 'cash', '', null, '{"fiscalNo":"F-22"}'));
select zz.put('V5v', zz.as('U_FM', format('select public.kassa_doc_void(%L, %L)::text', (select "cashDocId" from public.payments where id = 'man_v5_0001'), 'Boshqa o''quvchiga yozilgan')));
select zz.chk('V5 avansga tushgan to''lov ham bekor qilinadi (Moliya menejeri): avans qaytadi, jurnalda teskari yozuv',
  (select trim_scale(credit)::text from public.student_credit where id = 'T-2') || ':' ||
  (select trim_scale(delta) || '/' || reason from public.credit_ledger where "studentId" = 'T-2' order by "at" desc, delta limit 1), '^110000:-7000/manual$');

-- ---------- Orderga bog'langan to'lov qatori: faqat kassa funksiyalari orqali ----------
select zz.put('LK', (select id from public.payments where "cashDocId" is not null and status = 'applied' and provider = 'cash' order by id limit 1));
select zz.chk('LK1 orderga bog''langan to''lov: summa, holat (bekor), o''quvchi, kun, havola va fiskal № ni to''g''ridan-to''g''ri o''zgartirib bo''lmaydi',
  zz.as('U_FM', format($q$with x as (update public.payments set amount = amount + 1 where id = %L returning id) select id from x$q$, zz.get('LK'))) || ' | ' ||
  zz.as('U_KAS', format($q$with x as (update public.payments set status = 'canceled' where id = %L returning id) select id from x$q$, zz.get('LK'))) || ' | ' ||
  zz.as('U_FM', format($q$with x as (update public.payments set "studentId" = 'T-2' where id = %L returning id) select id from x$q$, zz.get('LK'))) || ' | ' ||
  zz.as('U_FM', format($q$with x as (update public.payments set raw = raw || '{"date":"2027-01-03"}' where id = %L returning id) select id from x$q$, zz.get('LK'))) || ' | ' ||
  zz.as('U_DIR', format($q$with x as (update public.payments set "cashDocId" = null, "fiscalNo" = null where id = %L returning id) select id from x$q$, zz.get('LK'))),
  '^ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:linked_row\]');
select zz.chk('LK2 havolani faqat kassa qo''yadi: yangi qatorda ham, bog''lanmagan qatorga ham — rad; bog''lanmagan qator va izoh — avvalgidek',
  zz.as('U_FM', format($q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "cashDocId") values ('fake_lk', 'T-1', 'cash', 1, 'applied', true, '{}', %L) returning id) select id from x$q$,
                       (select "cashDocId" from public.payments where id = zz.get('LK')))) || ' | ' ||
  zz.as('U_FM', format($q$with x as (update public.payments set "cashDocId" = %L where id = 'man_j1_0001' returning id) select id from x$q$,
                       (select "cashDocId" from public.payments where id = zz.get('LK')))) || ' | ' ||
  zz.as('U_FM', $q$with x as (update public.payments set raw = raw || '{"note":"tuzatildi"}' where id = 'man_j1_0001' returning id) select id from x$q$) || ' | ' ||
  zz.as('U_FM', format($q$with x as (update public.payments set raw = raw || '{"manualReverseDone":true}' where id = %L returning id) select id from x$q$, zz.get('LK'))),
  '^ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:linked_row\].* \| man_j1_0001 \| ' || zz.get('LK') || '$');
savepoint lk3;
set local iqror.migrating = '1';
update public.payments set "studentId" = 'kanon-' || "studentId" where id = zz.get('LK');
select (select count(*)::text from public.payments where id = zz.get('LK') and "studentId" like 'kanon-%')
  || ' | ' || zz.as('U_FM', format($q$with x as (update public.payments set amount = amount + 1 where id = %L returning id) select id from x$q$, zz.get('LK'))) as lk3 \gset
rollback to savepoint lk3;   -- (savepoint ichidagi natija psql o'zgaruvchisida saqlanadi)
select zz.chk('LK3 deploy paytidagi kalit kanonlash (faqat «studentId») o''tadi; boshqa o''zgarish deploy paytida ham rad', :'lk3', '^1 \| ERR 42501 \[kassa:linked_row\]');

-- ---------- Kun, moslik ----------
select zz.chk('J16 kassa qoldig''i = naqd to''lovlar yig''indisi (ishga tushgandan beri)',
  zz.as('U_KAS', $q$select (s ->> 'balance') from public.kassa_state('main') s$q$) || '/' ||
  (select trim_scale(sum(amount))::text from public.payments where "cashDocId" is not null and status = 'applied'), '^3090000/3090000$');
-- (crit-1: kassadan oldingi kun puli — KO-1 siz; tekshiruv ishga tushgan kundan keyingi kassa kuniga ega to'lovlarni sanaydi)
select zz.chk('J17 P1: ishga tushgandan keyingi har naqd to''lovda order bor (yetim yo''q)',
  (select count(*)::text from public.payments p where p.provider = 'cash' and p.status = 'applied' and p."cashDocId" is null
     and app.pay_day(p."createdAt", p.raw) >= '2027-01-04'), '^0$');
select zz.chk('J18 hisobotdagi «tushgan kun» (pay_day) = order kuni',
  (select count(*)::text from public.payments p join public.cash_docs c on c.id = p."cashDocId" where app.pay_day(p."createdAt", p.raw) is distinct from c."businessDay"), '^0$');
select zz.chk('J19 kun yopildi: farq 0', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-01-04","counted":3090000}')::text$q$), '"diff": 0[,}]');
select zz.clock('2027-01-05 09:00+05');
select zz.put('J20', zz.pay('U_KAS', 'man_j20_001', 'T-2', 30000, 'cash', '', null, '{"fiscalNo":"F-6"}'));
select zz.chk('J19b yopilgan kun to''lovi bekor qilinmaydi',
  zz.as('U_FM', format('select public.kassa_doc_void(%L, %L)::text', (select "cashDocId" from public.payments where id = 'man_legacy_001'), 'Sinov: yopilgan kun')), '^ERR P0001 \[kassa:day_closed\]');
select zz.chk('J20 ertasi kun: yangi kun (kun boshi 3 090 000), raqam davom etadi (№ 9)',
  (zz.get('J20')::jsonb -> 'kassa' ->> 'no') || ':' || (zz.get('J20')::jsonb -> 'kassa' ->> 'day') || ':' || (select trim_scale(opening)::text from public.cash_days where status = 'open'), '^9:2027-01-05:3090000$');
select zz.clock('2027-01-06 09:00+05');
select zz.chk('J21 kecha yopilmagan: naqd to''lov rad, to''lov ham yozilmaydi (CT-04, atomar)',
  zz.pay('U_KAS', 'man_j21_001', 'T-2', 1000, 'cash', '', null, '{"fiscalNo":"F-7"}') || ' / ' || (select count(*) from public.payments where id = 'man_j21_001')
  || '/' || (select count(*) from public.applied_payments where id = 'man_j21_001'), '^ERR P0001 \[kassa:prev_open\].* / 0/0$');
select zz.put('J22', zz.pay('U_KAS', 'man_j22_001', 'T-2', 2000, 'cash', '', '2027-01-05 16:00+05', '{"fiscalNo":"F-7"}'));
select zz.chk('J22 kecha olingan (oflayn navbatdagi) to''lov — hali ochiq kechagi kunga', (zz.get('J22')::jsonb -> 'kassa' ->> 'day') || ':' || (zz.get('J22')::jsonb -> 'kassa' ->> 'late'), '^2027-01-05:false$');
select zz.chk('J23 kechagi kun yopildi', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-01-05","counted":3122000}')::text$q$), '"diff": 0[,}]');
select zz.put('J24', zz.pay('U_KAS', 'man_j24_001', 'T-2', 3000, 'cash', '', '2027-01-05 17:00+05', '{"fiscalNo":"F-10"}'));
select zz.chk('J24 olingan kuni yopilgan: bugungi kunga «kech» belgisi bilan; hisobot kuni ham bugun',
  (zz.get('J24')::jsonb -> 'kassa' ->> 'day') || ':' || (zz.get('J24')::jsonb -> 'kassa' ->> 'late') || ':' || (select raw ->> 'date' from public.payments where id = 'man_j24_001'), '^2027-01-06:true:2027-01-06$');
select zz.chk('J25 kunlar bo''yicha: order jami = to''lovlar jami (kassa kitobi = «To''lovlar» hisoboti)',
  (select string_agg(d || '=' || s1 || '/' || s2, ',' order by d) from (
     select c."businessDay" d, trim_scale(sum(c.amount)) s1,
            (select trim_scale(sum(p.amount)) from public.payments p where p."cashDocId" is not null and p.status = 'applied' and app.pay_day(p."createdAt", p.raw) = c."businessDay") s2
       from public.cash_docs c where c.op = 'in_tuition' and c.status = 'posted' group by c."businessDay") x),
  '^2027-01-04=3090000/3090000,2027-01-05=32000/32000,2027-01-06=3000/3000$');
select zz.chk('J26 raqamlash uzluksiz', (select app.kassa_gap_check('main', 2027)::text), '^\[\]$');

-- ---------- acc-7: oy chegarasi — «boshlangan davr» (4010) / «kelgusi oy» (6310) HUJJAT KUNIGA nisbatan ----------
--   31.01 kassa kuni ochiq. Oflayn navbatda 31.01 23:55 da olingan to'lov yarim tundan keyin (01.02 00:30) yuborilsa, u hali ochiq 31.01
--   kuniga tushadi — fevral fakturasi o'sha kun bo'yicha kelgusi oy (Kt 6310), o'z vaqtida yozilgan to'lov bilan bir xil.
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s3','T-3','Sinov C',5,'A','uz','',3,'[]'), ('s4','T-4','Sinov D',5,'A','uz','',4,'[]'), ('s5','T-5','Sinov E',5,'A','uz','',5,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('mf3','T-3','Sinov C','2027-02',400000,0,'pending'), ('mf4','T-4','Sinov D','2027-02',400000,0,'pending'),
  ('mm4','T-4','Sinov D','2027-03',400000,0,'pending'), ('mf5','T-5','Sinov E','2027-02',400000,0,'pending');
set local session_replication_role = origin;
select zz.put('M0', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-01-06","counted":3125000}')::text$q$));
select zz.clock('2027-01-31 23:50+05');
select zz.put('M1', zz.pay('U_KAS', 'man_m1_0001', 'T-4', 400000, 'cash', '', null, '{"fiscalNo":"F-31"}'));   -- o'z vaqtida (31.01 23:50)
select zz.clock('2027-02-01 00:30+05');
select zz.put('M2', zz.pay('U_KAS', 'man_m2_0001', 'T-3', 400000, 'cash', '', '2027-01-31 23:55+05', '{"fiscalNo":"F-32"}'));   -- 31.01 da olingan, 01.02 00:30 da yuborilgan
select zz.chk('M1 06.01 yopildi; 31.01 23:50 da o''z vaqtida yozilgan to''lov: kun 31.01, fevral fakturasi — Kt 6310 (kelgusi oy)',
  (zz.get('M0')::jsonb -> 'day' ->> 'status') || ' / ' || (zz.get('M1')::jsonb -> 'kassa' ->> 'day') || ' / ' || zz.lines('man_m1_0001'), '^closed / 2027-01-31 / 5010>6310=400000@2027-02$');
select zz.chk('M2 oflayn: 31.01 da olingan, yarim tundan keyin yuborilgan — hali ochiq 31.01 kuniga, fevral fakturasi o''sha kun bo''yicha Kt 6310; taqsimot yozuvi ham 6310',
  (zz.get('M2')::jsonb -> 'kassa' ->> 'day') || ':' || (zz.get('M2')::jsonb -> 'kassa' ->> 'late') || ' / ' || zz.lines('man_m2_0001')
  || ' / ' || (select string_agg(account || '@' || month, ',') from public.payment_allocations where "paymentId" = 'man_m2_0001'),
  '^2027-01-31:false / 5010>6310=400000@2027-02 / 6310@2027-02$');
select zz.put('M3', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-01-31","counted":3925000}')::text$q$));
select zz.clock('2027-02-01 10:00+05');
select zz.put('M4', zz.pay('U_KAS', 'man_m4_0001', 'T-5', 400000, 'cash', '', null, '{"fiscalNo":"F-33"}'));
select zz.put('M5', zz.pay('U_KAS', 'man_m5_0001', 'T-4', 400000, 'cash', '', null, '{"fiscalNo":"F-34"}'));
select zz.chk('M3 31.01 yopildi; 01.02 kuni: fevral fakturasi — Kt 4010 (fevral boshlangan), mart — Kt 6310',
  (zz.get('M3')::jsonb -> 'day' ->> 'status') || ' / ' || (zz.get('M4')::jsonb -> 'kassa' ->> 'day') || ' ' || zz.lines('man_m4_0001')
  || ' / ' || (zz.get('M5')::jsonb -> 'kassa' ->> 'day') || ' ' || zz.lines('man_m5_0001'),
  '^closed / 2027-02-01 5010>4010=400000@2027-02 / 2027-02-01 5010>6310=400000@2027-03$');

-- ---------- ui-5 + ishga-tushirish §9: kassani TO'XTATISH (sanani bo'shatish / surish) va QAYTA ISHGA TUSHIRISH ----------
--   To'xtatish — faqat Direktor, ochiq kun va pul berilmagan so'rovlar bo'lmasa; kassa to'xtaydi (hujjat yozilmaydi, naqd — kassa
--   hujjatisiz). Qayta ishga tushirish — komissiya sanashi: sanalgan summa bilan oxirgi kun oxiri farqi — texnik dalolatnoma «Д-»
--   (OP-23, Dt 5010 Kt 0000), qayta ochilgan birinchi kun boshi = sanalgan summa: to'xtatilgan davr puli kassirga kamomad / ortiqcha bo'lmaydi.
--   01.02 kun ochiq: kun boshi 3 925 000, kirim 800 000 → hisobda 4 725 000.
set local session_replication_role = replica;
insert into public.fin_counterparties (id, kind, name) values ('cp_sup','supplier','Sinov Ta''minot MChJ');
set local session_replication_role = origin;
select zz.chk('R0 ochiq kassa kuni bor — kassani to''xtatib bo''lmaydi (sana o''zgarmadi, kassa to''xtamadi)',
  zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$) || ' | ' || (select "kassaGoLive"::text from public.fin_org where id = 'main')
  || ' | ' || coalesce((select "pausedAt"::text from public.cash_desks where id = 'main'), 'ishlaydi'),
  '^ERR P0001 \[kassa:rollback_open_day\].*01\.02\.2027.* \| 2027-01-04 \| ishlaydi$');
select zz.put('R1', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-01","counted":4725000}')::text$q$));
select zz.put('R2', zz.as('U_KAS', $q$select public.kassa_payout_request('{"op":"out_expense","amount":15000,"partyType":"counterparty","partyId":"cp_sup","articleId":"EX-16","basis":"Hisob-faktura 7","clientRef":"r2-req-00001"}')::text$q$));
select zz.chk('R1 kun yopildi (farq 0); R2 pul berilmagan so''rov bor — to''xtatib bo''lmaydi, so''rov nomlanadi',
  (zz.get('R1')::jsonb ->> 'diff') || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$),
  '^0 \| ERR P0001 \[kassa:rollback_requests\].*chiqim «Xarajat» 15000 so''m — tasdiq kutilmoqda$');
select zz.chk('R2b kassir sozlamani o''zgartira olmaydi (faqat Direktor)', zz.as('U_KAS', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$), '^ERR 42501');
select zz.put('R3', left(zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.get('R2')::jsonb ->> 'id', 'To''xtatishdan oldin')), 0)
  || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-20"}')::text$q$));
select zz.chk('R3 so''rov bekor qilindi; Direktor sanani 20.02 ga SURDI — kassa to''xtadi: sana bo''sh saqlanadi, rejalashtirilgan kun hodisada (kim, qachon)',
  coalesce(zz.get('R3')::jsonb ->> 'kassaGoLive', 'bo''sh') || ' | ' || (select ("pausedAt" is not null) || ':' || "pausedBy" from public.cash_desks where id = 'main')
  || ' | ' || (select "byUid" || ':' || (data ->> 'from') || '>' || (data ->> 'to') || ':pause=' || (data ->> 'pause') from public.cash_day_events where kind = 'golive' order by at desc, id desc limit 1),
  '^bo''sh \| true:U_DIR \| U_DIR:2027-01-04>2027-02-20:pause=true$');
select zz.put('R4', zz.pay('U_KAS', 'man_r4_0001', 'T-5', 60000, 'cash', '', null, null));
select zz.chk('R4 to''xtatilgan kassa: naqd o''quv to''lovi KO-1 siz va fiskal cheksiz (avvalgi tartib)',
  (zz.get('R4')::jsonb ->> 'ok') || ':' || coalesce(zz.get('R4')::jsonb ->> 'kassa', 'null') || ':' || (select coalesce("cashDocId", '-') from public.payments where id = 'man_r4_0001'), '^true:null:-$');
select zz.chk('R4b kassa hujjati yozilmaydi (kassa:paused); naqd xarajat — «Buxgalteriya»dan, avvalgidek',
  zz.as('U_KAS', $q$select public.kassa_receipt('{"op":"in_other","amount":1000,"partyType":"other","partyName":"Sinov Shaxs","articleId":"IN-06","basis":"Tilxat","note":"Kitob uchun","clientRef":"r4-rcp-00001"}')::text$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_r4', '2027-02-01', '2027-02', 'Boshqa', 25000, 'to''xtatilgan davr', 'cash') returning id) select id from x$q$),
  '^ERR P0001 \[kassa:paused\].* \| e_r4$');
select zz.chk('R4c «Kassa» holati: to''xtatilgan (01.02 dan), qoldiq — oxirgi kun oxiri; sanani to''g''ridan-to''g''ri qo''yib bo''lmaydi (avval komissiya sanashi)',
  (select (s ->> 'blockReason') || ':' || (s -> 'desk' ->> 'pausedDay') || ':' || (s ->> 'balance') from (select zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)::jsonb as s) q)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-02"}')::text$q$),
  '^paused:2027-02-01:4725000 \| ERR P0001 \[kassa:restart_needed\]');
select zz.clock('2027-02-02 09:00+05');
-- Komissiya sanadi: 4 725 000 + 60 000 (o'quv to'lovi) − 25 000 (xarajat) = 4 760 000. Avval xato (4 750 000), keyin qayta sanaldi.
select zz.chk('R5 qayta ishga tushirish qoldig''ini faqat Direktor kiritadi; kun oxirgi kassa kunidan keyin va bugundan oldin emas',
  zz.as('U_KAS', $q$select public.kassa_opening_set('{"amount":4750000,"startDay":"2027-02-03"}')::text$q$) || ' | '
  || zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4750000,"startDay":"2027-02-01"}')::text$q$),
  '^ERR 42501.* \| ERR 22023 \[kassa:bad_input\]');
select zz.put('R5a', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4750000,"startDay":"2027-02-03","note":"Sanash dalolatnomasi 2","commission":[{"title":"Direktor","name":"Sinov D"},{"title":"Kassir","name":"Sinov K"}]}')::text$q$));
select zz.put('R5b', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4760000,"startDay":"2027-02-03","note":"Qayta sanaldi"}')::text$q$));
select zz.chk('R5 farq dalolatnomasi: «Д-» (OP-23) Dt 5010 Kt 0000 (boshlang''ich qoldiq 0 edi — dalolatnomasi yo''q edi); qayta sanalganda avvalgisi bekor (raqami saqlanadi), yangisi 35 000; asos — qayta ishga tushirish',
  (zz.get('R5a')::jsonb ->> 'delta') || ' / ' || (zz.get('R5b')::jsonb ->> 'delta') || ' / '
  || (select string_agg(c.form || ':' || c.status || ':' || trim_scale(c.amount) || ':' || l.debit || '>' || l.credit || '@' || l."articleId", ', ' order by c.no)
        from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.op = 'nc_opening' and c."sourceSnapshot" ->> 'kind' = 'restart')
  || ' / ' || (zz.get('R5b')::jsonb #>> '{doc,basis}'),
  '^25000 / 35000 / ACT:void:25000:5010>0000@OP-23, ACT:posted:35000:5010>0000@OP-23 / Qayta ishga tushirish: sanash dalolatnomasi$');
select zz.chk('R5c sanash dalolatnomasi (kutilgan — oxirgi kun oxiri, sanalgan, farq) va kassa hali to''xtatilgan; qoldiq — sanalgan summa',
  (select trim_scale(expected) || ':' || trim_scale(counted) || ':' || trim_scale(diff) from public.cash_counts where kind = 'opening' and day = '2027-02-03' order by at desc limit 1)
  || ' | ' || (select (s ->> 'blockReason') || ':' || (s ->> 'balance') || ':' || (s -> 'desk' -> 'restart' ->> 'day') from (select zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)::jsonb as s) q),
  '^4725000:4760000:35000 \| paused:4760000:2027-02-03$');
select zz.put('R6x', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-04"}')::text$q$));
select zz.put('R6', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-03"}')::text$q$));
select zz.chk('R6 ishga tushadigan kun boshqa sana — rad; qayta ishga tushirish kuni (03.02) — kassa yana ishlaydi (hodisa: resume)',
  zz.get('R6x') || ' | ' || (zz.get('R6')::jsonb ->> 'kassaGoLive')
  || ' | ' || coalesce((select "pausedAt"::text from public.cash_desks where id = 'main'), 'ishlaydi')
  || ' | ' || (select (data ->> 'resume') from public.cash_day_events where kind = 'golive' order by at desc, id desc limit 1),
  '^ERR 22023 \[kassa:restart_day\].* \| 2027-02-03 \| ishlaydi \| true$');
-- (g4-v1: boshqa kun bilan qayta sanash avval «Kassa ishga tushgan — boshlang'ich qoldiq o'zgarmaydi» deb rad etilardi — endi
--   alohida xabar: avval ishga tushadigan kunni bo'shatish kerak)
select zz.chk('R6b 03.02 gacha kassa hujjati yozilmaydi (kassa:not_started); boshqa kun bilan qayta sanash — rad, avval sanani bo''shatish kerak (kassa:restart_pending)',
  zz.as('U_KAS', $q$select public.kassa_receipt('{"op":"in_other","amount":1000,"partyType":"other","partyName":"Sinov Shaxs","articleId":"IN-06","basis":"Tilxat","note":"Kitob uchun","clientRef":"r6-rcp-00001"}')::text$q$)
  || ' | ' || zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4760000,"startDay":"2027-02-04"}')::text$q$)
  || ' | ' || (select (s ->> 'blockReason') from (select zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)::jsonb as s) q),
  '^ERR P0001 \[kassa:not_started\].*03\.02\.2027.* \| ERR P0001 \[kassa:restart_pending\] Qayta ishga tushirish 03\.02\.2027 ga tayyorlangan.*avval «⚙ Sozlamalar»da ishga tushadigan kunni bo''shating.* \| restart$');
select zz.clock('2027-02-03 09:00+05');
select zz.put('R7', zz.pay('U_KAS', 'man_r7_0001', 'T-5', 100000, 'cash', '', null, '{"fiscalNo":"F-R7"}'));
select zz.chk('R7 qayta ishga tushgan kun: naqd o''quv to''lovi KO-1 bilan; kun boshi = komissiya sanagan 4 760 000 (oldingi kun oxiri 4 725 000 emas)',
  (zz.get('R7')::jsonb #>> '{kassa,day}') || ':' || (select trim_scale(opening)::text from public.cash_days where day = '2027-02-03'), '^2027-02-03:4760000$');
select zz.chk('R8 kun yopildi: farq 0 — to''xtatilgan davr puli kassirga kamomad / ortiqcha bo''lmadi',
  zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-03","counted":4860000}')::text$q$)::jsonb ->> 'diff', '^0$');
select zz.chk('R9 nazorat ro''yxati: qayta ishga tushirish — oxirgi kun oxiri, sanalgan, farq, dalolatnoma; to''xtatilgan davrdagi kassa hujjatisiz naqd: kirim 60 000, chiqim 25 000; orqa sanali yo''q; izohlanmagan farq 0',
  (select (r ->> 'startDay') || ':' || (r ->> 'prevClosing') || ':' || (r ->> 'counted') || ':' || (r ->> 'delta') || ':D-' || (r ->> 'docNo') || ':' || (r #>> '{rows,in}') || ':' || (r #>> '{rows,out}')
          || ':' || (r #>> '{backdated,n}') || ':' || (r ->> 'unexplained') || ':' || coalesce(c ->> 'paused', 'ishlaydi')
     from (select zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)::jsonb as c) q, jsonb_array_elements(c -> 'restarts') r limit 1),
  '^2027-02-03:4725000:4760000:35000:D-2:60000:25000:0:0:ishlaydi$');
select zz.chk('R10 KO-3 va statiya matritsasi (fevral): boshi + kirim − chiqim + qayta ishga tushirish farqi = oxiri — qoldiqlar mos',
  (select (j ->> 'opening') || '+' || (j #>> '{totals,in}') || '+' || (j ->> 'restartAdj') || '=' || (j ->> 'closing') || ':' || (j ->> 'balanced')
     from (select zz.as('U_FM', $q$select public.kassa_journal('main', '2027-02-01', '2027-02-28')::text$q$)::jsonb as j) q)
  || ' | ' || (select (m ->> 'balanced') || ':' || (m -> 'dayBal' ->> 0) || ',' || (m -> 'dayBal' ->> 1) || ',' || (m -> 'dayBal' ->> 2)
     from (select zz.as('U_FM', $q$select public.kassa_matrix('main', '2027-02')::text$q$)::jsonb as m) q),
  '^3925000\+900000\+35000=4860000:true \| true:4725000,4725000,4860000$');
select zz.chk('R11 qayta ochilgan kundan keyin qoldiqni o''zgartirib bo''lmaydi; moslik (03.02 dan) toza',
  zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":1,"startDay":"2027-02-04"}')::text$q$) || ' | ' || (app.kassa_reconcile(null, null) ->> 'total'),
  '^ERR 42501 \[kassa:started\].* \| 0$');

-- ---------- §9: IKKINCHI to'xtatish va qayta ishga tushirish (g4-v1: avval ikkinchi qayta ishga tushirish qoldig'i doim rad etilardi —
--   kassa:started — va kassa to'xtatilgan holatda qolib ketardi) ----------
--   03.02 yopilgan (4 860 000). Kassa yana to'xtatiladi; to'xtatilgan davrda: 03.02 — naqd o'quv to'lovi 30 000; 01.02 sanali (orqa sana —
--   u kun birinchi to'xtatilgan davrda) naqd xarajat 7 000; 04.02 — naqd o'quv to'lovi 5 000. Komissiya 05.02 uchun sanaydi:
--   4 860 000 + 30 000 + 5 000 − 7 000 = 4 888 000.
create or replace function zz.su(p_q text) returns text language plpgsql as $$   -- joriy (superfoydalanuvchi) rolda, xato matni bilan
declare r text; v_hint text;
begin
  begin execute p_q into r;
  exception when others then get stacked diagnostics v_hint = pg_exception_hint; r := 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm; end;
  return coalesce(r, '<null>');
end $$;
select zz.put('R12', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$));
select zz.chk('R12 ikkinchi marta to''xtatildi: sana bo''sh, kassa to''xtatilgan, oxirgi qayta ishga tushirish (03.02) joyida; to''xtatilgan kassada oxirgi kun qayta ochilmaydi',
  coalesce(zz.get('R12')::jsonb ->> 'kassaGoLive', 'bo''sh') || ' | ' || (select ("pausedAt" is not null) || ':' || "restartDay" from public.cash_desks where id = 'main')
  || ' | ' || zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-02-03', 'Sinov: qayta ochish')::text$q$)
  || ' | ' || (select status from public.cash_days where day = '2027-02-03'),
  '^bo''sh \| true:2027-02-03 \| ERR P0001 \[kassa:reopen_paused\].*03\.02\.2027.* \| closed$');
select zz.put('R13', zz.pay('U_KAS', 'man_r13_0001', 'T-5', 30000, 'cash', '', null, null));
select zz.put('R13b', zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_r13', '2027-02-01', '2027-02', 'Boshqa', 7000, 'to''xtatilgan davr, orqa sana', 'cash') returning id) select id from x$q$));
select zz.clock('2027-02-04 09:00+05');
select zz.put('R13c', zz.pay('U_KAS', 'man_r13_0002', 'T-5', 5000, 'cash', '', null, null));
select zz.chk('R13 to''xtatilgan davr: naqd o''quv to''lovlari KO-1 siz (03.02 va 04.02), orqa sanali naqd xarajat qabul qilindi (kassa nazorati o''chiq)',
  coalesce(zz.get('R13')::jsonb ->> 'kassa', 'null') || ':' || (zz.get('R13')::jsonb ->> 'day') || ' | ' || zz.get('R13b')
  || ' | ' || coalesce(zz.get('R13c')::jsonb ->> 'kassa', 'null') || ':' || (zz.get('R13c')::jsonb ->> 'day'),
  '^null:2027-02-03 \| e_r13 \| null:2027-02-04$');
select zz.chk('R14 qayta ishga tushirish kuni bugun (04.02), lekin bugun kassa hujjatisiz naqd yozuv bor — rad (kassa:restart_gap), dalolatnoma yozilmadi',
  zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4888000,"startDay":"2027-02-04"}')::text$q$)
  || ' | ' || (select count(*) from public.cash_docs where op = 'nc_opening' and "sourceSnapshot" ->> 'kind' = 'restart'),
  '^ERR P0001 \[kassa:restart_gap\] Qayta ishga tushirish kuni \(04\.02\.2027\).*\(1 ta\).* \| 2$');
select zz.put('R14a', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4888000,"startDay":"2027-02-05","note":"Sanash dalolatnomasi 3"}')::text$q$));
select zz.chk('R14a ikkinchi qayta ishga tushirish qoldig''i 05.02 uchun qabul qilindi: farq 28 000 — yangi «Д-3» (Dt 5010 Kt 0000); birinchisi («Д-2», 35 000) joyida',
  (zz.get('R14a')::jsonb ->> 'delta') || ':' || (zz.get('R14a')::jsonb #>> '{doc,lines,0,debit}') || '>' || (zz.get('R14a')::jsonb #>> '{doc,lines,0,credit}') || ' | '
  || (select string_agg('D-' || c.no || ':' || c.status || ':' || trim_scale(c.amount) || ':' || c."businessDay", ', ' order by c.no)
        from public.cash_docs c where c.op = 'nc_opening' and c."sourceSnapshot" ->> 'kind' = 'restart' and c.status = 'posted'),
  '^28000:5010>0000 \| D-2:posted:35000:2027-02-03, D-3:posted:28000:2027-02-05$');
select zz.chk('R14b tayyorlangan qayta ishga tushirishda ham oxirgi kun qayta ochilmaydi (qayta yopilsa farq dalolatnomasi eskirardi)',
  zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-02-03', 'Sinov: qayta ochish')::text$q$), '^ERR P0001 \[kassa:reopen_paused\]');
select zz.put('R15', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-05"}')::text$q$));
select zz.clock('2027-02-05 09:00+05');
select zz.put('R16', zz.pay('U_KAS', 'man_r16_0001', 'T-5', 50000, 'cash', '', null, '{"fiscalNo":"F-R16"}'));
select zz.chk('R15 ishga tushadigan kun 05.02 — kassa yana ishlaydi; R16 05.02 naqd to''lov KO-1 bilan, kun boshi = ikkinchi komissiya sanagan 4 888 000; kun farqsiz yopildi',
  (zz.get('R15')::jsonb ->> 'kassaGoLive') || ':' || coalesce((select "pausedAt"::text from public.cash_desks where id = 'main'), 'ishlaydi')
  || ' | ' || (zz.get('R16')::jsonb #>> '{kassa,day}') || ':' || (select trim_scale(opening)::text from public.cash_days where day = '2027-02-05')
  || ' | ' || (zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-05","counted":4938000}')::text$q$)::jsonb ->> 'diff'),
  '^2027-02-05:ishlaydi \| 2027-02-05:4888000 \| 0$');
select zz.chk('R17 nazorat ro''yxati: ikkita qayta ishga tushirish — har birining farqi va to''xtatilgan davr naqd harakati (orqa sanali xarajat — ikkinchisida alohida, birinchisiga kirmaydi), izohlanmagan farq 0',
  (select string_agg((r ->> 'startDay') || ':' || (r ->> 'prevDay') || ':' || (r ->> 'delta') || ':D-' || (r ->> 'docNo') || ':' || (r #>> '{rows,in}') || '-' || (r #>> '{rows,out}')
                     || ':' || (r #>> '{backdated,out}') || ':' || (r ->> 'unexplained'), ' | ' order by r ->> 'startDay' desc)
     from (select zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)::jsonb as c) q, jsonb_array_elements(c -> 'restarts') r),
  '^2027-02-05:2027-02-03:28000:D-3:35000-0:7000:0 \| 2027-02-03:2027-02-01:35000:D-2:60000-25000:0:0$');
select zz.chk('R18 KO-3 va statiyalar (fevral): ikkala farq bilan qoldiqlar mos (boshi + kirim − chiqim + 63 000 = oxiri); kun oxirlari — farq o''z kunidan',
  (select (j ->> 'opening') || '+' || (j #>> '{totals,in}') || '-' || (j #>> '{totals,out}') || '+' || (j ->> 'restartAdj') || '=' || (j ->> 'closing') || ':' || (j ->> 'balanced')
     from (select zz.as('U_FM', $q$select public.kassa_journal('main', '2027-02-01', '2027-02-28')::text$q$)::jsonb as j) q)
  || ' | ' || (select (m ->> 'balanced') || ':' || (m ->> 'restartAdj') || ':' || (m -> 'dayBal' ->> 3) || ',' || (m -> 'dayBal' ->> 4)
     from (select zz.as('U_FM', $q$select public.kassa_matrix('main', '2027-02')::text$q$)::jsonb as m) q),
  '^3925000\+950000-0\+63000=4938000:true \| true:63000:4860000,4938000$');
do $$ begin perform set_config('iqror.kassa_rpc', '1', true); end $$;
select zz.put('R19', zz.su($q$with x as (update public.cash_desks set "restartAmount" = 1 where id = 'main' returning id) select id from x$q$));
do $$ begin perform set_config('iqror.kassa_rpc', '', true); end $$;
select zz.chk('R19 kassa ishlab turganda (qayta ishga tushirish boshlangan) qayta ishga tushirish qoldig''i kassa funksiyasi bayrog''i bilan ham o''zgarmaydi; moslik toza',
  zz.get('R19') || ' | ' || (app.kassa_reconcile(null, null) ->> 'total'), '^ERR 42501 \[kassa:started\].* \| 0$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
