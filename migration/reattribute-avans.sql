-- =====================================================================
-- reattribute_avans — noto'g'ri o'quvchiga tushgan AVANSNI to'g'risiga ko'chirish.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/reattribute-avans.sql
-- Idempotent (CREATE OR REPLACE) — funksiyani o'rnatadi. run-all.sql + deploy.sh'да.
--
-- QACHON KERAK: bir xil telefonли to'lovlar noto'g'ri bir bolага 'applied' bo'lib,
--   uning avansига o'tirib qolganда. Bu funksiya manba avansdan p_amount ni AYIRADI
--   va uni to'g'ri o'quvchiга apply_payment orqali QO'LLAYDI (fakturasini yopadi,
--   ortig'i o'sha bolaning avansига). Har ikkala harakat credit_ledger'ga yoziladi.
--
--   ★ Money-move — faqat DIREKTOR/MOLIYA yoki server (service_role). BITTA tranzaksiya
--     (atomik): apply_payment xato bersa — manbadan ayirish ham bekor bo'ladi.
--
--   Ishlatish (admin TASDIQLAGACH, har biriга alohida):
--     select public.reattribute_avans('IQ-0259','IQ-0256', 2610000, 'Oybekov Muhammadulloh 2B');
-- =====================================================================
create or replace function public.reattribute_avans(p_from text, p_to text, p_amount numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_from text; v_to text;
  v_from_credit numeric := 0;
  v_fname text;
  v_claims jsonb;
  v_res jsonb;
begin
  -- Ruxsat: pul ko'chirish — faqat direktor/moliya yoki server.
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance()
          or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  p_amount := coalesce(p_amount, 0);
  if p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'amount<=0'); end if;

  -- Kanonik studentId (audit-7 kabi): _id yoki studentId kelishi mumkin.
  select "studentId" into v_from from public.students where id = p_from or "studentId" = p_from order by (id = p_from) desc limit 1;
  v_from := coalesce(nullif(v_from, ''), p_from);
  select "studentId" into v_to   from public.students where id = p_to   or "studentId" = p_to   order by (id = p_to) desc limit 1;
  v_to := coalesce(nullif(v_to, ''), p_to);
  if v_from = v_to then return jsonb_build_object('ok', false, 'reason', 'from=to'); end if;

  -- Manba avansини qulflab tekshiramiz.
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || v_from));
  select coalesce(credit, 0) into v_from_credit from public.student_credit where id = v_from for update;
  if coalesce(v_from_credit, 0) < p_amount - 0.5 then
    return jsonb_build_object('ok', false, 'reason', 'insufficient', 'have', coalesce(v_from_credit, 0), 'need', p_amount);
  end if;

  -- 1) Manbadan AYIRAMIZ + jurnal.
  update public.student_credit set credit = credit - p_amount, "updatedAt" = now() where id = v_from;
  select name into v_fname from public.students where id = v_from or "studentId" = v_from limit 1;
  insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, provider, "at")
    values (gen_random_uuid()::text, v_from, coalesce(v_fname, ''), -p_amount, v_from_credit - p_amount,
            'reattribute-out' || case when coalesce(p_note,'') <> '' then ' → ' || p_to || ' (' || p_note || ')' else ' → ' || p_to end,
            'reattr', now());

  -- 2) To'g'ri o'quvchига QO'LLAYMIZ (fakturasi + ortiqcha avans). apply_payment ichki
  --    ravishda kanonik kalitga keltiradi, jurnal ham yozadi.
  v_res := public.apply_payment(v_to, p_amount, 'reattr',
             'reattr-' || v_from || '-' || v_to || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 10));

  return jsonb_build_object('ok', true, 'from', v_from, 'to', v_to, 'amount', p_amount, 'target', v_res);
end $$;
grant execute on function public.reattribute_avans(text, text, numeric, text) to authenticated, service_role;

notify pgrst, 'reload schema';
