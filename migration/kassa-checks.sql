-- =====================================================================
-- «Kassa» / moliya moduli tekshiruvi — FAQAT O'QIYDI (bazaga hech narsa yozmaydi). Moliya ish rejasi, F1.18.
--   Ishlatish (VPS; o'rnatishdan keyin va istalgan payt — masalan har oy oxirida):
--     sudo docker exec -i supabase-db psql -U postgres -d postgres -X -P pager=off < ~/iqror-repo/migration/kassa-checks.sql
--   (migration/deploy/full-deploy.sh buni «Keyingi tekshiruvlar»da o'zi ishga tushiradi.)
--   O'qish: har band ostida BO'SH jadval = muammo yo'q. Muammo qatorlari «!!» bilan boshlanadi. Oxirgi qator — yakun:
--     «✅ Kassa tekshiruvi: muammo topilmadi»  yoki  «!! Kassa tekshiruvi: N ta muammo qatori …».
--   Chiqishda ism, telefon va pul summalari YO'Q — faqat identifikatorlar, sanalar, sonlar va farqlar (ko'chirib yuborish xavfsiz).
--   Modul o'rnatilmagan bazada faqat 1-band ishlaydi. Sxema eski bo'lsa ayrim band ERROR berishi mumkin — keyingilari baribir
--     ishlaydi, yakunda «bajarilmagan bandlar» soni ko'rsatiladi.
--   Bandlar: 1–10 — tuzilma va huquqlar (har doim bir xil bo'lishi kerak); 11–22 — ma'lumot yaxlitligi; 23 — holat (ma'lumot uchun).
--   QOIDA: modul relizi o'zgarganda want_ver va 3-banddagi kutilgan sonlar yangilanadi (migration/fin-version.sql ga qarang);
--     sinovi — migration/test-kassa-checks.sql (har band uchun toza va buzilgan holat).
-- =====================================================================
\set QUIET on
set default_transaction_read_only = on;
\pset footer off
\pset null ''
\set bad 0
\set err 0
\set want_ver 10
\set ver 0
-- har band bo'yicha muammo qatorlari soni (c1 … c22) — sinov (test-kassa-checks.sql) shularni o'qiydi
\set c1 0 \set c2 0 \set c3 0 \set c4 0 \set c5 0 \set c6 0 \set c7 0 \set c8 0 \set c9 0 \set c10 0 \set c11 0
\set c12 0 \set c13 0 \set c14 0 \set c15 0 \set c16 0 \set c17 0 \set c18 0 \set c19 0 \set c20 0 \set c21 0 \set c22 0
\set fn_re '^(kassa|fin_|tuition_)'
\set fin_tables '{gl_accounts,fin_articles,fin_category_map,fin_op_rules,fin_org,fin_signatories,fin_counterparties,cash_desks,doc_counters,cash_days,cash_docs,cash_doc_lines,payment_allocations,cash_day_events,cash_counts,fin_snapshots,cash_prints,cash_handovers}'

\qecho '== 1) SECURITY DEFINER funksiyalar search_path''siz (butun baza: app, public) — bunday funksiyani chaqiruvchi o''z sxemasi orqali aldashi mumkin'
select '!!' as belgi, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as funksiya
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('app', 'public') and p.prosecdef
   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c where c like 'search_path=%')
   and not exists (select 1 from pg_depend dp where dp.classid = 'pg_proc'::regclass and dp.objid = p.oid and dp.deptype = 'e')
 order by 2;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c1 \gset

select to_regclass('public.cash_docs') is not null and to_regclass('public.fin_org') is not null as has_kassa \gset
\if :has_kassa

select to_regprocedure('app.kassa_version()') is not null as has_ver \gset
\if :has_ver
select app.kassa_version() as ver \gset
\else
\set ver 0
\endif
select (:ver = :want_ver) as ver_ok \gset

\qecho '== 2) Modul relizi (deploy markeri): bazadagi reliz shu tekshiruv fayli kutgani bilan bir xil bo''lishi kerak'
select '!!' as belgi,
       case when :ver = 0 then 'app.kassa_version() yo''q — modul to''liq o''rnatilmagan (zanjirni qayta ishga tushiring)'
            else 'bazada reliz ' || :ver || ', tekshiruv fayli kutgani ' || :want_ver || ' — repo va baza turli relizda (git fetch + deploy)' end as muammo
 where :ver <> :want_ver;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c2 \gset

\if :ver_ok
\qecho '== 3) Obyektlar soni (shu reliz uchun kutilgan). Farq bo''lsa — qaysi obyektligini verify-db.sh ko''rsatadi'
select '!!' as belgi, x.nima, x.bor, case when x.aniq then '' else 'kamida ' end || x.kutilgan as kutilgan
  from (values
    ('moliya jadvallari', (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname = any(:'fin_tables'::text[])), 18, true),   -- +1: cash_handovers (state-6, ikki bosqichli smena topshirish)
    ('ochiq (public) funksiyalar', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ :'fn_re'), 44, true),   -- +1: kassa_staff_open (acc-1); +1: fin_counterparty_confirm (sec-3); +2: kassa_handover_accept, kassa_handover_cancel (state-6)
    ('ichki (app) funksiyalar', (select count(*) from pg_proc p where p.pronamespace = 'app'::regnamespace and p.proname ~ :'fn_re'), 99, true),   -- +1: kassa_user_label (F1.21); +1: kassa_damage_open (acc-4); +3: kassa_adv_article (acc-5), kassa_exp_category (acc-9), kassa_refund_resplit (acc-7); +4: kassa_golive_guard, kassa_restart_adj, kassa_desk_balance (ui-5, §9 qayta ishga tushirish), kassa_cash_rows (crit-1); +4: kassa_periods, kassa_pre_day (g4v-1), kassa_restart_stale (g4v-2), kassa_reconcile_range (g4v-4); +2: kassa_user_cards (sec-1), kassa_org_due (sec-3); +4: kassa_handover_guard, kassa_handover_pending, kassa_handover_block (state-6), kassa_op_user (sec-2); +1: kassa_shortage_default (sec-2 / sec-4); +1: kassa_shortage_why (g6v-3); +3: kassa_pending_parse, kassa_pending_open, kassa_day_pending (state-2, crit-3); +2: kassa_z_day (g7v-1), kassa_pending_merge (g7v-3); +1: fin_lock_receipt (state-1); +2: kassa_emp_left (g9: ketgan xodimga yangi avans yo'q), kassa_handover_stale (g9: qabul qilinmay qolgan smena topshirish)
    ('himoya triggerlari (trg_kassa_*, trg_fin_*)', (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
                                                      where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and t.tgname ~ '^trg_(kassa|fin)_'), 25, true),   -- +1: trg_kassa_handover_guard (state-6)
    ('o''qish siyosatlari (RLS)', (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = any(:'fin_tables'::text[])), 17, true),   -- +1: cash_handovers_sel (state-6)
    -- ma'lumotnomalar keyin to'ldirilishi mumkin — faqat kamayishi muammo
    ('hisobvaraqlar rejasi (gl_accounts)', (select count(*) from public.gl_accounts), 92, false),
    ('statiyalar (fin_articles)', (select count(*) from public.fin_articles), 75, false),
    ('operatsiya qoidalari (fin_op_rules)', (select count(*) from public.fin_op_rules), 22, false)   -- 21 + in_damage_repay (acc-4)
  ) x(nima, bor, kutilgan, aniq)
 where x.bor <> x.kutilgan and (x.aniq or x.bor < x.kutilgan);
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c3 \gset
\endif

\qecho '== 4) Moliya funksiyalari search_path''siz (SECURITY DEFINER bo''lmaganlari ham)'
select '!!' as belgi, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as funksiya
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('app', 'public') and p.proname ~ :'fn_re'
   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c where c like 'search_path=%')
 order by 2;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c4 \gset

\qecho '== 5) Ichki (app.*) moliya funksiyalarini mijoz rollari chaqira oladi — faqat app.kassa_reader / kassa_operator / fin_list2 ochiq bo''lishi kerak (RLS siyosatlari ishlatadi)'
select '!!' as belgi, 'app.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as funksiya,
       concat_ws(', ', case when has_function_privilege('anon', p.oid, 'execute') then 'anon' end,
                       case when has_function_privilege('authenticated', p.oid, 'execute') then 'authenticated' end) as chaqira_oladi
  from pg_proc p
 where p.pronamespace = 'app'::regnamespace and p.proname ~ :'fn_re'
   and p.proname not in ('kassa_reader', 'kassa_operator', 'fin_list2')
   and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
 order by 2;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c5 \gset

\qecho '== 6) Ochiq (public.*) moliya funksiyalari: tizimga kirmagan (anon) chaqira olmasligi, kirgan foydalanuvchi (authenticated) chaqira olishi kerak'
select '!!' as belgi, 'public.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as funksiya,
       case when has_function_privilege('anon', p.oid, 'execute') then 'anon chaqira oladi' else 'authenticated chaqira olmaydi (sahifa ishlamaydi)' end as muammo
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.proname ~ :'fn_re'
   and (has_function_privilege('anon', p.oid, 'execute') or not has_function_privilege('authenticated', p.oid, 'execute'))
 order by 2;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c6 \gset

\qecho '== 7) Moliya jadvallari: RLS yoqilgan, mijoz rollarida yozish huquqi va yozish siyosati yo''q, anon o''qiy olmaydi (yozish faqat funksiyalar orqali)'
with t as (select c.oid, c.relname, c.relrowsecurity from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname = any(:'fin_tables'::text[]))
select '!!' as belgi, x.jadval, x.muammo
  from (select w.name as jadval, 'jadval yo''q' as muammo from unnest(:'fin_tables'::text[]) w(name) where not exists (select 1 from t where t.relname = w.name)
        union all
        select t.relname, 'RLS o''chiq' from t where not t.relrowsecurity
        union all
        select t.relname, r.rol || ': ' || pr.priv || ' huquqi bor'
          from t cross join (values ('anon'), ('authenticated')) r(rol) cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) pr(priv)
         where case when pr.priv in ('INSERT', 'UPDATE') then has_any_column_privilege(r.rol, t.oid, pr.priv) else has_table_privilege(r.rol, t.oid, pr.priv) end
        union all
        select t.relname, 'anon: SELECT huquqi bor' from t where has_any_column_privilege('anon', t.oid, 'SELECT')
        union all
        select p.tablename, 'yozish siyosati: ' || p.policyname || ' (' || p.cmd || ')'
          from pg_policies p where p.schemaname = 'public' and p.tablename = any(:'fin_tables'::text[]) and p.cmd <> 'SELECT') x
 order by 2, 3;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c7 \gset

