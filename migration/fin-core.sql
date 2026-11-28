\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-core.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-core.sql — MOLIYA ISH REJASI, 1a-BOSQICH POYDEVORI (docs/moliya/buxgalteriya-ish-reja.md: F1.1).
--   Ma'lumotnomalar: hisobvaraqlar rejasi (BHMS 21), statiyalar, kassa operatsiyalari qoidalari, tashkilot sozlamalari
--   (T1, L1, limit, chop etish tili, kassaGoLive), imzo ro'yxatlari, kontragentlar, kassalar, hujjat raqamlari hisoblagichi.
--   Boshlang'ich ma'lumot — fin-seed.sql (ON CONFLICT DO NOTHING: buxgalter o'zgartirgani qayta yozilmaydi).
--
--   XAVFSIZLIK: barcha jadvallarda RLS; mijoz (anon/authenticated) faqat O'QIYDI (kassa/moliya rollari), yozish — faqat
--   SECURITY DEFINER RPC orqali (aniq rol tekshiruvi, search_path qat'iy). supabase-grants.sql har deployda barcha jadvalga
--   DML beradi — shu fayl har safar qaytarib oladi.
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi (chain.sh --dev faqat lokal sinovda).
-- =====================================================================

-- (Moliya soati — app.fin_now() / app.fin_today() — fin-prereq.sql da: jonli bazada doim now().)

-- ---------- Rol yordamchilari (rls-initplan.sql v_fns ro'yxatida ham bor) ----------
-- Buxgalter — faqat ASOSIY rol (qo'shimcha lavozim bo'lmaydi; is_staff / is_finance tarkibiga kirmaydi — D6).
create or replace function app.is_accountant() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(app.my_role() = 'accountant', false)
$$;
-- Kassa operatori: naqd pulni qabul qiladi va beradi (kassir — qo'shimcha lavozim bo'lishi ham mumkin; g'aznachi).
create or replace function app.kassa_operator() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(app.is_cashier() or app.my_role() = 'treasurer', false)
$$;
-- 2-ro'yxat (buxgalteriya / moliya imzosi): Moliya menejeri yoki buxgalter. Direktor — 1-ro'yxat.
create or replace function app.fin_list2() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(app.my_role() in ('finance_mgr', 'accountant'), false)
$$;
-- Kassa hujjatlarini ko'ra oladiganlar: operator, moliya (Moliya menejeri, g'aznachi), buxgalter, Direktor.
create or replace function app.kassa_reader() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(app.is_admin() or app.is_finance() or app.is_cashier() or app.is_accountant(), false)
$$;

-- ---------- Ma'lumotnoma jadvallari ----------
create table if not exists public.gl_accounts (
  code        text primary key,                  -- BHMS 21 to'rt xonali kod (balansdan tashqari — uch xonali)
  "nameUz"    text not null,
  "nameRu"    text not null default '',
  kind        text not null check (kind in ('A', 'P', 'KA', 'T', 'BT', 'X')),   -- aktiv / passiv / kontraktiv / tranzit / balansdan tashqari / texnik
  analytics   text[] not null default '{}',      -- S o'quvchi, P to'lovchi turi, E xodim, C kontragent, K kassa, B bank, CH kanal, A statiya …
  note        text not null default '',
  active      boolean not null default true,
  "sortOrder" int not null default 0
);
create table if not exists public.fin_articles (
  id               text primary key,             -- 'IN-01' / 'EX-20' / 'OP-06'
  kind             text not null check (kind in ('IN', 'EX', 'OP')),
  "nameUz"         text not null,
  "nameRu"         text not null default '',
  "accountCode"    text,                         -- standart hisobvaraq (EX: debet; IN: kredit; OP: asosiy tomon)
  "form2Line"      text not null default '',     -- Moliyaviy natijalar (2-shakl) satri
  "cfLine"         text not null default '',     -- Pul oqimi (BHMS 9) satri: 'O·020', 'I·060', 'F·150', 'ichki' …
  "cashOutAllowed" boolean not null default false,   -- KO-2 «Xarajat»da tanlash mumkinmi (maosh, soliq, eskirish — yo'q)
  "needsNote"      boolean not null default false,   -- izoh majburiy («Boshqa»)
  active           boolean not null default true,
  "sortOrder"      int not null default 0
);
create table if not exists public.fin_category_map (   -- «Buxgalteriya»dagi eski 21 toifa -> standart statiya
  category    text primary key,
  "articleId" text not null
);
create table if not exists public.fin_op_rules (
  op               text primary key,             -- 'in_tuition', 'out_expense' …
  form             text not null check (form in ('KO1', 'KO2', 'ACT')),
  "nameUz"         text not null,
  "nameRu"         text not null default '',
  debit            text,                         -- qat'iy debet (KO-1: 5010); bo'sh — statiya hisobvarag'i
  credit           text,                         -- qat'iy kredit (KO-2: 5010); bo'sh — statiya / hujjat qatoridan
  "articleMode"    text not null check ("articleMode" in ('fixed', 'choose', 'none')),
  "articleId"      text,                         -- 'fixed' bo'lsa
  "partyTypes"     text[] not null default '{}', -- student / employee / counterparty / bank / founder / other
  "needsApproval"  boolean not null default false,   -- KO-2: to'lovdan oldin 2-ro'yxat tasdig'i
  "directorAlways" boolean not null default false,   -- summadan qat'i nazar Direktor ruxsati
  "systemOnly"     boolean not null default false,   -- faqat tizim yaratadi (kun yopishdagi farq)
  "fiscalRequired" boolean not null default false,   -- aholidan naqd: fiskal chek № majburiy
  "allowedArticles" text[] not null default '{}',    -- 'choose': ruxsat etilgan statiyalar (bo'sh — "cashOutAllowed" bo'lgan barcha statiyalar)
  "accountByParty" jsonb not null default '{}'::jsonb,   -- tomon turiga qarab hisobvaraq: {"employee":"4290","founder":"4890"}
  manual           boolean not null default true,    -- «+ Kirim» / «+ Chiqim» shaklidan kiritiladi
  active           boolean not null default true,
  "sortOrder"      int not null default 0
);
-- Fiskal chek tomon turiga qarab (g8): shu tomon turlaridan naqd kirimda fiskal chek № majburiy ("fiscalRequired" bo'lmasa ham) —
--   «Boshqa kirim» o'quvchi / boshqa shaxsdan (aholidan) — ha, kontragent va xodimdan — yo'q (kassa-docs.sql: kassa_doc_build).
alter table public.fin_op_rules add column if not exists "fiscalParties" text[] not null default '{}';
create table if not exists public.fin_org (
  id            text primary key,
  "nameUz"      text not null default '',
  "nameRu"      text not null default '',
  stir          text not null default '',
  place         text not null default '',
  "printLang"   text not null default 'uz-cyrl' check ("printLang" in ('uz-cyrl', 'uz-latn', 'ru')),
  t1            numeric not null default 0 check (t1 >= 0 and t1 < 1e12),            -- KO-2: shundan katta summa — Direktor ham (0 — har doim)
  l1            numeric not null default 0 check (l1 >= 0 and l1 < 1e12),            -- asos hujjatisiz naqd xarid chegarasi
  "cashLimit"   numeric not null default 0 check ("cashLimit" >= 0 and "cashLimit" < 1e12),   -- kassa limiti (0 — kelishilmagan)
  "kassaGoLive" date,                             -- shu kundan naqd pul faqat kassa hujjati bilan (bo'sh — hali ishga tushmagan)
  extra         jsonb not null default '{}'::jsonb,
  "updatedAt"   timestamptz not null default now(),
  "updatedBy"   text
);
alter table public.fin_org add column if not exists "lockedThrough" date;   -- shu sanagacha (shu kun ham) davr yopilgan: fin-period.sql
insert into public.fin_org (id) values ('main') on conflict (id) do nothing;
create table if not exists public.fin_signatories (
  id          text primary key,
  list        int not null check (list in (1, 2)),   -- 1 — rahbariyat, 2 — buxgalteriya / moliya
  uid         text,                                   -- tizim foydalanuvchisi (bo'lsa)
  title       text not null default '',               -- lavozim (chop etish uchun)
  "fullName"  text not null default '',
  active      boolean not null default true,
  "createdAt" timestamptz not null default now()
);
create table if not exists public.fin_counterparties (
  id          text primary key,
  kind        text not null check (kind in ('supplier', 'org', 'person', 'bank', 'founder', 'other')),
  name        text not null check (length(btrim(name)) between 2 and 200),
  stir        text not null default '',
  note        text not null default '',
  active      boolean not null default true,
  "createdAt" timestamptz not null default now(),
  "createdBy" text
);
-- Kontragent turining tasdig'i (sec-3): tur yuridik shaxsga kassadan naqd to'lovda Direktor qoidasini hal qiladi (F1.27; kassa-docs.sql:
--   app.kassa_is_org). Turni buxgalter yoki Direktor kiritgan / o'zgartirgan / tasdiqlagan bo'lsa — tasdiqlangan; kassir yoki Moliya
--   menejeri kiritgan yoki turini, nomini, STIR'ini o'zgartirgan kontragent — tasdiqlanmagan: «Jismoniy shaxs» / «Boshqa» turi tasdiqlanguncha
--   yuridik shaxs hisoblanadi (Direktor tasdig'i kerak).
alter table public.fin_counterparties add column if not exists "kindConfirmedBy" text;
alter table public.fin_counterparties add column if not exists "kindConfirmedAt" timestamptz;
-- Kontragent kartasi to'liq (F2.2; kartani saqlash va RP-10 ko'chirmasi — fin-cp.sql): bank rekvizitlari (hisob raqami — 20 raqam,
--   bank MFO kodi — 5 raqam; hisob raqami MFO'siz bo'lmaydi, MFO yolg'iz — bank kontragentida bo'lishi mumkin), shartnoma (raqami va
--   sanasi birga; amal qilish muddati — ixtiyoriy, sanasidan oldin emas); rev — karta versiyasi (har saqlashda +1: bir vaqtda ikki
--   kishi tahrirlasa, keyingisi eskirgan karta bilan yozmaydi — fin:cp_changed); kim va qachon oxirgi marta o'zgartirgan.
--   STIR — 9 raqam: jadval cheklovi emas (eski kartalarda boshqacha yozilgan bo'lishi mumkin — ular boshqa maydoni o'zgarganda ham
--   saqlanadi), saqlash funksiyalari yangi yoki o'zgargan STIR'ni tekshiradi (app.fin_cp_stir_check).
alter table public.fin_counterparties add column if not exists account         text not null default '';
alter table public.fin_counterparties add column if not exists mfo             text not null default '';
alter table public.fin_counterparties add column if not exists "bankName"      text not null default '';
alter table public.fin_counterparties add column if not exists "contractNo"    text not null default '';
alter table public.fin_counterparties add column if not exists "contractDate"  date;
alter table public.fin_counterparties add column if not exists "contractUntil" date;
alter table public.fin_counterparties add column if not exists rev             int not null default 0;
alter table public.fin_counterparties add column if not exists "updatedAt"     timestamptz;
alter table public.fin_counterparties add column if not exists "updatedBy"     text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'fin_counterparties_bank_chk' and conrelid = 'public.fin_counterparties'::regclass) then
    alter table public.fin_counterparties add constraint fin_counterparties_bank_chk
      check ((mfo = '' or mfo ~ '^[0-9]{5}$') and (account = '' or (account ~ '^[0-9]{20}$' and mfo <> '')) and length("bankName") <= 200);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'fin_counterparties_contract_chk' and conrelid = 'public.fin_counterparties'::regclass) then
    alter table public.fin_counterparties add constraint fin_counterparties_contract_chk
      check (("contractNo" = '' and "contractDate" is null and "contractUntil" is null)
             or ("contractNo" <> '' and length("contractNo") <= 60 and "contractDate" is not null
                 and ("contractUntil" is null or "contractUntil" >= "contractDate")));
  end if;
end $$;
create table if not exists public.cash_desks (
  id       text primary key,
  name     text not null,
  "isTest" boolean not null default false,   -- sinov kassasi: o'z raqamlari, hisobotlarga kirmaydi
  active   boolean not null default true
);
insert into public.cash_desks (id, name, "isTest") values ('main', 'Asosiy kassa', false), ('sinov', 'Sinov kassasi', true)
  on conflict (id) do nothing;
-- Hujjat raqamlari: sequence / identity EMAS (ROLLBACK raqam «yeb» qo'ymasin) — qator qulfi bilan, o'tkazishning oxirgi qadami.
create table if not exists public.doc_counters (
  desk     text not null,
  series   text not null,          -- 'KO1' / 'KO2' / 'KO4' (varaq) / 'ACT' (Д-) / 'OFS' (ЎҲ-, o'zaro hisob) / 'ADV' (А-, avans hisoboti)
  year     int  not null,
  "lastNo" int  not null default 0 check ("lastNo" >= 0),
  primary key (desk, series, year)
);

-- ---------- RLS: faqat o'qish (kassa/moliya rollari); yozish — RPC ----------
do $$ declare t text; begin
  foreach t in array array['gl_accounts', 'fin_articles', 'fin_category_map', 'fin_op_rules', 'fin_org', 'fin_signatories',
                           'fin_counterparties', 'cash_desks', 'doc_counters'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    if t <> 'doc_counters' then
      execute format('grant select on table public.%I to authenticated', t);
      execute format('create policy %I on public.%I for select using (app.kassa_reader())', t || '_sel', t);
    end if;
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;

-- ---------- Sozlamalar RPC'lari ----------
-- Tashkilot sozlamalari — FAQAT Direktor (T1, L1, limit, kassaGoLive va rekvizitlar). Faqat berilgan maydonlar o'zgaradi.
--   orgCashMax (extra) — yuridik shaxs kontragentga (yetkazib beruvchi / tashkilot) kassadan naqd to'lovda Direktor tasdig'isiz
--   chegara (so'm; 0 yoki yo'q — har doim Direktor). Hisob siyosati qarori (F1.27, buxgalter ko'rigi M3).
--   depositDays / depositKeep (extra; Sh-8 B15 — buxgalter: inkassatsiya har juma; egasi qarori 2026-11-26): naqd pulni bankka
--   topshirish kunlari (ISO hafta kunlari 1–7, takrorsiz; bo'sh massiv — jadval yo'q; kalit yo'q — juma) va topshirilgandan keyin
--   kassada qoldiriladigan summa (maydalik). Eslatma, nazorat va limit tavsiyasi — kassa-day.sql: app.kassa_deposit_cfg.
--   advDays / advBlock (extra; F2.6b, FD-14): avans hisoboti muddati — maktab ish kunlarida (1–30; kalit yo'q — 3) va muddati o'tgan
--   yopilmagan avansi bor xodimga yangi «Hisobdorga avans»ni bloklash (true — so'rov ham, pul berish ham rad; kalit yo'q — false,
--   faqat ogohlantirish). Qo'llanishi — kassa-docs.sql: app.kassa_adv_days, app.kassa_adv_block.
--   directGuard (extra; F2.9, «Huquqlar II»): pul jadvallariga to'g'ridan-to'g'ri yozuv QULFI (true — detektor yozuvni rad etadi;
--   false / kalit yo'q — faqat jurnalga yozadi). Yoqish — «7 kun 0 yozuv» sharti bilan (fin-guard.sql: app.fin_guard_check);
--   o'chirish (orqaga qaytarish) — doim. guardSince (extra) — detektor o'rnatilgan kun, faqat fin-guard.sql qo'yadi.
--   kassaGoLive o'zgarsa — kassa-day.sql: app.kassa_golive_guard (modulning shu qismi o'rnatilgan bo'lsa): ishlagan kassada kelgan sanani
--   bo'shatish / surish — kassani TO'XTATISH (ochiq kun va pul berilmagan so'rovlar bo'lmasa; sana bo'sh saqlanadi), to'xtatilgan kassada —
--   faqat qayta ishga tushirish kuniga (ishga-tushirish §9; ui-5). O'zgarish kun jurnaliga yoziladi.
create or replace function public.fin_org_set(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare k text; v_num numeric; r public.fin_org%rowtype; v_live date; v_rec jsonb; v_new date;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: faqat Direktor' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'fin_org_set: obyekt kerak' using errcode = '22023'; end if;
  select * into r from public.fin_org where id = 'main' for update;
  for k in select jsonb_object_keys(p) loop
    if k in ('nameUz', 'nameRu', 'stir', 'place') then
      if length(coalesce(p ->> k, '')) > 300 then raise exception 'fin_org_set: % juda uzun', k using errcode = '22023'; end if;
    elsif k = 'printLang' then
      if coalesce(p ->> k, '') not in ('uz-cyrl', 'uz-latn', 'ru') then raise exception 'fin_org_set: printLang noto''g''ri' using errcode = '22023'; end if;
    elsif k in ('t1', 'l1', 'cashLimit', 'orgCashMax', 'depositKeep') then
      begin v_num := (p ->> k)::numeric; exception when others then raise exception 'fin_org_set: % son emas', k using errcode = '22023'; end;
      if v_num is null or v_num = 'NaN'::numeric or v_num < 0 or v_num >= 1e12 then raise exception 'fin_org_set: % noto''g''ri', k using errcode = '22023'; end if;
    elsif k = 'kassaGoLive' then
      if p -> k <> 'null'::jsonb and coalesce(p ->> k, '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'fin_org_set: kassaGoLive sana emas' using errcode = '22023'; end if;
    elsif k = 'depositDays' then
      -- (ikki bosqichda: massiv emas qiymatda jsonb_array_* xato beradi, SQL'da «or» tartibi kafolatlanmagan)
      if jsonb_typeof(p -> k) is distinct from 'array' then
        raise exception 'fin_org_set: depositDays — hafta kunlari ro''yxati (1–7, takrorsiz)' using errcode = '22023';
      end if;
      if jsonb_array_length(p -> k) > 7
         or exists (select 1 from jsonb_array_elements(p -> k) x where jsonb_typeof(x) <> 'number' or (x #>> '{}') !~ '^[1-7]$')
         or (select count(distinct x #>> '{}') from jsonb_array_elements(p -> k) x) <> jsonb_array_length(p -> k) then
        raise exception 'fin_org_set: depositDays — hafta kunlari ro''yxati (1–7, takrorsiz)' using errcode = '22023';
      end if;
    elsif k = 'advDays' then
      if jsonb_typeof(p -> k) is distinct from 'number' or (p ->> k) !~ '^[0-9]{1,2}$' or (p ->> k)::int not between 1 and 30 then
        raise exception 'fin_org_set: advDays — avans hisoboti muddati, ish kunlarida (1–30)' using errcode = '22023';
      end if;
    elsif k = 'advBlock' then
      if jsonb_typeof(p -> k) is distinct from 'boolean' then raise exception 'fin_org_set: advBlock — true yoki false' using errcode = '22023'; end if;
    elsif k = 'directGuard' then
      if jsonb_typeof(p -> k) is distinct from 'boolean' then raise exception 'fin_org_set: directGuard — true yoki false' using errcode = '22023'; end if;
    else
      raise exception 'fin_org_set: noma''lum maydon %', k using errcode = '22023';
    end if;
  end loop;
  if p ? 'kassaGoLive' then
    v_new := nullif(p ->> 'kassaGoLive', '')::date;
    if v_new is distinct from r."kassaGoLive" and to_regprocedure('app.kassa_golive_guard(date,date)') is not null then
      execute 'select app.kassa_golive_guard($1, $2)' into v_new using r."kassaGoLive", v_new;
    end if;
  end if;
  -- Qulfni yoqish (o'chiq holatdan) — «7 kun 0 yozuv» sharti (fin-guard.sql: app.fin_guard_check); o'chirish — doim mumkin.
  if p ? 'directGuard' and (p ->> 'directGuard')::boolean and coalesce(r.extra ->> 'directGuard', '') <> 'true' then
    if to_regprocedure('app.fin_guard_check()') is null then
      raise exception 'fin_org_set: to''g''ridan-to''g''ri yozuv detektori o''rnatilmagan' using errcode = 'P0001', hint = 'fin:guard_missing';
    end if;
    execute 'select app.fin_guard_check()';
  end if;
  update public.fin_org set
    "nameUz"      = case when p ? 'nameUz' then coalesce(p ->> 'nameUz', '') else "nameUz" end,
    "nameRu"      = case when p ? 'nameRu' then coalesce(p ->> 'nameRu', '') else "nameRu" end,
    stir          = case when p ? 'stir' then coalesce(p ->> 'stir', '') else stir end,
    place         = case when p ? 'place' then coalesce(p ->> 'place', '') else place end,
    "printLang"   = case when p ? 'printLang' then p ->> 'printLang' else "printLang" end,
    t1            = case when p ? 't1' then (p ->> 't1')::numeric else t1 end,
    l1            = case when p ? 'l1' then (p ->> 'l1')::numeric else l1 end,
    "cashLimit"   = case when p ? 'cashLimit' then (p ->> 'cashLimit')::numeric else "cashLimit" end,
    "kassaGoLive" = case when p ? 'kassaGoLive' then v_new else "kassaGoLive" end,
    extra         = extra
                    || case when p ? 'orgCashMax' then jsonb_build_object('orgCashMax', (p ->> 'orgCashMax')::numeric) else '{}'::jsonb end
                    || case when p ? 'depositKeep' then jsonb_build_object('depositKeep', (p ->> 'depositKeep')::numeric) else '{}'::jsonb end
                    || case when p ? 'depositDays' then jsonb_build_object('depositDays', (select coalesce(jsonb_agg((x #>> '{}')::int order by (x #>> '{}')::int), '[]'::jsonb)
                                                                                             from jsonb_array_elements(p -> 'depositDays') x)) else '{}'::jsonb end
                    || case when p ? 'advDays' then jsonb_build_object('advDays', (p ->> 'advDays')::int) else '{}'::jsonb end
                    || case when p ? 'advBlock' then jsonb_build_object('advBlock', (p ->> 'advBlock')::boolean) else '{}'::jsonb end
                    || case when p ? 'directGuard' then jsonb_build_object('directGuard', (p ->> 'directGuard')::boolean) else '{}'::jsonb end,
    "updatedAt"   = now(), "updatedBy" = app.uid()
  where id = 'main';
  -- Ishga tushadigan kun bugungi yoki o'tgan kunga qo'yilsa: shu kundan beri kassa orderisiz naqd yozuv (o'quv to'lovi, xarajat,
  --   maosh, avans, qaytarish) bo'lmasligi kerak — aks holda ular abadiy «kassa hujjatisiz naqd harakat» bo'lib qoladi (moslik
  --   P1 / P4 / P5 / P8). Bunday yozuv bo'lsa sana ulardan keyingi kunga qo'yiladi (ular boshlang'ich qoldiq sanashiga kiradi).
  --   Tekshiruv kassa-links.sql dagi app.kassa_reconcile bilan (modulning shu qismi o'rnatilgan bo'lsa).
  if p ? 'kassaGoLive' then
    select o."kassaGoLive" into v_live from public.fin_org o where o.id = 'main';
    if v_live is not null and v_live is distinct from r."kassaGoLive" and v_live <= app.fin_today()
       and to_regprocedure('app.kassa_reconcile(date,date)') is not null then
      execute 'select app.kassa_reconcile($1, $2)' into v_rec using v_live, app.fin_today();
      if coalesce((v_rec ->> 'total')::int, 0) > 0 then
        raise exception 'Kassani % dan ishga tushirib bo''lmaydi: shu kundan beri kassa orderisiz naqd yozuvlar bor (o''quv to''lovi: %, xarajat: %, maosh / avans: %, qaytarish: %; jami moslik farqi: %). Ishga tushadigan kunni shu yozuvlardan keyingi kunga qo''ying',
          to_char(v_live, 'DD.MM.YYYY'), coalesce(v_rec #>> '{p1,pay}', '0'), coalesce(v_rec #>> '{p4,row}', '0'),
          coalesce(v_rec #>> '{p5,row}', '0'), coalesce(v_rec #>> '{p8,row}', '0'), coalesce(v_rec ->> 'total', '0')
          using errcode = 'P0001', hint = 'kassa:live_gap';
      end if;
    end if;
  end if;
  return (select to_jsonb(o) from public.fin_org o where o.id = 'main');
end $$;
revoke all on function public.fin_org_set(jsonb) from public, anon;
grant execute on function public.fin_org_set(jsonb) to authenticated;

-- Kontragent (yetkazib beruvchi, tashkilot, bank, ta'sischi, boshqa): kassa operatori, 2-ro'yxat yoki Direktor qo'shadi;
--   mavjudini 2-ro'yxat yoki Direktor o'zgartiradi. Kalit serverda beriladi.
--   Tur tasdig'i (sec-3): buxgalter yoki Direktor saqlasa — tur tasdiqlangan (kim, qachon); kassir yoki Moliya menejeri qo'shgan kontragent —
--   tasdiqlanmagan, mavjudining turi, nomi yoki STIR'i ular tomonidan o'zgarsa — tasdiq bekor bo'ladi (izoh va «faol» belgisi tasdiqqa
--   ta'sir qilmaydi). Tasdiqlanmagan «Jismoniy shaxs» / «Boshqa» — yuridik shaxs hisoblanadi (kassa-docs.sql: app.kassa_is_org).
--   Takror (ui-13): yangi kontragent shu tur, me'yorlangan nom (bo'shliqlar, katta-kichik harf, apostrof turlari) va STIR bilan faol
--   kontragent bor bo'lsa yaratilmaydi — mavjudi qaytadi ("dup": true; «Qo'shish»ni ikki marta bosish, javob yo'qolib qayta yuborish).
--   Bir vaqtdagi ikki chaqiruv shu kalit bo'yicha navbatga turadi (qulf) — ikkinchisi birinchisi yozganini ko'radi.
--   F2.2: STIR — bo'shliqlarsiz, 9 raqam (yangi yoki o'zgargan qiymat; app.fin_cp_stir_check); mavjudini o'zgartirish karta versiyasini
--   oshiradi (rev) va kim / qachon o'zgartirganini yozadi. Bank rekvizitlari va shartnoma bu funksiyada o'zgarmaydi — kartani saqlash
--   (fin-cp.sql: fin_cp_save; takror kaliti va qulfi — shu funksiya bilan bir xil).

-- Kontragent rekvizitlari uchun yordamchilar (F2.2): kiritilgan raqamdan bo'shliqlar (oddiy, bo'linmas, tor) olib tashlanadi — boshqa
--   belgi qolsa, tekshiruv rad etadi; nom kaliti — takrorni aniqlash (bo'shliqlar, katta-kichik harf, apostrof turlari).
create or replace function app.fin_cp_digits(p text) returns text
language sql immutable set search_path = public, app, pg_temp as $$
  select regexp_replace(translate(coalesce(p, ''), chr(160) || chr(8199) || chr(8239), '   '), '[[:space:]]+', '', 'g')
$$;
create or replace function app.fin_cp_name_key(p text) returns text
language sql immutable set search_path = public, app, pg_temp as $$
  select lower(regexp_replace(translate(btrim(coalesce(p, '')), '‘’ʻʼ`´', repeat(chr(39), 6)), '\s+', ' ', 'g'))
$$;
-- STIR: bo'sh yoki 9 raqam (yuridik shaxs, YaTT). Jismoniy shaxsning JShShIR'i (14 raqam) saqlanmaydi — shaxsiy ma'lumot. p_old —
--   kartadagi hozirgi qiymat: o'zgarmagan eski qiymat (bu tekshiruvdan oldin yozilgan) rad etilmaydi.
create or replace function app.fin_cp_stir_check(p_new text, p_old text) returns void
language plpgsql immutable set search_path = public, app, pg_temp as $$
begin
  if coalesce(p_new, '') <> '' and p_new !~ '^[0-9]{9}$' and p_new is distinct from p_old then
    raise exception 'STIR — 9 ta raqam (yuridik shaxs yoki YaTT); jismoniy shaxsning JShShIR''i (14 raqam) kiritilmaydi'
      using errcode = '22023', hint = 'fin:cp_stir';
  end if;
end $$;
revoke all on function app.fin_cp_digits(text) from public, anon, authenticated;
revoke all on function app.fin_cp_name_key(text) from public, anon, authenticated;
revoke all on function app.fin_cp_stir_check(text, text) from public, anon, authenticated;

create or replace function public.fin_counterparty_save(p_id text, p_kind text, p_name text, p_stir text default '', p_note text default '', p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_id text := nullif(btrim(coalesce(p_id, '')), ''); v_conf boolean := app.is_admin() or app.is_accountant();
        v_name text := btrim(coalesce(p_name, '')); v_stir text := app.fin_cp_digits(p_stir); v_key text; v_ex text; v_old text;
begin
  if not (app.is_admin() or app.fin_list2() or app.kassa_operator()) then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  if coalesce(p_kind, '') not in ('supplier', 'org', 'person', 'bank', 'founder', 'other') then raise exception 'Kontragent turi noto''g''ri' using errcode = '22023'; end if;
  if length(v_name) not between 2 and 200 then raise exception 'Kontragent nomi 2–200 belgi bo''lsin' using errcode = '22023'; end if;
  if v_id is null then
    perform app.fin_cp_stir_check(v_stir, null);
    v_key := app.fin_cp_name_key(v_name);
    perform pg_advisory_xact_lock(hashtext('iqror_cp:' || p_kind || '|' || v_key || '|' || v_stir));
    select c.id into v_ex from public.fin_counterparties c
     where c.active and c.kind = p_kind and c.stir = v_stir and app.fin_cp_name_key(c.name) = v_key
     order by c."createdAt", c.id limit 1;
    if v_ex is not null then
      return (select to_jsonb(c) from public.fin_counterparties c where c.id = v_ex) || jsonb_build_object('dup', true);
    end if;
    v_id := 'cp_' || replace(gen_random_uuid()::text, '-', '');
    insert into public.fin_counterparties (id, kind, name, stir, note, active, "createdBy", "kindConfirmedBy", "kindConfirmedAt")
      values (v_id, p_kind, v_name, v_stir, left(coalesce(p_note, ''), 500), true, app.uid(),
              case when v_conf then app.uid() end, case when v_conf then now() end);
  else
    if not (app.is_admin() or app.fin_list2()) then raise exception 'Ruxsat yo''q: mavjud kontragentni Moliya menejeri, buxgalter yoki Direktor o''zgartiradi' using errcode = '42501'; end if;
    select c.stir into v_old from public.fin_counterparties c where c.id = v_id for update;
    if not found then raise exception 'Kontragent topilmadi' using errcode = '22023'; end if;
    perform app.fin_cp_stir_check(v_stir, v_old);
    update public.fin_counterparties
       set kind = p_kind, name = v_name, stir = v_stir, note = left(coalesce(p_note, ''), 500), active = coalesce(p_active, true),
           "kindConfirmedBy" = case when v_conf then app.uid()
                                    when kind is distinct from p_kind or name is distinct from v_name or stir is distinct from v_stir then null
                                    else "kindConfirmedBy" end,
           "kindConfirmedAt" = case when v_conf then now()
                                    when kind is distinct from p_kind or name is distinct from v_name or stir is distinct from v_stir then null
                                    else "kindConfirmedAt" end,
           rev = rev + 1, "updatedAt" = now(), "updatedBy" = app.uid()
     where id = v_id;
  end if;
  return (select to_jsonb(c) from public.fin_counterparties c where c.id = v_id);
end $$;
revoke all on function public.fin_counterparty_save(text, text, text, text, text, boolean) from public, anon;
grant execute on function public.fin_counterparty_save(text, text, text, text, text, boolean) to authenticated;

-- Kontragent turini tasdiqlash (sec-3): FAQAT buxgalter yoki Direktor. p_kind / p_name — tasdiqlovchi ekranda ko'rgan tur va nom: shu orada
--   o'zgargan bo'lsa — rad (sahifani yangilab, qayta ko'rib chiqiladi). Allaqachon tasdiqlangan — takror (o'zgarishsiz).
create or replace function public.fin_counterparty_confirm(p_id text, p_kind text, p_name text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_c public.fin_counterparties%rowtype;
begin
  if not (app.is_admin() or app.is_accountant()) then
    raise exception 'Ruxsat yo''q: kontragent turini buxgalter yoki Direktor tasdiqlaydi' using errcode = '42501';
  end if;
  select * into v_c from public.fin_counterparties c where c.id = nullif(btrim(coalesce(p_id, '')), '') for update;
  if not found then raise exception 'Kontragent topilmadi' using errcode = '22023', hint = 'fin:not_found'; end if;
  if v_c.kind is distinct from p_kind or v_c.name is distinct from btrim(coalesce(p_name, '')) then
    raise exception 'Kontragent shu orada o''zgartirilgan (hozir: «%», turi %) — sahifani yangilab, qayta ko''rib chiqing', v_c.name, v_c.kind
      using errcode = 'P0001', hint = 'fin:cp_changed';
  end if;
  if v_c."kindConfirmedBy" is not null then
    return to_jsonb(v_c) || jsonb_build_object('ok', true, 'dup', true);
  end if;
  update public.fin_counterparties set "kindConfirmedBy" = app.uid(), "kindConfirmedAt" = now() where id = v_c.id;
  return (select to_jsonb(c) from public.fin_counterparties c where c.id = v_c.id) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.fin_counterparty_confirm(text, text, text) from public, anon;
grant execute on function public.fin_counterparty_confirm(text, text, text) to authenticated;

-- Imzo ro'yxati — FAQAT Direktor.
create or replace function public.fin_signatory_save(p_id text, p_list int, p_uid text, p_title text, p_full_name text, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_id text := nullif(btrim(coalesce(p_id, '')), '');
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: faqat Direktor' using errcode = '42501'; end if;
  if p_list not in (1, 2) then raise exception 'Ro''yxat 1 yoki 2 bo''lsin' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_full_name, ''))) < 2 then raise exception 'F.I.Sh. kiriting' using errcode = '22023'; end if;
  if v_id is null then
    v_id := 'sg_' || replace(gen_random_uuid()::text, '-', '');
    insert into public.fin_signatories (id, list, uid, title, "fullName", active)
      values (v_id, p_list, nullif(btrim(coalesce(p_uid, '')), ''), left(coalesce(p_title, ''), 200), left(btrim(p_full_name), 200), coalesce(p_active, true));
  else
    update public.fin_signatories set list = p_list, uid = nullif(btrim(coalesce(p_uid, '')), ''), title = left(coalesce(p_title, ''), 200),
           "fullName" = left(btrim(p_full_name), 200), active = coalesce(p_active, true) where id = v_id;
    if not found then raise exception 'Imzo egasi topilmadi' using errcode = '22023'; end if;
  end if;
  return (select to_jsonb(s) from public.fin_signatories s where s.id = v_id);
end $$;
revoke all on function public.fin_signatory_save(text, int, text, text, text, boolean) from public, anon;
grant execute on function public.fin_signatory_save(text, int, text, text, text, boolean) to authenticated;

-- O'zgarishlar tarixi (Direktor ko'radi).
select app.chlog_attach('fin_org', 'nameUz,nameRu,stir,place,printLang,t1,l1,cashLimit,kassaGoLive');
select app.chlog_attach('fin_signatories', 'list,uid,title,fullName,active');
select app.chlog_attach('fin_counterparties', 'kind,name,stir,active,kindConfirmedBy,account,mfo,bankName,contractNo,contractDate,contractUntil');   -- tur o'zgarishlari — nazorat ro'yxatida ham (sec-3); bank rekvizitlari va shartnoma (F2.2) — hisob raqami o'zgarishi tarixda ko'rinadi
select app.chlog_attach('fin_articles', 'kind,nameUz,accountCode,cashOutAllowed,active');
select app.chlog_attach('fin_op_rules', 'debit,credit,articleMode,articleId,allowedArticles,accountByParty,partyTypes,needsApproval,directorAlways,fiscalRequired,fiscalParties,active');

notify pgrst, 'reload schema';
