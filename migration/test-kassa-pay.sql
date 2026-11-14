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
create or replace function zz.js(p text) returns jsonb language plpgsql as $$   -- xato matni (ERR …) bo'lsa — NULL: mutatsiyada FAIL, to'plam to'xtamaydi
begin return p::jsonb; exception when others then return null; end $$;
-- JSON maydoni (yo'q bo'lsa — standart qiymat), faqat javob JSON bo'lsa; JSON bo'lmagan javob (ERR …) o'zicha qaytadi — mutatsiyada
--   standart qiymatga aylanib PASS bermaydi, FAIL bo'ladi (g10 tekshiruvchisi)
create or replace function zz.jd(p text, p_key text, p_dflt text) returns text language sql as $$
  select case when zz.js(p) is null then '<json emas> ' || left(coalesce(p, '<null>'), 200) else coalesce(zz.js(p) ->> p_key, p_dflt) end $$;
create or replace function zz.jdp(p text, p_path text[], p_dflt text) returns text language sql as $$
  select case when zz.js(p) is null then '<json emas> ' || left(coalesce(p, '<null>'), 200) else coalesce(zz.js(p) #>> p_path, p_dflt) end $$;
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
-- g8 (g4b qoldig'i): kassa hujjati ishga tushadigan kundan OLDINGI kunga ham tushishi mumkin — boshlang'ich qoldiqdagi «Birinchi kassa
--   kuni» undan oldin bo'lsa (kassa_receipt ishga tushishni tekshirmaydi, kun birinchi hujjat bilan ochiladi). Shunda «first» — birinchi
--   kassa kuni: u kun ham kassa kitobida, ishga tushgach kassa hujjatisiz naqd yozuv unga tushmaydi (Direktorga ham — kassa:live_day);
--   undan oldingi kun — avvalgidek (Direktor). Ssenariy savepoint ichida (natija psql o'zgaruvchisida): keyingi bo'limlar 04.01 dan boshlanadi.
savepoint kpf;
select zz.put('KF1', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":0,"startDay":"2027-01-03"}')::text$q$));
select zz.put('KF2', zz.as('U_KAS', $q$select public.kassa_receipt('{"op":"in_other","amount":5000,"partyType":"other","partyName":"Sinov Shaxs","articleId":"IN-06","basis":"Tilxat","note":"Kitob uchun","fiscalNo":"F-KF1","clientRef":"kf-rcp-00001"}')::text$q$));
select zz.put('KF3', (select (app.kassa_periods('main') ->> 'first') is null)::text);
select zz.clock('2027-01-04 10:00+05');
select zz.put('KF4', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-01-04"}')::text$q$));
select (case when zz.get('KF2') like '{%' then zz.js(zz.get('KF2')) ->> 'businessDay' else zz.get('KF2') end) || ':' || zz.get('KF3')
  || ' | ' || (case when zz.get('KF4') like '{%' then zz.js(zz.get('KF4')) ->> 'kassaGoLive' else zz.get('KF4') end)
  || ' | ' || (app.kassa_periods('main') ->> 'first') || ':' || app.kassa_pre_day('main', '2027-01-03')::text || ':' || app.kassa_pre_day('main', '2027-01-02')::text
  || ' | ' || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_kf1', '2027-01-03', '2027-01', 'Boshqa', 7000, 'birinchi kassa kuni', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_kf2', '2027-01-02', '2027-01', 'Boshqa', 7000, 'kassadan oldingi kun', 'cash') returning id) select id from x$q$) as kpf \gset
rollback to savepoint kpf;
select zz.chk('KF g8: birinchi kassa kuni (03.01) ishga tushadigan kundan (04.01) oldin — «first» = 03.01 (ishga tushmagan kassada — bo''sh); 03.01 sanali kassa hujjatisiz naqd xarajat Direktorga ham rad (kassa:live_day), 02.01 — Direktor kiritadi',
  :'kpf', '^2027-01-03:true \| 2027-01-04 \| 2027-01-03:false:true \| ERR 42501 \[kassa:live_day\].* \| e_kf2$');
-- g8: kassa hali ishlamagan (yashirin o'rnatilgan — asosiy kassa kuni yo'q): reverse_payment avansdan qaytarib olishi — avvalgidek (N3 — ishlagach)
savepoint n0;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values ('sN0','T-N0','Sinov N0',5,'A','uz','',91,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values ('iN0','T-N0','Sinov N0','2027-01',500000,0,'pending');
set local session_replication_role = origin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select left(public.apply_payment('T-N0', 600000, 'click', 'clk_n0_0001')::text, 0);   -- faktura 500 000 to'landi, avans 100 000
select set_config('request.jwt.claims', '', true);
select zz.as('U_FM', $q$select (public.reverse_payment('iN0', 600000, 'click', 'mrev:n0a') ->> 'ok') || ':' || trim_scale((public.reverse_payment('iN0', 600000, 'click', 'mrev:n0a') ->> 'fromCredit')::numeric)$q$)
  || ' | ' || (select count(*) from public.cash_days) as n0 \gset
rollback to savepoint n0;
select zz.chk('N0 kassa hali ishlamagan (kassa kuni yo''q): Moliya menejeri reverse_payment bilan avansdan ham qaytarib oladi — avvalgidek', :'n0', '^true:100000 \| 0$');
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
  (zz.js(zz.get('PL1')) ->> 'ok') || ':' || zz.jd(zz.get('PL1'), 'kassa', 'null') || ':' || (zz.js(zz.get('PL1')) ->> 'day'), '^true:null:2027-01-03$');
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
  zz.jd(zz.get('PL5'), 'kassa', 'null') || ':' || (select (raw ->> 'date') || ':' || coalesce("cashDocId", '-') from public.payments where id = 'man_pl5_0001'),
  '^null:2027-01-02:-$');
select zz.put('PL6q', zz.as('U_DIR', $q$select public.fin_period_lock('2027-01-02', '')::text$q$));
select zz.chk('PL6 davr qulfi baribir: 02.01 gacha yopilgan davrga Direktor ham kassadan oldingi to''lovni kirita olmaydi',
  (zz.js(zz.get('PL6q')) ->> 'lockedThrough') || ' | ' || zz.payd('U_DIR', 'man_pl6_0001', 'T-6', 1000, 'cash', '2027-01-02', null, null),
  '^2027-01-02 \| ERR 42501 \[fin:locked\]');
select zz.chk('PL6b qulf olib tashlandi (sabab bilan)',
  zz.jd(zz.as('U_DIR', $q$select public.fin_period_lock(null, 'Sinov: qulf olib tashlandi')::text$q$), 'lockedThrough', 'yo''q'), '^yo''q$');
select zz.chk('PL7 so''ralgan sana ishga tushishdan oldin va 31 kunlik oraliqdan tashqarida (01.12) — bugungi KO-1 bo''lib ikki marta hisoblanmaydi: rad, iz yo''q',
  zz.payd('U_KAS', 'man_pl7_0001', 'T-6', 10000, 'cash', '2026-12-01', null, '{"fiscalNo":"F-PL7"}') || ' / ' || (select count(*) from public.payments where id = 'man_pl7_0001')
  || '/' || (select count(*) from public.cash_docs where "sourceId" = 'man_pl7_0001'), '^ERR 22023 \[kassa:pre_live_old\].* / 0/0$');
select zz.chk('PL8 nazorat ro''yxati: «ishga tushishdan oldingi naqd yozuvlar (keyin kiritilgan)» — o''quv to''lovi 2 ta, 500 000',
  (select (c -> 'preLive')::text from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q),
  '"goLive": "2027-01-04"') ;
select zz.chk('PL8b ro''yxat mazmuni', (select (c #>> '{preLive,items,0,kind}') || ':' || (c #>> '{preLive,items,0,n}') || ':' || (c #>> '{preLive,items,0,sum}')
  from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q), '^tuition:2:500000$');
select zz.chk('PL9 moslik (ishga tushgan kundan): kassadan oldingi kun to''lovlari P1 ga kirmaydi', (select app.kassa_reconcile(null, null) ->> 'total'), '^0$');

-- ---------- Taqsimot ----------
select zz.put('J3', zz.pay('U_KAS', 'man_j3_0001', 'T-1', 1400000, 'cash', 'Sinov Ota', null, '{"fiscalNo":"F-1"}'));
select zz.chk('J3 naqd 1 400 000: javobda KO-1 № 1, kun 04.01.2027', zz.get('J3'), '"kassa": \{.*"no": 1[,}]');
select zz.chk('J3a javobdagi kun — kassa kuni', (zz.js(zz.get('J3')) ->> 'day') || '/' || (zz.js(zz.get('J3')) -> 'kassa' ->> 'day'), '^2027-01-04/2027-01-04$');
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
-- (eski mijoz pulni balansga kassa ishga tushishidan OLDIN qo'llagan, holatni 'applied' qilolmay qolgan: shu holat server roli bilan tiklanadi —
--   kassa ishlayotganda to'g'ridan-to'g'ri naqd apply_payment endi Direktorga ham rad etiladi, state-4: N-bandlar)
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select zz.put('J15a', public.apply_payment('T-2', 20000, 'cash', 'man_legacy_002')::text);
select set_config('request.jwt.claims', '', true);
select zz.put('J15', zz.pay('U_KAS', 'man_legacy_002', 'T-2', 20000, 'cash', '', null, '{"fiscalNo":"F-5"}'));
select zz.chk('J15 balansga avval qo''llangan to''lov: pul ikki marta qo''llanmaydi, KO-1 bitta qator bilan (taqsimot noma''lum — belgilanadi)',
  (zz.js(zz.get('J15')) ->> 'dup') || ':' || (zz.js(zz.get('J15')) -> 'kassa' ->> 'allocation') || ' / ' || zz.lines('man_legacy_002') || ' / ' ||
  (select trim_scale(credit)::text from public.student_credit where id = 'T-2'), '^true:unknown / 5010>4010=20000 / 110000$');   -- T-2 avansi: 70 000 (bank) + 10 000 + 10 000 + 20 000 — ikki marta qo'shilmagan
-- qa-2: taqsimoti aniq bo'lmagan o'quv to'lovi orderi ('unknown' — balansga avval qo'llangan; 'fallback' — taqsimot nazoratdan o'tmagan)
--   avtomatik bekor qilinmaydi: taqsimotda qaytariladigan faktura qatori yo'q — bekor qilinsa to'lov bekor bo'lib, faktura / avans
--   to'langanicha qolardi (o'quvchi qarzi kam ko'rinardi). Tuzatish — Direktorning «Qaytarish» amali.
create or replace function zz.j15s() returns text language sql as $$
  select (select c.status || ':' || p.status || ':' || trim_scale(c.amount) from public.payments p join public.cash_docs c on c.id = p."cashDocId" where p.id = 'man_legacy_002')
         || ':' || (select trim_scale(credit)::text from public.student_credit where id = 'T-2')
         || ':' || coalesce((select string_agg(i.id || '=' || trim_scale(i."paidAmount") || '/' || i.status, ',' order by i.id) from public.invoices i where i."studentId" = 'T-2'), '-')
         || ':' || trim_scale(app.kassa_day_balance((select d.id from public.cash_days d where d.desk = 'main' and d.status = 'open')))::text $$;
select zz.put('J15s', zz.j15s());
select zz.put('J15v', zz.as('U_KAS', format('select public.kassa_doc_void(%L, %L)::text', (select "cashDocId" from public.payments where id = 'man_legacy_002'), 'Summa xato kiritildi')));
select zz.chk('J15b qa-2: taqsimoti noma''lum KO-1 ni kassir bekor qila olmaydi (kassa:not_reversible) — order, to''lov, avans, faktura va kassa qoldig''i o''zgarmadi',
  zz.get('J15v') || ' | ' || zz.j15s() || ' | ' || (zz.j15s() = zz.get('J15s'))::text,
  '^ERR P0001 \[kassa:not_reversible\] Bu to''lovning taqsimoti aniq emas — avtomatik bekor qilinmaydi \(Direktor: «Qaytarish»\) \| posted:applied:20000:110000:.* \| true$');
savepoint j15c;
select left(zz.pay('U_KAS', 'man_j15c_001', 'T-1', 5000, 'cash', '', null, '{"fiscalNo":"F-J15C"}'), 0);
set local session_replication_role = replica;
update public.cash_docs set "sourceSnapshot" = jsonb_set("sourceSnapshot", '{allocation}', '"fallback"') where id = (select "cashDocId" from public.payments where id = 'man_j15c_001');
set local session_replication_role = origin;
select coalesce((select c."sourceSnapshot" ->> 'allocation' from public.cash_docs c join public.payments p on p."cashDocId" = c.id where p.id = 'man_j15c_001'), '<null>')
  || ' | ' || zz.as('U_KAS', format('select public.kassa_doc_void(%L, %L)::text', (select "cashDocId" from public.payments where id = 'man_j15c_001'), 'Summa xato kiritildi')) as j15c \gset
select :'j15c' || ' | ' || coalesce((select c.status || ':' || p.status from public.payments p join public.cash_docs c on c.id = p."cashDocId" where p.id = 'man_j15c_001'), '<null>') as j15c \gset
rollback to savepoint j15c;
select zz.chk('J15c qa-2: taqsimoti nazoratdan o''tmagan (''fallback'', tizim shunday yozgan holat) KO-1 ham — rad (kassa:not_reversible), order va to''lov joyida',
  :'j15c', '^fallback \| ERR P0001 \[kassa:not_reversible\].* \| posted:applied$');

-- ---------- Shu kunda bekor qilish (kassir xatosi) ----------
select zz.put('V1', zz.pay('U_KAS', 'man_v1_0001', 'T-1', 30000, 'cash', '', null, '{"fiscalNo":"F-20"}'));
select zz.chk('V1 xato kiritilgan to''lov: faktura 180 000 bo''ldi, xabarnoma navbatda',
  (select trim_scale("paidAmount")::text from public.invoices where id = 'id') || ':' || (zz.js(zz.get('V1')) -> 'kassa' ->> 'no') || ':' ||
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
-- ---------- (N) state-4: kassa hujjatisiz naqd to'lov qatori yo'q (F1.13 qabul mezoni: «RPC ni chetlab o'tadigan naqd yo'l yo'q») ----------
--   Eski 3 bosqichli yo'l (qator + apply_payment + holat) va unga yaqin yo'llar kassa qo'llanadigan kun bilan rad: kirim orderisiz, fiskal
--   cheksiz pul fakturaga tushmasin. «💵 To'lov» (record_manual_payment) va server (webhook) — avvalgidek. Holatni o'zgartiradigan ijobiy
--   holatlar savepoint ichida (natija psql o'zgaruvchisida) — keyingi tekshiruvlar qoldig'iga ta'sir qilmasin.
select zz.chk('N1 naqd to''lov qatorini to''g''ridan-to''g''ri yozish — kassir (pending), Moliya menejeri (applied), Direktor (bugungi «Sana» bilan) — rad, iz yo''q',
  zz.as('U_KAS', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n1_0001', 'T-1', 'cash', 100000, 'pending', true, '{"manual":true}') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n1_0002', 'T-1', 'cash', 100000, 'applied', true, '{}') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n1_0003', 'T-1', 'cash', 100000, 'applied', true, '{"manual":true,"date":"2027-01-04"}') returning id) select id from x$q$) || ' | '
  || (select count(*) from public.payments where id like 'man_n1_%'),
  '^ERR 42501 \[kassa:cash_only_kassa\] Kassa ishga tushgan: naqd o''quv to''lovi faqat «💵 To''lov» oynasi orqali.* \| ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_only_kassa\].* \| 0$');
select zz.chk('N1b apply_payment «naqd» kanal bilan to''g''ridan-to''g''ri: Direktor (yozuvsiz) ham — rad; apply_to_invoice ham — rad',
  zz.as('U_DIR', $q$select public.apply_payment('T-1', 5000, 'cash', 'x_n1b_0001')::text$q$) || ' | '
  || zz.as('U_DIR', $q$select public.apply_to_invoice('ic', 5000, 'cash', 'x_n1b_0002')::text$q$) || ' | '
  || (select count(*) from public.applied_payments where id like 'x_n1b_%'),
  '^ERR 42501 \[kassa:cash_only_kassa\] Kassa ishga tushgan: naqd pul balansga faqat «💵 To''lov» oynasi orqali.* \| ERR 42501 \[kassa:cash_only_kassa\].* \| 0$');
-- ichki pul RPC'si bayrog'i (iqror.money_rpc) «💵 To'lov» tugagach tozalanadi: o'sha tranzaksiyadagi keyingi to'g'ridan-to'g'ri naqd yozuv — rad
savepoint n1c;
select zz.put('N1c1', zz.pay('U_KAS', 'man_n1c_0001', 'T-1', 1000, 'cash', '', null, '{"fiscalNo":"F-N1C"}'));
select zz.put('N1c2', coalesce(nullif(current_setting('iqror.money_rpc', true), ''), 'bo''sh'));
select zz.put('N1c3', zz.as('U_FM', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n1c_0002', 'T-1', 'cash', 1000, 'applied', true, '{}') returning id) select id from x$q$));
select (case when zz.get('N1c1') like '{%' then (zz.js(zz.get('N1c1')) ->> 'ok') || ':' || zz.jdp(zz.get('N1c1'), '{kassa,status}', '-') else zz.get('N1c1') end)
  || ' | ' || zz.get('N1c2') || ' | ' || zz.get('N1c3') as n1c \gset
rollback to savepoint n1c;
select zz.chk('N1c «💵 To''lov» (kirim orderi bilan) tugagach ichki bayroq tozalangan: keyingi to''g''ridan-to''g''ri naqd qator — rad', :'n1c',
  '^true:posted \| bo''sh \| ERR 42501 \[kassa:cash_only_kassa\]');
savepoint n2;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values ('sN','T-N1','Sinov N',5,'A','uz','',90,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values ('iN1','T-N1','Sinov N','2027-01',500000,0,'pending');
insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw, "createdAt") values
  ('man_n2_old', 'T-N1', 'cash', 40000, 'pending', '', true, '{"manual":true}', '2027-01-04 09:30+05'),   -- eski mijoz qoldirgan «pending»
  ('bnk_n2', 'T-N1', 'bank', 30000, 'applied', '', true, '{"manual":true}', '2027-01-04 09:40+05'),
  ('clk_n2u', '', 'click', 60000, 'unmatched', 'Noma''lum', false, '{}', '2027-01-04 09:50+05');
set local session_replication_role = origin;
select zz.as('U_KAS', $q$with x as (update public.payments set status = 'applied' where id = 'man_n2_old' returning id) select id from x$q$) || ' | '
  || zz.as('U_KAS', $q$select public.apply_payment('T-N1', 40000, 'cash', 'man_n2_old')::text$q$) || ' | '
  || zz.as('U_FM', $q$with x as (update public.payments set provider = 'cash' where id = 'bnk_n2' returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$select public.split_payment('clk_n2u', 'cash', '[{"sid":"T-N1","amount":60000}]')::text$q$) || ' | '
  || (select status || ':' || provider from public.payments where id = 'man_n2_old') || ':' || (select status from public.payments where id = 'clk_n2u')
  || ':' || (select trim_scale("paidAmount")::text from public.invoices where id = 'iN1') as n2 \gset
-- ijobiy: o'sha yo'llar naqdsiz kanal bilan — avvalgidek; eski «pending» naqd qatorni «💵 To'lov» tugatadi (kirim orderi bilan)
select zz.jd(zz.as('U_FM', $q$select public.split_payment('clk_n2u', 'click', '[{"sid":"T-N1","amount":60000}]')::text$q$), 'ok', 'ERR') || ':'
  || zz.jd(zz.as('U_DIR', $q$select public.apply_payment('T-N1', 10000, 'bank', 'x_n2_bank')::text$q$), 'ok', 'ERR') || ':'
  || zz.jdp(zz.pay('U_KAS', 'man_n2_old', 'T-N1', 40000, 'cash', '', null, '{"fiscalNo":"F-N2"}'), '{kassa,status}', 'ERR') as n2b \gset
-- (faktura alohida so'rov bilan o'qiladi: yuqoridagi so'rov o'z boshidagi holatni ko'radi)
select :'n2b' || ':' || (select trim_scale("paidAmount")::text from public.invoices where id = 'iN1') as n2b \gset
rollback to savepoint n2;
select zz.chk('N2 eski 3 bosqichli yo''l: «pending» naqd qatorni «qo''llangan» qilish, uni apply_payment bilan qo''llash, bank qatorini naqdga o''zgartirish, bo''lishda «naqd» bola qator — rad; holat o''zgarmadi',
  :'n2', '^ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_only_kassa\].* \| pending:cash:unmatched:0$');
select zz.chk('N2b ijobiy: bo''lish (Click), Direktorning naqdsiz apply_payment''i — avvalgidek; eski «pending» naqd qator «💵 To''lov» bilan kirim orderi orqali tugadi (faktura 60 000 + 10 000 + 40 000)',
  :'n2b', '^true:true:posted:110000$');
-- reverse_payment (eski pul RPC'si): kassa hujjati bilan to'langan qism ayirilmaydi; naqdsiz qismi — avvalgidek; avansdan qaytarib olish — faqat server
savepoint n3;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values ('sN','T-N1','Sinov N',5,'A','uz','',90,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('iN1','T-N1','Sinov N','2027-01',500000,0,'pending'), ('iN2','T-N1','Sinov N','2027-02',500000,0,'pending');
set local session_replication_role = origin;
select left(zz.pay('U_KAS', 'man_n3_0001', 'T-N1', 300000, 'cash', '', null, '{"fiscalNo":"F-N3"}'), 0);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select left(public.apply_payment('T-N1', 100000, 'click', 'clk_n3_0001')::text, 0);   -- Click (server): faktura 400 000 = naqd 300 000 + Click 100 000
select left(public.apply_to_invoice('iN2', 100000, 'click', 'clk_n3_0002')::text, 0);   -- fevral fakturasi — faqat Click (kassa hujjatisiz)
select set_config('request.jwt.claims', '', true);
select zz.as('U_FM', $q$select public.reverse_payment('iN1', 100001, 'click', 'mrev:n3a')::text$q$) || ' | '
  || zz.as('U_DIR', $q$select public.reverse_payment('iN1', 400000, 'cash', 'mrev:n3b')::text$q$) || ' | '
  || zz.as('U_FM', $q$select public.reverse_payment('iN2', 150000, 'click', 'mrev:n3c')::text$q$) || ' | '
  || (zz.js(zz.as('U_FM', $q$select public.reverse_payment('iN1', 100000, 'click', 'mrev:n3d')::text$q$)) ->> 'newPaid') || ' | '
  || (zz.js(zz.as('U_FM', $q$select public.reverse_payment('iN1', 100000, 'click', 'mrev:n3d')::text$q$)) ->> 'dup') as n3 \gset
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select (public.reverse_payment('iN1', 300000, 'uzum', 'uz_n3_0001') ->> 'newPaid') as n3s \gset
select set_config('request.jwt.claims', '', true);
rollback to savepoint n3;
select zz.chk('N3 reverse_payment: kirim orderi bilan to''langan 300 000 ayirilmaydi (Moliya menejeri ham, Direktor ham); avansdan qaytarib olish — rad; Click qismi (100 000) — avvalgidek, takrori — dup; server (provayder qaytarishi) — mustasno',
  :'n3' || ' | ' || :'n3s',
  '^ERR 42501 \[kassa:linked_row\] Bu fakturaning 300000 so''m qismi kassa hujjati.*ayirish mumkin: 100000 so''m.* \| ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:reverse_credit\] Ayiriladigan summa fakturaning to''langan qismidan \(100000 so''m\) katta.* \| 300000 \| true \| 0$');
-- g8 (tekshiruvchi): avansni kamaytirish add_credit (manfiy delta) bilan ham — kassa ishlay boshlagach faqat Direktor yoki server
--   (reverse_payment bilan bir qoida, kassa:reverse_credit); Moliya menejeriga — rad, iz yo'q (applied_payments posboniga ham yozilmaydi)
savepoint n3b;
select zz.as('U_FM', $q$select public.add_credit('T-1', -1000, 'recompute', '', 'n3b-fm')::text$q$) || ' | '
  || zz.jd(zz.as('U_DIR', $q$select public.add_credit('T-1', -1000, 'recompute', '', 'n3b-dir')::text$q$), 'ok', 'ERR') as n3b \gset
-- (posbon yozuvlari alohida so'rov bilan o'qiladi: yuqoridagi so'rov o'z boshidagi holatni ko'radi)
select :'n3b' || ' | ' || (select count(*) from public.applied_payments where id like 'addcredit:n3b-%') as n3b \gset
rollback to savepoint n3b;
select zz.chk('N3b add_credit manfiy delta (avansni kamaytirish) kassa ishlay boshlagach: Moliya menejeri — rad (kassa:reverse_credit, iz yo''q), Direktor — avvalgidek',
  :'n3b', '^ERR 42501 \[kassa:reverse_credit\] Kassa ishlay boshlagach o''quvchi avansini kamaytirish.* \| true \| 1$');
-- kassa ishlamagan kun (03.01 — ishga tushishdan oldin): to'g'ridan-to'g'ri naqd qator — faqat Direktor (kech qog'oz), boshqalarga — rad
savepoint n4;
select zz.as('U_KAS', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n4_0001', 'T-1', 'cash', 1000, 'pending', true, '{"manual":true,"date":"2027-01-03"}') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n4_0002', 'T-1', 'cash', 1000, 'pending', true, '{"manual":true,"date":"2027-01-03"}') returning id) select id from x$q$) as n4 \gset
rollback to savepoint n4;
select zz.chk('N4 kassa ishlamagan kun (03.01) sanali naqd qator: kassir — rad (kassa:pre_live), Direktor — avvalgidek', :'n4', '^ERR 42501 \[kassa:pre_live\] To''lov kuni \(03\.01\.2027\).* \| man_n4_0002$');
-- g8 (tekshiruvchi): kanal yozuvi katta-kichik harf yoki bo'sh joy bilan ('CASH', ' Cash ') ham naqd — to'g'ridan-to'g'ri qator va naqd kanal
--   bilan apply_payment / apply_to_invoice rad (kassa_pay_guard, audit-7.sql, audit-5.sql)
select zz.chk('N1d «CASH» / « Cash » kanal yozuvi ham naqd: kassir va Moliya menejeri qatori, Direktorning apply_payment / apply_to_invoice''i — rad, iz yo''q',
  zz.as('U_KAS', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n1d_0001', 'T-1', 'CASH', 100000, 'pending', true, '{"manual":true}') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n1d_0002', 'T-1', ' Cash ', 100000, 'applied', true, '{}') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$select public.apply_payment('T-1', 5000, 'CASH', 'x_n1d_0001')::text$q$) || ' | '
  || zz.as('U_DIR', $q$select public.apply_to_invoice('ic', 5000, ' Cash', 'x_n1d_0002')::text$q$) || ' | '
  || (select count(*) from public.payments where id like 'man_n1d_%') || ':' || (select count(*) from public.applied_payments where id like 'x_n1d_%'),
  '^ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_only_kassa\].* \| 0:0$');
-- g8 (tekshiruvchi): kassa ishlayotganda mavjud «pending» qatorni BOSHQA usul bilan tugatish — «mismatch» (record_manual_payment): eski naqd
--   qator «bank» deb kirim orderisiz qo'llanmaydi, «bank» qatoriga kirim orderi yozilmaydi; o'sha usul bilan — avvalgidek (savepoint ichida)
savepoint n6;
set local session_replication_role = replica;
insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw, "createdAt") values
  ('man_n6_old', 'T-1', 'cash', 40000, 'pending', '', true, '{"manual":true,"date":"2027-01-03"}', '2027-01-03 15:00+05'),   -- kassadan oldingi eski «pending»
  ('man_n6_bnk', 'T-1', 'bank', 30000, 'pending', '', true, '{"manual":true}', '2027-01-04 09:00+05');
set local session_replication_role = origin;
select zz.put('N6a', zz.pay('U_KAS', 'man_n6_old', 'T-1', 40000, 'bank', '', null, null));
select zz.put('N6b', zz.pay('U_KAS', 'man_n6_bnk', 'T-1', 30000, 'cash', '', null, '{"fiscalNo":"F-N6"}'));
select zz.put('N6c', zz.pay('U_KAS', 'man_n6_bnk', 'T-1', 30000, 'bank', '', null, null));
-- (javob JSON bo'lsa — «reason», bo'lmasa «status»; xato matni — o'zi: mutatsiyada FAIL, to'plam to'xtamaydi)
select (select string_agg(case when zz.get(k) like '{%' then coalesce(zz.js(zz.get(k)) ->> 'reason', zz.js(zz.get(k)) ->> 'status') else zz.get(k) end, ' | ' order by k)
          from unnest(array['N6a', 'N6b', 'N6c']) k)
  || ' | ' || coalesce((select string_agg(id || '=' || status || ':' || provider || ':' || coalesce("cashDocId", '-'), ',' order by id) from public.payments where id like 'man_n6_%'), '-')
  || ' | ' || (select count(*) from public.cash_docs where "sourceId" like 'man_n6_%') as n6 \gset
rollback to savepoint n6;
select zz.chk('N6 g8: «pending» qatorni boshqa usul bilan tugatish — rad (mismatch): eski naqd qator «bank» deb, bank qatori «naqd» deb (kirim orderi bilan); o''sha usul bilan — qo''llanadi (kirim orderisiz)',
  :'n6', '^mismatch \| mismatch \| applied \| man_n6_bnk=applied:bank:-,man_n6_old=pending:cash:- \| 0$');
-- g8 (tekshiruvchi): createdAt bo'sh eski naqd to'lov qatori (import) — kassa ishlayotganda to'lovchi ismini tuzatish kabi o'zgarish
--   avvalgidek o'tadi (kassa_pay_guard eski va yangi kunni bir xil hisoblaydi; avval «kuni ko'chdi» deb kassa:cash_only_kassa bilan rad etilardi)
savepoint n7;
set local session_replication_role = replica;
insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw, "createdAt") values
  ('man_n7_old', 'T-1', 'cash', 1000, 'applied', '', true, '{}', null);
set local session_replication_role = origin;
select zz.as('U_FM', $q$with x as (update public.payments set "payerName" = 'Tuzatildi' where id = 'man_n7_old' returning id) select id from x$q$) as n7 \gset
select :'n7' || ' | ' || coalesce((select "payerName" from public.payments where id = 'man_n7_old'), '-') as n7 \gset
rollback to savepoint n7;
select zz.chk('N7 createdAt bo''sh eski naqd to''lov qatorining to''lovchi ismini tuzatish (kassa ishlayapti) — avvalgidek o''tadi', :'n7', '^man_n7_old \| Tuzatildi$');
select zz.chk('J19 kun yopildi: farq 0', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-01-04","counted":3090000}')::text$q$), '"diff": 0[,}]');
select zz.clock('2027-01-05 09:00+05');
select zz.put('J20', zz.pay('U_KAS', 'man_j20_001', 'T-2', 30000, 'cash', '', null, '{"fiscalNo":"F-6"}'));
select zz.chk('J19b yopilgan kun to''lovi bekor qilinmaydi',
  zz.as('U_FM', format('select public.kassa_doc_void(%L, %L)::text', (select "cashDocId" from public.payments where id = 'man_legacy_001'), 'Sinov: yopilgan kun')), '^ERR P0001 \[kassa:day_closed\]');
select zz.chk('J20 ertasi kun: yangi kun (kun boshi 3 090 000), raqam davom etadi (№ 9)',
  (zz.js(zz.get('J20')) -> 'kassa' ->> 'no') || ':' || (zz.js(zz.get('J20')) -> 'kassa' ->> 'day') || ':' || (select trim_scale(opening)::text from public.cash_days where status = 'open'), '^9:2027-01-05:3090000$');
select zz.clock('2027-01-06 09:00+05');
select zz.chk('J21 kecha yopilmagan: naqd to''lov rad, to''lov ham yozilmaydi (CT-04, atomar)',
  zz.pay('U_KAS', 'man_j21_001', 'T-2', 1000, 'cash', '', null, '{"fiscalNo":"F-7"}') || ' / ' || (select count(*) from public.payments where id = 'man_j21_001')
  || '/' || (select count(*) from public.applied_payments where id = 'man_j21_001'), '^ERR P0001 \[kassa:prev_open\].* / 0/0$');
select zz.put('J22', zz.pay('U_KAS', 'man_j22_001', 'T-2', 2000, 'cash', '', '2027-01-05 16:00+05', '{"fiscalNo":"F-7"}'));
select zz.chk('J22 kecha olingan (oflayn navbatdagi) to''lov — hali ochiq kechagi kunga', (zz.js(zz.get('J22')) -> 'kassa' ->> 'day') || ':' || (zz.js(zz.get('J22')) -> 'kassa' ->> 'late'), '^2027-01-05:false$');
select zz.chk('J23 kechagi kun yopildi', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-01-05","counted":3122000}')::text$q$), '"diff": 0[,}]');
select zz.put('J24', zz.pay('U_KAS', 'man_j24_001', 'T-2', 3000, 'cash', '', '2027-01-05 17:00+05', '{"fiscalNo":"F-10"}'));
select zz.chk('J24 olingan kuni yopilgan: bugungi kunga «kech» belgisi bilan; hisobot kuni ham bugun',
  (zz.js(zz.get('J24')) -> 'kassa' ->> 'day') || ':' || (zz.js(zz.get('J24')) -> 'kassa' ->> 'late') || ':' || (select raw ->> 'date' from public.payments where id = 'man_j24_001'), '^2027-01-06:true:2027-01-06$');
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
  (zz.js(zz.get('M0')) -> 'day' ->> 'status') || ' / ' || (zz.js(zz.get('M1')) -> 'kassa' ->> 'day') || ' / ' || zz.lines('man_m1_0001'), '^closed / 2027-01-31 / 5010>6310=400000@2027-02$');
select zz.chk('M2 oflayn: 31.01 da olingan, yarim tundan keyin yuborilgan — hali ochiq 31.01 kuniga, fevral fakturasi o''sha kun bo''yicha Kt 6310; taqsimot yozuvi ham 6310',
  (zz.js(zz.get('M2')) -> 'kassa' ->> 'day') || ':' || (zz.js(zz.get('M2')) -> 'kassa' ->> 'late') || ' / ' || zz.lines('man_m2_0001')
  || ' / ' || (select string_agg(account || '@' || month, ',') from public.payment_allocations where "paymentId" = 'man_m2_0001'),
  '^2027-01-31:false / 5010>6310=400000@2027-02 / 6310@2027-02$');
select zz.put('M3', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-01-31","counted":3925000}')::text$q$));
select zz.clock('2027-02-01 10:00+05');
select zz.put('M4', zz.pay('U_KAS', 'man_m4_0001', 'T-5', 400000, 'cash', '', null, '{"fiscalNo":"F-33"}'));
select zz.put('M5', zz.pay('U_KAS', 'man_m5_0001', 'T-4', 400000, 'cash', '', null, '{"fiscalNo":"F-34"}'));
select zz.chk('M3 31.01 yopildi; 01.02 kuni: fevral fakturasi — Kt 4010 (fevral boshlangan), mart — Kt 6310',
  (zz.js(zz.get('M3')) -> 'day' ->> 'status') || ' / ' || (zz.js(zz.get('M4')) -> 'kassa' ->> 'day') || ' ' || zz.lines('man_m4_0001')
  || ' / ' || (zz.js(zz.get('M5')) -> 'kassa' ->> 'day') || ' ' || zz.lines('man_m5_0001'),
  '^closed / 2027-02-01 5010>4010=400000@2027-02 / 2027-02-01 5010>6310=400000@2027-03$');

-- ---------- ui-5 + ishga-tushirish §9: kassani TO'XTATISH (sanani bo'shatish / surish) va QAYTA ISHGA TUSHIRISH ----------
--   To'xtatish — faqat Direktor, ochiq kun va pul berilmagan so'rovlar bo'lmasa; kassa to'xtaydi (hujjat yozilmaydi, naqd — kassa
--   hujjatisiz). Qayta ishga tushirish — komissiya sanashi: sanalgan summa bilan oxirgi kun oxiri farqi — texnik dalolatnoma «Д-»
--   (OP-23, Dt 5010 Kt 0000), qayta ochilgan birinchi kun boshi = sanalgan summa: to'xtatilgan davr puli kassirga kamomad / ortiqcha bo'lmaydi.
--   01.02 kun ochiq: kun boshi 3 925 000, kirim 800 000 → hisobda 4 725 000.
set local session_replication_role = replica;
insert into public.fin_counterparties (id, kind, name) values ('cp_sup','supplier','Sinov Ta''minot MChJ');
insert into public.users (id, email, role, status, "extraRoles") values ('U_KAS2','k2@x','kassir','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email;
set local session_replication_role = origin;
-- state-6: smena topshirish qabul qilinmagan (pul sanalgan, ikki kassir kassa yonida) — kassa to'xtatilmaydi (alohida hint, ochiq kundan oldin)
select zz.put('R00', zz.as('U_KAS', $q$select public.kassa_handover('{"counted":4725000,"toUid":"U_KAS2"}')::text$q$));
select zz.chk('R00 kutilayotgan smena topshirish — kassani to''xtatib bo''lmaydi (kassa:rollback_handover: avval qabul yoki bekor); bekor qilingach — keyingi qoida (ochiq kun)',
  (case when zz.get('R00') ~ '^\s*\{' then zz.js(zz.get('R00')) #>> '{handover,status}' else left(zz.get('R00'), 200) end)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$)
  || ' | ' || coalesce((select "pausedAt"::text from public.cash_desks where id = 'main'), 'ishlaydi')
  || ' | ' || (select case when r ~ '^\s*\{' then zz.js(r) #>> '{handover,status}' else left(r, 200) end
                 from (select zz.as('U_KAS', format('select public.kassa_handover_cancel(%L, %L)::text', substring(zz.get('R00') from '"id": "(ho_[0-9a-f]+)"'), 'To''xtatish rejalashtirilgan')) r) q),
  '^pending \| ERR P0001 \[kassa:rollback_handover\] Kassani to''xtatib bo''lmaydi: smena topshirish qabul qilinmagan — avval qabul qiluvchi uni qabul qilsin yoki topshirish bekor qilinsin.* \| ishlaydi \| cancelled$');
select zz.chk('R0 ochiq kassa kuni bor — kassani to''xtatib bo''lmaydi (sana o''zgarmadi, kassa to''xtamadi)',
  zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$) || ' | ' || (select "kassaGoLive"::text from public.fin_org where id = 'main')
  || ' | ' || coalesce((select "pausedAt"::text from public.cash_desks where id = 'main'), 'ishlaydi'),
  '^ERR P0001 \[kassa:rollback_open_day\].*01\.02\.2027.* \| 2027-01-04 \| ishlaydi$');
select zz.put('R1', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-01","counted":4725000}')::text$q$));
select zz.put('R2', zz.as('U_KAS', $q$select public.kassa_payout_request('{"op":"out_expense","amount":15000,"partyType":"counterparty","partyId":"cp_sup","articleId":"EX-16","basis":"Hisob-faktura 7","clientRef":"r2-req-00001"}')::text$q$));
select zz.chk('R1 kun yopildi (farq 0); R2 pul berilmagan so''rov bor — to''xtatib bo''lmaydi, so''rov nomlanadi',
  (zz.js(zz.get('R1')) ->> 'diff') || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$),
  '^0 \| ERR P0001 \[kassa:rollback_requests\].*chiqim «Xarajat» 15000 so''m — tasdiq kutilmoqda$');
select zz.chk('R2b kassir sozlamani o''zgartira olmaydi (faqat Direktor)', zz.as('U_KAS', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$), '^ERR 42501');
select zz.put('R3', left(zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.js(zz.get('R2')) ->> 'id', 'To''xtatishdan oldin')), 0)
  || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-20"}')::text$q$));
select zz.chk('R3 so''rov bekor qilindi; Direktor sanani 20.02 ga SURDI — kassa to''xtadi: sana bo''sh saqlanadi, rejalashtirilgan kun hodisada (kim, qachon)',
  zz.jd(zz.get('R3'), 'kassaGoLive', 'bo''sh') || ' | ' || (select ("pausedAt" is not null) || ':' || "pausedBy" from public.cash_desks where id = 'main')
  || ' | ' || (select "byUid" || ':' || (data ->> 'from') || '>' || (data ->> 'to') || ':pause=' || (data ->> 'pause') from public.cash_day_events where kind = 'golive' order by at desc, id desc limit 1),
  '^bo''sh \| true:U_DIR \| U_DIR:2027-01-04>2027-02-20:pause=true$');
-- g4r-2: to'xtatilgan kassada oxirgi kassa kuni (01.02) va undan oldingi sana bilan kassa hujjatisiz naqd yozuv hech kimga yo'q —
--   to'xtatilgan kunning o'zida (kun yopilgandan keyin) olingan pul ertasi kuni kiritiladi (R4a)
select zz.chk('R4 to''xtatilgan kassa, bugun = oxirgi kassa kuni (01.02): naqd o''quv to''lovi va naqd xarajat rad (kassa:paused_live_day), iz yo''q',
  zz.pay('U_KAS', 'man_r4_0000', 'T-5', 60000, 'cash', '', null, null) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_r4x', '2027-02-01', '2027-02', 'Boshqa', 25000, 'to''xtatilgan davr', 'cash') returning id) select id from x$q$)
  || ' | ' || (select count(*) from public.payments where id = 'man_r4_0000') || '/' || (select count(*) from public.expenses where id = 'e_r4x'),
  '^ERR 42501 \[kassa:paused_live_day\] To''lov sanasi \(01\.02\.2027\) — kassa kuni edi: to''xtatilgan kassada yozilmaydi.*\(oxirgi kassa kuni 01\.02\.2027 .*ertasi kuni.* \| ERR 42501 \[kassa:paused_live_day\] 01\.02\.2027 — kassa kuni edi.* \| 0/0$');
select zz.chk('R4b kassa hujjati yozilmaydi (kassa:paused)',
  zz.as('U_KAS', $q$select public.kassa_receipt('{"op":"in_other","amount":1000,"partyType":"other","partyName":"Sinov Shaxs","articleId":"IN-06","basis":"Tilxat","note":"Kitob uchun","fiscalNo":"F-R4B","clientRef":"r4-rcp-00001"}')::text$q$),
  '^ERR P0001 \[kassa:paused\]');
select zz.chk('R4c «Kassa» holati: to''xtatilgan (01.02 dan), qoldiq — oxirgi kun oxiri; sanani to''g''ridan-to''g''ri qo''yib bo''lmaydi (avval komissiya sanashi)',
  (select (s ->> 'blockReason') || ':' || (s -> 'desk' ->> 'pausedDay') || ':' || (s ->> 'balance') from (select zz.js(zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)) as s) q)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-02"}')::text$q$),
  '^paused:2027-02-01:4725000 \| ERR P0001 \[kassa:restart_needed\]');
select zz.clock('2027-02-02 08:00+05');
select zz.put('R4', zz.pay('U_KAS', 'man_r4_0001', 'T-5', 60000, 'cash', '', null, null));
select zz.chk('R4a to''xtatilgan davr sanasi (02.02): naqd o''quv to''lovi KO-1 siz va fiskal cheksiz, naqd xarajat — «Buxgalteriya»dan (avvalgi tartib)',
  (zz.js(zz.get('R4')) ->> 'ok') || ':' || zz.jd(zz.get('R4'), 'kassa', 'null') || ':' || (zz.js(zz.get('R4')) ->> 'day') || ':' || (select coalesce("cashDocId", '-') from public.payments where id = 'man_r4_0001')
  || ' | ' || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_r4', '2027-02-02', '2027-02', 'Boshqa', 25000, 'to''xtatilgan davr', 'cash') returning id) select id from x$q$),
  '^true:null:2027-02-02:- \| e_r4$');
-- state-4 (ushlangan kassa; kassa_tuition_before / kassa_cash_guard qoidasi): to'g'ridan-to'g'ri naqd to'lov qatori — oxirgi kassa kuni (01.02)
--   va undan oldingi sana bilan hech kimga (Direktorga ham) yo'q; to'xtatilgan davr sanasi (02.02) — avvalgi tartibda. g8 (g4b qoldig'i):
--   sanasiz naqd (yoki usulsiz) yozuv — kiritilmaydi, mavjud yozuvning sanasi bo'shatilmaydi (avval kunga oid qoidalar uni o'tkazardi)
savepoint n5;
select zz.as('U_DIR', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n5_0001', 'T-5', 'cash', 1000, 'pending', true, '{"manual":true,"date":"2027-02-01"}') returning id) select id from x$q$) || ' | '
  || zz.as('U_KAS', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw) values ('man_n5_0002', 'T-5', 'cash', 1000, 'pending', true, '{"manual":true}') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_n5a', null, '2027-02', 'Boshqa', 1000, 'sanasiz', 'cash') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note) values ('e_n5b', null, '2027-02', 'Boshqa', 1000, 'sanasiz, usulsiz') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date, method) values ('adv_n5', 'IQX-T1', 'staff:st1', 'Sinov', 1000, '2027-02', null, 'cash') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (update public.expenses set date = null where id = 'e_r4' returning id) select id from x$q$) as n5 \gset
rollback to savepoint n5;
select zz.chk('N5 ushlangan kassa: oxirgi kassa kuni sanali naqd qator — Direktorga ham rad; to''xtatilgan davr sanasi — avvalgidek; sanasiz naqd / usulsiz yozuv va sanani bo''shatish — rad (kassa:cash_date)',
  :'n5', '^ERR 42501 \[kassa:paused_live_day\] To''lov kuni \(01\.02\.2027\) — oxirgi kassa kuni.* \| man_n5_0002 \| ERR 42501 \[kassa:cash_date\] Kassa to''xtatilgan: naqd.* \| ERR 42501 \[kassa:cash_date\].* \| ERR 42501 \[kassa:cash_date\].* \| ERR 42501 \[kassa:cash_date\].*$');
select zz.clock('2027-02-02 09:00+05');
-- Komissiya sanadi: 4 725 000 + 60 000 (o'quv to'lovi) − 25 000 (xarajat) = 4 760 000. Avval xato (4 750 000), keyin qayta sanaldi.
select zz.chk('R5 qayta ishga tushirish qoldig''ini faqat Direktor kiritadi; kun oxirgi kassa kunidan keyin va bugundan oldin emas',
  zz.as('U_KAS', $q$select public.kassa_opening_set('{"amount":4750000,"startDay":"2027-02-03"}')::text$q$) || ' | '
  || zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4750000,"startDay":"2027-02-01"}')::text$q$),
  '^ERR 42501.* \| ERR 22023 \[kassa:bad_input\]');
select zz.put('R5a', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4750000,"startDay":"2027-02-03","note":"Sanash dalolatnomasi 2","commission":[{"title":"Direktor","name":"Sinov D"},{"title":"Kassir","name":"Sinov K"}]}')::text$q$));
select zz.put('R5b', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4760000,"startDay":"2027-02-03","note":"Qayta sanaldi"}')::text$q$));
select zz.chk('R5 farq dalolatnomasi: «Д-» (OP-23) Dt 5010 Kt 0000 (boshlang''ich qoldiq 0 edi — dalolatnomasi yo''q edi); qayta sanalganda avvalgisi bekor (raqami saqlanadi), yangisi 35 000; asos — qayta ishga tushirish',
  (zz.js(zz.get('R5a')) ->> 'delta') || ' / ' || (zz.js(zz.get('R5b')) ->> 'delta') || ' / '
  || (select string_agg(c.form || ':' || c.status || ':' || trim_scale(c.amount) || ':' || l.debit || '>' || l.credit || '@' || l."articleId", ', ' order by c.no)
        from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.op = 'nc_opening' and c."sourceSnapshot" ->> 'kind' = 'restart')
  || ' / ' || (zz.js(zz.get('R5b')) #>> '{doc,basis}'),
  '^25000 / 35000 / ACT:void:25000:5010>0000@OP-23, ACT:posted:35000:5010>0000@OP-23 / Qayta ishga tushirish: sanash dalolatnomasi$');
select zz.chk('R5c sanash dalolatnomasi (kutilgan — oxirgi kun oxiri, sanalgan, farq) va kassa hali to''xtatilgan; qoldiq — sanalgan summa',
  (select trim_scale(expected) || ':' || trim_scale(counted) || ':' || trim_scale(diff) from public.cash_counts where kind = 'opening' and day = '2027-02-03' order by at desc limit 1)
  || ' | ' || (select (s ->> 'blockReason') || ':' || (s ->> 'balance') || ':' || (s -> 'desk' -> 'restart' ->> 'day') from (select zz.js(zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)) as s) q),
  '^4725000:4760000:35000 \| paused:4760000:2027-02-03$');
select zz.put('R6x', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-04"}')::text$q$));
select zz.put('R6', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-03"}')::text$q$));
select zz.chk('R6 ishga tushadigan kun boshqa sana — rad; qayta ishga tushirish kuni (03.02) — kassa yana ishlaydi (hodisa: resume)',
  zz.get('R6x') || ' | ' || (zz.js(zz.get('R6')) ->> 'kassaGoLive')
  || ' | ' || coalesce((select "pausedAt"::text from public.cash_desks where id = 'main'), 'ishlaydi')
  || ' | ' || (select (data ->> 'resume') from public.cash_day_events where kind = 'golive' order by at desc, id desc limit 1),
  '^ERR 22023 \[kassa:restart_day\].* \| 2027-02-03 \| ishlaydi \| true$');
-- (g4-v1: boshqa kun bilan qayta sanash avval «Kassa ishga tushgan — boshlang'ich qoldiq o'zgarmaydi» deb rad etilardi — endi
--   alohida xabar: avval ishga tushadigan kunni bo'shatish kerak)
select zz.chk('R6b 03.02 gacha kassa hujjati yozilmaydi (kassa:not_started); boshqa kun bilan qayta sanash — rad, avval sanani bo''shatish kerak (kassa:restart_pending)',
  zz.as('U_KAS', $q$select public.kassa_receipt('{"op":"in_other","amount":1000,"partyType":"other","partyName":"Sinov Shaxs","articleId":"IN-06","basis":"Tilxat","note":"Kitob uchun","fiscalNo":"F-R6B","clientRef":"r6-rcp-00001"}')::text$q$)
  || ' | ' || zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4760000,"startDay":"2027-02-04"}')::text$q$)
  || ' | ' || (select (s ->> 'blockReason') from (select zz.js(zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)) as s) q),
  '^ERR P0001 \[kassa:not_started\].*03\.02\.2027.* \| ERR P0001 \[kassa:restart_pending\] Qayta ishga tushirish 03\.02\.2027 ga tayyorlangan.*avval «⚙ Sozlamalar»da ishga tushadigan kunni bo''shating.* \| restart$');
select zz.clock('2027-02-03 09:00+05');
select zz.put('R7', zz.pay('U_KAS', 'man_r7_0001', 'T-5', 100000, 'cash', '', null, '{"fiscalNo":"F-R7"}'));
select zz.chk('R7 qayta ishga tushgan kun: naqd o''quv to''lovi KO-1 bilan; kun boshi = komissiya sanagan 4 760 000 (oldingi kun oxiri 4 725 000 emas)',
  (zz.js(zz.get('R7')) #>> '{kassa,day}') || ':' || (select trim_scale(opening)::text from public.cash_days where day = '2027-02-03'), '^2027-02-03:4760000$');
select zz.chk('R8 kun yopildi: farq 0 — to''xtatilgan davr puli kassirga kamomad / ortiqcha bo''lmadi',
  zz.js(zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-03","counted":4860000}')::text$q$)) ->> 'diff', '^0$');
select zz.chk('R9 nazorat ro''yxati: qayta ishga tushirish — oxirgi kun oxiri, sanalgan, farq, dalolatnoma; to''xtatilgan davrdagi kassa hujjatisiz naqd: kirim 60 000, chiqim 25 000; orqa sanali yo''q; izohlanmagan farq 0',
  (select (r ->> 'startDay') || ':' || (r ->> 'prevClosing') || ':' || (r ->> 'counted') || ':' || (r ->> 'delta') || ':D-' || (r ->> 'docNo') || ':' || (r #>> '{rows,in}') || ':' || (r #>> '{rows,out}')
          || ':' || (r #>> '{backdated,n}') || ':' || (r ->> 'unexplained') || ':' || coalesce(c ->> 'paused', 'ishlaydi')
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q, jsonb_array_elements(c -> 'restarts') r limit 1),
  '^2027-02-03:4725000:4760000:35000:D-2:60000:25000:0:0:ishlaydi$');
select zz.chk('R10 KO-3 va statiya matritsasi (fevral): boshi + kirim − chiqim + qayta ishga tushirish farqi = oxiri — qoldiqlar mos',
  (select (j ->> 'opening') || '+' || (j #>> '{totals,in}') || '+' || (j ->> 'restartAdj') || '=' || (j ->> 'closing') || ':' || (j ->> 'balanced')
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_journal('main', '2027-02-01', '2027-02-28')::text$q$)) as j) q)
  || ' | ' || (select (m ->> 'balanced') || ':' || (m -> 'dayBal' ->> 0) || ',' || (m -> 'dayBal' ->> 1) || ',' || (m -> 'dayBal' ->> 2)
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_matrix('main', '2027-02')::text$q$)) as m) q),
  '^3925000\+900000\+35000=4860000:true \| true:4725000,4725000,4860000$');
select zz.chk('R11 qayta ochilgan kundan keyin qoldiqni o''zgartirib bo''lmaydi; moslik (03.02 dan) toza',
  zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":1,"startDay":"2027-02-04"}')::text$q$) || ' | ' || (app.kassa_reconcile(null, null) ->> 'total'),
  '^ERR 42501 \[kassa:started\].* \| 0$');

-- ---------- §9: IKKINCHI to'xtatish va qayta ishga tushirish (g4-v1: avval ikkinchi qayta ishga tushirish qoldig'i doim rad etilardi —
--   kassa:started — va kassa to'xtatilgan holatda qolib ketardi) ----------
--   03.02 yopilgan (4 860 000). Kassa yana to'xtatiladi; to'xtatilgan davrda: 03.02 (oxirgi kassa kuni) sanali naqd o'quv to'lovi va
--   01.02 sanali (orqa sana — yopilgan kassa kuni) naqd xarajat — rad (g4r-2); 04.02 — naqd o'quv to'lovi 5 000. Komissiya 05.02 uchun
--   sanaydi: 4 860 000 + 5 000 = 4 865 000.
create or replace function zz.su(p_q text) returns text language plpgsql as $$   -- joriy (superfoydalanuvchi) rolda, xato matni bilan
declare r text; v_hint text;
begin
  begin execute p_q into r;
  exception when others then get stacked diagnostics v_hint = pg_exception_hint; r := 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm; end;
  return coalesce(r, '<null>');
end $$;
select zz.put('R12', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$));
select zz.chk('R12 ikkinchi marta to''xtatildi: sana bo''sh, kassa to''xtatilgan, oxirgi qayta ishga tushirish (03.02) joyida; to''xtatilgan kassada oxirgi kun qayta ochilmaydi',
  zz.jd(zz.get('R12'), 'kassaGoLive', 'bo''sh') || ' | ' || (select ("pausedAt" is not null) || ':' || "restartDay" from public.cash_desks where id = 'main')
  || ' | ' || zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-02-03', 'Sinov: qayta ochish')::text$q$)
  || ' | ' || (select status from public.cash_days where day = '2027-02-03'),
  '^bo''sh \| true:2027-02-03 \| ERR P0001 \[kassa:reopen_paused\].*03\.02\.2027.* \| closed$');
-- g4r-2 (g4-v1 s5b_backdate): avval to'xtatilgan kassada moliya menejeri yopilgan kassa kunini (01.02) orqa sana bilan «ochib», unga naqd
--   xarajat yozardi — u faqat «backdated» ro'yxatida ko'rinardi. Endi oxirgi kassa kuni va undan oldingi sana bilan hech kimga yo'q.
select zz.chk('R13 to''xtatilgan davr: oxirgi kassa kuni (03.02) sanali naqd o''quv to''lovi va 01.02 sanali (orqa sana) naqd xarajat — rad (kassa:paused_live_day), iz yo''q',
  zz.pay('U_KAS', 'man_r13_0001', 'T-5', 30000, 'cash', '', null, null) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_r13', '2027-02-01', '2027-02', 'Boshqa', 7000, 'to''xtatilgan davr, orqa sana', 'cash') returning id) select id from x$q$)
  || ' | ' || (select count(*) from public.payments where id = 'man_r13_0001') || '/' || (select count(*) from public.expenses where id = 'e_r13'),
  '^ERR 42501 \[kassa:paused_live_day\] To''lov sanasi \(03\.02\.2027\) — kassa kuni edi.* \| ERR 42501 \[kassa:paused_live_day\] 01\.02\.2027 — kassa kuni edi \(oxirgi kassa kuni 03\.02\.2027\).* \| 0/0$');
select zz.clock('2027-02-04 09:00+05');
select zz.put('R13c', zz.pay('U_KAS', 'man_r13_0002', 'T-5', 5000, 'cash', '', null, null));
select zz.chk('R13c to''xtatilgan davr sanasi (04.02): naqd o''quv to''lovi KO-1 siz',
  zz.jd(zz.get('R13c'), 'kassa', 'null') || ':' || (zz.js(zz.get('R13c')) ->> 'day'), '^null:2027-02-04$');
select zz.chk('R14 qayta ishga tushirish kuni bugun (04.02), lekin bugun kassa hujjatisiz naqd yozuv bor — rad (kassa:restart_gap), dalolatnoma yozilmadi',
  zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4865000,"startDay":"2027-02-04"}')::text$q$)
  || ' | ' || (select count(*) from public.cash_docs where op = 'nc_opening' and "sourceSnapshot" ->> 'kind' = 'restart'),
  '^ERR P0001 \[kassa:restart_gap\] Qayta ishga tushirish kuni \(04\.02\.2027\).*\(1 ta\).* \| 2$');
select zz.put('R14a', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4865000,"startDay":"2027-02-05","note":"Sanash dalolatnomasi 3"}')::text$q$));
select zz.chk('R14a ikkinchi qayta ishga tushirish qoldig''i 05.02 uchun qabul qilindi: farq 5 000 — yangi «Д-3» (Dt 5010 Kt 0000); birinchisi («Д-2», 35 000) joyida',
  (zz.js(zz.get('R14a')) ->> 'delta') || ':' || (zz.js(zz.get('R14a')) #>> '{doc,lines,0,debit}') || '>' || (zz.js(zz.get('R14a')) #>> '{doc,lines,0,credit}') || ' | '
  || (select string_agg('D-' || c.no || ':' || c.status || ':' || trim_scale(c.amount) || ':' || c."businessDay", ', ' order by c.no)
        from public.cash_docs c where c.op = 'nc_opening' and c."sourceSnapshot" ->> 'kind' = 'restart' and c.status = 'posted'),
  '^5000:5010>0000 \| D-2:posted:35000:2027-02-03, D-3:posted:5000:2027-02-05$');
select zz.chk('R14b tayyorlangan qayta ishga tushirishda ham oxirgi kun qayta ochilmaydi (qayta yopilsa farq dalolatnomasi eskirardi)',
  zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-02-03', 'Sinov: qayta ochish')::text$q$), '^ERR P0001 \[kassa:reopen_paused\]');
select zz.put('R15', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-05"}')::text$q$));
select zz.clock('2027-02-05 09:00+05');
select zz.put('R16', zz.pay('U_KAS', 'man_r16_0001', 'T-5', 50000, 'cash', '', null, '{"fiscalNo":"F-R16"}'));
select zz.chk('R15 ishga tushadigan kun 05.02 — kassa yana ishlaydi; R16 05.02 naqd to''lov KO-1 bilan, kun boshi = ikkinchi komissiya sanagan 4 865 000; kun farqsiz yopildi',
  (zz.js(zz.get('R15')) ->> 'kassaGoLive') || ':' || coalesce((select "pausedAt"::text from public.cash_desks where id = 'main'), 'ishlaydi')
  || ' | ' || (zz.js(zz.get('R16')) #>> '{kassa,day}') || ':' || (select trim_scale(opening)::text from public.cash_days where day = '2027-02-05')
  || ' | ' || (zz.js(zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-05","counted":4915000}')::text$q$)) ->> 'diff'),
  '^2027-02-05:ishlaydi \| 2027-02-05:4865000 \| 0$');
select zz.chk('R17 nazorat ro''yxati: ikkita qayta ishga tushirish — har birining farqi va to''xtatilgan davr naqd harakati (yangi yozuvlarda orqa sanalisi yo''q — g4r-2), izohlanmagan farq 0',
  (select string_agg((r ->> 'startDay') || ':' || (r ->> 'prevDay') || ':' || (r ->> 'delta') || ':D-' || (r ->> 'docNo') || ':' || (r #>> '{rows,in}') || '-' || (r #>> '{rows,out}')
                     || ':' || (r #>> '{backdated,n}') || ':' || (r ->> 'unexplained'), ' | ' order by r ->> 'startDay' desc)
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q, jsonb_array_elements(c -> 'restarts') r),
  '^2027-02-05:2027-02-03:5000:D-3:5000-0:0:0 \| 2027-02-03:2027-02-01:35000:D-2:60000-25000:0:0$');
select zz.chk('R18 KO-3 va statiyalar (fevral): ikkala farq bilan qoldiqlar mos (boshi + kirim − chiqim + 40 000 = oxiri); kun oxirlari — farq o''z kunidan',
  (select (j ->> 'opening') || '+' || (j #>> '{totals,in}') || '-' || (j #>> '{totals,out}') || '+' || (j ->> 'restartAdj') || '=' || (j ->> 'closing') || ':' || (j ->> 'balanced')
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_journal('main', '2027-02-01', '2027-02-28')::text$q$)) as j) q)
  || ' | ' || (select (m ->> 'balanced') || ':' || (m ->> 'restartAdj') || ':' || (m -> 'dayBal' ->> 3) || ',' || (m -> 'dayBal' ->> 4)
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_matrix('main', '2027-02')::text$q$)) as m) q),
  '^3925000\+950000-0\+40000=4915000:true \| true:40000:4860000,4915000$');
do $$ begin perform set_config('iqror.kassa_rpc', '1', true); end $$;
select zz.put('R19', zz.su($q$with x as (update public.cash_desks set "restartAmount" = 1 where id = 'main' returning id) select id from x$q$));
do $$ begin perform set_config('iqror.kassa_rpc', '', true); end $$;
select zz.chk('R19 kassa ishlab turganda (qayta ishga tushirish boshlangan) qayta ishga tushirish qoldig''i kassa funksiyasi bayrog''i bilan ham o''zgarmaydi; moslik toza',
  zz.get('R19') || ' | ' || (app.kassa_reconcile(null, null) ->> 'total'), '^ERR 42501 \[kassa:started\].* \| 0$');

-- ---------- g4b: UCHINCHI to'xtatish va qayta ishga tushirish — kassa ishlamagan kunlar chegarasi (g4v-1), to'xtatilgan kassada yopilgan
--   kunlar (g4r-2), eskirgan qayta ishga tushirish sanashi (g4v-2), «ishga tushishdan oldingi» ro'yxat oynasi (g4v-3), moslik — kassa
--   ishlagan barcha davrlar (g4v-4) ----------
--   Kassa ishlagan davrlar: 04.01–01.02, 03.02, 05.02–08.02, 11.02 dan; to'xtatilgan davrlar (kassa ishlamagan kunlar): 02.02, 04.02,
--   09.02–10.02; birinchi ishga tushgan kundan (04.01) oldingi kunlar ham. 08.02: kassa orqali xarajat (KO-2 — «Buxgalteriya»ga bog'langan
--   qator) va eski yo'l bilan (himoyani chetlab) kiritilgan kassa hujjatisiz naqd xarajat — kassa ishlagan davr «yetimi» (P4).
select zz.clock('2027-02-08 09:00+05');
select zz.put('G1', zz.pay('U_KAS', 'man_g1_0001', 'T-5', 10000, 'cash', '', null, '{"fiscalNo":"F-G1"}'));
select zz.put('G1r', zz.as('U_KAS', $q$select public.kassa_payout_request('{"op":"out_expense","amount":15000,"partyType":"counterparty","partyId":"cp_sup","articleId":"EX-16","basis":"Hisob-faktura 8","clientRef":"g1-req-00001"}')::text$q$));
select zz.put('G1a', zz.as('U_FM', format('select public.kassa_doc_approve(%L)::text', zz.js(zz.get('G1r')) ->> 'id')));
select zz.put('G1b', zz.as('U_DIR', format('select public.kassa_doc_approve(%L)::text', zz.js(zz.get('G1r')) ->> 'id')));
select zz.put('G1c', zz.as('U_KAS', format('select public.kassa_doc_pay(%L)::text', zz.js(zz.get('G1r')) ->> 'id')));
set local session_replication_role = replica;
insert into public.expenses (id, date, month, category, amount, note, method, "createdAt") values ('e_g4b_orphan', '2027-02-08', '2027-02', 'Boshqa', 1000, 'yetim (sinov)', 'cash', '2027-02-08 10:00+05');
set local session_replication_role = origin;
select zz.chk('G1 08.02: KO-1 (kun ochildi), kassa orqali xarajat (KO-2, bog''langan qator); kassa ishlagan davr yetimi moslikda (P4 = 1); kun farqsiz yopildi',
  (zz.js(zz.get('G1')) #>> '{kassa,day}') || ' | ' || (zz.js(zz.get('G1c')) ->> 'status') || ':' || (select count(*) from public.expenses where "cashDocId" = zz.js(zz.get('G1r')) ->> 'id')
  || ' | ' || (app.kassa_reconcile(null, null) #>> '{p4,row}') || ':' || (app.kassa_reconcile(null, null) ->> 'total')
  || ' | ' || (zz.js(zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-08","counted":4910000}')::text$q$)) ->> 'diff'),
  '^2027-02-08 \| posted:1 \| 1:1 \| 0$');
select zz.clock('2027-02-08 18:00+05');
select zz.put('G2', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$));
select zz.chk('G2 g4v-4: kassa to''xtatildi — moslik baribir tekshiriladi (oxirgi kassa kunigacha): yetim P4 = 1; Telegram bloki (kassa ishlagan, nazorat qatori) va nazorat ro''yxati ham',
  zz.jd(zz.get('G2'), 'kassaGoLive', 'bo''sh')
  || ' | ' || (select (r ->> 'live') || ':' || (r ->> 'from') || ':' || (r ->> 'to') || ':' || (r #>> '{p4,row}') || ':' || (r ->> 'total') from (select app.kassa_reconcile(null, null) as r) x)
  || ' | ' || (select (d ->> 'live') || ':' || (d #>> '{control,reconcile}') from (select app.kassa_daily('2027-02-08') as d) x)
  || ' | ' || (select (c #>> '{reconcile,total}') from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q),
  '^bo''sh \| true:2027-01-04:2027-02-08:1:1 \| true:1 \| 1$');
-- g4r-2: to'xtatilgan kassada oxirgi kassa kuni (08.02) va undan oldingi sana bilan kassa hujjatisiz naqd yozuv hech kimga yo'q
select zz.chk('G3 g4r-2: to''xtatilgan kassada yopilgan kassa kuni (05.02) sanali naqd xarajat — moliya menejeriga ham, Direktorga ham yo''q (kassa:paused_live_day)',
  zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g3a', '2027-02-05', '2027-02', 'Boshqa', 3300, 'orqa sana', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g3b', '2027-02-05', '2027-02', 'Boshqa', 3300, 'orqa sana', 'cash') returning id) select id from x$q$),
  '^ERR 42501 \[kassa:paused_live_day\] 05\.02\.2027 — kassa kuni edi \(oxirgi kassa kuni 08\.02\.2027\).*«Kassa» orqali \| ERR 42501 \[kassa:paused_live_day\] 05\.02\.2027 — kassa kuni edi');
select zz.chk('G3b to''xtatilgan kassada kassa ishlamagan, lekin oxirgi kassa kunidan oldingi kun (03.01 — ishga tushishdan oldin; 02.02 — oldingi to''xtatilgan davr) ham yo''q: qayta ishga tushgach Direktor kiritadi',
  zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g3c', '2027-01-03', '2027-01', 'Boshqa', 1500, 'kech chek', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.payd('U_DIR', 'man_g3_0001', 'T-5', 1500, 'cash', '2027-02-02', null, null),
  '^ERR 42501 \[kassa:paused_live_day\] 03\.01\.2027 — oxirgi kassa kunidan \(08\.02\.2027\) oldingi sana.*Direktor kiritadi \| ERR 42501 \[kassa:paused_live_day\] To''lov sanasi \(02\.02\.2027\) oxirgi kassa kunidan \(08\.02\.2027\) oldin.*Direktor haqiqiy sanasi bilan kiritadi$');
select zz.chk('G3c to''xtatilgan kunning o''zida (08.02 = oxirgi kassa kuni) naqd o''quv to''lovi — rad (ertasi kuni kiritiladi); Direktorning 31.01 sanali naqd to''lovi ham; iz yo''q',
  zz.pay('U_KAS', 'man_g3_0002', 'T-5', 2000, 'cash', '', null, null) || ' | ' || zz.payd('U_DIR', 'man_g3_0003', 'T-5', 2000, 'cash', '2027-01-31', null, null)
  || ' | ' || (select count(*) from public.payments where id in ('man_g3_0001', 'man_g3_0002', 'man_g3_0003')),
  '^ERR 42501 \[kassa:paused_live_day\] To''lov sanasi \(08\.02\.2027\) — kassa kuni edi.*ertasi kuni.* \| ERR 42501 \[kassa:paused_live_day\] To''lov sanasi \(31\.01\.2027\) — kassa kuni edi.* \| 0$');
select zz.put('G3d', zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g3d', '2027-02-05', '2027-02', 'Boshqa', 900, 'bank xizmati', 'bank') returning id) select id from x$q$));
select zz.chk('G3d naqdsiz yozuv yopilgan kun sanasi bilan — avvalgidek; uni naqdga aylantirish — rad; kassa hujjatiga bog''langan xarajat (KO-2) to''xtatilgan kassada ham o''zgarmaydi va o''chirilmaydi',
  zz.get('G3d') || ' | ' || zz.as('U_FM', $q$with x as (update public.expenses set method = 'cash' where id = 'e_g3d' returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', format($q$with x as (update public.expenses set amount = amount + 1 where "cashDocId" = %L returning id) select id from x$q$, zz.js(zz.get('G1r')) ->> 'id'))
  || ' | ' || zz.as('U_DIR', format($q$with x as (delete from public.expenses where "cashDocId" = %L returning id) select id from x$q$, zz.js(zz.get('G1r')) ->> 'id')),
  '^e_g3d \| ERR 42501 \[kassa:paused_live_day\].* \| ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:linked_row\]');
-- to'xtatilgan davr (09.02): avvalgi tartib; himoya chizig'i («backdated») uchun — himoyasiz eski tartibda orqa sana bilan kiritilgan yozuv
--   (endi tizim qabul qilmaydi; u kassadan chiqqan pulni aks ettiradi — sanashga kirgan)
select zz.clock('2027-02-09 09:00+05');
select zz.put('G4', zz.pay('U_KAS', 'man_g4_0001', 'T-5', 20000, 'cash', '', null, null));
select zz.put('G4b', zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g4', '2027-02-09', '2027-02', 'Boshqa', 4000, 'to''xtatilgan davr', 'cash') returning id) select id from x$q$));
set local session_replication_role = replica;
insert into public.expenses (id, date, month, category, amount, note, method, "createdAt") values ('e_g4b_legacy', '2027-02-05', '2027-02', 'Boshqa', 2500, 'orqa sana (eski tartib)', 'cash', '2027-02-09 09:30+05');
set local session_replication_role = origin;
select zz.chk('G4 to''xtatilgan davr sanasi (09.02): naqd o''quv to''lovi KO-1 siz, naqd xarajat — avvalgi tartibda',
  zz.jd(zz.get('G4'), 'kassa', 'null') || ':' || (zz.js(zz.get('G4')) ->> 'day') || ' | ' || zz.get('G4b'), '^null:2027-02-09 \| e_g4$');
-- g4v-2: komissiya 09.02 10:00 da sanadi (11.02 uchun): 4 910 000 + 20 000 − 4 000 − 2 500 = 4 923 500 (kassa hali to'xtatilgan)
select zz.clock('2027-02-09 10:00+05');
select zz.put('G5a', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4923500,"startDay":"2027-02-11","note":"Sanash 4"}')::text$q$));
select zz.chk('G5a qayta ishga tushirish qoldig''i 11.02 uchun; sanashdan keyin yozuv yo''q — «Kassa» holatida eskirgan yozuv 0, sanash payti beriladi',
  (zz.js(zz.get('G5a')) ->> 'delta') || ' | ' || (select (s #>> '{desk,restart,stale,n}') || ':' || ((s #>> '{desk,restart,countedAt}') is not null) from (select zz.js(zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)) as s) q),
  '^13500 \| 0:true$');
select zz.clock('2027-02-09 15:00+05');
select zz.put('G5b', zz.pay('U_KAS', 'man_g5_0001', 'T-5', 7000, 'cash', '', null, null));
select zz.chk('G5b g4v-2: sanashdan keyin (09.02 15:00) naqd o''quv to''lovi qabul qilinadi (to''xtatilgan davr), lekin sanashga kirmagan: eskirgan yozuv 1 ta (kirim 7 000); ishga tushadigan kun qo''yilmaydi (kassa:restart_recount — soni va summasi), kassa to''xtatilgan qoladi',
  zz.jd(zz.get('G5b'), 'kassa', 'null')
  || ' | ' || (select (s #>> '{desk,restart,stale,n}') || ':' || (s #>> '{desk,restart,stale,in}') from (select zz.js(zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)) as s) q)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-11"}')::text$q$)
  || ' | ' || coalesce((select "kassaGoLive"::text from public.fin_org where id = 'main'), 'bo''sh') || ':' || (select ("pausedAt" is not null)::text from public.cash_desks where id = 'main'),
  '^null \| 1:7000 \| ERR P0001 \[kassa:restart_recount\] Qayta ishga tushirish sanashidan \(09\.02\.2027 10:00\) keyin kassa hujjatisiz 1 ta naqd yozuv kiritilgan, sanasi qayta ishga tushirish kunidan \(11\.02\.2027\) oldin: kirim 7000 so''m, chiqim 0 so''m.* \| bo''sh:true$');
select zz.clock('2027-02-09 16:00+05');
select zz.put('G5c', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4930500,"startDay":"2027-02-11","note":"Qayta sanaldi"}')::text$q$));
select zz.put('G5d', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-11"}')::text$q$));
select zz.chk('G5c komissiya qayta sanadi (4 930 500; avvalgi dalolatnoma bekor) — eskirgan yozuv 0, ishga tushadigan kun 11.02 qo''yildi',
  (zz.js(zz.get('G5c')) ->> 'delta') || ' | ' || (select string_agg(c.status || ':' || trim_scale(c.amount), ',' order by c.no) from public.cash_docs c
                                                   where c.op = 'nc_opening' and c."sourceSnapshot" ->> 'kind' = 'restart' and c."businessDay" = '2027-02-11')
  || ' | ' || (select (s #>> '{desk,restart,stale,n}') from (select zz.js(zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)) as s) q)
  || ' | ' || (zz.js(zz.get('G5d')) ->> 'kassaGoLive') || ':' || coalesce((select "pausedAt"::text from public.cash_desks where id = 'main'), 'ishlaydi'),
  '^20500 \| void:13500,posted:20500 \| 0 \| 2027-02-11:ishlaydi$');
select zz.clock('2027-02-10 09:00+05');
select zz.put('G6a', zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g6', '2027-02-10', '2027-02', 'Boshqa', 3000, 'sanashdan keyin', 'cash') returning id) select id from x$q$));
select zz.chk('G6a qayta ishga tushish kunini kutayotgan kassa ham ushlangan: yopilgan kassa kuni (08.02) sanali naqd xarajat — rad; to''xtatilgan davr sanasi (10.02) — qabul qilinadi, lekin sanashdan keyin: eskirgan (chiqim 3 000)',
  zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g6x', '2027-02-08', '2027-02', 'Boshqa', 3000, 'orqa sana', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.get('G6a') || ' | ' || (select (s #>> '{desk,restart,stale,n}') || ':' || (s #>> '{desk,restart,stale,out}') from (select zz.js(zz.as('U_FM', $q$select public.kassa_state('main')::text$q$)) as s) q),
  '^ERR 42501 \[kassa:paused_live_day\] 08\.02\.2027 — kassa kuni edi.* \| e_g6 \| 1:3000$');
-- g4b-v1 (eslatma 1): kutilayotgan qayta ishga tushirish kuni va keyingi sana bilan kassa hujjatisiz naqd yozuv — yangi kassa davri yetimi bo'lardi
savepoint g6a2;   -- (natija psql o'zgaruvchisida — savepoint ortga qaytarilgach tekshiriladi)
select coalesce(zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g6y', '2027-02-11', '2027-02', 'Boshqa', 3000, 'oldindan', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.as('U_DIR', $q$with x as (update public.expenses set date = '2027-02-12' where id = 'e_g6' returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g6z', '2027-02-11', '2027-02', 'Boshqa', 3000, 'bank orqali', 'bank') returning id) select id from x$q$)
  || ' | ' || (select date from public.expenses where id = 'e_g6'), '<null>') as g6a2 \gset
rollback to savepoint g6a2;
select zz.chk('G6a2 qayta ishga tushish kunini kutayotgan kassada qayta ishga tushirish kuni (11.02) va keyingi sana bilan kassa hujjatisiz naqd xarajat — rad (kassa:restart_gap), sanani shunga ko''chirish ham; naqdsiz xarajat — avvalgidek', :'g6a2',
  '^ERR 42501 \[kassa:restart_gap\] 11\.02\.2027 — qayta ishga tushirish kuni \(11\.02\.2027\) yoki undan keyingi sana: kassa shu kundan qayta ishlaydi.*«Kassa» orqali\) \| ERR 42501 \[kassa:restart_gap\] 12\.02\.2027 — .* \| e_g6z \| 2027-02-10$');
select zz.clock('2027-02-11 09:00+05');
savepoint g6p;   -- (qayta ishga tushirish kuni o'tib ketgan holat — xabar avval sanani bo'shatishni aytadi; keyin ortga qaytariladi)
select zz.clock('2027-02-12 09:00+05');
select zz.pay('U_KAS', 'man_g6_0009', 'T-5', 1000, 'cash', '', null, '{"fiscalNo":"F-G6P"}') as g6p \gset
rollback to savepoint g6p;
select zz.chk('G6b g4v-2: qayta ishga tushirish kuni (11.02) — birinchi kassa kuni sanashdan keyingi yozuv bilan ochilmaydi (kassa:restart_recount; soni va summasi); to''lov ham yozilmadi, kun ochilmadi; «Kassa» holati — hujjat qabul qilinmaydi',
  zz.pay('U_KAS', 'man_g6_0001', 'T-5', 1000, 'cash', '', null, '{"fiscalNo":"F-G6"}')
  || ' | ' || (select count(*) from public.payments where id = 'man_g6_0001') || '/' || (select count(*) from public.cash_days where day = '2027-02-11')
  || ' | ' || (select (s ->> 'canPost') || ':' || (s ->> 'blockReason') from (select zz.js(zz.as('U_KAS', $q$select public.kassa_state('main')::text$q$)) as s) q),
  '^ERR P0001 \[kassa:restart_recount\] Qayta ishga tushirish sanashidan \(09\.02\.2027 16:00\) keyin kassa hujjatisiz 1 ta naqd yozuv kiritilgan.*kirim 0 so''m, chiqim 3000 so''m.*\(shu kun bilan; avvalgi dalolatnoma bekor bo''ladi\) \| 0/0 \| false:restart_recount$');
select zz.chk('G6p qayta ishga tushirish kuni o''tib ketgan bo''lsa — xabar avval ishga tushadigan kunni bo''shatishni aytadi', :'g6p',
  '^ERR P0001 \[kassa:restart_recount\].*\(qayta ishga tushirish kuni o''tgan: avval «⚙ Sozlamalar»da ishga tushadigan kunni bo''shating, keyin qoldiqni yangi kun bilan kiriting\)$');
-- komissiya 11.02 ertalab qayta sanadi: 4 930 500 − 3 000 (10.02 xarajat) − 2 000 (10.02 da berilgan, cheki keyin keladi) + 6 000 (10.02 da
--   olingan, qurilma navbatida turgan to'lov) = 4 931 500
select zz.clock('2027-02-11 09:10+05');
select zz.put('G6c', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4931500,"startDay":"2027-02-11","note":"Qayta sanaldi (2)"}')::text$q$));
-- g4b-v1: qayta sanashdan keyin birinchi hujjat — Direktorning oxirgi kassa kuni (08.02) sanali naqd to'lovi (yopilgan kassa kuni —
--   KO-1 bilan bugungi kunga). Avval to'lov qatori shu tranzaksiyada hali hujjatsiz turib, o'zini «sanashdan keyingi yozuv» deb sanardi:
--   birinchi kun kassa:restart_recount bilan ochilmasdi, qayta sanash ham yordam bermasdi (har urinishda qator yangi sanashdan keyin).
savepoint g6v;   -- (natija psql o'zgaruvchisida — savepoint ortga qaytarilgach tekshiriladi)
select zz.clock('2027-02-11 09:15+05');   -- (sanashdan keyin: to'lov qatori «sanashdan keyin kiritilgan» bo'lsin)
select zz.put('G6v0', (select (s ->> 'canPost') || ':' || coalesce(s ->> 'blockReason', '-') || ':' || (s #>> '{desk,restart,stale,n}')
                         from (select zz.js(zz.as('U_KAS', $q$select public.kassa_state('main')::text$q$)) as s) q));
select zz.put('G6v', zz.payd('U_DIR', 'man_g6_0008', 'T-5', 3000, 'cash', '2027-02-08', null, '{"fiscalNo":"F-G6V"}'));
select coalesce(zz.get('G6v0') || ' | ' || coalesce((zz.js(zz.get('G6v')) #>> '{kassa,day}') || ':' || (select trim_scale(opening)::text || ':' || status from public.cash_days where day = '2027-02-11'), zz.get('G6v'))
  || ' | ' || coalesce(app.kassa_restart_stale('main') ->> 'n', 'yo''q'), '<null>') as g6v \gset
rollback to savepoint g6v;
select zz.chk('G6v g4b-v1: birinchi qayta ochilgan kunning birinchi hujjati — Direktorning oxirgi kassa kuni (08.02) sanali naqd to''lovi: KO-1 bilan bugungi kunga, kun ochildi (kun boshi — sanalgan summa); eskirgan yozuv 0', :'g6v',
  '^true:-:0 \| 2027-02-11:4931500:open \| yo''q$');
select zz.clock('2027-02-11 09:20+05');
select zz.put('G6d', zz.pay('U_KAS', 'man_g6_0002', 'T-5', 1000, 'cash', '', null, '{"fiscalNo":"F-G6"}'));
select zz.put('G6e', zz.pay('U_KAS', 'man_g6_0003', 'T-5', 6000, 'cash', '', '2027-02-10 12:00+05', null));
select zz.chk('G6c qayta sanaldi (shu kun bilan) — birinchi kassa kuni ochildi (kun boshi = 4 931 500); qurilma navbatidan kelgan, to''xtatilgan davrda (10.02) olingan to''lov — KO-1 siz (kassa ishlamagan kun, 48 soatdan eski emas)',
  (zz.js(zz.get('G6c')) ->> 'delta') || ' | ' || (zz.js(zz.get('G6d')) #>> '{kassa,day}') || ':' || (select trim_scale(opening)::text from public.cash_days where day = '2027-02-11')
  || ' | ' || zz.jd(zz.get('G6e'), 'kassa', 'null') || ':' || (zz.js(zz.get('G6e')) ->> 'day'),
  '^21500 \| 2027-02-11:4931500 \| null:2027-02-10$');
-- g4v-1: «kassa ishlamagan kun» — birinchi ishga tushgan kundan oldin yoki to'xtatilgan davr ichida; yopilgan kassa davri kuni — yo'q
select zz.put('G7a', zz.payd('U_DIR', 'man_g7_0001', 'T-5', 33000, 'cash', '2027-01-31', null, '{"fiscalNo":"F-G7"}'));
select zz.chk('G7a g4v-1: qayta ishga tushgandan keyin Direktor birinchi davrning yopilgan kassa kuni (31.01) sanasi bilan naqd to''lov — kassa ishlamagan kun emas: KO-1 bilan, bugungi kassa kuniga (11.02)',
  (zz.js(zz.get('G7a')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('G7a')) ->> 'day') || ':' || (select (raw ->> 'date') || ':' || ("cashDocId" is not null) from public.payments where id = 'man_g7_0001'),
  '^2027-02-11:2027-02-11:2027-02-11:true$');
select zz.chk('G7b g4v-1: kassa ishlagan (yopilgan) kun sanasi (31.01 — birinchi davr, 08.02 — oxirgi davr) bilan kassa hujjatisiz naqd xarajat — Direktorga ham yo''q (kassa:live_day); moliya menejeriga ham',
  zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g7a', '2027-01-31', '2027-01', 'Boshqa', 22000, 'yopilgan kun', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g7b', '2027-02-08', '2027-02', 'Boshqa', 22000, 'yopilgan kun', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g7c', '2027-01-31', '2027-01', 'Boshqa', 22000, 'yopilgan kun', 'cash') returning id) select id from x$q$),
  '^ERR 42501 \[kassa:live_day\] 31\.01\.2027 — kassa kuni edi \(kassa ishlagan davr\).*«Kassa» orqali.* \| ERR 42501 \[kassa:live_day\] 08\.02\.2027.* \| ERR 42501 \[kassa:live_day\] 31\.01\.2027');
select zz.put('G7c', zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g7d', '2027-01-03', '2027-01', 'Boshqa', 1500, 'kech chek (ishga tushishdan oldin)', 'cash') returning id) select id from x$q$));
select zz.put('G7d', zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g7e', '2027-02-10', '2027-02', 'Boshqa', 2000, 'kech chek (to''xtatilgan davr)', 'cash') returning id) select id from x$q$));
select zz.chk('G7c kassa ishlamagan kun: birinchi ishga tushishdan oldin (03.01) va to''xtatilgan davr (10.02) — Direktor kassa hujjatisiz kiritadi; boshqalarga — rad (kassa:pre_live, alohida xabar)',
  zz.get('G7c') || ' | ' || zz.get('G7d')
  || ' | ' || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g7f', '2027-02-10', '2027-02', 'Boshqa', 2000, 'x', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_g7g', '2027-01-03', '2027-01', 'Boshqa', 2000, 'x', 'cash') returning id) select id from x$q$),
  '^e_g7d \| e_g7e \| ERR 42501 \[kassa:pre_live\] 10\.02\.2027 — kassa to''xtatilgan davr sanasi.* \| ERR 42501 \[kassa:pre_live\] 03\.01\.2027 — kassa ishga tushishidan \(04\.01\.2027\) oldingi sana');
select zz.chk('G7e kassa hujjatisiz naqd yozuvning sanasini kassa ishlagan kunga ko''chirib bo''lmaydi: yopilgan davr kuni — kassa:live_day, joriy kun — kassa:cash_only_kassa',
  zz.as('U_FM', $q$with x as (update public.expenses set date = '2027-02-08' where id = 'e_g4' returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (update public.expenses set date = '2027-02-11' where id = 'e_g4' returning id) select id from x$q$)
  || ' | ' || (select date from public.expenses where id = 'e_g4'),
  '^ERR 42501 \[kassa:live_day\] 08\.02\.2027 — kassa kuni edi.* \| ERR 42501 \[kassa:cash_only_kassa\].* \| 2027-02-09$');
select zz.chk('G8 11.02 yopildi — farq 0: sanashdan keyingi yozuvlar qayta sanashga kirdi, kassirga kamomad / ortiqcha tushmadi',
  zz.js(zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-11","counted":4965500}')::text$q$)) ->> 'diff', '^0$');
select zz.chk('G9 g4v-3: «ishga tushishdan oldingi» ro''yxat chegarasi — birinchi ishga tushgan kun (04.01): birinchi davrda kiritilgan to''lovlar (2 ta, 500 000) uch marta qayta ishga tushirilgandan keyin ham ko''rinadi; Direktorning 03.01 cheki ham',
  (select (c #>> '{preLive,goLive}') || ':' || (c #>> '{preLive,to}') || ' | ' || (select string_agg((i ->> 'kind') || ':' || (i ->> 'n') || ':' || (i ->> 'sum'), ',' order by i ->> 'kind') from jsonb_array_elements(c #> '{preLive,items}') i)
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q),
  '^2027-01-04:2027-01-03 \| expense:1:1500,tuition:2:500000$');
select zz.chk('G10 g4v-4: moslik kassa ishlagan barcha davrlar bo''yicha (birinchi ishga tushgan kundan, to''xtatilgan davrlarsiz): yetimlar (08.02 va to''xtatilgan davrda orqa sana bilan kiritilgan 05.02) qayta ishga tushirilgandan keyin ham ko''rinadi; to''xtatilgan davr yozuvlari (09.02–10.02) yetim emas; Telegram bloki',
  (select (r ->> 'from') || ':' || (r ->> 'to') || ':' || (r #>> '{p4,row}') || ':' || (r ->> 'total') from (select app.kassa_reconcile(null, null) as r) x)
  || ' | ' || (app.kassa_reconcile('2027-02-08', '2027-02-08') #>> '{p4,row}') || ':' || (app.kassa_reconcile('2027-02-09', '2027-02-10') ->> 'total')
  || ':' || (app.kassa_reconcile('2027-01-04', '2027-02-11') #>> '{p4,row}')
  || ' | ' || (select (d ->> 'live') || ':' || (d #>> '{control,reconcile}') from (select app.kassa_daily('2027-02-11') as d) x),
  '^2027-01-04:2027-02-11:2:2 \| 1:0:2 \| true:2$');
select zz.chk('G11 nazorat ro''yxati: uchinchi qayta ishga tushirish — farq 21 500; to''xtatilgan davr (09.02–10.02) naqd harakati: kirim 33 000 (navbatdan kech kelgan to''lov ham), chiqim 9 000 (Direktor keyin kiritgan chek ham); orqa sanali — faqat eski tartibdagi yozuv (himoya chizig''i); izohlanmagan farq 0; oxirgi kassa kuni sanali yetim bu yerga kirmaydi',
  (select (r ->> 'prevDay') || ':' || (r ->> 'delta') || ':' || (r #>> '{rows,in}') || '-' || (r #>> '{rows,out}') || ':' || (r #>> '{rows,n}')
          || ':' || (r #>> '{backdated,n}') || '/' || (r #>> '{backdated,out}') || ':' || (r ->> 'unexplained')
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q, jsonb_array_elements(c -> 'restarts') r where r ->> 'startDay' = '2027-02-11'),
  '^2027-02-08:21500:33000-9000:6:1/2500:0$');
select zz.chk('G13 «Kassa» holati — kassa ishlamagan kunlar (admin.html dagi Direktor oynalari shu bilan, server qoidasi bilan bir xil): birinchi ishga tushgan kun va to''xtatilgan davrlar',
  (select (s #>> '{desk,firstDay}') || ' | ' || (select string_agg((g ->> 'after') || '>' || (g ->> 'before'), ',' order by g ->> 'after') from jsonb_array_elements(s #> '{desk,gaps}') g)
     from (select zz.js(zz.as('U_KAS', $q$select public.kassa_state('main')::text$q$)) as s) q)
  || ' | ' || (select string_agg(app.kassa_pre_day('main', d::date)::text, ',' order by d) from generate_series('2027-01-03'::date, '2027-01-04'::date, '1 day') d)
  || ' | ' || (select string_agg(app.kassa_pre_day('main', d::date)::text, ',' order by d) from generate_series('2027-02-07'::date, '2027-02-12'::date, '1 day') d),
  '^2027-01-04 \| 2027-02-01>2027-02-03,2027-02-03>2027-02-05,2027-02-08>2027-02-11 \| true,false \| false,false,true,true,false,false$');
select zz.chk('G12 KO-3 (fevral): uch qayta ishga tushirish farqi bilan qoldiqlar mos',
  (select (j ->> 'restartAdj') || ':' || (j ->> 'closing') || ':' || (j ->> 'balanced') from (select zz.js(zz.as('U_FM', $q$select public.kassa_journal('main', '2027-02-01', '2027-02-28')::text$q$)) as j) q),
  '^61500:4965500:true$');

-- ---------- g4b-v1: oxirgi kassa kuni qurilma navbatidagi «hali o'tkazilmagan yozuvlar» bilan yopilgan — kassa to'xtatilmaydi
--   (ishga-tushirish §9 (1)); to'xtatilgan kassada navbatdan kech kelgan to'lov qayta yuborilmasin ----------
--   Avval: bunday kundan keyin kassa to'xtatilsa, navbatdagi to'lovni to'xtatilgan kassa rad etardi, qayta ishga tushgach esa u kech KO-1
--   bilan yozilib, komissiya sanashiga kirgan pulni ikkinchi marta hisoblardi — birinchi yopishda kassirga kamomad.
--   12.02: KO-1 (kun ochildi); qurilma oflayn — 17:00 da 5 000 naqd to'lov navbatda; 18:00 kun «hali o'tkazilmagan 1 ta / 5 000» bilan
--   yopildi (sanalgan = kun oxiri + 5 000).
select zz.clock('2027-02-12 10:00+05');
select zz.put('P1', zz.pay('U_KAS', 'man_p1_0001', 'T-5', 10000, 'cash', '', null, '{"fiscalNo":"F-P1"}'));
select zz.clock('2027-02-12 18:00+05');
select zz.put('P1c', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-12","counted":4980500,"pendingRefs":[{"ref":"man_p3_0001","amount":5000}]}')::text$q$));
select zz.clock('2027-02-12 18:10+05');
select zz.chk('P1 g4b-v1: oxirgi kun (12.02) qurilma navbatidagi hali o''tkazilmagan yozuv bilan yopilgan — kassa to''xtatilmaydi (kassa:rollback_pending: kun, soni, summasi); sanani surish (to''xtatish) ham — rad; kassa ishlayveradi',
  (zz.js(zz.get('P1')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('P1c')) ->> 'diff') || ':' || (select trim_scale(closing) || '/' || "pendingCount" from public.cash_days where day = '2027-02-12')
  || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-03-01"}')::text$q$)
  || ' | ' || (select "kassaGoLive"::text from public.fin_org where id = 'main') || ':' || coalesce((select "pausedAt"::text from public.cash_desks where id = 'main'), 'ishlaydi'),
  '^2027-02-12:0:4975500/1 \| ERR P0001 \[kassa:rollback_pending\] Kassani to''xtatib bo''lmaydi: oxirgi kassa kuni \(12\.02\.2027\) qurilma navbatidagi hali o''tkazilmagan 1 ta yozuv \(5000 so''m\) bilan yopilgan — bu pul kassada bor, hisobda hali yo''q.*Direktor kunni qayta ochadi.*keyin kassa to''xtatiladi \(ishga-tushirish §9\) \| ERR P0001 \[kassa:rollback_pending\].* \| 2027-02-11:ishlaydi$');
savepoint p2v;   -- kun tekshirilgan (qayta ochilmaydi): navbat keyingi kassa kuniga «kech» tushadi, o'sha kun yopilgach kassa to'xtatiladi
set local session_replication_role = replica;   -- (holat: tekshiruv tartibi — oldingi kunlar ham tekshirilgan bo'lishi kerak; bu yerda faqat natija)
update public.cash_days set status = 'verified', "verifiedBy" = 'U_FM', "verifiedAt" = now() where desk = 'main' and day = '2027-02-12';
set local session_replication_role = origin;
select zz.put('P2v', zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-02-12', 'Navbat yuborilsin')::text$q$));
select zz.clock('2027-02-13 09:00+05');
select zz.put('P2va', zz.payd('U_KAS', 'man_p2_0001', 'T-5', 5000, 'cash', '2027-02-12', '2027-02-12 17:00+05', '{"fiscalNo":"F-P2"}'));
select zz.put('P2vb', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-13","counted":4980500}')::text$q$));
select coalesce(zz.get('P2v') || ' | ' || (zz.js(zz.get('P2va')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('P2va')) #>> '{kassa,late}') || ' | ' || (zz.js(zz.get('P2vb')) ->> 'diff')
  || ' | ' || zz.jd(zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$), 'kassaGoLive', 'bo''sh'), '<null>') as p2v \gset
rollback to savepoint p2v;
select zz.chk('P2v kun tekshirilgan bo''lsa (qayta ochilmaydi): navbat keyingi kassa kuniga (13.02) «kech» KO-1 bilan tushadi, o''sha kun farqsiz yopilgach kassa to''xtatiladi', :'p2v',
  '^ERR 42501 \[kassa:verified\].* \| 2027-02-13:true \| 0 \| bo''sh$');
select zz.clock('2027-02-12 18:15+05');
select zz.put('P3', zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-02-12', 'Qurilma navbati yuborilsin')::text$q$));
select zz.clock('2027-02-12 18:20+05');
select zz.put('P3a', zz.payd('U_KAS', 'man_p3_0001', 'T-5', 5000, 'cash', '2027-02-12', '2027-02-12 17:00+05', '{"fiscalNo":"F-P3"}'));
select zz.clock('2027-02-12 18:30+05');
select zz.put('P3b', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-12","counted":4980500}')::text$q$));
select zz.clock('2027-02-12 18:40+05');
select zz.put('P4', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$));
select zz.chk('P3 Direktor kunni qayta ochdi — navbatdagi to''lov o''sha kunga tushdi (KO-1, «kech» emas), kun farqsiz qayta yopildi (hali o''tkazilmagan yozuv yo''q); endi kassa to''xtatildi',
  (zz.js(zz.get('P3')) ->> 'ok') || ' | ' || (zz.js(zz.get('P3a')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('P3a')) #>> '{kassa,late}')
  || ' | ' || (zz.js(zz.get('P3b')) ->> 'diff') || ':' || (select trim_scale(closing) || '/' || "pendingCount" from public.cash_days where day = '2027-02-12')
  || ' | ' || zz.jd(zz.get('P4'), 'kassaGoLive', 'bo''sh') || ':' || (select ("pausedAt" is not null)::text from public.cash_desks where id = 'main'),
  '^true \| 2027-02-12:false \| 0:4980500/0 \| bo''sh:true$');
select zz.clock('2027-02-13 09:00+05');
select zz.put('P5', zz.payd('U_KAS', 'man_p5_0001', 'T-5', 4000, 'cash', '2027-02-12', '2027-02-12 18:35+05', null));
select zz.chk('P5 to''xtatilgan kassa: qurilma navbatidan kech kelgan, oxirgi kassa kuni (12.02) sanali naqd to''lov — rad; xabar navbatdagi to''lov qayta ishga tushgach ham qayta yuborilmasligini (qurilma navbati oynasidagi 140 belgida) va to''xtatilgan davr puli qaysi sana bilan yozilishini aytadi',
  zz.get('P5') || ' | ' || (strpos(left(regexp_replace(zz.get('P5'), '^ERR \S+ \[[^]]*\] ', ''), 140), 'qayta yubormang — Direktor hal qiladi') > 0)::text,
  '^ERR 42501 \[kassa:paused_live_day\] To''lov sanasi \(12\.02\.2027\) — kassa kuni edi: to''xtatilgan kassada yozilmaydi, qayta ishga tushgach ham qayta yubormang — Direktor hal qiladi \(oxirgi kassa kuni 12\.02\.2027 kassa hujjatlari bilan yopilgan; pul kassada sanalgan bo''lsa, kirim orderi uni ikkinchi marta hisoblardi — buxgalter bilan\)\. .*kun yopilgandan keyin olingani — ertasi kuni, o''sha sana bilan\) \| true$');
select zz.chk('P5b g4b-v1: to''xtatilgan kassada 31 kundan eski «Sana» (05.01 — yopilgan kassa kuni) bugungi to''xtatilgan davr sanasiga surilib yozilmaydi — so''ralgan sana bo''yicha rad; iz yo''q',
  zz.payd('U_DIR', 'man_p5_0002', 'T-5', 4000, 'cash', '2027-01-05', null, null)
  || ' | ' || (select count(*) from public.payments where id in ('man_p5_0001', 'man_p5_0002')),
  '^ERR 42501 \[kassa:paused_live_day\] To''lov sanasi \(05\.01\.2027\) — kassa kuni edi: .*\(oxirgi kassa kuni 12\.02\.2027 .* \| 0$');
select zz.clock('2027-02-13 18:00+05');
select zz.put('P6', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4980500,"startDay":"2027-02-14","note":"Sanash 5"}')::text$q$));
select zz.put('P6b', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-14"}')::text$q$));
select zz.clock('2027-02-14 09:00+05');
select zz.put('P7', zz.pay('U_KAS', 'man_p7_0001', 'T-5', 1000, 'cash', '', null, '{"fiscalNo":"F-P7"}'));
select zz.chk('P7 qayta ishga tushirish farqi 0 (navbatdagi pul to''xtatishdan oldin hisobga kirgan) — birinchi kun farqsiz yopildi, kassirga kamomad yo''q; nazorat ro''yxatida izohlanmagan farq 0; moslik (12.02–14.02) toza',
  (zz.js(zz.get('P6')) ->> 'delta') || ':' || (zz.js(zz.get('P6b')) ->> 'kassaGoLive') || ' | ' || (zz.js(zz.get('P7')) #>> '{kassa,day}')
  || ':' || (zz.js(zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-14","counted":4981500}')::text$q$)) ->> 'diff')
  || ' | ' || (select (r ->> 'delta') || ':' || (r ->> 'unexplained') from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q, jsonb_array_elements(c -> 'restarts') r where r ->> 'startDay' = '2027-02-14')
  || ' | ' || (app.kassa_reconcile('2027-02-12', '2027-02-14') ->> 'total'),
  '^0:2027-02-14 \| 2027-02-14:0 \| 0:0 \| 0$');

-- ---------- g4b (yakuniy tekshiruv qoldiqlari): to'xtatilgan kassada tayyorlangan qayta ishga tushirish kuni va keyingi sanali naqd
--   yozuv; sanashdan KEYIN qurilma navbatiga yozilgan to'lov; naqdsiz yozuvni usulsiz qilish ----------
--   14.02 yopilgan (4 981 500), kassa to'xtatiladi. Qurilma A 15.02 17:00 da 3 000 naqd to'lov oldi (oflayn — sanashdan OLDIN: pul
--   sanashga kiradi). Komissiya 15.02 18:00 da 17.02 uchun sanadi: 4 981 500 + 3 000 = 4 984 500 (kassa hali to'xtatilgan).
select zz.clock('2027-02-14 19:00+05');
select zz.put('L0', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$));
select zz.clock('2027-02-15 18:00+05');
select zz.put('L0b', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":4984500,"startDay":"2027-02-17","note":"Sanash 6"}')::text$q$));
select zz.chk('L0 kassa to''xtatildi; qayta ishga tushirish qoldig''i 17.02 uchun (farq 3 000), ishga tushadigan kun hali qo''yilmagan',
  zz.jd(zz.get('L0'), 'kassaGoLive', 'bo''sh') || ' | ' || (zz.js(zz.get('L0b')) ->> 'delta')
  || ' | ' || (select ("pausedAt" is not null)::text || ':' || "restartDay"::text from public.cash_desks where id = 'main'),
  '^bo''sh \| 3000 \| true:2027-02-17$');
-- Avval: to'xtatilgan kassada (kutayotgan kassadan farqli) qayta ishga tushirish kuni va keyingi sana bilan naqd yozuv hamma uchun ochiq edi;
--   ishga tushadigan kun keyin qo'yilsa ham tekshirilmasdi — yangi kassa davri yetimi (P4) bo'lib qolardi.
select zz.clock('2027-02-15 18:30+05');
savepoint l1;   -- (natija psql o'zgaruvchisida — savepoint ortga qaytarilgach tekshiriladi)
select coalesce(zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_l1a', '2027-02-17', '2027-02', 'Boshqa', 1200, 'oldindan', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_l1b', '2027-02-20', '2027-02', 'Boshqa', 1200, 'oldindan', '') returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_l1c', '2027-02-17', '2027-02', 'Boshqa', 1200, 'bank orqali', 'bank') returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (update public.expenses set method = 'cash' where id = 'e_l1c' returning id) select id from x$q$), '<null>') as l1 \gset
set local session_replication_role = replica;   -- himoyasiz eski yo'l bilan kiritilgan (yoki shu tuzatishdan oldin qolgan) yozuv
insert into public.expenses (id, date, month, category, amount, note, method, "createdAt") values ('e_l1d', '2027-02-18', '2027-02', 'Boshqa', 1200, 'eski yo''l', 'cash', '2027-02-15 18:20+05');
set local session_replication_role = origin;
select coalesce(zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-17"}')::text$q$)
  || ' | ' || coalesce((select "kassaGoLive"::text from public.fin_org where id = 'main'), 'bo''sh') || ':' || (select ("pausedAt" is not null)::text from public.cash_desks where id = 'main'), '<null>') as l1g \gset
rollback to savepoint l1;
select zz.chk('L1 g4b: to''xtatilgan kassada tayyorlangan, hali kelmagan qayta ishga tushirish kuni (17.02) va keyingi sana bilan kassa hujjatisiz naqd (yoki usulsiz) xarajat — moliya menejeriga ham, Direktorga ham yo''q (kassa:restart_gap), naqdsiz yozuvni naqdga aylantirish ham; naqdsiz yozuv — avvalgidek', :'l1',
  '^ERR 42501 \[kassa:restart_gap\] 17\.02\.2027 — qayta ishga tushirish kuni \(17\.02\.2027\) yoki undan keyingi sana.* \| ERR 42501 \[kassa:restart_gap\] 20\.02\.2027 — .* \| e_l1c \| ERR 42501 \[kassa:restart_gap\] 17\.02\.2027 — .*$');
select zz.chk('L1g g4b: shunday yozuv bo''lsa (himoyasiz eski yo''l) — ishga tushadigan kun qo''yilmaydi (kassa:restart_gap: soni va chora), kassa to''xtatilgan qoladi', :'l1g',
  '^ERR P0001 \[kassa:restart_gap\] Qayta ishga tushirish kuni \(17\.02\.2027\) yoki undan keyingi sana bilan kassa hujjatisiz 1 ta naqd yozuv bor.*ulardan keyingi kun bilan qayta kiritiladi \| bo''sh:true$');
savepoint l1p;   -- qayta ishga tushirish kuni o'tib ketgan, kassa hali to'xtatilgan: eski tartib davom etadi, lekin kassa shu kundan ishga tushmaydi
select zz.clock('2027-02-18 09:00+05');
select coalesce(zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_l1p', '2027-02-18', '2027-02', 'Boshqa', 1200, 'to''xtatilgan davr', 'cash') returning id) select id from x$q$)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-17"}')::text$q$), '<null>') as l1p \gset
rollback to savepoint l1p;
select zz.chk('L1p qayta ishga tushirish kuni (17.02) o''tib ketgan, kassa hali to''xtatilgan — bugungi naqd xarajat avvalgi tartibda qabul qilinadi, lekin kassa 17.02 dan ishga tushirilmaydi (kassa:restart_gap — keyingi kun bilan qayta sanash)', :'l1p',
  '^e_l1p \| ERR P0001 \[kassa:restart_gap\] Qayta ishga tushirish kuni \(17\.02\.2027\) yoki undan keyingi sana bilan kassa hujjatisiz 1 ta naqd yozuv bor.*$');
-- Avval: sanashdan keyin (16.02) qurilma navbatiga yozilgan to'lov kassa qayta ishga tushgach (birinchi kun boshqa hujjat bilan ochilgandan
--   keyin) KO-1 siz yozilardi — pul sanashga kirmagan: birinchi yopishda ortiqcha (in_surplus) chiqib, tushum ikki marta hisoblanardi;
--   birinchi hujjat bo'lib kelsa — qator o'zini «sanashdan keyingi yozuv» deb sanab, birinchi kun qayta sanashsiz ochilmasdi.
--   Qurilma B: 16.02 18:00 da 2 000 (17.02 09:00 da birinchi hujjat bo'lib yuborildi); qurilma C: 16.02 19:00 da 1 500 (10:00 da);
--   qurilma A: 15.02 17:00 da (sanashdan OLDIN) 3 000 (10:30 da).
select zz.clock('2027-02-15 19:00+05');
select zz.put('L2a', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-17"}')::text$q$));
select zz.clock('2027-02-17 09:00+05');
select zz.put('L2b', zz.pay('U_KAS', 'man_l2_0001', 'T-5', 2000, 'cash', '', '2027-02-16 18:00+05', '{"fiscalNo":"F-L2B"}'));
select zz.clock('2027-02-17 10:00+05');
select zz.put('L2c', zz.pay('U_KAS', 'man_l2_0002', 'T-5', 1500, 'cash', '', '2027-02-16 19:00+05', '{"fiscalNo":"F-L2C"}'));
select zz.clock('2027-02-17 10:30+05');
select zz.put('L2d', zz.pay('U_KAS', 'man_l2_0003', 'T-5', 3000, 'cash', '', '2027-02-15 17:00+05', null));
select zz.chk('L2 g4b: sanashdan keyin qurilma navbatiga yozilgan to''lov — birinchi hujjat bo''lib kelsa ham KO-1 bilan bugungi kunga («kech»): birinchi kun ochildi (kun boshi — sanalgan summa); kun ochilgandan keyin kelgani ham; sanashdan OLDIN olingani — KO-1 siz (pul sanashga kirgan)',
  (zz.js(zz.get('L2a')) ->> 'kassaGoLive')
  || ' | ' || coalesce((zz.js(zz.get('L2b')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('L2b')) #>> '{kassa,late}') || ':' || (select trim_scale(opening)::text from public.cash_days where day = '2027-02-17'), zz.get('L2b'))
  || ' | ' || coalesce((zz.js(zz.get('L2c')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('L2c')) #>> '{kassa,late}'), zz.get('L2c'))
  || ' | ' || (select string_agg(id || ':' || (raw ->> 'date') || ':' || ("cashDocId" is not null), ',' order by id) from public.payments where id like 'man\_l2\_%')
  || ' | ' || zz.jd(zz.get('L2d'), 'kassa', 'null'),
  '^2027-02-17 \| 2027-02-17:true:4984500 \| 2027-02-17:true \| man_l2_0001:2027-02-17:true,man_l2_0002:2027-02-17:true,man_l2_0003:2027-02-15:false \| null$');
select zz.chk('L3 17.02 yopildi — farq 0 (sanashdan keyingi pul kirim orderlari bilan); nazorat ro''yxati: qayta ishga tushirish farqi 3 000 = to''xtatilgan davr kirimi (sanashdan oldin olingan to''lov), izohlanmagan farq 0; moslik toza',
  (zz.js(zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-02-17","counted":4988000}')::text$q$)) ->> 'diff')
  || ' | ' || (select (r ->> 'delta') || ':' || (r #>> '{rows,in}') || ':' || (r ->> 'unexplained') from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q, jsonb_array_elements(c -> 'restarts') r where r ->> 'startDay' = '2027-02-17')
  || ' | ' || (app.kassa_reconcile('2027-02-14', '2027-02-17') ->> 'total'),
  '^0 \| 3000:3000:0 \| 0$');
-- Avval: ishlayotgan kassada naqdsiz yozuvni usulsiz qilish (usuli ko'rsatilmagan — moslikda naqd) qabul qilinardi: moslik yetimi (P4)
select zz.put('L4a', zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_l4', '2027-02-17', '2027-02', 'Boshqa', 700, 'bank xizmati', 'bank') returning id) select id from x$q$));
select zz.chk('L4 g4b: ishlayotgan kassada naqdsiz xarajatni usulsiz qilish — rad (kassa:cash_only_kassa), usuli bo''sh (null) ham; summasini o''zgartirish — avvalgidek; moslik toza qoladi',
  zz.get('L4a') || ' | ' || zz.as('U_FM', $q$with x as (update public.expenses set method = '' where id = 'e_l4' returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (update public.expenses set method = null where id = 'e_l4' returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (update public.expenses set amount = 800 where id = 'e_l4' returning id) select id from x$q$)
  || ' | ' || (app.kassa_reconcile('2027-02-17', '2027-02-17') ->> 'total'),
  '^e_l4 \| ERR 42501 \[kassa:cash_only_kassa\] Naqd \(yoki usuli ko''rsatilmagan\) yozuv faqat «Kassa» orqali kiritiladi.* \| ERR 42501 \[kassa:cash_only_kassa\] .* \| e_l4 \| 0$');

-- ---------- g7: oflayn va kutilayotgan yozuvlar (state-2, state-3, state-8, crit-3) ----------
--   Avval: kunni yopish va smena topshirishda «hali o'tkazilmagan yozuvlar» faqat soni va summasi bilan kelardi — oyna ochiq paytda qurilma
--   navbati o'tib ketsa ikki marta ayirilib, kamomad yozilardi (keyingi kuni — ortiqcha); o'ylab topilgan yozuv ortiqchani jim yashirardi.
--   Yopilgan kunga o'sha kechqurun kelgan navbat yozuvi kassa:day_closed bilan, oy yopilgach esa fin:locked bilan abadiy rad etilardi;
--   kech fiskal chek Z-hisobotda ikki kunda teskari farq berardi; server ishlamagan kunning «Қ» blankalari uchun yopish oynasida joy yo'q edi.
--   Yangi kunlar 01.03–07.04.2027 (kassa 17.02 dan ishlaydi; 17.02 yopilgan: 4 988 000). Oldingi kunlar tekshiruv tartibi uchun
--   «tekshirilgan» deb belgilanadi (bu yerda faqat natija, P2v dagi kabi).
create or replace function zz.kc(p_uid text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_day_close(%L::jsonb)::text', p_json)) $$;
create or replace function zz.kh(p_uid text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_handover(%L::jsonb)::text', p_json)) $$;
create or replace function zz.kv(p_uid text, p_day text, p_note text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_day_verify(%L, %L, true, %L)::text', 'main', p_day, coalesce(p_note, ''))) $$;
create or replace function zz.kbal() returns numeric language sql as $$
  select app.kassa_day_balance((select id from public.cash_days where desk = 'main' and status = 'open')) $$;
-- kunning hali bog'lanmagan yozuvlari: navbat yozuvlari soni : summasi : «Қ» blankalari soni
create or replace function zz.kpend(p_day text) returns text language sql as $$
  select (p ->> 'n') || ':' || trim_scale((p ->> 'sum')::numeric) || ':' || (p ->> 'paperCount') from (select app.kassa_day_pending('cd_main_' || p_day) as p) x $$;
create or replace function zz.zst(p_day text) returns text language sql as $$
  select (z ->> 'expCash') || ':' || (z ->> 'nCash') || ':' || coalesce(z ->> 'diffCash', '-') || ':' || (z ->> 'ok') from (select app.kassa_z_state('cd_main_' || p_day) as z) x $$;
create or replace function zz.pendopen() returns jsonb language sql as $$
  select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) -> 'pendingOpen' $$;
set local session_replication_role = replica;
update public.cash_days set status = 'verified', "verifiedBy" = 'U_TCH', "verifiedAt" = now() where desk = 'main' and status = 'closed';
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values ('s9','T-9','Sinov G',5,'A','uz','',9,'[]');
set local session_replication_role = origin;
-- 01.03: oyna ochildi (qoldiq 5 088 000), qurilma navbatidagi 50 000 o'zi o'tdi (oyna ochiq), kassir oynadagi qiymatlar bilan yopadi
select zz.clock('2027-03-01 09:00+05');
select zz.put('Q0', zz.pay('U_KAS', 'man_q1_0001', 'T-9', 100000, 'cash', '', null, '{"fiscalNo":"F-Q11"}'));
select zz.clock('2027-03-01 17:55+05');
select zz.put('Q1b', zz.kbal()::text);
select zz.clock('2027-03-01 17:56+05');
select zz.put('Q1f', zz.pay('U_KAS', 'man_q1_0002', 'T-9', 50000, 'cash', '', '2027-03-01 16:00+05', '{"fiscalNo":"F-Q12"}'));
select zz.clock('2027-03-01 17:57+05');
select zz.put('Q1', zz.kc('U_KAS', format('{"day":"2027-03-01","counted":%s,"expected":%s,"pendingRefs":[{"ref":"man_q1_0002","amount":50000},{"ref":"man_q1_0003","amount":30000}],"z":{"no":"Z-0301","cash":180000,"card":0}}',
                                         zz.kbal() + 30000, zz.get('Q1b'))));
select zz.chk('Q1 state-2: oyna ochilgandan keyin navbat yozuvi o''tdi — oynadagi eski qoldiq bilan yopish rad (kassa:stale: oynada / hozir), kun ochiq, farq hujjati yo''q',
  zz.get('Q1') || ' | ' || (select status from public.cash_days where day = '2027-03-01')
  || ':' || (select count(*) from public.cash_docs where "businessDay" = '2027-03-01' and op in ('in_surplus', 'out_shortage')),
  '^ERR P0001 \[kassa:stale\] Kassa qoldig''i oyna ochilgandan keyin o''zgargan \(oynada 5088000 so''m, hozir 5138000 so''m\) — oyna yangilanadi: pulni qayta sanab, yana yuboring \| open:0$');
select zz.put('Q2', zz.kc('U_KAS', format('{"day":"2027-03-01","counted":%s,"expected":%s,"pendingRefs":[{"ref":"man_q1_0002","amount":50000},{"ref":"man_q1_0003","amount":30000}],"z":{"no":"Z-0301","cash":180000,"card":0}}',
                                         zz.kbal() + 30000, zz.kbal())));
select zz.chk('Q2 state-2: yangilangan oynadan — o''tib ketgan yozuv ayirilmadi (ignoredRefs), hali o''tmagani ayirildi: farq 0, kamomad yo''q; kunda va sanash dalolatnomasida yozuv kaliti va summasi',
  (zz.js(zz.get('Q2')) ->> 'diff') || ':' || (zz.js(zz.get('Q2')) -> 'ignoredRefs')::text
  || ' | ' || (select trim_scale(closing) || ':' || trim_scale(counted) || ':' || "pendingCount" || ':' || trim_scale("pendingSum") || ':' || "pendingRefs"::text from public.cash_days where day = '2027-03-01')
  || ' | ' || (select "pendingRefs"::text || ':' || trim_scale("pendingSum") from public.cash_counts where "dayId" = 'cd_main_2027-03-01' and kind = 'close')
  || ' | ' || (select count(*) from public.cash_docs where "businessDay" = '2027-03-01' and op in ('in_surplus', 'out_shortage')),
  '^0:\["man_q1_0002"\] \| 5138000:5168000:1:30000:\[\{"ref": "man_q1_0003", "amount": 30000\}\] \| \[\{"ref": "man_q1_0003", "amount": 30000\}\]:30000 \| 0$');
select zz.chk('Q3 state-8: yopishda Z (180 000) — oflayn urilgan chek (30 000) hali kirim orderisiz: Z farqi +30 000',
  zz.zst('2027-03-01'), '^150000:2:30000:false$');
select zz.clock('2027-03-01 18:05+05');
select zz.put('Q4', zz.pay('U_KAS', 'man_q1_0003', 'T-9', 30000, 'cash', '', '2027-03-01 17:30+05', '{"fiscalNo":"F-Q13"}'));
select zz.chk('Q4 state-3: o''sha kechqurun kelgan navbat yozuvi — kun yopilgan (kassa:day_closed — qurilma navbati kutib turadi), to''lov yozilmadi; kunning hali kelmagan yozuvi 1 ta / 30 000; izohsiz tekshirilmaydi (kassa:pending_note)',
  zz.get('Q4') || ' | ' || (select count(*) from public.payments where id = 'man_q1_0003') || ' | ' || zz.kpend('2027-03-01') || ' | ' || zz.kv('U_FM', '2027-03-01', null),
  '^ERR P0001 \[kassa:day_closed\].* \| 0 \| 1:30000:0 \| ERR 22023 \[kassa:pending_note\] Kun hali o''tkazilmagan yozuvlar bilan yopilgan: qurilma navbatidagi 1 ta yozuvning \(30000 so''m\) kirim orderi hali kelmagan\..*$');
select zz.clock('2027-03-02 09:00+05');
select zz.put('Q5', zz.pay('U_KAS', 'man_q1_0003', 'T-9', 30000, 'cash', '', '2027-03-01 17:30+05', '{"fiscalNo":"F-Q13"}'));
select zz.chk('Q5 state-3: ertasi kuni navbat yozuvi yangi kunga «kech» tushdi (kun boshi — kecha oxiri); to''lov qatori sanasi — kirim orderi kuni, olingan payt saqlangan; kun yozuvi bog''landi',
  coalesce((zz.js(zz.get('Q5')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Q5')) #>> '{kassa,late}'), zz.get('Q5')) || ':' || (select trim_scale(opening) from public.cash_days where day = '2027-03-02')
  || ' | ' || (select (raw ->> 'date') || ':' || ((raw ->> 'capturedAt')::timestamptz = '2027-03-01 17:30+05')::text from public.payments where id = 'man_q1_0003')
  || ' | ' || zz.kpend('2027-03-01'),
  '^2027-03-02:true:5138000 \| 2027-03-02:true \| 0:0:0$');
select zz.chk('Q6 state-8: kech kirim orderi Z da chek urilgan kunda sanaladi — 01.03: 3 chek / 180 000, farq 0; 02.03 da sanalmaydi',
  zz.zst('2027-03-01') || ' | ' || zz.zst('2027-03-02'), '^180000:3:0:true \| 0:0:-:true$');
select zz.chk('Q7 01.03 endi izohsiz tekshirildi (navbat yozuvi kelgan, Z mos)', zz.js(zz.kv('U_FM', '2027-03-01', null)) -> 'day' ->> 'status', '^verified$');
-- 02.03: smena topshirish qurilma navbatidagi yozuv bilan (state-2 + g6: ikki bosqichli topshirish)
select zz.clock('2027-03-02 12:00+05');
select zz.put('Q8a', zz.kh('U_KAS', format('{"counted":%s,"expected":%s,"toUid":"U_KAS2","pendingRefs":[{"ref":"man_q2_0001","amount":20000}]}', zz.kbal() + 20000, zz.kbal() - 1)));
select zz.put('Q8', zz.kh('U_KAS', format('{"counted":%s,"expected":%s,"toUid":"U_KAS2","pendingRefs":[{"ref":"man_q2_0001","amount":20000}]}', zz.kbal() + 20000, zz.kbal())));
select zz.put('Q8f', zz.pay('U_KAS', 'man_q2_0001', 'T-9', 20000, 'cash', '', '2027-03-02 11:00+05', '{"fiscalNo":"F-Q21"}'));
select zz.chk('Q8 smena topshirish: ro''yxatsiz summa — rad (kassa:pending_refs); oynadagi eski qoldiq bilan — rad (kassa:stale); navbat yozuvi bilan topshirildi (farq 0, yozuv saqlandi); qabul kutilayotganda navbat yozuvi — kassa:handover_pending (qurilma navbati kutib turadi), to''lov yozilmadi',
  zz.kh('U_KAS', '{"counted":1,"toUid":"U_KAS2","pendingSum":5}') || ' | ' || zz.get('Q8a')
  || ' | ' || (zz.js(zz.get('Q8')) ->> 'diff') || ':' || (zz.js(zz.get('Q8')) #>> '{handover,pendingSum}') || ':' || (zz.js(zz.get('Q8')) #> '{handover,pendingRefs}')::text
  || ' | ' || zz.get('Q8f') || ':' || (select count(*) from public.payments where id = 'man_q2_0001'),
  '^ERR 22023 \[kassa:pending_refs\] Hali o''tkazilmagan yozuvlar endi ro''yxat bilan yuboriladi.* \| ERR P0001 \[kassa:stale\] .* \| 0:20000:\[\{"ref": "man_q2_0001", "amount": 20000\}\] \| ERR P0001 \[kassa:handover_pending\] .*:0$');
select zz.put('Q9', zz.as('U_KAS2', format('select public.kassa_handover_accept(%L)::text', zz.js(zz.get('Q8')) #>> '{handover,id}')));
select zz.put('Q9f', zz.pay('U_KAS', 'man_q2_0001', 'T-9', 20000, 'cash', '', '2027-03-02 11:00+05', '{"fiscalNo":"F-Q21"}'));
select zz.chk('Q9 qabul qilindi: dalolatnomaga topshirishda e''lon qilingan yozuv o''zgarmay o''tdi (farq 0); keyin navbat o''tdi — o''sha kunga (kech emas), yozuv bog''landi',
  (zz.js(zz.get('Q9')) ->> 'diff') || ':' || (zz.js(zz.get('Q9')) #> '{count,pendingRefs}')::text || ':' || (zz.js(zz.get('Q9')) #>> '{count,pendingSum}')
  || ' | ' || coalesce((zz.js(zz.get('Q9f')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Q9f')) #>> '{kassa,late}'), zz.get('Q9f')) || ' | ' || zz.kpend('2027-03-02'),
  '^0:\[\{"ref": "man_q2_0001", "amount": 20000\}\]:20000 \| 2027-03-02:false \| 0:0:0$');
select zz.clock('2027-03-02 18:00+05');
select zz.put('Q10', zz.kc('U_KAS2', format('{"day":"2027-03-02","counted":%s,"expected":%s,"z":{"no":"Z-0302","cash":20000,"card":0}}', zz.kbal(), zz.kbal())));
select zz.chk('Q10 02.03 farqsiz yopildi; Z da faqat shu kuni urilgan chek (20 000) — 01.03 cheki (kech order) bu kunda sanalmaydi: mos',
  (zz.js(zz.get('Q10')) ->> 'diff') || ' | ' || zz.zst('2027-03-02'), '^0 \| 20000:1:0:true$');
-- 03.03: o'ylab topilgan navbat yozuvi (kassadagi 30 000 ortiqchani yashirish); 04.03: pul olib qo'yilgan, kun farqsiz
select zz.clock('2027-03-03 09:00+05');
select left(zz.pay('U_KAS2', 'man_q3_0001', 'T-9', 10000, 'cash', '', null, '{"fiscalNo":"F-Q31"}'), 0);
select zz.clock('2027-03-03 18:00+05');
select zz.put('Q11', zz.kc('U_KAS2', format('{"day":"2027-03-03","counted":%s,"expected":%s,"pendingRefs":[{"ref":"man_q3_fake1","amount":30000}],"z":{"no":"Z-0303","cash":10000,"card":0}}', zz.kbal() + 30000, zz.kbal())));
select zz.clock('2027-03-04 09:00+05');
select left(zz.pay('U_KAS2', 'man_q4_0001', 'T-9', 1000, 'cash', '', null, '{"fiscalNo":"F-Q41"}'), 0);
select zz.clock('2027-03-04 18:00+05');
select zz.put('Q12', zz.kc('U_KAS2', format('{"day":"2027-03-04","counted":%s,"expected":%s,"z":{"no":"Z-0304","cash":1000,"card":0}}', zz.kbal(), zz.kbal())));
select zz.chk('Q12 state-2: o''ylab topilgan navbat yozuvi — ikki kun ham farqsiz, lekin yozuv bog''lanmagan qoladi (1 ta / 30 000); 04.03 da nazorat ro''yxatida hali yo''q (2 kun o''tmagan)',
  (zz.js(zz.get('Q11')) ->> 'diff') || ':' || (zz.js(zz.get('Q12')) ->> 'diff') || ' | ' || zz.kpend('2027-03-03') || ' | ' || zz.pendopen()::text,
  '^0:0 \| 1:30000:0 \| \[\]$');
select zz.clock('2027-03-05 09:00+05');
select zz.put('Q13p', zz.pendopen()::text);
select zz.chk('Q13 2 kun (48 soat) o''tgach — nazorat ro''yxatida (kun, soni, summasi, yozuv kaliti); kun izohsiz tekshirilmaydi, izoh bilan — tekshirildi',
  (select (x ->> 'day') || ':' || (x ->> 'status') || ':' || (x ->> 'n') || ':' || (x ->> 'sum') || ':' || (x -> 'refs' -> 0 ->> 'ref') from jsonb_array_elements(zz.js(zz.get('Q13p'))) x)
  || ' | ' || left(zz.kv('U_FM', '2027-03-02', null), 0) || zz.kv('U_FM', '2027-03-03', null)
  || ' | ' || (zz.js(zz.kv('U_FM', '2027-03-03', 'Kassir: yozuv xato kiritilgan — kassada pul yo''q')) -> 'day' ->> 'status'),
  '^2027-03-03:closed:1:30000:man_q3_fake1 \| ERR 22023 \[kassa:pending_note\] .*30000 so''m.* \| verified$');
-- 31.03 (oy oxiri): kun qurilma navbatidagi uchta yozuv bilan yopildi; 01.04 Direktor martni yopmoqchi
select zz.clock('2027-03-31 09:00+05');
select left(zz.pay('U_KAS2', 'man_q5_0001', 'T-9', 5000, 'cash', '', null, '{"fiscalNo":"F-Q51"}'), 0);
select zz.clock('2027-03-31 18:00+05');
select zz.put('Q14', zz.kc('U_KAS2', format('{"day":"2027-03-31","counted":%s,"expected":%s,"pendingRefs":[{"ref":"man_q5_0002","amount":40000},{"ref":"man_q5_0003","amount":25000},{"ref":"man_q5_0004","amount":15000}],"z":{"no":"Z-0331","cash":85000,"card":0}}',
                                          zz.kbal() + 80000, zz.kbal())));
select zz.clock('2027-04-01 10:00+05');
select zz.put('Q15a', zz.as('U_DIR', $q$select public.fin_period_lock('2027-03-31', 'Mart')::text$q$));
select zz.put('Q15b', zz.kv('U_FM', '2027-03-04', null));
select zz.put('Q15c', zz.kv('U_FM', '2027-03-31', 'Uchta yozuv qurilma navbatida — kassir yuboradi'));
select zz.put('Q15', zz.as('U_DIR', $q$select public.fin_period_lock('2027-03-31', 'Mart')::text$q$));
select zz.chk('Q15 state-3: oy oxirgi kuni hali kelmagan navbat yozuvlari bilan yopilgan, tekshirilmagan — davr yopilmaydi (fin:pending: kun, soni); izoh bilan tekshirilgach — yopildi',
  zz.get('Q15a') || ' | ' || (zz.js(zz.get('Q15b')) -> 'day' ->> 'status') || ':' || (zz.js(zz.get('Q15c')) -> 'day' ->> 'status') || ' | ' || (zz.js(zz.get('Q15')) ->> 'lockedThrough'),
  '^ERR P0001 \[fin:pending\] Davrni yopib bo''lmaydi: 31\.03\.2027 kassa kuni hali o''tkazilmagan yozuvlar bilan yopilgan \(qurilma navbatidagi 3 ta yozuvning kirim orderi hali kelmagan\) va tekshirilmagan.* \| verified:verified \| 2027-03-31$');
-- davr yopilgandan keyin navbat yozuvlari kelmoqda: «Sana» = olingan kun (31.03) yoki bo'sh — avval fin:locked bilan abadiy rad etilardi
select zz.clock('2027-04-01 10:30+05');
select zz.put('Q16a', zz.payd('U_KAS2', 'man_q5_0002', 'T-9', 40000, 'cash', '2027-03-31', '2027-03-31 17:50+05', '{"fiscalNo":"F-Q52"}'));
select zz.clock('2027-04-01 18:00+05');
select zz.put('Q16c', zz.kc('U_KAS2', format('{"day":"2027-04-01","counted":%s,"expected":%s,"pendingRefs":[{"ref":"man_q5_0003","amount":25000},{"ref":"man_q5_0004","amount":15000}],"z":{"no":"Z-0401","cash":0,"card":0}}',
                                           zz.kbal() + 40000, zz.kbal())));
select zz.clock('2027-04-02 10:50+05');
select zz.put('Q16d', zz.payd('U_KAS2', 'man_q5_0003', 'T-9', 25000, 'cash', '2027-03-31', '2027-03-31 17:55+05', '{"fiscalNo":"F-Q53"}'));
select zz.put('Q16e', zz.pay('U_KAS2', 'man_q5_0004', 'T-9', 15000, 'cash', '', '2027-03-31 17:58+05', '{"fiscalNo":"F-Q54"}'));
select zz.chk('Q16 state-3: yopilgan oyning navbat yozuvlari ochiq kunga «kech» tushdi (01.04, 02.04); to''lov qatori sanasi — kirim orderi kuni, olingan payt (31.03) saqlangan; 01.04 qolgan ikki yozuv bilan farqsiz yopildi',
  coalesce((zz.js(zz.get('Q16a')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Q16a')) #>> '{kassa,late}'), zz.get('Q16a'))
  || ' | ' || (zz.js(zz.get('Q16c')) ->> 'diff') || ':' || (select "pendingCount" from public.cash_days where day = '2027-04-01')
  || ' | ' || coalesce((zz.js(zz.get('Q16d')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Q16d')) #>> '{kassa,late}'), zz.get('Q16d'))
  || ' | ' || coalesce((zz.js(zz.get('Q16e')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Q16e')) #>> '{kassa,late}'), zz.get('Q16e'))
  || ' | ' || (select string_agg(id || ':' || (raw ->> 'date') || ':' || ((raw ->> 'capturedAt')::timestamptz < '2027-04-01 00:00+05')::text, ',' order by id)
                 from public.payments where id in ('man_q5_0002', 'man_q5_0003', 'man_q5_0004')),
  '^2027-04-01:true \| 0:2 \| 2027-04-02:true \| 2027-04-02:true \| man_q5_0002:2027-04-01:true,man_q5_0003:2027-04-02:true,man_q5_0004:2027-04-02:true$');
select zz.clock('2027-04-02 18:00+05');
select zz.put('Q17c', zz.kc('U_KAS2', format('{"day":"2027-04-02","counted":%s,"expected":%s,"z":{"no":"Z-0402","cash":0,"card":0}}', zz.kbal(), zz.kbal())));
select zz.chk('Q17 31.03 yozuvlari bog''landi (0); 31.03 Z endi mos (kech cheklar o''z kunida); 02.04 farqsiz yopildi, Z 0 — mos; moslik (31.03–02.04) toza',
  zz.kpend('2027-03-31') || ' | ' || zz.zst('2027-03-31') || ' | ' || (zz.js(zz.get('Q17c')) ->> 'diff') || ':' || zz.zst('2027-04-02')
  || ' | ' || (app.kassa_reconcile('2027-03-31', '2027-04-02') ->> 'total'),
  '^0:0:0 \| 85000:4:0:true \| 0:0:0:0:true \| 0$');
-- crit-3: server 05.04 soat 15:00 dan ertasi ertalabgacha ishlamadi — 700 000 naqd to'lov: fiskal chek urildi va «Қ-0012» blankasi to'ldirildi
select zz.clock('2027-04-05 10:00+05');
select left(zz.pay('U_KAS2', 'man_q6_0001', 'T-9', 100000, 'cash', '', null, '{"fiscalNo":"F-Q61"}'), 0);
select zz.clock('2027-04-06 09:00+05');
select zz.put('Q18c', zz.pay('U_KAS2', 'man_q6_0002', 'T-9', 700000, 'cash', '', null, '{"fiscalNo":"F-Q62"}'));
select zz.chk('Q18 crit-3: server ishlamagan kun (05.04) ertasi kuni hali ochiq — «Қ» yozuvi kiritilmaydi (kassa:prev_open, avval kun yopiladi); «Қ» blankalari: soni, summasi, raqamlari birga — aks holda rad',
  zz.get('Q18c') || ' | ' || zz.kc('U_KAS2', format('{"day":"2027-04-05","counted":%s,"expected":%s,"paper":{"count":1,"sum":700000}}', zz.kbal() + 700000, zz.kbal()))
  || ' | ' || zz.kc('U_KAS2', format('{"day":"2027-04-05","counted":%s,"expected":%s,"paper":{"count":1,"nos":"Қ-0012"}}', zz.kbal() + 700000, zz.kbal()))
  || ' | ' || zz.kc('U_KAS2', format('{"day":"2027-04-05","counted":%s,"expected":%s,"paper":"Қ-0012"}', zz.kbal() + 700000, zz.kbal())),
  '^ERR P0001 \[kassa:prev_open\].* \| ERR 22023 \[kassa:paper\] «Қ» blankalari: soni, summasi va raqamlari birga kiritiladi \| ERR 22023 \[kassa:paper\] «Қ» .* \| ERR 22023 \[kassa:paper\] «Қ» blankalari ma''lumoti noto''g''ri$');
select zz.put('Q19', zz.kc('U_KAS2', format('{"day":"2027-04-05","counted":%s,"expected":%s,"paper":{"count":1,"sum":700000,"nos":"Қ-0012"},"z":{"no":"Z-0405","cash":800000,"card":0}}',
                                          zz.kbal() + 700000, zz.kbal())));
select zz.chk('Q19 crit-3: kun «Қ» blankalari bilan yopildi — farq 0 (ortiqcha yo''q, ertasi kuni kamomad ham bo''lmaydi); kunda va sanash dalolatnomasida — soni, summasi, raqamlari; jami hali o''tkazilmagan 700 000',
  (zz.js(zz.get('Q19')) ->> 'diff') || ' | ' || (select "pendingCount" || ':' || trim_scale("pendingSum") || ':' || "paperCount" || ':' || trim_scale("paperSum") || ':' || "paperNos" from public.cash_days where day = '2027-04-05')
  || ' | ' || (select "paperCount" || ':' || trim_scale("paperSum") || ':' || "paperNos" from public.cash_counts where "dayId" = 'cd_main_2027-04-05' and kind = 'close')
  || ' | ' || (select count(*) from public.cash_docs where "businessDay" = '2027-04-05' and op in ('in_surplus', 'out_shortage')),
  '^0 \| 1:700000:1:700000:Қ-0012 \| 1:700000:Қ-0012 \| 0$');
select zz.put('Q20a', zz.pay('U_KAS2', 'man_q6_0002', 'T-9', 700000, 'cash', '', null, '{"fiscalNo":"F-Q62"}'));
select zz.clock('2027-04-06 18:00+05');
select zz.put('Q20', zz.kc('U_KAS2', format('{"day":"2027-04-06","counted":%s,"expected":%s,"z":{"no":"Z-0406","cash":0,"card":0}}', zz.kbal(), zz.kbal())));
select zz.chk('Q20 «Қ» yozuvi kun yopilgach kiritildi (06.04, «kech» emas) — 06.04 farqsiz (pul 05.04 dan kassada); 05.04 nazorat ro''yxatida («Қ» blankalari), izohsiz tekshirilmaydi (soni, summasi, raqamlari)',
  coalesce((zz.js(zz.get('Q20a')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Q20a')) #>> '{kassa,late}'), zz.get('Q20a')) || ' | ' || (zz.js(zz.get('Q20')) ->> 'diff')
  || ' | ' || (select (x ->> 'day') || ':' || (x ->> 'paperCount') || ':' || (x ->> 'paperNos') from jsonb_array_elements(zz.pendopen()) x where x ->> 'day' = '2027-04-05')
  || ' | ' || left(zz.kv('U_FM', '2027-04-01', null), 0) || left(zz.kv('U_FM', '2027-04-02', null), 0) || zz.kv('U_FM', '2027-04-05', null),
  '^2027-04-06:false \| 0 \| 2027-04-05:1:Қ-0012 \| ERR 22023 \[kassa:pending_note\] Kun hali o''tkazilmagan yozuvlar bilan yopilgan: «Қ» blankalari — 1 ta, 700000 so''m \(№: Қ-0012\)\..*$');
select zz.chk('Q21 izoh bilan tekshirildi — nazorat ro''yxatidan tushdi',
  (zz.js(zz.kv('U_FM', '2027-04-05', '«Қ-0012» 06.04 da kiritildi; Z farqi shu')) -> 'day' ->> 'status')
  || ' | ' || (select count(*) from jsonb_array_elements(zz.pendopen()) x where x ->> 'day' = '2027-04-05'),
  '^verified \| 0$');
savepoint q22;   -- oxirgi kun hali kiritilmagan «Қ» blankalari bilan yopilgan: kassa to'xtatilmaydi; qayta ochish tarkibni bo'shatadi
select zz.clock('2027-04-07 10:00+05');
select left(zz.pay('U_KAS2', 'man_q7_0001', 'T-9', 1000, 'cash', '', null, '{"fiscalNo":"F-Q71"}'), 0);
select zz.clock('2027-04-07 18:00+05');
select left(zz.kc('U_KAS2', format('{"day":"2027-04-07","counted":%s,"expected":%s,"paper":{"count":2,"sum":9000,"nos":"Қ-0013, Қ-0014"}}', zz.kbal() + 9000, zz.kbal())), 0);
select zz.put('Q22s', zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":null}')::text$q$));
select zz.put('Q22r', zz.js(zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-04-07', 'Qayta sanash kerak')::text$q$)) -> 'day' ->> 'status');
select coalesce(zz.get('Q22s') || ' | ' || zz.get('Q22r')
  || ':' || (select "pendingCount" || ':' || trim_scale("pendingSum") || ':' || "paperCount" || ':' || "paperNos" || ':' || "pendingRefs"::text from public.cash_days where day = '2027-04-07'), '<null>') as q22 \gset
rollback to savepoint q22;
select zz.chk('Q22 crit-3: oxirgi kun hali kiritilmagan «Қ» blankalari bilan yopilgan — kassa to''xtatilmaydi (kassa:rollback_pending: soni, summasi; avval «Қ» yozuvlari); kun qayta ochilganda tarkib bo''shatiladi', :'q22',
  '^ERR P0001 \[kassa:rollback_pending\] Kassani to''xtatib bo''lmaydi: oxirgi kassa kuni \(07\.04\.2027\) server ishlamagan paytdagi hali kiritilmagan «Қ» blankalari \(2 ta, 9000 so''m\).* \| open:0:0:0::\[\]$');

-- ---------- g7b: kech chekning Z-hisobot kuni (g7v-1); smena topshirishda e'lon qilingan yozuvlar qabul qiluvchining yopishida (g7v-3) ----------
--   Avval: kech fiskal kirim orderi doim pul olingan kunning Z-hisobotida kutilardi — kun yopilgandan keyin olingan pul cheki NKM ning keyingi
--   smenasida (keyingi kunning Z ida) bo'lsa ham: olingan kunda «−», order kunida «+» Z farqi (ikkala kunga izoh); olingan kuni kassa kuni
--   ochilmagan bo'lsa (yakshanba) — chek hech bir kunda kutilmasdi. Smena topshirishda e'lon qilingan navbat yozuvi bilan qabul qilingan
--   kunni qabul qiluvchi navbatida bu yozuv bo'lmagan qurilmadan yopsa — soxta ortiqcha, yozuv kelgan kuni esa xuddi shuncha soxta kamomad.
--   Yangi kunlar 08.04–29.04.2027 (06.04 yopilgan, tekshirilmagan; 07.04 — savepoint bilan qaytarilgan; GV — 21.04–26.04; Z5 — 27.04–29.04).
select zz.clock('2027-04-08 08:00+05');
select zz.chk('Z0 g7v-5: «Қ» yozuvlari kiritilgan kun (06.04, kech emas) — Z farqi −700 000 (fiskal cheklar 05.04 Z ida); izohsiz tekshirilmaydi (kassa:z_note), izohda «Қ» raqami bilan — tekshirildi',
  zz.zst('2027-04-06') || ' | ' || zz.kv('U_FM', '2027-04-06', null)
  || ' | ' || (zz.js(zz.kv('U_FM', '2027-04-06', '«Қ-0012»: chek 05.04 da urilgan (05.04 Z da), yozuv 06.04 da kiritildi')) -> 'day' ->> 'status'),
  '^700000:1:-700000:false \| ERR 22023 \[kassa:z_note\] Onlayn kassa Z-hisoboti tizimdagi summalar bilan mos emas.* \| verified$');
-- Z1 (g7 tekshiruvchisi, s9): 08.04 18:00 da Z (100 000) chiqarildi va kun yopildi; 18:30 da qurilma (oflayn) 30 000 oldi — chek NKM ning
--   keyingi smenasida; navbat yozuvi kassa:day_closed bilan kutdi va ertasi kuni «kech» o'tdi
select zz.clock('2027-04-08 10:00+05');
select left(zz.pay('U_KAS2', 'man_z1_0001', 'T-9', 100000, 'cash', '', null, '{"fiscalNo":"F-Z11"}'), 0);
select zz.clock('2027-04-08 18:00+05');
select zz.put('Z1c', zz.kc('U_KAS2', format('{"day":"2027-04-08","counted":%s,"expected":%s,"z":{"no":"Z-0408","cash":100000,"card":0}}', zz.kbal(), zz.kbal())));
select zz.clock('2027-04-08 18:30+05');
select zz.put('Z1a', zz.pay('U_KAS2', 'man_z1_0002', 'T-9', 30000, 'cash', '', '2027-04-08 18:30+05', '{"fiscalNo":"F-Z12"}'));
select zz.clock('2027-04-09 09:00+05');
select zz.put('Z1b', zz.pay('U_KAS2', 'man_z1_0002', 'T-9', 30000, 'cash', '', '2027-04-08 18:30+05', '{"fiscalNo":"F-Z12"}'));
select zz.clock('2027-04-09 10:00+05');
select left(zz.pay('U_KAS2', 'man_z1_0003', 'T-9', 20000, 'cash', '', null, '{"fiscalNo":"F-Z13"}'), 0);
select zz.clock('2027-04-09 18:00+05');
select zz.put('Z1d', zz.kc('U_KAS2', format('{"day":"2027-04-09","counted":%s,"expected":%s,"z":{"no":"Z-0409","cash":50000,"card":0}}', zz.kbal(), zz.kbal())));
select zz.chk('Z1 g7v-1: kun yopilgandan keyin (18:30) olingan pul cheki — keyingi kun Z ida: 08.04 Z (100 000) mos, kech order (09.04) — 09.04 Z ida (30 000 + 20 000), mos; nazorat ro''yxatida Z farqi yo''q; yopilish payti — moliya soati bo''yicha (18:00)',
  (zz.js(zz.get('Z1c')) ->> 'diff') || ':' || (select ("closedAt" = '2027-04-08 18:00+05')::text from public.cash_days where day = '2027-04-08')
  || ' | ' || zz.get('Z1a') || ' | ' || coalesce((zz.js(zz.get('Z1b')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Z1b')) #>> '{kassa,late}'), zz.get('Z1b'))
  || ' | ' || (zz.js(zz.get('Z1d')) ->> 'diff') || ' | ' || zz.zst('2027-04-08') || ' / ' || zz.zst('2027-04-09')
  || ' | ' || (zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) -> 'zreport')::text,
  '^0:true \| ERR P0001 \[kassa:day_closed\].* \| 2027-04-09:true \| 0 \| 100000:1:0:true / 50000:2:0:true \| \[\]$');
-- Z2: yakshanba (11.04) — kassa kuni ochilmagan; qurilma 12:00 da 40 000 oldi (oflayn), dushanba 09:00 da yubordi
select zz.clock('2027-04-12 09:00+05');
select zz.put('Z2a', zz.pay('U_KAS2', 'man_z2_0001', 'T-9', 40000, 'cash', '', '2027-04-11 12:00+05', '{"fiscalNo":"F-Z21"}'));
select zz.clock('2027-04-12 10:00+05');
select left(zz.pay('U_KAS2', 'man_z2_0002', 'T-9', 5000, 'cash', '', null, '{"fiscalNo":"F-Z22"}'), 0);
select zz.clock('2027-04-12 18:00+05');
select zz.put('Z2c', zz.kc('U_KAS2', format('{"day":"2027-04-12","counted":%s,"expected":%s,"z":{"no":"Z-0412","cash":45000,"card":0}}', zz.kbal(), zz.kbal())));
select zz.chk('Z2 g7v-1: kassa kuni bo''lmagan kunda (yakshanba) olingan pul cheki — order kunida (12.04, «kech») kutiladi: Z (40 000 + 5 000) mos (avval bu chek hech bir kunda kutilmasdi)',
  coalesce((zz.js(zz.get('Z2a')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Z2a')) #>> '{kassa,late}'), zz.get('Z2a'))
  || ' | ' || (zz.js(zz.get('Z2c')) ->> 'diff') || ' | ' || zz.zst('2027-04-12')
  || ' | ' || app.kassa_z_day('main', '2027-04-12', true, '2027-04-11 12:00+05')::text,
  '^2027-04-12:true \| 0 \| 45000:2:0:true \| 2027-04-12$');
-- Z3: 13.04 18:00 da yopildi (Z 10 000); 18:30 da qurilma B 25 000 oldi (oflayn); 14.04 qurilma B navbatidagi yozuv e'lon qilinib yopildi
--   (Z: 25 000 + 15 000); qurilma B 15.04 ertalab internetga ulandi — kech order 15.04 ga; 15.04 ni kassir ertasi ertalab yopdi
select zz.clock('2027-04-13 10:00+05');
select left(zz.pay('U_KAS2', 'man_z3_0001', 'T-9', 10000, 'cash', '', null, '{"fiscalNo":"F-Z31"}'), 0);
select zz.clock('2027-04-13 18:00+05');
select zz.put('Z3c', zz.kc('U_KAS2', format('{"day":"2027-04-13","counted":%s,"expected":%s,"z":{"no":"Z-0413","cash":10000,"card":0}}', zz.kbal(), zz.kbal())));
select zz.clock('2027-04-14 10:00+05');
select left(zz.pay('U_KAS2', 'man_z3_0003', 'T-9', 15000, 'cash', '', null, '{"fiscalNo":"F-Z33"}'), 0);
select zz.clock('2027-04-14 18:00+05');
select zz.put('Z3k', (zz.kbal() + 25000)::text);   -- kassadagi pul (sanalgan): hisobdagi + qurilma B navbatidagi 25 000
select zz.put('Z3d', zz.kc('U_KAS2', format('{"day":"2027-04-14","counted":%s,"expected":%s,"pendingRefs":[{"ref":"man_z3_0002","amount":25000}],"z":{"no":"Z-0414","cash":40000,"card":0}}',
                                          zz.get('Z3k'), zz.kbal())));
select zz.clock('2027-04-15 09:00+05');
select zz.put('Z3a', zz.pay('U_KAS2', 'man_z3_0002', 'T-9', 25000, 'cash', '', '2027-04-13 18:30+05', '{"fiscalNo":"F-Z32"}'));
select zz.clock('2027-04-16 08:30+05');
select zz.put('Z3e', zz.kc('U_KAS2', format('{"day":"2027-04-15","counted":%s,"expected":%s,"z":{"no":"Z-0415","cash":0,"card":0}}', zz.get('Z3k'), zz.kbal())));
select zz.chk('Z3 g7v-1: olingan kun (13.04) yopilgandan keyin olingan, keyingi kun (14.04) yopilgan, order 15.04 da — chek pul olingandan keyin yopilgan birinchi kun (14.04) Z ida: 13.04, 14.04, 15.04 Z mos; kunlar farqsiz, 14.04 yozuvi bog''landi',
  (zz.js(zz.get('Z3c')) ->> 'diff') || ':' || (zz.js(zz.get('Z3d')) ->> 'diff') || ':' || (zz.js(zz.get('Z3e')) ->> 'diff')
  || ' | ' || coalesce((zz.js(zz.get('Z3a')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Z3a')) #>> '{kassa,late}'), zz.get('Z3a'))
  || ' | ' || app.kassa_z_day('main', '2027-04-15', true, '2027-04-13 18:30+05')::text || ':' || app.kassa_z_day('main', '2027-04-15', true, '2027-04-13 17:30+05')::text
  || ':' || app.kassa_z_day('main', '2027-04-15', false, '2027-04-13 18:30+05')::text
  || ' | ' || zz.zst('2027-04-13') || ' / ' || zz.zst('2027-04-14') || ' / ' || zz.zst('2027-04-15') || ' | ' || zz.kpend('2027-04-14'),
  '^0:0:0 \| 2027-04-15:true \| 2027-04-14:2027-04-13:2027-04-15 \| 10000:1:0:true / 40000:2:0:true / 0:0:0:true \| 0:0:0$');
select zz.chk('Z4 kunlar izohsiz tekshirildi (Z mos, hali kelmagan yozuv yo''q); RP-22: yopilish payti moliya soati bo''yicha — 15.04 ertasi ertalab yopilgan, «o''sha kuni yopilgan» 3 / 4',
  (select string_agg(coalesce(zz.js(zz.kv('U_FM', d, null)) -> 'day' ->> 'status', left(zz.kv('U_FM', d, null), 80)), ',' order by d)
     from unnest(array['2027-04-08', '2027-04-09', '2027-04-12', '2027-04-13', '2027-04-14', '2027-04-15']) d)
  || ' | ' || (select (k ->> 'closed') || ':' || (k ->> 'onTime') from (select app.kassa_week_kpi('main', '2027-04-12', '2027-04-18') k) q),
  '^verified,verified,verified,verified,verified,verified \| 4:3$');
-- H1 (g7 tekshiruvchisi, s8 H2–H6): 16.04 U_KAS kassa egasi; 12:00 smenani U_KAS2 ga topshirdi — qurilmasi navbatidagi 20 000 (11:00 da olingan,
--   hali yuborilmagan) bilan; U_KAS2 qabul qildi va kunni O'Z qurilmasidan (navbatida bu yozuv yo'q — bo'sh ro'yxat) yopdi
select zz.clock('2027-04-16 10:00+05');
select left(zz.pay('U_KAS', 'man_h1_0001', 'T-9', 10000, 'cash', '', null, '{"fiscalNo":"F-H11"}'), 0);
select zz.clock('2027-04-16 12:00+05');
select zz.put('H1h', zz.kh('U_KAS', format('{"counted":%s,"expected":%s,"toUid":"U_KAS2","pendingRefs":[{"ref":"man_h1_0002","amount":20000}]}', zz.kbal() + 20000, zz.kbal())));
select zz.put('H1q', zz.as('U_KAS2', format('select public.kassa_handover_accept(%L)::text', zz.js(zz.get('H1h')) #>> '{handover,id}')));
-- yopish oynasi shu ma'lumotdan «Smena topshirishda e'lon qilingan, hali kelmagan» qatorini va farqni ko'rsatadi (fin-kassa.js handoverRefs)
select zz.put('H1o', (zz.js(zz.as('U_KAS2', $q$select public.kassa_state('main')::text$q$)) #> '{openDay,pendingOpen,refs}')::text);
select zz.clock('2027-04-16 18:00+05');
select zz.put('H1k', (zz.kbal() + 20000)::text);   -- kassadagi pul: hisobdagi + 11:00 da olingan, hali kelmagan 20 000 (17.04 da yangi pul yo'q)
select zz.put('H1c', zz.kc('U_KAS2', format('{"day":"2027-04-16","counted":%s,"expected":%s,"pendingRefs":[],"z":{"no":"Z-0416","cash":30000,"card":0}}', zz.get('H1k'), zz.kbal())));
select zz.chk('H1 g7v-3: smena topshirishda e''lon qilingan, hali kelmagan yozuv (ochiq kun holatida — oyna uchun) qabul qiluvchining yopishida o''zi hisobga olindi — farq 0 (avval soxta ortiqcha 20 000), kunda saqlandi (yopish yozuvi); kelguncha kun izohsiz tekshirilmaydi',
  (zz.js(zz.get('H1h')) ->> 'diff') || ':' || (zz.js(zz.get('H1q')) ->> 'diff') || ' | ' || zz.get('H1o')
  || ' | ' || (zz.js(zz.get('H1c')) ->> 'diff') || ':' || (zz.js(zz.get('H1c')) -> 'ignoredRefs')::text || ':' || (zz.js(zz.get('H1c')) ->> 'pending')
  || ' | ' || (select "pendingCount" || ':' || trim_scale("pendingSum") || ':' || "pendingRefs"::text from public.cash_days where day = '2027-04-16')
  || ' | ' || (select string_agg((r ->> 'ref') || '/' || (r ->> 'kind'), ',') from jsonb_array_elements(app.kassa_day_pending('cd_main_2027-04-16') -> 'refs') r)
  || ' | ' || (select count(*) from public.cash_docs where "businessDay" = '2027-04-16' and op in ('in_surplus', 'out_shortage'))
  || ' | ' || zz.kv('U_FM', '2027-04-16', null),
  '^0:0 \| \[\{"ref": "man_h1_0002", "kind": "handover", "amount": 20000\}\] \| 0:\[\]:20000 \| 1:20000:\[\{"ref": "man_h1_0002", "amount": 20000\}\] \| man_h1_0002/close \| 0 \| ERR 22023 \[kassa:pending_note\] .*1 ta yozuvning \(20000 so''m\).*$');
select zz.clock('2027-04-17 09:00+05');
select zz.put('H1f', zz.pay('U_KAS', 'man_h1_0002', 'T-9', 20000, 'cash', '', '2027-04-16 11:00+05', '{"fiscalNo":"F-H12"}'));
select zz.clock('2027-04-17 18:00+05');
select zz.put('H1d', zz.kc('U_KAS', format('{"day":"2027-04-17","counted":%s,"expected":%s,"z":{"no":"Z-0417","cash":0,"card":0}}', zz.get('H1k'), zz.kbal())));
select zz.chk('H1b g7v-3: yozuv 17.04 da «kech» keldi — 16.04 yozuvi bog''landi; 17.04 farqsiz yopildi (avval — soxta kamomad 20 000); 16.04 Z (10 000 + 20 000) mos, kun izohsiz tekshirildi',
  coalesce((zz.js(zz.get('H1f')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('H1f')) #>> '{kassa,late}'), zz.get('H1f'))
  || ' | ' || zz.kpend('2027-04-16') || ' | ' || (zz.js(zz.get('H1d')) ->> 'diff') || ':' || (select count(*) from public.cash_docs where "businessDay" = '2027-04-17' and op in ('in_surplus', 'out_shortage'))
  || ' | ' || zz.zst('2027-04-16') || ' / ' || zz.zst('2027-04-17')
  || ' | ' || coalesce(zz.js(zz.kv('U_FM', '2027-04-16', null)) -> 'day' ->> 'status', zz.kv('U_FM', '2027-04-16', null)),
  '^2027-04-17:true \| 0:0:0 \| 0:0 \| 30000:2:0:true / 0:0:0:true \| verified$');
-- H2/H3: 19.04 U_KAS2 kassa egasi; 12:00 smenani U_KAS ga ikki navbat yozuvi bilan topshirdi (15 000 va 5 000; kassadagi umumiy qurilma);
--   qabuldan keyin 5 000 lik yozuv o'tdi (shu kunga); U_KAS kunni yopdi — qurilma navbatidagi 15 000 lik yozuv ham e'lon qilindi, 5 000 lik
--   yozuv esa eskirgan ro'yxatda qolgan
select zz.clock('2027-04-19 10:00+05');
select left(zz.pay('U_KAS2', 'man_h2_0001', 'T-9', 10000, 'cash', '', null, '{"fiscalNo":"F-H21"}'), 0);
select zz.clock('2027-04-19 12:00+05');
select zz.put('H2h', zz.kh('U_KAS2', format('{"counted":%s,"expected":%s,"toUid":"U_KAS","pendingRefs":[{"ref":"man_h2_0002","amount":15000},{"ref":"man_h3_0001","amount":5000}]}', zz.kbal() + 20000, zz.kbal())));
select zz.put('H2q', zz.as('U_KAS', format('select public.kassa_handover_accept(%L)::text', zz.js(zz.get('H2h')) #>> '{handover,id}')));
select zz.clock('2027-04-19 13:00+05');
select zz.put('H3f', zz.pay('U_KAS2', 'man_h3_0001', 'T-9', 5000, 'cash', '', '2027-04-19 11:30+05', '{"fiscalNo":"F-H31"}'));
select zz.clock('2027-04-19 18:00+05');
select zz.put('H2c', zz.kc('U_KAS', format('{"day":"2027-04-19","counted":%s,"expected":%s,"pendingRefs":[{"ref":"man_h2_0002","amount":15000},{"ref":"man_h3_0001","amount":5000}],"z":{"no":"Z-0419","cash":30000,"card":0}}',
                                         zz.kbal() + 15000, zz.kbal())));
select zz.chk('H2 g7v-3: qabul qiluvchining qurilmasi ham o''sha yozuvni e''lon qildi — bir marta ayirildi (farq 0; kunda bitta yozuv, 15 000)',
  (zz.js(zz.get('H2h')) ->> 'diff') || ':' || (zz.js(zz.get('H2q')) ->> 'diff') || ' | ' || (zz.js(zz.get('H2c')) ->> 'diff') || ':' || (zz.js(zz.get('H2c')) ->> 'pending')
  || ' | ' || (select "pendingCount" || ':' || trim_scale("pendingSum") || ':' || "pendingRefs"::text from public.cash_days where day = '2027-04-19'),
  '^0:0 \| 0:15000 \| 1:15000:\[\{"ref": "man_h2_0002", "amount": 15000\}\]$');
select zz.chk('H3 g7v-3: yopishdan oldin o''tib ketgan yozuv (shu kunga, «kech» emas) ayirilmadi — ignoredRefs da; ikkinchi marta hisoblanmadi',
  coalesce((zz.js(zz.get('H3f')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('H3f')) #>> '{kassa,late}'), zz.get('H3f'))
  || ' | ' || (zz.js(zz.get('H2c')) -> 'ignoredRefs')::text || ' | ' || (select count(*) from public.cash_docs where "businessDay" = '2027-04-19' and op in ('in_surplus', 'out_shortage')),
  '^2027-04-19:false \| \["man_h3_0001"\] \| 0$');
-- H4: 20.04 — 19.04 dagi 15 000 lik yozuv ertalab «kech» keldi (U_KAS2 kassa egasi); 11:00 U_KAS2 smenani U_KAS ga 12 000 lik navbat
--   yozuvi bilan topshirdi; 14:00 U_KAS smenani U_KAS2 ga qaytarib topshirdi — o'z qurilmasidan (navbatida bu yozuv yo'q)
select zz.clock('2027-04-20 09:00+05');
select zz.put('H4p', zz.pay('U_KAS2', 'man_h2_0002', 'T-9', 15000, 'cash', '', '2027-04-19 11:00+05', '{"fiscalNo":"F-H22"}'));
select zz.clock('2027-04-20 11:00+05');
select zz.put('H4h', zz.kh('U_KAS2', format('{"counted":%s,"expected":%s,"toUid":"U_KAS","pendingRefs":[{"ref":"man_h4_0001","amount":12000}]}', zz.kbal() + 12000, zz.kbal())));
select left(zz.as('U_KAS', format('select public.kassa_handover_accept(%L)::text', zz.js(zz.get('H4h')) #>> '{handover,id}')), 0);
select zz.clock('2027-04-20 14:00+05');
select zz.put('H4k', (zz.kbal() + 12000)::text);   -- kassadagi pul: hisobdagi + 10:30 da olingan, hali kelmagan 12 000 (keyin yangi pul yo'q)
select zz.put('H4g', zz.kh('U_KAS', format('{"counted":%s,"expected":%s,"toUid":"U_KAS2","pendingRefs":[]}', zz.get('H4k'), zz.kbal())));
select zz.put('H4r', zz.kh('U_KAS', format('{"counted":%s,"expected":%s,"toUid":"U_KAS2","pendingRefs":[]}', zz.get('H4k'), zz.kbal())));
select zz.put('H4q', zz.as('U_KAS2', format('select public.kassa_handover_accept(%L)::text', zz.js(zz.get('H4g')) #>> '{handover,id}')));
select zz.clock('2027-04-20 15:00+05');
select zz.put('H4f', zz.pay('U_KAS2', 'man_h4_0001', 'T-9', 12000, 'cash', '', '2027-04-20 10:30+05', '{"fiscalNo":"F-H41"}'));
select zz.clock('2027-04-20 18:00+05');
select zz.put('H4c', zz.kc('U_KAS2', format('{"day":"2027-04-20","counted":%s,"expected":%s,"z":{"no":"Z-0420","cash":12000,"card":0}}', zz.get('H4k'), zz.kbal())));
select zz.chk('H4 g7v-3: ikkinchi smena topshirishda birinchisida e''lon qilingan, hali kelmagan yozuv o''zi qo''shildi — topshirishda saqlandi (takror yuborish — o''sha), qabul sanashiga o''tdi; farq 0 (avval qabulda soxta ortiqcha 12 000)',
  (zz.js(zz.get('H4g')) ->> 'diff') || ':' || (zz.js(zz.get('H4g')) #>> '{handover,pendingSum}') || ':' || (zz.js(zz.get('H4g')) #> '{handover,pendingRefs}')::text
  || ' | ' || (zz.js(zz.get('H4r')) ->> 'dup')
  || ' | ' || (zz.js(zz.get('H4q')) ->> 'diff') || ':' || (zz.js(zz.get('H4q')) #>> '{count,pendingSum}') || ':' || (zz.js(zz.get('H4q')) #> '{count,pendingRefs}')::text
  || ' | ' || (select "pendingRefs"::text from public.cash_handovers where id = zz.js(zz.get('H4g')) #>> '{handover,id}')
  || ' | ' || (select count(*) from public.cash_docs where "businessDay" = '2027-04-20' and op in ('in_surplus', 'out_shortage')),
  '^0:12000:\[\{"ref": "man_h4_0001", "amount": 12000\}\] \| true \| 0:12000:\[\{"ref": "man_h4_0001", "amount": 12000\}\] \| \[\{"ref": "man_h4_0001", "amount": 12000\}\] \| 0$');
select zz.chk('H4b yozuv o''sha kuni keldi (kech emas) — bog''landi; 20.04 farqsiz yopildi; 19.04 Z (pul olingan, yopilishidan oldingi chek 15 000 bilan) va 20.04 Z mos',
  coalesce((zz.js(zz.get('H4p')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('H4p')) #>> '{kassa,late}'), zz.get('H4p'))
  || ' | ' || coalesce((zz.js(zz.get('H4f')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('H4f')) #>> '{kassa,late}'), zz.get('H4f'))
  || ' | ' || (zz.js(zz.get('H4c')) ->> 'diff') || ':' || zz.kpend('2027-04-19') || ':' || zz.kpend('2027-04-20')
  || ' | ' || zz.zst('2027-04-19') || ' / ' || zz.zst('2027-04-20'),
  '^2027-04-20:true \| 2027-04-20:false \| 0:0:0:0:0:0:0 \| 30000:3:0:true / 12000:1:0:true$');
-- GV (g7b-v1): server qo'shadigan smena yozuvlari sanalgan puldan oshmaydi — avval sanalgan pul ulardan kam bo'lsa, kun yopilmas va smena
--   topshirilmasdi (kassa:count; yopuvchi server qo'shgan yozuvni olib tashlay olmaydi — Direktor ham, kassa to'xtatilmaydi, ertasi har
--   hujjat kassa:prev_open). 21.04: U_KAS kassa egasi; 10:30 da qurilmasi (oflayn) 2 000 000 oldi (fiskal chek F-GV12); 11:00 smenani U_KAS2
--   ga shu navbat yozuvi bilan topshirdi, U_KAS2 qabul qildi. 11:30 U_KAS ning noutbuki ishdan chiqdi (navbat yo'qoldi) — to'lov yangi
--   kalit bilan qayta kiritildi (eski kalit endi kelmaydi). 13:00 U_KAS2 ning qurilmasi (internet uzilgan) 40 000 oldi. 16:00 ortiqcha
--   naqd bankka topshirildi (hisobda 100 000 qoldi); 17:00 U_KAS2 smenani U_KAS ga qaytardi (navbatidagi 40 000 bilan), 18:00 U_KAS kunni
--   yopdi (yangi qurilmasidan — navbati bo'sh). Kassada: hisobdagi 100 000 + hali kelmagan 40 000 = 140 000.
set local session_replication_role = replica;
insert into public.fin_counterparties (id, kind, name) values ('cp_bank','bank','Sinov Bank') on conflict (id) do nothing;
set local session_replication_role = origin;
select zz.clock('2027-04-21 09:00+05');
select left(zz.pay('U_KAS', 'man_gv1_0001', 'T-9', 300000, 'cash', '', null, '{"fiscalNo":"F-GV11"}'), 0);
select zz.clock('2027-04-21 11:00+05');
select zz.put('GV1h', zz.kh('U_KAS', format('{"counted":%s,"expected":%s,"toUid":"U_KAS2","pendingRefs":[{"ref":"man_gv1_0002","amount":2000000}]}', zz.kbal() + 2000000, zz.kbal())));
select zz.put('GV1a', zz.as('U_KAS2', format('select public.kassa_handover_accept(%L)::text', zz.js(zz.get('GV1h')) #>> '{handover,id}')));
select zz.clock('2027-04-21 11:30+05');
select left(zz.pay('U_KAS2', 'man_gv1_0004', 'T-9', 2000000, 'cash', '', null, '{"fiscalNo":"F-GV12"}'), 0);   -- o'sha to'lov, yangi kalit bilan
select zz.clock('2027-04-21 16:00+05');
select zz.put('GV1b', zz.as('U_KAS2', format('select public.kassa_payout_request(%L::jsonb)::text',
  format('{"op":"out_bank","amount":%s,"partyType":"bank","partyId":"cp_bank","basis":"Inkassatsiya, 21.04.2027","clientRef":"gv1-bank-0001"}', zz.kbal() - 100000))));
select left(zz.as('U_FM', format('select public.kassa_doc_approve(%L)::text', zz.js(zz.get('GV1b')) ->> 'id')), 0);
select left(zz.as('U_DIR', format('select public.kassa_doc_approve(%L)::text', zz.js(zz.get('GV1b')) ->> 'id')), 0);
select zz.put('GV1p', zz.as('U_KAS2', format('select public.kassa_doc_pay(%L)::text', zz.js(zz.get('GV1b')) ->> 'id')));
select zz.clock('2027-04-21 17:00+05');
select zz.put('GV1g', zz.kh('U_KAS2', format('{"counted":%s,"expected":%s,"toUid":"U_KAS","pendingRefs":[{"ref":"man_gv1_0003","amount":40000}]}', zz.kbal() + 40000, zz.kbal())));
select zz.put('GV1q', zz.as('U_KAS', format('select public.kassa_handover_accept(%L)::text', zz.js(zz.get('GV1g')) #>> '{handover,id}')));
select zz.clock('2027-04-21 18:00+05');
select zz.put('GV1o', (zz.js(zz.as('U_KAS', $q$select public.kassa_state('main')::text$q$)) #> '{openDay,pendingOpen}')::text);   -- yopish oynasi shundan
select zz.put('GV1c', zz.kc('U_KAS', format('{"day":"2027-04-21","counted":%s,"expected":%s,"pendingRefs":[],"z":{"no":"Z-0421","cash":2340000,"card":0}}', zz.kbal() + 40000, zz.kbal())));
select zz.chk('GV1 g7b-v1: eski kalit (to''lov yangi kalit bilan qayta kiritilgan, pul bankka topshirilgan) sanalgan pulga sig''maydi — smena topshirildi va kun yopildi (avval kassa:count), farq 0; sig''gani (40 000) ayirildi va saqlandi, eski kalit saqlanmadi',
  (zz.js(zz.get('GV1h')) ->> 'diff') || ':' || (zz.js(zz.get('GV1a')) ->> 'diff') || ':' || coalesce(zz.js(zz.get('GV1p')) ->> 'status', zz.get('GV1p'))
  || ' | ' || coalesce((zz.js(zz.get('GV1g')) ->> 'diff') || ':' || (zz.js(zz.get('GV1g')) #>> '{handover,pendingSum}') || ':' || (zz.js(zz.get('GV1g')) #> '{handover,pendingRefs}')::text, zz.get('GV1g'))
  || ' | ' || coalesce((zz.js(zz.get('GV1q')) ->> 'diff'), zz.get('GV1q'))
  || ' | ' || (zz.js(zz.get('GV1o')) ->> 'n') || ':' || (zz.js(zz.get('GV1o')) ->> 'sum')
  || ' | ' || coalesce((zz.js(zz.get('GV1c')) ->> 'diff') || ':' || (zz.js(zz.get('GV1c')) ->> 'pending') || ':' || (zz.js(zz.get('GV1c')) -> 'ignoredRefs')::text, zz.get('GV1c'))
  || ' | ' || (select status || ':' || trim_scale(closing) || ':' || "pendingCount" || ':' || trim_scale("pendingSum") || ':' || "pendingRefs"::text from public.cash_days where day = '2027-04-21')
  || ' | ' || (select count(*) from public.cash_docs where "businessDay" = '2027-04-21' and op in ('in_surplus', 'out_shortage')),
  '^0:0:posted \| 0:40000:\[\{"ref": "man_gv1_0003", "amount": 40000\}\] \| 0 \| 2:2040000 \| 0:40000:\[\] \| closed:100000:1:40000:\[\{"ref": "man_gv1_0003", "amount": 40000\}\] \| 0$');
select zz.chk('GV1b eski kalit ko''rinib turadi: kunning bog''lanmagan yozuvlari — eski kalit (smena topshirish yozuvi) va 40 000 (yopish yozuvi); kun izohsiz tekshirilmaydi (oldingi kunlar tekshirildi)',
  (select string_agg((r ->> 'ref') || '/' || (r ->> 'kind') || '/' || (r ->> 'amount'), ',' order by r ->> 'ref') from jsonb_array_elements(app.kassa_day_pending('cd_main_2027-04-21') -> 'refs') r)
  || ' | ' || (select string_agg(coalesce(zz.js(zz.kv('U_FM', d, null)) -> 'day' ->> 'status', left(zz.kv('U_FM', d, null), 60)), ',' order by d)
                 from unnest(array['2027-04-17', '2027-04-19', '2027-04-20']) d)
  || ' | ' || zz.kv('U_FM', '2027-04-21', null),
  '^man_gv1_0002/handover/2000000,man_gv1_0003/close/40000 \| verified,verified,verified \| ERR 22023 \[kassa:pending_note\] Kun hali o''tkazilmagan yozuvlar bilan yopilgan: qurilma navbatidagi 2 ta yozuvning \(2040000 so''m\) kirim orderi hali kelmagan\..*$');
-- 22.04: U_KAS2 ning qurilmasi internetga ulandi — 40 000 «kech» o'tdi; kun kassadagi o'sha pul bilan yopildi
select zz.clock('2027-04-22 09:00+05');
select zz.put('GV2f', zz.pay('U_KAS2', 'man_gv1_0003', 'T-9', 40000, 'cash', '', '2027-04-21 13:00+05', '{"fiscalNo":"F-GV13"}'));
select zz.clock('2027-04-22 18:00+05');
select zz.put('GV2c', zz.kc('U_KAS2', format('{"day":"2027-04-22","counted":%s,"expected":%s,"z":{"no":"Z-0422","cash":0,"card":0}}', zz.kbal(), zz.kbal())));
select zz.chk('GV2 40 000 bog''landi (eski kalit qoladi); 22.04 farqsiz (soxta juftlik yo''q); 21.04 Z (300 000 + 2 000 000 + kech 40 000) mos; 21.04 izoh bilan tekshirildi',
  coalesce((zz.js(zz.get('GV2f')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('GV2f')) #>> '{kassa,late}'), zz.get('GV2f'))
  || ' | ' || zz.kpend('2027-04-21') || ' | ' || coalesce(zz.js(zz.get('GV2c')) ->> 'diff', zz.get('GV2c'))
  || ':' || (select count(*) from public.cash_docs where "businessDay" = '2027-04-22' and op in ('in_surplus', 'out_shortage'))
  || ' | ' || zz.zst('2027-04-21') || ' / ' || zz.zst('2027-04-22')
  || ' | ' || coalesce(zz.js(zz.kv('U_FM', '2027-04-21', 'Eski navbat kaliti: to''lov 21.04 da yangi kalit bilan qayta kiritilgan (F-GV12)')) -> 'day' ->> 'status', 'xato'),
  '^2027-04-22:true \| 1:2000000:0 \| 0:0 \| 2340000:3:0:true / 0:0:0:true \| verified$');
-- GV3: eski kalit sanalgan pulga SIG'SA (pul bankka topshirilmagan) — hujjatlarda aytilgan juftlik: yopishda kamomad, keyingi sanashda
--   xuddi shuncha ortiqcha (kamomad haqiqiy emas — Direktor «Hisobdan chiqarish» bilan yopadi; ishga-tushirish §8)
select zz.clock('2027-04-23 09:00+05');
select left(zz.pay('U_KAS', 'man_gv3_0001', 'T-9', 10000, 'cash', '', null, '{"fiscalNo":"F-GV31"}'), 0);
select zz.clock('2027-04-23 11:00+05');
select left(zz.as('U_KAS2', format('select public.kassa_handover_accept(%L)::text',
  zz.js(zz.kh('U_KAS', format('{"counted":%s,"expected":%s,"toUid":"U_KAS2","pendingRefs":[{"ref":"man_gv3_0002","amount":25000}]}', zz.kbal() + 25000, zz.kbal()))) #>> '{handover,id}')), 0);
select zz.clock('2027-04-23 11:30+05');
select left(zz.pay('U_KAS2', 'man_gv3_0003', 'T-9', 25000, 'cash', '', null, '{"fiscalNo":"F-GV32"}'), 0);   -- o'sha to'lov, yangi kalit bilan
select zz.clock('2027-04-23 18:00+05');
select zz.put('GV3k', zz.kbal()::text);   -- kassadagi pul = hisobdagi (25 000 qayta kiritilgan to'lovda)
select zz.put('GV3c', zz.kc('U_KAS2', format('{"day":"2027-04-23","counted":%s,"expected":%s,"z":{"no":"Z-0423","cash":35000,"card":0}}', zz.get('GV3k'), zz.kbal())));
select zz.clock('2027-04-24 10:00+05');
select left(zz.pay('U_KAS2', 'man_gv3_0004', 'T-9', 5000, 'cash', '', null, '{"fiscalNo":"F-GV33"}'), 0);
select zz.clock('2027-04-24 18:00+05');
select zz.put('GV3d', zz.kc('U_KAS2', format('{"day":"2027-04-24","counted":%s,"expected":%s,"z":{"no":"Z-0424","cash":5000,"card":0}}', zz.get('GV3k')::numeric + 5000, zz.kbal())));
select zz.chk('GV3 eski kalit sig''di — 23.04 kamomad 25 000 (kamomad hujjati suratida eski kalit), 24.04 xuddi shuncha ortiqcha',
  coalesce((zz.js(zz.get('GV3c')) ->> 'diff') || ':' || (zz.js(zz.get('GV3c')) #> '{diffDoc,sourceSnapshot,pendingRefs}')::text, zz.get('GV3c'))
  || ' | ' || coalesce(zz.js(zz.get('GV3d')) ->> 'diff', zz.get('GV3d')) || ':' || zz.jdp(zz.get('GV3d'), '{diffDoc,op}', '-'),
  '^-25000:\[\{"ref": "man_gv3_0002", "amount": 25000\}\] \| 25000:in_surplus$');
-- GV4 (g7b tekshiruvchisi): «Қ» blankalari bilan yopishda server qo'shadigan smena yozuvlari uchun joy «Қ» summasini ham hisobga oladi.
--   26.04: U_KAS2 kassa egasi; 11:00 smenani U_KAS ga qurilma navbatidagi 50 000 bilan topshirdi, U_KAS qabul qildi; keyin server ishlamadi —
--   «Қ» blankasi (700 000) yozildi; kechqurun kassada 730 000 (katta kamomad). Joy = 730 000 − 700 000 = 30 000 < 50 000 — yozuv qo'shilmaydi.
--   «Қ» hisobga olinmasa — qo'shilardi: hali o'tkazilmagan 750 000 > sanalgan 730 000 — kun yopilmasdi (kassa:count).
select zz.clock('2027-04-26 10:00+05');
select left(zz.pay('U_KAS2', 'man_gv4_0001', 'T-9', 10000, 'cash', '', null, '{"fiscalNo":"F-GV41"}'), 0);
select zz.clock('2027-04-26 11:00+05');
select left(zz.as('U_KAS', format('select public.kassa_handover_accept(%L)::text',
  zz.js(zz.kh('U_KAS2', format('{"counted":%s,"expected":%s,"toUid":"U_KAS","pendingRefs":[{"ref":"man_gv4_0002","amount":50000}]}', zz.kbal() + 50000, zz.kbal()))) #>> '{handover,id}')), 0);
select zz.clock('2027-04-26 18:00+05');
select zz.put('GV4b', zz.kbal()::text);
select zz.put('GV4c', zz.kc('U_KAS', format('{"day":"2027-04-26","counted":730000,"expected":%s,"pendingRefs":[],"paper":{"count":1,"sum":700000,"nos":"Қ-0031"}}', zz.get('GV4b'))));
select zz.chk('GV4 g7b tekshiruvchisi: «Қ» blankalari va katta kamomad bilan yopish — smena yozuvi (50 000) sanalgan pulga sig''madi (joy = sanalgan − «Қ»), kun yopildi (kassa:count emas), hali o''tkazilmagan = faqat «Қ»; yozuv smena topshirish yozuvi bo''lib bog''lanmagan qoldi',
  coalesce(((zz.js(zz.get('GV4c')) ->> 'diff')::numeric = 30000 - zz.get('GV4b')::numeric)::text || ':' || (zz.js(zz.get('GV4c')) ->> 'pending'), left(zz.get('GV4c'), 200))
  || ' | ' || (select status || ':' || "pendingCount" || ':' || trim_scale("pendingSum") || ':' || "pendingRefs"::text || ':' || "paperCount" from public.cash_days where day = '2027-04-26')
  || ' | ' || (select string_agg((r ->> 'ref') || '/' || (r ->> 'kind') || '/' || (r ->> 'amount'), ',') from jsonb_array_elements(app.kassa_day_pending('cd_main_2027-04-26') -> 'refs') r),
  '^true:700000 \| closed:1:700000:\[\]:1 \| man_gv4_0002/handover/50000$');
-- Z5 (g7b tekshiruvchisi): kech orderning Z kuni pul olingan kundan oldin emas. 27.04 kassa kuni ertasi ertalab (28.04 08:30) yopildi (NKM
--   smenasi — Z-hisobot — kechqurun yopilgan); qurilma 28.04 08:00 da (oflayn) 7 000 oldi, yozuv 28.04 yopilgandan keyin (29.04) «kech» o'tdi.
--   Z kuni — 28.04: shu chek 28.04 da o'tganda (kech emas) ham o'sha kun Z ida kutilardi — Z kuni qurilma qachon internetga ulanganiga
--   bog'liq emas. Chegarasiz — 27.04 bo'lardi (pul olingandan keyin yopilgan birinchi kun).
select zz.clock('2027-04-27 10:00+05');
select left(zz.pay('U_KAS', 'man_z5_0001', 'T-9', 10000, 'cash', '', null, '{"fiscalNo":"F-Z51"}'), 0);
select zz.clock('2027-04-28 08:30+05');
select zz.put('Z5c', zz.kc('U_KAS', format('{"day":"2027-04-27","counted":%s,"expected":%s,"pendingRefs":[{"ref":"man_z5_0002","amount":7000}],"z":{"no":"Z-0427","cash":10000,"card":0}}', zz.kbal() + 7000, zz.kbal())));
select zz.clock('2027-04-28 10:00+05');
select left(zz.pay('U_KAS', 'man_z5_0003', 'T-9', 3000, 'cash', '', null, '{"fiscalNo":"F-Z53"}'), 0);
select zz.clock('2027-04-28 18:00+05');
select zz.put('Z5d', zz.kc('U_KAS', format('{"day":"2027-04-28","counted":%s,"expected":%s,"pendingRefs":[{"ref":"man_z5_0002","amount":7000}],"z":{"no":"Z-0428","cash":10000,"card":0}}', zz.kbal() + 7000, zz.kbal())));
select zz.clock('2027-04-29 09:00+05');
select zz.put('Z5a', zz.pay('U_KAS', 'man_z5_0002', 'T-9', 7000, 'cash', '', '2027-04-28 08:00+05', '{"fiscalNo":"F-Z52"}'));
select zz.chk('Z5 g7b tekshiruvchisi: kun ertasi ertalab yopilgan, pul o''sha ertalab yopilishdan oldin olingan — kech orderning Z kuni pul olingan kun (28.04), oldingi kun emas: 27.04 Z (10 000) va 28.04 Z (3 000 + kech 7 000) mos; ikkala kun yozuvi bog''landi',
  coalesce((zz.js(zz.get('Z5c')) ->> 'diff') || ':' || (zz.js(zz.get('Z5d')) ->> 'diff'), left(coalesce(zz.get('Z5c'), '') || ' / ' || coalesce(zz.get('Z5d'), ''), 300))
  || ' | ' || coalesce((zz.js(zz.get('Z5a')) #>> '{kassa,day}') || ':' || (zz.js(zz.get('Z5a')) #>> '{kassa,late}'), zz.get('Z5a'))
  || ' | ' || app.kassa_z_day('main', '2027-04-29', true, '2027-04-28 08:00+05')::text
  || ' | ' || zz.zst('2027-04-27') || ' / ' || zz.zst('2027-04-28') || ' | ' || zz.kpend('2027-04-27') || ':' || zz.kpend('2027-04-28'),
  '^0:0 \| 2027-04-29:true \| 2027-04-28 \| 10000:1:0:true / 10000:2:0:true \| 0:0:0:0:0:0$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
