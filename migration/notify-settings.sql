\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: notify-settings.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- notify-settings.sql — XABARNOMALAR (D3): avtomatik SMS vaqti va matnini sayt administratori ichki sozlamada boshqaradi;
--   sinfga e'lonlar (ota-ona kabinetida).
--   * notify_settings: 'general' (umumiy tinch soat, muharrirlar), 'new_invoice' (yangi faktura), 'debt_reminder' (qarz eslatmasi),
--     'manual_remind' (qo'lda «Eslatma»). Har biri: yoqilgan, faol matn (Eskiz tasdiqlagan), qoralama matn, Telegram matni
--     (PKG-10), hafta kunlari, soat oralig'i, oyning qaysi kunidan (qarz), necha kun orqaga (yangi faktura), yoqilgan vaqti.
--     O'qish/yozish — Direktor va u tayinlagan muharrirlar; sms-worker (service_role) o'qiydi. Avtomatik turlar standart
--     O'CHIQ — birinchi yoqishgacha hech narsa ketmaydi; bo'sh matn — server sozlamasidagi (config.json) matn.
--   * class_announcements: sinf(lar)ga yoki butun maktabga e'lon; yozish — Direktor, O'IBDO', sinf rahbari (faqat o'z sinfi);
--     o'qish — xodim (o'z sinfi), ota-ona (farzandining sinfi), muddati o'tganlar ota-onaga ko'rinmaydi.
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Xabarnoma sozlamalari
create table if not exists public.notify_settings (
  id              text primary key,
  enabled         boolean not null default false,
  "smsActive"     text,                  -- faol matn (Eskiz'da tasdiqlangan shablonga mos); bo'sh — server sozlamasi / standart
  "smsDraft"      text,                  -- qoralama (Eskiz moderatsiyasiga yuborish uchun)
  "tgText"        text,                  -- Telegram matni (PKG-10)
  days            jsonb,                 -- hafta kunlari [0=Yak, 1=Dush .. 6=Shan]
  "hourFrom"      int,                   -- Toshkent soati (0–23)
  "hourTo"        int,                   -- (1–24), hourFrom < hourTo
  "dayOfMonth"    int,                   -- qarz eslatmasi: oyning shu kunidan keyin (1–28)
  "lookbackDays"  int,                   -- yangi faktura: necha kun orqaga (1–60)
  editors         jsonb,                 -- 'general': qo'shimcha muharrir uid'lari
  "enabledAt"     timestamptz,
  "updatedBy"     text, "updatedAt" timestamptz
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'notify_settings_id_chk') then
    alter table public.notify_settings add constraint notify_settings_id_chk check (id in ('general','new_invoice','debt_reminder','manual_remind'));
  end if;
end $$;
insert into public.notify_settings(id, enabled, days, "hourFrom", "hourTo", "dayOfMonth", "lookbackDays", editors) values
  ('general',       true,  null,              9,    20,   null, null, '[]'::jsonb),
  ('new_invoice',   false, '[0,1,2,3,4,5,6]', null, null, null, 14,   null),
  ('debt_reminder', false, '[1,4]',           null, null, 10,   null, null),
  ('manual_remind', true,  null,              null, null, null, null, null)
on conflict (id) do nothing;

create or replace function app.is_notify_editor() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.is_admin() or (app.uid() is not null and exists (
    select 1 from public.notify_settings g, public.users u
     where g.id = 'general' and coalesce(g.editors, '[]'::jsonb) ? app.uid()
       and u.id = app.uid() and coalesce(nullif(u.status, ''), 'active') = 'active'))
$$;
revoke all on function app.is_notify_editor() from public;
grant execute on function app.is_notify_editor() to anon, authenticated, service_role;

alter table public.notify_settings enable row level security;
revoke all on public.notify_settings from anon, authenticated;
grant select, update on public.notify_settings to authenticated;
grant all on public.notify_settings to service_role;
drop policy if exists ns_sel on public.notify_settings;
create policy ns_sel on public.notify_settings for select using (app.is_notify_editor());
drop policy if exists ns_upd on public.notify_settings;
create policy ns_upd on public.notify_settings for update using (app.is_notify_editor()) with check (app.is_notify_editor());

create or replace function app.notify_settings_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare d jsonb;
begin
  if new.id is distinct from old.id then raise exception 'Sozlama turini o''zgartirib bo''lmaydi' using errcode = '22023'; end if;
  if not app.is_system() and new.editors is distinct from old.editors and not app.is_admin() then
    raise exception 'Muharrirlarni faqat Direktor tayinlaydi' using errcode = '42501';
  end if;
  if new."hourFrom" is not null and (new."hourFrom" < 0 or new."hourFrom" > 23) then raise exception 'Boshlanish soati 0–23' using errcode = '22023'; end if;
  if new."hourTo" is not null and (new."hourTo" < 1 or new."hourTo" > 24) then raise exception 'Tugash soati 1–24' using errcode = '22023'; end if;
  if new."hourFrom" is not null and new."hourTo" is not null and new."hourFrom" >= new."hourTo" then raise exception 'Soat oralig''i noto''g''ri (boshlanish < tugash)' using errcode = '22023'; end if;
  if new."dayOfMonth" is not null and (new."dayOfMonth" < 1 or new."dayOfMonth" > 28) then raise exception 'Oyning kuni 1–28' using errcode = '22023'; end if;
  if new."lookbackDays" is not null and (new."lookbackDays" < 1 or new."lookbackDays" > 60) then raise exception 'Necha kun orqaga: 1–60' using errcode = '22023'; end if;
  if new.days is not null then
    if jsonb_typeof(new.days) <> 'array' then raise exception 'Hafta kunlari ro''yxat bo''lishi kerak' using errcode = '22023'; end if;
    for d in select value from jsonb_array_elements(new.days) loop
      if jsonb_typeof(d) <> 'number' or (d::text)::numeric not in (0,1,2,3,4,5,6) then raise exception 'Hafta kuni 0–6' using errcode = '22023'; end if;
    end loop;
  end if;
  if new.editors is not null and jsonb_typeof(new.editors) <> 'array' then raise exception 'Muharrirlar ro''yxat bo''lishi kerak' using errcode = '22023'; end if;
  if length(coalesce(new."smsActive", '')) > 600 or length(coalesce(new."smsDraft", '')) > 600 or length(coalesce(new."tgText", '')) > 2000 then
    raise exception 'Matn juda uzun' using errcode = '22023';
  end if;
  -- Birinchi (qayta) yoqilgan vaqt: undan oldingi fakturalarga «yangi faktura» xabari ketmaydi (sms-worker).
  if new.enabled and not coalesce(old.enabled, false) then new."enabledAt" := now(); end if;
  new."updatedBy" := coalesce(app.uid(), new."updatedBy"); new."updatedAt" := now();
  return new;
end $$;
revoke all on function app.notify_settings_guard() from public, anon, authenticated;
drop trigger if exists trg_notify_settings_guard on public.notify_settings;
create trigger trg_notify_settings_guard before update on public.notify_settings
  for each row execute function app.notify_settings_guard();

-- 2) Sinfga e'lonlar
create table if not exists public.class_announcements (
  id           text primary key default gen_random_uuid()::text,
  "classKeys"  jsonb not null default '["all"]'::jsonb,   -- ['all'] yoki sinf kalitlari ('uz-5-A' — admin.html classKeyOf)
  title        text not null,
  body         text,
  "createdBy"  text,
  "createdAt"  timestamptz not null default now(),
  "expiresAt"  timestamptz,
  pinned       boolean not null default false
);
create index if not exists class_announcements_created_idx on public.class_announcements("createdAt" desc);
-- classKeys doim ro'yxat (ann_visible/ann_can_write shunga tayanadi; noto'g'ri qator xodimlar uchun BUTUN ro'yxatni buzmasin).
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'class_announcements_keys_chk') then
    alter table public.class_announcements add constraint class_announcements_keys_chk check (jsonb_typeof("classKeys") = 'array');
  end if;
