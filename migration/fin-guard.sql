\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: fin-guard.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- fin-guard.sql — moliya rejasi F2.9 «Huquqlar II» (RF-09 … RF-12): pul jadvallariga to'g'ridan-to'g'ri yozuv DETEKTORI va QULFI,
--   barcha pul funksiyalarida bayroq, «Bekor» / «✓ Bajarildi» — funksiya orqali, g'aznachi = kassa operatori, marketing — faqat yig'ma.
--
-- 1) Bayroq (RF-04 ning davomi, «barcha pul RPC larida bayroq»): pul jadvallariga (payments, invoices, student_credit, credit_ledger,
--    expenses) yozadigan har SECURITY DEFINER funksiyaga «SET iqror.fin_rpc = '1'» (funksiya ichida yoqiq, chiqishda o'zi tiklanadi;
--    ichma-ich chaqiruvlarga ham o'tadi). Ro'yxat qo'lda yuritilmaydi: shu fayl (zanjirning oxirida — rls-* fayllaridan oldin) funksiya
--    matnida shu jadvallarga INSERT / UPDATE / DELETE bor barcha definer funksiyalarni topadi va har deployda qayta belgilaydi (oldingi
--    fayl «create or replace» qilsa ham). Kutilgan ro'yxat — test-fin-guard.sql (yangi pul funksiyasi qo'shilsa sinov uni ko'rsatadi).
--
-- 2) Detektor (trg_fin_direct, app.fin_direct_detect — SECURITY INVOKER: current_user so'rov egasini ko'rsatadi): bayroqsiz yozuv —
--    «to'g'ridan-to'g'ri» (jurnal: public.fin_direct_log — Direktor ko'radi). Manba (via):
--      rest   — sahifa / PostgREST (authenticated, anon);
--      server — service_role REST (to'lov serveri; payments qatori — istisno: Click / Uzum serveri to'lov qatorini o'zi yozadi, pulni
--               esa apply_payment / apply_to_invoice / reverse_payment funksiyalari qo'llaydi — ular bayroqli);
--      rpc    — API so'rovi ichidagi bayroqsiz definer funksiya (yangi yoki unutilgan pul funksiyasi).
--    Kuzatilmaydi: deploy (iqror.migrating), API dan tashqari ish (psql / texnik xizmat — JWT yo'q, rol postgres).
--    Doira: payments — har qanday yozuv; invoices — to'lov maydonlari (paidAmount, status, paidAt; yangi faktura — to'lanmagan yoki
--    sababli 0 so'mlik «to'langan» bo'lsa toza, app.inv_paid_guard qoidasi bilan bir xil; o'chirish — to'lov holati bor faktura);
--    student_credit, credit_ledger — har qanday yozuv; expenses — oylik maosh hisobi qatoridan («payroll__YYYY-MM») boshqasi
--    (hujjatsiz to'g'ridan-to'g'ri yozuv; hujjatli qatorlar — trg_fin_exp_guard). Faqat «updatedAt» o'zgargan yozuv — hisoblanmaydi.
--
-- 3) Qulf (revoke): Direktor sozlamasi fin_org.extra.directGuard («⚙ Sozlamalar»; fin_org_set). Yoqish sharti — «7 kun 0 yozuv»:
--    detektor kamida 7 kun ishlagan (extra.guardSince — shu fayl birinchi o'rnatilgan kun) va oxirgi 7 kunda jurnal bo'sh
--    (app.fin_guard_check; fin:guard_young / fin:guard_dirty). Qulf yoqilganda detektor yozish o'rniga rad etadi (42501, fin:direct;
--    xarajatlarda — faqat «payroll__» qatori ochiq qoladi: reja «exp_ins / exp_upd / exp_del faqat payroll__ qatoriga» — siyosat emas,
--    trigger: aniq xabar beradi, qulfni o'chirish = orqaga qaytarish). Pul funksiyalari (bayroqli) va to'lov serveri ishlayveradi.
--    ORQAGA QAYTARISH: Direktor qulfni o'chiradi (fin_org_set {directGuard:false}) — deploy kerak emas; o'zgarish change_log da
--    (fin_org.extra kuzatiladi).
--
-- 4) Funksiyalar: fin_pay_cancel — «🚫 Bekor» (qo'llanmagan fantom / xato yozuv; avval sahifa payments ga o'zi yozardi — RF-09),
--    fin_pay_rev_done — «✓ Bajarildi» (qo'lda qaytarish ro'yxati; kim — server qo'yadi), fin_guard_report — detektor hisoboti
--    (Direktor), fin_marketing_spend — marketing xarajati oylar bo'yicha (RF-12: marketing «Buxgalteriya» qatorlarini o'qimaydi).
-- 5) RF-11: g'aznachi = kassa operatori (FD-30): app.is_finance() — Direktor va Moliya menejeri; app.is_cashier() — kassir va g'aznachi
--    (moliya menejeri huquqlari — faktura yaratish, xarajat, avans qo'shish, qaytarish — g'aznachida yo'q; kassir huquqlari bor).
-- 6) RF-10: student_credit — to'g'ridan-to'g'ri yozish allaqachon faqat Direktor (sc_credit_ins / sc_credit_upd); credit_ledger ham faqat
--    Direktor (cl_ins: moliya menejeri olib tashlandi — sahifada bunday yozuv yo'q); faktura to'lov maydonlari — 2-bandagi detektor
--    (service_role ham: to'lov serveri fakturani faqat funksiyalar orqali o'zgartiradi).
-- HOLAT: run-all.sql'da «--dev \ir» — kassa moduli bilan birga. Idempotent — QAYTA ishga tushirishga xavfsiz.
-- =====================================================================

-- ---------- 5) RF-11: g'aznachi = kassa operatori ----------
--   SQL, bitta SELECT (rls-plpgsql.sql zanjir oxirida shu ta'rifni plpgsql'ga o'raydi).
create or replace function app.is_finance() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.role_set() && array['director', 'finance_mgr']::text[]
$$;
create or replace function app.is_cashier() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.role_set() && array['kassir', 'treasurer']::text[]
$$;

-- ---------- 2) Detektor jurnali ----------
create table if not exists public.fin_direct_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),     -- yozuv vaqti (app.fin_now — server soati; «7 kun» sharti fin_today bilan bir xil soatda)
  grp         text not null check (grp in ('payments', 'invoices', 'credit', 'expenses')),
  tbl         text not null,
  op          text not null check (op in ('INSERT', 'UPDATE', 'DELETE')),
  row_id      text not null default '',
  via         text not null check (via in ('rest', 'server', 'rpc')),
  api_role    text not null default '',          -- JWT dagi rol (authenticated / anon / service_role)
  actor_uid   text,                              -- users.id (JWT sub; bo'lmasa — null)
  actor_role  text,                              -- o'sha paytdagi asosiy rol
  cols        text[] not null default '{}'        -- o'zgargan ustunlar (faqat nomlari, qiymatsiz)
);
create index if not exists fin_direct_log_at_idx on public.fin_direct_log (at desc);
alter table public.fin_direct_log enable row level security;
revoke all on public.fin_direct_log from public, anon, authenticated;
grant select on public.fin_direct_log to authenticated;
grant all on public.fin_direct_log to service_role;
drop policy if exists fin_direct_log_sel on public.fin_direct_log;
create policy fin_direct_log_sel on public.fin_direct_log for select using (app.is_admin());
-- insert / update / delete siyosati YO'Q: faqat detektor (app.fin_direct_note — security definer) yozadi.

