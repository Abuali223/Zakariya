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
--      MAVJUD (bo'sh bo'lmagan) studentId'ni o'zgartira olmaydi. (o'zgarishsiz)
--   0/8) O'QITUVCHI/XODIM ID'si — PASPORT KABI: public.payroll_ids — HAR BIR berilgan teacherId/staffId (kanonik:
--      app.pid_key — chetidagi bo'shliqlarsiz, katta harf) reyestri. Bir marta yoziladi, HECH QACHON o'chirilmaydi:
--      o'qituvchi/xodim o'chirilsa ham, ID'si o'zgarsa ham (bir martalik tuzatish) — ID qayta BERILMAYDI. Har deployda
--      joriy ro'yxat + tarix (maosh, avans, «xodim farzandi», xodimga BOG'LANGAN login yorlig'i users.staffCode) bilan
--      to'ldiriladi (idempotent). Manbalar — faqat tekshirib yoziladiganlar: ixtiyoriy matn (IQT-999999999) yangi ID
--      chegarasini abadiy ko'tarib, ID berishni to'xtatib qo'yardi — shuning uchun «xodim farzandi» 9-band bilan tekshiriladi,
--      staffCode'ni o'z-o'zini ro'yxatdan o'tkazgan hisob yoza olmaydi (staff-user-link.sql users_ins). Mijozga yopiq
--      (RLS, grant yo'q) — faqat SECURITY DEFINER funksiyalar/triggerlar yozadi va o'qiydi.
--   2) payroll_id_high_water(prefix) — IQT-/IQX- eng katta raqami: reyestr + joriy ro'yxat + tarix.
--   3) payroll_key_info(key) — kalit ostidagi tarix (+ issued/released — reyestrda bormi, bo'shatilganmi).
--   4) rekey_payroll_id(...) — FAQAT bir martalik tuzatish: eski ID BO'SH yoki TAKRORIY (boshqa joriy xodimda ham bor)
--      bo'lsa; yangi ID — shu jadval prefiksi (o'qituvchi IQT-, xodim IQX-) va hech qachon berilmagan raqam (> high-water).
--      Takroriy ID'da prefiksi jadvaliga mos egasi ID'ni SAQLAYDI (masalan IQT-016: o'qituvchi qoladi, xodim tuzatiladi).
--   5) Maosh/avans yozuvi kaliti (o'zgarishsiz).
--   6) camera_owners / camera_has_scans (o'zgarishsiz).
--   7) teacherId/staffId: ilovadan faqat rekey_payroll_id orqali (bir martalik); YANGI yozuv ID'si — prefiks + hech qachon
--      berilmagan raqam. payroll_id_state(coll, row) — forma uchun: ID tuzatilishi mumkinmi va keyingi noyob ID.
--   9) student_private."teacherId" («xodim farzandi» bog'lanishi; ID chegarasi manbalaridan biri): ilovadan faqat MAVJUD
--      o'qituvchi/xodim kaliti (o'zgarmagan eski qiymat — tegilmaydi).
-- 1–4, 7 — faqat direktor/HR (app.is_admin() / app.is_hr()); 6 — faol xodim; 9 — har qanday ilova foydalanuvchisi.
--   SQL / service_role (app.uid() bo'sh) — tekshiruvsiz (texnik tuzatish), lekin reyestr baribir yuritiladi. Idempotent (run-all.sql).
-- =====================================================================

-- ---- 0) Berilgan ID'lar reyestri ----
-- Kanonik ID (admin.html pidCanon bilan AYNAN bir xil): (1) ko'rinmas format belgilari (zero-width, bidi, soft hyphen, BOM …
--   — veb/Telegram'dan nusxa-ko'chirishda qo'shiladi) HAMMA joydan olinadi; (2) chetidagi bo'shliqlar — JavaScript String.trim()
--   to'plami (bo'shliq, tab, qator oxiri, NBSP, U+2000–200A …; locale'ga bog'liq \s emas — aniq ro'yxat); (3) katta harf — faqat
--   a–z (translate: locale'ga bog'liq emas — prod/zaxira serveri locale'i boshqa bo'lsa ham CHECK va solishtiruv bir xil).
--   btrim faqat oddiy bo'shliqni olardi: nusxa-ko'chirishdagi «IQX-004<NBSP>» / «IQX-009<ZWSP>» alohida ID hisoblanib, baza o'zi
--   ko'rinishi bir xil «IQX-004» ni berib yuborardi (ikkisi ham «noyob», tuzatib bo'lmasdi). Avval o'chirish, keyin trim —
--   idempotent (pid_key(pid_key(x)) = pid_key(x)).
create or replace function app.pid_key(p text)
returns text language sql immutable parallel safe as $$
  select translate(regexp_replace(regexp_replace(coalesce(p, ''),
    '[\u00ad\u061c\u180e\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u206f\ufeff]', '', 'g'),
    '^[ \t\n\v\f\r\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+|[ \t\n\v\f\r\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g'),
    'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')
