\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: school-holidays.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- school_holidays — MAKTAB BO'YICHA dam olish / bayram kunlari (Mustaqillik kuni, Navro'z, ...).
--   Bu kunlarda maktab yopiq: hech kim kamera skan qilmaydi. Ilgari attMetrics har ish kunini
--   (skan yo'q -> «yo'qlama») sanab, bayramda HAR xodimdan bir kunlik maosh ushlab qolardi
--   (yagona chora — har xodimga alohida «Ruhsat» kiritish edi). Endi bayram kuni xodim davomati
--   hisobida (ushlanma, «Ruhsatsiz», ish kunlari) O'TKAZIB yuboriladi — haq to'lanadigan dam kuni
--   (oylik kamaymaydi; kunlik stavka o'zgarmaydi).
--   Bitta kun = bitta yozuv: id = 'YYYY-MM-DD'.
-- Idempotent (run-all.sql zanjirida; deploy har safar qayta qo'llaydi — ma'lumot o'zgarmaydi).
-- =====================================================================

create table if not exists public.school_holidays (
  id          text primary key,              -- 'YYYY-MM-DD'
  day         text,                          -- 'YYYY-MM-DD' (id bilan bir xil — so'rovlar uchun)
  name        text,                          -- masalan «Mustaqillik kuni»
  "createdBy" text,
  "createdAt" timestamptz default now()
);
create index if not exists school_holidays_day_idx on public.school_holidays(day);

alter table public.school_holidays enable row level security;
grant select, insert, update, delete on public.school_holidays to authenticated;
grant all on public.school_holidays to service_role;

-- O'qiydi: barcha FAOL xodimlar (kurator/o'qituvchi ham — o'quvchi davomatida «bayram» ogohlantirishi)
--   + kassir (maosh berishda ushlanma hisobi). Ma'lumot maxfiy emas (sana + nom).
drop policy if exists hol_sel on public.school_holidays;
create policy hol_sel on public.school_holidays for select using (app.is_staff() or app.is_cashier());
-- Belgilaydi/o'chiradi: faqat Ma'muriyat/HR (xodim davomati va maosh qoidalarini boshqaruvchilar).
drop policy if exists hol_ins on public.school_holidays;
create policy hol_ins on public.school_holidays for insert with check (app.is_admin() or app.is_hr());
drop policy if exists hol_upd on public.school_holidays;
create policy hol_upd on public.school_holidays for update using (app.is_admin() or app.is_hr()) with check (app.is_admin() or app.is_hr());
drop policy if exists hol_del on public.school_holidays;
create policy hol_del on public.school_holidays for delete using (app.is_admin() or app.is_hr());

notify pgrst, 'reload schema';
