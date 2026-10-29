\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: camera-days.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- camera_days — KAMERA ISHLAMAGAN KUNLARNI aniqlash uchun kunlik ma'lumot (faqat Kamera ID'lar, ism yo'q).
--   MUAMMO: xodim davomatida skani yo'q ish kuni = yo'qlama (bir kunlik maosh ushlanadi). Kamera yoki internet bir kun ishlamasa,
--   kamera kuzatadigan HAMMA xodim «kelmagan» bo'lib qolardi.
--   YECHIM: har kun uchun kamerada ko'ringan xodim/o'qituvchi Kamera ID'larini qaytaramiz; admin panel (maosh berish oynasi) shu
--   kuni ISHLASHI KERAK bo'lganlardan (shaxsiy ish kuni, faol, ruhsatda emas — klientda, oylik hisobot bilan bir xil qoida)
--   nechtasi ko'ringanini sanaydi va 30% dan kam bo'lsa kunni «kamera ishlamagan» deb belgilaydi (skani yo'qqa yo'qlama yozilmaydi).
--   Ketgan («chiqdi») xodim kamerasi ham ro'yxatda — kim kutilganini klient hal qiladi (oylik hisobot ham barcha skanni ko'radi).
--   Natija: {"tracked": N, "days": {"YYYY-MM-DD": ["kamera ID", ...], ...}} — skan bo'lmagan kun ro'yxatda yo'q.
--   tracked — faol (chiqmagan) xodim/o'qituvchilarning Kamera ID soni (ma'lumot uchun).
--   Kim chaqiradi: direktor, HR, moliya, kassir (xodim davomati / maosh berish ekranlari) — ular staff_checkins'ni o'qiy oladi.
-- Idempotent (run-all.sql zanjirida).
-- =====================================================================

create or replace function public.camera_days(p_from text, p_to text)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_tracked int; v_days jsonb;
begin
  if not (app.is_admin() or app.is_hr() or app.is_finance() or app.is_cashier()) then
    raise exception 'Ruxsat yo''q: kamera kunlari faqat direktor / HR / moliya / kassir uchun' using errcode = '42501';
  end if;
  if coalesce(p_from, '') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(p_to, '') !~ '^\d{4}-\d{2}-\d{2}$'
     or p_to < p_from or (p_to::date - p_from::date) > 62 then
    raise exception 'Noto''g''ri sana oralig''i (YYYY-MM-DD, ko''pi bilan 62 kun)' using errcode = '22023';
  end if;
  with cams as (
    select btrim("cameraId") as cam from public.teachers where coalesce(btrim("cameraId"), '') <> ''
    union
    select btrim("cameraId") from public.staff where coalesce(btrim("cameraId"), '') <> ''
  )
  select (select count(*) from (
            select btrim("cameraId") from public.teachers where coalesce(btrim("cameraId"), '') <> '' and coalesce("payStatus", '') <> 'chiqdi'
            union
            select btrim("cameraId") from public.staff where coalesce(btrim("cameraId"), '') <> '' and coalesce("payStatus", '') <> 'chiqdi') t)::int,
         coalesce((select jsonb_object_agg(d.day, d.ids) from (
            select c.day, jsonb_agg(distinct btrim(c."personId") order by btrim(c."personId")) as ids
              from public.staff_checkins c
             where c.day between p_from and p_to
               and btrim(c."personId") in (select cam from cams)
             group by c.day) d), '{}'::jsonb)
    into v_tracked, v_days;
  return jsonb_build_object('tracked', v_tracked, 'days', v_days);
end $$;
revoke all on function public.camera_days(text, text) from public, anon;
grant execute on function public.camera_days(text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
