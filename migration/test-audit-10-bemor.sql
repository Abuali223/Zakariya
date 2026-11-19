-- =====================================================================
-- test-audit-10-bemor.sql — nurse-sick.sql sick_note_refund (audit 2026-11-18, G3) sinovi:
--   A2-03 ketgan / muzlatilgan o'quvchining kasal kunlarini avansga qaytarish fakturadagi qoida bilan bir xil: xodim farzandi (50%),
--         kontrakt va grant (olimpiada / ijtimoiy) — 'not_eligible'; toifa OXIRGI amaldagi fakturadan (admin.html sickExemptCat —
--         assets/js/davomat-bemor.test.mjs shu holatlarni JS'da tekshiradi); oddiy o'quvchi — avvalgidek.
--   A2-08 fakturaga sig'magan kasal kunlar: admin.html faqat to'liq sig'adigan kunlarni yozadi (sickNoteRefs / sickDaysApplied /
--         sickAmount = kunlar × stavka) — baza qabul qiladi, qolgan kunlar qo'llanmagan bo'lib qoladi va sick_note_refund ularni
--         qaytaradi; eski (hamma kun «qo'llangan», faktura 0) faktura «↻ Qayta hisoblash» (reprice_invoice) bilan tuzatiladi.
--   Har chaqiruv haqiqiy rol bilan (authenticated + JWT sub) — RLS va GRANT haqiqiy.
--   Migratsiya EMAS (run-all.sql'da yo'q). FAQAT BO'SH sinov bazasida, kanonik zanjirdan keyin:
--     bash migration/chain.sh --no-lock-timeout | psql -d sinov -q && psql -d sinov -X -f migration/test-audit-10-bemor.sql
--   Hamma narsa BITTA tranzaksiyada va oxirida ROLLBACK. O'quvchilar jadvali bo'sh bo'lmasa — darhol to'xtaydi. Ma'lumot to'qima.
-- =====================================================================
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
begin;
do $g$ begin
  if exists (select 1 from public.students) then
    raise exception 'test-audit-10-bemor.sql: o''quvchilar jadvali bo''sh emas — faqat bo''sh sinov bazasida ishga tushiring';
  end if;
end $g$;
set local iqror.migrating = '1';
insert into public.users (id, email, role, status) values
  ('U_DIR','d@example.org','director','active'), ('U_FM','fm@example.org','finance_mgr','active'), ('U_TR','tr@example.org','treasurer','active')
on conflict (id) do update set role = excluded.role, status = excluded.status;
-- O'tish oyi 2026-11: noyabr fakturasidan (oktyabr kasal kunlaridan) boshlab ma'lumotnoma qoidasi. Fakturalardan OLDIN (o'tish oyi qo'riqchisi).
insert into public.config (id, "sickApprovalFrom", "sickRate") values ('finance', '2026-11', 40000)
  on conflict (id) do update set "sickApprovalFrom" = excluded."sickApprovalFrom", "sickRate" = excluded."sickRate";
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "stopFrom", pauses) values
  ('IQ-0901','IQ-0901','Sinov Xodim Farzandi',5,'A','uz','chiqdi','2026-11-05','[]'),
  ('IQ-0902','IQ-0902','Sinov Kontrakt',5,'A','uz','muzlatilgan','2026-11-05','[]'),
  ('IQ-0903','IQ-0903','Sinov Grant',5,'A','uz','chiqdi','2026-11-05','[]'),
  ('IQ-0904','IQ-0904','Sinov Oddiy',5,'A','uz','chiqdi','2026-11-03','[]'),
  ('IQ-0905','IQ-0905','Sinov Monitoring',5,'A','uz','chiqdi','2026-11-05','[]'),
  ('IQ-0906','IQ-0906','Sinov Keyin Oddiy',5,'A','uz','chiqdi','2026-11-05','[]'),
  ('IQ-0907','IQ-0907','Sinov Keyin Xodim',5,'A','uz','chiqdi','2026-11-05','[]'),
  ('IQ-0908','IQ-0908','Sinov Bekor',5,'A','uz','chiqdi','2026-11-05','[]'),
  ('IQ-0909','IQ-0909','Sinov Eski Faktura',5,'A','uz','chiqdi','2026-11-03','[]')