$$;
create table if not exists public.payroll_ids (
  id          text primary key check (id <> '' and id = app.pid_key(id)),     -- kanonik ID (app.pid_key)
  coll        text check (coll is null or coll in ('teachers', 'staff')),    -- birinchi ma'lum egasi (null — faqat tarixdan)
  row_id      text,                                                          -- teachers.id / staff.id
  raw         text,                                                          -- birinchi ko'rilgan xom qiymat (ma'lumot)
  source      text not null default 'trigger',                               -- backfill:* | insert | rekey | sql:* | release:*
  created_at  timestamptz not null default now(),
  released_at timestamptz                                                    -- joriy egasi qolmagan (o'chirilgan/almashtirilgan)
);
alter table public.payroll_ids enable row level security;
-- Mijoz (anon/authenticated) umuman ko'rmaydi/yozmaydi; service_role — faqat o'qish (diagnostika). supabase-grants.sql har
--   deployda barcha jadvallarga qayta grant beradi — shuning uchun bu yerda HAR SAFAR qayta olinadi (bitta tranzaksiya).
revoke all on table public.payroll_ids from public, anon, authenticated, service_role;
grant select on table public.payroll_ids to service_role;
-- Kanonik shakl o'zgargan bo'lsa (avvalgi deploy'dagi pid_key): yozuv yangi shaklda qayta yoziladi — ID band qoladi, CHECK
--   (id = app.pid_key(id)) keyingi yangilanishda (bo'shatish) yiqilmaydi. Odatda 0 qator.
insert into public.payroll_ids (id, coll, row_id, raw, source, created_at, released_at)
select app.pid_key(id), coll, row_id, raw, source, created_at, released_at
  from public.payroll_ids where id <> app.pid_key(id) and app.pid_key(id) <> ''
on conflict (id) do nothing;
delete from public.payroll_ids where id <> app.pid_key(id);

-- To'ldirish (har deployda; mavjud yozuv tegilmaydi). Jadvallar zanjirning oldingi fayllarida (ALTER/POLICY) allaqachon
--   qulflangan — parallel yozuv bu o'qish va triggerlar orasiga tushmaydi; aniq bo'lishi uchun yana (DO ichida: zanjirsiz
--   `psql -f run-all.sql` — autocommit — ham yiqilmasin; chain.sh'ning BEGIN…COMMIT ichida qulf COMMIT'gacha turadi).
do $$ begin lock table public.teachers, public.staff in share row exclusive mode; end $$;
insert into public.payroll_ids (id, coll, row_id, raw, source, released_at)
select distinct on (k) k, coll, row_id, raw, source, released_at
  from (
    select app.pid_key(t."teacherId") k, 'teachers' coll, t.id row_id, t."teacherId" raw, 'backfill:teachers' source,
           null::timestamptz released_at, case when app.pid_key(t."teacherId") like 'IQT-%' then 0 else 1 end pri
      from public.teachers t where app.pid_key(t."teacherId") <> ''
    union all
    select app.pid_key(s."staffId"), 'staff', s.id, s."staffId", 'backfill:staff', null,
           case when app.pid_key(s."staffId") like 'IQX-%' then 0 else 1 end
      from public.staff s where app.pid_key(s."staffId") <> ''
    union all
    -- Tarix: o'chirilgan xodimlarning kalitlari ham (joriy qator id'si — bo'sh ID'li odamning ichki kaliti — emas).
    --   Maosh/avans kaliti yozilishida tekshiriladi (guard_payroll_key), «xodim farzandi» — 9-band, login yorlig'i — faqat
    --   xodim yozuviga bog'langan hisobniki (bog'lashni faqat admin/server o'rnatadi).
    select app.pid_key(h.k), null, null, h.k, 'backfill:' || h.src, now(), 2
      from (select "teacherId" k, 'salary_payments' src from public.salary_payments
            union all select "teacherId", 'staff_advances' from public.staff_advances
            union all select "teacherId", 'student_private' from public.student_private
            union all select "staffCode", 'users' from public.users
             where "staffRefType" in ('teacher', 'staff') and coalesce("staffRefId", '') <> '') h
     where app.pid_key(h.k) <> ''
       and not exists (select 1 from public.teachers t where t.id = h.k)
       and not exists (select 1 from public.staff s where s.id = h.k)
  ) x
 order by k, pri, coll nulls last, row_id
on conflict (id) do nothing;

-- Takroriy ID'lar (eski ma'lumot) — deploy chiqishida ko'rinadi (deploy.sh «OGOHLANTIRISH» qatorlarini chiqaradi).
do $$
declare r record;
begin
  for r in
    select k, count(*) n, string_agg(coll || ':' || id || ' «' || coalesce(name, '') || '»', ', ' order by coll, id) who
      from (select app.pid_key("teacherId") k, 'teachers' coll, id, name from public.teachers where app.pid_key("teacherId") <> ''
            union all select app.pid_key("staffId"), 'staff', id, name from public.staff where app.pid_key("staffId") <> '') x
     group by k having count(*) > 1 order by k
  loop
    raise notice 'OGOHLANTIRISH: takroriy o''qituvchi/xodim ID «%» (% ta: %) — kartochkada «Yangi noyob ID berish» bilan bir martalik tuzating', r.k, r.n, r.who;
  end loop;
