\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: sheets-sync.sql ALOHIDA ishga tushirilmaydi — u zanjirdagi yordamchilarga (fin-prereq.sql: pay_day, counts_as_receipt, fin_today) tayanadi' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- sheets-sync.sql — GOOGLE SHEETS JADVALIGA AVTOMATIK YOZISH: baza qismi (egasi 2026-11-25; SESSIYA-ISHLARI.md §87).
--
--   Egasi: «O'quvchi ma'lumotlari, qarzdorlik, oylik to'lovlar, barcha hisobotlar; platformadagi har o'zgarish jadvalga o'sha
--   zahoti yozilsin; jadvalni kim ko'rishini Direktor hal qiladi.» Yo'nalish — faqat platforma -> jadval (jadvaldagi tahrir
--   platformaga qaytmaydi; keyingi yozishda platformadagi qiymat bilan almashadi).
--
--   QANDAY ISHLAYDI:
--   1) app.sheets_outbox — o'zgarishlar navbati. Kuzatiladigan jadvallardagi har INSERT / UPDATE / DELETE trigger (app.sheets_mark)
--      bilan bitta yozuv qo'shadi: src — jadval nomi, key — qator kaliti (o'quvchida — o'quvchi kaliti, hisob-faktura va to'lov
--      shu kalit bilan bog'lanadi). Faqat varaqqa ta'sir qiladigan ustunlar kuzatiladi (masalan davomat foizi yoki rasm o'zgarishi
--      navbatga tushmaydi). Yozuv o'zgarish bilan BIR tranzaksiyada — bekor qilingan o'zgarish navbatga tushmaydi; faqat qo'shish
--      (UPDATE yo'q) — parallel to'lovlar bir-birini kutmaydi.
--   2) Navbatga faqat xizmat (iqror-sheets) oxirgi 15 daqiqada tirik bo'lsa yoziladi (app.sheets_state.beat; xizmat har daqiqada
--      yangilaydi). Xizmat o'rnatilmagan yoki to'xtagan bo'lsa navbat o'smaydi; xizmat qaytganda baribir hamma varaqni to'liq
--      qayta yozadi. 7 kundan eski yozuvlar o'chiriladi (bunday kechikishdan keyin xizmat to'liq qayta yozadi — sheets/sync.cjs).
--   3) Bir vaqtda faqat BITTA xizmat nusxasi yozadi (ijara: app.sheets_state.holder — sheets_beat oladi va yangilaydi, 3 daqiqa
--      yangilanmasa boshqa nusxa oladi). Navbatni o'qish / o'chirish faqat ijara egasiga (ikki nusxa bir-birining ustidan eski
--      ma'lumot yozmasin).
--   4) public.sheets_tab(varaq, …) — varaq sarlavhasi va qatorlari. Hisob admin panel bilan bir xil: to'langan — «paid» holatida
--      summa, bekor qilingan / qaytarilganda 0, aks holda paidAmount; qarz — bekor qilingan / qaytarilganda 0, aks holda
--      max(0, summa − to'langan) (admin.html paidOf / debtOf); arxiv — admin.html stuArchived; kassaga tushgan pul —
--      app.counts_as_receipt + app.pay_day (fin-prereq.sql, admin.html cashByMethod); oy kirimi — shu oy hisob-fakturalari bo'yicha
--      to'langan + kassadagi boshqa kirim (finance_other_income qoidasi; kassa moduli bo'lsa), xarajat oyi — month, bo'lmasa sana
--      (Buxgalteriya); yig'im foizi — to'langan / (to'langan + qarz) (Moliya).
--   Hammasi FAQAT service_role (server xizmati) uchun: anon / authenticated (Direktor ham) chaqira olmaydi, navbat va holat
--   jadvallarini ko'rmaydi. Xizmat: sheets/index.cjs (Google Sheets API; xizmat hisobi kaliti serverda). O'rnatish — sheets/README.md.
--
--   VARAQLAR (sheets/sync.cjs TABS bilan bir xil nomlar):
--     students — O'quvchilar: barcha kartalar (arxiv ham, holati bilan), ota-ona ismi va telefoni, shartnoma, joriy qarz, avans;
--     invoices — Oylik to'lovlar: har hisob-faktura (oy, asl summa, chegirma, hisoblangan, to'langan, qarz, holati) — kalitli;
--     payments — To'lovlar: har to'lov yozuvi (kassa kuni, summa, usul, holati, tushumga kiradimi, oy, to'lovchi — maxfiy kod
--                «[kod]» bo'lib saqlangan, payer-code-mask.sql) — kalitli;
--     debts    — Qarzdorlik: joriy oygacha qarzi bor har o'quvchi (qarzli oylar, jami, eng eski oy, ota-ona telefoni);
--     monthly  — Oylik hisobot: har oy — hisoblangan, chegirma, to'langan, qarz, yig'im foizi, kirim, xarajat, foyda, qaytarilgan,
--                kassaga tushgan pul usullar bo'yicha;
--     expenses — Xarajatlar; refunds — Qaytarishlar.
--   VARAQQA YOZILMAYDI: JSHSHIR, metrika, salomatlik, ketish sababi (faqat «bitirgan» belgisi), to'lovchi telefoni, xodimlar
--   maoshi alohida (xarajatda «Maosh» — vedomost jami, admin panel kabi), kassa hujjatlari jurnali.
--
--   Ledger varaqlari (oylik to'lovlar, to'lovlar, xarajatlar, qaytarishlar, oylik hisobot) uchun p_from ('YYYY-MM') — shu oydan
--   boshlab (jadval Google chegarasiga — 10 mln katak — yaqinlashsa; config.json sheets.fromMonth). O'quvchilar va qarzdorlik —
--   doim to'liq.
--   Idempotent — har deployda qayta ishga tushadi (create … if not exists / create or replace / drop trigger if exists).
-- =====================================================================

create table if not exists app.sheets_outbox (
  id bigserial primary key,
  src text not null,
  key text,
  at timestamptz not null default now(),
  seen boolean not null default false
);
alter table app.sheets_outbox add column if not exists seen boolean not null default false;
create table if not exists app.sheets_state (
  id int primary key default 1 check (id = 1),
  beat timestamptz,
  holder text,
  info jsonb not null default '{}'::jsonb,
  "updatedAt" timestamptz not null default now()
);
alter table app.sheets_state add column if not exists holder text;
insert into app.sheets_state (id) values (1) on conflict (id) do nothing;
revoke all on table app.sheets_outbox, app.sheets_state from public, anon, authenticated, service_role;
revoke all on sequence app.sheets_outbox_id_seq from public, anon, authenticated, service_role;

-- Xizmat tirikmi (oxirgi 15 daqiqada yurak urishi)?
create or replace function app.sheets_live() returns boolean
language sql stable security definer set search_path = app, pg_temp as $$
  select exists (select 1 from app.sheets_state where id = 1 and beat > now() - interval '15 minutes')
$$;

-- Navbat triggeri. TG_ARGV[0] — kalit ustuni (standart 'id'); '@skey' — o'quvchi kaliti (studentId, bo'lmasa id: hisob-faktura va
--   to'lov "studentId" shu bilan bog'lanadi). UPDATE da kalit o'zgarsa — eski va yangi kalit ikkalasi yoziladi.
create or replace function app.sheets_mark() returns trigger
language plpgsql security definer set search_path = app, public, pg_temp as $$
declare c text := coalesce(tg_argv[0], 'id'); jn jsonb; jo jsonb; k_new text; k_old text;
begin
  if not app.sheets_live() then return null; end if;
  if tg_op <> 'DELETE' then jn := to_jsonb(new); end if;
  if tg_op <> 'INSERT' then jo := to_jsonb(old); end if;
  if c = '@skey' then
    k_new := coalesce(nullif(jn ->> 'studentId', ''), jn ->> 'id');
    k_old := coalesce(nullif(jo ->> 'studentId', ''), jo ->> 'id');
  else
    k_new := jn ->> c; k_old := jo ->> c;
  end if;
  if tg_op <> 'DELETE' then insert into app.sheets_outbox (src, key) values (tg_table_name, k_new); end if;
  if tg_op = 'DELETE' or (tg_op = 'UPDATE' and k_old is distinct from k_new) then
    insert into app.sheets_outbox (src, key) values (tg_table_name, k_old);
  end if;
  return null;
