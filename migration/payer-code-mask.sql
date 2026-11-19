\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: payer-code-mask.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- payer-code-mask.sql — TO'LOVCHI MATNIDAGI MAXFIY KOD (egasi qarori (a), 2026-11-16; SESSIYA-ISHLARI.md §76 «Qolgan ishlar» (1)).
--
--   MUAMMO: o'quvchining maxfiy kodi (student_codes) ikki ishda: ota-ona farzandini ulaydi (claim_child: ID + kod) va Click /
--   Uzum'da «ID KOD» yoki «KOD» yozib to'laydi. To'lov serveri to'lovchi matnini (merchant_trans_id, payerName, payerClass,
--   payerPhone, Uzum so'rovi — raw) payments qatoriga AYNAN saqlardi; uni moliya menejeri, g'aznachi va kassir to'liq o'qiydi ->
--   (o'quvchi, kod) juftini bilib, istalgan hisobdan claim_child chaqira olardi.
--   YECHIM (a): kod to'lov yozuvlarida «[kod]» bo'lib saqlanadi (yangi yozuv — payments/index.cjs, eskisi — shu fayl), ochilib
--   qolgan kodlar almashtiriladi. Eski kod faqat TO'LOV uchun ishlayveradi (saqlangan Click / Uzum to'lovlari avtomatik
--   biriktirilsin); farzand ulash uchun — yo'q: claim_child eski kodga reason = 'code_changed' qaytaradi (urinish sanaladi).
--
--   1) public.student_code_prev — almashtirilgan kodlar. FAQAT server (to'lov serveri service_role bilan o'qiydi): RLS yoqilgan,
--      anon / authenticated'ga huquq yo'q (Direktorga ham — ekranda kerak emas). student_codes.code o'zgarganda eski kod shu
--      yerga yoziladi (trg_student_code_prev) — faqat shu tranzaksiya boshlanishidan OLDIN joriy bo'lgan (ota-onaga berilgan) kod:
--      shu tranzaksiyada yozilgan kod (yangi o'quvchiga berilgan, tiklashdagi oraliq kod, zanjirda security-2b bergan 6 belgili
--      kod — audit-4 uni 12 ga uzaytiradi) va 12 belgidan qisqa kod yozilmaydi. O'quvchi kodi qatori o'chsa — uning eski kodlari
--      ham o'chadi (FK cascade).
--   2) app.new_student_code() — yangi kod: 12 ta 0-9/A-F (avvalgi shakl), kamida bitta harf A–F (to'lov serverining bazasiz
--      shakl qoidasi har yangi kodni taniydi), kriptografik tasodif (gen_random_uuid), joriy va eski kodlarning hech biriga teng
--      emas. app.gen_student_code (audit-4.sql) shu bilan QAYTA ta'riflanadi.
--   3) app.claim_row (parent-link-canon.sql): to'qnash kalitli bog'lanish eski kod bilan ham o'z qatoriga tegishli bo'lib qoladi —
--      kod almashsa ulangan ota-ona uzilmaydi (audit-4 qoidasi). public.claim_child: faqat JORIY kod ulaydi (o'zgarmagan), shu
--      o'quvchining eski kodi kiritilsa — alohida javob ('code_changed'), urinish lockout'ga sanaladi.
--      DIQQAT: claim_row, claim_child, gen_student_code va restore_deleted_student'ning AMALDAGI ta'rifi SHU faylda — oldingi
--      fayllardagisi shu yerda almashtiriladi (o'zgartirish kerak bo'lsa — shu yerda).
--   4) app.payer_mask* — yashirish qoidasi (payments/index.cjs bilan AYNAN bir xil): bo'lak — harf / raqamning uzluksiz qatori;
--      bo'laklar qatori — orasida ajratgich bo'lgan bo'laklar; ajratgich — 1–2 ta belgi (bo'sh joy, tab, «.», «,», «-», «_», «/») yoki
--      3 tagacha bo'sh joy belgisi (bo'sh joy, tab, yangi qator, bo'linmas bo'sh joy): «3FA9 C21B 7D0E», «3FA9  C21B  7D0E»,
--      «3FA9_C21B_7D0E», «3FA9/C21B/7D0E», «3FA9, C21B, 7D0E», qatorma-qator yozilgan kod. Bo'lak (katta harfda yoki kodga o'xshash
--      harflar normallangan holda) kodga teng bo'lsa yoki qator bo'laklari ulanganda undagi 12 belgili 0-9/A-F oyna kodga teng bo'lsa —
--      kod va qatorda unga yondosh HEX-shaklli bo'laklar (oradagi ajratgichlar bilan) bitta «[kod]» (kodning bir belgisi farq qiladigan
--      nusxasi ham ochiq qolmasin). IQ-0042 kabi ID (to'lov serveri taniydigan har yozilishi: «IQ+0043», «IQ = 0043», «ИҚ-0043» —
--      app.payer_idnum) va hex bo'lmagan bo'lak (ism, so'z) o'zgarmaydi.
--      app.payer_codes_fix() — tuzatish: (0) student_code_prev dagi 12 belgidan qisqa (hech kimga berilmagan) yozuvlar o'chiriladi;
--      (1) to'lovchi matnida (payments matn maydonlari va raw, refunds."studentName" — biriktirilmagan to'lov qaytarilganda
--      payerName nusxasi) JORIY kodi uchragan o'quvchilarga yangi kod; (2) shu matnlardagi har joriy / eski kod -> «[kod]»;
--      (3) ochilgan kod bilan ulangan faol bog'lanishlar (child_claims) sanaladi — bog'lanishning o'ziga tegilmaydi. Idempotent
--      (qayta chaqirilsa hech narsa o'zgarmaydi). Har deployda ikki marta: zanjirda va deploy.sh 6/7 dan keyin (to'lov serveri qayta
--      ishga tushgach — oraliqda eski server yozgan matn uchun). NOTICE — faqat sonlar (app.payer_codes_fix_notice).
--   5) restore_deleted_student (admission-crm.sql): o'chirilgan o'quvchi tiklanganda qaytgan kod to'lovchi matnida ochiq bo'lsa (o'quvchi
--      yo'q paytda kelgan to'lov — server kodni taniy olmagan) — darhol yangi kod, eskisi student_code_prev ga (app.payer_code_exposed).
--   To'lovlar triggerlari: matn yozuvi migratsiya / server nomidan (app.is_system()) — davr qulfi (trg_fin_zlock) va kassa
--   qo'riqchisi (trg_kassa_pay_guard) uni o'tkazadi, holat / o'quvchi / summa o'zgarmaydi (Telegram navbati, tavsiya bonusi
--   triggerlari ishlamaydi), o'zgarishlar tarixi zanjirda yozilmaydi (iqror.migrating). Oddiy foydalanuvchi uchun hech bir trigger
--   yumshatilmaydi.
-- Idempotent (run-all.sql zanjirida; parent-link-canon.sql, audit-4.sql dan KEYIN).
-- =====================================================================

