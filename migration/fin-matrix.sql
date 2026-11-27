\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-matrix.sql ALOHIDA ishga tushirilmaydi — u zanjirdagi kassa, xarajatlar va vedomost jadvallariga tayanadi' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-matrix.sql — MOLIYA ISH REJASI, 2-BOSQICH (F2.5): RP-09 — barcha to'lov usullari bo'yicha statiya matritsasi (o'quv yoki
--   kalendar yili, 12 oy) va maosh taqsimoti (vedomost × lavozim -> EX-01…EX-04). Faqat o'qiydi; jadval va XLSX — sahifada
--   (assets/js/fin-matrix.js). RP-08 (kassa_matrix) — bitta kassa, bir oy, kunlar bo'yicha; RP-09 — kassa + kassadan tashqari har
--   pul harakati, oylar bo'yicha, usul kesimida.
--   Manbalar (har hujjat bir marta — kassa orderi (KO-1 / KO-2) bilan bog'langan yozuv kassada sanaladi, jadvalning o'zida emas):
--     kassa    — o'tkazilgan KO-1 (kirim) / KO-2 (chiqim) ning naqd qatorlari, statiya — amaldagi (F2.13 qayta tasnifidan keyin,
--                app.kassa_eff_art), sinov kassasisiz; kun — kassa kuni. Usul — naqd;
--     o'quv to'lovlari — kassa orderisiz tushumlar (yagona tushum qoidasi — app.counts_as_receipt, kun — app.pay_day): Click / Uzum /
--                Payme — onlayn, terminal — karta, bank, o'zaro hisob (ish haqidan, naqdsiz dalolatnoma), kassagacha naqd; avansdan
--                qo'llash, grant va avansni ko'chirish — pul emas, kirmaydi. Biriktirilgan — IN-01, biriktirilmagan (aniqlanmagan) —
--                OP-16. Egasiga qaytarilgan to'lov (holati «refunded») ham tushum (OP-16): pul kirgan va qaytgan — qaytarish OP-16
--                chiqimida (kassadan — KO-2, kassagacha — qaytarishlar jurnali); yagona tushum ta'rifi uni sanamaydi, lekin pul
--                oqimida ikkala harakat ham bor (aks holda qaytarish juftsiz qolib, sof natija kam chiqardi);
--     xarajatlar — «Buxgalteriya» reyestri: bank, karta, kassagacha naqd, eski yozuv (usuli yo'q — «boshqa») va hisobdor orqali
--                (avans hisoboti, «Д-» dalolatnoma — pul oldin OP-06 bilan kassadan chiqqan: bu ustun — sarflangan pulning statiyasi,
--                pul jamiga qo'shilmaydi); statiya — yozuvdagi, yo'q bo'lsa eski toifadan (fin_category_map — «taxminiy» belgisi);
--     qaytarishlar — o'quv to'lovi / avans (OP-15) va biriktirilmagan to'lov (OP-16), kassa orderisizlari (bank, karta, eski yozuv);
--     maosh (OP-09) va avans (OP-08) to'lovlari — kassa orderisizlari (karta, o'zaro hisob, kassagacha naqd); maosh summasi — berilgan
--                (paid; eski yozuvda — net + o'rinbosarlik, salary-carryover.sql qoidasi); oy — to'lov sanasi;
--     maosh taqsimoti — tasdiqlangan vedomost (payroll_runs.status = 'approved'): har qator summasi (maosh − ushlanma, 0 dan kam
--                emas, + o'rinbosarlik — «💼 Oylik maoshni yozish» qatori bilan bir xil qoida) xodimning hozirgi lavozimidan
--                statiyaga (app.fin_pos_article); vedomost tasdiqlanmagan oy — «Maosh» hisoblash qatori (payroll__YYYY-MM)
--                taqsimlanmagan. Bu — hisoblash (pul emas): pul jamiga qo'shilmaydi (maosh to'lovi — OP-09), alohida ustun.
--   Ichki o'tkazma — statiyasi pul oqimida «ichki» (fin_articles."cfLine": OP-01 bankdan naqd, OP-02 bankka topshirish, OP-03 ekvayring
--     hisob-kitobi, OP-04 o'z hisoblari / korporativ karta, OP-05 valyuta; kassada bankka / bankdan orderlarning statiyasi qat'iy — shu):
--     qator belgilanadi — daromad ham, xarajat ham emas (RP-08 dagi qoida); bank tomoni F3.2 gacha tizimda yo'q.
--   Qabul mezoni (reja F2.5): Jami = Σ hujjatlar — «sources» har manba bo'yicha hujjatlar soni va jami (matritsa qatorlari yig'indisi
--     shunga teng), kassa uchun mustaqil nazorat — order sarlavhalari summasi, maosh taqsimoti uchun — «Maosh» hisoblash qatori.
--   Lavozim -> statiya — buxgalter tasdig'iga (Sh-8 qo'shimcha savoli): o'qituvchilar ro'yxati — EX-01; «Xodimlar»dagi lavozim nomi
--     (admin.html STAFF_POSITIONS) bo'yicha; ro'yxatda yo'q lavozim — «aniqlanmagan» (summasi saqlanadi, nomi ro'yxatda).
--   Kim: Direktor, Moliya menejeri, buxgalter (oylik kassa to'plami bilan bir xil) — boshqalarga 42501. Faqat yig'ma summalar
--     (ism yo'q, FD-28): lavozim nomlari, xarajat toifalari va to'lov usullari.
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi (kassa moduli bilan birga).
-- =====================================================================

-- Lavozim -> ish haqi statiyasi (§4.4 «Moslik»: Maosh -> EX-01…EX-04). Apostrof turlari, bo'shliqlar va katta-kichik harf farqsiz.
create or replace function app.fin_pos_article(p_type text, p_position text) returns text
language sql immutable parallel safe set search_path = public, app, pg_temp as $$
  select case
    when coalesce(p_type, '') = 'teacher' then 'EX-01'
    else (select case
            when x in ('o''qituvchi', 'kurator') then 'EX-01'
            when x in ('laborant', 'kutubxonachi', 'hamshira', 'xo''jalik xodimi', 'bosh oshpaz', 'oshxona xodimi', 'tozalov xodimi',
                       'farrosh', 'qorovul', 'xavfsizlik xodimi', 'haydovchi', 'bog''bon') then 'EX-02'
            when x in ('direktor', 'ma''muriyat rahbari', 'o''ibdo''', 'hr', 'hr menejer', 'hr menejeri', 'moliya menejeri', 'kassir', 'g''aznachi',
                       'buxgalter', 'bosh buxgalter') then 'EX-03'
            when x in ('marketing menejeri', 'sotuvchi', 'qabulxona xodimi') then 'EX-04'
          end
          from (select regexp_replace(lower(btrim(translate(coalesce(p_position, ''), '‘’ʻʼ`´', repeat(chr(39), 6)))), '\s+', ' ', 'g') as x) z)
  end $$;
revoke all on function app.fin_pos_article(text, text) from public, anon, authenticated;

create or replace function public.fin_matrix(p_kind text, p_year int) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_kind text := lower(btrim(coalesce(p_kind, ''))); v_cur int; v_from date; v_to date; v_m text[]; v_out jsonb;
begin
  if not (app.is_admin() or app.fin_list2()) then
    raise exception 'Ruxsat yo''q: RP-09 statiya matritsasini Moliya menejeri, buxgalter yoki Direktor ko''radi' using errcode = '42501';
  end if;
  v_cur := extract(year from app.fin_today())::int;
  if v_kind not in ('school', 'calendar') or p_year is null or p_year < 2024 or p_year > v_cur + 1 then
    raise exception 'Davr noto''g''ri: o''quv (school) yoki kalendar (calendar) yili, yil — 2024 … %', v_cur + 1
      using errcode = '22023', hint = 'fin:bad_input';
  end if;
  v_from := case when v_kind = 'school' then make_date(p_year, 9, 1) else make_date(p_year, 1, 1) end;
  v_to := (v_from + interval '12 months')::date - 1;
  v_m := array(select to_char(v_from + make_interval(months => g.i), 'YYYY-MM') from generate_series(0, 11) g(i));

  with f as (
    -- kassa: o'tkazilgan KO-1 / KO-2 ning naqd qatorlari (amaldagi statiya), sinov kassasisiz
    select 'kassa'::text as src, case when c.form = 'KO1' then 'in' else 'out' end as dir,
           coalesce(app.kassa_eff_art(c.id, l."lineNo", l."articleId"), '') as art, 'cash'::text as method,
           to_char(c."businessDay", 'YYYY-MM') as m, l.amount as amt, false as approx, c.id as ref, ''::text as tag
      from public.cash_docs c
      join public.cash_doc_lines l on l."docId" = c.id
      join public.cash_desks k on k.id = c.desk
     where c.status = 'posted' and c.form in ('KO1', 'KO2') and l.cash and not k."isTest" and c."businessDay" between v_from and v_to
    union all
    -- o'quv to'lovlari — kassa orderisiz (qaytarilgani ham — yuqoridagi izoh)
    select 'payments', 'in', case when p.status in ('unmatched', 'refunded') then 'OP-16' else 'IN-01' end,
           case lower(coalesce(p.provider, ''))
             when 'cash' then 'cash' when 'naqd' then 'cash' when 'terminal' then 'card' when 'card' then 'card'
             when 'click' then 'online' when 'uzum' then 'online' when 'payme' then 'online'
             when 'bank' then 'bank' when 'transfer' then 'bank' when 'offset' then 'offset' else 'other' end,
           to_char(pd.d, 'YYYY-MM'), p.amount, false, p.id, lower(coalesce(p.provider, ''))
      from public.payments p
      cross join lateral (select app.pay_day(p."createdAt", p.raw) as d) pd
     where p."createdAt" >= (v_from::timestamp at time zone 'Asia/Tashkent')
       and p."createdAt" < ((v_to + 32)::timestamp at time zone 'Asia/Tashkent')
       and (app.counts_as_receipt(p.id, p.status, p.provider, p.amount)
            or (p.status = 'refunded' and app.counts_as_receipt(p.id, 'applied', p.provider, p.amount)))
       and coalesce(p.provider, '') not in ('credit', 'grant', 'reattr')
       and not exists (select 1 from public.cash_docs c where c.id = p."cashDocId" and c.form in ('KO1', 'KO2'))
       and pd.d between v_from and v_to
    union all
    -- «Buxgalteriya» reyestri (kassa orderidan ko'chirilganidan tashqari; maosh hisoblash qatori — pastda)
    select 'expenses', 'out', coalesce(nullif(e."articleId", ''), cm."articleId", ''),
           case when e.method in ('bank', 'card', 'cash', 'accountable') then e.method else 'other' end,
           coalesce(nullif(e.month, ''), left(e.date, 7)), e.amount, nullif(e."articleId", '') is null and cm."articleId" is not null,
           e.id, coalesce(e.category, '')
      from public.expenses e
      left join public.fin_category_map cm on cm.category = e.category
     where e.kind = 'expense' and coalesce(nullif(e.month, ''), left(e.date, 7)) = any(v_m)
       and not exists (select 1 from public.cash_docs c where c.id = e."cashDocId" and c.form in ('KO1', 'KO2'))
    union all
    -- qaytarishlar — kassa orderisiz; oy — yozilgan kun (eski yozuvdagi month — faktura oyi bo'lishi mumkin)
    select 'refunds', 'out', case when r.target = 'payment' then 'OP-16' else 'OP-15' end,
           case when r.method in ('bank', 'card', 'cash') then r.method else 'other' end,
           coalesce(to_char(r."createdAt" at time zone 'Asia/Tashkent', 'YYYY-MM'), nullif(r.month, '')), r.amount, false, r.id, coalesce(r.target, '')
      from public.refunds r
     where coalesce(to_char(r."createdAt" at time zone 'Asia/Tashkent', 'YYYY-MM'), nullif(r.month, '')) = any(v_m)
       and not exists (select 1 from public.cash_docs c where c.id = r."cashDocId" and c.form in ('KO1', 'KO2'))
    union all
    -- maosh to'lovlari — kassa orderisiz; oy — to'lov sanasi
    select 'salary', 'out', 'OP-09',
           case coalesce(s.method, '') when 'card' then 'card' when 'offset' then 'offset' when 'cash' then 'cash' when '' then 'cash' else 'other' end,
           left(coalesce(nullif(s.date, ''), s.month), 7), coalesce(s.paid, coalesce(s.net, 0) + coalesce(s."subBonus", 0)), false, s.id, ''
      from public.salary_payments s
     where left(coalesce(nullif(s.date, ''), s.month), 7) = any(v_m)
       and not exists (select 1 from public.cash_docs c where c.id = s."cashDocId" and c.form in ('KO1', 'KO2'))
    union all
    -- avans to'lovlari — kassa orderisiz
    select 'advances', 'out', 'OP-08',
           case coalesce(a.method, '') when 'card' then 'card' when 'cash' then 'cash' when '' then 'cash' else 'other' end,
           left(coalesce(nullif(a.date, ''), a.month), 7), a.amount, false, a.id, ''
      from public.staff_advances a
     where left(coalesce(nullif(a.date, ''), a.month), 7) = any(v_m)
       and not exists (select 1 from public.cash_docs c where c.id = a."cashDocId" and c.form in ('KO1', 'KO2'))
    union all
    -- maosh taqsimoti: tasdiqlangan vedomost — lavozimdan statiya (hisoblash)
    select 'payroll', 'out', coalesce(app.fin_pos_article(pl."personType", st.position), ''), 'accrual', pl."runId",
           round(greatest(0, coalesce(pl.gross, 0) - coalesce(pl.deduction, 0)) + coalesce(pl."subBonus", 0)), false, pl.id,
           case when pl."personType" = 'teacher' then '#teacher' else coalesce(btrim(st.position), '') end
      from public.payroll_lines pl
      join public.payroll_runs pr on pr.id = pl."runId" and pr.status = 'approved'
      left join public.staff st on pl."personType" = 'staff' and st.id = pl."refId"
     where pl."runId" = any(v_m)
    union all
    -- vedomost tasdiqlanmagan oy — «Maosh» hisoblash qatori taqsimlanmagan
    select 'payroll', 'out', '', 'accrual', right(e.id, 7), e.amount, false, e.id, '#unsplit'
      from public.expenses e
     where e.kind = 'accrual' and right(e.id, 7) = any(v_m)
       and not exists (select 1 from public.payroll_runs pr where pr.id = right(e.id, 7) and pr.status = 'approved')),
  fm as (select f.*, array_position(v_m, f.m) as i from f where f.amt is not null and f.amt <> 0 and f.m = any(v_m)),
  -- qatorlar: (yo'nalish, statiya) × usul × oy
  rm as (select dir, art, method, i, sum(amt) as s from fm group by 1, 2, 3, 4),
  rk as (select dir, art, method, sum(s) as total from rm group by 1, 2, 3),
  ra as (select rk.dir, rk.art, rk.method, rk.total,
                (select jsonb_agg(coalesce(x.s, 0) order by g.i)
                   from generate_series(1, 12) g(i)
                   left join rm x on x.dir = rk.dir and x.art = rk.art and x.method = rk.method and x.i = g.i) as arr
           from rk),
  rw as (select ra.dir, ra.art, jsonb_object_agg(ra.method, ra.arr) as m,
                coalesce(sum(ra.total) filter (where ra.method not in ('accountable', 'accrual')), 0) as money,
                coalesce(sum(ra.total) filter (where ra.method = 'accountable'), 0) as accountable,
                coalesce(sum(ra.total) filter (where ra.method = 'accrual'), 0) as accrual
           from ra group by 1, 2),
  rf as (select dir, art, bool_or(approx) as approx, array_agg(distinct src order by src) as srcs from fm group by 1, 2),
  -- manbalar nazorati
  sr as (select s.src, count(distinct s.ref) as n, sum(s.amt) as total,
                (select jsonb_agg(coalesce((select sum(y.amt) from fm y where y.src = s.src and y.i = g.i), 0) order by g.i)
                   from generate_series(1, 12) g(i)) as bym
           from fm s group by s.src),
  -- kassa: order sarlavhasi summasi (qatorlardan mustaqil)
  kh as (select coalesce(sum(c.amount) filter (where c.form = 'KO1'), 0) as hin, coalesce(sum(c.amount) filter (where c.form = 'KO2'), 0) as hout,
                count(*) as n
           from public.cash_docs c join public.cash_desks k on k.id = c.desk
          where c.status = 'posted' and c.form in ('KO1', 'KO2') and not k."isTest" and c."businessDay" between v_from and v_to),
  -- maosh taqsimoti: oy bo'yicha taqsimot (faqat tasdiqlangan vedomost qatorlari) va «Maosh» hisoblash qatori; farq — vedomost tasdiqlangan
  --   va qator yozilgan oyda
  pm as (select g.i, v_m[g.i] as m,
                coalesce((select sum(y.amt) from fm y where y.src = 'payroll' and y.tag <> '#unsplit' and y.i = g.i), 0) as split,
                (select e.amount from public.expenses e where e.kind = 'accrual' and e.id = 'payroll__' || v_m[g.i]) as acc,
                (select pr.status from public.payroll_runs pr where pr.id = v_m[g.i]) as run
           from generate_series(1, 12) g(i)),
  po as (select case when y.tag = '#teacher' then 'teacher' else 'staff' end as typ, nullif(nullif(y.tag, '#teacher'), '') as pos, y.art,
                count(*) as n, sum(y.amt) as s
           from fm y where y.src = 'payroll' and y.tag <> '#unsplit' group by 1, 2, 3),
  un as (select y.tag as category, count(*) as n, sum(y.amt) as s from fm y where y.src = 'expenses' and y.art = '' group by 1)
  select jsonb_build_object(
      'ok', true, 'kind', v_kind, 'year', p_year, 'from', v_from, 'to', v_to, 'months', to_jsonb(v_m), 'generatedAt', app.fin_now(),
      'methods', to_jsonb(array['cash', 'bank', 'card', 'online', 'offset', 'other', 'accountable', 'accrual']),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
                                  'dir', rw.dir, 'articleId', nullif(rw.art, ''), 'kind', a.kind, 'nameUz', a."nameUz", 'nameRu', a."nameRu",
                                  'cfLine', a."cfLine", 'transfer', coalesce(a."cfLine", '') = 'ichki', 'approx', rf.approx,
                                  'sources', to_jsonb(rf.srcs), 'm', rw.m, 'money', rw.money, 'accountable', rw.accountable, 'accrual', rw.accrual)
                                order by case rw.dir when 'in' then 0 else 1 end, (rw.art = ''), coalesce(a."sortOrder", 9999), rw.art)
                          from rw join rf on rf.dir = rw.dir and rf.art = rw.art
                          left join public.fin_articles a on a.id = rw.art), '[]'::jsonb),
      'sources', coalesce((select jsonb_agg(jsonb_build_object('key', sr.src, 'docs', sr.n, 'total', sr.total, 'byMonth', sr.bym)
                                            order by array_position(array['kassa', 'payments', 'expenses', 'refunds', 'salary', 'advances', 'payroll'], sr.src))
                             from sr), '[]'::jsonb),
      'kassaHeader', (select jsonb_build_object('in', kh.hin, 'out', kh.hout, 'docs', kh.n) from kh),
      'payroll', jsonb_build_object(
          'byMonth', (select jsonb_agg(jsonb_build_object('month', pm.m, 'run', pm.run, 'split', pm.split, 'accrualRow', pm.acc,
                                                          'diff', case when pm.run = 'approved' and pm.acc is not null then pm.split - pm.acc end) order by pm.i) from pm),
          'positions', coalesce((select jsonb_agg(jsonb_build_object('type', po.typ, 'position', po.pos, 'articleId', nullif(po.art, ''),
                                                                     'lines', po.n, 'total', po.s)
                                                  order by (po.art = ''), po.art, (po.typ <> 'teacher'), po.pos) from po), '[]'::jsonb)),
      'unclassified', coalesce((select jsonb_agg(jsonb_build_object('category', un.category, 'rows', un.n, 'total', un.s)
                                                 order by un.s desc, un.category) from un), '[]'::jsonb))
    into v_out;
  return v_out;
end $$;
revoke all on function public.fin_matrix(text, int) from public, anon;
grant execute on function public.fin_matrix(text, int) to authenticated;
