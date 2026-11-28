-- =====================================================================
-- test-rls-matrix.sql — moliya ish rejasi 2-bosqichi, F2.10 (reliz 26): pul va kassa jadvallarining REST (RLS + GRANT) matritsasi —
--   14 rol (Direktor, moliya menejeri, buxgalter, kassir, g'aznachi, HR, O'IBDO', marketing, qabulxona, o'qituvchi, ota-ona, hamshira,
--   sotuvchi, ma'muriyat rahbari) va tizimga kirmagan (anon) × har jadval / ko'rinish × SELECT / INSERT / UPDATE / DELETE.
--   Har urinish haqiqiy rol bilan (authenticated + JWT sub; anon — JWT siz), triggerlarsiz (session_replication_role = replica — faqat RLS
--   siyosati va GRANT qaror qiladi; biznes triggerlari — o'z sinovlarida) va o'z ichki tranzaksiyasida (natija yozilgach orqaga qaytariladi).
--     S — ko'radi (urug' qatoridan kamida bittasi ko'rinadi; ota-ona — o'z farzandiniki); I — RLS yangi qatorni qabul qiladi;
--     U / D — so'rov ustun o'qimaydi (set <ustun> = doimiy, returning 1, WHERE yo'q) — faqat UPDATE / DELETE siyosati ishlaydi (PostgREST
--     filtrsiz PATCH / DELETE kabi): kamida bitta qator o'zgarsa / o'chsa — ruxsat. 42501 (huquq yoki siyosat) yoki 0 qator — rad.
--     Boshqa xato (ma'lumot cheklovi) — «!» belgisi bilan (kutilmagan: urug' qatorini tuzatish kerak).
--   Kutilgan matritsa — pastdagi ro'yxat (har jadval: S=…;I=…;U=…;D=… — ruxsat berilgan rollar). Undan har farq — FAIL (yangi siyosat yoki rol
--   huquqi o'zgarsa shu yerda ko'rinadi); ro'yxatda yo'q (yangi) moliya jadvali ham FAIL.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-rls-matrix.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.payments) then
    raise exception 'test-rls-matrix.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- Bitta urinish: rol (null — anon) bilan so'rov, triggerlarsiz, natija — son ('n') yoki 'E <sqlstate>'; har doim orqaga qaytariladi.
create or replace function zz.probe(p_uid text, p_q text, p_count boolean) returns text language plpgsql as $$
declare r text; v_state text;
begin
  begin
    perform set_config('session_replication_role', 'replica', true);
    perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
    if p_uid is null then execute 'set local role anon'; else execute 'set local role authenticated'; end if;
    begin
      if p_count then execute p_q into r; else execute p_q; r := '1'; end if;
    exception when others then
      v_state := sqlstate; r := 'E ' || v_state;
    end;
    raise exception using errcode = 'ZZ001', message = coalesce(r, 'null');
  exception when sqlstate 'ZZ001' then
    r := sqlerrm;
  end;
  return r;
end $$;

-- ---------- Foydalanuvchilar (14 rol) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, verified, "extraRoles", "homeroomClasses", "assignedClasses") values
  ('U_DIR','d@x','Sinov Direktor','director','active',true,'[]','[]','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active',true,'[]','[]','[]'),
  ('U_ACC','a@x','Sinov Buxgalter','accountant','active',true,'[]','[]','[]'), ('U_KAS','k@x','Sinov Kassir','kassir','active',true,'[]','[]','[]'),
  ('U_TRS','g@x','Sinov Gaznachi','treasurer','active',true,'[]','[]','[]'), ('U_HR','h@x','Sinov Kadrlar','hr','active',true,'[]','[]','[]'),
  ('U_ZAV','z@x','Sinov Zavuch','zavuch','active',true,'[]','[]','[]'), ('U_MKT','m@x','Sinov Marketolog','marketing_mgr','active',true,'[]','[]','[]'),
  ('U_REC','r@x','Sinov Qabulxona','reception','active',true,'[]','[]','[]'), ('U_TCH','t@x','Sinov Muallim','teacher','active',true,'[]','["uz-5-A"]','["uz-5-A"]'),
  ('U_PAR','p@x','Sinov Ota','parent','active',true,'[]','[]','[]'), ('U_NUR','n@x','Sinov Hamshira','nurse','active',true,'[]','[]','[]'),
  ('U_SAL','s@x','Sinov Sotuvchi','sales','active',true,'[]','[]','[]'), ('U_ADM','ad@x','Sinov Mamuriyat','admin_head','active',true,'[]','[]','[]');
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus") values
  ('m1','IQ-M01','Sinov Bola Bir',5,'A','uz',''), ('m2','IQ-M02','Sinov Bola Ikki',7,'B','uz','');
