\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-11-moliya.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-11 (to'liq audit, 2026-11-18) — MOLIYA HISOBOTLARI.
--   Shu faylda — faqat YANGI funksiya. Hisobotlarning qolgan tuzatishlari o'z faylidagi amaldagi ta'rifda:
--     reports-roles.sql  — kpi_attendance (dars kunlari Du–Ju, A2-02), kpi_debt_aging (barcha o'quvchilar, A6-03), finance_plan_actual va
--                          kpi_collection (holati 'paid' — to'liq to'langan, A6-04);
--     telegram.sql       — director_daily: oldingi hisobotdan keyin tushgan to'lovlar 'since' va 'asOf' (A6-01), barcha biriktirilmagan
--                          to'lovlar (A6-07); kunlik hisobot kunlari standarti Du–Ju (A2-02).
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
-- Idempotent — QAYTA ishga tushirishga xavfsiz (create or replace; ma'lumot o'zgarmaydi).
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

notify pgrst, 'reload schema';
