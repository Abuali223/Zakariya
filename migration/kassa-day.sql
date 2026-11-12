\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: kassa-day.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- kassa-day.sql — MOLIYA ISH REJASI, 1a-BOSQICH (F1.9): KASSA KUNI SIKLI VA O'QISH FUNKSIYALARI.
--   kassa_opening_set(p)        — boshlang'ich qoldiq (komissiya sanashi) va birinchi kassa kuni: FAQAT Direktor, kassa ishga tushguncha;
--   kassa_day_close(p)          — kunni SANAB yopish: farq (sanalgan − hisobdagi − hali o'tkazilmagan) shu kun sanasi bilan tizim
--                                 hujjatiga aylanadi (kamomad KO-2 Dt 5910, ortiqcha KO-1 Kt 9390), varaqlar va xesh muzlaydi;
--   kassa_handover(p)           — smena topshirish-qabul sanashi (kun ochiq qoladi, kassir almashadi; farq — darhol hujjat);
--   kassa_day_verify(...)       — 2-ro'yxat / Direktor tekshiradi: tekshiruvchi ≠ yopuvchi va ≠ shu kun hujjat o'tkazganlar;
--                                 raqamlarda bo'shliq, xesh yoki jamlar mos kelmasa — rad;
--   kassa_day_z(p)              — onlayn kassa (NKM) Z-hisobotini kiritish / tuzatish (kun tekshirilguncha; yopishda ham beriladi);
--                                 tizim Z ni fiskal chekli KO-1 va terminal to'lovlari bilan solishtiradi (F1.26);
--   kassa_day_reopen(...)       — FAQAT Direktor, sabab bilan, faqat oxirgi yopilgan (tekshirilmagan) kun;
--   kassa_shortage_decide(...)  — kamomad bo'yicha Direktor qarori (xodim zimmasiga 4730 / hisobdan chiqarish 9430);
--   kassa_state(desk)           — «Kassa» kun kartasi uchun holat; kassa_day_book(desk, day) — KO-4 / kunlik hisobot (RP-02) ma'lumoti;
--   kassa_journal(desk, from, to) — KO-3: kirim va chiqim orderlari jurnali (davr ≤ 93 kun; chop etish va XLSX — sahifada);
--   kassa_journal_export(...)   — KO-3 Excel uchun ma'lumot (FD-28): kassirga yo'q, 2-ro'yxatga ismsiz, Direktorga to'liq;
--   kassa_checks(desk)          — nazorat ro'yxati, RP-06 (raqam bo'shliqlari, yopilmagan / tekshirilmagan kunlar, qarorsiz kamomad,
--                                 moslik P1/P4/P5/P8, hisobdorlar muddati, limit, Z-hisobot …);
--   app.kassa_daily(day)        — Direktorning kunlik Telegram hisobotidagi kassa bloki va nazorat qatori (RP-05; director_daily chaqiradi);
--   kassa_refs() / kassa_people() / kassa_overview(desk) / kassa_doc_get(id) — «Kassa» ekrani va chop etish uchun o'qish;
--   kassa_print_mark(kind, id)  — chop etish jurnali: birinchi chop etish — asl nusxa, keyingilari — «НУСХА».
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi.
-- =====================================================================

-- ---------- Yordamchilar ----------
-- Yopilgan kun mazmuni izi: kun boshi + hujjatlar (raqam, holat, summa, tomon, Dt/Kt qatorlari). Yopilgandan keyin o'zgarmasligi shart.
create or replace function app.kassa_day_hash(p_day_id text) returns text
language sql stable security definer set search_path = public, app, pg_temp as $$
  select encode(sha256(convert_to(
           d.desk || '|' || to_char(d.day, 'YYYY-MM-DD') || '|' || trim_scale(d.opening)::text || '|' ||
           coalesce((select string_agg(
                       c.form || ':' || c.no || ':' || c.status || ':' || trim_scale(c.amount)::text || ':' || c.op || ':' ||
                       coalesce(c."partyType", '') || ':' || coalesce(c."partyId", '') || ':' ||
                       coalesce((select string_agg(l.debit || '>' || l.credit || '=' || trim_scale(l.amount)::text || '@' || coalesce(l."articleId", ''), ','
                                                   order by l."lineNo")
                                   from public.cash_doc_lines l where l."docId" = c.id), ''),
                       ';' order by c.form, c.no)
                       from public.cash_docs c where c."dayId" = d.id and c.status in ('posted', 'void')), ''), 'UTF8')), 'hex')
    from public.cash_days d where d.id = p_day_id
$$;
revoke all on function app.kassa_day_hash(text) from public, anon, authenticated;

-- Raqamlash nazorati: hisoblagich = hujjatlar soni = eng katta raqam (bo'shliq va takror yo'q).
create or replace function app.kassa_gap_check(p_desk text, p_year int) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('series', x.series, 'lastNo', x.last_no, 'count', x.cnt, 'max', x.mx) order by x.series), '[]'::jsonb)
    from (select s.series,
                 coalesce((select k."lastNo" from public.doc_counters k where k.desk = p_desk and k.series = s.series and k.year = p_year), 0) as last_no,
                 (select count(*) from public.cash_docs c where c.desk = p_desk and c.form = s.series and c.year = p_year and c.no is not null) as cnt,
                 coalesce((select max(c.no) from public.cash_docs c where c.desk = p_desk and c.form = s.series and c.year = p_year), 0) as mx
            from (values ('KO1'), ('KO2'), ('ACT')) s(series)) x
   where x.last_no <> x.cnt or x.last_no <> x.mx
$$;
revoke all on function app.kassa_gap_check(text, int) from public, anon, authenticated;

-- JSON'dan manfiy bo'lmagan summa (0 mumkin): sanalgan pul, hali o'tkazilmagan yozuvlar.
create or replace function app.kassa_amount0(p_val jsonb, p_what text) returns numeric
language plpgsql immutable set search_path = public, app, pg_temp as $$
declare v numeric;
begin
  if p_val is null or jsonb_typeof(p_val) = 'null' then return null; end if;
  if jsonb_typeof(p_val) not in ('number', 'string') then
    raise exception '%: summa noto''g''ri', p_what using errcode = '22023', hint = 'kassa:amount';
  end if;
  begin v := (p_val #>> '{}')::numeric;
  exception when others then raise exception '%: summa noto''g''ri', p_what using errcode = '22023', hint = 'kassa:amount'; end;
  if v is null or v = 'NaN'::numeric or not (v >= 0 and v < 1e12) or v <> round(v, 2) then
    raise exception '%: summa noto''g''ri (manfiy emas, tiyin 2 xonagacha)', p_what using errcode = '22023', hint = 'kassa:amount';
  end if;
  return v;
end $$;
revoke all on function app.kassa_amount0(jsonb, text) from public, anon, authenticated;

-- Nominallar bo'yicha sanash {"100000": 12, "50000": 3} — yig'indisi sanalgan summaga teng bo'lishi shart.
create or replace function app.kassa_denoms_check(p_denoms jsonb, p_counted numeric) returns jsonb
language plpgsql immutable set search_path = public, app, pg_temp as $$
declare k text; v_sum numeric := 0; v_nom numeric; v_cnt numeric;
begin
  if p_denoms is null or jsonb_typeof(p_denoms) = 'null' then return null; end if;
  if jsonb_typeof(p_denoms) <> 'object' then
    raise exception 'Nominallar noto''g''ri' using errcode = '22023', hint = 'kassa:denoms';
  end if;
  if p_denoms = '{}'::jsonb then return null; end if;
  for k in select jsonb_object_keys(p_denoms) loop
    begin v_nom := k::numeric; v_cnt := (p_denoms ->> k)::numeric;
    exception when others then raise exception 'Nominallar noto''g''ri' using errcode = '22023', hint = 'kassa:denoms'; end;
    if v_nom is null or v_cnt is null or v_nom = 'NaN'::numeric or v_cnt = 'NaN'::numeric
       or not (v_nom > 0 and v_nom < 1e9) or not (v_cnt >= 0 and v_cnt < 1e9) or v_cnt <> trunc(v_cnt) then
      raise exception 'Nominallar noto''g''ri' using errcode = '22023', hint = 'kassa:denoms';
    end if;
    v_sum := v_sum + v_nom * v_cnt;
  end loop;
  if v_sum <> p_counted then
    raise exception 'Nominallar yig''indisi (%) sanalgan summaga (%) teng emas', v_sum, p_counted using errcode = '22023', hint = 'kassa:denoms';
  end if;
  return p_denoms;
end $$;
revoke all on function app.kassa_denoms_check(jsonb, numeric) from public, anon, authenticated;

-- Komissiya a'zolari [{title, name}] — matnlar tozalanadi; nechta a'zo borligi qaytadi.
create or replace function app.kassa_commission(p jsonb) returns jsonb
language sql immutable set search_path = public, app, pg_temp as $$
  select coalesce((select jsonb_agg(jsonb_build_object('title', left(btrim(coalesce(m ->> 'title', '')), 120), 'name', left(btrim(coalesce(m ->> 'name', '')), 200)))
                     from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) m
                    where jsonb_typeof(m) = 'object' and length(btrim(coalesce(m ->> 'name', ''))) >= 3), '[]'::jsonb)
$$;
revoke all on function app.kassa_commission(jsonb) from public, anon, authenticated;

-- ---------- Sanash yadrosi: farq bo'lsa — SHU KUN sanasi bilan tizim hujjati (CT-14) ----------
--   farq = sanalgan − hisobdagi qoldiq − hali o'tkazilmagan (oflayn) yozuvlar. Kamomad — KO-2 Dt 5910; ortiqcha — KO-1 Kt 9390.
--   Tizim hujjati hech kimni «o'tkazuvchi» qilmaydi (postedBy bo'sh) — tekshiruvchini cheklamaydi.
create or replace function app.kassa_count_apply(p_desk text, p_day_id text, p_day date, p_kind text, p_counted numeric, p_pending numeric,
                                                 p_denoms jsonb, p_commission jsonb, p_note text, p_uid text, p_to_uid text,
                                                 out o_expected numeric, out o_diff numeric, out o_doc_id text, out o_count_id text)
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_cashier text;
begin
  o_expected := app.kassa_day_balance(p_day_id);
  if p_counted < p_pending then
    raise exception 'Sanalgan summa hali o''tkazilmagan yozuvlar summasidan kam bo''lmaydi' using errcode = '22023', hint = 'kassa:count';
  end if;
  o_diff := p_counted - o_expected - p_pending;
  if o_diff <> 0 then
    select d."cashierUid" into v_cashier from public.cash_days d where d.id = p_day_id;
    select b.o_id into o_doc_id from app.kassa_doc_build(jsonb_build_object(
        'desk', p_desk, 'op', case when o_diff > 0 then 'in_surplus' else 'out_shortage' end, 'amount', abs(o_diff),
        'clientRef', 'sysdiff_' || replace(gen_random_uuid()::text, '-', ''), 'isSystem', true,
        'partyName', case when o_diff > 0 then 'Kassa ortiqchasi' else 'Kassa kamomadi' end,
        'basis', 'Kassani sanash dalolatnomasi, ' || to_char(p_day, 'DD.MM.YYYY'),
        'note', case p_kind when 'handover' then 'Smena topshirish-qabul sanashi' else 'Kun yopish sanashi' end,
        'sourceSnapshot', jsonb_build_object('cashierUid', v_cashier, 'expected', o_expected, 'counted', p_counted, 'pending', p_pending, 'kind', p_kind)),
      case when o_diff > 0 then 'KO1' else 'KO2' end, p_uid, true) b;
    perform app.kassa_doc_post(o_doc_id, p_uid, true, null, false, p_day_id);
  end if;
  o_count_id := 'cc_' || replace(gen_random_uuid()::text, '-', '');
  insert into public.cash_counts (id, desk, day, "dayId", kind, expected, counted, "pendingSum", diff, "diffDocId", denoms, commission, "fromUid", "toUid", note, "byUid")
    values (o_count_id, p_desk, p_day, p_day_id, p_kind, o_expected, p_counted, p_pending, o_diff, o_doc_id, p_denoms, p_commission,
            case when p_kind = 'handover' then p_uid end, p_to_uid, left(btrim(coalesce(p_note, '')), 500), p_uid);
end $$;
revoke all on function app.kassa_count_apply(text, text, date, text, numeric, numeric, jsonb, jsonb, text, text, text) from public, anon, authenticated;

