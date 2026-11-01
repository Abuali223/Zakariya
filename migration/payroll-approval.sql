\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: payroll-approval.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- payroll-approval.sql — MAOSH VEDOMOSTI: Moliya menejeri tayyorlaydi → HR menejer tasdiqlaydi → shundan keyin to'lanadi (D2).
--   * payroll_runs (id = 'YYYY-MM'; draft | submitted | approved | returned) + payroll_lines (har xodim: maosh, ushlanma,
--     o'rinbosarlik, avans, oldingi qoldiq, to'lanadigan). Yozish FAQAT shu fayldagi RPC'lar orqali.
--   * payroll_submit — Moliya menejeri (yoki Direktor); payroll_decide — HR menejer (HR bo'lmasa Direktor), tayyorlagan odam
--     o'zi tasdiqlay olmaydi, qaytarish — izoh bilan; payroll_approve_line — HR / Moliya menejerining O'Z maoshi Direktor
--     tasdig'i bilan (hech kim o'zini o'zi tasdiqlamaydi); payroll_reopen — Direktor (sabab bilan).
--   * O'tish oyi config/finance."payrollApprovalFrom": shu oydan boshlab maosh berish (salary_payments) faqat tasdiqlangan
--     vedomostdagi xodimga va tasdiqlangan summadan oshmasdan. Undan oldingi oylar — eski tartib.
--   * Tasdiqlangan oy uchun ta'til, chiqib-kelish belgilari, o'rinbosarlik, bayram kunlari va avans o'zgarmaydi (qayta
--     ochilgandan keyin — mumkin).
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Sozlama: o'tish oyi (faqat Direktor; shu oydan keyin maosh berilgan bo'lsa — o'zgarmaydi)
alter table public.config add column if not exists "payrollApprovalFrom" text;
create or replace function app.config_payroll_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_new text; v_old text; v_min text;
begin
  if new.id is distinct from 'finance' then return new; end if;
  -- Upsert (setDoc merge): qator bor bo'lsa haqiqiy o'zgarish UPDATE'da tekshiriladi.
  if tg_op = 'INSERT' and exists (select 1 from public.config x where x.id = new.id) then return new; end if;
  v_new := nullif(btrim(coalesce(new."payrollApprovalFrom", '')), '');
  v_old := case when tg_op = 'UPDATE' then nullif(btrim(coalesce(old."payrollApprovalFrom", '')), '') end;
  if v_new is not distinct from v_old then return new; end if;
  if not app.is_system() and not app.is_admin() then
    raise exception 'Maosh tasdig''i o''tish oyini faqat Direktor o''zgartiradi' using errcode = '42501';
  end if;
  if v_new is not null and v_new !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'O''tish oyi YYYY-MM' using errcode = '22023'; end if;
  v_min := least(v_new, v_old);
  if v_min is not null and exists (select 1 from public.salary_payments p where coalesce(p.month, '') >= v_min) then
    raise exception 'Maosh tasdig''i o''tish oyi: % oydan boshlab maosh allaqachon berilgan — o''tish oyini o''zgartirib bo''lmaydi (keyingi oyni tanlang)', v_min
      using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function app.config_payroll_guard() from public, anon, authenticated;
drop trigger if exists trg_config_payroll_guard on public.config;
create trigger trg_config_payroll_guard before insert or update on public.config
  for each row execute function app.config_payroll_guard();

