\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: bonus-100.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- bonus-100.sql — 100 BALL BONUSI: O'IBDO' 24 ish soati ichida taklif qiladi, Direktor 24 ish soati ichida tasdiqlaydi (D1).
--   * O'tish oyi config/finance."bonusApprovalFrom" ('YYYY-MM' — shu oy FAKTURASIDAN, ya'ni oldingi oy monitoringidan):
--     undan oldingi oylar ESKI qoida (tasdiqsiz). O'tish oyidan boshlab fakturadagi «Monitoring 100 · 100%» grant faqat
--     TASDIQLANGAN monitoring_bonus bilan (invoices."bonusRef"), 90+ (20%) ham, 100 ham — chegirma fanlarining HAMMASIDA
--     tasdiqlangan ball bo'lsa (to'liq qamrov). Tasdiqsiz 100 — 20% (qamrov to'liq bo'lsa).
--   * Raund (sinf × oy): fan o'qituvchilari kiritish muddati T0 (direktor belgilaydi; bo'lmasa config/monitoring."entryDeadlineDay"
--     — keyingi oyning N-kuni 23:59, standart 5). T0 dan keyin o'qituvchi o'zgartira olmaydi; direktor raundni yopsa — hech kim
--     (qayta ochish — direktor, sabab bilan). Qulf faqat o'tish oyidan boshlangan davrlarga (eski oylar odatdagidek).
--   * 24 soat — kalendar soati, lekin shanba, yakshanba va school_holidays kunlari sanalmaydi (Toshkent vaqti):
--     O'IBDO' muddati = T0 + 24 ish soati, Direktor muddati = taklif + 24 ish soati. Muddat o'tsa bonus yo'qolmaydi:
--     kech taklif — late; muddati o'tgan nomzod (taklif bo'lmagan) — Direktorga «muddati o'tgan», qaror SABAB bilan.
--   * Taklif — faqat O'IBDO' (zavuch), qaror — faqat Direktor, bir odam ikkalasini qila olmaydi.
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Sozlamalar
alter table public.config add column if not exists "bonusApprovalFrom" text;   -- config/finance (o'tish oyi; nurse-sick.sql guard)
alter table public.config add column if not exists "entryDeadlineDay" numeric; -- config/monitoring: keyingi oyning N-kuni 23:59

-- 2) Ish soatlari: dam olish (shanba, yakshanba) va school_holidays kunlari sanalmaydi; Toshkent vaqti.
create or replace function app.add_business_hours(p_from timestamptz, p_hours numeric) returns timestamptz
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare t timestamp := p_from at time zone 'Asia/Tashkent'; v_left numeric := greatest(coalesce(p_hours, 0), 0);
        v_end timestamp; v_avail numeric; g int := 0;
begin
  if p_from is null then return null; end if;
  while v_left > 0 and g < 800 loop
    g := g + 1;
    if extract(isodow from t) in (6, 7)
       or exists (select 1 from public.school_holidays h where h.id = to_char(t, 'YYYY-MM-DD') or h.day = to_char(t, 'YYYY-MM-DD')) then
      t := date_trunc('day', t) + interval '1 day'; continue;
    end if;
    v_end := date_trunc('day', t) + interval '1 day';
    v_avail := extract(epoch from (v_end - t)) / 3600.0;
    if v_avail >= v_left then t := t + make_interval(secs => v_left * 3600); v_left := 0;
    else v_left := v_left - v_avail; t := v_end; end if;
  end loop;
  return t at time zone 'Asia/Tashkent';
end $$;
revoke all on function app.add_business_hours(timestamptz, numeric) from public, anon;
grant execute on function app.add_business_hours(timestamptz, numeric) to authenticated, service_role;

