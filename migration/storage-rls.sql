-- =====================================================================
-- storage-rls.sql — Supabase Storage (storage.objects) uchun RLS.
-- Eski Firebase Storage qoidasi bilan bir xil: HAMMA o'qiydi (public bucket),
-- faqat ADMIN yuklaydi/o'chiradi (admin panelidan rasm/video).
--
-- ⚠️ Bu FAQAT Supabase o'rnatilgach ishlaydi (storage sxemasi Supabase tomonidan
--    yaratiladi). rls.sql (bare Postgres'da sinaladigan) ichiga QO'SHILMAYDI.
-- Ishga tushirish (VPS'da, rls.sql dan keyin):
--    psql "$PGURL" -f storage-rls.sql
-- =====================================================================

-- Supabase 'public' bucket ni yaratadi (import-auth-storage.cjs ham yaratadi).
-- storage.objects'da RLS Supabase'da odatda YOQILGAN.

-- Eski siyosatlarni tozalab, qaytadan yaratamiz (idempotent)
drop policy if exists iqror_public_read   on storage.objects;
drop policy if exists iqror_admin_insert  on storage.objects;
drop policy if exists iqror_admin_update  on storage.objects;
drop policy if exists iqror_admin_delete  on storage.objects;

-- Hamma o'qiydi (rasm/video ommaviy ko'rinadi)
create policy iqror_public_read on storage.objects
  for select using ( bucket_id = 'public' );

-- Faqat admin yozadi (Firebase'dagi 'admin claim' talabining ekvivalenti)
create policy iqror_admin_insert on storage.objects
  for insert with check ( bucket_id = 'public' and app.is_admin() );
create policy iqror_admin_update on storage.objects
  for update using ( bucket_id = 'public' and app.is_admin() );
create policy iqror_admin_delete on storage.objects
  for delete using ( bucket_id = 'public' and app.is_admin() );

-- Izoh: agar o'qituvchilar ham rasm yuklashi kerak bo'lsa, app.is_admin() o'rniga
--   (app.is_admin() or app.is_zavuch()) yozing. Hozir eski qoida bilan bir xil (admin).
