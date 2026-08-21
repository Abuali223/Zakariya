-- =====================================================================
-- Xodim ro'llari: Direktor = admin darajasidagi ruxsat (RLS boundary).
-- O'IBDO' = mavjud 'zavuch' roli (o'zgarishsiz). Boshqa xodim ro'llari —
-- foydalanuvchilar bo'limida tayinlanadigan tashkiliy yorliqlar (panel ruxsati
-- alohida dizayn qilinadi). Idempotent. Docker orqali:
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/roles.sql
-- =====================================================================
create or replace function app.is_admin() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('admin','director'))
$$;
notify pgrst, 'reload schema';
