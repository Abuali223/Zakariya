\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: sales-role.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- sales-role.sql — «SOTUVCHI» (marketing bo'limi) roli: faol o'quvchilar ota-onalarining FAQAT ismi va telefoni, o'zgartirishsiz
--   (egasi 2026-11-19: «ikkita sotuvchi olgandik … ota-onalarga aloqaga chiqib bizdagi muammolar haqida gaplashishadi va maktabni
--   boshqalarga tavsiya qilishini so'rashadi, buning uchun ota-onalar ismi va telefon raqamini o'zini ko'ra olishi kerak. Qolgan
--   ma'lumotlar ko'rinmasligi va o'zgartira olmasligi kerak»; SESSIYA-ISHLARI.md §85).
--
--   * Rol kaliti 'sales' (panelda «Sotuvchi»). Bu 'marketing_mgr' EMAS: Marketing menejeri — xodim darajasi (app.is_staff(), arizalar
--     tahriri, marketing statistikasi) — sotuvchiga ortiqcha. 'sales' HECH BIR mavjud ruxsat ro'yxatiga (app.is_staff, has_role / is_*
--     ro'yxatlari, RLS siyosatlari, kassa rollari) qo'shilmagan: jadvallarni RLS orqali farzandsiz ota-ona hisobidek ko'radi (o'quvchi,
--     xodim, moliya jadvallaridan — hech narsa; sinovi: test-sales-role.sql, «sizish» bandi). Qo'shimcha lavozim OLMAYDI (buxgalter kabi):
--     app.u_has, app.role_set va app.users_extra_roles_guard shu faylda qayta ta'riflangan — reports-roles.sql dagi bilan AYNAN bir xil +
--     'sales' (zanjirda oxirgi ta'rif amal qiladi; admin.html uHas / kirish ro'yxati / «➕ Lavozim» tugmasi ham shunday).
--   * Ma'lumot FAQAT uchta RPC orqali (jadvalga to'g'ridan-to'g'ri yo'l yo'q):
--       sales_contacts(q, limit, offset) — faol o'quvchilar OILALARI: aka-uka bitta oila (kartalar grafi: umumiy to'g'ri raqam + mos
--         ota yoki ona ismi, zid ism yo'q — app.sales_families); har oila: ota va ona — ism + NIQOBLANGAN telefon
--         («+998 00 *** ** 67»; xorij / noto'g'ri raqam — faqat oxirgi 2 raqam) + valid. Qidiruv — faqat ota / ona ismi bo'yicha (kamida
--         2 harf). O'quvchi ismi, ID, sinf, manzil va boshqa hech narsa qaytmaydi. Oila kaliti (k) — maxfiy tuz (app.sales_secret, mijozga
--         yopiq) bilan SHA-256: undan telefon ham, o'quvchi ID ham chiqmaydi.
--       sales_reveal(k) — shu oilaning to'liq raqamlari; har ochish jurnalga (public.sales_contact_log) yoziladi; bir foydalanuvchiga
--         kuniga 150 ta oila (Toshkent kuni). Shu oilani shu kuni qayta ochish chegaradan qayta yemaydi.
--       sales_log(days) — faqat Direktor: kim qaysi kuni nechta oila ochgani va oxirgi 200 ochish (ism, ota-ona ismi, vaqt — telefonsiz).
--     Ruxsat: FAOL 'sales' hisobi va Direktor (app.is_admin()); qolganlar (o'qituvchi, qabulxona, marketing menejeri, kassir, ota-ona,
--     anonim …) — 42501. Arxiv qoidasi — admin.html stuArchived bilan bir xil (holati «chiqdi» va chiqqan kuni — exitAt, bo'lmasa stopFrom —
--     bugun yoki o'tgan, yoki sana yo'q). O'chirilgan o'quvchi students jadvalida yo'q (to'liq nusxasi deleted_records da) — ro'yxatga
--     tushmaydi. «Bugun» — app.fin_today() (jonli bazada — Toshkent bugungi kuni; sinov bazasida sinov soati).
--   * Ochilgan raqamlar ekrandagina: eksport, chop etish, CSV yo'q (admin.html renderSales). Direktor ham bo'limni ko'radi (jurnal bilan).
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Qo'shimcha lavozimsiz asosiy rollar: director, parent, student, accountant, sales va rolsiz (reports-roles.sql + 'sales').
create or replace function app.u_has(p_role text, p_extra jsonb, r text) returns boolean
language sql immutable set search_path = pg_catalog as $$
  select coalesce(p_role = r, false)
      or (coalesce(p_role, '') not in ('director', 'parent', 'student', 'accountant', 'sales', '') and r = any(app.extra_roles_allowed())
          and jsonb_typeof(p_extra) = 'array' and p_extra ? r)
$$;
create or replace function app.role_set() returns text[]
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((
    select case
             when coalesce(u.role, '') = '' then '{}'::text[]
             when u.role in ('director', 'parent', 'student', 'accountant', 'sales') then array[u.role]
             else array[u.role] || coalesce(array(
                    select distinct e from jsonb_array_elements_text(case when jsonb_typeof(u."extraRoles") = 'array' then u."extraRoles" else '[]'::jsonb end) e
                     where e = any(app.extra_roles_allowed()) and e <> u.role), '{}'::text[])
           end
      from public.users u
     where u.id = app.uid() and coalesce(nullif(u.status, ''), 'active') = 'active'), '{}'::text[])
$$;
do $$ declare f text; begin
  foreach f in array array['app.u_has(text, jsonb, text)', 'app.role_set()'] loop
    execute 'revoke all on function ' || f || ' from public';
    execute 'grant execute on function ' || f || ' to anon, authenticated, service_role';
  end loop;