end $$;

-- Ichki yordamchi: IQT-/IQX- eng katta berilgan raqam (reyestr + joriy + tarix). SECURITY INVOKER: faqat definer
--   funksiyalar/triggerlar ichidan (egasi huquqi bilan) ishlaydi; mijoz to'g'ridan chaqirsa — reyestrni o'qiy olmaydi.
--   Manbalar — faqat tekshirib yoziladiganlar (yuqoridagi izoh; login yorlig'i — faqat bog'langan hisobniki).
create or replace function app.payroll_hw(p_prefix text)
returns int language plpgsql stable set search_path = public, app, pg_temp as $$
declare v int;
begin
  if p_prefix is null or p_prefix not in ('IQT-', 'IQX-') then return 0; end if;
  select coalesce(max((regexp_match(app.pid_key(x), '^' || p_prefix || '([0-9]{1,9})$'))[1]::int), 0) into v
    from (select id as x from public.payroll_ids
          union all select "teacherId" from public.teachers
          union all select "staffId" from public.staff
          union all select "teacherId" from public.salary_payments
          union all select "teacherId" from public.staff_advances
          union all select "teacherId" from public.student_private
          union all select "staffCode" from public.users
           where "staffRefType" in ('teacher', 'staff') and coalesce("staffRefId", '') <> '') t
   where coalesce(x, '') <> '';
  return v;
end $$;
revoke all on function app.payroll_hw(text) from public, anon, authenticated;

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

-- ---- 2) Yangi o'qituvchi/xodim ID'si uchun yuqori chegara (reyestr ham) ----
create or replace function public.payroll_id_high_water(p_prefix text)
returns int language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not (app.is_admin() or app.is_hr()) or coalesce(p_prefix, '') not in ('IQT-', 'IQX-') then
    return 0;
  end if;
  return app.payroll_hw(p_prefix);
end $$;
revoke all on function public.payroll_id_high_water(text) from public, anon;
grant execute on function public.payroll_id_high_water(text) to authenticated, service_role;

-- ---- 3) Maosh kaliti tarixi (+ reyestr holati) ----
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
              + (select count(*) from public.staff s    where coalesce(nullif(s."staffId", ''), s.id) = p_key),
    'issued',   exists (select 1 from public.payroll_ids p where p.id = app.pid_key(p_key)),
    'released', exists (select 1 from public.payroll_ids p where p.id = app.pid_key(p_key) and p.released_at is not null)
  ) end
