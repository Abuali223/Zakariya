-- =====================================================================
-- test-audit-11-elon.sql — audit-11 (H4b) sinovi: xodim hisobiga farzand bog'lash Direktor tasdig'i bilan (A7-01: claim_child,
--   child_claim_decide, app.child_claims_review), e'lon tahriri Telegram navbatini yangilaydi (A7-02), farzandi bor xodim farzandi sinfi
--   e'lonini ko'radi (A7-03), maktabdan chiqqan bola ota-onasi e'lon olmaydi — kabinet va Telegram bir xil qoida (A7-04, A3-09), ishdan
--   ketgan o'qituvchi teachers_public'da yo'q (A7-05), chiqqan o'quvchi egasi rasmiy hujjat kodini olmaydi (A7-07), kabinetdagi «Uzish»
--   faqat ota-ona bog'lanishlarini uzadi (A7-09).
--   Har chaqiruv haqiqiy rol bilan (anon yoki authenticated + JWT sub) — RLS va GRANT haqiqiy; server RPC'lari (tg_*) — tizim nomidan.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-audit-11-elon.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-11-elon.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
set local iqror.migrating = '1';
insert into public.users (id, email, role, status, phone) values
  ('U_DIR','d@example.org','director','active',null), ('U_ZAV','z@example.org','zavuch','active',null),
  ('U_REC','r@example.org','reception','active','998000001104'), ('U_REC2','r2@example.org','reception','active',null),
  ('U_TEAREC','tr@example.org','teacher','active',null), ('U_TEA','t@example.org','teacher','active',null),
  ('U_TP','tp@example.org','teacher','active',null), ('U_PA','pa@example.org','parent','active',null),
  ('U_P5','p5@example.org','parent','active',null), ('U_PX','px@example.org','parent','active',null),
  ('U_STX','sx@example.org','student','active',null), ('U_PF','pf@example.org','parent','active',null),
  ('U_PM','pm@example.org','parent','active',null), ('U_PN','pn@example.org','parent','active',null),
  ('U_PE','pe@example.org','parent','active',null), ('U_ACC','a@example.org','accountant','active',null)
on conflict (id) do update set role = excluded.role, status = excluded.status, phone = excluded.phone;
update public.users set "extraRoles" = '["reception"]'::jsonb where id = 'U_TEAREC';
update public.users set "assignedClasses" = '["uz-5-B"]'::jsonb, "homeroomClasses" = '["uz-5-B"]'::jsonb where id in ('U_TEA', 'U_TP');
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "stopFrom", "exitAt") values
  ('IQ-1103','IQ-1103','Sinov Uchinchi',3,'A','uz','','',null),
  ('IQ-1104','IQ-1104','Sinov Qabul Bola',4,'A','uz','','',null),
  ('IQ-1105','IQ-1105','Sinov Zavuch Bola',4,'A','uz','','',null),
  ('IQ-1106','IQ-1106','Sinov Ikki Lavozim Bola',4,'A','uz','','',null),
  ('IQ-1151','IQ-1151','Sinov Ketgan',5,'A','uz','chiqdi','2026-09-01','2026-09-01'),
  ('IQ-1152','IQ-1152','Sinov Keyin Ketadi',5,'A','uz','chiqdi','2099-01-01','2099-01-01'),
  ('IQ-1153','IQ-1153','Sinov Eski Ketgan',6,'A','uz','chiqdi','2026-09-01',null),
  ('IQ-1154','IQ-1154','Sinov Yettinchi',7,'A','uz','','',null),
  ('IQ-1155','IQ-1155','Sinov Sanasiz Ketgan',8,'A','uz','chiqdi','',null),
  ('IQ-1156','IQ-1156','Sinov Chiqish Kelajakda',9,'A','uz','chiqdi','2026-09-01','2099-01-01'),
  ('IQ-1157','IQ-1157','Sinov Beshinchi',5,'A','uz','','',null)
on conflict (id) do nothing;
insert into public.student_health (id, "studentId", allergies) values ('IQ-1104','IQ-1104','Sinov allergiya') on conflict (id) do nothing;
insert into public.student_private (id, "fatherName", "parentPhone") values
  ('IQ-1103','Sinov Ota','998000001103'), ('IQ-1104','Sinov Qabul','998000001104'), ('IQ-1151','Sinov Ota','998000001151'),
  ('IQ-1152','Sinov Ota','998000001152'), ('IQ-1157','Sinov Ota','998000001157')