end $$;
create or replace function app.users_extra_roles_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v jsonb; e text; v_out text[] := '{}'; v_changed boolean;
begin
  v_changed := case when tg_op = 'INSERT' then coalesce(new."extraRoles", '[]'::jsonb) <> '[]'::jsonb
                    else new."extraRoles" is distinct from old."extraRoles" end;
  if v_changed and not app.is_system() and not app.is_admin() then
    raise exception 'Qo''shimcha lavozimni faqat Direktor beradi' using errcode = '42501';
  end if;
  if v_changed and not app.is_system() and new.id = app.uid() then
    raise exception 'O''zingizga qo''shimcha lavozim berib bo''lmaydi' using errcode = '42501';
  end if;
  v := coalesce(new."extraRoles", '[]'::jsonb);
  if jsonb_typeof(v) <> 'array' then raise exception 'Qo''shimcha lavozimlar ro''yxat bo''lishi kerak' using errcode = '22023'; end if;
  if coalesce(new.status, '') = 'blocked' and not v_changed then return new; end if;
  if coalesce(new.role, '') in ('director', 'parent', 'student', 'accountant', 'sales', '') then
    if jsonb_array_length(v) > 0 then
      if v_changed then raise exception 'Bu asosiy rolga qo''shimcha lavozim berilmaydi' using errcode = '22023'; end if;
      new."extraRoles" := '[]'::jsonb;   -- asosiy rol o'zgardi (masalan, Sotuvchi bo'ldi) — qo'shimchalar bekor
    end if;
    return new;
  end if;
  for e in select x from jsonb_array_elements(v) x0, lateral (select x0 #>> '{}' as x) y loop
    if e is null or not (e = any(app.extra_roles_allowed())) then
      raise exception 'Qo''shimcha lavozim sifatida berib bo''lmaydi: %', coalesce(e, 'null') using errcode = '22023';
    end if;
    if e <> new.role and not (e = any(v_out)) then v_out := v_out || e; end if;
  end loop;
  new."extraRoles" := to_jsonb(v_out);
  return new;
end $$;
revoke all on function app.users_extra_roles_guard() from public, anon, authenticated;
-- Sotuvchi qo'shimcha lavozimsiz: oldin berilgan bo'lsa — bir martalik tozalash (zanjir — tizim nomidan; idempotent).
update public.users set "extraRoles" = '[]'::jsonb
 where role = 'sales' and coalesce("extraRoles", '[]'::jsonb) <> '[]'::jsonb;

-- 2) Oila kaliti uchun maxfiy tuz (bir marta yaratiladi, qayta ishga tushirishda o'zgarmaydi — kalitlar barqaror). Mijozga yopiq.
create table if not exists app.sales_secret (id int primary key default 1 check (id = 1), salt text not null);
alter table app.sales_secret enable row level security;
revoke all on table app.sales_secret from public, anon, authenticated;
insert into app.sales_secret (id, salt)
  values (1, replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
  on conflict (id) do nothing;

-- 3) Ochishlar jurnali. RLS yoqilgan, mijoz rollariga hech qanday huquq va siyosat yo'q — faqat RPC'lar (SECURITY DEFINER) yozadi / o'qiydi.
--    fkey — oila kaliti (yuqoridagi xesh; telefon ham, o'quvchi ID ham emas); day — Toshkent kuni (kunlik chegara shu bo'yicha).
create table if not exists public.sales_contact_log (
  id          bigserial primary key,
  uid         text not null,
  fkey        text not null,
  day         date not null,
  "createdAt" timestamptz not null default now(),
  constraint sales_contact_log_uid_fkey_day_key unique (uid, fkey, day)
);
-- actorName — ochgan xodimning OCHISH PAYTIDAGI nomi: jurnal o'tgan ochishlarni keyin hisob nomi o'zgarsa (rol almashib o'zi o'zgartirsa)
--   yoki hisob o'chirilib qayta yaratilsa ham o'sha nom bilan ko'rsatadi (mustaqil tekshiruv).
alter table public.sales_contact_log add column if not exists "actorName" text;
create index if not exists sales_contact_log_day_idx on public.sales_contact_log (day, uid);
create index if not exists sales_contact_log_created_idx on public.sales_contact_log ("createdAt" desc);
alter table public.sales_contact_log enable row level security;
revoke all on table public.sales_contact_log from public, anon, authenticated;
grant all on table public.sales_contact_log to service_role;
revoke all on sequence public.sales_contact_log_id_seq from public, anon, authenticated;
grant usage, select on sequence public.sales_contact_log_id_seq to service_role;

-- 4) Ichki yordamchilar (faqat quyidagi RPC'lar ichida; mijozga yopiq).
create or replace function app.sales_cap() returns int
language sql immutable set search_path = pg_catalog as $$ select 150 $$;
-- Ruxsat: tizimga kirgan va (faol 'sales' yoki Direktor). Aks holda 42501.
create or replace function app.sales_need() returns void
language plpgsql stable set search_path = public, app, pg_temp as $$
begin
  if app.uid() is null then raise exception 'Tizimga kiring' using errcode = '42501'; end if;
  if not (app.is_admin() or 'sales' = any(app.role_set())) then
    raise exception 'Ruxsat yo''q: bu bo''lim faqat sotuvchi (marketing) va Direktor uchun' using errcode = '42501';
  end if;
end $$;
-- Ism qidiruvi uchun: kichik harf, apostroflarsiz («Sa'dullayev» = «Saʼdullayev» = «Sadullayev»). Kirill katta harflari — aniq jadval
--   bilan (lower() C-ctype bazada faqat lotinni kichraytiradi; mustaqil tekshiruv).
create or replace function app.sales_norm(p text) returns text
language sql immutable set search_path = pg_catalog as $$
  select regexp_replace(lower(translate(coalesce(p, ''), 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ', 'абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳ')),
                        '[''`´‘’ʻʼ]', '', 'g')
$$;
-- Harf bormi (ism yozilganmi): lotin (kengaytmalari bilan), kirill (o'zbek / tojik / qozoq harflari), yunon, arman, ivrit, arab, gruzin,
--   yapon, xitoy, koreys. «-», «—», «0», «.», «?», «№», ««»», bo'sh joy — ism EMAS (registrator to'ldiruvchisi; aks holda bir xil
--   «-» ismli begona oilalar maktab raqami orqali bitta qatorga qo'shilib, qolganlari ro'yxatdan yo'qolardi — mustaqil tekshiruv).
--   Diapazonlar — kod nuqtasi bo'yicha (C, C.UTF-8 va ICU collation'larida bir xil; UTF8 baza).
--   SET search_path YO'Q (app.rls_in o'ramlari kabi): Postgres uni chaqiruvchi so'rov ichiga joylaydi — har so'z / karta uchun funksiya
--   chaqiruvi bo'lmaydi (oilalar ro'yxati tezligi); tanada faqat pg_catalog operatori, SECURITY DEFINER emas.
create or replace function app.sales_hasletter(p text) returns boolean
language sql immutable as $$
  select coalesce(p, '') ~ '[A-Za-zÀ-ÖØ-öø-ɏͰ-ϿЀ-ҁҊ-ԯԱ-Ֆա-ևא-תؠ-يႠ-ჿぁ-ヿ一-鿿가-힣]'
$$;
-- Ism kaliti (oilani bog'lash uchun): normallashgan so'zlar — takrorsiz, alifbo tartibida («Karimov Akmal» = «Akmal Karimov»); harfsiz
--   so'z (raqam, tinish belgisi) hisobga olinmaydi («Akmal -» = «Akmal»; «-» — kalitsiz, ya'ni ism yozilmagan). Ism o'rniga yoziladigan
--   so'zlar («yo'q», «Нет», «noma'lum», «vafot etgan», «ajrashgan», «ma'lumot yo'q» …) ham — kalitsiz: aks holda shunday yozilgan begona
--   oilalar umumiy (maktab) raqami orqali bitta qatorga qo'shilib, qolganlarining raqami yo'qolardi (mustaqil tekshiruv). Kalit tozalangan
--   ismdan (app.sales_pname) olinadi — sales_families.
create or replace function app.sales_nkey(p text) returns text
language sql immutable set search_path = pg_catalog as $$
  select coalesce((select string_agg(x.t, ' ' order by x.t)
                     from (select distinct w as t from regexp_split_to_table(app.sales_norm(p), '\s+') w
                            where app.sales_hasletter(w)
                              and w not in ('yoq', 'yok', 'yuq', 'йук', 'йўқ', 'йок', 'нет', 'нету', 'nomalum', 'номаълум', 'номалум', 'неизвестно',
                                            'otasi', 'onasi', 'отаси', 'онаси', 'vafot', 'etgan', 'вафот', 'этган', 'olgan', 'ўлган', 'marhum', 'марҳум',
                                            'умер', 'умерла', 'ajrashgan', 'ажрашган', 'mavjud', 'мавжуд', 'emas', 'эмас', 'malumot', 'маълумот',
                                            'aniq', 'аниқ', 'указано', 'данных')) x), '')
$$;
-- To'g'ri raqam: O'zbekiston (998 + 9 raqam) yoki boshqa mamlakat (10–15 raqam, E.164). Aks holda (bir katakda ikki raqam, qisqa,
--   aralash matn) — noto'g'ri: «+» va tel: havolasiz ko'rsatiladi (mustaqil tekshiruv).
create or replace function app.sales_valid(p text) returns boolean
language sql immutable set search_path = pg_catalog as $$
  select coalesce(p, '') ~ '^998[0-9]{9}$' or (coalesce(p, '') ~ '^[1-9][0-9]{9,14}$' and left(p, 3) <> '998')
$$;
-- Katak yozuvini o'qiydigan yordamchilar (sales_intl_ok, sales_cc, sales_dialable, sales_part_ok, sales_nums, sales_usable) — plpgsql:
--   ichma-ich chaqirilgan SQL funksiya har tashqi chaqiruvda qayta rejalashtirilib, oilalar ro'yxatini bir necha baravar sekinlashtirardi
--   (plpgsql rejani keshlaydi).
-- Xorijiy raqam (kanonik, «+» / 00 bilan yozilgan) qo'ng'iroq qilib bo'ladimi — sahifaning phoneCanon qoidasi bilan AYNAN bir xil: davlat
--   kodi (eng uzuni: 3 -> 2 -> 1 raqam) ma'lum va jami uzunlik shu davlatniki (PHONE_LEN; ro'yxatda yo'q davlat — 10–15 raqam). Jadvallar
--   admin.html PHONE_CC / PHONE_LEN bilan bir xil (assets/js/sales.test.mjs solishtiradi). Aks holda katakdagi raqamning kesilgan bo'lagi
--   («+44 7700 9001  21» dagi «+44 7700 9001») yoki noto'g'ri uzunlikdagi raqam «qo'ng'iroq qilib bo'ladigan» bo'lib chiqardi (mustaqil tekshiruv).
create or replace function app.sales_intl_ok(d text) returns boolean
language plpgsql immutable set search_path = pg_catalog as $$
declare cc text; lens jsonb;
begin
  if coalesce(d, '') !~ '^[1-9][0-9]{6,14}$' then return false; end if;
  cc := case when left(d, 3) = any('{211,212,213,216,218,220,221,222,223,224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,245,248,249,250,251,252,253,254,255,256,257,258,260,261,262,263,264,265,266,267,268,269,290,291,297,298,299,350,351,352,353,354,355,356,357,358,359,370,371,372,373,374,375,376,377,378,380,381,382,383,385,386,387,389,420,421,423,500,501,502,503,504,505,506,507,508,509,590,591,592,593,594,595,596,597,598,599,670,672,673,674,675,676,677,678,679,680,681,682,683,685,686,687,688,689,690,691,692,850,852,853,855,856,880,886,960,961,962,963,964,965,966,967,968,970,971,972,973,974,975,976,977,992,993,994,995,996,998}'::text[]) then left(d, 3)
             when left(d, 2) = any('{20,27,30,31,32,33,34,36,39,40,41,43,44,45,46,47,48,49,51,52,53,54,55,56,57,58,60,61,62,63,64,65,66,81,82,84,86,90,91,92,93,94,95,98}'::text[]) then left(d, 2)
             when left(d, 1) = any('{1,7}'::text[]) then left(d, 1) end;
  if cc is null then return false; end if;
  lens := '{"1":[11],"7":[11],"20":[12],"33":[11],"34":[11],"39":[11,12],"44":[12],"48":[11],"49":[12,13],"61":[11],"81":[12],"82":[11,12],"86":[13],"90":[12],"91":[12],"92":[12],"370":[11],"371":[11],"372":[10,11],"373":[11],"374":[11],"375":[12],"380":[12],"420":[12],"421":[12],"965":[11],"966":[12],"971":[12],"972":[12],"974":[11],"992":[12],"993":[11],"994":[12],"995":[12],"996":[12],"998":[12]}'::jsonb -> cc;
  return case when lens is not null then lens @> to_jsonb(length(d)) else length(d) >= 10 end;
end $$;
-- Kanonik raqamning davlat kodi (eng uzuni: 3 -> 2 -> 1 raqam) yoki NULL — app.sales_intl_ok jadvali bilan AYNAN bir xil
--   (assets/js/sales.test.mjs solishtiradi). 8-qoida birlashtirishida yozilgan kod o'qilgan raqamning davlat kodi bilan solishtiriladi
--   (app.sales_nums).
create or replace function app.sales_cc(d text) returns text
language plpgsql immutable set search_path = pg_catalog as $$
begin
  return case when left(d, 3) = any('{211,212,213,216,218,220,221,222,223,224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,245,248,249,250,251,252,253,254,255,256,257,258,260,261,262,263,264,265,266,267,268,269,290,291,297,298,299,350,351,352,353,354,355,356,357,358,359,370,371,372,373,374,375,376,377,378,380,381,382,383,385,386,387,389,420,421,423,500,501,502,503,504,505,506,507,508,509,590,591,592,593,594,595,596,597,598,599,670,672,673,674,675,676,677,678,679,680,681,682,683,685,686,687,688,689,690,691,692,850,852,853,855,856,880,886,960,961,962,963,964,965,966,967,968,970,971,972,973,974,975,976,977,992,993,994,995,996,998}'::text[]) then left(d, 3)
              when left(d, 2) = any('{20,27,30,31,32,33,34,36,39,40,41,43,44,45,46,47,48,49,51,52,53,54,55,56,57,58,60,61,62,63,64,65,66,81,82,84,86,90,91,92,93,94,95,98}'::text[]) then left(d, 2)
              when left(d, 1) = any('{1,7}'::text[]) then left(d, 1) end;
end $$;
-- Qo'ng'iroq qilib bo'ladigan BITTA yozuv (katak yoki uning bir qismi) — sahifaning salesPartDigits + salesDialable qoidasi: kanonik shakli
--   (app.tg_phone — «+» / 00 / 9 xonali mahalliy raqam qoidasi) O'zbekiston raqami (998 + 9 raqam) yoki «+» / 00 bilan yozilgan, davlat kodi
--   va uzunligi to'g'ri xorijiy raqam (app.sales_intl_ok). «+»siz 10–15 raqam (JSHSHIR, karta raqami bo'lagi, yopishib qolgan raqamlar) —
--   telefon EMAS (mustaqil tekshiruv).
create or replace function app.sales_dialable(p text) returns boolean
language plpgsql immutable set search_path = pg_catalog as $$
declare c text := app.tg_phone(p);
begin
  if c ~ '^998[0-9]{9}$' then return true; end if;
  if left(c, 3) = '998' then return false; end if;
  if btrim(coalesce(p, '')) ~ '^[^0-9]*\+' or regexp_replace(coalesce(p, ''), '\D', '', 'g') like '00%' then return app.sales_intl_ok(c); end if;
  return false;
end $$;
-- Katakdagi bitta raqam yozuvi (bo'lakcha) raqam sifatida o'qiladimi: qo'ng'iroq qilib bo'ladigan (app.sales_dialable) va — «+» / 00 siz,
--   9 xonali, bir necha guruhda yozilgan bo'lsa — birinchi guruhi 2 xonali (operator kodi: «01 234 56 78», «(01) 234-56-78», «01 2345678»)
--   yoki 3 xonali («012 345 678»), lekin oxiri «000» emas (summa: «120 000 000», «150.500.000»): «1234567 15» (pasport + uy), «0671712 12»
--   (shahar raqami + kvartira), «120 000 000 so'm» — telefon emas, bitta 9 xonali «O'zbekiston raqami» bo'lib o'qilmaydi (mustaqil
--   tekshiruv); 3 xonali birinchi guruh «998» ham operator kodi emas: «998 001 234⏎567» dagi birinchi qator — 998 kodi va 6 raqam (chala
--   yoki qatorga bo'lingan xalqaro raqam), 9 xonali mahalliy raqam bo'lib begona havola bermaydi (butun bo'lak to'liq bo'lsa — o'sha
--   raqam; 10-mustaqil tekshiruv, 2-o'tish). «+» / 00 bilan yozilgan xorijiy kanonik raqam (998 emas) esa o'qilmaydi, agar:
--   «+» dan keyingi birinchi guruh «0» va raqam bilan boshlansa (mahalliy operator kodi «02», «012»; davlat kodi noldan boshlanmaydi —
--   faqat «+0998 …» xatosi O'zbekiston raqami):
--   «01 234 56 78 + 02 345 67 89 (15)» dagi «+ 02 345 67 89 15» nol tashlanib begona «+234 …» bo'lmaydi; yoki kanonigi 1–3 raqam
--   va to'liq O'zbekiston raqami (998 + 9 raqam) bilan boshlansa (oxirida izoh raqami bo'lsa ham): «+2 998 00 765 43 21»,
--   «+2 998 00 765 43 21 (15)» — tasodifiy raqam yopishgan O'zbekiston raqami, ro'yxatda yo'q davlat kodi (10–15 raqam) bilan begona
--   «+299 …» bo'lib o'qilmaydi (mustaqil tekshiruv; PHONE_LEN dagi davlatlar raqami 13 xonadan oshmaydi, ya'ni ular o'zgarmaydi).
--   Oilalar ro'yxatining tezkor yo'li (sales_families, rawok) ham shu funksiyani chaqiradi.
create or replace function app.sales_part_ok(p text) returns boolean
language plpgsql immutable set search_path = pg_catalog as $$
declare d text; c text;
begin
  if not app.sales_dialable(p) then return false; end if;
  d := regexp_replace(coalesce(p, ''), '\D', '', 'g');
  if coalesce(p, '') ~ '^[^0-9]*\+' or d like '00%' then
    -- kanonik raqam — app.tg_phone bilan aynan bir xil («+» / 00 yozuvi: boshidagi nollarsiz raqamlar), qayta chaqiruvsiz (tezlik)
    c := ltrim(d, '0');
    return c ~ '^998' or (c !~ '^[1-9][0-9]{0,2}998[0-9]{9}' and p !~ '^[^0-9]*\+[^0-9]*0[1-9]');
  end if;
  if length(d) <> 9 then return true; end if;
  return p !~ '[0-9][^0-9]+[0-9]' or p ~ '^[^0-9]*[0-9]{2}([^0-9]|$)' or (p ~ '^[^0-9]*[0-9]{3}([^0-9]|$)' and d !~ '000$' and d !~ '^998');
end $$;
-- Katakdagi qo'ng'iroq qilib bo'ladigan raqamlar — yozilganidek (bo'sh joylar bittaga keltirilgan), katakdagi tartibda. Qoidalar:
--   1) birinchi 100 belgi; 100-belgi biror bo'lak (pastda, 6) o'rtasiga tushsa — shu bo'lak oxirigacha, ya'ni keyingi qat'iy chegaragacha
--      («,;/|» yoki harfli so'z; ko'pi bilan yana 100 belgi) o'qiladi, chegaradan keyingisi — yo'q; chegara topilmasa — kesilgan bo'lakning
--      oxirgi bo'lakchasi (7) o'qilmaydi, qolgan bo'lakchalari faqat alohida: kesilgan raqam («… +44 7700 900123|4») boshqa raqam bo'lib
--      o'qilmasin (mustaqil tekshiruv), qator-qator yozilgan raqamlar esa yo'qolmasin;
--   2) qator uzilishi / TAB / VT / FF (Excel'da Alt+Enter), Unicode qator va xatboshi ajratuvchisi — ikki bo'sh joy, ya'ni «yumshoq» ajratuvchi;
--      ko'rinadigan Unicode bo'sh joylar (NBSP, ingichka bo'sh joy …) — oddiy bo'sh joy (Excel / Word'dan nusxalangan katak); ko'rinmas
--      (eni nol) belgi — bo'sh joy emas: katak qanday ko'rinsa, shunday o'qiladi;
--   3) harfdan keyin «:» «.» «=» — bo'sh joy («tel:+998…», «тел.998…» -> «tel +998…»);
--   4) «+» doim yangi raqam boshlaydi: oldidagi belgi (raqam va «,;/|» dan boshqasi) bilan orasiga yumshoq ajratuvchi (ikki bo'sh joy)
--      qo'yiladi («tel+44 …», «ota-+44 …» -> «+44 …»; «01 234 56 78 +44 7700 900123» — ikki raqam), aks holda «+» harfli so'z bilan birga
--      tashlanib, qolgan 9 raqam O'zbekiston raqamidek o'qilardi (mustaqil tekshiruv);
--   5) harfli so'z (izoh «otasi», «kv», «ichki»; pasport «AA1234567», «2-uy», «15-уй») — «,» bilan almashtiriladi, ya'ni qat'iy ajratuvchi:
--      uning ikki tomonidagi raqamlar hech qachon qo'shilmaydi («0123456 kv 12», «ish: 123-45-67 (ichki 12)» -> raqam yo'q; so'z chegarasi —
--      bo'sh joy va «,;/|»);
--   6) «,» «;» «/» «|» — qat'iy ajratuvchi: bo'laklar hech qachon qo'shilmaydi («pasport AA 1234567, 15» -> raqam yo'q);
--   7) bo'lak ichida ikki va undan ortiq bo'sh joy — yumshoq ajratuvchi: bo'lakchalardan biri qo'ng'iroq qilib bo'ladigan bo'lsa — faqat shunday
--      bo'lakchalar («+998 … 07⏎+998 … 08», «+44 7700 900121  2»); aks holda — butun bo'lak (raqam ichida tasodifiy ikki bo'sh joy yoki
--      qator uzilishi: «+998 00 123  45 67 (otasi)», «+44 7700 9001  21», «01 234  56 78»), faqat: uning birinchi va oxirgi raqami orasida
--      raqam, «+», qavs, nuqta, chiziqcha va bo'sh joydan boshqa belgi yo'q («12 — 01 234 56», «12 № 01 234 56» — qo'shilmaydi) va bo'lak «+»
--      bilan boshlangan (to'liq yozilgan raqam) yoki hech bir raqam guruhi 4 xonadan uzun emas (telefon guruhlari) — bir-biriga aloqasi yo'q
--      guruhlar («15  0123456» — uy va shahar raqami) bitta 9 xonali «O'zbekiston raqami» bo'lib qo'shilmaydi (mustaqil tekshiruv);
--      keyingi bo'lakchalardan biri «+» bilan boshlansa (4-qoida: yangi raqam; yolg'iz davlat kodidan keyingisi — «+998 + 02-111-22-33»
--      — bundan mustasno; «+»siz yozilgan 998 kodidan keyingisi faqat 998 birinchi bo'lakcha, bo'lakda bitta «+» va jami 12 raqam
--      bo'lsa — «998 +00 123 45 67», «(998) +01 234 56 78») — butun bo'lak ham qo'shilmaydi: kesilgan raqam va «+7»
--      («+998 00 123 45 6⏎+7», «+998 00 123 45 6 +1», «998 +00 12 34») begona valid=true raqam bo'lib o'qilmaydi (mustaqil tekshiruv);
--   8) yolg'iz davlat kodi («+999», «00 999») va undan keyin (yumshoq ajratuvchi bilan) «+»siz bo'lakcha — bitta bo'lakcha, ya'ni bitta
--      xalqaro raqam: bo'lakcha alohida O'zbekiston raqami bo'lib o'qilmaydi («+999  01 234 56 78» -> +999 012345678, kodi noma'lum — raqam
--      yo'q); katakda boshqa raqam bo'lsa ham, kod va raqam orasida «:» / «—» bo'lsa ham, kod «00» bilan yozilgan bo'lsa ham — o'sha raqam
--      («+998⏎01 234 56 78⏎+998⏎01 234 56 79» — ikki raqam, «00998⏎012345678», «+998:⏎01 234 56 78», «0044  7700900123»; avval kod
--      bo'lakchasi tashlanib, raqam yo'qolardi — mustaqil tekshiruv); «00» bilan boshlangan yoki o'zi to'liq O'zbekiston raqami (998 + 9
--      raqam) bo'lgan bo'lakcha qo'shilmaydi — alohida o'qiladi («+2⏎998 00 765 43 21» -> 998 00 765 43 21, begona +299 … emas);
--      qo'shilgan bo'lakcha keyingisiga yana qo'shilmaydi («+4. 4) — 7700 900123» -> raqam yo'q); qo'shilgan raqamning davlat kodi
--      (app.sales_cc) yozilgan kod yoki kod va bo'lakchaning birinchi raqam guruhi («+99⏎8 00 …», «+4. 4) - 7700 …»; bo'lakcha o'zi
--      to'liq 9 xonali mahalliy raqam bo'lsa yoki «0» bilan boshlansa — faqat yozilgan kod) bo'lishi shart (nollardan iborat kod — «+0»,
--      «000» — xalqaro prefiks, tekshirilmaydi): aks holda o'sha bo'lakcha ham, butun bo'lak ham o'qilmaydi —
--      tasodifiy «+10» / «+3» / «+440» mahalliy raqamga qo'shilib boshqa davlat raqami bo'lmaydi («+10 — 01 234 56 78» -> +1 001 …,
--      «+3⏎01 234 56 78» -> +30 … emas; mustaqil tekshiruv); butun bo'lak faqat to'liq O'zbekiston raqami (998 + 9 raqam, 998998
--      emas) bo'lsa baribir o'qiladi — barcha raqamlari yozilgan tartibda, boshqa davlat raqami bo'lib chiqmaydi: raqam o'rtasidagi
--      «00X» guruhi davlat kodi emas («01  003  45  67», «+998⏎00 476⏎47 55» -> o'sha raqam), bo'lingan 998 kodi («+99⏎8001234567»;
--      10-mustaqil tekshiruv, 2-o'tish: avval niqoblanardi); bo'lak boshidagi yolg'iz koddan keyingi «00» bilan boshlangan bo'lakcha
--      (unga qo'shilmaydi) butun bo'lak bo'lib ham faqat yozilgan kod bilan o'qiladi («+998⏎00 123 45 67» -> +998 00 …;
--      «+4⏎00 123 45 67», «+10⏎00 …» -> raqam yo'q, begona +40 … / +1 000 … emas — 10-mustaqil tekshiruv, 2-o'tish);
--   9) «+» / 00 siz, 9 xonali, bir necha guruhda yozilgan bo'lakcha — birinchi guruhi 2 xonali (operator kodi) yoki 3 xonali (oxiri «000»
--      emas) bo'lsagina raqam (app.sales_part_ok): «pasport AA 1234567 15 uy», «0671712 12», «120 000 000 so'm» — raqam emas.
--   Ma'lum chegara: operator kodidek 2–3 xonali guruh bilan boshlanib, bitta bo'sh joy bilan yozilgan raqamlar («15 0123456» — uy va
--   shahar raqami) bitta 9 xonali raqamdek o'qiladi (operator kodi tekshirilmaydi); «00» bilan boshlangan yozuv — xalqaro raqam (davlat
--   kodi va uzunligi tekshiriladi, ro'yxatda yo'q davlat — 10–15 raqam); bitta bo'sh joy bilan yopishgan ikki raqam (ikkinchisi
--   «+»siz) — ajratilmaydi (qo'ng'iroq qilib bo'lmaydi, niqob); harfga yopishgan raqam («tel998…», «tel00…») — so'z bilan birga tashlanadi;
--   «+» doim xalqaro raqam boshlaydi: undan keyingi raqamlar to'g'ri xorijiy raqam bo'lsa, boshqa raqamdan keyin bo'lsa ham shunday o'qiladi
--   («01 234 56 78 + 44 7700 900123» -> +44 7700 900123, yozilganidek); yolg'iz davlat kodi va «+» bilan boshlangan bo'lakcha birga o'qilishi
--   mumkin («+44⏎+7700 900123» -> +44 7700 900123); xorijiy raqam ichida ikki bo'sh joy / qator uzilishi bilan ajratilgan «00X» guruhi
--   («+44 7700 9  003  21») — niqob (raqam o'qilmaydi, begona havola ham yo'q); «+» bilan boshlangan bo'lakda qavs ichidagi guruh ham
--   raqamning davomi (7-qoida: «+44 7700 9001  (23)» -> +44 7700 900123, uzunligi to'g'ri bo'lsa); kod bir necha bo'lakchaga bo'lingan
--   bo'lsa («+9⏎9⏎8 00 …») — bo'lakchalar raqamlari birga bitta xalqaro raqam: tasodifiy kod va yolg'iz «0» bo'lakchasidan keyingi
--   raqam ham shunday o'qilishi mumkin.
create or replace function app.sales_nums(p text) returns text[]
language plpgsql immutable set search_path = pg_catalog as $$
declare
  s text := coalesce(p, '');
  cut boolean := length(coalesce(p, '')) > 100;
  items text[]; parts text[]; item text; part text; prev text; dps text[]; dds boolean[]; anyd boolean; pure boolean; d boolean;
  tail boolean; plus2 boolean; lone boolean; nojoin boolean; cd text; fg text; i int; k int; res text[] := '{}';
begin
  -- Oddiy yozuv (100 belgigacha, faqat raqam / qavs / chiziqcha / bitta bo'sh joylar, boshida «+» bo'lishi mumkin) — bitta bo'lak, bitta
  --   bo'lakcha: pastdagi to'liq yo'l ham aynan shu natijani beradi (eng ko'p uchraydigan yozuvlar uchun tezlik).
  if length(s) <= 100 and s ~ '^[+]?[0-9() -]*$' and strpos(s, '  ') = 0 then
    if s ~ '[0-9]' and app.sales_part_ok(s) then
      return array[btrim(regexp_replace(regexp_replace(s, '[()]', ' ', 'g'), '\s+', ' ', 'g'), ' -')];
    end if;
    return res;
  end if;
  if cut then
    s := left(s, 100) || coalesce(substring(substr(s, 101, 100)
           from '^[^,;/|A-Za-zÀ-ÖØ-öø-ɏͰ-ϿЀ-ҁҊ-ԯԱ-Ֆա-ևא-תؠ-يႠ-ჿぁ-ヿ一-鿿가-힣]*(?:[,;/|]|[A-Za-zÀ-ÖØ-öø-ɏͰ-ϿЀ-ҁҊ-ԯԱ-Ֆա-ևא-תؠ-يႠ-ჿぁ-ヿ一-鿿가-힣][^\s,;/|]*)'), '');
  end if;
  if s !~ '[0-9]' then return res; end if;
  -- (faqat ASCII belgili katakda — Unicode almashtirishlar kerak emas: tezlik)
  if octet_length(s) = length(s) then
    s := regexp_replace(s, '[\r\n\t\v\f]', '  ', 'g');
  else
    s := regexp_replace(s, '[\r\n\t\v\f\u0085\u2028\u2029]', '  ', 'g');
    s := regexp_replace(s, '[\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]', ' ', 'g');
  end if;
  s := regexp_replace(s, '([A-Za-zÀ-ÖØ-öø-ɏͰ-ϿЀ-ҁҊ-ԯԱ-Ֆա-ևא-תؠ-يႠ-ჿぁ-ヿ一-鿿가-힣])[:.=]', '\1 ', 'g');
  s := regexp_replace(s, '([^0-9+,;/|])[+]', '\1  +', 'g');
  s := regexp_replace(s, '[^\s,;/|]*[A-Za-zÀ-ÖØ-öø-ɏͰ-ϿЀ-ҁҊ-ԯԱ-Ֆա-ևא-תؠ-يႠ-ჿぁ-ヿ一-鿿가-힣][^\s,;/|]*', ',', 'g');
  items := regexp_split_to_array(s, '[,;/|]');
  for k in 1 .. cardinality(items) loop
    item := items[k];
    continue when item !~ '[0-9]';
    -- 100 belgidan uzun katakning oxirgi bo'lagi (chegaradan keyingi yoki chegara topilmagan qism) kesilgan bo'lishi mumkin: uning oxirgi
    --   bo'lakchasi o'qilmaydi, qolganlari — faqat alohida (butun bo'lak qo'shilmaydi): qator-qator yozilgan raqamlar yo'qolmaydi
    tail := cut and k = cardinality(items);
    pure := regexp_replace(item, '^[^0-9+(]+|[^0-9)]+$', '', 'g') ~ '^[0-9+()\s.-]*$';
    item := regexp_replace(item, '[^0-9+ ()-]', ' ', 'g');
    parts := regexp_split_to_array(item, '\s{2,}');
    if tail then parts := parts[1 : cardinality(parts) - 1]; end if;
    dps := '{}'; dds := '{}'; anyd := false; prev := ''; plus2 := false; nojoin := false;
    foreach part in array parts loop
      continue when part !~ '[0-9]';
      -- oldingi bo'lakcha — yolg'iz davlat kodi («+999», «00 44», «(+998)»)
      lone := prev <> '' and regexp_replace(prev, '[\s()-]', '', 'g') ~ '^(\+|00)[0-9]{1,3}$';
      cd := '';
      if lone and part !~ '^[^0-9]*\+' and regexp_replace(part, '\D', '', 'g') !~ '^(00|998[0-9]{9}$)' then
        -- 8-qoida: yolg'iz davlat kodi + «+»siz bo'lakcha — bitta bo'lakcha (kod yozuvi o'rniga); keyingisiga yana qo'shilmaydi.
        --   cd — yozilgan kod (xalqaro prefiks nollarisiz), fg — bo'lakchaning birinchi raqam guruhi (bo'lingan kod: «+99⏎8 00 …»);
        --   bo'lakcha o'zi to'liq 9 xonali mahalliy raqam bo'lsa yoki «0» bilan boshlansa — faqat yozilgan kod (tasodifiy «+5» va «02 …» ->
        --   3 xonali kod emas, «+4» va «0 12 …» -> 40 emas)
        cd := ltrim(regexp_replace(prev, '\D', '', 'g'), '0');
        fg := case when length(regexp_replace(part, '\D', '', 'g')) = 9 or part ~ '^[^0-9]*0' then '' else substring(part from '[0-9]+') end;
        part := prev || ' ' || part;
        dps := dps[1 : cardinality(dps) - 1]; dds := dds[1 : cardinality(dds) - 1];
        prev := '';
      else
        -- 4-qoida: «+» bilan boshlangan keyingi bo'lakcha (yolg'iz davlat kodidan keyin emas) — yangi raqam: butun bo'lak qo'shilmaydi;
        --   faqat «+»siz 998 kodi bo'lakning birinchi bo'lakchasi, bo'lakda bitta «+» va jami 12 raqam (998 + 9) bo'lsa — qo'shiladi
        --   («998 +00 123 45 67»; «998 +00 12 34» — kesilgan raqam, oldiga yana 998 qo'shilib begona raqam bo'lmaydi)
        plus2 := plus2 or (cardinality(dps) > 0 and not lone and part ~ '^[^0-9]*\+'
                           and not (cardinality(dps) = 1 and regexp_replace(prev, '\D', '', 'g') = '998' and item !~ '\+.*\+'
                                    and length(regexp_replace(item, '\D', '', 'g')) = 12));
        -- 8-qoida: bo'lak boshidagi (oldida faqat nolli bo'lakchalar) yolg'iz koddan keyingi «00» bilan boshlangan bo'lakcha («+00 …»
        --   ham) qo'shilmadi — butun bo'lak bo'lib o'qilsa, uning davlat kodi yozilgan kod bo'lishi shart, aks holda butun bo'lak o'qilmaydi
        --   («+4⏎00 123 45 67», «+4⏎+00 123 45 67» -> begona +40 … emas; «+998⏎00 123 45 67» — o'qiladi)
        if lone and regexp_replace(part, '\D', '', 'g') ~ '^00'
           and array_to_string(dps[1 : cardinality(dps) - 1], '') !~ '[1-9]' and ltrim(regexp_replace(prev, '\D', '', 'g'), '0') <> ''
           and app.sales_cc(app.tg_phone(item)) is distinct from ltrim(regexp_replace(prev, '\D', '', 'g'), '0') then
          nojoin := true;
        end if;
        prev := part;
      end if;
      d := app.sales_part_ok(part);
      -- 8-qoida: qo'shilgan raqamning davlat kodi ma'lum, lekin yozilgan kod emas — bo'lakcha ham, butun bo'lak ham o'qilmaydi;
      --   butun bo'lak faqat to'liq O'zbekiston raqami (998 + 9 raqam, 998998 emas) bo'lsa o'qiladi — barcha raqamlari yozilgan tartibda:
      --   raqam o'rtasidagi «00X» guruhi («01  003  45  67») davlat kodi emas, «+99⏎8001234567» — bo'lingan 998 kodi
      if cd <> '' and app.sales_cc(app.tg_phone(part)) not in (cd, cd || fg) then
        d := false;
        nojoin := nojoin or app.tg_phone(item) !~ '^998[0-9]{9}$' or app.tg_phone(item) ~ '^998998';
      end if;
      dps := dps || part; dds := dds || d; anyd := anyd or d;
    end loop;
    if (cardinality(dps) >= 2 or tail) and anyd then
      for i in 1 .. cardinality(dps) loop
        if dds[i] then res := res || btrim(regexp_replace(regexp_replace(dps[i], '[()]', ' ', 'g'), '\s+', ' ', 'g'), ' -'); end if;
      end loop;
    elsif not tail and not nojoin and (cardinality(dps) = 1 or (pure and not plus2 and (item ~ '^[^0-9]*\+' or item !~ '[0-9]{5}')))
          and app.sales_part_ok(item) then
      res := res || btrim(regexp_replace(regexp_replace(item, '[()]', ' ', 'g'), '\s+', ' ', 'g'), ' -');
    end if;
  end loop;
  return res;
end $$;
-- Katakdan foydalanib bo'ladimi (oila raqamini tanlash darajalari — fok / mok): katakda kamida bitta qo'ng'iroq qilib bo'ladigan raqam
--   (ochilganda sales_parent aynan shularni ko'rsatadi). Karta raqami, JSHSHIR, bitta bo'sh joy bilan yopishgan ikki raqam, izoh raqami bilan
--   qo'shilgan raqam — yo'q (boshqa kartadagi to'g'ri raqamni yashirmasin).
create or replace function app.sales_usable(p_raw text) returns boolean
language plpgsql immutable set search_path = pg_catalog as $$
begin
  return cardinality(app.sales_nums(p_raw)) > 0;
end $$;
-- Eski yordamchilar (5-mustaqil tekshiruvgacha) — o'rniga app.sales_nums.
drop function if exists app.sales_whole(text);
drop function if exists app.sales_segs(text);
-- Niqob (kanonik raqamdan): O'zbekiston 998001234567 -> «+998 00 *** ** 67»; boshqa mamlakat va noto'g'ri raqam — faqat oxirgi 2 raqam.
create or replace function app.sales_mask(p text) returns text
language sql immutable set search_path = pg_catalog as $$
  select case when coalesce(p, '') = '' then null
              when p ~ '^998[0-9]{9}$' then '+' || left(p, 3) || ' ' || substr(p, 4, 2) || ' *** ** ' || right(p, 2)
              when length(p) >= 5 then '*** ** ' || right(p, 2)
              else '***' end
$$;
-- Ota-ona ismi (ko'rsatish va qidiruv uchun): katakka ism bilan birga yozilgan izoh (qavs ichidagi matn), raqamli so'z (telefon, sana)
--   va faqat tinish belgisidan iborat so'z olib tashlanadi, ko'pi bilan 60 belgi; harf qolmasa — NULL. Niqoblangan ro'yxatda ism
--   katagidagi telefon / izoh chegarasiz va jurnalsiz chiqardi (mustaqil tekshiruv). Oilani bog'lash kaliti ham shu tozalangan ismdan
--   olinadi (sales_families).
create or replace function app.sales_pname(p text) returns text
language sql immutable set search_path = pg_catalog as $$
  select case when app.sales_hasletter(v) then v end
    from (select btrim(left(btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
                   '[(\[{][^)\]}]*([)\]}]|$)', ' ', 'g'),
                   '\S*[0-9]\S*', ' ', 'g'),
                   '(^|\s)[[:punct:]—–«»“”„…•·№]+(?=\s|$)', ' ', 'g'),
                   '\s+', ' ', 'g'), ' ,;:./-'), 60)) as v) x
