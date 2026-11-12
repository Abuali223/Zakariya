-- =====================================================================
-- test-kassa-checks.sql — moliya ish rejasi 1a-bosqichi, F1.18: kassa-checks.sql (o'rnatishdan keyingi, faqat o'qiydigan
--   tekshiruv) sinovi:
--   (A) toza holat: haqiqiy funksiyalar orqali yozilgan uch kunlik kassa (o'quv to'lovlari, kirim, xarajat, bekor qilingan
--       order, avans, o'zaro hisob, kamomad bilan yopilgan va tekshirilgan kun, sinov kassasi, davr surati va qulfi) —
--       tekshiruv HECH NARSA topmasligi kerak;
--   (B) har bir buzilish (triggerlarni chetlab, to'g'ridan-to'g'ri kiritiladi) AYNAN o'z bandida ko'rinishi kerak:
--       tuzilma va huquqlar (1–10-bandlar) va ma'lumot yaxlitligi (11–22-bandlar);
--   (C) buzilishlar qaytarilgach — yana toza; modul bo'lmagan bazada — faqat 1-band.
--   kassa-checks.sql har band bo'yicha muammo qatorlari sonini psql o'zgaruvchilarida qoldiradi (c1 … c22, bad, err).
--   Har buzilish o'z savepoint'ida: tekshiruvdan keyin avval qaytariladi, so'ng natija yoziladi (psql o'zgaruvchilari saqlanadi).
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin, AYNAN -f bilan (\ir shu papkadan o'qiydi):
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-checks.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) then
    raise exception 'test-kassa-checks.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
-- Hujjat id'si: (kassa, shakl, raqam)
create or replace function zz.doc(p_desk text, p_form text, p_no int) returns text language sql as $$
  select c.id from public.cash_docs c where c.desk = p_desk and c.form = p_form and c.no = p_no and c.year = 2027 $$;

-- Ssenariy va tekshiruv fayli chiqishi ko'rsatilmaydi (faqat yakuniy PASS/FAIL ro'yxati); xatolar baribir ko'rinadi.
\o /dev/null

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]'), ('s2','T-2','Sinov B',5,'A','uz','',2,'[]');
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('ia','T-1','Sinov A','2027-01',1000000,0,'pending'), ('ib','T-2','Sinov B','2027-01',1000000,0,'pending');
insert into public.fin_counterparties (id, kind, name, stir, active) values
  ('cp_bank','bank','Sinov Bank','',true), ('cp_sup','supplier','Sinov Ta''minot MChJ','',true);
insert into public.config (id, "payrollApprovalFrom") values ('finance', '2026-12')
  on conflict (id) do update set "payrollApprovalFrom" = excluded."payrollApprovalFrom";
insert into public.payroll_runs (id, status, "approvedBy", "approvedAt") values ('2026-12', 'approved', 'U_FM', now());
insert into public.payroll_lines (id, "runId", "personType", "personId", "refId", name, gross, payable) values
  ('2026-12__teacher__IQT-T1', '2026-12', 'teacher', 'IQT-T1', 'tch1', 'Sinov O''qituvchi', 3000000, 3000000);
set local session_replication_role = origin;
select zz.clock('2027-01-04 10:00+05');

-- ---------- (A) toza holat: bo'sh modul ----------
\ir kassa-checks.sql
select zz.chk('A0 bo''sh modul: muammo yo''q, band xatosiz', :'bad' || '/' || :'err' || '/' || :'ver', '^0/0/5$');

