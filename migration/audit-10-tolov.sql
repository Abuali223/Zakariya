\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-10-tolov.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-10 (to'liq audit, 2026-11-18) — TO'LOVLAR: pul yozuvi faqat ishonchli yo'ldan, ortiqcha pul darhol qarzga.
--
-- 1) TO'LOV QATORI (payments) — to'g'ridan-to'g'ri yozish (A4-01).
--    Muammo: pay_ins / pay_upd kassir va moliya rollariga ochiq edi (cashier-role.sql). Kassir PostgREST orqali (tugmasiz)
--    {id:'click_…', provider:'click', status:'unmatched'} yozib assign_payment bilan biriktirsa — naqd pulni olib qolib, uni
--    «Click» tushumi qilib ko'rsatardi (kassa sanog'i ham, «🔍 Moliya tekshiruvi» ham mos chiqardi); «pending» qator + apply_payment
--    bilan qarzni pulsiz yopardi; qabul qilingan naqd to'lovni 100 000 / «click» / «canceled» qilib, kassa hisobotidan pul yo'qotardi.
--    Yechim (uch qavat):
--      * policy: to'g'ridan-to'g'ri yozish — faqat Direktor (cashier-role.sql: pay_ins / pay_upd; posbon applied_payments mijozga
--        allaqachon yopiq — audit-8.sql);
--      * RF-04: apply_payment / apply_to_invoice musbat summani faqat ichki bayroq (record_manual_payment, reattribute_avans,
--        kassa — iqror.money_rpc; assign_payment / split_payment — iqror.assign_rpc), Direktor yoki server bilan qabul qiladi
--        (audit-7.sql, audit-5.sql). «Shu payId bilan qator bor» sharti olib tashlandi: Click qatori server tomonidan boshqa
--        posbon kalitida (click_trans_id) qo'llanadi — uni qayta qo'llab, boshqa o'quvchining qarzini pulsiz yopish mumkin edi;
--      * shu fayldagi trigger (app.pay_direct_guard): REST orqali kelgan (authenticated / anon) yozuv — kim bo'lishidan qat'i nazar,
--        policy keyinchalik yana kengaytirilsa ham — yangi qator yarata olmaydi va pul / tushum ustunlarini o'zgartira olmaydi. Faqat
--        Direktorning sahifadagi ikki amali qoladi: qo'llanmagan (fantom / xato) yozuvni «🚫 Bekor» (holat → 'canceled') va
--        qaytarilgan to'lovga «✓ Bajarildi» belgisi (raw; tushum kuni o'zgarmasa) — ikkalasi setDoc (upsert). To'lovchi ismi /
--        telefoni / sinfini tuzatish ham mumkin (pulga ta'sir qilmaydi). SECURITY DEFINER pul funksiyalari (ular ichida current_user —
--        funksiya egasi), server (service_role) va migratsiya — tekshiruvsiz.
--
-- 2) HISOB-FAKTURA (invoices) — Direktordan boshqasi «to'landi» qila olmaydi (A4-02).
--    Muammo: moliya menejeri / g'aznachi reprice_invoice bilan fakturani 1 yoki 0 so'mga tushirardi (narx va chegirma maydonlari
--    mijozdan; D1 tasdig'isiz), yoki to'g'ridan-to'g'ri {status:'paid', paidAmount:…} yozib qarzni to'lovsiz yopardi.
--    Yechim: reprice_invoice — faqat Direktor / server (invoice-guards.sql); inv_upd — faqat Direktor (audit-9.sql); shu fayldagi
--    trigger (app.inv_paid_guard): Direktordan boshqa REST yozuvi to'lov holatini (paidAmount / status / paidAt) o'zgartirmaydi,
--    yaratayotgan fakturasi (moliya menejeri — «invoiceCreators» sozlamasi bilan) to'lanmagan holda bo'ladi (0 so'mlik — «to'landi»,
--    «Hisob-fakturalar yaratish» bilan bir xil; chegirma tasdig'i — discount-approval.sql).
--
-- 3) AVANS DARHOL QARZGA (A4-03).
--    Muammo: «↻ Qayta hisoblash» (holat bo'yicha bekor / narx kamaydi), Click/Uzum aniq to'lovining ortig'i (apply_to_invoice) va ketgan
--    o'quvchining kasal kunlari (sick_note_refund) pulni avansga qo'yib, oilaning boshqa ochiq oyiga qo'llamasdi — keyingi
--    «Hisob-fakturalar yaratish»gacha (bir oygacha) qarz SMS'i, «Qarzdorlar» va kabinet to'langan qarzni ko'rsatardi.
--    Yechim: app.credit_sweep — shu funksiyalar avansni SHU tranzaksiyada apply_payment(sid, 0, 'credit', null) bilan (odatiy
--    waterfall) qo'llaydi. «Hisob-fakturalar yaratish»dagi qoida (admin.html phantomSids) saqlanadi: o'quvchining ochiq fakturasi
--    holat bo'yicha «kerak emas» oyga tushsa (app.stu_bill_skip = billingInterval: sinov, hali boshlanmagan, sanasiz muzlatilgan /
--    chiqqan — arxivdagi o'quvchi ham, to'xtatilgandan keyingi oy, butun oy to'xtatilgan) — avans TURADI, fantom fakturaga sarflanmaydi.
--
-- Idempotent — QAYTA ishga tushirishga xavfsiz (create or replace, drop trigger if exists; ma'lumot o'zgartirilmaydi).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- ---------- 1) payments: REST orqali to'g'ridan-to'g'ri yozuv ----------
--   SECURITY INVOKER (ataylab): current_user — kim yozayotgani. PostgREST so'rovi — 'authenticated' / 'anon'; SECURITY DEFINER pul
--   funksiyasi ichidagi yozuv — funksiya egasi (record_manual_payment, assign_payment, split_payment, refund_invoice, kassa …).
--   Nomi «trg_pay_…»: trg_fin_server_ts, trg_fin_zlock, trg_kassa_pay_guard dan KEYIN ishlaydi (alifbo tartibi) — ularning aniq
--   xabarlari (fin:locked, kassa:…) avvalgidek birinchi chiqadi.
create or replace function app.pay_direct_guard() returns trigger
language plpgsql security invoker set search_path = public, app, pg_temp as $$
declare v_free text[] := array['raw', 'payerName', 'payerPhone', 'payerClass', 'status', 'statusAt'];
begin
  if current_user::text not in ('authenticated', 'anon') or app.is_system() then return new; end if;
  if tg_op = 'INSERT' then
    -- Sahifaning setDoc'i — upsert (INSERT … ON CONFLICT (id) DO UPDATE): mavjud qatorga taklif qilingan qator shu yerdan o'tadi
    --   (qo'shilmaydi), o'zgarishning o'zi — pastdagi UPDATE tekshiruvida. Taklifda pul maydonlari bo'lsa — yangi qator deb rad.
    if new.amount is null and new.provider is null and new."studentId" is null and new."invoiceId" is null
       and exists (select 1 from public.payments p where p.id = new.id) then
      return new;
    end if;
    raise exception 'To''lov yozuvi faqat «💵 To''lov», «Biriktirish» / «Bo''lish» yoki to''lov serveri orqali yaratiladi — to''g''ridan-to''g''ri yozib bo''lmaydi'
      using errcode = '42501', hint = 'pay:direct';
  end if;
  if not app.is_admin() then
    raise exception 'To''lov yozuvini faqat to''lov funksiyalari o''zgartiradi' using errcode = '42501', hint = 'pay:direct';
  end if;
  -- Pul / tushumga ta'sir qiluvchi barcha ustunlar (summa, kanal, o'quvchi, faktura, biriktirish, provayder kalitlari, kiritilgan vaqt,
  --   kassa havolasi …) — o'zgarmaydi; ro'yxatdan tashqari yangi ustun ham avtomatik shu qoidaga tushadi.
  if (to_jsonb(new) - v_free) is distinct from (to_jsonb(old) - v_free)
     or app.pay_day(new."createdAt", new.raw) is distinct from app.pay_day(old."createdAt", old.raw) then
    raise exception 'To''lov summasi, kanali, o''quvchisi, kuni va boshqa pul maydonlari to''g''ridan-to''g''ri o''zgartirilmaydi (noto''g''ri to''lov — «↩ Qaytarish» yoki fakturani qayta hisoblash orqali)'
      using errcode = '42501', hint = 'pay:direct';
  end if;
  -- Holat: faqat fakturaga QO'LLANMAGAN (fantom / xato / biriktirilmagan) yozuvni bekor qilish — sahifadagi «🚫 Bekor» bilan bir xil.
  --   NULL ham holat o'zgarishi (avval NULL'da shart jim o'tib ketardi — 'prepared' Click yozuvi NULL qilinib, kassir uni «tushum» sifatida
  --   biriktira olardi; mustaqil tekshiruv 2-raund).
  if new.status is distinct from old.status
     and (coalesce(new.status, '') <> 'canceled'
          or coalesce(old.status, '') in ('applied', 'confirmed', 'paid', 'split', 'refunded', 'reversed', 'canceled')) then
    raise exception 'To''lov holatini to''g''ridan-to''g''ri faqat qo''llanmagan yozuv uchun «bekor» qilish mumkin (qo''llangan to''lov — «↩ Qaytarish» orqali)'
      using errcode = '42501', hint = 'pay:direct';
  end if;
  return new;
