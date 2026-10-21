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
--      Yozuv o'chirilgan / ID boshqa joyda o'zgargan / yangi ID band yoki o'chirilgan xodim tarixi (maosh, avans,
--      «xodim farzandi» bog'lanishi) bilan — rad.
--   5) Maosh/avans yozuvi kaliti (salary_payments / staff_advances.teacherId): ilovadan faqat MAVJUD o'qituvchi/xodim
--      kaliti bilan yoziladi va ID o'zgartirish (4) bilan bir kalitda navbatma-navbat (advisory lock): ID o'zgartirilayotgan
--      paytda berilgan maosh eski kalitda «yetim» qolmaydi — kutadi va xato bilan qaytadi («sahifani yangilang»).
--      payeeRef ('teachers:<qator id>' / 'staff:<qator id>') — yozuv KIM uchun: kalit shu odamning HOZIRGI kaliti bo'lishi shart —
--      eski oynadan berilgan maosh/avans bo'shab boshqa odamga berilgan ID'ga (uning yangi egasiga) yozilmaydi.
--   6) camera_owners(cam) / camera_has_scans(cam) — Kamera ID kimda va eski skan tarixi bormi: qabulxona o'qituvchi/xodim
--      jadvallarini va skanlarni ko'rmaydi (RLS), shuning uchun tekshiruv serverda (faqat ism va tur qaytadi).
--   7) teacherId/staffId ilovadan faqat rekey_payroll_id orqali o'zgaradi; yangi yoki o'zgargan ID boshqa xodimnikiga teng emas
--      (shu ID'ni bir vaqtda yozayotgan ikki yozuvchi ham — 4 bilan bir kalitda navbat).
-- 1–4 — faqat direktor/admin/HR (app.is_admin() / app.is_hr()); 6 — faol xodim (app.is_staff()). Idempotent (run-all.sql).
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
--   plpgsql: ruxsat va prefiks shakli regex'dan OLDIN tekshiriladi (sql CASE ichidagi max() agregati shartdan oldin
--   hisoblanardi — istalgan foydalanuvchi o'z naqshini barcha maosh kalitlariga qo'llab, kalit borligini bilib olardi).
create or replace function public.payroll_id_high_water(p_prefix text)
returns int language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v int;
begin
  if not (app.is_admin() or app.is_hr()) or coalesce(p_prefix, '') !~ '^[A-Z]{1,6}-$' then
    return 0;
  end if;
  select coalesce(max((regexp_match(upper(btrim(x)), '^' || p_prefix || '(\d{1,9})$'))[1]::int), 0) into v
    from (select "teacherId" as x from public.teachers
          union all select "staffId" from public.staff
          union all select "teacherId" from public.salary_payments
          union all select "teacherId" from public.staff_advances
          union all select "teacherId" from public.student_private) t
   where coalesce(x, '') <> '';
  return v;
end $$;
revoke all on function public.payroll_id_high_water(text) from public, anon;
grant execute on function public.payroll_id_high_water(text) to authenticated, service_role;

