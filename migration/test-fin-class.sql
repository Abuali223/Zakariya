-- =====================================================================
-- test-fin-class.sql — moliya ish rejasi 2-bosqichi, F2.3 (reliz 27) sinovi: fin-class.sql — noyabr–yanvar eski xarajatlariga statiya.
--   (A) ro'yxat: kim ko'radi, oy doirasi, qatorlar (hozirgi statiya — yozuvdagi yoki toifadan), doiradan tashqari yozuvlar (hujjatli,
--       kassa hujjatli, maosh hisobi qatori, boshqa oylar) yo'q, tanlanadigan statiyalar;
--   (B) tasnif: huquq, kirish tekshiruvlari, doira va statiya qoidalari, «Boshqa» — izoh, tasdiqlash / o'zgartirish / takror / faqat izoh,
--       bitta tranzaksiya (biror qator xato — hech biri), o'zgarishlar tarixi, detektor jurnalsiz, jadvalga to'g'ridan-to'g'ri yozuv yo'q,
--       yopilgan davr;
--   (C) imzo: faqat buxgalter, hammasi tasdiqlanmaguncha — yo'q, takror — dup, keyin tasnif yoki summa o'zgarsa — eskirgan, qayta imzo;
--   (D) RP-09 (fin_matrix): «taxminiy» belgisi tasdiqdan, oylar holati («classify»).
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-fin-class.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.expenses) then
    raise exception 'test-fin-class.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
create or replace function zz.try(p_q text) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  if p_q ~* '^\s*(select|with)\M' then execute p_q into r; else execute p_q; end if;
  return coalesce(r, 'OK');
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  return 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
end $$;
-- xato satridan faqat «ERR holat [hint]» qismi (xabar matni — sinovda emas)
create or replace function zz.eh(p text) returns text language sql as $$
  select case when p like 'ERR %' then coalesce(substring(p from '^ERR [0-9A-Z]+ \[[^]]*\]'), p) else p end $$;
create or replace function zz.js(p text) returns jsonb language plpgsql as $$
begin return p::jsonb; exception when others then return null; end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
-- Holat o'qiydigan yordamchilar — plpgsql: bir ifodada oldinroq bajarilgan amalni ham ko'radi
create or replace function zz.cls(p_uid text, p_items text) returns text language plpgsql as $$
begin return zz.as(p_uid, format('select public.fin_exp_classify(%L::jsonb)::text', p_items)); end $$;
create or replace function zz.res1(p text) returns text language plpgsql as $$   -- natija qisqa: ok/changed/confirmed/unchanged yoki xato
declare j jsonb := zz.js(p);
begin
  if j is null then return left(p, 220); end if;
  return coalesce(j ->> 'ok', '-') || ':' || coalesce(j ->> 'changed', '-') || ':' || coalesce(j ->> 'confirmed', '-') || ':' || coalesce(j ->> 'unchanged', '-');
end $$;
create or replace function zz.art(p_id text) returns text language plpgsql as $$
begin return (select coalesce(e."articleId", '<null>') from public.expenses e where e.id = p_id); end $$;
create or replace function zz.nj(p_id text) returns bigint language plpgsql as $$
begin return (select count(*) from public.fin_exp_class c where c."expenseId" = p_id); end $$;
create or replace function zz.jlast(p_id text) returns text language plpgsql as $$
begin return (select coalesce(c."oldArticle", '<null>') || '>' || c."newArticle" || ':' || c."byRole" || ':' || c.note
                from public.fin_exp_class c where c."expenseId" = p_id order by c.id desc limit 1); end $$;
