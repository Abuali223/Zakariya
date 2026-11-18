-- =====================================================================
-- test-audit-11-platforma.sql — A8-01: chegirma «meros» (legacy) nusxalari sinovi — discount-approval.sql 4-bo'limi (deploy
--   qayta ishga tushganda yangi nusxa YARATILMAYDI) va audit-11-platforma.sql (avvalgi deploylar yaratgan noto'g'ri nusxalar
--   bekor qilinadi; fakturalardagi ishora haqiqiy so'rovga ko'chiriladi yoki qayta hisoblash ro'yxatiga tushadi).
--   Har so'rov va tasdiq haqiqiy rol bilan (authenticated + JWT sub): qabulxona so'raydi, Direktor va Moliya menejeri tasdiqlaydi.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-audit-11-platforma.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar / chegirma jadvali bo'sh bo'lmasa — darhol to'xtaydi.
--   Ma'lumot to'qima. Deploy — zanjirdagi AYNAN o'sha fayllarni shu tranzaksiyada qayta ishga tushirish (\ir; fayllar idempotent).
--   Vaqt chizig'i (tranzaksiya ichida now() o'zgarmaydi — shu sabab vaqtlar qo'lda qo'yiladi):
--     -90 kun — tasdiq oqimi joriy qilingan birinchi deploy (haqiqiy meros yozuvlari);
--     -40 … -19 kun — so'rovlar va ikki tasdiq; hozir — navbatdagi deploy.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.discount_requests) then
    raise exception 'test-audit-11-platforma.sql: o''quvchilar / chegirma jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
set local iqror.migrating = '1';
insert into public.users (id, email, role, status) values
  ('U_DIR','d@example.org','director','active'), ('U_FIN','f@example.org','finance_mgr','active'), ('U_REC','r@example.org','reception','active')
on conflict (id) do update set role = excluded.role, status = excluded.status;
insert into public.config (id, "discountApprovalFrom") values ('finance', '2026-01')
  on conflict (id) do update set "discountApprovalFrom" = excluded."discountApprovalFrom";
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus") values
  ('IQ-1101','IQ-1101','Sinov Vaqtinchalik',5,'A','uz',''),          -- (a) xodim farzandi 50% — faqat 2026-12
  ('IQ-1102','IQ-1102','Sinov Kelajak Grant',5,'A','uz',''),         -- (b) 100% grant — 2027-06 dan
  ('IQ-1103','IQ-1103','Sinov Haqiqiy Meros',5,'A','uz',''),         -- (c) tasdiq oqimidan OLDINGI chegirma (haqiqiy meros)
  ('IQ-1104','IQ-1104','Sinov Aka-uka',5,'A','uz',''),               -- (d) aka-uka 10% — 2026-12..2027-01
  ('IQ-1105','IQ-1105','Sinov Meros Va Grant',5,'A','uz',''),        -- (e) haqiqiy meros 50% + keyin faqat 2027-01 grant
  ('IQ-1106','IQ-1106','Sinov Ikki Guruh',5,'A','uz',''),            -- 50% 2026-12..2027-01 + aka-uka 10% faqat 2026-12
  ('IQ-1107','IQ-1107','Sinov Kontrakt',5,'A','uz',''),              -- kontrakt 1,5 mln 2026-12..2027-02, keyin 1,8 mln 2027-02 dan
  ('IQ-1108','IQ-1108','Sinov Deploy Fayli',5,'A','uz','')           -- C bo'limi: audit-11-platforma.sql o'zi tuzatadi
on conflict (id) do nothing;
-- Tasdiq oqimidan OLDIN student_private'da bo'lgan chegirmalar (eski baza).
insert into public.student_private (id, "specialCategory") values ('IQ-1103','teacher_child'), ('IQ-1105','teacher_child')
on conflict (id) do update set "specialCategory" = excluded."specialCategory";
set local iqror.migrating = '';