-- ---- 3) Maosh kaliti tarixi ----
--   p_row — o'qituvchi qator id'si (ixtiyoriy): «xodim farzandi» soni rekey_payroll_id ko'chiradigan bilan BIR XIL —
--   kalit bilan VA qator id'si bilan saqlangan (ID berilishidan oldingi) bog'lanishlar (boshqa o'qituvchining ID'si bo'lmasa).
drop function if exists public.payroll_key_info(text);
create or replace function public.payroll_key_info(p_key text, p_row text default null)
returns jsonb language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when (app.is_admin() or app.is_hr()) and coalesce(p_key, '') <> '' then jsonb_build_object(
    'salary',   (select count(*) from public.salary_payments where "teacherId" = p_key),
    'advances', (select count(*) from public.staff_advances  where "teacherId" = p_key),
    'children', (select count(*) from public.student_private sp where sp."teacherId" = p_key
                   or (coalesce(p_row, '') <> '' and sp."teacherId" = p_row
                       and not exists (select 1 from public.teachers t2 where t2."teacherId" = p_row))),
    'owners',   (select count(*) from public.teachers t where coalesce(nullif(t."teacherId", ''), t.id) = p_key)
              + (select count(*) from public.staff s    where coalesce(nullif(s."staffId", ''), s.id) = p_key)
  ) end
$$;
revoke all on function public.payroll_key_info(text, text) from public, anon;
grant execute on function public.payroll_key_info(text, text) to authenticated, service_role;

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
  -- Eski va yangi kalit bo'yicha navbat (5-band triggeri bilan): shu paytda berilayotgan maosh/avans kutadi.
  --   Tartib bilan (kichigi oldin) — ikki parallel ID o'zgartirish bir-birini kutib qolmasin.
  perform pg_advisory_xact_lock(hashtext('iqror:payroll:' || least(v_key, p_new)));
  perform pg_advisory_xact_lock(hashtext('iqror:payroll:' || greatest(v_key, p_new)));
  -- Yangi ID boshqa o'qituvchi/xodimning kaliti emas (o'qituvchi va xodim maosh kalitlari BITTA nomlar fazosida).
  if exists (select 1 from public.teachers t where btrim(coalesce(nullif(t."teacherId", ''), t.id)) = p_new and not (p_coll = 'teachers' and t.id = p_row))
     or exists (select 1 from public.staff s where btrim(coalesce(nullif(s."staffId", ''), s.id)) = p_new and not (p_coll = 'staff' and s.id = p_row)) then
    raise exception 'ID «%» boshqa xodim/o''qituvchida bor — takroriy ID maosh/avansni aralashtiradi', p_new using errcode = '23505';
  end if;
  -- Yangi ID ostida egasiz (o'chirilgan xodimning) maosh/avans tarixi yoki «xodim farzandi» bog'lanishi — meros olinmasin
  --   (bog'lanish o'qituvchiga ko'chsa, o'sha bolalar yangi o'qituvchiniki bo'lib ko'rinardi).
  if exists (select 1 from public.salary_payments where "teacherId" = p_new)
     or exists (select 1 from public.staff_advances where "teacherId" = p_new)
     or (p_coll = 'teachers' and exists (select 1 from public.student_private where "teacherId" = p_new)) then
    raise exception 'ID «%» ostida avvalgi (o''chirilgan) xodimning maosh/avans tarixi yoki «xodim farzandi» bog''lanishi bor — boshqa ID tanlang', p_new
      using errcode = '23505';
  end if;
  -- Eski kalit boshqa yozuvda ham bo'lsa (takroriy ID) — tarix kimniki ekani noma'lum: KO'CHIRILMAYDI.
  select (select count(*) from public.teachers t where coalesce(nullif(t."teacherId", ''), t.id) = v_key and not (p_coll = 'teachers' and t.id = p_row))
       + (select count(*) from public.staff s    where coalesce(nullif(s."staffId", ''), s.id) = v_key and not (p_coll = 'staff' and s.id = p_row))
    into v_shared;
  v_move := (v_shared = 0);
  -- 7-band triggeri: ID shu funksiya ichida (tarix bilan) o'zgaradi; 5-band triggeri: tarixni shu funksiya (kalitlarni
  --   qulflab) ko'chiradi — payeeRef'i boshqa (o'chirilgan) odamniki bo'lgan eski yozuv ID o'zgartirishni to'xtatmasin.
  perform set_config('iqror.rekey', '1', true);
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
  perform set_config('iqror.rekey', '', true);
  -- Foydalanuvchi yorlig'i (faqat ko'rinish uchun nusxa) ham yangilanadi.
  update public.users set "staffCode" = p_new
   where "staffRefId" = p_row and "staffRefType" = (case when p_coll = 'teachers' then 'teacher' else 'staff' end);
  return jsonb_build_object('moved', v_move, 'shared', not v_move, 'oldKey', v_key,
                            'salary', n_sal, 'advances', n_adv, 'children', n_ch);
end $$;
revoke all on function public.rekey_payroll_id(text, text, text, text) from public, anon;
grant execute on function public.rekey_payroll_id(text, text, text, text) to authenticated, service_role;

-- ---- 5) Maosh/avans yozuvi kaliti: faqat SHU odamning hozirgi kaliti; ID o'zgartirish bilan navbat ----
--   Kalit — admin.html dagi kabi String(teacherId||_id) (xom). payeeRef — '<jadval>:<qator id>' ('teachers:t1' / 'staff:s1'):
--   yozuv kim uchun (o'qituvchi va xodim kalitlari BITTA nomlar fazosida — jadval ham kerak); admin.html uni oyna ochilganda
--   o'qilgan ro'yxatdagi xodimdan yuboradi. Ilova foydalanuvchisi (app.uid()) yozganda, navbat (advisory lock) ichida:
--   • payeeRef bor — o'sha qatorning HOZIRGI kaliti new."teacherId" ga teng bo'lishi shart. Oyna ochilgandan keyin ID o'zgargan,
--     bo'shagan ID boshqa odamga berilgan yoki xodim o'chirilgan — rad (23503): aks holda maosh/avans kalitning YANGI egasiga jim
--     yozilardi (biri kam oladi, boshqasiga ikki marta beriladi). Mavjud yozuvni qayta yozish (upsert) ham tekshiriladi.
--     Buzuq payeeRef — 22023.
--   • payeeRef yo'q (eski mijoz / eski yozuv) — avvalgidek: kalit biror o'qituvchi/xodimda bo'lsin; mavjud yozuvni xuddi shu
--     kalit bilan qayta yozish (upsert) — tekshirilmaydi (o'chirilgan xodim tarixi ham saqlanadi).
--   Kalit va payeeRef o'zgarmagan yangilanish — tekshirilmaydi. SQL / service_role (import, tuzatish) — faqat navbat.
--   rekey_payroll_id tarixni ko'chirganda (iqror.rekey) — faqat navbat: qaysi yozuv ko'chishini u kalitlarni qulflab o'zi hal qiladi.
alter table public.salary_payments add column if not exists "payeeRef" text;
alter table public.staff_advances  add column if not exists "payeeRef" text;
create or replace function app.guard_payroll_key()
  returns trigger language plpgsql security definer
  set search_path = public, app, pg_temp as $$
declare v_same boolean := false; v_coll text; v_row text; v_cur text;
begin
  if coalesce(new."teacherId", '') = '' then return new; end if;
  if tg_op = 'UPDATE' and new."teacherId" is not distinct from old."teacherId"
     and new."payeeRef" is not distinct from old."payeeRef" then return new; end if;
  perform pg_advisory_xact_lock(hashtext('iqror:payroll:' || new."teacherId"));
  if app.uid() is null then return new; end if;
  -- Maosh ko'ra olmaydigan foydalanuvchi (ota-ona, o'qituvchi, qabulxona…) — tekshiruv xabarisiz RLS rad etadi (42501): aks holda
  --   xato matni («hozir «IQT-001»») yoki 23503/42501 farqi xodimning maosh kalitini ko'rsatib qo'yardi. Yozish huquqi borlar
  --   (salpay_ins / sa_ins) hammasi can_see_salary ichida.
  if not app.can_see_salary() then return new; end if;
  if tg_op = 'UPDATE' and coalesce(current_setting('iqror.rekey', true), '') = '1' then return new; end if;
  if new."payeeRef" is not null then
    -- Navbat ichida o'qiladi: shu kalitni o'zgartirayotgan rekey_payroll_id tugagach, uning natijasi ko'rinadi.
    v_coll := split_part(new."payeeRef", ':', 1);
    v_row := substr(new."payeeRef", length(v_coll) + 2);
    if v_coll not in ('teachers', 'staff') or v_row = '' then
      raise exception 'Noto''g''ri payeeRef «%» (kutilgan: teachers:<qator id> yoki staff:<qator id>)', new."payeeRef"
        using errcode = '22023';
    end if;
    if v_coll = 'teachers' then
      select coalesce(nullif(t."teacherId", ''), t.id) into v_cur from public.teachers t where t.id = v_row;
    else
      select coalesce(nullif(s."staffId", ''), s.id) into v_cur from public.staff s where s.id = v_row;
    end if;
    if v_cur is distinct from new."teacherId" then
      raise exception 'Maosh/avans yozilmadi: xodimning ID''si oyna ochilgandan keyin o''zgartirilgan yoki xodim o''chirilgan (oynada «%», hozir «%») — oynani yopib, qayta oching',
        new."teacherId", coalesce(v_cur, 'o''chirilgan') using errcode = '23503';
    end if;
    return new;
  end if;
  if tg_op = 'INSERT' then
    execute format('select exists (select 1 from public.%I where id = $1 and "teacherId" = $2)', tg_table_name)
      into v_same using new.id, new."teacherId";
  end if;
  if not v_same
     and not exists (select 1 from public.teachers t where coalesce(nullif(t."teacherId", ''), t.id) = new."teacherId")
     and not exists (select 1 from public.staff s where coalesce(nullif(s."staffId", ''), s.id) = new."teacherId") then
    raise exception 'Maosh kaliti «%» hech bir o''qituvchi/xodimda yo''q (ID o''zgartirilgan yoki o''chirilgan) — sahifani yangilab, qayta urinib ko''ring', new."teacherId"
      using errcode = '23503';
  end if;
  return new;
end $$;
drop trigger if exists trg_salpay_key on public.salary_payments;
create trigger trg_salpay_key before insert or update of "teacherId", "payeeRef" on public.salary_payments
  for each row execute function app.guard_payroll_key();
drop trigger if exists trg_staffadv_key on public.staff_advances;
create trigger trg_staffadv_key before insert or update of "teacherId", "payeeRef" on public.staff_advances
  for each row execute function app.guard_payroll_key();

-- ---- 7) O'qituvchi/xodim ID'si (maosh kaliti): ilovadan faqat rekey_payroll_id orqali o'zgaradi; yangi ID takroriy emas ----
--   API orqali to'g'ridan-to'g'ri PATCH teacherId/staffId (maosh/avans eski kalitda «yetim» qolardi) va boshqa xodimning ID'si
--   bilan yozuv — rad. Mavjud (eski) takroriy ID'lar tegilmaydi: tekshiruv faqat ID yozilganda. SQL / service_role — tegilmaydi.
--   Takror tekshiruvi ID bo'yicha navbatda (rekey_payroll_id p_new uchun oladigan AYNAN shu qulf; p_new doim kesilgan): bir vaqtda
--   shu ID'ni yozayotgan ikki INSERT yoki INSERT va ID o'zgartirish bir-birining tranzaksiyasini kutadi — ikkalasi ham tekshiruvdan
--   o'tib, bitta ID ikki kishida (biriga ko'chirilgan maosh/avans tarixi bilan) qolmaydi. rekey ichida qulf allaqachon olingan.
create or replace function app.guard_payroll_id()
  returns trigger language plpgsql security definer
  set search_path = public, app, pg_temp as $$