insert into public.student_codes (id, code) values ('m1','Q7K2ZP');
insert into public.child_claims (id, uid, "studentId", code, status) values ('U_PAR__IQ-M01','U_PAR','IQ-M01','Q7K2ZP','active');
-- ota-onaning farzandiga (IQ-M01) va boshqa o'quvchiga (IQ-M02) pul qatorlari
insert into public.invoices (id, "studentId", "studentName", "classKey", month, amount, "paidAmount", status) values
  ('IQ-M01__2026-11','IQ-M01','Sinov Bola Bir','uz-5-A','2026-11',2900000,0,'pending'), ('IQ-M02__2026-11','IQ-M02','Sinov Bola Ikki','uz-7-B','2026-11',2900000,0,'pending');
insert into public.student_credit (id, "studentId", credit) values ('IQ-M01','IQ-M01',0), ('IQ-M02','IQ-M02',0);
insert into public.credit_ledger (id, "studentId", delta, "balanceAfter", reason) values ('cl1','IQ-M01',1,1,'manual'), ('cl2','IQ-M02',1,1,'manual');
insert into public.payments (id, "studentId", provider, amount, status, raw, matched, "createdAt") values
  ('p1','IQ-M01','cash',2900000,'applied','{}',true,'2026-11-05 10:00+05'), ('p2','IQ-M02','click',2900000,'applied','{}',true,'2026-11-05 10:00+05');
insert into public.applied_payments (id, "studentId", amount, result) values ('p1','IQ-M01',2900000,'{}'), ('p2','IQ-M02',2900000,'{}');
insert into public.refunds (target, "targetId", "studentId", amount, reason, month) values ('invoice','IQ-M01__2026-11','IQ-M01',1,'zz','2026-11');
insert into public.expenses (id, date, month, category, amount, note) values ('e1','2026-11-04','2026-11','Kanselyariya',50000,'sinov');
insert into public.change_log (actor_uid, tbl, row_id, op, changes) values ('U_DIR','payments','p1','UPDATE','{}');
insert into public.fin_direct_log (grp, tbl, op, row_id, via) values ('payments','payments','UPDATE','p1','rest');

-- ---------- Jadvallar ro'yxati ----------
create table zz.t (tbl text primary key, kind text);
insert into zz.t (tbl, kind)
select c.relname, case c.relkind when 'v' then 'v' else 'r' end from pg_class c
 where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v')
   and (c.relname in ('payments', 'invoices', 'student_credit', 'credit_ledger', 'applied_payments', 'expenses', 'refunds', 'salary_payments',
                      'staff_advances', 'payroll_runs', 'payroll_lines', 'fin_direct_log', 'change_log', 'fin_exp_class', 'fin_exp_class_sign',
                      'gl_accounts', 'fin_articles', 'fin_category_map', 'fin_op_rules', 'fin_org', 'fin_signatories', 'fin_counterparties', 'cash_desks',
                      'doc_counters', 'cash_days', 'cash_docs', 'cash_doc_lines', 'payment_allocations', 'cash_day_events', 'cash_counts', 'fin_snapshots',
                      'cash_prints', 'cash_handovers', 'fin_exp_docs', 'cash_doc_fixes', 'cash_doc_verify', 'cash_doc_files')
        or (c.relkind = 'v' and c.relname ~ '_acc$'));