$$;
revoke all on function public.payroll_key_info(text, text) from public, anon;
grant execute on function public.payroll_key_info(text, text) to authenticated, service_role;

-- ---- 7a) Forma uchun: shu qatorning ID'si bir martalik tuzatilishi mumkinmi + keyingi noyob ID ----
--   fixable: ID bo'sh YOKI takroriy (kanonik — app.pid_key); takroriyda prefiksi jadvaliga mos (IQT- o'qituvchi /
--   IQX- xodim) egasi, mos KELMAYDIGAN boshqa egasi bo'lsa — ID'ni saqlaydi ('keep'): tuzatish o'sha boshqa kartochkada.
create or replace function public.payroll_id_state(p_coll text, p_row text)
returns jsonb language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_raw text; v_k text; v_pc text; v_pfx text; n_other int := 0; n_mis int := 0; v_fix boolean; v_hw int;
begin
  if not (app.is_admin() or app.is_hr()) or p_coll is null or p_coll not in ('teachers', 'staff') then return null; end if;
  if p_coll = 'teachers' then select "teacherId" into v_raw from public.teachers where id = p_row;
  else select "staffId" into v_raw from public.staff where id = p_row; end if;
  if not found then return null; end if;
  v_pfx := case p_coll when 'teachers' then 'IQT-' else 'IQX-' end;
  v_k := app.pid_key(v_raw);
  if v_k <> '' then
    v_pc := case when v_k like 'IQT-%' then 'teachers' when v_k like 'IQX-%' then 'staff' end;
    select count(*), count(*) filter (where o.coll is distinct from v_pc) into n_other, n_mis
      from (select 'teachers'::text coll from public.teachers t
             where app.pid_key(t."teacherId") = v_k and not (p_coll = 'teachers' and t.id = p_row)
            union all
            select 'staff' from public.staff s
             where app.pid_key(s."staffId") = v_k and not (p_coll = 'staff' and s.id = p_row)) o;
  end if;
  v_fix := v_k = '' or (n_other > 0 and not (coalesce(v_pc = p_coll, false) and n_mis > 0));
  v_hw := app.payroll_hw(v_pfx) + 1;
  return jsonb_build_object(
    'id', v_raw, 'fixable', v_fix, 'others', n_other,
    'reason', case when v_k = '' then 'empty' when n_other = 0 then 'unique' when v_fix then 'duplicate' else 'keep' end,
    'next', v_pfx || lpad(v_hw::text, greatest(3, length(v_hw::text)), '0'));
end $$;
revoke all on function public.payroll_id_state(text, text) from public, anon;
grant execute on function public.payroll_id_state(text, text) to authenticated, service_role;