$$;
-- Ota yoki ona: {name, phone, valid} (ism ham, raqam ham bo'lmasa — null). valid — katak BITTA qo'ng'iroq qilib bo'ladigan raqam va katakdagi
--   barcha raqamlar shu raqamniki (app.sales_nums; sahifa havoladan oldin phoneCanon bilan ham tekshiradi). Ochilganda (p_mask = false):
--   shunday bo'lsa — «+998001234567»; aks holda (bir nechta raqam, raqamli izoh) — faqat qo'ng'iroq qilib bo'ladigan raqamlar, yozilganidek
--   (sahifa har birini alohida havola qiladi); bunday raqam bo'lmasa — niqob («*** ** 67», sahifa «raqam noto'g'ri — ma'muriyatga xabar bering»
--   deydi). Ro'yxatda (p_mask) — niqob: butun katak to'g'ri raqam bo'lsa «+998 00 *** ** 67», aks holda birinchi qo'ng'iroq qilib bo'ladigan
--   raqamning niqobi, u ham bo'lmasa — faqat oxirgi 2 raqam (pasport / uy raqamidan yig'ilgan «+998 12 …» O'zbekiston raqami ko'rinishida
--   chiqmaydi). Katakka yozilgan izoh (ism, oila holati, sog'lig'i …), sana, hujjat / karta raqami, JSHSHIR sotuvchiga chiqmaydi (mustaqil tekshiruv).
drop function if exists app.sales_parent(text, text, boolean);
create or replace function app.sales_parent(p_name text, p_phone text, p_mask boolean, p_raw text default null) returns jsonb
language sql immutable set search_path = public, app, pg_temp as $$
  select case when p_name is null and coalesce(p_phone, '') = '' then null
              else jsonb_build_object('name', p_name,
                     'phone', case when coalesce(p_phone, '') = '' then null
                                   when w.whole then case when p_mask then app.sales_mask(p_phone) else '+' || p_phone end
                                   when cardinality(w.nums) > 0 then case when p_mask then app.sales_mask(app.tg_phone(w.nums[1]))
                                                                          else array_to_string(w.nums, ', ') end
                                   else w.mz end,
                     'valid', case when coalesce(p_phone, '') = '' then null else w.whole end) end
    from (select v.nums, case when length(coalesce(p_phone, '')) >= 5 then '*** ** ' || right(p_phone, 2) else '***' end as mz,
                 app.sales_valid(p_phone) and (p_raw is null or (cardinality(v.nums) = 1 and app.tg_phone(v.nums[1]) = p_phone)) as whole
            -- OFFSET 0 — sales_nums bir marta hisoblansin (aks holda har ishlatilgan joyda qayta hisoblanardi)
            from (select case when p_raw is null then '{}'::text[] else app.sales_nums(p_raw) end as nums offset 0) v offset 0) w