end $$;
-- Ota-onaning faol farzandlari sinf kalitlari (claim_row — owns_child bilan bir xil qoida).
create or replace function app.my_child_class_keys() returns text[]
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(array_agg(distinct app.student_class_key(s.lang, s.grade, s."classLetter", s.track)), '{}'::text[])
    from public.child_claims cc join public.students s on s.id = app.claim_row(cc."studentId", cc.code)
   where cc.uid = app.uid() and coalesce(nullif(cc.status, ''), 'active') = 'active'
     and not exists (select 1 from public.users u where u.id = cc.uid and u.status = 'blocked')
$$;
-- Xodimning sinflari (sinf rahbarligi + kurator/o'qituvchi biriktirilgan sinflar).
create or replace function app.my_staff_class_keys() returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select coalesce(u."homeroomClasses", '[]'::jsonb) || coalesce(u."assignedClasses", '[]'::jsonb)
                     from public.users u where u.id = app.uid() and coalesce(nullif(u.status, ''), 'active') = 'active'), '[]'::jsonb)
$$;
create or replace function app.ann_visible(p_keys jsonb, p_exp timestamptz) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case
    when app.is_admin() or app.is_zavuch() then true
    when jsonb_typeof(p_keys) is distinct from 'array' then false
    when app.is_staff() then coalesce(p_keys, '[]'::jsonb) ? 'all'
         or exists (select 1 from jsonb_array_elements_text(coalesce(p_keys, '[]'::jsonb)) k where app.my_staff_class_keys() ? k)
    else (p_exp is null or p_exp > now()) and cardinality(app.my_child_class_keys()) > 0
         and (coalesce(p_keys, '[]'::jsonb) ? 'all'
              or exists (select 1 from jsonb_array_elements_text(coalesce(p_keys, '[]'::jsonb)) k where k = any(app.my_child_class_keys())))
  end
