-- =====================================================================
-- Deploy'dan OLDINGI ma'lumot tekshiruvi — FAQAT O'QIYDI (bazaga hech narsa yozmaydi).
--   Ishlatish (VPS):
--     sudo docker exec -i supabase-db psql -U postgres -d postgres -X -P pager=off < ~/iqror-repo/migration/deploy/predeploy-checks.sql
--   (migration/deploy/full-deploy.sh buni o'zi ishga tushiradi.) Bo'sh jadval = muammo yo'q.
--   Eski sxemada (masalan child_claims.status hali yo'q) ayrim band ERROR berishi mumkin — keyingi bandlar baribir ishlaydi.
-- =====================================================================
set default_transaction_read_only = on;
\pset footer off
\echo '== 1) Import to''qnashuvi: o''quvchining studentId''si BOSHQA o''quvchining id/studentId''siga teng (deploy bunday o''quvchining doc-id to''lovlarini KO''CHIRMAYDI — qo''lda hal qiling: kalitni noyob qiling yoki ataylab birlashtiring)'
select s.id, s."studentId", s.name,
       (select string_agg(t.id || ' (' || coalesce(t.name, '') || ')', ', ') from public.students t
         where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId")) as toqnashadi,
       (select count(*) from public.payments p where p."studentId" = s.id) as doc_id_tolovlar
  from public.students s
 where coalesce(s."studentId", '') <> '' and s."studentId" <> s.id
   and exists (select 1 from public.students t where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId"));
\echo '== 2) Chetida bo''sh joy bor kalitlar (deploy''dan keyin o''quvchi studentId''sini ilovada tuzatib bo''lmaydi — faqat SQL bilan)'
select 'students' as jadval, id, quote_literal("studentId") as kalit from public.students where "studentId" <> btrim("studentId")
union all select 'teachers', id, quote_literal("teacherId") from public.teachers where "teacherId" <> btrim("teacherId")
union all select 'staff', id, quote_literal("staffId") from public.staff where "staffId" <> btrim("staffId")
order by 1, 2;
\echo '== 3) Takroriy maosh kalitlari (o''qituvchi+xodim BITTA nom maydonida, btrim bilan): «ID o''zgartirish» umumiy tarixni ko''chirmaydi; eski ochiq admin oynasi bu kartalarni saqlay olmaydi'
with k as (select 'teachers' coll, id, name, coalesce(nullif("teacherId", ''), id) as raw from public.teachers
           union all select 'staff', id, name, coalesce(nullif("staffId", ''), id) from public.staff),
     g as (select btrim(raw) as maosh_kaliti, count(*) as egalari,
                  string_agg(coll || ':' || id || ' «' || coalesce(name, '') || '» raw=' || quote_literal(raw), '; ' order by coll, id) as kimlar
             from k group by 1 having count(*) > 1)
select g.*, (select count(*) from public.salary_payments sp where btrim(sp."teacherId") = g.maosh_kaliti) as maosh_qatorlari,
            (select count(*) from public.staff_advances sa where btrim(sa."teacherId") = g.maosh_kaliti) as avans_qatorlari
  from g order by 1;
\echo '== 4) Hozirgi o''qituvchi/xodimga tegishli bo''lmagan kalitdagi maosh tarixi (o''chirilganlar; kichik harf/bo''sh joy variantlari) — ma''lumot uchun'
with keys as (select coalesce(nullif("teacherId", ''), id) k from public.teachers union all select coalesce(nullif("staffId", ''), id) from public.staff)
select 'salary_payments' jadval, quote_literal("teacherId") kalit, count(*) from public.salary_payments where coalesce("teacherId", '') <> '' and "teacherId" not in (select k from keys) group by 2
union all
select 'staff_advances', quote_literal("teacherId"), count(*) from public.staff_advances where coalesce("teacherId", '') <> '' and "teacherId" not in (select k from keys) group by 2
order by 1, 2;
\echo '== 5) O''quvchisiz («arvoh») kodlar: deploy faqat <= max(5, 20%) bo''lsa o''chiradi; ko''p bo''lsa — deploy chiqishida ⚠️ qatori'
select count(*) filter (where not exists (select 1 from public.students s where s.id = sc.id)) as arvohlar, count(*) as jami_kodlar,
       case when count(*) filter (where not exists (select 1 from public.students s where s.id = sc.id)) = 0 then 'hech narsa'
            when count(*) filter (where not exists (select 1 from public.students s where s.id = sc.id)) <= greatest(5, count(*) / 5) then 'deploy O''CHIRADI'
            else 'avtomatik o''chirilMAYDI (deploy ⚠️ ko''rsatadi)' end as deploy_amali
  from public.student_codes sc;
\echo '== 6) Ota-ona bog''lanishlari holati: «active» bo''lmaganlari deploy''dan keyin farzand ma''lumotini KO''RMAYDI'
select coalesce(nullif(status, ''), '(bo''sh = active)') as holat, count(*) from public.child_claims group by 1 order by 1;
\echo '== 7) Deploy qayta yozadigan ma''lumot (rejali tenglashlar)'
select 'to''lovlar: doc id -> studentId' as nima, count(*) from public.payments p join public.students s on p."studentId" = s.id
 where coalesce(s."studentId", '') <> '' and s."studentId" <> s.id
   and not exists (select 1 from public.students t where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId"))
union all
select 'qaytarishlar: doc id -> studentId', count(*) from public.refunds r join public.students s on r."studentId" = s.id
 where coalesce(s."studentId", '') <> '' and s."studentId" <> s.id
   and not exists (select 1 from public.students t where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId"))
union all
select '«Davomat %» qayta hisoblanadigan o''quvchilar', count(*) from public.students s
  join (select a."studentId" sid,
               round(100.0 * count(*) filter (where coalesce(e.v, '') in ('present', 'late'))
                     / nullif(count(*) filter (where coalesce(e.v, '') not in ('sick', 'excused')), 0))::int pct
          from public.attendance a cross join lateral jsonb_each_text(case when jsonb_typeof(a.days) = 'object' then a.days else '{}'::jsonb end) e(k, v)
         where coalesce(a."studentId", '') <> '' group by 1) x
    on (s."studentId" = x.sid or (coalesce(s."studentId", '') = '' and s.id = x.sid))
 where x.pct is not null and s.attendance is distinct from x.pct;
\echo '== 8) Deploy''ni to''sib qo''yishi mumkin bo''lgan ulanishlar (lock_timeout 20 s) — deploy oldidan bo''sh bo''lishi kerak'
select pid, usename, application_name, state, now() - xact_start as yoshi, left(query, 80) as sorov
  from pg_stat_activity
 where datname = current_database() and pid <> pg_backend_pid() and xact_start is not null and now() - xact_start > interval '5 seconds'
 order by xact_start;
