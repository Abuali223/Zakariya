\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-period.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-period.sql — MOLIYA ISH REJASI, 1a-BOSQICH (F1.16): DAVR SURATI VA YOPILGAN DAVR QULFI (CT-27, CT-01).
--   fin_snapshots (kassa.sql)   — davr oxiridagi holat surati (31-dekabr — yillik; oy oxiri; qo'lda): o'quvchilar bo'yicha
--                                 qarzdorlik va avanslar, aniqlanmagan tushumlar, kassa qoldig'i, hujjat hisoblagichlari,
--                                 to'lanmagan ish haqi, berilishi kerak bo'lgan qaytarishlar. O'zgarmaydi (faqat qo'shiladi),
--                                 SHA-256 xeshi bilan — keyin bosh kitobning boshlang'ich qoldig'i shundan tekshiriladi (F4.4).
--   fin_snapshot_take(p)        — suratni olish (FAQAT Direktor); xohlasa shu sanagacha davrni yopadi;
--   fin_snapshots_list() / fin_snapshot_get(id) — ro'yxat va to'liq surat (xeshi qayta hisoblanib tekshiriladi);
--   fin_period_lock(date, note) — davr qulfi: shu sanagacha (shu kun ham) pul yozuvlari kiritilmaydi va o'zgartirilmaydi
--                                 (42501; server — webhook'lar — mustasno). Orqaga surish — faqat sabab bilan.
--   Qulf qamrovi (1a): to'lovlar (yangi yozuvning kassa kuni), «Buxgalteriya» xarajatlari, maosh to'lovlari, xodim avanslari
--   (yangi yozuv, o'zgartirish, o'chirish). Kassa hujjatlari doim bugungi kunga yoziladi — ularga qulf kerak emas; lekin:
--   davr faqat shu sanagacha bo'lgan kassa kunlari yopilgan bo'lsa yopiladi (app.fin_lock_ready), yopilgan davrdagi kassa kuni
--   qayta ochilmaydi va birinchi kassa kuni yopilgan davrga qo'yilmaydi (kassa-day.sql: kassa_day_reopen, kassa_opening_set).
--   Barcha pul jadvallari uchun oy qulfi — 2-bosqich (F2.8).
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi.
-- =====================================================================

-- ---------- Jadval ----------
--   public.fin_snapshots kassa.sql da yaratilgan (id, kind, "asOf", payload, hash, note, "createdAt", "createdBy"; faqat qo'shiladi —
--   app.kassa_append_only: o'zgartirish va o'chirish yo'q, yozish faqat funksiya orqali; o'qish — Direktor va 2-ro'yxat).
--   Bu yerda — qo'shimcha ustunlar: qaysi KUN oxiri holati, shu kun uchun nechanchi surat, kechikib olinganmi.
alter table public.fin_snapshots add column if not exists "asOfDay" date;
alter table public.fin_snapshots add column if not exists version int not null default 1 check (version > 0);
alter table public.fin_snapshots add column if not exists late boolean not null default false;   -- "asOfDay" dan KEYIN olingan: keyingi kunlar harakati aralashgan bo'lishi mumkin
create unique index if not exists fin_snapshots_day_ver on public.fin_snapshots ("asOfDay", version) where "asOfDay" is not null;

-- ---------- Surat mazmuni ----------
--   students       — qarzi (to'liq to'lanmagan fakturasi), kelgusi oy uchun oldindan to'lovi yoki avansi bor o'quvchilar;
--   unmatched      — o'quvchiga biriktirilmagan tushumlar;  cash — kassalar qoldig'i;  counters — hujjat hisoblagichlari;
--   salary         — tasdiqlangan vedomostlar bo'yicha hali to'lanmagan (yoki ortiqcha to'langan) ish haqi;
--   refundsPending — Direktor tasdiqlagan, kassadan hali berilmagan qaytarishlar.
--   totals: receivable (shu oygacha bo'lgan fakturalar qarzi — 4010), receivableFuture (kelgusi oylar fakturalari qoldig'i),
--           prepaid (kelgusi oylar fakturalariga to'langan — 6310), credit (avans — 6310), unmatched (6390), cash (5010),
--           salaryPayable (6710), refundsPending.
create or replace function app.fin_snapshot_data(p_as_of date) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_m text := to_char(p_as_of, 'YYYY-MM'); v_students jsonb; v_unm jsonb; v_cash jsonb; v_cnt jsonb; v_sal jsonb; v_ref jsonb; v_tot jsonb;
begin
  with inv as (
    select i.id, i."studentId" as sid, coalesce(i.month, '') as month, coalesce(i.amount, 0) as amount, coalesce(i.status, '') as status,
           case when i.status = 'paid' then greatest(coalesce(i."paidAmount", 0), coalesce(i.amount, 0)) else coalesce(i."paidAmount", 0) end as paid
      from public.invoices i
     where coalesce(i.status, '') not in ('canceled', 'reversed') and coalesce(i."studentId", '') <> ''),
  pick as (
    select * from inv where (status <> 'paid' and amount - paid > 0) or (month > v_m and paid > 0)),
  keys as (
    select sid from pick union select c.id from public.student_credit c where coalesce(c.credit, 0) <> 0)
  select coalesce(jsonb_agg(jsonb_build_object(
           'studentId', k.sid,
           'name', coalesce((select st.name from public.students st where st."studentId" = k.sid or st.id = k.sid order by (st."studentId" = k.sid) desc limit 1), ''),
           'credit', coalesce((select c.credit from public.student_credit c where c.id = k.sid), 0),
           'invoices', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'month', p.month, 'amount', p.amount, 'paid', p.paid, 'status', p.status)
                                                 order by p.month, p.id) from pick p where p.sid = k.sid), '[]'::jsonb))
           order by k.sid), '[]'::jsonb)
    into v_students from keys k;
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'provider', coalesce(p.provider, ''), 'amount', coalesce(p.amount, 0),
                                               'day', app.pay_day(p."createdAt", p.raw)) order by p."createdAt", p.id), '[]'::jsonb)
    into v_unm from public.payments p where coalesce(p.status, '') = 'unmatched' and coalesce(p.amount, 0) > 0;
  select coalesce(jsonb_agg(jsonb_build_object('desk', k.id, 'isTest', k."isTest", 'startDay', k."startDay", 'openingAmount', k."openingAmount",
           'lastDay', (select max(d.day) from public.cash_days d where d.desk = k.id),
           'balance', coalesce((select app.kassa_day_balance(d.id) from public.cash_days d where d.desk = k.id and d.status = 'open'),
                               (select d.closing from public.cash_days d where d.desk = k.id and d.status <> 'open' order by d.day desc limit 1),
                               k."openingAmount", 0)) order by k.id), '[]'::jsonb)
    into v_cash from public.cash_desks k where k.active;
  select coalesce(jsonb_agg(jsonb_build_object('desk', c.desk, 'series', c.series, 'year', c.year, 'lastNo', c."lastNo") order by c.desk, c.series, c.year), '[]'::jsonb)
    into v_cnt from public.doc_counters c;
  select coalesce(jsonb_agg(jsonb_build_object('month', x.month, 'personId', x.pid, 'name', x.name, 'payable', x.payable, 'paid', x.paid, 'due', x.payable - x.paid)
                            order by x.month, x.pid), '[]'::jsonb)
    into v_sal
    from (select l."runId" as month, l."personId" as pid, coalesce(l.name, '') as name, coalesce(l.payable, 0) as payable,
                 coalesce((select sum(coalesce(s.paid, 0)) from public.salary_payments s where s."teacherId" = l."personId" and s.month = l."runId"), 0) as paid
            from public.payroll_lines l join public.payroll_runs r on r.id = l."runId"
           where r.status = 'approved' and l."runId" <= v_m) x
   where x.payable - x.paid <> 0;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'amount', c.amount, 'party', c."partyName", 'approvedAt', c."dirApprovedAt") order by c."createdAt"), '[]'::jsonb)
    into v_ref from public.cash_docs c where c.op = 'out_refund' and c.status = 'approved';
  v_tot := jsonb_build_object(
    'students', jsonb_array_length(v_students),
    'receivable', coalesce((select sum((i ->> 'amount')::numeric - (i ->> 'paid')::numeric) from jsonb_array_elements(v_students) s, jsonb_array_elements(s -> 'invoices') i
                             where i ->> 'status' <> 'paid' and i ->> 'month' <= v_m), 0),
    'receivableFuture', coalesce((select sum((i ->> 'amount')::numeric - (i ->> 'paid')::numeric) from jsonb_array_elements(v_students) s, jsonb_array_elements(s -> 'invoices') i
                                   where i ->> 'status' <> 'paid' and i ->> 'month' > v_m), 0),
    'prepaid', coalesce((select sum((i ->> 'paid')::numeric) from jsonb_array_elements(v_students) s, jsonb_array_elements(s -> 'invoices') i where i ->> 'month' > v_m), 0),
    'credit', coalesce((select sum((s ->> 'credit')::numeric) from jsonb_array_elements(v_students) s), 0),
    'unmatched', coalesce((select sum((u ->> 'amount')::numeric) from jsonb_array_elements(v_unm) u), 0),
    'unmatchedCount', jsonb_array_length(v_unm),
    'cash', coalesce((select sum((k ->> 'balance')::numeric) from jsonb_array_elements(v_cash) k where not (k ->> 'isTest')::boolean), 0),
    'salaryPayable', coalesce((select sum((x ->> 'due')::numeric) from jsonb_array_elements(v_sal) x), 0),
    'refundsPending', coalesce((select sum((x ->> 'amount')::numeric) from jsonb_array_elements(v_ref) x), 0));
  return jsonb_build_object('asOf', p_as_of, 'month', v_m, 'students', v_students, 'unmatched', v_unm, 'cash', v_cash, 'counters', v_cnt,
                            'salary', v_sal, 'refundsPending', v_ref, 'totals', v_tot);
