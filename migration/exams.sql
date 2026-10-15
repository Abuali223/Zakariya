\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: exams.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- IMTIHON JADVALI (exams) — har sinf uchun; o'quvchi/ota-ona kabinetда ko'radi.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
--
-- Boshqaradi: Direktor + Zavuch (akademik). O'qiydi: hamma (kabinet).
-- classKey = til-sinf-guruh (uy vazifasi/dars jadvali bilan bir xil format).
-- Idempotent.
-- =====================================================================
create table if not exists public.exams (
  id          text primary key default gen_random_uuid()::text,
  "classKey"  text,
  subject     text,
  date        text,
  "time"      text,
  room        text,
  note        text,
  "createdAt" timestamptz default now()
);
create index if not exists exams_class_idx on public.exams("classKey");

alter table public.exams enable row level security;
grant select, insert, update, delete on public.exams to authenticated;
grant select on public.exams to anon;
grant select, insert, update, delete on public.exams to service_role;

-- SELECT: hamma o'qiydi (kabinet — o'quvchi/ota-ona).
drop policy if exists exams_sel on public.exams;
create policy exams_sel on public.exams for select using (true);
-- WRITE: Direktor + Zavuch (akademik bo'lim).
drop policy if exists exams_ins on public.exams;
create policy exams_ins on public.exams for insert with check (app.is_admin() or app.is_zavuch());
drop policy if exists exams_upd on public.exams;
create policy exams_upd on public.exams for update using (app.is_admin() or app.is_zavuch()) with check (app.is_admin() or app.is_zavuch());
drop policy if exists exams_del on public.exams;
create policy exams_del on public.exams for delete using (app.is_admin() or app.is_zavuch());

notify pgrst, 'reload schema';
