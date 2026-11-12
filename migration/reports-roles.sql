\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: reports-roles.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- reports-roles.sql — PKG-11: IKKINCHI LAVOZIM (users."extraRoles"), oshxona menyusi, «Reja va tushum», direktorning
--   haftalik ko'rsatkichlari va pul qoidalari tekshiruvi.
--   * Ikkinchi lavozim: Direktor xodimga qo'shimcha rol beradi (o'qituvchi + qabulxona, HR + kassa ...). Barcha rol
--     yordamchilari (app.is_*, has_role, sinf predikatlari) ASOSIY rol YOKI FAOL qo'shimcha rolni hisobga oladi —
--     yagona app.role_set() orqali. Director, finance_mgr (va treasurer, admin, accountant) qo'shimcha rol BO'LA OLMAYDI;
--     Direktor, ota-ona, o'quvchi va buxgalterga (F1.21) qo'shimcha rol berilmaydi. Faqat Direktor beradi/oladi (o'zi o'ziga — yo'q); change_log.
--     Olib tashlansa — huquq DARHOL yo'qoladi (har so'rovda bazadan o'qiladi). Ikki kishilik tasdiqlarda bitta odam
--     ikkala bosqichni to'ldira olmaydi: chegirma, maosh, «Bemor» kuni — uid bo'yicha (avvaldan); monitoring balli —
--     qo'shimcha O'IBDO' roli bilan o'zi kiritgan ballni tasdiqlay olmaydi (shu faylda); qo'shimcha HR rolli xodimning o'z
--     maoshi — Direktor tasdig'ida (shu faylda).
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Ikkinchi lavozim
alter table public.users add column if not exists "extraRoles" jsonb not null default '[]'::jsonb;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'users_extra_roles_chk') then
    alter table public.users add constraint users_extra_roles_chk check (jsonb_typeof("extraRoles") = 'array');
  end if;
end $$;

