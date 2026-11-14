\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: kassa-day.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- kassa-day.sql — MOLIYA ISH REJASI, 1a-BOSQICH (F1.9): KASSA KUNI SIKLI VA O'QISH FUNKSIYALARI.
--   kassa_opening_set(p)        — boshlang'ich qoldiq (komissiya sanashi) va birinchi kassa kuni: FAQAT Direktor, kassa ishga tushguncha;
--                                 to'xtatilgan kassada — qayta ishga tushirish qoldig'i va farq dalolatnomasi (ishga-tushirish §9);
--   app.kassa_golive_guard(...) — «ishga tushadigan kun» o'zgarishi (fin_org_set): to'xtatish va qayta ishga tushirish shartlari (ui-5);
--   kassa_day_close(p)          — kunni SANAB yopish: farq (sanalgan − hisobdagi − hali o'tkazilmagan) shu kun sanasi bilan tizim
--                                 hujjatiga aylanadi (kamomad KO-2 Dt 5910, ortiqcha KO-1 Kt 9390), varaqlar va xesh muzlaydi;
--   kassa_handover(p)           — smena topshirish-qabul, IKKI BOSQICHLI (state-6): topshiruvchi sanab KUTILAYOTGAN topshirish yozadi
--                                 (kassa egasi bo'lmasa — kassir o'rniga, komissiya bilan; sec-2), kassada hujjat to'xtaydi;
--   kassa_handover_accept(id)   — qabul qiluvchi o'z hisobidan qabul qiladi: sanash dalolatnomasi, farq hujjati (kassa egasi —
--                                 topshiruvchi), kassa egasi — qabul qiluvchi; kassa_handover_cancel(id, sabab) — bekor / rad etish;
--   kassa_day_verify(...)       — 2-ro'yxat / Direktor tekshiradi: tekshiruvchi ≠ yopuvchi, ≠ shu kun hujjat o'tkazgan, bekor qilgan,
--                                 Z-hisobotni kiritgan / tuzatgan va kunni qayta ochganlar (crit-4); raqamlarda bo'shliq, xesh yoki
--                                 jamlar mos kelmasa — rad;
--   kassa_day_z(p)              — onlayn kassa (NKM) Z-hisobotini kiritish / tuzatish (kun tekshirilguncha; yopishda ham beriladi);
--                                 tizim Z ni fiskal chekli KO-1 va terminal to'lovlari bilan solishtiradi (F1.26); yopilgandan keyingi
--                                 o'zgarish belgilanadi va nazorat ro'yxatida ko'rinadi;
--   kassa_day_reopen(...)       — FAQAT Direktor, sabab bilan, faqat oxirgi yopilgan (tekshirilmagan) kun;
--   kassa_shortage_decide(...)  — kamomad bo'yicha Direktor qarori (xodim zimmasiga 4730 — faqat xodim kartasiga; hisobdan chiqarish 9430);
--   kassa_state(desk)           — «Kassa» kun kartasi uchun holat; kassa_day_book(desk, day) — KO-4 / kunlik hisobot (RP-02) ma'lumoti;
--   kassa_journal(desk, from, to) — KO-3: kirim va chiqim orderlari jurnali (davr ≤ 93 kun; chop etish va XLSX — sahifada);
--   kassa_journal_export(...)   — KO-3 Excel uchun ma'lumot (FD-28): kassirga yo'q, 2-ro'yxatga ismsiz, Direktorga to'liq;
--   kassa_matrix(desk, month)   — RP-08: oylik statiya matritsasi (statiya × kun; kunlik jamlar va qoldiq; chop etish va XLSX — sahifada);
--   kassa_month_pack(desk, month) — buxgalter uchun oylik kassa to'plami (E1–E4: KO-3, matritsa, kassa kunlari, hisobdorlar; FD-28);
--   kassa_kpi(desk, weeks)      — RP-22 haftalik ko'rsatkichlar (o'z vaqtida yopilgan kunlar, tekshirilmagan, farqlar, EX-49 ulushi,
--                                 muddati o'tgan avanslar) — Direktor va 2-ro'yxat; dushanba kungi Telegram hisobotida o'tgan hafta;
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
                 (select count(*) from public.cash_docs c where c.desk = p_desk and c.series = s.series and c.year = p_year and c.no is not null) as cnt,
                 coalesce((select max(c.no) from public.cash_docs c where c.desk = p_desk and c.series = s.series and c.year = p_year), 0) as mx
            from (values ('KO1'), ('KO2'), ('ACT'), ('OFS'), ('ADV')) s(series)) x
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
--   sec-2: kassa egasi (p_holder — kun kassiri; smenada — topshiruvchi) va sanagan xodim (p_by) ALOHIDA yoziladi — hujjat suratida
--   ("cashierUid", "countedBy"; smenada — "toUid", "handoverId") va sanash dalolatnomasida; ismlar shu paytdagi holatda (sec-4).
--   Kamomad bo'yicha «xodim zimmasiga» qarorida standart javobgar — faqat kassa egasi o'zi sanagan va boshqa hech kim kassa orderini
--   o'tkazmagan / bekor qilmagan bo'lsa (app.kassa_shortage_default). g6v-1: kunning «boshqalar» ro'yxati (cash_days."othersUids"; kassa
--   egasisiz) hujjat suratiga ko'chadi ("others", ismlari — names da); smenada bu — topshiruvchining davri.
--   p_uid — amalni bajarayotgan seans (hujjatni yaratgan): kunni yopgan yoki smenani qabul qilgan xodim.
drop function if exists app.kassa_count_apply(text, text, date, text, numeric, numeric, jsonb, jsonb, text, text, text);   -- avvalgi ta'rif (kassa egasisiz)
create or replace function app.kassa_count_apply(p_desk text, p_day_id text, p_day date, p_kind text, p_counted numeric, p_pending numeric,
                                                 p_denoms jsonb, p_commission jsonb, p_note text, p_uid text,
                                                 p_holder text, p_by text, p_to_uid text, p_handover text,
                                                 out o_expected numeric, out o_diff numeric, out o_doc_id text, out o_count_id text)
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_names jsonb := app.kassa_names(array[p_holder, p_by, p_to_uid]); v_others text[];
begin
  o_expected := app.kassa_day_balance(p_day_id);
  if p_counted < p_pending then
    raise exception 'Sanalgan summa hali o''tkazilmagan yozuvlar summasidan kam bo''lmaydi' using errcode = '22023', hint = 'kassa:count';
  end if;
  o_diff := p_counted - o_expected - p_pending;
  if o_diff <> 0 then
    select coalesce(array_agg(u.x order by u.n), '{}'::text[]) into v_others
      from public.cash_days d cross join lateral unnest(d."othersUids") with ordinality u(x, n)
     where d.id = p_day_id and u.x is distinct from p_holder;
    select b.o_id into o_doc_id from app.kassa_doc_build(jsonb_build_object(
        'desk', p_desk, 'op', case when o_diff > 0 then 'in_surplus' else 'out_shortage' end, 'amount', abs(o_diff),
        'clientRef', 'sysdiff_' || replace(gen_random_uuid()::text, '-', ''), 'isSystem', true,
        'partyName', case when o_diff > 0 then 'Kassa ortiqchasi' else 'Kassa kamomadi' end,
        'basis', 'Kassani sanash dalolatnomasi, ' || to_char(p_day, 'DD.MM.YYYY'),
        'note', case p_kind when 'handover' then 'Smena topshirish-qabul sanashi' else 'Kun yopish sanashi' end,
        'sourceSnapshot', jsonb_strip_nulls(jsonb_build_object('cashierUid', p_holder, 'countedBy', p_by, 'toUid', p_to_uid, 'handoverId', p_handover,
                                                               'expected', o_expected, 'counted', p_counted, 'pending', p_pending, 'kind', p_kind,
                                                               'others', case when cardinality(v_others) > 0 then to_jsonb(v_others) end,
                                                               'names', v_names || app.kassa_names(v_others)))),
      case when o_diff > 0 then 'KO1' else 'KO2' end, p_uid, true) b;
    perform app.kassa_doc_post(o_doc_id, p_uid, true, null, false, p_day_id);
  end if;
  o_count_id := 'cc_' || replace(gen_random_uuid()::text, '-', '');
  insert into public.cash_counts (id, desk, day, "dayId", kind, expected, counted, "pendingSum", diff, "diffDocId", denoms, commission, "fromUid", "toUid", note, "byUid",
                                  "cashierUid", "handoverId", names, at)
    values (o_count_id, p_desk, p_day, p_day_id, p_kind, o_expected, p_counted, p_pending, o_diff, o_doc_id, p_denoms, p_commission,
            case when p_kind = 'handover' then p_holder end, p_to_uid, left(btrim(coalesce(p_note, '')), 500), p_by,
            p_holder, p_handover, v_names, clock_timestamp());
end $$;
revoke all on function app.kassa_count_apply(text, text, date, text, numeric, numeric, jsonb, jsonb, text, text, text, text, text, text) from public, anon, authenticated;

-- Kamomad «xodim zimmasiga» bo'lsa — standart javobgar (sec-2, sec-4): FAQAT kassa egasi pulni o'zi sanagan (hujjat suratida
--   "cashierUid" = "countedBy") va shu davrda kassaga boshqa hech kim tegmagan bo'lsa (g6v-1: "others" — kassa egasidan boshqa kassa orderi
--   o'tkazgan / bekor qilganlar — bo'sh) — uning xodim kartasi (asosiy havola; bo'lmasa — yagona bog'langan karta). Boshqa holatda (kassir
--   o'rniga sanalgan, kassa egasi aniqlanmagan, boshqa xodim ham kassa orderi bilan ishlagan, hisob kartaga bog'lanmagan yoki kartalar bir
--   nechta; eski hujjat — sanagan xodim yozilmagan) — NULL: Direktor javobgar xodim kartasini o'zi tanlaydi (sababi — app.kassa_shortage_why).
create or replace function app.kassa_shortage_default(p_snap jsonb) returns text
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when coalesce(p_snap ->> 'cashierUid', '') <> '' and p_snap ->> 'cashierUid' = p_snap ->> 'countedBy'
                   and coalesce(jsonb_array_length(case when jsonb_typeof(p_snap -> 'others') = 'array' then p_snap -> 'others' end), 0) = 0 then
           coalesce((select case when u."staffRefType" = 'teacher' then 'teachers:' else 'staff:' end || u."staffRefId"
                       from public.users u
                      where u.id = p_snap ->> 'cashierUid' and coalesce(u."staffRefId", '') <> ''
                        and case when u."staffRefType" = 'teacher' then exists (select 1 from public.teachers t where t.id = u."staffRefId")
                                 else exists (select 1 from public.staff s where s.id = u."staffRefId") end),
                    (select c[1] from (select app.kassa_user_cards(p_snap ->> 'cashierUid') as c) x where cardinality(x.c) = 1)) end
$$;
revoke all on function app.kassa_shortage_default(jsonb) from public, anon, authenticated;

-- Nega standart javobgar yo'q (g6v-3) — BITTA manba: kamomad qarori xatosi (kassa_shortage_decide, kassa:shortage_party) ham, qaror oynasi
--   ham (kassa_overview → shortages: defaultWhy) shu matnni ko'rsatadi. Tartib: kassa egasi aniqlanmagan → eski hujjat (sanagan xodim
--   yozilmagan) → kassir o'rniga sanalgan → boshqa xodim ham kassa orderi o'tkazgan / bekor qilgan (ismlari — hujjat suratidagi ismlardan,
--   sanash paytidagi holatda) → hisob kartaga bog'lanmagan yoki kartalar bir nechta. Standart javobgar bor bo'lsa — NULL.
create or replace function app.kassa_shortage_why(p_snap jsonb) returns text
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when coalesce(p_snap ->> 'cashierUid', '') = '' then 'Kassa egasi (kun kassiri) aniqlanmagan'
              when coalesce(p_snap ->> 'countedBy', '') = '' then 'Eski hujjat: pulni kim sanagani yozilmagan'
              when p_snap ->> 'countedBy' <> p_snap ->> 'cashierUid' then 'Pulni kassa egasining o''zi sanamagan (kassir o''rniga sanalgan)'
              when o.names is not null then 'Shu kuni kassa egasidan boshqa xodim ham kassa orderini o''tkazgan yoki bekor qilgan: ' || o.names
              when app.kassa_shortage_default(p_snap) is null then 'Kassir hisobi xodim kartasiga bog''lanmagan (yoki bir nechta kartaga)' end
    from (select string_agg(coalesce(nullif(btrim(p_snap -> 'names' ->> u.x), ''), u.x), ', ' order by u.n) as names
            from jsonb_array_elements_text(case when jsonb_typeof(p_snap -> 'others') = 'array' then p_snap -> 'others' else '[]'::jsonb end)
                 with ordinality u(x, n)) o
$$;
revoke all on function app.kassa_shortage_why(jsonb) from public, anon, authenticated;

-- Hisobning kassada ko'rinadigan ismi (sec-4): bog'langan xodim kartasi ismi (HR yuritadi; asosiy havola — users.staffRefType / staffRefId,
--   bo'lmasa — teskari havola staff / teachers."userUid") → kartaga bog'lanmagan hisobda users.name (ism o'rnida email bo'lmasa — eski
--   ro'yxatdan o'tishda name = email) → uid. users.name ni foydalanuvchi o'zi o'zgartira oladi («Profil») — bog'langan hisobda u kassa
--   hujjatlariga chiqmaydi; bog'lanmaganlar nazorat ro'yxatida (kassa_checks → unlinkedUsers). Email HECH QACHON: kassa javoblari va
--   chop etishni 2-ro'yxat, jumladan buxgalter ham ko'radi (F1.21, D6); xodim ismi 2-ro'yxatga ochiq.
create or replace function app.kassa_user_label(p_name text, p_ref_type text, p_ref_id text, p_uid text) returns text
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(case when coalesce(p_ref_id, '') <> '' then
                    case when p_ref_type = 'teacher' then (select nullif(btrim(t.name), '') from public.teachers t where t.id = p_ref_id)
                         else (select nullif(btrim(s.name), '') from public.staff s where s.id = p_ref_id) end end,
                  (select nullif(btrim(s.name), '') from public.staff s where coalesce(p_uid, '') <> '' and s."userUid" = p_uid order by s.id limit 1),
                  (select nullif(btrim(t.name), '') from public.teachers t where coalesce(p_uid, '') <> '' and t."userUid" = p_uid order by t.id limit 1),
                  nullif(case when p_name ~ '@' then '' else btrim(p_name) end, ''),
                  p_uid)
$$;
revoke all on function app.kassa_user_label(text, text, text, text) from public, anon, authenticated;

-- Foydalanuvchi ismlari {uid: ism} — ekran va chop etish uchun (faqat berilgan uid'lar); ism — app.kassa_user_label (email emas).
create or replace function app.kassa_names(p_uids text[]) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select jsonb_object_agg(u.id, app.kassa_user_label(u.name, u."staffRefType", u."staffRefId", u.id))
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
--   p_after — kun yopilgandan keyin kiritilgan / tuzatilgan (kassa_day_z): hodisada "afterClose" belgisi (crit-4) — nazorat ro'yxati
--   («Z-hisobot kun yopilgandan keyin o'zgartirilgan») shundan; faktlar bir xil bo'lsa — belgisiz yozuv bilan ham takror hisoblanadi.
drop function if exists app.kassa_z_put(text, jsonb, text);
create or replace function app.kassa_z_put(p_day_id text, p_z jsonb, p_uid text, p_after boolean default false) returns boolean
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
  if v_last.id is not null and (v_last.data - 'afterClose') = v_data and coalesce(v_last.reason, '') = v_reason then return false; end if;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", at, reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_d.id, v_d.desk, v_d.day, 'zreport', p_uid, clock_timestamp(), nullif(v_reason, ''),
            v_data || case when coalesce(p_after, false) then jsonb_build_object('afterClose', true) else '{}'::jsonb end);
  return true;
end $$;
revoke all on function app.kassa_z_put(text, jsonb, text, boolean) from public, anon, authenticated;

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
           -- acc-6: smena topshirishda topilgan farqlar (qabul qilingan topshirishlar sanashidan, cash_counts — yagona manba): jami va
           --   har biri (vaqt tartibida, 0 lari tashlanadi). Yopish farqi — "diff"; kun farqi ko'rsatkichlari ikkalasidan
           'handoverDiff', coalesce((select sum(n.diff) from public.cash_counts n where n."dayId" = d.id and n.kind = 'handover'), 0),
           'handoverDiffs', coalesce((select jsonb_agg(n.diff order by n.at, n.id) from public.cash_counts n where n."dayId" = d.id and n.kind = 'handover' and n.diff <> 0), '[]'::jsonb),
           -- g6v-2: smena topshirishda sanalgan orderlar — qabul qilingan topshirishlar yozilgan paytdagi eng katta KO-1 / KO-2 raqamlari
           --   (shu raqamgacha orderni kassir bekor qilmaydi — kassa-docs.sql: kassa_doc_void; sahifa «Bekor» tugmasini ko'rsatmaydi)
           'countedKo1', (select max(h."lastKo1") from public.cash_handovers h where h."dayId" = d.id and h.status = 'accepted'),
           'countedKo2', (select max(h."lastKo2") from public.cash_handovers h where h."dayId" = d.id and h.status = 'accepted'),
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

-- Qayta ishga tushirish farqi (ishga-tushirish §9): kuni (p_after, p_to] oralig'idagi o'tkazilgan qayta ishga tushirish dalolatnomalarining
--   (nc_opening, "sourceSnapshot".kind = 'restart') kassa qoldig'iga ta'siri: Dt 5010 — «+», Kt 5010 — «−». Farq 0 bo'lsa dalolatnoma yo'q.
create or replace function app.kassa_restart_adj(p_desk text, p_after date, p_to date) returns numeric
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(sum(case when l.debit = '5010' then l.amount else -l.amount end), 0)
    from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id and l.cash
   where c.desk = p_desk and c.op = 'nc_opening' and c.status = 'posted' and c."sourceSnapshot" ->> 'kind' = 'restart'
     and c."businessDay" > p_after and c."businessDay" <= p_to
$$;
revoke all on function app.kassa_restart_adj(text, date, date) from public, anon, authenticated;

-- Kassadagi hisob qoldig'i (hozir): ochiq kun bo'lsa — uning qoldig'i; bo'lmasa — tayyorlangan qayta ishga tushirishning sanalgan summasi,
--   oxirgi yopilgan kun oxiri yoki boshlang'ich qoldiq (hech biri yo'q — NULL). «Kassa» kartasi, nazorat ro'yxati, Telegram bloki va davr
--   surati — bitta qoida.
create or replace function app.kassa_desk_balance(p_desk text) returns numeric
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select app.kassa_day_balance(d.id) from public.cash_days d where d.desk = k.id and d.status = 'open'),
                  case when k."restartDay" > (select max(d.day) from public.cash_days d where d.desk = k.id) then k."restartAmount" end,
                  (select d.closing from public.cash_days d where d.desk = k.id and d.status <> 'open' order by d.day desc limit 1),
                  k."openingAmount")
    from public.cash_desks k where k.id = p_desk
