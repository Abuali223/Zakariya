\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: inv-parts.sql ALOHIDA ishga tushirilmaydi — u zanjirdagi faktura ustunlari va qo''riqchilariga (discounts.sql, invoice-guards.sql, discount-approval.sql) tayanadi' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- inv-parts.sql — HISOB-FAKTURA TARKIBI (moliya ish rejasi F2.7, qaror FD-32). Har fakturada yalpi summa va chegirmalar turlari
--   bo'yicha: bosh kitob (4-bosqich) Dt 4010 Kt 9030 (yalpi) va Dt 9050 Kt 4010 (chegirma turi bo'yicha; bemor kuni — 9030 storno)
--   provodkalarini va DT analitikasini (4.3) shundan oladi. Pul summasi (amount) O'ZGARMAYDI (CON-02) — tarkib uni tushuntiradi:
--     amount = "grossAmount" − Σ "discountParts".
--   "grossAmount" — yalpi: asosiy narx (narx jadvali / kontrakt / zaxira summa); oy o'rtasida kelgan-ketganda — ish kunlari ulushi
--     (prorata — kamroq daromad, chegirma emas; FD-32). 100 % grantda ham ulush bilan (yalpi = grant qismi, summa 0).
--   "discountParts" — {tur: so'm}, faqat musbat qismlar. Turlar:
--     grant          — 100 % grant (olimpiada / ijtimoiy; tasdiqlangan so'rov bilan)
--     monitoring100  — monitoring 100 ball (100 %; o'tish oyidan — Direktor tasdiqlagan bonus bilan)
--     monitoring20   — monitoring 90+ (20 %)
--     teacher_child  — xodim farzandi (50 %)
--     siblings       — aka-uka (10 %)
--     referral       — tavsiya bonusi (FD-32: 9050, variant 9410)
--     sick           — bemor kuni (FD-32: 9030 storno, variant 9050) — fakturadan HAQIQATAN ayirilgan qismi (eski qoidada fakturaga
--                      sig'magan kasal kun summasi "sickAmount" da qoladi, tarkibga kirmaydi)
--     other          — izohsiz farq: faqat server eski fakturadan tushuntira olmagan qism (sahifa yubormaydi)
--   Toifa chegirmasi (birinchi beshtasi) — fakturada ko'pi bilan bittasi va u "pctApplied" ga mos (app.inv_parts_kind; admin.html
--     invPartKind bilan aynan bir xil): ≥ 100 % — «Monitoring 100…» matni yoki bonus ishorasi bo'lsa monitoring100, aks holda grant;
--     ≥ 50 % — teacher_child; ≥ 20 % — monitoring20; > 0 — siblings; 0 — toifa chegirmasi yo'q (kontrakt summasi — asosiy narxning o'zi).
--   Kim yozadi: sahifa (admin.html computeTuition — «Hisob-fakturalar yaratish» va «↻ Qayta hisoblash» / reprice_invoice meta).
--     Trigger trg_invoice_zparts — faktura qo'riqchilaridan KEYIN (BEFORE triggerlar nom bo'yicha alfavit tartibida ishlaydi):
--     • yuborilgan tarkib qoidalarga mos bo'lsa — saqlanadi (0 qismlar olib tashlanadi);
--     • mos bo'lmasa yoki yuborilmagan bo'lsa (eski sahifa, to'lov serveri, qo'lda yozuv) — server SAQLANGAN maydonlardan o'zi chiqaradi
--       (app.inv_parts_infer): asosiy narx, foiz, kasal kun summasi, izohdagi «a/b ish kuni (prorata)» va «Referral −X» — admin.html
--       bilan aynan bir xil yaxlitlash (JavaScript Math.round, IEEE double). Faktura yozuvi tarkib sababli HECH QACHON rad etilmaydi
--       (tarkib — hisobga oid ma'lumot, pul amali to'xtamasin): mos kelmagan yuborilgan tarkib — WARNING va serverda qayta hisoblanadi;
--     • summa / chegirma maydonlari yoki izoh o'zgarganda saqlangan tarkib endi mos kelmasa — qayta chiqariladi; mos kelsa — tegilmaydi
--       (holat bo'yicha bekor qilishda — «[holat] …» izohi — summa, foiz va tarkib o'zgarmaydi, 100 % turi ham saqlanadi);
--     • ikkala ustunni NULL qilish — «server qayta hisoblasin» (ogohlantirishsiz; quyidagi to'ldirish shundan foydalanadi).
--   Eski fakturalar — fayl oxirida, HAR DEPLOYDA: tarkibi yo'q yoki mos kelmaydigan qatorlar to'ldiriladi (to'g'rilariga tegilmaydi).
--     Saqlangan maydonlardan tushuntirib bo'lmagan farq: summa kutilgandan kichik — 'other'; katta — avval kasal kun, keyin tavsiya,
--     keyin toifa qismi kamaytiriladi (qolsa — yalpi = summa). 2026-11 dan amaldagi shunday fakturalar — deploy chiqishida
--     «OGOHLANTIRISH» (faktura ID lari, ismsiz). Qabul mezoni (F2.7): 2026-11 dan 100 % fakturada amount = yalpi − Σ qismlar.
--   Huquq: summa / chegirma maydonlari kabi — Direktor yoki reprice_invoice (discount-approval.sql, invoice_discount_guard a-bandi);
--     yopilgan davrda o'zgarmaydi (fin-period.sql app.fin_lock_invoices); buxgalter — invoices_acc orqali o'qiydi (fin-rights.sql).
--   Sinov: migration/test-inv-parts.sql (korpus — assets/js/inv-parts.test.mjs bilan umumiy), brauzer k24.
-- =====================================================================

-- JavaScript Math.round: kasr qismi ≥ 0,5 — +∞ tomonga. float8 — admin.html dagi IEEE double hisobi bilan bir xil natija.
create or replace function app.inv_jsround(p float8) returns numeric
language sql immutable parallel safe set search_path = public, app, pg_temp as $$
  select (case when p - floor(p) >= 0.5 then floor(p) + 1 else floor(p) end)::numeric $$;

-- Toifa chegirmasi turi (admin.html invPartKind bilan bir xil).
create or replace function app.inv_parts_kind(p_pct numeric, p_bonus text, p_info text) returns text
language sql immutable parallel safe set search_path = public, app, pg_temp as $$
  select case
    when coalesce(p_pct, 0) >= 1 then
      case when coalesce(p_bonus, '') <> '' or coalesce(p_info, '') ilike 'Monitoring 100%' then 'monitoring100' else 'grant' end
    when p_pct >= 0.5 then 'teacher_child'
    when p_pct >= 0.2 then 'monitoring20'
    when p_pct > 0 then 'siblings'
  end $$;

-- 0 so'mlik qismlarni olib tashlaydi (obyekt bo'lmasa — o'zgarmaydi, tekshiruv rad etadi).
create or replace function app.inv_parts_norm(p jsonb) returns jsonb
language sql immutable parallel safe set search_path = public, app, pg_temp as $$
  select case when jsonb_typeof(p) = 'object'
    then coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(p) e
                    where not (jsonb_typeof(e.value) = 'number' and (e.value #>> '{}')::numeric = 0)), '{}'::jsonb)
    else p end $$;

-- Tarkib qoidalarga mosmi: null — mos; aks holda sabab. p_strict — mijoz yuborgan qiymat ('other' — faqat server chiqaradi).
create or replace function app.inv_parts_check(p_gross numeric, p_parts jsonb, p_amount numeric, p_pct numeric, p_bonus text,
                                               p_info text, p_sick numeric, p_strict boolean) returns text
language plpgsql immutable parallel safe set search_path = public, app, pg_temp as $$
declare v_k text := app.inv_parts_kind(p_pct, p_bonus, p_info); e record; v numeric; s numeric := 0;
begin
  if p_gross is null or p_gross < 0 then return 'gross'; end if;
  if jsonb_typeof(p_parts) is distinct from 'object' then return 'shape'; end if;
  for e in select key, value from jsonb_each(p_parts) loop
    if e.key not in ('grant', 'monitoring100', 'monitoring20', 'teacher_child', 'siblings', 'referral', 'sick', 'other') then
      return 'kind:' || e.key;
    end if;
    if p_strict and e.key = 'other' then return 'other'; end if;
    if jsonb_typeof(e.value) <> 'number' then return 'value:' || e.key; end if;
    v := (e.value #>> '{}')::numeric;
    if v <= 0 then return 'value:' || e.key; end if;
    -- Holat bo'yicha bekor qilingan fakturada («[holat] …» izohi) 100 % turi izohdan aniqlanmaydi (eski qoidadagi «Monitoring 100»
    --   bonus ishorasisiz) — saqlangan grant / monitoring100 o'zgartirilmaydi.
    if e.key in ('grant', 'monitoring100', 'monitoring20', 'teacher_child', 'siblings') and e.key is distinct from v_k
       and not (coalesce(p_info, '') like '[holat]%' and e.key in ('grant', 'monitoring100') and v_k in ('grant', 'monitoring100')) then
      return 'category:' || e.key;
    end if;
    if e.key = 'sick' and v > coalesce(p_sick, 0) + 0.5 then return 'sick'; end if;
    s := s + v;
  end loop;
  if abs(p_gross - s - coalesce(p_amount, 0)) >= 0.5 then return 'sum'; end if;
  return null;
end $$;

-- Saqlangan maydonlardan tarkib (admin.html computeTuition tartibi: narx → toifa foizi → prorata → kasal kun → tavsiya).
--   Natija: {"g": yalpi, "p": {tur: so'm}, "x": aniqmi (saqlangan summa to'liq tushuntirildi)}.
create or replace function app.inv_parts_infer(p_amount numeric, p_base numeric, p_pct numeric, p_bonus text, p_info text,
                                               p_sick numeric) returns jsonb
language plpgsql immutable parallel safe set search_path = public, app, pg_temp as $$
declare
  a numeric := coalesce(p_amount, 0); b numeric := p_base; p numeric := coalesce(p_pct, 0); i text := coalesce(p_info, '');
  k text := app.inv_parts_kind(p_pct, p_bonus, p_info); m text[]; f float8 := 1; pr boolean := false;
  q numeric; n1 numeric; g numeric; c numeric := 0; s numeric := 0; r numeric := 0; x numeric; d numeric; t numeric;
  v jsonb := '{}'::jsonb;
begin
  -- Asosiy narx yo'q (chegirma ustunlaridan oldingi faktura): tarkib — faqat summa.
  if b is null or b <= 0 then return jsonb_build_object('g', a, 'p', '{}'::jsonb, 'x', true); end if;
  m := regexp_match(i, '(\d+)/(\d+) ish kuni \(prorata\)');
  if m is not null and m[2]::numeric > 0 and m[1]::numeric < m[2]::numeric then
    f := m[1]::float8 / m[2]::float8; pr := true;
  end if;
  -- toifa foizidan keyingi summa (kontrakt — belgilangan summaning o'zi, yaxlitlanmaydi)
  q := case when p >= 1 then 0
            when p = 0 and i ilike 'Kontrakt%' then b
            else app.inv_jsround(b::float8 * (1::float8 - p::float8)) end;
  n1 := case when pr and q > 0 then app.inv_jsround(q::float8 * f) else q end;   -- prorata dan keyin, kasal kundan oldin
  g := case when pr then app.inv_jsround(b::float8 * f) else b end;
  if k is not null and g - n1 > 0 then c := g - n1; else g := n1; end if;
  if coalesce(p_sick, 0) > 0 then s := least(p_sick, n1); end if;
  select coalesce(sum(z[1]::numeric), 0) into r from regexp_matches(i, 'Referral [−-]([0-9]+)', 'g') z;
  x := n1 - s - r - a;
  if abs(x) < 0.5 then
    g := g - x; x := 0;   -- yaxlitlash qoldig'i (kasrli eski summa) — yalpiga
  elsif x < 0 then        -- chegirma summadan katta ko'rsatilgan: kasal kun, tavsiya, toifa qismi tartibida kamaytiriladi
    d := -x;
    t := least(d, s); s := s - t; d := d - t;
    t := least(d, r); r := r - t; d := d - t;
    t := least(d, c); c := c - t; d := d - t;
    g := g + d;
  end if;
  if c > 0 then v := v || jsonb_build_object(k, c); end if;
  if s > 0 then v := v || jsonb_build_object('sick', s); end if;
  if r > 0 then v := v || jsonb_build_object('referral', r); end if;
  if x > 0 then v := v || jsonb_build_object('other', x); end if;
  return jsonb_build_object('g', g, 'p', v, 'x', x = 0);
end $$;

create or replace function app.inv_parts_set() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_exp boolean; v_money boolean; v_p jsonb; v_why text; v jsonb;
begin
  if tg_op = 'UPDATE' then
    v_exp := new."grossAmount" is distinct from old."grossAmount" or new."discountParts" is distinct from old."discountParts";
    v_money := (new.amount, new."baseAmount", new."pctApplied", new."sickAmount", new."bonusRef", new."discountInfo")
                 is distinct from (old.amount, old."baseAmount", old."pctApplied", old."sickAmount", old."bonusRef", old."discountInfo");
    if not v_exp and not v_money and new."grossAmount" is not null and jsonb_typeof(new."discountParts") = 'object' then
      return new;   -- to'lov qo'llanishi va boshqa belgilar
    end if;
  else
    v_exp := new."grossAmount" is not null or new."discountParts" is not null;
  end if;
  if new."grossAmount" is not null and jsonb_typeof(new."discountParts") = 'object' then
    v_p := app.inv_parts_norm(new."discountParts");
    v_why := app.inv_parts_check(new."grossAmount", v_p, new.amount, new."pctApplied", new."bonusRef", new."discountInfo",
                                 new."sickAmount", v_exp);
    if v_why is null then new."discountParts" := v_p; return new; end if;
  elsif new."grossAmount" is not null or new."discountParts" is not null then
    v_why := 'shape';
  end if;
  if v_exp and v_why is not null then
    raise warning 'Hisob-faktura % tarkibi qabul qilinmadi (%) — server saqlangan maydonlardan qayta hisobladi', new.id, v_why;
  end if;
  v := app.inv_parts_infer(new.amount, new."baseAmount", new."pctApplied", new."bonusRef", new."discountInfo", new."sickAmount");
  new."grossAmount" := (v ->> 'g')::numeric;
  new."discountParts" := v -> 'p';
  return new;
end $$;
revoke all on function app.inv_jsround(float8), app.inv_parts_kind(numeric, text, text), app.inv_parts_norm(jsonb),
  app.inv_parts_check(numeric, jsonb, numeric, numeric, text, text, numeric, boolean),
  app.inv_parts_infer(numeric, numeric, numeric, text, text, numeric), app.inv_parts_set() from public, anon, authenticated;
drop trigger if exists trg_invoice_zparts on public.invoices;
create trigger trg_invoice_zparts before insert or update on public.invoices for each row execute function app.inv_parts_set();

-- Eski fakturalar: tarkibi yo'q yoki mos kelmaydigan qatorlar — ikkala ustun NULL qilinadi, trigger saqlangan maydonlardan chiqaradi.
--   To'g'ri qatorlarga tegilmaydi. Natija: {"updated": yozilgan qatorlar, "inexact": 2026-11 dan amaldagi, saqlangan maydonlardan to'liq
--   tushuntirilmaganlar soni, "ids": ularning birinchi 30 tasi}. Faqat zanjir (tizim nomidan: davr qulfi va qo'riqchilar to'smaydi;
--   tarkib ustunlari o'zgarishlar tarixida yo'q) va sinov chaqiradi.
create or replace function app.inv_parts_backfill() returns jsonb
language plpgsql volatile set search_path = public, app, pg_temp as $$
declare v_n int; v_cnt int; v_ids text[];
begin
  select count(*) filter (where z.bad), (array_agg(z.id order by z.id) filter (where z.bad))[1:30] into v_cnt, v_ids
    from (select i.id,
                 not (app.inv_parts_infer(i.amount, i."baseAmount", i."pctApplied", i."bonusRef", i."discountInfo", i."sickAmount") ->> 'x')::boolean
                   and coalesce(i.month, '') >= '2026-11' and coalesce(i.status, '') not in ('canceled', 'reversed') as bad
            from public.invoices i
           where i."grossAmount" is null or jsonb_typeof(i."discountParts") is distinct from 'object'
              or app.inv_parts_check(i."grossAmount", i."discountParts", i.amount, i."pctApplied", i."bonusRef", i."discountInfo",
                                     i."sickAmount", false) is not null) z;
  update public.invoices i set "grossAmount" = null, "discountParts" = null
   where i."grossAmount" is null or jsonb_typeof(i."discountParts") is distinct from 'object'
      or app.inv_parts_check(i."grossAmount", i."discountParts", i.amount, i."pctApplied", i."bonusRef", i."discountInfo",
                             i."sickAmount", false) is not null;
  get diagnostics v_n = row_count;
  return jsonb_build_object('updated', v_n, 'inexact', v_cnt, 'ids', to_jsonb(coalesce(v_ids, '{}'::text[])));
end $$;
revoke all on function app.inv_parts_backfill() from public, anon, authenticated;

-- Har deployda. deploy.sh «OGOHLANTIRISH» qatorlarini chiqishda ko'rsatadi (faktura ID lari — ismsiz).
do $inv_parts$
declare r jsonb := app.inv_parts_backfill();
begin
  if (r ->> 'inexact')::int > 0 then
    raise notice 'OGOHLANTIRISH: faktura tarkibi (F2.7): % ta amaldagi fakturada (2026-11 dan) chegirmaning bir qismi saqlangan maydonlardan tushuntirilmadi — «izohsiz farq» (other) yoki kamaytirilgan qism bilan yozildi (summa o''zgarmagan). To''lanmaganlarini shu oy uchun «↻ Qayta hisoblash» aniq tarkib bilan yozadi; to''langanlarini buxgalter tasniflaydi. Fakturalar (30 tagacha): %',
      r ->> 'inexact', (select string_agg(x, ', ') from jsonb_array_elements_text(r -> 'ids') x);
  end if;
end $inv_parts$;
