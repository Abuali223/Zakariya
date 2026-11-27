-- =====================================================================
-- test-inv-parts.sql — moliya ish rejasi F2.7 (qaror FD-32): hisob-faktura TARKIBI (inv-parts.sql) sinovi:
--   (K) KORPUS — admin.html computeTuition hisoblagan fakturalar (assets/js/inv-parts.test.mjs bilan BIR XIL ro'yxat): baza saqlangan
--       maydonlardan (summa, asosiy narx, foiz, bonus ishorasi, izoh, kasal kun summasi) aynan sahifadagi yalpi va tarkibni chiqaradi
--       (app.inv_parts_infer — JS Math.round va IEEE double bilan bir xil yaxlitlash), sahifa yuborgan tarkib qat'iy tekshiruvdan o'tadi;
--   (T) trigger trg_invoice_zparts: mos tarkib saqlanadi (0 qismlar olib tashlanadi), mos kelmagan / yuborilmagani — server chiqaradi
--       (faktura yozuvi rad etilmaydi); to'lov va holat bo'yicha bekor qilish tarkibga tegmaydi; summa o'zgarsa — qayta chiqariladi;
--       reprice_invoice meta; «other» faqat serverdan; toifa turi foizga mos; huquq (moliya menejeri — rad);
--   (Q) davr qulfi va buxgalter ko'rinishi — faqat kassa moduli («--dev») bazasida;
--   (B) eski fakturalarni to'ldirish (app.inv_parts_backfill): tarkibsiz va mos kelmaydigan qatorlar, to'g'rilariga tegilmaydi; 2026-11 dan
--       amaldagi tushuntirilmagan qatorlar soni va ID lari (bekor qilingan va oldingi oylar sanalmaydi).
--   Migratsiya EMAS. FAQAT BO'SH sinov bazasida, zanjirdan keyin (jonli zanjir ham, «--dev» ham):
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-inv-parts.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. Ma'lumot to'qima. Natija: har tekshiruv PASS/FAIL + JAMI.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) or exists (select 1 from public.invoices) then
    raise exception 'test-inv-parts.sql: baza bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