-- Foydalanuvchi ismlari {uid: ism} — ekran va chop etish uchun (faqat berilgan uid'lar).
create or replace function app.kassa_names(p_uids text[]) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select jsonb_object_agg(u.id, coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), u.id))
                     from public.users u where u.id = any (coalesce(p_uids, '{}'))), '{}'::jsonb)
$$;
revoke all on function app.kassa_names(text[]) from public, anon, authenticated;

-- ---------- Onlayn kassa (NKM) Z-hisoboti (F1.26, buxgalter ko'rigi M6) ----------
--   Kun oxirida kassir NKM Z-hisobotidagi SOTUV jamlarini kiritadi: naqd va bank kartasi (qaytarishlarsiz). Tizim solishtiradi:
--     naqd  ↔ shu kunning fiskal chekli kirim orderlari (KO-1, "fiscalNo" bor, bekor qilinmagan; fiskal cheksiz istisno — chekda yo'q);
--     karta ↔ shu kunning terminal to'lovlari («💵 To‘lov» → Terminal; kassa kuni bo'yicha, app.fin_receipts bilan bir xil qoida).
--   Faktlar (Z raqami va summalar yoki «Z-hisobot yo'q» + sabab) kun hodisasi bo'lib yoziladi (cash_day_events, 'zreport'; faqat
--   qo'shiladi, oxirgisi amalda); kutilgan summalar va farq har safar hujjatlardan hisoblanadi (qayta ochilgan kunda ham to'g'ri).
--   Kiritilmagan yoki mos kelmagan Z kunni yopishga to'sqinlik qilmaydi: nazorat ro'yxatida ko'rinadi, kunni tekshirishda izoh
--   talab qilinadi. Sinov kassasida Z-hisobot yuritilmaydi (karta to'lovlari asosiy kassaga tegishli).
create or replace function app.kassa_z_state(p_day_id text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_d public.cash_days%rowtype; v_e public.cash_day_events%rowtype; v_cash numeric; v_ncash int; v_card numeric; v_ncard int;
  v_rec boolean; v_miss boolean; v_need boolean; v_zc numeric; v_zk numeric; v_dc numeric; v_dk numeric;
begin
  select * into v_d from public.cash_days d where d.id = p_day_id;
  if not found then return null; end if;
  if coalesce((select k."isTest" from public.cash_desks k where k.id = v_d.desk), false) then return jsonb_build_object('applies', false); end if;
  select coalesce(sum(c.amount), 0), count(*) into v_cash, v_ncash from public.cash_docs c
   where c."dayId" = v_d.id and c.form = 'KO1' and c.status = 'posted' and c."fiscalNo" is not null;
  -- terminal to'lovlari (app.fin_receipts bilan bir xil: kassa kuni = pay_day; avval arzon filtr — usul va kiritilgan vaqt oralig'i)
  select coalesce(sum(p.amount), 0), count(*) into v_card, v_ncard from public.payments p
   where p.provider = 'terminal'
     and p."createdAt" >= (v_d.day::timestamp at time zone 'Asia/Tashkent')
     and p."createdAt" <  ((v_d.day + 32)::timestamp at time zone 'Asia/Tashkent')
     and app.counts_as_receipt(p.id, p.status, p.provider, p.amount)
     and app.pay_day(p."createdAt", p.raw) = v_d.day;
  select * into v_e from public.cash_day_events e where e."dayId" = v_d.id and e.kind = 'zreport' order by e.at desc, e.id desc limit 1;
  v_rec := v_e.id is not null;
  v_miss := v_rec and coalesce((v_e.data ->> 'missing')::boolean, false);
  v_need := v_cash > 0 or v_card > 0;
  if v_rec and not v_miss then
    v_zc := (v_e.data ->> 'cash')::numeric; v_zk := (v_e.data ->> 'card')::numeric;
    v_dc := v_zc - v_cash; v_dk := v_zk - v_card;
  end if;
  return jsonb_build_object('applies', true, 'needed', v_need, 'recorded', v_rec, 'missing', v_miss,
    'no', v_e.data ->> 'no', 'reason', v_e.reason, 'cash', v_zc, 'card', v_zk, 'byUid', v_e."byUid", 'at', v_e.at,
    'expCash', v_cash, 'nCash', v_ncash, 'expCard', v_card, 'nCard', v_ncard, 'diffCash', v_dc, 'diffCard', v_dk,
    -- mos: kiritilgan Z tizim bilan teng; yoki Z kerak emas edi (shu kuni fiskal kirim va terminal to'lovi yo'q)
    'ok', case when v_rec and not v_miss then v_dc = 0 and v_dk = 0 else not v_need end);
end $$;
revoke all on function app.kassa_z_state(text) from public, anon, authenticated;

-- Z-hisobot faktini yozish (ichki; chaqiruvchi kassa bayrog'ini yoqqan). p_z: {no, cash, card[, note]} yoki {missing: true, reason}.
--   Oxirgi yozuv bilan aynan bir xil bo'lsa — qayta yozilmaydi (false qaytadi).
create or replace function app.kassa_z_put(p_day_id text, p_z jsonb, p_uid text) returns boolean
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_d public.cash_days%rowtype; v_no text; v_cash numeric; v_card numeric; v_miss boolean; v_reason text; v_data jsonb;
  v_last public.cash_day_events%rowtype;
begin
  if p_z is null or jsonb_typeof(p_z) <> 'object' then
    raise exception 'Z-hisobot ma''lumoti noto''g''ri' using errcode = '22023', hint = 'kassa:z';
  end if;
  select * into v_d from public.cash_days d where d.id = p_day_id;
  if not found then raise exception 'Kassa kuni topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if coalesce((select k."isTest" from public.cash_desks k where k.id = v_d.desk), false) then
    raise exception 'Sinov kassasida Z-hisobot yuritilmaydi' using errcode = '22023', hint = 'kassa:z';
  end if;
  v_miss := app.kassa_bool(p_z, 'missing');
  v_reason := left(btrim(coalesce(p_z ->> case when v_miss then 'reason' else 'note' end, '')), 300);
  if v_miss then
    if length(v_reason) < 5 then
      raise exception 'Z-hisobot yo''qligi sababini yozing (kamida 5 belgi)' using errcode = '22023', hint = 'kassa:z';
    end if;
    v_data := jsonb_build_object('missing', true);
  else
    v_no := btrim(coalesce(p_z ->> 'no', ''));
    if v_no !~ '^[0-9A-Za-z/-]{1,20}$' then
      raise exception 'Z-hisobot raqamini kiriting (kassa apparati chiqargan hisobotdagi №)' using errcode = '22023', hint = 'kassa:z';
    end if;
    v_cash := app.kassa_amount0(p_z -> 'cash', 'Z-hisobot: naqd');
    v_card := app.kassa_amount0(p_z -> 'card', 'Z-hisobot: bank kartasi');
    if v_cash is null or v_card is null then
      raise exception 'Z-hisobotdagi naqd va bank kartasi summalarini kiriting (bo''lmasa — 0)' using errcode = '22023', hint = 'kassa:z';
    end if;
    v_data := jsonb_build_object('missing', false, 'no', v_no, 'cash', v_cash, 'card', v_card);
  end if;
  select * into v_last from public.cash_day_events e where e."dayId" = v_d.id and e.kind = 'zreport' order by e.at desc, e.id desc limit 1;
  if v_last.id is not null and v_last.data = v_data and coalesce(v_last.reason, '') = v_reason then return false; end if;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", at, reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_d.id, v_d.desk, v_d.day, 'zreport', p_uid, clock_timestamp(), nullif(v_reason, ''), v_data);
  return true;
end $$;
revoke all on function app.kassa_z_put(text, jsonb, text) from public, anon, authenticated;

-- Kun (javob uchun): ochiq kunda jamlar hujjatlardan hisoblanadi.
create or replace function app.kassa_day_json(p_day_id text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select to_jsonb(d) || jsonb_build_object(
           'receiptsLive', coalesce((select sum(c.amount) from public.cash_docs c where c."dayId" = d.id and c.status = 'posted' and c.form = 'KO1'), 0),
           'payoutsLive',  coalesce((select sum(c.amount) from public.cash_docs c where c."dayId" = d.id and c.status = 'posted' and c.form = 'KO2'), 0),
           'balance', app.kassa_day_balance(d.id),
           'docs', (select count(*) from public.cash_docs c where c."dayId" = d.id and c.status in ('posted', 'void')),
           'voids', (select count(*) from public.cash_docs c where c."dayId" = d.id and c.status = 'void'),
           -- kassa kitobi varag'i necha marta chop etishga yuborilgan: hozirgi holati (prints) va qayta ochilishdan oldingisi (printsOld)
           'prints', (select count(*) from public.cash_prints x where x."dayId" = d.id and x.kind = 'book' and x.version = d."reopenCount"),
           'printsOld', (select count(*) from public.cash_prints x where x."dayId" = d.id and x.kind = 'book' and x.version < d."reopenCount"),
           -- onlayn kassa Z-hisoboti: ochiq kunda faqat kiritilgan faktlar va «kerakmi» (kutilgan summalar — yopilgach; kassir
           --   Z dagi raqamni yozadi, tizimnikini emas)
           'z', case when d.status = 'open'
                     then app.kassa_z_state(d.id) - 'expCash' - 'nCash' - 'expCard' - 'nCard' - 'diffCash' - 'diffCard' - 'ok'
                     else app.kassa_z_state(d.id) end)
    from public.cash_days d where d.id = p_day_id
$$;
revoke all on function app.kassa_day_json(text) from public, anon, authenticated;

-- ---------- Boshlang'ich qoldiq (CT-02): FAQAT Direktor, kassa ishga tushguncha ----------
--   p: desk, amount (0 mumkin), startDay ('YYYY-MM-DD' — birinchi kassa kuni), note, commission [{title, name}]
create or replace function public.kassa_opening_set(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text; v_amount numeric; v_start date; v_k public.cash_desks%rowtype; v_doc_id text;
  v_comm jsonb; v_note text;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: boshlang''ich qoldiqni faqat Direktor kiritadi' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_desk := coalesce(nullif(btrim(coalesce(p ->> 'desk', '')), ''), 'main');
  v_amount := app.kassa_amount0(p -> 'amount', 'Boshlang''ich qoldiq');
  if v_amount is null then raise exception 'Boshlang''ich qoldiq kiritilmagan' using errcode = '22023', hint = 'kassa:amount'; end if;
  begin
    if coalesce(p ->> 'startDay', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'x'; end if;
    v_start := (p ->> 'startDay')::date;
  exception when others then raise exception 'Birinchi kassa kuni (sana) noto''g''ri' using errcode = '22023', hint = 'kassa:bad_input'; end;
  if v_start > app.fin_today() + 366 or v_start < app.fin_today() - 366 then
    raise exception 'Birinchi kassa kuni juda uzoq sana' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  v_comm := app.kassa_commission(p -> 'commission');
  v_note := left(btrim(coalesce(p ->> 'note', '')), 500);

  perform app.kassa_lock_desk(v_desk);
  select * into v_k from public.cash_desks k where k.id = v_desk and k.active for update;
  if not found then raise exception 'Kassa topilmadi' using errcode = '22023', hint = 'kassa:bad_desk'; end if;
  if exists (select 1 from public.cash_days d where d.desk = v_desk) then
    raise exception 'Kassa ishga tushgan — boshlang''ich qoldiq endi o''zgarmaydi' using errcode = '42501', hint = 'kassa:started';
  end if;
  if not v_k."isTest" then   -- yopilgan davrga kassa kuni qo'yilmaydi (fin-period.sql); sozlama qatori — davr qulfi bilan navbatga
    perform 1 from public.fin_org o where o.id = 'main' for share;
    perform app.fin_lock_check(v_start, 'Birinchi kassa kuni');
  end if;
  perform app.kassa_flag(true);
  -- Avval kiritilgan dalolatnoma bo'lsa — bekor qilinadi (raqami saqlanadi), yangisi yoziladi.
  if v_k."openingDocId" is not null then
    update public.cash_docs set status = 'void', "voidedBy" = v_uid, "voidedAt" = now(), "voidReason" = 'Boshlang''ich qoldiq qayta kiritildi'
     where id = v_k."openingDocId" and status = 'posted';
  end if;
  if v_amount > 0 then
    select b.o_id into v_doc_id from app.kassa_doc_build(jsonb_build_object(
        'desk', v_desk, 'op', 'nc_opening', 'amount', v_amount, 'clientRef', 'opening_' || replace(gen_random_uuid()::text, '-', ''),
        'partyName', 'Boshlang''ich qoldiq', 'basis', 'Kassani sanash dalolatnomasi (boshlang''ich qoldiq)', 'note', v_note,
        'lines', jsonb_build_array(jsonb_build_object('debit', '5010', 'credit', '0000', 'amount', v_amount, 'articleId', 'OP-23'))),
      'ACT', v_uid, true) b;
    perform app.kassa_act_post(v_doc_id, v_uid, v_start);
  end if;
  update public.cash_desks set "startDay" = v_start, "openingAmount" = v_amount, "openingDocId" = v_doc_id, "openingBy" = v_uid, "openingAt" = now()
   where id = v_desk;
  insert into public.cash_counts (id, desk, day, kind, expected, counted, diff, "diffDocId", commission, note, "byUid")
    values ('cc_' || replace(gen_random_uuid()::text, '-', ''), v_desk, v_start, 'opening', v_amount, v_amount, 0, v_doc_id, v_comm, v_note, v_uid);
  insert into public.cash_day_events (id, desk, day, kind, "byUid", reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_desk, v_start, 'opening', v_uid, v_note, jsonb_build_object('amount', v_amount, 'docId', v_doc_id));
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'desk', (select to_jsonb(k) from public.cash_desks k where k.id = v_desk));
end $$;
revoke all on function public.kassa_opening_set(jsonb) from public, anon;
grant execute on function public.kassa_opening_set(jsonb) to authenticated;

-- ---------- Kunni sanab yopish (CT-03) ----------
--   p: desk, day ('YYYY-MM-DD' — yopilayotgan kun; eski ekrandan boshqa kunni yopib qo'ymaslik uchun), counted, denoms {nominal: soni},
--      pendingCount, pendingSum (qurilma navbatidagi hali o'tkazilmagan yozuvlar), note, commission [{title, name}],
--      z — onlayn kassa Z-hisoboti {no, cash, card} yoki {missing: true, reason} (ixtiyoriy; sinov kassasida e'tiborga olinmaydi)
--   Kassir yopadi; Direktor yoki Moliya menejeri — kassir o'rniga, kamida 2 kishilik komissiya bilan.
create or replace function public.kassa_day_close(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text; v_day date; v_d public.cash_days%rowtype; v_counted numeric; v_pending numeric; v_pcount int;
  v_denoms jsonb; v_comm jsonb; v_note text; v_exp numeric; v_diff numeric; v_doc_id text; v_cnt_id text;
  v_rec numeric; v_pay numeric; v_docs int; v_f1 int; v_l1 int; v_f2 int; v_l2 int; v_rows int; v_sheets int; v_from int;
begin
  if not (app.kassa_operator() or app.is_admin() or app.is_finance_mgr()) then
    raise exception 'Ruxsat yo''q: kunni kassir yopadi' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_desk := coalesce(nullif(btrim(coalesce(p ->> 'desk', '')), ''), 'main');
  begin
    if coalesce(p ->> 'day', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'x'; end if;
    v_day := (p ->> 'day')::date;
  exception when others then raise exception 'Yopilayotgan kun (sana) ko''rsatilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end;
  v_counted := app.kassa_amount0(p -> 'counted', 'Sanalgan summa');
  if v_counted is null then raise exception 'Kassadagi pulni sanab, summasini kiriting' using errcode = '22023', hint = 'kassa:count'; end if;
  v_pending := coalesce(app.kassa_amount0(p -> 'pendingSum', 'Hali o''tkazilmagan yozuvlar'), 0);
  begin v_pcount := coalesce(nullif(p ->> 'pendingCount', '')::int, 0); exception when others then v_pcount := 0; end;
  if v_pcount < 0 or (v_pending > 0 and v_pcount = 0) or (v_pending = 0 and v_pcount > 0) then
    raise exception 'Hali o''tkazilmagan yozuvlar soni va summasi birga ko''rsatiladi' using errcode = '22023', hint = 'kassa:count';
  end if;
  v_denoms := app.kassa_denoms_check(p -> 'denoms', v_counted);
  v_comm := app.kassa_commission(p -> 'commission');
  v_note := left(btrim(coalesce(p ->> 'note', '')), 500);
  if not app.kassa_operator() and jsonb_array_length(v_comm) < 2 then   -- kassir o'rniga yopish: 2 kishilik dalolatnoma
    raise exception 'Kassir o''rniga yopishda kamida 2 kishilik komissiya ko''rsatiladi' using errcode = '22023', hint = 'kassa:commission';
  end if;

  perform app.kassa_lock_desk(v_desk);
  select * into v_d from public.cash_days d where d.desk = v_desk and d.status = 'open' for update;
  if not found then
    select * into v_d from public.cash_days d where d.desk = v_desk and d.day = v_day;
    if found and v_d.counted = v_counted then   -- qayta yuborish (javob yetib kelmagan)
      return jsonb_build_object('ok', true, 'dup', true, 'day', app.kassa_day_json(v_d.id));
    end if;
    raise exception 'Ochiq kassa kuni yo''q' using errcode = 'P0001', hint = 'kassa:no_open_day';
  end if;
  if v_d.day <> v_day then
    raise exception 'Ochiq kun — % (ekrandagi sana eskirgan, sahifani yangilang)', to_char(v_d.day, 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:wrong_day';
  end if;
  if v_d.day > app.fin_today() then
    raise exception 'Server sanasi ochiq kassa kunidan oldin — soatni tekshiring' using errcode = 'P0001', hint = 'kassa:clock';
  end if;

  perform app.kassa_flag(true);
  -- Z-hisobot (F1.26) — sanashdan oldin: noto'g'ri ma'lumot bo'lsa kun yopilmaydi (xato matni bilan qaytadi)
  if jsonb_typeof(p -> 'z') = 'object' and not coalesce((select k."isTest" from public.cash_desks k where k.id = v_desk), false) then
    perform app.kassa_z_put(v_d.id, p -> 'z', v_uid);
  end if;
  select c.o_expected, c.o_diff, c.o_doc_id, c.o_count_id into v_exp, v_diff, v_doc_id, v_cnt_id
    from app.kassa_count_apply(v_desk, v_d.id, v_d.day, 'close', v_counted, v_pending, v_denoms, v_comm, v_note, v_uid, null) c;
  select coalesce(sum(c.amount) filter (where c.status = 'posted' and c.form = 'KO1'), 0),
         coalesce(sum(c.amount) filter (where c.status = 'posted' and c.form = 'KO2'), 0),
         count(*), min(c.no) filter (where c.form = 'KO1'), max(c.no) filter (where c.form = 'KO1'),
         min(c.no) filter (where c.form = 'KO2'), max(c.no) filter (where c.form = 'KO2')
    into v_rec, v_pay, v_docs, v_f1, v_l1, v_f2, v_l2
    from public.cash_docs c where c."dayId" = v_d.id and c.status in ('posted', 'void');
  -- KO-4 varaqlari: varaqdagi qatorlar soni qat'iy; raqamlar yil ichida uzluksiz (qayta ochib yopilsa — o'sha raqamdan).
  begin v_rows := coalesce(nullif((select o.extra ->> 'ko4Rows' from public.fin_org o where o.id = 'main'), '')::int, 30);
  exception when others then v_rows := 30; end;
  v_rows := least(greatest(v_rows, 10), 60);
  v_sheets := greatest(1, ceil(v_docs::numeric / v_rows)::int);
  select coalesce(max(d."sheetTo"), 0) + 1 into v_from from public.cash_days d
   where d.desk = v_desk and d.day < v_d.day and extract(year from d.day) = extract(year from v_d.day);
  update public.cash_days
     set status = 'closed', receipts = v_rec, payouts = v_pay, closing = opening + v_rec - v_pay, counted = v_counted, diff = v_diff,
         "diffDocId" = v_doc_id, denoms = v_denoms, "pendingCount" = v_pcount, "pendingSum" = v_pending, "docCount" = v_docs,
         "firstKo1" = v_f1, "lastKo1" = v_l1, "firstKo2" = v_f2, "lastKo2" = v_l2, "sheetFrom" = v_from, "sheetTo" = v_from + v_sheets - 1, "sheetRows" = v_rows,
         hash = app.kassa_day_hash(v_d.id), "closedBy" = v_uid, "closedAt" = now(), "closeNote" = v_note, commission = v_comm
   where id = v_d.id;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_d.id, v_desk, v_d.day, 'close', v_uid, v_note,
            jsonb_build_object('expected', v_exp, 'counted', v_counted, 'pendingSum', v_pending, 'diff', v_diff, 'diffDocId', v_doc_id, 'countId', v_cnt_id));
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', false, 'day', app.kassa_day_json(v_d.id), 'expected', v_exp, 'diff', v_diff,
                            'diffDoc', case when v_doc_id is not null then app.kassa_doc_json(v_doc_id) end);
end $$;
revoke all on function public.kassa_day_close(jsonb) from public, anon;
grant execute on function public.kassa_day_close(jsonb) to authenticated;

-- ---------- Smena topshirish-qabul (FD-16): kun ochiq qoladi, kassir almashadi ----------
--   p: desk, counted, denoms, pendingCount, pendingSum, toUid (qabul qiluvchi kassir), note, commission
create or replace function public.kassa_handover(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text; v_d public.cash_days%rowtype; v_counted numeric; v_pending numeric; v_denoms jsonb;
  v_to text; v_exp numeric; v_diff numeric; v_doc_id text; v_cnt_id text; v_note text;
begin
  if not (app.kassa_operator() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: smenani kassir topshiradi' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_desk := coalesce(nullif(btrim(coalesce(p ->> 'desk', '')), ''), 'main');
  v_counted := app.kassa_amount0(p -> 'counted', 'Sanalgan summa');
  if v_counted is null then raise exception 'Kassadagi pulni sanab, summasini kiriting' using errcode = '22023', hint = 'kassa:count'; end if;
  v_pending := coalesce(app.kassa_amount0(p -> 'pendingSum', 'Hali o''tkazilmagan yozuvlar'), 0);
  v_denoms := app.kassa_denoms_check(p -> 'denoms', v_counted);
  v_note := left(btrim(coalesce(p ->> 'note', '')), 500);
  v_to := nullif(btrim(coalesce(p ->> 'toUid', '')), '');
  if v_to is null or v_to = v_uid or not exists (
       select 1 from public.users u where u.id = v_to and coalesce(nullif(u.status, ''), 'active') = 'active'
          and (u.role in ('kassir', 'treasurer')
               or (jsonb_typeof(u."extraRoles") = 'array' and u."extraRoles" ? 'kassir' and u.role not in ('director', 'parent', 'student')))) then
    raise exception 'Qabul qiluvchi kassir tanlanmagan yoki kassir emas' using errcode = '22023', hint = 'kassa:handover_to';
  end if;
  perform app.kassa_lock_desk(v_desk);
  select * into v_d from public.cash_days d where d.desk = v_desk and d.status = 'open' for update;
  if not found then raise exception 'Ochiq kassa kuni yo''q' using errcode = 'P0001', hint = 'kassa:no_open_day'; end if;
  perform app.kassa_flag(true);
  select c.o_expected, c.o_diff, c.o_doc_id, c.o_count_id into v_exp, v_diff, v_doc_id, v_cnt_id
    from app.kassa_count_apply(v_desk, v_d.id, v_d.day, 'handover', v_counted, v_pending, v_denoms, app.kassa_commission(p -> 'commission'), v_note, v_uid, v_to) c;
  update public.cash_days set "cashierUid" = v_to where id = v_d.id;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_d.id, v_desk, v_d.day, 'handover', v_uid, v_note,
            jsonb_build_object('toUid', v_to, 'expected', v_exp, 'counted', v_counted, 'pendingSum', v_pending, 'diff', v_diff, 'diffDocId', v_doc_id, 'countId', v_cnt_id));
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'day', app.kassa_day_json(v_d.id), 'expected', v_exp, 'diff', v_diff,
                            'diffDoc', case when v_doc_id is not null then app.kassa_doc_json(v_doc_id) end);
end $$;
revoke all on function public.kassa_handover(jsonb) from public, anon;
grant execute on function public.kassa_handover(jsonb) to authenticated;

-- ---------- Kunni tekshirish (CT-05): 2-ro'yxat yoki Direktor; tekshiruvchi ≠ yopuvchi, ≠ shu kun hujjat o'tkazganlar ----------
create or replace function public.kassa_day_verify(p_desk text, p_day date, p_papers boolean, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_d public.cash_days%rowtype;
  v_prev date; v_gaps jsonb; v_rec numeric; v_pay numeric; v_z jsonb;
begin
  if not (app.fin_list2() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: kassa kunini Moliya menejeri / buxgalter yoki Direktor tekshiradi' using errcode = '42501';
  end if;
  if p_day is null then raise exception 'Kun ko''rsatilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  perform app.kassa_lock_desk(v_desk);
  select * into v_d from public.cash_days d where d.desk = v_desk and d.day = p_day for update;
  if not found then raise exception 'Kassa kuni topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if v_d.status = 'verified' then
    if v_d."verifiedBy" = v_uid then return jsonb_build_object('ok', true, 'dup', true, 'day', app.kassa_day_json(v_d.id)); end if;
    raise exception 'Bu kun allaqachon tekshirilgan' using errcode = 'P0001', hint = 'kassa:verified';
  end if;
  if v_d.status <> 'closed' then
    raise exception 'Kun hali yopilmagan — avval kassir sanab yopadi' using errcode = 'P0001', hint = 'kassa:not_closed';
  end if;
  select min(d.day) into v_prev from public.cash_days d where d.desk = v_desk and d.day < p_day and d.status <> 'verified';
  if v_prev is not null then
    raise exception 'Avval % kunini tekshiring (kunlar tartib bilan tekshiriladi)', to_char(v_prev, 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:verify_order';
  end if;
  if v_d."closedBy" = v_uid
     or exists (select 1 from public.cash_docs c where c."dayId" = v_d.id and c."postedBy" = v_uid) then
    raise exception 'Kunni yopgan yoki shu kuni hujjat o''tkazgan xodim o''zi tekshira olmaydi' using errcode = '42501', hint = 'kassa:self_verify';
  end if;
  if not coalesce(p_papers, false) then
    raise exception 'Qog''oz hujjatlar va ilovalar olinganini tasdiqlang' using errcode = '22023', hint = 'kassa:papers';
  end if;
  -- Onlayn kassa Z-hisoboti (F1.26): kiritilmagan, «yo'q» deb belgilangan yoki tizim bilan mos emas — tekshiruvchi sababini yozadi
  v_z := app.kassa_z_state(v_d.id);
  if coalesce((v_z ->> 'applies')::boolean, false) and not coalesce((v_z ->> 'ok')::boolean, true)
     and length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception 'Onlayn kassa Z-hisoboti %: izohda sababini yozing (kamida 5 belgi)',
      case when not coalesce((v_z ->> 'recorded')::boolean, false) then 'kiritilmagan'
           when coalesce((v_z ->> 'missing')::boolean, false) then 'yo''q deb belgilangan'
           else 'tizimdagi summalar bilan mos emas' end
      using errcode = '22023', hint = 'kassa:z_note';
  end if;
  v_gaps := app.kassa_gap_check(v_desk, extract(year from p_day)::int);
  if jsonb_array_length(v_gaps) > 0 then
    raise exception 'Hujjat raqamlarida nomuvofiqlik bor — tekshirish to''xtatildi: %', v_gaps::text using errcode = 'P0001', hint = 'kassa:gaps';
  end if;
  select coalesce(sum(c.amount) filter (where c.form = 'KO1'), 0), coalesce(sum(c.amount) filter (where c.form = 'KO2'), 0)
    into v_rec, v_pay from public.cash_docs c where c."dayId" = v_d.id and c.status = 'posted';
  if v_rec <> v_d.receipts or v_pay <> v_d.payouts or app.kassa_day_hash(v_d.id) is distinct from v_d.hash then
    raise exception 'Yopilgan kun ma''lumoti o''zgargan (jamlar yoki iz mos kelmadi) — Direktorga xabar bering' using errcode = 'P0001', hint = 'kassa:hash';
  end if;
  perform app.kassa_flag(true);
  update public.cash_days set status = 'verified', "verifiedBy" = v_uid, "verifiedAt" = now(), "verifyNote" = left(btrim(coalesce(p_note, '')), 500)
   where id = v_d.id;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", reason)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_d.id, v_desk, v_d.day, 'verify', v_uid, left(btrim(coalesce(p_note, '')), 500));
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', false, 'day', app.kassa_day_json(v_d.id));
end $$;
revoke all on function public.kassa_day_verify(text, date, boolean, text) from public, anon;
grant execute on function public.kassa_day_verify(text, date, boolean, text) to authenticated;

-- ---------- Onlayn kassa Z-hisobotini kiritish / tuzatish (F1.26) ----------
--   Kunni yopishda kiritilmagan bo'lsa (kassir yo'q edi, hisobot keyin topildi) yoki xato yozilgan bo'lsa — kun tekshirilguncha.
--   p: desk, day ('YYYY-MM-DD'), z: {no, cash, card[, note]} | {missing: true, reason}. Tarix saqlanadi (oxirgi yozuv amalda).
create or replace function public.kassa_day_z(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_desk text; v_day date; v_d public.cash_days%rowtype; v_new boolean;
begin
  if not (app.kassa_operator() or app.is_admin() or app.is_finance_mgr()) then
    raise exception 'Ruxsat yo''q: Z-hisobotni kassir (kassir o''rniga — Direktor yoki Moliya menejeri) kiritadi' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_desk := coalesce(nullif(btrim(coalesce(p ->> 'desk', '')), ''), 'main');
  begin
    if coalesce(p ->> 'day', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'x'; end if;
    v_day := (p ->> 'day')::date;
  exception when others then raise exception 'Kun (sana) ko''rsatilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end;
  perform app.kassa_lock_desk(v_desk);
  select * into v_d from public.cash_days d where d.desk = v_desk and d.day = v_day for update;
  if not found then raise exception 'Kassa kuni topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if v_d.status = 'verified' then
    raise exception 'Tekshirilgan kunning Z-hisoboti o''zgarmaydi' using errcode = 'P0001', hint = 'kassa:verified';
  end if;
  perform app.kassa_flag(true);
  v_new := app.kassa_z_put(v_d.id, p -> 'z', v_uid);
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', not v_new, 'day', app.kassa_day_json(v_d.id));
end $$;
revoke all on function public.kassa_day_z(jsonb) from public, anon;
grant execute on function public.kassa_day_z(jsonb) to authenticated;

-- ---------- Qayta ochish (CT-06): FAQAT Direktor, sabab bilan, faqat oxirgi yopilgan (tekshirilmagan) kun ----------
--   Sanash farqi hujjati bekor qilinadi (raqami saqlanadi) — kun qayta sanab yopiladi; KO-4 varaqlari o'sha raqamlardan qayta beriladi.
create or replace function public.kassa_day_reopen(p_desk text, p_day date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_d public.cash_days%rowtype;
  v_reason text := left(btrim(coalesce(p_reason, '')), 500);
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: kassa kunini faqat Direktor qayta ochadi' using errcode = '42501'; end if;
  if length(v_reason) < 5 then raise exception 'Qayta ochish sababini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  if p_day is null then raise exception 'Kun ko''rsatilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  perform app.kassa_lock_desk(v_desk);
  select * into v_d from public.cash_days d where d.desk = v_desk and d.day = p_day for update;
  if not found then raise exception 'Kassa kuni topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if v_d.status = 'open' then return jsonb_build_object('ok', true, 'dup', true, 'day', app.kassa_day_json(v_d.id)); end if;
  if v_d.status = 'verified' then
    raise exception 'Tekshirilgan kun qayta ochilmaydi (tuzatish — buxgalter storno hujjati bilan)' using errcode = '42501', hint = 'kassa:verified';
  end if;
  if exists (select 1 from public.cash_days d where d.desk = v_desk and d.day > p_day) then
    raise exception 'Faqat oxirgi kassa kuni qayta ochiladi (keyingi kunda hujjat bor)' using errcode = 'P0001', hint = 'kassa:reopen_last';
  end if;
  -- Yopilgan davrdagi kun qayta ochilmaydi (qayta yopilishida farq hujjati o'zgarishi mumkin) — avval Direktor davrni qayta ochadi.
  --   (fin_org qatori FOR SHARE: bir vaqtda davr yopilayotgan bo'lsa — u tugaguncha kutib, yangi qulf bilan tekshiradi)
  if not exists (select 1 from public.cash_desks k where k.id = v_desk and k."isTest") then
    perform 1 from public.fin_org o where o.id = 'main' for share;
    perform app.fin_lock_check(p_day, 'Kassa kuni');
  end if;
  perform app.kassa_flag(true);
  update public.cash_days
     set status = 'open', receipts = null, payouts = null, closing = null, counted = null, diff = null, "diffDocId" = null, denoms = null,
         "pendingCount" = 0, "pendingSum" = 0, "docCount" = null, "firstKo1" = null, "lastKo1" = null, "firstKo2" = null, "lastKo2" = null,
         "sheetFrom" = null, "sheetTo" = null, "sheetRows" = null, hash = null, "closedBy" = null, "closedAt" = null, "closeNote" = null, commission = null,
         "reopenCount" = "reopenCount" + 1, "reopenedBy" = v_uid, "reopenedAt" = now(), "reopenReason" = v_reason
   where id = v_d.id;
  if v_d."diffDocId" is not null then
    -- Kamomad bo'yicha qaror qabul qilingan bo'lsa — qaror dalolatnomasi ham bekor bo'ladi (kun qayta sanaladi, qaror yangidan).
    update public.cash_docs set status = 'void', "voidedBy" = v_uid, "voidedAt" = now(), "voidReason" = 'Kun qayta ochildi: ' || v_reason
     where id = (select c."decisionDocId" from public.cash_docs c where c.id = v_d."diffDocId") and status = 'posted';
    update public.cash_docs set status = 'void', "voidedBy" = v_uid, "voidedAt" = now(), "voidReason" = 'Kun qayta ochildi: ' || v_reason
     where id = v_d."diffDocId" and status = 'posted';
  end if;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_d.id, v_desk, v_d.day, 'reopen', v_uid, v_reason,
            jsonb_build_object('closing', v_d.closing, 'counted', v_d.counted, 'diff', v_d.diff, 'diffDocId', v_d."diffDocId", 'hash', v_d.hash,
                               'closedBy', v_d."closedBy", 'closedAt', v_d."closedAt", 'sheetFrom', v_d."sheetFrom", 'sheetTo', v_d."sheetTo"));
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', false, 'day', app.kassa_day_json(v_d.id));
end $$;
revoke all on function public.kassa_day_reopen(text, date, text) from public, anon;
grant execute on function public.kassa_day_reopen(text, date, text) to authenticated;

-- ---------- Kamomad bo'yicha Direktor qarori (PR-60): xodim zimmasiga (Dt 4730) yoki hisobdan chiqarish (Dt 9430), Kt 5910 ----------
create or replace function public.kassa_shortage_decide(p_doc_id text, p_decision text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text; v_doc public.cash_docs%rowtype; v_act text; v_cashier text; v_ref text; v_name text;
  v_note text := left(btrim(coalesce(p_note, '')), 500); v_party jsonb;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: kamomad bo''yicha qarorni faqat Direktor qabul qiladi' using errcode = '42501'; end if;
  if coalesce(p_decision, '') not in ('employee', 'writeoff') then
    raise exception 'Qaror noto''g''ri (xodim zimmasiga / hisobdan chiqarish)' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  if length(v_note) < 5 then raise exception 'Qaror asosini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  select c.desk into v_desk from public.cash_docs c where c.id = p_doc_id;
  if v_desk is null then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  perform app.kassa_lock_desk(v_desk);
  select * into v_doc from public.cash_docs c where c.id = p_doc_id for update;
  if v_doc.op <> 'out_shortage' or v_doc.status <> 'posted' then
    raise exception 'Bu hujjat — amaldagi kamomad hujjati emas' using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  if v_doc.decision is not null then
    if v_doc.decision = p_decision then return app.kassa_doc_json(p_doc_id) || jsonb_build_object('ok', true, 'dup', true); end if;
    raise exception 'Bu kamomad bo''yicha qaror allaqachon qabul qilingan' using errcode = 'P0001', hint = 'kassa:decided';
  end if;
  -- Xodim zimmasiga: shu kun kassiri (xodim kartasiga bog'langan bo'lsa — o'sha, aks holda ismi bilan «boshqa»).
  v_cashier := v_doc."sourceSnapshot" ->> 'cashierUid';
  if p_decision = 'employee' then
    select case when coalesce(u."staffRefId", '') <> '' then (case when u."staffRefType" = 'teacher' then 'teachers' else 'staff' end) || ':' || u."staffRefId" end,
           coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), u.id)
      into v_ref, v_name from public.users u where u.id = v_cashier;
    if v_ref is not null and (
         (split_part(v_ref, ':', 1) = 'teachers' and exists (select 1 from public.teachers t where t.id = split_part(v_ref, ':', 2)))
      or (split_part(v_ref, ':', 1) = 'staff' and exists (select 1 from public.staff s where s.id = split_part(v_ref, ':', 2)))) then
      v_party := jsonb_build_object('partyType', 'employee', 'partyId', v_ref);
    else
      v_party := jsonb_build_object('partyType', 'other', 'partyName', coalesce(v_name, 'Kassir'));
    end if;
  else
    v_party := jsonb_build_object('partyType', 'other', 'partyName', 'Kassa kamomadi (hisobdan chiqarildi)');
  end if;
  perform app.kassa_flag(true);
  select b.o_id into v_act from app.kassa_doc_build(v_party || jsonb_build_object(
      'desk', v_desk, 'op', 'nc_shortage_dec', 'amount', v_doc.amount, 'clientRef', 'shdec_' || p_doc_id,
      'basis', 'Direktor qarori: KO-2 № ' || v_doc.no || ', ' || to_char(v_doc."businessDay", 'DD.MM.YYYY'), 'note', v_note,
      'sourceTable', 'cash_docs', 'sourceId', p_doc_id,
      'lines', jsonb_build_array(jsonb_build_object('debit', case when p_decision = 'employee' then '4730' else '9430' end, 'credit', '5910',
                                                    'amount', v_doc.amount, 'articleId', case when p_decision = 'employee' then 'OP-22' else 'EX-45' end))),
    'ACT', v_uid, true) b;
  perform app.kassa_act_post(v_act, v_uid, app.fin_today());
  update public.cash_docs set decision = p_decision, "decidedBy" = v_uid, "decidedAt" = now(), "decisionNote" = v_note, "decisionDocId" = v_act
   where id = p_doc_id;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_doc."dayId", v_desk, v_doc."businessDay", 'decision', v_uid, v_note,
            jsonb_build_object('docId', p_doc_id, 'decision', p_decision, 'actId', v_act, 'amount', v_doc.amount));
  perform app.kassa_flag(false);
  return app.kassa_doc_json(p_doc_id) || jsonb_build_object('ok', true, 'dup', false, 'act', app.kassa_doc_json(v_act));
end $$;
revoke all on function public.kassa_shortage_decide(text, text, text) from public, anon;
grant execute on function public.kassa_shortage_decide(text, text, text) to authenticated;

-- ---------- O'qish: «Kassa» kun kartasi ----------
create or replace function public.kassa_state(p_desk text default 'main') returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_today date := app.fin_today();
  v_k public.cash_desks%rowtype; v_o public.fin_org%rowtype; v_open public.cash_days%rowtype; v_last public.cash_days%rowtype;
  v_block text; v_bal numeric; v_l2 boolean := app.fin_list2(); v_dir boolean := app.is_admin(); v_op boolean := app.kassa_operator();
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  select * into v_k from public.cash_desks k where k.id = v_desk;
  if not found then raise exception 'Kassa topilmadi' using errcode = '22023', hint = 'kassa:bad_desk'; end if;
  select * into v_o from public.fin_org o where o.id = 'main';
  select * into v_open from public.cash_days d where d.desk = v_desk and d.status = 'open';
  select * into v_last from public.cash_days d where d.desk = v_desk and d.status <> 'open' order by d.day desc limit 1;
  if v_open.id is not null then
    v_bal := app.kassa_day_balance(v_open.id);
    v_block := case when v_open.day < v_today then 'prev_open' when v_open.day > v_today then 'clock' end;
  else
    v_bal := coalesce(v_last.closing, v_k."openingAmount");
    v_block := case when v_last.id is null and (v_k."startDay" is null or v_k."openingAmount" is null or v_today < v_k."startDay") then 'not_started'
                    when v_last.day = v_today then 'day_closed' when v_last.day > v_today then 'clock' end;
  end if;
  return jsonb_build_object(
    'desk', jsonb_build_object('id', v_k.id, 'name', v_k.name, 'isTest', v_k."isTest", 'active', v_k.active, 'startDay', v_k."startDay",
                               'openingAmount', v_k."openingAmount", 'started', exists (select 1 from public.cash_days d where d.desk = v_desk)),
    'today', v_today, 'now', app.fin_now(),
    'openDay', case when v_open.id is not null then app.kassa_day_json(v_open.id) end,
    'lastDay', case when v_last.id is not null then app.kassa_day_json(v_last.id) end,
    'balance', v_bal,
    'canPost', v_block is null, 'blockReason', v_block,
    'pending', jsonb_build_object(
      'toApprove', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'draft'
                      and ((v_l2 and c."needsList2" and c."approvedBy" is null and c."requestedBy" is distinct from v_uid)
                        or (v_dir and c."needsDirector" and c."dirApprovedBy" is null))),
      'waiting', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'draft'),
      'toPay', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'approved'),
      'toPaySum', (select coalesce(sum(c.amount), 0) from public.cash_docs c where c.desk = v_desk and c.status = 'approved' and c.form = 'KO2'),
      -- CT-26: Direktor tasdiqlagan qaytarish 1 kundan ortiq berilmay turibdi
      'refundsLate', (select count(*) from public.cash_docs c where c.desk = v_desk and c.op = 'out_refund' and c.status = 'approved'
                        and c."dirApprovedAt" < app.fin_now() - interval '1 day')),
    'unverifiedDays', (select count(*) from public.cash_days d where d.desk = v_desk and d.status = 'closed'),
    'undecidedShortages', (select count(*) from public.cash_docs c where c.desk = v_desk and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null),
    'limit', jsonb_build_object('cashLimit', v_o."cashLimit", 'set', v_o."cashLimit" > 0, 'exceeded', v_o."cashLimit" > 0 and coalesce(v_bal, 0) > v_o."cashLimit"),
    't1', v_o.t1, 'l1', v_o.l1, 'kassaGoLive', v_o."kassaGoLive", 'printLang', v_o."printLang", 'lockedThrough', v_o."lockedThrough",
    'counters', (select coalesce(jsonb_object_agg(k.series, k."lastNo"), '{}'::jsonb) from public.doc_counters k
                  where k.desk = v_desk and k.year = extract(year from v_today)::int),
    'me', jsonb_build_object('uid', v_uid, 'operator', v_op, 'list2', v_l2, 'director', v_dir),
    'version', app.kassa_version());   -- modul relizi (fin-version.sql): sahifa o'zi kutgani bilan solishtiradi
end $$;
revoke all on function public.kassa_state(text) from public, anon;
grant execute on function public.kassa_state(text) to authenticated;

-- ---------- Kunlik hisobot (RP-02) bloklari ----------
-- Tomonning asosiy nomi — KALIT bo'yicha (CT-22): o'quvchi, xodim, kontragent ma'lumotnomadan. Topilmasa — NULL.
create or replace function app.kassa_party_label(p_type text, p_id text) returns text
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v text; v_coll text; v_row text;
begin
  if p_id is null or p_type is null then return null; end if;
  if p_type = 'student' then
    select s.name into v from public.students s where s."studentId" = p_id or s.id = p_id order by (s."studentId" = p_id) desc limit 1;
  elsif p_type = 'employee' then
    v_coll := split_part(p_id, ':', 1); v_row := substr(p_id, length(v_coll) + 2);
    if v_coll = 'teachers' then select t.name into v from public.teachers t where t.id = v_row;
    elsif v_coll = 'staff' then select x.name into v from public.staff x where x.id = v_row;
    end if;
  elsif p_type in ('counterparty', 'bank', 'founder') then
    select c.name into v from public.fin_counterparties c where c.id = p_id;
  end if;
  return nullif(btrim(coalesce(v, '')), '');
end $$;
revoke all on function app.kassa_party_label(text, text) from public, anon, authenticated;

-- Kun bo'yicha jamlanmalar (faqat o'tkazilgan hujjatlar, faqat naqd qatorlar):
--   byParty   — «kimdan / kimga qancha»: tomon KALITI bo'yicha (tur + kod); «boshqa» — yozilgan nom bo'yicha; tizim hujjati — alohida;
--   byArticle — statiya va korrespondent hisobvaraq bo'yicha; "transfer" — ichki o'tkazma (bank 5110 / yo'ldagi pul 5710):
--               daromad ham, xarajat ham emas;
--   transfers — bankdan olingan va bankka topshirilgan naqd pul.
create or replace function app.kassa_day_blocks(p_day_id text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select jsonb_build_object(
    'byParty', coalesce((select jsonb_agg(jsonb_build_object('form', x.form, 'partyType', x.ptype, 'partyId', x.pid, 'name', x.name,
                                                             'ops', x.ops, 'count', x.n, 'amount', x.amount)
                                          order by x.form, x.amount desc, x.name, x.pid)
                           from (select c.form, coalesce(c."partyType", case when c."isSystem" then 'system' else 'none' end) as ptype,
                                        c."partyId" as pid,
                                        coalesce(app.kassa_party_label(max(c."partyType"), c."partyId"), max(c."partyName"), '') as name,
                                        to_jsonb(array_agg(distinct c.op order by c.op)) as ops, count(*) as n, sum(c.amount) as amount
                                   from public.cash_docs c
                                  where c."dayId" = p_day_id and c.status = 'posted' and c.form in ('KO1', 'KO2')
                                  group by c.form, 2, c."partyId",
                                           case when c."partyId" is null then lower(regexp_replace(btrim(c."partyName"), '\s+', ' ', 'g')) end) x), '[]'::jsonb),
    'byArticle', coalesce((select jsonb_agg(jsonb_build_object('form', x.form, 'articleId', x."articleId", 'kind', a.kind, 'nameUz', a."nameUz",
                                                               'nameRu', a."nameRu", 'debit', x.debit, 'credit', x.credit, 'amount', x.amount,
                                                               'transfer', x.transfer)
                                            order by x.form, x."articleId", x.debit, x.credit)
                             from (select c.form, l."articleId", l.debit, l.credit, sum(l.amount) as amount,
                                          (case when c.form = 'KO1' then l.credit else l.debit end) in ('5110', '5710') as transfer
                                     from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id
                                    where c."dayId" = p_day_id and c.status = 'posted' and c.form in ('KO1', 'KO2') and l.cash
                                    group by c.form, l."articleId", l.debit, l.credit) x
                             left join public.fin_articles a on a.id = x."articleId"), '[]'::jsonb),
    'transfers', (select jsonb_build_object(
                    'inCount', count(distinct c.id) filter (where c.form = 'KO1'), 'inAmount', coalesce(sum(l.amount) filter (where c.form = 'KO1'), 0),
                    'outCount', count(distinct c.id) filter (where c.form = 'KO2'), 'outAmount', coalesce(sum(l.amount) filter (where c.form = 'KO2'), 0))
                    from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id
                   where c."dayId" = p_day_id and c.status = 'posted' and c.form in ('KO1', 'KO2') and l.cash
                     and (case when c.form = 'KO1' then l.credit else l.debit end) in ('5110', '5710')))
$$;
revoke all on function app.kassa_day_blocks(text) from public, anon, authenticated;

-- ---------- O'qish: kassa kitobi varag'i (KO-4) va kunlik hisobot (RP-02) uchun kun ma'lumoti ----------
--   KO-4 ham, kunlik hisobot ham SHU javobdan tuziladi — jamlari bir xil bo'lishi shundan (F1.15 qabul mezoni: RP-02 = KO-4).
--   channels — shu kunda barcha usullar bo'yicha tushgan o'quv to'lovlari (to'lovlar jadvalidan; MA'LUMOT uchun — naqd bo'lmaganlari
--   kassa kitobiga kirmaydi); pending / limit — hisobot olingan paytdagi holat.
create or replace function public.kassa_day_book(p_desk text, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_id text; v_uids text[]; v_test boolean; v_limit numeric; v_end numeric;
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  select d.id into v_id from public.cash_days d where d.desk = v_desk and d.day = p_day;
  if v_id is null then return jsonb_build_object('ok', true, 'day', null, 'docs', '[]'::jsonb, 'counts', '[]'::jsonb, 'events', '[]'::jsonb, 'names', '{}'::jsonb); end if;
  select array_agg(distinct x) into v_uids from (
      select unnest(array[c."requestedBy", c."approvedBy", c."dirApprovedBy", c."postedBy", c."voidedBy", c."createdBy", c."decidedBy"]) as x
        from public.cash_docs c where c."dayId" = v_id
      union all
      select unnest(array[d."cashierUid", d."openedBy", d."closedBy", d."verifiedBy", d."reopenedBy"]) from public.cash_days d where d.id = v_id
      union all
      select unnest(array[n."byUid", n."fromUid", n."toUid"]) from public.cash_counts n where n."dayId" = v_id
      union all
      select e."byUid" from public.cash_day_events e where e."dayId" = v_id) q
   where x is not null;
  v_test := coalesce((select k."isTest" from public.cash_desks k where k.id = v_desk), false);
  select o."cashLimit" into v_limit from public.fin_org o where o.id = 'main';
  select case when d.status = 'open' then app.kassa_day_balance(d.id) else d.closing end into v_end from public.cash_days d where d.id = v_id;
  return jsonb_build_object('ok', true,
    'isTest', v_test,
    'names', app.kassa_names(v_uids),
    'day', app.kassa_day_json(v_id),
    'docs', coalesce((select jsonb_agg(app.kassa_doc_json(c.id) order by c."postedAt", c.form, c.no)
                        from public.cash_docs c where c."dayId" = v_id and c.status in ('posted', 'void')), '[]'::jsonb),
    'counts', coalesce((select jsonb_agg(to_jsonb(n) order by n.at) from public.cash_counts n where n."dayId" = v_id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(to_jsonb(e) order by e.at) from public.cash_day_events e where e."dayId" = v_id), '[]'::jsonb))
    || app.kassa_day_blocks(v_id)
    || jsonb_build_object(
    'channels', case when v_test then '[]'::jsonb else
                  coalesce((select jsonb_agg(jsonb_build_object('provider', z.provider, 'count', z.n, 'amount', z.s) order by z.s desc, z.provider)
                              from (select r.provider, count(*) as n, sum(r.amount) as s from app.fin_receipts(p_day, p_day) r group by r.provider) z), '[]'::jsonb) end,
    'pending', (select jsonb_build_object(
                  'waiting', count(*) filter (where c.status = 'draft'), 'waitingSum', coalesce(sum(c.amount) filter (where c.status = 'draft'), 0),
                  'toPay', count(*) filter (where c.status = 'approved'), 'toPaySum', coalesce(sum(c.amount) filter (where c.status = 'approved'), 0))
                  from public.cash_docs c where c.desk = v_desk and c.status in ('draft', 'approved')),
    'limit', jsonb_build_object('cashLimit', coalesce(v_limit, 0), 'set', coalesce(v_limit, 0) > 0,
                                'exceeded', coalesce(v_limit, 0) > 0 and coalesce(v_end, 0) > v_limit));
end $$;
revoke all on function public.kassa_day_book(text, date) from public, anon;
grant execute on function public.kassa_day_book(text, date) to authenticated;

-- ---------- O'qish: KO-3 — kirim va chiqim kassa hujjatlarini ro'yxatga olish jurnali (F1.22, buxgalter ko'rigi M4) ----------
--   Davr (≤ 93 kun: oy yoki chorak) bo'yicha barcha kirim va chiqim orderlari — o'tkazilgan va bekor qilingan (raqami saqlanadi),
--   jamlar (faqat o'tkazilgan), davr boshi va oxiridagi qoldiq va ularning mosligi (boshi + kirim − chiqim = oxiri), har shakl
--   bo'yicha davrdagi birinchi / oxirgi raqam. Chop etish (KO-3) va XLSX — sahifada (fin-print.js: journalHtml, journalSheet).
create or replace function public.kassa_journal(p_desk text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_k public.cash_desks%rowtype;
  v_open numeric; v_close numeric; v_t jsonb;
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'Jurnal davri noto''g''ri (boshi oxiridan keyin bo''lmasin)' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  if p_to - p_from > 92 then
    raise exception 'Jurnal davri 93 kundan oshmasin (oy yoki chorak)' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  select * into v_k from public.cash_desks k where k.id = v_desk;
  if not found then raise exception 'Kassa topilmadi' using errcode = '22023', hint = 'kassa:bad_desk'; end if;
  -- davr boshidagi qoldiq: davrdagi birinchi kassa kunining boshi; kun bo'lmasa — oldingi oxirgi kun oxiri; u ham bo'lmasa —
  --   boshlang'ich qoldiq (birinchi kassa kuni davr oxirigacha bo'lsa). Oxiri — davrdagi (yoki undan oldingi) oxirgi kun oxiri.
  select d.opening into v_open from public.cash_days d where d.desk = v_desk and d.day between p_from and p_to order by d.day limit 1;
  if v_open is null then
    select case when d.status = 'open' then app.kassa_day_balance(d.id) else d.closing end into v_open
      from public.cash_days d where d.desk = v_desk and d.day < p_from order by d.day desc limit 1;
  end if;
  if v_open is null then
    v_open := case when v_k."startDay" is not null and v_k."startDay" <= p_to then coalesce(v_k."openingAmount", 0) else 0 end;
  end if;
  select case when d.status = 'open' then app.kassa_day_balance(d.id) else d.closing end into v_close
    from public.cash_days d where d.desk = v_desk and d.day <= p_to order by d.day desc limit 1;
  v_close := coalesce(v_close, v_open);
  select jsonb_build_object(
           'in', coalesce(sum(c.amount) filter (where c.form = 'KO1' and c.status = 'posted'), 0),
           'nIn', count(*) filter (where c.form = 'KO1' and c.status = 'posted'),
           'out', coalesce(sum(c.amount) filter (where c.form = 'KO2' and c.status = 'posted'), 0),
           'nOut', count(*) filter (where c.form = 'KO2' and c.status = 'posted'),
           'voids', count(*) filter (where c.status = 'void'),
           'firstKo1', min(c.no) filter (where c.form = 'KO1'), 'lastKo1', max(c.no) filter (where c.form = 'KO1'),
           'firstKo2', min(c.no) filter (where c.form = 'KO2'), 'lastKo2', max(c.no) filter (where c.form = 'KO2'))
    into v_t
    from public.cash_docs c
   where c.desk = v_desk and c.form in ('KO1', 'KO2') and c.status in ('posted', 'void') and c."businessDay" between p_from and p_to;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to,
    'desk', jsonb_build_object('id', v_k.id, 'name', v_k.name, 'isTest', v_k."isTest"),
    'opening', v_open, 'closing', v_close, 'totals', v_t,
    'balanced', v_open + (v_t ->> 'in')::numeric - (v_t ->> 'out')::numeric = v_close,
    'docs', coalesce((select jsonb_agg(app.kassa_doc_json(c.id) order by c."businessDay", c."postedAt", c.form, c.no)
                        from public.cash_docs c
                       where c.desk = v_desk and c.form in ('KO1', 'KO2') and c.status in ('posted', 'void')
                         and c."businessDay" between p_from and p_to), '[]'::jsonb));
end $$;
revoke all on function public.kassa_journal(text, date, date) from public, anon;
grant execute on function public.kassa_journal(text, date, date) to authenticated;

-- Shaxs ma'lumotini eksport uchun yashirish (FD-28 / D7): {partyName, partyId, partyKept}.
--   Yuridik shaxs (yetkazib beruvchi, tashkilot, bank) va tizim hujjati nomi qoladi (partyKept); o'quvchi — ID, xodim — tabel
--   kodi, jismoniy shaxs / ta'sischi / «boshqa» turdagi kontragent — kontragent ID, yozilgan «boshqa» tomon — nomsiz.
create or replace function app.kassa_mask_party(p_type text, p_id text, p_name text, p_system boolean) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_kind text; v_coll text; v_row text; v_code text;
begin
  if coalesce(p_system, false) or p_type is null then
    return jsonb_build_object('partyName', p_name, 'partyId', null, 'partyKept', true);
  end if;
  if p_type = 'student' then return jsonb_build_object('partyName', null, 'partyId', p_id, 'partyKept', false); end if;
  if p_type = 'employee' then
    v_coll := split_part(coalesce(p_id, ''), ':', 1); v_row := substr(coalesce(p_id, ''), length(v_coll) + 2);
    if v_coll = 'teachers' then select nullif(t."teacherId", '') into v_code from public.teachers t where t.id = v_row;
    elsif v_coll = 'staff' then select nullif(s."staffId", '') into v_code from public.staff s where s.id = v_row; end if;
    return jsonb_build_object('partyName', null, 'partyId', coalesce(v_code, nullif(v_row, '')), 'partyKept', false);
  end if;
  if p_type in ('counterparty', 'bank', 'founder') then
    select c.kind into v_kind from public.fin_counterparties c where c.id = p_id;
    if v_kind in ('supplier', 'org', 'bank') then return jsonb_build_object('partyName', p_name, 'partyId', p_id, 'partyKept', true); end if;
    return jsonb_build_object('partyName', null, 'partyId', p_id, 'partyKept', false);
  end if;
  return jsonb_build_object('partyName', null, 'partyId', null, 'partyKept', false);   -- 'other': yozilgan ism — eksportga chiqmaydi
end $$;
revoke all on function app.kassa_mask_party(text, text, text, boolean) from public, anon, authenticated;

-- KO-3 Excel eksporti uchun ma'lumot (FD-28): kassirga — yo'q (jurnalni chop etadi); 2-ro'yxatga (Moliya menejeri, buxgalter) —
--   ismsiz (app.kassa_mask_party; hujjat surati va qatorlari chiqmaydi); Direktorga — to'liq. Jismoniy shaxs hujjatida qo'lda
--   kiritilgan matn (asos, bekor qilish sababi) ismsiz nusxaga chiqmaydi — unda ism bo'lishi mumkin (masalan, qaytarish sababi);
--   operatsiya turi, summa, raqam va ID qoladi. Yuridik shaxs va tizim hujjatlarida asos qoladi.
create or replace function public.kassa_journal_export(p_desk text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_j jsonb; v_dir boolean := app.is_admin();
begin
  if not (v_dir or app.fin_list2()) then
    raise exception 'Ruxsat yo''q: Excel eksporti — Moliya menejeri, buxgalter yoki Direktor (kassir jurnalni chop etadi)' using errcode = '42501';
  end if;
  v_j := public.kassa_journal(p_desk, p_from, p_to);
  if v_dir then return v_j || jsonb_build_object('masked', false); end if;
  return v_j || jsonb_build_object('masked', true, 'docs', coalesce((
    select jsonb_agg(jsonb_build_object('id', d ->> 'id', 'form', d ->> 'form', 'no', d -> 'no', 'year', d -> 'year', 'businessDay', d ->> 'businessDay',
                                        'op', d ->> 'op', 'amount', d -> 'amount', 'status', d ->> 'status', 'partyType', d ->> 'partyType',
                                        'basis', case when (m ->> 'partyKept')::boolean then d ->> 'basis' end, 'fiscalNo', d ->> 'fiscalNo',
                                        'voidReason', case when (m ->> 'partyKept')::boolean then d ->> 'voidReason' end, 'isSystem', d -> 'isSystem')
                     || m
                     order by x.ord)
      from jsonb_array_elements(v_j -> 'docs') with ordinality x(d, ord)
      cross join lateral (select app.kassa_mask_party(d ->> 'partyType', d ->> 'partyId', d ->> 'partyName', coalesce((d ->> 'isSystem')::boolean, false)) as m) mm), '[]'::jsonb));
end $$;
revoke all on function public.kassa_journal_export(text, date, date) from public, anon;
grant execute on function public.kassa_journal_export(text, date, date) to authenticated;

-- ---------- O'qish: nazorat ro'yxati (RP-06) ----------
--   Faktlar (baho va matn — mijozda): raqam bo'shliqlari, yopilmagan / tekshirilmagan kunlar, qarorsiz kamomad, sanash farqlari,
--   bekor qilish va qayta ochishlar, tasdiq kutayotgan va berilmagan so'rovlar, eski qaytarishlar, fiskal cheksiz kirimlar, «boshqa»
--   tomonlar, kech (oflayn) yozuvlar, asl nusxani qayta chiqarish, darvozasiz naqd maosh, KO-4 chop etilmagan kunlar, limit,
--   moslik (P1/P4/P5/P8), hisobdorlardagi pul (4230) muddati, rahbar / ta'sischiga berilgan pul (4290 / 4890), onlayn kassa
--   Z-hisoboti (tekshirilmagan kunlarda kiritilmagan / mos emas).
create or replace function public.kassa_checks(p_desk text default 'main') returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_today date := app.fin_today(); v_limit numeric; v_bal numeric;
  v_test boolean; v_m0 date := date_trunc('month', app.fin_today())::date;
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  v_test := coalesce((select k."isTest" from public.cash_desks k where k.id = v_desk), false);
  select o."cashLimit" into v_limit from public.fin_org o where o.id = 'main';
  select coalesce((select app.kassa_day_balance(d.id) from public.cash_days d where d.desk = v_desk and d.status = 'open'),
                  (select d.closing from public.cash_days d where d.desk = v_desk and d.status <> 'open' order by d.day desc limit 1),
                  (select k."openingAmount" from public.cash_desks k where k.id = v_desk), 0) into v_bal;
  return jsonb_build_object('ok', true, 'today', v_today, 'isTest', v_test,
    'gaps', (select coalesce(jsonb_agg(jsonb_build_object('year', y.year, 'problems', y.g)), '[]'::jsonb)
               from (select k.year, app.kassa_gap_check(v_desk, k.year) as g from (select distinct year from public.doc_counters where desk = v_desk) k) y
              where jsonb_array_length(y.g) > 0),
    'staleOpenDay', (select d.day from public.cash_days d where d.desk = v_desk and d.status = 'open' and d.day < v_today),
    'unverifiedDays', coalesce((select jsonb_agg(d.day order by d.day) from public.cash_days d where d.desk = v_desk and d.status = 'closed'), '[]'::jsonb),
    'undecidedShortages', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'no', c.no, 'day', c."businessDay", 'amount', c.amount) order by c."businessDay")
                                      from public.cash_docs c where c.desk = v_desk and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null), '[]'::jsonb),
    'diffs30', coalesce((select jsonb_agg(jsonb_build_object('day', d.day, 'diff', d.diff) order by d.day)
                           from public.cash_days d where d.desk = v_desk and d.diff <> 0 and d.day >= v_today - 30), '[]'::jsonb),
    'voids30', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'void' and c."businessDay" >= v_today - 30),
    'reopens30', (select count(*) from public.cash_day_events e where e.desk = v_desk and e.kind = 'reopen' and e.at >= now() - interval '30 days'),
    'waitingApproval', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'draft'),
    'approvedUnpaid', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'approved'),
    'fiscalExempt30', (select count(*) from public.cash_docs c where c.desk = v_desk and c."fiscalExempt" and c.status = 'posted' and c."businessDay" >= v_today - 30),
    'otherParties30', (select count(*) from public.cash_docs c where c.desk = v_desk and c."partyType" = 'other' and c.status = 'posted' and not c."isSystem" and c."businessDay" >= v_today - 30),
    'late30', (select count(*) from public.cash_docs c where c.desk = v_desk and c.late and c.status = 'posted' and c."businessDay" >= v_today - 30),
    -- yuridik shaxslarga (yetkazib beruvchi / tashkilot) kassadan naqd xarajat (F1.27) — buxgalter ko'rib chiqadi
    'orgCash30', (select jsonb_build_object('count', count(*), 'sum', coalesce(sum(c.amount), 0)) from public.cash_docs c
                   where c.desk = v_desk and c.op = 'out_expense' and c.status = 'posted' and c."partyType" = 'counterparty'
                     and app.kassa_is_org(c."partyId") and c."businessDay" >= v_today - 30),
    'reissues30', (select count(*) from public.cash_prints x where x.desk = v_desk and x.mode = 'reissue' and x.at >= app.fin_now() - interval '30 days'),
    'staleRefunds', (select count(*) from public.cash_docs c where c.desk = v_desk and c.op = 'out_refund' and c.status = 'approved'
                       and c."dirApprovedAt" < app.fin_now() - interval '1 day'),
    'salaryGateOff30', (select count(*) from public.cash_docs c where c.desk = v_desk and c.op = 'out_salary' and c.status = 'posted'
                          and c."sourceSnapshot" ->> 'gateOff' = 'true' and c."businessDay" >= v_today - 30),
    -- yopilgan, lekin kassa kitobi varag'i (KO-4) hali chop etilmagan kunlar (2 nusxa imzolanishi kerak)
    'unprintedBooks30', coalesce((select jsonb_agg(d.day order by d.day) from public.cash_days d
                                   where d.desk = v_desk and d.status <> 'open' and d.day >= v_today - 30
                                     and not exists (select 1 from public.cash_prints x where x."dayId" = d.id and x.kind = 'book' and x.version = d."reopenCount")), '[]'::jsonb),
    -- yopish paytida «hali o'tkazilmagan» (oflayn navbatdagi) yozuv bilan yopilgan kunlar
    'pendingDays30', (select count(*) from public.cash_days d where d.desk = v_desk and d.status <> 'open' and coalesce(d."pendingCount", 0) > 0 and d.day >= v_today - 30),
    -- onlayn kassa Z-hisoboti (F1.26): yopilgan, hali tekshirilmagan kunlarda — kiritilmagan, «yo'q» yoki tizim bilan mos emas
    'zreport', case when v_test then '[]'::jsonb else
                 coalesce((select jsonb_agg(jsonb_build_object('day', x.day, 'recorded', (x.z ->> 'recorded')::boolean, 'missing', (x.z ->> 'missing')::boolean,
                                                               'diffCash', x.z -> 'diffCash', 'diffCard', x.z -> 'diffCard') order by x.day)
                             from (select d.day, app.kassa_z_state(d.id) as z from public.cash_days d where d.desk = v_desk and d.status = 'closed') x
                            where not coalesce((x.z ->> 'ok')::boolean, true)), '[]'::jsonb) end,
    'limit', jsonb_build_object('cashLimit', coalesce(v_limit, 0), 'set', coalesce(v_limit, 0) > 0, 'balance', v_bal,
                                'exceeded', coalesce(v_limit, 0) > 0 and v_bal > v_limit,
                                'days30', case when coalesce(v_limit, 0) > 0 then
                                            (select count(*) from public.cash_days d where d.desk = v_desk and d.status <> 'open' and d.closing > v_limit and d.day >= v_today - 30)
                                          else 0 end),
    -- moslik (kassa-links.sql: app.kassa_reconcile) — faqat asosiy kassa
    'reconcile', case when v_test then jsonb_build_object('live', false, 'total', 0) else app.kassa_reconcile(v_today - 30, v_today) end,
    -- hisobdorlardagi pul (4230): berilgan − naqd qaytarilgan − avans hisobotlari; "since" — hali yopilmagan eng eski berilgan sana (FIFO);
    --   "workDays" — o'shandan beri o'tgan ish kunlari (du–ju); hisobot muddati — 3 ish kuni (§4.9).
    'accountable', coalesce((select jsonb_agg(jsonb_build_object('partyId', o.pid, 'name', coalesce(app.kassa_party_label('employee', o.pid), o.nm, ''),
                                                                 'given', o.given, 'returned', o.ret, 'reported', o.rep, 'balance', o.given - o.ret - o.rep, 'since', o.since,
                                                                 'workDays', (select count(*) from generate_series(o.since + 1, v_today, interval '1 day') g
                                                                               where extract(isodow from g) < 6),
                                                                 'overdue', (select count(*) from generate_series(o.since + 1, v_today, interval '1 day') g
                                                                              where extract(isodow from g) < 6) > 3)
                                              order by o.since, o.pid)
                               from (select g.pid, max(g.nm) as nm, max(g.cum) as given, coalesce(max(r.ret), 0) as ret, coalesce(max(r.rep), 0) as rep,
                                            min(g.d) filter (where g.cum > coalesce(r.ret, 0) + coalesce(r.rep, 0)) as since
                                       from (select c."partyId" as pid, c."partyName" as nm, c."businessDay" as d,
                                                    sum(c.amount) over (partition by c."partyId" order by c."businessDay", c."postedAt", c.id) as cum
                                               from public.cash_docs c where c.desk = v_desk and c.op = 'out_accountable' and c.status = 'posted') g
                                       left join (select c."partyId" as pid, sum(c.amount) filter (where c.op = 'in_acc_return') as ret,
                                                         sum(c.amount) filter (where c.op = 'nc_adv_report') as rep from public.cash_docs c
                                                   where c.desk = v_desk and c.op in ('in_acc_return', 'nc_adv_report') and c.status = 'posted' group by 1) r on r.pid = g.pid
                                      group by g.pid) o
                              where o.given - o.ret - o.rep > 0), '[]'::jsonb),
    -- rahbar / ta'sischiga berilgan pul: buxgalter shu oy ichida tasniflaydi (dividend, ish haqi …) — hech qachon xarajat emas
    'handover', (select jsonb_build_object(
                   'monthCount', count(*) filter (where c."businessDay" >= v_m0), 'monthSum', coalesce(sum(c.amount) filter (where c."businessDay" >= v_m0), 0),
                   'earlierCount', count(*) filter (where c."businessDay" < v_m0), 'earlierSum', coalesce(sum(c.amount) filter (where c."businessDay" < v_m0), 0))
                   from public.cash_docs c where c.desk = v_desk and c.op = 'out_handover' and c.status = 'posted' and c."businessDay" >= v_today - 92));
end $$;
revoke all on function public.kassa_checks(text) from public, anon;
grant execute on function public.kassa_checks(text) to authenticated;

-- ---------- Direktorning kunlik Telegram hisoboti uchun kassa bloki va nazorat qatori (RP-05) ----------
--   director_daily (telegram.sql) shu funksiyani DINAMIK chaqiradi: kassa moduli o'rnatilmagan bo'lsa — blok yo'q.
--   NULL — kassa hali ishlatilmayapti (ishga tushirish sanasi yo'q va birorta kassa kuni ochilmagan).
--   day — shu kunning kassa varag'i (jamlari KO-4 va kunlik hisobot bilan AYNAN bir manbadan); control — nazorat qatori.
create or replace function app.kassa_daily(p_day date) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_day date := coalesce(p_day, app.fin_today()); v_d public.cash_days%rowtype; v_open public.cash_days%rowtype; v_last public.cash_days%rowtype;
  v_o public.fin_org%rowtype; v_k public.cash_desks%rowtype; v_bal numeric; v_j jsonb; v_closed boolean;
begin
  select * into v_k from public.cash_desks k where k.id = 'main';
  select * into v_o from public.fin_org o where o.id = 'main';
  if v_k.id is null or (v_o."kassaGoLive" is null and not exists (select 1 from public.cash_days d where d.desk = 'main')) then return null; end if;
  select * into v_d from public.cash_days d where d.desk = 'main' and d.day = v_day;
  select * into v_open from public.cash_days d where d.desk = 'main' and d.status = 'open';
  select * into v_last from public.cash_days d where d.desk = 'main' and d.status <> 'open' order by d.day desc limit 1;
  v_bal := case when v_open.id is not null then app.kassa_day_balance(v_open.id) else coalesce(v_last.closing, v_k."openingAmount", 0) end;
  if v_d.id is not null then
    v_j := app.kassa_day_json(v_d.id); v_closed := v_d.status <> 'open';
  end if;
  return jsonb_build_object(
    'live', v_o."kassaGoLive" is not null and v_day >= v_o."kassaGoLive",
    'day', case when v_d.id is not null then jsonb_build_object(
             'day', v_d.day, 'status', v_d.status, 'opening', v_d.opening,
             'receipts', case when v_closed then v_d.receipts else (v_j ->> 'receiptsLive')::numeric end,
             'payouts', case when v_closed then v_d.payouts else (v_j ->> 'payoutsLive')::numeric end,
             'closing', case when v_closed then v_d.closing else (v_j ->> 'balance')::numeric end,
             'counted', v_d.counted, 'diff', v_d.diff,
             'n1', (select count(*) from public.cash_docs c where c."dayId" = v_d.id and c.status = 'posted' and c.form = 'KO1'),
             'n2', (select count(*) from public.cash_docs c where c."dayId" = v_d.id and c.status = 'posted' and c.form = 'KO2'),
             'voids', (v_j ->> 'voids')::int,
             'transfers', app.kassa_day_blocks(v_d.id) -> 'transfers') end,
    'balance', v_bal,
    'control', jsonb_build_object(
      'reconcile', (app.kassa_reconcile(v_day - 6, v_day) ->> 'total')::int,
      'openDay', v_open.day,
      'staleOpenDay', case when v_open.id is not null and v_open.day < v_day then v_open.day end,
      'unverifiedDays', (select count(*) from public.cash_days d where d.desk = 'main' and d.status = 'closed'),
      'voids', coalesce((v_j ->> 'voids')::int, 0),
      'diff', coalesce(v_d.diff, 0),
      'undecidedShortages', (select count(*) from public.cash_docs c where c.desk = 'main' and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null),
      'waitingApproval', (select count(*) from public.cash_docs c where c.desk = 'main' and c.status = 'draft'),
      'approvedUnpaid', (select count(*) from public.cash_docs c where c.desk = 'main' and c.status = 'approved'),
      'staleRefunds', (select count(*) from public.cash_docs c where c.desk = 'main' and c.op = 'out_refund' and c.status = 'approved'
                         and c."dirApprovedAt" < app.fin_now() - interval '1 day'),
      'gaps', (select count(*) from (select distinct year from public.doc_counters where desk = 'main') k
                where jsonb_array_length(app.kassa_gap_check('main', k.year)) > 0),
      'fiscalExempt', (select count(*) from public.cash_docs c where c.desk = 'main' and c."fiscalExempt" and c.status = 'posted' and c."businessDay" = v_day),
      'limitExceeded', coalesce(v_o."cashLimit", 0) > 0 and v_bal > v_o."cashLimit",
      -- onlayn kassa Z-hisoboti (F1.26) — shu kun yopilgan bo'lsa
      'z', case when v_closed then (select jsonb_build_object('ok', (z ->> 'ok')::boolean, 'needed', (z ->> 'needed')::boolean,
                                                               'recorded', (z ->> 'recorded')::boolean, 'missing', (z ->> 'missing')::boolean,
                                                               'diffCash', z -> 'diffCash', 'diffCard', z -> 'diffCard')
                                      from app.kassa_z_state(v_d.id) z) end));
end $$;
revoke all on function app.kassa_daily(date) from public, anon, authenticated;

-- ---------- O'qish: shakllar uchun ma'lumotnomalar (bitta chaqiruv) ----------
create or replace function public.kassa_refs() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  return jsonb_build_object(
    'rules', coalesce((select jsonb_agg(to_jsonb(r) order by r."sortOrder") from public.fin_op_rules r where r.active), '[]'::jsonb),
    'articles', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'nameUz', a."nameUz", 'nameRu', a."nameRu", 'accountCode', a."accountCode",
                                                              'cashOutAllowed', a."cashOutAllowed", 'needsNote', a."needsNote") order by a."sortOrder")
                            from public.fin_articles a where a.active), '[]'::jsonb),
    'counterparties', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'name', c.name, 'stir', c.stir) order by c.name)
                                  from public.fin_counterparties c where c.active), '[]'::jsonb),
    'org', (select to_jsonb(o) from public.fin_org o where o.id = 'main'),
    'desks', coalesce((select jsonb_agg(to_jsonb(k) order by k.id) from public.cash_desks k where k.active), '[]'::jsonb),
    'signatories', coalesce((select jsonb_agg(to_jsonb(s) order by s.list, s."fullName") from public.fin_signatories s where s.active), '[]'::jsonb),
    'operators', coalesce((select jsonb_agg(jsonb_build_object('uid', u.id, 'name', coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), u.id)) order by u.name)
                             from public.users u
                            where coalesce(nullif(u.status, ''), 'active') = 'active'
                              and (u.role in ('kassir', 'treasurer')
                                   or (jsonb_typeof(u."extraRoles") = 'array' and u."extraRoles" ? 'kassir' and u.role not in ('director', 'parent', 'student')))), '[]'::jsonb),
    -- imzo huquqi bo'lishi mumkin bo'lgan hisoblar («⚙ Sozlamalar» → «Imzo egalari» da hisobni bog'lash uchun) — faqat Direktorga
    'signers', case when app.is_admin() then
                 coalesce((select jsonb_agg(jsonb_build_object('uid', u.id, 'name', coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), u.id), 'role', u.role) order by u.name)
                             from public.users u
                            where coalesce(nullif(u.status, ''), 'active') = 'active'
                              and (u.role in ('director', 'finance_mgr', 'accountant')
                                   or (jsonb_typeof(u."extraRoles") = 'array' and (u."extraRoles" ? 'finance_mgr' or u."extraRoles" ? 'accountant')
                                       and u.role not in ('parent', 'student')))), '[]'::jsonb)
               else '[]'::jsonb end);