-- ---- 4) ID bir martalik tuzatish + tarixni ko'chirish (atomik) ----
create or replace function public.rekey_payroll_id(p_coll text, p_row text, p_old text, p_new text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_cur    text;
  v_key    text;
  v_shared int;
  v_move   boolean;
  v_pfx    text;
  v_num    int;
  v_hw     int;
  v_state  jsonb;
  k        text;
  n_sal    int := 0;
  n_adv    int := 0;
  n_ch     int := 0;
begin
  if not (app.is_admin() or app.is_hr()) then
    raise exception 'O''qituvchi/xodim ID''sini faqat direktor yoki HR tuzatadi' using errcode = '42501';
  end if;
  if p_coll is null or p_coll not in ('teachers', 'staff') then
    raise exception 'Noto''g''ri jadval: %', p_coll using errcode = '22023';
  end if;
  v_pfx := case p_coll when 'teachers' then 'IQT-' else 'IQX-' end;
  -- Yangi ID: faqat shu jadval prefiksi + raqam (kanonik: kamida 3 xona, ortiqcha nolsiz) — «yangi noyob ID» beradi.
  if coalesce(p_new, '') !~ ('^' || v_pfx || '[0-9]{3,9}$') then
    raise exception 'Yangi ID «%» noto''g''ri — % uchun faqat %NNN («Yangi noyob ID berish» tugmasi)', coalesce(p_new, ''),
      case p_coll when 'teachers' then 'o''qituvchi' else 'xodim' end, v_pfx using errcode = '22023';
  end if;
  v_num := substr(p_new, length(v_pfx) + 1)::int;
  if p_new <> v_pfx || lpad(v_num::text, greatest(3, length(v_num::text)), '0') then
    raise exception 'Yangi ID «%» kanonik emas (kutilgan %)', p_new, v_pfx || lpad(v_num::text, greatest(3, length(v_num::text)), '0')
      using errcode = '22023';
  end if;
  -- Qator qulflanadi: parallel tahrir/ID tuzatish tugashini kutadi.
  if p_coll = 'teachers' then
    select "teacherId" into v_cur from public.teachers where id = p_row for update;
  else
    select "staffId" into v_cur from public.staff where id = p_row for update;
  end if;
  if not found then
    raise exception 'Yozuv topilmadi (o''chirilgan bo''lishi mumkin) — sahifani yangilang' using errcode = 'P0002';
  end if;
  if coalesce(v_cur, '') is distinct from coalesce(p_old, '') then
    raise exception 'ID boshqa joyda o''zgartirilgan (bazada hozir «%») — oynani yopib, qayta oching', coalesce(v_cur, '')
      using errcode = 'P0001';
  end if;
  v_key := case when coalesce(v_cur, '') = '' then p_row else v_cur end;
  if v_key = p_new then
    return jsonb_build_object('moved', false, 'same', true, 'oldKey', v_key);
  end if;
  -- Navbat (kichigi oldin — o'zaro kutib qolmasin): eski xom kalit, eski KANONIK ID (bo'shliq/harf varianti bo'lgan ikki
  --   takroriy egasi bir vaqtda tuzatmasin) va yangi ID.
  for k in select distinct x from unnest(array[v_key, nullif(app.pid_key(v_cur), ''), p_new]) x
            where x is not null order by x loop
    perform pg_advisory_xact_lock(hashtext('iqror:payroll:' || k));
  end loop;
  -- PASPORT: faqat bo'sh yoki takroriy ID bir marta tuzatiladi (navbat ichida — boshqa egasi shu paytda tuzatgan bo'lsa ko'rinadi).
  v_state := public.payroll_id_state(p_coll, p_row);
  if not coalesce((v_state ->> 'fixable')::boolean, false) then
    raise exception '%', case v_state ->> 'reason'
        when 'keep' then format('ID «%s» shu %s ID''si (prefiksi mos) — takroriylikni boshqa (prefiksi mos kelmaydigan) kartochkada tuzating',
                                v_cur, case p_coll when 'teachers' then 'o''qituvchining' else 'xodimning' end)
        else format('ID «%s» pasport kabi o''zgarmaydi — faqat bo''sh yoki takroriy ID bir marta tuzatiladi (eski oyna bo''lsa — sahifani yangilang: Ctrl+Shift+R)', v_cur) end
      using errcode = '42501';
  end if;
  -- Yangi ID hech qachon berilmagan bo'lsin (o'chirilgan / almashtirilgan xodimniki ham — reyestr va tarix).
  v_hw := app.payroll_hw(v_pfx);
  if v_num <= v_hw or exists (select 1 from public.payroll_ids where id = p_new) then
    raise exception 'ID «%» avval berilgan (o''chirilgan xodimniki ham qayta berilmaydi) — yangi ID: %', p_new,
      v_pfx || lpad((v_hw + 1)::text, greatest(3, length((v_hw + 1)::text)), '0') using errcode = '23505';
  end if;
  -- (Quyidagi ikki tekshiruv yuqoridagi «> high-water» bilan qoplangan — himoya chuqurligi uchun qoldirildi.)
  if exists (select 1 from public.teachers t where app.pid_key(coalesce(nullif(t."teacherId", ''), t.id)) = p_new and not (p_coll = 'teachers' and t.id = p_row))
     or exists (select 1 from public.staff s where app.pid_key(coalesce(nullif(s."staffId", ''), s.id)) = p_new and not (p_coll = 'staff' and s.id = p_row)) then
    raise exception 'ID «%» boshqa xodim/o''qituvchida bor — takroriy ID maosh/avansni aralashtiradi', p_new using errcode = '23505';
  end if;
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
      update public.student_private sp set "teacherId" = p_new
       where sp."teacherId" = v_key
          or (sp."teacherId" = p_row and not exists (select 1 from public.teachers t2 where t2."teacherId" = p_row));
      get diagnostics n_ch = row_count;
    end if;
  end if;
  perform set_config('iqror.rekey', '', true);
  update public.users set "staffCode" = p_new
   where "staffRefId" = p_row and "staffRefType" = (case when p_coll = 'teachers' then 'teacher' else 'staff' end);
  return jsonb_build_object('moved', v_move, 'shared', not v_move, 'oldKey', v_key, 'newKey', p_new,
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

-- ---- 7) O'qituvchi/xodim ID'si: BEFORE — ilova qoidalari ----
--   UPDATE: ID faqat rekey_payroll_id ichida (u bir martalik tuzatish shartlarini navbat ichida tekshirgan).
--   INSERT: setDoc (INSERT … ON CONFLICT (id) DO UPDATE) MAVJUD qatorda ham avval shu yerdan o'tadi — mavjud qator: o'tkaziladi
--     (ID o'zgarishini UPDATE yo'li ushlaydi; sof INSERT esa PK 23505 bilan yiqiladi). YANGI qator: ID shu jadval prefiksi + raqam
--     (kanonik) va raqam hech qachon berilmagan (> high-water: reyestr + tarix) — shu ID bo'yicha navbatda (ikki parallel INSERT
--     yoki INSERT va ID tuzatish bir xil ID'ni ikki kishiga bera olmaydi).
create or replace function app.guard_payroll_id()
  returns trigger language plpgsql security definer
  set search_path = public, app, pg_temp as $$
