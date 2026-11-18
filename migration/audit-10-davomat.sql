\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-10-davomat.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-10 (to'liq audit, 2026-11-18) — DAVOMAT va O'QUVCHI ID'si.
--
-- 1) DAVOMAT YOZUVI — faqat o'z sinfi o'quvchisiga (A2-01).
--    Muammo: att_ins / att_upd (rls.sql) faqat yozuvning O'Z "classKey"ini tekshiradi; studentId, id va oy u bilan bog'lanmagan.
--    5-A kuratori PostgREST orqali (o'z JWT'si bilan) 7-B o'quvchisiga «uz-5-A» kalitli satr yarata olardi (ixtiyoriy id bilan
--    qo'shimcha satrlar ham), yoki o'z o'quvchisi satrining studentId'sini boshqa bolaga almashtira olardi. Natija: ota-ona
--    kabinetida soxta «Kelmadi», trg_attendance_pct o'sha bolaning «Davomat %»ini buzardi (xavf ro'yxatlari), haqiqiy 7-B
--    kuratori «Saqlash»da 42501 (USING) olib, satrni ko'rmasdi ham; eski «Bemor» qoidasida (sickApprovalFrom gacha) pmLoadCtx
--    shu oydagi BARCHA satrlarning «Bemor» kunlarini qo'shgani uchun soxta dublikatlar keyingi fakturani 0 gacha tushirardi.
--    Yechim — BEFORE INSERT/UPDATE trigger (RLS o'zgarmaydi, unga qo'shimcha):
--      * yangi satr: id = studentId || '__' || oy (bitta o'quvchi-oy — bitta satr, id esa birlamchi kalit), oy 'YYYY-MM';
--      * yangilash: id, studentId va oy O'ZGARMAYDI (satrni boshqa bolaga «ko'chirib» bo'lmaydi);
--      * yangi satrda va sinf kaliti o'zgarganda — "classKey" o'quvchining HOZIRGI sinfi (app.student_class_key, admin.html
--        classKeyOf bilan bir xil). RLS esa yozuvchining shu sinfga huquqini tekshiradi -> birgalikda: faqat o'z sinfi o'quvchisi;
--      * kun kaliti '01'..'31', belgi present/absent/late/excused/sick — faqat yangi yoki o'zgargan kunlar tekshiriladi (eski
--        satrdagi o'zgarmagan kunlar saqlashni to'xtatmasin). «15a», «1» kabi kalitlar eski «Bemor» qoidasida ham sanalardi.
--    Mavjud qonuniy oqimlar ishlaydi: kurator / sinf rahbari / O'IBDO' (sinf rahbarligi bilan) o'z sinfi uchun «Saqlash»
--    (kamera belgisi ham shu saqlash orqali), Direktor, arxivdagi o'quvchining o'tgan sanasi (sinfi o'zgarmaydi), oy o'rtasida
--    sinf o'zgarishi (sync_student_class_rows — o'quvchi qatori allaqachon yangi sinfda), o'tgan oy tarixini o'sha sinf
--    xodimi tuzatishi (kalit o'zgarmaydi). Baza / migratsiya / server (JWT yo'q) — tekshiruvsiz (import, SQL bilan tuzatish).
--
-- 2) O'QUVCHI ID'si «YUQORI CHEGARASI» va TARIX — tibbiyot, so'rovlar va o'chirilganlar arxivi ham (A2-04, A1-11).
--    student-ids.sql qoidasi: ota-ona o'qiy oladigan har o'quvchi jadvali yuqori chegaraga kirishi shart. Keyin qo'shilgan
--    jadvallar tushib qolgan edi: student_health / sick_notes / nurse_visits (nurse-sick.sql — sh_sel, my_sick_notes,
--    my_nurse_visits owns_child orqali), discount_requests / referral_requests / monitoring_bonus (ota-ona ham o'qiydi,
--    tasdiqlangani hisobga ta'sir qiladi), referral_ledger va o'chirilgan o'quvchi arxivi (deleted_records). Natija: eng oxirgi
--    o'quvchi o'chirilsa, keyingi yangi bola uning ID'sini olardi — YANGI ota-ona eski bolaning allergiyasi / surunkali kasalligi,
--    hamshira murojaatlari va kasallik ma'lumotnomalarini ko'rardi; tiklashda esa ikki oilaning arxivi aralashardi.
--    Bu funksiyalar shu yerda QAYTA belgilanadi (amaldagi ta'rif — SHU fayl): student-ids.sql zanjirda bu jadvallardan OLDIN
--    turadi, SQL funksiya tanasi esa yaratilganda tekshiriladi.
--
-- Idempotent — QAYTA ishga tushirishga xavfsiz (create or replace, drop trigger if exists; ma'lumot tuzatish — faqat farq bo'lsa).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- ---------- 1) Davomat yozuvi qo'riqchisi ----------
create or replace function app.attendance_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_old jsonb; v_bad text;
begin
  -- Baza / migratsiya / server (service_role) — tekshiruvsiz: RLS ham ularga qo'llanmaydi (import, ID'ni SQL bilan tuzatish).
  if app.is_system() then return new; end if;
  -- Shu sinfga yozish huquqi yo'q foydalanuvchi — tekshiruvsiz qaytadi: uni RLS (att_ins / att_upd — xuddi shu shart) xabarsiz
  --   rad etadi (42501). Aks holda trigger xatosi bilan RLS xatosi farqidan qaysi ID qaysi sinfda ekanini bilib olardi.
  --   (Sinf o'zgarganda sync_student_class_rows qabulxona nomidan ham shu yerga keladi — u ishonchli, tekshirilmaydi.)
  if not (app.is_admin() or app.is_kurator_for(new."classKey") or app.is_homeroom_for(new."classKey")) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    -- Satr boshqa bolaga / boshqa oyga «ko'chirilmaydi»: o'z o'quvchisi satrining studentId'sini almashtirib, boshqa sinf
    --   bolasiga soxta belgi yozish yo'li shu edi. Yangi kun — o'sha o'quvchi-oy satriga yoziladi (admin.html shunday qiladi).
    if new.id is distinct from old.id or new."studentId" is distinct from old."studentId" or new.month is distinct from old.month then
      raise exception 'Davomat: yozuvning o''quvchisi va oyi o''zgartirilmaydi' using errcode = '42501';
    end if;
    v_old := case when jsonb_typeof(old.days) = 'object' then old.days else '{}'::jsonb end;
  else
    if coalesce(new.month, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then
      raise exception 'Davomat: oy «YYYY-MM» ko''rinishida bo''lsin («%»)', coalesce(new.month, '') using errcode = '22023';
    end if;
    -- Kalit admin.html bilan bir xil: `${studentId}__${oy}`. Ixtiyoriy id bilan bitta bolaga bir oyda bir nechta satr
    --   (ularning «Bemor» kunlari eski qoidada qo'shilib ketardi) endi yaratilmaydi.
    if coalesce(btrim(new."studentId"), '') = '' or new.id is distinct from new."studentId" || '__' || new.month then
      raise exception 'Davomat: yozuv kaliti «<o''quvchi ID>__<oy>» bo''lsin (bitta o''quvchi-oy — bitta yozuv)' using errcode = '22023';
    end if;
    -- admin.html «Saqlash» — upsert (INSERT ... ON CONFLICT (id) DO UPDATE): BEFORE INSERT mavjud satr uchun ham ishlaydi.
    --   Kunlar mavjud satrga nisbatan tekshiriladi — eski satrdagi o'zgarmagan kunlar (masalan eski import kaliti) saqlashni
    --   to'xtatmasin; o'zgargan / yangi kun baribir tekshiriladi (UPDATE yo'lida ham).
    select a.days into v_old from public.attendance a where a.id = new.id;
    v_old := case when jsonb_typeof(v_old) = 'object' then v_old else '{}'::jsonb end;
  end if;
  -- Sinf: yangi satrda va kalit o'zgarganda — o'quvchining HOZIRGI sinfi. O'quvchi kaliti trg_attendance_pct va
  --   sync_student_class_rows bilan bir xil: studentId, bo'lmasa (eski yozuv) hujjat id — boshqa o'quvchining studentId'si bilan
  --   to'qnashmasa. Bir nechta o'quvchi mos kelsa (eski import to'qnashuvi) — birortasining sinfi yetarli (avvalgi holat saqlanadi).
  --   Xabar bir xil: ID yo'q yoki boshqa sinfda — farqi oshkor qilinmaydi. Kunlarni tekshirishdan OLDIN: boshqa sinf satriga
  --   urinish har doim shu xabar bilan rad etiladi (o'sha satr mazmuniga bog'liq javob chiqmaydi).
  if tg_op = 'INSERT' or new."classKey" is distinct from old."classKey" then
    if not exists (
      select 1 from public.students s
       where (s."studentId" = new."studentId"
              or (s.id = new."studentId"
                  and (coalesce(s."studentId", '') = ''
                       or not exists (select 1 from public.students s2 where s2."studentId" = new."studentId"))))
         and app.student_class_key(s.lang, s.grade, s."classLetter", s.track) = new."classKey") then
      raise exception 'Davomat: «%» bu sinf o''quvchisi emas (yoki ID noto''g''ri) — sahifani yangilab, sinf ro''yxatidan saqlang', new."studentId"
        using errcode = '42501';
    end if;
  end if;
  if new.days is not null and jsonb_typeof(new.days) <> 'object' then
    raise exception 'Davomat: kunlar {"DD": "belgi"} ko''rinishida bo''lsin' using errcode = '22023';
  end if;
  select e.key into v_bad
    from jsonb_each(coalesce(new.days, '{}'::jsonb)) e
   where (v_old -> e.key) is distinct from e.value
     and not (e.key ~ '^(0[1-9]|[12][0-9]|3[01])$' and jsonb_typeof(e.value) = 'string'
              and (e.value #>> '{}') in ('present', 'absent', 'late', 'excused', 'sick'))
   limit 1;
  if found then
    raise exception 'Davomat: «%» kuni yoki belgisi noto''g''ri (kun 01–31; belgi: present, absent, late, excused, sick)', v_bad
      using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function app.attendance_guard() from public, anon, authenticated;
drop trigger if exists trg_attendance_guard on public.attendance;
create trigger trg_attendance_guard before insert or update on public.attendance
  for each row execute function app.attendance_guard();

-- Bir martalik (har deployda xavfsiz) tuzatish: JORIY va keyingi oylarning davomat satri o'quvchining hozirgi sinfidan boshqa
--   sinf kalitida qolgan bo'lsa (shu qo'riqchidan oldin boshqa sinf xodimi yozgan yoki eskirgan sahifadan saqlangan: o'quvchi
--   oy boshida boshqa sinfga o'tkazilgach eski kurator sahifasi «Saqlash» qilgan) — haqiqiy sinf kalitiga o'tkaziladi (sinf
--   o'zgarganda sync_student_class_rows qiladigan ish). Aks holda haqiqiy sinf rahbari butun oy «Saqlash»da 42501 olib, satrni
--   ko'rmasdi. O'tgan oylar (tarix) tegilmaydi; o'quvchisi aniq bo'lmagan satr (to'qnash ID, o'chirilgan o'quvchi) tegilmaydi.
--   Zanjirda (JWT yo'q) — qo'riqchi tekshirmaydi; days o'zgarmaydi -> «Davomat %» va change_log triggerlari ishlamaydi.
with m as (
  select a.id, min(app.student_class_key(s.lang, s.grade, s."classLetter", s.track)) as ck, count(*) as n
    from public.attendance a
    join public.students s
      on s."studentId" = a."studentId"
      or (s.id = a."studentId"
          and (coalesce(s."studentId", '') = ''
               or not exists (select 1 from public.students s2 where s2."studentId" = a."studentId")))
   where a.month >= to_char(app.tashkent_now(), 'YYYY-MM')
   group by a.id
)
update public.attendance a set "classKey" = m.ck
  from m
 where m.id = a.id and m.n = 1 and a."classKey" is distinct from m.ck;

-- Kaliti «<o'quvchi ID>__<oy>» bo'lmagan eski satrlar (qo'riqchidan oldin qo'lda / soxta yaratilgan bo'lishi mumkin) — O'CHIRILMAYDI,
--   faqat sanab ogohlantiriladi: ular «Davomat %»ga va eski «Bemor» qoidasidagi chegirmaga kiradi, Direktor / texnik yordam
--   ko'rib chiqsin (deploy.sh «OGOHLANTIRISH» qatorini ko'rsatadi). Faqat son — ism yoki ID logga yozilmaydi.
do $att$ declare n int; begin
  select count(*) into n from public.attendance a
   where a.id is distinct from coalesce(a."studentId", '') || '__' || coalesce(a.month, '');
  if n > 0 then
    raise notice 'OGOHLANTIRISH: davomat: % ta satr kaliti «<o''quvchi ID>__<oy>» emas (eski import yoki qo''riqchidan oldin qo''lda yaratilgan) — «Davomat %%» va eski «Bemor» qoidasida hisobga kiradi; ko''rib chiqing: select id, "studentId", "classKey", month from public.attendance where id <> "studentId" || ''__'' || month;', n;
  end if;
end $att$;

-- ---------- 2) O'quvchi ID'sining yuqori chegarasi (student-ids.sql dagi ta'rifni almashtiradi) ----------
--   Raqam 1–9 xonali: 10+ xonali (xato kiritilgan) qiymat int chegarasidan oshib butun funksiyani xatoga tushirmasin — aks holda
--   admin.html yuqori chegarani olmay, faqat tirik o'quvchilar ichidagi eng katta ID bilan ishlab, eski ID'ni qayta berardi.
create or replace function public.student_id_high_water()
returns int language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.is_staff() then coalesce(max((regexp_match(x, '^IQ-(\d{1,9})$'))[1]::int), 0) else 0 end
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
          union all select id from public.student_private
          -- tibbiyot (nurse-sick.sql): sog'liq kartasi, kasallik ma'lumotnomalari, hamshira murojaatlari
          union all select id from public.student_health
          union all select "studentId" from public.student_health
          union all select "studentId" from public.sick_notes
          union all select "studentId" from public.nurse_visits
          -- chegirma / tavsiya / 100 ball bonusi (discount-approval.sql, discounts.sql, bonus-100.sql)
          union all select "studentId" from public.discount_requests
          union all select id from public.referral_requests
          union all select "referrerId" from public.referral_requests
          union all select id from public.referral_ledger
          union all select "referrerId" from public.referral_ledger
          union all select "studentId" from public.monitoring_bonus
          -- o'chirilgan o'quvchi arxivi (admission-crm.sql): tiklanadigan yozuvning ID'si boshqa bolaga berilmasin
          union all select "rowId" from public.deleted_records where tbl in ('students', 'student_private', 'student_codes')
          union all select row ->> 'studentId' from public.deleted_records where tbl = 'students') t
   where x ~ '^IQ-\d{1,9}$'
$$;
revoke all on function public.student_id_high_water() from public, anon;
grant execute on function public.student_id_high_water() to authenticated, service_role;

-- ---------- 3) Bitta ID tarixi (student-ids.sql dagi ta'rifni almashtiradi) ----------
--   'other' — ota-ona ko'radigan / hisobga ta'sir qiladigan boshqa yozuvlar: endi tibbiyot va chegirma / tavsiya / bonus so'rovlari
--   ham (admin.html YANGI ID tekshiruvi 'other'ga qaraydi — eski sahifa keshida ham shu ID rad etiladi).
--   'medical' — tibbiy yozuvlar soni alohida: o'chirish oynasi «tibbiy yozuv bor» deb ogohlantiradi.
--   'private' — maxfiy ma'lumot qatori + o'chirilganlar arxividagi (tiklanmagan) shu ID: o'chirilgan bolaning ID'si qo'lda ham
--   yangi bolaga berilmasin (aks holda tiklash rad etilardi yoki ikki oila arxivi aralashardi).
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
    'other',      (select count(*) from public.characteristics where "studentId" = p_sid)
                + (select count(*) from public.subject_notes where "studentId" = p_sid)
                + (select count(*) from public.student_summaries where "studentId" = p_sid)
                + (select count(*) from public.olympiads where "studentId" = p_sid)
                + (select count(*) from public.credit_ledger where "studentId" = p_sid)
                + (select count(*) from public.refunds where "studentId" = p_sid)
                + (select count(*) from public.discount_requests where "studentId" = p_sid)
                + (select count(*) from public.referral_requests where id = p_sid or "referrerId" = p_sid)
                + (select count(*) from public.referral_ledger where id = p_sid or "referrerId" = p_sid)
                + (select count(*) from public.monitoring_bonus where "studentId" = p_sid)
                + (select count(*) from public.student_health where id = p_sid or "studentId" = p_sid)
                + (select count(*) from public.sick_notes where "studentId" = p_sid)
                + (select count(*) from public.nurse_visits where "studentId" = p_sid),
    'medical',    (select count(*) from public.student_health where id = p_sid or "studentId" = p_sid)
                + (select count(*) from public.sick_notes where "studentId" = p_sid)
                + (select count(*) from public.nurse_visits where "studentId" = p_sid),
    'private',    (select count(*) from public.student_private where id = p_sid)
                + (select count(*) from public.deleted_records d
                    where d."restoredAt" is null
                      and ((d.tbl in ('students', 'student_private', 'student_codes') and d."rowId" = p_sid)
                           or (d.tbl = 'students' and d.row ->> 'studentId' = p_sid)))
  ) end
$$;
revoke all on function public.student_history(text) from public, anon;
grant execute on function public.student_history(text) to authenticated, service_role;

notify pgrst, 'reload schema';
