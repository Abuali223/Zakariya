\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-cp.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-cp.sql — MOLIYA ISH REJASI, 2-BOSQICH (F2.2): KONTRAGENT KARTASI TO'LIQ va RP-10 «KONTRAGENT KO'CHIRMASI».
--   Karta (public.fin_counterparties; ustunlar, cheklovlar va yordamchilar — fin-core.sql): tur, nom, STIR (9 raqam), bank hisob
--   raqami (20 raqam) va MFO kodi (5 raqam), bank nomi, shartnoma (raqami, sanasi, amal qilish muddati), izoh, faollik; versiya (rev).
--   public.fin_cp_save(p)  — kartani saqlash (yangi yoki mavjud), hamma maydonlar bilan:
--     • kim: yangi — kassa operatori, Moliya menejeri, buxgalter, Direktor (fin_counterparty_save bilan bir xil); mavjud — Moliya
--       menejeri, buxgalter, Direktor (fin:cp_rights);
--     • tur tasdig'i (sec-3) — fin_counterparty_save qoidasi: buxgalter yoki Direktor saqlasa — tasdiqlangan; boshqalar turini, nomini
--       yoki STIR'ini o'zgartirsa — tasdiq bekor; rekvizitlar va shartnoma tasdiqqa ta'sir qilmaydi;
--     • takror: yangi karta shu tur, nom kaliti va STIR bilan faol kartada bor bo'lsa — yaratilmaydi, mavjudi qaytadi ("dup": true;
--       qulf kaliti fin_counterparty_save bilan bir xil — ikki yo'ldan bir vaqtda ham bitta karta); mavjud kartani shunday boshqa karta
--       nomiga o'tkazish — rad (fin:cp_dup); shu STIR boshqa faol kartada bo'lsa — ogohlantirish (fin:cp_stir_dup; bank filiallari bir
--       STIR'da bo'lishi mumkin — p.dupOk bilan yoziladi);
--     • bir vaqtda tahrirlash: p.rev — oynadagi karta versiyasi; shu orada boshqa birov saqlagan bo'lsa — rad (fin:cp_changed), javob
--       yo'qolib o'sha ma'lumot qayta yuborilsa — o'sha karta qaytadi ("dup": true).
--   public.fin_cp_statement(id, dan, gacha, fayl) — RP-10 «Kontragent ko'chirmasi» (pul harakati): kontragent bilan barcha to'lovlar
--     va tushumlar — kassa orderlari (KO-1 / KO-2: tomon — kontragent, bank yoki ta'sischi; o'tkazilgan; sinov kassasi va bekor
--     qilinganlari — yo'q), «Buxgalteriya» xarajat hujjatlari (fin_exp_docs: bank, karta, orderisiz naqd; bekor qilinganlari — yo'q) va
--     hujjatsiz eski yozuvlar (expenses: kontragent ko'rsatilgan, kassa orderidan ko'chmagan). Kassa orderidan «Buxgalteriya»ga
--     ko'chgan qatorlar ("cashDocId") qayta sanalmaydi — order o'zi ko'chirmada. Davr boshigacha va davr oxirigacha jamlar (olindi /
--     berildi), davr qatorlari (sana, hujjat, operatsiya, statiyalar, usul, asos / izoh). Hisob-kitob qoldig'i (qarz) — bosh kitob
--     bilan (4-bosqich): bu ko'chirmada faqat pul harakati.
--     Kim: Moliya menejeri, buxgalter, Direktor (fin:cp_rights). Davr — 3 yilgacha (fin:period).
--     Fayl (chop etish, Excel — p_file): FD-28 — jismoniy shaxs / ta'sischi / «boshqa» turidagi kontragent ko'chirmasi Direktordan
--     boshqaga ismsiz (kontragent ID; STIR, hisob raqami, bank, asos / izoh matni — yo'q); yuridik shaxs (yetkazib beruvchi, tashkilot,
--     bank) — to'liq (app.kassa_mask_party qoidasi bilan bir xil).
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi (kassa moduli bilan birga).
-- =====================================================================

