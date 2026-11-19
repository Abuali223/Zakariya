-- =====================================================================
-- test-audit-10-tolov.sql — audit-10-tolov.sql (to'liq audit, 2026-11-18) sinovi:
--   (A) A4-01 to'lov qatori faqat ishonchli yo'ldan: kassir / moliya REST orqali yoza olmaydi, Direktor — faqat sahifadagi ikki amal;
--       RF-04 — mavjud (yoki o'zi yozgan) qator bilan apply_payment / apply_to_invoice pulsiz qo'llamaydi; RPC yo'llari ishlaydi;
--   (B) A4-02 moliya rollari fakturani «to'landi» / 0 so'm qila olmaydi (reprice_invoice, to'g'ridan-to'g'ri UPDATE / INSERT);
--   (C) A4-03 avans (qayta hisoblash, aniq to'lov ortig'i, kasal kunlari) darhol oilaning ochiq qarziga; holati shubhali o'quvchida
--       (ochiq fantom faktura — arxivdagi o'quvchi ham) avans turadi; app.stu_bill_skip = admin.html billingInterval.
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub) — RLS va GRANT haqiqiy. SYSTEM — server (service_role da'vosi).
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-audit-10-tolov.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-10-tolov.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' when p_uid = 'SYSTEM' then '{"role":"service_role"}'
                                                else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  -- SYSTEM (to'lov serveri): faqat JWT da'vosi qo'yiladi — lokal sinov bazasida service_role RLS ni chetlab o'tmaydi (jonli bazada o'tadi)
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
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- Holatni o'qish — VOLATILE plpgsql (har so'rov yangi surat): bitta select ichida zz.as(...) dan KEYIN chaqirilsa ham uning o'zgarishini
--   ko'radi (oddiy ichki so'rov tashqi select boshidagi holatni ko'rardi).
create or replace function zz.q(p_q text) returns text language plpgsql as $$
declare r text;
begin
  begin execute p_q into r; exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm; end;   -- mutatsiyada FAIL, to'plam to'xtamaydi
  return coalesce(r, '<null>');
end $$;
-- faktura holati: «id=status:to'langan/summa»; avans; to'lov qatori «holat:kanal:summa:o'quvchi»
create or replace function zz.inv(p_id text) returns text language plpgsql as $$
begin return coalesce((select id || '=' || coalesce(status, '-') || ':' || trim_scale(coalesce("paidAmount", 0)) || '/' || trim_scale(coalesce(amount, 0))
                         from public.invoices where id = p_id), p_id || '=yo''q'); end $$;
create or replace function zz.cr(p_sid text) returns text language plpgsql as $$
begin return coalesce((select trim_scale(credit)::text from public.student_credit where id = p_sid), '0'); end $$;
create or replace function zz.p(p_id text) returns text language plpgsql as $$
begin return coalesce((select coalesce(status, '-') || ':' || coalesce(provider, '-') || ':' || coalesce(trim_scale(amount)::text, '-') || ':' || coalesce(nullif("studentId", ''), '-')
                         from public.payments where id = p_id), 'yo''q'); end $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles") values
  ('U_DIR','d@example.org','director','active','[]'), ('U_FM','f@example.org','finance_mgr','active','[]'),
  ('U_TRE','g@example.org','treasurer','active','[]'), ('U_KAS','k@example.org','kassir','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email;
insert into public.config (id, "sickApprovalFrom", "sickRate", "invoiceCreators") values ('finance', '2026-10', 40000, 'director')
on conflict (id) do update set "sickApprovalFrom" = excluded."sickApprovalFrom", "sickRate" = excluded."sickRate", "invoiceCreators" = excluded."invoiceCreators";
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "activeFrom", "stopFrom", "exitAt", pauses, "order") values
  ('T-1','T-1','Sinov Bir',5,'A','uz','',null,null,null,'[]',1),
  ('T-2','T-2','Sinov Ikki',5,'A','uz','',null,null,null,'[]',2),
  ('T-3','T-3','Sinov Uch',6,'A','uz','chiqdi',null,'2026-09-30','2026-09-30','[]',3),        -- arxivda: 30.09 da chiqqan
  ('T-4','T-4','Sinov Tort',6,'A','uz','',null,null,null,'[]',4),
  ('T-5','T-5','Sinov Besh',7,'A','uz','',null,null,null,'[]',5),
  ('T-6','T-6','Sinov Olti',7,'A','uz','chiqdi',null,'2026-10-15','2026-10-15','[]',6),       -- oy o'rtasida chiqqan
  ('T-7','T-7','Sinov Yetti',8,'A','uz','muzlatilgan',null,null,null,'[]',7),                 -- sanasiz muzlatilgan (shubhali)
  ('T-8','T-8','Sinov Sakkiz',8,'A','uz','chiqdi',null,'2026-09-30','2026-09-30','[]',8);      -- arxivda + ochiq fantom (noyabr) faktura
insert into public.invoices (id, "studentId", "studentName", month, amount, "baseAmount", "paidAmount", status, provider, "billedFrom", "billedTo") values
  ('T-1__2026-10','T-1','Sinov Bir','2026-10',2000000,2000000,0,'pending','',null,null),
  ('T-1__2026-11','T-1','Sinov Bir','2026-11',2000000,2000000,0,'pending','',null,null),
  ('T-2__2026-10','T-2','Sinov Ikki','2026-10',2000000,2000000,0,'pending','',null,null),
  ('T-2__2026-12','T-2','Sinov Ikki','2026-12',2000000,2000000,0,'pending','',null,null),
  ('T-3__2026-09','T-3','Sinov Uch','2026-09',2000000,2000000,0,'pending','',null,null),
  ('T-3__2026-10','T-3','Sinov Uch','2026-10',2000000,2000000,2000000,'paid','click',null,null),
  ('T-4__2026-10','T-4','Sinov Tort','2026-10',2000000,2000000,1500000,'partial','cash',null,null),
  ('T-4__2026-11','T-4','Sinov Tort','2026-11',2000000,2000000,0,'pending','',null,null),
  ('T-5__2026-09','T-5','Sinov Besh','2026-09',2000000,2000000,0,'pending','',null,null),
  ('T-5__2026-10','T-5','Sinov Besh','2026-10',2000000,2000000,0,'pending','',null,null),
  ('T-6__2026-10','T-6','Sinov Olti','2026-10',1000000,2000000,0,'pending','','2026-10-01','2026-10-15'),
  ('T-7__2026-09','T-7','Sinov Yetti','2026-09',2000000,2000000,0,'pending','',null,null),
  ('T-7__2026-10','T-7','Sinov Yetti','2026-10',2000000,2000000,0,'pending','',null,null),
  ('T-8__2026-09','T-8','Sinov Sakkiz','2026-09',2000000,2000000,0,'pending','',null,null),
  ('T-8__2026-10','T-8','Sinov Sakkiz','2026-10',2000000,2000000,2000000,'paid','click',null,null),
  ('T-8__2026-11','T-8','Sinov Sakkiz','2026-11',2000000,2000000,0,'pending','',null,null);
-- To'lov serveri yozgan qatorlar: T-1 ning qo'llangan Click to'lovi (server posboni — click_trans_id, «click_» siz), biriktirilmagan
--   Click to'lovlari, qabul qilingan naqd to'lov, provayder qaytargan Uzum to'lovi, fantom «pending» yozuv.
insert into public.payments (id, "studentId", "invoiceId", provider, amount, status, raw, click_trans_id, "payerName", matched, "createdAt") values
  ('click_9900001','T-1','T-1__2026-09','click',2000000,'paid','{}','9900001','Sinov Ota',true,'2026-11-02 10:00+05'),
  ('click_9900002','',null,'click',1000000,'unmatched','{}','9900002','Sinov Ota 2',false,'2026-11-03 10:00+05'),
  ('click_9900003','',null,'click',300000,'unmatched','{}','9900003','Sinov Ota 3',false,'2026-11-03 11:00+05'),
  ('man_t5_00001','T-1',null,'cash',2000000,'applied','{"manual":true,"date":"2026-11-04"}',null,'Sinov Ota',true,'2026-11-04 09:00+05'),
  ('uzum_t9_0001','T-1',null,'uzum',500000,'reversed','{"needsManualReverse":true}',null,'Sinov Ota',true,'2026-11-05 09:00+05'),
  ('man_t9_00001','T-1',null,'bank',700000,'pending','{"manual":true}',null,'Sinov Ota',true,'2026-11-05 10:00+05');
insert into public.applied_payments (id, "studentId", amount, "createdAt") values ('9900001','T-1',2000000,'2026-11-02 10:00+05'), ('man_t5_00001','T-1',2000000,'2026-11-04 09:00+05');
insert into public.sick_notes (id, "studentId", "fromDay", "toDay", "schoolDays", status, "appliedDays") values
  ('sn_t20','T-6','2026-10-05','2026-10-06','["2026-10-05","2026-10-06"]','approved','{}');
set local session_replication_role = origin;

-- ===== (A) A4-01: to'lov qatori faqat ishonchli yo'ldan =====
select zz.chk('A01 kassir REST orqali soxta Click qatori yoza olmaydi (biriktirib «Click tushumi» qilish uchun)',
  zz.as('U_KAS', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched) values ('click_999000111', '', 'click', 2000000, 'unmatched', false) returning id) select id from x$q$)
  || ' | ' || zz.p('click_999000111'), '^ERR 42501 \[pay:direct\].* \| yo''q$');
select zz.chk('A02 moliya menejeri va g''aznachi ham yoza olmaydi; «pending» qator ham (qarzni pulsiz yopish uchun)',
  zz.as('U_FM', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched) values ('man_fake_00001', 'T-2', 'bank', 2000000, 'pending', true) returning id) select id from x$q$) || ' | '
  || zz.as('U_TRE', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched) values ('man_fake_00002', 'T-2', 'cash', 2000000, 'applied', true) returning id) select id from x$q$) || ' | '
  || zz.q($q$select count(*) from public.payments where id like 'man_fake_%'$q$), '^ERR 42501.* \| ERR 42501.* \| 0$');
