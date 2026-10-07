-- =====================================================================
-- secdef-searchpath.sql — SECURITY DEFINER funksiyalarга search_path mahkamlash.
--
--   MUAMMO: app.* RLS yordamchilari (is_admin, owns_child, ...) SECURITY DEFINER
--   (postgres huquqida ishlaydi) edi, lekin search_path O'RNATILMAGAN. Bu — klassik
--   imtiyoz oshirish (privilege escalation) yo'li: chaqiruvchi search_path'ni o'zgartirib
--   funksiya ichidagi obyektni (jadval/operator/cast) soxta sxema bilan "soyalashi" mumkin.
--   Supabase'ning o'z xavfsizlik linteri ham shuni belgilaydi (0011_function_search_path_mutable).
--
--   TUZATMA: har bir SECURITY DEFINER app.* funksiyasiga barqaror search_path.
--   Funksiya TANASI o'zgarmaydi (ular allaqachon public.* ni to'liq nom bilan yozadi) —
--   bu FAQAT himoya. apply_payment/adjust_credit/... RPC'lari allaqachon search_path pinланган.
--
--   DIQQAT: FORCE ROW LEVEL SECURITY bu arxitekturaга MOS EMAS — SECURITY DEFINER pul
--   RPC'lari (applied_payments/credit_ledger'ga yozadi) egasi superuser bo'lmasa RLS'ga
--   tushib buzilardi; postgres superuser bo'lsa — foydasiz (no-op). Shuning uchun FORCE
--   QO'LLANMAYDI; himoya search_path orqali beriladi.
--
-- Idempotent — QAYTA ishga tushirishга xavfsiz (ALTER ... SET qayta o'rnatadi).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/secdef-searchpath.sql
-- =====================================================================

do $$
declare r record;
begin
  for r in
    select n.nspname, p.proname,
           pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app'
      and p.prosecdef = true
      and p.proconfig is null       -- faqat hali o'rnatilmaganlarini
  loop
    execute format('alter function app.%I(%s) set search_path = public, app, pg_temp',
                   r.proname, r.args);
  end loop;
end $$;

notify pgrst, 'reload schema';
