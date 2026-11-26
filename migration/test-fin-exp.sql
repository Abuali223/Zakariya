-- =====================================================================
-- test-fin-exp.sql — moliya ish rejasi 2-bosqichi, F2.1 (fin-exp.sql) sinovi: «Buxgalteriya» xarajatlari reyestri.
--   (A) huquqlar: kim kiritadi / bekor qiladi / o'qiydi; hujjatsiz to'g'ridan-to'g'ri (REST) yozish — avvalgidek (huquq F2.9 da olinadi),
--       hujjat havolasi bilan — rad;
--   (B) bank / karta hujjati: statiya qatorlari, «Buxgalteriya» qatorlari (toifa, izoh, usul, kontragent), takror yuborish, takror
--       to'lov ogohlantirishi, kiritish tekshiruvlari va atomarlik;
--   (C) naqd: kassa ishga tushmagan — yoziladi; ishga tushgach — faqat kassa ishlamagan kun sanasi bilan va faqat Direktor;
--   (D) bekor qilish: hujjat, eski yozuv, qayta bosish, sabab, kassa / maosh / hujjat qatori, davr qulfi;
--   (E) tuzatish (replaces): hujjat va eski yozuv, bekor qilingan hujjat, qayta yuborish;
--   (F) himoya triggerlari (RLS chetlab o'tilganda ham): bog'langan qator va hujjat o'zgarmaydi;
--   (G) o'qish va o'zgarishlar jurnali.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-fin-exp.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.fin_exp_docs) or exists (select 1 from public.expenses) then
    raise exception 'test-fin-exp.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
create schema if not exists zz;
-- p_uid: null — anon; boshqa — authenticated (RLS bilan)
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
-- Jadval egasi sifatida (RLS chetlab o'tiladi), lekin foydalanuvchi da'vosi bilan — triggerlar himoyasini sinash uchun
create or replace function zz.own(p_uid text, p_q text, p_flag boolean default false) returns text language plpgsql as $$
declare r text; v_hint text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  if p_flag then perform set_config('iqror.fin_exp_rpc', '1', true); end if;   -- funksiya bayrog'i qo'lda qo'yilgan holat
  begin
    execute p_q into r;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
    r := 'ERR ' || sqlstate || ' [' || coalesce(v_hint, '') || '] ' || sqlerrm;
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('iqror.fin_exp_rpc', '', true);
  return coalesce(r, '<null>');
end $$;
create or replace function zz.js(p text) returns jsonb language plpgsql as $$
begin return p::jsonb; exception when others then return null; end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
create table if not exists zz.v (k text primary key, v text);
truncate zz.res; truncate zz.v;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
create or replace function zz.put(p_k text, p_v text) returns void language plpgsql as $$
begin insert into zz.v (k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; end $$;
create or replace function zz.get(p_k text) returns text language sql as $$ select v from zz.v where k = p_k $$;
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
create or replace function zz.save(p_uid text, p jsonb) returns text language sql as $$
  select zz.as(p_uid, format('select public.fin_exp_save(%L::jsonb)::text', p::text)) $$;
create or replace function zz.void(p_uid text, p_id text, p_reason text) returns text language sql as $$
  select zz.as(p_uid, format('select public.fin_exp_void(%L, %L)::text', p_id, p_reason)) $$;
create or replace function zz.id(p text) returns text language sql as $$ select zz.js(p) ->> 'id' $$;
-- hujjat qatorlari «Buxgalteriya»da: id-qo'shimcha:toifa:summa:usul:statiya:kontragent (qator tartibida)
create or replace function zz.rows(p_doc text) returns text language sql as $$
  select coalesce(string_agg(replace(e.id, p_doc, '') || ':' || e.category || ':' || trim_scale(e.amount) || ':' || e.method || ':' || e."articleId" || ':' || coalesce(e."counterpartyId", '-'),
                             ',' order by e.id), '-')
    from public.expenses e where e."expDocId" = p_doc $$;
create or replace function zz.doc(p_id text) returns text language sql as $$
  select d.status || ':' || d.origin || ':' || coalesce(d.method, '-') || ':' || trim_scale(d.amount) || ':' || jsonb_array_length(d.lines)
    from public.fin_exp_docs d where d.id = p_id $$;
-- bank hujjati namunasi
create or replace function zz.bank(p_ref text, p_doc text, p_amt numeric, p_date text default '2027-01-08') returns jsonb language sql as $$
  select jsonb_build_object('clientRef', p_ref, 'method', 'bank', 'date', p_date, 'counterpartyId', 'cp1', 'docNo', p_doc,
                            'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-11', 'amount', p_amt))) $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_KAS','k@x','Sinov Kassir','kassir','active','[]'), ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]'),
  ('U_MKT','m@x','Sinov Marketolog','marketing_mgr','active','[]'), ('U_TCH','t@x','Sinov Muallim','teacher','active','[]')
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name;
insert into public.fin_counterparties (id, kind, name, stir, active) values
  ('cp1', 'supplier', 'Sinov Ta''minotchi', '300000001', true), ('cp2', 'bank', 'Sinov Bank', '', true),
  ('cp3', 'supplier', 'Eski Ta''minotchi', '', false);
insert into public.expenses (id, date, month, category, amount, note, method, "articleId", "cashDocId") values
  ('e_old1', '2027-01-05', '2027-01', 'Kommunal', 900000, 'Sinov kommunal (eski)', null, 'EX-11', null),
  ('e_old2', '2027-01-06', '2027-01', 'Ijara', 5000000, 'Sinov ijara (eski)', 'bank', 'EX-10', null),
  ('e_old3', '2027-01-04', '2027-01', 'Boshqa', 70000, 'Sinov boshqa (eski)', null, 'EX-49', null),
  ('e_old4', '2027-01-03', '2027-01', 'Kanselyariya', 40000, 'Sinov qog''oz (eski)', null, 'EX-32', null),
  ('payroll__2026-12', '2026-12-01', '2026-12', 'Maosh', 3000000, 'Avtomatik', null, null, null),
  ('e_kx', '2027-01-07', '2027-01', 'Kanselyariya', 50000, 'Sinov KO-2', 'cash', 'EX-32', 'cd_sinov');
