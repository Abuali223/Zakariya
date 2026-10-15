\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: olympiads.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- OLIMPIADA BOSHQARUVI (olympiads) — o'quvchi olimpiada ishtiroki/natijasi.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
--
-- Boshqaradi: Direktor + Zavuch (akademik). O'qiydi: xodimlar + o'z farzandi.
-- Idempotent.
-- =====================================================================
create table if not exists public.olympiads (
  id           text primary key default gen_random_uuid()::text,
  "studentId"  text,
  "studentName" text,
  "classKey"   text,
  subject      text,
  name         text,                          -- olimpiada nomi
  level        text,                          -- maktab | tuman | viloyat | respublika | xalqaro
  result       text,                          -- ishtirokchi | 1 | 2 | 3 | golib | laureat
  date         text,
  mentor       text,
  note         text,
  "createdAt"  timestamptz default now()
);
create index if not exists olympiads_student_idx on public.olympiads("studentId");
create index if not exists olympiads_level_idx   on public.olympiads(level);

alter table public.olympiads enable row level security;
grant select, insert, update, delete on public.olympiads to authenticated;
grant select, insert, update, delete on public.olympiads to service_role;

-- SELECT: xodimlar + o'z farzandi (ota-ona kabinetда kelajakда ko'rsatish uchun).
drop policy if exists oly_sel on public.olympiads;
create policy oly_sel on public.olympiads for select using (app.is_staff() or app.owns_child("studentId"));
-- WRITE: Direktor + Zavuch (akademik bo'lim).
drop policy if exists oly_ins on public.olympiads;
create policy oly_ins on public.olympiads for insert with check (app.is_admin() or app.is_zavuch());
drop policy if exists oly_upd on public.olympiads;
create policy oly_upd on public.olympiads for update using (app.is_admin() or app.is_zavuch()) with check (app.is_admin() or app.is_zavuch());
drop policy if exists oly_del on public.olympiads;
create policy oly_del on public.olympiads for delete using (app.is_admin() or app.is_zavuch());

notify pgrst, 'reload schema';