on conflict (id) do nothing;
insert into public.child_claims (id, uid, "studentId", code, status) values
  ('U_P5__IQ-1157','U_P5','IQ-1157','X','active'), ('U_PX__IQ-1151','U_PX','IQ-1151','X','active'),
  ('U_STX__IQ-1151','U_STX','IQ-1151','X','active'), ('U_PF__IQ-1152','U_PF','IQ-1152','X','active'),
  ('U_PM__IQ-1153','U_PM','IQ-1153','X','active'), ('U_PM__IQ-1154','U_PM','IQ-1154','X','active'),
  ('U_PN__IQ-1155','U_PN','IQ-1155','X','active'), ('U_PE__IQ-1156','U_PE','IQ-1156','X','active')
on conflict (id) do nothing;
insert into public.class_announcements (id, "classKeys", title, "createdBy", "expiresAt") values
  ('A_ALL','["all"]','Hammaga','U_DIR',null), ('A_3A','["uz-3-A"]','3-A ga','U_DIR',null),
  ('A_3A_OLD','["uz-3-A"]','3-A eskirgan','U_DIR',now() - interval '1 day'), ('A_4A','["uz-4-A"]','4-A ga','U_DIR',null),
  ('A_5A','["uz-5-A"]','5-A ga','U_DIR',null), ('A_5B','["uz-5-B"]','5-B ga','U_DIR',null),
  ('A_6A','["uz-6-A"]','6-A ga','U_DIR',null), ('A_7A','["uz-7-A"]','7-A ga','U_DIR',null),
  ('A_8A','["uz-8-A"]','8-A ga','U_DIR',null), ('A_9A','["uz-9-A"]','9-A ga','U_DIR',null)
on conflict (id) do nothing;
insert into public.teachers (id, name, "payStatus", "stopFrom") values
  ('T_ACT','Sinov Faol Ustoz','',''), ('T_LEFT','Sinov Ketgan Ustoz','chiqdi','2026-09-01'),
  ('T_NODATE','Sinov Sanasiz Ustoz','chiqdi',''), ('T_TODAY','Sinov Bugun Ketadi','chiqdi',to_char(now() at time zone 'Asia/Tashkent', 'YYYY-MM-DD')),
  ('T_FUT','Sinov Keyin Ketadi','chiqdi','2099-01-01'), ('T_FROZEN','Sinov Muzlatilgan','muzlatilgan','2026-09-01')
on conflict (id) do nothing;
insert into public.telegram_links (id, uid, kind, "tgUserId", "chatId", phone, "studentIds", status, "verifiedAt") values
  ('L_PA','U_PA','parent',1103,1103,'998000001103','["IQ-1103"]','active',now()),
  ('L_P5','U_P5','parent',1157,1157,'998000001157','["IQ-1157"]','active',now()),
  ('L_PX','U_PX','parent',1151,1151,'998000001151','["IQ-1151"]','active',now()),
  ('L_PF','U_PF','parent',1152,1152,'998000001152','["IQ-1152"]','active',now()),
  ('L_DSTAFF','U_DIR','staff',9001,9001,null,'[]','active',now()),
  ('L_DPAR','U_DIR','parent',9001,9001,'998000009001','[]','active',now())
on conflict (id) do nothing;
set local iqror.migrating = '';

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
-- zz.hint: authenticated nomidan; xato bo'lsa 'HINT <hint>' (kabinet xatoni shu bilan taniydi).
create or replace function zz.hint(p_uid text, p_q text) returns text language plpgsql as $$
declare r text; h text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    execute p_q into r; r := 'OK';
  exception when others then get stacked diagnostics h = pg_exception_hint; r := 'HINT ' || coalesce(h, '');
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return r;
end $$;
-- zz.try: so'rovni joriy (postgres — server / tizim) huquqida bajaradi; xato bo'lsa 'ERR <sqlstate>'.
create or replace function zz.try(p_q text) returns text language plpgsql as $$
declare r text;
begin
  begin execute p_q into r; exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
  return coalesce(r, '<null>');
end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, p_got ~ p_pat); end $$;
-- Ko'rinadigan e'lonlar (A_ bilan boshlanganlar) — vergul bilan.
create or replace function zz.ann(p_uid text) returns text language sql as $$
  select zz.as(p_uid, $q$select string_agg(id, ',' order by id) from public.class_announcements where id like 'A\_%'$q$)