\qecho '== 8) Himoya triggerlari: yo''q yoki o''chirib qo''yilgan (o''zgarmaslik, kun va davr qulfi, server vaqti, «faqat funksiya orqali»)'
select '!!' as belgi, w.jadval, w.trigger, case when t.oid is null then 'yo''q' else 'o''chirilgan (DISABLE)' end as holat
  from (values ('cash_counts', 'trg_kassa_append_only'), ('cash_day_events', 'trg_kassa_append_only'), ('cash_prints', 'trg_kassa_append_only'),
               ('fin_snapshots', 'trg_kassa_append_only'), ('payment_allocations', 'trg_kassa_append_only'),
               ('cash_days', 'trg_kassa_day_guard'), ('cash_desks', 'trg_kassa_desk_guard'), ('cash_doc_lines', 'trg_kassa_line_guard'),
               ('cash_handovers', 'trg_kassa_handover_guard'),
               ('cash_docs', 'trg_kassa_doc_guard'), ('cash_docs', 'trg_kassa_doc_after'), ('doc_counters', 'trg_kassa_counter_guard'),
               ('expenses', 'trg_kassa_cash_guard'), ('salary_payments', 'trg_kassa_cash_guard'), ('staff_advances', 'trg_kassa_cash_guard'),
               ('payments', 'trg_kassa_pay_guard'),
               ('payments', 'trg_fin_zlock'), ('expenses', 'trg_fin_zlock'), ('salary_payments', 'trg_fin_zlock'), ('staff_advances', 'trg_fin_zlock'),
               ('payments', 'trg_fin_server_ts'), ('expenses', 'trg_fin_server_ts'), ('salary_payments', 'trg_fin_server_ts'),
               ('staff_advances', 'trg_fin_server_ts'), ('refunds', 'trg_fin_server_ts')) w(jadval, trigger)
  left join pg_trigger t on t.tgname = w.trigger and not t.tgisinternal and t.tgrelid = to_regclass('public.' || quote_ident(w.jadval))
 where t.oid is null or t.tgenabled = 'D'
 order by 2, 3;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c8 \gset

