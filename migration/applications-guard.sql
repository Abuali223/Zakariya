\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: applications-guard.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- applications-guard.sql — ariza (imtihon) INSERT siyosatini mahkamlash.
--
--   MUAMMO: app_ins faqat status='submitted' ni tekshirardi. To'g'ridan-to'g'ri
--   PostgREST insert orqali nomzod 'result'/'gradedAt' ni oldindan to'ldirib yuborishi
--   mumkin edi (UI buni yubormaydi, lekin RLS buni to'smaydi). Baho faqat ma'muriyatники
--   (app_upd: admin/zavuch) bo'lishi kerak.
--
--   TUZATMA: INSERT with_check — status='submitted' VA result IS NULL VA gradedAt IS NULL.
--   Haqiqiy forma (imtihon.html) faqat {name,phone,specialty,answers,status,ts,day,created}
--   yuboradi — result/gradedAt yubormaydi, shuning uchun bu o'zgarish ARIZA oqimini buzmaydi.
--
-- Idempotent — QAYTA ishga tushirishга xavfsiz. run-all.sql + deploy.sh'da.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

drop policy if exists app_ins on public.applications;
create policy app_ins on public.applications for insert
  with check (status = 'submitted' and "result" is null and "gradedAt" is null);

notify pgrst, 'reload schema';
