\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: reverse-payment.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT (High B) — reverse_payment: to'lovni QAYTARISH (Uzum reverse) ATOMIK + IDEMPOTENT.
--   Muammo: payments/index.cjs uzReverse() atomik BO'LMAGAN JS waterfall edi —
--     (1) invoice.paidAmount kamaytirish, (2) student_credit o'qish, (3) student_credit
--     kamaytirish, (4) credit_ledger yozish — 4 alohida yozuv. Oraliqда jarayon uzilса
--     yoki parallel reverse kelsa: invoice ikki marta kamayishi / avans qaytarilmasligi /
--     jurnalsiz qolishi mumkin edi (balans buziladi).
--   Yechim: apply_to_invoice / reattribute_avans kabi — BITTA tranzaksiya, invoice qulfi
--     + advisory lock + p_ref idempotentlik posboni (applied_payments'да 'reverse:'+ref).
-- Idempotent (CREATE OR REPLACE) — QAYTA ishga tushirishга xavfsiz. run-all.sql + deploy.sh'да.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================
create or replace function public.reverse_payment(p_invoice text, p_amount numeric, p_provider text, p_ref text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_claims jsonb;
  v_inv record;
  v_sid text;
  v_from_invoice numeric;
  v_from_credit numeric;
  v_newpaid numeric;
  v_status text;
  v_cr numeric := 0;
  v_name text;
  v_provider text;
  v_inserted int := 0;
  v_res jsonb;
begin
  -- Ruxsat: pulни QAYTARISH — sezgir money-move. Faqat direktor/moliya yoki server (Uzum/Click webhook).
  -- Kassir EMAS (kassir faqat to'lov QABUL qiladi, qaytarmaydi).
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if not (app.is_admin() or app.is_finance()
          or coalesce(v_claims->>'role','') = 'service_role') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  p_amount := coalesce(p_amount, 0);
  if p_amount <= 0 then return jsonb_build_object('ok', false, 'reason', 'amount<=0'); end if;
  v_provider := coalesce(nullif(p_provider, ''), 'uzum');

  -- 1) Invoysни qulflab o'qib, notfound holatини posbonNI OLMASDAN qaytaramiz
  --    (apply_to_invoice bilan bir xil xavfsiz tartib). for update -> parallel reverse'lar seriyalanadi.
  --    paid: ESKI 'paid' yozuvlarda paidAmount 0 bo'lishi mumkin -> to'langan = amount (admin.html paidOf kabi);
  --    aks holda butun summa aloqasiz avansdan qaytarib olinardi.
  --    QULF TARTIBI: AVVAL o'quvchi advisory qulfi, KEYIN qator (apply_payment / reprice_invoice bilan BIR XIL).
  --    Avval teskari (qator -> advisory) edi: bir vaqtda kelgan apply_payment/qayta hisoblash bilan o'zaro
  --    qulflanish (40P01) Uzum/Click so'rovini xato bilan uzardi.
  select "studentId" into v_sid from public.invoices where id = p_invoice;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  -- 2) O'quvchi bo'yicha boshqa to'lovlar bilan seriyalash (apply_payment/apply_to_invoice bilan bir xil advisory lock).
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || coalesce(v_sid, '')));
  select id, "studentId", coalesce(amount,0) as amount,
         case when status = 'paid' then greatest(coalesce("paidAmount",0), coalesce(amount,0)) else coalesce("paidAmount",0) end as paid, status
    into v_inv from public.invoices where id = p_invoice for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'notfound'); end if;
  if coalesce(v_inv."studentId",'') <> coalesce(v_sid,'') then   -- oraliqda kalit o'zgargan — chaqiruvchi qayta urinadi
    return jsonb_build_object('ok', false, 'error', 'retry');
  end if;

  -- 3) IDEMPOTENTLIK POSBONI: aynan shu reverse faqat BIR marta pulни harakatlantiradi. Bir xil
  --    p_ref bilan qayta chaqirilса (webhook retry / crash-recovery) -> {dup:true}, invoice/avans
  --    IKKI marta kamaymaydi. applied_payments'da 'reverse:'+ref namespace (apply bilan to'qnashmaydi).
  if p_ref is not null and p_ref <> '' then
    insert into public.applied_payments(id, "studentId", amount, "createdAt")
      values ('reverse:' || p_ref, coalesce(v_sid,''), p_amount, now())
      on conflict (id) do nothing;
    get diagnostics v_inserted = row_count;
    -- Takroriy chaqiruv: BIRINCHI natija ham qaytadi (masalan «unrecovered») — provayder qayta yuborganda yoki javob
    --   yo'qolganda «qo'lda qaytarish» belgisi tushib qolmasin.
    if v_inserted = 0 then
      return coalesce((select ap.result from public.applied_payments ap where ap.id = 'reverse:' || p_ref), '{}'::jsonb)
             || jsonb_build_object('dup', true, 'ref', p_ref);
    end if;
  end if;

  -- 4) AYNAN shu tranzaksiya summasini ayiramiz (boshqa to'lovlar saqlanadi): paidAmount'dan
  --    min(summa, paid), qolган ortiqcha (avansга o'tган qism) student_credit'dan qaytariladi.
  v_from_invoice := least(p_amount, v_inv.paid);
  v_from_credit  := greatest(0, p_amount - v_from_invoice);
  v_newpaid := greatest(0, v_inv.paid - v_from_invoice);
  -- To'liq qaytarilsa -> 'pending' (NE 'reversed'): refund_invoice kabi QARZ TIRILADI (ota-ona pulni
  --   qaytarib oldi, lekin o'qish haqi hali qarzda — aks holda moliya hamma joyida qarz=0 ko'rib,
  --   undiruvni to'xtatardi). «reversedAt» belgisi audit sifatida saqlanadi.
  --   BEKOR QILINGAN faktura (masalan holat bo'yicha '[holat]' bekor — puli avansga o'tgan) bekorligicha qoladi:
  --   aks holda qaytarishdan keyin to'liq narxli «kutilmoqda» qarz bo'lib tirilardi (pul esa avansdan olingan).
  v_status  := case when v_inv.status in ('canceled','reversed') then v_inv.status
                    when v_newpaid <= 0 then 'pending'
                    when v_newpaid >= v_inv.amount - 0.5 then 'paid'
                    else 'partial' end;
  update public.invoices
     set "paidAmount" = v_newpaid, status = v_status, "reversedAt" = now()
   where id = p_invoice;

  -- 5) Avansга o'tган ortiqcha qismни qaytarib olamiz (avans manfiy bo'lmaydi: max(0, …)).
  if v_from_credit > 0 and v_sid is not null and v_sid <> '' then
    select coalesce(credit,0) into v_cr from public.student_credit where id = v_sid for update;
    if not found then v_cr := 0; end if;
    insert into public.student_credit(id, "studentId", credit, "updatedAt")
      values (v_sid, v_sid, greatest(0, v_cr - v_from_credit), now())
      on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();
    select name into v_name from public.students where id = v_sid or "studentId" = v_sid limit 1;
    -- delta = HAQIQATDA olib tashlangan avans (= least(mavjud, qaytariladigan)); aks holda avans
    --   allaqachon (qisman) sarflangan bo'lsa, delta balanceAfter bilan mos kelmay, ledger yig'indisi buziladi.
    insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, provider, "at")
      values (gen_random_uuid()::text, v_sid, coalesce(v_name,''), -least(v_cr, v_from_credit),
              greatest(0, v_cr - v_from_credit), 'reversed', v_provider, now());
  end if;

  -- unrecovered: avansdan qaytarib olinishi kerak bo'lgan, lekin avans allaqachon sarflangani uchun OLINMAGAN qism
  --   (chaqiruvchi — pay-server — buni «qo'lda qaytarish» navbatiga qo'yadi; jim yo'qolmasin).
  v_res := jsonb_build_object('ok', true, 'status', v_status, 'fromInvoice', v_from_invoice,
                            'fromCredit', v_from_credit, 'newPaid', v_newpaid, 'studentId', coalesce(v_sid,''),
                            'unrecovered', greatest(0, v_from_credit - (case when v_sid is not null and v_sid <> '' then v_cr else 0 end)));
  if p_ref is not null and p_ref <> '' then
    update public.applied_payments set result = v_res where id = 'reverse:' || p_ref;
  end if;
  return v_res;
end $$;
revoke all on function public.reverse_payment(text, numeric, text, text) from public;
grant execute on function public.reverse_payment(text, numeric, text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