-- Qo'shimcha bo'la oladigan rollar (director / finance_mgr / treasurer / admin / parent / student / accountant — YO'Q).
--   Qo'shimcha OLA OLMAYDIGAN asosiy rollar (pastdagi u_has, role_set, users_extra_roles_guard va admin.html bilan bir xil):
--   director, parent, student, rolsiz va accountant (buxgalter kassirni nazorat qiladi — vazifalar ajratilishi; qo'shimcha
--   kassir / qabulxona / HR o'quvchi va xodim ma'lumotini ham ochardi — D6; moliya rejasi F1.21).
create or replace function app.extra_roles_allowed() returns text[]
language sql immutable set search_path = pg_catalog as $$
  select array['teacher', 'kurator', 'reception', 'hr', 'kassir', 'nurse', 'marketing_mgr', 'admin_head', 'zavuch']::text[]
$$;
-- Bitta foydalanuvchi qatori bo'yicha: asosiy rol r mi yoki (qo'shimcha olish mumkin bo'lgan asosiy rolda) qo'shimcha r bormi.
create or replace function app.u_has(p_role text, p_extra jsonb, r text) returns boolean
language sql immutable set search_path = pg_catalog as $$
  select coalesce(p_role = r, false)
      or (coalesce(p_role, '') not in ('director', 'parent', 'student', 'accountant', '') and r = any(app.extra_roles_allowed())
          and jsonb_typeof(p_extra) = 'array' and p_extra ? r)
$$;
-- Joriy foydalanuvchining FAOL rollari: [asosiy, ...qo'shimchalar]. Faol bo'lmagan / bloklangan / noma'lum — bo'sh.
create or replace function app.role_set() returns text[]
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((
    select case
             when coalesce(u.role, '') = '' then '{}'::text[]
             when u.role in ('director', 'parent', 'student', 'accountant') then array[u.role]
             else array[u.role] || coalesce(array(
                    select distinct e from jsonb_array_elements_text(case when jsonb_typeof(u."extraRoles") = 'array' then u."extraRoles" else '[]'::jsonb end) e
                     where e = any(app.extra_roles_allowed()) and e <> u.role), '{}'::text[])
           end
      from public.users u
     where u.id = app.uid() and coalesce(nullif(u.status, ''), 'active') = 'active'), '{}'::text[])
$$;
do $$ declare f text; begin
  foreach f in array array['app.extra_roles_allowed()', 'app.u_has(text, jsonb, text)', 'app.role_set()'] loop
    execute 'revoke all on function ' || f || ' from public';
    execute 'grant execute on function ' || f || ' to anon, authenticated, service_role';
  end loop;
end $$;

-- 2) Rol yordamchilari — asosiy YOKI faol qo'shimcha rol. app.is_admin() va app.my_role() O'ZGARMAYDI (Direktor — faqat
--    asosiy rol; my_role — asosiy rol, ko'rsatish uchun). Grantlar «create or replace» bilan saqlanadi.
create or replace function app.has_role(p_role text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(p_role = any(app.role_set()), false)
$$;
create or replace function app.is_zavuch() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select 'zavuch' = any(app.role_set())
$$;
create or replace function app.is_staff() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.role_set() && array['admin', 'director', 'zavuch', 'kurator', 'teacher', 'hr', 'admin_head', 'finance_mgr', 'treasurer', 'marketing_mgr', 'reception']::text[]
$$;
create or replace function app.is_teacher_for_class(ck text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select exists(select 1 from public.users u where u.id = app.uid() and coalesce(nullif(u.status, ''), 'active') = 'active'
                   and app.u_has(u.role, u."extraRoles", 'teacher') and coalesce(u."assignedClasses", '[]'::jsonb) ? ck)
$$;
create or replace function app.is_homeroom_for(ck text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select exists(select 1 from public.users u where u.id = app.uid() and coalesce(nullif(u.status, ''), 'active') = 'active'
                   and (u.role = 'admin' or app.u_has(u.role, u."extraRoles", 'zavuch') or app.u_has(u.role, u."extraRoles", 'kurator')
                        or app.u_has(u.role, u."extraRoles", 'teacher'))
                   and coalesce(u."homeroomClasses", '[]'::jsonb) ? ck)
$$;
create or replace function app.is_kurator_for(ck text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select exists(select 1 from public.users u where u.id = app.uid() and coalesce(nullif(u.status, ''), 'active') = 'active'
                   and app.u_has(u.role, u."extraRoles", 'kurator') and coalesce(u."assignedClasses", '[]'::jsonb) ? ck)
$$;
create or replace function app.is_cashier() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select 'kassir' = any(app.role_set())
$$;
create or replace function app.is_admin_head() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.role_set() && array['director', 'admin', 'admin_head']::text[]
$$;
create or replace function app.is_hr() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.role_set() && array['director', 'hr']::text[]
$$;
create or replace function app.is_finance() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.role_set() && array['director', 'finance_mgr', 'treasurer']::text[]
$$;
create or replace function app.is_marketing() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.role_set() && array['director', 'marketing_mgr']::text[]
$$;
create or replace function app.is_reception() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select 'reception' = any(app.role_set())
$$;
create or replace function app.is_nurse() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select 'nurse' = any(app.role_set())
$$;
create or replace function app.is_finance_mgr() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.role_set() && array['director', 'finance_mgr']::text[]
$$;

-- 3) users: qo'shimcha rolni faqat Direktor (yoki server) o'zgartiradi; qiymatlar tekshiriladi, takror/asosiy rol olib
--    tashlanadi; asosiy rol Direktor/ota-ona/o'quvchi/buxgalter bo'lib qolsa — qo'shimchalar avtomatik tozalanadi. Bloklangan hisob
--    (status blocked) — qo'shimchalar saqlanadi (role_set baribir bo'sh; blokdan chiqqanda tiklanadi).
create or replace function app.users_extra_roles_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v jsonb; e text; v_out text[] := '{}'; v_changed boolean;
begin
  v_changed := case when tg_op = 'INSERT' then coalesce(new."extraRoles", '[]'::jsonb) <> '[]'::jsonb
                    else new."extraRoles" is distinct from old."extraRoles" end;
  if v_changed and not app.is_system() and not app.is_admin() then
    raise exception 'Qo''shimcha lavozimni faqat Direktor beradi' using errcode = '42501';
  end if;
  if v_changed and not app.is_system() and new.id = app.uid() then
    raise exception 'O''zingizga qo''shimcha lavozim berib bo''lmaydi' using errcode = '42501';
  end if;
  v := coalesce(new."extraRoles", '[]'::jsonb);
  if jsonb_typeof(v) <> 'array' then raise exception 'Qo''shimcha lavozimlar ro''yxat bo''lishi kerak' using errcode = '22023'; end if;
  if coalesce(new.status, '') = 'blocked' and not v_changed then return new; end if;
  if coalesce(new.role, '') in ('director', 'parent', 'student', 'accountant', '') then
    if jsonb_array_length(v) > 0 then
      if v_changed then raise exception 'Bu asosiy rolga qo''shimcha lavozim berilmaydi' using errcode = '22023'; end if;
      new."extraRoles" := '[]'::jsonb;   -- asosiy rol o'zgardi (masalan, Direktor bo'ldi) — qo'shimchalar bekor
    end if;
    return new;
  end if;
  for e in select x from jsonb_array_elements(v) x0, lateral (select x0 #>> '{}' as x) y loop
    if e is null or not (e = any(app.extra_roles_allowed())) then
      raise exception 'Qo''shimcha lavozim sifatida berib bo''lmaydi: %', coalesce(e, 'null') using errcode = '22023';
    end if;
    if e <> new.role and not (e = any(v_out)) then v_out := v_out || e; end if;
  end loop;
  new."extraRoles" := to_jsonb(v_out);
  return new;
end $$;
revoke all on function app.users_extra_roles_guard() from public, anon, authenticated;
drop trigger if exists trg_users_extra_roles on public.users;
create trigger trg_users_extra_roles before insert or update on public.users
  for each row execute function app.users_extra_roles_guard();
-- Buxgalter qo'shimcha lavozimsiz (F1.21): oldin berilgan bo'lsa — bir martalik tozalash (zanjir — tizim nomidan; idempotent).
update public.users set "extraRoles" = '[]'::jsonb
 where role = 'accountant' and coalesce("extraRoles", '[]'::jsonb) <> '[]'::jsonb;

-- users_upd / users_ins: o'z qatorini tahrirlashda qo'shimcha rol ham O'ZGARMASIN (staff-user-link.sql dagi ro'yxat + extraRoles).
drop policy if exists users_upd on public.users;
create policy users_upd on public.users for update using (app.is_admin() or id = app.uid())
  with check (app.is_admin() or (
     id = app.uid()
     and role     = (select u.role     from public.users u where u.id = app.uid())
     and verified = (select u.verified from public.users u where u.id = app.uid())
     and coalesce(status, 'active') = coalesce((select u.status from public.users u where u.id = app.uid()), 'active')
     and coalesce(phone, '')        = coalesce((select u.phone  from public.users u where u.id = app.uid()), '')
     and coalesce("staffRefType",'') = coalesce((select u."staffRefType" from public.users u where u.id = app.uid()), '')
     and coalesce("staffRefId",'')   = coalesce((select u."staffRefId"   from public.users u where u.id = app.uid()), '')
     and coalesce("staffCode",'')    = coalesce((select u."staffCode"    from public.users u where u.id = app.uid()), '')
     and coalesce("childIds",        '[]'::jsonb) = coalesce((select u."childIds"        from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("homeroomClasses", '[]'::jsonb) = coalesce((select u."homeroomClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedClasses", '[]'::jsonb) = coalesce((select u."assignedClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedSubjects",'[]'::jsonb) = coalesce((select u."assignedSubjects" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("extraRoles",      '[]'::jsonb) = coalesce((select u."extraRoles"      from public.users u where u.id = app.uid()), '[]'::jsonb)
  ));
drop policy if exists users_ins on public.users;
create policy users_ins on public.users for insert with check (
  app.is_admin() or (id = app.uid() and role in ('parent','student') and verified = false
    and coalesce("staffRefType", '') = '' and coalesce("staffRefId", '') = '' and coalesce("staffCode", '') = ''
    and coalesce("extraRoles", '[]'::jsonb) = '[]'::jsonb)
);
select app.chlog_attach('users', 'role,status,verified,staffRefType,staffRefId,staffCode,assignedClasses,assignedSubjects,homeroomClasses,childIds,childId,!phone,!email,blockedRole,blockedAt,blockedBy,extraRoles');

-- 4) Ikki kishilik tasdiq: qo'shimcha O'IBDO' roli bilan O'ZI kiritgan monitoring ballini o'zi tasdiqlay olmaydi
--    (asosiy O'IBDO' va Direktor — avvalgidek). trg_monitoring_guard'dan KEYIN ishlaydi (nomi alifbo bo'yicha keyin).
create or replace function app.monitoring_self_approve_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if app.is_system() or app.is_admin() or coalesce(app.my_role(), '') = 'zavuch' then return new; end if;
  if new.status = 'approved' and new."approvedBy" = app.uid() and new."enteredBy" = app.uid()
     and (tg_op = 'INSERT' or old."approvedBy" is distinct from new."approvedBy" or old.score is distinct from new.score or old.status is distinct from new.status) then
    raise exception 'O''zingiz kiritgan ballni o''zingiz tasdiqlay olmaysiz — boshqa O''IBDO'' yoki Direktor tasdiqlaydi' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function app.monitoring_self_approve_guard() from public, anon, authenticated;
drop trigger if exists trg_monitoring_selfok on public.monitoring;
create trigger trg_monitoring_selfok before insert or update on public.monitoring
  for each row execute function app.monitoring_self_approve_guard();

-- 5) Maosh: vedomostni tasdiqlaydigan (qo'shimcha HR rolli) xodimning o'z qatori ham Direktor tasdig'ida
--    (payroll_submit asosiy hr/finance_mgr rolini tekshiradi; bu trigger qo'shimcha HR rolini qo'shadi).
create or replace function app.payroll_line_extra_hr() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if not coalesce(new."needsDirector", false) and exists (
       select 1 from public.users u where u."staffRefType" = new."personType" and u."staffRefId" = new."refId"
          and app.u_has(u.role, u."extraRoles", 'hr')) then
    new."needsDirector" := true;
  end if;
  return new;
end $$;
revoke all on function app.payroll_line_extra_hr() from public, anon, authenticated;
drop trigger if exists trg_payroll_line_extra_hr on public.payroll_lines;
create trigger trg_payroll_line_extra_hr before insert on public.payroll_lines
  for each row execute function app.payroll_line_extra_hr();

-- 6) Oshxona menyusi (raqib): kun bo'yicha nonushta / tushlik / peshinlik, izoh, allergenlar. Yozish — Direktor va
--    Ma'muriyat rahbari; o'qish — tizimga kirgan FAOL foydalanuvchi (xodim, ota-ona, o'quvchi). Ommaviy saytda ko'rsatilmaydi.
create table if not exists public.canteen_menu (
  id          text primary key,              -- 'YYYY-MM-DD' (kun)
  breakfast   text,
  lunch       text,
  snack       text,
  note        text,
  allergens   jsonb not null default '[]'::jsonb,
  "updatedBy" text, "updatedAt" timestamptz
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'canteen_menu_id_chk') then
    alter table public.canteen_menu add constraint canteen_menu_id_chk check (id ~ '^\d{4}-\d{2}-\d{2}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'canteen_menu_allergens_chk') then
    alter table public.canteen_menu add constraint canteen_menu_allergens_chk check (jsonb_typeof(allergens) = 'array');
  end if;
end $$;
create or replace function app.canteen_menu_stamp() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare a text;
begin
  if length(coalesce(new.breakfast, '')) > 1000 or length(coalesce(new.lunch, '')) > 1000 or length(coalesce(new.snack, '')) > 1000
     or length(coalesce(new.note, '')) > 1000 then
    raise exception 'Menyu matni juda uzun (1000 belgidan oshmasin)' using errcode = '22023';
  end if;
  for a in select x from jsonb_array_elements_text(coalesce(new.allergens, '[]'::jsonb)) x loop
    if a not in ('gluten', 'milk', 'egg', 'nuts', 'fish', 'soy', 'sesame', 'honey') then
      raise exception 'Noma''lum allergen: %', a using errcode = '22023';
    end if;
  end loop;
  new."updatedBy" := coalesce(app.uid(), new."updatedBy"); new."updatedAt" := now();
  return new;
end $$;
revoke all on function app.canteen_menu_stamp() from public, anon, authenticated;
drop trigger if exists trg_canteen_menu_stamp on public.canteen_menu;
create trigger trg_canteen_menu_stamp before insert or update on public.canteen_menu
  for each row execute function app.canteen_menu_stamp();
alter table public.canteen_menu enable row level security;
revoke all on public.canteen_menu from anon, authenticated;
grant select, insert, update, delete on public.canteen_menu to authenticated;
grant all on public.canteen_menu to service_role;
drop policy if exists cm_sel on public.canteen_menu;
create policy cm_sel on public.canteen_menu for select using (cardinality(app.role_set()) > 0);
drop policy if exists cm_ins on public.canteen_menu;
create policy cm_ins on public.canteen_menu for insert with check (app.is_admin() or app.is_admin_head());
drop policy if exists cm_upd on public.canteen_menu;
create policy cm_upd on public.canteen_menu for update using (app.is_admin() or app.is_admin_head()) with check (app.is_admin() or app.is_admin_head());
drop policy if exists cm_del on public.canteen_menu;
create policy cm_del on public.canteen_menu for delete using (app.is_admin() or app.is_admin_head());
select app.chlog_attach('canteen_menu', 'breakfast,lunch,snack,note,allergens');

-- 7) «Reja va tushum» (Direktor, Moliya menejeri): oy × sinf — hisoblangan (bekor/qaytarilganlarsiz), to'langan, qarz,
--    yig'ilish %; har oy uchun 10-sana / oy oxiri / keyingi oyning 10-sanasi kesimi (shu paytgacha TO'LIQ to'langan
--    fakturalar summasi — paidAt bo'yicha; qisman to'lov vaqti saqlanmaydi). Serverda yig'iladi (1000 qator cheklovi yo'q).
create or replace function public.finance_plan_actual(p_from text, p_to text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v jsonb;
begin
  if not app.is_finance_mgr() then raise exception 'Ruxsat yo''q: faqat Direktor va Moliya menejeri' using errcode = '42501'; end if;
  if coalesce(p_from, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' or coalesce(p_to, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' or p_from > p_to then
    raise exception 'Oy oralig''i noto''g''ri (YYYY-MM)' using errcode = '22023';
  end if;
  if (p_to || '-01')::date > (p_from || '-01')::date + interval '23 months' then
    raise exception 'Ko''pi bilan 24 oy' using errcode = '22023';
  end if;
  with inv as (
    select i.month, coalesce(nullif(btrim(i."classKey"), ''), '—') as ck, coalesce(i.amount, 0) as amt,
           least(greatest(coalesce(i."paidAmount", 0), 0), coalesce(i.amount, 0)) as paid, coalesce(i.status, '') as st, i."paidAt" as pat,
           coalesce(nullif(i."studentId", ''), i.id) as sid
      from public.invoices i
     where i.month between p_from and p_to and coalesce(i.status, '') not in ('canceled', 'reversed')),
  cut as (
    select m.month,
           ((m.month || '-11')::timestamp at time zone 'Asia/Tashkent') as c10,
           (((m.month || '-01')::date + interval '1 month')::timestamp at time zone 'Asia/Tashkent') as cend,
           ((((m.month || '-01')::date + interval '1 month')::date + 10)::timestamp at time zone 'Asia/Tashkent') as cn10
      from (select distinct month from inv) m),
  bym as (
    select inv.month, sum(amt) as billed, sum(paid) as paid,
           sum(case when st = 'paid' then 0 else greatest(amt - paid, 0) end) as debt,
           count(*) as n, count(distinct sid) as students,
           sum(amt) filter (where st = 'paid' and (pat is null or pat <= c.c10)) as p10,
           sum(amt) filter (where st = 'paid' and (pat is null or pat <= c.cend)) as pend,
           sum(amt) filter (where st = 'paid' and (pat is null or pat <= c.cn10)) as pn10,
           bool_or(now() >= c.c10) as d10, bool_or(now() >= c.cend) as dend, bool_or(now() >= c.cn10) as dn10
      from inv join cut c on c.month = inv.month group by inv.month),
  byc as (
    select month, ck, sum(amt) as billed, sum(paid) as paid, sum(case when st = 'paid' then 0 else greatest(amt - paid, 0) end) as debt, count(*) as n
      from inv group by month, ck)
  select jsonb_build_object(
    'from', p_from, 'to', p_to,
    'months', coalesce((select jsonb_agg(jsonb_build_object('month', month, 'billed', billed, 'paid', paid, 'debt', debt, 'n', n, 'students', students,
                  'rate', case when billed > 0 then round(100.0 * paid / billed, 1) end,
                  'cut10', case when d10 and billed > 0 then round(100.0 * coalesce(p10, 0) / billed, 1) end,
                  'cutEnd', case when dend and billed > 0 then round(100.0 * coalesce(pend, 0) / billed, 1) end,
                  'cutNext10', case when dn10 and billed > 0 then round(100.0 * coalesce(pn10, 0) / billed, 1) end) order by month) from bym), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('month', month, 'classKey', ck, 'billed', billed, 'paid', paid, 'debt', debt, 'n', n,
                  'rate', case when billed > 0 then round(100.0 * paid / billed, 1) end) order by month, ck) from byc), '[]'::jsonb),
    'total', (select jsonb_build_object('billed', coalesce(sum(billed), 0), 'paid', coalesce(sum(paid), 0), 'debt', coalesce(sum(debt), 0),
                  'rate', case when sum(billed) > 0 then round(100.0 * sum(paid) / sum(billed), 1) end) from bym)) into v;
  return v;
end $$;
revoke all on function public.finance_plan_actual(text, text) from public, anon;
grant execute on function public.finance_plan_actual(text, text) to authenticated, service_role;

-- 8) Pul qoidalari buzilishi (Direktor): o'tish oylaridan boshlab — tasdiqsiz chegirma/grant/kontrakt, tasdiqsiz «Monitoring
--    100», tasdiqsiz «Bemor» kuni, tasdiqlanmagan tavsiya bonusi, HR tasdig'isiz maosh to'lovi, haq to'langan «o'z arizasi»
--    ta'tili. Yozish paytidagi trigger qoidalari bilan bir xil shartlar (aylanib o'tilgan / eski yozuvlarni ushlaydi).
create or replace function public.money_rule_violations() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_disc text; v_bonus text; v_sick text; v_pay text; v_rules jsonb := '[]'::jsonb; n int; ids jsonb;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: faqat Direktor' using errcode = '42501'; end if;
  select nullif(btrim(coalesce(c."discountApprovalFrom", '')), ''), nullif(btrim(coalesce(c."bonusApprovalFrom", '')), ''),
         nullif(btrim(coalesce(c."sickApprovalFrom", '')), ''), nullif(btrim(coalesce(c."payrollApprovalFrom", '')), '')
    into v_disc, v_bonus, v_sick, v_pay from public.config c where c.id = 'finance';
  -- (a) chegirma / grant / kontrakt
  with inv as (
    select i.id, i."studentId" as sid, i.month, coalesce(i."pctApplied", 0) as pct, coalesce(i."isGrant", false) as g,
           coalesce(i."discountInfo", '') as di, coalesce(i."bonusRef", '') as br, i."baseAmount" as base,
           case when jsonb_typeof(i."approvalRefs") = 'array' then i."approvalRefs" else '[]'::jsonb end as refs
      from public.invoices i
     where v_disc is not null and i.month >= v_disc and coalesce(i.status, '') not in ('canceled', 'reversed')),
  okr as (
    select inv.id, d.kind, d.params
      from inv, jsonb_array_elements_text(inv.refs) r
      join public.discount_requests d on d.id = r
     where d.status = 'approved' and d."studentId" = inv.sid
       and (d."fromMonth" is null or inv.month >= d."fromMonth") and (d."toMonth" is null or inv.month <= d."toMonth")),
  chk as (
    select inv.*,
           coalesce((select array_agg(o.kind) from okr o where o.id = inv.id), '{}'::text[]) as kinds,
           jsonb_array_length(inv.refs) - (select count(*) from okr o where o.id = inv.id) as bad_refs,
           coalesce((select array_agg(round((o.params->>'contractAmount')::numeric)) from okr o
                      where o.id = inv.id and o.kind = 'contract' and (o.params->>'contractAmount') ~ '^\d+(\.\d+)?$'), '{}'::numeric[]) as camt
      from inv),
  bad as (
    select id, month from chk
     where bad_refs > 0
        or (g and pct >= 1 and br = '' and di not ilike 'Monitoring 100%' and not (kinds && array['olympiad', 'social']))
        or (pct >= 0.5 and pct < 1 and not (kinds && array['teacher_child']))
        or (di ilike 'Kontrakt%' and not (round(coalesce(base, -1)) = any(camt))))
  select count(*), coalesce((select jsonb_agg(id) from (select id from bad order by month desc, id limit 10) q), '[]'::jsonb) into n, ids from bad;
  v_rules := v_rules || jsonb_build_object('key', 'discount', 'title', 'Ikkala tasdig‘isiz chegirma / grant / kontrakt', 'from', v_disc, 'count', n, 'ids', ids);
  -- (b) «Monitoring 100» granti — Direktor tasdiqlagan bonussiz
  with bad as (
    select i.id, i.month from public.invoices i
     where v_bonus is not null and i.month >= v_bonus and coalesce(i.status, '') not in ('canceled', 'reversed')
       and coalesce(i."isGrant", false) and coalesce(i."pctApplied", 0) >= 1 and coalesce(i."discountInfo", '') ilike 'Monitoring 100%'
       and not exists (select 1 from public.monitoring_bonus b where b.id = i."bonusRef" and b.status = 'approved'
                        and b."studentId" = i."studentId" and b.period = to_char((i.month || '-01')::date - interval '1 month', 'YYYY-MM')))
  select count(*), coalesce((select jsonb_agg(id) from (select id from bad order by month desc, id limit 10) q), '[]'::jsonb) into n, ids from bad;
  v_rules := v_rules || jsonb_build_object('key', 'bonus', 'title', 'Direktor tasdig‘isiz 100 ball granti', 'from', v_bonus, 'count', n, 'ids', ids);
  -- (c) «Bemor» kuni — tasdiqlangan ma'lumotnomasiz
  -- "sickNoteRefs" — obyekt {ma'lumotnoma id: [kunlar]} (nurse-sick.sql, yozish paytidagi app.invoice_sick_guard bilan bir xil
  --   shartlar). Avval massiv deb tekshirilardi -> har bir to'g'ri (tasdiqlangan ma'lumotnomali) chegirma ham «buzilish» edi.
  --   Buzilish: kasal kun yoki summa bor, lekin obyekt yo'q / bo'sh; kalit — shu o'quvchining tasdiqlangan ma'lumotnomasi emas;
  --   qiymat ro'yxat emas; kun ma'lumotnomada yo'q; kunlar soni "sickDaysApplied" ga teng emas. (Summa × stavka tekshirilmaydi:
  --   stavka keyin o'zgargan bo'lishi mumkin.) jsonb_each faqat obyektga (r0.refs — boshqa turda null).
  with bad as (
    select i.id, i.month from public.invoices i
     cross join lateral (select case when jsonb_typeof(i."sickNoteRefs") = 'object' then i."sickNoteRefs" end as refs) r0
     where v_sick is not null and i.month >= v_sick and coalesce(i.status, '') not in ('canceled', 'reversed')
       and (coalesce(i."sickDaysApplied", 0) > 0 or coalesce(i."sickAmount", 0) > 0)
       and (r0.refs is null or r0.refs = '{}'::jsonb
            or coalesce(i."sickDaysApplied", 0) <> (select coalesce(sum(case when jsonb_typeof(e.value) = 'array' then jsonb_array_length(e.value) else 0 end), 0)
                                                       from jsonb_each(r0.refs) e)
            or exists (select 1 from jsonb_each(r0.refs) e
                         left join public.sick_notes s on s.id = e.key and s.status = 'approved' and s."studentId" = i."studentId"
                        where s.id is null or jsonb_typeof(e.value) <> 'array'
                           or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(e.value) = 'array' then e.value else '[]'::jsonb end) d
                                       where not (coalesce(s."schoolDays", '[]'::jsonb) ? d)))))
  select count(*), coalesce((select jsonb_agg(id) from (select id from bad order by month desc, id limit 10) q), '[]'::jsonb) into n, ids from bad;
  v_rules := v_rules || jsonb_build_object('key', 'sick', 'title', 'Tasdiqsiz «Bemor» kuni chegirmasi', 'from', v_sick, 'count', n, 'ids', ids);
  -- (d) tavsiya bonusi — tasdiqlanmagan tavsiya bilan
  with bad as (
    select i.id, i.month from public.invoices i
     where v_disc is not null and i.month >= v_disc and coalesce(i.status, '') not in ('canceled', 'reversed')
       and jsonb_typeof(i."referralUsedIds") = 'array' and jsonb_array_length(i."referralUsedIds") > 0
       and exists (select 1 from jsonb_array_elements_text(i."referralUsedIds") r
                    where not exists (select 1 from public.referral_requests q where q.id = r and q.status in ('approved', 'applied'))))
  select count(*), coalesce((select jsonb_agg(id) from (select id from bad order by month desc, id limit 10) q), '[]'::jsonb) into n, ids from bad;
  v_rules := v_rules || jsonb_build_object('key', 'referral', 'title', 'Moliya tasdig‘isiz tavsiya bonusi', 'from', v_disc, 'count', n, 'ids', ids);
  -- (e) maosh — HR tasdig'isiz to'lov
  with bad as (
    select p.id, p.month from public.salary_payments p
     where v_pay is not null and p.month >= v_pay
       and not exists (select 1 from public.payroll_runs r where r.id = p.month and r.status = 'approved'))
  select count(*), coalesce((select jsonb_agg(id) from (select id from bad order by month desc, id limit 10) q), '[]'::jsonb) into n, ids from bad;
  v_rules := v_rules || jsonb_build_object('key', 'payroll', 'title', 'HR tasdig‘isiz to‘langan maosh', 'from', v_pay, 'count', n, 'ids', ids);
  -- (f) haq to'langan «o'z arizasi bilan» ta'til (D5)
  with bad as (select l.id, l."startDay" as month from public.staff_leaves l where l.type = 'ruhsat' and coalesce(l.paid, false))
  select count(*), coalesce((select jsonb_agg(id) from (select id from bad order by month desc, id limit 10) q), '[]'::jsonb) into n, ids from bad;
  v_rules := v_rules || jsonb_build_object('key', 'leave', 'title', 'Haq to‘langan «o‘z arizasi bilan» ta’til', 'from', null, 'count', n, 'ids', ids);
  return jsonb_build_object('total', (select coalesce(sum((r->>'count')::int), 0) from jsonb_array_elements(v_rules) r), 'rules', v_rules);
end $$;
revoke all on function public.money_rule_violations() from public, anon;
grant execute on function public.money_rule_violations() to authenticated, service_role;

-- 9) Direktorning haftalik ko'rsatkichlari («📊 Haftalik hisobot», faqat Direktor). Har ko'rsatkich — shu hafta va o'tgan
--    hafta (taqqoslash uchun). Ta'riflar — «Yo'l xaritasi» → «Direktorning haftalik sahifasi» jadvali.
--   (1) To'lov yig'ilishi: baholanayotgan oy = (sana − 10 kun) oyi (muddati — keyingi oyning 10-sanasi); shu paytgacha TO'LIQ
--       to'langan fakturalar summasi / hisoblangan (bekor/qaytarilganlarsiz); qisman to'lovlar bilan — alohida (hozir).
--   (2) Qarz muddati: o'tgan oylar (va 10-sanadan keyin joriy oy) bo'yicha to'liq to'lanmagan oylar soni har o'quvchiga.
--   (3) Davomat kiritilishi: belgilangan o'quvchi-kunlar / kerakli (Du–Sha, bayramsiz, bugungacha), sinf bo'yicha.
--       Kiritish VAQTI saqlanmaydi — «10:00 gacha» qismi hisoblanmaydi.
--   (4) Ota-onalar ulanishi: kamida bitta faol bog'lanishi bor o'quvchilar / o'qiyotganlar, sinf bo'yicha.
--   (5) O'qituvchilar hisobi (bog'langan faol hisob / ro'yxat) va faolligi (shu hafta tizimda yozuv qilganlar — o'zgarishlar tarixi).
--   (6) Muddati o'tgan tasdiqlar (hozir): 100 ball (Direktor muddati o'tgan), chegirma/«Bemor» kuni/tavsiya (faktura
--       chiqarilganda hali tasdiqlanmagan), maosh (yuborilganiga 3 kundan oshgan).
--   (7) Pul qoidalari buzilishi — money_rule_violations().  (8) Zaxira — auth-server «Tizim holati»dan (sahifada).
create or replace function app.kpi_collection(p_at timestamptz) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  with m as (select to_char((p_at at time zone 'Asia/Tashkent') - interval '10 days', 'YYYY-MM') as mon),
  inv as (select coalesce(i.amount, 0) as amt, least(greatest(coalesce(i."paidAmount", 0), 0), coalesce(i.amount, 0)) as paid,
                 coalesce(i.status, '') as st, i."paidAt" as pat
            from public.invoices i, m
           where i.month = m.mon and coalesce(i.status, '') not in ('canceled', 'reversed') and coalesce(i.amount, 0) > 0
             and (i."createdAt" is null or i."createdAt" <= p_at))
  select jsonb_build_object('month', (select mon from m),
    'deadline', to_char(((select mon from m) || '-01')::date + interval '1 month' + interval '9 days', 'YYYY-MM-DD'),
    'billed', coalesce(sum(amt), 0),
    'rate', case when sum(amt) > 0 then round(100.0 * coalesce(sum(amt) filter (where st = 'paid' and (pat is null or pat <= p_at)), 0) / sum(amt), 1) end,
    'ratePartial', case when sum(amt) > 0 then round(100.0 * sum(paid) / sum(amt), 1) end)
  from inv
