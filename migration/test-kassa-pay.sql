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
select zz.clock('2027-01-04 10:00+05');

-- ---------- Kassa ishga tushguncha: avvalgidek ----------
select zz.put('J1', zz.pay('U_KAS', 'man_j1_0001', 'T-1', 100000, 'cash', 'Sinov Ota', null, null));
select zz.chk('J1 kassa ishga tushmagan: naqd to''lov avvalgidek, KO-1 siz', zz.get('J1'), '"ok": true.*"kassa": null|"kassa": null.*"ok": true');
select zz.chk('J1b to''lov qo''llandi, kassa hujjati yo''q',
  (select status || ':' || coalesce("cashDocId", '-') from public.payments where id = 'man_j1_0001') || ':' || (select count(*) from public.cash_docs), '^applied:-:0$');

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

-- ---------- Kun, moslik ----------
select zz.chk('J16 kassa qoldig''i = naqd to''lovlar yig''indisi (ishga tushgandan beri)',
  zz.as('U_KAS', $q$select (s ->> 'balance') from public.kassa_state('main') s$q$) || '/' ||
  (select trim_scale(sum(amount))::text from public.payments where "cashDocId" is not null and status = 'applied'), '^3090000/3090000$');
select zz.chk('J17 P1: ishga tushgandan keyingi har naqd to''lovda order bor (yetim yo''q)',
  (select count(*)::text from public.payments p where p.provider = 'cash' and p.status = 'applied' and p."cashDocId" is null and p.id <> 'man_j1_0001'), '^0$');
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

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
