-- =====================================================================
-- test-kassa-links.sql — moliya ish rejasi 1a-bosqichi, F1.5 / F1.6 / F1.13 (kassa-links.sql) sinovi:
--   (S) naqd maosh — kassa_salary_pay: maosh to'lovi + KO-2 bitta tranzaksiyada; vedomost chegarasi; karta — KO siz; rollar;
--   (A) ish haqi avansi — so'rov → tasdiq → pul berilganda staff_advances; oy vedomosti qulfi; bekor qilish;
--   (R) qaytarish — Direktor so'rovi (balans o'zgarmaydi) → kassir pul berganda refund_invoice shu tranzaksiyada; holat
--       o'zgargan bo'lsa rad; biriktirilmagan to'lov; kechikkan qaytarish ogohlantirishi;
--   (E) xarajat — KO-2 qatorlari «Buxgalteriya»ga ko'chadi, bekor qilinsa olib tashlanadi;
--   (O) o'zaro hisob — xodimning ish haqidan farzandining o'quv to'lovi: maosh to'lovi + o'quv to'lovi + naqdsiz dalolatnoma bitta
--       tranzaksiyada; faqat Direktor; vedomost chegarasi; kassa qoldig'i o'zgarmaydi; shu kunda bekor qilish;
--   (G) himoya — kassa ishga tushgach naqd yozuvni to'g'ridan-to'g'ri kiritib bo'lmaydi; bog'langan qator o'zgarmaydi.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-links.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) then
    raise exception 'test-kassa-links.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
-- Sinov natijasini JSON sifatida o'qish: xato matni (ERR …) yoki JSON bo'lmagan javobda — NULL (mutatsiyada tekshiruv FAIL bo'ladi,
--   to'plam «invalid json» ERROR bilan to'xtamaydi)
create or replace function zz.js(p text) returns jsonb language plpgsql as $$
begin return p::jsonb; exception when others then return null; end $$;
-- JSON maydoni (yo'q bo'lsa — standart qiymat), faqat javob JSON bo'lsa; JSON bo'lmagan javob (ERR …) o'zicha qaytadi — mutatsiyada
--   standart qiymatga aylanib PASS bermaydi, FAIL bo'ladi (g10 tekshiruvchisi)
create or replace function zz.jd(p text, p_key text, p_dflt text) returns text language sql as $$
  select case when zz.js(p) is null then '<json emas> ' || left(coalesce(p, '<null>'), 200) else coalesce(zz.js(p) ->> p_key, p_dflt) end $$;
create or replace function zz.jdp(p text, p_path text[], p_dflt text) returns text language sql as $$
  select case when zz.js(p) is null then '<json emas> ' || left(coalesce(p, '<null>'), 200) else coalesce(zz.js(p) #>> p_path, p_dflt) end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
create table if not exists zz.v (k text primary key, v text);
truncate zz.res; truncate zz.v;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
create or replace function zz.put(p_k text, p_v text) returns text language plpgsql as $$
begin insert into zz.v (k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; return p_v; end $$;
create or replace function zz.get(p_k text) returns text language sql as $$ select v from zz.v where k = p_k $$;
create or replace function zz.id(p_k text) returns text language sql as $$ select zz.js(v) ->> 'id' from zz.v where k = p_k $$;
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
create or replace function zz.bal() returns text language sql as $$
  select trim_scale(app.kassa_day_balance((select id from public.cash_days where desk = 'main' and status = 'open')))::text $$;
create or replace function zz.lines(p_doc text) returns text language sql as $$
  select string_agg(l.debit || '>' || l.credit || '=' || trim_scale(l.amount) || coalesce('@' || l."articleId", ''), ', ' order by l."lineNo")
    from public.cash_doc_lines l where l."docId" = p_doc $$;
-- maosh to'lovi JSON'i
create or replace function zz.sal(p_id text, p_method text, p_tid text, p_ref text, p_month text, p_paid numeric) returns text language sql as $$
  select jsonb_build_object('id', p_id, 'method', p_method, 'teacherId', p_tid, 'payeeRef', p_ref, 'teacherName', 'Sinov', 'month', p_month,
                            'paid', p_paid, 'gross', 3000000, 'advance', 0, 'deduction', 0, 'subBonus', 0, 'net', 3000000, 'carryIn', 0, 'carryOut', 0)::text $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles") values
  ('U_DIR','d@x','director','active','[]'), ('U_FM','f@x','finance_mgr','active','[]'), ('U_KAS','k@x','kassir','active','[]'),
  ('U_HR','h@x','hr','active','[]'), ('U_TCH','t@x','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]'), ('s2','T-2','Sinov B',5,'A','uz','',2,'[]'), ('s3','T-3','Sinov C',5,'A','uz','',3,'[]');
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','[]');
insert into public.staff (id, "staffId", name, position) values ('st1','IQX-T1','Sinov Xodim','Farrosh');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('ia','T-1','Sinov A','2026-12',1000000,1000000,'paid'), ('ib','T-1','Sinov A','2027-02',1000000,400000,'partial'),
  ('oa','T-2','Sinov B','2027-01',1000000,0,'pending'), ('ob','T-2','Sinov B','2027-03',1000000,0,'pending');
insert into public.student_credit (id, "studentId", credit) values ('T-1','T-1',150000);
insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw) values
  ('pu1', '', 'bank', 250000, 'unmatched', 'Noma''lum To''lovchi', false, '{}');
insert into public.config (id, "payrollApprovalFrom") values ('finance', '2026-12')
  on conflict (id) do update set "payrollApprovalFrom" = excluded."payrollApprovalFrom";
insert into public.payroll_runs (id, status, "approvedBy", "approvedAt") values ('2026-12', 'approved', 'U_HR', now());
insert into public.payroll_lines (id, "runId", "personType", "personId", "refId", name, gross, payable) values
  ('2026-12__teacher__IQT-T1', '2026-12', 'teacher', 'IQT-T1', 'tch1', 'Sinov O''qituvchi', 3000000, 3000000),
  ('2026-12__staff__IQX-T1', '2026-12', 'staff', 'IQX-T1', 'st1', 'Sinov Xodim', 2000000, 2000000);
set local session_replication_role = origin;
select zz.clock('2027-01-03 16:00+05');   -- ishga tushirishdan bir kun oldin

-- ---------- Kassa ishga tushguncha: avvalgidek ----------
select zz.chk('K0 kassa ishga tushmagan: maosh avvalgidek to''g''ridan-to''g''ri yoziladi',
  zz.as('U_KAS', $q$with x as (insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date) values ('sp_old_1','IQT-T1','teachers:tch1','Sinov','2026-12',100000,'2027-01-03') returning id) select id from x$q$), '^sp_old_1$');
