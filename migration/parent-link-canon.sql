\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
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

-- Kalit NOYOBmi: boshqa o'quvchi qatori shu qatorning id/studentId kalitlaridan birini ishlatmaydimi. Eski importdan
--   qolgan TO'QNASHUVLAR (bir xil studentId ikki qatorda, yoki bir qatorning doc id'si boshqasining studentId'si) —
--   bunday qatorlar uchun doc id <-> studentId moslash O'CHIQ: aks holda ota-ona BOSHQA oila bolasining maxfiy
--   ma'lumoti/fakturalarini ko'rib qolardi. To'qnashuv admin tomonidan tuzatilguncha avvalgidek (faqat aniq kalit).
create or replace function app.student_keys_unique(p_id text, p_sid text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select not exists(
    select 1 from public.students s2
     where s2.id <> p_id
       and (s2."studentId" = p_id
            or (nullif(p_sid, '') is not null and (s2.id = p_sid or s2."studentId" = p_sid))))
$$;
revoke all on function app.student_keys_unique(text, text) from public, anon;
grant execute on function app.student_keys_unique(text, text) to authenticated, service_role;

create or replace function app.owns_child(sid text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select exists(
    select 1 from public.child_claims cc
     where cc.uid = app.uid()
       and coalesce(nullif(cc.status, ''), 'active') = 'active'
       and (cc."studentId" = sid
            or exists (select 1 from public.students s
                        where s.id = sid and nullif(s."studentId", '') = cc."studentId"
                          and app.student_keys_unique(s.id, s."studentId"))
            or exists (select 1 from public.students s
                        where s."studentId" = sid and s.id = cc."studentId"
                          and app.student_keys_unique(s.id, s."studentId"))))
$$;

create or replace function public.claim_child(p_sid text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_fails int; v_ok boolean; v_canon text; v_doc text; v_sidraw text; v_n int;
begin
  if v_uid is null then
    raise exception 'auth required' using errcode = '42501';
  end if;
  p_sid := btrim(coalesce(p_sid, ''));
  -- Lockout: oxirgi 15 daqiqada 5+ MUVAFFAQIYATSIZ urinish -> bloklash.
  select count(*) into v_fails
    from public.child_claim_attempts
   where uid = v_uid and ok = false and "at" > now() - interval '15 minutes';
  if v_fails >= 5 then
    insert into public.child_claim_attempts(uid, "studentId", ok) values (v_uid, p_sid, false);
    return jsonb_build_object('ok', false, 'locked', true,
      'error', 'Juda ko''p urinish. 15 daqiqadan so''ng qayta urinib ko''ring.');
  end if;
  -- Kod AYNAN qaysi o'quvchi qatoriga tegishli (kod doc id bilan saqlanadi) — bog'lanish faqat SHU qatorga
  --   (avval kalit alohida qidirilib, bo'sh/to'qnash ID'da boshqa bolaga bog'lanib qolishi mumkin edi).
  select count(*), min(s.id) into v_n, v_doc
    from public.students s join public.student_codes sc on sc.id = s.id
   where p_sid <> '' and coalesce(p_code, '') <> '' and upper(sc.code) = upper(p_code)
     and (s.id = p_sid or s."studentId" = p_sid);
  v_ok := (v_n = 1);
  insert into public.child_claim_attempts(uid, "studentId", ok) values (v_uid, p_sid, v_ok);
  if not v_ok then
    return jsonb_build_object('ok', false, 'error', 'O''quvchi ID yoki kod noto''g''ri.');
  end if;
  -- KANONIK kalit (invoices/attendance/… shu bilan kalitlangan): studentId, bo'sh bo'lsa doc id — kod tekshirilgan qatordan.
  select coalesce(nullif(s."studentId", ''), s.id), s."studentId" into v_canon, v_sidraw from public.students s where s.id = v_doc;
  if not app.student_keys_unique(v_doc, v_sidraw) then
    return jsonb_build_object('ok', false, 'error',
      'Bu o''quvchi ID''si boshqa o''quvchi bilan takrorlangan — maktab ma''muriyatiga murojaat qiling.');
  end if;
  insert into public.child_claims(id, uid, "studentId", code)
    values (v_uid || '__' || v_canon, v_uid, v_canon, p_code)
    on conflict do nothing;
  return jsonb_build_object('ok', true, 'studentId', v_canon);
end $$;
grant execute on function public.claim_child(text, text) to authenticated;

notify pgrst, 'reload schema';
