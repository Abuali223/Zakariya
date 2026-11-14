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
--   Bandlar: 1–10 — tuzilma va huquqlar (har doim bir xil bo'lishi kerak); 11–22 — ma'lumot yaxlitligi; 23 — himoya mantig'i izi
--     (funksiya matnlari, himoya triggerlari, o'qish siyosatlari va cheklovlar — shu reliz toza zanjiridan olingan barmoq izlari bilan
--     solishtiriladi; qo'lda «tuzatilgan» funksiya yoki o'chirilgan cheklov keyingi deploydan oldin ham ko'rinadi); 24 — vazifalar
--     ajratilishi (ma'lumot: tasdiqsiz o'tgan hujjat, o'zi tasdiqlagan / pul bergan / tekshirgan); 25 — holat (ma'lumot uchun).
--   QOIDA: modul relizi o'zgarganda want_ver va 3-banddagi kutilgan sonlar yangilanadi (migration/fin-version.sql ga qarang); har
--     reliz (va himoya funksiyasi, trigger, siyosat yoki cheklov o'zgargan har o'zgarish) bilan 23-band barmoq izlari toza zanjirdan
--     qayta yoziladi: bash migration/kassa-fingerprints.sh (lokal sinov bazasida; pastdagi «barmoq-izlari» bloki — qo'lda tahrirlanmaydi).
--     Sinovi — migration/test-kassa-checks.sql (har band uchun toza va buzilgan holat).
--   Barmoq izi: funksiya — matni (prosrc), argumentlari, natijasi, tili, SECURITY DEFINER, o'zgaruvchanligi, search_path; trigger — jadval,
--     voqealar, funksiya, ustunlar; siyosat — buyruq, rollar, USING / WITH CHECK ifodasi; cheklov — ta'rifi. Funksiya va trigger izi
--     PostgreSQL versiyasiga bog'liq emas; siyosat va cheklov ifodasi (deparse) versiyaga bog'liq bo'lishi mumkin — bazaning asosiy
--     versiyasi izlar yozilgan versiyadan farq qilsa, ular solishtirilmaydi (25-bandda yoziladi; to'liq solishtirish — verify-db.sh).
-- =====================================================================
\set QUIET on
set default_transaction_read_only = on;
\pset footer off
\pset null ''
\set bad 0
\set err 0
\set want_ver 11
\set ver 0
-- har band bo'yicha muammo qatorlari soni (c1 … c24) — sinov (test-kassa-checks.sql) shularni o'qiydi
\set c1 0 \set c2 0 \set c3 0 \set c4 0 \set c5 0 \set c6 0 \set c7 0 \set c8 0 \set c9 0 \set c10 0 \set c11 0
\set c12 0 \set c13 0 \set c14 0 \set c15 0 \set c16 0 \set c17 0 \set c18 0 \set c19 0 \set c20 0 \set c21 0 \set c22 0
\set c23 0 \set c24 0
\set fn_re '^(kassa|fin_|tuition_)'
\set fin_tables '{gl_accounts,fin_articles,fin_category_map,fin_op_rules,fin_org,fin_signatories,fin_counterparties,cash_desks,doc_counters,cash_days,cash_docs,cash_doc_lines,payment_allocations,cash_day_events,cash_counts,fin_snapshots,cash_prints,cash_handovers}'
-- 23-band (qa-5): himoya mantig'i barmoq izlari — bazadagi holat (kind | name | h). Bitta so'rov matni — 23-band ham, izlarni qayta yozish
--   (bash migration/kassa-fingerprints.sh → «psql -v fp_dump=1», pastda) ham shuni ishlatadi. Nomlar search_path = public bilan olinadi.
--   Obyektlar: app / public dagi ^(kassa|fin_|tuition_) funksiyalar; moliya jadvallaridagi barcha va istalgan jadvaldagi trg_kassa_* /
--   trg_fin_* triggerlar (test soati qo'riqchisi ham); moliya jadvallarining va buxgalter o'qishining (*_acc_sel) siyosatlari; moliya
--   jadvallari cheklovlari (vazifalar ajratilishi: cash_days_verifier_ne_closer, cash_docs_approver_ne_requester ham).
select format($fp$
select 'func'::text as kind, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as name,
       left(md5(concat_ws('#', p.prosrc, pg_get_function_result(p.oid), l.lanname, p.prokind, p.prosecdef, p.provolatile, p.proisstrict,
                          p.proretset, array_to_string(p.proconfig, ','))), 16) as h
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
 where n.nspname in ('app', 'public') and p.proname ~ %1$L
union all
select 'trigger', case when n.nspname = 'public' then '' else n.nspname || '.' end || c.relname || '.' || t.tgname,
       left(md5(concat_ws('#', t.tgtype, fn.nspname || '.' || fp.proname || '(' || pg_get_function_identity_arguments(fp.oid) || ')',
                          encode(t.tgargs, 'hex'), t.tgattr::text, pg_get_expr(t.tgqual, t.tgrelid), t.tgdeferrable, t.tginitdeferred)), 16)
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
  join pg_proc fp on fp.oid = t.tgfoid join pg_namespace fn on fn.oid = fp.pronamespace
 where not t.tgisinternal and n.nspname in ('app', 'public')
   and ((n.nspname = 'public' and c.relname = any(%2$L::text[])) or t.tgname ~ '^trg_(kassa|fin)_')
union all
select 'policy', p.tablename || '.' || p.policyname,
       left(md5(concat_ws('#', p.cmd, p.permissive, array_to_string(p.roles, ','), p.qual, p.with_check)), 16)
  from pg_policies p
 where p.schemaname = 'public' and (p.tablename = any(%2$L::text[]) or p.policyname like '%%\_acc\_sel')
union all
select 'constraint', c.relname || '.' || k.conname, left(md5(k.contype::text || '#' || pg_get_constraintdef(k.oid)), 16)
  from pg_constraint k join pg_class c on c.oid = k.conrelid
 where c.relnamespace = 'public'::regnamespace and c.relname = any(%2$L::text[])
$fp$, :'fn_re', :'fin_tables') as fp_have \gset
\if :{?fp_dump}
-- Izlarni qayta yozish rejimi (migration/kassa-fingerprints.sh): faqat «kind|name|h» qatorlari, boshqa band ishlamaydi.
set search_path = public;
\pset tuples_only on
\pset format unaligned
select x.kind || '|' || x.name || '|' || x.h from (:fp_have) x order by x.kind, x.name;
\quit
\endif

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

\qecho '== 7) Moliya jadvallari: RLS yoqilgan, mijoz rollarida yozish huquqi va yozish siyosati yo''q, anon o''qiy olmaydi (yozish faqat funksiyalar orqali); kirgan foydalanuvchi o''qiy oladi (ko''rinishini siyosat belgilaydi)'
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
        -- qa-5: SELECT huquqi olib qo'yilsa sahifa ishlamaydi (hisoblagichlar — doc_counters — faqat funksiyalar orqali o'qiladi)
        select t.relname, 'authenticated: SELECT huquqi yo''q (sahifa o''qiy olmaydi)' from t where t.relname <> 'doc_counters' and not has_table_privilege('authenticated', t.oid, 'SELECT')
        union all
        select p.tablename, 'yozish siyosati: ' || p.policyname || ' (' || p.cmd || ')'
          from pg_policies p where p.schemaname = 'public' and p.tablename = any(:'fin_tables'::text[]) and p.cmd <> 'SELECT') x
 order by 2, 3;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c7 \gset

\qecho '== 8) Himoya triggerlari: yo''q yoki o''chirib qo''yilgan (o''zgarmaslik, kun va davr qulfi, server vaqti, «faqat funksiya orqali», test soati faqat sinov bazasida)'
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
               ('staff_advances', 'trg_fin_server_ts'), ('refunds', 'trg_fin_server_ts'),
               ('app.fin_clock', 'trg_fin_clock_guard')) w(jadval, trigger)   -- qa-5: test soati faqat sinov bazasida (fin-prereq.sql)
  left join pg_trigger t on t.tgname = w.trigger and not t.tgisinternal
                        and t.tgrelid = to_regclass(case when w.jadval like '%.%' then w.jadval else 'public.' || quote_ident(w.jadval) end)
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

-- <barmoq-izlari> Shu reliz toza zanjiridan olingan himoya mantig'i izlari (23-band). Qo'lda tahrirlanmaydi — qayta yozish:
--   bash migration/kassa-fingerprints.sh   (lokal PostgreSQL'da vaqtinchalik bazaga --dev zanjirni quradi va shu blokni almashtiradi)
\set fp_rel 11
\set fp_pg 16
select $fp$
constraint|cash_counts.cash_counts_counted_check|4771070363f33300
constraint|cash_counts.cash_counts_dayId_fkey|3ddb3cb9109705b7
constraint|cash_counts.cash_counts_desk_fkey|50ecb89a0ca8bcf3
constraint|cash_counts.cash_counts_kind_check|47143847aea1c855
constraint|cash_counts.cash_counts_paperCount_check|2f14ff1b48e44260
constraint|cash_counts.cash_counts_paperSum_check|921b98dd5d579c4b
constraint|cash_counts.cash_counts_pendingSum_check|0e7987b8a7cdecf0
constraint|cash_counts.cash_counts_pkey|73a6946c22c2793d
constraint|cash_day_events.cash_day_events_dayId_fkey|3ddb3cb9109705b7
constraint|cash_day_events.cash_day_events_kind_check|1569694d9d91391c
constraint|cash_day_events.cash_day_events_pkey|73a6946c22c2793d
constraint|cash_days.cash_days_closed_by|ddb57fc70ac1cbcb
constraint|cash_days.cash_days_closing_check|72fcdbcbd5ddfef0
constraint|cash_days.cash_days_counted|ca0333dc625cd7d7
constraint|cash_days.cash_days_counted_check|f1fcb0047d14ea2e
constraint|cash_days.cash_days_desk_day_key|2af19de801c39007
constraint|cash_days.cash_days_desk_fkey|50ecb89a0ca8bcf3
constraint|cash_days.cash_days_i4|0f564e7fae6de8ce
constraint|cash_days.cash_days_open_null|3ec5ae97ee5af5cf
constraint|cash_days.cash_days_opening_check|d47e7760c6eb3f4d
constraint|cash_days.cash_days_paper|96212016563e3242
constraint|cash_days.cash_days_paperCount_check|2f14ff1b48e44260
constraint|cash_days.cash_days_paperSum_check|921b98dd5d579c4b
constraint|cash_days.cash_days_payouts_check|19565aa8ebbd422f
constraint|cash_days.cash_days_pendingCount_check|b48bac6edc866ead
constraint|cash_days.cash_days_pendingSum_check|0e7987b8a7cdecf0
constraint|cash_days.cash_days_pkey|73a6946c22c2793d
constraint|cash_days.cash_days_receipts_check|a3e194eff74e3a21
constraint|cash_days.cash_days_status_check|fea58f265e8546df
constraint|cash_days.cash_days_verified_by|ed788cdff202db19
constraint|cash_days.cash_days_verifier_ne_closer|da99e530f29cde6f
constraint|cash_desks.cash_desks_openingAmount_check|05ec31e1159f65f2
constraint|cash_desks.cash_desks_pkey|73a6946c22c2793d
constraint|cash_desks.cash_desks_restartAmount_check|0fed0c495d438fa5
constraint|cash_doc_lines.cash_doc_lines_amount_check|5c245c77d04b5dc5
constraint|cash_doc_lines.cash_doc_lines_articleId_fkey|ae3b69226c59598a
constraint|cash_doc_lines.cash_doc_lines_cash|38f280838a7c66cd
constraint|cash_doc_lines.cash_doc_lines_credit_fkey|90cfb9e634f23241
constraint|cash_doc_lines.cash_doc_lines_debit_fkey|446da048a3a2f061
constraint|cash_doc_lines.cash_doc_lines_docId_fkey|973ac815366d1f18
constraint|cash_doc_lines.cash_doc_lines_docId_lineNo_key|f3dfae2d14fa4e4c
constraint|cash_doc_lines.cash_doc_lines_lineNo_check|2238577477cbec88
constraint|cash_doc_lines.cash_doc_lines_pkey|73a6946c22c2793d
constraint|cash_doc_lines.cash_doc_lines_sides|61b8e29837d9d538
constraint|cash_docs.cash_docs_amount_check|5c245c77d04b5dc5
constraint|cash_docs.cash_docs_approver_ne_requester|c26b449eb6df5cd2
constraint|cash_docs.cash_docs_client_ref|e73e5ca00536824b
constraint|cash_docs.cash_docs_dayId_fkey|3ddb3cb9109705b7
constraint|cash_docs.cash_docs_decision_check|f38126f87a034eb7
constraint|cash_docs.cash_docs_desk_fkey|50ecb89a0ca8bcf3
constraint|cash_docs.cash_docs_fiscal|2ab3402af2e9ef93
constraint|cash_docs.cash_docs_form_check|504da4428060202f
constraint|cash_docs.cash_docs_no_check|46cd7d1a6da8335f
constraint|cash_docs.cash_docs_no_status|76bf42f2b82c80a0
constraint|cash_docs.cash_docs_op_fkey|7154f4639527430a
constraint|cash_docs.cash_docs_partyType_check|cc99bef5929bf854
constraint|cash_docs.cash_docs_pkey|73a6946c22c2793d
constraint|cash_docs.cash_docs_posted_fields|2307e55d5144f025
constraint|cash_docs.cash_docs_status_check|8c603bd516d2763a
constraint|cash_handovers.cash_handovers_counted_check|4771070363f33300
constraint|cash_handovers.cash_handovers_dayId_fkey|3ddb3cb9109705b7
constraint|cash_handovers.cash_handovers_desk_fkey|50ecb89a0ca8bcf3
constraint|cash_handovers.cash_handovers_pendingSum_check|0e7987b8a7cdecf0
constraint|cash_handovers.cash_handovers_pkey|73a6946c22c2793d
constraint|cash_handovers.cash_handovers_status_check|eeaa414740953501
constraint|cash_prints.cash_prints_dayId_fkey|3ddb3cb9109705b7
constraint|cash_prints.cash_prints_docId_fkey|63d9d9c2ffe62e9d
constraint|cash_prints.cash_prints_kind_check|4d6cf8c76c4661f8
constraint|cash_prints.cash_prints_mode_check|46f4abb3b7cf66c2
constraint|cash_prints.cash_prints_pkey|73a6946c22c2793d
constraint|cash_prints.cash_prints_target|58c02eccfe119f30
constraint|doc_counters.doc_counters_lastNo_check|6505ec655161ab65
constraint|doc_counters.doc_counters_pkey|e0cee437038e1bd9
constraint|fin_articles.fin_articles_kind_check|84c631da99fdce28
constraint|fin_articles.fin_articles_pkey|73a6946c22c2793d
constraint|fin_category_map.fin_category_map_pkey|a82e749a863c72f7
constraint|fin_counterparties.fin_counterparties_kind_check|67ff4b945f0c7bc2
constraint|fin_counterparties.fin_counterparties_name_check|2f2154323b181dfb
constraint|fin_counterparties.fin_counterparties_pkey|73a6946c22c2793d
constraint|fin_op_rules.fin_op_rules_articleMode_check|b6abcb85b9d426fe
constraint|fin_op_rules.fin_op_rules_form_check|504da4428060202f
constraint|fin_op_rules.fin_op_rules_pkey|db736d573cf8eaad
constraint|fin_org.fin_org_cashLimit_check|291880eb5fc3c7ec
constraint|fin_org.fin_org_l1_check|b582362f859514c4
constraint|fin_org.fin_org_pkey|73a6946c22c2793d
constraint|fin_org.fin_org_printLang_check|1f0b8892d48ee077
constraint|fin_org.fin_org_t1_check|2f9480911611771f
constraint|fin_signatories.fin_signatories_list_check|d6d8693d8f653fed
constraint|fin_signatories.fin_signatories_pkey|73a6946c22c2793d
constraint|fin_snapshots.fin_snapshots_pkey|73a6946c22c2793d
constraint|fin_snapshots.fin_snapshots_version_check|ec4db17c2a692af6
constraint|gl_accounts.gl_accounts_kind_check|5bff40152473b561
constraint|gl_accounts.gl_accounts_pkey|2e0bf1d368ef45d1
constraint|payment_allocations.payment_allocations_docId_fkey|63d9d9c2ffe62e9d
constraint|payment_allocations.payment_allocations_fromCash_check|3015930b18e695dd
constraint|payment_allocations.payment_allocations_fromCredit_check|f5ed755876e7f5f5
constraint|payment_allocations.payment_allocations_pkey|73a6946c22c2793d
func|app.fin_clock_allowed()|7894de1623f34f3e
func|app.fin_clock_guard()|197376d472b3cc8d
func|app.fin_list2()|fd2ba396c2a2e1a2
func|app.fin_lock_check(p_day date, p_what text)|af22cffb251779f2
func|app.fin_lock_payments()|3cda528e964aa7a3
func|app.fin_lock_ready(p_through date)|d4ec95210b437e52
func|app.fin_lock_receipt(p_day date)|5218ffb28599649f
func|app.fin_lock_rows()|b7e1d1bb89a9df7a
func|app.fin_now()|af9b775fb20c9237
func|app.fin_receipts(p_from date, p_to date)|4b69a8405a905766
func|app.fin_server_ts()|a9cddfc6cf65d785
func|app.fin_snapshot_data(p_as_of date)|f759e168eedeb6bb
func|app.fin_text_day(p text)|6443cb4dbb6a384e
func|app.fin_today()|096719722f3d421d
func|app.kassa_acc_open(p_party text, p_desk text)|44193511cc5531e1
func|app.kassa_acc_overdue(p_desk text, p_asof date)|742864bdd787bd19
func|app.kassa_accountables(p_desk text, p_asof date)|963877d7d86e7aee
func|app.kassa_act_post(p_doc_id text, p_uid text, p_day date)|433520fe45b83c4c
func|app.kassa_adv_article(a fin_articles)|0b16c7bdfbc9660a
func|app.kassa_advance_check(p_month text)|eec913db5b30ccfd
func|app.kassa_amount(p_val jsonb, p_what text)|4013fd8e6c38a4a1
func|app.kassa_amount0(p_val jsonb, p_what text)|38a7b4b28b048712
func|app.kassa_append_only()|e78400a0126c0b26
func|app.kassa_bool(p jsonb, p_key text)|ec2651748a219629
func|app.kassa_cash_guard()|05a77e5794333de2
func|app.kassa_cash_rows(p_from date, p_to date, p_created_from timestamp with time zone, p_created_to timestamp with time zone, p_skip tstzrange[])|99eca9d289da39d0
func|app.kassa_commission(p jsonb)|810d98851fdc01f0
func|app.kassa_count_apply(p_desk text, p_day_id text, p_day date, p_kind text, p_counted numeric, p_pending numeric, p_refs jsonb, p_paper jsonb, p_denoms jsonb, p_commission jsonb, p_note text, p_uid text, p_holder text, p_by text, p_to_uid text, p_handover text, OUT o_expected numeric, OUT o_diff numeric, OUT o_doc_id text, OUT o_count_id text)|3b6c5642e3ab19b7
func|app.kassa_counter_guard()|17b5ccd9254b3d1f
func|app.kassa_daily(p_day date)|178c7e7adfca8a2f
func|app.kassa_damage_open(p_party text, p_desk text)|26cd9b92f22f1e5d
func|app.kassa_day_balance(p_day_id text)|bc0ad242d09ccbc8
func|app.kassa_day_blocks(p_day_id text)|a3d90a53356eff46
func|app.kassa_day_guard()|9c1a99de32d107b7
func|app.kassa_day_hash(p_day_id text)|b4282d860efa2abe
func|app.kassa_day_json(p_day_id text)|9ca7121f58ba4494
func|app.kassa_day_pending(p_day_id text)|dd20f40c49a8dda0
func|app.kassa_denoms_check(p_denoms jsonb, p_counted numeric)|28ec036da759e4b5
func|app.kassa_desk_balance(p_desk text)|9d7cf8a3ad593b5b
func|app.kassa_desk_guard()|3cc432899ef14193
func|app.kassa_doc_after()|01a4fe37a1af50a2
func|app.kassa_doc_build(p jsonb, p_form text, p_uid text, p_internal boolean, OUT o_id text, OUT o_dup boolean)|86bb3846eef3723a
func|app.kassa_doc_guard()|e6d92321f3b7e851
func|app.kassa_doc_json(p_id text)|773dae78fa4bb21b
func|app.kassa_doc_post(p_doc_id text, p_uid text, p_system boolean, p_captured timestamp with time zone, p_late_ok boolean, p_day_id text)|3733c246698e8a85
func|app.kassa_emp_left(p_ref text)|f781309f5cc1c81f
func|app.kassa_exp_category(p_article text, OUT o_category text, OUT o_label text)|5e6a43c3f180581f
func|app.kassa_flag(p_on boolean)|0ad01f53a15ee249
func|app.kassa_gap_check(p_desk text, p_year integer)|c1f885b0d59a3a35
func|app.kassa_golive_guard(p_old date, p_new date)|c9364d43ea226267
func|app.kassa_handover_block(p_desk text)|6b7553e04ed6f6bc
func|app.kassa_handover_guard()|06886cf0d564e479
func|app.kassa_handover_pending(p_desk text)|576708a6230b8640
func|app.kassa_handover_stale(p_desk text)|663654fcf3f1965a
func|app.kassa_is_org(p_cp text)|304a009463af2dff
func|app.kassa_line_guard()|551b384bb7536672
func|app.kassa_link_paid(p_doc_id text, p_uid text)|cc729cdd44225ad4
func|app.kassa_link_prelock(p_doc_id text)|ca0cdf03537d44da
func|app.kassa_link_void(p_doc_id text, p_uid text, p_reason text)|dc26dd7a4294bfb5
func|app.kassa_live()|7f04fd57dee29464
func|app.kassa_lock_desk(p_desk text)|75a587a584ed9666
func|app.kassa_mask_party(p_type text, p_id text, p_name text, p_system boolean)|fac7e559a8576f51
func|app.kassa_names(p_uids text[])|87ee55d6d6808a42
func|app.kassa_next_no(p_desk text, p_series text, p_year integer)|80a68d07a41b7b43
func|app.kassa_num(p jsonb, p_key text)|a410a52fbbcfc99b
func|app.kassa_op_user(p_uid text)|cd748347796953d5
func|app.kassa_operator()|41e97e64e44b4a77
func|app.kassa_org_due(p_doc cash_docs)|a81036df4022afea
func|app.kassa_party(p_type text, p_id text, p_name text, OUT o_id text, OUT o_name text)|6c8ff2c8c20098fe
func|app.kassa_party_label(p_type text, p_id text)|420c44cb60b52498
func|app.kassa_pay_guard()|7f5ab202bfa2af1f
func|app.kassa_payee_code(p_ref text)|97456c6b2da91ec2
func|app.kassa_pending_merge(p_day_id text, p_refs jsonb, p_room numeric)|0560d6301e488391
func|app.kassa_pending_open(p_refs jsonb)|a2d58abefb915025
func|app.kassa_pending_parse(p jsonb)|29242948e205b99f
func|app.kassa_period_bal(p_desk text, p_from date, p_to date, OUT o_open numeric, OUT o_close numeric, OUT o_adj numeric, OUT o_ref date)|ea334c823ac1b1f6
func|app.kassa_periods(p_desk text)|bb7d288361ea5c39
func|app.kassa_pre_day(p_desk text, p_day date)|7555f89f12002d06
func|app.kassa_reader()|6bddd741878a9b8b
func|app.kassa_reconcile(p_from date, p_to date)|3d726ad7c5e34a30
func|app.kassa_reconcile_range(p_from date, p_to date)|ca7a268a5c01c4b7
func|app.kassa_refund_resplit(p_doc_id text, p_uid text)|6b438097ecb4ddc5
func|app.kassa_resolve_day(p_desk text, p_captured timestamp with time zone, p_uid text, p_late_ok boolean, OUT o_day_id text, OUT o_day date, OUT o_late boolean)|a834ab2c32c73636
func|app.kassa_restart_adj(p_desk text, p_after date, p_to date)|00ca231ec05c1cf3
func|app.kassa_restart_stale(p_desk text)|b6274167f9a09762
func|app.kassa_shortage_default(p_snap jsonb)|d43e6f7ea6b29333
func|app.kassa_shortage_why(p_snap jsonb)|917aed96d5936108
func|app.kassa_tuition_alloc(p_before jsonb, p_amount numeric, p_debit text, p_credit_lines boolean, p_apply_dup boolean, p_day date)|00ec9646f7fac63d
func|app.kassa_tuition_before(p_sid text, p_day date, p_captured timestamp with time zone, p_asked text)|fa2088fc826b29ef
func|app.kassa_tuition_info(p_pay_id text)|bc91bdae2f75c015
func|app.kassa_tuition_post(p_pay_id text, p_amount numeric, p_payer_name text, p_captured timestamp with time zone, p_extra jsonb, p_before jsonb, p_apply_dup boolean)|13bcb0807603b2a5
func|app.kassa_user_cards(p_uid text)|2fecd501adbfa623
func|app.kassa_user_label(p_name text, p_ref_type text, p_ref_id text, p_uid text)|1619d01296fbe3b6
func|app.kassa_version()|796eabf11e70a27a
func|app.kassa_week_kpi(p_desk text, p_from date, p_to date)|23dc58b8b45d39cc
func|app.kassa_z_day(p_desk text, p_day date, p_late boolean, p_captured timestamp with time zone)|e388c6c761abaa22
func|app.kassa_z_put(p_day_id text, p_z jsonb, p_uid text, p_after boolean)|50bfdd09bc7cec0c
func|app.kassa_z_state(p_day_id text)|32862bf228476605
func|app.tuition_reverse_core(p_doc_id text, p_uid text, p_reason text)|fd66bc2a0c079bcf
func|public.fin_counterparty_confirm(p_id text, p_kind text, p_name text)|9752777eede3c416
func|public.fin_counterparty_save(p_id text, p_kind text, p_name text, p_stir text, p_note text, p_active boolean)|e283696ac0c8a823
func|public.fin_org_set(p jsonb)|aaeff99d5abbd285
func|public.fin_period_lock(p_through date, p_note text)|41051d1fe5b0971c
func|public.fin_signatory_save(p_id text, p_list integer, p_uid text, p_title text, p_full_name text, p_active boolean)|57c06fa6ae46d25c
func|public.fin_snapshot_get(p_id text)|3d2b401ee33bd279
func|public.fin_snapshot_take(p jsonb)|cab5e32bc98752ac
func|public.fin_snapshots_list()|3a2eceffe9c6adb6
func|public.kassa_adv_report(p jsonb)|04f8d32694894e7b
func|public.kassa_adv_report_void(p_id text, p_reason text)|e07212fd3b10e0d5
func|public.kassa_checks(p_desk text)|8d28d9c8f41c18e9
func|public.kassa_day_book(p_desk text, p_day date)|e659308b98324e16
func|public.kassa_day_close(p jsonb)|dfd07187e6e0cb50
func|public.kassa_day_reopen(p_desk text, p_day date, p_reason text)|552711197fee976c
func|public.kassa_day_verify(p_desk text, p_day date, p_papers boolean, p_note text)|6ba8e5ee66650b8b
func|public.kassa_day_z(p jsonb)|df7dd934ea930d3d
func|public.kassa_doc_approve(p_id text, p_note text)|8d7cf46af284722c
func|public.kassa_doc_cancel(p_id text, p_reason text)|db85f1ade475c0f6
func|public.kassa_doc_get(p_id text)|b50c76a4880785c6
func|public.kassa_doc_pay(p_id text)|fb85ef896da1b993
func|public.kassa_doc_reject(p_id text, p_reason text)|5d5573f6a368421e
func|public.kassa_doc_void(p_id text, p_reason text)|6ec84b5c11053d1d
func|public.kassa_handover(p jsonb)|c5a2c18a56d59af5
func|public.kassa_handover_accept(p_id text)|929b734a8a70de68
func|public.kassa_handover_cancel(p_id text, p_reason text)|b013fa34d41b3d8f
func|public.kassa_journal(p_desk text, p_from date, p_to date)|d67fb5f5d01b22c1
func|public.kassa_journal_export(p_desk text, p_from date, p_to date)|c2fe36b38ee75f88
func|public.kassa_kpi(p_desk text, p_weeks integer)|dad4c51aa918bc20
func|public.kassa_matrix(p_desk text, p_month text)|decf3f6ce906286b
func|public.kassa_month_pack(p_desk text, p_month text)|204bdeac201ba0ef
func|public.kassa_offset(p jsonb)|4f7a62400fbf8314
func|public.kassa_offset_void(p_id text, p_reason text)|9897bfc090c5c6c8
func|public.kassa_opening_set(p jsonb)|a4d8417f8195ebb1
func|public.kassa_overview(p_desk text)|449146faee03b115
func|public.kassa_payout_request(p jsonb)|e07b35753e1233d5
func|public.kassa_people()|4f633283d004d704
func|public.kassa_print_mark(p_kind text, p_id text, p_reissue boolean)|f7960e3209b1c2c7
func|public.kassa_receipt(p jsonb)|8716d44b4cd0738a
func|public.kassa_refs()|dc942708c9b16a35
func|public.kassa_refund_request(p jsonb)|7336614cc5de469c
func|public.kassa_salary_pay(p jsonb)|769c05bc466d4073
func|public.kassa_shortage_decide(p_doc_id text, p_decision text, p_note text, p_party text)|bcc0d451b2182306
func|public.kassa_staff_open(p_desk text, p_party text, p_month text)|8c672068449b6d79
func|public.kassa_state(p_desk text)|73e40004dd0b8db0
policy|cash_counts.cash_counts_sel|c7bb2ccc4a83a1b4
policy|cash_day_events.cash_day_events_sel|c7bb2ccc4a83a1b4
policy|cash_days.cash_days_sel|c7bb2ccc4a83a1b4
policy|cash_desks.cash_desks_sel|c7bb2ccc4a83a1b4
policy|cash_doc_lines.cash_doc_lines_sel|c7bb2ccc4a83a1b4
policy|cash_docs.cash_docs_sel|c7bb2ccc4a83a1b4
policy|cash_handovers.cash_handovers_sel|c7bb2ccc4a83a1b4
policy|cash_prints.cash_prints_sel|c7bb2ccc4a83a1b4
policy|config.config_acc_sel|217dec050bee35bc
policy|credit_ledger.credit_ledger_acc_sel|57f2921c5671f415
policy|expenses.expenses_acc_sel|57f2921c5671f415
policy|fin_articles.fin_articles_sel|c7bb2ccc4a83a1b4
policy|fin_category_map.fin_category_map_sel|c7bb2ccc4a83a1b4
policy|fin_counterparties.fin_counterparties_sel|c7bb2ccc4a83a1b4
policy|fin_op_rules.fin_op_rules_sel|c7bb2ccc4a83a1b4
policy|fin_org.fin_org_sel|c7bb2ccc4a83a1b4
policy|fin_signatories.fin_signatories_sel|c7bb2ccc4a83a1b4
policy|fin_snapshots.fin_snapshots_sel|909780daff6a2fd9
policy|gl_accounts.gl_accounts_sel|c7bb2ccc4a83a1b4
policy|payment_allocations.payment_allocations_sel|c7bb2ccc4a83a1b4
policy|payroll_runs.payroll_runs_acc_sel|57f2921c5671f415
policy|staff_advances.staff_advances_acc_sel|57f2921c5671f415
policy|student_credit.student_credit_acc_sel|57f2921c5671f415
trigger|app.fin_clock.trg_fin_clock_guard|339ff52879201f41
trigger|cash_counts.trg_kassa_append_only|37e5f38a40fc5ecf
trigger|cash_day_events.trg_kassa_append_only|37e5f38a40fc5ecf
trigger|cash_days.trg_change_log|39b037665bb56478
trigger|cash_days.trg_kassa_day_guard|80bf0c34bb6959da
trigger|cash_desks.trg_change_log|006a6be359eaad50
trigger|cash_desks.trg_kassa_desk_guard|77a53a25a48dcc48
trigger|cash_doc_lines.trg_kassa_line_guard|9dac5fa7011872f9
trigger|cash_docs.trg_change_log|fb27fe6cd0c9cfe5
trigger|cash_docs.trg_kassa_doc_after|92c7b830a867390a
trigger|cash_docs.trg_kassa_doc_guard|12e63715894dac2c
trigger|cash_handovers.trg_kassa_handover_guard|6294542289af399d
trigger|cash_prints.trg_kassa_append_only|37e5f38a40fc5ecf
trigger|doc_counters.trg_kassa_counter_guard|cfa615cab93d0e55
trigger|expenses.trg_fin_server_ts|bc50f81cab944305
trigger|expenses.trg_fin_zlock|5a2618b507878a85
trigger|expenses.trg_kassa_cash_guard|1ce9b92eedcce8b6
trigger|fin_articles.trg_change_log|77669933e056c28b
trigger|fin_counterparties.trg_change_log|9517c70083ceda78
trigger|fin_op_rules.trg_change_log|78a05dc42a94b893
trigger|fin_org.trg_change_log|523a698a187984b1
trigger|fin_signatories.trg_change_log|66755163057ba48b
trigger|fin_snapshots.trg_kassa_append_only|37e5f38a40fc5ecf
trigger|payment_allocations.trg_kassa_append_only|37e5f38a40fc5ecf
trigger|payments.trg_fin_server_ts|bc50f81cab944305
trigger|payments.trg_fin_zlock|0fd85f02274ed119
trigger|payments.trg_kassa_pay_guard|ae7170961f70ccc4
trigger|refunds.trg_fin_server_ts|bc50f81cab944305
trigger|salary_payments.trg_fin_server_ts|bc50f81cab944305
trigger|salary_payments.trg_fin_zlock|5a2618b507878a85
trigger|salary_payments.trg_kassa_cash_guard|1ce9b92eedcce8b6
trigger|staff_advances.trg_fin_server_ts|bc50f81cab944305
trigger|staff_advances.trg_fin_zlock|5a2618b507878a85
trigger|staff_advances.trg_kassa_cash_guard|1ce9b92eedcce8b6
$fp$ as fp_want \gset
-- </barmoq-izlari>

\if :ver_ok
\qecho '== 23) Himoya mantig''i izi: funksiya matni, himoya triggeri, o''qish siyosati yoki cheklov shu reliz (toza zanjir) izidan farq qiladi — qo''lda «tuzatilgan» yoki yarim o''rnatilgan baza (qaysi farqligini verify-db.sh to''liq ko''rsatadi)'
select current_setting('search_path') as kc_sp \gset
set search_path = public;
-- (o'zgaruvchilar matni 'true' / 'false' — SQL ichida mantiqiy qiymat bo'lib qo'yiladi)
select (current_setting('server_version_num')::int / 10000 = :fp_pg)::text as fp_same_pg, (:fp_rel = :want_ver)::text as fp_rel_ok \gset
select '!!' as belgi, x.tur, x.obyekt, x.holat
  from (select case coalesce(h.kind, w.kind) when 'func' then 'funksiya' when 'trigger' then 'trigger' when 'policy' then 'o''qish siyosati' else 'cheklov' end as tur,
               coalesce(h.name, w.name) as obyekt,
               case when h.h is null then 'yo''q (reliz izida bor)' when w.h is null then 'ortiqcha (reliz izida yo''q)' else 'o''zgargan' end as holat
          from (:fp_have) h
          full join (select split_part(l, '|', 1) as kind, split_part(l, '|', 2) as name, split_part(l, '|', 3) as h
                       from regexp_split_to_table(:'fp_want', E'\n') l where l ~ '^[a-z]+\|.+\|[0-9a-f]{16}$') w on w.kind = h.kind and w.name = h.name
         where :fp_rel_ok and h.h is distinct from w.h and (:fp_same_pg or coalesce(h.kind, w.kind) in ('func', 'trigger'))
        union all
        select 'reliz', 'barmoq izlari ' || :fp_rel || '-reliz uchun yozilgan, tekshiruv fayli ' || :want_ver || '-relizni kutadi',
               'eskirgan — bash migration/kassa-fingerprints.sh'
         where not :fp_rel_ok) x
 order by 2, 3;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c23 \gset
select set_config('search_path', :'kc_sp', false) as kc_sp \gset
\endif

\qecho '== 24) Vazifalar ajratilishi (CT-05, CT-07; g5) — o''tkazilgan / bekor qilingan hujjat va tekshirilgan kun: talab qilingan tasdiq yo''q; tasdiqlovchi so''rovchi yoki pul oluvchining o''zi; 2-ro''yxat bosqichini Direktor imzolagan (oluvchi 2-ro''yxat xodimi emas); pulni tasdiqlovchi bergan; avans hisobotini hisobdorning o''zi kiritgan / bekor qilgan; kunni unda qatnashgan xodim tekshirgan (rollar va xodim kartasiga bog''lanishlar — hozirgi holati bo''yicha)'
select '!!' as belgi, x.kassa, x.kun, x.hujjat, x.muammo
  from (select c.desk as kassa, c."businessDay" as kun, c.form || coalesce(' № ' || c.no, '') || ' (' || c.id || ')' as hujjat, m.muammo
          from public.cash_docs c
         cross join lateral (values
           (case when c."needsList2" and c."approvedBy" is null then '2-ro''yxat tasdig''isiz o''tkazilgan' end),
           (case when c."needsDirector" and c."dirApprovedBy" is null then 'Direktor tasdig''isiz o''tkazilgan' end),
           (case when c."approvedBy" = c."requestedBy" then 'tasdiqlovchi — so''rovchining o''zi' end),
           (case when c."partyType" = 'employee' and c."approvedBy" is not null and c."partyId" = any(app.kassa_user_cards(c."approvedBy"))
                 then 'tasdiqlovchi — pul oluvchining o''zi (bog''langan xodim kartasi)' end),
           (case when exists (select 1 from public.users u where u.id = c."approvedBy" and u.role = 'director')
                  and not (c."partyType" = 'employee'
                           and exists (select 1 from public.users u where u.role in ('finance_mgr', 'accountant') and c."partyId" = any(app.kassa_user_cards(u.id))))
                 then '2-ro''yxat bosqichini Direktor imzolagan, pul oluvchi 2-ro''yxat xodimi emas' end),
           (case when c."approvedBy" is not null and c."postedBy" = c."approvedBy" then 'pulni so''rovni tasdiqlagan xodimning o''zi bergan' end),
           (case when c.op = 'nc_adv_report' and c."partyId" = any(app.kassa_user_cards(c."createdBy")) then 'avans hisobotini hisobdorning o''zi kiritgan' end),
           (case when c.op = 'nc_adv_report' and c.status = 'void' and c."partyId" = any(app.kassa_user_cards(c."voidedBy"))
                 then 'avans hisobotini hisobdorning o''zi bekor qilgan' end)) m(muammo)
         where c.status in ('posted', 'void') and m.muammo is not null
        union all
        select d.desk, d.day, '—', 'kunni tekshirgan xodim ' || m.why
          from public.cash_days d
         cross join lateral (select case when d."verifiedBy" = d."closedBy" then 'uni yopgan'
                                         when exists (select 1 from public.cash_docs c where c."dayId" = d.id and c."postedBy" = d."verifiedBy") then 'shu kuni hujjat o''tkazgan'
                                         when exists (select 1 from public.cash_day_events e where e."dayId" = d.id and e.kind = 'reopen' and e."byUid" = d."verifiedBy")
                                           then 'kunni qayta ochgan'
                                         when exists (select 1 from public.cash_docs c where c."dayId" = d.id and c."voidedBy" = d."verifiedBy") then 'shu kunning hujjatini bekor qilgan'
                                         when exists (select 1 from public.cash_day_events e where e."dayId" = d.id and e.kind = 'zreport' and e."byUid" = d."verifiedBy")
                                           then 'shu kunning Z-hisobotini kiritgan yoki tuzatgan'
                                         when exists (select 1 from public.cash_handovers h where h."dayId" = d.id and h.status = 'accepted'
                                                        and d."verifiedBy" in (h."byUid", h."toUid", coalesce(h."fromUid", '')))
                                           then 'shu kungi smena topshirish-qabulida qatnashgan' end as why) m
         where d.status = 'verified' and m.why is not null) x
 order by 2, 3, 4, 5;
select :bad + :ROW_COUNT as bad, :err + (:'ERROR' = 'true')::int as err, :ROW_COUNT as c24 \gset

\qecho '== 25) Holat (ma''lumot uchun; muammo emas)'
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
            from public.cash_desks k where k.id = 'main')),
    -- qa-5: 23-band izlari qaysi reliz va PostgreSQL versiyasida yozilgani; versiya boshqa bo'lsa — siyosat va cheklovlar solishtirilmagan
    (12, 'himoya mantig''i izi (23-band)',
         'reliz ' || :fp_rel || ', ' || (select count(*) from regexp_split_to_table(:'fp_want', E'\n') l where l ~ '^[a-z]+\|.+\|[0-9a-f]{16}$')
         || ' ta obyekt, PostgreSQL ' || :fp_pg
         || case when current_setting('server_version_num')::int / 10000 <> :fp_pg
                 then ' (bazada PostgreSQL ' || current_setting('server_version_num')::int / 10000 || ': siyosat va cheklovlar solishtirilmadi — verify-db.sh)'
                 else '' end)
  ) x(n, nima, qiymat)
 order by x.n;
select :err + (:'ERROR' = 'true')::int as err \gset

\else
\qecho '   «Kassa» moduli bu bazada o''rnatilmagan — 2–25-bandlar o''tkazib yuborildi.'
\endif

\pset tuples_only on
select case when :bad = 0 and :err = 0 then '✅ Kassa tekshiruvi: muammo topilmadi'
            else '!! Kassa tekshiruvi: ' || :bad || ' ta muammo qatori'
                 || case when :err > 0 then ', ' || :err || ' ta band bajarilmadi (yuqoridagi ERROR xabarlari)' else '' end
                 || ' — yuqoridagi «!!» bilan boshlangan qatorlarni ko''ring' end
       || case when :'has_kassa' = 't' then ' (modul relizi ' || :ver || ').' else ' (kassa moduli o''rnatilmagan).' end;
