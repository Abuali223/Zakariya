-- =====================================================================
-- test-fin-lock.sql — moliya ish rejasi F2.8 (2-qism, reliz 19): oy qulfi barcha pul jadvallariga (fin-period.sql:
--   app.fin_lock_invoices / _credit / _refunds / _payroll) sinovi:
--   (I) hisob-fakturalar: yopilgan oy fakturasi qayta hisoblanmaydi, bekor qilinmaydi, o'chirilmaydi, yangisi yozilmaydi, oyi
--       yopilgan oyga / oydan ko'chmaydi; to'lov qo'llanishi (eski qarzga to'lov) va hisoblanishga tegmaydigan belgilar — mumkin;
--   (C) avans (kredit) harakatlari: foydalanuvchi yozuvida sana — server vaqti (orqa sana yo'q); yopilgan davr yozuvi o'zgarmaydi
--       va o'chirilmaydi;
--   (R) qaytarishlar: yopilgan davr yozuvining summasi o'zgarmaydi, yozuv o'chirilmaydi (ism — mumkin);
--   (P) oylik vedomost: yopilgan oy (oxirgi kuni qulf sanasigacha) vedomosti tasdiqlanmaydi, qaytarilmaydi, qayta ochilmaydi,
--       qatori tasdiqlanmaydi; joriy oy — mumkin;
--   (M) oy oxiri ro'yxati: tasdiqlash rejimidagi tugagan oy vedomosti tasdiqlanmagan — ogohlantirish;
--   (B) chegaralar: qulf sanasi oy ichida (faktura — oyning 1-kuni, vedomost — oxirgi kuni); (S) server mustasno; (N) qulf olinsa — hammasi mumkin.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-fin-lock.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.invoices) then
    raise exception 'test-fin-lock.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
-- Foydalanuvchi RPC'si / to'g'ridan-to'g'ri yozuvi (RLS bilan): rol authenticated; SYSTEM — server (service_role da'vosi)
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' when p_uid = 'SYSTEM' then '{"role":"service_role"}'
                                                else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  if p_uid is null then execute 'set local role anon'; elsif p_uid <> 'SYSTEM' then execute 'set local role authenticated'; end if;
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
-- Foydalanuvchi nomidan ishlayotgan server funksiyasi (security definer — RLS'siz, lekin JWT da'vosi foydalanuvchiniki): triggerlar
--   «tizim emas» deb ko'radi — jadvalda o'zgartirish / o'chirish siyosati bo'lmasa ham trigger qoidasi tekshiriladi
create or replace function zz.asu(p_uid text, p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  begin
    execute p_q into r;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    r := 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
  end;
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
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
create or replace function zz.inv(p_id text) returns text language sql as $$
  select coalesce((select i.month || ':' || trim_scale(i.amount) || ':' || trim_scale(coalesce(i."paidAmount", 0)) || ':' || coalesce(i.status, '')
                     from public.invoices i where i.id = p_id), 'yo''q') $$;
create or replace function zz.mc(p_month text) returns jsonb language sql as $$
  select (zz.js(zz.as('U_DIR', format('select public.kassa_month_check(%L, %L)::text', 'main', p_month))) -> 'items') $$;
create or replace function zz.item(p_items jsonb, p_code text) returns jsonb language sql as $$
  select i from jsonb_array_elements(p_items) i where i ->> 'code' = p_code limit 1 $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]'), ('s2','T-2','Sinov B',5,'A','uz','',2,'[]'), ('s3','T-3','Sinov C',5,'A','uz','',3,'[]'),
  ('s4','T-4','Sinov D',5,'A','uz','',4,'[]');
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('d1','T-1','Sinov A','2026-12',1000000,0,'pending'),      -- qayta hisoblash / to'lov qo'llanishi
  ('d2','T-2','Sinov B','2026-12',1000000,0,'pending'),      -- bekor qilish / o'chirish
  ('d3','T-4','Sinov D','2026-12',1000000,0,'pending'),      -- server va hisoblanishga tegmaydigan belgilar
  ('j1','T-1','Sinov A','2027-01',1000000,0,'pending'),      -- ochiq oy
  ('n1','T-3','Sinov C','2026-11',1000000,1000000,'paid');   -- oldingi yopilgan oy
