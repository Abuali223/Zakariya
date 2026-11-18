\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-11-maosh.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-11 (to'liq audit, 2026-11-18) — MAOSH, XODIMLAR VA FOYDALANUVCHILAR (H2).
--   Maosh darvozasi, oldingi qoldiq, vedomost yuborish / tasdiqlash qoidalari — payroll-approval.sql da (o'sha joyda tuzatilgan,
--   amaldagi ta'rif o'sha fayl). Bu faylda — yangi qo'riqchilar:
--
-- 1) XODIM AVANSI — summa musbat (A5-01). Manfiy avans (avans kassaga «qaytdi») faqat kassa funksiyasi ichida (kirim orderi bilan,
--    shu oy naqd avans qoldig'idan oshmaydi — kassa-links.sql). Aks holda Moliya menejeri / g'aznachi PostgREST orqali manfiy avans
--    yozib, vedomostdagi avans ayirmasini kamaytirar va to'lanadigan summani oshirardi (vedomost va darvoza avansni bazadan oladi —
--    app.payroll_adv). Summasi o'zgarmagan tahrir (masalan usul) — o'tadi.
--
-- 2) O'RINBOSARLIK — dars soni va bir dars haqi chegarasi (A5-01). Vedomostdagi o'rinbosarlik summasi shu yozuvlardan hisoblanadi
--    (dars × stavka); HR (subst_ins) bitta yozuvda 1000 dars yoki 1 000 000 so'mlik «stavka» bilan istalgan xodim maoshini oshira
--    olardi, HR qayta hisobi esa xuddi shu yozuvlardan hisoblagani uchun farq ko'rsatmasdi. Endi: dars soni butun, 1..12 (bitta
--    o'rinbosar bir kunda bir kelmagan xodim o'rniga); stavka 0 dan katta va Direktor belgilagan «1 dars haqi»dan
--    (config/finance."lessonRate", bo'lmasa 40 000 — admin.html bilan bir xil) oshmaydi. Eski formatdagi yozuv (dars soni ham, stavka
--    ham yo'q) — tekshirilmaydi (yangi oyna bunday yozmaydi).
--
-- 3) LOGIN HISOBI O'CHIRILGANDA kartadagi teskari havola tozalanadi (A5-04). «Foydalanuvchilar» → «O'chir» faqat users qatorini
--    o'chirardi: staff / teachers."userUid" eski (yo'q) hisobda qolib, karta abadiy «band» edi — yangi hisobni na avtomatik (server
--    'taken'), na ekran orqali bog'lab bo'lardi (HR'ga trigger ruxsat bermaydi), «📚 Sinflar» «hisob topilmadi» derdi, HR / Moliya
--    menejerining yangi hisobi kartaga bog'lanmagani uchun uning maosh qatori «Direktor tasdig'i»siz qolardi. Endi users qatori
--    qaysi yo'l bilan o'chmasin (ekran, server, SQL) — shu tranzaksiyada havola bo'shatiladi (o'zgarishlar tarixiga — o'chirgan
--    foydalanuvchi nomidan). Avval o'chirilgan hisoblardan qolgan «osilib qolgan» havolalar har deployda tozalanadi (NOTICE — karta
--    qator id'lari bilan; yo'q bo'lsa 0).
--
-- 4) OXIRGI FAOL DIREKTOR va O'Z HISOBI (A5-05). «Bloklash»da bor qoida (user-block.sql: self / last_director) o'chirish va
--    tahrirda yo'q edi: yagona Direktor o'z qatorini o'chirsa yoki rolini almashtirsa maktab Direktorsiz qolardi (qayta ro'yxatdan
--    o'tish 'staff' kutilayotgan hisob yaratadi, tasdiqlaydigan Direktor yo'q — faqat server orqali tiklanardi). Endi (mijoz JWT'si
--    bilan): o'z users qatorini o'chirib bo'lmaydi, o'z rolini / holatini o'zgartirib bo'lmaydi (buni boshqa Direktor qiladi), oxirgi
--    FAOL Direktor qatori o'chirilmaydi va roli / holati o'zgarmaydi. Server (service_role), migratsiya va bloklash RPC'lari (o'z
--    tekshiruvi bor) — cheklanmaydi. Bir vaqtdagi ikki o'zgarish navbat bilan tekshiriladi (ikkalasi o'tib Direktorsiz qolinmaydi).
--
-- 5) VEDOMOSTNI TAYYORLAGAN / TASDIQLAGAN ODAM ISMI (A5-08). Ismlar users jadvalidan o'qilardi — users_sel faqat o'z qatori yoki
--    Direktorga ochiq, shuning uchun HR / Moliya menejeri ekranida va HR chop etadigan oylik hisobot imzo qatorida ism o'rniga ichki
--    UUID chiqardi. public.payroll_actor_names — faqat maoshni ko'radigan rollarga (app.can_see_salary: Direktor, HR, moliya, kassir;
--    buxgalter — yo'q, unga avvalgidek «—») va faqat vedomost ishtirokchilari (tayyorlagan / tasdiqlagan / qaytargan / qayta ochgan,
--    qatorni tasdiqlagan Direktor) uchun ism va rol qaytaradi — email / telefon yo'q, boshqa foydalanuvchilar ro'yxati ochilmaydi.
--    Moliya menejeri / kassirning FAYL nusxasi (FD-28) avvalgidek ismsiz — buni admin.html hal qiladi.
--
-- Idempotent — QAYTA ishga tushirishga xavfsiz (create or replace, drop trigger if exists; ma'lumot tuzatish — faqat farq bo'lsa).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Xodim avansi — summa musbat (kassa funksiyasi va server — mustasno).
create or replace function app.staff_advance_amount_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if app.is_system() or coalesce(current_setting('iqror.kassa_rpc', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and new.amount is not distinct from old.amount then return new; end if;
  if new.amount is null or new.amount <= 0 then
    raise exception 'Xodim avansi: summa musbat bo''lishi kerak (xodim qaytargan avans — faqat «Kassa» orqali kirim orderi bilan)'
      using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function app.staff_advance_amount_guard() from public, anon, authenticated;
drop trigger if exists trg_staffadv_amount on public.staff_advances;
create trigger trg_staffadv_amount before insert or update on public.staff_advances
  for each row execute function app.staff_advance_amount_guard();

-- 2) O'rinbosarlik — dars soni va stavka chegarasi (server — mustasno).
create or replace function app.staff_subst_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_rate numeric;
begin
  if app.is_system() then return new; end if;
  if tg_op = 'UPDATE' and new.lessons is not distinct from old.lessons and new."ratePerLesson" is not distinct from old."ratePerLesson" then
    return new;
  end if;
  if new.lessons is null and new."ratePerLesson" is null then return new; end if;   -- eski format (dars soni yo'q)
  select case when coalesce(c."lessonRate", 0) > 0 then c."lessonRate" end into v_rate from public.config c where c.id = 'finance';
  v_rate := coalesce(v_rate, 40000);
  if new.lessons is null or new.lessons <> trunc(new.lessons) or new.lessons < 1 or new.lessons > 12 then
    raise exception 'O''rinbosarlik: dars soni 1 dan 12 gacha butun son bo''lishi kerak (bir o''rinbosar bir kunda bir kelmagan xodim o''rniga)'
      using errcode = '23514';
  end if;
  if new."ratePerLesson" is null or new."ratePerLesson" <= 0 or new."ratePerLesson" > v_rate then
    raise exception 'O''rinbosarlik: bir dars haqi 0 dan katta va «1 dars haqi» sozlamasidan (% so''m) oshmasligi kerak', v_rate
      using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function app.staff_subst_guard() from public, anon, authenticated;
drop trigger if exists trg_staff_subst_guard on public.staff_substitutions;
create trigger trg_staff_subst_guard before insert or update on public.staff_substitutions
  for each row execute function app.staff_subst_guard();

-- 3) Login hisobi o'chirilganda — kartadagi teskari havola bo'shatiladi (kartani himoya trigger'i — payroll-approval.sql 7-bo'lim —
--    o'chirayotgan Direktor / server nomidan o'tkazadi). Keyin — avvalgi o'chirishlardan qolgan osilib qolgan havolalar.
create or replace function app.users_unlink_cards() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  update public.teachers set "userUid" = null where "userUid" = old.id;
  update public.staff set "userUid" = null where "userUid" = old.id;
  return old;
end $$;
revoke all on function app.users_unlink_cards() from public, anon, authenticated;
drop trigger if exists trg_users_unlink_cards on public.users;
create trigger trg_users_unlink_cards after delete on public.users
  for each row execute function app.users_unlink_cards();
do $$
declare n int; v_list text;
begin
  with t as (update public.teachers x set "userUid" = null
              where coalesce(x."userUid", '') <> '' and not exists (select 1 from public.users u where u.id = x."userUid")
              returning 'teachers/' || x.id as k),
       s as (update public.staff x set "userUid" = null
              where coalesce(x."userUid", '') <> '' and not exists (select 1 from public.users u where u.id = x."userUid")
              returning 'staff/' || x.id as k),
       a as (select k from t union all select k from s)
  select count(*), string_agg(k, ', ' order by k) filter (where rn <= 20) into n, v_list
    from (select k, row_number() over (order by k) as rn from a) z;
  if n > 0 then
    raise notice 'OGOHLANTIRISH: % ta xodim / o''qituvchi kartasidagi login havolasi (userUid) o''chirilgan hisobga qaragan edi — bo''shatildi: % (endi «Foydalanuvchilar»da yangi hisobga bog''lash mumkin)',
      n, v_list || case when n > 20 then ', … yana ' || (n - 20) else '' end;
  else
    raise notice 'Login havolasi: o''chirilgan hisobga qaragan xodim / o''qituvchi kartasi yo''q (0)';
  end if;
end $$;

-- 4) Oxirgi faol Direktor va o'z hisobi.
create or replace function app.users_last_director_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_others int;
begin
  if app.is_system() or coalesce(current_setting('iqror.user_block', true), '') = '1' then return coalesce(new, old); end if;
  if tg_op = 'DELETE' and old.id = v_uid then
    raise exception 'O''z hisobingizni o''chira olmaysiz — kerak bo''lsa buni boshqa Direktor qiladi' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and old.id = v_uid
     and (new.role is distinct from old.role or coalesce(nullif(new.status, ''), 'active') <> coalesce(nullif(old.status, ''), 'active')) then
    raise exception 'O''z rolingiz yoki holatingizni o''zgartira olmaysiz — buni boshqa Direktor qiladi' using errcode = '42501';
  end if;
  if old.role = 'director' and coalesce(nullif(old.status, ''), 'active') = 'active'
     and (tg_op = 'DELETE' or new.role is distinct from 'director' or coalesce(nullif(new.status, ''), 'active') <> 'active') then
    -- navbat: bir vaqtda ikki Direktorni olib tashlash ikkalasi ham «yana bittasi bor» deb o'tib ketmasin
    perform pg_advisory_xact_lock(hashtext('iqror:last_director'));
    select count(*) into v_others from public.users u
     where u.role = 'director' and coalesce(nullif(u.status, ''), 'active') = 'active' and u.id <> old.id;
    if v_others < 1 then
      raise exception 'Oxirgi faol Direktor hisobini o''chirib ham, rolini / holatini o''zgartirib ham bo''lmaydi — avval boshqa Direktor tayinlang'
        using errcode = '42501';
    end if;
  end if;
  return coalesce(new, old);
