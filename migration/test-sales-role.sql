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
\set kutilgan 76
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
select zz.chk('H09 raqam shakli: bir katakda ikki raqam — valid:false, niqob — oxirgi 2 raqam, ochganda — kartadagi ASL yozuv; xorij raqami — valid:true, «+»; ro''yxatda uzun raqam yo''q',
  coalesce((select (r -> 'father')::text || ' ' || (r -> 'mother')::text from jsonb_array_elements(zz.j(:'h_list') -> 'rows') r
             where r -> 'father' ->> 'name' = 'Sinov Ota Sigma'), '-')
  || ' | ' || coalesce((zz.j(:'h_rv2') -> 'father')::text || ' ' || (zz.j(:'h_rv2') -> 'mother')::text, left(:'h_rv2', 90))
  || ' | ' || coalesce((regexp_match(regexp_replace(:'h_list', '"k": "[0-9a-f]{32}"', '', 'g'), '\d{5,}'))[1], 'yoq'),
  '^\{"name": "Sinov Ota Sigma", "phone": "\*\*\* \*\* 32", "valid": false\} \{"name": "Sinov Ona Sigma", "phone": "\*\*\* \*\* 33", "valid": true\}'
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
  ('q20','IQ-Q20','Sinov Bola Q20',5,'F','uz','',320), ('q21','IQ-Q21','Sinov Bola Q21',6,'F','uz','',321);
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
  ('q17',null,'Sinov Ona Vee','+998 00 999 00 08','+998 00 888 00 08');                      --      katak, ota ismisiz kartada bitta raqam
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
select zz.chk('H24 ona raqami ikkala katakda, ota ismi yo''q — otaniki bo''lib takrorlanmaydi; ismli kartadagi ikki raqamli «ota telefoni» — ota ismisiz kartadagi raqamdan ustun',
  coalesce(coalesce(zz.j(:'h24z_rv') ->> 'father', 'null') || ' ' || (zz.j(:'h24z_rv') #>> '{mother,phone}'), left(:'h24z_rv', 120)) || ' | '
  || coalesce((zz.j(:'h24v_rv') #>> '{father,name}') || ' ' || (zz.j(:'h24v_rv') #>> '{father,phone}') || ' ' || (zz.j(:'h24v_rv') #>> '{mother,phone}'), left(:'h24v_rv', 120)),
  '^null \+998008880010 \| Sinov Ota Vee \+998 00 777 00 08, \+998 00 777 00 09 \+998008880008$');

-- H25 — savepoint ichida: bitta umumiy raqamli 500 karta (ota ismi «-», ona ismi yo'q, maktab raqami) — hammasi o'zaro bog'langan bitta
--   katta qism (bitta oila). Oilalar ro'yxati chiziqli vaqtda (union-find): avvalgi juftlik + to'liq tutashuv usuli kub vaqt oldi
--   (400 kartada ~8 s, 500 da ~16 s, 1000 da ~2 daqiqa — sotuvchi ro'yxati va Direktor jurnali ochilmay qolardi).
savepoint h25;
set local session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order")
  select 'zb' || g, 'IQ-ZB' || g, 'Sinov Bola ZB' || g, 1 + g % 11, 'Z', 'uz', '', 1000 + g from generate_series(1, 500) g;
insert into public.student_private (id, "fatherName", "motherName", "parentPhone", "parentPhone2")
  select 'zb' || g, '-', null, '+998 00 555 55 55', null from generate_series(1, 500) g;
set local session_replication_role = origin;
set local statement_timeout = '90s';
select zz.q($q$select (select count(*) from app.sales_families(false) f where f.f_name = '-')::text || ' ' || (extract(epoch from clock_timestamp() - t0) * 1000 < 5000)::text
                from (select clock_timestamp() as t0) z$q$) as h25 \gset
rollback to savepoint h25;
select zz.chk('H25 bitta umumiy raqamli 500 karta (ota ismi «-», ona ismi yo''q) — bitta oila, ro''yxat tez hisoblanadi (5 s dan kam)',
  :'h25', '^1 true$');

-- har tekshiruv yozildimi (savepoint ichida yo'qolgan yoki bajarilmay qolgan tekshiruv — FAIL)
select count(*)::text as yozilgan from zz.res \gset
select zz.chk('ZZ yozilgan tekshiruvlar soni = kutilgan', :'yozilgan', '^' || :'kutilgan' || '$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL (jami ' || count(*) || ')' from zz.res;
rollback;
