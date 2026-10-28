\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: staff-user-link.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- XODIM HISOBINI HR YOZUVIGA BOG'LASH (staff/teachers <-> users) — telefon bo'yicha.
--   Maqsad: xodim bazaga kiritilgan TELEFON bilan ro'yxatdan o'tsa, login hisobi
--   o'sha davomat/maosh yozuviga (staff yoki teachers) AVTOMATIK bog'lanadi.
--   MOLIYAVIY XAVFSIZLIK: bog'lanish FAQAT identifikatsiya (havola) — maosh/davomat
--   summalariga TEGMAYDI. Bog'lash FAQAT server (service_role, register) yoki admin
--   tomonidan o'rnatiladi; foydalanuvchi O'ZINI bog'lay/o'zgartira OLMAYDI (RLS qotiradi).
--
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- Idempotent. run-all.sql + deploy.sh'da (auth-phone.sql'DAN KEYIN — users_upd'ni qayta yaratadi).
-- =====================================================================

-- 1) users: HR yozuviga havola (qaysi staff/teacher) + audit.
alter table public.users add column if not exists "staffRefType" text;   -- 'staff' | 'teacher'
alter table public.users add column if not exists "staffRefId"   text;   -- staff/teachers.id (PK)
alter table public.users add column if not exists "staffCode"    text;   -- IQX-005 / IQT-003 (ko'rsatish)
alter table public.users add column if not exists "linkedAt"     timestamptz;
alter table public.users add column if not exists "linkedVia"    text;   -- 'auto' (register) | 'admin'

-- 2) staff/teachers: teskari havola (bu yozuvга qaysi login bog'langan).
alter table public.staff    add column if not exists "userUid" text;
alter table public.teachers add column if not exists "userUid" text;

-- 3) BIR-BIRGA-BIR kafolati (DB darajasida — ikki marta bog'lash imkonsiz):
--    - bitta staff/teacher yozuvi -> ko'pi bilan BITTA login;
--    - bitta (type,recordId) -> ko'pi bilan BITTA login.
create unique index if not exists uq_staff_user_uid
  on public.staff ("userUid") where "userUid" is not null and "userUid" <> '';
create unique index if not exists uq_teachers_user_uid
  on public.teachers ("userUid") where "userUid" is not null and "userUid" <> '';
create unique index if not exists uq_users_staffref
  on public.users ("staffRefType","staffRefId") where "staffRefId" is not null and "staffRefId" <> '';

-- 4) [CRITICAL] RLS: self-update'da BOG'LANISH havolasini QOTIRAMIZ. Aks holda oddiy
--    foydalanuvchi o'zini istalган (yuqori maoshli) xodim yozuviga bog'lab, kelajakda
--    maosh/davomat ko'rish/da'vo qilish huquqini o'g'irlashi mumkin edi (moliyaviy hujum).
--    Bog'lashni FAQAT admin yoki server (service_role, RLS chetlaydi) o'rnatadi.
--    (auth-phone.sql'даги users_upd'ни to'liq qayta yaratamiz + 3 ta yangi qotirilган maydon.)
drop policy if exists users_upd on users;
create policy users_upd on users for update using (app.is_admin() or id = app.uid())
  with check (app.is_admin() or (
     id = app.uid()
     and role     = (select u.role     from public.users u where u.id = app.uid())
     and verified = (select u.verified from public.users u where u.id = app.uid())
     and coalesce(status, 'active') = coalesce((select u.status from public.users u where u.id = app.uid()), 'active')
     and coalesce(phone, '')        = coalesce((select u.phone  from public.users u where u.id = app.uid()), '')
     and coalesce("staffRefType",'') = coalesce((select u."staffRefType" from public.users u where u.id = app.uid()), '')
     and coalesce("staffRefId",'')   = coalesce((select u."staffRefId"   from public.users u where u.id = app.uid()), '')
     and coalesce("staffCode",'')    = coalesce((select u."staffCode"    from public.users u where u.id = app.uid()), '')
     and coalesce("childIds",        '[]'::jsonb) = coalesce((select u."childIds"        from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("homeroomClasses", '[]'::jsonb) = coalesce((select u."homeroomClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedClasses", '[]'::jsonb) = coalesce((select u."assignedClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedSubjects",'[]'::jsonb) = coalesce((select u."assignedSubjects" from public.users u where u.id = app.uid()), '[]'::jsonb)
  ));

-- 5) [CRITICAL] RLS: self-INSERT'da ham bog'lanish havolasi BO'SH bo'lsin (users_upd kabi). auth-phone.sql'dagi users_ins
--    faqat id/rol/verified'ni tekshirardi: users qatori hali yo'q hisob (ochiq ro'yxatdan o'tish) birinchi yozuvidayoq o'zini
--    istalgan xodim yozuviga bog'lab (staffRefType/staffRefId — tasdiqlash oynasi shu lavozimga mos rolni oldindan tanlaydi;
--    haqiqiy xodim hisobini bog'lashni noyob indeks bilan to'sib) yoki soxta staffCode yozib qo'ya olardi. Bog'lashni FAQAT
--    admin yoki server (service_role) o'rnatadi. (Ustunlar shu faylda qo'shiladi — siyosat shu yerda qayta yaratiladi.)
drop policy if exists users_ins on users;
create policy users_ins on users for insert with check (
  app.is_admin() or (id = app.uid() and role in ('parent','student') and verified = false
    and coalesce("staffRefType", '') = '' and coalesce("staffRefId", '') = '' and coalesce("staffCode", '') = '')
);

notify pgrst, 'reload schema';
