\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-class.sql ALOHIDA ishga tushirilmaydi — u zanjirdagi xarajatlar, statiyalar va davr qulfiga tayanadi' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-class.sql — moliya rejasi F2.3: noyabr–yanvar «Buxgalteriya» eski xarajatlariga statiya — buxgalter tasnifi va imzosi.
--
-- Nima uchun: kassa moduli (statiyali KO-2, F2.1 xarajat hujjati) ishga tushgunga qadar «Buxgalteriya»ga xarajat faqat eski toifa bilan
--   kiritilgan; statiya toifadan taxminan olinadi (fin_category_map: «Boshqa» → EX-49, «Kommunal» → EX-11 …). Hisobot davri
--   (2026-yil noyabr — 2027-yil yanvar) uchun buxgalter har yozuvga aniq statiyani qo'yadi yoki toifadagini tasdiqlaydi va oyni imzolaydi
--   (reja §4.4 «Moslik», §4.16 «Statiya bo'yicha to'liqlik»: 2026-yil noyabr–dekabr — F2.3 orqali, «qisman» belgisi bilan).
--
-- Doira (app.fin_class_in): «Buxgalteriya»dagi hujjatsiz eski yozuv — xarajat hujjatiga ("expDocId") va kassa hujjatiga ("cashDocId")
--   bog'lanmagan, maosh hisoblash qatori emas (kind = 'expense'), oyi 2026-11 … 2027-01 (oy bo'sh bo'lsa — sanadan). Hujjatli yozuv
--   statiyasi hujjatda («Tuzatish», F2.1), kassa yozuviniki — kassa hujjatida (qayta tasnif dalolatnomasi, F2.13).
-- Tasnif (fin_exp_classify): yozuvga BITTA statiya — expenses."articleId" (summa, sana, toifa, izoh, usul o'zgarmaydi) va jurnal
--   fin_exp_class (eski → yangi statiya, izoh, kim, qachon). Toifadagi statiyani tasdiqlash ham jurnalga yoziladi (taxminiy → tasdiqlangan).
--   Bitta yozuvni bir nechta statiyaga bo'lish kerak bo'lsa — Moliya menejeri «Tuzatish» bilan hujjat qatorlariga ajratadi (F2.1).
--   Statiya: faol, IN emas; eskirish, umidsiz qarz va imtiyoz hisoblash (EX-44 / 45 / 47) hamda texnik boshlang'ich qoldiq (OP-23) —
--   yo'q; «Boshqa» (EX-49) — izoh majburiy. Yopilgan davr yozuvi — rad (fin:locked; QT kabi — Direktor davrni qayta ochadi).
-- Holat: yozuv «tasdiqlangan» — uning oxirgi jurnal yozuvidagi statiya hozirgi statiyasiga teng bo'lsa (aks holda — taxminiy; statiyani
--   keyin boshqa yo'l bilan o'zgartirish ham tasdiqni bekor qiladi). RP-09 (fin_matrix) shu oylarda «≈» belgisini shundan oladi.
-- Imzo (fin_exp_class_sign): faqat buxgalter; oyning barcha yozuvlari tasdiqlangan bo'lsa. Imzo yozuvi saqlanadi (yozuvlar soni, jami,
--   «Boshqa» summasi, oxirgi jurnal raqami); keyin oyning tasnifi, yozuvlar soni yoki summasi o'zgarsa — imzo «eskirgan» (o'qishda
--   hisoblanadi) va qayta imzolanadi.
-- Huquq: ko'rish va tasnif — buxgalter, Moliya menejeri, Direktor; imzo — buxgalter. Jadvallarga to'g'ridan-to'g'ri yozish yo'q
--   (trg_fin_class_guard: faqat qo'shiladi va faqat shu funksiyalar orqali).
-- HOLAT: run-all.sql'da «--dev \ir» — kassa moduli bilan birga (fin-matrix.sql dan oldin: RP-09 shu yordamchilarni ishlatadi;
--   fin-guard.sql dan oldin: fin_exp_classify pul jadvaliga yozadi — bayroq unga ham qo'yiladi). Idempotent.
-- =====================================================================

-- ---------- Jadvallar ----------
create table if not exists public.fin_exp_class (     -- tasnif jurnali (faqat qo'shiladi)
  id            bigint generated always as identity primary key,
  "expenseId"   text not null,                       -- expenses.id (yozuv keyin o'chirilsa ham jurnal qoladi)
  month         text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),   -- xarajat oyi (tasnif paytidagi)
  "oldArticle"  text,                                -- oldingi statiya (yozuvdagi yoki toifadan; yo'q bo'lsa — null)
  "newArticle"  text not null references public.fin_articles(id),
  note          text not null default '',
  "byUid"       text not null,
  "byRole"      text not null default '',
  at            timestamptz not null default now()
);
create index if not exists fin_exp_class_exp_idx on public.fin_exp_class ("expenseId", id desc);
create index if not exists fin_exp_class_month_idx on public.fin_exp_class (month, id desc);

create table if not exists public.fin_exp_class_sign (   -- buxgalter imzosi (oy bo'yicha; tarix saqlanadi)
  id             bigint generated always as identity primary key,
  month          text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  n              int not null,                      -- imzolangan yozuvlar soni
  total          numeric not null,                  -- ularning jami
  ex49           numeric not null default 0,        -- shundan «Boshqa» (EX-49)
  "lastClassId"  bigint,                            -- imzo paytidagi oyning oxirgi jurnal yozuvi
  "byUid"        text not null,
  at             timestamptz not null default now()
);
create index if not exists fin_exp_class_sign_month_idx on public.fin_exp_class_sign (month, id desc);

do $$ declare t text; begin
  foreach t in array array['fin_exp_class', 'fin_exp_class_sign'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format('create policy %I on public.%I for select using (app.is_admin() or app.fin_list2())', t || '_sel', t);
  end loop;
end $$;

-- Faqat qo'shiladi va faqat tasnif funksiyalari orqali (bayroq iqror.fin_class_rpc — fin_exp_classify / fin_exp_class_sign da);
--   server (service_role) va psql ham istisno emas — imzo va tasdiq faqat odamning o'z amali bo'lishi kerak.
create or replace function app.fin_class_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if tg_op <> 'INSERT' then
    raise exception '«%» jadvali faqat qo''shiladi (o''zgartirish va o''chirish yo''q)', tg_table_name using errcode = '42501', hint = 'fin:class_immutable';
  end if;
  if coalesce(current_setting('iqror.fin_class_rpc', true), '') <> '1' then
    raise exception 'Statiya tasnifi faqat «Statiya tasnifi» funksiyalari orqali yoziladi' using errcode = '42501', hint = 'fin:class_rpc_only';
  end if;
  return new;
end $$;
revoke all on function app.fin_class_guard() from public, anon, authenticated;
do $$ declare t text; begin
  foreach t in array array['fin_exp_class', 'fin_exp_class_sign'] loop
    execute format('drop trigger if exists trg_fin_class_guard on public.%I', t);
    execute format('create trigger trg_fin_class_guard before insert or update or delete on public.%I for each row execute function app.fin_class_guard()', t);
  end loop;
end $$;

-- ---------- Doira va holat ----------
-- Tasnif davri (reja F2.3: noyabr–yanvar)
create or replace function app.fin_class_months() returns text[]
language sql immutable set search_path = public, app, pg_temp as $$ select array['2026-11', '2026-12', '2027-01']::text[] $$;
revoke all on function app.fin_class_months() from public, anon, authenticated;

-- Yozuv tasnif doirasidami (ustunlar alohida — so'rovlarda indekssiz, qatorga bog'lanmagan holda ishlatiladi)
create or replace function app.fin_class_in(p_kind text, p_doc text, p_cash text, p_month text, p_date text) returns boolean
language sql immutable set search_path = public, app, pg_temp as $$
  select coalesce(p_kind, 'expense') = 'expense' and p_doc is null and p_cash is null
     and coalesce(nullif(p_month, ''), left(coalesce(p_date, ''), 7)) = any(app.fin_class_months())
$$;
revoke all on function app.fin_class_in(text, text, text, text, text) from public, anon, authenticated;

-- Statiya tasnifda tanlanadimi: faol, xarajat yoki operatsiya (IN emas), hisobvarag'i bor; hisoblash (EX-44 / 45 / 47) va texnik (OP-23) — yo'q
create or replace function app.fin_class_article_ok(p_art public.fin_articles) returns boolean
language sql stable set search_path = public, app, pg_temp as $$
  select coalesce(p_art.active and p_art.kind in ('EX', 'OP') and nullif(p_art."accountCode", '') is not null
                  and p_art.id not in ('EX-44', 'EX-45', 'EX-47', 'OP-23'), false)
$$;
revoke all on function app.fin_class_article_ok(public.fin_articles) from public, anon, authenticated;

-- Yozuv shu statiya bilan tasdiqlanganmi: oxirgi jurnal yozuvidagi statiya = berilgan (hozirgi) statiya
create or replace function app.fin_class_ok(p_id text, p_article text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select c."newArticle" = p_article from public.fin_exp_class c where c."expenseId" = p_id order by c.id desc limit 1), false)
$$;
revoke all on function app.fin_class_ok(text, text) from public, anon, authenticated;

-- Oylar bo'yicha holat: [{month, n, confirmed, total, ex49, sign: {by, at, n, total, valid} | null}] (berilgan tartibda)
create or replace function app.fin_class_stats(p_months text[]) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  with r as (
    select coalesce(nullif(e.month, ''), left(e.date, 7)) as mo, e.id, coalesce(e.amount, 0) as amt,
           coalesce(nullif(e."articleId", ''), cm."articleId") as art
      from public.expenses e left join public.fin_category_map cm on cm.category = e.category
     where app.fin_class_in(e.kind, e."expDocId", e."cashDocId", e.month, e.date)
       and coalesce(nullif(e.month, ''), left(e.date, 7)) = any(p_months)),
  s as (select mo, count(*) as n, count(*) filter (where art is not null and app.fin_class_ok(id, art)) as ok, sum(amt) as total,
               coalesce(sum(amt) filter (where art = 'EX-49'), 0) as ex49
          from r group by mo),
  g as (select distinct on (x.month) x.* from public.fin_exp_class_sign x where x.month = any(p_months) order by x.month, x.id desc),
  j as (select c.month, max(c.id) as last from public.fin_exp_class c where c.month = any(p_months) group by c.month)
  select coalesce(jsonb_agg(jsonb_build_object(
           'month', mo.m, 'n', coalesce(s.n, 0), 'confirmed', coalesce(s.ok, 0), 'total', coalesce(s.total, 0), 'ex49', coalesce(s.ex49, 0),
           'sign', case when g.id is null then null else jsonb_build_object(
                     'by', app.fin_exp_who(g."byUid"), 'at', g.at, 'n', g.n, 'total', g.total,
                     'valid', g.n = coalesce(s.n, 0) and g.total = coalesce(s.total, 0) and coalesce(s.ok, 0) = coalesce(s.n, 0)
                              and g."lastClassId" is not distinct from j.last) end)
           order by mo.o), '[]'::jsonb)
    from unnest(p_months) with ordinality mo(m, o)
    left join s on s.mo = mo.m left join g on g.month = mo.m left join j on j.month = mo.m
$$;
revoke all on function app.fin_class_stats(text[]) from public, anon, authenticated;

-- ---------- Ro'yxat (buxgalter, Moliya menejeri, Direktor) ----------
--   {ok, month, months: holat (barcha tasnif oylari), lockedThrough, canSign, articles: [{id, nameUz, kind, needsNote}],
--    rows: [{id, date, category, amount, note, method, articleId (hozirgi: yozuvdagi yoki toifadan), mapArticle, confirmed, locked,
--            last: {by, at, old, new, note} | null}]}
create or replace function public.fin_exp_class_list(p_month text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_m text := btrim(coalesce(p_month, '')); v_lock date; v_mend date;
begin
  if not (app.is_admin() or app.fin_list2()) then
    raise exception 'Ruxsat yo''q: statiya tasnifini buxgalter, Moliya menejeri yoki Direktor ko''radi' using errcode = '42501';
  end if;
  if not (v_m = any(app.fin_class_months())) then
    raise exception 'Oy noto''g''ri: tasnif davri — %', array_to_string(app.fin_class_months(), ', ') using errcode = '22023', hint = 'fin:class_month';
  end if;
  select o."lockedThrough" into v_lock from public.fin_org o where o.id = 'main';
  v_mend := ((v_m || '-01')::date + interval '1 month')::date - 1;
  return jsonb_build_object(
    'ok', true, 'month', v_m, 'months', app.fin_class_stats(app.fin_class_months()), 'lockedThrough', v_lock, 'canSign', app.is_accountant(),
    'articles', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'nameUz', a."nameUz", 'kind', a.kind, 'needsNote', a."needsNote")
                                           order by a."sortOrder", a.id)
                            from public.fin_articles a where app.fin_class_article_ok(a)), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
               'id', x.id, 'date', x.date, 'category', x.category, 'amount', x.amount, 'note', x.note, 'method', x.method,
               'articleId', x.art, 'mapArticle', x.map, 'confirmed', x.art is not null and app.fin_class_ok(x.id, x.art),
               'locked', v_lock is not null and coalesce(app.fin_text_day(x.date), v_mend) <= v_lock,
               'last', (select jsonb_build_object('by', app.fin_exp_who(c."byUid"), 'at', c.at, 'old', c."oldArticle", 'new', c."newArticle", 'note', c.note)
                          from public.fin_exp_class c where c."expenseId" = x.id order by c.id desc limit 1))
             order by x.date nulls last, x.id)
             from (select e.id, e.date, coalesce(e.category, '') as category, coalesce(e.amount, 0) as amount, coalesce(e.note, '') as note,
                          coalesce(e.method, '') as method, coalesce(nullif(e."articleId", ''), cm."articleId") as art, cm."articleId" as map
                     from public.expenses e left join public.fin_category_map cm on cm.category = e.category
                    where app.fin_class_in(e.kind, e."expDocId", e."cashDocId", e.month, e.date)
                      and coalesce(nullif(e.month, ''), left(e.date, 7)) = v_m) x), '[]'::jsonb));