-- ---------- 1-kun (04.01.2027): ishga tushirish va hujjatlar ----------
select zz.chk('A1 ishga tushirish: sozlamalar va boshlang''ich qoldiq 2 000 000',
  left(zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-01-04","t1":1000000,"l1":200000,"cashLimit":5000000,"orgCashMax":1000000000}')::text$q$), 0)
  || zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":2000000,"startDay":"2027-01-04"}')::text$q$), '"ok": true');
select zz.put('P1', zz.tui('U_KAS', 'man_c1_0001', 'T-1', 600000, 'Sinov Ota', '111'));      -- KO-1 № 1: qisman (4010)
select zz.put('P2', zz.tui('U_KAS', 'man_c1_0002', 'T-2', 1200000, 'Sinov Ona', '112'));     -- KO-1 № 2: faktura + ortiqchasi avansga (6310)
select zz.put('K3', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_other","amount":50000,"partyType":"other","partyName":"Sinov Shaxs","articleId":"IN-06","basis":"Tilxat, 04.01.2027","note":"Kitob uchun","clientRef":"c-k3-0001"}'));
select zz.put('C1', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_expense","amount":300000,"partyType":"counterparty","partyId":"cp_sup","basis":"Hisob-faktura № 5","clientRef":"c-c1-0001","lines":[{"articleId":"EX-32","amount":200000},{"articleId":"EX-07","amount":100000}]}'));
select zz.put('C1p', left(zz.appr('U_FM', zz.id('C1')), 0) || zz.pay('U_KAS', zz.id('C1')));   -- KO-2 № 1
select zz.put('C2', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_expense","amount":50000,"partyType":"other","partyName":"Bozor sotuvchisi","noBasis":true,"clientRef":"c-c2-0001","lines":[{"articleId":"EX-07","amount":50000}]}'));
select zz.put('C2p', left(zz.appr('U_FM', zz.id('C2')), 0) || left(zz.pay('U_KAS', zz.id('C2')), 0) || zz.void('U_FM', zz.id('C2'), 'Xato kiritilgan'));   -- KO-2 № 2: bekor
select zz.put('C3', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_advance","amount":100000,"partyType":"employee","partyId":"teachers:tch1","basis":"Ariza, 04.01.2027","clientRef":"c-c3-0001"}'));
select zz.put('C3p', left(zz.appr('U_FM', zz.id('C3')), 0) || zz.pay('U_KAS', zz.id('C3')));   -- KO-2 № 3: avans
select zz.put('O1', zz.rpc('U_DIR', 'kassa_offset', jsonb_build_object('id', 'sp_ofs_c1', 'teacherId', 'IQT-T1', 'payeeRef', 'teachers:tch1', 'teacherName', 'Sinov',
  'month', '2026-12', 'paid', 300000, 'gross', 3000000, 'advance', 0, 'deduction', 0, 'subBonus', 0, 'net', 3000000, 'carryIn', 0, 'carryOut', 0,
  'studentId', 'T-1', 'requestDate', '2027-01-03')::text));                                    -- naqdsiz dalolatnoma
select zz.chk('A2 1-kun hujjatlari: 3 kirim, 2 chiqim, 1 bekor, 2 dalolatnoma (boshlang''ich qoldiq, o''zaro hisob)',
  (select count(*) filter (where form = 'KO1' and status = 'posted') || ':' || count(*) filter (where form = 'KO2' and status = 'posted') || ':'
       || count(*) filter (where status = 'void') || ':' || count(*) filter (where form = 'ACT' and status = 'posted') from public.cash_docs where desk = 'main'), '^3:2:1:2$');
-- hisobda 3 450 000; sanaldi 3 445 000 — kamomad 5 000 (chiqim orderi o'zi yoziladi)
select zz.put('CL1', zz.as('U_KAS', $q$select public.kassa_day_close('{"desk":"main","day":"2027-01-04","counted":3445000}')::text$q$));
select zz.chk('A3 1-kun kamomad bilan yopildi va tekshirildi',
  (zz.get('CL1')::jsonb ->> 'diff') || ' | ' || zz.as('U_FM', $q$select public.kassa_day_verify('main', '2027-01-04', true, 'Sinov')::text$q$), '^-5000(\.0+)? \| .*"status": "verified"');

-- ---------- 2-kun (05.01.2027): bankdan olingan pul, aniq yopildi ----------
select zz.clock('2027-01-05 10:00+05');
select zz.put('K4', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_bank","amount":1000000,"partyType":"bank","partyId":"cp_bank","basis":"Chek № 12, 05.01.2027","clientRef":"c-k4-0001"}'));
select zz.put('CL2', zz.as('U_KAS', $q$select public.kassa_day_close('{"desk":"main","day":"2027-01-05","counted":4445000}')::text$q$));
select zz.chk('A4 2-kun farqsiz yopildi (tekshirilmagan)', (select status || ':' || trim_scale(closing) || ':' || trim_scale(diff) from public.cash_days where desk = 'main' and day = '2027-01-05'), '^closed:4445000:0$');

-- ---------- 3-kun (06.01.2027): ochiq kun, sinov kassasi, davr surati va qulfi ----------
select zz.clock('2027-01-06 10:00+05');
select zz.put('K5', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_other","amount":30000,"partyType":"other","partyName":"Sinov Shaxs","articleId":"IN-06","basis":"Tilxat, 06.01.2027","note":"Kitob uchun","clientRef":"c-k5-0001"}'));
select zz.put('C4', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_accountable","amount":200000,"partyType":"employee","partyId":"teachers:tch1","basis":"Xo''jalik xaridlari","clientRef":"c-c4-0001"}'));
select zz.put('C4p', left(zz.appr('U_FM', zz.id('C4')), 0) || zz.pay('U_KAS', zz.id('C4')));   -- hisobdorga avans
select zz.put('AV1', zz.rpc('U_FM', 'kassa_adv_report', '{"clientRef":"c-av1-0001","partyId":"teachers:tch1","reportDate":"2027-01-06","lines":[{"articleId":"EX-20","amount":150000,"note":"Chek 7, 06.01"}]}'));   -- avans hisoboti (dalolatnoma)
select zz.put('T0', zz.as('U_DIR', $q$select public.kassa_opening_set('{"desk":"sinov","amount":100000,"startDay":"2027-01-06"}')::text$q$));
select zz.put('T1', zz.rpc('U_KAS', 'kassa_payout_request', '{"desk":"sinov","op":"out_expense","amount":20000,"partyType":"counterparty","partyId":"cp_sup","basis":"Sinov hisob-fakturasi","clientRef":"c-t1-0001","lines":[{"articleId":"EX-32","amount":20000}]}'));
select zz.put('T1p', left(zz.appr('U_FM', zz.id('T1')), 0) || zz.pay('U_KAS', zz.id('T1')));
select zz.put('S1', zz.as('U_DIR', $q$select public.fin_snapshot_take('{"asOf":"2027-01-05","note":"Sinov surati","lock":true}')::text$q$));
select zz.chk('A5 holat: 3 kun (tekshirilgan, yopilgan, ochiq), sinov kassasida 2 hujjat, surat va qulf 05.01.2027',
  (select string_agg(status, ',' order by day) from public.cash_days where desk = 'main') || ' | '
  || (select count(*) from public.cash_docs where desk = 'sinov' and status = 'posted') || ' | '
  || (select count(*) from public.fin_snapshots) || ' | ' || (select "lockedThrough" from public.fin_org where id = 'main'),
  '^verified,closed,open \| 2 \| 1 \| 2027-01-05$');

\ir kassa-checks.sql
select zz.chk('A6 toza holat: tekshiruv hech narsa topmadi (barcha bandlar bajarildi)',
  :'bad' || '/' || :'err' || ' | ' || concat_ws(',', :'c1', :'c2', :'c3', :'c4', :'c5', :'c6', :'c7', :'c8', :'c9', :'c10', :'c11', :'c12', :'c13', :'c14', :'c15', :'c16',
                                               :'c17', :'c18', :'c19', :'c20', :'c21', :'c22'), '^0/0 \| 0(,0){21}$');

-- ---------- (B) tuzilma va huquqlar ----------
savepoint b1;
create function app.zz_sd() returns int language sql security definer as 'select 1';
\ir kassa-checks.sql
rollback to savepoint b1;
select zz.chk('B1 search_path''siz SECURITY DEFINER funksiya (istalgan) — 1-band', :'c1' || '/' || :'bad', '^1/1$');

savepoint b2;
create or replace function app.kassa_version() returns int language sql immutable set search_path = public, app, pg_temp as 'select 6';
\ir kassa-checks.sql
rollback to savepoint b2;
select zz.chk('B2 bazadagi reliz tekshiruv fayli kutganidan boshqa — 2-band (sonlar bandi o''tkazib yuboriladi)', :'c2' || '/' || :'c3' || '/' || :'bad', '^1/0/1$');

savepoint b2b;
drop function app.kassa_version();
\ir kassa-checks.sql
rollback to savepoint b2b;
select zz.chk('B2b reliz belgisi yo''q — 2-band', :'c2' || '/' || :'bad' || '/' || :'ver', '^1/1/0$');

savepoint b3;
create function public.kassa_zz() returns int language sql as 'select 1';
\ir kassa-checks.sql
rollback to savepoint b3;
select zz.chk('B3 ortiqcha ochiq funksiya: soni (3), search_path (4), anon chaqira oladi (6)', :'c3' || '/' || :'c4' || '/' || :'c6' || '/' || :'bad', '^1/1/1/3$');

savepoint b5;
grant execute on function app.kassa_day_hash(text) to authenticated;
grant execute on function app.fin_lock_check(date, text) to anon;
\ir kassa-checks.sql
rollback to savepoint b5;
select zz.chk('B5 ichki funksiya mijoz roliga ochilgan — 5-band (2 ta)', :'c5' || '/' || :'bad', '^2/2$');

savepoint b6;
grant execute on function public.kassa_state(text) to anon;
revoke execute on function public.kassa_refs() from authenticated;
\ir kassa-checks.sql
rollback to savepoint b6;
select zz.chk('B6 ochiq funksiya: anon''ga ochilgan / foydalanuvchidan yopilgan — 6-band (2 ta)', :'c6' || '/' || :'bad', '^2/2$');

savepoint b7;
alter table public.cash_docs disable row level security;
grant insert on public.cash_days to authenticated;
grant select on public.fin_org to anon;
create policy zz_w on public.cash_doc_lines for update using (true);
\ir kassa-checks.sql
rollback to savepoint b7;
select zz.chk('B7 jadval: RLS o''chiq, yozish huquqi, anon o''qiydi, yozish siyosati — 7-band (4 ta; siyosatlar soni — 3-band)', :'c7' || '/' || :'c3' || '/' || :'bad', '^4/1/5$');

savepoint b8;
alter table public.cash_docs disable trigger trg_kassa_doc_guard;
drop trigger trg_fin_zlock on public.payments;
\ir kassa-checks.sql
rollback to savepoint b8;
select zz.chk('B8 himoya triggeri o''chirilgan / olib tashlangan — 8-band (2 ta; soni — 3-band)', :'c8' || '/' || :'c3' || '/' || :'bad', '^2/1/3$');

savepoint b9;
drop index public.cash_docs_number;
\ir kassa-checks.sql
rollback to savepoint b9;
select zz.chk('B9 noyoblik indeksi yo''q — 9-band', :'c9' || '/' || :'bad', '^1/1$');

savepoint b10;
create function public.kassa_state(p_desk text, p_x int) returns jsonb language sql set search_path = public, app, pg_temp as 'select null::jsonb';
revoke all on function public.kassa_state(text, int) from public, anon;
grant execute on function public.kassa_state(text, int) to authenticated;
\ir kassa-checks.sql
rollback to savepoint b10;
select zz.chk('B10 bir xil nomli funksiya (overload) — 10-band (soni — 3-band)', :'c10' || '/' || :'c3' || '/' || :'bad', '^1/1/2$');

-- ---------- (B) ma'lumot yaxlitligi (triggerlarni chetlab buziladi) ----------
savepoint d11;
set local session_replication_role = replica;
update public.cash_days set opening = opening + 1000, closing = closing + 1000, counted = counted + 1000 where desk = 'main' and day = '2027-01-05';
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d11;
select zz.chk('D11 kun boshi o''zgartirilgan: zanjir ikki joyda uziladi (11), kun izi (13)', :'c11' || '/' || :'c13' || '/' || :'bad', '^2/1/3$');

savepoint d11b;
set local session_replication_role = replica;
update public.cash_desks set "openingAmount" = "openingAmount" + 1 where id = 'main';
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d11b;
select zz.chk('D11b boshlang''ich qoldiq o''zgartirilgan: birinchi kun va dalolatnoma mos emas — 11-band (2 ta)', :'c11' || '/' || :'bad', '^2/2$');

savepoint d12;
set local session_replication_role = replica;
update public.cash_docs set amount = amount + 1000 where id = zz.id('K3');
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d12;
select zz.chk('D12 yopilgan kundagi order summasi o''zgartirilgan: kun jamlari (12: kirim, kun oxiri), izi (13), qatorlari (16)',
  :'c12' || '/' || :'c13' || '/' || :'c16' || '/' || :'bad', '^2/1/1/4$');

savepoint d13;
set local session_replication_role = replica;
update public.cash_docs set "partyId" = 'cp_sup', "partyType" = 'counterparty' where id = zz.id('K3');
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d13;
select zz.chk('D13 yopilgan kun hujjatining tomoni o''zgartirilgan — faqat kun izi (13)', :'c13' || '/' || :'bad', '^1/1$');

savepoint d14;
set local session_replication_role = replica;
update public.doc_counters set "lastNo" = "lastNo" + 1 where desk = 'main' and series = 'KO2' and year = 2027;
delete from public.cash_doc_lines where "docId" = zz.id('K5');
delete from public.cash_docs where id = zz.id('K5');                 -- ochiq kundagi oxirgi kirim orderi o'chirilgan
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d14;
select zz.chk('D14 raqamlash: hisoblagich oshirilgan (KO-2) va oxirgi order o''chirilgan (KO-1) — 14-band (2 ta)', :'c14' || '/' || :'bad', '^2/2$');

savepoint d15;
set local session_replication_role = replica;
update public.cash_days set "sheetFrom" = "sheetFrom" + 1, "sheetTo" = "sheetTo" + 2 where desk = 'main' and day = '2027-01-05';
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d15;
select zz.chk('D15 kassa kitobi varaqlari: uzluksiz emas va soni mos emas — 15-band (2 ta)', :'c15' || '/' || :'bad', '^2/2$');

savepoint d16;
set local session_replication_role = replica;
update public.cash_doc_lines set amount = amount - 1 where "docId" = (select "openingDocId" from public.cash_desks where id = 'main');
update public.cash_doc_lines set amount = amount - 1 where "docId" = (select id from public.cash_docs where op = 'nc_offset' and status = 'posted') and "lineNo" = 1;
update public.cash_doc_lines set amount = amount + 10000 where "docId" = zz.id('C1') and "lineNo" = 1;
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d16;
select zz.chk('D16 hujjat qatorlari o''zgartirilgan: boshlang''ich qoldiq, o''zaro hisob, chiqim orderi — 16-band (3 ta), kun izi (13)',
  :'c16' || '/' || :'c13' || '/' || :'bad', '^3/1/4$');

savepoint d17;
set local session_replication_role = replica;
update public.cash_docs set "businessDay" = '2027-01-05' where id = zz.id('K3');
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d17;
select zz.chk('D17 hujjatning ish kuni kassa kuniga teng emas — 17-band', :'c17' || '/' || :'bad', '^1/1$');

savepoint d18;
set local session_replication_role = replica;
delete from public.payment_allocations where id = (select a.id from public.payment_allocations a where a."docId" = zz.doc('main', 'KO1', 2) order by a.id limit 1);
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d18;
select zz.chk('D18 o''quv to''lovi taqsimotidan qator o''chirilgan — 18-band', :'c18' || '/' || :'bad', '^1/1$');

savepoint d19;
set local session_replication_role = replica;
update public.expenses set "cashDocId" = 'kd_yoq' where id = (select e.id from public.expenses e where e."cashDocId" = zz.id('C1') order by e.id limit 1);
update public.staff_advances set "cashDocId" = zz.id('T1') where "cashDocId" = zz.id('C3');
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d19;
select zz.chk('D19 bog''lanish: yo''q hujjatga va sinov kassasi hujjatiga — 19-band (2 ta); moslik (20): P4 va P5 ikki tomondan',
  :'c19' || '/' || :'c20' || '/' || :'bad', '^2/4/6$');

savepoint d20;
set local session_replication_role = replica;
insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_zz_1', '2027-01-05', '2027-01', 'Boshqa', 1000, 'kassani chetlab', 'cash');
insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values ('man_zz_1', 'T-1', 'cash', 1000, 'applied', true, '{}', '2027-01-05 12:00+05');
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d20;
select zz.chk('D20 kassani chetlab yozilgan naqd xarajat va naqd o''quv to''lovi — 20-band (P4, P1)', :'c20' || '/' || :'bad', '^2/2$');

savepoint d21;
set local session_replication_role = replica;
update public.fin_snapshots set payload = payload || '{"zz":1}'::jsonb;
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d21;
select zz.chk('D21 davr surati mazmuni o''zgartirilgan — 21-band', :'c21' || '/' || :'bad', '^1/1$');

savepoint d22;
set local session_replication_role = replica;
update public.fin_org set "lockedThrough" = '2027-01-06' where id = 'main';
update public.cash_desks set "startDay" = null where id = 'main';
set local session_replication_role = origin;
\ir kassa-checks.sql
rollback to savepoint d22;
select zz.chk('D22 sozlamalar ziddiyati: qulf bugungi kunda; ishga tushirilgan, lekin boshlang''ich qoldiq yo''q — 22-band (2 ta)', :'c22' || '/' || :'bad', '^2/2$');

-- ---------- (C) qaytarilgach — toza; modul bo'lmagan baza ----------
\ir kassa-checks.sql
select zz.chk('C1 buzilishlar qaytarilgach yana toza', :'bad' || '/' || :'err', '^0/0$');

savepoint c2;
alter table public.cash_docs rename to cash_docs_zz;
\ir kassa-checks.sql
rollback to savepoint c2;
select zz.chk('C2 kassa jadvali yo''q baza: faqat 1-band ishlaydi, muammo yo''q', :'has_kassa' || '/' || :'bad' || '/' || :'err', '^f/0/0$');

-- ---------- Natija ----------
\o
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 600), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
