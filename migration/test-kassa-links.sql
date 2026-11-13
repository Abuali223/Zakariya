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

-- ---------- (A) ish haqi avansi ----------
select zz.put('A1', zz.rpc('U_KAS', 'kassa_payout_request', '{"op":"out_advance","amount":300000,"partyType":"employee","partyId":"staff:st1","basis":"Ariza, 03.01.2027","clientRef":"a1-000001"}'));
select zz.chk('A1 avans so''rovi: 2-ro''yxat tasdig''ini kutadi, avans hali yozilmagan',
  (zz.get('A1')::jsonb ->> 'status') || ':' || (zz.get('A1')::jsonb ->> 'needsList2') || ':' || (select count(*) from public.staff_advances), '^draft:true:0$');
select zz.chk('A2 tasdiqsiz pul berilmaydi', zz.pay('U_KAS', zz.id('A1')), '^ERR 42501 \[kassa:not_approved\]');
select zz.put('A2b', zz.appr('U_FM', zz.id('A1')));
select zz.put('A3', zz.pay('U_KAS', zz.id('A1')));
select zz.chk('A3 pul berildi: order № 3, Dt 4210 Kt 5010', (zz.get('A3')::jsonb ->> 'no') || ' / ' || zz.lines(zz.id('A1')), '^3 / 4210>5010=300000@OP-08$');
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
  (zz.get('A5')::jsonb ->> 'status') || ' / ' || (select string_agg(id, ',') from public.staff_advances) || ' / ' || zz.bal(), '^void / adv_card_1 / 4000000$');
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
  (zz.get('R1')::jsonb ->> 'status') || ':' || coalesce(zz.get('R1')::jsonb ->> 'no', '-') || ':' || (zz.get('R1')::jsonb ->> 'amount') || ':' || (zz.get('R1')::jsonb ->> 'partyName') || ':' || (zz.get('R1')::jsonb ->> 'dirApprovedBy')
  || ' / ' || zz.lines(zz.id('R1')) || ' / ' || (zz.get('R1')::jsonb ->> 'basis'),
  '^approved:-:450000:Sinov Ota Onaevich:U_DIR / 4010>5010=300000@OP-15, 6310>5010=150000@OP-15 / Qaytarish: O''quvchi ketdi; ariza 03.01.2027$');
select zz.chk('R1b so''rov paytida balans o''zgarmaydi: faktura, avans, jurnal',
  (select trim_scale("paidAmount") || ':' || status from public.invoices where id = 'ia') || '/' || (select trim_scale(credit) from public.student_credit where id = 'T-1') || '/' || (select count(*) from public.refunds), '^1000000:paid/150000/0$');