insert into public.credit_ledger (id, "studentId", "studentName", delta, "balanceAfter", reason, note, "at") values
  ('cl_d','T-1','Sinov A',100000,100000,'manual','dekabr harakati','2026-12-20 10:00+05');
insert into public.student_credit (id, "studentId", credit) values ('T-1','T-1',100000);
insert into public.refunds (id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, "createdAt") values
  ('rf_d','invoice','n1','T-3','Sinov C',50000,'dekabr qaytarishi','','2026-11','2026-12-15 10:00+05');
insert into public.config (id, "payrollApprovalFrom") values ('finance', '2026-11')
  on conflict (id) do update set "payrollApprovalFrom" = excluded."payrollApprovalFrom";
insert into public.payroll_runs (id, status, "preparedBy", "preparedAt", "submittedAt", "approvedBy", "approvedAt") values
  ('2026-11', 'approved', 'U_FM', '2026-12-01 10:00+05', '2026-12-01 10:00+05', 'U_DIR', '2026-12-02 10:00+05'),
  ('2026-12', 'submitted', 'U_FM', '2027-01-03 10:00+05', '2027-01-03 10:00+05', null, null);
insert into public.payroll_lines (id, "runId", "personType", "personId", "refId", name, gross, payable, "needsDirector") values
  ('2026-11__teacher__IQT-T1', '2026-11', 'teacher', 'IQT-T1', 'tch1', 'Sinov O''qituvchi', 3000000, 3000000, false),
  ('2026-12__teacher__IQT-T1', '2026-12', 'teacher', 'IQT-T1', 'tch1', 'Sinov O''qituvchi', 3000000, 3000000, true);
set local session_replication_role = origin;
select zz.clock('2027-01-05 10:00+05');

-- ---------- Qulf ----------
select zz.chk('L0 Direktor davrni 31.12.2026 gacha yopdi',
  zz.as('U_DIR', $q$select (public.fin_period_lock('2026-12-31', 'Dekabr yopildi (sinov)') ->> 'lockedThrough')$q$), '^2026-12-31$');

-- ---------- (I) hisob-fakturalar ----------
select zz.chk('I1 yopilgan oy (dekabr) fakturasini qayta hisoblash — rad (42501, fin:locked), faktura o''zgarmadi',
  zz.as('U_DIR', $q$select public.reprice_invoice('d1', 900000, '{}'::jsonb, false)::text$q$) || ' | ' || zz.inv('d1'),
  '^ERR 42501 \[fin:locked\] Hisob-faktura \(2026-12 oyi\) yopilgan davrga tegishli \(davr 31\.12\.2026 gacha yopilgan\).* \| 2026-12:1000000:0:pending$');
select zz.chk('I2 yopilgan oy fakturasini bekor qilish (cancel_invoice) — rad',
  zz.as('U_DIR', $q$select public.cancel_invoice('d2')::text$q$) || ' | ' || zz.inv('d2'), '^ERR 42501 \[fin:locked\].* \| 2026-12:1000000:0:pending$');
select zz.chk('I3 yopilgan oyning to''lanmagan fakturasini o''chirish (delete_unpaid_invoice) — rad',
  zz.as('U_DIR', $q$select public.delete_unpaid_invoice('d2')::text$q$) || ' | ' || zz.inv('d2'), '^ERR 42501 \[fin:locked\].* \| 2026-12:1000000:0:pending$');
select zz.chk('I4 yopilgan oyga yangi faktura (to''g''ridan-to''g''ri yozuv) — rad',
  zz.as('U_DIR', $q$insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values ('d9', 'T-3', 'Sinov C', '2026-12', 1000000, 0, 'pending') returning id$q$)
    || ' | ' || zz.inv('d9'), '^ERR 42501 \[fin:locked\].* \| yo''q$');