end $$;
revoke all on function app.fin_snapshot_data(date) from public, anon, authenticated;

-- ---------- Davr qulfi ----------
-- Yozuv sanasi yopilgan davrga tushsa — rad (server / webhook mustasno).
create or replace function app.fin_lock_check(p_day date, p_what text) returns void
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_lock date;
begin
  if p_day is null or app.is_system() then return; end if;
  select o."lockedThrough" into v_lock from public.fin_org o where o.id = 'main';
  if v_lock is not null and p_day <= v_lock then
    raise exception '%: % — yopilgan davr (% gacha yopilgan). Sana % dan keyin bo''lishi kerak; yopilgan davrni faqat Direktor qayta ochadi',
      coalesce(p_what, 'Yozuv'), to_char(p_day, 'DD.MM.YYYY'), to_char(v_lock, 'DD.MM.YYYY'), to_char(v_lock, 'DD.MM.YYYY')
      using errcode = '42501', hint = 'fin:locked';
  end if;
end $$;
revoke all on function app.fin_lock_check(date, text) from public, anon, authenticated;

-- Matn ko'rinishidagi sana ('YYYY-MM-DD') — xavfsiz o'qish.
create or replace function app.fin_text_day(p text) returns date
language plpgsql immutable set search_path = public, app, pg_temp as $$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}' then return null; end if;
  begin return left(p, 10)::date; exception when others then return null; end;
