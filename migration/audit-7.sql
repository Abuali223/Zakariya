-- =====================================================================
-- AUDIT-7 — [P0 PUL] apply_payment: p_sid'ni KANONIK studentId'ga normallashtirish.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/audit-7.sql
-- Idempotent (CREATE OR REPLACE). run-all.sql'да audit-4'дан KEYIN ishlaydi
-- (keyingi ta'rif ustun) — audit-4'даги apply_payment'ni yangilaydi.
--
-- ILDIZ SABAB ("chalkashlik"):
--   Import qilingan (Firebase) o'quvchida students.id (hujjat _id) <> studentId (IQ-xxxx).
--   Click "erkin" to'lovi telefon/ism bo'yicha o'quvchini topganда (findStudentByPhone)
--   HUJJAT _id sini qaytaradi. Eski apply_payment esa invoyslarни FAQAT
--   `where "studentId" = p_sid` bilan qidirardi -> _id != studentId bo'lgani uchun
--   BIRORTA to'lanmagan invoys topilmasdi -> BUTUN summa avansга ("Ortiqcha to'lov ->
--   avans") o'tib ketardi. Ism to'g'ri ko'rinardi, chunki ism qidiruvi `id OR studentId`
--   edi — shu asimmetriya aynan simptomni tushuntiradi.
--
-- TUZATISH: RPC boshida p_sid'ni students orqali kanonik studentId'ga aylantiramiz
--   (id=p_sid YOKI studentId=p_sid -> studentId). Shundan keyin invoys/avans/jurnal/
--   advisory-lock HAMMASИ bitta kanonik kalit bilan ishlaydi. Bu qaysi kalit
--   uzatilishидан QAT'I NAZAR to'g'ri ishlaydi (webhook, kassir, qo'lda) va
--   rekey-students.sql ishga tushirilган-tushirilmaganига bog'liq emas.
-- =====================================================================
create or replace function public.apply_payment(p_sid text, p_amount numeric, p_provider text, p_pay_id text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_sid text;
  v_credit numeric := 0;
  v_available numeric;
  v_provider text;
  v_inserted int := 0;
  v_pay numeric;
  v_newpaid numeric;
  v_full boolean;
  v_delta numeric;
  v_name text;
  v_claims jsonb;
  inv record;
begin
  -- Ruxsat: faqat to'lov oluvchilar (kassir/moliya/direktor) yoki server (service_role).
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance() or app.is_cashier()
          or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  p_amount := coalesce(p_amount, 0);
  if p_amount < 0 then return jsonb_build_object('ok', false, 'reason', 'neg'); end if;
  v_provider := coalesce(nullif(p_provider, ''), case when p_amount > 0 then 'click' else 'credit' end);

  -- ★ KANONIK KALIT: p_sid _id (Firebase hujjat) YOKI studentId (IQ-xxxx) bo'lishi mumkin.
  --   Har doim studentId'ga keltiramiz — invoyslar, avans, jurnal shu bilan kalitlangan.
  --   Topilmasa (o'quvchi yo'q) p_sid o'zi qoladi.
  select "studentId" into v_sid from public.students
   where id = p_sid or "studentId" = p_sid
   order by (id = p_sid) desc limit 1;
  v_sid := coalesce(nullif(v_sid, ''), p_sid);

  -- Idempotentlik: posbonni AVVAL o'rnatamiz. Allaqachon bo'lsa -> dup, qayta qo'llamaymiz.
  if p_pay_id is not null and p_pay_id <> '' then
    insert into public.applied_payments(id, "studentId", amount, "createdAt")
      values (p_pay_id, v_sid, p_amount, now())
      on conflict (id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted = 0 then
      return jsonb_build_object('dup', true);
    end if;
  end if;

  -- Shu o'quvchi bo'yicha BARCHA to'lovlarni seriyalash (advisory lock kanonik kalit bilan
  -- -> _id va studentId bilan kelgan to'lovlar ham bir xil qulfга tushadi).
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));

  -- Joriy avans.
  select coalesce(credit, 0) into v_credit from public.student_credit where id = v_sid for update;
  if not found then v_credit := 0; end if;
  v_available := p_amount + coalesce(v_credit, 0);

  -- Waterfall: eng eski (oy bo'yicha) to'lanmagan invoysdan boshlab; qulflaymiz.
  -- MUHIM: status IS NULL (eski/import) invoyslar ham TO'LANMAGAN hisoblanadi.
  for inv in
    select id, coalesce(amount, 0) as amount, coalesce("paidAmount", 0) as paid
      from public.invoices
     where "studentId" = v_sid and (status is null or status not in ('paid', 'canceled', 'reversed'))
     order by coalesce(nullif(month, ''), id) asc
     for update
  loop
    exit when v_available <= 0;
    if (inv.amount - inv.paid) <= 0 then continue; end if;
    v_pay := least(v_available, inv.amount - inv.paid);
    v_newpaid := inv.paid + v_pay;
    v_full := v_newpaid >= inv.amount - 0.5;
    update public.invoices
       set "paidAmount" = v_newpaid,
           status = case when v_full then 'paid' else 'partial' end,
           provider = v_provider,
           "paidAt" = case when v_full then now() else "paidAt" end
     where id = inv.id;
    v_available := v_available - v_pay;
  end loop;

  -- Avansni yozamiz (ortiqcha to'lov keyingi oyga) — kanonik kalit bilan.
  insert into public.student_credit(id, "studentId", credit, "updatedAt")
    values (v_sid, v_sid, v_available, now())
    on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();

  -- Avans harakati jurnali (izlanish uchun).
  v_delta := v_available - coalesce(v_credit, 0);
  if abs(v_delta) >= 0.5 then
    select name into v_name from public.students where id = v_sid or "studentId" = v_sid limit 1;
    insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, provider, "at")
      values (gen_random_uuid()::text, v_sid, coalesce(v_name, ''), v_delta, v_available,
              case when v_delta > 0 then 'overpay' else 'applied' end, v_provider, now());
  end if;

  return jsonb_build_object('ok', true, 'credit', v_available, 'sid', v_sid);
end $$;
grant execute on function public.apply_payment(text, numeric, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