select zz.chk('I5 ochiq oyga (yanvar) yangi faktura — yoziladi',
  zz.as('U_DIR', $q$insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values ('j2', 'T-2', 'Sinov B', '2027-01', 1000000, 0, 'pending') returning id$q$),
  '^j2$');
select zz.chk('I6 ochiq oy fakturasini yopilgan oyga ko''chirish — rad; I7 yopilgan oy fakturasini ochiq oyga ko''chirish — rad',
  zz.asu('U_DIR', $q$with u as (update public.invoices set month = '2026-12' where id = 'j1' returning 1) select count(*)::text from u$q$) || ' | '
    || zz.asu('U_DIR', $q$with u as (update public.invoices set month = '2027-01' where id = 'd1' returning 1) select count(*)::text from u$q$) || ' | ' || zz.inv('j1') || ' | ' || zz.inv('d1'),
  '^ERR 42501 \[fin:locked\] Hisob-faktura \(2026-12 oyi\).* \| ERR 42501 \[fin:locked\] Hisob-faktura \(2026-12 oyi\).* \| 2027-01:1000000:0:pending \| 2026-12:1000000:0:pending$');
select zz.chk('I8 ochiq oy fakturasini qayta hisoblash — mumkin',
  coalesce(zz.js(zz.as('U_DIR', $q$select public.reprice_invoice('j1', 900000, '{}'::jsonb, false)::text$q$)) ->> 'ok', 'xato') || ' | ' || zz.inv('j1'),
  '^true \| 2027-01:900000:0:pending$');
select zz.put('I9', zz.as('U_FM', $q$select public.record_manual_payment('man_lock_1', 'T-1', 300000, 'bank', '2027-01-05', '', '', 'Sinov Ota', null, null)::text$q$));
select zz.chk('I9 eski (yopilgan oy) qarziga yanvarda to''lov — qabul qilinadi, dekabr fakturasiga avans (100 000) bilan qo''llanadi (to''lov qo''llanishi qulfga tushmaydi; avans jurnali — bugungi sana)',
  coalesce(zz.js(zz.get('I9')) ->> 'ok', zz.get('I9')) || ' | ' || zz.inv('d1') || ' | '
    || (select string_agg(trim_scale(l.delta) || '@' || to_char(l."at" at time zone 'Asia/Tashkent', 'YYYY-MM-DD'), ',' order by l."at") from public.credit_ledger l where l."studentId" = 'T-1'),
  '^true \| 2026-12:1000000:400000:partial \| 100000@2026-12-20,-100000@2027-01-05$');
select zz.chk('I10 hisoblanishga tegmaydigan belgilar (ism, chegirma izohi) — o''zgaradi',
  zz.asu('U_DIR', $q$with u as (update public.invoices set "studentName" = 'Sinov D2', "discountInfo" = 'izoh' where id = 'd3' returning 1) select count(*)::text from u$q$), '^1$');
select zz.chk('I11 oldingi yopilgan oy (noyabr) to''langan fakturasini «bekor» holatiga o''tkazish — rad',
  zz.asu('U_DIR', $q$with u as (update public.invoices set status = 'canceled' where id = 'n1' returning 1) select count(*)::text from u$q$) || ' | ' || zz.inv('n1'),
  '^ERR 42501 \[fin:locked\] Hisob-faktura \(2026-11 oyi\).* \| 2026-11:1000000:1000000:paid$');

select zz.chk('I12 yopilgan oy fakturasining faqat summasi (Direktor, to''g''ridan-to''g''ri) — rad; faqat chegirmasi — rad',
  zz.asu('U_DIR', $q$with u as (update public.invoices set amount = 950000 where id = 'd1' returning 1) select count(*)::text from u$q$) || ' | '
    || zz.asu('U_DIR', $q$with u as (update public.invoices set discount = 50000 where id = 'd1' returning 1) select count(*)::text from u$q$) || ' | ' || zz.inv('d1'),
  '^ERR 42501 \[fin:locked\] Hisob-faktura \(2026-12 oyi\).* \| ERR 42501 \[fin:locked\] Hisob-faktura \(2026-12 oyi\).* \| 2026-12:1000000:400000:partial$');