declare v_new text; v_old text;
begin
  if app.uid() is null then return new; end if;
  if tg_table_name = 'teachers' then
    v_new := new."teacherId"; if tg_op = 'UPDATE' then v_old := old."teacherId"; end if;
  else
    v_new := new."staffId"; if tg_op = 'UPDATE' then v_old := old."staffId"; end if;
  end if;
  if tg_op = 'UPDATE' then
    if v_new is not distinct from v_old then return new; end if;
    if coalesce(current_setting('iqror.rekey', true), '') <> '1' then
      raise exception 'O''qituvchi/xodim ID''si faqat «ID o''zgartirish» orqali (maosh/avans tarixi bilan birga) o''zgaradi — kartochkani forma orqali saqlang'
        using errcode = '42501';
    end if;
  end if;
  if btrim(coalesce(v_new, '')) <> '' then
    perform pg_advisory_xact_lock(hashtext('iqror:payroll:' || btrim(v_new)));
  end if;
  if btrim(coalesce(v_new, '')) <> ''
     and (exists (select 1 from public.teachers t where btrim(coalesce(nullif(t."teacherId", ''), t.id)) = btrim(v_new) and not (tg_table_name = 'teachers' and t.id = new.id))
       or exists (select 1 from public.staff s where btrim(coalesce(nullif(s."staffId", ''), s.id)) = btrim(v_new) and not (tg_table_name = 'staff' and s.id = new.id))) then
    raise exception 'ID «%» boshqa xodim/o''qituvchida bor — takroriy ID maosh/avansni aralashtiradi', v_new using errcode = '23505';
  end if;
  return new;
