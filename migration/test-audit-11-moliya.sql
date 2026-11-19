-- =====================================================================
-- test-audit-11-moliya.sql — moliya hisobotlari (audit-11) sinovi:
--   (D) davomat kiritilishi — dars kunlari Du–Ju, bayram / ta'tilsiz (app.school_days): haftalik va kunlik (A2-02);
--   (Q) qarz muddati — barcha o'quvchilar, ketgan / muzlatilganlar ham, alohida yorliq bilan (A6-03);
--   (P) «Reja va tushum» va haftalik yig'ilish — holati 'paid' (paidAmount bo'sh) to'liq to'langan (A6-04);
--   (T) Telegram kunlik hisobot ma'lumoti: oldingi hisobotdan keyin tushgan to'lovlar ('since', 'asOf') (A6-01) va BARCHA
--       biriktirilmagan to'lovlar (A6-07);
--   (R) ikki bosqichli onlayn to'lov (Click prepare → complete) hisobot payti bilan kesishsa ham 'since'da: tushumga aylangan payt
--       payments."receivedAt" (trigger app.pay_received_at; A6-01, 2-raund) — bir marta qo'yiladi, REST orqali o'zgarmaydi;
--   (K) kassadagi o'quv to'lovidan tashqari daromad finance_other_income (A6-02): --dev zanjirda — kassa hujjatlari bilan; jonli zanjirda
--       (kassa moduli yo'q) — bo'sh natija. Huquq — har ikkisida.
--   Har chaqiruv haqiqiy rol bilan (anon yoki authenticated + JWT sub) — RLS va GRANT haqiqiy; ichki app.* yordamchilar — to'g'ridan-to'g'ri.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-audit-11-moliya.sql
--     (kassa qismi uchun: bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q)
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-11-moliya.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
-- got NULL — '<NULL>' (FAIL qatori bo'sh chiqib, sanoqdan tushib qolmasin)
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, coalesce(p_got, '<NULL>'), p_pat, coalesce(p_got ~ p_pat, false)); end $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles") values
  ('U_DIR','d@example.org','director','active','[]'), ('U_FM','f@example.org','finance_mgr','active','[]'),
  ('U_TRE','g@example.org','treasurer','active','[]'), ('U_ACC','b@example.org','accountant','active','[]'),
  ('U_KAS','k@example.org','kassir','active','[]'), ('U_TEA','t@example.org','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "stopFrom", "exitAt", "order", pauses) values
  ('IQ-0301','IQ-0301','Sinov Faol A',5,'A','uz','',null,null,1,'[]'),
  ('IQ-0302','IQ-0302','Sinov Faol B',5,'A','uz','',null,null,2,'[]'),
  ('IQ-0303','IQ-0303','Sinov Chiqqan',5,'A','uz','chiqdi','2026-10-31','2026-10-31',3,'[]'),
  ('IQ-0304','IQ-0304','Sinov Muzlatilgan',5,'A','uz','muzlatilgan','2026-10-31',null,4,'[]');
-- Fakturalar (har biri 1 000 000): faol A — oktyabr to'lanmagan; faol B — oktyabr 'paid', "paidAmount" BO'SH (eski import);
--   chiqqan — avgust–oktyabr (oktyabr qisman 400 000); muzlatilgan — sentyabr–oktyabr; bekor qilingan — hisoblanmaydi.
insert into public.invoices (id, "studentId", "studentName", "classKey", month, amount, "paidAmount", status, "createdAt", "paidAt") values
  ('IQ-0301__2026-10','IQ-0301','Sinov Faol A','uz-5-A','2026-10',1000000,0,'pending','2026-10-01 09:00+05',null),
  ('IQ-0302__2026-10','IQ-0302','Sinov Faol B','uz-5-A','2026-10',1000000,null,'paid','2026-10-01 09:00+05',null),
  ('IQ-0302__2026-09','IQ-0302','Sinov Faol B','uz-5-A','2026-09',1000000,0,'canceled','2026-09-01 09:00+05',null),
  ('IQ-0303__2026-08','IQ-0303','Sinov Chiqqan','uz-5-A','2026-08',1000000,0,'pending','2026-08-01 09:00+05',null),
  ('IQ-0303__2026-09','IQ-0303','Sinov Chiqqan','uz-5-A','2026-09',1000000,0,'pending','2026-09-01 09:00+05',null),
  ('IQ-0303__2026-10','IQ-0303','Sinov Chiqqan','uz-5-A','2026-10',1000000,400000,'partial','2026-10-01 09:00+05',null),
  ('IQ-0304__2026-09','IQ-0304','Sinov Muzlatilgan','uz-5-A','2026-09',1000000,0,'pending','2026-09-01 09:00+05',null),
  ('IQ-0304__2026-10','IQ-0304','Sinov Muzlatilgan','uz-5-A','2026-10',1000000,0,'pending','2026-10-01 09:00+05',null);
-- Davomat: 2026-11-02 (dushanba) – 2026-11-06 (juma) — ikkala faol o'quvchi har kuni belgilangan; shanba / yakshanba — dars yo'q.
insert into public.attendance (id, "studentId", "classKey", month, days) values
  ('IQ-0301__2026-11','IQ-0301','uz-5-A','2026-11','{"02":"present","03":"present","04":"present","05":"present","06":"present"}'),
  ('IQ-0302__2026-11','IQ-0302','uz-5-A','2026-11','{"02":"present","03":"absent","04":"late","05":"present","06":"sick"}');
-- To'lovlar (Toshkent vaqti): 13-noyabr juma, 14 shanba, 15 yakshanba, 16 dushanba. Kunlik hisobot juma 19:00 da yuborilgan.
insert into public.payments (id, "studentId", provider, amount, status, raw, matched, "createdAt") values
  ('p_thu2000','IQ-0301','cash',10000,'applied',null,true,'2026-11-12 20:00+05'),
  ('p_fri1800','IQ-0301','click',100000,'applied',null,true,'2026-11-13 18:00+05'),
  ('p_fri2100','IQ-0301','click',200000,'applied',null,true,'2026-11-13 21:00+05'),
  ('p_sat1000','IQ-0301','click',400000,'confirmed',null,true,'2026-11-14 10:00+05'),
  ('p_sat_man','IQ-0301','bank',300000,'applied','{"manual":true,"date":"2026-11-13"}',true,'2026-11-14 11:00+05'),
  ('p_sun1500','IQ-0301','uzum',800000,'applied',null,true,'2026-11-15 15:00+05'),
  ('p_sun_pend','IQ-0301','click',999,'pending',null,false,'2026-11-15 16:00+05'),
  ('p_sun_reattr','IQ-0301','reattr',70,'applied',null,true,'2026-11-15 16:10+05'),
  ('p_sun:s:IQ-0302','IQ-0302','cash',50,'applied',null,true,'2026-11-15 16:20+05'),
  ('u_old',null,'uzum',50000,'unmatched',null,false,'2026-11-10 12:00+05'),
  ('u_new',null,'click',70000,'unmatched',null,false,'2026-11-16 08:00+05'),
  ('p_mon0900','IQ-0301','click',1600000,'applied',null,true,'2026-11-16 09:00+05'),
  ('p_mon_late','IQ-0301','cash',25000,'applied','{"manual":true,"date":"2026-11-14"}',true,'2026-11-16 10:00+05');
-- Kunlik hisobot jurnali: muvaffaqiyatli (sent) — 12, 13-noyabr va eski 1-sentyabr; 14-noyabr — yetkazilmagan; boshqa tur — e'tiborsiz.
insert into public.sms_log (id, type, status, channel, phone, "createdAt") values
  ('daily__2026-09-01__L1','daily','sent','telegram','','2026-09-01 19:00:00+05'),
  ('daily__2026-11-12__L1','daily','sent','telegram','','2026-11-12 19:00:03+05'),
  ('daily__2026-11-13__L1','daily','sent','telegram','','2026-11-13 19:00:05+05'),
  ('daily__2026-11-14__L1','daily','failed','telegram','','2026-11-14 19:00:00+05'),
  ('remind__IQ-0301__2026-11-15','remind','sent','sms','998001112233','2026-11-15 12:00:00+05');
set local session_replication_role = origin;

-- ===== (D) Davomat kiritilishi: dars kunlari — Du–Ju (A2-02) =====
select zz.chk('D01 to''liq hafta (du–yak), har dars kuni belgilangan — 100% (10/10); avval shanba ham sanalib 83,3% (10/12)',
  (select (r->>'rate') || ' ' || (r->>'marked') || '/' || (r->>'required') from (select app.kpi_attendance('2026-11-02', '2026-11-08') r) x), '^100\.0 10/10$');
select zz.chk('D02 shanbaning o''zi — dars kuni emas (talab 0, foiz yo''q); avval 0% (0/2)',
  (select coalesce(r->>'rate', 'null') || ' ' || (r->>'required') from (select app.kpi_attendance('2026-11-07', '2026-11-07') r) x), '^null 0$');
select zz.chk('D03 Telegram kunlik: shanba — «dars kuni emas» (rate null)',
  zz.as('U_DIR', $q$select coalesce(public.director_daily('2026-11-07')->'attendance'->>'rate', 'null')$q$), '^null$');
select zz.chk('D04 Telegram kunlik: juma — 100% (2/2)',
  zz.as('U_DIR', $q$select (a->>'rate') || ' ' || (a->>'marked') || '/' || (a->>'required') from (select public.director_daily('2026-11-06')->'attendance' a) x$q$), '^100\.0 2/2$');
select zz.chk('D05 haftalik hisobot (Direktor): o''sha hafta davomati 100%',
  zz.as('U_DIR', $q$select public.director_weekly('2026-11-04')->'attendance'->'cur'->>'rate'$q$), '^100\.0$');
-- bayram: kun ham, id ham (app.school_days bilan bir xil qoida — id bo'yicha ham)
insert into public.school_holidays (id, day, name) values ('2026-11-04', '2026-11-04', 'Sinov bayrami'), ('2026-11-05', null, 'Sinov ta''til (faqat id)');
select zz.chk('D06 bayram / ta''til kunlari talab qilinmaydi (id yoki day bo''yicha): 6/6',
  (select (r->>'rate') || ' ' || (r->>'marked') || '/' || (r->>'required') from (select app.kpi_attendance('2026-11-02', '2026-11-08') r) x), '^100\.0 6/6$');
select zz.chk('D07 sinf bo''yicha ham shu kunlar (uz-5-A: 6/6)',
  (select string_agg((b->>'classKey') || ':' || (b->>'marked') || '/' || (b->>'required'), ',') from jsonb_array_elements(app.kpi_attendance('2026-11-02', '2026-11-08')->'byClass') b), '^uz-5-A:6/6$');

-- ===== (Q) Qarz muddati: barcha o'quvchilar (A6-03) =====
select zz.chk('Q01 1 / 2 / 3+ oy — ketgan (3 oy) va muzlatilgan (2 oy) ham sanaladi: 1/1/1, 2+ oy — 2; avval 1/0/0, 0',
  (select (r->>'m1') || '/' || (r->>'m2') || '/' || (r->>'m3') || ' ' || (r->>'m2plus') from (select app.kpi_debt_aging('2026-11-18 12:00+05') r) x), '^1/1/1 2$');
select zz.chk('Q02 ketgan / muzlatilgan alohida: 2 o''quvchi, 2+ oy — 2, qolgan qarz 4 600 000 (qisman to''lov ayirilgan)',
  (select (r->'inactive'->>'n') || ' ' || (r->'inactive'->>'m2plus') || ' ' || (r->'inactive'->>'sum') from (select app.kpi_debt_aging('2026-11-18 12:00+05') r) x), '^2 2 4600000$');
select zz.chk('Q03 o''qiyotganlar soni (maxraj) — 2; 1 oy ulushi — o''qiyotganlardan 50%',
  (select (r->>'students') || ' ' || (r->>'m1share') from (select app.kpi_debt_aging('2026-11-18 12:00+05') r) x), '^2 50\.0$');
select zz.chk('Q04 Telegram kunlik «Qarzdorlar» — xuddi shunday (ketgan / muzlatilgan bilan)',
  zz.as('U_DIR', $q$select (d->>'m2plus') || ' ' || (d->'inactive'->>'n') from (select public.director_daily('2026-11-16')->'debt' d) x$q$), '^2 2$');
select zz.chk('Q05 haftalik «Qarz muddati» — 2+ oy: 2',
  zz.as('U_DIR', $q$select public.director_weekly('2026-11-18')->'debt'->'cur'->>'m2plus'$q$), '^2$');
select zz.chk('Q06 o''tmishdagi payt (2026-09-05): faqat avgust muddati o''tgan — 1 o''quvchi (ketgan), 1 oy',
  (select (r->>'m1') || '/' || (r->>'m2plus') || ' ' || (r->'inactive'->>'n') from (select app.kpi_debt_aging('2026-09-05 12:00+05') r) x), '^1/0 1$');

-- ===== (P) Holati 'paid', "paidAmount" bo'sh — to'liq to'langan (A6-04) =====
select zz.chk('P01 «Reja va tushum» oktyabr: hisoblangan 4 000 000, to''langan 1 400 000, qarz 2 600 000 (to''langan + qarz = hisoblangan), 35%',
  zz.as('U_FM', $q$select (m->>'billed') || ' ' || (m->>'paid') || ' ' || (m->>'debt') || ' ' || (m->>'rate') from (select public.finance_plan_actual('2026-10', '2026-10')->'months'->0 m) x$q$),
  '^4000000 1400000 2600000 35\.0$');
select zz.chk('P02 yig''ilish foizi 10-sana kesimidan (faqat to''liq to''langanlar, 25%) past emas',
  zz.as('U_FM', $q$select ((m->>'rate')::numeric >= (m->>'cut10')::numeric)::text || ' ' || (m->>'cut10') from (select public.finance_plan_actual('2026-10', '2026-10')->'months'->0 m) x$q$), '^true 25\.0$');
select zz.chk('P03 sinf bo''yicha va jami ham: to''langan 1 400 000',
  zz.as('U_FM', $q$select (r->'rows'->0->>'paid') || ' ' || (r->'total'->>'paid') || ' ' || (r->'total'->>'debt') from (select public.finance_plan_actual('2026-10', '2026-10') r) x$q$), '^1400000 1400000 2600000$');
select zz.chk('P04 haftalik «To''lov yig''ilishi»: to''liq — 25%, qisman to''lovlar bilan — 35% (avval 10% — to''liqdan past edi)',
  (select (r->>'month') || ' ' || (r->>'rate') || ' ' || (r->>'ratePartial') from (select app.kpi_collection('2026-11-05 12:00+05') r) x), '^2026-10 25\.0 35\.0$');

-- ===== (T) Telegram kunlik hisobot: oldingi hisobotdan keyin + barcha biriktirilmaganlar (A6-01, A6-07) =====
select zz.chk('T01 dushanba: oyna — oldingi MUVAFFAQIYATLI hisobotdan (juma 19:00:05; shanbadagi yetkazilmagani va boshqa tur e''tiborsiz)',
  zz.as('U_DIR', $q$select ((public.director_daily('2026-11-16')->'since'->>'from')::timestamptz = '2026-11-13 19:00:05+05')::text$q$), '^true$');
select zz.chk('T02 juma kechqurun, shanba, yakshanba tushganlar: 4 ta, 1 700 000 (kutilayotgan, avans ko''chirmasi, bo''lingan to''lov bolasi — yo''q)',
  zz.as('U_DIR', $q$select (s->>'count') || ' ' || (s->>'sum') from (select public.director_daily('2026-11-16')->'since' s) x$q$), '^4 1700000$');
select zz.chk('T03 kassa kuni bo''yicha: 13 (kechqurun + shanba kiritilgan juma sanali qo''lda to''lov), 14, 15',
  zz.as('U_DIR', $q$select string_agg((b->>'day') || ':' || (b->>'count') || ':' || (b->>'sum'), ',' order by b->>'day') from jsonb_array_elements(public.director_daily('2026-11-16')->'since'->'byDay') b$q$),
  '^2026-11-13:2:500000,2026-11-14:1:400000,2026-11-15:1:800000$');
select zz.chk('T04 bloklar kesishmaydi: bugungi to''lovlar 2 ta 1 670 000; bugun orqa sana bilan — 1 ta 25 000',
  zz.as('U_DIR', $q$select (d->'payments'->>'count') || ' ' || (d->'payments'->>'sum') || ' | ' || (d->'late'->>'count') || ' ' || (d->'late'->>'sum') from (select public.director_daily('2026-11-16') d) x$q$),
  '^2 1670000 \| 1 25000$');
select zz.chk('T05 juma hisoboti: oyna payshanba 19:00:03 dan — payshanba kechqurungi 1 ta (10 000)',
  zz.as('U_DIR', $q$select (s->>'count') || ' ' || (s->>'sum') || ' ' || ((s->>'from')::timestamptz = '2026-11-12 19:00:03+05')::text from (select public.director_daily('2026-11-13')->'since' s) x$q$), '^1 10000 true$');
select zz.chk('T06 oldingi hisobot 31 kundan eski — oyna oxirgi 31 kun (12-oktyabr 00:00 dan)',
  zz.as('U_DIR', $q$select ((public.director_daily('2026-11-12')->'since'->>'from')::timestamptz = '2026-10-12 00:00+05')::text$q$), '^true$');
select zz.chk('T07 oldingi hisobot yo''q (birinchi hisobot) — since null',
  zz.as('U_DIR', $q$select jsonb_typeof(public.director_daily('2026-09-01')->'since')$q$), '^null$');
-- asOf — "receivedAt" bilan bir xil asos: sinov bazasida sinov soati (ishlab chiqarish yo'li — R11)
insert into app.fin_clock (id, t) values (1, '2026-11-16 19:00:07+05') on conflict (id) do update set t = excluded.t;
select zz.as('U_DIR', $q$select public.director_daily('2026-11-16')->>'asOf'$q$) as t08 \gset
delete from app.fin_clock where id = 1;
select zz.chk('T08 asOf — ma''lumot olingan payt, "receivedAt" bilan bir xil asosda (sinov bazasida — sinov soati 19:00:07)',
  ((:'t08')::timestamptz = '2026-11-16 19:00:07+05')::text, '^true$');
select zz.chk('T09 biriktirilmagan — BARCHASI («To''lovlar» ro''yxati bilan bir xil): 2 ta, 120 000, eng eskisi 10-noyabr; avval faqat bugungi 1 ta',
  zz.as('U_DIR', $q$select (d->>'unmatched') || ' ' || (d->>'unmatchedSum') || ' ' || (d->>'unmatchedSince') from (select public.director_daily('2026-11-16') d) x$q$),
  '^2 120000 2026-11-10$');
select zz.chk('T10 kassir director_daily ni chaqira olmaydi (o''zgarmagan)', zz.as('U_KAS', $q$select public.director_daily('2026-11-16')::text$q$), '^ERR 42501');

-- ===== (R) Ikki bosqichli onlayn to'lov: 'since' — tushumga aylangan payt ("receivedAt") bo'yicha (A6-01, 2-raund) =====
--   Ko'rib chiquvchi ssenariysi: juma 13-noyabr Click prepare 18:59:50 (hisobotdan OLDIN; qator 'prepared' — tushum emas), kunlik hisobot
--   19:00:05 (urug'dagi 'sent' qator), complete 19:30 (hisobotdan KEYIN). Avval u HECH QAYSI hisobotda chiqmasdi: jumada hali tushum emas
--   edi, dushanba 'since' esa juma 19:00:05 dan keyin KIRITILGANlarni olardi ("createdAt" 18:59:50 qolgan).
--   Triggerlar yoqilgan (server yozuvi: JWT'siz — app.is_system), vaqt — sinov soati (app.fin_clock). Har amal o'z so'rovida, tekshiruv —
--   keyingisida (bitta so'rov o'z o'zgarishini ko'rmaydi). Ustun to_jsonb(...) orqali o'qiladi: tuzatishsiz bazada ham FAIL (xato emas).
insert into app.fin_clock (id, t) values (1, '2026-11-13 18:00+05') on conflict (id) do update set t = excluded.t;
-- hisobotdan OLDIN prepare va complete — juma hisobotida bor edi: dushanba 'since'ga tushmasin
insert into public.payments (id, "studentId", provider, amount, status, raw, matched, "createdAt") values
  ('click_r2', 'IQ-0301', 'click', 7000, 'prepared', '{"mode":"precise"}', true, '2026-11-13 18:00+05');
insert into app.fin_clock (id, t) values (1, '2026-11-13 18:30+05') on conflict (id) do update set t = excluded.t;
update public.payments set status = 'applied', merchant_confirm_id = 'mc_r2' where id = 'click_r2';
-- biriktirilmagan (tushum) — hisobotdan oldin keldi, shanba biriktiriladi: 'unmatched' → 'applied' ikkalasi ham tushum (qayta sanalmasin)
insert into public.payments (id, "studentId", provider, amount, status, raw, matched, "createdAt") values
  ('u_r3', null, 'uzum', 9000, 'unmatched', null, false, '2026-11-13 18:40+05');
insert into app.fin_clock (id, t) values (1, '2026-11-13 18:59:50+05') on conflict (id) do update set t = excluded.t;
insert into public.payments (id, "studentId", provider, amount, status, raw, matched, "createdAt") values
  ('click_r1', 'IQ-0301', 'click', 500000, 'prepared', '{"mode":"precise"}', true, '2026-11-13 18:59:50+05');
select zz.chk('R01 prepare — tushum emas: "receivedAt" bo''sh, juma to''lovlari (kassa kuni) orasida yo''q',
  (select coalesce(to_jsonb(p) ->> 'receivedAt', 'NULL') || ' ' || (select count(*) from app.fin_receipts('2026-11-13', '2026-11-13') r where r.id = 'click_r1')
     from public.payments p where p.id = 'click_r1'), '^NULL 0$');
insert into app.fin_clock (id, t) values (1, '2026-11-13 19:30+05') on conflict (id) do update set t = excluded.t;
update public.payments set status = 'applied', amount = 500000, merchant_confirm_id = 'mc_r1' where id = 'click_r1';
insert into app.fin_clock (id, t) values (1, '2026-11-14 10:00+05') on conflict (id) do update set t = excluded.t;
update public.payments set status = 'applied', "studentId" = 'IQ-0301', matched = true where id = 'u_r3';
-- tarixiy import / server yozuvi tushum holatida va o'z vaqti bilan — "receivedAt" = o'sha vaqt (import payti emas)
insert into public.payments (id, "studentId", provider, amount, status, raw, matched, "createdAt") values
  ('p_imp_r6', 'IQ-0302', 'bank', 11000, 'applied', null, true, '2026-11-13 12:00+05');
-- yakshanba 23:59 prepare, dushanba 00:05 complete — dushanba 'since'da (yuqori chegara "createdAt" < bugun boshi; 'payments' va
--   'late'da yo'q). Yuqori chegara "receivedAt" bo'lsa — hech qaysi hisobotda chiqmasdi.
insert into app.fin_clock (id, t) values (1, '2026-11-15 23:59+05') on conflict (id) do update set t = excluded.t;
insert into public.payments (id, "studentId", provider, amount, status, raw, matched, "createdAt") values
  ('click_r7', 'IQ-0301', 'click', 13000, 'prepared', '{"mode":"precise"}', true, '2026-11-15 23:59+05');
insert into app.fin_clock (id, t) values (1, '2026-11-16 00:05+05') on conflict (id) do update set t = excluded.t;
update public.payments set status = 'applied', merchant_confirm_id = 'mc_r7' where id = 'click_r7';
select zz.chk('R02 complete (19:30) — "receivedAt" = tushumga aylangan payt; "createdAt" o''zgarmagan (18:59:50)',
  (select ((to_jsonb(p) ->> 'receivedAt')::timestamptz = '2026-11-13 19:30+05')::text || ' ' || (p."createdAt" = '2026-11-13 18:59:50+05')::text
     from public.payments p where p.id = 'click_r1'), '^true true$');
select zz.chk('R03 dushanba ''since'': juma 18:59:50 da prepare, hisobotdan keyin complete bo''lgan Click ham — 6 ta, 2 213 000 (avval 5 ta, 1 713 000 — yo''qolardi)',
  zz.as('U_DIR', $q$select (s->>'count') || ' ' || (s->>'sum') from (select public.director_daily('2026-11-16')->'since' s) x$q$), '^6 2213000$');
select zz.chk('R04 kassa kuni bo''yicha: 13 — 3 ta 1 000 000 (Click o''z kuni — kiritilgan juma), 15 — yakshanba 23:59 dagi bilan 2 ta',
  zz.as('U_DIR', $q$select string_agg((b->>'day') || ':' || (b->>'count') || ':' || (b->>'sum'), ',' order by b->>'day') from jsonb_array_elements(public.director_daily('2026-11-16')->'since'->'byDay') b$q$),
  '^2026-11-13:3:1000000,2026-11-14:1:400000,2026-11-15:2:813000$');
select zz.chk('R05 bloklar kesishmaydi: bugungi to''lovlar va bugun orqa sana bilan — o''zgarmagan (2 ta 1 670 000 | 1 ta 25 000)',
  zz.as('U_DIR', $q$select (d->'payments'->>'count') || ' ' || (d->'payments'->>'sum') || ' | ' || (d->'late'->>'count') || ' ' || (d->'late'->>'sum') from (select public.director_daily('2026-11-16') d) x$q$),
  '^2 1670000 \| 1 25000$');
select zz.chk('R06 bir marta qo''yiladi: hisobotdan oldin complete (18:30), biriktirilgan (tushum 18:40 dan), import (o''z vaqti 12:00) — ''since''ga tushmaydi',
  (select string_agg(p.id || '=' || to_char((to_jsonb(p) ->> 'receivedAt')::timestamptz at time zone 'Asia/Tashkent', 'DD HH24:MI'), ',' order by p.id)
     from public.payments p where p.id in ('click_r2', 'u_r3', 'p_imp_r6', 'click_r7')), '^click_r2=13 18:30,click_r7=16 00:05,p_imp_r6=13 12:00,u_r3=13 18:40$');
select zz.chk('R07 Direktor REST orqali "receivedAt"ni o''zgartira olmaydi (pay_direct_guard: pul ustuni)',
  zz.as('U_DIR', $q$update public.payments set "receivedAt" = '2026-11-16 08:00+05' where id = 'click_r1' returning id$q$), '^ERR 42501');
-- Direktorning «🚫 Bekor»i (sahifa setDoc — upsert {status:'canceled'}) qo'llanmagan yozuvda ishlayveradi, "receivedAt" o'zgarmaydi
insert into public.payments (id, "studentId", provider, amount, status, raw, matched, "createdAt") values
  ('u_r4', null, 'click', 15000, 'unmatched', null, false, '2026-11-14 09:00+05');
create temp table zz_r (step text primary key, r text) on commit drop;
insert into zz_r select 'cancel', zz.as('U_DIR', $q$insert into public.payments (id, status) values ('u_r4', 'canceled') on conflict (id) do update set status = excluded.status returning status$q$);
select zz.chk('R08 «🚫 Bekor» (upsert) ishlaydi; "receivedAt" (tushgan payt, 14-noyabr 09:00) o''zgarmagan',
  (select c.r || ' ' || p.status || ' ' || ((to_jsonb(p) ->> 'receivedAt')::timestamptz = '2026-11-14 09:00+05')::text from zz_r c, public.payments p where c.step = 'cancel' and p.id = 'u_r4'),
  '^canceled canceled true$');
-- Pul RPC'si (record_manual_payment: 'pending' qator + qo'llash + 'applied' — bitta tranzaksiyada) — "receivedAt" = "createdAt" (server vaqti)
insert into app.fin_clock (id, t) values (1, '2026-11-16 11:00+05') on conflict (id) do update set t = excluded.t;
insert into zz_r select 'manual', zz.as('U_FM', $q$select public.record_manual_payment('man_r5_sinov', 'IQ-0301', 1000, 'bank')->>'ok'$q$);
select zz.chk('R09 qo''lda to''lov (Moliya menejeri): ok, "receivedAt" = "createdAt" = server vaqti (11:00)',
  (select m.r || ' ' || ((to_jsonb(p) ->> 'receivedAt')::timestamptz = p."createdAt")::text || ' ' || (p."createdAt" = '2026-11-16 11:00+05')::text || ' ' || p.status
     from zz_r m, public.payments p where m.step = 'manual' and p.id = 'man_r5_sinov'), '^true true true applied$');
select zz.chk('R10 trigger — BEFORE triggerlarning oxirgisi (pay_direct_guard mijoz yuborgan qiymatni ko''radi), nomi trg_kassa_ / trg_fin_ emas',
  (select string_agg(t.tgname, ',' order by t.tgname) from pg_trigger t where t.tgrelid = 'public.payments'::regclass and not t.tgisinternal and t.tgtype & 2 = 2),
  '(^|,)trg_pay_direct_guard,trg_pay_received$');
delete from app.fin_clock where id = 1;
-- (4-raund) ISHLAB CHIQARISH yo'li: sinov bazalari nomi sinov soatiga mos (app.fin_clock_allowed()) — savepoint ichida vaqtincha false.
--   "receivedAt" — tushumga aylantirgan UPDATE'ning haqiqiy soati (tranzaksiya boshi now() emas); asOf — director_daily boshlangan haqiqiy
--   soat (so'rovlari undan oldingi snapshot'ni ko'radi: hisobotda ko'ringan to'lov keyingi hisobotda qayta sanalmaydi).
savepoint r11;
create or replace function app.fin_clock_allowed() returns boolean language sql stable set search_path = public, app, pg_temp as $f$ select false $f$;
insert into public.payments (id, "studentId", provider, amount, status, raw, matched) values
  ('click_r11', 'IQ-0301', 'click', 21000, 'prepared', '{"mode":"precise"}', true);
select clock_timestamp() as r11c0 \gset
update public.payments set status = 'applied', merchant_confirm_id = 'mc_r11' where id = 'click_r11';
select clock_timestamp() as r11c1 \gset
select coalesce(to_jsonb(p) ->> 'receivedAt', 'NULL') as r11rcv from public.payments p where p.id = 'click_r11' \gset
select clock_timestamp() as r11c2 \gset
select zz.as('U_DIR', $q$select public.director_daily('2026-11-16')->>'asOf'$q$) as r11asof \gset
select clock_timestamp() as r11c3 \gset
rollback to savepoint r11;
select zz.chk('R11 ishlab chiqarish yo''li (sinov soatisiz): "receivedAt" — UPDATE''ning haqiqiy soati (tranzaksiya boshidan keyin); asOf — funksiya boshlangan haqiqiy soat',
  (case when :'r11rcv' = 'NULL' then 'NULL' else ((:'r11rcv')::timestamptz between (:'r11c0')::timestamptz and (:'r11c1')::timestamptz)::text
          || ' ' || ((:'r11rcv')::timestamptz > now())::text end)
  || ' ' || coalesce(((:'r11asof')::timestamptz between (:'r11c2')::timestamptz and (:'r11c3')::timestamptz)::text, 'NULL'), '^true true true$');

-- ===== (K) Kassadagi o'quv to'lovidan tashqari daromad (A6-02) =====
select case when to_regclass('public.cash_docs') is not null then 'true' else 'false' end as has_kassa \gset
\if :has_kassa
set local session_replication_role = replica;
insert into public.cash_days (id, desk, day, status, opening) values
  ('cd_main_2027-01-05', 'main', '2027-01-05', 'open', 0), ('cd_sinov_2027-01-05', 'sinov', '2027-01-05', 'open', 0);
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "clientRef", "postedAt") values
  ('k1', 'main',  'KO1', 'in_sale',     'posted', 2027, 1, '2027-01-05', 'cd_main_2027-01-05',  25000000, 'ref_k1', '2027-01-05 10:00+05'),
  ('k2', 'main',  'KO1', 'in_other',    'posted', 2027, 2, '2027-01-06', 'cd_main_2027-01-05',   3000000, 'ref_k2', '2027-01-06 10:00+05'),
  ('k3', 'main',  'KO1', 'in_other',    'posted', 2027, 3, '2027-01-06', 'cd_main_2027-01-05',   1000000, 'ref_k3', '2027-01-06 11:00+05'),
  ('k4', 'main',  'KO1', 'in_tuition',  'posted', 2027, 4, '2027-01-06', 'cd_main_2027-01-05',   2000000, 'ref_k4', '2027-01-06 12:00+05'),
  ('k5', 'main',  'KO1', 'in_sale',     'void',   2027, 5, '2027-01-07', 'cd_main_2027-01-05',   5000000, 'ref_k5', '2027-01-07 10:00+05'),
  ('k6', 'sinov', 'KO1', 'in_sale',     'posted', 2027, 1, '2027-01-05', 'cd_sinov_2027-01-05',  7000000, 'ref_k6', '2027-01-05 10:00+05'),
  ('k7', 'main',  'KO1', 'in_surplus',  'posted', 2027, 6, '2027-01-07', 'cd_main_2027-01-05',     50000, 'ref_k7', '2027-01-07 19:00+05'),
  ('k8', 'main',  'KO1', 'in_sale',     'posted', 2027, 7, '2027-02-01', 'cd_main_2027-01-05',   4000000, 'ref_k8', '2027-02-01 10:00+05'),
  ('k9', 'main',  'KO2', 'out_expense', 'posted', 2027, 1, '2027-01-05', 'cd_main_2027-01-05',  20000000, 'ref_k9', '2027-01-05 09:00+05');
insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash) values
  ('k1_1', 'k1', 1, '5010', '9020', 25000000, 'IN-04', true),   -- forma sotuvi — daromad
  ('k2_1', 'k2', 1, '5010', '9390',  3000000, 'IN-06', true),   -- boshqa kirim (to'garak, chipta) — daromad
  ('k3_1', 'k3', 1, '5010', '6390',  1000000, 'OP-16', true),   -- aniqlanmagan tushum — daromad emas
  ('k4_1', 'k4', 1, '5010', '4010',  2000000, 'IN-01', true),   -- o'quv to'lovi — Kirimda «To'lovlar» orqali allaqachon bor
  ('k5_1', 'k5', 1, '5010', '9020',  5000000, 'IN-04', true),   -- bekor qilingan hujjat
  ('k6_1', 'k6', 1, '5010', '9020',  7000000, 'IN-04', true),   -- sinov kassasi
  ('k7_1', 'k7', 1, '5010', '9390',    50000, 'IN-06', true),   -- kassa ortiqchasi (sanash farqi)
  ('k8_1', 'k8', 1, '5010', '9020',  4000000, 'IN-04', true),
  ('k9_1', 'k9', 1, '2910', '5010', 20000000, 'OP-24', true);   -- xarid (KO-2) — chiqim tomoni (kassa_link_paid → expenses)
set local session_replication_role = origin;
select zz.chk('K01 Direktor: oy bo''yicha — 2027-01: 28 000 000 (forma 25 mln + boshqa kirim 3 mln), 2027-02: 4 000 000; boshqa oy yo''q',
  zz.as('U_DIR', $q$select string_agg(k || ':' || (v->>'sum'), ',' order by k) from jsonb_each(public.finance_other_income()->'months') e(k, v)$q$), '^2027-01:28000000,2027-02:4000000$');
select zz.chk('K02 statiya bo''yicha (A4 hisobot uchun): IN-04 25 000 000, IN-06 3 000 000 — OP-16, IN-01, bekor qilingan, sinov kassasi, ortiqcha, KO-2 yo''q',
  zz.as('U_DIR', $q$select string_agg((i->>'articleId') || ':' || (i->>'sum'), ',' order by i->>'articleId') from jsonb_array_elements(public.finance_other_income()->'months'->'2027-01'->'items') i$q$),
  '^IN-04:25000000,IN-06:3000000$');
select zz.chk('K03 statiya nomi bilan', zz.as('U_DIR', $q$select public.finance_other_income()->'months'->'2027-01'->'items'->0->>'nameUz'$q$), '^Forma');
\else
select zz.chk('K00 jonli zanjir (kassa moduli yo''q): bo''sh natija, xatosiz',
  zz.as('U_DIR', $q$select public.finance_other_income()::text$q$), '^\{"months": \{\}\}$');
\endif
select zz.chk('K04 Moliya menejeri, g''aznachi, buxgalter ham o''qiydi (Direktor bilan bir xil natija, xatosiz)',
  (select (zz.as('U_DIR', $q$select public.finance_other_income()::text$q$) like '{"months": %')::text
       || (zz.as('U_FM', $q$select public.finance_other_income()::text$q$) = zz.as('U_DIR', $q$select public.finance_other_income()::text$q$))::text
       || (zz.as('U_TRE', $q$select public.finance_other_income()::text$q$) = zz.as('U_DIR', $q$select public.finance_other_income()::text$q$))::text
       || (zz.as('U_ACC', $q$select public.finance_other_income()::text$q$) = zz.as('U_DIR', $q$select public.finance_other_income()::text$q$))::text), '^truetruetruetrue$');
select zz.chk('K05 kassir, o''qituvchi va anonim — ruxsat yo''q',
  zz.as('U_KAS', $q$select public.finance_other_income()::text$q$) || ' | ' || zz.as('U_TEA', $q$select public.finance_other_income()::text$q$) || ' | ' || zz.as(null, $q$select public.finance_other_income()::text$q$),
  '^ERR 42501 .* \| ERR 42501 .* \| ERR 42501 ');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