-- ---------- (C) avans (kredit) harakatlari ----------
select zz.chk('C1 foydalanuvchi orqa sana bilan yozgan avans harakati — sanasi server vaqtiga (05.01.2027) almashadi',
  zz.as('U_FM', $q$insert into public.credit_ledger (id, "studentId", "studentName", delta, "balanceAfter", reason, note, "at") values ('cl_x', 'T-2', 'Sinov B', 5000, 5000, 'manual', 'orqa sana', '2026-12-20 10:00+05') returning to_char("at" at time zone 'Asia/Tashkent', 'YYYY-MM-DD')$q$),
  '^2027-01-05$');
select zz.chk('C2 yopilgan davr avans harakatini o''zgartirish — rad; C3 o''chirish — rad',
  zz.asu('U_DIR', $q$with u as (update public.credit_ledger set delta = 1 where id = 'cl_d' returning 1) select count(*)::text from u$q$) || ' | '
    || zz.asu('U_DIR', $q$with u as (delete from public.credit_ledger where id = 'cl_d' returning 1) select count(*)::text from u$q$) || ' | '
    || (select trim_scale(delta)::text from public.credit_ledger where id = 'cl_d'),
  '^ERR 42501 \[fin:locked\] Avans \(kredit\) harakati \(20\.12\.2026 kuni\) yopilgan davrga tushadi \(davr 31\.12\.2026 gacha yopilgan\).* \| ERR 42501 \[fin:locked\].* \| 100000$');
select zz.put('C4', zz.as('U_DIR', $q$select public.add_credit('T-3', 7000, 'manual', 'sinov', 'lock:c4')::text$q$));
select zz.chk('C4 avans RPC (add_credit) yanvarda — yoziladi (jurnal sanasi — bugun)',
  coalesce(zz.js(zz.get('C4')) ->> 'ok', zz.get('C4')) || ' | '
    || coalesce((select to_char(l."at" at time zone 'Asia/Tashkent', 'YYYY-MM-DD') from public.credit_ledger l where l."studentId" = 'T-3' order by l."at" desc limit 1), 'yo''q'),
  '^true \| 2027-01-05$');
select zz.chk('C5 server (webhook) — mustasno: o''zi bergan sana saqlanadi va yopilgan davr yozuvini o''zgartira oladi',
  zz.as('SYSTEM', $q$insert into public.credit_ledger (id, "studentId", "studentName", delta, "balanceAfter", reason, note, "at") values ('cl_s', 'T-4', 'Sinov D', 1000, 1000, 'manual', 'server', '2026-12-21 10:00+05') returning to_char("at" at time zone 'Asia/Tashkent', 'YYYY-MM-DD')$q$) || ' | '
    || zz.as('SYSTEM', $q$with u as (update public.credit_ledger set note = 'server tuzatdi' where id = 'cl_s' returning 1) select count(*)::text from u$q$),
  '^2026-12-21 \| 1$');

-- ---------- (R) qaytarishlar ----------
select zz.chk('R1 yopilgan davr qaytarish yozuvining summasini o''zgartirish — rad; R2 o''chirish — rad',
  zz.asu('U_DIR', $q$with u as (update public.refunds set amount = 1 where id = 'rf_d' returning 1) select count(*)::text from u$q$) || ' | '
    || zz.asu('U_DIR', $q$with u as (delete from public.refunds where id = 'rf_d' returning 1) select count(*)::text from u$q$) || ' | '
    || (select trim_scale(amount)::text from public.refunds where id = 'rf_d'),
  '^ERR 42501 \[fin:locked\] Qaytarish yozuvi \(15\.12\.2026 kuni\) yopilgan davrga tegishli \(davr 31\.12\.2026 gacha yopilgan\).* \| ERR 42501 \[fin:locked\].* \| 50000$');
select zz.chk('R3 ism (maxfiy kodni yashirish kabi) — o''zgaradi',
  zz.asu('U_DIR', $q$with u as (update public.refunds set "studentName" = 'Sinov C [kod]' where id = 'rf_d' returning 1) select count(*)::text from u$q$), '^1$');