create schema if not exists zz;
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  if p_uid is null then execute 'set local role anon'; else execute 'set local role authenticated'; end if;
  begin
    execute p_q into r;
  exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
-- Baza / migratsiya nomidan (JWT yo'q) — xato matn sifatida qaytadi (sinov to'xtamaydi).
create or replace function zz.q(p_q text) returns text language plpgsql as $$
declare r text;
begin
  begin execute p_q into r; exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
  return coalesce(r, '<null>');
end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- So'rov: qabulxona yaratadi, Direktor va Moliya menejeri tasdiqlaydi; id zz.<teg> sozlamasida. Vaqt: p_days kun oldin so'ralgan,
--   bir kundan keyin ikkala tasdiq (birinchi «meros» deployidan keyin, navbatdagi deploydan oldin).
create or replace function zz.req(p_tag text, p_sid text, p_kind text, p_params jsonb, p_from text, p_to text, p_days int) returns text language plpgsql as $$
declare v_id text; a text; b text;
begin
  v_id := zz.as('U_REC', format($q$select public.discount_request_create(%L, %L, %L::jsonb, %L, %L, 'Sinov asosi')->>'id'$q$,
                                p_sid, p_kind, p_params::text, p_from, p_to));
  a := zz.as('U_DIR', format($q$select public.discount_decide(%L, true)->>'status'$q$, v_id));
  b := zz.as('U_FIN', format($q$select public.discount_decide(%L, true)->>'status'$q$, v_id));
  perform set_config('zz.' || p_tag, v_id, true);
  perform set_config('iqror.migrating', '1', true);
  update public.discount_requests
     set "requestedAt" = now() - make_interval(days => p_days), "directorAt" = now() - make_interval(days => p_days - 1),
         "financeAt" = now() - make_interval(days => p_days - 1), "appliedAt" = now() - make_interval(days => p_days - 1)
   where id = v_id;
  perform set_config('iqror.migrating', '', true);
  return a || '/' || b;
end $$;
-- Faktura (baza nomidan — mijoz qoidasi emas, faqat invoice_discount_guard tasdiq ishoralarini tekshiradi). Asosiy narx 2 800 000.
create or replace function zz.inv(p_sid text, p_month text, p_pct numeric, p_grant boolean, p_refs jsonb,
                                  p_base numeric default 2800000, p_info text default null, p_status text default 'pending') returns text language plpgsql as $$
begin
  insert into public.invoices (id, "studentId", month, amount, "baseAmount", "pctApplied", "isGrant", "discountInfo", "approvalRefs", status, "paidAmount")
  values (p_sid || '__' || p_month, p_sid, p_month, round(p_base * (1 - p_pct)), p_base, p_pct, p_grant,
          coalesce(p_info, case when p_grant then 'Grant 100%' when p_pct = 0.5 then 'Xodim farzandi 50%' when p_pct = 0.1 then 'Aka-uka 10%' else '' end),
          p_refs, p_status, 0);
  return 'OK';
exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $$;
create or replace function zz.refs(p_id text) returns text language sql as $$
  select coalesce((select "approvalRefs"::text from public.invoices where id = p_id), '<yo''q>') $$;
-- Haqiqiy so'rov id'larini nomga almashtirish (uuid tasodifiy) — natijani o'qish oson bo'lsin.
create or replace function zz.nm(p text) returns text language plpgsql as $$
declare r text := coalesce(p, '<null>'); t text; v text;
begin
  foreach t in array array['ra', 'rb', 'rd', 're', 'r6c', 'r6s', 'r7a', 'r7b', 'r8'] loop
    v := nullif(current_setting('zz.' || t, true), '');
    if v is not null then r := replace(r, v, upper(t)); end if;
  end loop;
  return r;
end $$;

