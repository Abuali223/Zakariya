\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: kassa-fix.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/migration/chain.sh | psql'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- kassa-fix.sql — MOLIYA ISH REJASI, 2-BOSQICH (F2.13): QAYTA TASNIF DALOLATNOMASI («ҚТ-», seriya 'FIX').
--   Sabab (Sh-8 B11, FD-20; buxgalter 2026-11-26): kassa kuni yopilgach xato hujjat bekor qilinmaydi — hisobda xato qolardi.
--   Kassa hujjatining o'zi (summa, sana, raqam, qatorlar, imzolar) Nizom 143 (25-band) bo'yicha o'zgarmaydi (CL-03); HISOBDAGI xato —
--   qator statiyasi (debet hisobvarag'i statiyadan), tomon (kimga) va asos izohi — alohida dalolatnoma bilan tuzatiladi. Jadval,
--   himoya triggeri va «amaldagi holat» yordamchilari (app.kassa_eff_doc, app.kassa_eff_art) — kassa.sql; hisobotlar: statiya
--   matritsasi RP-08 (kassa-day.sql: kassa_matrix), kontragent ko'chirmasi RP-10 (fin-cp.sql) va «Buxgalteriya»dagi xarajat qatori
--   (kx_<hujjat>_<qator>: statiya, toifa, kontragent, izoh) — amaldagi holat bo'yicha; registrlar (KO-3, KO-4, kunlik hisobot, KO-2
--   bosmasi) — asl hujjat bo'yicha (hujjatda «ҚТ» belgisi ko'rinadi). Summa xatosi — sanashdagi kamomad / ortiqcha (FD-21), bu yerda emas.
--   Doira (1-versiya): o'tkazilgan «Xarajat» chiqim orderi (KO-2, out_expense) — kassirlar statiyani eng ko'p shu yerda adashtiradi;
--     boshqa operatsiyalar (maosh, avans, qaytarish, o'quv to'lovi) o'z hisob-kitob jadvallariga bog'langan — ular uchun storno (F4.8).
--   public.kassa_fix_request(p)            — so'rov: buxgalter yoki Moliya menejeri (2-ro'yxat). Kun yopilgan bo'lishi (ochiq kunda —
--     kassir bekor qilib, to'g'risini yozadi), davr yopilmagan bo'lishi (fin:locked), hujjatda boshqa kutilayotgan so'rov bo'lmasligi,
--     kamida bitta o'zgarish va sabab (5+ belgi) shart. Statiya — «Xarajat» shaklidagi qoida bilan (faol, kassadan xarajat qilinadigan);
--     tomon — operatsiya tomon turlari (kontragent yoki «boshqa»). Bir xil kalit (clientRef) qayta kelsa — o'sha so'rov (dup), mazmuni
--     boshqa bo'lsa — kassa:ref_mismatch.
--   public.kassa_fix_decide(id, approve, izoh) — faqat Direktor (so'ragan o'zi emas). Tasdiqda shartlar QAYTA tekshiriladi (kun ochilgan
--     bo'lsa yoki davr yopilgan bo'lsa — rad), raqam va sana beriladi (kassa qulfi ostida, oxirgi qadam) va «Buxgalteriya» qatori yangilanadi.
--     Rad etishda sabab majburiy.
--   public.kassa_fix_cancel(id, sabab)     — kutilayotgan so'rovni so'ragan yoki Direktor bekor qiladi.
--   public.kassa_fix_list(kassa, holat, hujjat), public.kassa_fix_get(id) — 2-ro'yxat va Direktor uchun (tasdiqlar paneli, chop etish).
--   QULF TARTIBI (kassa.sql bilan bir xil): so'rov — L0 iqror_doc:<kalit> → hujjat qatori (FOR UPDATE; kassa qulfini olmaydi); tasdiq —
--     L4 iqror_desk:<kassa> → dalolatnoma qatori → L5 hisoblagich → «Buxgalteriya» qatorlari (o'tkazishdagi kabi); rad / bekor — faqat
--     dalolatnoma qatori.
--     Kassa qulfi (L4) ostida hujjat holati ham, kun holati ham o'zgarmaydi (bekor qilish va qayta ochish shu qulf bilan) — tasdiq
--     hujjat qatorini qulflamaydi; halqa (deadlock) yo'q.
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi (kassa moduli bilan birga).
-- =====================================================================

-- Hujjat qayta tasniflanishi mumkinmi: o'tkazilgan «Xarajat» KO-2, kuni yopilgan, davri yopilmagan.
create or replace function app.kassa_fix_target(p_doc public.cash_docs, p_what text) returns void
language plpgsql volatile security definer set search_path = public, app, pg_temp as $$
declare v_day public.cash_days%rowtype;
begin
  if p_doc.status is distinct from 'posted' or p_doc.form <> 'KO2' or p_doc.op <> 'out_expense' then
    raise exception 'Qayta tasnif faqat o''tkazilgan «Xarajat» chiqim orderida (KO-2) qilinadi' using errcode = '22023', hint = 'kassa:fix_kind';
  end if;
  select * into v_day from public.cash_days d where d.id = p_doc."dayId";
  if not found or v_day.status = 'open' then
    raise exception 'Kassa kuni hali ochiq — xato hujjatni kassir bekor qilib, to''g''risini yozadi (qayta tasnif — yopilgan kun hujjati uchun)'
      using errcode = 'P0001', hint = 'kassa:fix_day_open';
  end if;
  perform app.fin_lock_check(p_doc."businessDay", p_what);
end $$;
revoke all on function app.kassa_fix_target(public.cash_docs, text) from public, anon, authenticated;

-- Hujjatning amaldagi holati (dalolatnoma «before» uchun): oxirgi tasdiqlangan dalolatnomaning «after» qismi yoki asl hujjat
--   (faqat naqd qatorlar: raqam, statiya, debet, summa).
create or replace function app.kassa_fix_state(p_doc public.cash_docs) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(
    (select f.after from public.cash_doc_fixes f where f."docId" = p_doc.id and f.status = 'approved' order by f.year desc, f.no desc limit 1),
    jsonb_build_object('partyType', p_doc."partyType", 'partyId', p_doc."partyId", 'partyName', p_doc."partyName", 'basis', p_doc.basis,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('lineNo', l."lineNo", 'articleId', l."articleId", 'debit', l.debit, 'amount', l.amount)
                                          order by l."lineNo")
                           from public.cash_doc_lines l where l."docId" = p_doc.id and l.cash), '[]'::jsonb)))
