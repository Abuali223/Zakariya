\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: student-ids.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- student-ids.sql — o'quvchi ID'si (IQ-NNNN) HECH QACHON qayta ishlatilmasin.
--
--   Muammo: yangi o'quvchi ID'si = joriy o'quvchilar ichidagi eng katta raqam + 1. Eng katta ID'li
--   o'quvchi (ko'pincha eng oxirgi qabul qilingan sinov o'quvchi) O'CHIRILSA, keyingi yangi o'quvchi
--   o'sha ID'ni oladi va uning ESKI davomatini (kasallik chegirmasi bilan), hisob-fakturasini, avansini
--   va — eng xavflisi — ota-ona kabinet ulanishini (child_claims) MEROS oladi: eski ota-ona yangi
--   bolaning baholari/davomati/to'lovlarini ko'radi.
--   Yechim: ID «yuqori chegarasi» o'quvchilar + barcha tarixiy jadvallardan olinadi (o'chirilgan
--   o'quvchining izi qolgan joylardan ham) — admin.html yangi ID'ni shundan katta qilib beradi.
--   student_history — o'chirishdan oldin «bu o'quvchida tarix bor» ogohlantirishi uchun.
-- Faqat FAOL xodim chaqira oladi (is_staff). Idempotent (run-all.sql zanjirida).
-- =====================================================================

create or replace function public.student_id_high_water()
returns int language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.is_staff() then coalesce(max((regexp_match(x, '^IQ-(\d+)$'))[1]::int), 0) else 0 end
    from (select id as x from public.students
          union all select "studentId" from public.students
          union all select "studentId" from public.invoices
          union all select "studentId" from public.payments
          union all select "studentId" from public.attendance
          union all select "studentId" from public.grades
          union all select "studentId" from public.monitoring
          union all select "studentId" from public.child_claims
          union all select id from public.student_codes
          union all select id from public.student_credit) t
   where x ~ '^IQ-\d+$'
$$;
revoke all on function public.student_id_high_water() from public, anon;
grant execute on function public.student_id_high_water() to authenticated, service_role;

-- Bitta ID bo'yicha tarix (o'chirishdan oldin ogohlantirish / eski ID'ni qayta bermaslik uchun).
create or replace function public.student_history(p_sid text)
returns jsonb language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.is_staff() and coalesce(p_sid, '') <> '' then jsonb_build_object(
    'invoices',   (select count(*) from public.invoices   where "studentId" = p_sid),
    'paid',       (select count(*) from public.invoices   where "studentId" = p_sid and coalesce("paidAmount", 0) > 0),
    'payments',   (select count(*) from public.payments   where "studentId" = p_sid),
    'credit',     (select coalesce(sum(credit), 0) from public.student_credit where id = p_sid or "studentId" = p_sid),
    'attendance', (select count(*) from public.attendance where "studentId" = p_sid),
    'grades',     (select count(*) from public.grades     where "studentId" = p_sid),
    'claims',     (select count(*) from public.child_claims where "studentId" = p_sid)
  ) end
$$;
revoke all on function public.student_history(text) from public, anon;
grant execute on function public.student_history(text) to authenticated, service_role;

notify pgrst, 'reload schema';
