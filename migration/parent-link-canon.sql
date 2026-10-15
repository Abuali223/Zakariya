\if :{?iqror_chain}
\else
do $iqror_guard$ begin raise exception 'iqror: parent-link-canon.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- parent-link-canon.sql — ota-ona <-> farzand bog'lanishi o'quvchi KALITIDAN qat'i nazar ishlasin.
--
--   O'quvchida ikki kalit bo'lishi mumkin: doc id (students.id) va studentId (IQ-xxxx). Import qilingan
--   (Firebase'dan ko'chgan) qatorlarda ular FARQ qiladi. Muammolar:
--     1) claim_child(p_sid = IQ-xxxx, kod) -> code_ok faqat student_codes.id = p_sid ni tekshirardi, kod esa
--        doc id bilan saqlanadi (gen_student_code: NEW.id) -> admin bergan «ID + kod» bilan bunday bolani
--        BOG'LAB BO'LMASDI (har urinish «noto'g'ri», 5 tadan keyin 15 daqiqa blok).
--     2) owns_child(sid) faqat child_claims."studentId" = sid ni solishtirardi. RLS ba'zan doc id (students,
--        student_private, student_credit), ba'zan studentId (invoices, attendance, grades…) bilan chaqiradi ->
--        bog'langan ota-ona farzandining o'quvchi qatorini / davomat foizini / maxfiy ma'lumotini ko'rmasdi.
--   Yechim: code_ok ikkala kalitni qabul qiladi; claim_child KANONIK studentId bilan yozadi; owns_child
--   ikkala kalitni moslaydi (+ faqat 'active' bog'lanish — kelajakdagi pending/revoked holatlari uchun).
-- Idempotent (create or replace; run-all.sql zanjirida — rls/security-2b/audit-4 ta'riflaridan KEYIN).
-- =====================================================================

create or replace function app.code_ok(sid text, c text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(c, '') <> '' and exists(
    select 1 from public.student_codes sc
     where upper(sc.code) = upper(c)
       and (sc.id = sid or sc.id in (select s.id from public.students s where s."studentId" = sid)))
$$;

create or replace function app.owns_child(sid text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select exists(
    select 1 from public.child_claims cc
     where cc.uid = app.uid()
       and coalesce(nullif(cc.status, ''), 'active') = 'active'
       and (cc."studentId" = sid
            or cc."studentId" in (select nullif(s."studentId", '') from public.students s where s.id = sid)
            or cc."studentId" in (select s.id from public.students s where s."studentId" = sid)))
$$;

create or replace function public.claim_child(p_sid text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_fails int; v_ok boolean; v_canon text;
begin
  if v_uid is null then
    raise exception 'auth required' using errcode = '42501';
  end if;
  -- Lockout: oxirgi 15 daqiqada 5+ MUVAFFAQIYATSIZ urinish -> bloklash.
  select count(*) into v_fails
    from public.child_claim_attempts
   where uid = v_uid and ok = false and "at" > now() - interval '15 minutes';
  if v_fails >= 5 then
    insert into public.child_claim_attempts(uid, "studentId", ok) values (v_uid, p_sid, false);
    return jsonb_build_object('ok', false, 'locked', true,
      'error', 'Juda ko''p urinish. 15 daqiqadan so''ng qayta urinib ko''ring.');
  end if;
  v_ok := app.code_ok(p_sid, p_code);
  insert into public.child_claim_attempts(uid, "studentId", ok) values (v_uid, p_sid, v_ok);
  if not v_ok then
    return jsonb_build_object('ok', false, 'error', 'O''quvchi ID yoki kod noto''g''ri.');
  end if;
  -- KANONIK kalit (invoices/attendance/… shu bilan kalitlangan): studentId, bo'sh bo'lsa doc id.
  select coalesce(nullif("studentId", ''), id) into v_canon from public.students
   where id = p_sid or "studentId" = p_sid order by ("studentId" = p_sid) desc limit 1;
  v_canon := coalesce(v_canon, p_sid);
  insert into public.child_claims(id, uid, "studentId", code)
    values (v_uid || '__' || v_canon, v_uid, v_canon, p_code)
    on conflict do nothing;
  return jsonb_build_object('ok', true, 'studentId', v_canon);
end $$;
grant execute on function public.claim_child(text, text) to authenticated;

notify pgrst, 'reload schema';
