-- =====================================================================
-- test-kassa.sql — moliya ish rejasi 1a-bosqichi (fin-core.sql, fin-seed.sql, kassa.sql, kassa-docs.sql, kassa-day.sql) sinovi:
--   (A) ma'lumotnomalar va xavfsizlik (RLS, to'g'ridan-to'g'ri yozish rad, sozlamalar faqat Direktor);
--   (B) boshlang'ich qoldiq; (C) KO-1 kirim (idempotentlik, fiskal chek, tomon, statiya, Direktor ruxsati);
--   (D) KO-2 chiqim: so'rov → 2-ro'yxat tasdig'i (≠ so'rovchi) → T1 dan katta bo'lsa Direktor → to'lash; manfiy qoldiq rad;
--   (E) shu kunda bekor qilish; (F) bazadagi himoya (o'zgarmaslik, I1–I6) — RPC'ni chetlab o'tib ham buzib bo'lmaydi;
--   (G) kun sikli: sanab yopish, farq hujjati (kamomad / ortiqcha), tekshirish (≠ yopuvchi / o'tkazuvchi), qayta ochish,
--       kamomad qarori, oflayn va kech kiritish, smena topshirish, yil chegarasi, raqam bo'shlig'i va xesh nazorati;
--   (H) o'qish funksiyalari; (I) qarordan keyin qayta ochish, band kalitlar; (J) chop etish jurnali («НУСХА»), varaq qatorlari.
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub). Sana — test soati (app.fin_clock) bilan boshqariladi.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) then
    raise exception 'test-kassa.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