$$;
-- Oilalar: faol o'quvchilar (p_all — arxivdagilar ham: faqat Direktor jurnalidagi ismlar uchun). Oila — kartalar grafining bog'langan
--   qismi. Ikki karta bitta oila, agar (1) umumiy TO'G'RI raqami bo'lsa (app.sales_valid; «0», qisqa yoki ikki raqamli katak — bog'lamaydi)
--   va (2) ota yoki ona ismi mos kelsa (app.sales_nkey) hamda ikkinchi ota-ona ismi zid bo'lmasa (ikkalasida bor va har xil — zid).
--   Shunday qilib aka-uka kartalarida raqamlar almashib yozilgan yoki birida ona raqami / ismi yo'q bo'lsa ham — bitta qator (kunlik
--   chegaradan bitta o'rin); umumiy «to'ldiruvchi» raqam (maktab raqami, «0») yoki bir ota — ikki ona (boshqa-boshqa oila) esa
--   birlashmaydi (aks holda oila ro'yxatdan jim yo'qolardi; mustaqil tekshiruv); ismi bo'sh karta orqali zid ismlar bitta komponentga
--   tushsa — komponent bo'linadi. Raqamsiz oila — yo'q. Ism — oiladagi kartalarda eng ko'p uchragani; raqam — darajalar bo'yicha (foydalanib
--   bo'ladigan katak, shu ota-onaning ismi yozilgan karta, ona raqami ota katagida emas — pastdagi fpt / mpt / fpf); ona raqami —
--   otanikidan farqlisi.
--   Kalit — oiladagi eng kichik o'quvchi hujjat id'si (tuz bilan sha256; id ham,
--   telefon ham chiqmaydi). Shaxsiy karta — o'quvchi hujjat id'si bilan (eski yozuv — studentId kalitli, boshqa o'quvchining hujjati
--   bo'lmasa; app.tg_card_phones bilan bir xil qoida).
-- Birlashtirish-topish (union-find): p_n ta tugun (1…p_n), qirralar (p_x[i], p_y[i]); natija — har tugun uchun o'z bog'langan qismidagi
--   ENG KICHIK tugun raqami (kichigi ildiz bo'ladi; yo'l qisqartirish bilan — chiziqliga yaqin vaqt).
create or replace function app.sales_uf(p_n int, p_x int[], p_y int[]) returns int[]
language plpgsql immutable set search_path = pg_catalog as $$
declare
  par int[] := array(select g from generate_series(1, greatest(coalesce(p_n, 0), 0)) g);
  i int; a int; b int;
begin
  for i in 1 .. coalesce(array_length(p_x, 1), 0) loop
    a := p_x[i]; while par[a] <> a loop par[a] := par[par[a]]; a := par[a]; end loop;
    b := p_y[i]; while par[b] <> b loop par[b] := par[par[b]]; b := par[b]; end loop;
    if a < b then par[b] := a; elsif b < a then par[a] := b; end if;
  end loop;
  for i in 1 .. coalesce(p_n, 0) loop
    a := i; while par[a] <> a loop a := par[a]; end loop;
    par[i] := a;
  end loop;
  return par;
end $$;
drop function if exists app.sales_families(boolean);
create or replace function app.sales_families(p_all boolean default false)
returns table(fkey text, f_name text, f_phone text, m_name text, m_phone text, f_raw text, m_raw text)
language sql stable set search_path = public, app, pg_temp set jit = off as $$
  with recursive st as (
    select s.id as cid,
           case when n.fk <> '' then n.fn end as fn, app.tg_phone(p."parentPhone") as fp, n.fk,
           case when n.mk <> '' then n.mn end as mn, app.tg_phone(p."parentPhone2") as mp, n.mk,
           btrim(coalesce(p."parentPhone", '')) as fr, btrim(coalesce(p."parentPhone2", '')) as mr
      from public.students s
      cross join lateral (
        select sp."fatherName", sp."motherName", sp."parentPhone", sp."parentPhone2" from public.student_private sp where sp.id = s.id
        union all
        select sp."fatherName", sp."motherName", sp."parentPhone", sp."parentPhone2" from public.student_private sp
         where nullif(btrim(coalesce(s."studentId", '')), '') is not null and sp.id = s."studentId" and sp.id <> s.id
           and not exists (select 1 from public.student_private x where x.id = s.id)
           and not exists (select 1 from public.students s2 where s2.id = s."studentId")
        limit 1) p
      -- Ism bir marta tozalanadi (app.sales_pname: qavsdagi izoh, raqamli so'z, tinish belgisi olib tashlanadi) va kalit shu tozalangan
      --   ismdan olinadi: «Akmal (ota)» = «Akmal»; kalit bo'sh bo'lsa («-», «yo'q», «- (vafot etgan)» …) — ism yozilmagan. OFFSET 0 — ifodalar
      --   so'rov ichida qayta hisoblanmasin (tezlik).
      cross join lateral (select v.fn, app.sales_nkey(v.fn) as fk, v.mn, app.sales_nkey(v.mn) as mk
                            from (select app.sales_pname(p."fatherName") as fn, app.sales_pname(p."motherName") as mn offset 0) v offset 0) n
     where p_all or not (coalesce(s."payStatus", '') = 'chiqdi'
                 and case when left(coalesce(s."exitAt", ''), 10) ~ '^\d{4}-\d{2}-\d{2}$' then left(s."exitAt", 10)
                          when left(coalesce(s."stopFrom", ''), 10) ~ '^\d{4}-\d{2}-\d{2}$' then left(s."stopFrom", 10)
                          else '' end <= to_char(app.fin_today(), 'YYYY-MM-DD'))
  ),
  cards as (select st.cid, st.fn, st.fp, st.mn, st.mp, st.fr, st.mr, st.fk, st.mk
              from st where st.fp <> '' or st.mp <> ''),
  -- Bog'lanish qoidasi (ikki karta): umumiy TO'G'RI raqam va (ota ismi teng yoki ona ismi teng), zid ism yo'q (ikkalasida bor va har xil).
  --   Juftlarni sanab chiqish (n²) va to'liq tutashuv (n³) o'rniga — teng kuchli «yulduz» qirralar va birlashtirish-topish (union-find):
  --   bir raqamda (ota, ona) sinfi ichidagi kartalar — sinf vakiliga; (ota, —) vakili — shu raqam va shu otali (ota, ona) vakillariga;
  --   (—, ona) vakili — shu raqam va shu onali (ota, ona) vakillariga. Bog'langan qismlar aynan juftlik qoidasi bilan bir xil, lekin bitta
  --   umumiy raqamli yuzlab karta (masalan ota ismi «-» va maktab raqami) ham ro'yxatni sekinlashtirmaydi (mustaqil tekshiruv).
  --   Faqat ona ismi yozilgan karta (ota ismi yo'q / «-») «ota telefoni»dagi raqam orqali faqat shu raqam shu ismli onaning raqami bo'lsa
  --   bog'lanadi: kartada onaning boshqa to'g'ri raqami yo'q yoki bu raqam biror kartada shu ismli onaning «ona telefoni»da turadi (aka-uka
  --   kartalarida raqamlar almashib yozilgan). Aks holda — faqat onasining raqami orqali: otasiz kartalarda «ota telefoni»ga ko'pincha
  --   maktab yoki qarindosh raqami yoziladi va keng tarqalgan ona ismi (Zarina, Dilnoza …) bilan begona oilalar bitta qatorga qo'shilib,
  --   bir onaning raqami yo'qolardi (mustaqil tekshiruv).
  mph as (select distinct c.mp as ph, c.mk from cards c where c.mk <> '' and app.sales_valid(c.mp)),
  cph as (select c.cid, c.fp as ph, c.fk, c.mk from cards c
           where app.sales_valid(c.fp) and (c.fk <> '' or c.mk <> '')
             and (c.fk <> '' or not app.sales_valid(c.mp) or c.mp = c.fp or exists (select 1 from mph m where m.ph = c.fp and m.mk = c.mk))
          union select c.cid, c.mp, c.fk, c.mk from cards c where app.sales_valid(c.mp) and (c.fk <> '' or c.mk <> '')),
  cls as (select p.ph, p.fk, p.mk, min(p.cid) as rep from cph p group by p.ph, p.fk, p.mk),
  e0 as (select p.cid as x, k.rep as y from cph p join cls k on k.ph = p.ph and k.fk = p.fk and k.mk = p.mk where p.cid <> k.rep
         union all
         select a.rep, b.rep from cls a join cls b on b.ph = a.ph and b.fk = a.fk and b.mk <> '' where a.fk <> '' and a.mk = ''
         union all
         select a.rep, b.rep from cls a join cls b on b.ph = a.ph and b.mk = a.mk and b.fk <> '' where a.mk <> '' and a.fk = ''
         union all
         -- ismsiz kartalar (ota ham, ona ham yozilmagan yoki «-») — faqat IKKALA raqami bir xil bo'lsa birga (hech narsa yo'qolmaydi)
         select c.cid, min(c.cid) over (partition by c.fp, c.mp) from cards c where c.fk = '' and c.mk = ''),
  nodes as materialized (select c.cid, (row_number() over (order by c.cid))::int as i from cards c),
  ed as (select array_agg(nx.i order by nx.i, ny.i) as ex, array_agg(ny.i order by nx.i, ny.i) as ey
           from e0 join nodes nx on nx.cid = e0.x join nodes ny on ny.cid = e0.y),
  uf as (select app.sales_uf((select count(*)::int from nodes), coalesce(ed.ex, '{}'::int[]), coalesce(ed.ey, '{}'::int[])) as r from ed),
  ufr as (select t.i::int as i, t.ri from uf cross join lateral unnest(uf.r) with ordinality t(ri, i)),
  -- root — bog'langan qismdagi eng kichik karta id'si (union-find ildizi — eng kichik tartib raqami)
  comp0 as (select n.cid, rn.cid as root from nodes n join ufr on ufr.i = n.i join nodes rn on rn.i = ufr.ri),
  -- Zid komponent: ismi bo'sh «ko'prik» karta orqali ikki xil ota yoki ona ismi bitta komponentga tushgan (masalan, bir ota — ikki ona
  --   va onasi yozilmagan uchinchi karta). Birlashtirilmaydi: ikkala ismi bor bir xil (ota, ona) kartalar birga, bitta ismli kartalar —
  --   ismi va ikkala raqami bir xil bo'lsa birga (bir xil qator takrorlanmasin), qolgan karta — alohida qator (oila ro'yxatdan
  --   yashirinmaydi, ism boshqa odamning raqami bilan chiqmaydi; mustaqil tekshiruv).
  bad as (select cp.root from comp0 cp join cards c on c.cid = cp.cid group by cp.root
           having count(distinct c.fk) filter (where c.fk <> '') > 1 or count(distinct c.mk) filter (where c.mk <> '') > 1),
  comp as (select cp.cid,
                  case when not exists (select 1 from bad b where b.root = cp.root) then cp.root
                       when c.fk <> '' and c.mk <> '' then min(cp.cid) over (partition by cp.root, c.fk, c.mk)
                       when c.fk <> '' or c.mk <> '' then min(cp.cid) over (partition by cp.root, c.fk, c.mk, c.fp, c.mp)
                       else cp.cid end as root
             from comp0 cp join cards c on c.cid = cp.cid),
  -- fok / mok — katakdan foydalanib bo'ladi (app.sales_nums bo'sh emas): butun katak yoki uning biror qismi qo'ng'iroq qilib bo'ladigan raqam
  --   (bir nechta raqamli katakni sahifa alohida havolalarga ajratadi); karta raqami, JSHSHIR, yopishgan raqamlar — yo'q.
  --   cc — katakdagi qo'ng'iroq qilinadigan raqamning kanonigi (katakda bitta shunday raqam bo'lsa — uniki: «+998 00 300 00 02 (2-uy)» ->
  --   998003000002; aks holda butun katakniki): «bu ikkinchi ota-onaning raqamimi» (fp_mom, mpt 5-daraja, fpf) shu bilan solishtiriladi —
  --   aks holda izohli katakdagi ona raqami otaning haqiqiy raqami bilan teng darajada turib, uni yashirardi (mustaqil tekshiruv). Guruhlash,
  --   valid — butun katak kanonigi (fp / mp) bo'yicha, o'zgarmaydi; asl yozuv — shu kanonikli kataklardan, qo'ng'iroq kanonigi bilan (frw / mrw).
  --   Har bir NOYOB yozuv uchun bir marta (aka-uka kartalarida bir xil yozuv takror hisoblanmaydi). Tezlik uchun: 100 belgigacha, faqat
  --   raqam / qavs / chiziqcha / bitta bo'sh joylardan iborat (boshida «+» bo'lishi mumkin), butunligicha raqam sifatida o'qiladigan
  --   (app.sales_part_ok) katak — darhol «ha»: sales_nums bunday katakni bitta bo'lak, bitta bo'lakcha deb o'qib, aynan shu raqamni beradi
  --   (nuqta, ikki bo'sh joy, o'rtadagi «+» — yumshoq ajratuvchi bo'lishi mumkin, shuning uchun ular sales_nums orqali). Kanonigi 998 + 9
  --   raqam va «+» bilan boshlangan yoki faqat raqamdan iborat katak uchun sales_part_ok chaqirilmaydi — uning javobi baribir «ha» (eng
  --   ko'p uchraydigan yozuvlar, tezlik). 9 raqamdan kam katak — qo'ng'iroq qilib bo'ladigan raqami bo'lmaydi (eng qisqasi — 9 xonali
  --   mahalliy raqam).
  --   ccs — katakda bir nechta qo'ng'iroq raqami bo'lsa, har birining kanonigi (fxo). fw — katak ota yorlig'i: unda ota so'zi bor («ota»,
  --   «otasi», «otam», «dada», «dadasi», «dadam», «papa», «papasi», «papam», ularning qaratqich shakllari — «otaning», «otasining», «otasiniki»,
  --   so'zlashuvdagi «otasini», «dadasini» —, kirillchasi, ruscha «отец», «отца», «папы», «папин»), undan boshqa so'z faqat «tel», «telefon»,
  --   «raqami», «nomeri», «mob», «ish», «uy» kabi telefon yorlig'i («+998 00 111 21 31 (otasi)», «otasi 998001112131», «(dadasini nomeri)»,
  --   «(отец, моб.)») va katakdagi raqamlar shu bitta raqamdan iborat (katak kanonigi qo'ng'iroq kanonigiga teng: boshqa raqam yoki izohdagi
  --   raqam yo'q). Ota haqidagi izoh («(onasi; otasi chet elda)», «(otasi, vafot etgan)», «(мама, папа в России)»), istalgan yozuvdagi «ota-ona»
  --   («ota – ona», «ona/ota», «onasi, otasi») va «o'ta» (juda) — yorliq emas: bunday izohli katakdagi onaning raqami otaniki bo'lib chiqardi
  --   (14-mustaqil tekshiruv); yorliqdan keyin boshqa so'z bo'lsa ham («(otasi, ishda)») — yorliq emas (ehtiyotkor tanlov, 24-chegara). Ikki
  --   raqamli yoki so'z boshqa raqamga yopishgan katak («+998 02 544 84 25, +998 00 111 22 35dadasi») sanalmaydi: so'z qaysi raqamniki ekani
  --   noma'lum. Raqamli (tezkor) katak — so'zsiz.
  --   Yorliq qoidasining o'zi «ona» so'zini ham chiqarib tashlaydi (u yorliq emas), shuning uchun ota so'zi yonidagi «ona» alohida
  --   tekshirilmaydi: avvalgi alohida tekshiruv «ishxona» so'zining oxirini «ona» deb o'qib, «(ishxona otasi)» yozuvini yorliq
  --   emas, «(otasi ishxona)» ni esa yorliq deb hisoblardi (o'z mutatsiya tahlili). Yorliqlar lotin va kirill yozuvida bir xil.
  rawok as materialized (
    select z.raw, z.ok, z.cc, z.ccs,
           case when z.fast or z.n > 1 or z.cc <> z.canon then false
                else (select w.t ~ '(^|[^a-zа-яёўқғҳ])((ota|dada|papa)(si|m)?(ning|niki|ni)?|(ота|дада|папа)(си|м)?(нинг|ники|ни)?|отец|отца|папин|папы)([^a-zа-яёўқғҳ]|$)'
                             and w.t ~ '^[^a-zа-яёўқғҳ]*(((ota|dada|papa)(si|m)?(ning|niki|ni)?|(ота|дада|папа)(си|м)?(нинг|ники|ни)?|отец|отца|папин|папы|tel|telefon|telefoni|raqam|raqami|nomer|nomeri|mob|mobil|uyali|ish|ishxona|uy|тел|телефон|телефони|рақам|рақами|номер|номери|моб|мобил|уяли|иш|ишхона|уй|мобильный|сотовый|рабочий|домашний)([^a-zа-яёўқғҳ]+|$))*$'
                        from (select lower(translate(z.raw, 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ', 'абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳ')) as t) w) end as fw
      from (select q.raw, q.fast, q.canon, cardinality(q.nums) as n, q.fast or cardinality(q.nums) > 0 as ok,
                   case when not q.fast and cardinality(q.nums) = 1 then app.tg_phone(q.nums[1]) else q.canon end as cc,
                   case when not q.fast and cardinality(q.nums) > 1 then array(select app.tg_phone(x) from unnest(q.nums) x) end as ccs
            from (select r.raw, r.canon, r.fast,
                         case when r.fast or length(regexp_replace(r.raw, '\D', '', 'g')) < 9 then '{}'::text[] else app.sales_nums(r.raw) end as nums
                    from (select u.raw, u.canon,
                                 (length(u.raw) <= 100 and u.raw ~ '^[+]?[0-9() -]*$' and strpos(u.raw, '  ') = 0
                                  and ((u.canon ~ '^998[0-9]{9}$' and (left(u.raw, 1) = '+' or u.raw !~ '[^0-9]')) or app.sales_part_ok(u.raw))) as fast
                            from (select c.fr as raw, c.fp as canon from cards c where c.fr <> ''
                                  union select c.mr, c.mp from cards c where c.mr <> '') u
                          offset 0) r
                  offset 0) q
            offset 0) z),
  fam0 as (select c.fn, c.fp, c.mn, c.mp, c.fr, c.mr, cp.root, coalesce(fo.ok, false) as fok, coalesce(mo.ok, false) as mok,
                  coalesce(fo.cc, c.fp) as fc, coalesce(mo.cc, c.mp) as mc, mo.ccs as mcs, coalesce(mo.fw, false) as mfw
             from cards c join comp cp on cp.cid = c.cid
             left join rawok fo on fo.raw = c.fr left join rawok mo on mo.raw = c.mr),
  -- fp_mom: shu oilada ona ismi yozilgan kartada ona raqami bo'lib turgan raqam (qo'ng'iroq kanonigi bo'yicha). «Ota telefoni» katagidagi
  --   bunday raqam: ota ismi yozilmagan kartada — otaniki emas; ota ismi yozilgan kartada — faqat boshqa kartalarda otaning o'z raqami
  --   bo'lmasa (masalan oilaning umumiy raqami) ishlatiladi (fpt darajalari).
  --   fmn — shu raqam ona ismi yozilgan nechta kartaning «ona telefoni»da turgani (pastda, fpc).
  mom as (select y.root, y.mc, count(*) as nm, bool_or(y.mfw) as fw from fam0 y where y.mn is not null group by y.root, y.mc),
  fam as (select f.*, (m.root is not null) as fp_mom, coalesce(m.nm, 0) as fmn
            from fam0 f left join mom m on m.root = f.root and m.mc = f.fc),
  -- Ism — oiladagi kartalarda eng ko'p uchragan tozalangan ism (izoh, raqam, qavs ichidagi matn — olib tashlangan; st).
  nm as (select fam.root,
                mode() within group (order by fam.fn) filter (where fam.fn is not null) as fn,
                mode() within group (order by fam.mn) filter (where fam.mn is not null) as mn
           from fam group by fam.root),
  -- Ota raqami — eng yaxshi darajadagi kartalardan; daraja ichida (qo'ng'iroq raqami bo'yicha): ona katagidagi soni minus shu ism sinfidagi
  --   ota katagidagi soni (har qanday yozuvda) kamrog'i (fmn − fct; boshqa darajalarda fmn = 0, ya'ni shu sinfdagi kartalar soni ko'prog'i;
  --   2-darajada — avval ota ismi yozilgan kartalarda, «+»siz / izohli bo'lsa ham, ko'proq turgani; 3- va 6-darajada —
  --   ona raqami bilan bir xil raqamlarda — otaning raqami ota ustunida ko'proq, ona ustunida kamroq turadi), teng bo'lsa — kamroq ona
  --   katagida turgani (fmn), so'ng barcha kartalarda ko'proq yozilgani (har qanday yozuv va darajada — fcn), so'ng shu yozuvi ko'p uchragani;
  --   teng bo'lsa — toza yozilgani (butun katak bitta to'g'ri raqam, ya'ni katak kanonigi qo'ng'iroq kanonigiga teng: izohli yoki tasodifiy
  --   raqam yopishgan katakdan ajratib olingan raqam emas); yana teng bo'lsa — kichigi. Aks holda: bitta kartada raqamlar almashib, ota
  --   raqami izohli («(2-uy)», «kv 5») yozilganda otaning turli izohli yozuvlari alohida sanalib, toza yozilgan ona raqami ustun chiqib, ota
  --   bilan ona to'liq almashardi (8-mustaqil tekshiruv); otasiz kartalardagi maktab / qarindosh raqami yoki onasi ro'yxatdan o'tkazgan
  --   kartalardagi ona raqami ismli kartalardagi ko'pchilikni bosib o'tardi (barcha kartalar soni daraja ichidagi sondan oldin edi), ona
  --   katagiga ikkala raqami yozilgan yoki bitta karta almashgan oilada «kamroq ona katagida» qoidasi otaning ota ustunidagi kartalarini
  --   hisobga olmay, ota va ona almashardi (9-mustaqil tekshiruv). Ma'lum chegara: ota ismi yozilgan kartalarning ko'pchiligida raqamlar
  --   almashgan bo'lsa (ona raqami ota katagida otanikidan ko'p) — ota ismli kartalar bo'yicha hal qilib bo'lmaydi. Darajalar: foydalanib
  --   bo'ladigan katak (fok) — (1) ota ismi yozilgan karta, ona raqami emas; (2) ona raqami emas; (3) ota ismi yozilgan karta, ona raqami bilan
  --   bir xil (oilaning umumiy raqami); (4–6) noto'g'ri katak — xuddi shu tartibda. Ota ismi yozilmagan kartaning «ota telefoni»dagi ona
  --   raqami — nomzod emas. Shunday qilib ismli kartadagi «0» boshqa kartadagi to'g'ri raqamni yashirmaydi, ona raqami ota ismi yozilgan
  --   kartada bo'lsa ham boshqa kartadagi haqiqiy ota raqamidan ustun emas (mustaqil tekshiruv).
  fpt as (select fam.root, fam.fp, fam.fc, fam.fmn,
                 case when fam.fn is not null and not fam.fp_mom then 1 when not fam.fp_mom then 2 else 3 end
                 + case when fam.fok then 0 else 3 end as t
            from fam where fam.fp <> '' and (fam.fn is not null or not fam.fp_mom)),
  -- fcn / mcn — shu ustunda shu qo'ng'iroq raqami (fc / mc) yozilgan kartalar soni (yozilish shakli va darajadan qat'i nazar); fct — shu
  --   ism sinfidagi ota nomzodi kartalari soni (qo'ng'iroq raqami bo'yicha, har qanday yozuvda: 1- va 4-, 2- va 5-, 3- va 6-darajalar birga,
  --   fmn kabi; fmn va fmn − fct teng bo'lsa — fct ham teng, alohida kalit emas); fnm — shu raqam ota ismi yozilgan (ona raqami bo'lmagan)
  --   kartalarning ota katagida necha marta turgani (1- va 4-daraja). Aks holda «+»siz yozilgan xorijiy raqam yoki so'zga yopishgan raqam
  --   («447700900141», «… 43dadasi» — qo'ng'iroq qilib bo'lmaydi, 4-daraja) otaning raqami sifatida sanalmay, ota ismli kamroq kartadagi
  --   bobosi / ona raqami otaniki bo'lardi, ota ismli kartalarda faqat shunday yozilgan raqam esa otasiz kartalardagi qarindosh raqamidan
  --   keyin qolardi (10-mustaqil tekshiruv, 2-o'tish). Ikkalasi faqat to'g'ri (bitta) raqam uchun: ikki raqamli katakning kanonigi shu
  --   raqamlardan iborat boshqa katak bilan qo'shilmaydi.
  --   fct / fnm — guruhlangan yozuvlar ustida oyna yig'indisi: fpt ikkinchi marta o'qilsa, Postgres uni materiallashtirib, katta oilada
  --   ro'yxatni ~25% sekinlashtirardi.
  --   4-darajadagi raqam telefon ko'rinishida (998 + 9 raqam yoki ma'lum davlat kodi va uzunligi) va kamida ikki ota ismli kartada (fct > 1)
  --   bo'lsa — 3-darajaga qo'shiladi: ona ismli BARCHA kartalarning ona katagida turgan va ona ustunida ko'proq (fmn > fct) raqam — aniq ona
  --   raqami (mt — ona ismli, ona katagi bo'sh bo'lmagan kartalar soni) — undan avval ota ismli kartalarda ko'proq turgani (fct), so'ng
  --   fmn − fct bo'yicha. Aks holda «447700900198» ota ismli ikki kartada, ona raqami bitta kartaning ota katagida bo'lsa ham
  --   «foydalanib bo'ladigan» 3-daraja oldin turib, ota ham, ona ham ona raqami bo'lardi (eng og'ir; 8-qoida bilan endi o'qiladigan
  --   «+998⏎00 006⏎22 98», «02  003  01  99» kataklarida 44e1049 ga nisbatan regressiya — 11-mustaqil tekshiruv). Ona ismli kartada boshqa
  --   raqam ham bo'lsa yoki raqam ota ustunida ona ustunidagidan kam bo'lmasa — o'zgarmaydi (ism dalili bir tomonlama emas); ona ismi umuman
  --   yozilmagan, otaning raqami ona ismli katakda ham turgan (6-daraja — ko'tarilmaydi) yoki bitta ota ismli kartada bo'lsa ham o'zgarmaydi.
  --   fxo — shu raqam ota katagida, ona katagida esa boshqa telefon ko'rinishidagi raqam turgan ota ismli kartalar soni (ajratuvchi karta;
  --   ona katagida bir nechta raqam bo'lsa — har biri: kamida bittasi telefon ko'rinishida, hech biri biror ota ismli kartaning ota
  --   katagida turmaydi, aks holda raqamlari almashgan karta; «0044 7700 900705 (2)» kabi izohli 13 xonali yozuv ham emas). Ajratuvchi
  --   karta raqamni «aniq ona raqami» sifatida pasaytirishdan faqat biror ona ismli katakda shu raqam ota so'zi bilan yozilgan bo'lsa
  --   himoyalaydi (mom.fw: «+998 00 111 21 31 (otasi)»). Aks holda ona ismli kataklarga otaning raqami yozilgan, onaning o'z raqami onasiz
  --   kartada bo'lgan oilada ota ismli kartalardagi «+»siz uchinchi raqam otaniki, ota raqami esa onaniki bo'lib chiqardi (8f9925d,
  --   12-mustaqil tekshiruv). So'zsiz ajratuvchi karta himoya emas: u doim ona ismsiz (ona ismli bo'lsa, raqam ona ustunini to'liq
  --   egallamaydi) va ona katagida maktab yoki qarindosh raqami ham turadi — onaning raqamini ham himoyalab, ota qatorida onaning raqamini
  --   chiqarardi (025c023; 8f9925d to'g'ri edi); ota so'zining o'zi ham himoya emas: kataklardagi tasodifiy izoh onaning raqamini himoyalab
  --   qo'yardi; ikki raqamli ona katagi sanalmasa — «(otasi)» izohli oilada ota qatorida «+»siz uchinchi raqam, ona qatorida otaning raqami
  --   chiqardi (13-mustaqil tekshiruv). fna — oiladagi ota ismli kartalarning ota katagidagi raqamlari (jsonb kalitlari: har karta uchun
  --   ikkilik qidiruv; massiv bilan solishtirish ota kataklarida turli raqamlar ko'p bo'lgan katta oilada n² edi — 13-mustaqil tekshiruv;
  --   fam bilan anti-join emas — Postgres CTE hajmini millionlab qator deb baholab, diskka bo'lingan hash qurardi); fxo faqat ona ismli
  --   kataklarda turgan raqamlar (fp_mom) uchun — u faqat 3-darajada o'qiladi. Ma'lum chegara: ona ismli barcha kataklarda otaning raqami,
  --   onaning raqami faqat onasiz kartalarda bo'lib, ajratuvchi karta yoki ota so'zi bo'lmasa — ota katagida otanikidan kam bo'lmagan
  --   uchinchi («+»siz) raqam otaniki, otaning raqami ona raqami deb olinadi (ism dalili shunday; 14-chegaraning ona tomoni); kartalarning
  --   ko'pchiligida raqamlar almashgan bo'lsa ham — shunday.
  fcn as (select fam.root, fam.fc, count(*) as nc from fam where fam.fp <> '' group by fam.root, fam.fc),
  mcn as (select fam.root, fam.mc, count(*) as nc from fam where fam.mp <> '' group by fam.root, fam.mc),
  fna as (select fam.root, jsonb_object_agg(fam.fc, true) as fcs from fam where fam.fn is not null and fam.fp <> '' group by fam.root),
  fxo as (select fam.root, fam.fc, count(*) as n from fam join fna on fna.root = fam.root
           where fam.fn is not null and fam.fp <> '' and fam.fp_mom
             and exists (select 1 from unnest(coalesce(fam.mcs, array[fam.mc])) y where (y ~ '^998[0-9]{9}$' or app.sales_intl_ok(y)) and y <> fam.fc)
             and not exists (select 1 from unnest(coalesce(fam.mcs, array[fam.mc])) y where y <> fam.fc and fna.fcs ? y)
           group by fam.root, fam.fc),
  -- fpr / mpr — tanlangan guruhning ko'rsatiladigan raqami (guruh vakili; asl yozuv, ikkinchi tomondagi istisno va zaxira tanlov shu bilan): bir
  --   xil raqamlar ketma-ketligi turlicha o'qiladigan kataklar guruhida (so'zga yopishgan / «+»siz qism) — ota guruhida ona ustunidagi soni (mcn)
  --   minus shu ism sinfidagi ota nomzodi kataklaridagi soni (fpn.nn — ota ismi yozilmagan, fpn.nc − fpn.nn — ota ismi yozilgan kartalar, fct
  --   kabi) kamrog'i, teng bo'lsa — barcha ota nomzodi kataklari (fpn.nc) bilan; ona guruhida — ota nomzodi kataklarida kamroq uchraydigan
  --   o'qish, bu teng bo'lsa — barcha kartalarning ota katagidagi soni (fcn) minus ona ismli kartalarning ona katagidagi soni (mom) kamrog'i;
  --   so'ng guruhda ko'proq uchragani, so'ng kichigi; tartiblash (fct, fnm, fcn) — avvalgidek guruhdagi eng kichik qo'ng'iroq kanonigi bo'yicha.
  --   Aks holda (eng kichigi ko'rsatilganda) ona ustunidagi 4:1 guruhda ham ozchilikdagi otaning raqami ona qatorida chiqardi; faqat eng ko'p
  --   uchragani olinsa — otaning «+»siz qismi o'qilmagan ota guruhida ona raqami ota qatorida chiqardi; ota ismi yozilmagan oilada (ota
  --   kataklarida otaning raqami, ona kataklarida ikkala raqam: «tel01 909 46 28; +998005556681») otaning raqami ona katagida ham bo'lgani uchun
  --   fpn da sanalmay, ona qatorida otaning raqami chiqardi; ona raqami ko'p ona ismli kataklarda so'zga yopishgan oilada ona qatorida uchinchi
  --   raqam chiqardi (67b0e73 to'g'ri edi); ona ustunidagi barcha kartalar sanalsa — ona ismli kartalarda ona raqami, onasiz kartalarda uchinchi
  --   raqam ko'p yozilgan oilada uchinchi raqam chiqardi (12-mustaqil tekshiruv); ota guruhida faqat ona ustunidagi soni solishtirilsa — otaning
  --   raqami «(otasi)» izohi bilan ona kataklarida (onasiz kartalarda ham) onaning o'z raqamidan ko'p yozilgan oilada ota qatorida onaning, ona
  --   qatorida otaning raqami chiqardi (13-mustaqil tekshiruv; 67b0e73 to'g'ri edi), barcha ota kataklari (fcn) sanalsa — onasi ro'yxatdan
  --   o'tkazgan kartalarning «ota telefoni»dagi ona raqami ota qatoriga chiqardi. Shu ism sinfi hisobga olinmasa — onasi o'z raqamini faqat «ota
  --   telefoni»ga yozgan (fp_mom emas, otasiz) kartalari ko'p oilada ota guruhining vakili onaning raqami bo'lib, ota va ona almashardi
  --   (14-mustaqil tekshiruv). Ma'lum chegara: ota guruhida ikkala ota-onaning o'qishi aralash va onaning ismi yozilgan barcha kartalarda faqat
  --   otaning raqami bo'lsa (ism dalili qarama-qarshi) — shu ism sinfi bo'yicha tanlov 025c023 dagidek onaning o'qishini olishi mumkin (2a91fa9
  --   va 8f9925d bunda to'g'ri edi; korpuslarda bunday oila yo'q).
  fpn as (select fpt.root, fpt.fc, count(*) as nc, count(*) filter (where fpt.t in (2, 5)) as nn from fpt group by fpt.root, fpt.fc),
  fpr as (select distinct on (r.root, r.fp, r.t) r.root, r.fp, r.t, r.fc
            from (select fpt.root, fpt.fp, fpt.t, fpt.fc, count(*) as k from fpt group by fpt.root, fpt.fp, fpt.t, fpt.fc) r
            left join mcn on mcn.root = r.root and mcn.mc = r.fc
            left join fpn on fpn.root = r.root and fpn.fc = r.fc
           order by r.root, r.fp, r.t, coalesce(mcn.nc, 0) - coalesce(case when r.t in (2, 5) then fpn.nn else fpn.nc - fpn.nn end, 0),
                    coalesce(mcn.nc, 0) - coalesce(fpn.nc, 0), r.k desc, r.fc),
  fpc as (select distinct on (x.root) x.root, x.fp, x.fc, fpr.fc as dfc
            from (select g.*, sum(g.n) over (partition by g.root, g.fc, case when app.sales_valid(g.fc) then g.t % 3 else g.t end) as fct,
                         sum(case when g.t in (1, 4) then g.n else 0 end) over (partition by g.root, g.fc) as fnm
                    from (select fpt.root, fpt.fp, fpt.t, min(fpt.fc) as fc, min(fpt.fmn) as fmn, count(*) as n
                            from fpt group by fpt.root, fpt.fp, fpt.t) g) x
            left join fcn on fcn.root = x.root and fcn.fc = x.fc
            left join fpr on fpr.root = x.root and fpr.fp = x.fp and fpr.t = x.t
            left join (select mom.root, sum(mom.nm) as nm from mom where mom.mc <> '' group by mom.root) mt on mt.root = x.root
            left join fxo on fxo.root = x.root and fxo.fc = x.fc
            left join mom mw on mw.root = x.root and mw.mc = x.fc
           order by x.root, case when x.t = 4 and x.fct > 1 and (x.fc ~ '^998[0-9]{9}$' or app.sales_intl_ok(x.fc)) then 3 else x.t end,
                    case when x.t = 4 or (x.t = 3 and x.fmn > x.fct and x.fmn >= mt.nm and (fxo.n is null or not coalesce(mw.fw, false))) then -x.fct end nulls first,
                    case when x.t = 2 and app.sales_valid(x.fc) then -x.fnm else 0 end, x.fmn - x.fct, x.fmn,
                    fcn.nc desc nulls last, x.n desc, not (app.sales_valid(x.fp) and x.fp = x.fc), x.fp),
  -- Ona raqami — otanikidan farqlisi, xuddi shunday: (1) foydalanib bo'ladigan, ona ismi yozilgan karta; (2) foydalanib bo'ladigan; (3)
  --   noto'g'ri, ona ismi yozilgan; (4) noto'g'ri; (5) otaniki bilan bir xil (oilaning yagona umumiy raqami; butun katak yoki ota qatorida
  --   ko'rsatiladigan qo'ng'iroq kanonigi bo'yicha; ota qatorida ikki raqamli katak ko'rsatilsa — guruhning eng kichik qo'ng'iroq kanonigi
  --   ham, 67b0e73 kabi: aks holda «(otasi)» izohli ona kataklaridagi otaning raqami ona qatoriga chiqardi; ota so'zi bu yerda hisobga
  --   olinmaydi: kataklardagi tasodifiy izohda onaning raqami 5-darajaga tushib, ona qatorida otaning raqami chiqardi — 13-mustaqil
  --   tekshiruv). Daraja ichida — ona ustunida ko'proq kartada yozilgani (mcn, barcha kartalar; «(otasi)» izohli yoki ikkala katakka
  --   yozilgan ona katagidagi ota raqami ona ismsiz kartalarda ham yozilgan ona raqamidan ustun chiqmaydi), so'ng xuddi otanikidek. Ma'lum
  --   chegara: onasiz kartalarning ona katagidagi maktab / qarindosh raqami ona ismli kartalardagi raqamdan ko'p kartada bo'lsa, u
  --   tanlanadi (ona raqami yo'qoladi) — ona tomonida shu darajadagi kartalar sonini ustun qo'yish otaning raqamini onaniki qilib
  --   chiqarardi (9-mustaqil tekshiruv: eng og'ir xato o'rniga raqam yo'qolishi tanlangan). Ma'lum chegara: ota qatoridagi ikki raqamli
  --   katak guruhida eng kichik o'qish onaniki (otaning raqami so'zga yopishgan kataklarda) bo'lsa, ona qatorida otaning raqami chiqishi
  --   mumkin (67b0e73 va 8f9925d kabi; 025c023 bunda to'g'ri edi, lekin ko'zgu ko'rinishida ona qatorida otaning raqamini ko'rsatardi —
  --   ikkalasini farqlab bo'lmaydi).
  mpt as (select fam.root, fam.mp, fam.mc,
                 case when fam.mp = coalesce(fpc.fp, '') or fam.mc = coalesce(fpc.dfc, '')
                           or (fpc.dfc = fpc.fp and not app.sales_valid(fpc.dfc) and fam.mc = fpc.fc) then 5
                      when fam.mok and fam.mn is not null then 1
                      when fam.mok then 2
                      when fam.mn is not null then 3
                      else 4 end as t
            from fam left join fpc on fpc.root = fam.root where fam.mp <> ''),
  mpr as (select distinct on (r.root, r.mp, r.t) r.root, r.mp, r.t, r.mc
            from (select mpt.root, mpt.mp, mpt.t, mpt.mc, count(*) as k from mpt group by mpt.root, mpt.mp, mpt.t, mpt.mc) r
            left join fpn on fpn.root = r.root and fpn.fc = r.mc
            left join fcn on fcn.root = r.root and fcn.fc = r.mc
            left join mom on mom.root = r.root and mom.mc = r.mc
           order by r.root, r.mp, r.t, coalesce(fpn.nc, 0), coalesce(fcn.nc, 0) - coalesce(mom.nm, 0), r.k desc, r.mc),
  mpc as (select distinct on (x.root) x.root, x.mp, x.mc, mpr.mc as dmc
            from (select mpt.root, mpt.mp, mpt.t, min(mpt.mc) as mc, count(*) as n from mpt group by mpt.root, mpt.mp, mpt.t) x
            left join mcn on mcn.root = x.root and mcn.mc = x.mc
            left join mpr on mpr.root = x.root and mpr.mp = x.mp and mpr.t = x.t
           order by x.root, x.t, mcn.nc desc nulls last, x.n desc, not (app.sales_valid(x.mp) and x.mp = x.mc), x.mp),
  -- Ota raqami hali bo'sh (masalan aka-uka kartalarida raqamlar almashib yozilgan, ota ismi yo'q): tanlangan ona raqamidan boshqa
  --   foydalanib bo'ladigan «ota telefoni» — ikkala raqam ham chiqsin, ona raqami (butun katak yoki ona qatorida ko'rsatiladigan qo'ng'iroq
  --   kanonigi bo'yicha) otaniki bo'lib takrorlanmasin; ko'rsatiladigan raqami (fpd) — fpr kabi: ikkinchi ustunda kamroq, so'ng guruhda
  --   ko'proq uchragani, so'ng kichigi. fpd — bitta guruhlash (har oila uchun alohida ichki so'rov katta maktabda ro'yxatni 2–3 baravar
  --   sekinlashtirardi).
  fpd as (select distinct on (y.root, y.fp) y.root, y.fp, y.fc
            from (select fam.root, fam.fp, fam.fc, count(*) as k from fam left join mpc on mpc.root = fam.root
                   where fam.fok and fam.fc <> coalesce(mpc.dmc, '') group by fam.root, fam.fp, fam.fc) y
            left join mcn on mcn.root = y.root and mcn.mc = y.fc
           order by y.root, y.fp, coalesce(mcn.nc, 0), y.k desc, y.fc),
  fpf as (select distinct on (x.root) x.root, x.fp, x.fc, fpd.fc as dfc
            from (select fam.root, fam.fp, min(fam.fc) as fc, count(*) as n
                    from fam left join mpc on mpc.root = fam.root
                   where fam.fok and fam.fp <> coalesce(mpc.mp, '') and fam.fc <> coalesce(mpc.dmc, '') group by fam.root, fam.fp) x
            left join fcn on fcn.root = x.root and fcn.fc = x.fc
            left join fpd on fpd.root = x.root and fpd.fp = x.fp
           order by x.root, fcn.nc desc nulls last, x.n desc, not (app.sales_valid(x.fp) and x.fp = x.fc), x.fp),
  pick as materialized (select nm.root, nm.fn, coalesce(fpc.fp, fpf.fp, '') as fp, coalesce(fpc.dfc, fpf.dfc, '') as fc,
                                nm.mn, coalesce(mpc.mp, '') as mp, coalesce(mpc.dmc, '') as mc
             from nm left join fpc on fpc.root = nm.root left join mpc on mpc.root = nm.root left join fpf on fpf.root = nm.root),
  -- Asl yozuv (ochganda qaysi qismlar ko'rsatilishini aniqlaydi): tanlangan raqam (butun katak kanonigi fp / mp) yozilgan kartalardan —
  --   (1) katakdagi barcha raqamlar qo'ng'iroq qilinadigan katak (katak kanonigi = qo'ng'iroq kanonigi: toza yoki ikki raqamli), (2) qo'ng'iroq
  --   kanonigi tanlangan raqamniki (fc / mc) bo'lgan foydalanib bo'ladigan katak, (3) shu kanonikli har qanday katak; har birida eng ko'p
  --   uchragani. Aks holda bir kartada «+44 7700 900120», ikkitasida «447700900120» bo'lsa, «+»siz yozuv tanlanib, raqam niqoblanardi
  --   (mustaqil tekshiruv); raqamlar ketma-ketligi bir xil, lekin turlicha o'qiladigan kataklardan (so'zga yopishgan / «+»siz qism, boshqa
  --   darajadagi katak) alifbo bo'yicha birinchisi olinib, ota qatorida faqat ona raqami (ona qatorida — ota raqami) chiqardi (11-mustaqil
  --   tekshiruv). Har oila uchun alohida so'rov emas, bitta guruhlash (katta maktabda ham tez). Guruh vakili (fc / mc) — fpr / mpr.
  --   Ma'lum chegara: o'qishlar ikkinchi ustunda ham, guruhda ham teng uchrasa — kichigi (tasodifiy teng holat).
  frw as (select p.root, coalesce(mode() within group (order by f.fr) filter (where f.fok and f.fc = f.fp),
                                  mode() within group (order by f.fr) filter (where f.fok and f.fc = p.fc),
                                  mode() within group (order by f.fr) filter (where f.fc = p.fc), mode() within group (order by f.fr)) as fr
            from pick p join fam f on f.root = p.root and f.fp = p.fp where f.fp <> '' and f.fr <> '' group by p.root),
  mrw as (select p.root, coalesce(mode() within group (order by f.mr) filter (where f.mok and f.mc = f.mp),
                                  mode() within group (order by f.mr) filter (where f.mok and f.mc = p.mc),
                                  mode() within group (order by f.mr) filter (where f.mc = p.mc), mode() within group (order by f.mr)) as mr
            from pick p join fam f on f.root = p.root and f.mp = p.mp where f.mp <> '' and f.mr <> '' group by p.root)
  select left(encode(sha256(convert_to(k.salt || '|sales-v3|' || p.root, 'UTF8')), 'hex'), 32), p.fn, p.fp, p.mn, p.mp, frw.fr, mrw.mr
    from pick p
    left join frw on frw.root = p.root
    left join mrw on mrw.root = p.root
    cross join (select s.salt from app.sales_secret s where s.id = 1) k
$$;
-- Bugun shu foydalanuvchi ochgan oilalar soni.
create or replace function app.sales_used() returns int
language sql stable set search_path = public, app, pg_temp as $$
  select count(*)::int from public.sales_contact_log l where l.uid = app.uid() and l.day = app.fin_today()
$$;
-- Hisobning hozirgi nomi (ism, bo'lmasa email / telefon; hisob yo'q — NULL) va jurnaldagi nom (hisob o'chirilgan bo'lsa — uid).
create or replace function app.sales_user_live(p_uid text) returns text
language sql stable set search_path = public, app, pg_temp as $$
  select coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), nullif(btrim(u.phone), '')) from public.users u where u.id = p_uid
$$;
create or replace function app.sales_user_name(p_uid text) returns text
language sql stable set search_path = public, app, pg_temp as $$
  select coalesce(app.sales_user_live(p_uid), p_uid)
$$;

-- 5) RPC'lar. Uchalasi «set jit = off» bilan: katak yozuvini o'qiydigan ichma-ich funksiyalar (sales_nums) rejasi katta ko'rinadi va JIT har
--   chaqiruvda kompilyatsiya qilib, ro'yxat / ochishni o'nlab baravar sekinlashtirardi (sales_families kabi; mustaqil tekshiruv).
-- Ro'yxat: {ok, rows:[{k, father:{name, phone(niqob)}|null, mother:{…}|null}], total, limit, offset, todayUsed, dailyCap}.
create or replace function public.sales_contacts(p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp set jit = off as $$
declare
  v_q   text := app.sales_norm(btrim(coalesce(p_q, '')));
  v_lim int  := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_off int  := least(greatest(coalesce(p_offset, 0), 0), 1000000);
  v_pat text; v_total int; v_rows jsonb;
begin
  perform app.sales_need();
  if length(v_q) >= 2 then v_pat := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  elsif btrim(coalesce(p_q, '')) <> '' then v_pat := '%' || chr(1) || '%';   -- «o'» kabi 2 harfdan qisqa qidiruv — hech narsa (hammasi emas)
  end if;
  with f as materialized (
    select x.fkey, x.f_name, x.f_phone, x.m_name, x.m_phone, x.f_raw, x.m_raw,
           (x.f_name is null and x.m_name is null) as o1, app.sales_norm(coalesce(x.f_name, x.m_name)) as o2
      from app.sales_families(false) x
     where v_pat is null or app.sales_norm(x.f_name) like v_pat or app.sales_norm(x.m_name) like v_pat
  ), pg as (
    select * from f order by o1, o2, fkey limit v_lim offset v_off
  )
  select (select count(*) from f)::int,
         coalesce((select jsonb_agg(jsonb_build_object('k', pg.fkey,
                                                       'father', app.sales_parent(pg.f_name, pg.f_phone, true, pg.f_raw),
                                                       'mother', app.sales_parent(pg.m_name, pg.m_phone, true, pg.m_raw))
                                    order by pg.o1, pg.o2, pg.fkey) from pg), '[]'::jsonb)
    into v_total, v_rows;
  return jsonb_build_object('ok', true, 'rows', v_rows, 'total', v_total, 'limit', v_lim, 'offset', v_off,
                            'todayUsed', app.sales_used(), 'dailyCap', app.sales_cap());
end $$;
-- Ochish: {ok:true, k, father:{name, phone:'+99800…'}, mother, todayUsed, dailyCap} | {ok:false, reason:'daily_cap'|'not_found'}.
create or replace function public.sales_reveal(p_k text) returns jsonb
language plpgsql volatile security definer set search_path = public, app, pg_temp set jit = off as $$
declare v_uid text; v_day date; v_k text := lower(btrim(coalesce(p_k, ''))); v_f record; v_used int; v_cap int := app.sales_cap();
begin
  perform app.sales_need();
  v_uid := app.uid(); v_day := app.fin_today();
  if v_k !~ '^[0-9a-f]{32}$' then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select x.* into v_f from app.sales_families(false) x where x.fkey = v_k;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  -- Bitta foydalanuvchining bir vaqtdagi so'rovlari kunlik chegarani oshirib yubormasin.
  perform pg_advisory_xact_lock(hashtextextended('sales_reveal|' || v_uid, 0));
  if not exists (select 1 from public.sales_contact_log l where l.uid = v_uid and l.fkey = v_k and l.day = v_day) then
    select count(*) into v_used from public.sales_contact_log l where l.uid = v_uid and l.day = v_day;
    if v_used >= v_cap then
      return jsonb_build_object('ok', false, 'reason', 'daily_cap', 'todayUsed', v_used, 'dailyCap', v_cap);
    end if;
    insert into public.sales_contact_log (uid, fkey, day, "actorName") values (v_uid, v_k, v_day, app.sales_user_name(v_uid))
      on conflict (uid, fkey, day) do nothing;
  end if;
  select count(*) into v_used from public.sales_contact_log l where l.uid = v_uid and l.day = v_day;
  return jsonb_build_object('ok', true, 'k', v_k,
                            'father', app.sales_parent(v_f.f_name, v_f.f_phone, false, v_f.f_raw),
                            'mother', app.sales_parent(v_f.m_name, v_f.m_phone, false, v_f.m_raw),
                            'todayUsed', v_used, 'dailyCap', v_cap);
end $$;
-- Direktor jurnali: {ok, from, to, dailyCap, days:[{day, uid, name, nameNow, role, count}], recent:[{at, day, uid, name, nameNow, role, father,
--   mother}]} — kunlar p_days (1…366) oralig'ida; recent — oxirgi 200 ochish (ota-ona ismi — hozirgi kartadan: avval faol oilalardan, keyin
--   arxivdan; oila tarkibi / raqami o'zgargan bo'lsa — bo'sh). name — xodimning ochish paytidagi nomi (actorName; eski yozuvda — hozirgi
--   nomi), nameNow — hisobning hozirgi nomi, agar u boshqacha bo'lsa (aks holda null); role — hozirgi rol.
create or replace function public.sales_log(p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp set jit = off as $$
declare v_days int := least(greatest(coalesce(p_days, 30), 1), 366); v_to date; v_from date;
begin
  if app.uid() is null then raise exception 'Tizimga kiring' using errcode = '42501'; end if;
  if not app.is_admin() then raise exception 'Ruxsat yo''q: sotuvchilar jurnalini faqat Direktor ko''radi' using errcode = '42501'; end if;
  v_to := app.fin_today(); v_from := v_to - (v_days - 1);
  return jsonb_build_object('ok', true, 'from', v_from, 'to', v_to, 'dailyCap', app.sales_cap(),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', d.day, 'uid', d.uid, 'name', coalesce(d.an, app.sales_user_name(d.uid)),
                                                          'nameNow', case when d.an is not null and app.sales_user_live(d.uid) <> d.an then app.sales_user_live(d.uid) end,
                                                          'role', (select u.role from public.users u where u.id = d.uid), 'count', d.n)
                                       order by d.day desc, d.n desc, d.uid)
                        from (select l.day, l.uid, count(*)::int as n, min(l."actorName") as an from public.sales_contact_log l
                               where l.day between v_from and v_to group by l.day, l.uid) d), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', r."createdAt", 'day', r.day, 'uid', r.uid,
                                                            'name', coalesce(r."actorName", app.sales_user_name(r.uid)),
                                                            'nameNow', case when r."actorName" is not null and app.sales_user_live(r.uid) <> r."actorName"
                                                                            then app.sales_user_live(r.uid) end,
                                                            'role', (select u.role from public.users u where u.id = r.uid),
                                                            'father', coalesce(fa.f_name, fb.f_name), 'mother', coalesce(fa.m_name, fb.m_name))
                                         order by r."createdAt" desc, r.id desc)
                          from (select l.* from public.sales_contact_log l order by l."createdAt" desc, l.id desc limit 200) r
                          left join app.sales_families(false) fa on fa.fkey = r.fkey
                          left join app.sales_families(true) fb on fa.fkey is null and fb.fkey = r.fkey), '[]'::jsonb));
