\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-fixes.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT TUZATISHLARI (RLS + kod entropiyasi). Idempotent.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Monitoring: o'qituvchi O'ZI qo'ygan bahoni TASDIQLAY olmaydi (status='approved' faqat admin/zavuch).
--    Ilgari mon_upd status'ni cheklamasди -> o'qituvchi PATCH bilan o'zini tasdiqlashi mumkin edi.
drop policy if exists mon_upd on monitoring;
create policy mon_upd on monitoring for update
  using  (app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject)))
  with check (app.is_admin() or app.is_zavuch() or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject) and status='pending'));

-- 2) Farzand biriktirish kodi entropiyasi: 6 -> 8 belgi (16^6 ≈ 16M -> 16^8 ≈ 4.3 mlrd).
--    Faqat YANGI o'quvchilarga ta'sir qiladi (mavjud kodlar o'zgarmaydi, amal qiladi).
create or replace function app.gen_student_code() returns trigger language plpgsql security definer as $$
begin
  insert into public.student_codes(id, code)
    values (NEW.id, upper(substr(md5(random()::text || NEW.id || clock_timestamp()::text), 1, 8)))
    on conflict (id) do nothing;
  return NEW;
end $$;

-- 3) users_ins: admin/direktor upsert (setDoc) orqali foydalanuvchi rolini yangilay olsin.
--    Shim setDoc = UPSERT -> mavjud qatorni yangilashда ham INSERT with-check ishlaydi;
--    eski siyosat faqat 'self parent/student'ga ruxsat berardi -> admin rol biriktirsa 42501.
drop policy if exists users_ins on users;
create policy users_ins on users for insert with check (app.is_admin() or (id = app.uid() and role in ('parent','student') and verified = false));

notify pgrst, 'reload schema';
