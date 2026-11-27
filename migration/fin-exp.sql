\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-exp.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-exp.sql — MOLIYA ISH REJASI, 2-BOSQICH (F2.1): «BUXGALTERIYA» XARAJATLARI REYESTRI — faqat server funksiyasi orqali.
--   Har xarajat — hujjat (public.fin_exp_docs): to'lov usuli (bank o'tkazmasi / korporativ karta; naqd — faqat kassa ishlamagan kun
--   sanasi bilan, orderisiz), sana, kontragent, hujjat № (to'lov topshiriqnomasi, hisob-faktura, chek), hujjat sanasi, ilova
--   (hujjatlar ro'yxati), izoh, STATIYA QATORLARI (1–20; har qatorda statiya majburiy) va kim kiritgani (server: app.uid(); vaqt — server).
--   Har qator «Buxgalteriya» ro'yxatiga (expenses) alohida yozuv bo'lib tushadi: id = <hujjat id>_<qator №>, "expDocId" — hujjat;
--   toifa va izoh boshi — kassa bilan bir xil qoida (app.kassa_exp_category). Shu sababli mavjud hisobotlar (oylik hisobot, toifalar,
--   Google jadvali, Telegram) o'zgarishsiz to'g'ri sanaydi.
--   public.fin_exp_save(p)  — kiritish; «Tuzatish» — p.replaces: eski hujjat (yoki eski yozuv) shu tranzaksiyada bekor qilinib, o'rniga
--                             yangisi yoziladi. Takror yo'q: clientRef (oynaning bir martalik kaliti) bilan qayta yuborish o'sha hujjatni
--                             qaytaradi (dup), boshqa ma'lumot bilan — rad (fin:ref_mismatch); bir xil to'lovni ikkinchi marta kiritish
--                             (shu usul + kontragent + hujjat № + yil; № bo'lmasa — + sana + summa) — ogohlantirish (fin:exp_dup),
--                             tasdiqlansa (p.dupOk) yoziladi.
--   public.fin_exp_void(id, sabab) — bekor qilish (sabab majburiy): hujjat «bekor qilingan» bo'lib qoladi (o'chirilmaydi), qatorlari
--                             «Buxgalteriya»dan olib tashlanadi. Eski (F2.1 dan oldingi, hujjatsiz) yozuvni bekor qilish yoki tuzatish —
--                             u reyestrga «eski yozuv» (origin = 'legacy', bekor qilingan) bo'lib suratga olinadi, keyin olib tashlanadi.
--   public.fin_exp_refs()   — shakl uchun: statiyalar (qaysi usulda ruxsat) va faol kontragentlar.
--   Qoidalar: kim — Direktor yoki Moliya menejeri (avvalgi «Buxgalteriya» huquqi: app.is_admin() / app.is_finance()). Statiya — usulga
--     qarab (app.fin_exp_article_ok): naqd — kassa «Xarajat»i ro'yxati ("cashOutAllowed", CT-23); bank / karta — EX (ish haqi EX-01…05,
--     ijtimoiy soliq hisoblash EX-06, eskirish EX-44, hisobdan chiqarish EX-45, imtiyoz solig'i EX-47 — yo'q: ular to'lov emas yoki o'z
--     oynasidan) + OP-17 (yetkazib beruvchi), OP-18 (asosiy vosita), OP-24 (sotish uchun tovar); faqat bank — OP-12/13/14 (soliqlar).
--     Ichki o'tkazma (OP-01…05, shu jumladan korporativ kartani to'ldirish OP-04), maosh (OP-08/09 — «Maosh berish»), qaytarish (OP-15 —
--     «↩ Qaytarish»), qarz va ta'sischi — xarajat emas. Bank o'tkazmasida kontragent va hujjat № majburiy. Sana — bugundan keyin emas,
--     2 yildan eski emas; yopilgan davr — rad (expenses trigeri, fin:locked). Naqd — kassa qoidalari o'zgarmaydi (app.kassa_cash_guard:
--     kassa ishga tushgach faqat kassa ishlamagan kun sanasi bilan va faqat Direktor; kassa to'xtatilganda — to'xtatilgan davr sanasi bilan).
--   Himoya: hujjatga bog'langan «Buxgalteriya» qatori to'g'ridan-to'g'ri o'zgarmaydi va o'chirilmaydi, havola qo'lda qo'yilmaydi
--     (trg_fin_exp_guard; fin:exp_linked); hujjat — faqat «kiritilgan → bekor qilingan» (trg_fin_exp_doc_guard; fin:exp_immutable).
--     Sahifa (modul relizi 13+) xarajatni faqat shu funksiyalar orqali yozadi (oylik maosh hisobi qatori — kind 'accrual', «payroll__YYYY-MM» —
--     avvalgidek; F2.4).
--     Hujjatsiz yozuvni to'g'ridan-to'g'ri (REST) yozish huquqi (exp_ins / exp_upd / exp_del — Direktor, Moliya menejeri) hozircha
--     O'ZGARMAYDI: reja F2.9 «Huquqlar II» — avval detektor haftasi (o'zgarishlar jurnalida hujjatsiz to'g'ridan-to'g'ri yozuvlar 0),
--     keyin huquq qaytarib olinadi; eski (keshdagi) sahifa deploydan keyin ham ishlaydi. Kassa qoidalari (naqd) — avvalgidek trigerda.
--   Qulflar (reja §4.17): L0 iqror_doc:<clientRef> → takror tekshiruvi kaliti (usul + kontragent) → qatorlar.
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi (kassa moduli bilan birga).
-- =====================================================================