end $$;
revoke all on function app.users_last_director_guard() from public, anon, authenticated;
drop trigger if exists trg_users_last_director on public.users;
create trigger trg_users_last_director before update or delete on public.users
  for each row execute function app.users_last_director_guard();

-- 5) Vedomost ishtirokchilari ismi (faqat maoshni ko'radigan rollar; faqat vedomostda qatnashgan hisoblar; ism va rol).
create or replace function public.payroll_actor_names(p_uids text[]) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.uid() is null or not app.can_see_salary() then '{}'::jsonb else coalesce((
    select jsonb_object_agg(u.id, jsonb_build_object('name', coalesce(nullif(btrim(u.name), ''),
                                                                       nullif(btrim(concat_ws(' ', u."firstName", u."lastName")), ''), ''),
                                                    'role', coalesce(u.role, u."blockedRole", '')))
      from public.users u
     where u.id in (select x from unnest(p_uids[1:50]) x)
       and (exists (select 1 from public.payroll_runs r where u.id in (r."preparedBy", r."approvedBy", r."returnedBy", r."reopenedBy"))
            or exists (select 1 from public.payroll_lines l where l."directorOkBy" = u.id))), '{}'::jsonb) end
$$;
revoke all on function public.payroll_actor_names(text[]) from public, anon;
grant execute on function public.payroll_actor_names(text[]) to authenticated, service_role;

notify pgrst, 'reload schema';
