\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
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
--   Manbalar — ota-ona owns_child / owns_student_doc orqali O'QIY OLADIGAN barcha o'quvchi jadvallari (tavsifnoma, fan izohi,
--   oylik xulosa, olimpiada, avans jurnali, qaytarish, maxfiy ma'lumot ham): ulardan biri tushib qolsa, o'chirilgan bolaning
--   ID'si (masalan qolgan kodi o'chirilgach) yangi bolaga berilib, YANGI ota-ona eski bolaning yozuvini ko'rardi.
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
          union all select id from public.student_credit
          union all select "studentId" from public.student_credit
          union all select "studentId" from public.credit_ledger
          union all select "studentId" from public.refunds
          union all select "studentId" from public.characteristics
          union all select "studentId" from public.subject_notes
          union all select "studentId" from public.student_summaries
          union all select "studentId" from public.olympiads
          union all select id from public.student_private) t
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
    'claims',     (select count(*) from public.child_claims where "studentId" = p_sid),
    -- ota-ona ko'radigan boshqa yozuvlar (tavsifnoma, fan izohi, oylik xulosa, olimpiada, avans jurnali, qaytarish)
    'other',      (select count(*) from public.characteristics where "studentId" = p_sid)
                + (select count(*) from public.subject_notes where "studentId" = p_sid)
                + (select count(*) from public.student_summaries where "studentId" = p_sid)
                + (select count(*) from public.olympiads where "studentId" = p_sid)
                + (select count(*) from public.credit_ledger where "studentId" = p_sid)
                + (select count(*) from public.refunds where "studentId" = p_sid),
    -- maxfiy ma'lumot qatori (tirik o'quvchida doim bor — faqat YANGI ID tekshiruvi uchun: o'chirilgan bolaniki qolgan bo'lsa)
    'private',    (select count(*) from public.student_private where id = p_sid)
  ) end
$$;
revoke all on function public.student_history(text) from public, anon;
grant execute on function public.student_history(text) to authenticated, service_role;

-- O'chirilgan o'quvchining KIRISH KODI ham o'chsin. admin.html o'quvchini o'chirganda student_codes qatorini ham
--   o'chiradi, lekin DELETE policy yo'q edi (faqat sc_sel) -> jim 0 qator: kod qolib, to'lov serveri «faqat kod» bilan
--   kelgan to'lovni mavjud bo'lmagan («arvoh») kalitga yo'naltirardi, ota-ona esa o'chirilgan o'quvchini «bog'lay» olardi.
drop policy if exists sc_del on public.student_codes;
create policy sc_del on public.student_codes for delete using (app.is_admin());
-- Avval qolib ketgan arvoh kodlar (o'quvchisi yo'q) tozalanadi — keyingi deploylarda 0 qator (idempotent).
--   Arvoh = kalit HECH QAYSI o'quvchining id'si ham, studentId'si ham emas. Kalit tirik o'quvchining studentId'siga teng kod
--   (import: o'chirilgan dublikat IQ-0042 + tirik fbX9/IQ-0042) arvoh EMAS: to'lov serveri «IQ-0042 KOD» to'lovini u bilan
--   tirik bolaga biriktiradi (payments/index.cjs codeMatchesAny + studentExists; attr.test T14b) — o'chirilsa o'sha oilaning
--   to'lovlari «Biriktirilmagan»ga tushardi.
--   Himoya: o'quvchilar jadvali bo'sh yoki arvohlar g'ayrioddiy ko'p bo'lsa (masalan tiklash/import jarayoni) — tegilmaydi.
do $$ declare n_all int; n_ghost int; begin
  select count(*) into n_all from public.student_codes;
  select count(*) into n_ghost from public.student_codes sc
   where not exists (select 1 from public.students s where s.id = sc.id or s."studentId" = sc.id);
  if n_ghost > 0 and exists (select 1 from public.students) and n_ghost <= greatest(5, n_all / 5) then
    delete from public.student_codes sc where not exists (select 1 from public.students s where s.id = sc.id or s."studentId" = sc.id);
  elsif n_ghost > 0 then
    raise notice 'student_codes: % ta o''quvchisiz kod (jami %) — g''ayrioddiy ko''p, avtomatik tozalanmadi. Zararsiz (hech qaysi o''quvchiga tegishli emas — to''lov va ota-ona bog''lanishida ishlatilmaydi); o''quvchilar ataylab o''chirilgan bo''lsa — qo''lda tozalash: migration/deploy/README.md «Arvoh kodlar»', n_ghost, n_all;
  end if;
end $$;

notify pgrst, 'reload schema';
