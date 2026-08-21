-- =====================================================================
-- Audit 2b — Ota-ona↔farzand: MAXFIY KOD tizimi (IDOR ni to'liq yopadi).
-- Idempotent. Docker orqali:
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/security-2b.sql
--
-- Mexanizm:
--  * student_codes(id, code): har o'quvchiga maxfiy kod (faqat admin/zavuch ko'radi).
--  * child_claims(uid, studentId, code): ota-ona ID+KOD kiritib biriktiradi;
--    INSERT RLS kodni app.code_ok() (SECURITY DEFINER) orqali tekshiradi.
--  * owns_child endi child_claims'ni o'qiydi (users.childIds'ga TAYANMAYDI).
--  Natija: begona bolani "farzandim" deb qo'shib bo'lmaydi — kod kerak.
-- =====================================================================

-- ---- 1. Maxfiy kodlar jadvali ----
create table if not exists student_codes(
  id text primary key,                 -- = studentId
  code text,
  "updatedAt" timestamptz default now()
);
alter table student_codes enable row level security;
drop policy if exists sc_sel on student_codes;
create policy sc_sel on student_codes for select using (app.is_admin() or app.is_zavuch());
-- yozish faqat service_role / definer funksiyalar orqali (mijozga insert/update/delete yo'q)
grant select on student_codes to anon, authenticated;
grant all on student_codes to service_role;

-- Mavjud o'quvchilarga kod generatsiya (6 belgi, katta harf/raqam)
insert into student_codes(id, code)
  select s.id, upper(substr(md5(random()::text || s.id || clock_timestamp()::text), 1, 6))
  from public.students s
  on conflict (id) do nothing;

-- Yangi o'quvchi qo'shilganda avtomatik kod
create or replace function app.gen_student_code() returns trigger language plpgsql security definer as $$
begin
  insert into public.student_codes(id, code)
    values (NEW.id, upper(substr(md5(random()::text || NEW.id || clock_timestamp()::text), 1, 8)))
    on conflict (id) do nothing;
  return NEW;
end $$;
drop trigger if exists trg_student_code on students;
create trigger trg_student_code after insert on students for each row execute function app.gen_student_code();

-- ---- 2. Kodni tekshiruvchi (SECURITY DEFINER — student_codes RLS'ini chetlab o'tadi) ----
create or replace function app.code_ok(sid text, c text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.student_codes where id = sid and code = c and coalesce(c,'') <> '')
$$;

-- ---- 3. Biriktirish jadvali (ota-ona ID+kod kiritadi) ----
create table if not exists child_claims(
  id text primary key,                 -- shim addDoc random uuid
  uid text,
  "studentId" text,
  code text,
  created timestamptz default now()
);
create unique index if not exists uq_child_claims on child_claims (uid, "studentId");
alter table child_claims enable row level security;
drop policy if exists cc_ins on child_claims;
drop policy if exists cc_sel on child_claims;
drop policy if exists cc_del on child_claims;
-- INSERT: faqat o'z uid'i uchun VA kod to'g'ri bo'lsa
create policy cc_ins on child_claims for insert with check (uid = app.uid() and app.code_ok("studentId", code));
create policy cc_sel on child_claims for select using (uid = app.uid() or app.is_admin() or app.is_zavuch());
create policy cc_del on child_claims for delete using (uid = app.uid() or app.is_admin());
grant select, insert, delete on child_claims to anon, authenticated;
grant all on child_claims to service_role;

-- ---- 4. owns_child endi child_claims'ni o'qiydi ----
create or replace function app.owns_child(sid text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.child_claims where uid = app.uid() and "studentId" = sid)
$$;

-- ---- 5. Mavjud biriktirishlarni ko'chirish (uzilish bo'lmasin; admin keyin ko'rib chiqsin) ----
insert into child_claims(id, uid, "studentId", code)
  select u.id || '__' || sid, u.id, sid, ''
  from public.users u, jsonb_array_elements_text(coalesce(u."childIds",'[]'::jsonb)) sid
  where coalesce(u."childIds",'[]'::jsonb) <> '[]'::jsonb
  on conflict (uid, "studentId") do nothing;