-- 2) Vedomost jadvallari
create table if not exists public.payroll_runs (
  id              text primary key,                      -- 'YYYY-MM'
  status          text not null default 'draft',         -- draft | submitted | approved | returned
  "preparedBy"    text, "preparedAt" timestamptz, "submittedAt" timestamptz, "prepNote" text,
  "approvedBy"    text, "approvedAt" timestamptz, "decisionNote" text,
  "returnedBy"    text, "returnedAt" timestamptz, "returnNote" text,
  "reopenedBy"    text, "reopenedAt" timestamptz, "reopenReason" text,
  totals          jsonb not null default '{}'::jsonb,
  version         int not null default 0
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'payroll_runs_status_chk') then
    alter table public.payroll_runs add constraint payroll_runs_status_chk check (status in ('draft','submitted','approved','returned'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'payroll_runs_id_chk') then
    alter table public.payroll_runs add constraint payroll_runs_id_chk check (id ~ '^\d{4}-(0[1-9]|1[0-2])$');
  end if;
end $$;
create table if not exists public.payroll_lines (
  id              text primary key,                      -- runId__personType__personId
  "runId"         text not null,
  "personType"    text not null,                         -- teacher | staff
  "personId"      text not null,                         -- maosh kaliti = salary_payments."teacherId" (teacherId / staffId)
  "refId"         text,                                  -- teachers/staff qator id
  name            text,
  gross           numeric not null default 0,            -- nominal (holat/sana prorata)
  deduction       numeric not null default 0,            -- davomat ushlanmasi (yo'qlama, kech, erta, o'z hisobidan, haqsiz ta'til)
  "subBonus"      numeric not null default 0,            -- o'rinbosarlik
  advance         numeric not null default 0,            -- shu oy avanslari (bazadan)
  "carryIn"       numeric not null default 0,            -- oldingi oylardan qolgan qoldiq (bazadan)
  payable         numeric not null default 0,            -- max(0, gross − avans − ushlanma + o'rinbosarlik + qoldiq)
  "workedMin"     numeric,
  details         jsonb not null default '{}'::jsonb,
  "needsDirector" boolean not null default false,        -- HR / Moliya menejerining o'z maoshi
  "directorOkBy"  text, "directorOkAt" timestamptz, "directorNote" text
);
create index if not exists payroll_lines_run_idx on public.payroll_lines("runId");
create unique index if not exists payroll_lines_person_uq on public.payroll_lines("runId", "personId");
alter table public.payroll_runs enable row level security;
alter table public.payroll_lines enable row level security;
revoke all on public.payroll_runs, public.payroll_lines from anon, authenticated;
grant select on public.payroll_runs, public.payroll_lines to authenticated;
grant all on public.payroll_runs, public.payroll_lines to service_role;
drop policy if exists pr_sel on public.payroll_runs;
create policy pr_sel on public.payroll_runs for select using (app.can_see_salary());
drop policy if exists pl_sel on public.payroll_lines;
create policy pl_sel on public.payroll_lines for select using (app.can_see_salary());

-- Oldingi oylardan qolgan qoldiq — admin.html carryBalance() bilan AYNAN bir xil: oy bo'yicha, oyning qarzi eng so'nggi (date)
--   yozuvidan (teng sanada — eng kattasi), to'lovlar yig'iladi; paid bo'sh (eski yozuv) — to'liq to'langan.
create or replace function app.salary_carry(p_tid text, p_before text) returns numeric
language sql stable security definer set search_path = public, app, pg_temp as $$
  with r as (
    select month, coalesce(date, '') as ord,
           case when gross is not null or advance is not null or deduction is not null
                then coalesce(gross, 0) - coalesce(advance, 0) - coalesce(deduction, 0) + coalesce("subBonus", 0)
                else coalesce(net, 0) + coalesce("subBonus", 0) end as due,
           paid
      from public.salary_payments
     where "teacherId" = p_tid and coalesce(month, '') <> '' and month < p_before),
  r2 as (select month, ord, due, coalesce(paid, due) as paidv from r),
  d as (select month, max(due) as due from r2 x where ord = (select max(ord) from r2 y where y.month = x.month) group by month),
  p as (select month, sum(paidv) as paid from r2 group by month)
  select coalesce(round(sum(d.due - p.paid)), 0) from d join p using (month)
$$;
revoke all on function app.salary_carry(text, text) from public, anon, authenticated;

create or replace function app.payroll_adv(p_tid text, p_month text) returns numeric
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(sum(coalesce(a.amount, 0)), 0) from public.staff_advances a
   where a."teacherId" = p_tid and coalesce(nullif(a.month, ''), left(coalesce(a.date, ''), 7)) = p_month
$$;
revoke all on function app.payroll_adv(text, text) from public, anon, authenticated;

-- 3) RPC: yuborish (Moliya menejeri / Direktor)
create or replace function public.payroll_submit(p_month text, p_lines jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); r public.payroll_runs%rowtype; x jsonb; v_type text; v_pid text; v_ref text; v_name text;
        v_g numeric; v_d numeric; v_s numeric; v_a numeric; v_c numeric; v_p numeric; v_w numeric; v_nd boolean;
        n int := 0; t_g numeric := 0; t_d numeric := 0; t_p numeric := 0; v_ids text[] := '{}';
begin
  if v_uid is null or not (app.has_role('finance_mgr') or app.has_role('director')) then
    raise exception 'Ruxsat yo''q: oylik vedomostni Moliya menejeri (yoki Direktor) tayyorlaydi' using errcode = '42501';
  end if;
  if coalesce(p_month, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Oy YYYY-MM' using errcode = '22023'; end if;
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'empty');
  end if;
  insert into public.payroll_runs(id) values (p_month) on conflict (id) do nothing;
  select * into r from public.payroll_runs where id = p_month for update;
  if r.status in ('submitted', 'approved') then return jsonb_build_object('ok', false, 'reason', 'status', 'status', r.status); end if;
  delete from public.payroll_lines where "runId" = p_month;
  for x in select value from jsonb_array_elements(p_lines) loop
    v_type := x->>'personType'; v_pid := btrim(coalesce(x->>'personId', ''));
    if coalesce(v_type, '') not in ('teacher', 'staff') or v_pid = '' then
      raise exception 'Vedomost qatori noto''g''ri (xodim turi yoki ID yo''q)' using errcode = '22023';
    end if;
    if v_pid = any(v_ids) then raise exception 'Vedomostda takroriy maosh ID: %', v_pid using errcode = '23505'; end if;
    v_ids := v_ids || v_pid;
    -- Xodim bazadan (ID, ism): mijoz yuborgan refId'ga ishonilmaydi (o'z qatori «Direktor tasdig'i»dan chetlab o'tmasin).
    if v_type = 'teacher' then
      select t.id, t.name into v_ref, v_name from public.teachers t where coalesce(nullif(btrim(t."teacherId"), ''), t.id) = v_pid limit 1;
    else
      select s.id, s.name into v_ref, v_name from public.staff s where coalesce(nullif(btrim(s."staffId"), ''), s.id) = v_pid limit 1;
    end if;
    if v_ref is null then raise exception 'Vedomost: «%» ID''li xodim topilmadi (o''chirilgan yoki ID o''zgargan) — qayta hisoblang', v_pid using errcode = '23503'; end if;
    begin
      v_g := round(coalesce((x->>'gross')::numeric, 0)); v_d := round(coalesce((x->>'deduction')::numeric, 0));
      v_s := round(coalesce((x->>'subBonus')::numeric, 0)); v_w := (x->>'workedMin')::numeric;
    exception when others then raise exception 'Vedomost qatori: summa noto''g''ri (%)', v_pid using errcode = '22023'; end;
    if v_g < 0 or v_d < 0 or v_s < 0 then raise exception 'Vedomost qatori: manfiy summa (%)', v_pid using errcode = '22023'; end if;
    -- Avans va oldingi qoldiq — BAZADAN (mijoz qiymati emas).
    v_a := app.payroll_adv(v_pid, p_month);
    v_c := app.salary_carry(v_pid, p_month);
    v_p := greatest(0, round(v_g - v_a - v_d + v_s + v_c));
    v_nd := exists (select 1 from public.users u where u."staffRefType" = v_type and u."staffRefId" = v_ref and u.role in ('hr', 'finance_mgr'));
    insert into public.payroll_lines(id, "runId", "personType", "personId", "refId", name, gross, deduction, "subBonus", advance, "carryIn", payable,
                                     "workedMin", details, "needsDirector")
    values (p_month || '__' || v_type || '__' || v_pid, p_month, v_type, v_pid, v_ref, coalesce(nullif(btrim(coalesce(x->>'name', '')), ''), v_name),
            v_g, v_d, v_s, v_a, v_c, v_p, v_w, case when jsonb_typeof(x->'details') = 'object' then x->'details' else '{}'::jsonb end, v_nd);
    n := n + 1; t_g := t_g + v_g; t_d := t_d + v_d; t_p := t_p + v_p;
  end loop;
  update public.payroll_runs
     set status = 'submitted', "preparedBy" = v_uid, "preparedAt" = now(), "submittedAt" = now(),
         "prepNote" = nullif(btrim(coalesce(p_note, '')), ''), "approvedBy" = null, "approvedAt" = null, "decisionNote" = null,
         totals = jsonb_build_object('count', n, 'gross', t_g, 'deduction', t_d, 'payable', t_p), version = version + 1
   where id = p_month;
  return jsonb_build_object('ok', true, 'count', n, 'payable', t_p, 'version', r.version + 1);
end $$;
revoke all on function public.payroll_submit(text, jsonb, text) from public, anon;
grant execute on function public.payroll_submit(text, jsonb, text) to authenticated, service_role;

-- HR menejer (HR bo'lmasa — Direktor) tasdiqlaydi yoki izoh bilan qaytaradi; tayyorlagan odam o'zi tasdiqlay olmaydi.
create or replace function public.payroll_decide(p_month text, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); r public.payroll_runs%rowtype;
begin
  if v_uid is null or not (app.has_role('hr') or app.has_role('director')) then
    raise exception 'Ruxsat yo''q: oylik vedomostni HR menejer tasdiqlaydi (yo''q bo''lsa — Direktor)' using errcode = '42501';
  end if;
  select * into r from public.payroll_runs where id = p_month for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.status <> 'submitted' then return jsonb_build_object('ok', false, 'reason', 'not_submitted', 'status', r.status); end if;
  if r."preparedBy" = v_uid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  if not coalesce(p_approve, false) then
    if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('ok', false, 'reason', 'note_required'); end if;
    update public.payroll_runs set status = 'returned', "returnedBy" = v_uid, "returnedAt" = now(), "returnNote" = btrim(p_note) where id = p_month;
    return jsonb_build_object('ok', true, 'status', 'returned');
  end if;
  update public.payroll_runs set status = 'approved', "approvedBy" = v_uid, "approvedAt" = now(),
         "decisionNote" = nullif(btrim(coalesce(p_note, '')), '') where id = p_month;
  return jsonb_build_object('ok', true, 'status', 'approved');
end $$;
revoke all on function public.payroll_decide(text, boolean, text) from public, anon;
grant execute on function public.payroll_decide(text, boolean, text) to authenticated, service_role;

-- HR / Moliya menejerining o'z maosh qatori — faqat Direktor tasdig'i bilan to'lanadi.
create or replace function public.payroll_approve_line(p_line text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); l public.payroll_lines%rowtype; v_st text;
begin
  if v_uid is null or not app.has_role('director') then raise exception 'Ruxsat yo''q: faqat Direktor' using errcode = '42501'; end if;
  select * into l from public.payroll_lines where id = p_line for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if not l."needsDirector" then return jsonb_build_object('ok', false, 'reason', 'not_needed'); end if;
  select status into v_st from public.payroll_runs where id = l."runId";
  if coalesce(v_st, '') not in ('submitted', 'approved') then return jsonb_build_object('ok', false, 'reason', 'not_submitted'); end if;
  update public.payroll_lines set "directorOkBy" = v_uid, "directorOkAt" = now(), "directorNote" = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_line;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.payroll_approve_line(text, text) from public, anon;
grant execute on function public.payroll_approve_line(text, text) to authenticated, service_role;

-- Direktor: tasdiqlangan oyni qayta ochish (sabab bilan) — berilgan maoshlar saqlanadi; Moliya menejeri qayta yuboradi.
create or replace function public.payroll_reopen(p_month text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); r public.payroll_runs%rowtype;
begin
  if v_uid is null or not app.has_role('director') then raise exception 'Ruxsat yo''q: oyni faqat Direktor qayta ochadi' using errcode = '42501'; end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'reason', 'note_required'); end if;
  select * into r from public.payroll_runs where id = p_month for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.status <> 'approved' then return jsonb_build_object('ok', false, 'reason', 'not_approved', 'status', r.status); end if;
  update public.payroll_runs set status = 'returned', "reopenedBy" = v_uid, "reopenedAt" = now(), "reopenReason" = btrim(p_reason),
         "returnedBy" = v_uid, "returnedAt" = now(), "returnNote" = 'Qayta ochildi: ' || btrim(p_reason)
   where id = p_month;
  return jsonb_build_object('ok', true, 'status', 'returned');
end $$;
revoke all on function public.payroll_reopen(text, text) from public, anon;
grant execute on function public.payroll_reopen(text, text) to authenticated, service_role;

-- 4) To'lov darvozasi (o'tish oyidan): tasdiqlangan vedomost, xodim qatori, Direktor tasdig'i (kerak bo'lsa), summa chegarasi.
create or replace function app.salary_payment_gate() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_from text; v_st text; l public.payroll_lines%rowtype; v_paid numeric; v_live numeric; v_cap numeric;
begin
  select nullif(btrim(coalesce(c."payrollApprovalFrom", '')), '') into v_from from public.config c where c.id = 'finance';
  if v_from is null or coalesce(new.month, '') < v_from then return new; end if;
  if tg_op = 'UPDATE' and new.paid is not distinct from old.paid and new.month is not distinct from old.month
     and new."teacherId" is not distinct from old."teacherId" then return new; end if;
  select status into v_st from public.payroll_runs where id = new.month;
  if coalesce(v_st, '') <> 'approved' then
    raise exception 'Maosh berilmaydi: % oy vedomosti HR menejer tomonidan tasdiqlanmagan', new.month using errcode = '23514';
  end if;
  select * into l from public.payroll_lines where "runId" = new.month and "personId" = new."teacherId";
  if not found then
    raise exception 'Maosh berilmaydi: bu xodim % oy tasdiqlangan vedomostida yo''q (Direktor oyni qayta ochadi, vedomost yangilanadi)', new.month using errcode = '23514';
  end if;
  if l."needsDirector" and l."directorOkAt" is null then
    raise exception 'Maosh berilmaydi: HR / Moliya menejerining o''z maoshi — Direktor tasdig''i kerak' using errcode = '23514';
  end if;
  perform pg_advisory_xact_lock(hashtext('iqror_salpay:' || coalesce(new."teacherId", '') || ':' || new.month));
  select coalesce(sum(coalesce(p.paid, 0)), 0) into v_paid from public.salary_payments p
   where p."teacherId" = new."teacherId" and p.month = new.month and p.id <> new.id;
  -- Tasdiqlangan summa, lekin hozirgi haqiqiy qarzdan ko'p emas (tasdiqdan keyin oldingi oy ortiqcha to'langan bo'lsa).
  v_live := greatest(0, l.gross - app.payroll_adv(new."teacherId", new.month) - l.deduction + l."subBonus" + app.salary_carry(new."teacherId", new.month));
  v_cap := least(l.payable, v_live) - v_paid;
  if coalesce(new.paid, 0) > v_cap + 0.5 then
    raise exception 'Maosh berilmaydi: tasdiqlangan summadan oshadi (berish mumkin: % so''m)', greatest(0, round(v_cap)) using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function app.salary_payment_gate() from public, anon, authenticated;