-- ---------- Jadval: xarajat hujjatlari (reyestr) ----------
create table if not exists public.fin_exp_docs (
  id                text primary key,
  origin            text not null default 'form' check (origin in ('form', 'legacy')),   -- legacy — bekor qilingan / tuzatilgan eski yozuv surati
  method            text check (method in ('bank', 'card', 'cash')),
  date              date,                                    -- to'lov sanasi (bank ko'chirmasi / karta cheki / naqd)
  "counterpartyId"  text references public.fin_counterparties (id),
  "partyName"       text not null default '',              -- kontragent nomi (hujjat paytidagi surat)
  "docNo"           text not null default '',              -- to'lov topshiriqnomasi / hisob-faktura / chek raqami
  "docDate"         date,                                    -- asos hujjat sanasi (ixtiyoriy)
  attachment        text not null default '',              -- ilova: hujjatlar ro'yxati (matn)
  note              text not null default '',
  amount            numeric not null,                        -- qatorlar jami
  lines             jsonb not null default '[]'::jsonb,      -- [{lineNo, articleId, amount, note}] — bekor qilinganda ham saqlanadi
  status            text not null default 'posted' check (status in ('posted', 'void')),
  "clientRef"       text not null,                           -- takror yuborish kaliti (eski yozuv surati — 'legacy:<expenses.id>')
  "reqHash"         text not null default '',
  replaces          text,                                    -- shu hujjat tuzatgan (bekor qilingan) hujjat
  "replacedBy"      text,                                    -- shu hujjat o'rniga yozilgan yangi hujjat
  "createdBy"       text,
  "createdByName"   text not null default '',
  "createdAt"       timestamptz not null default now(),
  "voidReason"      text,
  "voidedBy"        text,
  "voidedByName"    text,
  "voidedAt"        timestamptz,
  constraint fin_exp_docs_form check (origin <> 'form' or (method is not null and date is not null and amount > 0
                                      and jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) between 1 and 20)),
  constraint fin_exp_docs_legacy check (origin <> 'legacy' or status = 'void'),
  constraint fin_exp_docs_void check (status <> 'void' or ("voidReason" is not null and "voidedAt" is not null))
);
create unique index if not exists fin_exp_docs_client_ref on public.fin_exp_docs ("clientRef");
create index if not exists fin_exp_docs_date_idx on public.fin_exp_docs (date);

alter table public.fin_exp_docs enable row level security;
revoke all on table public.fin_exp_docs from public, anon, authenticated;
grant select on table public.fin_exp_docs to authenticated;
grant all on table public.fin_exp_docs to service_role;
drop policy if exists fin_exp_docs_sel on public.fin_exp_docs;
create policy fin_exp_docs_sel on public.fin_exp_docs for select using (app.kassa_reader());

-- «Buxgalteriya» qatori → hujjat
alter table public.expenses add column if not exists "expDocId" text;
create index if not exists expenses_exp_doc_idx on public.expenses ("expDocId") where "expDocId" is not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'expenses_exp_doc_fkey' and conrelid = 'public.expenses'::regclass) then
    alter table public.expenses add constraint expenses_exp_doc_fkey foreign key ("expDocId") references public.fin_exp_docs (id);
  end if;
