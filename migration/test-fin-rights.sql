-- =====================================================================
-- test-fin-rights.sql — moliya ish rejasi F1.21 (fin-rights.sql, nurse-sick.sql students_billing, reports-roles.sql, claim_child)
--   sinovi: «Buxgalter» (accountant) rolining o'qish huquqlari — YOPIQ RO'YXAT.
--   (R) ruxsat etilgan jadvallar; (V) «*_acc» ko'rinishlari — to'lovchi matni, telefon, email, kasallik sanalari, davomat tafsilotisiz;
--   (K) maxfiy ota-ona kodi, telefon, boshqa xodim emaili (ism o'rnida email turgan eski hisob ham), kasallik sanalari, manzil va
--       sog'liq belgilari buxgalter o'qiy oladigan HECH BIR jadval / ko'rinishda va kassa javoblarida (qaytarish so'rovi, kamomad
--       dalolatnomasi ham) yo'q; farzand biriktira olmaydi;
--   (B) students_billing; (D) D6/D7: boshqa jadvallar (baholar, davomat, monitoring ham) yopiq; (W) yozish yo'q: UPDATE / DELETE —
--       ustunsiz so'rov (faqat yozish siyosati ishlaydi), INSERT — triggerlarsiz (faqat RLS qaror qiladi); (P) pul RPC'lari — 42501;
--   (L) yopiq ro'yxat: buxgalterga «true» bo'ladigan yordamchilar ishlatilgan siyosatlar (yozish siyosati — umuman yo'q), ko'rinishlar
--       va RPC'lar (matn + chaqiruvlar zanjiri: ruxsatni boshqa RPC orqali tekshiradiganlar ham) = kutilgan ro'yxat; L4b — xatti-harakat
--       bo'yicha (NULL argumentlar bilan: STRICT yoki avval qator qidiradigan RPC'larni ko'rmaydi — ularni L4 zanjiri topadi);
--   (X) qo'shimcha lavozim yo'q; (Q) orqaga qaytarish yo'li: fin-rights.sql «fin_rights_on = off» — siyosatlar, ko'rinishlar,
--       students_billing va sahifa kaliti (kassa_state «accRead») o'chadi; qayta «on» — tiklanadi.
--   Sana belgilari (kasallik kunlari) — 2001-yil: kassa javoblari bugungi sanadan hosil bo'ladi va ular bilan hech qachon to'qnashmaydi.
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub). Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan
--   keyin:  bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-fin-rights.sql
--   (Q-band fin-rights.sql ni «\ir» bilan o'qiydi — test fayli «-f» bilan beriladi yoki migration/ papkasidan ishga tushiriladi.)
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari, kodlar va telefonlar to'qima. Natija: PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.payments) then
    raise exception 'test-fin-rights.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
create or replace function zz.try(p_q text) returns text language plpgsql as $$
declare v_hint text;
begin
  execute p_q; return 'OK';
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  return 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
end $$;
-- INSERT sinovi: triggerlarsiz (session_replication_role = replica) — qatorni faqat RLS qabul qiladi yoki rad etadi.
create or replace function zz.ins(p_uid text, p_q text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('session_replication_role', 'replica', true);
  r := zz.as(p_uid, p_q);
  perform set_config('session_replication_role', 'origin', true);
  return r;
end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
create or replace function zz.cnt(p_uid text, p_rel text) returns text language sql as $$
  select zz.as(p_uid, format('select count(*)::text from public.%I', p_rel)) $$;
-- Ustunlar ro'yxati (vergul bilan, tartibda).
create or replace function zz.cols(p_rel text) returns text language sql as $$
  select string_agg(attname, ',' order by attnum) from pg_attribute
   where attrelid = ('public.' || p_rel)::regclass and attnum > 0 and not attisdropped $$;
-- Skaner: authenticated o'qiy oladigan HAR BIR public jadval / ko'rinishda (p_skip dan tashqari) p_uid ko'radigan va matni p_re ga mos
--   qatorlar — «jadval=soni» ro'yxati (bo'sh bo'lishi kerak). RLS yoki huquq rad etsa (ERR) — o'qib bo'lmaydi, hisoblanmaydi.
create or replace function zz.scan(p_uid text, p_re text, p_skip text[] default '{}') returns text language sql as $$
  select coalesce(string_agg(r || '=' || n, ',' order by r), '') from (
    select c.relname as r, zz.as(p_uid, format('select count(*)::text from public.%I t where t::text ~ %L', c.relname, p_re)) as n
      from pg_class c
     where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p') and not (c.relname = any(p_skip))
       and has_table_privilege('authenticated', c.oid, 'SELECT')) x
   where n !~ '^(0|ERR .*)$' $$;
-- Jadval ustunlari: ko'rinishda ham bor yoki aniq istisno ro'yxatida — qolgani (bo'sh bo'lishi kerak).
create or replace function zz.unclassified(p_tab text, p_view text, p_excluded text[]) returns text language sql as $$
  select coalesce(string_agg(a.attname, ','), '') from pg_attribute a
   where a.attrelid = ('public.' || p_tab)::regclass and a.attnum > 0 and not a.attisdropped and not (a.attname = any(p_excluded))
     and not exists (select 1 from pg_attribute b where b.attrelid = ('public.' || p_view)::regclass and b.attname = a.attname and not b.attisdropped) $$;

-- ---------- Urug' (triggerlarsiz; ismlar, kodlar va telefonlar to'qima) ----------
set local session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles") values
  ('U_DIR','d@x','director','active','[]'), ('U_FM','f@x','finance_mgr','active','[]'), ('U_KAS','k@x','kassir','active','[]'),
  ('U_ACC','a@x','accountant','active','[]'), ('U_ACCB','ab@x','accountant','blocked','[]'),
  ('U_ACCX','ax@x','accountant','active','["kassir","reception","hr","zavuch","teacher"]'),   -- eski (qo'shimchali) qator
  ('U_ACCB2','ab2@x','accountant','active','["kassir"]'),   -- eski qo'shimchali; X9 da bloklanib, blokdan chiqariladi
  ('U_TCH','t@x','teacher','active','[]'), ('U_TX','tx@x','teacher','active','["reception"]'), ('U_NONE','n@x','cleaner','active','[]'),
  ('U_BASE','bs@x','cleaner','active','[]')   -- L1 / L4b solishtirish asosi: rolsiz xodim, hech bir tekshiruv uni o'zgartirmaydi
on conflict (id) do update set role = excluded.role, status = excluded.status, "extraRoles" = excluded."extraRoles";
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]'), ('s2','T-2','Sinov B',6,'B','ru','',2,'[]');
insert into public.student_codes (id, code) values ('s1','K7Q2ZP');
insert into public.student_private (id, "parentPhone", address, health) values ('s1','+998900000001','ZZADDR1 ko''chasi','ZZHEALTH1');
insert into public.teachers (id, "teacherId", name, phone, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','+998900000003','[]');
insert into public.staff (id, "staffId", name, phone, position) values ('st1','IQX-T1','Sinov Xodim','+998900000004','Qorovul');
insert into public.payments (id, "studentId", provider, amount, status, raw, "payerName", "payerPhone", "payerClass", matched, "createdAt", merchant_trans_id, click_trans_id) values
  ('p1','T-1','click',1000000,'applied','{"mode":"freeform","via":"code","phone":"+998900000002"}','T-1 K7Q2ZP','+998900000002','5A',true,'2027-01-04 10:00+05','T-1 K7Q2ZP','777001'),
  ('p2','T-1','cash',500000,'applied','{"manual":true,"method":"cash","date":"2027-01-03","note":"+998900000005 qo''ng''iroq qildi","byUid":"U_KAS"}','Sinov Ota','',null,true,'2027-01-04 11:00+05',null,null),
  ('p3','','click',300000,'reversed','{"needsManualReverse":true,"reverseNote":"Click bekor qildi (som=300000, studentId=)","manualReverseBy":"k@x"}','K7Q2ZP','+998900000006','K7Q2ZP +998900000009',false,'2027-01-04 12:00+05','K7Q2ZP','777002');
insert into public.invoices (id, "studentId", "studentName", month, amount, status, "sickDaysApplied", "sickAmount", "sickNoteRefs", "discountInfo") values
  ('i1','T-1','Sinov A','2027-01',1000000,'paid',2,100000,'{"sn1": ["2001-01-18", "2001-01-19"]}','Monitoring 90–99 · 20% + 2 kasal kun (−100000)');
insert into public.refunds (id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month) values
  ('r1','invoice','i1','T-1','Sinov A',1000,'sinov','d@x','2027-01'), ('r2','payment','p3','','K7Q2ZP',300000,'adashib tushgan','d@x','');
insert into public.expenses (id, date, month, category, amount, note) values ('e1','2027-01-04','2027-01','Kanselyariya',5000,'sinov');
insert into public.credit_ledger (id, "studentId", delta, "balanceAfter", reason) values ('cl1','T-1',100,100,'overpay');
insert into public.student_credit (id, "studentId", credit) values ('T-1','T-1',100);
insert into public.applied_payments (id, "studentId", amount) values ('ap1','T-1',1000000);
insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date) values ('sa1','IQX-T1','Sinov Xodim',1000,'2027-02','2027-02-04');
insert into public.salary_payments (id, "teacherId", "teacherName", month, gross, net, date, "byEmail") values ('sp1','IQX-T1','Sinov Xodim','2027-01',5000,4000,'2027-01-04','f@x');
insert into public.payroll_runs (id, status) values ('2027-01','approved');
insert into public.payroll_lines (id, "runId", "personType", "personId", name, gross, payable, "workedMin", details, "directorNote") values
  ('2027-01__IQX-T1','2027-01','staff','IQX-T1','Sinov Xodim',5000,4000,7200,'{"camera":true,"absent":2,"kasallik":3,"workedMin":7200}','sinov izoh');
insert into public.config (id, "refundPin") values ('security','1234') on conflict (id) do nothing;
insert into public.config (id, "lessonRate") values ('finance', 50000) on conflict (id) do nothing;
insert into public.config (id) values ('salary') on conflict (id) do nothing;
insert into public.config (id, "tenureYears") values ('ltv', 4) on conflict (id) do nothing;
insert into public.staff_checkins (id, "personId", name, day) values ('ck1','IQX-T1','Sinov Xodim','2027-01-04');
insert into public.sick_notes (id, "studentId", "fromDay", "toDay", status) values ('sn1','T-1','2001-01-18','2001-01-19','pending');
insert into public.sms_log (id, "studentId", phone, message) values ('sm1','T-1','+998900000007','sinov');
insert into public.price_table (id, grade, amount) values ('pt1', 5, 1000000);
insert into public.pay_notes (id, note) values ('T-1','sinov');
insert into public.discount_requests (id, "studentId", kind, status) values ('dr1','T-1','none','pending');
insert into public.enrollments (id, name, phone) values ('en1','Sinov Ariza','+998900000008');
insert into public.staff_leaves (id, "refId", name, type, "startDay", "endDay", reason) values ('lv1','st1','Sinov Xodim','kasallik','2027-01-04','2027-01-05','sinov');
insert into public.staff_substitutions (id, day, month, "absentName", "subName") values ('sub1','2027-01-04','2027-01','Sinov A1','Sinov B1');
insert into public.fin_snapshots (id, kind, "asOf", payload, hash) values ('fs1','manual','2027-01-04 10:00+05','{"students":[{"name":"Sinov A"}]}','h');
insert into public.child_claims (id, uid, "studentId", code) values ('U_DIR__T-2','U_DIR','T-2','K7Q2ZP');
insert into public.student_health (id, "studentId", allergies) values ('s1','T-1','ZZALLERGY1');
insert into public.attendance (id, "studentId", "classKey", month, days) values ('att1','T-1','uz-5-A','2027-01','{"04": "absent", "05": "sick"}');
insert into public.grades (id, "studentId", "classKey", year, subjects) values ('gr1','T-1','uz-5-A','2026-2027','{"math": [2, 3]}');
insert into public.monitoring (id, "studentId", "classKey", subject, period, score, status) values ('mon1','T-1','uz-5-A','math','2027-01',41,'approved');
insert into public.applications (id, name, phone, specialty, status) values ('app1','Sinov Nomzod','+998900000010','math','submitted');
update public.users set name = email where id = 'U_KAS';   -- eski ro'yxatdan o'tish shakli: ism o'rnida email (index.html askRole)
update public.fin_org set "kassaGoLive" = app.fin_today() - 1 where id = 'main';
set local session_replication_role = origin;
-- Direktor kassadan qaytarish so'rovini yozadi (KO-2, tasdiqlangan) — surat va hujjat buxgalterga ko'rinadi (kassa_reader).
-- Kamomad oqimi: boshlang'ich qoldiq → kirim (kun ochiladi) → kassir kunni kam pul bilan yopadi → Direktor «xodim zimmasiga» qaror
--   qiladi (kassir HR kartasiga bog'lanmagan — dalolatnoma tomoni ismi bilan; ismi o'rnida email turgan hisob — email chiqmasligi kerak).
--   Har qadam alohida so'rovda (oldingi qadam yozganini keyingisi ko'rishi uchun).
select zz.as('U_DIR', $q$select public.kassa_refund_request('{"target":"invoice","id":"i1","amount":1000,"reason":"sinov qaytarish","payee":"Sinov Ota Onasi","clientRef":"zz-ref-k7a"}'::jsonb) ->> 'ok'$q$) as zz_k0a
\gset
select zz.as('U_DIR', format($q$select public.kassa_opening_set('{"amount":1000000,"startDay":"%s"}') ->> 'ok'$q$, app.fin_today())) as zz_k0b
\gset
select zz.as('U_KAS', $q$select public.kassa_receipt('{"op":"in_other","amount":100000,"partyType":"other","partyName":"Noma''lum shaxs","articleId":"OP-16","basis":"Ariza","note":"Aniqlanmagan tushum","clientRef":"zz-c1-000001"}'::jsonb) ->> 'ok'$q$) as zz_k0c
\gset
select zz.as('U_KAS', format($q$select public.kassa_day_close('{"day":"%s","counted":1090000}') ->> 'ok'$q$, app.fin_today())) as zz_k0d
\gset
select zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L) ->> ''ok''', (select "diffDocId" from public.cash_days where day = app.fin_today()), 'employee', 'Kassir yozma roziligi bilan')) as zz_k0e
\gset

-- ---------- (R) ruxsat etilgan jadvallar ----------
select zz.chk('R' || x.n || ' buxgalter ' || x.t || ' ni o''qiydi', zz.cnt('U_ACC', x.t), '^1$')
  from unnest(array['expenses','credit_ledger','student_credit','staff_advances','payroll_runs']) with ordinality x(t, n);
select zz.chk('R7 config: faqat finance va salary (security / ltv — yo''q)',
  zz.as('U_ACC', $q$select string_agg(id, ',' order by id) from public.config where id in ('finance','salary','security','ltv')$q$), '^finance,salary$');
select zz.chk('R8 bloklangan buxgalter hech narsani ko''rmaydi',
  zz.as('U_ACCB', 'select ((select count(*) from public.invoices_acc) + (select count(*) from public.payroll_runs) + (select count(*) from public.payments_acc) + (select count(*) from public.payroll_lines_acc) + (select count(*) from public.students_billing))::text'), '^0$');
select zz.chk('R9 o''qituvchi buxgalter jadvallarini ko''rmaydi', zz.cnt('U_TCH', 'payroll_runs') || '/' || zz.cnt('U_TCH', 'invoices') || '/' || zz.cnt('U_TCH', 'payments_acc') || '/' || zz.cnt('U_TCH', 'invoices_acc'), '^0/0/0/0$');

-- ---------- (V) «*_acc» ko'rinishlari ----------
select zz.chk('V1 buxgalter to''lovlarni payments_acc orqali ko''radi (3), xom payments — 0',
  zz.cnt('U_ACC', 'payments_acc') || '/' || zz.cnt('U_ACC', 'payments'), '^3/0$');
select zz.chk('V2 payments_acc ustunlari (to''lovchi matni — ism, «sinf», merchant_trans_id; telefon — yo''q; raw — tozalangan)', zz.cols('payments_acc'),
  '^id,studentId,invoiceId,provider,amount,status,click_trans_id,merchant_prepare_id,merchant_confirm_id,transId,matched,createdAt,statusAt,cashDocId,fiscalNo,raw$');
select zz.chk('V3 payments: yangi ustun ko''rinishda yoki istisnoda bo''lishi shart (sinflanmagan ustun yo''q)',
  zz.unclassified('payments', 'payments_acc', array['payerName','payerPhone','payerClass','merchant_trans_id']), '^$');
select zz.chk('V4 payments_acc.raw — faqat ruxsat etilgan kalitlar (to''lov kuni, qo''lda, qaytarish belgilari)',
  zz.as('U_ACC', $q$select string_agg(distinct k, ',' order by k) from public.payments_acc, jsonb_object_keys(raw) k$q$),
  '^date,manual,method,needsManualReverse,reverseNote$');
select zz.chk('V5 refunds_acc: byEmail yo''q; to''lov qaytarishida studentName (to''lovchi matni) — bo''sh',
  coalesce(zz.cols('refunds_acc'), '') || ' | ' || zz.as('U_ACC', $q$select string_agg(id || '=' || coalesce("studentName", '∅'), ',' order by id) from public.refunds_acc$q$),
  '^id,target,targetId,studentId,studentName,amount,reason,month,createdAt,byUid,method,cashDocId \| r1=Sinov A,r2=∅$');
select zz.chk('V6 refunds: sinflanmagan ustun yo''q', zz.unclassified('refunds', 'refunds_acc', array['byEmail']), '^$');
select zz.chk('V7 salary_payments_acc: byEmail yo''q, qator ko''rinadi',
  (zz.cols('salary_payments_acc') !~ 'byEmail')::text || '/' || zz.cnt('U_ACC', 'salary_payments_acc') || '/' || zz.cnt('U_ACC', 'salary_payments'), '^true/1/0$');
select zz.chk('V8 salary_payments: sinflanmagan ustun yo''q', zz.unclassified('salary_payments', 'salary_payments_acc', array['byEmail']), '^$');
select zz.chk('V9 payroll_lines_acc: davomat tafsiloti, workedMin, Direktor izohi yo''q; details — faqat camera',
  zz.cols('payroll_lines_acc') || ' | ' || zz.as('U_ACC', $q$select details::text from public.payroll_lines_acc$q$) || ' | ' || zz.cnt('U_ACC', 'payroll_lines'),
  '^id,runId,personType,personId,refId,name,gross,deduction,subBonus,advance,carryIn,payable,details,needsDirector,directorOkBy,directorOkAt \| \{"camera": true\} \| 0$');
select zz.chk('V10 payroll_lines: sinflanmagan ustun yo''q', zz.unclassified('payroll_lines', 'payroll_lines_acc', array['workedMin','directorNote']), '^$');
select zz.chk('V11 «*_acc» ko''rinishlari boshqa rollarga bo''sh (Direktor / MM / kassir / o''qituvchi)',
  (select string_agg(zz.cnt(u, v), '' order by u, v) from unnest(array['U_DIR','U_FM','U_KAS','U_TCH']) u,
     unnest(array['invoices_acc','payments_acc','refunds_acc','salary_payments_acc','payroll_lines_acc']) v), '^0{20}$');
select zz.chk('V12 anon «*_acc» ko''rinishlarini o''qiy olmaydi',
  zz.cnt(null, 'payments_acc') || ' | ' || zz.cnt(null, 'payroll_lines_acc') || ' | ' || zz.cnt(null, 'invoices_acc'), '^ERR 42501.* \| ERR 42501.* \| ERR 42501');
select zz.chk('V13 buxgalter ko''rinishga yoza olmaydi',
  zz.as('U_ACC', $q$insert into public.payments_acc (id, amount) values ('pX', 1) returning id$q$), '^ERR');
select zz.chk('V14 applied_payments buxgalterga yopiq (ekrani yo''q)', zz.cnt('U_ACC', 'applied_payments'), '^0$');
select zz.chk('V15 buxgalter fakturalarni invoices_acc orqali ko''radi (1), xom invoices — 0',
  zz.cnt('U_ACC', 'invoices_acc') || '/' || zz.cnt('U_ACC', 'invoices'), '^1/0$');
select zz.chk('V16 invoices_acc: kasallik sanalari (sickNoteRefs) yo''q; chegirma sababi, kasal kunlar soni va summasi — bor',
  (zz.cols('invoices_acc') !~ 'sickNoteRefs')::text || ' | ' ||
  zz.as('U_ACC', $q$select "sickDaysApplied" || '/' || trim_scale("sickAmount") || '/' || "discountInfo" from public.invoices_acc$q$),
  '^true \| 2/100000/Monitoring 90–99');
select zz.chk('V17 invoices: yangi ustun ko''rinishda yoki istisnoda bo''lishi shart (sinflanmagan ustun yo''q)',
  zz.unclassified('invoices', 'invoices_acc', array['sickNoteRefs']), '^$');

-- ---------- (K) maxfiy kod va telefon ----------
--   Buxgalter o'qiy oladigan HAR BIR jadval / ko'rinishda (dinamik: SELECT huquqi bor barcha public obyektlar — kassa jadvallari va
--   kelajakdagi yangilari ham) qatorlar matni: kod, telefon, boshqa xodim emaili, kasallik sanalari yo'q.
select zz.chk('K0 sinov sharti: qaytarish so''rovi, boshlang''ich qoldiq, kirim, kamomad bilan yopilgan kun, Direktor qarori — hammasi bajarildi',
  :'zz_k0a' || '/' || :'zz_k0b' || '/' || :'zz_k0c' || '/' || :'zz_k0d' || '/' || :'zz_k0e', '^true/true/true/true/true$');
select zz.chk('K1 maxfiy ota-ona kodi (K7Q2ZP) buxgalter o''qiy oladigan hech bir joyda yo''q', zz.scan('U_ACC', '(?i)K7Q2ZP'), '^$');
select zz.chk('K2 telefon raqami (+998…) buxgalter o''qiy oladigan hech bir joyda yo''q', zz.scan('U_ACC', '\+?998[0-9]{9}'), '^$');
select zz.chk('K5 boshqa foydalanuvchilar emaili (…@x) buxgalter o''qiy oladigan hech bir joyda yo''q (o''z qatori — users — bundan tashqari)',
  zz.scan('U_ACC', '[A-Za-z0-9._-]+@x\M', array['users']), '^$');
select zz.chk('K6 kasallik sanalari (2001-01-18/19) buxgalter o''qiy oladigan hech bir joyda yo''q', zz.scan('U_ACC', '2001-01-1[89]'), '^$');
select zz.chk('K7 qaytarish so''rovi suratida Direktor emaili emas, uid',
  (select ("sourceSnapshot" ->> 'byUid') || '/' || ("sourceSnapshot" ? 'by')::text from public.cash_docs where "sourceId" = 'kref_zz-ref-k7a'), '^U_DIR/false$');
select zz.chk('K8 kassa javoblari (buxgalter): kod, telefon, email, kasallik sanasi yo''q',
  (select coalesce(string_agg(f, ','), '') from (
     select f, zz.as('U_ACC', 'select ' || f || '::text') as r
       from unnest(array['public.kassa_refs()', 'public.kassa_people()', 'public.kassa_state(''main'')', 'public.kassa_overview(''main'')',
                         'public.kassa_checks(''main'')', 'public.kassa_kpi(''main'')', 'public.fin_snapshots_list()',
                         format('public.kassa_day_book(''main'', %L::date)', app.fin_today()),
                         format('public.kassa_journal(''main'', %L::date, %L::date)', app.fin_today() - 7, app.fin_today()),
                         format('public.kassa_matrix(''main'', %L)', to_char(app.fin_today(), 'YYYY-MM')),
                         format('public.kassa_doc_get(%L)', (select id from public.cash_docs where "sourceId" = 'kref_zz-ref-k7a')),
                         format('public.kassa_doc_get(%L)', (select id from public.cash_docs where op = 'out_shortage')),
                         format('public.kassa_doc_get(%L)', (select id from public.cash_docs where op = 'nc_shortage_dec'))]) f) x
    where r ~ '^ERR' or r ~ '(?i)K7Q2ZP' or r ~ '\+?998[0-9]{9}' or r ~ '[A-Za-z0-9._-]+@x\M' or r ~ '2001-01-1[89]'), '^$');
select zz.chk('K9 kamomad dalolatnomasi tomoni: ism o''rnida email turgan kassir — email emas, «Kassir»; kassirlar ro''yxatida ham email yo''q',
  (select "partyType" || '/' || coalesce("partyName", '∅') from public.cash_docs where op = 'nc_shortage_dec') || ' | ' ||
  zz.as('U_ACC', $q$select (public.kassa_refs() -> 'operators')::text$q$), '^other/Kassir \| \[\{"uid": "U_KAS", "name": "U_KAS"\}\]$');
select zz.chk('K10 manzil va sog''liq belgilari (ZZADDR1 / ZZHEALTH1 / ZZALLERGY1) buxgalter o''qiy oladigan hech bir joyda yo''q',
  zz.scan('U_ACC', '(ZZADDR1|ZZHEALTH1|ZZALLERGY1)'), '^$');
select zz.chk('K3 buxgalter farzand biriktira olmaydi (kodni bilsa ham)',
  zz.as('U_ACC', $q$select public.claim_child('T-1', 'K7Q2ZP')::text$q$) || ' | ' || (select count(*)::text from public.child_claims where uid = 'U_ACC'),
  'Buxgalter hisobiga farzand biriktirilmaydi.* \| 0$');
select zz.chk('K4 claim_child boshqa (ota-ona) hisob uchun ishlaydi', zz.as('U_NONE', $q$select (public.claim_child('T-1', 'K7Q2ZP') ->> 'ok')$q$), '^true$');

-- ---------- (B) students_billing ----------
select zz.chk('B1 buxgalter o''quvchilarni billing ko''rinishidan ko''radi (2)', zz.cnt('U_ACC', 'students_billing'), '^2$');
select zz.chk('B2 xom students jadvali buxgalterga yopiq', zz.cnt('U_ACC', 'students'), '^0$');
select zz.chk('B3 students_billing ustunlari o''zgarmagan (telefon / ball / davomat / rasm yo''q)', zz.cols('students_billing'),
  '^id,studentId,name,grade,classLetter,track,lang,payStatus,activeFrom,stopFrom,pauses,order$');
select zz.chk('B4 MM va kassir uchun students_billing o''zgarmagan; o''qituvchi — 0', zz.cnt('U_FM', 'students_billing') || zz.cnt('U_KAS', 'students_billing') || zz.cnt('U_TCH', 'students_billing'), '^220$');
select zz.chk('B5 anon students_billing ni o''qiy olmaydi', zz.cnt(null, 'students_billing'), '^ERR 42501');

-- ---------- (D) D6 / D7: yopiq ----------
select zz.chk('D0 urug'' tekshiruvi: D-bandidagi har jadvalda kamida 1 qator bor (aks holda «0» hech narsani isbotlamaydi)',
  (select coalesce(string_agg(t, ','), '') from unnest(array['student_private','student_codes','student_health','teachers','staff','staff_checkins','sick_notes',
     'fin_snapshots','sms_log','price_table','pay_notes','discount_requests','enrollments','staff_leaves','staff_substitutions','refunds','child_claims','applied_payments',
     'attendance','grades','monitoring','applications']) t
    where not (xpath('/row/c/text()', query_to_xml(format('select exists(select 1 from public.%I) as c', t), false, true, '')))[1]::text::boolean), '^$');
select zz.chk('D' || x.n || ' buxgalterga yopiq: ' || x.t, zz.cnt('U_ACC', x.t), '^0$')
  from unnest(array['student_private','student_phones','student_codes','student_health','teachers','staff','staff_checkins','sick_notes',
                    'fin_snapshots','sms_log','price_table','pay_notes','discount_requests','enrollments','staff_leaves','staff_substitutions',
                    'refunds','child_claims','attendance','grades','monitoring','applications']) with ordinality x(t, n);
select zz.chk('DU users: faqat o''z qatori', zz.as('U_ACC', 'select string_agg(id, '','') from public.users'), '^U_ACC$');

-- ---------- (W) yozish va pul RPC'lari yo'q ----------
--   So'rovda ustun o'qilmaydi (set id = doimiy, returning 1, WHERE yo'q) — shuning uchun faqat UPDATE / DELETE siyosatlari ishlaydi
--   (ustun o'qilsa, PostgreSQL SELECT siyosatini ham qo'shadi va xom jadvalda bu tekshiruv doim 0 qaytarardi).
--   Kutilgan natija aniq: authenticated'da huquq bor jadvalda — 0 qator (RLS o'tkazmadi), huquq yo'q jadvalda — «permission denied»
--   (biznes triggeri bergan boshqa 42501 tekshiruvni «o'tkazib» yubormaydi).
select zz.chk('W' || x.n || ' buxgalter ' || x.t || ' ni o''zgartira olmaydi',
  zz.as('U_ACC', format($q$with u as (update public.%I set id = 'zz-w' returning 1) select count(*)::text from u$q$, x.t)),
  case when has_table_privilege('authenticated', ('public.' || x.t)::regclass, 'UPDATE') then '^0$' else '^ERR 42501 .*permission denied' end)
  from unnest(array['invoices','expenses','credit_ledger','student_credit','staff_advances','payroll_runs','config','payments',
                    'refunds','salary_payments','payroll_lines']) with ordinality x(t, n);
select zz.chk('W' || x.n || 'd buxgalter ' || x.t || ' dan o''chira olmaydi',
  zz.as('U_ACC', format($q$with d as (delete from public.%I returning 1) select count(*)::text from d$q$, x.t)),
  case when has_table_privilege('authenticated', ('public.' || x.t)::regclass, 'DELETE') then '^0$' else '^ERR 42501 .*permission denied' end)
  from unnest(array['invoices','expenses','credit_ledger','student_credit','staff_advances','payroll_runs','config','payments',
                    'refunds','salary_payments','payroll_lines']) with ordinality x(t, n);
select zz.chk('W' || x.n || 'i buxgalter ' || x.t || ' ga qator qo''sha olmaydi (triggerlarsiz — faqat RLS qaror qiladi)',
  zz.ins('U_ACC', format('insert into public.%I %s returning 1', x.t, x.v)), '^ERR 42501 .*(row-level security|permission denied)')
  from (values
    (1, 'invoices', $v$(id, "studentId", month, amount, status) values ('zz-wi', 'T-1', '2027-02', 1, 'pending')$v$),
    (2, 'expenses', $v$(id, date, month, category, amount, method) values ('zz-we', '2027-02-04', '2027-02', 'Boshqa', 1, 'bank')$v$),
    (3, 'credit_ledger', $v$(id, "studentId", delta, "balanceAfter", reason) values ('zz-wc', 'T-1', 1, 1, 'manual')$v$),
    (4, 'student_credit', $v$(id, "studentId", credit) values ('T-2', 'T-2', 1)$v$),
    (5, 'staff_advances', $v$(id, "teacherId", "teacherName", amount, month, date) values ('zz-wa', 'IQX-T1', 'Sinov Xodim', 1, '2027-02', '2027-02-04')$v$),
    (6, 'payroll_runs', $v$(id, status) values ('2027-03', 'draft')$v$),
    (7, 'config', $v$(id) values ('zz-wconf')$v$),
    (8, 'payments', $v$(id, "studentId", provider, amount, status) values ('zz-wp', 'T-1', 'cash', 1, 'applied')$v$),
    (9, 'refunds', $v$(target, "targetId", "studentId", amount, reason, month) values ('invoice', 'i1', 'T-1', 1, 'zz', '2027-02')$v$),
    (10, 'salary_payments', $v$("teacherId", "teacherName", month, gross, net, date) values ('IQX-T1', 'Sinov Xodim', '2027-02', 1, 1, '2027-02-04')$v$),
    (11, 'payroll_lines', $v$(id, "runId", "personType", "personId", name, gross, payable) values ('zz-wl', '2027-01', 'staff', 'IQX-T1', 'x', 1, 1)$v$)) x(n, t, v);
select zz.chk('W20 buxgalter naqdsiz xarajat qo''sha olmaydi (triggerlar bilan — RLS rad etadi)',
  zz.as('U_ACC', $q$insert into public.expenses (id, date, month, category, amount, method) values ('eX','2027-02-04','2027-02','Boshqa',1,'bank') returning id$q$),
  '^ERR 42501 .*row-level security');
select zz.chk('W21 buxgalter pul RPC''larini chaqira olmaydi (qo''lda to''lov, avans qo''shish, vedomost yuborish)',
  zz.as('U_ACC', $q$select public.record_manual_payment('zz-pay-1', 'T-1', 1000, 'bank', null, null, null, null, null, null)::text$q$) || ' | ' ||
  zz.as('U_ACC', $q$select public.add_credit('T-1', 1000, 'sinov', 'manual', 'zz-ref-1')::text$q$) || ' | ' ||
  zz.as('U_ACC', $q$select public.payroll_submit('2027-02', '[]'::jsonb, null)::text$q$),
  '^ERR 42501.* \| ERR 42501.* \| ERR 42501');
select zz.chk('W22 buxgalter xarajatni o''chira olmaydi',
  zz.as('U_ACC', $q$with d as (delete from public.expenses returning 1) select count(*)::text from d$q$), '^0$');

-- ---------- (L) yopiq ro'yxat ----------
--   Buxgalterga TRUE, rolsiz xodimga (U_BASE — hech bir tekshiruv o'zgartirmaydi; U_NONE K4 da ota-ona bo'lib qolgan) FALSE
--   bo'ladigan argumentsiz yordamchilar (dinamik: yangi yordamchi qo'shilsa ham topiladi); ular (yoki 'accountant' so'zi) ishlatilgan
--   har bir SELECT/ALL siyosat, ko'rinish va SECURITY DEFINER RPC — kutilgan ro'yxatda; yozish siyosati — umuman yo'q.
create temp table zz_acc_fns on commit drop as
  select p.proname from pg_proc p
   where p.pronamespace = 'app'::regnamespace and p.pronargs = 0 and p.prorettype = 'boolean'::regtype
     and zz.as('U_ACC', format('select app.%I()::text', p.proname)) = 'true'
     and zz.as('U_BASE', format('select app.%I()::text', p.proname)) is distinct from 'true';
create temp table zz_acc_re on commit drop as
  select '(\m(app\.)?(' || string_agg(proname, '|') || ')\s*\(\s*\)|accountant)' as re from zz_acc_fns;
-- Bilvosita: shu yordamchilarni chaqiradigan argumentli app funksiyalari (masalan kelajakdagi «can_read_x(id)») — ular orqali
--   ochilgan siyosatlar ham topilsin. (role_set / u_has kabi 'accountant' so'zini faqat istisno ro'yxatida tutadiganlar — yo'q.)
create temp table zz_acc_re2 on commit drop as
  select '(app\.(' || coalesce(string_agg(distinct p.proname, '|'), 'zz_none') || ')\()' as re from pg_proc p
   where p.pronamespace = 'app'::regnamespace and p.pronargs > 0
     and p.prosrc ~ ('\m(app\.)?(' || (select string_agg(proname, '|') from zz_acc_fns) || ')\s*\(\s*\)');
select zz.chk('L1 buxgalterga true yordamchilar', (select string_agg(proname, ',' order by proname) from zz_acc_fns), '^acc_read,fin_list2,is_accountant,kassa_reader$');
select zz.chk('L2 YOPIQ RO''YXAT: buxgalterni o''tkazadigan siyosatlar jadvallari',
  (select string_agg(distinct p.tablename, ',' order by p.tablename) from pg_policies p, zz_acc_re
    , zz_acc_re2 where p.schemaname = 'public' and p.cmd in ('SELECT', 'ALL') and (coalesce(p.qual, '') ~ zz_acc_re.re or coalesce(p.qual, '') ~ zz_acc_re2.re)),
  '^cash_counts,cash_day_events,cash_days,cash_desks,cash_doc_lines,cash_docs,cash_prints,config,credit_ledger,expenses,fin_articles,fin_category_map,fin_counterparties,fin_op_rules,fin_org,fin_signatories,gl_accounts,payment_allocations,payroll_runs,staff_advances,student_credit$');
select zz.chk('L2w YOPIQ RO''YXAT: buxgalterni o''tkazadigan YOZISH siyosati yo''q (INSERT / UPDATE / DELETE / ALL; USING va WITH CHECK)',
  (select coalesce(string_agg(distinct p.tablename || ':' || p.cmd, ','), '') from pg_policies p, zz_acc_re, zz_acc_re2
    where p.schemaname = 'public' and p.cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
      and ((coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '')) ~ zz_acc_re.re
        or (coalesce(p.qual, '') || ' ' || coalesce(p.with_check, '')) ~ zz_acc_re2.re)), '^$');
select zz.chk('L3 YOPIQ RO''YXAT: buxgalterni o''tkazadigan ko''rinishlar',
  (select string_agg(v.viewname, ',' order by v.viewname) from pg_views v, zz_acc_re, zz_acc_re2
    where v.schemaname = 'public' and (v.definition ~ zz_acc_re.re or v.definition ~ zz_acc_re2.re)),
  '^invoices_acc,payments_acc,payroll_lines_acc,refunds_acc,salary_payments_acc,students_billing$');
--   L4: mijoz chaqira oladigan SECURITY DEFINER RPC'lar — matnida yordamchi (yoki 'accountant' so'zi) bor, YOKI shunday RPC'ni
--   chaqiradi (zanjir: ruxsatni boshqa RPC orqali tekshiradigan kassa_overview kabilar; STRICT bo'lsa ham, avval qator qidirsa ham).
create temp table zz_l4 on commit drop as
with recursive base as (
  select p.oid, p.proname, p.prosrc from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
), clo(proname) as (
  select b.proname from base b, zz_acc_re, zz_acc_re2 where b.prosrc ~ zz_acc_re.re or b.prosrc ~ zz_acc_re2.re
  union
  select b.proname from base b, clo where b.prosrc ~ ('\m(public\.)?' || clo.proname || '\s*\(') and b.proname <> clo.proname
) select distinct proname from clo;
select zz.chk('L4 YOPIQ RO''YXAT: buxgalterni o''tkazadigan mijoz RPC''lari (matn + chaqiruvlar zanjiri)',
  (select string_agg(proname, ',' order by proname) from zz_l4),
  '^claim_child,fin_counterparty_save,fin_snapshot_get,fin_snapshots_list,kassa_adv_report,kassa_adv_report_void,kassa_checks,kassa_day_book,kassa_day_verify,kassa_doc_approve,kassa_doc_cancel,kassa_doc_get,kassa_doc_reject,kassa_doc_void,kassa_journal,kassa_journal_export,kassa_kpi,kassa_matrix,kassa_month_pack,kassa_overview,kassa_people,kassa_print_mark,kassa_refs,kassa_state$');
select zz.chk('L5 rls-initplan: buxgalter siyosatlari o''ralgan (o''ralmagan app.* chaqiruvi — faqat users)',
  (select coalesce(string_agg(distinct tablename, ','), '') from pg_policies where schemaname = 'public'
     and (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~ '(?<!SELECT )app\.(is_accountant|kassa_reader|fin_list2)\(\)'), '^$');

select zz.chk('L6 ko''rinishlar: security_barrier bor, security_invoker yo''q (egasi nomidan, filtr chetlab o''tilmaydi)',
  (select string_agg(c.relname || '=' || (coalesce(c.reloptions, '{}') @> array['security_barrier=true'])::text
                     || (not coalesce(array_to_string(c.reloptions, ','), '') ~ 'security_invoker')::text, ',' order by c.relname)
     from pg_class c where c.relnamespace = 'public'::regnamespace
      and c.relname in ('invoices_acc','payments_acc','refunds_acc','salary_payments_acc','payroll_lines_acc','students_billing')),
  '^invoices_acc=truetrue,payments_acc=truetrue,payroll_lines_acc=truetrue,refunds_acc=truetrue,salary_payments_acc=truetrue,students_billing=truetrue$');
select zz.chk('L7 ko''rinishlar huquqi: authenticated — faqat SELECT, anon — hech narsa; «*_acc» avtomatik yangilanmaydi',
  (select string_agg(v || '=' || has_table_privilege('authenticated', ('public.' || v)::regclass, 'SELECT')::text
                       || (has_table_privilege('authenticated', ('public.' || v)::regclass, 'INSERT,UPDATE,DELETE'))::text
                       || (has_table_privilege('anon', ('public.' || v)::regclass, 'SELECT,INSERT,UPDATE,DELETE'))::text, ',' order by v)
     from unnest(array['invoices_acc','payments_acc','refunds_acc','salary_payments_acc','payroll_lines_acc','students_billing']) v)
  || ' | ' || (select string_agg(is_updatable || is_insertable_into, ',' order by table_name) from information_schema.views
                where table_schema = 'public' and table_name in ('invoices_acc','payments_acc','refunds_acc','salary_payments_acc','payroll_lines_acc')),
  '^invoices_acc=truefalsefalse,payments_acc=truefalsefalse,payroll_lines_acc=truefalsefalse,refunds_acc=truefalsefalse,salary_payments_acc=truefalsefalse,students_billing=truefalsefalse \| NONO,NONO,NONO,NONO,NONO$');

-- L4b: xatti-harakat bo'yicha — authenticated chaqira oladigan har bir SECURITY DEFINER RPC buxgalter (U_ACC) va rolsiz xodim (U_BASE)
--   nomidan bo'sh (NULL) argumentlar bilan chaqiriladi; javobi farq qiladiganlari (uid / email / rol nomi tenglashtirilgan) = buxgalterni
--   boshqacha ko'radigan RPC'lar. Matnda yordamchi ko'rinmasa ham (masalan, ruxsatni boshqa RPC orqali tekshiradigan kassa_overview) topiladi;
--   STRICT yoki argumentini avval qidiradigan RPC'larni NULL bilan ko'rib bo'lmaydi — ularni L4 zanjiri topadi.
--   Chaqiruvlarning har qanday ta'siri savepoint bilan bekor qilinadi (natija psql o'zgaruvchisida).
savepoint zz_l4b_sp;
create temp table zz_l4b as
  select p.proname,
         regexp_replace(zz.as('U_ACC', format('select left(public.%I(%s)::text, 2000)', p.proname, (select coalesce(string_agg('null', ','), '') from generate_series(1, p.pronargs))))
                        , '(U_ACC|a@x|accountant)', '#', 'g') as r_acc,
         regexp_replace(zz.as('U_BASE', format('select left(public.%I(%s)::text, 2000)', p.proname, (select coalesce(string_agg('null', ','), '') from generate_series(1, p.pronargs))))
                        , '(U_BASE|bs@x|cleaner)', '#', 'g') as r_base
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prokind = 'f' and has_function_privilege('authenticated', p.oid, 'execute');
select (select count(*) from zz_l4b) || ':' || coalesce((select string_agg(proname, ',' order by proname) from zz_l4b where r_acc is distinct from r_base), '') as zz_l4b_res
\gset
rollback to savepoint zz_l4b_sp;
select zz.chk('L4b YOPIQ RO''YXAT (xatti-harakat): buxgalterga boshqacha javob beradigan RPC''lar (oldida — tekshirilgan RPC''lar soni)',
  :'zz_l4b_res',
  '^[0-9]{2,}:claim_child,fin_counterparty_save,fin_snapshot_get,fin_snapshots_list,kassa_adv_report,kassa_adv_report_void,kassa_checks,kassa_day_book,kassa_day_verify,kassa_doc_approve,kassa_doc_cancel,kassa_doc_get,kassa_doc_reject,kassa_doc_void,kassa_journal,kassa_journal_export,kassa_kpi,kassa_matrix,kassa_month_pack,kassa_overview,kassa_people,kassa_print_mark,kassa_refs,kassa_state$');

-- ---------- (P) pul va yozish RPC'lari: buxgalter (va eski qo'shimchali buxgalter) — 42501 ----------
create temp table zz_money on commit drop as
  select p.oid, p.proname, p.pronargs from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any(array[
     'record_manual_payment','apply_payment','apply_to_invoice','split_payment','assign_payment','reverse_payment','refund_invoice',
     'add_credit','adjust_credit','reattribute_avans','cancel_invoice','reprice_invoice','delete_unpaid_invoice',
     'kassa_receipt','kassa_payout_request','kassa_doc_pay','kassa_salary_pay','kassa_refund_request','kassa_offset',
     'kassa_day_close','kassa_day_z','kassa_handover','kassa_day_reopen','kassa_opening_set','kassa_shortage_decide',
     'fin_period_lock','fin_snapshot_take','fin_org_set','fin_signatory_save','payroll_submit','payroll_decide','payroll_approve_line',
     'payroll_reopen']);
select zz.chk('P1 tekshiriladigan pul RPC''lari soni (ro''yxatdagi nomlar bazada bor)', (select (count(*) >= 30)::text from zz_money), '^true$');
select zz.chk('P2 buxgalter: har bir pul / yozish RPC''i 42501 bilan rad etadi',
  (select coalesce(string_agg(proname || ' → ' || left(r, 60), '; '), '') from (
     select m.proname, zz.as('U_ACC', format('select public.%I(%s)::text', m.proname, (select string_agg('null', ',') from generate_series(1, m.pronargs)))) r
       from zz_money m) x where r !~ '^ERR 42501'), '^$');
select zz.chk('P3 eski qo''shimchali buxgalter (kassir, HR, qabulxona …): ham 42501',
  (select coalesce(string_agg(proname || ' → ' || left(r, 60), '; '), '') from (
     select m.proname, zz.as('U_ACCX', format('select public.%I(%s)::text', m.proname, (select string_agg('null', ',') from generate_series(1, m.pronargs)))) r
       from zz_money m) x where r !~ '^ERR 42501'), '^$');

-- ---------- (X) qo'shimcha lavozim yo'q ----------
select zz.chk('X1 eski qo''shimchali buxgalter: rollar faqat {accountant}', zz.as('U_ACCX', 'select app.role_set()::text'), '^\{accountant\}$');
select zz.chk('X2 qo''shimchasi kassir bo''lsa ham kassa operatori emas', zz.as('U_ACCX', 'select app.kassa_operator()::text'), '^false$');
select zz.chk('X3 qo''shimcha qabulxona / O''IBDO'' / HR — o''quvchi va xodim ma''lumoti yopiq',
  zz.cnt('U_ACCX', 'students') || zz.cnt('U_ACCX', 'student_private') || zz.cnt('U_ACCX', 'teachers') || zz.cnt('U_ACCX', 'student_phones'), '^0000$');
select zz.chk('X4 Direktor buxgalterga qo''shimcha lavozim bera olmaydi',
  zz.as('U_DIR', $q$update public.users set "extraRoles" = '["kassir"]' where id = 'U_ACC' returning "extraRoles"::text$q$), '^ERR 22023');
select zz.chk('X5 asosiy rol buxgalter bo''lganda qo''shimchalar tozalanadi',
  zz.as('U_DIR', $q$update public.users set role = 'accountant' where id = 'U_TX' returning "extraRoles"::text$q$), '^\[\]$');
select zz.chk('X6 app.u_has: buxgalterning qo''shimchasi hisobga olinmaydi; boshqa rolda — hisobga olinadi',
  (select app.u_has('accountant', '["kassir"]'::jsonb, 'kassir')::text || '/' || app.u_has('guard', '["kassir"]'::jsonb, 'kassir')::text), '^false/true$');
select zz.chk('X7 kassa: qo''shimchasi kassir bo''lgan buxgalter «operatorlar» ro''yxatida yo''q (smena topshirish)',
  (zz.as('U_DIR', $q$select (public.kassa_refs() -> 'operators')::text$q$) !~ 'U_ACCX')::text, '^true$');

select zz.chk('X8 yangi buxgalter hisobi qo''shimcha lavozim bilan yaratilmaydi',
  zz.try($q$insert into public.users (id, email, role, status, "extraRoles") values ('U_NEWACC','na@x','accountant','active','["kassir"]')$q$), '^ERR 22023');
select zz.chk('X9a eski qo''shimchali buxgalterni bloklash va blokdan chiqarish (auth-server RPC''lari)',
  (public.user_block('U_ACCB2', 'U_DIR') ->> 'ok') || '/' || (public.user_unblock('U_ACCB2', 'U_DIR') ->> 'ok'), '^true/true$');
select zz.chk('X9b blokdan chiqqan buxgalterning eski qo''shimchalari tozalangan',
  (select role || ':' || "extraRoles"::text from public.users where id = 'U_ACCB2'), '^accountant:\[\]$');

-- ---------- (Q) orqaga qaytarish yo'li: fin-rights.sql «fin_rights_on = off» bilan — siyosat va ko'rinishlar o'chadi; qayta «on» — tiklanadi ----------
savepoint zz_q;
\set iqror_chain 1
\set fin_rights_on off
\ir fin-rights.sql
\unset fin_rights_on
select (select count(*) from pg_policies where schemaname = 'public' and policyname = tablename || '_acc_sel')
       || '/' || (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace
                    and (c.relname in ('invoices_acc','payments_acc','refunds_acc','salary_payments_acc','payroll_lines_acc') or obj_description(c.oid, 'pg_class') like 'F1.21:%'))
       || '/' || zz.cnt('U_ACC', 'expenses') || zz.cnt('U_ACC', 'payroll_runs') || zz.cnt('U_ACC', 'config') || zz.cnt('U_ACC', 'credit_ledger')
       || '/' || zz.cnt('U_ACC', 'students_billing') || '/' || zz.as('U_ACC', $q$select public.kassa_state('main') ->> 'accRead'$q$)
       || '/' || zz.cnt('U_FM', 'students_billing') as zz_q1
\gset
\ir fin-rights.sql
select (select count(*) from pg_policies where schemaname = 'public' and policyname = tablename || '_acc_sel')
       || '/' || (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and obj_description(c.oid, 'pg_class') like 'F1.21:%')
       || '/' || zz.cnt('U_ACC', 'invoices_acc') || zz.cnt('U_ACC', 'expenses') || zz.cnt('U_ACC', 'payments_acc')
       || '/' || zz.cnt('U_ACC', 'students_billing') || '/' || zz.as('U_ACC', $q$select public.kassa_state('main') ->> 'accRead'$q$) as zz_q2
\gset
rollback to savepoint zz_q;
\unset iqror_chain
select zz.chk('Q1 orqaga qaytarish (fin_rights_on = off): siyosatlar va ko''rinishlar o''chdi, buxgalter o''qimaydi (students_billing ham), sahifa kaliti o''chiq; MM — o''zgarmagan',
  :'zz_q1', '^0/0/0000/0/false/2$');
select zz.chk('Q2 qayta yoqish (fin_rights_on = on): 6 siyosat, 5 ko''rinish, students_billing va sahifa kaliti tiklandi', :'zz_q2', '^6/5/113/2/true$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 400), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
