-- Lokal stend (tests/kassa-e2e): Supabase'da 'authenticated' storage.objects ga yetadi va RLS hal qiladi. Lokal server
--   storage.objects ga CHAQIRUVCHI nomidan (authenticated + JWT claims) yozadi va o'qiydi — repo'dagi tibbiy papka siyosatlari
--   (nurse-sick.sql) prod'dagidek ishlaydi. Zanjirdan keyin, urug'dan oldin qo'llanadi (stand.sh).
grant usage on schema storage to authenticated, anon;
grant select, insert on storage.objects to authenticated;
