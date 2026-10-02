-- =====================================================================
-- XODIM RUHSAT / KASALLIK (davomat hisoboti uchun qo'lda kiritiladi).
--   Kamera faqat YUZNI ko'radi — kelmagan odam haqida hech narsa yubormaydi.
--   Shuning uchun «ruhsat so'rab ishdan qoldi» / «kasallik»ни direktor/HR
--   QO'LDA kiritadi. Oylik hisobot kelmagan kunни ruhsat/kasallik yoki
--   ruhsatsiz (sababsiz)ga ajratadi.
-- Idempotent. run-all.sql + deploy.sh'да.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/staff-leaves.sql
-- =====================================================================

create table if not exists public.staff_leaves (
  id          text primary key,
  "refId"     text,                         -- xodim/o'qituvchi _id (staff/teachers)
  "refType"   text,                         -- 'staff' | 'teacher'
  "cameraId"  text,                          -- kiritilган vaqtdagi Kamera ID (ma'lumot uchun)
  name        text,                          -- ism (kiritilган vaqtda)
  type        text,                          -- 'ruhsat' | 'kasallik'
  "startDay"  text,                          -- 'YYYY-MM-DD' (shu kundan)
  "endDay"    text,                          -- 'YYYY-MM-DD' (shu kungacha, ichiga oladi)
  reason      text,                          -- sabab (ixtiyoriy)
  "createdBy" text,                          -- kim kiritdi (email/rol)
  "createdAt" timestamptz default now()
);
create index if not exists staff_leaves_ref_idx   on public.staff_leaves("refType","refId");
create index if not exists staff_leaves_start_idx on public.staff_leaves("startDay");
create index if not exists staff_leaves_end_idx   on public.staff_leaves("endDay");

alter table public.staff_leaves enable row level security;
grant select, insert, update, delete on public.staff_leaves to authenticated;
grant all on public.staff_leaves to service_role;

-- O'qish + yozish: FAQAT direktor/HR (xodimlar davomati — HR ishi).
drop policy if exists sl_sel on public.staff_leaves;
create policy sl_sel on public.staff_leaves for select using (app.is_admin() or app.is_hr());
drop policy if exists sl_ins on public.staff_leaves;
create policy sl_ins on public.staff_leaves for insert with check (app.is_admin() or app.is_hr());
drop policy if exists sl_upd on public.staff_leaves;
create policy sl_upd on public.staff_leaves for update using (app.is_admin() or app.is_hr()) with check (app.is_admin() or app.is_hr());
drop policy if exists sl_del on public.staff_leaves;
create policy sl_del on public.staff_leaves for delete using (app.is_admin() or app.is_hr());

notify pgrst, 'reload schema';
