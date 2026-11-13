\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-rights.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-rights.sql — MOLIYA ISH REJASI, F1.21: «Buxgalter» (accountant) rolining O'QISH huquqlari — YOPIQ RO'YXAT.
--   Buxgalter — moliya nazoratchisi. Shu fayl faqat O'QISH beradi: pul qabul qilish / berish, xarajat, faktura, vedomost va
--   to'lov yozuvlarini yozish huquqi yo'q. Kassa nazorati (fin-core / kassa-* fayllarida, app.fin_list2 / app.kassa_reader
--   orqali) — 2-ro'yxat imzosi: kassir so'rovini tasdiqlash / rad etish, kunni tekshirish, o'tkazilgan hujjatni bekor qilish,
--   avans hisoboti (o'tkazilganda «Buxgalteriya»ga xarajat bo'lib tushadi).
--   Qoidalar (docs/moliya/buxgalteriya-ish-reja.md 4.13, FD-28; JORIY-ETISH-REJA.md D6/D7):
--     • ekranda o'quvchi va xodim ismi ko'rinadi (moliya menejeri kabi); shaxsiy fayl yo'q: telefon, manzil, sog'liq kartasi,
--       baholar, davomat jurnali, rasm, xodim kartochkasi (teachers / staff qatorlari), boshqa foydalanuvchilar qatori va emaili;
--     • to'lovchi yozgan matn (Click: ism, «sinf» va izoh maydonlari — unda o'quvchining maxfiy ota-ona kodi yoki telefon bo'lishi
--       mumkin), ota-ona telefoni va provayderning xom javobi — YO'Q;
--     • chegirma va uning sababi (monitoring 20% / 100%, kasal kunlar soni va summasi) — ko'rinadi: buxgalteriya hisobi uchun
--       kerak (4.3 analitika, FD-32 «bemor kuni — 9030 storno»); kasallik SANALARI (invoices."sickNoteRefs") — yo'q;
--     • fakturalar, to'lovlar, qaytarishlar, berilgan maosh va vedomost qatorlari — faqat «*_acc» ko'rinishlari orqali (aniq
--       ustunlar ro'yxati: jadvalga yangi ustun qo'shilsa, u bu yerga o'zi tushmaydi — test-fin-rights.sql V-bandlari uni
--       ko'rinishga yoki istisnoga kiritishni talab qiladi);
--     • can_see_salary() O'ZGARMAYDI (u teachers / staff qatorlarini ham ochadi);
--     • eksport / chop etish — ID bilan, ismsiz (FD-28): kassa eksportlari serverda (kassa_journal_export, kassa_month_pack),
--       «Buxgalteriya» A4 hisoboti sahifada.
--   YOPIQ RO'YXAT uch faylda: shu fayl (jadval siyosatlari, «*_acc» ko'rinishlari va app.acc_read() kaliti), nurse-sick.sql
--   (students_billing — o'quvchilar ro'yxati, buxgalter app.acc_read() orqali; ta'rif bitta joyda qoladi), parent-link-canon.sql
--   (claim_child buxgalter hisobini rad etadi). migration/test-fin-rights.sql (L-bandlar) aynan shu ro'yxatni kutadi.
--   «<jadval>_acc_sel» nomlari va «*_acc» ko'rinishlari — faqat F1.21 uchun.
--   Sahifa buxgalterning «To‘lovlar» / «Buxgalteriya» bo'limlarini kassa_state javobidagi «accRead» (= app.acc_read()) bo'yicha
--   ochadi — reliz raqamiga bog'liq emas.
--   ORQAGA QAYTARISH: faylni zanjirdan OLIB TASHLAMANG — yangi nomli siyosat va ko'rinishlarni boshqa hech bir fayl o'chirmaydi
--   (bazada qolib, buxgalter o'qishda davom etadi). Quyidagi «fin_rights_on» qiymatini «off» qilib deploy qiling — boshqa hech narsa
--   o'zgarmaydi (reliz 10 qoladi): 0-bo'limdagi tozalash siyosat va ko'rinishlarni o'chiradi, app.acc_read() false bo'ladi
--   (students_billing buxgalterga yopiladi, sahifa bo'limlarni o'zi yashiradi); test-fin-rights.sql Q-bandi shu yo'lni tekshiradi.
--   Reliz 10 ning boshqa o'zgarishlari (buxgalterga qo'shimcha lavozim yo'q, kassa javoblarida email o'rniga uid) huquq bermaydi —
--   ular qoladi.
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi (kassa moduli bilan birga o'rnatiladi).
--   Idempotent — QAYTA ishga tushirishga xavfsiz.
-- =====================================================================
\if :{?fin_rights_on}
\else
\set fin_rights_on on
\endif

-- 0) Tozalash (har deployda): shu fayl yaratgan barcha «<jadval>_acc_sel» siyosatlari va «*_acc» ko'rinishlari (izohidagi «F1.21:»
--    belgisi bo'yicha ham) o'chiriladi — ro'yxatdan olingani bazada qolib ketmasin; 1–2-bo'limlar (yoqilgan bo'lsa) qayta yaratadi.
do $$
declare t text;
begin
  for t in select p.tablename from pg_policies p
            where p.schemaname = 'public' and p.policyname = p.tablename || '_acc_sel' loop
    execute format('drop policy %I on public.%I', t || '_acc_sel', t);
  end loop;
  for t in select c.relname from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'v' and obj_description(c.oid, 'pg_class') like 'F1.21:%' loop
    execute format('drop view public.%I', t);
  end loop;
end $$;
drop view if exists public.invoices_acc, public.payments_acc, public.refunds_acc, public.salary_payments_acc, public.payroll_lines_acc;
-- Kalit: o'chiq holat (students_billing va sahifa bo'limlari uchun) — yoqilgan bo'lsa pastda qayta belgilanadi.
create or replace function app.acc_read() returns boolean language sql stable set search_path = public, app, pg_temp as $$ select false $$;
revoke all on function app.acc_read() from public, anon;
grant execute on function app.acc_read() to authenticated, service_role;

\if :fin_rights_on
-- Kalit yoqildi: buxgalter (faol, asosiy rol) — students_billing va kassa_state «accRead».
create or replace function app.acc_read() returns boolean language sql stable set search_path = public, app, pg_temp as $$ select app.is_accountant() $$;

-- 1) Jadvallar (ustunlarida to'lovchi matni, telefon, email yoki kasallik sanalari yo'q): buxgalterga SELECT — «*_acc_sel».
--    app.is_accountant() — PUBLIC uchun bajariladigan (anon'ga false), anon o'qiy oladigan jadvallarda ham xavfsiz.
do $$
declare t text;
  v_list constant text[] := array['expenses', 'credit_ledger', 'student_credit', 'staff_advances', 'payroll_runs'];
begin
  foreach t in array v_list loop
    if to_regclass('public.' || t) is null then
      raise exception 'fin-rights.sql: public.% jadvali topilmadi (zanjir tartibi?)', t;
    end if;
    execute format('create policy %I on public.%I for select using (app.is_accountant())', t || '_acc_sel', t);
  end loop;
  -- config: faqat moliya sozlamalari ('finance' — o'tish oylari, stavkalar; 'salary' — maosh stavkalari).
  --   'security' (qaytarish PIN'i), 'ltv' va boshqa qatorlar — yo'q.
  create policy config_acc_sel on public.config for select using (app.is_accountant() and id in ('finance', 'salary'));
end $$;

-- 2) Ko'rinishlar: egasi nomidan ishlaydi (RLS chetlanadi), qator filtri — rol tekshiruvi (bitta qatorli «acc» bilan birlashma:
--    ko'rinish shu sababli avtomatik YANGILANMAYDIGAN — huquq tasodifan berilsa ham u orqali yozib bo'lmaydi); ustunlar — aniq ro'yxat.
--    Xom jadvallarga (invoices, payments, refunds, salary_payments, payroll_lines) buxgalter siyosati YO'Q. Sahifa buxgalter uchun
--    shu nomlardan o'qiydi (admin.html: collection() — «invoices» → «invoices_acc» va h.k.).

-- 2a) Fakturalar: kasallik sanalari (sickNoteRefs — {ma'lumotnoma: [kunlar]}) — yo'q; summa, chegirma va sababi, kasal kunlar
--     soni va summasi — bor (hisob uchun kerak).
create view public.invoices_acc with (security_barrier = true) as
  select i.id, i."studentId", i."studentName", i."classKey", i.month, i.amount, i."paidAmount", i.provider, i.status,
         i."providerTrans", i."paidAt", i."reversedAt", i."createdAt", i."baseAmount", i.discount, i."discountInfo", i."isGrant",
         i."pctApplied", i."sickDaysApplied", i."sickAmount", i."priceKey", i."referralUsedIds", i."billedFrom", i."billedTo",
         i."bonusRef", i."approvalRefs"
    from public.invoices i, (select app.is_accountant() as ok) acc
   where acc.ok;

-- 2b) To'lovlar: payerName / payerClass / merchant_trans_id (to'lovchi yozgan matn — maxfiy kod yoki telefon bo'lishi mumkin),
--     payerPhone (D7) — yo'q; raw o'rniga faqat sahifa hisobi uchun kerakli kalitlar (to'lov kuni, qo'lda kiritilgani,
--     provayder qaytarish belgilari).
create view public.payments_acc with (security_barrier = true) as
  select p.id, p."studentId", p."invoiceId", p.provider, p.amount, p.status, p.click_trans_id, p.merchant_prepare_id,
         p.merchant_confirm_id, p."transId", p.matched, p."createdAt", p."statusAt", p."cashDocId", p."fiscalNo",
         jsonb_strip_nulls(jsonb_build_object(
           'manual', p.raw -> 'manual', 'method', p.raw -> 'method', 'date', p.raw -> 'date',
           'needsManualReverse', p.raw -> 'needsManualReverse', 'manualReverseDone', p.raw -> 'manualReverseDone',
           'reverseNote', p.raw -> 'reverseNote')) as raw
    from public.payments p, (select app.is_accountant() as ok) acc
   where acc.ok;

-- 2c) Qaytarishlar: byEmail (boshqa xodim emaili) — yo'q; biriktirilmagan to'lov qaytarilganda studentName to'lovchi matnidan
--     ko'chirilgan (refund-rpc.sql) — faqat fakturaga qaytarishda ko'rsatiladi.
create view public.refunds_acc with (security_barrier = true) as
  select r.id, r.target, r."targetId", r."studentId", case when r.target = 'invoice' then r."studentName" end as "studentName",
         r.amount, r.reason, r.month, r."createdAt", r."byUid", r.method, r."cashDocId"
    from public.refunds r, (select app.is_accountant() as ok) acc
   where acc.ok;