end $$;
revoke all on function app.sheets_live(), app.sheets_mark() from public, anon, authenticated, service_role;

-- Triggerlar. O'quvchi va maxfiy karta — faqat varaqda ko'rinadigan ustunlar haqiqatan o'zgarganda (WHEN).
drop trigger if exists trg_sheets_mark on public.students;
create trigger trg_sheets_mark after insert or delete on public.students for each row execute function app.sheets_mark('@skey');
drop trigger if exists trg_sheets_mark_u on public.students;
create trigger trg_sheets_mark_u after update on public.students for each row
  when (old.id is distinct from new.id or old."studentId" is distinct from new."studentId" or old.name is distinct from new.name
        or old.grade is distinct from new.grade or old."classLetter" is distinct from new."classLetter" or old.track is distinct from new.track
        or old.lang is distinct from new.lang or old."payStatus" is distinct from new."payStatus" or old."activeFrom" is distinct from new."activeFrom"
        or old."stopFrom" is distinct from new."stopFrom" or old."exitAt" is distinct from new."exitAt"
        or old."exitReason" is distinct from new."exitReason")
  execute function app.sheets_mark('@skey');

drop trigger if exists trg_sheets_mark on public.student_private;
create trigger trg_sheets_mark after insert or delete on public.student_private for each row execute function app.sheets_mark();
drop trigger if exists trg_sheets_mark_u on public.student_private;
create trigger trg_sheets_mark_u after update on public.student_private for each row
  when (old.id is distinct from new.id or old."parentPhone" is distinct from new."parentPhone" or old."parentPhone2" is distinct from new."parentPhone2"
        or old."fatherName" is distinct from new."fatherName" or old."motherName" is distinct from new."motherName" or old.guardian is distinct from new.guardian
        or old."birthDate" is distinct from new."birthDate" or old.address is distinct from new.address
        or old."contractAmount" is distinct from new."contractAmount" or old."siblingDiscount" is distinct from new."siblingDiscount")
  execute function app.sheets_mark();

do $t$
declare r record;
begin
  -- cash_docs / cash_doc_lines — faqat Kassa moduli bazada bo'lsa (hozir --dev): oylik hisobotdagi «boshqa kirim» uchun.
  for r in select * from (values ('invoices', 'id'), ('payments', 'id'), ('refunds', 'id'), ('expenses', 'id'), ('student_credit', 'id'),
                                 ('cash_docs', 'id'), ('cash_doc_lines', 'docId')) v(t, k) loop
    if to_regclass('public.' || r.t) is null then continue; end if;
    execute format('drop trigger if exists trg_sheets_mark on public.%I', r.t);
    execute format('create trigger trg_sheets_mark after insert or update or delete on public.%I for each row execute function app.sheets_mark(%L)', r.t, r.k);
  end loop;
end $t$;

-- ---------------------------------------------------------------------
-- Yordamchilar (ichki; anon / authenticated / service_role to'g'ridan-to'g'ri chaqira olmaydi)
-- ---------------------------------------------------------------------
-- Son: NaN / cheksiz — bo'sh (JS: Number(x)||0 kabi hisobga kirmaydi; jadvalda «NaN» matni chiqmasin).
create or replace function app.sheets_num(p numeric) returns numeric
language sql immutable set search_path = pg_temp as $$
  select case when p is null or p = 'NaN'::numeric or p = 'Infinity'::numeric or p = '-Infinity'::numeric then null else p end
