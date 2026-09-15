-- =====================================================================
-- AUDIT (High A / Medium #2) — refund_invoice: to'lovni QAYTARISH ATOMIK + IDEMPOTENT.
--   Muammo: admin.html refund oqimi 2-5 alohida atomik BO'LMAGAN yozuv edi
--     (refunds jurnal + invoice paidAmount↓ + [clawback] refunds + student_credit=0 +
--      credit_ledger). Oraliqда uzilса — invoice kamaygan-u avans clawback chala qolishi,
--     yoki retry'да IKKI marta qaytarish mumkin edi (posbon yo'q edi).
--   Yechim: BITTA tranzaksiya — invoice qulfi + advisory lock + p_ref idempotentlik
--     ('refund:'+ref applied_payments'да). refunds jurnal qatori DOIM shu tranzaksiyaда yoziladi.
--   Ruxsat: FAQAT direktor (refunds_ins = is_admin) yoki server — refund sezgir amal.
-- Idempotent (CREATE OR REPLACE). run-all.sql + deploy.sh'да.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/refund-rpc.sql
-- =====================================================================
create or replace function public.refund_invoice(
  p_target text, p_id text, p_amount numeric, p_reason text,
  p_clawback boolean default false, p_by text default '', p_ref text default '')
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_claims jsonb;
  v_inserted int := 0;
  v_inv record;
  v_sid text;
  v_sname text;
  v_month text;
  v_newpaid numeric;
  v_status text;
  v_cr numeric := 0;
  v_pname text;
begin
  -- Ruxsat: refund — FAQAT direktor (refunds jadvali ins = is_admin) yoki server.
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  p_amount := coalesce(p_amount, 0);
  if p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'amount<=0'); end if;
  if coalesce(nullif(p_reason, ''), '') = '' then return jsonb_build_object('ok', false, 'reason', 'reason-required'); end if;

  if p_target = 'invoice' then
    -- 1) Invoysни qulflab o'qib, notfound'ни posbonNI OLMASDAN qaytaramiz.
    select id, "studentId", coalesce(amount,0) as amount, coalesce("paidAmount",0) as paid,
           coalesce("studentName",'') as sname, coalesce(month,'') as month
      into v_inv from public.invoices where id = p_id for update;
    if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
    v_sid := v_inv."studentId"; v_sname := v_inv.sname; v_month := v_inv.month;

    perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));

    -- 2) IDEMPOTENTLIK POSBONI: aynan shu refund faqat BIR marta pulни harakatlantiradi.
    if p_ref is not null and p_ref <> '' then
      insert into public.applied_payments(id, "studentId", amount, "createdAt")
        values ('refund:' || p_ref, coalesce(v_sid,''), p_amount, now()) on conflict (id) do nothing;
      get diagnostics v_inserted = row_count;
      if v_inserted = 0 then return jsonb_build_object('dup', true, 'ref', p_ref); end if;
    end if;

    -- 3) refunds jurnal (pul o'zgarishi hech qachon jurnalsiz qolmasin — bitta tranzaksiyaда).
    insert into public.refunds(id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, "createdAt")
      values (gen_random_uuid()::text, 'invoice', p_id, coalesce(v_sid,''), v_sname, p_amount, p_reason, coalesce(p_by,''), v_month, now());

    -- 4) invoice paidAmount↓ (0 dan past emas) + status qayta hisoblanadi (to'liq qaytsa -> 'pending', qarz tirilaadi).
    v_newpaid := greatest(0, v_inv.paid - p_amount);
    v_status  := case when v_newpaid <= 0 then 'pending'
                      when v_newpaid >= v_inv.amount - 0.5 then 'paid'
                      else 'partial' end;
    update public.invoices set "paidAmount" = v_newpaid, status = v_status, "reversedAt" = now() where id = p_id;

    -- 5) Avans clawback (direktor belgilaган + avans bor bo'lsa): avansни 0 ga tushiramiz (o'quvchi ketyapti).
    if coalesce(p_clawback, false) and v_sid is not null and v_sid <> '' then
      select coalesce(credit,0) into v_cr from public.student_credit where id = v_sid for update;
      if found and v_cr > 0 then
        update public.student_credit set credit = 0, "updatedAt" = now() where id = v_sid;
        insert into public.refunds(id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, "createdAt")
          values (gen_random_uuid()::text, 'credit', v_sid, v_sid, v_sname, v_cr,
                  p_reason || ' · avans 0 ga tushirildi', coalesce(p_by,''), v_month, now());
        insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, note, "at")
          values (gen_random_uuid()::text, v_sid, v_sname, -v_cr, 0, 'manual', 'Refundda avans 0 ga tushirildi', now());
      end if;
    end if;
    return jsonb_build_object('ok', true, 'target', 'invoice', 'newPaid', v_newpaid, 'status', v_status,
                              'clawback', coalesce(v_cr,0), 'studentId', coalesce(v_sid,''));

  elsif p_target = 'payment' then
    -- Biriktirilmagan to'lov: 'refunded' deb belgilanadi + refunds jurnal. (Invoice/avans TEGILMAYDI.)
    if p_ref is not null and p_ref <> '' then
      insert into public.applied_payments(id, "studentId", amount, "createdAt")
        values ('refund:' || p_ref, '', p_amount, now()) on conflict (id) do nothing;
      get diagnostics v_inserted = row_count;
      if v_inserted = 0 then return jsonb_build_object('dup', true, 'ref', p_ref); end if;
    end if;
    select coalesce("payerName",'') into v_pname from public.payments where id = p_id;
    insert into public.refunds(id, target, "targetId", "studentId", "studentName", amount, reason, "byEmail", month, "createdAt")
      values (gen_random_uuid()::text, 'payment', p_id, '', coalesce(v_pname,''), p_amount, p_reason, coalesce(p_by,''), '', now());
    update public.payments set status = 'refunded' where id = p_id;
    return jsonb_build_object('ok', true, 'target', 'payment');
  end if;

  return jsonb_build_object('ok', false, 'reason', 'bad-target');
end $$;
revoke all on function public.refund_invoice(text, text, numeric, text, boolean, text, text) from public;
grant execute on function public.refund_invoice(text, text, numeric, text, boolean, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
