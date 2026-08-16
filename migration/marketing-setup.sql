-- =====================================================================
-- Iqror Academy — Marketing / CRM — «enrollments» (arizalar) ga lead holati.
-- Bir marta bazada ishlating (Supabase SQL Editor yoki docker exec psql).
-- Idempotent: qayta ishlatsa ham xavfsiz.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/marketing-setup.sql
-- =====================================================================

-- Lead voronkasi uchun holat: yangi | boglanildi | sinov | qabul | rad
alter table enrollments add column if not exists status      text default 'yangi';
alter table enrollments add column if not exists note        text;
alter table enrollments add column if not exists "updatedAt" timestamptz default now();

-- Eslatma: RLS'da admin UPDATE ruxsati allaqachon bor (enr_upd) — qo'shimcha siyosat shart emas.
-- Reklama xarajati «expenses» (category='Reklama')dan olinadi — alohida jadval kerak emas.
