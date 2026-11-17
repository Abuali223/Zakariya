-- =====================================================================
-- test-audit-fixes.sql — jonli audit oldidan topilgan pul/hisobot xatolari tuzatmasi sinovi (SESSIYA-ISHLARI.md §46):
--   (1) 100 ball qamrovi: 'it' — «Informatika» taxallusi (app.mon_canon, app.mon_disc_slugs, app.monitoring_avg, bonus_candidates);
--   (2) tavsiya bonusi: birinchi haqiqiy to'lov 'paid' / 'applied' / 'confirmed' (Uzum), avans ko'chirmasi ('reattr') va sof puli
--       0 bo'lgan o'quvchi hisoblanmaydi; to'lov bekor/qaytarilsa yoki faktura to'liq qaytarilsa — tavsiya bekor / ogohlantirish;
--       kutilayotgan tavsiyalar hisoblagichi (Direktor kunlik hisoboti);
--   (3) money_rule_violations «Bemor» qoidasi — sickNoteRefs obyekt (yozish paytidagi qo'riqchi bilan bir xil shartlar);
--   (4) sinfga e'lon yozish huquqi (app.ann_can_write) — app.is_homeroom_for bilan bir xil (lavozim ham kerak);
--   (5) o'chirilgan e'lonning yuborilmagan navbat yozuvi bekor ('skipped');
--   (6) ota-ona o'z users qatorida tanlangan farzandni PATCH bilan saqlay oladi (upsert esa RLS insert tekshiruvidan o'tmaydi);
--   (7) reprice_invoice: bayroq (iqror.inv_reprice) faqat RPC ichida — Moliya menejeri RPC orqali narxni o'zgartira oladi,
--       to'g'ridan-to'g'ri o'zgartira olmaydi, va RPC'dan keyin tranzaksiyada bayroq qolmaydi (funksiya darajasidagi SET'siz);
--   (8) maosh vedomosti: HR / Moliya menejerining (qo'shimcha HR rolli xodimning ham) o'z qatori Direktor tasdig'ida — xodim kartasi
--       asosiy havola (users."staffRefType" / "staffRefId") bilan ham, teskari havola (staff / teachers."userUid") bilan ham bog'langan
--       bo'lsa (payroll_submit va app.payroll_line_extra_hr); oddiy xodim qatori — tasdiqsiz; teskari havolali HR o'z maoshini o'zi bermaydi;
--   (9) xodim kartasining login havolasi (staff / teachers."userUid", payroll-approval.sql 7-bo'lim): HR uni uza / o'zgartira / yangi kartaga
--       yoza olmaydi (42501), kartaning boshqa maydonlarini tahrirlaydi (o'sha havola bilan to'liq qator upsert'i ham), o'zi bog'langan
--       kartani o'chira olmaydi; Direktor va server (service_role) o'zgartiradi, o'zgarish tarixga yoziladi; HR'ning null ↔ ''
--       almashtirishi (UPDATE va upsert) saqlangan qiymatga qaytariladi — tarixda «— → —» qatori yo'q.
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub) — RLS va GRANT haqiqiy.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-audit-fixes.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa (jonli baza) — darhol to'xtaydi.
--   Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-fixes.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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

-- Urug' (triggerlarsiz — faqat o'qiladigan funksiyalar va keyingi triggerlar sinaladi)
set local session_replication_role = replica;
insert into public.users (id, email, role, status, "homeroomClasses", "extraRoles") values
  ('U_DIR','d@x','director','active','[]','[]'), ('U_FM','f@x','finance_mgr','active','[]','[]'),
  ('U_TEA','t@x','teacher','active','["uz-5-A"]','[]'), ('U_HR','h@x','hr','active','["uz-5-A"]','[]'),
  ('U_RECT','rt@x','reception','active','["uz-5-A"]','["teacher"]'), ('U_PA','pa@x','parent','active','[]','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, "homeroomClasses" = excluded."homeroomClasses", "extraRoles" = excluded."extraRoles";
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('s1','T-1','Sinov A',5,'A','uz','',1,'[]'), ('s2','T-2','Sinov B',5,'A','uz','',2,'[]'), ('s3','T-3','Sinov C',5,'A','uz','',3,'[]'),
  ('s4','T-4','Sinov D',4,'A','uz','',4,'[]'), ('s5','T-5','Sinov E',7,'B','ru','',5,'[]'), ('s7','T-7','Sinov G',5,'A','uz','',7,'[]'),
  ('s8','T-8','Sinov H',5,'A','uz','',8,'[]'), ('s9','T-9','Sinov I',5,'A','uz','',9,'[]'), ('s10','T-10','Sinov J',5,'A','uz','',10,'[]'),
  ('s11','T-11','Sinov K',5,'A','uz','',11,'[]'), ('s12','T-12','Sinov L',5,'A','uz','',12,'[]');
create temp table zz_m (sid text, slug text, score numeric, st text, ck text);
insert into zz_m values
 ('T-1','ona_tili',100,'approved','uz-5-A'),('T-1','matematika',100,'approved','uz-5-A'),('T-1','ingliz_tili',100,'approved','uz-5-A'),('T-1','biologiya',100,'approved','uz-5-A'),('T-1','informatika',100,'approved','uz-5-A'),
 ('T-2','ona_tili',100,'approved','uz-5-A'),('T-2','matematika',100,'approved','uz-5-A'),('T-2','ingliz_tili',100,'approved','uz-5-A'),('T-2','biologiya',100,'approved','uz-5-A'),('T-2','it',100,'approved','uz-5-A'),
 ('T-3','ona_tili',100,'approved','uz-5-A'),('T-3','matematika',100,'approved','uz-5-A'),('T-3','ingliz_tili',100,'approved','uz-5-A'),('T-3','biologiya',100,'approved','uz-5-A'),('T-3','it',80,'approved','uz-5-A'),('T-3','informatika',100,'approved','uz-5-A'),
 ('T-4','matematika',95,'approved','uz-4-A'),('T-4','it',90,'approved','uz-4-A'),('T-4','informatika',100,'pending','uz-4-A'),
 ('T-5','rus_tili',92,'approved','ru-7-B'),('T-5','matematika',92,'approved','ru-7-B'),('T-5','ingliz_tili',92,'approved','ru-7-B'),('T-5','informatika',92,'approved','ru-7-B'),('T-5','biologiya',92,'approved','ru-7-B'),('T-5','kimyo',92,'approved','ru-7-B'),
 ('T-7','ona_tili',100,'approved','uz-5-A'),('T-7','matematika',100,'approved','uz-5-A'),('T-7','ingliz_tili',100,'approved','uz-5-A'),('T-7','biologiya',100,'approved','uz-5-A'),('T-7','informatika',100,'pending','uz-5-A');
insert into public.monitoring (id, "studentId", "classKey", subject, period, score, status)
  select sid || '__2026-10__' || slug, sid, ck, slug, '2026-10', score, st from zz_m;
insert into public.sick_notes (id, "studentId", "fromDay", "toDay", "schoolDays", status) values
  ('N1','T-1','2026-10-12','2026-10-13','["2026-10-12","2026-10-13"]','approved'),
  ('N2','T-3','2026-10-12','2026-10-13','["2026-10-12","2026-10-13"]','pending');
insert into public.config (id, "sickApprovalFrom") values ('finance','2026-11')
  on conflict (id) do update set "sickApprovalFrom" = excluded."sickApprovalFrom";
insert into public.invoices (id, "studentId", month, status, "sickDaysApplied", "sickAmount", "sickNoteRefs") values
  ('T-1__2026-11','T-1','2026-11','unpaid',2,80000,'{"N1":["2026-10-12","2026-10-13"]}'),   -- to'g'ri
  ('T-2__2026-11','T-2','2026-11','unpaid',2,80000,'{}'),                                   -- bo'sh
  ('T-3__2026-11','T-3','2026-11','unpaid',2,80000,'{"N2":["2026-10-12","2026-10-13"]}'),   -- tasdiqlanmagan
  ('T-4__2026-11','T-4','2026-11','unpaid',1,40000,'["N1"]'),                               -- eski massiv shakli
  ('T-5__2026-11','T-5','2026-11','unpaid',0,0,null),                                       -- kasal kun yo'q
  ('T-7__2026-11','T-7','2026-11','unpaid',1,40000,'{"N1":["2026-10-12"]}'),                -- boshqa o'quvchiniki
  ('T-8__2026-11','T-8','2026-11','unpaid',0,40000,null),                                   -- summa bor, kun yo'q
  ('T-9__2026-11','T-9','2026-11','unpaid',5,200000,'{"N9":["2026-10-12"]}'),               -- 5 kun, 1 kun havola
  ('T-10__2026-11','T-10','2026-11','unpaid',1,40000,'{"N10":["2026-10-20"]}');             -- kun ma'lumotnomada yo'q
insert into public.sick_notes (id, "studentId", "fromDay", "toDay", "schoolDays", status) values
  ('N9','T-9','2026-10-12','2026-10-12','["2026-10-12"]','approved'),
  ('N10','T-10','2026-10-12','2026-10-13','["2026-10-12","2026-10-13"]','approved');
-- tavsiya: T-11 (naqd), T-12 (Uzum), T-2 (faqat avans ko'chirmasi), T-3 (to'lov boshqaga ko'chirilgan)
insert into public.referral_requests (id, "referrerId", status) values
  ('T-11','T-1','pending_payment'), ('T-12','T-1','pending_payment'), ('T-2','T-1','pending_payment'), ('T-3','T-1','pending_payment');
insert into public.payments (id, "studentId", amount, status, provider, "createdAt") values
  ('p_ref','T-11',500000,'refunded','cash', now() - interval '3 day'),
  ('p_pend','T-11',500000,'pending','click', now() - interval '2 day'),
  ('p_cash','T-11',1500000,'applied','cash', now() - interval '1 day'),
  ('p_uz','T-12',1500000,'confirmed','uzum', now() - interval '1 day'),
  ('reattr:rv-1:in','T-2',700000,'applied','reattr', now() - interval '1 day'),
  ('click_W7','T-3',1000000,'applied','click', now() - interval '2 day'),
  ('reattr:rv-2:out','T-3',-1000000,'applied','reattr', now() - interval '1 day');
insert into public.invoices (id, "studentId", month, status, amount, "baseAmount", "paidAmount") values
  ('T-12__2098-01','T-12','2098-01','pending',1000000,1000000,0);
set local session_replication_role = origin;

-- ===== (1) 100 ball qamrovi =====
select zz.chk('M01 5-sinf: 5 kanonik fan (Informatika) -> full, required 5', (select app.monitoring_avg('T-1','2026-10')::text), '"full": true, "required": 5');
select zz.chk('M02 5-sinf: eski «IT» yozuvi Informatika o''rnida -> full', (select app.monitoring_avg('T-2','2026-10')::text), '"n": 5, "avg": 100.00, "full": true');
select zz.chk('M03 IT va Informatika ikkalasi: Informatika yozuvi olinadi (avg 100, n 5)', (select app.monitoring_avg('T-3','2026-10')::text), '"n": 5, "avg": 100.00, "full": true');
select zz.chk('M04 4-sinf: sinf fanlari kanonik (2), IT = Informatika -> full, 92.5', (select app.monitoring_avg('T-4','2026-10')::text), '"n": 2, "avg": 92.50, "full": true, "required": 2');
select zz.chk('M05 7-sinf ru: 6 kanonik fan -> full', (select app.monitoring_avg('T-5','2026-10')::text), '"full": true, "required": 6');
select zz.chk('M06 Informatika tasdiqlanmagan -> full emas (4/5)', (select app.monitoring_avg('T-7','2026-10')::text), '"n": 4, .*"full": false');
select zz.chk('M07 mon_disc_slugs kanonik ro''yxat, mon_canon', (select app.mon_disc_slugs(5,'uz')::text || '|' || app.mon_canon('it') || '|' || app.mon_canon('kimyo')),
  '^\{ona_tili,matematika,ingliz_tili,informatika,biologiya\}\|informatika\|kimyo$');
select zz.chk('M08 bonus_candidates (Direktor): to''liq 100 — T-1, T-2 (IT bilan), T-3', zz.as('U_DIR', $q$select string_agg(e->>'studentId', ',' order by e->>'studentId') from jsonb_array_elements(public.bonus_candidates('2026-10')) e$q$), '^T-1,T-2,T-3$');

-- ===== (2) tavsiya bonusi =====
select zz.chk('R01 navbat: naqd («applied») va Uzum («confirmed») to''lovi ko''rinadi; avans ko''chirmasi va ko''chirib yuborilgani yo''q',
  zz.as('U_FM', $q$select string_agg((q->>'id') || '=' || coalesce(q->'payment'->>'id','-'), ',' order by q->>'id') from jsonb_array_elements(public.referral_queue()) q$q$),
  '^T-11=p_cash,T-12=p_uz,T-2=-,T-3=-$');
select zz.chk('R02 Direktor kunlik hisoboti: kutilayotgan tavsiya (to''lovi bor) = 2', zz.as('U_DIR', $q$select (public.director_daily()->'pending'->>'referral')$q$), '^2$');
select zz.chk('R03 avans ko''chirmasi bilan -> no_payment', zz.as('U_FM', $q$select public.referral_decide('T-2', true, null)->>'reason'$q$), '^no_payment$');
select zz.chk('R04 to''lov boshqaga ko''chirilgan (sof 0) -> no_payment', zz.as('U_FM', $q$select public.referral_decide('T-3', true, null)->>'reason'$q$), '^no_payment$');
select zz.chk('R05 naqd to''lov -> tasdiqlanadi', zz.as('U_FM', $q$select public.referral_decide('T-11', true, null)->>'status'$q$), '^approved$');
select zz.chk('R05b firstPaymentId = naqd to''lov (qaytarilgan / kutilayotgani emas)', (select "firstPaymentId" from public.referral_requests where id = 'T-11'), '^p_cash$');
select zz.chk('R06 Uzum to''lovi -> tasdiqlanadi', zz.as('U_FM', $q$select public.referral_decide('T-12', true, null)->>'status'$q$), '^approved$');
update public.payments set status = 'reversed' where id = 'p_uz';   -- Uzum bekor qildi
select zz.chk('R07 Uzum «confirmed» -> «reversed»: tasdiqlangan tavsiya bekor', (select status from public.referral_requests where id = 'T-12'), '^revoked$');
insert into public.refunds (id, target, "targetId", "studentId", amount, reason) values ('rf1','invoice','T-11__2026-11','T-11',1500000,'sinov');
select zz.chk('R08 faktura to''liq qaytarildi (sof 0): tasdiqlangan tavsiya bekor', (select status from public.referral_requests where id = 'T-11'), '^revoked$');

-- ===== (3) «Bemor» qoidasi buzilishlari =====
select zz.chk('S01 Bemor qoidasi: to''g''ri chegirma (T-1) buzilish emas; qolgan 7 tasi — buzilish',
  zz.as('U_DIR', $q$select (r->>'count') || '|' || (select string_agg(x, ',' order by x) from jsonb_array_elements_text(r->'ids') x)
                     from jsonb_array_elements((public.money_rule_violations())->'rules') r where r->>'key' = 'sick'$q$),
  '^7\|T-10__2026-11,T-2__2026-11,T-3__2026-11,T-4__2026-11,T-7__2026-11,T-8__2026-11,T-9__2026-11$');

-- ===== (4) sinfga e'lon yozish huquqi =====
select zz.chk('A01 o''qituvchi — o''z sinfiga e''lon yoza oladi', zz.as('U_TEA', $q$select app.ann_can_write('["uz-5-A"]')::text$q$), '^true$');
select zz.chk('A02 HR (homeroomClasses qolib ketgan) — yoza olmaydi', zz.as('U_HR', $q$select app.ann_can_write('["uz-5-A"]')::text$q$), '^false$');
select zz.chk('A03 qabulxona + qo''shimcha «O''qituvchi» lavozimi — yoza oladi', zz.as('U_RECT', $q$select app.ann_can_write('["uz-5-A"]')::text$q$), '^true$');
select zz.chk('A04 o''qituvchi — boshqa sinfga yoza olmaydi', zz.as('U_TEA', $q$select app.ann_can_write('["uz-6-B"]')::text$q$), '^false$');

-- ===== (5) o'chirilgan e'lon navbatdan chiqadi =====
select zz.chk('Q01 o''qituvchi o''z sinfiga e''lon yozadi', zz.as('U_TEA', $q$insert into public.class_announcements (id, "classKeys", title, body, "createdBy") values ('ANN_T1', '["uz-5-A"]', 'Sinov e''lon', 'matn', 'U_TEA') returning id$q$), '^ANN_T1$');
select zz.chk('Q01b navbatda «pending» yozuv paydo bo''ldi', (select status from public.notify_queue where id = 'ann__ANN_T1'), '^pending$');
select zz.chk('Q02 o''qituvchi o''z e''lonini o''chiradi', zz.as('U_TEA', $q$with d as (delete from public.class_announcements where id = 'ANN_T1' returning 1) select count(*)::text from d$q$), '^1$');
select zz.chk('Q02b navbat yozuvi endi «skipped»', (select status from public.notify_queue where id = 'ann__ANN_T1'), '^skipped$');
insert into public.class_announcements (id, "classKeys", title, "createdBy") values ('ANN_T2', '["uz-5-A"]', 'Yuborilgan', 'U_DIR');
update public.notify_queue set status = 'done' where id = 'ann__ANN_T2';
delete from public.class_announcements where id = 'ANN_T2';
select zz.chk('Q03 allaqachon yuborilgan («done») yozuv o''zgarmaydi', (select status from public.notify_queue where id = 'ann__ANN_T2'), '^done$');

-- ===== (6) ota-ona tanlagan farzand =====
select zz.chk('U01 ota-ona o''z qatorini PATCH qiladi (activeChildId/childId) -> 1 qator', zz.as('U_PA', $q$with u as (update public.users set "activeChildId" = 'T-1', "childId" = 'T-1' where id = 'U_PA' returning 1) select count(*)::text from u$q$), '^1$');
select zz.chk('U02 upsert (avvalgi usul) — RLS insert tekshiruvi rad etadi', zz.as('U_PA', $q$insert into public.users (id, "activeChildId", "childId") values ('U_PA', 'T-2', 'T-2') on conflict (id) do update set "activeChildId" = excluded."activeChildId" returning 'ok'$q$), '^ERR 42501');
select zz.chk('U03 ota-ona o''z rolini o''zgartira olmaydi', zz.as('U_PA', $q$with u as (update public.users set role = 'director' where id = 'U_PA' returning 1) select count(*)::text from u$q$), '^(ERR 42501|0$)');

-- ===== (7) reprice_invoice bayrog'i =====
select zz.chk('P01 Moliya menejeri faktura summasini to''g''ridan-to''g''ri o''zgartira olmaydi', zz.as('U_FM', $q$with u as (update public.invoices set amount = 900000 where id = 'T-12__2098-01' returning 1) select count(*)::text from u$q$), '^ERR 42501');
select zz.chk('P02 Moliya menejeri reprice_invoice RPC orqali o''zgartiradi', zz.as('U_FM', $q$select public.reprice_invoice('T-12__2098-01', 800000, '{}'::jsonb, false)->>'ok'$q$), '^true$');
select zz.chk('P02b summa 800 000 bo''ldi', (select amount::bigint::text from public.invoices where id = 'T-12__2098-01'), '^800000$');
select zz.chk('P03 RPC''dan keyin tranzaksiyada bayroq qolmadi', (select coalesce(current_setting('iqror.inv_reprice', true), '')), '^$');
select zz.chk('P04 bayroq qolmagani uchun keyingi to''g''ridan-to''g''ri o''zgartirish yana rad etiladi', zz.as('U_FM', $q$with u as (update public.invoices set amount = 1 where id = 'T-12__2098-01' returning 1) select count(*)::text from u$q$), '^ERR 42501');
select zz.chk('P05 xato bo''lsa ham bayroq qolmaydi (ruxsatsiz rol: ota-ona)', zz.as('U_PA', $q$select public.reprice_invoice('T-12__2098-01', 1, '{}'::jsonb, false)->>'ok'$q$) || '|' || coalesce(current_setting('iqror.inv_reprice', true), ''), '^ERR 42501.*\|$');

-- ===== (8) maosh vedomosti: o'z qatori Direktor tasdig'ida — asosiy va teskari havola =====
-- Urug' (triggerlarsiz): asosiy havola — users."staffRefType" / "staffRefId"; teskari — staff / teachers."userUid" (ikkinchi lavozim kartasi).
--   x_dup: bir xil qator id — xodimlar ro'yxatida bog'lanmagan karta, o'qituvchilarda HR'ning ikkinchi lavozim kartasi.
set local session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles", "staffRefType", "staffRefId") values
  ('U_HRF','hrf@x','hr','active','[]','staff','x_hrf'),            ('U_HRR','hrr@x','hr','active','[]',null,null),
  ('U_FMF','fmf@x','finance_mgr','active','[]','teacher','x_fmf'), ('U_FMR','fmr@x','finance_mgr','active','[]',null,null),
  ('U_XHF','xhf@x','teacher','active','["hr"]','teacher','x_xhf'), ('U_XHR','xhr@x','kassir','active','["hr"]',null,null),
  ('U_KS','ks@x','kassir','active','[]','staff','x_ks'),           ('U_TR','tr@x','teacher','active','[]',null,null);
insert into public.staff (id, "staffId", name, "userUid") values
  ('x_hrf','IQX-T1','Sinov HR 1',null), ('x_hrr','IQX-T2','Sinov HR 2','U_HRR'), ('x_xhr','IQX-T3','Sinov Kassir HR','U_XHR'),
  ('x_ks','IQX-T4','Sinov Kassir',null), ('x_free','IQX-T5','Sinov Qorovul',null), ('x_dup','IQX-T6','Sinov Farrosh',null);
insert into public.teachers (id, "teacherId", name, "userUid") values
  ('x_fmf','IQT-T1','Sinov Moliya 1',null), ('x_fmr','IQT-T2','Sinov Moliya 2','U_FMR'), ('x_xhf','IQT-T3','Sinov HR O''qituvchi',null),
  ('x_tr','IQT-T4','Sinov O''qituvchi','U_TR'), ('x_dup','IQT-T6','Sinov HR 2 (ikkinchi lavozim)','U_HRR');
update public.config set "payrollApprovalFrom" = '2098-03' where id = 'finance';
set local session_replication_role = origin;
create or replace function zz.nd(p_pid text) returns text language sql as $$
  select coalesce((select "needsDirector"::text from public.payroll_lines where "runId" = '2098-03' and "personId" = p_pid), '<qator yo''q>') $$;
select zz.chk('W00 Moliya menejeri vedomostni yuboradi (11 qator)', zz.as('U_FM', $q$select public.payroll_submit('2098-03', '[
    {"personType":"staff","personId":"IQX-T1","gross":1000000}, {"personType":"staff","personId":"IQX-T2","gross":1000000},
    {"personType":"staff","personId":"IQX-T3","gross":1000000}, {"personType":"staff","personId":"IQX-T4","gross":1000000},
    {"personType":"staff","personId":"IQX-T5","gross":1000000}, {"personType":"staff","personId":"IQX-T6","gross":1000000},
    {"personType":"teacher","personId":"IQT-T1","gross":1000000}, {"personType":"teacher","personId":"IQT-T2","gross":1000000},
    {"personType":"teacher","personId":"IQT-T3","gross":1000000}, {"personType":"teacher","personId":"IQT-T4","gross":1000000},
    {"personType":"teacher","personId":"IQT-T6","gross":1000000}]'::jsonb, null)->>'count'$q$), '^11$');
select zz.chk('W01 HR, asosiy havola — o''z qatori Direktor tasdig''ida', zz.nd('IQX-T1'), '^true$');
select zz.chk('W02 HR, faqat teskari havola (staff."userUid") — Direktor tasdig''ida', zz.nd('IQX-T2'), '^true$');
select zz.chk('W03 Moliya menejeri, asosiy havola — Direktor tasdig''ida', zz.nd('IQT-T1'), '^true$');
select zz.chk('W04 Moliya menejeri, faqat teskari havola (teachers."userUid") — Direktor tasdig''ida', zz.nd('IQT-T2'), '^true$');
select zz.chk('W05 qo''shimcha HR rolli o''qituvchi, asosiy havola — Direktor tasdig''ida (trigger)', zz.nd('IQT-T3'), '^true$');
select zz.chk('W06 qo''shimcha HR rolli kassir, faqat teskari havola — Direktor tasdig''ida (trigger)', zz.nd('IQX-T3'), '^true$');
select zz.chk('W07 HR''ning ikkinchi lavozim kartasi (o''qituvchi, teskari havola) — Direktor tasdig''ida; xodimlardagi shu qator id''li bog''lanmagan karta — yo''q',
  zz.nd('IQT-T6') || '|' || zz.nd('IQX-T6'), '^true\|false$');
select zz.chk('W08 oddiy xodimlar (kassir — asosiy havola, o''qituvchi — teskari havola, bog''lanmagan qorovul) — Direktor tasdig''isiz',
  zz.nd('IQX-T4') || '|' || zz.nd('IQT-T4') || '|' || zz.nd('IQX-T5'), '^false\|false\|false$');
select zz.chk('W09 teskari havolali HR vedomostni tasdiqlaydi (tayyorlagani — Moliya menejeri)', zz.as('U_HRR', $q$select public.payroll_decide('2098-03', true, null)->>'status'$q$), '^approved$');
select zz.chk('W10 teskari havolali HR o''z maoshini Direktor tasdig''isiz bera olmaydi',
  zz.as('U_HRR', $q$insert into public.salary_payments (id, "teacherId", month, gross, net, paid, date) values ('w_sp1', 'IQX-T2', '2098-03', 1000000, 1000000, 1000000, '2098-03-28') returning id$q$),
  '^ERR 23514 .*Direktor tasdig''i kerak');
select zz.chk('W11 Direktor shu qatorni tasdiqlaydi', zz.as('U_DIR', $q$select public.payroll_approve_line('2098-03__staff__IQX-T2', null)->>'ok'$q$), '^true$');
select zz.chk('W12 Direktor tasdig''idan keyin maosh beriladi (Moliya menejeri)',
  zz.as('U_FM', $q$insert into public.salary_payments (id, "teacherId", month, gross, net, paid, date) values ('w_sp2', 'IQX-T2', '2098-03', 1000000, 1000000, 1000000, '2098-03-28') returning id$q$),
  '^w_sp2$');

-- ===== (9) xodim kartasining login havolasi (staff / teachers."userUid") — faqat Direktor / server =====
-- (8)-bo'limdagi kartalar: x_hrr (U_HRR — teskari havola), x_dup o'qituvchi (U_HRR ning ikkinchi lavozimi), x_hrf (U_HRF — asosiy havola),
--   x_tr (U_TR), x_free (bog'lanmagan). Server: faqat JWT da'vosi (service_role) — lokal sinov bazasida service_role RLS'ni chetlab
--   o'tmaydi (jonli bazada o'tadi), shuning uchun so'rov postgres nomidan, da'vo bilan (test-fin-period.sql dagi SYSTEM kabi).
create or replace function zz.sys(p_q text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  begin execute p_q into r; exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
select zz.chk('H01 HR o''z kartasidagi teskari havolani uza olmaydi (null ham, bo''sh satr ham)',
  zz.as('U_HRR', $q$with u as (update public.staff set "userUid" = null where id = 'x_hrr' returning 1) select count(*)::text from u$q$) || ' / '
  || zz.as('U_HRR', $q$with u as (update public.staff set "userUid" = '' where id = 'x_hrr' returning 1) select count(*)::text from u$q$),
  '^ERR 42501 .*faqat Direktor o''zgartiradi.* / ERR 42501 .*faqat Direktor o''zgartiradi');
select zz.chk('H02 HR boshqa kartaning havolasini o''zgartira olmaydi (o''qituvchi) va bog''lanmagan kartaga o''zini bog''lay olmaydi',
  zz.as('U_HR', $q$with u as (update public.teachers set "userUid" = 'U_HR' where id = 'x_tr' returning 1) select count(*)::text from u$q$) || ' / '
  || zz.as('U_HR', $q$with u as (update public.staff set "userUid" = 'U_HR' where id = 'x_free' returning 1) select count(*)::text from u$q$),
  '^ERR 42501 .*faqat Direktor o''zgartiradi.* / ERR 42501 .*faqat Direktor o''zgartiradi');
select zz.chk('H03 HR havolali yangi karta qo''sha olmaydi (xodim va o''qituvchi)',
  zz.as('U_HR', $q$insert into public.staff (id, "staffId", name, "userUid") values ('x_n1', 'IQX-901', 'Sinov Yangi 1', 'U_HR') returning id$q$) || ' / '
  || zz.as('U_HR', $q$insert into public.teachers (id, "teacherId", name, "userUid") values ('x_n1', 'IQT-901', 'Sinov Yangi 1', 'U_HR') returning id$q$),
  '^ERR 42501 .*faqat Direktor o''zgartiradi.* / ERR 42501 .*faqat Direktor o''zgartiradi');
select zz.chk('H04 HR havolasiz yangi karta qo''shadi (null va bo''sh satr)',
  zz.as('U_HR', $q$insert into public.staff (id, "staffId", name, "userUid") values ('x_n2', 'IQX-902', 'Sinov Yangi 2', null) returning id$q$) || '|'
  || zz.as('U_HR', $q$insert into public.teachers (id, "teacherId", name, "userUid") values ('x_n3', 'IQT-902', 'Sinov Yangi 3', '') returning id$q$),
  '^x_n2\|x_n3$');
select zz.chk('H05 HR bog''langan kartaning boshqa maydonlarini tahrirlaydi — havola o''zgarmaydi',
  zz.as('U_HRR', $q$with u as (update public.staff set position = 'Sinov lavozim' where id = 'x_hrr' returning "userUid") select count(*) || '|' || min("userUid") from u$q$),
  '^1\|U_HRR$');
select zz.chk('H06 HR to''liq qator upsert''i: o''sha havola bilan — o''tadi; havola ustunisiz — o''tadi; boshqa havola bilan — 42501',
  zz.as('U_HRR', $q$insert into public.staff (id, "staffId", name, position, "userUid") values ('x_hrr', 'IQX-T2', 'Sinov HR 2', 'Sinov lavozim 2', 'U_HRR')
     on conflict (id) do update set "staffId" = excluded."staffId", name = excluded.name, position = excluded.position, "userUid" = excluded."userUid"
     returning position || ':' || "userUid"$q$) || ' / '
  || zz.as('U_HRR', $q$insert into public.staff (id, "staffId", name, position) values ('x_hrr', 'IQX-T2', 'Sinov HR 2', 'Sinov lavozim 3')
     on conflict (id) do update set "staffId" = excluded."staffId", name = excluded.name, position = excluded.position returning position || ':' || "userUid"$q$) || ' / '
  || zz.as('U_HRR', $q$insert into public.staff (id, "staffId", name, position, "userUid") values ('x_hrr', 'IQX-T2', 'Sinov HR 2', 'Sinov lavozim 4', 'U_HR')
     on conflict (id) do update set position = excluded.position, "userUid" = excluded."userUid" returning position || ':' || "userUid"$q$),
  '^Sinov lavozim 2:U_HRR / Sinov lavozim 3:U_HRR / ERR 42501 .*faqat Direktor o''zgartiradi');
select zz.chk('H07 HR o''zi bog''langan xodim kartasini o''chira olmaydi (teskari va asosiy havola); o''qituvchi kartasini HR umuman o''chirmaydi (teachers_del — Direktor)',
  zz.as('U_HRR', $q$with d as (delete from public.staff where id = 'x_hrr' returning 1) select count(*)::text from d$q$) || ' / '
  || zz.as('U_HRF', $q$with d as (delete from public.staff where id = 'x_hrf' returning 1) select count(*)::text from d$q$) || ' / '
  || zz.as('U_HRR', $q$with d as (delete from public.teachers where id = 'x_dup' returning 1) select count(*)::text from d$q$),
  '^ERR 42501 .*o''chira olmaysiz.* / ERR 42501 .*o''chira olmaysiz.* / 0$');
select zz.chk('H08 HR boshqa (o''ziga bog''lanmagan) kartani o''chiradi',
  zz.as('U_HRR', $q$with d as (delete from public.staff where id = 'x_n2' returning 1) select count(*)::text from d$q$), '^1$');
select zz.chk('H09 HR urinishlaridan keyin havolalar o''zgarmagan',
  (select string_agg(id || '=' || coalesce("userUid", ''), ',' order by id) from public.staff where id in ('x_hrr', 'x_hrf', 'x_free')) || ' | '
  || (select string_agg(id || '=' || coalesce("userUid", ''), ',' order by id) from public.teachers where id in ('x_dup', 'x_tr')),
  '^x_free=,x_hrf=,x_hrr=U_HRR \| x_dup=U_HRR,x_tr=U_TR$');
select zz.chk('H10 Direktor havolani uzadi va qayta bog''laydi',
  zz.as('U_DIR', $q$with u as (update public.staff set "userUid" = '' where id = 'x_hrr' returning 1) select count(*)::text from u$q$) || '|'
  || zz.as('U_DIR', $q$with u as (update public.staff set "userUid" = 'U_HRR' where id = 'x_hrr' returning "userUid") select min("userUid") from u$q$),
  '^1\|U_HRR$');
select zz.chk('H11 server (ro''yxatdan o''tish, service_role) bo''sh kartaga havola yozadi (shartli yozish — auth/index.cjs kabi)',
  zz.sys($q$with u as (update public.staff set "userUid" = 'U_HR' where id = 'x_free' and ("userUid" is null or "userUid" = '') returning 1) select count(*)::text from u$q$),
  '^1$');
-- HR null ↔ '' (ikkalasi ham «bog'lanmagan»): UPDATE va upsert saqlangan qiymatni o'zgartirmaydi — H12 da HR nomidan havola qatori yo'q.
select zz.chk('H13 HR null ↔ '''' almashtirishi saqlangan qiymatni o''zgartirmaydi: UPDATE (xodim null→'''', o''qituvchi ''''→null) va upsert (xodim, o''qituvchi)',
  zz.as('U_HR', $q$with u as (update public.staff set "userUid" = '' where id = 'x_ks' returning '[' || coalesce("userUid", '<null>') || ']' v) select string_agg(v, ',') from u$q$) || ' '
  || zz.as('U_HR', $q$with u as (update public.teachers set "userUid" = null where id = 'x_n3' returning '[' || coalesce("userUid", '<null>') || ']' v) select string_agg(v, ',') from u$q$) || ' '
  || zz.as('U_HR', $q$insert into public.staff (id, "staffId", name, "userUid") values ('x_dup', 'IQX-T6', 'Sinov Farrosh', '')
     on conflict (id) do update set name = excluded.name, "userUid" = excluded."userUid" returning '[' || coalesce("userUid", '<null>') || ']'$q$) || ' '
  || zz.as('U_HR', $q$insert into public.teachers (id, "teacherId", name, "userUid") values ('x_n3', 'IQT-902', 'Sinov Yangi 3', null)
     on conflict (id) do update set name = excluded.name, "userUid" = excluded."userUid" returning '[' || coalesce("userUid", '<null>') || ']'$q$),
  '^\[<null>\] \[\] \[<null>\] \[\]$');
select zz.chk('H12 havola o''zgarishi tarixda: Direktorniki (2 ta) va tizimniki (kim — bo''sh); HR tahriri — havolasiz',
  (select count(*) filter (where row_id = 'x_hrr' and actor_uid = 'U_DIR') || '|' || count(*) filter (where row_id = 'x_free' and actor_uid is null)
          || '|' || count(*) filter (where actor_uid in ('U_HR', 'U_HRR', 'U_HRF'))
     from public.change_log where tbl in ('staff', 'teachers') and changes ? 'userUid'),
  '^2\|1\|0$');
select zz.chk('H14 null ↔ '''' almashtirishlaridan keyin bu kartalarda havola o''zgarishi tarixi yo''q (x_ks, x_n3, x_dup)',
  (select count(*)::text from public.change_log where tbl in ('staff', 'teachers') and row_id in ('x_ks', 'x_n3', 'x_dup') and changes ? 'userUid'), '^0$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