select zz.chk('R4 foydalanuvchi yangi qaytarish yozuvi — sana server vaqti (orqa sana yo''q), yoziladi',
  zz.asu('U_DIR', $q$insert into public.refunds (id, target, "targetId", "studentId", "studentName", amount, reason, month, "createdAt") values ('rf_x', 'invoice', 'j2', 'T-2', 'Sinov B', 1000, 'sinov', '2027-01', '2026-12-10 10:00+05') returning to_char("createdAt" at time zone 'Asia/Tashkent', 'YYYY-MM-DD')$q$),
  '^2027-01-05$');

-- ---------- (P) oylik vedomost ----------
select zz.chk('P1 yopilgan oy (dekabr) vedomostini tasdiqlash — rad; P2 qaytarish — rad',
  zz.as('U_DIR', $q$select public.payroll_decide('2026-12', true, null)::text$q$) || ' | ' || zz.as('U_DIR', $q$select public.payroll_decide('2026-12', false, 'qaytarildi')::text$q$)
    || ' | ' || (select status from public.payroll_runs where id = '2026-12'),
  '^ERR 42501 \[fin:locked\] Oylik vedomost \(2026-12 oyi\) yopilgan davrga tegishli \(davr 31\.12\.2026 gacha yopilgan\).* \| ERR 42501 \[fin:locked\].* \| submitted$');
select zz.chk('P3 yopilgan oy (noyabr) tasdiqlangan vedomostini qayta ochish — rad',
  zz.as('U_DIR', $q$select public.payroll_reopen('2026-11', 'xato topildi')::text$q$) || ' | ' || (select status from public.payroll_runs where id = '2026-11'),
  '^ERR 42501 \[fin:locked\] Oylik vedomost \(2026-11 oyi\).* \| approved$');
select zz.chk('P4 yopilgan oy vedomosti qatorini Direktor tasdig''i — rad',
  zz.as('U_DIR', $q$select public.payroll_approve_line('2026-12__teacher__IQT-T1', null)::text$q$), '^ERR 42501 \[fin:locked\]');
select zz.chk('P5 yopilgan oy vedomostini qayta yuborish (payroll_submit) — rad',
  zz.as('U_FM', $q$select public.payroll_submit('2026-12', '[{"personType":"teacher","personId":"IQT-T1","gross":3000000}]'::jsonb, null)::text$q$), '^ERR 42501 \[fin:locked\]');
select zz.put('P6', zz.as('U_FM', $q$select public.payroll_submit('2027-01', '[{"personType":"teacher","personId":"IQT-T1","gross":3000000}]'::jsonb, null)::text$q$));
select zz.chk('P6 joriy oy (yanvar) vedomostini yuborish — mumkin',
  coalesce(zz.js(zz.get('P6')) ->> 'ok', zz.get('P6'))
    || ' | ' || coalesce((select status || ':' || (select count(*) from public.payroll_lines l where l."runId" = r.id) from public.payroll_runs r where r.id = '2027-01'), 'yo''q'),
  '^true \| submitted:1$');

-- ---------- (M) oy oxiri ro'yxati ----------
select zz.chk('M1 dekabr: vedomost tasdiqlanmagan (tasdiqlash rejimi noyabrdan) — ogohlantirish; M2 oktyabr (rejimdan oldin) — ma''lumot',
  (select (zz.item(zz.mc('2026-12'), 'payroll') ->> 'level') || ':' || (zz.item(zz.mc('2026-12'), 'payroll') ->> 'run') || ':' || (zz.item(zz.mc('2026-12'), 'payroll') ->> 'approvalFrom'))
    || ' | ' || (select (zz.item(zz.mc('2026-10'), 'payroll') ->> 'level') || ':' || (zz.item(zz.mc('2026-10'), 'payroll') ->> 'run')),
  '^warn:submitted:2026-11 \| info:none$');

