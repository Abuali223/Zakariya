-- =====================================================================
-- test-fin-period.sql — moliya ish rejasi 1a-bosqichi, F1.16 (fin-period.sql) sinovi:
--   (S) davr surati: faqat Direktor; mazmuni (qarzdorlik, kelgusi oy uchun oldindan to'lov, avans, biriktirilmagan tushum,
--       to'lanmagan ish haqi), jamlar, xesh, versiyalar, o'zgarmaslik;
--   (L) davr qulfi: yopilgan davr sanasi bilan to'lov, xarajat, maosh to'lovi, avans yozilmaydi va o'zgartirilmaydi (42501);
--       server (webhook) mustasno; qulfni faqat Direktor suradi — orqaga faqat sabab bilan; bugungi kun yopilmaydi;
--   (G) rollar.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-fin-period.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.fin_snapshots) then
    raise exception 'test-fin-period.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' when p_uid = 'SYSTEM' then '{"role":"service_role"}'
                                                else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  -- SYSTEM (webhook serveri): faqat JWT da'vosi qo'yiladi — lokal sinov bazasida service_role RLS ni chetlab o'tmaydi (jonli bazada o'tadi)
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
-- qo'lda to'lov (naqdsiz): (uid, payId, o'quvchi, summa, sana)
create or replace function zz.bank(p_uid text, p_id text, p_sid text, p_amount numeric, p_date text) returns text language sql as $$
  select zz.as(p_uid, format('select public.record_manual_payment(%L, %L, %s, %L, %L, %L, %L, %L, null, null)::text', p_id, p_sid, p_amount, 'bank', p_date, '', '', 'Sinov Ota')) $$;
create or replace function zz.tot(p_j text, p_k text) returns text language sql as $$ select trim_scale((p_j::jsonb -> 'totals' ->> p_k)::numeric)::text $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'), ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]'), ('s2','T-2','Sinov B',5,'A','uz','',2,'[]'), ('s3','T-3','Sinov C',5,'A','uz','',3,'[]');
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','[]');
insert into public.staff (id, "staffId", name, position) values ('st1','IQX-T1','Sinov Xodim','Farrosh');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('ia','T-1','Sinov A','2026-12',1000000,400000,'partial'),    -- qarz 600 000 (4010)
  ('ib','T-1','Sinov A','2027-01',1000000,0,'pending'),         -- kelgusi oy fakturasi (hali muddati kelmagan)
  ('ic','T-1','Sinov A','2027-02',1000000,1000000,'paid'),      -- kelgusi oy uchun oldindan to'langan (6310)
  ('id','T-3','Sinov C','2026-12',1000000,1000000,'paid'),      -- to'liq to'langan — suratga kirmaydi
  ('ie','T-3','Sinov C','2026-11',1000000,0,'canceled');        -- bekor qilingan — kirmaydi
insert into public.student_credit (id, "studentId", credit) values ('T-2','T-2',250000);
insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw, "createdAt") values
  ('pu1', '', 'bank', 300000, 'unmatched', 'Noma''lum', false, '{}', '2026-12-30 10:00+05');
insert into public.config (id, "payrollApprovalFrom") values ('finance', '2026-12')
  on conflict (id) do update set "payrollApprovalFrom" = excluded."payrollApprovalFrom";
insert into public.payroll_runs (id, status, "approvedBy", "approvedAt") values ('2026-12', 'approved', 'U_FM', now());
insert into public.payroll_lines (id, "runId", "personType", "personId", "refId", name, gross, payable) values
  ('2026-12__teacher__IQT-T1', '2026-12', 'teacher', 'IQT-T1', 'tch1', 'Sinov O''qituvchi', 3000000, 3000000),
  ('2026-12__staff__IQX-T1', '2026-12', 'staff', 'IQX-T1', 'st1', 'Sinov Xodim', 2000000, 2000000);
insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date) values
  ('sp_d1', 'IQT-T1', 'teachers:tch1', 'Sinov', '2026-12', 1000000, '2026-12-28'), ('sp_d2', 'IQX-T1', 'staff:st1', 'Sinov', '2026-12', 2000000, '2026-12-28');
insert into public.expenses (id, date, month, category, amount, note) values ('ex_dec', '2026-12-20', '2026-12', 'Boshqa', 50000, 'dekabr xarajati');
insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date) values ('adv_dec', 'IQX-T1', 'staff:st1', 'Sinov', 100000, '2026-12', '2026-12-15');
set local session_replication_role = origin;
select zz.clock('2027-01-02 10:00+05');

-- ---------- (S) davr surati ----------
select zz.chk('S0 suratni faqat Direktor oladi (Moliya menejeri, kassir — yo''q)',
  zz.as('U_FM', $q$select public.fin_snapshot_take('{"asOf":"2026-12-31"}')::text$q$) || ' | ' || zz.as('U_KAS', $q$select public.fin_snapshot_take('{"asOf":"2026-12-31"}')::text$q$), '^ERR 42501.* \| ERR 42501');
select zz.chk('S0b kelajakdagi sana — rad; bugungi kunni qulf bilan — rad',
  zz.as('U_DIR', $q$select public.fin_snapshot_take('{"asOf":"2027-01-03"}')::text$q$) || ' | ' || zz.as('U_DIR', $q$select public.fin_snapshot_take('{"asOf":"2027-01-02","lock":true}')::text$q$),
  '^ERR 22023 \[fin:bad_input\].* \| ERR 22023 \[fin:lock_day\]');
select zz.put('S1', zz.as('U_DIR', $q$select public.fin_snapshot_take('{"asOf":"2026-12-31","note":"Yil yakuni (sinov)","lock":true}')::text$q$));
select zz.chk('S1 yil yakuni surati: turi, versiya, «keyin olingan» belgisi, davr shu sanagacha yopildi',
  (zz.get('S1')::jsonb ->> 'kind') || ':' || (zz.get('S1')::jsonb ->> 'version') || ':' || (zz.get('S1')::jsonb ->> 'late') || ':' || (zz.get('S1')::jsonb ->> 'lockedThrough') || ':' || (zz.get('S1')::jsonb ->> 'id'),
  '^year_end:1:true:2026-12-31:fs_20261231_1$');
select zz.chk('S1a jamlar: qarzdorlik 600 000 (4010), kelgusi oy fakturasi 1 000 000, oldindan to''langan 1 000 000 va avans 250 000 (6310), biriktirilmagan 300 000 (1 ta), to''lanmagan ish haqi 2 000 000',
  zz.tot(zz.get('S1'), 'receivable') || ':' || zz.tot(zz.get('S1'), 'receivableFuture') || ':' || zz.tot(zz.get('S1'), 'prepaid') || ':' || zz.tot(zz.get('S1'), 'credit') || ':' || zz.tot(zz.get('S1'), 'unmatched')
    || ':' || (zz.get('S1')::jsonb -> 'totals' ->> 'unmatchedCount') || ':' || zz.tot(zz.get('S1'), 'salaryPayable') || ':' || (zz.get('S1')::jsonb -> 'totals' ->> 'students') || ':' || zz.tot(zz.get('S1'), 'cash'),
  '^600000:1000000:1000000:250000:300000:1:2000000:2:0$');
select zz.put('S2', zz.as('U_FM', $q$select public.fin_snapshot_get('fs_20261231_1')::text$q$));
select zz.chk('S2 to''liq surat (2-ro''yxat ko''radi): xesh mos; o''quvchilar — T-1 (3 faktura) va T-2 (avans); to''liq to''langan va bekor qilingan fakturali T-3 yo''q',
  (zz.get('S2')::jsonb ->> 'hashOk') || ':' || (select string_agg((s ->> 'studentId') || '/' || (s ->> 'name') || '/' || jsonb_array_length(s -> 'invoices') || '/' || trim_scale((s ->> 'credit')::numeric), ',' order by s ->> 'studentId')
                                                  from jsonb_array_elements(zz.get('S2')::jsonb -> 'data' -> 'students') s),
  '^true:T-1/Sinov A/3/0,T-2/Sinov B/0/250000$');