$$;
create or replace function zz.code(p_sid text) returns text language sql as $$ select code from public.student_codes where id = p_sid $$;

-- ===== A7-01: kod ko'radigan xodim farzandni o'zi bog'lay olmaydi — Direktor tasdig'i =====
select zz.chk('C01 qabulxona o''quvchi kodini ko''radi (D6 o''zgarmagan — shu sabab bog''lanish tasdiqqa)',
  zz.as('U_REC', $q$select count(*)::text from public.student_codes where id = 'IQ-1104'$q$), '^1$');
select zz.chk('C02 qabulxona to''g''ri kod bilan -> ulanmaydi, Direktor tasdig''ini kutadi (pending)',
  zz.as('U_REC', format($q$select (r->>'ok') || '|' || (r->>'pending') || '|' || (r->>'studentId') from (select public.claim_child('IQ-1104', %L) r) x$q$, zz.code('IQ-1104')))
  || ' ' || zz.try($q$select coalesce((select status from public.child_claims where uid = 'U_REC' and "studentId" = 'IQ-1104'), '-')$q$),
  '^false\|true\|IQ-1104 pending$');
select zz.chk('C03 kutilayotgan bog''lanish ota-ona huquqini bermaydi: sog''liq kartasi 0, owns_child yo''q',
  zz.as('U_REC', $q$select (select count(*) from public.student_health)::text || '/' || app.owns_child('IQ-1104')::text$q$), '^0/false$');
select zz.chk('C04 qayta urinish — yana «kutmoqda», ikkinchi qator yo''q',
  zz.as('U_REC', format($q$select (public.claim_child('IQ-1104', %L)->>'pending')$q$, zz.code('IQ-1104')))
  || ' ' || zz.try($q$select count(*)::text from public.child_claims where uid = 'U_REC'$q$), '^true 1$');
select zz.chk('C05 O''IBDO'' -> pending', zz.as('U_ZAV', format($q$select (public.claim_child('IQ-1105', %L)->>'pending')$q$, zz.code('IQ-1105'))), '^true$');
select zz.chk('C06 o''qituvchi + qo''shimcha qabulxona lavozimi -> pending',
  zz.as('U_TEAREC', format($q$select (public.claim_child('IQ-1106', %L)->>'pending')$q$, zz.code('IQ-1106'))), '^true$');
select zz.chk('C07 oddiy o''qituvchi (kod ko''rmaydi) — darhol faol (xodim-ota-ona yo''li o''zgarmagan)',
  zz.as('U_TP', format($q$select (public.claim_child('IQ-1103', %L)->>'ok')$q$, zz.code('IQ-1103')))
  || ' ' || zz.try($q$select status from public.child_claims where uid = 'U_TP'$q$), '^true active$');
select zz.chk('C08 oddiy ota-ona — darhol faol', zz.as('U_PA', format($q$select (public.claim_child('IQ-1103', %L)->>'ok')$q$, zz.code('IQ-1103')))
  || ' ' || zz.try($q$select status from public.child_claims where uid = 'U_PA'$q$), '^true active$');
select zz.chk('C09 Direktor — darhol faol (u baribir hamma o''quvchini ko''radi)',
  zz.as('U_DIR', format($q$select (public.claim_child('IQ-1104', %L)->>'ok')$q$, zz.code('IQ-1104'))) || ' ' || zz.try($q$select status from public.child_claims where uid = 'U_DIR'$q$), '^true active$');
select zz.chk('C10 buxgalter — avvalgidek rad', zz.as('U_ACC', format($q$select public.claim_child('IQ-1104', %L)->>'error'$q$, zz.code('IQ-1104'))), '^Buxgalter hisobiga');
select zz.chk('C11 child_claim_decide: qabulxona, O''IBDO'', o''qituvchi, ota-ona — 42501; anon — huquq yo''q',
  zz.as('U_REC', $q$select public.child_claim_decide('U_REC__IQ-1104', true)::text$q$) || ' | ' || zz.as('U_ZAV', $q$select public.child_claim_decide('U_REC__IQ-1104', true)::text$q$)
  || ' | ' || zz.as('U_TEA', $q$select public.child_claim_decide('U_REC__IQ-1104', true)::text$q$) || ' | ' || zz.as('U_PA', $q$select public.child_claim_decide('U_REC__IQ-1104', true)::text$q$)
  || ' | ' || zz.as(null, $q$select public.child_claim_decide('U_REC__IQ-1104', true)::text$q$),
  '^ERR 42501 Farzand.* \| ERR 42501 Farzand.* \| ERR 42501 Farzand.* \| ERR 42501 Farzand.* \| ERR 42501 permission denied');
