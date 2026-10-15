\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: otp-codes.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- OTP KODLAR (telefon tasdiqlash) — ro'yxatdan o'tish / parol tiklash / telefon o'zgartirish.
--   Kod OCHIQ saqlanmaydi: HMAC-SHA256(server_secret, phone|purpose|code) hash'i saqlanadi.
--   TTL qisqa (2-3 daqiqa), urinishlar cheklangan (5), soatiga yuborish cheklangan (server).
--   Mijozga TO'LIQ YOPIQ (RLS on, policy YO'Q) — faqat auth-server (service_role) o'qiydi/yozadi.
-- Idempotent. run-all.sql + deploy.sh'da.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

create table if not exists public.otp_codes(
  id          bigint generated always as identity primary key,
  phone       text not null,                 -- kanonik 998XXXXXXXXX
  "codeHash"  text not null,                 -- HMAC-SHA256 hex (kod OCHIQ emas)
  purpose     text not null,                 -- register | login | reset | change_phone
  "expiresAt" timestamptz not null,
  attempts    int  default 0,                -- noto'g'ri kiritishlar (>=5 -> bloklash)
  consumed    boolean default false,         -- muvaffaqiyatli ishlatilgan (qayta ishlatilmaydi)
  ip          text,
  "createdAt" timestamptz default now()
);
-- Telefon bo'yicha oxirgi kodlar (rate-limit + joriy kodni topish uchun).
create index if not exists idx_otp_phone_created on public.otp_codes(phone, "createdAt" desc);
create index if not exists idx_otp_phone_purpose on public.otp_codes(phone, purpose, "createdAt" desc);

-- RLS yoqilgan, LEKIN hech qanday policy yo'q -> anon/authenticated mijoz UMUMAN ko'ra olmaydi.
--   Faqat service_role (RLS'ni chetlab o'tadi) ishlaydi.
alter table public.otp_codes enable row level security;
grant all on public.otp_codes to service_role;

-- Eskirgan/ishlatilgan kodlarni tozalash (server vaqti-vaqti bilan chaqiradi; ixtiyoriy).
create or replace function app.otp_gc() returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.otp_codes where "expiresAt" < now() - interval '1 day';
$$;

notify pgrst, 'reload schema';