$$;
revoke all on function app.kassa_fix_state(public.cash_docs) from public, anon, authenticated;

-- «Xarajat» qatoriga tanlanadigan statiya (kassa-docs.sql: kassa_doc_build dagi 'choose' qoidasi bilan bir xil) va uning debet hisobvarag'i.
create or replace function app.kassa_fix_article(p_rule public.fin_op_rules, p_aid text, p_ptype text) returns text
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_art public.fin_articles%rowtype; v_debit text;
begin
  select * into v_art from public.fin_articles a where a.id = p_aid and a.active;
  if not found then raise exception 'Statiya topilmadi yoki faol emas (%)', coalesce(p_aid, '—') using errcode = '22023', hint = 'kassa:article'; end if;
  if cardinality(p_rule."allowedArticles") > 0 then
    if not (p_aid = any (p_rule."allowedArticles")) then
      raise exception '«%» statiyasi bu operatsiyada ishlatilmaydi', v_art."nameUz" using errcode = '22023', hint = 'kassa:article';
    end if;
  elsif not v_art."cashOutAllowed" then   -- CT-23
    raise exception '«%» statiyasi bo''yicha kassadan to''g''ridan-to''g''ri xarajat qilinmaydi', v_art."nameUz" using errcode = '22023', hint = 'kassa:article';
  end if;
  v_debit := coalesce(p_rule.debit, p_rule."accountByParty" ->> coalesce(p_ptype, ''), v_art."accountCode");
  if v_debit is null or v_debit = coalesce(p_rule.credit, '5010') or v_debit in ('5010', '5110', '5710')
     or not exists (select 1 from public.gl_accounts g where g.code = v_debit and g.active) then
    raise exception 'Hisobvaraq noto''g''ri («%» statiyasi: Dt %)', v_art."nameUz", coalesce(v_debit, '—') using errcode = '22023', hint = 'kassa:account';
  end if;
  return v_debit;