set local session_replication_role = origin;
select zz.clock('2027-01-10 10:00+05');   -- kassa hali ishga tushmagan

-- ---------- (A) huquqlar ----------
select zz.chk('A1 kassir, buxgalter, marketolog, o''qituvchi xarajat kirita olmaydi; anon — funksiya yopiq',
  zz.save('U_KAS', zz.bank('ref-a1-kas-0001', '1', 1000)) || ' | ' || zz.save('U_ACC', zz.bank('ref-a1-acc-0001', '1', 1000)) || ' | '
  || zz.save('U_MKT', zz.bank('ref-a1-mkt-0001', '1', 1000)) || ' | ' || zz.save('U_TCH', zz.bank('ref-a1-tch-0001', '1', 1000)) || ' | '
  || zz.save(null, zz.bank('ref-a1-anon-001', '1', 1000)),
  '^ERR 42501 \[fin:exp_rights\].* \| ERR 42501 \[fin:exp_rights\].* \| ERR 42501 \[fin:exp_rights\].* \| ERR 42501 \[fin:exp_rights\].* \| ERR 42501 .*permission denied');
select zz.chk('A2 kassir va buxgalter bekor qila olmaydi',
  zz.void('U_KAS', 'e_old1', 'sinov sababi') || ' | ' || zz.void('U_ACC', 'e_old1', 'sinov sababi'), '^ERR 42501 \[fin:exp_rights\].* \| ERR 42501 \[fin:exp_rights\]');
select zz.put('A3', zz.as('U_DIR', $q$select public.fin_exp_refs()::text$q$));
select zz.chk('A3 ma''lumotnoma: statiya usullari (EX-11 hammasi; EX-40 bank+karta; OP-12 faqat bank; OP-24 hammasi)',
  (select string_agg(a ->> 'id' || '=' || (a ->> 'cash') || '/' || (a ->> 'bank') || '/' || (a ->> 'card'), ',' order by a ->> 'id')
     from jsonb_array_elements(zz.js(zz.get('A3')) -> 'articles') a where a ->> 'id' in ('EX-11', 'EX-40', 'OP-12', 'OP-24')),
  '^EX-11=true/true/true,EX-40=false/true/true,OP-12=false/true/false,OP-24=true/true/true$');
select zz.chk('A3b ma''lumotnomada yo''q: ish haqi, ijtimoiy soliq, eskirish, maosh to''lovi, kartani to''ldirish, qaytarish, daromad; faol kontragentlar — 2',
  (select count(*) from jsonb_array_elements(zz.js(zz.get('A3')) -> 'articles') a
    where a ->> 'id' in ('EX-01', 'EX-05', 'EX-06', 'EX-44', 'EX-45', 'EX-47', 'OP-04', 'OP-09', 'OP-15', 'OP-19', 'OP-21', 'IN-01'))
  || ' | ' || jsonb_array_length(zz.js(zz.get('A3')) -> 'counterparties') || ' | ' || (zz.js(zz.get('A3')) ->> 'today'), '^0 \| 2 \| 2027-01-10$');
select zz.chk('A3c buxgalter ma''lumotnomani o''qiydi; o''qituvchi — yo''q',
  left(zz.as('U_ACC', $q$select (public.fin_exp_refs() ? 'articles')::text$q$), 4) || ' | ' || zz.as('U_TCH', $q$select public.fin_exp_refs()::text$q$), '^true \| ERR 42501');
select zz.chk('A4 to''g''ridan-to''g''ri yozish (eski sahifa; huquq F2.9 da olinadi): hujjatsiz xarajat va oylik maosh hisobi qatori — yoziladi; hujjat havolasi bilan — rad',
  zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method) values ('e_rest','2027-01-08','2027-01','Ijara',1000,'x','bank') returning id) select id from x$q$)
  || ' | ' || zz.as('U_FM', $q$with x as (insert into public.expenses (id, date, month, category, amount, note) values ('payroll__2027-01','2027-01-01','2027-01','Maosh',2500000,'Avtomatik') returning id) select id from x$q$)
  || ' | ' || zz.as('U_DIR', $q$with x as (insert into public.expenses (id, date, month, category, amount, note, method, "expDocId") values ('e_rest2','2027-01-08','2027-01','Ijara',1000,'x','bank','xd_yoq') returning id) select id from x$q$),
  '^e_rest \| payroll__2027-01 \| ERR 42501 \[fin:exp_linked\]');
select zz.chk('A4b hujjatsiz yozuvni to''g''ridan-to''g''ri o''zgartirish va o''chirish — avvalgidek (eski sahifa); maosh qatori ham',
  zz.as('U_DIR', $q$with x as (update public.expenses set amount = 2000 where id = 'e_rest' returning id) select count(*)::text from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (update public.expenses set amount = 2600000 where id = 'payroll__2027-01' returning id) select count(*)::text from x$q$) || ' | '
  || zz.as('U_FM', $q$with x as (delete from public.expenses where id = 'e_rest' returning id) select count(*)::text from x$q$),
  '^1 \| 1 \| 1$');
select zz.chk('A4c … statiya toifadan o''zi qo''yildi (kassa trigeri); o''chirilgan yozuv yo''q, maosh qatori yangilangan; eski yozuvlar joyida',
  (select coalesce("articleId", '-') from public.expenses where id = 'payroll__2027-01') || '/' || (select count(*) from public.expenses where id in ('e_rest', 'e_rest2'))
  || '/' || (select trim_scale(amount) from public.expenses where id = 'payroll__2027-01') || '/' || (select count(*) from public.expenses where id in ('e_old1', 'e_old2', 'e_old3', 'e_old4')),
  '^-/0/2600000/4$');
select zz.chk('A5 hujjatlar jadvaliga to''g''ridan-to''g''ri yozib bo''lmaydi; ichki funksiyalar mijozga yopiq',
  zz.as('U_DIR', $q$with x as (insert into public.fin_exp_docs (id, method, date, amount, lines, "clientRef") values ('x','bank','2027-01-08',1,'[{}]','xxxxxxxx') returning id) select id from x$q$)
  || ' | ' || zz.as('U_DIR', $q$select app.fin_exp_json('x')::text$q$) || ' | ' || zz.as('U_FM', $q$select app.fin_exp_docno_key('1')$q$),
  '^ERR 42501 .*permission denied.* \| ERR 42501 .*permission denied.* \| ERR 42501 .*permission denied');

