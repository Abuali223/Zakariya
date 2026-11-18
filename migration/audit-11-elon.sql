\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-11-elon.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-11 (to'liq audit, 2026-11-18) — KABINET, SINF E'LONLARI, SAYT (sinovi: test-audit-11-elon.sql).
--
-- 1) XODIM HISOBIGA FARZAND BOG'LASH — DIREKTOR TASDIG'I BILAN (A7-01).
--    Muammo: O'IBDO' va qabulxona (asosiy yoki qo'shimcha lavozim) har o'quvchining maxfiy kodini ko'radi (student_codes sc_sel) va
--    claim_child bilan istalgan bolani o'z hisobiga ulab, uning baho, davomat, monitoring, sog'liq kartasi va hamshira yozuvlarini
--    «ota-ona» sifatida o'qiy olardi (RLS bu rollarga ularni bermaydi; haqiqiy ota-onaga xabar ham bormasdi).
--    Yechim: child_claims.status 'pending' (parent-student-links.sql shu holatni oldindan ko'zda tutgan). claim_child (payer-code-mask.sql)
--    kod ko'radigan xodimning bog'lanishini 'pending' yozadi; owns_child / owns_student_doc, Telegram, e'lonlar, avtobus faqat 'active'ni
--    hisoblaydi. Direktor «✅ Tasdiqlash» → «Xodim hisobiga farzand bog‘lash»da (admin.html) haqiqiy farzandi ekanini kartadagi ota-ona
--    ma'lumoti bilan solishtirib tasdiqlaydi (public.child_claim_decide — faqat Direktor; tasdiq: 'active' + approvedBy/approvedAt, rad:
--    bog'lanish o'chiriladi). Har qaror o'zgarishlar tarixiga yoziladi (child_claims change_log triggeri). Kod ko'rmaydigan xodim
--    (o'qituvchi, kurator, HR, kassir, hamshira…) va oddiy ota-ona — avvalgidek darhol; Direktor — darhol (u baribir hamma o'quvchini ko'radi).
--    HIMOYA TO'RI (har deployda, app.child_claims_review): kod ko'radigan xodim hisobidagi Direktor tasdiqlamagan FAOL bog'lanish ->
--    'pending' — bu tuzatishdan oldin claim_child orqali yozilganlari ham, keyin shunday lavozim berilgan hisobniki ham.
-- 2) E'LON TAHRIRLANSA — TELEGRAM NAVBATI HAM (A7-02). Navbat yozuvi (notify_queue 'ann__<id>') e'lon yozilganda nusxa (sinflar,
--    sarlavha, matn) oladi; tahrir (✏️) navbatga yetmasdi — tinch soatda yoki cron oralig'ida tuzatilgan e'lon (masalan, «Butun maktab»
--    adashib belgilanib, keyin 5-A ga o'zgartirilgan) Telegram'da ESKI matn bilan ESKI auditoriyaga (butun maktabga) ketardi. Endi hali
--    yuborilmagan ('pending') yozuv tahrir bilan yangilanadi. Yuborilgan xabar qayta yuborilmaydi (takror xabar bo'lmasin).
-- 3) ISHDAN KETGAN O'QITUVCHI (A7-05): teachers_public (ommaviy sayt «O‘qituvchilar» va kabinet «Ustozga reyting» ro'yxati) — holati
--    «chiqdi» va ketish kuni (stopFrom) o'tgan yoki yozilmagan o'qituvchisiz (ketish kunining o'zi hali ish kuni — kassa_emp_left /
--    child_card qoidasi). Qator maosh tarixi uchun saqlanadi — faqat ommaga ko'rinmaydi.
-- Amaldagi ta'rifi o'z faylida tahrirlangan (shu yerda emas): claim_child (payer-code-mask.sql), my_child_class_keys / ann_visible
--   (notify-settings.sql — A7-03, A7-04, A3-09), issue_doc_token (public-close.sql — A7-07), tg_unlink / tg_announce_recipients
--   (telegram.sql — A7-09, A3-09).
-- Idempotent (create or replace, add column if not exists, drop trigger if exists) — har deployda qayta ishga tushirishga xavfsiz.
-- =====================================================================

-- ---------- 1) Xodim hisobiga farzand bog'lash ----------
alter table public.child_claims add column if not exists "approvedBy" text;          -- tasdiqlagan Direktor (uid)
alter table public.child_claims add column if not exists "approvedAt" timestamptz;