-- Haqiqiy rol bilan bajarish; xato bo'lsa: 'ERR <sqlstate> [<hint>] <xabar>'
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
-- Tizim (postgres) nomidan bajarish — trigger himoyasini sinash uchun.
create or replace function zz.try(p_q text) returns text language plpgsql as $$
declare v_hint text;
begin
  execute p_q; return 'OK';
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  return 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
create table if not exists zz.v (k text primary key, v text);
truncate zz.res; truncate zz.v;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- Natijani kalit bilan saqlab qo'yish (keyingi qadamlar hujjat id'sini shundan oladi).
create or replace function zz.put(p_k text, p_v text) returns text language plpgsql as $$
begin insert into zz.v (k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; return p_v; end $$;
create or replace function zz.id(p_k text) returns text language sql as $$ select (v::jsonb ->> 'id') from zz.v where k = p_k $$;
create or replace function zz.get(p_k text) returns text language sql as $$ select v from zz.v where k = p_k $$;
-- JSON javobdan maydon; javob xato matni bo'lsa — matnning o'zi (yangi qoida buzilsa tekshiruv ERR bilan to'xtamaydi, FAIL bo'lib ko'rinadi)
create or replace function zz.f(p text, variadic p_path text[]) returns text language sql as $$
  select case when p ~ '^\s*\{' then (p::jsonb #>> p_path) else left(coalesce(p, '<null>'), 300) end $$;
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
create or replace function zz.rcpt(p_uid text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_receipt(%L::jsonb)::text', p_json)) $$;
create or replace function zz.preq(p_uid text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_payout_request(%L::jsonb)::text', p_json)) $$;
create or replace function zz.appr(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_approve(%L)::text', p_id)) $$;
create or replace function zz.pay(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_pay(%L)::text', p_id)) $$;
create or replace function zz.void(p_uid text, p_id text, p_reason text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_void(%L, %L)::text', p_id, p_reason)) $$;
create or replace function zz.close(p_uid text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_day_close(%L::jsonb)::text', p_json)) $$;
create or replace function zz.bal() returns text language sql as $$
  select trim_scale(app.kassa_day_balance((select id from public.cash_days where desk = 'main' and status = 'open')))::text $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles", "staffRefType", "staffRefId") values
  ('U_DIR','d@x','director','active','[]',null,null), ('U_FM','f@x','finance_mgr','active','[]',null,null),
  ('U_KAS','k@x','kassir','active','[]','staff','st1'), ('U_KAS2','k2@x','kassir','active','[]','teacher','tch1'),
  ('U_ACC','a@x','accountant','active','[]',null,null), ('U_TRE','g@x','treasurer','active','[]',null,null),
  ('U_ZAV','z@x','zavuch','active','[]',null,null), ('U_TCH','t@x','teacher','active','[]',null,null),
  ('U_HRK','h@x','hr','active','["kassir"]',null,null), ('U_BLK','b@x','finance_mgr','blocked','["kassir"]',null,null)
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]');
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','[]');
insert into public.staff (id, "staffId", name, position) values ('st1','IQX-T1','Sinov Xodim','Kassir');
-- kassadan oldingi (usulsiz = naqd) avans: C11 «Xodim qaytargan pul» (OP-08) shu oy avans qoldig'idan qaytariladi (acc-1)
insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date) values
  ('adv_old_st1', 'IQX-T1', 'staff:st1', 'Sinov Xodim', 50000, '2027-01', '2027-01-03');
set local session_replication_role = origin;
select zz.clock('2027-01-04 10:00+05');

-- ---------- (A) ma'lumotnomalar va xavfsizlik ----------
select zz.chk('A1 anon kassa hujjatlarini o''qiy olmaydi', zz.as(null, 'select count(*)::text from public.cash_docs'), '^ERR 42501');
select zz.chk('A2 anon hisobvaraqlar rejasini o''qiy olmaydi', zz.as(null, 'select count(*)::text from public.gl_accounts'), '^ERR 42501');
select zz.chk('A3 o''qituvchi statiyalarni ko''rmaydi (RLS)', zz.as('U_TCH', 'select count(*)::text from public.fin_articles'), '^0$');
select zz.chk('A4 kassir 75 statiyani ko''radi', zz.as('U_KAS', 'select count(*)::text from public.fin_articles'), '^75$');
select zz.chk('A5 buxgalter hisobvaraqlarni ko''radi', zz.as('U_ACC', 'select (count(*) > 80)::text from public.gl_accounts'), '^true$');
select zz.chk('A6 statiyalar: IN 7, EX 44, OP 24',
  (select string_agg(kind || '=' || n, ',' order by kind) from (select kind, count(*) n from public.fin_articles group by kind) x), '^EX=44,IN=7,OP=24$');
select zz.chk('A7 kassadan xarajat qilib bo''lmaydigan statiyalar',
  (select string_agg(id, ',' order by id) from public.fin_articles where kind = 'EX' and not "cashOutAllowed"),
  '^EX-01,EX-02,EX-03,EX-04,EX-05,EX-06,EX-36,EX-40,EX-41,EX-43,EX-44,EX-45,EX-46,EX-47$');
select zz.chk('A8 kassir kassa hujjatini to''g''ridan-to''g''ri yoza olmaydi',
  zz.as('U_KAS', $q$insert into public.cash_docs (id, desk, form, op, status, amount, "clientRef") values ('x','main','KO1','in_bank','draft',1,'xxxxxx') returning id$q$), '^ERR 42501');
select zz.chk('A9 Direktor ham jadvalga to''g''ridan-to''g''ri yoza olmaydi',
  zz.as('U_DIR', $q$update public.fin_org set t1 = 1 where id = 'main' returning id$q$), '^ERR 42501');
select zz.chk('A10 tizim (bayroqsiz) ham hujjat yoza olmaydi — trigger',
  zz.try($q$insert into public.cash_docs (id, desk, form, op, status, amount, "clientRef") values ('x','main','KO1','in_bank','draft',1,'xxxxxx')$q$), '^ERR 42501 \[kassa:rpc_only\]');
select zz.chk('A11 sozlamalar: kassir o''zgartira olmaydi', zz.as('U_KAS', $q$select public.fin_org_set('{"t1":1}')::text$q$), '^ERR 42501');
select zz.chk('A12 sozlamalar: Moliya menejeri T1 ni o''zgartira olmaydi', zz.as('U_FM', $q$select public.fin_org_set('{"t1":1}')::text$q$), '^ERR 42501');
select zz.chk('A13 sozlamalar: Direktor T1 = 500 000, L1 = 200 000',
  zz.as('U_DIR', $q$select public.fin_org_set('{"t1":500000,"l1":200000,"nameUz":"Sinov maktabi","orgCashMax":1000000000}')::text$q$), '"t1": 500000.*"l1": 200000|"l1": 200000.*"t1": 500000');
select zz.chk('A14 sozlamalar: noma''lum maydon rad', zz.as('U_DIR', $q$select public.fin_org_set('{"hack":1}')::text$q$), '^ERR 22023');
select zz.chk('A15 sozlamalar: NaN rad', zz.as('U_DIR', $q$select public.fin_org_set('{"t1":"NaN"}')::text$q$), '^ERR 22023');
select zz.put('cp_sup', zz.as('U_KAS', $q$select public.fin_counterparty_save(null, 'supplier', 'Sinov Yetkazuvchi MChJ')::text$q$));
select zz.put('cp_bank', zz.as('U_FM', $q$select public.fin_counterparty_save(null, 'bank', 'Sinov Bank')::text$q$));
select zz.put('cp_fnd', zz.as('U_DIR', $q$select public.fin_counterparty_save(null, 'founder', 'Sinov Ta''sischi')::text$q$));
select zz.chk('A16 kontragent: kassir qo''sha oladi', (select v from zz.v where k = 'cp_sup'), '"kind": "supplier"');
select zz.chk('A17 kontragent: kassir mavjudini o''zgartira olmaydi',
  zz.as('U_KAS', format('select public.fin_counterparty_save(%L, %L, %L)::text', zz.id('cp_sup'), 'supplier', 'Boshqa nom')), '^ERR 42501');
select zz.chk('A18 kontragent: o''qituvchi qo''sha olmaydi', zz.as('U_TCH', $q$select public.fin_counterparty_save(null, 'supplier', 'Xato')::text$q$), '^ERR 42501');
select zz.chk('A19 imzo ro''yxati: faqat Direktor', zz.as('U_FM', $q$select public.fin_signatory_save(null, 2, null, 'Bosh buxgalter', 'Sinov B')::text$q$), '^ERR 42501');
select zz.chk('A20 imzo ro''yxati: Direktor qo''shadi', zz.as('U_DIR', $q$select public.fin_signatory_save(null, 2, 'U_FM', 'Bosh buxgalter', 'Sinov B')::text$q$), '"list": 2');
select zz.chk('A21 o''qituvchi kassa holatini ko''ra olmaydi', zz.as('U_TCH', $q$select public.kassa_state('main')::text$q$), '^ERR 42501');

-- ---------- (B) boshlang'ich qoldiq ----------
select zz.chk('B1 boshlang''ich qoldiqsiz kirim rad', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"b1-000001"}', zz.id('cp_bank'))),
  '^ERR P0001 \[kassa:not_started\]');
select zz.chk('B1b rad etilgan urinish iz qoldirmadi (hujjat ham, raqam ham yo''q)',
  (select count(*)::text from public.cash_docs) || '/' || (select count(*)::text from public.doc_counters), '^0/0$');
select zz.chk('B2 boshlang''ich qoldiq: kassir kirita olmaydi', zz.as('U_KAS', $q$select public.kassa_opening_set('{"amount":1000000,"startDay":"2027-01-04"}')::text$q$), '^ERR 42501');
select zz.chk('B3 boshlang''ich qoldiq: Direktor 1 000 000', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":1000000,"startDay":"2027-01-04","note":"31.12 sanash","commission":[{"title":"Direktor","name":"Sinov D"},{"title":"Kassir","name":"Sinov K"}]}')::text$q$),
  '"openingAmount": 1000000');
select zz.chk('B4 dalolatnoma «Д-1» (Dt 5010 Kt 0000)',
  (select c.form || ':' || c.no || ':' || c.status || ':' || l.debit || '>' || l.credit from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.op = 'nc_opening'), '^ACT:1:posted:5010>0000$');
select zz.put('B5', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":500000,"startDay":"2027-01-04"}')::text$q$));
select zz.chk('B5 qayta kiritish (500 000): eski dalolatnoma bekor, yangisi «Д-2»', (select v from zz.v where k = 'B5') || ' / ' ||
  (select string_agg(no || ':' || status, ',' order by no) from public.cash_docs where op = 'nc_opening'), '"openingAmount": 500000.* / 1:void,2:posted$');
select zz.chk('B6 holat: kassa tayyor, qoldiq 500 000', zz.as('U_KAS', $q$select (s ->> 'canPost') || '/' || (s ->> 'balance') from public.kassa_state('main') s$q$), '^true/500000$');

-- ---------- (C) KO-1 kirim ----------
select zz.put('C1', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":2000000,"partyType":"bank","partyId":"%s","basis":"Chek kitobchasi № 001","clientRef":"c1-000001"}', zz.id('cp_bank'))));
select zz.chk('C1 bankdan naqd: o''tkazildi, KO-1 № 1, 04.01.2027', (select v from zz.v where k = 'C1'), '"no": 1[,}].*"status": "posted"|"status": "posted".*"no": 1[,}]');
select zz.chk('C1b kun ochildi: kun boshi 500 000, qoldiq 2 500 000',
  (select trim_scale(opening)::text || '/' || day from public.cash_days where status = 'open') || '/' || zz.bal(), '^500000/2027-01-04/2500000$');
select zz.chk('C1c qator: Dt 5010 Kt 5110, statiya OP-01',
  (select debit || '>' || credit || '@' || "articleId" from public.cash_doc_lines where "docId" = zz.id('C1')), '^5010>5110@OP-01$');
select zz.chk('C2 qayta yuborish (o''sha kalit): takror, raqam o''zgarmadi',
  zz.rcpt('U_KAS', format('{"op":"in_bank","amount":2000000,"partyType":"bank","partyId":"%s","basis":"Chek kitobchasi № 001","clientRef":"c1-000001"}', zz.id('cp_bank')))
  || ' / ' || (select "lastNo" from public.doc_counters where series = 'KO1'), '"dup": true.* / 1$');
select zz.chk('C3 o''sha kalit, boshqa summa — rad',
  zz.rcpt('U_KAS', format('{"op":"in_bank","amount":2000001,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"c1-000001"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:ref_mismatch\]');
-- state-9: o'sha kalit bilan qayta yuborishda mazmun ham solishtiriladi (so'rov izi "reqHash") — summa bir xil, lekin tomon / asos / statiya
--   boshqa bo'lsa eski hujjat jim qaytmaydi; aynan o'sha mazmun — takror (C2)
select zz.chk('C3b o''sha kalit va summa, boshqa asos yoki boshqa bank — rad (eski hujjat qaytmaydi); hujjat o''zgarmadi',
  zz.rcpt('U_KAS', format('{"op":"in_bank","amount":2000000,"partyType":"bank","partyId":"%s","basis":"Chek kitobchasi № 002","clientRef":"c1-000001"}', zz.id('cp_bank'))) || ' | '
  || zz.rcpt('U_KAS', format('{"op":"in_bank","amount":2000000,"partyType":"bank","partyId":"%s","basis":"Chek kitobchasi № 001","clientRef":"c1-000001"}', zz.id('cp_fnd'))) || ' | '
  || (select basis || ':' || "partyId" = 'Chek kitobchasi № 001:' || zz.id('cp_bank') from public.cash_docs where "clientRef" = 'c1-000001')::text,
  '^ERR 22023 \[kassa:ref_mismatch\].* \| ERR 22023 \[kassa:ref_mismatch\].* \| true$');
select zz.chk('C3c so''rov izi hujjatda saqlanadi (md5), mijoz hujjatlarida — doim',
  (select (length("reqHash") = 32)::text from public.cash_docs where "clientRef" = 'c1-000001'), '^true$');
select zz.chk('C4 boshqa kirim: izohsiz rad',
  zz.rcpt('U_KAS', $q${"op":"in_other","amount":100000,"partyType":"other","partyName":"Noma'lum shaxs","articleId":"OP-16","basis":"Ariza","clientRef":"c4-000001"}$q$), '^ERR 22023 \[kassa:note\]');
select zz.put('C4', zz.rcpt('U_KAS', $q${"op":"in_other","amount":100000,"partyType":"other","partyName":"Noma'lum shaxs","articleId":"OP-16","basis":"Ariza","note":"Aniqlanmagan tushum","fiscalNo":"FK-C4","clientRef":"c4-000002"}$q$));
select zz.chk('C4b boshqa kirim (aniqlanmagan): KO-1 № 2, Kt 6390',
  (select c.no || ':' || l.credit from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('C4')), '^2:6390$');
-- g8: «Boshqa kirim» aholidan (o'quvchi / to'lovchi, boshqa shaxs) — fiskal chek № majburiy (CT-21, CL-08; istisno — Direktor),
--   kontragent va xodimdan — yo'q (C10); qoida — operatsiya qoidasidagi "fiscalParties"
select zz.chk('C4c g8: boshqa kirim aholidan fiskal cheksiz — rad (boshqa shaxs ham, o''quvchi ham); kassir istisno so''ray olmaydi; raqam sarflanmaydi',
  zz.rcpt('U_KAS', $q${"op":"in_other","amount":20000,"partyType":"other","partyName":"Sinov Mehmon","articleId":"IN-06","basis":"Tilxat","note":"Tadbir chiptasi","clientRef":"c4c-00001"}$q$) || ' | '
  || zz.rcpt('U_KAS', $q${"op":"in_other","amount":20000,"partyType":"student","partyId":"T-1","articleId":"IN-06","basis":"Tilxat","note":"To'garak","clientRef":"c4c-00002"}$q$) || ' | '
  || zz.rcpt('U_KAS', $q${"op":"in_other","amount":20000,"partyType":"student","partyId":"T-1","articleId":"IN-06","basis":"Tilxat","note":"To'garak","fiscalExempt":true,"clientRef":"c4c-00003"}$q$) || ' | '
  || (select "lastNo" from public.doc_counters where series = 'KO1')::text || ':' || (select "fiscalParties"::text from public.fin_op_rules where op = 'in_other'),
  '^ERR 22023 \[kassa:fiscal\].* \| ERR 22023 \[kassa:fiscal\].* \| ERR 22023 \[kassa:fiscal\].* \| 2:\{student,other\}$');
-- (raqamlar keyingi tekshiruvlar uchun o'zgarmasin: natija psql o'zgaruvchisida, savepoint qaytariladi)
savepoint c4d;
select (zz.rcpt('U_KAS', $q${"op":"in_other","amount":20000,"partyType":"student","partyId":"T-1","articleId":"IN-06","basis":"Tilxat","note":"To'garak","fiscalNo":"F-C4D","clientRef":"c4d-00001"}$q$)::jsonb ->> 'fiscalNo') || ':'
  || (select (j ->> 'fiscalExempt') || ':' || (j ->> 'status') from (select zz.rcpt('U_DIR', $q${"op":"in_other","amount":20000,"partyType":"other","partyName":"Sinov Mehmon","articleId":"IN-06","basis":"Tilxat","note":"Tadbir chiptasi","fiscalExempt":true,"clientRef":"c4d-00002"}$q$)::jsonb j) q) || ':'
  || (zz.rcpt('U_KAS', format('{"op":"in_other","amount":20000,"partyType":"counterparty","partyId":"%s","articleId":"IN-06","basis":"Qaytarilgan ortiqcha to''lov","note":"Yetkazib beruvchidan","clientRef":"c4d-00003"}', zz.id('cp_sup')))::jsonb ->> 'status') as c4d \gset
rollback to savepoint c4d;
select zz.chk('C4d g8: o''quvchidan fiskal chek bilan va Direktor istisnosi bilan — o''tkaziladi; kontragentdan — fiskal cheksiz ham', :'c4d', '^F-C4D:true:posted:posted$');
select zz.chk('C5 boshqa kirimda ruxsat etilmagan statiya rad',
  zz.rcpt('U_KAS', $q${"op":"in_other","amount":1000,"partyType":"other","partyName":"Noma'lum shaxs","articleId":"EX-20","basis":"Ariza","note":"izoh bor","clientRef":"c5-000001"}$q$), '^ERR 22023 \[kassa:article\]');
select zz.chk('C6 forma sotuvi: fiskal chek raqamisiz rad',
  zz.rcpt('U_KAS', $q${"op":"in_sale","amount":150000,"partyType":"student","partyId":"T-1","basis":"Forma","clientRef":"c6-000001"}$q$), '^ERR 22023 \[kassa:fiscal\]');
select zz.put('C6', zz.rcpt('U_KAS', $q${"op":"in_sale","amount":150000,"partyType":"student","partyId":"s1","partyName":"Sinov Ota","basis":"Forma","fiscalNo":"F-1001","clientRef":"c6-000002"}$q$));
select zz.chk('C6b forma sotuvi: KO-1 № 3, Kt 9020, o''quvchi kanonik kaliti, to''lovchi ismi',
  (select c.no || ':' || l.credit || ':' || c."partyId" || ':' || c."partyName" || ':' || c."fiscalNo" from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('C6')), '^3:9020:T-1:Sinov Ota:F-1001$');
select zz.chk('C6c o''sha fiskal chek raqami ikkinchi marta — rad',
  zz.rcpt('U_KAS', $q${"op":"in_sale","amount":150000,"partyType":"student","partyId":"T-1","basis":"Forma","fiscalNo":"F-1001","clientRef":"c6-000003"}$q$), '^ERR 22023 \[kassa:fiscal_dup\]');
select zz.chk('C6c2 state-9: javob yo''qolgach fiskal chek raqami tuzatilib o''sha kalit bilan qayta yuborilsa — rad (eski raqamli hujjat jim qaytmaydi); aynan o''sha — takror',
  zz.rcpt('U_KAS', $q${"op":"in_sale","amount":150000,"partyType":"student","partyId":"s1","partyName":"Sinov Ota","basis":"Forma","fiscalNo":"F-1002","clientRef":"c6-000002"}$q$) || ' | '
  || (zz.rcpt('U_KAS', $q${"op":"in_sale","amount":150000,"partyType":"student","partyId":"s1","partyName":"Sinov Ota","basis":"Forma","fiscalNo":"F-1001","clientRef":"c6-000002"}$q$)::jsonb ->> 'dup'),
  '^ERR 22023 \[kassa:ref_mismatch\].* \| true$');
select zz.chk('C6d fiskal istisno: kassir so''ray olmaydi',
  zz.rcpt('U_KAS', $q${"op":"in_sale","amount":50000,"partyType":"student","partyId":"T-1","basis":"Forma","fiscalExempt":true,"clientRef":"c6-000004"}$q$), '^ERR 22023 \[kassa:fiscal\]');
select zz.put('C6e', zz.rcpt('U_DIR', $q${"op":"in_sale","amount":50000,"partyType":"student","partyId":"T-1","basis":"Forma","fiscalExempt":true,"clientRef":"c6-000005"}$q$));
select zz.chk('C6e fiskal istisno: Direktor (favqulodda) — KO-1 № 4, belgilanadi',
  (select no || ':' || "fiscalExempt" || ':' || "postedBy" from public.cash_docs where id = zz.id('C6e')), '^4:true:U_DIR$');
select zz.chk('C7 o''quv haqi qo''lda kiritilmaydi («To''lov» bo''limidan)',
  zz.rcpt('U_KAS', $q${"op":"in_tuition","amount":1000,"partyType":"student","partyId":"T-1","basis":"x y z","fiscalNo":"F-2","clientRef":"c7-000001"}$q$), '^ERR 42501 \[kassa:not_manual\]');
select zz.chk('C8 kassa ortiqchasi qo''lda kiritilmaydi (tizim hujjati)',
  zz.rcpt('U_KAS', $q${"op":"in_surplus","amount":1000,"basis":"x y z","clientRef":"c8-000001"}$q$), '^ERR 42501 \[kassa:not_manual\]');
select zz.chk('C9 o''qituvchi kirim yoza olmaydi', zz.rcpt('U_TCH', $q${"op":"in_other","amount":1,"clientRef":"c9-000001"}$q$), '^ERR 42501');
select zz.chk('C9b Moliya menejeri kirim yoza olmaydi (pulni kassir oladi)', zz.rcpt('U_FM', $q${"op":"in_other","amount":1,"clientRef":"c9-000002"}$q$), '^ERR 42501');
select zz.chk('C9c buxgalter kirim yoza olmaydi', zz.rcpt('U_ACC', $q${"op":"in_other","amount":1,"clientRef":"c9-000003"}$q$), '^ERR 42501');
-- acc-3: hisobdordan qaytim faqat hisobot qilinmagan avans qoldig'idan (bu xodimda avans yo'q) — rad, iz qolmaydi
select zz.chk('C10 hisobdordan qaytim: avans berilmagan xodimdan — rad (qoldiq 0), hujjat ham, raqam ham yo''q',
  zz.rcpt('U_KAS', $q${"op":"in_acc_return","amount":40000,"partyType":"employee","partyId":"teachers:tch1","basis":"Avans hisoboti qoldig'i","clientRef":"c10-00001"}$q$)
  || ' / ' || (select count(*) from public.cash_docs where "clientRef" = 'c10-00001') || '/' || (select "lastNo" from public.doc_counters where series = 'KO1'),
  '^ERR P0001 \[kassa:acc_over\].*qoldiq 0 so''m.* / 0/4$');
select zz.put('C10', zz.rcpt('U_KAS', $q${"op":"in_other","amount":40000,"partyType":"employee","partyId":"teachers:tch1","articleId":"IN-06","basis":"Tushuntirish xati","note":"Ortiqcha olingan pul qaytdi","clientRef":"c10-00002"}$q$));
select zz.chk('C10b boshqa kirim xodimdan: KO-1 № 5, Kt 9390, xodim',
  (select c.no || ':' || l.credit || ':' || c."partyId" || ':' || c."partyName" from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('C10')), '^5:9390:teachers:tch1:Sinov O''qituvchi$');
-- acc-1: xodim qaytargan avans — oy majburiy, shu oy naqd avans qoldig'idan (50 000) oshmaydi; manfiy avans yozuvi shu tranzaksiyada
select zz.chk('C11a xodim qaytargan pul: oy tanlanmagan — rad; avans qoldig''idan katta — rad (qoldiq 50 000)',
  zz.rcpt('U_KAS', $q${"op":"in_staff_return","amount":10000,"partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha berilgan avans","clientRef":"c11-00001"}$q$) || ' | ' ||
  zz.rcpt('U_KAS', $q${"op":"in_staff_return","amount":50001,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha berilgan avans","clientRef":"c11-00001"}$q$),
  '^ERR 22023 \[kassa:month\].* \| ERR P0001 \[kassa:staff_over\].*qoldiq 50000 so''m');
select zz.put('C11', zz.rcpt('U_KAS', $q${"op":"in_staff_return","amount":10000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha berilgan avans","clientRef":"c11-00001"}$q$));
select zz.chk('C11 xodim qaytargan avans: KO-1 № 6, Kt 4210; avans yozuvi −10 000 (shu order bilan), oy avansi sof 40 000',
  (select c.no || ':' || l.credit || ':' || (c."sourceSnapshot" ->> 'month') from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('C11'))
  || ' / ' || (select trim_scale(amount) || ':' || month || ':' || method || ':' || ("cashDocId" = zz.id('C11')) from public.staff_advances where "cashDocId" is not null)
  || ' / ' || trim_scale(app.payroll_adv('IQX-T1', '2027-01')), '^6:4210:2027-01 / -10000:2027-01:cash:true / 40000$');
select zz.chk('C12a summa 0 rad', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":0,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"c12-00001"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:amount\]');
select zz.chk('C12b manfiy summa rad', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":-5,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"c12-00002"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:amount\]');
select zz.chk('C12c NaN rad', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":"NaN","partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"c12-00003"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:amount\]');
select zz.chk('C12d juda katta summa rad', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":1000000000000,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"c12-00004"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:amount\]');
select zz.chk('C12e 3 xonali tiyin rad', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":1.234,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"c12-00005"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:amount\]');
select zz.chk('C12f Infinity rad', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":"Infinity","partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"c12-00006"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:amount\]');
select zz.put('C13', zz.rcpt('U_KAS', format('{"op":"in_funding","amount":1000000,"partyType":"founder","partyId":"%s","articleId":"OP-19","basis":"Qarz shartnomasi № 1","clientRef":"c13-00001"}', zz.id('cp_fnd'))));
select zz.chk('C13 qarz / ta''sischi mablag''i: avval so''rov (raqamsiz), Direktor ruxsati kerak',
  (select status || ':' || coalesce(no::text, '-') || ':' || "needsDirector" || ':' || "needsList2" from public.cash_docs where id = zz.id('C13')), '^draft:-:true:false$');
select zz.chk('C13b ruxsatsiz o''tkazib bo''lmaydi', zz.pay('U_KAS', zz.id('C13')), '^ERR 42501 \[kassa:not_approved\]');
select zz.chk('C13c Moliya menejeri tasdig''i bu yerda talab qilinmaydi', zz.appr('U_FM', zz.id('C13')), '^ERR 42501 \[kassa:no_approval\]');
select zz.chk('C13d Direktor ruxsat berdi', zz.appr('U_DIR', zz.id('C13')), '"status": "approved"');
select zz.put('C13e', zz.pay('U_KAS', zz.id('C13')));
select zz.chk('C13e kassir qabul qildi: KO-1 № 7, Kt 6820', (select v from zz.v where k = 'C13e') || ' / ' ||
  (select c.no || ':' || l.credit from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('C13')), '"status": "posted".* / 7:6820$');
select zz.chk('C14 tomon turi mos emas (bank o''rniga yetkazib beruvchi)',
  zz.rcpt('U_KAS', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"c14-00001"}', zz.id('cp_sup'))), '^ERR 22023 \[kassa:party\]');
select zz.chk('C15 «boshqa» tomon: ism yozilmagan — rad',
  zz.rcpt('U_KAS', $q${"op":"in_other","amount":1000,"partyType":"other","partyName":"a","articleId":"IN-06","basis":"Ariza","note":"izoh bor","clientRef":"c15-00001"}$q$), '^ERR 22023 \[kassa:party\]');
select zz.chk('C16 tomon ko''rsatilmagan — rad',
  zz.rcpt('U_KAS', $q${"op":"in_other","amount":1000,"articleId":"IN-06","basis":"Ariza","note":"izoh bor","clientRef":"c16-00001"}$q$), '^ERR 22023 \[kassa:party\]');
select zz.chk('C17 asos yozilmagan — rad',
  zz.rcpt('U_KAS', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","clientRef":"c17-00001"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:basis\]');
select zz.chk('C18 noto''g''ri kalit (clientRef) — rad',
  zz.rcpt('U_KAS', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"a b"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:bad_input\]');
select zz.chk('C19 qo''shimcha «kassir» lavozimli xodim ham kirim yoza oladi',
  zz.rcpt('U_HRK', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"Chek 002","clientRef":"c19-00001"}', zz.id('cp_bank'))), '"no": 8[,}]');
select zz.chk('C20 rad etilgan urinishlar raqam yemadi: KO-1 hisoblagich = 8, qoldiq',
  (select "lastNo"::text from public.doc_counters where series = 'KO1') || '/' || zz.bal(), '^8/3851000$');

-- ---------- (D) KO-2 chiqim ----------
select zz.put('D1', zz.preq('U_KAS', format('{"op":"out_expense","amount":300000,"partyType":"counterparty","partyId":"%s","articleId":"EX-16","basis":"Hisob-faktura № 15, 04.01.2027","clientRef":"d1-000001"}', zz.id('cp_sup'))));
select zz.chk('D1 xarajat so''rovi: raqamsiz, 2-ro''yxat tasdig''i kerak, Direktor shart emas (≤ T1)',
  (select status || ':' || coalesce(no::text, '-') || ':' || "needsList2" || ':' || "needsDirector" from public.cash_docs where id = zz.id('D1')), '^draft:-:true:false$');
select zz.chk('D1b qator: Dt 2010 (statiya hisobvarag''i) Kt 5010',
  (select debit || '>' || credit || '@' || "articleId" from public.cash_doc_lines where "docId" = zz.id('D1')), '^2010>5010@EX-16$');
select zz.chk('D2 tasdiqsiz pul berilmaydi', zz.pay('U_KAS', zz.id('D1')), '^ERR 42501 \[kassa:not_approved\]');
select zz.chk('D3 kassir tasdiqlay olmaydi', zz.appr('U_KAS', zz.id('D1')), '^ERR 42501');
select zz.chk('D4 Moliya menejeri tasdiqladi', zz.appr('U_FM', zz.id('D1')), '"status": "approved"');
select zz.chk('D4b qayta tasdiq — takror', zz.appr('U_FM', zz.id('D1')), '"dup": true');
select zz.chk('D5 kassir pulni berdi: KO-2 № 1, qoldiq kamaydi', zz.pay('U_KAS', zz.id('D1')) || ' / ' || zz.bal(), '"no": 1[,}].* / 3551000$');
select zz.chk('D6 qayta to''lash — takror, raqam va qoldiq o''zgarmadi',
  zz.pay('U_KAS', zz.id('D1')) || ' / ' || (select "lastNo" from public.doc_counters where series = 'KO2') || '/' || zz.bal(), '"dup": true.* / 1/3551000$');
select zz.put('D7', zz.preq('U_KAS', format('{"op":"out_expense","amount":600000,"partyType":"counterparty","partyId":"%s","articleId":"EX-15","basis":"Shartnoma № 7","clientRef":"d7-000001"}', zz.id('cp_sup'))));
select zz.chk('D7 T1 dan katta: Direktor ham kerak', (select "needsDirector"::text from public.cash_docs where id = zz.id('D7')), '^true$');
select zz.chk('D7b faqat Moliya menejeri tasdiqladi — hali tasdiqlanmagan', zz.appr('U_FM', zz.id('D7')), '"status": "draft"');
select zz.chk('D7c Direktorsiz pul berilmaydi', zz.pay('U_KAS', zz.id('D7')), '^ERR 42501 \[kassa:not_approved\]');
select zz.chk('D7d Direktor tasdiqladi', zz.appr('U_DIR', zz.id('D7')), '"status": "approved"');
select zz.chk('D7e to''landi: KO-2 № 2', zz.pay('U_KAS', zz.id('D7')), '"no": 2[,}]');
select zz.put('D8', zz.preq('U_FM', format('{"op":"out_expense","amount":100000,"partyType":"counterparty","partyId":"%s","articleId":"EX-32","basis":"Hisob-faktura № 16","clientRef":"d8-000001"}', zz.id('cp_sup'))));
select zz.chk('D8 so''rovchi o''zi tasdiqlay olmaydi', zz.appr('U_FM', zz.id('D8')), '^ERR 42501 \[kassa:self_approve\]');
select zz.chk('D8b boshqa 2-ro''yxat shaxsi (buxgalter) tasdiqladi', zz.appr('U_ACC', zz.id('D8')), '"status": "approved"');
select zz.chk('D8c to''landi: KO-2 № 3, Dt 9420', zz.pay('U_KAS', zz.id('D8')) || ' / ' ||
  (select debit from public.cash_doc_lines where "docId" = zz.id('D8')), '"no": 3[,}].* / 9420$');
select zz.chk('D9 ish haqi statiyasi kassa xarajatida rad (CT-23)',
  zz.preq('U_KAS', format('{"op":"out_expense","amount":1000,"partyType":"counterparty","partyId":"%s","articleId":"EX-01","basis":"Hujjat № 1","clientRef":"d9-000001"}', zz.id('cp_sup'))), '^ERR 22023 \[kassa:article\]');
select zz.chk('D10 xarajat oluvchisi xodim bo''lolmaydi (CT-24)',
  zz.preq('U_KAS', $q${"op":"out_expense","amount":1000,"partyType":"employee","partyId":"staff:st1","articleId":"EX-16","basis":"Hujjat № 1","clientRef":"d10-00001"}$q$), '^ERR 22023 \[kassa:party\]');
select zz.put('D11', zz.preq('U_KAS', $q${"op":"out_expense","amount":150000,"partyType":"other","partyName":"Bozor sotuvchisi","articleId":"EX-20","noBasis":true,"clientRef":"d11-00001"}$q$));
select zz.chk('D11 asos hujjatisiz xarid ≤ L1: qabul, Dt 1010', (select c.status || ':' || c."noBasis" || ':' || l.debit from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('D11')), '^draft:true:1010$');
select zz.chk('D11b asos hujjatisiz L1 dan katta — rad',
  zz.preq('U_KAS', $q${"op":"out_expense","amount":200001,"partyType":"other","partyName":"Bozor sotuvchisi","articleId":"EX-20","noBasis":true,"clientRef":"d11-00002"}$q$), '^ERR 22023 \[kassa:basis\]');
select zz.chk('D11c asos hujjatisiz ikki statiya — rad',
  zz.preq('U_KAS', $q${"op":"out_expense","amount":100000,"partyType":"other","partyName":"Bozor sotuvchisi","noBasis":true,"lines":[{"articleId":"EX-20","amount":60000},{"articleId":"EX-16","amount":40000}],"clientRef":"d11-00003"}$q$), '^ERR 22023 \[kassa:basis\]');
select zz.chk('D11d tasdiq va to''lov: KO-2 № 4', zz.appr('U_FM', zz.id('D11')) || zz.pay('U_KAS', zz.id('D11')), '"no": 4[,}]');
select zz.chk('D12 ko''p qatorli: yig''indi mos emas — rad',
  zz.preq('U_KAS', format('{"op":"out_expense","amount":100000,"partyType":"counterparty","partyId":"%s","basis":"Hisob-faktura № 17","lines":[{"articleId":"EX-16","amount":70000},{"articleId":"EX-32","amount":20000}],"clientRef":"d12-00001"}', zz.id('cp_sup'))), '^ERR 22023 \[kassa:lines\]');
select zz.put('D12', zz.preq('U_KAS', format('{"op":"out_expense","amount":100000,"partyType":"counterparty","partyId":"%s","basis":"Hisob-faktura № 17","lines":[{"articleId":"EX-16","amount":70000},{"articleId":"EX-32","amount":30000}],"clientRef":"d12-00002"}', zz.id('cp_sup'))));
select zz.chk('D12b ko''p qatorli: 2 qator (2010 va 9420)',
  (select string_agg(debit || '=' || trim_scale(amount), ',' order by "lineNo") from public.cash_doc_lines where "docId" = zz.id('D12')), '^2010=70000,9420=30000$');
select zz.chk('D12b2 state-9: o''sha kalit, o''sha jami, lekin qatorlar boshqacha taqsimlangan — rad; aynan o''sha — takror (so''rov bitta)',
  zz.preq('U_KAS', format('{"op":"out_expense","amount":100000,"partyType":"counterparty","partyId":"%s","basis":"Hisob-faktura № 17","lines":[{"articleId":"EX-16","amount":60000},{"articleId":"EX-32","amount":40000}],"clientRef":"d12-00002"}', zz.id('cp_sup'))) || ' | '
  || (zz.preq('U_KAS', format('{"op":"out_expense","amount":100000,"partyType":"counterparty","partyId":"%s","basis":"Hisob-faktura № 17","lines":[{"articleId":"EX-16","amount":70000},{"articleId":"EX-32","amount":30000}],"clientRef":"d12-00002"}', zz.id('cp_sup')))::jsonb ->> 'dup')
  || ':' || (select count(*) from public.cash_docs where "clientRef" = 'd12-00002'),
  '^ERR 22023 \[kassa:ref_mismatch\].* \| true:1$');
select zz.chk('D12c tasdiq va to''lov: KO-2 № 5', zz.appr('U_FM', zz.id('D12')) || zz.pay('U_KAS', zz.id('D12')), '"no": 5[,}]');
select zz.chk('D13 «Boshqa xarajatlar» izohsiz — rad',
  zz.preq('U_KAS', format('{"op":"out_expense","amount":1000,"partyType":"counterparty","partyId":"%s","articleId":"EX-49","basis":"Hujjat № 2","clientRef":"d13-00001"}', zz.id('cp_sup'))), '^ERR 22023 \[kassa:note\]');
select zz.put('D14', zz.preq('U_KAS', format('{"op":"out_expense","amount":50000000,"partyType":"counterparty","partyId":"%s","articleId":"OP-18","basis":"Shartnoma № 9","clientRef":"d14-00001"}', zz.id('cp_sup'))));
select zz.chk('D14 kassada yetmaydigan summa: tasdiqlangan bo''lsa ham berilmaydi (CT-12)',
  left(zz.appr('U_FM', zz.id('D14')), 0) || left(zz.appr('U_DIR', zz.id('D14')), 0) || zz.pay('U_KAS', zz.id('D14')), '^ERR P0001 \[kassa:negative\]');
select zz.chk('D14b rad etilgan to''lov raqam yemadi; hujjat «tasdiqlangan» holatda qoldi',
  (select "lastNo"::text from public.doc_counters where series = 'KO2') || '/' || (select status from public.cash_docs where id = zz.id('D14')), '^5/approved$');
select zz.put('D15', zz.preq('U_KAS', format('{"op":"out_expense","amount":5000,"partyType":"counterparty","partyId":"%s","articleId":"EX-16","basis":"Hujjat № 3","clientRef":"d15-00001"}', zz.id('cp_sup'))));
select zz.chk('D15 rad etish: sababsiz bo''lmaydi', zz.as('U_FM', format('select public.kassa_doc_reject(%L, %L)::text', zz.id('D15'), '')), '^ERR 22023 \[kassa:reason\]');
select zz.chk('D15b Moliya menejeri rad etdi', zz.as('U_FM', format('select public.kassa_doc_reject(%L, %L)::text', zz.id('D15'), 'Asos hujjati yo''q')), '"status": "rejected"');
select zz.chk('D15c rad etilgan hujjat bo''yicha pul berilmaydi', zz.pay('U_KAS', zz.id('D15')), '^ERR P0001 \[kassa:bad_status\]');
select zz.put('D16', zz.preq('U_KAS', format('{"op":"out_expense","amount":6000,"partyType":"counterparty","partyId":"%s","articleId":"EX-16","basis":"Hujjat № 4","clientRef":"d16-00001"}', zz.id('cp_sup'))));
select zz.chk('D16 boshqa kassir so''rovni bekor qila olmaydi', zz.as('U_KAS2', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('D16'), 'Kerak emas')), '^ERR 42501');
select zz.chk('D16b so''rovchi o''zi bekor qiladi', zz.as('U_KAS', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('D16'), 'Kerak emas')), '"status": "cancelled"');
select zz.chk('D16c Direktor tasdiqlangan (to''lanmagan) so''rovni bekor qiladi', zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('D14'), 'Mablag'' yo''q')), '"status": "cancelled"');
select zz.put('D17', zz.preq('U_KAS', format('{"op":"out_handover","amount":200000,"partyType":"founder","partyId":"%s","basis":"Direktor farmoyishi № 2","clientRef":"d17-00001"}', zz.id('cp_fnd'))));
select zz.chk('D17 rahbar / ta''sischiga berish: summadan qat''i nazar Direktor ham; ta''sischi — Dt 4890',
  (select c."needsList2" || ':' || c."needsDirector" || ':' || l.debit from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('D17')), '^true:true:4890$');
select zz.chk('D17b ikki tasdiq va to''lov: KO-2 № 6', left(zz.appr('U_DIR', zz.id('D17')), 0) || left(zz.appr('U_FM', zz.id('D17')), 0) || zz.pay('U_KAS', zz.id('D17')), '"no": 6[,}]');
select zz.put('D17x', zz.preq('U_KAS', $q${"op":"out_handover","amount":1000,"partyType":"employee","partyId":"staff:st1","basis":"Direktor farmoyishi № 3","clientRef":"d17-00002"}$q$));
select zz.chk('D17c xodim-rahbarga berish — Dt 4290', (select debit from public.cash_doc_lines where "docId" = zz.id('D17x')), '^4290$');
select zz.put('D18', zz.preq('U_KAS', format('{"op":"out_bank","amount":1000000,"partyType":"bank","partyId":"%s","basis":"Naqd pul topshirish e''loni № 1","clientRef":"d18-00001"}', zz.id('cp_bank'))));
select zz.chk('D18 bankka topshirish: Dt 5710 (yo''ldagi pul), tasdiqlar, KO-2 № 7',
  left(zz.appr('U_FM', zz.id('D18')), 0) || left(zz.appr('U_DIR', zz.id('D18')), 0) || zz.pay('U_KAS', zz.id('D18')) || ' / ' ||
  (select debit || '@' || "articleId" from public.cash_doc_lines where "docId" = zz.id('D18')), '"no": 7[,}].* / 5710@OP-02$');
select zz.chk('D19 ish haqi qo''lda kiritilmaydi («Maosh» bo''limidan)',
  zz.preq('U_KAS', $q${"op":"out_salary","amount":1000,"partyType":"employee","partyId":"staff:st1","basis":"Vedomost","clientRef":"d19-00001"}$q$), '^ERR 42501 \[kassa:not_manual\]');
select zz.chk('D20 o''qituvchi chiqim so''ray olmaydi', zz.preq('U_TCH', $q${"op":"out_expense","amount":1,"clientRef":"d20-00001"}$q$), '^ERR 42501');
select zz.chk('D21 buxgalter chiqim so''ray olmaydi (faqat tasdiqlaydi)', zz.preq('U_ACC', $q${"op":"out_expense","amount":1,"clientRef":"d21-00001"}$q$), '^ERR 42501');
select zz.chk('D22 Moliya menejeri pul bera olmaydi', zz.pay('U_FM', zz.id('D17x')), '^ERR 42501');
select zz.chk('D23 kassa operatsiyasi KO-1 shaklida so''ralsa — rad',
  zz.rcpt('U_KAS', format('{"op":"out_expense","amount":1000,"partyType":"counterparty","partyId":"%s","articleId":"EX-16","basis":"Hujjat № 5","clientRef":"d23-00001"}', zz.id('cp_sup'))), '^ERR 22023 \[kassa:bad_op\]');
select zz.chk('D24 qoldiq: 500 000 + kirim 3 351 000 − chiqim 2 450 000', zz.bal(), '^1401000$');

-- ---------- (F1) bazadagi himoya — kun ochiq paytida ----------
select zz.chk('F1 bayroq bilan ham: summani o''zgartirib bo''lmaydi',
  zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_docs set amount = 1 where id = %L; end $x$$q$, zz.id('C1'))), '^ERR 42501 \[kassa:immutable\]');
select app.kassa_flag(false);
select zz.chk('F2 hujjat o''chirilmaydi', zz.try(format('delete from public.cash_docs where id = %L', zz.id('C1'))), '^ERR 42501 \[kassa:immutable\]');
select zz.chk('F3 qator o''zgartirilmaydi', zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_doc_lines set amount = 1 where "docId" = %L; end $x$$q$, zz.id('C1'))), '^ERR 42501 \[kassa:immutable\]');
select app.kassa_flag(false);
select zz.chk('F4 qator o''chirilmaydi', zz.try(format('delete from public.cash_doc_lines where "docId" = %L', zz.id('C1'))), '^ERR 42501 \[kassa:immutable\]');
select zz.chk('F5 o''tkazilgan hujjat so''rov holatiga qaytmaydi',
  zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_docs set status = 'draft' where id = %L; end $x$$q$, zz.id('C1'))), '^ERR (42501|23514)');
select app.kassa_flag(false);
select zz.chk('F6 tasdiqsiz hujjatni RPC''siz ham o''tkazib bo''lmaydi',
  zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_docs set status = 'posted', no = 99, year = 2027, "businessDay" = '2027-01-04', "dayId" = 'cd_main_2027-01-04', "postedAt" = now() where id = %L; end $x$$q$, zz.id('D17x'))),
  '^ERR 42501 \[kassa:not_approved\]');
select app.kassa_flag(false);
select zz.put('F7', zz.preq('U_KAS', format('{"op":"out_expense","amount":90000000,"partyType":"counterparty","partyId":"%s","articleId":"OP-18","basis":"Shartnoma № 10","clientRef":"f7-000001"}', zz.id('cp_sup'))));
select zz.chk('F7 I5: RPC''ni chetlab o''tib ham qoldiq manfiy bo''lmaydi',
  left(zz.appr('U_FM', zz.id('F7')), 0) || left(zz.appr('U_DIR', zz.id('F7')), 0) ||
  zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_docs set status = 'posted', no = 99, year = 2027, "businessDay" = '2027-01-04', "dayId" = 'cd_main_2027-01-04', "postedAt" = now() where id = %L; end $x$$q$, zz.id('F7'))),
  '^ERR P0001 \[kassa:negative\]');
select app.kassa_flag(false);
select zz.chk('F7b so''rov bekor qilindi', zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('F7'), 'Sinov uchun')), '"status": "cancelled"');
select zz.chk('F8 I1: ikkinchi ochiq kun bo''lmaydi',
  zz.try($q$do $x$ begin perform app.kassa_flag(true); insert into public.cash_days (id, desk, day, status, opening) values ('cd_x', 'main', '2027-01-05', 'open', 0); end $x$$q$), '^ERR (P0001 \[kassa:prev_open\]|23505)');
select app.kassa_flag(false);
select zz.chk('F9 hisoblagich faqat +1', zz.try($q$do $x$ begin perform app.kassa_flag(true); update public.doc_counters set "lastNo" = "lastNo" + 2 where series = 'KO1'; end $x$$q$), '^ERR 22023 \[kassa:counter\]');
select app.kassa_flag(false);
select zz.chk('F10 hisoblagich bayroqsiz o''zgarmaydi', zz.try($q$update public.doc_counters set "lastNo" = "lastNo" + 1 where series = 'KO1'$q$), '^ERR 42501 \[kassa:rpc_only\]');
select zz.chk('F11 kun hodisalari jurnali o''zgartirilmaydi', zz.try($q$do $x$ begin perform app.kassa_flag(true); update public.cash_day_events set reason = 'x'; end $x$$q$), '^ERR 42501 \[kassa:immutable\]');
select app.kassa_flag(false);
select zz.chk('F12 kun boshi o''zgartirilmaydi', zz.try($q$do $x$ begin perform app.kassa_flag(true); update public.cash_days set opening = 0 where status = 'open'; end $x$$q$), '^ERR 42501 \[kassa:immutable\]');
select app.kassa_flag(false);
select zz.chk('F13 ishga tushgan kassaning boshlang''ich qoldig''i o''zgarmaydi',
  zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":1,"startDay":"2027-01-04"}')::text$q$), '^ERR 42501 \[kassa:started\]');

-- ---------- (E) shu kunda bekor qilish ----------
select zz.chk('E1 sababsiz bekor qilinmaydi', zz.void('U_KAS', zz.id('C4'), 'x'), '^ERR 22023 \[kassa:reason\]');
select zz.put('E2', zz.void('U_KAS', zz.id('C4'), 'Xato summa kiritildi'));
select zz.chk('E2 kassir o''z hujjatini bekor qildi: raqam saqlanadi, qoldiq kamaydi', (select v from zz.v where k = 'E2') || ' / ' || (select no || ':' || status from public.cash_docs where id = zz.id('C4')) || '/' || zz.bal(), '"status": "void".* / 2:void/1301000$');
select zz.chk('E3 qayta bekor qilish — takror', zz.void('U_KAS', zz.id('C4'), 'Xato summa kiritildi'), '"dup": true');
select zz.chk('E4 boshqa kassir birovning hujjatini bekor qila olmaydi', zz.void('U_KAS2', zz.id('C10'), 'Xato kiritilgan'), '^ERR 42501 \[kassa:not_own\]');
select zz.chk('E5 Moliya menejeri istalgan hujjatni bekor qiladi', zz.void('U_FM', zz.id('C10'), 'Xato kiritilgan') || ' / ' || zz.bal(), '"status": "void".* / 1261000$');
select zz.chk('E6 bekor qilinsa qoldiq manfiy bo''lsa — rad', zz.void('U_KAS', zz.id('C1'), 'Sinov: manfiy qoldiq'), '^ERR P0001 \[kassa:negative\]');
select zz.chk('E7 o''qituvchi bekor qila olmaydi', zz.void('U_TCH', zz.id('C1'), 'Sinov uchun'), '^ERR 42501');
select zz.chk('E8 so''rov (o''tkazilmagan) «bekor» bilan emas — so''rovni bekor qilish bilan', zz.void('U_KAS', zz.id('D17x'), 'Sinov uchun'), '^ERR P0001 \[kassa:bad_status\]');

-- ---------- (G) kun sikli ----------
select zz.chk('G1 boshqa sana bilan yopib bo''lmaydi (eski ekran)', zz.close('U_KAS', '{"day":"2027-01-03","counted":1261000}'), '^ERR P0001 \[kassa:wrong_day\]');
select zz.chk('G2 o''qituvchi yopa olmaydi', zz.close('U_TCH', '{"day":"2027-01-04","counted":1261000}'), '^ERR 42501');
select zz.chk('G2b Moliya menejeri kassir o''rniga — komissiyasiz rad', zz.close('U_FM', '{"day":"2027-01-04","counted":1261000}'), '^ERR 22023 \[kassa:commission\]');
select zz.chk('G2c sanalgan summa kiritilmagan — rad', zz.close('U_KAS', '{"day":"2027-01-04"}'), '^ERR 22023 \[kassa:count\]');
select zz.chk('G2d nominallar yig''indisi mos emas — rad', zz.close('U_KAS', '{"day":"2027-01-04","counted":1261000,"denoms":{"100000":12}}'), '^ERR 22023 \[kassa:denoms\]');
select zz.put('G3', zz.close('U_KAS', '{"day":"2027-01-04","counted":1261000,"denoms":{"100000":12,"50000":1,"10000":1,"1000":1}}'));
select zz.chk('G3 kun yopildi: farq 0, farq hujjati yo''q', (select v from zz.v where k = 'G3'), '"diff": 0[,}].*"diffDoc": null|"diffDoc": null.*"diff": 0[,}]');
select zz.chk('G3b I4: kun oxiri = kun boshi + kirim − chiqim = sanalgan',
  (select status || ':' || trim_scale(opening) || '+' || trim_scale(receipts) || '-' || trim_scale(payouts) || '=' || trim_scale(closing) || ':' || trim_scale(counted) from public.cash_days where day = '2027-01-04'),
  '^closed:500000\+3211000-2450000=1261000:1261000$');
select zz.chk('G3c hujjatlar soni, raqam oraliqlari, KO-4 varag''i, xesh',
  (select "docCount" || ':' || "firstKo1" || '-' || "lastKo1" || ':' || "firstKo2" || '-' || "lastKo2" || ':' || "sheetFrom" || '-' || "sheetTo" || ':' || length(hash) from public.cash_days where day = '2027-01-04'),
  '^15:1-8:1-7:1-1:64$');
select zz.chk('G3d qayta yopish (o''sha summa) — takror', zz.close('U_KAS', '{"day":"2027-01-04","counted":1261000}'), '"dup": true');
select zz.chk('G4 yopilgan kunga kirim yozilmaydi', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"Chek 003","clientRef":"g4-000001"}', zz.id('cp_bank'))), '^ERR P0001 \[kassa:day_closed\]');
select zz.chk('G4b yopilgan kun hujjati bekor qilinmaydi', zz.void('U_FM', zz.id('C1'), 'Sinov: yopilgan kun'), '^ERR P0001 \[kassa:day_closed\]');
select zz.chk('G4c I6: yopilgan kunga RPC''siz ham hujjat yozilmaydi',
  left(zz.appr('U_FM', zz.id('D17x')), 0) || left(zz.appr('U_DIR', zz.id('D17x')), 0) ||
  zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_docs set status = 'posted', no = 99, year = 2027, "businessDay" = '2027-01-04', "dayId" = 'cd_main_2027-01-04', "postedAt" = now() where id = %L; end $x$$q$, zz.id('D17x'))),
  '^ERR P0001 \[kassa:day_closed\]');
select app.kassa_flag(false);
select zz.chk('G5 kassir tekshira olmaydi', zz.as('U_KAS', $q$select public.kassa_day_verify('main', '2027-01-04', true)::text$q$), '^ERR 42501');
select zz.chk('G5b shu kuni hujjat o''tkazgan Direktor tekshira olmaydi (CT-05)', zz.as('U_DIR', $q$select public.kassa_day_verify('main', '2027-01-04', true)::text$q$), '^ERR 42501 \[kassa:self_verify\]');
-- crit-4: kunning nazorat ma'lumotini o'zgartirgan ham tekshirmaydi — Moliya menejeri shu kuni C10 ni bekor qilgan (E5); kunni buxgalter tekshiradi
select zz.chk('G5b2 shu kun hujjatini bekor qilgan Moliya menejeri tekshira olmaydi (crit-4)',
  zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-04', true, 'Hammasi joyida')::text$q$), '^ERR 42501 \[kassa:self_verify\] Shu kunning hujjatini o''zingiz bekor qilgansiz — kunni o''zingiz tekshira olmaysiz');
select zz.chk('G5c «qog''ozlar olindi» belgisisiz tekshirilmaydi', zz.as('U_ACC', $q$select public.kassa_day_verify('main', '2027-01-04', false)::text$q$), '^ERR 22023 \[kassa:papers\]');
select zz.chk('G5d buxgalter tekshirdi', zz.as('U_ACC', $q$select public.kassa_day_verify('main', '2027-01-04', true, 'Hammasi joyida')::text$q$), '"status": "verified"');
select zz.chk('G5e qayta tekshirish — takror', zz.as('U_ACC', $q$select public.kassa_day_verify('main', '2027-01-04', true)::text$q$), '"dup": true');
select zz.chk('G6 tekshirilgan kun qayta ochilmaydi', zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-01-04', 'Sinov: qayta ochish')::text$q$), '^ERR 42501 \[kassa:verified\]');
select zz.chk('G6b I6: tekshirilgan kun RPC''siz ham o''zgarmaydi',
  zz.try($q$do $x$ begin perform app.kassa_flag(true); update public.cash_days set "closeNote" = 'x' where day = '2027-01-04'; end $x$$q$), '^ERR 42501 \[kassa:verified\]');
select app.kassa_flag(false);

-- 2-kun: kamomad, qayta ochish, ortiqcha
select zz.clock('2027-01-05 09:30+05');
select zz.put('G7', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":100000,"partyType":"bank","partyId":"%s","basis":"Chek 004","clientRef":"g7-000001"}', zz.id('cp_bank'))));
select zz.chk('G7 I3: yangi kun boshi = kecha kun oxiri; raqam davom etadi (№ 9)',
  (select trim_scale(opening)::text || ':' || day from public.cash_days where status = 'open') || ':' || (select no from public.cash_docs where id = zz.id('G7')), '^1261000:2027-01-05:9$');
select zz.put('G8', zz.close('U_KAS', '{"day":"2027-01-05","counted":1311000,"note":"50 000 yetishmadi"}'));
select zz.chk('G8 kamomad: farq −50 000 → tizim KO-2 «Kassa kamomadi» (Dt 5910), shu kun sanasi bilan',
  (select c.form || ':' || c.no || ':' || c.op || ':' || trim_scale(c.amount) || ':' || c."isSystem" || ':' || coalesce(c."postedBy", '-') || ':' || c."businessDay" || ':' || l.debit
     from public.cash_days d join public.cash_docs c on c.id = d."diffDocId" join public.cash_doc_lines l on l."docId" = c.id where d.day = '2027-01-05'),
  '^KO2:8:out_shortage:50000:true:-:2027-01-05:5910$');
select zz.chk('G8b kun oxiri = sanalgan (KO-4 = sanalgan)', (select trim_scale(closing) || '/' || trim_scale(counted) || '/' || trim_scale(diff) from public.cash_days where day = '2027-01-05'), '^1311000/1311000/-50000$');
select zz.chk('G9 kassir qayta ocha olmaydi', zz.as('U_KAS', $q$select public.kassa_day_reopen('main', '2027-01-05', 'Qayta sanash kerak')::text$q$), '^ERR 42501');
select zz.chk('G9b sababsiz qayta ochilmaydi', zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-01-05', 'x')::text$q$), '^ERR 22023 \[kassa:reason\]');
select zz.put('G9c', zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-01-05', 'Qayta sanash kerak')::text$q$));
select zz.chk('G9c Direktor qayta ochdi: farq hujjati bekor (raqami saqlanadi), qoldiq tiklandi', (select v from zz.v where k = 'G9c') || ' / ' ||
  (select no || ':' || status from public.cash_docs where op = 'out_shortage') || '/' || zz.bal(), '"status": "open".* / 8:void/1361000$');
select zz.chk('G9d qayta ochish jurnalda (eski yopilish ma''lumoti bilan)',
  (select reason || ':' || (data ->> 'diff') from public.cash_day_events where kind = 'reopen'), '^Qayta sanash kerak:-50000');
select zz.put('G10', zz.close('U_KAS', '{"day":"2027-01-05","counted":1381000}'));
select zz.chk('G10 qayta yopish, ortiqcha +20 000 → tizim KO-1 «Kassa ortiqchasi» (Kt 9390)',
  (select c.form || ':' || c.no || ':' || c.op || ':' || trim_scale(c.amount) || ':' || l.credit || ':' || d."reopenCount" || ':' || d."sheetFrom" || '-' || d."sheetTo"
     from public.cash_days d join public.cash_docs c on c.id = d."diffDocId" join public.cash_doc_lines l on l."docId" = c.id where d.day = '2027-01-05'),
  '^KO1:10:in_surplus:20000:9390:1:2-2$');
select zz.chk('G10b kunni qayta ochgan Direktor uni tekshira olmaydi (crit-4)', zz.as('U_DIR', $q$select public.kassa_day_verify('main', '2027-01-05', true, 'Qayta sanaldi')::text$q$),
  '^ERR 42501 \[kassa:self_verify\] Kunni o''zingiz qayta ochgansiz — kunni o''zingiz tekshira olmaysiz');
select zz.chk('G11 buxgalter tekshirdi (2-kun)', zz.as('U_ACC', $q$select public.kassa_day_verify('main', '2027-01-05', true)::text$q$), '"status": "verified"');

-- 3-kun: smena topshirish, kecha ochiq qolgan kun, oflayn yozuv
select zz.clock('2027-01-06 09:00+05');
select zz.put('G12', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":200000,"partyType":"bank","partyId":"%s","basis":"Chek 005","clientRef":"g12-00001"}', zz.id('cp_bank'))));
select zz.chk('G12 3-kun: kun boshi 1 381 000', (select trim_scale(opening)::text from public.cash_days where status = 'open') || '/' || zz.bal(), '^1381000/1581000$');
select zz.chk('G13 smena topshirish: qabul qiluvchi kassir emas — rad',
  zz.as('U_KAS', $q$select public.kassa_handover('{"counted":1581000,"toUid":"U_TCH"}')::text$q$), '^ERR 22023 \[kassa:handover_to\]');
select zz.put('G13b', zz.as('U_KAS', $q$select public.kassa_handover('{"counted":1581000,"toUid":"U_KAS2","note":"Tushlikdan keyin"}')::text$q$));
-- state-6: smena topshirish ikki bosqichli — topshiruvchi yozadi (qabul kutiladi), qabul qiluvchi o'z hisobidan qabul qiladi
select zz.chk('G13b smena topshirish yozildi — qabul kutilmoqda: kassa egasi hali o''zgarmadi, sanash dalolatnomasi hali yo''q',
  zz.f(zz.get('G13b'), 'pending') || ':' || zz.f(zz.get('G13b'), 'diff') || ' / ' ||
  (select status || ':' || "cashierUid" from public.cash_days where day = '2027-01-06') || ':' || (select count(*) from public.cash_counts where kind = 'handover'),
  '^true:0 / open:U_KAS:0$');
select zz.put('G13c', zz.as('U_KAS2', format('select public.kassa_handover_accept(%L)::text', zz.get('G13b')::jsonb #>> '{handover,id}')));
select zz.chk('G13c qabul qiluvchi qabul qildi: kun ochiq, kassir almashdi, dalolatnoma yozildi', zz.f(zz.get('G13c'), 'diff') || ' / ' ||
  (select status || ':' || "cashierUid" from public.cash_days where day = '2027-01-06') || ':' || (select kind || ':' || trim_scale(diff) || ':' || "toUid" from public.cash_counts where kind = 'handover'),
  '^0 / open:U_KAS2:handover:0:U_KAS2$');
select zz.clock('2027-01-07 10:00+05');
select zz.chk('G14 CT-04: kecha yopilmagan — bugun hujjat yo''q',
  zz.rcpt('U_KAS2', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"Chek 006","clientRef":"g14-00001"}', zz.id('cp_bank'))), '^ERR P0001 \[kassa:prev_open\]');
select zz.chk('G14b holat: bloklangan (kecha ochiq)', zz.as('U_KAS2', $q$select (s ->> 'canPost') || '/' || (s ->> 'blockReason') from public.kassa_state('main') s$q$), '^false/prev_open$');
select zz.put('G15', zz.rcpt('U_KAS2', format('{"op":"in_bank","amount":30000,"partyType":"bank","partyId":"%s","basis":"Chek 007","capturedAt":"2027-01-06T17:00:00+05:00","clientRef":"g15-00001"}', zz.id('cp_bank'))));
select zz.chk('G15 kecha olingan (oflayn) yozuv hali ochiq o''sha kunga tushadi',
  (select "businessDay" || ':' || late || ':' || no from public.cash_docs where id = zz.id('G15')), '^2027-01-06:false:12$');
select zz.put('G16', zz.close('U_KAS2', '{"day":"2027-01-06","counted":1601000}'));
select zz.chk('G16 kechagi kun bugun yopildi: kamomad −10 000, hujjat kecha sanasi bilan',
  (select trim_scale(d.diff) || ':' || c."businessDay" || ':' || c.no from public.cash_days d join public.cash_docs c on c.id = d."diffDocId" where d.day = '2027-01-06'), '^-10000:2027-01-06:9$');
select zz.chk('G17 kamomad qarori: kassir qabul qila olmaydi', zz.as('U_KAS', format('select public.kassa_shortage_decide(%L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2027-01-06'), 'employee', 'Kassir roziligi bilan')), '^ERR 42501');
select zz.put('G17', zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2027-01-06'), 'employee', 'Kassir yozma roziligi bilan')));
select zz.chk('G17b Direktor qarori: xodim zimmasiga — dalolatnoma Dt 4730 Kt 5910 (yopilgan kun hujjatida faqat qaror maydonlari o''zgardi)',
  (select c.decision || ':' || a.form || ':' || a.status || ':' || l.debit || '>' || l.credit || ':' || coalesce(a."partyType", '-') || ':' || coalesce(a."partyId", '-')
     from public.cash_docs c join public.cash_docs a on a.id = c."decisionDocId" join public.cash_doc_lines l on l."docId" = a.id
    where c.id = (select "diffDocId" from public.cash_days where day = '2027-01-06')), '^employee:ACT:posted:4730>5910:employee:teachers:tch1$');
select zz.chk('G17c boshqa qaror — rad (qaror qabul qilingan)', zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2027-01-06'), 'writeoff', 'Boshqa qaror sinovi')), '^ERR P0001 \[kassa:decided\]');
select zz.chk('G17d o''sha qaror qayta — takror', zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2027-01-06'), 'employee', 'Kassir yozma roziligi bilan')), '"dup": true');

-- 4-kun: kech kiritish, 48 soat chegarasi, «hali o'tkazilmagan» yozuvlar
select zz.put('G18', zz.rcpt('U_KAS2', format('{"op":"in_bank","amount":20000,"partyType":"bank","partyId":"%s","basis":"Chek 008","capturedAt":"2027-01-06T18:00:00+05:00","clientRef":"g18-00001"}', zz.id('cp_bank'))));
select zz.chk('G18 olingan kuni yopilgan: joriy kunga «kech» belgisi bilan (kun boshi 1 601 000)',
  (select c."businessDay" || ':' || c.late || ':' || trim_scale(d.opening) from public.cash_docs c join public.cash_days d on d.id = c."dayId" where c.id = zz.id('G18')), '^2027-01-07:true:1601000$');
select zz.chk('G19 48 soatdan eski yozuv: kassir kirita olmaydi',
  zz.rcpt('U_KAS2', format('{"op":"in_bank","amount":5000,"partyType":"bank","partyId":"%s","basis":"Qog''oz varaqa Қ-1","capturedAt":"2027-01-04T09:00:00+05:00","clientRef":"g19-00001"}', zz.id('cp_bank'))), '^ERR P0001 \[kassa:late_limit\]');
select zz.put('G19', zz.rcpt('U_DIR', format('{"op":"in_bank","amount":5000,"partyType":"bank","partyId":"%s","basis":"Qog''oz varaqa Қ-1","capturedAt":"2027-01-04T09:00:00+05:00","clientRef":"g19-00002"}', zz.id('cp_bank'))));
select zz.chk('G19b 48 soatdan eski yozuvni Direktor kiritadi (kech)', (select late || ':' || "postedBy" from public.cash_docs where id = zz.id('G19')), '^true:U_DIR$');
-- state-2: hali o'tkazilmagan yozuvlar — ro'yxat bilan (qurilma navbatidagi har yozuv kaliti va summasi); avvalgi ro'yxatsiz soni / summa — rad
select zz.chk('G20 «hali o''tkazilmagan» yozuvlar: ro''yxatsiz soni / summa (avvalgi oyna) — rad; yozuv kaliti noto''g''ri yoki takror — rad',
  zz.close('U_KAS2', '{"day":"2027-01-07","counted":1726000,"pendingCount":1,"pendingSum":100000}')
  || ' | ' || zz.close('U_KAS2', '{"day":"2027-01-07","counted":1726000,"pendingRefs":[{"ref":"x1","amount":100000}]}')
  || ' | ' || zz.close('U_KAS2', '{"day":"2027-01-07","counted":1726000,"pendingRefs":[{"ref":"man_g20_00001","amount":50000},{"ref":"man_g20_00001","amount":50000}]}'),
  '^ERR 22023 \[kassa:pending_refs\] Hali o''tkazilmagan yozuvlar endi ro''yxat bilan yuboriladi.* \| ERR 22023 \[kassa:pending_refs\] Qurilma navbatidagi yozuv kaliti noto''g''ri .* \| ERR 22023 \[kassa:pending_refs\] Qurilma navbatidagi yozuv ikki marta ko''rsatilgan \(man_g20_00001\)$');
select zz.put('G20', zz.close('U_KAS2', '{"day":"2027-01-07","counted":1726000,"pendingRefs":[{"ref":"man_g20_00001","amount":100000}],"denoms":{"100000":17,"5000":5,"1000":1}}'));
select zz.chk('G20b qurilmada 100 000 lik yozuv hali o''tkazilmagan: farq 0, kun oxiri (hisobda) 1 626 000, sanalgan 1 726 000',
  (select trim_scale(diff) || ':' || trim_scale(closing) || ':' || trim_scale(counted) || ':' || "pendingCount" from public.cash_days where day = '2027-01-07'), '^0:1626000:1726000:1$');
select zz.chk('G21 tekshirish tartib bilan: avval 06.01', zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-07', true)::text$q$), '^ERR P0001 \[kassa:verify_order\]');
-- Xesh nazorati: yopilgan kun hujjati bazada «jimgina» o'zgartirilsa — tekshiruv to'xtaydi
set local session_replication_role = replica;
update public.cash_docs set amount = amount + 1 where id = (select zz.id('G12'));
set local session_replication_role = origin;
select zz.chk('G22 yopilgan kun hujjati o''zgartirilgan bo''lsa tekshiruv to''xtaydi (xesh)', zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-06', true)::text$q$), '^ERR P0001 \[kassa:hash\]');
set local session_replication_role = replica;
update public.cash_docs set amount = amount - 1 where id = (select zz.id('G12'));
set local session_replication_role = origin;
-- (state-2: 07.01 qurilma navbatidagi hali kelmagan yozuv bilan yopilgan — endi izohsiz tekshirilmaydi; izoh bilan — o'tadi)
select zz.chk('G22b tiklangach tekshiruv o''tadi (06.01, keyin 07.01 — hali kelmagan navbat yozuvi bor: izohsiz rad, izoh bilan o''tadi)',
  left(zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-06', true)::text$q$), 0) || zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-07', true)::text$q$)
  || ' | ' || zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-07', true, 'Navbatdagi to''lov hali yuborilmagan, kassir bilan aniqlanadi')::text$q$),
  '^ERR 22023 \[kassa:pending_note\] Kun hali o''tkazilmagan yozuvlar bilan yopilgan: qurilma navbatidagi 1 ta yozuvning \(100000 so''m\) kirim orderi hali kelmagan\..* \| .*"status": "verified"');

-- Yil chegarasi: raqamlar va varaqlar yangi yilda 1 dan
select zz.clock('2027-12-31 11:00+05');
select zz.put('G23', zz.rcpt('U_KAS2', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"Chek 009","clientRef":"g23-00001"}', zz.id('cp_bank'))));
select zz.chk('G23 31.12.2027: raqam davom etadi', (select year || ':' || no from public.cash_docs where id = zz.id('G23')), '^2027:15$');
select zz.put('G23b', zz.close('U_KAS2', '{"day":"2027-12-31","counted":1627000}'));
select zz.chk('G23b 31.12 yopildi (varaq 5)', (select v from zz.v where k = 'G23b') || ' / ' || (select "sheetFrom" from public.cash_days where day = '2027-12-31'), '"status": "closed".* / 5$');
select zz.clock('2028-01-03 09:00+05');
select zz.put('G24', zz.rcpt('U_KAS2', format('{"op":"in_bank","amount":2000,"partyType":"bank","partyId":"%s","basis":"Chek 010","clientRef":"g24-00001"}', zz.id('cp_bank'))));
select zz.chk('G24 2028-yil: KO-1 № 1 dan, kun boshi 31.12 oxiri', (select c.year || ':' || c.no || ':' || trim_scale(d.opening) from public.cash_docs c join public.cash_days d on d.id = c."dayId" where c.id = zz.id('G24')), '^2028:1:1627000$');
select zz.put('G24b', zz.close('U_KAS2', '{"day":"2028-01-03","counted":1629000}'));
select zz.chk('G24b 2028: varaqlar 1 dan', (select v from zz.v where k = 'G24b') || ' / ' || (select "sheetFrom" from public.cash_days where day = '2028-01-03'), '"status": "closed".* / 1$');
select zz.chk('G25 raqamlash nazorati: bo''shliq yo''q (2027, 2028)', (select app.kassa_gap_check('main', 2027)::text || app.kassa_gap_check('main', 2028)::text), '^\[\]\[\]$');
select zz.chk('G25b har seriyada: hisoblagich = hujjatlar soni = eng katta raqam',
  (select string_agg(k.series || k.year || ':' || k."lastNo" || '=' || (select count(*) from public.cash_docs c where c.series = k.series and c.year = k.year and c.no is not null)
                     || '=' || (select max(no) from public.cash_docs c where c.series = k.series and c.year = k.year), ',' order by k.year, k.series) from public.doc_counters k),
  '^ACT2027:3=3=3,KO12027:15=15=15,KO22027:9=9=9,KO12028:1=1=1$');
-- Hisoblagich hujjatsiz oshib qolsa (nazariy) — tekshiruv to'xtaydi
select app.kassa_flag(true); select app.kassa_next_no('main', 'KO1', 2028); select app.kassa_flag(false);
select zz.chk('G26 raqamda bo''shliq bo''lsa tekshiruv to''xtaydi',
  left(zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-12-31', true)::text$q$), 0) || zz.as('U_FM', $q$select public.kassa_day_verify('main', '2028-01-03', true)::text$q$), '^ERR P0001 \[kassa:gaps\]');

-- ---------- (H) o'qish funksiyalari ----------
select zz.chk('H1 kun kitobi: hujjatlar soni va kun jami (04.01)',
  zz.as('U_ACC', $q$select jsonb_array_length(b -> 'docs') || ':' || (b -> 'day' ->> 'closing') || ':' || (b -> 'day' ->> 'status') from public.kassa_day_book('main', '2027-01-04') b$q$), '^15:1261000:verified$');
select zz.chk('H2 kun kitobi: statiya bo''yicha jamlar = kirim − chiqim',
  zz.as('U_FM', $q$select trim_scale(sum(case when x ->> 'form' = 'KO1' then (x ->> 'amount')::numeric else -(x ->> 'amount')::numeric end))::text
                     from public.kassa_day_book('main', '2027-01-04') b, jsonb_array_elements(b -> 'byArticle') x$q$), '^761000$');
select zz.chk('H3 kun kitobi: o''qituvchi ko''ra olmaydi', zz.as('U_TCH', $q$select public.kassa_day_book('main', '2027-01-04')::text$q$), '^ERR 42501');
select zz.chk('H4 nazorat ro''yxati: bo''shliq ko''rinadi, tekshirilmagan kun 1 ta',
  zz.as('U_DIR', $q$select jsonb_array_length(c -> 'gaps') || ':' || jsonb_array_length(c -> 'unverifiedDays') || ':' || (c ->> 'voids30') from public.kassa_checks('main') c$q$), '^1:1:');
select zz.chk('H5 holat: g''aznachi — kassa operatori', zz.as('U_TRE', $q$select (s -> 'me' ->> 'operator') from public.kassa_state('main') s$q$), '^true$');
select zz.chk('H6 sinov kassasi alohida: o''z boshlang''ich qoldig''i va raqamlari',
  left(zz.as('U_DIR', $q$select public.kassa_opening_set('{"desk":"sinov","amount":0,"startDay":"2028-01-03"}')::text$q$), 0) ||
  zz.rcpt('U_KAS', format('{"desk":"sinov","op":"in_bank","amount":777,"partyType":"bank","partyId":"%s","basis":"Sinov cheki","clientRef":"h6-000001"}', zz.id('cp_bank'))), '"no": 1[,}].*"desk": "sinov"|"desk": "sinov".*"no": 1[,}]');
select zz.chk('H8 ma''lumotnomalar: 22 qoida (+ «Kamomadni qoplash (xodim)», acc-4), 75 statiya, tashkilot, kassirlar',
  zz.as('U_KAS', $q$select jsonb_array_length(r -> 'rules') || ':' || jsonb_array_length(r -> 'articles') || ':' || (r -> 'org' ->> 'id') || ':' || jsonb_array_length(r -> 'operators') from public.kassa_refs() r$q$), '^22:75:main:4$');
select zz.chk('H8b ma''lumotnomalar: o''qituvchi ko''ra olmaydi', zz.as('U_TCH', $q$select public.kassa_refs()::text$q$), '^ERR 42501');
-- Har bir ochiq moliya funksiyasi (public.kassa_* / fin_*) bo'sh ma'lumot bilan chaqirilganda ham AVVAL ruxsatni tekshiradi:
--   begona rol (o'qituvchi, zavuch) va bloklangan hisob (roli moliya menejeri + kassir bo'lsa ham) faqat «ruxsat yo'q» (42501) oladi.
select zz.chk('H9 barcha ochiq moliya funksiyalari begona rol va bloklangan hisobga avval «ruxsat yo''q» deydi (ma''lumot tekshiruvidan oldin)',
  (select count(*) filter (where q.r !~ '^ERR 42501') || '/' || (count(*) >= 96)::text from (
     select zz.as(u.id, 'select public.' || quote_ident(p.proname) || '(' ||
              coalesce((select string_agg(case when format_type(a.oid, null) = 'jsonb' then $x$'{}'::jsonb$x$ else 'null::' || format_type(a.oid, null) end, ', ' order by a.ord)
                          from unnest(p.proargtypes::oid[]) with ordinality as a(oid, ord)), '') || ')::text') as r
       from pg_proc p cross join (values ('U_TCH'), ('U_ZAV'), ('U_BLK')) u(id)
      where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(kassa|fin_)') q), '^0/true$');
select zz.chk('H8c imzo egasi sifatida bog''lanadigan hisoblar ro''yxati — faqat Direktorga (kassirga bo''sh)',
  zz.as('U_DIR', $q$select (select count(*) from jsonb_array_elements(r -> 'signers') x where x ->> 'uid' in ('U_DIR', 'U_FM'))::text || ':' ||
                          (select count(*) from jsonb_array_elements(r -> 'signers') x where x ->> 'uid' in ('U_KAS', 'U_TCH'))::text from public.kassa_refs() r$q$) || ' | ' ||
  zz.as('U_KAS', $q$select jsonb_array_length(r -> 'signers')::text from public.kassa_refs() r$q$), '^2:0 \| 0$');
select zz.chk('H9 xodimlar ro''yxati: faqat kalit, ism, lavozim', zz.as('U_KAS', $q$select string_agg((x ->> 'ref') || '=' || (x ->> 'name'), ',' order by x ->> 'ref') from jsonb_array_elements(public.kassa_people()) x$q$),
  '^staff:st1=Sinov Xodim,teachers:tch1=Sinov O''qituvchi$');
select zz.chk('H9b xodimlar ro''yxati: o''qituvchi ko''ra olmaydi', zz.as('U_TCH', $q$select public.kassa_people()::text$q$), '^ERR 42501');
select zz.chk('H10 sahifa ma''lumoti bir chaqiruvda: holat, kunlar, so''rovlar, ismlar',
  zz.as('U_FM', $q$select (o -> 'state' ->> 'today') || ':' || jsonb_array_length(o -> 'days') || ':' || jsonb_array_length(o -> 'requests') || ':' || (jsonb_typeof(o -> 'names')) from public.kassa_overview('main') o$q$),
  '^2028-01-03:6:1:object$');
select zz.chk('H10b sahifa ma''lumoti: o''qituvchi ko''ra olmaydi', zz.as('U_TCH', $q$select public.kassa_overview('main')::text$q$), '^ERR 42501');
select zz.chk('H7 o''zgarishlar tarixi yoziladi (hujjat holati)', (select (count(*) > 0)::text from public.change_log where tbl = 'cash_docs'), '^true$');

-- ---------- (I) qo'shimcha: qarordan keyin qayta ochish; band kalitlar (sinov kassasida) ----------
select zz.put('I1', zz.close('U_KAS', '{"desk":"sinov","day":"2028-01-03","counted":700}'));
select zz.chk('I1 sinov kassasi: kamomad −77', (select trim_scale(diff)::text from public.cash_days where desk = 'sinov'), '^-77$');
select zz.put('I2', zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L)::text', (select "diffDocId" from public.cash_days where desk = 'sinov'), 'writeoff', 'Aybdor aniqlanmadi')));
select zz.chk('I2 qaror: hisobdan chiqarish — dalolatnoma Dt 9430 Kt 5910',
  (select c.decision || ':' || a.status || ':' || l.debit || '>' || l.credit || '@' || l."articleId"
     from public.cash_docs c join public.cash_docs a on a.id = c."decisionDocId" join public.cash_doc_lines l on l."docId" = a.id
    where c.id = (select d."diffDocId" from public.cash_days d where d.desk = 'sinov')), '^writeoff:posted:9430>5910@EX-45$');
select zz.put('I3', zz.as('U_DIR', $q$select public.kassa_day_reopen('sinov', '2028-01-03', 'Qayta sanash (sinov)')::text$q$));
select zz.chk('I3 qarordan keyin qayta ochilsa: kamomad hujjati ham, qaror dalolatnomasi ham bekor',
  (select string_agg(op || ':' || status, ',' order by op) from public.cash_docs where desk = 'sinov' and op in ('out_shortage', 'nc_shortage_dec')),
  '^nc_shortage_dec:void,out_shortage:void$');
select zz.chk('I4 tizim kaliti bilan boshlanadigan clientRef — rad',
  zz.rcpt('U_KAS', format('{"desk":"sinov","op":"in_bank","amount":1,"partyType":"bank","partyId":"%s","basis":"Sinov cheki","clientRef":"shdec_x12345"}', zz.id('cp_bank'))), '^ERR 22023 \[kassa:bad_input\]');
select zz.chk('I5 sinov kassasi asosiy kassa raqamlariga ta''sir qilmadi',
  (select string_agg(desk || ':' || series || ':' || "lastNo", ',' order by desk, series, year) from public.doc_counters where desk = 'sinov'), '^sinov:ACT:1,sinov:KO1:1,sinov:KO2:1$');

-- ---------- (J) chop etish jurnali («НУСХА» belgisi), bitta hujjatni o'qish, varaq qatorlari ----------
select zz.put('j_doc', (select id from public.cash_docs where desk = 'main' and form = 'KO1' and year = 2027 and no = 1));
select zz.chk('J1 hujjatni o''qish: qatorlar, ismlar, chop etilmagan',
  zz.as('U_ACC', format($q$select (g -> 'doc' ->> 'no') || ':' || jsonb_array_length(g -> 'doc' -> 'lines') || ':' || (g -> 'doc' ->> 'prints') || ':' || jsonb_typeof(g -> 'names') || ':' || (g ->> 'isTest') from public.kassa_doc_get(%L) g$q$, (select v from zz.v where k = 'j_doc'))),
  '^1:[1-9]:0:object:false$');
select zz.chk('J1b hujjatni o''qish: o''qituvchi ko''ra olmaydi', zz.as('U_TCH', format('select public.kassa_doc_get(%L)::text', (select v from zz.v where k = 'j_doc'))), '^ERR 42501');
select zz.chk('J1c hujjatni o''qish: yo''q hujjat', zz.as('U_ACC', $q$select public.kassa_doc_get('yoq-hujjat')::text$q$), '^ERR 22023 \[kassa:not_found\]');
select zz.put('J2', zz.as('U_KAS', format('select public.kassa_print_mark(%L, %L)::text', 'doc', (select v from zz.v where k = 'j_doc'))));
select zz.chk('J2 birinchi chop etish — asl nusxa', (select v from zz.v where k = 'J2'), '"mode": "original".*"prior": 0|"prior": 0.*"mode": "original"');
select zz.put('J3', zz.as('U_KAS', format('select public.kassa_print_mark(%L, %L)::text', 'doc', (select v from zz.v where k = 'j_doc'))));
select zz.chk('J3 ikkinchi chop etish — «НУСХА»', (select v from zz.v where k = 'J3'), '"mode": "copy".*"prior": 1|"prior": 1.*"mode": "copy"');
select zz.put('J3b', zz.as('U_FM', format('select public.kassa_print_mark(%L, %L, true)::text', 'doc', (select v from zz.v where k = 'j_doc'))));
select zz.chk('J3b «avvalgisi chiqmadi» — asl nusxa qayta (jurnalda alohida)', (select v from zz.v where k = 'J3b'), '"mode": "reissue".*"prior": 2|"prior": 2.*"mode": "reissue"');
select zz.chk('J4 hujjatda chop etishlar soni', zz.as('U_ACC', format($q$select g -> 'doc' ->> 'prints' from public.kassa_doc_get(%L) g$q$, (select v from zz.v where k = 'j_doc'))), '^3$');
select zz.chk('J5 raqamsiz (so''rov holatidagi) hujjat chop etilmaydi',
  zz.as('U_KAS', format('select public.kassa_print_mark(%L, %L)::text', 'doc', (select id from public.cash_docs where desk = 'main' and status in ('draft', 'approved') limit 1))), '^ERR 22023 \[kassa:print\]');
select zz.chk('J5b o''qituvchi chop etishni qayd qila olmaydi', zz.as('U_TCH', format('select public.kassa_print_mark(%L, %L)::text', 'doc', (select v from zz.v where k = 'j_doc'))), '^ERR 42501');
select zz.chk('J5c noto''g''ri tur', zz.as('U_KAS', format('select public.kassa_print_mark(%L, %L)::text', 'varaq', (select v from zz.v where k = 'j_doc'))), '^ERR 22023 \[kassa:bad_input\]');
select zz.chk('J6 nazorat ro''yxati: asl nusxa qayta chiqarilgani ko''rinadi', zz.as('U_DIR', $q$select c ->> 'reissues30' from public.kassa_checks('main') c$q$), '^1$');
-- kassa kitobi varag'i: ochiq kunda — faqat qoralama (qayd qilinmaydi); yopilgach — asl nusxa; qayta ochib yopilsa — yangi asl nusxa, «АЛМАШТИРИЛДИ»
select zz.chk('J7 ochiq kun varag''i qayd qilinmaydi (qoralama)',
  zz.as('U_KAS', format('select public.kassa_print_mark(%L, %L)::text', 'book', (select id from public.cash_days where desk = 'sinov'))), '^ERR 22023 \[kassa:print\]');
select zz.put('J8', zz.close('U_KAS', '{"desk":"sinov","day":"2028-01-03","counted":777}'));
select zz.chk('J8 sinov kuni qayta yopildi (farq yo''q), varaq qatorlari soni saqlandi',
  (select status || ':' || trim_scale(diff) || ':' || "sheetRows" || ':' || "reopenCount" from public.cash_days where desk = 'sinov'), '^closed:0:30:1$');
select zz.put('J9', zz.as('U_KAS', format('select public.kassa_print_mark(%L, %L)::text', 'book', (select id from public.cash_days where desk = 'sinov'))));
select zz.chk('J9 yopilgan kun varag''i — asl nusxa (eski nusxasi chop etilmagan)', (select v from zz.v where k = 'J9'), '"mode": "original".*"replaced": false|"replaced": false.*"mode": "original"');
select zz.put('J10a', zz.as('U_DIR', $q$select public.kassa_day_reopen('sinov', '2028-01-03', 'Qayta sanash (chop etish sinovi)')::text$q$));
select zz.put('J10b', zz.close('U_KAS', '{"desk":"sinov","day":"2028-01-03","counted":777}'));
select zz.put('J10', zz.as('U_KAS', format('select public.kassa_print_mark(%L, %L)::text', 'book', (select id from public.cash_days where desk = 'sinov'))));
select zz.chk('J10 qayta ochib yopilgan kun varag''i — yangi asl nusxa, eskisi almashtirildi', (select v from zz.v where k = 'J10'),
  '"mode": "original".*"prior": 0.*"replaced": true|"replaced": true.*"mode": "original"');
select zz.put('J11', zz.as('U_KAS', format('select public.kassa_print_mark(%L, %L)::text', 'book', (select id from public.cash_days where desk = 'sinov'))));
select zz.chk('J11 varaqni qayta chop etish — «НУСХА»; kun ma''lumotida sonlar',
  (select v from zz.v where k = 'J11') || ' / ' || zz.as('U_DIR', $q$select (b -> 'day' ->> 'prints') || ':' || (b -> 'day' ->> 'printsOld') || ':' || (b ->> 'isTest') || ':' || jsonb_typeof(b -> 'names') from public.kassa_day_book('sinov', '2028-01-03') b$q$),
  '"mode": "copy".* / 2:1:true:object$');
select zz.chk('J12 chop etish jurnali: o''zgartirish va o''chirish yo''q', zz.try($q$update public.cash_prints set mode = 'original'$q$) || ' | ' || zz.try($q$delete from public.cash_prints$q$),
  '^ERR 42501 \[kassa:immutable\].* \| ERR 42501 \[kassa:immutable\]');
select zz.chk('J12b chop etish jurnali: funksiyasiz yozish yo''q',
  zz.try(format($q$insert into public.cash_prints (id, kind, "docId", desk, mode) values ('x1', 'doc', %L, 'main', 'original')$q$, (select v from zz.v where k = 'j_doc'))) || ' | ' ||
  zz.as('U_KAS', format($q$insert into public.cash_prints (id, kind, "docId", desk, mode) values ('x2', 'doc', %L, 'main', 'original') returning id$q$, (select v from zz.v where k = 'j_doc'))),
  '^ERR 42501 \[kassa:rpc_only\].* \| ERR 42501');
select zz.chk('J13 asosiy kassa: yopilgan kunda varaq qatorlari soni saqlangan (30)',
  (select string_agg(distinct "sheetRows"::text, ',') from public.cash_days where desk = 'main' and status <> 'open'), '^30$');

-- ---------- (K) kamomadni qoplash (xodim) — acc-4: Dt 5010 Kt 4730 (OP-22), xodim zimmasidagi qoldiqdan oshmaydi ----------
--   G17: 06.01.2027 dagi 10 000 kamomad Direktor qarori bilan kassir-o'qituvchi (teachers:tch1) zimmasiga yozilgan (Dt 4730 Kt 5910).
select zz.clock('2028-01-04 10:00+05');
create or replace function zz.dmg() returns jsonb language sql as $$
  select zz.as('U_FM', $q$select (public.kassa_checks('main') -> 'damage')::text$q$)::jsonb $$;
select zz.chk('K1 RP-06: xodim zimmasidagi kamomad 10 000 — nazorat ro''yxatida (xodim kartasiga bog''langan)',
  (select string_agg((x ->> 'partyId') || ':' || (x ->> 'name') || ':' || trim_scale((x ->> 'charged')::numeric) || ':' || trim_scale((x ->> 'repaid')::numeric)
                     || ':' || trim_scale((x ->> 'balance')::numeric) || ':' || (x ->> 'linked') || ':' || (x ->> 'since'), ',') from jsonb_array_elements(zz.dmg()) x),
  '^teachers:tch1:Sinov O''qituvchi:10000:0:10000:true:2027-01-07$');
select zz.chk('K2 qoplash qoldiqdan katta — rad; «boshqa» tomon — rad (faqat xodim); iz qolmaydi',
  zz.rcpt('U_KAS2', $q${"op":"in_damage_repay","amount":10001,"partyType":"employee","partyId":"teachers:tch1","basis":"Tushuntirish xati","clientRef":"k2-000001"}$q$) || ' | '
  || zz.rcpt('U_KAS2', $q${"op":"in_damage_repay","amount":1000,"partyType":"other","partyName":"Sinov Kassir","basis":"Tushuntirish xati","clientRef":"k2-000002"}$q$) || ' | '
  || (select count(*) from public.cash_docs where op = 'in_damage_repay'),
  '^ERR P0001 \[kassa:damage_over\].*qoldiq 10000 so''m.* \| ERR 22023 \[kassa:party\].* \| 0$');
select zz.put('K3', zz.rcpt('U_KAS2', $q${"op":"in_damage_repay","amount":4000,"partyType":"employee","partyId":"teachers:tch1","basis":"Tushuntirish xati, 04.01.2028","clientRef":"k3-000001"}$q$));
select zz.chk('K3 kamomad qisman qoplandi: KO-1, Dt 5010 Kt 4730 (OP-22); qoldiq 6 000 — kassir oynasida ham, RP-06 da ham',
  ((select v from zz.v where k = 'K3')::jsonb ->> 'status') || ':' || (select string_agg(l.debit || '>' || l.credit || '@' || l."articleId", ',') from public.cash_doc_lines l where l."docId" = zz.id('K3'))
  || ' | ' || (zz.as('U_KAS2', $q$select public.kassa_staff_open('main', 'teachers:tch1')::text$q$)::jsonb ->> 'damage')
  || ':' || (select string_agg(trim_scale((x ->> 'repaid')::numeric) || '/' || trim_scale((x ->> 'balance')::numeric), ',') from jsonb_array_elements(zz.dmg()) x),
  '^posted:5010>4730@OP-22 \| 6000:4000/6000$');
select zz.chk('K4 ikkinchi qoplash qolgan 6 000 dan katta — rad',
  zz.rcpt('U_KAS2', $q${"op":"in_damage_repay","amount":6001,"partyType":"employee","partyId":"teachers:tch1","basis":"Tushuntirish xati","clientRef":"k4-000001"}$q$),
  '^ERR P0001 \[kassa:damage_over\].*qoldiq 6000 so''m');
select zz.put('K5', zz.void('U_KAS2', zz.id('K3'), 'Summa xato yozildi'));
select zz.chk('K5 shu kunda bekor qilindi — qoldiq yana 10 000', ((select v from zz.v where k = 'K5')::jsonb ->> 'status') || ':' || trim_scale(app.kassa_damage_open('teachers:tch1')), '^void:10000$');
select zz.put('K6', zz.rcpt('U_KAS2', $q${"op":"in_damage_repay","amount":10000,"partyType":"employee","partyId":"teachers:tch1","basis":"Tushuntirish xati, 04.01.2028","clientRef":"k6-000001"}$q$));
select zz.chk('K6 to''liq qoplandi — nazorat ro''yxatidan chiqdi', ((select v from zz.v where k = 'K6')::jsonb ->> 'status') || ':' || jsonb_array_length(zz.dmg()), '^posted:0$');
select zz.chk('K7 xodim qoldiqlari (kirim shakli uchun): faqat kirim yozuvchilarga — Moliya menejeri, o''qituvchi — yo''q; noto''g''ri oy — rad',
  zz.as('U_FM', $q$select public.kassa_staff_open('main', 'teachers:tch1')::text$q$) || ' | ' || zz.as('U_TCH', $q$select public.kassa_staff_open('main', 'teachers:tch1')::text$q$)
  || ' | ' || zz.as('U_KAS2', $q$select public.kassa_staff_open('main', 'teachers:tch1', '2027-13')::text$q$),
  '^ERR 42501.* \| ERR 42501.* \| ERR 22023 \[kassa:month\]');

-- ---------- (L) vazifalar ajratilishi: pul oluvchi ≠ tasdiqlovchi (sec-1), tasdiqlovchi ≠ pul beruvchi (sec-5), kontragent turi (sec-3) ----------
--   Moliya menejeri (U_FM) va buxgalter (U_ACC) xodim kartalariga bog'lanadi (st2, st3), Direktor — st4; U_FMK — Moliya menejeri + qo'shimcha
--   «kassir» lavozimi. Kassa: 04.01.2028 ochiq kun (kassir U_KAS2). Yuridik shaxsga naqd chegarasi — 0 (har doim Direktor).
set local session_replication_role = replica;
insert into public.staff (id, "staffId", name, position) values ('st2','IQX-T2','Sinov Moliyachi','Moliya menejeri'), ('st3','IQX-T3','Sinov Hisobchi','Buxgalter'),
  ('st4','IQX-T4','Sinov Rahbar','Direktor');
update public.users set "staffRefType" = 'staff', "staffRefId" = 'st2' where id = 'U_FM';
update public.users set "staffRefType" = 'staff', "staffRefId" = 'st3' where id = 'U_ACC';
update public.users set "staffRefType" = 'staff', "staffRefId" = 'st4' where id = 'U_DIR';
insert into public.users (id, email, role, status, "extraRoles") values ('U_FMK','fk@x','finance_mgr','active','["kassir"]');
-- U_FMK ning ikkinchi lavozim kartasi — faqat teskari havola bilan (teachers."userUid"; users.staffRefId bo'sh); st6 — hech kimga bog'lanmagan xodim
insert into public.teachers (id, "teacherId", name, pauses, "userUid") values ('tch5','IQT-T5','Sinov Ikkinchi Lavozim','[]','U_FMK');
insert into public.staff (id, "staffId", name, position) values ('st6','IQX-T6','Sinov Farrosh','Farrosh');
set local session_replication_role = origin;
select zz.put('L0', zz.as('U_DIR', $q$select (public.fin_org_set('{"orgCashMax":0}') -> 'extra' ->> 'orgCashMax')$q$));
-- sec-1: tasdiqlovchi ≠ pul oluvchi xodim
select zz.put('L0q', zz.as('U_FM', $q$select public.kassa_state('main') #>> '{pending,toApprove}'$q$) || '/' || zz.as('U_ACC', $q$select public.kassa_state('main') #>> '{pending,toApprove}'$q$));
select zz.put('L1', zz.preq('U_KAS2', $q${"op":"out_accountable","amount":100000,"partyType":"employee","partyId":"staff:st2","basis":"Xo'jalik xaridi","clientRef":"l1-000001"}$q$));
select zz.chk('L1 sec-1: Moliya menejeri o''z kartasiga beriladigan avansni tasdiqlay olmaydi (ko''rik ssenariysi); hujjat o''zgarmadi',
  zz.appr('U_FM', zz.id('L1')) || ' | ' || (select status || ':' || coalesce("approvedBy", '-') from public.cash_docs where id = zz.id('L1')),
  '^ERR 42501 \[kassa:self_party\] O''zingizga \(bog''langan xodim kartangizga\) beriladigan pulni o''zingiz tasdiqlay olmaysiz.* \| draft:-$');
select zz.chk('L1c navbat: o''z kartasiga beriladigan so''rov Moliya menejeri navbatiga qo''shilmadi, buxgalter navbatiga qo''shildi; holatda bog''langan karta',
  ((split_part(zz.get('L0q'), '/', 1)::int = zz.as('U_FM', $q$select public.kassa_state('main') #>> '{pending,toApprove}'$q$)::int)
   and (split_part(zz.get('L0q'), '/', 2)::int + 1 = zz.as('U_ACC', $q$select public.kassa_state('main') #>> '{pending,toApprove}'$q$)::int))::text
  || ':' || zz.as('U_FM', $q$select public.kassa_state('main') #>> '{me,cards}'$q$), '^true:\["staff:st2"\]$');
select zz.put('L1b', zz.f(zz.appr('U_ACC', zz.id('L1')), 'status') || ':' || zz.f(zz.pay('U_KAS2', zz.id('L1')), 'status'));
select zz.chk('L1b boshqa 2-ro''yxat xodimi (buxgalter) tasdiqlaydi, kassir pulni beradi — hisobdorda 100 000',
  zz.get('L1b') || ':' || trim_scale(app.kassa_acc_open('staff:st2')), '^approved:posted:100000$');
select zz.put('L2', zz.preq('U_KAS2', $q${"op":"out_accountable","amount":50000,"partyType":"employee","partyId":"staff:st3","basis":"Kanselyariya","clientRef":"l2-000001"}$q$));
select zz.chk('L2 buxgalter ham o''z kartasiga beriladigan pulni tasdiqlay olmaydi; Moliya menejeri tasdiqlaydi',
  zz.appr('U_ACC', zz.id('L2')) || ' | ' || zz.f(zz.appr('U_FM', zz.id('L2')), 'status'), '^ERR 42501 \[kassa:self_party\].* \| approved$');
select zz.put('L3', zz.preq('U_KAS2', $q${"op":"out_handover","amount":20000,"partyType":"employee","partyId":"staff:st4","basis":"Buyruq № 1","clientRef":"l3-000001"}$q$));
select zz.chk('L3 Direktor tasdig''i bosqichi — o''z kartasiga ham (eng yuqori vakolat): 2-ro''yxat, keyin Direktor — tasdiqlandi',
  zz.f(zz.get('L3'), 'needsDirector') || ':' || zz.f(zz.appr('U_FM', zz.id('L3')), 'status') || ':' || zz.f(zz.appr('U_DIR', zz.id('L3')), 'status'),
  '^true:draft:approved$');
-- sec-1 (rahbar tuzatishi): xodim kartalari — asosiy havola va teskari havola (ikkinchi lavozim kartasi); pul oluvchi 2-ro'yxat xodimi bo'lsa,
--   2-ro'yxat bosqichini Direktor imzolaydi (2-ro'yxatda boshqa xodim bo'lmasa ham so'rov to'xtab qolmaydi); boshqa xodimga — yo'q
select zz.put('L3q', zz.as('U_DIR', $q$select public.kassa_state('main') #>> '{pending,toApprove}'$q$));
select zz.put('L3b', zz.preq('U_KAS2', $q${"op":"out_accountable","amount":10000,"partyType":"employee","partyId":"teachers:tch5","basis":"Laboratoriya xaridi","clientRef":"l3b-00001"}$q$));
select zz.chk('L3b ikkinchi lavozim kartasi (teskari havola): Moliya menejeri unga beriladigan pulni ham o''zi tasdiqlay olmaydi; holatda shu karta',
  zz.appr('U_FMK', zz.id('L3b')) || ' | ' || zz.as('U_FMK', $q$select public.kassa_state('main') #>> '{me,cards}'$q$),
  '^ERR 42501 \[kassa:self_party\].* \| \["teachers:tch5"\]$');
select zz.chk('L3c so''rov Direktor navbatida (2-ro''yxat xodimiga beriladigan pul); 2-ro''yxat xodimlari kartalari faqat Direktorga',
  (zz.as('U_DIR', $q$select public.kassa_state('main') #>> '{pending,toApprove}'$q$)::int - zz.get('L3q')::int)::text || ':'
  || zz.as('U_DIR', $q$select public.kassa_state('main') #>> '{me,l2Cards}'$q$) || ':' || zz.as('U_FM', $q$select public.kassa_state('main') #>> '{me,l2Cards}'$q$),
  '^1:\["staff:st2", "staff:st3", "teachers:tch5"\]:\[\]$');
select zz.put('L3d', zz.appr('U_DIR', zz.id('L3b')));
select zz.put('L3dp', zz.f(zz.pay('U_KAS2', zz.id('L3b')), 'status'));
select zz.chk('L3d pul oluvchi 2-ro''yxat xodimi: 2-ro''yxat bosqichini Direktor imzoladi (Direktor tasdig''i talab qilinmagan), kassir pulni berdi',
  zz.f(zz.get('L3d'), 'status') || ':' || zz.f(zz.get('L3d'), 'approvedBy') || ':' || coalesce(zz.f(zz.get('L3d'), 'dirApprovedBy'), '-') || ':'
  || zz.get('L3dp') || ':' || trim_scale(app.kassa_acc_open('teachers:tch5')), '^approved:U_DIR:-:posted:10000$');
select zz.put('L3e', zz.preq('U_KAS2', $q${"op":"out_accountable","amount":20000,"partyType":"employee","partyId":"teachers:tch5","basis":"Laboratoriya xaridi 2","clientRef":"l3e-00001"}$q$));
select zz.chk('L3e hisobot qilinmagan qoldiq bor (Direktor tasdig''i ham kerak): Direktorning bitta tasdig''i ikkala bosqichni imzolaydi',
  zz.f(zz.get('L3e'), 'needsDirector') || ' | ' || (select zz.f(r, 'status') || ':' || zz.f(r, 'approvedBy') || ':' || zz.f(r, 'dirApprovedBy') from (select zz.appr('U_DIR', zz.id('L3e')) r) q),
  '^true \| approved:U_DIR:U_DIR$');
select zz.put('L3f', zz.preq('U_KAS2', $q${"op":"out_accountable","amount":5000,"partyType":"employee","partyId":"staff:st6","basis":"Xo'jalik xaridi","clientRef":"l3f-00001"}$q$));
select zz.chk('L3f boshqa xodimga beriladigan pulda 2-ro''yxat bosqichi Direktorniki emas; so''rov bekor qilindi',
  zz.f(zz.get('L3f'), 'needsDirector') || ' | ' || zz.appr('U_DIR', zz.id('L3f')) || ' | '
  || zz.f(zz.as('U_KAS2', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('L3f'), 'Sinov: bekor')), 'status')
  || ':' || zz.f(zz.as('U_KAS2', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('L3e'), 'Sinov: bekor')), 'status'),
  '^false \| ERR 42501 \[kassa:no_approval\].* \| cancelled:cancelled$');
-- sec-5: tasdiqlovchi ≠ pul beruvchi (qo'shimcha «kassir» lavozimi bilan ham)
select zz.put('L4', zz.preq('U_KAS2', $q${"op":"out_expense","amount":30000,"partyType":"other","partyName":"Bozor sotuvchisi","noBasis":true,"clientRef":"l4-000001","lines":[{"articleId":"EX-20","amount":30000}]}$q$));
select zz.put('L4r', zz.f(zz.appr('U_FMK', zz.id('L4')), 'status') || ' | ' || zz.pay('U_FMK', zz.id('L4')) || ' | ' || zz.f(zz.pay('U_KAS2', zz.id('L4')), 'status'));
select zz.chk('L4 sec-5: qo''shimcha «kassir» lavozimli Moliya menejeri o''zi tasdiqlagan so''rov pulini bera olmaydi; boshqa kassir beradi',
  zz.get('L4r') || ':' || (select "approvedBy" || '/' || "postedBy" from public.cash_docs where id = zz.id('L4')),
  '^approved \| ERR 42501 \[kassa:self_pay\] Bu so''rovni o''zingiz tasdiqlagansiz.* \| posted:U_FMK/U_KAS2$');
select zz.put('L5', zz.preq('U_KAS2', $q${"op":"out_expense","amount":20000,"partyType":"other","partyName":"Bozor sotuvchisi","noBasis":true,"clientRef":"l5-000001","lines":[{"articleId":"EX-20","amount":20000}]}$q$));
select zz.chk('L5 boshqa xodim tasdiqlagan so''rov pulini qo''shimcha «kassir» lavozimi bilan berish mumkin',
  left(zz.appr('U_FM', zz.id('L5')), 0) || zz.f(zz.pay('U_FMK', zz.id('L5')), 'status'), '^posted$');
-- sec-3: kontragent turini kim belgilaydi — Direktor qoidasi (yuridik shaxsga kassadan naqd) shunga bog'liq
select zz.put('cpL1', zz.as('U_KAS2', $q$select public.fin_counterparty_save(null, 'person', 'Beta Qurilish MChJ', '309876543')::text$q$));
select zz.put('cpL2', zz.as('U_ACC', $q$select public.fin_counterparty_save(null, 'person', 'Sinov YaTT', '301111111')::text$q$));
select zz.put('cpL3', zz.as('U_FM', $q$select public.fin_counterparty_save(null, 'other', 'Sinov Usta')::text$q$));
select zz.put('cpL4', zz.as('U_DIR', $q$select public.fin_counterparty_save(null, 'other', 'Sinov Bog''bon')::text$q$));
select zz.chk('L6 sec-3: kassir / Moliya menejeri kiritgan «jismoniy shaxs» / «boshqa» — tasdiqlanmagan, yuridik shaxs hisoblanadi; buxgalter / Direktor kiritgani — tasdiqlangan',
  (select string_agg(x.k || '=' || coalesce(c."kindConfirmedBy", '-') || ':' || app.kassa_is_org(c.id)::text, ',' order by x.k)
     from (values ('1', zz.id('cpL1')), ('2', zz.id('cpL2')), ('3', zz.id('cpL3')), ('4', zz.id('cpL4'))) x(k, id) join public.fin_counterparties c on c.id = x.id),
  '^1=-:true,2=U_ACC:false,3=-:true,4=U_DIR:false$');
select zz.chk('L6b kassa_refs: tur tasdig''i va «yuridik shaxs» belgisi (sahifa ogohlantirishi server qoidasidan)',
  (select string_agg((c ->> 'confirmed') || '/' || (c ->> 'org'), ',' order by c ->> 'name') from jsonb_array_elements(zz.as('U_KAS2', $q$select public.kassa_refs()::text$q$)::jsonb -> 'counterparties') c
    where c ->> 'id' in (zz.id('cpL1'), zz.id('cpL2'))), '^false/true,true/false$');
select zz.put('L7', zz.preq('U_KAS2', format('{"op":"out_expense","amount":100000,"partyType":"counterparty","partyId":"%s","basis":"Hisob-faktura 13","clientRef":"l7-000001","lines":[{"articleId":"EX-15","amount":100000}]}', zz.id('cpL1'))));
select zz.chk('L7 ko''rik ssenariysi: kassir «jismoniy shaxs» deb kiritgan MChJ ga naqd — Direktor tasdig''i talab qilinadi, buxgalter tasdig''i yetmaydi',
  zz.f(zz.get('L7'), 'needsDirector') || ':' || zz.f(zz.get('L7'), 'orgCash') || ' | ' || zz.f(zz.appr('U_ACC', zz.id('L7')), 'status') || ' | ' || zz.pay('U_KAS2', zz.id('L7')),
  '^true:true \| draft \| ERR 42501 \[kassa:not_approved\]');
select zz.chk('L8 tur tasdig''i: kassir va Moliya menejeri tasdiqlay olmaydi; ko''rilgan tur eskirgan — rad; kontragent yo''q — rad',
  zz.as('U_KAS2', format('select public.fin_counterparty_confirm(%L, %L, %L)::text', zz.id('cpL3'), 'other', 'Sinov Usta')) || ' | '
  || zz.as('U_FM', format('select public.fin_counterparty_confirm(%L, %L, %L)::text', zz.id('cpL3'), 'other', 'Sinov Usta')) || ' | '
  || zz.as('U_ACC', format('select public.fin_counterparty_confirm(%L, %L, %L)::text', zz.id('cpL3'), 'person', 'Sinov Usta')) || ' | '
  || zz.as('U_ACC', format('select public.fin_counterparty_confirm(%L, %L, %L)::text', 'cp_yoq', 'other', 'Sinov')),
  '^ERR 42501.* \| ERR 42501.* \| ERR P0001 \[fin:cp_changed\].* \| ERR 22023 \[fin:not_found\]');
select zz.put('L9', zz.as('U_ACC', format('select public.fin_counterparty_confirm(%L, %L, %L)::text', zz.id('cpL3'), 'other', 'Sinov Usta')));
select zz.chk('L9 buxgalter turini tasdiqladi — endi yuridik shaxs emas; qayta tasdiq — takror',
  zz.f(zz.get('L9'), 'kindConfirmedBy') || ':' || app.kassa_is_org(zz.id('cpL3'))::text || ':'
  || (zz.f(zz.as('U_DIR', format('select public.fin_counterparty_confirm(%L, %L, %L)::text', zz.id('cpL3'), 'other', 'Sinov Usta')), 'dup')), '^U_ACC:false:true$');
select zz.put('L10x', zz.f(zz.as('U_FM', format('select public.fin_counterparty_save(%L, %L, %L, %L, %L)::text', zz.id('cpL2'), 'person', 'Sinov YaTT', '301111111', 'Telefon orqali')), 'kindConfirmedBy'));
select zz.put('L10y', coalesce(zz.f(zz.as('U_FM', format('select public.fin_counterparty_save(%L, %L, %L, %L)::text', zz.id('cpL2'), 'person', 'Gamma Qurilish MChJ', '301111111')), 'kindConfirmedBy'), '-'));
select zz.put('L10z', coalesce(zz.f(zz.as('U_FM', format('select public.fin_counterparty_save(%L, %L, %L)::text', zz.id('cpL4'), 'person', 'Sinov Bog''bon')), 'kindConfirmedBy'), '-'));
select zz.chk('L10 Moliya menejeri izohni o''zgartirsa — tasdiq qoladi; nomini (yoki turini) o''zgartirsa — bekor, yana yuridik shaxs',
  zz.get('L10x') || ' | ' || zz.get('L10y') || ':' || app.kassa_is_org(zz.id('cpL2'))::text || ' | ' || zz.get('L10z') || ':' || app.kassa_is_org(zz.id('cpL4'))::text,
  '^U_ACC \| -:true \| -:true$');
select zz.put('L10w', zz.f(zz.as('U_ACC', format('select public.fin_counterparty_save(%L, %L, %L)::text', zz.id('cpL4'), 'other', 'Sinov Bog''bon')), 'kindConfirmedBy'));
select zz.chk('L10b buxgalter o''zgartirsa — tur shu zahoti tasdiqlangan', zz.get('L10w') || ':' || app.kassa_is_org(zz.id('cpL4'))::text, '^U_ACC:false$');
select zz.chk('L11 ko''rik ssenariysi: Moliya menejeri yetkazib beruvchini «jismoniy shaxs»ga o''zgartirsa ham yangi so''rov Direktorga boradi',
  (zz.f(zz.as('U_FM', format('select public.fin_counterparty_save(%L, %L, %L)::text', zz.id('cp_sup'), 'person', 'Sinov Yetkazuvchi MChJ')), 'kind'))
  || ':' || (zz.f(zz.preq('U_FM', format('{"op":"out_expense","amount":40000,"partyType":"counterparty","partyId":"%s","basis":"Hisob-faktura 14","clientRef":"l11-00001","lines":[{"articleId":"EX-15","amount":40000}]}', zz.id('cp_sup'))), 'needsDirector')),
  '^person:true$');
-- tasdiqdan oldin tur o'zgardi: so'rov yozilganda tasdiqlangan «boshqa» (Direktorsiz) — 2-ro'yxat tasdig'ida Direktor talabi qo'shiladi
select zz.put('L12', zz.preq('U_KAS2', format('{"op":"out_expense","amount":30000,"partyType":"counterparty","partyId":"%s","basis":"Ish dalolatnomasi 3","clientRef":"l12-00001","lines":[{"articleId":"EX-15","amount":30000}]}', zz.id('cpL3'))));
select zz.put('L12e', zz.as('U_FM', format('select public.fin_counterparty_save(%L, %L, %L)::text', zz.id('cpL3'), 'other', 'Sinov Usta MChJ')));
select zz.chk('L12 so''rovdan keyin nomi o''zgardi (tasdiq bekor): 2-ro''yxat tasdig''ida Direktor talabi qo''shildi, pul berilmaydi; Direktor tasdiqlagach — beriladi',
  zz.f(zz.get('L12'), 'needsDirector') || ' | ' || (select zz.f(r, 'status') || ':' || zz.f(r, 'needsDirector') || ':' || zz.f(r, 'orgCash') from (select zz.appr('U_ACC', zz.id('L12')) r) q)
  || ' | ' || zz.pay('U_KAS2', zz.id('L12')) || ' | ' || zz.f(zz.appr('U_DIR', zz.id('L12')), 'status') || ':' || zz.f(zz.pay('U_KAS2', zz.id('L12')), 'status'),
  '^false \| draft:true:true \| ERR 42501 \[kassa:not_approved\].* \| approved:posted$');
-- pul berishda: tasdiqlangandan keyin tur o'zgardi — pul berilmaydi, so'rov Direktorga qaytadi (ok = false), Direktor tasdiqlagach beriladi
select zz.put('L13', zz.preq('U_KAS2', format('{"op":"out_expense","amount":25000,"partyType":"counterparty","partyId":"%s","basis":"Dalolatnoma 4","clientRef":"l13-00001","lines":[{"articleId":"EX-15","amount":25000}]}', zz.id('cpL4'))));
select zz.put('L13a', zz.appr('U_FM', zz.id('L13')));
select zz.put('L13e', zz.as('U_FM', format('select public.fin_counterparty_save(%L, %L, %L)::text', zz.id('cpL4'), 'person', 'Sinov Bog''bon')));
select zz.put('L13n', (select count(*)::text from public.cash_docs where desk = 'main' and status = 'posted') || ':' || zz.bal());
select zz.put('L13p', zz.pay('U_KAS2', zz.id('L13')));
select zz.chk('L13 tasdiqlangan so''rov: pul berishda kontragent yuridik shaxs bo''lib chiqdi — pul berilmadi (ok = false, kassa:org_director), so''rov Direktorga qaytdi, kassa o''zgarmadi',
  zz.f(zz.get('L13'), 'needsDirector') || ':' || zz.f(zz.get('L13a'), 'status')
  || ' | ' || (select zz.f(r, 'ok') || ':' || zz.f(r, 'hint') || ':' || zz.f(r, 'status') || ':' || zz.f(r, 'needsDirector') || ':' || zz.f(r, 'orgCash') || ':' || coalesce(zz.f(r, 'no'), '-')
                 from (select zz.get('L13p') r) q)
  || ' | ' || ((select count(*)::text from public.cash_docs where desk = 'main' and status = 'posted') || ':' || zz.bal() = zz.get('L13n'))::text
  || ' | ' || zz.f(zz.get('L13p'), 'message'),
  '^false:approved \| false:kassa:org_director:draft:true:true:- \| true \| Pul berilmadi: yuridik shaxsga kassadan naqd to''lov qoidasi bo''yicha endi Direktor tasdig''i kerak');
select zz.put('L13b', zz.f(zz.appr('U_DIR', zz.id('L13')), 'status') || ':' || (select zz.f(r, 'status') || ':' || zz.f(r, 'orgCash') from (select zz.pay('U_KAS2', zz.id('L13')) r) q));
select zz.chk('L13b Direktor «So''rovlar»da tasdiqlaydi, kassir pulni beradi; "orgCash" saqlangan, xarajat «Buxgalteriya»da',
  zz.get('L13b') || ':' || (select count(*) from public.expenses where "cashDocId" = zz.id('L13')), '^approved:posted:true:1$');
select zz.chk('L14 himoya (RPC''siz ham): Direktor talabi va nazorat belgisi olib tashlanmaydi; tasdiqlangan hujjat Direktor talabisiz «tasdiq kutilmoqda»ga qaytmaydi',
  zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_docs set "needsDirector" = false where id = %L; end $x$$q$, zz.id('L7'))) || ' | '
  || zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_docs set "orgCash" = false where id = %L; end $x$$q$, zz.id('L7'))) || ' | '
  || zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_docs set status = 'draft' where id = %L; end $x$$q$, zz.id('L2'))),
  '^ERR 42501 \[kassa:immutable\].* \| ERR 42501 \[kassa:immutable\].* \| ERR 22023 \[kassa:bad_doc\]');
select app.kassa_flag(false);
select zz.put('L15', zz.as('U_ACC', format('select public.fin_counterparty_confirm(%L, %L, %L)::text', zz.id('cpL4'), 'person', 'Sinov Bog''bon')));
select zz.chk('L15 to''lovdan keyin tur tasdiqlansa ham o''tgan to''lovlar nazorat ro''yxatida qoladi (hujjatda saqlangan belgi)',
  zz.f(zz.get('L15'), 'kindConfirmedBy') || ':' || app.kassa_is_org(zz.id('cpL4'))::text
  || ':' || (zz.f(zz.as('U_ACC', $q$select (public.kassa_checks('main') -> 'orgCash30')::text$q$), 'count')), '^U_ACC:false:2$');

-- ---------- (M) kassa egasi va smena (g6): kassir o'rniga yopish / topshirish (sec-2), ikki bosqichli smena topshirish (state-6),
--   o'zi o'zgartiradigan ism (sec-4), smena topshirishdagi farq kun varag'ida (acc-6; ko'rsatkichlar — test-kassa-report.sql (HD)) ----------
--   04.01.2028 ochiq kun — kassa egasi U_KAS2 (K bo'limi). U_TRE — g'aznachi, U_HRK — HR + qo'shimcha «kassir» (ikkalasi kartaga bog'lanmagan).
create or replace function zz.hid(p_k text) returns text language sql as $$ select (v::jsonb #>> '{handover,id}') from zz.v where k = p_k $$;
create or replace function zz.ho(p_uid text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_handover(%L::jsonb)::text', p_json)) $$;
create or replace function zz.hacc(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_handover_accept(%L)::text', p_id)) $$;
create or replace function zz.hcan(p_uid text, p_id text, p_reason text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_handover_cancel(%L, %L)::text', p_id, p_reason)) $$;
select zz.put('comm2', '[{"title":"Moliya menejeri","name":"Sinov M"},{"title":"Buxgalter","name":"Sinov B"}]');
select zz.chk('M0 sec-2: kassa egasi bo''lmagan kassir (U_KAS) kunni komissiyasiz yopa olmaydi — kassir o''rniga; xabarda kassa egasi',
  zz.close('U_KAS', format('{"day":"2028-01-04","counted":%s}', zz.bal())), '^ERR 22023 \[kassa:commission\] Kunni kassa egasi — Sinov O''qituvchi — yopadi');
select zz.put('M0b', zz.close('U_KAS2', format('{"day":"2028-01-04","counted":%s}', zz.bal())));
select zz.chk('M0b kassa egasi o''zi komissiyasiz yopadi; kassir va yopgan ismi muzlatildi (sec-4)',
  zz.f(zz.get('M0b'), 'day', 'status') || ':' || zz.f(zz.get('M0b'), 'day', 'cashierName') || ':' || zz.f(zz.get('M0b'), 'day', 'closedByName'), '^closed:Sinov O''qituvchi:Sinov O''qituvchi$');
-- 05.01: U_KAS kassa egasi; boshqa kassir komissiya bilan yopadi, kamomad
select zz.clock('2028-01-05 09:00+05');
select zz.put('M1', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":300000,"partyType":"bank","partyId":"%s","basis":"Chek M1","clientRef":"m1-000001"}', zz.id('cp_bank'))));
select zz.chk('M1 kassa egasi — kunning birinchi hujjatini o''tkazgan kassir, ismi muzlatildi', (select "cashierUid" || ':' || "cashierName" from public.cash_days where day = '2028-01-05'), '^U_KAS:Sinov Xodim$');
select zz.put('M2', zz.close('U_KAS2', format('{"day":"2028-01-05","counted":%s,"commission":%s}', zz.bal()::numeric - 30000, zz.get('comm2'))));
select zz.chk('M2 boshqa kassir komissiya bilan yopdi (kamomad 30 000): hujjat suratida va dalolatnomada kassa egasi va sanagan xodim alohida, ismlari bilan',
  zz.f(zz.get('M2'), 'diff') || ' | ' || (select (c."sourceSnapshot" ->> 'cashierUid') || ':' || (c."sourceSnapshot" ->> 'countedBy') || ':' || (c."sourceSnapshot" -> 'names' ->> 'U_KAS')
                                                 || ':' || (c."sourceSnapshot" -> 'names' ->> 'U_KAS2') from public.cash_docs c where c.id = (select "diffDocId" from public.cash_days where day = '2028-01-05'))
  || ' | ' || (select n."cashierUid" || ':' || n."byUid" || ':' || (n.names ->> 'U_KAS') from public.cash_counts n where n."dayId" = 'cd_main_2028-01-05' and n.kind = 'close'),
  '^-30000 \| U_KAS:U_KAS2:Sinov Xodim:Sinov O''qituvchi \| U_KAS:U_KAS2:Sinov Xodim$');
select zz.chk('M3 qaror oynasi: kassa egasi o''zi sanamagan — standart javobgar yo''q; «xodim zimmasiga» kartasiz — rad (Direktor tanlaydi)',
  zz.as('U_DIR', $q$select string_agg((x ->> 'cashierUid') || ':' || (x ->> 'countedBy') || ':' || (x ->> 'kind') || ':' || coalesce(x ->> 'defaultParty', '-'), ',')
                     from jsonb_array_elements(public.kassa_overview('main') -> 'shortages') x where x ->> 'day' = '2028-01-05'$q$)
  || ' | ' || zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2028-01-05'), 'employee', 'Komissiya dalolatnomasi bilan')),
  '^U_KAS:U_KAS2:close:- \| ERR 22023 \[kassa:shortage_party\] Pulni kassa egasining o''zi sanamagan \(kassir o''rniga sanalgan\) — javobgar xodim kartasini tanlang$');
select zz.chk('M3b noto''g''ri karta — rad (kassa:party)',
  zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2028-01-05'), 'employee', 'Komissiya dalolatnomasi bilan', 'staff:yoq')),
  '^ERR 22023 \[kassa:party\]');
select zz.put('M3c', zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2028-01-05'), 'employee', 'Komissiya dalolatnomasi bilan', 'staff:st1')));
select zz.chk('M3c Direktor tanlagan karta (staff:st1): dalolatnoma tomoni — xodim kartasi va uning ismi; takror — dup; boshqa karta bilan — rad',
  (select a."partyType" || ':' || a."partyId" || ':' || a."partyName" || ':' || l.debit || '>' || l.credit from public.cash_docs a join public.cash_doc_lines l on l."docId" = a.id
    where a.id = zz.f(zz.get('M3c'), 'act', 'id'))
  || ' | ' || zz.f(zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2028-01-05'), 'employee', 'Takror', 'staff:st1')), 'dup')
  || ' | ' || zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2028-01-05'), 'employee', 'Boshqa xodim', 'teachers:tch1')),
  '^employee:staff:st1:Sinov Xodim:4730>5910 \| true \| ERR P0001 \[kassa:decided\]');
-- 06.01: Direktor favqulodda birinchi hujjati; ikki bosqichli smena topshirish (ortiqcha 5 000), qabul kutilayotganda kassa to'xtaydi
select zz.clock('2028-01-06 09:00+05');
select zz.put('M4', zz.rcpt('U_DIR', format('{"op":"in_bank","amount":100000,"partyType":"bank","partyId":"%s","basis":"Chek M4","clientRef":"m4-000001"}', zz.id('cp_bank'))));
select zz.put('M4a', coalesce((select "cashierUid" from public.cash_days where day = '2028-01-06'), '-'));
select zz.put('M4b', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":50000,"partyType":"bank","partyId":"%s","basis":"Chek M4b","clientRef":"m4-000002"}', zz.id('cp_bank'))));
select zz.chk('M4 Direktor hujjati bilan ochilgan kunda kassa egasi yo''q; birinchi kassir hujjati bilan belgilanadi',
  zz.get('M4a') || ' | ' || (select "cashierUid" || ':' || "cashierName" from public.cash_days where day = '2028-01-06'), '^- \| U_KAS:Sinov Xodim$');
select zz.put('M5c', (zz.bal()::numeric + 5000)::text);
select zz.put('M5', zz.ho('U_KAS', format('{"counted":%s,"toUid":"U_KAS2","note":"Tushlik"}', zz.get('M5c'))));
select zz.chk('M5 state-6: smena topshirish yozildi — qabul kutilmoqda: kassa egasi o''zgarmadi, farq hujjati va dalolatnoma hali yo''q; ismlar muzlatildi',
  zz.f(zz.get('M5'), 'pending') || ':' || zz.f(zz.get('M5'), 'diff') || ':' || zz.f(zz.get('M5'), 'handover', 'status') || ':' || zz.f(zz.get('M5'), 'handover', 'fromUid')
  || '>' || zz.f(zz.get('M5'), 'handover', 'toUid') || ':' || zz.f(zz.get('M5'), 'handover', 'names', 'U_KAS2')
  || ' | ' || (select "cashierUid" from public.cash_days where day = '2028-01-06') || ':' || (select count(*) from public.cash_counts where "dayId" = 'cd_main_2028-01-06')
  || ':' || (select count(*) from public.cash_docs where "dayId" = 'cd_main_2028-01-06' and op = 'in_surplus'),
  '^true:5000:pending:U_KAS>U_KAS2:Sinov O''qituvchi \| U_KAS:0:0$');
select zz.put('M5n', (select count(*)::text from public.cash_docs where "dayId" = 'cd_main_2028-01-06' and status = 'posted') || ':' || zz.bal());
select zz.put('M6q', zz.preq('U_KAS2', $q${"op":"out_expense","amount":20000,"partyType":"other","partyName":"Bozor sotuvchisi","noBasis":true,"clientRef":"m6-000001","lines":[{"articleId":"EX-20","amount":20000}]}$q$));
select zz.put('M6a', zz.f(zz.appr('U_FM', zz.id('M6q')), 'status'));
select zz.chk('M6 qabul kutilayotganda: kirim (qabul qiluvchi ham), bekor qilish, so''rov puli, kunni yopish — rad (kassa:handover_pending); so''rov yozish va tasdiq — mumkin; kassa o''zgarmadi',
  zz.rcpt('U_KAS2', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"Chek M6","clientRef":"m6-000002"}', zz.id('cp_bank')))
  || ' | ' || left(zz.void('U_KAS', zz.id('M4b'), 'Summa xato yozildi'), 40) || ' | ' || left(zz.pay('U_KAS', zz.id('M6q')), 40)
  || ' | ' || left(zz.close('U_KAS', format('{"day":"2028-01-06","counted":%s}', zz.get('M5c'))), 40)
  || ' | ' || zz.f(zz.get('M6q'), 'status') || ':' || zz.get('M6a')
  || ' | ' || ((select count(*)::text from public.cash_docs where "dayId" = 'cd_main_2028-01-06' and status = 'posted') || ':' || zz.bal() = zz.get('M5n'))::text,
  '^ERR P0001 \[kassa:handover_pending\] Smena topshirilmoqda \(Sinov Xodim → Sinov O''qituvchi, sanalgan [0-9]+ so''m\): qabul qiluvchi o''z hisobidan «Qabul qildim» deguncha.* \| ERR P0001 \[kassa:handover_pending\].* \| ERR P0001 \[kassa:handover_pending\].* \| ERR P0001 \[kassa:handover_pending\].* \| draft:approved \| true$');
select zz.chk('M7 ikkinchi topshirish — rad; aynan o''sha so''rov qayta (javob yetmagan) — o''sha topshirish',
  zz.ho('U_KAS', format('{"counted":%s,"toUid":"U_TRE"}', zz.get('M5c'))) || ' | '
  || (select zz.f(r, 'dup') || ':' || (zz.f(r, 'handover', 'id') = zz.hid('M5'))::text from (select zz.ho('U_KAS', format('{"counted":%s,"toUid":"U_KAS2","note":"Tushlik"}', zz.get('M5c'))) r) q),
  '^ERR P0001 \[kassa:handover_pending\].* \| true:true$');
select zz.chk('M8 holat: kutilayotgan topshirish, «hujjat yozilmaydi» (blockReason handover)',
  zz.as('U_KAS2', $q$select (s ->> 'canPost') || ':' || (s ->> 'blockReason') || ':' || (s -> 'handover' ->> 'fromUid') || '>' || (s -> 'handover' ->> 'toUid') || ':' || (s -> 'handover' ->> 'diff') from public.kassa_state('main') s$q$),
  '^false:handover:U_KAS>U_KAS2:5000$');
select zz.chk('M9 qabul: faqat qabul qiluvchi o''z hisobidan — Direktor (kassir emas), topshiruvchi va boshqa kassir — rad',
  zz.hacc('U_DIR', zz.hid('M5')) || ' | ' || zz.hacc('U_KAS', zz.hid('M5')) || ' | ' || zz.hacc('U_TRE', zz.hid('M5')),
  '^ERR 42501 \[\] Ruxsat yo''q.* \| ERR 42501 \[kassa:handover_receiver\] Smenani faqat qabul qiluvchi kassir — Sinov O''qituvchi — o''z hisobidan qabul qiladi \| ERR 42501 \[kassa:handover_receiver\]');
select zz.put('M10', zz.hacc('U_KAS2', zz.hid('M5')));
select zz.chk('M10 qabul qilindi: dalolatnoma (kassa egasi va sanagan — topshiruvchi, qabul qiluvchi), ortiqcha 5 000 hujjati topshiruvchi nomidan, kassa egasi — qabul qiluvchi',
  zz.f(zz.get('M10'), 'diff') || ':' || zz.f(zz.get('M10'), 'handover', 'status')
  || ' | ' || (select n.kind || ':' || n."cashierUid" || ':' || n."byUid" || ':' || n."fromUid" || '>' || n."toUid" || ':' || trim_scale(n.diff) || ':' || (n."handoverId" = zz.hid('M5'))::text
                 from public.cash_counts n where n."dayId" = 'cd_main_2028-01-06')
  || ' | ' || (select c.op || ':' || trim_scale(c.amount) || ':' || (c."sourceSnapshot" ->> 'cashierUid') || ':' || (c."sourceSnapshot" ->> 'countedBy') || ':' || (c."sourceSnapshot" ->> 'toUid')
                      || ':' || c.status || ':' || c."createdBy" from public.cash_docs c where c.id = zz.f(zz.get('M10'), 'handover', 'diffDocId'))
  || ' | ' || (select "cashierUid" || ':' || "cashierName" from public.cash_days where day = '2028-01-06'),
  '^5000:accepted \| handover:U_KAS:U_KAS:U_KAS>U_KAS2:5000:true \| in_surplus:5000:U_KAS:U_KAS:U_KAS2:posted:U_KAS2 \| U_KAS2:Sinov O''qituvchi$');
select zz.chk('M10b qayta qabul — takror; qabul qilinganini bekor qilib bo''lmaydi; jadval — faqat funksiya orqali, qabul qilingani o''zgarmaydi; kun jurnali',
  zz.f(zz.hacc('U_KAS2', zz.hid('M5')), 'dup') || ' | ' || zz.hcan('U_KAS', zz.hid('M5'), 'Kech qoldi') || ' | '
  || zz.try(format($q$update public.cash_handovers set counted = 1 where id = %L$q$, zz.hid('M5'))) || ' | '
  || zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_handovers set status = 'cancelled', "cancelledBy" = 'U_DIR', "cancelledAt" = now() where id = %L; end $x$$q$, zz.hid('M5')))
  || ' | ' || (select string_agg(e.data ->> 'step', ',' order by e.at, e.id) from public.cash_day_events e where e.kind = 'handover' and e.data ->> 'handoverId' = zz.hid('M5')),
  '^true \| ERR P0001 \[kassa:handover_state\].* \| ERR 42501 \[kassa:rpc_only\].* \| ERR 42501 \[kassa:immutable\].* \| pending,accept$');
select app.kassa_flag(false);
select zz.put('M11', zz.f(zz.pay('U_KAS2', zz.id('M6q')), 'status'));
select zz.chk('M11 qabul qilingach kassa yana ishlaydi (so''rov puli berildi); topshiruvchi endi kassa egasi emas — komissiyasiz yopa olmaydi',
  zz.get('M11') || ' | ' || zz.close('U_KAS', format('{"day":"2028-01-06","counted":%s}', zz.bal())), '^posted \| ERR 22023 \[kassa:commission\] Kunni kassa egasi — Sinov O''qituvchi — yopadi');
select zz.put('M12', zz.close('U_KAS2', format('{"day":"2028-01-06","counted":%s}', zz.bal()::numeric - 2000)));
select zz.chk('M12 kassa egasi yopdi (kamomad 2 000, o''zi sanagan): standart javobgar — uning kartasi; kun javobida smena farqi (acc-6); qaror oynasida smena tarixi',
  zz.f(zz.get('M12'), 'diff') || ':' || zz.f(zz.get('M12'), 'day', 'handoverDiff') || ':' || zz.f(zz.get('M12'), 'day', 'handoverDiffs')
  || ' | ' || zz.as('U_DIR', $q$select string_agg((x ->> 'cashierUid') || ':' || (x ->> 'countedBy') || ':' || coalesce(x ->> 'defaultParty', '-') || ':' || coalesce(x ->> 'defaultPartyName', '-')
                                                   || ':' || jsonb_array_length(x -> 'handovers') || ':' || (x -> 'handovers' -> 0 ->> 'status'), ',')
                                   from jsonb_array_elements(public.kassa_overview('main') -> 'shortages') x where x ->> 'day' = '2028-01-06'$q$),
  '^-2000:5000:\[5000\] \| U_KAS2:U_KAS2:teachers:tch1:Sinov O''qituvchi:1:accepted$');
select zz.put('M12d', zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2028-01-06'), 'employee', 'Kassir yozma roziligi bilan')));
select zz.chk('M12d kassa egasi o''zi sanagan kamomad — kartasiz qarorda standart javobgar (teachers:tch1)',
  (select a."partyType" || ':' || a."partyId" || ':' || a."partyName" from public.cash_docs a where a.id = zz.f(zz.get('M12d'), 'act', 'id')), '^employee:teachers:tch1:Sinov O''qituvchi$');
select zz.chk('M12e kun varag''i (KO-4 / RP-02 manbai): smena topshirishlar va sanashlar',
  zz.as('U_ACC', $q$select jsonb_array_length(b -> 'handovers') || ':' || (b -> 'handovers' -> 0 ->> 'status') || ':' || (select string_agg((c ->> 'kind') || '=' || (c ->> 'diff'), ',' order by c ->> 'at') from jsonb_array_elements(b -> 'counts') c)
                     from public.kassa_day_book('main', '2028-01-06') b$q$), '^1:accepted:handover=5000,close=-2000$');
-- 07.01: rad etish, Direktor bekor qilishi, qabul qiluvchi qoidalari, kassir o'rniga topshirish va qabul qilish, himoya
select zz.clock('2028-01-07 09:00+05');
select zz.put('M13', zz.rcpt('U_KAS2', format('{"op":"in_bank","amount":40000,"partyType":"bank","partyId":"%s","basis":"Chek M13","clientRef":"m13-00001"}', zz.id('cp_bank'))));
select zz.put('M13h', zz.ho('U_KAS2', format('{"counted":%s,"toUid":"U_KAS"}', zz.bal())));
select zz.put('M13r', zz.hcan('U_TRE', zz.hid('M13h'), 'Men emas') || ' | ' || zz.f(zz.hcan('U_KAS', zz.hid('M13h'), 'Summa mos emas'), 'handover', 'status'));
select zz.chk('M13 bekor qilish: ishtirok etmagan kassir — rad; qabul qiluvchi rad etdi (sabab bilan) — kassa egasi o''zgarmadi, dalolatnoma yo''q; qayta — takror; rad etilganini qabul qilib bo''lmaydi; jurnalda «rad etish»',
  zz.get('M13r') || ':' || (select "cashierUid" from public.cash_days where day = '2028-01-07') || ':' || (select count(*) from public.cash_counts where "dayId" = 'cd_main_2028-01-07')
  || ' | ' || zz.f(zz.hcan('U_KAS', zz.hid('M13h'), 'Summa mos emas'), 'dup') || ' | ' || zz.hacc('U_KAS', zz.hid('M13h'))
  || ' | ' || (select string_agg(e.data ->> 'step', ',' order by e.at, e.id) from public.cash_day_events e where e.kind = 'handover' and e.data ->> 'handoverId' = zz.hid('M13h')),
  '^ERR 42501 \[kassa:handover_cancel\].* \| cancelled:U_KAS2:0 \| true \| ERR P0001 \[kassa:handover_state\].* \| pending,reject$');
select zz.chk('M13b bekor qilingach kassa yana ishlaydi',
  zz.f(zz.rcpt('U_KAS2', format('{"op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"Chek M13b","clientRef":"m13-00002"}', zz.id('cp_bank'))), 'status'), '^posted$');
select zz.put('M14h', zz.ho('U_KAS2', format('{"counted":%s,"toUid":"U_KAS"}', zz.bal())));
select zz.chk('M14 Direktor kutilayotgan topshirishni bekor qiladi',
  zz.f(zz.hcan('U_DIR', zz.hid('M14h'), 'Topshirish keyinga qoldirildi'), 'handover', 'cancelledBy'), '^U_DIR$');
select zz.chk('M15 qabul qiluvchi: kassaning hozirgi egasi (o''zi) — rad; kassir emas — rad; sanalgan summa yo''q — rad',
  zz.ho('U_KAS2', format('{"counted":%s,"toUid":"U_KAS2"}', zz.bal())) || ' | ' || zz.ho('U_KAS2', format('{"counted":%s,"toUid":"U_TCH"}', zz.bal()))
  || ' | ' || zz.ho('U_KAS2', '{"toUid":"U_KAS"}'),
  '^ERR 22023 \[kassa:handover_to\].* \| ERR 22023 \[kassa:handover_to\].* \| ERR 22023 \[kassa:count\]');
select zz.chk('M16 sec-2: kassa egasi bo''lmagan g''aznachi va Direktor komissiyasiz smena topshira olmaydi',
  zz.ho('U_TRE', format('{"counted":%s,"toUid":"U_KAS"}', zz.bal())) || ' | ' || zz.ho('U_DIR', format('{"counted":%s,"toUid":"U_KAS"}', zz.bal())),
  '^ERR 22023 \[kassa:commission\] Smenani kassa egasi — Sinov O''qituvchi — topshiradi.* \| ERR 22023 \[kassa:commission\]');
-- himoya: kutilayotganda kassa qoldig'i (RPC'ni chetlab) o'zgargan bo'lsa — qabul rad etiladi
select zz.put('M16sh', zz.ho('U_KAS2', format('{"counted":%s,"toUid":"U_KAS"}', zz.bal())));
select zz.try(format($q$do $x$ declare v text; begin perform app.kassa_flag(true);
  select b.o_id into v from app.kassa_doc_build('{"desk":"main","op":"in_bank","amount":1000,"partyType":"bank","partyId":"%s","basis":"RPC siz","clientRef":"m16-stale01"}'::jsonb, 'KO1', 'U_DIR', true) b;
  perform app.kassa_doc_post(v, 'U_DIR', false, null, false, 'cd_main_2028-01-07'); perform app.kassa_flag(false); end $x$$q$, zz.id('cp_bank')));
select zz.chk('M16s qoldiq kutilayotganda o''zgargan — qabul rad (kassa:handover_stale), topshiruvchi bekor qiladi',
  zz.hacc('U_KAS', zz.hid('M16sh')) || ' | ' || zz.f(zz.hcan('U_KAS2', zz.hid('M16sh'), 'Qayta sanaladi'), 'handover', 'status'),
  '^ERR P0001 \[kassa:handover_stale\].* \| cancelled$');
select zz.put('M17h', zz.ho('U_TRE', format('{"counted":%s,"toUid":"U_KAS","commission":%s}', zz.bal()::numeric - 7000, zz.get('comm2'))));
select zz.put('M17', zz.hacc('U_KAS', zz.hid('M17h')));
select zz.chk('M17 g''aznachi komissiya bilan kassa egasi (U_KAS2) o''rniga topshirdi, U_KAS qabul qildi: kamomad 7 000 — kassa egasi U_KAS2, sanagan U_TRE; standart javobgar yo''q',
  zz.f(zz.get('M17'), 'diff') || ' | ' || (select n."cashierUid" || ':' || n."byUid" || ':' || n."toUid" || ':' || jsonb_array_length(n.commission) from public.cash_counts n where n."handoverId" = zz.hid('M17h'))
  || ' | ' || zz.as('U_DIR', $q$select string_agg((x ->> 'kind') || ':' || (x ->> 'cashierUid') || ':' || (x ->> 'countedBy') || ':' || (x ->> 'toUid') || ':' || coalesce(x ->> 'defaultParty', '-'), ',')
                                   from jsonb_array_elements(public.kassa_overview('main') -> 'shortages') x where x ->> 'day' = '2028-01-07'$q$),
  '^-7000 \| U_KAS2:U_TRE:U_KAS:2 \| handover:U_KAS2:U_TRE:U_KAS:-$');
select zz.put('M18h', zz.ho('U_TRE', format('{"counted":%s,"toUid":"U_TRE","commission":%s}', zz.bal(), zz.get('comm2'))));
select zz.put('M18a', zz.f(zz.hacc('U_TRE', zz.hid('M18h')), 'handover', 'status'));
select zz.chk('M18 kassir o''rniga (komissiya bilan) kassani o''zi qabul qilishi mumkin — ikki bosqichda; kassa egasi — g''aznachi, endi u komissiyasiz yopadi',
  zz.f(zz.get('M18h'), 'handover', 'fromUid') || '>' || zz.f(zz.get('M18h'), 'handover', 'toUid') || ':' || zz.get('M18a') || ':' || (select "cashierUid" from public.cash_days where day = '2028-01-07')
  || ' | ' || zz.f(zz.close('U_TRE', format('{"day":"2028-01-07","counted":%s}', zz.bal())), 'day', 'status'),
  '^U_KAS>U_TRE:accepted:U_TRE \| closed$');
-- sec-4: o'zi o'zgartiradigan ism (users.name) — bog'langan hisobda kassaga chiqmaydi; muzlatilgan ismlar o'zgarmaydi; bog'lanmaganlar — RP-06
select zz.put('M19r', zz.as('U_KAS2', $q$update public.users set name = 'Kassir Bir' where id = 'U_KAS2' returning name$q$));
select zz.chk('M19 kartaga bog''langan kassir o''z ismini o''zgartirdi — kassirlar ro''yxatida va hujjat ismlarida karta ismi (HR)',
  zz.get('M19r') || ' | ' || zz.as('U_KAS', $q$select string_agg((x ->> 'uid') || '=' || (x ->> 'name'), ',' order by x ->> 'uid') from jsonb_array_elements(public.kassa_refs() -> 'operators') x where x ->> 'uid' in ('U_KAS', 'U_KAS2')$q$)
  || ' | ' || zz.as('U_ACC', format($q$select (g -> 'doc' ->> 'postedByName') || ':' || (g -> 'names' ->> 'U_KAS2') from public.kassa_doc_get(%L) g$q$, zz.id('M13'))),
  '^Kassir Bir \| U_KAS=Sinov Xodim,U_KAS2=Sinov O''qituvchi \| Sinov O''qituvchi:Sinov O''qituvchi$');
set local session_replication_role = replica;
update public.staff set name = 'Sinov Xodim Yangi' where id = 'st1';
set local session_replication_role = origin;
select zz.chk('M20 xodim kartasi ismi keyin o''zgardi (HR): ro''yxatda yangi ism; o''tkazilgan hujjat, kun kassiri, dalolatnoma, smena topshirish — o''sha paytdagi ism',
  zz.as('U_KAS', $q$select x ->> 'name' from jsonb_array_elements(public.kassa_refs() -> 'operators') x where x ->> 'uid' = 'U_KAS'$q$)
  || ' | ' || zz.as('U_ACC', format($q$select (g -> 'doc' ->> 'postedByName') || ':' || (g -> 'names' ->> 'U_KAS') from public.kassa_doc_get(%L) g$q$, zz.id('M1')))
  || ' | ' || (select "cashierName" from public.cash_days where day = '2028-01-05')
  || ' | ' || (select n.names ->> 'U_KAS' from public.cash_counts n where n."dayId" = 'cd_main_2028-01-05' and n.kind = 'close')
  || ' | ' || (select h.names ->> 'U_KAS' from public.cash_handovers h where h.id = zz.hid('M5')),
  '^Sinov Xodim Yangi \| Sinov Xodim:Sinov Xodim \| Sinov Xodim \| Sinov Xodim \| Sinov Xodim$');
-- 08.01: kartaga bog'lanmagan kassir (U_HRK) o'z kunini kamomad bilan yopadi — «xodim zimmasiga» faqat karta tanlab; users.name — hech qachon
select zz.clock('2028-01-08 09:00+05');
select zz.put('M21', zz.rcpt('U_HRK', format('{"op":"in_bank","amount":10000,"partyType":"bank","partyId":"%s","basis":"Chek M21","clientRef":"m21-00001"}', zz.id('cp_bank'))));
select zz.put('M21r', zz.as('U_HRK', $q$update public.users set name = 'Sinov Xodim Yangi' where id = 'U_HRK' returning name$q$));
select zz.put('M21c', zz.close('U_HRK', format('{"day":"2028-01-08","counted":%s}', zz.bal()::numeric - 1000)));
select zz.put('M21d', zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2028-01-08'), 'employee', 'Tushuntirish xati bilan')));
select zz.put('M21e', zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = '2028-01-08'), 'employee', 'Tushuntirish xati bilan', 'staff:st6')));
select zz.chk('M21 bog''lanmagan kassir: standart javobgar yo''q, kartasiz qaror — rad; Direktor kartani tanlaydi (staff:st6) — tomon karta ismi, o''zi yozgan ism emas',
  zz.f(zz.get('M21c'), 'diff') || ' | ' || zz.get('M21d')
  || ' | ' || (select a."partyType" || ':' || a."partyId" || ':' || a."partyName" from public.cash_docs a where a.id = zz.f(zz.get('M21e'), 'act', 'id')),
  '^-1000 \| ERR 22023 \[kassa:shortage_party\] Kassir hisobi xodim kartasiga bog''lanmagan.* \| employee:staff:st6:Sinov Farrosh$');
select zz.chk('M22 RP-06: xodim kartasiga bog''lanmagan kassa hisoblari — HR+kassir va g''aznachi (bloklangan — yo''q, teskari havolali — bog''langan)',
  zz.as('U_FM', $q$select string_agg((x ->> 'uid') || ':' || (x ->> 'name') || ':' || (x ->> 'role') || ':' || (x ->> 'kassir'), ',') from jsonb_array_elements(public.kassa_checks('main') -> 'unlinkedUsers') x$q$),
  '^U_HRK:Sinov Xodim Yangi:hr:true,U_TRE:U_TRE:treasurer:false$');
select zz.chk('M23 RP-06 sanash farqlari: yopish va smena topshirish farqlari kun bo''yicha (acc-6)',
  zz.as('U_FM', $q$select string_agg((x ->> 'day') || '=' || (x ->> 'diff') || '/' || (x -> 'handover')::text, ',' order by x ->> 'day') from jsonb_array_elements(public.kassa_checks('main') -> 'diffs30') x where x ->> 'day' >= '2028-01-05'$q$),
  '^2028-01-05=-30000/\[\],2028-01-06=-2000/\[5000\],2028-01-07=0/\[-7000\],2028-01-08=-1000/\[\]$');

-- ---------- (N) smena qo'shimchalari (g6b): standart javobgar faqat boshqa hech kim tegmagan kassada (g6v-1), smenada sanalgan orderni
--   kassir bekor qilmaydi (g6v-2), «nega standart javobgar yo'q» — bitta manba (g6v-3) ----------
--   Yangi kunlar 10–14.01.2028. Ismlar — xodim kartasidan: U_DIR — «Sinov Rahbar» (st4), U_FM — «Sinov Moliyachi» (st2), U_KAS — staff:st1,
--   U_KAS2 — teachers:tch1. Mavjud standart javobgar holatlari (G17, M12d: kassa egasi kassani olgandan keyin boshqa hech kim tegmagan) — o'zgarmagan.
create or replace function zz.inb(p_uid text, p_amt numeric, p_ref text) returns text language sql as $$
  select zz.rcpt(p_uid, format('{"op":"in_bank","amount":%s,"partyType":"bank","partyId":"%s","basis":"Chek","clientRef":"%s"}', p_amt, zz.id('cp_bank'), p_ref)) $$;
-- qaror oynasi ma'lumoti (kassa_overview → shortages) kun bo'yicha: tur:kassa egasi:sanagan:standart javobgar:boshqalar:nega yo'q
create or replace function zz.sh(p_day text) returns text language sql as $$
  select zz.as('U_DIR', format($q$select string_agg(coalesce(x ->> 'kind', '-') || ':' || coalesce(x ->> 'cashierUid', '-') || ':' || coalesce(x ->> 'countedBy', '-')
                                                    || ':' || coalesce(x ->> 'defaultParty', '-') || ':' || coalesce((x -> 'others')::text, '-') || ':' || coalesce(x ->> 'defaultWhy', '-'),
                                                    ' ; ' order by x ->> 'kind')
                                    from jsonb_array_elements(public.kassa_overview('main') -> 'shortages') x where x ->> 'day' = %L$q$, p_day)) $$;
create or replace function zz.dec(p_day text, p_decision text, p_party text) returns text language sql as $$
  select zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L, %L)::text', (select "diffDocId" from public.cash_days where day = p_day::date), p_decision,
                               'Tushuntirish xati bilan', p_party)) $$;
-- 10.01: Direktor kunning birinchi orderini o'tkazdi (kassa egasi yo'q), keyin kassir — kassa egasi; kassir o'zi sanab kamomad bilan yopdi
select zz.clock('2028-01-10 09:00+05');
select zz.put('N1a', zz.inb('U_DIR', 60000, 'n1-000001'));
select zz.put('N1b', zz.inb('U_KAS', 30000, 'n1-000002'));
select zz.chk('N1 g6v-1: Direktor birinchi orderni o''tkazdi — kassa egasi yo''q, u «boshqalar»da; birinchi kassir orderi bilan kassa egasi — kassir (u «boshqa» emas); '
              || 'sanash farqi (tizim hujjati) yaratgan xodim «boshqa» emas (M2: 05.01 ni boshqa kassir komissiya bilan yopgan)',
  zz.f(zz.get('N1a'), 'status') || ':' || zz.f(zz.get('N1b'), 'status') || ' | ' || (select "cashierUid" || ':' || array_to_string("othersUids", ',') from public.cash_days where day = '2028-01-10')
  || ' | ' || (select "cashierUid" || ':' || cardinality("othersUids") || ':' || (select count(*) from public.cash_docs c where c."dayId" = d.id and c."isSystem")
                 from public.cash_days d where d.day = '2028-01-05'),
  '^posted:posted \| U_KAS:U_DIR \| U_KAS:0:1$');
select zz.put('N2', zz.close('U_KAS', format('{"day":"2028-01-10","counted":%s}', zz.bal()::numeric - 1500)));
select zz.chk('N2 kassa egasi o''zi sanagan kamomad — standart javobgar YO''Q: farq hujjati suratida «boshqalar» (ismi bilan); qaror oynasida sababi — server matni',
  zz.f(zz.get('N2'), 'diff') || ' | ' || (select (c."sourceSnapshot" -> 'others')::text || ':' || (c."sourceSnapshot" -> 'names' ->> 'U_DIR')
                                             from public.cash_docs c where c.id = (select "diffDocId" from public.cash_days where day = '2028-01-10'))
  || ' | ' || zz.sh('2028-01-10'),
  '^-1500 \| \["U_DIR"\]:Sinov Rahbar \| close:U_KAS:U_KAS:-:\["U_DIR"\]:Shu kuni kassa egasidan boshqa xodim ham kassa orderini o''tkazgan yoki bekor qilgan: Sinov Rahbar$');
select zz.put('N3e', zz.dec('2028-01-10', 'employee', null));
select zz.put('N3', zz.dec('2028-01-10', 'employee', 'staff:st1'));
select zz.chk('N3 «xodim zimmasiga» kartasiz — rad, xuddi shu matn bilan (bitta manba); Direktor tanlagan karta bilan — qaror (dalolatnoma suratida «boshqalar», standart javobgar yo''q)',
  zz.get('N3e') || ' | ' || (select a."partyType" || ':' || a."partyId" || ':' || (a."sourceSnapshot" -> 'others')::text || ':' || coalesce(a."sourceSnapshot" ->> 'defaultParty', '-')
                               || ':' || (a."sourceSnapshot" ->> 'picked') from public.cash_docs a where a.id = zz.f(zz.get('N3'), 'act', 'id')),
  '^ERR 22023 \[kassa:shortage_party\] Shu kuni kassa egasidan boshqa xodim ham kassa orderini o''tkazgan yoki bekor qilgan: Sinov Rahbar — javobgar xodim kartasini tanlang \| employee:staff:st1:\["U_DIR"\]:-:true$');
-- 11.01: kassir kunida Direktor kabinetda chiqim orderini o'tkazdi (so'rov puli), kassir kamomad bilan yopdi
select zz.clock('2028-01-11 09:00+05');
select zz.put('N4a', zz.inb('U_KAS', 80000, 'n4-000001'));
select zz.put('N4q', zz.preq('U_KAS', $q${"op":"out_expense","amount":15000,"partyType":"other","partyName":"Bozor sotuvchisi","noBasis":true,"clientRef":"n4-000002","lines":[{"articleId":"EX-20","amount":15000}]}$q$));
select zz.put('N4r', zz.f(zz.appr('U_FM', zz.id('N4q')), 'status'));
select zz.put('N4p', zz.f(zz.pay('U_DIR', zz.id('N4q')), 'status'));
select zz.put('N4c', zz.close('U_KAS', format('{"day":"2028-01-11","counted":%s}', zz.bal()::numeric - 2500)));
select zz.chk('N4 kassa egasi kunida Direktor chiqim orderini o''tkazdi — kassir kamomad bilan yopdi: standart javobgar yo''q, «boshqalar»da Direktor',
  zz.get('N4r') || ':' || zz.get('N4p') || ' | ' || zz.f(zz.get('N4c'), 'diff') || ' | ' || zz.sh('2028-01-11'),
  '^approved:posted \| -2500 \| close:U_KAS:U_KAS:-:\["U_DIR"\]:Shu kuni kassa egasidan boshqa xodim ham kassa orderini o''tkazgan yoki bekor qilgan: Sinov Rahbar$');
-- g6v-3: eski hujjat (g6 dan oldingi surat — sanagan xodim yozilmagan): qaror oynasi va server xatosi bir xil «Eski hujjat…»
set local session_replication_role = replica;
update public.cash_docs set "sourceSnapshot" = "sourceSnapshot" - 'countedBy' - 'others' where id = (select "diffDocId" from public.cash_days where day = '2028-01-11');
set local session_replication_role = origin;
select zz.put('N5e', zz.sh('2028-01-11') || ' | ' || zz.dec('2028-01-11', 'employee', null));
select zz.chk('N5 eski hujjat (sanagan xodim yozilmagan): qaror oynasi va server xatosi — bir xil «Eski hujjat…» (avval «kassir o''rniga» deyilardi); hisobdan chiqarish — mumkin',
  zz.get('N5e') || ' | ' || zz.f(zz.dec('2028-01-11', 'writeoff', null), 'decision'),
  '^close:U_KAS:-:-:\[\]:Eski hujjat: pulni kim sanagani yozilmagan \| ERR 22023 \[kassa:shortage_party\] Eski hujjat: pulni kim sanagani yozilmagan — javobgar xodim kartasini tanlang \| writeoff$');
select zz.chk('N6 g6v-3: «nega standart javobgar yo''q» — bitta yordamchi, tartib bilan; eski surat (sanagan yozilmagan) — standart javobgar yo''q',
  coalesce(app.kassa_shortage_why('{}'::jsonb), '-') || ' | ' || coalesce(app.kassa_shortage_why('{"cashierUid":"U_KAS"}'::jsonb), '-')
  || ':' || coalesce(app.kassa_shortage_default('{"cashierUid":"U_KAS"}'::jsonb), 'NULL')
  || ' | ' || coalesce(app.kassa_shortage_why('{"cashierUid":"U_KAS","countedBy":"U_KAS2","others":["U_DIR"]}'::jsonb), '-')
  || ' | ' || coalesce(app.kassa_shortage_why('{"cashierUid":"U_KAS","countedBy":"U_KAS","others":["U_ZAV","U_DIR"],"names":{"U_DIR":"Sinov Rahbar"}}'::jsonb), '-')
  || ':' || coalesce(app.kassa_shortage_default('{"cashierUid":"U_KAS","countedBy":"U_KAS","others":["U_DIR"]}'::jsonb), 'NULL')
  || ' | ' || coalesce(app.kassa_shortage_why('{"cashierUid":"U_TRE","countedBy":"U_TRE"}'::jsonb), '-')
  || ' | ' || coalesce(app.kassa_shortage_why('{"cashierUid":"U_KAS","countedBy":"U_KAS","others":[]}'::jsonb), 'NULL')
  || ':' || coalesce(app.kassa_shortage_default('{"cashierUid":"U_KAS","countedBy":"U_KAS","others":[]}'::jsonb), 'NULL'),
  '^Kassa egasi \(kun kassiri\) aniqlanmagan \| Eski hujjat: pulni kim sanagani yozilmagan:NULL \| Pulni kassa egasining o''zi sanamagan \(kassir o''rniga sanalgan\) \| '
  || 'Shu kuni kassa egasidan boshqa xodim ham kassa orderini o''tkazgan yoki bekor qilgan: U_ZAV, Sinov Rahbar:NULL \| Kassir hisobi xodim kartasiga bog''lanmagan \(yoki bir nechta kartaga\) \| NULL:staff:st1$');
-- 12.01: A (U_KAS) va Direktor orderlari, A → B (U_KAS2) smena kamomad bilan qabul qilindi (ro'yxat bo'shatildi), B yolg'iz ishlab kamomad bilan yopdi
select zz.clock('2028-01-12 09:00+05');
select zz.put('N7a', zz.inb('U_KAS', 50000, 'n7-000001'));
select zz.put('N7b', zz.inb('U_DIR', 20000, 'n7-000002'));
select zz.put('N7h', zz.ho('U_KAS', format('{"counted":%s,"toUid":"U_KAS2"}', zz.bal()::numeric - 500)));
select zz.put('N7x', zz.hacc('U_KAS2', zz.hid('N7h')));
select zz.chk('N7 smena qabul qilindi: topshirishdagi kamomad hujjatida topshiruvchi davri («boshqalar»: Direktor) — standart javobgar yo''q; ro''yxat bo''shatildi, kassa egasi — qabul qiluvchi',
  zz.f(zz.get('N7x'), 'diff') || ' | ' || (select "cashierUid" || ':' || cardinality("othersUids") from public.cash_days where day = '2028-01-12') || ' | ' || zz.sh('2028-01-12'),
  '^-500 \| U_KAS2:0 \| handover:U_KAS:U_KAS:-:\["U_DIR"\]:Shu kuni kassa egasidan boshqa xodim ham kassa orderini o''tkazgan yoki bekor qilgan: Sinov Rahbar$');
select zz.put('N8a', zz.inb('U_KAS2', 10000, 'n8-000001'));
select zz.put('N8c', zz.close('U_KAS2', format('{"day":"2028-01-12","counted":%s}', zz.bal()::numeric - 700)));
select zz.put('N8s', zz.sh('2028-01-12'));
select zz.put('N8d', zz.dec('2028-01-12', 'employee', null));
select zz.chk('N8 qabul qiluvchi o''z davrida yolg''iz ishlab kamomad bilan yopdi — standart javobgar uning kartasi (Direktorning smenadan oldingi orderi unga «boshqa» emas); kartasiz qaror o''tdi',
  zz.f(zz.get('N8c'), 'diff') || ' | ' || zz.get('N8s') || ' | '
  || (select a."partyType" || ':' || a."partyId" from public.cash_docs a where a.id = zz.f(zz.get('N8d'), 'act', 'id')),
  '^-700 \| close:U_KAS2:U_KAS2:teachers:tch1:\[\]:- ; handover:U_KAS:U_KAS:-:\["U_DIR"\]:Shu kuni .* \| employee:teachers:tch1$');
-- 13.01: g6v-2 — smenada sanalgan orderni kassir bekor qilmaydi; 2-ro'yxat bekor qiladi va «boshqalar»ga tushadi
select zz.clock('2028-01-13 09:00+05');
select zz.put('N9a', zz.inb('U_KAS', 40000, 'n9-000001'));
select zz.put('N9h', zz.ho('U_KAS', format('{"counted":%s,"toUid":"U_KAS2"}', zz.bal())));
select zz.put('N9x', zz.f(zz.hacc('U_KAS2', zz.hid('N9h')), 'handover', 'status'));
select zz.put('N9b', zz.bal());
select zz.chk('N9 g6v-2: avvalgi kassa egasi smenada sanalgan o''z orderini bekor qila olmaydi (kassa:void_counted), qoldiq o''zgarmadi; topshirishda va kun javobida sanalgan raqam',
  zz.get('N9x') || ' | ' || zz.void('U_KAS', zz.id('N9a'), 'Xato yozilgan edi') || ' | ' || (zz.bal() = zz.get('N9b'))::text
  || ' | ' || (zz.f(zz.get('N9h'), 'handover', 'lastKo1') = zz.f(zz.get('N9a'), 'no'))::text || ':' || coalesce(zz.f(zz.get('N9h'), 'handover', 'lastKo2'), 'null')
  || ':' || ((select app.kassa_day_json(id) ->> 'countedKo1' from public.cash_days where day = '2028-01-13') = zz.f(zz.get('N9a'), 'no'))::text,
  '^accepted \| ERR 42501 \[kassa:void_counted\] Bu order smena topshirishda sanalgan \(topshirish-qabul dalolatnomasiga kirgan\) — kassir uni bekor qilmaydi\. Xato bo''lsa, moliya menejeri, buxgalter yoki Direktor bekor qiladi; farq kunni yopishda ko''rinadi \| true \| true:null:true$');
select zz.put('N10a', zz.inb('U_KAS2', 25000, 'n10-00001'));
select zz.put('N10h', zz.ho('U_KAS2', format('{"counted":%s,"toUid":"U_KAS"}', zz.bal())));
select zz.put('N10x', zz.f(zz.hacc('U_KAS', zz.hid('N10h')), 'handover', 'status'));
select zz.put('N10b', zz.inb('U_KAS', 12000, 'n10-00002'));
select zz.put('N10v', left(zz.void('U_KAS2', zz.id('N10a'), 'Xato yozilgan edi'), 30));
select zz.put('N10w', zz.f(zz.void('U_KAS', zz.id('N10b'), 'Xato yozilgan edi'), 'status'));
select zz.put('N10y', left(zz.void('U_KAS', zz.id('N9a'), 'Xato yozilgan edi'), 30));
select zz.chk('N10 smena qaytdi: U_KAS2 o''z sanalgan orderini ham bekor qilmaydi; U_KAS yana kassa egasi — oxirgi topshirishdan KEYIN o''tkazgan orderini bekor qiladi, oldingisini — yo''q; o''z orderini bekor qilgan kassa egasi «boshqa» emas',
  zz.get('N10x') || ' | ' || zz.get('N10v') || ' | ' || zz.get('N10w') || ' | ' || zz.get('N10y')
  || ' | ' || (select "cashierUid" || ':' || cardinality("othersUids") from public.cash_days where day = '2028-01-13'),
  '^accepted \| ERR 42501 \[kassa:void_counted\] \| void \| ERR 42501 \[kassa:void_counted\] \| U_KAS:0$');
select zz.chk('N10b sanalgan raqamlar o''zgarmaydi (topshirish yozuvi qabul qilingach o''zgarmaydi)',
  zz.try(format($q$do $x$ begin perform app.kassa_flag(true); update public.cash_handovers set "lastKo1" = 0 where id = %L; end $x$$q$, zz.hid('N9h'))),
  '^ERR 42501 \[kassa:immutable\]');
select app.kassa_flag(false);
select zz.put('N11', zz.f(zz.void('U_FM', zz.id('N9a'), 'Summa xato yozilgan'), 'status'));
select zz.chk('N11 2-ro''yxat (Moliya menejeri) sanalgan orderni bekor qiladi — u kassa egasi emas, «boshqalar»ga tushdi; ochiq kunda ro''yxat qisqarmaydi (bayroq bilan ham)',
  zz.get('N11') || ' | ' || (select array_to_string("othersUids", ',') from public.cash_days where day = '2028-01-13')
  || ' | ' || zz.try($q$do $x$ begin perform app.kassa_flag(true); update public.cash_days set "othersUids" = '{}' where day = '2028-01-13'; end $x$$q$),
  '^void \| U_FM \| ERR 42501 \[kassa:immutable\]');
select app.kassa_flag(false);
select zz.put('N12', zz.close('U_KAS', format('{"day":"2028-01-13","counted":%s}', zz.bal()::numeric - 900)));
select zz.chk('N12 kassa egasi kamomad bilan yopdi — standart javobgar yo''q, «boshqalar»da Moliya menejeri (ismi bilan)',
  zz.f(zz.get('N12'), 'diff') || ' | ' || zz.sh('2028-01-13'),
  '^-900 \| close:U_KAS:U_KAS:-:\["U_FM"\]:Shu kuni kassa egasidan boshqa xodim ham kassa orderini o''tkazgan yoki bekor qilgan: Sinov Moliyachi$');
select zz.chk('N13 kun qulfi: yopilgan kunda ro''yxat o''zgarmaydi (bayroq bilan ham); kun izi unga bog''liq emas',
  zz.try($q$do $x$ begin perform app.kassa_flag(true); update public.cash_days set "othersUids" = '{}' where day = '2028-01-13'; end $x$$q$)
  || ' | ' || zz.try($q$do $x$ begin perform app.kassa_flag(true); update public.cash_days set "othersUids" = "othersUids" || 'U_ACC'::text where day = '2028-01-10'; end $x$$q$)
  || ' | ' || (select (hash = app.kassa_day_hash(id))::text from public.cash_days where day = '2028-01-13'),
  '^ERR 42501 \[kassa:immutable\].* \| ERR 42501 \[kassa:immutable\].* \| true$');
select app.kassa_flag(false);
select zz.put('N14r', zz.f(zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2028-01-13', 'Qayta sanash kerak')::text$q$), 'day', 'othersUids'));
select zz.put('N14', zz.close('U_KAS', format('{"day":"2028-01-13","counted":%s}', zz.bal()::numeric - 600)));
select zz.chk('N14 qayta ochish ro''yxatni bo''shatmaydi (faqat sanash farqi hujjati bekor bo''ladi): qayta yopishdagi kamomadda ham standart javobgar yo''q',
  zz.get('N14r') || ' | ' || zz.f(zz.get('N14'), 'diff') || ' | ' || zz.sh('2028-01-13'),
  '^\["U_FM"\] \| -600 \| close:U_KAS:U_KAS:-:\["U_FM"\]:Shu kuni .*: Sinov Moliyachi$');
-- 14.01: kassa egasi aniqlanmagan kun (faqat Direktor orderi) — kassir komissiyasiz yopadi (o'zi kassa egasi va sanagan), lekin standart javobgar yo'q
select zz.clock('2028-01-14 09:00+05');
select zz.put('N15a', zz.inb('U_DIR', 30000, 'n15-00001'));
select zz.put('N15', zz.close('U_KAS', format('{"day":"2028-01-14","counted":%s}', zz.bal()::numeric - 400)));
select zz.chk('N15 g6 tekshiruvchisi 1-holati: kassa egasi yo''q kunni kassir yopdi — kassa egasi va sanagan o''zi, lekin kunning orderini Direktor o''tkazgan: standart javobgar yo''q',
  coalesce((select "cashierUid" from public.cash_days where day = '2028-01-14'), '-') || ' | ' || zz.f(zz.get('N15'), 'diff') || ' | ' || zz.sh('2028-01-14'),
  '^- \| -400 \| close:U_KAS:U_KAS:-:\["U_DIR"\]:Shu kuni kassa egasidan boshqa xodim ham kassa orderini o''tkazgan yoki bekor qilgan: Sinov Rahbar$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 400), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