-- Ko'chirma so'rovlari uchun indekslar (kassa orderlari — cash_docs_party_idx, kassa.sql)
create index if not exists expenses_cp_idx on public.expenses ("counterpartyId") where "counterpartyId" is not null;
create index if not exists fin_exp_docs_cp_idx on public.fin_exp_docs ("counterpartyId") where "counterpartyId" is not null;

-- Eski yozuv sanasi (matn, ba'zan noto'g'ri yozilgan) → sana; o'qib bo'lmasa — bo'sh (ko'chirma xato bermaydi).
create or replace function app.fin_cp_day(p text) returns date
language plpgsql immutable set search_path = public, app, pg_temp as $$
begin
  if p is null or p !~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$' then return null; end if;
  return to_date(p, 'YYYY-MM-DD');
exception when others then return null;
end $$;
revoke all on function app.fin_cp_day(text) from public, anon, authenticated;

-- ---------- RPC: kartani saqlash ----------
--   p = { id (mavjud karta; yangi — bo'sh), rev (mavjud kartada majburiy), kind, name, stir, account, mfo, bankName, contractNo,
--         contractDate ('YYYY-MM-DD'), contractUntil, note, active, dupOk }
create or replace function public.fin_cp_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_id     text := nullif(btrim(coalesce(p ->> 'id', '')), '');
  v_conf   boolean := app.is_admin() or app.is_accountant();
  v_kind   text := coalesce(p ->> 'kind', '');
  v_name   text := btrim(coalesce(p ->> 'name', ''));
  v_stir   text := app.fin_cp_digits(p ->> 'stir');
  v_acc    text := app.fin_cp_digits(p ->> 'account');
  v_mfo    text := app.fin_cp_digits(p ->> 'mfo');
  v_bank   text := btrim(coalesce(p ->> 'bankName', ''));
  v_cno    text := btrim(regexp_replace(btrim(coalesce(p ->> 'contractNo', '')), '^(№|#)+[[:space:]]*', ''));
  v_cd     text := btrim(coalesce(p ->> 'contractDate', ''));
  v_cu     text := btrim(coalesce(p ->> 'contractUntil', ''));
  v_note   text := btrim(coalesce(p ->> 'note', ''));
  v_dupok  boolean := coalesce(p -> 'dupOk' = 'true'::jsonb, false);
  v_today  date := app.fin_today();
  v_cdate  date; v_cuntil date; v_active boolean; v_key text;
  v_cur    public.fin_counterparties%rowtype; v_ex public.fin_counterparties%rowtype;
begin
  if v_id is null then
    if not (app.is_admin() or app.fin_list2() or app.kassa_operator()) then
      raise exception 'Ruxsat yo''q: kontragentni kassir, Moliya menejeri, buxgalter yoki Direktor qo''shadi' using errcode = '42501', hint = 'fin:cp_rights';
    end if;
  elsif not (app.is_admin() or app.fin_list2()) then
    raise exception 'Ruxsat yo''q: mavjud kontragentni Moliya menejeri, buxgalter yoki Direktor o''zgartiradi' using errcode = '42501', hint = 'fin:cp_rights';
  end if;
  if jsonb_typeof(p) is distinct from 'object' then raise exception 'So''rov noto''g''ri' using errcode = '22023', hint = 'fin:cp_bad'; end if;
  if v_kind not in ('supplier', 'org', 'person', 'bank', 'founder', 'other') then
    raise exception 'Kontragent turi noto''g''ri' using errcode = '22023', hint = 'fin:cp_kind';
  end if;
  if length(v_name) not between 2 and 200 then raise exception 'Kontragent nomi 2–200 belgi bo''lsin' using errcode = '22023', hint = 'fin:cp_name'; end if;
  if v_acc <> '' and v_acc !~ '^[0-9]{20}$' then
    raise exception 'Hisob raqami — 20 ta raqam (hozir: %)', length(v_acc) using errcode = '22023', hint = 'fin:cp_account';
  end if;
  if v_mfo <> '' and v_mfo !~ '^[0-9]{5}$' then raise exception 'Bank MFO kodi — 5 ta raqam' using errcode = '22023', hint = 'fin:cp_mfo'; end if;
  if v_acc <> '' and v_mfo = '' then raise exception 'Hisob raqami bilan bankning MFO kodini ham kiriting' using errcode = '22023', hint = 'fin:cp_mfo'; end if;
  if length(v_bank) > 200 then raise exception 'Bank nomi 200 belgidan oshmasin' using errcode = '22023', hint = 'fin:cp_bank'; end if;
  if length(v_cno) > 60 then raise exception 'Shartnoma raqami 60 belgidan oshmasin' using errcode = '22023', hint = 'fin:cp_contract'; end if;
  if (v_cd <> '' and v_cd !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') or (v_cu <> '' and v_cu !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') then
    raise exception 'Shartnoma sanasi noto''g''ri' using errcode = '22023', hint = 'fin:cp_contract';
  end if;
  begin
    v_cdate := nullif(v_cd, '')::date; v_cuntil := nullif(v_cu, '')::date;
  exception when others then
    raise exception 'Shartnoma sanasi noto''g''ri' using errcode = '22023', hint = 'fin:cp_contract';
  end;
  if v_cno = '' and (v_cdate is not null or v_cuntil is not null) then
    raise exception 'Shartnoma raqamini kiriting (sanasi bor)' using errcode = '22023', hint = 'fin:cp_contract';
  end if;
  if v_cno <> '' and v_cdate is null then raise exception 'Shartnoma sanasini kiriting' using errcode = '22023', hint = 'fin:cp_contract'; end if;
  if v_cdate > v_today then raise exception 'Shartnoma sanasi bugundan keyin bo''lmasin' using errcode = '22023', hint = 'fin:cp_contract'; end if;
  if v_cdate < date '1991-01-01' then raise exception 'Shartnoma sanasi noto''g''ri' using errcode = '22023', hint = 'fin:cp_contract'; end if;
  if v_cuntil < v_cdate then
    raise exception 'Shartnoma muddati uning sanasidan oldin bo''lmasin' using errcode = '22023', hint = 'fin:cp_contract';
  end if;
  if v_cuntil > v_cdate + 18262 then raise exception 'Shartnoma muddati noto''g''ri (50 yildan uzoq)' using errcode = '22023', hint = 'fin:cp_contract'; end if;
  if length(v_note) > 500 then raise exception 'Izoh 500 belgidan oshmasin' using errcode = '22023', hint = 'fin:cp_note'; end if;
  v_active := case when jsonb_typeof(p -> 'active') = 'boolean' then (p ->> 'active')::boolean end;

  if v_id is null then
    -- ---------- yangi karta ----------
    perform app.fin_cp_stir_check(v_stir, null);
    v_key := app.fin_cp_name_key(v_name);
    perform pg_advisory_xact_lock(hashtext('iqror_cp:' || v_kind || '|' || v_key || '|' || v_stir));
    select * into v_ex from public.fin_counterparties c
     where c.active and c.kind = v_kind and c.stir = v_stir and app.fin_cp_name_key(c.name) = v_key
     order by c."createdAt", c.id limit 1;
    if found then
      return to_jsonb(v_ex) || jsonb_build_object('ok', true, 'dup', true, 'confirmed', v_ex."kindConfirmedBy" is not null, 'org', app.kassa_is_org(v_ex.id));
    end if;
    if v_stir <> '' then
      perform pg_advisory_xact_lock(hashtext('iqror_cp_stir:' || v_stir));
      if not v_dupok then
        select * into v_ex from public.fin_counterparties c where c.active and c.stir = v_stir order by c."createdAt", c.id limit 1;
        if found then
          raise exception 'STIR % ro''yxatdagi boshqa kontragentda bor: «%» — o''sha emasmi?', v_stir, v_ex.name
            using errcode = 'P0001', hint = 'fin:cp_stir_dup';
        end if;
      end if;
    end if;
    insert into public.fin_counterparties (id, kind, name, stir, note, active, "createdBy", "kindConfirmedBy", "kindConfirmedAt",
                                           account, mfo, "bankName", "contractNo", "contractDate", "contractUntil")
      values ('cp_' || replace(gen_random_uuid()::text, '-', ''), v_kind, v_name, v_stir, v_note, coalesce(v_active, true), app.uid(),
              case when v_conf then app.uid() end, case when v_conf then now() end,
              v_acc, v_mfo, v_bank, v_cno, v_cdate, v_cuntil)
      returning * into v_cur;
    return to_jsonb(v_cur) || jsonb_build_object('ok', true, 'dup', false, 'confirmed', v_cur."kindConfirmedBy" is not null, 'org', app.kassa_is_org(v_cur.id));
  end if;

  -- ---------- mavjud karta ----------
  select * into v_cur from public.fin_counterparties c where c.id = v_id for update;
  if not found then raise exception 'Kontragent topilmadi' using errcode = '22023', hint = 'fin:not_found'; end if;
  v_active := coalesce(v_active, v_cur.active);
  if coalesce(p ->> 'rev', '') !~ '^[0-9]{1,9}$' then
    raise exception 'Karta versiyasi ko''rsatilmagan — kartani qayta oching' using errcode = '22023', hint = 'fin:cp_changed';
  end if;
  if (p ->> 'rev')::int <> v_cur.rev then
    -- javob yo'qolib o'sha ma'lumot qayta yuborilgan — o'sha karta (yangi versiya yozilmaydi)
    if (v_cur.kind, v_cur.name, v_cur.stir, v_cur.account, v_cur.mfo, v_cur."bankName", v_cur."contractNo", v_cur."contractDate",
        v_cur."contractUntil", v_cur.note, v_cur.active)
       is not distinct from (v_kind, v_name, v_stir, v_acc, v_mfo, v_bank, v_cno, v_cdate, v_cuntil, v_note, v_active) then
      return to_jsonb(v_cur) || jsonb_build_object('ok', true, 'dup', true, 'confirmed', v_cur."kindConfirmedBy" is not null, 'org', app.kassa_is_org(v_cur.id));
    end if;
    raise exception 'Kontragent kartasi shu orada o''zgartirilgan — kartani qayta oching (yangi ma''lumot bilan)' using errcode = 'P0001', hint = 'fin:cp_changed';
  end if;
  perform app.fin_cp_stir_check(v_stir, v_cur.stir);
  v_key := app.fin_cp_name_key(v_name);
  if v_active and (not v_cur.active or v_kind is distinct from v_cur.kind or v_key is distinct from app.fin_cp_name_key(v_cur.name)
                   or v_stir is distinct from v_cur.stir) then
    perform pg_advisory_xact_lock(hashtext('iqror_cp:' || v_kind || '|' || v_key || '|' || v_stir));
    select * into v_ex from public.fin_counterparties c
     where c.active and c.id <> v_cur.id and c.kind = v_kind and c.stir = v_stir and app.fin_cp_name_key(c.name) = v_key
     order by c."createdAt", c.id limit 1;
    if found then
      raise exception 'Bunday kontragent ro''yxatda bor: «%»%', v_ex.name, case when v_ex.stir <> '' then ' (STIR ' || v_ex.stir || ')' else '' end
        using errcode = 'P0001', hint = 'fin:cp_dup';
    end if;
  end if;
  if v_active and v_stir <> '' and (v_stir is distinct from v_cur.stir or not v_cur.active) then
    perform pg_advisory_xact_lock(hashtext('iqror_cp_stir:' || v_stir));
    if not v_dupok then
      select * into v_ex from public.fin_counterparties c where c.active and c.id <> v_cur.id and c.stir = v_stir order by c."createdAt", c.id limit 1;
      if found then
        raise exception 'STIR % ro''yxatdagi boshqa kontragentda bor: «%» — o''sha emasmi?', v_stir, v_ex.name
          using errcode = 'P0001', hint = 'fin:cp_stir_dup';
      end if;
    end if;
  end if;
  update public.fin_counterparties
     set kind = v_kind, name = v_name, stir = v_stir, account = v_acc, mfo = v_mfo, "bankName" = v_bank,
         "contractNo" = v_cno, "contractDate" = v_cdate, "contractUntil" = v_cuntil, note = v_note, active = v_active,
         "kindConfirmedBy" = case when v_conf then app.uid()
                                  when (kind, name, stir) is distinct from (v_kind, v_name, v_stir) then null
                                  else "kindConfirmedBy" end,
         "kindConfirmedAt" = case when v_conf then now()
                                  when (kind, name, stir) is distinct from (v_kind, v_name, v_stir) then null
                                  else "kindConfirmedAt" end,
         rev = rev + 1, "updatedAt" = now(), "updatedBy" = app.uid()
   where id = v_cur.id
   returning * into v_cur;
  return to_jsonb(v_cur) || jsonb_build_object('ok', true, 'dup', false, 'confirmed', v_cur."kindConfirmedBy" is not null, 'org', app.kassa_is_org(v_cur.id));
end $$;
revoke all on function public.fin_cp_save(jsonb) from public, anon;
grant execute on function public.fin_cp_save(jsonb) to authenticated;

-- ---------- RPC: RP-10 kontragent ko'chirmasi ----------
--   Javob: { cp, org, chief, me, from, to, today, masked, opening {in, out}, totals {in, out, n}, closing {in, out}, rows [...],
--            articles {id: {uz, ru}} }
--   rows: { day, src (cash | exp | legacy), ref, doc, method (cash | bank | card | ''), op, opName, opNameRu, arts [statiya], text, in, out } —
--   sana, o'tkazilgan / kiritilgan vaqt va kalit tartibida. in — kontragentdan olingan (KO-1), out — unga berilgan / to'langan.
create or replace function public.fin_cp_statement(p_id text, p_from date, p_to date, p_file boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_cp public.fin_counterparties%rowtype; v_mask boolean; v_j jsonb;
begin
  if not (app.is_admin() or app.fin_list2()) then
    raise exception 'Ruxsat yo''q: kontragent ko''chirmasini Moliya menejeri, buxgalter yoki Direktor ko''radi' using errcode = '42501', hint = 'fin:cp_rights';
  end if;
  select * into v_cp from public.fin_counterparties c where c.id = btrim(coalesce(p_id, ''));
  if not found then raise exception 'Kontragent topilmadi' using errcode = '22023', hint = 'fin:not_found'; end if;
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'Davrni to''g''ri tanlang (boshi oxiridan keyin bo''lmasin)' using errcode = '22023', hint = 'fin:period';
  end if;
  if p_to - p_from > 1100 then raise exception 'Davr 3 yildan oshmasin' using errcode = '22023', hint = 'fin:period'; end if;
  v_mask := coalesce(p_file, false) and not app.is_admin() and v_cp.kind not in ('supplier', 'org', 'bank');

  with src as (
    -- kassa orderlari (naqd): tomon — shu kontragent (kontragent / bank / ta'sischi sifatida)
    select d."businessDay" as day, d."postedAt" as ts, 'cash'::text as src, d.id as ref,
           case d.form when 'KO1' then 'KO-1' else 'KO-2' end || ' № ' || d.no as doc,
           'cash'::text as method, d.op as op, coalesce(r."nameUz", d.op) as op_name, coalesce(nullif(r."nameRu", ''), r."nameUz", d.op) as op_ru,
           coalesce((select jsonb_agg(distinct l."articleId") from public.cash_doc_lines l where l."docId" = d.id and l."articleId" is not null), '[]'::jsonb) as arts,
           d.basis as txt,
           case when d.form = 'KO1' then d.amount else 0 end as amt_in,
           case when d.form = 'KO2' then d.amount else 0 end as amt_out
      from public.cash_docs d
      join public.cash_desks k on k.id = d.desk and not k."isTest"
      left join public.fin_op_rules r on r.op = d.op
     where d."partyType" in ('counterparty', 'bank', 'founder') and d."partyId" = v_cp.id
       and d.status = 'posted' and d.form in ('KO1', 'KO2')
    union all
    -- «Buxgalteriya» xarajat hujjatlari (bank, karta, orderisiz naqd)
    select x.date, x."createdAt", 'exp', x.id,
           btrim(case when x."docNo" <> '' then '№ ' || x."docNo" else '' end
                 || case when x."docDate" is not null then ' · ' || to_char(x."docDate", 'DD.MM.YYYY') else '' end, ' ·'),
           coalesce(x.method, ''), 'expense', 'Xarajat', 'Расход',
           coalesce((select jsonb_agg(distinct l ->> 'articleId') from jsonb_array_elements(x.lines) l where l ->> 'articleId' is not null), '[]'::jsonb),
           x.note, 0, x.amount
      from public.fin_exp_docs x
     where x."counterpartyId" = v_cp.id and x.status = 'posted' and x.origin = 'form'
    union all
    -- hujjatsiz eski yozuvlar (kassa orderidan ko'chmagan)
    select coalesce(app.fin_cp_day(e.date), app.fin_cp_day(e.month || '-01'), (e."createdAt" at time zone 'Asia/Tashkent')::date),
           e."createdAt", 'legacy', e.id, '', coalesce(e.method, ''), 'expense', 'Xarajat', 'Расход',
           case when e."articleId" is not null then jsonb_build_array(e."articleId") else '[]'::jsonb end,
           coalesce(e.note, ''), 0, coalesce(e.amount, 0)
      from public.expenses e
     where e."counterpartyId" = v_cp.id and e."cashDocId" is null and e."expDocId" is null
  )
  select jsonb_build_object(
           'opening', jsonb_build_object('in', coalesce(sum(s.amt_in) filter (where s.day < p_from), 0),
                                         'out', coalesce(sum(s.amt_out) filter (where s.day < p_from), 0)),
           'totals', jsonb_build_object('in', coalesce(sum(s.amt_in) filter (where s.day between p_from and p_to), 0),
                                        'out', coalesce(sum(s.amt_out) filter (where s.day between p_from and p_to), 0),
                                        'n', count(*) filter (where s.day between p_from and p_to)),
           'closing', jsonb_build_object('in', coalesce(sum(s.amt_in) filter (where s.day <= p_to), 0),
                                         'out', coalesce(sum(s.amt_out) filter (where s.day <= p_to), 0)),
           'rows', coalesce(jsonb_agg(jsonb_build_object('day', s.day, 'src', s.src, 'ref', s.ref, 'doc', s.doc, 'method', s.method, 'op', s.op,
                                                         'opName', s.op_name, 'opNameRu', s.op_ru, 'arts', s.arts, 'text', case when v_mask then '' else coalesce(s.txt, '') end,
                                                         'in', s.amt_in, 'out', s.amt_out) order by s.day, s.ts, s.ref)
                              filter (where s.day between p_from and p_to), '[]'::jsonb),
           'articles', coalesce((select jsonb_object_agg(a.id, jsonb_build_object('uz', a."nameUz", 'ru', a."nameRu")) from public.fin_articles a
                                  where a.id in (select jsonb_array_elements_text(s2.arts) from src s2 where s2.day between p_from and p_to)), '{}'::jsonb))
    into v_j
    from src s;

  return v_j || jsonb_build_object(
    'cp', case when v_mask
               then jsonb_build_object('id', v_cp.id, 'kind', v_cp.kind, 'contractNo', v_cp."contractNo", 'contractDate', v_cp."contractDate",
                                       'contractUntil', v_cp."contractUntil", 'active', v_cp.active)
               else jsonb_build_object('id', v_cp.id, 'kind', v_cp.kind, 'name', v_cp.name, 'stir', v_cp.stir, 'account', v_cp.account,
                                       'mfo', v_cp.mfo, 'bankName', v_cp."bankName", 'contractNo', v_cp."contractNo",
                                       'contractDate', v_cp."contractDate", 'contractUntil', v_cp."contractUntil", 'active', v_cp.active,
                                       'confirmed', v_cp."kindConfirmedBy" is not null) end,
    'org', (select jsonb_build_object('nameUz', o."nameUz", 'nameRu', o."nameRu", 'stir', o.stir, 'place', o.place, 'printLang', o."printLang")
              from public.fin_org o where o.id = 'main'),
    -- bosh buxgalter (2-ro'yxat imzo egasi — bitta bo'lsa; chop etishda imzo qatoriga)
    'chief', (select case when count(*) = 1 then max(s."fullName") end from public.fin_signatories s where s.list = 2 and s.active),
    'me', app.fin_exp_who(app.uid()),   -- chop etishda «Tuzdi» (ism — xodim kartasidan, email emas)
    'from', p_from, 'to', p_to, 'today', app.fin_today(), 'masked', v_mask);
end $$;
revoke all on function public.fin_cp_statement(text, date, date, boolean) from public, anon;
grant execute on function public.fin_cp_statement(text, date, date, boolean) to authenticated;