end $$;
drop trigger if exists trg_teacher_payroll_id on public.teachers;
create trigger trg_teacher_payroll_id before insert or update of "teacherId" on public.teachers
  for each row execute function app.guard_payroll_id();
drop trigger if exists trg_staff_payroll_id on public.staff;
create trigger trg_staff_payroll_id before insert or update of "staffId" on public.staff
  for each row execute function app.guard_payroll_id();

-- ---- 6) Kamera ID egalari va skan tarixi (qabulxona uchun ham) ----
--   Faqat tur, qator id'si va ism qaytadi (maosh / PII yo'q). Kamera ID chetidagi bo'sh joy hisobga olinmaydi.
create or replace function public.camera_owners(p_cam text)
returns jsonb language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.is_staff() and btrim(coalesce(p_cam, '')) <> '' then coalesce((
    select jsonb_agg(jsonb_build_object('coll', coll, 'id', id, 'name', name) order by coll, id) from (
      select 'students' as coll, s.id, s.name from public.students s where btrim(coalesce(s."cameraId", '')) = btrim(p_cam)
      union all select 'teachers', t.id, t.name from public.teachers t where btrim(coalesce(t."cameraId", '')) = btrim(p_cam)
      union all select 'staff', x.id, x.name from public.staff x where btrim(coalesce(x."cameraId", '')) = btrim(p_cam)) o
  ), '[]'::jsonb) end
$$;
revoke all on function public.camera_owners(text) from public, anon;
grant execute on function public.camera_owners(text) to authenticated, service_role;

create or replace function public.camera_has_scans(p_cam text)
returns boolean language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.is_staff() and btrim(coalesce(p_cam, '')) <> ''
    then exists (select 1 from public.staff_checkins c where c."personId" = btrim(p_cam)) end
$$;
revoke all on function public.camera_has_scans(text) from public, anon;
grant execute on function public.camera_has_scans(text) to authenticated, service_role;

notify pgrst, 'reload schema';
