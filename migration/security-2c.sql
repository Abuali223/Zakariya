\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: security-2c.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- Audit 2c — 'students' ro'yxati: cameraId + attendance ni OMMAVIYDAN yashirish.
-- Idempotent. Docker orqali:
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
--
-- Muammo: students_sel using(true) -> ANON har o'quvchining cameraId (bola↔kamera
--   oqimi) va attendance (davomat %) ustunlarini ham tortib olishi mumkin edi.
-- Xom 'students' jadvali endi faqat KIRGAN foydalanuvchilarga (admin/o'qituvchi/
--   ota-ona) o'qiladi. PII allaqachon student_private'da (bu 2c'ga tegmaydi).
-- D6 (2026-10-30): ommaviy o'quvchi ko'rinishi (ilgari ism/sinf/ball/foto anonga ochiq edi)
--   endi YARATILMAYDI — public-close.sql uni o'chiradi; anon o'quvchi ma'lumotini olmaydi.
-- =====================================================================

-- ---- 1. Xom students jadvalini ANON'dan qulflash ----
-- Kirgan har kim o'qiy oladi (admin/zavuch/o'qituvchi/kurator/ota-ona) — bu
-- admin panel va kabinet oqimlarini buzmaydi. (Keyingi fayllar qoidani toraytiradi.)
-- Yozish siyosatlari (ins/upd/del) o'zgarmaydi.
drop policy if exists students_sel on public.students;
create policy students_sel on public.students for select using (app.uid() is not null);

-- Izoh: cameraId hali ham kirgan foydalanuvchilarga ochiq (xom jadval orqali).
-- Kelgusi nafislik: cameraId'ni alohida admin-only jadvalga ko'chirish.

-- ---- 2. PostgREST sxema keshini yangilash ----
notify pgrst, 'reload schema';