$$;
-- Yozish: Direktor / O'IBDO' — istalgan sinf yoki butun maktab; sinf rahbari — faqat o'z sinflari (butun maktab emas).
create or replace function app.ann_can_write(p_keys jsonb) returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case
    when jsonb_typeof(p_keys) is distinct from 'array' or jsonb_array_length(p_keys) = 0 then false
    when app.is_admin() or app.is_zavuch() then true
    when p_keys ? 'all' then false
    -- Sinf rahbari — har kalit bo'yicha app.is_homeroom_for (faol hisob + admin / O'IBDO' / kurator / o'qituvchi lavozimi, asosiy
    --   yoki qo'shimcha + homeroomClasses). Avval faqat homeroomClasses qaralardi: roli o'zgargan sobiq rahbar (masalan, HR) API
    --   orqali sinfga e'lon yoza olardi (Telegram'da ota-onalarga ham ketardi), panelda esa bo'lim yopiq.
    else not exists (select 1 from jsonb_array_elements_text(p_keys) k where not app.is_homeroom_for(k))
  end
$$;
do $$ declare f text; begin
  foreach f in array array['app.my_child_class_keys()', 'app.my_staff_class_keys()', 'app.ann_visible(jsonb, timestamptz)', 'app.ann_can_write(jsonb)'] loop
    execute 'revoke all on function ' || f || ' from public';
    execute 'grant execute on function ' || f || ' to anon, authenticated, service_role';
  end loop;
end $$;
alter table public.class_announcements enable row level security;
revoke all on public.class_announcements from anon, authenticated;
grant select, insert, update, delete on public.class_announcements to authenticated;
grant all on public.class_announcements to service_role;
drop policy if exists ann_sel on public.class_announcements;
create policy ann_sel on public.class_announcements for select using (app.ann_visible("classKeys", "expiresAt"));
drop policy if exists ann_ins on public.class_announcements;
create policy ann_ins on public.class_announcements for insert with check (app.ann_can_write("classKeys") and "createdBy" = app.uid());
drop policy if exists ann_upd on public.class_announcements;
create policy ann_upd on public.class_announcements for update using (app.is_admin() or app.is_zavuch() or "createdBy" = app.uid())
  with check (app.ann_can_write("classKeys"));
drop policy if exists ann_del on public.class_announcements;
create policy ann_del on public.class_announcements for delete using (app.is_admin() or app.is_zavuch() or "createdBy" = app.uid());
create or replace function app.ann_stamp() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if coalesce(btrim(new.title), '') = '' then raise exception 'E''lon sarlavhasi bo''sh' using errcode = '22023'; end if;
  if length(new.title) > 200 or length(coalesce(new.body, '')) > 4000 then raise exception 'E''lon juda uzun' using errcode = '22023'; end if;
  if tg_op = 'UPDATE' then new."createdBy" := old."createdBy"; new."createdAt" := old."createdAt"; end if;
  return new;
end $$;
revoke all on function app.ann_stamp() from public, anon, authenticated;
drop trigger if exists trg_ann_stamp on public.class_announcements;
create trigger trg_ann_stamp before insert or update on public.class_announcements for each row execute function app.ann_stamp();

-- 3) O'zgarishlar tarixi
select app.chlog_attach('notify_settings',     'enabled,smsActive,smsDraft,tgText,days,hourFrom,hourTo,dayOfMonth,lookbackDays,editors');
select app.chlog_attach('class_announcements', 'classKeys,title,body,expiresAt,pinned');

notify pgrst, 'reload schema';