$$;
-- O'quvchi kaliti: studentId (IQ-0001), bo'lmasa doc id.
create or replace function app.sheets_skey(p_sid text, p_id text) returns text
language sql immutable set search_path = pg_temp as $$ select coalesce(nullif(p_sid, ''), p_id) $$;
-- Sinf: «5-A».
create or replace function app.sheets_class(p_grade int, p_letter text) returns text
language sql immutable set search_path = pg_temp as $$
  select case when p_grade is null then coalesce(nullif(p_letter, ''), '') else p_grade::text || coalesce('-' || nullif(p_letter, ''), '') end
$$;
-- Hisob-fakturadagi sinf kaliti «uz-5-A» -> «5-A» (hisob-faktura yozilgan paytdagi sinf).
create or replace function app.sheets_classkey(p text) returns text
language sql immutable set search_path = pg_temp as $$
  select case when coalesce(p, '') ~ '^[A-Za-z]+-[0-9]+-' then regexp_replace(p, '^[A-Za-z]+-', '') else coalesce(p, '') end
$$;
-- Chiqqan kun (admin.html stuExitDay): exitAt, bo'lmasa stopFrom — birinchi 10 belgisi sana bo'lsa.
create or replace function app.sheets_exit_day(p_exit text, p_stop text) returns text
language sql immutable set search_path = pg_temp as $$
  select case when left(coalesce(p_exit, ''), 10) ~ '^\d{4}-\d{2}-\d{2}$' then left(p_exit, 10)
              when left(coalesce(p_stop, ''), 10) ~ '^\d{4}-\d{2}-\d{2}$' then left(p_stop, 10) else '' end
$$;
-- Arxivdami (admin.html stuArchived): «chiqdi» va chiqqan kun yo'q yoki bugun / o'tgan.
create or replace function app.sheets_archived(p_status text, p_exit text, p_stop text, p_today text) returns boolean
language sql immutable set search_path = pg_temp as $$
  select coalesce(p_status, '') = 'chiqdi' and (app.sheets_exit_day(p_exit, p_stop) = '' or app.sheets_exit_day(p_exit, p_stop) <= p_today)
$$;
-- Holat yorlig'i. Ketish sababi yozilmaydi (ichki ma'lumot — students_billing qoidasi), faqat bitiruvchi belgisi.
create or replace function app.sheets_status(p_status text, p_exit text, p_stop text, p_reason text, p_today text) returns text
language sql immutable set search_path = pg_temp as $$
  select case coalesce(p_status, '')
    when 'chiqdi' then case when app.sheets_archived(p_status, p_exit, p_stop, p_today)
                            then case when p_reason = 'bitirdi' then 'Bitirgan (arxiv)' else 'Chiqqan (arxiv)' end
                            else 'Chiqadi: ' || app.sheets_exit_day(p_exit, p_stop) end
    when 'muzlatilgan' then 'Muzlatilgan'
    when 'sinov' then 'Sinov'
    else 'Faol' end
$$;
create or replace function app.sheets_lang(p text) returns text
language sql immutable set search_path = pg_temp as $$
  select case lower(coalesce(p, '')) when 'uz' then 'O''zbek' when 'ru' then 'Rus' when 'en' then 'Ingliz' else coalesce(p, '') end
$$;
-- Hisob-faktura: to'langan / qarz (admin.html paidOf / debtOf).
create or replace function app.sheets_inv_paid(p_status text, p_amount numeric, p_paid numeric) returns numeric
language sql immutable set search_path = pg_temp as $$
  select case when p_status in ('canceled', 'reversed') then 0 when p_status = 'paid' then coalesce(app.sheets_num(p_amount), 0)
              else coalesce(app.sheets_num(p_paid), 0) end
$$;
create or replace function app.sheets_inv_debt(p_status text, p_amount numeric, p_paid numeric) returns numeric
language sql immutable set search_path = pg_temp as $$
  select case when p_status in ('canceled', 'reversed') then 0
              else greatest(0, coalesce(app.sheets_num(p_amount), 0) - app.sheets_inv_paid(p_status, p_amount, p_paid)) end
$$;
create or replace function app.sheets_inv_status(p_status text, p_amount numeric, p_paid numeric) returns text
language sql immutable set search_path = pg_temp as $$
  select case when p_status = 'canceled' then 'Bekor qilingan'
              when p_status = 'reversed' then 'Qaytarilgan (bekor)'
              when p_status = 'paid' or app.sheets_inv_debt(p_status, p_amount, p_paid) <= 0 then 'To''langan'
              when app.sheets_inv_paid(p_status, p_amount, p_paid) > 0 then 'Qisman to''langan'
              else 'To''lanmagan' end
$$;
-- Vaqt -> Toshkent: «YYYY-MM-DD HH:MI» / sana.
create or replace function app.sheets_ts(p timestamptz) returns text
language sql immutable set search_path = pg_temp as $$ select to_char(p at time zone 'Asia/Tashkent', 'YYYY-MM-DD HH24:MI') $$;
create or replace function app.sheets_day(p timestamptz) returns text
language sql immutable set search_path = pg_temp as $$ select to_char(p at time zone 'Asia/Tashkent', 'YYYY-MM-DD') $$;
-- To'lov usuli (admin.html PROV_LBL; xarajat usullari ham).
create or replace function app.sheets_method(p text) returns text
language sql immutable set search_path = pg_temp as $$
  select case lower(coalesce(p, ''))
    when 'click' then 'Click' when 'uzum' then 'Uzum' when 'payme' then 'Payme' when 'cash' then 'Naqd' when 'naqd' then 'Naqd'
    when 'bank' then 'Bank' when 'transfer' then 'Bank' when 'terminal' then 'Terminal' when 'card' then 'Karta'
    when 'mixed' then 'Aralash' when 'fix' then 'Tuzatish' when 'credit' then 'Avans' when 'grant' then 'Grant' when 'reattr' then 'Avans ko''chirish'
    when 'offset' then 'O''zaro hisob (ish haqidan)' when 'nc_offset' then 'O''zaro hisob (ish haqidan)'
    when 'boshqa' then 'Boshqa' when '' then ''
    else p end
