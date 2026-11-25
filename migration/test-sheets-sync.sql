-- =====================================================================
-- test-sheets-sync.sql — sheets-sync.sql (Google Sheets jadvaliga avtomatik yozish, egasi 2026-11-25) sinovi:
--   (A) huquqlar — faqat service_role; anon / authenticated (Direktor ham) chaqira olmaydi, navbat va holatni ko'rmaydi;
--   (D) har varaqning sarlavhasi, qiymatlari va tartibi — admin panel qoidalari bilan qo'lda hisoblangan kutilgan sonlar
--       (paidOf / debtOf, arxiv qoidasi, kassa kuni, tushum ta'rifi, oy kirimi, yig'im foizi), sezgir maydonlar yo'qligi,
--       kalitli tanlov (qator / o'quvchi kalitlari), boshlang'ich oy;
--   (B) o'zgarishlar navbati — triggerlar, faqat ko'rinadigan ustunlar, kalit almashganda ikkala kalit, bekor qilingan o'zgarish,
--       xizmat tirik bo'lmasa navbat o'smasligi;
--   (C) ijara (bitta xizmat nusxasi), navbatni o'qish / o'chirish, to'liq yozish belgisi, eski yozuvlarni tozalash.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida (nomi fx_… / …sinov… / …test… — sinov soati kerak),
--   kanonik zanjirdan keyin (jonli yoki --dev zanjir):
--     bash migration/chain.sh --no-lock-timeout | psql -d fx_sinov -q && psql -d fx_sinov -X -f migration/test-sheets-sync.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Ma'lumot to'qima (telefonlar «+998 00 …», summalar shartli).
--   (K) Kassa moduli bo'lsa (--dev) — oylik hisobotdagi kassadagi boshqa kirim (finance_other_income bilan bir xil).
--   Oxirida yozilgan tekshiruvlar soni kutilgan son bilan solishtiriladi (yo'qolgan tekshiruv — FAIL): --dev 58, jonli 56 (ZZ bilan).
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- kutilgan tekshiruvlar soni — (K) bo'limida: --dev zanjirda 57, jonli zanjirda 55
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-sheets-sync.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
  if not app.fin_clock_allowed() then
    raise exception 'test-sheets-sync.sql: sinov soati kerak — baza nomi fx_… / …sinov… / …test… bo''lsin';
  end if;
end $g$;
set local iqror.migrating = '1';
insert into app.fin_clock (id, t) values (1, '2026-11-15 12:00+05') on conflict (id) do update set t = excluded.t;   -- bugun 2026-11-15
update app.sheets_state set beat = null, holder = null where id = 1;
delete from app.sheets_outbox;
insert into public.users (id, email, role, status) values ('U_DIR', 'd@x', 'director', 'active')
on conflict (id) do update set role = excluded.role, status = excluded.status;

insert into public.students (id, "studentId", name, grade, "classLetter", lang, track, "payStatus", "activeFrom", "stopFrom", "exitAt", "exitReason", attendance) values
  ('SH-1', 'IQ-9001', 'Sinov Bir',   5,  'A', 'uz', 'umumiy', '',            '2026-09-01', '',           null,                   null,      95),
  ('SH-2', 'IQ-9002', 'Sinov Ikki',  5,  'B', 'ru', null,     'muzlatilgan', '2026-09-01', '2026-11-01', null,                   null,      null),
  ('SH-3', '',        'Sinov Uch',   7,  'A', 'uz', null,     'chiqdi',      '2026-09-01', '2026-10-31', '2026-10-31',           'soglik',  null),
  ('SH-4', 'IQ-9004', 'Sinov Tort',  11, 'A', 'uz', null,     'chiqdi',      null,         '2026-05-31', '2026-05-31T09:00:00Z', 'bitirdi', null),
  ('SH-5', 'IQ-9005', 'Sinov Besh',  6,  'A', 'en', null,     'chiqdi',      null,         '',           '2026-12-31',           'kochdi',  null),
  ('SH-6', 'IQ-9006', 'Sinov Olti',  6,  'A', 'uz', null,     'sinov',       null,         null,         null,                   null,      null);
insert into public.student_private (id, pinfl, metrika, health, "parentPhone", "parentPhone2", "fatherName", "motherName", guardian, "birthDate", address, "contractAmount", "siblingDiscount") values
  ('SH-1', '99999999999999', 'SINOV-METRIKA', 'SINOV-SALOMATLIK', '+998 00 111 22 33', '+998 00 444 55 66', 'Sinov Otasi', 'Sinov Onasi', null, '2015-03-04', 'Sinov ko''chasi 1', 1000, 'ha'),
  ('SH-2', null, null, null, '+998 00 777 88 99', null, null, null, 'Sinov Vasiy', null, null, null, null);
insert into public.invoices (id, "studentId", "studentName", "classKey", month, amount, "paidAmount", status, "baseAmount", discount, "paidAt", "createdAt") values
  ('inv1',  'IQ-9001', 'Sinov Bir',        'uz-5-A',  '2026-10', 1000, 1000, 'paid',     1200, 200,  '2026-10-05 05:00:00Z', '2026-10-01 03:00:00Z'),
  ('inv2',  'IQ-9001', 'Sinov Bir',        'uz-5-A',  '2026-11', 1000, 400,  'partial',  1000, 0,    null,                   '2026-11-01 03:00:00Z'),
  ('inv3',  'IQ-9002', 'Sinov Ikki',       'ru-5-B',  '2026-11', 1000, 0,    'pending',  null, null, null,                   '2026-11-01 03:00:00Z'),
  ('inv4',  'IQ-9002', 'Sinov Ikki',       'ru-5-B',  '2026-10', 1000, 0,    'canceled', null, null, null,                   '2026-10-01 03:00:00Z'),
  ('inv5',  'SH-3',    'Sinov Uch',        'uz-7-A',  '2026-10', 800,  300,  'pending',  null, null, null,                   '2026-10-01 03:00:00Z'),
  ('inv6',  'IQ-9001', 'Sinov Bir',        'uz-5-A',  '2026-12', 1000, 0,    'pending',  null, null, null,                   '2026-11-14 03:00:00Z'),
  ('inv7',  'IQ-ESKI', 'Sinov Eski Karta', 'uz-4-B',  '2026-09', 700,  0,    'pending',  null, null, null,                   '2026-09-01 03:00:00Z'),
  ('inv8',  'IQ-9002', 'Sinov Ikki',       'ru-5-B',  '2026-09', 900,  900,  'reversed', null, null, null,                   '2026-09-01 03:00:00Z'),
  ('inv9',  'IQ-9001', 'Sinov Bir',        'uz-5-A',  '2026-09', 1000, 0,    'paid',     null, null, '2026-09-03 05:00:00Z', '2026-09-01 03:00:00Z'),
  ('inv10', 'IQ-9004', 'Sinov Tort',       'uz-10-A', '2026-05', 1000, 1200, 'partial',  null, null, null,                   '2026-05-01 03:00:00Z');
insert into public.payments (id, "studentId", "invoiceId", provider, amount, status, raw, "payerName", "createdAt") values
  ('P1',     'IQ-9001', 'inv1', 'click',  1000,  'applied',   null,                                   null,                     '2026-10-05 05:00:00Z'),
  ('P2',     'IQ-9001', 'inv2', 'cash',   400,   'applied',   '{"manual": true, "date": "2026-10-30"}', 'Sinov Otasi',            '2026-11-03 04:00:00Z'),
  ('P3',     'IQ-9002', 'inv3', 'uzum',   500,   'prepared',  null,                                   null,                     '2026-11-04 06:00:00Z'),
  ('P4',     'SH-3',    'inv5', 'payme',  300,   'confirmed', null,                                   null,                     '2026-10-20 07:00:00Z'),
  ('P5',     null,      null,   'click',  250,   'unmatched', null,                                   'Sinov To''lovchi [kod]', '2026-11-10 10:00:00Z'),
  ('P6',     'IQ-9001', null,   'reattr', 100,   'applied',   null,                                   null,                     '2026-11-11 05:00:00Z'),
  ('P7:s:1', 'IQ-9001', 'inv2', 'click',  50,    'applied',   null,                                   null,                     '2026-11-12 05:00:00Z'),
  ('P8',     'IQ-9002', null,   'cash',   'NaN', 'applied',   null,                                   null,                     '2026-11-13 05:00:00Z');
insert into public.expenses (id, date, month, category, amount, note, "createdAt") values
  ('E1', '2026-10-15', '',        'Ijara', 300, 'Sinov ijara', '2026-10-15 05:00:00Z'),
  ('E2', '2026-11-02', '2026-11', '',      100, null,          '2026-11-02 05:00:00Z');
insert into public.refunds (id, target, "targetId", "studentId", "studentName", amount, reason, month, "createdAt") values
  ('R1', 'invoice', 'inv1', 'IQ-9001', 'Sinov Bir',  50, 'Sinov qaytarish', '2026-10', '2026-10-25 05:00:00Z'),
  ('R2', 'credit',  null,   'IQ-9002', 'Sinov Ikki', 30, null,              '',        '2026-11-05 05:00:00Z');
insert into public.student_credit (id, "studentId", credit) values ('IQ-9002', 'IQ-9002', 150), ('IQ-9001', 'IQ-9001', -0.3);

create schema if not exists zz;
-- p_who: 'anon' | 'service' (server: service_role) | foydalanuvchi id (authenticated + JWT sub)
create or replace function zz.as(p_who text, p_q text) returns text language plpgsql as $$
declare r text;
begin
  if p_who = 'anon' then
    perform set_config('request.jwt.claims', '', true); execute 'set local role anon';
  elsif p_who = 'service' then
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true); execute 'set local role service_role';
  else
    perform set_config('request.jwt.claims', json_build_object('sub', p_who, 'role', 'authenticated')::text, true); execute 'set local role authenticated';
  end if;
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
-- Varaq natijalari (server nomidan olinadi), katak — 1-ustun (kalit) va sarlavha nomi bo'yicha.
create table if not exists zz.tabs (name text primary key, j jsonb);
truncate zz.tabs;
create or replace function zz.take(p_name text, p_q text) returns void language plpgsql as $$
declare r text := zz.as('service', p_q);
begin
  insert into zz.tabs (name, j) values (p_name, case when r like 'ERR %' or r = '<null>' then jsonb_build_object('err', r) else r::jsonb end);
end $$;
create or replace function zz.cell(p_name text, p_key text, p_col text) returns text language sql as $$
  select coalesce((r.value -> (h.ord::int - 1)) #>> '{}', 'null')
    from zz.tabs t, jsonb_array_elements(t.j -> 'rows') r(value), jsonb_array_elements_text(t.j -> 'header') with ordinality h(name, ord)
   where t.name = p_name and (r.value ->> 0) = p_key and h.name = p_col
   limit 1
$$;
create or replace function zz.cells(p_name text, p_key text, p_cols text[]) returns text language sql as $$
  select string_agg(coalesce(zz.cell(p_name, p_key, c), '<yo''q>'), '|' order by o) from unnest(p_cols) with ordinality u(c, o)
$$;
create or replace function zz.keys(p_name text) returns text language sql as $$
  select coalesce((select string_agg(r.value ->> 0, ',' order by r.o) from zz.tabs t, jsonb_array_elements(t.j -> 'rows') with ordinality r(value, o)
                    where t.name = p_name), '')
$$;
create or replace function zz.hdr(p_name text, p_want jsonb) returns text language sql as $$
  select case when t.j -> 'header' = p_want then 'ok' else coalesce((t.j -> 'header')::text, t.j::text) end from zz.tabs t where t.name = p_name
$$;
create or replace function zz.money(p_name text) returns text language sql as $$
  select coalesce(string_agg(t.j -> 'header' ->> (m.v)::int, ',' order by m.o), '') from zz.tabs t, jsonb_array_elements_text(t.j -> 'money') with ordinality m(v, o)
   where t.name = p_name
$$;
create or replace function zz.outbox() returns text language sql as $$
  select coalesce(string_agg(src || ':' || coalesce(key, 'null'), ',' order by id), '') from app.sheets_outbox
$$;

-- ===== (A) huquqlar =====
select zz.chk('A01 mehmon (anon) varaq ma''lumotini ololmaydi', zz.as('anon', $q$select public.sheets_tab('students')::text$q$), '^ERR 42501');
select zz.chk('A02 Direktor ham varaq ma''lumotini ololmaydi (faqat server xizmati)', zz.as('U_DIR', $q$select public.sheets_tab('debts')::text$q$), '^ERR 42501');
select zz.chk('A03 Direktor navbat RPC''larini chaqira olmaydi (beat, release, pull, ack, full_begin, full_end)',
  zz.as('U_DIR', $q$select public.sheets_beat('x')::text$q$) || ' ' || zz.as('U_DIR', $q$select public.sheets_release('x')::text$q$) || ' ' ||
  zz.as('U_DIR', $q$select public.sheets_pull('x')::text$q$) || ' ' || zz.as('U_DIR', $q$select public.sheets_ack('x', '{1}')::text$q$) || ' ' ||
  zz.as('U_DIR', $q$select public.sheets_full_begin('x')::text$q$) || ' ' || zz.as('U_DIR', $q$select public.sheets_full_end('x')::text$q$),
  '^ERR 42501[^E]*ERR 42501[^E]*ERR 42501[^E]*ERR 42501[^E]*ERR 42501[^E]*ERR 42501');
select zz.chk('A04 navbat va holat jadvallari — Direktor va mehmon o''qiy olmaydi',
  zz.as('U_DIR', $q$select count(*)::text from app.sheets_outbox$q$) || ' ' || zz.as('anon', $q$select count(*)::text from app.sheets_state$q$),
  '^ERR 42501.* ERR 42501');
select zz.chk('A05 server ham jadvallarni to''g''ridan-to''g''ri o''qimaydi (faqat RPC orqali)', zz.as('service', $q$select count(*)::text from app.sheets_outbox$q$), '^ERR 42501');
select zz.chk('A06 ichki varaq funksiyalari — Direktor va server chaqira olmaydi',
  zz.as('U_DIR', $q$select app.sheets_tab_students()::text$q$) || ' ' || zz.as('service', $q$select app.sheets_tab_debts()::text$q$) || ' ' ||
  zz.as('U_DIR', $q$select count(*)::text from app.sheets_stu('2026-11-15')$q$),
  '^ERR 42501.* ERR 42501.* ERR 42501');
select zz.chk('A07 server (service_role) varaqni oladi', zz.as('service', $q$select public.sheets_tab('students') -> 'header' ->> 0$q$), '^O''quvchi ID$');

-- ===== (D) varaqlar (server nomidan, sinov ma'lumoti bilan) =====
select zz.take('students', $q$select public.sheets_tab('students')::text$q$);
select zz.take('invoices', $q$select public.sheets_tab('invoices')::text$q$);
select zz.take('inv_k1', $q$select public.sheets_tab('invoices', array['inv2'])::text$q$);
select zz.take('inv_k2', $q$select public.sheets_tab('invoices', null, array['IQ-9002'])::text$q$);
select zz.take('inv_k3', $q$select public.sheets_tab('invoices', '{}'::text[])::text$q$);
select zz.take('inv_k4', $q$select public.sheets_tab('invoices', array['inv2'], array['SH-3'])::text$q$);
select zz.take('inv_f', $q$select public.sheets_tab('invoices', null, null, '2026-11')::text$q$);
select zz.take('payments', $q$select public.sheets_tab('payments')::text$q$);
select zz.take('pay_k', $q$select public.sheets_tab('payments', null, array['IQ-9002'])::text$q$);
select zz.take('pay_f', $q$select public.sheets_tab('payments', null, null, '2026-11')::text$q$);
select zz.take('debts', $q$select public.sheets_tab('debts')::text$q$);
select zz.take('monthly', $q$select public.sheets_tab('monthly')::text$q$);
select zz.take('mon_f', $q$select public.sheets_tab('monthly', p_from => '2026-10')::text$q$);
select zz.take('expenses', $q$select public.sheets_tab('expenses')::text$q$);
select zz.take('refunds', $q$select public.sheets_tab('refunds')::text$q$);

select zz.chk('D01 O''quvchilar — sarlavha', zz.hdr('students', $j$["O'quvchi ID", "F.I.Sh.", "Sinf", "Yo'nalish", "Til", "Holati", "O'qishni boshlagan",
  "Chiqqan sana", "Tug'ilgan sana", "Otasi", "Otasining telefoni", "Onasi", "Onasining telefoni", "Vasiy", "Manzil", "Shartnoma summasi",
  "Aka-uka chegirmasi", "Joriy qarz", "Qarzli oylar", "Avans (ortiqcha to'lov)"]$j$), '^ok$');
select zz.chk('D02 O''quvchilar — faol o''quvchi: karta, ota-ona, shartnoma; joriy qarz faqat shu oygacha (dekabr kirmaydi), manfiy avans — 0',
  zz.cells('students', 'IQ-9001', array['F.I.Sh.', 'Sinf', 'Yo''nalish', 'Til', 'Holati', 'O''qishni boshlagan', 'Chiqqan sana', 'Tug''ilgan sana', 'Otasi',
    'Otasining telefoni', 'Onasi', 'Onasining telefoni', 'Vasiy', 'Manzil', 'Shartnoma summasi', 'Aka-uka chegirmasi', 'Joriy qarz', 'Qarzli oylar',
    'Avans (ortiqcha to''lov)']),
  '^Sinov Bir\|5-A\|umumiy\|O''zbek\|Faol\|2026-09-01\|null\|2015-03-04\|Sinov Otasi\|\+998 00 111 22 33\|Sinov Onasi\|\+998 00 444 55 66\|null\|Sinov ko''chasi 1\|1000\|ha\|600\|1\|0$');
select zz.chk('D03 O''quvchilar — holatlar: muzlatilgan, arxiv (chiqqan / bitirgan, chiqqan sana bilan), kelajakda chiqadi, sinov; til',
  zz.cells('students', 'IQ-9002', array['Holati', 'Til', 'Vasiy', 'Joriy qarz', 'Avans (ortiqcha to''lov)']) || ' / ' ||
  zz.cells('students', 'SH-3', array['Holati', 'Chiqqan sana']) || ' / ' || zz.cells('students', 'IQ-9004', array['Holati', 'Chiqqan sana']) || ' / ' ||
  zz.cells('students', 'IQ-9005', array['Holati', 'Til']) || ' / ' || zz.cell('students', 'IQ-9006', 'Holati'),
  '^Muzlatilgan\|Rus\|Sinov Vasiy\|1000\|150 / Chiqqan \(arxiv\)\|2026-10-31 / Bitirgan \(arxiv\)\|2026-05-31 / Chiqadi: 2026-12-31\|Ingliz / Sinov$');
select zz.chk('D04 sezgir maydonlar va ketish sababi varaqqa yozilmaydi (JSHSHIR, metrika, salomatlik, «soglik», «kochdi»)',
  (select case when position('99999999999999' in j::text) + position('SINOV-METRIKA' in j::text) + position('SINOV-SALOMATLIK' in j::text)
                    + position('soglik' in j::text) + position('kochdi' in j::text) = 0 then 'yo''q' else j::text end from zz.tabs where name = 'students'),
  '^yo''q$');
select zz.chk('D05 O''quvchilar — tartib: avval faol (sinf, ism), oxirida arxiv', zz.keys('students'), '^IQ-9001,IQ-9002,IQ-9005,IQ-9006,SH-3,IQ-9004$');
select zz.chk('D06 summalar jadvalga SON bo''lib boradi (matn emas)',
  (select string_agg(jsonb_typeof(r.value -> 17) || '/' || jsonb_typeof(r.value -> 15), ',') from zz.tabs t, jsonb_array_elements(t.j -> 'rows') r(value)
    where t.name = 'students' and r.value ->> 0 = 'IQ-9001'), '^number/number$');

select zz.chk('D07 Oylik to''lovlar — sarlavha', zz.hdr('invoices', $j$["Kalit (ID)", "Oy", "O'quvchi ID", "F.I.Sh.", "Sinf", "Asl summa", "Chegirma",
  "Hisoblangan", "To'langan", "Qarz", "Holati", "To'liq to'langan vaqti", "Yaratilgan"]$j$), '^ok$');
select zz.chk('D08 Oylik to''lovlar — paidOf / debtOf: «paid» (paidAmount 0 bo''lsa ham) — summa; qaytarilgan / bekor — 0; qisman; to''lanmagan; ortiqcha to''langan',
  zz.cells('invoices', 'inv9', array['To''langan', 'Qarz', 'Holati']) || ' / ' || zz.cells('invoices', 'inv8', array['To''langan', 'Qarz', 'Holati']) || ' / ' ||
  zz.cells('invoices', 'inv4', array['To''langan', 'Qarz', 'Holati']) || ' / ' || zz.cells('invoices', 'inv2', array['To''langan', 'Qarz', 'Holati']) || ' / ' ||
  zz.cells('invoices', 'inv3', array['To''langan', 'Qarz', 'Holati']) || ' / ' || zz.cells('invoices', 'inv10', array['To''langan', 'Qarz', 'Holati']),
  '^1000\|0\|To''langan / 0\|0\|Qaytarilgan \(bekor\) / 0\|0\|Bekor qilingan / 400\|600\|Qisman to''langan / 0\|1000\|To''lanmagan / 1200\|0\|To''langan$');
select zz.chk('D09 Oylik to''lovlar — sinf (yozilgan paytdagi kalitdan), asl summa / chegirma, to''langan vaqti (Toshkent), kartasiz o''quvchi ismi',
  zz.cells('invoices', 'inv1', array['Oy', 'O''quvchi ID', 'F.I.Sh.', 'Sinf', 'Asl summa', 'Chegirma', 'Hisoblangan', 'To''liq to''langan vaqti', 'Yaratilgan']) || ' / ' ||
  zz.cells('invoices', 'inv3', array['Sinf', 'Asl summa']) || ' / ' || zz.cells('invoices', 'inv7', array['F.I.Sh.', 'Sinf']),
  '^2026-10\|IQ-9001\|Sinov Bir\|5-A\|1200\|200\|1000\|2026-10-05 10:00\|2026-10-01 08:00 / 5-B\|null / Sinov Eski Karta\|4-B$');
select zz.chk('D10 Oylik to''lovlar — tartib: oy, sinf raqami, ism', zz.keys('invoices'), '^inv10,inv7,inv9,inv8,inv1,inv4,inv5,inv2,inv3,inv6$');
select zz.chk('D11 Oylik to''lovlar — kalitli tanlov: qator kaliti; o''quvchi kaliti; bo''sh ro''yxat; ikkalasi; boshlang''ich oy',
  zz.keys('inv_k1') || ' / ' || zz.keys('inv_k2') || ' / [' || zz.keys('inv_k3') || '] / ' || zz.keys('inv_k4') || ' / ' || zz.keys('inv_f'),
  '^inv2 / inv8,inv4,inv3 / \[\] / inv5,inv2 / inv2,inv3,inv6$');

select zz.chk('D12 To''lovlar — sarlavha', zz.hdr('payments', $j$["Kalit (ID)", "Sana (kassa kuni)", "Kiritilgan vaqt", "O'quvchi ID", "F.I.Sh.", "Sinf",
  "Summa", "Usul", "Holati", "Tushumga kiradimi", "Hisob-faktura oyi", "To'lovchi", "Fiskal chek"]$j$), '^ok$');
select zz.chk('D13 To''lovlar — qo''lda to''lovning kassa kuni (raw.date) va kiritilgan vaqti, usul, holat, tushum, oy, to''lovchi',
  zz.cells('payments', 'P2', array['Sana (kassa kuni)', 'Kiritilgan vaqt', 'O''quvchi ID', 'F.I.Sh.', 'Sinf', 'Summa', 'Usul', 'Holati', 'Tushumga kiradimi',
    'Hisob-faktura oyi', 'To''lovchi', 'Fiskal chek']),
  '^2026-10-30\|2026-11-03 09:00\|IQ-9001\|Sinov Bir\|5-A\|400\|Naqd\|Qabul qilingan\|Ha\|2026-11\|Sinov Otasi\|null$');
select zz.chk('D14 To''lovlar — tushum ta''rifi: tasdiqlanmagan, avans ko''chirish, bo''lingan qism, NaN summa — kirmaydi; biriktirilmagan — kiradi',
  zz.cells('payments', 'P3', array['Usul', 'Holati', 'Tushumga kiradimi']) || ' / ' || zz.cells('payments', 'P6', array['Usul', 'Tushumga kiradimi']) || ' / ' ||
  zz.cell('payments', 'P7:s:1', 'Tushumga kiradimi') || ' / ' || zz.cells('payments', 'P8', array['Summa', 'Tushumga kiradimi']) || ' / ' ||
  zz.cells('payments', 'P5', array['O''quvchi ID', 'F.I.Sh.', 'Holati', 'Tushumga kiradimi', 'To''lovchi']),
  '^Uzum\|Kutilmoqda\|Yo''q / Avans ko''chirish\|Yo''q / Yo''q / null\|Yo''q / null\|null\|Biriktirilmagan\|Ha\|Sinov To''lovchi \[kod\]$');
select zz.chk('D15 To''lovlar — arxivdagi (studentId''siz) o''quvchi kaliti bo''yicha ism va sinf', zz.cells('payments', 'P4', array['F.I.Sh.', 'Sinf', 'Usul']),
  '^Sinov Uch\|7-A\|Payme$');
select zz.chk('D16 To''lovlar — tartib (kiritilgan vaqt), o''quvchi tanlovi, boshlang''ich oy (kassa kuni bo''yicha)',
  zz.keys('payments') || ' / ' || zz.keys('pay_k') || ' / ' || zz.keys('pay_f'),
  '^P1,P4,P2,P3,P5,P6,P7:s:1,P8 / P3,P8 / P3,P5,P6,P7:s:1,P8$');

select zz.chk('D17 Qarzdorlik — sarlavha', zz.hdr('debts', $j$["O'quvchi ID", "F.I.Sh.", "Sinf", "Holati", "Qarzli oylar", "Oylar soni", "Jami qarz",
  "Eng eski qarz oyi", "Avans (ortiqcha to'lov)", "Otasining telefoni", "Onasining telefoni"]$j$), '^ok$');
select zz.chk('D18 Qarzdorlik — qarzi bor o''quvchilar, katta qarzdan; ortiqcha to''lagan va kelajak oy hisobga olinmaydi', zz.keys('debts'), '^IQ-9002,IQ-ESKI,IQ-9001,SH-3$');
select zz.chk('D19 Qarzdorlik — qiymatlar (bekor / qaytarilgan faktura qarz emas; kartasiz o''quvchi — faktura ismi va sinfi; arxivdagi qarz)',
  zz.cells('debts', 'IQ-9002', array['F.I.Sh.', 'Sinf', 'Holati', 'Qarzli oylar', 'Oylar soni', 'Jami qarz', 'Eng eski qarz oyi', 'Avans (ortiqcha to''lov)',
    'Otasining telefoni']) || ' / ' ||
  zz.cells('debts', 'IQ-ESKI', array['F.I.Sh.', 'Sinf', 'Holati', 'Qarzli oylar', 'Jami qarz']) || ' / ' ||
  zz.cells('debts', 'IQ-9001', array['Qarzli oylar', 'Jami qarz', 'Otasining telefoni', 'Onasining telefoni']) || ' / ' ||
  zz.cells('debts', 'SH-3', array['Holati', 'Sinf', 'Qarzli oylar', 'Jami qarz']),
  '^Sinov Ikki\|5-B\|Muzlatilgan\|2026-11\|1\|1000\|2026-11\|150\|\+998 00 777 88 99 / Sinov Eski Karta\|4-B\|Kartasi yo''q\|2026-09\|700 / 2026-11\|600\|\+998 00 111 22 33\|\+998 00 444 55 66 / Chiqqan \(arxiv\)\|7-A\|2026-10\|500$');

select zz.chk('D20 Oylik hisobot — sarlavha (kassa ustuni faqat Kassa moduli bazada bo''lsa; tushum ustunlari — shu davrda bo''lgan usullar)',
  (select case when jsonb_agg(h.v order by h.o) filter (where h.v <> '"Boshqa kirim (kassa)"') = $j$["Oy", "O'quvchilar (hisob-faktura)", "Hisoblangan",
      "Chegirma", "To'langan (shu oy uchun)", "Qarz", "Yig'im foizi, %", "Jami kirim", "Xarajat", "Foyda (kirim − xarajat)", "Qaytarilgan (hisob-fakturadan)",
      "Qaytarilgan (avansdan)", "Kassaga tushgan (jami)", "Tushum: Naqd", "Tushum: Click", "Tushum: Payme"]$j$::jsonb
      and (count(*) filter (where h.v = '"Boshqa kirim (kassa)"') = 1) = (to_regclass('public.cash_docs') is not null)
    then 'ok' else (t.j -> 'header')::text end
     from zz.tabs t, jsonb_array_elements(t.j -> 'header') with ordinality h(v, o) where t.name = 'monthly' group by t.j), '^ok$');
select zz.chk('D21 Oylik hisobot — 2026-10: hisoblangan (bekorsiz), chegirma, to''langan, qarz, yig''im foizi, kirim, xarajat (oy — sanadan), foyda, qaytarilgan, kassaga tushgan usullar bo''yicha (qo''lda to''lov kassa kuni bilan)',
  zz.cells('monthly', '2026-10', array['O''quvchilar (hisob-faktura)', 'Hisoblangan', 'Chegirma', 'To''langan (shu oy uchun)', 'Qarz', 'Yig''im foizi, %',
    'Jami kirim', 'Xarajat', 'Foyda (kirim − xarajat)', 'Qaytarilgan (hisob-fakturadan)', 'Qaytarilgan (avansdan)', 'Kassaga tushgan (jami)',
    'Tushum: Naqd', 'Tushum: Click', 'Tushum: Payme']),
  '^2\|1800\|200\|1300\|500\|72\|1300\|300\|1000\|50\|0\|1700\|400\|1000\|300$');
select zz.chk('D22 Oylik hisobot — 2026-11: qaytarish oyi yaratilgan kundan; kassaga faqat biriktirilmagan to''lov (qolganlari tushum emas)',
  zz.cells('monthly', '2026-11', array['O''quvchilar (hisob-faktura)', 'Hisoblangan', 'Chegirma', 'To''langan (shu oy uchun)', 'Qarz', 'Yig''im foizi, %',
    'Jami kirim', 'Xarajat', 'Foyda (kirim − xarajat)', 'Qaytarilgan (hisob-fakturadan)', 'Qaytarilgan (avansdan)', 'Kassaga tushgan (jami)',
    'Tushum: Naqd', 'Tushum: Click', 'Tushum: Payme']),
  '^2\|2000\|0\|400\|1600\|20\|400\|100\|300\|0\|30\|250\|0\|250\|0$');
select zz.chk('D23 Oylik hisobot — oylar ro''yxati, yig''im foizi (2026-09 — qaytarilgan faktura hisoblanmaydi; ortiqcha to''langan oy — 100; to''lanmagan kelajak oy — 0), boshlang''ich oy',
  zz.keys('monthly') || ' / ' || zz.cells('monthly', '2026-09', array['O''quvchilar (hisob-faktura)', 'Hisoblangan', 'Yig''im foizi, %']) || ' / ' ||
  zz.cell('monthly', '2026-05', 'Yig''im foizi, %') || ' / ' || zz.cell('monthly', '2026-12', 'Yig''im foizi, %') || ' / ' || zz.keys('mon_f'),
  '^2026-05,2026-09,2026-10,2026-11,2026-12 / 2\|1700\|59 / 100 / 0 / 2026-10,2026-11,2026-12$');

select zz.chk('D24 Xarajatlar — sarlavha, oy (bo''sh bo''lsa sanadan), toifasiz — «Boshqa», tartib',
  zz.hdr('expenses', $j$["Sana", "Oy", "Toifa", "Summa", "To'lov usuli", "Izoh", "Kassa hujjati"]$j$) || ' / ' ||
  zz.cells('expenses', '2026-10-15', array['Oy', 'Toifa', 'Summa', 'Izoh']) || ' / ' || zz.cells('expenses', '2026-11-02', array['Oy', 'Toifa', 'Summa']) || ' / ' ||
  zz.keys('expenses'), '^ok / 2026-10\|Ijara\|300\|Sinov ijara / 2026-11\|Boshqa\|100 / 2026-10-15,2026-11-02$');
select zz.chk('D25 Qaytarishlar — sarlavha, oy (bo''sh bo''lsa yaratilgan kundan), qayerdan, o''quvchi ismi va sinfi',
  zz.hdr('refunds', $j$["Sana", "Oy", "O'quvchi ID", "F.I.Sh.", "Sinf", "Summa", "Qayerdan", "Usul", "Sabab", "Kassa hujjati"]$j$) || ' / ' ||
  zz.cells('refunds', '2026-10-25', array['Oy', 'O''quvchi ID', 'F.I.Sh.', 'Sinf', 'Summa', 'Qayerdan', 'Sabab']) || ' / ' ||
  zz.cells('refunds', '2026-11-05', array['Oy', 'F.I.Sh.', 'Qayerdan']),
  '^ok / 2026-10\|IQ-9001\|Sinov Bir\|5-A\|50\|Hisob-fakturadan\|Sinov qaytarish / 2026-11\|Sinov Ikki\|Avansdan \(ortiqcha to''lovdan\)$');
select zz.chk('D26 noto''g''ri boshlang''ich oy — 22023; noma''lum varaq — null',
  zz.as('service', $q$select public.sheets_tab('invoices', p_from => '2026-13')::text$q$) || ' / ' || zz.as('service', $q$select public.sheets_tab('kassa')::text$q$),
  '^ERR 22023 .* / <null>$');
select zz.chk('D27 pul ustunlari (jadvalda «1 500 000» formatida) — faqat summalar',
  zz.money('students') || ' / ' || zz.money('invoices') || ' / ' || zz.money('payments') || ' / ' || zz.money('debts') || ' / ' || zz.money('expenses') || ' / ' ||
  zz.money('refunds') || ' / ' || zz.money('monthly'),
  '^Shartnoma summasi,Joriy qarz,Avans \(ortiqcha to''lov\) / Asl summa,Chegirma,Hisoblangan,To''langan,Qarz / Summa / Jami qarz,Avans \(ortiqcha to''lov\) / Summa / Summa / Hisoblangan,Chegirma,To''langan \(shu oy uchun\),Qarz,(Boshqa kirim \(kassa\),)?Jami kirim,Xarajat,Foyda \(kirim − xarajat\),Qaytarilgan \(hisob-fakturadan\),Qaytarilgan \(avansdan\),Kassaga tushgan \(jami\),Tushum: Naqd,Tushum: Click,Tushum: Payme$');

-- ===== (K) navbat triggerlari ro'yxati; Kassa moduli bo'lsa (--dev zanjir) — oylik hisobotdagi «boshqa kirim» =====
select case when to_regclass('public.cash_docs') is not null then 'true' else 'false' end as has_kassa \gset
\if :has_kassa
\set kutilgan 57
select zz.chk('K01 navbat triggeri — barcha kuzatiladigan jadvallarda, Kassa moduli jadvallarida ham (cash_docs, cash_doc_lines)',
  (select string_agg(distinct c.relname, ',' order by c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where t.tgname in ('trg_sheets_mark', 'trg_sheets_mark_u')),
  '^cash_doc_lines,cash_docs,expenses,invoices,payments,refunds,student_credit,student_private,students$');
set local session_replication_role = replica;
insert into public.cash_days (id, desk, day, status, opening) values
  ('cd_main_2027-01-05', 'main', '2027-01-05', 'open', 0), ('cd_sinov_2027-01-05', 'sinov', '2027-01-05', 'open', 0);
insert into public.cash_docs (id, desk, form, op, status, year, no, "businessDay", "dayId", amount, "clientRef", "postedAt") values
  ('k1', 'main',  'KO1', 'in_sale',     'posted', 2027, 1, '2027-01-05', 'cd_main_2027-01-05',  250, 'ref_k1', '2027-01-05 10:00+05'),
  ('k2', 'main',  'KO1', 'in_other',    'posted', 2027, 2, '2027-01-06', 'cd_main_2027-01-05',   30, 'ref_k2', '2027-01-06 10:00+05'),
  ('k3', 'main',  'KO1', 'in_other',    'posted', 2027, 3, '2027-01-06', 'cd_main_2027-01-05',   10, 'ref_k3', '2027-01-06 11:00+05'),
  ('k4', 'main',  'KO1', 'in_tuition',  'posted', 2027, 4, '2027-01-06', 'cd_main_2027-01-05',   20, 'ref_k4', '2027-01-06 12:00+05'),
  ('k5', 'main',  'KO1', 'in_sale',     'void',   2027, 5, '2027-01-07', 'cd_main_2027-01-05',   50, 'ref_k5', '2027-01-07 10:00+05'),
  ('k6', 'sinov', 'KO1', 'in_sale',     'posted', 2027, 1, '2027-01-05', 'cd_sinov_2027-01-05',  70, 'ref_k6', '2027-01-05 10:00+05'),
  ('k7', 'main',  'KO1', 'in_surplus',  'posted', 2027, 6, '2027-01-07', 'cd_main_2027-01-05',    5, 'ref_k7', '2027-01-07 19:00+05'),
  ('k8', 'main',  'KO1', 'in_sale',     'posted', 2027, 7, '2027-02-01', 'cd_main_2027-01-05',   40, 'ref_k8', '2027-02-01 10:00+05'),
  ('k9', 'main',  'KO2', 'out_expense', 'posted', 2027, 1, '2027-01-05', 'cd_main_2027-01-05',  200, 'ref_k9', '2027-01-05 09:00+05');
insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash) values
  ('k1_1', 'k1', 1, '5010', '9020', 250, 'IN-04', true),   -- forma sotuvi — daromad
  ('k2_1', 'k2', 1, '5010', '9390',  30, 'IN-06', true),   -- boshqa kirim — daromad
  ('k3_1', 'k3', 1, '5010', '6390',  10, 'OP-16', true),   -- aniqlanmagan tushum — daromad emas
  ('k4_1', 'k4', 1, '5010', '4010',  20, 'IN-01', true),   -- o'quv to'lovi — «To'langan» ustunida allaqachon bor
  ('k5_1', 'k5', 1, '5010', '9020',  50, 'IN-04', true),   -- bekor qilingan hujjat
  ('k6_1', 'k6', 1, '5010', '9020',  70, 'IN-04', true),   -- sinov kassasi
  ('k7_1', 'k7', 1, '5010', '9390',   5, 'IN-06', true),   -- kassa ortiqchasi
  ('k8_1', 'k8', 1, '5010', '9020',  40, 'IN-04', true),
  ('k9_1', 'k9', 1, '2910', '5010', 200, 'OP-24', true);   -- chiqim (KO-2)
set local session_replication_role = origin;
select zz.take('mon_k', $q$select public.sheets_tab('monthly', p_from => '2027-01')::text$q$);
select zz.chk('K02 oylik hisobot — boshqa kirim: forma va boshqa kirim (o''quv to''lovi, aniqlanmagan tushum, bekor qilingan, sinov kassasi, ortiqcha, chiqim — kirmaydi); jami kirim va foydaga qo''shiladi',
  zz.keys('mon_k') || ' / ' || zz.cells('mon_k', '2027-01', array['Boshqa kirim (kassa)', 'To''langan (shu oy uchun)', 'Jami kirim', 'Foyda (kirim − xarajat)']) || ' / ' ||
  zz.cell('mon_k', '2027-02', 'Boshqa kirim (kassa)'),
  '^2027-01,2027-02 / 280\|0\|280\|280 / 40$');
select zz.chk('K03 boshqa kirim — Buxgalteriya hisobotidagi finance_other_income bilan bir xil (Direktor nomidan)',
  zz.as('U_DIR', $q$select string_agg(k || ':' || (v->>'sum'), ',' order by k) from jsonb_each(public.finance_other_income()->'months') e(k, v)$q$),
  '^2027-01:280,2027-02:40$');
\else
\set kutilgan 55
select zz.chk('K00 navbat triggeri — barcha kuzatiladigan jadvallarda (jonli zanjirda Kassa moduli jadvallari yo''q)',
  (select string_agg(distinct c.relname, ',' order by c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where t.tgname in ('trg_sheets_mark', 'trg_sheets_mark_u')),
  '^expenses,invoices,payments,refunds,student_credit,student_private,students$');
\endif

-- ===== (B) o'zgarishlar navbati =====
select zz.chk('B01 xizmat hali ishlamagan (yurak urishi yo''q) — yuqoridagi barcha yozuvlar navbatga tushmadi', (select count(*)::text from app.sheets_outbox), '^0$');
select zz.chk('B02 xizmat yurak urishi — ijara olindi', zz.as('service', $q$select public.sheets_beat('svc-A', '{"lastOk": null}')::text$q$), '^\{"ok": true\}$');
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('SH-7', 'IQ-9007', 'Sinov Yetti', 8, 'A', 'uz');
select zz.chk('B03 yangi o''quvchi — o''quvchi kaliti bilan', zz.outbox(), '^students:IQ-9007$');
delete from app.sheets_outbox;
update public.students set attendance = 50, score = 70 where id = 'SH-1';
update public.student_private set pinfl = '88888888888888', health = 'SINOV-2' where id = 'SH-1';
select zz.chk('B04 varaqda ko''rinmaydigan ustunlar (davomat, ball, JSHSHIR, salomatlik) — navbatga tushmaydi', zz.outbox(), '^$');
update public.students set name = 'Sinov Bir Yangi' where id = 'SH-1';
update public.student_private set "parentPhone" = '+998 00 111 22 34' where id = 'SH-1';
select zz.chk('B05 ism / ota-ona telefoni o''zgardi — o''quvchi kaliti / karta id', zz.outbox(), '^students:IQ-9001,student_private:SH-1$');
delete from app.sheets_outbox;
update public.students set "studentId" = 'IQ-9106' where id = 'SH-6';
select zz.chk('B06 o''quvchi kaliti almashdi — yangi va eski kalit (ikkala o''quvchining qatorlari yangilanadi)', zz.outbox(), '^students:IQ-9106,students:IQ-9006$');
delete from app.sheets_outbox;
update public.invoices set "paidAmount" = 100 where id = 'inv3';
delete from public.payments where id = 'P6';
insert into public.expenses (id, date, month, category, amount) values ('E3', '2026-11-14', '2026-11', 'Kanselyariya', 20);
update public.refunds set reason = 'Sinov sabab' where id = 'R2';
update public.student_credit set credit = 160 where id = 'IQ-9002';
select zz.chk('B07 hisob-faktura, to''lov (o''chirish ham), xarajat, qaytarish, avans — har biri o''z kaliti bilan', zz.outbox(),
  '^invoices:inv3,payments:P6,expenses:E3,refunds:R2,student_credit:IQ-9002$');
delete from app.sheets_outbox;
savepoint b08;
update public.students set name = 'Sinov Bekor' where id = 'SH-2';
rollback to savepoint b08;
select zz.chk('B08 bekor qilingan o''zgarish navbatda qolmaydi', zz.outbox(), '^$');
update app.sheets_state set beat = now() - interval '16 minutes' where id = 1;
update public.students set name = 'Sinov Ikki Yangi' where id = 'SH-2';
select zz.chk('B09 xizmat 15 daqiqadan beri jim — navbat o''smaydi', zz.outbox(), '^$');
update app.sheets_state set beat = now() where id = 1;
delete from public.students where id = 'SH-7';
select zz.chk('B10 o''quvchi o''chirildi — o''quvchi kaliti', zz.outbox(), '^students:IQ-9007$');

-- ===== (C) ijara, navbatni o'qish / o'chirish, to'liq yozish =====
select zz.chk('C01 ikkinchi nusxa ijarani ololmaydi (birinchisi tirik)', zz.as('service', $q$select public.sheets_beat('svc-B')::text$q$),
  '^\{"ok": false, "ageSec": [0-9]+, "holder": "svc-A"\}$');
select zz.chk('C02 ijarasiz nusxa navbatni o''qiy / o''chira / to''liq yozishni boshlay olmaydi',
  zz.as('service', $q$select public.sheets_pull('svc-B')::text$q$) || ' ' || zz.as('service', $q$select public.sheets_ack('svc-B', '{1}')::text$q$) || ' ' ||
  zz.as('service', $q$select public.sheets_full_begin('svc-B')::text$q$) || ' ' || zz.as('service', $q$select public.sheets_full_end('svc-B')::text$q$),
  '^ERR 55P03 .* ERR 55P03 .* ERR 55P03 .* ERR 55P03 ');
delete from app.sheets_outbox;
insert into app.sheets_outbox (src, key) values ('invoices', 'inv1'), ('payments', 'P1'), ('students', 'IQ-9001');
select zz.chk('C03 navbatdan o''qish — id tartibida, src va key bilan; chegara (p_limit)',
  zz.as('service', $q$select string_agg(e ->> 'src' || ':' || (e ->> 'key'), ',' order by (e ->> 'id')::bigint) from jsonb_array_elements(public.sheets_pull('svc-A', 2)) e$q$),
  '^invoices:inv1,payments:P1$');
select zz.chk('C04 o''chirish — aynan berilgan id''lar (qolgani navbatda)',
  zz.as('service', format($q$select public.sheets_ack('svc-A', array[%s, %s])::text$q$, (select min(id) from app.sheets_outbox), (select min(id) + 1 from app.sheets_outbox))) || ' ' || zz.outbox(),
  '^2 students:IQ-9001$');
select zz.chk('C05 ijarani bo''shatish — ikkinchi nusxa darhol oladi, birinchisi endi o''qiy olmaydi',
  zz.as('service', $q$select public.sheets_release('svc-A')::text$q$) || ' ' || zz.as('service', $q$select public.sheets_beat('svc-B')::text$q$) || ' ' ||
  zz.as('service', $q$select public.sheets_pull('svc-A')::text$q$),
  '^true \{"ok": true\} ERR 55P03 ');
update app.sheets_state set beat = now() - interval '4 minutes' where id = 1;
select zz.chk('C06 ijara 3 daqiqadan ko''p yangilanmagan — boshqa nusxa oladi', zz.as('service', $q$select public.sheets_beat('svc-A')::text$q$), '^\{"ok": true\}$');
delete from app.sheets_outbox;
insert into app.sheets_outbox (src, key) values ('invoices', 'inv1'), ('payments', 'P1');
select zz.chk('C07 to''liq yozish boshi — ko''rinib turgan yozuvlar belgilanadi', zz.as('service', $q$select public.sheets_full_begin('svc-A')::text$q$), '^2$');
insert into app.sheets_outbox (src, key) values ('refunds', 'R1');
select zz.chk('C08 to''liq yozish oxiri — faqat belgilanganlar o''chadi, keyin kelgani navbatda qoladi',
  zz.as('service', $q$select public.sheets_full_end('svc-A')::text$q$) || ' ' || zz.outbox(), '^2 refunds:R1$');
insert into app.sheets_outbox (src, key, at) values ('expenses', 'E1', now() - interval '8 days');
select zz.as('service', $q$select public.sheets_beat('svc-A', '{"lastError": "sinov"}')::text$q$) as c09 \gset
select zz.chk('C09 yurak urishi 7 kundan eski yozuvlarni tozalaydi (bunday uzilishdan keyin xizmat baribir to''liq yozadi) va holatni yozadi',
  :'c09' || ' ' || zz.outbox() || ' ' || (select info ->> 'lastError' from app.sheets_state where id = 1), '^\{"ok": true\} refunds:R1 sinov$');
select zz.chk('C10 p_instance bo''sh — rad etiladi', zz.as('service', $q$select public.sheets_beat('')::text$q$) || ' ' || zz.as('service', $q$select public.sheets_pull(null)::text$q$),
  '^ERR 22023 .* ERR 55P03 ');

-- ===== yakun =====
select count(*)::text as yozilgan from zz.res \gset
select zz.chk('ZZ yozilgan tekshiruvlar soni = kutilgan', :'yozilgan', '^' || :'kutilgan' || '$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || coalesce(got, '<null>') || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL (jami ' || count(*) || ')' from zz.res;
rollback;
