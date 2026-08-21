-- =====================================================================
-- XODIM AVANSI (staff_advances): xodimга oy ichida oldindan berilgan maosh.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/staff-advances.sql
--
-- Xodim avansi — maktab BERGAN pul (xodimning shu oylik maoshidan). Oy oxirida
-- «Oylik maoshni yozish»да maosh xarajati TO'LIQ yoziladi (oylik mehnat qiymati),
-- avans esa "allaqachon berilgan" qism sifatida ko'rsatiladi -> naqd beriladigan
-- qoldiq = maosh − avans. Ikki marta hisoblanmaydi.
-- =====================================================================
create table if not exists staff_advances (
  id           text primary key,
  "teacherId"  text,
  "teacherName" text,
  amount       numeric,
  month        text,      -- "YYYY-MM"
  date         text,      -- "YYYY-MM-DD"
  note         text,
  "createdAt"  timestamptz default now()
);
alter table staff_advances enable row level security;
drop policy if exists sa_sel on staff_advances;
create policy sa_sel on staff_advances for select using (app.is_admin());
drop policy if exists sa_ins on staff_advances;
create policy sa_ins on staff_advances for insert with check (app.is_admin());
drop policy if exists sa_upd on staff_advances;
create policy sa_upd on staff_advances for update using (app.is_admin()) with check (app.is_admin());
drop policy if exists sa_del on staff_advances;
create policy sa_del on staff_advances for delete using (app.is_admin());
grant select, insert, update, delete on staff_advances to authenticated;
grant all on staff_advances to service_role;

notify pgrst, 'reload schema';