-- ===== 0) Tasdiq oqimi joriy qilingan birinchi deploy: mavjud chegirmalar — haqiqiy meros =====
\set iqror_chain 1
\ir discount-approval.sql
set local iqror.migrating = '1';
update public.discount_requests set "requestedAt" = now() - interval '90 days', "appliedAt" = now() - interval '90 days' where legacy;
set local iqror.migrating = '';
select zz.chk('A00 birinchi deploy: haqiqiy meros yozuvlari (c, e) yaratildi',
  (select string_agg(id || ':' || kind || ':' || status, ',' order by id) from public.discount_requests where legacy),
  '^legacy__IQ-1103__cat:teacher_child:approved,legacy__IQ-1105__cat:teacher_child:approved$');

-- ===== A) Tasdiq oqimi: so'rovlar ikki tasdiq bilan, so'ng deploy IKKI marta =====
select zz.chk('A01 so''rovlar qabulxonadan, Direktor + Moliya menejeri tasdig''i bilan',
  zz.req('ra',  'IQ-1101', 'teacher_child',   '{}', '2026-12', '2026-12', 30) || ' ' ||
  zz.req('rb',  'IQ-1102', 'olympiad',        '{}', '2027-06', null,      30) || ' ' ||
  zz.req('rd',  'IQ-1104', 'sibling_force',   '{}', '2026-12', '2027-01', 30) || ' ' ||
  zz.req('re',  'IQ-1105', 'olympiad',        '{}', '2027-01', '2027-01', 30) || ' ' ||
  zz.req('r6c', 'IQ-1106', 'teacher_child',   '{}', '2026-12', '2027-01', 30) || ' ' ||
  zz.req('r6s', 'IQ-1106', 'sibling_force',   '{}', '2026-12', '2026-12', 30) || ' ' ||
  zz.req('r7a', 'IQ-1107', 'contract', '{"contractAmount":1500000}', '2026-12', '2027-02', 40) || ' ' ||
  zz.req('r7b', 'IQ-1107', 'contract', '{"contractAmount":1800000}', '2027-02', null,      20),
  '^(pending/approved ?){8}$');
select zz.chk('A02 discount_apply student_private''ga darhol yozdi (muddatidan qat''i nazar) — meros nusxaning manbai shu',
  (select string_agg(id || '=' || coalesce("specialCategory", '') || '/' || coalesce("siblingDiscount", '') || '/' || coalesce("contractAmount"::text, ''), ',' order by id)
     from public.student_private where id in ('IQ-1101','IQ-1102','IQ-1104','IQ-1105','IQ-1106','IQ-1107')),
  '^IQ-1101=teacher_child//,IQ-1102=olympiad//,IQ-1104=/Ha/,IQ-1105=olympiad//,IQ-1106=teacher_child/Ha/,IQ-1107=contract//1800000$');
\ir discount-approval.sql
\ir discount-approval.sql
select zz.chk('A03 deploy ×2: tasdiq oqimidan o''tgan o''quvchilarga «meros» nusxa YARATILMADI (faqat haqiqiy meros c, e qoldi)',
  (select string_agg(id, ',' order by id) from public.discount_requests where legacy),
  '^legacy__IQ-1103__cat,legacy__IQ-1105__cat$');
select zz.chk('A04 (a) vaqtinchalik va (b) kelajakdagi tasdiqlar o''z muddatini saqladi',
  zz.nm((select string_agg(id || ':' || kind || ':' || coalesce("fromMonth", '-') || '..' || coalesce("toMonth", '-') || ':' || status, ',' order by "studentId")
           from public.discount_requests where id in (current_setting('zz.ra'), current_setting('zz.rb')))),
  '^RA:teacher_child:2026-12..2026-12:approved,RB:olympiad:2027-06..-:approved$');
select zz.chk('A05 (c) haqiqiy meros saqlandi: tasdiqlangan, muddatsiz, birinchi deploy vaqti o''zgarmadi',
  (select string_agg(status || ':' || coalesce("fromMonth", '-') || '..' || coalesce("toMonth", '-') || ':' || ("requestedAt" = now() - interval '90 days')::text, ',')
     from public.discount_requests where id in ('legacy__IQ-1103__cat', 'legacy__IQ-1105__cat')),
  '^approved:-..-:true,approved:-..-:true$');
