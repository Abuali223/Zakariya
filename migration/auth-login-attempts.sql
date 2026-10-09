-- =====================================================================
-- LOGIN URINISHLARI (lockout) + otp_codes.uid (telefon o'zgartirish uchun).
--   Mijozga TO'LIQ YOPIQ (RLS on, policy yo'q) — faqat auth-server (service_role).
-- Idempotent. run-all.sql + deploy.sh'da.
-- =====================================================================

-- Login urinishlari — vaqtinchalik bloklash uchun (masalan 15 daqiqada 10 xato).
create table if not exists public.auth_login_attempts(
  id          bigint generated always as identity primary key,
  phone       text,
  ok          boolean,
  ip          text,
  "at"        timestamptz default now()
);
create index if not exists idx_login_attempts_phone_at on public.auth_login_attempts(phone, "at" desc);
alter table public.auth_login_attempts enable row level security;   -- policy yo'q -> mijoz ko'rolmaydi
grant all on public.auth_login_attempts to service_role;

-- Telefon o'zgartirish OTP'si egasini bog'lash uchun (request-otp authЗ bo'lganда yoziladi).
alter table public.otp_codes add column if not exists uid text;

-- Eski urinishlarni tozalash (ixtiyoriy; server chaqiradi).
create or replace function app.login_attempts_gc() returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.auth_login_attempts where "at" < now() - interval '1 day';
$$;

-- auth.users'dan email bo'yicha uid (YETIM/squat hisobni qayta tiklash uchun — register).
--   FAQAT service_role chaqiradi (anon/authenticated EXECUTE ruxsati OLINADI). public'da —
--   auth-server .rpc() orqali chaqirsin (PostgREST public sxemani ochadi).
create or replace function public.auth_uid_by_email(p_email text)
returns text language sql security definer set search_path = auth, public, pg_temp as $$
  select id::text from auth.users where lower(email) = lower(p_email) limit 1
$$;
revoke all on function public.auth_uid_by_email(text) from public, anon, authenticated;
grant execute on function public.auth_uid_by_email(text) to service_role;

notify pgrst, 'reload schema';
