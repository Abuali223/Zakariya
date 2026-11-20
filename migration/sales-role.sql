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
create or replace function app.sales_hasletter(p text) returns boolean
language sql immutable set search_path = pg_catalog as $$
  select coalesce(p, '') ~ '[A-Za-zÀ-ÖØ-öø-ɏͰ-ϿЀ-ҁҊ-ԯԱ-Ֆա-ևא-תؠ-يႠ-ჿぁ-ヿ一-鿿가-힣]'
$$;
-- Ism kaliti (oilani bog'lash uchun): normallashgan so'zlar — takrorsiz, alifbo tartibida («Karimov Akmal» = «Akmal Karimov»); harfsiz
--   so'z (raqam, tinish belgisi) hisobga olinmaydi («Akmal -» = «Akmal»; «-» — kalitsiz, ya'ni ism yozilmagan).
create or replace function app.sales_nkey(p text) returns text
language sql immutable set search_path = pg_catalog as $$
  select coalesce((select string_agg(x.t, ' ' order by x.t)
                     from (select distinct w as t from regexp_split_to_table(app.sales_norm(p), '\s+') w where app.sales_hasletter(w)) x), '')
$$;
-- To'g'ri raqam: O'zbekiston (998 + 9 raqam) yoki boshqa mamlakat (10–15 raqam, E.164). Aks holda (bir katakda ikki raqam, qisqa,
--   aralash matn) — noto'g'ri: «+» va tel: havolasiz ko'rsatiladi (mustaqil tekshiruv).
create or replace function app.sales_valid(p text) returns boolean
language sql immutable set search_path = pg_catalog as $$
  select coalesce(p, '') ~ '^998[0-9]{9}$' or (coalesce(p, '') ~ '^[1-9][0-9]{9,14}$' and left(p, 3) <> '998')
$$;
-- Qo'ng'iroq qilib bo'ladigan BITTA yozuv (katak yoki uning bir qismi): kanonik shakli (app.tg_phone — «+» / 00 / 9 xonali mahalliy
--   raqam qoidasi) to'g'ri va O'zbekiston raqami (998…) yoki «+» / 00 bilan yozilgan xorijiy raqam — sahifaning salesPartDigits /
--   phoneCanon qoidasi. «+»siz 10–15 raqam (JSHSHIR, karta raqami bo'lagi, yopishib qolgan raqamlar) — telefon EMAS (mustaqil tekshiruv).
create or replace function app.sales_dialable(p text) returns boolean
language sql immutable set search_path = pg_catalog as $$
  select app.sales_valid(app.tg_phone(p))
     and (left(app.tg_phone(p), 3) = '998' or btrim(coalesce(p, '')) ~ '^[^0-9]*\+'
          or regexp_replace(coalesce(p, ''), '\D', '', 'g') like '00%')
$$;
-- Katak yozuvining qismlari (sahifadagi salesTel bilan bir xil bo'linish): raqam, «+», bo'sh joy, «,;/|()-» dan boshqa belgi — bo'sh
--   joy; «,» «;» «/» «|» yoki ikki va undan ortiq bo'sh joy — ajratuvchi; qism chetidagi « ()-» olib tashlanadi.
create or replace function app.sales_segs(p text) returns table (seg text, n bigint)
language sql immutable set search_path = pg_catalog as $$
  select btrim(x.seg, ' ()-'), x.n
    from regexp_split_to_table(regexp_replace(left(coalesce(p, ''), 100), '[^0-9+ ,;/|()-]', ' ', 'g'), '[,;/|]|\s{2,}') with ordinality x(seg, n)
$$;
-- Katakdan foydalanib bo'ladimi (oila raqamini tanlash darajalari — fok / mok): butun katak yoki uning biror qismi qo'ng'iroq qilib
--   bo'ladigan raqam. Karta raqami, JSHSHIR, bitta bo'sh joy bilan yopishgan ikki raqam — yo'q (boshqa kartadagi to'g'ri raqamni yashirmasin).
create or replace function app.sales_usable(p_raw text) returns boolean
language sql immutable set search_path = pg_catalog as $$
  select app.sales_dialable(p_raw) or exists (select 1 from app.sales_segs(p_raw) s where app.sales_dialable(s.seg))
$$;
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
--   katagidagi telefon / izoh chegarasiz va jurnalsiz chiqardi (mustaqil tekshiruv). Oilani bog'lash kaliti (sales_nkey) — o'zgarmaydi.
create or replace function app.sales_pname(p text) returns text
language sql immutable set search_path = pg_catalog as $$
  select case when app.sales_hasletter(v) then v end
    from (select btrim(left(btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
                   '[(\[{][^)\]}]*([)\]}]|$)', ' ', 'g'),
                   '\S*[0-9]\S*', ' ', 'g'),
                   '(^|\s)[[:punct:]—–«»“”„…•·№]+(?=\s|$)', ' ', 'g'),
                   '\s+', ' ', 'g'), ' ,;:./-'), 60)) as v) x