select zz.chk('R1c qayta yuborish (o''sha kalit) — takror', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ia","amount":300000,"reason":"O''quvchi ketdi","payee":"Sinov Ota Onaevich","clawback":true,"clientRef":"rf_test_0001"}'), '"dup": true');
select zz.chk('R1d Moliya menejeri pulni bera olmaydi', zz.pay('U_FM', zz.id('R1')), '^ERR 42501');
select zz.put('R2', zz.pay('U_KAS', zz.id('R1')));
select zz.chk('R2 kassir pulni berdi: order № 4; faktura 700 000 (qisman), avans 0',
  (zz.get('R2')::jsonb ->> 'no') || ' / ' || (select trim_scale("paidAmount") || ':' || status from public.invoices where id = 'ia') || ' / ' || (select trim_scale(credit) from public.student_credit where id = 'T-1') || ' / ' || zz.bal(),
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
-- tasdiqdan keyin holat o'zgarsa: Direktor shu orada naqdsiz qaytarib yuboradi → kassa so'rovi bo'yicha pul berilmaydi
select zz.put('R5', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"ia","amount":500000,"reason":"Qayta hisob","payee":"Sinov Ota Onaevich","clientRef":"rf_test_0005"}'));
select zz.chk('R5a naqdsiz qaytarish — avvalgidek darhol (Direktor)', zz.as('U_DIR', $q$select public.refund_invoice('invoice','ia',400000,'bank orqali qaytarildi',false,'d@x','rf_bank_0001')::text$q$), '"ok": true');
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
  (zz.get('R6c')::jsonb ->> 'partyType') || ':' || (zz.get('R6c')::jsonb ->> 'status') || ' / ' || zz.lines(zz.id('R6b')) || ' / ' || (select status from public.payments where id = 'pu1')
  || ' / ' || (select method || ':' || ("cashDocId" = zz.id('R6b')) from public.refunds where target = 'payment'),
  '^other:posted / 6390>5010=250000@OP-16 / refunded / cash:true$');
-- o'quvchi qatori yo'q (eski, «yetim» faktura): tomon — «boshqa», qaytarish baribir bajariladi
set local session_replication_role = replica;
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values ('iz','T-OLD','Sinov Eski','2026-11',500000,500000,'paid');
set local session_replication_role = origin;
select zz.put('R6d', zz.rpc('U_DIR', 'kassa_refund_request', '{"target":"invoice","id":"iz","amount":200000,"reason":"Eski faktura","payee":"Sinov Eski Otasi","clientRef":"rf_test_0008"}'));
select zz.put('R6e', zz.pay('U_KAS', zz.id('R6d')));
select zz.chk('R6d o''quvchi qatori yo''q faktura: tomon «boshqa», qaytarish bajarildi',
  (zz.get('R6d')::jsonb ->> 'partyType') || ':' || (zz.get('R6e')::jsonb ->> 'status') || ':' || (select trim_scale("paidAmount") || ':' || status from public.invoices where id = 'iz'), '^other:posted:300000:partial$');
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
  (zz.get('E4')::jsonb ->> 'status') || ' / ' || (select string_agg(id, ',' order by id) from public.expenses), '^void / ex_bank_1,payroll__2027-01$');

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
  (zz.get('O1')::jsonb ->> 'ok') || ':' || (zz.get('O1')::jsonb ->> 'method') || ':' || (zz.get('O1')::jsonb -> 'kassa' ->> 'form') || ':' || (zz.get('O1')::jsonb -> 'kassa' ->> 'status')
    || ':' || (zz.get('O1')::jsonb -> 'kassa' ->> 'day') || ':' || (zz.get('O1')::jsonb -> 'student' ->> 'id'), '^true:offset:ACT:posted:2027-01-04:T-2$');
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
  (zz.bal() = zz.get('O_bal0'))::text || ':' || (select count(*) from jsonb_array_elements(zz.as('U_FM', $q$select public.kassa_day_book('main', '2027-01-04')::text$q$)::jsonb -> 'docs') d where d ->> 'op' = 'nc_offset'), '^true:0$');
select zz.chk('O2 qayta yuborish — takror: yangi yozuv ham, yangi dalolatnoma ham yo''q',
  (zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 1300000, 's2', '2027-01-03'))::jsonb ->> 'dup') || ':' ||
  (select count(*) from public.cash_docs where op = 'nc_offset') || ':' || (select count(*) from public.payments where provider = 'offset') || ':' ||
  (select trim_scale("paidAmount") from public.invoices where id = 'ob'), '^true:1:1:300000$');
select zz.chk('O2b o''sha kalit, boshqa summa — rad', zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0001', 'IQT-T1', 'teachers:tch1', '2026-12', 999, 's2', '2027-01-03')), '^ERR 22023 \[kassa:ref_mismatch\]');
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
  (zz.get('O8')::jsonb ->> 'status') || ':' || ((zz.get('O8')::jsonb ->> 'no') is not null) || ':' || (zz.get('O8')::jsonb ->> 'voidedBy')
  || ' / ' || (select count(*) from public.salary_payments where id = 'sp_ofs_0001')
  || ' / ' || (select status from public.payments where provider = 'offset')
  || ' / ' || (select string_agg(id || '=' || status || ':' || coalesce(trim_scale("paidAmount")::text, 'null'), ',' order by id) from public.invoices where "studentId" = 'T-2')
  || ' / ' || coalesce((select trim_scale(credit)::text from public.student_credit where id = 'T-2'), '0'),
  '^void:true:U_DIR / 0 / canceled / oa=pending:0,ob=pending:0 / 0$');
select zz.chk('O8b qayta bekor qilish — takror; ota-onaga hali yuborilmagan to''lov xabarnomasi to''xtatildi',
  (zz.as('U_DIR', format('select public.kassa_offset_void(%L, %L)::text', zz.id('O1d'), 'Xato o''quvchi tanlangan'))::jsonb ->> 'dup') || ':' ||
  coalesce((select status from public.notify_queue where id = 'pay__' || (select id from public.payments where provider = 'offset')), 'yo''q'), '^true:(skipped|yo''q)$');