$$;
create or replace function app.sheets_pay_status(p text) returns text
language sql immutable set search_path = pg_temp as $$
  select case lower(coalesce(p, ''))
    when 'applied' then 'Qabul qilingan' when 'paid' then 'Qabul qilingan' when 'confirmed' then 'Qabul qilingan'
    when 'split' then 'Bo''lingan (qismlarga)' when 'unmatched' then 'Biriktirilmagan' when 'ambiguous' then 'Biriktirilmagan (noaniq)'
    when 'prepared' then 'Kutilmoqda' when 'created' then 'Kutilmoqda' when 'pending' then 'Kutilmoqda'
    when 'reversed' then 'Qaytarilgan (bekor)' when 'canceled' then 'Bekor qilingan' when 'cancelled' then 'Bekor qilingan'
    when 'refunded' then 'Qaytarib berilgan' when 'failed' then 'Amalga oshmagan' when '' then ''
    else p end
$$;
create or replace function app.sheets_refund_target(p text) returns text
language sql immutable set search_path = pg_temp as $$
  select case coalesce(p, '') when 'invoice' then 'Hisob-fakturadan' when 'credit' then 'Avansdan (ortiqcha to''lovdan)' else coalesce(p, '') end
$$;
-- Oy filtri ('YYYY-MM' yoki bo'sh).
create or replace function app.sheets_from(p text) returns text
language plpgsql immutable set search_path = pg_temp as $$
begin
  if coalesce(p, '') = '' then return null; end if;
  if p !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'sheets: p_from «YYYY-MM» bo''lishi kerak (hozir: %)', p using errcode = '22023'; end if;
  return p;
end $$;
-- O'quvchilar kalit bo'yicha (to'qnash kalitda — studentId yozilgan karta).
create or replace function app.sheets_stu(p_today text)
returns table(sk text, id text, name text, cls text, grade int, letter text, st text, arch boolean)
language sql stable security definer set search_path = app, public, pg_temp as $$
  select distinct on (app.sheets_skey(s."studentId", s.id))
         app.sheets_skey(s."studentId", s.id), s.id, s.name, app.sheets_class(s.grade, s."classLetter"), s.grade, s."classLetter",
         app.sheets_status(s."payStatus", s."exitAt", s."stopFrom", s."exitReason", p_today),
         app.sheets_archived(s."payStatus", s."exitAt", s."stopFrom", p_today)
    from public.students s
   order by app.sheets_skey(s."studentId", s.id), (coalesce(s."studentId", '') <> '') desc, s.id
$$;
revoke all on function app.sheets_num(numeric), app.sheets_skey(text, text), app.sheets_class(int, text), app.sheets_classkey(text),
  app.sheets_exit_day(text, text), app.sheets_archived(text, text, text, text), app.sheets_status(text, text, text, text, text),
  app.sheets_lang(text), app.sheets_inv_paid(text, numeric, numeric), app.sheets_inv_debt(text, numeric, numeric),
  app.sheets_inv_status(text, numeric, numeric), app.sheets_ts(timestamptz), app.sheets_day(timestamptz), app.sheets_method(text),
  app.sheets_pay_status(text), app.sheets_refund_target(text), app.sheets_from(text), app.sheets_stu(text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- Varaqlar: har biri {header: [...], money: [pul ustunlari, 0 dan], rows: [[...], ...]}. Kalitli varaqlarda 1-ustun — qator kaliti;
--   money — jadvalda «1 500 000» ko'rinishida formatlanadigan ustunlar.
--   Kassa moduli qo'shadigan ustunlar (payments."fiscalNo", expenses / refunds: method, "cashDocId" — kassa-pay.sql, kassa-links.sql;
--   hozir --dev) to_jsonb(qator) orqali o'qiladi: jonli zanjirda ustun yo'q — katak bo'sh, funksiya yiqilmaydi.
-- ---------------------------------------------------------------------
create or replace function app.sheets_tab_students() returns jsonb
language sql stable security definer set search_path = app, public, pg_temp as $$
  with t as (select to_char(app.fin_today(), 'YYYY-MM-DD') as today, to_char(app.fin_today(), 'YYYY-MM') as mon),
  d as (
    select i."studentId" as sk, sum(app.sheets_inv_debt(i.status, i.amount, i."paidAmount")) as debt,
           count(*) filter (where app.sheets_inv_debt(i.status, i.amount, i."paidAmount") > 0) as n
      from public.invoices i, t
     where i.month <= t.mon
     group by 1),
  c as (select sc.id as sk, sum(greatest(coalesce(app.sheets_num(sc.credit), 0), 0)) as credit from public.student_credit sc group by 1),
  s as (
    select st.*, app.sheets_skey(st."studentId", st.id) as sk,
           app.sheets_archived(st."payStatus", st."exitAt", st."stopFrom", t.today) as arch,
           app.sheets_status(st."payStatus", st."exitAt", st."stopFrom", st."exitReason", t.today) as lbl
      from public.students st, t)
  select jsonb_build_object(
    'header', jsonb_build_array('O''quvchi ID', 'F.I.Sh.', 'Sinf', 'Yo''nalish', 'Til', 'Holati', 'O''qishni boshlagan', 'Chiqqan sana',
                                'Tug''ilgan sana', 'Otasi', 'Otasining telefoni', 'Onasi', 'Onasining telefoni', 'Vasiy', 'Manzil',
                                'Shartnoma summasi', 'Aka-uka chegirmasi', 'Joriy qarz', 'Qarzli oylar', 'Avans (ortiqcha to''lov)'),
    'money', jsonb_build_array(15, 17, 19),
    'rows', coalesce(jsonb_agg(jsonb_build_array(
        s.sk, s.name, app.sheets_class(s.grade, s."classLetter"), s.track, app.sheets_lang(s.lang), s.lbl,
        nullif(left(coalesce(s."activeFrom", ''), 10), ''),
        case when coalesce(s."payStatus", '') = 'chiqdi' then nullif(app.sheets_exit_day(s."exitAt", s."stopFrom"), '') end,
        nullif(p."birthDate", ''), nullif(p."fatherName", ''), nullif(p."parentPhone", ''), nullif(p."motherName", ''),
        nullif(p."parentPhone2", ''), nullif(p.guardian, ''), nullif(p.address, ''), app.sheets_num(p."contractAmount"),
        nullif(p."siblingDiscount", ''), coalesce(d.debt, 0), coalesce(d.n, 0), coalesce(c.credit, 0))
      order by s.arch, s.grade nulls last, s."classLetter" nulls last, s.name, s.id), '[]'::jsonb))
  from s
  left join public.student_private p on p.id = s.id
  left join d on d.sk = s.sk
  left join c on c.sk = s.sk
$$;

create or replace function app.sheets_tab_invoices(p_keys text[], p_students text[], p_from text) returns jsonb
language sql stable security definer set search_path = app, public, pg_temp as $$
  with s as (select * from app.sheets_stu(to_char(app.fin_today(), 'YYYY-MM-DD'))),
  i as (
    select i.* from public.invoices i
     where (p_from is null or i.month >= p_from)
       and ((p_keys is null and p_students is null) or i.id = any(p_keys) or i."studentId" = any(p_students)))
  select jsonb_build_object(
    'header', jsonb_build_array('Kalit (ID)', 'Oy', 'O''quvchi ID', 'F.I.Sh.', 'Sinf', 'Asl summa', 'Chegirma', 'Hisoblangan', 'To''langan',
                                'Qarz', 'Holati', 'To''liq to''langan vaqti', 'Yaratilgan'),
    'money', jsonb_build_array(5, 6, 7, 8, 9),
    'rows', coalesce(jsonb_agg(jsonb_build_array(
        i.id, i.month, i."studentId", coalesce(s.name, i."studentName"), app.sheets_classkey(i."classKey"),
        app.sheets_num(i."baseAmount"), app.sheets_num(i.discount), app.sheets_num(i.amount),
        app.sheets_inv_paid(i.status, i.amount, i."paidAmount"), app.sheets_inv_debt(i.status, i.amount, i."paidAmount"),
        app.sheets_inv_status(i.status, i.amount, i."paidAmount"), app.sheets_ts(i."paidAt"), app.sheets_ts(i."createdAt"))
      order by i.month, (substring(app.sheets_classkey(i."classKey") from '^[0-9]+'))::numeric nulls last, app.sheets_classkey(i."classKey"),
               coalesce(s.name, i."studentName"), i.id), '[]'::jsonb))
  from i left join s on s.sk = i."studentId"
$$;

create or replace function app.sheets_tab_payments(p_keys text[], p_students text[], p_from text) returns jsonb
language sql stable security definer set search_path = app, public, pg_temp as $$
  with s as (select * from app.sheets_stu(to_char(app.fin_today(), 'YYYY-MM-DD'))),
  p as (
    select p.*, app.pay_day(p."createdAt", p.raw) as pd from public.payments p
     where (p_keys is null and p_students is null) or p.id = any(p_keys) or p."studentId" = any(p_students))
  select jsonb_build_object(
    'header', jsonb_build_array('Kalit (ID)', 'Sana (kassa kuni)', 'Kiritilgan vaqt', 'O''quvchi ID', 'F.I.Sh.', 'Sinf', 'Summa', 'Usul',
                                'Holati', 'Tushumga kiradimi', 'Hisob-faktura oyi', 'To''lovchi', 'Fiskal chek'),
    'money', jsonb_build_array(6),
    'rows', coalesce(jsonb_agg(jsonb_build_array(
        p.id, to_char(p.pd, 'YYYY-MM-DD'), app.sheets_ts(p."createdAt"), nullif(p."studentId", ''), s.name, s.cls,
        app.sheets_num(p.amount), app.sheets_method(p.provider), app.sheets_pay_status(p.status),
        case when app.counts_as_receipt(p.id, p.status, p.provider, p.amount) then 'Ha' else 'Yo''q' end,
        i.month, nullif(p."payerName", ''), nullif(to_jsonb(p) ->> 'fiscalNo', ''))
      order by p."createdAt" nulls first, p.id), '[]'::jsonb))
  from p
  left join s on s.sk = p."studentId"
  left join public.invoices i on i.id = p."invoiceId"
  where p_from is null or to_char(p.pd, 'YYYY-MM') >= p_from
$$;

create or replace function app.sheets_tab_debts() returns jsonb
language sql stable security definer set search_path = app, public, pg_temp as $$
  with t as (select to_char(app.fin_today(), 'YYYY-MM-DD') as today, to_char(app.fin_today(), 'YYYY-MM') as mon),
  inv as (
    select i."studentId" as sk, i.month, i."studentName", i."classKey", app.sheets_inv_debt(i.status, i.amount, i."paidAmount") as debt
      from public.invoices i, t
     where i.month <= t.mon),
  d as (
    select sk, sum(debt) as debt, count(*) filter (where debt > 0) as n,
           string_agg(month, ', ' order by month) filter (where debt > 0) as months, min(month) filter (where debt > 0) as oldest,
           (array_agg("studentName" order by month desc))[1] as iname, (array_agg("classKey" order by month desc))[1] as ick
      from inv group by sk having sum(debt) > 0),
  s as (select * from app.sheets_stu((select today from t))),
  c as (select sc.id as sk, sum(greatest(coalesce(app.sheets_num(sc.credit), 0), 0)) as credit from public.student_credit sc group by 1)
  select jsonb_build_object(
    'header', jsonb_build_array('O''quvchi ID', 'F.I.Sh.', 'Sinf', 'Holati', 'Qarzli oylar', 'Oylar soni', 'Jami qarz', 'Eng eski qarz oyi',
                                'Avans (ortiqcha to''lov)', 'Otasining telefoni', 'Onasining telefoni'),
    'money', jsonb_build_array(6, 8),
    'rows', coalesce(jsonb_agg(jsonb_build_array(
        d.sk, coalesce(s.name, d.iname), coalesce(s.cls, app.sheets_classkey(d.ick)), coalesce(s.st, 'Kartasi yo''q'), d.months, d.n, d.debt,
        d.oldest, coalesce(c.credit, 0), nullif(p."parentPhone", ''), nullif(p."parentPhone2", ''))
      order by d.debt desc, coalesce(s.name, d.iname), d.sk), '[]'::jsonb))
  from d
  left join s on s.sk = d.sk
  left join public.student_private p on p.id = s.id
  left join c on c.sk = d.sk
$$;

create or replace function app.sheets_tab_monthly(p_from text) returns jsonb
language plpgsql stable security definer set search_path = app, public, pg_temp as $$
declare
  v_other jsonb := '{}'::jsonb;
  v_header jsonb;
  v_kassa boolean := to_regclass('public.cash_docs') is not null and to_regclass('public.cash_doc_lines') is not null
                     and to_regclass('public.cash_desks') is not null and to_regclass('public.fin_articles') is not null;
  v jsonb;
begin
  if v_kassa then
    -- Kassadagi o'quv to'lovidan tashqari kirim (audit-11-moliya.sql finance_other_income qoidasi; sinov kassalarisiz).
    execute $q$
      select coalesce(jsonb_object_agg(x.m, x.s), '{}'::jsonb)
        from (select to_char(c."businessDay", 'YYYY-MM') as m, sum(l.amount) as s
                from public.cash_docs c
                join public.cash_doc_lines l on l."docId" = c.id
                join public.cash_desks k on k.id = c.desk
                join public.fin_articles a on a.id = l."articleId"
               where c.form = 'KO1' and c.status = 'posted' and c.op <> 'in_surplus' and not k."isTest"
                 and l.cash and a.kind = 'IN' and a.id <> 'IN-01' and c."businessDay" is not null
               group by 1) x $q$ into v_other;
  end if;
  with inv as (
    select i.month as m,
           count(distinct i."studentId") filter (where coalesce(i.status, '') not in ('canceled', 'reversed')) as n_stu,
           coalesce(sum(app.sheets_num(i.amount)) filter (where coalesce(i.status, '') not in ('canceled', 'reversed')), 0) as billed,
           coalesce(sum(app.sheets_num(i.discount)) filter (where coalesce(i.status, '') not in ('canceled', 'reversed')), 0) as disc,
           sum(app.sheets_inv_paid(i.status, i.amount, i."paidAmount")) as paid,
           sum(app.sheets_inv_debt(i.status, i.amount, i."paidAmount")) as debt
      from public.invoices i where i.month ~ '^\d{4}-\d{2}$' group by 1),
  rc as (
    select to_char(app.pay_day(p."createdAt", p.raw), 'YYYY-MM') as m, coalesce(nullif(p.provider, ''), 'boshqa') as pv,
           coalesce(sum(app.sheets_num(p.amount)), 0) as s
      from public.payments p
     where p."createdAt" is not null and app.counts_as_receipt(p.id, p.status, p.provider, p.amount)
     group by 1, 2),
  ex as (select coalesce(nullif(e.month, ''), left(e.date, 7)) as m, coalesce(sum(app.sheets_num(e.amount)), 0) as s from public.expenses e group by 1),
  rf as (
    select coalesce(nullif(r.month, ''), to_char(r."createdAt" at time zone 'Asia/Tashkent', 'YYYY-MM')) as m,
           coalesce(sum(app.sheets_num(r.amount)) filter (where r.target = 'invoice'), 0) as inv,
           coalesce(sum(app.sheets_num(r.amount)) filter (where r.target = 'credit'), 0) as cred
      from public.refunds r group by 1),
  oth as (select o.key as m, app.sheets_num((o.value #>> '{}')::numeric) as s from jsonb_each(v_other) o),
  months as (
    select u.m from (select m from inv union select m from rc union select m from ex union select m from rf union select m from oth) u
     where u.m ~ '^\d{4}-\d{2}$' and (p_from is null or u.m >= p_from)),
  pv as (
    select x.pv, row_number() over (order by coalesce(array_position(array['cash', 'terminal', 'click', 'uzum', 'payme', 'bank', 'mixed', 'fix',
                                                                            'credit', 'grant', 'offset', 'boshqa'], x.pv), 100), x.pv) as ord
      from (select distinct rc.pv from rc join months using (m) where rc.s <> 0) x),
  rws as (
    select mo.m,
           jsonb_build_array(mo.m, coalesce(inv.n_stu, 0), coalesce(inv.billed, 0), coalesce(inv.disc, 0), coalesce(inv.paid, 0),
                             coalesce(inv.debt, 0),
                             case when coalesce(inv.paid, 0) + coalesce(inv.debt, 0) > 0
                                  then round(100 * coalesce(inv.paid, 0) / (coalesce(inv.paid, 0) + coalesce(inv.debt, 0))) end)
           || case when v_kassa then jsonb_build_array(coalesce(oth.s, 0)) else '[]'::jsonb end
           || jsonb_build_array(coalesce(inv.paid, 0) + coalesce(oth.s, 0), coalesce(ex.s, 0),
                                coalesce(inv.paid, 0) + coalesce(oth.s, 0) - coalesce(ex.s, 0), coalesce(rf.inv, 0), coalesce(rf.cred, 0),
                                coalesce((select sum(r2.s) from rc r2 where r2.m = mo.m), 0))
           || coalesce((select jsonb_agg(coalesce((select r3.s from rc r3 where r3.m = mo.m and r3.pv = pv.pv), 0) order by pv.ord) from pv), '[]'::jsonb)
           as r
      from months mo
      left join inv on inv.m = mo.m
      left join ex on ex.m = mo.m
      left join rf on rf.m = mo.m
      left join oth on oth.m = mo.m)
  select jsonb_build_array('Oy', 'O''quvchilar (hisob-faktura)', 'Hisoblangan', 'Chegirma', 'To''langan (shu oy uchun)', 'Qarz', 'Yig''im foizi, %')
         || case when v_kassa then jsonb_build_array('Boshqa kirim (kassa)') else '[]'::jsonb end
         || jsonb_build_array('Jami kirim', 'Xarajat', 'Foyda (kirim − xarajat)', 'Qaytarilgan (hisob-fakturadan)', 'Qaytarilgan (avansdan)',
                              'Kassaga tushgan (jami)')
         || coalesce((select jsonb_agg('Tushum: ' || app.sheets_method(pv.pv) order by pv.ord) from pv), '[]'::jsonb),
         coalesce((select jsonb_agg(rws.r order by rws.m) from rws), '[]'::jsonb)
    into v_header, v;
  return jsonb_build_object('header', v_header,
    'money', (select jsonb_agg(h.o - 1 order by h.o) from jsonb_array_elements_text(v_header) with ordinality h(n, o)
               where h.n not in ('Oy', 'O''quvchilar (hisob-faktura)', 'Yig''im foizi, %')),
    'rows', v);
end $$;

-- Maosh hisoblash qatori (`payroll__YYYY-MM`, reliz 20 dan expenses.kind = 'accrual' — kassa-links.sql; ustun yo'q zanjirda — ID bo'yicha):
--   «To'lov usuli» katagida «Hisoblash (naqd emas)» — ish haqi hisoblangani, pul chiqimi emas (to'lov — maosh to'lovlarida).
create or replace function app.sheets_tab_expenses(p_from text) returns jsonb
language sql stable security definer set search_path = app, public, pg_temp as $$
  select jsonb_build_object(
    'header', jsonb_build_array('Sana', 'Oy', 'Toifa', 'Summa', 'To''lov usuli', 'Izoh', 'Kassa hujjati'),
    'money', jsonb_build_array(3),
    'rows', coalesce(jsonb_agg(jsonb_build_array(
        nullif(e.date, ''), coalesce(nullif(e.month, ''), left(e.date, 7)), coalesce(nullif(e.category, ''), 'Boshqa'),
        app.sheets_num(e.amount),
        case when coalesce(to_jsonb(e) ->> 'kind', case when e.id ~ '^payroll__[0-9]{4}-(0[1-9]|1[0-2])$' then 'accrual' else 'expense' end) = 'accrual'
             then 'Hisoblash (naqd emas)' else app.sheets_method(to_jsonb(e) ->> 'method') end,
        nullif(e.note, ''), nullif(to_jsonb(e) ->> 'cashDocId', ''))
      order by coalesce(nullif(e.date, ''), e.month), e."createdAt" nulls first, e.id), '[]'::jsonb))
  from public.expenses e
  where p_from is null or coalesce(nullif(e.month, ''), left(e.date, 7)) >= p_from
$$;

create or replace function app.sheets_tab_refunds(p_from text) returns jsonb
language sql stable security definer set search_path = app, public, pg_temp as $$
  with s as (select * from app.sheets_stu(to_char(app.fin_today(), 'YYYY-MM-DD'))),
  r as (select r.*, coalesce(nullif(r.month, ''), to_char(r."createdAt" at time zone 'Asia/Tashkent', 'YYYY-MM')) as rm from public.refunds r)
  select jsonb_build_object(
    'header', jsonb_build_array('Sana', 'Oy', 'O''quvchi ID', 'F.I.Sh.', 'Sinf', 'Summa', 'Qayerdan', 'Usul', 'Sabab', 'Kassa hujjati'),
    'money', jsonb_build_array(5),
    'rows', coalesce(jsonb_agg(jsonb_build_array(
        app.sheets_day(r."createdAt"), r.rm, nullif(r."studentId", ''), coalesce(s.name, r."studentName"), s.cls, app.sheets_num(r.amount),
        app.sheets_refund_target(r.target), app.sheets_method(to_jsonb(r) ->> 'method'), nullif(r.reason, ''), nullif(to_jsonb(r) ->> 'cashDocId', ''))
      order by r."createdAt" nulls first, r.id), '[]'::jsonb))
  from r left join s on s.sk = r."studentId"
  where p_from is null or r.rm >= p_from
$$;
revoke all on function app.sheets_tab_students(), app.sheets_tab_invoices(text[], text[], text), app.sheets_tab_payments(text[], text[], text),
  app.sheets_tab_debts(), app.sheets_tab_monthly(text), app.sheets_tab_expenses(text), app.sheets_tab_refunds(text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- Xizmat uchun RPC (FAQAT service_role). p_instance — xizmat nusxasi nomi (ijara egasi).
-- ---------------------------------------------------------------------
-- Ijara egasimi? Aks holda — xato (boshqa nusxa ishlayapti).
create or replace function app.sheets_holder_check(p_instance text) returns void
language plpgsql stable security definer set search_path = app, pg_temp as $$
begin
  if coalesce(p_instance, '') = '' or not exists (select 1 from app.sheets_state where id = 1 and holder = p_instance) then
    raise exception 'sheets: bu nusxa (%) yozish ijarasiga ega emas — boshqa iqror-sheets nusxasi ishlayapti yoki ijara muddati o''tdi', p_instance
      using errcode = '55P03';
  end if;
end $$;
revoke all on function app.sheets_holder_check(text) from public, anon, authenticated, service_role;

-- Yurak urishi + ijara: bo'sh / shu nusxaniki / 3 daqiqa yangilanmagan bo'lsa — olinadi. Holat (oxirgi muvaffaqiyat, xato) yoziladi.
create or replace function public.sheets_beat(p_instance text, p_info jsonb default null) returns jsonb
language plpgsql volatile security definer set search_path = app, public, pg_temp as $$
declare v_ok boolean; v_holder text; v_age int;
begin
  if coalesce(p_instance, '') = '' then raise exception 'sheets_beat: p_instance kerak' using errcode = '22023'; end if;
  update app.sheets_state
     set beat = now(), holder = p_instance, info = coalesce(p_info, info), "updatedAt" = now()
   where id = 1 and (holder is null or holder = p_instance or beat is null or beat < now() - interval '3 minutes')
  returning true into v_ok;
  if coalesce(v_ok, false) then
    delete from app.sheets_outbox where at < now() - interval '7 days';
    return jsonb_build_object('ok', true);
  end if;
  select holder, extract(epoch from now() - beat)::int into v_holder, v_age from app.sheets_state where id = 1;
  return jsonb_build_object('ok', false, 'holder', v_holder, 'ageSec', v_age);
end $$;

-- Ijarani bo'shatish (xizmat to'xtaganda) — keyingi nusxa kutmasdan oladi. Navbat yozilishi to'xtamaydi (beat saqlanadi).
create or replace function public.sheets_release(p_instance text) returns boolean
language sql volatile security definer set search_path = app, public, pg_temp as $$
  update app.sheets_state set holder = null, "updatedAt" = now() where id = 1 and holder = p_instance returning true
$$;

-- Navbatdan o'qish: eng eski p_limit ta (id tartibida).
create or replace function public.sheets_pull(p_instance text, p_limit int default 5000) returns jsonb
language plpgsql volatile security definer set search_path = app, public, pg_temp as $$
declare v jsonb;
begin
  perform app.sheets_holder_check(p_instance);
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'src', x.src, 'key', x.key) order by x.id), '[]'::jsonb) into v
    from (select o.id, o.src, o.key from app.sheets_outbox o order by o.id limit greatest(1, least(coalesce(p_limit, 5000), 50000))) x;
  return v;
end $$;

-- Yozilgan yozuvlarni o'chirish — aynan o'qilgan id'lar (o'qilgandan keyin kelgani qoladi).
create or replace function public.sheets_ack(p_instance text, p_ids bigint[]) returns int
language plpgsql volatile security definer set search_path = app, public, pg_temp as $$
declare n int;
begin
  perform app.sheets_holder_check(p_instance);
  delete from app.sheets_outbox where id = any(coalesce(p_ids, '{}'::bigint[]));
  get diagnostics n = row_count;
  return n;
end $$;

-- To'liq qayta yozish: boshida hozir ko'rinib turgan (commit bo'lgan) yozuvlar belgilanadi, oxirida faqat ular o'chiriladi —
--   to'liq yozish ularning hammasini qamraydi (varaq ma'lumoti belgilashdan KEYIN o'qiladi); belgilashdan keyin commit bo'lgani
--   navbatda qoladi va keyingi aylanishda yoziladi. Katta navbat (uzoq uzilishdan keyin) id'larni tashimasdan tozalanadi.
create or replace function public.sheets_full_begin(p_instance text) returns int
language plpgsql volatile security definer set search_path = app, public, pg_temp as $$
declare n int;
begin
  perform app.sheets_holder_check(p_instance);
  update app.sheets_outbox set seen = true where not seen;
  get diagnostics n = row_count;
  return n;
end $$;
create or replace function public.sheets_full_end(p_instance text) returns int
language plpgsql volatile security definer set search_path = app, public, pg_temp as $$
declare n int;
begin
  perform app.sheets_holder_check(p_instance);
  delete from app.sheets_outbox where seen;
  get diagnostics n = row_count;
  return n;
end $$;

-- Varaq ma'lumoti. p_keys — kalitli varaqda kerakli qator kalitlari, p_students — o'quvchi kalitlari (shu o'quvchining
--   qatorlari); ikkalasi ham null — butun varaq. p_from — ledger varaqlari uchun boshlang'ich oy ('YYYY-MM').
create or replace function public.sheets_tab(p_tab text, p_keys text[] default null, p_students text[] default null, p_from text default null)
returns jsonb
language plpgsql stable security definer set search_path = app, public, pg_temp as $$
declare f text := app.sheets_from(p_from);
begin
  return case p_tab
    when 'students' then app.sheets_tab_students()
    when 'invoices' then app.sheets_tab_invoices(p_keys, p_students, f)
    when 'payments' then app.sheets_tab_payments(p_keys, p_students, f)
    when 'debts' then app.sheets_tab_debts()
    when 'monthly' then app.sheets_tab_monthly(f)
    when 'expenses' then app.sheets_tab_expenses(f)
    when 'refunds' then app.sheets_tab_refunds(f)
    else null end;
end $$;

revoke all on function public.sheets_beat(text, jsonb), public.sheets_release(text), public.sheets_pull(text, int),
  public.sheets_ack(text, bigint[]), public.sheets_full_begin(text), public.sheets_full_end(text),
  public.sheets_tab(text, text[], text[], text)
  from public, anon, authenticated;
grant execute on function public.sheets_beat(text, jsonb), public.sheets_release(text), public.sheets_pull(text, int),
  public.sheets_ack(text, bigint[]), public.sheets_full_begin(text), public.sheets_full_end(text),
  public.sheets_tab(text, text[], text[], text)
  to service_role;