-- 3) Chegirma fanlari (admin.html MON_DISC_SUBJECTS + monSlug + monCanon bilan AYNAN bir xil; 1–4, 10–11 — cheklov yo'q -> null).
--    Ro'yxat KANONIK fanlar: 'it' — «Informatika»ning eski qo'lda yozilgan taxallusi (app.mon_canon), alohida fan EMAS.
--    Avval ikkalasi ham talab qilinardi: 'IT'ni o'qituvchi tanlay olmaydi (SUBJECTS'da yo'q; faqat «Boshqa fan…» bilan qo'lda) ->
--    5–9-sinfda to'liq qamrov amalda bo'lmas, yangi qoidada 20% / 100% chegirma yo'qolardi. Bu funksiyalar faqat yangi qoidada
--    (bonus taklifi/tasdig'i) ishlatiladi; eski qoida oylari hisobi admin.html'da avvalgidek («IT» alohida).
create or replace function app.mon_disc_slugs(p_grade int, p_lang text) returns text[]
language sql immutable set search_path = pg_catalog as $$
  select case
    when p_grade between 5 and 6 then case when p_lang = 'ru'
      then array['rus_tili','matematika','ingliz_tili','informatika','biologiya']
      else array['ona_tili','matematika','ingliz_tili','informatika','biologiya'] end
    when p_grade between 7 and 9 then case when p_lang = 'ru'
      then array['rus_tili','matematika','ingliz_tili','informatika','biologiya','kimyo']
      else array['ona_tili','matematika','ingliz_tili','informatika','biologiya','kimyo'] end
    else null end
$$;
-- Fan slug'ining kanonik shakli (admin.html monCanon bilan bir xil): taxallus -> asosiy fan.
create or replace function app.mon_canon(p_slug text) returns text
language sql immutable set search_path = pg_catalog as $$
  select case when p_slug = 'it' then 'informatika' else p_slug end
$$;
-- Monitoring qatori kaliti {studentId}__{period}__{slug} -> fan slug'i (admin.html monSlug natijasi).
create or replace function app.mon_slug_of(p_id text, p_sid text, p_period text) returns text
language sql immutable set search_path = pg_catalog as $$
  select case when left(p_id, length(p_sid) + length(p_period) + 4) = p_sid || '__' || p_period || '__'
              then substr(p_id, length(p_sid) + length(p_period) + 5) end
$$;

-- 4) O'quvchining oy monitoringi: o'rtacha (faqat tasdiqlangan), qamrov n / required, to'liqmi.
--    5–9-sinf: required = chegirma fanlari; boshqalar: shu sinf/oyda monitoring o'tkazilgan fanlar soni.
create or replace function app.monitoring_avg(p_sid text, p_period text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare s record; v_req text[]; v_ck text; v_avg numeric; v_n int; v_r int;
begin
  select st.grade, coalesce(nullif(st.lang, ''), 'uz') as lang, st."classLetter", st.track into s
    from public.students st where st."studentId" = p_sid or st.id = p_sid
   order by (st."studentId" = p_sid) desc limit 1;
  if not found then return jsonb_build_object('avg', null, 'n', 0, 'required', 0, 'full', false); end if;
  v_req := app.mon_disc_slugs(s.grade, s.lang);
  if v_req is null then
    v_ck := app.student_class_key(s.lang, s.grade, s."classLetter", s.track);
    select array_agg(distinct app.mon_canon(app.mon_slug_of(m.id, m."studentId", m.period))) into v_req
      from public.monitoring m where m."classKey" = v_ck and m.period = p_period
       and app.mon_slug_of(m.id, m."studentId", m.period) is not null;
  end if;
  v_r := coalesce(array_length(v_req, 1), 0);
  -- Har kanonik fan bir marta: ham «IT», ham «Informatika» bo'lsa — «Informatika» yozuvi (admin.html bilan bir xil tanlov).
  select avg(x.score), count(*) into v_avg, v_n
    from (select distinct on (y.c) y.score
            from (select app.mon_canon(app.mon_slug_of(m.id, m."studentId", m.period)) as c,
                         app.mon_slug_of(m.id, m."studentId", m.period) as sl, m.score, m.id
                    from public.monitoring m
                   where m."studentId" = p_sid and m.period = p_period and m.status = 'approved' and m.score is not null) y
           where y.c = any(coalesce(v_req, '{}'::text[]))
           order by y.c, (y.sl = y.c) desc, y.id) x;
  return jsonb_build_object('avg', round(v_avg, 2), 'n', coalesce(v_n, 0), 'required', v_r, 'full', v_r > 0 and coalesce(v_n, 0) >= v_r);
end $$;
revoke all on function app.monitoring_avg(text, text) from public, anon, authenticated;

-- 5) Raundlar (sinf × oy): kiritish muddati T0, yopish / qayta ochish (faqat direktor, RPC orqali).
create table if not exists public.monitoring_rounds (
  id               text primary key,          -- {period}__{classKey}
  period           text not null,
  "classKey"       text not null,
  "entryDeadline"  timestamptz,               -- T0 (bo'sh — config/monitoring bo'yicha)
  "closedAt"       timestamptz,
  "closedBy"       text,
  "reopenedAt"     timestamptz,
  "reopenedBy"     text,
  "reopenReason"   text,
  "updatedAt"      timestamptz default now()
);
alter table public.monitoring_rounds enable row level security;
revoke all on public.monitoring_rounds from anon, authenticated;
grant select on public.monitoring_rounds to authenticated;
grant all on public.monitoring_rounds to service_role;
drop policy if exists mr_sel on public.monitoring_rounds;
create policy mr_sel on public.monitoring_rounds for select using (app.is_staff());

