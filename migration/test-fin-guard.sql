-- =====================================================================
-- test-fin-guard.sql — moliya ish rejasi 2-bosqichi, F2.9 «Huquqlar II» (reliz 26) sinovi: fin-guard.sql.
--   (F) bayroq: pul jadvallariga yozadigan barcha SECURITY DEFINER funksiyalarda iqror.fin_rpc — kutilgan ro'yxat (yangi pul funksiyasi
--       qo'shilsa shu yerda ko'rinadi), bayroqsiz yozuvchi yo'q, yangi funksiyalarda search_path ham;
--   (D) detektor (qulf o'chiq): sahifa (REST) yozuvlari jurnalga — to'lov qatori, faktura to'lov maydonlari (boshqa maydon emas, toza
--       yangi faktura emas, to'lanmagan fakturani o'chirish emas), avans va avans jurnali, hujjatsiz xarajat (oylik maosh hisobi qatori emas,
--       faqat updatedAt emas); pul funksiyalari, to'lov serverining RPC'lari (service_role — webhook), deploy va psql — jurnalsiz; to'lov
--       serverining to'lov qatori — istisno, fakturaga to'g'ridan-to'g'ri yozuvi — «server»; bayroqsiz definer funksiya — «rpc»;
--   (P) «🚫 Bekor» / «✓ Bajarildi» funksiyalari (fin_pay_cancel, fin_pay_rev_done): faqat Direktor, qoidalar, qayta bosish, kim — server;
--   (Q) qulf: yoqish sharti (detektor 7 kun, oxirgi 7 kunda 0 yozuv), faqat Direktor, yoqilganda — rad (fin:direct; jurnal yozilmaydi),
--       pul funksiyalari, to'lov serveri va oylik maosh qatori ishlaydi; o'chirish (orqaga qaytarish); o'zgarishlar tarixida;
--   (R) RF-11 g'aznachi = kassa operatori; (M) RF-12 marketing — faqat yig'ma; (C) avans jurnali — to'g'ridan-to'g'ri faqat Direktor;
--   (L) jurnal va yordamchi himoyasi; (K) fin_guard_report, kassa_checks «direct»; (X) «Qo'llash» — provider 'fix'.
--   Lokal sinov bazasida service_role RLS ni chetlab o'tmaydi (jonli bazada o'tadi) — server yozuvlari uchun shu tranzaksiyada
--   service_role uchun ochiq vaqtinchalik siyosatlar qo'yiladi (ROLLBACK bilan yo'qoladi).
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-fin-guard.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.payments) then
    raise exception 'test-fin-guard.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  if p_uid is null then execute 'set local role anon'; else execute 'set local role authenticated'; end if;
  begin
    execute p_q into r;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    r := 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