-- Bo'sh jadvalga bitta qator (test-sales-role.sql dagi umumiy urug'chi bilan bir xil qoida): NOT NULL ustunlar — turiga qarab, CHECK
--   talab qiladigan qiymatlar — ro'yxatdan.
create or replace function zz.row_sql(p_tbl text, p_id text) returns text language plpgsql as $$
declare col record; v_cols text[] := '{}'; v_vals text[] := '{}'; v_ov jsonb; v_oid oid := ('public.' || quote_ident(p_tbl))::regclass;
  ovr constant jsonb := '{
    "cash_counts": {"kind": "close"}, "cash_day_events": {"kind": "open"}, "cash_days": {"status": "open"}, "cash_doc_fixes": {"status": "pending"},
    "cash_doc_lines": {"cash": "false", "debit": "1010", "credit": "2010"}, "cash_docs": {"form": "KO1", "status": "draft", "partyType": "other"},
    "cash_handovers": {"status": "pending"}, "cash_doc_verify": {"token": "00000000000000000000000000000000"},
    "cash_doc_files": {"path": "adv/00000000-0000-4000-8000-000000000000.jpg"}, "cash_prints": {"kind": "doc", "mode": "original", "docId": "zz_doc"},
    "fin_counterparties": {"kind": "other", "name": "Sinov Hamkor"},
    "fin_exp_docs": {"origin": "legacy", "status": "void", "voidReason": "zz", "voidedAt": "2026-11-02 10:00:00+05"},
    "invoices": {"month": "2026-11"}, "payroll_runs": {"id": "2026-10", "status": "draft"},
    "fin_direct_log": {"grp": "payments", "op": "UPDATE", "via": "rest"}, "change_log": {"op": "UPDATE"},
    "fin_exp_class": {"month": "2026-11", "newArticle": "EX-32"}, "fin_exp_class_sign": {"month": "2026-11"}
  }'::jsonb;
begin
  v_ov := coalesce(ovr -> p_tbl, '{}'::jsonb);
  for col in select a.attname, format_type(a.atttypid, a.atttypmod) as typ, a.attnotnull, (ad.adbin is not null) as hasdef, a.attidentity, a.attgenerated
               from pg_attribute a left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
              where a.attrelid = v_oid and a.attnum > 0 and not a.attisdropped order by a.attnum loop
    continue when col.attgenerated <> '' or col.attidentity <> '';
    continue when not (v_ov ? col.attname) and (col.hasdef or not col.attnotnull) and col.attname not in ('id', 'path', 'token');
    continue when col.attname in ('id', 'path', 'token') and col.hasdef and not (v_ov ? col.attname);
    v_cols := v_cols || quote_ident(col.attname);
    v_vals := v_vals || case
      when col.attname in ('id', 'token') and not (v_ov ? col.attname) and (col.typ like 'text%' or col.typ like 'character varying%') then quote_literal(p_id)
      when v_ov ? col.attname then quote_literal(v_ov ->> col.attname) || '::' || col.typ
      when col.typ like 'text%' or col.typ like 'character varying%' then quote_literal('zz_' || p_tbl)
      when col.typ in ('integer', 'smallint', 'bigint') or col.typ like 'numeric%' or col.typ in ('double precision', 'real') then '1'
      when col.typ = 'boolean' then 'false'
      when col.typ = 'date' then quote_literal('2026-11-02')
      when col.typ like 'timestamp%' then 'now()'
      when col.typ in ('jsonb', 'json') then quote_literal('{}')
      when col.typ = 'uuid' then 'gen_random_uuid()'
      when col.typ like '%[]' then quote_literal('{}')
      else 'null' end;
  end loop;
  return case when cardinality(v_cols) = 0 then format('insert into public.%I default values', p_tbl)
              else format('insert into public.%I (%s) values (%s)', p_tbl, array_to_string(v_cols, ','), array_to_string(v_vals, ',')) end;