select zz.put('O9', zz.rpc('U_DIR', 'kassa_offset', zz.ofs('sp_ofs_0003', 'IQT-T1', 'teachers:tch1', '2026-12', 500000, 'T-3', '2027-01-04')));
select zz.chk('O9 fakturasi yo''q o''quvchi: butun summa avansga (Kt 6310); vedomost chegarasi bekor qilingandan keyin tiklangan',
  (zz.get('O9')::jsonb -> 'kassa' ->> 'status') || ' / ' || zz.lines(zz.get('O9')::jsonb -> 'kassa' ->> 'docId') || ' / ' || (select trim_scale(credit)::text from public.student_credit where id = 'T-3')
  || ' / ' || (select "sourceSnapshot" ->> 'allocation' from public.cash_docs where id = zz.get('O9')::jsonb -> 'kassa' ->> 'docId'),
  '^posted / 6710>6310=500000@IN-01 / 500000 / exact$');
select zz.chk('O9b dalolatnomalar raqami uzluksiz (bekor qilingani raqamini saqlaydi)', jsonb_array_length(app.kassa_gap_check('main', 2027))::text, '^0$');
select zz.chk('O9c kassa qoldig''i o''zaro hisoblardan keyin ham o''zgarmadi', (zz.bal() = zz.get('O_bal0'))::text, '^true$');

-- ---------- Kechikkan qaytarish (CT-26) ----------
select zz.clock('2027-01-06 10:00+05');
select zz.chk('O10 o''zaro hisob ertasi kunlarda bekor qilinmaydi',
  zz.as('U_DIR', format('select public.kassa_offset_void(%L, %L)::text', zz.get('O9')::jsonb -> 'kassa' ->> 'docId', 'Kechikkan bekor qilish')), '^ERR P0001 \[kassa:day_closed\]');
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
  (zz.get('Q0')::jsonb -> 'day' ->> 'status') || ':' || (zz.get('Q1p')::jsonb ->> 'status') || ':' || (select trim_scale(amount) || ':' || month from public.staff_advances where "cashDocId" = zz.id('Q1')),
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
  (zz.get('Q3')::jsonb ->> 'status') || ':' || (zz.get('Q3')::jsonb ->> 'no') || ':' || zz.lines(zz.id('Q3')) || ' / '
  || (select "teacherId" || ':' || "payeeRef" || ':' || trim_scale(amount) || ':' || month || ':' || date || ':' || method || ':' || (note ~ 'KO-1 № 1') from public.staff_advances where "cashDocId" = zz.id('Q3')),
  '^posted:1:5010>4210=80000@OP-08 / IQX-T1:staff:st1:-80000:2027-01:2027-01-06:cash:true$');
select zz.chk('Q3b oylik hisobida avans sof: naqd 200 000 − 80 000 + karta 50 000 = 170 000; kassir oynasi: berilgan / qaytgan / qoldiq',
  trim_scale(app.payroll_adv('IQX-T1', '2027-01')) || ' | '
  || (select (j -> 'advance' ->> 'given') || '/' || (j -> 'advance' ->> 'returned') || '/' || (j -> 'advance' ->> 'open') || ':' || (j ->> 'locked')
        from (select zz.as('U_KAS', $q$select public.kassa_staff_open('main', 'staff:st1', '2027-01')::text$q$)::jsonb as j) q),
  '^170000 \| 200000/80000/120000:false$');
select zz.chk('Q4 qayta yuborish — takror, ikkinchi yozuv yo''q; bog''langan manfiy qatorni mijoz o''chira olmaydi',
  (zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":80000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q3-000001"}')::jsonb ->> 'dup')
  || ':' || (select count(*) from public.staff_advances where amount < 0) || ' | '
  || zz.as('U_DIR', $q$with x as (delete from public.staff_advances where amount < 0 returning id) select count(*)::text from x$q$),
  '^true:1 \| ERR 42501 \[kassa:linked_row\]');
select zz.chk('Q4b o''sha kalit, boshqa oy — rad', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":80000,"month":"2026-12","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q3-000001"}'),
  '^ERR 22023 \[kassa:ref_mismatch\]');