select zz.chk('A03 kassir allaqachon qo''llangan Click qatori (server posboni boshqa kalitda) bilan boshqa o''quvchining qarzini yopa olmaydi',
  zz.as('U_KAS', $q$select public.apply_payment('T-2', 2000000, 'click', 'click_9900001')::text$q$) || ' | '
  || zz.inv('T-2__2026-10') || ' | ' || zz.q($q$select count(*) from public.applied_payments where id = 'click_9900001'$q$),
  '^ERR 42501 \[\] apply_payment: to''lov yozuvisiz.* \| T-2__2026-10=pending:0/2000000 \| 0$');
select zz.chk('A04 moliya menejeri apply_to_invoice bilan ham — rad',
  zz.as('U_FM', $q$select public.apply_to_invoice('T-2__2026-10', 2000000, 'click', 'click_9900001')::text$q$) || ' | ' || zz.inv('T-2__2026-10'),
  '^ERR 42501 \[\] apply_to_invoice: to''lov yozuvisiz.* \| T-2__2026-10=pending:0/2000000$');
select zz.chk('A05 kassir qabul qilingan naqd to''lovni o''zgartira olmaydi (summa / kanal / holat) — 0 qator, qator o''zgarmadi',
  zz.as('U_KAS', $q$with x as (update public.payments set amount = 100000 where id = 'man_t5_00001' returning id) select count(*)::text from x$q$) || ' | '
  || zz.as('U_KAS', $q$with x as (update public.payments set provider = 'click' where id = 'man_t5_00001' returning id) select count(*)::text from x$q$) || ' | '
  || zz.as('U_KAS', $q$with x as (update public.payments set status = 'canceled' where id = 'man_t5_00001' returning id) select count(*)::text from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (update public.payments set status = 'canceled' where id = 'man_t5_00001' returning id) select count(*)::text from x$q$) || ' | '
  || zz.p('man_t5_00001'),
  '^0 \| 0 \| 0 \| 0 \| applied:cash:2000000:T-1$');