$$;
create or replace function app.kpi_debt_aging(p_at timestamptz) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  with d as (select (p_at at time zone 'Asia/Tashkent')::date as d),
  cur as (select to_char(d, 'YYYY-MM') as mon, extract(day from d)::int as dd from d),
  st as (select coalesce(nullif(s."studentId", ''), s.id) as sid, s.id as did from public.students s
          where coalesce(s."payStatus", '') not in ('chiqdi', 'muzlatilgan')),
  od as (select i."studentId" as k, i.month from public.invoices i, cur
          where coalesce(i.status, '') not in ('canceled', 'reversed') and coalesce(i.amount, 0) > 0
            and (i."createdAt" is null or i."createdAt" <= p_at)
            and (i.month < cur.mon or (i.month = cur.mon and cur.dd > 10))
            and not (coalesce(i.status, '') = 'paid' and (i."paidAt" is null or i."paidAt" <= p_at))),
  per as (select st.sid, count(distinct od.month) as n from st join od on od.k in (st.sid, st.did) group by st.sid)
  select jsonb_build_object('students', (select count(*) from st),
    'm1', count(*) filter (where n = 1), 'm2', count(*) filter (where n = 2), 'm3', count(*) filter (where n >= 3),
    'm2plus', count(*) filter (where n >= 2),
    'm1share', case when (select count(*) from st) > 0 then round(100.0 * count(*) filter (where n = 1) / (select count(*) from st), 1) end)
  from per
