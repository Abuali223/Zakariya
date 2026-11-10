\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: kassa-docs.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- kassa-docs.sql — MOLIYA ISH REJASI, 1a-BOSQICH (F1.3, F1.4, F1.10): KASSA HUJJATLARI FUNKSIYALARI.
--   Ichki yadro (mijoz chaqira olmaydi):
--     app.kassa_party(...)        — tomonni (o'quvchi / xodim / kontragent / bank / ta'sischi / boshqa) tekshiradi, nomini oladi;
--     app.kassa_doc_build(...)    — operatsiya qoidasi bo'yicha hujjat va Dt/Kt qatorlarini yaratadi (so'rov holatida, raqamsiz);
--     app.kassa_resolve_day(...)  — hujjat qaysi kassa kuniga yozilishini aniqlaydi (kerak bo'lsa kunni ochadi);
--     app.kassa_doc_post(...)     — kassa qulfi ostida o'tkazadi: kun, qoldiq (manfiy bo'lmasin), OXIRIDA raqam.
--   Mijoz funksiyalari (har birida aniq rol tekshiruvi):
--     kassa_receipt(p)            — KO-1 kirim orderi (kassir; Direktor ruxsati kerak bo'lgan operatsiya — avval so'rov);
--     kassa_payout_request(p)     — KO-2 chiqim so'rovi (raqamsiz); to'lovdan OLDIN 2-ro'yxat tasdig'i, katta summada Direktor ham;
--     kassa_doc_approve / kassa_doc_reject / kassa_doc_cancel — tasdiqlash (≠ so'rovchi), rad etish, so'rovni bekor qilish;
--     kassa_doc_pay(id)           — tasdiqlangan hujjat bo'yicha pulni berish / qabul qilish (o'tkazish, raqam);
--     kassa_doc_void(id, sabab)   — shu kunning o'zida bekor qilish (raqam saqlanadi).
--   Xato javoblarida HINT — dastur uchun qisqa kod ('kassa:prev_open', 'kassa:negative' …), MESSAGE — foydalanuvchiga matn.
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi.
-- =====================================================================

-- ---------- Tomon (kimdan / kimga) ----------
create or replace function app.kassa_party(p_type text, p_id text, p_name text, out o_id text, out o_name text)
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_coll text; v_row text; v_kind text; v_active boolean;
begin
  p_id := nullif(btrim(coalesce(p_id, '')), '');
  p_name := left(btrim(coalesce(p_name, '')), 200);
  if p_type = 'student' then
    select coalesce(nullif(s."studentId", ''), s.id), s.name into o_id, o_name
      from public.students s where s.id = p_id or s."studentId" = p_id order by (s.id = p_id) desc limit 1;
    if o_id is null then raise exception 'O''quvchi topilmadi' using errcode = '22023', hint = 'kassa:party'; end if;
    -- to'lovchi (ota-ona) ismi berilgan bo'lsa — hujjatda o'sha, o'quvchi kaliti analitikada qoladi
    o_name := coalesce(nullif(p_name, ''), o_name, '');
  elsif p_type = 'employee' then
    v_coll := split_part(coalesce(p_id, ''), ':', 1);
    v_row := substr(coalesce(p_id, ''), length(v_coll) + 2);
    if v_coll not in ('teachers', 'staff') or v_row = '' then
      raise exception 'Xodim tanlanmagan' using errcode = '22023', hint = 'kassa:party';
    end if;
    if v_coll = 'teachers' then select t.name into o_name from public.teachers t where t.id = v_row;
    else select s.name into o_name from public.staff s where s.id = v_row; end if;
    if not found then raise exception 'Xodim topilmadi' using errcode = '22023', hint = 'kassa:party'; end if;
    o_id := v_coll || ':' || v_row; o_name := coalesce(o_name, '');
  elsif p_type in ('counterparty', 'bank', 'founder') then
    select c.id, c.name, c.kind, c.active into o_id, o_name, v_kind, v_active from public.fin_counterparties c where c.id = p_id;
    if o_id is null then raise exception 'Kontragent topilmadi' using errcode = '22023', hint = 'kassa:party'; end if;
    if not v_active then raise exception 'Kontragent faol emas' using errcode = '22023', hint = 'kassa:party'; end if;
    if (p_type = 'bank' and v_kind <> 'bank') or (p_type = 'founder' and v_kind <> 'founder')
       or (p_type = 'counterparty' and v_kind in ('bank', 'founder')) then
      raise exception 'Kontragent turi bu operatsiyaga mos emas' using errcode = '22023', hint = 'kassa:party';
    end if;
  elsif p_type = 'other' then
    if length(p_name) < 3 then raise exception 'Kimdan / kimga — to''liq yozing' using errcode = '22023', hint = 'kassa:party'; end if;
    o_id := null; o_name := p_name;
  else
    raise exception 'Tomon turi noto''g''ri' using errcode = '22023', hint = 'kassa:party';
  end if;
end $$;
revoke all on function app.kassa_party(text, text, text) from public, anon, authenticated;

-- JSON'dan mantiqiy qiymatni xavfsiz o'qish (noto'g'ri matn — false).
create or replace function app.kassa_bool(p jsonb, p_key text) returns boolean
language sql immutable set search_path = public, app, pg_temp as $$
  select lower(coalesce(p ->> p_key, '')) in ('true', 't', '1', 'yes')
$$;
revoke all on function app.kassa_bool(jsonb, text) from public, anon, authenticated;