drop trigger if exists trg_salary_payment_gate on public.salary_payments;
create trigger trg_salary_payment_gate before insert or update on public.salary_payments
  for each row execute function app.salary_payment_gate();

-- 5) Tasdiqlangan oy kiritmalari qulfi
create or replace function app.payroll_locked_month(p_from text, p_to text) returns text
language sql stable security definer set search_path = public, app, pg_temp as $$
  select min(r.id) from public.payroll_runs r
   where r.status = 'approved' and r.id >= left(coalesce(p_from, ''), 7) and r.id <= left(coalesce(nullif(p_to, ''), p_from, ''), 7)
$$;
revoke all on function app.payroll_locked_month(text, text) from public, anon, authenticated;
create or replace function app.payroll_input_lock() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare j jsonb; a text; b text; m text;
begin
  if app.is_system() then return coalesce(new, old); end if;
  foreach j in array array[case when tg_op <> 'INSERT' then to_jsonb(old) end, case when tg_op <> 'DELETE' then to_jsonb(new) end] loop
    if j is null then continue; end if;
    if tg_table_name = 'staff_leaves' then a := j->>'startDay'; b := coalesce(nullif(j->>'endDay', ''), j->>'startDay');
    elsif tg_table_name = 'staff_advances' then a := coalesce(nullif(j->>'month', ''), left(coalesce(j->>'date', ''), 7)); b := a;
    elsif tg_table_name = 'staff_substitutions' then a := coalesce(nullif(j->>'month', ''), left(coalesce(j->>'day', ''), 7)); b := a;
    else a := j->>'day'; b := a; end if;   -- staff_break_marks, school_holidays
    m := app.payroll_locked_month(a, b);
    if m is not null then
      raise exception 'Oylik vedomost tasdiqlangan (%): bu oy uchun ta''til, avans, o''rinbosarlik, bayram va chiqib-kelish belgilari o''zgarmaydi — Direktor oyni qayta ochadi', m
        using errcode = '42501';
    end if;
  end loop;
  return coalesce(new, old);
