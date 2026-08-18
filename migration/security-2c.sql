-- =====================================================================
-- Audit 2c — 'students' ro'yxati: cameraId + attendance ni OMMAVIYDAN yashirish.
-- Idempotent. Docker orqali:
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/security-2c.sql
--
-- Muammo: students_sel using(true) -> ANON har o'quvchining cameraId (bola↔kamera
--   oqimi) va attendance (davomat %) ustunlarini ham tortib olishi mumkin edi.
-- Maktab falsafasi (ochiq natijalar/reyting) saqlanadi: ism/sinf/ball/foto OCHIQ
--   qoladi — lekin ular endi 'students_public' KO'RINISHI orqali beriladi.
-- Xom 'students' jadvali endi faqat KIRGAN foydalanuvchilarga (admin/o'qituvchi/
--   ota-ona) o'qiladi. PII allaqachon student_private'da (bu 2c'ga tegmaydi).
-- =====================================================================

-- ---- 1. Ommaviy ko'rinish: xavfsiz ustunlar (cameraId/attendance YO'Q) ----
-- Oddiy view (security_invoker EMAS) -> egasi (postgres) huquqi bilan ishlaydi,
-- students RLS'ini chetlab o'tadi. Shu bois anon xavfsiz ustunlarni ko'radi.
create or replace view public.students_public as
  select id, "studentId", name, grade, "classLetter", track, lang, score,
         photo, "posterImage", subjects, "order", "updatedAt"
  from public.students;

grant select on public.students_public to anon, authenticated;
revoke all on public.students_public from public;
grant select on public.students_public to service_role;

-- ---- 2. Xom students jadvalini ANON'dan qulflash ----
-- Kirgan har kim o'qiy oladi (admin/zavuch/o'qituvchi/kurator/ota-ona) — bu
-- admin panel va kabinet oqimlarini buzmaydi. ANON endi faqat view'ni ko'radi.
-- Yozish siyosatlari (ins/upd/del) o'zgarmaydi.
drop policy if exists students_sel on public.students;
create policy students_sel on public.students for select using (app.uid() is not null);

-- Izoh: cameraId hali ham kirgan foydalanuvchilarga ochiq (xom jadval orqali).
-- Kelgusi nafislik: cameraId'ni alohida admin-only jadvalga ko'chirish.

-- ---- 3. PostgREST sxema keshini yangilash (yangi view API'da darrov ko'rinsin) ----
notify pgrst, 'reload schema';