-- ---------- 1) Almashtirilgan kodlar ----------
create table if not exists public.student_code_prev (
  code           text primary key,                 -- KATTA harf bilan (student_codes kabi)
  "studentDocId" text not null references public.student_codes(id) on delete cascade on update cascade,
  "retiredAt"    timestamptz not null default now()
);
create index if not exists student_code_prev_sid_idx on public.student_code_prev ("studentDocId");
alter table public.student_code_prev enable row level security;
revoke all on public.student_code_prev from public, anon, authenticated;   -- supabase-grants.sql har zanjirda hamma jadvalga beradi
grant all on public.student_code_prev to service_role;

-- ---------- 2) Kod yaratish ----------
create or replace function app.new_student_code() returns text
language plpgsql volatile set search_path = public, app, pg_temp as $$
declare c text; n int := 0;
begin
  loop
    c := upper(left(replace(gen_random_uuid()::text, '-', ''), 12));   -- UUID v4 ning dastlabki 12 belgisi — to'liq tasodifiy
    exit when c ~ '[A-F]'                                                -- faqat raqamli kod (~0,4%) berilmaydi (shakl qoidasi uchun)
          and not exists (select 1 from public.student_codes sc where upper(sc.code) = c)
          and not exists (select 1 from public.student_code_prev pc where pc.code = c);
    n := n + 1;
    if n >= 20 then raise exception 'Yangi o''quvchi kodi yaratilmadi (takrorlanish)'; end if;
  end loop;
  return c;
end $$;
revoke all on function app.new_student_code() from public, anon, authenticated;

-- Shu tranzaksiyada yozilgan (ota-onaga hali berilmagan) kodlar: iqror.code_fresh — «,KOD1,KOD2,» (tranzaksiya oxirigacha; butun
--   deploy zanjiri BITTA tranzaksiya, shuning uchun bitta umumiy belgi emas — har kod alohida: boshqa o'quvchining yangi kodi
--   haqiqiy almashtirishni yashirmaydi). Bunday kod almashtirilsa student_code_prev ga yozilmaydi.
create or replace function app.code_fresh_add(p_code text) returns void
language sql volatile set search_path = public, app, pg_temp as $$
  select set_config('iqror.code_fresh', coalesce(nullif(current_setting('iqror.code_fresh', true), ''), ',') || upper(p_code) || ',', true)
$$;
revoke all on function app.code_fresh_add(text) from public, anon, authenticated;

-- AFTER INSERT (students) — faqat HAQIQATAN yangi o'quvchi qatori uchun (upsert'ning UPDATE yo'li ishga tushirmaydi). Shu id bilan
--   ESKI (o'chirilgan o'quvchidan qolgan) kod bo'lsa — YANGI kod beriladi: aks holda yangi bola eski oilaga berilgan kodni meros olib,
--   o'sha oila uni bog'lab olardi. Eski kod va uning almashtirilgan kodlari yangi bolaga o'tmaydi (to'lovda ham unga tushmaydi):
--   ular o'chiriladi, arvoh kod esa «shu tranzaksiyaniki» deb belgilanadi — almashtirish triggeri uni saqlamaydi.
create or replace function app.gen_student_code() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_old text;
begin
  delete from public.student_code_prev where "studentDocId" = NEW.id;
  select sc.code into v_old from public.student_codes sc where sc.id = NEW.id;
  if coalesce(v_old, '') <> '' then perform app.code_fresh_add(v_old); end if;
  insert into public.student_codes(id, code, "updatedAt")
    values (NEW.id, app.new_student_code(), now())
    on conflict (id) do update set code = excluded.code, "updatedAt" = now();
  return NEW;
end $$;
revoke all on function app.gen_student_code() from public, anon, authenticated;

-- student_codes.code yozilsa (yangi qator, almashtirish, qo'lda SQL, tiklash): eski kod student_code_prev ga (to'lovda ishlayversin) —
--   faqat tranzaksiya boshlanishidan oldin joriy bo'lgan, 12 belgili kod (yuqoridagi iqror.code_fresh'da yo'q). Yangi kod shu
--   o'quvchining eski kodi bo'lsa — u yana joriy: ro'yxatdan chiqadi; aks holda yangi kod «shu tranzaksiyaniki» deb belgilanadi.
create or replace function app.student_code_retire() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_new text := upper(coalesce(new.code, '')); v_old text := '';
begin
  if tg_op = 'UPDATE' then v_old := upper(coalesce(old.code, '')); end if;
  if v_old = v_new then return null; end if;
  if length(v_old) >= 12   -- qisqasi: security-2b bergan, audit-4 uzaytiradigan oraliq kod (12 belgidan beri hamma kod 12 belgili)
     and position(',' || v_old || ',' in coalesce(current_setting('iqror.code_fresh', true), '')) = 0 then
    insert into public.student_code_prev (code, "studentDocId", "retiredAt") values (v_old, new.id, now())
      on conflict (code) do update set "studentDocId" = excluded."studentDocId", "retiredAt" = excluded."retiredAt";
  end if;
  if v_new <> '' then
    delete from public.student_code_prev where code = v_new and "studentDocId" = new.id;
    if not found then perform app.code_fresh_add(v_new); end if;
  end if;
  return null;
end $$;
revoke all on function app.student_code_retire() from public, anon, authenticated;
drop trigger if exists trg_student_code_prev on public.student_codes;
create trigger trg_student_code_prev after insert or update of code on public.student_codes
  for each row execute function app.student_code_retire();

-- ---------- 3) Ota-ona bog'lanishi ----------
-- claim_row(kalit, kod) — parent-link-canon.sql bilan bir xil, faqat to'qnash kalitda bog'lanishdagi kod qatorning JORIY kodi YOKI
--   shu qatorning almashtirilgan (eski) kodi bo'lsa ham — o'sha qator (bog'lanish o'sha kod joriy paytda claim_child orqali yozilgan).
create or replace function app.claim_row(p_key text, p_code text) returns text
language sql stable security definer set search_path = public, app, pg_temp as $$
  select case
    when (select count(*) from public.students s where s.id = p_key or s."studentId" = p_key) = 1
      then (select s.id from public.students s where s.id = p_key or s."studentId" = p_key)
    when coalesce(p_code, '') <> '' then (
      select min(s.id) from public.students s join public.student_codes sc on sc.id = s.id
       where (s.id = p_key or s."studentId" = p_key)
         and (upper(sc.code) = upper(p_code)
              or exists (select 1 from public.student_code_prev pc where pc."studentDocId" = s.id and pc.code = upper(p_code)))
      having count(*) = 1)
  end
