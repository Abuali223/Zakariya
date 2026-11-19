-- =====================================================================
-- test-payer-codes.sql — payer-code-mask.sql sinovi (egasi qarori (a), 2026-11-16): to'lovchi matnidagi maxfiy kod yashiriladi
--   (payments: merchant_trans_id, payerName, payerClass, payerPhone, raw; refunds."studentName"), ochilgan JORIY kod almashtiriladi
--   (eski kod student_code_prev ga), qayta chaqiruv hech narsani o'zgartirmaydi, claim_child: eski kod -> 'code_changed' (ulanmaydi,
--   urinish sanaladi), yangi kod -> ulanadi, lockout ishlaydi; to'qnash kalitli eski bog'lanish uzilmaydi (claim_row); eski kodlar
--   jadvalini mijoz rollari o'qiy / yoza olmaydi; moliya rollari o'qiydigan to'lov va qaytarish qatorlarida kod yo'q;
--   gen_student_code (arvoh kod meros qolmaydi), qo'lda o'zgartirish / o'chirish triggeri. --dev zanjirda qo'shimcha: davr qulfi va
--   kassa hujjatiga bog'langan qator — tuzatish o'tadi, oddiy foydalanuvchi uchun qulf o'z joyida.
--   2-raund: guruhlab yozilgan («3FA9 C21B 7D0E», «-», «.», 6+6, sinf bilan) va kiril / «O» harfli guruh — aniqlanadi va yashiriladi;
--   eski kodlar ro'yxatiga faqat tranzaksiyadan OLDIN joriy bo'lgan 12 belgili kod yoziladi (zanjir qayta ishlashi — security-2b /
--   audit-4, tiklash, bir tranzaksiyada boshqa o'quvchining yangi kodi); qisqa yaroqsiz «eski kod» tozalanadi va qidiruv uzunligini
--   tushirmaydi; yangi kod har doim harfli; ochilgan kod bilan ulangan faol bog'lanishlar sanaladi (ota-ona bo'lmagan hisob — alohida).
--   3-raund: ajratgich — 1–2 ta belgi (bo'sh joy, tab, «.», «,», «-», «_», «/») yoki 3 tagacha bo'sh joy belgisi (yangi qator ham) —
--   aniqlanadi, yashiriladi, kod almashtiriladi; «[kod]» — kod va qatorda unga yondosh hex bo'laklar (yaqin nusxa ham), IQ-ID va so'z
--   qoladi (payments/index.cjs bilan AYNAN bir xil — M19 / M23 = mask.test.cjs P1 / P2); arvoh kod OLDINGI tranzaksiyadan (G2 —
--   gen_student_code uni o'zi «shu tranzaksiyaniki» deb belgilaydi).
--   4-raund: kod matnda FAQAT yangi qator / CR LF / bo'linmas bo'sh joy bilan ajratilgan (M25 — aniqlash qoidasining shu qismi alohida
--   tekshiriladi); o'chirilgan o'quvchi tiklanganda qaytgan kod to'lovchi matnida ochiq bo'lsa — darhol almashtiriladi (T1–T4).
--   5-raund: to'lov serveri taniydigan IQ-ID raqami («IQ+0043», «ИҚ-0043», «IQ = 0043») «[kod]» ga qo'shilmaydi (M26 = mask.test.cjs P3).
--   Butun sinov BITTA tranzaksiya: urug' «oldingi tranzaksiyada yozilgan» bo'lishi uchun iqror.code_fresh tozalanadi (izohli joylarda).
--   Har chaqiruv haqiqiy rol bilan (anon yoki authenticated + JWT sub) — RLS va GRANT haqiqiy.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin (jonli yoki --dev):
--     bash migration/chain.sh [--dev] --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-payer-codes.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK — bazada hech narsa qolmaydi. Ismlar va kodlar to'qima.
--   Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-payer-codes.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
set local iqror.migrating = '1';   -- urug' change_log'ga yozilmasin
insert into public.users (id, email, role, status) values
  ('U_DIR','dir@example.org','director','active'), ('U_FIN','fin@example.org','finance_mgr','active'),
  ('U_TRE','tre@example.org','treasurer','active'), ('U_KAS','kas@example.org','kassir','active'),
  ('U_REC','rec@example.org','reception','active'), ('U_ZAV','zav@example.org','zavuch','active'),
  ('U_PA','pa@example.org','parent','active'), ('U_PB','pb@example.org','parent','active'), ('U_PK','pk@example.org','parent','active'),
  ('U_PC','pc@example.org','parent','active'), ('U_TCH','tch@example.org','teacher','active')
on conflict (id) do update set role = excluded.role, status = excluded.status;
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values
  ('docA1','IQ-0701','Sinov Aziz',7,'A','uz'),        -- kodi merchant_trans_id / payerName da (import: doc id != studentId)
  ('IQ-0702','IQ-0702','Sinov Bobur',7,'A','uz'),     -- kodi payerClass da (kichik harf)
  ('IQ-0703','IQ-0703','Sinov Dilshod',7,'B','uz'),   -- JORIY kodi hech qayerda yo'q (almashtirilmaydi); ESKI kodi to'lovda
  ('IQ-0704','IQ-0704','Sinov Eldor',8,'A','uz'),     -- kodi Uzum raw (params.account) da
  ('IQ-0705','IQ-0705','Sinov Farrux',8,'A','uz'),    -- kodi faqat refunds."studentName" da
  ('IQ-0706','IQ-0706','Sinov Gulom',8,'B','uz'),     -- kodi kiril harflari bilan va bo'sh joysiz
  ('IQ-0707','IQ-0707','Sinov Hamid',9,'A','uz'),     -- raqamli kod raw'da SON bo'lib
  -- eski import to'qnashuvi: docK1.studentId = boshqa qatorning doc id'si (IQ-0790) — kalit 'IQ-0790' ikki qatorga mos
  ('docK1','IQ-0790','Sinov Kamol',9,'A','uz'),
  ('IQ-0790','','Sinov Lola',9,'B','uz'),
  ('IQ-0708','IQ-0708','Sinov Ilhom',9,'B','uz'),     -- kodi hech qayerda yo'q (J4: bir tranzaksiyada haqiqiy almashtirish)
  ('IQ-0709','IQ-0709','Sinov Jasur',6,'A','uz'),     -- kodi «-» bilan guruhlab yozilgan
  ('IQ-0710','IQ-0710','Sinov Komil',6,'A','uz'),     -- kodi ID bilan, 6+6 guruh
  ('IQ-0715','IQ-0715','Sinov Laziz',6,'B','uz'),     -- kodi payerClass da, sinf bilan guruh
  ('IQ-0716','IQ-0716','Sinov Mirzo',6,'B','uz'),     -- kodi «.» bilan guruhlab yozilgan
  ('IQ-0717','IQ-0717','Sinov Nodir',6,'B','uz'),     -- kodi kiril harflari va «O» bilan guruhlab yozilgan
  ('IQ-0718','IQ-0718','Sinov Olim',6,'A','uz'),      -- kodi ikki bo'sh joy bilan; qatorma-qator va «, » bilan (3-raund)
  ('IQ-0719','IQ-0719','Sinov Pulat',6,'A','uz'),     -- kodi «_» bilan (ID bilan)
  ('IQ-0720','IQ-0720','Sinov Rustam',6,'B','uz'),    -- kodi payerClass da «, » va «/» bilan (sinf bilan)
  ('IQ-0725','IQ-0725','Sinov Sobir',5,'A','uz'),     -- kodi FAQAT qatorma-qator (yangi qator) yozilgan, payerName neytral (4-raund)
  ('IQ-0726','IQ-0726','Sinov Tohir',5,'A','uz'),     -- kodi FAQAT CR LF bilan ajratilgan
  ('IQ-0727','IQ-0727','Sinov Umid',5,'B','uz')       -- kodi FAQAT bo'linmas bo'sh joy (NBSP) bilan ajratilgan
on conflict (id) do nothing;
update public.student_codes sc set code = v.c from (values ('docA1','A1B2C3D4E5F6'), ('IQ-0702','B2C3D4E5F6A1'), ('IQ-0703','C3D4E5F6A1B2'),
  ('IQ-0704','D4E5F6A1B2C3'), ('IQ-0705','E5F6A1B2C3D4'), ('IQ-0706','F6A1B2C3D4E5'), ('IQ-0707','123456789012'),
  ('docK1','1A2B3C4D5E6F'), ('IQ-0790','2B3C4D5E6F1A'), ('IQ-0708','3C4D5E6F1A2B'), ('IQ-0709','4D5E6F1A2B3C'), ('IQ-0710','5E6F1A2B3C4D'),
  ('IQ-0715','6F1A2B3C4D5E'), ('IQ-0716','A2B3C4D5E6F1'), ('IQ-0717','B3C4D5E6F1A0'), ('IQ-0718','C4D5E6F1A2B3'), ('IQ-0719','D5E6F1A2B3C4'),
  ('IQ-0720','E6F1A2B3C4D5'), ('IQ-0725','A7B8C9D0E1F2'), ('IQ-0726','B8C9D0E1F2A3'), ('IQ-0727','C9D0E1F2A3B4')) v(id, c) where sc.id = v.id;
-- J0: o'quvchi qo'shilganda berilgan kodlar shu tranzaksiyada almashtirildi — eski kodlar ro'yxatiga hech biri yozilmasligi kerak
select set_config('zz.j0', (select count(*)::text from public.student_code_prev), true);
insert into public.student_code_prev (code, "studentDocId") values ('0F1E2D3C4B5A', 'IQ-0703');   -- IQ-0703 ning ESKI kodi
insert into public.student_code_prev (code, "studentDocId") values ('23BDBA', 'IQ-0703');         -- 1-raund xatosi: qisqa yaroqsiz «eski kod»
insert into public.child_claims (id, uid, "studentId", code, status) values ('cc_pk','U_PK','IQ-0790','2B3C4D5E6F1A','active'),
  ('cc_pc1','U_PC','IQ-0701','A1B2C3D4E5F6','active'),      -- ochiladigan kod bilan ulangan (ota-ona)
  ('cc_tch','U_TCH','IQ-0701','a1b2c3d4e5f6','active'),     -- ochiladigan kod bilan ulangan (o'qituvchi hisobi — ota-ona emas)
  ('cc_pc2','U_PC','docK1','1A2B3C4D5E6F','active'),        -- ochilmagan kod bilan — sanalmaydi
  ('cc_pc3','U_PC','IQ-0704','D4E5F6A1B2C3','revoked')      -- bekor qilingan — sanalmaydi
on conflict (id) do nothing;
insert into public.payments (id, provider, click_trans_id, merchant_trans_id, "payerName", "payerClass", "payerPhone", amount, status, matched, "studentId", raw) values
  ('click_t1','click','t1','IQ-0701 a1b2c3d4e5f6','IQ-0701 a1b2c3d4e5f6','7A','998000000001',100000,'applied',true,'IQ-0701','{"mode":"freeform","via":"code"}'),
  ('click_t2','click','t2','Sinov Bobur','Sinov Bobur','7a b2c3d4e5f6a1','998000000002',100000,'unmatched',false,'','{"mode":"freeform","via":"notfound"}'),
  ('click_t3','click','t3','IQ-0703 0f1e2d3c4b5a','IQ-0703 0f1e2d3c4b5a','','',100000,'applied',true,'IQ-0703','{"mode":"freeform","via":"code"}'),
  ('uzum_t4','uzum',null,null,null,null,null,50000,'confirmed',null,'IQ-0704','{"serviceId":"S","transId":"t4","params":{"account":"IQ-0704 D4E5F6A1B2C3"},"amount":5000000,"appliedTo":"invoice"}'),
  ('click_t5','click','t5','Sinov Farrux','Sinov Farrux','','',70000,'refunded',false,'','{"mode":"freeform","via":"ambiguous"}'),
  ('click_t6','click','t6','Kod: F6А1В2С3D4Е5','Kod: F6А1В2С3D4Е5','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t6b','click','t6b','IQ0706F6A1B2C3D4E5','IQ0706F6A1B2C3D4E5','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('uzum_t7','uzum',null,null,null,null,null,10000,'confirmed',null,'IQ-0707','{"params":{"account":123456789012},"amount":1000000}'),
  ('click_t8','click','t8','IQ-0790 2b3c4d5e6f1a','IQ-0790 2b3c4d5e6f1a','','',100000,'applied',true,'IQ-0790','{"mode":"freeform","via":"code"}'),
  ('man_t9','cash',null,null,'Sinov Aziz A1B2C3D4E5F6','','',100000,'applied',true,'IQ-0701','{"manual":true,"method":"cash","date":"2026-11-02"}'),
  ('click_t11','click','t11','Sinov 23BDBA Ota','Sinov 23BDBA Ota','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t12','click','t12','IQ-0702 B2C3 D4E5 F6A1','IQ-0702 B2C3 D4E5 F6A1','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t13','click','t13','4d5e-6f1a-2b3c','4d5e-6f1a-2b3c','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t14','click','t14','IQ-0710 5E6F1A 2B3C4D','IQ-0710 5E6F1A 2B3C4D','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t15','click','t15','Sinov Ota','Sinov Ota','5A 6F1A2B3C 4D5E','998000000015',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t16','click','t16','Sinov Ota A2B3.C4D5.E6F1','Sinov Ota A2B3.C4D5.E6F1','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t17','click','t17','В3С4 D5Е6 F1АO','В3С4 D5Е6 F1АO','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t18','click','t18','Sinov Ota  C4D5  E6F1  A2B3','Sinov Ota  C4D5  E6F1  A2B3','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t19','click','t19','IQ-0719 D5E6_F1A2_B3C4','IQ-0719 D5E6_F1A2_B3C4','5A, E6F1/A2B3/C4D5','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t20','click','t20',E'Ota\nC4D5\nE6F1\nA2B3',E'Kod:\tC4D5, E6F1, A2B3','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  -- kod ikki maydonga bo'lingan (yarmi payerName oxirida, yarmi payerClass boshida): maydonlar alohida tekshiriladi (JS bilan bir xil) —
  --   aniqlanmaydi, IQ-0708 kodi almashtirilmaydi (R3)
  ('click_t21','click','t21','Sinov Ota','Sinov Ota 3C4D5E','6F1A2B 7A','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  -- kod matnda FAQAT yangi qator / CR LF / NBSP bilan ajratilgan (payerName neytral): aniqlashning shu qismi alohida (M25)
  ('click_t22','click','t22',E'Kod\nA7B8\nC9D0\nE1F2','Sinov Ota','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t23','click','t23',E'B8C9\r\nD0E1\r\nF2A3','Sinov Ota','','',100000,'unmatched',false,'','{"mode":"freeform"}'),
  ('click_t24','click','t24',E'Kod:\u00a0C9D0\u00a0E1F2\u00a0A3B4','Sinov Ota','','',100000,'unmatched',false,'','{"mode":"freeform"}')
on conflict (id) do nothing;
-- eski (--dev zanjirda yopilgan davrdagi) to'lov — tizim nomidan yozilganda createdAt saqlanadi
insert into public.payments (id, provider, click_trans_id, merchant_trans_id, "payerName", amount, status, matched, "studentId", raw, "createdAt") values
  ('click_t10','click','t10','IQ-0701 A1B2C3D4E5F6','IQ-0701 A1B2C3D4E5F6',100000,'applied',true,'IQ-0701','{"mode":"freeform","via":"code"}','2026-01-15T10:00:00+05')
on conflict (id) do nothing;
insert into public.refunds (id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, "createdAt") values
  ('rf_t5','payment','click_t5','','Sinov Ota E5F6A1B2C3D4',70000,'Sinov qaytarish','','',now())
on conflict (id) do nothing;
set local iqror.migrating = '';
select set_config('iqror.code_fresh', '', true);   -- urug' — oldingi tranzaksiyada yozilgan (kodlar ota-onalarga berilgan) deb

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
create table if not exists zz.tok (k text primary key, v text);
truncate zz.tok;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- Hamma joriy va eski kodlar — regex (mustaqil tekshiruv: oddiy katta-kichik harfsiz qidiruv, app.payer_* ishlatilmaydi).
create or replace function zz.codes_re() returns text language sql as $$
  select string_agg(c, '|') from (select upper(code) c from public.student_codes where coalesce(code, '') <> ''
                                   union select code from public.student_code_prev) x
$$;
-- Holat izi (qayta chaqiruv hech narsani o'zgartirmasligi uchun)
create or replace function zz.state_md5() returns text language sql as $$
  select md5(string_agg(t, '|' order by t)) from (
    select 'p' || to_jsonb(p)::text t from public.payments p union all select 'r' || to_jsonb(f)::text from public.refunds f
    union all select 'c' || to_jsonb(c)::text from public.student_codes c union all select 'v' || to_jsonb(v)::text from public.student_code_prev v) x
$$;
-- Pul / holat ustunlari izi (yashirish ularga tegmasligi kerak)
create or replace function zz.money_md5() returns text language sql as $$
  select md5(string_agg(concat_ws('#', id, provider, amount, status, matched, "studentId", "invoiceId", "createdAt", "statusAt"), '|' order by id))
    from public.payments
$$;

-- ===== Tuzatishdan oldin =====
insert into zz.tok values ('money0', zz.money_md5()), ('t5row', (select to_jsonb(p)::text from public.payments p where id = 'click_t5'));
select zz.chk('B0 urug'': kod uchragan to''lov qatorlari (oddiy qidiruv; kiril harfli va guruhlab yozilganlar bundan tashqari, click_t11 — qisqa yaroqsiz «eski kod») — 10',
  (select count(*)::text from public.payments where upper(concat_ws(' ', merchant_trans_id, "payerName", "payerClass", "payerPhone", raw::text)) ~ zz.codes_re()), '^10$');

-- DEV zanjir: davr qulfi (2026-06-30 gacha — click_t10 yopilgan davrda) va kassa hujjatiga bog'langan qator — tuzatish (tizim
--   nomidan) o'tishi kerak
do $dev$ begin
  if to_regclass('public.cash_docs') is not null then
    execute $q$update public.payments set "cashDocId" = 'KO1-sinov-1' where id = 'man_t9'$q$;
    execute $q$update public.fin_org set "lockedThrough" = '2026-06-30' where id = 'main'$q$;
  end if;
end $dev$;

-- ===== 1-chaqiruv =====
insert into zz.tok values ('fix1', (select app.payer_codes_fix()::text));
select zz.chk('X1 natija: 18 kod almashtirildi, 22 to''lov va 1 qaytarish yozuvi yashirildi, ochilgan kod bilan 3 faol bog''lanish (1 tasi ota-ona emas), 1 qisqa yaroqsiz eski kod o''chirildi',
  (select concat_ws('/', j ->> 'rotated', j ->> 'payments', j ->> 'refunds', j ->> 'claims', j ->> 'claims_staff', j ->> 'short') from (select v::jsonb j from zz.tok where k = 'fix1') x),
  '^18/22/1/3/1/1$');
select zz.chk('R1 ochilgan JORIY kodlar almashtirildi (yangi kod 12 ta 0-9/A-F, harfli, eskisiga teng emas)',
  (select string_agg(id || '=' || (code ~ '^[0-9A-F]{12}$' and code ~ '[A-F]' and code not in ('A1B2C3D4E5F6','B2C3D4E5F6A1','D4E5F6A1B2C3','E5F6A1B2C3D4','F6A1B2C3D4E5',
            '123456789012','2B3C4D5E6F1A','4D5E6F1A2B3C','5E6F1A2B3C4D','6F1A2B3C4D5E','A2B3C4D5E6F1','B3C4D5E6F1A0','C4D5E6F1A2B3','D5E6F1A2B3C4','E6F1A2B3C4D5'))::text, ',' order by id)
     from public.student_codes where id in ('docA1','IQ-0702','IQ-0704','IQ-0705','IQ-0706','IQ-0707','IQ-0790','IQ-0709','IQ-0710','IQ-0715','IQ-0716','IQ-0717',
                                            'IQ-0718','IQ-0719','IQ-0720')),
  '^IQ-0702=true,IQ-0704=true,IQ-0705=true,IQ-0706=true,IQ-0707=true,IQ-0709=true,IQ-0710=true,IQ-0715=true,IQ-0716=true,IQ-0717=true,IQ-0718=true,IQ-0719=true,IQ-0720=true,IQ-0790=true,docA1=true$');
select zz.chk('R2 eski kodlar student_code_prev da (egasi bilan); qisqa yaroqsiz yozuv yo''q',
  (select string_agg(code || ':' || "studentDocId", ',' order by code) from public.student_code_prev),
  '^0F1E2D3C4B5A:IQ-0703,123456789012:IQ-0707,2B3C4D5E6F1A:IQ-0790,4D5E6F1A2B3C:IQ-0709,5E6F1A2B3C4D:IQ-0710,6F1A2B3C4D5E:IQ-0715,A1B2C3D4E5F6:docA1,A2B3C4D5E6F1:IQ-0716,A7B8C9D0E1F2:IQ-0725,B2C3D4E5F6A1:IQ-0702,B3C4D5E6F1A0:IQ-0717,B8C9D0E1F2A3:IQ-0726,C4D5E6F1A2B3:IQ-0718,C9D0E1F2A3B4:IQ-0727,D4E5F6A1B2C3:IQ-0704,D5E6F1A2B3C4:IQ-0719,E5F6A1B2C3D4:IQ-0705,E6F1A2B3C4D5:IQ-0720,F6A1B2C3D4E5:IQ-0706$');
select zz.chk('R3 ochilmagan joriy kodlar o''zgarmadi (IQ-0703 — faqat eski kodi to''lovda; docK1, IQ-0708)',
  (select string_agg(id || '=' || code, ',' order by id) from public.student_codes where id in ('IQ-0703','docK1','IQ-0708')), '^IQ-0703=C3D4E5F6A1B2,IQ-0708=3C4D5E6F1A2B,docK1=1A2B3C4D5E6F$');
select zz.chk('M1 Click: merchant_trans_id / payerName yashirildi, sinf va telefon o''zgarmadi',
  (select concat_ws('|', merchant_trans_id, "payerName", "payerClass", "payerPhone") from public.payments where id = 'click_t1'), '^IQ-0701 \[kod\]\|IQ-0701 \[kod\]\|7A\|998000000001$');
select zz.chk('M2 payerClass (kichik harfli kod; yondosh «7a» — hex bo''lak, u ham)', (select "payerClass" from public.payments where id = 'click_t2'), '^\[kod\]$');
select zz.chk('M3 ESKI kod ham yashirildi', (select "payerName" from public.payments where id = 'click_t3'), '^IQ-0703 \[kod\]$');
select zz.chk('M4 Uzum raw: params.account yashirildi, boshqa maydonlar (son ham) o''zgarmadi',
  (select concat_ws('|', raw #>> '{params,account}', raw ->> 'appliedTo', jsonb_typeof(raw -> 'amount'), raw ->> 'amount', raw ->> 'transId') from public.payments where id = 'uzum_t4'),
  '^IQ-0704 \[kod\]\|invoice\|number\|5000000\|t4$');
select zz.chk('M5 refunds."studentName" (biriktirilmagan to''lov qaytarilganda payerName nusxasi) yashirildi',
  (select "studentName" from public.refunds where id = 'rf_t5'), '^Sinov Ota \[kod\]$');
select zz.chk('M6 kiril harfli kod va bo''sh joysiz «IDKOD»',
  (select string_agg("payerName", '|' order by id) from public.payments where id in ('click_t6','click_t6b')), '^Kod: \[kod\]\|IQ0706\[kod\]$');
select zz.chk('M7 raw''dagi SON ko''rinishidagi (raqamli) kod -> «[kod]» satri, summa soni o''zgarmadi',
  (select (raw -> 'params' -> 'account')::text || '|' || (raw -> 'amount')::text from public.payments where id = 'uzum_t7'), '^"\[kod\]"\|1000000$');
select zz.chk('M8 naqd to''lov payerName (kassa hujjatiga bog''langan — --dev) yashirildi, raw o''zgarmadi',
  (select "payerName" || '|' || (raw ->> 'date') from public.payments where id = 'man_t9'), '^Sinov Aziz \[kod\]\|2026-11-02$');
select zz.chk('M8b yopilgan davrdagi (--dev) eski to''lov ham yashirildi, createdAt saqlandi',
  (select "payerName" || '|' || to_char("createdAt" at time zone 'Asia/Tashkent', 'YYYY-MM-DD') from public.payments where id = 'click_t10'), '^IQ-0701 \[kod\]\|2026-01-15$');
select zz.chk('M9 pul / holat / o''quvchi / sana ustunlari o''zgarmadi; kodsiz qator (click_t5) tegilmadi',
  ((zz.money_md5() = (select v from zz.tok where k = 'money0'))::text || '|'
   || ((select to_jsonb(p)::text from public.payments p where id = 'click_t5') = (select v from zz.tok where k = 't5row'))::text), '^true\|true$');
select zz.chk('M10 mustaqil tekshiruv: hech bir to''lov / qaytarish matnida joriy yoki eski kod yo''q',
  (select count(*)::text from public.payments where upper(concat_ws(' ', merchant_trans_id, "payerName", "payerClass", "payerPhone", raw::text)) ~ zz.codes_re())
  || '/' || (select count(*)::text from public.refunds where upper(coalesce("studentName", '')) ~ zz.codes_re()), '^0/0$');
-- guruhlab yozilgan kod (2-raund)
select zz.chk('M11 «ID + 4-4-4 guruh» -> «ID [kod]» (merchant_trans_id va payerName)',
  (select merchant_trans_id || '|' || "payerName" from public.payments where id = 'click_t12'), '^IQ-0702 \[kod\]\|IQ-0702 \[kod\]$');
select zz.chk('M12 «-» bilan guruh (kichik harf) -> «[kod]»', (select "payerName" from public.payments where id = 'click_t13'), '^\[kod\]$');
select zz.chk('M13 «ID + 6+6 guruh» -> «ID [kod]»', (select "payerName" from public.payments where id = 'click_t14'), '^IQ-0710 \[kod\]$');
select zz.chk('M14 payerClass «5A + 8+4 guruh» -> «[kod]» (yondosh hex bo''lak «5A» ham); ism va telefon o''zgarmadi',
  (select concat_ws('|', "payerClass", "payerName", "payerPhone") from public.payments where id = 'click_t15'), '^\[kod\]\|Sinov Ota\|998000000015$');
select zz.chk('M15 «.» bilan guruh -> «Sinov Ota [kod]»', (select "payerName" from public.payments where id = 'click_t16'), '^Sinov Ota \[kod\]$');
select zz.chk('M16 kiril harflari va «O» bilan guruh -> «[kod]»', (select "payerName" from public.payments where id = 'click_t17'), '^\[kod\]$');
select zz.chk('M17 mustaqil tekshiruv: harf / raqamdan boshqa HAMMA belgi olib tashlangan va normallangan matnda ham hech bir joriy yoki eski kod yo''q (click_t21 dan tashqari — M24)',
  (select count(*)::text from public.payments
    where id <> 'click_t21' and upper(translate(regexp_replace(concat_ws(' ', merchant_trans_id, "payerName", "payerClass", "payerPhone", raw::text), '[^0-9A-Za-zА-Яа-яЁё]', '', 'g'),
                          'АаБбВвСсДдЕеФфОоOo', 'AABBBBCCDDEEFF0000')) ~ zz.codes_re()), '^0$');
select zz.chk('M18 qisqa yaroqsiz «eski kod»: o''chirildi, uning bo''lagi yashirilmadi (qidiruv uzunligi 12 dan tushmadi)',
  (select "payerName" from public.payments where id = 'click_t11') || '|' || (select count(*)::text from public.student_code_prev where length(code) < 12),
  '^Sinov 23BDBA Ota\|0$');
-- app.payer_mask — mask.test.cjs P1 / P2 dagi AYNAN o'sha satrlar va kutilgan natijalar, o'sha kodlar bilan (JS–SQL tengligi)
create or replace function zz.pm(p text) returns text language sql as $$
  select app.payer_mask(p, array['3FA9C21B7D0E','9C0D1E2F3A4B','5E6F7A8B9C0D','ABCDEF012345','0A1B2C3D4E5F','123456789012','0F0E0D0C0B0A'])
$$;
select zz.chk('M19 app.payer_mask — guruh, kiril / «O», kod bo''lmagan raqamlar; kodga yondosh hex bo''laklar (yaqin nusxa ham) bitta «[kod]», IQ-ID va so''z qoladi (payments/mask.test.cjs P1 bilan bir xil)',
  (select string_agg(case when zz.pm(s) = w then 'ok' else s || ' -> ' || zz.pm(s) end, ' # ' order by n)
     from (values
                  (1, 'IQ-0042 3FA9 C21B 7D0E', 'IQ-0042 [kod]'), (2, '3FA9-C21B-7D0E', '[kod]'), (3, 'IQ-0042 3FA9C2 1B7D0E', 'IQ-0042 [kod]'),
                  (4, '5A 3FA9C21B 7D0E', '[kod]'), (5, 'Sinov  3FA9 C21B 7D0E.', 'Sinov  [kod].'), (6, 'Кod: 3FА9 С21В 7DОЕ', 'Кod: [kod]'),
                  (7, 'AB3FA9 C21B 7D0E12', '[kod]'), (8, '3FA9 C21B 7D0F', '3FA9 C21B 7D0F'),
                  (9, '+998 90 123 45 67, 16.11.2026, 5A, IQ-0042 5A 998901234567', '+998 90 123 45 67, 16.11.2026, 5A, IQ-0042 5A 998901234567'),
                  (10, '3FA9C21B7D0E 3FA9C21B7D0F', '[kod]'), (11, '3FA9C21B7D0F 3FA9C21B7D0E', '[kod]'),
                  (12, 'Sinov Ali 3FA9C21B7D0E', 'Sinov Ali [kod]'), (13, 'Kod 3FA9C21B7D0E-3FA9C21B7D0F', 'Kod [kod]'),
                  (14, '3FA9 C21B 7D0E 3FA9 C21B 7D0', '[kod]'), (15, '3FA9C21B7D0E3FA9C21B7D0F', '[kod]'),
                  (16, 'Kod3FA9C21B7D0E3FA9C21B7D0F', 'Kod[kod]'), (17, '3FA9C21B7D0E va 3FA9C21B7D0F', '[kod] va 3FA9C21B7D0F'),
                  (18, 'IQ-00423FA9C21B7D0E', 'IQ-0042[kod]'), (19, 'IQ00423FA9C21B7D0E', 'IQ0042[kod]'),
                  (20, 'IQ 0042 3FA9C21B7D0E 1234', 'IQ 0042 [kod]'), (21, 'iq_0042_3fa9_c21b_7d0e_7d0f', 'iq_0042_[kod]'),
                  (22, '3FA9C21B7D0E__2026-09', '[kod]'), (23, 'Sinov 0A1B2C3D4E5F 3FA9C21B7D0E Ota', 'Sinov [kod] Ota')) v(n, s, w)),
  '^ok( # ok)*$');
-- 3-raund: ajratgichlar (ikki bo'sh joy, «_», «/», «, », qatorma-qator) — guruhlab yozilgan kod aniqlanadi, almashtiriladi, yashiriladi
select zz.chk('M20 ikki bo''sh joy bilan guruh -> «Sinov Ota  [kod]» (merchant_trans_id va payerName)',
  (select merchant_trans_id || '|' || "payerName" from public.payments where id = 'click_t18'), '^Sinov Ota  \[kod\]\|Sinov Ota  \[kod\]$');
select zz.chk('M21 «_» bilan guruh (ID bilan) -> «IQ-0719 [kod]»; payerClass «5A, » + «/» bilan guruh -> «[kod]» (yondosh «5A» ham)',
  (select concat_ws('|', merchant_trans_id, "payerName", "payerClass") from public.payments where id = 'click_t19'), '^IQ-0719 \[kod\]\|IQ-0719 \[kod\]\|\[kod\]$');
select zz.chk('M22 qatorma-qator yozilgan guruh -> «Ota⏎[kod]»; tab va «, » bilan -> «Kod:⇥[kod]»',
  (select merchant_trans_id || '|' || "payerName" from public.payments where id = 'click_t20'), E'^Ota\n\\[kod\\]\\|Kod:\t\\[kod\\]$');
select zz.chk('M23 app.payer_mask: ajratgich — 1–2 ta [bo''sh joy, tab . , - _ /] yoki 3 tagacha bo''sh joy belgisi (yangi qator ham); 3 ta aralash, «|», «:», «–», 4+ bo''sh joy qatorni uzadi (payments/mask.test.cjs P2 bilan bir xil)',
  (select string_agg(case when zz.pm(s) = w then 'ok' else s || ' -> ' || zz.pm(s) end, ' # ' order by n)
     from (values
                  (1, '3FA9  C21B  7D0E', '[kod]'), (2, '3FA9_C21B_7D0E', '[kod]'), (3, '3FA9/C21B/7D0E', '[kod]'), (4, '3FA9, C21B, 7D0E', '[kod]'),
                  (5, E'3FA9\nC21B\n7D0E', '[kod]'), (6, E'3FA9\tC21B\t7D0E', '[kod]'), (7, E'3FA9\r\nC21B\r\n7D0E', '[kod]'),
                  (8, E'3FA9 \n C21B \n 7D0E', '[kod]'), (9, E'3FA9\u00a0C21B\u00a07D0E', '[kod]'), (10, '3FA9,,C21B._7D0E', '[kod]'),
                  (11, 'IQ-0042, 3FA9/C21B/7D0E', 'IQ-0042, [kod]'), (12, '3FA9 | C21B | 7D0E', '3FA9 | C21B | 7D0E'),
                  (13, '3FA9    C21B    7D0E', '3FA9    C21B    7D0E'), (14, '3FA9 - C21B - 7D0E', '3FA9 - C21B - 7D0E'),
                  (15, '3FA9 / C21B / 7D0E', '3FA9 / C21B / 7D0E'), (16, '3FA9:C21B:7D0E', '3FA9:C21B:7D0E'), (17, '3FA9–C21B—7D0E', '3FA9–C21B—7D0E'),
                  (18, '3FA9...C21B...7D0E', '3FA9...C21B...7D0E'), (19, E'3FA9\n\n\n\nC21B\n7D0E', E'3FA9\n\n\n\nC21B\n7D0E'),
                  (20, 'IQ-0042 _ 3FA9 C21B 7D0E __', 'IQ-0042 _ [kod] __')) v(n, s, w)),
  '^ok( # ok)*$');
select zz.chk('M24 ikki maydonga bo''lingan kod (payerName oxiri + payerClass boshi) — maydon chegarasidan o''tmaydi: aniqlanmadi, matn o''zgarmadi (JS ham har maydonni alohida tekshiradi)',
  (select concat_ws('|', "payerName", "payerClass") from public.payments where id = 'click_t21'), '^Sinov Ota 3C4D5E\|6F1A2B 7A$');
select zz.chk('M25 kod FAQAT yangi qator / CR LF / bo''linmas bo''sh joy bilan ajratilgan (payerName neytral) — aniqlandi: kod almashtirildi (eskisi student_code_prev da), matn yashirildi',
  (select string_agg(sc.id || '=' || (sc.code <> v.c and sc.code ~ '^[0-9A-F]{12}$')::text || '/'
            || (select count(*) from public.student_code_prev pc where pc.code = v.c and pc."studentDocId" = sc.id)::text, ',' order by sc.id)
     from public.student_codes sc join (values ('IQ-0725','A7B8C9D0E1F2'), ('IQ-0726','B8C9D0E1F2A3'), ('IQ-0727','C9D0E1F2A3B4')) v(id, c) on v.id = sc.id)
  || '|' || (select string_agg(merchant_trans_id || '#' || "payerName", '|' order by id) from public.payments where id in ('click_t22','click_t23','click_t24')),
  E'^IQ-0725=true/1,IQ-0726=true/1,IQ-0727=true/1\\|Kod\n\\[kod\\]#Sinov Ota\\|\\[kod\\]#Sinov Ota\\|Kod:\u00a0\\[kod\\]#Sinov Ota$');
-- 5-raund: IQ-ID raqami (to'lov serveridagi SID_IQ taniydigan yozilish: «IQ+0043», «ИҚ-0043», «IQ = 0043», kodga yopishgani ham) «[kod]» ga
--   qo'shilmaydi (app.payer_idnum); harfga yopishgan «…iq», harfdan keyingi «IQ», son belgisi, 3 tadan ortiq belgi — ID emas
select zz.chk('M26 app.payer_mask: IQ belgisidan keyingi ID raqami qoladi, ID bo''lmagan raqam kod bilan yashiriladi (payments/mask.test.cjs P3 bilan bir xil)',
  (select string_agg(case when zz.pm(s) = w then 'ok' else s || ' -> ' || zz.pm(s) end, ' # ' order by n)
     from (values
                  (1, 'IQ+0043 3FA9 C21B 7D0E', 'IQ+0043 [kod]'), (2, 'ИҚ-0043 3FA9C21B7D0E', 'ИҚ-0043 [kod]'), (3, 'IQ#0043 3FA9 C21B 7D0E', 'IQ#0043 [kod]'),
                  (4, 'IQ''0043 3FA9 C21B 7D0E', 'IQ''0043 [kod]'), (5, 'ІQ-0043 3FA9 C21B 7D0E', 'ІQ-0043 [kod]'), (6, 'IQ = 0043 3FA9 C21B 7D0E', 'IQ = 0043 [kod]'),
                  (7, 'ик 0043 3FA9 C21B 7D0E', 'ик 0043 [kod]'), (8, 'IҚ_0043 3FA9 C21B 7D0E', 'IҚ_0043 [kod]'), (9, '5AIQ-0043 3FA9 C21B 7D0E', '5AIQ-0043 [kod]'),
                  (10, 'IQ+00433FA9C21B7D0E', 'IQ+0043[kod]'), (11, 'ИК 00433FA9C21B7D0E', 'ИК 0043[kod]'), (12, 'IQ+0042 3FA9C21B7D0E', 'IQ+0042 [kod]'),
                  (13, 'IQ–0043 3FA9C21B7D0E', 'IQ–0043 [kod]'), (14, '9IQ 0043 3FA9C21B7D0E', '9IQ 0043 [kod]'), (15, 'IQ_ 0043 3FA9C21B7D0E', 'IQ_ 0043 [kod]'),
                  (16, 'IQ' || chr(160) || chr(160) || chr(160) || '#' || chr(160) || '0043 3FA9C21B7D0E', 'IQ' || chr(160) || chr(160) || chr(160) || '#' || chr(160) || '0043 [kod]'),
                  (17, 'IQ' || chr(12288) || ':' || chr(12288) || '0043 3FA9C21B7D0E', 'IQ' || chr(12288) || ':' || chr(12288) || '0043 [kod]'),
                  (18, 'IQ ' || chr(128512) || ' 0043 3FA9C21B7D0E', 'IQ ' || chr(128512) || ' 0043 [kod]'),
                  (19, 'IQ   #   #   #   0043 3FA9C21B7D0E', 'IQ   #   #   #   0043 [kod]'),
                  (20, 'Sinov Ota Sinov Ota Sinov Ota Sinov Ota Sinov Ota IQ+0043 3FA9C21B7D0E', 'Sinov Ota Sinov Ota Sinov Ota Sinov Ota Sinov Ota IQ+0043 [kod]'),
                  (21, 'Sodiq 0043 3FA9 C21B 7D0E', 'Sodiq [kod]'), (22, 'Rafiq+0043 3FA9 C21B 7D0E', 'Rafiq+[kod]'), (23, 'ўIQ+0043 3FA9 C21B 7D0E', 'ўIQ+[kod]'),
                  (24, 'αIQ+0043 3FA9 C21B 7D0E', 'αIQ+[kod]'), (25, 'xIQ   #   #   #   0043 3FA9C21B7D0E', 'xIQ   #   #   #   [kod]'),
                  (26, 'IQ ½ 0043 3FA9 C21B 7D0E', 'IQ ½ [kod]'), (27, 'IQ - - - - 0043 3FA9 C21B 7D0E', 'IQ - - - - [kod]'), (28, 'IQ+123456789012', 'IQ+[kod]'),
                  (29, 'IQ+3FA9C21B7D0F 3FA9C21B7D0E', 'IQ+[kod]'), (30, '3FA9C21B7D0E IQ+0043', '[kod] IQ+0043')) v(n, s, w)),
  '^ok( # ok)*$');
select zz.chk('K1 ochilgan kod bilan ulangan bog''lanishlar faqat sanaldi: hammasi o''z holatida (4 faol, 1 bekor qilingan)',
  (select string_agg(id || '=' || status, ',' order by id) from public.child_claims where id in ('cc_pk','cc_pc1','cc_tch','cc_pc2','cc_pc3')),
  '^cc_pc1=active,cc_pc2=active,cc_pc3=revoked,cc_pk=active,cc_tch=active$');

-- ===== 2-chaqiruv (idempotent) =====
insert into zz.tok values ('st1', zz.state_md5());
insert into zz.tok values ('fix2', (select app.payer_codes_fix()::text));
select zz.chk('I1 qayta chaqiruv: hamma son 0 va hech bir qator o''zgarmadi',
  (select concat_ws('/', j ->> 'rotated', j ->> 'payments', j ->> 'refunds', j ->> 'claims', j ->> 'claims_staff', j ->> 'short') from (select v::jsonb j from zz.tok where k = 'fix2') x)
  || '|' || (zz.state_md5() = (select v from zz.tok where k = 'st1'))::text, '^0/0/0/0/0/0\|true$');

-- ===== claim_child =====
insert into zz.tok values ('newA1', (select code from public.student_codes where id = 'docA1'));
select zz.chk('C1 eski kod (studentId bilan) -> code_changed, aniq xabar',
  zz.as('U_PA', $q$select (r ->> 'ok') || '|' || (r ->> 'reason') || '|' || (r ->> 'error') from (select public.claim_child('IQ-0701', 'a1b2c3d4e5f6') r) x$q$),
  '^false\|code_changed\|Bu kod almashtirilgan — yangi kodni maktabdan oling\.$');
-- (RPC natijasi avval zz.tok ga: bir so'rov ichidagi pastki so'rov funksiya yozgan qatorni ko'rmaydi)
insert into zz.tok values ('c2', zz.as('U_PA', $q$select public.claim_child('docA1', 'A1B2C3D4E5F6') ->> 'reason'$q$));
select zz.chk('C2 eski kod (doc id bilan) -> code_changed; ikkala urinishda bog''lanish YO''Q, ikkalasi ham xato urinish',
  (select v from zz.tok where k = 'c2') || '|' || (select count(*)::text from public.child_claims where uid = 'U_PA')
  || '|' || (select count(*) filter (where not ok)::text || '/' || count(*)::text from public.child_claim_attempts where uid = 'U_PA'), '^code_changed\|0\|2/2$');
select zz.chk('C3 BOSHQA o''quvchining eski kodi -> oddiy xato (code_changed emas)',
  zz.as('U_PB', $q$select coalesce(r ->> 'reason', '-') || '|' || (r ->> 'error') from (select public.claim_child('IQ-0701', 'B2C3D4E5F6A1') r) x$q$),
  '^-\|O''quvchi ID yoki kod noto''g''ri\.$');
insert into zz.tok values ('c4', zz.as('U_PA', format($q$select (public.claim_child('IQ-0701', %L) ->> 'studentId')$q$, (select lower(v) from zz.tok where k = 'newA1'))));
select zz.chk('C4 yangi (joriy) kod -> ulanadi (kanonik studentId)',
  (select v from zz.tok where k = 'c4') || '|' || (select count(*)::text from public.child_claims where uid = 'U_PA' and "studentId" = 'IQ-0701'), '^IQ-0701\|1$');
insert into zz.tok values ('c5a', zz.as('U_PB', $q$select string_agg(coalesce(public.claim_child('IQ-0701', 'A1B2C3D4E5F6') ->> 'reason', 'x'), ',') from generate_series(1, 4)$q$));
insert into zz.tok values ('c5b', zz.as('U_PB', format($q$select (public.claim_child('IQ-0701', %L) ->> 'locked')$q$, (select v from zz.tok where k = 'newA1'))));
select zz.chk('C5 eski kod urinishlari lockout''ga sanaladi: 5 xatodan keyin to''g''ri kod ham — bloklangan',
  (select v from zz.tok where k = 'c5a') || '|' || (select v from zz.tok where k = 'c5b')
  || '|' || (select count(*) filter (where not ok)::text || '/' || count(*)::text from public.child_claim_attempts where uid = 'U_PB')
  || '|' || (select count(*)::text from public.child_claims where uid = 'U_PB'),
  '^code_changed,code_changed,code_changed,code_changed\|true\|6/6\|0$');
select zz.chk('C6 to''qnash kalit: eski kod bilan yozilgan bog''lanish o''z qatoriga tegishli bo''lib qoldi (claim_row / owns_student_doc)',
  coalesce(app.claim_row('IQ-0790', '2B3C4D5E6F1A'), '<null>')
  || '|' || zz.as('U_PK', $q$select app.owns_student_doc('IQ-0790')::text || ',' || app.owns_student_doc('docK1')::text$q$), '^IQ-0790\|true,false$');

-- ===== Eski kodlar jadvali — faqat server =====
select zz.chk('P1 Direktor, moliya, kassir, qabulxona, O''IBDO'', ota-ona, anon — student_code_prev ni o''qiy olmaydi',
  zz.as('U_DIR', 'select count(*)::text from public.student_code_prev') || '|' || zz.as('U_FIN', 'select count(*)::text from public.student_code_prev')
  || '|' || zz.as('U_TRE', 'select count(*)::text from public.student_code_prev') || '|' || zz.as('U_KAS', 'select count(*)::text from public.student_code_prev')
  || '|' || zz.as('U_REC', 'select count(*)::text from public.student_code_prev') || '|' || zz.as('U_ZAV', 'select count(*)::text from public.student_code_prev')
  || '|' || zz.as('U_PA', 'select count(*)::text from public.student_code_prev') || '|' || zz.as(null, 'select count(*)::text from public.student_code_prev'),
  '^ERR 42501[^|]*\|ERR 42501[^|]*\|ERR 42501[^|]*\|ERR 42501[^|]*\|ERR 42501[^|]*\|ERR 42501[^|]*\|ERR 42501[^|]*\|ERR 42501[^|]*$');
select zz.chk('P2 mijoz yoza olmaydi (Direktor ham)',
  zz.as('U_DIR', $q$insert into public.student_code_prev (code, "studentDocId") values ('FFFF00001111', 'IQ-0703') returning code$q$), '^ERR 42501');
select zz.chk('P3 tuzatish / yashirish funksiyalari mijozga yopiq',
  zz.as('U_DIR', 'select app.payer_codes_fix()::text') || '|' || zz.as('U_DIR', $q$select app.payer_mask('x', array['X'])$q$)
  || '|' || zz.as('U_DIR', 'select app.new_student_code()') || '|' || zz.as('U_DIR', 'select app.payer_codes_fix_notice()::text')
  || '|' || zz.as('U_DIR', $q$select app.code_fresh_add('X')::text$q$),
  '^ERR 42501[^|]*\|ERR 42501[^|]*\|ERR 42501[^|]*\|ERR 42501[^|]*\|ERR 42501');
select zz.chk('P4 service_role (to''lov serveri) o''qiy oladi', (select has_table_privilege('service_role', 'public.student_code_prev', 'SELECT')::text), '^true$');

-- ===== Moliya rollari o'qiydigan qatorlar =====
select zz.chk('F1 moliya menejeri / g''aznachi / kassir: to''lovlarni ko''radi (25 qator), hech birida kod yo''q',
  zz.as('U_FIN', format($q$select count(*) filter (where upper(concat_ws(' ', merchant_trans_id, "payerName", "payerClass", "payerPhone", raw::text)) ~ %L) || '/' || count(*) from public.payments$q$, zz.codes_re()))
  || '|' || zz.as('U_TRE', format($q$select count(*) filter (where upper(concat_ws(' ', merchant_trans_id, "payerName", "payerClass", "payerPhone", raw::text)) ~ %L) || '/' || count(*) from public.payments$q$, zz.codes_re()))
  || '|' || zz.as('U_KAS', format($q$select count(*) filter (where upper(concat_ws(' ', merchant_trans_id, "payerName", "payerClass", "payerPhone", raw::text)) ~ %L) || '/' || count(*) from public.payments$q$, zz.codes_re())),
  '^0/25\|0/25\|0/25$');
select zz.chk('F2 qaytarishlar (moliya menejeri, kassir): ko''radi, kod yo''q',
  zz.as('U_FIN', format($q$select count(*) filter (where upper(coalesce("studentName", '')) ~ %L) || '/' || count(*) from public.refunds$q$, zz.codes_re()))
  || '|' || zz.as('U_KAS', format($q$select count(*) filter (where upper(coalesce("studentName", '')) ~ %L) || '/' || count(*) from public.refunds$q$, zz.codes_re())),
  '^0/1\|0/1$');

-- ===== Kod yaratish va almashtirish triggeri =====
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-0711','IQ-0711','Sinov Yangi',5,'A','uz');
select zz.chk('G1 yangi o''quvchi: 12 belgili kod, boshqa joriy / eski kodlarga teng emas, eski ro''yxatda yo''q',
  (select (c.code ~ '^[0-9A-F]{12}$')::text || '|' || (select count(*) from public.student_codes x where upper(x.code) = c.code)::text
          || '|' || (select count(*) from public.student_code_prev v where v.code = c.code or v."studentDocId" = 'IQ-0711')::text
     from public.student_codes c where c.id = 'IQ-0711'), '^true\|1\|0$');
-- arvoh: o'chirilgan o'quvchidan qolgan kod qatori (va uning eski kodi) — shu id bilan yangi o'quvchiga o'tmasligi kerak
insert into public.student_codes (id, code) values ('IQ-0712', 'ABABABABABAB');
insert into public.student_code_prev (code, "studentDocId") values ('CDCDCDCDCDCD', 'IQ-0712');
select set_config('iqror.code_fresh', '', true);   -- arvoh qator OLDINGI tranzaksiyada yozilgan (gen_student_code uni o'zi belgilashi kerak)
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-0712','IQ-0712','Sinov Arvoh',5,'B','uz');
select zz.chk('G2 arvoh kod yangi o''quvchiga o''tmadi: yangi kod, arvoh kodi va uning eski kodi eski ro''yxatda YO''Q',
  (select (code <> 'ABABABABABAB' and code ~ '^[0-9A-F]{12}$')::text from public.student_codes where id = 'IQ-0712')
  || '|' || (select count(*)::text from public.student_code_prev where code in ('ABABABABABAB','CDCDCDCDCDCD') or "studentDocId" = 'IQ-0712'), '^true\|0$');
update public.student_codes set code = 'EEEEEEEEEEE1' where id = 'IQ-0703';
select zz.chk('G3 qo''lda (SQL) o''zgartirilgan kod — eskisi student_code_prev ga',
  (select string_agg(code, ',' order by code) from public.student_code_prev where "studentDocId" = 'IQ-0703'), '^0F1E2D3C4B5A,C3D4E5F6A1B2$');
select set_config('iqror.code_fresh', '', true);   -- keyingi tranzaksiya (EEEEEEEEEEE1 ota-onaga berilgan)
update public.student_codes set code = 'C3D4E5F6A1B2' where id = 'IQ-0703';
select zz.chk('G4 eski kod qayta joriy qilinsa — ro''yxatdan chiqadi (o''rniga oldingi joriy kod)',
  (select string_agg(code, ',' order by code) from public.student_code_prev where "studentDocId" = 'IQ-0703'), '^0F1E2D3C4B5A,EEEEEEEEEEE1$');
update public.student_codes set code = 'EEEEEEEEEEE2' where id = 'IQ-0703';   -- o'sha tranzaksiyada yana almashtirildi
select zz.chk('G4b qayta joriy bo''lgan ESKI kod shu tranzaksiyada yana almashtirilsa — u haqiqiy (oldin berilgan) kod: yana yoziladi',
  (select string_agg(code, ',' order by code) from public.student_code_prev where "studentDocId" = 'IQ-0703'), '^0F1E2D3C4B5A,C3D4E5F6A1B2,EEEEEEEEEEE1$');
delete from public.student_codes where id = 'IQ-0702';
select zz.chk('G5 o''quvchi kodi qatori o''chirilsa — eski kodlari ham o''chadi',
  (select count(*)::text from public.student_code_prev where "studentDocId" = 'IQ-0702' or code = 'B2C3D4E5F6A1'), '^0$');
insert into zz.tok values ('g0', zz.as('U_DIR', $q$insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-0713','IQ-0713','Sinov Direktor',5,'A','uz') returning id$q$));
select zz.chk('G6 Direktor (mijoz) qo''shgan o''quvchiga ham kod beriladi (trigger funksiyasi mijozga yopiq bo''lsa ham)',
  (select v from zz.tok where k = 'g0') || '|' || (select (code ~ '^[0-9A-F]{12}$')::text from public.student_codes where id = 'IQ-0713'), '^IQ-0713\|true$');
-- o'chirish va tiklash (admission-crm.sql: restore_deleted_student) — arxivdagi JORIY kod qaytadi, eski kodlar o'chirilgan qoladi
insert into zz.tok values ('g7code', (select code from public.student_codes where id = 'IQ-0705'));
delete from public.students where id = 'IQ-0705';
delete from public.student_codes where id = 'IQ-0705';
insert into zz.tok values ('g7', zz.as('U_DIR', format($q$select public.restore_deleted_student(%L)::text$q$,
  (select id from public.deleted_records where tbl = 'students' and "rowId" = 'IQ-0705' order by "deletedAt" desc limit 1))));
select zz.chk('G7 o''chirilgan o''quvchini tiklash: ishlaydi, arxivdagi kod qaytadi, eski (ochilgan) kodi qaytmaydi, tiklashdagi oraliq (hech kimga berilmagan) kod ham eski kod bo''lib YOZILMAYDI — 0 ta',
  ((select v from zz.tok where k = 'g7')::jsonb ->> 'ok') || '|' || ((select code from public.student_codes where id = 'IQ-0705') = (select v from zz.tok where k = 'g7code'))::text
  || '|' || (select count(*)::text from public.student_code_prev where code = 'E5F6A1B2C3D4')
  || '|' || (select count(*)::text from public.student_code_prev where "studentDocId" = 'IQ-0705'), '^true\|true\|0\|0$');
select zz.chk('G8 yangi kod har doim kamida bitta harf A–F bilan (3000 ta: faqat raqamli kod chiqmadi)',
  (select (bool_and(c ~ '^[0-9A-F]{12}$' and c ~ '[A-F]'))::text from (select app.new_student_code() c from generate_series(1, 3000)) x), '^true$');

-- ===== Eski kodlar ro'yxatiga faqat tranzaksiyadan OLDIN joriy bo'lgan 12 belgili kod (2-raund) =====
select zz.chk('J0 urug'': o''quvchi qo''shilganda berilgan kodlar shu tranzaksiyada almashtirildi — eski kodlar ro''yxatiga hech biri yozilmadi',
  current_setting('zz.j0', true), '^0$');
-- kodsiz o'quvchi (oldingi tranzaksiyadan) va 6 belgili (12 dan oldingi) kodli o'quvchi
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-0721','IQ-0721','Sinov Kodsiz',6,'A','uz'),
  ('IQ-0722','IQ-0722','Sinov Qisqa',6,'A','uz');
delete from public.student_codes where id = 'IQ-0721';
update public.student_codes set code = 'ABC123' where id = 'IQ-0722';
select set_config('iqror.code_fresh', '', true);   -- keyingi tranzaksiya: deploy zanjiri qayta ishlaydi
-- zanjirdagi AYNAN o'sha buyruqlar: security-2b.sql (kodsiz o'quvchiga 6 belgili kod) va audit-4.sql (12 dan qisqasini uzaytirish)
insert into student_codes(id, code)
  select s.id, upper(substr(md5(random()::text || s.id || clock_timestamp()::text), 1, 6))
  from public.students s
  on conflict (id) do nothing;
update public.student_codes
   set code = upper(substr(md5(random()::text || id || clock_timestamp()::text), 1, 12)),
       "updatedAt" = now()
 where coalesce(length(code),0) < 12;
select zz.chk('J1 zanjir qayta ishlashi: kodsiz o''quvchiga (IQ-0721; G5 dagi IQ-0702 ham) 12 belgili kod, oraliq 6 belgili kod eski kod bo''lib YOZILMADI',
  (select string_agg(id || '=' || (code ~ '^[0-9A-F]{12}$')::text, ',' order by id) from public.student_codes where id in ('IQ-0721','IQ-0702'))
  || '|' || (select count(*)::text from public.student_code_prev where "studentDocId" in ('IQ-0721','IQ-0702')), '^IQ-0702=true,IQ-0721=true\|0$');
select zz.chk('J2 12 belgidan qisqa (oldingi tranzaksiyadan) kod uzaytirilganda ham yozilmadi',
  (select (length(code) = 12)::text from public.student_codes where id = 'IQ-0722')
  || '|' || (select count(*)::text from public.student_code_prev where "studentDocId" = 'IQ-0722'), '^true\|0$');
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-0723','IQ-0723','Sinov Yangi Ikki',6,'B','uz');
update public.student_codes set code = 'ABCDEF000003' where id = 'IQ-0723';
select zz.chk('J3 shu tranzaksiyada berilgan 12 belgili kod darhol almashtirilsa (tiklash / sinov urug''i kabi) — yozilmadi',
  (select count(*)::text from public.student_code_prev where "studentDocId" = 'IQ-0723'), '^0$');
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-0724','IQ-0724','Sinov Yangi Uch',6,'B','uz');
update public.student_codes set code = 'ABCDEF000004' where id = 'IQ-0708';
select zz.chk('J4 bir tranzaksiyada boshqa o''quvchiga yangi kod berilgan bo''lsa ham, haqiqiy almashtirishda (IQ-0708) eski kod yozildi',
  (select coalesce(string_agg(code || ':' || "studentDocId", ',' order by code), '-') from public.student_code_prev where "studentDocId" in ('IQ-0708','IQ-0724')),
  '^3C4D5E6F1A2B:IQ-0708$');

-- ===== Tiklash oralig'i (4-raund): o'quvchi o'chirilgan paytda kelgan to'lovda kod ochiq qolgan — tiklashda kod darhol almashtiriladi =====
insert into public.students (id, "studentId", name, grade, "classLetter", lang) values ('IQ-0951','IQ-0951','Sinov Tiklash',6,'A','uz'),
  ('IQ-0952','IQ-0952','Sinov Qaytish',6,'B','uz');
select set_config('iqror.code_fresh', '', true);   -- kodlar ota-onalarga berilgan (oldingi tranzaksiya)
insert into zz.tok select 'rs_' || id, code from public.student_codes where id in ('IQ-0951','IQ-0952');
delete from public.students where id in ('IQ-0951','IQ-0952');   -- panel o'quvchi bilan birga kod qatorini ham o'chiradi
delete from public.student_codes where id in ('IQ-0951','IQ-0952');
select set_config('iqror.code_fresh', '', true);
-- server shu oraliqda yozgan matn (kod hech bir jadvalda yo'q — taniy olmagan): Click (kichik harf) va qaytarish (guruhlab)
set local iqror.migrating = '1';
insert into public.payments (id, provider, click_trans_id, merchant_trans_id, "payerName", amount, status, matched, "studentId", raw)
  select 'click_rs1', 'click', 'rs1', 'IQ-0951 ' || lower(v), 'IQ-0951 ' || lower(v), 100000, 'unmatched', false, '', '{"mode":"freeform","via":"notfound"}'
    from zz.tok where k = 'rs_IQ-0951';
insert into public.refunds (id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, "createdAt")
  select 'rf_rs2', 'payment', 'click_rs2', '', 'Sinov Ota ' || substr(v, 1, 4) || ' ' || substr(v, 5, 4) || ' ' || substr(v, 9), 50000, 'Sinov qaytarish', '', '', now()
    from zz.tok where k = 'rs_IQ-0952';
set local iqror.migrating = '';
insert into zz.tok values ('t_res1', zz.as('U_DIR', format($q$select public.restore_deleted_student(%L)::text$q$,
  (select id from public.deleted_records where tbl = 'students' and "rowId" = 'IQ-0951' order by "deletedAt" desc limit 1))));
insert into zz.tok values ('t_res2', zz.as('U_DIR', format($q$select public.restore_deleted_student(%L)::text$q$,
  (select id from public.deleted_records where tbl = 'students' and "rowId" = 'IQ-0952' order by "deletedAt" desc limit 1))));
select zz.chk('T1 tiklash: to''lov / qaytarish matnida ochiq qolgan kod darhol almashtirildi (codeChanged), yangi kod harfli, eski kod student_code_prev da (egasi bilan)',
  (select string_agg(case when v like '{%' then (v::jsonb ->> 'ok') || '/' || coalesce(v::jsonb ->> 'codeChanged', '-') else v end, ',' order by k)
     from zz.tok where k in ('t_res1','t_res2'))
  || '|' || (select string_agg(sc.id || '=' || (sc.code <> t.v and sc.code ~ '^[0-9A-F]{12}$' and sc.code ~ '[A-F]')::text || '/'
              || (select count(*) from public.student_code_prev pc where pc.code = upper(t.v) and pc."studentDocId" = sc.id)::text, ',' order by sc.id)
             from public.student_codes sc join zz.tok t on t.k = 'rs_' || sc.id where sc.id in ('IQ-0951','IQ-0952')),
  '^true/true,true/true\|IQ-0951=true/1,IQ-0952=true/1$');
select zz.chk('T2 moliya menejeri: to''lov va qaytarish yozuvlarida tiklangan o''quvchilarning JORIY kodi yo''q; eski kod bilan claim_child -> code_changed (ulanmaydi)',
  zz.as('U_FIN', format($q$select (select count(*) from public.payments where upper(concat_ws(' ', merchant_trans_id, "payerName", raw::text)) ~ %1$L)
                          + (select count(*) from public.refunds where upper(translate(coalesce("studentName", ''), ' ', '')) ~ %1$L) || ''$q$,
                        (select string_agg(code, '|') from public.student_codes where id in ('IQ-0951','IQ-0952'))))
  || '|' || zz.as('U_FIN', format($q$select coalesce(public.claim_child('IQ-0951', %L) ->> 'reason', 'ok')$q$, (select v from zz.tok where k = 'rs_IQ-0951')))
  || '|' || (select count(*)::text from public.child_claims where uid = 'U_FIN'),
  '^0\|code_changed\|0$');
select zz.chk('T3 tiklash to''lov qatorlariga tegmaydi (Direktor sessiyasi): matn keyingi app.payer_codes_fix gacha o''zgarmagan',
  (select (merchant_trans_id = 'IQ-0951 ' || lower((select v from zz.tok where k = 'rs_IQ-0951')))::text from public.payments where id = 'click_rs1'), '^true$');
insert into zz.tok values ('fix3', (select app.payer_codes_fix()::text));
select zz.chk('T4 keyingi app.payer_codes_fix: eski kod yashirildi (1 to''lov, 1 qaytarish), yangi kod almashtirilmadi',
  (select concat_ws('/', j ->> 'rotated', j ->> 'payments', j ->> 'refunds', j ->> 'claims') from (select v::jsonb j from zz.tok where k = 'fix3') x)
  || '|' || (select merchant_trans_id from public.payments where id = 'click_rs1') || '|' || (select "studentName" from public.refunds where id = 'rf_rs2'),
  '^0/1/1/0\|IQ-0951 \[kod\]\|Sinov Ota \[kod\]$');

-- ===== --dev: davr qulfi va kassa qo'riqchisi oddiy foydalanuvchi uchun o'z joyida =====
do $dev$ begin
  if to_regclass('public.cash_docs') is not null then
    perform zz.chk('D1 (--dev) urug'': davr 2026-06-30 gacha yopilgan, naqd qator kassa hujjatiga bog''langan — yashirish baribir o''tdi (M8, M8b)',
      (select "lockedThrough"::text from public.fin_org where id = 'main') || '|' || (select "cashDocId" from public.payments where id = 'man_t9'),
      '^2026-06-30\|KO1-sinov-1$');
    -- audit-10 (A4-01): to'lov qatorini REST orqali faqat Direktor yangilaydi (pay_upd) — moliya menejerida 0 qator; Direktorni ham
    --   davr qulfi va kassa qo'riqchisi to'xtatadi (ular pul qo'riqchisidan OLDIN ishlaydi).
    perform zz.chk('D2 (--dev) moliya menejeri to''lov summasini o''zgartira olmaydi (0 qator); Direktorni yopilgan davr qulfi to''xtatadi',
      zz.as('U_FIN', $q$update public.payments set amount = 1 where id = 'click_t10' returning id$q$) || ' | '
      || zz.as('U_DIR', $q$update public.payments set amount = 1 where id = 'click_t10' returning id$q$), '^<null> \| ERR 42501 .*yopilgan davr');
    perform zz.chk('D3 (--dev) kassa hujjatiga bog''langan qator summasi — moliya menejeri 0 qator; Direktor — kassa qo''riqchisi rad etadi',
      zz.as('U_FIN', $q$update public.payments set amount = 1 where id = 'man_t9' returning id$q$) || ' | '
      || zz.as('U_DIR', $q$update public.payments set amount = 1 where id = 'man_t9' returning id$q$), '^<null> \| ERR 42501 .*kassa hujjatiga bog');
  end if;
end $dev$;

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || coalesce(got, '<null>') || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