$$;
create or replace function app.kpi_attendance(p_from date, p_to date) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  with days as (select g::date as d from generate_series(p_from, greatest(p_from, p_to), interval '1 day') g
                 where g::date <= p_to and extract(isodow from g) < 7
                   and not exists (select 1 from public.school_holidays h where h.day = to_char(g, 'YYYY-MM-DD'))),
  st as (select coalesce(nullif(s."studentId", ''), s.id) as sid, app.student_class_key(s.lang, s.grade, s."classLetter", s.track) as ck,
                nullif(s."activeFrom", '') as af
           from public.students s where coalesce(s."payStatus", '') not in ('chiqdi', 'muzlatilgan')),
  req as (select st.sid, st.ck, days.d from st cross join days where st.af is null or st.af <= to_char(days.d, 'YYYY-MM-DD')),
  att as (select a."studentId" as sid, a.month, a.days from public.attendance a
           where a.month in (select distinct to_char(d, 'YYYY-MM') from days) and jsonb_typeof(a.days) = 'object'),
  mk as (select r.ck, (att.days ? to_char(r.d, 'DD') or att.days ? extract(day from r.d)::int::text) as marked
           from req r left join att on att.sid = r.sid and att.month = to_char(r.d, 'YYYY-MM'))
  select jsonb_build_object('from', p_from, 'to', p_to, 'required', count(*), 'marked', count(*) filter (where marked),
    'rate', case when count(*) > 0 then round(100.0 * count(*) filter (where marked) / count(*), 1) end,
    'byClass', coalesce((select jsonb_agg(jsonb_build_object('classKey', ck, 'required', rq, 'marked', m,
                         'rate', case when rq > 0 then round(100.0 * m / rq, 1) end) order by ck)
                         from (select ck, count(*) as rq, count(*) filter (where marked) as m from mk group by ck) x), '[]'::jsonb))
  from mk