$$;
revoke all on function app.claim_row(text, text) from public, anon;
grant execute on function app.claim_row(text, text) to authenticated, service_role;

-- claim_child — parent-link-canon.sql bilan bir xil; yangi: shu o'quvchining ESKI kodi kiritilsa — reason 'code_changed' (ulanmaydi,
--   urinish muvaffaqiyatsiz deb sanaladi — lockout o'zgarmagan).
--   KOD KO'RADIGAN XODIM (audit-11, A7-01): O'IBDO' va qabulxona (asosiy yoki qo'shimcha lavozim — student_codes sc_sel) HAR bolaning
--   kodini ko'radi, shuning uchun to'g'ri kod ularning ota-onaligini isbotlamaydi: avval istalgan bolani o'z hisobiga ulab, uning baho,
--   davomat, monitoring, sog'liq kartasi va hamshira yozuvlarini «ota-ona» sifatida o'qiy olardi (RLS bu rollarga ularni bermaydi).
--   Endi ularning bog'lanishi 'pending' yoziladi — owns_child, Telegram va e'lonlar faqat 'active'ni hisoblaydi; Direktor haqiqiy farzandi
--   ekanini tekshirib «✅ Tasdiqlash»da tasdiqlaydi (child_claim_decide, audit-11-elon.sql). Javob: ok=false, pending=true. Direktor
--   kutmaydi (u baribir hamma o'quvchini ko'radi — bog'lanish unga yangi huquq bermaydi); oddiy ota-ona va boshqa xodim — avvalgidek.
create or replace function public.claim_child(p_sid text, p_code text)
returns jsonb language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_fails int; v_ok boolean; v_canon text; v_doc text; v_sidraw text; v_n int; v_review boolean;
begin
  if v_uid is null then
    raise exception 'auth required' using errcode = '42501';
  end if;
  -- Bloklangan hisob (user-block.sql) farzand biriktira olmaydi — muddati tugamagan JWT bilan ham (urinish sanalmaydi).
  if exists (select 1 from public.users u where u.id = v_uid and u.status = 'blocked') then
    return jsonb_build_object('ok', false, 'blocked', true,
      'error', 'Hisobingiz bloklangan. Maktab ma''muriyatiga murojaat qiling.');
  end if;
  -- Buxgalter hisobi farzand biriktirmaydi (moliya rejasi F1.21, D6): bu ish hisobi o'quvchi ma'lumotiga ota-ona huquqini olmasin —
  --   maktab buxgalteri ota-ona bo'lsa, alohida ota-ona hisobidan foydalanadi.
  --   «Sotuvchi» (sales-role.sql) — xuddi shunday: ish hisobi faqat ota-onalar ismi va telefonini ko'radi, farzand ma'lumotini emas.
  if app.my_role() in ('accountant', 'sales') then
    return jsonb_build_object('ok', false, 'error', case when app.my_role() = 'sales'
      then 'Sotuvchi hisobiga farzand biriktirilmaydi — ota-ona hisobidan foydalaning.'
      else 'Buxgalter hisobiga farzand biriktirilmaydi — ota-ona hisobidan foydalaning.' end);
  end if;
  p_sid := btrim(coalesce(p_sid, ''));
  -- Lockout: oxirgi 15 daqiqada 5+ MUVAFFAQIYATSIZ urinish -> bloklash.
  select count(*) into v_fails
    from public.child_claim_attempts
   where uid = v_uid and ok = false and "at" > now() - interval '15 minutes';
  if v_fails >= 5 then
    insert into public.child_claim_attempts(uid, "studentId", ok) values (v_uid, p_sid, false);
    return jsonb_build_object('ok', false, 'locked', true,
      'error', 'Juda ko''p urinish. 15 daqiqadan so''ng qayta urinib ko''ring.');
  end if;
  -- Kod AYNAN qaysi o'quvchi qatoriga tegishli (kod doc id bilan saqlanadi) — bog'lanish faqat SHU qatorga
  --   (avval kalit alohida qidirilib, bo'sh/to'qnash ID'da boshqa bolaga bog'lanib qolishi mumkin edi).
  select count(*), min(s.id) into v_n, v_doc
    from public.students s join public.student_codes sc on sc.id = s.id
   where p_sid <> '' and coalesce(p_code, '') <> '' and upper(sc.code) = upper(p_code)
     and (s.id = p_sid or s."studentId" = p_sid);
  v_ok := (v_n = 1);
  insert into public.child_claim_attempts(uid, "studentId", ok) values (v_uid, p_sid, v_ok);
  if not v_ok then
    -- Shu o'quvchining almashtirilgan (eski) kodi: ulanmaydi (faqat joriy kod), lekin ota-onaga aniq sabab — yangi kodni maktabdan oladi.
    if v_n = 0 and p_sid <> '' and coalesce(p_code, '') <> '' and exists (
         select 1 from public.students s join public.student_code_prev pc on pc."studentDocId" = s.id
          where (s.id = p_sid or s."studentId" = p_sid) and pc.code = upper(p_code)) then
      return jsonb_build_object('ok', false, 'reason', 'code_changed',
        'error', 'Bu kod almashtirilgan — yangi kodni maktabdan oling.');
    end if;
    return jsonb_build_object('ok', false, 'error', 'O''quvchi ID yoki kod noto''g''ri.');
  end if;
  -- KANONIK kalit (invoices/attendance/… shu bilan kalitlangan): studentId, bo'sh bo'lsa doc id — kod tekshirilgan qatordan.
  select coalesce(nullif(s."studentId", ''), s.id), s."studentId" into v_canon, v_sidraw from public.students s where s.id = v_doc;
  if not app.student_keys_unique(v_doc, v_sidraw) then
    return jsonb_build_object('ok', false, 'error',
      'Bu o''quvchi ID''si boshqa o''quvchi bilan takrorlangan — maktab ma''muriyatiga murojaat qiling.');
  end if;
  -- Kod ko'radigan xodim — Direktor tasdig'igacha 'pending' (yuqoridagi izoh). Javob bog'lanishning HAQIQIY holatidan: avvalgi so'rov
  --   hali kutilayotgan bo'lsa — yana «kutmoqda» (ikkinchi qator yaratilmaydi), Direktor tasdiqlagan bo'lsa — ok.
  v_review := app.is_zavuch() or app.is_reception();
  -- Avval bekor qilingan bog'lanish (masalan, hisob vaqtincha «Sotuvchi» bo'lgan, keyin ota-onaga qaytarilgan) JORIY to'g'ri kod bilan
  --   yangi so'rovdek qayta ochiladi (aks holda «on conflict do nothing» uni 'revoked' qoldirib, ok qaytarardi va kabinet «kod
  --   noto'g'ri» derdi). Qo'riqchi (child_claim_staff_gate) ish hisobini rad etadi, kod ko'radigan xodimni 'pending' qiladi.
  update public.child_claims
     set status = case when v_review then 'pending' else 'active' end, code = p_code,
         "approvedBy" = null, "approvedAt" = null, "updatedAt" = now()
   where uid = v_uid and "studentId" = v_canon and status = 'revoked';
  insert into public.child_claims(id, uid, "studentId", code, status)
    values (v_uid || '__' || v_canon, v_uid, v_canon, p_code, case when v_review then 'pending' else 'active' end)
    on conflict do nothing;
  if exists (select 1 from public.child_claims cc where cc.uid = v_uid and cc."studentId" = v_canon and cc.status = 'pending') then
    return jsonb_build_object('ok', false, 'pending', true, 'studentId', v_canon,
      'error', 'Farzand bog''lanishi Direktor tasdig''ini kutmoqda (o''quvchi kodlarini ko''radigan xodim hisobi). Tasdiqlangach farzandingiz kabinetda ko''rinadi.');
  end if;
  return jsonb_build_object('ok', true, 'studentId', v_canon);