select zz.chk('A06 kassir setDoc (upsert) bilan ham — rad',
  zz.as('U_KAS', $q$with x as (insert into public.payments (id, status) values ('man_t9_00001', 'canceled') on conflict (id) do update set status = excluded.status returning id) select id from x$q$)
  || ' | ' || zz.p('man_t9_00001'), '^ERR 42501.* \| pending:bank:700000:T-1$');
select zz.chk('A07 Direktor ham to''lov qatorini REST orqali yarata olmaydi (faqat «💵 To''lov» / server)',
  zz.as('U_DIR', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched) values ('click_999000222', 'T-2', 'click', 2000000, 'applied', true) returning id) select id from x$q$),
  '^ERR 42501 \[pay:direct\]');
select zz.chk('A08 Direktor pul maydonlarini o''zgartira olmaydi: summa, kanal, o''quvchi, biriktirish, kun, qo''llangan holat',
  zz.as('U_DIR', $q$with x as (update public.payments set amount = 1 where id = 'man_t5_00001' returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.payments set provider = 'click' where id = 'man_t5_00001' returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.payments set "studentId" = 'T-2' where id = 'man_t5_00001' returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.payments set matched = false where id = 'man_t5_00001' returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.payments set raw = raw || '{"date":"2026-11-01"}' where id = 'man_t5_00001' returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.payments set status = 'canceled' where id = 'man_t5_00001' returning id) select id from x$q$) || ' | '
  || zz.p('man_t5_00001') || ':' || zz.q($q$select raw ->> 'date' from public.payments where id = 'man_t5_00001'$q$),
  '^ERR 42501 \[pay:direct\].* \| ERR 42501 \[pay:direct\].* \| ERR 42501 \[pay:direct\].* \| ERR 42501 \[pay:direct\].* \| ERR 42501 \[pay:direct\].* \| ERR 42501 \[pay:direct\].* \| applied:cash:2000000:T-1:2026-11-04$');
