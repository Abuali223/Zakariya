-- =====================================================================
-- reception-guard.sql — Qabulxona (reception) xodimiga CHEKLOV (DB darajasida).
--
--   MAQSAD: qabulxona xodimi o'quvchi QO'SHADI va asosiy ma'lumotini TAHRIRLAYDI,
--   LEKIN:
--     (a) o'quvchi HOLATINI (faollashtirish/muzlatish/chiqarish/sinov =
--         payStatus/activeFrom/stopFrom) O'ZGARTIRA OLMAYDI — bu faqat Ma'muriyat
--         (direktor/ma'muriyat rahbari = app.is_admin_head()) huquqi.
--     (b) MOLIYAVIY maydonlarni (chegirma toifasi/kontrakt summasi/aka-uka chegirmasi/
--         referral = specialCategory/contractAmount/siblingDiscount/referrerId) o'zgartira olmaydi.
--
--   RLS satr darajasida ishlaydi, USTUN darajasida cheklay olmaydi — shuning uchun
--   TRIGGER ishlatamiz (frontend ham bu maydonlarni qabulxonaga ko'rsatmaydi; bu — DB
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
  if app.is_reception() and not app.is_admin_head() then
    if tg_op = 'INSERT' then
      new."payStatus"  := '';   -- qabulxona o'quvchini oddiy (faol) qilib yaratadi
      new."activeFrom" := '';
      new."stopFrom"   := '';
    elsif tg_op = 'UPDATE' then
      if (new."payStatus"  is distinct from old."payStatus")
      or (new."activeFrom" is distinct from old."activeFrom")
      or (new."stopFrom"   is distinct from old."stopFrom") then
        raise exception 'Qabulxona xodimi o''quvchi holatini (faollashtirish/muzlatish/chiqarish) o''zgartira olmaydi — bu Ma''muriyat huquqi'
          using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_reception_student_lifecycle on public.students;
create trigger trg_reception_student_lifecycle before insert or update on public.students
  for each row execute function app.guard_reception_student_lifecycle();

-- ---- MOLIYAVIY maydonlar (chegirma/kontrakt/referral) — qabulxonaga yopiq ----
create or replace function app.guard_reception_private_finance()
  returns trigger language plpgsql
  set search_path = public, app, pg_temp as $$
begin
  if app.is_reception() and not app.is_admin_head() then
    if tg_op = 'INSERT' then
      new."specialCategory" := null;
      new."contractAmount"  := null;
      new."siblingDiscount" := null;
      new."referrerId"      := null;
    elsif tg_op = 'UPDATE' then
      if (new."specialCategory" is distinct from old."specialCategory")
      or (new."contractAmount"  is distinct from old."contractAmount")
      or (new."siblingDiscount" is distinct from old."siblingDiscount")
      or (new."referrerId"      is distinct from old."referrerId") then
        raise exception 'Qabulxona xodimi moliyaviy maydonlarni (chegirma/kontrakt/referral) o''zgartira olmaydi — bu Ma''muriyat huquqi'
          using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_reception_private_finance on public.student_private;
create trigger trg_reception_private_finance before insert or update on public.student_private
  for each row execute function app.guard_reception_private_finance();

notify pgrst, 'reload schema';