end $$;
-- F2.4 (reliz 20): maoshni hisoblash qatori (kind 'accrual' — kassa-links.sql) pul harakati emas — unda to'lov usuli, kassa hujjati va
--   xarajat hujjati bo'lmaydi: aks holda u naqd (yoki naqdsiz) pul sifatida yashirinib qolardi. Yangi yozuvlar uchun darhol; mavjud
--   yozuvlar tekshiriladi — mos kelmagan qator bo'lsa zanjir to'xtamaydi, deploy chiqishida «OGOHLANTIRISH» (qator id lari bilan).
do $$ declare v_bad text; begin
  if not exists (select 1 from pg_constraint where conname = 'expenses_accrual_chk' and conrelid = 'public.expenses'::regclass) then
    alter table public.expenses add constraint expenses_accrual_chk
      check (kind <> 'accrual' or (coalesce(method, '') = '' and "cashDocId" is null and "expDocId" is null)) not valid;
  end if;
  if exists (select 1 from pg_constraint where conname = 'expenses_accrual_chk' and conrelid = 'public.expenses'::regclass and not convalidated) then
    select string_agg(e.id, ', ' order by e.id) into v_bad from public.expenses e
     where e.kind = 'accrual' and not (coalesce(e.method, '') = '' and e."cashDocId" is null and e."expDocId" is null);
    if v_bad is null then
      alter table public.expenses validate constraint expenses_accrual_chk;
    else
      raise notice 'OGOHLANTIRISH: maoshni hisoblash qatorida to''lov usuli yoki hujjat bor (%): qatorni «💼 Oylik maoshni yozish» bilan qayta yozing — tekshiruv yangi yozuvlar uchun ishlaydi', v_bad;
    end if;
  end if;
end $$;

-- O'zgarishlar jurnali: xarajatning usuli, statiyasi, kontragenti va hujjati ham (change-log.sql dagi ro'yxat kengaytiriladi)
select app.chlog_attach('expenses', 'date,month,category,amount,note,method,articleId,counterpartyId,expDocId');
select app.chlog_attach('fin_exp_docs', 'method,date,counterpartyId,docNo,amount,status,voidReason,replacedBy');

-- ---------- Yordamchilar ----------
-- Statiya shu to'lov usulida xarajat bo'la oladimi (yuqoridagi qoida; shakl ro'yxati ham shundan — fin_exp_refs).
create or replace function app.fin_exp_article_ok(p_art public.fin_articles, p_method text) returns boolean
language sql stable set search_path = public, app, pg_temp as $$
  select coalesce(p_art.active and nullif(p_art."accountCode", '') is not null and case
           when p_method = 'cash' then p_art."cashOutAllowed"
           when p_method in ('bank', 'card') then
                (p_art.kind = 'EX' and p_art.id not in ('EX-01', 'EX-02', 'EX-03', 'EX-04', 'EX-05', 'EX-06', 'EX-44', 'EX-45', 'EX-47'))
             or p_art.id in ('OP-17', 'OP-18', 'OP-24')
             or (p_method = 'bank' and p_art.id in ('OP-12', 'OP-13', 'OP-14'))
           else false end, false)
$$;
revoke all on function app.fin_exp_article_ok(public.fin_articles, text) from public, anon, authenticated;

-- Hujjat raqamini solishtirish kaliti: bo'shliq, «№», «#» tashlanadi, kichik harf («№ 145» = «145»).
create or replace function app.fin_exp_docno_key(p text) returns text
language sql immutable set search_path = public, app, pg_temp as $$
  select lower(regexp_replace(replace(coalesce(p, ''), '№', ''), '[[:space:]#]+', '', 'g'))
$$;
revoke all on function app.fin_exp_docno_key(text) from public, anon, authenticated;

-- Xodim nomi (email emas — kassa bilan bir xil qoida, app.kassa_user_label)
create or replace function app.fin_exp_who(p_uid text) returns text
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select app.kassa_user_label(u.name, u."staffRefType", u."staffRefId", u.id) from public.users u where u.id = p_uid), p_uid, '')
$$;
revoke all on function app.fin_exp_who(text) from public, anon, authenticated;

create or replace function app.fin_exp_json(p_id text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select to_jsonb(d) from public.fin_exp_docs d where d.id = p_id
$$;
revoke all on function app.fin_exp_json(text) from public, anon, authenticated;

-- Hujjatsiz (eski) yozuvni reyestrga «eski yozuv» (bekor qilingan) bo'lib suratga olish va «Buxgalteriya»dan olib tashlash.
--   Chaqiruvchi: tekshiruvlar (kassa / maosh qatori emas) va bayroq (iqror.fin_exp_rpc) — fin_exp_save / fin_exp_void da.
--   Yopilgan davr sanasi bo'lsa — expenses trigeri rad etadi (fin:locked), surat ham yozilmaydi (bitta tranzaksiya).
create or replace function app.fin_exp_legacy_void(p_row public.expenses, p_uid text, p_reason text, p_by text) returns text
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_id text := 'xl_' || replace(gen_random_uuid()::text, '-', ''); v_cp public.fin_counterparties%rowtype; v_who text := app.fin_exp_who(p_uid);
begin
  select * into v_cp from public.fin_counterparties c where c.id = p_row."counterpartyId";
  insert into public.fin_exp_docs (id, origin, method, date, "counterpartyId", "partyName", note, amount, lines, status, "clientRef",
                                   "createdBy", "createdByName", "voidReason", "voidedBy", "voidedByName", "voidedAt", "replacedBy")
    values (v_id, 'legacy', case when p_row.method in ('bank', 'card', 'cash') then p_row.method end, app.fin_text_day(p_row.date),
            v_cp.id, coalesce(v_cp.name, ''), left(coalesce(p_row.note, ''), 300), coalesce(p_row.amount, 0),
            jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('lineNo', 1, 'articleId', p_row."articleId", 'amount', p_row.amount,
                                                                   'note', p_row.note, 'category', p_row.category, 'expenseId', p_row.id,
                                                                   'expenseDate', p_row.date, 'expenseCreatedAt', p_row."createdAt"))),
            'void', 'legacy:' || p_row.id, p_uid, v_who, p_reason, p_uid, v_who, now(), p_by);
  delete from public.expenses e where e.id = p_row.id;
  return v_id;