select zz.put('Q5', zz.as('U_FM', $q$select public.payroll_submit('2027-01', '[{"personType":"staff","personId":"IQX-T1","gross":2000000}]')::text$q$));
select zz.chk('Q5 yanvar vedomosti: avans BAZADAN sof 170 000 (qaytgan 80 000 ushlanmaydi)',
  (zz.get('Q5')::jsonb ->> 'ok') || ' | ' || (select trim_scale(advance) || ':' || (payable = greatest(0, gross - advance - deduction + "subBonus" + "carryIn")) from public.payroll_lines where "runId" = '2027-01'),
  '^true \| 170000:true$');
select zz.put('Q6', zz.as('U_HR', $q$select public.payroll_decide('2027-01', true)::text$q$));
select zz.chk('Q6 vedomost tasdiqlandi: endi avans qaytimi rad («Ish haqi to''lovi» statiyasi yoki oyni qayta ochish); qaytimni bekor qilish ham rad',
  (zz.get('Q6')::jsonb ->> 'status') || ' | '
  || zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":10000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Ortiqcha avans qaytdi","clientRef":"q6-000001"}') || ' | '
  || zz.void('U_KAS', zz.id('Q3'), 'Xato kiritilgan qaytim'),
  '^approved \| ERR P0001 \[kassa:advance_locked\].*Ish haqi to''lovi.* \| ERR P0001 \[kassa:advance_locked\]');
select zz.put('Q7', zz.as('U_DIR', $q$select public.payroll_reopen('2027-01', 'Avans qaytimi xato')::text$q$) || ' | ' || zz.void('U_KAS', zz.id('Q3'), 'Xato kiritilgan qaytim'));
select zz.chk('Q7 Direktor oyni qayta ochdi — qaytim shu kuni bekor qilindi: manfiy avans yozuvi olib tashlandi, avans 250 000',
  (split_part(zz.get('Q7'), ' | ', 1)::jsonb ->> 'status') || ':' || (split_part(zz.get('Q7'), ' | ', 2)::jsonb ->> 'status') || ':'
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
  (zz.get('Q9')::jsonb ->> 'status') || ':' || zz.lines(zz.id('Q9')) || ' / '
  || (select trim_scale(paid) || ':' || trim_scale(gross) || ':' || month || ':' || date || ':' || method || ':' || "payeeRef" from public.salary_payments where "cashDocId" = zz.id('Q9'))
  || ' / ' || (app.salary_carry('IQT-T1', '2027-01') - zz.get('Qc0')::numeric),
  '^posted:5010>6710=300000@OP-09 / -300000:3000000:2026-12:2027-01-06:cash:teachers:tch1 / 300000$');
select zz.chk('Q9b kassir oynasi: dekabr naqd maosh berilgan 1 100 000, qaytgan 300 000, sof 800 000; oy tasdiqlangan',
  (select (j -> 'salary' ->> 'paid') || '/' || (j -> 'salary' ->> 'returned') || '/' || (j -> 'salary' ->> 'net') || ':' || (j ->> 'locked')
     from (select zz.as('U_KAS', $q$select public.kassa_staff_open('main', 'teachers:tch1', '2026-12')::text$q$)::jsonb as j) q), '^1100000/300000/800000:true$');