end $$;

do $$ declare f text; begin
  foreach f in array array['public.sales_contacts(text, integer, integer)', 'public.sales_reveal(text)', 'public.sales_log(integer)'] loop
    execute 'revoke all on function ' || f || ' from public, anon';
    execute 'grant execute on function ' || f || ' to authenticated, service_role';
  end loop;
  foreach f in array array['app.sales_cap()', 'app.sales_need()', 'app.sales_norm(text)', 'app.sales_nkey(text)', 'app.sales_valid(text)', 'app.sales_mask(text)',
                           'app.sales_hasletter(text)', 'app.sales_intl_ok(text)', 'app.sales_cc(text)', 'app.sales_dialable(text)', 'app.sales_part_ok(text)', 'app.sales_nums(text)',
                           'app.sales_usable(text)', 'app.sales_pname(text)',
                           'app.sales_parent(text, text, boolean, text)', 'app.sales_uf(integer, integer[], integer[])', 'app.sales_families(boolean)',
                           'app.sales_used()', 'app.sales_user_live(text)',
                           'app.sales_user_name(text)'] loop
    execute 'revoke all on function ' || f || ' from public, anon, authenticated';
  end loop;
end $$;

-- Jurnaldagi nomsiz (ustun qo'shilishidan oldingi) yozuvlar — hozirgi nom bilan bir marta to'ldiriladi (qayta ishga tushirishda — o'zgarmaydi).
update public.sales_contact_log l set "actorName" = app.sales_user_name(l.uid) where l."actorName" is null;

-- 6) «Sotuvchi» hisobida farzand bog'lanishi bo'lmaydi (mustaqil tekshiruv): rol «Sotuvchi»ga o'zgarganda (yoki shunday yaratilganda) faol /
--    kutilayotgan bog'lanishlar bekor qilinadi ('revoked' — o'chirilmaydi; rol qaytsa, ota-ona kod bilan qayta bog'laydi). Yangi bog'lanish —
--    claim_child (payer-code-mask.sql) va child_claim_staff_gate (audit-11-elon.sql) rad etadi. Bir martalik tozalash — idempotent.
create or replace function app.users_sales_claims() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if coalesce(new.role, '') = 'sales' and (tg_op = 'INSERT' or coalesce(old.role, '') <> 'sales') then
    update public.child_claims set status = 'revoked', "updatedAt" = now()
     where uid = new.id and coalesce(nullif(status, ''), 'active') <> 'revoked';
    -- Xabarnoma muharrirlari ro'yxatidan ham (is_notify_editor / auth sms-tpl-check uni baribir muharrir hisoblamaydi — ro'yxat toza qolsin).
    --   Ixtiyoriy tozalash: muharrirlar qo'riqchisi (faqat Direktor / tizim) rad etsa — rol o'zgarishi to'xtamaydi.
    begin
      update public.notify_settings set editors = editors - new.id
       where id = 'general' and jsonb_typeof(editors) = 'array' and editors ? new.id;
    exception when others then null;
    end;
  end if;
  return new;
