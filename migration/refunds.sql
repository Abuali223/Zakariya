-- =====================================================================
-- TO'LOVNI QAYTARISH JURNALI (refunds) — adashib kiritilgan to'lovni qaytarish.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/refunds.sql
--
-- FAQAT DIREKTOR (app.is_admin) qaytaradi va ko'radi. Har qaytarish: summa + sabab +
-- direktor paroli (klientda tasdiqlanadi) bilan yoziladi. Biriktirilmagan to'lovlarga ham.
-- Idempotent.
-- =====================================================================
create table if not exists public.refunds (
  id            text primary key default gen_random_uuid()::text,
  target        text,                          -- 'invoice' | 'payment'
  "targetId"    text,                          -- invoice id yoki payment id
  "studentId"   text,
  "studentName" text,
  amount        numeric,
  reason        text,
  "byEmail"     text,
  month         text,
  "createdAt"   timestamptz default now()
);
create index if not exists refunds_student_idx on public.refunds("studentId");
create index if not exists refunds_created_idx on public.refunds("createdAt");

alter table public.refunds enable row level security;
grant select, insert on public.refunds to authenticated;
grant select, insert, update, delete on public.refunds to service_role;

-- Faqat DIREKTOR (is_admin = director) yozadi/o'qiydi.
drop policy if exists refunds_sel on public.refunds;
create policy refunds_sel on public.refunds for select using (app.is_admin());
drop policy if exists refunds_ins on public.refunds;
create policy refunds_ins on public.refunds for insert with check (app.is_admin());

notify pgrst, 'reload schema';