select zz.chk('S2b fakturalar tafsiloti; ish haqi qatori — faqat qoldig''i bor xodim; biriktirilmagan tushum',
  (select string_agg((i ->> 'id') || '=' || (i ->> 'month') || ':' || trim_scale((i ->> 'amount')::numeric) || '-' || trim_scale((i ->> 'paid')::numeric) || ':' || (i ->> 'status'), ',' order by i ->> 'id')
     from jsonb_array_elements(zz.get('S2')::jsonb -> 'data' -> 'students' -> 0 -> 'invoices') i)
  || ' / ' || (select string_agg((x ->> 'personId') || '=' || trim_scale((x ->> 'due')::numeric), ',') from jsonb_array_elements(zz.get('S2')::jsonb -> 'data' -> 'salary') x)
  || ' / ' || (select string_agg((u ->> 'id') || '=' || trim_scale((u ->> 'amount')::numeric) || '@' || (u ->> 'day'), ',') from jsonb_array_elements(zz.get('S2')::jsonb -> 'data' -> 'unmatched') u),
  '^ia=2026-12:1000000-400000:partial,ib=2027-01:1000000-0:pending,ic=2027-02:1000000-1000000:paid / IQT-T1=2000000 / pu1=300000@2026-12-30$');
select zz.chk('S3 xesh — saqlangan mazmunning SHA-256 izi (64 belgi), javobdagi bilan bir xil',
  (select (s.hash = encode(sha256(convert_to(s.payload::text, 'UTF8')), 'hex'))::text || ':' || length(s.hash) || ':' || (s.hash = zz.get('S1')::jsonb ->> 'hash')::text from public.fin_snapshots s where s.id = 'fs_20261231_1'),
  '^true:64:true$');
create or replace function zz.try(p_q text) returns text language plpgsql as $$
declare v_hint text;
begin execute p_q; return 'ok';
exception when others then get stacked diagnostics v_hint = pg_exception_hint; return 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || ']'; end $$;
select zz.chk('S4 surat o''zgarmaydi va o''chirilmaydi — baza egasi uchun ham; mijoz uchun — umuman ruxsat yo''q',
  zz.try($q$update public.fin_snapshots set note = 'x' where id = 'fs_20261231_1'$q$) || ' | ' || zz.try($q$delete from public.fin_snapshots where id = 'fs_20261231_1'$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.fin_snapshots set note = 'x' returning id) select count(*)::text from x$q$),
  '^ERR 42501 \[kassa:immutable\] \| ERR 42501 \[kassa:immutable\] \| ERR 42501');
select zz.put('S5', zz.as('U_DIR', $q$select public.fin_snapshot_take('{"asOf":"2026-12-31","note":"Takroriy"}')::text$q$));
select zz.chk('S5 shu sana uchun ikkinchi surat — yangi versiya, oldingisi saqlanadi; ro''yxat — eng yangisi birinchi, mazmunsiz',
  (zz.get('S5')::jsonb ->> 'version') || ':' || (select count(*) from public.fin_snapshots) || ':' ||
  zz.as('U_FM', $q$select (l ->> 'lockedThrough') || ':' || (select string_agg((i ->> 'id') || '/' || (i ->> 'byName') || '/' || ((i ? 'data')::text), ',') from jsonb_array_elements(l -> 'items') i) from public.fin_snapshots_list() l$q$),
  '^2:2:2026-12-31:fs_20261231_2/Sinov Direktor/false,fs_20261231_1/Sinov Direktor/false$');
