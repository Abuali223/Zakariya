-- =====================================================================
-- add_credit — AVANSGA (student_credit) DELTA qo'shish: ATOMIK + idempotent + jurnal.
--
--   MUAMMO (audit M2/M4): «↻ Qayta hisoblash» narx kamayganda ortiqcha to'lovni avansga
--     client getDoc+setDoc (o'qi-o'zgartir-yoz) bilan ko'chirardi — advisory lock YO'Q:
--       M2) o'qish va yozish orasida apply_payment (webhook/kassir) avansni o'zgartirsa ->
--           stale qiymat ustiga yozilib, avans YO'QOLARDI (poyga).
--       M4) yozuv uzilsa -> invoice allaqachon kamaytirilgan, ortiqcha pul na invoysda na avansda.
--   YECHIM: apply_payment / adjust_credit kabi SECURITY DEFINER RPC — advisory lock bilan
--     seriyalaydi, SERVERDA credit = old + delta hisoblaydi (client stale o'qishi muhim emas),
--     p_ref orqali idempotent (uzilib qayta urinilsa ikki marta qo'shmaydi), credit_ledger yozadi.
--
--   DIQQAT: student_credit APPLY_PAYMENT bilan BIR XIL qatorni (id = p_sid, kanonlashtirmasdan)
--     ishlatadi — ikki xil kalit ikki avans qatori yaratib qo'ymasin.
--   Ruxsat: apply_payment bilan BIR XIL (direktor/moliya/kassir yoki server). Delta-based
--     (adjust_credit absolyut summa — recalc uchun stale-race'ni yopmaydi, shu sabab alohida).
-- Idempotent (CREATE OR REPLACE). run-all.sql + deploy.sh'da (adjust-credit yonida).
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/add-credit.sql
-- =====================================================================
create or replace function public.add_credit(p_sid text, p_delta numeric, p_reason text default 'recompute', p_note text default '', p_ref text default '')
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_claims jsonb;
  v_old numeric := 0;
  v_new numeric;
  v_name text;
  v_inserted int := 0;
begin
  -- Ruxsat: to'lov/avans oluvchilar (kassir/moliya/direktor) yoki server — apply_payment bilan bir xil.
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance() or app.is_cashier()
          or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  p_delta := coalesce(p_delta, 0);
  if abs(p_delta) < 0.5 then return jsonb_build_object('ok', false, 'reason', 'zero'); end if;

  -- Idempotentlik: bir xil ref bilan qayta chaqirilsa -> {dup:true} (avans ikki marta qo'shilmaydi).
  --   Uzilgan recalc qayta ishga tushganda invoice hali kamaytirilmagan bo'lsa -> excess qayta
  --   hisoblanadi -> add_credit QAYTA chaqiriladi -> ref to'qnashadi -> dup. applied_payments nomfazosi
  --   'addcredit:' (apply_payment id / adjust_credit 'adjcredit:' bilan to'qnashmaydi).
  if p_ref is not null and p_ref <> '' then
    insert into public.applied_payments(id, "studentId", amount, "createdAt")
      values ('addcredit:' || p_ref, p_sid, p_delta, now()) on conflict (id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted = 0 then return jsonb_build_object('dup', true, 'ref', p_ref); end if;
  end if;

  -- Shu o'quvchi bo'yicha barcha pul harakatini seriyalash (apply_payment bilan bir xil lock kaliti).
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(p_sid, '')));

  select coalesce(credit, 0) into v_old from public.student_credit where id = p_sid for update;
  if not found then v_old := 0; end if;
  v_new := v_old + p_delta;
  if v_new < 0 then v_new := 0; end if;   -- himoya: avans manfiy bo'lmasin

  insert into public.student_credit(id, "studentId", credit, "updatedAt")
    values (p_sid, p_sid, v_new, now())
    on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();

  select name into v_name from public.students where id = p_sid or "studentId" = p_sid limit 1;
  insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, note, "at")
    values (gen_random_uuid()::text, p_sid, coalesce(v_name, ''), v_new - v_old, v_new,
            coalesce(nullif(p_reason, ''), 'recompute'), coalesce(p_note, ''), now());

  return jsonb_build_object('ok', true, 'old', v_old, 'new', v_new, 'studentId', p_sid);
end $$;
revoke all on function public.add_credit(text, numeric, text, text, text) from public;
grant execute on function public.add_credit(text, numeric, text, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