end $$;
revoke all on function app.fin_exp_legacy_void(public.expenses, text, text, text) from public, anon, authenticated;

-- Eski yozuvni shu reyestr orqali tuzatish / bekor qilish mumkinmi (kassa qatori, maosh hisobi qatori, hujjat qatori — yo'q).
create or replace function app.fin_exp_legacy_check(p_row public.expenses) returns void
language plpgsql stable set search_path = public, app, pg_temp as $$
begin
  if p_row."expDocId" is not null then
    raise exception 'Bu qator xarajat hujjatiga tegishli — hujjatni tuzating yoki bekor qiling' using errcode = '22023', hint = 'fin:exp_linked';
  end if;
  if p_row."cashDocId" is not null then
    raise exception 'Bu xarajat kassa hujjatidan ko''chgan — «Kassa» bo''limida hujjatni bekor qilish orqali o''zgaradi' using errcode = '42501', hint = 'kassa:linked_row';
  end if;
  if p_row.kind = 'accrual' then   -- F2.4: maoshni hisoblash qatori (kassa-links.sql: expenses.kind)
    raise exception 'Bu — oylik maosh hisobi qatori: «💼 Oylik maoshni yozish» orqali yangilanadi (yoki o''chiriladi)' using errcode = '22023', hint = 'fin:exp_payroll';
  end if;
end $$;
revoke all on function app.fin_exp_legacy_check(public.expenses) from public, anon, authenticated;

-- ---------- Himoya triggerlari ----------
-- expenses: hujjatga bog'langan qator faqat xarajat funksiyalari orqali (bayroq iqror.fin_exp_rpc) yoziladi, o'zgaradi va o'chadi.
create or replace function app.fin_exp_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if coalesce(current_setting('iqror.fin_exp_rpc', true), '') = '1' or app.is_system() then return coalesce(new, old); end if;
  if tg_op = 'INSERT' then
    if new."expDocId" is not null then
      raise exception 'Xarajat hujjati havolasini faqat «Buxgalteriya» xarajat funksiyasi qo''yadi' using errcode = '42501', hint = 'fin:exp_linked';
    end if;
    return new;
  end if;
  if old."expDocId" is null and (tg_op = 'DELETE' or new."expDocId" is null) then return coalesce(new, old); end if;
  if tg_op = 'UPDATE' and (to_jsonb(new) - 'updatedAt') is not distinct from (to_jsonb(old) - 'updatedAt') then return new; end if;
  raise exception 'Bu xarajat hujjat bilan kiritilgan — «Buxgalteriya»da «Tuzatish» yoki «Bekor qilish» orqali o''zgaradi'
    using errcode = '42501', hint = 'fin:exp_linked';
end $$;
revoke all on function app.fin_exp_guard() from public, anon, authenticated;
drop trigger if exists trg_fin_exp_guard on public.expenses;
create trigger trg_fin_exp_guard before insert or update or delete on public.expenses for each row execute function app.fin_exp_guard();

-- fin_exp_docs: faqat funksiyalar yozadi; hujjat o'chirilmaydi, faqat «kiritilgan → bekor qilingan» (sabab, kim, qachon, o'rnini bosgan).
create or replace function app.fin_exp_doc_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_rpc boolean := coalesce(current_setting('iqror.fin_exp_rpc', true), '') = '1';
        v_k constant text[] := array['status', 'voidReason', 'voidedBy', 'voidedByName', 'voidedAt', 'replacedBy'];
