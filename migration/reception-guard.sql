\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: reception-guard.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- reception-guard.sql — Qabulxona (reception) xodimiga CHEKLOV (DB darajasida).
--
--   MAQSAD: qabulxona xodimi o'quvchi QO'SHADI va asosiy ma'lumotini TAHRIRLAYDI,
--   LEKIN o'quvchi HOLATINI (faollashtirish/muzlatish/chiqarish/sinov =
--     payStatus/activeFrom/stopFrom) O'ZGARTIRA OLMAYDI — bu faqat Ma'muriyat
--     (direktor/ma'muriyat rahbari = app.is_admin_head()) huquqi.
--
--   MOLIYAVIY maydonlar (chegirma/kontrakt/aka-uka/referral) qabulxonaga QOLDIRILADI —
--     ular pulga ta'sir qilmaydi, faqat ota-onaga xabar berish/undiruv uchun kerak
--     (foydalanuvchi talabi). Oldingi deploy'da qo'yilgan moliya triggeri BU YERDA OLIB
--     TASHLANADI (pastda drop).
--
--   RLS satr darajasida ishlaydi, USTUN darajasida cheklay olmaydi — shuning uchun HOLAT
--   uchun TRIGGER ishlatamiz (frontend ham bu maydonlarni qabulxonaga ko'rsatmaydi; bu — DB
--   darajasidagi asl himoya, API orqali chetlab o'tishning oldini oladi).
--
--   UPDATE: qabulxona himoyalangan maydonni O'ZGARTIRSA -> xato (42501).
--   INSERT: qabulxona yangi yozuvda bu maydonlarni to'ldirsa -> jim tozalanadi
--           (o'quvchi oddiy/faol, chegirmasiz yaratiladi).
-- Idempotent. run-all.sql + deploy.sh'da (student-status.sql va discounts.sql'dan KEYIN).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- ---- O'quvchi HOLATI (lifecycle) — faqat Ma'muriyat ----
create or replace function app.guard_reception_student_lifecycle()
  returns trigger language plpgsql
  set search_path = public, app, pg_temp as $$
begin
  -- O'quvchi HOLATI = faqat Ma'muriyat (app.is_admin_head()) huquqi. students'ga yoza oladigan boshqa
  --    roller (qabulxona VA O'IBDO'/zavuch) buni o'zgartira olmaydi. Superuser/service_role (seed/backend)
  --   tegilmaydi (ular reception/zavuch emas).
  if (app.is_reception() or app.is_zavuch()) and not app.is_admin_head() then
    if tg_op = 'INSERT' then
      new."payStatus"  := '';   -- oddiy (faol) qilib yaratiladi
      -- To'lov RO'YXATGA OLINGAN KUNDAN (Toshkent) hisoblanadi: avval '' yozilib, oy o'rtasida qo'shilgan
      --   bola butun oy uchun (1-sanadan, prorata'siz) hisoblanardi. Ma'muriyat keyin ⏯️ bilan o'zgartirishi mumkin.
      new."activeFrom" := to_char((now() at time zone 'Asia/Tashkent')::date, 'YYYY-MM-DD');
      new."stopFrom"   := '';
      new."pauses"     := '[]'::jsonb;   -- to'xtatilgan davrlar tarixi ham holatning bir qismi
    elsif tg_op = 'UPDATE' then
      if (new."payStatus"  is distinct from old."payStatus")
      or (new."activeFrom" is distinct from old."activeFrom")
      or (new."stopFrom"   is distinct from old."stopFrom")
      or (new."pauses"     is distinct from old."pauses") then
        raise exception 'O''quvchi holatini (faollashtirish/muzlatish/chiqarish) faqat Ma''muriyat o''zgartira oladi'
          using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_reception_student_lifecycle on public.students;
create trigger trg_reception_student_lifecycle before insert or update on public.students
  for each row execute function app.guard_reception_student_lifecycle();

-- ---- MOLIYAVIY maydon triggeri OLIB TASHLANADI (chegirma/kontrakt/referral qabulxonaga QOLADI) ----
-- Oldingi deploy'da qo'yilgan bo'lsa — jim o'chiriladi (idempotent). Bu maydonlar pulga ta'sir
--   qilmaydi, faqat ota-onaga xabar/undiruv uchun; qabulxona ularni to'ldira/tahrirlay oladi.
drop trigger if exists trg_reception_private_finance on public.student_private;
drop function if exists app.guard_reception_private_finance();

notify pgrst, 'reload schema';
