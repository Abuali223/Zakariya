\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: id-guards.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- id-guards.sql — tahrirda ID'lar (kalitlar) jim o'zgarmasin / qayta ishlatilmasin.
--
--   1) O'quvchi kalitlari (DB himoyasi): ilova foydalanuvchisi (JWT bilan — direktor ham) students.id ni va
--      MAVJUD (bo'sh bo'lmagan) studentId'ni o'zgartira olmaydi. studentId — hisob-faktura, to'lov, avans,
--      davomat, baho va ota-ona ulanishi kaliti: o'zgarsa hammasi «yetim» qoladi. Bo'sh studentId'ni to'ldirish
--      (NULL/'' -> qiymat) mumkin. Texnik tuzatish (SQL, service_role) — tegilmaydi (app.uid() bo'sh).
--      O'qituvchi/xodim qatori kaliti (teachers.id / staff.id) ham ilovadan o'zgarmaydi (ta'til, tanaffus,
--      o'rinbosarlik, foydalanuvchi bog'lanishi shu kalit bilan).
--   2) payroll_id_high_water(prefix) — o'qituvchi (IQT-) / xodim (IQX-) ID'sining eng katta raqami: joriy
--      ro'yxat + maosh berish / avans tarixidan (o'chirilgan xodimning ham). Yangi xodimga O'CHIRILGAN xodimning
--      ID'si berilmaydi — aks holda u eski qoldiq/avans/«shu oy berilgan»ni meros olardi.
--   3) payroll_key_info(key) — shu maosh kaliti ostidagi tarix (maosh, avans, «xodim farzandi» bog'lanishi) va
--      egalari soni: ID o'zgartirish tasdig'ida ANIQ ko'rsatish uchun (avval «(bo'sh)» deyilardi, pul esa _id
--      kalitida turardi).
--   4) rekey_payroll_id(...) — o'qituvchi/xodim ID'sini o'zgartirish VA uning maosh/avans tarixi, «xodim
--      farzandi» bog'lanishi va foydalanuvchi yorlig'ini (users.staffCode) yangi ID'ga BITTA tranzaksiyada
--      ko'chirish. Eski ID boshqa xodimda ham bo'lsa (takroriy ID) — tarix kimniki ekani noma'lum: ko'chirilmaydi.
--      Yozuv o'chirilgan / ID boshqa joyda o'zgargan / yangi ID band yoki o'chirilgan xodim tarixi bilan — rad.
-- Faqat direktor/admin/HR (app.is_admin() / app.is_hr()). Idempotent (run-all.sql zanjirida).
-- =====================================================================

-- ---- 1) Kalit himoyasi ----
create or replace function app.guard_student_keys()
  returns trigger language plpgsql
  set search_path = public, app, pg_temp as $$
begin
  if app.uid() is not null then
    if new.id is distinct from old.id then
      raise exception 'O''quvchi yozuvi kaliti (id) ilovadan o''zgartirilmaydi' using errcode = '42501';
    end if;
    if btrim(coalesce(old."studentId", '')) <> '' and new."studentId" is distinct from old."studentId" then
      raise exception 'O''quvchi ID''si («%») o''zgartirilmaydi — u hisob-faktura, to''lov, avans, davomat va ota-ona ulanishi kaliti', old."studentId"
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_student_keys on public.students;
create trigger trg_student_keys before update on public.students
  for each row execute function app.guard_student_keys();

create or replace function app.guard_row_id()
  returns trigger language plpgsql
  set search_path = public, app, pg_temp as $$
begin
  if app.uid() is not null and new.id is distinct from old.id then
    raise exception 'Yozuv kaliti (id) ilovadan o''zgartirilmaydi (%)', tg_table_name using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists trg_teacher_row_id on public.teachers;
create trigger trg_teacher_row_id before update on public.teachers
  for each row execute function app.guard_row_id();
drop trigger if exists trg_staff_row_id on public.staff;
create trigger trg_staff_row_id before update on public.staff
  for each row execute function app.guard_row_id();

-- ---- 2) Yangi o'qituvchi/xodim ID'si uchun yuqori chegara ----
create or replace function public.payroll_id_high_water(p_prefix text)
returns int language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when (app.is_admin() or app.is_hr()) and coalesce(p_prefix, '') ~ '^[A-Z]{1,6}-$'
    then coalesce(max((regexp_match(upper(btrim(x)), '^' || p_prefix || '(\d{1,9})$'))[1]::int), 0) else 0 end
    from (select "teacherId" as x from public.teachers
          union all select "staffId" from public.staff
          union all select "teacherId" from public.salary_payments
          union all select "teacherId" from public.staff_advances
          union all select "teacherId" from public.student_private) t
   where coalesce(x, '') <> ''
$$;
revoke all on function public.payroll_id_high_water(text) from public, anon;
grant execute on function public.payroll_id_high_water(text) to authenticated, service_role;

-- ---- 3) Maosh kaliti tarixi ----
create or replace function public.payroll_key_info(p_key text)
returns jsonb language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when (app.is_admin() or app.is_hr()) and coalesce(p_key, '') <> '' then jsonb_build_object(
    'salary',   (select count(*) from public.salary_payments where "teacherId" = p_key),
    'advances', (select count(*) from public.staff_advances  where "teacherId" = p_key),
    'children', (select count(*) from public.student_private where "teacherId" = p_key),
    'owners',   (select count(*) from public.teachers t where coalesce(nullif(t."teacherId", ''), t.id) = p_key)
              + (select count(*) from public.staff s    where coalesce(nullif(s."staffId", ''), s.id) = p_key)
  ) end
