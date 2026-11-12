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
--     • qaytarish — kassa_refund_request(p): Direktor tasdiqlaydi (so'rov = tasdiq), balans O'ZGARMAYDI; kassir pulni berganda
--                   (kassa_doc_pay) refund_invoice shu tranzaksiyada bajariladi — balans KO-2 sanasida o'zgaradi;
--                   naqdsiz qaytarish — avvalgidek refund_invoice;
--     • xarajat   — KO-2 «Xarajat» o'tkazilganda har qatori «Buxgalteriya»ga (expenses) ko'chiriladi (statiya → eski toifa),
--                   bekor qilinsa — olib tashlanadi.
--   Himoya (F1.13 qabul mezoni: funksiyani chetlab o'tadigan naqd yo'l yo'q): kassa ishga tushgach salary_payments,
--     staff_advances va expenses jadvallariga NAQD (yoki usuli ko'rsatilmagan) yozuvni to'g'ridan-to'g'ri qo'shib bo'lmaydi;
--     kassa hujjatiga bog'langan qator o'zgartirilmaydi va o'chirilmaydi (faqat «Kassa»dan, hujjatni bekor qilish orqali).
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

-- ---------- Himoya: kassa ishga tushgach naqd yozuv faqat kassa funksiyalari orqali ----------
create or replace function app.kassa_cash_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_m text;
begin
  -- Xarajatga standart statiya — eski toifadan (fin_category_map); «payroll__» (maosh hisoblash) qatoriga tegilmaydi.
  --   (Shartlar ichma-ich: «articleId» ustuni faqat expenses jadvalida bor — boshqa jadvalda bu ifoda hisoblanmasligi kerak.)
  if tg_table_name = 'expenses' and tg_op <> 'DELETE' then
    if new."articleId" is null and coalesce(new.id, '') not like 'payroll\_\_%' then
      select m."articleId" into new."articleId" from public.fin_category_map m where m.category = new.category;
    end if;
  end if;
  if coalesce(current_setting('iqror.kassa_rpc', true), '') = '1' or app.is_system() or not app.kassa_live() then
    return coalesce(new, old);
  end if;
  if tg_op = 'DELETE' then
    if old."cashDocId" is not null then
      raise exception 'Bu yozuv kassa hujjatiga bog''langan — «Kassa» bo''limida hujjatni bekor qilish orqali olib tashlanadi' using errcode = '42501', hint = 'kassa:linked_row';
    end if;
    return old;
  end if;
  v_m := coalesce(new.method, '');
  if tg_op = 'UPDATE' then
    if old."cashDocId" is not null or new."cashDocId" is not null then
      -- «Yangi noyob ID berish» (id-guards.sql: rekey_payroll_id) xodim kalitini tarix qatorlarida ham almashtiradi — faqat shu ustun.
      if coalesce(current_setting('iqror.rekey', true), '') = '1' and tg_table_name in ('salary_payments', 'staff_advances')
         and (to_jsonb(new) - 'updatedAt' - 'teacherId') = (to_jsonb(old) - 'updatedAt' - 'teacherId') then
        return new;
      end if;
      if (to_jsonb(new) - 'updatedAt') is distinct from (to_jsonb(old) - 'updatedAt') then
        raise exception 'Bu yozuv kassa hujjatiga bog''langan — o''zgartirilmaydi' using errcode = '42501', hint = 'kassa:linked_row';
      end if;
    elsif v_m = 'cash' and coalesce(old.method, '') <> 'cash' then
      raise exception 'Naqd yozuv faqat «Kassa» orqali kiritiladi' using errcode = '42501', hint = 'kassa:cash_only_kassa';
    elsif tg_table_name = 'expenses' and v_m = 'accountable' and coalesce(old.method, '') <> 'accountable' then
      raise exception 'Hisobdor shaxs xarajati «Kassa» → «Avans hisoboti» orqali yoziladi' using errcode = '42501', hint = 'kassa:cash_only_kassa';
    end if;
    return new;
  end if;
  -- INSERT
  if new."cashDocId" is not null then
    raise exception 'Kassa hujjati havolasini faqat kassa funksiyalari qo''yadi' using errcode = '42501', hint = 'kassa:linked_row';
  end if;
  if tg_table_name = 'salary_payments' then
    raise exception 'Kassa ishga tushgan: maosh «Maosh berish» oynasidan, to''lov usuli bilan yoziladi (naqd — kassa chiqim orderi bilan)'
      using errcode = '42501', hint = 'kassa:cash_only_kassa';
  elsif tg_table_name = 'staff_advances' then
    if v_m <> 'card' then
      raise exception 'Kassa ishga tushgan: naqd avans «Kassa» → «+ Chiqim so''rovi» → «Ish haqi avansi» orqali beriladi' using errcode = '42501', hint = 'kassa:cash_only_kassa';
    end if;
  elsif tg_table_name = 'expenses' then
    -- «payroll__YYYY-MM» — oylik maoshni hisoblash qatori (pul harakati emas): avvalgidek.
    --   Hisobdor shaxs orqali xarajat ('accountable') — faqat «Avans hisoboti» dalolatnomasidan (shu funksiya bayroq bilan yozadi):
    --   aks holda xarajat ikki marta (qo'lda va hisobotdan) yozilib, hisobdordagi qoldiq kamaymay qolardi.
    if coalesce(new.id, '') not like 'payroll\_\_%' and v_m not in ('bank', 'card') then
      if v_m = 'accountable' then
        raise exception 'Kassa ishga tushgan: hisobdor shaxs xarajati «Kassa» → «Avans hisoboti» orqali yoziladi (avans qoldig''idan hisobdan chiqariladi)'
          using errcode = '42501', hint = 'kassa:cash_only_kassa';
      end if;
      raise exception 'Kassa ishga tushgan: naqd xarajat «Kassa» → «+ Chiqim so''rovi» orqali yoziladi; naqdsiz xarajatda to''lov usulini tanlang'
        using errcode = '42501', hint = 'kassa:cash_only_kassa';
    end if;
  end if;
  return new;
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
--   p: target ('invoice' | 'payment'), id, amount, reason, clawback (avansni ham qaytarish), payee (kimga beriladi — to'liq F.I.Sh.),
--      requestDate (ariza sanasi, ixtiyoriy), clientRef. Hech narsa o'zgarmaydi — faqat tasdiqlangan KO-2 so'rovi paydo bo'ladi;
--      qaytarishning o'zi kassir pulni bergan paytda (kassa_doc_pay → app.kassa_link_paid) bajariladi.
create or replace function public.kassa_refund_request(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_target text; v_tid text; v_amount numeric; v_reason text; v_payee text; v_claw boolean; v_ref text;
  v_inv record; v_sid text; v_cr numeric := 0; v_pst text; v_pamt numeric; v_lines jsonb; v_month text := to_char(app.fin_today(), 'YYYY-MM');
  v_id text; v_dup boolean; v_req text; v_basis text;
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
  if v_target not in ('invoice', 'payment') or v_tid = '' or v_ref !~ '^[A-Za-z0-9_.:-]{6,70}$' then
    raise exception 'Qaytarish ma''lumoti to''liq emas' using errcode = '22023', hint = 'kassa:bad_input';
  end if;
  if length(v_reason) < 3 then raise exception 'Qaytarish sababini yozing' using errcode = '22023', hint = 'kassa:reason'; end if;
  if length(v_payee) < 5 then raise exception 'Pul kimga berilishini to''liq yozing (F.I.Sh.)' using errcode = '22023', hint = 'kassa:party'; end if;
  begin v_req := to_char(nullif(p ->> 'requestDate', '')::date, 'DD.MM.YYYY'); exception when others then v_req := null; end;
  v_basis := 'Qaytarish: ' || v_reason || case when v_req is not null then '; ariza ' || v_req else '' end;

  if v_target = 'invoice' then
    select i.id, i."studentId", coalesce(i.amount, 0) as amount, coalesce(i.status, '') as status, coalesce(i.month, '') as month,
           case when i.status = 'paid' then greatest(coalesce(i."paidAmount", 0), coalesce(i.amount, 0)) else coalesce(i."paidAmount", 0) end as paid
      into v_inv from public.invoices i where i.id = v_tid;
    if not found then raise exception 'Hisob-faktura topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
    if v_inv.status in ('canceled', 'reversed') or v_amount > v_inv.paid + 0.5 then
      raise exception 'Qaytarib bo''lmaydi: bu hisob-fakturada % so''m to''langan', v_inv.paid using errcode = '22023', hint = 'kassa:refund';
    end if;
    v_sid := v_inv."studentId";
    v_lines := jsonb_build_array(jsonb_build_object(
      'debit', case when v_inv.month ~ '^\d{4}-\d{2}$' and v_inv.month > v_month then '6310' else '4010' end, 'credit', '5010', 'amount', v_amount,
      'analytics', jsonb_build_object('studentId', v_sid, 'invoiceId', v_inv.id, 'month', v_inv.month)));
    if v_claw then
      select coalesce(c.credit, 0) into v_cr from public.student_credit c where c.id = v_sid;
      v_cr := coalesce(v_cr, 0);
      if v_cr > 0 then
        v_lines := v_lines || jsonb_build_object('debit', '6310', 'credit', '5010', 'amount', v_cr,
                                                 'analytics', jsonb_build_object('studentId', v_sid, 'kind', 'credit_refund'));
      end if;
    end if;
  else
    select coalesce(pm.status, ''), coalesce(pm.amount, 0) into v_pst, v_pamt from public.payments pm where pm.id = v_tid;
    if not found then raise exception 'To''lov topilmadi' using errcode = '22023', hint = 'kassa:not_found'; end if;
    if v_pst not in ('unmatched', '') then
      raise exception 'Faqat biriktirilmagan to''lov shu yo''l bilan qaytariladi (holati: %)', v_pst using errcode = '22023', hint = 'kassa:refund';
    end if;
    if abs(v_amount - v_pamt) > 0.5 then
      raise exception 'Biriktirilmagan to''lov faqat to''liq qaytariladi (% so''m)', v_pamt using errcode = '22023', hint = 'kassa:refund';
    end if;
    v_claw := false;
    -- biriktirilmagan (aniqlanmagan) tushum 6390 da turadi (PR-13, OP-16) — qaytarish ham shu hisobdan
    v_lines := jsonb_build_array(jsonb_build_object('debit', '6390', 'credit', '5010', 'amount', v_amount, 'articleId', 'OP-16',
                                                    'analytics', jsonb_build_object('paymentId', v_tid)));
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
create or replace function app.kassa_link_prelock(p_doc_id text) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_op text; v_snap jsonb; v_party text;
begin
  select c.op, c."sourceSnapshot", c."partyId" into v_op, v_snap, v_party from public.cash_docs c where c.id = p_doc_id;
  if v_op = 'out_accountable' then   -- hisobdor qulfi (avans hisoboti bilan bir navbat): qoldiq tekshiruvi va to'lov orasida o'zgarmasin
    perform pg_advisory_xact_lock(hashtext('iqror_acc:' || coalesce(v_party, '')));
  end if;
  if v_op = 'out_refund' and v_snap is not null then
    perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_snap ->> 'studentId', '')));
    if v_snap ->> 'target' = 'payment' then perform 1 from public.payments pm where pm.id = v_snap ->> 'targetId' for update; end if;
  end if;
end $$;
revoke all on function app.kassa_link_prelock(text) from public, anon, authenticated;

-- ---------- Pul berilgandan keyin (hujjat o'tkazilgan, shu tranzaksiya): bog'langan amal ----------
create or replace function app.kassa_link_paid(p_doc_id text, p_uid text) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_doc public.cash_docs%rowtype; s jsonb; r jsonb; v_before text[]; v_code text; l record; v_cat text;
begin
  select * into v_doc from public.cash_docs c where c.id = p_doc_id;
  -- Sinov kassasi (CT-20): hujjatlari va raqamlari alohida — «Buxgalteriya», avans va qaytarish jadvallariga HECH NARSA yozilmaydi.
  if coalesce((select k."isTest" from public.cash_desks k where k.id = v_doc.desk), false) then return; end if;
  if v_doc.op = 'out_refund' then
    s := v_doc."sourceSnapshot";
    if s is null or v_doc."sourceTable" is distinct from 'refunds' then
      raise exception 'Qaytarish hujjati ma''lumoti to''liq emas' using errcode = 'P0001', hint = 'kassa:refund';
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
    for l in select * from public.cash_doc_lines x where x."docId" = v_doc.id and x.cash order by x."lineNo" loop
      select m.category into v_cat from public.fin_category_map m where m."articleId" = l."articleId" order by m.category limit 1;
      insert into public.expenses (id, date, month, category, amount, note, method, "cashDocId", "articleId", "counterpartyId")
        values ('kx_' || v_doc.id || '_' || l."lineNo", to_char(v_doc."businessDay", 'YYYY-MM-DD'), to_char(v_doc."businessDay", 'YYYY-MM'),
                coalesce(v_cat, 'Boshqa'), l.amount,
                left(btrim(coalesce(nullif(v_doc."partyName", ''), '') || case when v_doc.basis <> '' then ' — ' || v_doc.basis else '' end
                           || ' (KO-2 № ' || v_doc.no || ')'), 300),
                'cash', v_doc.id, l."articleId", case when v_doc."partyType" = 'counterparty' then v_doc."partyId" end);
    end loop;
  end if;
end $$;
revoke all on function app.kassa_link_paid(text, text) from public, anon, authenticated;

-- ---------- Shu kunda bekor qilish: bog'langan yozuvni olib tashlash ----------
--   Qaytarish orderi bekor qilinmaydi (pul qaytib kelgan bo'lsa — yangi kirim sifatida qabul qilinadi).
create or replace function app.kassa_link_void(p_doc_id text, p_uid text, p_reason text) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_doc public.cash_docs%rowtype;
begin
  select * into v_doc from public.cash_docs c where c.id = p_doc_id;
  if coalesce((select k."isTest" from public.cash_desks k where k.id = v_doc.desk), false) then return; end if;   -- sinov kassasi: bog'langan yozuv yo'q
  if v_doc.op = 'out_refund' then
    raise exception 'Qaytarish orderi bekor qilinmaydi — xato bo''lsa, pulni yangi to''lov sifatida qayta qabul qiling' using errcode = '42501', hint = 'kassa:linked_doc';
  elsif v_doc.op = 'out_advance' then
    delete from public.staff_advances a where a."cashDocId" = v_doc.id;   -- oy vedomosti tasdiqlangan bo'lsa — trigger rad etadi
  elsif v_doc.op = 'out_salary' then
    delete from public.salary_payments s where s."cashDocId" = v_doc.id;
  elsif v_doc.op = 'out_expense' then
    delete from public.expenses e where e."cashDocId" = v_doc.id;
  end if;
end $$;
revoke all on function app.kassa_link_void(text, text, text) from public, anon, authenticated;

-- ---------- O'zaro hisob (nc_offset): xodimning ish haqidan farzandining o'quv to'lovi — NAQDSIZ ----------
--   Yozma ariza + Direktor (§4.10). BITTA tranzaksiyada:
--     • maosh to'lovi (salary_payments, usul 'offset') — tasdiqlangan vedomost chegarasi mavjud darvoza trigeri bilan;
--     • o'quv to'lovi (payments, provider 'offset') va uning balansga qo'llanishi (apply_payment: eng eski fakturadan, ortiqchasi avansga);
--     • naqdsiz dalolatnoma (ACT): Dt 6710 Kt 4010 / 6310 — taqsimot naqd o'quv to'lovidagi qoida bilan (app.kassa_tuition_alloc).
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

  v_before := app.kassa_tuition_before(v_sid);   -- L1: o'quvchi bo'yicha navbat + to'lovdan oldingi holat
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
  -- 3) naqdsiz dalolatnoma: Dt 6710 Kt 4010 / 6310 (to'lov qayerga taqsimlangan bo'lsa)
  v_a := app.kassa_tuition_alloc(v_before, v_paid, '6710', false, false);
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
--   bo'yicha) + har qator «Buxgalteriya»dagi xarajat (usul 'accountable', shu hujjatga bog'langan). Hisobot summasi hisobdordagi
--   hisobot qilinmagan qoldiqdan oshmaydi: ortiqcha sarf hozircha alohida «Xarajat» orderi bilan beriladi (to'liq versiya — F2.6).
--   Statiyalar — kassa xarajatidagi ro'yxat (ish haqi, soliq, eskirish, bank komissiyasi, jarima kabilar — yo'q).
--   p: clientRef, partyId (xodim: 'teachers:<id>' | 'staff:<id>'), reportDate (qog'ozdagi hisobot sanasi, 92 kun ichida),
--      basis (ixtiyoriy izoh), lines: [{articleId, amount, note — chek yoki hujjat}], 1–40 qator.
create or replace function public.kassa_adv_report(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_ref text; v_pid text; v_pname text; v_rep text; v_basis text; v_today date := app.fin_today();
  v_lines jsonb := '[]'::jsonb; v_line jsonb; v_i int := 0; v_amt numeric; v_total numeric := 0; v_art public.fin_articles%rowtype;
  v_note text; v_open numeric; v_doc_id text; v_dup boolean; v_doc public.cash_docs%rowtype; v_ex public.cash_docs%rowtype; l record; v_cat text;
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
    if v_art.kind <> 'EX' or not v_art."cashOutAllowed" or nullif(v_art."accountCode", '') is null then
      raise exception '«%» statiyasi bo''yicha hisobdor xarajati yozilmaydi', v_art."nameUz" using errcode = '22023', hint = 'kassa:article';
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
    select m.category into v_cat from public.fin_category_map m where m."articleId" = l."articleId" order by m.category limit 1;
    insert into public.expenses (id, date, month, category, amount, note, method, "cashDocId", "articleId")
      values ('ka_' || v_doc.id || '_' || l."lineNo", to_char(v_doc."businessDay", 'YYYY-MM-DD'), to_char(v_doc."businessDay", 'YYYY-MM'),
              coalesce(v_cat, 'Boshqa'), l.amount,
              left(btrim(v_pname || case when coalesce(l.note, '') <> '' then ' — ' || l.note else '' end || ' (avans hisoboti № ' || v_doc.no || ')'), 300),
              'accountable', v_doc.id, l."articleId");
  end loop;
  perform app.kassa_flag(false);
  return app.kassa_doc_json(v_doc.id) || jsonb_build_object('ok', true, 'dup', false, 'openBefore', v_open, 'openAfter', v_open - v_total);
end $$;
revoke all on function public.kassa_adv_report(jsonb) from public, anon;
grant execute on function public.kassa_adv_report(jsonb) to authenticated;

-- Avans hisobotini bekor qilish: faqat kiritilgan kunning o'zida, sabab bilan (2-ro'yxat yoki Direktor). Xarajatlar olib tashlanadi,
--   hisobdordagi qoldiq tiklanadi, dalolatnoma raqami saqlanib «bekor qilingan» bo'ladi. Keyingi kunlarda — buxgalter tuzatishi.
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

-- ---------- Moslik (§8.1: P1, P4, P5, P8) — kassa hujjatlari ↔ pul yozuvlari, kassa ishga tushgan kundan ----------
--   P1  naqd o'quv to'lovi = KO-1:   pay  — kirim orderisiz (yoki summasi / kuni boshqa) naqd to'lov;
--                                     doc  — to'lov yozuvi yo'q (yoki summasi boshqa) o'quv to'lovi orderi;
--   P4  naqd xarajat = KO-2:         row  — chiqim orderisiz naqd (usuli ko'rsatilmagan) «Buxgalteriya» xarajati;
--                                     doc  — «Buxgalteriya»ga ko'chmagan (summasi mos emas) xarajat orderi;
--                                     adv  — avans hisoboti ↔ xarajatlar mos emas yoki hisobotsiz 'accountable' xarajat;
--   P5  maosh va avans = KO-2:       row  — chiqim orderisiz naqd (usulsiz) maosh / avans yozuvi; doc — yozuvsiz maosh / avans orderi;
--                                     ofs  — o'zaro hisob: dalolatnoma, maosh to'lovi ('offset') va o'quv to'lovi ('offset') bir-biriga mos emas;
--   P8  naqd qaytarish = KO-2:       row  — chiqim orderisiz naqd qaytarish; doc — qaytarish yozuvi yo'q qaytarish orderi.
--   Hammasi 0 bo'lishi shart (AC1.3). Kassa ishga tushmagan bo'lsa — {live: false, total: 0}. Faqat asosiy kassa ('main').
create or replace function app.kassa_reconcile(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_live date; v_to date := coalesce(p_to, app.fin_today()); v_from date; v_f text; v_t text;
  v_p1p int; v_p1ps numeric; v_p1d int; v_p4r int; v_p4d int; v_p4a int; v_p5r int; v_p5d int; v_p5o int; v_p8r int; v_p8d int;
begin
  select o."kassaGoLive" into v_live from public.fin_org o where o.id = 'main';
  if v_live is null or v_live > v_to then return jsonb_build_object('live', false, 'total', 0); end if;
  v_from := greatest(coalesce(p_from, v_live), v_live);
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
  -- P5
  select (select count(*) from public.salary_payments s
           where s.date between v_f and v_t and coalesce(s.method, '') in ('', 'cash')
             and not exists (select 1 from public.cash_docs c where c.id = s."cashDocId" and c.status = 'posted' and c.op = 'out_salary'))
       + (select count(*) from public.staff_advances a
           where a.date between v_f and v_t and coalesce(a.method, '') in ('', 'cash')
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
  -- P8
  select count(*) into v_p8r from public.refunds r
   where r."createdAt" >= (v_from::timestamp at time zone 'Asia/Tashkent') and r."createdAt" < ((v_to + 1)::timestamp at time zone 'Asia/Tashkent')
     and coalesce(r.method, '') = 'cash'
     and not exists (select 1 from public.cash_docs c where c.id = r."cashDocId" and c.status = 'posted' and c.op = 'out_refund');
  select count(*) into v_p8d from public.cash_docs c
   where c.desk = 'main' and c.op = 'out_refund' and c.status = 'posted' and c."businessDay" between v_from and v_to
     and not exists (select 1 from public.refunds r where r."cashDocId" = c.id);
  return jsonb_build_object('live', true, 'from', v_from, 'to', v_to,
    'p1', jsonb_build_object('pay', v_p1p, 'paySum', v_p1ps, 'doc', v_p1d),
    'p4', jsonb_build_object('row', v_p4r, 'doc', v_p4d, 'adv', v_p4a),
    'p5', jsonb_build_object('row', v_p5r, 'doc', v_p5d, 'ofs', v_p5o),
    'p8', jsonb_build_object('row', v_p8r, 'doc', v_p8d),
    'total', v_p1p + v_p1d + v_p4r + v_p4d + v_p4a + v_p5r + v_p5d + v_p5o + v_p8r + v_p8d);
end $$;
revoke all on function app.kassa_reconcile(date, date) from public, anon, authenticated;

notify pgrst, 'reload schema';
