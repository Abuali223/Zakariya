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
--       sales_contacts(q, limit, offset) — faol o'quvchilar OILALARI: aka-uka bitta oila (kanonik raqamlar — app.tg_phone — grafi:
--         umumiy raqamli kartalar bitta oila, raqamlar almashib yozilgan bo'lsa ham); har oila: ota va ona — ism + NIQOBLANGAN telefon
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
-- To'g'ri raqam: O'zbekiston (998 + 9 raqam) yoki boshqa mamlakat (10–15 raqam, E.164). Aks holda (bir katakda ikki raqam, qisqa,
--   aralash matn) — noto'g'ri: «+» va tel: havolasiz ko'rsatiladi (mustaqil tekshiruv).
create or replace function app.sales_valid(p text) returns boolean
language sql immutable set search_path = pg_catalog as $$
  select coalesce(p, '') ~ '^998[0-9]{9}$' or (coalesce(p, '') ~ '^[1-9][0-9]{9,14}$' and left(p, 3) <> '998')
$$;
-- Niqob (kanonik raqamdan): O'zbekiston 998001234567 -> «+998 00 *** ** 67»; boshqa mamlakat va noto'g'ri raqam — faqat oxirgi 2 raqam.
create or replace function app.sales_mask(p text) returns text
language sql immutable set search_path = pg_catalog as $$
  select case when coalesce(p, '') = '' then null
              when p ~ '^998[0-9]{9}$' then '+' || left(p, 3) || ' ' || substr(p, 4, 2) || ' *** ** ' || right(p, 2)
              when length(p) >= 5 then '*** ** ' || right(p, 2)
              else '***' end
$$;
-- Ota yoki ona: {name, phone, valid} (ism ham, raqam ham bo'lmasa — null). p_mask — niqoblangan; aks holda to'g'ri raqam «+998001234567»,
--   noto'g'risi — raqamlarning o'zi («+»siz; sahifa uni tel: havolasiz ko'rsatadi).
create or replace function app.sales_parent(p_name text, p_phone text, p_mask boolean) returns jsonb
language sql immutable set search_path = public, app, pg_temp as $$
  select case when p_name is null and coalesce(p_phone, '') = '' then null
              else jsonb_build_object('name', p_name,
                     'phone', case when coalesce(p_phone, '') = '' then null
                                   when p_mask then app.sales_mask(p_phone)
                                   when app.sales_valid(p_phone) then '+' || p_phone
                                   else p_phone end,
                     'valid', case when coalesce(p_phone, '') = '' then null else app.sales_valid(p_phone) end) end
$$;
-- Oilalar: faol o'quvchilar (p_all — arxivdagilar ham: faqat Direktor jurnalidagi ismlar uchun). Oila — raqamlar grafining bog'langan
--   qismi: bitta kartadagi ota va ona raqami bog'langan, umumiy raqamli kartalar — bitta oila (aka-uka kartalarida raqamlar almashib
--   yozilgan yoki birida ona raqami yo'q bo'lsa ham — bitta qator, kunlik chegaradan bitta o'rin; mustaqil tekshiruv). Raqamsiz oila — yo'q.
--   Ism va raqam — oiladagi kartalarda eng ko'p uchragani. Kalit — oiladagi eng kichik raqam (tuz bilan sha256). Shaxsiy karta — o'quvchi
--   hujjat id'si bilan (eski yozuv — studentId kalitli, boshqa o'quvchining hujjati bo'lmasa; app.tg_card_phones bilan bir xil qoida).
create or replace function app.sales_families(p_all boolean default false)
returns table(fkey text, f_name text, f_phone text, m_name text, m_phone text)
language sql stable set search_path = public, app, pg_temp as $$
  with recursive st as (
    select nullif(btrim(coalesce(p."fatherName", '')), '') as fn, app.tg_phone(p."parentPhone") as fp,
           nullif(btrim(coalesce(p."motherName", '')), '') as mn, app.tg_phone(p."parentPhone2") as mp
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
  cards as (select fn, fp, mn, mp from st where fp <> '' or mp <> ''),
  edges as (select fp as a, coalesce(nullif(mp, ''), fp) as b from cards where fp <> ''
            union select mp, coalesce(nullif(fp, ''), mp) from cards where mp <> ''),
  sym as (select a, b from edges union select b, a from edges),
  reach (a, b) as (select a, b from sym union select r.a, e.b from reach r join sym e on e.a = r.b),
  comp as (select a as phone, min(b) as root from reach group by a),
  fam as (select c.fn, c.fp, c.mn, c.mp, coalesce(cf.root, cm.root) as root
            from cards c left join comp cf on c.fp <> '' and cf.phone = c.fp left join comp cm on c.mp <> '' and cm.phone = c.mp),
  agg as (select fam.root,
                 mode() within group (order by fam.fn) filter (where fam.fn is not null) as fn,
                 coalesce(mode() within group (order by fam.fp) filter (where fam.fp <> ''), '') as fp,
                 mode() within group (order by fam.mn) filter (where fam.mn is not null) as mn
            from fam group by fam.root)
  -- Ona raqami — otaniki bilan bir xil bo'lmagani (raqamlar almashib yozilgan kartalarda ikkala raqam ham ko'rinsin); boshqasi bo'lmasa — o'zi.
  select left(encode(sha256(convert_to(k.salt || '|sales-v2|' || a.root, 'UTF8')), 'hex'), 32), a.fn, a.fp, a.mn,
         coalesce((select mode() within group (order by x.mp) from fam x where x.root = a.root and x.mp <> '' and x.mp <> a.fp),
                  (select mode() within group (order by x.mp) from fam x where x.root = a.root and x.mp <> ''), '')
    from agg a cross join (select s.salt from app.sales_secret s where s.id = 1) k
