\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: rls-plpgsql.sql ALOHIDA ishga tushirilmaydi — u zanjirdagi oxirgi ta''riflarni o''giradi (alohida ishlatilsa eski ta''riflar o''giriladi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- rls-plpgsql.sql — RLS yordamchi funksiyalari: SQL -> plpgsql (reja keshlanadi). rls-initplan.sql dan OLDIN (run-all.sql), har deployda.
--
-- Nima uchun (3-mustaqil tekshiruv, 2026-11-20): policy'lardagi yordamchilar — app.role_set(), app.is_admin(), app.my_child_sids(),
--   app.my_student_docs(), app.rls_gate_*() … — SECURITY DEFINER va SET search_path li SQL funksiyalar. Bunday SQL funksiya ichiga
--   joylanmaydi va uning so'rovi har chaqiruvda (so'rov boshiga bir marta — InitPlan'da ham) qaytadan tahlil qilinib REJALANADI:
--   bir chaqiruv 0,1–2 ms. PostgREST filtri (leakproof) RLS shartidan oldin bajariladi, shartdagi InitPlan'lar esa «dangasa» — faqat
--   filtrdan biror qator o'tganda hisoblanadi. Natijada «filtrga mos yashirin qator bormi?» savoliga javob vaqti 0,6–2,5 ms farq
--   qilardi (tizimga kirgan istalgan hisob, hatto yangi ro'yxatdan o'tgan yoki anonim seans ham; ota-ona — telefon / ism ustunlarida).
--   plpgsql funksiyaning so'rov rejasi seans davomida keshlanadi — bir chaqiruv o'nlab mikrosoniya; farq shuncha kamayadi.
--
-- Qanday: quyidagi ro'yxatdagi har funksiyaning JORIY (zanjirdagi oxirgi) ta'rifi olinadi va aynan o'sha tana plpgsql'ga o'raladi:
--     #variable_conflict use_column   -- SQL funksiyadagi kabi: ustun nomi parametr nomidan ustun
--     begin return ( <aynan o'sha SELECT / WITH> ); end
--   Imzo, qaytish turi, STABLE, SECURITY DEFINER, SET search_path, huquqlar (ACL) va egasi — o'zgarmaydi (CREATE OR REPLACE).
--   Mantiq o'zgarmaydi: ro'yxatdagi tanalarning hammasi BITTA qator qaytaradi (FROM'siz SELECT, GROUP BY'siz agregat yoki birlamchi
--   kalit bo'yicha skalyar subso'rov) — qator bo'lmasa ikkalasi ham NULL. Tana bir nechta qator qaytarsa plpgsql XATO beradi (SQL
--   funksiya birinchisini olardi) — xavfsizlik funksiyasi uchun «yopiq» xato; ro'yxatga funksiya qo'shilganda shuni tekshiring.
--   STABLE plpgsql ham chaqirgan so'rovning snapshot'ini ishlatadi. Asl ta'riflar o'z fayllarida qoladi (ular o'zgarsa — bu fayl
--   keyingi deployda yangi tanani o'giradi). Ro'yxatdagi funksiya bu zanjirda yo'q bo'lsa (masalan faqat --dev) — o'tkazib yuboriladi;
--   allaqachon plpgsql bo'lsa — tegilmaydi (qayta ishga tushirish xavfsiz). Tanasi bitta SELECT / WITH bo'lmasa — deploy to'xtaydi
--   (jim noto'g'ri o'girish o'rniga).
--   Ichiga joylanadigan o'ramlar (app.rls_in, app.rlsg_*) va app.uid() — SQL bo'lib qoladi (ular inline bo'lishi shart).
-- =====================================================================
do $rp$
declare
  f text; v_oid oid; v_lang text; v_src text; v_def text; v_pos int; v_new text; n int := 0;
begin
  foreach f in array array[
    'app.role_set()', 'app.is_admin()', 'app.is_zavuch()', 'app.is_reception()', 'app.is_finance()', 'app.is_finance_mgr()',
    'app.is_cashier()', 'app.is_staff()', 'app.is_nurse()', 'app.is_hr()', 'app.is_accountant()', 'app.is_marketing()',
    'app.is_admin_head()', 'app.is_system()', 'app.is_notify_editor()', 'app.kassa_reader()', 'app.kassa_operator()', 'app.fin_list2()',
    'app.can_see_salary()', 'app.has_active_child()', 'app.claim_row(text,text)', 'app.owns_child(text)', 'app.owns_student_doc(text)',
    'app.my_child_sids()', 'app.my_student_docs()', 'app.my_child_class_keys()', 'app.my_staff_class_keys()',
    'app.rls_class_staff()', 'app.rls_ann_gate()', 'app.rls_ann_staff_keys()', 'app.rls_ann_child_keys()',
    'app.rls_gate_private()', 'app.rls_gate_students()', 'app.rls_gate_phones()', 'app.rls_gate_health()', 'app.rls_gate_any()', 'app.rls_acl()',
    'app.is_teacher_for_class(text)', 'app.is_homeroom_for(text)', 'app.is_kurator_for(text)', 'app.teacher_has_subject(text)',
    'app.ann_visible(jsonb,timestamptz)', 'app.ann_can_write(jsonb)'] loop
    v_oid := to_regprocedure(f);
    continue when v_oid is null;
    select l.lanname, p.prosrc into v_lang, v_src from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_oid;
    continue when v_lang <> 'sql';
    v_src := regexp_replace(v_src, '[[:space:];]+$', '');
    if v_src ~ ';' or v_src !~* '^[[:space:]]*(select|with)[[:space:]]' then
      raise exception 'rls-plpgsql: % — tanasi bitta SELECT / WITH emas, o''girilmadi (faylni tekshiring)', f;
    end if;
    v_def := pg_get_functiondef(v_oid);
    v_pos := strpos(v_def, E'\nAS $function$');
    if v_pos = 0 or v_def !~ E'\n LANGUAGE sql\n' then
      raise exception 'rls-plpgsql: % — kutilmagan ta''rif ko''rinishi', f;
    end if;
    v_new := replace(substr(v_def, 1, v_pos - 1), E'\n LANGUAGE sql\n', E'\n LANGUAGE plpgsql\n')
             || E'\nAS $function$\n#variable_conflict use_column\nbegin\n  return (\n' || v_src || E'\n  );\nend\n$function$';
    execute v_new;
    n := n + 1;
  end loop;
  raise notice 'rls-plpgsql: % ta RLS yordamchisi plpgsql ga o''girildi (reja keshlanadi)', n;
end $rp$;