-- ---------- (B) bank / karta ----------
select zz.put('B1', zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b1-000000001', 'method', 'bank', 'date', '2027-01-08', 'counterpartyId', 'cp1',
  'docNo', '№ 145', 'docDate', '2027-01-07', 'attachment', 'Hisob-faktura, dalolatnoma', 'note', 'Yanvar kommunal',
  'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-11', 'amount', 1200000, 'note', 'Elektr, yanvar'),
                             jsonb_build_object('articleId', 'EX-13', 'amount', '300000.00')))));
select zz.put('B1id', zz.id(zz.get('B1')));
select zz.chk('B1 bank hujjati: kiritildi (2 qator, jami 1 500 000), muallif — server, takror emas',
  zz.doc(zz.get('B1id')) || ' | ' || (zz.js(zz.get('B1')) ->> 'createdBy') || ':' || (zz.js(zz.get('B1')) ->> 'createdByName') || ' | ' || (zz.js(zz.get('B1')) ->> 'dup')
  || ' | ' || (zz.js(zz.get('B1')) ->> 'docNo') || ':' || (zz.js(zz.get('B1')) ->> 'docDate') || ':' || (zz.js(zz.get('B1')) ->> 'partyName'),
  '^posted:form:bank:1500000:2 \| U_FM:Sinov Moliyachi \| false \| 145:2027-01-07:Sinov Ta''minotchi$');
select zz.chk('B2 «Buxgalteriya» qatorlari: har statiya alohida (toifa xaritadan, xaritada yo''q — «Boshqa»), usul, kontragent, hujjat',
  zz.rows(zz.get('B1id')), '^_1:Kommunal:1200000:bank:EX-11:cp1,_2:Boshqa:300000:bank:EX-13:cp1$');
select zz.chk('B2b qator izohi: (statiya nomi —) kontragent — izoh (usul, №); sana va oy — hujjatdan',
  (select string_agg(e.note || ' @' || e.date || '/' || e.month, ' || ' order by e.id) from public.expenses e where e."expDocId" = zz.get('B1id')),
  '^Sinov Ta''minotchi — Elektr, yanvar \(bank o''tkazmasi, № 145\) @2027-01-08/2027-01 \|\| Suv, kanalizatsiya, chiqindi: Sinov Ta''minotchi — Yanvar kommunal \(bank o''tkazmasi, № 145\) @2027-01-08/2027-01$');
select zz.put('B3', zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b1-000000001', 'method', 'bank', 'date', '2027-01-08', 'counterpartyId', 'cp1',
  'docNo', '№ 145', 'docDate', '2027-01-07', 'attachment', 'Hisob-faktura, dalolatnoma', 'note', 'Yanvar kommunal',
  'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-11', 'amount', '1200000', 'note', 'Elektr, yanvar'),
                             jsonb_build_object('articleId', 'EX-13', 'amount', 300000)))));
select zz.chk('B3 qayta yuborish (o''sha oyna, o''sha ma''lumot; summa yozilishi farqli) — o''sha hujjat, yangi qator yo''q',
  (zz.id(zz.get('B3')) = zz.get('B1id'))::text || ':' || (zz.js(zz.get('B3')) ->> 'dup')
  || ' | ' || (select count(*) from public.fin_exp_docs) || '/' || (select count(*) from public.expenses where "expDocId" is not null), '^true:true \| 1/2$');
select zz.chk('B4 o''sha kalit, boshqa ma''lumot — rad; boshqa xodim o''sha kalit va o''sha ma''lumot bilan — ham rad (birovning hujjati qaytarilmaydi)',
  zz.save('U_FM', zz.bank('ref-b1-000000001', '145', 1)) || ' | ' || zz.save('U_DIR', zz.bank('ref-b1-000000001', '145', 1500000)) || ' | '
  || zz.save('U_DIR', jsonb_build_object('clientRef', 'ref-b1-000000001', 'method', 'bank', 'date', '2027-01-08', 'counterpartyId', 'cp1',
       'docNo', '№ 145', 'docDate', '2027-01-07', 'attachment', 'Hisob-faktura, dalolatnoma', 'note', 'Yanvar kommunal',
       'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-11', 'amount', 1200000, 'note', 'Elektr, yanvar'),
                                  jsonb_build_object('articleId', 'EX-13', 'amount', 300000)))),
  '^ERR 22023 \[fin:ref_mismatch\].* \| ERR 22023 \[fin:ref_mismatch\].* \| ERR 22023 \[fin:ref_mismatch\]');
select zz.chk('B5 boshqa oynadan shu kontragent + hujjat № + yil — takror ogohlantirishi (№ yozilishi farqli: «145»)',
  zz.save('U_DIR', zz.bank('ref-b5-000000001', '145', 999)), '^ERR P0001 \[fin:exp_dup\].*08\.01\.2027, «Sinov Ta''minotchi», № 145, 1 500 000 so''m, kiritdi: Sinov Moliyachi');
select zz.put('B5b', zz.save('U_DIR', zz.bank('ref-b5-000000001', '145', 999) || '{"dupOk": true}'));
select zz.chk('B5b tasdiqlansa (dupOk) — yoziladi; boshqa yil yoki boshqa kontragent — ogohlantirishsiz',
  zz.doc(zz.id(zz.get('B5b'))) || ' | ' || zz.doc(zz.id(zz.save('U_DIR', zz.bank('ref-b5-000000002', '145', 999, '2026-12-28')))) || ' | '
  || zz.doc(zz.id(zz.save('U_DIR', zz.bank('ref-b5-000000003', '145', 999) || '{"counterpartyId": "cp2"}'))),
  '^posted:form:bank:999:1 \| posted:form:bank:999:1 \| posted:form:bank:999:1$');