-- Detektor ishga tushgan kun (bir marta; qayta deploy o'zgartirmaydi) — «7 kun» sharti shundan hisoblanadi.
update public.fin_org set extra = coalesce(extra, '{}'::jsonb) || jsonb_build_object('guardSince', app.fin_today())
 where id = 'main' and not (coalesce(extra, '{}'::jsonb) ? 'guardSince');

-- ---------- 3) Qulf holati va yoqish sharti ----------
create or replace function app.fin_guard_on() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce((select (o.extra ->> 'directGuard') = 'true' from public.fin_org o where o.id = 'main'), false)
$$;
revoke all on function app.fin_guard_on() from public, anon, authenticated;

-- Detektor ishga tushgan kun (extra.guardSince; noto'g'ri yoki yo'q — null).
create or replace function app.fin_guard_since() returns date
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when (o.extra ->> 'guardSince') ~ '^\d{4}-\d{2}-\d{2}$' then (o.extra ->> 'guardSince')::date end
    from public.fin_org o where o.id = 'main'
$$;
revoke all on function app.fin_guard_since() from public, anon, authenticated;

-- «7 kun 0 yozuv»: qulfni yoqishdan oldin (fin_org_set) — shart bajarilmasa rad etadi.
create or replace function app.fin_guard_check() returns void
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_today date := app.fin_today(); v_since date := app.fin_guard_since(); v_n int; v_last timestamptz;
begin
  if v_since is null or v_today - v_since < 7 then
    raise exception 'To''g''ridan-to''g''ri yozuvni yopish uchun detektor kamida 7 kun ishlagan bo''lishi kerak (ishga tushgan: %; yopish mumkin: %)',
      coalesce(to_char(v_since, 'DD.MM.YYYY'), '—'), coalesce(to_char(v_since + 7, 'DD.MM.YYYY'), '—')
      using errcode = 'P0001', hint = 'fin:guard_young';
  end if;
  select count(*), max(l.at) into v_n, v_last
    from public.fin_direct_log l where l.at >= (v_today - 7)::timestamp at time zone 'Asia/Tashkent';
  if v_n > 0 then
    raise exception 'Oxirgi 7 kunda to''g''ridan-to''g''ri yozuvlar bor: % ta (oxirgisi %) — avval ularning manbasini aniqlang (⚙ Sozlamalar → detektor ro''yxati)',
      v_n, to_char(v_last at time zone 'Asia/Tashkent', 'DD.MM.YYYY HH24:MI')
      using errcode = 'P0001', hint = 'fin:guard_dirty';
  end if;
end $$;
revoke all on function app.fin_guard_check() from public, anon, authenticated;

-- Detektor yordamchisi: qulf yoqilgan — rad etadi; o'chiq — jurnalga yozadi (jurnal yozilmasa asosiy amal to'xtamaydi — WARNING).
--   Faqat trigger ichidan (pg_trigger_depth); app sxemasi PostgREST'da ochiq emas. Detektor triggeri SECURITY INVOKER bo'lgani uchun
--   so'rov egasi (authenticated / anon / service_role) chaqira olishi kerak — kassa-checks.sql 5-bandida istisno.
create or replace function app.fin_direct_note(p_grp text, p_tbl text, p_op text, p_id text, p_via text, p_cols text[]) returns void
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_claims text; v_uid text; v_role text;
begin
  if pg_trigger_depth() < 1 then
    raise exception 'fin_direct_note: faqat detektor triggeri chaqiradi' using errcode = '42501';
  end if;
  if app.fin_guard_on() then
    raise exception '%', case p_grp
        when 'payments' then 'To''lov yozuvini faqat to''lov funksiyalari yozadi («💵 To''lov», «Biriktirish», «Bekor» …) — to''g''ridan-to''g''ri yozish yopilgan'
        when 'invoices' then 'Hisob-fakturaning to''lov holatini (to''langan summa, holat, to''langan vaqt) faqat to''lov funksiyalari o''zgartiradi — to''g''ridan-to''g''ri yozish yopilgan'
        when 'credit' then 'Avans va avans jurnali faqat to''lov funksiyalari orqali o''zgaradi — to''g''ridan-to''g''ri yozish yopilgan'
        else 'Xarajat faqat «Buxgalteriya» xarajat oynasi (hujjat bilan) orqali yoziladi — to''g''ridan-to''g''ri faqat oylik maosh hisobi qatori'
      end
      using errcode = '42501', hint = 'fin:direct', detail = p_tbl || ' / ' || p_op;
  end if;
  begin
    v_claims := nullif(current_setting('request.jwt.claims', true), '');
    v_uid := app.uid();
    if v_uid is not null then select u.role into v_role from public.users u where u.id = v_uid; end if;
    insert into public.fin_direct_log (at, grp, tbl, op, row_id, via, api_role, actor_uid, actor_role, cols)
    values (app.fin_now(), p_grp, p_tbl, p_op, left(coalesce(p_id, ''), 200), p_via,
            coalesce(case when v_claims is not null then left(v_claims::jsonb ->> 'role', 40) end, ''), v_uid, v_role, coalesce(p_cols, '{}'));
  exception when others then
    raise warning 'fin_direct_log yozilmadi (%): %', p_tbl, sqlerrm;
  end;
