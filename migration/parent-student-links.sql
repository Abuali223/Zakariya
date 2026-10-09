-- =====================================================================
-- OTA-ONA <-> FARZAND BOG'LANISHI — mavjud `child_claims` jadvali = spec'dagi
--   `parent_student_links` (uid = parent_id, "studentId" = student_id).
--   Bog'lash yo'li O'ZGARMAYDI: public.claim_child(sid, code) RPC (o'quvchi kodi + lockout).
--   Bu yerda faqat `status` ustuni qo'shiladi: hozir DARHOL 'active' (kodning o'zi isbot),
--   kelajakda admin-tasdig'i rejimi kerak bo'lsa 'pending' ishlatish mumkin (claim_child shuni yozadi).
-- Idempotent. run-all.sql + deploy.sh'da.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/parent-student-links.sql
-- =====================================================================

alter table public.child_claims add column if not exists status      text default 'active';   -- active | pending | revoked
alter table public.child_claims add column if not exists "updatedAt" timestamptz;

-- Mavjud qatorlar (status NULL) -> 'active' (orqaga moslik: eski bog'lanishlar uzilmasin).
update public.child_claims set status = 'active' where status is null;

create index if not exists idx_child_claims_status on public.child_claims(status);

notify pgrst, 'reload schema';