select zz.put('B6card', zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b6-000000001', 'method', 'card', 'date', '2027-01-09',
  'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-33', 'amount', 450000, 'note', 'Xosting, yillik')))));
select zz.chk('B6 karta: kontragent va № ixtiyoriy; toifa xaritadan (Dasturiy ta''minot), izohda usul',
  zz.rows(zz.id(zz.get('B6card'))) || ' | ' || (select note from public.expenses where "expDocId" = zz.id(zz.get('B6card'))),
  '^_1:Dasturiy ta‘minot:450000:card:EX-33:- \| Xosting, yillik \(korporativ karta\)$');
select zz.chk('B6b karta: № yo''q — takror kaliti sana + summa (+ kontragent); tasdiqlansa yoziladi',
  zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b6-000000002', 'method', 'card', 'date', '2027-01-09',
    'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-32', 'amount', 450000)))) || ' | '
  || zz.doc(zz.id(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b6-000000003', 'method', 'card', 'date', '2027-01-09', 'dupOk', true,
    'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-32', 'amount', 450000)))))),
  '^ERR P0001 \[fin:exp_dup\].* \| posted:form:card:450000:1$');
select zz.put('B7', zz.save('U_DIR', jsonb_build_object('clientRef', 'ref-b7-000000001', 'method', 'bank', 'date', '2027-01-09', 'counterpartyId', 'cp2',
  'docNo', 'TT-7', 'lines', jsonb_build_array(jsonb_build_object('articleId', 'OP-12', 'amount', 800000), jsonb_build_object('articleId', 'EX-40', 'amount', 12000)))));
select zz.chk('B7 soliq (faqat bank) — toifa «Soliq», izoh boshida statiya; bank komissiyasi — «Bank»',
  zz.rows(zz.id(zz.get('B7'))) || ' | ' || (select note from public.expenses where id = zz.id(zz.get('B7')) || '_1'),
  '^_1:Soliq:800000:bank:OP-12:cp2,_2:Bank:12000:bank:EX-40:cp2 \| JShDS va INPS \(faqat bank\): Sinov Bank \(bank o''tkazmasi, № TT-7\)$');
select zz.chk('B8 bank: kontragentsiz / №siz / nofaol kontragent / noma''lum kontragent — rad',
  zz.save('U_FM', zz.bank('ref-b8-000000001', '9', 1000) - 'counterpartyId') || ' | ' || zz.save('U_FM', zz.bank('ref-b8-000000002', ' № ', 1000)) || ' | '
  || zz.save('U_FM', zz.bank('ref-b8-000000003', '9', 1000) || '{"counterpartyId": "cp3"}') || ' | ' || zz.save('U_FM', zz.bank('ref-b8-000000004', '9', 1000) || '{"counterpartyId": "cpX"}'),
  '^ERR 22023 \[fin:exp_party\].* \| ERR 22023 \[fin:exp_docno\].* \| ERR 22023 \[fin:exp_party\].* \| ERR 22023 \[fin:exp_party\]');
select zz.chk('B9 statiya usulga mos emas: ish haqi, maosh to''lovi, kartani to''ldirish, eskirish, daromad (bank); soliq (karta); bank komissiyasi (naqd)',
  (select string_agg(regexp_replace(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b9-' || x.a || '-' || x.m, 'method', x.m, 'date', '2027-01-08', 'counterpartyId', 'cp1', 'docNo', '9',
            'lines', jsonb_build_array(jsonb_build_object('articleId', x.a, 'amount', 1000)))), '^(ERR \S+ \[[^]]*\]).*$', '\1'), ',' order by x.a, x.m)
     from (values ('EX-01', 'bank'), ('OP-09', 'bank'), ('OP-04', 'bank'), ('EX-44', 'bank'), ('IN-01', 'bank'), ('OP-12', 'card'), ('EX-40', 'cash'), ('ZZ-99', 'bank')) x(a, m)),
  '^(ERR 22023 \[fin:exp_article\],){7}ERR 22023 \[fin:exp_article\]$');
select zz.chk('B10 «Boshqa xarajatlar» (EX-49): izohsiz — rad; qator izohi yoki hujjat izohi bilan — yoziladi',
  zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b10-00000001', 'method', 'card', 'date', '2027-01-08', 'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-49', 'amount', 1000, 'note', 'ab')))) || ' | '
  || zz.doc(zz.id(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b10-00000002', 'method', 'card', 'date', '2027-01-08', 'note', 'Gul sotib olindi', 'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-49', 'amount', 1000)))))),
  '^ERR 22023 \[fin:exp_note\].* \| posted:form:card:1000:1$');
select zz.chk('B11 summa: 0, manfiy, 3 xona tiyin, matn, juda katta jami — rad',
  (select string_agg(regexp_replace(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b11-' || x.n, 'method', 'card', 'date', '2027-01-08',
            'lines', x.l)), '^(ERR \S+ \[[^]]*\]).*$', '\1'), ',' order by x.n)
     from (values ('00000001', '[{"articleId":"EX-32","amount":0}]'::jsonb), ('00000002', '[{"articleId":"EX-32","amount":-5}]'), ('00000003', '[{"articleId":"EX-32","amount":1.005}]'),
                  ('00000004', '[{"articleId":"EX-32","amount":"bir ming"}]'), ('00000005', '[{"articleId":"EX-32","amount":999999999999},{"articleId":"EX-16","amount":1}]')) x(n, l)),
  '^ERR 22023 \[kassa:amount\],ERR 22023 \[kassa:amount\],ERR 22023 \[kassa:amount\],ERR 22023 \[kassa:amount\],ERR 22023 \[kassa:amount\]$');
