-- =====================================================================
-- RLS cross-rol testi (auth tizimi). Toza authtest bazasida ishlatiladi:
--   runuser -u postgres -- psql -d authtest -f migration/test-auth-rls.sql
-- Har tekshiruv kutilgan natijani bosib chiqaradi (OK/FAIL ko'rinadi).
-- =====================================================================
\set ON_ERROR_STOP off
\pset pager off

-- ---- urug' (postgres = RLS chetlab) ----
set role postgres;
insert into public.users(id,role,verified,status,phone) values
  ('u_admin','director',true,'active','998900000001'),
  ('u_pa','parent',true,'active','998900000002'),
  ('u_pb','parent',true,'active','998900000003'),
  ('u_tt','teacher',false,'pending','998900000004')
on conflict (id) do update set role=excluded.role,verified=excluded.verified,status=excluded.status,phone=excluded.phone;

insert into public.students(id,"studentId",name) values ('S1','S1','Bola Bir'),('S2','S2','Bola Ikki')
on conflict (id) do nothing;
insert into public.student_codes(id,code) values ('S1','CODE1'),('S2','CODE2') on conflict (id) do update set code=excluded.code;
insert into public.child_claims(id,uid,"studentId",code,status) values ('cc1','u_pa','S1','CODE1','active')
on conflict (id) do update set uid=excluded.uid,"studentId"=excluded."studentId",status='active';
insert into public.student_private(id,"parentPhone") values ('S1','998900000002'),('S2','998900000003')
on conflict (id) do update set "parentPhone"=excluded."parentPhone";
insert into public.invoices(id,"studentId",month,amount,status) values
  ('inv_s1','S1','2026-10',500000,'pending'),('inv_s2','S2','2026-10',500000,'pending')
on conflict (id) do nothing;
insert into public.otp_codes(phone,"codeHash",purpose,"expiresAt") values ('998900000002','h','register', now()+interval '3 min');
insert into public.auth_login_attempts(phone,ok) values ('998900000002',false);

\echo '================= PARENT A (u_pa) ================='
set role authenticated;
set app.uid = 'u_pa';
\echo '--- users: faqat O''ZI (1 kutilади) ---'
select count(*) as users_visible_to_parentA from public.users;
\echo '--- users: begona (u_pb) ko''rinmasin (0 kutilади) ---'
select count(*) as sees_other_user from public.users where id='u_pb';
\echo '--- child_claims: faqat o''zining (1) ---'
select count(*) as own_claims from public.child_claims;
\echo '--- student_private: O''Z farzandi S1 (1) ---'
select count(*) as priv_own_child from public.student_private where id='S1';
\echo '--- student_private: BEGONA farzand S2 (0 kutilади) ---'
select count(*) as priv_other_child from public.student_private where id='S2';
\echo '--- invoices: O''Z farzandi S1 (1) ---'
select count(*) as inv_own from public.invoices where "studentId"='S1';
\echo '--- invoices: BEGONA S2 (0 kutilади) ---'
select count(*) as inv_other from public.invoices where "studentId"='S2';
\echo '--- otp_codes: TO''LIQ YOPIQ (0) ---'
select count(*) as otp_visible from public.otp_codes;
\echo '--- auth_login_attempts: TO''LIQ YOPIQ (0) ---'
select count(*) as login_attempts_visible from public.auth_login_attempts;
\echo '--- ESKALATSIYA: parent o''zini director qila OLMAYDI (xato/0) ---'
update public.users set role='director' where id='u_pa';
reset role; reset app.uid;
select role as parentA_role_after_attack from public.users where id='u_pa';

\echo '================= TEACHER (u_tt, pending) ================='
set role authenticated; set app.uid='u_tt';
\echo '--- O''ZINI TASDIQLAY OLMAYDI: verified=true / status=active (xato/BLOKLANADI) ---'
update public.users set verified=true, status='active' where id='u_tt';
reset role; reset app.uid;
select verified as tt_verified_after, status as tt_status_after from public.users where id='u_tt';

\echo '================= ADMIN (u_admin) ================='
set role authenticated; set app.uid='u_admin';
\echo '--- admin hamma userni ko''radi (>=4) ---'
select count(*) as users_visible_to_admin from public.users;
\echo '--- admin pending o''qituvchini tasdiqlaydi (ruxsat) ---'
update public.users set verified=true, status='active' where id='u_tt';
reset role; reset app.uid;
select verified as tt_verified_by_admin, status as tt_status_by_admin from public.users where id='u_tt';
\echo '================= HARDENING (ko''rikdan keyin) ================='
set role postgres;
-- yangi pending o'qituvchi + unga (xayoliy) biriktirilgan sinf — gate'ni sinash uchun
insert into public.users(id,role,verified,status,"assignedClasses") values
  ('u_tp','teacher',false,'pending','["g5a"]'::jsonb) on conflict (id) do update set status='pending',verified=false,"assignedClasses"='["g5a"]'::jsonb;
insert into public.teachers(id,name) values ('t_x','O''qituvchi X') on conflict (id) do nothing;

\echo '--- SELF-INSERT: oddiy user O''ZIGA role=teacher yoza OLMAYDI (BLOKLANADI) ---'
set role authenticated; set app.uid='u_hacker';
insert into public.users(id,role,verified,"assignedClasses") values ('u_hacker','teacher',false,'["g5a"]'::jsonb);
reset role; reset app.uid;
select count(*) as hacker_row_created from public.users where id='u_hacker';   -- 0 kutilади

\echo '--- PENDING o''qituvchi teachers ro''yxatini O''QIY OLMAYDI (is_staff active emas) (0) ---'
set role authenticated; set app.uid='u_tp';
select count(*) as pending_reads_teachers from public.teachers;
\echo '--- PENDING o''qituvchi students ro''yxatini O''QIY OLMAYDI (0) ---'
select count(*) as pending_reads_students from public.students;
reset role; reset app.uid;

\echo '--- otp_consume ATOMIK: noto''g''ri kod attempts oshiradi, 5-dan keyin locked ---'
set role postgres;
delete from public.otp_codes where phone='998900000009';
insert into public.otp_codes(phone,"codeHash",purpose,"expiresAt",attempts) values ('998900000009','GOOD','register', now()+interval '3 min',0);
select (public.otp_consume('998900000009','register','BAD',5))->>'remaining' as r1_remaining;   -- 4
select (public.otp_consume('998900000009','register','BAD',5))->>'remaining' as r2_remaining;   -- 3
select (public.otp_consume('998900000009','register','BAD',5))->>'remaining' as r3_remaining;   -- 2
select (public.otp_consume('998900000009','register','BAD',5))->>'remaining' as r4_remaining;   -- 1
select (public.otp_consume('998900000009','register','BAD',5))->>'remaining' as r5_remaining;   -- 0
select (public.otp_consume('998900000009','register','GOOD',5))->>'locked' as after_cap_locked;  -- true (cap, to'g'ri kod ham o'tmaydi)
\echo '--- otp_consume: toza kodda to''g''ri kod -> ok, consumed ---'
insert into public.otp_codes(phone,"codeHash",purpose,"expiresAt",attempts) values ('998900000010','GOOD2','register', now()+interval '3 min',0);
select (public.otp_consume('998900000010','register','GOOD2',5))->>'ok' as good_ok;   -- true
select (public.otp_consume('998900000010','register','GOOD2',5))->>'nocode' as reused_nocode;  -- true (consumed)
reset role;

\echo '================= TUGADI ================='
