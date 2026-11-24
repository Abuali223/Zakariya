-- =====================================================================
-- test-sales-role.sql — «Sotuvchi» (sales) roli sinovi (migration/sales-role.sql; egasi 2026-11-19, SESSIYA-ISHLARI.md §85):
--   (A) ruxsat: sales_contacts / sales_reveal — faol sotuvchi va Direktor; sales_log — faqat Direktor; qolganlar (o'qituvchi, qabulxona,
--       marketing menejeri, kassir, moliya, buxgalter, HR, O'IBDO', hamshira, ma'muriyat, ota-ona, o'quvchi, rolsiz, kutilayotgan va
--       bloklangan sotuvchi, anonim) — 42501;
--   (B) ro'yxat: faqat FAOL o'quvchilar oilalari (arxiv — «chiqdi» + chiqqan kuni bugun / o'tgan / sanasiz; o'chirilgan o'quvchi — yo'q;
--       kelajak sanali chiqish va muzlatilgan — bor), aka-uka bitta oila (telefonlar juftligi, turli yozuv shakli), arxivdagi aka-uka
--       kartasidagi ism ishlatilmaydi, eski (studentId kalitli) karta, niqob «+998 00 *** ** 01», javob kalitlari — faqat ruxsat etilganlar,
--       o'quvchi ma'lumoti (ism, ID, sinf, manzil …) yo'q, oila kaliti — telefon / ID'dan chiqarib bo'lmaydi (maxfiy tuzga bog'liq),
--       qidiruv — faqat ota-ona ismi (katta-kichik harf va apostrofsiz), sahifalash;
--   (R) ochish: to'liq raqam, jurnal yozuvi, shu oila shu kuni — chegarani qayta yemaydi, noma'lum / arxivdagi kalit — not_found, kunlik
--       chegara (150) — daily_cap, chegara har foydalanuvchiga alohida, ertasi kuni — yangidan;
--   (L) Direktor jurnali (telefonsiz); (X) qo'shimcha lavozim yo'q; (W) yozish yo'q (asosiy jadvallar, o'z roli, jurnal, tuz);
--   (G) SIZISH INVARIANTI: authenticated o'qiy oladigan HAR BIR public / storage jadval va ko'rinishda sotuvchi ko'radigan qatorlar soni
--       farzandsiz faol ota-ona ko'radiganidan oshmaydi (barcha jadvallar urug' bilan to'ldiriladi — bo'sh jadval qolmaydi); har bir mijoz
--       RPC'si (NULL argumentlar bilan) sotuvchiga ota-onadan boshqacha javob beradiganlari — faqat sales_contacts, sales_reveal;
--       'sales' so'zi uchraydigan funksiya / siyosat / ko'rinish — yopiq ro'yxat;
--   (H) kuchaytirish (mustaqil tekshiruv): sotuvchi / buxgalter hisobiga farzand biriktirilmaydi (claim_child, Direktor tasdig'i, xizmat
--       yozuvi), rol «Sotuvchi»ga o'zgarganda bog'lanishlar bekor qilinadi, blokdan chiqarish ish hisobining bog'lanishini qaytarmaydi
--       (xato bilan to'xtamaydi), o'qituvchiga baho yo'q, xabarnoma muharriri emas, student_phones — security_barrier, oila grafi
--       (almashib yozilgan / to'liq bo'lmagan aka-uka kartalari — bitta oila, ikkala raqam; umumiy «to'ldiruvchi» yoki noto'g'ri raqam va
--       bir ota — ikki ona — birlashmaydi), noto'g'ri / xorij raqami, kirill qidiruvi; (H18–H24, 3-mustaqil tekshiruv) oila raqamini
--       tanlash darajalari (ismli kartadagi «0» to'g'ri raqamni yashirmaydi, raqamlari almashgan oilada ikkalasi ham chiqadi, ona raqami
--       otaniki bo'lib takrorlanmaydi, ikki raqamli ismli katak ustun), bo'lingan komponentda takror qator yo'q, katakdagi izoh matni
--       chiqmaydi, jurnalda ochishi bor hisob (rol o'zgargach ham) ismini o'zi o'zgartirmaydi.
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub) — RLS va GRANT haqiqiy. Sana — sinov soati (app.fin_clock; faqat fx_* / sinov /
--   test nomli bazada): bugun 2026-11-19, R-bandida ertasi kun. Sinov qoidalari: (a) yozuv / RPC o'z so'rovida (\gset bilan), natija
--   KEYINGI so'rovda o'qiladi; (b) NULL natija — FAIL (hisobdan tushib qolmaydi); (c) savepoint ichidagi qiymat \gset bilan olinadi,
--   savepoint qaytarilgach tekshiriladi; (d) oxirida yozilgan tekshiruvlar soni kutilgan son bilan solishtiriladi (yo'qolgan tekshiruv — FAIL).
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin (dev va jonli zanjir), migration/ papkasidan:
--     bash migration/chain.sh --no-lock-timeout | psql -d fx_sinov -q && (cd migration && psql -d fx_sinov -X -f test-sales-role.sql)
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ism / telefonlar to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- yozilishi kerak bo'lgan tekshiruvlar soni (ZZ dan tashqari): yangi tekshiruv qo'shilsa — oshiriladi
\set kutilgan 120
do $g0$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-sales-role.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g0$;
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.users) then
    raise exception 'test-sales-role.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
-- INSERT sinovi: triggerlarsiz (session_replication_role = replica) — qatorni faqat RLS / GRANT qabul qiladi yoki rad etadi.
create or replace function zz.ins(p_uid text, p_q text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('session_replication_role', 'replica', true);
  r := zz.as(p_uid, p_q);
  perform set_config('session_replication_role', 'origin', true);
  return r;
end $$;
-- Baza egasi (migratsiya kabi, JWT'siz): xato — matn bo'lib qaytadi.
create or replace function zz.try(p_q text) returns text language plpgsql as $$
begin execute p_q; return 'OK'; exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm; end $$;
-- Baza egasi nomidan so'rov natijasi (matn); xato — 'ERR …' (yangi obyekt yo'q bo'lsa ham sinov to'xtamaydi — FAIL bo'ladi).
create or replace function zz.q(p_q text) returns text language plpgsql as $$
declare r text;
begin begin execute p_q into r; exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm; end; return r; end $$;
-- Matn -> jsonb (xato matni bo'lsa — NULL: tekshiruv FAIL bo'ladi, sinov to'xtamaydi).
create or replace function zz.j(p text) returns jsonb language plpgsql immutable as $$
begin return p::jsonb; exception when others then return null; end $$;
create or replace function zz.keys(p jsonb) returns text language sql immutable as $$
  select case when jsonb_typeof(p) = 'object' then (select string_agg(k, ',' order by k) from jsonb_object_keys(p) k) end $$;
create or replace function zz.cnt(p_uid text, p_rel text) returns text language sql as $$
  select zz.as(p_uid, format('select count(*)::text from %s', p_rel)) $$;
-- sotuvchi nomidan ro'yxat (jsonb) va oila kaliti (ota yoki ona ismi bo'yicha)
create or replace function zz.list(p_uid text, p_args text default '') returns jsonb language sql as $$
  select zz.j(zz.as(p_uid, format('select public.sales_contacts(%s)::text', p_args))) $$;
create or replace function zz.key(p_name text) returns text language sql as $$
  select r ->> 'k' from jsonb_array_elements(coalesce(zz.list('U_SAL') -> 'rows', '[]'::jsonb)) r
   where r -> 'father' ->> 'name' = p_name or r -> 'mother' ->> 'name' = p_name limit 1 $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
-- NULL natija — FAIL (got '<NULL>', ok false): hech bir tekshiruv hisobdan jim tushib qolmaydi.
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, coalesce(p_got, '<NULL>'), p_pat, coalesce(p_got ~ p_pat, false)); end $$;

-- ---------- Urug' (triggerlarsiz; ismlar va telefonlar to'qima, «+99800…») ----------
set local session_replication_role = replica;
insert into app.fin_clock (id, t) values (1, '2026-11-19 10:00+05') on conflict (id) do update set t = excluded.t;
insert into public.users (id, email, name, role, status, verified, "extraRoles", "blockedRole", "homeroomClasses", "assignedClasses") values
  ('U_DIR','d@example.org','Sinov Direktor','director','active',true,'[]',null,'[]','[]'),
  ('U_SAL','s@example.org','Sinov Sotuvchi','sales','active',true,'[]',null,'[]','[]'),
  ('U_SAL2','s2@example.org','Sinov Sotuvchi Ikki','sales','active',true,'[]',null,'[]','[]'),
  -- eski qator: qo'shimcha lavozimlar va sinf biriktiruvi qolib ketgan sotuvchi (huquq bermasligi kerak)
  ('U_SALX','sx@example.org','Sinov Sotuvchi Eski','sales','active',true,'["reception","kassir","zavuch","teacher"]',null,'["uz-5-A"]','["uz-5-A"]'),
  ('U_SALP','sp@example.org','Sinov Sotuvchi Kutilmoqda','sales','pending',false,'[]',null,'[]','[]'),
  ('U_SALB','sb@example.org','Sinov Sotuvchi Bloklangan',null,'blocked',true,'[]','sales','[]','[]'),
  ('U_TCH','t@example.org','Sinov Oqituvchi','teacher','active',true,'[]',null,'["uz-5-A"]','["uz-5-A"]'),
  ('U_TX','tx@example.org','Sinov Oqituvchi Qabul','teacher','active',true,'["reception"]',null,'[]','[]'),
  ('U_REC','r@example.org','Sinov Qabulxona','reception','active',true,'[]',null,'[]','[]'),
  ('U_MKT','m@example.org','Sinov Marketing','marketing_mgr','active',true,'[]',null,'[]','[]'),
  ('U_KAS','k@example.org','Sinov Kassir','kassir','active',true,'[]',null,'[]','[]'),
  ('U_FM','f@example.org','Sinov Moliyachi','finance_mgr','active',true,'[]',null,'[]','[]'),
  ('U_ACC','a@example.org','Sinov Buxgalter','accountant','active',true,'[]',null,'[]','[]'),
  ('U_HR','h@example.org','Sinov Kadrlar','hr','active',true,'[]',null,'[]','[]'),
  ('U_ZAV','z@example.org','Sinov Oibdo','zavuch','active',true,'[]',null,'[]','[]'),
  ('U_NUR','n@example.org','Sinov Hamshira','nurse','active',true,'[]',null,'[]','[]'),
  ('U_ADM','ad@example.org','Sinov Mamuriyat','admin','active',true,'[]',null,'[]','[]'),
  ('U_PAR','p@example.org','Sinov Ota Farzandli','parent','active',true,'[]',null,'[]','[]'),
  ('U_PAR0','p0@example.org','Sinov Ota Farzandsiz','parent','active',true,'[]',null,'[]','[]'),
  ('U_STU','st@example.org','Sinov Oquvchi Hisobi','student','active',true,'[]',null,'[]','[]'),
  ('U_NONE','no@example.org','Sinov Rolsiz',null,'active',false,'[]',null,'[]','[]'),
  -- (H) bandi: farzand bog'lanishi bor hisoblar
  ('U_SALC','sc@example.org','Sinov Sotuvchi Kutilgan Bog','sales','active',true,'[]',null,'[]','[]'),
  ('U_PAR2','p2@example.org','Sinov Ota Sotuvchiga','parent','active',true,'[]',null,'[]','[]'),
  ('U_PAR3','p3@example.org','Sinov Ota Bloklanadi','parent','active',true,'[]',null,'[]','[]'),
  ('U_ACCB','ab@example.org','Sinov Buxgalter Farzandli','accountant','active',true,'[]',null,'[]','[]');
insert into public.users (id, email, name, role, status, verified, "extraRoles", "blockedRole", "blockedAt", "homeroomClasses", "assignedClasses") values
  ('U_SALB2','sb2@example.org','Sinov Sotuvchi Bloklangan Ikki',null,'blocked',true,'[]','sales','2026-11-01 10:00+05','[]','[]');
-- O'quvchilar (bugun = 2026-11-19): o'quvchi ismlari «Bola», ID'lar «IQ-S…» — sotuvchi javoblarida uchramasligi kerak.
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "exitAt", "stopFrom", "exitReason", "order") values
  ('s1','IQ-S01','Sinov Bola Bir',5,'A','uz','',null,null,null,1),
  ('s2','IQ-S02','Sinov Bola Ikki',7,'B','uz','faol',null,null,null,2),
  ('s3','IQ-S03','Sinov Bola Uch',3,'A','uz','chiqdi','2026-11-09',null,'boshqa',3),          -- arxiv (o'tgan oy)
  ('s4','IQ-S04','Sinov Bola Tort',4,'A','uz','chiqdi','2026-11-24',null,'boshqa',4),         -- kelajak sanali chiqish — hali faol
  ('s5','IQ-S05','Sinov Bola Besh',6,'A','uz','chiqdi',null,null,null,5),                      -- sanasiz «chiqdi» — arxiv
  ('s6','IQ-S06','Sinov Bola Olti',2,'A','uz','muzlatilgan',null,'2026-11-01',null,6),        -- muzlatilgan — faol ro'yxatda
  ('s8','IQ-S08','Sinov Bola Sakkiz',8,'A','ru','',null,null,null,8),
  ('s9','IQ-S09','Sinov Bola Toqqiz',11,'A','ru','chiqdi','2026-10-20',null,'bitirdi',9),     -- s8 ning arxivdagi akasi
  ('s10','IQ-S10','Sinov Bola On',1,'A','uz','',null,null,null,10),                            -- shaxsiy kartasi yo'q
  ('s11','IQ-S11','Sinov Bola Onbir',1,'B','uz','',null,null,null,11),                         -- kartada raqam yo'q
  ('doc12','IQ-S12','Sinov Bola Onikki',9,'A','uz','',null,null,null,12),                      -- eski karta studentId kalitli
  ('s13','IQ-S13','Sinov Bola Onuch',10,'A','uz','',null,null,null,13),
  ('s14','IQ-S14','Sinov Bola Ontort',3,'B','uz','chiqdi','yoq','2026-11-18',null,14),        -- exitAt yaroqsiz -> stopFrom (kecha) — arxiv
  ('s15','IQ-S15','Sinov Bola Onbesh',3,'B','uz','chiqdi','2026-11-19',null,null,15),         -- bugun chiqdi — arxiv
  ('s16','IQ-S16','Sinov Bola Onolti',5,'B','uz','',null,null,null,16);
insert into public.student_private (id, pinfl, "fatherName", "motherName", "parentPhone", "parentPhone2", address, health, "fatherWork", "birthDate", guardian) values
  ('s1','ZZPINFL00000001','Sinov Ota Alfa','Sinov Ona Alfa','+998 00 111 00 01','+998 00 222 00 01','ZZADDR ko''chasi 1','ZZHEALTH','ZZWORK','2015-01-01','Ota'),
  ('s2','ZZPINFL00000002','Sinov Ota Alfa','Sinov Ona Alfa','998001110001','+998002220001','ZZADDR ko''chasi 1','ZZHEALTH','ZZWORK','2013-01-01','Ota'),
  ('s3','ZZPINFL00000003','Sinov Ota Beta','Sinov Ona Beta','+998001110002','+998002220002','ZZADDR','ZZHEALTH',null,null,null),
  ('s4','ZZPINFL00000004','Sinov Ota Gamma','Sinov Ona Gamma','+998001110003','+998002220003','ZZADDR','ZZHEALTH',null,null,null),
  ('s5','ZZPINFL00000005','Sinov Ota Delta','Sinov Ona Delta','+998001110004','+998002220004','ZZADDR','ZZHEALTH',null,null,null),
  ('s6','ZZPINFL00000006','Sinov Ota Epsilon',null,'+998001110005',null,'ZZADDR','ZZHEALTH',null,null,null),
  ('s7','ZZPINFL00000007','Sinov Ota Zeta','Sinov Ona Zeta','+998001110006','+998002220006','ZZADDR','ZZHEALTH',null,null,null),  -- o'chirilgan o'quvchi kartasi qolgan
  ('s8','ZZPINFL00000008','Sinov Ota Eta','Sinov Ona Eta','+998001110007','+998002220007','ZZADDR','ZZHEALTH',null,null,null),
  ('s9','ZZPINFL00000009','ZZARXIV Ota','ZZARXIV Ona','+998001110007','+998002220007','ZZADDR','ZZHEALTH',null,null,null),
  ('s11','ZZPINFL00000011','Sinov Ota Raqamsiz','Sinov Ona Raqamsiz','','  ','ZZADDR','ZZHEALTH',null,null,null),
  ('IQ-S12','ZZPINFL00000012','Sinov Ota Teta','Sinov Ona Teta','+998001110008','+998002220008','ZZADDR','ZZHEALTH',null,null,null),
  ('s13','ZZPINFL00000013','Sinov Ota Iota','Sinov Ona Iota',null,'+998002220009','ZZADDR','ZZHEALTH',null,null,null),
  ('s14','ZZPINFL00000014','Sinov Ota Kappa','Sinov Ona Kappa','+998001110010','+998002220010','ZZADDR','ZZHEALTH',null,null,null),
  ('s15','ZZPINFL00000015','Sinov Ota Lambda',null,'+998001110011',null,'ZZADDR','ZZHEALTH',null,null,null),
  ('s16','ZZPINFL00000016','Sinov Sa''dulla Mu','Sinov Ona Mu','+998001110012','+998002220012','ZZADDR','ZZHEALTH',null,null,null);
insert into public.deleted_records (tbl, "rowId", row, "deletedBy") values
  ('students','s7','{"id":"s7","studentId":"IQ-S07","name":"Sinov Bola Yetti","grade":5,"classLetter":"A","lang":"uz"}','U_DIR');
insert into public.student_codes (id, code) values ('s1','K7Q2ZP'), ('s2','M4R8TX');
insert into public.child_claims (id, uid, "studentId", code, status) values ('U_PAR__IQ-S01','U_PAR','IQ-S01','K7Q2ZP','active');
-- (H) bandi: eski (tuzatishdan oldingi) bog'lanishlar — kutilayotgan sotuvchi bog'lanishi, rol o'zgaradigan ota-ona, bloklanadigan ota-ona va
--   buxgalter, bloklashda bekor qilingan sotuvchi bog'lanishi (updatedAt = blockedAt — user_unblock uni qaytarishga urinardi).
insert into public.child_claims (id, uid, "studentId", code, status, "updatedAt") values
  ('U_SALC__IQ-S02','U_SALC','IQ-S02','M4R8TX','pending',now()), ('U_PAR2__IQ-S02','U_PAR2','IQ-S02','M4R8TX','active',now()),
  ('U_PAR2__IQ-S08','U_PAR2','IQ-S08','X','pending',now()), ('U_PAR3__IQ-S08','U_PAR3','IQ-S08','X','active',now()),
  ('U_ACCB__IQ-S02','U_ACCB','IQ-S02','M4R8TX','active',now()), ('U_SALB2__IQ-S02','U_SALB2','IQ-S02','M4R8TX','revoked','2026-11-01 10:00+05');
insert into public.teacher_ratings (id, "teacherId", uid, "raterRole", stars) values ('U_PAR2__IQT-S01','IQT-S01','U_PAR2','parent',5);
insert into public.notify_settings (id, editors) values ('general', '["U_SAL","U_REC","U_PAR2"]') on conflict (id) do update set editors = excluded.editors;
insert into public.invoices (id, "studentId", "studentName", "classKey", month, amount, "paidAmount", status) values
  ('i1','IQ-S01','Sinov Bola Bir','uz-5-A','2026-11',2900000,0,'pending'), ('i2','IQ-S02','Sinov Bola Ikki','uz-7-B','2026-11',2900000,2900000,'paid');
insert into public.payments (id, "studentId", provider, amount, status, raw, "payerName", "payerPhone", matched, "createdAt") values
  ('p1','IQ-S02','cash',2900000,'applied','{"manual":true,"method":"cash"}','Sinov Ota Alfa','+998001110001',true,'2026-11-05 10:00+05');
insert into public.attendance (id, "studentId", "classKey", month, days) values ('IQ-S01__2026-11','IQ-S01','uz-5-A','2026-11','{"03":"present","04":"absent"}');
insert into public.grades (id, "studentId", "classKey", year, subjects) values ('IQ-S01__2026-2027','IQ-S01','uz-5-A','2026-2027','{"Matematika":{"q1":5}}');
insert into public.monitoring (id, "studentId", "classKey", subject, period, score, status) values ('IQ-S01__2026-11__mat','IQ-S01','uz-5-A','Matematika','2026-11',91,'approved');
insert into public.characteristics (id, "studentId", "classKey", year, quarter, term, text) values ('IQ-S01__2026-2027-q1','IQ-S01','uz-5-A','2026-2027','q1','2026-2027-q1','ZZCHAR tavsif');
insert into public.student_summaries (id, "studentId", "classKey", month, text) values ('IQ-S01__2026-10','IQ-S01','uz-5-A','2026-10','ZZSUM xulosa');
insert into public.subject_notes (id, "studentId", "classKey", subject, slug, year, quarter, term, text) values ('IQ-S01__mat__2026-2027-q1','IQ-S01','uz-5-A','Matematika','mat','2026-2027','q1','2026-2027-q1','ZZNOTE izoh');
insert into public.enrollments (id, name, phone, "parentName", "childName") values ('en1','Sinov Ariza','+998003330001','Sinov Arizachi','Sinov Bola Ariza');
insert into public.teachers (id, "teacherId", name, phone, "baseSalary") values ('t1','IQT-S01','Sinov Ustoz','+998004440001',5000000);
insert into public.staff (id, "staffId", name, phone, position, salary) values ('st1','IQX-S01','Sinov Xodim','+998004440002','Sotuvchi','3000000');
insert into public.salary_payments (id, "teacherId", "teacherName", month, gross, net, paid, date) values ('sp1','IQT-S01','Sinov Ustoz','2026-10',5000000,4500000,4500000,'2026-11-05');
insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date) values ('sa1','IQX-S01','Sinov Xodim',500000,'2026-11','2026-11-10');
insert into public.expenses (id, date, month, category, amount, note) values ('e1','2026-11-04','2026-11','Kanselyariya',50000,'sinov');
insert into public.discount_requests (id, "studentId", kind, status) values ('dr1','IQ-S01','none','pending');
insert into public.student_health (id, "studentId", allergies) values ('s1','IQ-S01','ZZALLERGY');
insert into public.nurse_visits (id, "studentId", complaint, action) values ('nv1','IQ-S01','ZZCOMPLAINT','rest');
insert into public.sick_notes (id, "studentId", "fromDay", "toDay", status) values ('sn1','IQ-S01','2026-11-10','2026-11-11','pending');
insert into public.sms_log (id, "studentId", phone, message) values ('sm1','IQ-S01','+998001110001','ZZSMS matn');
insert into public.feedback (id, type, uid, "authorName", text) values ('fb1','taklif','U_PAR','Sinov Ota Farzandli','ZZFEEDBACK');
insert into public.telegram_links (id, uid, kind, "tgUserId", "chatId", phone, status) values ('tg1','U_PAR','parent',1,1,'998001110001','active');
insert into public.class_announcements (id, "classKeys", title, body) values ('an1','["all"]','Sinov e''lon','ZZANN');
-- Qolgan har bir (authenticated o'qiy oladigan) bo'sh jadvalga bitta qator: NOT NULL ustunlar — turiga qarab, CHECK talab qiladigan
--   qiymatlar — pastdagi ro'yxatdan (yangi jadval paydo bo'lsa ham to'ldiriladi; to'ldirilmagani G01 da ko'rinadi).
create temp table zz_fill_fail (t text, err text) on commit drop;
do $f$
declare r record; col record; v_cols text[]; v_vals text[]; v_sql text; v_n int; v_ov jsonb;
  ovr constant jsonb := '{
    "canteen_menu": {"id": "2026-11-02"}, "cash_counts": {"kind": "close"}, "cash_day_events": {"kind": "open"},
    "cash_days": {"status": "open"}, "cash_doc_lines": {"cash": "false", "debit": "1010", "credit": "2010"},
    "cash_docs": {"form": "KO1", "status": "draft", "partyType": "other"}, "cash_handovers": {"status": "pending"},
    "cash_prints": {"kind": "doc", "mode": "original", "docId": "zz_doc"}, "discount_requests": {"kind": "none", "status": "pending"},
    "enrollment_events": {"type": "note"}, "fin_counterparties": {"kind": "other", "name": "Sinov Hamkor"},
    "invoices": {"month": "2026-11"}, "nurse_visits": {"action": "rest"}, "payroll_runs": {"id": "2026-10", "status": "draft"},
    "staff_leaves": {"startDay": "2026-11-02", "endDay": "2026-11-03", "type": "ruhsat"}, "public_names_backup": {"name": "Sinov Zaxira"}
  }'::jsonb;
begin
  for r in select c.oid, c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
             and has_table_privilege('authenticated', c.oid, 'SELECT') order by c.relname loop
    execute format('select count(*) from public.%I', r.relname) into v_n;
    continue when v_n > 0;
    v_cols := '{}'; v_vals := '{}'; v_ov := coalesce(ovr -> r.relname, '{}'::jsonb);
    for col in select a.attname, format_type(a.atttypid, a.atttypmod) as typ, a.attnotnull, (ad.adbin is not null) as hasdef, a.attidentity, a.attgenerated
                 from pg_attribute a left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
                where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped order by a.attnum loop
      continue when col.attgenerated <> '' or col.attidentity <> '';
      continue when not (v_ov ? col.attname) and (col.hasdef or not col.attnotnull) and col.attname <> 'id';
      continue when col.attname = 'id' and col.hasdef and not (v_ov ? 'id');
      v_cols := v_cols || quote_ident(col.attname);
      v_vals := v_vals || case
        when v_ov ? col.attname then quote_literal(v_ov ->> col.attname) || '::' || col.typ
        when col.typ like 'text%' or col.typ like 'character varying%' then quote_literal('zz_' || r.relname)
        when col.typ in ('integer', 'smallint', 'bigint') or col.typ like 'numeric%' or col.typ in ('double precision', 'real') then '1'
        when col.typ = 'boolean' then 'false'
        when col.typ = 'date' then quote_literal('2026-11-02')
        when col.typ like 'timestamp%' then 'now()'
        when col.typ in ('jsonb', 'json') then quote_literal('{}')
        when col.typ = 'uuid' then 'gen_random_uuid()'
        when col.typ like '%[]' then quote_literal('{}')
        else 'null' end;
    end loop;
    v_sql := case when cardinality(v_cols) = 0 then format('insert into public.%I default values', r.relname)
                  else format('insert into public.%I (%s) values (%s)', r.relname, array_to_string(v_cols, ','), array_to_string(v_vals, ',')) end;
    begin execute v_sql; exception when others then insert into zz_fill_fail values (r.relname, sqlstate || ' ' || left(sqlerrm, 120)); end;
  end loop;
end $f$;
set local session_replication_role = origin;

-- ========== (A) ruxsat ==========
select zz.chk('A01 faol sotuvchi: ro''yxat ok; ochish ok shaklida (noma''lum kalit — not_found); jurnal — faqat Direktor (42501)',
  (zz.list('U_SAL') ->> 'ok') || ' | ' || zz.as('U_SAL', $q$select public.sales_reveal(repeat('a', 32))::text$q$) || ' | '
  || zz.as('U_SAL', $q$select public.sales_log()::text$q$),
  '^true \| \{"ok": false, "reason": "not_found"\} \| ERR 42501 .*faqat Direktor');
select zz.chk('A02 Direktor: ro''yxat ok, ochish ok shaklida, jurnal ok',
  (zz.list('U_DIR') ->> 'ok') || ' | ' || zz.as('U_DIR', $q$select public.sales_reveal(repeat('b', 32))->>'reason'$q$) || ' | '
  || (zz.j(zz.as('U_DIR', $q$select public.sales_log()::text$q$)) ->> 'ok'), '^true \| not_found \| true$');
select zz.chk('A03 boshqa rollar va kutilayotgan / bloklangan sotuvchi, rolsiz hisob: uchala RPC — 42501 (ro''yxatda faqat rad etmaganlar)',
  (select coalesce(string_agg(u || ':' || f || '=' || left(r, 40), '; ' order by u, f), '') from (
     select u, f, zz.as(u, q) as r
       from unnest(array['U_TCH','U_TX','U_REC','U_MKT','U_KAS','U_FM','U_ACC','U_HR','U_ZAV','U_NUR','U_ADM','U_PAR','U_PAR0','U_STU','U_NONE','U_SALP','U_SALB']) u,
            (values ('contacts', 'select public.sales_contacts()::text'), ('reveal', $q$select public.sales_reveal(repeat('a', 32))::text$q$),
                    ('log', 'select public.sales_log()::text')) v(f, q)) x
    where r !~ '^ERR 42501 '), '^$');
select zz.chk('A04 anonim: uchala RPC — 42501 (EXECUTE yo''q)',
  zz.as(null, 'select public.sales_contacts()::text') || ' | ' || zz.as(null, $q$select public.sales_reveal('x')::text$q$) || ' | '
  || zz.as(null, 'select public.sales_log()::text'), '^ERR 42501 [^|]* \| ERR 42501 [^|]* \| ERR 42501 ');
select zz.chk('A05 tizimga kirmagan authenticated (sub yo''q) — 42501',
  (select zz.as('U_YOQ', 'select public.sales_contacts()::text')), '^ERR 42501 ');

-- ========== (B) ro'yxat ==========
select coalesce(zz.list('U_SAL')::text, '<NULL>') as b_list \gset
select zz.chk('B01 faol oilalar: 7 ta (Alfa — aka-uka bitta, Gamma — kelajak sanali chiqish, Epsilon — muzlatilgan, Eta, Teta — eski karta, Iota, Mu)',
  (zz.j(:'b_list') ->> 'total') || ' ' || jsonb_array_length(zz.j(:'b_list') -> 'rows') || ' | '
  || (select string_agg(coalesce(r -> 'father' ->> 'name', '-') || '/' || coalesce(r -> 'mother' ->> 'name', '-'), ', ' order by 1)
        from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r),
  '^7 7 \| Sinov Ota Alfa/Sinov Ona Alfa, Sinov Ota Epsilon/-, Sinov Ota Eta/Sinov Ona Eta, Sinov Ota Gamma/Sinov Ona Gamma, Sinov Ota Iota/Sinov Ona Iota, Sinov Ota Teta/Sinov Ona Teta, Sinov Sa''dulla Mu/Sinov Ona Mu$');
select zz.chk('B02 aka-uka (turli yozuv shaklidagi bir xil raqamlar) — bitta oila',
  (select count(*)::text from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r where r -> 'father' ->> 'name' = 'Sinov Ota Alfa'), '^1$');
select zz.chk('B03 arxiv (o''tgan / bugungi chiqish, sanasiz «chiqdi», yaroqsiz exitAt + o''tgan stopFrom) va o''chirilgan o''quvchi oilasi — yo''q',
  (zz.j(:'b_list') ->> 'total') || ' ' || coalesce((regexp_match(:'b_list', '(Beta|Delta|Kappa|Lambda|Zeta)'))[1], 'yoq'), '^7 yoq$');
select zz.chk('B04 arxivdagi aka-uka kartasidagi ism ishlatilmaydi (faqat faol o''quvchi kartasidan)',
  (zz.j(:'b_list') ->> 'total') || ' ' || coalesce((regexp_match(:'b_list', 'ZZARXIV'))[1], 'yoq'), '^7 yoq$');
select zz.chk('B05 niqob: hamma raqam «+998 00 *** ** NN»; Alfa — ota 01 / ona 01; javobda (oila kalitidan tashqari) 4 tadan uzun raqam ketma-ketligi yo''q',
  (select string_agg(distinct regexp_replace(p ->> 'phone', '\d{2}$', 'NN'), ',') from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r,
          lateral (select r -> 'father' as p union all select r -> 'mother') x where jsonb_typeof(p) = 'object' and p ->> 'phone' is not null)
  || ' | ' || (select (r -> 'father' ->> 'phone') || ' ' || (r -> 'mother' ->> 'phone') from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r
                where r -> 'father' ->> 'name' = 'Sinov Ota Alfa')
  || ' | ' || coalesce((regexp_match(regexp_replace(:'b_list', '"k": "[0-9a-f]{32}"', '', 'g'), '\d{5,}'))[1], 'yoq'),
  '^\+998 00 \*\*\* \*\* NN \| \+998 00 \*\*\* \*\* 01 \+998 00 \*\*\* \*\* 01 \| yoq$');
select zz.chk('B06 ota yoki ona yo''q bo''lsa — null; ismi bor, raqami yo''q — {name, phone:null, valid:null}; to''g''ri raqam — valid:true',
  (select (r -> 'mother')::text from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r where r -> 'father' ->> 'name' = 'Sinov Ota Epsilon') || ' | '
  || (select (r -> 'father')::text from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r where r -> 'mother' ->> 'name' = 'Sinov Ona Iota') || ' | '
  || (select string_agg(distinct p ->> 'valid', ',') from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r,
             lateral (select r -> 'father' as p union all select r -> 'mother') x where jsonb_typeof(p) = 'object' and p ->> 'phone' is not null),
  '^null \| \{"name": "Sinov Ota Iota", "phone": null, "valid": null\} \| true$');
select zz.chk('B07 javob kalitlari — faqat ruxsat etilganlar (yuqori / qator / ota-ona)',
  zz.keys(zz.j(:'b_list')) || ' | ' || (select string_agg(distinct zz.keys(r), ';') from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r) || ' | '
  || (select string_agg(distinct zz.keys(p), ';') from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r,
             lateral (select r -> 'father' as p union all select r -> 'mother') x where jsonb_typeof(p) = 'object'),
  '^dailyCap,limit,offset,ok,rows,todayUsed,total \| father,k,mother \| name,phone,valid$');
select zz.chk('B08 o''quvchi ma''lumoti yo''q: ism, ID, hujjat id, sinf, manzil, JSHSHIR, sog''liq, tug''ilgan sana, ish joyi, kod',
  (zz.j(:'b_list') ->> 'total') || ' ' || coalesce((regexp_match(:'b_list', '(Bola|IQ-S|doc12|"s1"|uz-5|ZZ|2015-|K7Q2ZP|Ota"|grade|class)'))[1], 'yoq'), '^7 yoq$');
select zz.chk('B09 oila kaliti: 32 ta hex, takrorlanmaydi, qayta so''ralganda o''zgarmaydi, oddiy telefon / ID xeshi emas',
  (select count(*) filter (where r ->> 'k' ~ '^[0-9a-f]{32}$') || '/' || count(distinct r ->> 'k') from jsonb_array_elements(zz.j(:'b_list') -> 'rows') r)
  || ' ' || (zz.list('U_SAL')::text = :'b_list')::text || ' '
  || (zz.key('Sinov Ota Alfa') not in (left(encode(sha256(convert_to('998001110001|998002220001', 'UTF8')), 'hex'), 32), md5('998001110001|998002220001'),
                                       md5('IQ-S01'), md5('s1'), left(encode(sha256(convert_to('|sales-v1|998001110001|998002220001', 'UTF8')), 'hex'), 32)))::text,
  '^7/7 true true$');
-- B10 — savepoint ichida (tuz almashtiriladi): kalit tuzga bog'liq — tuzsiz telefondan kalitni hisoblab bo'lmaydi.
select coalesce(zz.key('Sinov Ota Alfa'), '<NULL>') as b10a \gset
savepoint b10;
select zz.try($q$update app.sales_secret set salt = 'zz-boshqa-tuz' where id = 1$q$) as b10u \gset
select coalesce(zz.key('Sinov Ota Alfa'), '<NULL>') as b10b \gset
rollback to savepoint b10;
select zz.chk('B10 kalit maxfiy tuzga bog''liq (tuz o''zgarsa — kalit o''zgaradi; tuz qaytgach — avvalgisi)',
  :'b10u' || ' ' || (:'b10a' <> :'b10b' and :'b10a' ~ '^[0-9a-f]{32}$' and :'b10b' ~ '^[0-9a-f]{32}$')::text || ' ' || (zz.key('Sinov Ota Alfa') = :'b10a')::text, '^OK true true$');
select zz.chk('B11 qidiruv faqat ota-ona ismi bo''yicha: «alfa», «ONA GAMMA», apostrofsiz «sa''dulla / saʼdulla / sadulla» — 1 tadan',
  (zz.list('U_SAL', $a$'alfa'$a$) ->> 'total') || (zz.list('U_SAL', $a$'ONA GAMMA'$a$) ->> 'total') || (zz.list('U_SAL', $a$'sa''dulla'$a$) ->> 'total')
  || (zz.list('U_SAL', $a$'saʼdulla'$a$) ->> 'total') || (zz.list('U_SAL', $a$'SADULLA'$a$) ->> 'total')
  || ' ' || (select string_agg(r -> 'father' ->> 'name', ',') from jsonb_array_elements(zz.list('U_SAL', $a$'alfa'$a$) -> 'rows') r),
  '^11111 Sinov Ota Alfa$');
select zz.chk('B12 qidiruv o''quvchi ismi / ID / telefon raqami / LIKE belgilari bo''yicha — topmaydi; 2 harfdan qisqa («a», «o''») — hech narsa; bo''sh joy — hammasi',
  (zz.list('U_SAL', $a$'Bola'$a$) ->> 'total') || (zz.list('U_SAL', $a$'IQ-S01'$a$) ->> 'total') || (zz.list('U_SAL', $a$'1110001'$a$) ->> 'total')
  || (zz.list('U_SAL', $a$'%%'$a$) ->> 'total') || (zz.list('U_SAL', $a$'__'$a$) ->> 'total') || ' ' || (zz.list('U_SAL', $a$'a'$a$) ->> 'total')
  || (zz.list('U_SAL', $a$'o'''$a$) ->> 'total') || ' ' || (zz.list('U_SAL', $a$'   '$a$) ->> 'total'),
  '^00000 00 7$');
select zz.chk('B13 sahifalash: 2 ta / 1 ta qoldiq; limit 1000 -> 100, manfiy offset -> 0; jami o''zgarmaydi',
  jsonb_array_length(zz.list('U_SAL', 'null, 2, 0') -> 'rows') || ' ' || jsonb_array_length(zz.list('U_SAL', 'null, 2, 6') -> 'rows') || ' '
  || (zz.list('U_SAL', 'null, 1000, -5') ->> 'limit') || '/' || (zz.list('U_SAL', 'null, 1000, -5') ->> 'offset') || ' '
  || (zz.list('U_SAL', 'null, 2, 6') ->> 'total'), '^2 1 100/0 7$');
select zz.chk('B14 Direktor ham xuddi shu ro''yxatni ko''radi (niqoblangan)', ((zz.list('U_DIR') -> 'rows')::text = (zz.j(:'b_list') -> 'rows')::text)::text, '^true$');

-- ========== (R) ochish, jurnal, kunlik chegara ==========
select coalesce(zz.key('Sinov Ota Alfa'), '<NULL>') as k_alfa, coalesce(zz.key('Sinov Ota Gamma'), '<NULL>') as k_gamma \gset
select zz.as('U_SAL', format('select public.sales_reveal(%L)::text', :'k_alfa')) as r01 \gset
select zz.chk('R01 sotuvchi Alfa oilasini ochadi: to''liq raqamlar va ismlar, bugun 1 / 150',
  (zz.j(:'r01') ->> 'ok') || ' ' || (zz.j(:'r01') #>> '{father,name}') || ' ' || (zz.j(:'r01') #>> '{father,phone}') || ' '
  || (zz.j(:'r01') #>> '{mother,name}') || ' ' || (zz.j(:'r01') #>> '{mother,phone}') || ' ' || (zz.j(:'r01') ->> 'todayUsed') || '/' || (zz.j(:'r01') ->> 'dailyCap'),
  '^true Sinov Ota Alfa \+998001110001 Sinov Ona Alfa \+998002220001 1/150$');
select zz.chk('R02 jurnal: bitta yozuv (sotuvchi, oila kaliti, bugungi kun); raqam yoki o''quvchi ID''si yo''q',
  zz.q(format($q$select string_agg(uid || ' ' || (fkey = %L)::text || ' ' || day::text, ';') from public.sales_contact_log$q$, :'k_alfa'))
  || ' | ' || zz.q($q$select coalesce(string_agg(fkey, ','), 'yoq') from public.sales_contact_log where fkey ~ '(99800|IQ-S)'$q$),
  '^U_SAL true 2026-11-19 \| yoq$');
select zz.as('U_SAL', format('select public.sales_reveal(%L)::text', :'k_alfa')) as r03 \gset
select zz.chk('R03 shu oilani shu kuni qayta ochish — chegarani yemaydi (1 / 150, jurnalda bitta yozuv)',
  (zz.j(:'r03') ->> 'ok') || ' ' || (zz.j(:'r03') ->> 'todayUsed') || ' ' || zz.q('select count(*)::text from public.sales_contact_log'), '^true 1 1$');
select zz.chk('R04 ochish javobi kalitlari — faqat ruxsat etilganlar; o''quvchi ma''lumoti yo''q',
  zz.keys(zz.j(:'r01')) || ' | ' || zz.keys(zz.j(:'r01') -> 'father') || ' | ' || coalesce((regexp_match(:'r01', '(Bola|IQ-S|doc12|ZZ|uz-5|2015-)'))[1], 'yoq'),
  '^dailyCap,father,k,mother,ok,todayUsed \| name,phone,valid \| yoq$');
select zz.as('U_SAL', $q$select public.sales_reveal('0123456789abcdef0123456789abcdef')::text$q$) || ' | '
  || zz.as('U_SAL', $q$select public.sales_reveal('abc')::text$q$) || ' | ' || zz.as('U_SAL', 'select public.sales_reveal(null)::text') || ' | '
  || zz.as('U_SAL', $q$select public.sales_reveal($$' or 1=1 --$$)::text$q$) || ' | '
  || zz.as('U_SAL', format('select public.sales_reveal(%L)::text', zz.q($q$select f.fkey from app.sales_families(true) f where f.f_name = 'Sinov Ota Beta'$q$))) || ' | '
  || zz.as('U_SAL', format('select public.sales_reveal(%L)::text', zz.q($q$select f.fkey from app.sales_families(true) f where f.f_name = 'Sinov Ota Zeta'$q$))) || ' | '
  || coalesce(zz.q($q$select f.fkey from app.sales_families(true) f where f.f_name = 'Sinov Ota Beta'$q$), '<NULL>') as r05 \gset
select zz.chk('R05 noma''lum, yaroqsiz, NULL, «inyeksiya», arxivdagi (kaliti haqiqiy) va o''chirilgan o''quvchi oilasi — not_found; jurnal o''zgarmaydi',
  regexp_replace(:'r05', '\{"ok": false, "reason": "not_found"\}', 'NF', 'g') || ' | ' || zz.q('select count(*)::text from public.sales_contact_log'),
  '^NF \| NF \| NF \| NF \| NF \| NF \| [0-9a-f]{32} \| 1$');
select zz.as('U_DIR', format('select public.sales_reveal(%L)::text', :'k_gamma')) as r06 \gset
select zz.chk('R06 Direktor ochadi — o''z nomidan yoziladi (sotuvchi hisobiga qo''shilmaydi)',
  (zz.j(:'r06') ->> 'ok') || ' ' || (zz.j(:'r06') ->> 'todayUsed') || ' | '
  || zz.q($q$select string_agg(uid || '=' || n, ',' order by uid) from (select uid, count(*) n from public.sales_contact_log group by uid) x$q$),
  '^true 1 \| U_DIR=1,U_SAL=1$');
-- Kunlik chegara: sotuvchiga bugun yana 149 ta (boshqa) oila yozuvi — jami 150.
select zz.try($q$insert into public.sales_contact_log (uid, fkey, day)
  select 'U_SAL', 'zzcap' || lpad(g::text, 27, '0'), '2026-11-19' from generate_series(1, 149) g$q$) as r07i \gset
select zz.as('U_SAL', format('select public.sales_reveal(%L)::text', :'k_gamma')) as r07a \gset
select zz.as('U_SAL', format('select public.sales_reveal(%L)::text', :'k_alfa')) as r07b \gset
select zz.chk('R07 150 ta oila ochilgan: yangi oila — daily_cap (raqamsiz), bugun ochilgani — ochiladi; jurnal 150 da qoladi',
  :'r07a' || ' | ' || (zz.j(:'r07b') ->> 'ok') || ' ' || (zz.j(:'r07b') ->> 'todayUsed') || ' | '
  || zz.q($q$select count(*)::text from public.sales_contact_log where uid = 'U_SAL'$q$) || ' ' || :'r07i',
  '^\{"ok": false, "reason": "daily_cap", "dailyCap": 150, "todayUsed": 150\} \| true 150 \| 150 OK$');
select zz.chk('R08 ro''yxatda ham bugun 150 / 150', (zz.list('U_SAL') ->> 'todayUsed') || '/' || (zz.list('U_SAL') ->> 'dailyCap'), '^150/150$');
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', :'k_gamma')) as r09 \gset
select zz.chk('R09 chegara har foydalanuvchiga alohida: ikkinchi sotuvchi shu oilani ochadi (1 / 150)',
  (zz.j(:'r09') ->> 'ok') || ' ' || (zz.j(:'r09') ->> 'todayUsed') || ' ' || (zz.j(:'r09') #>> '{mother,phone}'), '^true 1 \+998002220003$');
-- Ertasi kun (sinov soati): chegara yangidan.
update app.fin_clock set t = '2026-11-20 09:00+05' where id = 1;
select zz.as('U_SAL', format('select public.sales_reveal(%L)::text', :'k_gamma')) as r10 \gset
select zz.chk('R10 ertasi kun: chegara yangidan — ochiladi, bugun 1; jurnalda yangi kun yozuvi',
  (zz.j(:'r10') ->> 'ok') || ' ' || (zz.j(:'r10') ->> 'todayUsed') || ' ' || (zz.list('U_SAL') ->> 'todayUsed') || ' | '
  || zz.q($q$select string_agg(day::text || '=' || n, ',' order by day) from (select day, count(*) n from public.sales_contact_log where uid = 'U_SAL' group by day) x$q$),
  '^true 1 1 \| 2026-11-19=150,2026-11-20=1$');
-- R11 — tuzilma: bir vaqtdagi ochishlar chegarani oshirmasligi uchun foydalanuvchi bo'yicha qulf olinadi (bitta tranzaksiyali sinovda ikki
--   ulanishni sinab bo'lmaydi — funksiya matni va noyoblik cheklovi tekshiriladi).
select zz.chk('R11 sales_reveal — foydalanuvchi bo''yicha maslahat qulfi (pg_advisory_xact_lock) va jurnal noyobligi (uid, fkey, day)',
  (select (prosrc ~ 'pg_advisory_xact_lock\(hashtextextended\(''sales_reveal\|'' \|\| v_uid')::text from pg_proc where oid = to_regprocedure('public.sales_reveal(text)'))
  || ' ' || (select pg_get_constraintdef(k.oid) from pg_constraint k where k.conrelid = to_regclass('public.sales_contact_log') and k.contype = 'u'),
  '^true UNIQUE \(uid, fkey, day\)$');

-- ========== (L) Direktor jurnali ==========
select zz.as('U_DIR', 'select public.sales_log(30)::text') as l01 \gset
select zz.chk('L01 Direktor jurnali: kunlar bo''yicha (sotuvchi 150 / 1, ikkinchi sotuvchi 1, Direktor 1), ism va rol bilan',
  (select string_agg((d ->> 'day') || ' ' || (d ->> 'name') || ' ' || (d ->> 'role') || ' ' || (d ->> 'count'), '; ' order by d ->> 'day', d ->> 'uid')
     from jsonb_array_elements(zz.j(:'l01') -> 'days') d),
  '^2026-11-19 Sinov Direktor director 1; 2026-11-19 Sinov Sotuvchi sales 150; 2026-11-19 Sinov Sotuvchi Ikki sales 1; 2026-11-20 Sinov Sotuvchi sales 1$');
select zz.chk('L02 oxirgi ochishlar: eng yangisi birinchi; ota-ona ismi (sinov yozuvlari — ismsiz); telefon raqami yo''q',
  jsonb_array_length(zz.j(:'l01') -> 'recent') || ' | '
  || (select string_agg(coalesce(r ->> 'father', '-') || '/' || (r ->> 'name'), ', ' order by ord) from jsonb_array_elements(zz.j(:'l01') -> 'recent') with ordinality t(r, ord)
       where r ->> 'father' is not null)
  || ' | ' || coalesce((regexp_match(:'l01', '(\d{7,}|99800)'))[1], 'yoq'),
  '^153 \| Sinov Ota Gamma/Sinov Sotuvchi, Sinov Ota Gamma/Sinov Sotuvchi Ikki, Sinov Ota Gamma/Sinov Direktor, Sinov Ota Alfa/Sinov Sotuvchi \| yoq$');
select zz.chk('L03 jurnal kunlar oralig''i: 1 kun — faqat bugungi (ertasi kun) yozuvlar',
  (select string_agg(d ->> 'day', ',') from jsonb_array_elements(zz.j(zz.as('U_DIR', 'select public.sales_log(1)::text')) -> 'days') d), '^2026-11-20$');

-- ========== (X) qo'shimcha lavozim yo'q ==========
select zz.chk('X01 Direktor sotuvchiga qo''shimcha lavozim bera olmaydi',
  zz.as('U_DIR', $q$update public.users set "extraRoles" = '["reception"]' where id = 'U_SAL' returning "extraRoles"::text$q$), '^ERR 22023 ');
select zz.as('U_DIR', $q$update public.users set role = 'sales' where id = 'U_TX' returning "extraRoles"::text$q$) as x02 \gset
select zz.chk('X02 asosiy rol «Sotuvchi» bo''lganda qo''shimchalar tozalanadi', :'x02' || ' ' || (select "extraRoles"::text from public.users where id = 'U_TX'), '^\[\] \[\]$');
select zz.chk('X03 eski qo''shimchali sotuvchi: rollar faqat {sales}, xodim / qabulxona / kassir / O''IBDO'' emas; sinf o''qituvchisi ham emas',
  zz.as('U_SALX', 'select app.role_set()::text') || ' ' || zz.as('U_SALX', 'select app.is_staff()::text') || ' ' || zz.as('U_SALX', 'select app.is_reception()::text')
  || ' ' || zz.as('U_SALX', 'select app.is_cashier()::text') || ' ' || zz.as('U_SALX', 'select app.is_zavuch()::text')
  || ' ' || zz.as('U_SALX', $q$select app.is_teacher_for_class('uz-5-A')::text$q$) || ' ' || zz.as('U_SALX', $q$select app.is_homeroom_for('uz-5-A')::text$q$),
  '^\{sales\} false false false false false false$');
select zz.chk('X04 app.u_has: sotuvchining qo''shimchasi hisobga olinmaydi; boshqa rolda — olinadi; sales — qo''shimcha bo''la olmaydi',
  app.u_has('sales', '["kassir"]'::jsonb, 'kassir')::text || '/' || app.u_has('guard', '["kassir"]'::jsonb, 'kassir')::text || '/'
  || ('sales' = any(app.extra_roles_allowed()))::text || '/' || app.u_has('guard', '["sales"]'::jsonb, 'sales')::text, '^false/true/false/false$');
select zz.chk('X05 yangi sotuvchi hisobi qo''shimcha lavozim bilan yaratilmaydi',
  zz.try($q$insert into public.users (id, email, role, status, "extraRoles") values ('U_NEWS','ns@example.org','sales','active','["kassir"]')$q$), '^ERR 22023 ');
select zz.chk('X06 sotuvchi o''ziga qo''shimcha lavozim bera olmaydi',
  zz.as('U_SAL', $q$update public.users set "extraRoles" = '["reception"]' where id = 'U_SAL' returning "extraRoles"::text$q$), '^ERR 42501 ');

-- ========== (W) yozish yo'q ==========
select zz.chk('W01 sotuvchi asosiy jadvallarga yoza olmaydi (INSERT — triggerlarsiz, faqat RLS / GRANT): ro''yxatda faqat o''tib ketganlar',
  (select coalesce(string_agg(t || '=' || left(r, 30), '; ' order by t), '') from (
     select t, zz.ins('U_SAL', case when t = 'sales_contact_log'
                                     then $s$insert into public.sales_contact_log (uid, fkey, day) values ('U_SAL', 'zzw', '2026-11-19') returning id::text$s$
                                     else format('insert into public.%I (id) values (%L) returning id', t, 'zzw_' || t) end) as r
       from unnest(array['students','student_private','student_codes','child_claims','invoices','payments','attendance','grades','monitoring',
                         'characteristics','student_summaries','subject_notes','enrollments','teachers','staff','salary_payments','staff_advances',
                         'expenses','discount_requests','student_health','sick_notes','sms_log','deleted_records','users','sales_contact_log']) t) x
    where r !~ '^ERR 42501 '), '^$');
select zz.chk('W02 sotuvchi UPDATE / DELETE: hech bir qator (0) yoki huquq yo''q',
  (select coalesce(string_agg(t || ':' || u || '/' || d, '; ' order by t), '') from (
     select t, zz.as('U_SAL', format('with x as (update public.%I set id = id returning 1) select count(*)::text from x', t)) as u,
               zz.as('U_SAL', format('with x as (delete from public.%I returning 1) select count(*)::text from x', t)) as d
       from unnest(array['students','student_private','student_codes','child_claims','invoices','payments','attendance','grades','monitoring',
                         'characteristics','student_summaries','subject_notes','enrollments','teachers','staff','salary_payments','staff_advances',
                         'expenses','discount_requests','student_health','sick_notes','sms_log','deleted_records','sales_contact_log']) t) x
    where u !~ '^(0|ERR 42501 .*)$' or d !~ '^(0|ERR 42501 .*)$'), '^$');
select zz.as('U_SAL', $q$with u as (update public.users set role = 'director' where id = 'U_SAL' returning 1) select count(*)::text from u$q$) || ' / '
  || zz.as('U_SAL', $q$with u as (update public.users set status = 'active', verified = true where id = 'U_SALP' returning 1) select count(*)::text from u$q$) || ' / '
  || zz.as('U_SAL', $q$with d as (delete from public.users where id <> 'U_SAL' returning 1) select count(*)::text from d$q$) as w03 \gset
select zz.chk('W03 sotuvchi o''z rolini o''zgartira olmaydi, boshqa hisobga tegolmaydi; roli — sales',
  :'w03' || ' | ' || (select role from public.users where id = 'U_SAL') || ' ' || (select status from public.users where id = 'U_SALP'),
  '^(ERR 42501 [^/]*|0) / 0 / 0 \| sales pending$');
select zz.chk('W04 jurnal va maxfiy tuz: sotuvchi (va Direktor) to''g''ridan-to''g''ri o''qiy olmaydi; ichki yordamchilar yopiq',
  zz.as('U_SAL', 'select count(*)::text from public.sales_contact_log') || ' | ' || zz.as('U_DIR', 'select count(*)::text from public.sales_contact_log')
  || ' | ' || zz.as('U_SAL', 'select salt from app.sales_secret') || ' | ' || zz.as('U_SAL', 'select count(*)::text from app.sales_families(false)')
  || ' | ' || zz.as('U_SAL', 'select app.sales_need()::text'),
  '^ERR 42501 [^|]* \| ERR 42501 [^|]* \| ERR 42501 [^|]* \| ERR 42501 [^|]* \| ERR 42501 ');
select zz.chk('W05 jurnal va tuz jadvali huquqlari: anon / authenticated — hech narsa; RLS yoqilgan',
  (select string_agg(t || '=' || case when to_regclass(t) is null then 'yoq' else has_table_privilege('anon', t, 'SELECT,INSERT,UPDATE,DELETE')::text
                     || has_table_privilege('authenticated', t, 'SELECT,INSERT,UPDATE,DELETE')::text
                     || (select relrowsecurity::text from pg_class where oid = to_regclass(t)) end, ',' order by t)
     from unnest(array['public.sales_contact_log', 'app.sales_secret']) t),
  '^app.sales_secret=falsefalsetrue,public.sales_contact_log=falsefalsetrue$');

-- ========== (S) sotuvchi jadvallarda nima ko'radi ==========
select zz.chk('S01 asosiy jadval va ko''rinishlar: sotuvchi (va eski qo''shimchali sotuvchi) — 0 qator (yoki huquq yo''q)',
  (select coalesce(string_agg(u || ':' || t || '=' || n, '; ' order by u, t), '') from (
     select u, t, zz.cnt(u, 'public.' || t) as n
       from unnest(array['U_SAL','U_SALX']) u,
            unnest(array['students','student_private','student_phones','students_billing','student_codes','child_claims','invoices','invoices_acc',
                         'payments','payments_acc','attendance','grades','monitoring','characteristics','student_summaries','subject_notes',
                         'enrollments','teachers','staff','salary_payments','staff_advances','expenses','discount_requests','student_health',
                         'nurse_visits','sick_notes','sms_log','deleted_records','feedback','change_log','class_announcements']) t
      where to_regclass('public.' || t) is not null) x
    where n !~ '^(0|ERR 42501 .*)$'), '^$');
select zz.chk('S02 users: sotuvchi faqat o''z qatorini ko''radi',
  zz.as('U_SAL', 'select string_agg(id, '','') from public.users'), '^U_SAL$');

-- ========== (G) sizish invarianti ==========
select zz.chk('G01 urug'': authenticated o''qiy oladigan har bir jadval to''ldirilgan (bo''sh jadval yo''q; to''ldirib bo''lmagani — ro''yxatda)',
  (select coalesce(string_agg(c.relname || coalesce(' (' || (select f.err from zz_fill_fail f where f.t = c.relname limit 1) || ')', ''), '; ' order by c.relname), '')
     from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and has_table_privilege('authenticated', c.oid, 'SELECT')
      and not (xpath('/row/c/text()', query_to_xml(format('select (exists (select 1 from public.%I))::int as c', c.relname), false, true, '')))[1]::text = '1'), '^$');
create temp table zz_leak on commit drop as
  select n.nspname || '.' || c.relname as rel,
         zz.cnt('U_SAL', format('%I.%I', n.nspname, c.relname)) as n_sal,
         zz.cnt('U_SALX', format('%I.%I', n.nspname, c.relname)) as n_salx,
         zz.cnt('U_PAR0', format('%I.%I', n.nspname, c.relname)) as n_par
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'storage') and c.relkind in ('r', 'v', 'm', 'p') and has_table_privilege('authenticated', c.oid, 'SELECT');
-- son: ERR (o'qib bo'lmaydi) — 0 deb olinadi
create or replace function zz.num(p text) returns bigint language sql immutable as $$ select case when p ~ '^\d+$' then p::bigint else 0 end $$;
select zz.chk('G02 SIZISH INVARIANTI: har bir jadval / ko''rinishda sotuvchi ko''radigan qatorlar <= farzandsiz faol ota-ona (oldida — tekshirilganlar soni)',
  (select count(*) || ':' || coalesce(string_agg(case when zz.num(n_sal) > zz.num(n_par) then rel || '=' || n_sal || '>' || n_par end, ',' order by rel), '') from zz_leak),
  '^[0-9]{2,}:$');
select zz.chk('G03 eski qo''shimchali sotuvchi (reception, kassir, zavuch, teacher + sinf biriktiruvi) ham — farzandsiz ota-onadan ortiq emas',
  (select count(*) || ':' || coalesce(string_agg(case when zz.num(n_salx) > zz.num(n_par) then rel || '=' || n_salx || '>' || n_par end, ',' order by rel), '') from zz_leak),
  '^[0-9]{2,}:$');
-- G04: har bir mijoz RPC'si (public, SECURITY DEFINER, authenticated chaqira oladi) sotuvchi va farzandsiz ota-ona nomidan NULL argumentlar bilan;
--   javobi farq qiladiganlar (uid / email / ism / rol tenglashtirilgan). Ta'siri savepoint bilan bekor qilinadi (natija psql o'zgaruvchisida).
savepoint g04;
create temp table zz_rpc as
  select p.proname,
         regexp_replace(zz.as('U_SAL', format('select left(public.%I(%s)::text, 2000)', p.proname, (select coalesce(string_agg('null', ','), '') from generate_series(1, p.pronargs))))
                        , '(U_SAL|s@example\.org|Sinov Sotuvchi|"sales")', '#', 'g') as r_sal,
         regexp_replace(zz.as('U_PAR0', format('select left(public.%I(%s)::text, 2000)', p.proname, (select coalesce(string_agg('null', ','), '') from generate_series(1, p.pronargs))))
                        , '(U_PAR0|p0@example\.org|Sinov Ota Farzandsiz|"parent")', '#', 'g') as r_par
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prokind = 'f' and has_function_privilege('authenticated', p.oid, 'execute');
select (select count(*) from zz_rpc) || ':' || coalesce((select string_agg(proname, ',' order by proname) from zz_rpc where r_sal is distinct from r_par), '') as g04 \gset
rollback to savepoint g04;
select zz.chk('G04 YOPIQ RO''YXAT (xatti-harakat): sotuvchiga farzandsiz ota-onadan boshqacha javob beradigan RPC''lar (oldida — tekshirilganlar soni; claim_child — rad javobi)',
  :'g04', '^[0-9]{2,}:claim_child,sales_contacts,sales_reveal$');
-- G05: ruxsat beruvchi joylar (role_set, u_has, sales_need, oila kaliti) va faqat RAD ETUVCHI qoidalar (farzand bog'lanishi, blokdan chiqarish,
--   xabarnoma muharriri, o'qituvchi bahosi, RLS darvozalari — rls_acl / rls_gate_any sotuvchini huquqsizlar qatoriga qo'yadi).
--   Yangi joy paydo bo'lsa — shu ro'yxatga ongli ravishda qo'shiladi.
select zz.chk('G05 YOPIQ RO''YXAT (matn): ''sales'' so''zi — faqat shu funksiya va siyosatlarda; ko''rinishlarda — yo''q',
  (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname, p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'app') and p.prosrc ~ '\msales\M') || ' | '
  || coalesce((select string_agg(tablename || '.' || policyname, ',' order by tablename, policyname) from pg_policies
                where (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ~ '\msales\M'), '-') || ' | '
  || coalesce((select string_agg(viewname, ',' order by viewname) from pg_views where schemaname in ('public', 'app') and definition ~ '\msales\M'), '-'),
  '^app.child_claim_staff_gate,app.is_notify_editor,app.rls_acl,app.rls_gate_any,app.role_set,app.sales_families,app.sales_need,app.u_has,app.users_extra_roles_guard,app.users_sales_claims,app.users_sales_identity_guard,public.claim_child,public.user_unblock \| feedback.fb_ins,teacher_ratings.tr_del,teacher_ratings.tr_ins,teacher_ratings.tr_upd \| -$');

-- ========== (H) kuchaytirish ==========
select zz.chk('H01 claim_child: sotuvchi va buxgalter hisobiga farzand biriktirilmaydi (to''g''ri kod bilan ham); bog''lanish yozilmaydi',
  zz.as('U_SAL', $q$select public.claim_child('IQ-S01', 'K7Q2ZP')::text$q$) || ' | ' || zz.as('U_ACC', $q$select public.claim_child('IQ-S01', 'K7Q2ZP') ->> 'error'$q$)
  || ' | ' || zz.q($q$select count(*)::text from public.child_claims where uid in ('U_SAL', 'U_ACC')$q$),
  '^\{"ok": false, "error": "Sotuvchi hisobiga farzand biriktirilmaydi — ota-ona hisobidan foydalaning\."\} \| Buxgalter hisobiga farzand biriktirilmaydi — ota-ona hisobidan foydalaning\. \| 0$');
select zz.try($q$insert into public.child_claims (id, uid, "studentId", code, status) values ('U_SAL__IQ-S02', 'U_SAL', 'IQ-S02', 'M4R8TX', 'active')$q$) || ' | '
  || zz.try($q$insert into public.child_claims (id, uid, "studentId", code, status) values ('U_ACC__IQ-S02', 'U_ACC', 'IQ-S02', 'M4R8TX', 'active')$q$) || ' | '
  || zz.as('U_DIR', $q$select public.child_claim_decide('U_SALC__IQ-S02', true)::text$q$) as h02 \gset
select zz.chk('H02 qo''riqchi: xizmat yozuvi (baza egasi) va Direktor tasdig''i ham ish hisobidagi bog''lanishni faollashtirmaydi (42501)',
  :'h02' || ' | ' || coalesce((select status from public.child_claims where id = 'U_SALC__IQ-S02'), '-') || ' '
  || (select count(*)::text from public.child_claims where uid in ('U_SAL', 'U_ACC')),
  '^ERR 42501 Bu ish hisobiga \(buxgalter / sotuvchi\) farzand biriktirilmaydi[^|]* \| ERR 42501 Bu ish hisobiga[^|]* \| ERR 42501 Bu ish hisobiga[^|]* \| pending 0$');
select zz.cnt('U_PAR2', 'public.students') as h03a \gset
select zz.as('U_DIR', $q$update public.users set role = 'sales' where id = 'U_PAR2' returning role$q$) as h03u \gset
select zz.chk('H03 rol «Sotuvchi»ga o''zgarganda faol va kutilayotgan bog''lanishlar bekor qilinadi — farzand ma''lumoti yopiladi; xabarnoma muharrirlaridan chiqariladi',
  :'h03a' || ' ' || :'h03u' || ' | ' || coalesce((select string_agg(id || ':' || status, ',' order by id) from public.child_claims where uid = 'U_PAR2'), '-')
  || ' | ' || zz.cnt('U_PAR2', 'public.students') || zz.cnt('U_PAR2', 'public.student_private') || zz.cnt('U_PAR2', 'public.invoices')
  || ' | ' || coalesce((select (editors ? 'U_PAR2')::text || '/' || (editors ? 'U_REC')::text from public.notify_settings where id = 'general'), '-'),
  '^1 sales \| U_PAR2__IQ-S02:revoked,U_PAR2__IQ-S08:revoked \| 000 \| false/true$');
-- H04: bloklash / blokdan chiqarish (auth-server RPC'lari, baza egasi nomidan). Har chaqiruv xatoni matn qilib qaytaradi (sinov to'xtamaydi).
create temp table zz_h04 (step text primary key, r text) on commit drop;
insert into zz_h04 select 'block', zz.q($q$select (public.user_block('U_ACCB', 'U_DIR') ->> 'ok') || '/' || (public.user_block('U_PAR3', 'U_DIR') ->> 'ok')$q$);
insert into zz_h04 select 'unblock', (select string_agg(u || '=' || coalesce((zz.j(r) ->> 'ok') || '/' || (zz.j(r) ->> 'claims') || '/' || (zz.j(r) ->> 'role'), left(r, 90)), ',' order by u)
                                        from (select u, zz.q(format('select public.user_unblock(%L, %L)::text', u, 'U_DIR')) as r
                                                from unnest(array['U_ACCB', 'U_PAR3', 'U_SALB2']) u) x);
do $rs$ begin perform set_config('app.uid', '', true); perform set_config('iqror.user_block', '', true); end $rs$;   -- user_block / user_unblock o'rnatgan qiymatlar
select zz.chk('H04 blokdan chiqarish: buxgalter va sotuvchi bog''lanishi qaytmaydi, RPC xatosiz (avval qo''riqchi xatosi bilan to''xtardi); ota-onaniki — qaytadi',
  coalesce((select r from zz_h04 where step = 'block'), '-') || ' | ' || coalesce((select r from zz_h04 where step = 'unblock'), '-') || ' | '
  || coalesce((select string_agg(id || ':' || status, ',' order by id) from public.child_claims where uid in ('U_ACCB', 'U_PAR3', 'U_SALB2')), '-'),
  '^true/true \| U_ACCB=true/0/accountant,U_PAR3=true/1/parent,U_SALB2=true/0/sales \| U_ACCB__IQ-S02:revoked,U_PAR3__IQ-S08:active,U_SALB2__IQ-S02:revoked$');
select zz.as('U_PAR2', $q$with d as (delete from public.teacher_ratings where id = 'U_PAR2__IQT-S01' returning 1) select count(*)::text from d$q$) as h05d \gset
select zz.chk('H05 o''qituvchiga baho: sotuvchi qo''ya olmaydi, ota-ona qo''yadi (nazorat); sotuvchiga aylangan hisob eski bahosini o''zgartira ham, o''chira ham olmaydi',
  zz.ins('U_SAL', $q$insert into public.teacher_ratings (id, "teacherId", uid, stars) values ('U_SAL__IQT-S01', 'IQT-S01', 'U_SAL', 5) returning id$q$) || ' | '
  || zz.ins('U_PAR0', $q$insert into public.teacher_ratings (id, "teacherId", uid, stars) values ('U_PAR0__IQT-S01', 'IQT-S01', 'U_PAR0', 4) returning id$q$) || ' | '
  || zz.as('U_PAR2', $q$update public.teacher_ratings set stars = 1 where id = 'U_PAR2__IQT-S01' returning id$q$) || ' | '
  || :'h05d' || ' ' || (select count(*)::text from public.teacher_ratings where id = 'U_PAR2__IQT-S01'),
  '^ERR 42501 [^|]* \| U_PAR0__IQT-S01 \| ERR 42501 [^|]* \| 0 1$');
select zz.chk('H06 xabarnoma muharriri: ro''yxatdagi sotuvchi — emas (o''qiy / o''zgartira olmaydi); ro''yxatdagi qabulxona — muharrir (nazorat)',
  zz.as('U_SAL', 'select app.is_notify_editor()::text') || ' ' || zz.as('U_REC', 'select app.is_notify_editor()::text') || ' | '
  || zz.cnt('U_SAL', 'public.notify_settings') || ' ' || zz.as('U_SAL', $q$with u as (update public.notify_settings set "tgText" = 'zz' returning 1) select count(*)::text from u$q$),
  '^false true \| 0 (0|ERR 42501 .*)$');
select zz.chk('H07 student_phones — security_barrier (mijoz filtri ruxsat shartidan oldin bajarilmaydi)',
  (select coalesce(array_to_string(reloptions, ','), '-') from pg_class where oid = to_regclass('public.student_phones')), '^security_barrier=true$');
-- H08–H10 — savepoint ichida (yangi oilalar; natijalar \gset bilan, savepoint qaytarilgach tekshiriladi). Bugun (sinov soati) — 2026-11-20.
savepoint h08;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('h1','IQ-H01','Sinov Bola H Bir',4,'A','uz','',101), ('h2','IQ-H02','Sinov Bola H Ikki',6,'A','uz','',102), ('h3','IQ-H03','Sinov Bola H Uch',2,'A','uz','',103),
  ('h4','IQ-H04','Sinov Bola H Tort',7,'A','uz','',104), ('h5','IQ-H05','Sinov Bola H Besh',8,'A','ru','',105),
  ('h6','IQ-H06','Sinov Bola H Olti',3,'A','uz','',106), ('h7','IQ-H07','Sinov Bola H Yetti',4,'A','uz','',107), ('h8','IQ-H08','Sinov Bola H Sakkiz',5,'A','uz','',108),
  ('h9','IQ-H09','Sinov Bola H Toqqiz',6,'A','uz','',109), ('h10','IQ-H10','Sinov Bola H On',7,'A','uz','',110), ('h11','IQ-H11','Sinov Bola H Onbir',8,'A','uz','',111);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('h1','Sinov Ota Omega','Sinov Ona Omega','+998 00 111 00 21','+998 00 222 00 22'),
  ('h2','Sinov Ota Omega','Sinov Ona Omega','998002220022','998001110021'),                            -- aka-uka kartasida raqamlar almashib yozilgan
  ('h3','Ota Omega Sinov',null,'+998 (00) 111-00-21',null),                                            -- faqat ota raqami, boshqa yozuv shakli, so'zlar tartibi boshqa
  ('h4','Sinov Ota Sigma','Sinov Ona Sigma','+998 00 111 00 31, +998 00 111 00 32','+44 7700 900033'),  -- bir katakda ikki raqam; xorij raqami
  ('h5','Синов Ота Тау',null,'+998 00 111 00 41',null),                                               -- kirill yozuvi
  ('h6','Sinov Ota Pi','Sinov Ona Pi','+998 00 111 00 61','+998 00 555 00 00'),
  ('h7','Sinov Ota Rho','Sinov Ona Rho','+998 00 111 00 71','+998 00 555 00 00'),                      -- umumiy «to'ldiruvchi» raqam, boshqa oila
  ('h8','Sinov Ota Phi',null,'0','+998 00 222 00 81'),
  ('h9','Sinov Ota Phi',null,'0','+998 00 222 00 91'),                                                 -- umumiy raqam faqat noto'g'ri «0»
  ('h10','Sinov Ota Psi','Sinov Ona Psi Bir','+998 00 111 00 95','+998 00 222 00 95'),
  ('h11','Sinov Ota Psi','Sinov Ona Psi Ikki','+998 00 111 00 95','+998 00 222 00 96');               -- bir ota, ikki ona — ikki oila
set local session_replication_role = origin;
select coalesce(zz.list('U_SAL')::text, '<NULL>') as h_list \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Omega'))) as h_rv1 \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Sigma'))) as h_rv2 \gset
select coalesce((zz.list('U_SAL', $a$'тау'$a$) ->> 'total') || (zz.list('U_SAL', $a$'ТАУ'$a$) ->> 'total') || (zz.list('U_SAL', $a$'Тау'$a$) ->> 'total')
       || (zz.list('U_SAL', $a$'синов ота'$a$) ->> 'total') || ' ' || coalesce((select string_agg(r -> 'father' ->> 'name', ',')
            from jsonb_array_elements(zz.list('U_SAL', $a$'тау'$a$) -> 'rows') r), '-'), '<NULL>') as h_cyr \gset
rollback to savepoint h08;
select zz.chk('H08 oila grafi: almashib yozilgan, to''liq bo''lmagan, ism so''zlari boshqa tartibdagi aka-uka kartalari — bitta oila (jami 16); ikkala raqam (ota 21, ona 22)',
  (zz.j(:'h_list') ->> 'total') || ' ' || (select count(*) from jsonb_array_elements(zz.j(:'h_list') -> 'rows') r where r -> 'father' ->> 'name' = 'Sinov Ota Omega')
  || ' | ' || coalesce((select (r -> 'father' ->> 'phone') || ' ' || (r -> 'mother' ->> 'name') || ' ' || (r -> 'mother' ->> 'phone')
                          from jsonb_array_elements(zz.j(:'h_list') -> 'rows') r where r -> 'father' ->> 'name' = 'Sinov Ota Omega'), '-')
  || ' | ' || coalesce((zz.j(:'h_rv1') #>> '{father,phone}') || ' ' || (zz.j(:'h_rv1') #>> '{mother,phone}'), left(:'h_rv1', 90)),
  '^16 1 \| \+998 00 \*\*\* \*\* 21 Sinov Ona Omega \+998 00 \*\*\* \*\* 22 \| \+998001110021 \+998002220022$');
select zz.chk('H09 raqam shakli: bir katakda ikki raqam — valid:false, niqob — birinchi raqamniki, ochganda — har bir raqam; xorij raqami — valid:true, «+»; ro''yxatda uzun raqam yo''q',
  coalesce((select (r -> 'father')::text || ' ' || (r -> 'mother')::text from jsonb_array_elements(zz.j(:'h_list') -> 'rows') r
             where r -> 'father' ->> 'name' = 'Sinov Ota Sigma'), '-')
  || ' | ' || coalesce((zz.j(:'h_rv2') -> 'father')::text || ' ' || (zz.j(:'h_rv2') -> 'mother')::text, left(:'h_rv2', 90))
  || ' | ' || coalesce((regexp_match(regexp_replace(:'h_list', '"k": "[0-9a-f]{32}"', '', 'g'), '\d{5,}'))[1], 'yoq'),
  '^\{"name": "Sinov Ota Sigma", "phone": "\+998 00 \*\*\* \*\* 31", "valid": false\} \{"name": "Sinov Ona Sigma", "phone": "\*\*\* \*\* 33", "valid": true\}'
  || ' \| \{"name": "Sinov Ota Sigma", "phone": "\+998 00 111 00 31, \+998 00 111 00 32", "valid": false\} \{"name": "Sinov Ona Sigma", "phone": "\+447700900033", "valid": true\} \| yoq$');
select zz.chk('H10 kirill yozuvidagi ism: kichik / katta / aralash harf bilan topiladi (lotin «Sinov» — boshqa harflar)',
  :'h_cyr', '^1111 Синов Ота Тау$');
select zz.chk('H11 bog''lanmaydi: umumiy «to''ldiruvchi» raqam (ismlar boshqa), faqat noto''g''ri «0» umumiy, bir ota — ikki ona (ona ismi zid)',
  coalesce((select string_agg(n || '=' || c, ',' order by n) from (select r -> 'father' ->> 'name' as n, count(*) as c
              from jsonb_array_elements(zz.j(:'h_list') -> 'rows') r
             where r -> 'father' ->> 'name' in ('Sinov Ota Pi', 'Sinov Ota Rho', 'Sinov Ota Phi', 'Sinov Ota Psi') group by 1) x), '-'),
  '^Sinov Ota Phi=2,Sinov Ota Pi=1,Sinov Ota Psi=2,Sinov Ota Rho=1$');
-- H12 — savepoint ichida: Gamma oilasiga arxivdagi (bitirgan) aka qo'shiladi — hujjat id'si eng kichik, shuning uchun «hamma o'quvchilar»
--   bo'yicha oila kaliti boshqacha; jurnal ismlari avval faol oilalardan olinadi.
savepoint h12;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "exitAt", "order") values
  ('s0','IQ-S00','Sinov Bola Nol',11,'A','uz','chiqdi','2026-06-01',0);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('s0','Sinov Ota Gamma','Sinov Ona Gamma','+998001110003','+998002220003');
set local session_replication_role = origin;
select zz.as('U_DIR', 'select public.sales_log(30)::text') as h12 \gset
select (select count(*) from app.sales_families(true) f where f.f_name = 'Sinov Ota Gamma') || '/'
       || (select count(*) from app.sales_families(true) f join app.sales_families(false) g on g.fkey = f.fkey where f.f_name = 'Sinov Ota Gamma') as h12k \gset
rollback to savepoint h12;
select zz.chk('H12 Direktor jurnali: oilaga arxivdagi aka (kichik id, oila kaliti boshqa) qo''shilsa ham — ota-ona ismlari ko''rinadi',
  :'h12k' || ' | ' || coalesce((select string_agg(coalesce(r ->> 'father', '-') || '/' || (r ->> 'name'), ', ' order by ord)
                                  from jsonb_array_elements(zz.j(:'h12') -> 'recent') with ordinality t(r, ord) where r ->> 'father' is not null), '-'),
  '^1/0 \| Sinov Ota Gamma/Sinov Sotuvchi, Sinov Ota Gamma/Sinov Sotuvchi Ikki, Sinov Ota Gamma/Sinov Direktor, Sinov Ota Alfa/Sinov Sotuvchi$');
-- H13–H14 — savepoint ichida: (H13) «ko'prik» karta — bir ota, ikki ona va onasi yozilmagan uchinchi karta (umumiy ota raqami);
--   (H14) ota raqami ota ismi yozilgan kartadan — onasi ro'yxatdan o'tkazgan ikki karta (ota ismi bo'sh, «ota telefoni»da ona raqami).
savepoint h13;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('k1','IQ-K1','Sinov Bola K1',3,'A','uz','',201), ('k2','IQ-K2','Sinov Bola K2',4,'A','uz','',202), ('k3','IQ-K3','Sinov Bola K3',5,'A','uz','',203),
  ('k4','IQ-K4','Sinov Bola K4',6,'A','uz','',204),
  ('b1','IQ-B1','Sinov Bola B1',3,'B','uz','',211), ('b2','IQ-B2','Sinov Bola B2',4,'B','uz','',212), ('b3','IQ-B3','Sinov Bola B3',5,'B','uz','',213);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('k1','Sinov Ota Kappa Ikki','Sinov Ona Zarina','+998 00 111 00 51','+998 00 222 00 51'),
  ('k2','Sinov Ota Kappa Ikki',null,'+998 00 111 00 51',null),                                        -- «ko'prik»: onasi yozilmagan
  ('k4','Kappa Ikki Sinov Ota',null,'998001110051',null),                                              -- xuddi shu «ko'prik», boshqacha yozilgan
  ('k3','Sinov Ota Kappa Ikki','Sinov Ona Aziza','+998 00 111 00 51','+998 00 333 00 53'),
  ('b1','Sinov Ota Botir','Sinov Ona Dilnoza','+998 00 111 00 61','+998 00 222 00 62'),
  ('b2',null,'Sinov Ona Dilnoza','+998 00 222 00 62',null),                                            -- ota ismi bo'sh, «ota telefoni» — ona raqami
  ('b3',null,'Sinov Ona Dilnoza','+998 00 222 00 62',null);
set local session_replication_role = origin;
select coalesce(zz.list('U_SAL', $a$'kappa ikki'$a$)::text, '<NULL>') as h13_list \gset
select coalesce((zz.list('U_SAL', $a$'zarina'$a$) ->> 'total') || (zz.list('U_SAL', $a$'aziza'$a$) ->> 'total'), '<NULL>') as h13_q \gset
select coalesce(zz.list('U_SAL', $a$'dilnoza'$a$)::text, '<NULL>') as h14_list \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Botir'))) as h14_rv \gset
rollback to savepoint h13;
select zz.chk('H13 «ko''prik» karta: bir ota — ikki ona birlashmaydi (3 qator: Zarina, Aziza, onasi yozilmagani); har ona o''z raqami bilan; ikkalasi qidiruvda topiladi',
  (zz.j(:'h13_list') ->> 'total') || ' | ' || coalesce((select string_agg(coalesce(r -> 'mother' ->> 'name', '-') || '=' || coalesce(r -> 'mother' ->> 'phone', '-'), ', ' order by coalesce(r -> 'mother' ->> 'name', '-'))
                                                        from jsonb_array_elements(zz.j(:'h13_list') -> 'rows') r), '-') || ' | ' || :'h13_q',
  '^3 \| -=-, Sinov Ona Aziza=\+998 00 \*\*\* \*\* 53, Sinov Ona Zarina=\+998 00 \*\*\* \*\* 51 \| 11$');
select zz.chk('H14 ota raqami — ota ismi yozilgan kartadan (onasi ro''yxatdan o''tkazgan 2 karta ustun bo''lsa ham): ota 61, ona 62; bitta oila',
  (zz.j(:'h14_list') ->> 'total') || ' | ' || coalesce((zz.j(:'h14_rv') #>> '{father,name}') || ' ' || (zz.j(:'h14_rv') #>> '{father,phone}') || ' '
  || (zz.j(:'h14_rv') #>> '{mother,name}') || ' ' || (zz.j(:'h14_rv') #>> '{mother,phone}'), left(:'h14_rv', 90)),
  '^1 \| Sinov Ota Botir \+998001110061 Sinov Ona Dilnoza \+998002220062$');
select zz.chk('H15 murojaatlar qutisi: sotuvchi yoza olmaydi (ota-ona nomidan soxta shikoyat yo''q); ota-ona yozadi (nazorat)',
  zz.ins('U_SAL', $q$insert into public.feedback (id, type, uid, "authorName", "authorRole", text) values ('zzfb1', 'shikoyat', 'U_SAL', 'Ota-ona', 'parent', 'ZZ') returning id$q$) || ' | '
  || zz.ins('U_PAR0', $q$insert into public.feedback (id, type, uid, "authorName", text) values ('zzfb2', 'taklif', 'U_PAR0', 'Sinov Ota', 'ZZ') returning id$q$),
  '^ERR 42501 [^|]* \| zzfb2$');
-- H16: rol yana ota-onaga qaytariladi — bekor qilingan bog'lanish JORIY to'g'ri kod bilan qayta ochiladi (avval «ok», lekin 'revoked' qolardi).
select zz.as('U_DIR', $q$update public.users set role = 'parent' where id = 'U_PAR2' returning role$q$) as h16r \gset
select zz.as('U_PAR2', $q$select public.claim_child('IQ-S02', 'M4R8TX')::text$q$) as h16c \gset
select zz.chk('H16 rol qaytgach farzandni to''g''ri kod bilan qayta bog''laydi: bog''lanish faol, o''quvchi ko''rinadi',
  :'h16r' || ' | ' || (zz.j(:'h16c') ->> 'ok') || ' | ' || coalesce((select status from public.child_claims where id = 'U_PAR2__IQ-S02'), '-')
  || ' ' || zz.cnt('U_PAR2', 'public.students'),
  '^parent \| true \| active 1$');
-- H17: sotuvchi hisobining ism-familiyasi / emaili — faqat Direktor (Direktor jurnalida ochishlar boshqa xodim nomiga «yozilmasin»).
select zz.as('U_SAL', $q$with u as (update public.users set name = 'Sinov Sotuvchi Ikki' where id = 'U_SAL' returning 1) select count(*)::text from u$q$) || ' | '
  || zz.as('U_SAL', $q$with u as (update public.users set email = 'zz@example.org' where id = 'U_SAL' returning 1) select count(*)::text from u$q$) || ' | '
  || zz.as('U_DIR', $q$with u as (update public.users set name = 'Sinov Sotuvchi Yangi' where id = 'U_SAL' returning 1) select count(*)::text from u$q$) || ' | '
  || zz.as('U_PAR0', $q$with u as (update public.users set name = 'Sinov Ota Yangi' where id = 'U_PAR0' returning 1) select count(*)::text from u$q$) as h17 \gset
select zz.chk('H17 sotuvchi o''z ismi / emailini o''zgartira olmaydi (42501); Direktor o''zgartiradi; boshqa rol — avvalgidek o''zinikini',
  :'h17' || ' | ' || (select name || ' ' || email from public.users where id = 'U_SAL'),
  '^ERR 42501 [^|]* \| ERR 42501 [^|]* \| 1 \| 1 \| Sinov Sotuvchi Yangi s@example.org$');
select zz.chk('HX6 sotuvchi faqat firstName / lastName ni ham o''zgartira olmaydi (42501)',
  zz.as('U_SAL', $q$with u as (update public.users set "firstName" = 'Boshqa' where id = 'U_SAL' returning 1) select count(*)::text from u$q$) || ' | '
  || zz.as('U_SAL', $q$with u as (update public.users set "lastName" = 'Xodim' where id = 'U_SAL' returning 1) select count(*)::text from u$q$),
  '^ERR 42501 [^|]* \| ERR 42501 ');
select zz.chk('HX7 (nazorat) H18 savepointi tashqarisida firstName o''zgarmagan', coalesce((select coalesce("firstName", '<null>') from public.users where id = 'U_SAL'), '-'), '^<null>$');

-- H18–H22 — savepoint ichida (3-mustaqil tekshiruv): oila raqamini tanlash darajalari (to'g'ri raqam, ismli karta, ona raqami ota
--   katagida), bo'lingan komponentda bir xil bitta ismli kartalar, noto'g'ri raqamni ochganda katakdagi izoh matni.
savepoint h18;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('q1','IQ-Q1','Sinov Bola Q1',3,'C','uz','',301), ('q2','IQ-Q2','Sinov Bola Q2',4,'C','uz','',302),
  ('q3','IQ-Q3','Sinov Bola Q3',3,'C','uz','',303), ('q4','IQ-Q4','Sinov Bola Q4',4,'C','uz','',304),
  ('q5','IQ-Q5','Sinov Bola Q5',3,'C','uz','',305), ('q6','IQ-Q6','Sinov Bola Q6',4,'C','uz','',306), ('q7','IQ-Q7','Sinov Bola Q7',5,'C','uz','',307),
  ('q8','IQ-Q8','Sinov Bola Q8',3,'D','uz','',308), ('q9','IQ-Q9','Sinov Bola Q9',4,'D','uz','',309),
  ('q10','IQ-Q10','Sinov Bola Q10',5,'D','uz','',310), ('q11','IQ-Q11','Sinov Bola Q11',6,'D','uz','',311),
  ('q12','IQ-Q12','Sinov Bola Q12',7,'D','uz','',312), ('q13','IQ-Q13','Sinov Bola Q13',3,'E','uz','',313), ('q14','IQ-Q14','Sinov Bola Q14',4,'E','uz','',314),
  ('q15','IQ-Q15','Sinov Bola Q15',5,'E','uz','',315), ('q16','IQ-Q16','Sinov Bola Q16',6,'E','uz','',316), ('q17','IQ-Q17','Sinov Bola Q17',7,'E','uz','',317),
  ('q18','IQ-Q18','Sinov Bola Q18',3,'F','uz','',318), ('q19','IQ-Q19','Sinov Bola Q19',4,'F','uz','',319),
  ('q20','IQ-Q20','Sinov Bola Q20',5,'F','uz','',320), ('q21','IQ-Q21','Sinov Bola Q21',6,'F','uz','',321),
  ('q22','IQ-Q22','Sinov Bola Q22',3,'G','uz','',322), ('q23','IQ-Q23','Sinov Bola Q23',4,'G','uz','',323), ('q24','IQ-Q24','Sinov Bola Q24',5,'G','uz','',324),
  ('q25','IQ-Q25','Sinov Bola Q25',3,'G','uz','',325), ('q26','IQ-Q26','Sinov Bola Q26',4,'G','uz','',326),
  ('q27','IQ-Q27','Sinov Bola Q27',3,'H','uz','',327), ('q28','IQ-Q28','Sinov Bola Q28',4,'H','uz','',328), ('q29','IQ-Q29','Sinov Bola Q29',5,'H','uz','',329),
  ('q30','IQ-Q30','Sinov Bola Q30',3,'H','uz','',330), ('q31','IQ-Q31','Sinov Bola Q31',4,'H','uz','',331),
  ('q32','IQ-Q32','Sinov Bola Q32',3,'J','uz','',332), ('q33','IQ-Q33','Sinov Bola Q33',4,'J','uz','',333), ('q34','IQ-Q34','Sinov Bola Q34',5,'J','uz','',334),
  ('q35','IQ-Q35','Sinov Bola Q35',6,'J','uz','',335);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('q1','Sinov Ota Nol','Sinov Ona Nol','0','+998 00 888 00 01'),                          -- H18: ota ismi yozilgan kartada «0»,
  ('q2',null,'Sinov Ona Nol','+998 00 777 00 01','+998 00 888 00 01'),                      --      to'g'ri ota raqami — ota ismisiz kartada
  ('q13','Sinov Ota Nolb','Sinov Ona Nolb','+998 00 777 00 06','0'),                         --      ona uchun ham: ona ismi yozilgan kartada «0»,
  ('q14','Sinov Ota Nolb',null,'+998 00 777 00 06','+998 00 888 00 07'),                     --      to'g'ri ona raqami — ona ismisiz kartada
  ('q3',null,'Sinov Ona Almash','+998 00 777 00 02','+998 00 888 00 02'),                   -- H19: raqamlar almashib yozilgan, ota ismi yo'q
  ('q4',null,'Sinov Ona Almash','+998 00 888 00 02','+998 00 777 00 02'),
  ('q5','Sinov Ota Sardor','Sinov Ona Malika','+998 00 888 00 03',null),                    -- H20: ota ismi bor kartalarda «ota telefoni» —
  ('q6','Sinov Ota Sardor','Sinov Ona Malika','+998 00 888 00 03',null),                    --      ona raqami; uchinchi kartada ikkalasi to'g'ri
  ('q7','Sinov Ota Sardor','Sinov Ona Malika','+998 00 777 00 03','+998 00 888 00 03'),
  ('q18','Sinov Ota Upsilon','Sinov Ona Upsilon','+998 00 999 00 11','+998 00 888 00 11'),   --      ikki karta: ota raqami onanikidan keyin
  ('q19','Sinov Ota Upsilon','Sinov Ona Upsilon','+998 00 888 00 11',null),                  --      saralanadi (teng ovozda ham to'g'ri)
  ('q20','Sinov Ota Umumiy','Sinov Ona Umumiy','+998 00 888 00 12','+998 00 888 00 12'),     --      oilaning umumiy raqami ikkala katakda,
  ('q21','Sinov Ota Umumiy','Sinov Ona Umumiy','+998 00 777 00 12','+998 00 888 00 12'),     --      boshqa kartada otaning o'z raqami
  ('q8','Sinov Ota Lambda','Sinov Ona Nilufar','+998 00 777 00 04','+998 00 888 00 04'),    -- H21: bir ota — ikki ona, «ko'prik» kartalar
  ('q9','Sinov Ota Lambda',null,'+998 00 777 00 04',null),                                  --      (q9, q10) — ismi va raqami bir xil
  ('q10','Sinov Ota Lambda',null,'+998 00 777 00 04',null),
  ('q11','Sinov Ota Lambda','Sinov Ona Sevara','+998 00 777 00 04','+998 00 999 00 04'),
  ('q12','Sinov Ota Izoh','Sinov Ona Izoh','+998 00 777 00 05, 3-guruh','+998 00 888 00 05, +998 00 888 00 06 (ona ishda, faqat kechqurun)'),  -- H22
  ('q15',null,'Sinov Ona Zet','+998 00 888 00 10','+998 00 888 00 10'),                     -- H24: ona raqami ikkala katakda, ota ismi yo'q
  ('q16','Sinov Ota Vee','Sinov Ona Vee','+998 00 777 00 08, +998 00 777 00 09','+998 00 888 00 08'),   -- H24: ismli kartada ikki raqamli
  ('q17',null,'Sinov Ona Vee','+998 00 999 00 08','+998 00 888 00 08'),                      --      katak, ota ismisiz kartada bitta raqam
  ('q22','Sinov Ota Zanjir','Sinov Ona Zanjir','+998 00 222 00 42',null),                     -- HX1: zanjir (union-find yakuniy siqish)
  ('q23','Sinov Ota Zanjir',null,'+998 00 111 00 41',null),
  ('q24','Sinov Ota Zanjir','Sinov Ona Zanjir','+998 00 111 00 41','+998 00 222 00 42'),
  ('q25','Sinov Ota Daraja','Sinov Ona Daraja','+998 00 888 00 43','+998 00 888 00 43'),       -- HX2: fpt 2-daraja (ota ismisiz, ona raqami emas) > 3-daraja
  ('q26',null,'Sinov Ona Daraja','+998 00 777 00 43','+998 00 888 00 43'),
  ('q27','Sinov Ota Chastota','Sinov Ona Chastota','+998 00 777 00 44','+998 00 888 00 44'),   -- HX3: ona raqami — eng ko'p uchragani
  ('q28','Sinov Ota Chastota','Sinov Ona Chastota','+998 00 777 00 44','+998 00 888 00 44'),
  ('q29','Sinov Ota Chastota','Sinov Ona Chastota','+998 00 777 00 44','+998 00 666 00 44'),
  ('q30','Sinov Ota Ikkiraqam','Sinov Ona Ikkiraqam','+998 00 777 00 45','+998 00 888 00 45, +998 00 888 00 46'),  -- HX3: mok (>15)
  ('q31','Sinov Ota Ikkiraqam',null,'+998 00 777 00 45','+998 00 999 00 45'),
  ('q32','Sinov Ota Yozuv',null,'12 34 567','+998 00 888 00 47'),                             -- HX4: 7 raqamli shahar raqami (kodsiz) — niqob
  ('q33','Sinov Ota Yozuv',null,'12 34 567','+998 00 888 00 47'),
  ('q34','Sinov Ota Yozuv',null,'1234567','+998 00 888 00 47'),
  ('q35','Sinov Ota Bosh',null,'+998 00 777 00 48  uy 12',null);                              -- HX4: ikki bo'sh joy bo'yicha bo'linadi
set local session_replication_role = origin;
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Nol'))) as h18_rv \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Nolb'))) as h18b_rv \gset
select coalesce(zz.list('U_SAL', $a$'almash'$a$) ->> 'total', '<NULL>') as h19_n \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ona Almash'))) as h19_rv \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Sardor'))) as h20_rv \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Upsilon'))) as h20u_rv \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Umumiy'))) as h20c_rv \gset
select coalesce(zz.list('U_SAL', $a$'lambda'$a$)::text, '<NULL>') as h21_list \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Izoh'))) as h22_rv \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ona Zet'))) as h24z_rv \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Vee'))) as h24v_rv \gset
select coalesce(zz.list('U_SAL') ->> 'total', '<NULL>') || ' ' || coalesce(zz.list('U_SAL', $a$'zanjir'$a$)::text, '<NULL>') as hx1 \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Daraja'))) as hx2 \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Chastota'))) as hx3a \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Ikkiraqam'))) as hx3b \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Yozuv'))) as hx4a \gset
select zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.key('Sinov Ota Bosh'))) as hx4b \gset
rollback to savepoint h18;
select zz.chk('H18 ota / ona ismi yozilgan kartadagi «0» boshqa kartadagi to''g''ri raqamni yashirmaydi (ota ham, ona ham)',
  coalesce((zz.j(:'h18_rv') #>> '{father,name}') || ' ' || (zz.j(:'h18_rv') #>> '{father,phone}') || ' ' || (zz.j(:'h18_rv') #>> '{father,valid}') || ' '
  || (zz.j(:'h18_rv') #>> '{mother,phone}'), left(:'h18_rv', 120)) || ' | '
  || coalesce((zz.j(:'h18b_rv') #>> '{mother,name}') || ' ' || (zz.j(:'h18b_rv') #>> '{mother,phone}') || ' ' || (zz.j(:'h18b_rv') #>> '{mother,valid}'), left(:'h18b_rv', 120)),
  '^Sinov Ota Nol \+998007770001 true \+998008880001 \| Sinov Ona Nolb \+998008880007 true$');
select zz.chk('H19 aka-uka kartalarida raqamlar almashib yozilgan, ota ismi yo''q — bitta oila, ikkala raqam ham chiqadi (biri yo''qolmaydi)',
  :'h19_n' || ' | ' || coalesce(coalesce(zz.j(:'h19_rv') #>> '{father,phone}', '-') || ' ' || coalesce(zz.j(:'h19_rv') #>> '{mother,phone}', '-'), left(:'h19_rv', 120)),
  '^1 \| \+998008880002 \+998007770002$');
select zz.chk('H20 ota ismi yozilgan kartalarda «ota telefoni»ga ona raqami yozilgan bo''lsa ham — ota o''z raqami bilan, ona o''zinikiga (raqamlar tartibidan qat''i nazar; umumiy oila raqami — onada)',
  coalesce((zz.j(:'h20_rv') #>> '{father,phone}') || ' ' || (zz.j(:'h20_rv') #>> '{mother,phone}'), left(:'h20_rv', 120)) || ' | '
  || coalesce((zz.j(:'h20u_rv') #>> '{father,phone}') || ' ' || (zz.j(:'h20u_rv') #>> '{mother,phone}'), left(:'h20u_rv', 120)) || ' | '
  || coalesce((zz.j(:'h20c_rv') #>> '{father,phone}') || ' ' || (zz.j(:'h20c_rv') #>> '{mother,phone}'), left(:'h20c_rv', 120)),
  '^\+998007770003 \+998008880003 \| \+998009990011 \+998008880011 \| \+998007770012 \+998008880012$');
select zz.chk('H21 bo''lingan komponentda bir xil bitta ismli kartalar (ismi va raqamlari bir xil) — bitta qator (3 qator, takror yo''q)',
  (zz.j(:'h21_list') ->> 'total') || ' | ' || coalesce((select string_agg(coalesce(r -> 'mother' ->> 'name', '-'), ', ' order by coalesce(r -> 'mother' ->> 'name', '-'))
                                                        from jsonb_array_elements(zz.j(:'h21_list') -> 'rows') r), '-'),
  '^3 \| -, Sinov Ona Nilufar, Sinov Ona Sevara$');
select zz.chk('H22 noto''g''ri raqam ochilganda — katakdan faqat raqamga o''xshagan qismlar (izoh matni va undagi raqam bo''laklari sotuvchiga chiqmaydi)',
  coalesce((zz.j(:'h22_rv') #>> '{mother,phone}') || ' | ' || (zz.j(:'h22_rv') #>> '{mother,valid}') || ' | ' || (zz.j(:'h22_rv') #>> '{father,phone}'), left(:'h22_rv', 120)),
  '^\+998 00 888 00 05, \+998 00 888 00 06 \| false \| \+998 00 777 00 05$');
-- H23 — savepoint ichida: hisob «Sotuvchi»dan ota-onaga o'tkazildi va ismini o'zgartirdi (endi mumkin), keyin Direktor hisobni o'chirdi —
--   Direktor jurnali o'tgan ochishlarni baribir ochish paytidagi nom bilan ko'rsatadi (boshqa xodim nomiga «yozilmaydi»), hozirgi nom — alohida.
savepoint h23;
select zz.as('U_DIR', $q$update public.users set role = 'parent' where id = 'U_SAL' returning role$q$) || ' | '
  || zz.as('U_SAL', $q$with u as (update public.users set name = 'Sinov Boshqa Xodim' where id = 'U_SAL' returning 1) select count(*)::text from u$q$) as h23 \gset
select zz.as('U_DIR', 'select public.sales_log(30)::text') as h23_log \gset
select zz.q($q$with d as (delete from public.users where id = 'U_SAL' returning 1) select count(*)::text from d$q$) as h23_del \gset
select zz.as('U_DIR', 'select public.sales_log(30)::text') as h23_log2 \gset
rollback to savepoint h23;
select zz.chk('H23 rol o''zgargach o''z ismini o''zgartirgan / o''chirilgan hisob: jurnalda o''tgan ochishlar — ochish paytidagi nom bilan, hozirgi nom alohida',
  :'h23' || ' | '
  || coalesce((select string_agg(distinct d ->> 'name', ',') from jsonb_array_elements(zz.j(:'h23_log') -> 'days') d where d ->> 'uid' = 'U_SAL'), '-') || ' / '
  || coalesce((select string_agg(distinct r ->> 'name', ',') from jsonb_array_elements(zz.j(:'h23_log') -> 'recent') r where r ->> 'uid' = 'U_SAL' and r ->> 'father' is not null), '-') || ' / '
  || coalesce((select string_agg(distinct r ->> 'nameNow', ',') from jsonb_array_elements(zz.j(:'h23_log') -> 'recent') r where r ->> 'uid' = 'U_SAL' and r ->> 'father' is not null), '-')
  || ' | ' || :'h23_del' || ' | '
  || coalesce((select string_agg(distinct r ->> 'name', ',') from jsonb_array_elements(zz.j(:'h23_log2') -> 'recent') r where r ->> 'uid' = 'U_SAL' and r ->> 'father' is not null), '-'),
  '^parent \| 1 \| Sinov Sotuvchi / Sinov Sotuvchi / Sinov Boshqa Xodim \| 1 \| Sinov Sotuvchi$');
select zz.chk('HX5 jurnal kunlari: hozirgi nom (nameNow) ham',
  coalesce((select string_agg(distinct d ->> 'nameNow', ',') from jsonb_array_elements(zz.j(:'h23_log') -> 'days') d where d ->> 'uid' = 'U_SAL'), '-'), '^Sinov Boshqa Xodim$');
select zz.chk('H24 ona raqami ikkala katakda, ota ismi yo''q — otaniki bo''lib takrorlanmaydi; ismli kartadagi ikki raqamli «ota telefoni» — ota ismisiz kartadagi raqamdan ustun',
  coalesce(coalesce(zz.j(:'h24z_rv') ->> 'father', 'null') || ' ' || (zz.j(:'h24z_rv') #>> '{mother,phone}'), left(:'h24z_rv', 120)) || ' | '
  || coalesce((zz.j(:'h24v_rv') #>> '{father,name}') || ' ' || (zz.j(:'h24v_rv') #>> '{father,phone}') || ' ' || (zz.j(:'h24v_rv') #>> '{mother,phone}'), left(:'h24v_rv', 120)),
  '^null \+998008880010 \| Sinov Ota Vee \+998 00 777 00 08, \+998 00 777 00 09 \+998008880008$');
select zz.chk('HX1 zanjir: oxirgi qirra ildizni boshqa ildizga ulasa ham — bitta oila (savepointda jami 25; «zanjir» — 1 qator, ota 41, ona 42)',
  split_part(:'hx1', ' ', 1) || ' | ' || (zz.j(substr(:'hx1', strpos(:'hx1', ' ') + 1)) ->> 'total') || ' | '
  || coalesce((select (r -> 'father' ->> 'phone') || ' ' || (r -> 'mother' ->> 'phone') from jsonb_array_elements(zz.j(substr(:'hx1', strpos(:'hx1', ' ') + 1)) -> 'rows') r limit 1), '-'),
  '^25 \| 1 \| \+998 00 \*\*\* \*\* 41 \+998 00 \*\*\* \*\* 42$');
select zz.chk('HX2 fpt: ota ismisiz kartadagi (ona raqami emas) raqam — ota ismli kartadagi oilaning umumiy raqamidan ustun',
  coalesce((zz.j(:'hx2') #>> '{father,phone}') || ' ' || (zz.j(:'hx2') #>> '{mother,phone}'), left(:'hx2', 120)), '^\+998007770043 \+998008880043$');
select zz.chk('HX3 ona raqami: eng ko''p uchragani; ona ismli kartadagi ikki raqamli katak — ona ismisiz kartadagi bitta raqamdan ustun',
  coalesce(zz.j(:'hx3a') #>> '{mother,phone}', left(:'hx3a', 120)) || ' | ' || coalesce(zz.j(:'hx3b') #>> '{mother,phone}', left(:'hx3b', 120)),
  '^\+998008880044 \| \+998 00 888 00 45, \+998 00 888 00 46$');
select zz.chk('HX4 7 raqamli shahar raqami (kodsiz) — qo''ng''iroq qilib bo''lmaydi: niqob (raqam ochilmaydi); ikki bo''sh joydan keyingi izoh raqami chiqmaydi',
  coalesce(zz.j(:'hx4a') #>> '{father,phone}', left(:'hx4a', 120)) || ' ' || coalesce(zz.j(:'hx4a') #>> '{father,valid}', '-') || ' | '
  || coalesce(zz.j(:'hx4b') #>> '{father,phone}', left(:'hx4b', 120)),
  '^\*\*\* \*\* 67 false \| \+998 00 777 00 48$');

-- H25 — savepoint ichida: bitta umumiy raqamli 500 ta ismli karta (bir xil ota ismi, ona ismi yo'q) va bitta umumiy raqamli 500 ta
--   «-» karta (ismsiz) — har biri bitta oila. Oilalar ro'yxati chiziqli vaqtda (union-find): avvalgi juftlik + to'liq tutashuv usuli
--   kub vaqt oldi (400 kartada ~8 s, 500 da ~16 s, 1000 da ~2 daqiqa — sotuvchi ro'yxati va Direktor jurnali ochilmay qolardi).
savepoint h25;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'zb' || g, 'IQ-ZB' || g, 'Sinov Bola ZB' || g, 1 + g % 11, 'Z', 'uz', '', 1000 + g from generate_series(1, 1000) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'zb' || g, case when g <= 500 then 'Sinov Ota Umumiy' else '-' end, null,
         case when g <= 500 then '+998 00 555 55 55' else '+998 00 555 55 56' end, null from generate_series(1, 1000) g;
set local session_replication_role = origin;
set local statement_timeout = '90s';
select zz.q($q$select (select count(*) from app.sales_families(false) f where f.f_phone = '998005555555' and f.f_name = 'Sinov Ota Umumiy')::text || ' '
                   || (select count(*) from app.sales_families(false) f where f.f_phone = '998005555556' and f.f_name is null)::text || ' '
                   || (extract(epoch from clock_timestamp() - t0) * 1000 < 5000)::text
                from (select clock_timestamp() as t0) z$q$) as h25 \gset
rollback to savepoint h25;
select zz.chk('H25 bitta umumiy raqamli 500 ta ismli karta — bitta oila; 500 ta «-» karta (ismsiz, raqamlari bir xil) — bitta oila; ro''yxat tez (5 s dan kam)',
  :'h25', '^1 1 true$');

-- H26–H29 (4-mustaqil tekshiruv): oilani nom bo'yicha qidiruv orqali topib ochish (birinchi sahifaga bog'liq emas).
create or replace function zz.rk(p_name text) returns text language sql as $$
  select r ->> 'k' from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal(p_name)) -> 'rows', '[]'::jsonb)) r
   where r -> 'father' ->> 'name' = p_name or r -> 'mother' ->> 'name' = p_name limit 1 $$;
create or replace function zz.rv(p_name text) returns jsonb language sql as $$
  select zz.j(zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', zz.rk(p_name)))) $$;

-- H26 — savepoint ichida: «-» / «—» — ism emas. Umumiy maktab raqami + ota ismi «-», har kartada boshqa ona raqami — uch oila (hech
--   bir ona yo'qolmaydi; avval «-» ism hisoblanib, uchala karta bitta qatorga qo'shilardi); aka-uka kartalari: birida ota ismi «-» —
--   bitta oila, ota ismi haqiqiy ismdan (avval «-» bilan «Akmal» zid ism hisoblanib, ikki qator chiqardi).
savepoint h26;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('zp1','IQ-ZP1','Sinov Bola ZP1',5,'A','uz','',2001), ('zp2','IQ-ZP2','Sinov Bola ZP2',6,'A','uz','',2002), ('zp3','IQ-ZP3','Sinov Bola ZP3',7,'A','uz','',2003),
  ('zs1','IQ-ZS1','Sinov Bola ZS1',5,'B','uz','',2004), ('zs2','IQ-ZS2','Sinov Bola ZS2',8,'B','uz','',2005);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('zp1','-',null,'+998 00 555 55 55','+998 00 111 70 01'),
  ('zp2','-',null,'+998 00 555 55 55','+998 00 111 70 02'),
  ('zp3','—',null,'+998 00 555 55 55','+998 00 111 70 03'),
  ('zs1','Sinov Ota Akmal','Sinov Ona Zarina','+998 00 111 70 11','+998 00 111 70 12'),
  ('zs2','-','Sinov Ona Zarina','+998 00 111 70 11','+998 00 111 70 12');
set local session_replication_role = origin;
select zz.q($q$select string_agg(coalesce(f.f_name, '0') || ' ' || f.f_phone || ' ' || coalesce(f.m_name, '0') || ' ' || f.m_phone, ', ' order by f.m_phone)
                from app.sales_families(false) f where f.f_phone in ('998005555555', '998001117011')$q$) as h26 \gset
rollback to savepoint h26;
select zz.chk('H26 «-» ism emas: umumiy maktab raqami + ota ismi «-» — har ona alohida (3 qator); aka-uka (birida ota «-») — bitta oila',
  :'h26', '^0 998005555555 0 998001117001, 0 998005555555 0 998001117002, 0 998005555555 0 998001117003, Sinov Ota Akmal 998001117011 Sinov Ona Zarina 998001117012$');

-- H27 — savepoint ichida: ochilgan katakdan faqat qo'ng'iroq qilib bo'ladigan qismlar: pasport / karta raqami, sana, JSHSHIR (14 raqam,
--   «+»siz — avval «to'g'ri xorijiy raqam» bo'lib chiqardi), izohdagi raqamlar — chiqmaydi; bunday qism bo'lmasa — niqob (avval katakdagi
--   barcha raqamlar qo'shilib chiqardi). Bir katakdagi bir nechta to'g'ri raqam, 9 xonali mahalliy raqam va «+» bilan yozilgan xorijiy
--   raqam — avvalgidek.
savepoint h27;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('r1','IQ-R1','Sinov Bola R1',5,'K','uz','',2101), ('r2','IQ-R2','Sinov Bola R2',6,'K','uz','',2102), ('r3','IQ-R3','Sinov Bola R3',7,'K','uz','',2103),
  ('r4','IQ-R4','Sinov Bola R4',8,'K','uz','',2104), ('r5','IQ-R5','Sinov Bola R5',9,'K','uz','',2105);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('r1','Sinov Ota Pasport','Sinov Ona Pasport','+998 00 111 00 61, pasport AA 1234567','tug''ilgan 31.12.2015, karta 8600 1234 5678 9012'),
  ('r2','Sinov Ota Guruh',null,'3-guruh, 2020 yil, 15-uy',null),
  ('r3',null,'Sinov Ona Jshr',null,'JSHSHIR 31203456789012'),
  ('r4','Sinov Ota Ikki','Sinov Ona Ikki','+44 7700 900036, +998 00 444 00 65','01 234 56 78, 02 345 67 89'),
  ('r5','Sinov Ota Xorijiy',null,'+44 7700 900037',null);
set local session_replication_role = origin;
select zz.rv('Sinov Ota Pasport')::text as h27a, zz.rv('Sinov Ota Guruh')::text as h27b, zz.rv('Sinov Ona Jshr')::text as h27c,
       zz.rv('Sinov Ota Ikki')::text as h27d, zz.rv('Sinov Ota Xorijiy')::text as h27e \gset
rollback to savepoint h27;
select zz.chk('H27 ochilgan katak: faqat qo''ng''iroq qilib bo''ladigan qismlar (pasport / karta / sana / JSHSHIR / izoh raqami — yo''q, bo''lmasa niqob); bir nechta to''g''ri raqam, mahalliy va «+» xorijiy raqam — avvalgidek',
  coalesce((zz.j(:'h27a') #>> '{father,phone}') || ' / ' || (zz.j(:'h27a') #>> '{mother,phone}') || ' ' || (zz.j(:'h27a') #>> '{mother,valid}'), left(:'h27a', 120)) || ' | '
  || coalesce((zz.j(:'h27b') #>> '{father,phone}') || ' ' || (zz.j(:'h27b') #>> '{father,valid}'), left(:'h27b', 120)) || ' | '
  || coalesce((zz.j(:'h27c') #>> '{mother,phone}') || ' ' || (zz.j(:'h27c') #>> '{mother,valid}'), left(:'h27c', 120)) || ' | '
  || coalesce((zz.j(:'h27d') #>> '{father,phone}') || ' / ' || (zz.j(:'h27d') #>> '{mother,phone}'), left(:'h27d', 120)) || ' | '
  || coalesce((zz.j(:'h27e') #>> '{father,phone}') || ' ' || (zz.j(:'h27e') #>> '{father,valid}'), left(:'h27e', 120)),
  '^\+998 00 111 00 61 / \*\*\* \*\* 12 false \| \*\*\* \*\* 15 false \| \*\*\* \*\* 12 false \| \+44 7700 900036, \+998 00 444 00 65 / 01 234 56 78, 02 345 67 89 \| \+447700900037 true$');

-- H28 — savepoint ichida: ism katagiga ism bilan birga yozilgan telefon / izoh sotuvchiga chiqmaydi — ro'yxatda (niqoblangan, jurnalsiz),
--   qidiruvda va ochishda faqat ism; ism katagidagi raqam bo'yicha qidiruv hech narsa topmaydi; ro'yxat jurnalga yozilmaydi.
savepoint h28;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('n1','IQ-N1','Sinov Bola N1',5,'L','uz','',2201);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('n1','Sinov Ota Raqamli (tel 00 765 43 21, Rossiyada)','Sinov Ona Raqamli 00-765-43-21 [astma]','+998 00 111 00 71','+998 00 111 00 72');
set local session_replication_role = origin;
select (select count(*) from public.sales_contact_log)::text as h28_log0 \gset
select zz.list('U_SAL', quote_literal('Raqamli'))::text as h28_list, zz.list('U_SAL', quote_literal('765'))::text as h28_q \gset
select (select count(*) from public.sales_contact_log)::text as h28_log1 \gset
select zz.rv('Sinov Ota Raqamli')::text as h28_rv \gset
rollback to savepoint h28;
select zz.chk('H28 ism katagidagi telefon / izoh: ro''yxatda, qidiruvda va ochishda faqat ism; raqam bo''yicha qidiruv — 0; ro''yxat jurnalga yozilmaydi',
  coalesce((select (r #>> '{father,name}') || ' / ' || (r #>> '{mother,name}') from jsonb_array_elements(zz.j(:'h28_list') -> 'rows') r limit 1), '-') || ' | '
  || coalesce(zz.j(:'h28_q') ->> 'total', '-') || ' | ' || (:'h28_log1'::int - :'h28_log0'::int)::text || ' | '
  || coalesce((zz.j(:'h28_rv') #>> '{father,name}') || ' / ' || (zz.j(:'h28_rv') #>> '{mother,name}'), left(:'h28_rv', 120)),
  '^Sinov Ota Raqamli / Sinov Ona Raqamli \| 0 \| 0 \| Sinov Ota Raqamli / Sinov Ona Raqamli$');

-- H29 — savepoint ichida: «foydalanib bo'ladigan» katak — sahifa qo'ng'iroq havolasi bera oladigan raqam: karta raqami (16 raqam), JSHSHIR
--   (14 raqam, «+»siz), bitta bo'sh joy bilan yopishgan ikki raqam aka-uka kartasidagi to'g'ri raqamni yashirmaydi (ota ham, ona ham;
--   avval ular «foydalanib bo'ladigan» hisoblanib, satr tartibida to'g'ri raqamdan oldin tushardi); «+» bilan xorijiy raqam — foydalanib bo'ladi.
savepoint h29;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('u1','IQ-U1','Sinov Bola U1',3,'G','uz','',2301), ('u2','IQ-U2','Sinov Bola U2',4,'G','uz','',2302),
  ('u3','IQ-U3','Sinov Bola U3',3,'G','uz','',2303), ('u4','IQ-U4','Sinov Bola U4',4,'G','uz','',2304),
  ('u5','IQ-U5','Sinov Bola U5',3,'G','uz','',2305), ('u6','IQ-U6','Sinov Bola U6',4,'G','uz','',2306),
  ('u7','IQ-U7','Sinov Bola U7',3,'G','uz','',2307), ('u8','IQ-U8','Sinov Bola U8',4,'G','uz','',2308),
  ('u9','IQ-U9','Sinov Bola U9',3,'G','uz','',2309), ('u10','IQ-U10','Sinov Bola U10',4,'G','uz','',2310),
  ('u11','IQ-U11','Sinov Bola U11',3,'G','uz','',2311), ('u12','IQ-U12','Sinov Bola U12',4,'G','uz','',2312);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('u11','Sinov Ota Nolli','Sinov Ona Nolli','0, 01 234 56 78','+998 00 333 00 43'),                     -- kanonik shakli qisqa (8 raqam),
  ('u12',null,'Sinov Ona Nolli','+998 00 444 00 75','+998 00 333 00 43'),                                --   lekin qismi — mahalliy raqam
  ('u1','Sinov Ota Karta','Sinov Ona Karta','8600 1234 5678 9012','+998 00 333 00 03'),                 -- karta raqami (16 raqam)
  ('u2','Sinov Ota Karta','Sinov Ona Karta','+998 00 444 00 04','+998 00 333 00 03'),
  ('u3','Sinov Ota Jshr','Sinov Ona Jshr','31234567890123','+998 00 333 00 13'),                        -- JSHSHIR (14 raqam, «+»siz)
  ('u4','Sinov Ota Jshr','Sinov Ona Jshr','+998 00 444 00 14','+998 00 333 00 13'),
  ('u5','Sinov Ota Bosh','Sinov Ona Bosh','+998 00 111 00 01 +998 00 111 00 02','+998 00 333 00 23'),  -- bitta bo'sh joy: ajratib bo'lmaydi
  ('u6','Sinov Ota Bosh','Sinov Ona Bosh','+998 00 444 00 24','+998 00 333 00 23'),
  ('u7','Sinov Ota Mkarta','Sinov Ona Mkarta','+998 00 777 00 53','8600 1234 5678 9053'),               -- ona katagida karta raqami
  ('u8','Sinov Ota Mkarta','Sinov Ona Mkarta','+998 00 777 00 53','+998 00 888 00 54'),
  ('u9','Sinov Ota Xorij','Sinov Ona Xorij','+44 7700 900038','+998 00 333 00 33'),                     -- «+» bilan xorijiy raqam — foydalanib
  ('u10','Sinov Ota Xorij','Sinov Ona Xorij','31234567890131','+998 00 333 00 33');                     --   bo'ladi (raqib — «44…» dan oldin saralanadi)
set local session_replication_role = origin;
select (zz.rv('Sinov Ota Karta') #>> '{father,phone}') || ' | ' || (zz.rv('Sinov Ota Jshr') #>> '{father,phone}') || ' | '
       || (zz.rv('Sinov Ota Bosh') #>> '{father,phone}') || ' | ' || (zz.rv('Sinov Ona Mkarta') #>> '{mother,phone}') || ' | '
       || (zz.rv('Sinov Ota Xorij') #>> '{father,phone}') || ' | ' || (zz.rv('Sinov Ota Nolli') #>> '{father,phone}') as h29 \gset
rollback to savepoint h29;
select zz.chk('H29 karta raqami / JSHSHIR / bitta bo''sh joy bilan yopishgan ikki raqam aka-uka kartasidagi to''g''ri raqamni yashirmaydi (ota ham, ona ham); «+» bilan xorijiy raqam va «0, <mahalliy raqam>» katagi — foydalanib bo''ladi',
  :'h29', '^\+998004440004 \| \+998004440014 \| \+998004440024 \| \+998008880054 \| \+447700900038 \| 01 234 56 78$');

-- H30–H33, HX8 (5-mustaqil tekshiruv).
-- H30 — savepoint ichida: katakdagi barcha raqamlar qo'shilib chiqmaydi: «+» / 00 bilan xorijiy raqam + raqamli izoh — faqat raqam qismi
--   (avval «+4477009001212» valid:true chiqardi); pasport + uy raqami — telefon emas (avval «+998123456715» havola bo'lardi): ochishda va
--   ro'yxatda faqat oxirgi 2 raqam; aka-uka kartasidagi bunday katak to'g'ri raqamni yashirmaydi; ikki bo'sh joyli bitta raqam — avvalgidek.
savepoint h30;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('v1','IQ-V1','Sinov Bola V1',5,'M','uz','',2401), ('v2','IQ-V2','Sinov Bola V2',5,'M','uz','',2402),
  ('v3','IQ-V3','Sinov Bola V3',6,'M','uz','',2403), ('v4','IQ-V4','Sinov Bola V4',7,'M','uz','',2404),
  ('v5','IQ-V5','Sinov Bola V5',8,'M','uz','',2405), ('v6','IQ-V6','Sinov Bola V6',9,'M','uz','',2406),
  ('v7','IQ-V7','Sinov Bola V7',3,'M','uz','',2407), ('v8','IQ-V8','Sinov Bola V8',4,'M','uz','',2408),
  ('v9','IQ-V9','Sinov Bola V9',5,'M','uz','',2409), ('v10','IQ-V10','Sinov Bola V10',6,'M','uz','',2410);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('v1','Sinov Ota Uy',null,'+44 7700 900121, 2-uy',null),                                     -- xorijiy + izoh raqami
  ('v2','Sinov Ota Nolnol',null,'0044 7700 900122; 3-guruh',null),                            -- 00 bilan xorijiy + izoh
  ('v3','Sinov Ota Pasportli',null,'pasport AA1234567, 15-uy',null),                           -- telefon yo'q: pasport + uy
  ('v4','Sinov Ota Takror','Sinov Ona Takror','+44 7700 900124, 2-uy','+998 00 333 00 24'),     -- aka-uka: ikkitasi izohli,
  ('v5','Sinov Ota Takror','Sinov Ona Takror','+44 7700 900124, 2-uy','+998 00 333 00 24'),     --   bittasi toza katak
  ('v6','Sinov Ota Takror','Sinov Ona Takror','+44 7700 900124','+998 00 333 00 24'),
  ('v7','Sinov Ota Hujjat','Sinov Ona Hujjat','pasport AA0111111, 11-uy','+998 00 333 00 27'),  -- aka-uka: pasport katagi to'g'ri
  ('v8','Sinov Ota Hujjat','Sinov Ona Hujjat','01 234 56 78','+998 00 333 00 27'),              --   raqamni yashirmaydi
  ('v9','Sinov Ota Ikkibosh',null,'+998 00  123 45 67',null),                                  -- ikki bo'sh joyli bitta raqam
  ('v10','Sinov Ota Ikkiqism',null,'+44 7700 900125  2',null);                                 -- ikki bo'sh joydan keyin izoh raqami
set local session_replication_role = origin;
select (zz.rv('Sinov Ota Uy') -> 'father')::text || ' | ' || (zz.rv('Sinov Ota Nolnol') -> 'father')::text || ' | '
       || (zz.rv('Sinov Ota Pasportli') -> 'father')::text || ' | ' || (zz.rv('Sinov Ota Takror') #>> '{father,phone}') || ' | '
       || (zz.rv('Sinov Ota Hujjat') #>> '{father,phone}') || ' | '
       || (zz.rv('Sinov Ota Ikkibosh') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Ikkibosh') #>> '{father,valid}') || ' | '
       || (zz.rv('Sinov Ota Ikkiqism') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Ikkiqism') #>> '{father,valid}') || ' | '
       || coalesce((select string_agg(r #>> '{father,phone}', ', ' order by r #>> '{father,name}')
                      from jsonb_array_elements(zz.list('U_SAL', quote_literal('Sinov Ota')) -> 'rows') r
                     where r #>> '{father,name}' in ('Sinov Ota Pasportli', 'Sinov Ota Takror')), '-') as h30 \gset
rollback to savepoint h30;
select zz.chk('H30 izohli / pasportli katak: katakdagi raqamlar qo''shilib chiqmaydi — faqat raqam qismi yoki niqob (ochishda ham, ro''yxatda ham); aka-uka kartasidagi to''g''ri raqam yashirinmaydi',
  :'h30', '^\{"name": "Sinov Ota Uy", "phone": "\+44 7700 900121", "valid": false\} \| \{"name": "Sinov Ota Nolnol", "phone": "0044 7700 900122", "valid": false\} \| '
       || '\{"name": "Sinov Ota Pasportli", "phone": "\*\*\* \*\* 15", "valid": false\} \| \+44 7700 900124 \| \+998012345678 \| \+998001234567 true \| '
       || '\+44 7700 900125 false \| \*\*\* \*\* 15, \*\*\* \*\* 24$');

-- H31 — savepoint ichida: qator uzilishi (Excel'da Alt+Enter) va TAB — ajratuvchi: katakdagi ikki raqam ham chiqadi (avval niqob
--   chiqardi); keyingi qatordagi JSHSHIR chiqmaydi; ikki qatorga bo'lingan bitta raqam — bitta raqam.
savepoint h31;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('w1','IQ-W1','Sinov Bola W1',5,'M','uz','',2411), ('w2','IQ-W2','Sinov Bola W2',6,'M','uz','',2412),
  ('w3','IQ-W3','Sinov Bola W3',7,'M','uz','',2413), ('w4','IQ-W4','Sinov Bola W4',8,'M','uz','',2414);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('w1','Sinov Ota Qator','Sinov Ona Qator',E'+998 00 100 20 07\n+998 00 100 20 08',E'01 234 56 71\n02 345 67 81'),
  ('w2','Sinov Ota Tabli',null,E'+998 00 100 20 17\t+998 00 100 20 18',null),
  ('w3','Sinov Ota Jqator',null,E'+998 00 100 20 37\n31234567890123',null),
  ('w4','Sinov Ota Bolingan',null,E'+998 00 100\n20 47',null);
set local session_replication_role = origin;
select (zz.rv('Sinov Ota Qator') #>> '{father,phone}') || ' / ' || (zz.rv('Sinov Ota Qator') #>> '{mother,phone}') || ' | '
       || (zz.rv('Sinov Ota Tabli') #>> '{father,phone}') || ' | ' || (zz.rv('Sinov Ota Jqator') #>> '{father,phone}') || ' | '
       || (zz.rv('Sinov Ota Bolingan') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Bolingan') #>> '{father,valid}') as h31 \gset
rollback to savepoint h31;
select zz.chk('H31 qator uzilishi / TAB — ajratuvchi: ikki raqam ham chiqadi, keyingi qatordagi JSHSHIR chiqmaydi, ikki qatorga bo''lingan bitta raqam — bitta',
  :'h31', '^\+998 00 100 20 07, \+998 00 100 20 08 / 01 234 56 71, 02 345 67 81 \| \+998 00 100 20 17, \+998 00 100 20 18 \| \+998 00 100 20 37 \| \+998001002047 true$');

-- H32 — savepoint ichida: oila raqami bir xil, lekin aka-uka kartalarida turlicha yozilgan (biri «+» bilan, qolganlari «+»siz): ochishda
--   foydalanib bo'ladigan yozuv ustun — ko'pchilik «+»siz yozgan bo'lsa ham raqam niqoblanmaydi (ota ham, ona ham; teng ovozda oldin
--   saralanadigan «(44) …» yozuvi ham).
savepoint h32;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('x1','IQ-X1','Sinov Bola X1',3,'M','uz','',2421), ('x2','IQ-X2','Sinov Bola X2',4,'M','uz','',2422), ('x3','IQ-X3','Sinov Bola X3',5,'M','uz','',2423),
  ('x4','IQ-X4','Sinov Bola X4',3,'M','uz','',2424), ('x5','IQ-X5','Sinov Bola X5',4,'M','uz','',2425), ('x6','IQ-X6','Sinov Bola X6',5,'M','uz','',2426),
  ('x7','IQ-X7','Sinov Bola X7',3,'M','uz','',2427), ('x8','IQ-X8','Sinov Bola X8',4,'M','uz','',2428);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('x1','Sinov Ota Uchkarta',null,'+44 7700 900120',null),
  ('x2','Sinov Ota Uchkarta',null,'447700900120',null),
  ('x3','Sinov Ota Uchkarta',null,'447700900120',null),
  ('x4','Sinov Ota Onauch','Sinov Ona Onauch','+998 00 111 00 91','+44 7700 900121'),
  ('x5','Sinov Ota Onauch','Sinov Ona Onauch','+998 00 111 00 91','447700900121'),
  ('x6','Sinov Ota Onauch','Sinov Ona Onauch','+998 00 111 00 91','447700900121'),
  ('x7','Sinov Ota Qavs',null,'+44 7700 900122',null),
  ('x8','Sinov Ota Qavs',null,'(44) 7700 900122',null);
set local session_replication_role = origin;
select coalesce((zz.rv('Sinov Ota Uchkarta') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Uchkarta') #>> '{father,valid}') || ' | '
       || (zz.rv('Sinov Ona Onauch') #>> '{mother,phone}') || ' ' || (zz.rv('Sinov Ona Onauch') #>> '{mother,valid}') || ' | '
       || (zz.rv('Sinov Ota Qavs') #>> '{father,phone}'), '<NULL>') as h32 \gset
rollback to savepoint h32;
select zz.chk('H32 bir xil raqam aka-uka kartalarida «+» bilan va «+»siz yozilgan (ko''pchiligi «+»siz) — ochishda «+» yozuv ustun, raqam niqoblanmaydi (ota ham, ona ham; teng ovozda ham)',
  :'h32', '^\+447700900120 true \| \+447700900121 true \| \+447700900122$');

-- H33 — savepoint ichida: ism o'rniga yozilgan so'z («yo'q», «Нет», «- (vafot etgan)») — ism emas: maktab raqamini bo'lishgan begona
--   oilalar qo'shilmaydi; ism katagidagi qavsli izoh kalitni bo'lmaydi; otasiz (ota ismi «-») kartaning «ota telefoni»dagi umumiy raqam
--   va bir xil ona ismi — boshqa onaning raqami bor kartani begona oilaga ham, shunday boshqa kartaga ham qo'shmaydi; aka-uka (ota ismisiz
--   kartada faqat ota raqami) — bitta oila.
savepoint h33;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('y1','IQ-Y1','Sinov Bola Y1',5,'M','uz','',2431), ('y2','IQ-Y2','Sinov Bola Y2',6,'M','uz','',2432), ('y3','IQ-Y3','Sinov Bola Y3',7,'M','uz','',2433),
  ('y4','IQ-Y4','Sinov Bola Y4',5,'M','uz','',2434), ('y5','IQ-Y5','Sinov Bola Y5',6,'M','uz','',2435),
  ('y6','IQ-Y6','Sinov Bola Y6',5,'M','uz','',2436), ('y7','IQ-Y7','Sinov Bola Y7',6,'M','uz','',2437),
  ('y8','IQ-Y8','Sinov Bola Y8',5,'M','uz','',2438), ('y9','IQ-Y9','Sinov Bola Y9',6,'M','uz','',2439),
  ('y10','IQ-Y10','Sinov Bola Y10',5,'M','uz','',2440), ('y11','IQ-Y11','Sinov Bola Y11',6,'M','uz','',2441),
  ('y12','IQ-Y12','Sinov Bola Y12',5,'M','uz','',2442), ('y13','IQ-Y13','Sinov Bola Y13',6,'M','uz','',2443);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('y1','yo''q',null,'+998 00 555 00 31','+998 00 310 31 01'),
  ('y2','yoq','-','+998 00 555 00 31','+998 00 310 31 02'),
  ('y3','Нет','','+998 00 555 00 31','+998 00 310 31 03'),
  ('y4','- (vafot etgan)',null,'+998 00 555 00 41','+998 00 310 41 01'),
  ('y5','- (vafot etgan)',null,'+998 00 555 00 41','+998 00 310 41 02'),
  ('y6','Sinov Ota Izohli (ota)','Sinov Ona Izohli','+998 00 100 07 01','+998 00 100 07 02'),
  ('y7','Sinov Ota Izohli','Sinov Ona Izohli','+998 00 100 07 01','+998 00 100 07 02'),
  ('y8','-','Sinov Ona Zarina','+998 00 555 00 09','+998 00 100 20 09'),
  ('y9','Sinov Ota Akmal','Sinov Ona Zarina','+998 00 555 00 09','+998 00 100 20 10'),
  ('y10','Sinov Ota Bek','Sinov Ona Lola','+998 00 120 00 01','+998 00 120 00 02'),
  ('y11',null,'Sinov Ona Lola','+998 00 120 00 01',null),
  ('y12','-','Sinov Ona Dilnoza','+998 00 555 00 51','+998 00 310 51 01'),
  ('y13','-','Sinov Ona Dilnoza','+998 00 555 00 51','+998 00 310 51 02');
set local session_replication_role = origin;
select zz.q($q$select string_agg(coalesce(f.f_name, '0') || ' ' || f.f_phone || ' ' || coalesce(f.m_name, '0') || ' ' || f.m_phone, ', ' order by f.f_phone, f.m_phone)
                from app.sales_families(false) f
               where f.f_phone in ('998005550031', '998005550041', '998001000701', '998005550009', '998001200001', '998005550051')$q$) as h33 \gset
rollback to savepoint h33;
select zz.chk('H33 ism o''rniga yozilgan so''z — ism emas; qavsli izoh kalitni bo''lmaydi; otasiz kartaning «ota telefoni»dagi umumiy raqam boshqa onalarni qo''shmaydi; aka-uka — bitta',
  :'h33', '^Sinov Ota Izohli 998001000701 Sinov Ona Izohli 998001000702, Sinov Ota Bek 998001200001 Sinov Ona Lola 998001200002, '
       || '0 998005550009 Sinov Ona Zarina 998001002009, Sinov Ota Akmal 998005550009 Sinov Ona Zarina 998001002010, '
       || '0 998005550031 0 998003103101, 0 998005550031 0 998003103102, 0 998005550031 0 998003103103, 0 998005550041 0 998003104101, '
       || '0 998005550041 0 998003104102, 0 998005550051 Sinov Ona Dilnoza 998003105101, 0 998005550051 Sinov Ona Dilnoza 998003105102$');

-- HX8 — savepoint ichida: «+» bilan xorijiy raqam «44…» dan oldin saralanadigan JSHSHIRdan ustun; asl yozuv — foydalanib bo'ladiganlardan
--   eng ko'p uchragani; 00 bilan yozilgan xorijiy raqam — qo'ng'iroq qilib bo'ladi; ismdagi alohida «—» olib tashlanadi, ism 60 belgigacha.
savepoint hx8;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('m1','IQ-M1','Sinov Bola M1',3,'M','uz','',2451), ('m2','IQ-M2','Sinov Bola M2',4,'M','uz','',2452),
  ('m3','IQ-M3','Sinov Bola M3',3,'M','uz','',2453), ('m4','IQ-M4','Sinov Bola M4',4,'M','uz','',2454), ('m5','IQ-M5','Sinov Bola M5',5,'M','uz','',2455),
  ('m6','IQ-M6','Sinov Bola M6',3,'M','uz','',2456), ('m7','IQ-M7','Sinov Bola M7',4,'M','uz','',2457);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('m1','Sinov Ota Xorijb','Sinov Ona Xorijb','+44 7700 900039','+998 00 333 00 34'),
  ('m2','Sinov Ota Xorijb','Sinov Ona Xorijb','31234567890139','+998 00 333 00 34'),
  ('m3','Sinov Ota Yozuvb',null,'+44 7700 900040',null), ('m4','Sinov Ota Yozuvb',null,'+44 7700 900040',null),
  ('m5','Sinov Ota Yozuvb',null,'447700900040',null),
  ('m6','Sinov Ota Nolnolb',null,'0044 7700 900041',null),
  ('m7','Sinov Ota — Tire Uzunism Uzunism Uzunism Uzunism Uzunism Uzunism Uzunism Uzunism',null,'+998 00 333 00 35',null);
set local session_replication_role = origin;
select coalesce(zz.rv('Sinov Ota Xorijb') #>> '{father,phone}', '-') || ' | ' || coalesce(zz.rv('Sinov Ota Yozuvb') #>> '{father,phone}', '-') || ' | '
       || coalesce((zz.rv('Sinov Ota Nolnolb') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Nolnolb') #>> '{father,valid}'), '-') || ' | '
       || coalesce((select string_agg(r #>> '{father,name}', ',') from jsonb_array_elements(zz.list('U_SAL', quote_literal('Tire')) -> 'rows') r), '-') as hx8 \gset
rollback to savepoint hx8;
select zz.chk('HX8 «+» xorijiy raqam JSHSHIRdan ustun; asl yozuv — foydalanib bo''ladiganlardan; 00 bilan xorijiy raqam; ismdagi «—» va 60 belgi', :'hx8',
  '^\+447700900039 \| \+447700900040 \| \+447700900041 true \| Sinov Ota Tire Uzunism Uzunism Uzunism Uzunism Uzunism Uzuni$');

-- H34 (5-tekshiruvdan keyingi qayta ko'rik): katakni o'qish qoidasi (app.sales_nums) — raqam ichida tasodifiy ikki bo'sh joy / qator uzilishi
--   va izoh (yoki oxirida vergul) — butun raqam (avval niqob chiqardi); xorijiy raqam ichida ikki bo'sh joy — kesilgan bo'lak emas, butun
--   raqam; VT ham ajratuvchi, «v» harfi — yo'q; vergulsiz «pasport AA1234567 15-uy» va vergulli «AA 1234567, 15» — raqam emas; «(2-uy)» izohli
--   raqam — raqam qismi; «tel:+998…» — raqam; uzunligi noto'g'ri / davlat kodi noma'lum xorijiy raqam — niqob; ro'yxat niqobi.
select string_agg(t.n || '=' || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'phone', '-') || '/'
                  || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'valid', '-'), ' | ' order by t.n)
       || ' || ' || (select string_agg(coalesce(app.sales_parent('S', app.tg_phone(y), true, y) ->> 'phone', '-'), ' | ' order by k)
                       from unnest(array['+998 00 123 45 67 (2-uy)', '+44 7700 9001  21', 'pasport AA1234567 15-uy']) with ordinality u(y, k)) as h34
  from unnest(array['+998 00 123  45 67 (otasi)', '+998 00 123  45 67,', E'+998 00 100\n20 47 otasi', '+44 7700 9001  21', '+44 7700 900121  2',
                    E'+998 00 111 00 31\x0B+998 00 111 00 32', '+998 00 111 00 31 v +998 00 111 00 32', 'pasport AA1234567 15-uy', '+998 00 123 45 67 (2-uy)',
                    'tel:+998001234567', '+44 7700 90012', '+999 123 456 7890', '(01) 234-56-78, 2-uy', 'pasport AA 1234567, 15',
                    '(01) 234-56-78  (02) 345-67-89']) with ordinality t(x, n) \gset
select zz.chk('H34 katakni o''qish: ikki bo''sh joy / qator uzilishi + izoh — butun raqam; xorijiy raqam bo''lagi chiqmaydi; VT ajratadi, «v» — yo''q; pasport — raqam emas; uzunligi / kodi noto''g''ri xorijiy — niqob',
  :'h34', '^1=\+998001234567/true \| 2=\+998001234567/true \| 3=\+998001002047/true \| 4=\+447700900121/true \| 5=\+44 7700 900121/false \| '
       || '6=\+998 00 111 00 31, \+998 00 111 00 32/false \| 7=\+998 00 111 00 31, \+998 00 111 00 32/false \| 8=\*\*\* \*\* 15/false \| '
       || '9=\+998 00 123 45 67/false \| 10=\+998001234567/true \| 11=\*\*\* \*\* 12/false \| 12=\*\*\* \*\* 90/false \| 13=01 234-56-78/false \| '
       || '14=\*\*\* \*\* 15/false \| 15=01 234-56-78, 02 345-67-89/false \|\| \+998 00 \*\*\* \*\* 67 \| \*\*\* \*\* 21 \| \*\*\* \*\* 15$');

-- H35 — savepoint ichida: aka-uka kartalarida vergulsiz pasport yozuvi («pasport AA0222222 22-uy» — raqamlari 9 ta, avval «+998022222222»
--   bo'lib «foydalanib bo'ladigan» hisoblanardi va saralashda to'g'ri raqamdan oldin tushardi) — to'g'ri raqamni yashirmaydi; raqam ichida
--   ikki bo'sh joy va izohli katak — foydalanib bo'ladi (aka-uka kartasidagi «+»siz xorijiy raqamdan ustun).
savepoint h35;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('t21','IQ-T21','Sinov Bola T21',3,'M','uz','',2461), ('t22','IQ-T22','Sinov Bola T22',4,'M','uz','',2462),
  ('t23','IQ-T23','Sinov Bola T23',3,'M','uz','',2463), ('t24','IQ-T24','Sinov Bola T24',4,'M','uz','',2464);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('t21','Sinov Ota Hujjatb','Sinov Ona Hujjatb','pasport AA0222222 22-uy','+998 00 333 00 61'),
  ('t22','Sinov Ota Hujjatb','Sinov Ona Hujjatb','02 345 67 82','+998 00 333 00 61'),
  ('t23','Sinov Ota Bostir','Sinov Ona Bostir','+44 7700 9001  23 (otasi)','+998 00 333 00 62'),
  ('t24','Sinov Ota Bostir','Sinov Ona Bostir','447700900123','+998 00 333 00 62');
set local session_replication_role = origin;
select coalesce(zz.rv('Sinov Ota Hujjatb') #>> '{father,phone}', '-') || ' | '
       || coalesce((zz.rv('Sinov Ota Bostir') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Bostir') #>> '{father,valid}'), '-') as h35 \gset
rollback to savepoint h35;
select zz.chk('H35 aka-uka: vergulsiz pasport yozuvi to''g''ri raqamni yashirmaydi; ikki bo''sh joyli izohli xorijiy raqam — «+»siz yozuvdan ustun',
  :'h35', '^\+998023456782 \| \+447700900123 true$');

-- H36–H41 (7-mustaqil tekshiruv). H36: harfli so'z — qat'iy ajratuvchi: uning ikki tomonidagi raqamlar (pasport, kvartira, ichki raqam,
--   yosh) qo'shilib, valid=true «O'zbekiston raqami» bo'lmaydi (avval «ish: 123-45-67 (ichki 12)» -> +998123456712); belgidan iborat ajratuvchi
--   («—», «№») ham butun bo'lakni qo'shmaydi; «Tel.:» oldidagi belgi va raqam ichidagi ikki bo'sh joy — xalal bermaydi; «+»siz 9 xonali
--   raqam birinchi guruhi 2 yoki 3 xonali (oxiri «000» emas) bo'lsagina o'qiladi (pasport + uy «1234567 15», «0671712 12», summa
--   «120 000 000» — raqam emas; «012 345 678» — raqam); ma'lum chegara:
--   «15 0123456» (operator kodidek boshlangan) — raqamdek o'qiladi (nazorat); ikki bo'sh joy bilan yozilgan aloqasiz guruhlar («15  0123456»,
--   «2  01 234 56 7») — qo'shilmaydi.
select string_agg(t.n || '=' || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'phone', '-') || '/'
                  || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'valid', '-'), ' | ' order by t.n)
       || ' || ' || (select string_agg(coalesce(app.sales_parent('S', app.tg_phone(y), true, y) ->> 'phone', '-'), ' | ' order by k)
                       from unnest(array['ish: 123-45-67 (ichki 12)', 'pasport AA 0123456 kv 12']) with ordinality u(y, k)) as h36
  from unnest(array['ish: 123-45-67 (ichki 12)', 'pasport AA 0123456 kv 12', '0123456 (kv 12)', '12 yosh 0123456',
                    'ish: 123-45-67 (ichki 12), +998 00 765 43 21', 'otasi +998 00 123  45 67 onasi 02 345 67 89', 'kv.12 — 0123456',
                    '12 № 0123456', 'Otasi-02 012 34 56 uy 78', 'pasport AA 1234567 15 uy', 'Tel.: 01 234  56 78', 'tel:998001234567',
                    'тел.012345678', '0671712 12', '15 0123456', '120 000 000 so''m', '012 345 678', '15  0123456',
                    '2  01 234 56 7', '12 № 01 234 56', '12 — 01 234 56', '+998 00 123 45 67  0123456 15', '15. 0123456']) with ordinality t(x, n) \gset
select zz.chk('H36 harfli so''z — qat''iy ajratuvchi: pasport / kvartira / ichki raqam qo''shilib O''zbekiston raqami bo''lmaydi; «—», «№» ham qo''shmaydi',
  :'h36', '^1=\*\*\* \*\* 12/false \| 2=\*\*\* \*\* 12/false \| 3=\*\*\* \*\* 12/false \| 4=\*\*\* \*\* 56/false \| 5=\+998 00 765 43 21/false \| '
       || '6=\+998 00 123 45 67, 02 345 67 89/false \| 7=\*\*\* \*\* 56/false \| 8=\*\*\* \*\* 56/false \| 9=\*\*\* \*\* 78/false \| '
       || '10=\*\*\* \*\* 15/false \| 11=\+998012345678/true \| 12=\+998001234567/true \| 13=\+998012345678/true \| 14=\*\*\* \*\* 12/false \| '
       || '15=\+998150123456/true \| 16=\*\*\* \*\* 00/false \| 17=\+998012345678/true \| 18=\*\*\* \*\* 56/false \| '
       || '19=\*\*\* \*\* 67/false \| 20=\*\*\* \*\* 56/false \| 21=\*\*\* \*\* 56/false \| 22=\+998 00 123 45 67/false \| 23=\*\*\* \*\* 56/false \|\| '
       || '\*\*\* \*\* 12 \| \*\*\* \*\* 12$');

-- H37: «+» doim yangi so'z boshlaydi: so'zga yopishgan «+999» / «+44» harfli so'z bilan birga tashlanib, qolgan 9 raqam O'zbekiston raqami
--   (begona abonent) bo'lib o'qilmaydi; «tel+…» bilan to'g'ri yozilgan raqam — o'qiladi; yolg'iz davlat kodi va undan keyingi «+»siz bo'lakcha
--   (ikki bo'sh joy / qator uzilishi bilan) — bitta xalqaro raqam (+999 — kodi noma'lum: niqob); +998 va +44 bilan — o'sha raqam; «+» oldidagi
--   bitta bo'sh joy ham ajratadi (ikki raqam). 8-raund: bo'lakchaning o'zi to'liq O'zbekiston raqami (998 + 9 raqam) bo'lsa — alohida
--   o'qiladi, oldidagi «+2» / «+1» / «+998» / «00 2» unga qo'shilib begona valid=true raqam (+299 800 …) bo'lmaydi va raqam yo'qolmaydi (avval
--   «+2⏎998 00 765 43 21» -> begona «+299 …» havolasi); «+» bilan boshlangan keyingi bo'lakcha butun bo'lakni qo'shishga ham qo'shilmaydi:
--   kesilgan raqam + «+7» / «+1» / «+8» (qator uzilishi yoki bitta bo'sh joy bilan, 100-belgi oynasida ham) valid=true begona raqam bo'lmaydi
--   (avval «+998 00 123 45 6⏎+7» -> tel:+998001234567); yolg'iz davlat kodidan keyingisi — qo'shiladi («+998 + 02-111-22-33»). «+» bilan
--   boshlangan raqamning uzun guruhi ichidagi tasodifiy ikki bo'sh joy — butun bo'lak qo'shiladi («+447700900  123»); yolg'iz koddan keyin
--   «+» yoki «00» bilan boshlangan bo'lakcha unga qo'shilmaydi — o'zi o'qiladi («+999  +44 …», «+999  00 44 …»).
select string_agg(t.n || '=' || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'phone', '-') || '/'
                  || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'valid', '-'), ' | ' order by t.n)
       || ' || ' || (select string_agg(coalesce(app.sales_parent('S', app.tg_phone(y), true, y) ->> 'phone', '-'), ' | ' order by k)
                       from unnest(array['tel+999 01 234 56 78', '+999  01 234 56 78', '+2' || E'\n' || '998 00 765 43 21',
                                         '+998 00 123 45 6' || E'\n' || '+7']) with ordinality u(y, k)) as h37
  from unnest(array['tel+999 01 234 56 78', 'ota-+999 01 234 56 78', 'Sinov' || chr(160) || '+999 01 234 56 78', 'tel(+999) 01 234 56 78',
                    'Sinov«+999 01 234 56 78»', '[ota]-+44 7700 90012', 'tel+44 7700 900123', 'tel+998 00 123 45 67', '+999  01 234 56 78',
                    '+999' || E'\n' || '01 234 56 78', '+998  01 234 56 78', '+44  7700 900123', '+999  +998 00 123 45 67',
                    '01 234 56 78 +44 7700 900123', '01 234 56 78-+44 7700 900123',
                    '+2' || E'\n' || '998 00 765 43 21', '+1' || E'\t' || '998 00 843 92 36', '+998' || E'\n' || '998 00 765 43 21',
                    '+29  998 00 765 43 21', '00 2' || E'\n' || '998 00 765 43 21', '+998' || E'\n' || '01 234 56 78',
                    '+998 00 123 45 6' || E'\n' || '+7', '+998 00 123 45 6 +1', '+44 7700 90012' || E'\n' || '+1', '01 234 56 7' || E'\n' || '+8',
                    left(repeat('— ', 47), 93) || chr(160) || '+44 7700 90012' || chr(133) || '+1 / Sinov', '+998 + 02-111-22-33',
                    '+447700900  123', '+99800123  4567', '+999  +44 7700 900123', '+999  00 44 7700 900123']) with ordinality t(x, n) \gset
select zz.chk('H37 so''zga yopishgan «+999» / «+44» tashlanib qolgan 9 raqam +998 bo''lmaydi; «tel+…» — o''qiladi; yolg''iz davlat kodi + bo''lakcha — bitta xalqaro raqam',
  :'h37', '^1=\*\*\* \*\* 78/false \| 2=\*\*\* \*\* 78/false \| 3=\*\*\* \*\* 78/false \| 4=\*\*\* \*\* 78/false \| 5=\*\*\* \*\* 78/false \| '
       || '6=\*\*\* \*\* 12/false \| 7=\+447700900123/true \| 8=\+998001234567/true \| 9=\*\*\* \*\* 78/false \| 10=\*\*\* \*\* 78/false \| '
       || '11=\+998012345678/true \| 12=\+447700900123/true \| 13=\+998 00 123 45 67/false \| 14=01 234 56 78, \+44 7700 900123/false \| 15=01 234 56 78, \+44 7700 900123/false \| '
       || '16=998 00 765 43 21/false \| 17=998 00 843 92 36/false \| 18=998 00 765 43 21/false \| 19=998 00 765 43 21/false \| 20=998 00 765 43 21/false \| '
       || '21=\+998012345678/true \| 22=\*\*\* \*\* 67/false \| 23=\*\*\* \*\* 61/false \| 24=\*\*\* \*\* 21/false \| 25=\*\*\* \*\* 78/false \| '
       || '26=\*\*\* \*\* 21/false \| 27=\+998021112233/true \| 28=\+447700900123/true \| 29=\+998001234567/true \| '
       || '30=\+44 7700 900123/false \| 31=00 44 7700 900123/false \|\| '
       || '\*\*\* \*\* 78 \| \*\*\* \*\* 78 \| \+998 00 \*\*\* \*\* 21 \| \*\*\* \*\* 67$');

-- H38: ko'rinadigan Unicode bo'sh joy (NBSP, U+202F, U+2009) — oddiy bo'sh joy: raqam va izoh orasida bo'lsa raqam yo'qolmaydi (avval
--   niqob); eni nol belgi (U+200B) — bo'sh joy emas (katak yopishgan ko'rinadi: pasport — niqob); Unicode qator ajratuvchisi — qator uzilishi.
select string_agg(t.n || '=' || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'phone', '-') || '/'
                  || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'valid', '-'), ' | ' order by t.n)
       || ' || ' || app.sales_usable('+998 00 123 45 67' || chr(160) || '(otasi)')::text as h38
  from unnest(array['+998 00 123 45 67' || chr(160) || '(otasi)', 'otasi' || chr(160) || '+998 00 123 45 67', 'ota' || chr(8239) || '01 234 56 78',
                    '+44 7700 900123' || chr(8201) || 'otasi', 'pasport AA' || chr(8203) || '0222222 22' || chr(8203) || 'uy',
                    '+998 00 111 00 31' || chr(8232) || '+998 00 111 00 32', '01 234 56 78' || chr(8233) || '02 345 67 89',
                    '01 234 56 78' || chr(133) || '02 345 67 89', 'ota' || chr(8203) || '01 234 56 78', '01 234 56 78' || chr(11) || '02 345 67 89',
                    '01 234 56 78' || chr(12) || '02 345 67 89', 'ота 01 234 56 78' || chr(11) || '02 345 67 89',
                    'ота 01 234 56 78' || chr(12) || '02 345 67 89']) with ordinality t(x, n) \gset
select zz.chk('H38 NBSP / ingichka bo''sh joy — bo''sh joy (raqam yo''qolmaydi); eni nol belgi — bo''sh joy emas; Unicode qator ajratuvchisi — ajratadi',
  :'h38', '^1=\+998001234567/true \| 2=\+998001234567/true \| 3=\+998012345678/true \| 4=\+447700900123/true \| 5=\*\*\* \*\* 22/false \| '
       || '6=\+998 00 111 00 31, \+998 00 111 00 32/false \| 7=01 234 56 78, 02 345 67 89/false \| 8=01 234 56 78, 02 345 67 89/false \| '
       || '9=\*\*\* \*\* 78/false \| 10=01 234 56 78, 02 345 67 89/false \| 11=01 234 56 78, 02 345 67 89/false \| '
       || '12=01 234 56 78, 02 345 67 89/false \| 13=01 234 56 78, 02 345 67 89/false \|\| true$');

-- H39: 100 belgi chegarasi raqam o'rtasiga tushsa — kesilgan raqam (boshqa raqam) o'qilmaydi (avval «… +44 7700 900123|4» -> tel:+447700900123);
--   harfga yopishgan raqam kesilganda ham — niqob; chegaradan keyin bo'lak oxirigacha to'g'ri yozilgan raqam — o'qiladi; qator-qator yozilgan
--   raqamlardan faqat kesilgani tashlanadi; faqat raqam / belgidan iborat uzun katak — niqob (ro'yxat ham).
select string_agg(t.n || '=' || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'phone', '-') || '/'
                  || coalesce(app.sales_parent('S', app.tg_phone(t.x), true, t.x) ->> 'phone', '-'), ' | ' order by t.n) as h39
  from unnest(array[rpad('Sinov izoh', 84, ' izoh') || ' +44 7700 9001234', rpad('Sinov izoh', 82, ' izoh') || ' +998 00 123 45 678',
                    rpad('Sinov izoh', 90, ' izoh') || ' 01234567890123', rpad('Sinov izoh', 90, ' izoh') || ' 012345678ota',
                    rpad('Sinov izoh', 84, ' izoh') || ' +44 7700 900123 4', rpad('Sinov izoh', 82, ' izoh') || ' +998 00 123 45 67 2-uy',
                    'Sinov +998 00 123 45 67' || E'\n' || rpad('Sinov izoh', 60, ' izoh') || ' +44 7700 9001234',
                    rpad('Sinov izoh', 90, ' izoh') || ' +998 00 123 45 67, izoh',
                    '+998 00 111 00 01' || E'\n' || '+998 00 111 00 02' || E'\n' || '+998 00 111 00 03' || E'\n' || '+998 00 111 00 04' || E'\n'
                      || '+998 00 111 00 05' || E'\n' || '+998 00 111 00 06',
                    repeat('-', 90) || '+998 00 127 00 01',
                    rpad('Sinov izoh', 70, ' izoh') || ' +998 00 123 45 67' || E'\n' || '+998 00 765 43 21']) with ordinality t(x, n) \gset
select zz.chk('H39 100 belgi chegarasi: kesilgan raqam o''qilmaydi; bo''lak oxirigacha to''g''ri raqam — o''qiladi; qator-qator raqamlardan faqat kesilgani tashlanadi',
  :'h39', '^1=\*\*\* \*\* 34/\*\*\* \*\* 34 \| 2=\*\*\* \*\* 78/\*\*\* \*\* 78 \| 3=\*\*\* \*\* 23/\*\*\* \*\* 23 \| 4=\*\*\* \*\* 78/\*\*\* \*\* 78 \| '
       || '5=\*\*\* \*\* 34/\*\*\* \*\* 34 \| 6=\+998 00 123 45 67/\+998 00 \*\*\* \*\* 67 \| 7=\+998 00 123 45 67/\+998 00 \*\*\* \*\* 67 \| '
       || '8=\+998001234567/\+998 00 \*\*\* \*\* 67 \| 9=\+998 00 111 00 01, \+998 00 111 00 02, \+998 00 111 00 03, \+998 00 111 00 04, '
       || '\+998 00 111 00 05/\+998 00 \*\*\* \*\* 01 \| 10=\*\*\* \*\* 01/\*\*\* \*\* 01 \| 11=\+998 00 123 45 67/\+998 00 \*\*\* \*\* 67$');

-- H40 / H41 — savepoint ichida (aka-uka kartalari). H40: «bu ikkinchi ota-onaning raqamimi» — qo'ng'iroq kanonigi bo'yicha: izohli katakdagi
--   ona raqami («+998 00 300 00 02 (2-uy)», «…, 2-uy») otaning haqiqiy raqamini yashirmaydi va aksincha (avval teng darajada turib, saralashda
--   oldin tushardi); ota ismisiz kartadagi izohli ona raqami ota raqami bo'lib chiqmaydi; NBSP li izohli katak — foydalanib bo'ladi.
--   H41: 100 belgidan uzun katak (raqami 100-belgidan keyin), ikki bo'sh joy / nuqta bilan yozilgan aloqasiz guruhlar («01  2345678»,
--   «01. 2345678»), pasport + uy («0123456 15») — foydalanib bo'lmaydi (oilalar ro'yxatining tezkor yo'li ham sales_nums kabi o'qiydi):
--   aka-uka kartasidagi to'g'ri raqam yashirinmaydi.
--   H42: daraja va soni teng ikki raqam — butun katagi to'g'ri raqam bo'lgani (toza yozilgani) ustun, izohli katakdan olingani emas (avval
--   alifbo tartibida kichigi — ko'pincha izohli katakniki — tanlanardi); kesilgan raqam + «+7» katagi (o'qilmaydi) aka-uka kartasidagi to'g'ri
--   raqamni yashirmaydi (8-raund: avval ikkalasi teng darajada turib, begona +998001234567 tanlanardi).
savepoint h40;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('t41','IQ-T41','Sinov Bola T41',3,'M','uz','',2471), ('t42','IQ-T42','Sinov Bola T42',4,'M','uz','',2472),
  ('t43','IQ-T43','Sinov Bola T43',3,'M','uz','',2473), ('t44','IQ-T44','Sinov Bola T44',4,'M','uz','',2474),
  ('t45','IQ-T45','Sinov Bola T45',3,'M','uz','',2475), ('t46','IQ-T46','Sinov Bola T46',4,'M','uz','',2476),
  ('t47','IQ-T47','Sinov Bola T47',3,'M','uz','',2477), ('t48','IQ-T48','Sinov Bola T48',4,'M','uz','',2478),
  ('t49','IQ-T49','Sinov Bola T49',3,'M','uz','',2479), ('t50','IQ-T50','Sinov Bola T50',4,'M','uz','',2480),
  ('t51','IQ-T51','Sinov Bola T51',3,'M','uz','',2481), ('t52','IQ-T52','Sinov Bola T52',4,'M','uz','',2482),
  ('t53','IQ-T53','Sinov Bola T53',3,'M','uz','',2483), ('t54','IQ-T54','Sinov Bola T54',4,'M','uz','',2484),
  ('t55','IQ-T55','Sinov Bola T55',3,'M','uz','',2485), ('t56','IQ-T56','Sinov Bola T56',4,'M','uz','',2486),
  ('t57','IQ-T57','Sinov Bola T57',3,'M','uz','',2487), ('t58','IQ-T58','Sinov Bola T58',4,'M','uz','',2488),
  ('t59','IQ-T59','Sinov Bola T59',3,'M','uz','',2489), ('t60','IQ-T60','Sinov Bola T60',4,'M','uz','',2490),
  ('t69','IQ-T69','Sinov Bola T69',3,'M','uz','',2499), ('t70','IQ-T70','Sinov Bola T70',4,'M','uz','',2500),
  ('t71','IQ-T71','Sinov Bola T71',3,'M','uz','',2501), ('t72','IQ-T72','Sinov Bola T72',4,'M','uz','',2502),
  ('t73','IQ-T73','Sinov Bola T73',3,'M','uz','',2503), ('t74','IQ-T74','Sinov Bola T74',4,'M','uz','',2504),
  ('t61','IQ-T61','Sinov Bola T61',3,'M','uz','',2491), ('t62','IQ-T62','Sinov Bola T62',4,'M','uz','',2492),
  ('t63','IQ-T63','Sinov Bola T63',3,'M','uz','',2493), ('t64','IQ-T64','Sinov Bola T64',4,'M','uz','',2494),
  ('t65','IQ-T65','Sinov Bola T65',3,'M','uz','',2495), ('t66','IQ-T66','Sinov Bola T66',4,'M','uz','',2496),
  ('t67','IQ-T67','Sinov Bola T67',3,'M','uz','',2497), ('t68','IQ-T68','Sinov Bola T68',4,'M','uz','',2498),
  ('t75','IQ-T75','Sinov Bola T75',3,'M','uz','',2505), ('t76','IQ-T76','Sinov Bola T76',4,'M','uz','',2506);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('t41','Sinov Ota Delfin','Sinov Ona Delfin','02 345 67 01','+998 00 300 00 02'),
  ('t42','Sinov Ota Delfin','Sinov Ona Delfin','+998 00 300 00 02 (2-uy)','+998 00 300 00 02'),
  ('t43','Sinov Ota Hilola','Sinov Ona Hilola','+998 00 300 00 31','+998 00 300 00 31 (2-uy)'),
  ('t44','Sinov Ota Hilola','Sinov Ona Hilola','+998 00 300 00 31','02 345 67 32'),
  ('t45','Sinov Ota Gulsara','Sinov Ona Gulsara','pasport AA 1234567, 15','+998 00 300 00 22'),
  ('t46',null,'Sinov Ona Gulsara','+998 00 300 00 22 (2-uy)','+998 00 300 00 22'),
  ('t47','Sinov Ota Jasurv','Sinov Ona Jasurv','+998 00 300 00 53, 2-uy','+998 00 300 00 53'),
  ('t48','Sinov Ota Jasurv','Sinov Ona Jasurv','+998 00 300 00 53, 2-uy','+998 00 300 00 53'),
  ('t49','Sinov Ota Jasurv','Sinov Ona Jasurv','+998 00 300 00 53','02 345 67 54'),
  ('t50','Sinov Ota Jasurv','Sinov Ona Jasurv','+998 00 300 00 53, 2-uy','02 345 67 54'),
  ('t51',null,'Sinov Ona Qumri','+998 00 300 00 61 (2-uy)','+998 00 300 00 61'),
  ('t52','Sinov Ota Nbsp','Sinov Ona Nbsp','+998 00 333 00 75' || chr(160) || '(otasi)','+998 00 333 00 76'),
  ('t53','Sinov Ota Nbsp','Sinov Ona Nbsp','+998 00 333 00 75' || chr(160) || '(otasi)','+998 00 333 00 76'),
  ('t54','Sinov Ota Nbsp','Sinov Ona Nbsp','01 234 56 77','+998 00 333 00 76'),
  ('t55','Sinov Ota Uzun','Sinov Ona Uzun', repeat('-', 90) || '998 00 127 00 01','+998 00 201 00 31'),
  ('t56','Sinov Ota Uzun','Sinov Ona Uzun','01 234 56 24','+998 00 201 00 31'),
  ('t57','Sinov Ota Uzunx','Sinov Ona Uzunx', repeat('.', 90) || '+44 7700 900131','+998 00 201 00 32'),
  ('t58','Sinov Ota Uzunx','Sinov Ona Uzunx','+44 7700 900132','+998 00 201 00 32'),
  ('t59','Sinov Ota Iroda',null,'02 345 67 43','+998 00 300 00 41'),
  ('t69','Sinov Ota Tezkor','Sinov Ona Tezkor','01  2345678','+998 00 201 00 33'),
  ('t70','Sinov Ota Tezkor','Sinov Ona Tezkor','02 345 67 79','+998 00 201 00 33'),
  ('t71','Sinov Ota Tezkorn','Sinov Ona Tezkorn','01. 2345678','+998 00 201 00 34'),
  ('t72','Sinov Ota Tezkorn','Sinov Ona Tezkorn','02 345 67 78','+998 00 201 00 34'),
  ('t73','Sinov Ota Guruh','Sinov Ona Guruh','0123456 15','+998 00 201 00 35'),
  ('t74','Sinov Ota Guruh','Sinov Ona Guruh','02 345 67 77','+998 00 201 00 35'),
  ('t60','Sinov Ota Iroda','Sinov Ona Iroda','+998 00 300 00 41','+998 00 300 00 41 (2-uy)'),
  ('t61','Sinov Ota Fa','Sinov Ona Fa','+0998 00 123 45 67 (2-uy)','+998 00 111 22 33'),
  ('t62','Sinov Ota Fa','Sinov Ona Fa','+998 00 765 43 21','+998 00 111 22 33'),
  ('t63','Sinov Ota Fb','Sinov Ona Fb','+998 00 111 22 34','+0998 00 123 45 68 (2-uy)'),
  ('t64','Sinov Ota Fb','Sinov Ona Fb','+998 00 111 22 34','+998 00 765 43 22'),
  ('t65',null,'Sinov Ona Fd','+998 00 765 43 24','+0998 00 123 45 70 (2-uy)'),
  ('t66',null,'Sinov Ona Fd','+0998 00 123 45 70 (2-uy)','+998 00 765 43 24'),
  ('t67',null,'Sinov Ona Fd','+998 00 765 43 24','+998 00 111 22 36'),
  ('t68',null,'Sinov Ona Fd','+0998 00 123 45 70 (2-uy)','+998 00 111 22 36'),
  ('t75','Sinov Ota Qoshplyus','Sinov Ona Qoshplyus','+998 00 123 45 6' || E'\n' || '+7','+998 00 222 00 75'),
  ('t76','Sinov Ota Qoshplyus','Sinov Ona Qoshplyus','+998 00 765 43 75','+998 00 222 00 75');
set local session_replication_role = origin;
select coalesce((zz.rv('Sinov Ota Delfin') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Delfin') #>> '{father,valid}'), '-') || ' | '
       || coalesce(zz.rv('Sinov Ota Hilola') #>> '{mother,phone}', '-') || ' | '
       || coalesce(zz.rv('Sinov Ota Gulsara') #>> '{father,phone}', '-') || ' | '
       || coalesce(zz.rv('Sinov Ota Jasurv') #>> '{mother,phone}', '-') || ' | '
       || coalesce(zz.rv('Sinov Ona Qumri') #>> '{father,phone}', 'null') || ' ' || coalesce(zz.rv('Sinov Ona Qumri') #>> '{mother,phone}', '-') || ' | '
       || coalesce((zz.rv('Sinov Ota Nbsp') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Nbsp') #>> '{father,valid}'), '-') || ' | '
       || coalesce(zz.rv('Sinov Ota Iroda') #>> '{father,phone}', '-') as h40,
       coalesce((zz.rv('Sinov Ota Fa') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Fa') #>> '{father,valid}'), '-') || ' | '
       || coalesce((zz.rv('Sinov Ota Fb') #>> '{mother,phone}') || ' ' || (zz.rv('Sinov Ota Fb') #>> '{mother,valid}'), '-') || ' | '
       || coalesce((zz.rv('Sinov Ona Fd') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ona Fd') #>> '{father,valid}'), '-') || ' '
       || coalesce(zz.rv('Sinov Ona Fd') #>> '{mother,phone}', '-') || ' | '
       || coalesce((zz.rv('Sinov Ota Qoshplyus') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Qoshplyus') #>> '{father,valid}'), '-') as h42,
       coalesce((zz.rv('Sinov Ota Uzun') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Uzun') #>> '{father,valid}'), '-') || ' | '
       || coalesce((zz.rv('Sinov Ota Uzunx') #>> '{father,phone}') || ' ' || (zz.rv('Sinov Ota Uzunx') #>> '{father,valid}'), '-') || ' | '
       || coalesce(zz.rv('Sinov Ota Tezkor') #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv('Sinov Ota Tezkorn') #>> '{father,phone}', '-') || ' '
       || coalesce(zz.rv('Sinov Ota Guruh') #>> '{father,phone}', '-') as h41 \gset
rollback to savepoint h40;
select zz.chk('H40 aka-uka: izohli katakdagi ikkinchi ota-onaning raqami haqiqiy raqamni yashirmaydi (ota ham, ona ham); ota ismisiz izohli katak — ota raqami emas; NBSP li izohli katak — foydalanib bo''ladi',
  :'h40', '^\+998023456701 true \| \+998023456732 \| \*\*\* \*\* 15 \| \+998023456754 \| null \+998003000061 \| \+998003330075 true \| \+998023456743$');
select zz.chk('H41 aka-uka: o''qilmaydigan katak (100 belgidan uzun; ikki bo''sh joy / nuqta bilan aloqasiz guruhlar; pasport + uy) to''g''ri raqamni yashirmaydi — tezkor yo''l sales_nums bilan bir xil',
  :'h41', '^\+998012345624 true \| \+447700900132 true \| \+998023456779 \+998023456778 \+998023456777$');
select zz.chk('H42 aka-uka: daraja va soni teng ikki raqamdan toza yozilgan to''g''ri raqam izohli katakdan olinganidan ustun (ota, ona, ota ismisiz almashgan raqamlar)',
  :'h42', '^\+998007654321 true \| \+998007654322 true \| \+998007654324 true \+998001112236 \| \+998007654375 true$');

-- H43–H45 (8-mustaqil tekshiruv, 2ea2b95 ga). H43: yolg'iz davlat kodi va undan keyingi «+»siz bo'lakcha — bitta bo'lakcha (8-qoida),
--   katakda boshqa raqam bo'lsa ham, kod va raqam orasida «:» / «—» bo'lsa ham, kod «00» bilan yozilgan bo'lsa ham (avval kod bo'lakchasi
--   tashlanib, raqam yo'qolardi: «+998⏎01 234 56 78⏎+998⏎01 234 56 79» -> niqob, «00998⏎012345678» -> niqob); «+999» — kodi noma'lum (niqob),
--   keyingi raqam — alohida; o'zi to'liq 998 raqam bo'lgan bo'lakcha — alohida; qo'shilgan bo'lakcha keyingisiga qo'shilmaydi («+4. 4) — …»);
--   davlat kodi — 1–3 raqam: «+4477⏎01 234 56 78» dagi «+4477» kod emas, keyingi mahalliy raqam yo'qolmaydi.
select string_agg(t.n || '=' || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'phone', '-') || '/'
                  || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'valid', '-'), ' | ' order by t.n)
       || ' || ' || (select string_agg(coalesce(app.sales_parent('S', app.tg_phone(y), true, y) ->> 'phone', '-'), ' | ' order by k)
                       from unnest(array['+998' || E'\n' || '01 234 56 78' || E'\n' || '+998' || E'\n' || '01 234 56 79',
                                         '00998' || E'\n' || '012345678']) with ordinality u(y, k)) as h43
  from unnest(array['+998' || E'\n' || '01 234 56 78' || E'\n' || '+998' || E'\n' || '01 234 56 79',
                    '+998  01 234 56 78' || E'\n' || '+998 01 234 56 79', '01 234 56 78' || E'\n' || '+998' || E'\n' || '01 234 56 79',
                    '00998' || E'\n' || '012345678', '0044  7700900123', '+998:' || E'\n' || '01 234 56 78', '+998 —' || E'\n' || '01 234 56 78',
                    '+44' || E'\n' || '7700 900123' || E'\n' || '01 234 56 79', '+998' || E'\n' || '998 01 234 56 78',
                    '+999' || E'\n' || '01 234 56 78' || E'\n' || '01 234 56 79', '+4. 4) — 7700 900123',
                    '00 998' || E'\n' || '01 234 56 78' || E'\n' || '00 998' || E'\n' || '01 234 56 79', '+4477' || E'\n' || '01 234 56 78']) with ordinality t(x, n) \gset
select zz.chk('H43 yolg''iz davlat kodi + bo''lakcha — bitta raqam (ikkinchi raqam, «:» / «—», «00» kod bilan ham); to''liq 998 bo''lakcha — alohida; zanjir yo''q',
  :'h43', '^1=\+998 01 234 56 78, \+998 01 234 56 79/false \| 2=\+998 01 234 56 78, \+998 01 234 56 79/false \| '
       || '3=01 234 56 78, \+998 01 234 56 79/false \| 4=\+998012345678/true \| 5=\+447700900123/true \| 6=\+998012345678/true \| '
       || '7=\+998012345678/true \| 8=\+44 7700 900123, 01 234 56 79/false \| 9=998 01 234 56 78/false \| 10=01 234 56 79/false \| '
       || '11=\*\*\* \*\* 23/false \| 12=00 998 01 234 56 78, 00 998 01 234 56 79/false \| 13=01 234 56 78/false \|\| '
       || '\+998 01 \*\*\* \*\* 78 \| \+998 01 \*\*\* \*\* 78$');

-- H44: «+» dan keyin «0» bilan boshlangan mahalliy raqam («+ 02 345 67 89 (15)» — «va» ma'nosidagi yoki tasodifiy «+») nol tashlanib xorijiy
--   raqam bo'lib o'qilmaydi va sahifada tel: havolasi bo'lmaydi — bir katakdagi ikkinchi raqam bo'lsa ham (« + », vergul, qator uzilishi
--   bilan; avval «01 234 56 78 + 02 345 67 89 (15)» -> «01 234 56 78, + 02 345 67 89 15» va sahifada begona «+234 …» havolasi); tasodifiy raqam
--   yopishgan O'zbekiston raqami («+2 998 00 765 43 21», «00 2 998 …») ro'yxatda yo'q davlat kodi bilan begona valid=true xorijiy raqam
--   bo'lmaydi (avval begona «+299 …» havolasi) — oxirida izoh raqami bo'lsa ham («+2 998 00 765 43 21 (15)», 9-mustaqil tekshiruv: avval
--   «$» bilan cheklangan qoida chetlab o'tilib, valid=true begona «+299 … 15» havolasi); «+0998 …» xatosi, «+0 44 …», «+00 44 …», ichida
--   «998» bo'lgan to'g'ri raqamlar — o'qiladi.
select string_agg(t.n || '=' || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'phone', '-') || '/'
                  || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'valid', '-'), ' | ' order by t.n) as h44
  from unnest(array['01 234 56 78 + 02 345 67 89 (15)', '01 234 56 78, + 02 345 67 89 (15)', '01 234 56 78' || E'\n' || '+ 02 345 67 89 (15)',
                    '+ 02 345 67 89 (15)', '+ (02) 345 67 89 (15)', '+0998 00 123 45 67', '+0 44 7700 900123', '+00 44 7700 900123',
                    '+0998 00 123 45 67 (2-uy)', '+2 998 00 765 43 21', '+29 998 00 765 43 21', '00 2 998 00 765 43 21',
                    '+44 7700 900998', '+998 00 998 77 12',
                    '+2 998 00 765 43 21 (15)', '+2' || E'\n' || '998 00 765 43 21 (15)', '+2 998 00 765 43 21 1', '00 2 998 00 765 43 21 (15)',
                    '+2 998 00 765 43 21  (15)', '(+2)' || chr(8232) || '+998 00 123 45 6' || chr(160) || chr(160) || '(15)',
                    '+2 998 00 765 43 21 (15), 01 234 56 78']) with ordinality t(x, n) \gset
select zz.chk('H44 «+» dan keyin «0» bilan boshlangan mahalliy raqam nol tashlanib xorijiy raqam bo''lmaydi; «+2 998 …» (izoh raqami bilan ham) — begona xorijiy raqam emas; «+0998 …», «+0 44 …» — o''qiladi',
  :'h44', '^1=01 234 56 78/false \| 2=01 234 56 78/false \| 3=01 234 56 78/false \| 4=\*\*\* \*\* 15/false \| 5=\*\*\* \*\* 15/false \| '
       || '6=\+998001234567/true \| 7=\+447700900123/true \| 8=\+447700900123/true \| 9=\+0998 00 123 45 67/false \| '
       || '10=\*\*\* \*\* 21/false \| 11=\*\*\* \*\* 21/false \| 12=\*\*\* \*\* 21/false \| 13=\+447700900998/true \| 14=\+998009987712/true \| '
       || '15=\*\*\* \*\* 15/false \| 16=\*\*\* \*\* 15/false \| 17=\*\*\* \*\* 11/false \| 18=\*\*\* \*\* 15/false \| 19=\*\*\* \*\* 15/false \| '
       || '20=\*\*\* \*\* 15/false \| 21=01 234 56 78/false$');

-- H45 — savepoint ichida (aka-uka kartalari). Bitta kartada ota va ona raqamlari almashib yozilgan, ota raqami esa izohli («(2-uy)»,
--   «(kv 5)», «kv 12») — qo'ng'iroq kanonigi bo'yicha ota raqami ham «ona raqami» (fp_mom) bo'lib, ikkala raqam 3-darajada teng turardi;
--   otaning turli izohli yozuvlari alohida sanalib, toza yozilgan ona raqami ustun chiqib, ota va ona to'liq almashardi (valid=true tel:
--   havolasi boshqa ota-onaga). Endi daraja ichida: ota uchun — kamroq ona katagida turgan raqam, so'ng ustundagi qo'ng'iroq raqami soni;
--   ona uchun — ona ustunidagi soni. Nodirb — almashgan karta + ikki izohli ota katagi; Rustamb — ota raqami ota ismisiz kartada;
--   Xurshidb — uchinchi karta onasi ro'yxatdan o'tkazgan (ota ismisiz, ikkala katakda ona raqami); Lolab — «(otasi)» izohli ota raqami
--   ona katagida, ona raqami 2 kartada. Plyusb / Plyusc / Lolac: daraja va soni teng — toza yozilgan raqam tasodifiy raqam yopishgan
--   katakdagisidan («+2⏎998 …» — katak kanonigi 2998…, «to'g'ri» ko'rinadi) ustun: ota (fpc), ona (mpc), ota ismisiz kartalardan ota (fpf).
--   Ikkiizoh: ota raqami ikki kartada ikki xil izoh bilan, maktab raqami bitta kartada toza — ota raqami (qo'ng'iroq raqami soni) ustun;
--   Lolad: xuddi shunday, ota ismisiz kartalardan ota raqamini tanlashda (fpf).
--   9-mustaqil tekshiruv (1c08011 ga): Ikkiona / Qatorona — ona katagiga ikkala raqami yozilgan («M, M2», «M⏎M2»), bitta karta almashgan,
--   bittasida ikkala katakda ota raqami: ota raqami 4 ta ota katagida, 2 ta ona katagida — ota va ona almashmaydi (avval «kamroq ona katagida»
--   qoidasi faqat ona katagini sanab, otaning raqamini onaniki, onanikini otaniki qilardi; 2ea2b95 da to'g'ri edi). Plyusd — ota katagida
--   tasodifiy «+2» va izoh raqami bilan yozilgan raqam («+2 998 00 765 43 70 (15)») begona «+299 …» bo'lib, aka-ukaning toza yozilgan
--   raqamini yashirmaydi.
savepoint h45;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order") values
  ('u41','IQ-U41','Sinov Bola U41',3,'M','uz','',2511), ('u42','IQ-U42','Sinov Bola U42',4,'M','uz','',2512),
  ('u43','IQ-U43','Sinov Bola U43',5,'M','uz','',2513), ('u44','IQ-U44','Sinov Bola U44',3,'M','uz','',2514),
  ('u45','IQ-U45','Sinov Bola U45',4,'M','uz','',2515), ('u46','IQ-U46','Sinov Bola U46',5,'M','uz','',2516),
  ('u47','IQ-U47','Sinov Bola U47',3,'M','uz','',2517), ('u48','IQ-U48','Sinov Bola U48',4,'M','uz','',2518),
  ('u49','IQ-U49','Sinov Bola U49',5,'M','uz','',2519), ('u50','IQ-U50','Sinov Bola U50',3,'M','uz','',2520),
  ('u51','IQ-U51','Sinov Bola U51',4,'M','uz','',2521), ('u52','IQ-U52','Sinov Bola U52',5,'M','uz','',2522),
  ('u53','IQ-U53','Sinov Bola U53',3,'M','uz','',2523), ('u54','IQ-U54','Sinov Bola U54',4,'M','uz','',2524),
  ('u55','IQ-U55','Sinov Bola U55',3,'M','uz','',2525), ('u56','IQ-U56','Sinov Bola U56',4,'M','uz','',2526),
  ('u57','IQ-U57','Sinov Bola U57',3,'M','uz','',2527), ('u58','IQ-U58','Sinov Bola U58',4,'M','uz','',2528),
  ('u59','IQ-U59','Sinov Bola U59',5,'M','uz','',2529), ('u60','IQ-U60','Sinov Bola U60',3,'M','uz','',2530),
  ('u61','IQ-U61','Sinov Bola U61',4,'M','uz','',2531), ('u62','IQ-U62','Sinov Bola U62',5,'M','uz','',2532),
  ('u63','IQ-U63','Sinov Bola U63',3,'M','uz','',2533), ('u64','IQ-U64','Sinov Bola U64',4,'M','uz','',2534),
  ('u65','IQ-U65','Sinov Bola U65',5,'M','uz','',2535), ('u66','IQ-U66','Sinov Bola U66',6,'M','uz','',2536),
  ('u67','IQ-U67','Sinov Bola U67',7,'M','uz','',2537),
  ('u68','IQ-U68','Sinov Bola U68',3,'M','uz','',2538), ('u69','IQ-U69','Sinov Bola U69',4,'M','uz','',2539),
  ('u70','IQ-U70','Sinov Bola U70',5,'M','uz','',2540), ('u71','IQ-U71','Sinov Bola U71',6,'M','uz','',2541),
  ('u72','IQ-U72','Sinov Bola U72',7,'M','uz','',2542), ('u73','IQ-U73','Sinov Bola U73',3,'M','uz','',2543),
  ('u74','IQ-U74','Sinov Bola U74',4,'M','uz','',2544), ('u75','IQ-U75','Sinov Bola U75',5,'M','uz','',2545),
  ('u76','IQ-U76','Sinov Bola U76',6,'M','uz','',2546), ('u77','IQ-U77','Sinov Bola U77',3,'M','uz','',2547),
  ('u78','IQ-U78','Sinov Bola U78',4,'M','uz','',2548);
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2") values
  ('u41','Sinov Ota Nodirb','Sinov Ona Nodirb','+998 00 222 33 51','01 234 56 51 (2-uy)'),
  ('u42','Sinov Ota Nodirb','Sinov Ona Nodirb','01 234 56 51 (kv 5)','+998 00 222 33 51'),
  ('u43','Sinov Ota Nodirb','Sinov Ona Nodirb','01 234 56 51 (3-uy)','+998 00 222 33 51'),
  ('u44','Sinov Ota Rustamb','Sinov Ona Rustamb','02 345 67 52','+998 00 111 22 52 (otasi)'),
  ('u45',null,'Sinov Ona Rustamb','+998 00 111 22 52','(02) 345-67-52'),
  ('u46','Sinov Ota Rustamb','Sinov Ona Rustamb','+998 00 111 22 52 kv 12','tel: 02 345 67 52'),
  ('u47','Sinov Ota Xurshidb','Sinov Ona Xurshidb','01 234 56 53 (kv 5)','+998 00 222 33 53'),
  ('u48','Sinov Ota Xurshidb','Sinov Ona Xurshidb','+998 00 222 33 53','01 234 56 53 (2-uy)'),
  ('u49',null,'Sinov Ona Xurshidb','+998 00 222 33 53','+998 00 222 33 53'),
  ('u50','Sinov Ota Lolab','Sinov Ona Lolab','','+998 00 111 22 55 (otasi)'),
  ('u51',null,'Sinov Ona Lolab','+998 00 111 22 55','02 345 67 55, 2-uy'),
  ('u52',null,'Sinov Ona Lolab','+998 00 111 22 55','02 345 67 55'),
  ('u53','Sinov Ota Plyusb','Sinov Ona Plyusb','+2' || E'\n' || '998 00 765 43 56','+998 00 222 33 56'),
  ('u54','Sinov Ota Plyusb','Sinov Ona Plyusb','+998 00 765 43 56','+998 00 222 33 56'),
  ('u55','Sinov Ota Plyusc','Sinov Ona Plyusc','+998 00 765 43 57','+3' || E'\n' || '998 00 222 33 57'),
  ('u56','Sinov Ota Plyusc','Sinov Ona Plyusc','+998 00 765 43 57','+998 00 222 33 57'),
  ('u57','Sinov Ota Lolac','Sinov Ona Lolac','','+998 00 111 22 59 (otasi)'),
  ('u58',null,'Sinov Ona Lolac','+4' || E'\n' || '998 00 111 22 59','02 345 67 59'),
  ('u59',null,'Sinov Ona Lolac','+998 00 111 22 59','02 345 67 59'),
  ('u60','Sinov Ota Ikkiizoh','Sinov Ona Ikkiizoh','01 234 56 60 (kv 5)','+998 00 222 33 60'),
  ('u61','Sinov Ota Ikkiizoh','Sinov Ona Ikkiizoh','01 234 56 60 (2-uy)','+998 00 222 33 60'),
  ('u62','Sinov Ota Ikkiizoh','Sinov Ona Ikkiizoh','+998 00 555 55 60','+998 00 222 33 60'),
  ('u63',null,'Sinov Ona Lolad','02 345 67 63','+998 00 111 22 63 (otasi)'),
  ('u64',null,'Sinov Ona Lolad','02 345 67 63','+998 00 444 22 63 (otasi)'),
  ('u65',null,'Sinov Ona Lolad','+998 00 111 22 63 (2-uy)','02 345 67 63'),
  ('u66',null,'Sinov Ona Lolad','+998 00 111 22 63, 3-uy','02 345 67 63'),
  ('u67',null,'Sinov Ona Lolad','+998 00 444 22 63','02 345 67 63'),
  ('u68','Sinov Ota Ikkiona','Sinov Ona Ikkiona','+998 00 111 22 68','+998 00 444 55 68, +998 00 777 88 68'),
  ('u69','Sinov Ota Ikkiona','Sinov Ona Ikkiona','+998 00 111 22 68','+998 00 444 55 68, +998 00 777 88 68'),
  ('u70','Sinov Ota Ikkiona','Sinov Ona Ikkiona','+998 00 111 22 68','+998 00 444 55 68'),
  ('u71','Sinov Ota Ikkiona','Sinov Ona Ikkiona','+998 00 444 55 68','+998 00 111 22 68'),
  ('u72','Sinov Ota Ikkiona','Sinov Ona Ikkiona','+998 00 111 22 68','+998 00 111 22 68'),
  ('u73','Sinov Ota Qatorona','Sinov Ona Qatorona','+998 00 111 22 69','+998 00 444 55 69' || E'\n' || '+998 00 777 88 69'),
  ('u74','Sinov Ota Qatorona','Sinov Ona Qatorona','+998 00 111 22 69','+998 00 444 55 69'),
  ('u75','Sinov Ota Qatorona','Sinov Ona Qatorona','+998 00 444 55 69','+998 00 111 22 69'),
  ('u76','Sinov Ota Qatorona','Sinov Ona Qatorona','+998 00 111 22 69','+998 00 111 22 69'),
  ('u77','Sinov Ota Plyusd','Sinov Ona Plyusd','+2 998 00 765 43 70 (15)','+998 00 222 33 70'),
  ('u78','Sinov Ota Plyusd','Sinov Ona Plyusd','+998 00 765 43 70','+998 00 222 33 70');
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o) as h45
  from (values (1, 'Sinov Ota Nodirb'), (2, 'Sinov Ota Rustamb'), (3, 'Sinov Ota Xurshidb'), (4, 'Sinov Ona Lolab'),
               (5, 'Sinov Ota Plyusb'), (6, 'Sinov Ota Plyusc'), (7, 'Sinov Ona Lolac'), (8, 'Sinov Ota Ikkiizoh'),
               (9, 'Sinov Ona Lolad'), (10, 'Sinov Ota Ikkiona'), (11, 'Sinov Ota Qatorona'), (12, 'Sinov Ota Plyusd')) x(o, n) \gset
rollback to savepoint h45;
select zz.chk('H45 aka-uka: bitta kartada raqamlar almashgan, ota raqami izohli — ota va ona almashmaydi; teng darajada toza yozilgan raqam tasodifiy raqam yopishgan katakdagisidan ustun',
  :'h45', '^01 234 56 51 false \+998002223351 true \| \+998 00 111 22 52 false \+998023456752 true \| 01 234 56 53 false \+998002223353 true \| '
       || '\+998001112255 true \+998023456755 true \| \+998007654356 true \+998002223356 true \| \+998007654357 true \+998002223357 true \| '
       || '\+998001112259 true \+998023456759 true \| 01 234 56 60 false \+998002223360 true \| \+998 00 111 22 63 false \+998023456763 true \| '
       || '\+998001112268 true \+998 00 444 55 68, \+998 00 777 88 68 false \| \+998001112269 true \+998004445569 true \| '
       || '\+998007654370 true \+998002223370 true$');

-- H46 (9-mustaqil tekshiruv, 1c08011 ga): 8-qoida birlashtirishida yozilgan kod qo'shilgan raqamning davlat kodi bo'lishi shart (yoki kod
--   keyingi bo'lakchaning birinchi raqam guruhi bilan davom etadi: «+99⏎8 00 …», «+4. 4) - 7700 …»; nollardan iborat kod — xalqaro prefiks).
--   Aks holda tasodifiy «+10» / «+3» / «+440» / «00 10» mahalliy raqamga qo'shilib boshqa davlat raqami (+1 001 …, +30 …, +44 0…) valid=true
--   yoki tel: havolasi bo'lardi; butun bo'lak ham qayta qo'shilmaydi («+10⏎01 234 56⏎78»); bo'lakcha to'liq 9 xonali mahalliy raqam bo'lsa,
--   yoki «0» bilan boshlansa, kod uning birinchi guruhi bilan davom etmaydi («+5⏎02 345 67 89» — 3 xonali kod emas, «+4⏎0 12 …» — 40 emas,
--   «+2⏎44 7700 900» — 244 emas);
--   «+44⏎+7700 900123» — ma'lum chegara (birga). 7-qoida: «+»siz yozilgan 998 kodidan keyingi «+»
--   bo'lakcha («998 +00 123 45 67», «(998) +01 234 56 78») — 998 birinchi bo'lakcha, bitta «+» va jami 12 raqam bo'lsa — butun bo'lak
--   qo'shiladi (2ea2b95 o'qigan, 1c08011 niqoblardi); kesilgan «998 +00 12 34» va «998⏎998 +00 12 34» (998 birinchi bo'lakcha emas) — oldiga
--   yana 998 qo'shilib begona raqam bo'lardi (e34959a, 10-mustaqil tekshiruv), kesilgan raqam va «+7», boshqa 1–3 raqamli bo'lakcha
--   («15 +00 …», «99 +8 00 …», «— (15). +(44)⏎00 999» — 2ea2b95 da begona +998 15 … havolasi) — qo'shilmaydi.
select string_agg(t.n || '=' || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'phone', '-') || '/'
                  || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'valid', '-'), ' | ' order by t.n)
       || ' || ' || coalesce(app.sales_parent('S', app.tg_phone('+10 ' || chr(8212) || ' 01 234 56 78'), true, '+10 ' || chr(8212) || ' 01 234 56 78') ->> 'phone', '-') as h46
  from unnest(array['+10 ' || chr(8212) || ' 01 234 56 78', '01 234 56 78' || E'\n' || '+10' || E'\n' || '02 345 67 89',
                    '+3' || E'\n' || '01 234 56 78' || E'\n' || '02 345 67 89', '+10' || E'\n' || '01 234 56 78', '+10: 01 234 56 78',
                    '+440' || E'\n' || '01 234 56 78', '00 10' || E'\n' || '01 234 56 78', '+10' || E'\n' || '01 234 56' || E'\n' || '78',
                    '(+998)' || E'\n' || '01 234 56 78', '+99' || E'\n' || '8 00 123 45 67', '+4. 4) - 7700 900123',
                    '+0' || E'\n' || '44 7700 900123', '+9' || E'\n' || '9' || E'\n' || '8 00 123 45 67',
                    '998 +00 123 45 67', '(998) +01 234 56 78', '998  +00 123 45 67', '998 + 00 123 45 67', '998 +44 7700 900123',
                    '+998 00 123 45 6' || E'\n' || '+7', chr(8212) || ' (15). +(44)' || chr(8232) || '00 999', '15 +00 123 45 67',
                    '+44' || E'\n' || '+7700 900123', '+5' || E'\n' || '02 345 67 89', '998 +00 12 34', '(998)' || E'\n' || '+01 23 45',
                    '01' || E'\n' || '998' || E'\n' || '+00 12', '(998). + 998. +00 12 34', '+4' || E'\n' || '0 12 345 67 89',
                    '998' || E'\n' || '+00 123' || E'\n' || '45 67', '99 +8 00 123 45 67', '998' || E'\n' || '998 +00 12 34',
                    '+2' || E'\n' || '44 7700 900']) with ordinality t(x, n) \gset
select zz.chk('H46 8-qoida: yozilgan kod — raqamning davlat kodi (tasodifiy «+10» / «+3» / «+440» mahalliy raqam bilan begona xorijiy raqam bo''lmaydi); bo''lingan kod, «+0» — o''qiladi; «998 +00 …» — o''qiladi',
  :'h46', '^1=\*\*\* \*\* 78/false \| 2=01 234 56 78/false \| 3=02 345 67 89/false \| 4=\*\*\* \*\* 78/false \| 5=\*\*\* \*\* 78/false \| '
       || '6=\*\*\* \*\* 78/false \| 7=\*\*\* \*\* 78/false \| 8=\*\*\* \*\* 78/false \| 9=\+998012345678/true \| 10=\+998001234567/true \| '
       || '11=\+447700900123/true \| 12=\+447700900123/true \| 13=\+998001234567/true \| 14=\+998001234567/true \| 15=\+998012345678/true \| '
       || '16=\+998001234567/true \| 17=\+998001234567/true \| 18=\+44 7700 900123/false \| 19=\*\*\* \*\* 67/false \| '
       || '20=\*\*\* \*\* 99/false \| 21=\*\*\* \*\* 67/false \| 22=\+447700900123/true \| 23=\*\*\* \*\* 89/false \| '
       || '24=\*\*\* \*\* 34/false \| 25=\*\*\* \*\* 45/false \| 26=\*\*\* \*\* 12/false \| 27=\*\*\* \*\* 34/false \| 28=\*\*\* \*\* 89/false \| '
       || '29=\+998001234567/true \| 30=\*\*\* \*\* 67/false \| 31=\*\*\* \*\* 34/false \| 32=\*\*\* \*\* 00/false \|\| \*\*\* \*\* 78$');

-- H47 — savepoint ichida (aka-uka kartalari, 9-mustaqil tekshiruv, 1c08011 ga). Ota raqami: daraja ichida avval shu darajadagi kartalar
--   soni (ona raqami bilan bir xil raqamlarda — ona katagidagi soni minus ota katagidagi soni, teng bo'lsa kamroq ona katagida turgani),
--   so'ng barcha kartalar soni: otasiz kartalardagi maktab raqami (Maktabf, Zetv), onaning ikkinchi telefoni (Ikkitel), onasi ro'yxatdan
--   o'tkazgan kartalardagi ona raqami (Onareg, Onaregm — almashgan karta bilan; raqamlar teskari tartibda ham) ismli kartalardagi
--   ko'pchilikni bosib o'tmaydi (avval maktab / ona raqami valid=true bilan otaniki bo'lib, ota-ona almashib chiqardi; 2ea2b95 da to'g'ri
--   edi). Ikkiizohc — ota raqami ikki xil izoh bilan, maktab raqami bitta ismli va ikki otasiz kartada; Tengsof — ikkala raqam ota va ona
--   ustunida teng uchraydi, kamroq ona katagida turgani — otaniki; Tengota — shu darajada teng, otasiz kartada ham yozilgan raqam (fcn)
--   — otaniki (kichik raqamli maktab raqami emas). Ona tomoni (o'zgarmagan, qo'riqlanadi): Kapv / Lamv — otaning raqami ona
--   ismi yozilgan ikki kartaning ona katagida («(otasi)», «(2-uy)», ikkala katakda bir raqam), ona raqami bitta ona ismli va ikki onasiz
--   kartada — otaning raqami onaniki bo'lib chiqmaydi; Onaro — onasi ro'yxatdan o'tkazgan kartalarda ona raqami ota katagida ham — ona
--   raqami onaniki, otaniki emas.
savepoint h47;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x47' || lpad(g::text, 2, '0'), 'IQ-X47' || lpad(g::text, 2, '0'), 'Sinov Bola X47' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 2600 + g
    from generate_series(1, 49) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x47' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Onareg','Sinov Ona Onareg','+998 00 111 22 31','+998 00 444 55 62'), (2,'Sinov Ota Onareg','Sinov Ona Onareg','+998 00 444 55 62','+998 00 111 22 31'),
  (3,'Sinov Ota Onareg',null,'+998 00 111 22 31','+998 00 444 55 62'), (4,null,'Sinov Ona Onareg','+998 00 444 55 62',null),
  (5,null,'Sinov Ona Onareg','+998 00 444 55 62',null),
  (6,'Sinov Ota Onaregm','Sinov Ona Onaregm','+998 00 444 55 63','+998 00 111 22 32'), (7,'Sinov Ota Onaregm','Sinov Ona Onaregm','+998 00 111 22 32','+998 00 444 55 63'),
  (8,'Sinov Ota Onaregm',null,'+998 00 444 55 63','+998 00 111 22 32'), (9,null,'Sinov Ona Onaregm','+998 00 111 22 32',null),
  (10,null,'Sinov Ona Onaregm','+998 00 111 22 32',null),
  (11,'Sinov Ota Maktabf','Sinov Ona Maktabf','+998 00 111 22 35','+998 00 444 55 66'), (12,'Sinov Ota Maktabf','Sinov Ona Maktabf','+998 00 111 22 35','+998 00 444 55 66'),
  (13,'Sinov Ota Maktabf','Sinov Ona Maktabf','+998 00 999 00 97','+998 00 444 55 66'), (14,null,'Sinov Ona Maktabf','+998 00 999 00 97','+998 00 444 55 66'),
  (15,null,'Sinov Ona Maktabf','+998 00 999 00 97','+998 00 444 55 66'),
  (16,'Sinov Ota Ikkitel','Sinov Ona Ikkitel','+998 00 111 22 39','+998 00 777 88 01'), (17,'Sinov Ota Ikkitel','Sinov Ona Ikkitel','+998 00 111 22 39','+998 00 777 88 01'),
  (18,'Sinov Ota Ikkitel','Sinov Ona Ikkitel','+998 00 444 55 70','+998 00 777 88 01'), (19,null,'Sinov Ona Ikkitel','+998 00 444 55 70','+998 00 777 88 01'),
  (20,null,'Sinov Ona Ikkitel','+998 00 444 55 70','+998 00 777 88 01'),
  (21,'Sinov Ota Ikkiizohc','Sinov Ona Ikkiizohc','01 234 56 64 (kv 5)','+998 00 222 33 64'), (22,'Sinov Ota Ikkiizohc','Sinov Ona Ikkiizohc','01 234 56 64 (2-uy)','+998 00 222 33 64'),
  (23,'Sinov Ota Ikkiizohc','Sinov Ona Ikkiizohc','+998 00 555 55 64','+998 00 222 33 64'), (24,null,'Sinov Ona Ikkiizohc','+998 00 555 55 64','+998 00 222 33 64'),
  (25,null,'Sinov Ona Ikkiizohc','+998 00 555 55 64','+998 00 222 33 64'),
  (26,'Sinov Ota Zetv','Sinov Ona Zetv','01 111 22 61','02 222 33 61'), (27,'Sinov Ota Zetv','Sinov Ona Zetv','01 111 22 61','02 222 33 61'),
  (28,'Sinov Ota Zetv','Sinov Ona Zetv','+998 00 999 00 61','02 222 33 61'), (29,null,'Sinov Ona Zetv','+998 00 999 00 61','02 222 33 61'),
  (30,'-','Sinov Ona Zetv','+998 00 999 00 61','02 222 33 61'),
  (31,'Sinov Ota Tengsof','Sinov Ona Tengsof','+998 00 222 33 74','+998 00 111 22 74'), (32,'Sinov Ota Tengsof','Sinov Ona Tengsof','+998 00 111 22 74','+998 00 222 33 74'),
  (33,'Sinov Ota Tengsof',null,'+998 00 222 33 74','+998 00 222 33 74'), (34,null,'Sinov Ona Tengsof','+998 00 111 22 74','+998 00 222 33 74'),
  (35,'Sinov Ota Kapv','Sinov Ona Kapv','01 333 44 62','01 333 44 62'), (36,'Sinov Ota Kapv','Sinov Ona Kapv','01 333 44 62','01 333 44 62 (otasi)'),
  (37,'Sinov Ota Kapv','Sinov Ona Kapv','01 333 44 62, 02 444 55 62','02 444 55 62'), (38,'Sinov Ota Kapv',null,'01 333 44 62','02 444 55 62'),
  (39,'Sinov Ota Kapv','-','01 333 44 62','02 444 55 62'),
  (40,'Sinov Ota Lamv','Sinov Ona Lamv','01 333 44 63','01 333 44 63 (2-uy)'), (41,null,'Sinov Ona Lamv','+998 00 999 00 63','01 333 44 63'),
  (42,'Sinov Ota Lamv','Sinov Ona Lamv','01 333 44 63','02 444 55 63'), (43,'Sinov Ota Lamv',null,'01 333 44 63','02 444 55 63'),
  (44,'Sinov Ota Lamv','-','01 333 44 63','02 444 55 63'),
  (45,null,'Sinov Ona Onaro','+998 00 222 33 76','+998 00 222 33 76'), (46,null,'Sinov Ona Onaro','+998 00 222 33 76','+998 00 222 33 76, +998 00 111 22 76'),
  (47,'Sinov Ota Tengota','Sinov Ona Tengota','+998 00 555 22 77','+998 00 333 44 77'), (48,'Sinov Ota Tengota','Sinov Ona Tengota','+998 00 111 00 77','+998 00 333 44 77'),
  (49,null,'Sinov Ona Tengota','+998 00 555 22 77','+998 00 333 44 77')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(case when x.f then coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' ' else '' end
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o) as h47
  from (values (1, 'Sinov Ota Onareg', true), (2, 'Sinov Ota Onaregm', true), (3, 'Sinov Ota Maktabf', true), (4, 'Sinov Ota Ikkitel', true),
               (5, 'Sinov Ota Ikkiizohc', true), (6, 'Sinov Ota Zetv', true), (7, 'Sinov Ota Tengsof', true), (8, 'Sinov Ota Kapv', false),
               (9, 'Sinov Ota Lamv', false), (10, 'Sinov Ona Onaro', true), (11, 'Sinov Ota Tengota', true)) x(o, n, f) \gset
rollback to savepoint h47;
select zz.chk('H47 aka-uka: daraja ichida shu darajadagi kartalar soni — otasiz kartalardagi maktab raqami, onaning ikkinchi telefoni, onasi ro''yxatdan o''tkazgan kartalar ismli kartalardagi ko''pchilikni bosib o''tmaydi; ota ustunidagi raqam onaniki bo''lib chiqmaydi',
  :'h47', '^\+998001112231 true \+998004445562 true \| \+998004445563 true \+998001112232 true \| \+998001112235 true \+998004445566 true \| '
       || '\+998001112239 true \+998007778801 true \| 01 234 56 64 false \+998002223364 true \| \+998011112261 true \+998022223361 true \| '
       || '\+998001112274 true \+998002223374 true \| \+998024445562 true \| \+998024445563 true \| - - \+998002223376 true \| '
       || '\+998005552277 true \+998003334477 true$');

-- H48 (10-mustaqil tekshiruv, 2-o'tish, 44e1049 ga). 8-qoida kod tekshiruvi o'tmasa ham butun bo'lak to'liq O'zbekiston raqami
--   (998 + 9 raqam, 998998 emas) bo'lsa — o'qiladi: raqam o'rtasidagi «00X» guruhi («01  003  45  67», «+998⏎00 476⏎47 55»; e34959a
--   va 44e1049 niqoblardi), bo'lingan 998 kodi («+99⏎8001234567»), «998⏎+02⏎345 67 89»; boshqa davlat raqami bo'lib chiqadigan butun
--   bo'lak — yo'q («0⏎003⏎01 …» -> +30 …, «998⏎998⏎003⏎456», «+4 4⏎003⏎7700 900»; 1c08011 da begona valid=true havola). Xorijiy raqam
--   ichidagi ikki bo'sh joyli «00X» guruhi («+44 7700 9  003  21») — ma'lum chegara (niqob). Bo'lak boshidagi yolg'iz koddan keyingi «00»
--   bilan boshlangan bo'lakcha (8-qoida unga qo'shmaydi) butun bo'lak bo'lib ham faqat yozilgan kod bilan o'qiladi: «+4⏎00 123 45 67»,
--   «+10⏎00 …», «+440⏎00 …», «00 4⏎(00) …», «+3⏎0 01 …» — 44e1049 va undan oldingi barcha versiyalarda begona valid=true havola edi;
--   «(+998)⏎00 …», «998⏎00 4⏎00 45 67» (kod bo'lak boshida emas), «+0⏎00 44 …» — o'qiladi; oldida faqat nolli bo'lakcha — «0⏎00 4⏎00 …» —
--   ham tekshiriladi; «+00 …» bo'lakcha ham («+4⏎+00 123 45 67» — avval begona +40 …; «+998⏎+00 …» — o'qiladi); nolli kod va undan keyingi
--   bir necha bo'lakcha — butun bo'lak («+0⏎00 44 7700 900⏎123»). 9-qoida: 3 xonali birinchi guruh «998» — operator kodi emas (998 va
--   6 raqam): «998 001 234⏎567» — butun raqam (avval birinchi qator 9 xonali mahalliy raqam bo'lib begona havola berardi).
select string_agg(t.n || '=' || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'phone', '-') || '/'
                  || coalesce(app.sales_parent('S', app.tg_phone(t.x), false, t.x) ->> 'valid', '-'), ' | ' order by t.n) as h48
  from unnest(array['01  003  45  67', '01' || E'\n' || '003' || E'\n' || '45' || E'\n' || '67', '+998  01  003  45  67',
                    '+998 00  003  23 45', '012  003  456', '+998' || E'\n' || '00 476' || E'\n' || '47 55',
                    '+99' || E'\n' || '8001234567', '998' || E'\n' || '+02' || E'\n' || '345 67 89', '998 001 234' || E'\n' || '567',
                    '0' || E'\n' || '003' || E'\n' || '01 234 56 78', '998' || E'\n' || '998' || E'\n' || '003' || E'\n' || '456',
                    '+4 4' || E'\n' || '003' || E'\n' || '7700 900', '+44 7700 9  003  21',
                    '+4' || E'\n' || '00 123 45 67', '+10' || E'\n' || '00 123 45 67', '+440' || E'\n' || '00 123 45 67',
                    '00 4' || E'\n' || '(00) 123-45-67', '+3' || E'\n' || '0 01 234 56 78', '+4' || E'\n' || '00 123 45 67, 01 234 56 79',
                    '+4' || E'\n' || '00 12 345 67 89', '(+998)' || E'\n' || '00 123 45 67', '+44' || E'\n' || '0044 7700 900123',
                    '+0' || E'\n' || '00 44 7700 900123', '998' || E'\n' || '00 4' || E'\n' || '00 45 67',
                    '0' || E'\n' || '00 4' || E'\n' || '00 123 45 67', '+4' || E'\n' || '+00 123 45 67',
                    '+0' || E'\n' || '00 44 7700 900' || E'\n' || '123', '+998' || E'\n' || '+00 123 45 67']) with ordinality t(x, n) \gset
select zz.chk('H48 8-qoida: kod tekshiruvi o''tmasa ham butun bo''lak to''liq O''zbekiston raqami bo''lsa — o''qiladi («00X» guruhi, bo''lingan 998 kodi); yolg''iz koddan keyingi «00» bo''lakcha begona raqam bo''lmaydi; «998 xxx xxx» — mahalliy raqam emas',
  :'h48', '^1=\+998010034567/true \| 2=\+998010034567/true \| 3=\+998010034567/true \| 4=\+998000032345/true \| 5=\+998012003456/true \| '
       || '6=\+998004764755/true \| 7=\+998001234567/true \| 8=\+998023456789/true \| 9=\+998001234567/true \| 10=\*\*\* \*\* 78/false \| '
       || '11=\*\*\* \*\* 56/false \| 12=\*\*\* \*\* 00/false \| 13=\*\*\* \*\* 21/false \| 14=\*\*\* \*\* 67/false \| 15=\*\*\* \*\* 67/false \| '
       || '16=\*\*\* \*\* 67/false \| 17=\*\*\* \*\* 67/false \| 18=\*\*\* \*\* 78/false \| 19=01 234 56 79/false \| 20=\*\*\* \*\* 89/false \| '
       || '21=\+998001234567/true \| 22=0044 7700 900123/false \| 23=\+447700900123/true \| 24=\+998004004567/true \| 25=\*\*\* \*\* 67/false \| '
       || '26=\*\*\* \*\* 67/false \| 27=\+447700900123/true \| 28=\+998001234567/true$');

-- H49 — savepoint ichida (aka-uka kartalari, 10-mustaqil tekshiruv, 2-o'tish, 44e1049 ga). Ota raqamining daraja ichidagi soni (fct)
--   shu ism sinfidagi kartalarni har qanday yozuvda sanaydi: «+»siz yozilgan xorijiy raqam («447700900141», «44 7700 900141»,
--   «(44) 7700 900142») yoki so'zga yopishgan raqam («+998 00 111 22 43dadasi», «tel998001112243») qo'ng'iroq qilib bo'lmaydi (4-daraja),
--   lekin kanonigi otaning qo'ng'iroq raqami bilan bir xil. e34959a / 44e1049 faqat qo'ng'iroq qilinadigan yozuvlarni sanab, ota ismli
--   ikki kartadagi bobosi raqamini (Plussiz) yoki ona raqamini (Plussizm, Plussizn, Yopishiq — ota ham, ona ham bir raqam) otaniki qilardi;
--   Plussizb — ota ismi yozilmagan kartalar (2-daraja) ham shunday. Plussizc — ota ismli kartalarda raqam faqat «+»siz yozilgan, «+» bilan
--   — ota ismsiz bitta kartada: 2-darajada ota ismli kartalarda ko'proq turgani (fnm) qarindosh raqamidan ustun. Nolguruh — «01  003  45  67»
--   (H48) oila darajasida ham to'g'ri raqam (ro'yxatda «+998 01 *** ** 67»); Kodli — «+4⏎00 123 45 67» begona raqam emas, ota raqami —
--   aka-ukasining kartasidagi to'g'ri raqam. Ikkiyozuv — ikki raqamli katak («+44 …; +998 …», ichida ona raqami) va xuddi shu raqamlar
--   yopishgan «+»siz katak (to'g'ri bitta raqam emas) qo'shib sanalmaydi: ota raqami — ikki kartadagi toza raqam, ona raqami ota
--   ro'yxatida chiqmaydi; Ikkiyozuvb — xuddi shunday, 2-darajada (fnm ham faqat to'g'ri bitta raqam uchun). Plussizd — 2-darajada ota ismli
--   kartalarda turgan raqam (fnm) qarindoshning uchta ismsiz kartadagi raqamidan ustun (barcha kartalar soni emas — u teng: 3 va 3).
savepoint h49;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x49' || lpad(g::text, 2, '0'), 'IQ-X49' || lpad(g::text, 2, '0'), 'Sinov Bola X49' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 2800 + g
    from generate_series(1, 50) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x49' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Plussiz','Sinov Ona Plussiz','+44 7700 900141','+998 00 222 33 41'), (2,'Sinov Ota Plussiz','Sinov Ona Plussiz','447700900141','+998 00 222 33 41'),
  (3,'Sinov Ota Plussiz','Sinov Ona Plussiz','44 7700 900141','+998 00 222 33 41'), (4,'Sinov Ota Plussiz','Sinov Ona Plussiz','+998 00 555 66 41','+998 00 222 33 41'),
  (5,'Sinov Ota Plussiz','Sinov Ona Plussiz','+998 00 555 66 41','+998 00 222 33 41'),
  (6,'Sinov Ota Plussizm',null,'+44 7700 900142','01 234 56 42'), (7,'Sinov Ota Plussizm',null,'44 7700 900142','01 234 56 42'),
  (8,'Sinov Ota Plussizm',null,'(44) 7700 900142','01 234 56 42'), (9,'Sinov Ota Plussizm','Sinov Ona Plussizm','01 234 56 42',null),
  (10,'Sinov Ota Plussizm','Sinov Ona Plussizm','01 234 56 42',null),
  (11,'Sinov Ota Plussizn',null,'+44 7700 900145','+998 00 222 33 45'), (12,'Sinov Ota Plussizn',null,'447700900145','+998 00 222 33 45'),
  (13,'Sinov Ota Plussizn',null,'44 7700 900145','+998 00 222 33 45'), (14,'Sinov Ota Plussizn',null,'+998 00 222 33 45','+998 00 222 33 45'),
  (15,'Sinov Ota Plussizn',null,'+998 00 222 33 45','+998 00 222 33 45'),
  (16,'Sinov Ota Yopishiq',null,'+998 00 111 22 43','02 345 67 43'), (17,'Sinov Ota Yopishiq',null,'+998 00 111 22 43dadasi','02 345 67 43'),
  (18,'Sinov Ota Yopishiq',null,'tel998001112243','02 345 67 43'), (19,'Sinov Ota Yopishiq',null,'02 345 67 43','02 345 67 43'),
  (20,'Sinov Ota Yopishiq',null,'02 345 67 43','02 345 67 43'),
  (21,null,'Sinov Ona Plussizb','+44 7700 900124','+998 00 222 33 44'), (22,null,'Sinov Ona Plussizb','447700900124','+998 00 222 33 44'),
  (23,null,'Sinov Ona Plussizb','44 7700 900124','+998 00 222 33 44'), (24,null,'Sinov Ona Plussizb','+998 00 555 66 78','+998 00 222 33 44'),
  (25,null,'Sinov Ona Plussizb','+998 00 555 66 78','+998 00 222 33 44'),
  (26,'Sinov Ota Plussizc','Sinov Ona Plussizc','447700900151','+998 00 222 33 51'), (27,'Sinov Ota Plussizc','Sinov Ona Plussizc','44 7700 900151','+998 00 222 33 51'),
  (28,null,'Sinov Ona Plussizc','+44 7700 900151','+998 00 222 33 51'), (29,null,'Sinov Ona Plussizc','+998 00 555 66 51','+998 00 222 33 51'),
  (30,null,'Sinov Ona Plussizc','+998 00 555 66 51','+998 00 222 33 51'),
  (31,'Sinov Ota Nolguruh','Sinov Ona Nolguruh','01  003  45  67','+998 00 222 33 47'),
  (32,'Sinov Ota Nolguruh','Sinov Ona Nolguruh','01' || E'\n' || '003' || E'\n' || '45' || E'\n' || '67','+998 00 222 33 47'),
  (33,'Sinov Ota Kodli','Sinov Ona Kodli','+4' || E'\n' || '00 123 45 67','+998 00 222 33 48'),
  (34,'Sinov Ota Kodli','Sinov Ona Kodli','+4' || E'\n' || '00 123 45 67','+998 00 222 33 48'),
  (35,'Sinov Ota Kodli','Sinov Ona Kodli','+998 00 765 43 21','+998 00 222 33 48'),
  (36,'Sinov Ota Ikkiyozuv','Sinov Ona Ikkiyozuv','+44 7700 900144; +998 00 222 33 49','+998 00 222 33 49'),
  (37,'Sinov Ota Ikkiyozuv','Sinov Ona Ikkiyozuv','447700900144 998002223349','+998 00 222 33 49'),
  (38,'Sinov Ota Ikkiyozuv','Sinov Ona Ikkiyozuv','447700900144 998002223349','+998 00 222 33 49'),
  (39,'Sinov Ota Ikkiyozuv','Sinov Ona Ikkiyozuv','+998 00 111 22 49','+998 00 222 33 49'),
  (40,'Sinov Ota Ikkiyozuv','Sinov Ona Ikkiyozuv','+998 00 111 22 49','+998 00 222 33 49'),
  (41,null,'Sinov Ona Ikkiyozuvb','+44 7700 900146; +998 00 222 33 46','+998 00 222 33 46'),
  (42,'Sinov Ota Ikkiyozuvb','Sinov Ona Ikkiyozuvb','447700900146 998002223346','+998 00 222 33 46'),
  (43,null,'Sinov Ona Ikkiyozuvb','+998 00 111 22 46','+998 00 222 33 46'), (44,null,'Sinov Ona Ikkiyozuvb','+998 00 111 22 46','+998 00 222 33 46'),
  (45,'Sinov Ota Plussizd','Sinov Ona Plussizd','447700900152','+998 00 222 33 52'), (46,'Sinov Ota Plussizd','Sinov Ona Plussizd','44 7700 900152','+998 00 222 33 52'),
  (47,null,'Sinov Ona Plussizd','+44 7700 900152','+998 00 222 33 52'), (48,null,'Sinov Ona Plussizd','+998 00 555 66 52','+998 00 222 33 52'),
  (49,null,'Sinov Ona Plussizd','+998 00 555 66 52','+998 00 222 33 52'), (50,null,'Sinov Ona Plussizd','+998 00 555 66 52','+998 00 222 33 52')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o)
       || ' || ' || coalesce((select r -> 'father' ->> 'phone' from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal('Sinov Ota Nolguruh')) -> 'rows', '[]'::jsonb)) r
                               where r -> 'father' ->> 'name' = 'Sinov Ota Nolguruh' limit 1), '-') as h49
  from (values (1, 'Sinov Ota Plussiz'), (2, 'Sinov Ota Plussizm'), (3, 'Sinov Ota Plussizn'), (4, 'Sinov Ota Yopishiq'), (5, 'Sinov Ona Plussizb'),
               (6, 'Sinov Ota Plussizc'), (7, 'Sinov Ota Nolguruh'), (8, 'Sinov Ota Kodli'), (9, 'Sinov Ota Ikkiyozuv'),
               (10, 'Sinov Ona Ikkiyozuvb'), (11, 'Sinov Ota Plussizd')) x(o, n) \gset
rollback to savepoint h49;
select zz.chk('H49 aka-uka: ota raqamining soni — shu ism sinfidagi kartalar har qanday yozuvda («+»siz xorijiy, so''zga yopishgan); bobosi / qarindosh / ona raqami otaniki bo''lib chiqmaydi; «01  003  45  67», «+4⏎00 …» oila darajasida',
  :'h49', '^\+447700900141 true \+998002223341 true \| \+447700900142 true \+998012345642 true \| \+447700900145 true \+998002223345 true \| '
       || '\+998001112243 true \+998023456743 true \| \+447700900124 true \+998002223344 true \| \+447700900151 true \+998002223351 true \| '
       || '\+998010034567 true \+998002223347 true \| \+998007654321 true \+998002223348 true \| \+998001112249 true \+998002223349 true \| '
       || '\+998001112246 true \+998002223346 true \| \+447700900152 true \+998002223352 true \|\| \+998 01 \*\*\* \*\* 67$');

-- H50 — savepoint ichida (aka-uka kartalari, 11-mustaqil tekshiruv, 67b0e73 ga). Ota ismli kartalarda otaning raqami faqat qo'ng'iroq
--   qilib bo'lmaydigan yozuvda («447700900198» — «+»siz xorijiy, «… 99dadasi» — so'zga yopishgan; 4-daraja), ona raqami esa ona ismli
--   barcha kartalarda va bitta kartaning ota katagida (3-daraja): «foydalanib bo'ladigan» 3-daraja 4-darajadan oldin turgani uchun ona
--   raqami otaniki ham bo'lib chiqardi (ota ham, ona ham bitta raqam — eng og'ir). Nolguruhm / Nolguruhl — ota katagidagi ona raqami
--   8-qoida bilan endi o'qiladigan «+998⏎00 006⏎22 98» / «02  003  01  99» (44e1049 niqoblardi — ota ustunida otaning raqami chiqardi;
--   67b0e73 regressiyasi); Plusiz / Yopishf — ona raqami odatdagi yozuvda (1c08011, 44e1049, 67b0e73 — hammasida). Endi telefon ko'rinishidagi
--   (998 + 9 raqam yoki ma'lum davlat kodi va uzunligi) va kamida ikki ota ismli kartadagi 4-daraja raqami 3-darajaga qo'shiladi: ona ismli
--   barcha kartalarning ona katagida turgan, ona ustunida ko'proq raqam (aniq ona raqami) undan — ota ismli kartalarda (har qanday yozuvda)
--   ko'p bo'lmasa — ustun emas. Qo'riqlanadi: Famfs — otaning qo'ng'iroq raqami ota ismli to'rt kartada (uchtasida ikkala katakda), «+»siz
--   xorijiy raqam ikkitasida — ota raqami otaniki qoladi, ona raqami onasiz kartadan; Gtierc — 3-darajadagi raqam ona ustunini to'liq
--   egallamagan (ona ismli kartada boshqa raqam ham bor) — o'zgarmaydi; Nolj — «0» telefon ko'rinishida emas; Birkarta — bitta karta (1:1) —
--   o'zgarmaydi (oilaning yagona umumiy raqami); Umumt — ikkala katakdagi umumiy raqam ota katagida ona katagidan kam emas (2:2 teng) —
--   o'zgarmaydi; Boshkat — ona ismli kartaning bo'sh ona katagi «ona ismli barcha kartalar»ga sanalmaydi (dalil emas); Oltinchi — ona
--   raqami ota ismli kartalarda qo'ng'iroq qilib bo'lmaydigan yozuvda (6-daraja) — 3-darajaga ko'tarilmaydi, otaning 4-darajadagi raqami
--   oldin. 12-mustaqil tekshiruv (8f9925d ga): Otasib / Oltita — ona ismli barcha kataklarda otaning raqami «(otasi)», onaning raqami
--   onasiz kartada (ota katagida — ota raqami, ona katagida — boshqa raqam: ajratuvchi karta) — ota raqami otaniki qoladi (8f9925d da ota
--   ismli kartalardagi «+»siz uchinchi raqam otaniki, ota raqami onaniki bo'lardi; 67b0e73 to'g'ri edi), uchinchi raqam ikki (teng) va uch
--   kartada; Almash — raqamlari almashgan bitta karta (ota katagida ona raqami, ona katagida ota raqami) ajratuvchi emas (67b0e73 ota va
--   onani almashtirardi); Boshkat — bo'sh ona katagi ham ajratuvchi emas; Otasib dagi otasiz ('-') kartaning ota katagidagi ona raqami
--   almashuv belgisi emas (faqat ota ismli kartaning ota katagi); Famfsb — ona ustunini to'liq egallagan raqam ota ismli kartalarda
--   «+»siz raqamdan ko'proq bo'lsa — otaniki qoladi (avval ota ismli kartalardagi soni, net emas); Xorsep — ajratuvchi kartaning ona
--   katagida xorijiy telefon raqami («+44 7700 900 243») ham ajratadi; Izohsep — izohli 13 xonali yozuv («0044 7700 900752 (2)»,
--   hujjat raqamiga o'xshash) ajratuvchi emas: ona raqami ota ismli kartaning ota katagida bo'lsa ham otaniki bo'lmaydi, «+»siz / so'zga
--   yopishgan ota raqami otaniki. 13-mustaqil tekshiruv (025c023 ga): ajratuvchi karta raqamni «aniq ona raqami» sifatida
--   pasaytirishdan faqat biror ona ismli katakda shu raqam ota so'zi bilan («(otasi)») yozilgan bo'lsa himoyalaydi, ona katagidagi har
--   bir raqam tekshiriladi: Ikkimc / Ikkimd — onasiz kartaning ona katagida ikki raqam (025c023 ularni sanamay, ota qatorida «+»siz
--   uchinchi raqamni, ona qatorida otaning raqamini ko'rsatardi); Ajrat — Oltita, lekin ota so'zisiz («o'ta muhim», «Otabek», «Shota» — emas): ona ismli barcha
--   kataklardagi raqam onaniki (025c023 da ona ismsiz kartaning ona katagidagi maktab raqami uni «ajratib», ota qatorida onaning
--   raqami chiqardi; 8f9925d to'g'ri edi). Ota so'zining boshqa shakllari: Otasib — «(otasining)», Xorsep — «(ОТАСИНИНГ)»,
--   Ikkimc — «(отца)», Ikkimd — «(Papasi)».
savepoint h50;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x50' || lpad(g::text, 2, '0'), 'IQ-X50' || lpad(g::text, 2, '0'), 'Sinov Bola X50' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 2900 + g
    from generate_series(1, 81) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x50' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Nolguruhm','Sinov Ona Nolguruhm','447700900198','+998 00 006 22 98'),
  (2,'Sinov Ota Nolguruhm','Sinov Ona Nolguruhm','447700900198','+998 00 006 22 98'),
  (3,'Sinov Ota Nolguruhm','Sinov Ona Nolguruhm','+998' || E'\n' || '00 006' || E'\n' || '22 98','+998 00 006 22 98'),
  (4,'Sinov Ota Nolguruhl','Sinov Ona Nolguruhl','+998 01 149 35 99dadasi','02 003 01 99'),
  (5,'Sinov Ota Nolguruhl','Sinov Ona Nolguruhl','+998 01 149 35 99dadasi','02 003 01 99'),
  (6,'Sinov Ota Nolguruhl','Sinov Ona Nolguruhl','02  003  01  99','02 003 01 99'),
  (7,'Sinov Ota Plusiz','Sinov Ona Plusiz','447700900184','+998 00 222 33 84'),
  (8,'Sinov Ota Plusiz','Sinov Ona Plusiz','447700900184','+998 00 222 33 84'),
  (9,'Sinov Ota Plusiz','Sinov Ona Plusiz','447700900184','+998 00 222 33 84'),
  (10,'Sinov Ota Plusiz','Sinov Ona Plusiz','+998 00 222 33 84','+998 00 222 33 84'),
  (11,'Sinov Ota Yopishf','Sinov Ona Yopishf','+998 00 111 22 86dadasi','02 345 67 86'),
  (12,'Sinov Ota Yopishf','Sinov Ona Yopishf','+998 00 111 22 86dadasi','02 345 67 86'),
  (13,'Sinov Ota Yopishf','Sinov Ona Yopishf','+998 00 111 22 86dadasi','02 345 67 86'),
  (14,'Sinov Ota Yopishf','Sinov Ona Yopishf','02 345 67 86','02 345 67 86'),
  (15,'Sinov Ota Famfs','Sinov Ona Famfs','+998 00 333 44 81','+998 00 333 44 81'),
  (16,'Sinov Ota Famfs','Sinov Ona Famfs','+998 00 333 44 81','+998 00 333 44 81'),
  (17,'Sinov Ota Famfs','Sinov Ona Famfs','+998 00 333 44 81','+998 00 333 44 81'),
  (18,'Sinov Ota Famfs','Sinov Ona Famfs','447700900181','+998 00 333 44 81'),
  (19,'Sinov Ota Famfs','Sinov Ona Famfs','447700900181','+998 00 333 44 81'),
  (20,'Sinov Ota Famfs',null,'+998 00 333 44 81','+998 00 777 88 81'),
  (21,'Sinov Ota Gtierc',null,'44 7700 900877','+998 02 567 44 52'),
  (22,'Sinov Ota Gtierc',null,'+998029707845oyisi','+44 7700 900877'),
  (23,'Sinov Ota Gtierc','Sinov Ona Gtierc','ota02 970 78 45','44-7700-900877'),
  (24,'-','Sinov Ona Gtierc','44-7700-900877','(02) 567-44-52'),
  (25,null,'Sinov Ona Gtierc','+44 7700 900877','ota998 02 567 44 52'),
  (26,'Sinov Ota Gtierc','Sinov Ona Gtierc','+998 02 567 44 52','+998 02 567 44 52'),
  (27,'Sinov Ota Nolj','Sinov Ona Nolj','0','+998 00 444 55 72'),
  (28,'Sinov Ota Nolj','Sinov Ona Nolj','0','+998 00 444 55 72'),
  (29,'Sinov Ota Nolj','Sinov Ona Nolj','+998 00 444 55 72','+998 00 444 55 72'),
  (30,'Sinov Ota Birkarta','Sinov Ona Birkarta','447700900174','+998 00 666 77 74'),
  (31,'Sinov Ota Birkarta','Sinov Ona Birkarta','+998 00 666 77 74','+998 00 666 77 74'),
  (32,'Sinov Ota Umumt','Sinov Ona Umumt','+998 00 555 66 83','+998 00 555 66 83'),
  (33,'Sinov Ota Umumt','Sinov Ona Umumt','+998 00 555 66 83','+998 00 555 66 83'),
  (34,'Sinov Ota Umumt',null,'447700900183','+998 00 555 66 83'),
  (35,'Sinov Ota Umumt',null,'447700900183','+998 00 555 66 83'),
  (36,'Sinov Ota Boshkat','Sinov Ona Boshkat','447700900176','+998 00 006 22 76'),
  (37,'Sinov Ota Boshkat','Sinov Ona Boshkat','447700900176','+998 00 006 22 76'),
  (38,'Sinov Ota Boshkat','Sinov Ona Boshkat','+998 00 006 22 76','+998 00 006 22 76'),
  (39,'Sinov Ota Boshkat','Sinov Ona Boshkat','+998 00 006 22 76',''),
  (40,'Sinov Ota Oltinchi','Sinov Ona Oltinchi','447700900178','+998 00 006 22 79'),
  (41,'Sinov Ota Oltinchi','Sinov Ona Oltinchi','447700900178','+998 00 006 22 79'),
  (42,'Sinov Ota Oltinchi','Sinov Ona Oltinchi','+998 00 006 22 79oyisi','+998 00 006 22 79'),
  (43,'Sinov Ota Oltinchi','Sinov Ona Oltinchi','+998 00 006 22 79oyisi','+998 00 006 22 79'),
  (44,'Sinov Ota Otasib','Sinov Ona Otasib','+998 00 111 21 31','+998 00 111 21 31 (otasining)'),
  (45,'Sinov Ota Otasib','Sinov Ona Otasib','447700900131','+998 00 111 21 31 (otasining)'),
  (46,'Sinov Ota Otasib','Sinov Ona Otasib','447700900131','+998 00 111 21 31 (otasining)'),
  (47,'Sinov Ota Otasib',null,'+998 00 111 21 31','+998 00 222 42 37'),
  (48,'Sinov Ota Oltita','Sinov Ona Oltita','447700900136','+998 00 111 21 36 (otasi)'),
  (49,'Sinov Ota Oltita','Sinov Ona Oltita','447700900136','+998 00 111 21 36 (otasi)'),
  (50,'Sinov Ota Oltita','Sinov Ona Oltita','447700900136','+998 00 111 21 36 (otasi)'),
  (51,'Sinov Ota Oltita',null,'+998 00 111 21 36','+998 00 222 42 42'),
  (52,null,'Sinov Ona Almash','447700900139','+998 00 222 42 43'),
  (53,'Sinov Ota Almash','Sinov Ona Almash','44 7700 900139 (otasi)','+998 00 222 42 43'),
  (54,'Sinov Ota Almash','Sinov Ona Almash','447700900139','+998 00 222 42 43'),
  (55,'Sinov Ota Almash',null,'+998 00 222 42 43','44-7700-900139'),
  (56,'-','Sinov Ona Otasib','+998 00 222 42 37ona','+998 00 111 21 31 (otasining)'),
  (57,'Sinov Ota Famfsb','Sinov Ona Famfsb','+998 00 333 44 91','+998 00 333 44 91'),
  (58,'Sinov Ota Famfsb','Sinov Ona Famfsb','+998 00 333 44 91','+998 00 333 44 91'),
  (59,'Sinov Ota Famfsb','Sinov Ona Famfsb','+998 00 333 44 91','+998 00 333 44 91'),
  (60,'Sinov Ota Famfsb','Sinov Ona Famfsb','447700900191','+998 00 333 44 91'),
  (61,'Sinov Ota Famfsb','Sinov Ona Famfsb','447700900191','+998 00 333 44 91'),
  (62,'Sinov Ota Xorsep','Sinov Ona Xorsep','447700900137','+998 00 111 21 37 (ОТАСИНИНГ)'),
  (63,'Sinov Ota Xorsep','Sinov Ona Xorsep','447700900137','+998 00 111 21 37 (ОТАСИНИНГ)'),
  (64,'Sinov Ota Xorsep','Sinov Ona Xorsep','447700900137','+998 00 111 21 37 (ОТАСИНИНГ)'),
  (65,'Sinov Ota Xorsep',null,'+998 00 111 21 37','+44 7700 900 243'),
  (66,'Sinov Ota Izohsep','Sinov Ona Izohsep','447700900651','44 7700 900752'),
  (67,'Sinov Ota Izohsep','Sinov Ona Izohsep','-','+44 7700 900 752'),
  (68,'Sinov Ota Izohsep','-','+44 7700 900752','0044 7700 900752 (2)'),
  (69,'Sinov Ota Izohsep','-','+44 7700 900651ota','+447700900752'),
  (70,'Sinov Ota Ikkimc','Sinov Ona Ikkimc','+998 00 111 21 51','+998 00 111 21 51 (отца)'),
  (71,'Sinov Ota Ikkimc','Sinov Ona Ikkimc','447700900157','+998 00 111 21 51 (отца)'),
  (72,'Sinov Ota Ikkimc','Sinov Ona Ikkimc','447700900157','+998 00 111 21 51 (отца)'),
  (73,'Sinov Ota Ikkimc',null,'+998 00 111 21 51','+998 00 222 42 57, +998 00 999 00 57'),
  (74,'Sinov Ota Ikkimd','Sinov Ona Ikkimd','+998 00 111 21 58','+998 00 111 21 58 (Papasi)'),
  (75,'Sinov Ota Ikkimd','Sinov Ona Ikkimd','447700900158','+998 00 111 21 58 (Papasi)'),
  (76,'Sinov Ota Ikkimd','Sinov Ona Ikkimd','447700900158','+998 00 111 21 58 (Papasi)'),
  (77,'Sinov Ota Ikkimd',null,'+998 00 111 21 58','+998 00 222 42 58; +998 00 111 21 58'),
  (78,'Sinov Ota Ajrat','Sinov Ona Ajrat','447700900174','+998 00 222 33 61 (o''ta muhim)'),
  (79,'Sinov Ota Ajrat','Sinov Ona Ajrat','447700900174','+998 00 222 33 61 (Otabek)'),
  (80,'Sinov Ota Ajrat','Sinov Ona Ajrat','447700900174','+998 00 222 33 61 Shota'),
  (81,'Sinov Ota Ajrat',null,'+998 00 222 33 61','+998 00 999 00 31')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o)
       || ' || ' || coalesce((select (r -> 'father' ->> 'phone') || ' ' || (r -> 'mother' ->> 'phone')
                                from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal('Sinov Ota Nolguruhm')) -> 'rows', '[]'::jsonb)) r
                               where r -> 'father' ->> 'name' = 'Sinov Ota Nolguruhm' limit 1), '-') as h50
  from (values (1, 'Sinov Ota Nolguruhm'), (2, 'Sinov Ota Nolguruhl'), (3, 'Sinov Ota Plusiz'), (4, 'Sinov Ota Yopishf'),
               (5, 'Sinov Ota Famfs'), (6, 'Sinov Ota Gtierc'), (7, 'Sinov Ota Nolj'), (8, 'Sinov Ota Birkarta'), (9, 'Sinov Ota Umumt'),
               (10, 'Sinov Ota Boshkat'), (11, 'Sinov Ota Oltinchi'), (12, 'Sinov Ota Otasib'), (13, 'Sinov Ota Oltita'), (14, 'Sinov Ota Almash'),
               (15, 'Sinov Ota Famfsb'), (16, 'Sinov Ota Xorsep'), (17, 'Sinov Ota Izohsep'), (18, 'Sinov Ota Ikkimc'),
               (19, 'Sinov Ota Ikkimd'), (20, 'Sinov Ota Ajrat')) x(o, n) \gset
rollback to savepoint h50;
select zz.chk('H50 aka-uka: ota ismli kartalarda faqat qo''ng''iroq qilib bo''lmaydigan yozuvdagi ota raqami — ona ustunini to''liq egallagan ona raqami (ota katagidagi «00X» guruhli ham) otaniki bo''lib chiqmaydi; ota ismli kartalarda ko''proq turgan qo''ng''iroq raqami, «0», bitta karta — o''zgarmaydi; umumiy raqam ota katagida kam bo''lmasa — o''zgarmaydi',
  :'h50', '^\*\*\* \*\* 98 false \+998000062298 true \| \*\*\* \*\* 99 false \+998020030199 true \| \*\*\* \*\* 84 false \+998002223384 true \| '
       || '\*\*\* \*\* 86 false \+998023456786 true \| \+998003334481 true \+998007778881 true \| \+998025674452 true \+447700900877 true \| '
       || '\+998004445572 true \+998004445572 true \| \+998006667774 true \+998006667774 true \| \+998005556683 true \+998005556683 true \| '
       || '\*\*\* \*\* 76 false \+998000062276 true \| \*\*\* \*\* 78 false \+998000062279 true \| '
       || '\+998001112131 true \+998002224237 true \| \+998001112136 true \+998002224242 true \| \*\*\* \*\* 39 false \+998002224243 true \| '
       || '\+998003334491 true \+998003334491 true \| '
       || '\+998001112137 true \+447700900243 true \| \*\*\* \*\* 51 false \+447700900752 true \| '
       || '\+998001112151 true \+998 00 222 42 57, \+998 00 999 00 57 false \| \+998001112158 true \+998 00 222 42 58, \+998 00 111 21 58 false \| '
       || '\*\*\* \*\* 74 false \+998002223361 true \|\| '
       || '\*\*\* \*\* 98 \+998 00 \*\*\* \*\* 98$');

-- H51 — savepoint ichida (aka-uka kartalari, 11-mustaqil tekshiruv, 67b0e73 ga). Ochilganda ko'rsatiladigan asl yozuv (frw / mrw):
--   tanlangan raqamning butun katak kanonigi bir xil, lekin turlicha o'qiladigan kataklar (so'zga yopishgan / «+»siz qism) bo'lsa — avval
--   katakdagi barcha raqamlar qo'ng'iroq qilinadigan katak (ikki raqamli), bo'lmasa qo'ng'iroq kanonigi (fc / mc) tanlangan raqamniki
--   bo'lgan katak. 67b0e73, 44e1049, 1c08011 yozuvni faqat butun katak kanonigi bo'yicha tanlab, alifbo bo'yicha birinchi katakni
--   ko'rsatardi: Yozuvd / Yozuve — ota qatorida faqat ona raqami (tel: havola, ro'yxatda «+998 01 *** ** 93»); Yozuvf — ona qatorida faqat
--   ota raqami; Yozuvi / Yozuvj — tanlangan raqam qo'ng'iroq qilinmaydigan katakda (boshqa daraja), ko'rsatilgani esa — ikkinchi ota-onaning
--   qo'ng'iroq raqami. Yozuvg / Yozuvh — faqat qo'ng'iroq kanonigi bo'yicha tanlash (guruhning min(fc) / min(mc)) xatosi: ona qatorida
--   faqat ota raqami / ota qatorida faqat ikkinchi raqami (asosiy raqam yo'qolardi) — chiqmaydi. Zaxira — ota nomzodi yo'q (otasiz
--   kartalardagi raqamlar ona ismli kataklarda ham bor), zaxira tanlovi (fpf) guruhida izohli qo'ng'iroq yozuvi va shu raqamlardan
--   iborat qo'ng'iroq qilib bo'lmaydigan yozuv: qo'ng'iroq yozuvi ko'rsatiladi. 12-mustaqil tekshiruv (8f9925d ga; guruh vakili — ikkinchi
--   ota-ona ustunida kamroq uchraydigan, so'ng ko'proq uchragan o'qish): Uchona / Tortona — ona guruhida 2:1 / 4:1, ozchilikdagi o'qish —
--   otaning raqami (8f9925d eng kichigini olib, ona qatorida otaning raqamini ko'rsatardi) — ona qatorida onaning, ota qatorida (zaxira)
--   otaning raqami; Ikkiota — ota guruhida ozchilikdagi o'qish ona raqami; Mosl — ona tomonidagi istisno ota qatorida ko'rsatiladigan raqam
--   bilan (67b0e73 da ikkala qatorda ham otaning raqami); Xorota — ota guruhida ko'pchilik o'qish ona raqami (otaning «+»siz qismi
--   o'qilmaydi) — faqat ko'proq uchragani olinganda ota qatorida ona raqami chiqardi; Ikkiona — ona guruhida 2:1, ikkala o'qish ota
--   ustunida yo'q — ko'proq uchragani (eng kichigi emas); Otasiz — ota ismi yozilmagan oila: ota kataklarida otaning raqami, ona
--   kataklarida ikkala raqam (biri so'zga yopishgan; otaning raqami ikki katakda qo'ng'iroq qilinadigan) — ikkala o'qish ota nomzodi
--   kataklarida yo'q (otaning raqami ona katagida ham bo'lgani uchun otasiz kartalar nomzod emas), shunda ota ustunida ko'proq, ona ismli
--   kartalarda kamroq turgan o'qish guruhda ko'p bo'lsa ham ona qatorida ko'rsatilmaydi: ona qatorida onaning, ota qatorida (zaxira)
--   otaning raqami (8f9925d ona qatorida otaning raqamini ko'rsatardi, 67b0e73 da ota qatori bo'sh edi); Yozuvg da ham shu sababli ota
--   qatorida endi otaning raqami; Yopish — ona ismli ikki kartada ona raqami, bittasida va onasiz uch kartada uchinchi raqam qo'ng'iroq
--   qilinadigan (ikkinchisi so'zga yopishgan) — ona ustunidagi umumiy son emas, ona ismli kartalardagi soni (67b0e73 ona qatorida uchinchi
--   raqamni ko'rsatardi); Kopyop — ona ismli besh kartadan ikkitasida ikkala raqam (birida ona raqami, ikkinchisida uchinchi raqam so'zga
--   yopishgan), uchtasida faqat so'zga yopishgan ona raqami — ona guruhida 1:1, ona ismli kartalarda ona raqami ko'p: ona qatorida onaning
--   raqami (8f9925d eng kichigini — uchinchi raqamni ko'rsatardi; 67b0e73 to'g'ri edi); Otaona — ona raqami ikki otasiz kartaning ota
--   katagida (ota nomzodi emas), ona guruhida ona raqami va uchinchi raqam 1:1 — barcha ota kataklari bo'yicha birinchi sanalsa ona raqami
--   jazolanib, uchinchi raqam chiqardi (67b0e73 ham uchinchi raqamni ko'rsatardi).
savepoint h51;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x51' || lpad(g::text, 2, '0'), 'IQ-X51' || lpad(g::text, 2, '0'), 'Sinov Bola X51' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 3000 + g
    from generate_series(1, 74) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x51' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Yozuvd','Sinov Ona Yozuvd','+44 7700 900193','+998 01 483 17 93'),
  (2,'Sinov Ota Yozuvd','Sinov Ona Yozuvd','+44 7700 900193, +998 01 483 17 93dadasi','+998 01 483 17 93'),
  (3,'Sinov Ota Yozuvd','Sinov Ona Yozuvd','+44 7700 900193; +998 01 483 17 93','+998 01 483 17 93'),
  (4,'Sinov Ota Yozuvd','Sinov Ona Yozuvd','(44) 7700 900193; 998014831793','+998 01 483 17 93'),
  (5,'Sinov Ota Yozuve','Sinov Ona Yozuve','+44 7700 900194, +998 01 483 17 94','+998 01 483 17 94'),
  (6,'Sinov Ota Yozuve','Sinov Ona Yozuve','+44 7700 900194; +998 01 483 17 94','+998 01 483 17 94'),
  (7,'Sinov Ota Yozuve','Sinov Ona Yozuve','(44) 7700 900194, +998 01 483 17 94','+998 01 483 17 94'),
  (8,'Sinov Ota Yozuve','Sinov Ona Yozuve','+44 7700 900194','+998 01 483 17 94'),
  (9,'Sinov Ota Yozuvf','Sinov Ona Yozuvf','+44 7700 900195','+998 01 483 17 95'),
  (10,'Sinov Ota Yozuvf','Sinov Ona Yozuvf','+44 7700 900195','998 01 483 17 95, +44 7700 900195dadasi'),
  (11,'Sinov Ota Yozuvf','Sinov Ona Yozuvf','+44 7700 900195','998 01 483 17 95; +44 7700 900195'),
  (12,'Sinov Ota Yozuvf','Sinov Ona Yozuvf','+44 7700 900195','+998 01 483 17 95ota; +44 7700 900195'),
  (13,null,'Sinov Ona Yozuvi','0044 7700 900198 / 15','0044 7700 900198 ota'),
  (14,null,'Sinov Ona Yozuvi','44 7700 900198 (15-uy)','44-7700-900198'),
  (15,'Sinov Ota Yozuvj',null,'+998 02 456 94 98','+998 02 456 94 98'),
  (16,'Sinov Ota Yozuvj','Sinov Ona Yozuvj','+998 02 456 94 98','+998 02 456 94 98dadasi (15-uy)'),
  (17,'Sinov Ota Yozuvj',null,'+998 02 456 94 98','+998 02 456 94 98 (15-uy)'),
  (18,null,'Sinov Ona Yozuvg','44-7700-900196','(01) 483-17-96, +44 7700 900 196'),
  (19,null,'Sinov Ona Yozuvg','+44 7700 900 196','+998 01 483 17 96ota; +44 7700 900 196'),
  (20,'-','Sinov Ona Yozuvg','+447700900196','+998 01 483 17 96; +44 7700 900196'),
  (21,'Sinov Ota Yozuvh','Sinov Ona Yozuvh','+998 (00) 723-74-97 (otasi)','+998 02 483 17 97'),
  (22,'Sinov Ota Yozuvh','Sinov Ona Yozuvh','+998 (00) 723-74-97' || chr(10) || '+998 (00) 614-39-97','+998 02 483 17 97'),
  (23,'Sinov Ota Yozuvh','Sinov Ona Yozuvh','+998 (00) 723-74-97dadasi / +998 (00) 614-39-97','+998 02 483 17 97'),
  (24,null,'Sinov Ona Zaxira','+998 00 111 22 39 (2-uy)','+998 00 888 99 39'),
  (25,null,'Sinov Ona Zaxira','9980011122392','+998 00 888 99 39'),
  (26,null,'Sinov Ona Zaxira','9980011122392','+998 00 888 99 39'),
  (27,null,'Sinov Ona Zaxira','+998 00 888 99 39','+998 00 111 22 39'),
  (28,null,'Sinov Ona Zaxira','+998 00 888 99 39','9980011122392'),
  (29,null,'Sinov Ona Uchona','+998 00 111 22 35','+998 02 544 84 25, +998 00 111 22 35dadasi'),
  (30,null,'Sinov Ona Uchona','+998 00 111 22 35','+998 02 544 84 25, +998 00 111 22 35dadasi'),
  (31,null,'Sinov Ona Uchona','+998 00 111 22 35','+998 02 544 84 25oyisi, +998 00 111 22 35'),
  (32,'yo''q','Sinov Ona Tortona','+998 00 111 22 45','+998 02 544 84 45, +998 00 111 22 45dadasi'),
  (33,'yo''q','Sinov Ona Tortona','+998 00 111 22 45','+998 02 544 84 45, +998 00 111 22 45dadasi'),
  (34,'yo''q','Sinov Ona Tortona','+998 00 111 22 45','+998 02 544 84 45, +998 00 111 22 45dadasi'),
  (35,'yo''q','Sinov Ona Tortona','+998 00 111 22 45','+998 02 544 84 45, +998 00 111 22 45dadasi'),
  (36,'yo''q','Sinov Ona Tortona','+998 00 111 22 45','+998 02 544 84 45oyisi, +998 00 111 22 45'),
  (37,'Sinov Ota Ikkiota','Sinov Ona Ikkiota','+998 02 544 84 24dadasi','+998 00 111 22 34, +998 00 444 55 67'),
  (38,'Sinov Ota Ikkiota','Sinov Ona Ikkiota','+998 02 544 84 24dadasi','+998 00 111 22 34, +998 00 444 55 67'),
  (39,'Sinov Ota Ikkiota','Sinov Ona Ikkiota','+998 02 544 84 24, +998 00 111 22 34oyisi','+998 00 444 55 67'),
  (40,'Sinov Ota Ikkiota','Sinov Ona Ikkiota','+998 02 544 84 24, +998 00 111 22 34oyisi','+998 00 444 55 67'),
  (41,'Sinov Ota Ikkiota','Sinov Ona Ikkiota','+998 02 544 84 24dadasi, +998 00 111 22 34','+998 00 444 55 67'),
  (42,'Sinov Ota Ikkiota','Sinov Ona Ikkiota','+998 02 544 84 24dadasi','+998 00 444 55 67'),
  (43,'Sinov Ota Mosl','Sinov Ona Mosl','+998 02 544 84 28, +998 00 111 22 48oyisi','+998 02 544 84 28'),
  (44,'Sinov Ota Mosl','Sinov Ona Mosl','+998 02 544 84 28, +998 00 111 22 48oyisi','+998 00 111 22 48'),
  (45,'Sinov Ota Mosl','Sinov Ona Mosl','+998 02 544 84 28dadasi, +998 00 111 22 48','+998 00 111 22 48'),
  (46,'Sinov Ota Mosl','Sinov Ona Mosl','+998 02 544 84 28','+998 00 111 22 48'),
  (47,'Sinov Ota Xorota',null,'44-7700-900145; 998028614645','998028614645'),
  (48,'Sinov Ota Xorota',null,'44 7700 900145, 998028614645','998028614645'),
  (49,'Sinov Ota Xorota',null,'+44 7700 900145','998028614645'),
  (50,'Sinov Ota Xorota',null,'0044 7700 900145, 998028614645mob','998028614645'),
  (51,'Sinov Ota Ikkiona','Sinov Ona Ikkiona','+998 01 333 22 51','+998 02 544 84 51, +998 00 111 22 51dadasi'),
  (52,'Sinov Ota Ikkiona','Sinov Ona Ikkiona','+998 01 333 22 51','+998 02 544 84 51, +998 00 111 22 51dadasi'),
  (53,'Sinov Ota Ikkiona','Sinov Ona Ikkiona','+998 01 333 22 51','+998 02 544 84 51oyisi, +998 00 111 22 51'),
  (54,null,'Sinov Ona Otasiz','998005556681','tel01 909 46 28; +998005556681'),
  (55,null,'Sinov Ona Otasiz','+998 00 555 66 81','tel01 909 46 28; +998005556681'),
  (56,null,'Sinov Ona Otasiz','+998 00 555 66 81','01 909 46 28  ota998 00 555 66 81'),
  (57,'Sinov Ota Yopish','Sinov Ona Yopish','+998 00 111 33 05','+998 00 333 44 05; 998007778805uy'),
  (58,'Sinov Ota Yopish','Sinov Ona Yopish','+998 00 111 33 05','+998 00 333 44 05; 998007778805uy'),
  (59,'Sinov Ota Yopish','Sinov Ona Yopish','+998 00 111 33 05','998003334405tel, +998 00 777 88 05'),
  (60,'Sinov Ota Yopish',null,'+998 00 111 33 05','998003334405tel, +998 00 777 88 05'),
  (61,'Sinov Ota Yopish',null,'+998 00 111 33 05','998003334405tel, +998 00 777 88 05'),
  (62,'Sinov Ota Yopish',null,'+998 00 111 33 05','998003334405tel, +998 00 777 88 05'),
  (63,'Sinov Ota Kopyop','Sinov Ona Kopyop','+998 00 794 06 11','+998 (00) 333-44-06 / 998002224406onasi'),
  (64,'Sinov Ota Kopyop','Sinov Ona Kopyop','+998 00 794 06 11','+998 00 333 44 06onasi  +998 (00) 222-44-06'),
  (65,'Sinov Ota Kopyop','Sinov Ona Kopyop','+998 00 794 06 11','998003334406tel'),
  (66,'Sinov Ota Kopyop','Sinov Ona Kopyop','+998 00 794 06 11','998003334406oyisi'),
  (67,'Sinov Ota Kopyop','Sinov Ona Kopyop','+998 00 794 06 11','tel998003334406'),
  (68,'Sinov Ota Otaona','Sinov Ona Otaona','+44 7700 900781','447700900582'),
  (69,null,'Sinov Ona Otaona','447700900582',null),
  (70,'Sinov Ota Otaona','Sinov Ona Otaona','+44 7700 900781','44 7700 900582'),
  (71,null,'Sinov Ona Otaona','44-7700-900582',null),
  (72,'Sinov Ota Otaona','Sinov Ona Otaona','+44 7700 900781','+44 7700 900 582'),
  (73,'-','Sinov Ona Otaona','+44 7700 900 781','+44 7700 900582ota, +998 00 555 25 82'),
  (74,'-','Sinov Ona Otaona','+447700900781','+447700900582 ona  998005552582tel')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o)
       || ' || ' || coalesce((select r -> 'father' ->> 'phone' from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal('Sinov Ota Yozuvd')) -> 'rows', '[]'::jsonb)) r
                               where r -> 'father' ->> 'name' = 'Sinov Ota Yozuvd' limit 1), '-') as h51
  from (values (1, 'Sinov Ota Yozuvd'), (2, 'Sinov Ota Yozuve'), (3, 'Sinov Ota Yozuvf'), (4, 'Sinov Ona Yozuvi'), (5, 'Sinov Ota Yozuvj'),
               (6, 'Sinov Ona Yozuvg'), (7, 'Sinov Ota Yozuvh'), (8, 'Sinov Ona Zaxira'), (9, 'Sinov Ona Uchona'), (10, 'Sinov Ona Tortona'),
               (11, 'Sinov Ota Ikkiota'), (12, 'Sinov Ota Mosl'), (13, 'Sinov Ota Xorota'), (14, 'Sinov Ota Ikkiona'),
               (15, 'Sinov Ona Otasiz'), (16, 'Sinov Ota Yopish'), (17, 'Sinov Ota Kopyop'),
               (18, 'Sinov Ota Otaona')) x(o, n) \gset
rollback to savepoint h51;
select zz.chk('H51 aka-uka: ochilgan asl yozuv — bir xil butun katak kanonigidagi turlicha o''qiladigan kataklardan tanlangan raqamniki (ikki raqamli katak, so''ng qo''ng''iroq kanonigi); ota qatorida faqat ona raqami / ona qatorida faqat ota raqami chiqmaydi',
  :'h51', '^\+44 7700 900193, \+998 01 483 17 93 false \+998014831793 true \| \+44 7700 900194, \+998 01 483 17 94 false \+998014831794 true \| '
       || '\+447700900195 true 998 01 483 17 95, \+44 7700 900195 false \| \*\*\* \*\* 15 false \+447700900198 true \| '
       || '\+998024569498 true \*\*\* \*\* 15 false \| \+447700900196 true \+998 01 483 17 96, \+44 7700 900196 false \| '
       || '\+998 00 723-74-97, \+998 00 614-39-97 false \+998024831797 true \| \+998 00 111 22 39 false \+998008889939 true \| '
       || '\+998001112235 true \+998 02 544 84 25 false \| \+998001112245 true \+998 02 544 84 45 false \| '
       || '\+998 02 544 84 24 false \+998004445567 true \| \+998 02 544 84 28 false \+998001112248 true \| '
       || '0044 7700 900145 false \+998028614645 true \| \+998013332251 true \+998 02 544 84 51 false \| '
       || '\+998005556681 true 01 909 46 28 false \| \+998001113305 true \+998 00 333 44 05 false \| '
       || '\+998007940611 true \+998 00 333-44-06 false \| \+447700900781 true \+447700900582 false \|\| \*\*\* \*\* 93$');

-- H52 — savepoint ichida (aka-uka kartalari, 13-mustaqil tekshiruv, 025c023 ga). Ota guruhining vakili (fpr) — ona ustunidagi soni
--   (mcn) minus ota nomzodi kataklaridagi soni (fpn) kamrog'i: Volti / Vtort — otaning raqami «(otasi)» izohi bilan ona kataklarida (onasiz
--   kartalarda ham) onaning o'z raqamidan ko'p turadi, ota guruhidagi ozchilik o'qish — ona raqami (025c023 faqat ona ustunidagi sonni
--   solishtirib, ota qatorida onaning, ona qatorida otaning raqamini ko'rsatardi; 67b0e73 to'g'ri edi); Xorc — ota guruhida ko'pchilik
--   o'qish ona raqami, u ona va ota ustunida teng (greatest(…, 0) bilan ikkala qator almashardi); Nsb — onasi ro'yxatdan o'tkazgan
--   sakkiz kartada ona raqami «ota telefoni»da (fcn bilan ota qatorida ona raqami chiqardi; fpn ularni sanamaydi). Ona tomoni (mpt
--   5-daraja): Vtob — ota qatorida ikki raqamli katak: guruhning eng kichik qo'ng'iroq kanonigi ham 5-darajada (67b0e73 kabi; 025c023
--   ona qatorida otaning raqamini ko'rsatardi); Vtom — otaning raqami ikki raqamli katakda ikkinchi yozilgan (025c023 ham ona qatorida
--   otaning raqamini ko'rsatardi); Otaonc — «(ota-onasi)», «(onasi-otasi)» ota so'zi emas: ajratuvchi karta (ona katagida maktab
--   raqami) bo'lsa ham ona ismli barcha kataklardagi raqam ota ismli kartalardagi «+»siz raqamdan ustun emas (025c023 ota qatorida onaning
--   raqamini ko'rsatardi).
savepoint h52;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x52' || lpad(g::text, 2, '0'), 'IQ-X52' || lpad(g::text, 2, '0'), 'Sinov Bola X52' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 3100 + g
    from generate_series(1, 49) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x52' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Volti','Sinov Ona Volti','+44 7700 900136, +998 00 222 32 48oyisi','+44 7700 900136 (otasi)'),
  (2,'Sinov Ota Volti',null,'+44 7700 900136, +998 00 222 32 48oyisi','+44 7700 900136 (otasi)'),
  (3,'Sinov Ota Volti',null,'+44 7700 900136, +998 00 222 32 48oyisi','+44 7700 900136 (otasi)'),
  (4,'Sinov Ota Volti','Sinov Ona Volti','(44) 7700 900136; 998002223248','+998 00 222 32 48'),
  (5,'Sinov Ota Volti','Sinov Ona Volti','+44 7700 900136','+998 00 222 32 48'),
  (6,'Sinov Ota Vtort','Sinov Ona Vtort','+998 00 111 21 34 / 998002223245oyisi','+998 00 111 21 34 (otasi)'),
  (7,'Sinov Ota Vtort',null,'+998 00 111 21 34 / 998002223245oyisi','+998 00 111 21 34 (otasi)'),
  (8,'Sinov Ota Vtort',null,'+998 00 111 21 34 / 998002223245oyisi','+998 00 111 21 34 (otasi)'),
  (9,'Sinov Ota Vtort',null,'+998 00 111 21 34 / 998002223245oyisi','+998 00 111 21 34 (otasi)'),
  (10,'Sinov Ota Vtort','Sinov Ona Vtort','998001112134dadasi / +998 00 222 32 45','+998 00 222 32 45'),
  (11,'Sinov Ota Vtort','Sinov Ona Vtort','+998 00 111 21 34','+998 00 222 32 45'),
  (12,'Sinov Ota Vtob',null,'+998 00 111 21 41 / +998 00 222 32 53','+998 00 111 21 41 (otasi)'),
  (13,'Sinov Ota Vtob',null,'+998 00 111 21 41 / +998 00 222 32 53','+998 00 111 21 41 (otasi)'),
  (14,'Sinov Ota Vtob',null,'+998 00 111 21 41 / +998 00 222 32 53','+998 00 111 21 41 (otasi)'),
  (15,'Sinov Ota Vtob',null,'+998 00 111 21 41 / 998002223253oyisi','+998 00 111 21 41 (otasi)'),
  (16,'Sinov Ota Vtob',null,'+998 00 111 21 41 / 998002223253oyisi','+998 00 222 32 53'),
  (17,'Sinov Ota Vtob',null,'+998 00 111 21 41','+998 00 222 32 53'),
  (18,'Sinov Ota Vtob',null,'+998 00 111 21 41','+998 00 222 32 53'),
  (19,'Sinov Ota Xorc',null,'44-7700-900147; 998028614647','998028614647'),
  (20,'Sinov Ota Xorc',null,'44 7700 900147, 998028614647','998028614647'),
  (21,'Sinov Ota Xorc',null,'44 7700 900147 / 998028614647','+44 7700 900147 (otasi)'),
  (22,'Sinov Ota Xorc',null,'0044 7700 900147, 998028614647mob','998028614647'),
  (23,'Sinov Ota Xorc',null,'+44 7700 900147',null),
  (24,'Sinov Ota Xorc',null,'+44 7700 900147','998028614647'),
  (25,'Sinov Ota Xorc',null,'44 7700 900147, 998028614647','+44 7700 900147 (otasi)'),
  (26,'Sinov Ota Nsb','Sinov Ona Nsb','+998 00 111 21 81, 998002223281oyisi','+998 00 222 32 81'),
  (27,'Sinov Ota Nsb','Sinov Ona Nsb','+998 00 111 21 81, 998002223281oyisi','+998 00 222 32 81'),
  (28,'Sinov Ota Nsb','Sinov Ona Nsb','+998 00 111 21 81, 998002223281oyisi','+998 00 222 32 81'),
  (29,'Sinov Ota Nsb','Sinov Ona Nsb','998001112181dadasi, +998 00 222 32 81','+998 00 111 21 81 (otasi)'),
  (30,'Sinov Ota Nsb','Sinov Ona Nsb','+998 00 111 21 81','+998 00 222 32 81'),
  (31,null,'Sinov Ona Nsb','+998 00 222 32 81',null),
  (32,null,'Sinov Ona Nsb','+998 00 222 32 81',null),
  (33,null,'Sinov Ona Nsb','+998 00 222 32 81',null),
  (34,null,'Sinov Ona Nsb','+998 00 222 32 81',null),
  (35,null,'Sinov Ona Nsb','+998 00 222 32 81',null),
  (36,null,'Sinov Ona Nsb','+998 00 222 32 81',null),
  (37,null,'Sinov Ona Nsb','+998 00 222 32 81',null),
  (38,null,'Sinov Ona Nsb','+998 00 222 32 81',null),
  (39,'Sinov Ota Vtom',null,'+998 00 222 32 71 / +998 00 111 21 61','+998 00 111 21 61 (otasi)'),
  (40,'Sinov Ota Vtom',null,'+998 00 222 32 71 / +998 00 111 21 61','+998 00 111 21 61 (otasi)'),
  (41,'Sinov Ota Vtom',null,'+998 00 222 32 71 / +998 00 111 21 61','+998 00 111 21 61 (otasi)'),
  (42,'Sinov Ota Vtom',null,'998002223271oyisi / +998 00 111 21 61','+998 00 111 21 61 (otasi)'),
  (43,'Sinov Ota Vtom',null,'998002223271oyisi / +998 00 111 21 61','+998 00 222 32 71'),
  (44,'Sinov Ota Vtom',null,'+998 00 111 21 61','+998 00 222 32 71'),
  (45,'Sinov Ota Vtom',null,'+998 00 111 21 61','+998 00 222 32 71'),
  (46,'Sinov Ota Otaonc','Sinov Ona Otaonc','447700900139','+998 00 222 33 62 (ota-onasi)'),
  (47,'Sinov Ota Otaonc','Sinov Ona Otaonc','447700900139','+998 00 222 33 62 (onasi-otasi)'),
  (48,'Sinov Ota Otaonc','Sinov Ona Otaonc','447700900139','+998 00 222 33 62'),
  (49,'Sinov Ota Otaonc',null,'+998 00 222 33 62','+998 00 999 00 32')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o)
       || ' || ' || coalesce((select (r -> 'father' ->> 'phone') || ' / ' || (r -> 'mother' ->> 'phone')
                                from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal('Sinov Ota Volti')) -> 'rows', '[]'::jsonb)) r
                               where r -> 'father' ->> 'name' = 'Sinov Ota Volti' limit 1), '-') as h52
  from (values (1, 'Sinov Ota Volti'), (2, 'Sinov Ota Vtort'), (3, 'Sinov Ota Vtob'), (4, 'Sinov Ota Xorc'), (5, 'Sinov Ota Nsb'),
               (6, 'Sinov Ota Vtom'), (7, 'Sinov Ota Otaonc')) x(o, n) \gset
rollback to savepoint h52;
select zz.chk('H52 aka-uka: ota guruhining vakili — ona ustunida ota nomzodi kataklaridagidan kamroq turgan o''qish; ona tomonida ikki raqamli ota katagining eng kichik o''qishi 5-darajada; ' || chr(171) || 'ota-ona' || chr(187) || ' ota so''zi emas',
  :'h52', '^\+44 7700 900136 false \+998002223248 true \| \+998 00 111 21 34 false \+998002223245 true \| '
       || '\+998 00 111 21 41, \+998 00 222 32 53 false \+998002223253 true \| 0044 7700 900147 false \+998028614647 true \| '
       || '\+998 00 111 21 81 false \+998002223281 true \| '
       || '\+998 00 222 32 71, \+998 00 111 21 61 false \+998002223271 true \| \*\*\* \*\* 39 false \+998002223362 true \|\| '
       || '\*\*\* \*\* 36 / \+998 00 \*\*\* \*\* 48$');

-- H53 — savepoint ichida (aka-uka kartalari; 13-mustaqil tekshiruv tuzatishlari). Ona ismli barcha kataklarda turgan raqam «aniq ona raqami»
--   sifatida pasaytirilmasligi uchun IKKALASI kerak: ajratuvchi karta va biror ona ismli katakda shu raqam ota so'zi bilan. Fwsiz — «(otasi)»
--   bor, ajratuvchi karta yo'q — pasaytiriladi (ota so'zi yolg'iz himoya emas: tasodifiy izoh onaning raqamini himoyalardi); Fwswap — ajratuvchi
--   bo'lishi mumkin bo'lgan kartaning ona katagidagi ikkinchi raqam ota ismli kartaning ota katagida turadi (raqamlari almashgan karta, ikki
--   raqamli katakda ham) — ajratmaydi; Fwizoh — ona katagida izohli 13 xonali yozuv («0044 7700 900873 (2)») telefon ko'rinishida emas —
--   ajratmaydi; Fwyop — ota so'zi boshqa, yopishgan raqamniki («+998 00 222 52 74, +44 7700 900174dadasi») — onaning raqamini himoyalamaydi (ota
--   qatorida otaning «+»siz raqami); Fwfp — ajratuvchi kartaning ota katagi izohli («(2-uy)»), ona katagida onaning raqami: ota so'zi qo'ng'iroq
--   raqami bo'yicha topiladi. Vtorm — Vtort ko'zgusi (ona raqami kichikroq): ota guruhining vakili otaning raqami (025c023 va 67b0e73 da ona
--   raqami — ota va ona almashardi), ota qatorida bitta raqamli katak bo'lgani uchun ona tomonida guruhning eng kichik o'qishi (onaning raqami)
--   istisno qilinmaydi.
savepoint h53;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x53' || lpad(g::text, 2, '0'), 'IQ-X53' || lpad(g::text, 2, '0'), 'Sinov Bola X53' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 3200 + g
    from generate_series(1, 28) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x53' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Fwsiz','Sinov Ona Fwsiz','+998 00 111 21 71','+998 00 111 21 71 (otasi)'),
  (2,'Sinov Ota Fwsiz','Sinov Ona Fwsiz','447700900171','+998 00 111 21 71 (otasi)'),
  (3,'Sinov Ota Fwsiz','Sinov Ona Fwsiz','447700900171','+998 00 111 21 71 (otasi)'),
  (4,'Sinov Ota Fwsiz',null,'447700900171','+998 00 222 42 71'),
  (5,'Sinov Ota Fwswap','Sinov Ona Fwswap','+998 00 111 21 72','+998 00 111 21 72 (otasi)'),
  (6,'Sinov Ota Fwswap','Sinov Ona Fwswap','447700900172','+998 00 111 21 72 (otasi)'),
  (7,'Sinov Ota Fwswap','Sinov Ona Fwswap','447700900172','+998 00 111 21 72 (otasi)'),
  (8,'Sinov Ota Fwswap',null,'+998 00 111 21 72','+998 00 999 00 72, +44 7700 900172'),
  (9,'Sinov Ota Fwizoh','Sinov Ona Fwizoh','+998 00 111 21 73','+998 00 111 21 73 (otasi)'),
  (10,'Sinov Ota Fwizoh','Sinov Ona Fwizoh','447700900173','+998 00 111 21 73 (otasi)'),
  (11,'Sinov Ota Fwizoh','Sinov Ona Fwizoh','447700900173','+998 00 111 21 73 (otasi)'),
  (12,'Sinov Ota Fwizoh',null,'+998 00 111 21 73','0044 7700 900873 (2)'),
  (13,'Sinov Ota Fwyop','Sinov Ona Fwyop','447700900174','+998 00 222 52 74, +44 7700 900174dadasi'),
  (14,'Sinov Ota Fwyop','Sinov Ona Fwyop','447700900174','+998 00 222 52 74, +44 7700 900174dadasi'),
  (15,'Sinov Ota Fwyop','Sinov Ona Fwyop','447700900174','+998 00 222 52 74'),
  (16,'Sinov Ota Fwyop',null,'+998 00 222 52 74','+998 00 999 00 74'),
  (17,'Sinov Ota Fwfp','Sinov Ona Fwfp','447700900175','+998 00 111 21 75 (otasi)'),
  (18,'Sinov Ota Fwfp','Sinov Ona Fwfp','447700900175','+998 00 111 21 75 (otasi)'),
  (19,'Sinov Ota Fwfp','Sinov Ona Fwfp','447700900175','+998 00 111 21 75 (otasi)'),
  (20,'Sinov Ota Fwfp',null,'+998 00 111 21 75 (2-uy)','+998 00 222 42 75'),
  (21,'Sinov Ota Fwfp',null,'447700900175','+998 00 222 42 75'),
  (22,'Sinov Ota Fwfp',null,'447700900175','+998 00 999 00 75'),
  (23,'Sinov Ota Vtorm','Sinov Ona Vtorm','+998 00 222 32 76 / 998001112176oyisi','+998 00 222 32 76 (otasi)'),
  (24,'Sinov Ota Vtorm',null,'+998 00 222 32 76 / 998001112176oyisi','+998 00 222 32 76 (otasi)'),
  (25,'Sinov Ota Vtorm',null,'+998 00 222 32 76 / 998001112176oyisi','+998 00 222 32 76 (otasi)'),
  (26,'Sinov Ota Vtorm',null,'+998 00 222 32 76 / 998001112176oyisi','+998 00 222 32 76 (otasi)'),
  (27,'Sinov Ota Vtorm','Sinov Ona Vtorm','998002223276dadasi / +998 00 111 21 76','+998 00 111 21 76'),
  (28,'Sinov Ota Vtorm','Sinov Ona Vtorm','+998 00 222 32 76','+998 00 111 21 76')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o) as h53
  from (values (1, 'Sinov Ota Fwsiz'), (2, 'Sinov Ota Fwswap'), (3, 'Sinov Ota Fwizoh'), (4, 'Sinov Ota Fwyop'), (5, 'Sinov Ota Fwfp'),
               (6, 'Sinov Ota Vtorm')) x(o, n) \gset
rollback to savepoint h53;
select zz.chk('H53 aka-uka: ajratuvchi karta faqat ota so''zi bilan himoyalaydi; ota so''zi yolg''iz, almashgan yoki izohli 13 xonali ona katagi, boshqa raqamga yopishgan so''z ' || chr(8212) || ' himoya emas; ota guruhi vakili Vtort ko''zgusida',
  :'h53', '^\*\*\* \*\* 71 false \+998001112171 true \| \*\*\* \*\* 72 false \+998001112172 true \| \*\*\* \*\* 73 false \+998001112173 true \| '
       || '\*\*\* \*\* 74 false \+998 00 222 52 74 false \| \+998 00 111 21 75 false \+998002224275 true \| '
       || '\+998 00 222 32 76 false \+998001112176 true$');

-- H54 — savepoint ichida (aka-uka kartalari; 14-mustaqil tekshiruv). Ona ismli katakdagi ota so'zi raqamni otaniki deb ko'rsatadigan
--   yorliq bo'lishi uchun katakda boshqa so'z bo'lmasligi kerak («(otasi)», «(otasi tel)» — yorliq): ota haqidagi izoh («(onasi; otasi chet
--   elda)», «(otasi, chet elda)») yoki boshqa yozuvdagi «ota-ona» («ota – ona», en tire) — yorliq emas. Aks holda ikki raqamli ajratuvchi karta
--   (ota ismli, ona ismsiz kartada ota katagida ona raqami, ona katagida ikki boshqa raqam) bilan ona raqami «aniq ona raqami» sifatida
--   pasaytirilmay, ota qatorida onaning raqami chiqardi (2a91fa9; 025c023 va 8f9925d to'g'ri edi). Fwtel — yorliq («otasi tel»): himoya qoladi.
savepoint h54;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x54' || lpad(g::text, 2, '0'), 'IQ-X54' || lpad(g::text, 2, '0'), 'Sinov Bola X54' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 3300 + g
    from generate_series(1, 12) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x54' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Fwizn','Sinov Ona Fwizn','44 7700 900183','+998 00 123 45 12 (onasi; otasi chet elda)'),
  (2,'Sinov Ota Fwizn','Sinov Ona Fwizn','44 7700 900183','+998 00 123 45 12'),
  (3,'Sinov Ota Fwizn',null,'+998 00 123 45 12','+998 00 999 00 25, +998 00 888 00 26'),
  (4,'Sinov Ota Fwtir','Sinov Ona Fwtir','44 7700 900184','+998 00 123 45 13 (ota ' || chr(8211) || ' ona)'),
  (5,'Sinov Ota Fwtir','Sinov Ona Fwtir','44 7700 900184','+998 00 123 45 13'),
  (6,'Sinov Ota Fwtir',null,'+998 00 123 45 13','+998 00 999 00 36, +998 00 888 00 37'),
  (7,'Sinov Ota Fwver','Sinov Ona Fwver','44 7700 900185','+998 00 123 45 14 (otasi, chet elda)'),
  (8,'Sinov Ota Fwver','Sinov Ona Fwver','44 7700 900185','+998 00 123 45 14'),
  (9,'Sinov Ota Fwver',null,'+998 00 123 45 14','+998 00 999 00 47, +998 00 888 00 48'),
  (10,'Sinov Ota Fwtel','Sinov Ona Fwtel','44 7700 900186','+998 00 123 45 15 (otasi tel)'),
  (11,'Sinov Ota Fwtel','Sinov Ona Fwtel','44 7700 900186','+998 00 123 45 15'),
  (12,'Sinov Ota Fwtel',null,'+998 00 123 45 15','+998 00 999 00 58, +998 00 888 00 59')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o) as h54
  from (values (1, 'Sinov Ota Fwizn'), (2, 'Sinov Ota Fwtir'), (3, 'Sinov Ota Fwver'), (4, 'Sinov Ota Fwtel')) x(o, n) \gset
rollback to savepoint h54;
select zz.chk('H54 aka-uka: ona ismli katakdagi ota haqidagi izoh yoki boshqa yozuvdagi ' || chr(171) || 'ota-ona' || chr(187) || ' ' || chr(8212) || ' ota yorlig''i emas (ikki raqamli ajratuvchi karta bilan ota qatorida ona raqami chiqmaydi); ' || chr(171) || 'otasi tel' || chr(187) || ' ' || chr(8212) || ' yorliq',
  :'h54', '^\*\*\* \*\* 83 false \+998001234512 true \| \*\*\* \*\* 84 false \+998001234513 true \| \*\*\* \*\* 85 false \+998001234514 true \| '
       || '\+998001234515 true \+998 00 999 00 58, \+998 00 888 00 59 false$');

-- H55 — savepoint ichida (aka-uka kartalari; 14-mustaqil tekshiruv, 2a91fa9 ga). Ota so'zining so'zlashuvdagi qaratqich shakli «-ni»
--   («dadasini nomeri», «otasini tel», «ДАДАСИНИ НОМЕРИ» = «dadasining nomeri»): H50 Otasib / Oltita shakli — ona ismli kataklarda otaning
--   raqami shu izoh bilan, ajratuvchi karta bor — ota raqami otaniki qoladi (2a91fa9 da so'z topilmay, ota qatorida «+»siz uchinchi raqam,
--   ona qatorida otaning raqami chiqardi; 025c023 va 67b0e73 to'g'ri edi). Otona — «ota-onasini nomeri» ota so'zi emas (pasaytiriladi, 24-chegara).
savepoint h55;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x55' || lpad(g::text, 2, '0'), 'IQ-X55' || lpad(g::text, 2, '0'), 'Sinov Bola X55' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 3400 + g
    from generate_series(1, 16) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x55' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Dadni','Sinov Ona Dadni','447700900146','+998 00 111 21 31 (dadasini nomeri)'),
  (2,'Sinov Ota Dadni','Sinov Ona Dadni','447700900146','+998 00 111 21 31 (dadasini nomeri)'),
  (3,'Sinov Ota Dadni','Sinov Ona Dadni','447700900146','+998 00 111 21 31'),
  (4,'Sinov Ota Dadni',null,'+998 00 111 21 31','+998 00 222 42 37'),
  (5,'Sinov Ota Otni','Sinov Ona Otni','447700900147','+998 00 111 21 47 (otasini tel)'),
  (6,'Sinov Ota Otni','Sinov Ona Otni','447700900147','+998 00 111 21 47 (otasini tel)'),
  (7,'Sinov Ota Otni','Sinov Ona Otni','447700900147','+998 00 111 21 47 (otasini tel)'),
  (8,'Sinov Ota Otni',null,'+998 00 111 21 47','+998 00 222 42 47'),
  (9,'Sinov Ota Kirni','Sinov Ona Kirni','447700900148','+998 00 111 21 48 (' || chr(1044) || chr(1040) || chr(1044) || chr(1040) || chr(1057) || chr(1048) || chr(1053) || chr(1048) || ' ' || chr(1053) || chr(1054) || chr(1052) || chr(1045) || chr(1056) || chr(1048) || ')'),
  (10,'Sinov Ota Kirni','Sinov Ona Kirni','447700900148','+998 00 111 21 48 (' || chr(1044) || chr(1040) || chr(1044) || chr(1040) || chr(1057) || chr(1048) || chr(1053) || chr(1048) || ' ' || chr(1053) || chr(1054) || chr(1052) || chr(1045) || chr(1056) || chr(1048) || ')'),
  (11,'Sinov Ota Kirni','Sinov Ona Kirni','447700900148','+998 00 111 21 48'),
  (12,'Sinov Ota Kirni',null,'+998 00 111 21 48','+998 00 222 42 48'),
  (13,'Sinov Ota Otona','Sinov Ona Otona','447700900149','+998 00 111 21 49 (ota-onasini nomeri)'),
  (14,'Sinov Ota Otona','Sinov Ona Otona','447700900149','+998 00 111 21 49 (ota-onasini nomeri)'),
  (15,'Sinov Ota Otona','Sinov Ona Otona','447700900149','+998 00 111 21 49 (ota-onasini nomeri)'),
  (16,'Sinov Ota Otona',null,'+998 00 111 21 49','+998 00 222 42 49')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o)
       || ' || ' || coalesce((select (r -> 'father' ->> 'phone') || ' / ' || (r -> 'mother' ->> 'phone')
                                from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal('Sinov Ota Dadni')) -> 'rows', '[]'::jsonb)) r
                               where r -> 'father' ->> 'name' = 'Sinov Ota Dadni' limit 1), '-') as h55
  from (values (1, 'Sinov Ota Dadni'), (2, 'Sinov Ota Otni'), (3, 'Sinov Ota Kirni'), (4, 'Sinov Ota Otona')) x(o, n) \gset
rollback to savepoint h55;
select zz.chk('H55 aka-uka: ota so''zining so''zlashuvdagi qaratqich shakli ' || chr(171) || 'dadasini nomeri' || chr(187) || ' ham ota so''zi (ajratuvchi karta bilan himoya); ' || chr(171) || 'ota-onasini' || chr(187) || ' ' || chr(8212) || ' emas',
  :'h55', '^\+998001112131 true \+998002224237 true \| \+998001112147 true \+998002224247 true \| \+998001112148 true \+998002224248 true \| '
       || '\*\*\* \*\* 49 false \+998001112149 true \|\| \+998 00 \*\*\* \*\* 31 / \+998 00 \*\*\* \*\* 37$');

-- H56 — savepoint ichida (aka-uka kartalari; 14-mustaqil tekshiruv). Ota guruhining vakili (fpr) — shu ism sinfidagi ota nomzodi
--   kataklari bilan: onasi ro'yxatdan o'tkazgan kartalarning «ota telefoni»dagi ona raqami (ona ismli kartaning ona katagida yozilmagan —
--   fp_mom emas, shuning uchun fpt da 2-daraja) ota ismli guruhning vakilini tanlashda sanalmaydi. Dqs — ota ismli kartalarda otaning
--   raqami ko'p, ikki raqamli kataklarda ikkinchi raqam so'zga yopishgan («998002224297ona», «998001112191ota»), onasi to'rt kartani
--   ro'yxatdan o'tkazgan; Dqc — ona ustunida onaning raqami faqat bitta kartada. 2a91fa9 da ikkalasida ota qatorida onaning raqami,
--   Dqs da ona qatorida otaning raqami chiqardi (025c023, 8f9925d va 67b0e73 to'g'ri edi; H52 Nsb — fp_mom bo'lgan holat).
savepoint h56;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x56' || lpad(g::text, 2, '0'), 'IQ-X56' || lpad(g::text, 2, '0'), 'Sinov Bola X56' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 3500 + g
    from generate_series(1, 20) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x56' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Dqs',null,'+998 00 111 21 91, 998002224297ona','+998 00 111 21 91 (otasi)'),
  (2,'Sinov Ota Dqs',null,'998001112191ota, +998 00 222 42 97','998009990091tel'),
  (3,'Sinov Ota Dqs',null,'+998 00 111 21 91, 998002224297ona','+998 00 222 42 97'),
  (4,'Sinov Ota Dqs',null,'+998 00 111 21 91','998009990091tel'),
  (5,'Sinov Ota Dqs',null,'+998 00 111 21 91','+998 00 222 42 97'),
  (6,'Sinov Ota Dqs','Sinov Ona Dqs','+998 00 222 42 97',null),
  (7,null,'Sinov Ona Dqs','+998 00 222 42 97',null),
  (8,null,'Sinov Ona Dqs','+998 00 222 42 97',null),
  (9,null,'Sinov Ona Dqs','+998 00 222 42 97',null),
  (10,null,'Sinov Ona Dqs','+998 00 222 42 97',null),
  (11,'Sinov Ota Dqc',null,'+998 00 111 21 92, 998002224298ona','998009990092tel'),
  (12,'Sinov Ota Dqc',null,'998001112192ota, +998 00 222 42 98','998009990092tel'),
  (13,'Sinov Ota Dqc',null,'+998 00 111 21 92, 998002224298ona','998009990092tel'),
  (14,'Sinov Ota Dqc',null,'+998 00 111 21 92','998009990092tel'),
  (15,'Sinov Ota Dqc',null,'+998 00 111 21 92','+998 00 222 42 98'),
  (16,'Sinov Ota Dqc','Sinov Ona Dqc','+998 00 222 42 98',null),
  (17,null,'Sinov Ona Dqc','+998 00 222 42 98',null),
  (18,null,'Sinov Ona Dqc','+998 00 222 42 98',null),
  (19,null,'Sinov Ona Dqc','+998 00 222 42 98',null),
  (20,null,'Sinov Ona Dqc','+998 00 222 42 98',null)) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o)
       || ' || ' || coalesce((select (r -> 'father' ->> 'phone') || ' / ' || (r -> 'mother' ->> 'phone')
                                from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal('Sinov Ota Dqs')) -> 'rows', '[]'::jsonb)) r
                               where r -> 'father' ->> 'name' = 'Sinov Ota Dqs' limit 1), '-') as h56
  from (values (1, 'Sinov Ota Dqs'), (2, 'Sinov Ota Dqc')) x(o, n) \gset
rollback to savepoint h56;
select zz.chk('H56 aka-uka: ota guruhining vakili ' || chr(8212) || ' shu ism sinfidagi ota kataklari bilan; onasi ro''yxatdan o''tkazgan kartalardagi ona raqami (fp_mom emas) ota qatoriga chiqmaydi',
  :'h56', '^\+998 00 111 21 91 false \+998002224297 true \| \+998 00 111 21 92 false \+998002224298 true \|\| '
       || '\+998 00 \*\*\* \*\* 91 / \+998 00 \*\*\* \*\* 97$');

-- H57 — savepoint ichida (aka-uka kartalari; o'z mutatsiya tahlili, 14-raund tuzatishlari). Ota yorlig'i so'zlar tartibiga bog'liq
--   emas: «(ishxona - otasi)» — yorliq («(otasi ishxona)» kabi; avvalgi alohida «ona» tekshiruvi «ishxona» oxirini «ona» deb
--   o'qib, himoyani olib tashlardi va ota qatorida onaning raqami chiqardi); kirill yozuvidagi «(ИШХОНА, ОТАСИ)» — yorliq (lotincha
--   bilan bir xil); «(o'ta)» — «o'» harfi «o» emas, ota so'zi emas (tutuq belgisi olib tashlanmaydi). H54 shakli.
savepoint h57;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x57' || lpad(g::text, 2, '0'), 'IQ-X57' || lpad(g::text, 2, '0'), 'Sinov Bola X57' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 3600 + g
    from generate_series(1, 9) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x57' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Fwish','Sinov Ona Fwish','44 7700 900187','+998 00 123 45 16 (ishxona - otasi)'),
  (2,'Sinov Ota Fwish','Sinov Ona Fwish','44 7700 900187','+998 00 123 45 16'),
  (3,'Sinov Ota Fwish',null,'+998 00 123 45 16','+998 00 999 00 69, +998 00 888 00 70'),
  (4,'Sinov Ota Fwkir','Sinov Ona Fwkir','44 7700 900188','+998 00 123 45 17 (' || chr(1048) || chr(1064) || chr(1061) || chr(1054) || chr(1053) || chr(1040) || ', ' || chr(1054) || chr(1058) || chr(1040) || chr(1057) || chr(1048) || ')'),
  (5,'Sinov Ota Fwkir','Sinov Ona Fwkir','44 7700 900188','+998 00 123 45 17'),
  (6,'Sinov Ota Fwkir',null,'+998 00 123 45 17','+998 00 999 00 71, +998 00 888 00 72'),
  (7,'Sinov Ota Fwapo','Sinov Ona Fwapo','44 7700 900189','+998 00 123 45 18 (o''ta)'),
  (8,'Sinov Ota Fwapo','Sinov Ona Fwapo','44 7700 900189','+998 00 123 45 18'),
  (9,'Sinov Ota Fwapo',null,'+998 00 123 45 18','+998 00 999 00 73, +998 00 888 00 74')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o) as h57
  from (values (1, 'Sinov Ota Fwish'), (2, 'Sinov Ota Fwkir'), (3, 'Sinov Ota Fwapo')) x(o, n) \gset
rollback to savepoint h57;
select zz.chk('H57 aka-uka: ota yorlig''i so''zlar tartibiga bog''liq emas (' || chr(171) || 'ishxona - otasi' || chr(187) || ', kirill yozuvida ham); ' || chr(171) || 'o''ta' || chr(187) || ' ' || chr(8212) || ' ota so''zi emas',
  :'h57', '^\+998001234516 true \+998 00 999 00 69, \+998 00 888 00 70 false \| \+998001234517 true \+998 00 999 00 71, \+998 00 888 00 72 false \| '
       || '\*\*\* \*\* 89 false \+998001234518 true$');

-- H58 — savepoint ichida (aka-uka kartalari; o'z mutatsiya tahlili, 14-raund tuzatishlari). Ota guruhining vakili (fpr): Dtie — ota
--   ismli ikki raqamli kataklar guruhida ikki o'qish shu ism sinfida teng (har biri bitta kartada), otaning raqami esa ota ismi yozilmagan
--   kartalarning ota katagida ham turadi — teng bo'lsa barcha ota nomzodi kataklari hisobga olinadi (aks holda kichik raqam — boshqa
--   odamning raqami — ota qatoriga chiqardi); Dqg — H56 Dqs, lekin onasi ro'yxatdan o'tkazgan ota ismsiz kartalarda onaning raqami
--   «ota telefoni»ga so'zga yopishib yozilgan («998002224294ona», noto'g'ri katak, 5-daraja): bunday katak ham ota ismsiz sinfda qoladi —
--   ota ismli guruhning vakilini tanlashda sanalmaydi (aks holda ota qatorida onaning raqami chiqardi).
savepoint h58;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x58' || lpad(g::text, 2, '0'), 'IQ-X58' || lpad(g::text, 2, '0'), 'Sinov Bola X58' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 3700 + g
    from generate_series(1, 14) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x58' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Dtie','Sinov Ona Dtie','+998 00 111 21 95, 998002224295ota','+998 00 333 63 95'),
  (2,'Sinov Ota Dtie','Sinov Ona Dtie','998001112195tel, +998 00 222 42 95','+998 00 333 63 95'),
  (3,null,'Sinov Ona Dtie','+998 00 222 42 95','+998 00 333 63 95'),
  (4,null,'Sinov Ona Dtie','+998 00 222 42 95','+998 00 333 63 95'),
  (5,'Sinov Ota Dqg',null,'+998 00 111 21 93, 998002224294ona','+998 00 111 21 93 (otasi)'),
  (6,'Sinov Ota Dqg',null,'998001112193ota, +998 00 222 42 94','998009990093tel'),
  (7,'Sinov Ota Dqg',null,'+998 00 111 21 93, 998002224294ona','+998 00 222 42 94'),
  (8,'Sinov Ota Dqg',null,'+998 00 111 21 93','998009990093tel'),
  (9,'Sinov Ota Dqg',null,'+998 00 111 21 93','+998 00 222 42 94'),
  (10,'Sinov Ota Dqg','Sinov Ona Dqg','+998 00 222 42 94',null),
  (11,null,'Sinov Ona Dqg','998002224294ona',null),
  (12,null,'Sinov Ona Dqg','998002224294ona',null),
  (13,null,'Sinov Ona Dqg','998002224294ona',null),
  (14,null,'Sinov Ona Dqg','998002224294ona',null)) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o) as h58
  from (values (1, 'Sinov Ota Dtie'), (2, 'Sinov Ota Dqg')) x(o, n) \gset
rollback to savepoint h58;
select zz.chk('H58 aka-uka: ota guruhining vakili ' || chr(8212) || ' shu ism sinfida teng bo''lsa barcha ota kataklari bilan; ota ismsiz kartalardagi so''zga yopishgan katak ham ota ismsiz sinfda',
  :'h58', '^\+998 00 222 42 95 false \+998003336395 true \| \+998 00 111 21 93 false \+998002224294 true$');

-- H59 — savepoint ichida (aka-uka kartalari; 15-mustaqil tekshiruv). Ota yorlig'idagi telefon so'zining odatiy yozuvlari ham yorliq:
--   egalik shakli («otasining teli», «otasining mobili», «dadasining ishi», «otasining ishxonasi», «otasining uyi», «dadasini teli»), rus
--   klaviaturasida «қ» o'rniga «к» («ОТАСИНИНГ РАКАМИ», «otasi rakami»), so'zlashuvdagi «sotka(si)», «мобильник», ruscha qisqartma va
--   qaratqich («сот. отца», «отец, раб.», «дом. тел. отца», «номер телефона отца») — har bir yangi so'z alohida oilada (so'z ro'yxatdan
--   olib tashlansa — shu oila yiqiladi). H55 shakli: ona ismli kataklarda otaning raqami shu yorliq bilan, ajratuvchi karta bor — ota
--   raqami otaniki qoladi (735cae3 da yorliq ro'yxatda yo'q so'z tufayli rad etilib, ota qatorida «+»siz uchinchi raqam, ona qatorida
--   otaning raqami chiqardi; 2a91fa9 da «-ni» va «телефона» (eski «она» tekshiruvi) oilalari yiqilardi, 025c023 va 67b0e73 to'g'ri edi).
savepoint h59;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x59' || lpad(g::text, 3, '0'), 'IQ-X59' || lpad(g::text, 3, '0'), 'Sinov Bola X59' || lpad(g::text, 3, '0'), 3 + g % 5, 'M', 'uz', '', 3800 + g
    from generate_series(1, 96) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x59' || lpad(v.g::text, 3, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Wteli','Sinov Ona Wteli','447700900201','+998 00 555 77 01 (otasining teli)'),
  (2,'Sinov Ota Wteli','Sinov Ona Wteli','447700900201','+998 00 555 77 01 (otasining teli)'),
  (3,'Sinov Ota Wteli','Sinov Ona Wteli','447700900201','+998 00 555 77 01'),
  (4,'Sinov Ota Wteli',null,'+998 00 555 77 01','+998 00 666 88 11'),
  (5,'Sinov Ota Wrkm','Sinov Ona Wrkm','447700900202','+998 00 555 77 02 (otasi tel rakam)'),
  (6,'Sinov Ota Wrkm','Sinov Ona Wrkm','447700900202','+998 00 555 77 02 (otasi tel rakam)'),
  (7,'Sinov Ota Wrkm','Sinov Ona Wrkm','447700900202','+998 00 555 77 02'),
  (8,'Sinov Ota Wrkm',null,'+998 00 555 77 02','+998 00 666 88 12'),
  (9,'Sinov Ota Wrkmi','Sinov Ona Wrkmi','447700900203','+998 00 555 77 03 (otasi rakami)'),
  (10,'Sinov Ota Wrkmi','Sinov Ona Wrkmi','447700900203','+998 00 555 77 03 (otasi rakami)'),
  (11,'Sinov Ota Wrkmi','Sinov Ona Wrkmi','447700900203','+998 00 555 77 03'),
  (12,'Sinov Ota Wrkmi',null,'+998 00 555 77 03','+998 00 666 88 13'),
  (13,'Sinov Ota Wmobi','Sinov Ona Wmobi','447700900204','+998 00 555 77 04 (otasining mobili)'),
  (14,'Sinov Ota Wmobi','Sinov Ona Wmobi','447700900204','+998 00 555 77 04 (otasining mobili)'),
  (15,'Sinov Ota Wmobi','Sinov Ona Wmobi','447700900204','+998 00 555 77 04'),
  (16,'Sinov Ota Wmobi',null,'+998 00 555 77 04','+998 00 666 88 14'),
  (17,'Sinov Ota Wishi','Sinov Ona Wishi','447700900205','+998 00 555 77 05 (dadasining ishi)'),
  (18,'Sinov Ota Wishi','Sinov Ona Wishi','447700900205','+998 00 555 77 05 (dadasining ishi)'),
  (19,'Sinov Ota Wishi','Sinov Ona Wishi','447700900205','+998 00 555 77 05'),
  (20,'Sinov Ota Wishi',null,'+998 00 555 77 05','+998 00 666 88 15'),
  (21,'Sinov Ota Wishx','Sinov Ona Wishx','447700900206','+998 00 555 77 06 (otasining ishxonasi)'),
  (22,'Sinov Ota Wishx','Sinov Ona Wishx','447700900206','+998 00 555 77 06 (otasining ishxonasi)'),
  (23,'Sinov Ota Wishx','Sinov Ona Wishx','447700900206','+998 00 555 77 06'),
  (24,'Sinov Ota Wishx',null,'+998 00 555 77 06','+998 00 666 88 16'),
  (25,'Sinov Ota Wuyi','Sinov Ona Wuyi','447700900207','+998 00 555 77 07 (otasining uyi)'),
  (26,'Sinov Ota Wuyi','Sinov Ona Wuyi','447700900207','+998 00 555 77 07 (otasining uyi)'),
  (27,'Sinov Ota Wuyi','Sinov Ona Wuyi','447700900207','+998 00 555 77 07'),
  (28,'Sinov Ota Wuyi',null,'+998 00 555 77 07','+998 00 666 88 17'),
  (29,'Sinov Ota Wsotk','Sinov Ona Wsotk','447700900208','+998 00 555 77 08 (dadasi sotka)'),
  (30,'Sinov Ota Wsotk','Sinov Ona Wsotk','447700900208','+998 00 555 77 08 (dadasi sotka)'),
  (31,'Sinov Ota Wsotk','Sinov Ona Wsotk','447700900208','+998 00 555 77 08'),
  (32,'Sinov Ota Wsotk',null,'+998 00 555 77 08','+998 00 666 88 18'),
  (33,'Sinov Ota Wsotki','Sinov Ona Wsotki','447700900209','+998 00 555 77 09 (otasining sotkasi)'),
  (34,'Sinov Ota Wsotki','Sinov Ona Wsotki','447700900209','+998 00 555 77 09 (otasining sotkasi)'),
  (35,'Sinov Ota Wsotki','Sinov Ona Wsotki','447700900209','+998 00 555 77 09'),
  (36,'Sinov Ota Wsotki',null,'+998 00 555 77 09','+998 00 666 88 19'),
  (37,'Sinov Ota Wdni','Sinov Ona Wdni','447700900210','+998 00 555 77 10 (dadasini teli)'),
  (38,'Sinov Ota Wdni','Sinov Ona Wdni','447700900210','+998 00 555 77 10 (dadasini teli)'),
  (39,'Sinov Ota Wdni','Sinov Ona Wdni','447700900210','+998 00 555 77 10'),
  (40,'Sinov Ota Wdni',null,'+998 00 555 77 10','+998 00 666 88 20'),
  (41,'Sinov Ota Ktel','Sinov Ona Ktel','447700900211','+998 00 555 77 11 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1090) || chr(1077) || chr(1083) || chr(1080) || ')'),
  (42,'Sinov Ota Ktel','Sinov Ona Ktel','447700900211','+998 00 555 77 11 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1090) || chr(1077) || chr(1083) || chr(1080) || ')'),
  (43,'Sinov Ota Ktel','Sinov Ona Ktel','447700900211','+998 00 555 77 11'),
  (44,'Sinov Ota Ktel',null,'+998 00 555 77 11','+998 00 666 88 21'),
  (45,'Sinov Ota Krkm','Sinov Ona Krkm','447700900212','+998 00 555 77 12 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || ' ' || chr(1090) || chr(1077) || chr(1083) || ' ' || chr(1088) || chr(1072) || chr(1082) || chr(1072) || chr(1084) || ')'),
  (46,'Sinov Ota Krkm','Sinov Ona Krkm','447700900212','+998 00 555 77 12 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || ' ' || chr(1090) || chr(1077) || chr(1083) || ' ' || chr(1088) || chr(1072) || chr(1082) || chr(1072) || chr(1084) || ')'),
  (47,'Sinov Ota Krkm','Sinov Ona Krkm','447700900212','+998 00 555 77 12'),
  (48,'Sinov Ota Krkm',null,'+998 00 555 77 12','+998 00 666 88 22'),
  (49,'Sinov Ota Kraq','Sinov Ona Kraq','447700900213','+998 00 555 77 13 (' || chr(1054) || chr(1058) || chr(1040) || chr(1057) || chr(1048) || chr(1053) || chr(1048) || chr(1053) || chr(1043) || ' ' || chr(1056) || chr(1040) || chr(1050) || chr(1040) || chr(1052) || chr(1048) || ')'),
  (50,'Sinov Ota Kraq','Sinov Ona Kraq','447700900213','+998 00 555 77 13 (' || chr(1054) || chr(1058) || chr(1040) || chr(1057) || chr(1048) || chr(1053) || chr(1048) || chr(1053) || chr(1043) || ' ' || chr(1056) || chr(1040) || chr(1050) || chr(1040) || chr(1052) || chr(1048) || ')'),
  (51,'Sinov Ota Kraq','Sinov Ona Kraq','447700900213','+998 00 555 77 13'),
  (52,'Sinov Ota Kraq',null,'+998 00 555 77 13','+998 00 666 88 23'),
  (53,'Sinov Ota Kmobi','Sinov Ona Kmobi','447700900214','+998 00 555 77 14 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1084) || chr(1086) || chr(1073) || chr(1080) || chr(1083) || chr(1080) || ')'),
  (54,'Sinov Ota Kmobi','Sinov Ona Kmobi','447700900214','+998 00 555 77 14 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1084) || chr(1086) || chr(1073) || chr(1080) || chr(1083) || chr(1080) || ')'),
  (55,'Sinov Ota Kmobi','Sinov Ona Kmobi','447700900214','+998 00 555 77 14'),
  (56,'Sinov Ota Kmobi',null,'+998 00 555 77 14','+998 00 666 88 24'),
  (57,'Sinov Ota Kishi','Sinov Ona Kishi','447700900215','+998 00 555 77 15 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1080) || chr(1096) || chr(1080) || ')'),
  (58,'Sinov Ota Kishi','Sinov Ona Kishi','447700900215','+998 00 555 77 15 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1080) || chr(1096) || chr(1080) || ')'),
  (59,'Sinov Ota Kishi','Sinov Ona Kishi','447700900215','+998 00 555 77 15'),
  (60,'Sinov Ota Kishi',null,'+998 00 555 77 15','+998 00 666 88 25'),
  (61,'Sinov Ota Kishx','Sinov Ona Kishx','447700900216','+998 00 555 77 16 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1080) || chr(1096) || chr(1093) || chr(1086) || chr(1085) || chr(1072) || chr(1089) || chr(1080) || ')'),
  (62,'Sinov Ota Kishx','Sinov Ona Kishx','447700900216','+998 00 555 77 16 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1080) || chr(1096) || chr(1093) || chr(1086) || chr(1085) || chr(1072) || chr(1089) || chr(1080) || ')'),
  (63,'Sinov Ota Kishx','Sinov Ona Kishx','447700900216','+998 00 555 77 16'),
  (64,'Sinov Ota Kishx',null,'+998 00 555 77 16','+998 00 666 88 26'),
  (65,'Sinov Ota Kuyi','Sinov Ona Kuyi','447700900217','+998 00 555 77 17 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1091) || chr(1081) || chr(1080) || ')'),
  (66,'Sinov Ota Kuyi','Sinov Ona Kuyi','447700900217','+998 00 555 77 17 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1091) || chr(1081) || chr(1080) || ')'),
  (67,'Sinov Ota Kuyi','Sinov Ona Kuyi','447700900217','+998 00 555 77 17'),
  (68,'Sinov Ota Kuyi',null,'+998 00 555 77 17','+998 00 666 88 27'),
  (69,'Sinov Ota Ksotk','Sinov Ona Ksotk','447700900218','+998 00 555 77 18 (' || chr(1076) || chr(1072) || chr(1076) || chr(1072) || chr(1089) || chr(1080) || ' ' || chr(1089) || chr(1086) || chr(1090) || chr(1082) || chr(1072) || ')'),
  (70,'Sinov Ota Ksotk','Sinov Ona Ksotk','447700900218','+998 00 555 77 18 (' || chr(1076) || chr(1072) || chr(1076) || chr(1072) || chr(1089) || chr(1080) || ' ' || chr(1089) || chr(1086) || chr(1090) || chr(1082) || chr(1072) || ')'),
  (71,'Sinov Ota Ksotk','Sinov Ona Ksotk','447700900218','+998 00 555 77 18'),
  (72,'Sinov Ota Ksotk',null,'+998 00 555 77 18','+998 00 666 88 28'),
  (73,'Sinov Ota Ksotki','Sinov Ona Ksotki','447700900219','+998 00 555 77 19 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1089) || chr(1086) || chr(1090) || chr(1082) || chr(1072) || chr(1089) || chr(1080) || ')'),
  (74,'Sinov Ota Ksotki','Sinov Ona Ksotki','447700900219','+998 00 555 77 19 (' || chr(1086) || chr(1090) || chr(1072) || chr(1089) || chr(1080) || chr(1085) || chr(1080) || chr(1085) || chr(1075) || ' ' || chr(1089) || chr(1086) || chr(1090) || chr(1082) || chr(1072) || chr(1089) || chr(1080) || ')'),
  (75,'Sinov Ota Ksotki','Sinov Ona Ksotki','447700900219','+998 00 555 77 19'),
  (76,'Sinov Ota Ksotki',null,'+998 00 555 77 19','+998 00 666 88 29'),
  (77,'Sinov Ota Rsot','Sinov Ona Rsot','447700900220','+998 00 555 77 20 (' || chr(1089) || chr(1086) || chr(1090) || '. ' || chr(1086) || chr(1090) || chr(1094) || chr(1072) || ')'),
  (78,'Sinov Ota Rsot','Sinov Ona Rsot','447700900220','+998 00 555 77 20 (' || chr(1089) || chr(1086) || chr(1090) || '. ' || chr(1086) || chr(1090) || chr(1094) || chr(1072) || ')'),
  (79,'Sinov Ota Rsot','Sinov Ona Rsot','447700900220','+998 00 555 77 20'),
  (80,'Sinov Ota Rsot',null,'+998 00 555 77 20','+998 00 666 88 30'),
  (81,'Sinov Ota Rrab','Sinov Ona Rrab','447700900221','+998 00 555 77 21 (' || chr(1086) || chr(1090) || chr(1077) || chr(1094) || ', ' || chr(1088) || chr(1072) || chr(1073) || '.)'),
  (82,'Sinov Ota Rrab','Sinov Ona Rrab','447700900221','+998 00 555 77 21 (' || chr(1086) || chr(1090) || chr(1077) || chr(1094) || ', ' || chr(1088) || chr(1072) || chr(1073) || '.)'),
  (83,'Sinov Ota Rrab','Sinov Ona Rrab','447700900221','+998 00 555 77 21'),
  (84,'Sinov Ota Rrab',null,'+998 00 555 77 21','+998 00 666 88 31'),
  (85,'Sinov Ota Rdom','Sinov Ona Rdom','447700900222','+998 00 555 77 22 (' || chr(1076) || chr(1086) || chr(1084) || '. ' || chr(1090) || chr(1077) || chr(1083) || '. ' || chr(1086) || chr(1090) || chr(1094) || chr(1072) || ')'),
  (86,'Sinov Ota Rdom','Sinov Ona Rdom','447700900222','+998 00 555 77 22 (' || chr(1076) || chr(1086) || chr(1084) || '. ' || chr(1090) || chr(1077) || chr(1083) || '. ' || chr(1086) || chr(1090) || chr(1094) || chr(1072) || ')'),
  (87,'Sinov Ota Rdom','Sinov Ona Rdom','447700900222','+998 00 555 77 22'),
  (88,'Sinov Ota Rdom',null,'+998 00 555 77 22','+998 00 666 88 32'),
  (89,'Sinov Ota Rtfa','Sinov Ona Rtfa','447700900223','+998 00 555 77 23 (' || chr(1085) || chr(1086) || chr(1084) || chr(1077) || chr(1088) || ' ' || chr(1090) || chr(1077) || chr(1083) || chr(1077) || chr(1092) || chr(1086) || chr(1085) || chr(1072) || ' ' || chr(1086) || chr(1090) || chr(1094) || chr(1072) || ')'),
  (90,'Sinov Ota Rtfa','Sinov Ona Rtfa','447700900223','+998 00 555 77 23 (' || chr(1085) || chr(1086) || chr(1084) || chr(1077) || chr(1088) || ' ' || chr(1090) || chr(1077) || chr(1083) || chr(1077) || chr(1092) || chr(1086) || chr(1085) || chr(1072) || ' ' || chr(1086) || chr(1090) || chr(1094) || chr(1072) || ')'),
  (91,'Sinov Ota Rtfa','Sinov Ona Rtfa','447700900223','+998 00 555 77 23'),
  (92,'Sinov Ota Rtfa',null,'+998 00 555 77 23','+998 00 666 88 33'),
  (93,'Sinov Ota Rmbn','Sinov Ona Rmbn','447700900224','+998 00 555 77 24 (' || chr(1087) || chr(1072) || chr(1087) || chr(1080) || chr(1085) || ' ' || chr(1084) || chr(1086) || chr(1073) || chr(1080) || chr(1083) || chr(1100) || chr(1085) || chr(1080) || chr(1082) || ')'),
  (94,'Sinov Ota Rmbn','Sinov Ona Rmbn','447700900224','+998 00 555 77 24 (' || chr(1087) || chr(1072) || chr(1087) || chr(1080) || chr(1085) || ' ' || chr(1084) || chr(1086) || chr(1073) || chr(1080) || chr(1083) || chr(1100) || chr(1085) || chr(1080) || chr(1082) || ')'),
  (95,'Sinov Ota Rmbn','Sinov Ona Rmbn','447700900224','+998 00 555 77 24'),
  (96,'Sinov Ota Rmbn',null,'+998 00 555 77 24','+998 00 666 88 34')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o)
       || ' || ' || coalesce((select (r -> 'father' ->> 'phone') || ' / ' || (r -> 'mother' ->> 'phone')
                                from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal('Sinov Ota Wteli')) -> 'rows', '[]'::jsonb)) r
                               where r -> 'father' ->> 'name' = 'Sinov Ota Wteli' limit 1), '-') as h59
  from (values (1, 'Sinov Ota Wteli'), (2, 'Sinov Ota Wrkm'), (3, 'Sinov Ota Wrkmi'), (4, 'Sinov Ota Wmobi'), (5, 'Sinov Ota Wishi'), (6, 'Sinov Ota Wishx'), (7, 'Sinov Ota Wuyi'), (8, 'Sinov Ota Wsotk'), (9, 'Sinov Ota Wsotki'), (10, 'Sinov Ota Wdni'), (11, 'Sinov Ota Ktel'), (12, 'Sinov Ota Krkm'), (13, 'Sinov Ota Kraq'), (14, 'Sinov Ota Kmobi'), (15, 'Sinov Ota Kishi'), (16, 'Sinov Ota Kishx'), (17, 'Sinov Ota Kuyi'), (18, 'Sinov Ota Ksotk'), (19, 'Sinov Ota Ksotki'), (20, 'Sinov Ota Rsot'), (21, 'Sinov Ota Rrab'), (22, 'Sinov Ota Rdom'), (23, 'Sinov Ota Rtfa'), (24, 'Sinov Ota Rmbn')) x(o, n) \gset
rollback to savepoint h59;
select zz.chk('H59 aka-uka: ota yorlig''idagi telefon so''zining egalik shakli, ' || chr(171) || chr(1082) || chr(187) || ' bilan yozuvi, so''zlashuvdagi va ruscha qisqartmasi ham yorliq (ajratuvchi karta bilan himoya)',
  :'h59', '^\+998005557701 true \+998006668811 true \| \+998005557702 true \+998006668812 true \| \+998005557703 true \+998006668813 true \| \+998005557704 true \+998006668814 true \| '
       || '\+998005557705 true \+998006668815 true \| \+998005557706 true \+998006668816 true \| \+998005557707 true \+998006668817 true \| \+998005557708 true \+998006668818 true \| '
       || '\+998005557709 true \+998006668819 true \| \+998005557710 true \+998006668820 true \| \+998005557711 true \+998006668821 true \| \+998005557712 true \+998006668822 true \| '
       || '\+998005557713 true \+998006668823 true \| \+998005557714 true \+998006668824 true \| \+998005557715 true \+998006668825 true \| \+998005557716 true \+998006668826 true \| '
       || '\+998005557717 true \+998006668827 true \| \+998005557718 true \+998006668828 true \| \+998005557719 true \+998006668829 true \| \+998005557720 true \+998006668830 true \| '
       || '\+998005557721 true \+998006668831 true \| \+998005557722 true \+998006668832 true \| \+998005557723 true \+998006668833 true \| \+998005557724 true \+998006668834 true \|\| '
       || '\+998 00 \*\*\* \*\* 01 / \+998 00 \*\*\* \*\* 11$');

-- H60 — savepoint ichida (aka-uka kartalari; 15-mustaqil tekshiruv). Ota guruhining vakili (fpr): shu ism sinfi bo'yicha tanlov (o3)
--   bilan barcha ota nomzodi kataklari bo'yicha tanlov (o2) farq qilsa — ota ismi yozilgan ota kataklarida ko'proq turgani. Rgl — H56 Dqs
--   ning ko'zgusi: ota ismli onasiz kartalarda ikki raqamli ota katagi (biri so'zga yopishgan) va ona katagida otaning raqami «(otasi)», ona
--   ismli kartalarda ota katagida otaning raqami, ona katagida onaning ikki raqami; Ruc — onasi ro'yxatdan o'tkazgan kartalarning
--   ko'pchiligida ota katagida otaning raqami. 735cae3 da ota qatorida onaning raqami (Ruc da ona qatorida otaning raqami ham) chiqardi
--   (2a91fa9, 8f9925d va 67b0e73 to'g'ri edi, 025c023 — 735cae3 dagidek; H56 / H58 o'zgarmaydi).
savepoint h60;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x60' || lpad(g::text, 2, '0'), 'IQ-X60' || lpad(g::text, 2, '0'), 'Sinov Bola X60' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 3900 + g
    from generate_series(1, 16) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x60' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Rgl','Sinov Ona Rgl','+998 00 111 21 96','+998 00 222 42 69, +998 00 333 63 58'),
  (2,'Sinov Ota Rgl',null,'998001112196ota, +998 00 222 42 69','+998 00 111 21 96 (otasi)'),
  (3,'Sinov Ota Rgl',null,'+998 00 111 21 96, 998002224269ona','+998 00 111 21 96 (otasi)'),
  (4,null,'Sinov Ona Rgl','+998 00 111 21 96','+998 00 222 42 69, +998 00 333 63 58'),
  (5,null,'Sinov Ona Rgl','+998 00 111 21 96','+998 00 222 42 69, +998 00 333 63 58'),
  (6,'Sinov Ota Ruc','Sinov Ona Ruc','+998 00 111 21 87',null),
  (7,'Sinov Ota Ruc','Sinov Ona Ruc','+998 00 222 42 78',null),
  (8,'Sinov Ota Ruc',null,'+998 00 111 21 87','+998 00 222 42 78'),
  (9,'Sinov Ota Ruc',null,'998001112187ota, +998 00 222 42 78','+998 00 111 21 87'),
  (10,'Sinov Ota Ruc',null,'+998 00 111 21 87, 998002224278ona','+998 00 111 21 87'),
  (11,'Sinov Ota Ruc',null,'+998 00 111 21 87, 998002224278ona','+998 00 111 21 87'),
  (12,'Sinov Ota Ruc',null,null,'+998 00 111 21 87'),
  (13,null,'Sinov Ona Ruc','+998 00 111 21 87',null),
  (14,null,'Sinov Ona Ruc','+998 00 111 21 87',null),
  (15,null,'Sinov Ona Ruc','+998 00 111 21 87',null),
  (16,null,'Sinov Ona Ruc','+998 00 222 42 78',null)) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(coalesce(zz.rv(x.n) #>> '{father,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{father,valid}', '-') || ' '
                  || coalesce(zz.rv(x.n) #>> '{mother,phone}', '-') || ' ' || coalesce(zz.rv(x.n) #>> '{mother,valid}', '-'), ' | ' order by x.o)
       || ' || ' || coalesce((select (r -> 'father' ->> 'phone') || ' / ' || (r -> 'mother' ->> 'phone')
                                from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal('Sinov Ota Rgl')) -> 'rows', '[]'::jsonb)) r
                               where r -> 'father' ->> 'name' = 'Sinov Ota Rgl' limit 1), '-') as h60
  from (values (1, 'Sinov Ota Rgl'), (2, 'Sinov Ota Ruc')) x(o, n) \gset
rollback to savepoint h60;
select zz.chk('H60 aka-uka: ota guruhining vakili ' || chr(8212) || ' shu ism sinfi va barcha sinf bo''yicha tanlov farq qilsa, ota ismli ota kataklarida ko''proq turgani (ona ismli kartalardagi otaning raqami tashlanmaydi)',
  :'h60', '^\+998 00 111 21 96 false \+998 00 222 42 69, \+998 00 333 63 58 false \| \+998 00 111 21 87 false \+998002224278 true \|\| '
       || '\+998 00 \*\*\* \*\* 96 / \+998 00 \*\*\* \*\* 69$');

-- H61 — savepoint ichida (aka-uka kartalari; 15-raund tuzatishlarining o'z mutatsiya tahlili). Ota guruhining vakili (fpr), M2 ning
--   qolgan ikki kaliti: Rtie — ikki kalit (o3, o2) turli o'qishni tanlaydi va ota ismli ota kataklarida ikkalasi teng uchraydi — shu ism
--   sinfi bo'yicha tanlov qoladi (teng holatda barcha sinf tanlovi olinsa — ota qatorida onaning raqami); Rfrq — ota ismli ikki raqamli
--   kataklar, ikki komponent: shu ism sinfi kalitlari teng, guruhda ko'proq uchragan o'qish hal qiladi (chastota olib tashlansa — ota
--   qatorida onaning raqami). Ikkala oila 14-raund tekshiruvchisining genF generatoridan (genF_2:G00321, genF_3:G00257; to'qima
--   raqamlar). 735cae3 va 025c023 da to'g'ri; 2a91fa9 da Rtie (ota qatorida onaning raqami, ona
--   qatorida maktab raqami), 8f9925d da Rfrq, 67b0e73 da ikkalasi yiqiladi.
savepoint h61;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'x61' || lpad(g::text, 2, '0'), 'IQ-X61' || lpad(g::text, 2, '0'), 'Sinov Bola X61' || lpad(g::text, 2, '0'), 3 + g % 5, 'M', 'uz', '', 4000 + g
    from generate_series(1, 13) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'x61' || lpad(v.g::text, 2, '0'), v.fn, v.mn, v.fp, v.mp from (values
  (1,'Sinov Ota Rtie',null,'+998 (02) 348-85-05','02 360 37 66'),
  (2,'Sinov Ota Rtie',null,'+998 (02) 360-37-66ona; +998 (02) 348-85-05','tel998009990031'),
  (3,null,'Sinov Ona Rtie','+998 02 360 37 66',null),
  (4,null,'Sinov Ona Rtie','+998 02 360 37 66',''),
  (5,'Sinov Ota Rtie',null,'02 360 37 66; +998 02 348 85 05otasi','tel998009990031'),
  (6,'Sinov Ota Rtie',null,'02 360 37 66mob; +998 (02) 348-85-05','998009990031tel'),
  (7,'Sinov Ota Rtie','Sinov Ona Rtie','(02) 360-37-66','tel998009990031'),
  (8,'Sinov Ota Rtie',null,'+998023603766; +998 02 348 85 05tel','998009990031maktab'),
  (9,'Sinov Ota Rfrq',null,'+998 00 790 63 52tel, 998025160869','tel998009990031'),
  (10,'Sinov Ota Rfrq',null,'+998007906352, 02 516 08 69ota','tel998009990031'),
  (11,'Sinov Ota Rfrq',null,'+998007906352onasi, +998 02 516 08 69','998009990031tel'),
  (12,'Sinov Ota Rfrq',null,'+998025160869','998007906352'),
  (13,'Sinov Ota Rfrq',null,'+998 00 790 63 52, 998025160869ota','tel998009990031')) v(g, fn, mn, fp, mp);
set local session_replication_role = origin;
select string_agg(x.n || ': ' || coalesce((select string_agg(coalesce(q.v #>> '{father,phone}', '-') || ' ' || coalesce(q.v #>> '{father,valid}', '-') || ' / '
                                                             || coalesce(q.v #>> '{mother,phone}', '-') || ' ' || coalesce(q.v #>> '{mother,valid}', '-'), ' + '
                                                             order by q.v #>> '{father,phone}', q.v #>> '{mother,phone}')
                                             from (select zz.j(zz.as('U_SAL2', format('select public.sales_reveal(%L)::text', r ->> 'k'))) as v
                                                     from jsonb_array_elements(coalesce(zz.list('U_SAL', quote_literal(x.n)) -> 'rows', '[]'::jsonb)) r
                                                    where r -> 'father' ->> 'name' = x.n) q), '-'), ' | ' order by x.o) as h61
  from (values (1, 'Sinov Ota Rtie'), (2, 'Sinov Ota Rfrq')) x(o, n) \gset
rollback to savepoint h61;
select zz.chk('H61 aka-uka: ota guruhining vakili ' || chr(8212) || ' ikki kalit teng ism dalilida shu ism sinfi tanlovi, shu ism sinfi kalitlari tengida guruhdagi chastota',
  :'h61', '^Sinov Ota Rtie: \+998 02 348-85-05 false / \+998023603766 true \| Sinov Ota Rfrq: \+998025160869 true / \+998007906352 true \+ 998025160869 false / \*\*\* \*\* 31 false$');

-- har tekshiruv yozildimi (savepoint ichida yo'qolgan yoki bajarilmay qolgan tekshiruv — FAIL)
select count(*)::text as yozilgan from zz.res \gset
select zz.chk('ZZ yozilgan tekshiruvlar soni = kutilgan', :'yozilgan', '^' || :'kutilgan' || '$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL (jami ' || count(*) || ')' from zz.res;
rollback;
