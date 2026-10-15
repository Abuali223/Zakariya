\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-2.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-2 — audit topilmalari bo'yicha tuzatmalar (2026-09).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- Idempotent.
-- =====================================================================

-- 1) applications: AI baholash natijasi/vaqti ustunlari yo'q edi — ai-grader yozganda xato
--    berib, baho SAQLANMASdan qayta-qayta baholanardi (token isrofi). Ustunlarni qo'shamiz.
alter table public.applications add column if not exists result jsonb;
alter table public.applications add column if not exists "gradedAt" timestamptz;

-- 2) exam_questions: ai-grader qaysi model bilan generatsiya qilganini yozadi (ustun yo'q edi).
alter table public.exam_questions add column if not exists model text;

-- 3) config: umumiy `config_sel using(true)` (rls.sql) maxfiy `config/salary`, `finance`, `ltv`
--    hujjatlarni ham HAMMAGA (hatto anonimga) ochib qo'ygan edi — HR-cheklovi amalda ishlamagan.
--    Sezgir qatorlarni cheklaymiz; ommaviy qatorlar (payments — parent to'lov havolasi;
--    ai — sayt chatboti; boshqalar) ochiq qoladi.
drop policy if exists config_sel on config;
create policy config_sel on config for select using (
      (id = 'salary'              and (app.is_admin() or app.is_hr() or app.is_finance()))   -- moliya payroll hisoblaydi
   or (id = 'security'            and app.is_admin())                                        -- refund PIN — faqat direktor
   or (id in ('finance','ltv')     and app.is_staff())
   or (id not in ('salary','finance','ltv','security'))
);

notify pgrst, 'reload schema';