select zz.chk('A06 qo''riqchi: (a) 2027-02 da 50% — tasdiq faqat 2026-12 uchun, meros nusxasi yo''q — rad',
  zz.inv('IQ-1101', '2027-02', 0.5, false, jsonb_build_array(current_setting('zz.ra'))) || ' | ' ||
  zz.inv('IQ-1101', '2027-02', 0.5, false, '["legacy__IQ-1101__cat"]'), '^ERR 23514 .* \| ERR 23514 ');
select zz.chk('A07 qo''riqchi: (a) 2026-12 da 50% — o''z tasdig''i bilan qabul', zz.inv('IQ-1101', '2026-12', 0.5, false, jsonb_build_array(current_setting('zz.ra'))), '^OK$');
select zz.chk('A08 qo''riqchi: (b) 2027-01 da 100% grant — boshlanishidan oldin, meros nusxasi yo''q — rad',
  zz.inv('IQ-1102', '2027-01', 1, true, jsonb_build_array(current_setting('zz.rb'))) || ' | ' ||
  zz.inv('IQ-1102', '2027-01', 1, true, '["legacy__IQ-1102__cat"]'), '^ERR 23514 .* \| ERR 23514 ');
select zz.chk('A09 qo''riqchi: (b) 2027-07 da grant — qabul', zz.inv('IQ-1102', '2027-07', 1, true, jsonb_build_array(current_setting('zz.rb'))), '^OK$');
select zz.chk('A10 qo''riqchi: (c) haqiqiy meros bilan 50% — qabul (meros chegirmalar ishlayveradi)',
  zz.inv('IQ-1103', '2027-02', 0.5, false, '["legacy__IQ-1103__cat"]'), '^OK$');
select zz.chk('A11 (e) haqiqiy meros + muddatli grant: 2027-01 — grant, 2027-02 — yana meros 50% (avvalgi xulq)',
  zz.inv('IQ-1105', '2027-01', 1, true, jsonb_build_array(current_setting('zz.re'))) || ' | ' ||
  zz.inv('IQ-1105', '2027-02', 0.5, false, '["legacy__IQ-1105__cat"]'), '^OK \| OK$');
set local iqror.migrating = '1';
delete from public.invoices where "studentId" like 'IQ-11%';
set local iqror.migrating = '';

-- ===== B) Avvalgi (tuzatishdan oldingi) deploylar qoldirgan holat va uni tuzatish =====
-- Tuzatishdan OLDINGI discount-approval.sql 4-bo'limi — AYNAN shu ko'rinishda har deployda ishlardi (himoyasiz):
insert into public.discount_requests(id, "studentId", kind, params, reason, status, legacy, "requestedAt", "appliedAt")
select 'legacy__' || x.sid || '__cat', x.sid,
       case when x.cat = 'olympiad' then 'olympiad' when x.cat = 'contract' then 'contract' else 'teacher_child' end,
       case when x.cat = 'contract' then jsonb_build_object('contractAmount', x.amt)
            when x.cat = 'teacher_child' then jsonb_strip_nulls(jsonb_build_object('teacherId', nullif(btrim(coalesce(x.tid, '')), '')))
            else '{}'::jsonb end,
       'Avvaldan bor (meros) — direktor ko''rib chiqadi', 'approved', true, now(), now()
  from (select coalesce(nullif(s."studentId", ''), p.id) as sid, p."specialCategory" as cat, p."contractAmount" as amt, p."teacherId" as tid
          from public.student_private p left join public.students s on s.id = p.id
         where p."specialCategory" in ('teacher_child', 'olympiad', 'contract')) x