end $$;
revoke all on function app.fin_text_day(text) from public, anon, authenticated;

-- To'lovlar: YANGI yozuvning kassa kuni yopilgan davrga tushmasin (qo'lda to'lovda kassir tanlagan «Sana»).
--   Mavjud to'lov holatining o'zgarishi (qaytarish, biriktirish) — bugungi amal, cheklanmaydi.
create or replace function app.fin_lock_payments() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  perform app.fin_lock_check(app.pay_day(coalesce(new."createdAt", app.fin_now()), new.raw), 'To‘lov');
  return new;
end $$;
revoke all on function app.fin_lock_payments() from public, anon, authenticated;
drop trigger if exists trg_fin_zlock on public.payments;   -- nomi «z» bilan: trg_fin_server_ts dan KEYIN ishlaydi (createdAt serverdan qo'yilgan bo'ladi)
create trigger trg_fin_zlock before insert on public.payments for each row execute function app.fin_lock_payments();

-- Xarajat, maosh to'lovi, xodim avansi: yopilgan davr sanasi bilan yangi yozuv ham, o'sha davr yozuvini o'zgartirish / o'chirish ham yo'q.
create or replace function app.fin_lock_rows() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_what text := case tg_table_name when 'expenses' then 'Xarajat' when 'salary_payments' then 'Maosh to‘lovi' else 'Xodim avansi' end;
begin
  if tg_op <> 'INSERT' then perform app.fin_lock_check(app.fin_text_day(old.date), v_what); end if;
  if tg_op <> 'DELETE' then perform app.fin_lock_check(app.fin_text_day(new.date), v_what); end if;
  return coalesce(new, old);