$$;
revoke all on function app.kassa_desk_balance(text) from public, anon, authenticated;

-- Kassa ishlagan va ishlamagan davrlar (ishga-tushirish §4, §9; g4v-1, g4v-4) — bitta manba (naqd yozuv himoyasi, naqd o'quv to'lovi,
--   moslik, nazorat ro'yxati, «Kassa» sahifasi):
--   «first» — birinchi ishga tushgan kun: kassa hech to'xtatilmagan bo'lsa — hozirgi «ishga tushadigan kun» (bo'sh yoki kelmagan —
--     kassa hali ishga tushmagan); to'xtatilgan bo'lsa — birinchi to'xtatishda amalda bo'lgan sana (hodisa jurnalidan; topilmasa —
--     birinchi kassa kuni);
--   «gaps» — to'xtatilgan davrlar [{after, before}]: oxirgi kassa kunidan (after) KEYIN va qayta ishga tushirish kunidan (before)
--     OLDIN (qayta sanalgan bo'lsa — oxirgi sanash kuni); kassa hozir to'xtatilgan va qayta ishga tushirish hali tayyorlanmagan
--     bo'lsa — oxirgi kassa kunidan keyingi kunlar («paused», «last»);
--   «hold» — kassa ushlab turilgan: to'xtatilgan yoki qayta ishga tushirish kunini kutmoqda (kassa kunlari bor, kassa hozir ishlamaydi).
create or replace function app.kassa_periods(p_desk text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select jsonb_build_object(
           'first', case when s.stopped then coalesce(s.pause_from, k."startDay") else o."kassaGoLive" end,
           'last', s.last_day,
           'paused', k."pausedAt" is not null,
           'hold', not k."isTest" and s.last_day is not null
                   and (k."pausedAt" is not null or (k."restartDay" > s.last_day and (o."kassaGoLive" is null or o."kassaGoLive" > app.fin_today()))),
           'gaps', s.gaps)
    from public.cash_desks k
    left join public.fin_org o on o.id = 'main'
   cross join lateral (
     select (select max(d.day) from public.cash_days d where d.desk = k.id) as last_day,
            (select (e.data ->> 'from')::date from public.cash_day_events e
              where e.desk = k.id and e.kind = 'golive' and e.data ->> 'pause' = 'true' and e.data ->> 'from' is not null
              order by e.at, e.id limit 1) as pause_from,
            k."pausedAt" is not null
              or exists (select 1 from public.cash_day_events e
                          where e.desk = k.id and ((e.kind = 'golive' and e.data ->> 'pause' = 'true') or (e.kind = 'opening' and e.data ->> 'restart' = 'true'))) as stopped,
            coalesce((select jsonb_agg(jsonb_build_object('after', g.prev_day, 'before', g.day) order by g.prev_day)
                        from (select distinct on (e.data ->> 'prevDay') (e.data ->> 'prevDay')::date as prev_day, e.day
                                from public.cash_day_events e
                               where e.desk = k.id and e.kind = 'opening' and e.data ->> 'restart' = 'true'
                               order by e.data ->> 'prevDay', e.at desc, e.id desc) g), '[]'::jsonb) as gaps) s
   where k.id = p_desk
$$;
revoke all on function app.kassa_periods(text) from public, anon, authenticated;

-- Kassa ishlamagan kunmi (g4v-1): birinchi ishga tushgan kundan OLDIN yoki to'xtatilgan davr ICHIDA (oxirgi kassa kunidan keyin,
--   qayta ishga tushirish kunidan oldin; hozir to'xtatilgan kassada — oxirgi kassa kunidan keyin). Faqat shunday kunning naqd puli
--   kassa hujjatisiz yoziladi (u komissiya sanashiga kirgan; kim — kassa-pay.sql, kassa-links.sql). Kassa ishlagan davr kuni
--   (oxirgi kassa kuni ham) — yo'q: u kunning naqd harakati faqat kassa hujjati bilan.
create or replace function app.kassa_pre_day(p_desk text, p_day date) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(p_day is not null
                  and ((x.j ->> 'first') is null or p_day < (x.j ->> 'first')::date
                       or exists (select 1 from jsonb_array_elements(x.j -> 'gaps') g
                                   where p_day > (g ->> 'after')::date and p_day < (g ->> 'before')::date)
                       or ((x.j ->> 'paused')::boolean and p_day > (x.j ->> 'last')::date)), false)
    from (select app.kassa_periods(p_desk) as j) x
$$;
revoke all on function app.kassa_pre_day(text, date) from public, anon, authenticated;

-- ---------- Boshlang'ich qoldiq (CT-02): FAQAT Direktor, kassa ishga tushguncha ----------
--   p: desk, amount (0 mumkin), startDay ('YYYY-MM-DD' — birinchi kassa kuni), note, commission [{title, name}]
--   QAYTA ISHGA TUSHIRISH (ishga-tushirish §9; ui-5): to'xtatilgan kassada (yoki tayyorlangan, hali boshlanmagan qayta ishga
--   tushirishni o'sha kun bilan qayta sanashda) — amount: komissiya sanagan summa, startDay: qayta ishga tushirish kuni (oxirgi kassa
--   kunidan keyin, bugundan oldin emas). Sanalgan summa bilan oxirgi kun oxiri farqi — texnik dalolatnoma («Д-», OP-23; ortiqcha —
--   Dt 5010 Kt 0000, kam — Dt 0000 Kt 5010; asos «Qayta ishga tushirish: sanash dalolatnomasi»): to'xtatilgan davrda kassa hujjatisiz
--   yozilgan naqd harakat (nazorat ro'yxati, «Kassani to'xtatish va qayta ishga tushirish» — buxgalter solishtiradi). Kassir zimmasiga
--   kamomad / ortiqcha yozilmaydi. Qayta ochilgan birinchi kun boshi — sanalgan summa; kassa ishga tushadigan kun (fin_org_set) shu
--   sanaga qo'yilgach qayta ishlaydi. Kassa keyin yana to'xtatilsa — navbatdagi qayta ishga tushirish xuddi shunday (har biri o'z
--   dalolatnomasi bilan). Qayta ishga tushirish kuni va undan keyingi sana bilan kassa hujjatisiz naqd yozuv bo'lmasin (kassa:restart_gap):
--   u yangi kassa davrida «hujjatisiz naqd harakat» bo'lib qolardi (fin_org_set ham qabul qilmaydi — kassa:live_gap). Sanashdan KEYIN
--   to'xtatilgan davr sanasi bilan kassa hujjatisiz naqd yozuv kiritilsa — u sanashga kirmagan: ishga tushadigan kun qo'yilmaydi va birinchi
--   qayta ochilgan kun ochilmaydi (kassa:restart_recount), komissiya qayta sanaydi (shu kun bilan qayta kiritish avvalgisini bekor qiladi).
create or replace function public.kassa_opening_set(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text; v_amount numeric; v_start date; v_k public.cash_desks%rowtype; v_doc_id text;
  v_comm jsonb; v_note text; v_last public.cash_days%rowtype; v_delta numeric; v_gap jsonb; v_pfrom timestamptz;
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

  -- Qulf tartibi (kassa.sql, QULF TARTIBI): sozlama qatori FOR SHARE — kassa qulfi (L4) va kassa qatoridan OLDIN. «Ishga tushadigan kun»
  --   shu payt o'zgarayotgan bo'lsa (fin_org_set FOR UPDATE → app.kassa_golive_guard kassa qatorini yangilaydi) — u tugaguncha kutiladi;
  --   aksincha (kassa qatori ushlangan holda sozlama qatorini kutish) o'zaro qulflanish (deadlock) bo'lardi.
  perform 1 from public.fin_org o where o.id = 'main' for share;
  perform app.kassa_lock_desk(v_desk);
  select * into v_k from public.cash_desks k where k.id = v_desk and k.active for update;
  if not found then raise exception 'Kassa topilmadi' using errcode = '22023', hint = 'kassa:bad_desk'; end if;
  select * into v_last from public.cash_days d where d.desk = v_desk order by d.day desc limit 1;
  if v_last.id is not null then
    -- tayyorlangan qayta ishga tushirish va ishga tushadigan kun allaqachon shu sanada: boshqa kun — avval sanani bo'shatish (kassa yana
    --   to'xtatiladi), keyin yangi kun bilan qayta sanash
    if not v_k."isTest" and v_k."pausedAt" is null and v_k."restartDay" > v_last.day and v_start <> v_k."restartDay" then
      raise exception 'Qayta ishga tushirish % ga tayyorlangan va ishga tushadigan kun shu sanaga qo''yilgan: boshqa kun bilan qayta sanash uchun avval «⚙ Sozlamalar»da ishga tushadigan kunni bo''shating (kassa yana to''xtatiladi), keyin qoldiqni yangi kun bilan kiriting',
        to_char(v_k."restartDay", 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:restart_pending';
    end if;
    if v_k."isTest" or not (v_k."pausedAt" is not null or coalesce(v_k."restartDay" > v_last.day and v_start = v_k."restartDay", false)) then
      raise exception 'Kassa ishga tushgan — boshlang''ich qoldiq endi o''zgarmaydi' using errcode = '42501', hint = 'kassa:started';
    end if;
    if v_last.status = 'open' then   -- (to'xtatishda ochiq kun bo'lmaydi — himoya)
      raise exception 'Avval % kassa kunini sanab yoping', to_char(v_last.day, 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:prev_open';
    end if;
    if v_start <= v_last.day or v_start < app.fin_today() then
      raise exception 'Qayta ishga tushirish kuni oxirgi kassa kunidan (%) keyin va bugundan oldin bo''lmasin', to_char(v_last.day, 'DD.MM.YYYY')
        using errcode = '22023', hint = 'kassa:bad_input';
    end if;
  end if;
  if not v_k."isTest" then   -- yopilgan davrga kassa kuni qo'yilmaydi (fin-period.sql); sozlama qatori boshida FOR SHARE bilan olingan
    perform app.fin_lock_check(v_start, case when v_last.id is null then 'Birinchi kassa kuni' else 'Qayta ishga tushirish kuni' end);
  end if;
  if v_last.id is not null then   -- qayta ishga tushirish (sinov kassasida — yo'q, yuqorida rad)
    -- to'xtatilgan davrdagi kassa hujjatisiz naqd yozuvlar qayta ishga tushirish kunidan OLDINGI sanali bo'lsin
    v_gap := app.kassa_cash_rows(v_start, v_start + 366, null);
    if (v_gap ->> 'n')::int > 0 then
      raise exception 'Qayta ishga tushirish kuni (%) yoki undan keyingi sana bilan kassa hujjatisiz naqd yozuvlar bor (% ta) — ular to''xtatilgan davrga tegishli: qayta ishga tushirish kunini ulardan keyingi kunga qo''ying (sana xato bo''lsa — yozuvni tuzating)',
        to_char(v_start, 'DD.MM.YYYY'), v_gap ->> 'n' using errcode = 'P0001', hint = 'kassa:restart_gap';
    end if;
    -- to'xtatilgan davr boshi (nazorat ro'yxati: shu paytdan qayta ishga tushirish kunigacha kiritilgan yozuvlar, sanasidan qat'i nazar):
    --   kassa hozir to'xtatilgan bo'lsa — "pausedAt"; tayyorlangan qayta ishga tushirishni qayta sanashda — avvalgi sanashdagisi (eng erta)
    v_pfrom := least(v_k."pausedAt",
                     (select (e.data ->> 'pausedFrom')::timestamptz from public.cash_day_events e
                       where e.desk = v_desk and e.kind = 'opening' and e.data ->> 'restart' = 'true' and v_k."restartDay" > v_last.day
                         and e.day = v_k."restartDay" order by e.at desc, e.id desc limit 1));
  end if;
  perform app.kassa_flag(true);
  if v_last.id is not null then   -- qayta ishga tushirish
    v_delta := v_amount - v_last.closing;
    -- Avval kiritilgan (hali boshlanmagan) qayta ishga tushirish dalolatnomasi bo'lsa — bekor qilinadi (raqami saqlanadi).
    if v_k."restartDocId" is not null and v_k."restartDay" > v_last.day then
      update public.cash_docs set status = 'void', "voidedBy" = v_uid, "voidedAt" = now(), "voidReason" = 'Qayta ishga tushirish qoldig''i qayta kiritildi'
       where id = v_k."restartDocId" and status = 'posted';
    end if;
    if v_delta <> 0 then
      select b.o_id into v_doc_id from app.kassa_doc_build(jsonb_build_object(
          'desk', v_desk, 'op', 'nc_opening', 'amount', abs(v_delta), 'clientRef', 'opening_' || replace(gen_random_uuid()::text, '-', ''),
          'partyName', 'Qayta ishga tushirish', 'basis', 'Qayta ishga tushirish: sanash dalolatnomasi', 'note', v_note,
          'sourceSnapshot', jsonb_build_object('kind', 'restart', 'prevDay', v_last.day, 'prevClosing', v_last.closing, 'counted', v_amount,
                                               'startDay', v_start, 'pausedAt', v_k."pausedAt"),
          'lines', jsonb_build_array(jsonb_build_object('debit', case when v_delta > 0 then '5010' else '0000' end,
                                                        'credit', case when v_delta > 0 then '0000' else '5010' end, 'amount', abs(v_delta), 'articleId', 'OP-23'))),
        'ACT', v_uid, true) b;
      perform app.kassa_act_post(v_doc_id, v_uid, v_start);
    end if;
    -- "restartAt" — sanash payti, pul yozuvlari "createdAt" bilan bir soatda (app.fin_now): undan keyin kiritilgan kassa hujjatisiz naqd
    --   yozuv sanashga kirmagan — birinchi qayta ochilgan kun qayta sanashsiz ochilmaydi (g4v-2: kassa-links.sql app.kassa_restart_stale)
    update public.cash_desks set "restartDay" = v_start, "restartAmount" = v_amount, "restartDocId" = v_doc_id, "restartBy" = v_uid, "restartAt" = app.fin_now()
     where id = v_desk;
    insert into public.cash_counts (id, desk, day, kind, expected, counted, diff, "diffDocId", commission, note, "byUid", at)
      values ('cc_' || replace(gen_random_uuid()::text, '-', ''), v_desk, v_start, 'opening', v_last.closing, v_amount, v_delta, v_doc_id, v_comm, v_note, v_uid, clock_timestamp());
    insert into public.cash_day_events (id, desk, day, kind, "byUid", at, reason, data)   -- at — qayta sanash bir tranzaksiyada ham tartibli
      values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_desk, v_start, 'opening', v_uid, clock_timestamp(), v_note,
              jsonb_build_object('amount', v_amount, 'docId', v_doc_id, 'restart', true, 'prevDay', v_last.day, 'prevClosing', v_last.closing, 'delta', v_delta,
                                 'pausedFrom', v_pfrom));
    perform app.kassa_flag(false);
    return jsonb_build_object('ok', true, 'restart', true, 'delta', v_delta, 'doc', case when v_doc_id is not null then app.kassa_doc_json(v_doc_id) end,
                              'desk', (select to_jsonb(k) from public.cash_desks k where k.id = v_desk));
  end if;
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

-- ---------- «Kassa ishga tushadigan kun» o'zgarishi: to'xtatish va qayta ishga tushirish (ishga-tushirish §9; ui-5) ----------
--   fin_org_set (fin-core.sql) sana o'zgarganda DINAMIK chaqiradi — sozlama qatori FOR UPDATE bilan ushlangan holda. Natija — saqlanadigan sana.
--   * TO'XTATISH — kelgan sana bo'shatilsa yoki keyinga surilsa, kassada kunlar bo'lsa: kassa qulfi (L4) bo'sh bo'lishi (shu payt hujjat
--     yozilmayotgan), qabul qilinmagan smena topshirish (state-6, kassa:rollback_handover), ochiq kassa kuni, qurilma navbatidagi hali
--     o'tkazilmagan yozuvlar bilan yopilgan oxirgi kun (g4b-v1: ishga-tushirish §9 (1)
--     — navbat avval yuborilsin) va pul berilmagan so'rovlar (tasdiq kutayotgan / tasdiqlangan) bo'lmasligi shart — aks holda rad,
--     alohida hint bilan. Kassa to'xtatiladi ("pausedAt"): yangi kassa kuni ochilmaydi, naqd pul kassa hujjatisiz yoziladi. Saqlanadigan sana —
--     bo'sh (kiritilgan keyingi sana — rejalashtirilgan kun sifatida hodisada qoladi): qayta ishga tushirish faqat yangi komissiya sanashi bilan.
--   * TO'XTATILGAN kassada sana faqat tayyorlangan qayta ishga tushirish kuniga ("restartDay", kassa_opening_set) qo'yiladi — kassa
--     shundan qayta ishlaydi; tayyorlangan, hali boshlanmagan qayta ishga tushirishda sana bo'shatilsa — kassa yana to'xtatiladi.
--     Sanashdan keyin to'xtatilgan davr sanasi bilan kassa hujjatisiz naqd yozuv kiritilgan bo'lsa — rad (kassa:restart_recount, g4v-2);
--     qayta ishga tushirish kuni va undan keyingi sana bilan bunday yozuv bo'lsa ham — rad (kassa:restart_gap, g4b).
--   Har o'zgarish kun jurnaliga 'golive' hodisasi bo'lib yoziladi (kim, qachon, qaysi sanadan qaysiga). Sinov kassasi bunga kirmaydi.
--   Qulf tartibi: sozlama qatori (FOR UPDATE) → kassa qulfi faqat pg_try_advisory_xact_lock bilan (kutmaydi) — yozuvchilar sozlama qatorini
--   FOR SHARE bilan kassa qulfidan oldin ham, keyin ham oladi; kutmaydigan qulf o'zaro qulflanishga (deadlock) yo'l qo'ymaydi.
create or replace function app.kassa_golive_guard(p_old date, p_new date) returns date
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_today date := app.fin_today(); v_k public.cash_desks%rowtype; v_last date; v_open date; v_req text;
  v_store date := p_new; v_pause boolean; v_resume boolean; v_reached boolean := p_old is not null and p_old <= app.fin_today(); v_stale jsonb;
  v_pcnt int; v_psum numeric; v_gap jsonb;
begin
  for v_k in select * from public.cash_desks k where not k."isTest" and k.active order by k.id loop
    select max(d.day) into v_last from public.cash_days d where d.desk = v_k.id;
    v_pause := false; v_resume := false;
    if v_k."pausedAt" is not null then   -- to'xtatilgan kassa
      if p_new is not null then
        if v_k."restartDay" is null or v_k."restartDay" <= v_last then
          raise exception 'Kassa to''xtatilgan: avval komissiya sanashi bilan qayta ishga tushirish qoldig''ini kiriting («Qayta ishga tushirish»), keyin ishga tushadigan kunni shu sanaga qo''ying'
            using errcode = 'P0001', hint = 'kassa:restart_needed';
        end if;
        if p_new <> v_k."restartDay" then
          raise exception 'Qayta ishga tushirish kuni — %: ishga tushadigan kun shu sana bo''ladi (boshqa sana kerak bo''lsa — qoldiqni o''sha sana bilan qayta kiriting)',
            to_char(v_k."restartDay", 'DD.MM.YYYY') using errcode = '22023', hint = 'kassa:restart_day';
        end if;
        -- g4v-2: sanashdan keyin to'xtatilgan davr sanasi bilan kassa hujjatisiz naqd yozuv kiritilgan — sanalgan summa eskirgan
        --   (birinchi qayta ochilgan kun ham ochilmaydi: kassa-docs.sql app.kassa_resolve_day)
        v_stale := app.kassa_restart_stale(v_k.id);
        if coalesce((v_stale ->> 'n')::int, 0) > 0 then
          raise exception 'Qayta ishga tushirish sanashidan (%) keyin kassa hujjatisiz % ta naqd yozuv kiritilgan, sanasi qayta ishga tushirish kunidan (%) oldin: kirim % so''m, chiqim % so''m — ular komissiya sanagan summaga kirmagan. Ishga tushadigan kun qo''yilmaydi: komissiya pulni qayta sanaydi va «Qayta ishga tushirish» qoldig''i qayta kiritiladi (avvalgi dalolatnoma bekor bo''ladi)',
            to_char(v_k."restartAt" at time zone 'Asia/Tashkent', 'DD.MM.YYYY HH24:MI'), v_stale ->> 'n', to_char(v_k."restartDay", 'DD.MM.YYYY'),
            trim_scale((v_stale ->> 'in')::numeric), trim_scale((v_stale ->> 'out')::numeric) using errcode = 'P0001', hint = 'kassa:restart_recount';
        end if;
        -- g4b: qayta ishga tushirish kuni va undan keyingi sana bilan kassa hujjatisiz naqd yozuv (sanashdan keyin, kassa to'xtatilgan
        --   paytda kiritilgan — kun o'tib ketgach eski tartib davom etgan; yoki himoyasiz eski yo'l) — yangi kassa davri yetimi bo'lardi
        --   (sanashda kassa_opening_set ham shu qoida bilan rad etadi; kelgan kunda fin_org_set — kassa:live_gap, kelajakdagisida — faqat shu yerda)
        v_gap := app.kassa_cash_rows(v_k."restartDay", v_k."restartDay" + 366, null);
        if coalesce((v_gap ->> 'n')::int, 0) > 0 then
          raise exception 'Qayta ishga tushirish kuni (%) yoki undan keyingi sana bilan kassa hujjatisiz % ta naqd yozuv bor — kassa shu kundan ishlasa, ular kassa hujjatlarida bo''lmaydi. Ishga tushadigan kun qo''yilmaydi: sana xato bo''lsa — yozuvni tuzating; aks holda komissiya qayta sanaydi va «Qayta ishga tushirish» qoldig''i ulardan keyingi kun bilan qayta kiritiladi',
            to_char(v_k."restartDay", 'DD.MM.YYYY'), v_gap ->> 'n' using errcode = 'P0001', hint = 'kassa:restart_gap';
        end if;
        v_resume := true;
      end if;
    elsif v_k."restartDay" is not null and v_k."restartDay" > coalesce(v_last, v_k."restartDay" - 1) then   -- tayyorlangan qayta ishga tushirish
      if p_new is null then v_pause := true;
      elsif p_new <> v_k."restartDay" then   -- (sana allaqachon qayta ishga tushirish kunida: boshqa kun — avval bo'shatib, qayta sanash)
        raise exception 'Qayta ishga tushirish kuni — %: ishga tushadigan kun shu sana bo''ladi. Boshqa sana kerak bo''lsa — avval ishga tushadigan kunni bo''shating (kassa yana to''xtatiladi), keyin «Qayta ishga tushirish» qoldig''ini o''sha sana bilan qayta kiriting',
          to_char(v_k."restartDay", 'DD.MM.YYYY') using errcode = '22023', hint = 'kassa:restart_day';
      end if;
    elsif v_reached and (p_new is null or p_new > p_old) then   -- kelgan sana bo'shatiladi yoki suriladi — kassani to'xtatish
      if not pg_try_advisory_xact_lock(hashtext('iqror_desk:' || v_k.id)) then   -- shu payt kun ochilayotgan / hujjat yozilayotgan bo'lmasin
        raise exception 'Kassada hozir hujjat yozilmoqda — bir oz kutib, qayta saqlang' using errcode = 'P0001', hint = 'kassa:busy';
      end if;
      select max(d.day) into v_last from public.cash_days d where d.desk = v_k.id;
      -- state-6: smena topshirish qabul qilinmagan (pul sanalgan, ikki kassir kassa yonida) — avval qabul qilinsin yoki bekor qilinsin
      if exists (select 1 from public.cash_handovers h where h.desk = v_k.id and h.status = 'pending') then
        raise exception 'Kassani to''xtatib bo''lmaydi: smena topshirish qabul qilinmagan — avval qabul qiluvchi uni qabul qilsin yoki topshirish bekor qilinsin, keyin kunni sanab yoping (ishga-tushirish §9)'
          using errcode = 'P0001', hint = 'kassa:rollback_handover';
      end if;
      select d.day into v_open from public.cash_days d where d.desk = v_k.id and d.status = 'open';
      if v_open is not null then
        raise exception 'Kassani to''xtatib bo''lmaydi: % kassa kuni ochiq — avval pulni sanab, kunni yoping (ishga-tushirish §9)', to_char(v_open, 'DD.MM.YYYY')
          using errcode = 'P0001', hint = 'kassa:rollback_open_day';
      end if;
      -- g4b-v1 (ishga-tushirish §9 (1)): oxirgi kun qurilma navbatidagi hali o'tkazilmagan yozuvlar bilan yopilgan — bu pul kassada bor
      --   (sanalgan), hisobda hali yo'q. To'xtatilgandan keyin u to'g'ri yozilmaydi: to'xtatilgan kassa oxirgi kassa kuni sanasi bilan naqd
      --   to'lovni qabul qilmaydi, qayta ishga tushgach esa kech kirim orderi uni komissiya sanashiga qo'shimcha — ikkinchi marta — hisoblardi
      --   (birinchi yopishda kassirga kamomad). Navbat avval yuboriladi: kun qayta ochiladi, yozuvlar o'sha kunga tushadi, kun qayta yopiladi.
      select d."pendingCount", d."pendingSum" into v_pcnt, v_psum from public.cash_days d where d.desk = v_k.id and d.day = v_last;
      if coalesce(v_pcnt, 0) > 0 then
        raise exception 'Kassani to''xtatib bo''lmaydi: oxirgi kassa kuni (%) qurilma navbatidagi hali o''tkazilmagan % ta yozuv (% so''m) bilan yopilgan — bu pul kassada bor, hisobda hali yo''q (to''xtatilgandan keyin u to''g''ri yozilmaydi). Avval navbat yuborilsin: Direktor kunni qayta ochadi, qurilmalar navbati o''tgach kun qayta sanab yopiladi (kun tekshirilgan bo''lsa — navbat keyingi kassa kuniga «kech» tushadi, o''sha kun yopiladi), keyin kassa to''xtatiladi (ishga-tushirish §9)',
          to_char(v_last, 'DD.MM.YYYY'), v_pcnt, trim_scale(v_psum) using errcode = 'P0001', hint = 'kassa:rollback_pending';
      end if;
      select string_agg(x.t, '; ' order by x.rn) filter (where x.rn <= 10)
             || case when count(*) > 10 then '; … (jami ' || count(*) || ' ta)' else '' end
        into v_req
        from (select case when c.form = 'KO1' then 'kirim' else 'chiqim' end || ' «' || coalesce(r."nameUz", c.op) || '» ' || trim_scale(c.amount) || ' so''m — '
                     || case when c.status = 'draft' then 'tasdiq kutilmoqda' else 'tasdiqlangan, pul berilmagan' end as t,
                     row_number() over (order by c."createdAt", c.id) as rn
                from public.cash_docs c left join public.fin_op_rules r on r.op = c.op
               where c.desk = v_k.id and c.status in ('draft', 'approved')) x;
      if v_req is not null then
        raise exception 'Kassani to''xtatib bo''lmaydi: pul berilmagan kassa so''rovlari bor — avval ularni bekor qiling yoki pulini bering: %', v_req
          using errcode = 'P0001', hint = 'kassa:rollback_requests';
      end if;
      v_pause := v_last is not null;
      if v_pause then v_store := null; end if;
    end if;
    perform app.kassa_flag(true);
    if v_pause then
      update public.cash_desks set "pausedAt" = app.fin_now(), "pausedBy" = v_uid where id = v_k.id;
    elsif v_resume then
      update public.cash_desks set "pausedAt" = null, "pausedBy" = null where id = v_k.id;
    end if;
    insert into public.cash_day_events (id, desk, day, kind, "byUid", at, data)
      values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_k.id, v_today, 'golive', v_uid, clock_timestamp(),
              jsonb_build_object('from', p_old, 'to', p_new, 'stored', v_store, 'pause', v_pause, 'resume', v_resume, 'lastDay', v_last));
    perform app.kassa_flag(false);
  end loop;
  return v_store;
end $$;
revoke all on function app.kassa_golive_guard(date, date) from public, anon, authenticated;

-- ---------- Kunni sanab yopish (CT-03) ----------
--   p: desk, day ('YYYY-MM-DD' — yopilayotgan kun; eski ekrandan boshqa kunni yopib qo'ymaslik uchun), counted, denoms {nominal: soni},
--      pendingCount, pendingSum (qurilma navbatidagi hali o'tkazilmagan yozuvlar), note, commission [{title, name}],
--      z — onlayn kassa Z-hisoboti {no, cash, card} yoki {missing: true, reason} (ixtiyoriy; sinov kassasida e'tiborga olinmaydi)
--   Kassa egasi (kun kassiri, "cashierUid") yopadi. Boshqa kassir (g'aznachi), Direktor yoki Moliya menejeri — kassir o'rniga, kamida
--   2 kishilik komissiya bilan (sec-2; kassa egasi hali aniqlanmagan kunni kassa operatori o'zi yopadi). Smena topshirish kutilayotganda
--   kun yopilmaydi (state-6: avval qabul qilinadi yoki bekor qilinadi). Kamomad hujjati suratida kassa egasi va sanagan xodim alohida.
create or replace function public.kassa_day_close(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text; v_day date; v_d public.cash_days%rowtype; v_counted numeric; v_pending numeric; v_pcount int;
  v_denoms jsonb; v_comm jsonb; v_note text; v_exp numeric; v_diff numeric; v_doc_id text; v_cnt_id text;
  v_rec numeric; v_pay numeric; v_docs int; v_f1 int; v_l1 int; v_f2 int; v_l2 int; v_rows int; v_sheets int; v_from int;
  v_op boolean := app.kassa_operator(); v_holder text;
begin
  if not (v_op or app.is_admin() or app.is_finance_mgr()) then
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
  if not v_op and jsonb_array_length(v_comm) < 2 then   -- kassir o'rniga yopish: 2 kishilik dalolatnoma
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
  perform app.kassa_handover_block(v_desk);   -- state-6: smena topshirish kutilmoqda — avval qabul qilinadi yoki bekor qilinadi
  -- sec-2: kassa egasi bo'lmagan kassir (g'aznachi) yopsa — kassir o'rniga: 2 kishilik dalolatnoma (Direktor / Moliya menejeri — yuqorida).
  --   Kassa egasi hali aniqlanmagan kunni (faqat Direktor / Moliya menejeri hujjatlari) kassa operatori o'zi yopadi — u kassa egasi.
  v_holder := coalesce(v_d."cashierUid", case when v_op then v_uid end);
  if v_op and v_holder is distinct from v_uid and jsonb_array_length(v_comm) < 2 then
    raise exception 'Kunni kassa egasi — % — yopadi: uning o''rniga yopishda kamida 2 kishilik komissiya ko''rsatiladi (yoki avval smena topshiriladi)',
      coalesce(v_d."cashierName", app.kassa_names(array[v_holder]) ->> v_holder, v_holder) using errcode = '22023', hint = 'kassa:commission';
  end if;

  perform app.kassa_flag(true);
  -- Z-hisobot (F1.26) — sanashdan oldin: noto'g'ri ma'lumot bo'lsa kun yopilmaydi (xato matni bilan qaytadi)
  if jsonb_typeof(p -> 'z') = 'object' and not coalesce((select k."isTest" from public.cash_desks k where k.id = v_desk), false) then
    perform app.kassa_z_put(v_d.id, p -> 'z', v_uid);
  end if;
  select c.o_expected, c.o_diff, c.o_doc_id, c.o_count_id into v_exp, v_diff, v_doc_id, v_cnt_id
    from app.kassa_count_apply(v_desk, v_d.id, v_d.day, 'close', v_counted, v_pending, v_denoms, v_comm, v_note, v_uid, v_holder, v_uid, null, null) c;
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
         hash = app.kassa_day_hash(v_d.id), "closedBy" = v_uid, "closedAt" = now(), "closeNote" = v_note, commission = v_comm,
         "closedByName" = app.kassa_names(array[v_uid]) ->> v_uid   -- sec-4: yopish paytidagi ism
   where id = v_d.id;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_d.id, v_desk, v_d.day, 'close', v_uid, v_note,
            jsonb_build_object('expected', v_exp, 'counted', v_counted, 'pendingSum', v_pending, 'diff', v_diff, 'diffDocId', v_doc_id, 'countId', v_cnt_id,
                               'cashierUid', v_holder));
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', false, 'day', app.kassa_day_json(v_d.id), 'expected', v_exp, 'diff', v_diff,
                            'diffDoc', case when v_doc_id is not null then app.kassa_doc_json(v_doc_id) end);
end $$;
revoke all on function public.kassa_day_close(jsonb) from public, anon;
grant execute on function public.kassa_day_close(jsonb) to authenticated;

-- ---------- Smena topshirish-qabul (FD-16): IKKI BOSQICHLI (state-6), kun ochiq qoladi ----------
--   1) kassa_handover(p) — topshiruvchi pulni qabul qiluvchi bilan birga sanaydi va KUTILAYOTGAN topshirish yozadi (cash_handovers):
--      kassa egasi hali o'zgarmaydi, sanash dalolatnomasi va farq hujjati hali yozilmaydi. Kassa egasi (kun kassiri) bo'lmagan kassir
--      (g'aznachi) yoki Direktor — kassir o'rniga (sec-2): kamida 2 kishilik komissiya bilan (shunda qabul qiluvchi o'zi ham bo'lishi
--      mumkin — egasi yo'q kassani qabul qilish). Kutilayotgan paytda kassada hujjat yozilmaydi va bekor qilinmaydi, kun yopilmaydi
--      (app.kassa_handover_block). Aynan shu so'rov qayta kelsa (javob yetib kelmagan) — o'sha topshirish qaytadi.
--   2) kassa_handover_accept(id) — FAQAT qabul qiluvchi o'z hisobidan: sanash dalolatnomasi (cash_counts), farq bo'lsa — shu kun hujjati
--      (kamomad / ortiqcha; kassa egasi — topshiruvchi, sanagan — topshirishni yozgan xodim), kassa egasi — qabul qiluvchi. Topshirish
--      yozilgan paytgacha o'tkazilgan orderlar (raqami "lastKo1" / "lastKo2" gacha) sanashga kirgan — kassir ularni bekor qilmaydi (g6v-2).
--   3) kassa_handover_cancel(id, sabab) — topshiruvchi (kassa egasi yoki topshirishni yozgan xodim), qabul qiluvchi (rad etish) yoki Direktor.
--   p: desk, counted, denoms, pendingSum, toUid (qabul qiluvchi kassir), note, commission [{title, name}]
create or replace function public.kassa_handover(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_op boolean := app.kassa_operator(); v_desk text; v_d public.cash_days%rowtype; v_counted numeric; v_pending numeric;
  v_denoms jsonb; v_to text; v_note text; v_comm jsonb; v_holder text; v_from text; v_h public.cash_handovers%rowtype; v_exp numeric;
begin
  if not (v_op or app.is_admin()) then
    raise exception 'Ruxsat yo''q: smenani kassir topshiradi' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_desk := coalesce(nullif(btrim(coalesce(p ->> 'desk', '')), ''), 'main');
  v_counted := app.kassa_amount0(p -> 'counted', 'Sanalgan summa');
  if v_counted is null then raise exception 'Kassadagi pulni sanab, summasini kiriting' using errcode = '22023', hint = 'kassa:count'; end if;
  v_pending := coalesce(app.kassa_amount0(p -> 'pendingSum', 'Hali o''tkazilmagan yozuvlar'), 0);
  if v_counted < v_pending then
    raise exception 'Sanalgan summa hali o''tkazilmagan yozuvlar summasidan kam bo''lmaydi' using errcode = '22023', hint = 'kassa:count';
  end if;
  v_denoms := app.kassa_denoms_check(p -> 'denoms', v_counted);
  v_note := left(btrim(coalesce(p ->> 'note', '')), 500);
  v_comm := app.kassa_commission(p -> 'commission');
  v_to := nullif(btrim(coalesce(p ->> 'toUid', '')), '');
  perform app.kassa_lock_desk(v_desk);
  select * into v_d from public.cash_days d where d.desk = v_desk and d.status = 'open' for update;
  if not found then raise exception 'Ochiq kassa kuni yo''q' using errcode = 'P0001', hint = 'kassa:no_open_day'; end if;
  -- kutilayotgan topshirish bor: aynan shu so'rov qayta kelgan bo'lsa — o'sha (javob yetib kelmagan); boshqasi — rad
  v_h := app.kassa_handover_pending(v_desk);
  if v_h.id is not null then
    if v_h."byUid" = v_uid and v_h."toUid" is not distinct from v_to and v_h.counted = v_counted and v_h."pendingSum" = v_pending then
      return jsonb_build_object('ok', true, 'dup', true, 'pending', true, 'handover', to_jsonb(v_h), 'expected', v_h.expected, 'diff', v_h.diff,
                                'day', app.kassa_day_json(v_d.id));
    end if;
    perform app.kassa_handover_block(v_desk);
  end if;
  -- sec-2: kassa egasi (kun kassiri) bo'lmagan kassir yoki Direktor — kassir o'rniga: kamida 2 kishilik komissiya.
  --   Kassa egasi hali aniqlanmagan kunda (faqat Direktor / Moliya menejeri hujjatlari) kassa operatori — o'zi topshiruvchi.
  v_holder := v_d."cashierUid";
  v_from := coalesce(v_holder, case when v_op then v_uid end);
  if v_from is distinct from v_uid and jsonb_array_length(v_comm) < 2 then
    raise exception '%', case when v_holder is not null
                              then format('Smenani kassa egasi — %s — topshiradi: uning o''rniga topshirishda kamida 2 kishilik komissiya ko''rsatiladi',
                                          coalesce(v_d."cashierName", app.kassa_names(array[v_holder]) ->> v_holder, v_holder))
                              else 'Kassir o''rniga smena topshirishda kamida 2 kishilik komissiya ko''rsatiladi' end
      using errcode = '22023', hint = 'kassa:commission';
  end if;
  -- qabul qiluvchi: faol kassir / g'aznachi, kassa egasining o'zi emas (o'zingizga — faqat kassir o'rniga, komissiya bilan)
  if v_to is null or not app.kassa_op_user(v_to) or v_to is not distinct from v_from then
    raise exception 'Qabul qiluvchi kassir tanlanmagan, kassir emas yoki kassaning hozirgi egasi' using errcode = '22023', hint = 'kassa:handover_to';
  end if;
  v_exp := app.kassa_day_balance(v_d.id);
  perform app.kassa_flag(true);
  -- g6v-2: sanashga kirgan orderlar — shu paytdagi eng katta KO-1 / KO-2 raqamlari (kutilayotganda yangi order yo'q, raqam kassa qulfi ostida)
  insert into public.cash_handovers (id, desk, "dayId", day, status, "fromUid", "toUid", "byUid", expected, counted, "pendingSum", diff, denoms, commission, note,
                                     names, "createdAt", "lastKo1", "lastKo2")
    values ('ho_' || replace(gen_random_uuid()::text, '-', ''), v_desk, v_d.id, v_d.day, 'pending', v_from, v_to, v_uid, v_exp, v_counted, v_pending,
            v_counted - v_exp - v_pending, v_denoms, v_comm, v_note, app.kassa_names(array[v_from, v_to, v_uid]), clock_timestamp(),
            (select max(c.no) from public.cash_docs c where c."dayId" = v_d.id and c.form = 'KO1' and c.no is not null),
            (select max(c.no) from public.cash_docs c where c."dayId" = v_d.id and c.form = 'KO2' and c.no is not null))
    returning * into v_h;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", at, reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_d.id, v_desk, v_d.day, 'handover', v_uid, clock_timestamp(), nullif(v_note, ''),
            jsonb_build_object('step', 'pending', 'handoverId', v_h.id, 'fromUid', v_from, 'toUid', v_to, 'expected', v_exp, 'counted', v_counted,
                               'pendingSum', v_pending, 'diff', v_h.diff));
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', false, 'pending', true, 'handover', to_jsonb(v_h), 'expected', v_exp, 'diff', v_h.diff,
                            'day', app.kassa_day_json(v_d.id));
end $$;
revoke all on function public.kassa_handover(jsonb) from public, anon;
grant execute on function public.kassa_handover(jsonb) to authenticated;

-- Smenani qabul qilish (state-6): FAQAT qabul qiluvchi kassir o'z hisobidan. Kutilayotgan paytda kassa qoldig'i o'zgarmagan bo'lishi shart
--   (hujjatlar to'xtatilgan; himoya — farq bo'lsa rad, topshirish bekor qilinib qayta sanaladi). Farq hujjati — kassa egasi (topshiruvchi)
--   nomidan, sanagan — topshirishni yozgan xodim; kassa egasi — qabul qiluvchi, kunning «boshqalar» ro'yxati bo'shatiladi (g6v-1).
--   Qayta yuborilsa — takror (o'zgarishsiz).
create or replace function public.kassa_handover_accept(p_id text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text; v_h public.cash_handovers%rowtype; v_d public.cash_days%rowtype; v_exp numeric; v_diff numeric;
  v_doc_id text; v_cnt_id text;
begin
  if not app.kassa_operator() then
    raise exception 'Ruxsat yo''q: smenani qabul qiluvchi kassir o''z hisobidan qabul qiladi' using errcode = '42501';
  end if;
  select h.desk into v_desk from public.cash_handovers h where h.id = p_id;
  if v_desk is null then raise exception 'Smena topshirish topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  perform app.kassa_lock_desk(v_desk);
  select * into v_h from public.cash_handovers h where h.id = p_id for update;
  if v_h."toUid" is distinct from v_uid then
    raise exception 'Smenani faqat qabul qiluvchi kassir — % — o''z hisobidan qabul qiladi', coalesce(v_h.names ->> v_h."toUid", v_h."toUid")
      using errcode = '42501', hint = 'kassa:handover_receiver';
  end if;
  if v_h.status = 'accepted' then
    return jsonb_build_object('ok', true, 'dup', true, 'handover', to_jsonb(v_h), 'count', (select to_jsonb(n) from public.cash_counts n where n.id = v_h."countId"),
                              'diff', v_h.diff, 'day', app.kassa_day_json(v_h."dayId"));
  end if;
  if v_h.status <> 'pending' then
    raise exception 'Smena topshirish bekor qilingan — topshiruvchi pulni qayta sanab, yangidan topshiradi' using errcode = 'P0001', hint = 'kassa:handover_state';
  end if;
  select * into v_d from public.cash_days d where d.id = v_h."dayId" for update;
  if v_d.status <> 'open' then raise exception 'Kassa kuni ochiq emas' using errcode = 'P0001', hint = 'kassa:no_open_day'; end if;
  v_exp := app.kassa_day_balance(v_d.id);
  if v_exp <> v_h.expected then
    raise exception 'Smena topshirilgandan keyin kassa qoldig''i o''zgargan (% → % so''m): topshirishni bekor qiling va pulni qayta sanang', trim_scale(v_h.expected), trim_scale(v_exp)
      using errcode = 'P0001', hint = 'kassa:handover_stale';
  end if;
  perform app.kassa_flag(true);
  select c.o_diff, c.o_doc_id, c.o_count_id into v_diff, v_doc_id, v_cnt_id
    from app.kassa_count_apply(v_h.desk, v_d.id, v_d.day, 'handover', v_h.counted, v_h."pendingSum", v_h.denoms, v_h.commission, v_h.note, v_uid,
                               v_h."fromUid", v_h."byUid", v_h."toUid", v_h.id) c;
  update public.cash_handovers set status = 'accepted', "acceptedAt" = clock_timestamp(), "countId" = v_cnt_id, "diffDocId" = v_doc_id
   where id = v_h.id returning * into v_h;
  -- g6v-1: qabul sanashi hammasini hisobga oldi (farq hujjati suratida — topshiruvchi davrining «boshqalar» ro'yxati): yangi kassa egasi toza boshlaydi
  update public.cash_days set "cashierUid" = v_h."toUid", "cashierName" = app.kassa_names(array[v_h."toUid"]) ->> v_h."toUid", "othersUids" = '{}'::text[]
   where id = v_d.id;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", at, reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_d.id, v_h.desk, v_d.day, 'handover', v_uid, clock_timestamp(), nullif(v_h.note, ''),
            jsonb_build_object('step', 'accept', 'handoverId', v_h.id, 'fromUid', v_h."fromUid", 'toUid', v_h."toUid", 'countedBy', v_h."byUid",
                               'expected', v_exp, 'counted', v_h.counted, 'pendingSum', v_h."pendingSum", 'diff', v_diff, 'diffDocId', v_doc_id, 'countId', v_cnt_id));
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', false, 'handover', to_jsonb(v_h), 'count', (select to_jsonb(n) from public.cash_counts n where n.id = v_cnt_id),
                            'diff', v_diff, 'diffDoc', case when v_doc_id is not null then app.kassa_doc_json(v_doc_id) end, 'day', app.kassa_day_json(v_d.id));
end $$;
revoke all on function public.kassa_handover_accept(text) from public, anon;
grant execute on function public.kassa_handover_accept(text) to authenticated;

-- Kutilayotgan smena topshirishni bekor qilish (state-6): topshiruvchi (kassa egasi yoki topshirishni yozgan xodim), qabul qiluvchi
--   («Rad etish» — summa mos emas va h.k.) yoki Direktor; sabab bilan. Kassa egasi o'zgarmaydi, hujjat yozilmaydi; kassa yana ishlaydi.
create or replace function public.kassa_handover_cancel(p_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text; v_h public.cash_handovers%rowtype; v_reason text := left(btrim(coalesce(p_reason, '')), 500); v_step text;
begin
  if not (app.kassa_operator() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: smena topshirishni topshiruvchi, qabul qiluvchi yoki Direktor bekor qiladi' using errcode = '42501';
  end if;
  if length(v_reason) < 3 then raise exception 'Sababini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  select h.desk into v_desk from public.cash_handovers h where h.id = p_id;
  if v_desk is null then raise exception 'Smena topshirish topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  perform app.kassa_lock_desk(v_desk);
  select * into v_h from public.cash_handovers h where h.id = p_id for update;
  if not (app.is_admin() or v_uid = v_h."byUid" or v_uid = v_h."toUid" or v_uid is not distinct from v_h."fromUid") then
    raise exception 'Kutilayotgan smena topshirishni topshiruvchi, qabul qiluvchi yoki Direktor bekor qiladi' using errcode = '42501', hint = 'kassa:handover_cancel';
  end if;
  if v_h.status = 'cancelled' then return jsonb_build_object('ok', true, 'dup', true, 'handover', to_jsonb(v_h)); end if;
  if v_h.status <> 'pending' then
    raise exception 'Smena allaqachon qabul qilingan — bekor qilinmaydi' using errcode = 'P0001', hint = 'kassa:handover_state';
  end if;
  v_step := case when v_uid = v_h."toUid" and v_uid <> v_h."byUid" and v_uid is distinct from v_h."fromUid" then 'reject' else 'cancel' end;
  perform app.kassa_flag(true);
  update public.cash_handovers set status = 'cancelled', "cancelledBy" = v_uid, "cancelledAt" = clock_timestamp(), "cancelReason" = v_reason
   where id = v_h.id returning * into v_h;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", at, reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_h."dayId", v_h.desk, v_h.day, 'handover', v_uid, clock_timestamp(), v_reason,
            jsonb_build_object('step', v_step, 'handoverId', v_h.id, 'fromUid', v_h."fromUid", 'toUid', v_h."toUid", 'counted', v_h.counted, 'diff', v_h.diff));
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', false, 'handover', to_jsonb(v_h));
end $$;
revoke all on function public.kassa_handover_cancel(text, text) from public, anon;
grant execute on function public.kassa_handover_cancel(text, text) to authenticated;

-- ---------- Kunni tekshirish (CT-05): 2-ro'yxat yoki Direktor; tekshiruvchi ≠ yopuvchi, ≠ shu kun hujjat o'tkazganlar ----------
--   crit-4: kunning nazorat ma'lumotini o'zgartirganlar ham tekshirmaydi — shu kun hujjatini bekor qilgan, shu kunning Z-hisobotini
--   kiritgan yoki tuzatgan (kassa_day_z; yopilgandan keyin ham, oldin ham), kunni qayta ochgan xodim, shu kungi smena topshirish-qabulida
--   qatnashgan xodim (state-6). Har holat o'z matni bilan (hint 'kassa:self_verify'); kunni boshqa 2-ro'yxat xodimi yoki Direktor tekshiradi.
--   Tekshirgan xodim ismi tekshirish paytidagi holatda muzlatiladi (sec-4).
create or replace function public.kassa_day_verify(p_desk text, p_day date, p_papers boolean, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_d public.cash_days%rowtype;
  v_prev date; v_gaps jsonb; v_rec numeric; v_pay numeric; v_z jsonb; v_self text;
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
  -- (qayta ochish sanash farqi hujjatini ham qayta ochgan nomidan bekor qiladi — avval shu holat tekshiriladi)
  v_self := case when v_d."closedBy" = v_uid then 'Kunni o''zingiz yopgansiz'
                 when exists (select 1 from public.cash_docs c where c."dayId" = v_d.id and c."postedBy" = v_uid) then 'Shu kuni o''zingiz hujjat o''tkazgansiz'
                 when exists (select 1 from public.cash_day_events e where e."dayId" = v_d.id and e.kind = 'reopen' and e."byUid" = v_uid)
                   then 'Kunni o''zingiz qayta ochgansiz'
                 when exists (select 1 from public.cash_docs c where c."dayId" = v_d.id and c."voidedBy" = v_uid) then 'Shu kunning hujjatini o''zingiz bekor qilgansiz'
                 when exists (select 1 from public.cash_day_events e where e."dayId" = v_d.id and e.kind = 'zreport' and e."byUid" = v_uid)
                   then 'Shu kunning Z-hisobotini o''zingiz kiritgansiz yoki tuzatgansiz'
                 -- state-6: shu kungi smena topshirish sanashida qatnashgan (topshirgan, sanagan yoki qabul qilgan) — o'z sanashini tekshirmaydi
                 when exists (select 1 from public.cash_handovers h where h."dayId" = v_d.id and h.status = 'accepted'
                                and v_uid in (h."byUid", h."toUid", coalesce(h."fromUid", '')))
                   then 'Shu kuni smena topshirish-qabulida qatnashgansiz' end;
  if v_self is not null then
    raise exception '% — kunni o''zingiz tekshira olmaysiz: uni boshqa 2-ro''yxat xodimi (Moliya menejeri / buxgalter) yoki Direktor tekshiradi', v_self
      using errcode = '42501', hint = 'kassa:self_verify';
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
  update public.cash_days set status = 'verified', "verifiedBy" = v_uid, "verifiedAt" = now(), "verifyNote" = left(btrim(coalesce(p_note, '')), 500),
         "verifiedByName" = app.kassa_names(array[v_uid]) ->> v_uid
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
  v_new := app.kassa_z_put(v_d.id, p -> 'z', v_uid, v_d.status = 'closed');   -- yopilgan kunda — «yopilgandan keyin» belgisi (crit-4)
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
  -- To'xtatilgan kassa yoki tayyorlangan qayta ishga tushirish (ishga-tushirish §9): oxirgi kun qayta ochilmaydi — qayta yopilsa kun oxiri
  --   o'zgarib, qayta ishga tushirish sanashi (farq dalolatnomasi) shu kun oxiridan hisoblangani bilan mos kelmay qolardi. Tuzatish —
  --   qayta ishga tushirish sanashida (farq dalolatnomasida) aks etadi.
  if exists (select 1 from public.cash_desks k where k.id = v_desk and not k."isTest" and (k."pausedAt" is not null or k."restartDay" > p_day)) then
    raise exception 'Kassa to''xtatilgan yoki qayta ishga tushirish tayyorlangan: % kassa kuni qayta ochilmaydi — farq qayta ishga tushirish sanashida (dalolatnomada) aks etadi (ishga-tushirish §9)',
      to_char(p_day, 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:reopen_paused';
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
         "closedByName" = null,
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
--   «Xodim zimmasiga» — FAQAT xodim kartasiga (sec-4; tomon 'employee', ism kartadan — HR yuritadi; foydalanuvchi o'zi o'zgartiradigan
--   users.name hech qachon). p_party — Direktor tanlagan javobgar xodim kartasi ('teachers:<id>' / 'staff:<id>'). Berilmasa — standart
--   javobgar (sec-2): faqat kassa egasi pulni o'zi sanagan va kassaga boshqa hech kim tegmagan bo'lsa (g6v-1), uning kartasi
--   (app.kassa_shortage_default); aks holda (kassir o'rniga sanalgan, kassa egasi yo'q, boshqa xodim ham kassa orderi bilan ishlagan yoki
--   kartaga bog'lanmagan) — rad (kassa:shortage_party; sababi — app.kassa_shortage_why, g6v-3): Direktor javobgarni o'zi tanlaydi.
drop function if exists public.kassa_shortage_decide(text, text, text);   -- avvalgi ta'rif (javobgar tanlovisiz)
create or replace function public.kassa_shortage_decide(p_doc_id text, p_decision text, p_note text default '', p_party text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text; v_doc public.cash_docs%rowtype; v_act text; v_ref text; v_snap jsonb;
  v_note text := left(btrim(coalesce(p_note, '')), 500); v_party jsonb; v_pick text := nullif(btrim(coalesce(p_party, '')), '');
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
    if v_doc.decision = p_decision and (p_decision <> 'employee' or v_pick is null
         or v_pick = (select a."partyId" from public.cash_docs a where a.id = v_doc."decisionDocId")) then
      return app.kassa_doc_json(p_doc_id) || jsonb_build_object('ok', true, 'dup', true);
    end if;
    raise exception 'Bu kamomad bo''yicha qaror allaqachon qabul qilingan' using errcode = 'P0001', hint = 'kassa:decided';
  end if;
  v_snap := coalesce(v_doc."sourceSnapshot", '{}'::jsonb);
  if p_decision = 'employee' then
    v_ref := coalesce(v_pick, app.kassa_shortage_default(v_snap));
    if v_ref is null then
      raise exception '%', coalesce(app.kassa_shortage_why(v_snap), 'Standart javobgar aniqlanmadi') || ' — javobgar xodim kartasini tanlang'
        using errcode = '22023', hint = 'kassa:shortage_party';
    end if;
    -- karta kassa_doc_build ichida tekshiriladi (app.kassa_party: 'teachers:<id>' / 'staff:<id>', mavjud bo'lishi shart); ism — kartadan
    v_party := jsonb_build_object('partyType', 'employee', 'partyId', v_ref);
  else
    v_party := jsonb_build_object('partyType', 'other', 'partyName', 'Kassa kamomadi (hisobdan chiqarildi)');
  end if;
  perform app.kassa_flag(true);
  select b.o_id into v_act from app.kassa_doc_build(v_party || jsonb_build_object(
      'desk', v_desk, 'op', 'nc_shortage_dec', 'amount', v_doc.amount, 'clientRef', 'shdec_' || p_doc_id,
      'basis', 'Direktor qarori: KO-2 № ' || v_doc.no || ', ' || to_char(v_doc."businessDay", 'DD.MM.YYYY'), 'note', v_note,
      'sourceTable', 'cash_docs', 'sourceId', p_doc_id,
      'sourceSnapshot', jsonb_strip_nulls(jsonb_build_object('cashierUid', v_snap ->> 'cashierUid', 'countedBy', v_snap ->> 'countedBy', 'kind', v_snap ->> 'kind',
                                                             'others', v_snap -> 'others',
                                                             'defaultParty', app.kassa_shortage_default(v_snap), 'picked', v_pick is not null)),
      'lines', jsonb_build_array(jsonb_build_object('debit', case when p_decision = 'employee' then '4730' else '9430' end, 'credit', '5910',
                                                    'amount', v_doc.amount, 'articleId', case when p_decision = 'employee' then 'OP-22' else 'EX-45' end))),
    'ACT', v_uid, true) b;
  perform app.kassa_act_post(v_act, v_uid, app.fin_today());
  update public.cash_docs set decision = p_decision, "decidedBy" = v_uid, "decidedAt" = now(), "decisionNote" = v_note, "decisionDocId" = v_act
   where id = p_doc_id;
  insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", reason, data)
    values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_doc."dayId", v_desk, v_doc."businessDay", 'decision', v_uid, v_note,
            jsonb_strip_nulls(jsonb_build_object('docId', p_doc_id, 'decision', p_decision, 'actId', v_act, 'amount', v_doc.amount,
                                                 'partyId', case when p_decision = 'employee' then v_ref end)));
  perform app.kassa_flag(false);
  return app.kassa_doc_json(p_doc_id) || jsonb_build_object('ok', true, 'dup', false, 'act', app.kassa_doc_json(v_act));
end $$;
revoke all on function public.kassa_shortage_decide(text, text, text, text) from public, anon;
grant execute on function public.kassa_shortage_decide(text, text, text, text) to authenticated;

-- ---------- O'qish: «Kassa» kun kartasi ----------
create or replace function public.kassa_state(p_desk text default 'main') returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_today date := app.fin_today();
  v_k public.cash_desks%rowtype; v_o public.fin_org%rowtype; v_open public.cash_days%rowtype; v_last public.cash_days%rowtype;
  v_block text; v_bal numeric; v_l2 boolean := app.fin_list2(); v_dir boolean := app.is_admin(); v_op boolean := app.kassa_operator();
  v_paused boolean; v_restart jsonb; v_per jsonb; v_cards text[] := app.kassa_user_cards(v_uid); v_ho public.cash_handovers%rowtype;
  -- 2-ro'yxat xodimlarining kartalari (faqat Direktorga): ularga beriladigan pulning 2-ro'yxat bosqichini Direktor imzolaydi (sec-1)
  v_l2cards text[] := case when app.is_admin() then array(select distinct x from public.users u cross join lateral unnest(app.kassa_user_cards(u.id)) x
                                                           where u.role in ('finance_mgr', 'accountant') order by 1) else '{}'::text[] end;
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  select * into v_k from public.cash_desks k where k.id = v_desk;
  if not found then raise exception 'Kassa topilmadi' using errcode = '22023', hint = 'kassa:bad_desk'; end if;
  select * into v_o from public.fin_org o where o.id = 'main';
  select * into v_open from public.cash_days d where d.desk = v_desk and d.status = 'open';
  select * into v_last from public.cash_days d where d.desk = v_desk and d.status <> 'open' order by d.day desc limit 1;
  v_bal := app.kassa_desk_balance(v_desk);
  v_per := app.kassa_periods(v_desk);
  v_ho := app.kassa_handover_pending(v_desk);   -- state-6: kutilayotgan smena topshirish (qabul qilinguncha hujjat yozilmaydi)
  -- To'xtatilgan kassa va tayyorlangan (hali boshlanmagan) qayta ishga tushirish (ishga-tushirish §9; ui-5); «stale» — sanashdan keyin
  --   kiritilgan, sanasi qayta ishga tushirish kunidan oldingi kassa hujjatisiz naqd yozuvlar (g4v-2: bo'lsa — qayta sanash kerak)
  v_paused := not v_k."isTest" and v_k."pausedAt" is not null;
  if v_open.id is null and v_last.id is not null and v_k."restartDay" > v_last.day then
    v_restart := jsonb_build_object('day', v_k."restartDay", 'amount', v_k."restartAmount", 'prevDay', v_last.day, 'prevClosing', v_last.closing,
                                    'delta', v_k."restartAmount" - v_last.closing, 'docId', v_k."restartDocId",
                                    'docNo', (select c.no from public.cash_docs c where c.id = v_k."restartDocId" and c.status = 'posted'),
                                    'countedAt', v_k."restartAt", 'stale', app.kassa_restart_stale(v_desk));
  end if;
  if v_open.id is not null then
    v_block := case when v_ho.id is not null then 'handover' when v_open.day < v_today then 'prev_open' when v_open.day > v_today then 'clock' end;
  else
    v_block := case when v_paused then 'paused'
                    when v_restart is not null and v_today < v_k."restartDay" then 'restart'
                    -- g4v-2: qayta ishga tushirish kuni keldi, lekin sanashdan keyin kassa hujjatisiz naqd yozuv bor — birinchi kun ochilmaydi
                    when v_restart is not null and coalesce((v_restart #>> '{stale,n}')::int, 0) > 0 then 'restart_recount'
                    when v_last.id is null and (v_k."startDay" is null or v_k."openingAmount" is null or v_today < v_k."startDay") then 'not_started'
                    when v_last.day = v_today then 'day_closed' when v_last.day > v_today then 'clock' end;
  end if;
  return jsonb_build_object(
    'desk', jsonb_build_object('id', v_k.id, 'name', v_k.name, 'isTest', v_k."isTest", 'active', v_k.active, 'startDay', v_k."startDay",
                               'openingAmount', v_k."openingAmount", 'started', exists (select 1 from public.cash_days d where d.desk = v_desk),
                               'pausedAt', case when v_paused then v_k."pausedAt" end,
                               'pausedDay', case when v_paused then (v_k."pausedAt" at time zone 'Asia/Tashkent')::date end,
                               'restart', v_restart,
                               -- kassa ishlamagan kunlar (g4v-1; app.kassa_pre_day bilan bir xil): birinchi ishga tushgan kundan oldin va
                               --   to'xtatilgan davrlar (after < kun < before) — Direktorning kassa hujjatisiz naqd yozuv oynalari shundan
                               'firstDay', v_per -> 'first', 'gaps', coalesce(v_per -> 'gaps', '[]'::jsonb)),
    'today', v_today, 'now', app.fin_now(),
    'openDay', case when v_open.id is not null then app.kassa_day_json(v_open.id) end,
    'lastDay', case when v_last.id is not null then app.kassa_day_json(v_last.id) end,
    -- state-6: kutilayotgan smena topshirish — qabul qiluvchiga «Smenani qabul qilish», topshiruvchi va Direktorga «Bekor qilish»
    'handover', case when v_ho.id is not null then to_jsonb(v_ho) end,
    'balance', v_bal,
    'canPost', v_block is null, 'blockReason', v_block,
    'pending', jsonb_build_object(
      -- sec-1: o'z kartasiga beriladigan pulni boshqa 2-ro'yxat xodimi tasdiqlaydi — bu xodimning navbatida yo'q; 2-ro'yxat xodimiga
      --   beriladigan pulning 2-ro'yxat bosqichi — Direktor navbatida ham (kassa_doc_approve)
      'toApprove', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'draft'
                      and ((v_l2 and c."needsList2" and c."approvedBy" is null and c."requestedBy" is distinct from v_uid
                            and not (c."partyType" = 'employee' and c."partyId" = any(v_cards)))
                        or (v_dir and c."needsDirector" and c."dirApprovedBy" is null)
                        or (v_dir and c."needsList2" and c."approvedBy" is null and c."requestedBy" is distinct from v_uid
                            and c."partyType" = 'employee' and c."partyId" = any(v_l2cards)))),
      'waiting', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'draft'),
      'toPay', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'approved'),
      'toPaySum', (select coalesce(sum(c.amount), 0) from public.cash_docs c where c.desk = v_desk and c.status = 'approved' and c.form = 'KO2'),
      -- CT-26: Direktor tasdiqlagan qaytarish 1 kundan ortiq berilmay turibdi
      'refundsLate', (select count(*) from public.cash_docs c where c.desk = v_desk and c.op = 'out_refund' and c.status = 'approved'
                        and c."dirApprovedAt" < app.fin_now() - interval '1 day')),
    'unverifiedDays', (select count(*) from public.cash_days d where d.desk = v_desk and d.status = 'closed'),
    'undecidedShortages', (select count(*) from public.cash_docs c where c.desk = v_desk and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null),
    'accOverdue', app.kassa_acc_overdue(v_desk, v_today),   -- eslatma (F1.24): avans hisoboti muddati o'tgan hisobdorlar
    'limit', jsonb_build_object('cashLimit', v_o."cashLimit", 'set', v_o."cashLimit" > 0, 'exceeded', v_o."cashLimit" > 0 and coalesce(v_bal, 0) > v_o."cashLimit"),
    't1', v_o.t1, 'l1', v_o.l1, 'kassaGoLive', v_o."kassaGoLive", 'printLang', v_o."printLang", 'lockedThrough', v_o."lockedThrough",
    'counters', (select coalesce(jsonb_object_agg(k.series, k."lastNo"), '{}'::jsonb) from public.doc_counters k
                  where k.desk = v_desk and k.year = extract(year from v_today)::int),
    -- kindConfirm — kontragent turini tasdiqlay oladi (buxgalter, Direktor; sec-3); cards — bog'langan xodim kartalari (sec-1: o'ziga beriladigan
    --   pulni tasdiqlamaydi — sahifa tugmani ko'rsatmaydi, server ham rad etadi); l2Cards — Direktorga: 2-ro'yxat xodimlarining kartalari
    --   (ularga beriladigan pulning 2-ro'yxat bosqichini Direktor imzolaydi)
    'me', jsonb_build_object('uid', v_uid, 'operator', v_op, 'list2', v_l2, 'director', v_dir, 'kindConfirm', v_dir or app.is_accountant(),
                             'cards', to_jsonb(v_cards), 'l2Cards', to_jsonb(v_l2cards)),
    'accRead', app.acc_read(),   -- F1.21: buxgalterning «To‘lovlar» / «Buxgalteriya» bo'limlari (fin-rights.sql «fin_rights_on»)
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
      select unnest(array[n."byUid", n."fromUid", n."toUid", n."cashierUid"]) from public.cash_counts n where n."dayId" = v_id
      union all
      select unnest(array[h."byUid", h."fromUid", h."toUid", h."cancelledBy"]) from public.cash_handovers h where h."dayId" = v_id
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
    -- smena topshirishlar (state-6): kutilayotgan, qabul qilingan, bekor qilingan / rad etilgan — kun varag'i va kamomad qarori uchun
    'handovers', coalesce((select jsonb_agg(to_jsonb(h) order by h."createdAt", h.id) from public.cash_handovers h where h."dayId" = v_id), '[]'::jsonb),
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

-- Davr boshidagi va oxiridagi kassa qoldig'i — KO-3 va RP-08 uchun bitta qoida: boshi — davrdagi birinchi kassa kunining boshi;
--   kun bo'lmasa — oldingi oxirgi kun oxiri; u ham bo'lmasa — boshlang'ich qoldiq (birinchi kassa kuni davr oxirigacha bo'lsa).
--   Oxiri — davrdagi (yoki undan oldingi) oxirgi kun oxiri (ochiq kunda — joriy qoldiq).
--   Qayta ishga tushirish (ishga-tushirish §9): o_ref — boshi olingan kun; o_adj — o_ref dan davr oxirigacha bo'lgan qayta ishga tushirish
--   dalolatnomalari farqi (oxiriga ham qo'shiladi: kun ochilmagan bo'lsa ham hisob qoldig'i — sanalgan summa). Davr uchun: boshi + kirim −
--   chiqim + o_adj = oxiri. OUT parametrlar o'zgargani uchun avvalgi ta'rif o'chiriladi (chaqiruvchilar — kassa_journal, kassa_matrix).
drop function if exists app.kassa_period_bal(text, date, date);
create or replace function app.kassa_period_bal(p_desk text, p_from date, p_to date, out o_open numeric, out o_close numeric, out o_adj numeric, out o_ref date)
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_k public.cash_desks%rowtype; v_cday date;
begin
  select * into v_k from public.cash_desks k where k.id = p_desk;
  select d.opening, d.day into o_open, o_ref from public.cash_days d where d.desk = p_desk and d.day between p_from and p_to order by d.day limit 1;
  if o_open is null then
    select case when d.status = 'open' then app.kassa_day_balance(d.id) else d.closing end, d.day into o_open, o_ref
      from public.cash_days d where d.desk = p_desk and d.day < p_from order by d.day desc limit 1;
  end if;
  if o_open is null then
    o_open := case when v_k."startDay" is not null and v_k."startDay" <= p_to then coalesce(v_k."openingAmount", 0) else 0 end;
    o_ref := p_from - 1;
  end if;
  select case when d.status = 'open' then app.kassa_day_balance(d.id) else d.closing end, d.day into o_close, v_cday
    from public.cash_days d where d.desk = p_desk and d.day <= p_to order by d.day desc limit 1;
  o_close := coalesce(o_close, o_open) + app.kassa_restart_adj(p_desk, coalesce(v_cday, o_ref), p_to);
  o_adj := app.kassa_restart_adj(p_desk, o_ref, p_to);
end $$;
revoke all on function app.kassa_period_bal(text, date, date) from public, anon, authenticated;

-- ---------- O'qish: KO-3 — kirim va chiqim kassa hujjatlarini ro'yxatga olish jurnali (F1.22, buxgalter ko'rigi M4) ----------
--   Davr (≤ 93 kun: oy yoki chorak) bo'yicha barcha kirim va chiqim orderlari — o'tkazilgan va bekor qilingan (raqami saqlanadi),
--   jamlar (faqat o'tkazilgan), davr boshi va oxiridagi qoldiq va ularning mosligi (boshi + kirim − chiqim = oxiri), har shakl
--   bo'yicha davrdagi birinchi / oxirgi raqam. Chop etish (KO-3) va XLSX — sahifada (fin-print.js: journalHtml, journalSheet).
create or replace function public.kassa_journal(p_desk text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_k public.cash_desks%rowtype;
  v_open numeric; v_close numeric; v_adj numeric; v_t jsonb;
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
  select b.o_open, b.o_close, b.o_adj into v_open, v_close, v_adj from app.kassa_period_bal(v_desk, p_from, p_to) b;
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
    'restartAdj', v_adj,   -- qayta ishga tushirish farqi (texnik dalolatnoma, kassa kitobidan tashqari): boshi + kirim − chiqim + farq = oxiri
    'balanced', v_open + (v_t ->> 'in')::numeric - (v_t ->> 'out')::numeric + v_adj = v_close,
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

-- ---------- O'qish: RP-08 — oylik statiya matritsasi (kassa) (F1.22) ----------
--   Oy bo'yicha kassadagi naqd harakat statiyalar kesimida: qator — (shakl, statiya), ustun — oy kunlari. Manba — o'tkazilgan KO-1 /
--   KO-2 ning naqd qatorlari (KO-4 va kunlik hisobot bilan bir manba). Ichki o'tkazma (bank 5110 / yo'ldagi pul 5710 — kunlik
--   hisobotdagi qoida) belgilanadi: daromad ham, xarajat ham emas. Kunlar bo'yicha jami kirim / chiqim va qoldiq; oy boshi + kirim −
--   chiqim = oy oxiri (KO-3 bilan bir qoida). Chop etish (haftalar bo'yicha) va XLSX (kunlar bo'yicha) — sahifada (fin-print.js).
create or replace function public.kassa_matrix(p_desk text, p_month text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_k public.cash_desks%rowtype;
  v_from date; v_to date; v_n int; v_open numeric; v_close numeric; v_adj numeric; v_ref date; v_rows jsonb; v_t jsonb;
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  if coalesce(p_month, '') !~ '^20\d{2}-(0[1-9]|1[0-2])$' then
    raise exception 'Oy noto''g''ri (YYYY-MM)' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  select * into v_k from public.cash_desks k where k.id = v_desk;
  if not found then raise exception 'Kassa topilmadi' using errcode = '22023', hint = 'kassa:bad_desk'; end if;
  v_from := to_date(p_month || '-01', 'YYYY-MM-DD'); v_to := (v_from + interval '1 month')::date - 1; v_n := v_to - v_from + 1;
  select b.o_open, b.o_close, b.o_adj, b.o_ref into v_open, v_close, v_adj, v_ref from app.kassa_period_bal(v_desk, v_from, v_to) b;
  with l as (
         select c.form, coalesce(l."articleId", '') as art, c."businessDay" as d, sum(l.amount) as amount,
                bool_or((case when c.form = 'KO1' then l.credit else l.debit end) in ('5110', '5710')) as transfer
           from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id
          where c.desk = v_desk and c.status = 'posted' and c.form in ('KO1', 'KO2') and l.cash
            and c."businessDay" between v_from and v_to
          group by 1, 2, 3),
       g as (select i, v_from + i as d from generate_series(0, v_n - 1) i),
       k as (select form, art, bool_or(transfer) as transfer from l group by form, art),
       m as (select k.form, k.art, k.transfer, jsonb_agg(coalesce(l.amount, 0) order by g.i) as byday, coalesce(sum(l.amount), 0) as total
               from k cross join g left join l on l.form = k.form and l.art = k.art and l.d = g.d
              group by k.form, k.art, k.transfer)
  select coalesce(jsonb_agg(jsonb_build_object('form', m.form, 'articleId', nullif(m.art, ''), 'kind', a.kind, 'nameUz', a."nameUz",
                                               'nameRu', a."nameRu", 'transfer', m.transfer, 'byDay', m.byday, 'total', m.total)
                            order by m.form, coalesce(a."sortOrder", 9999), m.art), '[]'::jsonb)
    into v_rows
    from m left join public.fin_articles a on a.id = m.art;
  with t as (
         select c."businessDay" as d, c.form, sum(l.amount) as s,
                sum(l.amount) filter (where (case when c.form = 'KO1' then l.credit else l.debit end) in ('5110', '5710')) as tr
           from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id
          where c.desk = v_desk and c.status = 'posted' and c.form in ('KO1', 'KO2') and l.cash
            and c."businessDay" between v_from and v_to
          group by 1, 2),
       x as (select g.i, coalesce(i.s, 0) as din, coalesce(o.s, 0) as dout, coalesce(i.tr, 0) as trin, coalesce(o.tr, 0) as trout
               from generate_series(0, v_n - 1) g(i)
               left join t i on i.d = v_from + g.i and i.form = 'KO1'
               left join t o on o.d = v_from + g.i and o.form = 'KO2')
  select jsonb_build_object('dayIn', jsonb_agg(y.din order by y.i), 'dayOut', jsonb_agg(y.dout order by y.i),
                            -- kun oxiri qoldig'i: qayta ishga tushirish farqi o'z kunidan qo'shiladi (ishga-tushirish §9)
                            'dayBal', jsonb_agg(v_open + y.cum + case when v_adj <> 0 then app.kassa_restart_adj(v_desk, v_ref, v_from + y.i) else 0 end order by y.i),
                            'in', sum(y.din), 'out', sum(y.dout), 'transferIn', sum(y.trin), 'transferOut', sum(y.trout))
    into v_t
    from (select x.*, sum(x.din - x.dout) over (order by x.i) as cum from x) y;
  return jsonb_build_object('ok', true, 'month', p_month, 'from', v_from, 'to', v_to, 'nDays', v_n,
    'desk', jsonb_build_object('id', v_k.id, 'name', v_k.name, 'isTest', v_k."isTest"),
    'opening', v_open, 'closing', v_close, 'restartAdj', v_adj,
    'balanced', v_open + (v_t ->> 'in')::numeric - (v_t ->> 'out')::numeric + v_adj = v_close,
    'rows', v_rows,
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', d.day, 'status', d.status,
                                                          'closing', case when d.status = 'open' then app.kassa_day_balance(d.id) else d.closing end)
                                       order by d.day)
                        from public.cash_days d where d.desk = v_desk and d.day between v_from and v_to), '[]'::jsonb))
    || v_t;
end $$;
revoke all on function public.kassa_matrix(text, text) from public, anon;
grant execute on function public.kassa_matrix(text, text) to authenticated;

-- ---------- O'qish: buxgalter uchun oylik kassa to'plami (F1.22; E1–E4 — eksport to'plamining kassa qismi) ----------
--   Bitta javob — bitta XLSX kitob: E1 KO-3 (kassa_journal_export, FD-28), E2 statiya matritsasi (kassa_matrix), E3 kassa kunlari
--   (KO-4 jamlari, sanash va farq — yopishdagi va smena topshirishdagi (acc-6), tekshirilganmi, Z-hisobot), E4 hisobdorlar (oy boshi,
--   berildi, qaytdi, hisobot, oy oxiri).
--   Moliya menejeri / buxgalter va Direktor; 2-ro'yxatga ismsiz (xodim — tabel kodi bilan), Direktorga to'liq. Kassir — yo'q.
create or replace function public.kassa_month_pack(p_desk text, p_month text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_dir boolean := app.is_admin(); v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main');
  v_m jsonb; v_from date; v_to date; v_test boolean;
begin
  if not (v_dir or app.fin_list2()) then
    raise exception 'Ruxsat yo''q: oylik kassa to''plami — Moliya menejeri, buxgalter yoki Direktor (kassir hisobotlarni chop etadi)' using errcode = '42501';
  end if;
  v_m := public.kassa_matrix(v_desk, p_month);      -- oy va kassa shu yerda tekshiriladi
  v_from := (v_m ->> 'from')::date; v_to := (v_m ->> 'to')::date; v_test := coalesce((v_m -> 'desk' ->> 'isTest')::boolean, false);
  return jsonb_build_object('ok', true, 'month', p_month, 'from', v_from, 'to', v_to, 'masked', not v_dir, 'desk', v_m -> 'desk',
    'journal', public.kassa_journal_export(v_desk, v_from, v_to),
    'matrix', v_m,
    'days', coalesce((select jsonb_agg(jsonb_build_object(
                                 'day', d.day, 'status', d.status, 'opening', d.opening,
                                 'receipts', coalesce(d.receipts, (j ->> 'receiptsLive')::numeric), 'payouts', coalesce(d.payouts, (j ->> 'payoutsLive')::numeric),
                                 'closing', coalesce(d.closing, (j ->> 'balance')::numeric), 'counted', d.counted, 'diff', d.diff,
                                 'handoverDiff', (j ->> 'handoverDiff')::numeric,   -- acc-6: smena topshirishdagi farq (E3 da yopish farqi yonida)
                                 'docs', (j ->> 'docs')::int, 'voids', (j ->> 'voids')::int, 'reopens', d."reopenCount",
                                 'z', case when coalesce((j -> 'z' ->> 'applies')::boolean, false)
                                           then jsonb_strip_nulls(jsonb_build_object('needed', j -> 'z' -> 'needed', 'recorded', j -> 'z' -> 'recorded',
                                                  'missing', j -> 'z' -> 'missing', 'reason', j -> 'z' -> 'reason', 'no', j -> 'z' -> 'no',
                                                  'cash', j -> 'z' -> 'cash', 'card', j -> 'z' -> 'card', 'expCash', j -> 'z' -> 'expCash',
                                                  'expCard', j -> 'z' -> 'expCard', 'diffCash', j -> 'z' -> 'diffCash', 'diffCard', j -> 'z' -> 'diffCard',
                                                  'ok', j -> 'z' -> 'ok')) end)
                               order by d.day)
                        from public.cash_days d cross join lateral (select app.kassa_day_json(d.id) as j) jj
                       where d.desk = v_desk and d.day between v_from and v_to), '[]'::jsonb),
    'advances', coalesce((select jsonb_agg(jsonb_build_object(
                                 'code', app.kassa_mask_party('employee', a.pid, null, false) ->> 'partyId',
                                 'partyName', case when v_dir then app.kassa_party_label('employee', a.pid) end,
                                 'opening', a.op, 'issued', a.iss, 'returned', a.ret, 'reported', a.rep, 'closing', a.op + a.iss - a.ret - a.rep)
                               order by app.kassa_mask_party('employee', a.pid, null, false) ->> 'partyId', a.pid)
                            from (select c."partyId" as pid,
                                         coalesce(sum(case when c.op = 'out_accountable' then c.amount else -c.amount end) filter (where c."businessDay" < v_from), 0) as op,
                                         coalesce(sum(c.amount) filter (where c.op = 'out_accountable' and c."businessDay" >= v_from), 0) as iss,
                                         coalesce(sum(c.amount) filter (where c.op = 'in_acc_return' and c."businessDay" >= v_from), 0) as ret,
                                         coalesce(sum(c.amount) filter (where c.op = 'nc_adv_report' and c."businessDay" >= v_from), 0) as rep
                                    from public.cash_docs c
                                   where c."partyType" = 'employee' and c.status = 'posted' and c."businessDay" <= v_to
                                     and c.op in ('out_accountable', 'in_acc_return', 'nc_adv_report')
                                     and case when v_test then c.desk = v_desk
                                              else not exists (select 1 from public.cash_desks k where k.id = c.desk and k."isTest") end
                                   group by c."partyId") a
                           where a.op <> 0 or a.iss <> 0 or a.ret <> 0 or a.rep <> 0), '[]'::jsonb));
end $$;
revoke all on function public.kassa_month_pack(text, text) from public, anon;
grant execute on function public.kassa_month_pack(text, text) to authenticated;

-- Hisobdorlardagi pul (4230) p_asof sanasi holatiga: berilgan − naqd qaytarilgan − avans hisobotlari; "since" — hali yopilmagan
--   eng eski berilgan sana (FIFO); "workDays" — o'shandan p_asof gacha o'tgan ish kunlari (du–ju); hisobot muddati — 3 ish kuni (§4.9).
--   Manfiy qoldiq (qaytim yoki hisobot berilgan avansdan ko'p, avanssiz qaytim ham — xato yozuv izi; acc-3, state-5) yashirilmaydi:
--   "negative" belgisi bilan (muddat hisoblanmaydi) — nazorat ro'yxatida qizil.
create or replace function app.kassa_accountables(p_desk text, p_asof date) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  with g as (select c."partyId" as pid, c."partyName" as nm, c."businessDay" as d,
                    sum(c.amount) over (partition by c."partyId" order by c."businessDay", c."postedAt", c.id) as cum
               from public.cash_docs c where c.desk = p_desk and c.op = 'out_accountable' and c.status = 'posted' and c."businessDay" <= p_asof),
       r as (select c."partyId" as pid, max(c."partyName") as nm, coalesce(sum(c.amount) filter (where c.op = 'in_acc_return'), 0) as ret,
                    coalesce(sum(c.amount) filter (where c.op = 'nc_adv_report'), 0) as rep
               from public.cash_docs c
              where c.desk = p_desk and c.op in ('in_acc_return', 'nc_adv_report') and c.status = 'posted' and c."businessDay" <= p_asof
              group by 1),
       o as (select coalesce(gg.pid, r.pid) as pid, coalesce(gg.nm, r.nm) as nm, coalesce(gg.given, 0) as given,
                    coalesce(r.ret, 0) as ret, coalesce(r.rep, 0) as rep,
                    (select min(g.d) from g where g.pid = gg.pid and g.cum > coalesce(r.ret, 0) + coalesce(r.rep, 0)) as since
               from (select g.pid, max(g.nm) as nm, max(g.cum) as given from g group by g.pid) gg
               full join r on r.pid = gg.pid)
  select coalesce((select jsonb_agg(jsonb_build_object('partyId', o.pid, 'name', coalesce(app.kassa_party_label('employee', o.pid), o.nm, ''),
                                                       'given', o.given, 'returned', o.ret, 'reported', o.rep, 'balance', o.given - o.ret - o.rep, 'since', o.since,
                                                       'workDays', (select count(*) from generate_series(o.since + 1, p_asof, interval '1 day') g
                                                                     where extract(isodow from g) < 6),
                                                       'overdue', (select count(*) from generate_series(o.since + 1, p_asof, interval '1 day') g
                                                                    where extract(isodow from g) < 6) > 3,
                                                       'negative', o.given - o.ret - o.rep < 0)
                                    order by o.since, o.pid)
                     from o where o.given - o.ret - o.rep <> 0), '[]'::jsonb)
$$;
revoke all on function app.kassa_accountables(text, date) from public, anon, authenticated;

-- Muddati o'tgan avans hisobotlari soni va summasi (eslatmalar — F1.24: «Kassa» sahifasi va Telegram nazorat qatori).
create or replace function app.kassa_acc_overdue(p_desk text, p_asof date) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select jsonb_build_object('n', count(*), 'sum', coalesce(sum((x ->> 'balance')::numeric), 0))
    from jsonb_array_elements(app.kassa_accountables(p_desk, p_asof)) x where (x ->> 'overdue')::boolean
$$;
revoke all on function app.kassa_acc_overdue(text, date) from public, anon, authenticated;

-- RP-22 haftalik KPI (F1.25) davr bo'yicha: kassa kunlari (yopilgan, o'z vaqtida — o'sha kuni yopilgan, tekshirilgan / tekshirilmagan,
--   qayta ochilgan), sanash farqlari (kunlar, kamomad, ortiqcha), bekor qilingan hujjatlar, «Boshqa xarajatlar» (EX-49) ulushi —
--   davrdagi naqd xarajat (EX statiyalari) ichida, davr oxirida muddati o'tgan avans hisobotlari.
--   acc-6: sanash farqi = kunni yopishdagi (cash_days.diff) va smena topshirishdagi (qabul qilingan topshirishlar sanashi, cash_counts)
--   farqlar; har sanash alohida (kamomad va ortiqcha bir-birini «yopmaydi»); "handoverDiffs" — shundan smena topshirishdagi farqlar soni.
create or replace function app.kassa_week_kpi(p_desk text, p_from date, p_to date) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select jsonb_build_object('from', p_from, 'to', p_to) || d.j || e.j || jsonb_build_object('voids', v.n) || jsonb_build_object('accOverdue', app.kassa_acc_overdue(p_desk, p_to))
    from (select jsonb_build_object(
                   'days', count(*), 'closed', count(*) filter (where x.status <> 'open'),
                   'onTime', count(*) filter (where x.status <> 'open' and (x."closedAt" at time zone 'Asia/Tashkent')::date <= x.day),
                   'verified', count(*) filter (where x.status = 'verified'), 'unverified', count(*) filter (where x.status = 'closed'),
                   'reopened', count(*) filter (where x."reopenCount" > 0),
                   'diffDays', count(*) filter (where coalesce(x.diff, 0) <> 0 or h.n > 0),
                   'shortage', coalesce(sum(-x.diff) filter (where x.diff < 0), 0) + coalesce(sum(h.short), 0),
                   'surplus', coalesce(sum(x.diff) filter (where x.diff > 0), 0) + coalesce(sum(h.over), 0),
                   'handoverDiffs', coalesce(sum(h.n), 0)) as j
            from public.cash_days x
            cross join lateral (select count(*) filter (where n.diff <> 0) as n, sum(-n.diff) filter (where n.diff < 0) as short,
                                       sum(n.diff) filter (where n.diff > 0) as over
                                  from public.cash_counts n where n."dayId" = x.id and n.kind = 'handover') h
           where x.desk = p_desk and x.day between p_from and p_to) d,
         (select jsonb_build_object('exTotal', coalesce(sum(l.amount), 0), 'ex49', coalesce(sum(l.amount) filter (where l."articleId" = 'EX-49'), 0),
                                    'ex49Share', case when coalesce(sum(l.amount), 0) > 0
                                                      then round(100 * coalesce(sum(l.amount) filter (where l."articleId" = 'EX-49'), 0) / sum(l.amount), 1) end) as j
            from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id join public.fin_articles a on a.id = l."articleId"
           where c.desk = p_desk and c.status = 'posted' and c.form = 'KO2' and l.cash and a.kind = 'EX' and c."businessDay" between p_from and p_to) e,
         (select count(*) as n from public.cash_docs c where c.desk = p_desk and c.status = 'void' and c."businessDay" between p_from and p_to) v
$$;
revoke all on function app.kassa_week_kpi(text, date, date) from public, anon, authenticated;

-- O'qish: RP-22 haftalik KPI — oxirgi N hafta (du–ya; joriy hafta — bugungacha). Direktor va 2-ro'yxat ko'radi.
create or replace function public.kassa_kpi(p_desk text, p_weeks int default 8) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_k public.cash_desks%rowtype; v_today date := app.fin_today();
  v_n int := least(greatest(coalesce(p_weeks, 8), 1), 26); v_mon date;
begin
  if not (app.is_admin() or app.fin_list2()) then raise exception 'Ruxsat yo''q: haftalik ko''rsatkichlar — Direktor, Moliya menejeri yoki buxgalter' using errcode = '42501'; end if;
  select * into v_k from public.cash_desks k where k.id = v_desk;
  if not found then raise exception 'Kassa topilmadi' using errcode = '22023', hint = 'kassa:bad_desk'; end if;
  v_mon := v_today - (extract(isodow from v_today)::int - 1);
  return jsonb_build_object('ok', true, 'today', v_today, 'desk', jsonb_build_object('id', v_k.id, 'name', v_k.name, 'isTest', v_k."isTest"),
    'weeks', (select jsonb_agg(app.kassa_week_kpi(v_desk, w.m, least(w.m + 6, v_today)) order by w.m desc)
                from (select v_mon - 7 * i as m from generate_series(0, v_n - 1) i) w));
end $$;
revoke all on function public.kassa_kpi(text, int) from public, anon;
grant execute on function public.kassa_kpi(text, int) to authenticated;

-- ---------- O'qish: nazorat ro'yxati (RP-06) ----------
--   Faktlar (baho va matn — mijozda): raqam bo'shliqlari, yopilmagan / tekshirilmagan kunlar, qarorsiz kamomad, sanash farqlari,
--   bekor qilish va qayta ochishlar, tasdiq kutayotgan va berilmagan so'rovlar, eski qaytarishlar, fiskal cheksiz kirimlar, «boshqa»
--   tomonlar, kech (oflayn) yozuvlar, asl nusxani qayta chiqarish, darvozasiz naqd maosh, KO-4 chop etilmagan kunlar, limit,
--   moslik (P1/P4/P5/P8), hisobdorlardagi pul (4230) muddati va manfiy qoldiq, xodimlar zimmasidagi kamomad (4730),
--   rahbar / ta'sischiga berilgan pul (4290 / 4890), onlayn kassa Z-hisoboti (tekshirilmagan kunlarda kiritilmagan / mos emas; kun
--   yopilgandan keyin o'zgartirilgani — crit-4), kontragent turi o'zgarishlari va tasdiqlanmagan turlar (sec-3),
--   kassa ishga tushishidan oldingi sanali, keyin kiritilgan naqd yozuvlar (crit-1), kassani to'xtatish va qayta ishga tushirish (§9),
--   xodim kartasiga bog'lanmagan kassa hisoblari (sec-4); sanash farqlari smena topshirishdagilari bilan (acc-6).
create or replace function public.kassa_checks(p_desk text default 'main') returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_today date := app.fin_today(); v_limit numeric; v_bal numeric;
  v_test boolean; v_m0 date := date_trunc('month', app.fin_today())::date; v_first date; v_skip tstzrange[]; v_restarts jsonb := '[]'::jsonb;
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  v_test := coalesce((select k."isTest" from public.cash_desks k where k.id = v_desk), false);
  select o."cashLimit" into v_limit from public.fin_org o where o.id = 'main';
  v_bal := coalesce(app.kassa_desk_balance(v_desk), 0);
  -- birinchi ishga tushgan kun (app.kassa_periods; kassa to'xtatilib qayta ishga tushirilgan bo'lsa ham — birinchisi)
  v_first := (app.kassa_periods('main') ->> 'first')::date;
  -- Kassani to'xtatish va qayta ishga tushirishlar (ishga-tushirish §9): har to'xtatish uchun oxirgi sanash (qayta sanalganlari o'rniga) —
  --   oxirgi kun oxiri, komissiya sanagan summa, farq dalolatnomasi va to'xtatilgan davrdagi kassa hujjatisiz naqd harakat.
  --   Har yozuv bitta joyda: «rows» — sanasi to'xtatilgan davrda (oxirgi kassa kunidan KEYIN, qayta ishga tushirish kunidan oldin — kassa
  --   ishlamagan kunlar, app.kassa_pre_day), qachon kiritilganidan qat'i nazar (keyin Direktor kiritgan kechikkan qog'oz ham — farqni
  --   tushuntiradi), keyingi to'xtatilgan davrlar oynasida kiritilganlaridan tashqari; oxirgi kassa kuni va undan oldingi kassa kunlari
  --   sanali hujjatisiz yozuv — moslikda (g4v-4: kassa ishlagan barcha davrlar); «backdated» — shu to'xtatilgan davr oynasida
  --   (to'xtatilgandan qayta ishga tushirish kunigacha) kiritilgan, sanasi oxirgi kassa kuni yoki undan oldingi (g4r-2: endi bunday yozuv
  --   qabul qilinmaydi — ro'yxat himoya chizig'i bo'lib qoladi, yangi yozuvlar uchun bo'sh). v_skip — barcha to'xtatilgan davr oynalari:
  --   «preLive» ularda kiritilgan yozuvni sanamaydi (u «backdated» da).
  if not v_test then
    with ev as (select distinct on (y.data ->> 'prevDay') y.day, (y.data ->> 'prevDay')::date as prev_day, (y.data ->> 'prevClosing')::numeric as prev_closing,
                       (y.data ->> 'amount')::numeric as counted, (y.data ->> 'delta')::numeric as delta, (y.data ->> 'pausedFrom')::timestamptz as paused_from,
                       y.data ->> 'docId' as doc_id
                  from public.cash_day_events y
                 where y.desk = v_desk and y.kind = 'opening' and y.data ->> 'restart' = 'true'
                 order by y.data ->> 'prevDay', y.at desc, y.id desc),
         r as (select e.*, (select c.no from public.cash_docs c where c.id = e.doc_id and c.status = 'posted') as doc_no,
                      exists (select 1 from public.cash_days d where d.desk = v_desk and d.day >= e.day) as started,
                      app.kassa_cash_rows(e.prev_day + 1, e.day - 1, null, null,
                                          (select array_agg(tstzrange(w.paused_from, w.day::timestamp at time zone 'Asia/Tashkent', '[)')) from ev w
                                            where w.prev_day > e.prev_day and w.paused_from is not null)) as rows,
                      case when e.paused_from is not null
                           then app.kassa_cash_rows(e.prev_day - 400, e.prev_day, e.paused_from, e.day::timestamp at time zone 'Asia/Tashkent') end as back
                 from ev e where e.day >= v_today - 400)
    select coalesce((select jsonb_agg(jsonb_build_object('startDay', r.day, 'prevDay', r.prev_day, 'prevClosing', r.prev_closing,
                                                         'counted', r.counted, 'delta', r.delta, 'docNo', r.doc_no, 'started', r.started,
                                                         'rows', r.rows, 'backdated', r.back,
                                                         'unexplained', r.delta - ((r.rows ->> 'in')::numeric - (r.rows ->> 'out')::numeric)
                                                                        - coalesce((r.back ->> 'in')::numeric - (r.back ->> 'out')::numeric, 0))
                                      order by r.day desc) from r), '[]'::jsonb),
           (select array_agg(tstzrange(w.paused_from, w.day::timestamp at time zone 'Asia/Tashkent', '[)')) from ev w where w.paused_from is not null)
      into v_restarts, v_skip;
  end if;
  return jsonb_build_object('ok', true, 'today', v_today, 'isTest', v_test,
    'gaps', (select coalesce(jsonb_agg(jsonb_build_object('year', y.year, 'problems', y.g)), '[]'::jsonb)
               from (select k.year, app.kassa_gap_check(v_desk, k.year) as g from (select distinct year from public.doc_counters where desk = v_desk) k) y
              where jsonb_array_length(y.g) > 0),
    'staleOpenDay', (select d.day from public.cash_days d where d.desk = v_desk and d.status = 'open' and d.day < v_today),
    'unverifiedDays', coalesce((select jsonb_agg(d.day order by d.day) from public.cash_days d where d.desk = v_desk and d.status = 'closed'), '[]'::jsonb),
    'undecidedShortages', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'no', c.no, 'day', c."businessDay", 'amount', c.amount) order by c."businessDay")
                                      from public.cash_docs c where c.desk = v_desk and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null), '[]'::jsonb),
    -- sanash farqlari (acc-6): kunni yopishdagi ("diff"; ochiq kunda 0) va smena topshirishdagi ("handover" — qabul qilingan topshirishlar
    --   sanashidagi farqlar, vaqt tartibida) — ikkalasidan biri bo'lgan kunlar
    'diffs30', coalesce((select jsonb_agg(jsonb_build_object('day', d.day, 'diff', coalesce(d.diff, 0), 'handover', h.diffs) order by d.day)
                           from public.cash_days d
                           cross join lateral (select coalesce(jsonb_agg(n.diff order by n.at, n.id), '[]'::jsonb) as diffs from public.cash_counts n
                                                where n."dayId" = d.id and n.kind = 'handover' and n.diff <> 0) h
                          where d.desk = v_desk and d.day >= v_today - 30 and (coalesce(d.diff, 0) <> 0 or jsonb_array_length(h.diffs) > 0)), '[]'::jsonb),
    'voids30', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'void' and c."businessDay" >= v_today - 30),
    'reopens30', (select count(*) from public.cash_day_events e where e.desk = v_desk and e.kind = 'reopen' and e.at >= now() - interval '30 days'),
    'waitingApproval', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'draft'),
    'approvedUnpaid', (select count(*) from public.cash_docs c where c.desk = v_desk and c.status = 'approved'),
    'fiscalExempt30', (select count(*) from public.cash_docs c where c.desk = v_desk and c."fiscalExempt" and c.status = 'posted' and c."businessDay" >= v_today - 30),
    'otherParties30', (select count(*) from public.cash_docs c where c.desk = v_desk and c."partyType" = 'other' and c.status = 'posted' and not c."isSystem" and c."businessDay" >= v_today - 30),
    'late30', (select count(*) from public.cash_docs c where c.desk = v_desk and c.late and c.status = 'posted' and c."businessDay" >= v_today - 30),
    -- yuridik shaxslarga (yetkazib beruvchi / tashkilot; tasdiqlanmagan «jismoniy shaxs» / «boshqa» ham) kassadan naqd xarajat (F1.27) —
    --   buxgalter ko'rib chiqadi. Hujjatda saqlangan belgi bo'yicha (sec-3: kontragent keyin qayta tasniflansa ham o'tgan to'lov yashirinmaydi;
    --   belgidan oldingi hujjatlar — kontragentning hozirgi turi bo'yicha)
    'orgCash30', (select jsonb_build_object('count', count(*), 'sum', coalesce(sum(c.amount), 0)) from public.cash_docs c
                   where c.desk = v_desk and c.op = 'out_expense' and c.status = 'posted' and c."partyType" = 'counterparty'
                     and coalesce(c."orgCash", app.kassa_is_org(c."partyId")) and c."businessDay" >= v_today - 30),
    -- kontragent turi o'zgarishlari (sec-3; o'zgarishlar tarixi — change_log): oxirgi 30 kunda turi o'zgargan yoki «jismoniy shaxs» /
    --   «boshqa» turi bilan qo'shilgan kontragentlar — eski → yangi tur, kim (ism, email emas), qachon, tur hozir tasdiqlanganmi (ma'lumot uchun)
    'cpKinds30', coalesce((select jsonb_agg(jsonb_build_object('id', l.row_id, 'name', coalesce(c.name, ''), 'from', l.changes -> 'kind' ->> 0, 'to', l.changes -> 'kind' ->> 1,
                                                               'byName', case when l.actor_uid is not null then app.kassa_user_label(u.name, u."staffRefType", u."staffRefId", l.actor_uid) end,
                                                               'at', l.at, 'confirmed', coalesce(c."kindConfirmedBy" is not null, false)) order by l.at desc, l.id desc)
                             from public.change_log l
                             left join public.fin_counterparties c on c.id = l.row_id
                             left join public.users u on u.id = l.actor_uid
                            where l.tbl = 'fin_counterparties' and l.changes ? 'kind' and l.at >= now() - interval '30 days'
                              and (l.op = 'UPDATE' or (l.op = 'INSERT' and l.changes -> 'kind' ->> 1 in ('person', 'other')))), '[]'::jsonb),
    -- tasdiqlanmagan «jismoniy shaxs» / «boshqa» kontragentlar (sec-3): tasdiqlanguncha yuridik shaxs hisoblanadi (kassadan naqd to'lovga
    --   Direktor tasdig'i) — buxgalter yoki Direktor turini tasdiqlaydi (fin-core.sql: fin_counterparty_confirm)
    'cpUnconfirmed', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'kind', c.kind, 'stir', c.stir) order by c.name, c.id)
                                 from public.fin_counterparties c where c.active and c.kind in ('person', 'other') and c."kindConfirmedBy" is null), '[]'::jsonb),
    -- sec-4: xodim kartasiga bog'lanmagan kassa hisoblari (kassir — asosiy yoki qo'shimcha lavozim, g'aznachi, Moliya menejeri, buxgalter):
    --   kassa hujjatlaridagi ism kartadan olinadi (HR); bog'lanmagan hisobda — foydalanuvchi o'zi yozgan va o'zgartira oladigan ism, kamomad
    --   «xodim zimmasiga» qarorida esa standart javobgar yo'q. Direktor «Foydalanuvchilar»da hisobni HR yozuviga (kartaga) bog'laydi
    'unlinkedUsers', coalesce((select jsonb_agg(jsonb_build_object('uid', u.id, 'name', app.kassa_user_label(u.name, u."staffRefType", u."staffRefId", u.id),
                                                                  'role', u.role, 'kassir', app.u_has(u.role, u."extraRoles", 'kassir')) order by u.role, u.id)
                                 from public.users u
                                where coalesce(nullif(u.status, ''), 'active') = 'active'
                                  and (u.role in ('treasurer', 'finance_mgr', 'accountant') or app.u_has(u.role, u."extraRoles", 'kassir'))
                                  and cardinality(app.kassa_user_cards(u.id)) = 0), '[]'::jsonb),
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
    -- Z-hisobot kun yopilgandan keyin kiritilgan yoki tuzatilgan kunlar (crit-4; «afterClose» belgili hodisa, kassa_day_z): tekshirilmagan
    --   kunlar va oxirgi 30 kun — necha marta, oxirgisini kim (ism) va qachon. Kunni o'sha xodim tekshira olmaydi; buxgalter qog'ozdagi Z bilan
    --   solishtiradi (kassir xatosini tuzatgan bo'lishi ham, farqni yashirgan bo'lishi ham mumkin)
    'zChanged30', case when v_test then '[]'::jsonb else
                    coalesce((select jsonb_agg(jsonb_build_object('day', x.day, 'status', x.status, 'n', x.n, 'at', x.at,
                                                                  'byName', app.kassa_user_label(u.name, u."staffRefType", u."staffRefId", x.by_uid)) order by x.day)
                                from (select d.day, d.status, count(*) as n, max(e.at) as at, (array_agg(e."byUid" order by e.at desc, e.id desc))[1] as by_uid
                                        from public.cash_days d
                                        join public.cash_day_events e on e."dayId" = d.id and e.kind = 'zreport' and e.data ->> 'afterClose' = 'true'
                                       where d.desk = v_desk and (d.status = 'closed' or d.day >= v_today - 30)
                                       group by d.id, d.day, d.status) x
                                left join public.users u on u.id = x.by_uid), '[]'::jsonb) end,
    'limit', jsonb_build_object('cashLimit', coalesce(v_limit, 0), 'set', coalesce(v_limit, 0) > 0, 'balance', v_bal,
                                'exceeded', coalesce(v_limit, 0) > 0 and v_bal > v_limit,
                                'days30', case when coalesce(v_limit, 0) > 0 then
                                            (select count(*) from public.cash_days d where d.desk = v_desk and d.status <> 'open' and d.closing > v_limit and d.day >= v_today - 30)
                                          else 0 end),
    -- moslik (kassa-links.sql: app.kassa_reconcile) — faqat asosiy kassa
    'reconcile', case when v_test then jsonb_build_object('live', false, 'total', 0) else app.kassa_reconcile(v_today - 30, v_today) end,
    -- hisobdorlardagi pul (4230): app.kassa_accountables — berilgan − naqd qaytarilgan − avans hisobotlari; hisobot muddati — 3 ish kuni (§4.9);
    --   manfiy qoldiq ham («negative»)
    'accountable', app.kassa_accountables(v_desk, v_today),
    -- xodimlar zimmasidagi kamomad (4730, acc-4): Direktor qarori bilan yozilgan − kassaga qoplangani («Kamomadni qoplash (xodim)»);
    --   qolgani — qoplash orderi yoki ish haqidan ushlash (buxgalter). Xodim kartasiga bog'lanmagan kassir qarori («boshqa» tomon,
    --   kassadan qoplab bo'lmaydi) ham ismi bilan ko'rinadi ("linked": false). Doira — app.kassa_damage_open bilan bir xil.
    'damage', coalesce((select jsonb_agg(jsonb_build_object('partyId', x.pid, 'name', coalesce(app.kassa_party_label('employee', x.pid), x.nm, ''),
                                                            'charged', x.dt, 'repaid', x.kt, 'balance', x.dt - x.kt, 'since', x.since, 'linked', x.pid is not null)
                                         order by x.since, x.nm)
                         from (select y.pid, max(y.nm) as nm, sum(y.dt) as dt, sum(y.kt) as kt, min(y.d) filter (where y.dt > 0) as since
                                 from (select case when c."partyType" = 'employee' then c."partyId" end as pid,
                                              case when c."partyType" = 'employee' then c."partyId" else 'other:' || lower(btrim(c."partyName")) end as k,
                                              c."partyName" as nm, c."businessDay" as d,
                                              case when l.debit = '4730' then l.amount else 0 end as dt, case when l.credit = '4730' then l.amount else 0 end as kt
                                         from public.cash_docs c join public.cash_doc_lines l on l."docId" = c.id
                                        where c.status = 'posted' and (l.debit = '4730' or l.credit = '4730') and c."partyType" in ('employee', 'other')
                                          and case when v_test then c.desk = v_desk
                                                   else not exists (select 1 from public.cash_desks k where k.id = c.desk and k."isTest") end) y
                                group by y.k, y.pid) x
                        where x.dt - x.kt <> 0), '[]'::jsonb),
    -- rahbar / ta'sischiga berilgan pul: buxgalter shu oy ichida tasniflaydi (dividend, ish haqi …) — hech qachon xarajat emas
    'handover', (select jsonb_build_object(
                   'monthCount', count(*) filter (where c."businessDay" >= v_m0), 'monthSum', coalesce(sum(c.amount) filter (where c."businessDay" >= v_m0), 0),
                   'earlierCount', count(*) filter (where c."businessDay" < v_m0), 'earlierSum', coalesce(sum(c.amount) filter (where c."businessDay" < v_m0), 0))
                   from public.cash_docs c where c.desk = v_desk and c.op = 'out_handover' and c.status = 'posted' and c."businessDay" >= v_today - 92),
    -- kassa ishga tushishidan OLDINGI sanali, ishga tushgandan KEYIN kiritilgan kassa hujjatisiz naqd yozuvlar (crit-1: kech kelgan
    --   to'lov / xarajat qog'ozi — Direktor haqiqiy sanasi bilan kiritadi): turi bo'yicha soni va summasi. Buxgalter ularni boshlang'ich
    --   qoldiq sanashi bilan solishtiradi — o'sha pul sanashga kirgan bo'lishi va ikkinchi marta (bugungi sana bilan) kiritilmagan bo'lishi kerak.
    --   Chegara — BIRINCHI ishga tushgan kun (g4v-3: qayta ishga tushirilgandan keyin ham birinchi davrda kiritilganlari yo'qolmaydi);
    --   to'xtatilgan davr sanalari bu yerga kirmaydi (ular «restarts» ro'yxatida), kassa ishlagan kunlarniki — moslikda («reconcile»).
    'preLive', case when v_test or v_first is null then null
                    else jsonb_build_object('goLive', v_first, 'to', v_first - 1)
                         || app.kassa_cash_rows(v_first - 400, v_first - 1, v_first::timestamp at time zone 'Asia/Tashkent', null, v_skip) end,
    -- kassani to'xtatish va qayta ishga tushirish (ishga-tushirish §9): to'xtatilgan bo'lsa — qachondan; oxirgi 400 kundagi qayta ishga
    --   tushirishlar (har to'xtatish uchun oxirgi sanash — qayta sanalganlari o'rniga) — oxirgi kun oxiri, komissiya sanagan summa, farq
    --   dalolatnomasi va to'xtatilgan davrdagi kassa hujjatisiz naqd harakat; izohlanmagan farq = farq − (shu harakat kirimi − chiqimi):
    --   0 bo'lmasa — buxgalter «Қ» jurnali bilan tekshiradi (texnik 0000 yozuvi orqasida kamomad / ortiqcha qolmasin).
    'paused', case when v_test then null else
                (select jsonb_build_object('day', (k."pausedAt" at time zone 'Asia/Tashkent')::date,
                                           'lastDay', (select max(d.day) from public.cash_days d where d.desk = k.id))
                   from public.cash_desks k where k.id = v_desk and k."pausedAt" is not null) end,
    --   Oxirgi 400 kundagi qayta ishga tushirishlar (yuqorida hisoblangan: «rows», «backdated», izohlanmagan farq).
    'restarts', v_restarts);
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
  v_o public.fin_org%rowtype; v_k public.cash_desks%rowtype; v_bal numeric; v_j jsonb; v_closed boolean; v_rec jsonb;
begin
  select * into v_k from public.cash_desks k where k.id = 'main';
  select * into v_o from public.fin_org o where o.id = 'main';
  if v_k.id is null or (v_o."kassaGoLive" is null and not exists (select 1 from public.cash_days d where d.desk = 'main')) then return null; end if;
  -- moslik — kassa ishlagan barcha davrlar bo'yicha (g4v-4; to'xtatilgan kassada ham — oxirgi kassa kunigacha): «live» — moslik
  --   tekshiriladimi (kassa hech bo'lmasa bir marta ishga tushgan)
  v_rec := app.kassa_reconcile(v_day - 6, v_day);
  select * into v_d from public.cash_days d where d.desk = 'main' and d.day = v_day;
  select * into v_open from public.cash_days d where d.desk = 'main' and d.status = 'open';
  select * into v_last from public.cash_days d where d.desk = 'main' and d.status <> 'open' order by d.day desc limit 1;
  v_bal := coalesce(app.kassa_desk_balance('main'), 0);   -- qayta ishga tushirish tayyorlangan bo'lsa — sanalgan summa
  if v_d.id is not null then
    v_j := app.kassa_day_json(v_d.id); v_closed := v_d.status <> 'open';
  end if;
  return jsonb_build_object(
    'live', coalesce((v_rec ->> 'live')::boolean, false),
    'day', case when v_d.id is not null then jsonb_build_object(
             'day', v_d.day, 'status', v_d.status, 'opening', v_d.opening,
             'receipts', case when v_closed then v_d.receipts else (v_j ->> 'receiptsLive')::numeric end,
             'payouts', case when v_closed then v_d.payouts else (v_j ->> 'payoutsLive')::numeric end,
             'closing', case when v_closed then v_d.closing else (v_j ->> 'balance')::numeric end,
             'counted', v_d.counted, 'diff', v_d.diff,
             -- acc-6: smena topshirishdagi farqlar (jami va har biri) — kunni yopishdagi farq bilan yonma-yon
             'handoverDiff', (v_j ->> 'handoverDiff')::numeric, 'handoverDiffs', v_j -> 'handoverDiffs',
             'n1', (select count(*) from public.cash_docs c where c."dayId" = v_d.id and c.status = 'posted' and c.form = 'KO1'),
             'n2', (select count(*) from public.cash_docs c where c."dayId" = v_d.id and c.status = 'posted' and c.form = 'KO2'),
             'voids', (v_j ->> 'voids')::int,
             'transfers', app.kassa_day_blocks(v_d.id) -> 'transfers') end,
    'balance', v_bal,
    'control', jsonb_build_object(
      'reconcile', (v_rec ->> 'total')::int,
      'openDay', v_open.day,
      'staleOpenDay', case when v_open.id is not null and v_open.day < v_day then v_open.day end,
      'unverifiedDays', (select count(*) from public.cash_days d where d.desk = 'main' and d.status = 'closed'),
      'voids', coalesce((v_j ->> 'voids')::int, 0),
      'diff', coalesce(v_d.diff, 0),
      'handoverDiffs', coalesce(v_j -> 'handoverDiffs', '[]'::jsonb),   -- acc-6: shu kungi smena topshirishdagi farqlar
      'undecidedShortages', (select count(*) from public.cash_docs c where c.desk = 'main' and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null),
      'waitingApproval', (select count(*) from public.cash_docs c where c.desk = 'main' and c.status = 'draft'),
      'approvedUnpaid', (select count(*) from public.cash_docs c where c.desk = 'main' and c.status = 'approved'),
      'staleRefunds', (select count(*) from public.cash_docs c where c.desk = 'main' and c.op = 'out_refund' and c.status = 'approved'
                         and c."dirApprovedAt" < app.fin_now() - interval '1 day'),
      'gaps', (select count(*) from (select distinct year from public.doc_counters where desk = 'main') k
                where jsonb_array_length(app.kassa_gap_check('main', k.year)) > 0),
      'fiscalExempt', (select count(*) from public.cash_docs c where c.desk = 'main' and c."fiscalExempt" and c.status = 'posted' and c."businessDay" = v_day),
      'limitExceeded', coalesce(v_o."cashLimit", 0) > 0 and v_bal > v_o."cashLimit",
      'accOverdue', app.kassa_acc_overdue('main', v_day),   -- eslatma (F1.24)
      -- onlayn kassa Z-hisoboti (F1.26) — shu kun yopilgan bo'lsa
      'z', case when v_closed then (select jsonb_build_object('ok', (z ->> 'ok')::boolean, 'needed', (z ->> 'needed')::boolean,
                                                               'recorded', (z ->> 'recorded')::boolean, 'missing', (z ->> 'missing')::boolean,
                                                               'diffCash', z -> 'diffCash', 'diffCard', z -> 'diffCard')
                                      from app.kassa_z_state(v_d.id) z) end),
    -- RP-22 (F1.25): dushanba kungi hisobotda o'tgan hafta (du–ya) ko'rsatkichlari
    'week', case when extract(isodow from v_day) = 1 then app.kassa_week_kpi('main', v_day - 7, v_day - 1) end);
end $$;
revoke all on function app.kassa_daily(date) from public, anon, authenticated;

-- ---------- O'qish: shakllar uchun ma'lumotnomalar (bitta chaqiruv) ----------
create or replace function public.kassa_refs() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  return jsonb_build_object(
    'rules', coalesce((select jsonb_agg(to_jsonb(r) order by r."sortOrder") from public.fin_op_rules r where r.active), '[]'::jsonb),
    -- advReport — avans hisoboti (АО-1) qatoriga tanlanadimi: server bilan bir xil qoida (kassa-docs.sql: app.kassa_adv_article; acc-5)
    'articles', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'nameUz', a."nameUz", 'nameRu', a."nameRu", 'accountCode', a."accountCode",
                                                              'cashOutAllowed', a."cashOutAllowed", 'needsNote', a."needsNote", 'advReport', app.kassa_adv_article(a)) order by a."sortOrder")
                            from public.fin_articles a where a.active), '[]'::jsonb),
    -- confirmed — turini buxgalter / Direktor tasdiqlagan; org — yuridik shaxs hisoblanadi (server qoidasi, app.kassa_is_org; sec-3)
    'counterparties', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'name', c.name, 'stir', c.stir,
                                                                    'confirmed', c."kindConfirmedBy" is not null, 'org', app.kassa_is_org(c.id)) order by c.name)
                                  from public.fin_counterparties c where c.active), '[]'::jsonb),
    'org', (select to_jsonb(o) from public.fin_org o where o.id = 'main'),
    'desks', coalesce((select jsonb_agg(to_jsonb(k) order by k.id) from public.cash_desks k where k.active), '[]'::jsonb),
    'signatories', coalesce((select jsonb_agg(to_jsonb(s) order by s.list, s."fullName") from public.fin_signatories s where s.active), '[]'::jsonb),
    'operators', coalesce((select jsonb_agg(jsonb_build_object('uid', u.id, 'name', app.kassa_user_label(u.name, u."staffRefType", u."staffRefId", u.id)) order by u.name)   -- email emas
                             from public.users u
                            where coalesce(nullif(u.status, ''), 'active') = 'active'
                              and (u.role = 'treasurer' or app.u_has(u.role, u."extraRoles", 'kassir'))), '[]'::jsonb),
    -- imzo huquqi bo'lishi mumkin bo'lgan hisoblar («⚙ Sozlamalar» → «Imzo egalari» da hisobni bog'lash uchun) — faqat Direktorga
    'signers', case when app.is_admin() then
                 coalesce((select jsonb_agg(jsonb_build_object('uid', u.id, 'name', coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), u.id), 'role', u.role) order by u.name)
                             from public.users u
                            where coalesce(nullif(u.status, ''), 'active') = 'active'
                              and u.role in ('director', 'finance_mgr', 'accountant')), '[]'::jsonb)   -- faqat asosiy rol (qo'shimcha bo'lmaydi)
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
      select unnest(array[d."cashierUid", d."closedBy", d."verifiedBy", d."reopenedBy"]) from public.cash_days d where d.desk = v_desk and d.day >= app.fin_today() - 62
      union all   -- kamomad qarori: kassa egasi, sanagan, qabul qiluvchi (sec-2); kutilayotgan va shu kunlardagi smena topshirishlar (state-6)
      select unnest(array[c."sourceSnapshot" ->> 'cashierUid', c."sourceSnapshot" ->> 'countedBy', c."sourceSnapshot" ->> 'toUid']) from public.cash_docs c
       where c.desk = v_desk and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null
      union all   -- g6v-1: kassa egasidan boshqa kassa orderi o'tkazgan / bekor qilganlar
      select jsonb_array_elements_text(case when jsonb_typeof(c."sourceSnapshot" -> 'others') = 'array' then c."sourceSnapshot" -> 'others' else '[]'::jsonb end)
        from public.cash_docs c where c.desk = v_desk and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null
      union all
      select unnest(array[h."fromUid", h."toUid", h."byUid", h."cancelledBy"]) from public.cash_handovers h
       where h.desk = v_desk and (h.status = 'pending' or h."dayId" = v_day
                                  or h."dayId" in (select c."dayId" from public.cash_docs c where c.desk = v_desk and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null))) q
   where x is not null;
  return jsonb_build_object('ok', true, 'state', v_state,
    'docs', coalesce((select jsonb_agg(app.kassa_doc_json(c.id) order by c."postedAt" desc, c.form, c.no desc)
                        from public.cash_docs c where c."dayId" = v_day and c.status in ('posted', 'void')), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(app.kassa_doc_json(c.id) order by c."createdAt")
                            from public.cash_docs c where c.desk = v_desk and c.status in ('draft', 'approved')), '[]'::jsonb),
    'days', coalesce((select jsonb_agg(app.kassa_day_json(d.id) order by d.day desc)
                        from (select x.id, x.day from public.cash_days x where x.desk = v_desk order by x.day desc limit 31) d), '[]'::jsonb),
    -- qarori kutilayotgan kamomadlar (sec-2): kassa egasi va sanagan xodim alohida (ismlar — sanash paytidagi holatda), smenada — qabul qiluvchi;
    --   standart javobgar (faqat kassa egasi o'zi sanagan va kassaga boshqa hech kim tegmagan bo'lsa — uning kartasi; aks holda bo'sh — Direktor
    --   tanlaydi) va nega yo'qligi (defaultWhy — server matni, g6v-3); kassa egasidan boshqa kassa orderi o'tkazgan / bekor qilganlar (others,
    --   g6v-1; ismlari — names da); shu kungi smena topshirishlar
    'shortages', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'no', c.no, 'day', c."businessDay", 'amount', c.amount,
                                                               'cashierUid', c."sourceSnapshot" ->> 'cashierUid', 'countedBy', c."sourceSnapshot" ->> 'countedBy',
                                                               'toUid', c."sourceSnapshot" ->> 'toUid', 'kind', c."sourceSnapshot" ->> 'kind',
                                                               'handoverId', c."sourceSnapshot" ->> 'handoverId', 'names', coalesce(c."sourceSnapshot" -> 'names', '{}'::jsonb),
                                                               'defaultParty', x.def, 'defaultPartyName', app.kassa_party_label('employee', x.def),
                                                               'defaultWhy', app.kassa_shortage_why(c."sourceSnapshot"),
                                                               'others', case when jsonb_typeof(c."sourceSnapshot" -> 'others') = 'array' then c."sourceSnapshot" -> 'others' else '[]'::jsonb end,
                                                               'handovers', coalesce((select jsonb_agg(to_jsonb(h) order by h."createdAt", h.id) from public.cash_handovers h
                                                                                       where h."dayId" = c."dayId"), '[]'::jsonb)) order by c."businessDay")
                             from public.cash_docs c cross join lateral (select app.kassa_shortage_default(c."sourceSnapshot") as def) x
                            where c.desk = v_desk and c.op = 'out_shortage' and c.status = 'posted' and c.decision is null), '[]'::jsonb),
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
    -- o'tkazgan xodim ismi — o'tkazish paytidagisi (sec-4: "postedByName"; keyingi o'zgarish chop etilgan hujjatga ta'sir qilmaydi)
    'names', app.kassa_names(array[v_c."requestedBy", v_c."approvedBy", v_c."dirApprovedBy", v_c."rejectedBy", v_c."postedBy",
                                   v_c."voidedBy", v_c."createdBy", v_c."decidedBy"])
             || case when v_c."postedBy" is not null and v_c."postedByName" is not null then jsonb_build_object(v_c."postedBy", v_c."postedByName") else '{}'::jsonb end);
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
