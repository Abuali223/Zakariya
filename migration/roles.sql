\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: roles.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- Xodim ro'llari: Direktor = admin darajasidagi ruxsat (RLS boundary).
-- O'IBDO' = mavjud 'zavuch' roli (o'zgarishsiz). Boshqa xodim ro'llari —
-- foydalanuvchilar bo'limida tayinlanadigan tashkiliy yorliqlar (panel ruxsati
-- alohida dizayn qilinadi). Idempotent. Docker orqali:
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================
create or replace function app.is_admin() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('admin','director'))
$$;
notify pgrst, 'reload schema';
