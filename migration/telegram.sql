\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: telegram.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- telegram.sql — TELEGRAM (D4): ota-ona raqami O'QUVCHI KARTASIDAGI raqam bilan bir xilligi tasdiqlangandan keyin xabarlar
--   Telegram orqali; yetkazilmasa — SMS (faqat +998). Direktorga kunlik hisobot (bir martalik havola bilan ulanadi).
--   * telegram_links        — tasdiqlangan bog'lanish: kabinet hisobi (uid) <-> Telegram foydalanuvchisi; farzandlar (studentIds),
--                             holat (active | unlinked | blocked | reverify), xabar turlari (prefs), til.
--   * telegram_link_tokens  — kabinetdan bir martalik havola (deep link): faqat HMAC xeshi saqlanadi, 10 daqiqa, bir marta.
--   * telegram_updates      — Telegram update_id takror ishlanmasin (webhook qayta yuborsa).
--   * notify_queue          — «To'lov qabul qilindi» va sinf e'loni navbati (trigger yozadi, sms-worker yuboradi).
--   Mijoz (anon/authenticated) bu jadvallarga TO'G'RIDAN-TO'G'RI kira olmaydi: faqat server (service_role) va RPC'lar.
--   Ota-ona o'z holatini my_telegram_status() bilan ko'radi; Direktor — tg_stats().
--   Kimga yuborish — BITTA qoida: app.tg_recipients(<o'quvchi kaliti>) — faol, 365 kun ichida tasdiqlangan, kabinet hisobi faol,
--   farzand bog'lanishi faol va bog'lanishdagi raqam HOZIRGI kartadagi raqam (parentPhone yoki parentPhone2) bilan bir xil.
--   Karta raqami o'zgarsa — o'sha farzand bo'yicha xabar to'xtaydi (kabinetda «qayta tasdiqlash kerak»).
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Jadvallar
create table if not exists public.telegram_links (
  id               text primary key default gen_random_uuid()::text,
  uid              text not null,                       -- users.id (ota-ona kabineti yoki Direktor)
  kind             text not null default 'parent',      -- parent | staff (Direktor: kunlik hisobot)
  "tgUserId"       bigint not null,
  "chatId"         bigint not null,
  phone            text,                                -- kanonik raqam (Telegram kontaktidan)
  "studentIds"     jsonb not null default '[]'::jsonb,  -- tasdiqlangan farzandlar (students.id)
  status           text not null default 'active',
  prefs            jsonb not null default '{}'::jsonb,  -- {"invoice":false,...} — o'chirilgan turlar (standart: hammasi yoqilgan)
  lang             text,
  "verifiedAt"     timestamptz,
  "lastReverifyAt" timestamptz,
  "blockedAt"      timestamptz,
  "createdAt"      timestamptz not null default now(),
  "updatedAt"      timestamptz
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'telegram_links_kind_chk') then
    alter table public.telegram_links add constraint telegram_links_kind_chk check (kind in ('parent', 'staff'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'telegram_links_status_chk') then
    alter table public.telegram_links add constraint telegram_links_status_chk check (status in ('active', 'unlinked', 'blocked', 'reverify'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'telegram_links_json_chk') then
    alter table public.telegram_links add constraint telegram_links_json_chk check (jsonb_typeof("studentIds") = 'array' and jsonb_typeof(prefs) = 'object');
  end if;
end $$;
create unique index if not exists telegram_links_uid_tg_kind on public.telegram_links(uid, "tgUserId", kind);
create index if not exists telegram_links_chat_idx on public.telegram_links("chatId");

create table if not exists public.telegram_link_tokens (
  "tokenHash"  text primary key,                        -- HMAC-SHA256(token) — tokenning o'zi saqlanmaydi
  uid          text not null,
  kind         text not null default 'parent',
  "expiresAt"  timestamptz not null,
  "usedAt"     timestamptz,
  "tgUserId"   bigint,                                  -- /start bilan bog'langan Telegram foydalanuvchisi
  "chatId"     bigint,
  "consentAt"  timestamptz,                             -- «Roziman»
  "createdAt"  timestamptz not null default now()
);
create index if not exists telegram_link_tokens_tg_idx on public.telegram_link_tokens("tgUserId");
create index if not exists telegram_link_tokens_uid_idx on public.telegram_link_tokens(uid, "createdAt");

create table if not exists public.telegram_updates (
  update_id  bigint primary key,
  at         timestamptz not null default now()
);

create table if not exists public.notify_queue (
  id            text primary key,                       -- 'pay__<to'lov id>' | 'ann__<e'lon id>' — takror navbatga tushmaydi
  type          text not null,                          -- payment | announce
  ref           text,
  payload       jsonb not null default '{}'::jsonb,
  status        text not null default 'pending',        -- pending | done | skipped | failed
  attempts      int not null default 0,
  error         text,
  "createdAt"   timestamptz not null default now(),
  "processedAt" timestamptz
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'notify_queue_type_chk') then
    alter table public.notify_queue add constraint notify_queue_type_chk check (type in ('payment', 'announce'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'notify_queue_status_chk') then
    alter table public.notify_queue add constraint notify_queue_status_chk check (status in ('pending', 'done', 'skipped', 'failed'));
  end if;
end $$;
create index if not exists notify_queue_pending_idx on public.notify_queue(status, "createdAt");

do $$ declare t text; begin
  foreach t in array array['telegram_links', 'telegram_link_tokens', 'telegram_updates', 'notify_queue'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;

-- SMS jurnali: kanal (sms | telegram) — «Xabarnomalar» jurnalida ko'rinadi. Bitta xabar id (masalan '<faktura>__new') —
--   qaysi kanal bilan ketgan bo'lsa ham BITTA qator (takror yuborilmaydi).
alter table public.sms_log add column if not exists channel text default 'sms';

-- Xabarnoma turlari: + to'lov qabul qilindi, sinf e'loni (Telegram), Direktorga kunlik hisobot. Standart — O'CHIQ.
alter table public.notify_settings drop constraint if exists notify_settings_id_chk;
alter table public.notify_settings add constraint notify_settings_id_chk
  check (id in ('general', 'new_invoice', 'debt_reminder', 'manual_remind', 'payment_received', 'announce', 'daily_report'));
insert into public.notify_settings(id, enabled, days, "hourFrom", "hourTo") values
  ('payment_received', false, null, null, null),
  ('announce',         false, null, null, null),
  ('daily_report',     false, '[1,2,3,4,5,6]', 19, null)
on conflict (id) do nothing;

-- 2) Raqam (kanonik raqamlar): '+998 90 111 22 33' -> 998901112233; '90 111 22 33' -> 998901112233; '+7 903 ...' -> 7903...;
--    '0048 ...' -> 48...  (server/phone.cjs bilan bir xil asosiy qoida — taqqoslash uchun).
create or replace function app.tg_phone(p text) returns text
language sql immutable set search_path = pg_catalog as $$
  select case
    when d = '' then ''
    when left(d, 2) = '00' then ltrim(substr(d, 3), '0')
    when s ~ '^[^0-9]*\+' then ltrim(d, '0')
    when length(d) = 9 then '998' || d
    else d end
  from (select btrim(coalesce(p, '')) as s, regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x
$$;
-- O'quvchi kartasidagi raqamlar (hujjat id yozuvi; bo'lmasa — studentId kalitli eski yozuv, boshqa bolaning hujjati bo'lmasa).
create or replace function app.tg_card_phones(p_doc text) returns text[]
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select array_remove(array[app.tg_phone(sp."parentPhone"), app.tg_phone(sp."parentPhone2")], '')
                     from public.student_private sp
                    where sp.id = coalesce(
                      (select p.id from public.student_private p where p.id = p_doc),
                      (select p.id from public.student_private p, public.students s
                        where s.id = p_doc and nullif(s."studentId", '') is not null and p.id = s."studentId"
                          and not exists (select 1 from public.students s2 where s2.id = s."studentId")))), '{}'::text[])
$$;
-- Bog'lanish shu farzand bo'yicha HOZIR yuborishga yaroqlimi (bitta qoida: tg_recipients, holat, statistika).
create or replace function app.tg_link_ok(l public.telegram_links, p_doc text) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select l.kind = 'parent' and l.status = 'active' and l."verifiedAt" > now() - interval '365 days'
     and coalesce(l.phone, '') <> '' and l."studentIds" ? p_doc
     and l.phone = any(app.tg_card_phones(p_doc))
     and exists (select 1 from public.users u where u.id = l.uid and coalesce(nullif(u.status, ''), 'active') = 'active')
     and exists (select 1 from public.child_claims cc where cc.uid = l.uid and coalesce(nullif(cc.status, ''), 'active') = 'active'
                   and app.claim_row(cc."studentId", cc.code) = p_doc)
$$;
-- Kimga yuborish: o'quvchi kaliti (studentId yoki hujjat id; BITTA o'quvchiga mos bo'lishi shart) -> chat'lar.
create or replace function app.tg_recipients(p_student_key text) returns table(link_id text, chat_id bigint, prefs jsonb, lang text)
language sql stable security definer set search_path = public, app, pg_temp as $$
  with s as (select st.id from public.students st where st.id = p_student_key or st."studentId" = p_student_key),
       one as (select min(id) as id from s having count(*) = 1)
  select l.id, l."chatId", l.prefs, l.lang
    from one, public.telegram_links l
   where l."studentIds" ? one.id and app.tg_link_ok(l, one.id)
$$;
do $$ declare f text; begin
  foreach f in array array['app.tg_card_phones(text)', 'app.tg_link_ok(public.telegram_links, text)', 'app.tg_recipients(text)'] loop
    execute 'revoke all on function ' || f || ' from public, anon, authenticated';
  end loop;
end $$;

-- 3) Server RPC'lari (faqat service_role / baza; mijozga yopiq)
create or replace function app.tg_need_system() returns void
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not app.is_system() then raise exception 'Ruxsat yo''q: faqat server' using errcode = '42501'; end if;
end $$;
-- Hamma yaroqli qabul qiluvchilar (sms-worker bir marta o'qiydi): o'quvchi hujjat id va kaliti bilan.
create or replace function public.tg_recipients_bulk() returns table(student_doc text, student_key text, link_id text, chat_id bigint, prefs jsonb, lang text)
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  perform app.tg_need_system();
  return query
    select s.id, coalesce(nullif(s."studentId", ''), s.id), l.id, l."chatId", l.prefs, l.lang
      from public.telegram_links l
      cross join lateral jsonb_array_elements_text(l."studentIds") sd(doc)
      join public.students s on s.id = sd.doc
     where l.kind = 'parent' and l.status = 'active' and app.tg_link_ok(l, s.id);
end $$;
-- Bir martalik havola: kabinet hisobi (parent — kamida bitta faol farzand; staff — faqat faol Direktor). Soatiga 6 ta.
create or replace function public.tg_token_new(p_uid text, p_kind text, p_hash text, p_ttl_sec int default 600) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_role text; v_status text; v_n int;
begin
  perform app.tg_need_system();
  if coalesce(p_kind, '') not in ('parent', 'staff') or coalesce(p_hash, '') = '' or coalesce(p_uid, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  select u.role, coalesce(nullif(u.status, ''), 'active') into v_role, v_status from public.users u where u.id = p_uid;
  if v_role is null or v_status <> 'active' then return jsonb_build_object('ok', false, 'error', 'inactive'); end if;
  if p_kind = 'staff' and v_role <> 'director' then return jsonb_build_object('ok', false, 'error', 'not_director'); end if;
  if p_kind = 'parent' and not exists (select 1 from public.child_claims cc where cc.uid = p_uid
                                         and coalesce(nullif(cc.status, ''), 'active') = 'active'
                                         and app.claim_row(cc."studentId", cc.code) is not null) then
    return jsonb_build_object('ok', false, 'error', 'no_children');
  end if;
  select count(*) into v_n from public.telegram_link_tokens t where t.uid = p_uid and t."createdAt" > now() - interval '1 hour';
  if v_n >= 6 then return jsonb_build_object('ok', false, 'error', 'rate'); end if;
  delete from public.telegram_link_tokens t where t."expiresAt" < now() - interval '1 day';
  insert into public.telegram_link_tokens("tokenHash", uid, kind, "expiresAt") values (p_hash, p_uid, p_kind, now() + make_interval(secs => greatest(60, least(coalesce(p_ttl_sec, 600), 1800))));
  return jsonb_build_object('ok', true);
end $$;
-- /start <token>: token shu Telegram foydalanuvchisiga biriktiriladi (boshqasi ishlata olmaydi).
create or replace function public.tg_start(p_hash text, p_tg bigint, p_chat bigint) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare t public.telegram_link_tokens;
begin
  perform app.tg_need_system();
  select * into t from public.telegram_link_tokens where "tokenHash" = p_hash for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  if t."usedAt" is not null then return jsonb_build_object('ok', false, 'error', 'used'); end if;
  if t."expiresAt" < now() then return jsonb_build_object('ok', false, 'error', 'expired'); end if;
  if t."tgUserId" is not null and t."tgUserId" <> p_tg then return jsonb_build_object('ok', false, 'error', 'claimed'); end if;
  update public.telegram_link_tokens set "tgUserId" = p_tg, "chatId" = p_chat where "tokenHash" = p_hash;
  return jsonb_build_object('ok', true, 'kind', t.kind);
end $$;
-- «Roziman»: shu Telegram foydalanuvchisining oxirgi faol tokeni.
create or replace function public.tg_consent(p_tg bigint) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_hash text;
begin
  perform app.tg_need_system();
  select "tokenHash" into v_hash from public.telegram_link_tokens
   where "tgUserId" = p_tg and "usedAt" is null and "expiresAt" > now() order by "createdAt" desc limit 1;
  if v_hash is null then return jsonb_build_object('ok', false, 'error', 'notoken'); end if;
  update public.telegram_link_tokens set "consentAt" = now() where "tokenHash" = v_hash;
  return jsonb_build_object('ok', true);
end $$;
-- Kontakt (o'z raqami — tekshiruv serverda: contact.user_id = from.id, shaxsiy chat): raqam kartadagi raqam bilan mosmi.
--   parent: kabinetdagi faol farzandlardan kartasidagi parentPhone/parentPhone2 shu raqam bo'lganlari bog'lanadi.
--   staff : faol Direktor; hisobida telefon bo'lsa — shu raqam bo'lishi shart.
--   Natija qanday bo'lsa ham token ishlatilgan bo'ladi (yangi havola — kabinetdan).
create or replace function public.tg_contact(p_tg bigint, p_chat bigint, p_phone text, p_lang text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare t public.telegram_link_tokens; v_phone text := app.tg_phone(p_phone); v_ids jsonb; v_names jsonb; v_uphone text; v_role text; v_st text; v_id text;
begin
  perform app.tg_need_system();
  select * into t from public.telegram_link_tokens
   where "tgUserId" = p_tg and "usedAt" is null and "expiresAt" > now() and "consentAt" is not null
   order by "createdAt" desc limit 1 for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'notoken'); end if;
  update public.telegram_link_tokens set "usedAt" = now() where "tokenHash" = t."tokenHash";
  if v_phone = '' then return jsonb_build_object('ok', false, 'reason', 'mismatch'); end if;
  select u.role, coalesce(nullif(u.status, ''), 'active'), app.tg_phone(u.phone) into v_role, v_st, v_uphone from public.users u where u.id = t.uid;
  if v_role is null or v_st <> 'active' then return jsonb_build_object('ok', false, 'reason', 'inactive'); end if;
  if t.kind = 'staff' then
    if v_role <> 'director' then return jsonb_build_object('ok', false, 'reason', 'inactive'); end if;
    if coalesce(v_uphone, '') <> '' and v_uphone <> v_phone then return jsonb_build_object('ok', false, 'reason', 'mismatch'); end if;
    v_ids := '[]'::jsonb; v_names := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(x.id order by x.id), '[]'::jsonb), coalesce(jsonb_agg(x.nm order by x.id), '[]'::jsonb) into v_ids, v_names
      from (select distinct s.id, split_part(btrim(coalesce(s.name, '')), ' ', 1) as nm
              from public.child_claims cc join public.students s on s.id = app.claim_row(cc."studentId", cc.code)
             where cc.uid = t.uid and coalesce(nullif(cc.status, ''), 'active') = 'active'
               and v_phone = any(app.tg_card_phones(s.id))) x;
    if jsonb_array_length(v_ids) = 0 then return jsonb_build_object('ok', false, 'reason', 'mismatch'); end if;
  end if;
  insert into public.telegram_links(uid, kind, "tgUserId", "chatId", phone, "studentIds", status, lang, "verifiedAt", "lastReverifyAt", "createdAt")
  values (t.uid, t.kind, p_tg, p_chat, v_phone, v_ids, 'active', nullif(p_lang, ''), now(), now(), now())
  on conflict (uid, "tgUserId", kind) do update set "chatId" = excluded."chatId", phone = excluded.phone, "studentIds" = excluded."studentIds",
    status = 'active', lang = coalesce(excluded.lang, telegram_links.lang), "verifiedAt" = now(), "lastReverifyAt" = now(), "blockedAt" = null, "updatedAt" = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'kind', t.kind, 'linkId', v_id, 'names', v_names);
end $$;
-- /stop — shu Telegram foydalanuvchisining barcha bog'lanishlari uziladi.
create or replace function public.tg_stop(p_tg bigint) returns int
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare n int;
begin
  perform app.tg_need_system();
  update public.telegram_links set status = 'unlinked', "updatedAt" = now() where "tgUserId" = p_tg and status <> 'unlinked';
  get diagnostics n = row_count; return n;
end $$;
-- Bot bloklandi (403 yoki my_chat_member kicked) — shu chat'dagi faol bog'lanishlar 'blocked' (keyin SMS).
create or replace function public.tg_blocked(p_chat bigint) returns int
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare n int;
begin
  perform app.tg_need_system();
  update public.telegram_links set status = 'blocked', "blockedAt" = now(), "updatedAt" = now() where "chatId" = p_chat and status in ('active', 'reverify');
  get diagnostics n = row_count; return n;
end $$;
-- /sozlamalar: xabar turini yoqish/o'chirish (barcha faol bog'lanishlarida). p_key null — faqat holatni qaytaradi.
--   -> {"prefs": {...}, "kinds": ["parent","staff"]} yoki null (faol bog'lanish yo'q).
create or replace function public.tg_prefs(p_tg bigint, p_key text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v jsonb; k jsonb;
begin
  perform app.tg_need_system();
  if p_key is not null and p_key not in ('invoice', 'debt', 'payment', 'announce', 'daily') then raise exception 'Noma''lum tur' using errcode = '22023'; end if;
  select prefs into v from public.telegram_links where "tgUserId" = p_tg and status = 'active' order by "updatedAt" desc nulls last, "createdAt" desc limit 1;
  if v is null then return null; end if;
  if p_key is not null then
    v := v || jsonb_build_object(p_key, not coalesce((v ->> p_key)::boolean, true));
    update public.telegram_links set prefs = v, "updatedAt" = now() where "tgUserId" = p_tg and status = 'active';
  end if;
  select coalesce(jsonb_agg(distinct kind), '[]'::jsonb) into k from public.telegram_links where "tgUserId" = p_tg and status = 'active';
  return jsonb_build_object('prefs', v, 'kinds', k);
end $$;
-- update_id takror kelsa — false (webhook bir xil update'ni qayta yuborganda ikki marta ishlamaydi). 3 kundan eskilari o'chadi.
create or replace function public.tg_seen_update(p_update_id bigint) returns boolean
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare n int;
begin
  perform app.tg_need_system();
  insert into public.telegram_updates(update_id) values (p_update_id) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 1 and random() < 0.02 then delete from public.telegram_updates where at < now() - interval '3 days'; end if;
  return n = 1;
end $$;
-- Server: uid bo'yicha holat (kabinet kartasi) va uzish.
create or replace function app.tg_status_of(p_uid text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select jsonb_build_object('links', coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'kind', l.kind, 'verifiedAt', l."verifiedAt",
      'status', case when l.status <> 'active' then l.status
                     when l."verifiedAt" is null or l."verifiedAt" <= now() - interval '365 days' then 'reverify'
                     when l.kind = 'parent' and not exists (select 1 from jsonb_array_elements_text(l."studentIds") d where app.tg_link_ok(l, d)) then 'reverify'
                     else 'active' end,
      'students', (select coalesce(jsonb_agg(split_part(btrim(coalesce(s.name, '')), ' ', 1) order by s.id), '[]'::jsonb)
                     from public.students s where l."studentIds" ? s.id),
      'mismatch', (select coalesce(jsonb_agg(split_part(btrim(coalesce(s.name, '')), ' ', 1) order by s.id), '[]'::jsonb)
                     from public.students s where l.kind = 'parent' and l."studentIds" ? s.id and not app.tg_link_ok(l, s.id)))
      order by l."createdAt" desc), '[]'::jsonb))
  from public.telegram_links l where l.uid = p_uid and l.status <> 'unlinked'
$$;
revoke all on function app.tg_status_of(text) from public, anon, authenticated;
create or replace function public.tg_status(p_uid text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin perform app.tg_need_system(); return app.tg_status_of(p_uid); end $$;
create or replace function public.tg_unlink(p_uid text, p_link text default null) returns int
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare n int;
begin
  perform app.tg_need_system();
  update public.telegram_links set status = 'unlinked', "updatedAt" = now()
   where uid = p_uid and status <> 'unlinked' and (p_link is null or id = p_link);
  get diagnostics n = row_count; return n;
end $$;
-- Mijoz: o'z holati (ota-ona kabineti / Direktor «Sozlamalar») — faqat o'ziniki.
create or replace function public.my_telegram_status() returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.uid() is null then null else app.tg_status_of(app.uid()) end
$$;

-- 4) Navbat: to'lov qabul qilindi (to'lov yozuvi qo'llanganda) va yangi sinf e'loni. Navbatga yozib bo'lmasa ham to'lov
--    / e'lon SAQLANADI (xato yutiladi — pul oqimi xabarnoma tufayli to'xtamaydi).
create or replace function app.tg_queue_payment() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if coalesce(new.status, '') in ('applied', 'paid', 'confirmed', 'split') and coalesce(new."studentId", '') <> '' and coalesce(new.amount, 0) > 0
     and (tg_op = 'INSERT' or coalesce(old.status, '') not in ('applied', 'paid', 'confirmed', 'split') or coalesce(old."studentId", '') = '') then
    begin
      insert into public.notify_queue(id, type, ref, payload)
      values ('pay__' || new.id, 'payment', new.id, jsonb_build_object('studentId', new."studentId", 'amount', new.amount, 'provider', new.provider, 'at', now()))
      on conflict (id) do nothing;
    exception when others then null;
    end;
  end if;
  return null;
end $$;
revoke all on function app.tg_queue_payment() from public, anon, authenticated;
drop trigger if exists trg_tg_queue_payment on public.payments;
create trigger trg_tg_queue_payment after insert or update of status, "studentId" on public.payments
  for each row execute function app.tg_queue_payment();
create or replace function app.tg_queue_announce() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  begin
    insert into public.notify_queue(id, type, ref, payload)
    values ('ann__' || new.id, 'announce', new.id, jsonb_build_object('classKeys', new."classKeys", 'title', new.title, 'body', new.body))
    on conflict (id) do nothing;
  exception when others then null;
  end;
  return null;
end $$;
revoke all on function app.tg_queue_announce() from public, anon, authenticated;
drop trigger if exists trg_tg_queue_announce on public.class_announcements;
create trigger trg_tg_queue_announce after insert on public.class_announcements
  for each row execute function app.tg_queue_announce();
-- Sinf e'loni uchun qabul qiluvchilar (navbat ishlovchisi): e'lon sinflaridagi o'quvchilarning yaroqli bog'lanishlari.
create or replace function public.tg_announce_recipients(p_keys jsonb) returns table(chat_id bigint, link_id text, prefs jsonb, lang text)
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  perform app.tg_need_system();
  if jsonb_typeof(p_keys) is distinct from 'array' then return; end if;
  return query
    select distinct on (l."chatId") l."chatId", l.id, l.prefs, l.lang
      from public.telegram_links l
      cross join lateral jsonb_array_elements_text(l."studentIds") sd(doc)
      join public.students s on s.id = sd.doc
     where l.kind = 'parent' and l.status = 'active'
       and coalesce(s."payStatus", '') not in ('chiqdi')
       and (p_keys ? 'all' or p_keys ? app.student_class_key(s.lang, s.grade, s."classLetter", s.track))
       and app.tg_link_ok(l, s.id)
     order by l."chatId", l.id;
end $$;

-- 5) Direktor: ulanish statistikasi (sinf bo'yicha) va kunlik hisobot
create or replace function public.tg_stats() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare r jsonb;
begin
  if not (app.is_admin() or app.is_system()) then raise exception 'Ruxsat yo''q: faqat Direktor' using errcode = '42501'; end if;
  with st as (select s.id, app.student_class_key(s.lang, s.grade, s."classLetter", s.track) as ck
                from public.students s where coalesce(s."payStatus", '') not in ('chiqdi', 'muzlatilgan')),
  x as (select st.ck, exists (select 1 from public.telegram_links l where l."studentIds" ? st.id and app.tg_link_ok(l, st.id)) as con from st)
  select jsonb_build_object(
    'students', count(*), 'connected', count(*) filter (where con),
    'rate', case when count(*) > 0 then round(100.0 * count(*) filter (where con) / count(*), 1) end,
    'byClass', coalesce((select jsonb_agg(jsonb_build_object('classKey', ck, 'students', n, 'connected', c,
                         'rate', case when n > 0 then round(100.0 * c / n, 1) end) order by ck)
                         from (select ck, count(*) as n, count(*) filter (where con) as c from x group by ck) y), '[]'::jsonb),
    'links', (select count(*) from public.telegram_links where kind = 'parent' and status = 'active'),
    'blocked', (select count(*) from public.telegram_links where kind = 'parent' and status = 'blocked'),
    'reverify', (select count(*) from public.telegram_links l where l.kind = 'parent' and l.status = 'active'
                   and not exists (select 1 from jsonb_array_elements_text(l."studentIds") d where app.tg_link_ok(l, d))),
    'directors', (select count(*) from public.telegram_links l join public.users u on u.id = l.uid
                   where l.kind = 'staff' and l.status = 'active' and u.role = 'director' and coalesce(nullif(u.status, ''), 'active') = 'active'))
  into r from x;
  return r;
end $$;
-- Kunlik hisobot ma'lumoti (Toshkent kuni): to'lovlar (soni, summa, usul bo'yicha), qarzdorlar, davomat kiritilishi,
--   kutilayotgan tasdiqlar (navbatlar bo'yicha; muddati o'tganlari alohida). Server (tg-daily.cjs) yoki Direktor.
create or replace function public.director_daily(p_day date default null) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare d date := coalesce(p_day, (now() at time zone 'Asia/Tashkent')::date); v_from timestamptz; v_to timestamptz; r jsonb;
begin
  if not (app.is_admin() or app.is_system()) then raise exception 'Ruxsat yo''q: faqat Direktor' using errcode = '42501'; end if;
  v_from := (d::timestamp) at time zone 'Asia/Tashkent'; v_to := ((d + 1)::timestamp) at time zone 'Asia/Tashkent';
  select jsonb_build_object(
    'day', to_char(d, 'YYYY-MM-DD'),
    'payments', (select jsonb_build_object('count', count(*), 'sum', coalesce(sum(p.amount), 0),
                   'byProvider', coalesce((select jsonb_object_agg(pv, s) from (select coalesce(nullif(p2.provider, ''), 'boshqa') as pv, sum(p2.amount) as s
                       from public.payments p2 where p2."createdAt" >= v_from and p2."createdAt" < v_to
                        and coalesce(p2.status, '') in ('applied', 'paid', 'confirmed', 'split', 'unmatched') group by 1) z), '{}'::jsonb))
                   from public.payments p where p."createdAt" >= v_from and p."createdAt" < v_to
                    and coalesce(p.status, '') in ('applied', 'paid', 'confirmed', 'split', 'unmatched')),
    'unmatched', (select count(*) from public.payments p where p."createdAt" >= v_from and p."createdAt" < v_to and coalesce(p.status, '') = 'unmatched'),
    'debt', app.kpi_debt_aging(least(v_to, now())),
    'attendance', app.kpi_attendance(d, d) - 'byClass',
    'pending', jsonb_build_object(
      'bonus', (select count(*) from public.monitoring_bonus b where b.status = 'proposed'),
      'discount', (select count(*) from public.discount_requests q where q.status = 'pending'),
      'sick', (select count(*) from public.sick_notes n where n.status = 'pending'),
      'referral', (select count(*) from public.referral_requests q where q.status = 'pending_payment' and q."firstPaymentId" is not null),
      'payroll', (select count(*) from public.payroll_runs pr where pr.status = 'submitted')),
    'overdue', app.kpi_overdue_approvals())
  into r;
  return r;
end $$;
do $$ declare f text; begin
  foreach f in array array['app.tg_need_system()', 'public.tg_recipients_bulk()', 'public.tg_token_new(text, text, text, int)', 'public.tg_start(text, bigint, bigint)',
                           'public.tg_consent(bigint)', 'public.tg_contact(bigint, bigint, text, text)', 'public.tg_stop(bigint)', 'public.tg_blocked(bigint)',
                           'public.tg_prefs(bigint, text)', 'public.tg_seen_update(bigint)', 'public.tg_status(text)', 'public.tg_unlink(text, text)',
                           'public.tg_announce_recipients(jsonb)'] loop
    execute 'revoke all on function ' || f || ' from public, anon, authenticated';
    execute 'grant execute on function ' || f || ' to service_role';
  end loop;
  foreach f in array array['public.my_telegram_status()', 'public.tg_stats()', 'public.director_daily(date)'] loop
    execute 'revoke all on function ' || f || ' from public, anon';
    execute 'grant execute on function ' || f || ' to authenticated, service_role';
  end loop;
end $$;

-- 6) O'zgarishlar tarixi (raqam qiymati yozilmaydi)
select app.chlog_attach('telegram_links', 'uid,kind,status,studentIds,verifiedAt,!phone');

notify pgrst, 'reload schema';
