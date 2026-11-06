\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: discount-approval.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- discount-approval.sql — CHEGIRMA VA GRANT: Direktor VA Moliya menejeri tasdig'i; TAVSIYA bonusi — yangi o'quvchi to'lov
--   qilgach, Moliya menejeri tasdig'i bilan (direktor qarori D1).
--   * discount_requests: so'rov (qabulxona, O'IBDO', Moliya menejeri, Direktor) → ikki slot: Direktor + Moliya menejeri
--     (g'aznachi emas; bitta odam ikkala slotga emas) → ikkinchi tasdiqda student_private'ga yoziladi (shu fayldagi RPC).
--     student_private chegirma maydonlari (specialCategory, teacherId, contractAmount, siblingDiscount, referrerId) endi
--     FAQAT RPC orqali o'zgaradi (mijoz yozuvi — rad). Mavjud chegirmalar bir martalik «meros» (legacy) tasdiqlangan yozuv.
--   * referral_requests: tavsiya qayd etiladi (referral_register) → yangi o'quvchining birinchi haqiqiy to'lovi (payments
--     status 'paid') → Moliya menejeri tasdiqlaydi → hisob-fakturada qo'llanadi (applied). To'lov bekor/qaytarilsa → revoked.
--   * O'tish oyi config/finance."discountApprovalFrom": shu oy FAKTURASIDAN boshlab grant / ≥50% / kontrakt chegirmasi
--     faqat amaldagi (fromMonth..toMonth) tasdiqlangan so'rovga ishora (invoices."approvalRefs") bilan; tavsiya bonusi
--     (referral_ledger) — faqat tasdiqlangan tavsiya bilan. Undan oldingi oylar — eski qoida.
--   * Faktura maydonlari: summa/chegirma/grant/kasal/bonus/ishoralarni Direktordan boshqasi to'g'ridan-to'g'ri o'zgartira
--     olmaydi (faqat to'lov maydonlari yoki reprice_invoice RPC). Faktura yaratish: config/finance."invoiceCreators"
--     ('director' — standart | 'director_finance').
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Sozlamalar (config/finance)
alter table public.config add column if not exists "discountApprovalFrom" text;   -- o'tish oyi (nurse-sick.sql umumiy guard)
alter table public.config add column if not exists "invoiceCreators"      text;   -- 'director' | 'director_finance'
alter table public.config add column if not exists "referralAmount"       numeric; -- standart 300 000
create or replace function app.config_finance_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if new.id is distinct from 'finance' then return new; end if;
  if coalesce(new."invoiceCreators", '') not in ('', 'director', 'director_finance') then
    raise exception 'Hisob-faktura yaratuvchi: director yoki director_finance' using errcode = '22023';
  end if;
  if new."referralAmount" is not null and (new."referralAmount" < 0 or new."referralAmount" > 100000000) then
    raise exception 'Tavsiya bonusi summasi noto''g''ri' using errcode = '22023';
  end if;
  -- Tasdiq qoidalari sozlamalarini faqat Direktor o'zgartiradi (moliya «finance» qatorining boshqa maydonlarini yozadi).
  if not app.is_system() and not app.is_admin() and tg_op = 'UPDATE'
     and (new."invoiceCreators" is distinct from old."invoiceCreators" or new."referralAmount" is distinct from old."referralAmount"
          or new."discountApprovalFrom" is distinct from old."discountApprovalFrom" or new."sickApprovalFrom" is distinct from old."sickApprovalFrom"
          or new."bonusApprovalFrom" is distinct from old."bonusApprovalFrom") then
    raise exception 'Tasdiq qoidalarini faqat Direktor o''zgartiradi' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function app.config_finance_guard() from public, anon, authenticated;
drop trigger if exists trg_config_finance_guard on public.config;
create trigger trg_config_finance_guard before insert or update on public.config
  for each row execute function app.config_finance_guard();

-- 2) Chegirma so'rovlari
create table if not exists public.discount_requests (
  id              text primary key default gen_random_uuid()::text,
  "studentId"     text not null,                 -- kanonik (students."studentId" yoki id)
  kind            text not null,                 -- teacher_child | olympiad | social | contract | none | sibling_force | sibling_exclude | sibling_auto
  params          jsonb not null default '{}'::jsonb,   -- {teacherId} | {contractAmount}
  "fromMonth"     text,                          -- 'YYYY-MM' (bo'sh — darhol)
  "toMonth"       text,                          -- 'YYYY-MM' (bo'sh — muddatsiz)
  reason          text,
  status          text not null default 'pending',      -- pending | approved | rejected | canceled
  "requestedBy"   text,
  "requestedAt"   timestamptz not null default now(),
  "directorBy"    text, "directorAt" timestamptz, "directorNote" text, "directorOk" boolean,
  "financeBy"     text, "financeAt"  timestamptz, "financeNote"  text, "financeOk"  boolean,
  legacy          boolean not null default false,
  "appliedAt"     timestamptz
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'discount_requests_kind_chk') then
    alter table public.discount_requests add constraint discount_requests_kind_chk
      check (kind in ('teacher_child','olympiad','social','contract','none','sibling_force','sibling_exclude','sibling_auto'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'discount_requests_status_chk') then
    alter table public.discount_requests add constraint discount_requests_status_chk check (status in ('pending','approved','rejected','canceled'));
  end if;
end $$;
create index if not exists discount_requests_student_idx on public.discount_requests("studentId");
create index if not exists discount_requests_status_idx on public.discount_requests(status);
alter table public.discount_requests enable row level security;
revoke all on public.discount_requests from anon, authenticated;
grant select on public.discount_requests to authenticated;
grant all on public.discount_requests to service_role;
drop policy if exists dr_sel on public.discount_requests;
create policy dr_sel on public.discount_requests for select
  using (app.is_admin() or app.is_finance_mgr() or app.is_zavuch() or app.is_reception() or app.owns_child("studentId"));

-- Chegirma guruhi: toifa (specialCategory) yoki aka-uka (siblingDiscount).
create or replace function app.discount_group(p_kind text) returns text language sql immutable set search_path = pg_catalog as $$
  select case when p_kind like 'sibling_%' then 'sibling' else 'category' end $$;

create or replace function public.discount_request_create(p_sid text, p_kind text, p_params jsonb, p_from text, p_to text, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_sid text; v_id text := gen_random_uuid()::text; v_amt numeric;
        -- Boshlanish oyi bo'sh — «darhol» = joriy oy (Toshkent): o'tgan oylar fakturalariga orqaga qarab qo'llanmasin.
        v_from text := coalesce(nullif(btrim(coalesce(p_from, '')), ''), to_char(now() at time zone 'Asia/Tashkent', 'YYYY-MM'));
        v_to   text := nullif(btrim(coalesce(p_to, '')), '');
begin
  if v_uid is null or not (app.is_admin() or app.has_role('finance_mgr') or app.is_zavuch() or app.is_reception()) then
    raise exception 'Ruxsat yo''q: chegirma so''rovini Direktor, Moliya menejeri, O''IBDO'' yoki qabulxona yaratadi' using errcode = '42501';
  end if;
  select coalesce(nullif(s."studentId", ''), s.id) into v_sid from public.students s
   where s."studentId" = p_sid or s.id = p_sid order by (s."studentId" = p_sid) desc limit 1;
  if v_sid is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if coalesce(p_kind, '') not in ('teacher_child','olympiad','social','contract','none','sibling_force','sibling_exclude','sibling_auto') then
    raise exception 'Noto''g''ri chegirma turi' using errcode = '22023';
  end if;
  if v_from !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Boshlanish oyi YYYY-MM' using errcode = '22023'; end if;
  if v_to is not null and v_to !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Tugash oyi YYYY-MM' using errcode = '22023'; end if;
  if v_to is not null and v_to < v_from then raise exception 'Tugash oyi boshlanishdan oldin' using errcode = '22023'; end if;
  if coalesce(btrim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'reason', 'reason_required'); end if;
  if p_kind = 'contract' then
    begin v_amt := (p_params->>'contractAmount')::numeric; exception when others then v_amt := null; end;
    if not (coalesce(v_amt, 0) > 0) then return jsonb_build_object('ok', false, 'reason', 'amount_required'); end if;
  end if;
  insert into public.discount_requests(id, "studentId", kind, params, "fromMonth", "toMonth", reason, status, "requestedBy", "requestedAt")
  values (v_id, v_sid, p_kind,
          case p_kind when 'contract' then jsonb_build_object('contractAmount', v_amt)
                      when 'teacher_child' then jsonb_strip_nulls(jsonb_build_object('teacherId', nullif(btrim(coalesce(p_params->>'teacherId', '')), '')))
                      else '{}'::jsonb end,
          v_from, v_to, btrim(p_reason), 'pending', v_uid, now());
  return jsonb_build_object('ok', true, 'id', v_id, 'fromMonth', v_from);
end $$;
revoke all on function public.discount_request_create(text, text, jsonb, text, text, text) from public, anon;
grant execute on function public.discount_request_create(text, text, jsonb, text, text, text) to authenticated, service_role;

-- Tasdiqlangan so'rovni student_private'ga yozish (faqat shu fayldagi RPC'lar; iqror.discount_rpc bayrog'i).
create or replace function app.discount_apply(p_req public.discount_requests) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_doc text;
begin
  select s.id into v_doc from public.students s where s."studentId" = p_req."studentId" or s.id = p_req."studentId"
   order by (s."studentId" = p_req."studentId") desc limit 1;
  if v_doc is null then return; end if;
  perform set_config('iqror.discount_rpc', '1', true);
  insert into public.student_private(id) values (v_doc) on conflict (id) do nothing;
  if app.discount_group(p_req.kind) = 'sibling' then
    update public.student_private set "siblingDiscount" = case p_req.kind when 'sibling_force' then 'Ha' when 'sibling_exclude' then 'Yoq' else '' end
     where id = v_doc;
  else
    update public.student_private
       set "specialCategory" = case p_req.kind when 'social' then 'olympiad' when 'none' then '' else p_req.kind end,
           "teacherId"       = case when p_req.kind = 'teacher_child' then nullif(p_req.params->>'teacherId', '') else "teacherId" end,
           "contractAmount"  = case when p_req.kind = 'contract' then (p_req.params->>'contractAmount')::numeric else null end
     where id = v_doc;
  end if;
  perform set_config('iqror.discount_rpc', '', true);
end $$;
revoke all on function app.discount_apply(public.discount_requests) from public, anon, authenticated;

create or replace function public.discount_decide(p_id text, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); r public.discount_requests%rowtype; v_slot text;
begin
  if v_uid is null then raise exception 'auth required' using errcode = '42501'; end if;
  if app.has_role('director') then v_slot := 'director';
  elsif app.has_role('finance_mgr') then v_slot := 'finance';
  else raise exception 'Ruxsat yo''q: chegirmani Direktor va Moliya menejeri tasdiqlaydi' using errcode = '42501'; end if;
  select * into r from public.discount_requests where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.status <> 'pending' then return jsonb_build_object('ok', false, 'reason', 'not_pending', 'status', r.status); end if;
  if (v_slot = 'director' and r."directorBy" is not null) or (v_slot = 'finance' and r."financeBy" is not null) then
    return jsonb_build_object('ok', false, 'reason', 'slot_done');
  end if;
  if (v_slot = 'director' and r."financeBy" = v_uid) or (v_slot = 'finance' and r."directorBy" = v_uid) then
    return jsonb_build_object('ok', false, 'reason', 'self');   -- bitta odam ikkala slotga emas
  end if;
  if not coalesce(p_approve, false) and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'note_required');
  end if;
  if v_slot = 'director' then
    update public.discount_requests set "directorBy" = v_uid, "directorAt" = now(), "directorOk" = coalesce(p_approve, false),
           "directorNote" = nullif(btrim(coalesce(p_note, '')), '') where id = p_id;
  else
    update public.discount_requests set "financeBy" = v_uid, "financeAt" = now(), "financeOk" = coalesce(p_approve, false),
           "financeNote" = nullif(btrim(coalesce(p_note, '')), '') where id = p_id;
  end if;
  if not coalesce(p_approve, false) then
    update public.discount_requests set status = 'rejected' where id = p_id;
    return jsonb_build_object('ok', true, 'status', 'rejected');
  end if;
  select * into r from public.discount_requests where id = p_id;
  if coalesce(r."directorOk", false) and coalesce(r."financeOk", false) then
    update public.discount_requests set status = 'approved', "appliedAt" = now() where id = p_id;
    -- Shu o'quvchining shu guruhdagi boshqa ochiq so'rovlari bekor (ziddiyat bo'lmasin).
    update public.discount_requests set status = 'canceled', reason = coalesce(reason, '') || ' [boshqa so''rov tasdiqlandi]'
     where "studentId" = r."studentId" and status = 'pending' and id <> p_id and app.discount_group(kind) = app.discount_group(r.kind);
    select * into r from public.discount_requests where id = p_id;
    perform app.discount_apply(r);
    return jsonb_build_object('ok', true, 'status', 'approved');
  end if;
  return jsonb_build_object('ok', true, 'status', 'pending', 'slot', v_slot);
end $$;
revoke all on function public.discount_decide(text, boolean, text) from public, anon;
grant execute on function public.discount_decide(text, boolean, text) to authenticated, service_role;

create or replace function public.cancel_discount_request(p_id text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); r public.discount_requests%rowtype;
begin
  if v_uid is null then raise exception 'auth required' using errcode = '42501'; end if;
  select * into r from public.discount_requests where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.status <> 'pending' then return jsonb_build_object('ok', false, 'reason', 'not_pending'); end if;
  if r."requestedBy" is distinct from v_uid and not app.has_role('director') then
    raise exception 'Ruxsat yo''q: so''rovni so''ragan odam yoki Direktor bekor qiladi' using errcode = '42501';
  end if;
  update public.discount_requests set status = 'canceled' where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.cancel_discount_request(text) from public, anon;
grant execute on function public.cancel_discount_request(text) to authenticated, service_role;

-- 3) student_private chegirma maydonlari — faqat RPC orqali (iqror.discount_rpc / iqror.referral_rpc bayrog'i yoki tizim).
create or replace function app.student_private_discount_lock() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare n text := '';
begin
  if app.is_system() or coalesce(current_setting('iqror.discount_rpc', true), '') = '1' then return new; end if;
  if tg_op = 'INSERT' then
    -- Upsert (setDoc merge): qator BOR bo'lsa haqiqiy o'zgarish UPDATE'da tekshiriladi.
    if exists (select 1 from public.student_private p where p.id = new.id) then return new; end if;
    if coalesce(new."specialCategory", '') <> '' or coalesce(btrim(new."teacherId"), '') <> '' or coalesce(new."contractAmount", 0) <> 0
       or coalesce(new."siblingDiscount", '') <> '' or coalesce(btrim(new."referrerId"), '') <> '' then
      raise exception 'Chegirma / grant / tavsiya faqat «💸 Chegirma so''rash» orqali (Direktor va Moliya menejeri tasdiqlaydi)' using errcode = '42501';
    end if;
    return new;
  end if;
  if coalesce(new."specialCategory", '') is distinct from coalesce(old."specialCategory", '') then n := 'specialCategory';
  -- rekey_payroll_id (id-guards.sql, iqror.rekey): o'qituvchi ID'si tuzatilganda «xodim farzandi» bog'lanishi yangi ID'ga
  --   ko'chadi — faqat teacherId (toifa/summa emas).
  elsif coalesce(btrim(new."teacherId"), '') is distinct from coalesce(btrim(old."teacherId"), '')
        and coalesce(current_setting('iqror.rekey', true), '') <> '1' then n := 'teacherId';
  elsif coalesce(new."contractAmount", 0) is distinct from coalesce(old."contractAmount", 0) then n := 'contractAmount';
  elsif coalesce(new."siblingDiscount", '') is distinct from coalesce(old."siblingDiscount", '') then n := 'siblingDiscount';
  elsif coalesce(btrim(new."referrerId"), '') is distinct from coalesce(btrim(old."referrerId"), '') then n := 'referrerId'; end if;
  if n <> '' then
    raise exception 'Chegirma / grant / tavsiya (%) faqat «💸 Chegirma so''rash» orqali (Direktor va Moliya menejeri tasdiqlaydi)', n using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function app.student_private_discount_lock() from public, anon, authenticated;
drop trigger if exists trg_sp_discount_lock on public.student_private;
create trigger trg_sp_discount_lock before insert or update on public.student_private
  for each row execute function app.student_private_discount_lock();

-- 4) Meros: mavjud chegirmalar — tasdiqlangan (legacy) yozuvlar (bir marta; qayta ishga tushganda ko'paymaydi).
insert into public.discount_requests(id, "studentId", kind, params, reason, status, legacy, "requestedAt", "appliedAt")
select 'legacy__' || x.sid || '__cat', x.sid,
       case when x.cat = 'olympiad' then 'olympiad' when x.cat = 'contract' then 'contract' else 'teacher_child' end,
       case when x.cat = 'contract' then jsonb_build_object('contractAmount', x.amt)
            when x.cat = 'teacher_child' then jsonb_strip_nulls(jsonb_build_object('teacherId', nullif(btrim(coalesce(x.tid, '')), '')))
            else '{}'::jsonb end,
       'Avvaldan bor (meros) — direktor ko''rib chiqadi', 'approved', true, now(), now()
  from (select coalesce(nullif(s."studentId", ''), p.id) as sid, p."specialCategory" as cat, p."contractAmount" as amt, p."teacherId" as tid
          from public.student_private p left join public.students s on s.id = p.id
         where p."specialCategory" in ('teacher_child', 'olympiad', 'contract')) x
on conflict (id) do nothing;
insert into public.discount_requests(id, "studentId", kind, params, reason, status, legacy, "requestedAt", "appliedAt")
select 'legacy__' || coalesce(nullif(s."studentId", ''), p.id) || '__sib', coalesce(nullif(s."studentId", ''), p.id),
       case when p."siblingDiscount" = 'Ha' then 'sibling_force' else 'sibling_exclude' end, '{}'::jsonb,
       'Avvaldan bor (meros) — direktor ko''rib chiqadi', 'approved', true, now(), now()
  from public.student_private p left join public.students s on s.id = p.id
 where p."siblingDiscount" in ('Ha', 'Yoq')
on conflict (id) do nothing;

-- 5) Tavsiya (referral)
create table if not exists public.referral_requests (
  id                text primary key,              -- yangi (tavsiya qilingan) o'quvchi ID = referral_ledger.id
  "referrerId"      text not null,                 -- tavsiya qilgan o'quvchi ID
  status            text not null default 'pending_payment',   -- pending_payment | approved | rejected | applied | revoked
  "firstPaymentId"  text,
  "firstPaymentAt"  timestamptz,
  "createdBy"       text,
  "createdAt"       timestamptz not null default now(),
  "decidedBy"       text, "decidedAt" timestamptz, "decisionNote" text,
  "appliedAt"       timestamptz,
  "revokeWarn"      boolean not null default false,
  legacy            boolean not null default false
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'referral_requests_status_chk') then
    alter table public.referral_requests add constraint referral_requests_status_chk
      check (status in ('pending_payment','approved','rejected','applied','revoked'));
  end if;
end $$;
alter table public.referral_requests enable row level security;
revoke all on public.referral_requests from anon, authenticated;
grant select on public.referral_requests to authenticated;
grant all on public.referral_requests to service_role;
drop policy if exists rr_sel on public.referral_requests;
create policy rr_sel on public.referral_requests for select
  using (app.is_admin() or app.is_finance_mgr() or app.is_zavuch() or app.is_reception() or app.owns_child(id) or app.owns_child("referrerId"));
-- Meros: mavjud referrerId — ledger'da bo'lsa applied, aks holda to'lov kutilmoqda.
insert into public.referral_requests(id, "referrerId", status, legacy, "appliedAt")
select x.nid, x.rid, case when exists (select 1 from public.referral_ledger l where l.id = x.nid) then 'applied' else 'pending_payment' end,
       true, case when exists (select 1 from public.referral_ledger l where l.id = x.nid) then now() end
  from (select distinct on (coalesce(nullif(s."studentId", ''), p.id)) coalesce(nullif(s."studentId", ''), p.id) as nid, btrim(p."referrerId") as rid
          from public.student_private p left join public.students s on s.id = p.id
         where coalesce(btrim(p."referrerId"), '') <> '' order by coalesce(nullif(s."studentId", ''), p.id)) x
 where x.nid <> x.rid
on conflict (id) do nothing;

-- O'quvchining SOF haqiqiy puli: haqiqiy holatli to'lovlar (avans ko'chirmalari 'reattr' ± bilan) − faktura qaytarishlari.
--   (To'lov qaytarilsa — refund_invoice('payment') to'lovni 'refunded' qiladi, u yig'indiga kirmaydi; faktura qaytarishi
--    to'lov holatini o'zgartirmaydi, shuning uchun refunds jurnalidan ayiriladi.)
create or replace function app.student_real_net(p_sid text) returns numeric
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select sum(coalesce(p.amount, 0)) from public.payments p
                    where p."studentId" = p_sid and coalesce(p.status, '') in ('paid', 'applied', 'confirmed')), 0)
       - coalesce((select sum(coalesce(r.amount, 0)) from public.refunds r
                    where r."studentId" = p_sid and coalesce(r.target, '') = 'invoice'), 0)
$$;
revoke all on function app.student_real_net(text) from public, anon, authenticated;
-- Birinchi haqiqiy to'lov (summa > 0): 'paid' (faktura to'g'ridan-to'g'ri to'langan), 'applied' (balansga / fakturalarga
--   qo'llangan — naqd, bank, terminal, Click'ning ko'p to'lovlari) yoki 'confirmed' (Uzum — asosiy usul). Avval faqat 'paid'
--   olinardi -> bunday to'lovli yangi o'quvchining tavsiya bonusini hech qachon tasdiqlab bo'lmasdi.
--   Hisoblanmaydi: qaytarilgan / bekor / kutilayotgan / bo'lingan (split — pul bolalarida) to'lovlar, avans ko'chirmasi
--   ('reattr' — oilaning boshqa farzandidan o'tkazilgan pul, yangi to'lov emas) va sof puli 0 bo'lgan o'quvchi (masalan,
--   adashib shu o'quvchiga qo'llangan to'lov boshqasiga ko'chirilgan yoki to'liq qaytarilgan).
create or replace function app.first_real_payment(p_sid text) returns table(pid text, pat timestamptz)
language sql stable security definer set search_path = public, app, pg_temp as $$
  select p.id, p."createdAt" from public.payments p
   where p."studentId" = p_sid and coalesce(p.status, '') in ('paid', 'applied', 'confirmed') and coalesce(p.amount, 0) > 0
     and coalesce(p.provider, '') <> 'reattr'
     and app.student_real_net(p_sid) > 0
   order by p."createdAt" nulls last, p.id limit 1
$$;
revoke all on function app.first_real_payment(text) from public, anon, authenticated;

create or replace function public.referral_register(p_new_sid text, p_referrer_sid text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_new text; v_doc text; v_ref text; r public.referral_requests%rowtype;
begin
  if v_uid is null or not (app.is_admin() or app.has_role('finance_mgr') or app.is_zavuch() or app.is_reception()) then
    raise exception 'Ruxsat yo''q' using errcode = '42501';
  end if;
  select coalesce(nullif(s."studentId", ''), s.id), s.id into v_new, v_doc from public.students s
   where s."studentId" = p_new_sid or s.id = p_new_sid order by (s."studentId" = p_new_sid) desc limit 1;
  select coalesce(nullif(s."studentId", ''), s.id) into v_ref from public.students s
   where s."studentId" = p_referrer_sid or s.id = p_referrer_sid order by (s."studentId" = p_referrer_sid) desc limit 1;
  if v_new is null or v_ref is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if v_new = v_ref then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  select * into r from public.referral_requests where id = v_new;
  if found and r.status in ('approved', 'applied') then return jsonb_build_object('ok', false, 'reason', 'already', 'status', r.status); end if;
  insert into public.referral_requests(id, "referrerId", status, "createdBy", "createdAt")
  values (v_new, v_ref, 'pending_payment', v_uid, now())
  on conflict (id) do update set "referrerId" = excluded."referrerId", status = 'pending_payment', "createdBy" = excluded."createdBy",
     "createdAt" = now(), "decidedBy" = null, "decidedAt" = null, "decisionNote" = null, "firstPaymentId" = null, "firstPaymentAt" = null;
  perform set_config('iqror.discount_rpc', '1', true);
  insert into public.student_private(id) values (v_doc) on conflict (id) do nothing;
  update public.student_private set "referrerId" = v_ref where id = v_doc;
  perform set_config('iqror.discount_rpc', '', true);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.referral_register(text, text) from public, anon;
grant execute on function public.referral_register(text, text) to authenticated, service_role;

create or replace function public.referral_decide(p_id text, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); r public.referral_requests%rowtype; v_pid text; v_pat timestamptz;
begin
  if v_uid is null or not app.has_role('finance_mgr') then
    raise exception 'Ruxsat yo''q: tavsiya bonusini Moliya menejeri tasdiqlaydi' using errcode = '42501';
  end if;
  select * into r from public.referral_requests where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.status <> 'pending_payment' then return jsonb_build_object('ok', false, 'reason', 'not_pending', 'status', r.status); end if;
  if not coalesce(p_approve, false) then
    if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('ok', false, 'reason', 'note_required'); end if;
    update public.referral_requests set status = 'rejected', "decidedBy" = v_uid, "decidedAt" = now(), "decisionNote" = btrim(p_note) where id = p_id;
    return jsonb_build_object('ok', true, 'status', 'rejected');
  end if;
  select f.pid, f.pat into v_pid, v_pat from app.first_real_payment(r.id) f;
  if v_pid is null then return jsonb_build_object('ok', false, 'reason', 'no_payment'); end if;
  update public.referral_requests set status = 'approved', "firstPaymentId" = v_pid, "firstPaymentAt" = v_pat,
         "decidedBy" = v_uid, "decidedAt" = now(), "decisionNote" = nullif(btrim(coalesce(p_note, '')), '') where id = p_id;
  return jsonb_build_object('ok', true, 'status', 'approved');
end $$;
revoke all on function public.referral_decide(text, boolean, text) from public, anon;
grant execute on function public.referral_decide(text, boolean, text) to authenticated, service_role;

-- Moliya navbati: to'lov kutilayotgan tavsiyalar + birinchi to'lov ma'lumoti (summa, sana).
create or replace function public.referral_queue() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v jsonb;
begin
  if not (app.is_admin() or app.is_finance_mgr()) then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'referrerId', r."referrerId", 'status', r.status, 'legacy', r.legacy,
           'createdAt', r."createdAt", 'payment', (select jsonb_build_object('id', p.id, 'amount', p.amount, 'at', p."createdAt", 'provider', p.provider)
                                                     from public.payments p where p.id = (select f.pid from app.first_real_payment(r.id) f)))
         order by r."createdAt"), '[]'::jsonb) into v
    from public.referral_requests r where r.status = 'pending_payment';
  return v;
end $$;
revoke all on function public.referral_queue() from public, anon;
grant execute on function public.referral_queue() to authenticated, service_role;

-- To'lov bekor / qaytarildi → hali qo'llanmagan tasdiqlangan tavsiya bekor (qo'llangan bo'lsa — Direktorga ogohlantirish).
create or replace function app.referral_payment_revoke() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  -- 'applied' / 'confirmed' (Uzum) ham birinchi to'lov bo'la oladi (app.first_real_payment); 'refunded' — pul qaytarilgan.
  if coalesce(old.status, '') in ('paid', 'applied', 'confirmed') and coalesce(new.status, '') in ('canceled', 'reversed', 'refunded') then
    begin
      update public.referral_requests set status = 'revoked', "decisionNote" = coalesce("decisionNote", '') || ' [birinchi to''lov bekor/qaytarildi]'
       where "firstPaymentId" = new.id and status = 'approved';
      update public.referral_requests set "revokeWarn" = true
       where "firstPaymentId" = new.id and status = 'applied';
    exception when others then
      raise warning 'referral_payment_revoke: %', sqlerrm;   -- to'lov yangilanishi HECH QACHON shu sababli to'xtamasin
    end;
  end if;
  return new;
end $$;
revoke all on function app.referral_payment_revoke() from public, anon, authenticated;
drop trigger if exists trg_referral_payment_revoke on public.payments;
create trigger trg_referral_payment_revoke after update of status on public.payments
  for each row execute function app.referral_payment_revoke();

-- Faktura qaytarishi (refund_invoice('invoice')) to'lov holatini o'zgartirmaydi -> yuqoridagi trigger sezmaydi. Qaytarishdan keyin
--   yangi o'quvchining SOF puli 0 yoki kam bo'lsa: hali qo'llanmagan tasdiqlangan tavsiya bekor, qo'llangani — Direktorga ogohlantirish.
create or replace function app.referral_refund_revoke() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if coalesce(new."studentId", '') <> '' then
    begin
      if app.student_real_net(new."studentId") <= 0 then
        update public.referral_requests set status = 'revoked', "decisionNote" = coalesce("decisionNote", '') || ' [to''lov qaytarildi — sof to''lov 0]'
         where id = new."studentId" and status = 'approved';
        update public.referral_requests set "revokeWarn" = true
         where id = new."studentId" and status = 'applied';
      end if;
    exception when others then
      raise warning 'referral_refund_revoke: %', sqlerrm;   -- qaytarish HECH QACHON shu sababli to'xtamasin
    end;
  end if;
  return new;
end $$;
revoke all on function app.referral_refund_revoke() from public, anon, authenticated;
drop trigger if exists trg_referral_refund_revoke on public.refunds;
create trigger trg_referral_refund_revoke after insert on public.refunds
  for each row execute function app.referral_refund_revoke();

-- Ledger: o'tish oyidan boshlab faqat tasdiqlangan tavsiya; yozilgach — applied.
create or replace function app.referral_ledger_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_from text; r public.referral_requests%rowtype;
begin
  select nullif(btrim(coalesce(c."discountApprovalFrom", '')), '') into v_from from public.config c where c.id = 'finance';
  if v_from is null or coalesce(new.month, '') < v_from then return new; end if;
  select * into r from public.referral_requests where id = new.id;
  if not found or r.status not in ('approved', 'applied') or r."referrerId" is distinct from new."referrerId" then
    raise exception 'Tavsiya bonusi faqat Moliya menejeri tasdiqlagan tavsiya bilan (%)', new.id using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function app.referral_ledger_guard() from public, anon, authenticated;
drop trigger if exists trg_referral_ledger_guard on public.referral_ledger;
create trigger trg_referral_ledger_guard before insert or update on public.referral_ledger
  for each row execute function app.referral_ledger_guard();
create or replace function app.referral_ledger_applied() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  update public.referral_requests set status = 'applied', "appliedAt" = coalesce("appliedAt", now()) where id = new.id and status = 'approved';
  return new;
end $$;
revoke all on function app.referral_ledger_applied() from public, anon, authenticated;
drop trigger if exists trg_referral_ledger_applied on public.referral_ledger;
create trigger trg_referral_ledger_applied after insert or update on public.referral_ledger
  for each row execute function app.referral_ledger_applied();

-- 6) Fakturalar: maydonlar himoyasi + (o'tish oyidan) tasdiq ishoralari
alter table public.invoices add column if not exists "approvalRefs" jsonb;
create or replace function app.invoice_discount_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_from text; v_creators text; v_refs jsonb; v_ref text; r public.discount_requests%rowtype; v_need text;
        v_kinds text[] := '{}'; v_changed boolean; v_camt numeric[] := '{}';
begin
  -- a) Kim yozadi: Direktordan boshqasi (moliya, kassa) faqat to'lov maydonlari; reprice_invoice RPC — bayroq bilan.
  if not app.is_system() and not app.is_admin() and coalesce(current_setting('iqror.inv_reprice', true), '') <> '1' then
    if tg_op = 'INSERT' then
      select coalesce(nullif(c."invoiceCreators", ''), 'director') into v_creators from public.config c where c.id = 'finance';
      if not (coalesce(v_creators, 'director') = 'director_finance' and app.has_role('finance_mgr')) then
        raise exception 'Hisob-fakturani faqat Direktor yaratadi (sozlama: «Hisob-faktura yaratish»)' using errcode = '42501';
      end if;
    elsif new.amount is distinct from old.amount or new."baseAmount" is distinct from old."baseAmount" or new.discount is distinct from old.discount
       or new."discountInfo" is distinct from old."discountInfo" or new."pctApplied" is distinct from old."pctApplied"
       or new."isGrant" is distinct from old."isGrant" or new."sickDaysApplied" is distinct from old."sickDaysApplied"
       or new."sickAmount" is distinct from old."sickAmount" or new."sickNoteRefs" is distinct from old."sickNoteRefs"
       or new."bonusRef" is distinct from old."bonusRef" or new."approvalRefs" is distinct from old."approvalRefs"
       or new."referralUsedIds" is distinct from old."referralUsedIds" or new.month is distinct from old.month
       or new."studentId" is distinct from old."studentId" or new."priceKey" is distinct from old."priceKey"
       or new."billedFrom" is distinct from old."billedFrom" or new."billedTo" is distinct from old."billedTo" then
      raise exception 'Hisob-faktura summasi / chegirmasini faqat Direktor yoki «↻ Qayta hisoblash» o''zgartiradi (to''lov maydonlari — mumkin)' using errcode = '42501';
    end if;
  end if;
  -- b) O'tish oyidan: grant / ≥50% / kontrakt — amaldagi tasdiqlangan so'rov bilan.
  if tg_op = 'UPDATE' then
    v_changed := new."approvalRefs" is distinct from old."approvalRefs" or new."pctApplied" is distinct from old."pctApplied"
              or new."isGrant" is distinct from old."isGrant" or new."discountInfo" is distinct from old."discountInfo"
              or new."baseAmount" is distinct from old."baseAmount" or new.month is distinct from old.month
              or new."studentId" is distinct from old."studentId" or new."bonusRef" is distinct from old."bonusRef";
    if not v_changed then return new; end if;
  end if;
  select nullif(btrim(coalesce(c."discountApprovalFrom", '')), '') into v_from from public.config c where c.id = 'finance';
  if v_from is null or coalesce(new.month, '') < v_from then return new; end if;
  v_refs := case when jsonb_typeof(new."approvalRefs") = 'array' then new."approvalRefs" else '[]'::jsonb end;
  for v_ref in select x from jsonb_array_elements_text(v_refs) x loop
    select * into r from public.discount_requests where id = v_ref;
    if not found or r.status <> 'approved' or r."studentId" is distinct from new."studentId"
       or (r."fromMonth" is not null and new.month < r."fromMonth") or (r."toMonth" is not null and new.month > r."toMonth") then
      raise exception 'Hisob-fakturadagi chegirma tasdig''i (%) amalda emas yoki boshqa o''quvchiniki', v_ref using errcode = '23514';
    end if;
    v_kinds := v_kinds || r.kind;
    if r.kind = 'contract' then v_camt := v_camt || (r.params->>'contractAmount')::numeric; end if;
  end loop;
  v_need := case
    when coalesce(new."isGrant", false) and coalesce(new."bonusRef", '') = '' and coalesce(new."pctApplied", 0) >= 1
         and coalesce(new."discountInfo", '') not ilike 'Monitoring 100%' then 'grant'   -- monitoring-100: bonus-100.sql qoidasi
    when coalesce(new."pctApplied", 0) >= 0.5 and coalesce(new."pctApplied", 0) < 1 then 'teacher_child'
    when coalesce(new."discountInfo", '') ilike 'Kontrakt%' then 'contract'
    else null end;
  if v_need = 'grant' and not (v_kinds && array['olympiad', 'social']) then
    raise exception '100%% grant faqat Direktor va Moliya menejeri tasdiqlagan so''rov bilan' using errcode = '23514';
  elsif v_need = 'teacher_child' and not (v_kinds && array['teacher_child']) then
    raise exception 'Xodim farzandi chegirmasi faqat tasdiqlangan so''rov bilan' using errcode = '23514';
  elsif v_need = 'contract' and not (round(coalesce(new."baseAmount", -1)) = any(array(select round(x) from unnest(v_camt) x))) then
    raise exception 'Kontrakt summasi faqat tasdiqlangan so''rovdagi summa bilan' using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function app.invoice_discount_guard() from public, anon, authenticated;
