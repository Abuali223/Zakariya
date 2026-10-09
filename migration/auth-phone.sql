-- =====================================================================
-- TELEFON + PAROL AUTH — users jadvaliga telefon/ism maydonlari + RLS qattiqlashtirish.
--   Identifikator: telefon (+998XXXXXXXXX) -> sintetik email '998XXXXXXXXX@phone.<domen>'
--   Parol: Supabase Auth (bcrypt) — public.users'da PAROL SAQLANMAYDI (auth.users ichida).
--   phone/status/role/verified — AUTHZ maydonlari: foydalanuvchi O'ZI o'zgartira OLMAYDI
--     (faqat admin yoki server/service_role). firstName/lastName — o'zi tahrirlashi mumkin.
-- Idempotent. run-all.sql + deploy.sh'da.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/auth-phone.sql
-- =====================================================================

-- 1) Yangi ustunlar (barchasi ixtiyoriy — mavjud email-foydalanuvchilar buzilmaydi).
alter table public.users add column if not exists phone        text;   -- kanonik: 998XXXXXXXXX (12 raqam)
alter table public.users add column if not exists "firstName"  text;
alter table public.users add column if not exists "lastName"   text;
alter table public.users add column if not exists status       text default 'active';   -- active | pending | blocked
alter table public.users add column if not exists "updatedAt"  timestamptz;

-- 2) Telefon — YAGONA (bo'sh/NULL bundan mustasno). Bir telefon = bitta hisob.
create unique index if not exists uq_users_phone
  on public.users (phone) where phone is not null and phone <> '';

-- 3) RLS: self-update'da phone/status'ni ham QOTIRAMIZ (role/verified/sinflar allaqachon qotirilgan).
--    Telefon o'zgartirish FAQAT server orqali (yangi raqamga OTP bilan) — service_role bajaradi.
--    firstName/lastName/name/childId/activeChildId — o'zi tahrirlashi mumkin (profil).
drop policy if exists users_upd on users;
create policy users_upd on users for update using (app.is_admin() or id = app.uid())
  with check (app.is_admin() or (
     id = app.uid()
     and role     = (select u.role     from public.users u where u.id = app.uid())
     and verified = (select u.verified from public.users u where u.id = app.uid())
     and coalesce(status, 'active') = coalesce((select u.status from public.users u where u.id = app.uid()), 'active')
     and coalesce(phone, '')        = coalesce((select u.phone  from public.users u where u.id = app.uid()), '')
     and coalesce("childIds",        '[]'::jsonb) = coalesce((select u."childIds"        from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("homeroomClasses", '[]'::jsonb) = coalesce((select u."homeroomClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedClasses", '[]'::jsonb) = coalesce((select u."assignedClasses" from public.users u where u.id = app.uid()), '[]'::jsonb)
     and coalesce("assignedSubjects",'[]'::jsonb) = coalesce((select u."assignedSubjects" from public.users u where u.id = app.uid()), '[]'::jsonb)
  ));

-- 4) Self-insert: teacher'ni ham ruxsat beramiz (verified=false -> admin tasdig'igача cheklangan).
--    (Avval faqat parent/student edi.) role/verified bundan boshqa bo'lsa — admin shart.
--    Eslatma: ODATDA ro'yxatdan o'tish SERVER (service_role) orqali bo'ladi; bu policy — zaxira/mijoz yo'li.
drop policy if exists users_ins on users;
create policy users_ins on users for insert with check (
  app.is_admin() or (id = app.uid() and role in ('parent','student','teacher') and verified = false)
);

notify pgrst, 'reload schema';