$$;
create or replace function app.kpi_parents(p_at timestamptz) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  with st as (select coalesce(nullif(s."studentId", ''), s.id) as sid, s.id as did,
                     app.student_class_key(s.lang, s.grade, s."classLetter", s.track) as ck
                from public.students s where coalesce(s."payStatus", '') not in ('chiqdi', 'muzlatilgan')),
  x as (select st.ck, exists (select 1 from public.child_claims cc where cc."studentId" in (st.sid, st.did)
                                and coalesce(nullif(cc.status, ''), 'active') = 'active' and (cc.created is null or cc.created <= p_at)) as con
          from st)
  select jsonb_build_object('students', count(*), 'connected', count(*) filter (where con),
    'rate', case when count(*) > 0 then round(100.0 * count(*) filter (where con) / count(*), 1) end,
    'byClass', coalesce((select jsonb_agg(jsonb_build_object('classKey', ck, 'students', n, 'connected', c,
                         'rate', case when n > 0 then round(100.0 * c / n, 1) end) order by ck)
                         from (select ck, count(*) as n, count(*) filter (where con) as c from x group by ck) y), '[]'::jsonb))
  from x
$$;
create or replace function app.kpi_staff(p_at timestamptz, p_from timestamptz, p_to timestamptz) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  with t as (select t.id, t."userUid" from public.teachers t where coalesce(t."payStatus", '') <> 'chiqdi'),
  lk as (select t.id, (select u.id from public.users u
                        where coalesce(nullif(u.status, ''), 'active') = 'active' and (u."createdAt" is null or u."createdAt" <= p_at)
                          and ((u."staffRefType" = 'teacher' and u."staffRefId" = t.id) or u.id = t."userUid") limit 1) as uid
           from t)
  select jsonb_build_object('teachers', count(*), 'withAccount', count(uid),
    'rate', case when count(*) > 0 then round(100.0 * count(uid) / count(*), 1) end,
    'active', count(*) filter (where uid is not null and exists (select 1 from public.change_log c where c.actor_uid = lk.uid and c.at >= p_from and c.at < p_to)),
    'activeRate', case when count(uid) > 0 then round(100.0 * count(*) filter (where uid is not null and exists (
                    select 1 from public.change_log c where c.actor_uid = lk.uid and c.at >= p_from and c.at < p_to)) / count(uid), 1) end)
  from lk