-- JSON'dan pul summasini xavfsiz o'qish (NaN / Infinity / matn / 2 xonadan ortiq tiyin — rad).
create or replace function app.kassa_amount(p_val jsonb, p_what text) returns numeric
language plpgsql immutable set search_path = public, app, pg_temp as $$
declare v numeric;
begin
  if p_val is null or jsonb_typeof(p_val) not in ('number', 'string') then
    raise exception '%: summa kiritilmagan', p_what using errcode = '22023', hint = 'kassa:amount';
  end if;
  begin v := (p_val #>> '{}')::numeric;
  exception when others then raise exception '%: summa noto''g''ri', p_what using errcode = '22023', hint = 'kassa:amount'; end;
  if v is null or v = 'NaN'::numeric or not (v > 0 and v < 1e12) or v <> round(v, 2) then
    raise exception '%: summa noto''g''ri (musbat, tiyin 2 xonagacha)', p_what using errcode = '22023', hint = 'kassa:amount';
  end if;
  return v;
end $$;
revoke all on function app.kassa_amount(jsonb, text) from public, anon, authenticated;

-- ---------- Hujjatni yaratish (so'rov holatida, raqamsiz) ----------
--   p: desk, op, amount, partyType, partyId, partyName, basis, attachment, note, noBasis, fiscalNo, fiscalExempt, clientRef,
--      capturedAt, articleId | lines:[{articleId, amount, note}]
--   p_internal (faqat tizim funksiyalari): systemOnly / manual=false operatsiyalar, qatorlarda aniq debit/credit/analytics,
--      sourceTable/sourceId/sourceSnapshot, isSystem, tasdiq talablari (needsList2/needsDirector) berilishi mumkin.
--   Bir xil clientRef qayta kelsa — mavjud hujjat qaytadi (o_dup = true); mazmuni boshqa bo'lsa — xato.
create or replace function app.kassa_doc_build(p jsonb, p_form text, p_uid text, p_internal boolean default false,
                                               out o_id text, out o_dup boolean)
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_ref text; v_op text; v_desk text; v_amount numeric; v_rule public.fin_op_rules%rowtype; v_ex public.cash_docs%rowtype;
  v_org public.fin_org%rowtype; v_ptype text; v_pid text; v_pname text;
  v_basis text; v_note text; v_attach text; v_nobasis boolean; v_fiscal text; v_fexempt boolean := false;
  v_lines jsonb; v_line jsonb; v_i int := 0; v_n int; v_lamt numeric; v_art public.fin_articles%rowtype; v_aid text;
  v_debit text; v_credit text; v_counter text; v_sum_cash numeric := 0; v_sum_all numeric := 0; v_lnote text;
  v_need2 boolean; v_needd boolean; v_cap timestamptz; v_rows jsonb := '[]'::jsonb; v_is_cash boolean;
begin
  o_dup := false;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'Hujjat ma''lumoti yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  v_ref := btrim(coalesce(p ->> 'clientRef', ''));
  if v_ref !~ '^[A-Za-z0-9_.:-]{6,80}$' then
    raise exception 'Hujjat kaliti (clientRef) noto''g''ri' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  -- Tizim hujjatlari kalitlari (sanash farqi, boshlang'ich qoldiq, kamomad qarori, o'quv to'lovi / maosh / avans / qaytarish
  --   orderlari) mijozga band qilib qo'yilmaydi.
  if not p_internal and v_ref ~* '^(sys|opening_|shdec_|pay_|sal_|adv_|ref_)' then
    raise exception 'Hujjat kaliti (clientRef) noto''g''ri' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  v_op := btrim(coalesce(p ->> 'op', ''));
  v_desk := coalesce(nullif(btrim(coalesce(p ->> 'desk', '')), ''), 'main');
  v_amount := app.kassa_amount(p -> 'amount', 'Hujjat');

  perform pg_advisory_xact_lock(hashtext('iqror_doc:' || v_ref));   -- L0: bir xil kalit bilan parallel yuborish navbatga turadi
  select * into v_ex from public.cash_docs c where c."clientRef" = v_ref;
  if found then
    if v_ex.op <> v_op or v_ex.amount <> v_amount or v_ex.desk <> v_desk or v_ex.form <> p_form then
      raise exception 'Shu kalit bilan boshqa hujjat allaqachon yozilgan' using errcode = '22023', hint = 'kassa:ref_mismatch';
    end if;
    o_id := v_ex.id; o_dup := true; return;
  end if;

  select * into v_rule from public.fin_op_rules r where r.op = v_op and r.active;
  if not found or v_rule.form <> p_form then
    raise exception 'Kassa operatsiyasi noto''g''ri' using errcode = '22023', hint = 'kassa:bad_op';
  end if;
  if not p_internal and (v_rule."systemOnly" or not v_rule.manual) then
    raise exception '«%» qo''lda kiritilmaydi — tegishli bo''limdan avtomatik yoziladi', v_rule."nameUz" using errcode = '42501', hint = 'kassa:not_manual';
  end if;
  if not exists (select 1 from public.cash_desks k where k.id = v_desk and k.active) then
    raise exception 'Kassa topilmadi' using errcode = '22023', hint = 'kassa:bad_desk';
  end if;
  select * into v_org from public.fin_org o where o.id = 'main';

  -- Tomon (CT-22): tur + kalit; erkin matn faqat «boshqa».
  v_ptype := nullif(btrim(coalesce(p ->> 'partyType', '')), '');
  if cardinality(v_rule."partyTypes") > 0 then
    if v_ptype is null or not (v_ptype = any (v_rule."partyTypes")) then
      raise exception 'Kimdan / kimga — tanlanmagan yoki bu operatsiyaga mos emas' using errcode = '22023', hint = 'kassa:party';
    end if;
    select k.o_id, k.o_name into v_pid, v_pname from app.kassa_party(v_ptype, p ->> 'partyId', p ->> 'partyName') k;
  elsif p_internal and v_ptype is not null then
    select k.o_id, k.o_name into v_pid, v_pname from app.kassa_party(v_ptype, p ->> 'partyId', p ->> 'partyName') k;
  else
    v_ptype := null; v_pid := null; v_pname := left(btrim(coalesce(p ->> 'partyName', '')), 200);
  end if;

  v_basis := left(btrim(coalesce(p ->> 'basis', '')), 500);
  v_attach := left(btrim(coalesce(p ->> 'attachment', '')), 500);
  v_note := left(btrim(coalesce(p ->> 'note', '')), 500);
  v_nobasis := app.kassa_bool(p, 'noBasis');

  -- Qatorlar
  v_lines := p -> 'lines';
  if v_lines is null or jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) = 0 then
    v_lines := jsonb_build_array(jsonb_build_object('articleId', p ->> 'articleId', 'amount', v_amount));
  end if;
  v_n := jsonb_array_length(v_lines);
  if v_n > (case when p_internal then 80 else 20 end) then
    raise exception 'Bitta hujjatda 20 tadan ortiq qator bo''lmaydi' using errcode = '22023', hint = 'kassa:lines';
  end if;
  if v_n > 1 and not p_internal and v_op <> 'out_expense' then
    raise exception 'Bu operatsiyada bitta qator bo''ladi' using errcode = '22023', hint = 'kassa:lines';
  end if;
  for v_line in select x from jsonb_array_elements(v_lines) x loop
    v_i := v_i + 1;
    if jsonb_typeof(v_line) <> 'object' then raise exception 'Qator noto''g''ri' using errcode = '22023', hint = 'kassa:lines'; end if;
    v_lamt := app.kassa_amount(v_line -> 'amount', v_i || '-qator');
    v_lnote := left(btrim(coalesce(v_line ->> 'note', '')), 300);
    -- statiya
    v_aid := null; v_art := null;
    if v_rule."articleMode" = 'fixed' then
      v_aid := v_rule."articleId";
      if p_internal and nullif(v_line ->> 'articleId', '') is not null then v_aid := v_line ->> 'articleId'; end if;
    elsif v_rule."articleMode" = 'choose' then
      v_aid := nullif(btrim(coalesce(v_line ->> 'articleId', '')), '');
      if v_aid is null then raise exception 'Statiya tanlanmagan' using errcode = '22023', hint = 'kassa:article'; end if;
    end if;
    if v_aid is not null then
      select * into v_art from public.fin_articles a where a.id = v_aid and a.active;
      if not found then raise exception 'Statiya topilmadi yoki faol emas (%)', v_aid using errcode = '22023', hint = 'kassa:article'; end if;
      if v_rule."articleMode" = 'choose' and not p_internal then
        if cardinality(v_rule."allowedArticles") > 0 then
          if not (v_aid = any (v_rule."allowedArticles")) then
            raise exception '«%» statiyasi bu operatsiyada ishlatilmaydi', v_art."nameUz" using errcode = '22023', hint = 'kassa:article';
          end if;
        elsif not v_art."cashOutAllowed" then   -- CT-23: ish haqi, soliq, eskirish va h.k. kassa xarajati emas
          raise exception '«%» statiyasi bo''yicha kassadan to''g''ridan-to''g''ri xarajat qilinmaydi', v_art."nameUz" using errcode = '22023', hint = 'kassa:article';
        end if;
      end if;
      if v_art."needsNote" and length(v_lnote) < 3 and length(v_note) < 3 then
        raise exception '«%» statiyasi uchun izoh majburiy', v_art."nameUz" using errcode = '22023', hint = 'kassa:note';
      end if;
    end if;
    -- hisobvaraqlar
    if p_internal and nullif(v_line ->> 'debit', '') is not null and nullif(v_line ->> 'credit', '') is not null then
      v_debit := v_line ->> 'debit'; v_credit := v_line ->> 'credit';
    else
      v_counter := case when p_form = 'KO1' then v_rule.credit else v_rule.debit end;
      if v_counter is null then v_counter := v_rule."accountByParty" ->> coalesce(v_ptype, ''); end if;
      if v_counter is null then v_counter := v_art."accountCode"; end if;
      if v_counter is null then raise exception 'Hisobvaraq aniqlanmadi (operatsiya «%»)', v_rule."nameUz" using errcode = '22023', hint = 'kassa:account'; end if;
      if p_form = 'KO1' then v_debit := '5010'; v_credit := v_counter;
      elsif p_form = 'KO2' then v_debit := v_counter; v_credit := '5010';
      else v_debit := coalesce(v_rule.debit, v_counter); v_credit := coalesce(v_rule.credit, v_counter); end if;
    end if;
    if v_debit = v_credit
       or not exists (select 1 from public.gl_accounts g where g.code = v_debit and g.active)
       or not exists (select 1 from public.gl_accounts g where g.code = v_credit and g.active) then
      raise exception 'Hisobvaraq noto''g''ri (Dt % / Kt %)', v_debit, v_credit using errcode = '22023', hint = 'kassa:account';
    end if;
    v_is_cash := (v_debit = '5010' or v_credit = '5010');
    if v_is_cash and ((p_form = 'KO1' and v_debit <> '5010') or (p_form = 'KO2' and v_credit <> '5010')
                      or (p_form = 'ACT' and v_op <> 'nc_opening')) then
      raise exception 'Kassa hisobvarag''i (5010) noto''g''ri tomonda' using errcode = '22023', hint = 'kassa:account';
    end if;
    v_sum_all := v_sum_all + v_lamt;
    if v_is_cash then v_sum_cash := v_sum_cash + v_lamt; end if;
    v_rows := v_rows || jsonb_build_object('n', v_i, 'debit', v_debit, 'credit', v_credit, 'amount', v_lamt, 'articleId', v_aid,
                                           'cash', v_is_cash, 'note', v_lnote,
                                           'analytics', case when p_internal and jsonb_typeof(v_line -> 'analytics') = 'object' then v_line -> 'analytics' else '{}'::jsonb end);
  end loop;
  if (p_form in ('KO1', 'KO2') and v_sum_cash <> v_amount) or (p_form = 'ACT' and v_sum_all <> v_amount) then
    raise exception 'Qatorlar yig''indisi hujjat summasiga teng emas' using errcode = '22023', hint = 'kassa:lines';
  end if;

  -- Asos (CT-24): xarajatda asos hujjati bo'lmasa — faqat L1 gacha va bitta statiya.
  if not p_internal then
    if v_nobasis then
      if v_op <> 'out_expense' then raise exception 'Asos hujjati majburiy' using errcode = '22023', hint = 'kassa:basis'; end if;
      if coalesce(v_org.l1, 0) <= 0 or v_amount > v_org.l1 or v_n > 1 then
        raise exception 'Asos hujjatisiz naqd xarid faqat % so''mgacha va bitta statiya bilan', coalesce(v_org.l1, 0) using errcode = '22023', hint = 'kassa:basis';
      end if;
    elsif length(v_basis) < 3 then
      raise exception 'Asos (hujjat nomi, raqami, sanasi) yozilmagan' using errcode = '22023', hint = 'kassa:basis';
    end if;
    if v_op = 'in_other' and length(v_note) < 3 then
      raise exception 'Boshqa kirimda izoh majburiy' using errcode = '22023', hint = 'kassa:note';
    end if;
  end if;

  -- Fiskal chek (CT-21): aholidan naqd kirimda raqam majburiy; istisno — faqat Direktor.
  v_fiscal := nullif(left(btrim(coalesce(p ->> 'fiscalNo', '')), 40), '');
  if v_rule."fiscalRequired" and v_fiscal is null then
    if app.kassa_bool(p, 'fiscalExempt') and (app.is_admin() or p_internal) then
      v_fexempt := true;
    else
      raise exception 'Fiskal chek raqami kiritilmagan' using errcode = '22023', hint = 'kassa:fiscal';
    end if;
  end if;
  -- Bitta fiskal chek — bitta kirim: shu raqam boshqa (bekor qilinmagan) hujjatda ishlatilgan bo'lsa rad etiladi.
  if v_fiscal is not null and exists (select 1 from public.cash_docs c where c."fiscalNo" = v_fiscal and c.desk = v_desk
                                          and c.status in ('draft', 'approved', 'posted') and c."createdAt" > now() - interval '400 days') then
    raise exception 'Bu fiskal chek raqami boshqa hujjatda ishlatilgan (%)', v_fiscal using errcode = '22023', hint = 'kassa:fiscal_dup';
  end if;

  -- Tasdiq talablari (CT-07): 2-ro'yxat; T1 dan katta chiqim, rahbarga berish, qarz — Direktor ham.
  if p_internal then
    v_need2 := app.kassa_bool(p, 'needsList2');
    v_needd := app.kassa_bool(p, 'needsDirector');
  else
    v_need2 := v_rule."needsApproval";
    v_needd := v_rule."directorAlways" or (p_form = 'KO2' and v_rule."needsApproval" and v_amount > coalesce(v_org.t1, 0));
  end if;

  begin v_cap := nullif(p ->> 'capturedAt', '')::timestamptz; exception when others then v_cap := null; end;
  if v_cap is not null and v_cap > app.fin_now() + interval '5 minutes' then v_cap := null; end if;

  o_id := 'kd_' || replace(gen_random_uuid()::text, '-', '');
  insert into public.cash_docs (id, desk, form, op, status, amount, "partyType", "partyId", "partyName", basis, attachment, note, "noBasis",
                                "fiscalNo", "fiscalExempt", "sourceTable", "sourceId", "sourceSnapshot", "clientRef", "capturedAt",
                                "needsList2", "needsDirector", "requestedBy", "requestedAt", "isSystem", "createdBy")
    values (o_id, v_desk, p_form, v_op, 'draft', v_amount, v_ptype, v_pid, coalesce(v_pname, ''), v_basis, v_attach, v_note, v_nobasis,
            v_fiscal, v_fexempt,
            case when p_internal then nullif(p ->> 'sourceTable', '') end, case when p_internal then nullif(p ->> 'sourceId', '') end,
            case when p_internal then p -> 'sourceSnapshot' end, v_ref, v_cap,
            v_need2, v_needd, p_uid, now(), p_internal and app.kassa_bool(p, 'isSystem'), p_uid);
  insert into public.cash_doc_lines (id, "docId", "lineNo", debit, credit, amount, "articleId", cash, analytics, note)
    select o_id || '_' || (r ->> 'n'), o_id, (r ->> 'n')::int, r ->> 'debit', r ->> 'credit', (r ->> 'amount')::numeric,
           r ->> 'articleId', (r ->> 'cash')::boolean, r -> 'analytics', r ->> 'note'
      from jsonb_array_elements(v_rows) r;
end $$;
revoke all on function app.kassa_doc_build(jsonb, text, text, boolean) from public, anon, authenticated;

-- ---------- Hujjat qaysi kassa kuniga yoziladi (kassa qulfi ostida chaqiriladi) ----------
--   Odatda — bugungi ochiq kun (yo'q bo'lsa ochiladi: kun boshi = oldingi kun oxiri). Oldingi kun yopilmagan bo'lsa — rad,
--   faqat o'sha kuni olingan (capturedAt) oflayn yozuv o'sha ochiq kunga tushadi. Olingan kuni yopilgan bo'lsa — joriy ochiq
--   kunga «kech» belgisi bilan. 48 soatdan eski yozuv — faqat Direktor ruxsati bilan (p_late_ok).
create or replace function app.kassa_resolve_day(p_desk text, p_captured timestamptz, p_uid text, p_late_ok boolean,
                                                 out o_day_id text, out o_day date, out o_late boolean)
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_today date := app.fin_today(); v_now timestamptz := app.fin_now();
  v_open public.cash_days%rowtype; v_last public.cash_days%rowtype; v_k public.cash_desks%rowtype; v_cap date; v_opening numeric;
begin
  o_late := false;
  if p_captured is not null and p_captured > v_now + interval '5 minutes' then p_captured := null; end if;
  if p_captured is not null then
    v_cap := (p_captured at time zone 'Asia/Tashkent')::date;
    if p_captured < v_now - interval '48 hours' and not coalesce(p_late_ok, false) then
      raise exception '48 soatdan oldin olingan pul — faqat Direktor ruxsati bilan kech kiritiladi' using errcode = 'P0001', hint = 'kassa:late_limit';
    end if;
  end if;
  select * into v_open from public.cash_days d where d.desk = p_desk and d.status = 'open';
  if found then
    if v_open.day = v_today then
      o_day_id := v_open.id; o_day := v_open.day; o_late := (v_cap is not null and v_cap < v_today); return;
    elsif v_open.day < v_today then
      if v_cap is not null and v_cap = v_open.day then o_day_id := v_open.id; o_day := v_open.day; return; end if;
      raise exception '% kuni yopilmagan — avval pulni sanab, kunni yoping', to_char(v_open.day, 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:prev_open';
    else
      raise exception 'Server sanasi ochiq kassa kunidan (%) oldin — soatni tekshiring', to_char(v_open.day, 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:clock';
    end if;
  end if;
  select * into v_last from public.cash_days d where d.desk = p_desk order by d.day desc limit 1;
  if found then
    if v_last.day = v_today then
      raise exception 'Bugungi kassa kuni yopilgan. Yangi hujjat uchun Direktor kunni qayta ochishi kerak' using errcode = 'P0001', hint = 'kassa:day_closed';
    elsif v_last.day > v_today then
      raise exception 'Server sanasi oxirgi kassa kunidan (%) oldin — soatni tekshiring', to_char(v_last.day, 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:clock';
    end if;
    v_opening := v_last.closing;
  else
    select * into v_k from public.cash_desks k where k.id = p_desk;
    if v_k."startDay" is null or v_k."openingAmount" is null then
      raise exception 'Kassa hali ishga tushirilmagan: boshlang''ich qoldiq kiritilmagan (Direktor)' using errcode = 'P0001', hint = 'kassa:not_started';
    end if;
    if v_today < v_k."startDay" then
      raise exception 'Kassa % dan ishlaydi', to_char(v_k."startDay", 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:not_started';
    end if;
    v_opening := v_k."openingAmount";
  end if;
  o_day_id := 'cd_' || p_desk || '_' || to_char(v_today, 'YYYY-MM-DD'); o_day := v_today;
  insert into public.cash_days (id, desk, day, status, opening, "cashierUid", "openedBy")
    values (o_day_id, p_desk, v_today, 'open', v_opening, p_uid, p_uid);
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), o_day_id, p_desk, v_today, 'open', p_uid, jsonb_build_object('opening', v_opening));
  o_late := (v_cap is not null and v_cap < v_today);
end $$;
revoke all on function app.kassa_resolve_day(text, timestamptz, text, boolean) from public, anon, authenticated;

-- ---------- O'tkazish: kassa qulfi → kun → qoldiq → OXIRIDA raqam ----------
--   p_captured — faqat DARHOL o'tkaziladigan kirimda (oflayn navbat): pul olingan payt. Tasdiqdan keyin to'lanadigan
--   hujjatda berilmaydi (pul to'lash paytida beriladi — kun o'sha payt bo'yicha).
--   p_day_id   — tizim hujjati (sanash farqi) aynan shu OCHIQ kunga yoziladi (kecha yopilayotgan bo'lsa ham).
create or replace function app.kassa_doc_post(p_doc_id text, p_uid text, p_system boolean default false,
                                              p_captured timestamptz default null, p_late_ok boolean default false,
                                              p_day_id text default null)
returns public.cash_docs
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_desk text; v_doc public.cash_docs%rowtype; v_day_id text; v_day date; v_late boolean; v_bal numeric; v_no int;
begin
  select c.desk into v_desk from public.cash_docs c where c.id = p_doc_id;
  if v_desk is null then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  perform app.kassa_lock_desk(v_desk);                                         -- L4
  select * into v_doc from public.cash_docs c where c.id = p_doc_id for update;
  if v_doc.status = 'posted' then return v_doc; end if;                        -- qayta chaqiruv: o'zgarishsiz
  if v_doc.status not in ('draft', 'approved') or v_doc.form not in ('KO1', 'KO2') then
    raise exception 'Hujjat o''tkazilmaydi (holati: %)', v_doc.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  if (v_doc."needsList2" and v_doc."approvedBy" is null) or (v_doc."needsDirector" and v_doc."dirApprovedBy" is null) then
    raise exception 'Hujjat tasdiqlanmagan — avval tasdiq kerak' using errcode = '42501', hint = 'kassa:not_approved';
  end if;
  if p_day_id is not null then
    select d.id, d.day, false into v_day_id, v_day, v_late from public.cash_days d where d.id = p_day_id and d.desk = v_desk and d.status = 'open';
    if not found then raise exception 'Kassa kuni ochiq emas' using errcode = 'P0001', hint = 'kassa:day_closed'; end if;
  else
    select d.o_day_id, d.o_day, d.o_late into v_day_id, v_day, v_late from app.kassa_resolve_day(v_desk, p_captured, p_uid, p_late_ok) d;
  end if;
  if v_doc.form = 'KO2' then
    v_bal := app.kassa_day_balance(v_day_id);
    if v_bal < v_doc.amount then   -- CT-12
      raise exception 'Kassada yetarli pul yo''q: qoldiq % so''m, kerak % so''m', v_bal, v_doc.amount using errcode = 'P0001', hint = 'kassa:negative';
    end if;
  end if;
  v_no := app.kassa_next_no(v_desk, v_doc.form, extract(year from v_day)::int);   -- L5: oxirgi qadam
  update public.cash_docs
     set status = 'posted', year = extract(year from v_day)::int, no = v_no, "businessDay" = v_day, "dayId" = v_day_id,
         "postedBy" = case when p_system then null else p_uid end, "postedAt" = now(), late = v_late
   where id = p_doc_id returning * into v_doc;
  return v_doc;
end $$;
revoke all on function app.kassa_doc_post(text, text, boolean, timestamptz, boolean, text) from public, anon, authenticated;

-- Naqdsiz dalolatnomani (ACT) o'tkazish: kassa kuniga bog'lanmaydi, o'z raqam seriyasi.
create or replace function app.kassa_act_post(p_doc_id text, p_uid text, p_day date) returns public.cash_docs
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_desk text; v_doc public.cash_docs%rowtype; v_no int;
begin
  select c.desk into v_desk from public.cash_docs c where c.id = p_doc_id;
  if v_desk is null then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  perform app.kassa_lock_desk(v_desk);
  select * into v_doc from public.cash_docs c where c.id = p_doc_id for update;
  if v_doc.status = 'posted' then return v_doc; end if;
  if v_doc.status not in ('draft', 'approved') or v_doc.form <> 'ACT' then
    raise exception 'Dalolatnoma o''tkazilmaydi (holati: %)', v_doc.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  v_no := app.kassa_next_no(v_desk, 'ACT', extract(year from p_day)::int);
  update public.cash_docs
     set status = 'posted', year = extract(year from p_day)::int, no = v_no, "businessDay" = p_day, "postedBy" = p_uid, "postedAt" = now()
   where id = p_doc_id returning * into v_doc;
  return v_doc;
end $$;
revoke all on function app.kassa_act_post(text, text, date) from public, anon, authenticated;

-- Hujjat + qatorlari + chop etishlar soni (javob uchun).
create or replace function app.kassa_doc_json(p_id text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select to_jsonb(c) || jsonb_build_object('lines', coalesce((
           select jsonb_agg(to_jsonb(l) - 'docId' order by l."lineNo") from public.cash_doc_lines l where l."docId" = c.id), '[]'::jsonb),
           'prints', (select count(*) from public.cash_prints x where x."docId" = c.id))   -- necha marta chop etishga yuborilgan
    from public.cash_docs c where c.id = p_id
$$;
revoke all on function app.kassa_doc_json(text) from public, anon, authenticated;

-- ---------- KO-1: kirim orderi ----------
create or replace function public.kassa_receipt(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_id text; v_dup boolean; v_doc public.cash_docs%rowtype;
begin
  if not (app.kassa_operator() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: kirim orderini kassir (favqulodda — Direktor) yozadi' using errcode = '42501';
  end if;
  perform app.kassa_flag(true);
  select b.o_id, b.o_dup into v_id, v_dup from app.kassa_doc_build(p, 'KO1', v_uid, false) b;
  select * into v_doc from public.cash_docs c where c.id = v_id;
  -- Direktor ruxsati kerak bo'lmagan kirim darhol o'tkaziladi; kerak bo'lsa — so'rov bo'lib qoladi (keyin kassa_doc_pay).
  --   48 soatdan eski (qog'oz «Қ» bo'yicha) kirimni faqat Direktor o'zi kiritadi.
  if v_doc.status = 'draft' and not v_doc."needsList2" and not v_doc."needsDirector" then
    v_doc := app.kassa_doc_post(v_id, v_uid, false, v_doc."capturedAt", app.is_admin());
  end if;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(v_id) || jsonb_build_object('ok', true, 'dup', v_dup);
end $$;
revoke all on function public.kassa_receipt(jsonb) from public, anon;
grant execute on function public.kassa_receipt(jsonb) to authenticated;

-- ---------- KO-2: chiqim so'rovi (raqamsiz; pul berilmaydi) ----------
create or replace function public.kassa_payout_request(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_id text; v_dup boolean;
begin
  if not (app.kassa_operator() or app.is_admin() or app.is_finance_mgr()) then
    raise exception 'Ruxsat yo''q: chiqim so''rovini kassir, Moliya menejeri yoki Direktor yozadi' using errcode = '42501';
  end if;
  -- Ish haqi avansi: shu oy vedomosti tasdiqlangan bo'lsa so'rov ham qabul qilinmaydi (kassa-links.sql).
  if jsonb_typeof(p) = 'object' and coalesce(p ->> 'op', '') = 'out_advance' then
    perform app.kassa_advance_check(to_char(app.fin_today(), 'YYYY-MM'));
  end if;
  perform app.kassa_flag(true);
  select b.o_id, b.o_dup into v_id, v_dup from app.kassa_doc_build(p, 'KO2', v_uid, false) b;
  -- Tasdiq talab qilmaydigan chiqim (hozircha qo'lda kiritiladiganlar ichida yo'q) darhol «tasdiqlangan» bo'ladi.
  update public.cash_docs set status = 'approved'
   where id = v_id and status = 'draft' and not "needsList2" and not "needsDirector";
  perform app.kassa_flag(false);
  return app.kassa_doc_json(v_id) || jsonb_build_object('ok', true, 'dup', v_dup);
end $$;
revoke all on function public.kassa_payout_request(jsonb) from public, anon;
grant execute on function public.kassa_payout_request(jsonb) to authenticated;

-- ---------- Tasdiqlash: 2-ro'yxat (≠ so'rovchi) va / yoki Direktor ----------
create or replace function public.kassa_doc_approve(p_id text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_doc public.cash_docs%rowtype; v_dup boolean := false;
begin
  if not (app.fin_list2() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: hujjatni Moliya menejeri / buxgalter yoki Direktor tasdiqlaydi' using errcode = '42501';
  end if;
  select * into v_doc from public.cash_docs c where c.id = p_id for update;
  if not found then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if v_doc.status <> 'draft' then
    if v_doc.status in ('approved', 'posted') and v_uid in (v_doc."approvedBy", v_doc."dirApprovedBy") then
      return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', true);
    end if;
    raise exception 'Hujjat tasdiq kutmayapti (holati: %)', v_doc.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  perform app.kassa_flag(true);
  if app.fin_list2() and v_doc."needsList2" and v_doc."approvedBy" is null then
    if v_doc."requestedBy" = v_uid then   -- CT-07
      raise exception 'O''zingiz so''ragan hujjatni o''zingiz tasdiqlay olmaysiz' using errcode = '42501', hint = 'kassa:self_approve';
    end if;
    update public.cash_docs set "approvedBy" = v_uid, "approvedAt" = now() where id = p_id;
  elsif app.is_admin() and v_doc."needsDirector" and v_doc."dirApprovedBy" is null then
    update public.cash_docs set "dirApprovedBy" = v_uid, "dirApprovedAt" = now() where id = p_id;
  elsif v_uid in (v_doc."approvedBy", v_doc."dirApprovedBy") then
    v_dup := true;
  else
    raise exception 'Bu hujjatda sizning tasdig''ingiz talab qilinmaydi' using errcode = '42501', hint = 'kassa:no_approval';
  end if;
  update public.cash_docs set status = 'approved'
   where id = p_id and status = 'draft'
     and (not "needsList2" or "approvedBy" is not null) and (not "needsDirector" or "dirApprovedBy" is not null);
  perform app.kassa_flag(false);
  return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', v_dup);
end $$;
revoke all on function public.kassa_doc_approve(text, text) from public, anon;
grant execute on function public.kassa_doc_approve(text, text) to authenticated;

-- ---------- Rad etish (tasdiqlovchilar) ----------
create or replace function public.kassa_doc_reject(p_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_doc public.cash_docs%rowtype; v_reason text := left(btrim(coalesce(p_reason, '')), 500);
begin
  if not (app.fin_list2() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: hujjatni Moliya menejeri / buxgalter yoki Direktor rad etadi' using errcode = '42501';
  end if;
  if length(v_reason) < 3 then raise exception 'Rad etish sababini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  select * into v_doc from public.cash_docs c where c.id = p_id for update;
  if not found then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if v_doc.status = 'rejected' then return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', true); end if;
  if v_doc.status <> 'draft' then
    raise exception 'Faqat tasdiq kutayotgan hujjat rad etiladi (holati: %)', v_doc.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  perform app.kassa_flag(true);
  update public.cash_docs set status = 'rejected', "rejectedBy" = v_uid, "rejectedAt" = now(), "rejectReason" = v_reason where id = p_id;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.kassa_doc_reject(text, text) from public, anon;
grant execute on function public.kassa_doc_reject(text, text) to authenticated;

-- ---------- So'rovni bekor qilish (pul berilmagan): so'rovchi yoki Direktor ----------
create or replace function public.kassa_doc_cancel(p_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_doc public.cash_docs%rowtype; v_reason text := left(btrim(coalesce(p_reason, '')), 500);
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  if length(v_reason) < 3 then raise exception 'Bekor qilish sababini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  select * into v_doc from public.cash_docs c where c.id = p_id for update;
  if not found then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if v_doc.status = 'cancelled' then return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', true); end if;
  if v_doc.status not in ('draft', 'approved') then
    raise exception 'Faqat pul berilmagan so''rov bekor qilinadi (holati: %)', v_doc.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  if not (app.is_admin() or v_doc."requestedBy" = v_uid) then
    raise exception 'So''rovni uni yozgan xodim yoki Direktor bekor qiladi' using errcode = '42501';
  end if;
  perform app.kassa_flag(true);
  update public.cash_docs set status = 'cancelled', "voidedBy" = v_uid, "voidedAt" = now(), "voidReason" = v_reason where id = p_id;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.kassa_doc_cancel(text, text) from public, anon;
grant execute on function public.kassa_doc_cancel(text, text) to authenticated;

-- ---------- Tasdiqlangan hujjat bo'yicha pulni berish / qabul qilish ----------
--   Bog'langan amallar (kassa-links.sql) SHU tranzaksiyada bajariladi: tasdiqlangan qaytarish (out_refund) — refund_invoice;
--   ish haqi avansi (out_advance) — staff_advances qatori; xarajat (out_expense) — «Buxgalteriya»ga (expenses) ko'chirish.
--   Boshqa bo'limdan yozilib, o'sha zahoti o'tkaziladigan hujjatlar (o'quv to'lovi, maosh) bu yerdan to'lanmaydi.
create or replace function public.kassa_doc_pay(p_id text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_doc public.cash_docs%rowtype; v_was text; v_src text; v_op text; v_desk text;
begin
  if not (app.kassa_operator() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: naqd pulni kassir (favqulodda — Direktor) beradi' using errcode = '42501';
  end if;
  select c.status, c."sourceTable", c.op, c.desk into v_was, v_src, v_op, v_desk from public.cash_docs c where c.id = p_id;
  if v_was is null then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if v_src is not null and v_op <> 'out_refund' then
    raise exception 'Bu hujjat boshqa bo''limdan yozilgan — pul o''sha bo''limdan beriladi' using errcode = '42501', hint = 'kassa:linked_doc';
  end if;
  if v_was = 'draft' then
    raise exception 'Hujjat hali tasdiqlanmagan' using errcode = '42501', hint = 'kassa:not_approved';
  end if;
  perform app.kassa_link_prelock(p_id);   -- bog'langan amal qulflari kassa qulfidan OLDIN (qulf tartibi: L1 → L4)
  perform app.kassa_lock_desk(v_desk);    -- L4 (kassa_doc_post shu qulfni qayta oladi)
  select c.status into v_was from public.cash_docs c where c.id = p_id;   -- qulf ostida: aynan shu chaqiruv o'tkazadimi
  perform app.kassa_flag(true);
  v_doc := app.kassa_doc_post(p_id, v_uid);
  if v_was <> 'posted' and v_op in ('out_refund', 'out_advance', 'out_expense') then
    perform app.kassa_link_paid(p_id, v_uid);
  end if;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', v_was = 'posted');
end $$;
revoke all on function public.kassa_doc_pay(text) from public, anon;
grant execute on function public.kassa_doc_pay(text) to authenticated;

-- ---------- Shu kunning o'zida bekor qilish (raqam saqlanadi) ----------
--   Kassir — faqat o'zi o'tkazgan hujjatni; Moliya menejeri, buxgalter, Direktor — istalganini. Kun yopilgan bo'lsa — yo'q.
--   Naqd o'quv to'lovi orderi (in_tuition) bekor qilinsa — to'lovning o'zi ham teskari qilinadi (kassa-pay.sql:
--   app.tuition_reverse_core): fakturalar va avans to'lovdan OLDINGI holatga qaytadi, to'lov «bekor qilingan» bo'ladi, ota-onaga
--   hali yuborilmagan xabarnoma to'xtatiladi. Faqat shu to'lovdan keyin o'quvchi bo'yicha boshqa pul harakati bo'lmagan bo'lsa.
--   Naqd maosh (out_salary), ish haqi avansi (out_advance) va xarajat (out_expense) orderi bekor qilinsa — bog'langan yozuv
--   (maosh to'lovi, avans, «Buxgalteriya»dagi xarajat) ham olib tashlanadi (kassa-links.sql: app.kassa_link_void).
--   Qaytarish orderi (out_refund) bekor qilinmaydi.
create or replace function public.kassa_doc_void(p_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_desk text; v_doc public.cash_docs%rowtype; v_day public.cash_days%rowtype;
        v_reason text := left(btrim(coalesce(p_reason, '')), 500); v_bal numeric; v_op text; v_src text; v_party text; v_tuition boolean;
begin
  if not (app.kassa_operator() or app.fin_list2() or app.is_admin()) then
    raise exception 'Ruxsat yo''q' using errcode = '42501';
  end if;
  if length(v_reason) < 5 then raise exception 'Bekor qilish sababini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  select c.desk, c.op, c."sourceTable", c."partyId" into v_desk, v_op, v_src, v_party from public.cash_docs c where c.id = p_id;
  if v_desk is null then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  v_tuition := (v_op = 'in_tuition' and v_src = 'payments');
  -- Qulf tartibi: o'quvchi bo'yicha navbat (L1) kassa qulfidan (L4) OLDIN — yangi to'lov bilan o'zaro qulflanish bo'lmasin.
  if v_tuition then perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_party, ''))); end if;
  perform app.kassa_lock_desk(v_desk);
  select * into v_doc from public.cash_docs c where c.id = p_id for update;
  if v_doc.status = 'void' then return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', true); end if;
  if v_doc.status <> 'posted' or v_doc.form not in ('KO1', 'KO2') then
    raise exception 'Faqat o''tkazilgan kassa orderi bekor qilinadi (holati: %)', v_doc.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  if v_doc."isSystem" then
    raise exception 'Sanash farqi hujjati alohida bekor qilinmaydi (Direktor kunni qayta ochadi)' using errcode = '42501', hint = 'kassa:system_doc';
  end if;
  if v_doc."sourceTable" is not null and not v_tuition and v_doc.op <> 'out_salary' then
    raise exception 'Bu hujjat bekor qilinmaydi (qaytarish orderi — xato bo''lsa, pulni yangi to''lov sifatida qayta qabul qiling)' using errcode = '42501', hint = 'kassa:linked_doc';
  end if;
  if not (app.fin_list2() or app.is_admin()) and v_doc."postedBy" is distinct from v_uid then
    raise exception 'Kassir faqat o''zi o''tkazgan hujjatni bekor qiladi' using errcode = '42501', hint = 'kassa:not_own';
  end if;
  select * into v_day from public.cash_days d where d.id = v_doc."dayId";
  if v_day.status <> 'open' then
    raise exception 'Kun yopilgan — hujjat bekor qilinmaydi (Direktor kunni qayta ochadi yoki buxgalter storno qiladi)' using errcode = 'P0001', hint = 'kassa:day_closed';
  end if;
  if v_doc.form = 'KO1' then
    v_bal := app.kassa_day_balance(v_day.id);
    if v_bal < v_doc.amount then
      raise exception 'Bekor qilinsa kassa qoldig''i manfiy bo''lib qoladi (qoldiq % so''m)', v_bal using errcode = 'P0001', hint = 'kassa:negative';
    end if;
  end if;
  perform app.kassa_flag(true);
  if v_tuition then perform app.tuition_reverse_core(p_id, v_uid, v_reason); end if;
  if v_doc.op in ('out_salary', 'out_advance', 'out_expense') then perform app.kassa_link_void(p_id, v_uid, v_reason); end if;
  update public.cash_docs set status = 'void', "voidedBy" = v_uid, "voidedAt" = now(), "voidReason" = v_reason where id = p_id;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', false, 'balance', app.kassa_day_balance(v_day.id));
end $$;
revoke all on function public.kassa_doc_void(text, text) from public, anon;
grant execute on function public.kassa_doc_void(text, text) to authenticated;

notify pgrst, 'reload schema';
