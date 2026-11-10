-- =====================================================================
-- test-kassa.sql — moliya ish rejasi 1a-bosqichi (fin-core.sql, fin-seed.sql, kassa.sql, kassa-docs.sql, kassa-day.sql) sinovi:
--   (A) ma'lumotnomalar va xavfsizlik (RLS, to'g'ridan-to'g'ri yozish rad, sozlamalar faqat Direktor);
--   (B) boshlang'ich qoldiq; (C) KO-1 kirim (idempotentlik, fiskal chek, tomon, statiya, Direktor ruxsati);
--   (D) KO-2 chiqim: so'rov → 2-ro'yxat tasdig'i (≠ so'rovchi) → T1 dan katta bo'lsa Direktor → to'lash; manfiy qoldiq rad;
--   (E) shu kunda bekor qilish; (F) bazadagi himoya (o'zgarmaslik, I1–I6) — RPC'ni chetlab o'tib ham buzib bo'lmaydi;
--   (G) kun sikli: sanab yopish, farq hujjati (kamomad / ortiqcha), tekshirish (≠ yopuvchi / o'tkazuvchi), qayta ochish,
--       kamomad qarori, oflayn va kech kiritish, smena topshirish, yil chegarasi, raqam bo'shlig'i va xesh nazorati;
--   (H) o'qish funksiyalari.
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
  ('U_HRK','h@x','hr','active','["kassir"]',null,null)
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]');
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','[]');
insert into public.staff (id, "staffId", name, position) values ('st1','IQX-T1','Sinov Xodim','Kassir');
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
  zz.as('U_DIR', $q$select public.fin_org_set('{"t1":500000,"l1":200000,"nameUz":"Sinov maktabi"}')::text$q$), '"t1": 500000.*"l1": 200000|"l1": 200000.*"t1": 500000');
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
select zz.chk('C4 boshqa kirim: izohsiz rad',
  zz.rcpt('U_KAS', $q${"op":"in_other","amount":100000,"partyType":"other","partyName":"Noma'lum shaxs","articleId":"OP-16","basis":"Ariza","clientRef":"c4-000001"}$q$), '^ERR 22023 \[kassa:note\]');
select zz.put('C4', zz.rcpt('U_KAS', $q${"op":"in_other","amount":100000,"partyType":"other","partyName":"Noma'lum shaxs","articleId":"OP-16","basis":"Ariza","note":"Aniqlanmagan tushum","clientRef":"c4-000002"}$q$));
select zz.chk('C4b boshqa kirim (aniqlanmagan): KO-1 № 2, Kt 6390',
  (select c.no || ':' || l.credit from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('C4')), '^2:6390$');
select zz.chk('C5 boshqa kirimda ruxsat etilmagan statiya rad',
  zz.rcpt('U_KAS', $q${"op":"in_other","amount":1000,"partyType":"other","partyName":"Noma'lum shaxs","articleId":"EX-20","basis":"Ariza","note":"izoh bor","clientRef":"c5-000001"}$q$), '^ERR 22023 \[kassa:article\]');
select zz.chk('C6 forma sotuvi: fiskal chek raqamisiz rad',
  zz.rcpt('U_KAS', $q${"op":"in_sale","amount":150000,"partyType":"student","partyId":"T-1","basis":"Forma","clientRef":"c6-000001"}$q$), '^ERR 22023 \[kassa:fiscal\]');
select zz.put('C6', zz.rcpt('U_KAS', $q${"op":"in_sale","amount":150000,"partyType":"student","partyId":"s1","partyName":"Sinov Ota","basis":"Forma","fiscalNo":"F-1001","clientRef":"c6-000002"}$q$));
select zz.chk('C6b forma sotuvi: KO-1 № 3, Kt 9020, o''quvchi kanonik kaliti, to''lovchi ismi',
  (select c.no || ':' || l.credit || ':' || c."partyId" || ':' || c."partyName" || ':' || c."fiscalNo" from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('C6')), '^3:9020:T-1:Sinov Ota:F-1001$');
