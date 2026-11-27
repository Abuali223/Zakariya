-- =====================================================================
-- test-kassa-inv.sql — moliya ish rejasi 2-bosqichi, F2.8 (oylik sanash dalolatnomasi, topshirish-qabul, oy oxiri ro'yxati) sinovi:
--   (A) kunni yopishda oylik komissiya inventarizatsiyasi (INV-16): komissiya majburiy (kamida 2 kishi), qat'iy hisobdagi blankalar
--       («Қ» kvitansiyalari) — faqat inventarizatsiyada, shakli tekshiriladi; sanash dalolatnomasi turi 'monthly' (dekabrda — 'yearly'),
--       farq hujjati asosi va izohi, kun javobida invKind, kun hodisasi, takror yuborish, KO-4 ma'lumotidagi dalolatnoma;
--   (B) moddiy javobgar shaxs almashganda smena topshirish: komissiya majburiy (kassa egasining o'zi topshirsa ham), blankalar, takror va
--       zid so'rov, qabulda dalolatnomaga o'tishi (molChange, blankalar, farq hujjati izohi); oddiy topshirishda belgi yo'q;
--   (C) kassa_month_check — oy oxiri ro'yxati: huquqlar (Direktor va 2-ro'yxat; kassir, o'qituvchi, anon — yo'q), oy va kassa tekshiruvi,
--       standart oy, bandlar (yopilmagan kun — block, tekshirilmagan kun, INV-16 oxirgi yopish sanashi bo'yicha, qarorsiz kamomad,
--       biriktirilmagan tushum, vedomost, surat va qulf), ready / canLock, sinov kassasi; nazorat ro'yxatidagi invMissing.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-inv.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov nomlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) or exists (select 1 from public.payroll_runs) then
    raise exception 'test-kassa-inv.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
create or replace function zz.as(p_uid text, p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
  if p_uid is null then execute 'set local role anon'; else execute 'set local role authenticated'; end if;
  begin
    execute p_q into r;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    r := 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(r, '<null>');
end $$;
create or replace function zz.js(p text) returns jsonb language plpgsql as $$
begin return p::jsonb; exception when others then return null; end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
create table if not exists zz.v (k text primary key, v text);
truncate zz.res; truncate zz.v;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
create or replace function zz.put(p_k text, p_v text) returns text language plpgsql as $$
begin insert into zz.v (k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; return p_v; end $$;
create or replace function zz.get(p_k text) returns text language sql as $$ select v from zz.v where k = p_k $$;
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
create or replace function zz.rpc(p_uid text, p_fn text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.%I(%L::jsonb)::text', p_fn, p_json)) $$;
-- oy oxiri ro'yxati: butun javob va bitta band (kod bo'yicha)
create or replace function zz.mc(p_uid text, p_desk text, p_month text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_month_check(%L, %s)::text', p_desk, coalesce(quote_literal(p_month), 'null'))) $$;
create or replace function zz.item(p text, p_code text) returns jsonb language sql as $$
  select (select i from jsonb_array_elements(zz.js(p) -> 'items') i where i ->> 'code' = p_code limit 1) $$;
create or replace function zz.lv(p text, p_code text) returns text language sql as $$
  select coalesce((zz.item(p, p_code) ->> 'level') || '/' || (zz.item(p, p_code) ->> 'n'), '-') $$;
-- kunning oxirgi sanash dalolatnomasi (turi bo'yicha)
create or replace function zz.cnt(p_day date, p_kinds text[]) returns public.cash_counts language sql as $$
  select n.* from public.cash_counts n join public.cash_days d on d.id = n."dayId"
   where d.desk = 'main' and d.day = p_day and n.kind = any(p_kinds) order by n.at desc, n.id desc limit 1 $$;
create or replace function zz.comm3() returns text language sql as $$
  select '[{"title":"Rais — direktor","name":"Sinov Direktor"},{"title":"A’zo — bosh buxgalter","name":"Sinov Buxgalter"},{"title":"A’zo — moliya menejeri","name":"Sinov Moliyachi"}]' $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles", "staffRefType", "staffRefId") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]',null,null), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]',null,null),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]','staff','st1'), ('U_KAS2','k2@x','Sinov Kassir Ikki','kassir','active','[]','teacher','tch1'),
  ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]',null,null), ('U_TCH','t@x','Sinov Muallim','teacher','active','[]',null,null)
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1', 'IQT-T1', 'Sinov O''qituvchi', '[]');
insert into public.staff (id, "staffId", name, position) values ('st1', 'IQX-T1', 'Sinov Xodim', 'Kassir');
set local session_replication_role = origin;
select zz.clock('2027-01-28 10:00+05');   -- payshanba
select zz.put('cp_bank', zz.as('U_FM', $q$select public.fin_counterparty_save(null, 'bank', 'Sinov Bank')::text$q$));
select zz.put('open', zz.rpc('U_DIR', 'kassa_opening_set', '{"amount":1000000,"startDay":"2027-01-28","note":"30.12 sanash","commission":[{"title":"Direktor","name":"Sinov D"},{"title":"Kassir","name":"Sinov K"}]}'));
select zz.put('r1', zz.rpc('U_KAS', 'kassa_receipt', format('{"op":"in_bank","amount":200000,"partyType":"bank","partyId":"%s","basis":"Chek 001","clientRef":"inv-r1-0001"}', zz.js(zz.get('cp_bank')) ->> 'id')));
select zz.chk('A0 urug'': kassa ishga tushdi, kun ochildi (qoldiq 1 200 000)',
  (zz.js(zz.get('r1')) ->> 'status') || '/' || trim_scale(app.kassa_day_balance((select id from public.cash_days where desk = 'main' and status = 'open')))::text, '^posted/1200000$');

-- ---------- (A) kunni yopishda oylik komissiya inventarizatsiyasi ----------
select zz.chk('A1 inventarizatsiya — komissiyasiz (1 kishi) rad',
  zz.rpc('U_KAS', 'kassa_day_close', '{"day":"2027-01-28","counted":1200000,"expected":1200000,"inv":true,"commission":[{"title":"Rais","name":"Sinov Direktor"}]}'),
  '^ERR 22023 \[kassa:commission\] Oylik komissiya inventarizatsiyasida kamida 2 kishilik');
select zz.chk('A2 blankalar inventarizatsiyasiz — rad',
  zz.rpc('U_KAS', 'kassa_day_close', '{"day":"2027-01-28","counted":1200000,"expected":1200000,"blanks":{"count":5,"nos":"0001-0005"}}'), '^ERR 22023 \[kassa:blanks\]');
select zz.chk('A3 blankalar: soni bor, raqamlari yo''q — rad',
  zz.rpc('U_KAS', 'kassa_day_close', format('{"day":"2027-01-28","counted":1200000,"expected":1200000,"inv":true,"commission":%s,"blanks":{"count":3}}', zz.comm3())), '^ERR 22023 \[kassa:blanks\]');
select zz.chk('A3b blankalar: 0 ta, lekin raqam yozilgan — rad',
  zz.rpc('U_KAS', 'kassa_day_close', format('{"day":"2027-01-28","counted":1200000,"expected":1200000,"inv":true,"commission":%s,"blanks":{"count":0,"nos":"0001"}}', zz.comm3())), '^ERR 22023 \[kassa:blanks\]');
select zz.chk('A3c blankalar: soni butun son emas / ro''yxat — rad',
  zz.rpc('U_KAS', 'kassa_day_close', format('{"day":"2027-01-28","counted":1200000,"expected":1200000,"inv":true,"commission":%s,"blanks":{"count":"2.5","nos":"1-2"}}', zz.comm3())) || ' | ' ||
  zz.rpc('U_KAS', 'kassa_day_close', format('{"day":"2027-01-28","counted":1200000,"expected":1200000,"inv":true,"commission":%s,"blanks":[1]}', zz.comm3())),
  '^ERR 22023 \[kassa:blanks\].* \| ERR 22023 \[kassa:blanks\]');
select zz.chk('A3d rad etilgan urinishlar iz qoldirmadi (sanash yo''q, kun ochiq)',
  (select count(*)::text from public.cash_counts where kind <> 'opening') || '/' || (select status from public.cash_days where desk = 'main' and day = '2027-01-28'), '^0/open$');
select zz.put('A4', zz.rpc('U_KAS', 'kassa_day_close', format('{"day":"2027-01-28","counted":1199000,"expected":1200000,"inv":true,"commission":%s,"blanks":{"count":38,"nos":"0013-0050"},"note":"Oy oxiri"}', zz.comm3())));
select zz.chk('A4 oylik inventarizatsiya bilan yopildi: kamomad 1 000', (zz.js(zz.get('A4')) ->> 'diff') || '/' || (zz.js(zz.get('A4')) -> 'day' ->> 'status'), '^-1000/closed$');
select zz.chk('A4b dalolatnoma: turi monthly, belgisiz, blankalar va komissiya (3 kishi) saqlandi',
  (select n.kind || '/' || n."molChange" || '/' || (n.blanks ->> 'count') || '/' || (n.blanks ->> 'nos') || '/' || jsonb_array_length(n.commission) from zz.cnt('2027-01-28', array['close','monthly','yearly']) n),
  '^monthly/false/38/0013-0050/3$');
select zz.chk('A4c farq hujjati: asosi va izohi — INV-16',
  (select c.op || ' | ' || c.basis || ' | ' || c.note || ' | ' || (c."sourceSnapshot" ->> 'kind') from public.cash_docs c where c.id = (select n."diffDocId" from zz.cnt('2027-01-28', array['monthly']) n)),
  '^out_shortage \| Kassani inventarizatsiya qilish dalolatnomasi \(INV-16\), 28\.01\.2027 \| Oylik komissiya inventarizatsiyasi \(kun yopish\) \| monthly$');
select zz.chk('A4d kun javobida invKind = monthly; kun hodisasida countKind',
  (select app.kassa_day_json(d.id) ->> 'invKind' from public.cash_days d where d.desk = 'main' and d.day = '2027-01-28') || '/' ||
  (select e.data ->> 'countKind' from public.cash_day_events e join public.cash_days d on d.id = e."dayId" where d.day = '2027-01-28' and e.kind = 'close' order by e.at desc limit 1),
  '^monthly/monthly$');
select zz.put('A5', zz.rpc('U_KAS', 'kassa_day_close', format('{"day":"2027-01-28","counted":1199000,"inv":true,"commission":%s}', zz.comm3())));
select zz.chk('A5 qayta yuborish — takror (dup), yangi dalolatnoma yo''q',
  (zz.js(zz.get('A5')) ->> 'dup') || '/' || (select count(*) from public.cash_counts where kind = 'monthly')::text, '^true/1$');
select zz.chk('A6 KO-4 ma''lumotida dalolatnoma: monthly, blankalar 38',
  (select (c ->> 'kind') || '/' || (c -> 'blanks' ->> 'count') || '/' || (c ->> 'molChange')
     from jsonb_array_elements(zz.js(zz.as('U_KAS', $q$select public.kassa_day_book('main', '2027-01-28')::text$q$)) -> 'counts') c where c ->> 'kind' <> 'opening' limit 1),
  '^monthly/38/false$');
select zz.put('A7', zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-01-28', 'Blankalar qayta sanaladi')::text$q$));
select zz.chk('A7 Direktor kunni qayta ochdi — ochiq kunda invKind yo''q',
  coalesce(zz.js(zz.get('A7')) -> 'day' ->> 'status', zz.get('A7')) || '/' ||
  (select coalesce(app.kassa_day_json(d.id) ->> 'invKind', 'null') from public.cash_days d where d.desk = 'main' and d.day = '2027-01-28'), '^open/null$');
select zz.put('A8', zz.rpc('U_KAS', 'kassa_day_close', format('{"day":"2027-01-28","counted":1199000,"expected":1200000,"inv":true,"commission":%s,"blanks":{"count":37,"nos":"0014-0050"}}', zz.comm3())));
select zz.chk('A8 qayta yopildi (qayta ochishda farq hujjati bekor bo''lgan — kamomad yana 1 000): invKind — oxirgi yopish sanashi bo''yicha; kunda 2 ta oylik dalolatnoma',
  (zz.js(zz.get('A8')) -> 'day' ->> 'invKind') || '/' || (zz.js(zz.get('A8')) ->> 'diff') || '/' ||
  (select count(*) from public.cash_counts n join public.cash_days d on d.id = n."dayId" where d.day = '2027-01-28' and n.kind = 'monthly')::text || '/' ||
  (select string_agg(c.status, ',' order by c.no) from public.cash_docs c where c.op = 'out_shortage'), '^monthly/-1000/2/void,posted$');

-- ---------- (B) moddiy javobgar shaxs almashganda smena topshirish ----------
select zz.clock('2027-01-29 09:00+05');   -- juma
select zz.put('r2', zz.rpc('U_KAS', 'kassa_receipt', format('{"op":"in_bank","amount":300000,"partyType":"bank","partyId":"%s","basis":"Chek 002","clientRef":"inv-r2-0001"}', zz.js(zz.get('cp_bank')) ->> 'id')));
select zz.chk('B0 ikkinchi kun ochildi: kun boshi 1 199 000, qoldiq 1 499 000',
  (select trim_scale(opening)::text from public.cash_days where desk = 'main' and day = '2027-01-29') || '/' ||
  trim_scale(app.kassa_day_balance((select id from public.cash_days where desk = 'main' and status = 'open')))::text, '^1199000/1499000$');
select zz.chk('B1 moddiy javobgar almashganda — komissiyasiz rad (kassa egasining o''zi topshirsa ham)',
  zz.rpc('U_KAS', 'kassa_handover', '{"counted":1499000,"expected":1499000,"toUid":"U_KAS2","mol":true}'),
  '^ERR 22023 \[kassa:commission\] Moddiy javobgar shaxs almashganda');
select zz.chk('B2 blankalar oddiy topshirishda — rad',
  zz.rpc('U_KAS', 'kassa_handover', '{"counted":1499000,"expected":1499000,"toUid":"U_KAS2","blanks":{"count":0}}'), '^ERR 22023 \[kassa:blanks\]');
select zz.put('B3', zz.rpc('U_KAS', 'kassa_handover', '{"counted":1499500,"expected":1499000,"toUid":"U_KAS2","mol":true,"commission":[{"title":"Rais","name":"Sinov Direktor"},{"title":"A’zo","name":"Sinov Buxgalter"}],"blanks":{"count":0},"note":"Yangi kassir"}'));
select zz.chk('B3 topshirish yozildi: kutilmoqda, belgi va blankalar (0 ta)',
  (zz.js(zz.get('B3')) ->> 'pending') || '/' || (select h."molChange" || '/' || (h.blanks ->> 'count') || '/' || (h.blanks ->> 'nos') || '/' || h.status from public.cash_handovers h where h.desk = 'main'),
  '^true/true/0//pending$');
select zz.chk('B3b aynan shu so''rov qayta — takror; belgisiz zid so''rov — rad (topshirish kutilmoqda)',
  (zz.js(zz.rpc('U_KAS', 'kassa_handover', '{"counted":1499500,"expected":1499000,"toUid":"U_KAS2","mol":true,"commission":[{"title":"Rais","name":"Sinov Direktor"},{"title":"A’zo","name":"Sinov Buxgalter"}],"blanks":{"count":0}}')) ->> 'dup') || ' | ' ||
  zz.rpc('U_KAS', 'kassa_handover', '{"counted":1499500,"expected":1499000,"toUid":"U_KAS2"}'),
  '^true \| ERR P0001 \[kassa:handover_pending\]');
select zz.put('B4', zz.as('U_KAS2', format('select public.kassa_handover_accept(%L)::text', (select h.id from public.cash_handovers h where h.desk = 'main' and h.status = 'pending'))));
select zz.chk('B4 qabul: dalolatnoma — handover, belgi, blankalar; farq +500',
  (zz.js(zz.get('B4')) ->> 'diff') || '/' || (select n.kind || '/' || n."molChange" || '/' || (n.blanks ->> 'count') || '/' || jsonb_array_length(n.commission) from zz.cnt('2027-01-29', array['handover']) n),
  '^500/handover/true/0/2$');
select zz.chk('B4b farq hujjati (ortiqcha): asosi va izohi — moddiy javobgar almashganda INV-16',
  (select c.op || ' | ' || c.basis || ' | ' || c.note || ' | ' || (c."sourceSnapshot" ->> 'molChange') from public.cash_docs c where c.id = (select n."diffDocId" from zz.cnt('2027-01-29', array['handover']) n)),
  '^in_surplus \| Kassani inventarizatsiya qilish dalolatnomasi \(INV-16\), 29\.01\.2027 \| Moddiy javobgar shaxs almashganda inventarizatsiya \(smena topshirish-qabul\) \| true$');
select zz.put('B5', zz.rpc('U_KAS2', 'kassa_handover', '{"counted":1499500,"expected":1499500,"toUid":"U_KAS"}'));
select zz.put('B5b', zz.as('U_KAS', format('select public.kassa_handover_accept(%L)::text', (select h.id from public.cash_handovers h where h.desk = 'main' and h.status = 'pending'))));
select zz.chk('B5 oddiy topshirish (kassa egasi, komissiyasiz): belgi yo''q, blankalar yo''q',
  (zz.js(zz.get('B5')) ->> 'pending') || '/' || (select n."molChange" || '/' || coalesce(n.blanks::text, 'null') || '/' || n.diff from zz.cnt('2027-01-29', array['handover']) n),
  '^true/false/null/0$');

-- ---------- (C) oy oxiri ro'yxati ----------
select zz.clock('2027-02-01 09:00+05');   -- dushanba; 29-yanvar kuni hali ochiq
select zz.chk('C1 huquq: o''qituvchi, kassir va anon — yo''q; buxgalter — bor',
  zz.mc('U_TCH', 'main', '2027-01') || ' | ' || zz.mc('U_KAS', 'main', '2027-01') || ' | ' || zz.mc(null, 'main', '2027-01') || ' | ' || (zz.js(zz.mc('U_ACC', 'main', '2027-01')) ->> 'ok'),
  '^ERR 42501 .* \| ERR 42501 .* \| ERR 42501 .* \| true$');
select zz.chk('C2 oy va kassa tekshiruvi: 2027-13, 2027-1, kelajak oy, noma''lum kassa — rad',
  zz.mc('U_DIR', 'main', '2027-13') || ' | ' || zz.mc('U_DIR', 'main', '2027-1') || ' | ' || zz.mc('U_DIR', 'main', '2027-03') || ' | ' || zz.mc('U_DIR', 'yoq', '2027-01'),
  '^ERR 22023 \[kassa:bad_input\].* \| ERR 22023 \[kassa:bad_input\].* \| ERR 22023 \[kassa:bad_input\].* \| ERR 22023 \[kassa:not_found\]');
select zz.put('C3', zz.mc('U_DIR', 'main', null));
select zz.chk('C3 standart — o''tgan oy (2027-01), oy tugagan; bandlar tartibi',
  (zz.js(zz.get('C3')) ->> 'month') || '/' || (zz.js(zz.get('C3')) ->> 'ended') || '/' ||
  (select string_agg(i ->> 'code', ',' order by o) from jsonb_array_elements(zz.js(zz.get('C3')) -> 'items') with ordinality t(i, o)),
  '^2027-01/true/days_open,days_pending,unverified,inv,shortages,fixes,z,advances,advPending,limit,unmatched,refunds,payroll,snapshot,lock$');
select zz.chk('C4 ochiq kun (29-yanvar): block, ready yo''q, canLock yo''q; INV — oxirgi yopilgan kun (28) bo''yicha joyida',
  zz.lv(zz.get('C3'), 'days_open') || '/' || (zz.item(zz.get('C3'), 'days_open') -> 'days' ->> 0) || '/' || (zz.js(zz.get('C3')) ->> 'blockers') || '/' ||
  (zz.js(zz.get('C3')) ->> 'ready') || '/' || (zz.js(zz.get('C3')) ->> 'canLock') || '/' || zz.lv(zz.get('C3'), 'inv') || '/' || (zz.item(zz.get('C3'), 'inv') ->> 'lastDay'),
  '^block/1/2027-01-29/1/false/false/ok/0/2027-01-28$');
select zz.chk('C4b readyWhy — fin_lock_ready matni (yopilmagan kun)', zz.js(zz.get('C3')) ->> 'readyWhy', 'yopilmagan');
select zz.put('C5', zz.rpc('U_KAS', 'kassa_day_close', '{"day":"2027-01-29","counted":1499500,"expected":1499500}'));
select zz.put('C6', zz.mc('U_DIR', 'main', '2027-01'));
select zz.chk('C6 oddiy yopilgandan keyin: yopilmagan kun yo''q; INV — oxirgi kun oddiy yopilgan (warn), invDays [28]; ready, canLock (Direktor)',
  (zz.js(zz.get('C5')) -> 'day' ->> 'status') || '/' || zz.lv(zz.get('C6'), 'days_open') || '/' || zz.lv(zz.get('C6'), 'inv') || '/' || (zz.item(zz.get('C6'), 'inv') ->> 'lastDay') || '/' ||
  (zz.item(zz.get('C6'), 'inv') ->> 'kind') || '/' || (zz.item(zz.get('C6'), 'inv') ->> 'invDays') || '/' || (zz.js(zz.get('C6')) ->> 'ready') || '/' || (zz.js(zz.get('C6')) ->> 'canLock'),
  '^closed/ok/0/warn/1/2027-01-29/close/\["2027-01-28"\]/true/true$');
select zz.chk('C6b tekshirilmagan kunlar va qarorsiz kamomad — warn; buxgalterda canLock yo''q',
  zz.lv(zz.get('C6'), 'unverified') || '/' || (zz.item(zz.get('C6'), 'unverified') ->> 'days') || '/' || zz.lv(zz.get('C6'), 'shortages') || '/' || (zz.item(zz.get('C6'), 'shortages') ->> 'sum') || '/' ||
  (zz.js(zz.mc('U_ACC', 'main', '2027-01')) ->> 'canLock') || '/' || (zz.js(zz.get('C6')) ->> 'warnings'),
  '^warn/2/\["2027-01-28", "2027-01-29"\]/warn/1/1000/false/3$');
select zz.chk('C6c nazorat ro''yxati: invMissing — 2027-01 (oxirgi kun 29)',
  zz.js(zz.as('U_ACC', $q$select public.kassa_checks('main')::text$q$)) ->> 'invMissing', '^\[\{"month": "2027-01", "lastDay": "2027-01-29"\}\]$');
select zz.put('C7', zz.as('U_DIR', $q$select public.kassa_day_reopen('main', '2027-01-29', 'Oylik inventarizatsiya o''tkazilmagan')::text$q$));
select zz.chk('C7 Direktor 29-yanvarni qayta ochdi — yana block (ochiq kun)',
  coalesce(zz.js(zz.get('C7')) -> 'day' ->> 'status', zz.get('C7')) || '/' ||
  zz.lv(zz.mc('U_DIR', 'main', '2027-01'), 'days_open') || '/' || (select coalesce(app.kassa_day_json(d.id) ->> 'invKind', 'null') from public.cash_days d where d.desk = 'main' and d.day = '2027-01-29'),
  '^open/block/1/null$');
select zz.chk('C7b Direktor kassir o''rniga yopadi: inventarizatsiyada komissiya — 2 kishidan kam rad',
  zz.rpc('U_DIR', 'kassa_day_close', '{"day":"2027-01-29","counted":1499500,"expected":1499500,"inv":true,"commission":[{"title":"Rais","name":"Sinov Direktor"}]}'), '^ERR 22023 \[kassa:commission\]');
select zz.put('C8', zz.rpc('U_DIR', 'kassa_day_close', format('{"day":"2027-01-29","counted":1499500,"expected":1499500,"inv":true,"commission":%s,"blanks":{"count":36,"nos":"0015-0050"}}', zz.comm3())));
select zz.put('C8m', zz.mc('U_DIR', 'main', '2027-01'));
select zz.chk('C8 komissiya bilan qayta yopildi: INV joyida (oxirgi yopish sanashi — monthly), countId, invDays [28, 29]; invMissing bo''sh',
  (zz.js(zz.get('C8')) -> 'day' ->> 'invKind') || '/' || zz.lv(zz.get('C8m'), 'inv') || '/' ||
  ((zz.item(zz.get('C8m'), 'inv') ->> 'countId') = (select n.id from zz.cnt('2027-01-29', array['monthly']) n))::text || '/' ||
  (zz.item(zz.get('C8m'), 'inv') ->> 'invDays') || '/' || (zz.js(zz.as('U_ACC', $q$select public.kassa_checks('main')::text$q$)) ->> 'invMissing'),
  '^monthly/ok/0/true/\["2027-01-28", "2027-01-29"\]/\[\]$');
select zz.put('C9c', zz.as('U_DIR', format('select public.kassa_shortage_decide(%L, %L, %L)::text', (select c.id from public.cash_docs c where c.op = 'out_shortage' and c.status = 'posted'), 'writeoff', 'Aybdor aniqlanmadi')));
select zz.put('C9a', zz.as('U_ACC', $q$select public.kassa_day_verify('main', '2027-01-28', true, 'Qog''ozlar olindi')::text$q$));
select zz.put('C9b', zz.as('U_ACC', $q$select public.kassa_day_verify('main', '2027-01-29', true, 'Qog''ozlar olindi')::text$q$));
select zz.put('C9', zz.mc('U_DIR', 'main', '2027-01'));
select zz.chk('C9 kamomad qarori, kunlar tekshirildi — shortages va unverified joyida, ogohlantirish yo''q',
  coalesce(zz.js(zz.get('C9c')) ->> 'ok', zz.get('C9c')) || '/' || coalesce(zz.js(zz.get('C9a')) ->> 'ok', zz.get('C9a')) || '/' || coalesce(zz.js(zz.get('C9b')) ->> 'ok', zz.get('C9b')) || '/' ||
  zz.lv(zz.get('C9'), 'unverified') || '/' || zz.lv(zz.get('C9'), 'shortages') || '/' || (zz.js(zz.get('C9')) ->> 'warnings'),
  '^true/true/true/ok/0/ok/0/0$');
-- biriktirilmagan tushum (yanvar — hisobga olinadi, fevral — yo'q) va vedomost (tasdiqlangan, qisman to'langan)
set local session_replication_role = replica;
insert into public.payments (id, provider, amount, status, raw, "createdAt") values
  ('pu1', 'click', 50000, 'unmatched', '{}', '2027-01-20 12:00+05'), ('pu2', 'click', 70000, 'unmatched', '{}', '2027-02-01 08:00+05');
insert into public.payroll_runs (id, status) values ('2027-01', 'approved');
insert into public.payroll_lines (id, "runId", "personType", "personId", name, payable) values ('2027-01__teacher__IQT-T1', '2027-01', 'teacher', 'IQT-T1', 'Sinov O''qituvchi', 1000000);
insert into public.salary_payments (id, "teacherId", "teacherName", month, paid, net) values ('spx', 'IQT-T1', 'Sinov O''qituvchi', '2027-01', 400000, 400000);
set local session_replication_role = origin;
select zz.put('C10', zz.mc('U_ACC', 'main', '2027-01'));
select zz.chk('C10 biriktirilmagan tushum (faqat yanvarniki) — warn 50 000; vedomost tasdiqlangan, to''lanmagan 600 000 — info',
  zz.lv(zz.get('C10'), 'unmatched') || '/' || (zz.item(zz.get('C10'), 'unmatched') ->> 'sum') || '/' || zz.lv(zz.get('C10'), 'payroll') || '/' ||
  (zz.item(zz.get('C10'), 'payroll') ->> 'run') || '/' || (zz.item(zz.get('C10'), 'payroll') ->> 'sum') || '/' || zz.lv(zz.get('C10'), 'snapshot') || '/' || zz.lv(zz.get('C10'), 'lock'),
  '^warn/1/50000/info/1/approved/600000/info/0/info/0$');
select zz.put('C11s', zz.rpc('U_DIR', 'fin_snapshot_take', '{"asOf":"2027-01-31","lock":true,"note":"Yanvar yakuni"}'));
select zz.put('C11', zz.mc('U_DIR', 'main', '2027-01'));
select zz.chk('C11 oy oxiri surati va qulf: snapshot va lock joyida, locked, canLock yo''q (yopilgan), ready',
  zz.lv(zz.get('C11'), 'snapshot') || '/' || (zz.item(zz.get('C11'), 'snapshot') -> 'snapshot' ->> 'id') || '/' || zz.lv(zz.get('C11'), 'lock') || '/' ||
  (zz.js(zz.get('C11')) ->> 'locked') || '/' || (zz.js(zz.get('C11')) ->> 'canLock') || '/' || (zz.js(zz.get('C11')) ->> 'ready') || '/' || (zz.js(zz.get('C11')) ->> 'lockedThrough'),
  '^ok/1/fs_20270131_1/ok/1/true/false/true/2027-01-31$');
select zz.chk('C12 sinov kassasi: pul jadvallari bandlarisiz, block yo''q, canLock yo''q',
  (zz.js(zz.mc('U_DIR', 'sinov', '2027-01')) ->> 'isTest') || '/' ||
  (select string_agg(i ->> 'code', ',' order by o) from jsonb_array_elements(zz.js(zz.mc('U_DIR', 'sinov', '2027-01')) -> 'items') with ordinality t(i, o)) || '/' ||
  (zz.js(zz.mc('U_DIR', 'sinov', '2027-01')) ->> 'canLock'),
  '^true/days_open,days_pending,unverified,inv,shortages,fixes,advances,advPending,limit,refunds/false$');
select zz.chk('C13 joriy oy (tugamagan): ended yo''q, canLock yo''q, INV — info',
  (zz.js(zz.mc('U_DIR', 'main', '2027-02')) ->> 'ended') || '/' || (zz.js(zz.mc('U_DIR', 'main', '2027-02')) ->> 'canLock') || '/' || zz.lv(zz.mc('U_DIR', 'main', '2027-02'), 'inv'),
  '^false/false/info/0$');
select zz.put('r4', zz.rpc('U_KAS', 'kassa_receipt', format('{"op":"in_bank","amount":10000,"partyType":"bank","partyId":"%s","basis":"Chek 004","clientRef":"inv-r4-0001"}', zz.js(zz.get('cp_bank')) ->> 'id')));
select zz.chk('C14 joriy oyning bugungi ochiq kuni — info (block emas)', zz.lv(zz.mc('U_DIR', 'main', '2027-02'), 'days_open'), '^info/1$');
select zz.put('C15', zz.rpc('U_KAS', 'kassa_day_close', '{"day":"2027-02-01","counted":1509500,"expected":1509500}'));
select zz.chk('C15 joriy oy, oddiy yopilgan kun: INV — info (oy tugamagan), lastDay; invMissing — joriy oy kirmaydi',
  zz.lv(zz.mc('U_DIR', 'main', '2027-02'), 'inv') || '/' || (zz.item(zz.mc('U_DIR', 'main', '2027-02'), 'inv') ->> 'lastDay') || '/' ||
  (zz.js(zz.as('U_ACC', $q$select public.kassa_checks('main')::text$q$)) ->> 'invMissing'), '^info/1/2027-02-01/\[\]$');

-- ---------- (D) dekabr — yillik inventarizatsiya ----------
select zz.clock('2027-12-30 10:00+05');
select zz.put('r3', zz.rpc('U_KAS', 'kassa_receipt', format('{"op":"in_bank","amount":100000,"partyType":"bank","partyId":"%s","basis":"Chek 003","clientRef":"inv-r3-0001"}', zz.js(zz.get('cp_bank')) ->> 'id')));
select zz.put('D1', zz.rpc('U_KAS', 'kassa_day_close', format('{"day":"2027-12-30","counted":1609500,"expected":1609500,"inv":true,"commission":%s,"blanks":{"count":0}}', zz.comm3())));
select zz.chk('D1 dekabrda — yillik (yearly), farqsiz (hujjat yo''q), invKind yearly',
  (zz.js(zz.get('D1')) -> 'day' ->> 'invKind') || '/' || (select n.kind || '/' || coalesce(n."diffDocId", '-') || '/' || (n.blanks ->> 'count') from zz.cnt('2027-12-30', array['close','monthly','yearly']) n),
  '^yearly/yearly/-/0$');
select zz.chk('D2 oddiy yopish — belgisiz (close), blankalar yo''q (A — boshqa kunlar o''zgarmagan)',
  (select string_agg(n.kind || ':' || coalesce(n.blanks ->> 'count', '-'), ',' order by n.at) from public.cash_counts n where n.kind in ('close', 'monthly', 'yearly')),
  '^monthly:38,monthly:37,close:-,monthly:36,close:-,yearly:0$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else E'\n      olindi: ' || coalesce(got, '<null>') || E'\n      kutildi: ' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || case when bool_and(ok) then ' o''tdi' else ' — XATO BOR' end from zz.res;
rollback;
