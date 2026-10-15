\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: parent-student-links.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- OTA-ONA <-> FARZAND BOG'LANISHI — mavjud `child_claims` jadvali = spec'dagi
--   `parent_student_links` (uid = parent_id, "studentId" = student_id).
--   Bog'lash yo'li O'ZGARMAYDI: public.claim_child(sid, code) RPC (o'quvchi kodi + lockout).
--   Bu yerda faqat `status` ustuni qo'shiladi: hozir DARHOL 'active' (kodning o'zi isbot),
--   kelajakda admin-tasdig'i rejimi kerak bo'lsa 'pending' ishlatish mumkin (claim_child shuni yozadi).
-- Idempotent. run-all.sql + deploy.sh'da.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

alter table public.child_claims add column if not exists status      text default 'active';   -- active | pending | revoked
alter table public.child_claims add column if not exists "updatedAt" timestamptz;

-- Mavjud qatorlar (status NULL) -> 'active' (orqaga moslik: eski bog'lanishlar uzilmasin).
update public.child_claims set status = 'active' where status is null;

create index if not exists idx_child_claims_status on public.child_claims(status);

notify pgrst, 'reload schema';
