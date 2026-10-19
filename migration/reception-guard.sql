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
--   LEKIN o'quvchi HOLATINI (faollashtirish/muzlatish/sinov, sanalarni tuzatish =
--     payStatus/activeFrom/stopFrom/pauses) O'ZGARTIRA OLMAYDI — bu faqat Ma'muriyat
--     (direktor/ma'muriyat rahbari = app.is_admin_head()) huquqi.
--   ISTISNO (foydalanuvchi talabi): qabulxona o'quvchini CHIQARA OLADI — FAQAT «chiqdi» ga o'tish:
--     payStatus -> 'chiqdi' (avval 'chiqdi' bo'lmagan), stopFrom — haqiqiy sana, o'tgan oyning 1-sanasidan
--     (Toshkent) oldin emas YOKI o'zgarmagan; muzlatilganda faqat eski sanadan ERTAROQ (eski, ertaroq sana
--     saqlanadi), pauses o'zgarmaydi, activeFrom o'zgarmaydi («sinov»dan chiqarilsa — AYNAN stopFrom + 1 kun,
--     admin.html bilan bir xil). NULL qiymatlar bilan chetlab o'tib bo'lmaydi. O'IBDO' — hech biri.
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
--   INSERT: qabulxona YANGI yozuvda bu maydonlarni to'ldirsa -> jim tozalanadi
--           (o'quvchi oddiy/faol, chegirmasiz yaratiladi). MAVJUD qatorga upsert (shim setDoc) —
--           UPDATE qoidalari bilan tekshiriladi (tozalanmaydi).
-- Idempotent. run-all.sql + deploy.sh'da (student-status.sql va discounts.sql'dan KEYIN).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- ---- O'quvchi HOLATI (lifecycle) — faqat Ma'muriyat ----
create or replace function app.guard_reception_student_lifecycle()
  returns trigger language plpgsql
  set search_path = public, app, pg_temp as $$
declare
  v_stop  date;   -- yangi stopFrom — HAQIQIY kalendar sanasi (yaroqsiz bo'lsa null)
  v_old   date;   -- eski stopFrom (xuddi shunday)
  v_min   date;   -- qabulxona uchun eng erta chiqish sanasi: o'tgan oyning 1-sanasi (Toshkent)
  v_prev  text;   -- eski holat ('' = faol)
  v_ok    boolean;
begin
  -- O'quvchi HOLATI = faqat Ma'muriyat (app.is_admin_head()) huquqi. students'ga yoza oladigan boshqa
  --    roller (qabulxona VA O'IBDO'/zavuch) buni o'zgartira olmaydi. Superuser/service_role (seed/backend)
  --   tegilmaydi (ular reception/zavuch emas).
  if (app.is_reception() or app.is_zavuch()) and not app.is_admin_head() then
    if tg_op = 'INSERT' then
      -- MUHIM: shim'ning setDoc'i — UPSERT (INSERT ... ON CONFLICT (id) DO UPDATE SET col = EXCLUDED.col).
      --   BEFORE INSERT shu yerda MAVJUD qator uchun ham ishlaydi va o'zgartirgan qiymatlari EXCLUDED'ga
      --   o'tadi: ilgari bu yerda tozalash qabulxonaning «Chiqarish» yozuvini jimgina '' ga aylantirardi
      --   (yoki 42501). Shuning uchun tozalash FAQAT haqiqatan YANGI qator uchun; mavjud qatorga upsert esa
      --   pastdagi UPDATE tekshiruvidan o'tadi.
      if not exists (select 1 from public.students x where x.id = new.id) then
        new."payStatus"  := '';   -- oddiy (faol) qilib yaratiladi
        -- To'lov RO'YXATGA OLINGAN KUNDAN (Toshkent) hisoblanadi: avval '' yozilib, oy o'rtasida qo'shilgan
        --   bola butun oy uchun (1-sanadan, prorata'siz) hisoblanardi. Ma'muriyat keyin ⏯️ bilan o'zgartirishi mumkin.
        new."activeFrom" := to_char((now() at time zone 'Asia/Tashkent')::date, 'YYYY-MM-DD');
        new."stopFrom"   := '';
        new."pauses"     := '[]'::jsonb;   -- to'xtatilgan davrlar tarixi ham holatning bir qismi
      end if;
    elsif tg_op = 'UPDATE' then
      if (new."payStatus"  is distinct from old."payStatus")
      or (new."activeFrom" is distinct from old."activeFrom")
      or (new."stopFrom"   is distinct from old."stopFrom")
      or (new."pauses"     is distinct from old."pauses") then
        -- Qabulxona: FAQAT «Chiqarish». Shartlar (hammasi bajarilishi SHART; NULL — «yo'q» deb hisoblanadi):
        --   * payStatus -> 'chiqdi' (avval 'chiqdi' bo'lmagan); NULL/'' ga o'tkazish (= faollashtirish) — rad;
        --   * stopFrom — haqiqiy sana (YYYY-MM-DD; '2026-99-99' kabi qolipga mos yaroqsiz qiymat — rad);
        --   * stopFrom o'zgarmagan YOKI >= o'tgan oyning 1-sanasi; muzlatilgan o'quvchida faqat ERTAROQ sana
        --     (kechroq sana muzlatilgan oylarni qayta to'lanadigan qilardi — bu «sanani tuzatish», direktor ishi);
        --   * pauses o'zgarmaydi;
        --   * activeFrom o'zgarmaydi; «sinov»dan chiqarilsa — AYNAN stopFrom + 1 kun (sinov kunlari to'lanmaydi).
        v_prev := coalesce(old."payStatus", '');
        v_stop := null; v_old := null;
        if coalesce(new."stopFrom", '') ~ '^\d{4}-\d{2}-\d{2}$' then
          begin
            v_stop := new."stopFrom"::date;
            if to_char(v_stop, 'YYYY-MM-DD') <> new."stopFrom" then v_stop := null; end if;
          exception when others then v_stop := null;
          end;
        end if;
        if coalesce(old."stopFrom", '') ~ '^\d{4}-\d{2}-\d{2}$' then
          begin
            v_old := old."stopFrom"::date;
            if to_char(v_old, 'YYYY-MM-DD') <> old."stopFrom" then v_old := null; end if;
          exception when others then v_old := null;
          end;
        end if;
        v_min := date_trunc('month', (now() at time zone 'Asia/Tashkent')::date - interval '1 month')::date;
        v_ok := app.is_reception()
            and coalesce(new."payStatus", '') = 'chiqdi'
            and v_prev <> 'chiqdi'
            and new."pauses" is not distinct from old."pauses"
            and v_stop is not null
            and ( new."stopFrom" is not distinct from old."stopFrom"
                  or ( v_stop >= v_min
                       and not (v_prev = 'muzlatilgan' and v_old is not null and v_stop > v_old) ) )
            and ( case when v_prev = 'sinov'
                       then new."activeFrom" is not distinct from to_char(v_stop + 1, 'YYYY-MM-DD')
                       else new."activeFrom" is not distinct from old."activeFrom" end );
        if not coalesce(v_ok, false) then
          raise exception 'O''quvchi holatini (faollashtirish/muzlatish/sinov, sanani tuzatish) faqat Ma''muriyat o''zgartira oladi; qabulxona faqat «Chiqarish» qila oladi (o''tgan oyning 1-sanasidan oldin emas)'
            using errcode = '42501';
        end if;
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