on conflict (id) do nothing;
insert into public.discount_requests(id, "studentId", kind, params, reason, status, legacy, "requestedAt", "appliedAt")
select 'legacy__' || coalesce(nullif(s."studentId", ''), p.id) || '__sib', coalesce(nullif(s."studentId", ''), p.id),
       case when p."siblingDiscount" = 'Ha' then 'sibling_force' else 'sibling_exclude' end, '{}'::jsonb,
       'Avvaldan bor (meros) — direktor ko''rib chiqadi', 'approved', true, now(), now()
  from public.student_private p left join public.students s on s.id = p.id
 where p."siblingDiscount" in ('Ha', 'Yoq')
on conflict (id) do nothing;
select zz.chk('B00 eski deploy: tasdiqlangan so''rovlardan muddatsiz «meros» nusxalari yaratilgan edi (xato manbai)',
  (select string_agg(id || ':' || coalesce("fromMonth", '-') || '..' || coalesce("toMonth", '-'), ',' order by id) from public.discount_requests
    where legacy and "studentId" not in ('IQ-1103', 'IQ-1105')),
  '^legacy__IQ-1101__cat:-..-,legacy__IQ-1102__cat:-..-,legacy__IQ-1104__sib:-..-,legacy__IQ-1106__cat:-..-,legacy__IQ-1106__sib:-..-,legacy__IQ-1107__cat:-..-$');
-- O'sha nusxalar bilan chiqqan fakturalar (eski qo'riqchi nusxani amaldagi tasdiq deb qabul qilardi):
select zz.chk('B01 nusxa bilan fakturalar (tayyorgarlik) — eski holatda qo''riqchi qabul qilardi',
  zz.inv('IQ-1101', '2026-12', 0.5, false, '["legacy__IQ-1101__cat"]') || ' ' ||   -- tasdiq oyi: summa to'g'ri -> ishora ko'chadi
  zz.inv('IQ-1101', '2027-02', 0.5, false, '["legacy__IQ-1101__cat"]') || ' ' ||   -- tasdiqsiz 50% -> qayta hisoblash
  zz.inv('IQ-1101', '2027-03', 0.5, false, '["legacy__IQ-1101__cat"]', 2800000, null, 'canceled') || ' ' ||   -- bekor qilingan — tegilmaydi
  zz.inv('IQ-1102', '2027-01', 1, true, '["legacy__IQ-1102__cat"]') || ' ' ||       -- grant boshlanishidan oldin -> qayta hisoblash
  zz.inv('IQ-1102', '2027-07', 1, true, '["legacy__IQ-1102__cat"]') || ' ' ||       -- grant oyi -> ko'chadi
  zz.inv('IQ-1104', '2026-12', 0.1, false, '["legacy__IQ-1104__sib"]') || ' ' ||    -- aka-uka oyi -> ko'chadi
  zz.inv('IQ-1104', '2027-03', 0.1, false, '["legacy__IQ-1104__sib"]') || ' ' ||    -- muddatdan keyin -> qayta hisoblash
  zz.inv('IQ-1106', '2027-01', 0.5, false, '["legacy__IQ-1106__cat","legacy__IQ-1106__sib"]') || ' ' ||   -- 50% ko'chadi, aka-uka emas -> butun faktura qayta hisoblash
  zz.inv('IQ-1107', '2027-01', 0, false, '["legacy__IQ-1107__cat"]', 1800000, 'Kontrakt') || ' ' ||   -- 1,5 mln tasdiqlangan oy 1,8 mln bilan -> qayta hisoblash
  zz.inv('IQ-1107', '2027-02', 0, false, '["legacy__IQ-1107__cat"]', 1800000, 'Kontrakt') || ' ' ||   -- 1,8 mln tasdiqlangan oy -> ko'chadi
  zz.inv('IQ-1103', '2027-02', 0.5, false, '["legacy__IQ-1103__cat"]') || ' ' ||   -- haqiqiy meros — tegilmaydi
  zz.inv('IQ-1105', '2027-02', 0.5, false, '["legacy__IQ-1105__cat"]'),             -- haqiqiy meros — tegilmaydi
  '^(OK ?){12}$');