\qecho '== 9) Noyoblik indekslari: yo''q yoki yaroqsiz (bitta ochiq kun, hujjat raqami, takror yuborish kaliti, surat versiyasi, bitta kutilayotgan smena topshirish)'
select '!!' as belgi, w.indeks, case when i.indexrelid is null then 'yo''q' else 'yaroqsiz (INVALID) — qayta quring' end as holat
  from (values ('cash_days_one_open'), ('cash_days_desk_day_key'), ('cash_docs_number'), ('cash_docs_client_ref'), ('fin_snapshots_day_ver'),
               ('cash_handovers_one_pending')) w(indeks)   -- state-6: kassada bittadan ortiq kutilayotgan smena topshirish yo'q
  left join pg_index i on i.indexrelid = to_regclass('public.' || quote_ident(w.indeks))
 where i.indexrelid is null or not i.indisvalid or not i.indisunique
 order by 2;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c9 \gset

\qecho '== 10) Bir xil nomli (overload) moliya funksiyalari — sahifa qaysi birini chaqirishini ajrata olmaydi'
select '!!' as belgi, n.nspname || '.' || p.proname as funksiya, count(*) as nusxa
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('app', 'public') and p.proname ~ :'fn_re'
 group by 2 having count(*) > 1 order by 2;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c10 \gset