set local client_min_messages = error;   -- trigger ogohlantirishlari (mos kelmagan yuborilgan tarkib) sinov chiqishini to'ldirmasin
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
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- faktura tarkibi: «yalpi|{tur: so'm}»
create or replace function zz.inv(p_id text) returns text language sql as $$
  select coalesce((select coalesce("grossAmount"::text, '-') || '|' || coalesce("discountParts"::text, '-') from public.invoices where id = p_id), 'yo''q') $$;
-- summa va holat (alohida so'rov — bitta SELECT ichida oldingi chaqiruvlar yozganini ko'radi)
create or replace function zz.st(p_id text) returns text language sql as $$
  select coalesce((select amount::text || '/' || coalesce(status, '') from public.invoices where id = p_id), 'yo''q') $$;
-- himoyalangan (SECURITY DEFINER) funksiya ichidan yozuv — RLS chetlanadi, qo'riqchi chaqiruvchi rolini tekshiradi
create or replace function zz.defupd(p_id text) returns text language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.invoices set "grossAmount" = 2800000, "discountParts" = '{"monitoring20": 400000}' where id = p_id;
  return 'ok';
end $$;
grant usage on schema zz to authenticated;
grant execute on function zz.defupd(text) to authenticated;
-- tizim nomidan yozish (migratsiya / server kabi) — xato matni bilan
create or replace function zz.sys(p_q text) returns text language plpgsql as $$
declare r text;
begin
  begin execute p_q into r; exception when others then r := 'ERR ' || sqlstate || ' ' || sqlerrm; end;
  return coalesce(r, 'ok');
end $$;
create or replace function zz.ins(p_id text, p_amount numeric, p_base numeric, p_pct numeric, p_info text, p_sick numeric, p_g numeric, p_parts jsonb,
                                  p_month text default '2026-11', p_status text default 'pending', p_bonus text default null) returns text
language sql as $$
  select zz.sys(format('insert into public.invoices (id, "studentId", month, amount, "paidAmount", status, provider, "baseAmount", discount, "discountInfo", '
    || '"isGrant", "pctApplied", "sickDaysApplied", "sickAmount", "bonusRef", "grossAmount", "discountParts") values (%L, %L, %L, %s, 0, %L, %L, %s, %s, %L, %s, %s, 0, %s, %L, %s, %s) returning ''ok''',
    p_id, split_part(p_id, '__', 1), p_month, p_amount, p_status, case when p_pct >= 1 then 'grant' else '' end, coalesce(p_base::text, 'null'),
    coalesce((p_base - p_amount)::text, '0'), p_info, (p_pct >= 1)::text, coalesce(p_pct::text, '0'), coalesce(p_sick::text, '0'), p_bonus,
    coalesce(p_g::text, 'null'), coalesce(quote_literal(p_parts::text) || '::jsonb', 'null'))) $$;

-- ---------- Urug' (triggerlarsiz) ----------
set local session_replication_role = replica;
insert into public.users (id, email, name, role, status, "extraRoles") values
  ('U_DIR','d@x','Sinov Direktor','director','active','[]'), ('U_FM','f@x','Sinov Moliyachi','finance_mgr','active','[]'),
  ('U_ACC','a@x','Sinov Buxgalter','accountant','active','[]');
insert into public.config (id, "invoiceCreators") values ('finance', 'director')
  on conflict (id) do update set "invoiceCreators" = excluded."invoiceCreators";
set local session_replication_role = origin;

-- =====================================================================
-- (K) KORPUS — admin.html bilan umumiy. Blokni qo'lda tahrirlamang: INV_PARTS_WRITE=1 node --test assets/js/inv-parts.test.mjs
-- =====================================================================
create temp table kc as
  select x.* from jsonb_to_recordset((select $korpus$[
{"id":"full.none","amount":1930000,"base":2950000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · Referral −900000","sick":120000,"gross":2950000,"parts":{"sick":120000,"referral":900000}},
{"id":"full.sib","amount":2300000,"base":3333333,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":3333333,"parts":{"siblings":333333,"sick":400000,"referral":300000}},
{"id":"full.mon92","amount":899998,"base":1999997,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":1999997,"parts":{"monitoring20":399999,"sick":400000,"referral":300000}},
{"id":"full.mon100","amount":0,"base":3000000,"pct":1,"bonus":"","info":"Monitoring 100 · 100% (o‘tgan oy)","sick":0,"gross":3000000,"parts":{"monitoring100":3000000}},
{"id":"full.new95","amount":2240000,"base":2950000,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 3 kasal kun (−120000)","sick":120000,"gross":2950000,"parts":{"monitoring20":590000,"sick":120000}},
{"id":"full.new100ok","amount":0,"base":3333333,"pct":1,"bonus":"B-IQ-1006","info":"Monitoring 100 · tasdiqlangan (2026-10-05)","sick":0,"gross":3333333,"parts":{"monitoring100":3333333}},
{"id":"full.new100no","amount":899998,"base":1999997,"pct":0.2,"bonus":"","info":"Monitoring 90+ · 20% (100 ball bonusi tasdiqlanmagan) + 10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":1999997,"parts":{"monitoring20":399999,"sick":400000,"referral":300000}},
{"id":"full.tchild","amount":1200000,"base":3000000,"pct":0.5,"bonus":"","info":"Xodim farzandi 50% · Referral −300000","sick":0,"gross":3000000,"parts":{"teacher_child":1500000,"referral":300000}},
{"id":"full.olymp","amount":0,"base":2950000,"pct":1,"bonus":"","info":"100% grant (olimpiada/ijtimoiy)","sick":0,"gross":2950000,"parts":{"grant":2950000}},
{"id":"full.contract","amount":2000000,"base":2000000,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa)","sick":0,"gross":2000000,"parts":{}},
{"id":"full.contractOdd","amount":334567.5,"base":1234567.5,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa) · Referral −900000","sick":0,"gross":1234567.5,"parts":{"referral":900000}},
{"id":"full.fallback","amount":1600000,"base":2500000,"pct":0,"bonus":"","info":"Referral −900000","sick":0,"gross":2500000,"parts":{"referral":900000}},
{"id":"join16.none","amount":1326032,"base":3333333,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · 11/21 ish kuni (prorata) · Referral −300000","sick":120000,"gross":1746032,"parts":{"sick":120000,"referral":300000}},
{"id":"join16.sib","amount":242856,"base":1999997,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · 11/21 ish kuni (prorata) · Referral −300000","sick":400000,"gross":1047617,"parts":{"siblings":104761,"sick":400000,"referral":300000}},
{"id":"join16.mon92","amount":857143,"base":3000000,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 10 kasal kun (−400000) · 11/21 ish kuni (prorata)","sick":400000,"gross":1571429,"parts":{"monitoring20":314286,"sick":400000}},
{"id":"join16.mon100","amount":0,"base":2950000,"pct":1,"bonus":"","info":"Monitoring 100 · 100% (o‘tgan oy) · 11/21 ish kuni (prorata)","sick":0,"gross":1545238,"parts":{"monitoring100":1545238}},
{"id":"join16.new95","amount":376825,"base":3333333,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 3 kasal kun (−120000) · 11/21 ish kuni (prorata) · Referral −900000","sick":120000,"gross":1746032,"parts":{"monitoring20":349207,"sick":120000,"referral":900000}},
{"id":"join16.new100ok","amount":0,"base":1999997,"pct":1,"bonus":"B-IQ-1018","info":"Monitoring 100 · tasdiqlangan (2026-10-05) · 11/21 ish kuni (prorata)","sick":0,"gross":1047617,"parts":{"monitoring100":1047617}},
{"id":"join16.new100no","amount":557143,"base":3000000,"pct":0.2,"bonus":"","info":"Monitoring 90+ · 20% (100 ball bonusi tasdiqlanmagan) + 10 kasal kun (−400000) · 11/21 ish kuni (prorata) · Referral −300000","sick":400000,"gross":1571429,"parts":{"monitoring20":314286,"sick":400000,"referral":300000}},
{"id":"join16.tchild","amount":472619,"base":2950000,"pct":0.5,"bonus":"","info":"Xodim farzandi 50% · 11/21 ish kuni (prorata) · Referral −300000","sick":0,"gross":1545238,"parts":{"teacher_child":772619,"referral":300000}},
{"id":"join16.olymp","amount":0,"base":3333333,"pct":1,"bonus":"","info":"100% grant (olimpiada/ijtimoiy) · 11/21 ish kuni (prorata)","sick":0,"gross":1746032,"parts":{"grant":1746032}},
{"id":"join16.contract","amount":147619,"base":2000000,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa) · 11/21 ish kuni (prorata) · Referral −900000","sick":0,"gross":1047619,"parts":{"referral":900000}},
{"id":"join16.contractOdd","amount":346678,"base":1234567.5,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa) · 11/21 ish kuni (prorata) · Referral −300000","sick":0,"gross":646678,"parts":{"referral":300000}},
{"id":"join16.fallback","amount":1009524,"base":2500000,"pct":0,"bonus":"","info":"11/21 ish kuni (prorata) · Referral −300000","sick":0,"gross":1309524,"parts":{"referral":300000}},
{"id":"left03.none","amount":0,"base":1999997,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · 2/21 ish kuni (prorata) · Referral −70476","sick":120000,"gross":190476,"parts":{"sick":120000,"referral":70476}},
{"id":"left03.sib","amount":17143,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 6 kasal kun (−240000; yana 4 kun keyingi fakturada) · 2/21 ish kuni (prorata)","sick":240000,"gross":285714,"parts":{"siblings":28571,"sick":240000}},
{"id":"left03.mon92","amount":0,"base":2950000,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":280952,"parts":{"monitoring20":56190,"sick":224762}},
{"id":"left03.mon100","amount":0,"base":3333333,"pct":1,"bonus":"","info":"Monitoring 100 · 100% (o‘tgan oy) · 2/21 ish kuni (prorata)","sick":0,"gross":317460,"parts":{"monitoring100":317460}},
{"id":"left03.new95","amount":32381,"base":1999997,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 3 kasal kun (−120000) · 2/21 ish kuni (prorata)","sick":120000,"gross":190476,"parts":{"monitoring20":38095,"sick":120000}},
{"id":"left03.new100ok","amount":0,"base":3000000,"pct":1,"bonus":"B-IQ-1030","info":"Monitoring 100 · tasdiqlangan (2026-10-05) · 2/21 ish kuni (prorata)","sick":0,"gross":285714,"parts":{"monitoring100":285714}},
{"id":"left03.new100no","amount":0,"base":2950000,"pct":0.2,"bonus":"","info":"Monitoring 90+ · 20% (100 ball bonusi tasdiqlanmagan) + 10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":280952,"parts":{"monitoring20":56190,"sick":224762}},
{"id":"left03.tchild","amount":158730,"base":3333333,"pct":0.5,"bonus":"","info":"Xodim farzandi 50% · 2/21 ish kuni (prorata)","sick":0,"gross":317460,"parts":{"teacher_child":158730}},
{"id":"left03.olymp","amount":0,"base":1999997,"pct":1,"bonus":"","info":"100% grant (olimpiada/ijtimoiy) · 2/21 ish kuni (prorata)","sick":0,"gross":190476,"parts":{"grant":190476}},
{"id":"left03.contract","amount":190476,"base":2000000,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa) · 2/21 ish kuni (prorata)","sick":0,"gross":190476,"parts":{}},
{"id":"left03.contractOdd","amount":0,"base":1234567.5,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa) · 2/21 ish kuni (prorata) · Referral −117578","sick":0,"gross":117578,"parts":{"referral":117578}},
{"id":"left03.fallback","amount":0,"base":2500000,"pct":0,"bonus":"","info":"2/21 ish kuni (prorata) · Referral −238095","sick":0,"gross":238095,"parts":{"referral":238095}},
{"id":"frz20.none","amount":2022857,"base":3000000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · 15/21 ish kuni (prorata)","sick":120000,"gross":2142857,"parts":{"sick":120000}},
{"id":"frz20.sib","amount":596429,"base":2950000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · 15/21 ish kuni (prorata) · Referral −900000","sick":400000,"gross":2107143,"parts":{"siblings":210714,"sick":400000,"referral":900000}},
{"id":"frz20.mon92","amount":1204761,"base":3333333,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 10 kasal kun (−400000) · 15/21 ish kuni (prorata) · Referral −300000","sick":400000,"gross":2380952,"parts":{"monitoring20":476191,"sick":400000,"referral":300000}},
{"id":"frz20.mon100","amount":0,"base":1999997,"pct":1,"bonus":"","info":"Monitoring 100 · 100% (o‘tgan oy) · 15/21 ish kuni (prorata)","sick":0,"gross":1428569,"parts":{"monitoring100":1428569}},
{"id":"frz20.new95","amount":1294286,"base":3000000,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 3 kasal kun (−120000) · 15/21 ish kuni (prorata) · Referral −300000","sick":120000,"gross":2142857,"parts":{"monitoring20":428571,"sick":120000,"referral":300000}},
{"id":"frz20.new100ok","amount":0,"base":2950000,"pct":1,"bonus":"B-IQ-1042","info":"Monitoring 100 · tasdiqlangan (2026-10-05) · 15/21 ish kuni (prorata)","sick":0,"gross":2107143,"parts":{"monitoring100":2107143}},
{"id":"frz20.new100no","amount":604761,"base":3333333,"pct":0.2,"bonus":"","info":"Monitoring 90+ · 20% (100 ball bonusi tasdiqlanmagan) + 10 kasal kun (−400000) · 15/21 ish kuni (prorata) · Referral −900000","sick":400000,"gross":2380952,"parts":{"monitoring20":476191,"sick":400000,"referral":900000}},
{"id":"frz20.tchild","amount":114285,"base":1999997,"pct":0.5,"bonus":"","info":"Xodim farzandi 50% · 15/21 ish kuni (prorata) · Referral −600000","sick":0,"gross":1428569,"parts":{"teacher_child":714284,"referral":600000}},
{"id":"frz20.olymp","amount":0,"base":3000000,"pct":1,"bonus":"","info":"100% grant (olimpiada/ijtimoiy) · 15/21 ish kuni (prorata)","sick":0,"gross":2142857,"parts":{"grant":2142857}},
{"id":"frz20.contract","amount":1128571,"base":2000000,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa) · 15/21 ish kuni (prorata) · Referral −300000","sick":0,"gross":1428571,"parts":{"referral":300000}},
{"id":"frz20.contractOdd","amount":881834,"base":1234567.5,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa) · 15/21 ish kuni (prorata)","sick":0,"gross":881834,"parts":{}},
{"id":"frz20.fallback","amount":1785714,"base":2500000,"pct":0,"bonus":"","info":"15/21 ish kuni (prorata)","sick":0,"gross":1785714,"parts":{}},
{"id":"pause.none","amount":1227619,"base":2950000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · 16/21 ish kuni (prorata) · Referral −900000","sick":120000,"gross":2247619,"parts":{"sick":120000,"referral":900000}},
{"id":"pause.sib","amount":1585714,"base":3333333,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · 16/21 ish kuni (prorata) · Referral −300000","sick":400000,"gross":2539682,"parts":{"siblings":253968,"sick":400000,"referral":300000}},
{"id":"pause.mon92","amount":519046,"base":1999997,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 10 kasal kun (−400000) · 16/21 ish kuni (prorata) · Referral −300000","sick":400000,"gross":1523807,"parts":{"monitoring20":304761,"sick":400000,"referral":300000}},
{"id":"pause.mon100","amount":0,"base":3000000,"pct":1,"bonus":"","info":"Monitoring 100 · 100% (o‘tgan oy) · 16/21 ish kuni (prorata)","sick":0,"gross":2285714,"parts":{"monitoring100":2285714}},
{"id":"pause.new95","amount":1678095,"base":2950000,"pct":0.2,"bonus":"","info":"Monitoring 90–99 · 20% (o‘tgan oy) + 3 kasal kun (−120000) · 16/21 ish kuni (prorata)","sick":120000,"gross":2247619,"parts":{"monitoring20":449524,"sick":120000}},
{"id":"pause.new100ok","amount":0,"base":3333333,"pct":1,"bonus":"B-IQ-1054","info":"Monitoring 100 · tasdiqlangan (2026-10-05) · 16/21 ish kuni (prorata)","sick":0,"gross":2539682,"parts":{"monitoring100":2539682}},
{"id":"pause.new100no","amount":519046,"base":1999997,"pct":0.2,"bonus":"","info":"Monitoring 90+ · 20% (100 ball bonusi tasdiqlanmagan) + 10 kasal kun (−400000) · 16/21 ish kuni (prorata) · Referral −300000","sick":400000,"gross":1523807,"parts":{"monitoring20":304761,"sick":400000,"referral":300000}},
{"id":"pause.tchild","amount":842857,"base":3000000,"pct":0.5,"bonus":"","info":"Xodim farzandi 50% · 16/21 ish kuni (prorata) · Referral −300000","sick":0,"gross":2285714,"parts":{"teacher_child":1142857,"referral":300000}},
{"id":"pause.olymp","amount":0,"base":2950000,"pct":1,"bonus":"","info":"100% grant (olimpiada/ijtimoiy) · 16/21 ish kuni (prorata)","sick":0,"gross":2247619,"parts":{"grant":2247619}},
{"id":"pause.contract","amount":1523810,"base":2000000,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa) · 16/21 ish kuni (prorata)","sick":0,"gross":1523810,"parts":{}},
{"id":"pause.contractOdd","amount":40623,"base":1234567.5,"pct":0,"bonus":"","info":"Kontrakt (belgilangan summa) · 16/21 ish kuni (prorata) · Referral −900000","sick":0,"gross":940623,"parts":{"referral":900000}},
{"id":"pause.fallback","amount":1004762,"base":2500000,"pct":0,"bonus":"","info":"16/21 ish kuni (prorata) · Referral −900000","sick":0,"gross":1904762,"parts":{"referral":900000}},
{"id":"full.none.s0.r0","amount":3000000,"base":3000000,"pct":0,"bonus":"","info":"Chegirmasiz","sick":0,"gross":3000000,"parts":{}},
{"id":"full.none.s0.rEx","amount":2700000,"base":3000000,"pct":0,"bonus":"","info":"Referral −300000","sick":0,"gross":3000000,"parts":{"referral":300000}},
{"id":"full.none.s0.rNew","amount":2700000,"base":3000000,"pct":0,"bonus":"","info":"Referral −300000","sick":0,"gross":3000000,"parts":{"referral":300000}},
{"id":"full.none.s0.rBoth","amount":2100000,"base":3000000,"pct":0,"bonus":"","info":"Referral −900000","sick":0,"gross":3000000,"parts":{"referral":900000}},
{"id":"full.none.s3.r0","amount":2880000,"base":3000000,"pct":0,"bonus":"","info":"3 kasal kun (−120000)","sick":120000,"gross":3000000,"parts":{"sick":120000}},
{"id":"full.none.s3.rEx","amount":2580000,"base":3000000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · Referral −300000","sick":120000,"gross":3000000,"parts":{"sick":120000,"referral":300000}},
{"id":"full.none.s3.rNew","amount":2580000,"base":3000000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · Referral −300000","sick":120000,"gross":3000000,"parts":{"sick":120000,"referral":300000}},
{"id":"full.none.s3.rBoth","amount":1980000,"base":3000000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · Referral −900000","sick":120000,"gross":3000000,"parts":{"sick":120000,"referral":900000}},
{"id":"full.none.s10.r0","amount":2600000,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000)","sick":400000,"gross":3000000,"parts":{"sick":400000}},
{"id":"full.none.s10.rEx","amount":2300000,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":3000000,"parts":{"sick":400000,"referral":300000}},
{"id":"full.none.s10.rNew","amount":2300000,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":3000000,"parts":{"sick":400000,"referral":300000}},
{"id":"full.none.s10.rBoth","amount":1700000,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · Referral −900000","sick":400000,"gross":3000000,"parts":{"sick":400000,"referral":900000}},
{"id":"full.none.s10old.r0","amount":2600000,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000)","sick":400000,"gross":3000000,"parts":{"sick":400000}},
{"id":"full.none.s10old.rEx","amount":2300000,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":3000000,"parts":{"sick":400000,"referral":300000}},
{"id":"full.none.s10old.rNew","amount":2300000,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":3000000,"parts":{"sick":400000,"referral":300000}},
{"id":"full.none.s10old.rBoth","amount":1700000,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · Referral −900000","sick":400000,"gross":3000000,"parts":{"sick":400000,"referral":900000}},
{"id":"full.sib.s0.r0","amount":2700000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10%","sick":0,"gross":3000000,"parts":{"siblings":300000}},
{"id":"full.sib.s0.rEx","amount":2400000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% · Referral −300000","sick":0,"gross":3000000,"parts":{"siblings":300000,"referral":300000}},
{"id":"full.sib.s0.rNew","amount":2400000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% · Referral −300000","sick":0,"gross":3000000,"parts":{"siblings":300000,"referral":300000}},
{"id":"full.sib.s0.rBoth","amount":1800000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% · Referral −900000","sick":0,"gross":3000000,"parts":{"siblings":300000,"referral":900000}},
{"id":"full.sib.s3.r0","amount":2580000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 3 kasal kun (−120000)","sick":120000,"gross":3000000,"parts":{"siblings":300000,"sick":120000}},
{"id":"full.sib.s3.rEx","amount":2280000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 3 kasal kun (−120000) · Referral −300000","sick":120000,"gross":3000000,"parts":{"siblings":300000,"sick":120000,"referral":300000}},
{"id":"full.sib.s3.rNew","amount":2280000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 3 kasal kun (−120000) · Referral −300000","sick":120000,"gross":3000000,"parts":{"siblings":300000,"sick":120000,"referral":300000}},
{"id":"full.sib.s3.rBoth","amount":1680000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 3 kasal kun (−120000) · Referral −900000","sick":120000,"gross":3000000,"parts":{"siblings":300000,"sick":120000,"referral":900000}},
{"id":"full.sib.s10.r0","amount":2300000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000)","sick":400000,"gross":3000000,"parts":{"siblings":300000,"sick":400000}},
{"id":"full.sib.s10.rEx","amount":2000000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":3000000,"parts":{"siblings":300000,"sick":400000,"referral":300000}},
{"id":"full.sib.s10.rNew","amount":2000000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":3000000,"parts":{"siblings":300000,"sick":400000,"referral":300000}},
{"id":"full.sib.s10.rBoth","amount":1400000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · Referral −900000","sick":400000,"gross":3000000,"parts":{"siblings":300000,"sick":400000,"referral":900000}},
{"id":"full.sib.s10old.r0","amount":2300000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000)","sick":400000,"gross":3000000,"parts":{"siblings":300000,"sick":400000}},
{"id":"full.sib.s10old.rEx","amount":2000000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":3000000,"parts":{"siblings":300000,"sick":400000,"referral":300000}},
{"id":"full.sib.s10old.rNew","amount":2000000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · Referral −300000","sick":400000,"gross":3000000,"parts":{"siblings":300000,"sick":400000,"referral":300000}},
{"id":"full.sib.s10old.rBoth","amount":1400000,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · Referral −900000","sick":400000,"gross":3000000,"parts":{"siblings":300000,"sick":400000,"referral":900000}},
{"id":"left03.none.s0.r0","amount":285714,"base":3000000,"pct":0,"bonus":"","info":"2/21 ish kuni (prorata)","sick":0,"gross":285714,"parts":{}},
{"id":"left03.none.s0.rEx","amount":0,"base":3000000,"pct":0,"bonus":"","info":"2/21 ish kuni (prorata) · Referral −285714","sick":0,"gross":285714,"parts":{"referral":285714}},
{"id":"left03.none.s0.rNew","amount":285714,"base":3000000,"pct":0,"bonus":"","info":"2/21 ish kuni (prorata)","sick":0,"gross":285714,"parts":{}},
{"id":"left03.none.s0.rBoth","amount":0,"base":3000000,"pct":0,"bonus":"","info":"2/21 ish kuni (prorata) · Referral −285714","sick":0,"gross":285714,"parts":{"referral":285714}},
{"id":"left03.none.s3.r0","amount":165714,"base":3000000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · 2/21 ish kuni (prorata)","sick":120000,"gross":285714,"parts":{"sick":120000}},
{"id":"left03.none.s3.rEx","amount":0,"base":3000000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · 2/21 ish kuni (prorata) · Referral −165714","sick":120000,"gross":285714,"parts":{"sick":120000,"referral":165714}},
{"id":"left03.none.s3.rNew","amount":165714,"base":3000000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · 2/21 ish kuni (prorata)","sick":120000,"gross":285714,"parts":{"sick":120000}},
{"id":"left03.none.s3.rBoth","amount":0,"base":3000000,"pct":0,"bonus":"","info":"3 kasal kun (−120000) · 2/21 ish kuni (prorata) · Referral −165714","sick":120000,"gross":285714,"parts":{"sick":120000,"referral":165714}},
{"id":"left03.none.s10.r0","amount":5714,"base":3000000,"pct":0,"bonus":"","info":"7 kasal kun (−280000; yana 3 kun keyingi fakturada) · 2/21 ish kuni (prorata)","sick":280000,"gross":285714,"parts":{"sick":280000}},
{"id":"left03.none.s10.rEx","amount":0,"base":3000000,"pct":0,"bonus":"","info":"7 kasal kun (−280000; yana 3 kun keyingi fakturada) · 2/21 ish kuni (prorata) · Referral −5714","sick":280000,"gross":285714,"parts":{"sick":280000,"referral":5714}},
{"id":"left03.none.s10.rNew","amount":5714,"base":3000000,"pct":0,"bonus":"","info":"7 kasal kun (−280000; yana 3 kun keyingi fakturada) · 2/21 ish kuni (prorata)","sick":280000,"gross":285714,"parts":{"sick":280000}},
{"id":"left03.none.s10.rBoth","amount":0,"base":3000000,"pct":0,"bonus":"","info":"7 kasal kun (−280000; yana 3 kun keyingi fakturada) · 2/21 ish kuni (prorata) · Referral −5714","sick":280000,"gross":285714,"parts":{"sick":280000,"referral":5714}},
{"id":"left03.none.s10old.r0","amount":0,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":285714,"parts":{"sick":285714}},
{"id":"left03.none.s10old.rEx","amount":0,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":285714,"parts":{"sick":285714}},
{"id":"left03.none.s10old.rNew","amount":0,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":285714,"parts":{"sick":285714}},
{"id":"left03.none.s10old.rBoth","amount":0,"base":3000000,"pct":0,"bonus":"","info":"10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":285714,"parts":{"sick":285714}},
{"id":"left03.sib.s0.r0","amount":257143,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% · 2/21 ish kuni (prorata)","sick":0,"gross":285714,"parts":{"siblings":28571}},
{"id":"left03.sib.s0.rEx","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% · 2/21 ish kuni (prorata) · Referral −257143","sick":0,"gross":285714,"parts":{"siblings":28571,"referral":257143}},
{"id":"left03.sib.s0.rNew","amount":257143,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% · 2/21 ish kuni (prorata)","sick":0,"gross":285714,"parts":{"siblings":28571}},
{"id":"left03.sib.s0.rBoth","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% · 2/21 ish kuni (prorata) · Referral −257143","sick":0,"gross":285714,"parts":{"siblings":28571,"referral":257143}},
{"id":"left03.sib.s3.r0","amount":137143,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 3 kasal kun (−120000) · 2/21 ish kuni (prorata)","sick":120000,"gross":285714,"parts":{"siblings":28571,"sick":120000}},
{"id":"left03.sib.s3.rEx","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 3 kasal kun (−120000) · 2/21 ish kuni (prorata) · Referral −137143","sick":120000,"gross":285714,"parts":{"siblings":28571,"sick":120000,"referral":137143}},
{"id":"left03.sib.s3.rNew","amount":137143,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 3 kasal kun (−120000) · 2/21 ish kuni (prorata)","sick":120000,"gross":285714,"parts":{"siblings":28571,"sick":120000}},
{"id":"left03.sib.s3.rBoth","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 3 kasal kun (−120000) · 2/21 ish kuni (prorata) · Referral −137143","sick":120000,"gross":285714,"parts":{"siblings":28571,"sick":120000,"referral":137143}},
{"id":"left03.sib.s10.r0","amount":17143,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 6 kasal kun (−240000; yana 4 kun keyingi fakturada) · 2/21 ish kuni (prorata)","sick":240000,"gross":285714,"parts":{"siblings":28571,"sick":240000}},
{"id":"left03.sib.s10.rEx","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 6 kasal kun (−240000; yana 4 kun keyingi fakturada) · 2/21 ish kuni (prorata) · Referral −17143","sick":240000,"gross":285714,"parts":{"siblings":28571,"sick":240000,"referral":17143}},
{"id":"left03.sib.s10.rNew","amount":17143,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 6 kasal kun (−240000; yana 4 kun keyingi fakturada) · 2/21 ish kuni (prorata)","sick":240000,"gross":285714,"parts":{"siblings":28571,"sick":240000}},
{"id":"left03.sib.s10.rBoth","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 6 kasal kun (−240000; yana 4 kun keyingi fakturada) · 2/21 ish kuni (prorata) · Referral −17143","sick":240000,"gross":285714,"parts":{"siblings":28571,"sick":240000,"referral":17143}},
{"id":"left03.sib.s10old.r0","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":285714,"parts":{"siblings":28571,"sick":257143}},
{"id":"left03.sib.s10old.rEx","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":285714,"parts":{"siblings":28571,"sick":257143}},
{"id":"left03.sib.s10old.rNew","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":285714,"parts":{"siblings":28571,"sick":257143}},
{"id":"left03.sib.s10old.rBoth","amount":0,"base":3000000,"pct":0.1,"bonus":"","info":"Aka-uka · 10% + 10 kasal kun (−400000) · 2/21 ish kuni (prorata)","sick":400000,"gross":285714,"parts":{"siblings":28571,"sick":257143}}
]$korpus$::jsonb)) as x(id text, amount numeric, base numeric, pct numeric, bonus text, info text,
         sick numeric, gross numeric, parts jsonb);
create temp table kr as
  select kc.id, app.inv_parts_infer(kc.amount, kc.base, kc.pct, kc.bonus, kc.info, kc.sick) as v,
         app.inv_parts_check(kc.gross, kc.parts, kc.amount, kc.pct, kc.bonus, kc.info, kc.sick, true) as why, kc.gross, kc.parts
    from kc;
select zz.chk('K0 korpus o''qildi (sahifa hisoblagan fakturalar soni)', (select count(*)::text from kc), '^1[2-9][0-9]$|^[2-9][0-9]{2}$');
select zz.chk('K1 baza har korpus fakturasidan sahifadagi yalpi va tarkibni AYNAN chiqaradi (aniq — x)',
  (select count(*) filter (where (v ->> 'g')::numeric = gross and v -> 'p' = parts and (v ->> 'x')::boolean)::text || '/' || count(*)::text
          || coalesce(' xato: ' || string_agg(id, ', ') filter (where not ((v ->> 'g')::numeric = gross and v -> 'p' = parts and (v ->> 'x')::boolean)), '')
     from kr),
  '^([0-9]+)/\1$');
select zz.chk('K2 sahifa tarkibi qat''iy tekshiruvdan o''tadi (turlar, toifa = foiz, kasal kun, summa)',
  (select count(*) filter (where why is null)::text || '/' || count(*)::text || coalesce(' xato: ' || string_agg(id || '=' || why, ', ') filter (where why is not null), '') from kr),
  '^([0-9]+)/\1$');
select zz.chk('K3 korpusda barcha turlar bor (toifa beshta, tavsiya, kasal kun) va qisman oy',
  (select string_agg(distinct k, ',' order by k) from kc, jsonb_object_keys(kc.parts) k) || ' | '
  || (select count(*) from kc where info ~ 'ish kuni \(prorata\)')::text,
  '^grant,monitoring100,monitoring20,referral,siblings,sick,teacher_child \| [1-9][0-9]*$');

select zz.chk('K4 JS Math.round bilan bir xil: kasr ≥ 0,5 — yuqoriga (juftga emas), manfiyda ham +∞ tomonga; IEEE double qoldig''i',
  app.inv_jsround(2.5)::text || ' ' || app.inv_jsround(999998.5)::text || ' ' || app.inv_jsround(-2.5)::text || ' ' || app.inv_jsround(1.4999999999999998::float8)::text
  || ' ' || app.inv_jsround(11::float8 * (3::float8 / 22::float8))::text,
  '^3 999999 -2 1 2$');

-- =====================================================================
-- (T) trigger
-- =====================================================================
select zz.chk('T1 mos tarkib saqlanadi, 0 qism olib tashlanadi',
  zz.ins('S-1__2026-11', 2620000, 3000000, 0.1, 'Aka-uka · 10% + 2 kasal kun (−80000)', 80000, 3000000, '{"siblings": 300000, "sick": 80000, "referral": 0}')
  || ' ' || zz.inv('S-1__2026-11'),
  '^ok 3000000\|\{"sick": 80000, "siblings": 300000\}$');
select zz.chk('T1b 0 qism olib tashlanadi — aniq tarkib (qisman oy granti, izohda ulushsiz) server taxminiga almashtirilmaydi',
  zz.ins('S-1b__2026-11', 0, 3000000, 1, '100% grant (olimpiada/ijtimoiy)', 0, 1571429, '{"grant": 1571429, "sick": 0}', '2026-11', 'paid') || ' ' || zz.inv('S-1b__2026-11'),
  '^ok 1571429\|\{"grant": 1571429\}$');
select zz.chk('T2 tarkib yuborilmasa — server chiqaradi',
  zz.ins('S-2__2026-11', 2400000, 3000000, 0.2, 'Monitoring 90–99 · 20% (o‘tgan oy)', 0, null, null) || ' ' || zz.inv('S-2__2026-11'),
  '^ok 3000000\|\{"monitoring20": 600000\}$');
select zz.chk('T3 summa mos emas (yalpi − qismlar ≠ summa) — rad etilmaydi, server chiqaradi',
  zz.ins('S-3__2026-11', 2700000, 3000000, 0.1, 'Aka-uka · 10%', 0, 3000000, '{"siblings": 200000}') || ' ' || zz.inv('S-3__2026-11'),
  '^ok 3000000\|\{"siblings": 300000\}$');
select zz.chk('T4 «other» faqat serverdan — sahifa yuborsa rad etilmaydi, server chiqaradi',
  zz.ins('S-4__2026-11', 2700000, 3000000, 0, 'Referral −300000', 0, 3000000, '{"other": 300000}') || ' ' || zz.inv('S-4__2026-11'),
  '^ok 3000000\|\{"referral": 300000\}$');
select zz.chk('T5 toifa turi foizga mos emas (10% — xodim farzandi deb) — server chiqaradi',
  zz.ins('S-5__2026-11', 2700000, 3000000, 0.1, 'Aka-uka · 10%', 0, 3000000, '{"teacher_child": 300000}') || ' ' || zz.inv('S-5__2026-11'),
  '^ok 3000000\|\{"siblings": 300000\}$');
select zz.chk('T6 noto''g''ri shakl (ro''yxat; faqat yalpi; manfiy; noma''lum tur; kasal kun summadan katta) — server chiqaradi',
  zz.ins('S-6a__2026-11', 3000000, 3000000, 0, 'Chegirmasiz', 0, 3000000, '[]') || zz.inv('S-6a__2026-11') || ' '
  || zz.ins('S-6b__2026-11', 3000000, 3000000, 0, 'Chegirmasiz', 0, 3100000, null) || zz.inv('S-6b__2026-11') || ' '
  || zz.ins('S-6c__2026-11', 2700000, 3000000, 0.1, 'Aka-uka · 10%', 0, 2400000, '{"siblings": -300000}') || zz.inv('S-6c__2026-11') || ' '
  || zz.ins('S-6d__2026-11', 2700000, 3000000, 0.1, 'Aka-uka · 10%', 0, 3000000, '{"chegirma": 300000}') || zz.inv('S-6d__2026-11') || ' '
  || zz.ins('S-6e__2026-11', 2620000, 3000000, 0.1, 'Aka-uka · 10% + 2 kasal kun (−80000)', 80000, 3000000, '{"siblings": 260000, "sick": 120000}') || zz.inv('S-6e__2026-11'),
  '^ok3000000\|\{\} ok3000000\|\{\} ok3000000\|\{"siblings": 300000\} ok3000000\|\{"siblings": 300000\} ok3000000\|\{"sick": 80000, "siblings": 300000\}$');
select zz.chk('T6f manfiy yalpi — mos emas, server chiqaradi (summa ham manfiy bo''lsa ham)',
  zz.ins('S-6f__2026-11', -300000, 3000000, 0, 'Chegirmasiz', 0, -300000, '{}') || ' ' || zz.inv('S-6f__2026-11'),
  '^ok 3000000\|\{"other": 3300000\}$');
-- bonus qo'riqchisi '' ni NULL qiladi (trigger undan keyin ishlaydi); eski qoidadagi «Monitoring 100» — matn bo'yicha
select zz.chk('T7 100 % — «Monitoring 100» matni / bonus ishorasi — monitoring100, aks holda grant; qisman oyda yalpi = ulush',
  zz.ins('S-7a__2026-11', 0, 3000000, 1, 'Monitoring 100 · 100% (o‘tgan oy)', 0, null, null, '2026-11', 'paid', '') || zz.inv('S-7a__2026-11') || ' '
  || zz.ins('S-7b__2026-11', 0, 3000000, 1, '100% grant (olimpiada/ijtimoiy) · 11/21 ish kuni (prorata)', 0, null, null, '2026-11', 'paid') || zz.inv('S-7b__2026-11') || ' '
  || zz.ins('S-7c__2026-11', 0, 3000000, 1, '100% grant (olimpiada/ijtimoiy) · 11/21 ish kuni (prorata)', 0, 1571429, '{"grant": 1571429}', '2026-11', 'paid') || zz.inv('S-7c__2026-11'),
  '^ok3000000\|\{"monitoring100": 3000000\} ok1571429\|\{"grant": 1571429\} ok1571429\|\{"grant": 1571429\}$');

-- yangilash yo'llari
select zz.chk('T8 to''lov qo''llanishi (paidAmount / holat) — tarkib o''zgarmaydi (serverdagi «other» ham)',
  zz.sys($q$update public.invoices set "discountParts" = '{"other": 100000, "siblings": 300000}', "grossAmount" = 3000000, amount = 2600000 where id = 'S-3__2026-11' returning 'ok'$q$)
  || ' ' || zz.inv('S-3__2026-11') || ' '
  || zz.sys($q$update public.invoices set "paidAmount" = 1000000, status = 'partial' where id = 'S-3__2026-11' returning 'ok'$q$) || ' ' || zz.inv('S-3__2026-11'),
  '^ok 3000000\|\{"other": 100000, "siblings": 300000\} ok 3000000\|\{"other": 100000, "siblings": 300000\}$');
select zz.chk('T9 summa / foiz o''zgarsa (tarkib yuborilmasa) — saqlangan tarkib endi mos emas, qayta chiqariladi',
  zz.sys($q$update public.invoices set amount = 2400000, "pctApplied" = 0.2, "discountInfo" = 'Monitoring 90–99 · 20% (o‘tgan oy)' where id = 'S-1__2026-11' returning 'ok'$q$)
  || ' ' || zz.inv('S-1__2026-11'),
  '^ok 3000000\|\{"monitoring20": 600000\}$');
select zz.chk('T10 summa bilan birga mos tarkib yuborilsa — saqlanadi; keyin mos kelmagani («other») yuborilsa — server chiqaradi (shu natija)',
  zz.sys($q$update public.invoices set amount = 2250000, "pctApplied" = 0.2, "discountInfo" = 'Monitoring 90–99 · 20% (o‘tgan oy) · Referral −150000', "grossAmount" = 3000000, "discountParts" = '{"monitoring20": 600000, "referral": 150000}' where id = 'S-1__2026-11' returning 'ok'$q$)
  || ' ' || zz.inv('S-1__2026-11') || ' '
  || zz.sys($q$update public.invoices set "grossAmount" = 2400000, "discountParts" = '{"other": 150000}' where id = 'S-1__2026-11' returning 'ok'$q$)
  || ' ' || zz.inv('S-1__2026-11'),
  '^ok 3000000\|\{"referral": 150000, "monitoring20": 600000\} ok 3000000\|\{"referral": 150000, "monitoring20": 600000\}$');
select zz.chk('T11 holat bo''yicha bekor qilish (izoh «[holat] …») — summa va tarkib o''zgarmaydi',
  zz.sys($q$update public.invoices set status = 'canceled', "discountInfo" = '[holat] chiqgan — shu oy hisob-faktura talab qilinmaydi' where id = 'S-1__2026-11' returning 'ok'$q$)
  || ' ' || zz.inv('S-1__2026-11'),
  '^ok 3000000\|\{"referral": 150000, "monitoring20": 600000\}$');
select zz.chk('T11b eski qoidadagi «Monitoring 100» (bonus ishorasisiz) holat bo''yicha bekor qilinsa — turi o''zgarmaydi (izoh «[holat] …» bo''lsa ham)',
  zz.ins('S-7d__2026-11', 0, 3000000, 1, 'Monitoring 100 · 100% (o‘tgan oy)', 0, null, null, '2026-11', 'paid') || ' '
  || zz.as('U_DIR', $q$select (public.reprice_invoice('S-7d__2026-11', 0, '{"statusReason": "chiqgan"}'::jsonb, true) ->> 'ok')$q$)
  || ' ' || zz.inv('S-7d__2026-11') || ' ' || zz.st('S-7d__2026-11'),
  '^ok true 3000000\|\{"monitoring100": 3000000\} 0/canceled$');
select zz.chk('T12 ikkala ustun NULL — «server qayta hisoblasin» (eski fakturalarni to''ldirish yo''li)',
  zz.sys($q$update public.invoices set "grossAmount" = null, "discountParts" = null where id = 'S-2__2026-11' returning 'ok'$q$) || ' ' || zz.inv('S-2__2026-11'),
  '^ok 3000000\|\{"monitoring20": 600000\}$');

select zz.chk('T12b izoh o''zgarib (summa o''zgarmay) saqlangan aniq tarkib hamon mos bo''lsa — tegilmaydi (server taxmini bilan almashtirilmaydi)',
  zz.sys($q$update public.invoices set "discountInfo" = '100% grant (olimpiada/ijtimoiy)' where id = 'S-7c__2026-11' returning 'ok'$q$) || ' ' || zz.inv('S-7c__2026-11'),
  '^ok 1571429\|\{"grant": 1571429\}$');

-- reprice_invoice (Direktor) — sahifadagi «↻ Qayta hisoblash» yo'li
select zz.chk('T13 reprice_invoice meta bilan tarkib — saqlanadi; meta da tarkib yo''q — yangi maydonlardan chiqariladi',
  zz.as('U_DIR', $q$select (public.reprice_invoice('S-5__2026-11', 2520000, '{"discountInfo": "Aka-uka · 10% + Referral −180000", "pctApplied": 0.1, "baseAmount": 3000000, "grossAmount": 3000000, "discountParts": {"siblings": 300000, "referral": 180000}}'::jsonb, false) ->> 'ok')$q$)
  || ' ' || zz.inv('S-5__2026-11') || ' '
  || zz.as('U_DIR', $q$select (public.reprice_invoice('S-4__2026-11', 257143, '{"discountInfo": "Aka-uka · 10% · 2/21 ish kuni (prorata)", "pctApplied": 0.1, "baseAmount": 3000000}'::jsonb, false) ->> 'ok')$q$)
  || ' ' || zz.inv('S-4__2026-11'),
  '^true 3000000\|\{"referral": 180000, "siblings": 300000\} true 285714\|\{"siblings": 28571\}$');
select zz.chk('T13b reprice_invoice: meta dagi aniq tarkib (qisman oy granti) server taxminidan ustun — saqlanadi',
  zz.as('U_DIR', $q$select (public.reprice_invoice('S-7a__2026-11', 0, '{"discountInfo": "100% grant (olimpiada/ijtimoiy)", "pctApplied": 1, "isGrant": true, "baseAmount": 3000000, "grossAmount": 1571429, "discountParts": {"grant": 1571429}}'::jsonb, false) ->> 'ok')$q$)
  || ' ' || zz.inv('S-7a__2026-11'),
  '^true 1571429\|\{"grant": 1571429\}$');
select zz.chk('T14 reprice_invoice: yuborilgan tarkib mos emas — summa yangilanadi, tarkibni server chiqaradi; holat bo''yicha bekor — tarkib o''zgarmaydi',
  zz.as('U_DIR', $q$select (public.reprice_invoice('S-6c__2026-11', 2620000, '{"discountInfo": "Aka-uka · 10% + 2 kasal kun (−80000)", "pctApplied": 0.1, "sickAmount": 80000, "grossAmount": 3000000, "discountParts": {"siblings": 300000}}'::jsonb, false) ->> 'ok')$q$)
  || ' ' || zz.inv('S-6c__2026-11') || ' '
  || zz.as('U_DIR', $q$select (public.reprice_invoice('S-6c__2026-11', 0, '{"statusReason": "chiqgan"}'::jsonb, true) ->> 'ok')$q$)
  || ' ' || zz.inv('S-6c__2026-11') || ' ' || zz.st('S-6c__2026-11'),
  '^true 3000000\|\{"sick": 80000, "siblings": 300000\} true 3000000\|\{"sick": 80000, "siblings": 300000\} 2620000/canceled$');
select zz.chk('T15 moliya menejeri tarkibni o''zgartira olmaydi: to''g''ridan-to''g''ri — 0 qator (RLS), himoyalangan funksiya ichidan — qo''riqchi rad etadi',
  zz.as('U_FM', $q$with x as (update public.invoices set "grossAmount" = 2800000, "discountParts" = '{"siblings": 100000}' where id = 'S-2__2026-11' returning id) select count(*)::text from x$q$)
  || ' | ' || zz.as('U_FM', $q$select zz.defupd('S-2__2026-11')$q$) || ' | ' || zz.inv('S-2__2026-11'),
  '^0 \| ERR 42501 .*faqat Direktor yoki «↻ Qayta hisoblash».* \| 3000000\|\{"monitoring20": 600000\}$');

-- =====================================================================
-- (Q) davr qulfi va buxgalter ko'rinishi — kassa moduli bazasida
-- =====================================================================
select to_regprocedure('app.fin_lock_invoices()') is not null and to_regclass('public.invoices_acc') is not null as has_fin \gset
\if :has_fin
select zz.chk('Q0 tayyorgarlik: oktyabr fakturasi, davr 2026-10-31 gacha yopiq',
  zz.ins('S-9__2026-10', 2700000, 3000000, 0.1, 'Aka-uka · 10%', 0, null, null, '2026-10') || ' ' || zz.inv('S-9__2026-10') || ' '
  || zz.sys($q$update public.fin_org set "lockedThrough" = '2026-10-31' where id = 'main' returning 'ok'$q$),
  '^ok 3000000\|\{"siblings": 300000\} ok$');
select zz.chk('Q1 yopilgan oy: Direktor tarkibni o''zgartira olmaydi (fin:locked); to''lov qo''llanishi — mumkin',
  zz.as('U_DIR', $q$update public.invoices set "grossAmount" = 2700000, "discountParts" = '{}' where id = 'S-9__2026-10' returning 'ok'$q$) || ' | '
  || zz.as('U_DIR', $q$update public.invoices set "grossAmount" = null, "discountParts" = null where id = 'S-9__2026-10' returning 'ok'$q$) || ' | '
  || zz.as('U_DIR', $q$update public.invoices set "paidAmount" = 2700000, status = 'paid' where id = 'S-9__2026-10' returning 'ok'$q$) || ' | ' || zz.inv('S-9__2026-10'),
  '^ERR 42501 \[fin:locked\].* \| ERR 42501 \[fin:locked\].* \| ok \| 3000000\|\{"siblings": 300000\}$');
select zz.chk('Q2 buxgalter tarkibni invoices_acc orqali ko''radi',
  zz.as('U_ACC', $q$select "grossAmount"::text || '|' || "discountParts"::text from public.invoices_acc where id = 'S-9__2026-10'$q$),
  '^3000000\|\{"siblings": 300000\}$');
select zz.sys($q$update public.fin_org set "lockedThrough" = null where id = 'main' returning 'ok'$q$) as unlock_ok \gset
\else
select zz.chk('Q0 kassa moduli yo''q (jonli zanjir) — qulf va buxgalter ko''rinishi tekshirilmaydi', 'ok', '^ok$');
\endif

-- =====================================================================
-- (B) eski fakturalarni to'ldirish — triggerlarsiz yozilgan «eski» qatorlar
-- =====================================================================
set local session_replication_role = replica;
insert into public.invoices (id, "studentId", month, amount, "paidAmount", status, "baseAmount", "discountInfo", "pctApplied", "sickAmount", "grossAmount", "discountParts") values
  ('B-1__2026-11', 'B-1', '2026-11', 2700000, 0, 'pending', 3000000, 'Aka-uka · 10%', 0.1, 0, null, null),                           -- tarkibsiz
  ('B-2__2026-11', 'B-2', '2026-11', 2700000, 0, 'pending', 3000000, 'Aka-uka · 10%', 0.1, 0, 3000000, '{"siblings": 100000}'),    -- summaga mos emas
  ('B-3__2026-11', 'B-3', '2026-11', 2500000, 0, 'pending', 3000000, 'Aka-uka · 10%', 0.1, 0, null, null),                           -- tushuntirilmagan (other)
  ('B-4__2026-11', 'B-4', '2026-11', 2500000, 0, 'canceled', 3000000, '[holat] chiqgan — shu oy hisob-faktura talab qilinmaydi', 0.1, 0, null, null),
  ('B-5__2026-10', 'B-5', '2026-10', 2500000, 0, 'paid', 3000000, 'Aka-uka · 10%', 0.1, 0, null, null),                             -- oldingi oy
  ('B-6__2026-11', 'B-6', '2026-11', 2700000, 0, 'paid', 3000000, 'Aka-uka · 10%', 0.1, 0, 3000000, '{"siblings": 300000}'),       -- to'g'ri
  ('B-7__2026-09', 'B-7', '2026-09', 1800000, 0, 'paid', null, null, null, null, null, null),                                        -- asosiy narxsiz
  ('B-8__2026-11', 'B-8', '2026-11', 2900000, 0, 'partial', 3000000, 'Aka-uka · 10% + 2 kasal kun (−80000)', 0.1, 80000, null, null), -- chegirma summadan katta
  ('B-9__2026-11', 'B-9', '2026-11', 1333333.33, 0, 'pending', 1333333.33, 'Chegirmasiz', 0, 0, null, null);                  -- kasrli eski summa (yaxlitlash qoldig'i)
set local session_replication_role = origin;
select zz.chk('B1 to''ldirish: 8 qator yozildi (to''g''risi tegilmadi), 2026-11 dan amaldagi tushuntirilmaganlar — 2 ta (bekor va oktyabr sanalmaydi)',
  (select (r ->> 'updated') || '/' || (r ->> 'inexact') || '/' || (r -> 'ids')::text from (select app.inv_parts_backfill() r) z),
  '^8/2/\["B-3__2026-11", "B-8__2026-11"\]$');
select zz.chk('B2 natijalar: tarkibsiz va mos kelmagani — aniq; tushuntirilmagani — other; chegirma summadan katta — kamaytirildi; narxsiz — yalpi = summa; kasrli — qoldiq yalpiga',
  zz.inv('B-1__2026-11') || ' ' || zz.inv('B-2__2026-11') || ' ' || zz.inv('B-3__2026-11') || ' ' || zz.inv('B-4__2026-11') || ' '
  || zz.inv('B-5__2026-10') || ' ' || zz.inv('B-6__2026-11') || ' ' || zz.inv('B-7__2026-09') || ' ' || zz.inv('B-8__2026-11') || ' ' || zz.inv('B-9__2026-11'),
  '^3000000\|\{"siblings": 300000\} 3000000\|\{"siblings": 300000\} 3000000\|\{"other": 200000, "siblings": 300000\} 3000000\|\{"other": 200000, "siblings": 300000\} '
  || '3000000\|\{"other": 200000, "siblings": 300000\} 3000000\|\{"siblings": 300000\} 1800000\|\{\} 3000000\|\{"siblings": 100000\} 1333333\.33\|\{\}$');
select zz.chk('B3 qayta ishga tushirish — hech narsa yozilmaydi (barcha qatorlar mos); har faktura: summa = yalpi − Σ qismlar',
  (select (r ->> 'updated') || '/' || (r ->> 'inexact') from (select app.inv_parts_backfill() r) z) || ' | '
  || (select count(*) filter (where abs("grossAmount" - coalesce((select sum(value::numeric) from jsonb_each_text("discountParts")), 0) - amount) < 0.5)::text
             || '/' || count(*)::text from public.invoices),
  '^0/0 \| ([0-9]+)/\1$');
select zz.chk('B4 mijoz rollari to''ldirish va xulosa funksiyalarini chaqira olmaydi',
  zz.as('U_DIR', $q$select app.inv_parts_backfill()::text$q$) || ' | ' || zz.as('U_DIR', $q$select app.inv_parts_infer(1, 1, 0, '', '', 0)::text$q$),
  '^ERR 42501 .* \| ERR 42501 .*$');

-- ---------- Natija ----------
select case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else E'\n      got: ' || coalesce(got, '<null>') || E'\n      pat: ' || pat end
  from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || '/' || count(*) || ' o''tdi' || case when count(*) filter (where not ok) > 0 then ' — FAIL BOR' else ' — HAMMASI O''TDI' end
  from zz.res;
rollback;