begin
  if tg_op = 'DELETE' then
    if app.is_system() then return old; end if;   -- faqat texnik xizmat (service_role): sinov ma'lumotini tozalash
    raise exception 'Xarajat hujjati o''chirilmaydi — faqat bekor qilinadi' using errcode = '42501', hint = 'fin:exp_immutable';
  end if;
  if not (v_rpc or app.is_system()) then
    raise exception 'Xarajat hujjatlari faqat «Buxgalteriya» xarajat funksiyalari orqali yoziladi' using errcode = '42501', hint = 'fin:exp_rpc_only';
  end if;
  if tg_op = 'INSERT' then return new; end if;
  if old.status = 'posted' and new.status = 'void' and (to_jsonb(new) - v_k) = (to_jsonb(old) - v_k) then return new; end if;
  raise exception 'Xarajat hujjati o''zgartirilmaydi — faqat bekor qilinadi (tuzatish — yangi hujjat bilan)' using errcode = '42501', hint = 'fin:exp_immutable';
end $$;
revoke all on function app.fin_exp_doc_guard() from public, anon, authenticated;
drop trigger if exists trg_fin_exp_doc_guard on public.fin_exp_docs;
create trigger trg_fin_exp_doc_guard before insert or update or delete on public.fin_exp_docs for each row execute function app.fin_exp_doc_guard();

-- ---------- RPC: shakl ma'lumotnomasi ----------
create or replace function public.fin_exp_refs() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not app.kassa_reader() then raise exception 'Ruxsat yo''q' using errcode = '42501', hint = 'fin:exp_rights'; end if;
  return jsonb_build_object(
    'articles', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'nameUz', a."nameUz", 'needsNote', a."needsNote",
                                                              'cash', app.fin_exp_article_ok(a, 'cash'), 'bank', app.fin_exp_article_ok(a, 'bank'),
                                                              'card', app.fin_exp_article_ok(a, 'card')) order by a."sortOrder", a.id)
                            from public.fin_articles a
                           where app.fin_exp_article_ok(a, 'cash') or app.fin_exp_article_ok(a, 'bank')), '[]'::jsonb),
    'counterparties', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'name', c.name, 'stir', c.stir) order by c.name, c.id)
                                  from public.fin_counterparties c where c.active), '[]'::jsonb),
    'today', app.fin_today());
end $$;
revoke all on function public.fin_exp_refs() from public, anon;
grant execute on function public.fin_exp_refs() to authenticated;

-- ---------- RPC: kiritish va tuzatish ----------
--   p = { clientRef, method: bank|card|cash, date: 'YYYY-MM-DD', counterpartyId, docNo, docDate, attachment, note,
--         lines: [{articleId, amount, note}], replaces (tuzatilayotgan hujjat yoki eski yozuv id), dupOk }
create or replace function public.fin_exp_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_ref text; v_method text; v_day date; v_today date := app.fin_today(); v_s text;
  v_cpid text; v_cp public.fin_counterparties%rowtype; v_docno text; v_dockey text; v_docdate date; v_att text; v_note text;
  v_repl text; v_dupok boolean; v_lines jsonb := '[]'::jsonb; v_line jsonb; v_i int := 0; v_amt numeric; v_lnote text; v_aid text;
  v_art public.fin_articles%rowtype; v_total numeric := 0; v_hash text; v_ex public.fin_exp_docs%rowtype; v_old public.fin_exp_docs%rowtype;
  v_row public.expenses%rowtype; v_dup public.fin_exp_docs%rowtype; v_id text; v_replid text; v_who text; v_cat text; v_lbl text;
  v_mlabel text; v_txt text;
