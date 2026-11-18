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
--   * Xodim kartasining login havolasi (staff / teachers."userUid") — «o'z qatori» qoidasi unga tayanadi: faqat Direktor yoki server
--     o'zgartiradi, HR o'zi bog'langan kartani o'chira olmaydi (7-bo'lim).
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

-- Shu oy avanslari (bazadan; kassaga qaytarilgani — manfiy yozuv). Quyidagi qoldiq hisobi ham ishlatadi — shuning uchun undan OLDIN
--   (SQL funksiya tanasi yaratilganda tekshiriladi).
create or replace function app.payroll_adv(p_tid text, p_month text) returns numeric
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(sum(coalesce(a.amount, 0)), 0) from public.staff_advances a
   where a."teacherId" = p_tid and coalesce(nullif(a.month, ''), left(coalesce(a.date, ''), 7)) = p_month
$$;
revoke all on function app.payroll_adv(text, text) from public, anon, authenticated;

-- Oldingi oylardan qolgan qoldiq — admin.html carryBalance() bilan AYNAN bir xil, oy bo'yicha:
--   * o'tish oyidan OLDINGI oylar (yoki o'tish oyi belgilanmagan) — eski tartib: oyning qarzi eng so'nggi (date) yozuvidan (teng
--     sanada — eng kattasi), to'lovlar yig'iladi; paid bo'sh (eski yozuv) — to'liq to'langan.
--   * o'tish oyidan boshlab (audit-11, A5-01 / A5-02) — oyning qarzi TASDIQLANGAN vedomost qatoridan: maosh − shu oy avanslari (bazadan)
--     − ushlanma + o'rinbosarlik (darvozadagi «hozirgi qarz» bilan bir xil), berilgani — shu oy yozuvlari paid yig'indisi (bo'sh — 0).
--     Sabab: mijoz yozadigan maosh yozuvidagi gross / ushlanma / avans maydonlariga ishonilardi — kassir (HR / moliya ham) soxta «gross»
--     yoki manfiy summa bilan keyingi oy «oldingi qoldig'i»ni oshirib, HR tasdiqlagan summadan ko'p pul chiqara olardi (HR ekranidagi
--     qayta hisob xuddi shu yozuvlardan hisoblagani uchun farq ko'rinmasdi). Oy qayta ochilib kamroq summa bilan qayta tasdiqlansa —
--     ortiqcha berilgani keyingi oyga MANFIY qoldiq bo'lib o'tadi (eski yozuvdagi eski ushlanma emas, yangi tasdiqlangan qator).
--     Oy hozir tasdiqlanmagan bo'lsa (qayta ochilgan / qayta yuborilgan, HR hali tasdiqlamagan) — shu oy qoldiqqa kirmaydi (faqat HR
--     tasdiqlagan qiymatlar), tasdiqlangach o'zi qo'shiladi; tasdiqlangan vedomostda qatori yo'q xodimga berilgani — butunlay ortiqcha.
--     Eski tartib kabi faqat maosh yozuvi bor oylar hisoblanadi.
create or replace function app.salary_carry(p_tid text, p_before text) returns numeric
language sql stable security definer set search_path = public, app, pg_temp as $$
  with f as (select nullif(btrim(coalesce((select c."payrollApprovalFrom" from public.config c where c.id = 'finance'), '')), '') as v_from),
  r as (
    select s.month, coalesce(s.date, '') as ord,
           case when s.gross is not null or s.advance is not null or s.deduction is not null
                then coalesce(s.gross, 0) - coalesce(s.advance, 0) - coalesce(s.deduction, 0) + coalesce(s."subBonus", 0)
                else coalesce(s.net, 0) + coalesce(s."subBonus", 0) end as due,
           s.paid, (f.v_from is not null and s.month >= f.v_from) as gated
      from public.salary_payments s cross join f
     where s."teacherId" = p_tid and coalesce(s.month, '') <> '' and s.month < p_before),
  r2 as (select month, ord, due, coalesce(paid, due) as paidv from r where not gated),
  d as (select month, max(due) as due from r2 x where ord = (select max(ord) from r2 y where y.month = x.month) group by month),
  p as (select month, sum(paidv) as paid from r2 group by month),
  g as (select month, sum(coalesce(paid, 0)) as paid from r where gated group by month),
  gd as (select coalesce(l.gross - app.payroll_adv(p_tid, g.month) - l.deduction + l."subBonus", 0) - g.paid as bal
           from g join public.payroll_runs pr on pr.id = g.month and pr.status = 'approved'
           left join public.payroll_lines l on l."runId" = g.month and l."personId" = p_tid)
  select coalesce(round(coalesce((select sum(d.due - p.paid) from d join p using (month)), 0) + coalesce((select sum(gd.bal) from gd), 0)), 0)
$$;
revoke all on function app.salary_carry(text, text) from public, anon, authenticated;

-- 3) RPC: yuborish (Moliya menejeri / Direktor)
create or replace function public.payroll_submit(p_month text, p_lines jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); r public.payroll_runs%rowtype; x jsonb; v_type text; v_pid text; v_ref text; v_name text; v_link text;
        v_g numeric; v_d numeric; v_s numeric; v_a numeric; v_c numeric; v_p numeric; v_w numeric; v_nd boolean;
        n int := 0; t_g numeric := 0; t_d numeric := 0; t_p numeric := 0; v_ids text[] := '{}'; n_over int; s_over numeric;