select zz.chk('C12 hali hech kim tasdiqlamadi — holat pending', (select status from public.child_claims where id = 'U_REC__IQ-1104'), '^pending$');
select zz.chk('C13 Direktor tasdiqlaydi -> faol, approvedBy = Direktor',
  zz.as('U_DIR', $q$select public.child_claim_decide('U_REC__IQ-1104', true)->>'status'$q$)
  || ' ' || zz.try($q$select status || '/' || "approvedBy" from public.child_claims where id = 'U_REC__IQ-1104'$q$), '^active active/U_DIR$');
select zz.chk('C14 tasdiqdan keyin xodim-ota-ona farzandi sog''liq kartasini ko''radi; qayta urinish — ok',
  zz.as('U_REC', $q$select (select count(*) from public.student_health)::text$q$)
  || ' ' || zz.as('U_REC', format($q$select (public.claim_child('IQ-1104', %L)->>'ok')$q$, zz.code('IQ-1104'))), '^1 true$');
select zz.chk('C15 Direktor rad etadi -> so''rov o''chadi; xodim keyin yana so''rasa — yana pending',
  zz.as('U_DIR', $q$select public.child_claim_decide('U_ZAV__IQ-1105', false)->>'status'$q$)
  || ' ' || zz.try($q$select count(*)::text from public.child_claims where id = 'U_ZAV__IQ-1105'$q$)
  || ' ' || zz.as('U_ZAV', format($q$select (public.claim_child('IQ-1105', %L)->>'pending')$q$, zz.code('IQ-1105'))), '^rejected 0 true$');
select zz.chk('C16 faol (oddiy ota-ona) bog''lanishi -> not_pending; yo''q id -> not_found; qarorsiz -> bad_request',
  zz.as('U_DIR', $q$select public.child_claim_decide('U_P5__IQ-1157', false)->>'reason'$q$) || ' ' || zz.as('U_DIR', $q$select public.child_claim_decide('yoq', true)->>'reason'$q$)
  || ' ' || zz.as('U_DIR', $q$select public.child_claim_decide('U_ZAV__IQ-1105', null)->>'reason'$q$)
  || ' ' || (select status from public.child_claims where id = 'U_P5__IQ-1157'), '^not_pending not_found bad_request active$');
-- Himoya to'ri (har deployda): oldin claim_child'dan o'tgan (tasdiqsiz) xodim bog'lanishi -> pending; tasdiqlangan, Direktor, o'qituvchi,
--   ota-ona bog'lanishiga tegilmaydi; qayta chaqiruv — hech narsa.
set local iqror.migrating = '1';
insert into public.child_claims (id, uid, "studentId", code, status) values ('U_REC2__IQ-1103','U_REC2','IQ-1103','X','active') on conflict (id) do nothing;
set local iqror.migrating = '';
select zz.chk('C17 himoya to''ri: faqat tasdiqsiz xodim bog''lanishi o''tkaziladi', zz.try($q$select app.child_claims_review()::text$q$), '^\{U_REC2__IQ-1103\}$');
select zz.chk('C18 o''tkazilgani pending; tasdiqlangan (U_REC), Direktor, o''qituvchi, ota-ona — faol',
  (select string_agg(id || ':' || status, ',' order by id) from public.child_claims where id in ('U_REC2__IQ-1103', 'U_REC__IQ-1104', 'U_DIR__IQ-1104', 'U_TP__IQ-1103', 'U_PA__IQ-1103')),
  '^U_DIR__IQ-1104:active,U_PA__IQ-1103:active,U_REC2__IQ-1103:pending,U_REC__IQ-1104:active,U_TP__IQ-1103:active$');
select zz.chk('C19 himoya to''ri qayta — hech narsa (idempotent)', zz.try($q$select app.child_claims_review()::text$q$), '^\{\}$');
select zz.chk('C20 himoya to''rini mijoz chaqira olmaydi', zz.as('U_DIR', $q$select app.child_claims_review()::text$q$), '^ERR 42501');