begin
  if v_uid is null or not (app.is_admin() or app.is_finance()) then
    raise exception 'Ruxsat yo''q: xarajatni Direktor yoki Moliya menejeri kiritadi' using errcode = '42501', hint = 'fin:exp_rights';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'So''rov noto''g''ri' using errcode = '22023', hint = 'fin:exp_input'; end if;
  v_ref := btrim(coalesce(p ->> 'clientRef', ''));
  if v_ref !~ '^[A-Za-z0-9_.:-]{8,80}$' then
    raise exception 'So''rov kaliti noto''g''ri — sahifani yangilang' using errcode = '22023', hint = 'fin:exp_input';
  end if;
  perform pg_advisory_xact_lock(hashtext('iqror_doc:' || v_ref));   -- L0

  -- 1) Ma'lumotni o'qish (holatga bog'liq bo'lmagan tekshiruvlar)
  v_method := coalesce(p ->> 'method', '');
  if v_method not in ('bank', 'card', 'cash') then
    raise exception 'To''lov usuli noto''g''ri (bank o''tkazmasi, korporativ karta yoki naqd)' using errcode = '22023', hint = 'fin:exp_input';
  end if;
  v_s := btrim(coalesce(p ->> 'date', ''));
  begin
    if v_s !~ '^\d{4}-\d{2}-\d{2}$' then raise exception using errcode = '22007'; end if;
    v_day := v_s::date;
  exception when others then
    raise exception 'Sana noto''g''ri' using errcode = '22023', hint = 'fin:exp_date';
  end;
  v_cpid := nullif(btrim(coalesce(p ->> 'counterpartyId', '')), '');
  v_docno := left(btrim(regexp_replace(btrim(coalesce(p ->> 'docNo', '')), '^(№|#)+[[:space:]]*', '')), 60);   -- «№ 145» → «145»
  v_dockey := app.fin_exp_docno_key(v_docno);
  v_s := btrim(coalesce(p ->> 'docDate', ''));
  if v_s <> '' then
    begin
      if v_s !~ '^\d{4}-\d{2}-\d{2}$' then raise exception using errcode = '22007'; end if;
      v_docdate := v_s::date;
    exception when others then
      raise exception 'Hujjat sanasi noto''g''ri' using errcode = '22023', hint = 'fin:exp_date';
    end;
  end if;
  v_att := left(btrim(coalesce(p ->> 'attachment', '')), 500);
  v_note := left(btrim(coalesce(p ->> 'note', '')), 300);
  v_repl := nullif(btrim(coalesce(p ->> 'replaces', '')), '');
  v_dupok := coalesce(p -> 'dupOk' = 'true'::jsonb, false);
  if jsonb_typeof(p -> 'lines') is distinct from 'array' or jsonb_array_length(p -> 'lines') = 0 then
    raise exception 'Kamida bitta statiya qatori kerak' using errcode = '22023', hint = 'fin:exp_lines';
  end if;
  if jsonb_array_length(p -> 'lines') > 20 then
    raise exception 'Bitta hujjatda ko''pi bilan 20 qator' using errcode = '22023', hint = 'fin:exp_lines';
  end if;
  for v_line in select x from jsonb_array_elements(p -> 'lines') x loop
    v_i := v_i + 1;
    if jsonb_typeof(v_line) <> 'object' then raise exception '%-qator noto''g''ri', v_i using errcode = '22023', hint = 'fin:exp_lines'; end if;
    v_aid := nullif(btrim(coalesce(v_line ->> 'articleId', '')), '');
    if v_aid is null then raise exception '%-qator: statiya tanlanmagan', v_i using errcode = '22023', hint = 'fin:exp_article'; end if;
    v_amt := trim_scale(app.kassa_amount(v_line -> 'amount', v_i || '-qator'));
    v_lnote := left(btrim(coalesce(v_line ->> 'note', '')), 300);
    v_total := v_total + v_amt;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('lineNo', v_i, 'articleId', v_aid, 'amount', v_amt, 'note', v_lnote));
  end loop;
  if v_total >= 1e12 then raise exception 'Hujjat summasi juda katta' using errcode = '22023', hint = 'kassa:amount'; end if;
  v_hash := md5(jsonb_build_object('method', v_method, 'date', v_day, 'cp', v_cpid, 'docNo', v_docno, 'docDate', v_docdate,
                                   'att', v_att, 'note', v_note, 'lines', v_lines, 'replaces', v_repl)::text);

  -- 2) Takror yuborish (o'sha oyna, o'sha ma'lumot) — o'sha hujjat
  select * into v_ex from public.fin_exp_docs d where d."clientRef" = v_ref;
  if found then
    if v_ex."reqHash" = v_hash and v_ex."createdBy" = v_uid then
      return app.fin_exp_json(v_ex.id) || jsonb_build_object('ok', true, 'dup', true);
    end if;
    raise exception 'Bu oynadan boshqa ma''lumot bilan xarajat allaqachon yozilgan — oynani yopib, qaytadan oching' using errcode = '22023', hint = 'fin:ref_mismatch';
  end if;

  -- 3) Holatga bog'liq tekshiruvlar
  if v_day > v_today then
    raise exception 'Sana (%) bugundan keyin bo''lmaydi', to_char(v_day, 'DD.MM.YYYY') using errcode = '22023', hint = 'fin:exp_date';
  end if;
  if v_day < v_today - 730 then
    raise exception 'Sana (%) 2 yildan eski — tekshiring', to_char(v_day, 'DD.MM.YYYY') using errcode = '22023', hint = 'fin:exp_date';
  end if;
  if v_docdate is not null and (v_docdate > v_today or v_docdate < v_day - 1100) then
    raise exception 'Hujjat sanasi (%) noto''g''ri', to_char(v_docdate, 'DD.MM.YYYY') using errcode = '22023', hint = 'fin:exp_date';
  end if;
  if v_cpid is not null then
    select * into v_cp from public.fin_counterparties c where c.id = v_cpid for share;
    if not found or not v_cp.active then
      raise exception 'Kontragent topilmadi yoki faol emas — ro''yxatni yangilang' using errcode = '22023', hint = 'fin:exp_party';
    end if;
  elsif v_method = 'bank' then
    raise exception 'Bank o''tkazmasida kontragent (kimga to''langani) majburiy' using errcode = '22023', hint = 'fin:exp_party';
  end if;
  if v_method = 'bank' and v_dockey = '' then
    raise exception 'Bank o''tkazmasida hujjat (to''lov topshiriqnomasi) raqami majburiy' using errcode = '22023', hint = 'fin:exp_docno';
  end if;
  v_mlabel := case v_method when 'bank' then 'bank o''tkazmasi' when 'card' then 'korporativ karta' else 'naqd (orderisiz)' end;
  for v_line in select x from jsonb_array_elements(v_lines) x loop
    select * into v_art from public.fin_articles a where a.id = v_line ->> 'articleId';
    if not found or not v_art.active then
      raise exception '%-qator: statiya topilmadi yoki faol emas (%)', v_line ->> 'lineNo', v_line ->> 'articleId' using errcode = '22023', hint = 'fin:exp_article';
    end if;
    if not app.fin_exp_article_ok(v_art, v_method) then
      raise exception '%-qator: «%» statiyasi bo''yicha % orqali xarajat yozilmaydi', v_line ->> 'lineNo', v_art."nameUz", v_mlabel
        using errcode = '22023', hint = 'fin:exp_article';
    end if;
    if v_art."needsNote" and length(v_line ->> 'note') < 3 and length(v_note) < 3 then
      raise exception '%-qator: «%» statiyasi uchun izoh majburiy', v_line ->> 'lineNo', v_art."nameUz" using errcode = '22023', hint = 'fin:exp_note';
    end if;
  end loop;

  -- tuzatilayotgan hujjat / eski yozuv
  if v_repl is not null then
    select * into v_old from public.fin_exp_docs d where d.id = v_repl for update;
    if found then
      if v_old.status <> 'posted' then
        raise exception 'Tuzatilayotgan hujjat allaqachon bekor qilingan — ro''yxatni yangilang' using errcode = '22023', hint = 'fin:exp_replace';
      end if;
      v_replid := v_old.id;
    else
      select * into v_row from public.expenses e where e.id = v_repl for update;
      if not found then
        raise exception 'Tuzatilayotgan xarajat topilmadi (o''chirilgan bo''lishi mumkin) — ro''yxatni yangilang' using errcode = '22023', hint = 'fin:exp_replace';
      end if;
      perform app.fin_exp_legacy_check(v_row);
    end if;
  end if;

  -- bir xil to'lovni ikkinchi marta kiritish (boshqa oynadan) — ogohlantirish; shu usul va kontragent bo'yicha navbat
  perform pg_advisory_xact_lock(hashtext('iqror_expdup:' || v_method || '|' || coalesce(v_cpid, '')));
  if not v_dupok then
    select * into v_dup from public.fin_exp_docs d
     where d.status = 'posted' and d.origin = 'form' and d.method = v_method and d."counterpartyId" is not distinct from v_cpid
       and d.id is distinct from v_replid
       and case when v_dockey <> '' then app.fin_exp_docno_key(d."docNo") = v_dockey and extract(year from d.date) = extract(year from v_day)
                else app.fin_exp_docno_key(d."docNo") = '' and d.date = v_day and d.amount = v_total end
     order by d."createdAt", d.id limit 1;
    if found then
      v_txt := to_char(v_dup.date, 'DD.MM.YYYY') || case when v_dup."partyName" <> '' then ', «' || v_dup."partyName" || '»' else '' end
               || case when v_dup."docNo" <> '' then ', № ' || v_dup."docNo" else '' end
               || ', ' || regexp_replace(trim_scale(v_dup.amount)::text, '(\d)(?=(\d{3})+(?!\d))', '\1 ', 'g') || ' so''m'   -- «1 500 000 so'm»
               || case when v_dup."createdByName" <> '' then ', kiritdi: ' || v_dup."createdByName" else '' end;
      raise exception 'Takror bo''lishi mumkin — shunday xarajat allaqachon kiritilgan (%). Bu boshqa to''lov bo''lsa — tasdiqlab qayta saqlang', v_txt
        using errcode = 'P0001', hint = 'fin:exp_dup';
    end if;
  end if;

  -- 4) Yozish (bitta tranzaksiya)
  v_id := 'xd_' || replace(gen_random_uuid()::text, '-', '');
  v_who := app.fin_exp_who(v_uid);
  perform set_config('iqror.fin_exp_rpc', '1', true);
  if v_old.id is not null then
    delete from public.expenses e where e."expDocId" = v_old.id;
    update public.fin_exp_docs
       set status = 'void', "voidReason" = 'Tuzatildi: o''rniga yangi hujjat yozildi', "voidedBy" = v_uid, "voidedByName" = v_who,
           "voidedAt" = now(), "replacedBy" = v_id
     where id = v_old.id;
  elsif v_row.id is not null then
    v_replid := app.fin_exp_legacy_void(v_row, v_uid, 'Tuzatildi: o''rniga yangi hujjat yozildi', v_id);
  end if;
  insert into public.fin_exp_docs (id, origin, method, date, "counterpartyId", "partyName", "docNo", "docDate", attachment, note, amount, lines,
                                   status, "clientRef", "reqHash", replaces, "createdBy", "createdByName")
    values (v_id, 'form', v_method, v_day, v_cpid, coalesce(v_cp.name, ''), v_docno, v_docdate, v_att, v_note, v_total, v_lines,
            'posted', v_ref, v_hash, v_replid, v_uid, v_who);
  for v_line in select x from jsonb_array_elements(v_lines) x loop
    select k.o_category, k.o_label into v_cat, v_lbl from app.kassa_exp_category(v_line ->> 'articleId') k;
    v_txt := concat_ws(' — ', nullif(coalesce(v_cp.name, ''), ''), nullif(coalesce(nullif(v_line ->> 'note', ''), v_note), ''));
    v_txt := concat_ws(' ', nullif(v_txt, ''), '(' || v_mlabel || case when v_docno <> '' then ', № ' || v_docno else '' end || ')');
    insert into public.expenses (id, date, month, category, amount, note, method, "articleId", "counterpartyId", "expDocId")
      values (v_id || '_' || (v_line ->> 'lineNo'), to_char(v_day, 'YYYY-MM-DD'), to_char(v_day, 'YYYY-MM'), v_cat, (v_line ->> 'amount')::numeric,
              left(coalesce(v_lbl || ': ', '') || v_txt, 300), v_method, v_line ->> 'articleId', v_cpid, v_id);
  end loop;
  perform set_config('iqror.fin_exp_rpc', '', true);
  return app.fin_exp_json(v_id) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.fin_exp_save(jsonb) from public, anon;