end $$;
create temp table zz_fill_fail (t text, err text) on commit drop;
do $f$
declare r record; v_n int;
begin
  for r in select tbl from zz.t where kind = 'r' order by tbl loop
    execute format('select count(*) from public.%I', r.tbl) into v_n;
    continue when v_n > 0;
    begin execute zz.row_sql(r.tbl, 'zz_seed_' || r.tbl); exception when others then insert into zz_fill_fail values (r.tbl, sqlstate || ' ' || left(sqlerrm, 120)); end;
  end loop;
end $f$;
set local session_replication_role = origin;

-- ---------- Matritsa ----------
create table zz.who (k text primary key, uid text, ord int);
insert into zz.who values ('dir','U_DIR',1), ('fm','U_FM',2), ('acc','U_ACC',3), ('kas','U_KAS',4), ('trs','U_TRS',5), ('hr','U_HR',6), ('zav','U_ZAV',7),
  ('mkt','U_MKT',8), ('rec','U_REC',9), ('tch','U_TCH',10), ('par','U_PAR',11), ('nur','U_NUR',12), ('sal','U_SAL',13), ('adm','U_ADM',14), ('anon',null,15);
create table zz.mx (tbl text, op text, who text, got text);
do $m$
declare t record; w record; v_ins text; v_ucol text; v_q text; r text;
begin
  for t in select tbl, kind from zz.t order by tbl loop
    v_ins := case when t.kind = 'r' then zz.row_sql(t.tbl, 'zz_mx_ins') end;
    -- U uchun ustun: noyob indeksga kirmaydigan birinchi matn ustun (generated / identity emas; bir nechta qatorga bir xil qiymat
    --   yozilganda noyoblik xatosi chiqmasin), bo'lmasa — birinchi matn ustun
    select a.attname into v_ucol from pg_attribute a
     where a.attrelid = ('public.' || quote_ident(t.tbl))::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = '' and a.attidentity = ''
       and format_type(a.atttypid, a.atttypmod) in ('text', 'character varying')
     order by exists (select 1 from pg_index i where i.indrelid = a.attrelid and i.indisunique and a.attnum = any(i.indkey)), a.attnum limit 1;
    for w in select k, uid from zz.who order by ord loop
      insert into zz.mx values (t.tbl, 'S', w.k, zz.probe(w.uid, format('select count(*)::text from public.%I', t.tbl), true));
      if t.kind = 'r' then
        insert into zz.mx values (t.tbl, 'I', w.k, zz.probe(w.uid, v_ins, false));
        insert into zz.mx values (t.tbl, 'U', w.k, case when v_ucol is null then 'E nocol' else
          zz.probe(w.uid, format($q$with u as (update public.%I set %I = 'zz_mx_upd' returning 1) select count(*)::text from u$q$, t.tbl, v_ucol), true) end);
        insert into zz.mx values (t.tbl, 'D', w.k, zz.probe(w.uid, format($q$with d as (delete from public.%I returning 1) select count(*)::text from d$q$, t.tbl), true));
      end if;
    end loop;
  end loop;
end $m$;
-- Katak: ruxsat — kamida bitta qator (I — xatosiz); rad — 0 qator yoki 42501; boshqa xato — «!sqlstate»
create or replace function zz.cell(p_op text, p_got text) returns text language sql immutable as $$
  select case when p_got ~ '^E 42501' then '-' when p_got ~ '^E ' then '!' || substr(p_got, 3)
              when p_op = 'I' then 'Y' when coalesce(nullif(p_got, ''), '0') ~ '^[0-9]+$' and p_got::bigint > 0 then 'Y' else '-' end $$;
create or replace function zz.row(p_tbl text) returns text language sql as $$
  select string_agg(o.op || '=' || coalesce((select string_agg(case when zz.cell(m.op, m.got) = 'Y' then m.who else m.who || zz.cell(m.op, m.got) end, ',' order by w.ord)
                                              from zz.mx m join zz.who w on w.k = m.who
                                             where m.tbl = p_tbl and m.op = o.op and zz.cell(m.op, m.got) <> '-'), '-'), ';' order by o.n)
    from (values (1, 'S'), (2, 'I'), (3, 'U'), (4, 'D')) o(n, op)
   where exists (select 1 from zz.mx m where m.tbl = p_tbl and m.op = o.op) $$;