end $$;
revoke all on function public.kassa_refs() from public, anon;
grant execute on function public.kassa_refs() to authenticated;

-- Xodimlar ro'yxati (tomon tanlash uchun): faqat kalit, ism, lavozim — maosh va boshqa ma'lumot yo'q.
create or replace function public.kassa_people() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not (app.kassa_operator() or app.fin_list2() or app.is_admin()) then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x.j order by x.nm)
                     from (select jsonb_build_object('ref', 'teachers:' || t.id, 'name', coalesce(t.name, ''), 'pos', 'O‘qituvchi', 'code', coalesce(t."teacherId", '')) as j, coalesce(t.name, '') as nm
                             from public.teachers t
                           union all
                           select jsonb_build_object('ref', 'staff:' || s.id, 'name', coalesce(s.name, ''), 'pos', coalesce(s.position, ''), 'code', coalesce(s."staffId", '')), coalesce(s.name, '')
                             from public.staff s) x), '[]'::jsonb);
end $$;
revoke all on function public.kassa_people() from public, anon;
grant execute on function public.kassa_people() to authenticated;

-- ---------- O'qish: «Kassa» sahifasi uchun hammasi bir chaqiruvda ----------
--   holat + ochiq kun hujjatlari + so'rovlar (tasdiq kutayotgan / to'lanishi kerak) + oxirgi kunlar + qarorsiz kamomadlar +
--   naqdsiz dalolatnomalar + ismlar.
create or replace function public.kassa_overview(p_desk text default 'main') returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_state jsonb; v_day text; v_uids text[];
begin
  v_state := public.kassa_state(v_desk);   -- ruxsatni shu tekshiradi
  select d.id into v_day from public.cash_days d where d.desk = v_desk and d.status = 'open';
  select array_agg(distinct x) into v_uids from (
      select unnest(array[c."requestedBy", c."approvedBy", c."dirApprovedBy", c."rejectedBy", c."postedBy", c."voidedBy", c."createdBy"]) as x
        from public.cash_docs c where c.desk = v_desk and (c."dayId" = v_day or c.status in ('draft', 'approved'))
      union all
      select unnest(array[c."postedBy", c."voidedBy", c."dirApprovedBy"]) from public.cash_docs c
       where c.desk = v_desk and c.form = 'ACT' and c.no is not null and c."businessDay" >= app.fin_today() - 92
      union all
      select unnest(array[d."cashierUid", d."closedBy", d."verifiedBy", d."reopenedBy"]) from public.cash_days d where d.desk = v_desk and d.day >= app.fin_today() - 62) q
   where x is not null;
  return jsonb_build_object('ok', true, 'state', v_state,
    'docs', coalesce((select jsonb_agg(app.kassa_doc_json(c.id) order by c."postedAt" desc, c.form, c.no desc)
                        from public.cash_docs c where c."dayId" = v_day and c.status in ('posted', 'void')), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(app.kassa_doc_json(c.id) order by c."createdAt")
                            from public.cash_docs c where c.desk = v_desk and c.status in ('draft', 'approved')), '[]'::jsonb),
    'days', coalesce((select jsonb_agg(app.kassa_day_json(d.id) order by d.day desc)
                        from (select x.id, x.day from public.cash_days x where x.desk = v_desk order by x.day desc limit 31) d), '[]'::jsonb),
    'shortages', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'no', c.no, 'day', c."businessDay", 'amount', c.amount,
                                                               'cashierUid', c."sourceSnapshot" ->> 'cashierUid') order by c."businessDay")
                             from public.cash_docs c where c.desk = v_desk and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null), '[]'::jsonb),
    -- naqdsiz dalolatnomalar (boshlang'ich qoldiq, kamomad qarori, o'zaro hisob): kassa kitobiga kirmaydi — oxirgi 92 kun, eng yangisi 30 ta
    'acts', coalesce((select jsonb_agg(app.kassa_doc_json(a.id) order by a."postedAt" desc, a.no desc)
                        from (select c.id, c."postedAt", c.no from public.cash_docs c
                               where c.desk = v_desk and c.form = 'ACT' and c.no is not null and c."businessDay" >= app.fin_today() - 92
                               order by c."postedAt" desc, c.no desc limit 30) a), '[]'::jsonb),
    'names', app.kassa_names(v_uids));
