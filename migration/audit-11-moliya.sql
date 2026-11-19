\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-11-moliya.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-11 (to'liq audit, 2026-11-18) — MOLIYA HISOBOTLARI.
--   Shu faylda — faqat YANGI obyektlar (funksiya, ustun, trigger). Hisobotlarning qolgan tuzatishlari o'z faylidagi amaldagi ta'rifda:
--     reports-roles.sql  — kpi_attendance (dars kunlari Du–Ju, A2-02), kpi_debt_aging (barcha o'quvchilar, A6-03), finance_plan_actual va
--                          kpi_collection (holati 'paid' — to'liq to'langan, A6-04);
--     telegram.sql       — director_daily: oldingi hisobotdan keyin tushgan to'lovlar 'since' va 'asOf' (A6-01; «tushgan» payti —
--                          shu faylning 2-bandidagi "receivedAt"), barcha biriktirilmagan to'lovlar (A6-07); kunlik hisobot kunlari
--                          standarti Du–Ju (A2-02).
--
-- 1) public.finance_other_income() — kassadagi O'QUV TO'LOVIDAN TASHQARI daromad, oy bo'yicha (A6-02). «Buxgalteriya» (Kirim, Foyda,
--    marja, A4 hisobot) va bosh sahifa (klassik va yangi) «Kirim» / «Sof foyda»siga qo'shiladi.
--    Muammo: kassa ishga tushgach KO-2 «Xarajat»ning har naqd qatori (sotish uchun tovar xaridi OP-24, asosiy vosita OP-18 ham)
--    app.kassa_link_paid orqali «Buxgalteriya» xarajatiga (expenses) ko'chadi, lekin o'sha tovarning sotuvi (KO-1 «Forma va tovarlar»,
--    IN-04) va «Boshqa kirim» (IN-06: to'garak, tadbir chiptasi, kitob…) hech qayerga yozilmasdi — Kirim faqat hisob-fakturalardan.
--    Natija: 20 mln ga forma olib 25 mln ga sotilsa, «Sof foyda» 20 mln KAM (haqiqatda +5 mln), kassa hisobotlari (KO-3, RP-08) bilan
--    zid edi.
--    Qoida: o'tkazilgan (posted; bekor qilingani — 'void' — yo'q) KO-1 ning NAQD qatorlari, statiyasi daromad (IN-*) va o'quv to'lovi
--    emas (IN-01 — u «To'lovlar» → hisob-faktura orqali Kirimda allaqachon bor); oy — hujjatning kassa kuni ("businessDay"; xarajat
--    ko'chirmasidagi oy bilan bir xil). Sinov kassasi ("isTest") — yo'q (kassa_link_paid ham xarajat yozmaydi).
--    Hisoblanmaydi (daromad emas yoki juftligi xarajatda yo'q): aniqlanmagan tushum (OP-16, keyin biriktiriladi), qarz / ta'sischi
--    mablag'i, bankdan naqd, hisobdor va xodim qaytimi, kamomadni qoplash; kassa SANASH FARQI — ortiqcha (in_surplus): uning juftligi
--    kamomad (va «hisobdan chiqarish» qarori) «Buxgalteriya» xarajatiga ko'chmaydi — faqat ortiqchani qo'shish foydani bir tomonlama
--    o'zgartirardi; ikkalasi «Kassa» hisobotlarida (RP-02, RP-08) va nazorat ro'yxatida.
--    Kassa moduli o'rnatilmagan bazada (jonli zanjir, --dev fayllarsiz) — bo'sh natija (so'rov dinamik: kassa jadvallari bo'lmasa
--    ham funksiya yaratiladi). O'qish: moliya rollari (Direktor, Moliya menejeri, g'aznachi) va buxgalter — «Buxgalteriya» va bosh
--    sahifa moliya bo'limini ko'radiganlar; faqat oy va statiya bo'yicha summalar (shaxsiy ma'lumot yo'q).
--
-- 2) payments."receivedAt" — to'lov BIRINCHI MARTA tushumga aylangan payt (A6-01, mustaqil tekshiruv 2-raund). Telegram kunlik
--    hisobotining «oldingi hisobotdan keyin tushgan» qatori (director_daily 'since', telegram.sql) shu bo'yicha tanlaydi.
--    Muammo: 'since' to'lovlarni KIRITILGAN vaqti ("createdAt") bo'yicha olardi. Click va Uzum to'lovi IKKI bosqichda yoziladi: qator
--    birinchi bosqichda yaratiladi (Click prepare — 'prepared', Uzum create — 'created'; tushum emas), tushumga esa ikkinchisida aylanadi
--    (Click complete — 'applied' / 'unmatched' / 'paid', Uzum confirm — 'confirmed'), "createdAt" esa o'zgarmaydi. Ikki bosqich kunlik
--    hisobot payti (asOf) bilan kesishsa — masalan juma 18:59:50 da prepare, hisobot 19:00:05, complete 19:30 — to'lov HECH QAYSI
--    hisobotda chiqmasdi: jumada u hali tushum emas edi, keyingi hisobotning 'since' oynasi esa asOf dan keyin kiritilganlarni olardi.
--    Yechim: shu ustun. Tushum ta'rifi — hisobotlarnikidek (app.counts_as_receipt). Tushum holatida yaratilgan qator — "createdAt"
--    (kiritilgan payt = tushgan payt; tarixiy import / server yozuvining o'z vaqti saqlanadi — import payti emas); tushum bo'lmagan
--    holatdan tushumga o'tgan qator — o'sha payt (server soati app.fin_now(), "createdAt" / "statusAt" bilan bir xil manba).
--    BIR MARTA qo'yiladi va keyin o'zgarmaydi: biriktirish ('unmatched' → 'applied') — ikkala holat ham tushum, qayta qo'yilmaydi (to'lov
--    ikki hisobotda sanalmasin; "statusAt" shu sabab yaramaydi — u har holat o'zgarishida yangilanadi), bekor / qaytarish ham uni
--    o'chirmaydi. Qiymatni FAQAT trigger qo'yadi: server va pul funksiyalari yuborgani e'tiborsiz; REST (Direktor) yuborgani —
--    app.pay_direct_guard (audit-10-tolov.sql) rad etadi (ustun uning «erkin» ro'yxatida yo'q — pul ustunlari qoidasi).
--    Trigger nomi «trg_pay_received» — BEFORE triggerlarning OXIRGISI (alifbo tartibi): trg_fin_server_ts "createdAt"ni allaqachon
--    qo'ygan (serverdan / tiklangan), trg_fin_zlock, trg_kassa_pay_guard va trg_pay_direct_guard esa qatorni mijoz yuborganidek ko'radi
--    (ularning xabarlari va «Direktor REST yozuvi faqat to'lovchi ma'lumoti / bekor» qoidasi avvalgidek). Nomi «trg_kassa_» / «trg_fin_»
--    emas — kassa-checks.sql trigger soni va barmoq izlari o'zgarmaydi; funksiya nomi ham ^(kassa|fin_|tuition_) emas.
--    Eski qatorlar (ustun bo'sh) — "createdAt" bo'yicha, avvalgidek (coalesce); deploydan oldin prepare qilinib keyin complete bo'lgani —
--    complete payti bilan. Oyna sharti coalesce("receivedAt", "createdAt") — indeks shu ifoda bo'yicha.
--    Tushumga O'TGAN payt — o'sha UPDATE ishlagan haqiqiy soat (clock_timestamp(); sinov bazasida — sinov soati app.fin_now()), tranzaksiya
--    boshlangan payt (now()) emas: oyna torayadi (3-raund tekshiruvi). MA'LUM QOLDIQ (to'liq yopilmagan): tushumga aylantirgan tranzaksiya
--    UPDATE'ni hisobot paytidan (asOf) OLDIN bajarib, hisobot ma'lumotni o'qigandan KEYIN commit qilsa — to'lov ikkala hisobotning
--    «oldingi hisobotdan keyin» qatoridan tushib qolishi mumkin. Oyna — UPDATE'dan commit'gacha (Click / Uzum holat yozuvi —
--    millisekundlar; qo'lda to'lov + kassa — biroz uzoqroq); tushum holatida YARATILGAN to'lovda ham shunday ("createdAt" — now(),
--    avval ham shunday edi). To'liq yopish uchun hisobot o'z snapshot'ini saqlashi kerak bo'lardi — kunlik Telegram qatori faqat ma'lumot
--    uchun, kunlik / oylik moliya hisobotlari (kassa kuni bo'yicha) bundan ta'sirlanmaydi.
--
-- Idempotent — QAYTA ishga tushirishga xavfsiz (create or replace, add column / create index if not exists, drop trigger if exists;
--   mavjud ma'lumot o'zgarmaydi — yangi ustun eski qatorlarda bo'sh qoladi).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

create or replace function public.finance_other_income() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v jsonb;
begin
  -- buxgalter: app.my_role() (fin-core.sql app.is_accountant bilan bir xil; u --dev faylda — jonli zanjirda yo'q)
  if not (app.is_finance() or coalesce(app.my_role() = 'accountant', false)) then
    raise exception 'Ruxsat yo''q: faqat Direktor, moliya xodimlari va buxgalter' using errcode = '42501';
  end if;
  if to_regclass('public.cash_docs') is null or to_regclass('public.cash_doc_lines') is null
     or to_regclass('public.cash_desks') is null or to_regclass('public.fin_articles') is null then
    return jsonb_build_object('months', '{}'::jsonb);
  end if;
  execute $q$
    with l as (
      select to_char(c."businessDay", 'YYYY-MM') as m, l."articleId" as art, sum(l.amount) as s
        from public.cash_docs c
        join public.cash_doc_lines l on l."docId" = c.id
        join public.cash_desks k on k.id = c.desk
        join public.fin_articles a on a.id = l."articleId"
       where c.form = 'KO1' and c.status = 'posted' and c.op <> 'in_surplus' and not k."isTest"
         and l.cash and a.kind = 'IN' and a.id <> 'IN-01' and c."businessDay" is not null
       group by 1, 2)
    select coalesce(jsonb_object_agg(q.m, q.x), '{}'::jsonb)
      from (select l.m, jsonb_build_object('sum', sum(l.s),
                     'items', jsonb_agg(jsonb_build_object('articleId', l.art, 'nameUz', a."nameUz", 'sum', l.s) order by l.art)) as x
              from l join public.fin_articles a on a.id = l.art
             group by l.m) q
  $q$ into v;
  return jsonb_build_object('months', v);
end $$;
revoke all on function public.finance_other_income() from public, anon;
grant execute on function public.finance_other_income() to authenticated, service_role;

-- ---------- 2) payments."receivedAt" — tushumga aylangan payt (A6-01, 2-raund) ----------
alter table public.payments add column if not exists "receivedAt" timestamptz;
create index if not exists payments_received_idx on public.payments ((coalesce("receivedAt", "createdAt")));
-- SECURITY DEFINER: REST (Direktor) yozuvida ham app.fin_now() chaqiriladi (u mijoz rollariga yopiq — fin-prereq.sql).
create or replace function app.pay_received_at() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    -- Tushum holatida yaratilgan — kiritilgan payt (trg_fin_server_ts qo'ygan "createdAt"); aks holda bo'sh. Upsert taklifidagi qator
    --   (mavjud id) — keyingi UPDATE bosqichida quyidagi qoida bilan qayta hisoblanadi.
    new."receivedAt" := case when app.counts_as_receipt(new.id, new.status, new.provider, new.amount)
                             then coalesce(new."createdAt", app.fin_now()) end;
  else
    -- Bir marta qo'yilgan — o'zgarmaydi; endi tushumga aylandi (avval emas edi) — shu UPDATE'ning haqiqiy soati (sinov bazasida — sinov
    --   soati); qolgan hollarda — avvalgisi.
    new."receivedAt" := coalesce(old."receivedAt",
      case when app.counts_as_receipt(new.id, new.status, new.provider, new.amount)
                and not app.counts_as_receipt(old.id, old.status, old.provider, old.amount)
           then case when app.fin_clock_allowed() then app.fin_now() else clock_timestamp() end end);
  end if;
  return new;
end $$;
revoke all on function app.pay_received_at() from public, anon, authenticated;
drop trigger if exists trg_pay_received on public.payments;
create trigger trg_pay_received before insert or update on public.payments for each row execute function app.pay_received_at();

notify pgrst, 'reload schema';