select zz.chk('B12 qatorlar: yo''q, bo''sh, 21 ta, statiyasiz — rad',
  regexp_replace(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b12-00000001', 'method', 'card', 'date', '2027-01-08')), '^(ERR \S+ \[[^]]*\]).*$', '\1') || ','
  || regexp_replace(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b12-00000002', 'method', 'card', 'date', '2027-01-08', 'lines', '[]'::jsonb)), '^(ERR \S+ \[[^]]*\]).*$', '\1') || ','
  || regexp_replace(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b12-00000003', 'method', 'card', 'date', '2027-01-08',
       'lines', (select jsonb_agg(jsonb_build_object('articleId', 'EX-32', 'amount', 10)) from generate_series(1, 21)))), '^(ERR \S+ \[[^]]*\]).*$', '\1') || ','
  || regexp_replace(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-b12-00000004', 'method', 'card', 'date', '2027-01-08', 'lines', '[{"amount":5}]'::jsonb)), '^(ERR \S+ \[[^]]*\]).*$', '\1'),
  '^ERR 22023 \[fin:exp_lines\],ERR 22023 \[fin:exp_lines\],ERR 22023 \[fin:exp_lines\],ERR 22023 \[fin:exp_article\]$');
select zz.chk('B13 sana: kelajak, 2 yildan eski, noto''g''ri; hujjat sanasi kelajakda; usul va kalit noto''g''ri — rad',
  (select string_agg(regexp_replace(zz.save('U_FM', x.p), '^(ERR \S+ \[[^]]*\]).*$', '\1'), ',' order by x.n)
     from (values (1, '{"clientRef":"ref-b13-00000001","method":"card","date":"2027-01-11","lines":[{"articleId":"EX-32","amount":5}]}'::jsonb),
                  (2, '{"clientRef":"ref-b13-00000002","method":"card","date":"2025-01-09","lines":[{"articleId":"EX-32","amount":5}]}'),
                  (3, '{"clientRef":"ref-b13-00000003","method":"card","date":"2027-02-30","lines":[{"articleId":"EX-32","amount":5}]}'),
                  (4, '{"clientRef":"ref-b13-00000004","method":"card","date":"2027-01-08","docDate":"2027-01-12","lines":[{"articleId":"EX-32","amount":5}]}'),
                  (5, '{"clientRef":"ref-b13-00000005","method":"accountable","date":"2027-01-08","lines":[{"articleId":"EX-32","amount":5}]}'),
                  (6, '{"clientRef":"short","method":"card","date":"2027-01-08","lines":[{"articleId":"EX-32","amount":5}]}')) x(n, p)),
  '^ERR 22023 \[fin:exp_date\],ERR 22023 \[fin:exp_date\],ERR 22023 \[fin:exp_date\],ERR 22023 \[fin:exp_date\],ERR 22023 \[fin:exp_input\],ERR 22023 \[fin:exp_input\]$');
select zz.chk('B14 atomar: rad etilgan so''rovlardan iz yo''q (hujjat ham, qator ham)',
  (select count(*) from public.fin_exp_docs where "clientRef" like 'ref-b8-%' or "clientRef" like 'ref-b9-%' or "clientRef" like 'ref-b11-%' or "clientRef" like 'ref-b12-%' or "clientRef" like 'ref-b13-%' or "clientRef" like 'ref-a1-%')
  || '/' || (select count(*) from public.expenses e where e."expDocId" is not null and not exists (select 1 from public.fin_exp_docs d where d.id = e."expDocId" and d.status = 'posted')),
  '^0/0$');

-- ---------- (C) naqd ----------
select zz.put('C1', zz.save('U_FM', jsonb_build_object('clientRef', 'ref-c1-000000001', 'method', 'cash', 'date', '2027-01-08',
  'lines', jsonb_build_array(jsonb_build_object('articleId', 'EX-32', 'amount', 80000, 'note', 'Qog''oz')))));
select zz.chk('C1 kassa ishga tushmagan: naqd xarajat (orderisiz) yoziladi, kontragent ixtiyoriy',
  zz.rows(zz.id(zz.get('C1'))) || ' | ' || (select note from public.expenses where "expDocId" = zz.id(zz.get('C1'))), '^_1:Kanselyariya:80000:cash:EX-32:- \| Qog''oz \(naqd \(orderisiz\)\)$');
