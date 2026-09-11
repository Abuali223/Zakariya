-- =====================================================================
-- BIR MARTALIK (IXTIYORIY) — mavjud AVANSNI to'lanmagan fakturalarga qo'llaydi.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/apply-credit-sweep.sql
--
-- QACHON: audit-7.sql (apply_payment tuzatmasi) + rekey-students.sql'DAN KEYIN.
--   Avans xatosi tufayli o'quvchi balansiga ("Ortiqcha to'lov -> avans") tushib
--   qolgan pulni endi o'sha o'quvchining TO'LANMAGAN fakturalariga o'tkazadi
--   (faktura «paid» bo'lib ko'rinsin, avansda muzlab qolmasin).
--
--   Har o'quvchi uchun apply_payment(sid, 0, 'credit', ...) chaqiriladi: summa=0,
--   ya'ni FAQAT mavjud avans waterfall bilan eng eski fakturadan boshlab tushadi;
--   ortig'i (agar bo'lsa) avans bo'lib qoladi. Faktura yo'q bo'lsa — hech narsa
--   o'zgarmaydi (avans saqlanadi). IDEMPOTENT: qayta ishlatilса, avansi 0 bo'lganlar
--   o'tkazib yuboriladi (double-count yo'q — summa=0).
--
--   NB: apply_payment ruxsatni tekshiradi -> service_role sifatida ishlatamiz.
-- =====================================================================
select set_config('request.jwt.claims', '{"role":"service_role"}', false);
do $$
declare r record; n int := 0;
begin
  for r in select id from public.student_credit where coalesce(credit, 0) > 0 loop
    perform public.apply_payment(r.id, 0, 'credit',
      'sweep-' || r.id || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 10));
    n := n + 1;
  end loop;
  raise notice 'SWEEP: % ta o''quvchi avansi fakturalarga qo''llandi (bor bo''lsa).', n;
end $$;
notify pgrst, 'reload schema';
