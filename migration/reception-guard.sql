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
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/reception-guard.sql
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
      new."activeFrom" := '';
      new."stopFrom"   := '';
    elsif tg_op = 'UPDATE' then
      if (new."payStatus"  is distinct from old."payStatus")
      or (new."activeFrom" is distinct from old."activeFrom")
      or (new."stopFrom"   is distinct from old."stopFrom") then
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