create or replace function zz.lst(p_uid text, p_m text) returns jsonb language plpgsql as $$
begin return zz.js(zz.as(p_uid, format('select public.fin_exp_class_list(%L)::text', p_m))); end $$;
create or replace function zz.row(p_uid text, p_m text, p_id text) returns jsonb language plpgsql as $$
begin return (select r from jsonb_array_elements(zz.lst(p_uid, p_m) -> 'rows') r where r ->> 'id' = p_id); end $$;
create or replace function zz.st(p_m text) returns jsonb language plpgsql as $$
begin return app.fin_class_stats(array[p_m]) -> 0; end $$;
create or replace function zz.sg(p_m text) returns text language plpgsql as $$   -- imzo holati: yo'q / valid / stale
declare j jsonb := zz.st(p_m);
begin return case when j -> 'sign' is null or jsonb_typeof(j -> 'sign') = 'null' then 'yoq' when (j #>> '{sign,valid}')::boolean then 'valid' else 'stale' end; end $$;
create or replace function zz.mx() returns jsonb language plpgsql as $$
begin return zz.js(zz.as('U_DIR', $q$select public.fin_matrix('school', 2026)::text$q$)); end $$;
create or replace function zz.fl(j jsonb, p_art text) returns text language sql as $$
  select coalesce((select r ->> 'approx' from jsonb_array_elements(j -> 'rows') r where r ->> 'dir' = 'out' and coalesce(r ->> 'articleId', '-') = p_art), 'yoq') $$;
create or replace function zz.chlog(p_id text, p_uid text) returns bigint language plpgsql as $$
begin return (select count(*) from public.change_log c where c.tbl = 'expenses' and c.changes ? 'articleId' and c.actor_uid = p_uid); end $$;

-- ---------- Urug' ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]'), ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'),
  ('U_TRS','g@x','Sinov G''aznachi','treasurer','active','[]'), ('U_HR','h@x','Sinov Kadrchi','hr','active','[]'),
  ('U_MKT','m@x','Sinov Marketolog','marketing_mgr','active','[]'), ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
-- doiradan tashqari: xarajat hujjatiga va kassa hujjatiga bog'langan qatorlar (triggerlarsiz — havolani faqat funksiyalar qo'yadi)
insert into public.expenses (id, date, month, category, amount, note, method, "articleId", "expDocId", "cashDocId") values
  ('zz-x1', '2026-11-12', '2026-11', 'Ijara', 200000, 'Sinov', 'bank', 'EX-10', 'xd_zz1', null),
  ('zz-k1', '2026-12-07', '2026-12', 'Kanselyariya', 15000, 'Sinov', 'cash', 'EX-32', null, 'zz_kd1'),
  ('zz-j1', '2027-01-10', '2027-01', 'Ijara', 300000, 'Sinov', 'bank', 'EX-10', 'xd_zz2', null);
