-- =====================================================================
-- test-fin-prereq.sql — moliya ish rejasi 0-bosqichi (fin-prereq.sql, add-credit.sql RF-03, telegram.sql director_daily) sinovi:
--   (A) yagona «tushgan pul» ta'rifi: app.counts_as_receipt / app.pay_day (admin.html isCashPay / payDay bilan bir xil);
--   (B) director_daily: kassa kuni bo'yicha, ':s:' bolalari va 'reattr' siz, 'late' (bugun kiritilgan, oldingi kun uchun);
--   (C) server vaqti (createdAt / statusAt / updatedAt) va «kim» (byUid / byEmail) — mijoz yuborgani emas;
--   (D) record_manual_payment — bitta tranzaksiya, idempotent, sana va huquq tekshiruvi, eski «pending» qatorni tugatish;
--   (E) huquqlar I: RF-01/02/03/05/07.
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub) — RLS va GRANT haqiqiy.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-fin-prereq.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa (jonli baza) — darhol to'xtaydi.
--   Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-fin-prereq.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  if p_uid is null then execute 'set local role anon'; else execute 'set local role authenticated'; end if;
  begin
    execute p_q into r;
  exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles") values
  ('U_DIR','d@x','director','active','[]'), ('U_FM','f@x','finance_mgr','active','[]'), ('U_KAS','k@x','kassir','active','[]'),
  ('U_ZAV','z@x','zavuch','active','[]'), ('U_TCH','t@x','teacher','active','[]'), ('U_TRE','g@x','treasurer','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]'), ('s2','T-2','Sinov B',5,'A','uz','',2,'[]'), ('s3','T-3','Sinov C',6,'B','uz','',3,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('inv1','T-1','Sinov A','2026-10',1000000,0,'pending'), ('inv2','T-1','Sinov A','2026-11',1000000,0,'pending'),
  ('inv3','T-3','Sinov C','2026-11',800000,0,'pending');
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','[]');
-- (B) uchun to'lovlar: d = 2026-11-09 (Toshkent). createdAt aniq (tizim yozuvi sifatida).
insert into public.payments (id, "studentId", provider, amount, status, raw, "createdAt") values
  ('pa','T-1','cash',100,'applied',null,'2026-11-09 10:00+05'),
  ('pb','T-1','click',200,'confirmed',null,'2026-11-09 23:30+05'),
  ('pc:s:T-2','T-2','cash',50,'applied',null,'2026-11-09 11:00+05'),
  ('pd','T-2','reattr',70,'applied',null,'2026-11-09 12:00+05'),
  ('pe','T-2','cash',300,'pending',null,'2026-11-09 12:30+05'),
  ('pf','T-2','bank',400,'applied','{"manual":true,"date":"2026-11-09"}','2026-11-10 09:00+05'),
  ('pg',null,'uzum',500,'unmatched',null,'2026-11-09 13:00+05'),
  ('ph','T-2','click',600,'split',null,'2026-11-09 14:00+05'),
  ('pi','T-2','cash',700,'applied',null,'2026-11-08 18:00+05');
set local session_replication_role = origin;

-- ---------- (A) yagona ta'rif ----------
select zz.chk('A1 applied naqd — tushgan', app.counts_as_receipt('p1','applied','cash',100)::text, '^true$');
select zz.chk('A2 bo''lingan to''lov bolasi (:s:) — yo''q', app.counts_as_receipt('p1:s:T-1','applied','cash',100)::text, '^false$');
select zz.chk('A3 avans ko''chirmasi (reattr) — yo''q', app.counts_as_receipt('p2','applied','reattr',100)::text, '^false$');
select zz.chk('A4 pending — yo''q', app.counts_as_receipt('p3','pending','cash',100)::text, '^false$');
select zz.chk('A5 split ota qator — bor', app.counts_as_receipt('p4','split','click',100)::text, '^true$');
select zz.chk('A6 summa 0 — yo''q', app.counts_as_receipt('p5','applied','cash',0)::text, '^false$');
select zz.chk('A7 kun — Toshkent sanasi', app.pay_day('2026-11-10 20:00+00', null)::text, '^2026-11-11$');
select zz.chk('A8 qo''lda — kassir sanasi', app.pay_day('2026-11-10 06:00+00', '{"manual":true,"date":"2026-11-01"}')::text, '^2026-11-01$');
select zz.chk('A9 qo''lda — kelajak sana rad', app.pay_day('2026-11-10 06:00+00', '{"manual":true,"date":"2026-11-12"}')::text, '^2026-11-10$');
select zz.chk('A10 qo''lda — 31 kundan eski rad', app.pay_day('2026-11-10 06:00+00', '{"manual":true,"date":"2026-10-09"}')::text, '^2026-11-10$');
select zz.chk('A11 qo''lda — aynan 31 kun oldin qabul', app.pay_day('2026-11-10 06:00+00', '{"manual":true,"date":"2026-10-10"}')::text, '^2026-10-10$');
select zz.chk('A12 qo''lda emas — sana e''tiborsiz', app.pay_day('2026-11-10 06:00+00', '{"date":"2026-11-01"}')::text, '^2026-11-10$');
select zz.chk('A13 yaroqsiz sana (30-fevral) — kiritilgan kun', app.pay_day('2026-03-05 06:00+00', '{"manual":true,"date":"2026-02-30"}')::text, '^2026-03-05$');

-- ---------- (B) director_daily ----------
select zz.chk('B1 kunlik to''lovlar: soni / summa',
  (select (director_daily('2026-11-09') -> 'payments' ->> 'count') || '/' || (director_daily('2026-11-09') -> 'payments' ->> 'sum')), '^5/1800$');
select zz.chk('B2 usul bo''yicha',
  (select string_agg(k || '=' || v, ',' order by k) from jsonb_each_text(director_daily('2026-11-09') -> 'payments' -> 'byProvider') e(k, v)),
  '^bank=400,cash=100,click=800,uzum=500$');
select zz.chk('B3 biriktirilmagan', (director_daily('2026-11-09') ->> 'unmatched'), '^1$');
select zz.chk('B4 kechikib kiritilgan (bugun yo''q)', (director_daily('2026-11-09') -> 'late' ->> 'count'), '^0$');
select zz.chk('B5 ertasi kuni: kechikib kiritilgan 1 ta, 400',
  (select (director_daily('2026-11-10') -> 'late' ->> 'count') || '/' || (director_daily('2026-11-10') -> 'late' ->> 'sum')), '^1/400$');
select zz.chk('B6 ertasi kuni: kassa to''lovi yo''q (orqaga sanalgan)', (director_daily('2026-11-10') -> 'payments' ->> 'count'), '^0$');
select zz.chk('B7 Direktor chaqira oladi', zz.as('U_DIR', $q$select (public.director_daily('2026-11-09') -> 'payments' ->> 'count')$q$), '^5$');
select zz.chk('B8 kassir chaqira olmaydi', zz.as('U_KAS', $q$select public.director_daily('2026-11-09')::text$q$), '^ERR 42501');
select zz.chk('B9 fin_receipts mijozga yopiq', zz.as('U_DIR', $q$select count(*)::text from app.fin_receipts('2026-11-09','2026-11-09')$q$), '^ERR 42501');

-- ---------- (C) server vaqti va «kim» ----------
select zz.chk('C1 kassir payments createdAt yubordi — server vaqti',
  zz.as('U_KAS', $q$with x as (insert into public.payments(id, "studentId", provider, amount, status, "createdAt") values ('c1','T-2','cash',10,'pending','2020-01-01') returning 1) select count(*)::text from x$q$), '^1$');
select zz.chk('C1b createdAt = now()', (select ("createdAt" = now())::text from public.payments where id = 'c1'), '^true$');
select zz.chk('C2 statusAt qo''yildi', (select ("statusAt" = now())::text from public.payments where id = 'c1'), '^true$');
select zz.chk('C3 moliya createdAt ni o''zgartira olmaydi',
  zz.as('U_FM', $q$with x as (update public.payments set "createdAt" = '2020-01-01', "statusAt" = '2020-01-01', amount = 11 where id = 'c1' returning 1) select count(*)::text from x$q$), '^1$');
select zz.chk('C3b createdAt va statusAt (holat o''zgarmadi) saqlandi',
  (select ("createdAt" = now() and "statusAt" = now() and amount = 11)::text from public.payments where id = 'c1'), '^true$');
insert into public.payments(id, "studentId", provider, amount, status, "createdAt") values ('c4','T-2','click',5,'pending','2021-05-05 10:00+05');
select zz.chk('C4 tizim (server) yozuvi createdAt ni saqlaydi',
  (select ("createdAt" = '2021-05-05 10:00+05')::text from public.payments where id = 'c4'), '^true$');
select zz.chk('C5 xarajat: createdAt / updatedAt — server',
  zz.as('U_FM', $q$with x as (insert into public.expenses(id, date, month, category, amount, note, "createdAt", "updatedAt") values ('e1','2026-11-09','2026-11','Boshqa',1000,'sinov','2020-01-01','2020-01-01') returning 1) select count(*)::text from x$q$), '^1$');
select zz.chk('C5b xarajat vaqtlari = now()', (select ("createdAt" = now() and "updatedAt" = now())::text from public.expenses where id = 'e1'), '^true$');
select zz.chk('C6 maosh berish: byEmail mijoznikidan emas',
  zz.as('U_DIR', $q$with x as (insert into public.salary_payments(id, "teacherId", "payeeRef", "teacherName", month, paid, "byEmail", date) values ('sp1','IQT-T1','teachers:tch1','Sinov O''qituvchi','2026-11',100,'spoof@x','2026-11-09') returning 1) select count(*)::text from x$q$), '^1$');
select zz.chk('C6b byUid / byEmail — server', (select "byUid" || '|' || "byEmail" from public.salary_payments where id = 'sp1'), '^U_DIR\|d@x$');

-- ---------- (D) record_manual_payment ----------
select zz.chk('D1 kassir: naqd to''lov qabul qilindi',
  zz.as('U_KAS', $q$select (r ->> 'ok') || '/' || (r ->> 'dup') from (select public.record_manual_payment('man_1731000000000_abc12','T-1',1500000,'cash',to_char((now() at time zone 'Asia/Tashkent')::date,'YYYY-MM-DD'),'sinov','Oktyabr','Sinov A',now()) r) z$q$), '^true/false$');
select zz.chk('D2 payments qatori: applied, naqd, server vaqti, qo''lda',
  (select status || '|' || provider || '|' || ("createdAt" = now())::text || '|' || (raw ->> 'manual') || '|' || (raw ->> 'byUid') from public.payments where id = 'man_1731000000000_abc12'),
  '^applied\|cash\|true\|true\|U_KAS$');
select zz.chk('D3 fakturalar: eng eskisi to''liq, keyingisi qisman',
  (select string_agg(id || '=' || status || ':' || "paidAmount"::bigint, ',' order by id) from public.invoices where "studentId" = 'T-1'), '^inv1=paid:1000000,inv2=partial:500000$');
select zz.chk('D4 ota-onaga xabar navbati — bitta', (select count(*)::text from public.notify_queue where id = 'pay__man_1731000000000_abc12'), '^1$');
select zz.chk('D5 qayta yuborish — dup, ikki marta qo''llanmaydi',
  zz.as('U_KAS', $q$select (r ->> 'ok') || '/' || (r ->> 'dup') from (select public.record_manual_payment('man_1731000000000_abc12','T-1',1500000,'cash',null,'','','',null) r) z$q$), '^true/true$');
select zz.chk('D5b faktura o''zgarmadi', (select "paidAmount"::bigint::text from public.invoices where id = 'inv2'), '^500000$');
select zz.chk('D6 orqaga 31 kun — qabul, kassa kuni shu sana',
  zz.as('U_KAS', $q$select (r ->> 'day') = to_char((now() at time zone 'Asia/Tashkent')::date - 31,'YYYY-MM-DD') from (select public.record_manual_payment('man_1731000000001_abc12','T-3',100000,'bank',to_char((now() at time zone 'Asia/Tashkent')::date - 31,'YYYY-MM-DD'),'','','',null) r) z$q$), '^true$');
select zz.chk('D6b pay_day = tanlangan sana',
  (select (app.pay_day("createdAt", raw) = (now() at time zone 'Asia/Tashkent')::date - 31)::text from public.payments where id = 'man_1731000000001_abc12'), '^true$');
select zz.chk('D7 kelajak sana — kiritilgan kun, dateAdjusted',
  zz.as('U_KAS', $q$select (r ->> 'dateAdjusted') || '/' || ((r ->> 'day') = to_char((now() at time zone 'Asia/Tashkent')::date,'YYYY-MM-DD'))::text from (select public.record_manual_payment('man_1731000000002_abc12','T-3',100000,'terminal',to_char((now() at time zone 'Asia/Tashkent')::date + 2,'YYYY-MM-DD'),'','','',null) r) z$q$), '^true/true$');
select zz.chk('D7b so''ralgan sana raw.dateRequested da', (select (raw ? 'dateRequested')::text from public.payments where id = 'man_1731000000002_abc12'), '^true$');
select zz.chk('D8 Click qo''lda kiritilmaydi', zz.as('U_KAS', $q$select public.record_manual_payment('man_1731000000003_abc12','T-3',1000,'click',null,'','','',null)::text$q$), '^ERR 22023');
select zz.chk('D9 noto''g''ri payId', zz.as('U_KAS', $q$select public.record_manual_payment('x1','T-3',1000,'cash',null,'','','',null)::text$q$), '^ERR 22023');
select zz.chk('D10 summa 0', zz.as('U_KAS', $q$select public.record_manual_payment('man_1731000000004_abc12','T-3',0,'cash',null,'','','',null)::text$q$), '^ERR 22023');
select zz.chk('D11 noma''lum o''quvchi', zz.as('U_KAS', $q$select public.record_manual_payment('man_1731000000005_abc12','T-404',1000,'cash',null,'','','',null)::text$q$), '^ERR 22023');
select zz.chk('D12 o''qituvchi — ruxsat yo''q', zz.as('U_TCH', $q$select public.record_manual_payment('man_1731000000006_abc12','T-3',1000,'cash',null,'','','',null)::text$q$), '^ERR 42501');
select zz.chk('D13 anon — ruxsat yo''q', zz.as(null, $q$select public.record_manual_payment('man_1731000000007_abc12','T-3',1000,'cash',null,'','','',null)::text$q$), '^ERR 42501');
select zz.chk('D14 eski mijozdan qolgan «pending» qator — tugatiladi',
  zz.as('U_KAS', $q$with x as (insert into public.payments(id, "studentId", provider, amount, status, raw) values ('man_legacy_00001','T-2','cash',200000,'pending','{"manual":true}') returning 1) select count(*)::text from x$q$), '^1$');
select zz.chk('D14b record_manual_payment qo''llaydi',
  zz.as('U_KAS', $q$select (r ->> 'ok') from (select public.record_manual_payment('man_legacy_00001','T-2',200000,'cash',null,'','','',null) r) z$q$), '^true$');
select zz.chk('D14c holat applied, avans 200000',
  (select p.status || '|' || c.credit::bigint from public.payments p, public.student_credit c where p.id = 'man_legacy_00001' and c.id = 'T-2'), '^applied\|200000$');
select zz.chk('D15 «pending» qator summasi boshqa — rad (mismatch)',
  zz.as('U_KAS', $q$with x as (insert into public.payments(id, "studentId", provider, amount, status) values ('man_legacy_00002','T-2','cash',300000,'pending') returning 1) select (select public.record_manual_payment('man_legacy_00002','T-2',999,'cash',null,'','','',null) ->> 'reason') from x$q$), '^mismatch$');
-- g8: usul boshqa — kassa moduli yo'q yoki kassa ishlamayapti: avvalgidek tugatiladi (kassa ishlaganda «mismatch» — test-kassa-pay.sql N6)
select zz.chk('D15b «pending» qatorni boshqa usul bilan tugatish — kassasiz (ishlamayotgan kassa) avvalgidek qo''llanadi',
  zz.as('U_KAS', $q$with x as (insert into public.payments(id, "studentId", provider, amount, status) values ('man_legacy_00003','T-2','cash',1000,'pending') returning 1) select (select public.record_manual_payment('man_legacy_00003','T-2',1000,'bank',null,'','','',null) ->> 'status') from x$q$), '^applied$');
select zz.chk('D16 G''aznachi ham kirita oladi',
  zz.as('U_TRE', $q$select (public.record_manual_payment('man_1731000000008_abc12','T-3',1000,'cash',null,'','','',null) ->> 'ok')$q$), '^true$');

-- ---------- (D, davomi) ko'rik topilmalari ----------
select zz.chk('D17 NaN summa — rad', zz.as('U_KAS', $q$select public.record_manual_payment('man_1731000000009_abc12','T-3','NaN'::numeric,'cash',null,'','','',null)::text$q$), '^ERR 22023');
select zz.chk('D17b Infinity summa — rad', zz.as('U_KAS', $q$select public.record_manual_payment('man_1731000000010_abc12','T-3','Infinity'::numeric,'cash',null,'','','',null)::text$q$), '^ERR 22023');
select zz.chk('D18 sana bo''sh — kassa kuni kiritilgan kun (p_captured)',
  zz.as('U_KAS', $q$select (r ->> 'day') = to_char((now() at time zone 'Asia/Tashkent')::date - 1,'YYYY-MM-DD') from (select public.record_manual_payment('man_1731000000011_abc12','T-3',1000,'cash',null,'','','',now() - interval '1 day') r) z$q$), '^true$');
select zz.chk('D19 «qaysi oy uchun» uzun matn — qabul',
  zz.as('U_KAS', $q$select (public.record_manual_payment('man_1731000000012_abc12','T-3',1000,'cash',null,'',repeat('Oyyy 2026, ',18),'',null) ->> 'ok')$q$), '^true$');
select zz.chk('D19b 198 belgi to''liq saqlandi', (select length(raw ->> 'forPeriod')::text from public.payments where id = 'man_1731000000012_abc12'), '^198$');
select zz.chk('A14 NaN summa — tushum emas', app.counts_as_receipt('p6','applied','cash','NaN'::numeric)::text, '^false$');

-- ---------- (F) RF-04: to'lov yozuvisiz pul qo'llanmaydi; avans faqat RPC orqali ----------
select zz.chk('F1 kassir apply_payment — payments qatorisiz rad',
  zz.as('U_KAS', $q$select public.apply_payment('T-3', 500000, 'cash', 'soxta-id-1')::text$q$), '^ERR 42501');
select zz.chk('F1b moliya ham rad', zz.as('U_FM', $q$select public.apply_payment('T-3', 500000, 'cash', 'soxta-id-2')::text$q$), '^ERR 42501');
select zz.chk('F2 eski mijoz yo''li (avval pending qator) — ishlaydi',
  zz.as('U_KAS', $q$with x as (insert into public.payments(id, "studentId", provider, amount, status, raw) values ('man_old_flow_001','T-3','cash',1000,'pending','{"manual":true}') returning 1) select (select public.apply_payment('T-3', 1000, 'cash', 'man_old_flow_001') ->> 'ok') from x$q$), '^true$');
select zz.chk('F3 Direktor NaN — bad-amount', zz.as('U_DIR', $q$select public.apply_payment('T-3', 'NaN'::numeric, 'cash', 'fix_x') ->> 'reason'$q$), '^bad-amount$');
select zz.chk('F4 kassir summa 0 (avansni qo''llash) — ruxsat', zz.as('U_KAS', $q$select public.apply_payment('T-3', 0, 'credit', null) ->> 'ok'$q$), '^true$');
select zz.chk('F5 kassir add_credit — rad (manfiy ham)', zz.as('U_KAS', $q$select public.add_credit('T-2', -1000, 'recompute', '', 'f5')::text$q$), '^ERR 42501');
select zz.chk('F6 moliya student_credit''ni to''g''ridan-to''g''ri o''zgartira olmaydi',
  zz.as('U_FM', $q$with x as (update public.student_credit set credit = 9999999 where id = 'T-2' returning 1) select count(*)::text from x$q$), '^0$');
select zz.chk('F6b g''aznachi student_credit qo''sha olmaydi',
  zz.as('U_TRE', $q$with x as (insert into public.student_credit(id, "studentId", credit) values ('T-9','T-9',7000000) returning 1) select count(*)::text from x$q$), '^ERR 42501');
select zz.chk('F7 moliya avansni ko''chira oladi (reattribute_avans, ichki bayroq)',
  zz.as('U_FM', $q$select (public.reattribute_avans('T-2','T-3',50000,'sinov','f7') ->> 'ok')$q$), '^true$');
select zz.chk('F8 kassir apply_to_invoice — payments qatorisiz rad',
  zz.as('U_KAS', $q$select public.apply_to_invoice('inv3', 1000, 'cash', 'soxta-id-3')::text$q$), '^ERR 42501');
insert into public.payments(id, "studentId", provider, amount, status, "payerName", matched) values ('click_unm_1','','click',300000,'unmatched','Sinov',false);
select zz.chk('F9 kassir biriktirish (assign_payment) — ishlaydi',
  zz.as('U_KAS', $q$select (public.assign_payment('click_unm_1','T-3') ->> 'ok')$q$), '^true$');
insert into public.payments(id, "studentId", provider, amount, status, "payerName", matched) values ('click_unm_2','','click',300000,'unmatched','Sinov',false);
select zz.chk('F10 moliya bo''lish (split_payment) — ishlaydi',
  zz.as('U_FM', $q$select (public.split_payment('click_unm_2','click','[{"sid":"T-1","amount":100000},{"sid":"T-3","amount":200000}]'::jsonb) ->> 'ok')$q$), '^true$');

-- ---------- (C, davomi) qaytarish: «kim» — server ----------
select zz.chk('C7 qaytarish: byEmail Direktorniki (p_by e''tiborsiz)',
  zz.as('U_DIR', $q$select (public.refund_invoice('invoice','inv1',100000,'sinov qaytarish',false,'spoof@x','ref-c7') ->> 'ok')$q$), '^true$');
select zz.chk('C7b refunds: byUid / byEmail', (select "byUid" || '|' || "byEmail" from public.refunds where "targetId" = 'inv1' limit 1), '^U_DIR\|d@x$');

-- ---------- (E) huquqlar I ----------
select zz.chk('E1 kassir xarajat yoza olmaydi (RF-01)',
  zz.as('U_KAS', $q$with x as (insert into public.expenses(id, date, month, category, amount) values ('e2','2026-11-09','2026-11','Boshqa',1) returning 1) select count(*)::text from x$q$), '^ERR 42501');
select zz.chk('E2 O''IBDO'' xarajat yoza olmaydi (RF-05)',
  zz.as('U_ZAV', $q$with x as (insert into public.expenses(id, date, month, category, amount) values ('e3','2026-11-09','2026-11','Boshqa',1) returning 1) select count(*)::text from x$q$), '^ERR 42501');
select zz.chk('E3 kassir xarajatni o''chira olmaydi (RF-01)',
  zz.as('U_KAS', $q$with x as (delete from public.expenses where id = 'e1' returning 1) select count(*)::text from x$q$), '^0$');
select zz.chk('E3b xarajat joyida', (select count(*)::text from public.expenses where id = 'e1'), '^1$');
select zz.chk('E4 moliya xarajatni o''chira oladi',
  zz.as('U_FM', $q$with x as (delete from public.expenses where id = 'e1' returning 1) select count(*)::text from x$q$), '^1$');
select zz.chk('E5 kassir xodim avansini yoza olmaydi (RF-02)',
  zz.as('U_KAS', $q$with x as (insert into public.staff_advances(id, "teacherId", "payeeRef", "teacherName", amount, month, date) values ('adv1','IQT-T1','teachers:tch1','Sinov',100,'2026-11','2026-11-09') returning 1) select count(*)::text from x$q$), '^ERR 42501');
select zz.chk('E6 moliya xodim avansini yoza oladi',
  zz.as('U_FM', $q$with x as (insert into public.staff_advances(id, "teacherId", "payeeRef", "teacherName", amount, month, date, "createdAt") values ('adv2','IQT-T1','teachers:tch1','Sinov',100,'2026-11','2026-11-09','2020-01-01') returning 1) select count(*)::text from x$q$), '^1$');
select zz.chk('E6b avans createdAt — server', (select ("createdAt" = now())::text from public.staff_advances where id = 'adv2'), '^true$');
select zz.chk('E7 kassir avansni o''zgartira olmaydi',
  zz.as('U_KAS', $q$with x as (update public.staff_advances set amount = 1 where id = 'adv2' returning 1) select count(*)::text from x$q$), '^0$');
select zz.chk('E8 moliya avansni (to''lovsiz) ko''paytira olmaydi (RF-03)',
  zz.as('U_FM', $q$select public.add_credit('T-3', 100000, 'recompute', '', 'e8')::text$q$), '^ERR 42501');
select zz.chk('E9 Direktor ko''paytira oladi',
  zz.as('U_DIR', $q$select (public.add_credit('T-3', 100000, 'recompute', '', 'e9') ->> 'ok')$q$), '^true$');
select zz.chk('E10 moliya kamaytira oladi',
  zz.as('U_FM', $q$select (public.add_credit('T-3', -50000, 'recompute', '', 'e10') ->> 'ok')$q$), '^true$');
select zz.chk('E11 avans jurnali o''chirilmaydi — Direktor (RF-07)',
  zz.as('U_DIR', $q$with x as (delete from public.credit_ledger returning 1) select count(*)::text from x$q$), '^0$');
select zz.chk('E11b jurnal yozuvlari joyida', (select (count(*) > 0)::text from public.credit_ledger), '^true$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(got, '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