select zz.chk('Q10 darvoza qaytgan summani ko''radi: berish mumkin 1 700 000 (1 400 000 + qaytgan 300 000), undan ortiq — rad',
  zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_q10', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1700001)), '^ERR 23514 .*berish mumkin: 1700000');
select zz.put('Q10', zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_q10', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 1700000)));
select zz.chk('Q10b qaytgan maosh qayta berildi — dekabr to''liq yopildi: qoldiq 0',
  (zz.get('Q10')::jsonb -> 'kassa' ->> 'status') || ':' || trim_scale(app.salary_carry('IQT-T1', '2027-01')) || ':' || zz.get('Qc0'), '^posted:0:1400000$');
select zz.chk('Q11 qaytgan maosh qayta berilgan — qaytimni bekor qilish rad (tasdiqlangandan 300 000 ortiq bo''lardi)',
  zz.void('U_KAS', zz.id('Q9'), 'Xato kiritilgan qaytim'), '^ERR P0001 \[kassa:salary_repaid\].*300000 so''m ortiq');
select zz.put('Q12', (zz.void('U_KAS', zz.get('Q10')::jsonb -> 'kassa' ->> 'docId', 'Xato berilgan maosh')::jsonb ->> 'status') || ':'
  || (zz.void('U_KAS', zz.id('Q9'), 'Xato kiritilgan qaytim')::jsonb ->> 'status'));
select zz.chk('Q12 avval keyingi maosh orderi, keyin qaytim bekor qilindi: ikkala yozuv olib tashlandi, qoldiq hisobi boshlang''ich holatda',
  zz.get('Q12') || ':' || (select count(*) from public.salary_payments where "cashDocId" in (zz.id('Q9'), zz.get('Q10')::jsonb -> 'kassa' ->> 'docId'))
  || ':' || (app.salary_carry('IQT-T1', '2027-01') = zz.get('Qc0')::numeric), '^void:void:0:true$');
select zz.put('Q13', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":50000,"month":"2027-01","partyType":"employee","partyId":"staff:st1","articleId":"OP-08","basis":"Avans qaytdi","clientRef":"q13-00001"}'));
select zz.chk('Q13 moslik (P5 «ret»): xodim qaytargan pul orderlari ↔ manfiy yozuvlar — toza; kassa qoldig''i hujjatlardan',
  (zz.get('Q13')::jsonb ->> 'status') || ':' || (app.kassa_reconcile('2027-01-04', '2027-01-06') -> 'p5' ->> 'ret') || ':' || (app.kassa_reconcile('2027-01-04', '2027-01-06') -> 'p5' ->> 'row')
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
select zz.put('Q16b', (zz.void('U_KAS', zz.id('Q13'), 'Xato kiritilgan qaytim')::jsonb ->> 'status') || ':' || (zz.void('U_KAS', zz.id('Q1'), 'Xato berilgan avans')::jsonb ->> 'status'));
select zz.chk('Q16 avans orderi (200 000), undan qaytim (50 000) bor — bekor qilish rad (oy naqd avansi −50 000 bo''lardi); avval qaytim, keyin avans — ikkalasi bekor, yozuvlar olib tashlandi, oy avansi faqat karta 50 000',
  zz.get('Q16') || ' | ' || zz.get('Q16b') || ':' || (select count(*) from public.staff_advances where "cashDocId" in (zz.id('Q1'), zz.id('Q13')))
  || ':' || trim_scale(app.payroll_adv('IQX-T1', '2027-01')) || ':' || zz.bal(),
  '^ERR P0001 \[kassa:staff_returned\].*2027-01 oy naqd avansi manfiy.*\(-50000 so''m\).*qaytim orderini bekor qiling \| void:void:0:50000:3100000$');
select zz.put('Q17', zz.rpc('U_KAS', 'kassa_salary_pay', zz.sal('sp_IQT-T1_2026-12_q17', 'cash', 'IQT-T1', 'teachers:tch1', '2026-12', 200000)));
select zz.put('Q17r', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_staff_return","amount":1200000,"month":"2026-12","partyType":"employee","partyId":"teachers:tch1","articleId":"OP-09","basis":"Ortiqcha maosh qaytdi","clientRef":"q17-00001"}'));
select zz.put('Q17v', zz.void('U_KAS', zz.get('Q17')::jsonb -> 'kassa' ->> 'docId', 'Xato berilgan maosh'));
select zz.put('Q17b', (zz.void('U_KAS', zz.id('Q17r'), 'Xato kiritilgan qaytim')::jsonb ->> 'status') || ':'
  || (zz.void('U_KAS', zz.get('Q17')::jsonb -> 'kassa' ->> 'docId', 'Xato berilgan maosh')::jsonb ->> 'status'));
select zz.chk('Q17 dekabr: naqd maosh 200 000 va qaytim 1 200 000 (naqd berilgan 1 300 000 dan) — maosh orderini bekor qilish rad (sof berilgan −100 000 bo''lardi); avval qaytim, keyin maosh — ikkalasi bekor, qoldiq hisobi boshlang''ich holatda',
  (zz.get('Q17')::jsonb -> 'kassa' ->> 'status') || ':' || (zz.get('Q17r')::jsonb ->> 'status') || ' | ' || zz.get('Q17v') || ' | ' || zz.get('Q17b') || ':'
  || (select count(*) from public.salary_payments where "cashDocId" in (zz.id('Q17r'), zz.get('Q17')::jsonb -> 'kassa' ->> 'docId'))
  || ':' || (app.salary_carry('IQT-T1', '2027-01') = zz.get('Qc0')::numeric) || ':' || zz.bal(),
  '^posted:posted \| ERR P0001 \[kassa:staff_returned\].*2026-12 oy uchun naqd berilgan maosh manfiy.*\(-100000 so''m\).*qaytim orderini bekor qiling \| void:void:0:true:3100000$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
