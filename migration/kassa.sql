\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: kassa.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- kassa.sql — MOLIYA ISH REJASI, 1a-BOSQICH (docs/moliya/buxgalteriya-ish-reja.md: F1.2, F1.3): KASSA JADVALLARI VA HIMOYASI.
--   Hujjatlar (KO-1 kirim, KO-2 chiqim, naqdsiz dalolatnomalar) → Dt/Kt qatorlari → kassa kuni (KO-4) → sanash dalolatnomalari.
--   Shu faylda: jadvallar, O'ZGARMASLIK va kun qulfi triggerlari (bazadagi invariantlar I1–I6), raqamlash va kassa qulfi
--   yordamchilari. Hujjat funksiyalari — kassa-docs.sql; kun sikli va o'qish funksiyalari — kassa-day.sql.
--
--   INVARIANTLAR (bazada, RPC'dan mustaqil):
--     I1  kassada BITTA ochiq kun (qisman noyob indeks);
--     I2  yangi kun faqat oldingi kun yopilgan bo'lsa ochiladi; kunlar faqat oldinga qo'shiladi;
--     I3  kun boshi = oldingi kun oxiri (birinchi kun — boshlang'ich qoldiq dalolatnomasidan);
--     I4  kun oxiri = kun boshi + kirim − chiqim (CHECK);
--     I5  kassa qoldig'i hech qachon manfiy emas (har o'tkazish / bekor qilishdan keyin tekshiriladi);
--     I6  tekshirilgan kun o'zgarmaydi; yopilgan kunga hujjat yozilmaydi (faqat Direktor qayta ochadi).
--   O'ZGARMASLIK (CT-11): kassa jadvallariga yozish FAQAT kassa funksiyalari ichida (tranzaksiya bayrog'i iqror.kassa_rpc);
--     DELETE yo'q; o'tkazilgan hujjatda faqat «bekor qilindi» belgisi (kun ochiq bo'lsa) va kamomad qarori o'zgaradi.
--   RAQAMLASH (CT-10): sequence / identity EMAS — doc_counters qatori, o'tkazishning OXIRGI qadami, kassa eksklyuziv qulfi
--     ostida: ROLLBACK raqam «yemaydi», bo'shliq va takror bo'lmaydi. Bekor qilingan hujjat raqamini saqlaydi.
--   QULF TARTIBI: L0 iqror_doc:<clientRef> → L1 iqror_pay:<o'quvchi> → L3 biznes qatorlari → L4 iqror_desk:<kassa> → cash_docs /
--     cash_days qatorlari → L5 doc_counters (oxirgi). cash_docs qatori kassa qulfisiz faqat keyin kassa qulfini OLMAYDIGAN
--     tranzaksiyada qulflanadi (tasdiq / rad / so'rovni bekor qilish) — halqa (deadlock) bo'lmaydi.
--   XAVFSIZLIK: RLS; mijoz faqat o'qiydi (kassa/moliya rollari); DML barcha rollardan qaytarib olingan.
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi.
-- =====================================================================

-- ---------- Kassa: boshlang'ich qoldiq (birinchi kun shu bilan ochiladi) ----------
alter table public.cash_desks add column if not exists "startDay" date;              -- birinchi kassa kuni (shundan oldin hujjat yo'q)
alter table public.cash_desks add column if not exists "openingAmount" numeric check ("openingAmount" is null or ("openingAmount" >= 0 and "openingAmount" < 1e12));
alter table public.cash_desks add column if not exists "openingDocId" text;
alter table public.cash_desks add column if not exists "openingBy" text;
alter table public.cash_desks add column if not exists "openingAt" timestamptz;

-- ---------- Kassa kuni ----------
create table if not exists public.cash_days (
  id             text primary key,                    -- 'cd_<kassa>_<YYYY-MM-DD>'
  desk           text not null references public.cash_desks(id),
  day            date not null,
  status         text not null check (status in ('open', 'closed', 'verified')),
  opening        numeric not null check (opening >= 0 and opening < 1e12),
  receipts       numeric check (receipts is null or receipts >= 0),      -- yopishda yoziladi (ochiq kunda hujjatlardan hisoblanadi)
  payouts        numeric check (payouts is null or payouts >= 0),
  closing        numeric check (closing is null or closing >= 0),
  counted        numeric check (counted is null or counted >= 0),        -- sanalgan naqd pul
  diff           numeric,                                                -- sanalgan − hisobdagi − hali o'tkazilmagan (0 bo'lmasa — shu kun hujjati)
  "diffDocId"    text,
  denoms         jsonb,                                                  -- nominallar bo'yicha sanash {"100000": 12, …}
  "pendingCount" int not null default 0 check ("pendingCount" >= 0),     -- sanash paytida hali o'tkazilmagan (oflayn) yozuvlar
  "pendingSum"   numeric not null default 0 check ("pendingSum" >= 0),
  "docCount"     int,
  "firstKo1" int, "lastKo1" int, "firstKo2" int, "lastKo2" int,
  "sheetFrom" int, "sheetTo" int,                                        -- KO-4 varaqlari
  "sheetRows" int,                                                        -- yopilgan paytdagi «varaqdagi qatorlar soni» (qayta chop etish aynan bir xil bo'lsin)
  hash           text,                                                   -- yopilgan kun mazmuni izi (sha256)
  "cashierUid"   text,
  "openedBy"     text,
  "openedAt"     timestamptz not null default now(),
  "closedBy"     text, "closedAt" timestamptz, "closeNote" text, commission jsonb,
  "verifiedBy"   text, "verifiedAt" timestamptz, "verifyNote" text,
  "reopenCount"  int not null default 0, "reopenedBy" text, "reopenedAt" timestamptz, "reopenReason" text,
  unique (desk, day),
  constraint cash_days_i4 check (closing is null or closing = opening + receipts - payouts),
  constraint cash_days_counted check (counted is null or closing is null or counted = closing + "pendingSum"),
  constraint cash_days_open_null check ((status = 'open') = (closing is null)),
  constraint cash_days_closed_by check (status = 'open' or ("closedBy" is not null and "closedAt" is not null and counted is not null and hash is not null)),
  constraint cash_days_verified_by check ((status = 'verified') = ("verifiedBy" is not null)),
  constraint cash_days_verifier_ne_closer check ("verifiedBy" is null or "verifiedBy" <> "closedBy")
);
create unique index if not exists cash_days_one_open on public.cash_days (desk) where status = 'open';   -- I1
alter table public.cash_days add column if not exists "sheetRows" int;

-- ---------- Kassa hujjati ----------
create table if not exists public.cash_docs (
  id              text primary key,
  desk            text not null references public.cash_desks(id),
  form            text not null check (form in ('KO1', 'KO2', 'ACT')),
  op              text not null references public.fin_op_rules(op),
  status          text not null check (status in ('draft', 'approved', 'rejected', 'cancelled', 'posted', 'void')),
  year            int,
  no              int check (no is null or no > 0),
  "businessDay"   date,
  "dayId"         text references public.cash_days(id),
  amount          numeric not null check (amount > 0 and amount < 1e12 and amount = round(amount, 2)),
  "partyType"     text check ("partyType" in ('student', 'employee', 'counterparty', 'bank', 'founder', 'other')),
  "partyId"       text,
  "partyName"     text not null default '',
  basis           text not null default '',            -- «Асоси»
  attachment      text not null default '',            -- «Иловаси»
  note            text not null default '',
  "noBasis"       boolean not null default false,      -- asos hujjatisiz naqd xarid (≤ L1, bitta statiya)
  "fiscalNo"      text,
  "fiscalExempt"  boolean not null default false,      -- fiskal chek raqamisiz — faqat Direktor istisnosi
  "sourceTable"   text, "sourceId" text, "sourceSnapshot" jsonb,
  "reversalOf"    text,
  "clientRef"     text not null,
  "capturedAt"    timestamptz,                         -- mijoz qurilmasida kiritilgan payt (oflayn navbat)
  late            boolean not null default false,      -- olingan kuni yopilgani uchun keyingi ochiq kunga yozilgan
  "needsList2"    boolean not null default false,
  "needsDirector" boolean not null default false,
  "requestedBy"   text, "requestedAt" timestamptz,
  "approvedBy"    text, "approvedAt" timestamptz,       -- 2-ro'yxat (Moliya menejeri / buxgalter)
  "dirApprovedBy" text, "dirApprovedAt" timestamptz,    -- Direktor
  "rejectedBy"    text, "rejectedAt" timestamptz, "rejectReason" text,
  "postedBy"      text, "postedAt" timestamptz,
  "voidedBy"      text, "voidedAt" timestamptz, "voidReason" text,   -- bekor qilish (o'tkazilgan) yoki so'rovni bekor qilish
  "isSystem"      boolean not null default false,       -- tizim hujjati (sanash farqi): hech kimni «o'tkazuvchi» qilmaydi
  decision        text check (decision is null or decision in ('employee', 'writeoff')),   -- kamomad bo'yicha Direktor qarori
  "decidedBy"     text, "decidedAt" timestamptz, "decisionNote" text, "decisionDocId" text,
  "createdAt"     timestamptz not null default now(),
  "createdBy"     text,
  constraint cash_docs_client_ref unique ("clientRef"),
  constraint cash_docs_no_status check ((no is not null) = (status in ('posted', 'void'))),
  constraint cash_docs_posted_fields check (no is null or (year is not null and "businessDay" is not null and "postedAt" is not null
                                                          and (form = 'ACT' or "dayId" is not null))),
  constraint cash_docs_approver_ne_requester check ("approvedBy" is null or "approvedBy" <> "requestedBy"),
  constraint cash_docs_fiscal check (not "fiscalExempt" or "fiscalNo" is null)
);
create unique index if not exists cash_docs_number on public.cash_docs (desk, form, year, no) where no is not null;
create index if not exists cash_docs_day_idx on public.cash_docs ("dayId");
create index if not exists cash_docs_status_idx on public.cash_docs (status) where status in ('draft', 'approved');
create index if not exists cash_docs_source_idx on public.cash_docs ("sourceTable", "sourceId") where "sourceId" is not null;
create index if not exists cash_docs_party_idx on public.cash_docs ("partyType", "partyId");
create index if not exists cash_docs_fiscal_idx on public.cash_docs ("fiscalNo") where "fiscalNo" is not null;

create table if not exists public.cash_doc_lines (
  id          text primary key,
  "docId"     text not null references public.cash_docs(id) on delete restrict,
  "lineNo"    int not null check ("lineNo" > 0),
  debit       text not null references public.gl_accounts(code),
  credit      text not null references public.gl_accounts(code),
  amount      numeric not null check (amount > 0 and amount < 1e12 and amount = round(amount, 2)),
  "articleId" text references public.fin_articles(id),
  cash        boolean not null default true,          -- naqd pul harakati (5010); false — naqdsiz qator (masalan Dt 6310 Kt 4010)
  analytics   jsonb not null default '{}'::jsonb,
  note        text not null default '',
  unique ("docId", "lineNo"),
  constraint cash_doc_lines_sides check (debit <> credit),
  constraint cash_doc_lines_cash check (cash = (debit = '5010' or credit = '5010'))
);
create index if not exists cash_doc_lines_article_idx on public.cash_doc_lines ("articleId");

-- O'quv to'lovi taqsimoti (KO-1 qatorlari shundan): to'lov qaysi fakturaga naqd / avansdan qancha qo'llandi.
create table if not exists public.payment_allocations (
  id            text primary key,
  "paymentId"   text not null,
  "docId"       text references public.cash_docs(id),
  "studentId"   text not null,
  "invoiceId"   text,                                  -- NULL — ortiqcha to'lov (avansga)
  month         text,
  "fromCash"    numeric not null default 0 check ("fromCash" >= 0),
  "fromCredit"  numeric not null default 0 check ("fromCredit" >= 0),
  account       text not null,                         -- '4010' (boshlangan davr) / '6310' (kelgusi oy, avans)
  "createdAt"   timestamptz not null default now()
);
create index if not exists payment_allocations_pay_idx on public.payment_allocations ("paymentId");
create index if not exists payment_allocations_doc_idx on public.payment_allocations ("docId");

create table if not exists public.cash_day_events (
  id        text primary key,
  "dayId"   text references public.cash_days(id),
  desk      text not null,
  day       date,
  kind      text not null check (kind in ('open', 'close', 'verify', 'reopen', 'handover', 'opening', 'decision', 'zreport')),
  "byUid"   text,
  at        timestamptz not null default now(),
  reason    text,
  data      jsonb not null default '{}'::jsonb
);
-- 'zreport' — onlayn kassa (NKM) Z-hisoboti fakti (F1.26; kassa-day.sql). Avval o'rnatilgan bazada cheklov yangilanadi.
alter table public.cash_day_events drop constraint if exists cash_day_events_kind_check;
alter table public.cash_day_events add constraint cash_day_events_kind_check
  check (kind in ('open', 'close', 'verify', 'reopen', 'handover', 'opening', 'decision', 'zreport'));
create index if not exists cash_day_events_day_idx on public.cash_day_events ("dayId");

-- Sanash dalolatnomalari: kun yopish, smena topshirish-qabul, oylik / yillik komissiya sanashi, boshlang'ich qoldiq.
create table if not exists public.cash_counts (
  id           text primary key,
  desk         text not null references public.cash_desks(id),
  day          date not null,
  "dayId"      text references public.cash_days(id),
  kind         text not null check (kind in ('close', 'handover', 'monthly', 'yearly', 'opening', 'surprise')),
  expected     numeric not null,                       -- hisobdagi qoldiq (sanash paytida)
  counted      numeric not null check (counted >= 0),
  "pendingSum" numeric not null default 0 check ("pendingSum" >= 0),
  diff         numeric not null,                       -- sanalgan − hisobdagi − hali o'tkazilmagan
  "diffDocId"  text,
  denoms       jsonb,
  commission   jsonb,                                  -- komissiya a'zolari (lavozim, F.I.Sh.)
  "fromUid"    text, "toUid" text,                     -- smena topshirish-qabul
  note         text not null default '',
  "byUid"      text,
  at           timestamptz not null default now()
);
create index if not exists cash_counts_day_idx on public.cash_counts (desk, day);

-- Xeshli suratlar (31.12 holati va b.) — keyin o'zgarmaydi.
create table if not exists public.fin_snapshots (
  id          text primary key,
  kind        text not null,
  "asOf"      timestamptz not null,
  payload     jsonb not null,
  hash        text not null,
  note        text not null default '',
  "createdAt" timestamptz not null default now(),
  "createdBy" text
);

-- Chop etish jurnali (FD-07, «НУСХА» belgisi): har chop etishga yuborish yoziladi. Birinchisi — asl nusxa ('original'),
--   keyingilari — «НУСХА» ('copy'); «avvalgisi qog'ozga chiqmadi» deb asl nusxa qayta chiqarilsa — 'reissue' (nazorat ro'yxatida).
--   Kassa kitobi varag'i (KO-4) uchun version = kunning "reopenCount" qiymati: qayta ochib yopilgan kun varag'i — yangi asl nusxa.
create table if not exists public.cash_prints (
  id        text primary key,
  kind      text not null check (kind in ('doc', 'book')),
  "docId"   text references public.cash_docs(id),
  "dayId"   text references public.cash_days(id),
  desk      text not null,
  mode      text not null check (mode in ('original', 'copy', 'reissue')),
  version   int not null default 0,
  "byUid"   text,
  at        timestamptz not null default now(),
  constraint cash_prints_target check ((kind = 'doc' and "docId" is not null) or (kind = 'book' and "dayId" is not null and "docId" is null))
);
create index if not exists cash_prints_doc_idx on public.cash_prints ("docId") where "docId" is not null;
create index if not exists cash_prints_day_idx on public.cash_prints ("dayId") where "dayId" is not null;

-- ---------- RLS: faqat o'qish; yozish — kassa funksiyalari ----------
do $$ declare t text; begin
  foreach t in array array['cash_days', 'cash_docs', 'cash_doc_lines', 'payment_allocations', 'cash_day_events', 'cash_counts', 'fin_snapshots', 'cash_prints'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant select on table public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    -- davr suratida o'quvchi va xodimlar ISMI bilan qoldiqlar bor — jadvalni to'g'ridan-to'g'ri faqat Direktor o'qiydi (FD-28 / D7:
    --   ismli eksport — faqat Direktor); 2-ro'yxat (Moliya menejeri, buxgalter) — fin_snapshot_get orqali, ismsiz (ID bilan).
    execute format('create policy %I on public.%I for select using (%s)', t || '_sel', t,
                   case when t = 'fin_snapshots' then 'app.is_admin()' else 'app.kassa_reader()' end);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;

-- ---------- Bayroq, qulf, raqam ----------
-- Kassa jadvallariga yozish ruxsati — faqat shu tranzaksiyada va faqat kassa funksiyalari ichida yoqiladi.
create or replace function app.kassa_flag(p_on boolean) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin perform set_config('iqror.kassa_rpc', case when p_on then '1' else '' end, true); end $$;
revoke all on function app.kassa_flag(boolean) from public, anon, authenticated;

-- Kassa bo'yicha eksklyuziv qulf (tranzaksiya oxirigacha): har pul hujjati, bekor qilish, sanash, yopish, tekshirish, qayta ochish.
create or replace function app.kassa_lock_desk(p_desk text) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin perform pg_advisory_xact_lock(hashtext('iqror_desk:' || coalesce(p_desk, ''))); end $$;
revoke all on function app.kassa_lock_desk(text) from public, anon, authenticated;

-- Navbatdagi raqam — O'TKAZISHNING OXIRGI QADAMI (kassa qulfi ostida). Hisoblagich qatori tranzaksiya bilan birga
--   saqlanadi yoki bekor bo'ladi: ROLLBACK raqamni «yemaydi».
create or replace function app.kassa_next_no(p_desk text, p_series text, p_year int) returns int
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_no int;
begin
  insert into public.doc_counters (desk, series, year, "lastNo") values (p_desk, p_series, p_year, 1)
    on conflict (desk, series, year) do update set "lastNo" = public.doc_counters."lastNo" + 1
    returning "lastNo" into v_no;
  return v_no;
end $$;
revoke all on function app.kassa_next_no(text, text, int) from public, anon, authenticated;

-- Kun qoldig'i: kun boshi + o'tkazilgan kirimlar − o'tkazilgan chiqimlar (bekor qilinganlar kirmaydi).
create or replace function app.kassa_day_balance(p_day_id text) returns numeric
language sql stable security definer set search_path = public, app, pg_temp as $$
  select d.opening + coalesce((select sum(case when c.form = 'KO1' then c.amount else -c.amount end)
                                 from public.cash_docs c
                                where c."dayId" = d.id and c.status = 'posted' and c.form in ('KO1', 'KO2')), 0)
    from public.cash_days d where d.id = p_day_id
$$;
revoke all on function app.kassa_day_balance(text) from public, anon, authenticated;

-- ---------- Himoya triggerlari ----------
-- Hisoblagich: faqat kassa funksiyasi ichida va faqat +1.
create or replace function app.kassa_counter_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Hujjat raqamlari hisoblagichi o''chirilmaydi' using errcode = '42501', hint = 'kassa:immutable';
  end if;
  if coalesce(current_setting('iqror.kassa_rpc', true), '') <> '1' then
    raise exception 'Hujjat raqamlari faqat kassa funksiyalari orqali beriladi' using errcode = '42501', hint = 'kassa:rpc_only';
  end if;
  if tg_op = 'INSERT' then
    if new."lastNo" <> 1 then raise exception 'Hisoblagich 1 dan boshlanadi' using errcode = '22023', hint = 'kassa:counter'; end if;
  elsif (new.desk, new.series, new.year) is distinct from (old.desk, old.series, old.year) or new."lastNo" <> old."lastNo" + 1 then
    raise exception 'Hisoblagich faqat bittaga oshadi' using errcode = '22023', hint = 'kassa:counter';
  end if;
  return new;
end $$;
drop trigger if exists trg_kassa_counter_guard on public.doc_counters;
create trigger trg_kassa_counter_guard before insert or update or delete on public.doc_counters
  for each row execute function app.kassa_counter_guard();

-- Kassa kuni: I2, I3, I6 va ruxsat etilgan holat o'tishlari.
create or replace function app.kassa_day_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_prev public.cash_days%rowtype; v_desk public.cash_desks%rowtype;
begin
  if tg_op = 'DELETE' then
    raise exception 'Kassa kuni o''chirilmaydi' using errcode = '42501', hint = 'kassa:immutable';
  end if;
  if coalesce(current_setting('iqror.kassa_rpc', true), '') <> '1' then
    raise exception 'Kassa kuni faqat kassa funksiyalari orqali o''zgaradi' using errcode = '42501', hint = 'kassa:rpc_only';
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'open' then
      raise exception 'Kassa kuni ochiq holatda yaratiladi' using errcode = '22023', hint = 'kassa:bad_day';
    end if;
    if exists (select 1 from public.cash_days d where d.desk = new.desk and d.day >= new.day) then
      raise exception 'Kassa kunlari faqat oldinga qo''shiladi (% yoki undan keyingi kun bor)', to_char(new.day, 'DD.MM.YYYY')
        using errcode = 'P0001', hint = 'kassa:day_order';
    end if;
    select * into v_prev from public.cash_days d where d.desk = new.desk order by d.day desc limit 1;
    if found then
      if v_prev.status = 'open' then   -- I2
        raise exception '% kuni yopilmagan — avval sanab yoping', to_char(v_prev.day, 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:prev_open';
      end if;
      if new.opening <> v_prev.closing then   -- I3
        raise exception 'Kun boshi oldingi kun oxiriga teng bo''lishi shart (% ≠ %)', new.opening, v_prev.closing using errcode = 'P0001', hint = 'kassa:opening';
      end if;
    else
      select * into v_desk from public.cash_desks k where k.id = new.desk;
      if v_desk."startDay" is null or v_desk."openingAmount" is null then
        raise exception 'Kassaning boshlang''ich qoldig''i kiritilmagan' using errcode = 'P0001', hint = 'kassa:not_started';
      end if;
      if new.day < v_desk."startDay" then
        raise exception 'Kassa % dan ishlaydi', to_char(v_desk."startDay", 'DD.MM.YYYY') using errcode = 'P0001', hint = 'kassa:not_started';
      end if;
      if new.opening <> v_desk."openingAmount" then
        raise exception 'Birinchi kun boshi boshlang''ich qoldiqqa teng bo''lishi shart' using errcode = 'P0001', hint = 'kassa:opening';
      end if;
    end if;
    return new;
  end if;
  -- UPDATE
  if old.status = 'verified' then   -- I6
    raise exception 'Tekshirilgan kassa kuni o''zgarmaydi' using errcode = '42501', hint = 'kassa:verified';
  end if;
  if (new.id, new.desk, new.day, new.opening, new."openedAt") is distinct from (old.id, old.desk, old.day, old.opening, old."openedAt") then
    raise exception 'Kassa kunining kaliti, sanasi va kun boshi o''zgarmaydi' using errcode = '42501', hint = 'kassa:immutable';
  end if;
  if not ((old.status = 'open' and new.status in ('open', 'closed'))
       or (old.status = 'closed' and new.status in ('verified', 'open'))) then
    raise exception 'Kassa kuni holati noto''g''ri o''zgartirilmoqda (% → %)', old.status, new.status using errcode = '22023', hint = 'kassa:bad_day';
  end if;
  if old.status = 'closed' and new.status = 'open'
     and exists (select 1 from public.cash_days d where d.desk = new.desk and d.day > new.day) then
    raise exception 'Faqat oxirgi kassa kuni qayta ochiladi' using errcode = 'P0001', hint = 'kassa:reopen_last';
  end if;
  if old.status = 'closed' and new.status = 'verified'
     and (to_jsonb(new) - array['status', 'verifiedBy', 'verifiedAt', 'verifyNote']) is distinct from (to_jsonb(old) - array['status', 'verifiedBy', 'verifiedAt', 'verifyNote']) then
    raise exception 'Tekshirishda yopilgan kun ma''lumoti o''zgarmaydi' using errcode = '42501', hint = 'kassa:immutable';
  end if;
  return new;
end $$;
drop trigger if exists trg_kassa_day_guard on public.cash_days;
create trigger trg_kassa_day_guard before insert or update or delete on public.cash_days
  for each row execute function app.kassa_day_guard();

-- Kassa hujjati: o'zgarmaslik, holat o'tishlari, tasdiqsiz o'tkazish yo'q, yopilgan kunga yozuv yo'q.
create or replace function app.kassa_doc_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_day public.cash_days%rowtype; v_keep text[]; v_cash numeric; v_all numeric; v_bad int;
  c_pre constant text[] := array['status', 'approvedBy', 'approvedAt', 'dirApprovedBy', 'dirApprovedAt', 'rejectedBy', 'rejectedAt',
                                 'rejectReason', 'year', 'no', 'businessDay', 'dayId', 'postedBy', 'postedAt', 'capturedAt', 'late',
                                 'voidedBy', 'voidedAt', 'voidReason'];
begin
  if tg_op = 'DELETE' then
    raise exception 'Kassa hujjati o''chirilmaydi (xato bo''lsa — «Bekor qilish»)' using errcode = '42501', hint = 'kassa:immutable';
  end if;
  if coalesce(current_setting('iqror.kassa_rpc', true), '') <> '1' then
    raise exception 'Kassa hujjatlari faqat kassa funksiyalari orqali yoziladi' using errcode = '42501', hint = 'kassa:rpc_only';
  end if;
  if tg_op = 'INSERT' then
    if new.status not in ('draft', 'approved') or new.no is not null or new."postedAt" is not null or new."dayId" is not null then
      raise exception 'Kassa hujjati avval so''rov sifatida yaratiladi (raqam o''tkazishda beriladi)' using errcode = '22023', hint = 'kassa:bad_doc';
    end if;
    new."createdAt" := now();
    return new;
  end if;
  -- UPDATE: qaysi ustunlar o'zgarishi mumkin — holatga qarab
  if old.status in ('draft', 'approved') then
    if not ((old.status = 'draft' and new.status in ('draft', 'approved', 'rejected', 'cancelled', 'posted'))
         or (old.status = 'approved' and new.status in ('approved', 'cancelled', 'posted'))) then
      raise exception 'Hujjat holati noto''g''ri o''zgartirilmoqda (% → %)', old.status, new.status using errcode = '22023', hint = 'kassa:bad_doc';
    end if;
    v_keep := c_pre;
  elsif old.status = 'posted' and new.status = 'void' then
    v_keep := array['status', 'voidedBy', 'voidedAt', 'voidReason'];
  elsif old.status = 'posted' and new.status = 'posted' then
    v_keep := array['decision', 'decidedBy', 'decidedAt', 'decisionNote', 'decisionDocId'];
  else
    raise exception 'Bu hujjat endi o''zgarmaydi (holati: %)', old.status using errcode = '42501', hint = 'kassa:immutable';
  end if;
  if (to_jsonb(new) - v_keep) is distinct from (to_jsonb(old) - v_keep) then
    raise exception 'Kassa hujjatining mazmuni o''zgartirilmaydi — bekor qilib, yangisini yozing' using errcode = '42501', hint = 'kassa:immutable';
  end if;
  -- Tasdiqsiz hujjat tasdiqlangan / o'tkazilgan bo'lmaydi (CT-07).
  if new.status in ('approved', 'posted') and old.status in ('draft', 'approved')
     and ((new."needsList2" and new."approvedBy" is null) or (new."needsDirector" and new."dirApprovedBy" is null)) then
    raise exception 'Hujjat tasdiqlanmagan — avval tasdiq kerak' using errcode = '42501', hint = 'kassa:not_approved';
  end if;
  if new.status = 'posted' and old.status <> 'posted' then
    if new.no is null or new.year is null or new."businessDay" is null or new."postedAt" is null then
      raise exception 'O''tkazilgan hujjatda raqam, yil, kun va vaqt bo''lishi shart' using errcode = '22023', hint = 'kassa:bad_doc';
    end if;
    if new.year <> extract(year from new."businessDay")::int then
      raise exception 'Hujjat yili kassa kuni yiliga teng bo''lishi shart' using errcode = '22023', hint = 'kassa:bad_doc';
    end if;
    select coalesce(sum(l.amount) filter (where l.cash), 0), coalesce(sum(l.amount), 0),
           count(*) filter (where l.cash and ((new.form = 'KO1' and l.debit <> '5010') or (new.form = 'KO2' and l.credit <> '5010')
                                              or (new.form = 'ACT' and new.op <> 'nc_opening')))
      into v_cash, v_all, v_bad from public.cash_doc_lines l where l."docId" = new.id;
    if new.form in ('KO1', 'KO2') then
      if v_cash <> new.amount or v_bad > 0 then
        raise exception 'Hujjat summasi naqd qatorlar yig''indisiga teng bo''lishi va kassa (5010) to''g''ri tomonda turishi shart' using errcode = '22023', hint = 'kassa:lines';
      end if;
      select * into v_day from public.cash_days d where d.id = new."dayId";
      if not found or v_day.status <> 'open' or v_day.day <> new."businessDay" or v_day.desk <> new.desk then   -- I6
        raise exception 'Hujjat faqat ochiq kassa kuniga yoziladi' using errcode = 'P0001', hint = 'kassa:day_closed';
      end if;
    else
      if v_all <> new.amount or v_bad > 0 or new."dayId" is not null then
        raise exception 'Dalolatnoma summasi qatorlar yig''indisiga teng bo''lishi va kassa kuniga bog''lanmasligi shart' using errcode = '22023', hint = 'kassa:lines';
      end if;
    end if;
  end if;
  if new.status = 'void' and old.status = 'posted' and new.form in ('KO1', 'KO2') then
    select * into v_day from public.cash_days d where d.id = new."dayId";
    if not found or v_day.status <> 'open' then   -- I6
      raise exception 'Yopilgan kun hujjati bekor qilinmaydi (Direktor kunni qayta ochadi yoki buxgalter storno qiladi)' using errcode = 'P0001', hint = 'kassa:day_closed';
    end if;
    if new."voidedBy" is null and not new."isSystem" or coalesce(length(btrim(new."voidReason")), 0) < 3 then
      raise exception 'Bekor qilishda kim va sabab yozilishi shart' using errcode = '22023', hint = 'kassa:void_reason';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_kassa_doc_guard on public.cash_docs;
create trigger trg_kassa_doc_guard before insert or update or delete on public.cash_docs
  for each row execute function app.kassa_doc_guard();

-- I5: har o'tkazish / bekor qilishdan keyin kun qoldig'i manfiy bo'lmasin (RPC kassa qulfi ostida ishlaydi).
create or replace function app.kassa_doc_after() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_bal numeric;
begin
  if new.form in ('KO1', 'KO2') and new."dayId" is not null and new.status in ('posted', 'void') and new.status is distinct from old.status then
    v_bal := app.kassa_day_balance(new."dayId");
    if v_bal < 0 then
      raise exception 'Kassada yetarli pul yo''q (qoldiq manfiy bo''lib qoladi: %)', v_bal using errcode = 'P0001', hint = 'kassa:negative';
    end if;
  end if;
  return null;
end $$;
drop trigger if exists trg_kassa_doc_after on public.cash_docs;
create trigger trg_kassa_doc_after after update on public.cash_docs
  for each row execute function app.kassa_doc_after();

-- Hujjat qatorlari: faqat hujjat yaratilayotganda qo'shiladi; keyin o'zgarmaydi.
create or replace function app.kassa_line_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_st text; v_no int;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Kassa hujjati qatorlari o''zgartirilmaydi va o''chirilmaydi' using errcode = '42501', hint = 'kassa:immutable';
  end if;
  if coalesce(current_setting('iqror.kassa_rpc', true), '') <> '1' then
    raise exception 'Kassa hujjatlari faqat kassa funksiyalari orqali yoziladi' using errcode = '42501', hint = 'kassa:rpc_only';
  end if;
  select c.status, c.no into v_st, v_no from public.cash_docs c where c.id = new."docId";
  if v_st is null or v_st not in ('draft', 'approved') or v_no is not null then
    raise exception 'Qator faqat yangi (o''tkazilmagan) hujjatga qo''shiladi' using errcode = '42501', hint = 'kassa:immutable';
  end if;
  return new;
end $$;
drop trigger if exists trg_kassa_line_guard on public.cash_doc_lines;
create trigger trg_kassa_line_guard before insert or update or delete on public.cash_doc_lines
  for each row execute function app.kassa_line_guard();

-- Faqat qo'shiladigan jurnallar: taqsimot, kun hodisalari, sanash dalolatnomalari, suratlar, chop etish jurnali.
create or replace function app.kassa_append_only() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if tg_op <> 'INSERT' then
    raise exception '«%» jadvali faqat qo''shiladi (o''zgartirish va o''chirish yo''q)', tg_table_name using errcode = '42501', hint = 'kassa:immutable';
  end if;
  if coalesce(current_setting('iqror.kassa_rpc', true), '') <> '1' then
    raise exception 'Kassa jadvallari faqat kassa funksiyalari orqali yoziladi' using errcode = '42501', hint = 'kassa:rpc_only';
  end if;
  return new;
end $$;
do $$ declare t text; begin
  foreach t in array array['payment_allocations', 'cash_day_events', 'cash_counts', 'fin_snapshots', 'cash_prints'] loop
    execute format('drop trigger if exists trg_kassa_append_only on public.%I', t);
    execute format('create trigger trg_kassa_append_only before insert or update or delete on public.%I for each row execute function app.kassa_append_only()', t);
  end loop;
end $$;

-- Kassa: boshlang'ich qoldiq faqat kassa funksiyasi orqali va faqat birinchi kun ochilguncha.
create or replace function app.kassa_desk_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    if exists (select 1 from public.cash_docs c where c.desk = old.id) or exists (select 1 from public.cash_days d where d.desk = old.id) then
      raise exception 'Hujjati bor kassa o''chirilmaydi' using errcode = '42501', hint = 'kassa:immutable';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE'
     and (new."startDay", new."openingAmount", new."openingDocId") is distinct from (old."startDay", old."openingAmount", old."openingDocId") then
    if coalesce(current_setting('iqror.kassa_rpc', true), '') <> '1' then
      raise exception 'Boshlang''ich qoldiq faqat kassa funksiyasi orqali kiritiladi' using errcode = '42501', hint = 'kassa:rpc_only';
    end if;
    if exists (select 1 from public.cash_days d where d.desk = old.id) then
      raise exception 'Kassa ishga tushgan — boshlang''ich qoldiq endi o''zgarmaydi' using errcode = '42501', hint = 'kassa:started';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_kassa_desk_guard on public.cash_desks;
create trigger trg_kassa_desk_guard before update or delete on public.cash_desks
  for each row execute function app.kassa_desk_guard();

revoke all on function app.kassa_counter_guard() from public, anon, authenticated;
revoke all on function app.kassa_day_guard() from public, anon, authenticated;
revoke all on function app.kassa_doc_guard() from public, anon, authenticated;
revoke all on function app.kassa_doc_after() from public, anon, authenticated;
revoke all on function app.kassa_line_guard() from public, anon, authenticated;
revoke all on function app.kassa_append_only() from public, anon, authenticated;
revoke all on function app.kassa_desk_guard() from public, anon, authenticated;

-- O'zgarishlar tarixi (Direktor ko'radi): holat o'zgarishlari, bekor qilish, qarorlar, kun yopish / tekshirish / qayta ochish.
select app.chlog_attach('cash_docs', 'status,no,year,businessDay,amount,op,partyType,partyId,approvedBy,dirApprovedBy,rejectReason,voidReason,decision,fiscalExempt,late');
select app.chlog_attach('cash_days', 'status,opening,closing,counted,diff,pendingSum,closedBy,verifiedBy,reopenCount,reopenReason');
select app.chlog_attach('cash_desks', 'name,active,startDay,openingAmount');

notify pgrst, 'reload schema';
