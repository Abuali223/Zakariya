-- =====================================================================
-- test-kassa-adv.sql — moliya ish rejasi 2-bosqichi, F2.6a (reliz 24) sinovi: avans hisoboti to'liq.
--   (P) hisobdorga avansning maqsadi (purposeArticle): faqat avans hisobotidagi statiyalar; hujjat suratida; so'rov izida (state-9);
--   (A) ikki bosqich: KIRITADI 2-ro'yxat / Direktor — hujjat tasdiq kutadi (raqamsiz, xarajatsiz, qoldiq o'zgarmaydi); bitta hisobdorda
--       bitta kutilayotgan hisobot; TASDIQLAYDI boshqa 2-ro'yxat xodimi yoki Direktor (kirituvchi emas, hisobdor emas) — o'tkaziladi,
--       «А-» raqami, «Buxgalteriya»ga xarajatlar; qayta tasdiq / qayta yuborish — dup;
--   (R) rad etish va bekor qilish; (S) eskirgan hisobot: kiritilgandan keyin qoldiq o'zgarsa — tasdiq rad (kassa:adv_stale);
--   (O) ortiqcha sarf: qoldiq qatorlarga tartib bilan (Kt 4230), qolgani Kt 6970 (chegaradagi qator bo'linadi); 4230 formulalari
--       (qoldiq, nazorat ro'yxati, oylik to'plam E4) faqat 4230 qismi bilan; hisobdorga qarzimiz (6970) nazorat ro'yxatida;
--   (D) «Ortiqcha sarfni qoplash» chiqim orderi (Dt 6970 Kt 5010): qarzdan oshmaydi — so'rovda ham, pul berishda ham (hisobdor qulfi);
--       qoplangan ortiqcha sarfli hisobot bekor qilinmaydi (avval order);
--   (C) RP-07 hisobdor kartochkasi (kassa_acc_card): ro'yxat (qoldiq, qarz, kutilayotgan hisobot, eng eski yopilmagan avans yoshi —
--       ish kunlarida, muddati o'tganlik) va kartochka (FIFO yopilmagan avanslar maqsadi bilan, hujjatlar — 4230 / 6970 qismlari); rollar.
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, «--dev» zanjiridan keyin:
--     bash migration/chain.sh --dev --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-kassa-adv.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Sinov ismlari to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
--   Eslatma: bitta tranzaksiyada now() o'zgarmaydi — bir kunda o'tkazilgan hujjatlar tartibi (postedAt teng) tasodifiy; shuning uchun
--   bir kun ichidagi ro'yxatlar tartibsiz (saralab) solishtiriladi, FIFO esa turli kunlardagi avanslar bilan tekshiriladi.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.cash_docs) then
    raise exception 'test-kassa-adv.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
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
-- JSON bo'lmagan javob (ERR …) — NULL: tekshiruv FAIL bo'ladi, to'plam to'xtamaydi
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
create or replace function zz.id(p_k text) returns text language sql as $$ select zz.js(v) ->> 'id' from zz.v where k = p_k $$;
-- JSON javobdan maydon; javob xato matni bo'lsa — matnning o'zi (tekshiruv FAIL bo'lib ko'rinadi)
create or replace function zz.f(p text, variadic p_path text[]) returns text language sql as $$
  select case when p ~ '^\s*\{' and zz.js(p) is not null then (zz.js(p) #>> p_path) else left(coalesce(p, '<null>'), 300) end $$;
create or replace function zz.clock(p_t timestamptz) returns void language sql as $$
  insert into app.fin_clock (id, t) values (1, p_t) on conflict (id) do update set t = excluded.t $$;
create or replace function zz.rpc(p_uid text, p_fn text, p_json text) returns text language sql as $$
  select zz.as(p_uid, format('select public.%I(%L::jsonb)::text', p_fn, p_json)) $$;
create or replace function zz.appr(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_approve(%L)::text', p_id)) $$;
create or replace function zz.pay(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_pay(%L)::text', p_id)) $$;
create or replace function zz.void(p_uid text, p_id text, p_reason text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_void(%L, %L)::text', p_id, p_reason)) $$;
create or replace function zz.rej(p_uid text, p_id text, p_reason text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_reject(%L, %L)::text', p_id, p_reason)) $$;
create or replace function zz.cancel(p_uid text, p_id text, p_reason text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_doc_cancel(%L, %L)::text', p_id, p_reason)) $$;
create or replace function zz.avoid(p_uid text, p_id text, p_reason text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_adv_report_void(%L, %L)::text', p_id, p_reason)) $$;
-- avans hisoboti: (kirituvchi, kalit, xodim, qatorlar JSON)
create or replace function zz.rep(p_uid text, p_ref text, p_party text, p_lines text) returns text language sql as $$
  select zz.rpc(p_uid, 'kassa_adv_report', format('{"clientRef":"%s","partyId":"%s","reportDate":"%s","lines":%s}', p_ref, p_party, app.fin_today(), p_lines)) $$;
-- chiqim so'rovi (kassir): (kalit, operatsiya, xodim, summa, qo'shimcha JSON maydonlari)
create or replace function zz.req(p_ref text, p_op text, p_party text, p_amount numeric, p_extra text default '{}') returns text language sql as $$
  select zz.rpc('U_KAS', 'kassa_payout_request', (jsonb_build_object('op', p_op, 'amount', p_amount, 'partyType', 'employee', 'partyId', p_party,
                                                                     'basis', 'Sinov asosi', 'clientRef', p_ref) || p_extra::jsonb)::text) $$;
-- Holat o'qiydigan yordamchilar — plpgsql (VOLATILE): har so'rovi yangi surat oladi, shuning uchun bir ifodada oldinroq bajarilgan amal
--   (tasdiq, to'lov, bekor qilish) natijasini ko'radi (SQL funksiya ichiga joylanib, STABLE funksiya tashqi so'rov suratida qolardi).
create or replace function zz.open(p_party text) returns text language plpgsql as $$ begin return trim_scale(app.kassa_acc_open(p_party))::text; end $$;
create or replace function zz.due(p_party text) returns text language plpgsql as $$ begin return trim_scale(app.kassa_acc_due(p_party))::text; end $$;
create or replace function zz.checks() returns jsonb language sql as $$ select zz.js(zz.as('U_FM', $q$select public.kassa_checks('main')::text$q$)) $$;
-- «Tasdiqlash» navbati (kassa_state → pending.toApprove) — shu foydalanuvchi uchun
create or replace function zz.toappr(p_uid text) returns text language sql as $$
  select coalesce(zz.js(zz.as(p_uid, $q$select public.kassa_state('main')::text$q$)) -> 'pending' ->> 'toApprove', 'ERR') $$;
create or replace function zz.card(p_uid text, p_party text) returns text language sql as $$
  select zz.as(p_uid, format('select public.kassa_acc_card(%L)::text', p_party)) $$;
-- hujjat qatorlari: n:statiya:summa:Kt:analytics.kind
create or replace function zz.lines(p_id text) returns text language plpgsql as $$
begin
  return (select string_agg(l."lineNo" || ':' || l."articleId" || ':' || trim_scale(l.amount) || ':' || l.credit || ':' || coalesce(l.analytics ->> 'kind', '-'), ',' order by l."lineNo")
            from public.cash_doc_lines l where l."docId" = p_id);
end $$;
create or replace function zz.status(p_id text) returns text language plpgsql as $$ begin return (select status from public.cash_docs where id = p_id); end $$;
create or replace function zz.nexp(p_id text) returns text language plpgsql as $$
begin return (select count(*) || ':' || trim_scale(coalesce(sum(amount), 0)) from public.expenses where "cashDocId" = p_id); end $$;
-- kassa kunini yopish (sanalgan = hisobdagi qoldiq)
create or replace function zz.close(p_day text) returns text language sql as $$
  select zz.rpc('U_KAS', 'kassa_day_close', format('{"desk":"main","day":"%s","counted":%s}', p_day,
                (select app.kassa_day_balance(d.id) from public.cash_days d where d.desk = 'main' and d.day = p_day::date))) $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles", "staffRefType", "staffRefId") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]',null,null), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]',null,null),
  ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]',null,null), ('U_KAS','k@x','Sinov Kassir','kassir','active','[]',null,null),
  ('U_TCH','t@x','Sinov Muallim','teacher','active','[]',null,null),
  ('U_FM2','f2@x','Sinov Moliyachi Ikki','finance_mgr','active','[]','staff','st2')   -- hisobdor xodim (st2) — o'zi ham 2-ro'yxatda
on conflict (id) do update set role = excluded.role, status = excluded.status, email = excluded.email, name = excluded.name,
  "staffRefType" = excluded."staffRefType", "staffRefId" = excluded."staffRefId";
insert into public.teachers (id, "teacherId", name, pauses) values ('tch1','IQT-T1','Sinov O''qituvchi','[]');
insert into public.staff (id, "staffId", name, position) values ('st1','IQX-T1','Sinov Zavxoz','Zavxoz'), ('st2','IQX-T2','Sinov Ta''minotchi','Moliya menejeri');
set local session_replication_role = origin;
select zz.clock('2027-02-01 10:00+05');   -- dushanba
select zz.chk('N1 kassa ishga tushdi: T1 1 000 000, boshlang''ich qoldiq 3 000 000',
  left(zz.as('U_DIR', $q$select public.fin_org_set('{"kassaGoLive":"2027-02-01","t1":1000000,"l1":200000,"cashLimit":9000000,"orgCashMax":1000000000}')::text$q$), 0)
  || zz.as('U_DIR', $q$select public.kassa_opening_set('{"amount":3000000,"startDay":"2027-02-01"}')::text$q$), '"ok": true');

-- ---------- (P) hisobdorga avansning maqsadi ----------
select zz.chk('P1 avans maqsadi: ish haqi (EX-01), yetkazib beruvchi bilan hisob-kitob (OP-17), yo''q statiya — rad, hujjat yozilmaydi',
  zz.req('adv-p1-0001', 'out_accountable', 'staff:st1', 300000, '{"purposeArticle":"EX-01"}') || ' | '
  || zz.req('adv-p1-0002', 'out_accountable', 'staff:st1', 300000, '{"purposeArticle":"OP-17"}') || ' | '
  || zz.req('adv-p1-0003', 'out_accountable', 'staff:st1', 300000, '{"purposeArticle":"ZZ-99"}') || ' | '
  || (select count(*) from public.cash_docs where "clientRef" like 'adv-p1-%'),
  '^ERR 22023 \[kassa:article\].* \| ERR 22023 \[kassa:article\].* \| ERR 22023 \[kassa:article\].* \| 0$');
select zz.put('A0', zz.req('adv-a0-0001', 'out_accountable', 'staff:st1', 300000, '{"purposeArticle":"EX-20"}'));
select zz.chk('P2 maqsad hujjat suratida (sourceSnapshot.purposeArticle); so''rov 2-ro''yxat tasdig''ini kutadi',
  zz.f(zz.get('A0'), 'status') || ':' || zz.f(zz.get('A0'), 'sourceSnapshot', 'purposeArticle') || ':' || zz.f(zz.get('A0'), 'needsList2') || ':' || zz.f(zz.get('A0'), 'needsDirector'),
  '^draft:EX-20:true:false$');
select zz.chk('P3 state-9: o''sha kalit bilan boshqa maqsad yoki maqsadsiz — rad; aynan o''sha so''rov — dup',
  zz.req('adv-a0-0001', 'out_accountable', 'staff:st1', 300000, '{"purposeArticle":"EX-16"}') || ' | '
  || zz.req('adv-a0-0001', 'out_accountable', 'staff:st1', 300000) || ' | '
  || zz.f(zz.req('adv-a0-0001', 'out_accountable', 'staff:st1', 300000, '{"purposeArticle":"EX-20"}'), 'dup'),
  '^ERR 22023 \[kassa:ref_mismatch\].* \| ERR 22023 \[kassa:ref_mismatch\].* \| true$');
select zz.put('A0p', left(zz.appr('U_FM', zz.id('A0')), 0) || zz.pay('U_KAS', zz.id('A0')));
select zz.chk('P4 avans berildi: hisobdorda 300 000', zz.f(zz.get('A0p'), 'status') || ':' || zz.open('staff:st1'), '^posted:300000$');
select zz.put('P5', zz.req('adv-p5-0001', 'out_accountable', 'teachers:tch1', 10000));
select zz.chk('P5 maqsadsiz so''rov — hujjat suratida maqsad yo''q (so''rov bekor qilinadi)',
  coalesce(zz.js(zz.get('P5')) -> 'sourceSnapshot' ->> 'purposeArticle', '-') || ':' || zz.f(zz.cancel('U_KAS', zz.id('P5'), 'Sinov so''rovi'), 'status'),
  '^-:cancelled$');

-- ---------- (A) ikki bosqich: kiritish → tasdiq ----------
select zz.put('A1', zz.rep('U_FM', 'adv-a1-0001', 'staff:st1', '[{"articleId":"EX-20","amount":120000,"note":"Chek 1, 01.02"},{"articleId":"EX-16","amount":80000,"note":"Chek 2, 01.02"}]'));
select zz.chk('A1 kiritildi: naqdsiz dalolatnoma tasdiq kutadi (raqamsiz, 2-ro''yxat), Kt 4230; xarajat yo''q, hisobdor qoldig''i o''zgarmagan',
  zz.f(zz.get('A1'), 'form') || ':' || zz.f(zz.get('A1'), 'op') || ':' || zz.f(zz.get('A1'), 'status') || ':' || coalesce(zz.f(zz.get('A1'), 'no'), '-') || ':' || zz.f(zz.get('A1'), 'needsList2')
  || ':' || zz.f(zz.get('A1'), 'openBefore') || ':' || zz.f(zz.get('A1'), 'openAfter') || ':' || zz.f(zz.get('A1'), 'overspend')
  || ' | ' || zz.lines(zz.id('A1')) || ' | ' || zz.nexp(zz.id('A1')) || ' | ' || zz.open('staff:st1'),
  '^ACT:nc_adv_report:draft:-:true:300000:100000:0 \| 1:EX-20:120000:4230:-,2:EX-16:80000:4230:- \| 0:0 \| 300000$');
select zz.chk('A1b hujjat suratida: hisobot sanasi, qoldiq oldin / keyin, ortiqcha sarf, qarzimiz oldin',
  (select (s ->> 'reportDate') || ':' || (s ->> 'openBefore') || ':' || (s ->> 'openAfter') || ':' || (s ->> 'overspend') || ':' || (s ->> 'dueBefore')
     from (select "sourceSnapshot" s from public.cash_docs where id = zz.id('A1')) q),
  '^2027-02-01:300000:100000:0:0$');
select zz.chk('A1c «Tasdiqlash» navbati: kirituvchida — yo''q; buxgalter, Direktor va boshqa Moliya menejerida — bor',
  zz.toappr('U_FM') || ':' || zz.toappr('U_ACC') || ':' || zz.toappr('U_DIR') || ':' || zz.toappr('U_FM2'), '^0:1:1:1$');
select zz.chk('A2 shu hisobdorda kutilayotgan hisobot bor — ikkinchisi rad (summasi va vaqti bilan); avansi yo''q xodim — «avans yo''q»',
  zz.rep('U_ACC', 'adv-a2-0001', 'staff:st1', '[{"articleId":"EX-20","amount":1000,"note":"Chek 9"}]') || ' | '
  || zz.rep('U_ACC', 'adv-a2-0002', 'teachers:tch1', '[{"articleId":"EX-20","amount":1000,"note":"Chek 9"}]'),
  '^ERR P0001 \[kassa:adv_pending\].*\(200000 so''m, \d\d\.\d\d\.\d{4} \d\d:\d\d\).* \| ERR P0001 \[kassa:acc_none\]');
select zz.chk('A3 qayta yuborish — o''sha hujjat (dup, hali tasdiq kutadi)',
  zz.f(zz.rep('U_FM', 'adv-a1-0001', 'staff:st1', '[{"articleId":"EX-20","amount":120000,"note":"Chek 1, 01.02"},{"articleId":"EX-16","amount":80000,"note":"Chek 2, 01.02"}]'), 'dup')
  || ':' || zz.status(zz.id('A1')) || ':' || (select count(*) from public.cash_docs where op = 'nc_adv_report'), '^true:draft:1$');
select zz.chk('A4 tasdiq: kassir, o''qituvchi — rad; kirituvchining o''zi — rad (kassa:self_approve); kassir pul bera olmaydi; hali tasdiq kutadi',
  zz.appr('U_KAS', zz.id('A1')) || ' | ' || zz.appr('U_TCH', zz.id('A1')) || ' | ' || zz.appr('U_FM', zz.id('A1')) || ' | ' || zz.pay('U_KAS', zz.id('A1'))
  || ' | ' || zz.status(zz.id('A1')),
  '^ERR 42501.* \| ERR 42501.* \| ERR 42501 \[kassa:self_approve\].* \| ERR 42501 \[kassa:not_approved\].* \| draft$');
select zz.put('A5', zz.appr('U_ACC', zz.id('A1')));
select zz.chk('A5 boshqa 2-ro''yxat xodimi (buxgalter) tasdiqladi — o''tkazildi: «А-» seriyasi № 1, bugungi kun; qoldiq 300 000 → 100 000',
  zz.f(zz.get('A5'), 'status') || ':' || zz.f(zz.get('A5'), 'series') || ':' || zz.f(zz.get('A5'), 'no') || ':' || zz.f(zz.get('A5'), 'approvedBy') || ':' || zz.f(zz.get('A5'), 'postedBy')
  || ':' || zz.f(zz.get('A5'), 'businessDay') || ':' || zz.f(zz.get('A5'), 'openBefore') || ':' || zz.f(zz.get('A5'), 'openAfter') || ':' || zz.f(zz.get('A5'), 'overspend')
  || ':' || zz.f(zz.get('A5'), 'due') || ' | ' || zz.open('staff:st1'),
  '^posted:ADV:1:U_ACC:U_ACC:2027-02-01:300000:100000:0:0 \| 100000$');
select zz.chk('A6 «Buxgalteriya»ga 2 ta xarajat: usul «hisobdor orqali», hujjatga bog''langan, statiyalar bilan; ortiqcha sarf belgisi yo''q',
  (select count(*) || ':' || trim_scale(sum(amount)) || ':' || string_agg(distinct method, ',') || ':' || string_agg("articleId", ',' order by "articleId")
          || ':' || count(*) filter (where note like '%ortiqcha sarf%')
     from public.expenses where "cashDocId" = zz.id('A1')), '^2:200000:accountable:EX-16,EX-20:0$');
select zz.chk('A7 qayta tasdiq — dup; boshqa tasdiqlovchi — «tasdiq kutmayapti»; kirituvchi qayta yuborsa — o''tkazilgan hujjat (dup)',
  zz.f(zz.appr('U_ACC', zz.id('A1')), 'dup') || ' | ' || zz.appr('U_DIR', zz.id('A1')) || ' | '
  || zz.f(zz.rep('U_FM', 'adv-a1-0001', 'staff:st1', '[{"articleId":"EX-20","amount":120000,"note":"Chek 1, 01.02"},{"articleId":"EX-16","amount":80000,"note":"Chek 2, 01.02"}]'), 'status'),
  '^true \| ERR P0001 \[kassa:bad_status\].* \| posted$');
-- sec-1: hisobdorning o'zi 2-ro'yxatda (U_FM2 ↔ st2)
select zz.put('B1', zz.req('adv-b1-0001', 'out_accountable', 'staff:st2', 50000));
select zz.put('B1p', left(zz.appr('U_FM', zz.id('B1')), 0) || zz.pay('U_KAS', zz.id('B1')));
select zz.put('B2', zz.rep('U_ACC', 'adv-b2-0001', 'staff:st2', '[{"articleId":"EX-20","amount":20000,"note":"Chek 3, 01.02"}]'));
select zz.chk('A8b navbat: hisobdorning o''zi (U_FM2 ↔ st2) va kirituvchi (buxgalter) navbatida — yo''q; boshqa Moliya menejeri va Direktorda — bor',
  zz.toappr('U_FM2') || ':' || zz.toappr('U_ACC') || ':' || zz.toappr('U_FM') || ':' || zz.toappr('U_DIR'), '^0:0:1:1$');
select zz.chk('A8 sec-1: hisobdor (2-ro''yxat xodimi) o''z hisobotini kirita ham, tasdiqlay ham olmaydi; Direktor tasdiqlaydi — qoldiq 50 000 → 30 000',
  zz.rep('U_FM2', 'adv-b2-0002', 'staff:st2', '[{"articleId":"EX-20","amount":20000,"note":"Chek 3, 01.02"}]') || ' | ' || zz.f(zz.get('B2'), 'status')
  || ' | ' || zz.appr('U_FM2', zz.id('B2')) || ' | ' || zz.f(zz.appr('U_DIR', zz.id('B2')), 'status') || ':' || zz.open('staff:st2'),
  '^ERR 42501 \[kassa:self_report\].* \| draft \| ERR 42501 \[kassa:self_report\].* \| posted:30000$');

-- ---------- (R) rad etish va bekor qilish ----------
select zz.put('R1', zz.rep('U_FM', 'adv-r1-0001', 'staff:st1', '[{"articleId":"EX-20","amount":30000,"note":"Chek 4, 01.02"}]'));
select zz.put('R1r', zz.rej('U_ACC', zz.id('R1'), 'Cheklar to''liq emas'));
select zz.chk('R1 rad etildi: xarajat yo''q, qoldiq o''zgarmagan (100 000)',
  zz.f(zz.get('R1r'), 'status') || ':' || zz.f(zz.get('R1r'), 'rejectedBy') || ':' || zz.f(zz.get('R1'), 'status') || ':' || zz.nexp(zz.id('R1')) || ':' || zz.open('staff:st1'),
  '^rejected:U_ACC:draft:0:0:100000$');
select zz.put('R2', zz.rep('U_FM', 'adv-r2-0001', 'staff:st1', '[{"articleId":"EX-20","amount":40000,"note":"Chek 5, 01.02"}]'));
select zz.chk('R2 rad etilgandan keyin yangi hisobot kiritiladi; tasdiq kutayotganini «bekor qilish (void)» — yo''q; boshqa xodim bekor qila olmaydi, kirituvchi — bekor qiladi; bekor qilingani tasdiqlanmaydi',
  zz.f(zz.get('R2'), 'status') || ' | ' || zz.avoid('U_FM', zz.id('R2'), 'Xato kiritilgan') || ' | ' || zz.cancel('U_ACC', zz.id('R2'), 'Xato kiritilgan')
  || ' | ' || zz.f(zz.cancel('U_FM', zz.id('R2'), 'Xato kiritilgan'), 'status') || ' | ' || zz.appr('U_ACC', zz.id('R2')),
  '^draft \| ERR P0001 \[kassa:bad_status\].* \| ERR 42501.* \| cancelled \| ERR P0001 \[kassa:bad_status\]');

-- ---------- (S) eskirgan hisobot ----------
select zz.put('S1', zz.rep('U_FM', 'adv-s1-0001', 'staff:st1', '[{"articleId":"EX-20","amount":50000,"note":"Chek 6, 01.02"}]'));
select zz.put('S1r', zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_acc_return","amount":20000,"partyType":"employee","partyId":"staff:st1","basis":"Qaytim","clientRef":"r-s1-ret1"}'));
select zz.chk('S1 kiritilgandan keyin qaytim olindi (100 000 → 80 000) — tasdiq rad (kassa:adv_stale), hisobot tasdiq kutishda qoladi, xarajat yo''q',
  zz.f(zz.get('S1r'), 'status') || ':' || zz.open('staff:st1') || ' | ' || zz.appr('U_ACC', zz.id('S1')) || ' | ' || zz.status(zz.id('S1')) || ':' || zz.nexp(zz.id('S1')),
  '^posted:80000 \| ERR P0001 \[kassa:adv_stale\].*100000 → 80000 so''m.* \| draft:0:0$');
select zz.put('S2', left(zz.cancel('U_FM', zz.id('S1'), 'Qoldiq o''zgardi'), 0)
  || zz.rep('U_FM', 'adv-s2-0001', 'staff:st1', '[{"articleId":"EX-20","amount":50000,"note":"Chek 6, 01.02"}]'));
select zz.chk('S2 bekor qilinib qayta kiritildi (qoldiq 80 000 dan) — tasdiqlandi, qoldiq 30 000',
  zz.status(zz.id('S1')) || ' | ' || zz.f(zz.get('S2'), 'openBefore') || ':' || zz.f(zz.appr('U_ACC', zz.id('S2')), 'status') || ':' || zz.open('staff:st1'),
  '^cancelled \| 80000:posted:30000$');

-- ---------- (O) ortiqcha sarf ----------
select zz.put('O1', zz.rep('U_FM', 'adv-o1-0001', 'staff:st1', '[{"articleId":"EX-20","amount":30000,"note":"Chek 7, 01.02"},{"articleId":"EX-16","amount":40000,"note":"Chek 8, 01.02"}]'));
select zz.chk('O1 hisobot 70 000, qoldiq 30 000: 1-qator qoldiqqa aynan teng — butunligicha Kt 4230 (bo''linmaydi), 2-qator butunligicha Kt 6970 (ortiqcha sarf); hujjat suratida ham',
  zz.f(zz.get('O1'), 'status') || ':' || zz.f(zz.get('O1'), 'amount') || ':' || zz.f(zz.get('O1'), 'openBefore') || ':' || zz.f(zz.get('O1'), 'openAfter') || ':' || zz.f(zz.get('O1'), 'overspend')
  || ' | ' || zz.lines(zz.id('O1')) || ' | ' || zz.f(zz.get('O1'), 'sourceSnapshot', 'overspend') || ':' || zz.f(zz.get('O1'), 'sourceSnapshot', 'openAfter') || ':' || zz.f(zz.get('O1'), 'sourceSnapshot', 'dueBefore'),
  '^draft:70000:30000:0:40000 \| 1:EX-20:30000:4230:-,2:EX-16:40000:6970:overspend \| 40000:0:0$');
select zz.chk('O1b ortiqcha sarf qatori: Dt statiya hisobvarag''i (2010), hisobdor tahlili (partyId) saqlanadi',
  (select l.debit || ':' || (l.analytics ->> 'partyId') || ':' || l.note from public.cash_doc_lines l where l."docId" = zz.id('O1') and l.credit = '6970'),
  '^2010:staff:st1:Chek 8, 01\.02$');
select zz.put('O2', zz.appr('U_DIR', zz.id('O1')));
select zz.chk('O2 Direktor tasdiqladi: qoldiq 30 000 → 0, ortiqcha sarf 40 000 — hisobdorga qarzimiz 40 000',
  zz.f(zz.get('O2'), 'status') || ':' || zz.f(zz.get('O2'), 'openBefore') || ':' || zz.f(zz.get('O2'), 'openAfter') || ':' || zz.f(zz.get('O2'), 'overspend') || ':' || zz.f(zz.get('O2'), 'due')
  || ' | ' || zz.open('staff:st1') || ':' || zz.due('staff:st1'),
  '^posted:30000:0:40000:40000 \| 0:40000$');
select zz.chk('O3 «Buxgalteriya»ga 2 ta xarajat (70 000): ortiqcha sarf qismi izohida belgilangan (40 000)',
  zz.nexp(zz.id('O1')) || ':' || (select trim_scale(sum(amount)) from public.expenses where "cashDocId" = zz.id('O1') and note like '%ortiqcha sarf%'),
  '^2:70000:40000$');
select zz.chk('O4 nazorat ro''yxati: hisobdorlar ro''yxatida yo''q (qoldiq 0, manfiy emas); «hisobdorga qarzimiz» — 40 000; moslik P4 (avans hisoboti ↔ xarajatlar) toza',
  coalesce((select string_agg(a ->> 'partyId', ',') from jsonb_array_elements(zz.checks() -> 'accountable') a where a ->> 'partyId' = 'staff:st1'), 'yo''q')
  || ' | ' || (select string_agg((d ->> 'partyId') || ':' || (d ->> 'name') || ':' || trim_scale((d ->> 'due')::numeric), ',') from jsonb_array_elements(zz.checks() -> 'accDue') d)
  || ' | ' || (zz.checks() -> 'reconcile' -> 'p4' ->> 'adv'),
  '^yo''q \| staff:st1:Sinov Zavxoz:40000 \| 0$');
select zz.chk('O5 qoldiq 0 (qarzimiz bor) — yangi hisobot «avans yo''q»; kassir oynasi: qoldiq 0, qarzimiz 40 000',
  zz.rep('U_FM', 'adv-o5-0001', 'staff:st1', '[{"articleId":"EX-20","amount":1000,"note":"Chek 9"}]') || ' | '
  || (select trim_scale((j ->> 'accountable')::numeric) || ':' || trim_scale((j ->> 'due')::numeric)
        from (select zz.js(zz.as('U_KAS', $q$select public.kassa_staff_open('main', 'staff:st1')::text$q$)) j) q),
  '^ERR P0001 \[kassa:acc_none\].* \| 0:40000$');

-- ---------- (D) «Ortiqcha sarfni qoplash» chiqim orderi ----------
select zz.chk('D1 qarzdan katta — rad (summa va qarz bilan); qarz yo''q xodim, sinov kassasi (o''z doirasi) — «qoplanadigan ortiqcha sarf yo''q»; hujjat yozilmaydi',
  zz.req('r-d1-0001', 'out_overspend', 'staff:st1', 50000) || ' | ' || zz.req('r-d1-0002', 'out_overspend', 'teachers:tch1', 1000) || ' | '
  || zz.req('r-d1-0003', 'out_overspend', 'staff:st1', 1000, '{"desk":"sinov"}') || ' | ' || (select count(*) from public.cash_docs where "clientRef" like 'r-d1-%'),
  '^ERR P0001 \[kassa:due_over\].*\(50000 so''m\).*\(ortiqcha sarf: 40000 so''m\).* \| ERR P0001 \[kassa:due_none\].* \| ERR P0001 \[kassa:due_none\].* \| 0$');
select zz.put('D2a', zz.req('r-d2-0001', 'out_overspend', 'staff:st1', 30000, '{"purposeArticle":"ZZ-99"}'));
select zz.put('D2b', zz.req('r-d2-0002', 'out_overspend', 'staff:st1', 30000));
select zz.chk('D2 so''rov: 2-ro''yxat tasdig''i kerak (Direktor — yo''q); qator Dt 6970 Kt 5010, statiya OP-07, naqd; maqsad maydoni (faqat hisobdorga avansda) — e''tiborsiz',
  zz.f(zz.get('D2a'), 'status') || ':' || zz.f(zz.get('D2a'), 'needsList2') || ':' || zz.f(zz.get('D2a'), 'needsDirector')
  || ':' || coalesce(zz.js(zz.get('D2a')) -> 'sourceSnapshot' ->> 'purposeArticle', '-')
  || ' | ' || (select string_agg(l.debit || ':' || l.credit || ':' || l."articleId" || ':' || l.cash, ',') from public.cash_doc_lines l where l."docId" = zz.id('D2a')),
  '^draft:true:false:- \| 6970:5010:OP-07:true$');
select zz.put('D3', left(zz.appr('U_FM', zz.id('D2a')), 0) || left(zz.appr('U_FM', zz.id('D2b')), 0) || zz.f(zz.pay('U_KAS', zz.id('D2a')), 'status') || ':' || zz.due('staff:st1')
  || ' | ' || zz.pay('U_KAS', zz.id('D2b')) || ' | ' || zz.status(zz.id('D2b')) || ':' || zz.due('staff:st1'));
select zz.chk('D3 ikki tasdiqlangan so''rov (30 000 + 30 000, qarz 40 000): birinchisi beriladi (qarz 10 000), ikkinchisi pul berishda rad (kassa:due_over)',
  zz.get('D3'), '^posted:10000 \| ERR P0001 \[kassa:due_over\].*\(30000 so''m\).*\(ortiqcha sarf: 10000 so''m\).* \| approved:10000$');
select zz.chk('D4 kassir oynasi va nazorat ro''yxati: qarzimiz 10 000',
  (select trim_scale((j ->> 'due')::numeric)::text from (select zz.js(zz.as('U_KAS', $q$select public.kassa_staff_open('main', 'staff:st1')::text$q$)) j) q)
  || ':' || (select string_agg(trim_scale((d ->> 'due')::numeric)::text, ',') from jsonb_array_elements(zz.checks() -> 'accDue') d), '^10000:10000$');
select zz.chk('D5 ortiqcha sarfi qoplangan hisobot bekor qilinmaydi (kassa:due_used) — avval qoplash orderi',
  zz.avoid('U_FM', zz.id('O1'), 'Xato kiritilgan hisobot') || ' | ' || zz.status(zz.id('O1')) || ':' || zz.nexp(zz.id('O1')),
  '^ERR P0001 \[kassa:due_used\].* \| posted:2:70000$');
select zz.chk('D6 qoplash orderi bekor qilindi (qarz 40 000) — so''ng hisobot ham: xarajatlar olib tashlandi, qarz 0, qoldiq 30 000 ga qaytdi',
  zz.f(zz.cancel('U_KAS', zz.id('D2b'), 'Kerak emas'), 'status') || ':' || zz.f(zz.void('U_FM', zz.id('D2a'), 'Xato berilgan'), 'status') || ':' || zz.due('staff:st1')
  || ' | ' || zz.f(zz.avoid('U_FM', zz.id('O1'), 'Xato kiritilgan hisobot'), 'status') || ':' || zz.due('staff:st1') || ':' || zz.open('staff:st1') || ':' || zz.nexp(zz.id('O1')),
  '^cancelled:void:40000 \| void:0:30000:0:0$');
select zz.put('O6', zz.rep('U_FM', 'adv-o6-0001', 'staff:st1', '[{"articleId":"EX-20","amount":50000,"note":"Chek 9, 01.02"}]'));
select zz.chk('D7 qayta kiritildi (50 000, qoldiq 30 000) va tasdiqlandi: qarzimiz 20 000, qoldiq 0',
  zz.f(zz.get('O6'), 'overspend') || ':' || zz.f(zz.appr('U_ACC', zz.id('O6')), 'status') || ':' || zz.due('staff:st1') || ':' || zz.open('staff:st1') || ' | ' || zz.lines(zz.id('O6')),
  '^20000:posted:20000:0 \| 1:EX-20:30000:4230:-,2:EX-20:20000:6970:overspend$');
-- o'qituvchiga avans (maqsadi — kanselyariya), hisobotsiz qoladi
select zz.put('T1', zz.req('adv-t1-0001', 'out_accountable', 'teachers:tch1', 100000, '{"purposeArticle":"EX-32"}'));
select zz.chk('T1 o''qituvchiga 100 000 avans berildi', zz.f(left(zz.appr('U_FM', zz.id('T1')), 0) || zz.pay('U_KAS', zz.id('T1')), 'status') || ':' || zz.open('teachers:tch1'), '^posted:100000$');
select zz.chk('K1 1-kun yopildi', zz.f(zz.close('2027-02-01'), 'day', 'status'), '^closed$');

-- ---------- 2-kun (seshanba): st2 ga ikkinchi avans (oldingisi hisobotsiz — Direktor ham) ----------
select zz.clock('2027-02-02 10:00+05');
select zz.put('B3', zz.req('adv-b3-0001', 'out_accountable', 'staff:st2', 40000, '{"purposeArticle":"EX-32"}'));
select zz.chk('B3 hisobotsiz qoldiq (30 000) bor — Direktor tasdig''i ham; berildi, qoldiq 70 000',
  zz.f(zz.get('B3'), 'needsDirector') || ':' || zz.f(left(zz.appr('U_FM', zz.id('B3')), 0) || left(zz.appr('U_DIR', zz.id('B3')), 0) || zz.pay('U_KAS', zz.id('B3')), 'status')
  || ':' || zz.open('staff:st2'), '^true:posted:70000$');
select zz.chk('K2 2-kun yopildi', zz.f(zz.close('2027-02-02'), 'day', 'status'), '^closed$');

-- ---------- 3-kun (chorshanba): st2 qaytimi ----------
select zz.clock('2027-02-03 10:00+05');
select zz.chk('B4 qaytim 35 000 — qoldiq 35 000',
  zz.f(zz.rpc('U_KAS', 'kassa_receipt', '{"op":"in_acc_return","amount":35000,"partyType":"employee","partyId":"staff:st2","basis":"Qaytim","clientRef":"r-b4-ret1"}'), 'status')
  || ':' || zz.open('staff:st2'), '^posted:35000$');
select zz.chk('K3 3-kun yopildi', zz.f(zz.close('2027-02-03'), 'day', 'status'), '^closed$');

-- ---------- 5-kun (juma): RP-07 ----------
select zz.clock('2027-02-05 10:00+05');
select zz.put('T2', zz.rep('U_FM', 'adv-t2-0001', 'teachers:tch1', '[{"articleId":"EX-32","amount":30000,"note":"Chek 11, 04.02"}]'));
select zz.chk('C1 RP-07 ro''yxat (kassir): eng eski yopilmagan avans bo''yicha — o''qituvchi (01.02, 4 ish kuni — muddati o''tgan, hisoboti tasdiq kutmoqda), st2 (FIFO: 02.02 avansi, 3 kun), st1 (faqat qarzimiz)',
  (select string_agg((x ->> 'partyId') || ':' || (x ->> 'name') || ':' || trim_scale((x ->> 'open')::numeric) || ':' || trim_scale((x ->> 'due')::numeric) || ':' || (x ->> 'pending')
                     || ':' || coalesce(x ->> 'since', '-') || ':' || coalesce(x ->> 'workDays', '-') || ':' || (x ->> 'overdue'), ' ; ' order by o)
     from jsonb_array_elements(zz.js(zz.card('U_KAS', '')) -> 'list') with ordinality t(x, o)),
  '^teachers:tch1:Sinov O''qituvchi:100000:0:true:2027-02-01:4:true ; staff:st2:Sinov Ta''minotchi:35000:0:false:2027-02-02:3:false ; staff:st1:Sinov Zavxoz:0:20000:false:-:-:false$');
select zz.put('C2', zz.card('U_FM', 'staff:st1'));
select zz.chk('C2 kartochka (st1): qoldiq 0, qarzimiz 20 000, yopilmagan avans yo''q; hujjatlar — avans (maqsadi bilan), qaytim, 3 hisobot (4230 / 6970 qismlari); bekor qilinganlar yo''q',
  zz.f(zz.get('C2'), 'party', 'id') || ':' || zz.f(zz.get('C2'), 'party', 'name') || ':' || zz.f(zz.get('C2'), 'party', 'left') || ' | ' || zz.f(zz.get('C2'), 'open') || ':' || zz.f(zz.get('C2'), 'due')
  || ' | ' || jsonb_array_length(zz.js(zz.get('C2')) -> 'aging') || ':' || coalesce(zz.js(zz.get('C2')) ->> 'pending', '-')
  || ' | ' || (select string_agg((x ->> 'op') || ':' || trim_scale((x ->> 'amount')::numeric) || ':' || trim_scale((x ->> 'acc')::numeric) || ':' || trim_scale((x ->> 'due')::numeric)
                                 || coalesce(':' || (x ->> 'purposeArticle'), ''), ', ' order by x ->> 'op', (x ->> 'amount')::numeric, (x ->> 'acc')::numeric)
                 from jsonb_array_elements(zz.js(zz.get('C2')) -> 'items') x),
  '^staff:st1:Sinov Zavxoz:false \| 0:20000 \| 0:- \| in_acc_return:20000:20000:0, nc_adv_report:50000:30000:20000, nc_adv_report:50000:50000:0, nc_adv_report:200000:200000:0, out_accountable:300000:300000:0:EX-20$');
select zz.put('C3', zz.card('U_KAS', 'staff:st2'));
select zz.chk('C3 kartochka (st2) FIFO: hisobot 20 000 + qaytim 35 000 avval 01.02 avansini (50 000) yopadi — 02.02 avansidan 35 000 qolgan (maqsadi, 3 ish kuni)',
  zz.f(zz.get('C3'), 'open') || ':' || zz.f(zz.get('C3'), 'due') || ' | '
  || (select string_agg((a ->> 'day') || ':' || trim_scale((a ->> 'amount')::numeric) || ':' || trim_scale((a ->> 'remaining')::numeric) || ':' || coalesce(a ->> 'purposeArticle', '-')
                        || ':' || (a ->> 'workDays') || ':' || (a ->> 'overdue'), ', ' order by a ->> 'day') from jsonb_array_elements(zz.js(zz.get('C3')) -> 'aging') a)
  || ' | ' || jsonb_array_length(zz.js(zz.get('C3')) -> 'items'),
  '^35000:0 \| 2027-02-02:40000:35000:EX-32:3:false \| 4$');
select zz.put('C4', zz.card('U_ACC', 'teachers:tch1'));
select zz.chk('C4 kartochka (o''qituvchi): tasdiq kutayotgan hisobot (summa, kirituvchi); yopilmagan avans — muddati o''tgan; hujjatlar — faqat o''tkazilganlar (kutayotgan hisobot ularda yo''q)',
  zz.f(zz.get('C4'), 'pending', 'amount') || ':' || zz.f(zz.get('C4'), 'pending', 'requestedBy') || ':' || zz.f(zz.get('C4'), 'pending', 'requestedByName') || ':' || zz.f(zz.get('C4'), 'pending', 'overspend')
  || ' | ' || (select string_agg((a ->> 'day') || ':' || trim_scale((a ->> 'amount')::numeric) || ':' || trim_scale((a ->> 'remaining')::numeric) || ':' || coalesce(a ->> 'purposeArticle', '-')
                                 || ':' || (a ->> 'workDays') || ':' || (a ->> 'overdue'), ', ') from jsonb_array_elements(zz.js(zz.get('C4')) -> 'aging') a)
  || ' | ' || (select string_agg(x ->> 'op', ',') from jsonb_array_elements(zz.js(zz.get('C4')) -> 'items') x),
  '^30000:U_FM:Sinov Moliyachi:0 \| 2027-02-01:100000:100000:EX-32:4:true \| out_accountable$');
select zz.chk('C4b oy oxiri ro''yxati (fevral): tasdiq kutayotgan avans hisoboti — ogohlantirish (soni, summasi)',
  (select (i ->> 'level') || ':' || (i ->> 'n') || ':' || trim_scale((i ->> 'sum')::numeric)
     from jsonb_array_elements(zz.js(zz.as('U_DIR', $q$select public.kassa_month_check('main', '2027-02')::text$q$)) -> 'items') i where i ->> 'code' = 'advPending'),
  '^warn:1:30000$');
-- Direktor ham hisobdor bo'lishi mumkin: o'qituvchi kartasi bog'langan ikkinchi Direktor hisobi (to'qima)
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles", "staffRefType", "staffRefId")
  values ('U_DIR2','d2@x','Sinov Direktor Ikki','director','active','[]','teacher','tch1');
set local session_replication_role = origin;
select zz.chk('C4c hisobdorning o''zi bo''lgan Direktor: o''z avans hisoboti «Tasdiqlash» navbatida yo''q va uni tasdiqlay olmaydi (kassa:self_report); boshqa Direktorda — bor',
  zz.toappr('U_DIR2') || ':' || zz.toappr('U_DIR') || ' | ' || zz.appr('U_DIR2', zz.id('T2')) || ' | ' || zz.status(zz.id('T2')),
  '^0:1 \| ERR 42501 \[kassa:self_report\].* \| draft$');
select zz.chk('C5 rollar: o''qituvchi va anon — yo''q; noma''lum xodim — rad',
  zz.card('U_TCH', '') || ' | ' || zz.card(null, '') || ' | ' || zz.card('U_FM', 'staff:zz'),
  '^ERR 42501.* \| ERR 42501.* \| ERR 22023 \[kassa:party\]');
select zz.chk('C6 ichki funksiyalar mijozga yopiq',
  zz.as('U_DIR', $q$select app.kassa_acc_due('staff:st1')::text$q$) || ' | ' || zz.as('U_DIR', $q$select count(*)::text from app.kassa_acc_fifo('staff:st1')$q$) || ' | '
  || zz.as('U_DIR', $q$select app.kassa_acc_part('x', 'nc_adv_report', 1)::text$q$) || ' | ' || zz.as('U_DIR', format('select app.kassa_adv_approve(%L, %L)::text', zz.id('T2'), 'U_DIR')),
  '^ERR 42501.* \| ERR 42501.* \| ERR 42501.* \| ERR 42501');

-- ---------- (F) 4230 formulalari: nazorat ro'yxati va oylik to'plam E4 ----------
select zz.chk('F1 nazorat ro''yxati (hisobdorlar, asosiy kassa): st2 — berildi 90 000, qaytdi 35 000, hisobot 20 000, qoldiq 35 000',
  (select (a ->> 'partyId') || ':' || trim_scale((a ->> 'given')::numeric) || ':' || trim_scale((a ->> 'returned')::numeric) || ':' || trim_scale((a ->> 'reported')::numeric) || ':' || trim_scale((a ->> 'balance')::numeric)
     from jsonb_array_elements(zz.checks() -> 'accountable') a where a ->> 'partyId' = 'staff:st2'), '^staff:st2:90000:35000:20000:35000$');
select zz.chk('F2 oylik to''plam E4 (st1, fevral): hisobot ustuni — faqat 4230 qismi (200 000 + 50 000 + 30 000), oy oxiri 0 (ortiqcha sarf — 6970)',
  (select trim_scale((a ->> 'opening')::numeric) || ':' || trim_scale((a ->> 'issued')::numeric) || ':' || trim_scale((a ->> 'returned')::numeric) || ':' || trim_scale((a ->> 'reported')::numeric)
          || ':' || trim_scale((a ->> 'closing')::numeric)
     from jsonb_array_elements(zz.js(zz.as('U_DIR', $q$select public.kassa_month_pack('main', '2027-02')::text$q$)) -> 'advances') a where a ->> 'partyName' = 'Sinov Zavxoz'),
  '^0:300000:20000:280000:0$');

-- ---------- (D) qarzni to'liq qoplash ----------
select zz.put('D8', zz.req('r-d8-0001', 'out_overspend', 'staff:st1', 20000));
select zz.chk('D8 qolgan 20 000 qoplandi: qarz 0; nazorat ro''yxatida va RP-07 ro''yxatida st1 yo''q',
  zz.f(left(zz.appr('U_FM', zz.id('D8')), 0) || zz.pay('U_KAS', zz.id('D8')), 'status') || ':' || zz.due('staff:st1') || ':' || (zz.checks() -> 'accDue')::text
  || ':' || coalesce((select string_agg(x ->> 'partyId', ',') from jsonb_array_elements(zz.js(zz.card('U_KAS', '')) -> 'list') x where x ->> 'partyId' = 'staff:st1'), 'yo''q'),
  '^posted:0:\[\]:yo''q$');
select zz.clock('2027-03-01 10:00+05');
select zz.chk('F3 keyingi oy (mart) E4: st1 — oy boshiga qoldiq 0 (fevral hisobotlarining faqat 4230 qismi ayirilgan), harakat yo''q — qatori yo''q; st2 — 35 000',
  coalesce((select string_agg(a ->> 'partyName', ',') from jsonb_array_elements(zz.js(zz.as('U_DIR', $q$select public.kassa_month_pack('main', '2027-03')::text$q$)) -> 'advances') a
             where a ->> 'partyName' = 'Sinov Zavxoz'), 'yo''q')
  || ' | ' || (select trim_scale((a ->> 'opening')::numeric)::text from jsonb_array_elements(zz.js(zz.as('U_DIR', $q$select public.kassa_month_pack('main', '2027-03')::text$q$)) -> 'advances') a
                where a ->> 'partyName' = 'Sinov Ta''minotchi'),
  '^yo''q \| 35000$');
select zz.chk('D9 kartochkada qoplash orderi: 4230 ga ta''siri yo''q, 6970 qismi 20 000',
  (select string_agg((x ->> 'form') || ':' || trim_scale((x ->> 'acc')::numeric) || ':' || trim_scale((x ->> 'due')::numeric), ',')
     from jsonb_array_elements(zz.js(zz.card('U_FM', 'staff:st1')) -> 'items') x where x ->> 'op' = 'out_overspend'), '^KO2:0:20000$');
select zz.chk('K5 5-kun yopildi', zz.f(zz.close('2027-02-05'), 'day', 'status'), '^closed$');
select zz.put('C7', zz.req('adv-c7-0001', 'out_accountable', 'staff:st1', 50000, '{"purposeArticle":"EX-20"}'));
select zz.chk('C7 ortiqcha sarfdan keyin yangi avans (50 000): FIFO — eski avansni hisobotlarning faqat 4230 qismi yopgan, yangisi butunligicha ochiq',
  zz.f(left(zz.appr('U_FM', zz.id('C7')), 0) || zz.pay('U_KAS', zz.id('C7')), 'status') || ':' || zz.open('staff:st1') || ' | '
  || (select string_agg((a ->> 'day') || ':' || trim_scale((a ->> 'amount')::numeric) || ':' || trim_scale((a ->> 'remaining')::numeric), ', ')
        from jsonb_array_elements(zz.js(zz.card('U_FM', 'staff:st1')) -> 'aging') a),
  '^posted:50000 \| 2027-03-01:50000:50000$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else '  (olindi: ' || coalesce(left(got, 500), '<null>') || ' ; kutilgan: ' || pat || ')' end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' from zz.res;
rollback;
