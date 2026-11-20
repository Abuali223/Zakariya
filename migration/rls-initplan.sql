\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: rls-initplan.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- rls-initplan.sql — RLS rol tekshiruvlari har QATOR uchun emas, har SO'ROV uchun BIR MARTA.
--
--   MUAMMO (jonli saytda 2026-10-30 tekshiruvda aniqlandi): policy'lardagi app.is_admin(), app.is_hr(),
--   app.uid() ... chaqiruvlari Postgres'da HAR QATOR uchun qayta bajariladi (SECURITY DEFINER funksiya
--   «inline» qilinmaydi; har chaqiruv users jadvaliga alohida so'rov). Katta jadvalda bu juda qimmat:
--   staff_checkins'da (kamera hodisalari — barcha o'quvchi va xodimlarniki) mehmon (anon) yoki ota-ona
--   so'rovi bazaning 3 s vaqt chegarasiga urilib 500 (57014) qaytardi. Har shunday so'rov bazani soniyalab
--   band qiladi (istalgan odam qayta-qayta yuborsa — DoS), direktor sahifalari ham keraksiz sekin.
--   PG16 sinovi (300 ming qator): anon count(*) 9,7 s -> 0,025 s; direktor oylik so'rovi 252 ms -> 6 ms.
--
--   TUZATMA: ARGUMENTSIZ rol yordamchilarini skalyar subso'rovga o'raymiz: app.is_admin() ->
--   (SELECT app.is_admin()). Postgres uni InitPlan sifatida so'rov boshida BIR MARTA hisoblaydi
--   (Supabase'ning rasmiy RLS tavsiyasi — linter 0003 «auth_rls_initplan»). MA'NO O'ZGARMAYDI: bu
--   funksiyalar argumentsiz va STABLE — natija qatorga emas, faqat KIM so'rayotganiga bog'liq.
--   Qatorga bog'liq yordamchilar (owns_child(sid), is_kurator_for(ck) ...) TEGILMAYDI.
--
--   VAQT BO'YICHA SIZISH (rls-timing.sql, 2026-11-19): qatorga bog'liq egalik / sinf yordamchilari ham har QATOR uchun emas —
--   app.owns_child(x) / app.owns_student_doc(x) -> app.rls_in((SELECT app.my_child_sids() / my_student_docs()), x) (bir xil
--   to'plam, massiv a'zoligi); app.is_class_staff / can_write_general / is_teacher_for_class / is_homeroom_for / is_kurator_for /
--   teacher_has_subject / ann_can_write (x) -> app.rlsg_*((SELECT app.rls_class_staff()), x), ann_visible -> app.rlsg_ann_visible5 (bir martalik
--   to'plamlar: admin / O'IBDO', xodim sinflari, farzand sinflari — qatorlab funksiya yo'q).
--   O'ramlar «ichiga joylanadi» (inline): ota-ona / sotuvchi / boshqa rollar uchun qatorlab SECURITY DEFINER chaqiruvi qolmaydi
--   (sinf xodimi uchun — avvalgidek). Ma'no o'zgarmaydi (sinov: test-rls-timing.sql — to'plamlar barcha kalitlarda solishtiriladi).
--
--   QANDAY: zanjir OXIRIDA (barcha policy'lar o'z fayllarida yaratilgandan keyin) public sxemadagi har
--   policy ifodasi olinadi va ro'yxatdagi chaqiruvlar o'raladi; allaqachon o'ralganlari qayta o'ralmaydi.
--
--   ISTISNO — o'z policy'si subso'rovda O'ZINI (yoki halqa orqali o'zini) o'qiydigan jadvallar (hozir faqat
--   users: users_upd WITH CHECK «role = (select u.role from users u ...)»). Postgres policy'da subso'rov bo'lsa,
--   shu jadval allaqachon ochilgan bo'lsa «infinite recursion detected in policy» (42P17) deb to'xtaydi —
--   users_sel'ga o'ram (subso'rov) qo'shilsa, profilni saqlash (UPDATE users) buzilardi. Shuning uchun bunday
--   jadvallar avtomatik aniqlanadi va TEGILMAYDI (users kichik jadval — tezlikka ta'siri yo'q).
--   XAVFSIZLIK TO'RI: matndan ko'rinmaydigan halqa (security_invoker view, boshqa sxema orqali) uchun o'ralgan har
--   jadval «oddiy kirgan foydalanuvchi» (authenticated) nomidan EXPLAIN bilan sinanadi (hech narsa bajarilmaydi);
--   42P17 chiqsa — shu jadval policy'lari asl ko'rinishga qaytariladi va OGOHLANTIRISH chiqadi.
--   '...' satr va "..." nom ichidagi matn o'ralmaydi (masalan, «val <> 'app.is_admin()'» satri o'zgarmaydi).
--   Policy'larni avvalgidek o'z fayllarida ODDIY yozavering — bu fayl ularni har deploy'da o'zi o'raydi.
--   Ro'yxatga YANGI argumentsiz rol funksiyasi qo'shilsa — shu yerdagi v_fns'ga ham yozing (yozilmasa
--   faqat sekinroq ishlaydi, xavfsizlik o'zgarmaydi).
--
-- Idempotent — QAYTA ishga tushirishga xavfsiz. Zanjirda OXIRGI fayl bo'lishi SHART (chain.sh tekshiradi:
--   undan keyin qo'shilgan migratsiyaning policy'lari o'ralmay qolardi yoki yangi halqa 42P17 berardi).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- Ifoda matnida chaqiruvlarni FAQAT kod qismida o'raydi: '...' satr va "..." nom ichiga tegmaydi.
--   Bo'laklash matnni to'liq qoplamasa (kutilmagan ko'rinish) — matn o'zgarmaydi (xavfsiz tomonga).
create or replace function pg_temp.iqror_wrap_calls(src text, re text) returns text
language plpgsql immutable as $f$
declare tok text; v_out text := ''; v_cat text := '';
begin
  if src is null then return null; end if;
  for tok in select x[1] from regexp_matches(src, '([^''"]+|''(?:[^'']|'''')*''|"(?:[^"]|"")*")', 'g') x loop
    v_cat := v_cat || tok;
    if left(tok, 1) in ('''', '"') then v_out := v_out || tok;
    else v_out := v_out || regexp_replace(tok, re, '(SELECT app.\1())', 'g'); end if;
  end loop;
  if v_cat is distinct from src then return src; end if;
  return v_out;
end $f$;
-- Qatorga bog'liq egalik / sinf yordamchilarini «bir marta hisoblanadigan» o'ramlarga almashtiradi (faqat kod qismida; o'ramlar
--   rls-timing.sql da yaratiladi — bo'lmasa matn o'zgarmaydi). Allaqachon almashtirilgani qayta almashtirilmaydi (nom boshqa).
create or replace function pg_temp.iqror_prefix_calls(src text) returns text
language plpgsql stable as $f$
declare tok text; v_out text := ''; v_cat text := ''; m text[];
  v_map constant text[][] := array[
    ['owns_child',           'app.rls_in((SELECT app.my_child_sids()), '],
    ['owns_student_doc',     'app.rls_in((SELECT app.my_student_docs()), '],
    ['is_class_staff',       'app.rlsg_is_class_staff((SELECT app.rls_class_staff()), '],
    ['can_write_general',    'app.rlsg_can_write_general((SELECT app.rls_class_staff()), '],
    ['is_teacher_for_class', 'app.rlsg_is_teacher_for_class((SELECT app.rls_class_staff()), '],
    ['is_homeroom_for',      'app.rlsg_is_homeroom_for((SELECT app.rls_class_staff()), '],
    ['is_kurator_for',       'app.rlsg_is_kurator_for((SELECT app.rls_class_staff()), '],
    ['teacher_has_subject',  'app.rlsg_teacher_has_subject((SELECT app.rls_class_staff()), '],
    ['ann_can_write',        'app.rlsg_ann_can_write((SELECT app.rls_class_staff()), '],
    ['ann_visible',          'app.rlsg_ann_visible5((SELECT app.is_admin() OR app.is_zavuch()), (SELECT app.rls_ann_staff_keys()), (SELECT app.rls_ann_child_keys()), ']];
  i int;
begin
  if src is null then return null; end if;
  if to_regprocedure('app.rls_in(text[], text)') is null or to_regprocedure('app.rlsg_ann_visible5(boolean, text[], text[], jsonb, timestamp with time zone)') is null
     or to_regprocedure('app.my_child_sids()') is null or to_regprocedure('app.rls_ann_child_keys()') is null then
    return src;
  end if;
  for tok in select x[1] from regexp_matches(src, '([^''"]+|''(?:[^'']|'''')*''|"(?:[^"]|"")*")', 'g') x loop
    v_cat := v_cat || tok;
    if left(tok, 1) in ('''', '"') then v_out := v_out || tok;
    else
      for i in 1 .. array_length(v_map, 1) loop
        tok := regexp_replace(tok, '(?<![A-Za-z0-9_.])app\.' || v_map[i][1] || '\(', replace(v_map[i][2], '\', '\\'), 'g');
      end loop;
      v_out := v_out || tok;
    end if;
  end loop;
  if v_cat is distinct from src then return src; end if;
  return v_out;
end $f$;

do $$
declare
  -- Argumentsiz, qatorga bog'liq bo'lmagan rol yordamchilari (app sxemasi).
  v_fns constant text[] := array['uid','is_admin','is_admin_head','is_cashier','is_finance','is_hr',
                                 'is_marketing','is_reception','is_staff','is_zavuch','can_see_salary',
                                 'has_active_child','my_role','is_nurse','is_finance_mgr','is_notify_editor','role_set',
                                 'is_accountant','kassa_operator','fin_list2','kassa_reader'];
  v_ok text[]; v_re text; v_sp text := current_setting('search_path');
  v_skip text[]; r record; v_qual text; v_chk text; v_sql text;
  v_done text[] := '{}'; v_orig jsonb := '{}'; v_probe boolean; t text; c1 text; p jsonb;
  v_cur text; v_cur_ok boolean;
  -- Umumiy darvoza (app.rls_gate_any) qo'yiladigan policy: faqat shu yordamchilardan tuzilgan (rol / to'plam InitPlan'lari, rls_in, rlsg_*).
  v_gp text := '\(\s*SELECT\s+(?:app\.(?:is_admin|is_zavuch|is_finance|is_finance_mgr|is_cashier|is_reception|is_nurse|is_staff|rls_class_staff'
               || '|rls_ann_staff_keys|rls_ann_child_keys|my_child_sids|my_student_docs)\(\)'
               || '|\(app\.is_admin\(\) OR app\.is_zavuch\(\)\)|app\.is_admin\(\) OR app\.is_zavuch\(\))(?:\s+AS\s+[a-z_]+)?\s*\)';
  v_gc text := '(?:"(?:[^"]|"")+"|[a-z_][a-z0-9_]*)';
  v_rest text;
begin
  -- Faqat haqiqatan argumentsiz va VOLATILE bo'lmagan funksiyalar (volatile'ni bir marta hisoblash ma'noni o'zgartirardi).
  select array_agg(p.proname order by p.proname) into v_ok
    from pg_proc p
   where p.pronamespace = 'app'::regnamespace and p.proname = any(v_fns)
     and p.pronargs = 0 and p.provolatile in ('s', 'i');
  if v_ok is null then return; end if;
  -- (?<!SELECT ) — allaqachon o'ralgani ( «( SELECT app.is_admin() AS is_admin)» ) qayta o'ralmasin.
  v_re := '(?<!SELECT )app\.(' || array_to_string(v_ok, '|') || ')\(\)';

  -- Ifodalar TO'LIQ nomlar bilan (public./app.) chiqsin va shunday qayta o'qilsin — search_path'ga bog'liq emas.
  perform set_config('search_path', 'pg_catalog', true);
  -- Policy subso'rovlari qaysi jadvallarni o'qiydi (to'liq nom «public.x»; «public.f(» — funksiya, hisobga olinmaydi)
  --   -> o'zidan o'ziga yo'l (halqa) bor jadvallar o'ralmaydi (yuqoridagi ISTISNO).
  with recursive pol as (
    select c.relname::text as tbl,
           coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') as e
      from pg_policy p join pg_class c on c.oid = p.polrelid
     where c.relnamespace = 'public'::regnamespace
  ), edges as (
    select distinct pol.tbl as src, coalesce(replace(m[1], '""', '"'), m[2]) as dst
      from pol, regexp_matches(pol.e, 'public\.(?:"((?:[^"]|"")+)"|([a-z_][a-z0-9_]*)\M(?!\())', 'g') m
  ), reach(src, dst) as (
    select src, dst from edges
    union
    select r2.src, e2.dst from reach r2 join edges e2 on e2.src = r2.dst
  )
  select coalesce(array_agg(distinct src), '{}') into v_skip from reach where src = dst;

  for r in
    select p.polname, c.relname, p.polcmd,
           pg_get_expr(p.polqual, p.polrelid) as qual, pg_get_expr(p.polwithcheck, p.polrelid) as chk
      from pg_policy p join pg_class c on c.oid = p.polrelid
     where c.relnamespace = 'public'::regnamespace
       and c.relname::text <> all(v_skip)
       -- ALTER POLICY jadval egasini talab qiladi: boshqa rolga tegishli jadval (masalan, Studio'da qo'lda yaratilgan)
       --   tegilmaydi — aks holda butun deploy tranzaksiyasi «must be owner» bilan to'xtardi.
       and pg_has_role(c.relowner, 'USAGE')
     order by c.relname, p.polname
  loop
    -- Jadval qulfi KUTILMAYDI: zanjir boshqaradigan jadvallar shu tranzaksiyada allaqachon qulflangan (bir zumda o'tadi);
    --   qo'lda yaratilgan jadvalni boshqa ulanish band qilgan bo'lsa — kutmasdan o'tkazib yuboriladi (aks holda har
    --   policy 20 s kutib, shu vaqt davomida zanjir qulflagan asosiy jadvallar — butun sayt — to'xtab turardi).
    if r.relname::text is distinct from v_cur then
      v_cur := r.relname::text;
      begin
        execute format('lock table public.%I in access exclusive mode nowait', r.relname);
        v_cur_ok := true;
      exception when others then
        v_cur_ok := false;
        raise warning 'OGOHLANTIRISH: rls-initplan: % band (%) — policy''lari bu safar o''ralmadi (keyingi deployda o''raladi)', r.relname, sqlerrm;
      end;
    end if;
    continue when not v_cur_ok;
    v_qual := pg_temp.iqror_prefix_calls(pg_temp.iqror_wrap_calls(r.qual, v_re));
    v_chk  := pg_temp.iqror_prefix_calls(pg_temp.iqror_wrap_calls(r.chk,  v_re));
    -- Umumiy oldindan darvoza (3-mustaqil tekshiruv): SELECT / ALL policy'si FAQAT yuqoridagi yordamchilardan va kamida bitta qatorga
    --   bog'liq o'ramdan (rls_in / rlsg_*) iborat bo'lsa — «(SELECT app.rls_gate_any()) AND (…)». Darvoza nol narxli birinchi shart:
    --   huquqi yo'q foydalanuvchida qolgan shartlar (InitPlan'lar) hisoblanmaydi. Postgres RLS shartini One-Time Filter qilmaydi —
    --   darvoza birinchi qatorda bir marta hisoblanadi (indeksli kalit bo'yicha — faqat darvoza narxi, rls-timing.sql qoldiq izohi).
    --   Darvoza faqat AND / OR dan iborat policy'ga qo'yiladi (NOT / CASE bo'lsa — yo'q), shuning uchun u hech qachon qatorni yashirmaydi
    --   (test-rls-timing G03). Allaqachon darvozasi bor (rls_gate_) yoki boshqa shartli policy — tegilmaydi.
    if r.polcmd in ('r', '*') and v_qual is not null and v_qual !~ 'rls_gate_' and to_regprocedure('app.rls_gate_any()') is not null
       and v_qual ~ 'app\.(rls_in|rlsg_[a-z0-9_]+)\(' then
      v_rest := regexp_replace(v_qual, 'app\.rlsg_ann_visible5\(' || v_gp || ',\s*' || v_gp || ',\s*' || v_gp || ',\s*' || v_gc || ',\s*' || v_gc || '\)', ' X ', 'g');
      v_rest := regexp_replace(v_rest, 'app\.(?:rls_in|rlsg_[a-z0-9_]+)\(' || v_gp || ',\s*' || v_gc || '\)', ' X ', 'g');
      v_rest := regexp_replace(v_rest, v_gp, ' X ', 'g');
      if v_rest ~ '^(?:\s|\(|\)|X|\mOR\M|\mAND\M)*$' then
        v_qual := '(SELECT app.rls_gate_any()) AND (' || v_qual || ')';
      end if;
    end if;
    continue when v_qual is not distinct from r.qual and v_chk is not distinct from r.chk;
    v_sql := format('alter policy %I on public.%I', r.polname, r.relname);
    if r.qual is not null then v_sql := v_sql || format(' using (%s)', v_qual); end if;
    if r.chk  is not null then v_sql := v_sql || format(' with check (%s)', v_chk); end if;
    -- Bu fayl faqat TEZLIK uchun: o'rab bo'lmasa policy avvalgi (to'g'ri, sekinroq) ko'rinishda qoladi, deploy davom etadi.
    begin
      execute v_sql;
      v_orig := jsonb_set(v_orig, array[r.relname::text], coalesce(v_orig -> r.relname::text, '[]'::jsonb)
                  || jsonb_build_array(jsonb_build_object('pol', r.polname, 'qual', r.qual, 'chk', r.chk)));
      if not (r.relname::text = any(v_done)) then v_done := v_done || r.relname::text; end if;
    exception when others then
      raise warning 'OGOHLANTIRISH: rls-initplan: %.% o''ralmadi (%) — avvalgi ko''rinishda qoldi (xavfsizlik o''zgarmaydi, faqat sekinroq)',
        r.relname, r.polname, sqlerrm;
    end;
  end loop;

  -- XAVFSIZLIK TO'RI (yuqoridagi izoh): o'ralgan har jadval authenticated nomidan EXPLAIN qilinadi — rejalashtirish
  --   policy'larni ochadi (42P17 shu yerda chiqadi), so'rov bajarilmaydi. 42P17 -> asl matnlar qaytariladi.
  begin
    execute 'set local role authenticated'; execute 'reset role'; v_probe := true;
  exception when others then
    v_probe := false;
    raise warning 'OGOHLANTIRISH: rls-initplan: authenticated roliga o''tib bo''lmadi (%) — o''ramdan keyingi 42P17 sinovi o''tkazilmadi', sqlerrm;
  end;
  if v_probe then
    foreach t in array v_done loop
      select quote_ident(a.attname) into c1 from pg_attribute a
       where a.attrelid = ('public.' || quote_ident(t))::regclass and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
       order by a.attnum limit 1;
      for k in 1..2 loop
        begin
          execute 'set local role authenticated';
          execute format('explain select 1 from public.%I where false', t);
          execute format('explain update public.%I set %s = %s where false', t, c1, c1);
          execute format('explain delete from public.%I where false', t);
          execute format('explain insert into public.%I (%s) select %s from public.%I where false', t, c1, c1, t);
          execute 'reset role';
          exit;
        exception
          when sqlstate '42P17' then
            if k = 2 then
              raise warning 'OGOHLANTIRISH: rls-initplan: % — 42P17 asl policy''larda ham bor (oldindan mavjud, bu fayl sababchi emas)', t;
              exit;
            end if;
            for p in select * from jsonb_array_elements(v_orig -> t) loop
              execute format('alter policy %I on public.%I', p ->> 'pol', t)
                || case when p ->> 'qual' is not null then format(' using (%s)', p ->> 'qual') else '' end
                || case when p ->> 'chk' is not null then format(' with check (%s)', p ->> 'chk') else '' end;
            end loop;
            raise warning 'OGOHLANTIRISH: rls-initplan: % — o''ramdan keyin 42P17 (policy halqasi), asl ko''rinishga qaytarildi', t;
          when others then
            exit;   -- ruxsat yo'q va h.k. — halqa belgisi emas
        end;
      end loop;
    end loop;
  end if;
  perform set_config('search_path', v_sp, true);
end $$;

drop function if exists pg_temp.iqror_wrap_calls(text, text);
drop function if exists pg_temp.iqror_prefix_calls(text);

notify pgrst, 'reload schema';