end $$;
revoke all on function app.users_sales_claims() from public, anon, authenticated;
drop trigger if exists trg_users_sales_claims on public.users;
create trigger trg_users_sales_claims after insert or update of role on public.users
  for each row execute function app.users_sales_claims();
update public.child_claims cc set status = 'revoked', "updatedAt" = now()
 where coalesce(nullif(cc.status, ''), 'active') <> 'revoked'
   and exists (select 1 from public.users u where u.id = cc.uid and u.role = 'sales');
update public.notify_settings g set editors = (select coalesce(jsonb_agg(e), '[]'::jsonb) from jsonb_array_elements(g.editors) e
                                                 where not exists (select 1 from public.users u where u.id = e #>> '{}' and u.role = 'sales'))
 where g.id = 'general' and jsonb_typeof(g.editors) = 'array'
   and exists (select 1 from jsonb_array_elements_text(g.editors) x join public.users u on u.id = x where u.role = 'sales');
-- 7) Sotuvchi hisobining ism-familiyasi va emaili — faqat Direktor (yoki tizim) o'zgartiradi: Direktor jurnali ochishlarni shu nom bilan
--    ko'rsatadi; sotuvchi o'z ismini boshqa xodimnikiga almashtirib, ochishlarini uning nomiga «yozdira» olmasin (mustaqil tekshiruv).
--    O'tgan ochishlar — jurnaldagi ochish paytidagi nom (actorName) bilan: rol keyin o'zgarsa yoki hisob qayta yaratilsa ham o'zgarmaydi.
create or replace function app.users_sales_identity_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if coalesce(old.role, '') = 'sales' and not app.is_system() and not app.is_admin()
     and (new.name is distinct from old.name or new."firstName" is distinct from old."firstName"
          or new."lastName" is distinct from old."lastName" or new.email is distinct from old.email) then
    raise exception 'Sotuvchi hisobining ism-familiyasi va emailini faqat Direktor o''zgartiradi' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function app.users_sales_identity_guard() from public, anon, authenticated;
drop trigger if exists trg_users_sales_identity on public.users;
create trigger trg_users_sales_identity before update of name, "firstName", "lastName", email on public.users
  for each row execute function app.users_sales_identity_guard();