$$;
-- Bugun shu foydalanuvchi ochgan oilalar soni.
create or replace function app.sales_used() returns int
language sql stable set search_path = public, app, pg_temp as $$
  select count(*)::int from public.sales_contact_log l where l.uid = app.uid() and l.day = app.fin_today()
$$;
-- Jurnaldagi foydalanuvchi nomi (hisob o'chirilgan bo'lsa — uid).
create or replace function app.sales_user_name(p_uid text) returns text
language sql stable set search_path = public, app, pg_temp as $$
  select coalesce((select coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), nullif(btrim(u.phone), ''))
                     from public.users u where u.id = p_uid), p_uid)
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
    insert into public.sales_contact_log (uid, fkey, day) values (v_uid, v_k, v_day) on conflict (uid, fkey, day) do nothing;
  end if;
  select count(*) into v_used from public.sales_contact_log l where l.uid = v_uid and l.day = v_day;
  return jsonb_build_object('ok', true, 'k', v_k,
                            'father', app.sales_parent(v_f.f_name, v_f.f_phone, false),
                            'mother', app.sales_parent(v_f.m_name, v_f.m_phone, false),
                            'todayUsed', v_used, 'dailyCap', v_cap);
end $$;
-- Direktor jurnali: {ok, from, to, dailyCap, days:[{day, uid, name, role, count}], recent:[{at, day, uid, name, role, father, mother}]}
--   — kunlar p_days (1…366) oralig'ida; recent — oxirgi 200 ochish (ota-ona ismi — hozirgi kartadan; raqam o'zgargan bo'lsa — bo'sh).
create or replace function public.sales_log(p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_days int := least(greatest(coalesce(p_days, 30), 1), 366); v_to date; v_from date;
begin
  if app.uid() is null then raise exception 'Tizimga kiring' using errcode = '42501'; end if;
  if not app.is_admin() then raise exception 'Ruxsat yo''q: sotuvchilar jurnalini faqat Direktor ko''radi' using errcode = '42501'; end if;
  v_to := app.fin_today(); v_from := v_to - (v_days - 1);
  return jsonb_build_object('ok', true, 'from', v_from, 'to', v_to, 'dailyCap', app.sales_cap(),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', d.day, 'uid', d.uid, 'name', app.sales_user_name(d.uid),
                                                          'role', (select u.role from public.users u where u.id = d.uid), 'count', d.n)
                                       order by d.day desc, d.n desc, d.uid)
                        from (select l.day, l.uid, count(*)::int as n from public.sales_contact_log l
                               where l.day between v_from and v_to group by l.day, l.uid) d), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', r."createdAt", 'day', r.day, 'uid', r.uid, 'name', app.sales_user_name(r.uid),
                                                            'role', (select u.role from public.users u where u.id = r.uid),
                                                            'father', f.f_name, 'mother', f.m_name)
                                         order by r."createdAt" desc, r.id desc)
                          from (select l.* from public.sales_contact_log l order by l."createdAt" desc, l.id desc limit 200) r
                          left join app.sales_families(true) f on f.fkey = r.fkey), '[]'::jsonb));
end $$;

do $$ declare f text; begin
  foreach f in array array['public.sales_contacts(text, integer, integer)', 'public.sales_reveal(text)', 'public.sales_log(integer)'] loop
    execute 'revoke all on function ' || f || ' from public, anon';
    execute 'grant execute on function ' || f || ' to authenticated, service_role';
  end loop;
  foreach f in array array['app.sales_cap()', 'app.sales_need()', 'app.sales_norm(text)', 'app.sales_valid(text)', 'app.sales_mask(text)',
                           'app.sales_parent(text, text, boolean)', 'app.sales_families(boolean)', 'app.sales_used()', 'app.sales_user_name(text)'] loop
    execute 'revoke all on function ' || f || ' from public, anon, authenticated';
  end loop;
end $$;

-- 6) «Sotuvchi» hisobida farzand bog'lanishi bo'lmaydi (mustaqil tekshiruv): rol «Sotuvchi»ga o'zgarganda (yoki shunday yaratilganda) faol /
--    kutilayotgan bog'lanishlar bekor qilinadi ('revoked' — o'chirilmaydi; rol qaytsa, ota-ona kod bilan qayta bog'laydi). Yangi bog'lanish —
--    claim_child (payer-code-mask.sql) va child_claim_staff_gate (audit-11-elon.sql) rad etadi. Bir martalik tozalash — idempotent.
create or replace function app.users_sales_claims() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if coalesce(new.role, '') = 'sales' and (tg_op = 'INSERT' or coalesce(old.role, '') <> 'sales') then
    update public.child_claims set status = 'revoked', "updatedAt" = now()
     where uid = new.id and coalesce(nullif(status, ''), 'active') <> 'revoked';
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
