\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: marketing-setup.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- Iqror Academy — Marketing / CRM — «enrollments» (arizalar) ga lead holati.
-- Idempotent: qayta ishlatsa ham xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- Lead voronkasi uchun holat: yangi | boglanildi | sinov | qabul | rad
alter table enrollments add column if not exists status      text default 'yangi';
alter table enrollments add column if not exists note        text;
alter table enrollments add column if not exists "updatedAt" timestamptz default now();

-- Eslatma: RLS'da admin UPDATE ruxsati allaqachon bor (enr_upd) — qo'shimcha siyosat shart emas.
-- Reklama xarajati «expenses» (category='Reklama')dan olinadi — alohida jadval kerak emas.