select zz.chk('S6 bugungi kun uchun surat (qulfsiz): «qo''lda», kechikmagan',
  (select (j ->> 'kind') || ':' || (j ->> 'late') || ':' || (j ->> 'lockedThrough') from (select zz.as('U_DIR', $q$select public.fin_snapshot_take('{"asOf":"2027-01-02"}')::text$q$)::jsonb as j) q), '^manual:false:2026-12-31$');

-- ---------- (L) davr qulfi ----------
select zz.chk('L1 yopilgan davr sanasi bilan qo''lda to''lov — rad (42501), iz qolmaydi',
  zz.bank('U_KAS', 'man_p_0001', 'T-1', 100000, '2026-12-31') || ' / ' || (select count(*) from public.payments where id = 'man_p_0001'), '^ERR 42501 \[fin:locked\] To‘lov: 31\.12\.2026 — yopilgan davr \(31\.12\.2026 gacha yopilgan\).* / 0$');
select zz.chk('L1b qulfdan keyingi sana bilan — yoziladi', (zz.bank('U_KAS', 'man_p_0002', 'T-1', 100000, '2027-01-01')::jsonb ->> 'status'), '^applied$');
select zz.chk('L1c server (webhook) yopilgan davrga ham yoza oladi — tizim mustasno',
  zz.as('SYSTEM', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values ('wh_old_1', 'T-1', 'click', 5000, 'pending', true, '{}', '2026-12-30 09:00+05') returning id) select id from x$q$), '^wh_old_1$');
select zz.chk('L1d eski to''lov holatini o''zgartirish (biriktirish, qaytarish) cheklanmaydi',
  zz.as('SYSTEM', $q$with x as (update public.payments set status = 'refunded' where id = 'pu1' returning status) select status from x$q$), '^refunded$');
select zz.chk('L2 xarajat: yopilgan davr sanasi bilan yangi yozuv — rad; o''sha davr yozuvini o''zgartirish va o''chirish — rad',
  zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_l1', '2026-12-30', '2026-12', 'Boshqa', 1000, 'kech', 'bank') returning id) select id from x$q$) || ' | ' ||
  zz.as('U_FM', $q$with x as (update public.expenses set amount = 1 where id = 'ex_dec' returning id) select count(*)::text from x$q$) || ' | ' ||
  zz.as('U_DIR', $q$with x as (delete from public.expenses where id = 'ex_dec' returning id) select count(*)::text from x$q$),
  '^ERR 42501 \[fin:locked\] Xarajat: 30\.12\.2026.* \| ERR 42501 \[fin:locked\].* \| ERR 42501 \[fin:locked\]');
select zz.chk('L2b joriy davr xarajati — avvalgidek; uni yopilgan davrga «ko''chirib» ham bo''lmaydi',
  zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_l2', '2027-01-02', '2027-01', 'Boshqa', 1000, 'yanvar', 'bank') returning id) select id from x$q$) || ' | ' ||
  zz.as('U_FM', $q$with x as (update public.expenses set date = '2026-12-31' where id = 'ex_l2' returning id) select count(*)::text from x$q$), '^ex_l2 \| ERR 42501 \[fin:locked\]');
select zz.chk('L3 maosh to''lovi va avans: yopilgan davr sanasi bilan — rad; joriy sana bilan — yoziladi',
  zz.as('U_FM', $q$with x as (insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date) values ('sp_l1','IQT-T1','teachers:tch1','Sinov','2026-12',1000,'2026-12-31') returning id) select id from x$q$) || ' | ' ||
  zz.as('U_FM', $q$with x as (insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date) values ('sp_l2','IQT-T1','teachers:tch1','Sinov','2026-12',1000,'2027-01-02') returning id) select id from x$q$) || ' | ' ||
  zz.as('U_FM', $q$with x as (insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date) values ('adv_l1','IQX-T1','staff:st1','Sinov',1000,'2027-01','2026-12-31') returning id) select id from x$q$),
  '^ERR 42501 \[fin:locked\] Maosh to‘lovi.* \| sp_l2 \| ERR 42501 \[fin:locked\] Xodim avansi');
