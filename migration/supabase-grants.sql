-- =====================================================================
-- supabase-grants.sql — Supabase rollari uchun ruxsatlar (RLS baribir cheklaydi).
-- schema.sql + rls.sql + storage-rls.sql DAN KEYIN yuklanadi.
--
-- Supabase'da uchta rol PostgREST orqali keladi:
--   anon           — login qilmagan (ommaviy)
--   authenticated  — login qilgan foydalanuvchi
--   service_role   — server (RLS'ni chetlab o'tadi, BYPASSRLS)
-- Ruxsat berilsa ham, RLS siyosatlari kim nimani ko'rishini belgilaydi.
-- =====================================================================

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema app    to anon, authenticated, service_role;

-- Jadval huquqlari (RLS cheklaydi)
grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant all on all tables in schema public to service_role;

-- Ketma-ketliklar (kerak bo'lsa)
grant usage, select on all sequences in schema public to anon, authenticated, service_role;

-- app.* yordamchi funksiyalari (RLS siyosatlari chaqiradi)
grant execute on all functions in schema app to anon, authenticated, service_role;

-- Kelajakda qo'shiladigan jadvallar uchun ham avtomatik
alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to anon, authenticated, service_role;

-- PostgREST sxema keshini yangilash (yangi jadvallarni ko'rishi uchun)
notify pgrst, 'reload schema';