select zz.chk('K0b kassa ishga tushmagan: naqd maosh funksiyasi rad', zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_k0_0001', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1000)), '^ERR P0001 \[kassa:not_live\]');
select zz.chk('K0c kassa ishga tushmagan: naqd qaytarish so''rovi rad',
  zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ia","amount":1000,"reason":"sinov","payee":"Sinov Ota Onaevich","clientRef":"rf_k0_000001"}'), '^ERR P0001 \[kassa:not_live\]');
select zz.chk('K0d ishga tushadigan kun kassa orderisiz naqd maosh berilgan kunga qo''yilmaydi; sozlama o''zgarmaydi',
  zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-01-03"}')::text$q$) || ' | ' || coalesce((select "kassaGoLive"::text from public.fin_org where id = 'main'), 'bo''sh'),
  '^ERR P0001 \[kassa:live_gap\].*maosh / avans: 1.* \| bo''sh$');
select zz.clock('2027-01-04 10:00+05');
select zz.chk('K1 ishga tushirish va boshlang''ich qoldiq 5 000 000',
  left(zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-01-04","t1":1000000,"l1":200000,"orgCashMax":1000000000}')::text$q$), 0)
  || zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":5000000,"startDay":"2027-01-04"}')::text$q$), '"ok": true');

-- ---------- (S) naqd maosh ----------
select zz.put('S1', zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_n1', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1000000)));
select zz.chk('S1 naqd maosh: javobda chiqim orderi № 1, kun 04.01.2027', zz.get('S1'), '"kassa": \{.*"no": 1[,}]');
select zz.chk('S1a order: KO-2, Dt 6710 Kt 5010, xodim, manba — maosh to''lovi',
  (select c.form || ':' || c.op || ':' || c.status || ':' || c."partyType" || ':' || c."partyId" || ':' || c."partyName" || ':' || c."sourceTable" || ':' || c."sourceId" || ':' || c."postedBy" || ' / ' || zz.lines(c.id)
     from public.cash_docs c where c.op = 'out_salary'),
  '^KO2:out_salary:posted:employee:teachers:tch1:Sinov O''qituvchi:salary_payments:sp_IQT-T1_2026-12_n1:U_KAS / 6710>5010=1000000@OP-09$');
select zz.chk('S1b maosh to''lovi: usul, order havolasi, kassa kuni, «kim» — serverdan',
  (select method || ':' || ("cashDocId" is not null) || ':' || date || ':' || "byUid" || ':' || trim_scale(paid) from public.salary_payments where id = 'sp_IQT-T1_2026-12_n1'), '^cash:true:2027-01-04:U_KAS:1000000$');
select zz.chk('S1c kassa qoldig''i 4 000 000', zz.bal(), '^4000000$');
select zz.chk('S2 qayta yuborish — takror, yangi hujjat yo''q',
  zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_n1', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1000000)) || ' / ' || (select count(*) from public.cash_docs where op = 'out_salary'),
  '"dup": true.* / 1$');
select zz.chk('S2b o''sha kalit, boshqa summa — rad', zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_n1', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 999)), '^ERR 22023 \[kassa:ref_mismatch\]');
select zz.chk('S3 tasdiqlangan vedomostdan ortiq — rad (qolgan 1 900 000)',
  zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_n2', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1900001)), '^ERR 23514 .*berish mumkin: 1900000');
select zz.chk('S3b atomar: rad etilgan to''lovdan iz yo''q',
  (select count(*) from public.salary_payments where id = 'sp_IQT-T1_2026-12_n2') || '/' || (select count(*) from public.cash_docs where op = 'out_salary') || '/' || zz.bal(), '^0/1/4000000$');
select zz.chk('S4 Moliya menejeri naqd maosh bera olmaydi', zz.rpc('U_FM', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_n3', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1000)), '^ERR 42501 \[kassa:cash_role\]');
select zz.chk('S4b HR naqd maosh bera olmaydi', zz.rpc('U_HR', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_n3', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1000)), '^ERR 42501 \[kassa:cash_role\]');
select zz.put('S5', zz.rpc('U_FM', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-12_c1', 'card', 'IQX-T1', 'staff:st1', '2026-12', 500000)));
select zz.chk('S5 karta orqali: Moliya menejeri yozadi, kassa hujjati yo''q',
  zz.get('S5') || ' / ' || (select method || ':' || coalesce("cashDocId", '-') from public.salary_payments where id = 'sp_IQX-T1_2026-12_c1') || ' / ' || zz.bal(),
  '"kassa": null.* / card:- / 4000000$');
select zz.chk('S5b kassir karta to''lovini yoza olmaydi', zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-12_c2', 'card', 'IQX-T1', 'staff:st1', '2026-12', 1000)), '^ERR 42501');
select zz.chk('S5c state-9: karta orqali yozilgan kalit bilan qayta yuborish — usul boshqa (naqd) yoki xodim kartasi boshqa — rad; aynan o''sha — takror',
  zz.rpc('U_DIR', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-12_c1', 'cash', 'IQX-T1', 'staff:st1', '2026-12', 500000)) || ' | '
  || zz.rpc('U_FM', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-12_c1', 'card', 'IQX-T1', 'teachers:tch1', '2026-12', 500000)) || ' | '
  || (zz.js(zz.rpc('U_FM', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-12_c1', 'card', 'IQX-T1', 'staff:st1', '2026-12', 500000))) ->> 'dup') || ':' || zz.bal(),
  '^ERR 22023 \[kassa:ref_mismatch\].* \| ERR 22023 \[kassa:ref_mismatch\].* \| true:4000000$');
select zz.chk('S6 kassa ishga tushgach to''g''ridan-to''g''ri yozuv rad (kassir)',
  zz.as('U_KAS', $q$with x as (insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date) values ('sp_dir_1','IQT-T1','teachers:tch1','Sinov','2026-12',1000,'2027-01-04') returning id) select id from x$q$), '^ERR 42501 \[kassa:cash_only_kassa\]');
select zz.chk('S6b … va Moliya menejeri (usul bilan ham)',
  zz.as('U_FM', $q$with x as (insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date, method) values ('sp_dir_2','IQT-T1','teachers:tch1','Sinov','2026-12',1000,'2027-01-04','card') returning id) select id from x$q$), '^ERR 42501 \[kassa:cash_only_kassa\]');
select zz.chk('S7 vedomost tasdig''i yoqilmagan oy (2026-11): kassirga naqd — rad',
  zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-11_n1', 'cash', 'IQX-T1', 'staff:st1', '2026-11', 200000)), '^ERR 42501 \[kassa:payroll_gate\]');
select zz.put('S7b', zz.rpc('U_DIR', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-11_n1', 'cash', 'IQX-T1', 'staff:st1', '2026-11', 200000)));
select zz.chk('S7b … Direktor ruxsati bilan — o''tadi va nazorat ro''yxatida ko''rinadi',
  zz.get('S7b') || ' / ' || (select "sourceSnapshot" ->> 'gateOff' from public.cash_docs where "sourceId" = 'sp_IQX-T1_2026-11_n1') || ' / ' || zz.as('U_FM', $q$select c ->> 'salaryGateOff30' from public.kassa_checks('main') c$q$),
  '"no": 2[,}].* / true / 1$');
select zz.chk('S8 kassada pul yetmasa — rad, maosh to''lovi ham yozilmaydi',
  zz.rpc('U_DIR', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-11_n2', 'cash', 'IQX-T1', 'staff:st1', '2026-11', 9000000)) || ' / ' || (select count(*) from public.salary_payments where id = 'sp_IQX-T1_2026-11_n2'),
  '^ERR P0001 \[kassa:negative\].* / 0$');
select zz.chk('S9 bog''langan maosh qatorini mijoz o''chira olmaydi',
  zz.as('U_DIR', $q$with x as (delete from public.salary_payments where id = 'sp_IQT-T1_2026-12_n1' returning id) select count(*)::text from x$q$), '^ERR 42501 \[kassa:linked_row\]');
savepoint s9c;
set local iqror.rekey = '1';   -- «Yangi noyob ID berish» (id-guards.sql: rekey_payroll_id) shu bayroq ostida xodim kalitini almashtiradi (vedomost darvozasidan oldingi oy qatori)
update public.salary_payments set "teacherId" = 'IQX-T9' where id = 'sp_IQX-T1_2026-11_n1';
select (select "teacherId" from public.salary_payments where id = 'sp_IQX-T1_2026-11_n1') || ' | '
  || zz.as('U_DIR', $q$with x as (update public.salary_payments set paid = 1 where id = 'sp_IQX-T1_2026-11_n1' returning id) select count(*)::text from x$q$) as s9c \gset
rollback to savepoint s9c;
select zz.chk('S9c bog''langan maosh qatorida xodim kalitini almashtirish (ID tuzatish) — o''tadi; mijoz maosh qatorini umuman o''zgartira olmaydi (RLS: 0 qator)',
  :'s9c' || ' | ' || zz.as('U_DIR', $q$with x as (update public.salary_payments set "teacherId" = 'IQX-T9' where id = 'sp_IQX-T1_2026-11_n1' returning id) select count(*)::text from x$q$),
  '^IQX-T9 \| 0 \| 0$');
select zz.chk('S9b maosh orderi «pulni berish» orqali qayta o''tkazilmaydi', zz.pay('U_KAS', (select id from public.cash_docs where "sourceId" = 'sp_IQT-T1_2026-12_n1')), '^ERR 42501 \[kassa:linked_doc\]');
select zz.put('S10', zz.void('U_FM', (select id from public.cash_docs where "sourceId" = 'sp_IQX-T1_2026-11_n1'), 'Xato xodimga yozilgan'));
select zz.chk('S10 maosh orderi shu kunda bekor qilindi: to''lov qatori ham olib tashlandi, qoldiq tiklandi',
  (select status || ':' || no from public.cash_docs where "sourceId" = 'sp_IQX-T1_2026-11_n1') || ' / ' || (select count(*) from public.salary_payments where id = 'sp_IQX-T1_2026-11_n1') || ' / ' || zz.bal(),
  '^void:2 / 0 / 4000000$');
-- g11 (sec-1, FD-48): Direktor o'z kartasiga (bog'langan xodim kartasi — st1) naqd maoshni o'zi bermaydi (vedomostni o'zi tasdiqlaydi) —
--   kassir beradi (tasdiqlangan vedomost bo'yicha). Savepoint ichida (keyingi raqamlar va qoldiq o'zgarmasin).
savepoint s11;
set local session_replication_role = replica;
update public.users set "staffRefType" = 'staff', "staffRefId" = 'st1' where id = 'U_DIR';
set local session_replication_role = origin;
select zz.rpc('U_DIR', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-12_d1', 'cash', 'IQX-T1', 'staff:st1', '2026-12', 100000)) as s11 \gset
select :'s11' || ' | ' || (select count(*) from public.salary_payments where id = 'sp_IQX-T1_2026-12_d1') || ' | '
       || zz.jdp(zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-12_k1', 'cash', 'IQX-T1', 'staff:st1', '2026-12', 100000)), '{kassa,status}', '-') as s11 \gset
select :'s11' || ':' || coalesce((select c."postedBy" || '/' || c."partyId" from public.cash_docs c where c."sourceId" = 'sp_IQX-T1_2026-12_k1'), '-') as s11 \gset
-- o'tish oyidan oldingi oy (2026-11 — vedomostsiz; kassir naqd maosh bermaydi, kassa:payroll_gate): xabar chiqish yo'lini aytadi (karta)
select zz.rpc('U_DIR', 'kassa_salary_pay', zz.sal('sp_IQX-T1_2026-11_d2', 'cash', 'IQX-T1', 'staff:st1', '2026-11', 100000)) as s11g \gset
select :'s11g' || ' | ' || (select count(*) from public.salary_payments where id = 'sp_IQX-T1_2026-11_d2') as s11g \gset
rollback to savepoint s11;
select zz.chk('S11 g11 (sec-1, FD-48): Direktor o''z kartasiga naqd maosh bera olmaydi (kassa:self_recipient, yozuv yo''q); kassir beradi (tasdiqlangan vedomost bo''yicha)',
  :'s11', '^ERR 42501 \[kassa:self_recipient\] Bu maosh sizga \(bog''langan xodim kartangizga\) beriladi — Direktor o''ziga naqd maoshni o''zi bermaydi: pulni kassir beradi \(FD-48\) \| 0 \| posted:U_KAS/staff:st1$');
select zz.chk('S11b o''tish oyidan oldingi oy (vedomostsiz — kassir naqd maosh bermaydi): Direktorga rad xabari chiqish yo''lini aytadi (karta orqali), yozuv yo''q',
  :'s11g', '^ERR 42501 \[kassa:self_recipient\] Bu maosh sizga .*\(FD-48\)\. 2026-11 oy maoshi HR tasdiqlagan vedomostsiz \(o''tish oyidan oldin\) — bunday oyda kassir naqd maosh bermaydi: maoshingizni karta orqali yozing \| 0$');

-- ---------- (A) ish haqi avansi ----------
select zz.put('A1', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_advance","amount":300000,"partyType":"employee","partyId":"staff:st1","basis":"Ariza, 03.01.2027","clientRef":"a1-000001"}'));
select zz.chk('A1 avans so''rovi: 2-ro''yxat tasdig''ini kutadi, avans hali yozilmagan',
  (zz.js(zz.get('A1')) ->> 'status') || ':' || (zz.js(zz.get('A1')) ->> 'needsList2') || ':' || (select count(*) from public.staff_advances), '^draft:true:0$');
select zz.chk('A2 tasdiqsiz pul berilmaydi', zz.pay('U_KAS', zz.id('A1')), '^ERR 42501 \[kassa:not_approved\]');
select zz.put('A2b', zz.appr('U_FM', zz.id('A1')));
select zz.put('A3', zz.pay('U_KAS', zz.id('A1')));
select zz.chk('A3 pul berildi: order № 3, Dt 4210 Kt 5010', (zz.js(zz.get('A3')) ->> 'no') || ' / ' || zz.lines(zz.id('A1')), '^3 / 4210>5010=300000@OP-08$');
select zz.chk('A3b avans qatori shu tranzaksiyada: xodim kodi, oy, sana, usul, order havolasi',
  (select "teacherId" || ':' || "payeeRef" || ':' || "teacherName" || ':' || trim_scale(amount) || ':' || month || ':' || date || ':' || method || ':' || ("cashDocId" = zz.id('A1')) from public.staff_advances),
  '^IQX-T1:staff:st1:Sinov Xodim:300000:2027-01:2027-01-04:cash:true$');
select zz.chk('A3c oylik hisobida avans ko''rinadi', trim_scale(app.payroll_adv('IQX-T1', '2027-01'))::text, '^300000$');
select zz.chk('A3d qayta chaqiruv — takror, ikkinchi avans yozilmaydi', zz.pay('U_KAS', zz.id('A1')) || ' / ' || (select count(*) from public.staff_advances), '"dup": true.* / 1$');
select zz.chk('A4 naqd avansni to''g''ridan-to''g''ri yozib bo''lmaydi',
  zz.as('U_FM', $q$with x as (insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date) values ('adv_dir_1','IQX-T1','staff:st1','Sinov',1000,'2027-01','2027-01-04') returning id) select id from x$q$), '^ERR 42501 \[kassa:cash_only_kassa\]');
select zz.chk('A4b karta orqali avans — Moliya menejeri avvalgidek yozadi',
  zz.as('U_FM', $q$with x as (insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date, method) values ('adv_card_1','IQX-T1','staff:st1','Sinov',50000,'2027-01','2027-01-04','card') returning id) select id from x$q$), '^adv_card_1$');
select zz.chk('A4c bog''langan avans qatorini mijoz o''zgartira / o''chira olmaydi',
  zz.as('U_DIR', $q$with x as (update public.staff_advances set amount = 1 where "cashDocId" is not null returning id) select count(*)::text from x$q$) || ' | ' ||
  zz.as('U_DIR', $q$with x as (delete from public.staff_advances where "cashDocId" is not null returning id) select count(*)::text from x$q$),
  '^ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:linked_row\]');
select zz.put('A5', zz.void('U_KAS', zz.id('A1'), 'Xodim pulni olmadi'));
select zz.chk('A5 avans orderi bekor qilindi: avans qatori ham olib tashlandi (karta avansi joyida)',
  (zz.js(zz.get('A5')) ->> 'status') || ' / ' || (select string_agg(id, ',') from public.staff_advances) || ' / ' || zz.bal(), '^void / adv_card_1 / 4000000$');
-- oy vedomosti tasdiqlangach avans yo'q: yangi so'rov rad; avval tasdiqlangan so'rov bo'yicha pul ham berilmaydi
select zz.put('A6', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_advance","amount":100000,"partyType":"employee","partyId":"teachers:tch1","basis":"Ariza, 04.01.2027","clientRef":"a6-000001"}'));
select zz.put('A6b', zz.appr('U_FM', zz.id('A6')));
set local session_replication_role = replica;
insert into public.payroll_runs (id, status, "approvedBy", "approvedAt") values ('2027-01', 'approved', 'U_HR', now());
set local session_replication_role = origin;
select zz.chk('A6 yanvar vedomosti tasdiqlangan: yangi avans so''rovi rad',
  zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_advance","amount":100000,"partyType":"employee","partyId":"teachers:tch1","basis":"Ariza","clientRef":"a6-000002"}'), '^ERR 42501 \[kassa:advance_locked\]');
select zz.chk('A6b avval tasdiqlangan so''rov bo''yicha ham pul berilmaydi; hujjat o''tmaydi, raqam sarflanmaydi',
  zz.pay('U_KAS', zz.id('A6')) || ' / ' || (select status || ':' || coalesce(no::text, '-') from public.cash_docs where id = zz.id('A6')) || ' / ' || (select "lastNo" from public.doc_counters where desk = 'main' and series = 'KO2'),
  '^ERR 42501 .*vedomost tasdiqlangan.* / approved:- / 3$');
set local session_replication_role = replica;
delete from public.payroll_runs where id = '2027-01';
set local session_replication_role = origin;

-- ---------- (R) qaytarish ----------
select zz.chk('R0 qaytarish so''rovini faqat Direktor yozadi',
  zz.rpc('U_FM', 'kassa_refund_request', '{"target":"invoice","id":"ia","amount":300000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_test_0001"}'), '^ERR 42501');
select zz.put('R1', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ia","amount":300000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clawback":true,"requestDate":"2027-01-03","clientRef":"rf_test_0001"}'));
select zz.chk('R1 Direktor so''rovi: tasdiqlangan, raqamsiz; summa = 300 000 + avans 150 000; oluvchi F.I.Sh.',
  (zz.js(zz.get('R1')) ->> 'status') || ':' || zz.jd(zz.get('R1'), 'no', '-') || ':' || (zz.js(zz.get('R1')) ->> 'amount') || ':' || (zz.js(zz.get('R1')) ->> 'partyName') || ':' || (zz.js(zz.get('R1')) ->> 'dirApprovedBy')
  || ' / ' || zz.lines(zz.id('R1')) || ' / ' || (zz.js(zz.get('R1')) ->> 'basis'),
  '^approved:-:450000:Sinov Ota Onaevich:U_DIR / 4010>5010=300000@OP-15, 6310>5010=150000@OP-15 / Qaytarish: O''quvchi ketdi; ariza 03.01.2027$');
select zz.chk('R1b so''rov paytida balans o''zgarmaydi: faktura, avans, jurnal',
  (select trim_scale("paidAmount") || ':' || status from public.invoices where id = 'ia') || '/' || (select trim_scale(credit) from public.student_credit where id = 'T-1') || '/' || (select count(*) from public.refunds), '^1000000:paid/150000/0$');
select zz.chk('R1c qayta yuborish (o''sha kalit va mazmun) — takror', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ia","amount":300000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clawback":true,"requestDate":"2027-01-03","clientRef":"rf_test_0001"}'), '"dup": true');
select zz.chk('R1d Moliya menejeri pulni bera olmaydi', zz.pay('U_FM', zz.id('R1')), '^ERR 42501');
select zz.put('R2', zz.pay('U_KAS', zz.id('R1')));
select zz.chk('R2 kassir pulni berdi: order № 4; faktura 700 000 (qisman), avans 0',
  (zz.js(zz.get('R2')) ->> 'no') || ' / ' || (select trim_scale("paidAmount") || ':' || status from public.invoices where id = 'ia') || ' / ' || (select trim_scale(credit) from public.student_credit where id = 'T-1') || ' / ' || zz.bal(),
  '^4 / 700000:partial / 0 / 3550000$');
select zz.chk('R2b qaytarish jurnali shu tranzaksiyada: 2 qator, usul naqd, order havolasi, «kim» — kassir',
  (select string_agg(target || '=' || trim_scale(amount) || ':' || method || ':' || ("cashDocId" = zz.id('R1')) || ':' || "byUid", ',' order by target desc) from public.refunds),
  '^invoice=300000:cash:true:U_KAS,credit=150000:cash:true:U_KAS$');
select zz.chk('R3 qayta chaqiruv — takror, ikkinchi marta qaytarilmaydi',
  zz.pay('U_KAS', zz.id('R1')) || ' / ' || (select count(*) from public.refunds) || ' / ' || (select trim_scale("paidAmount") from public.invoices where id = 'ia'), '"dup": true.* / 2 / 700000$');
select zz.chk('R3b qaytarish orderi bekor qilinmaydi', zz.void('U_DIR', zz.id('R1'), 'Sinov uchun bekor'), '^ERR 42501 \[kassa:linked_doc\]');
select zz.put('R4', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ib","amount":100000,"reason":"Ortiqcha to''lov","payee":"Sinov Ota Onaevich","clientRef":"rf_test_0004"}'));
select zz.chk('R4 kelgusi oy fakturasidan qaytarish — Dt 6310', zz.lines(zz.id('R4')), '^6310>5010=100000@OP-15$');
select zz.chk('R4b ogohlantirish: hali kechikmagan', zz.as('U_KAS', $q$select (s -> 'pending' ->> 'refundsLate') || ':' || (s -> 'pending' ->> 'toPay') from public.kassa_state('main') s$q$), '^0:2$');
-- tasdiqdan keyin holat o'zgarsa (Direktor shu orada naqdsiz qaytaradi, provayder pulni qaytaradi) → kassa so'rovi bo'yicha pul berilmaydi
select zz.put('R5', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ia","amount":500000,"reason":"Qayta hisob","payee":"Sinov Ota Onaevich","clientRef":"rf_test_0005"}'));
-- g8 (g2 qoldig'i): kutilayotgan naqd so'rov (500 000) bilan naqdsiz qaytarish jami to'langandan (700 000) oshsa — rad (javob yo'qolgach
--   o'sha oynadan «bank» bilan qayta urinish qisman qaytarishni ikki marta bajarmasin); sig'sa — avvalgidek darhol. Bajarilgan naqdsiz
--   qaytarishni o'sha kalit bilan qayta yuborish — takror (dup), so'rov tufayli xato emas (endi to'langan 500 000 + so'rov 500 000 sig'maydi)
select zz.chk('R5a naqdsiz qaytarish: kutilayotgan naqd so''rov bilan jami to''langandan oshsa — rad, faktura tegilmaydi; sig''sa — avvalgidek darhol (Direktor); o''sha kalit bilan qayta yuborish — takror',
  zz.as('U_DIR', $q$select public.refund_invoice('invoice','ia',400000,'bank orqali qaytarildi',false,'d@x','rf_bank_0001')::text$q$) || ' | '
  || (select trim_scale("paidAmount")::text from public.invoices where id = 'ia') || ' | '
  || zz.as('U_DIR', $q$select public.refund_invoice('invoice','ia',200000,'bank orqali qaytarildi',false,'d@x','rf_bank_0002') ->> 'ok'$q$) || ' | '
  || zz.as('U_DIR', $q$select public.refund_invoice('invoice','ia',200000,'bank orqali qaytarildi',false,'d@x','rf_bank_0002')::text$q$) || ' | '
  || zz.as('U_DIR', $q$select trim_scale("paidAmount") || ':' || (select count(*) from public.refunds r where r."targetId" = 'ia' and r."cashDocId" is null) from public.invoices where id = 'ia'$q$),
  '^ERR 22023 \[kassa:refund_pending\].*\(500000 so''m\).*\(700000 so''m\).* \| 700000 \| true \| \{"dup": true, "ref": "rf_bank_0002"\} \| 500000:1$');
-- provayder qolgan qismdan 200 000 ni qaytardi (server roli — kutilayotgan so'rov server qaytarishini to'xtatmaydi): to'langan 300 000
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select zz.put('R5r', public.reverse_payment('ia', 200000, 'click', 'clk_r5_0001')::text);
select set_config('request.jwt.claims', '', true);
select zz.chk('R5b holat o''zgargan: pul berilmaydi, hujjat o''tmaydi, raqam sarflanmaydi, faktura tegilmaydi',
  zz.pay('U_KAS', zz.id('R5')) || ' / ' || (select status || ':' || coalesce(no::text, '-') from public.cash_docs where id = zz.id('R5')) || ' / ' || (select trim_scale("paidAmount") from public.invoices where id = 'ia')
  || ' / ' || (select "lastNo" from public.doc_counters where desk = 'main' and series = 'KO2'),
  '^ERR P0001 \[kassa:refund\].* / approved:- / 300000 / 4$');
select zz.chk('R5c Direktor so''rovni bekor qiladi', zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('R5'), 'Naqdsiz qaytarildi')), '"status": "cancelled"');
select zz.chk('R6 biriktirilmagan to''lov: qisman qaytarish so''rovi rad',
  zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"payment","id":"pu1","amount":100000,"reason":"Egasi topilmadi","payee":"Sinov Begona Shaxs","clientRef":"rf_test_0006"}'), '^ERR 22023 \[kassa:refund\]');
select zz.put('R6b', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"payment","id":"pu1","amount":250000,"reason":"Egasi topilmadi","payee":"Sinov Begona Shaxs","clientRef":"rf_test_0007"}'));
select zz.put('R6c', zz.pay('U_KAS', zz.id('R6b')));
select zz.chk('R6b biriktirilmagan to''lov to''liq qaytarildi: tomon — «boshqa», Dt 6390 (aniqlanmagan tushum, OP-16); to''lov «qaytarilgan»',
  (zz.js(zz.get('R6c')) ->> 'partyType') || ':' || (zz.js(zz.get('R6c')) ->> 'status') || ' / ' || zz.lines(zz.id('R6b')) || ' / ' || (select status from public.payments where id = 'pu1')
  || ' / ' || (select method || ':' || ("cashDocId" = zz.id('R6b')) from public.refunds where target = 'payment'),
  '^other:posted / 6390>5010=250000@OP-16 / refunded / cash:true$');
-- o'quvchi qatori yo'q (eski, «yetim» faktura): tomon — «boshqa», qaytarish baribir bajariladi
set local session_replication_role = replica;
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values ('iz','T-OLD','Sinov Eski','2026-11',500000,500000,'paid');
set local session_replication_role = origin;
select zz.put('R6d', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"iz","amount":200000,"reason":"Eski faktura","payee":"Sinov Eski Otasi","clientRef":"rf_test_0008"}'));
select zz.put('R6e', zz.pay('U_KAS', zz.id('R6d')));
select zz.chk('R6d o''quvchi qatori yo''q faktura: tomon «boshqa», qaytarish bajarildi',
  (zz.js(zz.get('R6d')) ->> 'partyType') || ':' || (zz.js(zz.get('R6e')) ->> 'status') || ':' || (select trim_scale("paidAmount") || ':' || status from public.invoices where id = 'iz'), '^other:posted:300000:partial$');
select zz.chk('R7 kassir refund_invoice ni o''zi chaqira olmaydi', zz.as('U_KAS', $q$select public.refund_invoice('invoice','ib',1000,'sinov',false,'','rf_kas_0001')::text$q$), '^ERR 42501');

-- ---------- (E) xarajat: «Buxgalteriya»ga ko'chish ----------
select zz.put('cp', zz.as('U_KAS', $q$select public.fin_counterparty_save(null, 'supplier', 'Sinov Ta''minot MChJ', '123456789')::text$q$));
select zz.put('E1', zz.rpc('U_KAS', 'kassa_payout_request', format('{"op":"out_expense","amount":180000,"partyType":"counterparty","partyId":"%s","basis":"Hisob-faktura № 5","clientRef":"e1-000001","lines":[{"articleId":"EX-32","amount":120000},{"articleId":"EX-07","amount":60000}]}', zz.id('cp'))));
select zz.put('E1b', zz.appr('U_FM', zz.id('E1')));
select zz.chk('E1 tasdiqlangan, hali to''lanmagan: «Buxgalteriya»da yozuv yo''q', (select count(*)::text from public.expenses), '^0$');
select zz.put('E2', zz.pay('U_KAS', zz.id('E1')));
select zz.chk('E2 pul berildi: har qator xarajat bo''lib ko''chdi (statiya → toifa; mos toifa bo''lmasa — «Boshqa»)',
  (select string_agg(category || '=' || trim_scale(amount) || ':' || method || ':' || "articleId" || ':' || ("counterpartyId" = zz.id('cp')) || ':' || date || ':' || month || ':' || ("cashDocId" = zz.id('E1')), ' | ' order by id) from public.expenses),
  '^Kanselyariya=120000:cash:EX-32:true:2027-01-04:2027-01:true \| Boshqa=60000:cash:EX-07:true:2027-01-04:2027-01:true$');
select zz.chk('E2b izohda tomon, asos va order raqami', (select note from public.expenses order by id limit 1), '^Sinov Ta''minot MChJ — Hisob-faktura № 5 \(KO-2 № 7\)$');
select zz.chk('E3 naqd (usulsiz) xarajatni to''g''ridan-to''g''ri yozib bo''lmaydi',
  zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note) values ('ex_dir_1','2027-01-04','2027-01','Boshqa',1000,'sinov') returning id) select id from x$q$), '^ERR 42501 \[kassa:cash_only_kassa\]');
select zz.chk('E3b naqdsiz xarajat (usuli bilan) — avvalgidek',
  zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_bank_1','2027-01-04','2027-01','Ijara',700000,'bank orqali','bank') returning id) select id from x$q$), '^ex_bank_1$');
select zz.chk('E3b2 naqdsiz xarajatga statiya toifadan o''zi qo''yiladi', (select "articleId" from public.expenses where id = 'ex_bank_1'), '^EX-10$');
select zz.chk('E3c oylik maoshni hisoblash qatori (payroll__) — avvalgidek',
  zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note) values ('payroll__2027-01','2027-01-01','2027-01','Maosh',5000000,'Avtomatik') returning id) select id from x$q$), '^payroll__2027-01$');
select zz.chk('E3c2 maosh hisoblash qatoriga statiya qo''yilmaydi', coalesce((select "articleId" from public.expenses where id = 'payroll__2027-01'), '-'), '^-$');
select zz.chk('E3d kassadan ko''chgan xarajatni mijoz o''zgartira / o''chira olmaydi; naqdsiz yozuvni «naqd»ga aylantira olmaydi',
  zz.as('U_DIR', $q$with x as (update public.expenses set amount = 1 where "cashDocId" is not null returning id) select count(*)::text from x$q$) || ' | ' ||
  zz.as('U_DIR', $q$with x as (delete from public.expenses where "cashDocId" is not null returning id) select count(*)::text from x$q$) || ' | ' ||
  zz.as('U_DIR', $q$with x as (update public.expenses set method = 'cash' where id = 'ex_bank_1' returning id) select count(*)::text from x$q$),
  '^ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:linked_row\].* \| ERR 42501 \[kassa:cash_only_kassa\]');
select zz.chk('E3e naqdsiz yozuvni tahrirlash — avvalgidek', zz.as('U_FM', $q$with x as (update public.expenses set amount = 710000 where id = 'ex_bank_1' returning trim_scale(amount)::text as a) select a from x$q$), '^710000$');
select zz.put('E4', zz.void('U_FM', zz.id('E1'), 'Tovar qaytarildi'));
select zz.chk('E4 xarajat orderi bekor qilindi: ko''chgan yozuvlar olib tashlandi',
  (zz.js(zz.get('E4')) ->> 'status') || ' / ' || (select string_agg(id, ',' order by id) from public.expenses), '^void / ex_bank_1,payroll__2027-01$');
-- crit-1: kassa ishga tushishidan OLDINGI sanali naqd yozuv (kech kelgan chek, maosh / avans qog'ozi — pul sanashdan oldin chiqqan):
--   faqat Direktor kiritadi (boshqalarga — alohida xabar); ishga tushgan kundan — avvalgidek faqat «Kassa» orqali; davr qulfi amal qiladi.
select zz.chk('EP1 Moliya menejeri 02.01 sanali naqd xarajat — faqat Direktor (kassa:pre_live)',
  zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_pre_1','2027-01-02','2027-01','Boshqa',12000,'kech kelgan chek','cash') returning id) select id from x$q$),
  '^ERR 42501 \[kassa:pre_live\] 02\.01\.2027 — kassa ishga tushishidan \(04\.01\.2027\) oldingi sana');
select zz.put('EP2', zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_pre_1','2027-01-02','2027-01','Boshqa',12000,'kech kelgan chek','cash') returning id || ':' || coalesce("articleId", '-') as r) select r from x$q$)
  || ' | ' || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_pre_2','2027-01-04','2027-01','Boshqa',12000,'bugungi','cash') returning id) select id from x$q$));
select zz.chk('EP2 Direktor: o''sha xarajat — yoziladi (statiya toifadan); ishga tushgan kundagi (04.01) naqd xarajat esa — Direktorga ham «Kassa» orqali',
  zz.get('EP2'), '^ex_pre_1:EX-49 \| ERR 42501 \[kassa:cash_only_kassa\]');
select zz.chk('EP3 avans va maosh (kassadan oldingi sana; vedomosti tasdiqlanmagan oy): Moliya menejeri — rad; Direktor — yoziladi',
  zz.as('U_FM', $q$with x as (insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date, method) values ('adv_pre_1','IQX-T1','staff:st1','Sinov',7000,'2026-11','2026-11-30','cash') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date, method) values ('adv_pre_1','IQX-T1','staff:st1','Sinov',7000,'2026-11','2026-11-30','cash') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date) values ('sp_pre_1','IQT-T1','teachers:tch1','Sinov','2026-11',9000,'2026-12-29') returning id) select id from x$q$),
  '^ERR 42501 \[kassa:pre_live\].* \| adv_pre_1 \| sp_pre_1$');
select zz.chk('EP4 kassadan oldingi sanali naqdsiz yozuvni «naqd»ga aylantirish: Moliya menejeri — rad, Direktor — mumkin',
  left(zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_pre_3','2027-01-03','2027-01','Boshqa',5000,'bank','bank') returning id) select id from x$q$), 0)
  || zz.as('U_FM', $q$with x as (update public.expenses set method = 'cash' where id = 'ex_pre_3' returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.expenses set method = 'cash' where id = 'ex_pre_3' returning method) select method from x$q$),
  '^ERR 42501 \[kassa:pre_live\].* \| cash$');
select zz.chk('EP4b kassadan oldingi naqd yozuvni tahrirlab kassa ishlayotgan kunga ko''chirib bo''lmaydi (Direktor ham); oldingi sanalar ichida tahrir — mumkin',
  zz.as('U_FM', $q$with x as (update public.expenses set date = '2027-01-05' where id = 'ex_pre_1' returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.expenses set date = '2027-01-04' where id = 'ex_pre_1' returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (update public.expenses set date = '2027-01-03', note = 'kech kelgan chek (tuzatildi)' where id = 'ex_pre_1' returning date) select date from x$q$),
  '^ERR 42501 \[kassa:cash_only_kassa\] Kassa hujjatisiz naqd yozuvning sanasini kassa ishga tushgan kunga.* \| ERR 42501 \[kassa:cash_only_kassa\].* \| 2027-01-03$');
-- g4-v1 (e): istisno faqat NAQD yozuvga (usuli 'cash' yoki ko'rsatilmagan) — hisobdor shaxs xarajati va karta orqali maosh
--   kassadan oldingi sana bilan ham Direktorga avvalgidek o'z oynasi orqali (ro'yxatda ko'rinmaydigan yozuv bo'lmasin)
select zz.chk('EP4c kassadan oldingi sana: Direktor — hisobdor shaxs xarajati, karta orqali maosh va bankdan avans — rad (kassa:cash_only_kassa)',
  zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_pre_5','2027-01-02','2027-01','Boshqa',4000,'hisobdor','accountable') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date, method) values ('sp_pre_2','IQT-T1','teachers:tch1','Sinov','2026-11',9000,'2026-12-29','card') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date, method) values ('adv_pre_2','IQX-T1','staff:st1','Sinov',7000,'2026-11','2026-11-30','bank') returning id) select id from x$q$),
  '^ERR 42501 \[kassa:cash_only_kassa\] Kassa ishga tushgan: hisobdor shaxs xarajati.* \| ERR 42501 \[kassa:cash_only_kassa\] Kassa ishga tushgan: maosh.* \| ERR 42501 \[kassa:cash_only_kassa\] Kassa ishga tushgan: naqd avans.*$');
-- g8 (g4b qoldig'i): kassa ishlayotganda ham sanasiz naqd yozuv yo'q — yangisi (Direktor ham) rad, mavjud naqd yozuvning sanasini bo'shatish rad
select zz.chk('EP4d sanasiz naqd yozuv: yangi (Direktor, usulsiz ham) — rad; kassadan oldingi naqd yozuvning sanasini bo''shatish — rad (kassa:cash_date)',
  zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_nd_1', null, '2027-01', 'Boshqa', 1000, 'sanasiz', 'cash') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note) values ('ex_nd_2', null, '2027-01', 'Boshqa', 1000, 'sanasiz, usulsiz') returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.expenses set date = null where id = 'ex_pre_1' returning id) select id from x$q$) || ' | '
  || (select date from public.expenses where id = 'ex_pre_1'),
  '^ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_date\] Kassa ishga tushgan: naqd \(yoki usuli ko''rsatilmagan\) yozuvning sanasi bo''shatilmaydi.* \| 2027-01-03$');
select zz.put('EP5q', zz.as('U_DIR', $q$select public.fin_period_lock('2027-01-01', '')::text$q$));
select zz.chk('EP5 davr qulfi baribir: 01.01 gacha yopilgan davrga Direktor ham kassadan oldingi naqd yozuv kirita olmaydi',
  (zz.js(zz.get('EP5q')) ->> 'lockedThrough') || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('ex_pre_4','2027-01-01','2027-01','Boshqa',3000,'yopilgan davr','cash') returning id) select id from x$q$),
  '^2027-01-01 \| ERR 42501 \[fin:locked\]');
-- state-1: yopilgan davrdagi biriktirilmagan to'lovni naqd qaytarish — so'rov ham yozilmaydi (pul berishda holati o'zgarib, yopilgan davr
--   tushumi o'zgarardi); davr qayta ochilsa — avvalgidek (so'rov bekor qilinadi, keyingi tekshiruvlarga ta'sir qilmasin)
set local session_replication_role = replica;
insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw, "createdAt") values
  ('pu_lk', '', 'bank', 45000, 'unmatched', 'Noma''lum To''lovchi 3', false, '{}', '2026-12-30 10:00+05');
set local session_replication_role = origin;
select zz.chk('EP5c state-1: yopilgan davr (30.12) biriktirilmagan to''lovi — naqd qaytarish so''rovi rad (fin:locked, davrni qayta ochish tartibi), so''rov yozilmadi',
  zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"payment","id":"pu_lk","amount":45000,"reason":"Egasi topilmadi","payee":"Sinov Begona Shaxs","clientRef":"rf_lk_000001"}') || ' | '
  || (select count(*) from public.cash_docs where "clientRef" = 'ref_rf_lk_000001'),
  '^ERR 42501 \[fin:locked\] To‘lov \(30\.12\.2026 kuni\) yopilgan davrga tegishli \(01\.01\.2027 gacha yopilgan\).*Direktor «Davr»da davrni sababi bilan qayta ochadi.* \| 0$');
select zz.chk('EP5b qulf olib tashlandi', zz.jd(zz.as('U_DIR', $q$select public.fin_period_lock(null, 'Sinov: qulf olib tashlandi')::text$q$), 'lockedThrough', 'yo''q'), '^yo''q$');
select zz.put('EP5d', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"payment","id":"pu_lk","amount":45000,"reason":"Egasi topilmadi","payee":"Sinov Begona Shaxs","clientRef":"rf_lk_000002"}'));
select zz.chk('EP5d qulf olib tashlangach — so''rov yoziladi (keyin bekor qilindi)',
  (zz.js(zz.get('EP5d')) ->> 'status') || ':' || (zz.js(zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('EP5d'), 'Sinov: bekor'))) ->> 'status'),
  '^approved:cancelled$');
select zz.chk('EP6 nazorat ro''yxati: «kassa ishga tushishidan oldingi naqd yozuvlar (keyin kiritilgan)» — xarajat 2 ta, maosh 1, avans 1 (turi bo''yicha)',
  (select string_agg((i ->> 'kind') || '=' || (i ->> 'n') || '/' || (i ->> 'sum'), ',' order by i ->> 'kind')
     from (select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) as c) q, jsonb_array_elements(c #> '{preLive,items}') i),
  '^advance=1/7000,expense=2/17000,salary=1/9000$');
-- (keyingi tekshiruvlarga ta'sir qilmasin — kassaga bog'lanmagan yozuvlar Direktor tomonidan olib tashlanadi)
select zz.chk('EP7 tozalash: bog''lanmagan kassadan oldingi yozuvlarni Direktor o''chira oladi',
  zz.as('U_DIR', $q$with x as (delete from public.expenses where id in ('ex_pre_1', 'ex_pre_3') returning id) select count(*)::text from x$q$) || ':'
  || zz.as('U_DIR', $q$with x as (delete from public.staff_advances where id = 'adv_pre_1' returning id) select count(*)::text from x$q$) || ':'
  || zz.as('U_DIR', $q$with x as (delete from public.salary_payments where id = 'sp_pre_1' returning id) select count(*)::text from x$q$), '^2:1:1$');

-- ---------- (O) o'zaro hisob: ish haqidan farzandining o'quv to'lovi (naqdsiz) ----------
-- o'zaro hisob JSON'i: (kalit, xodim kodi, xodim havolasi, oy, summa, o'quvchi, ariza sanasi)
create or replace function zz.ofs(p_id text, p_tid text, p_ref text, p_month text, p_paid numeric, p_sid text, p_req text) returns text language sql as $$
  select (jsonb_build_object('id', p_id, 'teacherId', p_tid, 'payeeRef', p_ref, 'teacherName', 'Sinov', 'month', p_month, 'paid', p_paid, 'gross', 3000000,
                             'advance', 0, 'deduction', 0, 'subBonus', 0, 'net', 3000000, 'carryIn', 0, 'carryOut', 0, 'studentId', p_sid)
          || case when p_req is null then '{}'::jsonb else jsonb_build_object('requestDate', p_req) end)::text $$;
select zz.put('O_bal0', zz.bal());
select zz.put('O_rec0', (app.kassa_reconcile('2027-01-04', '2027-01-04') ->> 'total'));   -- o'zaro hisobdan oldingi holat (K0 dagi eski yozuv sanaladi)
select zz.chk('O0 o''zaro hisob: faqat Direktor (Moliya menejeri, kassir — yo''q)',
  zz.rpc('U_FM', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1000, 'T-2', '2027-01-03')) || ' | ' ||
  zz.rpc('U_KAS', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1000, 'T-2', '2027-01-03')), '^ERR 42501.* \| ERR 42501');
select zz.chk('O0b ariza sanasisiz / kelajakdagi sana bilan — rad; noma''lum o''quvchi — rad; noto''g''ri kalit — rad',
  zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1000, 'T-2', null)) || ' | ' ||
  zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1000, 'T-2', '2027-01-05')) || ' | ' ||
  zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1000, 'T-404', '2027-01-03')) || ' | ' ||
  zz.rpc('U_DIR', 'kassa_offset', zz.ofs('xx_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1000, 'T-2', '2027-01-03')),
  '^ERR 22023 \[kassa:basis\].* \| ERR 22023 \[kassa:basis\].* \| ERR 22023 \[kassa:party\].* \| ERR 22023 \[kassa:bad_input\]');
select zz.put('O1', zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1300000, 's2', '2027-01-03')));
select zz.chk('O1 o''zaro hisob 1 300 000: javobda dalolatnoma (ACT), o''quvchi kaliti kanonik (T-2)',
  (zz.js(zz.get('O1')) ->> 'ok') || ':' || (zz.js(zz.get('O1')) ->> 'method') || ':' || (zz.js(zz.get('O1')) -> 'kassa' ->> 'form') || ':' || (zz.js(zz.get('O1')) -> 'kassa' ->> 'status')
    || ':' || (zz.js(zz.get('O1')) -> 'kassa' ->> 'day') || ':' || (zz.js(zz.get('O1')) -> 'student' ->> 'id'), '^true:offset:ACT:posted:2027-01-04:T-2$');
select zz.put('O1d', (select jsonb_build_object('id', c.id)::text from public.cash_docs c where c.op = 'nc_offset'));
select zz.chk('O1a dalolatnoma: naqdsiz, Dt 6710 Kt 4010 (joriy oy fakturasi) / Kt 6310 (kelgusi oy), xodim — tomon, Direktor tasdig''i, kassa kunisiz',
  (select c.form || ':' || c.status || ':' || c."partyType" || ':' || c."partyId" || ':' || c."partyName" || ':' || c."sourceTable" || ':' || c."sourceId" || ':' || c."dirApprovedBy"
          || ':' || coalesce(c."dayId", 'kunsiz') || ':' || c.series || '-' || c.no || '=' || (select max(x.no) from public.cash_docs x where x.series = 'OFS') || ' / ' || zz.lines(c.id)
          || ' / ' || (select bool_or(l.cash)::text from public.cash_doc_lines l where l."docId" = c.id)
     from public.cash_docs c where c.id = zz.id('O1d')),
  '^ACT:posted:employee:teachers:tch1:Sinov O''qituvchi:salary_payments:sp_ofs_0001:U_DIR:kunsiz:OFS-(\d+)=\1 / 6710>4010=1000000@IN-01, 6710>6310=300000@IN-01 / false$');
select zz.chk('O1b maosh to''lovi: usul «offset», dalolatnoma havolasi, sana — bugun',
  (select method || ':' || ("cashDocId" = zz.id('O1d')) || ':' || date || ':' || trim_scale(paid) || ':' || "byUid" from public.salary_payments where id = 'sp_ofs_0001'), '^offset:true:2027-01-04:1300000:U_DIR$');
select zz.chk('O1c o''quv to''lovi: provider «offset», qo''llangan, dalolatnoma havolasi; fakturalar: 2027-01 to''liq, 2027-03 — 300 000; avans 0',
  (select provider || ':' || status || ':' || trim_scale(amount) || ':' || ("cashDocId" = zz.id('O1d')) || ':' || "studentId" || ':' || (raw -> 'offset' ->> 'salaryPaymentId') from public.payments where provider = 'offset')
  || ' / ' || (select string_agg(id || '=' || status || ':' || trim_scale("paidAmount"), ',' order by id) from public.invoices where "studentId" = 'T-2')
  || ' / ' || coalesce((select trim_scale(credit)::text from public.student_credit where id = 'T-2'), '0'),
  '^offset:applied:1300000:true:T-2:sp_ofs_0001 / oa=paid:1000000,ob=partial:300000 / 0$');
select zz.chk('O1d taqsimot jadvali: ikki qator (4010 va 6310), dalolatnomaga bog''langan',
  (select string_agg(account || '=' || trim_scale("fromCash") || '/' || coalesce(month, '-'), ',' order by account) from public.payment_allocations where "docId" = zz.id('O1d')),
  '^4010=1000000/2027-01,6310=300000/2027-03$');
select zz.chk('O1e kassa qoldig''i o''zgarmadi; kassa kitobida (kun hujjatlarida) dalolatnoma yo''q',
  (zz.bal() = zz.get('O_bal0'))::text || ':' || (select count(*) from jsonb_array_elements(zz.js(zz.as('U_FM', $q$select public.kassa_day_book('main', '2027-01-04')::text$q$)) -> 'docs') d where d ->> 'op' = 'nc_offset'), '^true:0$');
select zz.chk('O2 qayta yuborish — takror: yangi yozuv ham, yangi dalolatnoma ham yo''q',
  (zz.js(zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1300000, 's2', '2027-01-03'))) ->> 'dup') || ':' ||
  (select count(*) from public.cash_docs where op = 'nc_offset') || ':' || (select count(*) from public.payments where provider = 'offset') || ':' ||
  (select trim_scale("paidAmount") from public.invoices where id = 'ob'), '^true:1:1:300000$');
select zz.chk('O2b o''sha kalit, boshqa summa — rad', zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 999, 's2', '2027-01-03')), '^ERR 22023 \[kassa:ref_mismatch\]');
select zz.chk('O2c state-9: o''sha kalit va summa, lekin boshqa o''quvchi yoki boshqa ariza sanasi — rad (eski dalolatnoma jim qaytmaydi)',
  zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1300000, 's1', '2027-01-03')) || ' | '
  || zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1300000, 's2', '2027-01-02')),
  '^ERR 22023 \[kassa:ref_mismatch\].* \| ERR 22023 \[kassa:ref_mismatch\]');
select zz.chk('O3 tasdiqlangan vedomostdan ortiq — rad (qolgan 600 000); atomar — to''lov ham, dalolatnoma ham yozilmadi',
  zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0002', 'IQT-T1', 'teachers:tch1', '2026-12', 600001, 'T-2', '2027-01-03')) || ' / ' ||
  (select count(*) from public.payments where provider = 'offset') || ':' || (select count(*) from public.cash_docs where op = 'nc_offset') || ':' || (select trim_scale("paidAmount") from public.invoices where id = 'ob'),
  '^ERR 23514 .*berish mumkin: 600000.* / 1:1:300000$');
select zz.chk('O4 moslik: dalolatnoma ↔ maosh to''lovi ↔ o''quv to''lovi — toza (umumiy son o''zgarmadi)',
  zz.as('U_FM', $q$select (c -> 'reconcile' -> 'p5' ->> 'ofs') || ':' || (c -> 'reconcile' ->> 'total') from public.kassa_checks('main') c$q$) || '=' || zz.get('O_rec0'), '^0:(\d+)=\1$');
select zz.chk('O5 «tushgan to''lovlar» hisobotida alohida usul bilan ko''rinadi (naqd emas)',
  (select string_agg(provider || '=' || trim_scale(amount), ',' order by provider) from app.fin_receipts('2027-01-04', '2027-01-04') where provider = 'offset'), '^offset=1300000$');
select zz.chk('O6 to''g''ridan-to''g''ri «offset» maosh yozuvi — rad (faqat funksiya orqali)',
  zz.as('U_DIR', $q$with x as (insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date, method) values ('sp_dir_ofs','IQT-T1','teachers:tch1','Sinov','2026-12',1000,'2027-01-04','offset') returning id) select id from x$q$), '^ERR 42501 \[kassa:cash_only_kassa\]');
select zz.chk('O6b bog''langan maosh qatorini mijoz o''chira olmaydi; dalolatnoma oddiy «bekor qilish» orqali bekor qilinmaydi',
  zz.as('U_DIR', $q$with x as (delete from public.salary_payments where id = 'sp_ofs_0001' returning id) select count(*)::text from x$q$) || ' | ' || zz.void('U_DIR', zz.id('O1d'), 'Sinov uchun bekor'),
  '^ERR 42501 \[kassa:linked_row\].* \| ERR P0001 \[kassa:bad_status\]');
select zz.chk('O7 bekor qilish: Moliya menejeri — yo''q; sababsiz — yo''q',
  zz.as('U_FM', format('select public.kassa_offset_void(%L, %L)::text', zz.id('O1d'), 'Xato o''quvchi tanlangan')) || ' | ' ||
  zz.as('U_DIR', format('select public.kassa_offset_void(%L, %L)::text', zz.id('O1d'), 'x')), '^ERR 42501.* \| ERR 22023 \[kassa:reason\]');
select zz.put('O8', zz.as('U_DIR', format('select public.kassa_offset_void(%L, %L)::text', zz.id('O1d'), 'Xato o''quvchi tanlangan')));
select zz.chk('O8 Direktor shu kuni bekor qildi: dalolatnoma raqami saqlandi, maosh to''lovi olib tashlandi, o''quv to''lovi bekor, fakturalar va avans avvalgidek',
  (zz.js(zz.get('O8')) ->> 'status') || ':' || ((zz.js(zz.get('O8')) ->> 'no') is not null) || ':' || (zz.js(zz.get('O8')) ->> 'voidedBy')
  || ' / ' || (select count(*) from public.salary_payments where id = 'sp_ofs_0001')
  || ' / ' || (select status from public.payments where provider = 'offset')
  || ' / ' || (select string_agg(id || '=' || status || ':' || coalesce(trim_scale("paidAmount")::text, 'null'), ',' order by id) from public.invoices where "studentId" = 'T-2')
  || ' / ' || coalesce((select trim_scale(credit)::text from public.student_credit where id = 'T-2'), '0'),
  '^void:true:U_DIR / 0 / canceled / oa=pending:0,ob=pending:0 / 0$');
select zz.chk('O8b qayta bekor qilish — takror; ota-onaga hali yuborilmagan to''lov xabarnomasi to''xtatildi',
  (zz.js(zz.as('U_DIR', format('select public.kassa_offset_void(%L, %L)::text', zz.id('O1d'), 'Xato o''quvchi tanlangan'))) ->> 'dup') || ':' ||
  coalesce((select status from public.notify_queue where id = 'pay__' || (select id from public.payments where provider = 'offset')), 'yo''q'), '^true:(skipped|yo''q)$');
select zz.put('O9', zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0003', 'IQT-T1', 'teachers:tch1', '2026-12', 500000, 'T-3', '2027-01-04')));
select zz.chk('O9 fakturasi yo''q o''quvchi: butun summa avansga (Kt 6310); vedomost chegarasi bekor qilingandan keyin tiklangan',
  (zz.js(zz.get('O9')) -> 'kassa' ->> 'status') || ' / ' || zz.lines(zz.js(zz.get('O9')) -> 'kassa' ->> 'docId') || ' / ' || (select trim_scale(credit)::text from public.student_credit where id = 'T-3')
  || ' / ' || (select "sourceSnapshot" ->> 'allocation' from public.cash_docs where id = zz.js(zz.get('O9')) -> 'kassa' ->> 'docId'),
  '^posted / 6710>6310=500000@IN-01 / 500000 / exact$');
select zz.chk('O9b dalolatnomalar raqami uzluksiz (bekor qilingani raqamini saqlaydi)', jsonb_array_length(app.kassa_gap_check('main', 2027))::text, '^0$');
select zz.chk('O9c kassa qoldig''i o''zaro hisoblardan keyin ham o''zgarmadi', (zz.bal() = zz.get('O_bal0'))::text, '^true$');

-- ---------- Kechikkan qaytarish (CT-26) ----------
select zz.clock('2027-01-06 10:00+05');
select zz.chk('O10 o''zaro hisob ertasi kunlarda bekor qilinmaydi',
  zz.as('U_DIR', format('select public.kassa_offset_void(%L, %L)::text', zz.js(zz.get('O9')) -> 'kassa' ->> 'docId', 'Kechikkan bekor qilish')), '^ERR P0001 \[kassa:day_closed\]');
set local session_replication_role = replica;
delete from public.payments where provider = 'offset' and status = 'applied';
set local session_replication_role = origin;
select zz.chk('O11 moslik buzilishi ko''rinadi: o''zaro hisob to''lovi yozuvi yo''qolsa — P5 «ofs»',
  app.kassa_reconcile('2027-01-04', '2027-01-06') -> 'p5' ->> 'ofs', '^1$');
select zz.chk('R8 tasdiqlangan qaytarish 1 kundan ortiq berilmagan — ogohlantirish va nazorat ro''yxati',
  zz.as('U_KAS', $q$select s -> 'pending' ->> 'refundsLate' from public.kassa_state('main') s$q$) || ':' || zz.as('U_FM', $q$select c ->> 'staleRefunds' from public.kassa_checks('main') c$q$), '^1:1$');
select zz.chk('Z1 raqamlashda bo''shliq yo''q (bekor qilinganlar raqamini saqlaydi)', jsonb_array_length(app.kassa_gap_check('main', 2027))::text, '^0$');
select zz.chk('Z2 kun qoldig''i hujjatlardan: 5 000 000 − 1 000 000 − 450 000 − 250 000 − 200 000', zz.bal(), '^3100000$');

-- ---------- (Q) xodim qaytargan pul (acc-1): avans / maosh qaytimi KO-1 bilan SHU tranzaksiyada avans / maosh yozuviga tushadi ----------
--   04.01 kuni yopiladi (sanalgan = hisobdagi), 06.01 — yangi kun. Xodim st1 (IQX-T1): 2027-01 da karta avansi 50 000 (A4b) bor.
select zz.put('Q0', zz.as('U_KAS', $q$select public.kassa_day_close('{"day":"2027-01-04","counted":3100000}')::text$q$));
select zz.put('Q1', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_advance","amount":200000,"partyType":"employee","partyId":"staff:st1","basis":"Ariza, 06.01.2027","clientRef":"q1-000001"}'));
select zz.put('Q1p', left(zz.appr('U_FM', zz.id('Q1')), 0) || zz.pay('U_KAS', zz.id('Q1')));
select zz.chk('Q0 04.01 yopildi; 06.01: naqd avans 200 000 berildi (avans yozuvi 2027-01)',
  (zz.js(zz.get('Q0')) -> 'day' ->> 'status') || ':' || (zz.js(zz.get('Q1p')) ->> 'status') || ':' || (select trim_scale(amount) || ':' || month from public.staff_advances where "cashDocId" = zz.id('Q1')),
  '^closed:posted:200000:2027-01$');
select zz.chk('Q2 rad: oy tanlanmagan; naqd avans qoldig''idan katta (karta avansi 50 000 hisobga olinmaydi); Moliya menejeri kirim yozmaydi; boshqa statiya',
  zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":80000,"partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q3-000001"}') || ' | '
  || zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":200001,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q3-000001"}') || ' | '
  || zz.rpc('U_FM', 'kassa_receipt', '{"op":"in_staff_return","amount":80000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q3-000001"}') || ' | '
  || zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":80000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-22","basis":"Ortiqcha avans qaytdi","clientRef":"q3-000001"}') || ' | '
  || (select count(*) from public.cash_docs where op = 'in_staff_return'),
  '^ERR 22023 \[kassa:month\].* \| ERR P0001 \[kassa:staff_over\].*qoldiq 200000 so''m.* \| ERR 42501.* \| ERR 22023 \[kassa:article\].* \| 0$');
select zz.put('Q3', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":80000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q3-000001"}'));
select zz.chk('Q3 avans qaytdi: KO-1 № 1, Dt 5010 Kt 4210 (OP-08); avans yozuvi −80 000 shu order bilan (xodim kodi, oy, sana, usul)',
  (zz.js(zz.get('Q3')) ->> 'status') || ':' || (zz.js(zz.get('Q3')) ->> 'no') || ':' || zz.lines(zz.id('Q3')) || ' / '
  || (select "teacherId" || ':' || "payeeRef" || ':' || trim_scale(amount) || ':' || month || ':' || date || ':' || method || ':' || (note ~ 'KO-1 № 1') from public.staff_advances where "cashDocId" = zz.id('Q3')),
  '^posted:1:5010>4210=80000@OP-08 / IQX-T1:staff:st1:-80000:2027-01:2027-01-06:cash:true$');
select zz.chk('Q3b oylik hisobida avans sof: naqd 200 000 − 80 000 + karta 50 000 = 170 000; kassir oynasi: berilgan / qaytgan / qoldiq',
  trim_scale(app.payroll_adv('IQX-T1', '2027-01')) || ' | '
  || (select (j -> 'advance' ->> 'given') || '/' || (j -> 'advance' ->> 'returned') || '/' || (j -> 'advance' ->> 'open') || ':' || (j ->> 'locked')
        from (select zz.js(zz.as('U_KAS', $q$select public.kassa_staff_open('main', 'staff:st1', '2027-01')::text$q$)) as j) q),
  '^170000 \| 200000/80000/120000:false$');
select zz.chk('Q4 qayta yuborish — takror, ikkinchi yozuv yo''q; bog''langan manfiy qatorni mijoz o''chira olmaydi',
  (zz.js(zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":80000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q3-000001"}')) ->> 'dup')
  || ':' || (select count(*) from public.staff_advances where amount < 0) || ' | '
  || zz.as('U_DIR', $q$with x as (delete from public.staff_advances where amount < 0 returning id) select count(*)::text from x$q$),
  '^true:1 \| ERR 42501 \[kassa:linked_row\]');
select zz.chk('Q4b o''sha kalit, boshqa oy — rad', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":80000,"month":"2026-12","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q3-000001"}'),
  '^ERR 22023 \[kassa:ref_mismatch\]');
select zz.put('Q5', zz.as('U_FM', $q$select public.payroll_submit('2027-01', '[{"personType":"staff","personId":"IQX-T1","gross":2000000}]')::text$q$));
select zz.chk('Q5 yanvar vedomosti: avans BAZADAN sof 170 000 (qaytgan 80 000 ushlanmaydi)',
  (zz.js(zz.get('Q5')) ->> 'ok') || ' | ' || (select trim_scale(advance) || ':' || (payable = greatest(0, gross - advance - deduction + "subBonus" + "carryIn")) from public.payroll_lines where "runId" = '2027-01'),
  '^true \| 170000:true$');
select zz.put('Q6', zz.as('U_HR', $q$select public.payroll_decide('2027-01', true)::text$q$));
select zz.chk('Q6 vedomost tasdiqlandi: endi avans qaytimi rad («Ish haqi to''lovi» statiyasi yoki oyni qayta ochish); qaytimni bekor qilish ham rad',
  (zz.js(zz.get('Q6')) ->> 'status') || ' | '
  || zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":10000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q6-000001"}') || ' | '
  || zz.void('U_KAS', zz.id('Q3'), 'Xato kiritilgan qaytim'),
  '^approved \| ERR P0001 \[kassa:advance_locked\].*Ish haqi to''lovi.* \| ERR P0001 \[kassa:advance_locked\]');
select zz.put('Q7', zz.as('U_DIR', $q$select public.payroll_reopen('2027-01', 'Avans qaytimi xato')::text$q$) || ' | ' || zz.void('U_KAS', zz.id('Q3'), 'Xato kiritilgan qaytim'));
select zz.chk('Q7 Direktor oyni qayta ochdi — qaytim shu kuni bekor qilindi: manfiy avans yozuvi olib tashlandi, avans 250 000',
  (zz.js(split_part(zz.get('Q7'), ' | ', 1)) ->> 'status') || ':' || (zz.js(split_part(zz.get('Q7'), ' | ', 2)) ->> 'status') || ':'
  || (select count(*) from public.staff_advances where "cashDocId" = zz.id('Q3')) || ':' || trim_scale(app.payroll_adv('IQX-T1', '2027-01')),
  '^returned:void:0:250000$');
-- OP-09: o'qituvchi IQT-T1, dekabr — kassadan oldingi (usulsiz) 100 000 (K0) + naqd 1 000 000 (S1) + o'zaro hisob 500 000 (O9, naqd emas);
--   tasdiqlangan 3 000 000, qolgani 1 400 000
select zz.put('Qc0', app.salary_carry('IQT-T1', '2027-01')::text);
select zz.chk('Q8 maosh qaytimi naqd berilgan maoshdan (100 000 + 1 000 000; o''zaro hisob kirmaydi) katta — rad',
  zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":1100001,"month":"2026-12","partyType":"employee","partyId":"teachers:tch1","articleId":"OP-09","basis":"Ortiqcha maosh qaytdi","clientRef":"q9-000001"}'),
  '^ERR P0001 \[kassa:staff_over\].*berilgan 1100000 so''m');
select zz.put('Q9', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":300000,"month":"2026-12","partyType":"employee","partyId":"teachers:tch1","articleId":"OP-09","basis":"Ortiqcha maosh qaytdi","clientRef":"q9-000001"}'));
select zz.chk('Q9 maosh qaytdi: Dt 5010 Kt 6710 (OP-09); maosh yozuvi −300 000 (oy hisob qiymatlari o''zgarmagan), qoldiq hisobi +300 000',
  (zz.js(zz.get('Q9')) ->> 'status') || ':' || zz.lines(zz.id('Q9')) || ' / '
  || (select trim_scale(paid) || ':' || trim_scale(gross) || ':' || month || ':' || date || ':' || method || ':' || "payeeRef" from public.salary_payments where "cashDocId" = zz.id('Q9'))
  || ' / ' || (app.salary_carry('IQT-T1', '2027-01') - zz.get('Qc0')::numeric),
  '^posted:5010>6710=300000@OP-09 / -300000:3000000:2026-12:2027-01-06:cash:teachers:tch1 / 300000$');
select zz.chk('Q9b kassir oynasi: dekabr naqd maosh berilgan 1 100 000, qaytgan 300 000, sof 800 000; oy tasdiqlangan',
  (select (j -> 'salary' ->> 'paid') || '/' || (j -> 'salary' ->> 'returned') || '/' || (j -> 'salary' ->> 'net') || ':' || (j ->> 'locked')
     from (select zz.js(zz.as('U_KAS', $q$select public.kassa_staff_open('main', 'teachers:tch1', '2026-12')::text$q$)) as j) q), '^1100000/300000/800000:true$');
select zz.chk('Q10 darvoza qaytgan summani ko''radi: berish mumkin 1 700 000 (1 400 000 + qaytgan 300 000), undan ortiq — rad',
  zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_q10', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1700001)), '^ERR 23514 .*berish mumkin: 1700000');
select zz.put('Q10', zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_q10', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1700000)));
select zz.chk('Q10b qaytgan maosh qayta berildi — dekabr to''liq yopildi: qoldiq 0',
  (zz.js(zz.get('Q10')) -> 'kassa' ->> 'status') || ':' || trim_scale(app.salary_carry('IQT-T1', '2027-01')) || ':' || zz.get('Qc0'), '^posted:0:1400000$');
select zz.chk('Q11 qaytgan maosh qayta berilgan — qaytimni bekor qilish rad (tasdiqlangandan 300 000 ortiq bo''lardi)',
  zz.void('U_KAS', zz.id('Q9'), 'Xato kiritilgan qaytim'), '^ERR P0001 \[kassa:salary_repaid\].*300000 so''m ortiq');
select zz.put('Q12', (zz.js(zz.void('U_KAS', zz.js(zz.get('Q10')) -> 'kassa' ->> 'docId', 'Xato berilgan maosh')) ->> 'status') || ':'
  || (zz.js(zz.void('U_KAS', zz.id('Q9'), 'Xato kiritilgan qaytim')) ->> 'status'));
select zz.chk('Q12 avval keyingi maosh orderi, keyin qaytim bekor qilindi: ikkala yozuv olib tashlandi, qoldiq hisobi boshlang''ich holatda',
  zz.get('Q12') || ':' || (select count(*) from public.salary_payments where "cashDocId" in (zz.id('Q9'), zz.js(zz.get('Q10')) -> 'kassa' ->> 'docId'))
  || ':' || (app.salary_carry('IQT-T1', '2027-01') = zz.get('Qc0')::numeric), '^void:void:0:true$');
select zz.put('Q13', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":50000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Avans qaytdi","clientRef":"q13-00001"}'));
select zz.chk('Q13 moslik (P5 «ret»): xodim qaytargan pul orderlari ↔ manfiy yozuvlar — toza; kassa qoldig''i hujjatlardan',
  (zz.js(zz.get('Q13')) ->> 'status') || ':' || (app.kassa_reconcile('2027-01-04', '2027-01-06') -> 'p5' ->> 'ret') || ':' || (app.kassa_reconcile('2027-01-04', '2027-01-06') -> 'p5' ->> 'row')
  || ':' || zz.bal(), '^posted:0:0:2950000$');
savepoint q14;
set local session_replication_role = replica;
delete from public.staff_advances where "cashDocId" = zz.id('Q13');
insert into public.salary_payments (id, "teacherId", "payeeRef", month, paid, date, method) values ('spr_zz_1', 'IQT-T1', 'teachers:tch1', '2026-12', -1000, '2027-01-06', 'cash');
set local session_replication_role = origin;
select (app.kassa_reconcile('2027-01-04', '2027-01-06') -> 'p5' ->> 'ret') || ':' || (app.kassa_reconcile('2027-01-04', '2027-01-06') -> 'p5' ->> 'row') as q14 \gset
rollback to savepoint q14;
select zz.chk('Q14 moslik buzilishni topadi: yozuvsiz qaytim orderi va ordersiz manfiy maosh yozuvi — «ret» 2 (P5 «row» o''zgarmaydi)', :'q14', '^2:0$');
-- payroll-approval.sql (jonli fayl) darvozasi: manfiy yozuv faqat kassa funksiyasi bayrog'i bilan o'tadi; bayroqsiz — avvalgidek (2027-01 qayta ochilgan)
savepoint q15;
do $x$ begin
  begin
    insert into public.salary_payments (id, "teacherId", "payeeRef", month, paid, date, method) values ('spr_zz_2', 'IQX-T1', 'staff:st1', '2027-01', -1000, '2027-01-06', 'cash');
    perform zz.put('Q15a', 'ok');
  exception when others then perform zz.put('Q15a', 'ERR ' || sqlstate || ' ' || sqlerrm); end;
  perform set_config('iqror.kassa_rpc', '1', true);
  begin
    insert into public.salary_payments (id, "teacherId", "payeeRef", month, paid, date, method) values ('spr_zz_3', 'IQX-T1', 'staff:st1', '2027-01', -1000, '2027-01-06', 'cash');
    perform zz.put('Q15b', 'ok');
  exception when others then perform zz.put('Q15b', 'ERR ' || sqlstate || ' ' || sqlerrm); end;
  perform set_config('iqror.kassa_rpc', '', true);
end $x$;
select zz.get('Q15a') || ' | ' || zz.get('Q15b') as q15 \gset
rollback to savepoint q15;
select zz.chk('Q15 maosh darvozasi: bayroqsiz manfiy yozuv — avvalgidek tekshiriladi (oy tasdiqlanmagan — rad); kassa bayrog''i bilan — o''tadi',
  :'q15', '^ERR 23514 .*tasdiqlanmagan \| ok$');
-- Avans / maosh orderining o'zi qaytimdan oldin bekor qilinmaydi (g1, 2-davra): aks holda oy avansi / berilgan maosh manfiy bo'lib
--   qolardi (vedomost avans o'rniga maoshga qo'shardi, darvoza chegarasi tasdiqlangandan oshardi) — avval qaytim, keyin order.
select zz.put('Q16', zz.void('U_KAS', zz.id('Q1'), 'Xato berilgan avans'));
select zz.put('Q16b', (zz.js(zz.void('U_KAS', zz.id('Q13'), 'Xato kiritilgan qaytim')) ->> 'status') || ':' || (zz.js(zz.void('U_KAS', zz.id('Q1'), 'Xato berilgan avans')) ->> 'status'));
select zz.chk('Q16 avans orderi (200 000), undan qaytim (50 000) bor — bekor qilish rad (oy naqd avansi −50 000 bo''lardi); avval qaytim, keyin avans — ikkalasi bekor, yozuvlar olib tashlandi, oy avansi faqat karta 50 000',
  zz.get('Q16') || ' | ' || zz.get('Q16b') || ':' || (select count(*) from public.staff_advances where "cashDocId" in (zz.id('Q1'), zz.id('Q13')))
  || ':' || trim_scale(app.payroll_adv('IQX-T1', '2027-01')) || ':' || zz.bal(),
  '^ERR P0001 \[kassa:staff_returned\].*2027-01 oy naqd avansi manfiy.*\(-50000 so''m\).*qaytim orderini bekor qiling \| void:void:0:50000:3100000$');
select zz.put('Q17', zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_q17', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 200000)));
select zz.put('Q17r', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":1200000,"month":"2026-12","partyType":"employee","partyId":"teachers:tch1","articleId":"OP-09","basis":"Ortiqcha maosh qaytdi","clientRef":"q17-00001"}'));
select zz.put('Q17v', zz.void('U_KAS', zz.js(zz.get('Q17')) -> 'kassa' ->> 'docId', 'Xato berilgan maosh'));
select zz.put('Q17b', (zz.js(zz.void('U_KAS', zz.id('Q17r'), 'Xato kiritilgan qaytim')) ->> 'status') || ':'
  || (zz.js(zz.void('U_KAS', zz.js(zz.get('Q17')) -> 'kassa' ->> 'docId', 'Xato berilgan maosh')) ->> 'status'));
select zz.chk('Q17 dekabr: naqd maosh 200 000 va qaytim 1 200 000 (naqd berilgan 1 300 000 dan) — maosh orderini bekor qilish rad (sof berilgan −100 000 bo''lardi); avval qaytim, keyin maosh — ikkalasi bekor, qoldiq hisobi boshlang''ich holatda',
  (zz.js(zz.get('Q17')) -> 'kassa' ->> 'status') || ':' || (zz.js(zz.get('Q17r')) ->> 'status') || ' | ' || zz.get('Q17v') || ' | ' || zz.get('Q17b') || ':'
  || (select count(*) from public.salary_payments where "cashDocId" in (zz.id('Q17r'), zz.js(zz.get('Q17')) -> 'kassa' ->> 'docId'))
  || ':' || (app.salary_carry('IQT-T1', '2027-01') = zz.get('Qc0')::numeric) || ':' || zz.bal(),
  '^posted:posted \| ERR P0001 \[kassa:staff_returned\].*2026-12 oy uchun naqd berilgan maosh manfiy.*\(-100000 so''m\).*qaytim orderini bekor qiling \| void:void:0:true:3100000$');

-- g8 (acc-1 qoldig'i): kassaga qaytim yozilgan oyning ESKI (kassa hujjatisiz) naqd avans / maosh qatorini o'chirish yoki summasini kamaytirish,
--   usulini o'zgartirish oy sof summasini manfiy qilsa — rad (kassa holatidan qat'i nazar); manfiy bo'lmasa va qaytimsiz oyda — avvalgidek.
--   Savepoint ichida (natija psql o'zgaruvchisida) — keyingi tekshiruvlar qoldig'iga ta'sir qilmasin.
savepoint q18;
set local session_replication_role = replica;
insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date) values
  ('adv_leg_g8', 'IQX-T1', 'staff:st1', 'Sinov', 120000, '2027-01', '2027-01-02'), ('adv_leg_g8b', 'IQX-T1', 'staff:st1', 'Sinov', 5000, '2026-11', '2026-11-20');
insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, paid, date) values
  ('sp_leg_g8', 'IQT-T1', 'teachers:tch1', 'Sinov', '2027-01', 150000, '2027-01-02');
set local session_replication_role = origin;
select (zz.js(zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":100000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Avans qaytdi","clientRef":"q18-00001"}')) ->> 'status') || ':'
  || (zz.js(zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":100000,"month":"2027-01","partyType":"employee","partyId":"teachers:tch1","articleId":"OP-09","basis":"Maosh qaytdi","clientRef":"q18-00002"}')) ->> 'status') as q18a \gset
select zz.as('U_DIR', $q$with x as (delete from public.staff_advances where id = 'adv_leg_g8' returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (update public.staff_advances set amount = 90000 where id = 'adv_leg_g8' returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (update public.staff_advances set method = 'card' where id = 'adv_leg_g8' returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (delete from public.salary_payments where id = 'sp_leg_g8' returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (update public.staff_advances set amount = 110000 where id = 'adv_leg_g8' returning amount) select trim_scale(amount)::text from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (delete from public.staff_advances where id = 'adv_leg_g8b' returning id) select id from x$q$) as q18 \gset
-- (yig'indi alohida so'rov bilan: yuqoridagi so'rov o'z boshidagi holatni ko'radi)
select :'q18' || ' | ' || (select trim_scale(sum(amount))::text from public.staff_advances where "teacherId" = 'IQX-T1' and month = '2027-01' and coalesce(method, '') in ('', 'cash'))
  || ':' || (select trim_scale(sum(paid))::text from public.salary_payments where "teacherId" = 'IQT-T1' and month = '2027-01' and coalesce(method, '') in ('', 'cash')) as q18 \gset
rollback to savepoint q18;
select zz.chk('Q18 g8: qaytim yozilgan oy (avans 120 000 − 100 000, maosh 150 000 − 100 000) — eski naqd qatorni o''chirish, summasini 90 000 ga tushirish, kartaga o''tkazish — rad (kassa:staff_returned); 110 000 ga — mumkin; qaytimsiz oy qatori — o''chiriladi',
  :'q18a' || ' | ' || :'q18',
  '^posted:posted \| ERR 42501 \[kassa:staff_returned\] Bu xodimning 2027-01 oy naqd avansidan kassaga qaytim yozilgan.*\(-100000 so''m\).* \| ERR 42501 \[kassa:staff_returned\].*\(-10000 so''m\).* \| ERR 42501 \[kassa:staff_returned\].* \| ERR 42501 \[kassa:staff_returned\] Bu xodimning 2027-01 oy naqd maoshidan.* \| 110000 \| adv_leg_g8b \| 10000:50000$');
-- ---------- Ko'rik 2-guruhi: o'quvchi puli, eski «Buxgalteriya» nusxasi (acc-9, acc-2, crit-2, ui-3, acc-7) ----------
--   06.01 kuni ochiq (qoldiq 3 100 000). Yangi o'quvchilar: T-4 / T-5 — egizaklar (50 000 avans + to'lanmagan 100 000 lik 2027-01 fakturasi),
--   T-6 — fakturasiz, avansi 300 000 (ketgan o'quvchi), T-7 — to'langan faktura + 100 000 avans, T-8 / T-9 — oy chegarasi uchun.
create or replace function zz.lk(p_doc text) returns text language sql as $$
  select string_agg(l.debit || '>' || l.credit || '=' || trim_scale(l.amount) || coalesce('#' || (l.analytics ->> 'kind'), ''), ', ' order by l."lineNo")
    from public.cash_doc_lines l where l."docId" = p_doc $$;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s4','T-4','Sinov D',5,'A','uz','',4,'[]'), ('s5','T-5','Sinov E',5,'A','uz','',5,'[]'), ('s6','T-6','Sinov F',5,'A','uz','',6,'[]'),
  ('s7','T-7','Sinov G',5,'A','uz','',7,'[]'), ('s8','T-8','Sinov H',5,'A','uz','',8,'[]'), ('s9','T-9','Sinov I',5,'A','uz','',9,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('ic4','T-4','Sinov D','2027-01',100000,0,'pending'), ('ic5','T-5','Sinov E','2027-01',100000,0,'pending'),
  ('ik7','T-7','Sinov G','2027-01',400000,400000,'paid'),
  ('r8a','T-8','Sinov H','2027-01',300000,300000,'paid'), ('r8b','T-8','Sinov H','2027-02',300000,300000,'paid'), ('r8c','T-8','Sinov H','2027-03',300000,300000,'paid'),
  ('r9b','T-9','Sinov I','2027-02',300000,300000,'paid');
insert into public.student_credit (id, "studentId", credit) values ('T-4','T-4',50000), ('T-5','T-5',50000), ('T-6','T-6',300000), ('T-7','T-7',100000);
insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw) values
  ('pu2', '', 'bank', 70000, 'unmatched', 'Noma''lum To''lovchi 2', false, '{}');
set local session_replication_role = origin;

-- (E5) acc-9: xaritada yo'q statiyalar «Buxgalteriya»ga ham ko'chadi (eski ro'yxat — barcha naqd chiqimlar); asosiy vosita — «Inventar»,
--   sotish uchun tovar va yetkazib beruvchi — «Boshqa», izoh statiya nomi bilan boshlanadi; xaritadagi statiya — avvalgidek
select zz.put('E5', zz.rpc('U_KAS', 'kassa_payout_request', format('{"op":"out_expense","amount":400000,"partyType":"counterparty","partyId":"%s","basis":"Hisob-faktura № 9","clientRef":"e5-000001","lines":[{"articleId":"OP-24","amount":150000},{"articleId":"OP-18","amount":120000},{"articleId":"OP-17","amount":80000},{"articleId":"EX-32","amount":50000}]}', zz.id('cp'))));
select zz.put('E5p', left(zz.appr('U_FM', zz.id('E5')), 0) || zz.pay('U_KAS', zz.id('E5')));
select zz.chk('E5 acc-9: KO-2 qatorlari (OP-24, OP-18, OP-17, EX-32) — hammasi ko''chdi: Boshqa / Inventar / Boshqa / Kanselyariya; moslik P4 toza',
  (zz.js(zz.get('E5p')) ->> 'status') || ' / '
  || (select string_agg(category || '=' || trim_scale(amount) || '@' || "articleId", ', ' order by id) from public.expenses where "cashDocId" = zz.id('E5'))
  || ' / ' || (app.kassa_reconcile('2027-01-06', '2027-01-06') -> 'p4' ->> 'doc'),
  '^posted / Boshqa=150000@OP-24, Inventar=120000@OP-18, Boshqa=80000@OP-17, Kanselyariya=50000@EX-32 / 0$');
select zz.chk('E5b izoh: xaritadan olinmagan toifada statiya nomi bilan boshlanadi (Direktor «Boshqa» ichida nima ekanini ko''radi)',
  (select string_agg(note, ' | ' order by id) from public.expenses where "cashDocId" = zz.id('E5')),
  '^Sotish uchun tovar xaridi: Sinov Ta''minot MChJ — Hisob-faktura № 9 \(KO-2 № \d+\) \| Asosiy vosita, nomoddiy aktiv, ijaradagi binoga qo‘yilma: Sinov Ta''minot MChJ — Hisob-faktura № 9 \(KO-2 № \d+\) \| Yetkazib beruvchilar bilan hisob-kitob: Sinov Ta''minot MChJ — Hisob-faktura № 9 \(KO-2 № \d+\) \| Sinov Ta''minot MChJ — Hisob-faktura № 9 \(KO-2 № \d+\)$');

-- (OC) acc-2: o'zaro hisobda o'quvchining eski avansi fakturaga qo'llansa — dalolatnomada ham naqd KO-1 dagi kabi naqdsiz Dt 6310 Kt 4010
--   (ma'lumot qatori, summaga kirmaydi). Egizak: T-4 — o'zaro hisob 100 000, T-5 — naqd 100 000 (KO-1); natija bir xil bo'lishi kerak.
select zz.put('OC1', zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0004', 'IQT-T1', 'teachers:tch1', '2026-12', 100000, 'T-4', '2027-01-06')));
select zz.put('OC2', zz.as('U_KAS', $q$select public.record_manual_payment('man_oc5_0001', 'T-5', 100000, 'cash', null, '', '', 'Sinov Ota', null, '{"fiscalNo":"F-OC5"}'::jsonb)::text$q$));
select zz.put('OCd', (select jsonb_build_object('id', c.id)::text from public.cash_docs c where c."sourceId" = 'sp_ofs_0004'));
select zz.put('OCk', (select jsonb_build_object('id', c.id)::text from public.cash_docs c where c."sourceId" = 'man_oc5_0001'));
select zz.chk('OC1 dalolatnoma qatorlari: Dt 6710 Kt 4010 50 000, naqdsiz Dt 6310 Kt 4010 50 000 (avans qo''llandi), Dt 6710 Kt 6310 50 000; summa 100 000',
  (zz.js(zz.get('OC1')) -> 'kassa' ->> 'status') || ' / ' || zz.lk(zz.id('OCd')) || ' / ' || (select trim_scale(amount) from public.cash_docs where id = zz.id('OCd')),
  '^posted / 6710>4010=50000, 6310>4010=50000#credit_applied, 6710>6310=50000#overpay / 100000$');
select zz.chk('OC2 naqd KO-1 (egizak) bilan AYNAN bir xil qatorlar (5010 o''rnida 6710)',
  zz.lk(zz.id('OCk')) || ' = ' || replace(zz.lk(zz.id('OCk')), '5010>', '6710>') || ' | ' || zz.lk(zz.id('OCd')),
  '^5010>4010=50000, 6310>4010=50000#credit_applied, 5010>6310=50000#overpay = (.*) \| \1$');
select zz.chk('OC3 sof ta''sir: Kt 4010 jami 100 000 (qarz to''liq yopildi), 6310 sof 0 (avans o''zgarmadi), Dt 6710 100 000; faktura va avans — KO-1 egizagi bilan bir xil',
  (select trim_scale(coalesce(sum(amount) filter (where credit = '4010'), 0)) || ':' || trim_scale(coalesce(sum(amount) filter (where credit = '6310'), 0) - coalesce(sum(amount) filter (where debit = '6310'), 0))
          || ':' || trim_scale(coalesce(sum(amount) filter (where debit = '6710'), 0)) from public.cash_doc_lines where "docId" = zz.id('OCd'))
  || ' / ' || (select string_agg(i.id || '=' || i.status || ':' || trim_scale(i."paidAmount") || ':' || trim_scale(c.credit), ',' order by i.id)
                 from public.invoices i join public.student_credit c on c.id = i."studentId" where i.id in ('ic4', 'ic5')),
  '^100000:0:100000 / ic4=paid:100000:50000,ic5=paid:100000:50000$');
select zz.chk('OC4 taqsimot jadvali o''zgarmagan (4010: naqd 50 000 + avans 50 000; 6310: 50 000); dalolatnoma summasi — ma''lumot qatorisiz (kassa-checks 16-band qoidasi); moslik P5 «ofs» toza',
  (select string_agg(account || '=' || trim_scale("fromCash") || '/' || trim_scale("fromCredit"), ',' order by account) from public.payment_allocations where "docId" = zz.id('OCd'))
  || ' | ' || (select trim_scale(sum(amount) filter (where analytics ->> 'kind' is distinct from 'credit_applied')) from public.cash_doc_lines where "docId" = zz.id('OCd'))
  || ' | ' || (app.kassa_reconcile('2027-01-06', '2027-01-06') -> 'p5' ->> 'ofs'),
  '^4010=50000/50000,6310=50000/0 \| 100000 \| 0$');
select zz.put('OC5', zz.as('U_DIR', format('select public.kassa_offset_void(%L, %L)::text', zz.id('OCd'), 'Sinov: bekor qilish')));
select zz.chk('OC5 shu kunda bekor qilish (ma''lumot qatori bilan ham): faktura va avans to''lovdan oldingi holatga',
  (zz.js(zz.get('OC5')) ->> 'status') || ' / ' || (select status || ':' || coalesce(trim_scale("paidAmount")::text, 'null') from public.invoices where id = 'ic4')
  || ' / ' || (select trim_scale(credit) from public.student_credit where id = 'T-4'), '^void / pending:0 / 50000$');

-- (RC) crit-2: o'quvchi avansini naqd qaytarish — Direktor so'rovi (= tasdiq), pul kassadan; avans pul berilganda kamayadi
select zz.chk('RC0 rad: Moliya menejeri; avansdan katta summa; avansi yo''q o''quvchi; noma''lum maqsad',
  zz.rpc('U_FM', 'kassa_refund_request', '{"target":"credit","id":"T-6","amount":100000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc0_000001"}') || ' | '
  || zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"T-6","amount":300001,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc0_000002"}') || ' | '
  || zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"T-2","amount":1000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc0_000003"}') || ' | '
  || zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"avans","id":"T-6","amount":1000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc0_000004"}'),
  '^ERR 42501.* \| ERR 22023 \[kassa:credit_over\].*avansi 300000 so''m \| ERR 22023 \[kassa:credit_none\].*avans yo''q \| ERR 22023 \[kassa:bad_input\]');
select zz.put('RC1', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"s6","amount":200000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","requestDate":"2027-01-05","clientRef":"rf_rc1_000001"}'));
select zz.chk('RC1 so''rov: tasdiqlangan, raqamsiz; bitta qator Dt 6310 Kt 5010 (OP-15, avans qaytarish); o''quvchi kaliti kanonik; asos',
  (zz.js(zz.get('RC1')) ->> 'status') || ':' || zz.jd(zz.get('RC1'), 'no', '-') || ':' || trim_scale((zz.js(zz.get('RC1')) ->> 'amount')::numeric) || ':'
  || (zz.js(zz.get('RC1')) ->> 'partyType') || ':' || (zz.js(zz.get('RC1')) ->> 'partyId') || ':' || (zz.js(zz.get('RC1')) ->> 'dirApprovedBy') || ':' || (zz.js(zz.get('RC1')) -> 'sourceSnapshot' ->> 'target')
  || ' / ' || zz.lines(zz.id('RC1')) || ' ' || zz.lk(zz.id('RC1')) || ' / ' || (zz.js(zz.get('RC1')) ->> 'basis'),
  '^approved:-:200000:student:T-6:U_DIR:credit / 6310>5010=200000@OP-15 6310>5010=200000#credit_refund / Qaytarish: o‘quvchi avansi — O''quvchi ketdi; ariza 05\.01\.2027$');
-- (state-9: qayta yuborish — o'sha mazmun bilan; ariza sanasisiz yoki boshqa oluvchi bilan — eski so'rov jim qaytmaydi, kassa:ref_mismatch)
select zz.chk('RC1b so''rov paytida avans o''zgarmaydi; qayta yuborish (o''sha kalit va mazmun, o''quvchi kodi bilan) — o''sha so''rov (dup); ariza sanasisiz yoki boshqa oluvchi bilan — rad',
  (select trim_scale(credit)::text from public.student_credit where id = 'T-6') || ':' || (select count(*) from public.refunds where "studentId" = 'T-6') || ' | '
  || (zz.js(zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"T-6","amount":200000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","requestDate":"2027-01-05","clientRef":"rf_rc1_000001"}')) ->> 'dup')
  || ':' || (select count(*) from public.cash_docs where op = 'out_refund' and "sourceSnapshot" ->> 'target' = 'credit') || ' | '
  || zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"T-6","amount":200000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc1_000001"}') || ' | '
  || zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"T-6","amount":200000,"reason":"O''quvchi ketdi","payee":"Boshqa Oluvchi Ismi","requestDate":"2027-01-05","clientRef":"rf_rc1_000001"}'),
  '^300000:0 \| true:1 \| ERR 22023 \[kassa:ref_mismatch\].* \| ERR 22023 \[kassa:ref_mismatch\]');
select zz.chk('RC2 ui-3: shu avans bo''yicha kutilayotgan so''rov (200 000) bilan jami avansdan oshsa — rad; ichida bo''lsa — o''tadi',
  zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"T-6","amount":150000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc2_000001"}') || ' | '
  || (zz.js(zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"T-6","amount":100000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc2_000002"}')) ->> 'status'),
  '^ERR 22023 \[kassa:refund_pending\].*\(200000 so''m\).*avansdan \(300000 so''m\).* \| approved$');
select zz.put('RC2c', zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', (select id from public.cash_docs where "clientRef" = 'ref_rf_rc2_000002'), 'Ikkinchi so''rov kerak emas')));
select zz.put('RC3b', zz.bal());
-- g11 (sec-1): qaytarishni so'ragan (= tasdiqlagan) Direktor uning pulini o'zi bermaydi — kassir beradi (yagona tasdiq va pul berish bir
--   odamda bo'lmasin; reja §4.11, yo'riqnoma §3)
select zz.put('RC2d', zz.pay('U_DIR', zz.id('RC1')));
select zz.chk('RC2d g11 (sec-1): qaytarishni so''ragan (= tasdiqlagan) Direktor pulini o''zi bera olmaydi (kassa:self_pay); so''rov, avans va kassa o''zgarmadi',
  zz.get('RC2d') || ' | ' || (select status || ':' || coalesce(no::text, '-') from public.cash_docs where id = zz.id('RC1')) || ':' || (select trim_scale(credit)::text from public.student_credit where id = 'T-6')
  || ':' || (zz.bal() = zz.get('RC3b'))::text,
  '^ERR 42501 \[kassa:self_pay\] Bu qaytarishni \(so''rovni\) o''zingiz tasdiqlagansiz va boshqa tasdiq yo''q — pulini o''zingiz bera olmaysiz: pulni kassir beradi \| approved:-:300000:true$');
select zz.put('RC3', zz.pay('U_KAS', zz.id('RC1')));
select zz.chk('RC3 kassir pulni berdi: KO-2 o''tkazildi; avans 300 000 → 100 000; kassa qoldig''i −200 000',
  (zz.js(zz.get('RC3')) ->> 'status') || ':' || (zz.js(zz.get('RC3')) ->> 'postedBy') || ' / ' || (select trim_scale(credit)::text from public.student_credit where id = 'T-6')
  || ' / ' || (zz.get('RC3b')::numeric - zz.bal()::numeric), '^posted:U_KAS / 100000 / 200000$');
select zz.chk('RC3b avans jurnali (−200 000, qoldiq 100 000, naqd) va qaytarish jurnali (target credit, naqd, order havolasi, «kim» — kassir)',
  (select trim_scale(delta) || ':' || trim_scale("balanceAfter") || ':' || reason || ':' || provider || ':' || (note ~ '^Avans naqd qaytarildi \(KO-2 № \d+\): O''quvchi ketdi$') from public.credit_ledger where "studentId" = 'T-6')
  || ' / ' || (select target || ':' || "targetId" || ':' || trim_scale(amount) || ':' || method || ':' || ("cashDocId" = zz.id('RC1')) || ':' || "byUid" from public.refunds where "studentId" = 'T-6'),
  '^-200000:100000:manual:cash:true / credit:T-6:200000:cash:true:U_KAS$');
select zz.chk('RC4 moslik P8 (qaytarish yozuvi ↔ KO-2) toza; qaytarish orderi bekor qilinmaydi; qayta chaqiruv — takror',
  (app.kassa_reconcile('2027-01-06', '2027-01-06') -> 'p8')::text || ' | ' || zz.void('U_DIR', zz.id('RC1'), 'Sinov uchun bekor') || ' | '
  || (zz.js(zz.pay('U_KAS', zz.id('RC1'))) ->> 'dup') || ':' || (select count(*) from public.refunds where "studentId" = 'T-6'),
  '^\{"doc": 0, "row": 0\} \| ERR 42501 \[kassa:linked_doc\].* \| true:1$');
select zz.put('RC5', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"T-6","amount":100000,"reason":"Qoldiq ham qaytarilsin","payee":"Sinov Ota Onaevich","clientRef":"rf_rc5_000001"}'));
select zz.put('RC5a', zz.as('U_DIR', $q$select public.adjust_credit('T-6', 50000, 'Sinov: avans tuzatildi', 'adj-rc5-0001')::text$q$));
select zz.chk('RC5 tasdiqdan keyin avans kamaygan (100 000 → 50 000): pul berilmaydi, hujjat o''tmaydi, avans tegilmaydi',
  zz.pay('U_KAS', zz.id('RC5')) || ' / ' || (select status || ':' || coalesce(no::text, '-') from public.cash_docs where id = zz.id('RC5'))
  || ' / ' || (select trim_scale(credit)::text from public.student_credit where id = 'T-6'),
  '^ERR P0001 \[kassa:credit_changed\].*hozir 50000 so''m, so''rovda 100000 so''m.* / approved:- / 50000$');
select zz.put('RC5c', zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('RC5'), 'Avans o''zgargan')));
-- fakturadan qaytarishga avansni qo'shish (clawback) — shu avans boshqa kutilayotgan so'rovda band bo'lsa rad (ikki marta berilmasin)
select zz.put('RC6', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"credit","id":"T-7","amount":40000,"reason":"Avansning bir qismi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc6_000001"}'));
select zz.chk('RC6 avans (100 000) dan 40 000 so''rovi kutilmoqda: fakturadan qaytarishga avans qo''shilsa — rad; avanssiz — o''tadi',
  zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ik7","amount":50000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clawback":true,"clientRef":"rf_rc6_000002"}') || ' | '
  || (zz.js(zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ik7","amount":50000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc6_000003"}')) ->> 'status'),
  '^ERR 22023 \[kassa:refund_pending\].*avansi.*\(40000 so''m\).* \| approved$');
-- g8 (g2 qoldig'i, avans): naqdsiz qaytarishga (refund_invoice) «avans ham» qo'shilsa — shu o'quvchi avansi bo'yicha kutilayotgan naqd so'rov
--   (RC6, 40 000) bor ekan rad, faktura va avans tegilmaydi (avans ikki marta berilmasin); avanssiz — avvalgidek darhol (fakturada RC6 dagi
--   50 000 lik so'rov bilan ham sig'adi); RC6 bekor qilingach — avans bilan ham (avans 0 ga tushadi)
-- (natija maydoni: JSON bo'lsa — maydoni, xato matni bo'lsa — o'zi: mutatsiyada FAIL bo'ladi, to'plam to'xtamaydi)
create or replace function zz.jf(p_k text, p_f text) returns text language sql as $$
  select case when v like '{%' and zz.js(v) is not null then zz.js(v) ->> p_f else v end from zz.v where k = p_k $$;
select zz.put('RC7a', zz.as('U_DIR', $q$select public.refund_invoice('invoice','ik7',100000,'O''quvchi ketdi',true,'d@x','rf_bank_rc7_01')::text$q$));
select zz.put('RC7s', (select trim_scale(i."paidAmount") || ':' || trim_scale(c.credit) || ':' || (select count(*) from public.refunds r where r."studentId" = 'T-7')
                         from public.invoices i, public.student_credit c where i.id = 'ik7' and c.id = 'T-7'));
select zz.put('RC7b', zz.as('U_DIR', $q$select public.refund_invoice('invoice','ik7',100000,'O''quvchi ketdi',false,'d@x','rf_bank_rc7_02')::text$q$));
select zz.put('RC7c', zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('RC6'), 'Naqdsiz qaytariladi')));
select zz.put('RC7d', zz.as('U_DIR', $q$select public.refund_invoice('invoice','ik7',100000,'O''quvchi ketdi',true,'d@x','rf_bank_rc7_03')::text$q$));
select zz.chk('RC7 g8: avans bo''yicha naqd so''rov (RC6, 40 000) kutilmoqda — naqdsiz qaytarishga «avans ham» qo''shilsa rad, faktura 400 000 va avans 100 000 tegilmadi; avanssiz — o''tadi; RC6 bekor qilingach — avans bilan ham (avans 0)',
  zz.get('RC7a') || ' | ' || zz.get('RC7s') || ' | ' || zz.jf('RC7b', 'ok') || ':' || zz.jf('RC7b', 'clawback') || ' | '
  || zz.jf('RC7c', 'status') || ':' || zz.jf('RC7d', 'ok') || ':' || zz.jf('RC7d', 'clawback') || ' | '
  || (select trim_scale("paidAmount") || ':' || status from public.invoices where id = 'ik7') || ':' || (select trim_scale(credit) from public.student_credit where id = 'T-7'),
  '^ERR 22023 \[kassa:refund_pending\] Bu o''quvchi avansi bo''yicha pul hali berilmagan naqd qaytarish so''rovi bor \(40000 so''m\).* \| 400000:100000:0 \| true:0 \| cancelled:true:100000 \| 200000:partial:0$');
-- teskari yo'nalish: naqdsiz qaytarishlardan keyin (to'langan 400 000 → 200 000) yangi naqd so'rov kamaygan to'langan summaga sig'ishi kerak
select zz.put('RC7f', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ik7","amount":160000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc7_000001"}'));
select zz.put('RC7g', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ik7","amount":150000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clientRef":"rf_rc7_000002"}'));
select zz.chk('RC7e naqdsiz qaytarishlardan keyin (to''langan 200 000, 50 000 lik naqd so''rov kutilmoqda): yangi naqd so''rov 160 000 — rad, 150 000 — o''tadi',
  zz.get('RC7f') || ' | ' || zz.jf('RC7g', 'status'),
  '^ERR 22023 \[kassa:refund_pending\].*\(50000 so''m\).*to''langan summadan \(200000 so''m\).* \| approved$');

-- (RP) ui-3: so'rovlar navbati — kutilayotgan so'rovlar + yangisi qaytariladigan summadan oshmaydi; o'sha kalit — o'sha so'rov
select zz.chk('RP1 faktura «ib» (to''langan 400 000, R4 bo''yicha 100 000 kutilmoqda): 350 000 — rad; o''sha kalit (R4) — o''sha so''rov, boshqa summa bilan — rad',
  zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ib","amount":350000,"reason":"Ortiqcha to''lov","payee":"Sinov Ota Onaevich","clientRef":"rf_rp1_000001"}') || ' | '
  || (zz.js(zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ib","amount":100000,"reason":"Ortiqcha to''lov","payee":"Sinov Ota Onaevich","clientRef":"rf_test_0004"}')) ->> 'dup') || ':'
  || (select count(*) from public.cash_docs where op = 'out_refund' and "sourceSnapshot" ->> 'targetId' = 'ib') || ' | '
  || zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ib","amount":90000,"reason":"Ortiqcha to''lov","payee":"Sinov Ota Onaevich","clientRef":"rf_test_0004"}'),
  '^ERR 22023 \[kassa:refund_pending\].*\(100000 so''m\).*to''langan summadan \(400000 so''m\).* \| true:1 \| ERR 22023 \[kassa:ref_mismatch\]');
select zz.put('RP2', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ib","amount":300000,"reason":"Ortiqcha to''lov","payee":"Sinov Ota Onaevich","clientRef":"rf_rp2_000001"}'));
select zz.put('RP2p', (zz.js(zz.pay('U_KAS', zz.id('R4'))) ->> 'status') || ':' || (zz.js(zz.pay('U_KAS', zz.id('RP2'))) ->> 'status'));
select zz.chk('RP2 jami to''langan summagacha (100 000 + 300 000 = 400 000) — o''tadi; ikkalasi berildi, faktura 0; qaytarish jurnali 2 qator',
  (zz.js(zz.get('RP2')) ->> 'status') || ' / ' || zz.get('RP2p') || ' / ' || (select trim_scale("paidAmount") || ':' || status from public.invoices where id = 'ib')
  || ' / ' || (select count(*) from public.refunds where "targetId" = 'ib' and "cashDocId" is not null), '^approved / posted:posted / 0:pending / 2$');
select zz.put('RP3', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"payment","id":"pu2","amount":70000,"reason":"Egasi topilmadi","payee":"Sinov Begona Shaxs","clientRef":"rf_rp3_000001"}'));
select zz.chk('RP3 biriktirilmagan to''lov: kutilayotgan so''rov bor — ikkinchisi rad',
  (zz.js(zz.get('RP3')) ->> 'status') || ' | ' || zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"payment","id":"pu2","amount":70000,"reason":"Egasi topilmadi","payee":"Sinov Begona Shaxs","clientRef":"rf_rp3_000002"}'),
  '^approved \| ERR 22023 \[kassa:refund_pending\]');
-- g8 (g2 qoldig'i, to'lov maqsadi): shu biriktirilmagan to'lov bo'yicha naqd so'rov (RP3) kutilmoqda — naqdsiz qaytarish (refund_invoice) ham
--   rad, to'lov biriktirilmagan holicha (pul ikki marta qaytarilmasin); so'rov «Kassa»da bekor qilingach — avvalgidek darhol
select zz.put('RP4a', zz.as('U_DIR', $q$select public.refund_invoice('payment','pu2',70000,'Egasi topilmadi',false,'d@x','rf_bank_rp4_01')::text$q$));
select zz.put('RP4s', (select status from public.payments where id = 'pu2') || ':' || (select count(*) from public.refunds where "targetId" = 'pu2'));
select zz.put('RP4c', zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('RP3'), 'Naqdsiz qaytariladi')));
select zz.put('RP4b', zz.as('U_DIR', $q$select public.refund_invoice('payment','pu2',70000,'Egasi topilmadi',false,'d@x','rf_bank_rp4_02')::text$q$));
select zz.chk('RP4 g8: biriktirilmagan to''lov (pu2) bo''yicha naqd so''rov (RP3) kutilmoqda — naqdsiz qaytarish rad, to''lov tegilmadi; so''rov bekor qilingach — o''tadi',
  zz.get('RP4a') || ' | ' || zz.get('RP4s') || ' | ' || zz.jf('RP4c', 'status') || ':' || zz.jf('RP4b', 'ok') || ':'
  || (select status from public.payments where id = 'pu2') || ':' || (select count(*) from public.refunds where "targetId" = 'pu2' and "cashDocId" is null),
  '^ERR 22023 \[kassa:refund_pending\] Bu to''lov bo''yicha pul hali berilmagan naqd qaytarish so''rovi bor \(70000 so''m\).* \| unmatched:0 \| cancelled:true:refunded:1$');

-- (RK) live-1, live-1b: qaytarish oynasi kaliti kassa ishlayotganda. «Naqdsiz» (refund_invoice) o'sha kalit bilan boshqa ma'lumot — rad
--   (oldindan tekshirish tarmog'i: ref_mismatch, birinchi yozilgani bilan); «Naqdsiz»dan keyin o'sha oynadan «Naqd» so'rovi — rad
--   (kassa:ref_mismatch, so'rov yozilmaydi: avval ikkinchi so'rov yozilib, pul berilganda qaytarish ikki marta bajarilardi); teskarisi —
--   «Naqd» so'rovidan keyin o'sha kalit bilan «Naqdsiz» — rad (ref_mismatch, via cash; so'rov bekor qilingach ham), faktura tegilmaydi.
--   T-10: to'langan rk1, rk2 (600 000 dan), avans 120 000; pu_rk — biriktirilmagan 30 000.
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values ('s10','T-10','Sinov K',5,'A','uz','',10,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('rk1','T-10','Sinov K','2027-01',600000,600000,'paid'), ('rk2','T-10','Sinov K','2026-12',600000,600000,'paid');
insert into public.student_credit (id, "studentId", credit) values ('T-10','T-10',120000);
insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw) values
  ('pu_rk', '', 'bank', 30000, 'unmatched', 'Noma''lum To''lovchi 3', false, '{}');
set local session_replication_role = origin;
select zz.put('RK1a', zz.as('U_DIR', $q$select public.refund_invoice('invoice','rk1',100000,'Ortiqcha to''lov',false,'d@x','rf_rk1_000001')::text$q$));
select zz.put('RK1b', zz.as('U_DIR', $q$select public.refund_invoice('invoice','rk1',150000,'Ortiqcha to''lov',true,'d@x','rf_rk1_000001')::text$q$));
select zz.put('RK1s', (select trim_scale("paidAmount") from public.invoices where id = 'rk1') || ':' || (select count(*) from public.refunds where "studentId" = 'T-10')
                      || ':' || (select trim_scale(credit) from public.student_credit where id = 'T-10'));
select zz.put('RK1c', zz.as('U_DIR', $q$select public.refund_invoice('invoice','rk1',100000,'Ortiqcha to''lov',false,'d@x','rf_rk1_000001')::text$q$));
select zz.chk('RK1 live-1 (kassa ishlayapti, «Naqdsiz»): o''sha kalit, boshqa summa + «avans ham» — rad (ref_mismatch, birinchi yozilgani: 100 000, avanssiz); faktura, qaytarishlar, avans o''zgarmadi; bir xil ma''lumot — takror',
  zz.jf('RK1a', 'ok') || ':' || zz.jf('RK1a', 'newPaid') || ' | ' || zz.jf('RK1b', 'ok') || ':' || zz.jf('RK1b', 'reason') || ':' || zz.jf('RK1b', 'amount') || ':' || zz.jf('RK1b', 'clawback')
  || ' | ' || zz.get('RK1s') || ' | ' || zz.jf('RK1c', 'dup'),
  '^true:500000 \| false:ref_mismatch:100000:false \| 500000:1:120000 \| true$');
select zz.put('RK2a', zz.as('U_DIR', $q$select public.refund_invoice('invoice','rk2',100000,'Adashib kiritilgan',false,'d@x','rf_rk2_000001')::text$q$));
select zz.put('RK2b', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"rk2","amount":100000,"reason":"Adashib kiritilgan","payee":"Sinov Ota Onaevich","clientRef":"rf_rk2_000001"}'));
select zz.chk('RK2 live-1b: «Naqdsiz» qaytarishdan keyin o''sha oynadan (o''sha kalit) «Naqd» so''rovi — rad (kassa:ref_mismatch), naqd so''rov yozilmadi; faktura 500 000, qaytarish bitta',
  zz.jf('RK2a', 'ok') || ' | ' || zz.get('RK2b')
  || ' | ' || (select count(*) from public.cash_docs where "clientRef" = 'ref_rf_rk2_000001') || ':' || (select trim_scale("paidAmount") from public.invoices where id = 'rk2')
  || ':' || (select count(*) from public.refunds where "targetId" = 'rk2'),
  '^true \| ERR 22023 \[kassa:ref_mismatch\] Bu oynadan naqdsiz \(bank / karta\) qaytarish allaqachon yozilgan.* \| 0:500000:1$');
select zz.put('RK3a', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"rk2","amount":50000,"reason":"Ortiqcha to''lov","payee":"Sinov Ota Onaevich","clientRef":"rf_rk3_000001"}'));
select zz.put('RK3b', zz.as('U_DIR', $q$select public.refund_invoice('invoice','rk2',50000,'Ortiqcha to''lov',false,'d@x','rf_rk3_000001')::text$q$));
select zz.put('RK3s', (select trim_scale("paidAmount") from public.invoices where id = 'rk2') || ':' || (select count(*) from public.refunds where "targetId" = 'rk2')
                      || ':' || (select count(*) from public.applied_payments where id = 'refund:rf_rk3_000001'));
select zz.put('RK3c', zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('RK3a'), 'Naqdsiz qaytariladi')));
select zz.put('RK3d', zz.as('U_DIR', $q$select public.refund_invoice('invoice','rk2',50000,'Ortiqcha to''lov',false,'d@x','rf_rk3_000001')::text$q$));
select zz.put('RK4a', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"payment","id":"pu_rk","amount":30000,"reason":"Egasi topilmadi","payee":"Sinov Begona Shaxs","clientRef":"rf_rk4_000001"}'));
select zz.put('RK4b', zz.as('U_DIR', $q$select public.refund_invoice('payment','pu_rk',30000,'Egasi topilmadi',false,'d@x','rf_rk4_000001')::text$q$));
select zz.put('RK4s', (select status from public.payments where id = 'pu_rk') || ':' || (select count(*) from public.refunds where "targetId" = 'pu_rk'));
select zz.put('RK4c', zz.as('U_DIR', format('select public.kassa_doc_cancel(%L, %L)::text', zz.id('RK4a'), 'Sinov tugadi')));
select zz.chk('RK3 live-1b teskari: «Naqd» so''rovidan keyin o''sha kalit bilan «Naqdsiz» — rad (ref_mismatch, via cash; so''rov bilan jami to''langandan oshmasa ham), faktura tegilmadi, posbon yozilmadi; so''rov bekor qilingach ham — rad (boshqa usul — yangi oyna); biriktirilmagan to''lovda ham',
  zz.jf('RK3a', 'status') || ' | ' || zz.jf('RK3b', 'ok') || ':' || zz.jf('RK3b', 'reason') || ':' || zz.jf('RK3b', 'via') || ' | ' || zz.get('RK3s')
  || ' | ' || zz.jf('RK3c', 'status') || ':' || zz.jf('RK3d', 'reason') || ':' || zz.jf('RK3d', 'via')
  || ' | ' || zz.jf('RK4a', 'status') || ':' || zz.jf('RK4b', 'reason') || ':' || zz.jf('RK4b', 'via') || ':' || zz.get('RK4s') || ':' || zz.jf('RK4c', 'status'),
  '^approved \| false:ref_mismatch:cash \| 500000:1:0 \| cancelled:ref_mismatch:cash \| approved:ref_mismatch:cash:unmatched:0:cancelled$');

-- (RS) acc-7: qaytarish orderining faktura qismi hisobvarag'i (4010 / 6310) pul BERILGAN kunga ko'ra qayta aniqlanadi; summa va tasdiq o'zgarmaydi
select zz.put('RS0', zz.as('U_KAS', format('select public.kassa_day_close(%L::jsonb)::text', json_build_object('day', '2027-01-06', 'counted', zz.bal()::numeric))));
select zz.clock('2027-01-31 10:00+05');
select zz.put('RSa', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"r8b","amount":100000,"reason":"Fevral uchun ortiqcha","payee":"Sinov Ota Onaevich","clientRef":"rf_rsa_000001"}'));
select zz.put('RSb', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"r8c","amount":100000,"reason":"Mart uchun ortiqcha","payee":"Sinov Ota Onaevich","clientRef":"rf_rsb_000001"}'));
select zz.put('RSc', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"r8a","amount":100000,"reason":"Yanvar uchun ortiqcha","payee":"Sinov Ota Onaevich","clientRef":"rf_rsc_000001"}'));
select zz.chk('RS0 06.01 yopildi; 31.01 so''rovlari: fevral, mart — Dt 6310 (kelgusi oy), yanvar — Dt 4010',
  (zz.js(zz.get('RS0')) -> 'day' ->> 'status') || ' / ' || zz.lines(zz.id('RSa')) || ' / ' || zz.lines(zz.id('RSb')) || ' / ' || zz.lines(zz.id('RSc')),
  '^closed / 6310>5010=100000@OP-15 / 6310>5010=100000@OP-15 / 4010>5010=100000@OP-15$');
-- teskari yo'nalish (server soati tuzatilganda): 01.02 da yozilgan fevral so'rovi (Dt 4010), pul 31.01 kuni berilsa — Dt 6310
select zz.clock('2027-02-01 09:00+05');
select zz.put('RSd', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"r9b","amount":100000,"reason":"Fevral uchun ortiqcha","payee":"Sinov Ota Onaevich","clientRef":"rf_rsd_000001"}'));
select zz.put('RSd0', zz.lines(zz.id('RSd')));
select zz.clock('2027-01-31 18:00+05');
select zz.put('RSdp', zz.pay('U_KAS', zz.id('RSd')));
select zz.chk('RS1 01.02 dagi so''rov Dt 4010; pul 31.01 kuni berildi — Dt 6310 (summa, tasdiq, oluvchi o''zgarmadi); kun jurnalida «resplit»',
  zz.get('RSd0') || ' / ' || (zz.js(zz.get('RSdp')) ->> 'status') || ':' || (zz.js(zz.get('RSdp')) ->> 'businessDay') || ':' || trim_scale((zz.js(zz.get('RSdp')) ->> 'amount')::numeric)
  || ':' || (zz.js(zz.get('RSdp')) ->> 'dirApprovedBy') || ' / ' || zz.lines(zz.id('RSd'))
  || ' / ' || (select e.kind || ':' || e.day || ':' || (e.data ->> 'docId' = zz.id('RSd')) || ':' || (e.data -> 'lines' -> 0 ->> 'from') || '>' || (e.data -> 'lines' -> 0 ->> 'to')
                 from public.cash_day_events e where e.kind = 'resplit' and e.data ->> 'docId' = zz.id('RSd')),
  '^4010>5010=100000@OP-15 / posted:2027-01-31:100000:U_DIR / 6310>5010=100000@OP-15 / resplit:2027-01-31:true:4010>6310$');
select zz.put('RS2c', zz.as('U_KAS', format('select public.kassa_day_close(%L::jsonb)::text', json_build_object('day', '2027-01-31', 'counted', zz.bal()::numeric))));
select zz.clock('2027-02-01 10:00+05');
select zz.put('RS2', (zz.js(zz.pay('U_KAS', zz.id('RSa'))) ->> 'status') || ':' || (zz.js(zz.pay('U_KAS', zz.id('RSb'))) ->> 'status') || ':' || (zz.js(zz.pay('U_KAS', zz.id('RSc'))) ->> 'status'));
select zz.chk('RS2 31.01 da tasdiqlangan, 01.02 da berilgan: fevral — Dt 4010 (fevral boshlangan), mart — Dt 6310, yanvar — Dt 4010; faqat fevral qatori o''zgardi',
  zz.get('RS2') || ' / ' || zz.lines(zz.id('RSa')) || ' / ' || zz.lines(zz.id('RSb')) || ' / ' || zz.lines(zz.id('RSc'))
  || ' / ' || (select string_agg((e.data ->> 'docId' = zz.id('RSa'))::text || ':' || e.day || ':' || (e.reason ~ 'Dt 6310 → Dt 4010'), ',') from public.cash_day_events e where e.kind = 'resplit' and e.day = '2027-02-01'),
  '^posted:posted:posted / 4010>5010=100000@OP-15 / 6310>5010=100000@OP-15 / 4010>5010=100000@OP-15 / true:2027-02-01:true$');
select zz.chk('RS3 qaytarishlar bajarildi (fakturalar 200 000), moslik P8 toza, order summasi naqd qatorlar jamiga teng',
  (select string_agg(id || '=' || trim_scale("paidAmount"), ',' order by id) from public.invoices where id in ('r8a', 'r8b', 'r8c', 'r9b'))
  || ' / ' || (app.kassa_reconcile('2027-01-31', '2027-02-01') -> 'p8')::text
  || ' / ' || (select count(*) from public.cash_docs c where c.id in (zz.id('RSa'), zz.id('RSb'), zz.id('RSc'), zz.id('RSd'))
                 and c.amount = (select sum(l.amount) from public.cash_doc_lines l where l."docId" = c.id and l.cash)),
  '^r8a=200000,r8b=200000,r8c=200000,r9b=200000 / \{"doc": 0, "row": 0\} / 4$');
-- qator himoyasi tor: faqat tasdiqlangan, to'lanmagan qaytarish orderida, shu hujjat bayrog'i bilan va faqat debet 4010 ↔ 6310
select zz.put('RSe', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"r8b","amount":50000,"reason":"Yana ortiqcha","payee":"Sinov Ota Onaevich","clientRef":"rf_rse_000001"}'));
savepoint rs4;
do $x$ declare v_e text := zz.id('RSe'); v_p text := zz.id('RSa'); begin
  perform set_config('iqror.kassa_rpc', '1', true);
  begin update public.cash_doc_lines set debit = '6310' where "docId" = v_e; perform zz.put('RS4a', 'ok');
  exception when others then perform zz.put('RS4a', 'ERR ' || sqlstate || ' ' || sqlerrm); end;   -- hujjat bayrog'isiz
  perform set_config('iqror.kassa_resplit', v_e, true);
  begin update public.cash_doc_lines set amount = amount + 1 where "docId" = v_e; perform zz.put('RS4b', 'ok');
  exception when others then perform zz.put('RS4b', 'ERR ' || sqlstate || ' ' || sqlerrm); end;   -- summa
  begin update public.cash_doc_lines set debit = '9430' where "docId" = v_e; perform zz.put('RS4c', 'ok');
  exception when others then perform zz.put('RS4c', 'ERR ' || sqlstate || ' ' || sqlerrm); end;   -- boshqa hisobvaraq
  perform set_config('iqror.kassa_resplit', v_p, true);
  begin update public.cash_doc_lines set debit = '6310' where "docId" = v_p; perform zz.put('RS4d', 'ok');
  exception when others then perform zz.put('RS4d', 'ERR ' || sqlstate || ' ' || sqlerrm); end;   -- o'tkazilgan hujjat
  perform set_config('iqror.kassa_resplit', '', true); perform set_config('iqror.kassa_rpc', '', true);
end $x$;
select zz.get('RS4a') || ' | ' || zz.get('RS4b') || ' | ' || zz.get('RS4c') || ' | ' || zz.get('RS4d') as rs4 \gset
rollback to savepoint rs4;
select zz.chk('RS4 qatorlar boshqa holatda o''zgarmaydi: hujjat bayrog''isiz, summa, boshqa hisobvaraq, o''tkazilgan hujjat — hammasi rad',
  :'rs4', '^ERR 42501 .*o''zgartirilmaydi.* \| ERR 42501 .*o''zgartirilmaydi.* \| ERR 42501 .*o''zgartirilmaydi.* \| ERR 42501 .*o''zgartirilmaydi');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