on conflict (id) do nothing;
-- Ma'lumotnomalar (tasdiqlangan) va fakturalar — kiritish qo'riqchilarisiz (hamshira fayli / holat oqimi bu sinov mavzusi emas).
set local session_replication_role = replica;
insert into public.sick_notes (id, "studentId", "fromDay", "toDay", "schoolDays", status, "enteredBy", "reviewedBy") values
  ('N901','IQ-0901','2026-10-12','2026-10-16','["2026-10-12","2026-10-13","2026-10-14","2026-10-15","2026-10-16"]','approved','NURSE','U_FM'),
  ('N902','IQ-0902','2026-10-12','2026-10-16','["2026-10-12","2026-10-13","2026-10-14","2026-10-15","2026-10-16"]','approved','NURSE','U_FM'),
  ('N903','IQ-0903','2026-10-12','2026-10-16','["2026-10-12","2026-10-13","2026-10-14","2026-10-15","2026-10-16"]','approved','NURSE','U_FM'),
  ('N904','IQ-0904','2026-10-01','2026-10-16','["2026-10-01","2026-10-02","2026-10-05","2026-10-06","2026-10-07","2026-10-12","2026-10-13","2026-10-14","2026-10-15","2026-10-16"]','approved','NURSE','U_FM'),
  ('N905','IQ-0905','2026-10-12','2026-10-13','["2026-10-12","2026-10-13"]','approved','NURSE','U_FM'),
  ('N906','IQ-0906','2026-10-12','2026-10-13','["2026-10-12","2026-10-13"]','approved','NURSE','U_FM'),
  ('N907','IQ-0907','2026-10-12','2026-10-13','["2026-10-12","2026-10-13"]','approved','NURSE','U_FM'),
  ('N908','IQ-0908','2026-10-12','2026-10-13','["2026-10-12","2026-10-13"]','approved','NURSE','U_FM'),
  ('N909','IQ-0909','2026-10-01','2026-10-16','["2026-10-01","2026-10-02","2026-10-05","2026-10-06","2026-10-07","2026-10-12","2026-10-13","2026-10-14","2026-10-15","2026-10-16"]','approved','NURSE','U_FM');