select zz.chk('A09 Direktorning sahifadagi amallari (setDoc): qaytarilgan to''lovga «✓ Bajarildi» belgisi, fantom «pending» yozuvni «🚫 Bekor», to''lovchi ismi',
  zz.as('U_DIR', $q$with x as (insert into public.payments (id, raw) values ('uzum_t9_0001', '{"needsManualReverse":true,"manualReverseDone":true,"manualReverseBy":"d@example.org"}') on conflict (id) do update set raw = excluded.raw returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.payments (id, status) values ('man_t9_00001', 'canceled') on conflict (id) do update set status = excluded.status returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (update public.payments set "payerName" = 'Sinov Ota (tuzatildi)' where id = 'click_9900002' returning id) select id from x$q$) || ' | '
  || zz.q($q$select string_agg(id || ':' || status || ':' || coalesce(raw ->> 'manualReverseDone', '-') || ':' || trim_scale(amount), ',' order by id) from public.payments where id in ('uzum_t9_0001', 'man_t9_00001')$q$),
  '^uzum_t9_0001 \| man_t9_00001 \| click_9900002 \| man_t9_00001:canceled:-:700000,uzum_t9_0001:reversed:true:500000$');
select zz.chk('A10 kassir: «💵 To''lov» (record_manual_payment) — ishlaydi, faktura yopiladi',
  zz.as('U_KAS', $q$select (r ->> 'ok') || ':' || (r ->> 'status') from (select public.record_manual_payment('man_1731100000000_t1a10','T-2',2000000,'cash',null,'','','Sinov Ota',null) r) z$q$)
  || ' | ' || zz.inv('T-2__2026-10'), '^true:applied \| T-2__2026-10=paid:2000000/2000000$');
select zz.chk('A11 kassir: biriktirish (assign_payment) — ishlaydi (server yozgan «unmatched» qator)',
  zz.as('U_KAS', $q$select (public.assign_payment('click_9900002', 'T-1') ->> 'ok')$q$) || ' | '
  || zz.p('click_9900002') || ' | ' || zz.inv('T-1__2026-10'),
  '^true \| applied:click:1000000:T-1 \| T-1__2026-10=partial:1000000/2000000$');
select zz.chk('A11b ichki bayroq (iqror.assign_rpc) biriktirishdan keyin tranzaksiyada qolmadi',
  coalesce(nullif(current_setting('iqror.assign_rpc', true), ''), 'bo''sh'), '^bo''sh$');
select zz.chk('A12 qayta biriktirish — rad (qator endi «applied»)', zz.as('U_KAS', $q$select public.assign_payment('click_9900002', 'T-2') ->> 'reason'$q$), '^not-unmatched$');
select zz.chk('A13 moliya: bo''lish (split_payment) — ishlaydi',
  zz.as('U_FM', $q$select (public.split_payment('click_9900003', 'click', '[{"sid":"T-1","amount":300000}]'::jsonb) ->> 'ok')$q$) || ' | '
  || zz.p('click_9900003') || ' | ' || zz.inv('T-1__2026-10'),
  '^true \| split:click:300000:- \| T-1__2026-10=partial:1300000/2000000$');
select zz.chk('A14 Direktorning «Qo''llash»i (to''lov yozuvisiz, fix_ kalit) va server (service_role) — avvalgidek',
  zz.as('U_DIR', $q$select public.apply_payment('T-1', 700000, 'mixed', 'fix_T-1_700000_t14') ->> 'ok'$q$) || ' | '
  || zz.as('SYSTEM', $q$select public.apply_payment('T-1', 100000, 'click', 'ct_t14') ->> 'ok'$q$) || ' | ' || zz.inv('T-1__2026-10') || ' | ' || zz.inv('T-1__2026-11'),
  '^true \| true \| T-1__2026-10=paid:2000000/2000000 \| T-1__2026-11=partial:100000/2000000$');
select zz.chk('A15 server (webhook) to''lov qatorini yozadi va holatini o''zgartiradi — tizim mustasno',
  zz.as('SYSTEM', $q$with x as (insert into public.payments (id, "studentId", provider, amount, status, matched) values ('click_9900004', '', 'click', 50000, 'prepared', false) returning id) select id from x$q$) || ' | '
  || zz.as('SYSTEM', $q$with x as (update public.payments set status = 'unmatched' where id = 'click_9900004' returning status) select status from x$q$),
  '^click_9900004 \| unmatched$');
select zz.chk('A16 yangi yordamchilar mijozga yopiq (credit_sweep / stu_bill_skip)',
  zz.as('U_FM', $q$select app.credit_sweep('T-7')::text$q$) || ' | ' || zz.as('U_FM', $q$select app.stu_bill_skip('', null, null, '[]', '2026-10')$q$),
  '^ERR 42501.* \| ERR 42501');

-- ===== (B) A4-02: moliya rollari fakturani «to'landi» / 0 so'm qila olmaydi =====
select zz.chk('B01 g''aznachi va moliya menejeri reprice_invoice — rad (1 so''m ham, 0 ham), faktura o''zgarmadi',
  zz.as('U_TRE', $q$select public.reprice_invoice('T-5__2026-10', 1, '{"discountInfo":"Chegirmasiz","pctApplied":0}'::jsonb, false)::text$q$) || ' | '
  || zz.as('U_FM', $q$select public.reprice_invoice('T-5__2026-10', 0, '{}'::jsonb, false)::text$q$) || ' | ' || zz.inv('T-5__2026-10'),
  '^ERR 42501 \[\] forbidden \| ERR 42501 \[\] forbidden \| T-5__2026-10=pending:0/2000000$');
select zz.chk('B02 moliya menejeri to''g''ridan-to''g''ri {status:paid, paidAmount} — ta''sirsiz (0 qator); g''aznachi ham',
  zz.as('U_FM', $q$with x as (update public.invoices set status = 'paid', "paidAmount" = 2000000 where id = 'T-5__2026-10' returning id) select count(*)::text from x$q$) || ' | '
  || zz.as('U_TRE', $q$with x as (update public.invoices set status = 'paid', "paidAmount" = 2000000 where id = 'T-5__2026-10' returning id) select count(*)::text from x$q$) || ' | '
  || zz.inv('T-5__2026-10'), '^0 \| 0 \| T-5__2026-10=pending:0/2000000$');
select zz.chk('B03 moliya «Bekor» (cancel_invoice) — avvalgidek ishlaydi (to''lanmagan faktura)',
  zz.as('U_FM', $q$select public.cancel_invoice('T-2__2026-12') ->> 'ok'$q$) || ' | ' || zz.inv('T-2__2026-12'), '^true \| T-2__2026-12=canceled:0/2000000$');
update public.config set "invoiceCreators" = 'director_finance' where id = 'finance';
select zz.chk('B04 moliya menejeri faktura yaratishi mumkin bo''lsa ham (sozlama) — «to''langan» holatda emas; to''lanmagani — avvalgidek',
  zz.as('U_FM', $q$with x as (insert into public.invoices (id, "studentId", "studentName", month, amount, "baseAmount", "paidAmount", status) values ('T-2__2027-01', 'T-2', 'Sinov Ikki', '2027-01', 2000000, 2000000, 2000000, 'paid') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.invoices (id, "studentId", "studentName", month, amount, "baseAmount", "paidAmount", status) values ('T-2__2027-02', 'T-2', 'Sinov Ikki', '2027-02', 2000000, 2000000, 0, 'paid') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.invoices (id, "studentId", "studentName", month, amount, "baseAmount", "paidAmount", status) values ('T-2__2027-03', 'T-2', 'Sinov Ikki', '2027-03', 2000000, 2000000, 0, 'pending') returning id) select id from x$q$),
  '^ERR 42501 \[inv:paid\].* \| ERR 42501 \[inv:paid\].* \| T-2__2027-03$');
select zz.chk('B05 (2-raund) moliya menejeri sababsiz 0 so''mlik «to''langan» faktura yoza olmaydi; grant bilan 0 so''m — mumkin (generatsiyaning to''liq qoplangan holati)',
  zz.as('U_FM', $q$with x as (insert into public.invoices (id, "studentId", "studentName", month, amount, "baseAmount", "paidAmount", status, "discountInfo") values ('T-2__2027-04', 'T-2', 'Sinov Ikki', '2027-04', 0, 2000000, 0, 'paid', 'Chegirmasiz') returning id) select id from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (insert into public.invoices (id, "studentId", "studentName", month, amount, "baseAmount", "paidAmount", status, "isGrant", "pctApplied", "discountInfo") values ('T-2__2027-05', 'T-2', 'Sinov Ikki', '2027-05', 0, 2000000, 0, 'paid', true, 1, '100% grant') returning id) select id from x$q$),
  '^ERR 42501 \[inv:paid\].* \| T-2__2027-05$');
update public.config set "invoiceCreators" = 'director' where id = 'finance';

-- ===== (C) A4-03: avans darhol ochiq qarzga =====
select zz.chk('C01 ketgan o''quvchi (arxivda): to''langan oktyabr holat bo''yicha bekor — pul avansga va DARHOL sentyabr qarziga, avans 0',
  zz.as('U_DIR', $q$select (public.reprice_invoice('T-3__2026-10', 0, '{"statusReason":"chiqgan"}'::jsonb, true) ->> 'excess')$q$) || ' | '
  || zz.inv('T-3__2026-10') || ' | ' || zz.inv('T-3__2026-09') || ' | ' || zz.cr('T-3'),
  '^2000000 \| T-3__2026-10=canceled:0/2000000 \| T-3__2026-09=paid:2000000/2000000 \| 0$');
select zz.chk('C02 narx kamaydi (qisman to''langan oktyabr): ortiqcha 300 000 — noyabr qarziga, avans 0',
  zz.as('U_DIR', $q$select (public.reprice_invoice('T-4__2026-10', 1200000, '{}'::jsonb, false) ->> 'excess')$q$) || ' | '
  || zz.inv('T-4__2026-10') || ' | ' || zz.inv('T-4__2026-11') || ' | ' || zz.cr('T-4'),
  '^300000 \| T-4__2026-10=paid:1200000/1200000 \| T-4__2026-11=partial:300000/2000000 \| 0$');
select zz.chk('C03 Click aniq to''lovi (2,5 mln) oktyabrga: ortiqcha 500 000 — sentyabr qarziga, avans 0',
  zz.as('SYSTEM', $q$select (public.apply_to_invoice('T-5__2026-10', 2500000, 'click', 'ct_c03') ->> 'overflow')$q$) || ' | '
  || zz.inv('T-5__2026-10') || ' | ' || zz.inv('T-5__2026-09') || ' | ' || zz.cr('T-5'),
  '^500000 \| T-5__2026-10=paid:2000000/2000000 \| T-5__2026-09=partial:500000/2000000 \| 0$');
select zz.chk('C04 ketgan o''quvchining kasal kunlari (2 × 40 000) — avansga va oktyabr qarziga, avans 0',
  zz.as('U_FM', $q$select (public.sick_note_refund('sn_t20') ->> 'amount')$q$) || ' | ' || zz.inv('T-6__2026-10') || ' | ' || zz.cr('T-6'),
  '^80000 \| T-6__2026-10=partial:80000/1000000 \| 0$');
select zz.chk('C05 holati shubhali (sanasiz muzlatilgan): aniq to''lov ortig''i avansda turadi, sentyabrga qo''llanmaydi',
  zz.as('SYSTEM', $q$select (public.apply_to_invoice('T-7__2026-10', 2500000, 'click', 'ct_c05') ->> 'overflow')$q$) || ' | '
  || zz.inv('T-7__2026-10') || ' | ' || zz.inv('T-7__2026-09') || ' | ' || zz.cr('T-7'),
  '^500000 \| T-7__2026-10=paid:2000000/2000000 \| T-7__2026-09=pending:0/2000000 \| 500000$');
select zz.chk('C06 arxivdagi o''quvchida ochiq fantom faktura (noyabr — chiqqandan keyin): oktyabr bekor qilinsa avans turadi, sentyabrga sarflanmaydi',
  zz.as('U_DIR', $q$select (public.reprice_invoice('T-8__2026-10', 0, '{"statusReason":"chiqgan"}'::jsonb, true) ->> 'excess')$q$) || ' | '
  || zz.inv('T-8__2026-09') || ' | ' || zz.inv('T-8__2026-11') || ' | ' || zz.cr('T-8'),
  '^2000000 \| T-8__2026-09=pending:0/2000000 \| T-8__2026-11=pending:0/2000000 \| 2000000$');
select zz.chk('C07 fantom noyabr bekor qilingach (to''lanmagan) — to''xtab turgan avans darhol sentyabr qarziga',
  zz.as('U_DIR', $q$select (public.reprice_invoice('T-8__2026-11', 0, '{"statusReason":"chiqgan"}'::jsonb, true) ->> 'ok')$q$) || ' | '
  || zz.inv('T-8__2026-11') || ' | ' || zz.inv('T-8__2026-09') || ' | ' || zz.cr('T-8'),
  '^true \| T-8__2026-11=canceled:0/2000000 \| T-8__2026-09=paid:2000000/2000000 \| 0$');
select zz.chk('C08 avans jurnali: qayta hisoblash ortig''i (+) va qo''llandi (−) — iz saqlanadi',
  (select string_agg(reason || ':' || trim_scale(delta), ',' order by "at", delta desc) from public.credit_ledger where "studentId" = 'T-3'),
  '^recompute:2000000,applied:-2000000$');
-- app.stu_bill_skip = admin.html billingInterval «skip» xulosasi (kodlar)
select zz.chk('C09 stu_bill_skip: sinov / hali boshlanmagan / sanasiz / to''xtatilgan / bo''sh oraliq / butun oy to''xtatilgan / qisman / faol',
  zz.q($q$select concat_ws(',',
    coalesce(app.stu_bill_skip('sinov', null, null, '[]', '2026-10'), 'null'),
    coalesce(app.stu_bill_skip('', '2026-11-05', null, '[]', '2026-10'), 'null'),
    coalesce(app.stu_bill_skip('chiqdi', null, '', '[]', '2026-10'), 'null'),
    coalesce(app.stu_bill_skip('muzlatilgan', null, '2026-09-30', '[]', '2026-10'), 'null'),
    coalesce(app.stu_bill_skip('chiqdi', '2026-10-20', '2026-10-10', '[]', '2026-10'), 'null'),
    coalesce(app.stu_bill_skip('', null, null, '[{"from":"2026-09-28","to":"2026-11-02"}]', '2026-10'), 'null'),
    coalesce(app.stu_bill_skip('chiqdi', null, '2026-10-15', '[]', '2026-10'), 'null'),
    coalesce(app.stu_bill_skip('', null, null, '[{"from":"2026-10-05","to":"2026-10-09"}]', '2026-10'), 'null'),
    coalesce(app.stu_bill_skip('faol', null, null, '[]', 'noto''g''ri'), 'null'))$q$),
  '^trial,future,nodate,stopped,empty,paused,null,null,null$');

-- ===== Mustaqil tekshiruv (2-raund) =====
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "activeFrom", "stopFrom", "exitAt", pauses, "order") values
  ('T-9','T-9','Sinov Toqqiz',6,'A','uz','chiqdi',null,'2026-09-30','2026-09-30','[]',9),      -- arxivda + ochiq fantom (noyabr) faktura
  ('T-10','T-10','Sinov On',6,'A','uz','chiqdi',null,'2026-09-30','2026-09-30','[]',10);
