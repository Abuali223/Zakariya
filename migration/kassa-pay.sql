\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: kassa-pay.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- kassa-pay.sql — MOLIYA ISH REJASI, 1a-BOSQICH (F1.4): NAQD O'QUV TO'LOVI → KASSA KIRIM ORDERI (KO-1).
--   Kassa ishga tushgach (fin_org."kassaGoLive" — Direktor belgilaydi) har NAQD o'quv to'lovi «💵 To'lov» shaklidan
--   (public.record_manual_payment, fin-prereq.sql) SHU TRANZAKSIYADA KO-1 bilan yoziladi:
--     to'lov qatori (payments) + balansga qo'llash (apply_payment) + KO-1 (raqam, kun, Dt/Kt qatorlari) — hammasi yoki hech narsa.
--   KO-1 qatorlari to'lov TAQSIMOTIDAN chiqadi (PR-07, PR-08, PR-23):
--     Dt 5010 Kt 4010 — boshlangan davr (joriy va o'tgan oylar) fakturasiga tushgan naqd pul;
--     Dt 5010 Kt 6310 — kelgusi oy fakturasiga tushgan va ortiqcha (avansga o'tgan) naqd pul;
--     Dt 6310 Kt 4010 — NAQDSIZ qator: shu to'lov bilan birga fakturaga qo'llangan ESKI avans (kassa summasiga kirmaydi).
--   Eski avans avval (eng eski fakturadan boshlab) sarflanadi, keyin naqd pul — apply_payment tartibi bilan bir xil.
--   record_manual_payment bu fayldagi funksiyalarni DINAMIK chaqiradi (to_regprocedure): shu fayl zanjirda bo'lmasa yoki
--   kassa ishga tushmagan bo'lsa — to'lov avvalgidek, KO-1 siz yoziladi.
--   Kassa ishga tushgach naqd pulni faqat kassa operatori (kassir, g'aznachi) yoki favqulodda Direktor qabul qiladi (RF-08);
--   fiskal chek raqami majburiy (istisno — Direktor); kecha yopilmagan bo'lsa to'lov ham yozilmaydi (CT-04).
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi.
-- =====================================================================

-- Eski jadvalga faqat bo'sh bo'lishi mumkin bo'lgan ustunlar.
alter table public.payments add column if not exists "cashDocId" text;   -- naqd to'lovning kassa kirim orderi (cash_docs.id)
alter table public.payments add column if not exists "fiscalNo" text;    -- fiskal chek raqami
create index if not exists payments_cash_doc_idx on public.payments ("cashDocId") where "cashDocId" is not null;

-- Kassa ishga tushganmi: Direktor belgilagan kundan boshlab (bo'sh — hali yo'q; to'xtatilgan kassada ham bo'sh — kassa-day.sql:
--   app.kassa_golive_guard). Sozlama qatori FOR SHARE (state-7): ishga tushadigan kun shu payt o'zgarayotgan bo'lsa (fin_org_set qatorni
--   FOR UPDATE bilan ushlaydi) — u tugaguncha kutib, YANGI qiymat bilan javob beradi; aks holda naqd yozuv eski qiymat bilan kassa
--   hujjatisiz o'tib ketardi (moslik P1 / P4 / P5 da abadiy qolardi). FOR SHARE faqat VOLATILE funksiyada ishlaydi; chaqiruvchilar —
--   faqat yozuvchi yo'llar (naqd yozuv triggeri va kassa RPC'lari); o'qish funksiyalari fin_org ni o'zi o'qiydi.
create or replace function app.kassa_live() returns boolean
language plpgsql volatile security definer set search_path = public, app, pg_temp as $$
declare v_live date;
begin
  select o."kassaGoLive" into v_live from public.fin_org o where o.id = 'main' for share;
  return v_live is not null and app.fin_today() >= v_live;
end $$;
revoke all on function app.kassa_live() from public, anon, authenticated;

-- To'lovdan OLDINGI holat (o'quvchi bo'yicha navbat qulfi ichida): avans va to'lanmagan fakturalar. NULL — KO-1 yozilmaydi.
--   Kassa qo'llanadimi — to'lovning O'Z kassa kuni bo'yicha, bugun bo'yicha emas (crit-1). p_day — record_manual_payment hisoblagan
--   kun: kassir tanlagan «Sana», bo'lmasa olingan kun (p_captured, Toshkent), bo'lmasa bugun. p_asked — so'ralgan «Sana» (matn, o'zgarmagan).
--   * kassa hali ishga tushmagan (sana yo'q yoki kelmagan) — NULL, avvalgidek; kassa TO'XTATILGAN yoki qayta ishga tushirish kunini
--     kutmoqda (g4r-2): oxirgi kassa kuni va undan oldingi sana bilan naqd to'lov hech kimga yozilmaydi (kassa:paused_live_day — u kunlar
--     kassa hujjatlari bilan yopilgan; so'ralgan sana 31 kunlik oraliqdan chiqqani uchun bugunga surilgan bo'lsa ham — so'ralgani bo'yicha,
--     aks holda u to'xtatilgan davr puli bo'lib yozilardi); to'xtatilgan davr sanasi — NULL, avvalgidek (ishga-tushirish §9). Qurilma
--     navbatida qolgan to'lov qayta ishga tushgach qayta yuborilmasin (g4b-v1): pul kassada sanalgan bo'lsa, kech KO-1 uni ikkinchi marta
--     hisoblardi — xabar shuni aytadi; oxirgi kun «hali o'tkazilmagan yozuvlar» bilan yopilgan bo'lsa kassa umuman to'xtatilmaydi
--     (kassa-day.sql app.kassa_golive_guard, kassa:rollback_pending);
--   * p_day KASSA ISHLAMAGAN kun (g4v-1, app.kassa_pre_day: birinchi ishga tushgan kundan oldin yoki to'xtatilgan davr ichida) — u pul
--     komissiya sanashiga kirgan (ishga-tushirish §4, §9) — KO-1 siz va fiskal cheksiz (NULL). Kim: Direktor; kassir / g'aznachi — faqat
--     qurilma navbatidan kelgan yozuv: olingan kun ham kassa ishlamagan kun, olingan payt 48 soatdan eski emas (kassa:late_limit qoidasi),
--     «Sana» olingan kundan keyin emas. Boshqasi — rad (kassa:pre_live): KO-1 qoidasini chetlab o'tish yo'li bo'lmasin (state-4 bilan
--     solishtiring). Davr qulfi baribir amal qiladi;
--   * qolgan kunlar (kassa ishlagan davr — yopilganlari ham) — KO-1 bilan, bugungi kassa kuniga (RF-08: kassir yoki Direktor); lekin
--     so'ralgan sana kassa ishlamagan kun bo'lib, 31 kunlik oraliqdan chiqqani uchun bugunga surilgan bo'lsa — rad (kassa:pre_live_old):
--     eski pul bugungi KO-1 bo'lib ikki marta hisoblanmasin.
--   Sozlama qatori FOR SHARE (state-7): ishga tushadigan kun shu payt o'zgarayotgan bo'lsa — u tugaguncha kutib, yangi qiymat bilan qaror.
--   Natijadagi «day» (state-3) — kirim orderi tushadigan kassa kuni (taxmin): record_manual_payment to'lov qatorini shu kun bilan yozadi.
drop function if exists app.kassa_tuition_before(text);
create or replace function app.kassa_tuition_before(p_sid text, p_day date, p_captured timestamptz, p_asked text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_sid text; v_credit numeric; v_live date; v_today date := app.fin_today(); v_day date := coalesce(p_day, app.fin_today());
        v_asked date := app.fin_text_day(p_asked); v_cap date := (p_captured at time zone 'Asia/Tashkent')::date; v_p jsonb; v_chk date;
        v_after boolean := false; v_open date;
begin
  select o."kassaGoLive" into v_live from public.fin_org o where o.id = 'main' for share;
  v_p := app.kassa_periods('main');
  if v_live is null or v_today < v_live then
    -- ushlangan kassada sana — so'ralgani (oraliqdan tashqarida bo'lib bugunga surilgan bo'lsa ham; kelajakdagisi — bugun)
    v_chk := least(coalesce(v_asked, v_day), v_day);
    if coalesce((v_p ->> 'hold')::boolean, false) and v_chk <= (v_p ->> 'last')::date then
      if app.kassa_pre_day('main', v_chk) then
        raise exception 'To''lov sanasi (%) oxirgi kassa kunidan (%) oldin: kassa to''xtatilgan paytda bunday naqd to''lov yozilmaydi. Kassa ishlamagan kun (ishga tushishdan oldingi yoki oldingi to''xtatilgan davr) pulini kassa qayta ishga tushgach Direktor haqiqiy sanasi bilan kiritadi',
          to_char(v_chk, 'DD.MM.YYYY'), to_char((v_p ->> 'last')::date, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:paused_live_day';
      end if;
      -- (asosiy ko'rsatma boshida: qurilma navbati oynasi xabarning faqat boshini — 140 belgini — ko'rsatadi)
      raise exception 'To''lov sanasi (%) — kassa kuni edi: to''xtatilgan kassada yozilmaydi, qayta ishga tushgach ham qayta yubormang — Direktor hal qiladi (oxirgi kassa kuni % kassa hujjatlari bilan yopilgan; pul kassada sanalgan bo''lsa, kirim orderi uni ikkinchi marta hisoblardi — buxgalter bilan). To''xtatilgan davr puli oxirgi kassa kunidan keyingi sana bilan kiritiladi (to''xtatilgan kunning o''zida, kun yopilgandan keyin olingani — ertasi kuni, o''sha sana bilan)',
        to_char(v_chk, 'DD.MM.YYYY'), to_char((v_p ->> 'last')::date, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:paused_live_day';
    end if;
    return null;
  end if;
  -- g4b: qurilma navbatidagi to'lov qayta ishga tushirish SANASHIDAN KEYIN olingan ("capturedAt" > "restartAt"), olingan kuni esa qayta
  --   ishga tushirish kunidan oldin (to'xtatilgan davr) — bu pul komissiya sanagan summaga kirmagan: kassa ishlayotgan bo'lsa kirim orderi
  --   bilan (bugungi kassa kuniga, «kech») yoziladi. Aks holda KO-1 siz yozilib, birinchi yopishda ortiqcha bo'lib chiqar va tushum ikki
  --   marta hisoblanardi. (Kassa hali kutayotgan paytda yuborilsa — KO-1 siz, sanash eskirgan: kassa:restart_recount.) Olingan payt
  --   brauzerniki — onlayn kiritilgan (bugungi) yozuvga tegmaydi: Direktorning kechikkan qog'ozi avvalgi tartibda.
  select p_captured is not null and k."restartAt" is not null and p_captured > k."restartAt" and v_cap < k."restartDay"
    into v_after from public.cash_desks k where k.id = 'main' and not k."isTest";
  v_after := coalesce(v_after, false);
  if app.kassa_pre_day('main', v_day) and not v_after then
    if app.is_admin()
       or (app.kassa_operator() and p_captured is not null and p_captured >= app.fin_now() - interval '48 hours'
           and app.kassa_pre_day('main', v_cap) and v_day <= v_cap) then
      return null;
    end if;
    if v_day < (v_p ->> 'first')::date then
      raise exception 'Kassa ishga tushishidan (%) oldingi sana bilan naqd to''lov (%) — faqat Direktor kiritadi: bu pul boshlang''ich qoldiq sanashiga kirgan (kassir — faqat ishga tushishdan oldin qurilma navbatiga yozilgan va 48 soatdan eski bo''lmagan to''lovni yuboradi)',
        to_char((v_p ->> 'first')::date, 'DD.MM.YYYY'), to_char(v_day, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:pre_live';
    end if;
    raise exception 'Kassa to''xtatilgan davr sanasi bilan naqd to''lov (%) — faqat Direktor kiritadi: bu pul qayta ishga tushirish sanashiga kirgan (kassir — faqat o''sha davrda qurilma navbatiga yozilgan va 48 soatdan eski bo''lmagan to''lovni yuboradi)',
      to_char(v_day, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:pre_live';
  end if;
  if v_asked is not null and v_asked <> v_day and app.kassa_pre_day('main', v_asked) then
    raise exception 'So''ralgan sana (%) kassa ishlamagan kun (ishga tushishdan oldin yoki to''xtatilgan davr) va 31 kunlik oraliqdan tashqarida: bu to''lov bugungi kirim orderi bilan yozilmaydi (pul komissiya sanashiga kirgan) — buxgalter bilan hal qilinadi',
      to_char(v_asked, 'DD.MM.YYYY') using errcode = '22023', hint = 'kassa:pre_live_old';
  end if;
  if not (app.kassa_operator() or app.is_admin()) then   -- RF-08
    raise exception 'Ruxsat yo''q: naqd pulni kassir (favqulodda — Direktor) qabul qiladi' using errcode = '42501', hint = 'kassa:cash_role';
  end if;
  -- apply_payment bilan AYNAN bir xil kanonik kalit va qulf (L1).
  select s."studentId" into v_sid from public.students s where s.id = p_sid or s."studentId" = p_sid order by (s.id = p_sid) desc limit 1;
  v_sid := coalesce(nullif(v_sid, ''), p_sid);
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));
  select c.credit into v_credit from public.student_credit c where c.id = v_sid;
  -- state-3: kirim orderi tushadigan kassa kuni (kassa qulfisiz taxmin; aniq kunni kassa_tuition_post da app.kassa_resolve_day beradi):
  --   ochiq kun bugundan oldin va to'lov o'sha kuni olingan — o'sha kun, aks holda — bugun. record_manual_payment to'lov qatorini SHU kun
  --   bilan yozadi (olingan payt — raw.capturedAt da): davr qulfi to'lov olingan kunni emas, order tushadigan kunni tekshiradi — yopilgan
  --   oyning oxirgi kunida navbatda qolgan to'lov keyingi oyning ochiq kuniga «kech» tushadi (avval fin:locked bilan abadiy rad etilardi).
  --   Taxmin aniq kundan farq qilsa (shu orada kun yopilgan) — qator sanasi order kuniga tuzatiladi, davr qulfi ikkala kunni tekshiradi.
  select d.day into v_open from public.cash_days d where d.desk = 'main' and d.status = 'open';
  return jsonb_build_object('sid', v_sid, 'credit', coalesce(v_credit, 0), 'redate', v_after,
    'day', to_char(case when v_open < v_today and v_cap = v_open then v_open else v_today end, 'YYYY-MM-DD'),
    'invoices', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'month', coalesce(i.month, ''), 'amount', coalesce(i.amount, 0),
                                                              'paid', coalesce(i."paidAmount", 0), 'paidRaw', i."paidAmount", 'status', i.status,
                                                              'provider', i.provider, 'paidAt', i."paidAt")
                                           order by coalesce(nullif(i.month, ''), i.id))
                            from public.invoices i
                           where i."studentId" = v_sid and (i.status is null or i.status not in ('paid', 'canceled', 'reversed'))), '[]'::jsonb));
end $$;
revoke all on function app.kassa_tuition_before(text, date, timestamptz, text) from public, anon, authenticated;

-- To'lovning kassa orderi haqida qisqa ma'lumot (javob va chop etish uchun).
create or replace function app.kassa_tuition_info(p_pay_id text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select jsonb_build_object('docId', c.id, 'form', c.form, 'no', c.no, 'year', c.year, 'day', to_char(c."businessDay", 'YYYY-MM-DD'),
                            'late', c.late, 'status', c.status, 'desk', c.desk)
    from public.cash_docs c
   where c."sourceTable" = 'payments' and c."sourceId" = p_pay_id and c.form = 'KO1'
   order by (c.status = 'posted') desc, c."createdAt" desc limit 1
$$;
revoke all on function app.kassa_tuition_info(text) from public, anon, authenticated;

-- To'lov qo'llangandan KEYIN: pul qayerga taqsimlandi (fakturalar bo'yicha; ortiqchasi — avans). Naqd o'quv to'lovi (KO-1,
--   p_debit '5010') va o'zaro hisob dalolatnomasi (kassa-links.sql, p_debit '6710') — bitta qoida bilan.
--   p_before — app.kassa_tuition_before() natijasi (to'lovdan OLDINGI fakturalar va avans); p_credit_lines — shu to'lov bilan
--   birga fakturaga qo'llangan ESKI avans uchun naqdsiz qator (Dt 6310 Kt 4010) qo'shilsinmi (KO-1 da ham, dalolatnomada ham — ha;
--   dalolatnomada u ma'lumot qatori, hujjat summasiga kirmaydi — acc-2).
--   p_day — hujjat kuni (kassa kuni / dalolatnoma sanasi): «boshlangan davr» (4010) va «kelgusi oy» (6310) shu kunning oyiga nisbatan
--   (acc-7: kecha olingan, yarim tundan keyin yuborilgan oflayn to'lov hali ochiq kechagi kunga tushadi — oyi ham kechagi).
--   Natija: {mode: exact | fallback | unknown, lines, alloc, months, over, creditBefore, creditAfter}.
drop function if exists app.kassa_tuition_alloc(jsonb, numeric, text, boolean, boolean);
create or replace function app.kassa_tuition_alloc(p_before jsonb, p_amount numeric, p_debit text, p_credit_lines boolean, p_apply_dup boolean, p_day date)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_sid text := p_before ->> 'sid'; v_c0 numeric := coalesce((p_before ->> 'credit')::numeric, 0); v_c1 numeric;
  v_month text := to_char(coalesce(p_day, app.fin_today()), 'YYYY-MM');
  v_inv jsonb; v_paid numeric; v_delta numeric; v_rem numeric; v_fc numeric; v_fk numeric; v_cash_inv numeric := 0; v_over numeric := 0;
  v_acct text; v_lines jsonb := '[]'::jsonb; v_alloc jsonb := '[]'::jsonb; v_months text[] := '{}'; v_mode text := 'exact';
begin
  select c.credit into v_c1 from public.student_credit c where c.id = v_sid;
  v_c1 := coalesce(v_c1, 0);
  if p_apply_dup then
    v_mode := 'unknown';
  else
    v_rem := v_c0;   -- eski avans avval sarflanadi (eng eski fakturadan)
    for v_inv in select x from jsonb_array_elements(p_before -> 'invoices') x loop
      select coalesce(i."paidAmount", 0) into v_paid from public.invoices i where i.id = v_inv ->> 'id';
      v_delta := coalesce(v_paid, 0) - (v_inv ->> 'paid')::numeric;
      if v_delta is null or v_delta <= 0 then continue; end if;
      v_fc := least(v_delta, v_rem); v_rem := v_rem - v_fc; v_fk := v_delta - v_fc;
      v_acct := case when coalesce(v_inv ->> 'month', '') ~ '^\d{4}-\d{2}$' and (v_inv ->> 'month') > v_month then '6310' else '4010' end;
      if v_fk > 0 then
        v_lines := v_lines || jsonb_build_object('debit', p_debit, 'credit', v_acct, 'amount', v_fk, 'articleId', 'IN-01',
                     'analytics', jsonb_build_object('studentId', v_sid, 'invoiceId', v_inv ->> 'id', 'month', v_inv ->> 'month'));
        v_cash_inv := v_cash_inv + v_fk;
      end if;
      if v_fc > 0 and v_acct = '4010' and p_credit_lines then   -- naqdsiz: avans fakturaga qo'llandi
        v_lines := v_lines || jsonb_build_object('debit', '6310', 'credit', '4010', 'amount', v_fc, 'articleId', 'IN-01',
                     'analytics', jsonb_build_object('studentId', v_sid, 'invoiceId', v_inv ->> 'id', 'month', v_inv ->> 'month', 'kind', 'credit_applied'));
      end if;
      v_alloc := v_alloc || jsonb_build_object('invoiceId', v_inv ->> 'id', 'month', v_inv ->> 'month', 'fromCash', v_fk, 'fromCredit', v_fc, 'account', v_acct);
      if coalesce(v_inv ->> 'month', '') <> '' then v_months := v_months || (v_inv ->> 'month'); end if;
    end loop;
    v_over := p_amount - v_cash_inv;
    -- Nazorat: yangi avans = sarflanmagan eski avans + ortiqcha pul. Mos kelmasa (shu payt boshqa tuzatish bo'lgan) — bitta qator.
    if v_over < 0 or abs(v_c1 - (v_rem + v_over)) >= 0.01 then
      v_mode := 'fallback';
    elsif v_over > 0 then
      v_lines := v_lines || jsonb_build_object('debit', p_debit, 'credit', '6310', 'amount', v_over, 'articleId', 'IN-01',
                   'analytics', jsonb_build_object('studentId', v_sid, 'kind', 'overpay'));
      v_alloc := v_alloc || jsonb_build_object('invoiceId', null, 'month', null, 'fromCash', v_over, 'fromCredit', 0, 'account', '6310');
    end if;
  end if;
  if v_mode <> 'exact' then
    v_lines := jsonb_build_array(jsonb_build_object('debit', p_debit, 'credit', '4010', 'amount', p_amount, 'articleId', 'IN-01',
                 'analytics', jsonb_build_object('studentId', v_sid, 'allocation', v_mode)));
    v_alloc := jsonb_build_array(jsonb_build_object('invoiceId', null, 'month', null, 'fromCash', p_amount, 'fromCredit', 0, 'account', '4010'));
    v_months := '{}'; v_over := 0;
  end if;
  return jsonb_build_object('mode', v_mode, 'lines', v_lines, 'alloc', v_alloc, 'months', to_jsonb(v_months), 'over', v_over,
                            'creditBefore', v_c0, 'creditAfter', v_c1);
end $$;
revoke all on function app.kassa_tuition_alloc(jsonb, numeric, text, boolean, boolean, date) from public, anon, authenticated;

-- To'lov qo'llangandan KEYIN: taqsimotni hisoblab, KO-1 ni yozadi va o'tkazadi. p_apply_dup — balansga avval qo'llangan
--   (eski 3 bosqichli mijoz yarim yo'lda qolgan) to'lov: taqsimot noma'lum, bitta qator (Kt 4010) bilan yoziladi va belgilanadi.
create or replace function app.kassa_tuition_post(p_pay_id text, p_amount numeric, p_payer_name text, p_captured timestamptz,
                                                  p_extra jsonb, p_before jsonb, p_apply_dup boolean) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_sid text := p_before ->> 'sid'; v_c0 numeric := coalesce((p_before ->> 'credit')::numeric, 0); v_c1 numeric;
  v_extra jsonb := case when jsonb_typeof(p_extra) = 'object' then p_extra else '{}'::jsonb end;
  v_fiscal text; v_exempt boolean; v_day date;
  v_over numeric := 0; v_a jsonb;
  v_lines jsonb := '[]'::jsonb; v_alloc jsonb := '[]'::jsonb; v_months text[] := '{}'; v_mode text := 'exact';
  v_doc_id text; v_dup boolean; v_doc public.cash_docs%rowtype; v_info jsonb; v_basis text;
begin
  v_info := app.kassa_tuition_info(p_pay_id);
  if v_info ->> 'status' = 'posted' then return v_info || jsonb_build_object('dup', true); end if;   -- qayta yuborish

  -- Fiskal chek (CT-21): raqamsiz — faqat Direktor istisnosi.
  v_fiscal := nullif(left(btrim(coalesce(v_extra ->> 'fiscalNo', '')), 40), '');
  v_exempt := v_fiscal is null and app.kassa_bool(v_extra, 'fiscalExempt');
  if v_fiscal is null and not (v_exempt and app.is_admin()) then
    raise exception 'Fiskal chek raqami kiritilmagan' using errcode = '22023', hint = 'kassa:fiscal';
  end if;

  perform app.kassa_flag(true);
  -- g4b: sanashdan keyin olingan, to'xtatilgan davr sanali to'lov (kassa_tuition_before 'redate') — qatori sanasi oldindan bugunga:
  --   birinchi qayta ochilgan kun shu hujjat bilan ochilsa, «sanashdan keyingi hujjatisiz yozuv» tekshiruvi (app.kassa_restart_stale)
  --   uni — hali hujjatsiz turgan o'zini — sanab, kunni ochmay qo'ymasin. Yakuniy sana — pastda, order kuni. (state-3: yangi qator endi
  --   kirim orderi kuni bilan yoziladi — kassa_tuition_before 'day', bu holda bugun; qadam eski mijozdan qolgan «pending» qator uchun qoladi.)
  if coalesce((p_before ->> 'redate')::boolean, false) then
    update public.payments set raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('date', to_char(app.fin_today(), 'YYYY-MM-DD'))
     where id = p_pay_id;
  end if;
  -- Kassa kuni taqsimotdan OLDIN aniqlanadi (acc-7): kassa qulfi (L4; o'quvchi navbati L1 — kassa_tuition_before'da, undan keyin)
  --   ostida o'sha kun qoidasi bilan (app.kassa_resolve_day; kun hali ochilmagan bo'lsa — shu yerda ochiladi) — kassa_doc_post o'sha
  --   qulf ostida aynan shu kunni qaytadan oladi. «Boshlangan davr» (4010) / «kelgusi oy» (6310) — shu kunning oyiga nisbatan.
  perform app.kassa_lock_desk('main');
  select d.o_day into v_day from app.kassa_resolve_day('main', p_captured, v_uid, app.is_admin()) d;
  v_a := app.kassa_tuition_alloc(p_before, p_amount, '5010', true, p_apply_dup, v_day);
  v_mode := v_a ->> 'mode'; v_lines := v_a -> 'lines'; v_alloc := v_a -> 'alloc'; v_over := (v_a ->> 'over')::numeric;
  v_c1 := (v_a ->> 'creditAfter')::numeric;
  v_months := array(select jsonb_array_elements_text(v_a -> 'months'));
  v_basis := 'O‘quv to‘lovi' || case when cardinality(v_months) > 0 then ': ' || array_to_string(v_months, ', ') else '' end
             || case when v_mode = 'exact' and v_over > 0 then case when cardinality(v_months) > 0 then ' + avans' else ' (avans)' end else '' end;

  select b.o_id, b.o_dup into v_doc_id, v_dup from app.kassa_doc_build(jsonb_build_object(
      'desk', 'main', 'op', 'in_tuition', 'amount', p_amount, 'partyType', 'student', 'partyId', v_sid, 'partyName', p_payer_name,
      'basis', v_basis, 'fiscalNo', v_fiscal, 'fiscalExempt', v_exempt, 'clientRef', 'pay_' || p_pay_id, 'capturedAt', p_captured,
      'sourceTable', 'payments', 'sourceId', p_pay_id,
      'sourceSnapshot', jsonb_build_object('allocation', v_mode, 'creditBefore', v_c0, 'creditAfter', v_c1, 'before', p_before -> 'invoices'),
      'lines', v_lines), 'KO1', v_uid, true) b;
  --   48 soatdan eski (qog'oz «Қ» bo'yicha) to'lovni faqat Direktor o'zi kiritadi.
  v_doc := app.kassa_doc_post(v_doc_id, v_uid, false, p_captured, app.is_admin());
  insert into public.payment_allocations (id, "paymentId", "docId", "studentId", "invoiceId", month, "fromCash", "fromCredit", account)
    select 'pa_' || replace(gen_random_uuid()::text, '-', ''), p_pay_id, v_doc.id, v_sid, a ->> 'invoiceId', a ->> 'month',
           (a ->> 'fromCash')::numeric, (a ->> 'fromCredit')::numeric, a ->> 'account'
      from jsonb_array_elements(v_alloc) a;
  -- To'lov qatori: order havolasi, fiskal chek №; kassa kuni — order kuni (hisobotlarda «tushgan kun» shu). Bayroq ostida:
  --   orderga bog'langan to'lov qatorini faqat kassa funksiyalari o'zgartiradi (kassa-links.sql: app.kassa_pay_guard).
  update public.payments
     set "cashDocId" = v_doc.id, "fiscalNo" = v_fiscal,
         raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('date', to_char(v_doc."businessDay", 'YYYY-MM-DD'), 'kassaNo', v_doc.no)
   where id = p_pay_id;
  perform app.kassa_flag(false);
  return jsonb_build_object('docId', v_doc.id, 'form', 'KO1', 'no', v_doc.no, 'year', v_doc.year, 'day', to_char(v_doc."businessDay", 'YYYY-MM-DD'),
                            'late', v_doc.late, 'status', v_doc.status, 'desk', v_doc.desk, 'dup', false, 'allocation', v_mode);
end $$;
revoke all on function app.kassa_tuition_post(text, numeric, text, timestamptz, jsonb, jsonb, boolean) from public, anon, authenticated;

-- ---------- O'quv to'lovini teskari qilish (F1.7) — kassa_doc_void ichidan, shu kunda ----------
--   Ikki hujjat turi uchun: naqd o'quv to'lovi orderi (in_tuition; to'lov — hujjat manbasi) va o'zaro hisob dalolatnomasi
--   (nc_offset; to'lov va o'quvchi — hujjat suratida: kassa-links.sql kassa_offset_void chaqiradi).
--   Rol tekshirilmaydi (chaqiruvchi tekshirgan); chaqiruvchi o'quvchi navbati (L1), kassa qulfi (L4) va hujjat qatorini ushlab turadi.
--   Shart: shu to'lovdan keyin o'quvchi bo'yicha boshqa pul harakati bo'lmagan (avans va fakturalar aynan to'lovdan keyingi
--   holatda). Aks holda rad — tuzatish Direktorning «Qaytarish» amali orqali.
create or replace function app.tuition_reverse_core(p_doc_id text, p_uid text, p_reason text) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_doc public.cash_docs%rowtype; v_pay public.payments%rowtype; v_sid text; v_c0 numeric; v_c1 numeric; v_cr numeric;
  a record; b jsonb; v_paid numeric; v_st text; v_name text; v_ofs boolean; v_pay_id text;
begin
  select * into v_doc from public.cash_docs c where c.id = p_doc_id;
  v_ofs := found and v_doc.op = 'nc_offset' and v_doc."sourceTable" = 'salary_payments';
  if not found or v_doc.status <> 'posted' or not (v_ofs or (v_doc.op = 'in_tuition' and v_doc."sourceTable" = 'payments')) then
    raise exception 'Bu hujjat — amaldagi o''quv to''lovi orderi emas' using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  v_pay_id := case when v_ofs then v_doc."sourceSnapshot" ->> 'paymentId' else v_doc."sourceId" end;
  if coalesce(v_doc."sourceSnapshot" ->> 'allocation', '') <> 'exact' then
    raise exception 'Bu to''lovning taqsimoti aniq emas — avtomatik bekor qilinmaydi (Direktor: «Qaytarish»)' using errcode = 'P0001', hint = 'kassa:not_reversible';
  end if;
  select * into v_pay from public.payments p where p.id = v_pay_id for update;
  if not found or coalesce(v_pay.status, '') <> 'applied' then
    raise exception 'To''lov topilmadi yoki holati o''zgargan (%)', coalesce(v_pay.status, 'yo''q') using errcode = 'P0001', hint = 'kassa:pay_status';
  end if;
  v_sid := case when v_ofs then v_doc."sourceSnapshot" ->> 'studentId' else v_doc."partyId" end;
  v_c0 := coalesce((v_doc."sourceSnapshot" ->> 'creditBefore')::numeric, 0);
  v_c1 := coalesce((v_doc."sourceSnapshot" ->> 'creditAfter')::numeric, 0);
  select c.credit into v_cr from public.student_credit c where c.id = v_sid for update;
  v_cr := coalesce(v_cr, 0);
  if abs(v_cr - v_c1) >= 0.01 then
    raise exception 'Bu to''lovdan keyin o''quvchi avansi o''zgargan — bekor qilib bo''lmaydi (Direktor: «Qaytarish»)' using errcode = 'P0001', hint = 'kassa:later_movement';
  end if;
  -- 1) tekshiruv: har faktura aynan shu to'lovdan keyingi holatda
  for a in select * from public.payment_allocations x where x."paymentId" = v_pay.id and x."invoiceId" is not null loop
    select x into b from jsonb_array_elements(v_doc."sourceSnapshot" -> 'before') x where x ->> 'id' = a."invoiceId";
    select coalesce(i."paidAmount", 0), coalesce(i.status, '') into v_paid, v_st from public.invoices i where i.id = a."invoiceId" for update;
    if not found or b is null or v_st in ('canceled', 'reversed')
       or abs(v_paid - ((b ->> 'paid')::numeric + a."fromCash" + a."fromCredit")) >= 0.01 then
      raise exception 'Bu to''lovdan keyin fakturada o''zgarish bo''lgan — bekor qilib bo''lmaydi (Direktor: «Qaytarish»)' using errcode = 'P0001', hint = 'kassa:later_movement';
    end if;
  end loop;
  -- 2) fakturalar to'lovdan oldingi holatga
  for a in select * from public.payment_allocations x where x."paymentId" = v_pay.id and x."invoiceId" is not null loop
    select x into b from jsonb_array_elements(v_doc."sourceSnapshot" -> 'before') x where x ->> 'id' = a."invoiceId";
    update public.invoices
       set "paidAmount" = (b ->> 'paidRaw')::numeric, status = b ->> 'status', provider = b ->> 'provider', "paidAt" = (b ->> 'paidAt')::timestamptz
     where id = a."invoiceId";
  end loop;
  -- 3) avans to'lovdan oldingi holatga (jurnal bilan)
  if v_c0 <> v_c1 then
    select s.name into v_name from public.students s where s.id = v_sid or s."studentId" = v_sid limit 1;
    insert into public.student_credit (id, "studentId", credit, "updatedAt") values (v_sid, v_sid, v_c0, now())
      on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();
    insert into public.credit_ledger (id, "studentId", "studentName", delta, "balanceAfter", reason, provider, note, "at")
      values (gen_random_uuid()::text, v_sid, coalesce(v_name, ''), v_c0 - v_c1, v_c0, 'manual', case when v_ofs then 'offset' else 'cash' end,
              case when v_ofs then 'O‘zaro hisob bekor qilindi (dalolatnoma № ' else 'Naqd to‘lov bekor qilindi (KO-1 № ' end
                || v_doc.no || '): ' || left(coalesce(p_reason, ''), 200), now());
  end if;
  -- 4) to'lov — bekor qilingan (kirim hisobotlaridan chiqadi); tavsiya bonusi trigger orqali qaytariladi
  update public.payments
     set status = 'canceled',
         raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('voidReason', left(coalesce(p_reason, ''), 500), 'voidedBy', p_uid, 'voidedAt', now())
   where id = v_pay.id;
  -- 5) ota-onaga hali yuborilmagan to'lov xabarnomasi to'xtatiladi
  update public.notify_queue set status = 'skipped', error = 'to''lov bekor qilindi', "processedAt" = now()
   where id = 'pay__' || v_pay.id and status = 'pending';
end $$;
revoke all on function app.tuition_reverse_core(text, text, text) from public, anon, authenticated;

notify pgrst, 'reload schema';