end $$;
revoke all on function public.fin_exp_class_list(text) from public, anon;
grant execute on function public.fin_exp_class_list(text) to authenticated;

-- ---------- Tasnif (buxgalter, Moliya menejeri, Direktor) ----------
--   p_items: [{id, articleId, note}] (1–200). Hammasi tekshiriladi va bitta tranzaksiyada yoziladi (biror qator xato bo'lsa — hech biri).
--   Natija: {ok, changed (statiya o'zgardi), confirmed (toifadagi / avvalgi statiya tasdiqlandi yoki izoh yangilandi), unchanged (takror)}.
--   iqror.fin_rpc — F2.9 pul funksiyasi bayrog'i (expenses ga yozadi): fin-guard.sql ham qo'yadi, bu yerda — fayl alohida qayta yuklansa ham
--   to'g'ridan-to'g'ri yozuv detektori uni sahifa yozuvi deb hisoblamasin.
create or replace function public.fin_exp_classify(p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp set iqror.fin_class_rpc = '1' set iqror.fin_rpc = '1' as $$
declare
  v_uid text := app.uid(); v_role text := coalesce(app.my_role(), ''); v_it jsonb; v_id text; v_aid text; v_note text; v_row public.expenses;
  v_art public.fin_articles; v_map text; v_cur text; v_m text; v_ids text[] := '{}'; v_ch int := 0; v_cf int := 0; v_same int := 0;
  v_why text; v_last text;
begin
  if not (app.is_admin() or app.fin_list2()) then
    raise exception 'Ruxsat yo''q: statiyani buxgalter, Moliya menejeri yoki Direktor belgilaydi' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 200 then
    raise exception 'Tasnif ro''yxati bo''sh yoki juda katta (1–200 yozuv)' using errcode = '22023', hint = 'fin:bad_input';
  end if;
  for v_it in select x from jsonb_array_elements(p_items) x loop
    if jsonb_typeof(v_it) is distinct from 'object' then
      raise exception 'Tasnif qatori noto''g''ri' using errcode = '22023', hint = 'fin:bad_input';
    end if;
    v_id := nullif(btrim(coalesce(v_it ->> 'id', '')), '');
    v_aid := nullif(btrim(coalesce(v_it ->> 'articleId', '')), '');
    v_note := left(btrim(coalesce(v_it ->> 'note', '')), 300);
    if v_id is null or v_aid is null then
      raise exception 'Har qatorda xarajat va statiya bo''lishi kerak' using errcode = '22023', hint = 'fin:bad_input';
    end if;
    if v_id = any(v_ids) then
      raise exception 'Bitta xarajat ro''yxatda ikki marta (%)', v_id using errcode = '22023', hint = 'fin:bad_input';
    end if;
    v_ids := v_ids || v_id;
    select * into v_row from public.expenses e where e.id = v_id for update;
    if not found then
      raise exception 'Xarajat topilmadi (%) — ro''yxatni yangilang', v_id using errcode = '22023', hint = 'fin:class_missing';
    end if;
    v_m := coalesce(nullif(v_row.month, ''), left(coalesce(v_row.date, ''), 7));
    if not app.fin_class_in(v_row.kind, v_row."expDocId", v_row."cashDocId", v_row.month, v_row.date) then
      v_why := case when v_row."expDocId" is not null then 'hujjat bilan kiritilgan — statiya hujjatda («Tuzatish»)'
                    when v_row."cashDocId" is not null then 'kassa hujjatidan ko''chgan — statiya kassa hujjatida (qayta tasnif dalolatnomasi)'
                    when coalesce(v_row.kind, '') <> 'expense' then 'oylik maosh hisobi qatori'
                    else 'oyi ' || coalesce(nullif(v_m, ''), 'yo''q') || ', tasnif davri — ' || array_to_string(app.fin_class_months(), ', ') end;
      raise exception 'Bu xarajat tasnif doirasida emas (%): %', v_id, v_why using errcode = '22023', hint = 'fin:class_scope';
    end if;
    select * into v_art from public.fin_articles a where a.id = v_aid;
    if not found or not app.fin_class_article_ok(v_art) then
      raise exception 'Statiya topilmadi yoki xarajat tasnifida tanlanmaydi (%)', v_aid using errcode = '22023', hint = 'fin:class_article';
    end if;
    if v_art."needsNote" and length(v_note) < 3 then
      raise exception '«%» statiyasi uchun izoh majburiy (xarajat %)', v_art."nameUz", v_id using errcode = '22023', hint = 'fin:class_note';
    end if;
    -- yopilgan davr: yozuv sanasi (sanasiz — oy oxiri) qulfdan keyin bo'lsin
    perform app.fin_lock_check(coalesce(app.fin_text_day(v_row.date), ((v_m || '-01')::date + interval '1 month')::date - 1), 'Xarajat');
    select cm."articleId" into v_map from public.fin_category_map cm where cm.category = v_row.category;
    v_cur := coalesce(nullif(v_row."articleId", ''), v_map);
    select c.note into v_last from public.fin_exp_class c where c."expenseId" = v_id order by c.id desc limit 1;
    if v_cur is not distinct from v_aid and app.fin_class_ok(v_id, v_aid) and coalesce(v_last, '') = v_note then
      v_same := v_same + 1;
      continue;
    end if;
    if v_row."articleId" is distinct from v_aid then
      update public.expenses set "articleId" = v_aid where id = v_id;
    end if;
    if v_cur is distinct from v_aid then v_ch := v_ch + 1; else v_cf := v_cf + 1; end if;
    insert into public.fin_exp_class ("expenseId", month, "oldArticle", "newArticle", note, "byUid", "byRole", at)
      values (v_id, v_m, v_cur, v_aid, v_note, coalesce(v_uid, ''), v_role, app.fin_now());
  end loop;
  return jsonb_build_object('ok', true, 'changed', v_ch, 'confirmed', v_cf, 'unchanged', v_same);
end $$;
revoke all on function public.fin_exp_classify(jsonb) from public, anon;
grant execute on function public.fin_exp_classify(jsonb) to authenticated;

-- ---------- Imzo (faqat buxgalter) ----------
--   Oyning barcha yozuvlari tasdiqlangan bo'lishi kerak; amaldagi (eskirmagan) imzo bo'lsa — {ok, dup}. Oxirgi jurnal raqami holatdan OLDIN
--   o'qiladi: shu orada boshqa tasnif yozilsa, imzo darhol «eskirgan» bo'ladi (buxgalter ko'rmagan o'zgarish imzoga kirmaydi).
create or replace function public.fin_exp_class_sign(p_month text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp set iqror.fin_class_rpc = '1' as $$
declare v_m text := btrim(coalesce(p_month, '')); v_s jsonb; v_last bigint;
begin
  if not app.is_accountant() then
    raise exception 'Ruxsat yo''q: statiya tasnifini buxgalter imzolaydi' using errcode = '42501';
  end if;
  if not (v_m = any(app.fin_class_months())) then
    raise exception 'Oy noto''g''ri: tasnif davri — %', array_to_string(app.fin_class_months(), ', ') using errcode = '22023', hint = 'fin:class_month';
  end if;
  perform pg_advisory_xact_lock(hashtext('iqror:fin_class_sign:' || v_m));
  select max(c.id) into v_last from public.fin_exp_class c where c.month = v_m;
  v_s := app.fin_class_stats(array[v_m]) -> 0;
  if (v_s ->> 'n')::int = 0 then
    raise exception 'Bu oyda tasniflanadigan eski xarajat yo''q' using errcode = '22023', hint = 'fin:class_empty';
  end if;
  if (v_s ->> 'confirmed')::int < (v_s ->> 'n')::int then
    raise exception 'Imzolash uchun oyning barcha yozuvlari tasdiqlangan bo''lishi kerak: % tadan % tasi qoldi',
      (v_s ->> 'n')::int, (v_s ->> 'n')::int - (v_s ->> 'confirmed')::int using errcode = '22023', hint = 'fin:class_open';
  end if;
  if coalesce((v_s #>> '{sign,valid}')::boolean, false) then
    return jsonb_build_object('ok', true, 'dup', true, 'month', v_m);
  end if;
  insert into public.fin_exp_class_sign (month, n, total, ex49, "lastClassId", "byUid", at)
    values (v_m, (v_s ->> 'n')::int, (v_s ->> 'total')::numeric, (v_s ->> 'ex49')::numeric, v_last, coalesce(app.uid(), ''), app.fin_now());
  return jsonb_build_object('ok', true, 'month', v_m, 'n', (v_s ->> 'n')::int, 'total', (v_s ->> 'total')::numeric);
end $$;
revoke all on function public.fin_exp_class_sign(text) from public, anon;
grant execute on function public.fin_exp_class_sign(text) to authenticated;

notify pgrst, 'reload schema';
