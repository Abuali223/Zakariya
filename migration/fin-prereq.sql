\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-prereq.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-prereq.sql — MOLIYA ISH REJASI, 0-BOSQICH (docs/moliya/buxgalteriya-ish-reja.md: F0.12–F0.16).
--   Kassa hujjatlari (1a) shu poydevor ustiga quriladi. Hammasi idempotent va mavjud ma'lumotni o'zgartirmaydi.
--
--   F0.12  YAGONA «tushgan pul» ta'rifi — admin.html isCashPay()/payDay() bilan AYNAN bir xil (JS↔SQL moslik testi bor):
--          app.counts_as_receipt(...)  — pul TUSHGANmi (holat, avans ko'chirmasi 'reattr', bo'lingan to'lov bolalari ':s:');
--          app.pay_day(createdAt, raw) — kassa KUNI (qo'lda to'lovda kassir tanlagan «Sana», kiritilgan kundan 31 kungacha orqaga);
--          app.fin_receipts(from, to)  — shu kunlarda tushgan to'lovlar ro'yxati. director_daily (telegram.sql) shundan foydalanadi.
--   F0.13  Indekslar: payments(createdAt / status / studentId), staff_advances(month), expenses(date).
--   F0.14  SERVER VAQTI: payments / expenses / salary_payments / staff_advances / refunds da "createdAt" (expenses'da
--          "updatedAt" ham) mijoz (brauzer) soatidan emas — serverdan; UPDATE da "createdAt" o'zgarmaydi. Tizim (server,
--          webhook, migratsiya — app.is_system()) yozuvlari tegilmaydi (Click prepare vaqti saqlanadi). payments."statusAt" —
--          holat oxirgi marta o'zgargan server vaqti.
--   F0.15  public.record_manual_payment(...) — qo'lda to'lov (naqd / bank / terminal / Uzum) BITTA tranzaksiyada: payments
--          qatori + apply_payment + holat 'applied'. Avval 3 ta alohida so'rov edi (yarim yo'lda uzilsa «pending» yetim qator
--          qolib, kassa hisobotidan tushib qolardi). Idempotent: bir xil payId qayta yuborilsa — ikki marta qo'llanmaydi.
--   F0.16  HUQUQLAR I:
--          RF-01 kassir xarajat yozmaydi, o'zgartirmaydi, o'chirmaydi (UI'da ham yo'q edi — faqat baza ochiq edi);
--          RF-02 kassir xodim avansini to'g'ridan-to'g'ri yozmaydi (UI — «Buxgalteriya», Moliya/Direktor);
--          RF-03 add_credit musbat summa — faqat Direktor va server (add-credit.sql o'zida);
--          RF-05 O'IBDO' xarajat yozmaydi;
--          RF-06 qaytarish va maosh berishda «kim» (byUid / byEmail) — server qo'yadi (mijoz yuborgani emas);
--          RF-07 credit_ledger (avans jurnali) — faqat qo'shiladi, o'chirilmaydi; student_credit'ga to'g'ridan-to'g'ri yozish —
--                faqat Direktor (avans faqat jurnal yozadigan RPC'lar orqali o'zgaradi);
--          RF-04 (ko'rik, oldinga surildi) apply_payment / apply_to_invoice musbat summani faqat payments qatori, ichki pul
--                RPC'si bayrog'i (iqror.money_rpc), Direktor yoki server bilan qabul qiladi (audit-7.sql, audit-5.sql o'zida);
--          NaN / Infinity / bema'ni katta summa barcha pul RPC'larida rad etiladi.
-- =====================================================================

-- ---------- Ustunlar ----------
alter table public.payments        add column if not exists "statusAt" timestamptz;
alter table public.refunds         add column if not exists "byUid" text;
alter table public.salary_payments add column if not exists "byUid" text;

-- ---------- F0.13 indekslar ----------
create index if not exists payments_created_idx on public.payments ("createdAt");
create index if not exists payments_status_idx  on public.payments (status);
create index if not exists payments_student_idx on public.payments ("studentId");
create index if not exists staff_advances_month_idx on public.staff_advances (month);
create index if not exists expenses_date_idx on public.expenses (date);

-- ---------- F0.12 yagona «tushgan pul» ta'rifi ----------
-- admin.html: CASH_PAY_ST + isCashPay(p). Pul tushgan holatlar; 'reattr' (avansni o'quvchilar orasida ko'chirish) va bo'lingan
--   to'lovning bolalari (id ichida ':s:') — yangi pul emas (ota qator 'split' bir marta hisoblanadi); summa > 0.
create or replace function app.counts_as_receipt(p_id text, p_status text, p_provider text, p_amount numeric)
returns boolean language sql immutable set search_path = public, app, pg_temp as $$
  select coalesce(p_status, '') in ('applied', 'paid', 'confirmed', 'unmatched', 'split')
     and coalesce(p_provider, '') <> 'reattr'
     and strpos(coalesce(p_id, ''), ':s:') = 0
     and coalesce(p_amount, 0) > 0
     and p_amount <> 'NaN'::numeric   -- JS: (Number(NaN)||0) > 0 — false
$$;
-- admin.html: payDay(p). Kassa kuni = Toshkent sanasi (createdAt); qo'lda to'lovda (raw.manual) kassir tanlagan raw.date —
--   faqat [kiritilgan kun − 31 kun, kiritilgan kun] ichida (kelajak yoki juda eski sana — kiritilgan kun).
create or replace function app.pay_day(p_created timestamptz, p_raw jsonb)
returns date language plpgsql stable set search_path = public, app, pg_temp as $$
declare c date; r text; lo date;
begin
  if p_created is null then return null; end if;
  c := (p_created at time zone 'Asia/Tashkent')::date;
  if p_raw is null or coalesce(p_raw -> 'manual', 'false'::jsonb) in ('false'::jsonb, 'null'::jsonb, '0'::jsonb, '""'::jsonb) then return c; end if;
  r := coalesce(p_raw ->> 'date', '');
  if r !~ '^\d{4}-\d{2}-\d{2}$' then return c; end if;
  lo := c - 31;
  if r <= to_char(c, 'YYYY-MM-DD') and r >= to_char(lo, 'YYYY-MM-DD') then
    begin return r::date; exception when others then return c; end;
  end if;
  return c;
end $$;
-- Shu kunlarda (Toshkent, kassa kuni bo'yicha) TUSHGAN to'lovlar. pay_day ≤ kiritilgan kun ≤ pay_day + 31 bo'lgani uchun
--   createdAt oralig'i [from, to + 32) — indeksdan foydalanadi. Ichki yordamchi (mijozga ochiq emas).
create or replace function app.fin_receipts(p_from date, p_to date)
returns table(id text, "studentId" text, provider text, amount numeric, status text, day date, "createdDay" date)
language sql stable security definer set search_path = public, app, pg_temp as $$
  select p.id, p."studentId", coalesce(nullif(p.provider, ''), 'boshqa'), p.amount, p.status,
         app.pay_day(p."createdAt", p.raw), (p."createdAt" at time zone 'Asia/Tashkent')::date
    from public.payments p
   where p."createdAt" >= (p_from::timestamp at time zone 'Asia/Tashkent')
     and p."createdAt" <  ((p_to + 32)::timestamp at time zone 'Asia/Tashkent')
     and app.counts_as_receipt(p.id, p.status, p.provider, p.amount)
     and app.pay_day(p."createdAt", p.raw) between p_from and p_to
$$;
revoke all on function app.fin_receipts(date, date) from public, anon, authenticated;

-- ---------- Moliya soati ----------
-- Jonli bazada DOIM now(). Faqat sinov bazalari va o'quv stendida (baza nomi «fx_…», «…sinov…», «…test…») app.fin_clock qatori
--   orqali siljitiladi (kun almashishini mashq qilish, yil chegarasi sinovlari). Jonli bazada bu jadvalga yozib bo'lmaydi va
--   yozilgan bo'lsa ham e'tiborga olinmaydi.
create table if not exists app.fin_clock (id int primary key check (id = 1), t timestamptz);
revoke all on table app.fin_clock from public, anon, authenticated;
create or replace function app.fin_clock_allowed() returns boolean
language sql stable set search_path = public, app, pg_temp as $$
  select current_database() ~ '(^fx_|sinov|test)'
$$;
create or replace function app.fin_clock_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if not app.fin_clock_allowed() then
    raise exception 'Test soati faqat sinov bazasida ishlatiladi (jonli bazada emas)' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists trg_fin_clock_guard on app.fin_clock;
create trigger trg_fin_clock_guard before insert or update on app.fin_clock for each row execute function app.fin_clock_guard();
create or replace function app.fin_now() returns timestamptz
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when app.fin_clock_allowed() then coalesce((select c.t from app.fin_clock c where c.id = 1), now()) else now() end
$$;
create or replace function app.fin_today() returns date
language sql stable security definer set search_path = public, app, pg_temp as $$
  select (app.fin_now() at time zone 'Asia/Tashkent')::date
$$;
revoke all on function app.fin_clock_allowed() from public, anon, authenticated;
revoke all on function app.fin_clock_guard() from public, anon, authenticated;
revoke all on function app.fin_now() from public, anon, authenticated;
revoke all on function app.fin_today() from public, anon, authenticated;

-- ---------- F0.14 server vaqti + RF-06 «kim» ----------
create or replace function app.fin_server_ts() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_sys boolean := app.is_system(); v_uid text; v_email text;
begin
  if tg_op = 'INSERT' then
    if not v_sys or new."createdAt" is null then new."createdAt" := app.fin_now(); end if;
  elsif not v_sys then
    new."createdAt" := old."createdAt";
  end if;
  if tg_table_name = 'payments' then
    if tg_op = 'INSERT' or new.status is distinct from old.status then new."statusAt" := app.fin_now();
    else new."statusAt" := old."statusAt"; end if;
  elsif tg_table_name = 'expenses' then
    if not v_sys or new."updatedAt" is null then new."updatedAt" := app.fin_now(); end if;
  elsif tg_table_name in ('refunds', 'salary_payments') then
    if tg_op = 'INSERT' then
      if not v_sys then
        v_uid := app.uid();
        select nullif(u.email, '') into v_email from public.users u where u.id = v_uid;
        new."byUid" := v_uid;
        new."byEmail" := coalesce(v_email, 'uid:' || coalesce(v_uid, '?'));
      end if;
    elsif not v_sys then
      new."byUid" := old."byUid"; new."byEmail" := old."byEmail";
    end if;
  end if;
  return new;
end $$;
revoke all on function app.fin_server_ts() from public, anon, authenticated;
do $$ declare t text; begin
  foreach t in array array['payments', 'expenses', 'salary_payments', 'staff_advances', 'refunds'] loop
    execute format('drop trigger if exists trg_fin_server_ts on public.%I', t);
    execute format('create trigger trg_fin_server_ts before insert or update on public.%I for each row execute function app.fin_server_ts()', t);
  end loop;
end $$;

-- ---------- F0.15 qo'lda to'lov — bitta tranzaksiya ----------
--   p_pay_id   — mijoz yaratgan barqaror id ('man_<ms>_<tasodif>'): oflayn navbat va qayta urinishlar shu bilan idempotent.
--   p_date     — kassir tanlagan «Sana» (kassa kuni). [bugun − 31, bugun] (Toshkent) ichida bo'lmasa saqlanmaydi va kassa kuni
--                kiritilgan kun bo'ladi (payDay bilan bir xil) — javobda dateAdjusted = true.
--   p_captured — to'lov kiritilgan payt (brauzer, oflayn navbatga qo'yilgan vaqt) — faqat ma'lumot uchun raw.capturedAt
--                (kelajakdagi vaqt saqlanmaydi). Kassa hujjatlari (1a) uni tekshiradi.
--   p_extra    — qo'shimcha maydonlar: {"fiscalNo": "...", "fiscalExempt": true} (kassa ishga tushgach naqd to'lovda fiskal chek №).
--   KASSA (moliya rejasi 1a, kassa-pay.sql): kassa ishga tushgan bo'lsa (fin_org.kassaGoLive) NAQD to'lov shu tranzaksiyaning
--     o'zida kassa kirim orderi (KO-1) bilan yoziladi — order o'tmasa (kecha yopilmagan, fiskal chek № yo'q …) to'lov ham yozilmaydi.
--     Kassa qo'llanadimi — to'lovning O'Z kassa kuni («Sana», bo'lmasa olingan kun) bo'yicha: ishga tushishdan oldingi kun puli —
--     KO-1 siz (boshlang'ich qoldiq sanashiga kirgan; kim kirita olishi — kassa-pay.sql).
--     Kassa funksiyalari hali o'rnatilmagan bo'lsa (kassa-pay.sql zanjirda yo'q) — avvalgidek, KO-1 siz.
drop function if exists public.record_manual_payment(text, text, numeric, text, text, text, text, text, timestamptz);
create or replace function public.record_manual_payment(
  p_pay_id text, p_sid text, p_amount numeric, p_method text, p_date text default null,
  p_note text default '', p_period text default '', p_payer_name text default '', p_captured timestamptz default null,
  p_extra jsonb default null)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_today date := app.fin_today();
  v_date text := nullif(trim(coalesce(p_date, '')), '');
  v_adj boolean := false;
  v_cap timestamptz := p_captured;
  v_row record;
  v_res jsonb;
  v_raw jsonb;
  v_before jsonb;   -- kassa: to'lovdan oldingi holat (fakturalar, avans); NULL — kassa ishga tushmagan yoki naqd emas
  v_k jsonb;        -- kassa: yozilgan KO-1 (raqam, kun)
begin
  if not (app.is_admin() or app.is_finance() or app.is_cashier()) then
    raise exception 'Ruxsat yo''q: to''lov faqat kassir, Moliya yoki Direktor tomonidan kiritiladi' using errcode = '42501';
  end if;
  p_pay_id := trim(coalesce(p_pay_id, ''));
  if p_pay_id !~ '^man_[A-Za-z0-9_]{3,64}$' then
    raise exception 'record_manual_payment: noto''g''ri payId' using errcode = '22023';
  end if;
  p_sid := trim(coalesce(p_sid, ''));
  if p_sid = '' then raise exception 'record_manual_payment: o''quvchi tanlanmagan' using errcode = '22023'; end if;
  -- NaN / Infinity (PostgREST JSON "NaN" satrini numeric NaN qiladi) va bema'ni katta summa ham rad etiladi.
  if p_amount is null or not (p_amount > 0 and p_amount < 1e12) or p_amount <> round(p_amount, 2) then
    raise exception 'record_manual_payment: summa noto''g''ri' using errcode = '22023';
  end if;
  if coalesce(p_method, '') not in ('cash', 'bank', 'terminal', 'uzum') then
    raise exception 'record_manual_payment: to''lov usuli noto''g''ri (naqd / bank / terminal / uzum)' using errcode = '22023';
  end if;
  if v_date is not null then
    if v_date !~ '^\d{4}-\d{2}-\d{2}$' or v_date > to_char(v_today, 'YYYY-MM-DD') or v_date < to_char(v_today - 31, 'YYYY-MM-DD') then
      v_date := null; v_adj := true;
    else
      begin perform v_date::date; exception when others then v_date := null; v_adj := true; end;
    end if;
  end if;
  if v_cap is not null and v_cap > app.fin_now() + interval '5 minutes' then v_cap := null; end if;
  -- «Sana» bo'sh kelsa (eski mijoz yoki oflayn navbat) — kassa kuni to'lov KIRITILGAN kun (p_captured), yuborilgan kun emas:
  --   chek o'sha kun bilan chop etilgan. Faqat [bugun − 31, bugun] ichida.
  if v_date is null and not v_adj and v_cap is not null
     and (v_cap at time zone 'Asia/Tashkent')::date between v_today - 31 and v_today then
    v_date := to_char((v_cap at time zone 'Asia/Tashkent')::date, 'YYYY-MM-DD');
  end if;
  if not exists (select 1 from public.students s where s.id = p_sid or s."studentId" = p_sid) then
    raise exception 'record_manual_payment: o''quvchi topilmadi (%)', p_sid using errcode = '22023';
  end if;
  -- Kassa (1a): naqd to'lov — kassa ishga tushgan bo'lsa to'lovdan OLDINGI holat olinadi (o'quvchi bo'yicha navbat qulfi ichida).
  --   Kassa kuni: kassir tanlagan «Sana», bo'lmasa olingan kun, bo'lmasa bugun; so'ralgan «Sana» matni ham beriladi (crit-1).
  if p_method = 'cash' and to_regprocedure('app.kassa_tuition_before(text,date,timestamptz,text)') is not null then
    execute 'select app.kassa_tuition_before($1, $2, $3, $4)' into v_before using p_sid, coalesce(v_date::date, v_today), v_cap, p_date;
  end if;

  -- Yangi qator; shu payId allaqachon bo'lsa (qayta yuborish, ikkinchi tab, eski 3 bosqichli mijoz yarim yo'lda qolgan) —
  --   ON CONFLICT parallel chaqiruvni birinchisi tugaguncha kutadi, keyin mavjud qator holatiga qaraladi.
  --   Kassa orqali o'tadigan naqd to'lov (v_before bor): kuni — kirim orderi tushadigan kassa kuni (kassa-pay.sql: kassa_tuition_before 'day'),
  --   olingan payt — raw.capturedAt da. Davr qulfi (yopilgan oy) shu kunni tekshiradi: oy oxirida navbatda qolgan to'lov keyingi oyda o'tadi.
  --   Kassasiz (yoki kassa ishlamagan kun puli) — avvalgidek, «Sana» / olingan kun.
  v_raw := jsonb_build_object('manual', true, 'method', p_method, 'date', coalesce(v_before ->> 'day', v_date, to_char(v_today, 'YYYY-MM-DD')),
                              'note', left(coalesce(p_note, ''), 500), 'forPeriod', left(coalesce(p_period, ''), 500),
                              'byUid', app.uid());
  if v_cap is not null then v_raw := v_raw || jsonb_build_object('capturedAt', v_cap); end if;
  -- Fiskal chek raqami (naqd va terminal to'lovlarida kassir kiritadi) — har qanday usulda saqlanadi.
  if p_extra is not null and jsonb_typeof(p_extra) = 'object' and nullif(btrim(coalesce(p_extra ->> 'fiscalNo', '')), '') is not null then
    v_raw := v_raw || jsonb_build_object('fiscalNo', left(btrim(p_extra ->> 'fiscalNo'), 40));
  end if;
  if v_adj then v_raw := v_raw || jsonb_build_object('dateRequested', left(coalesce(p_date, ''), 20)); end if;
  insert into public.payments(id, "studentId", provider, amount, status, "payerName", matched, raw)
    values (p_pay_id, p_sid, p_method, p_amount, 'pending', left(coalesce(p_payer_name, ''), 200), true, v_raw)
    on conflict (id) do nothing;
  if not found then
    select id, status, "studentId", amount into v_row from public.payments where id = p_pay_id for update;
    if coalesce(v_row.status, '') = 'applied' then
      if v_before is not null then execute 'select app.kassa_tuition_info($1)' into v_k using p_pay_id; end if;
      return jsonb_build_object('ok', true, 'dup', true, 'payId', p_pay_id, 'status', 'applied', 'kassa', v_k);
    end if;
    if coalesce(v_row.status, '') <> 'pending' then
      return jsonb_build_object('ok', false, 'reason', 'exists', 'payId', p_pay_id, 'status', v_row.status);
    end if;
    if coalesce(v_row."studentId", '') <> p_sid or coalesce(v_row.amount, 0) <> p_amount then
      return jsonb_build_object('ok', false, 'reason', 'mismatch', 'payId', p_pay_id);
    end if;
  end if;

  -- Balansga qo'llash (eng eski to'lanmagan fakturadan, ortiqchasi avansga). applied_payments posboni bilan idempotent.
  perform set_config('iqror.money_rpc', '1', true);
  v_res := public.apply_payment(p_sid, p_amount, p_method, p_pay_id);
  perform set_config('iqror.money_rpc', '', true);
  if v_res is null or not (coalesce((v_res ->> 'ok')::boolean, false) or coalesce((v_res ->> 'dup')::boolean, false)) then
    raise exception 'record_manual_payment: to''lov qo''llanmadi (%)', coalesce(v_res::text, 'null') using errcode = 'P0001';
  end if;
  update public.payments set status = 'applied' where id = p_pay_id;
  -- Kassa (1a): kassa kirim orderi (KO-1) — shu tranzaksiyada. Kassa kuni server belgilaydi (kassir tanlagan «Sana» emas).
  if v_before is not null then
    execute 'select app.kassa_tuition_post($1, $2, $3, $4, $5, $6, $7)' into v_k
      using p_pay_id, p_amount, p_payer_name, v_cap, p_extra, v_before, coalesce((v_res ->> 'dup')::boolean, false);
  end if;
  return jsonb_build_object('ok', true, 'dup', coalesce((v_res ->> 'dup')::boolean, false), 'payId', p_pay_id, 'status', 'applied',
                            'sid', v_res ->> 'sid', 'credit', v_res -> 'credit', 'dateAdjusted', v_adj and v_k is null,
                            'day', coalesce(v_k ->> 'day', v_date, to_char(v_today, 'YYYY-MM-DD')), 'kassa', v_k);
end $$;
revoke all on function public.record_manual_payment(text, text, numeric, text, text, text, text, text, timestamptz, jsonb) from public, anon;
grant execute on function public.record_manual_payment(text, text, numeric, text, text, text, text, text, timestamptz, jsonb) to authenticated;

-- ---------- F0.16 huquqlar I ----------
-- RF-01 + RF-05: xarajatni faqat Direktor va moliya (Moliya menejeri / G'aznachi) yozadi va o'chiradi.
drop policy if exists exp_ins on public.expenses;
create policy exp_ins on public.expenses for insert with check (app.is_admin() or app.is_finance());
drop policy if exists exp_upd on public.expenses;
create policy exp_upd on public.expenses for update using (app.is_admin() or app.is_finance()) with check (app.is_admin() or app.is_finance());
drop policy if exists exp_del on public.expenses;
create policy exp_del on public.expenses for delete using (app.is_admin() or app.is_finance());
-- RF-02: xodim avansini kassir to'g'ridan-to'g'ri yozmaydi (UI — «Buxgalteriya» → «Xodim avansi», Moliya / Direktor).
drop policy if exists sa_ins on public.staff_advances;
create policy sa_ins on public.staff_advances for insert with check (app.is_admin() or app.is_finance());
drop policy if exists sa_upd on public.staff_advances;
create policy sa_upd on public.staff_advances for update using (app.is_admin() or app.is_finance()) with check (app.is_admin() or app.is_finance());
drop policy if exists sa_del on public.staff_advances;
create policy sa_del on public.staff_advances for delete using (app.is_admin() or app.is_finance());
-- RF-07: avans jurnali faqat qo'shiladi (o'chirish siyosati yo'q).
drop policy if exists cl_del on public.credit_ledger;
-- Avans (student_credit) — faqat pul RPC'lari orqali (apply_payment, add_credit, reattribute_avans va b. — jurnal bilan).
--   To'g'ridan-to'g'ri yozish faqat Direktor (moliya menejeri / g'aznachi avansni jurnalsiz o'zgartira olmasin; admin ilovasi
--   bu jadvalga to'g'ridan-to'g'ri yozmaydi).
drop policy if exists sc_credit_ins on public.student_credit;
create policy sc_credit_ins on public.student_credit for insert with check (app.is_admin());
drop policy if exists sc_credit_upd on public.student_credit;
create policy sc_credit_upd on public.student_credit for update using (app.is_admin()) with check (app.is_admin());

notify pgrst, 'reload schema';