\qecho '== 11) Kassa kunlari zanjiri: kun boshi = oldingi kun oxiri (qayta ishga tushirishda — + farq dalolatnomasi); birinchi kun boshi = boshlang''ich qoldiq = uning dalolatnomasi; kassada bittadan ortiq ochiq kun yo''q'
-- qayta ishga tushirish (ishga-tushirish §9; ui-5): oldingi kun bilan shu kun orasidagi «Д-» farq dalolatnomasi (OP-23, Dt 5010 Kt 0000 yoki teskari)
with d as (select d.id, d.desk, d.day, d.status, d.opening,
                  lag(d.closing) over w as prev_closing, lag(d.day) over w as prev_day, row_number() over w as rn
             from public.cash_days d window w as (partition by d.desk order by d.day)),
     d2 as (select d.*, coalesce((select sum(case when l.debit = '5010' then l.amount else -l.amount end)
                                    from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id and l.cash
                                   where c.desk = d.desk and c.op = 'nc_opening' and c.status = 'posted' and c."sourceSnapshot" ->> 'kind' = 'restart'
                                     and c."businessDay" > d.prev_day and c."businessDay" <= d.day), 0) as restart_adj
              from d)
select '!!' as belgi, x.kassa, x.kun, x.muammo, x.farq
  from (select d.desk as kassa, d.day as kun, 'kun boshi oldingi kun (' || to_char(d.prev_day, 'DD.MM.YYYY') || ') oxiriga teng emas'
               || case when d.restart_adj <> 0 then ' (qayta ishga tushirish farqi bilan)' else '' end as muammo,
               d.opening - d.prev_closing - d.restart_adj as farq
          from d2 d where d.rn > 1 and d.opening is distinct from d.prev_closing + d.restart_adj
        union all
        select d.desk, d.day, 'birinchi kun boshi kassaning boshlang''ich qoldig''iga teng emas', d.opening - k."openingAmount"
          from d join public.cash_desks k on k.id = d.desk where d.rn = 1 and d.opening is distinct from k."openingAmount"
        union all
        select d.desk, min(d.day), 'kassada ' || count(*) || ' ta ochiq kun', null from d where d.status = 'open' group by d.desk having count(*) > 1
        union all
        select k.id, k."startDay", 'boshlang''ich qoldiq dalolatnomasi yo''q, o''tkazilmagan yoki summasi boshlang''ich qoldiqqa teng emas',
               (select c.amount from public.cash_docs c where c.id = k."openingDocId") - k."openingAmount"
          from public.cash_desks k
         where coalesce(k."openingAmount", 0) > 0
           and not exists (select 1 from public.cash_docs c where c.id = k."openingDocId" and c.desk = k.id and c.op = 'nc_opening'
                                                               and c.status = 'posted' and c.amount = k."openingAmount")
        union all
        select c.desk, min(c."businessDay"), 'kassada ' || count(*) || ' ta o''tkazilgan boshlang''ich qoldiq dalolatnomasi', null
          from public.cash_docs c where c.op = 'nc_opening' and c.status = 'posted' and coalesce(c."sourceSnapshot" ->> 'kind', '') <> 'restart'
         group by c.desk having count(*) > 1) x
 order by 2, 3;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c11 \gset