begin
  if v_uid is null or not (app.has_role('finance_mgr') or app.has_role('director')) then
    raise exception 'Ruxsat yo''q: oylik vedomostni Moliya menejeri (yoki Direktor) tayyorlaydi' using errcode = '42501';
  end if;
  if coalesce(p_month, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Oy YYYY-MM' using errcode = '22023'; end if;
  -- (audit-11, A5-03) Kelgusi (hali boshlanmagan) oy uchun vedomost yo'q: davomat ushlanmasi va o'rinbosarlik hali yo'q, tasdiqlansa
  --   o'sha oyning ta'til / avans / o'rinbosarlik kiritmalari oldindan qulflanardi. Joriy (tugamagan) oy — tayyorlash mumkin (ushlanma
  --   «bugungacha»), lekin oy tugaguncha uni faqat Direktor tasdiqlaydi (payroll_decide). Sana — server (Toshkent) kuni.
  if p_month > to_char(app.fin_today(), 'YYYY-MM') then
    return jsonb_build_object('ok', false, 'reason', 'future', 'month', p_month);
  end if;
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
    -- Xodim bazadan (ID, ism, teskari havola): mijoz yuborgan refId'ga ishonilmaydi (o'z qatori «Direktor tasdig'i»dan chetlab o'tmasin).
    if v_type = 'teacher' then
      select t.id, t.name, t."userUid" into v_ref, v_name, v_link from public.teachers t where coalesce(nullif(btrim(t."teacherId"), ''), t.id) = v_pid limit 1;
    else
      select s.id, s.name, s."userUid" into v_ref, v_name, v_link from public.staff s where coalesce(nullif(btrim(s."staffId"), ''), s.id) = v_pid limit 1;
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
    -- HR / Moliya menejerining o'z qatori — Direktor tasdig'ida. Xodim kartasi foydalanuvchiga ikki yo'l bilan bog'lanadi: asosiy havola
    --   (users."staffRefType" / "staffRefId") yoki teskari havola (staff / teachers."userUid", staff-user-link.sql — ikkinchi lavozim
    --   kartasi shu yo'l bilan bog'lanadi); ikkalasi ham tekshiriladi (kassa moduli app.kassa_user_cards bilan bir xil qoida).
    v_nd := exists (select 1 from public.users u where u.role in ('hr', 'finance_mgr')
                     and ((u."staffRefType" = v_type and u."staffRefId" = v_ref) or u.id = nullif(v_link, '')));
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
  -- (audit-11, A5-02) Qayta ochilgan oy: shu oy allaqachon berilgani yangi to'lanadigandan ko'p bo'lsa — ortiqchasi yo'qolmaydi, keyingi
  --   oy vedomostida «oldingi qoldiq» (manfiy) bo'lib ushlanadi (app.salary_carry); Moliya menejeriga shu yerda ko'rsatiladi.
  select count(*), coalesce(sum(o.paid - o.payable), 0) into n_over, s_over
    from (select l.payable, (select coalesce(sum(coalesce(s.paid, 0)), 0) from public.salary_payments s
                              where s."teacherId" = l."personId" and s.month = p_month) as paid
            from public.payroll_lines l where l."runId" = p_month) o
   where o.paid > o.payable + 0.5;
  return jsonb_build_object('ok', true, 'count', n, 'payable', t_p, 'version', r.version + 1, 'overpaid', n_over, 'overpaidSum', s_over);
