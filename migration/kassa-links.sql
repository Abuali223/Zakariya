\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: kassa-links.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- kassa-links.sql — MOLIYA ISH REJASI, 1a-BOSQICH (F1.5, F1.6, F1.13): MAVJUD PUL OQIMLARINI KASSAGA BOG'LASH.
--   Kassa ishga tushgach (fin_org."kassaGoLive") NAQD pul faqat kassa hujjati bilan harakatlanadi:
--     • maosh     — kassa_salary_pay(p): salary_payments qatori + KO-2 (Dt 6710 Kt 5010) BITTA tranzaksiyada (tasdiqlangan
--                   vedomost chegarasi — mavjud darvoza trigeri); karta orqali — KO siz, Moliya menejeri / Direktor yozadi;
--     • o'zaro hisob — kassa_offset(p): xodimning ish haqidan farzandining o'quv to'lovi (naqdsiz dalolatnoma, Dt 6710 Kt 4010 /
--                   6310) — maosh to'lovi, o'quv to'lovi va dalolatnoma BITTA tranzaksiyada; faqat Direktor; kassa_offset_void;
--     • avans     — «Kassa» → «+ Chiqim so'rovi» → «Ish haqi avansi» (2-ro'yxat tasdig'i, T1 dan katta — Direktor ham) → kassir
--                   pulni berganda staff_advances qatori shu tranzaksiyada yoziladi (oy vedomosti tasdiqlangan bo'lsa — rad);
--     • xodim qaytargan pul (acc-1) — «+ Kirim» → «Xodim qaytargan pul» (KO-1, oy tanlanadi): avans qaytdi (OP-08, Kt 4210) — shu oy
--                   naqd avans qoldig'idan oshmaydi, oy vedomosti tasdiqlangan bo'lsa rad, staff_advances ga MANFIY qator (vedomost
--                   avansni sof summada ushlaydi); maosh qaytdi (OP-09, Kt 6710) — shu oy naqd berilgan maoshdan oshmaydi,
--                   salary_payments ga MANFIY qator (darvoza, qoldiq va hisobotlar sof berilganni ko'radi; qaytgan pul yana berilishi
--                   mumkin). Ikkalasi shu tranzaksiyada; shu kunda bekor qilinsa qator olib tashlanadi (izchillik buzilsa — rad);
--                   qaytim yozilgan avans / maosh orderining o'zi undan oldin bekor qilinmaydi (oy avansi / berilgan maosh manfiy
--                   bo'lardi); kassir oynasidagi qoldiqlar (avans, maosh, hisobdor, kamomad) — kassa_staff_open;
--     • qaytarish — kassa_refund_request(p): Direktor tasdiqlaydi (so'rov = tasdiq), balans O'ZGARMAYDI; kassir pulni berganda
--                   (kassa_doc_pay) refund_invoice shu tranzaksiyada bajariladi — balans KO-2 sanasida o'zgaradi; o'quvchi avansini
--                   naqd qaytarish (crit-2) — avans ham pul berilganda kamayadi; naqdsiz qaytarish — avvalgidek refund_invoice;
--     • xarajat   — KO-2 «Xarajat» o'tkazilganda har qatori «Buxgalteriya»ga (expenses) ko'chiriladi (statiya → eski toifa:
--                   app.kassa_exp_category), bekor qilinsa — olib tashlanadi.
--   Himoya (F1.13 qabul mezoni: funksiyani chetlab o'tadigan naqd yo'l yo'q): kassa ishga tushgach salary_payments,
--     staff_advances va expenses jadvallariga NAQD (yoki usuli ko'rsatilmagan) yozuvni to'g'ridan-to'g'ri qo'shib bo'lmaydi;
--     kassa hujjatiga bog'langan qator o'zgartirilmaydi va o'chirilmaydi (faqat «Kassa»dan, hujjatni bekor qilish orqali).
--     Kassa to'xtatilganda ham (ishga-tushirish §9; g4r-2): bog'langan qator o'zgarmaydi, oxirgi kassa kuni va undan oldingi sana bilan
--     naqd yozuv kiritilmaydi — faqat to'xtatilgan davr sanasi bilan.
--   kassa_doc_pay / kassa_doc_void (kassa-docs.sql) shu fayldagi app.kassa_link_* funksiyalarini chaqiradi.
--   Sinov kassasi (CT-20) hujjatlari bog'lanmaydi: «Buxgalteriya», avans va maosh jadvallariga hech narsa yozilmaydi.
--   app.kassa_reconcile(from, to) — moslik tekshiruvi (P1, P4, P5, P8): nazorat ro'yxati va Telegram nazorat qatori shundan.
--   HOLAT: run-all.sql'da «--dev \ir» — prod'ga hali chiqmaydi.
-- =====================================================================

-- ---------- Eski jadvallarga ustunlar (bo'sh bo'lishi mumkin) ----------
alter table public.salary_payments add column if not exists method text;           -- 'cash' | 'card' (bo'sh — kassadan oldingi yozuv)
alter table public.salary_payments add column if not exists "cashDocId" text;      -- naqd to'lovning chiqim orderi (cash_docs.id)
alter table public.staff_advances  add column if not exists method text;
alter table public.staff_advances  add column if not exists "cashDocId" text;
alter table public.refunds         add column if not exists method text;
alter table public.refunds         add column if not exists "cashDocId" text;
alter table public.expenses        add column if not exists method text;           -- 'cash' | 'bank' | 'card' | 'accountable'
alter table public.expenses        add column if not exists "cashDocId" text;
alter table public.expenses        add column if not exists "articleId" text;      -- standart statiya (fin_articles.id)
alter table public.expenses        add column if not exists "counterpartyId" text; -- kontragent (fin_counterparties.id)
create index if not exists salary_payments_cash_doc_idx on public.salary_payments ("cashDocId") where "cashDocId" is not null;
create index if not exists staff_advances_cash_doc_idx  on public.staff_advances  ("cashDocId") where "cashDocId" is not null;
create index if not exists expenses_cash_doc_idx        on public.expenses        ("cashDocId") where "cashDocId" is not null;
create index if not exists refunds_cash_doc_idx         on public.refunds         ("cashDocId") where "cashDocId" is not null;

-- JSON'dan sonni xavfsiz o'qish (bo'sh / noto'g'ri — NULL).
create or replace function app.kassa_num(p jsonb, p_key text) returns numeric
language plpgsql immutable set search_path = public, app, pg_temp as $$
declare v numeric;
begin
  if p is null or jsonb_typeof(p -> p_key) not in ('number', 'string') then return null; end if;
  begin v := (p ->> p_key)::numeric; exception when others then return null; end;
  if v = 'NaN'::numeric or abs(v) >= 1e12 then return null; end if;
  return round(v, 2);
end $$;
revoke all on function app.kassa_num(jsonb, text) from public, anon, authenticated;

-- Xodim kaliti (maosh va avans jadvallaridagi "teacherId"): kodi (IQT-… / IQX-…), bo'lmasa qator id — mijozdagi qoida bilan bir xil.
create or replace function app.kassa_payee_code(p_ref text) returns text
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_coll text := split_part(coalesce(p_ref, ''), ':', 1); v_row text; v_code text;
begin
  v_row := substr(coalesce(p_ref, ''), length(v_coll) + 2);
  if v_coll = 'teachers' then select coalesce(nullif(btrim(t."teacherId"), ''), t.id) into v_code from public.teachers t where t.id = v_row;
  elsif v_coll = 'staff' then select coalesce(nullif(btrim(s."staffId"), ''), s.id) into v_code from public.staff s where s.id = v_row;
  end if;
  return v_code;
end $$;
revoke all on function app.kassa_payee_code(text) from public, anon, authenticated;

-- «Buxgalteriya»ga (expenses) ko'chiriladigan xarajat qatorining eski toifasi — KO-2 «Xarajat» ham, avans hisoboti (АО-1) ham shu
--   bitta qoida bilan (acc-9): avval fin_category_map; xaritada yo'q statiya — OP-18 (asosiy vosita) «Inventar» (reja §4.4: «Inventar
--   EX-21/EX-16 yoki OP-18»), qolganlari «Boshqa». Toifa xaritadan olinmagan bo'lsa o_label — statiya nomi: ko'chgan yozuv izohi shu
--   bilan boshlanadi (Direktor «Boshqa» ichida nima ekanini ko'radi: «Sotish uchun tovar xaridi: …», «Yetkazib beruvchilar bilan
--   hisob-kitob: …»). Eski «Buxgalteriya» — barcha naqd chiqimlarning to'liq ro'yxati bo'lib qoladi (asosiy vosita va tovar ham).
create or replace function app.kassa_exp_category(p_article text, out o_category text, out o_label text)
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(m.category, case when p_article = 'OP-18' then 'Inventar' else 'Boshqa' end),
         case when m.category is null then (select a."nameUz" from public.fin_articles a where a.id = p_article) end
    from (select (select x.category from public.fin_category_map x where x."articleId" = p_article order by x.category limit 1) as category) m
$$;
revoke all on function app.kassa_exp_category(text) from public, anon, authenticated;

-- ---------- Himoya: kassa ishga tushgach naqd yozuv faqat kassa funksiyalari orqali ----------
--   Istisno (crit-1): sanasi KASSA ISHLAMAGAN kunga tushgan naqd yozuv (usuli 'cash' yoki ko'rsatilmagan: kech kelgan xarajat cheki,
--   maosh / avans qog'ozi — o'sha pul kassadan sanashdan oldin chiqqan) — faqat Direktor kiritadi; davr qulfi (trg_fin_zlock) baribir
--   amal qiladi. Boshqalarga — alohida xabar (kassa:pre_live). Kassa ishlamagan kun (g4v-1, kassa-day.sql app.kassa_pre_day) — birinchi
--   ishga tushgan kundan oldin yoki to'xtatilgan davr ichida; kassa ishlagan (yopilgan) davr kuni — Direktorga ham faqat «Kassa» orqali
--   (kassa:live_day). Nazorat ro'yxatida «Kassa ishga tushishidan oldingi naqd yozuvlar» yoki «Kassani to'xtatish va qayta ishga tushirish»
--   bo'lib ko'rinadi. Boshqa usullar (hisobdor shaxs, karta orqali maosh) — istisnosiz, avvalgidek.
--   Kassa TO'XTATILGAN yoki qayta ishga tushirish kunini kutmoqda (g4r-2): himoya o'chmaydi — kassa hujjatiga bog'langan qator avvalgidek
--   o'zgarmaydi; oxirgi kassa kuni va undan oldingi sana bilan kassa hujjatisiz NAQD yozuv (yangi, yoki sanasi / usuli shunga o'zgargan)
--   hech kimga kiritilmaydi (kassa:paused_live_day — u kunlar kassa hujjatlari bilan yopilgan); to'xtatilgan davr sanasi — avvalgi tartibda.
--   Qayta ishga tushirish kunini kutayotgan kassada (ishga tushadigan kun o'sha kunga qo'yilgan; g4b-v1) shu kun va keyingi sana bilan ham
--   yo'q (kassa:restart_gap): u yangi kassa davrida «hujjatisiz naqd harakat» — moslik yetimi bo'lib qolardi (sanash va ishga tushadigan
--   kunni qo'yishda shu qoida: kassa_opening_set — kassa:restart_gap, fin_org_set — kassa:live_gap).
create or replace function app.kassa_cash_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_m text; v_msg text; v_live date; v_day date; v_on boolean; v_p jsonb; v_rday date;
begin
  -- Xarajatga standart statiya — eski toifadan (fin_category_map); «payroll__» (maosh hisoblash) qatoriga tegilmaydi.
  --   (Shartlar ichma-ich: «articleId» ustuni faqat expenses jadvalida bor — boshqa jadvalda bu ifoda hisoblanmasligi kerak.)
  if tg_table_name = 'expenses' and tg_op <> 'DELETE' then
    if new."articleId" is null and coalesce(new.id, '') not like 'payroll\_\_%' then
      select m."articleId" into new."articleId" from public.fin_category_map m where m.category = new.category;
    end if;
  end if;
  if coalesce(current_setting('iqror.kassa_rpc', true), '') = '1' or app.is_system() then
    return coalesce(new, old);
  end if;
  v_on := app.kassa_live();
  if not v_on then   -- kassa hali ishga tushmagan — avvalgidek; to'xtatilgan yoki qayta ishga tushishini kutayotgan kassa — pastda
    v_p := app.kassa_periods('main');
    if not coalesce((v_p ->> 'hold')::boolean, false) then return coalesce(new, old); end if;
  end if;
  if tg_op = 'DELETE' then
    if old."cashDocId" is not null then
      raise exception 'Bu yozuv kassa hujjatiga bog''langan — «Kassa» bo''limida hujjatni bekor qilish orqali olib tashlanadi' using errcode = '42501', hint = 'kassa:linked_row';
    end if;
    return old;
  end if;
  v_m := coalesce(new.method, '');
  v_day := app.fin_text_day(new.date);
  if tg_op = 'UPDATE' and (old."cashDocId" is not null or new."cashDocId" is not null) then
    -- «Yangi noyob ID berish» (id-guards.sql: rekey_payroll_id) xodim kalitini tarix qatorlarida ham almashtiradi — faqat shu ustun.
    if coalesce(current_setting('iqror.rekey', true), '') = '1' and tg_table_name in ('salary_payments', 'staff_advances')
       and (to_jsonb(new) - 'updatedAt' - 'teacherId') = (to_jsonb(old) - 'updatedAt' - 'teacherId') then
      return new;
    end if;
    if (to_jsonb(new) - 'updatedAt') is distinct from (to_jsonb(old) - 'updatedAt') then
      raise exception 'Bu yozuv kassa hujjatiga bog''langan — o''zgartirilmaydi' using errcode = '42501', hint = 'kassa:linked_row';
    end if;
    return new;
  end if;
  if tg_op = 'INSERT' and new."cashDocId" is not null then
    raise exception 'Kassa hujjati havolasini faqat kassa funksiyalari qo''yadi' using errcode = '42501', hint = 'kassa:linked_row';
  end if;
  if not v_on then
    -- g4r-2: to'xtatilgan kassa — oxirgi kassa kuni va undan oldingi sana bilan kassa hujjatisiz naqd yozuv hech kimga kiritilmaydi;
    --   g4b-v1: qayta ishga tushirish kunini kutayotgan kassada — shu kun va keyingi sana bilan ham
    if v_m in ('', 'cash') and not (tg_table_name = 'expenses' and coalesce(new.id, '') like 'payroll\_\_%')
       and (tg_op = 'INSERT' or coalesce(old.method, '') not in ('', 'cash') or app.fin_text_day(old.date) is distinct from v_day) then
      if v_day <= (v_p ->> 'last')::date then
        if app.kassa_pre_day('main', v_day) then
          raise exception '% — oxirgi kassa kunidan (%) oldingi sana: kassa to''xtatilgan paytda bunday naqd yozuv kiritilmaydi. Kassa ishlamagan kun (ishga tushishdan oldingi yoki oldingi to''xtatilgan davr) yozuvini kassa qayta ishga tushgach Direktor kiritadi',
            to_char(v_day, 'DD.MM.YYYY'), to_char((v_p ->> 'last')::date, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:paused_live_day';
        end if;
        raise exception '% — kassa kuni edi (oxirgi kassa kuni %): kassa to''xtatilgan paytda bu sana bilan kassa hujjatisiz naqd yozuv kiritilmaydi — u kun kassa hujjatlari bilan yopilgan. To''xtatilgan davr harakati oxirgi kassa kunidan keyingi sana bilan yoziladi; u kunning tuzatishi — kassa qayta ishga tushgach, «Kassa» orqali',
          to_char(v_day, 'DD.MM.YYYY'), to_char((v_p ->> 'last')::date, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:paused_live_day';
      end if;
      --   to'xtatilgan kassada ham, qayta ishga tushirish kuni tayyorlangan va hali kelmagan bo'lsa (g4b: aks holda ishga tushadigan kun
      --   qo'yilgach yangi davr yetimi bo'lardi); kun o'tib ketgan bo'lsa — eski tartib davom etadi, qayta ishga tushirish esa keyingi kun
      --   bilan qayta sanashni talab qiladi (kassa-day.sql app.kassa_golive_guard — kassa:restart_gap)
      select k."restartDay" into v_rday from public.cash_desks k where k.id = 'main' and k."restartDay" > (v_p ->> 'last')::date;
      if v_day >= v_rday and (not coalesce((v_p ->> 'paused')::boolean, false) or v_rday > app.fin_today()) then
        raise exception '% — qayta ishga tushirish kuni (%) yoki undan keyingi sana: kassa shu kundan qayta ishlaydi — bu kunlarning naqd harakati kassa hujjatisiz yozilmaydi (kassa qayta ishga tushgach, «Kassa» orqali)',
          to_char(v_day, 'DD.MM.YYYY'), to_char(v_rday, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:restart_gap';
      end if;
    end if;
    return new;
  end if;
  if tg_op = 'UPDATE' then
    -- (usuli ko'rsatilmagan yozuv ham naqd hisoblanadi — moslik shunday sanaydi: naqdsiz yozuvni usulsiz qilish ham «Kassa» orqali; g4b)
    if v_m in ('', 'cash') and coalesce(old.method, '') not in ('', 'cash')
       and not (tg_table_name = 'expenses' and coalesce(new.id, '') like 'payroll\_\_%') then
      v_msg := 'Naqd (yoki usuli ko''rsatilmagan) yozuv faqat «Kassa» orqali kiritiladi — naqdsiz yozuvda to''lov usulini tanlang';
    elsif tg_table_name = 'expenses' and v_m = 'accountable' and coalesce(old.method, '') <> 'accountable' then
      v_msg := 'Hisobdor shaxs xarajati «Kassa» → «Avans hisoboti» orqali yoziladi';
    elsif v_m in ('', 'cash') and v_day is distinct from app.fin_text_day(old.date)
          and not (tg_table_name = 'expenses' and coalesce(new.id, '') like 'payroll\_\_%')
          and v_day is not null and not app.kassa_pre_day('main', v_day) then
      -- crit-1, g4v-1: kassa hujjatisiz naqd yozuvni kassa ishlagan kunga (yopilgan davrdagi kunga ham) ko'chirish — u kunning kassa
      --   hujjatlarida yo'q naqd harakat bo'lib qolardi (yaratishdagi qoidani tahrir orqali chetlab o'tish yo'li bo'lmasin).
      v_msg := 'Kassa hujjatisiz naqd yozuvning sanasini kassa ishga tushgan kunga (yoki keyingi kunga) o''zgartirib bo''lmaydi — bu kunlardagi naqd harakat «Kassa» orqali yoziladi';
    end if;
  else   -- INSERT
    if tg_table_name = 'salary_payments' then
      v_msg := 'Kassa ishga tushgan: maosh «Maosh berish» oynasidan, to''lov usuli bilan yoziladi (naqd — kassa chiqim orderi bilan)';
    elsif tg_table_name = 'staff_advances' then
      if v_m <> 'card' then
        v_msg := 'Kassa ishga tushgan: naqd avans «Kassa» → «+ Chiqim so''rovi» → «Ish haqi avansi» orqali beriladi';
      end if;
    elsif tg_table_name = 'expenses' then
      -- «payroll__YYYY-MM» — oylik maoshni hisoblash qatori (pul harakati emas): avvalgidek.
      --   Hisobdor shaxs orqali xarajat ('accountable') — faqat «Avans hisoboti» dalolatnomasidan (shu funksiya bayroq bilan yozadi):
      --   aks holda xarajat ikki marta (qo'lda va hisobotdan) yozilib, hisobdordagi qoldiq kamaymay qolardi.
      if coalesce(new.id, '') not like 'payroll\_\_%' and v_m not in ('bank', 'card') then
        v_msg := case when v_m = 'accountable'
                      then 'Kassa ishga tushgan: hisobdor shaxs xarajati «Kassa» → «Avans hisoboti» orqali yoziladi (avans qoldig''idan hisobdan chiqariladi)'
                      else 'Kassa ishga tushgan: naqd xarajat «Kassa» → «+ Chiqim so''rovi» orqali yoziladi; naqdsiz xarajatda to''lov usulini tanlang' end;
      end if;
    end if;
  end if;
  if v_msg is null then return new; end if;
  -- kassa ishlamagan kun (crit-1, g4v-1): faqat NAQD yozuv (usuli 'cash' yoki ko'rsatilmagan) va faqat Direktor; boshqa usul
  --   (hisobdor shaxs, karta orqali maosh …) — avvalgidek o'z oynasi orqali (sozlama qatori kassa_live() da FOR SHARE bilan ushlangan)
  if v_m in ('', 'cash') then
    if app.kassa_pre_day('main', v_day) then
      if app.is_admin() then return new; end if;
      v_live := (app.kassa_periods('main') ->> 'first')::date;
      if v_day < v_live then
        raise exception '% — kassa ishga tushishidan (%) oldingi sana: bunday naqd yozuvni faqat Direktor kiritadi (kech kelgan hujjat; o''sha pul kassadan sanashdan oldin chiqqan)',
          to_char(v_day, 'DD.MM.YYYY'), to_char(v_live, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:pre_live';
      end if;
      raise exception '% — kassa to''xtatilgan davr sanasi (kassa ishlamagan kun): bunday naqd yozuvni faqat Direktor kiritadi (kech kelgan hujjat; o''sha pul qayta ishga tushirish sanashidan oldin harakatlangan)',
        to_char(v_day, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:pre_live';
    end if;
    -- g4v-1: yopilgan kassa davri kuni (hozirgi ishga tushish kunidan oldin, lekin kassa ishlagan) — Direktorga ham kassa hujjatisiz yo'q
    select o."kassaGoLive" into v_live from public.fin_org o where o.id = 'main';
    if v_day < v_live then
      raise exception '% — kassa kuni edi (kassa ishlagan davr): bu sana bilan kassa hujjatisiz naqd yozuv kiritilmaydi — u kun kassa hujjatlari bilan yopilgan. Tuzatish — «Kassa» orqali (o''sha kunning sanash farqi, kamomad qarori — buxgalter bilan)',
        to_char(v_day, 'DD.MM.YYYY') using errcode = '42501', hint = 'kassa:live_day';
    end if;
  end if;
  raise exception '%', v_msg using errcode = '42501', hint = 'kassa:cash_only_kassa';
end $$;
revoke all on function app.kassa_cash_guard() from public, anon, authenticated;
do $$ declare t text; begin
  foreach t in array array['salary_payments', 'staff_advances', 'expenses'] loop
    execute format('drop trigger if exists trg_kassa_cash_guard on public.%I', t);
    execute format('create trigger trg_kassa_cash_guard before insert or update or delete on public.%I for each row execute function app.kassa_cash_guard()', t);
  end loop;
end $$;

-- ---------- Maosh ----------
--   p: id ('sp_…' — oynaning barqaror kaliti), method ('cash' | 'card'), teacherId, payeeRef ('teachers:<id>' | 'staff:<id>'),
--      teacherName, month ('YYYY-MM'), paid (> 0), gross, advance, deduction, subBonus, net, carryIn, carryOut, date (karta uchun), note
--   Naqd: faqat kassa operatori (favqulodda — Direktor); vedomost tasdig'i yoqilmagan oy uchun — faqat Direktor (RP-06 da ko'rinadi).
--   Tasdiqlangan vedomost, xodim qatori va summa chegarasi — mavjud trigger (payroll-approval.sql: app.salary_payment_gate).
create or replace function public.kassa_salary_pay(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_id text; v_method text; v_tid text; v_ref text; v_month text; v_paid numeric; v_from text; v_gate_off boolean;
  v_ex public.salary_payments%rowtype; v_doc_id text; v_dup boolean; v_doc public.cash_docs%rowtype; v_date text; v_key text;
begin
  -- Avval ruxsat (begona rolga holat haqida hech narsa oshkor qilinmaydi), keyin ma'lumot tekshiruvi.
  if not (app.kassa_operator() or app.is_admin() or app.is_finance_mgr()) then
    raise exception 'Ruxsat yo''q: maosh to''lovini kassir (naqd) yoki Moliya menejeri (karta) yozadi' using errcode = '42501', hint = 'kassa:cash_role';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_method := coalesce(p ->> 'method', '');
  if v_method = 'cash' then
    if not app.kassa_live() then
      raise exception 'Kassa ishga tushirilmagan' using errcode = 'P0001', hint = 'kassa:not_live';
    end if;
    if not (app.kassa_operator() or app.is_admin()) then
      raise exception 'Ruxsat yo''q: naqd maoshni kassir (favqulodda — Direktor) beradi' using errcode = '42501', hint = 'kassa:cash_role';
    end if;
  elsif v_method = 'card' then
    if not (app.is_admin() or app.is_finance_mgr()) then
      raise exception 'Ruxsat yo''q: karta orqali to''lovni Moliya menejeri yoki Direktor yozadi' using errcode = '42501';
    end if;
  else
    raise exception 'To''lov usuli noto''g''ri (naqd / karta)' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  v_id := btrim(coalesce(p ->> 'id', ''));
  v_tid := btrim(coalesce(p ->> 'teacherId', ''));
  v_ref := btrim(coalesce(p ->> 'payeeRef', ''));
  v_month := coalesce(p ->> 'month', '');
  if v_id !~ '^sp_.{3,200}$' or v_tid = '' or v_ref !~ '^(teachers|staff):.+$' or v_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Maosh to''lovi ma''lumoti to''liq emas' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  v_paid := app.kassa_amount(p -> 'paid', 'Maosh');
  v_key := 'sal_' || md5(v_id);
  perform pg_advisory_xact_lock(hashtext('iqror_doc:' || v_key));   -- L0: shu oynadan parallel / qayta yuborish navbatga turadi
  select * into v_ex from public.salary_payments s where s.id = v_id;
  if found then
    if coalesce(v_ex.paid, 0) <> v_paid or coalesce(v_ex."teacherId", '') <> v_tid or coalesce(v_ex.month, '') <> v_month then
      raise exception 'Shu kalit bilan boshqa maosh to''lovi yozilgan' using errcode = '22023', hint = 'kassa:ref_mismatch';
    end if;
    return jsonb_build_object('ok', true, 'dup', true, 'id', v_id, 'row', to_jsonb(v_ex),
      'kassa', (select jsonb_build_object('docId', c.id, 'no', c.no, 'day', c."businessDay", 'status', c.status) from public.cash_docs c where c.id = v_ex."cashDocId"));
  end if;
  select nullif(btrim(coalesce(c."payrollApprovalFrom", '')), '') into v_from from public.config c where c.id = 'finance';
  v_gate_off := v_from is null or v_month < v_from;
  if v_method = 'cash' and v_gate_off and not app.is_admin() then
    raise exception 'Naqd maosh berilmaydi: % oy uchun vedomost tasdig''i yoqilmagan — faqat Direktor ruxsati bilan', v_month
      using errcode = '42501', hint = 'kassa:payroll_gate';
  end if;
  v_date := to_char(app.fin_today(), 'YYYY-MM-DD');
  if v_method = 'card' and coalesce(p ->> 'date', '') ~ '^\d{4}-\d{2}-\d{2}$' and (p ->> 'date') <= v_date
     and (p ->> 'date') >= to_char(app.fin_today() - 31, 'YYYY-MM-DD') then
    v_date := p ->> 'date';
  end if;
  perform app.kassa_flag(true);
  insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, gross, advance, deduction, "subBonus", net,
                                      "carryIn", paid, "carryOut", date, note, method)
    values (v_id, v_tid, v_ref, left(btrim(coalesce(p ->> 'teacherName', '')), 200), v_month, app.kassa_num(p, 'gross'), app.kassa_num(p, 'advance'),
            app.kassa_num(p, 'deduction'), app.kassa_num(p, 'subBonus'), app.kassa_num(p, 'net'), app.kassa_num(p, 'carryIn'), v_paid,
            app.kassa_num(p, 'carryOut'), v_date, left(btrim(coalesce(p ->> 'note', '')), 300), v_method);
  if v_method = 'cash' then
    select b.o_id, b.o_dup into v_doc_id, v_dup from app.kassa_doc_build(jsonb_build_object(
        'desk', 'main', 'op', 'out_salary', 'amount', v_paid, 'partyType', 'employee', 'partyId', v_ref,
        'basis', 'Ish haqi: ' || v_month, 'clientRef', v_key, 'sourceTable', 'salary_payments', 'sourceId', v_id,
        'sourceSnapshot', jsonb_build_object('month', v_month, 'teacherId', v_tid, 'gateOff', v_gate_off)), 'KO2', v_uid, true) b;
    v_doc := app.kassa_doc_post(v_doc_id, v_uid);
    update public.salary_payments set "cashDocId" = v_doc.id, date = to_char(v_doc."businessDay", 'YYYY-MM-DD') where id = v_id;
  end if;
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', false, 'id', v_id, 'method', v_method,
    'row', (select to_jsonb(s) from public.salary_payments s where s.id = v_id),
    'kassa', case when v_doc.id is not null then jsonb_build_object('docId', v_doc.id, 'no', v_doc.no, 'day', v_doc."businessDay", 'status', v_doc.status) end);
end $$;
revoke all on function public.kassa_salary_pay(jsonb) from public, anon;
grant execute on function public.kassa_salary_pay(jsonb) to authenticated;

-- ---------- Avans: so'rov paytidagi tekshiruv (kassa_payout_request chaqiradi) ----------
create or replace function app.kassa_advance_check(p_month text) returns void
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_m text := app.payroll_locked_month(p_month, p_month);
begin
  if v_m is not null then
    raise exception 'Oylik vedomost tasdiqlangan (%): bu oy uchun avans berilmaydi — Direktor oyni qayta ochadi', v_m
      using errcode = '42501', hint = 'kassa:advance_locked';
  end if;
end $$;
revoke all on function app.kassa_advance_check(text) from public, anon, authenticated;

-- ---------- O'qish: xodim bilan hisob-kitob qoldiqlari («+ Kirim» shakli uchun; qoida — server tekshiruvida) ----------
--   p_party — 'teachers:<id>' | 'staff:<id>'; p_month — 'YYYY-MM' (avans / maosh oyi; bo'sh — faqat oyga bog'liq bo'lmagan qoldiqlar).
--   advance — shu oy naqd avansi: berilgan, qaytarilgan, qoldiq (avans qaytimi chegarasi); salary — shu oy naqd berilgan maosh:
--   berilgan, qaytarilgan, sof (maosh qaytimi chegarasi); locked — oy vedomosti tasdiqlangan (avans qaytimi qabul qilinmaydi);
--   accountable — hisobdordagi hisobot qilinmagan qoldiq (4230); damage — xodim zimmasidagi kamomad (4730). Doira — p_desk kassasi
--   (sinov kassasi — o'z qoldig'i). Kirim orderini yozadiganlar: kassa operatori va Direktor (acc-1, acc-3, acc-4).
create or replace function public.kassa_staff_open(p_desk text, p_party text, p_month text default null) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_desk text := coalesce(nullif(btrim(coalesce(p_desk, '')), ''), 'main'); v_pid text; v_name text; v_code text;
        v_m text := nullif(btrim(coalesce(p_month, '')), '');
begin
  if not (app.kassa_operator() or app.is_admin()) then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  if v_m is not null and v_m !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Oy noto''g''ri (YYYY-MM)' using errcode = '22023', hint = 'kassa:month';
  end if;
  select k.o_id, k.o_name into v_pid, v_name from app.kassa_party('employee', p_party, null) k;
  v_code := app.kassa_payee_code(v_pid);
  return jsonb_build_object('ok', true, 'partyId', v_pid, 'name', v_name, 'code', v_code, 'month', v_m,
    'accountable', app.kassa_acc_open(v_pid, v_desk), 'damage', app.kassa_damage_open(v_pid, v_desk),
    'advance', case when v_m is not null then
                 (select jsonb_build_object('given', coalesce(sum(a.amount) filter (where a.amount > 0), 0),
                                            'returned', coalesce(-sum(a.amount) filter (where a.amount < 0), 0),
                                            'open', coalesce(sum(coalesce(a.amount, 0)), 0))
                    from public.staff_advances a
                   where a."teacherId" = v_code and coalesce(nullif(a.month, ''), left(coalesce(a.date, ''), 7)) = v_m
                     and coalesce(a.method, '') in ('', 'cash')) end,
    'salary', case when v_m is not null then
                (select jsonb_build_object('paid', coalesce(sum(s.paid) filter (where s.paid > 0), 0),
                                           'returned', coalesce(-sum(s.paid) filter (where s.paid < 0), 0),
                                           'net', coalesce(sum(coalesce(s.paid, 0)), 0))
                   from public.salary_payments s
                  where s."teacherId" = v_code and s.month = v_m and coalesce(s.method, '') in ('', 'cash')) end,
    'locked', case when v_m is not null then app.payroll_locked_month(v_m, v_m) is not null end);
end $$;
revoke all on function public.kassa_staff_open(text, text, text) from public, anon;
grant execute on function public.kassa_staff_open(text, text, text) to authenticated;

-- ---------- Kassa hujjatiga bog'langan to'lov qatori (naqd o'quv to'lovi KO-1, o'zaro hisob dalolatnomasi) ----------
--   Order va dalolatnoma o'zgarmaydi — ularga bog'langan to'lov qatori ham: summa, kanal, o'quvchi, holat, kun (raw.manual / raw.date),
--   havola va fiskal chek № faqat kassa funksiyalari (bayroq) yoki server orqali o'zgaradi. Bekor qilish — «Kassa»da hujjat orqali
--   (to'lov ham, taqsimot ham teskari bo'ladi). Boshqa raw maydonlari (izoh, belgilar) — avvalgidek. Havolani ham faqat kassa qo'yadi.
create or replace function app.kassa_pay_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if coalesce(current_setting('iqror.kassa_rpc', true), '') = '1' or app.is_system() then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    if old."cashDocId" is not null then
      raise exception 'Bu to''lov kassa hujjatiga bog''langan — «Kassa» bo''limida hujjatni bekor qilish orqali bekor qilinadi' using errcode = '42501', hint = 'kassa:linked_row';
    end if;
    return old;
  end if;
  if tg_op = 'INSERT' then
    if new."cashDocId" is not null then
      raise exception 'Kassa hujjati havolasini faqat kassa funksiyalari qo''yadi' using errcode = '42501', hint = 'kassa:linked_row';
    end if;
    return new;
  end if;
  if old."cashDocId" is null then
    if new."cashDocId" is not null then
      raise exception 'Kassa hujjati havolasini faqat kassa funksiyalari qo''yadi' using errcode = '42501', hint = 'kassa:linked_row';
    end if;
    return new;
  end if;
  -- Deploy paytidagi kalit kanonlash (invoice-guards.sql: o'quvchi doc id -> studentId) — faqat «studentId» o'zgarsa, ruxsat.
  if coalesce(current_setting('iqror.migrating', true), '') = '1'
     and (to_jsonb(new) - 'studentId' - 'statusAt') = (to_jsonb(old) - 'studentId' - 'statusAt') then
    return new;
  end if;
  if new.amount is distinct from old.amount or new.provider is distinct from old.provider or new."studentId" is distinct from old."studentId"
     or new.status is distinct from old.status or new.matched is distinct from old.matched or new."cashDocId" is distinct from old."cashDocId"
     or new."fiscalNo" is distinct from old."fiscalNo" or new."createdAt" is distinct from old."createdAt"
     or app.pay_day(new."createdAt", new.raw) is distinct from app.pay_day(old."createdAt", old.raw) then
    raise exception 'Bu to''lov kassa hujjatiga bog''langan — o''zgartirilmaydi (xato bo''lsa «Kassa» bo''limida hujjatni bekor qiling)' using errcode = '42501', hint = 'kassa:linked_row';
  end if;
  return new;
end $$;
revoke all on function app.kassa_pay_guard() from public, anon, authenticated;
drop trigger if exists trg_kassa_pay_guard on public.payments;   -- trg_fin_server_ts va trg_fin_zlock dan keyin ishlaydi (alifbo tartibi)
create trigger trg_kassa_pay_guard before insert or update or delete on public.payments for each row execute function app.kassa_pay_guard();

-- ---------- Qaytarish: Direktor tasdiqlaydi (so'rov), pul kassadan beriladi ----------
--   p: target ('invoice' | 'payment' | 'credit'), id, amount, reason, clawback (avansni ham qaytarish), payee (kimga beriladi — to'liq
--      F.I.Sh.), requestDate (ariza sanasi, ixtiyoriy), clientRef. Hech narsa o'zgarmaydi — faqat tasdiqlangan KO-2 so'rovi paydo bo'ladi;
--      qaytarishning o'zi kassir pulni bergan paytda (kassa_doc_pay → app.kassa_link_paid) bajariladi.
--   'credit' (crit-2) — o'quvchi avansini (student_credit) naqd qaytarish, masalan ketgan o'quvchining oldindan to'lagan puli: id —
--      o'quvchi kodi; summa o'quvchi bo'yicha navbat (L1) ostida o'qilgan joriy avansdan oshmaydi; KO-2 — bitta qator Dt 6310 Kt 5010
--      (OP-15). Faqat naqd va faqat kassa ishga tushgach; naqdsiz avans qaytarish — F2.11.
--   So'rovlar navbati (ui-3): shu maqsad bo'yicha hali pul berilmagan (so'rov / tasdiqlangan) qaytarish so'rovlari + yangi summa
--      qaytariladigan summadan oshmaydi — faktura: to'langan summa; biriktirilmagan to'lov: uning summasi (faqat bitta so'rov); avans:
--      joriy avans (avans qaytarish so'rovlari va fakturadan qaytarishga qo'shilgan avans bilan) — aks holda kassa:refund_pending.
--      Oyna o'sha kalit (clientRef) bilan qayta yuborsa (javob yo'qolgan) — mavjud so'rov qaytadi (dup), qayta tekshirilmaydi.
create or replace function public.kassa_refund_request(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_target text; v_tid text; v_amount numeric; v_reason text; v_payee text; v_claw boolean; v_ref text;
  v_inv record; v_sid text; v_cr numeric := 0; v_pst text; v_pamt numeric; v_lines jsonb; v_month text := to_char(app.fin_today(), 'YYYY-MM');
  v_id text; v_dup boolean; v_req text; v_basis text; v_ex public.cash_docs%rowtype; v_held numeric; v_have numeric;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: qaytarishni faqat Direktor tasdiqlaydi' using errcode = '42501'; end if;
  if not app.kassa_live() then raise exception 'Kassa ishga tushirilmagan' using errcode = 'P0001', hint = 'kassa:not_live'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_target := coalesce(p ->> 'target', ''); v_tid := btrim(coalesce(p ->> 'id', ''));
  v_amount := app.kassa_amount(p -> 'amount', 'Qaytarish');
  v_reason := left(btrim(coalesce(p ->> 'reason', '')), 300);
  v_payee := left(btrim(coalesce(p ->> 'payee', '')), 200);
  v_claw := app.kassa_bool(p, 'clawback');
  v_ref := btrim(coalesce(p ->> 'clientRef', ''));
  if v_target not in ('invoice', 'payment', 'credit') or v_tid = '' or v_ref !~ '^[A-Za-z0-9_.:-]{6,70}$' then
    raise exception 'Qaytarish ma''lumoti to''liq emas' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  if length(v_reason) < 3 then raise exception 'Qaytarish sababini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  if length(v_payee) < 5 then raise exception 'Pul kimga berilishini to''liq yozing (F.I.Sh.)' using errcode = '22023', hint = 'kassa:party'; end if;
  begin v_req := to_char(nullif(p ->> 'requestDate', '')::date, 'DD.MM.YYYY'); exception when others then v_req := null; end;
  v_basis := 'Qaytarish: ' || case when v_target = 'credit' then 'o‘quvchi avansi — ' else '' end || v_reason
             || case when v_req is not null then '; ariza ' || v_req else '' end;
  if v_target = 'credit' then   -- o'quvchi kodi — apply_payment bilan bir xil kanonik kalit (avans qatori va L1 navbati shu kalit bilan)
    select s."studentId" into v_sid from public.students s where s.id = v_tid or s."studentId" = v_tid order by (s.id = v_tid) desc limit 1;
    v_sid := coalesce(nullif(v_sid, ''), v_tid); v_tid := v_sid;
  end if;
  -- O'sha kalit bilan qayta yuborish — mavjud so'rov (L0 — kassa_doc_build bilan bir xil qulf)
  perform pg_advisory_xact_lock(hashtext('iqror_doc:ref_' || v_ref));
  select * into v_ex from public.cash_docs c where c."clientRef" = 'ref_' || v_ref;
  if found then
    if v_ex.op <> 'out_refund' or (v_ex."sourceSnapshot" ->> 'target') is distinct from v_target
       or (v_ex."sourceSnapshot" ->> 'targetId') is distinct from v_tid or (v_ex."sourceSnapshot" ->> 'amount')::numeric is distinct from v_amount then
      raise exception 'Bu oynadan boshqa qaytarish so''rovi allaqachon yuborilgan — «Kassa» → «So''rovlar»ni tekshiring' using errcode = '22023', hint = 'kassa:ref_mismatch';
    end if;
    return app.kassa_doc_json(v_ex.id) || jsonb_build_object('ok', true, 'dup', true);
  end if;

  if v_target = 'invoice' then
    select i."studentId" into v_sid from public.invoices i where i.id = v_tid;
    if not found then raise exception 'Hisob-faktura topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
    perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));   -- L1: o'quvchi bo'yicha navbat (refund_invoice bilan bir xil)
    select i.id, i."studentId", coalesce(i.amount, 0) as amount, coalesce(i.status, '') as status, coalesce(i.month, '') as month,
           case when i.status = 'paid' then greatest(coalesce(i."paidAmount", 0), coalesce(i.amount, 0)) else coalesce(i."paidAmount", 0) end as paid
      into v_inv from public.invoices i where i.id = v_tid;
    if not found then raise exception 'Hisob-faktura topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
    if v_inv.status in ('canceled', 'reversed') or v_amount > v_inv.paid + 0.5 then
      raise exception 'Qaytarib bo''lmaydi: bu hisob-fakturada % so''m to''langan', v_inv.paid using errcode = '22023', hint = 'kassa:refund';
    end if;
    select coalesce(sum((c."sourceSnapshot" ->> 'amount')::numeric), 0) into v_held from public.cash_docs c
     where c.op = 'out_refund' and c.status in ('draft', 'approved') and c."sourceSnapshot" ->> 'target' = 'invoice' and c."sourceSnapshot" ->> 'targetId' = v_tid;
    if v_held > 0 and v_held + v_amount > v_inv.paid + 0.5 then
      raise exception 'Bu hisob-faktura bo''yicha pul hali berilmagan qaytarish so''rovi bor (% so''m): yangisi bilan jami to''langan summadan (% so''m) oshadi — avval o''sha so''rovni bering yoki bekor qiling',
        v_held, v_inv.paid using errcode = '22023', hint = 'kassa:refund_pending';
    end if;
    v_sid := v_inv."studentId";
    v_lines := jsonb_build_array(jsonb_build_object(
      'debit', case when v_inv.month ~ '^\d{4}-\d{2}$' and v_inv.month > v_month then '6310' else '4010' end, 'credit', '5010', 'amount', v_amount,
      'analytics', jsonb_build_object('studentId', v_sid, 'invoiceId', v_inv.id, 'month', v_inv.month)));
    if v_claw then
      select coalesce(c.credit, 0) into v_cr from public.student_credit c where c.id = v_sid;
      v_cr := coalesce(v_cr, 0);
      if v_cr > 0 then
        -- avans boshqa hali to'lanmagan so'rovda band (avans qaytarish yoki fakturadan qaytarish bilan) — ikkinchi marta qo'shilmaydi
        select coalesce(sum(case when c."sourceSnapshot" ->> 'target' = 'credit' then (c."sourceSnapshot" ->> 'amount')::numeric
                                 else coalesce((c."sourceSnapshot" ->> 'clawbackAmount')::numeric, 0) end), 0) into v_held
          from public.cash_docs c
         where c.op = 'out_refund' and c.status in ('draft', 'approved') and c."sourceSnapshot" ->> 'studentId' = v_sid
           and (c."sourceSnapshot" ->> 'target' = 'credit' or coalesce((c."sourceSnapshot" ->> 'clawback')::boolean, false));
        if v_held > 0 then
          raise exception 'Bu o''quvchi avansi bo''yicha pul hali berilmagan qaytarish so''rovi bor (% so''m) — avval o''sha so''rovni bering yoki bekor qiling', v_held
            using errcode = '22023', hint = 'kassa:refund_pending';
        end if;
        v_lines := v_lines || jsonb_build_object('debit', '6310', 'credit', '5010', 'amount', v_cr,
                                                 'analytics', jsonb_build_object('studentId', v_sid, 'kind', 'credit_refund'));
      end if;
    end if;
  elsif v_target = 'payment' then
    -- qator qulfi: shu to'lov bo'yicha so'rovlar navbatga turadi (kassa_link_prelock ham shu qatorni qulflaydi)
    select coalesce(pm.status, ''), coalesce(pm.amount, 0) into v_pst, v_pamt from public.payments pm where pm.id = v_tid for update;
    if not found then raise exception 'To''lov topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
    if v_pst not in ('unmatched', '') then
      raise exception 'Faqat biriktirilmagan to''lov shu yo''l bilan qaytariladi (holati: %)', v_pst using errcode = '22023', hint = 'kassa:refund';
    end if;
    if abs(v_amount - v_pamt) > 0.5 then
      raise exception 'Biriktirilmagan to''lov faqat to''liq qaytariladi (% so''m)', v_pamt using errcode = '22023', hint = 'kassa:refund';
    end if;
    select coalesce(sum((c."sourceSnapshot" ->> 'amount')::numeric), 0) into v_held from public.cash_docs c
     where c.op = 'out_refund' and c.status in ('draft', 'approved') and c."sourceSnapshot" ->> 'target' = 'payment' and c."sourceSnapshot" ->> 'targetId' = v_tid;
    if v_held > 0 then
      raise exception 'Bu to''lov bo''yicha pul hali berilmagan qaytarish so''rovi bor (% so''m) — avval o''sha so''rovni bering yoki bekor qiling', v_held
        using errcode = '22023', hint = 'kassa:refund_pending';
    end if;
    v_claw := false;
    -- biriktirilmagan (aniqlanmagan) tushum 6390 da turadi (PR-13, OP-16) — qaytarish ham shu hisobdan
    v_lines := jsonb_build_array(jsonb_build_object('debit', '6390', 'credit', '5010', 'amount', v_amount, 'articleId', 'OP-16',
                                                    'analytics', jsonb_build_object('paymentId', v_tid)));
  else   -- 'credit': o'quvchi avansini naqd qaytarish (crit-2)
    perform pg_advisory_xact_lock(hashtext('iqror_pay:' || v_sid));   -- L1: avans shu navbat ostida o'qiladi (to'lov, qaytarish bilan bir xil)
    select coalesce(c.credit, 0) into v_have from public.student_credit c where c.id = v_sid;
    v_have := coalesce(v_have, 0);
    if v_have <= 0 then
      raise exception 'Bu o''quvchida qaytariladigan avans yo''q' using errcode = '22023', hint = 'kassa:credit_none';
    end if;
    if v_amount > v_have then
      raise exception 'Qaytarib bo''lmaydi: o''quvchi avansi % so''m', v_have using errcode = '22023', hint = 'kassa:credit_over';
    end if;
    select coalesce(sum(case when c."sourceSnapshot" ->> 'target' = 'credit' then (c."sourceSnapshot" ->> 'amount')::numeric
                             else coalesce((c."sourceSnapshot" ->> 'clawbackAmount')::numeric, 0) end), 0) into v_held
      from public.cash_docs c
     where c.op = 'out_refund' and c.status in ('draft', 'approved') and c."sourceSnapshot" ->> 'studentId' = v_sid
       and (c."sourceSnapshot" ->> 'target' = 'credit' or coalesce((c."sourceSnapshot" ->> 'clawback')::boolean, false));
    if v_held > 0 and v_held + v_amount > v_have then
      raise exception 'Bu o''quvchi avansi bo''yicha pul hali berilmagan qaytarish so''rovi bor (% so''m): yangisi bilan jami avansdan (% so''m) oshadi — avval o''sha so''rovni bering yoki bekor qiling',
        v_held, v_have using errcode = '22023', hint = 'kassa:refund_pending';
    end if;
    v_claw := false;
    v_lines := jsonb_build_array(jsonb_build_object('debit', '6310', 'credit', '5010', 'amount', v_amount,
                                                    'analytics', jsonb_build_object('studentId', v_sid, 'kind', 'credit_refund')));
  end if;

  perform app.kassa_flag(true);
  select b.o_id, b.o_dup into v_id, v_dup from app.kassa_doc_build(jsonb_build_object(
      'desk', 'main', 'op', 'out_refund', 'amount', v_amount + v_cr,
      -- tomon: o'quvchi (ro'yxatda bo'lsa); o'quvchi qatori yo'q (eski faktura) yoki biriktirilmagan to'lov — «boshqa» (oluvchi F.I.Sh.)
      'partyType', case when v_sid is not null and exists (select 1 from public.students st where st.id = v_sid or st."studentId" = v_sid)
                        then 'student' else 'other' end, 'partyId', v_sid, 'partyName', v_payee,
      'basis', v_basis, 'attachment', 'Yozma ariza', 'clientRef', 'ref_' || v_ref, 'needsDirector', true,
      'sourceTable', 'refunds', 'sourceId', 'kref_' || v_ref,
      -- «kim so'radi» — uid (email EMAS: hujjat suratini 2-ro'yxat, jumladan buxgalter ham o'qiydi — F1.21, D6); qaytarish
      --   jurnalidagi «kim» (refunds."byUid" / "byEmail") ni pul berilganda server o'zi yozadi (fin_server_ts).
      'sourceSnapshot', jsonb_build_object('target', v_target, 'targetId', v_tid, 'amount', v_amount, 'reason', v_reason, 'clawback', v_claw and v_cr > 0,
                                           'clawbackAmount', v_cr, 'studentId', v_sid, 'byUid', v_uid),
      'lines', v_lines), 'KO2', v_uid, true) b;
  if not v_dup then   -- Direktor so'rovni o'zi yozadi — shu uning tasdig'i
    update public.cash_docs set "dirApprovedBy" = v_uid, "dirApprovedAt" = app.fin_now() where id = v_id and status = 'draft';
    update public.cash_docs set status = 'approved' where id = v_id and status = 'draft';
  end if;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(v_id) || jsonb_build_object('ok', true, 'dup', v_dup);
end $$;
revoke all on function public.kassa_refund_request(jsonb) from public, anon;
grant execute on function public.kassa_refund_request(jsonb) to authenticated;

-- ---------- Pul berishdan OLDIN olinadigan qulflar (kassa qulfidan oldin — qulf tartibi L1 → L4) ----------
--   Xodim bilan hisob-kitob: hisobdor (iqror_acc) va kamomad (iqror_dmg) qoldig'i qulfi; avans / maosh yozuvi bilan bog'langan
--   hujjatlarda — qaytgan maoshda AVVAL oy bo'yicha maosh navbati (payroll-approval.sql salary_payment_gate: iqror_salpay, S), KEYIN
--   xodim kaliti navbati (id-guards.sql guard_payroll_key: iqror:payroll, P): naqd maosh (kassa_salary_pay) va o'zaro hisob
--   (kassa_offset) bilan BIR XIL tartib S → P → L4 — ularda maosh yozuvining darvoza trigeri kalit trigeridan oldin ishlaydi
--   (triggerlar alifbo tartibida: trg_salary_payment_gate, keyin trg_salpay_key). Teskari tartib (P → S) parallel naqd maosh bilan
--   o'zaro qulflanardi (deadlock). Avans to'lovi, avans qaytimi va bekor qilinadigan avans / maosh orderi — faqat P (avvalgi avans
--   to'lovi qulfni kassa qulfidan keyin, yozuv paytida olardi — maosh to'lovi bilan teskari tartib edi).
--   Pul berish (kassa_doc_pay), kirim (kassa_receipt) va bekor qilish (kassa_doc_void) shu funksiyani chaqiradi.
create or replace function app.kassa_link_prelock(p_doc_id text) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_op text; v_snap jsonb; v_party text; v_code text;
begin
  select c.op, c."sourceSnapshot", c."partyId" into v_op, v_snap, v_party from public.cash_docs c where c.id = p_doc_id;
  if v_op in ('out_accountable', 'in_acc_return') then   -- hisobdor qulfi (avans hisoboti bilan bir navbat): qoldiq tekshiruvi va to'lov orasida o'zgarmasin
    perform pg_advisory_xact_lock(hashtext('iqror_acc:' || coalesce(v_party, '')));
  end if;
  if v_op = 'in_damage_repay' then   -- xodim zimmasidagi kamomad: ikki qoplash parallel o'tib, qoldiqdan oshib ketmasin (acc-4)
    perform pg_advisory_xact_lock(hashtext('iqror_dmg:' || coalesce(v_party, '')));
  end if;
  if v_op in ('out_advance', 'out_salary', 'in_staff_return') then
    v_code := app.kassa_payee_code(v_party);
    if v_code is not null then
      if v_op = 'in_staff_return' and coalesce(v_snap ->> 'month', '') <> ''
         and exists (select 1 from public.cash_doc_lines l where l."docId" = p_doc_id and l."articleId" = 'OP-09') then
        perform pg_advisory_xact_lock(hashtext('iqror_salpay:' || v_code || ':' || (v_snap ->> 'month')));   -- S — P dan OLDIN
      end if;
      perform pg_advisory_xact_lock(hashtext('iqror:payroll:' || v_code));   -- P
    end if;
  end if;
  if v_op = 'out_refund' and v_snap is not null then
    -- qaytarish (faktura, to'lov, o'quvchi avansi — crit-2): o'quvchi bo'yicha navbat (L1) — avans / faktura tekshiruvi va o'zgarishi orasida
    perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_snap ->> 'studentId', '')));
    if v_snap ->> 'target' = 'payment' then perform 1 from public.payments pm where pm.id = v_snap ->> 'targetId' for update; end if;
  end if;
end $$;
revoke all on function app.kassa_link_prelock(text) from public, anon, authenticated;

-- ---------- Qaytarish orderi pul berilayotganda: faktura qismining hisobvarag'i to'lov kuniga ko'ra (acc-7) ----------
--   So'rov paytida qatorlar o'sha kun bo'yicha tuzilgan (4010 — boshlangan davr, 6310 — kelgusi oy). So'rov oy oxirida tasdiqlanib, pul
--   keyingi oyda berilsa, fakturaning oyi endi boshlangan davr: qator to'lov kuniga ko'ra qayta aniqlanadi. Summa, oluvchi va tasdiq
--   o'zgarmaydi (tasdiq — summa va maqsad uchun, texnik hisobvaraq uchun emas); avans (clawback / 'credit') qismi doim Dt 6310.
--   kassa_doc_pay chaqiradi — prelock (L1) va kassa qulfi (L4) ostida, kassa bayrog'i bilan, o'tkazishdan OLDIN (kun — kassa_doc_post
--   aynan shu qoida bilan oladigan kun). Qator faqat shu hujjat uchun bayroq ostida o'zgaradi (kassa.sql: app.kassa_line_guard);
--   o'zgargan bo'lsa — kun jurnaliga «resplit» hodisasi (qaysi qator, qaysi hisobvaraqdan qaysiga).
create or replace function app.kassa_refund_resplit(p_doc_id text, p_uid text) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_doc public.cash_docs%rowtype; v_day_id text; v_day date; v_m text; l record; v_acct text; v_ch jsonb := '[]'::jsonb; v_txt text := '';
begin
  select * into v_doc from public.cash_docs c where c.id = p_doc_id;
  if v_doc.op is distinct from 'out_refund' or v_doc.status <> 'approved' or v_doc.no is not null
     or coalesce(v_doc."sourceSnapshot" ->> 'target', '') <> 'invoice' then
    return;
  end if;
  select d.o_day_id, d.o_day into v_day_id, v_day from app.kassa_resolve_day(v_doc.desk, null, p_uid, false) d;
  v_m := to_char(v_day, 'YYYY-MM');
  for l in select * from public.cash_doc_lines x
            where x."docId" = p_doc_id and x.analytics ? 'invoiceId' and x.debit in ('4010', '6310') order by x."lineNo" loop
    v_acct := case when coalesce(l.analytics ->> 'month', '') ~ '^\d{4}-\d{2}$' and (l.analytics ->> 'month') > v_m then '6310' else '4010' end;
    if v_acct <> l.debit then
      perform set_config('iqror.kassa_resplit', p_doc_id, true);
      update public.cash_doc_lines set debit = v_acct where id = l.id;
      perform set_config('iqror.kassa_resplit', '', true);
      v_ch := v_ch || jsonb_build_object('lineNo', l."lineNo", 'from', l.debit, 'to', v_acct, 'invoiceId', l.analytics ->> 'invoiceId',
                                         'month', l.analytics ->> 'month', 'amount', l.amount);
      v_txt := v_txt || case when v_txt = '' then '' else '; ' end || 'faktura ' || coalesce(l.analytics ->> 'month', '?') || ': Dt ' || l.debit || ' → Dt ' || v_acct;
    end if;
  end loop;
  if jsonb_array_length(v_ch) > 0 then
    insert into public.cash_day_events (id, "dayId", desk, day, kind, "byUid", reason, data)
      values ('ce_' || replace(gen_random_uuid()::text, '-', ''), v_day_id, v_doc.desk, v_day, 'resplit', p_uid,
              left('Qaytarish orderi: hisobvaraq pul berilgan kun (' || to_char(v_day, 'DD.MM.YYYY') || ') bo''yicha qayta aniqlandi — ' || v_txt, 500),
              jsonb_build_object('docId', p_doc_id, 'asOf', v_day, 'lines', v_ch));
  end if;
end $$;
revoke all on function app.kassa_refund_resplit(text, text) from public, anon, authenticated;

-- ---------- Pul berilgandan / qabul qilingandan keyin (hujjat o'tkazilgan, shu tranzaksiya): bog'langan amal ----------
--   Xodim bilan hisob-kitob kirimlarida tekshiruv shu yerda (qoldiq qulfi prelock'da, kassa qulfi o'tkazishda olingan): rad etilsa
--   butun tranzaksiya bekor — hujjat ham, raqam ham qolmaydi.
create or replace function app.kassa_link_paid(p_doc_id text, p_uid text) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_doc public.cash_docs%rowtype; s jsonb; r jsonb; v_before text[]; v_code text; l record; v_cat text; v_lbl text;
  v_open numeric; v_month text; v_art text; v_last public.salary_payments%rowtype; v_sid text; v_cr numeric; v_name text;
begin
  select * into v_doc from public.cash_docs c where c.id = p_doc_id;
  -- Hisobdordan qaytim (acc-3) / kamomadni qoplash (acc-4): o'tkazilgandan keyin xodim qoldig'i manfiy bo'lmasin — qaytim hisobdordagi
  --   hisobot qilinmagan qoldiqdan, qoplash xodim zimmasidagi kamomad qoldig'idan oshmaydi (sinov kassasida — o'sha kassaning o'z qoldig'i).
  if v_doc.op = 'in_acc_return' then
    v_open := app.kassa_acc_open(v_doc."partyId", v_doc.desk);   -- shu qaytim bilan
    if v_open < 0 then
      raise exception 'Qaytim summasi (% so''m) hisobdordagi hisobot qilinmagan avans qoldig''idan katta (qoldiq % so''m)', v_doc.amount, v_open + v_doc.amount
        using errcode = 'P0001', hint = 'kassa:acc_over';
    end if;
    return;
  elsif v_doc.op = 'in_damage_repay' then
    v_open := app.kassa_damage_open(v_doc."partyId", v_doc.desk);   -- shu qoplash bilan
    if v_open < 0 then
      raise exception 'Qoplash summasi (% so''m) xodim zimmasidagi kamomad qoldig''idan katta (qoldiq % so''m)', v_doc.amount, v_open + v_doc.amount
        using errcode = 'P0001', hint = 'kassa:damage_over';
    end if;
    return;
  end if;
  -- Sinov kassasi (CT-20): hujjatlari va raqamlari alohida — «Buxgalteriya», avans va qaytarish jadvallariga HECH NARSA yozilmaydi.
  if coalesce((select k."isTest" from public.cash_desks k where k.id = v_doc.desk), false) then return; end if;
  if v_doc.op = 'out_refund' then
    s := v_doc."sourceSnapshot";
    if s is null or v_doc."sourceTable" is distinct from 'refunds' then
      raise exception 'Qaytarish hujjati ma''lumoti to''liq emas' using errcode = 'P0001', hint = 'kassa:refund';
    end if;
    if s ->> 'target' = 'credit' then
      -- o'quvchi avansini naqd qaytarish (crit-2): avans pul berilayotgan paytdagi holatda qayta tekshiriladi (L1 — prelock'da) va shu
      --   tranzaksiyada kamayadi: avans jurnali (credit_ledger) va qaytarish jurnali (refunds, target 'credit' — moslik P8 shu bilan)
      v_sid := s ->> 'studentId';
      select c.credit into v_cr from public.student_credit c where c.id = v_sid for update;
      v_cr := coalesce(v_cr, 0);
      if v_cr < v_doc.amount then
        raise exception 'Qaytarib bo''lmadi: o''quvchi avansi tasdiqdan keyin o''zgargan (hozir % so''m, so''rovda % so''m) — so''rovni bekor qilib, qaytadan tasdiqlang',
          v_cr, v_doc.amount using errcode = 'P0001', hint = 'kassa:credit_changed';
      end if;
      update public.student_credit set credit = v_cr - v_doc.amount, "updatedAt" = now() where id = v_sid;
      select st.name into v_name from public.students st where st."studentId" = v_sid or st.id = v_sid order by (st."studentId" = v_sid) desc limit 1;
      insert into public.credit_ledger (id, "studentId", "studentName", delta, "balanceAfter", reason, provider, note, "at")
        values (gen_random_uuid()::text, v_sid, coalesce(v_name, ''), -v_doc.amount, v_cr - v_doc.amount, 'manual', 'cash',
                left('Avans naqd qaytarildi (KO-2 № ' || v_doc.no || '): ' || coalesce(s ->> 'reason', ''), 300), now());
      insert into public.refunds (id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, method, "cashDocId")
        values (gen_random_uuid()::text, 'credit', v_sid, v_sid, coalesce(v_name, ''), v_doc.amount,
                coalesce(s ->> 'reason', '') || ' · avans naqd qaytarildi', '', '', 'cash', v_doc.id);
      return;
    end if;
    select coalesce(array_agg(x.id), '{}') into v_before from public.refunds x
     where x."targetId" in (s ->> 'targetId', coalesce(s ->> 'studentId', ''));
    r := public.refund_invoice(s ->> 'target', s ->> 'targetId', (s ->> 'amount')::numeric, s ->> 'reason',
                               coalesce((s ->> 'clawback')::boolean, false), '', v_doc."sourceId");   -- p_by e'tiborsiz: «kim»ni fin_server_ts yozadi
    if r is null or coalesce((r ->> 'dup')::boolean, false) or not coalesce((r ->> 'ok')::boolean, false) then
      raise exception 'Qaytarib bo''lmadi (%): tasdiqdan keyin hisob-faktura yoki to''lov o''zgargan — so''rovni bekor qilib, qaytadan tasdiqlang',
        coalesce(r ->> 'reason', r ->> 'error', case when coalesce((r ->> 'dup')::boolean, false) then 'takror' else '?' end)
        using errcode = 'P0001', hint = 'kassa:refund';
    end if;
    if coalesce((s ->> 'clawback')::boolean, false) and abs(coalesce((r ->> 'clawback')::numeric, 0) - coalesce((s ->> 'clawbackAmount')::numeric, 0)) >= 0.01 then
      raise exception 'Qaytarib bo''lmadi: tasdiqdan keyin o''quvchi avansi o''zgargan — so''rovni bekor qilib, qaytadan tasdiqlang'
        using errcode = 'P0001', hint = 'kassa:refund';
    end if;
    update public.refunds set method = 'cash', "cashDocId" = v_doc.id
     where "targetId" in (s ->> 'targetId', coalesce(s ->> 'studentId', '')) and id <> all (v_before) and "cashDocId" is null;

  elsif v_doc.op = 'out_advance' then
    v_code := app.kassa_payee_code(v_doc."partyId");
    if v_code is null then raise exception 'Xodim topilmadi' using errcode = '22023', hint = 'kassa:party'; end if;
    insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date, note, method, "cashDocId")
      values ('adv_' || v_doc.id, v_code, v_doc."partyId", v_doc."partyName", v_doc.amount, to_char(v_doc."businessDay", 'YYYY-MM'),
              to_char(v_doc."businessDay", 'YYYY-MM-DD'), left(v_doc.basis, 300), 'cash', v_doc.id);

  elsif v_doc.op = 'out_expense' then
    -- har naqd qator (asosiy vosita, sotish uchun tovar, yetkazib beruvchi ham) — toifa va izoh boshi app.kassa_exp_category dan (acc-9)
    for l in select * from public.cash_doc_lines x where x."docId" = v_doc.id and x.cash order by x."lineNo" loop
      select k.o_category, k.o_label into v_cat, v_lbl from app.kassa_exp_category(l."articleId") k;
      insert into public.expenses (id, date, month, category, amount, note, method, "cashDocId", "articleId", "counterpartyId")
        values ('kx_' || v_doc.id || '_' || l."lineNo", to_char(v_doc."businessDay", 'YYYY-MM-DD'), to_char(v_doc."businessDay", 'YYYY-MM'),
                v_cat, l.amount,
                left(btrim(coalesce(v_lbl || ': ', '') || coalesce(nullif(v_doc."partyName", ''), '') || case when v_doc.basis <> '' then ' — ' || v_doc.basis else '' end
                           || ' (KO-2 № ' || v_doc.no || ')'), 300),
                'cash', v_doc.id, l."articleId", case when v_doc."partyType" = 'counterparty' then v_doc."partyId" end);
    end loop;

  elsif v_doc.op = 'in_staff_return' then   -- xodim qaytargan pul (acc-1): avans / maosh yozuvi (MANFIY) — vedomost va darvoza sof summani ko'radi
    v_month := v_doc."sourceSnapshot" ->> 'month';
    select x."articleId" into v_art from public.cash_doc_lines x where x."docId" = v_doc.id order by x."lineNo" limit 1;
    v_code := app.kassa_payee_code(v_doc."partyId");
    if v_code is null then raise exception 'Xodim topilmadi' using errcode = '22023', hint = 'kassa:party'; end if;
    if coalesce(v_month, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then
      raise exception 'Qaysi oy avansi / maoshi qaytarilayotgani tanlanmagan' using errcode = '22023', hint = 'kassa:month';
    end if;
    if v_art = 'OP-08' then
      -- avans qaytdi: oy vedomosti tasdiqlangan bo'lsa avans maoshdan allaqachon ushlangan — endi bu pul «berilgan maosh qaytdi»
      perform 1 from public.payroll_runs pr where pr.id = v_month for share;   -- tasdiqlash / qayta ochish bilan bir navbat
      if app.payroll_locked_month(v_month, v_month) is not null then
        raise exception '% oy vedomosti tasdiqlangan — avans maoshdan allaqachon ushlab qolingan: pulni «Ish haqi to''lovi» statiyasi bilan qabul qiling (berilgan maosh qaytdi) yoki Direktor oyni qayta ochsin', v_month
          using errcode = 'P0001', hint = 'kassa:advance_locked';
      end if;
      -- shu oy naqd avans qoldig'i (berilgan − qaytarilgan; usulsiz eski yozuv — naqd); qatorlar qulf ostida (to'g'ridan-to'g'ri o'chirish kutadi)
      perform 1 from public.staff_advances a
       where a."teacherId" = v_code and coalesce(nullif(a.month, ''), left(coalesce(a.date, ''), 7)) = v_month and coalesce(a.method, '') in ('', 'cash') for share;
      select coalesce(sum(coalesce(a.amount, 0)), 0) into v_open from public.staff_advances a
       where a."teacherId" = v_code and coalesce(nullif(a.month, ''), left(coalesce(a.date, ''), 7)) = v_month and coalesce(a.method, '') in ('', 'cash');
      if v_doc.amount > v_open then
        raise exception 'Qaytim summasi (% so''m) xodimning % oy naqd avansi qoldig''idan katta (qoldiq % so''m)', v_doc.amount, v_month, v_open
          using errcode = 'P0001', hint = 'kassa:staff_over';
      end if;
      insert into public.staff_advances (id, "teacherId", "payeeRef", "teacherName", amount, month, date, note, method, "cashDocId")
        values ('advr_' || v_doc.id, v_code, v_doc."partyId", v_doc."partyName", -v_doc.amount, v_month, to_char(v_doc."businessDay", 'YYYY-MM-DD'),
                left('Avans kassaga qaytarildi (KO-1 № ' || v_doc.no || ')' || case when v_doc.basis <> '' then ' — ' || v_doc.basis else '' end, 300),
                'cash', v_doc.id);
    elsif v_art = 'OP-09' then
      -- maosh qaytdi: shu oy naqd berilgan maoshdan (qaytganlari ayirilgan; usulsiz eski yozuv — naqd) oshmaydi
      perform 1 from public.salary_payments x
       where x."teacherId" = v_code and x.month = v_month and coalesce(x.method, '') in ('', 'cash') for share;
      select coalesce(sum(coalesce(x.paid, 0)), 0) into v_open from public.salary_payments x
       where x."teacherId" = v_code and x.month = v_month and coalesce(x.method, '') in ('', 'cash');
      if v_doc.amount > v_open then
        raise exception 'Qaytim summasi (% so''m) xodimga % oy uchun naqd berilgan maoshdan katta (berilgan % so''m)', v_doc.amount, v_month, v_open
          using errcode = 'P0001', hint = 'kassa:staff_over';
      end if;
      -- oyning hisob qiymatlari (maosh, avans, ushlanma, o'rinbosarlik) — qoldiq hisobida (app.salary_carry, admin.html carryBalance) oy
      --   qarzini belgilovchi yozuvdan (eng so'nggi sana, tengida — kattasi): oy qarzi o'zgarmaydi, berilgani kamayadi (qaytgan pul shu
      --   oy yana berilishi yoki keyingi oyga qoldiq bo'lib o'tishi mumkin)
      select * into v_last from public.salary_payments x where x."teacherId" = v_code and x.month = v_month
       order by coalesce(x.date, '') desc,
                case when x.gross is not null or x.advance is not null or x.deduction is not null
                     then coalesce(x.gross, 0) - coalesce(x.advance, 0) - coalesce(x.deduction, 0) + coalesce(x."subBonus", 0)
                     else coalesce(x.net, 0) + coalesce(x."subBonus", 0) end desc
       limit 1;
      insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, gross, advance, deduction, "subBonus", net,
                                          "carryIn", paid, "carryOut", date, note, method, "cashDocId")
        values ('spr_' || v_doc.id, v_code, v_doc."partyId", coalesce(nullif(v_doc."partyName", ''), v_last."teacherName"), v_month,
                v_last.gross, v_last.advance, v_last.deduction, v_last."subBonus", v_last.net, v_last."carryIn", -v_doc.amount,
                v_last."carryOut" + v_doc.amount, to_char(v_doc."businessDay", 'YYYY-MM-DD'),
                left('Maosh kassaga qaytarildi (KO-1 № ' || v_doc.no || ')' || case when v_doc.basis <> '' then ' — ' || v_doc.basis else '' end, 300),
                'cash', v_doc.id);
    else
      raise exception 'Xodim qaytargan pul: statiya noto''g''ri (avans yoki maosh)' using errcode = '22023', hint = 'kassa:article';
    end if;
  end if;
end $$;
revoke all on function app.kassa_link_paid(text, text) from public, anon, authenticated;

-- ---------- Shu kunda bekor qilish: bog'langan yozuvni olib tashlash ----------
--   Qaytarish orderi bekor qilinmaydi (pul qaytib kelgan bo'lsa — yangi kirim sifatida qabul qilinadi).
--   Xodim qaytargan pul (acc-1): manfiy avans / maosh yozuvi olib tashlanadi; avans qaytimi — oy vedomosti shu orada tasdiqlangan
--   bo'lsa (qaytgan avans maoshda hisobga olingan) rad; maosh qaytimi — qaytgan pul keyin qayta berilgan bo'lsa (bekor qilinsa
--   tasdiqlangan summadan ortiq berilgan bo'lib qoladi) rad: avval keyingi maosh orderi bekor qilinadi.
--   Avans / maosh orderining o'zi — undan kassaga qaytim yozilgan va bekor qilinsa shu oy naqd avansi / berilgan maosh manfiy bo'lib
--   qolsa rad: avval qaytim orderi bekor qilinadi (hisobdorga avansdagi kassa:acc_used kabi; xodim navbati — prelock'da).
create or replace function app.kassa_link_void(p_doc_id text, p_uid text, p_reason text) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_doc public.cash_docs%rowtype; r_adv public.staff_advances%rowtype; r_sal public.salary_payments%rowtype; r_line public.payroll_lines%rowtype;
        v_m text; v_from text; v_paid numeric; v_cap numeric;
begin
  select * into v_doc from public.cash_docs c where c.id = p_doc_id;
  if coalesce((select k."isTest" from public.cash_desks k where k.id = v_doc.desk), false) then return; end if;   -- sinov kassasi: bog'langan yozuv yo'q
  if v_doc.op = 'out_refund' then
    raise exception 'Qaytarish orderi bekor qilinmaydi — xato bo''lsa, pulni yangi to''lov sifatida qayta qabul qiling' using errcode = '42501', hint = 'kassa:linked_doc';
  elsif v_doc.op = 'out_advance' then
    for r_adv in select * from public.staff_advances a where a."cashDocId" = v_doc.id loop
      v_m := coalesce(nullif(r_adv.month, ''), left(coalesce(r_adv.date, ''), 7));
      select coalesce(sum(coalesce(a.amount, 0)), 0) into v_paid from public.staff_advances a
       where a."teacherId" = r_adv."teacherId" and coalesce(nullif(a.month, ''), left(coalesce(a.date, ''), 7)) = v_m
         and coalesce(a.method, '') in ('', 'cash') and a.id <> r_adv.id;
      if v_paid < 0 then
        raise exception 'Bu avansdan kassaga qaytim yozilgan («Xodim qaytargan pul»): bekor qilinsa xodimning % oy naqd avansi manfiy bo''ladi (% so''m) — avval qaytim orderini bekor qiling',
          v_m, v_paid using errcode = 'P0001', hint = 'kassa:staff_returned';
      end if;
    end loop;
    delete from public.staff_advances a where a."cashDocId" = v_doc.id;   -- oy vedomosti tasdiqlangan bo'lsa — trigger rad etadi
  elsif v_doc.op = 'out_salary' then
    for r_sal in select * from public.salary_payments s where s."cashDocId" = v_doc.id loop
      select coalesce(sum(coalesce(s.paid, 0)), 0) into v_paid from public.salary_payments s
       where s."teacherId" = r_sal."teacherId" and s.month = r_sal.month and coalesce(s.method, '') in ('', 'cash') and s.id <> r_sal.id;
      if v_paid < 0 then
        raise exception 'Bu maoshdan kassaga qaytim yozilgan («Xodim qaytargan pul»): bekor qilinsa xodimga % oy uchun naqd berilgan maosh manfiy bo''ladi (% so''m) — avval qaytim orderini bekor qiling',
          r_sal.month, v_paid using errcode = 'P0001', hint = 'kassa:staff_returned';
      end if;
    end loop;
    delete from public.salary_payments s where s."cashDocId" = v_doc.id;
  elsif v_doc.op = 'out_expense' then
    delete from public.expenses e where e."cashDocId" = v_doc.id;
  elsif v_doc.op = 'in_staff_return' then
    for r_adv in select * from public.staff_advances a where a."cashDocId" = v_doc.id loop
      v_m := coalesce(nullif(r_adv.month, ''), left(coalesce(r_adv.date, ''), 7));
      perform 1 from public.payroll_runs pr where pr.id = v_m for share;   -- tasdiqlash bilan bir navbat
      if app.payroll_locked_month(v_m, v_m) is not null then
        raise exception '% oy vedomosti tasdiqlangan — avans qaytimi bekor qilinmaydi (qaytgan avans maosh hisobida): Direktor oyni qayta ochsin', v_m
          using errcode = 'P0001', hint = 'kassa:advance_locked';
      end if;
    end loop;
    delete from public.staff_advances a where a."cashDocId" = v_doc.id;
    select nullif(btrim(coalesce(c."payrollApprovalFrom", '')), '') into v_from from public.config c where c.id = 'finance';
    for r_sal in select * from public.salary_payments s where s."cashDocId" = v_doc.id loop
      -- darvoza bilan bir xil chegara (payroll-approval.sql: app.salary_payment_gate) — tasdiqlangan, lekin hozirgi qarzdan ko'p emas
      if v_from is not null and coalesce(r_sal.month, '') >= v_from then
        r_line := null;
        select * into r_line from public.payroll_lines pl where pl."runId" = r_sal.month and pl."personId" = r_sal."teacherId";
        select coalesce(sum(coalesce(s.paid, 0)), 0) into v_paid from public.salary_payments s
         where s."teacherId" = r_sal."teacherId" and s.month = r_sal.month and s.id <> r_sal.id;
        v_cap := case when r_line.id is null then 0
                      else least(r_line.payable, greatest(0, r_line.gross - app.payroll_adv(r_sal."teacherId", r_sal.month) - r_line.deduction
                                                             + r_line."subBonus" + app.salary_carry(r_sal."teacherId", r_sal.month))) end;
        if v_paid > v_cap + 0.5 then
          raise exception 'Qaytgan maosh keyin qayta berilgan: bekor qilinsa xodimga % oy uchun tasdiqlangan summadan % so''m ortiq berilgan bo''lib qoladi — avval keyingi maosh orderini bekor qiling',
            r_sal.month, round(v_paid - v_cap) using errcode = 'P0001', hint = 'kassa:salary_repaid';
        end if;
      end if;
    end loop;
    delete from public.salary_payments s where s."cashDocId" = v_doc.id;
  end if;
end $$;
revoke all on function app.kassa_link_void(text, text, text) from public, anon, authenticated;

-- ---------- O'zaro hisob (nc_offset): xodimning ish haqidan farzandining o'quv to'lovi — NAQDSIZ ----------
--   Yozma ariza + Direktor (§4.10). BITTA tranzaksiyada:
--     • maosh to'lovi (salary_payments, usul 'offset') — tasdiqlangan vedomost chegarasi mavjud darvoza trigeri bilan;
--     • o'quv to'lovi (payments, provider 'offset') va uning balansga qo'llanishi (apply_payment: eng eski fakturadan, ortiqchasi avansga);
--     • naqdsiz dalolatnoma (ACT): Dt 6710 Kt 4010 / 6310 — taqsimot naqd o'quv to'lovidagi qoida bilan (app.kassa_tuition_alloc);
--       eski avans fakturaga qo'llangan bo'lsa — KO-1 dagi kabi naqdsiz Dt 6310 Kt 4010 ma'lumot qatori ham (summaga kirmaydi, acc-2).
--   Kassadan pul chiqmaydi ham, kirmaydi ham — kassa kitobida (KO-4) yo'q; dalolatnoma o'z raqam seriyasida («Д-»).
--   p: id ('sp_…' — «Maosh berish» oynasining barqaror kaliti), teacherId, payeeRef ('teachers:<id>' | 'staff:<id>'), teacherName,
--      month ('YYYY-MM'), paid (> 0 — hisobga olinadigan summa), gross, advance, deduction, subBonus, net, carryIn, carryOut,
--      studentId (o'quvchi kodi yoki qator id), requestDate (ariza sanasi 'YYYY-MM-DD' — majburiy), note
create or replace function public.kassa_offset(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_id text; v_tid text; v_ref text; v_month text; v_paid numeric; v_from text; v_gate_off boolean;
  v_sid_in text; v_sid text; v_sname text; v_ename text; v_req text; v_note text; v_key text; v_pay_id text; v_today date := app.fin_today();
  v_ex public.salary_payments%rowtype; v_before jsonb; v_res jsonb; v_a jsonb; v_doc_id text; v_dup boolean; v_doc public.cash_docs%rowtype;
begin
  if not app.is_admin() then
    raise exception 'Ruxsat yo''q: o''zaro hisobni faqat Direktor rasmiylashtiradi' using errcode = '42501';
  end if;
  if not app.kassa_live() then raise exception 'Kassa ishga tushirilmagan' using errcode = 'P0001', hint = 'kassa:not_live'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_id := btrim(coalesce(p ->> 'id', ''));
  v_tid := btrim(coalesce(p ->> 'teacherId', ''));
  v_ref := btrim(coalesce(p ->> 'payeeRef', ''));
  v_month := coalesce(p ->> 'month', '');
  if v_id !~ '^sp_.{3,200}$' or v_tid = '' or v_ref !~ '^(teachers|staff):.+$' or v_month !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Maosh to''lovi ma''lumoti to''liq emas' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  v_paid := app.kassa_amount(p -> 'paid', 'O''zaro hisob');
  v_sid_in := btrim(coalesce(p ->> 'studentId', ''));
  select coalesce(nullif(s."studentId", ''), s.id), coalesce(s.name, '') into v_sid, v_sname
    from public.students s where s.id = v_sid_in or s."studentId" = v_sid_in order by (s.id = v_sid_in) desc limit 1;
  if v_sid_in = '' or v_sid is null then raise exception 'O''quvchi tanlanmagan yoki topilmadi' using errcode = '22023', hint = 'kassa:party'; end if;
  v_ename := app.kassa_party_label('employee', v_ref);
  if v_ename is null then raise exception 'Xodim topilmadi' using errcode = '22023', hint = 'kassa:party'; end if;
  -- Ariza sanasi — hujjat asosi: majburiy, kelajakda emas, 92 kundan eski emas.
  v_req := coalesce(p ->> 'requestDate', '');
  begin
    if v_req !~ '^\d{4}-\d{2}-\d{2}$' or v_req::date > v_today or v_req::date < v_today - 92 then v_req := null; end if;
  exception when others then v_req := null; end;
  if v_req is null then raise exception 'Xodimning yozma arizasi sanasini kiriting' using errcode = '22023', hint = 'kassa:basis'; end if;
  v_note := left(btrim(coalesce(p ->> 'note', '')), 300);
  v_key := 'ofs_' || md5(v_id); v_pay_id := v_key;
  perform pg_advisory_xact_lock(hashtext('iqror_doc:' || v_key));   -- L0: shu oynadan parallel / qayta yuborish navbatga turadi
  select * into v_ex from public.salary_payments s where s.id = v_id;
  if found then
    if coalesce(v_ex.paid, 0) <> v_paid or coalesce(v_ex."teacherId", '') <> v_tid or coalesce(v_ex.month, '') <> v_month
       or coalesce(v_ex.method, '') <> 'offset' then
      raise exception 'Shu kalit bilan boshqa maosh to''lovi yozilgan' using errcode = '22023', hint = 'kassa:ref_mismatch';
    end if;
    return jsonb_build_object('ok', true, 'dup', true, 'id', v_id, 'method', 'offset', 'payId', v_pay_id, 'row', to_jsonb(v_ex),
      'kassa', (select jsonb_build_object('docId', c.id, 'form', c.form, 'no', c.no, 'day', c."businessDay", 'status', c.status)
                  from public.cash_docs c where c.id = v_ex."cashDocId"));
  end if;
  select nullif(btrim(coalesce(c."payrollApprovalFrom", '')), '') into v_from from public.config c where c.id = 'finance';
  v_gate_off := v_from is null or v_month < v_from;

  v_before := app.kassa_tuition_before(v_sid, v_today, null, null);   -- L1: o'quvchi bo'yicha navbat + to'lovdan oldingi holat (bugungi kun)
  perform app.kassa_flag(true);
  -- 1) maosh to'lovi (L3: vedomost chegarasi — darvoza trigeri)
  insert into public.salary_payments (id, "teacherId", "payeeRef", "teacherName", month, gross, advance, deduction, "subBonus", net,
                                      "carryIn", paid, "carryOut", date, note, method)
    values (v_id, v_tid, v_ref, left(btrim(coalesce(nullif(btrim(coalesce(p ->> 'teacherName', '')), ''), v_ename)), 200), v_month,
            app.kassa_num(p, 'gross'), app.kassa_num(p, 'advance'), app.kassa_num(p, 'deduction'), app.kassa_num(p, 'subBonus'),
            app.kassa_num(p, 'net'), app.kassa_num(p, 'carryIn'), v_paid, app.kassa_num(p, 'carryOut'), to_char(v_today, 'YYYY-MM-DD'),
            left(btrim('O‘zaro hisob: o‘quv to‘lovi — ' || v_sname || ' (' || v_sid || ')' || case when v_note <> '' then '; ' || v_note else '' end), 300),
            'offset');
  -- 2) o'quv to'lovi va uning balansga qo'llanishi
  insert into public.payments (id, "studentId", provider, amount, status, "payerName", matched, raw)
    values (v_pay_id, v_sid, 'offset', v_paid, 'pending', left(v_ename, 200), true,
            jsonb_build_object('manual', true, 'method', 'offset', 'date', to_char(v_today, 'YYYY-MM-DD'), 'byUid', v_uid,
                               'note', left('O‘zaro hisob: ish haqi ' || v_month || case when v_note <> '' then '; ' || v_note else '' end, 500),
                               'offset', jsonb_build_object('salaryPaymentId', v_id, 'payeeRef', v_ref, 'month', v_month, 'requestDate', v_req)));
  perform set_config('iqror.money_rpc', '1', true);
  v_res := public.apply_payment(v_sid, v_paid, 'offset', v_pay_id);
  perform set_config('iqror.money_rpc', '', true);
  if v_res is null or not coalesce((v_res ->> 'ok')::boolean, false) then
    raise exception 'O''zaro hisob qo''llanmadi (%)', coalesce(v_res::text, 'null') using errcode = 'P0001', hint = 'kassa:offset';
  end if;
  update public.payments set status = 'applied' where id = v_pay_id;
  -- 3) naqdsiz dalolatnoma: Dt 6710 Kt 4010 / 6310 (to'lov qayerga taqsimlangan bo'lsa) — naqd KO-1 bilan aynan bir xil qoida (acc-2):
  --    o'quvchining ESKI avansi shu to'lov bilan fakturaga qo'llangan bo'lsa — naqdsiz qator Dt 6310 Kt 4010 (ma'lumot qatori,
  --    dalolatnoma summasiga kirmaydi); oy chegarasi — dalolatnoma sanasi (bugun) bo'yicha
  v_a := app.kassa_tuition_alloc(v_before, v_paid, '6710', true, false, v_today);
  select b.o_id, b.o_dup into v_doc_id, v_dup from app.kassa_doc_build(jsonb_build_object(
      'desk', 'main', 'op', 'nc_offset', 'amount', v_paid, 'partyType', 'employee', 'partyId', v_ref,
      'basis', 'O‘zaro hisob: ish haqi ' || v_month || ' hisobidan o‘quv to‘lovi — ' || v_sname || ' (' || v_sid || '); ariza '
               || to_char(v_req::date, 'DD.MM.YYYY'),
      'attachment', 'Yozma ariza', 'note', v_note, 'clientRef', v_key, 'needsDirector', true,
      'sourceTable', 'salary_payments', 'sourceId', v_id,
      'sourceSnapshot', jsonb_build_object('allocation', v_a ->> 'mode', 'creditBefore', v_a -> 'creditBefore', 'creditAfter', v_a -> 'creditAfter',
                                           'before', v_before -> 'invoices', 'paymentId', v_pay_id, 'studentId', v_sid, 'studentName', v_sname,
                                           'month', v_month, 'teacherId', v_tid, 'gateOff', v_gate_off, 'requestDate', v_req,
                                           'months', v_a -> 'months', 'over', v_a -> 'over'),
      'lines', v_a -> 'lines'), 'ACT', v_uid, true) b;
  update public.cash_docs set "dirApprovedBy" = v_uid, "dirApprovedAt" = app.fin_now() where id = v_doc_id and status = 'draft';   -- Direktor o'zi rasmiylashtiradi
  v_doc := app.kassa_act_post(v_doc_id, v_uid, v_today);   -- L4, L5
  insert into public.payment_allocations (id, "paymentId", "docId", "studentId", "invoiceId", month, "fromCash", "fromCredit", account)
    select 'pa_' || replace(gen_random_uuid()::text, '-', ''), v_pay_id, v_doc.id, v_sid, a ->> 'invoiceId', a ->> 'month',
           (a ->> 'fromCash')::numeric, (a ->> 'fromCredit')::numeric, a ->> 'account'
      from jsonb_array_elements(v_a -> 'alloc') a;
  update public.salary_payments set "cashDocId" = v_doc.id where id = v_id;
  update public.payments
     set "cashDocId" = v_doc.id, raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('actNo', v_doc.no)
   where id = v_pay_id;
  perform app.kassa_flag(false);
  return jsonb_build_object('ok', true, 'dup', false, 'id', v_id, 'method', 'offset', 'payId', v_pay_id,
    'row', (select to_jsonb(s) from public.salary_payments s where s.id = v_id),
    'kassa', jsonb_build_object('docId', v_doc.id, 'form', 'ACT', 'series', v_doc.series, 'no', v_doc.no, 'day', v_doc."businessDay", 'status', v_doc.status),
    'student', jsonb_build_object('id', v_sid, 'name', v_sname, 'credit', coalesce((v_a ->> 'creditAfter')::numeric, 0)));
end $$;
revoke all on function public.kassa_offset(jsonb) from public, anon;
grant execute on function public.kassa_offset(jsonb) to authenticated;

-- O'zaro hisobni bekor qilish: FAQAT Direktor, FAQAT rasmiylashtirilgan kunning o'zida, sabab bilan. O'quv to'lovi teskari qilinadi
--   (fakturalar va avans avvalgi holatga — faqat undan keyin o'quvchi bo'yicha boshqa pul harakati bo'lmagan bo'lsa), maosh to'lovi
--   olib tashlanadi, dalolatnoma raqami saqlanib «bekor qilingan» bo'ladi. Keyingi kunlarda — «Qaytarish» va buxgalter tuzatishi.
create or replace function public.kassa_offset_void(p_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_doc public.cash_docs%rowtype; v_reason text := left(btrim(coalesce(p_reason, '')), 500); v_sid text; v_desk text;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: o''zaro hisobni faqat Direktor bekor qiladi' using errcode = '42501'; end if;
  if length(v_reason) < 5 then raise exception 'Bekor qilish sababini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  select c."sourceSnapshot" ->> 'studentId', c.desk into v_sid, v_desk from public.cash_docs c where c.id = p_id and c.op = 'nc_offset';
  if not found then raise exception 'O''zaro hisob dalolatnomasi topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));   -- L1 — kassa qulfidan (L4) oldin
  perform app.kassa_lock_desk(v_desk);                                            -- L4
  select * into v_doc from public.cash_docs c where c.id = p_id for update;
  if v_doc.status = 'void' then return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', true); end if;
  if v_doc.status <> 'posted' then
    raise exception 'Dalolatnoma bekor qilinmaydi (holati: %)', v_doc.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  if v_doc."businessDay" <> app.fin_today() then
    raise exception 'O''zaro hisob faqat rasmiylashtirilgan kunning o''zida bekor qilinadi (keyin — «Qaytarish» va buxgalter tuzatishi)'
      using errcode = 'P0001', hint = 'kassa:day_closed';
  end if;
  perform app.kassa_flag(true);
  perform app.tuition_reverse_core(p_id, v_uid, v_reason);
  delete from public.salary_payments s where s."cashDocId" = p_id;
  update public.cash_docs set status = 'void', "voidedBy" = v_uid, "voidedAt" = now(), "voidReason" = v_reason where id = p_id;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.kassa_offset_void(text, text) from public, anon;
grant execute on function public.kassa_offset_void(text, text) to authenticated;

-- ---------- Avans hisoboti (АО-1, minimal): hisobdor shaxs sarflagan pul — NAQDSIZ dalolatnoma ----------
--   Qog'ozdagi avans hisoboti (cheklar bilan; shakllar.md, Sh-1) bo'yicha buxgalter, Moliya menejeri yoki Direktor kiritadi.
--   BITTA tranzaksiyada: dalolatnoma (ACT; kassa kitobiga kirmaydi) — har qator Dt statiya hisobvarag'i Kt 4230 (hisobdor
--   bo'yicha) + har qator «Buxgalteriya»dagi xarajat (usul 'accountable', shu hujjatga bog'langan; toifa — app.kassa_exp_category). Hisobot
--   summasi hisobdordagi hisobot qilinmagan qoldiqdan oshmaydi: ortiqcha sarf hozircha alohida «Xarajat» orderi bilan beriladi (to'liq
--   versiya — F2.6).
--   Statiyalar (acc-5; kassa-docs.sql: app.kassa_adv_article — shakldagi ro'yxat ham shundan): EX — kassadan xarajat qilinadiganlari
--   (ish haqi, soliq, eskirish, bank komissiyasi, jarima kabilar — yo'q), OP-18 (asosiy vosita — Dt 0820) va OP-24 (sotish uchun tovar —
--   Dt 2910), reja §4.4 da Kt 4230 bilan provodkasi borlari. OP-17 (yetkazib beruvchi bilan hisob-kitob) va boshqa OP — yo'q.
--   p: clientRef, partyId (xodim: 'teachers:<id>' | 'staff:<id>'), reportDate (qog'ozdagi hisobot sanasi, 92 kun ichida),
--      basis (ixtiyoriy izoh), lines: [{articleId, amount, note — chek yoki hujjat}], 1–40 qator.
--   sec-1: hisobdor — kirituvchining o'zi (bog'langan xodim kartalaridan biri, app.kassa_user_cards) bo'lsa — rad: o'z avansini o'zi hisobdan chiqarmaydi,
--   hisobotni boshqa 2-ro'yxat xodimi yoki Direktor kiritadi (ikkinchi shaxs tasdig'i — 2-bosqich, F2.6).
create or replace function public.kassa_adv_report(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_ref text; v_pid text; v_pname text; v_rep text; v_basis text; v_today date := app.fin_today();
  v_lines jsonb := '[]'::jsonb; v_line jsonb; v_i int := 0; v_amt numeric; v_total numeric := 0; v_art public.fin_articles%rowtype;
  v_note text; v_open numeric; v_doc_id text; v_dup boolean; v_doc public.cash_docs%rowtype; v_ex public.cash_docs%rowtype; l record; v_cat text; v_lbl text;
begin
  if not (app.fin_list2() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: avans hisobotini buxgalter, Moliya menejeri yoki Direktor kiritadi' using errcode = '42501';
  end if;
  if not app.kassa_live() then raise exception 'Kassa ishga tushirilmagan' using errcode = 'P0001', hint = 'kassa:not_live'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Ma''lumot yuborilmagan' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_ref := btrim(coalesce(p ->> 'clientRef', ''));
  if v_ref !~ '^[A-Za-z0-9_.:-]{6,60}$' then raise exception 'Hujjat kaliti (clientRef) noto''g''ri' using errcode = '22023', hint = 'kassa:bad_input'; end if;
  v_ref := 'avh_' || v_ref;
  select k.o_id, k.o_name into v_pid, v_pname from app.kassa_party('employee', p ->> 'partyId', null) k;
  if v_pid = any(app.kassa_user_cards(v_uid)) then   -- sec-1
    raise exception 'O''zingiz hisobdor bo''lgan avans hisobotini o''zingiz kiritmaysiz — uni boshqa 2-ro''yxat xodimi (buxgalter / Moliya menejeri) yoki Direktor kiritadi'
      using errcode = '42501', hint = 'kassa:self_report';
  end if;
  -- Hisobot sanasi — qog'ozdagi hujjat sanasi: majburiy, kelajakda emas, 92 kundan eski emas.
  v_rep := coalesce(p ->> 'reportDate', '');
  begin
    if v_rep !~ '^\d{4}-\d{2}-\d{2}$' or v_rep::date > v_today or v_rep::date < v_today - 92 then v_rep := null; end if;
  exception when others then v_rep := null; end;
  if v_rep is null then raise exception 'Avans hisoboti sanasini kiriting (oxirgi 92 kun ichida)' using errcode = '22023', hint = 'kassa:basis'; end if;
  v_basis := left(btrim(coalesce(p ->> 'basis', '')), 300);
  if p -> 'lines' is null or jsonb_typeof(p -> 'lines') <> 'array' or jsonb_array_length(p -> 'lines') = 0 then
    raise exception 'Xarajat qatorlari yo''q' using errcode = '22023', hint = 'kassa:lines';
  end if;
  if jsonb_array_length(p -> 'lines') > 40 then raise exception 'Bitta hisobotda 40 tadan ortiq qator bo''lmaydi' using errcode = '22023', hint = 'kassa:lines'; end if;
  for v_line in select x from jsonb_array_elements(p -> 'lines') x loop
    v_i := v_i + 1;
    if jsonb_typeof(v_line) <> 'object' then raise exception 'Qator noto''g''ri' using errcode = '22023', hint = 'kassa:lines'; end if;
    v_amt := app.kassa_amount(v_line -> 'amount', v_i || '-qator');
    select * into v_art from public.fin_articles a where a.id = nullif(btrim(coalesce(v_line ->> 'articleId', '')), '') and a.active;
    if not found then raise exception '%-qator: statiya tanlanmagan yoki faol emas', v_i using errcode = '22023', hint = 'kassa:article'; end if;
    if not app.kassa_adv_article(v_art) then
      raise exception '«%» statiyasi bo''yicha hisobdor xarajati yozilmaydi%', v_art."nameUz",
        case when v_art.id = 'OP-17' then ' (yetkazib beruvchiga qarz kassa «Xarajat» orderi yoki bank orqali to''lanadi)' else '' end
        using errcode = '22023', hint = 'kassa:article';
    end if;
    v_note := left(btrim(coalesce(v_line ->> 'note', '')), 300);
    if length(v_note) < 3 then raise exception '%-qator: chek yoki hujjatni yozing (raqami, sanasi)', v_i using errcode = '22023', hint = 'kassa:note'; end if;
    v_total := v_total + v_amt;
    v_lines := v_lines || jsonb_build_object('debit', v_art."accountCode", 'credit', '4230', 'amount', v_amt, 'articleId', v_art.id,
                                             'note', v_note, 'analytics', jsonb_build_object('partyId', v_pid));
  end loop;

  perform pg_advisory_xact_lock(hashtext('iqror_doc:' || v_ref));   -- L0: qayta yuborish navbatga turadi
  select * into v_ex from public.cash_docs c where c."clientRef" = v_ref;
  if found then
    if v_ex.op <> 'nc_adv_report' or v_ex.amount <> v_total or coalesce(v_ex."partyId", '') <> v_pid then
      raise exception 'Shu kalit bilan boshqa hujjat allaqachon yozilgan' using errcode = '22023', hint = 'kassa:ref_mismatch';
    end if;
    return app.kassa_doc_json(v_ex.id) || jsonb_build_object('ok', true, 'dup', true);
  end if;
  perform pg_advisory_xact_lock(hashtext('iqror_acc:' || v_pid));   -- hisobdor qulfi (avans to'lovi bilan bir navbat) — kassa qulfidan oldin
  v_open := app.kassa_acc_open(v_pid);
  if v_open <= 0 then
    raise exception 'Bu xodimda hisobot qilinmagan avans yo''q' using errcode = 'P0001', hint = 'kassa:acc_none';
  end if;
  if v_total > v_open then
    raise exception 'Hisobot summasi (% so''m) hisobdordagi qoldiqdan (% so''m) katta: ortiqcha sarfni alohida «Xarajat» orderi bilan bering', v_total, v_open
      using errcode = 'P0001', hint = 'kassa:acc_over';
  end if;

  perform app.kassa_flag(true);
  select b.o_id, b.o_dup into v_doc_id, v_dup from app.kassa_doc_build(jsonb_build_object(
      'desk', 'main', 'op', 'nc_adv_report', 'amount', v_total, 'partyType', 'employee', 'partyId', v_pid,
      'basis', left('Avans hisoboti ' || to_char(v_rep::date, 'DD.MM.YYYY') || case when v_basis <> '' then '; ' || v_basis else '' end, 500),
      'attachment', 'Cheklar va hujjatlar: ' || v_i || ' ta', 'clientRef', v_ref,
      'sourceSnapshot', jsonb_build_object('reportDate', v_rep, 'openBefore', v_open, 'openAfter', v_open - v_total),
      'lines', v_lines), 'ACT', v_uid, true) b;
  v_doc := app.kassa_act_post(v_doc_id, v_uid, v_today);   -- L4, L5
  for l in select * from public.cash_doc_lines x where x."docId" = v_doc.id order by x."lineNo" loop
    select k.o_category, k.o_label into v_cat, v_lbl from app.kassa_exp_category(l."articleId") k;   -- KO-2 «Xarajat» bilan bir xil qoida (acc-9)
    insert into public.expenses (id, date, month, category, amount, note, method, "cashDocId", "articleId")
      values ('ka_' || v_doc.id || '_' || l."lineNo", to_char(v_doc."businessDay", 'YYYY-MM-DD'), to_char(v_doc."businessDay", 'YYYY-MM'),
              v_cat, l.amount,
              left(btrim(coalesce(v_lbl || ': ', '') || v_pname || case when coalesce(l.note, '') <> '' then ' — ' || l.note else '' end
                         || ' (avans hisoboti № ' || v_doc.no || ')'), 300),
              'accountable', v_doc.id, l."articleId");
  end loop;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(v_doc.id) || jsonb_build_object('ok', true, 'dup', false, 'openBefore', v_open, 'openAfter', v_open - v_total);
end $$;
revoke all on function public.kassa_adv_report(jsonb) from public, anon;
grant execute on function public.kassa_adv_report(jsonb) to authenticated;

-- Avans hisobotini bekor qilish: faqat kiritilgan kunning o'zida, sabab bilan (2-ro'yxat yoki Direktor). Xarajatlar olib tashlanadi,
--   hisobdordagi qoldiq tiklanadi, dalolatnoma raqami saqlanib «bekor qilingan» bo'ladi. Keyingi kunlarda — buxgalter tuzatishi.
--   sec-1: hisobdorning o'zi (bog'langan xodim kartalaridan biri) o'z hisobotini bekor qilmaydi — boshqa 2-ro'yxat xodimi yoki Direktor.
create or replace function public.kassa_adv_report_void(p_id text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_doc public.cash_docs%rowtype; v_reason text := left(btrim(coalesce(p_reason, '')), 500); v_party text; v_desk text;
begin
  if not (app.fin_list2() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: avans hisobotini buxgalter, Moliya menejeri yoki Direktor bekor qiladi' using errcode = '42501';
  end if;
  if length(v_reason) < 5 then raise exception 'Bekor qilish sababini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  select c."partyId", c.desk into v_party, v_desk from public.cash_docs c where c.id = p_id and c.op = 'nc_adv_report';
  if not found then raise exception 'Avans hisoboti topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
  if v_party = any(app.kassa_user_cards(v_uid)) then   -- sec-1
    raise exception 'O''zingiz hisobdor bo''lgan avans hisobotini o''zingiz bekor qilmaysiz — uni boshqa 2-ro''yxat xodimi (buxgalter / Moliya menejeri) yoki Direktor bekor qiladi'
      using errcode = '42501', hint = 'kassa:self_report';
  end if;
  perform pg_advisory_xact_lock(hashtext('iqror_acc:' || coalesce(v_party, '')));   -- hisobdor qulfi — kassa qulfidan (L4) oldin
  perform app.kassa_lock_desk(v_desk);
  select * into v_doc from public.cash_docs c where c.id = p_id for update;
  if v_doc.status = 'void' then return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', true); end if;
  if v_doc.status <> 'posted' then
    raise exception 'Avans hisoboti bekor qilinmaydi (holati: %)', v_doc.status using errcode = 'P0001', hint = 'kassa:bad_status';
  end if;
  if v_doc."businessDay" <> app.fin_today() then
    raise exception 'Avans hisoboti faqat kiritilgan kunning o''zida bekor qilinadi (keyin — buxgalter tuzatishi)' using errcode = 'P0001', hint = 'kassa:day_closed';
  end if;
  perform app.kassa_flag(true);
  delete from public.expenses e where e."cashDocId" = p_id;
  update public.cash_docs set status = 'void', "voidedBy" = v_uid, "voidedAt" = now(), "voidReason" = v_reason where id = p_id;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(p_id) || jsonb_build_object('ok', true, 'dup', false);
end $$;
revoke all on function public.kassa_adv_report_void(text, text) from public, anon;
grant execute on function public.kassa_adv_report_void(text, text) to authenticated;

-- ---------- Moslik (§8.1: P1, P4, P5, P8) — kassa hujjatlari ↔ pul yozuvlari, kassa ishlagan kunlarda (g4v-4) ----------
--   P1  naqd o'quv to'lovi = KO-1:   pay  — kirim orderisiz (yoki summasi / kuni boshqa) naqd to'lov;
--                                     doc  — to'lov yozuvi yo'q (yoki summasi boshqa) o'quv to'lovi orderi;
--   P4  naqd xarajat = KO-2:         row  — chiqim orderisiz naqd (usuli ko'rsatilmagan) «Buxgalteriya» xarajati;
--                                     doc  — «Buxgalteriya»ga ko'chmagan (summasi mos emas) xarajat orderi;
--                                     adv  — avans hisoboti ↔ xarajatlar mos emas yoki hisobotsiz 'accountable' xarajat;
--   P5  maosh va avans = KO-2:       row  — chiqim orderisiz naqd (usulsiz) maosh / avans yozuvi; doc — yozuvsiz maosh / avans orderi;
--                                     ofs  — o'zaro hisob: dalolatnoma, maosh to'lovi ('offset') va o'quv to'lovi ('offset') bir-biriga mos emas;
--                                     ret  — xodim qaytargan pul (KO-1, acc-1): manfiy avans (OP-08) / maosh (OP-09) yozuvisiz order yoki
--                                            o'tkazilgan orderisiz (summasi mos emas) manfiy naqd avans / maosh yozuvi;
--   P8  naqd qaytarish = KO-2:       row  — chiqim orderisiz naqd qaytarish; doc — qaytarish yozuvi yo'q qaytarish orderi
--                                     (faktura, to'lov va o'quvchi avansi — crit-2: avans qaytarish ham refunds qatori, target 'credit').
--   Hammasi 0 bo'lishi shart (AC1.3). Kassa hali ishga tushmagan bo'lsa — {live: false, total: 0}. Faqat asosiy kassa ('main').
--   Kassa ishlagan kunlar — birinchi ishga tushgan kundan, to'xtatilgan davrlarsiz (app.kassa_reconcile, pastda).
-- Kassa hujjatisiz naqd yozuvlar — sanasi [p_from, p_to] oralig'ida, [p_created_from, p_created_to) oralig'ida kiritilganlari (bo'sh
--   chegara — cheklanmagan), p_skip oraliqlarining birortasida kiritilganlaridan tashqari: turi bo'yicha soni va summasi; kirim (o'quv
--   to'lovi) va chiqim (xarajat, maosh, avans, qaytarish) jami.
--   Nazorat ro'yxati (kassa_checks): kassa ishga tushishidan oldingi sanali, keyin kiritilgan yozuvlar (crit-1) va to'xtatilgan davrdagi
--   naqd harakat — qayta ishga tushirish farqi bilan solishtirish uchun (ishga-tushirish §9; to'xtatilgan davrda kiritilgan, lekin orqa
--   sanali yozuvlar ham; p_skip — boshqa ro'yxatda sanalgan to'xtatilgan davr oynalari, ikki marta ko'rinmasin). Qayta ishga tushirish
--   sanashidan keyin kiritilganlari — app.kassa_restart_stale. Qoidalar moslik (P1 / P4 / P5 / P8) bilan bir xil: usuli ko'rsatilmagan
--   yozuv — naqd; maoshni hisoblash qatori (payroll__) — pul harakati emas. Manfiy avans / maosh (xodim qaytargan pul) — summaga ishorasi bilan.
--   (Uch va to'rt argumentli oldingi variantlar o'chiriladi: aks holda qisqa chaqiruv ikki ma'noli bo'lardi.)
drop function if exists app.kassa_cash_rows(date, date, timestamptz);
drop function if exists app.kassa_cash_rows(date, date, timestamptz, timestamptz);
create or replace function app.kassa_cash_rows(p_from date, p_to date, p_created_from timestamptz, p_created_to timestamptz default null,
                                               p_skip tstzrange[] default null) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  with x(kind, dir, n, s) as (
    select 'tuition', 1, count(*), coalesce(sum(r.amount), 0)
      from app.fin_receipts(greatest(p_from, coalesce((p_created_from at time zone 'Asia/Tashkent')::date - 32, p_from)), p_to) r
      join public.payments p on p.id = r.id
     where r.provider = 'cash' and p."cashDocId" is null and (p_created_from is null or p."createdAt" >= p_created_from)
       and (p_created_to is null or p."createdAt" < p_created_to) and (p_skip is null or not p."createdAt" <@ any(p_skip))
    union all
    select 'expense', -1, count(*), coalesce(sum(e.amount), 0) from public.expenses e
     where e.date between to_char(p_from, 'YYYY-MM-DD') and to_char(p_to, 'YYYY-MM-DD') and coalesce(e.method, '') in ('', 'cash')
       and e."cashDocId" is null and coalesce(e.id, '') not like 'payroll\_\_%' and (p_created_from is null or e."createdAt" >= p_created_from)
       and (p_created_to is null or e."createdAt" < p_created_to) and (p_skip is null or not e."createdAt" <@ any(p_skip))
    union all
    select 'salary', -1, count(*), coalesce(sum(s.paid), 0) from public.salary_payments s
     where s.date between to_char(p_from, 'YYYY-MM-DD') and to_char(p_to, 'YYYY-MM-DD') and coalesce(s.method, '') in ('', 'cash')
       and s."cashDocId" is null and (p_created_from is null or s."createdAt" >= p_created_from) and (p_created_to is null or s."createdAt" < p_created_to)
       and (p_skip is null or not s."createdAt" <@ any(p_skip))
    union all
    select 'advance', -1, count(*), coalesce(sum(a.amount), 0) from public.staff_advances a
     where a.date between to_char(p_from, 'YYYY-MM-DD') and to_char(p_to, 'YYYY-MM-DD') and coalesce(a.method, '') in ('', 'cash')
       and a."cashDocId" is null and (p_created_from is null or a."createdAt" >= p_created_from) and (p_created_to is null or a."createdAt" < p_created_to)
       and (p_skip is null or not a."createdAt" <@ any(p_skip))
    union all
    select 'refund', -1, count(*), coalesce(sum(r.amount), 0) from public.refunds r
     where r."createdAt" >= (p_from::timestamp at time zone 'Asia/Tashkent') and r."createdAt" < ((p_to + 1)::timestamp at time zone 'Asia/Tashkent')
       and coalesce(r.method, '') = 'cash' and r."cashDocId" is null and (p_created_from is null or r."createdAt" >= p_created_from)
       and (p_created_to is null or r."createdAt" < p_created_to) and (p_skip is null or not r."createdAt" <@ any(p_skip)))
  select jsonb_build_object(
           'items', coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'n', x.n, 'sum', x.s) order by x.dir desc, x.kind) filter (where x.n > 0), '[]'::jsonb),
           'n', coalesce(sum(x.n), 0), 'in', coalesce(sum(x.s) filter (where x.dir > 0), 0), 'out', coalesce(sum(x.s) filter (where x.dir < 0), 0))
    from x
$$;
revoke all on function app.kassa_cash_rows(date, date, timestamptz, timestamptz, tstzrange[]) from public, anon, authenticated;

-- Qayta ishga tushirish sanashi eskirganmi (g4v-2): komissiya sanagan paytdan ("restartAt") QAT'IY KEYIN kiritilgan, sanasi to'xtatilgan
--   davrda (oxirgi kassa kunidan KEYIN, qayta ishga tushirish kunidan oldin) bo'lgan kassa hujjatisiz naqd yozuvlar (soni, kirim, chiqim) —
--   ular sanalgan summaga kirmagan: birinchi qayta ochilgan kun shu summa bilan ochilsa, farq birinchi yopishda kassirga kamomad / ortiqcha
--   bo'lib tushardi. Oxirgi kassa kuni sanasi bu yerga kirmaydi (g4b-v1): kassa ushlangan paytda bunday hujjatisiz yozuv qabul qilinmaydi
--   (g4r-2), ishlayotgan kassada esa naqd o'quv to'lovi KO-1 bilan yoziladi — to'lov qatori shu tranzaksiyada hujjat bog'lanishidan oldin
--   (app.kassa_resolve_day chaqirilganda) hali hujjatsiz turadi va o'zini sanab, birinchi kunni qayta sanash ham ocholmaydigan qilib qo'yardi.
--   Tayyorlangan (hali boshlanmagan) qayta ishga tushirish bo'lmasa — NULL. Shu kun bilan qayta sanash "restartAt" ni yangilaydi.
--   Ishlatuvchilar: kassa-docs.sql app.kassa_resolve_day (birinchi kun ochilmaydi), kassa-day.sql app.kassa_golive_guard (ishga tushadigan
--   kun qo'yilmaydi) va kassa_state (sahifadagi ogohlantirish).
create or replace function app.kassa_restart_stale(p_desk text) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.kassa_cash_rows(l.last_day + 1, k."restartDay" - 1, k."restartAt" + interval '1 microsecond')
    from public.cash_desks k
   cross join lateral (select max(d.day) as last_day from public.cash_days d where d.desk = k.id) l
   where k.id = p_desk and not k."isTest" and k."restartAt" is not null and k."restartDay" > l.last_day
$$;
revoke all on function app.kassa_restart_stale(text) from public, anon, authenticated;

-- Moslikning bir oraliq bo'yicha hisobi (ichki; app.kassa_reconcile kassa ishlagan har davr uchun chaqiradi): [p_from, p_to] dagi
--   P1 / P4 / P5 / P8 sonlari (qoidalar — pastda, app.kassa_reconcile izohida).
create or replace function app.kassa_reconcile_range(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_to date := p_to; v_from date := p_from; v_f text; v_t text;
  v_p1p int; v_p1ps numeric; v_p1d int; v_p4r int; v_p4d int; v_p4a int; v_p5r int; v_p5d int; v_p5o int; v_p5t int; v_p8r int; v_p8d int;
begin
  v_f := to_char(v_from, 'YYYY-MM-DD'); v_t := to_char(v_to, 'YYYY-MM-DD');
  -- P1
  select count(*), coalesce(sum(r.amount), 0) into v_p1p, v_p1ps
    from app.fin_receipts(v_from, v_to) r
   where r.provider = 'cash'
     and not exists (select 1 from public.payments p join public.cash_docs c on c.id = p."cashDocId"
                      where p.id = r.id and c.status = 'posted' and c.op = 'in_tuition' and c.amount = r.amount and c."businessDay" = r.day);
  select count(*) into v_p1d from public.cash_docs c
   where c.desk = 'main' and c.op = 'in_tuition' and c.status = 'posted' and c."businessDay" between v_from and v_to
     and not exists (select 1 from public.payments p where p.id = c."sourceId" and p."cashDocId" = c.id and p.amount = c.amount
                                                       and coalesce(p.status, '') <> 'canceled');
  -- P4
  select count(*) into v_p4r from public.expenses e
   where e.date between v_f and v_t and coalesce(e.id, '') not like 'payroll\_\_%' and coalesce(e.method, '') in ('', 'cash')
     and not exists (select 1 from public.cash_docs c where c.id = e."cashDocId" and c.status = 'posted' and c.op = 'out_expense');
  select count(*) into v_p4d from public.cash_docs c
   where c.desk = 'main' and c.op = 'out_expense' and c.status = 'posted' and c."businessDay" between v_from and v_to
     and coalesce((select sum(e.amount) from public.expenses e where e."cashDocId" = c.id), 0) <> c.amount;
  -- P4: avans hisoboti — dalolatnoma ↔ «Buxgalteriya» xarajatlari (usul 'accountable'); hisobotsiz 'accountable' xarajat
  select (select count(*) from public.cash_docs c
           where c.op = 'nc_adv_report' and c.status = 'posted' and c."businessDay" between v_from and v_to
             and coalesce((select sum(e.amount) from public.expenses e where e."cashDocId" = c.id and e.method = 'accountable'), 0) <> c.amount)
       + (select count(*) from public.expenses e
           where e.date between v_f and v_t and e.method = 'accountable'
             and not exists (select 1 from public.cash_docs c where c.id = e."cashDocId" and c.status = 'posted' and c.op = 'nc_adv_report'))
    into v_p4a;
  -- P5 (manfiy — xodim qaytargan pul yozuvlari — «ret» da)
  select (select count(*) from public.salary_payments s
           where s.date between v_f and v_t and coalesce(s.method, '') in ('', 'cash') and coalesce(s.paid, 0) >= 0
             and not exists (select 1 from public.cash_docs c where c.id = s."cashDocId" and c.status = 'posted' and c.op = 'out_salary'))
       + (select count(*) from public.staff_advances a
           where a.date between v_f and v_t and coalesce(a.method, '') in ('', 'cash') and coalesce(a.amount, 0) >= 0
             and not exists (select 1 from public.cash_docs c where c.id = a."cashDocId" and c.status = 'posted' and c.op = 'out_advance'))
    into v_p5r;
  select count(*) into v_p5d from public.cash_docs c
   where c.desk = 'main' and c.op in ('out_salary', 'out_advance') and c.status = 'posted' and c."businessDay" between v_from and v_to
     and not (case when c.op = 'out_salary'
                   then exists (select 1 from public.salary_payments s where s."cashDocId" = c.id and coalesce(s.paid, 0) = c.amount)
                   else exists (select 1 from public.staff_advances a where a."cashDocId" = c.id and coalesce(a.amount, 0) = c.amount) end);
  -- P5: o'zaro hisob — dalolatnoma ↔ maosh to'lovi ↔ o'quv to'lovi
  select (select count(*) from public.cash_docs c
           where c.op = 'nc_offset' and c.status = 'posted' and c."businessDay" between v_from and v_to
             and not (exists (select 1 from public.salary_payments s where s."cashDocId" = c.id and s.method = 'offset' and coalesce(s.paid, 0) = c.amount)
                      and exists (select 1 from public.payments pm where pm."cashDocId" = c.id and pm.provider = 'offset' and pm.amount = c.amount
                                                                      and coalesce(pm.status, '') <> 'canceled')))
       + (select count(*) from public.salary_payments s
           where s.date between v_f and v_t and s.method = 'offset'
             and not exists (select 1 from public.cash_docs c where c.id = s."cashDocId" and c.status = 'posted' and c.op = 'nc_offset'))
       + (select count(*) from app.fin_receipts(v_from, v_to) r
           where r.provider = 'offset'
             and not exists (select 1 from public.payments pm join public.cash_docs c on c.id = pm."cashDocId"
                              where pm.id = r.id and c.status = 'posted' and c.op = 'nc_offset' and c.amount = r.amount))
    into v_p5o;
  -- P5: xodim qaytargan pul (KO-1) ↔ manfiy avans / maosh yozuvi (acc-1)
  select (select count(*) from public.cash_docs c
           where c.desk = 'main' and c.op = 'in_staff_return' and c.status = 'posted' and c."businessDay" between v_from and v_to
             and not exists (select 1 from public.cash_doc_lines l where l."docId" = c.id and (
                   (l."articleId" = 'OP-08' and exists (select 1 from public.staff_advances a where a."cashDocId" = c.id and a.amount = -c.amount))
                or (l."articleId" = 'OP-09' and exists (select 1 from public.salary_payments s where s."cashDocId" = c.id and s.paid = -c.amount)))))
       + (select count(*) from public.staff_advances a
           where a.date between v_f and v_t and coalesce(a.method, '') in ('', 'cash') and a.amount < 0
             and not exists (select 1 from public.cash_docs c where c.id = a."cashDocId" and c.status = 'posted' and c.op = 'in_staff_return' and c.amount = -a.amount))
       + (select count(*) from public.salary_payments s
           where s.date between v_f and v_t and coalesce(s.method, '') in ('', 'cash') and s.paid < 0
             and not exists (select 1 from public.cash_docs c where c.id = s."cashDocId" and c.status = 'posted' and c.op = 'in_staff_return' and c.amount = -s.paid))
    into v_p5t;
  -- P8
  select count(*) into v_p8r from public.refunds r
   where r."createdAt" >= (v_from::timestamp at time zone 'Asia/Tashkent') and r."createdAt" < ((v_to + 1)::timestamp at time zone 'Asia/Tashkent')
     and coalesce(r.method, '') = 'cash'
     and not exists (select 1 from public.cash_docs c where c.id = r."cashDocId" and c.status = 'posted' and c.op = 'out_refund');
  select count(*) into v_p8d from public.cash_docs c
   where c.desk = 'main' and c.op = 'out_refund' and c.status = 'posted' and c."businessDay" between v_from and v_to
     and not exists (select 1 from public.refunds r where r."cashDocId" = c.id);
  return jsonb_build_object(
    'p1', jsonb_build_object('pay', v_p1p, 'paySum', v_p1ps, 'doc', v_p1d),
    'p4', jsonb_build_object('row', v_p4r, 'doc', v_p4d, 'adv', v_p4a),
    'p5', jsonb_build_object('row', v_p5r, 'doc', v_p5d, 'ofs', v_p5o, 'ret', v_p5t),
    'p8', jsonb_build_object('row', v_p8r, 'doc', v_p8d));
end $$;
revoke all on function app.kassa_reconcile_range(date, date) from public, anon, authenticated;

-- Moslik — kassa ISHLAGAN barcha davrlar bo'yicha (g4v-4): birinchi ishga tushgan kundan so'ralgan oxirgi kungacha, to'xtatilgan davrlar
--   (oxirgi kassa kunidan keyin, qayta ishga tushirish kunidan oldin — kassa-day.sql app.kassa_periods) chiqarib tashlanadi; kassa hozir
--   to'xtatilgan bo'lsa — oxirgi kassa kunigacha. Avval faqat hozirgi «ishga tushadigan kun»dan hisoblanardi: to'xtatilgan kassada
--   (sana bo'sh) va qayta ishga tushirilgandan keyin birinchi davr yetimlari nazorat ro'yxati, Telegram va kassa-checks.sql dan yo'qolardi.
--   p_from / p_to — so'ralgan oraliq (bo'sh: birinchi ishga tushgan kundan / bugungacha), kassa ishlagan kunlar bilan kesishmasi tekshiriladi.
create or replace function app.kassa_reconcile(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_p jsonb := app.kassa_periods('main'); v_first date; v_to date := coalesce(p_to, app.fin_today()); v_from date; v_lo date;
  v_los date[] := '{}'; v_his date[] := '{}'; g jsonb; v_r jsonb;
  v_p1p int := 0; v_p1ps numeric := 0; v_p1d int := 0; v_p4r int := 0; v_p4d int := 0; v_p4a int := 0;
  v_p5r int := 0; v_p5d int := 0; v_p5o int := 0; v_p5t int := 0; v_p8r int := 0; v_p8d int := 0;
begin
  v_first := (v_p ->> 'first')::date;
  if v_first is null or v_first > v_to then return jsonb_build_object('live', false, 'total', 0); end if;
  if coalesce((v_p ->> 'paused')::boolean, false) then v_to := least(v_to, (v_p ->> 'last')::date); end if;
  v_from := greatest(coalesce(p_from, v_first), v_first);
  -- kassa ishlagan davrlar: [birinchi kun, 1-to'xtatishdagi oxirgi kassa kuni], [1-qayta ishga tushirish kuni, 2-to'xtatishdagi oxirgi kun], …,
  --   [oxirgi qayta ishga tushirish kuni, …) — har biri so'ralgan oraliq bilan kesishgan qismi tekshiriladi
  v_lo := v_first;
  for g in select x from jsonb_array_elements(v_p -> 'gaps') x order by (x ->> 'after')::date loop
    if (g ->> 'after')::date >= v_lo then v_los := v_los || v_lo; v_his := v_his || (g ->> 'after')::date; end if;
    v_lo := greatest(v_lo, (g ->> 'before')::date);
  end loop;
  v_los := v_los || v_lo; v_his := v_his || v_to;
  for i in 1 .. cardinality(v_los) loop
    if greatest(v_los[i], v_from) <= least(v_his[i], v_to) then
      v_r := app.kassa_reconcile_range(greatest(v_los[i], v_from), least(v_his[i], v_to));
      v_p1p := v_p1p + (v_r #>> '{p1,pay}')::int; v_p1ps := v_p1ps + (v_r #>> '{p1,paySum}')::numeric; v_p1d := v_p1d + (v_r #>> '{p1,doc}')::int;
      v_p4r := v_p4r + (v_r #>> '{p4,row}')::int; v_p4d := v_p4d + (v_r #>> '{p4,doc}')::int; v_p4a := v_p4a + (v_r #>> '{p4,adv}')::int;
      v_p5r := v_p5r + (v_r #>> '{p5,row}')::int; v_p5d := v_p5d + (v_r #>> '{p5,doc}')::int; v_p5o := v_p5o + (v_r #>> '{p5,ofs}')::int;
      v_p5t := v_p5t + (v_r #>> '{p5,ret}')::int; v_p8r := v_p8r + (v_r #>> '{p8,row}')::int; v_p8d := v_p8d + (v_r #>> '{p8,doc}')::int;
    end if;
  end loop;
  return jsonb_build_object('live', true, 'from', v_from, 'to', v_to,
    'p1', jsonb_build_object('pay', v_p1p, 'paySum', v_p1ps, 'doc', v_p1d),
    'p4', jsonb_build_object('row', v_p4r, 'doc', v_p4d, 'adv', v_p4a),
    'p5', jsonb_build_object('row', v_p5r, 'doc', v_p5d, 'ofs', v_p5o, 'ret', v_p5t),
    'p8', jsonb_build_object('row', v_p8r, 'doc', v_p8d),
    'total', v_p1p + v_p1d + v_p4r + v_p4d + v_p4a + v_p5r + v_p5d + v_p5o + v_p5t + v_p8r + v_p8d);
end $$;
revoke all on function app.kassa_reconcile(date, date) from public, anon, authenticated;

notify pgrst, 'reload schema';