-- Navbatdagi (tuzatilgan) deploy: discount-approval.sql, so'ng tuzatish (audit-11-platforma.sql dagi funksiya — xulosa jsonb).
\ir discount-approval.sql
select zz.chk('B02 tuzatish xulosasi: 6 ta nusxa bekor, 5 o''quvchi; 4 faktura ko''chdi; 5 tasi qayta hisoblash ro''yxatida',
  zz.q($q$select app.discount_legacy_repair_notice()::text$q$),
  '^\{"moved": \["IQ-1101__2026-12", "IQ-1102__2027-07", "IQ-1104__2026-12", "IQ-1107__2027-02"\], "reprice": \["IQ-1101__2027-02", "IQ-1102__2027-01", "IQ-1104__2027-03", "IQ-1106__2027-01", "IQ-1107__2027-01"\], "canceled": 6, "students": \["IQ-1101", "IQ-1102", "IQ-1104", "IQ-1106", "IQ-1107"\]\}$');
select zz.chk('B03 noto''g''ri nusxalar bekor qilindi (o''chirilmadi — tarix qoladi), sababi yozildi',
  (select string_agg(id || ':' || status || ':' || (reason like '%A8-01%')::text, ',' order by id) from public.discount_requests
    where legacy and "studentId" not in ('IQ-1103', 'IQ-1105')),
  '^legacy__IQ-1101__cat:canceled:true,legacy__IQ-1102__cat:canceled:true,legacy__IQ-1104__sib:canceled:true,legacy__IQ-1106__cat:canceled:true,legacy__IQ-1106__sib:canceled:true,legacy__IQ-1107__cat:canceled:true$');
select zz.chk('B04 haqiqiy meros (c, e) tegilmadi',
  (select string_agg(id || ':' || status || ':' || reason, ',' order by id) from public.discount_requests where id in ('legacy__IQ-1103__cat', 'legacy__IQ-1105__cat')),
  '^legacy__IQ-1103__cat:approved:Avvaldan bor \(meros\) — direktor ko''rib chiqadi,legacy__IQ-1105__cat:approved:Avvaldan bor \(meros\) — direktor ko''rib chiqadi$');
select zz.chk('B05 summasi to''g''ri fakturalar: ishora shu oyni qamragan haqiqiy so''rovga ko''chdi (1,8 mln — keyingi so''rov)',
  zz.nm(zz.refs('IQ-1101__2026-12') || ' ' || zz.refs('IQ-1102__2027-07') || ' ' || zz.refs('IQ-1104__2026-12') || ' ' || zz.refs('IQ-1107__2027-02')),
  '^\["RA"\] \["RB"\] \["RD"\] \["R7B"\]$');
select zz.chk('B06 tasdiqsiz chegirmali fakturalar tegilmadi (qayta hisoblanadi); bekor qilingan va haqiqiy meros fakturalari ham',
  zz.refs('IQ-1101__2027-02') || ' ' || zz.refs('IQ-1102__2027-01') || ' ' || zz.refs('IQ-1104__2027-03') || ' ' || zz.refs('IQ-1106__2027-01') || ' '
  || zz.refs('IQ-1107__2027-01') || ' ' || zz.refs('IQ-1101__2027-03') || ' ' || zz.refs('IQ-1103__2027-02') || ' ' || zz.refs('IQ-1105__2027-02'),
  '^\["legacy__IQ-1101__cat"\] \["legacy__IQ-1102__cat"\] \["legacy__IQ-1104__sib"\] \["legacy__IQ-1106__cat", "legacy__IQ-1106__sib"\] \["legacy__IQ-1107__cat"\] \["legacy__IQ-1101__cat"\] \["legacy__IQ-1103__cat"\] \["legacy__IQ-1105__cat"\]$');
