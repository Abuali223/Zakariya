-- =====================================================================
-- USTOZGA REYTING (teacher_ratings) — ota-ona (har doim) + o'quvchi (5-sinfdan).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/teacher-ratings.sql
--
-- Bir foydalanuvchi bir ustozga BITTA ovoz (id = uid__teacherId, upsert).
-- O'rtacha reyting TRIGGER orqali teachers.rating/votes'ga avtomatik yoziladi
-- (ommaviy sayt teachers_public'dan shu qiymatni ko'rsatadi).
-- 5-sinf cheklovi — klient tomonда (UX); bu yerда har kirgan foydalanuvchi
-- o'zi nomidan ovoz bera oladi (past sinf ovozi xavfsizlik xatari emas).
-- Idempotent.
-- =====================================================================
create table if not exists public.teacher_ratings (
  id          text primary key,            -- uid__teacherId
  "teacherId" text not null,
  uid         text not null,
  "raterRole" text,                          -- parent | student
  "studentId" text,
  stars       int  not null check (stars between 1 and 5),
  comment     text,
  "updatedAt" timestamptz default now()
);
create index if not exists tr_teacher_idx on public.teacher_ratings("teacherId");
create index if not exists tr_uid_idx     on public.teacher_ratings(uid);

alter table public.teacher_ratings enable row level security;
grant select, insert, update, delete on public.teacher_ratings to authenticated;
grant select, insert, update, delete on public.teacher_ratings to service_role;

-- INSERT/UPDATE: faqat O'ZI nomidan (uid = app.uid()) — upsert ikkalasini talab qiladi.
drop policy if exists tr_ins on public.teacher_ratings;
create policy tr_ins on public.teacher_ratings for insert with check (uid = app.uid());
drop policy if exists tr_upd on public.teacher_ratings;
create policy tr_upd on public.teacher_ratings for update using (uid = app.uid()) with check (uid = app.uid());
-- SELECT: yuboruvchi O'ZINIKINI; xodimlar (is_staff) — sharhlarni ko'rish uchun.
drop policy if exists tr_sel on public.teacher_ratings;
create policy tr_sel on public.teacher_ratings for select using (uid = app.uid() or app.is_staff());
-- DELETE: o'zi yoki Direktor.
drop policy if exists tr_del on public.teacher_ratings;
create policy tr_del on public.teacher_ratings for delete using (uid = app.uid() or app.is_admin());

-- O'rtacha reyting -> teachers.rating/votes (definer huquqi bilan; RLS'ni chetlab o'tadi).
create or replace function app.recompute_teacher_rating() returns trigger language plpgsql security definer as $$
declare tid text;
begin
  tid := coalesce(NEW."teacherId", OLD."teacherId");
  update public.teachers t set
    rating = coalesce((select round(avg(r.stars)::numeric, 1) from public.teacher_ratings r where r."teacherId" = tid), t.rating),
    votes  = (select count(*) from public.teacher_ratings r where r."teacherId" = tid)
  where t.id = tid;
  return null;
end $$;
drop trigger if exists trg_teacher_rating on public.teacher_ratings;
create trigger trg_teacher_rating after insert or update or delete on public.teacher_ratings
  for each row execute function app.recompute_teacher_rating();

notify pgrst, 'reload schema';