end $$;
revoke all on function app.payroll_input_lock() from public, anon, authenticated;
do $$ declare t text; begin
  foreach t in array array['staff_leaves', 'staff_break_marks', 'staff_substitutions', 'school_holidays', 'staff_advances'] loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('drop trigger if exists trg_payroll_input_lock on public.%I', t);
    execute format('create trigger trg_payroll_input_lock before insert or update or delete on public.%I for each row execute function app.payroll_input_lock()', t);
  end loop;
end $$;

-- 6) O'zgarishlar tarixi
select app.chlog_attach('payroll_runs',  'status,preparedBy,prepNote,approvedBy,decisionNote,returnNote,reopenReason,totals,version');
select app.chlog_attach('payroll_lines', 'runId,personId,gross,deduction,subBonus,advance,carryIn,payable,needsDirector,directorOkBy,directorNote');
select app.chlog_attach('config',        '!refundPin,sickRate,sickApprovalFrom,bonusApprovalFrom,discountApprovalFrom,invoiceCreators,referralAmount,payrollApprovalFrom,entryDeadlineDay,lessonRate,latePenalty,earlyPenalty,allowedBreakMin,breakPenaltyPerHour,clickServiceId,clickMerchantId,uzumUrlTemplate,flatAmount,perYear,monthsPerYear,tenureYears,yearsCap,degree,category,languages,russian,langLevel');

notify pgrst, 'reload schema';