end $$;
revoke all on function app.fin_direct_note(text, text, text, text, text, text[]) from public;
grant execute on function app.fin_direct_note(text, text, text, text, text, text[]) to anon, authenticated, service_role;

-- Detektor triggeri (AFTER ROW — faqat haqiqatda yozilgan qatorlar). tg_argv[0] — guruh.
create or replace function app.fin_direct_detect() returns trigger
language plpgsql security invoker set search_path = public, app, pg_temp as $$
declare
  v_cu text := current_user::text; v_grp text := tg_argv[0]; v_via text;
  v_o jsonb; v_n jsonb; v_id text; v_cols text[]; v_e jsonb;
begin
  if coalesce(current_setting('iqror.migrating', true), '') = '1' or coalesce(current_setting('iqror.fin_rpc', true), '') = '1' then
    return null;
  end if;
  if v_cu in ('authenticated', 'anon') then v_via := 'rest';
  elsif v_cu = 'service_role' then v_via := 'server';
  elsif coalesce(current_setting('request.jwt.claims', true), '') <> '' then v_via := 'rpc';
  else return null;
  end if;
  if v_grp = 'payments' and v_via = 'server' then return null; end if;
  v_o := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_n := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_id := coalesce(v_n ->> 'id', v_o ->> 'id', '');
  if v_grp = 'expenses' then
    -- oylik maosh hisobi qatori (sahifa yozadi, F2.4 — kind 'accrual') — ochiq; id o'zgarsa ikkalasi ham shu qator bo'lishi kerak
    if left(coalesce(v_n ->> 'id', v_o ->> 'id', ''), 9) = 'payroll__' and left(coalesce(v_o ->> 'id', v_n ->> 'id', ''), 9) = 'payroll__' then
      return null;
    end if;
  elsif v_grp = 'invoices' then
    if tg_op = 'INSERT' then
      -- toza yangi faktura: to'lanmagan yoki sababli 0 so'mlik «to'langan» (app.inv_paid_guard bilan bir xil qoida)
      if coalesce((v_n ->> 'paidAmount')::numeric, 0) = 0 and v_n ->> 'paidAt' is null and coalesce(v_n ->> 'status', '') in ('', 'pending') then
        return null;
      end if;
      if coalesce((v_n ->> 'paidAmount')::numeric, 0) = 0 and v_n ->> 'status' = 'paid' and coalesce((v_n ->> 'amount')::numeric, 0) = 0
         and (coalesce((v_n ->> 'isGrant')::boolean, false) or coalesce((v_n ->> 'pctApplied')::numeric, 0) > 0
              or coalesce(jsonb_typeof(v_n -> 'approvalRefs') = 'array' and jsonb_array_length(v_n -> 'approvalRefs') > 0, false)
              or coalesce(v_n ->> 'bonusRef', '') <> ''
              or coalesce(jsonb_typeof(v_n -> 'referralUsedIds') = 'array' and jsonb_array_length(v_n -> 'referralUsedIds') > 0, false)
              or coalesce((v_n ->> 'sickAmount')::numeric, 0) > 0) then
        return null;
      end if;
      v_cols := array['paidAmount', 'status', 'paidAt'];
    elsif tg_op = 'UPDATE' then
      v_cols := array(select k from unnest(array['paidAmount', 'status', 'paidAt']) k where (v_o -> k) is distinct from (v_n -> k));
      if cardinality(v_cols) = 0 then return null; end if;
    else
      if coalesce((v_o ->> 'paidAmount')::numeric, 0) = 0 and coalesce(v_o ->> 'status', '') in ('', 'pending') then return null; end if;
      v_cols := array['paidAmount', 'status'];
    end if;
  end if;
  if v_cols is null then
    if tg_op = 'UPDATE' then
      v_cols := array(select e.key from jsonb_each(v_n) e where e.key <> 'updatedAt' and e.value is distinct from (v_o -> e.key) order by e.key);
      if cardinality(v_cols) = 0 then return null; end if;
    else
      v_cols := '{}';
    end if;
  end if;
  perform app.fin_direct_note(v_grp, tg_table_name, tg_op, v_id, v_via, v_cols);
  return null;