$$;
-- Ota yoki ona: {name, phone, valid} (ism ham, raqam ham bo'lmasa — null). valid — butun katak qo'ng'iroq qilib bo'ladigan bitta raqam
--   (sahifa havoladan oldin phoneCanon bilan ham tekshiradi). p_mask — niqoblangan; aks holda to'g'ri raqam «+998001234567»; bir katakda
--   bir nechta raqam yoki izoh bo'lsa — faqat qo'ng'iroq qilib bo'ladigan QISMLAR (app.sales_dialable; sahifa har birini alohida havola
--   qiladi); bunday qism bo'lmasa — niqob («*** ** 67», sahifa «raqam noto'g'ri — ma'muriyatga xabar bering» deydi). Katakka yozilgan
--   izoh (ism, oila holati, sog'lig'i …), sana, hujjat / karta raqami, JSHSHIR sotuvchiga chiqmaydi (mustaqil tekshiruv).
drop function if exists app.sales_parent(text, text, boolean);
create or replace function app.sales_parent(p_name text, p_phone text, p_mask boolean, p_raw text default null) returns jsonb
language sql immutable set search_path = public, app, pg_temp as $$
  select case when p_name is null and coalesce(p_phone, '') = '' then null
              else jsonb_build_object('name', p_name,
                     'phone', case when coalesce(p_phone, '') = '' then null
                                   when p_mask then app.sales_mask(p_phone)
                                   when app.sales_valid(p_phone) and (p_raw is null or app.sales_dialable(p_raw)) then '+' || p_phone
                                   else coalesce((select string_agg(s.seg, ', ' order by s.n) from app.sales_segs(p_raw) s where app.sales_dialable(s.seg)),
                                                 app.sales_mask(p_phone)) end,
                     'valid', case when coalesce(p_phone, '') = '' then null
                                   else app.sales_valid(p_phone) and (p_raw is null or app.sales_dialable(p_raw)) end) end
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
           case when app.sales_hasletter(p."fatherName") then btrim(p."fatherName") end as fn, app.tg_phone(p."parentPhone") as fp,
           case when app.sales_hasletter(p."motherName") then btrim(p."motherName") end as mn, app.tg_phone(p."parentPhone2") as mp,
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
     where p_all or not (coalesce(s."payStatus", '') = 'chiqdi'
                 and case when left(coalesce(s."exitAt", ''), 10) ~ '^\d{4}-\d{2}-\d{2}$' then left(s."exitAt", 10)
                          when left(coalesce(s."stopFrom", ''), 10) ~ '^\d{4}-\d{2}-\d{2}$' then left(s."stopFrom", 10)
                          else '' end <= to_char(app.fin_today(), 'YYYY-MM-DD'))
  ),
  cards as (select st.cid, st.fn, st.fp, st.mn, st.mp, st.fr, st.mr, app.sales_nkey(st.fn) as fk, app.sales_nkey(st.mn) as mk
              from st where st.fp <> '' or st.mp <> ''),
  -- Bog'lanish qoidasi (ikki karta): umumiy TO'G'RI raqam va (ota ismi teng yoki ona ismi teng), zid ism yo'q (ikkalasida bor va har xil).
  --   Juftlarni sanab chiqish (n²) va to'liq tutashuv (n³) o'rniga — teng kuchli «yulduz» qirralar va birlashtirish-topish (union-find):
  --   bir raqamda (ota, ona) sinfi ichidagi kartalar — sinf vakiliga; (ota, —) vakili — shu raqam va shu otali (ota, ona) vakillariga;
  --   (—, ona) vakili — shu raqam va shu onali (ota, ona) vakillariga. Bog'langan qismlar aynan juftlik qoidasi bilan bir xil, lekin bitta
  --   umumiy raqamli yuzlab karta (masalan ota ismi «-» va maktab raqami) ham ro'yxatni sekinlashtirmaydi (mustaqil tekshiruv).
  cph as (select c.cid, c.fp as ph, c.fk, c.mk from cards c where app.sales_valid(c.fp) and (c.fk <> '' or c.mk <> '')
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
  -- fok / mok — katakdan foydalanib bo'ladi (app.sales_usable): butun katak yoki uning biror qismi qo'ng'iroq qilib bo'ladigan raqam
  --   (bir nechta raqamli katakni sahifa alohida havolalarga ajratadi); karta raqami, JSHSHIR, yopishgan raqamlar — yo'q.
  --   fnd / mnd — ko'rsatiladigan (tozalangan) ism (app.sales_pname).
  fam0 as (select c.fn, c.fp, c.mn, c.mp, c.fr, c.mr, cp.root,
                  app.sales_pname(c.fn) as fnd, app.sales_pname(c.mn) as mnd,
                  (c.fp ~ '^998[0-9]{9}$' or app.sales_usable(c.fr)) as fok, (c.mp ~ '^998[0-9]{9}$' or app.sales_usable(c.mr)) as mok
             from cards c join comp cp on cp.cid = c.cid),
  -- fp_mom: shu oilada ona ismi yozilgan kartada ona raqami bo'lib turgan raqam. «Ota telefoni» katagidagi bunday raqam: ota ismi
  --   yozilmagan kartada — otaniki emas; ota ismi yozilgan kartada — faqat boshqa kartalarda otaning o'z raqami bo'lmasa (masalan
  --   oilaning umumiy raqami) ishlatiladi (fpt darajalari).
  mom as (select distinct y.root, y.mp from fam0 y where y.mn is not null),
  fam as (select f.*, (m.root is not null) as fp_mom from fam0 f left join mom m on m.root = f.root and m.mp = f.fp),
  -- Ism — oiladagi kartalarda eng ko'p uchragan tozalangan ism (izoh, raqam, qavs ichidagi matn — olib tashlangan).
  nm as (select fam.root,
                mode() within group (order by fam.fnd) filter (where fam.fnd is not null) as fn,
                mode() within group (order by fam.mnd) filter (where fam.mnd is not null) as mn
           from fam group by fam.root),
  -- Ota raqami — eng yaxshi darajadagi kartalardan, daraja ichida eng ko'p uchragani (teng bo'lsa — kichigi): foydalanib bo'ladigan
  --   katak (fok) — (1) ota ismi yozilgan karta, ona raqami emas; (2) ona raqami emas; (3) ota ismi yozilgan karta, ona raqami bilan
  --   bir xil (oilaning umumiy raqami); (4–6) noto'g'ri katak — xuddi shu tartibda. Ota ismi yozilmagan kartaning «ota telefoni»dagi ona
  --   raqami — nomzod emas. Shunday qilib ismli kartadagi «0» boshqa kartadagi to'g'ri raqamni yashirmaydi, ona raqami ota ismi yozilgan
  --   kartada bo'lsa ham boshqa kartadagi haqiqiy ota raqamidan ustun emas (mustaqil tekshiruv).
  fpt as (select fam.root, fam.fp,
                 case when fam.fn is not null and not fam.fp_mom then 1 when not fam.fp_mom then 2 else 3 end
                 + case when fam.fok then 0 else 3 end as t
            from fam where fam.fp <> '' and (fam.fn is not null or not fam.fp_mom)),
  fpc as (select distinct on (x.root) x.root, x.fp
            from (select fpt.root, fpt.fp, fpt.t, count(*) as n from fpt group by fpt.root, fpt.fp, fpt.t) x
           order by x.root, x.t, x.n desc, x.fp),
  -- Ona raqami — otanikidan farqlisi, xuddi shunday: (1) foydalanib bo'ladigan, ona ismi yozilgan karta; (2) foydalanib bo'ladigan;
  --   (3) noto'g'ri, ona ismi yozilgan; (4) noto'g'ri; (5) otaniki bilan bir xil (oilaning yagona umumiy raqami).
  mpt as (select fam.root, fam.mp,
                 case when fam.mp = coalesce(fpc.fp, '') then 5
                      when fam.mok and fam.mn is not null then 1
                      when fam.mok then 2
                      when fam.mn is not null then 3
                      else 4 end as t
            from fam left join fpc on fpc.root = fam.root where fam.mp <> ''),
  mpc as (select distinct on (x.root) x.root, x.mp
            from (select mpt.root, mpt.mp, mpt.t, count(*) as n from mpt group by mpt.root, mpt.mp, mpt.t) x
           order by x.root, x.t, x.n desc, x.mp),
  -- Ota raqami hali bo'sh (masalan aka-uka kartalarida raqamlar almashib yozilgan, ota ismi yo'q): tanlangan ona raqamidan boshqa
  --   foydalanib bo'ladigan «ota telefoni» — ikkala raqam ham chiqsin, ona raqami otaniki bo'lib takrorlanmasin.
  fpf as (select distinct on (x.root) x.root, x.fp
            from (select fam.root, fam.fp, count(*) as n from fam left join mpc on mpc.root = fam.root
                   where fam.fok and fam.fp <> coalesce(mpc.mp, '') group by fam.root, fam.fp) x
           order by x.root, x.n desc, x.fp),
  pick as materialized (select nm.root, nm.fn, coalesce(fpc.fp, fpf.fp, '') as fp, nm.mn, coalesce(mpc.mp, '') as mp
             from nm left join fpc on fpc.root = nm.root left join mpc on mpc.root = nm.root left join fpf on fpf.root = nm.root),
  -- Asl yozuv (noto'g'ri raqamni ochganda ko'rsatish uchun): tanlangan raqam yozilgan kartalardagi eng ko'p uchragan matn — har oila
  --   uchun alohida so'rov emas, bitta guruhlash (katta maktabda ham tez; mustaqil tekshiruv).
  frw as (select f.root, f.fp, mode() within group (order by f.fr) as fr from fam f where f.fp <> '' and f.fr <> '' group by f.root, f.fp),
  mrw as (select f.root, f.mp, mode() within group (order by f.mr) as mr from fam f where f.mp <> '' and f.mr <> '' group by f.root, f.mp)
  select left(encode(sha256(convert_to(k.salt || '|sales-v3|' || p.root, 'UTF8')), 'hex'), 32), p.fn, p.fp, p.mn, p.mp, frw.fr, mrw.mr
    from pick p
    left join frw on frw.root = p.root and frw.fp = p.fp
    left join mrw on mrw.root = p.root and mrw.mp = p.mp
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

-- 5) RPC'lar.
-- Ro'yxat: {ok, rows:[{k, father:{name, phone(niqob)}|null, mother:{…}|null}], total, limit, offset, todayUsed, dailyCap}.
create or replace function public.sales_contacts(p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
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
    select x.fkey, x.f_name, x.f_phone, x.m_name, x.m_phone,
           (x.f_name is null and x.m_name is null) as o1, app.sales_norm(coalesce(x.f_name, x.m_name)) as o2
      from app.sales_families(false) x
     where v_pat is null or app.sales_norm(x.f_name) like v_pat or app.sales_norm(x.m_name) like v_pat
  ), pg as (
    select * from f order by o1, o2, fkey limit v_lim offset v_off
  )
  select (select count(*) from f)::int,
         coalesce((select jsonb_agg(jsonb_build_object('k', pg.fkey,
                                                       'father', app.sales_parent(pg.f_name, pg.f_phone, true),
                                                       'mother', app.sales_parent(pg.m_name, pg.m_phone, true))
                                    order by pg.o1, pg.o2, pg.fkey) from pg), '[]'::jsonb)
    into v_total, v_rows;
  return jsonb_build_object('ok', true, 'rows', v_rows, 'total', v_total, 'limit', v_lim, 'offset', v_off,
                            'todayUsed', app.sales_used(), 'dailyCap', app.sales_cap());
end $$;
-- Ochish: {ok:true, k, father:{name, phone:'+99800…'}, mother, todayUsed, dailyCap} | {ok:false, reason:'daily_cap'|'not_found'}.
create or replace function public.sales_reveal(p_k text) returns jsonb
language plpgsql volatile security definer set search_path = public, app, pg_temp as $$
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
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
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
                           'app.sales_hasletter(text)', 'app.sales_dialable(text)', 'app.sales_segs(text)', 'app.sales_usable(text)', 'app.sales_pname(text)',
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
