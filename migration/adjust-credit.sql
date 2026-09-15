-- =====================================================================
-- AUDIT (High A) — adjust_credit: avansni QO'LDA tuzatish ATOMIK + JURNAL bilan.
--   Muammo: admin.html «✏️ Avansni tuzatish» 2 alohida yozuv edi — student_credit.credit=nv,
--     so'ng credit_ledger addDoc. Ikkinchisi uzilса: balans o'zgargan-u nega o'zgargani
--     jurnalsiz ("pul qayoqqa ketdi") qolardi.
--   Yechim: BITTA tranzaksiya — student_credit yangilash + credit_ledger audit qatori.
--     advisory lock + p_ref idempotentlik. FAQAT direktor (UI SESSION.isAdmin bilan mos).
-- Idempotent (CREATE OR REPLACE). run-all.sql + deploy.sh'да.
--   sudo docker exec -i supabase-db psql -U postgres -d postgres < migration/adjust-credit.sql
-- =====================================================================
create or replace function public.adjust_credit(p_sid text, p_new_credit numeric, p_note text default '', p_ref text default '')
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_claims jsonb;
  v_sid text;
  v_old numeric := 0;
  v_new numeric;
  v_name text;
  v_inserted int := 0;
begin
  -- Ruxsat: qo'lda avans tuzatish — FAQAT direktor yoki server (UI SESSION.isAdmin).
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  v_new := coalesce(p_new_credit, 0);
  if v_new < 0 then return jsonb_build_object('ok', false, 'reason', 'neg'); end if;

  -- Kanonik studentId (audit-7 kabi): _id yoki studentId kelishi mumkin.
  select "studentId" into v_sid from public.students where id = p_sid or "studentId" = p_sid order by (id = p_sid) desc limit 1;
  v_sid := coalesce(nullif(v_sid, ''), p_sid);

  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || v_sid));

  -- Idempotentlik: bir xil ref bilan qayta -> {dup:true} (jurnal ikki marta yozilmaydi).
  if p_ref is not null and p_ref <> '' then
    insert into public.applied_payments(id, "studentId", amount, "createdAt")
      values ('adjcredit:' || p_ref, v_sid, v_new, now()) on conflict (id) do nothing;
    get diagnostics v_inserted = row_count;
    if v_inserted = 0 then return jsonb_build_object('dup', true, 'ref', p_ref); end if;
  end if;

  select coalesce(credit,0) into v_old from public.student_credit where id = v_sid for update;
  if not found then v_old := 0; end if;
  if abs(v_new - v_old) < 0.5 then return jsonb_build_object('ok', false, 'reason', 'no-change'); end if;

  insert into public.student_credit(id, "studentId", credit, "updatedAt")
    values (v_sid, v_sid, v_new, now())
    on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();
  select name into v_name from public.students where id = v_sid or "studentId" = v_sid limit 1;
  insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, note, "at")
    values (gen_random_uuid()::text, v_sid, coalesce(v_name,''), v_new - v_old, v_new, 'manual',
            coalesce(nullif(p_note,''), 'Admin qo''lda tuzatdi'), now());

  return jsonb_build_object('ok', true, 'old', v_old, 'new', v_new, 'studentId', v_sid);
end $$;
revoke all on function public.adjust_credit(text, numeric, text, text) from public;
grant execute on function public.adjust_credit(text, numeric, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
