-- =====================================================================
-- ARZ-SHIKOYAT / E'TIROF (feedback) — ota-ona/o'quvchi maktab ma'muriyatiga.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/feedback.sql
--
-- Yozadi: tizimga kirgan ota-ona/o'quvchi (uid = o'zi).
-- Ko'radi/boshqaradi: Direktor + Ma'muriyat rahbari (is_admin / is_admin_head).
-- Yuboruvchi O'Z murojaatini + javobini ko'radi.
-- Idempotent.
-- =====================================================================
create table if not exists public.feedback (
  id           text primary key default gen_random_uuid()::text,
  type         text not null default 'shikoyat',   -- shikoyat | etirof | taklif
  uid          text,
  "authorName" text,
  "authorRole" text,                                 -- parent | student
  "studentId"  text,
  "studentName" text,
  "text"       text,
  status       text not null default 'new',          -- new | read | resolved
  reply        text,
  "createdAt"  timestamptz default now(),
  "updatedAt"  timestamptz
);
create index if not exists feedback_uid_idx    on public.feedback(uid);
create index if not exists feedback_status_idx on public.feedback(status);

alter table public.feedback enable row level security;
grant select, insert, update, delete on public.feedback to authenticated;
grant select, insert, update, delete on public.feedback to service_role;

-- INSERT: faqat tizimga kirgan foydalanuvchi va faqat O'ZI nomidan (uid = o'zi).
drop policy if exists fb_ins on public.feedback;
create policy fb_ins on public.feedback for insert with check (uid = app.uid());

-- SELECT: yuboruvchi O'ZINIKINI; Direktor + Ma'muriyat rahbari — HAMMASINI.
drop policy if exists fb_sel on public.feedback;
create policy fb_sel on public.feedback for select using (uid = app.uid() or app.is_admin() or app.is_admin_head());

-- UPDATE: Direktor + Ma'muriyat rahbari (holat / javob).
drop policy if exists fb_upd on public.feedback;
create policy fb_upd on public.feedback for update using (app.is_admin() or app.is_admin_head()) with check (app.is_admin() or app.is_admin_head());

-- DELETE: faqat Direktor.
drop policy if exists fb_del on public.feedback;
create policy fb_del on public.feedback for delete using (app.is_admin());

notify pgrst, 'reload schema';