end $$;
revoke all on function app.fin_direct_detect() from public, anon, authenticated;

do $$
declare r record;
begin
  for r in select * from (values ('payments', 'payments'), ('invoices', 'invoices'), ('student_credit', 'credit'),
                                 ('credit_ledger', 'credit'), ('expenses', 'expenses')) v(t, g) loop
    if to_regclass('public.' || quote_ident(r.t)) is null then continue; end if;
    execute format('drop trigger if exists trg_fin_direct on public.%I', r.t);
    execute format('create trigger trg_fin_direct after insert or update or delete on public.%I for each row execute function app.fin_direct_detect(%L)', r.t, r.g);
  end loop;
end $$;

-- ---------- 1) Bayroq: pul jadvallariga yozadigan barcha definer funksiyalar ----------
--   (izohdagi so'z ham mos kelishi mumkin — ortiqcha bayroq zararsiz: funksiya baribir shu jadvallarga yozmaydi). Faqat SECURITY DEFINER:
--   SECURITY INVOKER funksiya so'rov egasi huquqlari bilan ishlaydi — u «sahifa yozuvi» bo'lib qoladi. Migratsiya ta'mirlash funksiyalari
--   (discount_legacy_repair, inv_parts_backfill, payer_codes_fix — invoker) deploy ichida ishlaydi (iqror.migrating).
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace in ('public'::regnamespace, 'app'::regnamespace) and p.prokind = 'f' and p.prosecdef
              and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(only\s+)?(public\.)?"?(payments|invoices|student_credit|credit_ledger|expenses)\M"?'
            order by 1 loop
    execute format('alter function %s set iqror.fin_rpc = %L', f, '1');
  end loop;
end $$;

-- ---------- 4) «🚫 Bekor» va «✓ Bajarildi» — funksiya orqali (RF-09) ----------
--   Qoida — app.pay_direct_guard bilan bir xil: faqat Direktor, faqat fakturaga QO'LLANMAGAN (fantom / xato / biriktirilmagan) yozuv;
--   qo'llangan to'lov — «↩ Qaytarish» yoki fakturani qayta hisoblash. Kim va qachon — raw ichida (server qo'yadi). Qayta bosish — xatosiz.
create or replace function public.fin_pay_cancel(p_id text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp set iqror.fin_rpc = '1' as $$
declare r public.payments%rowtype;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: to''lov yozuvini faqat Direktor bekor qiladi' using errcode = '42501'; end if;
  select * into r from public.payments p where p.id = coalesce(p_id, '') for update;
  if not found then raise exception 'To''lov yozuvi topilmadi' using errcode = '22023', hint = 'pay:not_found'; end if;
  if r.status = 'canceled' then return jsonb_build_object('ok', true, 'dup', true); end if;
  if coalesce(r.status, '') in ('applied', 'confirmed', 'paid', 'split', 'refunded', 'reversed') then
    raise exception 'Qo''llangan to''lovni «Bekor» qilib bo''lmaydi — «↩ Qaytarish» yoki fakturani qayta hisoblash orqali'
      using errcode = '42501', hint = 'pay:applied';
  end if;
  update public.payments
     set status = 'canceled', "statusAt" = now(),
         raw = coalesce(raw, '{}'::jsonb) || jsonb_build_object('canceledBy', app.uid(), 'canceledAt', now())
   where id = r.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.fin_pay_cancel(text) from public, anon;
grant execute on function public.fin_pay_cancel(text) to authenticated;

-- Qo'lda qaytarish ro'yxati (to'lov serveri raw.needsManualReverse qo'ygan qaytarilgan to'lov): o'quvchi balansi qo'lda tuzatilgach
--   Direktor «✓ Bajarildi» — ro'yxatdan chiqadi. Kim — uid (avval sahifa email yozardi).
create or replace function public.fin_pay_rev_done(p_id text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp set iqror.fin_rpc = '1' as $$
declare r public.payments%rowtype;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: faqat Direktor' using errcode = '42501'; end if;
  select * into r from public.payments p where p.id = coalesce(p_id, '') for update;
  if not found then raise exception 'To''lov yozuvi topilmadi' using errcode = '22023', hint = 'pay:not_found'; end if;
  if coalesce(r.raw ->> 'needsManualReverse', '') <> 'true' then
    raise exception 'Bu to''lov qo''lda qaytarish ro''yxatida emas' using errcode = '22023', hint = 'pay:not_manual';
  end if;
  if coalesce(r.raw ->> 'manualReverseDone', '') = 'true' then return jsonb_build_object('ok', true, 'dup', true); end if;
  update public.payments
     set raw = r.raw || jsonb_build_object('manualReverseDone', true, 'manualReverseBy', app.uid(), 'manualReverseAt', now())
   where id = r.id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.fin_pay_rev_done(text) from public, anon;
grant execute on function public.fin_pay_rev_done(text) to authenticated;

-- ---------- 3) Detektor hisoboti (Direktor) ----------
--   p_days — davr (1–400 kun, standart 7). Shaxsiy ma'lumot yo'q: yozuv id (to'lov / faktura / o'quvchi ID), ustun nomlari, rol, ism.
create or replace function public.fin_guard_report(p_days int default 7) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare
  v_days int := least(greatest(coalesce(p_days, 7), 1), 400); v_today date := app.fin_today();
  v_from timestamptz; v_f7 timestamptz; v_since date := app.fin_guard_since(); v_on boolean := app.fin_guard_on(); v_n7 int;
begin
  if not app.is_admin() then raise exception 'Ruxsat yo''q: faqat Direktor' using errcode = '42501'; end if;
  v_from := (v_today - v_days)::timestamp at time zone 'Asia/Tashkent';
  v_f7 := (v_today - 7)::timestamp at time zone 'Asia/Tashkent';
  select count(*) into v_n7 from public.fin_direct_log l where l.at >= v_f7;
  return jsonb_build_object(
    'mode', case when v_on then 'enforce' else 'detect' end, 'since', v_since, 'today', v_today, 'days', v_days, 'n7', v_n7,
    'canEnforce', not v_on and v_since is not null and v_today - v_since >= 7 and v_n7 = 0,
    'enforceFrom', v_since + 7,
    'groups', (select jsonb_agg(jsonb_build_object('grp', g.grp,
                                                   'n', (select count(*) from public.fin_direct_log l where l.grp = g.grp and l.at >= v_from),
                                                   'last', (select max(l.at) from public.fin_direct_log l where l.grp = g.grp)) order by g.o)
                 from (values (1, 'payments'), (2, 'invoices'), (3, 'credit'), (4, 'expenses')) g(o, grp)),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', x.at, 'grp', x.grp, 'tbl', x.tbl, 'op', x.op, 'rowId', x.row_id, 'via', x.via,
                                                            'apiRole', x.api_role, 'actorRole', x.actor_role, 'actorName', x.nm, 'cols', to_jsonb(x.cols))
                                         order by x.at desc, x.id desc)
                          from (select l.*, coalesce(nullif(btrim(u.name), ''), '') as nm
                                  from public.fin_direct_log l left join public.users u on u.id = l.actor_uid
                                 where l.at >= v_from order by l.at desc, l.id desc limit 50) x), '[]'::jsonb));