-- ===== A7-03: farzandi bor xodim farzandi sinfi e'lonini ko'radi =====
select zz.chk('T01 o''qituvchi-ota-ona: o''z sinfi (5-B, xodim qoidasi) + farzandi sinfi (3-A) + butun maktab; muddati o''tgan 3-A — yo''q',
  zz.ann('U_TP'), '^A_3A,A_5B,A_ALL$');
select zz.chk('T02 farzandsiz o''qituvchi — o''zgarmagan (5-B + butun maktab, muddati o''tgani ham xodim qoidasida)', zz.ann('U_TEA'), '^A_5B,A_ALL$');
select zz.chk('T03 oddiy ota-ona — o''zgarmagan', zz.ann('U_PA'), '^A_3A,A_ALL$');
select zz.chk('T04 qabulxona-ota-ona (Direktor tasdiqlagan) — farzandi sinfi (4-A) ham', zz.ann('U_REC'), '^A_4A,A_ALL$');
select zz.chk('T05 kutilayotgan (tasdiqlanmagan) bog''lanish e''lon ochmaydi: qo''shimcha qabulxonali o''qituvchi — farzandi sinfi (4-A) yo''q',
  zz.ann('U_TEAREC'), '^A_ALL$');

-- ===== A7-04 / A3-09: maktabdan chiqqan bola ota-onasi e'lon olmaydi (arxiv qoidasi) =====
select zz.chk('R01 farzandi chiqqan (exitAt o''tgan) — hech narsa (eski sinf ham, butun maktab ham)', zz.ann('U_PX'), '^<null>$');
select zz.chk('R02 kelajakda chiqadi — shu kungacha sinfda', zz.ann('U_PF'), '^A_5A,A_ALL$');
select zz.chk('R03 bir bola chiqqan (faqat stopFrom), ikkinchisi faol — faqat faolining sinfi + butun maktab', zz.ann('U_PM'), '^A_7A,A_ALL$');
select zz.chk('R04 «chiqdi», sana yo''q — arxivda', zz.ann('U_PN'), '^<null>$');
select zz.chk('R05 exitAt (kelajak) ustun — stopFrom o''tgan bo''lsa ham hali sinfda', zz.ann('U_PE'), '^A_9A,A_ALL$');
select zz.chk('R06 o''quvchi o''zi (chiqqan) — hech narsa', zz.ann('U_STX'), '^<null>$');
select zz.chk('R07 Telegram 5-A: chiqqan bola ota-onasiga yo''q, kelajakda chiqadiganga va faolga — bor (kabinet bilan bir xil)',
  zz.try($q$select string_agg(chat_id::text, ',' order by chat_id) from public.tg_announce_recipients('["uz-5-A"]'::jsonb)$q$), '^1152,1157$');
select zz.chk('R08 Telegram butun maktab: chiqqan bola ota-onasiga yo''q', zz.try($q$select string_agg(chat_id::text, ',' order by chat_id) from public.tg_announce_recipients('["all"]'::jsonb)$q$),
  '^1103,1152,1157$');

-- ===== A7-02: e'lon tahrirlansa Telegram navbati ham =====
select zz.chk('Q01 Direktor butun maktabga e''lon yozadi -> navbatda (pending)',
  zz.as('U_DIR', $q$insert into public.class_announcements (id, "classKeys", title, body, "createdBy") values ('Q_1', '["all"]', 'Majlis 15-noyabr', 'Hamma kelsin', 'U_DIR') returning id$q$)
  || ' ' || zz.try($q$select status || ' ' || (payload->>'title') from public.notify_queue where id = 'ann__Q_1'$q$), '^Q_1 pending Majlis 15-noyabr$');
select zz.chk('Q02 tahrir (5-A ga, sana va matn) -> navbat nusxasi ham yangi', zz.as('U_DIR', $q$update public.class_announcements set "classKeys" = '["uz-5-A"]', title = 'Majlis 16-noyabr', body = '5-A ota-onalari' where id = 'Q_1' returning id$q$)
  || ' ' || zz.try($q$select status || ' ' || (payload->'classKeys')::text || ' ' || (payload->>'title') || ' ' || (payload->>'body') from public.notify_queue where id = 'ann__Q_1'$q$),
  '^Q_1 pending \["uz-5-A"\] Majlis 16-noyabr 5-A ota-onalari$');