select zz.chk('B07 Direktorning «Pul qoidalari buzilishi» hisoboti aynan qayta hisoblanadigan 5 fakturani ko''rsatadi',
  zz.as('U_DIR', $q$select e->>'count' || ' ' || (e->'ids')::text from jsonb_array_elements(public.money_rule_violations()->'rules') e where e->>'key' = 'discount'$q$),
  '^5 \["IQ-1104__2027-03", "IQ-1101__2027-02", "IQ-1102__2027-01", "IQ-1106__2027-01", "IQ-1107__2027-01"\]$');
select zz.chk('B08 qo''riqchi: bekor qilingan nusxa bilan yangi faktura — rad; haqiqiy so''rov bilan — qabul',
  zz.inv('IQ-1101', '2027-04', 0.5, false, '["legacy__IQ-1101__cat"]') || ' | ' || zz.inv('IQ-1104', '2027-01', 0.1, false, jsonb_build_array(current_setting('zz.rd'))),
  '^ERR 23514 .* \| OK$');
-- Deploy yana ikki marta (to'liq: discount-approval.sql + audit-11-platforma.sql) — hech narsa o'zgarmaydi.
create temporary table zz_snap on commit drop as
  select (select string_agg(id || ':' || status || ':' || coalesce(reason, ''), ',' order by id) from public.discount_requests) as dr,
         (select string_agg(id || ':' || coalesce("approvalRefs"::text, ''), ',' order by id) from public.invoices) as inv;
\ir discount-approval.sql
\ir audit-11-platforma.sql
\ir discount-approval.sql
\ir audit-11-platforma.sql
select zz.chk('B09 deploy ×2 tuzatishdan keyin: so''rovlar va fakturalar o''zgarmadi, yangi nusxa yo''q (idempotent)',
  (select ((select string_agg(id || ':' || status || ':' || coalesce(reason, ''), ',' order by id) from public.discount_requests) = s.dr)::text || '/'
          || ((select string_agg(id || ':' || coalesce("approvalRefs"::text, ''), ',' order by id) from public.invoices) = s.inv)::text from zz_snap s),
  '^true/true$');
select zz.chk('B10 qayta chaqirilganda tuzatadigan narsa yo''q', zz.q($q$select app.discount_legacy_repair()::text$q$),
  '^\{"moved": \[\], "reprice": \[\], "canceled": 0, "students": \[\]\}$');
select zz.chk('B11 tuzatish funksiyalari mijozga yopiq', zz.as('U_DIR', $q$select app.discount_legacy_repair()::text$q$) || ' | '
  || zz.as('U_DIR', $q$select app.discount_legacy_repair_notice()::text$q$), '^ERR 42501 .* \| ERR 42501 ');

-- ===== C) Deploy fayli (audit-11-platforma.sql) o'zi tuzatadi =====
select zz.chk('C01 tayyorgarlik: IQ-1108 — tasdiqlangan muddatli so''rov', zz.req('r8', 'IQ-1108', 'teacher_child', '{}', '2026-12', '2027-01', 30), '^pending/approved$');
set local iqror.migrating = '1';
insert into public.discount_requests(id, "studentId", kind, params, reason, status, legacy, "requestedAt", "appliedAt")
values ('legacy__IQ-1108__cat', 'IQ-1108', 'teacher_child', '{}', 'Avvaldan bor (meros) — direktor ko''rib chiqadi', 'approved', true, now(), now());
set local iqror.migrating = '';
select zz.chk('C02 tayyorgarlik: nusxa bilan 2027-05 fakturasi', zz.inv('IQ-1108', '2027-05', 0.5, false, '["legacy__IQ-1108__cat"]'), '^OK$');
\ir audit-11-platforma.sql
select zz.chk('C03 audit-11-platforma.sql: nusxa bekor, faktura qayta hisoblash uchun qoldi, haqiqiy so''rov tasdiqlangan',
  zz.nm((select status from public.discount_requests where id = 'legacy__IQ-1108__cat') || ' ' || zz.refs('IQ-1108__2027-05') || ' '
        || (select id || ':' || status from public.discount_requests where id = current_setting('zz.r8'))),
  '^canceled \["legacy__IQ-1108__cat"\] R8:approved$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