$$;
revoke all on function public.payroll_key_info(text) from public, anon;
grant execute on function public.payroll_key_info(text) to authenticated, service_role;

-- ---- 4) ID o'zgartirish + tarixni ko'chirish (atomik) ----
create or replace function public.rekey_payroll_id(p_coll text, p_row text, p_old text, p_new text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_cur    text;
  v_key    text;
  v_shared int;
  v_move   boolean;
  n_sal    int := 0;
  n_adv    int := 0;
  n_ch     int := 0;
begin
  if not (app.is_admin() or app.is_hr()) then
    raise exception 'O''qituvchi/xodim ID''sini faqat direktor yoki HR o''zgartiradi' using errcode = '42501';
  end if;
  if p_coll is null or p_coll not in ('teachers', 'staff') then
    raise exception 'Noto''g''ri jadval: %', p_coll using errcode = '22023';
  end if;
  if coalesce(p_new, '') = '' or p_new <> btrim(p_new) then
    raise exception 'Yangi ID bo''sh yoki chetida bo''sh joy bor' using errcode = '22023';
  end if;
  -- Qator qulflanadi: parallel tahrir/ID o'zgartirish tugashini kutadi.
  if p_coll = 'teachers' then
    select "teacherId" into v_cur from public.teachers where id = p_row for update;
  else
    select "staffId" into v_cur from public.staff where id = p_row for update;
  end if;
  if not found then
    raise exception 'Yozuv topilmadi (o''chirilgan bo''lishi mumkin) — sahifani yangilang' using errcode = 'P0002';
  end if;
  -- Optimistik tekshiruv: oyna ochilgandan beri ID boshqa joyda o'zgarmagan bo'lsin.
  if coalesce(v_cur, '') is distinct from coalesce(p_old, '') then
    raise exception 'ID boshqa joyda o''zgartirilgan (bazada hozir «%») — oynani yopib, qayta oching', coalesce(v_cur, '')
      using errcode = 'P0001';
  end if;
  -- Maosh kaliti — admin.html bilan bir xil: String(teacherId||_id) (bo'sh bo'lsa qator id'si; xom, kesilmagan).
  v_key := case when coalesce(v_cur, '') = '' then p_row else v_cur end;
  if v_key = p_new then
    return jsonb_build_object('moved', false, 'same', true, 'oldKey', v_key);
  end if;
  -- Yangi ID boshqa o'qituvchi/xodimning kaliti emas (o'qituvchi va xodim maosh kalitlari BITTA nomlar fazosida).
  if exists (select 1 from public.teachers t where btrim(coalesce(nullif(t."teacherId", ''), t.id)) = p_new and not (p_coll = 'teachers' and t.id = p_row))
     or exists (select 1 from public.staff s where btrim(coalesce(nullif(s."staffId", ''), s.id)) = p_new and not (p_coll = 'staff' and s.id = p_row)) then
    raise exception 'ID «%» boshqa xodim/o''qituvchida bor — takroriy ID maosh/avansni aralashtiradi', p_new using errcode = '23505';
  end if;
  -- Yangi ID ostida egasiz (o'chirilgan xodimning) maosh/avans tarixi — meros olinmasin.
  if exists (select 1 from public.salary_payments where "teacherId" = p_new)
     or exists (select 1 from public.staff_advances where "teacherId" = p_new) then
    raise exception 'ID «%» ostida avvalgi (o''chirilgan) xodimning maosh/avans tarixi bor — boshqa ID tanlang', p_new using errcode = '23505';
  end if;
  -- Eski kalit boshqa yozuvda ham bo'lsa (takroriy ID) — tarix kimniki ekani noma'lum: KO'CHIRILMAYDI.
  select (select count(*) from public.teachers t where coalesce(nullif(t."teacherId", ''), t.id) = v_key and not (p_coll = 'teachers' and t.id = p_row))
       + (select count(*) from public.staff s    where coalesce(nullif(s."staffId", ''), s.id) = v_key and not (p_coll = 'staff' and s.id = p_row))
    into v_shared;
  v_move := (v_shared = 0);
  if p_coll = 'teachers' then
    update public.teachers set "teacherId" = p_new where id = p_row;
  else
    update public.staff set "staffId" = p_new where id = p_row;
  end if;
  if v_move then
    update public.salary_payments set "teacherId" = p_new where "teacherId" = v_key;
    get diagnostics n_sal = row_count;
    update public.staff_advances set "teacherId" = p_new where "teacherId" = v_key;
    get diagnostics n_adv = row_count;
    if p_coll = 'teachers' then
      -- «Xodim farzandi» bog'lanishi: kalit (teacherId||_id) bilan; o'qituvchiga ID berilishidan OLDIN bog'langanlar
      --   qator id'si bilan saqlangan bo'lishi mumkin — ular ham (boshqa o'qituvchining ID'si bo'lmasa).
      update public.student_private sp set "teacherId" = p_new
       where sp."teacherId" = v_key
          or (sp."teacherId" = p_row and not exists (select 1 from public.teachers t2 where t2."teacherId" = p_row));
      get diagnostics n_ch = row_count;
    end if;
  end if;
  -- Foydalanuvchi yorlig'i (faqat ko'rinish uchun nusxa) ham yangilanadi.
  update public.users set "staffCode" = p_new
   where "staffRefId" = p_row and "staffRefType" = (case when p_coll = 'teachers' then 'teacher' else 'staff' end);
  return jsonb_build_object('moved', v_move, 'shared', not v_move, 'oldKey', v_key,
                            'salary', n_sal, 'advances', n_adv, 'children', n_ch);
end $$;
revoke all on function public.rekey_payroll_id(text, text, text, text) from public, anon;
grant execute on function public.rekey_payroll_id(text, text, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