declare v_new text; v_old text; v_pfx text; v_num int; v_hw int; v_exists boolean;
begin
  if app.uid() is null then return new; end if;
  if tg_table_name = 'teachers' then
    v_new := new."teacherId"; v_pfx := 'IQT-'; if tg_op = 'UPDATE' then v_old := old."teacherId"; end if;
  else
    v_new := new."staffId"; v_pfx := 'IQX-'; if tg_op = 'UPDATE' then v_old := old."staffId"; end if;
  end if;
  -- PASPORT: mavjud yozuvning ID'si HAR QANDAY ilova foydalanuvchisi (rol va SECURITY DEFINER yo'lidan qat'i nazar) uchun
  --   o'zgarmaydi — faqat rekey_payroll_id ichida (bo'sh/takroriy ID'ni bir martalik tuzatish; iqror.rekey).
  if tg_op = 'UPDATE' then
    if v_new is not distinct from v_old then return new; end if;
    if coalesce(current_setting('iqror.rekey', true), '') <> '1' then
      raise exception 'O''qituvchi/xodim ID''si pasport kabi o''zgarmaydi — bo''sh yoki takroriy ID faqat «Yangi noyob ID berish» orqali bir marta tuzatiladi (eski oyna bo''lsa — sahifani yangilang: Ctrl+Shift+R)'
        using errcode = '42501';
    end if;
    return new;
  end if;
  -- INSERT: faqat direktor/HR yozadi (teachers_ins, staff_ins): boshqa rolga tekshiruv yo'q — RLS xabarsiz rad etadi (42501);
  --   23505/22023 javobi ID bor-yo'qligini oshkor qilmasin.
  if not (app.is_admin() or app.is_hr()) then return new; end if;
  execute format('select exists (select 1 from public.%I where id = $1)', tg_table_name) into v_exists using new.id;
  if v_exists then return new; end if;
  if coalesce(v_new, '') !~ ('^' || v_pfx || '[0-9]{3,9}$') then
    raise exception 'Yangi % ID''si «%» noto''g''ri — kutilgan %NNN (avtomatik beriladi)',
      case tg_table_name when 'teachers' then 'o''qituvchi' else 'xodim' end, coalesce(v_new, ''), v_pfx using errcode = '22023';
  end if;
  v_num := substr(v_new, length(v_pfx) + 1)::int;
  if v_new <> v_pfx || lpad(v_num::text, greatest(3, length(v_num::text)), '0') then
    raise exception 'Yangi ID «%» kanonik emas (kutilgan %)', v_new, v_pfx || lpad(v_num::text, greatest(3, length(v_num::text)), '0')
      using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('iqror:payroll:' || v_new));
  v_hw := app.payroll_hw(v_pfx);
  if v_num <= v_hw or exists (select 1 from public.payroll_ids where id = v_new) then
    raise exception 'ID «%» avval berilgan (o''chirilgan xodimniki ham qayta berilmaydi) — yangi ID: %', v_new,
      v_pfx || lpad((v_hw + 1)::text, greatest(3, length((v_hw + 1)::text)), '0') using errcode = '23505';
  end if;
  return new;
