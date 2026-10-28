-- =====================================================================
-- Deploy'dan OLDINGI ma'lumot tekshiruvi — FAQAT O'QIYDI (bazaga hech narsa yozmaydi).
--   Ishlatish (VPS):
--     sudo docker exec -i supabase-db psql -U postgres -d postgres -X -P pager=off < ~/iqror-repo/migration/deploy/predeploy-checks.sql
--   (migration/deploy/full-deploy.sh buni o'zi ishga tushiradi.) Bo'sh jadval = muammo yo'q.
--   Eski sxemada (masalan child_claims.status hali yo'q) ayrim band ERROR berishi mumkin — keyingi bandlar baribir ishlaydi.
-- =====================================================================
\set QUIET on
set default_transaction_read_only = on;
\pset footer off
-- Kanonik o'qituvchi/xodim ID'si (deploy'dagi app.pid_key bilan AYNAN bir xil — eski bazada funksiya hali yo'q): ko'rinmas format
--   belgilari (:'pidcf' — zero-width, bidi, soft hyphen, BOM) hamma joydan, keyin chetidagi bo'shliqlar (:'pidws' — JavaScript trim()
--   to'plami: tab, NBSP …) olinadi, katta harf — faqat a–z (translate; locale'ga bog'liq emas).
\set pidcf '[\\u00ad\\u061c\\u180e\\u200b-\\u200f\\u202a-\\u202e\\u2060-\\u2064\\u2066-\\u206f\\ufeff]'
\set pidws '^[ \\t\\n\\v\\f\\r\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]+|[ \\t\\n\\v\\f\\r\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]+$'
\echo '== 1) Import to''qnashuvi: o''quvchining studentId''si BOSHQA o''quvchining id/studentId''siga teng (yoki doc id''si boshqa o''quvchining studentId''si) (deploy bunday o''quvchining doc-id to''lovlarini KO''CHIRMAYDI — qo''lda hal qiling: kalitni noyob qiling yoki ataylab birlashtiring)'
select s.id, s."studentId", s.name,
       (select string_agg(t.id || ' (' || coalesce(t.name, '') || ')', ', ') from public.students t
         where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId" or t."studentId" = s.id)) as toqnashadi,
       (select count(*) from public.payments p where p."studentId" = s.id) as doc_id_tolovlar
  from public.students s
 where coalesce(s."studentId", '') <> '' and s."studentId" <> s.id
   and exists (select 1 from public.students t where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId" or t."studentId" = s.id));
\echo '== 2) Chetida bo''sh joy yoki ko''rinmas / ASCII bo''lmagan belgi (tab, NBSP, zero-width …; quote_literal''da ko''rinmasligi mumkin) bor kalitlar (o''quvchi studentId''sini deploy''dan keyin ilovada tuzatib bo''lmaydi — faqat SQL; o''qituvchi/xodim ID''si chetidagi bo''shliqlarsiz, katta harf bilan solishtiriladi)'
select 'students' as jadval, id, quote_literal("studentId") as kalit from public.students where "studentId" <> btrim("studentId") or "studentId" !~ '^[ -~]*$'
union all select 'teachers', id, quote_literal("teacherId") from public.teachers where "teacherId" <> btrim("teacherId") or "teacherId" !~ '^[ -~]*$'
union all select 'staff', id, quote_literal("staffId") from public.staff where "staffId" <> btrim("staffId") or "staffId" !~ '^[ -~]*$'
order by 1, 2;
\echo '== 3) Takroriy o''qituvchi/xodim ID''lari (o''qituvchi+xodim BITTA nomlar fazosida; kanonik — bo''shliqsiz, katta harf — bo''yicha): bu odamlarga maosh/avans berish BLOKLANGAN — kartochkada «Yangi noyob ID berish» bilan bir martalik tuzating (prefiksi jadvalga mos egasi — IQT- o''qituvchi / IQX- xodim — ID''ni saqlaydi; ID''lar pasport kabi o''zgarmaydi)'
with k as (select 'teachers' coll, id, name, coalesce(nullif("teacherId", ''), id) as raw from public.teachers
           union all select 'staff', id, name, coalesce(nullif("staffId", ''), id) from public.staff),
     g as (select translate(regexp_replace(regexp_replace(raw, :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') as maosh_kaliti, count(*) as egalari,
                  string_agg(coll || ':' || id || ' «' || coalesce(name, '') || '» raw=' || quote_literal(raw), '; ' order by coll, id) as kimlar
             from k group by 1 having count(*) > 1)
select g.*, (select count(*) from public.salary_payments sp where translate(regexp_replace(regexp_replace(sp."teacherId", :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') = g.maosh_kaliti) as maosh_qatorlari,
            (select count(*) from public.staff_advances sa where translate(regexp_replace(regexp_replace(sa."teacherId", :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') = g.maosh_kaliti) as avans_qatorlari
  from g order by 1;
\echo '== 4) Hozirgi o''qituvchi/xodimga tegishli bo''lmagan kalitdagi maosh tarixi (o''chirilganlar; kichik harf/bo''sh joy variantlari) — ma''lumot uchun'
with keys as (select coalesce(nullif("teacherId", ''), id) k from public.teachers union all select coalesce(nullif("staffId", ''), id) from public.staff)
select 'salary_payments' jadval, quote_literal("teacherId") kalit, count(*) from public.salary_payments where coalesce("teacherId", '') <> '' and "teacherId" not in (select k from keys) group by 2
union all
select 'staff_advances', quote_literal("teacherId"), count(*) from public.staff_advances where coalesce("teacherId", '') <> '' and "teacherId" not in (select k from keys) group by 2
order by 1, 2;
\echo '== 5) O''quvchisiz («arvoh») kodlar — kalit hech qaysi o''quvchining id/studentId''si emas (zararsiz): deploy faqat <= max(5, 20%) bo''lsa o''chiradi; ko''p bo''lsa — deploy chiqishida ⚠️ qatori (qo''lda tozalash: migration/deploy/README.md «Arvoh kodlar»)'
select count(*) filter (where g) as arvohlar, count(*) as jami_kodlar,
       case when count(*) filter (where g) = 0 then 'hech narsa'
            when count(*) filter (where g) <= greatest(5, count(*) / 5) then 'deploy O''CHIRADI'
            else 'avtomatik o''chirilMAYDI (deploy ⚠️ ko''rsatadi)' end as deploy_amali
  from (select not exists (select 1 from public.students s where s.id = sc.id or s."studentId" = sc.id) as g from public.student_codes sc) x;
\echo '== 6) Ota-ona bog''lanishlari holati: «active» bo''lmaganlari deploy''dan keyin farzand ma''lumotini KO''RMAYDI'
select coalesce(nullif(status, ''), '(bo''sh = active)') as holat, count(*) from public.child_claims group by 1 order by 1;
\echo '== 7) Deploy qayta yozadigan ma''lumot (rejali tenglashlar)'
select 'to''lovlar: doc id -> studentId' as nima, count(*) from public.payments p join public.students s on p."studentId" = s.id
 where coalesce(s."studentId", '') <> '' and s."studentId" <> s.id
   and not exists (select 1 from public.students t where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId" or t."studentId" = s.id))
union all
select 'qaytarishlar: doc id -> studentId', count(*) from public.refunds r join public.students s on r."studentId" = s.id
 where coalesce(s."studentId", '') <> '' and s."studentId" <> s.id
   and not exists (select 1 from public.students t where t.id <> s.id and (t.id = s."studentId" or t."studentId" = s."studentId" or t."studentId" = s.id))
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
\echo '== 9) O''qituvchi/xodim ID reyestri (payroll_ids): deploy shu ID''larni «hech qachon qayta berilmaydi» deb yozadi — o''chirilgan xodimlarniki (tarix / bog''langan login yorlig''i). Juda katta yoki g''alati raqam (masalan IQT-999999999) bo''lsa — deploy''dan OLDIN manbasini tekshiring: u yangi ID chegarasini abadiy ko''taradi'
select translate(regexp_replace(regexp_replace(h.k, :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') as id, string_agg(distinct h.src, ', ') as qayerdan
  from (select "teacherId" k, 'maosh' src from public.salary_payments
        union all select "teacherId", 'avans' from public.staff_advances
        union all select "teacherId", 'xodim farzandi' from public.student_private
        union all select "staffCode", 'login yorlig''i (users.staffCode)' from public.users
         where "staffRefType" in ('teacher', 'staff') and coalesce("staffRefId", '') <> '') h
 where translate(regexp_replace(regexp_replace(coalesce(h.k, ''), :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') <> ''
   and not exists (select 1 from public.teachers t where t.id = h.k or translate(regexp_replace(regexp_replace(t."teacherId", :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') = translate(regexp_replace(regexp_replace(h.k, :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'))
   and not exists (select 1 from public.staff s where s.id = h.k or translate(regexp_replace(regexp_replace(s."staffId", :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') = translate(regexp_replace(regexp_replace(h.k, :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'))
 group by 1 order by 1;
select coalesce(to_regclass('public.payroll_ids') is not null, false) as has_reg \gset
\if :has_reg
\echo '== 10) Reyestrda YO''Q joriy ID (trigger o''chirilgan / SQL bilan chetlab o''tilgan) — deploy to''ldiradi'
select coll, id, quote_literal(k) as kalit
  from (select 'teachers' coll, id, "teacherId" k from public.teachers union all select 'staff', id, "staffId" from public.staff) x
 where translate(regexp_replace(regexp_replace(coalesce(k, ''), :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') <> ''
   and not exists (select 1 from public.payroll_ids p where p.id = translate(regexp_replace(regexp_replace(x.k, :'pidcf', '', 'g'), :'pidws', '', 'g'), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'))
 order by 1, 2;
\endif
