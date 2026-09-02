-- =====================================================================
-- AUDIT-2 — audit topilmalari bo'yicha tuzatmalar (2026-09).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/audit-2.sql
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
      (id = 'salary'              and (app.is_admin() or app.is_hr()))
   or (id in ('finance','ltv')     and app.is_staff())
   or (id not in ('salary','finance','ltv'))
);

notify pgrst, 'reload schema';