end $$;
drop trigger if exists trg_teacher_payroll_id on public.teachers;
create trigger trg_teacher_payroll_id before insert or update of "teacherId" on public.teachers
  for each row execute function app.guard_payroll_id();
drop trigger if exists trg_staff_payroll_id on public.staff;
create trigger trg_staff_payroll_id before insert or update of "staffId" on public.staff
  for each row execute function app.guard_payroll_id();

-- ---- 8) O'qituvchi/xodim ID'si: AFTER — reyestrni yuritish (hamma yo'l uchun, SQL ham) ----
--   AFTER — faqat HAQIQATAN yozilgan qatorlar, yakuniy qiymat bilan (upsert'ning UPDATE yo'li, ON CONFLICT DO NOTHING o'tkazgan
--   qator yozilmaydi). Yangi ID reyestrga; band bo'lsa — ilova: rad (23505, PK — har qanday izolyatsiyada oxirgi to'siq);
--   SQL: egasi qolmagan bo'lsa shu qatorga qayta bog'lanadi, aks holda ogohlantirish (takroriy). Eski ID: boshqa joriy egasi
--   qolmasa «bo'shatilgan» (yozuv O'CHMAYDI — ID qayta berilmaydi). TRUNCATE / o'chirilgan trigger — keyingi deploy to'ldiradi.
create or replace function app.record_payroll_id()
  returns trigger language plpgsql security definer
  set search_path = public, app, pg_temp as $$
declare v_new text; v_old text; k_new text; k_old text; v_n int; v_live boolean;
begin
  if tg_table_name = 'teachers' then
    if tg_op <> 'DELETE' then v_new := new."teacherId"; end if;
    if tg_op <> 'INSERT' then v_old := old."teacherId"; end if;
  else
    if tg_op <> 'DELETE' then v_new := new."staffId"; end if;
    if tg_op <> 'INSERT' then v_old := old."staffId"; end if;
  end if;
  k_new := app.pid_key(v_new);
  k_old := app.pid_key(v_old);
  if k_new <> '' and k_new is distinct from k_old then
    insert into public.payroll_ids (id, coll, row_id, raw, source)
    values (k_new, tg_table_name, new.id, v_new,
            case when coalesce(current_setting('iqror.rekey', true), '') = '1' then 'rekey'
                 when app.uid() is null then 'sql:' || lower(tg_op) else lower(tg_op) end)
    on conflict (id) do nothing;
    get diagnostics v_n = row_count;
    if v_n = 0 then
      if app.uid() is not null then
        raise exception 'ID «%» avval berilgan — qayta berilmaydi (pasport kabi)', k_new using errcode = '23505';
      end if;
      v_live := exists (select 1 from public.teachers t where app.pid_key(t."teacherId") = k_new and not (tg_table_name = 'teachers' and t.id = new.id))
             or exists (select 1 from public.staff s where app.pid_key(s."staffId") = k_new and not (tg_table_name = 'staff' and s.id = new.id));
      if v_live then
        raise notice 'OGOHLANTIRISH: ID «%» boshqa joriy xodimda ham bor — SQL bilan TAKRORIY ID yozildi (%:%)', k_new, tg_table_name, new.id;
      else
        update public.payroll_ids set coll = tg_table_name, row_id = new.id, released_at = null, source = 'sql:rebind'
         where id = k_new and (coll is distinct from tg_table_name or row_id is distinct from new.id or released_at is not null);
        if found then raise notice 'Reyestr: ID «%» SQL bilan %:% ga (qayta) bog''landi', k_new, tg_table_name, new.id; end if;
      end if;
    end if;
  end if;
  if k_old <> '' and k_old is distinct from k_new
     and not exists (select 1 from public.teachers t where app.pid_key(t."teacherId") = k_old)
     and not exists (select 1 from public.staff s where app.pid_key(s."staffId") = k_old) then
    insert into public.payroll_ids (id, coll, row_id, raw, source, released_at)
    values (k_old, tg_table_name, old.id, v_old, 'release:' || lower(tg_op), now())
    on conflict (id) do update set released_at = coalesce(public.payroll_ids.released_at, now());
  end if;
  return null;
