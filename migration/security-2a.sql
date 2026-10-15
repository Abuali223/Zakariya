\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: security-2a.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- Audit 2a — RLS xavfsizlik (IDOR + imtiyoz oshirish darhol yopiladi).
-- Idempotent. Docker orqali:
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
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