-- to'lov serveri (service_role REST): haqiqiy rol + JWT da'vosi
create or replace function zz.sr(p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
  begin
    execute p_q into r;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    r := 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
-- psql (texnik xizmat): rol postgres, JWT yo'q
create or replace function zz.try(p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  if p_q ~* '^\s*(select|with)\M' then execute p_q into r; else execute p_q; end if;
  return coalesce(r, 'OK');
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  return 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
end $$;
-- INSERT sinovi triggerlarsiz (faqat RLS qaror qiladi)
create or replace function zz.ins(p_uid text, p_q text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('session_replication_role', 'replica', true);
  r := zz.as(p_uid, p_q);
  perform set_config('session_replication_role', 'origin', true);
  return r;
end $$;
create or replace function zz.js(p text) returns jsonb language plpgsql as $$
begin return p::jsonb; exception when others then return null; end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
-- Holat o'qiydigan yordamchilar — plpgsql: bir ifodada oldinroq bajarilgan amalni ham ko'radi
create or replace function zz.log() returns text language plpgsql as $$
begin
  return coalesce((select string_agg(l.grp || ':' || l.tbl || ':' || l.op || ':' || l.row_id || ':' || l.via || ':' || array_to_string(l.cols, ','), ' ; ' order by l.id)
                     from public.fin_direct_log l), '-');
end $$;
create or replace function zz.nlog() returns bigint language plpgsql as $$ begin return (select count(*) from public.fin_direct_log); end $$;
create or replace function zz.chlog(p_tbl text, p_key text, p_uid text) returns bigint language plpgsql as $$
begin return (select count(*) from public.change_log c where c.tbl = p_tbl and c.changes ? p_key and c.actor_uid = p_uid); end $$;
create or replace function zz.reset() returns text language plpgsql as $$ begin delete from public.fin_direct_log; return ''; end $$;
create or replace function zz.pst(p_id text) returns text language plpgsql as $$ begin return (select coalesce(status, '<null>') from public.payments where id = p_id); end $$;
create or replace function zz.praw(p_id text, p_k text) returns text language plpgsql as $$ begin return (select coalesce(raw ->> p_k, '<null>') from public.payments where id = p_id); end $$;
create or replace function zz.inv(p_id text) returns text language plpgsql as $$
begin return (select trim_scale("paidAmount")::text || ':' || coalesce(status, '') || ':' || coalesce(provider, '') from public.invoices where id = p_id); end $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]'), ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'),
  ('U_TRS','g@x','Sinov G''aznachi','treasurer','active','[]'), ('U_MKT','m@x','Sinov Marketolog','marketing_mgr','active','[]'),
  ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.students (id, "studentId", name) values ('S1','S1','Sinov Bola'), ('S2','S2','Sinov Qiz'), ('S3','S3','Sinov O''g''il');
insert into public.invoices (id, "studentId", month, amount, status, "paidAmount") values
  ('S1__2027-02','S1','2027-02',500,'pending',0), ('S2__2027-02','S2','2027-02',300,'pending',0), ('S3__2027-02','S3','2027-02',800,'pending',0),
  ('S1__2027-01','S1','2027-01',400,'paid',400);
insert into public.payments (id, "studentId", provider, amount, status, raw, "createdAt") values
  ('zz-p1','S1','bank',100,'pending','{}', now()), ('zz-p2','S1','click',400,'applied','{}', now()),
  ('zz-p3','S1','uzum',200,'reversed','{"needsManualReverse":true}', now()), ('zz-p4','S1','click',50,'failed','{}', now()),
  ('zz-p5','S1','click',60,'pending','{}', now()), ('zz-p6','S1','uzum',70,'reversed','{}', now());
insert into public.student_credit (id, "studentId", credit) values ('S1','S1',0);
insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp1', 'supplier', 'Sinov Ta''minotchi', '300000001', true);
set local session_replication_role = origin;
-- xarajatlar triggerlar bilan (statiya, tur — sahifadagi kabi); psql (JWT yo'q) — detektor yozmaydi
insert into public.expenses (id, date, month, category, amount, note, method) values
  ('zz-e1','2027-01-10','2027-01','Marketing',1000,'Sinov','bank'), ('zz-e2','2027-01-11','2027-01','Reklama',500,'Sinov','bank'),
  ('zz-e3','2027-01-12','2027-01','Boshqa',700,'Sinov','bank'), ('zz-e4','2026-12-05',null,'Marketing',250,'Sinov','bank');
insert into public.expenses (id, date, month, category, amount, note) values ('payroll__2027-01','2027-01-01','2027-01','Maosh',9000,'Sinov');
select zz.clock('2027-02-01 10:00+05');   -- dushanba
-- lokal bazada service_role RLS ni chetlab o'tmaydi — server yozuvlari uchun vaqtinchalik ochiq siyosatlar (ROLLBACK)
create policy zz_sr on public.payments for all to service_role using (true) with check (true);
create policy zz_sr on public.invoices for all to service_role using (true) with check (true);
create policy zz_sr on public.student_credit for all to service_role using (true) with check (true);
create policy zz_sr on public.credit_ledger for all to service_role using (true) with check (true);
create policy zz_sr on public.expenses for all to service_role using (true) with check (true);
-- bayroqsiz definer funksiyalar (yangi yoki unutilgan pul funksiyasi o'rnida)
create or replace function zz.bad_inv(p_id text) returns text language plpgsql security definer set search_path = public, pg_temp as $$
begin update public.invoices set "paidAmount" = "paidAmount" + 1 where id = p_id; return 'ok'; end $$;
create or replace function zz.bad_pay(p_id text) returns text language plpgsql security definer set search_path = public, pg_temp as $$
begin update public.payments set raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('zz', coalesce((raw ->> 'zz')::int, 0) + 1) where id = p_id; return 'ok'; end $$;
grant usage on schema zz to authenticated, service_role;
grant execute on function zz.bad_inv(text), zz.bad_pay(text) to authenticated, service_role;
select zz.reset();

-- ---------- (F) bayroq ----------
select zz.chk('F1 bayroqli funksiyalar — kutilgan ro''yxat (28: pul jadvallariga yozadigan barcha definer funksiyalar + 2 yangi)',
  (select string_agg(n.nspname || '.' || p.proname || '(' || oidvectortypes(p.proargtypes) || ')', ';' order by n.nspname, p.proname, oidvectortypes(p.proargtypes))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'iqror.fin_rpc=1')),
  '^' || regexp_replace('app.fin_exp_legacy_void(expenses, text, text, text);app.kassa_adv_approve(text, text);app.kassa_link_paid(text, text);'
    || 'app.kassa_link_void(text, text, text);app.kassa_tuition_post(text, numeric, text, timestamp with time zone, jsonb, jsonb, boolean);'
    || 'app.reprice_invoice_core(text, numeric, jsonb, boolean);app.tuition_reverse_core(text, text, text);public.add_credit(text, numeric, text, text, text);'
    || 'public.adjust_credit(text, numeric, text, text);public.apply_payment(text, numeric, text, text);public.apply_to_invoice(text, numeric, text, text);'
    || 'public.assign_payment(text, text);public.cancel_invoice(text);public.delete_unpaid_invoice(text);public.fin_exp_save(jsonb);public.fin_exp_void(text, text);'
    || 'public.fin_pay_cancel(text);public.fin_pay_rev_done(text);public.fin_refund_credit(jsonb);public.kassa_adv_report_void(text, text);'
    || 'public.kassa_fix_decide(text, boolean, text);public.kassa_offset(jsonb);public.reattribute_avans(text, text, numeric, text, text);'
    || 'public.record_manual_payment(text, text, numeric, text, text, text, text, text, timestamp with time zone, jsonb);'
    || 'public.refund_invoice(text, text, numeric, text, boolean, text, text);public.reverse_payment(text, numeric, text, text);public.sick_note_refund(text);'
    || 'public.split_payment(text, text, jsonb)', '([().$])', '\\\1', 'g') || '$');
select zz.chk('F2 pul jadvallariga yozadigan bayroqsiz SECURITY DEFINER funksiya yo''q (zz sinov funksiyalaridan tashqari)',
  coalesce((select string_agg(p.oid::regprocedure::text, ',') from pg_proc p
             where p.pronamespace in ('public'::regnamespace, 'app'::regnamespace) and p.prosecdef and p.prokind = 'f'
               and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(only\s+)?(public\.)?"?(payments|invoices|student_credit|credit_ledger|expenses)\M'
               and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'iqror.fin_rpc=1')), '-'),
  '^-$');
select zz.chk('F3 yangi funksiyalar: search_path bilan; detektor triggeri SECURITY INVOKER; yordamchi — definer',
  (select string_agg(p.proname || '=' || p.prosecdef::text || ':' || coalesce((select c from unnest(p.proconfig) c where c like 'search_path=%'), 'yo''q'), ',' order by p.proname)
     from pg_proc p where p.pronamespace in ('public'::regnamespace, 'app'::regnamespace)
      and p.proname in ('fin_direct_detect', 'fin_direct_note', 'fin_guard_report', 'fin_marketing_spend', 'fin_pay_cancel', 'fin_pay_rev_done')),
  '^fin_direct_detect=false:search_path=public, app, pg_temp,fin_direct_note=true:search_path=public, app, pg_temp,fin_guard_report=true:search_path=public, app, pg_temp,fin_marketing_spend=true:search_path=public, app, pg_temp,fin_pay_cancel=true:search_path=public, app, pg_temp,fin_pay_rev_done=true:search_path=public, app, pg_temp$');
select zz.chk('F4 detektor triggeri besh jadvalda (AFTER ROW, yoqiq)',
  (select string_agg(c.relname || ':' || t.tgenabled::text, ',' order by c.relname) from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where t.tgname = 'trg_fin_direct' and not t.tgisinternal),
  '^credit_ledger:O,expenses:O,invoices:O,payments:O,student_credit:O$');
select zz.chk('F5 detektor o''rnatilgan kun saqlangan (guardSince), qulf o''chiq',
  (select (o.extra ? 'guardSince')::text || ':' || coalesce(o.extra ->> 'directGuard', '-') from public.fin_org o where o.id = 'main'), '^true:-$');

-- ---------- (D) detektor — qulf o'chiq ----------
select zz.chk('D1 Direktor sahifadan (REST) qo''llanmagan to''lov yozuvini bekor qildi — o''tdi, jurnalda: payments / rest / status',
  zz.as('U_DIR', $q$with u as (update public.payments set status = 'canceled' where id = 'zz-p4' returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.log(),
  '^1 \| payments:payments:UPDATE:zz-p4:rest:status(,statusAt)?$');
select zz.chk('D2 jurnal qatori: API roli, kim (uid va rol), vaqt',
  (select l.api_role || ':' || coalesce(l.actor_uid, '-') || ':' || coalesce(l.actor_role, '-') || ':' || (l.at is not null)::text from public.fin_direct_log l),
  '^authenticated:U_DIR:director:true$');
select zz.reset();
select zz.chk('D3 faktura: to''lov maydonlari (paidAmount, status) — jurnalda; boshqa maydon (izoh) — yo''q',
  zz.as('U_DIR', $q$with u as (update public.invoices set "discountInfo" = 'Sinov izoh' where id = 'S1__2027-02' returning 1) select count(*)::text from u$q$)
  || ':' || zz.nlog() || ' | '
  || zz.as('U_DIR', $q$with u as (update public.invoices set "paidAmount" = 100, status = 'partial' where id = 'S1__2027-02' returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.log(),
  '^1:0 \| 1 \| invoices:invoices:UPDATE:S1__2027-02:rest:paidAmount,status$');
select zz.reset();
select zz.chk('D4 yangi faktura: to''lanmagan va sababli 0 so''mlik «to''langan» (grant) — jurnalsiz; to''lov bilan yaratilgani — jurnalda',
  zz.as('U_DIR', $q$with u as (insert into public.invoices (id, "studentId", month, amount, status, "paidAmount") values ('S2__2027-03', 'S2', '2027-03', 300, 'pending', 0) returning 1) select count(*)::text from u$q$)
  || zz.as('U_DIR', $q$with u as (insert into public.invoices (id, "studentId", month, amount, status, "paidAmount", "isGrant", "paidAt") values ('S3__2027-03', 'S3', '2027-03', 0, 'paid', 0, true, now()) returning 1) select count(*)::text from u$q$)
  || ':' || zz.nlog() || ' | '
  || zz.as('U_DIR', $q$with u as (insert into public.invoices (id, "studentId", month, amount, status, "paidAmount", "paidAt") values ('S1__2027-03', 'S1', '2027-03', 500, 'paid', 500, now()) returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.log(),
  '^11:0 \| 1 \| invoices:invoices:INSERT:S1__2027-03:rest:paidAmount,status,paidAt$');
select zz.reset();
select zz.chk('D5 faktura o''chirish: to''lanmagan — jurnalsiz; to''lov holati bor — jurnalda',
  zz.as('U_DIR', $q$with d as (delete from public.invoices where id = 'S2__2027-03' returning 1) select count(*)::text from d$q$) || ':' || zz.nlog() || ' | '
  || zz.as('U_DIR', $q$with d as (delete from public.invoices where id = 'S1__2027-03' returning 1) select count(*)::text from d$q$) || ' | ' || zz.log(),
  '^1:0 \| 1 \| invoices:invoices:DELETE:S1__2027-03:rest:paidAmount,status$');
select zz.reset();
select zz.chk('D6 avans (student_credit) — jurnalda (Direktor REST)',
  zz.as('U_DIR', $q$with u as (update public.student_credit set credit = 5 where id = 'S1' returning 1) select count(*)::text from u$q$) || ' | ' || zz.log(),
  '^1 \| credit:student_credit:UPDATE:S1:rest:credit');
select zz.reset();
select zz.chk('D7 hujjatsiz xarajat — jurnalda (qo''shish, o''zgartirish, o''chirish); oylik maosh hisobi qatori va faqat updatedAt — jurnalsiz',
  zz.as('U_FM', $q$with u as (insert into public.expenses (id, date, month, category, amount, method) values ('zz-e9', '2027-02-01', '2027-02', 'Boshqa', 10, 'bank') returning 1) select count(*)::text from u$q$)
  || zz.as('U_FM', $q$with u as (update public.expenses set amount = 11 where id = 'zz-e9' returning 1) select count(*)::text from u$q$)
  || zz.as('U_DIR', $q$with d as (delete from public.expenses where id = 'zz-e9' returning 1) select count(*)::text from d$q$)
  || zz.as('U_FM', $q$with u as (insert into public.expenses (id, date, month, category, amount, method) values ('payroll__2027-02', '2027-02-01', '2027-02', 'Maosh', 9100, null) on conflict (id) do update set amount = excluded.amount returning 1) select count(*)::text from u$q$)
  || zz.as('U_FM', $q$with u as (update public.expenses set "updatedAt" = now() where id = 'zz-e3' returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.log(),
  '^11111 \| expenses:expenses:INSERT:zz-e9:rest: ; expenses:expenses:UPDATE:zz-e9:rest:amount ; expenses:expenses:DELETE:zz-e9:rest:$');
select zz.reset();
select zz.chk('D8 pul funksiyalari (bayroqli) — jurnalsiz: qo''lda to''lov, «Bekor» va «✓ Bajarildi» funksiyalari, avansni tuzatish, xarajat hujjati',
  zz.as('U_FM', $q$select (public.record_manual_payment('man_zz_m1', 'S2', 300, 'bank', '2027-02-01', 'Sinov', '', 'Sinov Ota', null, null) ->> 'ok')$q$)
  || zz.as('U_DIR', $q$select (public.fin_pay_cancel('zz-p5') ->> 'ok')$q$)
  || zz.as('U_DIR', $q$select (public.fin_pay_rev_done('zz-p3') ->> 'ok')$q$)
  || zz.as('U_DIR', $q$select (public.adjust_credit('S1', 7, 'Sinov', 'zz-adj-1') ->> 'ok')$q$)
  || zz.as('U_FM', $q$select (public.fin_exp_save('{"clientRef":"zz-d8-0001","method":"bank","date":"2027-01-08","counterpartyId":"cp1","docNo":"1","lines":[{"articleId":"EX-11","amount":100}]}') ? 'id')::text$q$)
  || ' | ' || zz.nlog(),
  '^truetruetruetruetrue \| 0$');
select zz.chk('D9 to''lov serveri (service_role): to''lov qatorini o''zi yozadi — istisno; webhook RPC''lari (apply_payment, apply_to_invoice, reverse_payment) — jurnalsiz',
  zz.sr($q$with u as (insert into public.payments (id, provider, amount, status, click_trans_id) values ('click_zz1', 'click', 800, 'prepared', 'zz1') returning 1) select count(*)::text from u$q$)
  || zz.sr($q$with u as (update public.payments set status = 'applied', "studentId" = 'S3', matched = true where id = 'click_zz1' returning 1) select count(*)::text from u$q$)
  || ':' || coalesce(zz.sr($q$select public.apply_to_invoice('S3__2027-02', 800, 'click', 'click_zz1') ->> 'status'$q$), '<null>')
  || ':' || coalesce(zz.sr($q$select (public.apply_payment('S3', 0, 'credit', null) ->> 'ok')$q$), '<null>')
  || ':' || coalesce(zz.sr($q$select (public.reverse_payment('S3__2027-02', 100, 'click', 'click_zz1-r') ->> 'ok')$q$), '<null>')
  || ' | ' || zz.inv('S3__2027-02') || ' | ' || zz.nlog(),
  '^11:paid:true:true \| 700:partial:click \| 0$');
select zz.chk('D10 to''lov serverining fakturaga va avansga to''g''ridan-to''g''ri yozuvi — jurnalda («server»; RF-10: service_role ham)',
  zz.sr($q$with u as (update public.invoices set "paidAmount" = 800, status = 'paid' where id = 'S3__2027-02' returning 1) select count(*)::text from u$q$)
  || zz.sr($q$with u as (update public.student_credit set credit = 9 where id = 'S1' returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.log(),
  '^11 \| invoices:invoices:UPDATE:S3__2027-02:server:paidAmount,status ; credit:student_credit:UPDATE:S1:server:credit');
select zz.reset();
select zz.chk('D11 bayroqsiz definer funksiya API so''rovida — «rpc» (faktura ham, to''lov qatori ham); psql (JWT yo''q) — jurnalsiz',
  zz.as('U_DIR', $q$select zz.bad_inv('S2__2027-02')$q$) || zz.as('U_DIR', $q$select zz.bad_pay('zz-p1')$q$) || zz.sr($q$select zz.bad_pay('zz-p1')$q$)
  || ':' || zz.try($q$select zz.bad_inv('S2__2027-02')$q$) || ' | ' || zz.log(),
  '^okokok:ok \| invoices:invoices:UPDATE:S2__2027-02:rpc:paidAmount ; payments:payments:UPDATE:zz-p1:rpc:raw ; payments:payments:UPDATE:zz-p1:rpc:raw$');
select zz.reset();
select zz.chk('D12 deploy (iqror.migrating) — jurnalsiz',
  (select set_config('iqror.migrating', '1', true)) || zz.as('U_DIR', $q$with u as (update public.invoices set "paidAmount" = 0, status = 'pending' where id = 'S2__2027-02' returning 1) select count(*)::text from u$q$)
  || (select set_config('iqror.migrating', '', true)) || ':' || zz.nlog(),
  '^11:0$');

-- ---------- (P) «🚫 Bekor» va «✓ Bajarildi» funksiyalari ----------
select zz.chk('P1 «Bekor»: Direktor — qo''llanmagan yozuv bekor, kim va qachon raw da (server qo''ydi); qayta bosish — dup',
  zz.as('U_DIR', $q$select public.fin_pay_cancel('zz-p1')::text$q$) || ' | ' || zz.pst('zz-p1') || ':' || zz.praw('zz-p1', 'canceledBy')
  || ':' || (zz.praw('zz-p1', 'canceledAt') <> '<null>')::text || ' | ' || zz.as('U_DIR', $q$select public.fin_pay_cancel('zz-p1')::text$q$),
  '^\{"ok": true\} \| canceled:U_DIR:true \| \{"ok": true, "dup": true\}$');
select zz.chk('P2 «Bekor»: qo''llangan / qaytarilgan to''lov — rad (pay:applied); topilmadi — pay:not_found; holat o''zgarmaydi',
  zz.as('U_DIR', $q$select public.fin_pay_cancel('zz-p2')::text$q$) || ' | ' || zz.as('U_DIR', $q$select public.fin_pay_cancel('zz-p6')::text$q$)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_pay_cancel('zz-yoq')::text$q$) || ' | ' || zz.pst('zz-p2') || ':' || zz.pst('zz-p6'),
  '^ERR 42501 \[pay:applied\].* \| ERR 42501 \[pay:applied\].* \| ERR 22023 \[pay:not_found\].* \| applied:reversed$');
select zz.chk('P3 «Bekor»: Direktordan boshqasi (moliya menejeri, kassir, g''aznachi) — rad',
  zz.as('U_FM', $q$select public.fin_pay_cancel('zz-p4')::text$q$) || ' | ' || zz.as('U_KAS', $q$select public.fin_pay_cancel('zz-p4')::text$q$)
  || ' | ' || zz.as('U_TRS', $q$select public.fin_pay_cancel('zz-p4')::text$q$),
  '^ERR 42501 \[\] Ruxsat yo''q.* \| ERR 42501 \[\] Ruxsat.* \| ERR 42501 \[\] Ruxsat');
select zz.chk('P4 «✓ Bajarildi»: ro''yxatdagi to''lov — belgilandi (kim — uid, server qo''ydi; avvalgi raw saqlandi), qayta — dup; ro''yxatda emas — rad; boshqa rol — rad',
  zz.praw('zz-p3', 'manualReverseDone') || ':' || zz.praw('zz-p3', 'manualReverseBy') || ':' || zz.praw('zz-p3', 'needsManualReverse')
  || ' | ' || zz.as('U_DIR', $q$select public.fin_pay_rev_done('zz-p3')::text$q$)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_pay_rev_done('zz-p6')::text$q$)
  || ' | ' || zz.as('U_FM', $q$select public.fin_pay_rev_done('zz-p3')::text$q$),
  '^true:U_DIR:true \| \{"ok": true, "dup": true\} \| ERR 22023 \[pay:not_manual\].* \| ERR 42501 \[\] Ruxsat');

-- ---------- (Q) qulf ----------
select zz.chk('Q1 yoqish: detektor 7 kundan kam ishlagan — rad (fin:guard_young), qulf o''chiq qoladi',
  zz.try($q$update public.fin_org set extra = extra || jsonb_build_object('guardSince', app.fin_today() - 6) where id = 'main'$q$)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"directGuard":true}')::text$q$) || ' | ' || (select coalesce(extra ->> 'directGuard', '-') from public.fin_org where id = 'main'),
  '^OK \| ERR P0001 \[fin:guard_young\].*kamida 7 kun.* \| -$');
select zz.chk('Q2 yoqish: oxirgi 7 kunda to''g''ridan-to''g''ri yozuv bor — rad (fin:guard_dirty, soni bilan)',
  zz.try($q$update public.fin_org set extra = extra || jsonb_build_object('guardSince', app.fin_today() - 7) where id = 'main'$q$)
  || ' | ' || zz.as('U_DIR', $q$with u as (update public.payments set raw = raw || '{"q2":1}' where id = 'zz-p4' returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.as('U_DIR', $q$select public.fin_org_set('{"directGuard":true}')::text$q$),
  '^OK \| 1 \| ERR P0001 \[fin:guard_dirty\].*: 1 ta');
select zz.chk('Q3 7 kundan eski yozuv xalaqit bermaydi; Moliya menejeri yoqa olmaydi; Direktor yoqdi — o''zgarishlar tarixida (fin_org.extra)',
  zz.try($q$update public.fin_direct_log set at = now() - interval '8 days'$q$)
  || ' | ' || zz.as('U_FM', $q$select public.fin_org_set('{"directGuard":true}')::text$q$)
  || ' | ' || coalesce(zz.js(zz.as('U_DIR', $q$select public.fin_org_set('{"directGuard":true}')::text$q$)) #>> '{extra,directGuard}', 'ERR')
  || ' | ' || zz.chlog('fin_org', 'extra', 'U_DIR'),
  '^OK \| ERR 42501 .*faqat Direktor \| true \| [1-9]');
select zz.reset();
select zz.chk('Q4 qulf yoqiq: sahifadan to''lov qatori, faktura to''lov maydoni, avans, hujjatsiz xarajat — rad (fin:direct), o''zgarmadi, jurnal bo''sh',
  zz.as('U_DIR', $q$with u as (update public.payments set raw = raw || '{"q4":1}' where id = 'zz-p4' returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.as('U_DIR', $q$with u as (update public.invoices set "paidAmount" = 1 where id = 'S2__2027-02' returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.as('U_DIR', $q$with u as (update public.student_credit set credit = 1 where id = 'S1' returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.as('U_FM', $q$with u as (insert into public.expenses (id, date, month, category, amount, method) values ('zz-e8', '2027-02-01', '2027-02', 'Boshqa', 10, 'bank') returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.praw('zz-p4', 'q4') || ':' || zz.inv('S2__2027-02') || ':' || zz.nlog(),
  '^ERR 42501 \[fin:direct\] To''lov yozuvini faqat.* \| ERR 42501 \[fin:direct\] Hisob-fakturaning.* \| ERR 42501 \[fin:direct\] Avans.* \| ERR 42501 \[fin:direct\] Xarajat faqat.* \| <null>:0:pending:.*:0$');
select zz.chk('Q5 qulf yoqiq: faktura boshqa maydoni, toza yangi faktura, oylik maosh qatori — o''tadi',
  zz.as('U_DIR', $q$with u as (update public.invoices set "discountInfo" = 'Q5' where id = 'S2__2027-02' returning 1) select count(*)::text from u$q$)
  || zz.as('U_DIR', $q$with u as (insert into public.invoices (id, "studentId", month, amount, status, "paidAmount") values ('S2__2027-04', 'S2', '2027-04', 300, 'pending', 0) returning 1) select count(*)::text from u$q$)
  || zz.as('U_FM', $q$with u as (update public.expenses set amount = 9200 where id = 'payroll__2027-02' returning 1) select count(*)::text from u$q$),
  '^111$');
select zz.chk('Q6 qulf yoqiq: pul funksiyalari (qo''lda to''lov, «Bekor»), to''lov serveri (to''lov qatori va webhook RPC) — ishlaydi',
  zz.as('U_FM', $q$select (public.record_manual_payment('man_zz_m2', 'S2', 100, 'bank', '2027-02-01', 'Sinov', '', 'Sinov Ota', null, null) ->> 'ok')$q$)
  || zz.as('U_DIR', $q$select (public.fin_pay_cancel('zz-p4') ->> 'ok')$q$)
  || zz.sr($q$with u as (insert into public.payments (id, provider, amount, status, click_trans_id) values ('click_zz2', 'click', 50, 'prepared', 'zz2') returning 1) select (count(*) = 1)::text from u$q$)
  || zz.sr($q$select (public.apply_payment('S2', 50, 'click', 'click_zz2') ->> 'ok')$q$),
  '^truetruetruetrue$');
select zz.chk('Q7 qulf yoqiq: to''lov serverining fakturaga to''g''ridan-to''g''ri yozuvi va bayroqsiz definer funksiya — rad',
  zz.sr($q$with u as (update public.invoices set "paidAmount" = 5 where id = 'S2__2027-04' returning 1) select count(*)::text from u$q$)
  || ' | ' || zz.as('U_DIR', $q$select zz.bad_inv('S2__2027-04')$q$),
  '^ERR 42501 \[fin:direct\].* \| ERR 42501 \[fin:direct\]');
select zz.chk('Q8 orqaga qaytarish: Direktor qulfni o''chirdi — sahifa yozuvi yana o''tadi va jurnalga tushadi',
  coalesce(zz.js(zz.as('U_DIR', $q$select public.fin_org_set('{"directGuard":false}')::text$q$)) #>> '{extra,directGuard}', 'ERR')
  || ' | ' || zz.as('U_DIR', $q$with u as (update public.student_credit set credit = 2 where id = 'S1' returning 1) select count(*)::text from u$q$) || ':' || zz.nlog(),
  '^false \| 1:1$');
select zz.chk('Q9 sozlama turi: directGuard — faqat true / false',
  zz.as('U_DIR', $q$select public.fin_org_set('{"directGuard":"ha"}')::text$q$), '^ERR 22023 .*directGuard');

-- ---------- (R) RF-11 g'aznachi = kassa operatori ----------
select zz.chk('R1 g''aznachi: moliya emas, kassir (kassa operatori, kassa hujjatlarini ko''radi); moliya menejeri — moliya, kassir emas',
  zz.as('U_TRS', $q$select app.is_finance()::text || ':' || app.is_cashier()::text || ':' || app.kassa_operator()::text || ':' || app.kassa_reader()::text$q$)
  || ' | ' || zz.as('U_FM', $q$select app.is_finance()::text || ':' || app.is_cashier()::text || ':' || app.kassa_operator()::text$q$),
  '^false:true:true:true \| true:false:false$');
select zz.chk('R2 g''aznachi: to''lovlar, fakturalar, avansni ko''radi (kassir kabi); qo''lda to''lov qabul qiladi',
  zz.as('U_TRS', $q$select (select count(*) from public.payments)::text || ':' || (select count(*) from public.invoices)::text || ':' || (select count(*) from public.student_credit)::text$q$)
  || ' | ' || zz.as('U_TRS', $q$select (public.record_manual_payment('man_zz_m3', 'S2', 10, 'bank', '2027-02-01', 'Sinov', '', 'Sinov Ota', null, null) ->> 'ok')$q$),
  '^[1-9][0-9]*:[1-9][0-9]*:[1-9][0-9]* \| true$');
select zz.chk('R3 g''aznachi: moliya menejeri huquqlari yo''q — avans qo''shish, fakturani bekor qilish, xarajat hujjati, faktura yaratish (RLS)',
  zz.as('U_TRS', $q$select public.add_credit('S1', 10, 'manual', 'Sinov', 'zz-r3')::text$q$)
  || ' | ' || zz.as('U_TRS', $q$select public.cancel_invoice('S2__2027-04')::text$q$)
  || ' | ' || zz.as('U_TRS', $q$select public.fin_exp_save('{"clientRef":"zz-r3-0001","method":"bank","date":"2027-02-01","lines":[{"articleId":"OP-17","amount":10}]}')::text$q$)
  || ' | ' || zz.ins('U_TRS', $q$insert into public.invoices (id, "studentId", month, amount, status) values ('S2__2027-05', 'S2', '2027-05', 1, 'pending') returning id$q$),
  '^ERR 42501 .* \| ERR 42501 .* \| ERR 42501 .* \| ERR 42501 .*row-level security');

-- ---------- (M) RF-12 marketing — faqat yig'ma ----------
select zz.chk('M1 marketing: «Marketing» / «Reklama» xarajati oylar bo''yicha (sana bo''yicha oy ham); boshqa toifa va maosh — kirmaydi',
  coalesce(zz.js(zz.as('U_MKT', $q$select public.fin_marketing_spend()::text$q$))::text, 'ERR'),
  '^\{"2026-12": 250, "2027-01": 1500\}$');
select zz.chk('M2 marketing «Buxgalteriya» qatorlarini (expenses) o''qimaydi; Direktor va moliya menejeri o''qiydi',
  zz.as('U_MKT', $q$select count(*)::text from public.expenses$q$) || ':' || (zz.as('U_DIR', $q$select count(*)::text from public.expenses$q$)::int > 0)::text
  || ':' || (zz.as('U_FM', $q$select count(*)::text from public.expenses$q$)::int > 0)::text,
  '^0:true:true$');
select zz.chk('M3 yig''ma: Direktor — ha; moliya menejeri, o''qituvchi, anon — rad',
  (zz.js(zz.as('U_DIR', $q$select public.fin_marketing_spend()::text$q$)) ? '2027-01')::text
  || ' | ' || zz.as('U_FM', $q$select public.fin_marketing_spend()::text$q$) || ' | ' || zz.as('U_TCH', $q$select public.fin_marketing_spend()::text$q$)
  || ' | ' || zz.as(null, $q$select public.fin_marketing_spend()::text$q$),
  '^true \| ERR 42501 .* \| ERR 42501 .* \| ERR 42501 .*permission denied');

-- ---------- (C) avans jurnali ----------
select zz.chk('C1 avans jurnaliga to''g''ridan-to''g''ri qo''shish: moliya menejeri, kassir — RLS rad; Direktor — RLS o''tadi',
  zz.ins('U_FM', $q$insert into public.credit_ledger (id, "studentId", delta, "balanceAfter", reason) values ('zz-c1', 'S1', 1, 1, 'manual') returning id$q$)
  || ' | ' || zz.ins('U_KAS', $q$insert into public.credit_ledger (id, "studentId", delta, "balanceAfter", reason) values ('zz-c2', 'S1', 1, 1, 'manual') returning id$q$)
  || ' | ' || zz.ins('U_DIR', $q$insert into public.credit_ledger (id, "studentId", delta, "balanceAfter", reason) values ('zz-c3', 'S1', 1, 1, 'manual') returning id$q$),
  '^ERR 42501 .*row-level security.* \| ERR 42501 .*row-level security.* \| zz-c3$');

-- ---------- (L) jurnal va yordamchi himoyasi ----------
select zz.chk('L1 jurnalni faqat Direktor o''qiydi; moliya menejeri, buxgalter, kassir — 0 qator; anon — rad',
  (zz.as('U_DIR', $q$select count(*)::text from public.fin_direct_log$q$)::int > 0)::text
  || ':' || zz.as('U_FM', $q$select count(*)::text from public.fin_direct_log$q$) || ':' || zz.as('U_ACC', $q$select count(*)::text from public.fin_direct_log$q$)
  || ':' || zz.as('U_KAS', $q$select count(*)::text from public.fin_direct_log$q$) || ' | ' || zz.as(null, $q$select count(*)::text from public.fin_direct_log$q$),
  '^true:0:0:0 \| ERR 42501 .*permission denied');
select zz.chk('L2 jurnalga mijoz yoza / o''chira olmaydi (Direktor ham)',
  zz.as('U_DIR', $q$insert into public.fin_direct_log (grp, tbl, op, via) values ('payments', 'payments', 'INSERT', 'rest') returning id::text$q$)
  || ' | ' || zz.as('U_DIR', $q$with d as (delete from public.fin_direct_log returning 1) select count(*)::text from d$q$)
  || ' | ' || zz.as('U_DIR', $q$with u as (update public.fin_direct_log set grp = 'credit' returning 1) select count(*)::text from u$q$),
  '^ERR 42501 .*permission denied.* \| ERR 42501 .*permission denied.* \| ERR 42501 .*permission denied');
select zz.chk('L3 yordamchi (app.fin_direct_note) triggerdan tashqarida chaqirilmaydi',
  zz.try($q$select app.fin_direct_note('payments', 'payments', 'UPDATE', 'x', 'rest', '{}')::text$q$)
  || ' | ' || zz.as('U_DIR', $q$select app.fin_direct_note('payments', 'payments', 'UPDATE', 'x', 'rest', '{}')::text$q$),
  '^ERR 42501 .*faqat detektor.* \| ERR 42501 .*faqat detektor');

-- ---------- (K) hisobot va nazorat ro'yxati ----------
select zz.chk('K1 fin_guard_report: Direktor — rejim, kun, 7 kunlik son, guruhlar, oxirgi yozuvlar (kim bilan); boshqa rollar — rad',
  coalesce((select x ->> 'mode' || ':' || (x ->> 'n7') || ':' || jsonb_array_length(x -> 'groups') || ':' || (x #>> '{groups,2,grp}') || ':'
                   || (x #>> '{recent,0,tbl}') || ':' || (x #>> '{recent,0,actorName}') || ':' || (x ->> 'canEnforce')
              from zz.js(zz.as('U_DIR', $q$select public.fin_guard_report(30)::text$q$)) x), 'ERR')
  || ' | ' || zz.as('U_FM', $q$select public.fin_guard_report()::text$q$) || ' | ' || zz.as('U_ACC', $q$select public.fin_guard_report()::text$q$),
  '^detect:1:4:credit:student_credit:Sinov Direktor:false \| ERR 42501 .* \| ERR 42501 ');
select zz.chk('K2 kassa_checks «direct»: Direktorga — rejim, 7 kunlik son va yopish mumkinligi (yozuv bor — yo''q); moliya menejeri va buxgalterga — yo''q',
  coalesce((select (x #>> '{direct,mode}') || '/' || (x #>> '{direct,n7}') || '/' || (x #>> '{direct,canEnforce}')
              from zz.js(zz.as('U_DIR', $q$select public.kassa_checks('main')::text$q$)) x), 'ERR')
  || ':' || coalesce(zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) ->> 'direct', 'null')
  || ':' || coalesce(zz.js(zz.as('U_ACC', $q$select public.kassa_checks('main')::text$q$)) ->> 'direct', 'null'),
  '^detect/1/false:null:null$');
select zz.chk('K3 qulf yoqish mumkinligi (canEnforce): 7 kun toza — true (hisobot va nazorat ro''yxati); detektor 6 kun ishlagan — false',
  zz.reset() || coalesce(zz.js(zz.as('U_DIR', $q$select public.fin_guard_report()::text$q$)) ->> 'canEnforce', 'ERR')
  || ':' || coalesce(zz.js(zz.as('U_DIR', $q$select public.kassa_checks('main')::text$q$)) #>> '{direct,canEnforce}', 'ERR')
  || ' | ' || zz.try($q$update public.fin_org set extra = extra || jsonb_build_object('guardSince', app.fin_today() - 6) where id = 'main'$q$)
  || ':' || coalesce(zz.js(zz.as('U_DIR', $q$select public.fin_guard_report()::text$q$)) ->> 'canEnforce', 'ERR')
  || ':' || coalesce(zz.js(zz.as('U_DIR', $q$select public.kassa_checks('main')::text$q$)) #>> '{direct,canEnforce}', 'ERR')
  || ' | ' || zz.try($q$update public.fin_org set extra = extra || jsonb_build_object('guardSince', app.fin_today() - 7) where id = 'main'$q$),
  '^true:true \| OK:false:false \| OK$');

-- ---------- (X) «Qo'llash» — provider 'fix' (naqd emas) ----------
select zz.chk('X1 Direktorning «Qo''llash»i provider ''fix'' bilan: fakturaga qo''llandi, kanal — fix (naqd emas), jurnalsiz',
  coalesce(zz.as('U_DIR', $q$select (public.apply_payment('S1', 400, 'fix', 'fix_S1_400_400') ->> 'ok')$q$), '<null>')
  || ' | ' || zz.inv('S1__2027-02') || ':' || zz.nlog(),
  '^true \| 500:paid:fix:0$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
