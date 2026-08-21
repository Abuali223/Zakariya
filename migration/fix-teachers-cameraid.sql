-- =====================================================================
-- FIX: teachers jadvaliga cameraId ustuni (forma yozadi, jadvalda yo'q edi -> PGRST204)
-- Kamera ID = yuz terminalidagi xodim ID (kelish nazorati / camera-bridge uchun).
-- Idempotent. Docker orqali:
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/fix-teachers-cameraid.sql
-- =====================================================================
alter table teachers add column if not exists "cameraId" text;
notify pgrst, 'reload schema';