end $$;
revoke all on function public.fin_guard_report(int) from public, anon;
grant execute on function public.fin_guard_report(int) to authenticated;

-- Nazorat ro'yxati (RP-06, kassa_checks «direct») uchun qisqa holat — faqat Direktorga (kassa_checks dinamik chaqiradi).
--   canEnforce — fin_guard_report dagi bilan bir xil qoida (7 kun toza, qulf o'chiq): nazorat ro'yxati «yopish mumkin» deb eslatadi.
create or replace function app.fin_guard_brief() returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select jsonb_build_object('mode', case when x.v_on then 'enforce' else 'detect' end, 'since', x.v_since, 'n7', x.v_n7,
                            'canEnforce', not x.v_on and x.v_since is not null and app.fin_today() - x.v_since >= 7 and x.v_n7 = 0)
    from (select app.fin_guard_on() as v_on, app.fin_guard_since() as v_since,
                 (select count(*) from public.fin_direct_log l where l.at >= (app.fin_today() - 7)::timestamp at time zone 'Asia/Tashkent') as v_n7) x
$$;
revoke all on function app.fin_guard_brief() from public, anon, authenticated;

-- ---------- 4) RF-12: marketing — faqat yig'ma (CAC uchun «Marketing» / «Reklama» xarajati oylar bo'yicha) ----------
create or replace function public.fin_marketing_spend() returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not (app.is_admin() or app.is_marketing()) then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  return coalesce((select jsonb_object_agg(x.m, x.s)
                     from (select coalesce(nullif(e.month, ''), left(coalesce(e.date, ''), 7)) as m, sum(coalesce(e.amount, 0)) as s
                             from public.expenses e where e.category in ('Marketing', 'Reklama') group by 1) x
                    where x.m ~ '^\d{4}-\d{2}$'), '{}'::jsonb);
end $$;
revoke all on function public.fin_marketing_spend() from public, anon;
grant execute on function public.fin_marketing_spend() to authenticated, service_role;

drop policy if exists exp_sel on public.expenses;
create policy exp_sel on public.expenses for select using (app.is_admin() or app.is_zavuch() or app.is_finance() or app.is_cashier());

-- ---------- 6) RF-10: avans jurnali — to'g'ridan-to'g'ri qo'shish faqat Direktor ----------
drop policy if exists cl_ins on public.credit_ledger;
create policy cl_ins on public.credit_ledger for insert with check (app.is_admin());

-- Sozlamalar (shu jumladan qulf) o'zgarishi o'zgarishlar tarixida: fin_org.extra ham kuzatiladi (fin-period.sql ro'yxati + extra).
select app.chlog_attach('fin_org', 'nameUz,nameRu,stir,place,printLang,t1,l1,cashLimit,kassaGoLive,lockedThrough,extra');

notify pgrst, 'reload schema';
