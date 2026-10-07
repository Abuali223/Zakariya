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
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/applications-guard.sql
-- =====================================================================

drop policy if exists app_ins on public.applications;
create policy app_ins on public.applications for insert
  with check (status = 'submitted' and "result" is null and "gradedAt" is null);

notify pgrst, 'reload schema';