-- ---------- Kutilgan matritsa ----------
create table zz.exp (tbl text primary key, e text);
-- Har jadval: S=…;I=…;U=…;D=… — ruxsat berilgan rollar (dir — Direktor, fm — moliya menejeri, acc — buxgalter, kas — kassir,
--   trs — g'aznachi, hr — HR, zav — O'IBDO', mkt — marketing, rec — qabulxona, tch — o'qituvchi, par — ota-ona (faqat o'z farzandi),
--   nur — hamshira, sal — sotuvchi, adm — ma'muriyat rahbari, anon — tizimga kirmagan); «-» — hech kim. Bir xil qatorli jadvallar birga.
--   Kassa jadvallari — faqat o'qish (yozish — kassa funksiyalari); doc_counters — hech kim (raqamni funksiyalar beradi); *_acc ko'rinishlari —
--   faqat buxgalter (F1.21). payments / invoices / student_credit / credit_ledger / expenses / staff_advances yozuvlari — RLS darajasi;
--   ustidan biznes triggerlari (pay_direct_guard, inv_paid_guard, F2.9 detektor / qulf …) — o'z sinovlarida.
insert into zz.exp values
  ('applied_payments', 'S=dir,fm,kas,trs;I=-;U=-;D=-'),
  ('cash_counts', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'), ('cash_day_events', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('cash_days', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'), ('cash_desks', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('cash_doc_fixes', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'), ('cash_doc_lines', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('cash_doc_verify', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'), ('cash_docs', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('cash_handovers', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'), ('cash_prints', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('fin_articles', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'), ('fin_category_map', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('fin_counterparties', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'), ('fin_exp_docs', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('fin_op_rules', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'), ('fin_org', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('fin_signatories', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'), ('gl_accounts', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('payment_allocations', 'S=dir,fm,acc,kas,trs;I=-;U=-;D=-'),
  ('cash_doc_files', 'S=dir,fm,acc;I=-;U=-;D=-'),
  ('change_log', 'S=dir;I=-;U=-;D=-'), ('fin_direct_log', 'S=dir;I=-;U=-;D=-'), ('fin_snapshots', 'S=dir;I=-;U=-;D=-'),
  ('fin_exp_class', 'S=dir,fm,acc;I=-;U=-;D=-'), ('fin_exp_class_sign', 'S=dir,fm,acc;I=-;U=-;D=-'),   -- F2.3: statiya tasnifi (faqat funksiya orqali yoziladi)
  ('credit_ledger', 'S=dir,fm,acc,kas,trs,zav,par;I=dir;U=-;D=-'),
  ('doc_counters', 'S=-;I=-;U=-;D=-'),
  ('expenses', 'S=dir,fm,acc,kas,trs,zav;I=dir,fm;U=dir,fm;D=dir,fm'),
  ('invoices', 'S=dir,fm,kas,trs,zav,rec,par;I=dir,fm;U=dir;D=dir'),
  ('invoices_acc', 'S=acc'), ('payments_acc', 'S=acc'), ('payroll_lines_acc', 'S=acc'), ('refunds_acc', 'S=acc'), ('salary_payments_acc', 'S=acc'),
  ('payments', 'S=dir,fm,kas,trs;I=dir;U=dir;D=-'),
  ('payroll_lines', 'S=dir,fm,kas,trs,hr;I=-;U=-;D=-'),
  ('payroll_runs', 'S=dir,fm,acc,kas,trs,hr;I=-;U=-;D=-'),
  ('refunds', 'S=dir,fm,kas,trs,zav;I=dir;U=-;D=-'),
  ('salary_payments', 'S=dir,fm,kas,trs,hr;I=dir,fm,kas,trs,hr;U=-;D=dir,fm,hr'),
  ('staff_advances', 'S=dir,fm,acc,kas,trs,hr;I=dir,fm;U=dir,fm;D=dir,fm'),
  ('student_credit', 'S=dir,fm,acc,kas,trs,zav,par;I=dir;U=dir;D=-');

create or replace function zz.nrows(p_tbl text) returns bigint language plpgsql as $$
declare n bigint; begin execute format('select count(*) from public.%I', p_tbl) into n; return n; end $$;
select zz.chk('M00 urug'': har jadvalda kamida bitta qator (to''ldirib bo''lmagani — ro''yxatda); kutilgan ro''yxatdagi har jadval bazada bor',
  coalesce((select string_agg(t || ': ' || err, '; ') from zz_fill_fail), '')
  || coalesce((select string_agg(t.tbl, ',') from zz.t t where t.kind = 'r' and zz.nrows(t.tbl) = 0), '')
  || coalesce((select string_agg('yo''q: ' || e.tbl, ',') from zz.exp e where not exists (select 1 from zz.t t where t.tbl = e.tbl)), ''), '^$');
select zz.chk('M' || lpad(row_number() over (order by t.tbl)::text, 2, '0') || ' ' || t.tbl, zz.row(t.tbl), '^' || coalesce(regexp_replace(e.e, '([.$|()\[\]*+?{}^\\])', '\\\1', 'g'), '<kutilgan yo''q>') || '$')
  from zz.t t left join zz.exp e on e.tbl = t.tbl order by t.tbl;

select zz.chk('Q1 tizimga kirmagan (anon): hech bir pul / kassa jadvali va ko''rinishini o''qiy olmaydi, yoza olmaydi',
  coalesce((select string_agg(m.tbl || '.' || m.op, ',' order by m.tbl, m.op) from zz.mx m where m.who = 'anon' and zz.cell(m.op, m.got) <> '-'), ''), '^$');
select zz.chk('Q2 RF-12 marketing: hech bir pul / kassa jadvali va ko''rinishi yo''q (xarajat — faqat yig''ma funksiya)',
  coalesce((select string_agg(m.tbl || '.' || m.op, ',' order by m.tbl, m.op) from zz.mx m where m.who = 'mkt' and zz.cell(m.op, m.got) <> '-'), ''), '^$');
select zz.chk('Q3 RF-11 g''aznachi = kassir: har jadval va amalda bir xil',
  coalesce((select string_agg(a.tbl || '.' || a.op, ',' order by a.tbl, a.op) from zz.mx a join zz.mx b on b.tbl = a.tbl and b.op = a.op
             where a.who = 'trs' and b.who = 'kas' and zz.cell(a.op, a.got) <> zz.cell(b.op, b.got)), ''), '^$');
select zz.chk('Q4 to''g''ridan-to''g''ri yozuv (INSERT / UPDATE / DELETE) faqat Direktor, moliya menejeri, kassir, g''aznachi va HR da (boshqa rollar — hech qayerda)',
  coalesce((select string_agg(m.who || ':' || m.tbl || '.' || m.op, ',' order by m.who, m.tbl, m.op) from zz.mx m
             where m.op in ('I', 'U', 'D') and m.who not in ('dir', 'fm', 'kas', 'trs', 'hr') and zz.cell(m.op, m.got) <> '-'), ''), '^$');
select zz.chk('Q5 ota-ona: fakturalar, avans va avans jurnalida faqat o''z farzandi (boshqa o''quvchi ko''rinmaydi)',
  zz.probe('U_PAR', $q$select string_agg(distinct "studentId", ',') from public.invoices$q$, true) || '|'
  || zz.probe('U_PAR', $q$select string_agg(distinct "studentId", ',') from public.student_credit$q$, true) || '|'
  || zz.probe('U_PAR', $q$select string_agg(distinct "studentId", ',') from public.credit_ledger$q$, true), '^IQ-M01\|IQ-M01\|IQ-M01$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