select zz.chk('Q03 navbatdagi auditoriya — faqat 5-A (3-A ota-onasi chiqarildi), chiqqan bola ota-onasi yo''q',
  zz.try($q$select string_agg(r.chat_id::text, ',' order by r.chat_id) from public.notify_queue q, public.tg_announce_recipients(q.payload->'classKeys') r where q.id = 'ann__Q_1'$q$), '^1152,1157$');
select zz.chk('Q04 sinf rahbari o''z e''lonini tahrirlaydi -> navbat yangilanadi',
  zz.as('U_TEA', $q$insert into public.class_announcements (id, "classKeys", title, body, "createdBy") values ('Q_2', '["uz-5-B"]', 'Ekskursiya', '50 000', 'U_TEA') returning id$q$)
  || ' ' || zz.as('U_TEA', $q$update public.class_announcements set body = '60 000' where id = 'Q_2' returning id$q$)
  || ' ' || zz.try($q$select payload->>'body' from public.notify_queue where id = 'ann__Q_2'$q$), '^Q_2 Q_2 60 000$');
select zz.chk('Q05 faqat 📌 qadash — navbat o''zgarmaydi', zz.as('U_DIR', $q$update public.class_announcements set pinned = true where id = 'Q_2' returning id$q$)
  || ' ' || zz.try($q$select (payload->>'body') || '/' || status from public.notify_queue where id = 'ann__Q_2'$q$), '^Q_2 60 000/pending$');
update public.notify_queue set status = 'done', "processedAt" = now() where id = 'ann__Q_2';
select zz.chk('Q06 yuborilgan xabar — tahrirdan keyin qayta yuborilmaydi (nusxa va holat o''zgarmaydi)',
  zz.as('U_TEA', $q$update public.class_announcements set body = '70 000' where id = 'Q_2' returning id$q$)
  || ' ' || zz.try($q$select (payload->>'body') || '/' || status from public.notify_queue where id = 'ann__Q_2'$q$), '^Q_2 60 000/done$');
select zz.chk('Q07 sinf rahbari boshqa sinfga ko''chira olmaydi (RLS) — navbat o''zgarmaydi',
  zz.as('U_TEA', $q$update public.class_announcements set "classKeys" = '["all"]' where id = 'Q_2' returning id$q$)
  || ' ' || zz.try($q$select (payload->'classKeys')::text from public.notify_queue where id = 'ann__Q_2'$q$), '^ERR 42501.* \["uz-5-B"\]$');
select zz.chk('Q08 o''chirish — avvalgidek bekor (skipped)', zz.as('U_DIR', $q$with d as (delete from public.class_announcements where id = 'Q_1' returning 1) select count(*)::text from d$q$)
  || ' ' || zz.try($q$select status from public.notify_queue where id = 'ann__Q_1'$q$), '^1 skipped$');

-- ===== A7-05: ishdan ketgan o'qituvchi ommaviy ro'yxatda yo'q =====
select zz.chk('W01 anon: faol, muzlatilgan, kelajakda ketadigan, bugun ketadigan (oxirgi ish kuni) — bor; ketgan va sanasiz «chiqdi» — yo''q',
  zz.as(null, $q$select string_agg(id, ',' order by id) from public.teachers_public where id like 'T\_%'$q$), '^T_ACT,T_FROZEN,T_FUT,T_TODAY$');
select zz.chk('W02 kabinet (ota-ona) reyting ro''yxati ham shu', zz.as('U_PA', $q$select string_agg(id, ',' order by id) from public.teachers_public where id like 'T\_%'$q$), '^T_ACT,T_FROZEN,T_FUT,T_TODAY$');
select zz.chk('W03 qatorlar o''chirilmagan (maosh tarixi) — Direktor xom jadvalda 6 ta', zz.as('U_DIR', $q$select count(*)::text from public.teachers where id like 'T\_%'$q$), '^6$');
select zz.chk('W04 teachers_public ustunlari o''zgarmagan (maoshsiz)',
  (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'teachers_public'),
  '^id,name,photo,subject_uz,subject_ru,rating,years,certs,avg,votes,order$');

