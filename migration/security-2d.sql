\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: security-2d.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- Audit 2d — enrollments (ommaviy ariza): maydon injeksiyasini yopish.
-- Idempotent. Docker orqali:
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
--
-- Muammo: enr_ins with check(true) -> begona odam to'g'ridan-to'g'ri INSERT bilan
--   status='qabul' (soxta "qabul qilingan" lead) yoki note (adminning ichki izohi)
--   ni o'rnatib, admin voronkasini ifloslashi mumkin edi. Ommaviy forma bu
--   maydonlarni HECH QACHON yubormaydi (faqat name/phone/grade/direction/lang/ts).
--
-- Yechim: ommaviy (admin bo'lmagan) INSERT'da status faqat boshlang'ich ('yangi'
--   yoki null->default) va note bo'sh bo'lishi shart. Admin CHEKLANMAYDI —
--   voronka boshqaruvi (status yangilash setDoc/upsert orqali) buzilmasin.
-- =====================================================================

drop policy if exists enr_ins on public.enrollments;
create policy enr_ins on public.enrollments for insert with check (
  app.is_admin()
  or ((status is null or status = 'yangi') and note is null)
);

-- Eslatma: applications jadvali allaqachon himoyalangan (app_ins: status='submitted').
