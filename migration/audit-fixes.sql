-- =====================================================================
-- AUDIT TUZATISHLARI (RLS + kod entropiyasi). Idempotent.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/audit-fixes.sql
-- =====================================================================

-- 1) Monitoring: o'qituvchi O'ZI qo'ygan bahoni TASDIQLAY olmaydi (status='approved' faqat admin/zavuch).
--    Ilgari mon_upd status'ni cheklamasди -> o'qituvchi PATCH bilan o'zini tasdiqlashi mumkin edi.
drop policy if exists mon_upd on monitoring;
create policy mon_upd on monitoring for update
  using  (app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject)))
  with check (app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject) and status='pending'));

-- 2) Farzand biriktirish kodi entropiyasi: 6 -> 8 belgi (16^6 ≈ 16M -> 16^8 ≈ 4.3 mlrd).
--    Faqat YANGI o'quvchilarga ta'sir qiladi (mavjud kodlar o'zgarmaydi, amal qiladi).
create or replace function app.gen_student_code() returns trigger language plpgsql security definer as $$
begin
  insert into public.student_codes(id, code)
    values (NEW.id, upper(substr(md5(random()::text || NEW.id || clock_timestamp()::text), 1, 8)))
    on conflict (id) do nothing;
  return NEW;
end $$;

notify pgrst, 'reload schema';
