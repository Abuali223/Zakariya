\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: storage-rls.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- storage-rls.sql — Supabase Storage (storage.objects) uchun RLS.
-- Faqat ADMIN yuklaydi/o'chiradi (admin panelidan rasm/video). O'qish (papka ro'yxati)
-- siyosati public-close.sql'da — faqat xodimlarga (D6; app.is_staff bu yerda hali yo'q).
-- Ommaviy havolalar (/storage/v1/object/public/...) Supabase'da RLS'siz beriladi.
--
-- ⚠️ Bu FAQAT Supabase o'rnatilgach ishlaydi (storage sxemasi Supabase tomonidan
--    yaratiladi). rls.sql (bare Postgres'da sinaladigan) ichiga QO'SHILMAYDI.
-- (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- Supabase 'public' bucket ni yaratadi (import-auth-storage.cjs ham yaratadi).
-- storage.objects'da RLS Supabase'da odatda YOQILGAN.

-- Eski siyosatlarni tozalab, qaytadan yaratamiz (idempotent)
drop policy if exists iqror_public_read   on storage.objects;
drop policy if exists iqror_admin_insert  on storage.objects;
drop policy if exists iqror_admin_update  on storage.objects;
drop policy if exists iqror_admin_delete  on storage.objects;

-- iqror_public_read (hamma, anon ham papkani ro'yxatlardi) endi YARATILMAYDI: o'rniga iqror_staff_read
--   (public-close.sql). Rasm/video ommaviy havola orqali ko'rinishda davom etadi.

-- Faqat admin yozadi (Firebase'dagi 'admin claim' talabining ekvivalenti)
create policy iqror_admin_insert on storage.objects
  for insert with check ( bucket_id = 'public' and app.is_admin() );
create policy iqror_admin_update on storage.objects
  for update using ( bucket_id = 'public' and app.is_admin() );
create policy iqror_admin_delete on storage.objects
  for delete using ( bucket_id = 'public' and app.is_admin() );

-- Izoh: agar o'qituvchilar ham rasm yuklashi kerak bo'lsa, app.is_admin() o'rniga
--   (app.is_admin() or app.is_zavuch()) yozing. Hozir eski qoida bilan bir xil (admin).