create or replace function app.monitoring_round_state(p_period text, p_class text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare r public.monitoring_rounds%rowtype; v_day int; v_next date; v_t0 timestamptz; v_closed boolean;
begin
  select * into r from public.monitoring_rounds where id = p_period || '__' || p_class;
  if r."entryDeadline" is not null then v_t0 := r."entryDeadline";
  elsif coalesce(p_period, '') ~ '^\d{4}-(0[1-9]|1[0-2])$' then
    select greatest(1, least(28, coalesce(c."entryDeadlineDay", 5)::int)) into v_day from public.config c where c.id = 'monitoring';
    v_day := coalesce(v_day, 5);
    v_next := (p_period || '-01')::date + interval '1 month';
    v_t0 := ((v_next + (v_day - 1)) + time '23:59:59') at time zone 'Asia/Tashkent';
  end if;
  v_closed := r."closedAt" is not null and (r."reopenedAt" is null or r."reopenedAt" < r."closedAt");
  return jsonb_build_object('id', p_period || '__' || p_class, 'entryDeadline', v_t0, 'proposeDeadline', app.add_business_hours(v_t0, 24),
    'closed', coalesce(v_closed, false), 'closedAt', r."closedAt", 'reopenedAt', r."reopenedAt", 'reopenReason', r."reopenReason",
    'explicit', r."entryDeadline" is not null);
end $$;
revoke all on function app.monitoring_round_state(text, text) from public, anon, authenticated;

-- Yangi qoida shu davrga tegishlimi (davr = o'tish oyidan oldingi oy yoki keyin)?
create or replace function app.bonus_rule_period(p_period text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select nullif(btrim(coalesce(c."bonusApprovalFrom", '')), '') from public.config c where c.id = 'finance'), '') <> ''
     and coalesce(p_period, '') >= to_char(((select btrim(c."bonusApprovalFrom") from public.config c where c.id = 'finance') || '-01')::date - interval '1 month', 'YYYY-MM')
$$;
revoke all on function app.bonus_rule_period(text) from public, anon, authenticated;

-- 6) Monitoring: kim kiritdi / tasdiqladi (mijoz qiymati e'tiborsiz) + raund qulfi (yangi qoida davrlarida).
alter table public.monitoring add column if not exists "enteredAt"  timestamptz;
alter table public.monitoring add column if not exists "enteredBy"  text;
alter table public.monitoring add column if not exists "approvedAt" timestamptz;
alter table public.monitoring add column if not exists "approvedBy" text;
create or replace function app.monitoring_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_period text; v_ck text; v_st jsonb; v_auth boolean;
begin
  v_period := case when tg_op = 'DELETE' then old.period else new.period end;
  v_ck := case when tg_op = 'DELETE' then old."classKey" else new."classKey" end;
  -- Qulf: faqat yozishga haqli foydalanuvchiga (BEFORE trigger RLS'dan oldin — begonaga raund holati aytilmasin).
  v_auth := app.is_admin() or app.is_zavuch() or app.is_teacher_for_class(v_ck);
  if not app.is_system() and v_auth and app.bonus_rule_period(v_period) then
    v_st := app.monitoring_round_state(v_period, v_ck);
    if coalesce((v_st->>'closed')::boolean, false) then
      raise exception 'Bu sinf monitoring raundi yopilgan — o''zgartirish uchun direktor raundni qayta ochishi kerak' using errcode = '42501';
    end if;
    if not (app.is_admin() or app.is_zavuch()) and (v_st->>'entryDeadline') is not null and now() > (v_st->>'entryDeadline')::timestamptz then
      raise exception 'Monitoring kiritish muddati tugagan (%). O''zgartirish — O''IBDO'' orqali', to_char(((v_st->>'entryDeadline')::timestamptz) at time zone 'Asia/Tashkent', 'DD.MM.YYYY HH24:MI')
        using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  if tg_op = 'INSERT' then
    new."enteredBy" := app.uid(); new."enteredAt" := now();
    if new.status = 'approved' then new."approvedBy" := app.uid(); new."approvedAt" := now();
    else new."approvedBy" := null; new."approvedAt" := null; end if;
  else
    if new.score is distinct from old.score then new."enteredBy" := app.uid(); new."enteredAt" := now();
    else new."enteredBy" := old."enteredBy"; new."enteredAt" := old."enteredAt"; end if;
    if new.status = 'approved' and (coalesce(old.status, '') <> 'approved' or new.score is distinct from old.score) then
      new."approvedBy" := app.uid(); new."approvedAt" := now();
    elsif new.status = 'approved' then new."approvedBy" := old."approvedBy"; new."approvedAt" := old."approvedAt";
    else new."approvedBy" := null; new."approvedAt" := null; end if;
  end if;
  return new;
end $$;
revoke all on function app.monitoring_guard() from public, anon, authenticated;
drop trigger if exists trg_monitoring_guard on public.monitoring;
create trigger trg_monitoring_guard before insert or update or delete on public.monitoring
  for each row execute function app.monitoring_guard();

-- Raund boshqaruvi (faqat direktor): muddat, yopish, qayta ochish (sabab majburiy; qayta ochilganda o'qituvchiga yana
--   24 ish soati — yangi T0).
create or replace function public.monitoring_round_set(p_class text, p_period text, p_action text, p_value text default null)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_id text := p_period || '__' || p_class; v_dl timestamptz;
begin
  if v_uid is null or not app.has_role('director') then
    raise exception 'Ruxsat yo''q: raundni faqat direktor boshqaradi' using errcode = '42501';
  end if;
  if coalesce(p_period, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' or coalesce(btrim(p_class), '') = '' then
    raise exception 'Sinf va oy kerak' using errcode = '22023';
  end if;
  insert into public.monitoring_rounds(id, period, "classKey") values (v_id, p_period, p_class) on conflict (id) do nothing;
  if p_action = 'deadline' then
    begin v_dl := nullif(btrim(coalesce(p_value, '')), '')::timestamptz; exception when others then
      raise exception 'Muddat sanasi noto''g''ri' using errcode = '22023'; end;
    update public.monitoring_rounds set "entryDeadline" = v_dl, "updatedAt" = now() where id = v_id;
  elsif p_action = 'close' then
    update public.monitoring_rounds set "closedAt" = now(), "closedBy" = v_uid, "updatedAt" = now() where id = v_id;
  elsif p_action = 'reopen' then
    if coalesce(btrim(p_value), '') = '' then return jsonb_build_object('ok', false, 'reason', 'note_required'); end if;
    update public.monitoring_rounds set "reopenedAt" = now(), "reopenedBy" = v_uid, "reopenReason" = btrim(p_value),
           "entryDeadline" = app.add_business_hours(now(), 24), "updatedAt" = now() where id = v_id;
  else
    raise exception 'Amal: deadline | close | reopen' using errcode = '22023';
  end if;
  return jsonb_build_object('ok', true, 'state', app.monitoring_round_state(p_period, p_class));
end $$;
revoke all on function public.monitoring_round_set(text, text, text, text) from public, anon;
grant execute on function public.monitoring_round_set(text, text, text, text) to authenticated, service_role;

-- 7) Bonuslar
create table if not exists public.monitoring_bonus (
  id                text primary key,           -- {studentId}__{period}
  "studentId"       text not null,
  period            text not null,
  "classKey"        text,
  avg               numeric,
  n                 int,
  required          int,
  status            text not null default 'proposed',   -- proposed | approved | rejected
  "proposedBy"      text,
  "proposedAt"      timestamptz,
  "proposeDeadline" timestamptz,
  "decideDeadline"  timestamptz,
  late              boolean not null default false,
  "decidedBy"       text,
  "decidedAt"       timestamptz,
  "decisionNote"    text
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'monitoring_bonus_status_chk') then
    alter table public.monitoring_bonus add constraint monitoring_bonus_status_chk check (status in ('proposed', 'approved', 'rejected'));
  end if;
end $$;
create index if not exists monitoring_bonus_status_idx on public.monitoring_bonus(status);
create index if not exists monitoring_bonus_period_idx on public.monitoring_bonus(period);
alter table public.monitoring_bonus enable row level security;
revoke all on public.monitoring_bonus from anon, authenticated;
grant select on public.monitoring_bonus to authenticated;
grant all on public.monitoring_bonus to service_role;
drop policy if exists mb_sel on public.monitoring_bonus;
create policy mb_sel on public.monitoring_bonus for select
  using (app.is_admin() or app.is_zavuch() or app.is_finance_mgr() or app.owns_child("studentId"));

-- Taklif: faqat O'IBDO' (zavuch); o'rtacha ≥ 100 va to'liq qamrov; muddatdan keyin — late (rad etilmaydi).
create or replace function public.bonus_propose(p_sid text, p_period text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_a jsonb; v_ck text; v_st jsonb; v_id text := p_sid || '__' || p_period; b public.monitoring_bonus%rowtype;
        v_pdl timestamptz;
begin
  if v_uid is null or not app.has_role('zavuch') then
    raise exception 'Ruxsat yo''q: bonusni O''IBDO'' taklif qiladi (Direktor tasdiqlaydi)' using errcode = '42501';
  end if;
  if coalesce(p_period, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Oy YYYY-MM' using errcode = '22023'; end if;
  select app.student_class_key(st.lang, st.grade, st."classLetter", st.track) into v_ck from public.students st
   where st."studentId" = p_sid or st.id = p_sid order by (st."studentId" = p_sid) desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  v_a := app.monitoring_avg(p_sid, p_period);
  if not coalesce((v_a->>'full')::boolean, false) or coalesce((v_a->>'avg')::numeric, 0) < 100 then
    return jsonb_build_object('ok', false, 'reason', 'not_eligible', 'avg', v_a->'avg', 'n', v_a->'n', 'required', v_a->'required');
  end if;
  perform pg_advisory_xact_lock(hashtext('bonus:' || v_id));
  select * into b from public.monitoring_bonus where id = v_id;
  if found and b.status in ('proposed', 'approved') then return jsonb_build_object('ok', false, 'reason', 'already', 'status', b.status); end if;
  v_st := app.monitoring_round_state(p_period, v_ck);
  v_pdl := (v_st->>'proposeDeadline')::timestamptz;
  insert into public.monitoring_bonus(id, "studentId", period, "classKey", avg, n, required, status, "proposedBy", "proposedAt",
                                      "proposeDeadline", "decideDeadline", late, "decidedBy", "decidedAt", "decisionNote")
  values (v_id, p_sid, p_period, v_ck, (v_a->>'avg')::numeric, (v_a->>'n')::int, (v_a->>'required')::int, 'proposed', v_uid, now(),
          v_pdl, app.add_business_hours(now(), 24), v_pdl is not null and now() > v_pdl, null, null, null)
  on conflict (id) do update set avg = excluded.avg, n = excluded.n, required = excluded.required, status = 'proposed',
     "proposedBy" = excluded."proposedBy", "proposedAt" = excluded."proposedAt", "proposeDeadline" = excluded."proposeDeadline",
     "decideDeadline" = excluded."decideDeadline", late = excluded.late, "decidedBy" = null, "decidedAt" = null, "decisionNote" = null;
  return jsonb_build_object('ok', true, 'late', v_pdl is not null and now() > v_pdl);
end $$;
revoke all on function public.bonus_propose(text, text) from public, anon;
grant execute on function public.bonus_propose(text, text) to authenticated, service_role;

-- Qaror: faqat Direktor; taklif qilgan odam emas; muddat o'tgan yoki kech taklif — izoh MAJBURIY; tasdiqda o'rtacha qayta
--   tekshiriladi (taklifdan keyin ball o'zgargan bo'lsa — rad).
create or replace function public.bonus_decide(p_id text, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); b public.monitoring_bonus%rowtype; v_a jsonb;
begin
  if v_uid is null or not app.has_role('director') then
    raise exception 'Ruxsat yo''q: bonusni Direktor tasdiqlaydi' using errcode = '42501';
  end if;
  select * into b from public.monitoring_bonus where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if b.status <> 'proposed' then return jsonb_build_object('ok', false, 'reason', 'not_pending', 'status', b.status); end if;
  if b."proposedBy" = v_uid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  if (b.late or (b."decideDeadline" is not null and now() > b."decideDeadline") or not coalesce(p_approve, false))
     and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'note_required');
  end if;
  if coalesce(p_approve, false) then
    v_a := app.monitoring_avg(b."studentId", b.period);
    if not coalesce((v_a->>'full')::boolean, false) or coalesce((v_a->>'avg')::numeric, 0) < 100 then
      return jsonb_build_object('ok', false, 'reason', 'changed', 'avg', v_a->'avg', 'n', v_a->'n', 'required', v_a->'required');
    end if;
  end if;
  update public.monitoring_bonus set status = case when p_approve then 'approved' else 'rejected' end,
         "decidedBy" = v_uid, "decidedAt" = now(), "decisionNote" = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id;
  return jsonb_build_object('ok', true, 'status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.bonus_decide(text, boolean, text) from public, anon;
grant execute on function public.bonus_decide(text, boolean, text) to authenticated, service_role;

-- Muddati o'tgan nomzod (O'IBDO' taklif qilmagan, T0 + 24 ish soati o'tgan): Direktor SABAB bilan qaror qiladi.
create or replace function public.bonus_decide_expired(p_sid text, p_period text, p_approve boolean, p_note text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_a jsonb; v_ck text; v_st jsonb; v_id text := p_sid || '__' || p_period; v_pdl timestamptz;
begin
  if v_uid is null or not app.has_role('director') then
    raise exception 'Ruxsat yo''q: faqat Direktor' using errcode = '42501';
  end if;
  if coalesce(btrim(p_note), '') = '' then return jsonb_build_object('ok', false, 'reason', 'note_required'); end if;
  select app.student_class_key(st.lang, st.grade, st."classLetter", st.track) into v_ck from public.students st
   where st."studentId" = p_sid or st.id = p_sid order by (st."studentId" = p_sid) desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  v_st := app.monitoring_round_state(p_period, v_ck); v_pdl := (v_st->>'proposeDeadline')::timestamptz;
  if v_pdl is null or now() <= v_pdl then return jsonb_build_object('ok', false, 'reason', 'not_expired'); end if;
  if exists (select 1 from public.monitoring_bonus where id = v_id) then return jsonb_build_object('ok', false, 'reason', 'already'); end if;
  v_a := app.monitoring_avg(p_sid, p_period);
  if coalesce(p_approve, false) and (not coalesce((v_a->>'full')::boolean, false) or coalesce((v_a->>'avg')::numeric, 0) < 100) then
    return jsonb_build_object('ok', false, 'reason', 'not_eligible');
  end if;
  insert into public.monitoring_bonus(id, "studentId", period, "classKey", avg, n, required, status, "proposedBy", "proposedAt",
                                      "proposeDeadline", "decideDeadline", late, "decidedBy", "decidedAt", "decisionNote")
  values (v_id, p_sid, p_period, v_ck, (v_a->>'avg')::numeric, (v_a->>'n')::int, (v_a->>'required')::int,
          case when p_approve then 'approved' else 'rejected' end, null, null, v_pdl, null, true, v_uid, now(), btrim(p_note));
  return jsonb_build_object('ok', true, 'status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.bonus_decide_expired(text, text, boolean, text) from public, anon;
grant execute on function public.bonus_decide_expired(text, text, boolean, text) to authenticated, service_role;

-- 8) Ko'rinishlar uchun RPC: raund holati + o'quvchilar (o'rtacha, qamrov, bonus) — O'IBDO', Direktor, Moliya menejeri;
--    o'qituvchi (o'z sinfi) — faqat muddatlar. Nomzodlar (barcha sinflar) — taklif/qaror navbati uchun.
create or replace function public.monitoring_round_status(p_class text, p_period text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_st jsonb; v_list jsonb;
begin
  if not (app.is_admin() or app.is_zavuch() or app.is_finance_mgr() or app.is_teacher_for_class(p_class)) then
    raise exception 'Ruxsat yo''q' using errcode = '42501';
  end if;
  v_st := app.monitoring_round_state(p_period, p_class) || jsonb_build_object('ruleActive', app.bonus_rule_period(p_period));
  if not (app.is_admin() or app.is_zavuch() or app.is_finance_mgr()) then return jsonb_build_object('round', v_st); end if;
  select coalesce(jsonb_agg(jsonb_build_object('studentId', x.sid, 'mon', app.monitoring_avg(x.sid, p_period),
           'bonus', (select to_jsonb(b) - 'proposedBy' - 'decidedBy' from public.monitoring_bonus b where b.id = x.sid || '__' || p_period))
         order by x.sid), '[]'::jsonb) into v_list
    from (select coalesce(nullif(s."studentId", ''), s.id) as sid from public.students s
           where app.student_class_key(s.lang, s.grade, s."classLetter", s.track) = p_class
             and coalesce(s."payStatus", '') <> 'chiqdi') x;
  return jsonb_build_object('round', v_st, 'students', v_list);
end $$;
revoke all on function public.monitoring_round_status(text, text) from public, anon;
grant execute on function public.monitoring_round_status(text, text) to authenticated, service_role;

create or replace function public.bonus_candidates(p_period text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v jsonb;
begin
  if not (app.is_admin() or app.is_zavuch() or app.is_finance_mgr()) then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  with st as (
    select coalesce(nullif(s."studentId", ''), s.id) as sid, app.student_class_key(s.lang, s.grade, s."classLetter", s.track) as ck
      from public.students s
     where coalesce(s."payStatus", '') <> 'chiqdi'
       and exists (select 1 from public.monitoring m where m."studentId" = coalesce(nullif(s."studentId", ''), s.id)
                     and m.period = p_period and m.status = 'approved' and m.score >= 100)),
  a as (select st.sid, st.ck, app.monitoring_avg(st.sid, p_period) as mon from st)
  select coalesce(jsonb_agg(jsonb_build_object('studentId', a.sid, 'classKey', a.ck, 'mon', a.mon,
           'round', app.monitoring_round_state(p_period, a.ck),
           'bonus', (select to_jsonb(b) - 'proposedBy' - 'decidedBy' from public.monitoring_bonus b where b.id = a.sid || '__' || p_period))
         order by a.ck, a.sid), '[]'::jsonb) into v
    from a where coalesce((a.mon->>'full')::boolean, false) and coalesce((a.mon->>'avg')::numeric, 0) >= 100;
  return v;
end $$;
revoke all on function public.bonus_candidates(text) from public, anon;
grant execute on function public.bonus_candidates(text) to authenticated, service_role;

-- 9) Faktura: o'tish oyidan boshlab «Monitoring 100» granti faqat tasdiqlangan bonus bilan (invoices."bonusRef").
alter table public.invoices add column if not exists "bonusRef" text;
create or replace function app.invoice_bonus_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_from text; v_prev text; b public.monitoring_bonus%rowtype; v_is100 boolean;
begin
  if tg_op = 'UPDATE' and new."bonusRef" is not distinct from old."bonusRef" and new."pctApplied" is not distinct from old."pctApplied"
     and new."isGrant" is not distinct from old."isGrant" and new."discountInfo" is not distinct from old."discountInfo"
     and new.month is not distinct from old.month and new."studentId" is not distinct from old."studentId" then
    return new;
  end if;
  select nullif(btrim(coalesce(c."bonusApprovalFrom", '')), '') into v_from from public.config c where c.id = 'finance';
  if v_from is null or coalesce(new.month, '') < v_from then return new; end if;   -- eski qoida
  v_prev := to_char((new.month || '-01')::date - interval '1 month', 'YYYY-MM');
  v_is100 := coalesce(new."isGrant", false) and coalesce(new."pctApplied", 0) >= 1 and coalesce(new."discountInfo", '') ilike 'Monitoring 100%';
  if coalesce(new."bonusRef", '') = '' then
    if v_is100 then
      raise exception '«Monitoring 100» granti faqat Direktor tasdiqlagan bonus bilan (%)', v_prev using errcode = '23514';
    end if;
    new."bonusRef" := null;
    return new;
  end if;
  select * into b from public.monitoring_bonus where id = new."bonusRef";
  if not found or b.status <> 'approved' or b."studentId" is distinct from new."studentId" or b.period <> v_prev then
    raise exception 'Bonus tasdiqlanmagan yoki boshqa o''quvchi / oyniki' using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function app.invoice_bonus_guard() from public, anon, authenticated;
drop trigger if exists trg_invoice_bonus_guard on public.invoices;
create trigger trg_invoice_bonus_guard before insert or update on public.invoices
  for each row execute function app.invoice_bonus_guard();

-- 10) O'zgarishlar tarixi
select app.chlog_attach('monitoring_bonus',  'studentId,period,status,late,decisionNote');
select app.chlog_attach('monitoring_rounds', 'entryDeadline,closedAt,reopenedAt,reopenReason');
select app.chlog_attach('invoices',          'studentId,month,amount,paidAmount,status,baseAmount,discount,pctApplied,isGrant,sickAmount,sickDaysApplied,sickNoteRefs,bonusRef,billedFrom,billedTo');
select app.chlog_attach('config',            '!refundPin,sickRate,sickApprovalFrom,bonusApprovalFrom,entryDeadlineDay,lessonRate,latePenalty,earlyPenalty,allowedBreakMin,breakPenaltyPerHour,clickServiceId,clickMerchantId,uzumUrlTemplate,flatAmount,perYear,monthsPerYear,tenureYears,yearsCap,degree,category,languages,russian,langLevel');

notify pgrst, 'reload schema';