select zz.chk('L4 qulfni faqat Direktor suradi; bugungi kun yopilmaydi',
  zz.as('U_FM', $q$select public.fin_period_lock('2027-01-01')::text$q$) || ' | ' || zz.as('U_DIR', $q$select public.fin_period_lock('2027-01-02')::text$q$), '^ERR 42501.* \| ERR 22023 \[fin:lock_day\]');
select zz.chk('L4b oldinga surish — erkin (01.01.2027 gacha)', zz.as('U_DIR', $q$select public.fin_period_lock('2027-01-01')::text$q$), '"lockedThrough": "2027-01-01".*"previous": "2026-12-31"|"previous": "2026-12-31".*"lockedThrough": "2027-01-01"');
select zz.chk('L4c endi 01.01.2027 sanasi bilan ham to''lov yozilmaydi', zz.bank('U_KAS', 'man_p_0003', 'T-1', 100000, '2027-01-01'), '^ERR 42501 \[fin:locked\]');
select zz.put('L5', zz.as('U_DIR', $q$select public.fin_period_lock('2026-12-31')::text$q$) || ' | ' || zz.as('U_DIR', $q$select public.fin_period_lock('2026-12-31', 'Bank ko''chirmasi kech keldi')::text$q$));
select zz.chk('L5 orqaga surish (davrni qayta ochish) — sababsiz rad; sabab bilan — o''tadi va tarixda qoladi',
  zz.get('L5') || ' | ' || (select (o."lockedThrough")::text || ':' || (o.extra ->> 'lockNote') || ':' || (o.extra ->> 'lockPrev') from public.fin_org o where o.id = 'main'),
  '^ERR 22023 \[fin:lock_reason\].* \| \{.*"ok": true.*\} \| 2026-12-31:Bank ko''chirmasi kech keldi:2027-01-01$');
select zz.put('L5b', left(zz.as('U_DIR', $q$select public.fin_period_lock(null, 'Sinov: qulf olib tashlandi')::text$q$), 0) || (zz.bank('U_KAS', 'man_p_0004', 'T-1', 100000, '2026-12-31')::jsonb ->> 'status'));
select zz.chk('L5b qulfni olib tashlash — sabab bilan; keyin dekabr sanasi bilan to''lov yana yoziladi',
  zz.get('L5b') || ':' || coalesce((select o."lockedThrough"::text from public.fin_org o where o.id = 'main'), 'yo''q'), '^applied:yo''q$');
select zz.chk('L6 qulf o''zgarishlari «O''zgarishlar tarixi»ga yozilgan',
  (select (count(*) >= 3)::text from public.change_log c where c.tbl = 'fin_org' and c.changes::text like '%lockedThrough%'), '^true$');
select zz.chk('L7 kassa holatida davr qulfi ko''rinadi (shakllarda eng erta sana shundan)',
  left(zz.as('U_DIR', $q$select public.fin_period_lock('2026-12-31')::text$q$), 0) || zz.as('U_KAS', $q$select (public.kassa_state('main') ->> 'lockedThrough')$q$), '^2026-12-31$');