-- ---------- (S) server mustasno ----------
select zz.chk('S1 server yopilgan oy fakturasini o''zgartira oladi (webhook, zanjir)',
  zz.as('SYSTEM', $q$with u as (update public.invoices set amount = 990000 where id = 'd3' returning 1) select count(*)::text from u$q$) || ' | ' || zz.inv('d3'),
  '^1 \| 2026-12:990000:0:pending$');

-- ---------- (B) chegaralar ----------
select zz.chk('B0 qulf 30.12.2026 ga (orqaga — sabab bilan)',
  zz.as('U_DIR', $q$select (public.fin_period_lock('2026-12-30', 'Vedomost uchun bir kun ochildi (sinov)') ->> 'lockedThrough')$q$), '^2026-12-30$');
select zz.chk('B1 dekabr vedomosti (hisoblanish kuni — 31.12) endi tasdiqlanadi; B2 dekabr fakturasi (1.12) hali yopiq',
  coalesce(zz.js(zz.as('U_DIR', $q$select public.payroll_decide('2026-12', true, null)::text$q$)) ->> 'status', 'xato') || ' | '
    || zz.as('U_DIR', $q$select public.reprice_invoice('d1', 900000, '{}'::jsonb, false)::text$q$),
  '^approved \| ERR 42501 \[fin:locked\] Hisob-faktura \(2026-12 oyi\) yopilgan davrga tegishli \(davr 30\.12\.2026 gacha yopilgan\)');
select zz.chk('B3 qulf 30.11.2026 ga: dekabr fakturasi qayta hisoblanadi, dekabr vedomosti qayta ochiladi, noyabr vedomosti — hali yopiq',
  zz.as('U_DIR', $q$select (public.fin_period_lock('2026-11-30', 'Dekabr qayta ochildi (sinov)') ->> 'lockedThrough')$q$) || ' | '
    || coalesce(zz.js(zz.as('U_DIR', $q$select public.reprice_invoice('d1', 900000, '{}'::jsonb, false)::text$q$)) ->> 'ok', 'xato') || ':' || zz.inv('d1') || ' | '
    || coalesce(zz.js(zz.as('U_DIR', $q$select public.payroll_reopen('2026-12', 'qayta hisob')::text$q$)) ->> 'status', 'xato') || ' | '
    || zz.as('U_DIR', $q$select public.payroll_reopen('2026-11', 'qayta hisob')::text$q$),
  '^2026-11-30 \| true:2026-12:900000:400000:partial \| returned \| ERR 42501 \[fin:locked\] Oylik vedomost \(2026-11 oyi\)');
select zz.chk('B4 noyabr qulfi ostida: noyabr qaytarish yozuvi (sanasi dekabr) — o''zgaradi; dekabr avans harakati — o''zgaradi',
  zz.asu('U_DIR', $q$with u as (update public.refunds set amount = 40000 where id = 'rf_d' returning 1) select count(*)::text from u$q$) || ' | '
    || zz.asu('U_DIR', $q$with u as (update public.credit_ledger set note = 'tuzatildi' where id = 'cl_d' returning 1) select count(*)::text from u$q$),
  '^1 \| 1$');

-- ---------- (N) qulfsiz ----------
select zz.chk('N1 qulf olib tashlandi: noyabr vedomosti qayta ochiladi, noyabr fakturasi bekor holatiga o''tadi',
  coalesce(zz.js(zz.as('U_DIR', $q$select public.fin_period_lock(null, 'Qulf olib tashlandi (sinov)')::text$q$)) ->> 'ok', 'xato') || ' | '
    || coalesce(zz.js(zz.as('U_DIR', $q$select public.payroll_reopen('2026-11', 'qayta hisob')::text$q$)) ->> 'status', 'xato') || ' | '
    || zz.asu('U_DIR', $q$with u as (update public.invoices set status = 'canceled' where id = 'n1' returning 1) select count(*)::text from u$q$),
  '^true \| returned \| 1$');

-- ---------- Natija ----------
select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got: ' || coalesce(got, '<null>') || ' | want: ' || pat end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || case when bool_and(ok) then ' — HAMMASI O''TDI' else ' — XATO BOR' end from zz.res;
rollback;
