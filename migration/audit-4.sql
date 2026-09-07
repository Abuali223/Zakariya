-- =====================================================================
-- AUDIT-4 — 2026-09 to'liq audit tuzatmalari (P0 + P1 baza qatlami).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/audit-4.sql
-- Idempotent. run-all.sql'da ENG OXIRGI ishlaydi (barcha jadval/funksiya mavjud).
-- =====================================================================

-- =====================================================================
-- A-07 [P0] students_public / teachers_public / student_phones view'lari
--   avto-yangilanuvchi (bitta jadval, WHERE'siz) va egasi postgres (security
--   definer). supabase-grants.sql anon/authenticated'ga BARCHA jadvallarga
--   (view'larga ham) INSERT/UPDATE/DELETE bergan -> login qilmagan har kim
--   `DELETE /rest/v1/students_public` bilan RLS'ni chetlab o'tib butun
--   o'quvchi/o'qituvchi ro'yxatini o'chira/o'zgartira olardi.
-- TUZATISH: public sxemasidagi HAR BIR view'dan anon/authenticated uchun
--   INSERT/UPDATE/DELETE ni olib tashlaymiz (SELECT qoladi — ommaviy o'qish
--   ishlaydi). Jadvallar tegilmaydi (ular RLS bilan himoyalangan).
-- =====================================================================
do $$
declare v record;
begin
  for v in select table_name from information_schema.views where table_schema = 'public' loop
    execute format('revoke insert, update, delete on public.%I from anon, authenticated', v.table_name);
  end loop;
end $$;
-- ILDIZ SABAB (revyu M-1): supabase-grants.sql'daги `alter default privileges ... on tables`
--   KELAJAKDAGI har bir view'ga ham anon/authenticated uchun DML beradi (Postgres "TABLES"
--   default-privilege view'ni qamraydi) -> yangi view qo'shilishi bilan A-07 teshigi QAYTA
--   ochilardi. Buni event trigger bilan ILDIZDAN yopamiz: har CREATE VIEW'дан keyin o'sha
--   view'дан anon/authenticated DML'i AVTOMATIK olib tashlanadi. (Jadval grantlariga tegmaymiz —
--   ko'p jadval yozuvи default-privilege'ga tayanadi.)
create or replace function app.revoke_view_dml() returns event_trigger
  language plpgsql security definer set search_path = public, pg_temp as $$
declare r record;
begin
  for r in select object_identity from pg_event_trigger_ddl_commands()
           where command_tag in ('CREATE VIEW','CREATE MATERIALIZED VIEW') loop
    begin
      execute format('revoke insert, update, delete on %s from anon, authenticated', r.object_identity);
    exception when others then null; end;
  end loop;
end $$;
drop event trigger if exists trg_revoke_view_dml;
create event trigger trg_revoke_view_dml on ddl_command_end
  when tag in ('CREATE VIEW','CREATE MATERIALIZED VIEW')
  execute function app.revoke_view_dml();

-- =====================================================================
-- A-06 [P0] Farzand biriktirish kodini brute-force. Mavjud o'quvchilar kodi
--   6 hex belgi (24 bit ~ 16.7 mln) edi, urinish cheklovi/lockout YO'Q,
--   studentId'lar students_public orqali anonga ochiq -> begona bola PII
--   (JSHSHIR/manzil/sog'liq) bir necha soatda ochilishi mumkin.
-- TUZATISH: (1) barcha kodlarni 12 hex belgiga (48 bit) qayta generatsiya;
--   (2) to'g'ridan-to'g'ri child_claims INSERT'ni YOPAMIZ; biriktirish faqat
--   public.claim_child(sid, code) RPC orqali — urinishlar jurnali + lockout
--   (15 daqiqada 5 xato -> vaqtinchalik bloklash). Mavjud biriktirmalar
--   (child_claims qatorlari) SAQLANADI — owns_child ularga tayanadi, kod
--   qayta generatsiyasi ulangan ota-onalarni uzmaydi.
-- =====================================================================
-- (1) entropiyani oshirish — 12 hex (mavjud+yangi). Trigger ham 12 ga o'tadi.
update public.student_codes
   set code = upper(substr(md5(random()::text || id || clock_timestamp()::text), 1, 12)),
       "updatedAt" = now()
 where coalesce(length(code),0) < 12;
create or replace function app.gen_student_code() returns trigger language plpgsql security definer as $$
begin
  insert into public.student_codes(id, code)
    values (NEW.id, upper(substr(md5(random()::text || NEW.id || clock_timestamp()::text), 1, 12)))
    on conflict (id) do nothing;
  return NEW;
end $$;

-- (2) urinishlar jurnali (lockout uchun). Mijozga UMUMAN yopiq (RLS on, policy yo'q).
create table if not exists public.child_claim_attempts(
  id        bigint generated always as identity primary key,
  uid       text,
  "studentId" text,
  ok        boolean,
  "at"      timestamptz default now()
);
create index if not exists cca_uid_at on public.child_claim_attempts(uid, "at");
alter table public.child_claim_attempts enable row level security;
grant all on public.child_claim_attempts to service_role;

-- claim_child: yagona biriktirish yo'li. SECURITY DEFINER -> child_claims RLS'ni
--   chetlab o'tadi, lekin lockout + kod tekshiruvi ichkarida majburlanadi.
-- Kod katta-kichik harfga SEZGIR bo'lmasin (revyu m-2): kodlar upper(md5) bilan KATTA
-- saqlanadi; ota-ona kichik harfда kiritsa ham to'g'ri hisoblansin (aks holда noto'g'ri
-- "xato" sanalib lockout'ga olib kelardi).
create or replace function app.code_ok(sid text, c text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.student_codes where id = sid and upper(code) = upper(c) and coalesce(c,'') <> '')
$$;

create or replace function public.claim_child(p_sid text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_fails int; v_ok boolean;
begin
  if v_uid is null then
    raise exception 'auth required' using errcode = '42501';
  end if;
  -- Lockout: oxirgi 15 daqiqada 5+ MUVAFFAQIYATSIZ urinish -> bloklash.
  select count(*) into v_fails
    from public.child_claim_attempts
   where uid = v_uid and ok = false and "at" > now() - interval '15 minutes';
  if v_fails >= 5 then
    insert into public.child_claim_attempts(uid, "studentId", ok) values (v_uid, p_sid, false);
    return jsonb_build_object('ok', false, 'locked', true,
      'error', 'Juda ko''p urinish. 15 daqiqadan so''ng qayta urinib ko''ring.');
  end if;
  v_ok := app.code_ok(p_sid, p_code);
  insert into public.child_claim_attempts(uid, "studentId", ok) values (v_uid, p_sid, v_ok);
  if not v_ok then
    return jsonb_build_object('ok', false, 'error', 'O''quvchi ID yoki kod noto''g''ri.');
  end if;
  insert into public.child_claims(id, uid, "studentId", code)
    values (v_uid || '__' || p_sid, v_uid, p_sid, p_code)
    on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.claim_child(text, text) to authenticated;

-- To'g'ridan-to'g'ri client INSERT endi YOPIQ (faqat claim_child RPC orqali).
drop policy if exists cc_ins on public.child_claims;
create policy cc_ins on public.child_claims for insert with check (false);

-- =====================================================================
-- A-02 / A-03 [P0] Saqlangan XSS (asosiy tuzatish frontend esc()'da). Baza
--   tomonda mudofaa: yangi yozuvlarda status/month faqat xavfsiz shakl.
--   NOT VALID -> faqat YANGI/o'zgargan qatorlar tekshiriladi (mavjud data
--   buzilmaydi, migratsiya xato bermaydi).
-- =====================================================================
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'enr_status_chk') then
    alter table public.enrollments
      add constraint enr_status_chk check (status is null or status ~ '^[A-Za-z_]+$') not valid;
  end if;
exception when others then null; end $$;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'inv_month_chk') then
    alter table public.invoices
      add constraint inv_month_chk check (month is null or month ~ '^[0-9]{4}-[0-9]{2}$') not valid;
  end if;
exception when others then null; end $$;

-- =====================================================================
-- A-01 / A-05 [P0] + finance[1]/finance[2] — To'lov waterfall ATOMIK EMAS edi:
--   klientda har invoys alohida setDoc; qisman yozuvdan keyin xato bo'lsa
--   posbon (applied_payments) o'chirilib, qayta urinishда summa TAKROR
--   qo'llanardi (double-count); yoki posbon yozilib javob yo'qolsa to'lov
--   "qo'llandi" ko'rsatilib, aslida invoys yangilanmasdi (pul yo'qoladi).
-- TUZATISH: butun waterfall'ni BITTA tranzaksiyada bajaradigan SECURITY
--   DEFINER funksiya. applied_payments'ga INSERT ... ON CONFLICT DO NOTHING —
--   dup bo'lsa QAYTA qo'llamaydi. Xato bo'lsa BUTUN tranzaksiya (posbon ham)
--   qaytariladi -> qayta urinish xavfsiz. Klient shu RPC'ni chaqiradi.
-- =====================================================================
create or replace function public.apply_payment(p_sid text, p_amount numeric, p_provider text, p_pay_id text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_credit numeric := 0;
  v_available numeric;
  v_provider text;
  v_inserted int := 0;
  v_pay numeric;
  v_newpaid numeric;
  v_full boolean;
  v_delta numeric;
  v_name text;
  v_claims jsonb;
  inv record;
begin
  -- Ruxsat: faqat to'lov oluvchilar (kassir/moliya/direktor) yoki server (service_role).
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance() or app.is_cashier()
          or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  p_amount := coalesce(p_amount, 0);
  if p_amount < 0 then return jsonb_build_object('ok', false, 'reason', 'neg'); end if;
  v_provider := coalesce(nullif(p_provider, ''), case when p_amount > 0 then 'click' else 'credit' end);

  -- Idempotentlik: posbonni AVVAL o'rnatamiz. Allaqachon bo'lsa -> dup, qayta qo'llamaymiz.
  if p_pay_id is not null and p_pay_id <> '' then
    insert into public.applied_payments(id, "studentId", amount, "createdAt")
      values (p_pay_id, p_sid, p_amount, now())
      on conflict (id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted = 0 then
      return jsonb_build_object('dup', true);
    end if;
  end if;

  -- Shu o'quvchi bo'yicha BARCHA to'lovlarni seriyalash (yangi o'quvchida student_credit
  -- qatori hali yo'q -> FOR UPDATE qulflay olmaydi; advisory lock poygani to'liq yopadi).
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(p_sid, '')));

  -- Joriy avans.
  select coalesce(credit, 0) into v_credit from public.student_credit where id = p_sid for update;
  if not found then v_credit := 0; end if;
  v_available := p_amount + coalesce(v_credit, 0);

  -- Waterfall: eng eski (oy bo'yicha) to'lanmagan invoysdan boshlab; qulflaymiz.
  -- MUHIM: status IS NULL (eski/import qilingan) invoyslar ham TO'LANMAGAN hisoblanadi
  -- (SQL 3-qiymatli mantiqda `null not in (...)` = null, ya'ni chiqib ketardi — eski klient
  -- esa ularni kiritardi). Tartib: month bo'sh/null bo'lsa id (eski klient `month||id` kabi).
  for inv in
    select id, coalesce(amount, 0) as amount, coalesce("paidAmount", 0) as paid
      from public.invoices
     where "studentId" = p_sid and (status is null or status not in ('paid', 'canceled', 'reversed'))
     order by coalesce(nullif(month, ''), id) asc
     for update
  loop
    exit when v_available <= 0;
    if (inv.amount - inv.paid) <= 0 then continue; end if;
    v_pay := least(v_available, inv.amount - inv.paid);
    v_newpaid := inv.paid + v_pay;
    v_full := v_newpaid >= inv.amount - 0.5;
    update public.invoices
       set "paidAmount" = v_newpaid,
           status = case when v_full then 'paid' else 'partial' end,
           provider = v_provider,
           "paidAt" = case when v_full then now() else "paidAt" end
     where id = inv.id;
    v_available := v_available - v_pay;
  end loop;

  -- Avansni yozamiz (ortiqcha to'lov keyingi oyga).
  insert into public.student_credit(id, "studentId", credit, "updatedAt")
    values (p_sid, p_sid, v_available, now())
    on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();

  -- Avans harakati jurnali (izlanish uchun).
  v_delta := v_available - coalesce(v_credit, 0);
  if abs(v_delta) >= 0.5 then
    select name into v_name from public.students where id = p_sid or "studentId" = p_sid limit 1;
    insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, provider, "at")
      values (gen_random_uuid()::text, p_sid, coalesce(v_name, ''), v_delta, v_available,
              case when v_delta > 0 then 'overpay' else 'applied' end, v_provider, now());
  end if;

  return jsonb_build_object('ok', true, 'credit', v_available);
end $$;
grant execute on function public.apply_payment(text, numeric, text, text) to authenticated, service_role;

-- =====================================================================
-- P1 — "UI ko'rsatadi, DB rad etadi" (setDoc=UPSERT -> INSERT policy'ga uriladi
--   yoki rol qamralmagan). Bu yerda rol LEGITIM bo'lgan amallarga DB huquqi
--   beramiz. Buzg'unchi (destruktiv) o'chirishlar (o'quvchi/o'qituvchi/invoys/
--   ariza) direktorда qoladi — ular uchun UI tugmasi yashiriladi (frontend).
-- =====================================================================

-- roles[0] feedback: holat/javob endi frontend'да updateDoc (PATCH) bilan yoziladi ->
--   fb_upd (admin/admin_head, allaqachon bor) ishlaydi. fb_ins'ni KENGAYTIRMAYMIZ
--   (uid = app.uid() qoladi) — aks holda admin begona uid nomidan murojaat "yoza" olardi
--   (mualliflikni soxtalashtirish, revyu m-1). Faqat o'z nomidan insert.
drop policy if exists fb_ins on public.feedback;
create policy fb_ins on public.feedback for insert
  with check (uid = app.uid());

-- roles[6] expenses: moliya menejeri/g'aznachi xarajatni o'chira olsin (yaratadi ham).
drop policy if exists exp_del on public.expenses;
create policy exp_del on public.expenses for delete
  using (app.is_admin() or app.is_cashier() or app.is_finance());

-- roles[7] config/finance (Narx jadvali — kasal stavkasi): moliya menejeri saqlaydi.
drop policy if exists cfg_finance_fin_ins on public.config;
create policy cfg_finance_fin_ins on public.config for insert
  with check (app.is_finance() and id = 'finance');
drop policy if exists cfg_finance_fin_upd on public.config;
create policy cfg_finance_fin_upd on public.config for update
  using (app.is_finance() and id = 'finance') with check (app.is_finance() and id = 'finance');

-- roles[10] config/salary: kassir (payroll/maosh xarajatini hisoblaydi) O'QISIN.
--   (audit-2 config_sel'ni kassirsiz cheklagan edi.) can_see_salary = admin/hr/finance/kassir.
drop policy if exists config_sel on public.config;
create policy config_sel on public.config for select using (
      (id = 'salary'   and app.can_see_salary())
   or (id = 'security' and app.is_admin())
   or (id in ('finance','ltv') and app.is_staff())
   or (id not in ('salary','finance','ltv','security'))
);

-- roles[11] secrets: direktor AI kalitini saqlay/o'qiy olsin (RLS on, policy yo'q edi).
--   (Ishlab chiqarishда kalit server ENV/vault'da bo'lgani ma'qul — bu UI qulayligi uchun.)
drop policy if exists secrets_sel on public.secrets;
create policy secrets_sel on public.secrets for select using (app.is_admin());
drop policy if exists secrets_ins on public.secrets;
create policy secrets_ins on public.secrets for insert with check (app.is_admin());
drop policy if exists secrets_upd on public.secrets;
create policy secrets_upd on public.secrets for update using (app.is_admin()) with check (app.is_admin());
drop policy if exists secrets_del on public.secrets;
create policy secrets_del on public.secrets for delete using (app.is_admin());

-- roles[9] grades: O'IBDO' (zavuch) baholar jurnalini ko'radi/yozadi (butun maktab).
--   (rls.sql grades_* zavuch'ni qamramagan edi.)
drop policy if exists grades_sel on public.grades;
create policy grades_sel on public.grades for select
  using (app.is_admin() or app.is_zavuch() or app.owns_child("studentId") or app.is_teacher_for_class("classKey"));
drop policy if exists grades_ins on public.grades;
create policy grades_ins on public.grades for insert
  with check (app.is_admin() or app.is_zavuch() or app.is_teacher_for_class("classKey"));
drop policy if exists grades_upd on public.grades;
create policy grades_upd on public.grades for update
  using (app.is_admin() or app.is_zavuch() or app.is_teacher_for_class("classKey"))
  with check (app.is_admin() or app.is_zavuch() or app.is_teacher_for_class("classKey"));

-- roles[4] storage: HR o'qituvchi rasmini yuklay olsin (storage.objects INSERT
--   admin-only edi). storage sxemasi faqat Supabase'da mavjud -> guard bilan.
do $$ begin
  drop policy if exists iqror_admin_insert on storage.objects;
  create policy iqror_admin_insert on storage.objects for insert
    with check ( bucket_id = 'public' and (app.is_admin() or app.is_hr() or app.is_zavuch()) );
exception when undefined_table then null; when undefined_object then null; when others then null; end $$;   -- storage sxemasi yo'q bo'lsa (invalid_schema_name 3F000) -> 'others' tutadi

-- rls[7]/roles[15]: avans harakati jurnalini (credit_ledger) moliya/kassir/zavuch ham O'QISIN —
--   ular "To'lov/avans tarixi" va Buxgalteriyani yuritadi (ilgari faqat direktor+ota-ona ko'rardi).
drop policy if exists cl_sel on public.credit_ledger;
create policy cl_sel on public.credit_ledger for select
  using (app.is_admin() or app.is_finance() or app.is_cashier() or app.is_zavuch() or app.owns_child("studentId"));

-- roles[23]: kassir Buxgalteriyada «Qaytarilgan» (refunds) summasini ko'rsin (kirim/chiqimni kassir yuritadi).
--   (audit-3 refunds_sel = admin/finance/zavuch edi; kassirni qo'shamiz.)
drop policy if exists refunds_sel on public.refunds;
create policy refunds_sel on public.refunds for select
  using (app.is_admin() or app.is_finance() or app.is_zavuch() or app.is_cashier());

notify pgrst, 'reload schema';
