\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: staff.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- XODIMLAR (staff) — o'qituvchi BO'LMAGAN, maosh oladigan xodimlar.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
--
-- Qorovul, oshpaz, tozalovchi, g'aznachi va h.k. «Maosh berish» / «Xodim avansi» /
-- «Oylik maoshni yozish» da o'qituvchilar bilan BIRGA ro'yxatga tushadi.
-- Boshqaradi: Direktor + HR. O'qiydi: + Moliya (payroll). Idempotent.
-- =====================================================================
create table if not exists public.staff (
  id           text primary key default gen_random_uuid()::text,
  "staffId"    text,
  name         text,
  position     text,                            -- lavozim
  phone        text,
  salary       text,                            -- oylik maosh (matn: "3 000 000" — salaryNum o'qiydi)
  note         text,
  "order"      numeric,
  "createdAt"  timestamptz default now(),
  "updatedAt"  timestamptz
);
create index if not exists staff_order_idx on public.staff("order");

alter table public.staff enable row level security;
grant select, insert, update, delete on public.staff to authenticated;
grant select, insert, update, delete on public.staff to service_role;

drop policy if exists staff_sel on public.staff;
create policy staff_sel on public.staff for select using (app.is_admin() or app.is_hr() or app.is_finance());
drop policy if exists staff_ins on public.staff;
create policy staff_ins on public.staff for insert with check (app.is_admin() or app.is_hr());
drop policy if exists staff_upd on public.staff;
create policy staff_upd on public.staff for update using (app.is_admin() or app.is_hr()) with check (app.is_admin() or app.is_hr());
drop policy if exists staff_del on public.staff;
create policy staff_del on public.staff for delete using (app.is_admin() or app.is_hr());

notify pgrst, 'reload schema';