insert into public.invoices (id, "studentId", "studentName", month, amount, "baseAmount", "paidAmount", status, provider, "billedFrom", "billedTo") values
  ('T-9__2026-09','T-9','Sinov Toqqiz','2026-09',2000000,2000000,0,'pending','',null,null),
  ('T-9__2026-11','T-9','Sinov Toqqiz','2026-11',2000000,2000000,0,'pending','',null,null),
  ('T-10__2026-09','T-10','Sinov On','2026-09',2000000,2000000,0,'pending','',null,null),
  ('T-10__2026-11','T-10','Sinov On','2026-11',2000000,2000000,0,'pending','',null,null);
insert into public.student_credit (id, "studentId", credit) values ('T-9','T-9',2000000), ('T-10','T-10',2000000);   -- fantom tufayli ushlab turilgan avans
insert into public.payments (id, "studentId", "invoiceId", provider, amount, status, raw, click_trans_id, "payerName", matched, "createdAt") values
  ('click_9900077','',null,'click',400000,'prepared','{}','9900077','Sinov Ota 4',false,'2026-11-06 10:00+05');   -- server yozgan, pul KELMAGAN
set local session_replication_role = origin;
select zz.chk('C10 fantom noyabr «Bekor» (cancel_invoice, moliya menejeri) bilan olib tashlansa ham — ushlab turilgan avans darhol sentyabr qarziga',
  zz.as('U_FM', $q$select public.cancel_invoice('T-9__2026-11') ->> 'ok'$q$) || ' | ' || zz.inv('T-9__2026-11') || ' | ' || zz.inv('T-9__2026-09') || ' | ' || zz.cr('T-9'),
  '^true \| T-9__2026-11=canceled:0/2000000 \| T-9__2026-09=paid:2000000/2000000 \| 0$');
