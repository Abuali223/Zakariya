\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-11-talim.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-11 (to'liq audit, 2026-11-18) — O'QUV JARAYONI: baholar, monitoring, xarakteristika, fan izohi, oylik xulosa.
--
-- 1) YOZUV FAQAT O'Z SINFI O'QUVCHISIGA, O'QITUVCHI — FAQAT O'Z FANIGA (A3-02). audit-10-davomat.sql (A2-01, davomat) bilan bir xil yo'l.
--    Muammo: RLS (rls.sql, audit-4.sql, audit-fixes.sql) faqat yozuvning O'Z "classKey"ini tekshiradi — brauzer yuborgan qiymat;
--    studentId, id va davr u bilan bog'lanmagan. Baholarda fan umuman tekshirilmaydi. Natija: 5-A Matematika o'qituvchisi PostgREST
--    orqali 5-A o'quvchisining Fizika baholarini qayta yozardi yoki subjects='{}' bilan BARCHA fanlarni o'chirardi (izsiz); 7-B
--    o'quvchisiga «uz-5-A» kalitli monitoring balli (100) yozardi — haqiqiy 7-B o'qituvchisi 42501 olardi, O'IBDO' esa 7-B ekranida
--    «100 Kutilmoqda»ni ko'rib tasdiqlardi (chegirma va bonusga ta'sir qiladi); 5-A kuratori 7-B o'quvchisiga «Intizomsiz»
--    xarakteristika yozardi — 7-B sinf rahbari uni ko'rmas ham, tuzata olmas ham edi, ota-ona va rasmiy profil esa ko'rardi.
--    Yechim — BEFORE INSERT/UPDATE triggerlar (RLS o'zgarmaydi, unga qo'shimcha; Direktor / O'IBDO' huquqlari o'zgarmaydi):
--      * yangi satr: id kanonik (admin.html bilan bir xil: baho `${sid}__${yil}`, monitoring `${sid}__${oy}__${fan slug}`,
--        xarakteristika `${sid}__${davr}`, fan izohi `${sid}__${davr}__${slug}`, oylik xulosa `${sid}__${oy}`);
--      * yangilash: id, studentId va davr (yil / oy / chorak) O'ZGARMAYDI — satrni boshqa bolaga «ko'chirib» bo'lmaydi;
--      * yangi satrda va sinf kaliti o'zgarganda — "classKey" o'quvchining HOZIRGI sinfi (app.sid_in_class — attendance_guard bilan
--        bir xil moslash). RLS yozuvchining shu sinfga huquqini tekshiradi -> birgalikda: faqat o'z sinfi o'quvchisi;
--      * o'qituvchi (Direktor / O'IBDO' emas): baholarda faqat O'Z fanlari kalitlari o'zgaradi (boshqa fan yoki '{}' — rad); monitoring
--        va fan izohida yozuv kalitidagi fan slug'i fan nomiga mos (app.mon_slug — admin.html monSlug) — app.monitoring_avg va to'lov
--        hisobi fanni kalitdan oladi; fanni almashtirib bo'lmaydi.
--    Shu sinfga yozish huquqi yo'q foydalanuvchi — tekshiruvsiz qaytadi (RLS xabarsiz rad etadi, 42501): aks holda trigger xatosi bilan
--    RLS xatosi farqidan qaysi ID qaysi sinfda ekanini bilib olardi. Baza / migratsiya / server (JWT yo'q) — tekshiruvsiz.
--
-- 2) MONITORING: TASDIQLANGAN BALL JIM BEKOR BO'LMAYDI (A3-01), BALL 0–100 (A3-03), NOTO'G'RI YOZUVNI O'CHIRISH (A3-06).
--    * Avval o'qituvchi ochiq qolgan (eskirgan) sahifadan «Saqlash» qilsa, barcha qatorlar ESKI holat bilan 'pending' bo'lib qayta
--      yozilardi va O'IBDO' tasdig'i (approvedBy) jim o'chardi — chegirma / 100 ball bonusi yo'qolardi. Endi: tasdiqlangan satr balli
--      o'zgarmasa — 'pending'ga TUSHIRILMAYDI (yozuv o'tkazib yuboriladi, hech narsa o'zgarmaydi); balli o'zgarsa — faqat Direktor / O'IBDO'
--      (u holda satr qayta tasdiqlashga tushadi); o'qituvchi tasdiqlangan ballni o'zgartira olmaydi (admin.html ham qulflaydi).
--    * Ball 0–100 (yoki bo'sh): yangi yozuvda, ball o'zgarganda va tasdiqlashda tekshiriladi. 950 kabi xato 20% chegirma, eski qoidada
--      100% grant va 100 ball nomzodligini berardi. Mavjud noto'g'ri qatorlar O'ZGARTIRILMAYDI — pastda ro'yxati chiqariladi.
--    * O'chirish: Direktor / O'IBDO' — istalgan yozuv; o'qituvchi — faqat O'ZI kiritgan, tasdiqlanmagan yozuv (o'z sinfi va fani).
--      Raund qulfi (yopilgan raund, kiritish muddati) — monitoring_guard (bonus-100.sql) o'chirishga ham qo'llanadi.
--    trg_monitoring_check nomi alifbo bo'yicha trg_monitoring_guard'dan OLDIN — tasdiq belgilari (approvedBy/At) yakuniy holatdan qo'yiladi.
--
-- 3) XARAKTERISTIKA / FAN IZOHI / OYLIK XULOSA: muallif va sana belgisi (A3-07) — matn o'zgarmagan satrda eski belgi saqlanadi (eskirgan
--    sahifa barcha satrlarni qayta yuborsa ham «kim, qachon» buzilmaydi); matn o'zgarganda muallif ID'si — haqiqiy yozuvchi (app.uid()).
--
-- 4) Bir martalik (har deployda xavfsiz) tuzatish: JORIY davr (monitoring va oylik xulosa — joriy va keyingi oylar; baho, xarakteristika,
--    fan izohi — joriy o'quv yili, iyul–avgustdan tashqari) satrlari o'quvchining hozirgi sinfidan boshqa sinf kalitida qolgan bo'lsa —
--    haqiqiy sinfga o'tkaziladi (sinf o'zgarganda sync_student_class_rows qiladigan ish) va ID'lari NOTICE bilan chiqariladi. Aks holda
--    haqiqiy sinf xodimi o'z o'quvchisini saqlay olmasdi (42501). O'tgan davrlar va o'quvchisi aniq bo'lmagan satrlar tegilmaydi.
--
-- Idempotent — QAYTA ishga tushirishga xavfsiz (create or replace, drop trigger / policy if exists; tuzatish — faqat farq bo'lsa).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- ---------- Yordamchilar ----------
-- O'quvchi kaliti (studentId, bo'lmasa eski yozuvdagi hujjat id) shu sinf o'quvchisimi. Moslash attendance_guard (audit-10-davomat.sql) va
--   sync_student_class_rows bilan BIR XIL: studentId bo'yicha, yoki hujjat id bo'yicha — studentId bo'sh bo'lsa yoki bu kalit boshqa
--   o'quvchining studentId'si bilan to'qnashmasa. Bir nechta o'quvchi mos kelsa (eski import to'qnashuvi) — birortasining sinfi yetarli.
create or replace function app.sid_in_class(p_sid text, p_ck text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(btrim(p_sid), '') <> '' and exists (
    select 1 from public.students s
     where (s."studentId" = p_sid
            or (s.id = p_sid
                and (coalesce(s."studentId", '') = ''
                     or not exists (select 1 from public.students s2 where s2."studentId" = p_sid))))
       and app.student_class_key(s.lang, s.grade, s."classLetter", s.track) = p_ck)
$$;
revoke all on function app.sid_in_class(text, text) from public, anon, authenticated;

-- Fan nomi -> yozuv kalitidagi slug (admin.html monSlug bilan bir xil): kirill (o'zbek + rus) lotinga, qolgan harf/belgi -> '_'.
--   Kirillning KATTA harflari ham alohida: baza lc_ctype 'C' bo'lsa lower() faqat ASCII'ni kichraytiradi (JS toLowerCase hammasini).
--   Natija bo'sh bo'lsa (masalan faqat emoji) admin.html 'fan_<xesh>' beradi — bu yerda NULL (chaqiruvchi 'fan_…' ni qabul qiladi).
--   JS kichik harfi ASCII bo'ladigan ikki belgi (İ -> «i» + nuqta, Kelvin K -> k) lower()'dan OLDIN — natija bazaning lokaliga bog'liq bo'lmasin.
create or replace function app.mon_slug(p_subject text) returns text
language plpgsql immutable set search_path = pg_catalog as $$
declare s text := lower(replace(replace(coalesce(p_subject, ''), 'İ', 'i_'), 'K', 'k'));
begin
  s := replace(replace(s, 'ё', 'yo'), 'Ё', 'yo');
  s := replace(replace(s, 'ж', 'j'),  'Ж', 'j');
  s := replace(replace(s, 'ц', 'ts'), 'Ц', 'ts');
  s := replace(replace(s, 'ч', 'ch'), 'Ч', 'ch');
  s := replace(replace(s, 'ш', 'sh'), 'Ш', 'sh');
  s := replace(replace(s, 'щ', 'sh'), 'Щ', 'sh');
  s := replace(replace(s, 'ю', 'yu'), 'Ю', 'yu');
  s := replace(replace(s, 'я', 'ya'), 'Я', 'ya');
  s := translate(s, 'абвгдезийклмнопрстуфхыэўқғҳАБВГДЕЗИЙКЛМНОПРСТУФХЫЭЎҚҒҲъьЪЬ',
                    'abvgdeziyklmnoprstufxieoqghabvgdeziyklmnoprstufxieoqgh');
  s := regexp_replace(s, '[^a-z0-9]+', '_', 'g');
  s := regexp_replace(s, '^_+|_+$', '', 'g');
  return nullif(s, '');
end $$;
revoke all on function app.mon_slug(text) from public, anon, authenticated;

-- Kalitdagi slug fan nomiga mosmi (bo'sh slug'li fan — admin.html xeshi 'fan_…').
create or replace function app.subject_slug_ok(p_slug text, p_subject text) returns boolean
language sql immutable set search_path = pg_catalog, app as $$
  select coalesce(p_slug = app.mon_slug(p_subject) or (app.mon_slug(p_subject) is null and p_slug ~ '^fan_[0-9a-z]+$'), false)
$$;
revoke all on function app.subject_slug_ok(text, text) from public, anon, authenticated;

-- ---------- 1a) Baholar ----------
create or replace function app.grades_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_priv boolean; v_old jsonb; v_new jsonb; v_bad text;
begin
  if app.is_system() then return new; end if;
  v_priv := app.is_admin() or app.is_zavuch();
  -- RLS (grades_ins / grades_upd) bilan bir xil huquq; yo'q bo'lsa — tekshiruvsiz, RLS xabarsiz rad etadi.
  if not (v_priv or app.is_teacher_for_class(new."classKey")) then return new; end if;
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id or new."studentId" is distinct from old."studentId" or new.year is distinct from old.year then
      raise exception 'Baholar: yozuvning o''quvchisi va o''quv yili o''zgartirilmaydi' using errcode = '42501';
    end if;
    v_old := old.subjects;
  else
    if coalesce(new.year, '') !~ '^\d{4}-\d{4}$' then
      raise exception 'Baholar: o''quv yili «YYYY-YYYY» ko''rinishida bo''lsin («%»)', coalesce(new.year, '') using errcode = '22023';
    end if;
    if coalesce(btrim(new."studentId"), '') = '' or new.id is distinct from new."studentId" || '__' || new.year then
      raise exception 'Baholar: yozuv kaliti «<o''quvchi ID>__<o''quv yili>» bo''lsin' using errcode = '22023';
    end if;
    -- admin.html «Saqlash» — upsert: BEFORE INSERT mavjud satr uchun ham ishlaydi -> fanlar mavjud satrga nisbatan solishtiriladi.
    select g.subjects into v_old from public.grades g where g.id = new.id;
  end if;
  -- Sinf — yangi satrda va kalit o'zgarganda: o'quvchining HOZIRGI sinfi (xabar bir xil: ID yo'q yoki boshqa sinfda — farqi aytilmaydi).
  if tg_op = 'INSERT' or new."classKey" is distinct from old."classKey" then
    if not app.sid_in_class(new."studentId", new."classKey") then
      raise exception 'Baholar: «%» bu sinf o''quvchisi emas (yoki ID noto''g''ri) — sahifani yangilab, sinf ro''yxatidan saqlang', new."studentId"
        using errcode = '42501';
    end if;
  end if;
  if new.subjects is not null and jsonb_typeof(new.subjects) <> 'object' then
    raise exception 'Baholar: fanlar {"Fan": {"q1": baho}} ko''rinishida bo''lsin' using errcode = '22023';
  end if;
  -- O'qituvchi — faqat O'Z fanlari (users."assignedSubjects"): boshqa fan kaliti o'zgarsa yoki o'chsa (subjects='{}') — rad.
  --   Ochiq qolgan sahifa boshqa o'qituvchining shu orada qo'ygan bahosini eski nusxa bilan qaytarib yozsa ham shu yerda to'xtaydi.
  if not v_priv then
    v_old := case when jsonb_typeof(v_old) = 'object' then v_old else '{}'::jsonb end;
    v_new := coalesce(new.subjects, '{}'::jsonb);
    select k into v_bad
      from (select jsonb_object_keys(v_new) as k union select jsonb_object_keys(v_old)) t
     where (v_new -> t.k) is distinct from (v_old -> t.k) and not app.teacher_has_subject(t.k)
     order by k limit 1;
    if found then
      raise exception 'Baholar: «%» fani sizga biriktirilmagan — faqat o''z fanlaringiz baholarini o''zgartira olasiz (sahifani yangilab qayta saqlang)', v_bad
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function app.grades_guard() from public, anon, authenticated;
drop trigger if exists trg_grades_guard on public.grades;
create trigger trg_grades_guard before insert or update on public.grades
  for each row execute function app.grades_guard();

-- ---------- 1b + 2) Monitoring ----------
create or replace function app.monitoring_row_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_priv boolean; v_slug text;
begin
  if app.is_system() then return new; end if;
  v_priv := app.is_admin() or app.is_zavuch();
  -- RLS (mon_ins / mon_upd) bilan bir xil huquq (status shartisiz); yo'q bo'lsa — tekshiruvsiz, RLS xabarsiz rad etadi.
  if not (v_priv or (app.is_teacher_for_class(new."classKey") and app.teacher_has_subject(new.subject))) then return new; end if;
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id or new."studentId" is distinct from old."studentId" or new.period is distinct from old.period then
      raise exception 'Monitoring: yozuvning o''quvchisi va oyi o''zgartirilmaydi' using errcode = '42501';
    end if;
    -- O'qituvchi fanni almashtira olmaydi (yozib bo'lmaydigan fanga «ko'chirish» yo'li); yozilishi (katta-kichik harf) o'zgarishi mumkin.
    if not v_priv and app.mon_slug(new.subject) is distinct from app.mon_slug(old.subject) then
      raise exception 'Monitoring: yozuvning fani o''zgartirilmaydi' using errcode = '42501';
    end if;
  else
    if coalesce(new.period, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then
      raise exception 'Monitoring: oy «YYYY-MM» ko''rinishida bo''lsin («%»)', coalesce(new.period, '') using errcode = '22023';
    end if;
    v_slug := app.mon_slug_of(new.id, coalesce(new."studentId", ''), new.period);
    if coalesce(btrim(new."studentId"), '') = '' or coalesce(v_slug, '') !~ '^[a-z0-9_]+$' then
      raise exception 'Monitoring: yozuv kaliti «<o''quvchi ID>__<oy>__<fan>» bo''lsin' using errcode = '22023';
    end if;
    if not v_priv and not app.subject_slug_ok(v_slug, new.subject) then
      raise exception 'Monitoring: yozuv kalitidagi fan «%» fani bilan mos emas', new.subject using errcode = '42501';
    end if;
  end if;
  if tg_op = 'INSERT' or new."classKey" is distinct from old."classKey" then
    if not app.sid_in_class(new."studentId", new."classKey") then
      raise exception 'Monitoring: «%» bu sinf o''quvchisi emas (yoki ID noto''g''ri) — sahifani yangilab, sinf ro''yxatidan saqlang', new."studentId"
        using errcode = '42501';
    end if;
  end if;
  -- A3-03: ball 0–100 (bo'sh — mumkin). Faqat yangi / o'zgargan ballda va tasdiqlashda — mavjud qatorning boshqa ustuni
  --   (masalan sinf o'zgarganda "classKey") eski noto'g'ri ball tufayli to'xtab qolmasin.
  if new.score is not null
     and (tg_op = 'INSERT' or new.score is distinct from old.score
          or (coalesce(new.status, '') = 'approved' and coalesce(old.status, '') <> 'approved'))
     and not (new.score >= 0 and new.score <= 100) then
    raise exception 'Monitoring: «%» balli 0–100 oralig''ida bo''lsin (kiritilgan: %)', new."studentId", new.score using errcode = '22023';
  end if;
  -- A3-01: tasdiqlangan ball — balli o'zgarmasa 'pending'ga tushirilmaydi (eskirgan sahifa qayta yuborgani: yozuv o'tkazib yuboriladi,
  --   hech narsa o'zgarmaydi); balli o'zgarsa — faqat Direktor / O'IBDO' (satr qayta tasdiqlashga tushadi).
  if tg_op = 'UPDATE' and coalesce(old.status, '') = 'approved' and coalesce(new.status, '') <> 'approved' then
    if new.score is not distinct from old.score then return null; end if;
    if not v_priv then
      raise exception 'Monitoring: «%» balli O''IBDO'' tomonidan tasdiqlangan — o''zgartirish O''IBDO'' orqali (sahifani yangilang)', new."studentId"
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function app.monitoring_row_guard() from public, anon, authenticated;
drop trigger if exists trg_monitoring_check on public.monitoring;
create trigger trg_monitoring_check before insert or update on public.monitoring
  for each row execute function app.monitoring_row_guard();

-- A3-06: noto'g'ri yozuvni o'chirish (rls.sql dagi mon_del'ni almashtiradi — "enteredBy" ustuni bonus-100.sql'da qo'shiladi).
drop policy if exists mon_del on public.monitoring;
create policy mon_del on public.monitoring for delete using (
  app.is_admin() or app.is_zavuch()
  or (app.is_teacher_for_class("classKey") and app.teacher_has_subject(subject)
      and coalesce(status, '') <> 'approved' and "enteredBy" = app.uid()));

-- ---------- 1c + 3) Xarakteristika, fan izohi, oylik xulosa ----------
create or replace function app.academic_text_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare n jsonb := to_jsonb(new); o jsonb; v_priv boolean; v_ok boolean; v_key text; v_per text; v_slug text;
begin
  if app.is_system() then return new; end if;
  v_priv := app.is_admin() or app.is_zavuch();
  if tg_op = 'UPDATE' then o := to_jsonb(old); end if;
  -- RLS bilan bir xil huquq: fan izohi — note_ins / note_upd, qolganlari — can_write_general (char_*, sum_*).
  if tg_table_name = 'subject_notes' then
    v_ok := v_priv or (app.is_teacher_for_class(new."classKey") and app.teacher_has_subject(n ->> 'subject'));
  else
    v_ok := app.can_write_general(new."classKey");
  end if;
  if not v_ok then return new; end if;
  -- Davr: xarakteristika va fan izohi — chorak ('2026-2027-q1'), oylik xulosa — oy.
  v_per := case when tg_table_name = 'student_summaries' then n ->> 'month' else n ->> 'term' end;
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id or new."studentId" is distinct from old."studentId" or v_per is distinct from
         (case when tg_table_name = 'student_summaries' then o ->> 'month' else o ->> 'term' end)
       or (tg_table_name = 'subject_notes' and (n ->> 'slug') is distinct from (o ->> 'slug')) then
      raise exception 'Yozuvning o''quvchisi va davri o''zgartirilmaydi' using errcode = '42501';
    end if;
    if tg_table_name = 'subject_notes' and not v_priv and app.mon_slug(n ->> 'subject') is distinct from app.mon_slug(o ->> 'subject') then
      raise exception 'Fan izohi: yozuvning fani o''zgartirilmaydi' using errcode = '42501';
    end if;
  else
    if tg_table_name = 'student_summaries' then
      if coalesce(v_per, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then
        raise exception 'Oylik xulosa: oy «YYYY-MM» ko''rinishida bo''lsin («%»)', coalesce(v_per, '') using errcode = '22023';
      end if;
    elsif coalesce(v_per, '') !~ '^\d{4}-\d{4}-q[1-4]$' then
      raise exception 'Chorak «YYYY-YYYY-qN» ko''rinishida bo''lsin («%»)', coalesce(v_per, '') using errcode = '22023';
    end if;
    v_key := new."studentId" || '__' || v_per;
    if tg_table_name = 'subject_notes' then
      v_slug := n ->> 'slug';
      if coalesce(v_slug, '') !~ '^[a-z0-9_]+$' then
        raise exception 'Fan izohi: fan slug''i noto''g''ri («%»)', coalesce(v_slug, '') using errcode = '22023';
      end if;
      if not v_priv and not app.subject_slug_ok(v_slug, n ->> 'subject') then
        raise exception 'Fan izohi: yozuv kalitidagi fan «%» fani bilan mos emas', n ->> 'subject' using errcode = '42501';
      end if;
      v_key := v_key || '__' || v_slug;
    end if;
    if coalesce(btrim(new."studentId"), '') = '' or new.id is distinct from v_key then
      raise exception 'Yozuv kaliti «<o''quvchi ID>__<davr>» bo''lsin (bitta o''quvchi-davr — bitta yozuv)' using errcode = '22023';
    end if;
  end if;
  if tg_op = 'INSERT' or new."classKey" is distinct from old."classKey" then
    if not app.sid_in_class(new."studentId", new."classKey") then
      raise exception '«%» bu sinf o''quvchisi emas (yoki ID noto''g''ri) — sahifani yangilab, sinf ro''yxatidan saqlang', new."studentId"
        using errcode = '42501';
    end if;
  end if;
  -- A3-07: matn o'zgarmagan satr — muallif va sana belgisi eskicha (eskirgan sahifa qayta yuborsa ham «kim, qachon» buzilmaydi).
  --   Matn o'zgarganda — muallif ID'si haqiqiy yozuvchi (mijoz yuborgan qiymat emas), sana — server vaqti.
  if tg_op = 'UPDATE' and new.text is not distinct from old.text then
    new."byUid" := old."byUid"; new."byName" := old."byName"; new."updatedAt" := old."updatedAt";
  else
    new."byUid" := app.uid(); new."updatedAt" := now();
  end if;
  return new;
end $$;
revoke all on function app.academic_text_guard() from public, anon, authenticated;
drop trigger if exists trg_characteristics_guard on public.characteristics;
create trigger trg_characteristics_guard before insert or update on public.characteristics
  for each row execute function app.academic_text_guard();
drop trigger if exists trg_subject_notes_guard on public.subject_notes;
create trigger trg_subject_notes_guard before insert or update on public.subject_notes
  for each row execute function app.academic_text_guard();
drop trigger if exists trg_student_summaries_guard on public.student_summaries;
create trigger trg_student_summaries_guard before insert or update on public.student_summaries
  for each row execute function app.academic_text_guard();

-- ---------- 4) Bir martalik tuzatish (joriy davr satrlarining sinf kaliti) va noto'g'ri ballar ro'yxati ----------
--   Zanjirda (JWT yo'q) — qo'riqchilar tekshirmaydi; matn / ball o'zgarmaydi -> change_log va belgilar tegilmaydi.
--   O'quvchi kaliti AYNAN bitta o'quvchiga mos kelgan satrlar (to'qnash eski import ID — tegilmaydi).
do $fix$
declare
  v_now timestamp := app.tashkent_now();
  v_mon text := to_char(v_now, 'YYYY-MM');
  v_ay  text := case when extract(month from v_now) >= 9 then extract(year from v_now)::int || '-' || (extract(year from v_now)::int + 1)
                     else (extract(year from v_now)::int - 1) || '-' || extract(year from v_now)::int end;
  v_yr  boolean := extract(month from v_now) not in (7, 8);   -- iyul–avgust: sinf o'zgarishi = yangi o'quv yiliga o'tkazish
  t text; v_n int; v_ids text;
begin
  foreach t in array array['monitoring', 'student_summaries', 'grades', 'characteristics', 'subject_notes'] loop
    continue when t in ('grades', 'characteristics', 'subject_notes') and not v_yr;
    execute format($q$
      with m as (
        select a.id, min(app.student_class_key(s.lang, s.grade, s."classLetter", s.track)) as ck, count(*) as cnt
          from public.%1$I a
          join public.students s
            on s."studentId" = a."studentId"
            or (s.id = a."studentId"
                and (coalesce(s."studentId", '') = ''
                     or not exists (select 1 from public.students s2 where s2."studentId" = a."studentId")))
         where %2$s
         group by a.id),
      u as (update public.%1$I a set "classKey" = m.ck from m
             where m.id = a.id and m.cnt = 1 and a."classKey" is distinct from m.ck
            returning a.id)
      select count(*), left(string_agg(id, ', ' order by id), 3000) from u$q$,
      t, case t when 'monitoring' then format('a.period >= %L', v_mon)
                when 'student_summaries' then format('a.month >= %L', v_mon)
                else format('a.year = %L', v_ay) end)
      into v_n, v_ids;
    if v_n > 0 then
      raise notice 'TUZATILDI: %: % ta joriy davr satri o''quvchining haqiqiy sinfiga o''tkazildi (boshqa sinf kaliti bilan yozilgan edi): %', t, v_n, v_ids;
    end if;
  end loop;
  -- A3-03: 0–100 dan tashqari ballar — O'ZGARTIRILMAYDI, faqat ro'yxat (O'IBDO' / Direktor tuzatsin; tuzatilmaguncha hisobga kiradi).
  select count(*), left(string_agg(id || '=' || score::text, ', ' order by id), 3000) into v_n, v_ids
    from public.monitoring where score is not null and not (score >= 0 and score <= 100);
  if v_n > 0 then
    raise notice 'OGOHLANTIRISH: monitoring: % ta ball 0–100 oralig''idan tashqarida (o''zgartirilmadi — tuzating): %', v_n, v_ids;
  end if;
end $fix$;

notify pgrst, 'reload schema';