set local session_replication_role = origin;
select zz.clock('2027-01-20 10:00+05');
-- eski yozuvlar triggerlar bilan (psql — sahifadagi eski shakl o'rnida): statiya toifadan qo'yiladi (fin_category_map)
insert into public.expenses (id, date, month, category, amount, note) values
  ('zz-n1', '2026-11-05', '2026-11', 'Boshqa', 120000, 'Sinov xarid'), ('zz-n2', '2026-11-10', '2026-11', 'Kommunal', 300000, 'Sinov'),
  ('zz-n3', '2026-11-20', '2026-11', 'Kanselyariya', 50000, 'Sinov'), ('zz-n4', '2026-11-28', '2026-11', 'Noma''lum toifa', 25000, 'Sinov'),
  ('zz-o1', '2026-10-25', '2026-10', 'Hayriya', 40000, 'Sinov'), ('zz-f1', '2027-02-02', '2027-02', 'Boshqa', 10000, 'Sinov');
insert into public.expenses (id, date, month, category, amount, note, method) values
  ('zz-d1', '2026-12-03', '2026-12', 'Ijara', 1000000, 'Sinov', 'bank'), ('zz-d2', '2026-12-15', null, 'Marketing', 80000, 'Sinov', 'bank');
insert into public.expenses (id, date, month, category, amount, note) values ('payroll__2026-11', '2026-11-01', '2026-11', 'Maosh', 900000, 'Sinov');
update public.fin_articles set active = false where id = 'EX-37';   -- faol bo'lmagan statiya sinovi uchun (ROLLBACK)

-- ---------- (A) ro'yxat ----------
select zz.chk('A1 buxgalter: noyabr ro''yxati — 4 ta eski yozuv (sana bo''yicha), 3 ta tasnif oyi, imzo huquqi bor',
  (select (j ->> 'ok') || ':' || jsonb_array_length(j -> 'rows') || ':' || (select string_agg(r ->> 'id', ',') from jsonb_array_elements(j -> 'rows') r)
          || ':' || jsonb_array_length(j -> 'months') || ':' || (j ->> 'canSign') from zz.lst('U_ACC', '2026-11') j),
  '^true:4:zz-n1,zz-n2,zz-n3,zz-n4:3:true$');
select zz.chk('A2 Moliya menejeri va Direktor ko''radi (imzo huquqisiz)',
  (zz.lst('U_FM', '2026-11') ->> 'canSign') || ':' || jsonb_array_length(zz.lst('U_FM', '2026-11') -> 'rows') || ' | '
  || (zz.lst('U_DIR', '2026-12') ->> 'canSign') || ':' || jsonb_array_length(zz.lst('U_DIR', '2026-12') -> 'rows'),
  '^false:4 \| false:2$');
select zz.chk('A3 kassir, g''aznachi, HR, marketing, o''qituvchi va mehmon — rad (42501)',
  (select string_agg(left(zz.as(u, $q$select public.fin_exp_class_list('2026-11')::text$q$), 9), ',' order by u)
     from unnest(array['U_HR', 'U_KAS', 'U_MKT', 'U_TCH', 'U_TRS']) u) || ' | ' || left(zz.as(null, $q$select public.fin_exp_class_list('2026-11')::text$q$), 9),
  '^ERR 42501,ERR 42501,ERR 42501,ERR 42501,ERR 42501 \| ERR 42501$');
select zz.chk('A4 oy tasnif davridan tashqarida yoki bo''sh — 22023 (fin:class_month)',
  left(zz.as('U_ACC', $q$select public.fin_exp_class_list('2026-10')::text$q$), 30) || ' | ' || left(zz.as('U_ACC', $q$select public.fin_exp_class_list(null)::text$q$), 30),
  '^ERR 22023 \[fin:class_month\].* \| ERR 22023 \[fin:class_month\]');
select zz.chk('A5 qator: hozirgi statiya toifadan («Boshqa» → EX-49), tasdiqlanmagan, jurnalsiz; toifasi noma''lum — statiyasiz',
  (select (r ->> 'articleId') || ':' || (r ->> 'mapArticle') || ':' || (r ->> 'confirmed') || ':' || coalesce(r ->> 'last', 'null') || ':' || (r ->> 'locked')
     from zz.row('U_ACC', '2026-11', 'zz-n1') r)
  || ' | ' || coalesce((select coalesce(r ->> 'articleId', 'null') || ':' || (r ->> 'confirmed') from zz.row('U_ACC', '2026-11', 'zz-n4') r), 'yoq'),
  '^EX-49:EX-49:false:null:false \| null:false$');
select zz.chk('A6 doiradan tashqari: xarajat hujjatli, kassa hujjatli, maosh hisobi qatori, oktyabr va fevral — hech bir oyda yo''q; dekabr — oy bo''sh bo''lsa sanadan',
  (select coalesce(string_agg(r ->> 'id', ',' order by r ->> 'id'), '-') from unnest(array['2026-11', '2026-12', '2027-01']) m, jsonb_array_elements(zz.lst('U_ACC', m) -> 'rows') r
    where r ->> 'id' in ('zz-x1', 'zz-k1', 'zz-j1', 'payroll__2026-11', 'zz-o1', 'zz-f1'))
  || ' | ' || (select string_agg(r ->> 'id', ',' order by r ->> 'id') from jsonb_array_elements(zz.lst('U_ACC', '2026-12') -> 'rows') r)
  || ' | ' || jsonb_array_length(zz.lst('U_ACC', '2027-01') -> 'rows'),
  '^- \| zz-d1,zz-d2 \| 0$');
select zz.chk('A7 tanlanadigan statiyalar: xarajat va operatsiya; IN, EX-44 / 45 / 47, OP-23 va faol bo''lmagani — yo''q; «Boshqa» — izoh majburiy',
  (select string_agg(x, ',') from (select case when exists (select 1 from jsonb_array_elements(zz.lst('U_ACC', '2026-11') -> 'articles') a where a ->> 'id' = k) then k || '+' else k || '-' end as x
                                     from unnest(array['EX-16', 'OP-09', 'OP-02', 'IN-01', 'EX-44', 'EX-45', 'EX-47', 'OP-23', 'EX-37']) with ordinality u(k, o) order by o) t)
  || ' | ' || (select a ->> 'needsNote' from jsonb_array_elements(zz.lst('U_ACC', '2026-11') -> 'articles') a where a ->> 'id' = 'EX-49'),
  '^EX-16\+,OP-09\+,OP-02\+,IN-01-,EX-44-,EX-45-,EX-47-,OP-23-,EX-37- \| true$');

-- ---------- (B) tasnif ----------
select zz.chk('B1 kassir, g''aznachi, HR, marketing, o''qituvchi, mehmon — rad (42501)',
  (select string_agg(left(zz.cls(u, '[{"id":"zz-n1","articleId":"EX-49","note":"Sinov"}]'), 9), ',' order by u) from unnest(array['U_HR', 'U_KAS', 'U_MKT', 'U_TCH', 'U_TRS']) u)
  || ' | ' || left(zz.cls(null, '[{"id":"zz-n1","articleId":"EX-49","note":"Sinov"}]'), 9) || ' | ' || zz.nj('zz-n1'),
  '^ERR 42501,ERR 42501,ERR 42501,ERR 42501,ERR 42501 \| ERR 42501 \| 0$');
select zz.chk('B2 kirish: bo''sh / massiv emas / qator obyekt emas / id yoki statiyasiz / bitta xarajat ikki marta — 22023 (fin:bad_input)',
  (select string_agg(zz.eh(zz.cls('U_ACC', x)), ',' order by o) from unnest(array['[]', '{}', '[1]', '[{"id":"zz-n1"}]',
     '[{"id":"zz-n3","articleId":"EX-32"},{"id":"zz-n3","articleId":"EX-32"}]']) with ordinality u(x, o)) || ' | ' || zz.nj('zz-n3'),
  '^(ERR 22023 \[fin:bad_input\],){4}ERR 22023 \[fin:bad_input\] \| 0$');
select zz.chk('B3 doira: hujjatli, kassa hujjatli, maosh hisobi qatori, oktyabr — 22023 (fin:class_scope, sababi bilan); yo''q xarajat — fin:class_missing',
  zz.cls('U_ACC', '[{"id":"zz-x1","articleId":"EX-10"}]') || ' # ' || zz.cls('U_ACC', '[{"id":"zz-k1","articleId":"EX-32"}]') || ' # '
  || zz.cls('U_ACC', '[{"id":"payroll__2026-11","articleId":"OP-09"}]') || ' # ' || zz.cls('U_ACC', '[{"id":"zz-o1","articleId":"EX-42"}]') || ' # '
  || left(zz.cls('U_ACC', '[{"id":"zz-yoq","articleId":"EX-42"}]'), 32),
  '^ERR 22023 \[fin:class_scope\].*hujjat bilan kiritilgan.* # ERR 22023 \[fin:class_scope\].*kassa hujjatidan.* # ERR 22023 \[fin:class_scope\].*maosh hisobi.* # ERR 22023 \[fin:class_scope\].*oyi 2026-10, tasnif davri — 2026-11, 2026-12, 2027-01 # ERR 22023 \[fin:class_missing\]');
select zz.chk('B4 statiya: IN-01, EX-44, OP-23, faol bo''lmagan, mavjud bo''lmagan — 22023 (fin:class_article); yozuv o''zgarmaydi',
  (select string_agg(zz.eh(zz.cls('U_ACC', format('[{"id":"zz-n3","articleId":"%s","note":"Sinov izoh"}]', a))), ',' order by o)
     from unnest(array['IN-01', 'EX-44', 'OP-23', 'EX-37', 'ZZ-99']) with ordinality u(a, o)) || ' | ' || zz.art('zz-n3') || ':' || zz.nj('zz-n3'),
  '^(ERR 22023 \[fin:class_article\],){4}ERR 22023 \[fin:class_article\] \| EX-32:0$');
select zz.chk('B5 «Boshqa» (EX-49): izohsiz — rad (fin:class_note); izoh bilan — toifadagi statiya tasdiqlandi (yozuv o''zgarmadi, jurnalda)',
  zz.eh(zz.cls('U_ACC', '[{"id":"zz-n1","articleId":"EX-49","note":" "}]')) || ' | '
  || zz.res1(zz.cls('U_ACC', '[{"id":"zz-n1","articleId":"EX-49","note":"Turli mayda xarid"}]')) || ' | ' || zz.art('zz-n1') || ':' || zz.nj('zz-n1') || ':' || zz.jlast('zz-n1'),
  '^ERR 22023 \[fin:class_note\] \| true:0:1:0 \| EX-49:1:EX-49>EX-49:accountant:Turli mayda xarid$');
select zz.chk('B6 o''zgartirish (EX-11 → EX-13): yozuvda yangi statiya, jurnalda eski → yangi, o''zgarishlar tarixida (buxgalter nomidan)',
  zz.res1(zz.cls('U_ACC', '[{"id":"zz-n2","articleId":"EX-13"}]')) || ' | ' || zz.art('zz-n2') || ':' || zz.jlast('zz-n2') || ':' || zz.chlog('zz-n2', 'U_ACC'),
  '^true:1:0:0 \| EX-13:EX-11>EX-13:accountant::1$');
select zz.chk('B7 takror (o''sha statiya va izoh) — o''zgarishsiz, yangi jurnal yozuvi yo''q; faqat izoh o''zgarsa — tasdiq sifatida yoziladi',
  zz.res1(zz.cls('U_ACC', '[{"id":"zz-n2","articleId":"EX-13"}]')) || ':' || zz.nj('zz-n2') || ' | '
  || zz.res1(zz.cls('U_ACC', '[{"id":"zz-n2","articleId":"EX-13","note":"Suv hisobi"}]')) || ':' || zz.nj('zz-n2'),
  '^true:0:0:1:1 \| true:0:1:0:2$');
select zz.chk('B8 bitta tranzaksiya: ro''yxatdagi bitta yozuv xato bo''lsa — boshqalari ham yozilmaydi',
  zz.eh(zz.cls('U_ACC', '[{"id":"zz-n3","articleId":"EX-32"},{"id":"zz-o1","articleId":"EX-42"}]')) || ' | ' || zz.nj('zz-n3'),
  '^ERR 22023 \[fin:class_scope\] \| 0$');
select zz.chk('B9 statiyasiz yozuv (toifa noma''lum) — Moliya menejeri statiya qo''ydi; Direktor toifadagini tasdiqladi; bir chaqiruvda ikki yozuv',
  zz.res1(zz.cls('U_FM', '[{"id":"zz-n4","articleId":"EX-16"}]')) || ':' || zz.art('zz-n4') || ':' || zz.jlast('zz-n4') || ' | '
  || zz.res1(zz.cls('U_DIR', '[{"id":"zz-n3","articleId":"EX-32"},{"id":"zz-d2","articleId":"EX-39"}]')) || ':' || zz.jlast('zz-n3') || ':' || zz.art('zz-d2'),
  '^true:1:0:0:EX-16:<null>>EX-16:finance_mgr: \| true:1:1:0:EX-32>EX-32:director::EX-39$');
select zz.chk('B10 ro''yxatda: tasdiqlangan, oxirgi tasnif (kim — ism, izoh)',
  (select (r ->> 'confirmed') || ':' || (r #>> '{last,by}') || ':' || (r #>> '{last,note}') from zz.row('U_FM', '2026-11', 'zz-n1') r),
  '^true:Sinov Buxgalter:Turli mayda xarid$');
select zz.chk('B11 pul jadvaliga yozgan bo''lsa ham to''g''ridan-to''g''ri yozuv detektori jurnalsiz (funksiya bayroqli)',
  (select count(*)::text from public.fin_direct_log), '^0$');
select zz.chk('B12 jadvallar: sahifa (authenticated) yozolmaydi; psql ham faqat funksiya orqali; o''zgartirish va o''chirish — hech kimga',
  left(zz.as('U_ACC', $q$insert into public.fin_exp_class ("expenseId", month, "newArticle", "byUid") values ('zz-n3', '2026-11', 'EX-32', 'U_ACC') returning 1$q$), 9) || ' | '
  || left(zz.as('U_ACC', $q$insert into public.fin_exp_class_sign (month, n, total, "byUid") values ('2026-11', 1, 1, 'U_ACC') returning 1$q$), 9) || ' | '
  || zz.eh(zz.try($q$insert into public.fin_exp_class ("expenseId", month, "newArticle", "byUid") values ('zz-n3', '2026-11', 'EX-32', 'x')$q$)) || ' | '
  || zz.eh(zz.try($q$update public.fin_exp_class set note = 'x' where "expenseId" = 'zz-n1'$q$)) || ' | '
  || zz.eh(zz.try($q$delete from public.fin_exp_class where "expenseId" = 'zz-n1'$q$)),
  '^ERR 42501 \| ERR 42501 \| ERR 42501 \[fin:class_rpc_only\] \| ERR 42501 \[fin:class_immutable\] \| ERR 42501 \[fin:class_immutable\]$');
select zz.chk('B13 o''qish: buxgalter, Moliya menejeri, Direktor — jurnalni ko''radi; kassir — yo''q (0 qator)',
  zz.as('U_ACC', $q$select count(*)::text from public.fin_exp_class$q$) || ':' || zz.as('U_FM', $q$select count(*)::text from public.fin_exp_class$q$) || ':'
  || zz.as('U_DIR', $q$select count(*)::text from public.fin_exp_class$q$) || ':' || zz.as('U_KAS', $q$select count(*)::text from public.fin_exp_class$q$),
  '^6:6:6:0$');
select zz.chk('B14 yopilgan davr: noyabr yozuvi — rad (fin:locked): statiya o''zgarishi ham, faqat tasdiq / izoh ham (jurnal yozilmaydi); ro''yxatda «locked»; dekabr — ochiq',
  zz.try($q$update public.fin_org set "lockedThrough" = '2026-11-30' where id = 'main'$q$) || ' | '
  || zz.eh(zz.cls('U_ACC', '[{"id":"zz-n2","articleId":"EX-12"}]')) || ':' || zz.art('zz-n2') || ' | '
  || zz.eh(zz.cls('U_ACC', '[{"id":"zz-n1","articleId":"EX-49","note":"Yopilgan davrda izoh"}]')) || ':' || zz.nj('zz-n1') || ' | '
  || (select r ->> 'locked' from zz.row('U_ACC', '2026-11', 'zz-n2') r) || ':' || (select r ->> 'locked' from zz.row('U_ACC', '2026-12', 'zz-d1') r) || ' | '
  || zz.res1(zz.cls('U_ACC', '[{"id":"zz-d1","articleId":"EX-10"}]')) || ' | '
  || zz.try($q$update public.fin_org set "lockedThrough" = null where id = 'main'$q$),
  '^OK \| ERR 42501 \[fin:locked\]:EX-13 \| ERR 42501 \[fin:locked\]:1 \| true:false \| true:0:1:0 \| OK$');

-- ---------- (C) imzo ----------
select zz.chk('C1 faqat buxgalter: Moliya menejeri, Direktor — 42501; noto''g''ri oy — 22023',
  left(zz.as('U_FM', $q$select public.fin_exp_class_sign('2026-11')::text$q$), 9) || ':' || left(zz.as('U_DIR', $q$select public.fin_exp_class_sign('2026-11')::text$q$), 9)
  || ':' || zz.eh(zz.as('U_ACC', $q$select public.fin_exp_class_sign('2026-10')::text$q$)),
  '^ERR 42501:ERR 42501:ERR 22023 \[fin:class_month\]$');
select zz.chk('C2 hammasi tasdiqlanmagan oy (dekabrga yangi eski yozuv qo''shildi: 3 tadan 1 tasi qoldi) — rad, soni bilan; yozuvsiz oy (yanvar) — fin:class_empty',
  zz.try($q$insert into public.expenses (id, date, month, category, amount, note) values ('zz-d3', '2026-12-20', '2026-12', 'Kanselyariya', 7000, 'Sinov')$q$) || ' | '
  || zz.as('U_ACC', $q$select public.fin_exp_class_sign('2026-12')::text$q$) || ' | ' || zz.eh(zz.as('U_ACC', $q$select public.fin_exp_class_sign('2027-01')::text$q$)),
  '^OK \| ERR 22023 \[fin:class_open\] .*3 tadan 1 tasi qoldi \| ERR 22023 \[fin:class_empty\]$');
select zz.chk('C3 noyabr: 4 yozuv tasdiqlangan — imzolandi (soni, jami); holat — amaldagi imzo (kim — ism)',
  (select (x ->> 'n') || ':' || (x ->> 'total') from zz.js(zz.as('U_ACC', $q$select public.fin_exp_class_sign('2026-11')::text$q$)) x) || ' | '
  || zz.sg('2026-11') || ':' || (zz.st('2026-11') #>> '{sign,by}') || ':' || (zz.st('2026-11') ->> 'confirmed') || '/' || (zz.st('2026-11') ->> 'n'),
  '^4:495000 \| valid:Sinov Buxgalter:4/4$');
select zz.chk('C4 takror imzo — dup (yangi imzo yozuvi yo''q)',
  (zz.js(zz.as('U_ACC', $q$select public.fin_exp_class_sign('2026-11')::text$q$)) ->> 'dup') || ':' || (select count(*) from public.fin_exp_class_sign where month = '2026-11'),
  '^true:1$');
select zz.chk('C5 imzodan keyin tasnif o''zgardi — imzo eskirdi; buxgalter qayta imzoladi — amaldagi',
  zz.res1(zz.cls('U_FM', '[{"id":"zz-n3","articleId":"EX-26"}]')) || ':' || zz.sg('2026-11') || ' | '
  || (zz.js(zz.as('U_ACC', $q$select public.fin_exp_class_sign('2026-11')::text$q$)) ->> 'ok') || ':' || zz.sg('2026-11'),
  '^true:1:0:0:stale \| true:valid$');
select zz.chk('C6 imzodan keyin eski yozuv summasi o''zgardi (yoki yozuv qo''shildi) — imzo eskiradi',
  zz.try($q$update public.expenses set amount = 310000 where id = 'zz-n2'$q$) || ':' || zz.sg('2026-11') || ' | '
  || zz.try($q$update public.expenses set amount = 300000 where id = 'zz-n2'$q$) || ':' || zz.sg('2026-11') || ' | '
  || zz.try($q$insert into public.expenses (id, date, month, category, amount, note) values ('zz-n5', '2026-11-29', '2026-11', 'Kanselyariya', 1000, 'Sinov')$q$)
  || ':' || zz.sg('2026-11') || ':' || (zz.st('2026-11') ->> 'confirmed') || '/' || (zz.st('2026-11') ->> 'n'),
  '^OK:stale \| OK:valid \| OK:stale:4/5$');

select zz.chk('C7 imzodan keyin statiya funksiyasiz o''zgardi (yozuv tasdig''i tushadi) yoki 0 so''mlik yozuv qo''shildi (summa o''sha) — imzo eskiradi; tasdiq qaytsa — amaldagi',
  zz.res1(zz.cls('U_ACC', '[{"id":"zz-n5","articleId":"EX-32"}]')) || ':' || (zz.js(zz.as('U_ACC', $q$select public.fin_exp_class_sign('2026-11')::text$q$)) ->> 'ok') || ':' || zz.sg('2026-11') || ' | '
  || zz.try($q$update public.expenses set "articleId" = 'EX-12' where id = 'zz-n2'$q$) || ':' || (select r ->> 'confirmed' from zz.row('U_ACC', '2026-11', 'zz-n2') r) || ':' || zz.sg('2026-11') || ' | '
  || zz.try($q$update public.expenses set "articleId" = 'EX-13' where id = 'zz-n2'$q$) || ':' || (select r ->> 'confirmed' from zz.row('U_ACC', '2026-11', 'zz-n2') r) || ':' || zz.sg('2026-11') || ' | '
  || zz.try($q$insert into public.expenses (id, date, month, category, amount, note) values ('zz-n6', '2026-11-30', '2026-11', 'Kanselyariya', 0, 'Sinov')$q$) || ':' || zz.sg('2026-11'),
  '^true:0:1:0:true:valid \| OK:false:stale \| OK:true:valid \| OK:stale$');

-- ---------- (D) RP-09 ----------
select zz.chk('D1 RP-09: tasdiqlangan noyabr statiyalari — taxminiy emas; tasdiqlanmagan (yangi noyabr yozuvi, dekabr ijara) — taxminiy; oktyabr — eski qoida (statiya yozuvda)',
  (select zz.fl(j, 'EX-49') || ':' || zz.fl(j, 'EX-13') || ':' || zz.fl(j, 'EX-16') || ':' || zz.fl(j, 'EX-26') || ':' || zz.fl(j, 'EX-39') || ' | '
          || zz.fl(j, 'EX-32') || ':' || zz.fl(j, 'EX-10') || ' | ' || zz.fl(j, 'EX-42') || ':' || zz.fl(j, 'EX-11') from zz.mx() j),
  '^false:false:false:false:false \| true:false \| false:yoq$');
select zz.chk('D2 RP-09 «classify»: o''quv yili 2026 — uchala oy (noyabr — 6 tadan 5, imzo eskirgan; dekabr — 3 tadan 2, imzosiz; yanvar — 0)',
  (select string_agg((c ->> 'month') || '=' || (c ->> 'confirmed') || '/' || (c ->> 'n') || ':' ||
                     case when c -> 'sign' is null or jsonb_typeof(c -> 'sign') = 'null' then 'yoq' when (c #>> '{sign,valid}')::boolean then 'valid' else 'stale' end, ',')
     from jsonb_array_elements(zz.mx() -> 'classify') c),
  '^2026-11=5/6:stale,2026-12=2/3:yoq,2027-01=0/0:yoq$');
select zz.chk('D3 RP-09 «classify» davrga qarab: kalendar 2025 — bo''sh, kalendar 2027 — faqat yanvar',
  jsonb_array_length(zz.js(zz.as('U_DIR', $q$select public.fin_matrix('calendar', 2025)::text$q$)) -> 'classify') || ':'
  || (select string_agg(c ->> 'month', ',') from jsonb_array_elements(zz.js(zz.as('U_DIR', $q$select public.fin_matrix('calendar', 2027)::text$q$)) -> 'classify') c),
  '^0:2027-01$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