select zz.chk('C11 fantom noyabr «O''chir» (delete_unpaid_invoice, Direktor) — xuddi shunday',
  zz.as('U_DIR', $q$select public.delete_unpaid_invoice('T-10__2026-11') ->> 'ok'$q$) || ' | ' || zz.inv('T-10__2026-11') || ' | ' || zz.inv('T-10__2026-09') || ' | ' || zz.cr('T-10'),
  '^true \| T-10__2026-11=yo''q \| T-10__2026-09=paid:2000000/2000000 \| 0$');
select zz.chk('A17 Direktor ham holatni NULL qila olmaydi (UPDATE va upsert) — pul kelmagan «prepared» Click yozuvi kassirga biriktiriladigan bo''lib qolmaydi',
  zz.as('U_DIR', $q$with x as (update public.payments set status = null where id = 'click_9900077' returning id) select id from x$q$) || ' | '
  || zz.as('U_DIR', $q$with x as (insert into public.payments (id, status) values ('click_9900077', null) on conflict (id) do update set status = excluded.status returning id) select id from x$q$) || ' | '
  || zz.as('U_KAS', $q$select public.assign_payment('click_9900077', 'T-2') ->> 'reason'$q$) || ' | ' || zz.p('click_9900077'),
  '^ERR 42501 \[pay:direct\].* \| ERR 42501 \[pay:direct\].* \| not-unmatched \| prepared:click:400000:-$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