select zz.clock('2027-01-11 09:00+05');
select zz.chk('C2 kassa ishga tushirildi (11.01.2027, boshlang''ich qoldiq)',
  left(zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-01-11","t1":1000000,"l1":200000,"orgCashMax":1000000000}')::text$q$), 0)
  || zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":1000000,"startDay":"2027-01-11"}')::text$q$), '"ok": true');
select zz.chk('C3 kassa ishlayotgan kun sanasi bilan naqd — rad (Moliya menejeriga ham, Direktorga ham); hujjat qolmaydi',
  zz.save('U_FM', jsonb_build_object('clientRef', 'ref-c3-000000001', 'method', 'cash', 'date', '2027-01-11', 'lines', '[{"articleId":"EX-32","amount":5000}]'::jsonb)) || ' | '
  || zz.save('U_DIR', jsonb_build_object('clientRef', 'ref-c3-000000002', 'method', 'cash', 'date', '2027-01-11', 'lines', '[{"articleId":"EX-32","amount":5000}]'::jsonb)),
  '^ERR 42501 \[kassa:cash_only_kassa\].* \| ERR 42501 \[kassa:cash_only_kassa\]');
select zz.chk('C3b … rad etilgan naqd hujjatdan iz yo''q', (select count(*) from public.fin_exp_docs where "clientRef" like 'ref-c3-%')::text, '^0$');
select zz.chk('C4 kassa ishga tushishidan oldingi sana bilan naqd — faqat Direktor (kech topilgan xarajat)',
  zz.save('U_FM', jsonb_build_object('clientRef', 'ref-c4-000000001', 'method', 'cash', 'date', '2027-01-09', 'lines', '[{"articleId":"EX-16","amount":7000}]'::jsonb)) || ' | '
  || zz.doc(zz.id(zz.save('U_DIR', jsonb_build_object('clientRef', 'ref-c4-000000002', 'method', 'cash', 'date', '2027-01-09', 'lines', '[{"articleId":"EX-16","amount":7000}]'::jsonb)))),
  '^ERR 42501 \[kassa:pre_live\].* \| posted:form:cash:7000:1$');
select zz.chk('C5 kassa ishlayotganda bank va karta xarajati — avvalgidek (bugungi sana bilan)',
  zz.doc(zz.id(zz.save('U_FM', zz.bank('ref-c5-000000001', 'PP-11', 640000, '2027-01-11')))) || ' | '
  || zz.doc(zz.id(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-c5-000000002', 'method', 'card', 'date', '2027-01-11', 'lines', '[{"articleId":"EX-23","amount":30000}]'::jsonb)))),
  '^posted:form:bank:640000:1 \| posted:form:card:30000:1$');

-- ---------- (D) bekor qilish ----------
select zz.put('D1', zz.void('U_FM', zz.get('B1id'), 'Xato kiritilgan (sinov)'));
select zz.chk('D1 hujjat bekor qilindi: holat, sabab, kim (nomi bilan); qatorlar «Buxgalteriya»dan olib tashlandi; hujjat qatorlari saqlanadi',
  zz.doc(zz.get('B1id')) || ' | ' || (zz.js(zz.get('D1')) ->> 'voidReason') || ' | ' || (zz.js(zz.get('D1')) ->> 'voidedBy') || ':' || (zz.js(zz.get('D1')) ->> 'voidedByName')
  || ' | ' || zz.rows(zz.get('B1id')) || ' | ' || (zz.js(zz.get('D1')) ->> 'dup'),
  '^void:form:bank:1500000:2 \| Xato kiritilgan \(sinov\) \| U_FM:Sinov Moliyachi \| - \| false$');
select zz.chk('D2 qayta bosish — xatosiz (dup), o''zgarish yo''q; sababsiz — rad',
  (zz.js(zz.void('U_DIR', zz.get('B1id'), 'Yana bir bor')) ->> 'dup') || ' | ' || zz.void('U_FM', zz.id(zz.get('B6card')), '  x '),
  '^true \| ERR 22023 \[fin:exp_reason\]');
select zz.chk('D2b … sabab va muallif o''zgarmagan; sababsiz so''rovdan keyin hujjat kiritilgan holatda',
  (select "voidReason" || ':' || "voidedBy" from public.fin_exp_docs where id = zz.get('B1id')) || ' | ' || zz.doc(zz.id(zz.get('B6card'))),
  '^Xato kiritilgan \(sinov\):U_FM \| posted:form:card:450000:1$');
select zz.put('D3', zz.void('U_DIR', 'e_old1', 'Ikki marta yozilgan edi'));
select zz.chk('D3 eski yozuv bekor qilindi: reyestrda «eski yozuv» surati (bekor qilingan), qator olib tashlandi; qayta bosish — dup',
  zz.doc(zz.id(zz.get('D3'))) || ' | ' || (zz.js(zz.get('D3')) ->> 'clientRef') || ' | ' || (zz.js(zz.get('D3')) -> 'lines' -> 0 ->> 'category') || ':' || (zz.js(zz.get('D3')) -> 'lines' -> 0 ->> 'articleId')
  || ':' || (zz.js(zz.get('D3')) -> 'lines' -> 0 ->> 'expenseId') || ' | ' || (zz.js(zz.get('D3')) ->> 'date') || ':' || (zz.js(zz.get('D3')) ->> 'voidedByName')
  || ' | ' || (select count(*) from public.expenses where id = 'e_old1') || ' | ' || (zz.js(zz.void('U_FM', 'e_old1', 'Yana bir bor')) ->> 'dup'),
  '^void:legacy:-:900000:1 \| legacy:e_old1 \| Kommunal:EX-11:e_old1 \| 2027-01-05:Sinov Direktor \| 0 \| true$');
select zz.chk('D4 maosh hisobi qatori, kassa qatori, hujjat qatori, noma''lum — rad',
  zz.void('U_DIR', 'payroll__2026-12', 'sinov sababi') || ' | ' || zz.void('U_DIR', 'e_kx', 'sinov sababi') || ' | '
  || zz.void('U_DIR', zz.id(zz.get('B6card')) || '_1', 'sinov sababi') || ' | ' || zz.void('U_DIR', 'yoq_id', 'sinov sababi'),
  '^ERR 22023 \[fin:exp_payroll\].* \| ERR 42501 \[kassa:linked_row\].* \| ERR 22023 \[fin:exp_linked\].* \| ERR 22023 \[fin:exp_input\]');
select zz.chk('D5 davr yopildi (07.01.2027 gacha): yopilgan sana bilan kiritish, bekor qilish va eski yozuvni bekor qilish — rad',
  left(zz.as('U_DIR', $q$select public.fin_period_lock('2027-01-07')::text$q$), 0)
  || zz.save('U_FM', zz.bank('ref-d5-000000001', 'D5', 1000, '2027-01-07')) || ' | ' || zz.void('U_FM', 'e_old2', 'Davr yopilgan') || ' | '
  || zz.void('U_FM', zz.id(zz.get('B7')), 'Davr ochiq'),
  '^ERR 42501 \[fin:locked\].* \| ERR 42501 \[fin:locked\].* \| \{.*"status": "void".*$');
select zz.chk('D5b rad etilganlardan iz yo''q (eski yozuv joyida, surat yo''q)',
  (select count(*) from public.expenses where id = 'e_old2') || '/' || (select count(*) from public.fin_exp_docs where "clientRef" in ('legacy:e_old2', 'ref-d5-000000001')), '^1/0$');
select zz.chk('D5c davr qayta ochildi (sabab bilan)', zz.as('U_DIR', $q$select public.fin_period_lock(null, 'Tuzatish uchun ochildi (sinov)')::text$q$), '"lockedThrough": null');

-- ---------- (E) tuzatish ----------
select zz.put('E1src', zz.id(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-e1-000000000', 'method', 'bank', 'date', '2027-01-09', 'counterpartyId', 'cp1', 'docNo', 'E-1',
  'lines', '[{"articleId":"EX-15","amount":250000}]'::jsonb))));
select zz.put('E1', zz.save('U_DIR', jsonb_build_object('clientRef', 'ref-e1-000000001', 'method', 'bank', 'date', '2027-01-09', 'counterpartyId', 'cp1', 'docNo', 'E-1',
  'replaces', zz.get('E1src'), 'lines', '[{"articleId":"EX-15","amount":200000},{"articleId":"EX-16","amount":50000}]'::jsonb)));
select zz.chk('E1 hujjat tuzatildi: yangisi kiritildi (replaces), eskisi bekor (replacedBy, sabab), qatorlar almashdi; № takror deb hisoblanmaydi',
  zz.doc(zz.id(zz.get('E1'))) || ':' || ((zz.js(zz.get('E1')) ->> 'replaces') = zz.get('E1src')) || ' | ' || zz.doc(zz.get('E1src')) || ':'
  || ((select "replacedBy" from public.fin_exp_docs where id = zz.get('E1src')) = zz.id(zz.get('E1'))) || ':' || (select "voidReason" from public.fin_exp_docs where id = zz.get('E1src'))
  || ' | ' || zz.rows(zz.get('E1src')) || ' | ' || zz.rows(zz.id(zz.get('E1'))),
  '^posted:form:bank:250000:2:true \| void:form:bank:250000:1:true:Tuzatildi: o''rniga yangi hujjat yozildi \| - \| _1:Ta‘mir:200000:bank:EX-15:cp1,_2:Xo‘jalik tovarlari:50000:bank:EX-16:cp1$');
select zz.chk('E2 qayta yuborish (eski hujjat endi bekor) — o''sha yangi hujjat (dup); bekor qilingan hujjatni boshqa oynadan tuzatish — rad',
  (zz.js(zz.save('U_DIR', jsonb_build_object('clientRef', 'ref-e1-000000001', 'method', 'bank', 'date', '2027-01-09', 'counterpartyId', 'cp1', 'docNo', 'E-1',
    'replaces', zz.get('E1src'), 'lines', '[{"articleId":"EX-15","amount":200000},{"articleId":"EX-16","amount":50000}]'::jsonb))) ->> 'dup') || ' | '
  || zz.save('U_DIR', jsonb_build_object('clientRef', 'ref-e2-000000001', 'method', 'bank', 'date', '2027-01-09', 'counterpartyId', 'cp1', 'docNo', 'E-1x',
    'replaces', zz.get('E1src'), 'lines', '[{"articleId":"EX-15","amount":1}]'::jsonb)),
  '^true \| ERR 22023 \[fin:exp_replace\]');
select zz.put('E3', zz.save('U_FM', jsonb_build_object('clientRef', 'ref-e3-000000001', 'method', 'bank', 'date', '2027-01-06', 'counterpartyId', 'cp1', 'docNo', 'IJ-01',
  'note', 'Yanvar ijarasi', 'replaces', 'e_old2', 'lines', '[{"articleId":"EX-10","amount":5000000}]'::jsonb)));
select zz.chk('E3 eski yozuv tuzatildi: «eski yozuv» surati (bekor, replacedBy) + yangi hujjat (replaces = surat); eski qator olib tashlandi',
  zz.doc(zz.id(zz.get('E3'))) || ' | ' || (select d.status || ':' || d.origin || ':' || d.method || ':' || ("replacedBy" = zz.id(zz.get('E3'))) || ':' || (d.id = zz.js(zz.get('E3')) ->> 'replaces')
                                               from public.fin_exp_docs d where d."clientRef" = 'legacy:e_old2')
  || ' | ' || (select count(*) from public.expenses where id = 'e_old2') || ' | ' || zz.rows(zz.id(zz.get('E3'))),
  '^posted:form:bank:5000000:1 \| void:legacy:bank:true:true \| 0 \| _1:Ijara:5000000:bank:EX-10:cp1$');
select zz.chk('E4 maosh hisobi qatori, kassa qatori, hujjat qatori, noma''lum id ni tuzatish — rad',
  (select string_agg(regexp_replace(zz.save('U_FM', jsonb_build_object('clientRef', 'ref-e4-0000000' || x.n, 'method', 'card', 'date', '2027-01-09', 'replaces', x.r,
            'lines', '[{"articleId":"EX-32","amount":1}]'::jsonb)), '^(ERR \S+ \[[^]]*\]).*$', '\1'), ',' order by x.n)
     from (values (1, 'payroll__2026-12'), (2, 'e_kx'), (3, zz.id(zz.get('E3')) || '_1'), (4, 'yoq_id')) x(n, r)),
  '^ERR 22023 \[fin:exp_payroll\],ERR 42501 \[kassa:linked_row\],ERR 22023 \[fin:exp_linked\],ERR 22023 \[fin:exp_replace\]$');
select zz.put('E5', zz.save('U_DIR', jsonb_build_object('clientRef', 'ref-e5-000000001', 'method', 'cash', 'date', '2027-01-04', 'replaces', 'e_old3',
    'lines', '[{"articleId":"EX-49","amount":70000,"note":"Gullar"}]'::jsonb)));
select zz.chk('E5 eski yozuvni tuzatish (EX-49, izohi bor) — naqd, kassa ishlamagan kun, Direktor; Moliya menejeriga — rad',
  zz.doc(zz.id(zz.get('E5'))) || ' | ' || (select count(*) from public.expenses where id = 'e_old3') || ' | '
  || zz.save('U_FM', jsonb_build_object('clientRef', 'ref-e5-000000002', 'method', 'cash', 'date', '2027-01-03', 'replaces', 'e_old4',
       'lines', '[{"articleId":"EX-32","amount":45000}]'::jsonb)),
  '^posted:form:cash:70000:1 \| 0 \| ERR 42501 \[kassa:pre_live\]');
select zz.chk('E5b … rad etilgan tuzatishdan iz yo''q: eski yozuv joyida, surat yo''q; bekor qilingan eski yozuvni tuzatish — rad',
  (select trim_scale(amount) from public.expenses where id = 'e_old4') || '/' || (select count(*) from public.fin_exp_docs where "clientRef" in ('legacy:e_old4', 'ref-e5-000000002'))
  || ' | ' || zz.save('U_DIR', jsonb_build_object('clientRef', 'ref-e5-000000003', 'method', 'card', 'date', '2027-01-05', 'replaces', 'e_old1',
       'lines', '[{"articleId":"EX-11","amount":900000}]'::jsonb)),
  '^40000/0 \| ERR 22023 \[fin:exp_replace\]');

-- ---------- (F) himoya triggerlari (RLS chetlab o'tilganda ham) ----------
select zz.put('Fd', zz.id(zz.get('E3')));
select zz.chk('F0 REST (RLS ruxsat beradi): hujjat qatorini o''zgartirish, o''chirish, havolasini olib tashlash — rad (Direktor ham, Moliya menejeri ham)',
  zz.as('U_DIR', format($q$with x as (update public.expenses set amount = 1 where id = %L returning id) select id from x$q$, zz.get('Fd') || '_1')) || ' | '
  || zz.as('U_FM', format($q$with x as (delete from public.expenses where id = %L returning id) select id from x$q$, zz.get('Fd') || '_1')) || ' | '
  || zz.as('U_DIR', format($q$with x as (update public.expenses set "expDocId" = null, note = 'x' where id = %L returning id) select id from x$q$, zz.get('Fd') || '_1')),
  '^ERR 42501 \[fin:exp_linked\].* \| ERR 42501 \[fin:exp_linked\].* \| ERR 42501 \[fin:exp_linked\]');
select zz.chk('F1 hujjat qatorini o''zgartirish / o''chirish, hujjat havolasini qo''yish yoki olib tashlash — rad; faqat updatedAt — o''tadi',
  zz.own('U_DIR', format($q$with x as (update public.expenses set amount = 1 where id = %L returning id) select id from x$q$, zz.get('Fd') || '_1')) || ' | '
  || zz.own('U_DIR', format($q$with x as (delete from public.expenses where id = %L returning id) select id from x$q$, zz.get('Fd') || '_1')) || ' | '
  || zz.own('U_DIR', format($q$with x as (update public.expenses set "expDocId" = null where id = %L returning id) select id from x$q$, zz.get('Fd') || '_1')) || ' | '
  || zz.own('U_DIR', format($q$with x as (insert into public.expenses (id, date, month, category, amount, method, "expDocId") values ('e_fake','2027-01-09','2027-01','Ijara',1,'bank',%L) returning id) select id from x$q$, zz.get('Fd'))) || ' | '
  || zz.own('U_DIR', format($q$with x as (update public.expenses set "expDocId" = %L where id = 'payroll__2026-12' returning id) select id from x$q$, zz.get('Fd'))) || ' | '
  || zz.own('U_DIR', format($q$with x as (update public.expenses set "updatedAt" = now() where id = %L returning id) select id from x$q$, zz.get('Fd') || '_1')),
  '^ERR 42501 \[fin:exp_linked\].* \| ERR 42501 \[fin:exp_linked\].* \| ERR 42501 \[fin:exp_linked\].* \| ERR 42501 \[fin:exp_linked\].* \| ERR 42501 \[fin:exp_linked\].* \| xd_[0-9a-f]{32}_1$');
select zz.chk('F2 hujjat: qo''shish, o''zgartirish (summa; bekor → kiritilgan), o''chirish — rad (bayroq bilan ham faqat «kiritilgan → bekor»)',
  zz.own('U_DIR', $q$with x as (insert into public.fin_exp_docs (id, method, date, amount, lines, "clientRef") values ('x','bank','2027-01-08',1,'[{}]','xxxxxxxx') returning id) select id from x$q$) || ' | '
  || zz.own('U_DIR', format($q$with x as (update public.fin_exp_docs set amount = 1 where id = %L returning id) select id from x$q$, zz.get('Fd'))) || ' | '
  || zz.own('U_DIR', format($q$with x as (update public.fin_exp_docs set amount = 1 where id = %L returning id) select id from x$q$, zz.get('Fd')), true) || ' | '
  || zz.own('U_DIR', format($q$with x as (update public.fin_exp_docs set status = 'posted', "voidReason" = null, "voidedAt" = null where id = %L returning id) select id from x$q$, zz.get('B1id')), true) || ' | '
  || zz.own('U_DIR', format($q$with x as (delete from public.fin_exp_docs where id = %L returning id) select id from x$q$, zz.get('B1id'))),
  '^ERR 42501 \[fin:exp_rpc_only\].* \| ERR 42501 \[fin:exp_rpc_only\].* \| ERR 42501 \[fin:exp_immutable\].* \| ERR 42501 \[fin:exp_immutable\].* \| ERR 42501 \[fin:exp_immutable\]');
select zz.chk('F3 hujjat joyida, qatorlari o''zgarmagan',
  zz.doc(zz.get('Fd')) || ' | ' || zz.rows(zz.get('Fd')) || ' | ' || zz.doc(zz.get('B1id')), '^posted:form:bank:5000000:1 \| _1:Ijara:5000000:bank:EX-10:cp1 \| void:form:bank:1500000:2$');

-- ---------- (G) o'qish va jurnal ----------
select zz.chk('G1 hujjatlarni Direktor, Moliya menejeri, buxgalter va kassir o''qiydi; marketolog va o''qituvchi — 0 qator; anon — yopiq',
  (select string_agg(zz.as(u, $q$select count(*)::text from public.fin_exp_docs$q$), ',' order by u) from unnest(array['U_ACC', 'U_DIR', 'U_FM', 'U_KAS', 'U_MKT', 'U_TCH']) u)
  || ' | ' || zz.as(null, $q$select count(*)::text from public.fin_exp_docs$q$),
  '^([1-9][0-9]*),\1,\1,\1,0,0 \| ERR 42501');
select zz.chk('G2 marketolog «Buxgalteriya» qatorlarini avvalgidek ko''radi (reklama xarajati hisobi uchun)',
  zz.as('U_MKT', $q$select (count(*) > 0)::text from public.expenses$q$), '^true$');
select zz.chk('G3 o''zgarishlar jurnali: hujjat (kiritildi, bekor qilindi) va xarajat qatori (usul, statiya, hujjat bilan)',
  (select count(*) from public.change_log where tbl = 'fin_exp_docs' and row_id = zz.get('B1id') and op in ('INSERT', 'UPDATE')) || ' | '
  || (select string_agg(k, ',' order by k) from public.change_log c, jsonb_object_keys(c.changes) k where c.tbl = 'expenses' and c.row_id = zz.get('Fd') || '_1' and c.op = 'INSERT'),
  '^2 \| amount,articleId,category,counterpartyId,date,expDocId,method,month,note$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 600), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
