\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: rls-timing.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- rls-timing.sql — RLS orqali VAQT BO'YICHA SIZISHNI yopish (mustaqil tekshiruv 2026-11-19, SESSIYA-ISHLARI.md §85).
--
--   MUAMMO: PostgREST so'rovidagi filtr (eq / lt / gte / in …) — LEAKPROOF operatorlar; Postgres ularni RLS / security_barrier
--   shartidan OLDIN bajarishi mumkin. Shart har QATOR uchun SECURITY DEFINER funksiya chaqirsa (owns_child(sid),
--   owns_student_doc(id), is_class_staff(ck) …), javob vaqti filtrga mos (ko'rinmaydigan!) qatorlar soniga proporsional bo'ladi:
--   javob doim «[]», lekin vaqt bo'yicha ikkilik qidiruv bilan BOSHQA oilalarning telefon raqami, o'quvchi ismi, baho matni …
--   tiklanardi (anon kalit bilan ham — kalit sahifada ochiq). Bu sotuvchi rolining kunlik chegarasi va ochish jurnalini ham
--   chetlab o'tardi. student_phones'dagi security_barrier faqat regex / like (leakproof emas) variantini yopgan edi.
--
--   TUZATMA (ma'no o'zgarmaydi — sinov: test-rls-timing.sql):
--   1) anon (tizimga kirmagan) — faqat ochiq sayt kontentini o'qiydi; qolgan barcha jadval / ko'rinishlarda SELECT / UPDATE /
--      DELETE huquqi olinadi (INSERT — ariza / imtihon shakllari uchun — tegilmaydi). Yangi ochiq jadval kerak bo'lsa — v_pub
--      ro'yxatiga ongli ravishda qo'shiladi (sinov yopiq ro'yxatni tekshiradi).
--   2) Egalik va sinf tekshiruvlari har QATOR uchun emas, har SO'ROV uchun BIR MARTA: app.my_child_sids() / app.my_student_docs()
--      (owns_child / owns_student_doc bilan AYNAN bir xil to'plam) va app.rls_class_staff() (sinf funksiyalari faqat sinf xodimlari —
--      Direktor, ma'muriyat, O'IBDO', kurator, o'qituvchi — uchun rost bo'la oladi). rls-initplan.sql har deployda policy'lardagi
--      app.owns_child( / app.owns_student_doc( / sinf funksiyalarini shu yerdagi «ichiga joylanadigan» o'ramlarga almashtiradi:
--      Postgres ularni ifodaga ochib yuboradi (inline), natijada «InitPlan (bir marta) + massiv a'zoligi / mantiqiy AND» qoladi —
--      ota-ona va sotuvchi uchun qatorlab funksiya chaqiruvi yo'q.
--   3) Darvozalar: ko'ra oladigan hech narsasi yo'q foydalanuvchi (sotuvchi, farzandsiz ota-ona, users yozuvi yo'q seans, boshqa rollar)
--      uchun policy'ning BIRINCHI sharti yolg'on — qolgan shartlar hisoblanmaydi. student_private / students — o'z darvozasi
--      (rls_gate_private / rls_gate_students); qolgan, faqat rol / to'plam yordamchilaridan iborat SELECT policy'lar — umumiy
--      app.rls_gate_any() (rls-initplan har deployda qo'yadi). Ko'rinishlarda (student_phones, my_sick_notes, my_nurse_visits)
--      darvoza «One-Time Filter» — jadval umuman ko'rib chiqilmaydi. Barcha darvozalar BITTA so'rovli app.rls_acl() ustida (arzon).
--   4) my_sick_notes / my_nurse_visits (tibbiy ma'lumot) — xuddi shu o'ramlar bilan (sinf kaliti subso'rovi faqat sinf xodimi uchun).
--   5) rls-plpgsql.sql (keyingi fayl) — shu yordamchilar SQL dan plpgsql ga: reja seans davomida keshlanadi (3–7 marta tezroq).
--   Qoldiq (hujjatlashtirilgan, o'lchangan — 3-mustaqil tekshiruv, 2026-11-20): Postgres RLS shartidagi o'zgaruvchisiz shartni ham
--   qator filtri sifatida qoldiradi (One-Time Filter qilmaydi), InitPlan'lar esa «dangasa» — foydalanuvchi filtridan biror qator
--   o'tganda hisoblanadi. Shu sabab: (a) huquqsiz foydalanuvchi — telefon / ism / matn ustunlari (indeks yo'q) bo'yicha farq yo'q
--   (shovqin, ±10 mks); INDEKSLI kalit (studentId / hujjat id) bo'yicha «shu kalitli qator bormi?» — faqat darvoza narxi (~30–40 mks);
--   (b) farzandi bog'langan ota-ona va xodimlar — darvozadan o'tadi, policy'ning qolgan InitPlan'lari faqat mos qator bo'lsa
--   hisoblanadi: ~0,3 ms farq (avval 0,6–2,5 ms va har qanday hisob uchun). Masofadan o'lchash uchun ko'p ming so'rov kerak —
--   nginx'da so'rov chegarasi (limit_req) tavsiya etiladi. Sinf xodimlari uchun sinf funksiyalari qatorlab qoladi.
--   users jadvali — reports-roles.sql (users_upd o'ziga subso'rovsiz) + rls-initplan o'ramlari.
-- Idempotent — QAYTA ishga tushirishga xavfsiz. Zanjirda rls-initplan.sql dan OLDIN.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Egalik to'plamlari — owns_child(sid) / owns_student_doc(id) bilan AYNAN bir xil (sinov ikkalasini barcha kalitlarda solishtiradi).
--   owns_child(sid): faol, bloklanmagan hisobning faol bog'lanishi orqali (a) bog'langan o'quvchining hujjat id'si yoki studentId'si
--   (boshqa o'quvchida shu kalit bo'lmasa) yoki (b) hech bir o'quvchida yo'q kalitli bog'lanishning o'z kaliti.
create or replace function app.my_child_sids() returns text[]
language sql stable security definer set search_path = public, app, pg_temp as $$
  with cl as (
    select cc."studentId" as csid, app.claim_row(cc."studentId", cc.code) as doc
      from public.child_claims cc
     where app.uid() is not null and cc.uid = app.uid() and coalesce(nullif(cc.status, ''), 'active') = 'active'
       and not exists (select 1 from public.users u where u.id = cc.uid and u.status = 'blocked')
  ), own as (
    select distinct s.id, s."studentId" from public.students s join cl on s.id = cl.doc
  ), a as (
    select k.k from own o cross join lateral (values (o.id), (o."studentId")) k(k)
     where coalesce(k.k, '') <> ''
       and not exists (select 1 from public.students t where t.id <> o.id and (t.id = k.k or t."studentId" = k.k))
  ), b as (
    select cl.csid as k from cl
     where coalesce(cl.csid, '') <> ''
       and not exists (select 1 from public.students t where t.id = cl.csid or t."studentId" = cl.csid)
  )
  select coalesce(array_agg(distinct x.k), '{}'::text[]) from (select a.k from a union select b.k from b) x
$$;
-- owns_student_doc(id): id o'quvchi hujjati bo'lsa — bog'lanish (claim_row) aynan shu hujjatga; aks holda (eski, studentId kalitli
--   karta) — owns_child(id).
create or replace function app.my_student_docs() returns text[]
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(array_agg(distinct x.k), '{}'::text[]) from (
    select app.claim_row(cc."studentId", cc.code) as k
      from public.child_claims cc
     where app.uid() is not null and cc.uid = app.uid() and coalesce(nullif(cc.status, ''), 'active') = 'active'
       and not exists (select 1 from public.users u where u.id = cc.uid and u.status = 'blocked')
    union
    select m.k from unnest(app.my_child_sids()) m(k) where not exists (select 1 from public.students s0 where s0.id = m.k)
  ) x where x.k is not null
$$;
-- Sinf funksiyalari (is_class_staff, can_write_general, is_teacher_for_class, is_homeroom_for, is_kurator_for, ann_can_write,
--   teacher_has_subject — policy'larda doim o'qituvchi tekshiruvi bilan birga) faqat shu rollarda rost bo'la oladi — ustma-ust to'plam.
create or replace function app.rls_class_staff() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.uid() is not null and (app.is_admin() or app.role_set() && array['director', 'admin', 'zavuch', 'kurator', 'teacher']::text[])
$$;
-- ann_visible: Direktor, O'IBDO', xodim yoki faol farzandi bor ota-ona (o'zidan ham kengroq — ustma-ust to'plam).
create or replace function app.rls_ann_gate() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.uid() is not null and (app.is_admin() or app.is_zavuch() or app.is_staff() or cardinality(app.my_child_class_keys()) > 0)
$$;
-- Darvozalar uchun foydalanuvchi «imkoniyatlari» — BITTA so'rov (darvoza har so'rovda birinchi hisoblanadi, shuning uchun arzon bo'lishi
--   shart; avvalgi darvozalar 6 ta ichma-ich funksiya chaqirib ~150 mks olardi, indeksli kalit bo'yicha shu farq ko'rinardi):
--     'director*' — is_admin (role = 'director', holatdan qat'i nazar, app.is_admin bilan bir xil);
--     faol hisobning rollari — app.role_set() qoidasi (asosiy rol; director / parent / student / accountant / sales dan boshqa asosiy
--       rolda extraRoles ham — bu yerda ruxsat ro'yxatisiz, ya'ni kengroq);
--     'child*' — faol, bloklanmagan hisobning faol bog'lanishi bor (my_child_sids / my_student_docs / my_child_class_keys bo'sh
--       bo'lmasligining zaruriy sharti — kengroq).
--   Darvoza faqat USTMA-UST to'plam bo'lishi kerak (kengroq bo'lsa — faqat qolgan shartlar hisoblanadi; tor bo'lsa — qator yo'qoladi):
--   test-rls-timing G03 har policy'ning har InitPlan'i uchun «darvoza yolg'on => InitPlan yolg'on / bo'sh» ni barcha rollarda tekshiradi.
create or replace function app.rls_acl() returns text[]
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.uid() is null then '{}'::text[] else
    coalesce((select case when u.role = 'director' then array['director*'] else '{}'::text[] end
                     || case when coalesce(nullif(u.status, ''), 'active') <> 'active' or coalesce(u.role, '') = '' then '{}'::text[]
                             when u.role in ('director', 'parent', 'student', 'accountant', 'sales') then array[u.role]
                             else array[u.role] || array(select e from jsonb_array_elements_text(
                                    case when jsonb_typeof(u."extraRoles") = 'array' then u."extraRoles" else '[]'::jsonb end) e) end
                from public.users u where u.id = app.uid()), '{}'::text[])
    || case when exists (select 1 from public.child_claims cc
                          where cc.uid = app.uid() and coalesce(nullif(cc.status, ''), 'active') = 'active'
                            and not exists (select 1 from public.users b where b.id = cc.uid and b.status = 'blocked'))
            then array['child*'] else '{}'::text[] end
  end
$$;
-- Oldindan darvozalar (3-band): policy'ning har bir tarmog'i rost bo'la oladigan foydalanuvchilar (ustma-ust to'plam).
--   rls_gate_private: Direktor, O'IBDO', qabulxona, farzand bog'lanishi (my_student_docs);
--   rls_gate_students: + sinf xodimlari (rls_class_staff: Direktor, ma'muriyat, O'IBDO', kurator, o'qituvchi);
--   rls_gate_phones: + moliya (is_finance: Direktor, moliya menejeri, g'aznachi) va kassir;
--   rls_gate_health: farzand bog'lanishi (my_child_sids) yoki sinf xodimi.
create or replace function app.rls_gate_private() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.rls_acl() && array['director*', 'zavuch', 'reception', 'child*']::text[]
$$;
create or replace function app.rls_gate_students() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.rls_acl() && array['director*', 'zavuch', 'reception', 'child*', 'director', 'admin', 'kurator', 'teacher']::text[]
$$;
create or replace function app.rls_gate_phones() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.rls_acl() && array['director*', 'zavuch', 'reception', 'child*', 'director', 'finance_mgr', 'treasurer', 'kassir']::text[]
$$;
create or replace function app.rls_gate_health() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.rls_acl() && array['child*', 'director*', 'director', 'admin', 'zavuch', 'kurator', 'teacher']::text[]
$$;
-- Umumiy oldindan darvoza (3-mustaqil tekshiruv; rls-initplan har deployda qo'yadi): policy faqat rol yordamchilari, app.rls_in va
--   app.rlsg_* dan iborat bo'lsa — hech qanday huquqi yo'q foydalanuvchi (sotuvchi, farzandsiz ota-ona, users yozuvi yo'q yangi / anonim
--   seans) uchun YOLG'ON: qolgan shartlar hisoblanmaydi. Ustma-ust to'plam: Direktor (holatdan qat'i nazar), ota-ona / sotuvchi /
--   o'quvchidan boshqa har qanday faol rol, farzand bog'lanishi.
create or replace function app.rls_gate_any() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select exists (select 1 from unnest(app.rls_acl()) r where r not in ('parent', 'sales', 'student'))
$$;
-- «Ichiga joylanadigan» o'ramlar (LANGUAGE sql, SECURITY DEFINER ham, SET ham YO'Q — aks holda Postgres ochib yubormaydi).
--   Birinchi argument — chaqiruvchi yozadigan «(SELECT …)» (InitPlan, so'rovda bir marta); qatorga faqat massiv a'zoligi / AND qoladi.
create or replace function app.rls_in(p_set text[], p_key text) returns boolean
language sql stable as $$ select coalesce($2 = any(coalesce($1, '{}'::text[])), false) $$;
create or replace function app.rlsg_is_class_staff(p_gate boolean, p_ck text) returns boolean
language sql stable as $$ select $1 and app.is_class_staff($2) $$;
create or replace function app.rlsg_can_write_general(p_gate boolean, p_ck text) returns boolean
language sql stable as $$ select $1 and app.can_write_general($2) $$;
create or replace function app.rlsg_is_teacher_for_class(p_gate boolean, p_ck text) returns boolean
language sql stable as $$ select $1 and app.is_teacher_for_class($2) $$;
create or replace function app.rlsg_is_homeroom_for(p_gate boolean, p_ck text) returns boolean
language sql stable as $$ select $1 and app.is_homeroom_for($2) $$;
create or replace function app.rlsg_is_kurator_for(p_gate boolean, p_ck text) returns boolean
language sql stable as $$ select $1 and app.is_kurator_for($2) $$;
create or replace function app.rlsg_teacher_has_subject(p_gate boolean, p_subj text) returns boolean
language sql stable as $$ select $1 and app.teacher_has_subject($2) $$;
create or replace function app.rlsg_ann_can_write(p_gate boolean, p_keys jsonb) returns boolean
language sql stable as $$ select $1 and app.ann_can_write($2) $$;
create or replace function app.rlsg_ann_visible(p_gate boolean, p_keys jsonb, p_exp timestamptz) returns boolean
language sql stable as $$ select $1 and app.ann_visible($2, $3) $$;
-- ann_visible (e'lon kimga ko'rinadi) — QATORLAB funksiyasiz (3-mustaqil tekshiruv): avvalgi o'ram (rls_ann_gate bilan) farzandli ota-ona va
--   har qanday xodim uchun har qatorda SECURITY DEFINER ann_visible() chaqirardi — javob vaqti boshqa sinflarning yashirin e'lonlari
--   soniga proporsional edi (va minglab e'lon bo'lsa — sekinlashardi). Endi foydalanuvchi to'plamlari so'rov boshida bir marta:
--   Direktor / O'IBDO' (rost / yolg'on), xodim sinflari va farzand sinflari ('all' bilan; huquq yo'q — bo'sh) — qatorga faqat jsonb ?|
--   qoladi. Ma'no app.ann_visible bilan bir xil (classKeys satr elementlari; test-rls-timing E04 barcha rol / kalitda solishtiradi).
create or replace function app.rls_ann_staff_keys() returns text[]
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.is_staff() then array['all'] || (
           select case jsonb_typeof(j)
                    when 'array'  then array(select e #>> '{}' from jsonb_array_elements(j) e where jsonb_typeof(e) = 'string')
                    when 'object' then array(select jsonb_object_keys(j))
                    when 'string' then array[j #>> '{}']
                    else '{}'::text[] end
             from (select app.my_staff_class_keys() as j) s)
         else '{}'::text[] end
$$;
create or replace function app.rls_ann_child_keys() returns text[]
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when cardinality(k) > 0 then array['all'] || k else '{}'::text[] end from (select app.my_child_class_keys() as k) s
$$;
-- $1 … $3 — chaqiruvchi yozadigan «(SELECT …)» (InitPlan): har biri tanada BIR marta (ikki marta bo'lsa Postgres ichiga joylamaydi).
create or replace function app.rlsg_ann_visible5(p_adm boolean, p_staff text[], p_child text[], p_keys jsonb, p_exp timestamptz) returns boolean
language sql stable as $$ select $1 or (jsonb_typeof($4) = 'array' and ($4 ?| $2 or (($5 is null or $5 > now()) and $4 ?| $3))) $$;
do $$ declare f text; begin
  foreach f in array array['app.my_child_sids()', 'app.my_student_docs()', 'app.rls_class_staff()', 'app.rls_ann_gate()',
                           'app.rls_gate_private()', 'app.rls_gate_students()', 'app.rls_gate_phones()', 'app.rls_gate_health()',
                           'app.rls_gate_any()', 'app.rls_acl()', 'app.rls_in(text[], text)', 'app.rlsg_is_class_staff(boolean, text)', 'app.rlsg_can_write_general(boolean, text)',
                           'app.rlsg_is_teacher_for_class(boolean, text)', 'app.rlsg_is_homeroom_for(boolean, text)',
                           'app.rlsg_is_kurator_for(boolean, text)', 'app.rlsg_teacher_has_subject(boolean, text)',
                           'app.rlsg_ann_can_write(boolean, jsonb)', 'app.rlsg_ann_visible(boolean, jsonb, timestamp with time zone)',
                           'app.rls_ann_staff_keys()', 'app.rls_ann_child_keys()',
                           'app.rlsg_ann_visible5(boolean, text[], text[], jsonb, timestamp with time zone)'] loop
    execute 'revoke all on function ' || f || ' from public, anon';
    execute 'grant execute on function ' || f || ' to authenticated, service_role';
  end loop;
end $$;

-- 2) Oldindan darvoza: student_private (priv_sel) va students (students_sel) — oxirgi ta'rif o'z faylida yaratilgandan keyin har
--   deployda qo'shiladi (allaqachon bo'lsa — tegilmaydi). Darvoza YOLG'ON bo'lsa — jadval ko'rib chiqilmaydi (One-Time Filter).
do $$ declare r record; v_gate text; begin
  for r in select c.relname, p.polname, pg_get_expr(p.polqual, p.polrelid) as qual
             from pg_policy p join pg_class c on c.oid = p.polrelid
            where c.relnamespace = 'public'::regnamespace
              and (c.relname, p.polname) in (('student_private', 'priv_sel'), ('students', 'students_sel')) loop
    v_gate := case r.relname when 'student_private' then 'app.rls_gate_private()' else 'app.rls_gate_students()' end;
    continue when r.qual is null or strpos(r.qual, v_gate) > 0;
    execute format('alter policy %I on public.%I using ((SELECT %s) AND (%s))', r.polname, r.relname, v_gate, r.qual);
  end loop;
end $$;

-- 3) student_phones (oxirgi ta'rif — reception-access.sql dan keyin shu yerda): darvoza + rol tekshiruvlari bir marta (qabulxona /
--   kassir telefon qidiruvi ham tezlashadi — avval har qatorda 5 ta funksiya chaqirilardi) + egalik — massiv a'zoligi.
create or replace view public.student_phones with (security_barrier = true) as
  select id, "parentPhone", "parentPhone2"
  from public.student_private
  where (select app.rls_gate_phones())
    and ((select app.is_admin()) or (select app.is_zavuch()) or (select app.is_finance()) or (select app.is_cashier())
         or (select app.is_reception()) or app.rls_in((select app.my_student_docs()), id));
revoke all on public.student_phones from anon;
grant select on public.student_phones to authenticated, service_role;

-- 4) Tibbiy ko'rinishlar (oxirgi ta'rif — nurse-sick.sql dan keyin shu yerda; ustunlar — o'sha tartibda).
create or replace view public.my_sick_notes with (security_barrier = true) as
  select n.id, n."studentId", n."fromDay", n."toDay", n."schoolDays", n.status, n.late, n."enteredAt", n."reviewedAt",
         case when app.rls_in((select app.my_child_sids()), n."studentId") then n."reviewNote" end as "reviewNote",
         case when app.rls_in((select app.my_child_sids()), n."studentId") then n.institution end as institution,
         case when app.rls_in((select app.my_child_sids()), n."studentId") then n."noteNumber" end as "noteNumber",
         (select count(*) from jsonb_object_keys(n."appliedDays"))::int as "appliedCount"
    from public.sick_notes n
   where (select app.rls_gate_health())
     and n.status <> 'withdrawn'
     and (app.rls_in((select app.my_child_sids()), n."studentId")
          or app.rlsg_is_homeroom_for((select app.rls_class_staff()),
               (select app.student_class_key(s.lang, s.grade, s."classLetter", s.track) from public.students s
                 where s."studentId" = n."studentId" or s.id = n."studentId" order by (s."studentId" = n."studentId") desc limit 1))
          or app.rlsg_is_kurator_for((select app.rls_class_staff()),
               (select app.student_class_key(s.lang, s.grade, s."classLetter", s.track) from public.students s
                 where s."studentId" = n."studentId" or s.id = n."studentId" order by (s."studentId" = n."studentId") desc limit 1)));
revoke all on public.my_sick_notes from anon;
grant select on public.my_sick_notes to authenticated, service_role;
create or replace view public.my_nurse_visits with (security_barrier = true) as
  select v.id, v."studentId", v.at, v.action, v."parentNotified",
         case when app.rls_in((select app.my_child_sids()), v."studentId") then v.complaint end as complaint,
         case when app.rls_in((select app.my_child_sids()), v."studentId") then v.temperature end as temperature
    from public.nurse_visits v
   where (select app.rls_gate_health())
     and (app.rls_in((select app.my_child_sids()), v."studentId")
          or app.rlsg_is_homeroom_for((select app.rls_class_staff()),
               (select app.student_class_key(s.lang, s.grade, s."classLetter", s.track) from public.students s
                 where s."studentId" = v."studentId" or s.id = v."studentId" order by (s."studentId" = v."studentId") desc limit 1))
          or app.rlsg_is_kurator_for((select app.rls_class_staff()),
               (select app.student_class_key(s.lang, s.grade, s."classLetter", s.track) from public.students s
                 where s."studentId" = v."studentId" or s.id = v."studentId" order by (s."studentId" = v."studentId") desc limit 1)));
revoke all on public.my_nurse_visits from anon;
grant select on public.my_nurse_visits to authenticated, service_role;

-- 5) anon — faqat ochiq sayt kontenti (index.html ochiq bo'limlari, imtihon / haydovchi sahifalari). Qolgan har jadval / ko'rinish:
--   SELECT / UPDATE / DELETE olinadi (RLS ularni baribir bo'sh qaytarardi — endi vaqt bo'yicha ham hech narsa bilib bo'lmaydi).
--   INSERT tegilmaydi (ariza: enrollments, applications — RLS bilan). config — ochiq hujjatlar (to'lov / AI sozlamasi) uchun qoladi.
do $$
declare r record;
  v_pub constant text[] := array['achievements_school', 'achievements_students', 'admission_steps', 'bus_routes_public', 'classes', 'config',
                                 'events', 'exam_questions', 'exams', 'faq', 'gallery', 'news', 'plans', 'settings', 'teachers_public',
                                 'testimonials'];
begin
  for r in select c.relname from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'f')
              and not (c.relname = any(v_pub))
              and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'UPDATE')
                   or has_table_privilege('anon', c.oid, 'DELETE'))
  loop
    execute format('revoke select, update, delete on public.%I from anon', r.relname);
  end loop;
end $$;

notify pgrst, 'reload schema';
