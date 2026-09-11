-- =====================================================================
-- BIR MARTALIK MA'LUMOT MIGRATSIYASI — o'quvchi hujjat _id'sini studentId'ga tenglashtirish.
--   Ildiz "chalkashlik": import qilingan o'quvchida students.id (Firebase hujjat id) <> studentId
--   (IQ-xxxx). Ba'zi jadvallar _id bilan (student_private, student_codes), boshqalari studentId
--   bilan (invoices, attendance, monitoring, student_credit, child_claims) kalitlangan edi ->
--   chegirma, ma'lumotnoma, olimpiada grant, ota-ona biriktirishi buzilardi.
--   Bu migratsiya BARCHA jadvalни BITTA kalitга (studentId) keltiradi.
--
-- XAVFSIZLIK:
--   * IDEMPOTENT — qayta ishga tushirilса, id=studentId bo'lganlar tegilmaydi (no-op).
--   * FK yo'q (app-darajali bog'lanish), trigger AFTER INSERT — UPDATE qayta yaratmaydi.
--   * Olimpiada xatosi qoldirgan "phantom" student_private[studentId] qatorlar birlashtiriladi.
--   * ISHGA TUSHIRISHDAN OLDIN ZAXIRA OLING:  bash ~/backup.sh
--   Ishga tushirish (BIR MARTA):
--     sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/rekey-students.sql
-- =====================================================================

do $$
declare
  r record;
  v_rekeyed int := 0;
  v_merged int := 0;
  v_skipped int := 0;
begin
  for r in
    select id as old_id, "studentId" as new_id
      from public.students
     where "studentId" is not null and "studentId" <> '' and id <> "studentId"
  loop
    -- To'qnashuv: boshqa students qatori allaqachon new_id bilan bo'lsa — tegmaymiz (studentId noyob bo'lishi kerak).
    if exists (select 1 from public.students where id = r.new_id) then
      raise notice 'SKIP % -> % (nishon students id band)', r.old_id, r.new_id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    -- student_private: olimpiada xatosi new_id'да "phantom" qator yaratgan bo'lishi mumkin.
    if exists (select 1 from public.student_private where id = r.new_id)
       and exists (select 1 from public.student_private where id = r.old_id) then
      -- Phantomdagi specialCategory (olimpiada granti) HAQIQIY qatorda bo'lmasa — ko'chiramiz, so'ng phantomни o'chiramiz.
      update public.student_private rr
         set "specialCategory" = coalesce(nullif(rr."specialCategory",''),
                                           (select "specialCategory" from public.student_private where id = r.new_id))
       where rr.id = r.old_id;
      delete from public.student_private where id = r.new_id;
      v_merged := v_merged + 1;
    end if;
    update public.student_private set id = r.new_id where id = r.old_id;

    -- student_codes: nishonда qolgan qator bo'lsa (kutilmaydi) — o'chirib, haqiqiyni ko'chiramiz.
    if exists (select 1 from public.student_codes where id = r.new_id)
       and exists (select 1 from public.student_codes where id = r.old_id) then
      delete from public.student_codes where id = r.new_id;
    end if;
    update public.student_codes set id = r.new_id where id = r.old_id;

    -- child_claims: eski _id bilan biriktirilganlar bo'lsa (kutilmaydi — migratsiya o'quvchisi biriktirilmasди) — studentId'ga.
    update public.child_claims set "studentId" = r.new_id where "studentId" = r.old_id;

    -- student_credit (AVANS): apply_payment xatosi eski _id bilan avans yozgan bo'lishi mumkin
    --   (Click erkin to'lov -> _id -> invoys topilmadi -> butun summa avansга _id kaliti bilan).
    --   Kanonik studentId'ga ko'chiramiz; ikkalasi bo'lsa — kreditlarни QO'SHAMIZ (pul yo'qolmasin).
    if exists (select 1 from public.student_credit where id = r.new_id)
       and exists (select 1 from public.student_credit where id = r.old_id) then
      update public.student_credit n
         set credit = coalesce(n.credit,0) + coalesce((select credit from public.student_credit where id = r.old_id),0),
             "updatedAt" = now()
       where n.id = r.new_id;
      delete from public.student_credit where id = r.old_id;
    else
      update public.student_credit set id = r.new_id, "studentId" = r.new_id where id = r.old_id;
    end if;
    -- Avans harakati jurnali ham kanonik kalitга.
    update public.credit_ledger set "studentId" = r.new_id where "studentId" = r.old_id;

    -- Nihoyat, students hujjatining o'zi.
    update public.students set id = r.new_id where id = r.old_id;

    v_rekeyed := v_rekeyed + 1;
  end loop;

  raise notice 'REKEY tugadi: % ta o''quvchi qayta-kalitlandi, % ta phantom birlashtirildi, % ta o''tkazildi.',
    v_rekeyed, v_merged, v_skipped;
end $$;

notify pgrst, 'reload schema';