drop trigger if exists trg_invoice_discount_guard on public.invoices;
create trigger trg_invoice_discount_guard before insert or update on public.invoices
  for each row execute function app.invoice_discount_guard();

-- 7) O'zgarishlar tarixi
select app.chlog_attach('discount_requests', 'studentId,kind,params,fromMonth,toMonth,status,directorOk,directorNote,financeOk,financeNote');
select app.chlog_attach('referral_requests', 'referrerId,status,firstPaymentId,decisionNote,revokeWarn');
select app.chlog_attach('invoices',          'studentId,month,amount,paidAmount,status,baseAmount,discount,discountInfo,pctApplied,isGrant,sickAmount,sickDaysApplied,sickNoteRefs,bonusRef,approvalRefs,referralUsedIds,billedFrom,billedTo');
select app.chlog_attach('config',            '!refundPin,sickRate,sickApprovalFrom,bonusApprovalFrom,discountApprovalFrom,invoiceCreators,referralAmount,payrollApprovalFrom,entryDeadlineDay,lessonRate,latePenalty,earlyPenalty,allowedBreakMin,breakPenaltyPerHour,clickServiceId,clickMerchantId,uzumUrlTemplate,flatAmount,perYear,monthsPerYear,tenureYears,yearsCap,degree,category,languages,russian,langLevel');

notify pgrst, 'reload schema';