grant execute on function public.fin_exp_save(jsonb) to authenticated;

-- ---------- RPC: bekor qilish ----------
--   p_id — hujjat (fin_exp_docs.id) yoki hujjatsiz eski yozuv (expenses.id). Qayta bosish (allaqachon bekor qilingan) — xatosiz (dup).
create or replace function public.fin_exp_void(p_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_reason text := left(btrim(coalesce(p_reason, '')), 500); v_doc public.fin_exp_docs%rowtype;
        v_row public.expenses%rowtype; v_id text := btrim(coalesce(p_id, '')); v_lid text;
begin
  if v_uid is null or not (app.is_admin() or app.is_finance()) then
    raise exception 'Ruxsat yo''q: xarajatni Direktor yoki Moliya menejeri bekor qiladi' using errcode = '42501', hint = 'fin:exp_rights';
  end if;
  if length(v_reason) < 3 then
    raise exception 'Bekor qilish sababini yozing (kamida 3 belgi)' using errcode = '22023', hint = 'fin:exp_reason';
  end if;
  select * into v_doc from public.fin_exp_docs d where d.id = v_id for update;
  if found then
    if v_doc.status <> 'posted' then return to_jsonb(v_doc) || jsonb_build_object('ok', true, 'dup', true); end if;
    perform set_config('iqror.fin_exp_rpc', '1', true);
    delete from public.expenses e where e."expDocId" = v_doc.id;
    update public.fin_exp_docs
       set status = 'void', "voidReason" = v_reason, "voidedBy" = v_uid, "voidedByName" = app.fin_exp_who(v_uid), "voidedAt" = now()
     where id = v_doc.id;
    perform set_config('iqror.fin_exp_rpc', '', true);
    return app.fin_exp_json(v_doc.id) || jsonb_build_object('ok', true, 'dup', false);
  end if;
  select * into v_row from public.expenses e where e.id = v_id for update;
  if not found then
    select * into v_doc from public.fin_exp_docs d where d."clientRef" = 'legacy:' || v_id;
    if found then return to_jsonb(v_doc) || jsonb_build_object('ok', true, 'dup', true); end if;
    raise exception 'Xarajat topilmadi — ro''yxatni yangilang' using errcode = '22023', hint = 'fin:exp_input';
  end if;
  perform app.fin_exp_legacy_check(v_row);
  perform set_config('iqror.fin_exp_rpc', '1', true);
  v_lid := app.fin_exp_legacy_void(v_row, v_uid, v_reason, null);
  perform set_config('iqror.fin_exp_rpc', '', true);
  return app.fin_exp_json(v_lid) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.fin_exp_void(text, text) from public, anon;
grant execute on function public.fin_exp_void(text, text) to authenticated;
