-- =====================================================================
-- AUDIT-6 — Kichik RLS qat'iylashtirish (audit topilmalari).
--   timetable / homework SELECT `using(true)` (anonim ham o'qiy oladi) edi — rls.sql izohi
--   aslida "tizimga kirganlar o'qiydi" degan edi, lekin cheklov qo'llanmagan. Endi kirgan
--   foydalanuvchi (app.uid() is not null) o'qiydi. Kabinet ota-ona (Google/anonim auth) baribir
--   kirgan bo'ladi -> dars jadvali/uy vazifasi ko'rinaveradi; oddiy anonim (kirmagan) ko'rmaydi.
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/audit-6.sql
-- =====================================================================

do $$
begin
  if to_regclass('public.timetable') is not null then
    drop policy if exists timetable_sel on public.timetable;
    create policy timetable_sel on public.timetable for select using (app.uid() is not null);
  end if;
  if to_regclass('public.homework') is not null then
    drop policy if exists homework_sel on public.homework;
    create policy homework_sel on public.homework for select using (app.uid() is not null);
  end if;
end $$;

notify pgrst, 'reload schema';
