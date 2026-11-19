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
--    (r4) Avansni O'CHIRISH, summasini KAMAYTIRISH yoki boshqa oy / xodimga ko'chirish ham — faqat Direktor (server va kassa
--    funksiyasi — mustasno: kassa orderini bekor qilish bog'langan avansni shu bayroq bilan olib tashlaydi). Sabab: haqiqatda
--    berilgan 1 000 000 lik avansni 1 so'mga tushirish yoki o'chirish (vedomost yuborilishidan oldin) manfiy avans bilan bir xil —
--    to'lanadigan summa shuncha oshardi, HR qayta hisobi ham shu jadvaldan o'qigani uchun farq ko'rsatmasdi. Jadvalda avansni KIM
--    yozgani saqlanmaydi (faqat server vaqti) — «yozgan odam shu kuni tuzatadi» istisnosi qilib bo'lmaydi: xato yozilgan avansni
--    Direktor o'chiradi yoki kamaytiradi (ekranda «O'chir» tugmasi faqat Direktorda). Summani oshirish, izoh / usul, sanani shu oy
--    ichida tuzatish — avvalgidek; xodim ID'sini tuzatish (rekey_payroll_id — iqror.rekey bayrog'i, faqat kalit o'zgaradi) — mustasno.
--
-- 1b) MAOSH BERISH YOZUVINI O'CHIRISH — faqat Direktor (A5-01, r4). salpay_del HR / Moliya menejeriga ham ochiq, maosh darvozasi
--    (payroll-approval.sql) esa faqat yozishni (INSERT / UPDATE) tekshirardi: tasdiqlangan oy to'lovini o'chirib qayta berish (daftarda
--    2 000 000, aslida 4 000 000 chiqdi) yoki eski oy to'lovining bir qismini o'chirib keyingi oy «oldingi qoldig'i»ni oshirish mumkin
--    edi. 0 so'mlik yozuv ham istisno emas: eski tartibdagi oyda oy qarzi eng so'nggi yozuvdan olinadi (tuzatish yozuvi o'chsa qarz
--    oshadi), o'tish oyidan keyin esa to'lovsiz oyning yagona yozuvi o'chsa xodimning qarzi qoldiqdan yo'qoladi. Ekranda maosh yozuvini
--    o'chirish yo'li yo'q; kassa funksiyalari (naqd maosh / qaytim / o'zaro hisob orderini bekor qilish — iqror.kassa_rpc bayrog'i bilan)
--    va server — mustasno. Kassirda o'chirish huquqi umuman yo'q (RLS — avvalgidek).
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
--    qator id'lari va ESKI havola qiymati bilan, masalan 'teachers/t1→U_GONE': migratsiya o'zgarishlar tarixiga yozilmaydi — hisob
--    adashib o'chirilgan bo'lsa, tiklangach kartani qaysi hisobga qayta bog'lash kerakligi shu qatordan bilinadi; yo'q bo'lsa 0).
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
-- 6) DEPLOY OGOHLANTIRISHLARI (faqat o'qiydi, har deployda; r4 — app.payroll_deploy_notice): (a) maosh tasdig'i o'tish oyi
--    (config/finance."payrollApprovalFrom") belgilangan bo'lsa — o'tish oyidan OLDINGI oylar bo'yicha qoldig'i (to'lanmagan yoki ortiqcha
--    berilgan — app.salary_carry) bor va u hali TASDIQLANGAN vedomostga kirmagan xodimlar maosh ID'lari bilan (20 tagacha): qoldiq
--    navbatdagi vedomostga «oldingi qoldiq» bo'lib o'zi qo'shiladi (alohida to'lash shart emas), eski oyning o'ziga yozuvni endi faqat
--    Direktor kiritadi (kassir / HR / Moliya menejerining, karta orqali to'lov ham — rad), egasi deploy paytida bilsin. Tasdiqlangan
--    vedomostga kirgan qoldiq ro'yxatdan chiqadi (eski oy qatorlari o'zgarmaydi — aks holda xodim har deployda qolar, Direktor eski oyga
--    yana to'lasa ortiqchasi keyingi maoshdan ushlanardi); (b) oy tugamasdan yuborilib hali tasdiqlanmagan vedomostlar — ularni HR endi
--    tasdiqlamaydi (payroll_decide 'stale': HR qaytaradi, Moliya menejeri oy tugagach qayta yuboradi yoki Direktor tasdiqlaydi).
--    Ogohlantirish matni natijada ham qaytadi ('notice') — sinov deploy ko'rsatadigan matnni tekshiradi.
--
-- Idempotent — QAYTA ishga tushirishga xavfsiz (create or replace, drop trigger if exists; ma'lumot tuzatish — faqat farq bo'lsa).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Xodim avansi — summa musbat; o'chirish, kamaytirish, boshqa oy / xodimga ko'chirish — faqat Direktor (kassa funksiyasi va
--    server — mustasno). Trigger nomi o'zgarmagan: kassa (trg_kassa_cash_guard) va tasdiqlangan oy qulfi (trg_payroll_input_lock)
--    alifbo tartibida undan OLDIN ishlaydi — ularning aniqroq xabari (kassa hujjatiga bog'langan, qaytim yozilgan, oy tasdiqlangan)
--    birinchi chiqadi.
create or replace function app.staff_advance_amount_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_om text; v_nm text;
begin
  if app.is_system() or coalesce(current_setting('iqror.kassa_rpc', true), '') = '1' then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    if app.is_admin() then return old; end if;
    raise exception 'Xodim avansini faqat Direktor o''chiradi: vedomost avansni bazadan ayiradi — o''chirilsa xodimga to''lanadigan summa shuncha oshadi (kassa orqali berilgan avans — «Kassa» bo''limida orderni bekor qilish bilan)'
      using errcode = '42501';
  end if;
  -- summa musbat (o'zgargan bo'lsa) — avval: manfiy summaga aniqroq yo'l-yo'riq (qaytgan avans — «Kassa» orqali) shu xabarda
  if (tg_op = 'INSERT' or new.amount is distinct from old.amount) and (new.amount is null or new.amount <= 0) then
    raise exception 'Xodim avansi: summa musbat bo''lishi kerak (xodim qaytargan avans — faqat «Kassa» orqali kirim orderi bilan)'
      using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and not app.is_admin() then
    -- oy — vedomost bilan bir xil (app.payroll_adv: month, bo'lmasa sana)
    v_om := coalesce(nullif(old.month, ''), left(coalesce(old.date, ''), 7));
    v_nm := coalesce(nullif(new.month, ''), left(coalesce(new.date, ''), 7));
    if new.amount < old.amount or v_nm is distinct from v_om
       or (new."teacherId" is distinct from old."teacherId" and coalesce(current_setting('iqror.rekey', true), '') <> '1') then
      raise exception 'Xodim avansining summasini kamaytirish yoki uni boshqa oy / xodimga ko''chirish — faqat Direktor: vedomost avansni bazadan ayiradi, kamaysa xodimga to''lanadigan summa oshadi (summani oshirish, izoh va usul — mumkin)'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
revoke all on function app.staff_advance_amount_guard() from public, anon, authenticated;
drop trigger if exists trg_staffadv_amount on public.staff_advances;
create trigger trg_staffadv_amount before insert or update or delete on public.staff_advances
  for each row execute function app.staff_advance_amount_guard();

-- 1b) Maosh berish yozuvini o'chirish — faqat Direktor (kassa funksiyasi va server — mustasno). Kassa qo'riqchisi (trg_kassa_cash_guard)
--     alifbo tartibida OLDIN ishlaydi — kassa hujjatiga bog'langan yozuvda uning xabari («Kassa» orqali bekor qiling) chiqadi.
create or replace function app.salary_payment_delete_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if app.is_system() or app.is_admin() or coalesce(current_setting('iqror.kassa_rpc', true), '') = '1' then return old; end if;
  raise exception 'Maosh berish yozuvini faqat Direktor o''chiradi: o''chirilsa oyning berilgani kamayib, maosh qayta berilishi yoki keyingi oy «oldingi qoldig''i» oshishi mumkin (kassa orqali berilgan maosh — «Kassa» bo''limida orderni bekor qilish bilan)'
    using errcode = '42501';
end $$;
revoke all on function app.salary_payment_delete_guard() from public, anon, authenticated;
drop trigger if exists trg_salpay_delete_guard on public.salary_payments;
create trigger trg_salpay_delete_guard before delete on public.salary_payments
  for each row execute function app.salary_payment_delete_guard();

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
--    Tuzatish — app.users_card_link_repair() (deploy har safar chaqiradi; sinov ham shu funksiyani tekshiradi). NOTICE'da eski qiymat ham
--    ('karta→eski hisob ID') — HAMMASI (20 ta bilan cheklanmaydi): migratsiya paytida o'zgarishlar tarixi yozilmaydi (iqror.migrating),
--    hisob adashib o'chirilgan va keyin o'sha ID bilan tiklangan bo'lsa — kartani qayta bog'lash uchun boshqa iz qolmaydi. UPDATE …
--    RETURNING eski qiymatni bermaydi — shuning uchun qatorlar avval tanlanadi (o). Matn natijada ham ('notice'). Faqat server /
--    migratsiya (mijoz rollariga ruxsat yo'q).
create or replace function app.users_card_link_repair() returns jsonb
language plpgsql set search_path = public, app, pg_temp as $$
declare n int; v_list text; v_all jsonb; m text;
begin
  with t as (update public.teachers x set "userUid" = null
               from (select y.id, y."userUid" as old_uid from public.teachers y
                      where coalesce(y."userUid", '') <> '' and not exists (select 1 from public.users u where u.id = y."userUid")) o
              where x.id = o.id
              returning 'teachers/' || x.id || '→' || o.old_uid as k),
       s as (update public.staff x set "userUid" = null
               from (select y.id, y."userUid" as old_uid from public.staff y
                      where coalesce(y."userUid", '') <> '' and not exists (select 1 from public.users u where u.id = y."userUid")) o
              where x.id = o.id
              returning 'staff/' || x.id || '→' || o.old_uid as k),
       a as (select k from t union all select k from s)
  select count(*), string_agg(k, ', ' order by k), coalesce(jsonb_agg(k order by k), '[]'::jsonb)
    into n, v_list, v_all
    from a;
  if n > 0 then
    m := format('OGOHLANTIRISH: %s ta xodim / o''qituvchi kartasidagi login havolasi (userUid) o''chirilgan hisobga qaragan edi — bo''shatildi (karta→eski hisob ID): %s (endi «Foydalanuvchilar»da yangi hisobga bog''lash mumkin; hisob adashib o''chirilgan bo''lsa — tiklangach shu kartaga qayta bog''lang)',
      n, v_list);
  else
    m := 'Login havolasi: o''chirilgan hisobga qaragan xodim / o''qituvchi kartasi yo''q (0)';
  end if;
  raise notice '%', m;
  return jsonb_build_object('count', n, 'cleared', v_all, 'notice', m);
end $$;
revoke all on function app.users_card_link_repair() from public, anon, authenticated;
do $a504$ begin perform app.users_card_link_repair(); end $a504$;

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

-- 6) Deploy ogohlantirishlari — app.payroll_deploy_notice() (faqat o'qiydi; deploy har safar chaqiradi, sinov ham shu funksiyani
--    tekshiradi). Ism / summa yo'q — faqat maosh ID va oy. Matn natijada ham ('notice'). Faqat server / migratsiya (mijoz rollariga
--    ruxsat yo'q).
create or replace function app.payroll_deploy_notice() returns jsonb
language plpgsql set search_path = public, app, pg_temp as $$
declare v_from text; v_carry text[]; v_stale text[]; n int; m text; v_msg text[] := '{}';
begin
  select nullif(btrim(coalesce(c."payrollApprovalFrom", '')), '') into v_from from public.config c where c.id = 'finance';
  -- (a) o'tish oyi belgilangan bo'lsa — undan OLDINGI oylar qoldig'i: app.salary_carry(x, o'tish oyi) faqat o'sha oylarni (eski tartib
  --     bilan) hisoblaydi — maosh darvozasi va vedomostdagi «oldingi qoldiq» bilan bir xil. payroll_submit bu qoldiqni o'tish oyidan
  --     keyingi vedomost qatoriga «oldingi qoldiq» (carryIn) qilib qo'shadi, u o'sha vedomost bilan to'lanadi, eski oy qatorlari esa
  --     o'zgarmaydi — shuning uchun tasdiqlangan (o'tish oyi yoki keyingi) vedomostda qatori bor xodim ro'yxatga kirmaydi.
  if v_from is not null then
    select coalesce(array_agg(p.tid order by p.tid), '{}') into v_carry
      from (select distinct s."teacherId" as tid from public.salary_payments s
             where coalesce(s."teacherId", '') <> '' and coalesce(s.month, '') <> '' and s.month < v_from) p
     where app.salary_carry(p.tid, v_from) <> 0
       and not exists (select 1 from public.payroll_lines l join public.payroll_runs r on r.id = l."runId"
                        where l."personId" = p.tid and r.status = 'approved' and l."runId" >= v_from);
    n := cardinality(v_carry);
    if n > 0 then
      m := format('OGOHLANTIRISH: %s ta xodim / o''qituvchida maosh tasdig''i o''tish oyidan (%s) oldingi oylar bo''yicha qoldiq bor (to''lanmagan yoki ortiqcha berilgan) va u hali tasdiqlangan vedomostga kirmagan — navbatdagi oylik vedomostga «oldingi qoldiq» bo''lib o''zi qo''shiladi va o''sha vedomost bilan to''lanadi (alohida to''lash shart emas); eski oyning o''ziga maosh yozuvini endi faqat Direktor kiritadi (kassir, HR, Moliya menejeri, karta orqali to''lov — rad): %s',
        n, v_from, array_to_string(v_carry[1:20], ', ') || case when n > 20 then ', … yana ' || (n - 20) else '' end);
    else
      m := format('Maosh qoldig''i: o''tish oyidan (%s) oldingi oylar bo''yicha vedomostga kirmagan qoldig''i bor xodim yo''q (0)', v_from);
    end if;
    raise notice '%', m;
    v_msg := v_msg || m;
  end if;
  -- (b) oy tugamasdan yuborilgan, hali tasdiqlanmagan vedomostlar (payroll_decide dagi 'stale' sharti bilan bir xil; o'tish oyidan
  --     qat'i nazar — vedomostni HR har doim shu qoida bilan tasdiqlaydi)
  select coalesce(array_agg(r.id order by r.id), '{}') into v_stale
    from public.payroll_runs r
   where r.status = 'submitted'
     and coalesce((r."submittedAt" at time zone 'Asia/Tashkent')::date, '-infinity'::date) < ((r.id || '-01')::date + interval '1 month')::date;
  if cardinality(v_stale) > 0 then
    m := format('OGOHLANTIRISH: %s ta oylik vedomost oy tugamasdan yuborilgan va hali tasdiqlanmagan — HR uni endi tasdiqlamaydi (ushlanma yuborilgan kungacha): HR qaytarsin, Moliya menejeri oy tugagach qayta yuborsin (shoshilinch bo''lsa — Direktor tasdiqlaydi): %s',
      cardinality(v_stale), array_to_string(v_stale, ', '));
    raise notice '%', m;
    v_msg := v_msg || m;
  end if;
  return jsonb_build_object('from', v_from, 'carry', to_jsonb(coalesce(v_carry, '{}')), 'stale', to_jsonb(v_stale), 'notice', to_jsonb(v_msg));
end $$;
revoke all on function app.payroll_deploy_notice() from public, anon, authenticated;
do $a5n$ begin perform app.payroll_deploy_notice(); end $a5n$;

notify pgrst, 'reload schema';