-- Oktyabr fakturalari (kasal kunlar to'langan oy) va noyabr (oxirgi) fakturalari — admin.html computeTuition yozadigan ko'rinishda.
insert into public.invoices (id, "studentId", month, amount, "baseAmount", "paidAmount", status, "pctApplied", "discountInfo", "isGrant", provider, "bonusRef", "billedFrom", "billedTo") values
  ('IQ-0901__2026-10','IQ-0901','2026-10',1500000,3000000,1500000,'paid',0.5,'Xodim farzandi 50%',false,'','','2026-10-01','2026-10-31'),
  ('IQ-0901__2026-11','IQ-0901','2026-11',285714,3000000,0,'pending',0.5,'Xodim farzandi 50% · 4/21 ish kuni (prorata)',false,'','','2026-11-01','2026-11-05'),
  ('IQ-0902__2026-10','IQ-0902','2026-10',1000000,1000000,1000000,'paid',0,'Kontrakt (belgilangan summa)',false,'','','2026-10-01','2026-10-31'),
  ('IQ-0903__2026-10','IQ-0903','2026-10',3000000,3000000,3000000,'paid',0,'Chegirmasiz',false,'','','2026-10-01','2026-10-31'),
  ('IQ-0903__2026-11','IQ-0903','2026-11',0,3000000,0,'paid',1,'100% grant (olimpiada/ijtimoiy)',true,'grant','','2026-11-01','2026-11-05'),
  ('IQ-0904__2026-10','IQ-0904','2026-10',2400000,3000000,2400000,'paid',0.2,'Monitoring 90–99 · 20% (o‘tgan oy)',false,'','','2026-10-01','2026-10-31'),
  ('IQ-0905__2026-10','IQ-0905','2026-10',3000000,3000000,3000000,'paid',0,'Chegirmasiz',false,'','','2026-10-01','2026-10-31'),
  ('IQ-0905__2026-11','IQ-0905','2026-11',0,3000000,0,'paid',1,'Monitoring 100 · 100% (o‘tgan oy)',true,'grant','','2026-11-01','2026-11-05'),
  ('IQ-0906__2026-10','IQ-0906','2026-10',1500000,3000000,1500000,'paid',0.5,'Xodim farzandi 50%',false,'','','2026-10-01','2026-10-31'),
  ('IQ-0906__2026-11','IQ-0906','2026-11',571429,3000000,0,'pending',0,'4/21 ish kuni (prorata)',false,'','','2026-11-01','2026-11-05'),
  ('IQ-0907__2026-10','IQ-0907','2026-10',3000000,3000000,3000000,'paid',0,'Chegirmasiz',false,'','','2026-10-01','2026-10-31'),
  ('IQ-0907__2026-11','IQ-0907','2026-11',285714,3000000,0,'pending',0.5,'Xodim farzandi 50% · 4/21 ish kuni (prorata)',false,'','','2026-11-01','2026-11-05'),
  ('IQ-0908__2026-10','IQ-0908','2026-10',1500000,3000000,1500000,'paid',0.5,'Xodim farzandi 50%',false,'','','2026-10-01','2026-10-31'),
  ('IQ-0908__2026-11','IQ-0908','2026-11',571429,3000000,0,'canceled',0,'4/21 ish kuni (prorata)',false,'','','2026-11-01','2026-11-05'),
  ('IQ-0909__2026-10','IQ-0909','2026-10',2400000,3000000,2400000,'paid',0.2,'Monitoring 90–99 · 20% (o‘tgan oy)',false,'','','2026-10-01','2026-10-31');
set local session_replication_role = origin;
-- A2-08: noyabr fakturasi QO'RIQCHILAR BILAN (invoice_sick_guard + invoice_sick_apply). 3-noyabrda chiqqan: 2/21 ish kuni,
--   20% chegirma: round(2 400 000 × 2/21) = 228 571; 10 kun × 40 000 = 400 000 sig'maydi -> faqat 5 kun (200 000), qoldiq 28 571.
insert into public.invoices (id, "studentId", month, amount, "baseAmount", discount, "paidAmount", status, "pctApplied", "discountInfo", "isGrant", provider, "bonusRef",
                             "billedFrom", "billedTo", "sickDaysApplied", "sickAmount", "sickNoteRefs") values
  ('IQ-0904__2026-11','IQ-0904','2026-11',28571,3000000,2971429,0,'pending',0.2,'Monitoring 90–99 · 20% (o‘tgan oy) + 5 kasal kun (−200000; yana 5 kun keyingi fakturada) · 2/21 ish kuni (prorata)',false,'','',
   '2026-11-01','2026-11-03',5,200000,'{"N904":["2026-10-01","2026-10-02","2026-10-05","2026-10-06","2026-10-07"]}'),
  -- eski xatti-harakat (tuzatishdan oldin yozilgan): hamma 10 kun «qo'llangan», faktura 0 — ortig'i yo'qolgan
  ('IQ-0909__2026-11','IQ-0909','2026-11',0,3000000,3000000,0,'paid',0.2,'Monitoring 90–99 · 20% (o‘tgan oy) + 10 kasal kun (−400000) · 2/21 ish kuni (prorata)',false,'','',
   '2026-11-01','2026-11-03',10,400000,'{"N909":["2026-10-01","2026-10-02","2026-10-05","2026-10-06","2026-10-07","2026-10-12","2026-10-13","2026-10-14","2026-10-15","2026-10-16"]}');
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
-- Tizim nomidan (rolsiz) bitta buyruq: xato bo'lsa — 'ERR <sqlstate>' (tranzaksiya buzilmaydi).
create or replace function zz.try(p_q text) returns text language plpgsql as $$
begin
  execute p_q; return 'OK';
exception when others then return 'ERR ' || sqlstate || ' ' || sqlerrm;
end $$;
create table if not exists zz.res (n serial, name text, got text, pat text, ok boolean);
truncate zz.res;
create or replace function zz.chk(p_name text, p_got text, p_pat text) returns void language plpgsql as $$
begin insert into zz.res (name, got, pat, ok) values (p_name, p_got, p_pat, coalesce(p_got ~ p_pat, false)); end $$;
-- sick_note_refund natijasi qisqa ko'rinishda: ok/reason/category/days/amount
create or replace function zz.refund(p_uid text, p_id text) returns text language sql as $$
  select zz.as(p_uid, format($q$select concat_ws('/', r->>'ok', r->>'reason', r->>'category', r->>'days', r->>'amount') from (select public.sick_note_refund(%L) r) x$q$, p_id))
$$;

-- ===== A2-03: toifa — fakturadagi qoida bilan bir xil =====
select zz.chk('A01 xodim farzandi (oxirgi faktura 50%) — qaytarilmaydi', zz.refund('U_FM', 'N901'), '^false/not_eligible/teacher_child$');
select zz.chk('A02 kontrakt (muzlatilgan) — qaytarilmaydi', zz.refund('U_FM', 'N902'), '^false/not_eligible/contract$');
select zz.chk('A03 oxirgi faktura olimpiada granti (kasal oy oddiy bo''lsa ham) — qaytarilmaydi', zz.refund('U_FM', 'N903'), '^false/not_eligible/olympiad$');
select zz.chk('A04 oktyabr oddiy, noyabr 50% — o''qiyotganda ham noyabr fakturasida ayirilmasdi — qaytarilmaydi', zz.refund('U_FM', 'N907'), '^false/not_eligible/teacher_child$');
select zz.chk('A05 bekor qilingan oxirgi faktura hisobga olinmaydi (oktyabr 50%) — qaytarilmaydi', zz.refund('U_FM', 'N908'), '^false/not_eligible/teacher_child$');
select zz.chk('A06 toifa rad etilganda hech narsa o''zgarmaydi: avans, jurnal, qo''llangan kunlar',
  (select count(*) from public.student_credit where id in ('IQ-0901','IQ-0902','IQ-0903','IQ-0907','IQ-0908'))::text || '/' ||
  (select count(*) from public.credit_ledger where "studentId" in ('IQ-0901','IQ-0902','IQ-0903','IQ-0907','IQ-0908'))::text || '/' ||
  (select count(*) from public.sick_notes where id in ('N901','N902','N903','N907','N908') and "appliedDays" <> '{}'::jsonb)::text, '^0/0/0$');
select zz.chk('A07 oktyabr 50%, noyabr oddiy (noyabr fakturasi o''zi ayirardi) — qaytariladi', zz.refund('U_FM', 'N906'), '^true/2/80000$');
select zz.chk('A08 oxirgi faktura «Monitoring 100» — toifa emas (kunlar keyingi fakturaga qoldirilgan edi) — qaytariladi', zz.refund('U_FM', 'N905'), '^true/2/80000$');
select zz.chk('A09 g''aznachi — ruxsat yo''q (o''zgarmagan)', zz.refund('U_TR', 'N904'), '^ERR 42501');
select zz.chk('A10 direktor ham toifani chetlab o''tolmaydi', zz.refund('U_DIR', 'N901'), '^false/not_eligible/teacher_child$');

-- ===== A2-08: fakturaga sig'magan kunlar — qo'llanmagan bo'lib qoladi, avansga qaytariladi =====
select zz.chk('B01 faqat sig''adigan 5 kun yozilgan faktura qabul qilindi va o''sha 5 kun shu fakturaga belgilandi',
  (select count(*) filter (where e.value = to_jsonb('IQ-0904__2026-11'::text)) || '/' || count(*) from public.sick_notes n, jsonb_each(n."appliedDays") e where n.id = 'N904'), '^5/5$');
select zz.chk('B02 qo''riqchi: summa = kunlar × stavka (5 kun bilan 400 000 — rad)',
  zz.try($q$update public.invoices set "sickAmount" = 400000 where id = 'IQ-0904__2026-11'$q$), '^ERR 23514');
select zz.chk('B03 qolgan 5 kun (ketgan o''quvchi) — avansga: 5 × 40 000', zz.refund('U_FM', 'N904'), '^true/5/200000$');
-- Avansga tushgan 200 000 darhol ochiq qarzni yopadi (audit-10-tolov.sql app.credit_sweep, A4-03): noyabr fakturasidagi 28 571 qoldiq
--   (3-noyabrgacha o'qigan kunlari — haqiqiy qarz) to'lanadi, qolgani avansda.
select zz.chk('B04 avans va jurnal: sick_refund 200 000, shundan 28 571 noyabr qarziga; faktura to''landi',
  (select credit::text from public.student_credit where id = 'IQ-0904') || '/' ||
  (select string_agg(reason || ':' || delta::text, ',' order by delta desc) from public.credit_ledger where "studentId" = 'IQ-0904') || '/' ||
  (select status || ':' || "paidAmount"::text from public.invoices where id = 'IQ-0904__2026-11'),
  '^171429(\.0+)?/sick_refund:200000(\.0+)?,applied:-28571(\.0+)?/paid:28571(\.0+)?$');
select zz.chk('B05 10 kunning hammasi bir marta: 5 — faktura, 5 — avans',
  (select count(*) filter (where e.value = to_jsonb('IQ-0904__2026-11'::text)) || '/' || count(*) filter (where e.value #>> '{}' like 'credit:%')
     from public.sick_notes n, jsonb_each(n."appliedDays") e where n.id = 'N904'), '^5/5$');
select zz.chk('B06 qayta bosilsa — qaytariladigan kun yo''q', zz.refund('U_FM', 'N904'), '^false/nothing$');
-- Eski faktura (hamma kun «qo'llangan», faktura 0): avval qaytariladigan kun yo'q — ortig'i yo'qolgan edi
select zz.chk('B07 eski faktura: ortiqcha kunlar qo''llangan deb belgilangan — qaytarib bo''lmaydi', zz.refund('U_FM', 'N909'), '^false/nothing$');
-- «↻ Qayta hisoblash» (Direktor, reprice_invoice — admin.html yangi computeTuition natijasi bilan): 5 kun fakturada qoladi, 5 kun bo'shaydi
select zz.chk('B08 qayta hisoblash eski fakturani tuzatadi', zz.as('U_DIR', $q$select public.reprice_invoice('IQ-0909__2026-11', 28571,
  '{"discountInfo":"Monitoring 90–99 · 20% (o‘tgan oy) + 5 kasal kun (−200000; yana 5 kun keyingi fakturada) · 2/21 ish kuni (prorata)","discount":2971429,"baseAmount":3000000,"pctApplied":0.2,
    "sickDaysApplied":5,"sickAmount":200000,"sickNoteRefs":{"N909":["2026-10-01","2026-10-02","2026-10-05","2026-10-06","2026-10-07"]},"billedFrom":"2026-11-01","billedTo":"2026-11-03"}'::jsonb, false)->>'ok'$q$), '^true$');
select zz.chk('B09 faktura: 28 571 kutilmoqda, 5 kun; ma''lumotnomada 5 kun shu fakturada',
  (select amount::text || '/' || status || '/' || "sickDaysApplied" from public.invoices where id = 'IQ-0909__2026-11') || '/' ||
  (select count(*) from public.sick_notes n, jsonb_each(n."appliedDays") e where n.id = 'N909'), '^28571(\.0+)?/pending/5/5$');
select zz.chk('B10 bo''shagan 5 kun — avansga', zz.refund('U_FM', 'N909'), '^true/5/200000$');

select case when ok then 'PASS' else 'FAIL' end || ' | ' || name || case when ok then '' else ' | got=' || got || ' | want~' || pat end from zz.res order by n;
select 'JAMI: ' || count(*) filter (where ok) || ' PASS / ' || count(*) filter (where not ok) || ' FAIL' from zz.res;
rollback;