-- ===== A7-07: chiqqan o'quvchi egasi rasmiy hujjat kodini olmaydi =====
select zz.chk('D01 ota-ona (farzandi chiqqan) -> rad, aniq sabab', zz.as('U_PX', $q$select public.issue_doc_token('IQ-1151','profile')$q$), '^ERR 42501 o''quvchi maktabdan chiqqan');
select zz.chk('D02 kabinet xatoni hint bilan taniydi', zz.hint('U_PX', $q$select public.issue_doc_token('IQ-1151','profile')$q$), '^HINT student_left$');
select zz.chk('D03 o''quvchi o''zi (chiqqan) -> rad', zz.as('U_STX', $q$select public.issue_doc_token('IQ-1151','profile')$q$), '^ERR 42501 o''quvchi maktabdan chiqqan');
select zz.chk('D04 «chiqdi», sana yo''q -> rad', zz.as('U_PN', $q$select public.issue_doc_token('IQ-1155','profile')$q$), '^ERR 42501 o''quvchi maktabdan chiqqan');
select zz.chk('D05 kelajakda chiqadi -> kod', zz.as('U_PF', $q$select public.issue_doc_token('IQ-1152','profile')$q$), '^[0-9a-f]{32}$');
select zz.chk('D06 exitAt (kelajak) ustun -> kod', zz.as('U_PE', $q$select public.issue_doc_token('IQ-1156','profile')$q$), '^[0-9a-f]{32}$');
select zz.chk('D07 faol o''quvchi ota-onasi -> kod (o''zgarmagan)', zz.as('U_P5', $q$select public.issue_doc_token('IQ-1157','profile')$q$), '^[0-9a-f]{32}$');
select zz.chk('D08 begona bola — avvalgidek ruxsat yo''q (mavjudligi bilinmasin)', zz.as('U_PX', $q$select public.issue_doc_token('IQ-1157','profile')$q$), '^ERR 42501 ruxsat yo''q$');
select zz.chk('D09 xodim yo''li o''zgarmagan: Direktor (profil) va qabulxona (ma''lumotnoma) chiqqan o''quvchiga kod beradi',
  zz.as('U_DIR', $q$select public.issue_doc_token('IQ-1151','profile')$q$) || ' ' || zz.as('U_REC', $q$select public.issue_doc_token('IQ-1151','certificate')$q$), '^[0-9a-f]{32} [0-9a-f]{32}$');
select zz.chk('D10 xodim bergan kod QR sahifasida haqiqiy (o''zgarmagan)',
  zz.as(null, format($q$select (public.verify_doc(%L)->>'valid') || '/' || (public.verify_doc(%L)->>'kind')$q$,
    (select token from public.issued_documents where sid = 'IQ-1151' and kind = 'certificate'), (select token from public.issued_documents where sid = 'IQ-1151' and kind = 'certificate'))), '^true/certificate$');
select zz.chk('D11 chiqqan o''quvchiga egasi uchun yangi kod yozilmagan', (select count(*)::text from public.issued_documents where sid = 'IQ-1151' and "issuedBy" in ('U_PX', 'U_STX')), '^0$');

-- ===== A7-09: kabinetdagi «Uzish» faqat ota-ona bog'lanishlarini uzadi =====
select zz.chk('U01 linkId''siz uzish (kabinet) -> faqat ota-ona bog''lanishi; Direktorning kunlik hisobot havolasi faol qoladi',
  zz.try($q$select public.tg_unlink('U_DIR', null)::text$q$) || ' ' || zz.try($q$select string_agg(id || ':' || status, ',' order by id) from public.telegram_links where uid = 'U_DIR'$q$),
  '^1 L_DPAR:unlinked,L_DSTAFF:active$');
select zz.chk('U02 linkId bilan (admin «Sozlamalar») -> o''sha havola uziladi (o''zgarmagan)',
  zz.try($q$select public.tg_unlink('U_DIR', 'L_DSTAFF')::text$q$) || ' ' || zz.try($q$select status from public.telegram_links where id = 'L_DSTAFF'$q$), '^1 unlinked$');
select zz.chk('U03 boshqa hisobning havolasi linkId bilan ham uzilmaydi', zz.try($q$select public.tg_unlink('U_PA', 'L_P5')::text$q$) || ' ' || zz.try($q$select status from public.telegram_links where id = 'L_P5'$q$), '^0 active$');
select zz.chk('U04 mijoz tg_unlink chaqira olmaydi (faqat server)', zz.as('U_PA', $q$select public.tg_unlink('U_PA', null)::text$q$), '^ERR 42501');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
