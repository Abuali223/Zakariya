\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: staff-attendance.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- XODIMLAR DAVOMATI (keldi-ketdi + tanaffus) — Hikvision FaceID terminalidan.
--   Kamera (yuz terminali) internet orqali TO'G'RIDAN-TO'G'RI serverga hodisa yuboradi
--   (HTTP Listening) -> payments serveri /hik/<secret> endpointi -> shu jadvalga yozadi.
--   Har skan bitta qator: status = keldi/ketdi/tanaffus-chiqdi/tanaffus-qaytdi.
--   Admin «Xodimlar davomati» bo'limi personId<->cameraId bo'yicha xodimга bog'lab,
--   kelgan/ketgan/tanaffus/ish davomiyligini hisoblaydi.
-- Idempotent. run-all.sql + deploy.sh'да.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- Kamera ID (Hikvision person/employee ID) — xodim/o'qituvchiга bog'lash kaliti.
alter table public.staff    add column if not exists "cameraId" text;
alter table public.teachers add column if not exists "cameraId" text;

create table if not exists public.staff_checkins (
  id          text primary key,          -- dedup kaliti (qurilma serial / hash) — takror yozilmaydi
  "personId"  text,                       -- Hikvision employeeNoString (xom ID)
  "staffId"   text,                        -- bizning xodim id (ko'rinishda resolve qilinadi; ixtiyoriy)
  name        text,                        -- ism (hodisadan)
  status      text,                        -- 'in' | 'out' | 'break_out' | 'break_in' | 'unknown'
  ts          timestamptz,                 -- hodisa vaqti
  day         text,                        -- 'YYYY-MM-DD' (filtr uchun)
  raw         jsonb,                        -- asl hodisa (format moslash/diagnostika uchun)
  "createdAt" timestamptz default now()
);
create index if not exists staff_checkins_day_idx    on public.staff_checkins(day);
create index if not exists staff_checkins_person_idx on public.staff_checkins("personId");

alter table public.staff_checkins enable row level security;
grant select on public.staff_checkins to authenticated;
grant all    on public.staff_checkins to service_role;

-- O'qish: direktor/HR (xodimlar davomati — payroll/HR ishi). Yozish: FAQAT server (service_role —
--   kamera ko'prigi); authenticated'ga insert/update/delete policy yo'q -> klient yoza olmaydi.
drop policy if exists sc_chk_sel on public.staff_checkins;
create policy sc_chk_sel on public.staff_checkins for select using (app.is_admin() or app.is_hr() or app.is_finance() or app.is_cashier());

notify pgrst, 'reload schema';
