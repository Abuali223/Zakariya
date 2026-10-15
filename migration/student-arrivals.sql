\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: student-arrivals.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- student-arrivals.sql — o'quvchilarning KAMERA (Hikvision) bo'yicha kelish vaqti, sinf davomati uchun.
--
--   MUAMMO: kamera hodisalari (payments/index.cjs) hamma shaxs uchun staff_checkins'ga yoziladi
--     (personId = terminaldagi ID = o'quvchining «Kamera ID»si). Lekin sinf davomati (kurator) bu
--     ma'lumotni umuman ishlatmasdi: hamma «Keldi» bo'lib ochilardi -> tekshirmay saqlansa, kelmagan
--     bola ham «keldi» deb yozilardi. Kurator esa staff_checkins'ni o'qiy olmaydi (xodim maxfiyligi —
--     sc_chk_sel faqat admin/hr/moliya/kassir).
--   YECHIM: tor SECURITY DEFINER funksiya — FAQAT chaqiruvchi rahbarlik/dars beradigan SINF o'quvchilarining
--     shu kundagi BIRINCHI kirish vaqtini qaytaradi (xodimlar skani, boshqa sinf — qaytmaydi).
--     Sinf kaliti admin.html classKeyOf() bilan AYNAN bir xil: lang-grade-(classLetter|track|'-').
-- Idempotent (CREATE OR REPLACE). run-all.sql'da (deploy shu zanjirni qo'llaydi).
-- =====================================================================
create or replace function public.class_arrivals(p_class text, p_day text)
returns table("studentId" text, "firstIn" timestamptz)   -- ts timestamptz -> PostgREST ISO-8601 (offset bilan)
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(nullif(s."studentId", ''), s.id) as "studentId",
         min(c.ts)                                 as "firstIn"
    from public.students s
    join public.staff_checkins c
      on c."personId" = s."cameraId"
     and c.day = p_day
     and coalesce(nullif(c.status, ''), 'in') in ('in', 'unknown')        -- faqat KIRISH (chiqish/tanaffus emas)
   where coalesce(nullif(s."cameraId", ''), '') <> ''
     and (coalesce(nullif(s.lang, ''), 'uz') || '-' || coalesce(s.grade, 0)::text || '-'
          || coalesce(nullif(s."classLetter", ''), nullif(s.track, ''), '-')) = p_class   -- = classKeyOf()
     and (app.is_admin() or app.is_zavuch() or app.is_class_staff(p_class))           -- faqat O'Z sinfi
   group by 1
$$;
revoke all on function public.class_arrivals(text, text) from public, anon;
grant execute on function public.class_arrivals(text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