$$;
create or replace function app.kpi_overdue_approvals() returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select jsonb_build_object(
    'bonus', (select count(*) from public.monitoring_bonus b where b.status = 'proposed' and b."decideDeadline" is not null and b."decideDeadline" < now()),
    'discount', (select count(*) from public.discount_requests r where r.status = 'pending' and exists (
                   select 1 from public.invoices i where i."studentId" = r."studentId" and coalesce(i.status, '') not in ('canceled', 'reversed')
                      and (r."fromMonth" is null or i.month >= r."fromMonth") and i."createdAt" > r."requestedAt")),
    'sick', (select count(*) from public.sick_notes n where n.status = 'pending' and exists (
               select 1 from public.invoices i where i."studentId" = n."studentId" and coalesce(i.status, '') not in ('canceled', 'reversed')
                  and i.month >= substr(n."fromDay", 1, 7) and i."createdAt" > n."enteredAt")),
    -- "firstPaymentId" faqat tasdiqlanganda yoziladi -> kutilayotgan tavsiyaning to'lovi app.first_real_payment'dan olinadi
    --   (avval shu ustun bo'yicha sanalardi va hisoblagich doim 0 edi).
    'referral', (select count(*) from public.referral_requests q
                  cross join lateral (select f.pat from app.first_real_payment(q.id) f) fp
                  where q.status = 'pending_payment'
                    and exists (select 1 from public.invoices i where i."studentId" = q."referrerId" and i."createdAt" > fp.pat)),
    'payroll', (select count(*) from public.payroll_runs p where p.status = 'submitted' and p."submittedAt" < now() - interval '3 days'))
$$;
do $$ declare f text; begin
  foreach f in array array['app.kpi_collection(timestamptz)', 'app.kpi_debt_aging(timestamptz)', 'app.kpi_attendance(date, date)',
                           'app.kpi_parents(timestamptz)', 'app.kpi_staff(timestamptz, timestamptz, timestamptz)', 'app.kpi_overdue_approvals()'] loop
    execute 'revoke all on function ' || f || ' from public, anon, authenticated';
  end loop;
end $$;
create or replace function public.director_weekly(p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_today date := (now() at time zone 'Asia/Tashkent')::date;
  v_day date := least(coalesce(p_date, v_today), v_today);
  v_ws date; v_we date; v_at timestamptz; v_pat timestamptz; v_wsts timestamptz; v_wets timestamptz; v_ap jsonb; v_money jsonb;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: haftalik hisobot faqat Direktor uchun' using errcode = '42501'; end if;
  v_ws := v_day - (extract(isodow from v_day)::int - 1);
  v_we := v_ws + 6;
  v_wsts := v_ws::timestamp at time zone 'Asia/Tashkent';
  v_wets := (v_we + 1)::timestamp at time zone 'Asia/Tashkent';
  v_at := least(now(), v_wets);
  v_pat := v_at - interval '7 days';
  v_ap := app.kpi_overdue_approvals();
  v_money := public.money_rule_violations();
  return jsonb_build_object(
    'weekStart', v_ws, 'weekEnd', v_we, 'at', v_at, 'prevAt', v_pat, 'isCurrent', v_we >= v_today,
    'collection', jsonb_build_object('cur', app.kpi_collection(v_at), 'prev', app.kpi_collection(v_pat)),
    'debt', jsonb_build_object('cur', app.kpi_debt_aging(v_at), 'prev', app.kpi_debt_aging(v_pat)),
    'attendance', jsonb_build_object('cur', app.kpi_attendance(v_ws, least(v_we, v_today)), 'prev', app.kpi_attendance(v_ws - 7, v_ws - 1)),
    'parents', jsonb_build_object('cur', app.kpi_parents(v_at), 'prev', app.kpi_parents(v_pat)),
    'staff', jsonb_build_object('cur', app.kpi_staff(v_at, v_wsts, v_wets), 'prev', app.kpi_staff(v_pat, v_wsts - interval '7 days', v_wsts)),
    'approvals', v_ap || jsonb_build_object('total', (select coalesce(sum(value::int), 0) from jsonb_each_text(v_ap))),
    'money', v_money);
end $$;
revoke all on function public.director_weekly(date) from public, anon;
grant execute on function public.director_weekly(date) to authenticated, service_role;

notify pgrst, 'reload schema';