\qecho '== 12) Yopilgan kun jamlari hujjatlardan qayta hisoblanganda mos kelmaydi (kirim, chiqim, hujjatlar soni)'
select '!!' as belgi, d.desk as kassa, d.day as kun, x.muammo, x.farq
  from public.cash_days d
 cross join lateral (select coalesce(sum(c.amount) filter (where c.status = 'posted' and c.form = 'KO1'), 0) as r,
                            coalesce(sum(c.amount) filter (where c.status = 'posted' and c.form = 'KO2'), 0) as p, count(*) as n
                       from public.cash_docs c where c."dayId" = d.id and c.status in ('posted', 'void')) s
 cross join lateral (values ('kirim jami kirim orderlari yig''indisiga teng emas', d.receipts - s.r),
                            ('chiqim jami chiqim orderlari yig''indisiga teng emas', d.payouts - s.p),
                            ('hujjatlar soni mos emas', (d."docCount" - s.n)::numeric),
                            ('kun oxiri = kun boshi + kirim − chiqim emas', d.closing - (d.opening + s.r - s.p))) x(muammo, farq)
 where d.status <> 'open' and x.farq is distinct from 0
 order by 2, 3, 4;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c12 \gset

\qecho '== 13) Yopilgan kun mazmuni izi (xesh) mos emas — kun yopilgandan keyin hujjatlari o''zgargan'
select '!!' as belgi, d.desk as kassa, d.day as kun, d.status as holat
  from public.cash_days d
 where d.status <> 'open' and d.hash is distinct from app.kassa_day_hash(d.id)
 order by 2, 3;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c13 \gset

\qecho '== 14) Raqamlash: bo''shliq yoki takror (hisoblagich = hujjatlar soni = eng katta raqam bo''lishi kerak)'
with s as (select c.desk, c.series, c.year, count(*) as cnt, max(c.no) as mx
             from public.cash_docs c where c.no is not null group by 1, 2, 3),
     k as (select k.desk, k.series, k.year, k."lastNo" as last_no from public.doc_counters k where k.series in ('KO1', 'KO2', 'ACT', 'OFS', 'ADV'))
select '!!' as belgi, coalesce(s.desk, k.desk) as kassa, coalesce(s.series, k.series) as turkum, coalesce(s.year, k.year) as yil,
       coalesce(k.last_no, 0) as hisoblagich, coalesce(s.cnt, 0) as hujjatlar, coalesce(s.mx, 0) as eng_katta_raqam
  from s full join k on k.desk = s.desk and k.series = s.series and k.year = s.year
 where coalesce(k.last_no, 0) <> coalesce(s.cnt, 0) or coalesce(k.last_no, 0) <> coalesce(s.mx, 0)
 order by 2, 3, 4;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c14 \gset

\qecho '== 15) Kassa kitobi (KO-4) varaqlari: raqamlar yil ichida uzluksiz emas yoki varaqlar soni hujjatlar soniga mos emas'
with d as (select d.desk, d.day, d."sheetFrom" as sf, d."sheetTo" as st, d."docCount" as n, d."sheetRows" as rows,
                  lag(d."sheetTo") over (partition by d.desk, extract(year from d.day) order by d.day) as prev_to
             from public.cash_days d where d.status <> 'open')
select '!!' as belgi, x.kassa, x.kun, x.muammo
  from (select d.desk as kassa, d.day as kun, 'birinchi varaq ' || coalesce(d.sf::text, '—') || ', kutilgan ' || (coalesce(d.prev_to, 0) + 1) as muammo
          from d where d.sf is distinct from coalesce(d.prev_to, 0) + 1
        union all
        select d.desk, d.day, 'varaqlar ' || coalesce((d.st - d.sf + 1)::text, '—') || ' ta, hujjatlar ' || coalesce(d.n::text, '—') || ' ta (varaqda ' || coalesce(d.rows::text, '—') || ' qator)'
          from d where (d.st - d.sf + 1) is distinct from greatest(1, ceil(d.n::numeric / nullif(d.rows, 0))::int)) x
 order by 2, 3;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c15 \gset