end $$;
revoke all on function public.kassa_overview(text) from public, anon;
grant execute on function public.kassa_overview(text) to authenticated;

-- ---------- O'qish: bitta hujjat (chop etish uchun — ismlar bilan) ----------
create or replace function public.kassa_doc_get(p_id text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_c public.cash_docs%rowtype;
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  select * into v_c from public.cash_docs c where c.id = p_id;
  if not found then raise exception 'Hujjat topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  return jsonb_build_object('ok', true, 'doc', app.kassa_doc_json(v_c.id),
    'isTest', coalesce((select k."isTest" from public.cash_desks k where k.id = v_c.desk), false),
    'names', app.kassa_names(array[v_c."requestedBy", v_c."approvedBy", v_c."dirApprovedBy", v_c."rejectedBy", v_c."postedBy",
                                   v_c."voidedBy", v_c."createdBy", v_c."decidedBy"]));
end $$;
revoke all on function public.kassa_doc_get(text) from public, anon;
grant execute on function public.kassa_doc_get(text) to authenticated;

-- ---------- Chop etishni qayd qilish (FD-07): «НУСХА» belgisi server jurnaliga tayanadi ----------
--   p_kind 'doc' (p_id — hujjat) yoki 'book' (p_id — kassa kuni; faqat yopilgan kun). Birinchi chop etish — 'original';
--   keyingisi — 'copy' («НУСХА» belgisi bilan chiqadi); p_reissue — «avvalgisi qog'ozga chiqmadi»: asl nusxa qayta chiqariladi
--   va nazorat ro'yxatida ko'rinadi. Qayta ochib yopilgan kun varag'i — yangi asl nusxa, eskisi «АЛМАШТИРИЛДИ».
create or replace function public.kassa_print_mark(p_kind text, p_id text, p_reissue boolean default false) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_c public.cash_docs%rowtype; v_d public.cash_days%rowtype; v_prior int := 0; v_old int := 0;
  v_mode text; v_ver int := 0; v_desk text;
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  if p_id is null or p_kind is null or p_kind not in ('doc', 'book') then
    raise exception 'Chop etish turi noto''g''ri' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  perform pg_advisory_xact_lock(hashtext('iqror_print:' || p_id));   -- ikki qurilmadan bir vaqtda ikkita «asl nusxa» chiqmasin
  if p_kind = 'doc' then
    select * into v_c from public.cash_docs c where c.id = p_id;
    if not found or v_c.no is null then
      raise exception 'Faqat o''tkazilgan (raqam olgan) hujjat chop etiladi' using errcode = '22023', hint = 'kassa:print';
    end if;
    v_desk := v_c.desk;
    select count(*) into v_prior from public.cash_prints x where x."docId" = p_id;
  else
    select * into v_d from public.cash_days d where d.id = p_id;
    if not found or v_d.status = 'open' then
      raise exception 'Kassa kitobi varag''i yopilgan kun uchun chop etiladi (ochiq kunda — faqat qoralama)' using errcode = '22023', hint = 'kassa:print';
    end if;
    v_desk := v_d.desk; v_ver := v_d."reopenCount";
    select count(*) filter (where x.version = v_ver), count(*) filter (where x.version < v_ver) into v_prior, v_old
      from public.cash_prints x where x."dayId" = p_id and x.kind = 'book';
  end if;
  v_mode := case when v_prior = 0 then 'original' when coalesce(p_reissue, false) then 'reissue' else 'copy' end;
  perform app.kassa_flag(true);
  insert into public.cash_prints (id, kind, "docId", "dayId", desk, mode, version, "byUid", at)
    values ('cp_' || replace(gen_random_uuid()::text, '-', ''), p_kind, case when p_kind = 'doc' then p_id end,
            case when p_kind = 'doc' then v_c."dayId" else p_id end, v_desk, v_mode, v_ver, v_uid, app.fin_now());
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'mode', v_mode, 'prior', v_prior, 'replaced', p_kind = 'book' and v_old > 0,
                            'at', app.fin_now(), 'by', v_uid, 'byName', app.kassa_names(array[v_uid]) ->> v_uid);
end $$;
revoke all on function public.kassa_print_mark(text, text, boolean) from public, anon;
grant execute on function public.kassa_print_mark(text, text, boolean) to authenticated;

notify pgrst, 'reload schema';