-- ---------- (K) davr qulfi va kassa kunlari ----------
select zz.put('K1', zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":500000,"startDay":"2026-12-31"}')::text$q$));
select zz.chk('K1 birinchi kassa kuni yopilgan davrga qo''yilmaydi', zz.get('K1'), '^ERR 42501 \[fin:locked\] Birinchi kassa kuni');
select zz.put('K2', left(zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":500000,"startDay":"2027-01-02"}')::text$q$), 0)
  || zz.as('U_KAS', $q$select public.kassa_receipt('{"op":"in_other","amount":10000,"partyType":"other","partyName":"Sinov Shaxs","articleId":"IN-06","basis":"Tilxat, 02.01.2027","note":"Sinov","clientRef":"p-k2-0001"}'::jsonb)::text$q$));
select zz.chk('K2 kassa ishga tushdi: 02.01.2027 kuni ochiq', (select status from public.cash_days where desk = 'main' and day = '2027-01-02'), '^open$');
select zz.clock('2027-01-03 10:00+05');   -- ertasi kun: kechagi kassa kuni hali sanalmagan
select zz.put('K3n', (select count(*)::text from public.fin_snapshots));
select zz.chk('K3 ochiq kassa kuni bor — davr yopilmaydi (qulf ham, qulfli surat ham); surat yozilmaydi',
  zz.as('U_DIR', $q$select public.fin_period_lock('2027-01-02')::text$q$) || ' | ' || zz.as('U_DIR', $q$select public.fin_snapshot_take('{"asOf":"2027-01-02","lock":true}')::text$q$)
  || ' | ' || ((select count(*)::text from public.fin_snapshots) = zz.get('K3n'))::text, '^ERR P0001 \[fin:open_day\].*02\.01\.2027.* \| ERR P0001 \[fin:open_day\].* \| true$');
select zz.put('K4', zz.as('U_KAS', $q$select public.kassa_day_close('{"desk":"main","day":"2027-01-02","counted":510000}')::text$q$));
select zz.chk('K4 kun sanab yopilgach davr 02.01.2027 gacha yopiladi',
  (zz.get('K4')::jsonb -> 'day' ->> 'status') || ' | ' || zz.as('U_DIR', $q$select (public.fin_period_lock('2027-01-02') ->> 'lockedThrough')$q$), '^closed \| 2027-01-02$');
select zz.put('K5', zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-01-02', 'Sanash xatosi')::text$q$));
select zz.put('K5b', left(zz.as('U_DIR', $q$select public.fin_period_lock('2027-01-01', 'Kassa kunini tuzatish')::text$q$), 0)
  || zz.as('U_DIR', $q$select (public.kassa_day_reopen('main', '2027-01-02', 'Sanash xatosi') -> 'day' ->> 'status')$q$));
select zz.chk('K5 yopilgan davrdagi kassa kuni qayta ochilmaydi; davr sabab bilan qayta ochilgach — ochiladi',
  zz.get('K5') || ' | ' || zz.get('K5b'), '^ERR 42501 \[fin:locked\] Kassa kuni.* \| open$');

-- ---------- (G) rollar ----------
select zz.chk('G1 kassir va o''qituvchi suratlarni ko''ra olmaydi; anon — hech narsa',
  zz.as('U_KAS', $q$select public.fin_snapshots_list()::text$q$) || ' | ' || zz.as('U_TCH', $q$select public.fin_snapshot_get('fs_20261231_1')::text$q$) || ' | ' || zz.as(null, $q$select public.fin_snapshots_list()::text$q$)
  || ' | ' || zz.as('U_KAS', $q$select count(*)::text from public.fin_snapshots$q$) || ' | ' || zz.as(null, $q$select count(*)::text from public.fin_snapshots$q$),
  '^ERR 42501.* \| ERR 42501.* \| ERR 42501.* \| 0 \| ERR 42501');
select zz.chk('G2 ichki funksiyalar mijozga yopiq',
  zz.as('U_DIR', $q$select app.fin_snapshot_data('2026-12-31')::text$q$) || ' | ' || zz.as('U_DIR', $q$select app.fin_lock_check('2026-12-31', 'x')::text$q$), '^ERR 42501.* \| ERR 42501');
select zz.chk('G3 2-ro''yxat jadvaldan o''qiy oladi (RLS), yoza olmaydi',
  zz.as('U_FM', $q$select count(*)::text from public.fin_snapshots$q$) || ' | ' || zz.as('U_FM', $q$with x as (insert into public.fin_snapshots (id, kind, "asOf", payload, hash) values ('x','manual',now(),'{}','x') returning id) select id from x$q$),
  '^3 \| ERR 42501');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 600), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