-- 2d) Berilgan maosh: byEmail — yo'q.
create view public.salary_payments_acc with (security_barrier = true) as
  select s.id, s."teacherId", s."teacherName", s.month, s.gross, s.advance, s.net, s.date, s.note, s."createdAt", s.deduction,
         s."subBonus", s.paid, s."carryIn", s."carryOut", s."payeeRef", s."byUid", s.method, s."cashDocId"
    from public.salary_payments s, (select app.is_accountant() as ok) acc
   where acc.ok;

-- 2e) Vedomost qatorlari: summalar va holat; davomat tafsiloti (details: kelmagan / kechikkan kunlar, ta'til, kasallik),
--     workedMin va Direktor izohi — yo'q (details'dan faqat «Kamera ID bor-yo'qligi» — sahifa belgisi uchun).
create view public.payroll_lines_acc with (security_barrier = true) as
  select l.id, l."runId", l."personType", l."personId", l."refId", l.name, l.gross, l.deduction, l."subBonus", l.advance,
         l."carryIn", l.payable, jsonb_strip_nulls(jsonb_build_object('camera', l.details -> 'camera')) as details,
         l."needsDirector", l."directorOkBy", l."directorOkAt"
    from public.payroll_lines l, (select app.is_accountant() as ok) acc
   where acc.ok;

do $$ declare v text; begin
  foreach v in array array['invoices_acc', 'payments_acc', 'refunds_acc', 'salary_payments_acc', 'payroll_lines_acc'] loop
    execute format('revoke all on public.%I from public, anon, authenticated', v);
    execute format('grant select on public.%I to authenticated, service_role', v);
    execute format('comment on view public.%I is %L', v, 'F1.21: buxgalter uchun o''qish ko''rinishi (fin-rights.sql)');
  end loop;
end $$;
\endif

notify pgrst, 'reload schema';