end $$;
revoke all on function app.kassa_fix_article(public.fin_op_rules, text, text) from public, anon, authenticated;

-- Javob: dalolatnoma + hujjat qisqachasi.
create or replace function app.kassa_fix_json(p_id text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select to_jsonb(f) || jsonb_build_object('doc', jsonb_build_object('id', c.id, 'no', c.no, 'year', c.year, 'businessDay', c."businessDay",
                                                                      'form', c.form, 'op', c.op, 'amount', c.amount, 'status', c.status,
                                                                      'desk', c.desk, 'postedByName', c."postedByName"))
    from public.cash_doc_fixes f join public.cash_docs c on c.id = f."docId" where f.id = p_id
$$;
revoke all on function app.kassa_fix_json(text) from public, anon, authenticated;

-- ---------- RPC: so'rov ----------
--   p: { docId, clientRef, reason, lines: [{lineNo, articleId}] (ixtiyoriy), party: {type, id, name} (ixtiyoriy), basis (ixtiyoriy) }.
--   Ko'rsatilmagan qism amaldagi holatdan olinadi; ko'rsatilgan qatorning statiyasi (shu statiya bo'lsa ham) va debeti qayta aniqlanadi.
create or replace function public.kassa_fix_request(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_ref text; v_docid text; v_reason text; v_doc public.cash_docs%rowtype; v_rule public.fin_op_rules%rowtype;
  v_old jsonb; v_base text; v_in jsonb := '{}'::jsonb; x jsonb; l jsonb; v_lines jsonb := '[]'::jsonb; v_aid text; v_debit text;
  v_ptype text; v_pid text; v_pname text; v_basis text; v_after jsonb; v_hash text; v_ex public.cash_doc_fixes%rowtype; v_id text; v_n int;
begin
  if not app.fin_list2() then
    raise exception 'Ruxsat yo''q: qayta tasnifni buxgalter yoki Moliya menejeri so''raydi (Direktor tasdiqlaydi)' using errcode = '42501', hint = 'kassa:fix_rights';
  end if;
  if jsonb_typeof(p) is distinct from 'object' then raise exception 'So''rov noto''g''ri' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_ref := btrim(coalesce(p ->> 'clientRef', ''));
  if v_ref !~ '^[A-Za-z0-9_.:-]{6,80}$' then
    raise exception 'So''rov kaliti (clientRef) noto''g''ri' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  v_docid := btrim(coalesce(p ->> 'docId', ''));
  v_reason := left(btrim(coalesce(p ->> 'reason', '')), 500);
  if (p ? 'lines' and jsonb_typeof(p -> 'lines') <> 'array') or (p ? 'party' and jsonb_typeof(p -> 'party') not in ('object', 'null')) then
    raise exception 'So''rov noto''g''ri' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  -- so'rov mazmunining kanonik izi: qator tartibi va bo'sh joylar ahamiyatsiz
  for x in select * from jsonb_array_elements(coalesce(p -> 'lines', '[]'::jsonb)) loop
    if jsonb_typeof(x) <> 'object' or coalesce(x ->> 'lineNo', '') !~ '^[1-9][0-9]{0,3}$' then
      raise exception 'Qator raqami noto''g''ri' using errcode = '22023', hint = 'kassa:fix_line';
    end if;
    if v_in ? (x ->> 'lineNo') then raise exception 'Bir qator ikki marta ko''rsatilgan' using errcode = '22023', hint = 'kassa:fix_line'; end if;
    v_in := v_in || jsonb_build_object(x ->> 'lineNo', btrim(coalesce(x ->> 'articleId', '')));
  end loop;
  v_hash := md5(jsonb_build_object('docId', v_docid, 'reason', v_reason, 'lines', v_in,
                                   'party', case when jsonb_typeof(p -> 'party') = 'object'
                                                 then jsonb_build_object('type', btrim(coalesce(p -> 'party' ->> 'type', '')),
                                                                         'id', btrim(coalesce(p -> 'party' ->> 'id', '')),
                                                                         'name', btrim(coalesce(p -> 'party' ->> 'name', ''))) end,
                                   'basis', case when p ? 'basis' and jsonb_typeof(p -> 'basis') <> 'null' then btrim(coalesce(p ->> 'basis', '')) end)::text);

  perform pg_advisory_xact_lock(hashtext('iqror_doc:' || v_ref));   -- L0: bir xil kalit bilan parallel yuborish navbatga turadi
  select * into v_ex from public.cash_doc_fixes f where f."clientRef" = v_ref;
  if found then
    if v_ex."reqHash" <> v_hash or v_ex."requestedBy" <> v_uid then
      raise exception 'Bu oynadan avval boshqa ma''lumot bilan so''rov yuborilgan (javob yo''qolgan bo''lishi mumkin) — hujjatdagi dalolatnomalarni tekshiring'
        using errcode = '22023', hint = 'kassa:ref_mismatch';
    end if;
    return app.kassa_fix_json(v_ex.id) || jsonb_build_object('ok', true, 'dup', true);
  end if;

  select * into v_doc from public.cash_docs c where c.id = v_docid for update;   -- shu hujjat bo'yicha so'rovlar navbatga turadi
  if not found then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if exists (select 1 from public.cash_doc_fixes f where f."docId" = v_doc.id and f.status = 'pending') then
    raise exception 'Bu hujjat bo''yicha Direktor qarorini kutayotgan qayta tasnif so''rovi bor — avval u hal qilinsin (yoki bekor qilinsin)'
      using errcode = 'P0001', hint = 'kassa:fix_pending';
  end if;
  perform app.kassa_fix_target(v_doc, 'Qayta tasnif');
  select * into v_rule from public.fin_op_rules r where r.op = v_doc.op;
  v_old := app.kassa_fix_state(v_doc);
  select f.id into v_base from public.cash_doc_fixes f where f."docId" = v_doc.id and f.status = 'approved' order by f.year desc, f.no desc limit 1;

  -- tomon
  v_ptype := v_old ->> 'partyType'; v_pid := v_old ->> 'partyId'; v_pname := coalesce(v_old ->> 'partyName', '');
  if jsonb_typeof(p -> 'party') = 'object' then
    v_ptype := btrim(coalesce(p -> 'party' ->> 'type', ''));
    if not (v_ptype = any (v_rule."partyTypes")) then
      raise exception 'Bu operatsiyada tomon turi faqat: %', array_to_string(v_rule."partyTypes", ', ') using errcode = '22023', hint = 'kassa:party';
    end if;
    select o.o_id, o.o_name into v_pid, v_pname from app.kassa_party(v_ptype, nullif(btrim(coalesce(p -> 'party' ->> 'id', '')), ''), p -> 'party' ->> 'name') o;
  end if;
  -- asos
  v_basis := coalesce(v_old ->> 'basis', '');
  if p ? 'basis' and jsonb_typeof(p -> 'basis') <> 'null' then
    v_basis := left(btrim(coalesce(p ->> 'basis', '')), 500);
    if length(v_basis) < 3 then raise exception 'Asos (hujjat nomi, raqami, sanasi) — kamida 3 belgi' using errcode = '22023', hint = 'kassa:basis'; end if;
  end if;
  -- qatorlar: ko'rsatilgan statiya qoida bo'yicha tekshiriladi, debet statiyadan qayta aniqlanadi
  select count(*) into v_n from jsonb_object_keys(v_in) k
   where not exists (select 1 from jsonb_array_elements(v_old -> 'lines') o where o ->> 'lineNo' = k);
  if v_n > 0 then raise exception 'Hujjatda bunday naqd qator yo''q' using errcode = '22023', hint = 'kassa:fix_line'; end if;
  for l in select * from jsonb_array_elements(v_old -> 'lines') loop
    v_aid := l ->> 'articleId'; v_debit := l ->> 'debit';
    if v_in ? (l ->> 'lineNo') then
      v_aid := nullif(v_in ->> (l ->> 'lineNo'), '');
      if v_aid is null then raise exception 'Statiya tanlanmagan' using errcode = '22023', hint = 'kassa:article'; end if;
      v_debit := app.kassa_fix_article(v_rule, v_aid, v_ptype);
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('lineNo', (l ->> 'lineNo')::int, 'articleId', v_aid, 'debit', v_debit,
                                                               'amount', (l ->> 'amount')::numeric));
  end loop;
  v_after := jsonb_build_object('partyType', v_ptype, 'partyId', v_pid, 'partyName', v_pname, 'basis', v_basis, 'lines', v_lines);
  if v_after = v_old then
    raise exception 'O''zgarish yo''q — statiya, tomon yoki asosdan kamida bittasi boshqacha bo''lsin' using errcode = '22023', hint = 'kassa:fix_nochange';
  end if;
  if length(v_reason) < 5 then
    raise exception 'Tuzatish sababini yozing (kamida 5 belgi): qanday xato va qaysi hujjatga asoslanib' using errcode = '22023', hint = 'kassa:fix_reason';
  end if;

  v_id := 'fx_' || replace(gen_random_uuid()::text, '-', '');
  perform app.kassa_flag(true);
  insert into public.cash_doc_fixes (id, "docId", desk, status, reason, before, after, "baseFixId", "clientRef", "reqHash", "requestedBy", "requestedByName")
    values (v_id, v_doc.id, v_doc.desk, 'pending', v_reason, v_old, v_after, v_base, v_ref, v_hash, v_uid, app.fin_exp_who(v_uid))
    on conflict ("docId") where status = 'pending' do nothing;
  if not found then
    raise exception 'Bu hujjat bo''yicha Direktor qarorini kutayotgan qayta tasnif so''rovi bor — avval u hal qilinsin (yoki bekor qilinsin)'
      using errcode = 'P0001', hint = 'kassa:fix_pending';
  end if;
  perform app.kassa_flag(false);
  return app.kassa_fix_json(v_id) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.kassa_fix_request(jsonb) from public, anon;
grant execute on function public.kassa_fix_request(jsonb) to authenticated;

-- ---------- RPC: Direktor qarori ----------
create or replace function public.kassa_fix_decide(p_id text, p_approve boolean, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_note text := left(btrim(coalesce(p_note, '')), 500); v_desk text; v_f public.cash_doc_fixes%rowtype;
  v_doc public.cash_docs%rowtype; v_rule public.fin_op_rules%rowtype; v_base text; v_day date; v_no int; l jsonb; o jsonb;
  v_cat text; v_lbl text; v_a jsonb;
begin
  if not app.is_admin() then
    raise exception 'Ruxsat yo''q: qayta tasnifni faqat Direktor tasdiqlaydi yoki rad etadi' using errcode = '42501', hint = 'kassa:fix_rights';
  end if;
  if p_approve is null then raise exception 'Qaror ko''rsatilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  select f.desk into v_desk from public.cash_doc_fixes f where f.id = p_id;
  if not found then raise exception 'Dalolatnoma topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if p_approve then perform app.kassa_lock_desk(v_desk); end if;   -- L4: hujjat va kun holati shu tranzaksiya oxirigacha o'zgarmaydi
  select * into v_f from public.cash_doc_fixes f where f.id = p_id for update;
  if v_f.status <> 'pending' then
    if v_f."decidedBy" = v_uid and v_f.status = (case when p_approve then 'approved' else 'rejected' end) then
      return app.kassa_fix_json(p_id) || jsonb_build_object('ok', true, 'dup', true);
    end if;
    raise exception 'Dalolatnoma qaror kutmayapti (holati: %)', v_f.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  if v_f."requestedBy" = v_uid then
    raise exception 'O''zingiz so''ragan tuzatish bo''yicha o''zingiz qaror qilmaysiz' using errcode = '42501', hint = 'kassa:self_approve';
  end if;

  if not p_approve then
    if length(v_note) < 3 then raise exception 'Rad etish sababini yozing' using errcode = '22023', hint = 'kassa:fix_note'; end if;
    perform app.kassa_flag(true);
    update public.cash_doc_fixes set status = 'rejected', "decidedBy" = v_uid, "decidedAt" = now(), "decidedByName" = app.fin_exp_who(v_uid),
           "decisionNote" = v_note
     where id = p_id;
    perform app.kassa_flag(false);
    return app.kassa_fix_json(p_id) || jsonb_build_object('ok', true, 'dup', false);
  end if;

  -- Tasdiq: shartlar hozirgi holat bo'yicha qayta tekshiriladi
  select * into v_doc from public.cash_docs c where c.id = v_f."docId";
  perform app.kassa_fix_target(v_doc, 'Qayta tasnif');
  select f.id into v_base from public.cash_doc_fixes f where f."docId" = v_doc.id and f.status = 'approved' order by f.year desc, f.no desc limit 1;
  if v_base is distinct from v_f."baseFixId" or app.kassa_fix_state(v_doc) is distinct from v_f.before then
    raise exception 'Hujjat so''rovdan keyin boshqa dalolatnoma bilan tuzatilgan — so''rovni rad eting, buxgalter yangisini yozsin' using errcode = 'P0001', hint = 'kassa:fix_stale';
  end if;
  select * into v_rule from public.fin_op_rules r where r.op = v_doc.op;
  for l in select * from jsonb_array_elements(v_f.after -> 'lines') loop   -- o'zgargan statiya hali ham faol va ruxsat etilganmi
    select x into o from jsonb_array_elements(v_f.before -> 'lines') x where x ->> 'lineNo' = l ->> 'lineNo';
    if (l ->> 'articleId') is distinct from (o ->> 'articleId') or (l ->> 'debit') is distinct from (o ->> 'debit') then
      if app.kassa_fix_article(v_rule, l ->> 'articleId', v_f.after ->> 'partyType') is distinct from (l ->> 'debit') then
        raise exception 'Statiya hisobvarag''i so''rovdan keyin o''zgargan — so''rovni rad eting, buxgalter yangisini yozsin' using errcode = 'P0001', hint = 'kassa:fix_stale';
      end if;
    end if;
  end loop;
  if v_f.after ->> 'partyType' = 'counterparty'
     and not exists (select 1 from public.fin_counterparties c where c.id = v_f.after ->> 'partyId') then
    raise exception 'Kontragent topilmadi' using errcode = '22023', hint = 'kassa:party';
  end if;

  v_a := v_f.after;
  v_day := app.fin_today();
  perform app.kassa_flag(true);
  -- raqam (L5) — «Buxgalteriya» qatorlaridan oldin (o'tkazishdagi kabi: kassa_post → kassa_link_paid): bu qatorlarni faqat shu kassa
  --   qulfi (L4) ostidagi yo'llar o'zgartiradi (o'tkazish, bekor qilish, qayta tasnif) — halqa yo'q; xato bo'lsa raqam ham qaytadi
  v_no := app.kassa_next_no(v_f.desk, 'FIX', extract(year from v_day)::int);
  -- «Buxgalteriya»dagi ko'chgan xarajat qatori (kassa-links.sql: kassa_link_paid) — amaldagi statiya, toifa, kontragent va izoh
  for l in select * from jsonb_array_elements(v_a -> 'lines') loop
    select k.o_category, k.o_label into v_cat, v_lbl from app.kassa_exp_category(l ->> 'articleId') k;
    update public.expenses e
       set "articleId" = l ->> 'articleId', category = v_cat,
           "counterpartyId" = case when v_a ->> 'partyType' = 'counterparty' then v_a ->> 'partyId' end,
           note = left(btrim(coalesce(v_lbl || ': ', '') || coalesce(nullif(v_a ->> 'partyName', ''), '')
                             || case when coalesce(v_a ->> 'basis', '') <> '' then ' — ' || (v_a ->> 'basis') else '' end
                             || ' (KO-2 № ' || v_doc.no || '; QT-' || v_no || ')'), 300)
     where e.id = 'kx_' || v_doc.id || '_' || (l ->> 'lineNo') and e."cashDocId" = v_doc.id;
  end loop;
  update public.cash_doc_fixes
     set status = 'approved', year = extract(year from v_day)::int, no = v_no, "actDay" = v_day,
         "decidedBy" = v_uid, "decidedAt" = now(), "decidedByName" = app.fin_exp_who(v_uid), "decisionNote" = v_note
   where id = p_id;
  perform app.kassa_flag(false);
  return app.kassa_fix_json(p_id) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.kassa_fix_decide(text, boolean, text) from public, anon;
grant execute on function public.kassa_fix_decide(text, boolean, text) to authenticated;

-- ---------- RPC: kutilayotgan so'rovni bekor qilish (so'ragan yoki Direktor) ----------
create or replace function public.kassa_fix_cancel(p_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_f public.cash_doc_fixes%rowtype; v_reason text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not (app.is_admin() or app.fin_list2()) then
    raise exception 'Ruxsat yo''q' using errcode = '42501', hint = 'kassa:fix_rights';
  end if;
  select * into v_f from public.cash_doc_fixes f where f.id = p_id for update;
  if not found then raise exception 'Dalolatnoma topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if not app.is_admin() and v_f."requestedBy" is distinct from v_uid then
    raise exception 'Ruxsat yo''q: so''rovni uni yozgan xodim yoki Direktor bekor qiladi' using errcode = '42501', hint = 'kassa:fix_rights';
  end if;
  if v_f.status <> 'pending' then
    if v_f.status = 'cancelled' and v_f."cancelledBy" = v_uid then
      return app.kassa_fix_json(p_id) || jsonb_build_object('ok', true, 'dup', true);
    end if;
    raise exception 'Dalolatnoma qaror kutmayapti (holati: %)', v_f.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  if length(v_reason) < 3 then raise exception 'Bekor qilish sababini yozing' using errcode = '22023', hint = 'kassa:fix_note'; end if;
  perform app.kassa_flag(true);
  update public.cash_doc_fixes set status = 'cancelled', "cancelledBy" = v_uid, "cancelledAt" = now(), "cancelReason" = v_reason where id = p_id;
  perform app.kassa_flag(false);
  return app.kassa_fix_json(p_id) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.kassa_fix_cancel(text, text) from public, anon;
grant execute on function public.kassa_fix_cancel(text, text) to authenticated;

-- ---------- O'qish: ro'yxat va bitta dalolatnoma (2-ro'yxat va Direktor) ----------
--   p_status: 'pending' (qaror kutayotganlar) yoki 'all' (oxirgi 200 ta); p_doc — shu hujjatniki (hammasi, eng yangisi oxirida).
create or replace function public.kassa_fix_list(p_desk text default 'main', p_status text default 'pending', p_doc text default null) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main');
begin
  if not (app.is_admin() or app.fin_list2()) then raise exception 'Ruxsat yo''q' using errcode = '42501', hint = 'kassa:fix_rights'; end if;
  if coalesce(p_status, '') not in ('pending', 'all') then raise exception 'Holat noto''g''ri' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  if p_doc is not null then
    return jsonb_build_object('ok', true, 'fixes', coalesce((select jsonb_agg(app.kassa_fix_json(f.id) order by f."requestedAt", f.id)
                                                               from public.cash_doc_fixes f where f."docId" = p_doc), '[]'::jsonb));
  end if;
  return jsonb_build_object('ok', true, 'fixes', coalesce((select jsonb_agg(app.kassa_fix_json(x.id) order by x."requestedAt" desc, x.id)
                                                             from (select f.id, f."requestedAt" from public.cash_doc_fixes f
                                                                    where f.desk = v_desk and (p_status = 'all' or f.status = 'pending')
                                                                    order by f."requestedAt" desc, f.id limit 200) x), '[]'::jsonb));
end $$;
revoke all on function public.kassa_fix_list(text, text, text) from public, anon;
grant execute on function public.kassa_fix_list(text, text, text) to authenticated;

create or replace function public.kassa_fix_get(p_id text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_j jsonb;
begin
  if not (app.is_admin() or app.fin_list2()) then raise exception 'Ruxsat yo''q' using errcode = '42501', hint = 'kassa:fix_rights'; end if;
  v_j := app.kassa_fix_json(p_id);
  if v_j is null then raise exception 'Dalolatnoma topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  return jsonb_build_object('ok', true, 'fix', v_j,
                            'isTest', coalesce((select k."isTest" from public.cash_desks k where k.id = v_j ->> 'desk'), false));
end $$;
revoke all on function public.kassa_fix_get(text) from public, anon;
grant execute on function public.kassa_fix_get(text) to authenticated;

notify pgrst, 'reload schema';