end $$;
revoke all on function public.payroll_submit(text, jsonb, text) from public, anon;
grant execute on function public.payroll_submit(text, jsonb, text) to authenticated, service_role;

-- HR menejer (HR bo'lmasa — Direktor) tasdiqlaydi yoki izoh bilan qaytaradi; tayyorlagan odam o'zi tasdiqlay olmaydi.
--   (audit-11, A5-03) Tugamagan oy: ushlanma faqat «bugungacha» hisoblangan, tasdiqdan keyin oyning qolgan kunlari uchun ta'til /
--   chiqib-kelish / o'rinbosarlik / avans qulflanadi — shuning uchun joriy oyni (maosh oy tugamasdan beriladigan bo'lsa) faqat Direktor
--   tasdiqlaydi (Direktor ruxsati), HR — oy tugagach; kelgusi oy — hech kim (reason 'not_ended' / 'future'). Qaytarish — har doim.
--   (audit-11, A5-06) «Direktor tasdig'i kerak» belgisi TASDIQLASH paytida ham qayta tekshiriladi: vedomost yuborilgandan keyin HR /
--   Moliya menejeri roli berilgan (qo'shimcha HR ham) yoki kartasi shunday hisobga bog'langan xodimning qatori shu yerda Direktor
--   tasdig'iga o'tadi (reports-roles.sql 5b himoya to'ri bilan bir xil shart — u faqat keyingi deployda ishlardi): yangi HR o'z maoshini
--   o'zi tasdiqlab, Direktorsiz ololmaydi. O'tkazilgan qatorlar soni javobda ('moved').
create or replace function public.payroll_decide(p_month text, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); r public.payroll_runs%rowtype; v_cur text; v_moved int;
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
  v_cur := to_char(app.fin_today(), 'YYYY-MM');
  if p_month > v_cur then return jsonb_build_object('ok', false, 'reason', 'future', 'status', r.status); end if;
  if p_month = v_cur and not app.has_role('director') then return jsonb_build_object('ok', false, 'reason', 'not_ended', 'status', r.status); end if;
  with moved as (
    update public.payroll_lines l set "needsDirector" = true
     where l."runId" = p_month and not l."needsDirector" and l."directorOkAt" is null
       and exists (select 1 from public.users u
                    where (u.role in ('hr', 'finance_mgr') or app.u_has(u.role, u."extraRoles", 'hr'))
                      and ((u."staffRefType" = l."personType" and u."staffRefId" = l."refId")
                           or u.id = nullif(case l."personType"
                                              when 'teacher' then (select t."userUid" from public.teachers t where t.id = l."refId")
                                              when 'staff' then (select s."userUid" from public.staff s where s.id = l."refId") end, '')))
    returning 1)
  select count(*) into v_moved from moved;
  update public.payroll_runs set status = 'approved', "approvedBy" = v_uid, "approvedAt" = now(),
         "decisionNote" = nullif(btrim(coalesce(p_note, '')), '') where id = p_month;
  return jsonb_build_object('ok', true, 'status', 'approved', 'moved', v_moved);
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
--   Kassaga qaytarilgan maosh (moliya moduli, kassa-links.sql «Xodim qaytargan pul») — MANFIY yozuv, faqat kassa funksiyasi ichida
--   (bayroq iqror.kassa_rpc): berilganni kamaytiradi, chegaradan oshmaydi — darvozadan o'tadi (oy shu orada qayta ochilgan bo'lsa ham).
--   Kassa moduli o'rnatilmagan bazada bu bayroqni hech narsa qo'ymaydi — darvoza avvalgidek.
--   (audit-11, A5-01) Darvoza mijoz yozgan maydonlarga ishonmaydi (kassir / HR / moliya PostgREST orqali o'z JWT'si bilan yozadi):
--     * manfiy summa — faqat kassa funksiyasidan (yuqoridagi istisno), boshqa yo'l bilan HECH QAYSI oyga yozilmaydi (o'tish oyi
--       belgilanmagan bo'lsa ham): avval manfiy qator chegaraga kirmasdan «berilgan»ni kamaytirib, keyingi to'lovni tasdiqlangan
--       summadan oshirishga yo'l ochardi;
--     * o'tish oyi belgilangach undan OLDINGI oy (eski tartib, chegarasiz) maoshini faqat Direktor (yoki server) yozadi: eski oyga soxta
--       «gross»li qator keyingi oylar «oldingi qoldig'i»ni oshirib, vedomost tasdig'ini chetlab o'tardi (kassa moduli ham bunday oy
--       uchun naqd maoshni faqat Direktorga beradi — kassa_salary_pay; kassaga qaytgan pul — yuqoridagi istisno). Xodim ID'sini
--       tuzatish (rekey_payroll_id — faqat kalit o'zgaradi) bu qoidaga kirmaydi;
--     * o'tish oyidan boshlab yozuvning maosh / ushlanma / o'rinbosarlik / avans / qoldiq maydonlari tasdiqlangan vedomost qatori va
--       bazadan yoziladi (mijoz yuborgani e'tiborsiz) — chek, hisobot va kassa qaytimi (oy hisob qiymatlari) shu qiymatni ko'radi.
--   (audit-11, A5-02) Summa chegarasi faqat pul berilganda (paid > 0): oy qayta ochilib kamroq summa bilan qayta tasdiqlangan bo'lsa,
--     0 so'mlik tuzatish yozuvi pul chiqarmaydi va rad etilmaydi (ortiqcha berilgani app.salary_carry bilan keyingi oyga o'tadi).
create or replace function app.salary_payment_gate() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_from text; v_st text; l public.payroll_lines%rowtype; v_paid numeric; v_live numeric; v_cap numeric;
        v_adv numeric; v_carry numeric; v_moved boolean := false;
begin
  if tg_op = 'INSERT' and coalesce(new.paid, 0) < 0 and coalesce(current_setting('iqror.kassa_rpc', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and new.paid is not distinct from old.paid and new.month is not distinct from old.month then
    if new."teacherId" is not distinct from old."teacherId" then return new; end if;
    v_moved := true;   -- faqat xodim kaliti o'zgardi (ID tuzatish) — summa va oy o'sha
  end if;
  if not v_moved and coalesce(new.paid, 0) < 0 then
    raise exception 'Maosh yozuvi: berilgan summa manfiy bo''lmaydi — xodim qaytargan pul faqat «Kassa» orqali (kirim orderi bilan) yoziladi'
      using errcode = '23514';
  end if;
  select nullif(btrim(coalesce(c."payrollApprovalFrom", '')), '') into v_from from public.config c where c.id = 'finance';
  if v_from is null then return new; end if;
  if coalesce(new.month, '') < v_from then
    if v_moved or app.is_system() or app.is_admin() then return new; end if;
    raise exception 'Maosh berilmaydi: % oy maosh tasdig''i tartibidan (o''tish oyi %) oldingi oy — bunday oy maoshini faqat Direktor yozadi',
      coalesce(nullif(new.month, ''), '(oysiz)'), v_from using errcode = '42501';
  end if;
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
  v_adv := app.payroll_adv(new."teacherId", new.month);
  v_carry := app.salary_carry(new."teacherId", new.month);
  v_live := greatest(0, l.gross - v_adv - l.deduction + l."subBonus" + v_carry);
  v_cap := least(l.payable, v_live) - v_paid;
  if coalesce(new.paid, 0) > 0 and new.paid > v_cap + 0.5 then
    raise exception 'Maosh berilmaydi: tasdiqlangan summadan oshadi (berish mumkin: % so''m)', greatest(0, round(v_cap)) using errcode = '23514';
  end if;
  if not v_moved then
    new.gross := l.gross; new.deduction := l.deduction; new."subBonus" := l."subBonus"; new.advance := v_adv;
    new.net := greatest(0, l.gross - v_adv - l.deduction);
    new."carryIn" := v_carry;
    new."carryOut" := round(l.gross - v_adv - l.deduction + l."subBonus" + v_carry - v_paid - coalesce(new.paid, 0));
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

-- 7) Xodim kartasining login havolasi (staff / teachers."userUid" — teskari havola, staff-user-link.sql) himoyasi.
--    «O'z qatori Direktor tasdig'ida» qoidasi (payroll_submit, reports-roles.sql: app.payroll_line_extra_hr) va kassa moduli
--    (app.kassa_user_cards) shu havolaga ishonadi, staff_upd / teachers_upd esa HR'ga butun qatorni yozishga ruxsat beradi: HR o'z
--    kartasidagi havolani uzib (yoki boshqa kartaga ko'chirib) o'z maosh qatorini Direktor tasdig'isiz qoldira olardi. Asosiy havolani
--    (users."staffRefType" / "staffRefId") users_upd qotiradi; teskari havolani endi ham faqat Direktor («Foydalanuvchilar» → bog'lash)
--    yoki server (ro'yxatdan o'tish — service_role, migratsiya, psql) o'zgartiradi, boshqa foydalanuvchida — 42501. Havola o'zgarmagan
--    yozuv o'tadi (boshqa maydonlarni tahrirlash, shu qiymat bilan to'liq qator upsert'i); null va '' — bir xil (bog'lanmagan):
--    Direktor / serverdan boshqa yozuvchining null ↔ '' almashtirishi saqlangan qiymatga qaytariladi (tarixda «— → —» qatori chiqmaydi).
--    O'zi bog'langan kartani (asosiy yoki teskari havola) HR o'chira olmaydi (staff_del HR'ga ochiq; teachers_del — faqat Direktor):
--    o'chirib, bog'lanmagan yangi karta ochsa ham o'z qatori tasdiqsiz qolardi (bunday kartani Direktor o'chiradi).
--    O'zgarishlar tarixida — change-log.sql («userUid» ustuni).
create or replace function app.guard_card_user_link() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_cur text; v_hit boolean;
begin
  if app.is_system() or app.is_admin() then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    if (coalesce(old."userUid", '') <> '' and old."userUid" = app.uid())
       or exists (select 1 from public.users u
                   where u.id = app.uid() and u."staffRefId" = old.id
                     and u."staffRefType" = case tg_table_name when 'teachers' then 'teacher' else 'staff' end) then
      raise exception 'O''zingiz bog''langan xodim kartasini o''chira olmaysiz — uni Direktor o''chiradi' using errcode = '42501';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' then
    -- Havola o'zgarmagan — o'tadi; null ↔ '' almashtirishda saqlangan qiymat qoladi (no-op tarix qatori bo'lmasin).
    if coalesce(new."userUid", '') = coalesce(old."userUid", '') then new."userUid" := old."userUid"; return new; end if;
  else
    -- INSERT: yozish huquqi yo'q rolni RLS (staff_ins / teachers_ins) rad etadi (trigger RLS'dan OLDIN ishlaydi — javob farqi
    --   yozuv borligini oshkor qilmasin). Bo'sh havola — o'tadi; upsert (INSERT ... ON CONFLICT DO UPDATE) bog'lanmagan mavjud
    --   qatorga mos kelsa — saqlangan qiymat (null yoki '') bilan. Mavjud qatorga o'sha qiymatni yozsa — o'tadi (UPDATE bosqichini
    --   shu trigger yana tekshiradi).
    if not app.is_hr() then return new; end if;
    execute format('select "userUid", true from public.%I where id = $1', tg_table_name) into v_cur, v_hit using new.id;
    if coalesce(new."userUid", '') = '' then
      if v_hit and coalesce(v_cur, '') = '' then new."userUid" := v_cur; end if;
      return new;
    end if;
    if coalesce(v_cur, '') = new."userUid" then return new; end if;
  end if;
  raise exception 'Xodim kartasining login hisobiga bog''lanishini faqat Direktor o''zgartiradi («Foydalanuvchilar» bo''limi)'
    using errcode = '42501';
end $$;
revoke all on function app.guard_card_user_link() from public, anon, authenticated;
drop trigger if exists trg_teacher_user_link on public.teachers;
create trigger trg_teacher_user_link before insert or update or delete on public.teachers
  for each row execute function app.guard_card_user_link();
drop trigger if exists trg_staff_user_link on public.staff;
create trigger trg_staff_user_link before insert or update or delete on public.staff
  for each row execute function app.guard_card_user_link();

notify pgrst, 'reload schema';