end $$;
revoke all on function public.claim_child(text, text) from public, anon;
grant execute on function public.claim_child(text, text) to authenticated;

-- ---------- 4) Yashirish qoidasi ----------
-- Kodga o'xshash harflar: kiril А, Б / В, С, Д, Е, Ф va O (kiril / lotin — nol o'rniga yozilgan) -> 0-9/A-F; so'ng KATTA harf.
create or replace function app.payer_norm(p text) returns text
language sql immutable set search_path = public, app, pg_temp as $$
  select upper(translate(p, 'АаБбВвСсДдЕеФфОоOo', 'AABBBBCCDDEEFF0000'))
$$;
-- IQ-ID raqami (payments/index.cjs kodIdNum bilan AYNAN bir xil): matnning p_at (1 dan) o'rnidagi bo'lak raqam bilan boshlanadi va undan
--   oldingi matn (40 belgigacha) IQ belgisi bilan tugaydi — «IQ» + «-» / «_» / «–» / «—» (+ 2 tagacha bo'sh joy / «_» / «-») yoki oldida
--   harf yo'q «IQ», «ІQ», «IҚ», «ІҚ», «ИҚ», «ИК» (katta-kichik harf) + 3 tagacha boshqa belgi (atrofida bo'sh joylar): «IQ+0043»,
--   «IQ = 0043», «ИҚ-0043», «ІQ-0043» (to'lov serveridagi SID_IQ qoidasi). Harf / son — U+0000–U+052F dagi ro'yxat, bo'sh joy — JS \s
--   ro'yxati (JS bilan bir xil natija uchun; PostgreSQL regexida \p{…} yo'q).
create or replace function app.payer_idnum(p text, p_at int) returns boolean
language sql immutable set search_path = public, app, pg_temp as $$
  select substr(p, p_at, 1) ~ '^[0-9]$'
     and substr(p, greatest(1, p_at - 40), p_at - greatest(1, p_at - 40)) ~ (
       '(?:[Ii][Qq][-_\u2013\u2014][\u0009-\u000D \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF_-]{0,2}'
       || '|(?:^|[^A-Za-z\u00AA\u00B5\u00BA\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0345\u0370-\u0374'
       ||        '\u0376\u0377\u037A-\u037D\u037F\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u052F])'
       || '(?:[Ii][Qq]|[\u0406\u0456][Qq]|[Ii][\u049A\u049B]|[\u0406\u0456][\u049A\u049B]|[\u0418\u0438][\u049A\u049B]|[\u0418\u0438][\u041A\u043A])'
       || '(?:[\u0009-\u000D \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]{0,3}'
       ||    '[^A-Za-z\u00AA\u00B5\u00BA\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0345\u0370-\u0374'
       ||     '\u0376\u0377\u037A-\u037D\u037F\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u052F'
       ||     '0-9\u00B2\u00B3\u00B9\u00BC-\u00BE\u0009-\u000D \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]){0,3}'
       || '[\u0009-\u000D \u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]{0,3})$')
$$;
-- Matndagi kodlarni (p_codes — KATTA harfli kodlar) «[kod]» bilan almashtiradi; qolgan matn (ajratgichlar ham) AYNAN saqlanadi.
--   Bo'laklar qatori bo'yicha (payments/index.cjs kodMaskRun / kodWiden bilan bir xil): kodga teng bo'lak yoki ulangan qatordagi
--   12 belgili 0-9/A-F oyna — kod belgilari (oradagi ajratgichlar bilan); so'ng kengaytiriladi: kod turgan bo'lakdan chapga va o'ngga
--   qatordagi HEX-shaklli (normallangan: faqat 0-9/A-F) bo'laklar ham (kod bo'lak o'rtasida bo'lsa — bo'lakning kod oldidagi / ortidagi
--   qismi ham hex bo'lsagina); hex bo'lmagan bo'lakda va IQ-ID raqamida (qatorda «IQ» dan keyingi yoki IQ belgisidan keyingi —
--   app.payer_idnum — faqat raqamli bo'lak; shunday bo'lakdagi kodning oldi) to'xtaydi. Hammasi bitta «[kod]»: «IQ-0042 3FA9 C21B 7D0E»
--   -> «IQ-0042 [kod]», «IQ+0043 3FA9 C21B 7D0E» -> «IQ+0043 [kod]», «3FA9C21B7D0E 3FA9C21B7D0F» -> «[kod]», «Sinov Ali 3FA9C21B7D0E» ->
--   «Sinov Ali [kod]», «IQ00423FA9C21B7D0E» -> «IQ0042[kod]».
create or replace function app.payer_mask(p text, p_codes text[]) returns text
language plpgsql immutable set search_path = public, app, pg_temp as $$
declare m text[]; v_out text := ''; v_run text; v_tok text; v_j text; v_w text; v_pos int[]; v_at int[]; v_base boolean[]; v_mk boolean[];
        v_ts int[]; v_te int[]; v_tu text[]; v_tn text[]; n int; nt int; i int; k int; ts int; a int; b int; x int; y int; v_off int := 0;
