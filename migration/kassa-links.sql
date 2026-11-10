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
      if (to_jsonb(new) - 'updatedAt') is distinct from (to_jsonb(old) - 'updatedAt') then
        raise exception 'Bu yozuv kassa hujjatiga bog''langan — o''zgartirilmaydi' using errcode = '42501', hint = 'kassa:linked_row';
      end if;
    elsif v_m = 'cash' and coalesce(old.method, '') <> 'cash' then
      raise exception 'Naqd yozuv faqat «Kassa» orqali kiritiladi' using errcode = '42501', hint = 'kassa:cash_only_kassa';
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
    if coalesce(new.id, '') not like 'payroll\_\_%' and v_m not in ('bank', 'card', 'accountable') then
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

-- ---------- Qaytarish: Direktor tasdiqlaydi (so'rov), pul kassadan beriladi ----------
--   p: target ('invoice' | 'payment'), id, amount, reason, clawback (avansni ham qaytarish), payee (kimga beriladi — to'liq F.I.Sh.),
--      requestDate (ariza sanasi, ixtiyoriy), clientRef. Hech narsa o'zgarmaydi — faqat tasdiqlangan KO-2 so'rovi paydo bo'ladi;
--      qaytarishning o'zi kassir pulni bergan paytda (kassa_doc_pay → app.kassa_link_paid) bajariladi.
create or replace function public.kassa_refund_request(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_uid text := app.uid(); v_target text; v_tid text; v_amount numeric; v_reason text; v_payee text; v_claw boolean; v_ref text;
  v_inv record; v_sid text; v_cr numeric := 0; v_pst text; v_pamt numeric; v_lines jsonb; v_month text := to_char(app.fin_today(), 'YYYY-MM');
  v_id text; v_dup boolean; v_email text; v_req text; v_basis text;
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
  select nullif(u.email, '') into v_email from public.users u where u.id = v_uid;
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
    v_lines := jsonb_build_array(jsonb_build_object('debit', '6310', 'credit', '5010', 'amount', v_amount,
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
      'sourceSnapshot', jsonb_build_object('target', v_target, 'targetId', v_tid, 'amount', v_amount, 'reason', v_reason, 'clawback', v_claw and v_cr > 0,
                                           'clawbackAmount', v_cr, 'studentId', v_sid, 'by', coalesce(v_email, '')),
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
declare v_op text; v_snap jsonb;
begin
  select c.op, c."sourceSnapshot" into v_op, v_snap from public.cash_docs c where c.id = p_doc_id;
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
  if v_doc.op = 'out_refund' then
    s := v_doc."sourceSnapshot";
    if s is null or v_doc."sourceTable" is distinct from 'refunds' then
      raise exception 'Qaytarish hujjati ma''lumoti to''liq emas' using errcode = 'P0001', hint = 'kassa:refund';
    end if;
    select coalesce(array_agg(x.id), '{}') into v_before from public.refunds x
     where x."targetId" in (s ->> 'targetId', coalesce(s ->> 'studentId', ''));
    r := public.refund_invoice(s ->> 'target', s ->> 'targetId', (s ->> 'amount')::numeric, s ->> 'reason',
                               coalesce((s ->> 'clawback')::boolean, false), coalesce(s ->> 'by', ''), v_doc."sourceId");
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

notify pgrst, 'reload schema';