end $$;
revoke all on function app.fin_lock_rows() from public, anon, authenticated;
do $$ declare t text; begin
  foreach t in array array['expenses', 'salary_payments', 'staff_advances'] loop
    execute format('drop trigger if exists trg_fin_zlock on public.%I', t);
    execute format('create trigger trg_fin_zlock before insert or update or delete on public.%I for each row execute function app.fin_lock_rows()', t);
  end loop;
end $$;

-- Davrni yopishdan oldin: shu sanagacha bo'lgan kassa kunlari YOPILGAN bo'lishi kerak. Ochiq kun — hali sanalmagan pul: uni
--   yopishda farq hujjati yozilishi mumkin, bu esa yopilgan davrga yozuv bo'lardi. Sinov kassasi hisobga olinmaydi.
create or replace function app.fin_lock_ready(p_through date) returns void
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_day date;
begin
  if p_through is null then return; end if;
  select min(d.day) into v_day from public.cash_days d join public.cash_desks k on k.id = d.desk
   where d.status = 'open' and d.day <= p_through and not k."isTest";
  if v_day is not null then
    raise exception 'Davrni yopib bo''lmaydi: % kassa kuni hali yopilmagan — avval kunni sanab yoping', to_char(v_day, 'DD.MM.YYYY')
      using errcode = 'P0001', hint = 'fin:open_day';
  end if;
end $$;
revoke all on function app.fin_lock_ready(date) from public, anon, authenticated;

-- Qulfni o'rnatish: FAQAT Direktor. Oldinga (yangi davrni yopish) — erkin; orqaga yoki olib tashlash (yopilgan davrni qayta ochish)
--   — faqat sabab bilan (o'zgarishlar tarixida qoladi). Bugungi va kelajakdagi kun yopilmaydi.
create or replace function public.fin_period_lock(p_through date, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_old date; v_note text := left(btrim(coalesce(p_note, '')), 300);
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: davrni faqat Direktor yopadi' using errcode = '42501'; end if;
  select o."lockedThrough" into v_old from public.fin_org o where o.id = 'main' for update;
  if p_through is not null and p_through >= app.fin_today() then
    raise exception 'Bugungi yoki kelajakdagi kun yopilmaydi' using errcode = '22023', hint = 'fin:lock_day';
  end if;
  if v_old is not null and (p_through is null or p_through < v_old) and length(v_note) < 5 then
    raise exception 'Yopilgan davrni qayta ochish uchun sababni yozing' using errcode = '22023', hint = 'fin:lock_reason';
  end if;
  if p_through is not null and (v_old is null or p_through > v_old) then perform app.fin_lock_ready(p_through); end if;
  update public.fin_org
     set "lockedThrough" = p_through, "updatedAt" = now(), "updatedBy" = app.uid(),
         extra = coalesce(extra, '{}'::jsonb) || jsonb_build_object('lockNote', v_note, 'lockPrev', v_old)
   where id = 'main';
  return jsonb_build_object('ok', true, 'lockedThrough', p_through, 'previous', v_old);
end $$;
revoke all on function public.fin_period_lock(date, text) from public, anon;
grant execute on function public.fin_period_lock(date, text) to authenticated;

-- ---------- Suratni olish ----------
--   p: asOf ('YYYY-MM-DD' — bugundan kech emas), note, lock (true — shu sanagacha davr ham yopiladi; faqat o'tgan kun uchun)
create or replace function public.fin_snapshot_take(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_as date; v_today date := app.fin_today(); v_kind text; v_ver int; v_data jsonb; v_hash text; v_id text;
  v_lock boolean; v_old date;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: davr suratini faqat Direktor oladi' using errcode = '42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'fin:bad_input'; end if;
  v_as := app.fin_text_day(p ->> 'asOf');
  if v_as is null or v_as > v_today or v_as < v_today - 400 then
    raise exception 'Surat sanasi noto''g''ri (bugundan kech bo''lmasin)' using errcode = '22023', hint = 'fin:bad_input';
  end if;
  v_lock := lower(coalesce(p ->> 'lock', '')) in ('true', 't', '1');
  if v_lock and v_as >= v_today then
    raise exception 'Bugungi kun yopilmaydi: suratni qulfsiz oling yoki ertaga yoping' using errcode = '22023', hint = 'fin:lock_day';
  end if;
  if v_lock then perform app.fin_lock_ready(v_as); end if;   -- yopib bo'lmasa — surat ham olinmaydi (bitta amal)
  perform pg_advisory_xact_lock(hashtext('iqror_fin_snapshot'));
  v_kind := case when to_char(v_as, 'MM-DD') = '12-31' then 'year_end'
                 when (v_as + 1) = date_trunc('month', v_as + 1)::date then 'month_end' else 'manual' end;
  select coalesce(max(s.version), 0) + 1 into v_ver from public.fin_snapshots s where s."asOfDay" = v_as;
  v_data := app.fin_snapshot_data(v_as);
  v_hash := encode(sha256(convert_to(v_data::text, 'UTF8')), 'hex');
  v_id := 'fs_' || to_char(v_as, 'YYYYMMDD') || '_' || v_ver;
  perform app.kassa_flag(true);
  insert into public.fin_snapshots (id, kind, "asOf", "asOfDay", version, late, payload, hash, note, "createdAt", "createdBy")
    values (v_id, v_kind, ((v_as + 1)::timestamp at time zone 'Asia/Tashkent') - interval '1 second', v_as, v_ver, v_today > v_as, v_data, v_hash,
            left(btrim(coalesce(p ->> 'note', '')), 300), app.fin_now(), v_uid);
  perform app.kassa_flag(false);
  if v_lock then
    select o."lockedThrough" into v_old from public.fin_org o where o.id = 'main' for update;
    if v_old is null or v_old < v_as then
      update public.fin_org set "lockedThrough" = v_as, "updatedAt" = now(), "updatedBy" = v_uid,
             extra = coalesce(extra, '{}'::jsonb) || jsonb_build_object('lockNote', 'Davr surati ' || v_id, 'lockPrev', v_old) where id = 'main';
    end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'kind', v_kind, 'asOf', v_as, 'version', v_ver, 'late', v_today > v_as, 'hash', v_hash,
                            'totals', v_data -> 'totals', 'lockedThrough', (select o."lockedThrough" from public.fin_org o where o.id = 'main'));
end $$;
revoke all on function public.fin_snapshot_take(jsonb) from public, anon;
grant execute on function public.fin_snapshot_take(jsonb) to authenticated;

-- Suratlar ro'yxati (mazmunsiz) va davr qulfi holati — Direktor va 2-ro'yxat.
create or replace function public.fin_snapshots_list() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not (app.is_admin() or app.fin_list2()) then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  return jsonb_build_object('ok', true, 'today', app.fin_today(),
    'lockedThrough', (select o."lockedThrough" from public.fin_org o where o.id = 'main'),
    'lockNote', (select o.extra ->> 'lockNote' from public.fin_org o where o.id = 'main'),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'kind', s.kind, 'asOf', s."asOfDay", 'version', s.version, 'takenAt', s."createdAt",
                                                           'takenBy', s."createdBy", 'byName', app.kassa_names(array[s."createdBy"]) ->> s."createdBy",
                                                           'late', s.late, 'note', s.note, 'totals', s.payload -> 'totals', 'hash', s.hash)
                                         order by s."asOfDay" desc, s.version desc)
                         from public.fin_snapshots s where s."asOfDay" is not null), '[]'::jsonb));