begin
  if p is null or p = '' or p_codes is null or cardinality(p_codes) = 0 then return p; end if;
  -- qatorlar va oradagi matn ketma-ket butun matnni qoplaydi: v_off — joriy qatordan oldingi belgilar soni (app.payer_idnum uchun)
  for m in select regexp_matches(p, '([0-9A-Za-zА-Яа-яЁё]+(?:(?:[ \t.,_/-]{1,2}|[ \t\r\n\u00A0]{1,3})[0-9A-Za-zА-Яа-яЁё]+)*)|([^0-9A-Za-zА-Яа-яЁё]+)', 'g') loop
    if m[1] is null then v_out := v_out || m[2]; v_off := v_off + length(m[2]); continue; end if;
    v_run := m[1]; n := length(v_run); v_base := array_fill(false, array[n]); v_at := array_fill(0, array[n]);
    v_pos := '{}'; v_j := ''; v_ts := '{}'; v_te := '{}'; v_tu := '{}'; v_tn := '{}'; nt := 0; i := 1;
    while i <= n loop                                   -- bo'laklar: kodga tengini belgilash, ulangan normallangan matn (v_j)
      if substr(v_run, i, 1) !~ '[0-9A-Za-zА-Яа-яЁё]' then i := i + 1; continue; end if;   -- qator ichidagi ajratgich
      ts := i; nt := nt + 1;
      while i <= n and substr(v_run, i, 1) ~ '[0-9A-Za-zА-Яа-яЁё]' loop v_pos := v_pos || i; v_at[i] := nt; i := i + 1; end loop;
      v_tok := substr(v_run, ts, i - ts);
      v_ts := v_ts || ts; v_te := v_te || (i - 1); v_tu := v_tu || upper(v_tok); v_tn := v_tn || app.payer_norm(v_tok);
      v_j := v_j || app.payer_norm(v_tok);
      if upper(v_tok) = any(p_codes) or app.payer_norm(v_tok) = any(p_codes) then
        for k in ts .. i - 1 loop v_base[k] := true; end loop;
      end if;
    end loop;
    for i in 1 .. length(v_j) - 11 loop                -- ulangan qatordagi 12 belgili oyna (bo'lak ichida ham)
      v_w := substr(v_j, i, 12);
      if v_w ~ '^[0-9A-F]{12}$' and v_w = any(p_codes) then
        for k in v_pos[i] .. v_pos[i + 11] loop v_base[k] := true; end loop;
      end if;
    end loop;
    v_mk := array_fill(false, array[n]); a := 1;       -- kengaytirish (kodWiden)
    while a <= n loop
      if not v_base[a] then a := a + 1; continue; end if;
      b := a; while b < n and v_base[b + 1] loop b := b + 1; end loop;
      x := a; y := b; k := v_at[a];
      -- IQ-ID raqami (kodWiden idPos): qatorda «IQ» dan keyingi yoki IQ belgisidan keyingi bo'lak
      if not ((k > 1 and v_tu[k - 1] = 'IQ') or app.payer_idnum(p, v_off + v_ts[k])) and substr(v_tn[k], 1, a - v_ts[k]) ~ '^[0-9A-F]*$' then
        x := v_ts[k]; k := k - 1;
        while k >= 1 and v_tn[k] ~ '^[0-9A-F]+$'
              and not (v_tn[k] ~ '^[0-9]+$' and ((k > 1 and v_tu[k - 1] = 'IQ') or app.payer_idnum(p, v_off + v_ts[k]))) loop
          x := v_ts[k]; k := k - 1;
        end loop;
      end if;
      k := v_at[b];
      if substr(v_tn[k], b - v_ts[k] + 2) ~ '^[0-9A-F]*$' then
        y := v_te[k]; k := k + 1;
        while k <= nt and v_tn[k] ~ '^[0-9A-F]+$'
              and not (v_tn[k] ~ '^[0-9]+$' and ((k > 1 and v_tu[k - 1] = 'IQ') or app.payer_idnum(p, v_off + v_ts[k]))) loop
          y := v_te[k]; k := k + 1;
        end loop;
      end if;
      for i in x .. y loop v_mk[i] := true; end loop;
      a := b + 1;
    end loop;
    for k in 1 .. n loop
      if not v_mk[k] then v_out := v_out || substr(v_run, k, 1);
      elsif k = 1 or not v_mk[k - 1] then v_out := v_out || '[kod]'; end if;
    end loop;
    v_off := v_off + n;
  end loop;
  return v_out;
end $$;
-- jsonb (Uzum so'rovi — raw): har satr va son qiymati (kalitlar — provayderniki, tegilmaydi).
create or replace function app.payer_mask_json(j jsonb, p_codes text[]) returns jsonb
language plpgsql immutable set search_path = public, app, pg_temp as $$
declare v_t text; v_m text;
begin
  if j is null or p_codes is null or cardinality(p_codes) = 0 then return j; end if;
  case jsonb_typeof(j)
    when 'object' then
      return coalesce((select jsonb_object_agg(e.key, app.payer_mask_json(e.value, p_codes)) from jsonb_each(j) e), '{}'::jsonb);
    when 'array' then
      return coalesce((select jsonb_agg(app.payer_mask_json(e.value, p_codes) order by e.n)
                         from jsonb_array_elements(j) with ordinality e(value, n)), '[]'::jsonb);
    when 'string', 'number' then
      v_t := j #>> '{}';
      v_m := app.payer_mask(v_t, p_codes);
      if v_m is distinct from v_t then return to_jsonb(v_m); end if;
      return j;
    else
      return j;
  end case;
end $$;
revoke all on function app.payer_norm(text), app.payer_idnum(text, int), app.payer_mask(text, text[]), app.payer_mask_json(jsonb, text[])
  from public, anon, authenticated;

-- ---------- 5) Tuzatish ----------
-- To'lovchi matnlaridagi qidiruv kalitlari (payments/index.cjs kodKeys bilan bir xil): r_kind — 'p' (payments) / 'r' (refunds), r_id —
--   yozuv, r_key — kalit: 5–16 belgili bo'lak (KATTA harfda va kodga o'xshash harflar normallangan holda) va bo'laklar qatori (ajratgich —
--   app.payer_mask dagi kabi) ulanib normallanganda undagi har 12 belgili 0-9/A-F oyna (bitta uzun bo'lak ichida ham). Bir qatorning
--   maydonlari bitta matnga «|» bilan ulanadi (ajratgich emas — qator maydon chegarasidan o'tmaydi; yangi qator esa ajratgich); raw —
--   faqat satr va son qiymatlari, har biri alohida (app.payer_mask_json bilan bir xil). Hammasi bitta so'rov (har deployda ishlaydi — tez
--   bo'lishi kerak): p_min (eng qisqa kod) dan qisqa bo'lak olinmaydi, bo'lak kaliti — faqat p_lens uzunlikda, oyna — faqat 12+ belgili
--   0-9/A-F qismlarda. p_code berilsa — faqat harf / raqamdan boshqa belgilari olib tashlangan matnida shu kod (katta harfda yoki
--   normallangan) uchragan yozuvlar (kalit topilishining zarur sharti; tiklashdagi bitta kod tekshiruvi — app.payer_code_exposed).
--   app.payer_codes_fix va app.payer_code_exposed — ikkalasi shu funksiya orqali (qidiruv qoidasi bitta joyda).
create or replace function app.payer_text_keys(p_min int, p_lens int[], p_code text default null)
returns table (r_kind text, r_id text, r_key text)
language sql stable set search_path = public, app, pg_temp as $$
  with src0 as (
    select 'p'::text as kind, p.id,
           concat_ws('|', p.merchant_trans_id, p."payerName", p."payerClass", p."payerPhone",
                     (select string_agg(v #>> '{}', '|') from jsonb_path_query(p.raw, 'strict $.**') v
                       where jsonb_typeof(v) in ('string', 'number'))) as t
      from public.payments p
    union all
    select 'r', f.id, f."studentName" from public.refunds f where coalesce(f."studentName", '') <> ''
  ), src as (
    select s.kind, s.id, s.t from src0 s
     where p_code is null
        or (select position(upper(p_code) in upper(z.x)) > 0 or position(upper(p_code) in app.payer_norm(z.x)) > 0
              from (select regexp_replace(s.t, '[^0-9A-Za-zА-Яа-яЁё]', '', 'g') as x) z)
  ), tok as (
    select s.kind, s.id, m[1] as tk
      from src s cross join lateral regexp_matches(s.t, '[0-9A-Za-zА-Яа-яЁё]{' || greatest(5, p_min) || ',}', 'g') m
  ), run as (    -- 2+ bo'lakli qator (bitta bo'lak — yuqoridagi tok), ulangan va normallangan
    select s.kind, s.id, app.payer_norm(regexp_replace(m[1], '[^0-9A-Za-zА-Яа-яЁё]', '', 'g')) as j
      from src s cross join lateral regexp_matches(s.t, '[0-9A-Za-zА-Яа-яЁё]+(?:(?:[ \t.,_/-]{1,2}|[ \t\r\n\u00A0]{1,3})[0-9A-Za-zА-Яа-яЁё]+)+', 'g') m
     where length(m[1]) >= 12
  ), hex as (    -- 12+ belgili 0-9/A-F qismlar (oyna faqat shularda): 12 dan uzun bo'lak (12 belgilisi — butun bo'lak kaliti) yoki qator
    select t.kind, t.id, h[1] as x from tok t cross join lateral regexp_matches(app.payer_norm(t.tk), '[0-9A-F]{12,}', 'g') h
     where length(t.tk) > 12
    union all
    select q.kind, q.id, h[1] from run q cross join lateral regexp_matches(q.j, '[0-9A-F]{12,}', 'g') h
  )
  select kind, id, upper(tk) from tok where length(tk) <= 16 and length(tk) = any(p_lens)
  union all
  select kind, id, app.payer_norm(tk) from tok where length(tk) <= 16 and length(tk) = any(p_lens)
  union all
  select h.kind, h.id, substr(h.x, i, 12) from hex h cross join lateral generate_series(1, length(h.x) - 11) i
$$;
revoke all on function app.payer_text_keys(int, int[], text) from public, anon, authenticated;

-- Bitta kod (tiklangan o'quvchiniki) to'lovchi matnida (payments matn maydonlari va raw, refunds."studentName") ochiqmi —
--   app.payer_codes_fix bilan AYNAN bir xil kalitlar (shu kod uzunligidagi bo'lak va 12 belgili oyna).
create or replace function app.payer_code_exposed(p_code text) returns boolean
language sql stable set search_path = public, app, pg_temp as $$
  select coalesce(p_code, '') <> ''
     and exists (select 1 from app.payer_text_keys(length(p_code), array[length(p_code)], p_code) k where k.r_key = upper(p_code))
$$;
revoke all on function app.payer_code_exposed(text) from public, anon, authenticated;

-- Qaytaradi: {"rotated": almashtirilgan joriy kodlar, "payments": yashirilgan to'lov qatorlari, "refunds": qaytarish qatorlari,
--   "claims": ochilgan (matnda uchragan) kod bilan ulangan faol bog'lanishlar, "claims_staff": shundan ota-ona bo'lmagan hisoblarniki,
--   "short": student_code_prev dan o'chirilgan 12 belgidan qisqa (hech kimga berilmagan) yozuvlar}.
create or replace function app.payer_codes_fix() returns jsonb
language plpgsql volatile set search_path = public, app, pg_temp as $$
declare v_codes text[]; v_pay text[]; v_ref text[]; v_rot int := 0; v_np int := 0; v_nr int := 0; r record;
        v_lens int[]; v_min int; v_short int := 0; v_cl int := 0; v_cls int := 0;
begin
  -- (0) qisqa «eski kod» — zanjir qayta ishlaganda security-2b bergan, audit-4 uzaytirgan oraliq kod (eski versiyadagi trigger
  --     yozgan): hech kimga berilmagan, to'lovni biriktirmasin va qidiruvdagi eng qisqa uzunlikni tushirmasin.
  delete from public.student_code_prev where length(code) < 12;
  get diagnostics v_short = row_count;
  -- Kodlar uzunligi (odatda hammasi 12): undan qisqa bo'lak hech bir kodga teng bo'lolmaydi — matnni tez ko'rib chiqish uchun.
  select coalesce(array_agg(distinct length(x.c)), '{}'), coalesce(min(length(x.c)), 0) into v_lens, v_min
    from (select upper(sc.code) as c from public.student_codes sc where coalesce(sc.code, '') <> ''
          union select pc.code from public.student_code_prev pc) x;
  if v_min = 0 then
    return jsonb_build_object('rotated', 0, 'payments', 0, 'refunds', 0, 'claims', 0, 'claims_staff', 0, 'short', v_short);
  end if;
  -- (1) to'lovchi matnida uchragan joriy / eski kodlar va ular uchragan yozuvlar — kalitlar app.payer_text_keys dan (payments/index.cjs
  --     kodKeys bilan bir xil; eng qisqa koddan qisqa bo'lak olinmaydi).
  with codes as (
    select upper(sc.code) as code from public.student_codes sc where coalesce(sc.code, '') <> ''
    union
    select pc.code from public.student_code_prev pc
  ), hits as (
    select distinct k.r_kind as kind, k.r_id as id, c.code from app.payer_text_keys(v_min, v_lens) k join codes c on c.code = k.r_key
  )
  select coalesce(array_agg(distinct h.code), '{}'),
         coalesce(array_agg(distinct h.id) filter (where h.kind = 'p'), '{}'),
         coalesce(array_agg(distinct h.id) filter (where h.kind = 'r'), '{}')
    into v_codes, v_pay, v_ref
    from hits h;
  if cardinality(v_codes) = 0 then
    return jsonb_build_object('rotated', 0, 'payments', 0, 'refunds', 0, 'claims', 0, 'claims_staff', 0, 'short', v_short);
  end if;
  -- (2) JORIY kodi ochilgan o'quvchilarga yangi kod (eski kod — trg_student_code_prev orqali student_code_prev ga). Har qator alohida
  --     buyruq: keyingi yangi kod oldingilarini ham «band» deb ko'radi.
  for r in select sc.id from public.student_codes sc where upper(sc.code) = any(v_codes) order by sc.id loop
    update public.student_codes set code = app.new_student_code(), "updatedAt" = now() where id = r.id;
    v_rot := v_rot + 1;
  end loop;
  -- (3) ochilgan kod bilan (u hali joriy paytda) ulangan FAOL bog'lanishlar — kod to'lov yozuvidan o'qilib ulangan bo'lishi mumkin;
  --     faqat sanaladi (Direktor tekshirsin), bog'lanishga tegilmaydi. Ota-ona bo'lmagan hisob (xodim) — alohida son.
  select count(*), count(*) filter (where not exists (select 1 from public.users u where u.id = cc.uid and u.role = 'parent'))
    into v_cl, v_cls
    from public.child_claims cc
   where coalesce(nullif(cc.status, ''), 'active') = 'active' and upper(coalesce(cc.code, '')) = any(v_codes);
  -- (4) yashirish (faqat matn maydonlari: holat, o'quvchi, summa, sana o'zgarmaydi); sanaladi — haqiqatan o'zgargan qatorlar
  with m as (
    select p.id, app.payer_mask(p.merchant_trans_id, v_codes) as a, app.payer_mask(p."payerName", v_codes) as b,
           app.payer_mask(p."payerClass", v_codes) as c, app.payer_mask(p."payerPhone", v_codes) as d, app.payer_mask_json(p.raw, v_codes) as e
      from public.payments p where p.id = any(v_pay)
  )
  update public.payments p set merchant_trans_id = m.a, "payerName" = m.b, "payerClass" = m.c, "payerPhone" = m.d, raw = m.e
    from m
   where p.id = m.id
     and (p.merchant_trans_id, p."payerName", p."payerClass", p."payerPhone", p.raw) is distinct from (m.a, m.b, m.c, m.d, m.e);
  get diagnostics v_np = row_count;
  update public.refunds f set "studentName" = app.payer_mask(f."studentName", v_codes)
   where f.id = any(v_ref) and f."studentName" is distinct from app.payer_mask(f."studentName", v_codes);
  get diagnostics v_nr = row_count;
  return jsonb_build_object('rotated', v_rot, 'payments', v_np, 'refunds', v_nr, 'claims', v_cl, 'claims_staff', v_cls, 'short', v_short);
end $$;
revoke all on function app.payer_codes_fix() from public, anon, authenticated;

-- Tuzatish + NOTICE (faqat sonlar). Biror narsa o'zgargan bo'lsa — «OGOHLANTIRISH» (deploy.sh uni log ichidan ko'rsatadi): kodi
--   almashtirilgan o'quvchining ota-onasi farzandini yangi kod bilan ulaydi (qabulxona / Direktor «Kod» ustunidan beradi); ochilgan
--   kod bilan ulangan bog'lanishlarni Direktor ko'rib chiqadi (migration/deploy/README.md). Qisqa eski kodlar tozalanishi — alohida
--   qator, faqat SQL logida. Zanjirda (pastda) va deploy.sh 6/7 dan keyin chaqiriladi.
create or replace function app.payer_codes_fix_notice() returns jsonb
language plpgsql volatile set search_path = public, app, pg_temp as $$
declare r jsonb := app.payer_codes_fix();
begin
  raise notice '%payer-code-mask: to''lovchi matnidagi maxfiy kod — % ta o''quvchi kodi almashtirildi, % ta to''lov va % ta qaytarish yozuvida «[kod]» bilan yashirildi; ochilgan kod bilan ulangan faol bog''lanish: % ta (shundan ota-ona bo''lmagan hisobda: % ta)',
    case when (r ->> 'rotated')::int + (r ->> 'payments')::int + (r ->> 'refunds')::int + (r ->> 'claims')::int > 0 then 'OGOHLANTIRISH: ' else '' end,
    r ->> 'rotated', r ->> 'payments', r ->> 'refunds', r ->> 'claims', r ->> 'claims_staff';
  if (r ->> 'short')::int > 0 then
    raise notice 'payer-code-mask: student_code_prev dan % ta qisqa (hech kimga berilmagan) yozuv o''chirildi', r ->> 'short';
  end if;
  return r;
end $$;
revoke all on function app.payer_codes_fix_notice() from public, anon, authenticated;

-- ---------- 6) O'chirilgan o'quvchini tiklash ----------
-- restore_deleted_student — admission-crm.sql bilan bir xil; yangi: tiklangan kod to'lovchi matnida ochiq bo'lsa — darhol almashtiriladi.
--   O'quvchi o'chirilganda panel student_codes qatorini ham o'chiradi (eski kodlari FK bilan o'chadi): shu oraliqda kelgan to'lovdagi kod
--   (masalan, saqlangan «ID KOD» shabloni) hech kimniki emas — server uni taniy olmay ochiq saqlaydi. Tiklash o'sha kodni qaytaradi —
--   moliya rollari uni to'lov yozuvidan o'qib, farzandni ulay olardi (keyingi deploydagi app.payer_codes_fix gacha). Endi kod qaytgach
--   to'lov / qaytarish matnida qidiriladi (app.payer_code_exposed — app.payer_codes_fix bilan bir xil kalitlar, faqat shu kod); topilsa —
--   yangi kod (app.new_student_code), eskisi student_code_prev ga: saqlangan Click / Uzum to'lovi biriktirilaveradi, ulangan ota-onalar
--   uzilmaydi (claim_row), claim_child eski kodga 'code_changed' qaytaradi. Matnni yashirish keyingi app.payer_codes_fix da: tiklash
--   Direktor sessiyasida ishlaydi — to'lov qatorlariga tegilmaydi (davr qulfi / kassa qo'riqchisi tizimdan boshqa yozuvni rad etadi),
--   eski kod esa endi ulamaydi. DIQQAT: amaldagi ta'rif SHU yerda (admission-crm.sql dagisi zanjirda almashtiriladi).
--   SHU O'CHIRISHNIKI (audit-10, A1-11): ID qayta berilgan bo'lsa (eski student_id_high_water o'chirilganlar arxivini hisobga olmasdi)
--   bitta ID ostida ikki oilaning arxivi bo'ladi. Avval maxfiy ma'lumot va kod «eng oxirgi» arxivdan olinardi — birinchi bolani
--   tiklaganda IKKINCHI oilaning telefonlari, ota ismi va kodi unga yopishardi. Endi maxfiy ma'lumot / kod arxivi faqat vaqt bo'yicha
--   eng yaqin o'quvchi arxivi AYNAN shu (a) bo'lsa olinadi (panel o'quvchi, maxfiy ma'lumot va kod qatorlarini ketma-ket, bir necha
--   soniya ichida o'chiradi); boshqa o'chirishniki — tegilmaydi (tiklangan deb ham belgilanmaydi).
--   «XODIM FARZANDI» (A1-11): arxivdagi teacherId endi hech bir o'qituvchi/xodimniki bo'lmasa (o'qituvchi o'chirilgan yoki ID'si
--   tuzatilgan — rekey_payroll_id arxivni o'zgartirmaydi), guard_private_teacher_link butun tiklashni 23503 bilan bekor qilardi —
--   o'quvchini paneldan umuman tiklab bo'lmasdi. Endi bunday bog'lanish bo'sh qoldiriladi (o'chgan xodimga «xodim farzandi»
--   chegirmasi yopishmasin) va javobda qaytariladi ('teacherUnlinked') — Direktor kartadan qayta tanlaydi.
create or replace function public.restore_deleted_student(p_id text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare a record; p record; v_code text; v_cid text; v_sid text; v_priv boolean := false; v_rot boolean := false;
        v_pr public.student_private; v_unl text;
begin
  if not app.is_admin() then raise exception 'Faqat direktor tiklay oladi' using errcode = '42501'; end if;
  select * into a from public.deleted_records where id = p_id and tbl = 'students' for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Arxiv yozuvi topilmadi'); end if;
  if a."restoredAt" is not null then return jsonb_build_object('ok', false, 'error', 'Bu yozuv allaqachon tiklangan'); end if;
  v_sid := nullif(btrim(coalesce(a.row->>'studentId', '')), '');
  if exists (select 1 from public.students s where s.id = a."rowId" or (v_sid is not null and s."studentId" = v_sid)) then
    return jsonb_build_object('ok', false, 'error', 'Shu ID bilan o''quvchi bazada bor — tiklab bo''lmaydi');
  end if;
  -- Ota-ona kodi: hali bazada bo'lsa — o'sha, o'chirilgan bo'lsa — arxivdan, faqat SHU o'chirishniki (eng yaqini).
  select sc.code into v_code from public.student_codes sc where sc.id = a."rowId";
  if v_code is null then
    select d.id, d.row->>'code' into v_cid, v_code from public.deleted_records d
     where d.tbl = 'student_codes' and d."rowId" = a."rowId" and d."restoredAt" is null
       and not exists (select 1 from public.deleted_records s
                        where s.tbl = 'students' and s."rowId" = a."rowId" and s.id <> a.id
                          and abs(extract(epoch from s."deletedAt" - d."deletedAt")) < abs(extract(epoch from a."deletedAt" - d."deletedAt")))
     order by abs(extract(epoch from d."deletedAt" - a."deletedAt")), d."deletedAt" desc limit 1;
  end if;
  insert into public.students select * from jsonb_populate_record(null::public.students, a.row);
  if nullif(v_code, '') is not null then
    insert into public.student_codes(id, code, "updatedAt") values (a."rowId", v_code, now())
      on conflict (id) do update set code = excluded.code, "updatedAt" = now();
    -- Shu o'chirishning kod arxivi tiklangan deb belgilanadi (boshqa oilaniki — yo'q).
    update public.deleted_records d set "restoredAt" = now(), "restoredBy" = app.uid()
     where d.tbl = 'student_codes' and d."rowId" = a."rowId" and d."restoredAt" is null
       and (d.id = v_cid
            or not exists (select 1 from public.deleted_records s
                            where s.tbl = 'students' and s."rowId" = a."rowId" and s.id <> a.id
                              and abs(extract(epoch from s."deletedAt" - d."deletedAt")) < abs(extract(epoch from a."deletedAt" - d."deletedAt"))));
    -- Tiklangan kod to'lovchi matnida ochiq — almashtiriladi. U ota-onaga berilgan (haqiqiy) kod: «shu tranzaksiyada yozilgan» belgisi
    --   olinadi, shunda almashtirish triggeri uni student_code_prev ga yozadi.
    if app.payer_code_exposed(v_code) then
      perform set_config('iqror.code_fresh',
        replace(coalesce(current_setting('iqror.code_fresh', true), ''), ',' || upper(v_code) || ',', ','), true);
      update public.student_codes set code = app.new_student_code(), "updatedAt" = now() where id = a."rowId";
      v_rot := true;
    end if;
  end if;
  -- Maxfiy ma'lumot — faqat SHU o'chirishniki (kod bilan bir xil qoida): boshqa oilaning telefonlari / ota ismi yopishmaydi.
  select * into p from public.deleted_records d
   where d.tbl = 'student_private' and d."rowId" = a."rowId" and d."restoredAt" is null
     and not exists (select 1 from public.deleted_records s
                      where s.tbl = 'students' and s."rowId" = a."rowId" and s.id <> a.id
                        and abs(extract(epoch from s."deletedAt" - d."deletedAt")) < abs(extract(epoch from a."deletedAt" - d."deletedAt")))
   order by abs(extract(epoch from d."deletedAt" - a."deletedAt")), d."deletedAt" desc limit 1 for update;
  if found and not exists (select 1 from public.student_private sp where sp.id = a."rowId") then
    v_pr := jsonb_populate_record(null::public.student_private, p.row);
    -- O'chgan / ID'si o'zgargan xodimga bog'lanish tiklashni to'xtatmaydi (guard_private_teacher_link bilan bir xil tekshiruv).
    if coalesce(v_pr."teacherId", '') <> ''
       and not exists (select 1 from public.teachers t where coalesce(nullif(t."teacherId", ''), t.id) = v_pr."teacherId")
       and not exists (select 1 from public.staff s where coalesce(nullif(s."staffId", ''), s.id) = v_pr."teacherId") then
      v_unl := v_pr."teacherId";
      v_pr."teacherId" := null;
    end if;
    -- Chegirma maydonlari faqat RPC orqali (discount-approval.sql qulfi): tiklash — avvalgi (tasdiqlangan) holatni qaytaradi.
    perform set_config('iqror.discount_rpc', '1', true);
    insert into public.student_private select v_pr.*;
    perform set_config('iqror.discount_rpc', '', true);
    update public.deleted_records set "restoredAt" = now(), "restoredBy" = app.uid() where id = p.id;
    v_priv := true;
  end if;
  update public.deleted_records set "restoredAt" = now(), "restoredBy" = app.uid() where id = a.id;
  return jsonb_build_object('ok', true, 'id', a."rowId", 'private', v_priv, 'codeChanged', v_rot, 'teacherUnlinked', v_unl);
end $$;
revoke all on function public.restore_deleted_student(text) from public, anon;
grant execute on function public.restore_deleted_student(text) to authenticated, service_role;

-- Har zanjirda bir marta (deploy.sh xizmatlar qayta ishga tushgach yana bir marta chaqiradi).
do $pcm$ begin perform app.payer_codes_fix_notice(); end $pcm$;

notify pgrst, 'reload schema';
