-- =====================================================================
-- MAKTAB AVTOBUSI — jonli joylashuv kuzatuvi (GPS).
--   Haydovchi maxfiy havola bilan joylashuvni ulashadi (login YO'Q),
--   ota-ona kabinetда o'z yo'nalishini tanlab avtobusni jonli ko'radi.
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/bus.sql
--
-- Xavfsizlik:
--   * bus_routes — maxfiy driver_key bilan; FAQAT direktor (app.is_admin) o'qiydi/yozadi.
--   * bus_routes_public — (id,name,active) view — ota-ona/haydovchi driver_key'siz o'qiydi.
--   * bus_positions — kirgan foydalanuvchi o'qiydi; YOZISH faqat update_bus_position RPC orqali
--     (security definer, driver_key bilan tekshiradi) — to'g'ridan-to'g'ri yozib bo'lmaydi.
-- =====================================================================

-- 1) Jadvallar --------------------------------------------------------
create table if not exists public.bus_routes (
  id           text primary key,
  name         text not null,
  driver_key   text not null,
  active       boolean not null default true,
  "createdAt"  timestamptz not null default now()
);

create table if not exists public.bus_positions (
  id           text primary key,           -- = yo'nalish id (bitta yo'nalish -> bitta joriy joylashuv)
  lat          double precision,
  lng          double precision,
  heading      double precision,           -- yo'nalish burchagi (0-360), bo'lishi shart emas
  speed        double precision,           -- m/s, bo'lishi shart emas
  direction    text,                        -- 'to_school' | 'from_school'
  driver       text,                        -- haydovchi ismi (ixtiyoriy)
  active       boolean not null default false,
  "updatedAt"  timestamptz not null default now()
);

-- Jadval huquqlari (RLS baribir cheklaydi) — default privileges bo'lmasa ham
-- ota-ona SELECT qila olishi va RPC yozishi uchun aniq beramiz (idempotent).
grant select, insert, update, delete on public.bus_routes, public.bus_positions to anon, authenticated;
grant all on public.bus_routes, public.bus_positions to service_role;

-- 2) Ommaviy view (driver_key'siz) — ota-ona/haydovchi o'qiydi --------
create or replace view public.bus_routes_public as
  select id, name, active from public.bus_routes where active is not false;
revoke all on public.bus_routes_public from public;
grant select on public.bus_routes_public to anon, authenticated;
grant select on public.bus_routes_public to service_role;

-- 3) RLS --------------------------------------------------------------
alter table public.bus_routes    enable row level security;
alter table public.bus_positions enable row level security;

-- Yo'nalishlar (maxfiy kalit bilan) — faqat direktor.
drop policy if exists br_admin_all on public.bus_routes;
create policy br_admin_all on public.bus_routes for all
  using (app.is_admin()) with check (app.is_admin());

-- Joylashuvlar — kirgan foydalanuvchi (ota-ona) o'qiydi. Yozish siyosati YO'Q
-- (faqat security-definer RPC yozadi -> to'g'ridan-to'g'ri INSERT/UPDATE bloklangan).
drop policy if exists bp_sel on public.bus_positions;
create policy bp_sel on public.bus_positions for select
  using (app.uid() is not null or app.is_admin());

-- 4) RPC: haydovchi joylashuvni ulashadi (login yo'q; driver_key bilan) -
create or replace function public.update_bus_position(
  p_route text, p_key text,
  p_lat double precision, p_lng double precision,
  p_heading double precision default null, p_speed double precision default null,
  p_direction text default null, p_driver text default null
) returns jsonb language plpgsql security definer set search_path = public, app as $$
declare v_name text;
begin
  select name into v_name from public.bus_routes
    where id = p_route and driver_key = p_key and active is not false;
  if v_name is null then
    return jsonb_build_object('ok', false, 'msg', 'Kalit yoki yo''nalish xato');
  end if;
  if p_lat is null or p_lng is null then
    return jsonb_build_object('ok', false, 'msg', 'Joylashuv topilmadi');
  end if;
  insert into public.bus_positions(id, lat, lng, heading, speed, direction, driver, active, "updatedAt")
    values(p_route, p_lat, p_lng, p_heading, p_speed,
           nullif(p_direction,''), nullif(p_driver,''), true, now())
    on conflict (id) do update set
      lat = excluded.lat, lng = excluded.lng, heading = excluded.heading,
      speed = excluded.speed, direction = excluded.direction, driver = excluded.driver,
      active = true, "updatedAt" = now();
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.update_bus_position(text,text,double precision,double precision,double precision,double precision,text,text) from public;
grant execute on function public.update_bus_position(text,text,double precision,double precision,double precision,double precision,text,text) to anon, authenticated;

-- 5) RPC: haydovchi kuzatuvni to'xtatadi -------------------------------
create or replace function public.stop_bus(p_route text, p_key text)
returns jsonb language plpgsql security definer set search_path = public, app as $$
begin
  if not exists(select 1 from public.bus_routes where id = p_route and driver_key = p_key) then
    return jsonb_build_object('ok', false, 'msg', 'Kalit xato');
  end if;
  update public.bus_positions set active = false, "updatedAt" = now() where id = p_route;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.stop_bus(text,text) from public;
grant execute on function public.stop_bus(text,text) to anon, authenticated;

-- 6) Realtime — kabinet jonli yangilanishi (poll ham bor, bu qo'shimcha) -
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin execute 'alter publication supabase_realtime add table public.bus_positions';
    exception when duplicate_object then null; when others then null; end;
  end if;
end $$;

notify pgrst, 'reload schema';
