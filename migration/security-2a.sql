-- =====================================================================
-- Audit 2a — RLS xavfsizlik (IDOR + imtiyoz oshirish darhol yopiladi).
-- Idempotent. Docker orqali:
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/security-2a.sql
--
-- Nima qiladi:
-- (1) users_upd: foydalanuvchi O'ZI childIds/homeroomClasses/assignedClasses/
--     assignedSubjects ni O'ZGARTIRA OLMAYDI (faqat admin). Bu:
--       - IDOR ni yopadi: begona bolani "farzandim" deb qo'shib bo'lmaydi;
--       - privesc ni yopadi: o'ziga homeroom/sinf berib "rahbar" bo'lib bo'lmaydi.
-- (2) is_homeroom_for: rol darvozasi (parent/student homeroom bo'la olmaydi).
--
-- ESLATMA: shundan keyin ota-ona O'ZI farzand qo'sha OLMAYDI (childIds muzlagan).
--   Buni 2b (maxfiy kod tizimi) xavfsiz tarzda tiklaydi. Mavjud biriktirishlar
--   ishlashda davom etadi (owns_child hali childIds'ni o'qiydi).
-- =====================================================================

-- (2) is_homeroom_for — rol tekshiruvi qo'shildi
create or replace function app.is_homeroom_for(ck text) returns boolean language sql stable security definer as $$
  select exists(
    select 1 from public.users
    where id = app.uid()
      and role in ('admin','zavuch','kurator','teacher')
      and coalesce("homeroomClasses",'[]'::jsonb) ? ck
  )
$$;

-- (1) users_upd — barcha avtorizatsiya ustunlarini muzlatadi
drop policy if exists users_upd on users;
create policy users_upd on users for update using (app.is_admin() or id = app.uid())
  with check (app.is_admin() or (
     id = app.uid()
     and role     = (select u.role     from public.users u where u.id = app.uid())
     and verified = (select u.verified from public.users u where u.id = app.uid())
     and coalesce("childIds",        '[]'::jsonb) = coalesce((select u."childIds"        from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("homeroomClasses", '[]'::jsonb) = coalesce((select u."homeroomClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedClasses", '[]'::jsonb) = coalesce((select u."assignedClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedSubjects",'[]'::jsonb) = coalesce((select u."assignedSubjects" from public.users u where u.id = app.uid()), '[]'::jsonb)
  ));