end $$;
drop trigger if exists trg_teacher_payroll_reg on public.teachers;
create trigger trg_teacher_payroll_reg after insert or update of "teacherId" or delete on public.teachers
  for each row execute function app.record_payroll_id();
drop trigger if exists trg_staff_payroll_reg on public.staff;
create trigger trg_staff_payroll_reg after insert or update of "staffId" or delete on public.staff
  for each row execute function app.record_payroll_id();

-- ---- 9) «Xodim farzandi» bog'lanishi: faqat MAVJUD o'qituvchi/xodim kaliti ----
--   student_private."teacherId" yangi ID chegarasiga (payroll_hw) va deploy reyestriga kiradi (o'chirilgan o'qituvchining
--   bog'lanishi bo'lgan raqam yangi odamga berilmasin). Shu sabab ilova foydalanuvchisi (qabulxona ham yozadi) bu yerga
--   faqat hozirgi kalitni — String(teacherId||id), forma ro'yxatidagi kabi — yoza oladi: ixtiyoriy matn (IQT-999999999)
--   yangi o'qituvchi/xodim ID berishni to'xtatib qo'yardi. O'zgarmagan qiymat (o'chirilgan xodim bog'lanishi ham, upsert
--   bilan qayta yuborilsa ham) va bo'sh qiymat — tekshirilmaydi. SQL / service_role — tekshiruvsiz. SECURITY DEFINER:
--   qabulxona o'qituvchilar ro'yxatini ko'rmaydi (RLS), tekshiruv esa ko'rishi kerak.
create or replace function app.guard_private_teacher_link()
  returns trigger language plpgsql security definer
  set search_path = public, app, pg_temp as $$
declare v_old text;
begin
  if app.uid() is null or coalesce(new."teacherId", '') = '' then return new; end if;
  -- Yozish huquqi yo'q foydalanuvchi (ota-ona, o'qituvchi, moliya …) — tekshiruvsiz: uni RLS (priv_ins/priv_upd — xuddi shu shart)
  --   xabarsiz rad etadi (42501); aks holda 23503/42501 farqi qaysi o'qituvchi/xodim ID'si borligini va o'quvchining yashirin
  --   bog'lanishini oshkor qilardi (guard_payroll_key / guard_payroll_id kabi).
  if not (app.is_admin() or app.is_reception()) then return new; end if;
  if tg_op = 'UPDATE' then v_old := old."teacherId";
  else select sp."teacherId" into v_old from public.student_private sp where sp.id = new.id; end if;   -- upsert: mavjud qator
  if new."teacherId" is not distinct from v_old then return new; end if;
  if exists (select 1 from public.teachers t where coalesce(nullif(t."teacherId", ''), t.id) = new."teacherId")
     or exists (select 1 from public.staff s where coalesce(nullif(s."staffId", ''), s.id) = new."teacherId") then
    return new;
  end if;
  raise exception '«Xodim farzandi»: «%» hech bir o''qituvchi/xodim ID''si emas — ro''yxatdan tanlang (o''chirilgan bo''lishi mumkin)', new."teacherId"
    using errcode = '23503';
end $$;
drop trigger if exists trg_private_teacher_link on public.student_private;
create trigger trg_private_teacher_link before insert or update of "teacherId" on public.student_private
  for each row execute function app.guard_private_teacher_link();

-- ---- 6) Kamera ID egalari va skan tarixi (qabulxona uchun ham) ----
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