-- Direktor qarori: p_approve = true — bog'lanish faollashadi (approvedBy — himoya to'ri uni qayta o'tkazmaydi); false — so'rov o'chiriladi
--   (xodim keyin yana so'rashi mumkin; har urinish to'g'ri kod bilan). Faqat 'pending' bog'lanish.
create or replace function public.child_claim_decide(p_id text, p_approve boolean) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_st text;
begin
  if not app.is_admin() then raise exception 'Farzand bog''lanishini faqat Direktor tasdiqlaydi' using errcode = '42501'; end if;
  if coalesce(p_id, '') = '' or p_approve is null then return jsonb_build_object('ok', false, 'reason', 'bad_request'); end if;
  select cc.status into v_st from public.child_claims cc where cc.id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if v_st is distinct from 'pending' then return jsonb_build_object('ok', false, 'reason', 'not_pending'); end if;
  if p_approve then
    update public.child_claims set status = 'active', "approvedBy" = app.uid(), "approvedAt" = now(), "updatedAt" = now() where id = p_id;
    return jsonb_build_object('ok', true, 'status', 'active');
  end if;
  delete from public.child_claims where id = p_id;
  return jsonb_build_object('ok', true, 'status', 'rejected');
end $$;
revoke all on function public.child_claim_decide(text, boolean) from public, anon;
grant execute on function public.child_claim_decide(text, boolean) to authenticated, service_role;

-- Himoya to'ri: kod ko'radigan xodim (O'IBDO' / qabulxona — asosiy yoki qo'shimcha lavozim; claim_child dagi qoida bilan bir xil, Direktor
--   kirmaydi) hisobidagi Direktor tasdiqlamagan FAOL bog'lanishlar -> 'pending'. Konservativ: faqat Direktor tasdig'ini qo'shadi; Direktor
--   tasdiqlagan (approvedBy) bog'lanishga tegmaydi — qayta chaqiruv hech narsani o'zgartirmaydi. O'tkazilgan bog'lanish ID'lari qaytariladi.
create or replace function app.child_claims_review() returns text[]
language plpgsql volatile security definer set search_path = public, app, pg_temp as $$
declare v text[];
begin
  with moved as (
    update public.child_claims cc set status = 'pending', "updatedAt" = now()
     where coalesce(nullif(cc.status, ''), 'active') = 'active' and cc."approvedBy" is null
       and exists (select 1 from public.users u where u.id = cc.uid
                    and (app.u_has(u.role, u."extraRoles", 'zavuch') or app.u_has(u.role, u."extraRoles", 'reception')))
    returning cc.id)
  select coalesce(array_agg(id order by id), '{}'::text[]) into v from moved;
  return v;
end $$;
revoke all on function app.child_claims_review() from public, anon, authenticated;

-- HAR DEPLOYDA (bir martalik emas). Zanjirda change_log yozilmaydi (iqror.migrating) — o'tkazilganlar shu NOTICE'da: bog'lanish ID'lari
--   (uid__studentId; ism / kod yo'q; birinchi 20 tasi, qolgani «… yana N»). > 0 bo'lsa — «OGOHLANTIRISH: » (deploy.sh chiqishida ko'rinadi).
do $$
declare v text[]; n int;
begin
  v := app.child_claims_review(); n := coalesce(cardinality(v), 0);
  if n > 0 then
    raise notice 'OGOHLANTIRISH: % ta farzand bog''lanishi (o''quvchi kodlarini ko''radigan xodim hisobi — O''IBDO'' / qabulxona) Direktor tasdig''iga o''tkazildi: % — «✅ Tasdiqlash» → «Xodim hisobiga farzand bog‘lash»da ko''rib chiqing',
      n, array_to_string(v[1:20], ', ') || case when n > 20 then ', … yana ' || (n - 20) else '' end;
  else
    raise notice 'Farzand bog''lanishlari: Direktor tasdig''iga o''tkaziladigan xodim bog''lanishi yo''q (0)';
  end if;
end $$;

-- ---------- 2) E'lon tahrirlansa — Telegram navbatidagi nusxa ham ----------
-- Faqat sinflar / sarlavha / matn o'zgarganda (📌 qadash, muddat — Telegram matniga kirmaydi). Xato yutilmaydi: navbat yangilanmay
--   qolsa, eski matn eski auditoriyaga ketardi — undan ko'ra tahrir rad etilsin (bitta qatorli yangilash, amalda xato bermaydi).
create or replace function app.tg_requeue_announce() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if new."classKeys" is distinct from old."classKeys" or new.title is distinct from old.title or new.body is distinct from old.body then
    update public.notify_queue
       set payload = coalesce(payload, '{}'::jsonb) || jsonb_build_object('classKeys', new."classKeys", 'title', new.title, 'body', new.body)
     where id = 'ann__' || new.id and status = 'pending';
  end if;
  return null;
end $$;
revoke all on function app.tg_requeue_announce() from public, anon, authenticated;
drop trigger if exists trg_tg_requeue_announce on public.class_announcements;
create trigger trg_tg_requeue_announce after update of "classKeys", title, body on public.class_announcements
  for each row execute function app.tg_requeue_announce();

-- ---------- 3) Ishdan ketgan o'qituvchi ommaviy ro'yxatda yo'q ----------
-- Ustunlar staff-access.sql dagi bilan AYNAN bir xil (ko'rinish ustuni o'chirilmaydi / o'zgarmaydi). Bugun — Toshkent kuni (anon uchun
--   app.* funksiyasiz: ko'rinishdagi funksiyani chaqiruvchining o'zi bajara olishi kerak).
create or replace view public.teachers_public as
  select id, name, photo, "subject_uz", "subject_ru",
         rating, years, certs, avg, votes, "order"
  from public.teachers t
  where not (coalesce(t."payStatus", '') = 'chiqdi'
             and not (left(coalesce(t."stopFrom", ''), 10) ~ '^\d{4}-\d{2}-\d{2}$'
                      and left(t."stopFrom", 10) >= to_char(now() at time zone 'Asia/Tashkent', 'YYYY-MM-DD')));
grant select on public.teachers_public to anon, authenticated;
revoke all on public.teachers_public from public;
grant select on public.teachers_public to service_role;

notify pgrst, 'reload schema';
