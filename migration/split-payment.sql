-- =====================================================================
-- split_payment — BITTA to'lovni bir necha o'quvchiga BO'LIB biriktirish.
--   Muammo: aka-uka (masalan 8-A, 5-A, 2-A) uchun ota-ona BITTA to'lov (masalan 5 000 000)
--   qiladi -> ismда 3 o'quvchi bo'lgani uchun avtomatik biriktirilmaydi (unmatched). Uni
--   qo'lда har o'quvchiga qismini biriktirish kerak.
--
--   Buni to'g'ri (balansли) qilish uchun HER o'quvchiga ALOHIDA to'lov yozuvi kerak:
--   P (real to'lov, payments bo'yicha studentId) = I+C (faktura+avans). Klient payments'ga
--   INSERT qila olmaydi (RLS) -> shu SECURITY DEFINER RPC har qismга child payment yozuvi
--   yaratadi va apply_payment bilan o'quvchiга qo'llaydi. Original to'lov 'split' deb belgilanadi
--   (P dan chiqadi, unmatched ro'yxatidan ketadi). BITTA tranzaksiya (atomik) + idempotent.
--
--   p_allocs = jsonb massiv: [{"sid":"IQ-0001","amount":1666667}, {"sid":"IQ-0002","amount":...}, ...].
--   Yig'indi = to'lov summasi bo'lishi shart (± 0.5). Ruxsat: kassir/moliya/direktor yoki server.
-- Idempotent (CREATE OR REPLACE). run-all.sql + deploy.sh'да.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/split-payment.sql
-- =====================================================================
create or replace function public.split_payment(p_pay_id text, p_provider text, p_allocs jsonb)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_claims jsonb;
  v_pay record;
  v_alloc jsonb;
  v_sid text; v_amt numeric; v_total numeric := 0; v_n int := 0;
  v_child_id text; v_res jsonb; v_results jsonb := '[]'::jsonb;
  v_pname text; v_provider text;
begin
  -- Ruxsat: to'lov biriktirish/bo'lish — kassir/moliya/direktor yoki server.
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance() or app.is_cashier()
          or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_allocs is null or jsonb_typeof(p_allocs) <> 'array' or jsonb_array_length(p_allocs) < 1 then
    return jsonb_build_object('ok', false, 'reason', 'no-allocs');
  end if;

  -- Original to'lovni qulflab olamiz (parallel bo'lishни seriyalash).
  select id, coalesce(amount,0) as amount, coalesce(status,'') as status,
         coalesce("payerName",'') as pname, coalesce(provider,'') as provider
    into v_pay from public.payments where id = p_pay_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  if v_pay.status = 'split' then return jsonb_build_object('dup', true); end if;   -- allaqachon bo'lingan
  if v_pay.status not in ('unmatched', '') then
    return jsonb_build_object('ok', false, 'reason', 'not-splittable', 'status', v_pay.status);
  end if;
  v_provider := coalesce(nullif(p_provider, ''), nullif(v_pay.provider, ''), 'click');
  v_pname := v_pay.pname;

  -- Yig'indi = to'lov summasi (± 0.5) bo'lishi SHART.
  for v_alloc in select value from jsonb_array_elements(p_allocs) loop
    v_amt := coalesce((v_alloc->>'amount')::numeric, 0);
    if v_amt <= 0 then continue; end if;
    v_total := v_total + v_amt; v_n := v_n + 1;
  end loop;
  if v_n < 1 then return jsonb_build_object('ok', false, 'reason', 'no-positive-allocs'); end if;
  if abs(v_total - v_pay.amount) > 0.5 then
    return jsonb_build_object('ok', false, 'reason', 'sum-mismatch', 'allocated', v_total, 'payment', v_pay.amount);
  end if;

  -- Har o'quvchiga: child payment yozuvi (P) + apply_payment (I+C). Bir tranzaksiyaда (atomik).
  for v_alloc in select value from jsonb_array_elements(p_allocs) loop
    v_amt := coalesce((v_alloc->>'amount')::numeric, 0);
    if v_amt <= 0 then continue; end if;
    -- kanonik studentId (audit-7 kabi: _id yoki studentId kelishi mumkin).
    select "studentId" into v_sid from public.students
      where id = (v_alloc->>'sid') or "studentId" = (v_alloc->>'sid')
      order by (id = (v_alloc->>'sid')) desc limit 1;
    v_sid := coalesce(nullif(v_sid, ''), v_alloc->>'sid');
    v_child_id := p_pay_id || ':s:' || v_sid;
    -- P: child payment yozuvi (idempotent — ON CONFLICT DO NOTHING).
    insert into public.payments(id, "studentId", provider, amount, status, "payerName", matched, "createdAt")
      values (v_child_id, v_sid, v_provider, v_amt, 'applied', v_pname, true, now())
      on conflict (id) do nothing;
    -- I+C: o'quvchi balansiga qo'llaymiz (apply_payment idempotent, guard = v_child_id).
    v_res := public.apply_payment(v_sid, v_amt, v_provider, v_child_id);
    v_results := v_results || jsonb_build_object('sid', v_sid, 'amount', v_amt, 'apply', v_res);
  end loop;

  -- Original to'lovni 'split' deb belgilaymiz (P/unmatched dan chiqadi; child yozuvlar hisoblanadi).
  update public.payments set status = 'split', matched = true where id = p_pay_id;

  return jsonb_build_object('ok', true, 'total', v_total, 'count', v_n, 'children', v_results);
end $$;
revoke all on function public.split_payment(text, text, jsonb) from public;
grant execute on function public.split_payment(text, text, jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';