\qecho '== 16) O''tkazilgan hujjat qatorlari: qatorsiz hujjat; order summasi naqd (5010) qatorlar jamiga teng emas; dalolatnomada naqd qator (boshlang''ich qoldiq dalolatnomasidan tashqari)'
select '!!' as belgi, c.desk as kassa, c.form as shakl, c.year as yil, c.no as raqam, c.id as hujjat, x.muammo
  from public.cash_docs c
 cross join lateral (select count(*) as n, coalesce(sum(l.amount) filter (where l.debit = '5010'), 0) as dt,
                            coalesce(sum(l.amount) filter (where l.credit = '5010'), 0) as kt,
                            coalesce(sum(l.amount) filter (where l.debit <> '5010' and l.credit <> '5010' and l.analytics ->> 'kind' is distinct from 'credit_applied'), 0) as nc
                       from public.cash_doc_lines l where l."docId" = c.id) s
 cross join lateral (select case when s.n = 0 then 'qatorlari yo''q'
                                 when c.form = 'KO1' and (s.dt <> c.amount or s.kt <> 0) then 'kirim orderi: Dt 5010 qatorlar jami summaga teng emas'
                                 when c.form = 'KO2' and (s.kt <> c.amount or s.dt <> 0) then 'chiqim orderi: Kt 5010 qatorlar jami summaga teng emas'
                                 when c.op = 'nc_opening' and coalesce(c."sourceSnapshot" ->> 'kind', '') = 'restart'   -- qayta ishga tushirish farqi: ikkala tomon ham mumkin
                                      and (s.nc <> 0 or not ((s.dt = c.amount and s.kt = 0) or (s.kt = c.amount and s.dt = 0)))
                                   then 'qayta ishga tushirish dalolatnomasi: kassa (5010) qatori summaga teng emas'
                                 when c.op = 'nc_opening' and coalesce(c."sourceSnapshot" ->> 'kind', '') <> 'restart' and (s.dt <> c.amount or s.kt <> 0 or s.nc <> 0)
                                   then 'boshlang''ich qoldiq dalolatnomasi: Dt 5010 qatorlar jami summaga teng emas'
                                 when c.form = 'ACT' and c.op <> 'nc_opening' and (s.dt <> 0 or s.kt <> 0) then 'dalolatnomada naqd (5010) qator bor'
                                 when c.form = 'ACT' and c.op <> 'nc_opening' and s.nc <> c.amount then 'dalolatnoma: qatorlar jami summaga teng emas' end as muammo) x
 where c.status in ('posted', 'void') and x.muammo is not null
 order by 2, 3, 4, 5;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c16 \gset

\qecho '== 17) Hujjat va kassa kuni: hujjat boshqa kun yoki boshqa kassa kuniga bog''langan; raqam yili ish kuni yiliga teng emas'
select '!!' as belgi, c.desk as kassa, c.form as shakl, c.year as yil, c.no as raqam, c.id as hujjat, x.muammo
  from public.cash_docs c left join public.cash_days d on d.id = c."dayId"
 cross join lateral (select case when c."dayId" is not null and d.id is null then 'kassa kuni topilmadi'
                                 when d.id is not null and d.desk <> c.desk then 'boshqa kassaning kuniga bog''langan'
                                 when d.id is not null and c."businessDay" is distinct from d.day then 'ish kuni kassa kuniga teng emas'
                                 when c.no is not null and c.year is distinct from extract(year from c."businessDay")::int then 'raqam yili ish kuni yiliga teng emas'
                                 when c.form in ('KO1', 'KO2') and c.no is not null and c."dayId" is null then 'order kassa kuniga bog''lanmagan' end as muammo) x
 where x.muammo is not null
 order by 2, 3, 4, 5;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c17 \gset

\qecho '== 18) O''quv to''lovi taqsimoti: taqsimot jami hujjat summasiga teng emas (naqd o''quv to''lovi va o''zaro hisob)'
select '!!' as belgi, c.form as shakl, c.year as yil, c.no as raqam, c.id as hujjat,
       coalesce((select sum(a."fromCash") from public.payment_allocations a where a."docId" = c.id), 0) - c.amount as farq
  from public.cash_docs c
 where c.op in ('in_tuition', 'nc_offset') and c.status in ('posted', 'void')
   and coalesce((select sum(a."fromCash") from public.payment_allocations a where a."docId" = c.id), 0) <> c.amount
 order by 2, 3, 4;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c18 \gset

\qecho '== 19) Bog''lanishlar: yozuv yo''q kassa hujjatiga yoki SINOV kassasi hujjatiga bog''langan (sinov hujjatlari haqiqiy hisobga kirmasligi kerak)'
select '!!' as belgi, x.jadval, x.id as yozuv, x.doc as hujjat, case when c.id is null then 'kassa hujjati topilmadi' else 'SINOV kassasi hujjati' end as muammo
  from (select 'payments' as jadval, p.id, p."cashDocId" as doc from public.payments p where p."cashDocId" is not null
        union all select 'expenses', e.id, e."cashDocId" from public.expenses e where e."cashDocId" is not null
        union all select 'salary_payments', s.id, s."cashDocId" from public.salary_payments s where s."cashDocId" is not null
        union all select 'staff_advances', a.id, a."cashDocId" from public.staff_advances a where a."cashDocId" is not null
        union all select 'refunds', r.id, r."cashDocId" from public.refunds r where r."cashDocId" is not null) x
  left join public.cash_docs c on c.id = x.doc
  left join public.cash_desks k on k.id = c.desk
 where c.id is null or k."isTest"
 order by 2, 3;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c19 \gset