end $$;
revoke all on function app.pay_direct_guard() from public, anon, authenticated;
drop trigger if exists trg_pay_direct_guard on public.payments;
create trigger trg_pay_direct_guard before insert or update on public.payments for each row execute function app.pay_direct_guard();

-- ---------- 2) invoices: Direktordan boshqasining REST yozuvi to'lov holatiga tegmaydi ----------
--   SECURITY INVOKER — yuqoridagi kabi. Nomi «trg_invoice_z…»: chegirma / bonus / kasal kun himoyalaridan KEYIN ishlaydi.
create or replace function app.inv_paid_guard() returns trigger
language plpgsql security invoker set search_path = public, app, pg_temp as $$
begin
  if current_user::text not in ('authenticated', 'anon') or app.is_system() or app.is_admin() then return new; end if;
  if tg_op = 'INSERT' then
    -- 0 so'mlik «to'langan» faktura — faqat SABABI bilan (grant, foizli chegirma, tasdiq ishorasi, monitoring bonusi, tavsiya, kasal
    --   kunlar — generatsiyaning to'liq qoplangan holati); sababsiz 0 so'm — o'quvchi-oyni nolga tushirish (A4-02, 2-raund). Har shart
    --   coalesce bilan: NULL ustun (approvalRefs yo'q) butun shartni NULL qilib, qo'riqchini jim o'tkazib yubormasin.
    if coalesce(new."paidAmount", 0) <> 0
       or not (coalesce(new.status, '') in ('', 'pending')
               or (new.status = 'paid' and coalesce(new.amount, 0) = 0
                   and (coalesce(new."isGrant", false) or coalesce(new."pctApplied", 0) > 0
                        or coalesce(jsonb_typeof(new."approvalRefs") = 'array' and jsonb_array_length(new."approvalRefs") > 0, false)
                        or coalesce(new."bonusRef", '') <> ''
                        or coalesce(jsonb_typeof(new."referralUsedIds") = 'array' and jsonb_array_length(new."referralUsedIds") > 0, false)
                        or coalesce(new."sickAmount", 0) > 0))) then
      raise exception 'Hisob-faktura to''lanmagan holda yaratiladi — to''lov faqat «💵 To''lov» yoki to''lov serveri orqali yoziladi'
        using errcode = '42501', hint = 'inv:paid';
    end if;
    return new;
  end if;
  if new."paidAmount" is distinct from old."paidAmount" or new.status is distinct from old.status or new."paidAt" is distinct from old."paidAt" then
    raise exception 'Hisob-fakturaning to''lov holatini faqat Direktor yoki to''lov funksiyalari o''zgartiradi' using errcode = '42501', hint = 'inv:paid';
  end if;
  return new;
end $$;
revoke all on function app.inv_paid_guard() from public, anon, authenticated;
drop trigger if exists trg_invoice_zpaid_guard on public.invoices;
create trigger trg_invoice_zpaid_guard before insert or update on public.invoices for each row execute function app.inv_paid_guard();

-- ---------- 3) Avans darhol ochiq qarzga ----------
-- Matn ko'rinishidagi sana ('YYYY-MM-DD…') — xavfsiz o'qish (noto'g'ri bo'lsa null; admin.html _saDate kabi).
create or replace function app.stu_text_day(p text) returns date
language plpgsql immutable set search_path = public, app, pg_temp as $$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}' then return null; end if;
  begin return left(p, 10)::date; exception when others then return null; end;
end $$;
revoke all on function app.stu_text_day(text) from public, anon, authenticated;

-- O'quvchi shu oy (p_month 'YYYY-MM') uchun hisob-faktura TALAB QILMAYDIMI — admin.html billingInterval() ning «skip» xulosasi bilan bir
--   xil: trial | future | nodate | stopped | empty | paused; talab qilsa — null. Ish kunlari — Dush–Juma (o'quvchida shaxsiy ish kuni yo'q:
--   personRules → SA_WORKDAYS). Shu funksiya o'zgarsa — billingInterval ham (va aksincha).
create or replace function app.stu_bill_skip(p_status text, p_active text, p_stop text, p_pauses jsonb, p_month text)
returns text language plpgsql stable set search_path = public, app, pg_temp as $$
declare v_st text := coalesce(nullif(p_status, ''), 'faol'); v_ms date; v_me date; v_af date; v_sf date; v_stop boolean;
        v_start date; v_end date; v_work int; v_paused int;
begin
  if coalesce(p_month, '') !~ '^\d{4}-\d{2}' then return null; end if;
  begin v_ms := (left(p_month, 7) || '-01')::date; exception when others then return null; end;
  v_me := (v_ms + interval '1 month')::date - 1;
  if v_st = 'sinov' then return 'trial'; end if;
  v_af := app.stu_text_day(p_active); v_sf := app.stu_text_day(p_stop);
  if v_af > v_me then return 'future'; end if;
  v_stop := v_st in ('muzlatilgan', 'chiqdi');
  if v_stop and v_sf is null then return 'nodate'; end if;
  if v_stop and v_sf < v_ms then return 'stopped'; end if;
  v_start := greatest(v_ms, coalesce(v_af, v_ms));
  v_end := case when v_stop and v_sf < v_me then v_sf else v_me end;
  if v_start > v_end then return 'empty'; end if;
  -- To'xtatilgan davrlar (pauses: {from, to}) oraliqdagi BARCHA ish kunini qoplasa — butun oy to'xtatilgan.
  select count(*), count(*) filter (where exists (
           select 1 from jsonb_array_elements(case when jsonb_typeof(p_pauses) = 'array' then p_pauses else '[]'::jsonb end) p
            where jsonb_typeof(p) = 'object' and app.stu_text_day(p ->> 'from') <= app.stu_text_day(p ->> 'to')
              and g.d::date between app.stu_text_day(p ->> 'from') and app.stu_text_day(p ->> 'to')))
    into v_work, v_paused
    from generate_series(v_start, v_end, interval '1 day') g(d)
   where extract(isodow from g.d) <= 5;
  if v_paused > 0 and v_work - v_paused <= 0 then return 'paused'; end if;
  return null;
end $$;
revoke all on function app.stu_bill_skip(text, text, text, jsonb, text) from public, anon, authenticated;

-- O'quvchi avansini DARHOL eng eski ochiq fakturalariga qo'llash (apply_payment(sid, 0, 'credit', null) — odatiy waterfall, chaqiruvchi
--   tranzaksiyasida; o'quvchi navbat qulfi qayta kiriladi). Ochiq fakturalaridan birortasi holat bo'yicha «kerak emas» oyga tushsa — avans
--   TURADI (admin.html «Hisob-fakturalar yaratish»dagi phantomSids qoidasi): fantom fakturaga «yeb» qo'yilmasin, Direktor «↻ Qayta
--   hisoblash» yoki sana bilan holatni aniqlaguncha. Qo'llandimi — qaytaradi. Faqat pul funksiyalari ichidan (mijozga yopiq).
create or replace function app.credit_sweep(p_sid text) returns boolean
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare s record;
begin
  if coalesce(p_sid, '') = '' then return false; end if;
  if not exists (select 1 from public.student_credit c where c.id = p_sid and coalesce(c.credit, 0) >= 0.5) then return false; end if;
  select st."payStatus", st."activeFrom", st."stopFrom", st.pauses into s from public.students st
   where st."studentId" = p_sid or st.id = p_sid order by (st."studentId" = p_sid) desc limit 1;
  if found and exists (select 1 from public.invoices i
                        where i."studentId" = p_sid and (i.status is null or i.status not in ('paid', 'canceled', 'reversed'))
                          and app.stu_bill_skip(s."payStatus", s."activeFrom", s."stopFrom", s.pauses, i.month) is not null) then
    return false;
  end if;
  perform public.apply_payment(p_sid, 0, 'credit', null);
  return true;
end $$;
revoke all on function app.credit_sweep(text) from public, anon, authenticated;

notify pgrst, 'reload schema';