end $$;
revoke all on function public.fin_snapshots_list() from public, anon;
grant execute on function public.fin_snapshots_list() to authenticated;

-- To'liq surat; "hashOk" — saqlangan mazmun xeshi qayta hisoblanib solishtirilgan.
create or replace function public.fin_snapshot_get(p_id text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare s public.fin_snapshots%rowtype;
begin
  if not (app.is_admin() or app.fin_list2()) then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  select * into s from public.fin_snapshots x where x.id = p_id;
  if not found then raise exception 'Surat topilmadi' using errcode = '22023', hint = 'fin:not_found'; end if;
  return jsonb_build_object('ok', true, 'id', s.id, 'kind', s.kind, 'asOf', s."asOfDay", 'version', s.version, 'takenAt', s."createdAt", 'takenBy', s."createdBy",
                            'late', s.late, 'note', s.note, 'totals', s.payload -> 'totals', 'hash', s.hash,
                            'hashOk', s.hash = encode(sha256(convert_to(s.payload::text, 'UTF8')), 'hex'), 'data', s.payload);
end $$;
revoke all on function public.fin_snapshot_get(text) from public, anon;
grant execute on function public.fin_snapshot_get(text) to authenticated;

-- O'zgarishlar tarixi: davr qulfi ham yoziladi.
select app.chlog_attach('fin_org', 'nameUz,nameRu,stir,place,printLang,t1,l1,cashLimit,kassaGoLive,lockedThrough');

notify pgrst, 'reload schema';
