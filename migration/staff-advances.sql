\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: staff-advances.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- XODIM AVANSI (staff_advances): xodimга oy ichida oldindan berilgan maosh.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
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
-- DIQQAT (bog'liqlik tartibi): bu fayl run-all.sql'da roles-rbac.sql (app.is_hr) va cashier-role.sql
--   (app.is_cashier)'dan OLDIN ishlaydi -> bu yerda faqat MAVJUD funksiyalar (is_admin). YAKUNIY sa_sel
--   (admin/HR/moliya/kassir) audit-3.sql'da o'rnatiladi; deploy butun zanjirni tartib bilan qo'llaydi.
--   (Avval bu yerda is_hr() yozilgan edi — toza o'rnatishda "function app.is_hr() does not exist" bilan
--   butun run-all.sql to'xtardi.)
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
