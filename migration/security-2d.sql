-- =====================================================================
-- Audit 2d — enrollments (ommaviy ariza): maydon injeksiyasini yopish.
-- Idempotent. Docker orqali:
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/security-2d.sql
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