select zz.chk('C6c o''sha fiskal chek raqami ikkinchi marta — rad',
  zz.rcpt('U_KAS', $q${"op":"in_sale","amount":150000,"partyType":"student","partyId":"T-1","basis":"Forma","fiscalNo":"F-1001","clientRef":"c6-000003"}$q$), '^ERR 22023 \[kassa:fiscal_dup\]');
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
select zz.put('C10', zz.rcpt('U_KAS', $q${"op":"in_acc_return","amount":40000,"partyType":"employee","partyId":"teachers:tch1","basis":"Avans hisoboti qoldig'i","clientRef":"c10-00001"}$q$));
select zz.chk('C10 hisobdordan qaytim: KO-1 № 5, Kt 4230, xodim',
  (select c.no || ':' || l.credit || ':' || c."partyId" || ':' || c."partyName" from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('C10')), '^5:4230:teachers:tch1:Sinov O''qituvchi$');
select zz.put('C11', zz.rcpt('U_KAS', $q${"op":"in_staff_return","amount":10000,"partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha berilgan avans","clientRef":"c11-00001"}$q$));
select zz.chk('C11 xodim qaytargan avans: KO-1 № 6, Kt 4210',
  (select c.no || ':' || l.credit from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id where c.id = zz.id('C11')), '^6:4210$');
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
select zz.chk('G5c «qog''ozlar olindi» belgisisiz tekshirilmaydi', zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-04', false)::text$q$), '^ERR 22023 \[kassa:papers\]');
select zz.chk('G5d Moliya menejeri tekshirdi', zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-04', true, 'Hammasi joyida')::text$q$), '"status": "verified"');
select zz.chk('G5e qayta tekshirish — takror', zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-04', true)::text$q$), '"dup": true');
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
select zz.chk('G11 buxgalter tekshirdi (2-kun)', zz.as('U_ACC', $q$select public.kassa_day_verify('main', '2027-01-05', true)::text$q$), '"status": "verified"');

-- 3-kun: smena topshirish, kecha ochiq qolgan kun, oflayn yozuv
select zz.clock('2027-01-06 09:00+05');
select zz.put('G12', zz.rcpt('U_KAS', format('{"op":"in_bank","amount":200000,"partyType":"bank","partyId":"%s","basis":"Chek 005","clientRef":"g12-00001"}', zz.id('cp_bank'))));
select zz.chk('G12 3-kun: kun boshi 1 381 000', (select trim_scale(opening)::text from public.cash_days where status = 'open') || '/' || zz.bal(), '^1381000/1581000$');
select zz.chk('G13 smena topshirish: qabul qiluvchi kassir emas — rad',
  zz.as('U_KAS', $q$select public.kassa_handover('{"counted":1581000,"toUid":"U_TCH"}')::text$q$), '^ERR 22023 \[kassa:handover_to\]');
select zz.put('G13b', zz.as('U_KAS', $q$select public.kassa_handover('{"counted":1581000,"toUid":"U_KAS2","note":"Tushlikdan keyin"}')::text$q$));
select zz.chk('G13b smena topshirildi: kun ochiq, kassir almashdi, dalolatnoma yozildi', (select v from zz.v where k = 'G13b') || ' / ' ||
  (select status || ':' || "cashierUid" from public.cash_days where day = '2027-01-06') || ':' || (select kind || ':' || trim_scale(diff) || ':' || "toUid" from public.cash_counts where kind = 'handover'),
  '"diff": 0[,}].* / open:U_KAS2:handover:0:U_KAS2$');
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
select zz.chk('G20 «hali o''tkazilmagan» yozuvlar: soni va summasi birga', zz.close('U_KAS2', '{"day":"2027-01-07","counted":1726000,"pendingSum":100000}'), '^ERR 22023 \[kassa:count\]');
select zz.put('G20', zz.close('U_KAS2', '{"day":"2027-01-07","counted":1726000,"pendingCount":1,"pendingSum":100000,"denoms":{"100000":17,"5000":5,"1000":1}}'));
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
select zz.chk('G22b tiklangach tekshiruv o''tadi (06.01, keyin 07.01)',
  left(zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-06', true)::text$q$), 0) || zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-07', true)::text$q$), '"status": "verified"');

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
  (select string_agg(k.series || k.year || ':' || k."lastNo" || '=' || (select count(*) from public.cash_docs c where c.form = k.series and c.year = k.year and c.no is not null)
                     || '=' || (select max(no) from public.cash_docs c where c.form = k.series and c.year = k.year), ',' order by k.year, k.series) from public.doc_counters k),
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
select zz.chk('H7 o''zgarishlar tarixi yoziladi (hujjat holati)', (select (count(*) > 0)::text from public.change_log where tbl = 'cash_docs'), '^true$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 400), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