\qecho '== 20) Moslik (kassa ishlagan barcha kunlar: birinchi ishga tushgan kundan bugungacha, to''xtatilgan davrlarsiz — g4v-4): pul yozuvlari va kassa hujjatlari bir-biriga mos kelmaydi — P1 o''quv to''lovi, P4 xarajat, P5 maosh / avans / o''zaro hisob / xodim qaytargan pul, P8 qaytarish'
select '!!' as belgi, x.tekshiruv, x.soni
  from (select app.kassa_reconcile(null, null) as j) r
 cross join lateral (values ('P1: kirim orderisiz naqd o''quv to''lovi', (r.j #>> '{p1,pay}')::int),
                            ('P1: to''lov yozuvisiz kirim orderi', (r.j #>> '{p1,doc}')::int),
                            ('P4: chiqim orderisiz naqd xarajat', (r.j #>> '{p4,row}')::int),
                            ('P4: «Buxgalteriya»ga ko''chmagan xarajat orderi', (r.j #>> '{p4,doc}')::int),
                            ('P5: chiqim orderisiz naqd maosh / avans', (r.j #>> '{p5,row}')::int),
                            ('P5: yozuvsiz maosh / avans orderi', (r.j #>> '{p5,doc}')::int),
                            ('P5: o''zaro hisob (dalolatnoma, maosh, o''quv to''lovi) mos emas', (r.j #>> '{p5,ofs}')::int),
                            ('P5: xodim qaytargan pul (kirim orderi) va manfiy avans / maosh yozuvi mos emas', (r.j #>> '{p5,ret}')::int),
                            ('P8: chiqim orderisiz naqd qaytarish', (r.j #>> '{p8,row}')::int),
                            ('P8: yozuvsiz qaytarish orderi', (r.j #>> '{p8,doc}')::int)) x(tekshiruv, soni)
 where coalesce((r.j ->> 'live')::boolean, false) and coalesce(x.soni, 0) > 0;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c20 \gset

\qecho '== 21) Davr suratlari: saqlangan mazmun xeshi mos emas (surat o''zgargan)'
select '!!' as belgi, s.id as surat, s."asOfDay" as sana, s.version as versiya
  from public.fin_snapshots s
 where s.hash is distinct from encode(sha256(convert_to(s.payload::text, 'UTF8')), 'hex')
 order by 3, 4;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c21 \gset

\qecho '== 22) Sozlamalar ziddiyati: davr qulfi bugungi yoki kelajakdagi kunda; ishga tushirish sanasi bor, lekin asosiy kassada boshlang''ich qoldiq yo''q'
select '!!' as belgi, x.muammo
  from public.fin_org o
 cross join lateral (values (case when o."lockedThrough" >= app.fin_today() then 'davr qulfi (' || to_char(o."lockedThrough", 'DD.MM.YYYY') || ') bugundan oldin emas' end),
                            (case when o."kassaGoLive" is not null and o."kassaGoLive" <= app.fin_today()
                                       and not exists (select 1 from public.cash_desks k where k.id = 'main' and k."startDay" is not null and k."openingAmount" is not null)
                                  then 'kassa ishga tushirilgan (' || to_char(o."kassaGoLive", 'DD.MM.YYYY') || '), lekin asosiy kassaning boshlang''ich qoldig''i kiritilmagan' end)) x(muammo)
 where o.id = 'main' and x.muammo is not null;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c22 \gset

\qecho '== 23) Holat (ma''lumot uchun; muammo emas)'
select x.nima, x.qiymat
  from (values
    (1, 'modul relizi', :ver::text),
    (2, 'ishga tushirish sanasi (kassaGoLive)', coalesce((select to_char(o."kassaGoLive", 'DD.MM.YYYY') from public.fin_org o where o.id = 'main'), 'belgilanmagan')),
    (3, 'davr qulfi', coalesce((select to_char(o."lockedThrough", 'DD.MM.YYYY') || ' gacha' from public.fin_org o where o.id = 'main'), 'yo''q')),
    (4, 'kassa limiti / T1 / L1', (select case when coalesce(o."cashLimit", 0) > 0 then 'limit belgilangan' else 'limit belgilanmagan' end
                                       || '; T1 ' || case when coalesce(o.t1, 0) > 0 then 'belgilangan' else 'belgilanmagan' end
                                       || '; L1 ' || case when coalesce(o.l1, 0) > 0 then 'belgilangan' else 'belgilanmagan' end
                                     from public.fin_org o where o.id = 'main')),
    (5, 'tashkilot rekvizitlari va imzolar', (select case when coalesce(o."nameUz", '') <> '' then 'nomi bor' else 'nomi YO''Q' end
                                                  || '; STIR ' || case when coalesce(o.stir, '') <> '' then 'bor' else 'YO''Q' end
                                                from public.fin_org o where o.id = 'main')
                                              || '; imzo egalari: ' || (select count(*) from public.fin_signatories)::text),
    (6, 'kassalar', (select string_agg(k.id || case when k."isTest" then ' (sinov)' else '' end || case when not k.active then ' (o''chirilgan)' else '' end
                                       || ': ' || case when k."startDay" is null then 'boshlanmagan' else to_char(k."startDay", 'DD.MM.YYYY') || ' dan' end, '; ' order by k.id)
                       from public.cash_desks k)),
    (7, 'asosiy kassa kunlari', (select count(*) filter (where d.status = 'open') || ' ochiq, ' || count(*) filter (where d.status = 'closed') || ' yopilgan (tekshirilmagan), '
                                        || count(*) filter (where d.status = 'verified') || ' tekshirilgan; oxirgisi '
                                        || coalesce(to_char(max(d.day), 'DD.MM.YYYY'), '—')
                                   from public.cash_days d where d.desk = 'main')),
    (8, 'asosiy kassa hujjatlari', (select coalesce(string_agg(y.form || ' ' || y.status || ': ' || y.n, '; ' order by y.form, y.status), 'yo''q')
                                      from (select c.form, c.status, count(*) as n from public.cash_docs c where c.desk = 'main' group by 1, 2) y)),
    (9, 'sinov kassalari hujjatlari', (select count(*)::text from public.cash_docs c join public.cash_desks k on k.id = c.desk where k."isTest")),
    (10, 'davr suratlari', (select count(*) || ' ta' || coalesce('; oxirgisi ' || to_char(max(s."asOfDay"), 'DD.MM.YYYY'), '') from public.fin_snapshots s where s."asOfDay" is not null)),
    -- kassani to'xtatish va qayta ishga tushirish (ishga-tushirish §9) — summasiz
    (11, 'asosiy kassa: to''xtatish / qayta ishga tushirish',
         (select case when k."pausedAt" is not null then 'TO''XTATILGAN (' || to_char(k."pausedAt" at time zone 'Asia/Tashkent', 'DD.MM.YYYY') || ' dan)'
                           || case when k."restartDay" > coalesce((select max(d.day) from public.cash_days d where d.desk = k.id), k."restartDay" - 1)
                                   then '; qayta ishga tushirish tayyorlangan: ' || to_char(k."restartDay", 'DD.MM.YYYY') else '' end
                      when k."restartDay" > coalesce((select max(d.day) from public.cash_days d where d.desk = k.id), k."restartDay" - 1)
                        then 'qayta ishga tushadi: ' || to_char(k."restartDay", 'DD.MM.YYYY')
                      else 'ishlaydi' || coalesce('; oxirgi qayta ishga tushirish: ' || to_char(k."restartDay", 'DD.MM.YYYY'), '') end
            from public.cash_desks k where k.id = 'main'))
  ) x(n, nima, qiymat)
 order by x.n;
select :err + (:'ERROR' = 'true')::int as err \gset

\else
\qecho '   «Kassa» moduli bu bazada o''rnatilmagan — 2–23-bandlar o''tkazib yuborildi.'
\endif

\pset tuples_only on
select case when :bad = 0 and :err = 0 then '✅ Kassa tekshiruvi: muammo topilmadi'
            else '!! Kassa tekshiruvi: ' || :bad || ' ta muammo qatori'
                 || case when :err > 0 then ', ' || :err || ' ta band bajarilmadi (yuqoridagi ERROR xabarlari)' else '' end
                 || ' — yuqoridagi «!!» bilan boshlangan qatorlarni ko''ring' end
       || case when :'has_kassa' = 't' then ' (modul relizi ' || :ver || ').' else ' (kassa moduli o''rnatilmagan).' end;
