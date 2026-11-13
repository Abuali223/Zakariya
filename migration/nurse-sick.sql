\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: nurse-sick.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- nurse-sick.sql — «BEMOR» KUNI VA HAMSHIRA (direktor qarori D1, 2026-10-30):
--   «Bemor kuni — hamshira ma'lumotnoma asosida (elektron nusxasi bilan) kiritadi, Moliya menejeri tasdiqlaydi,
--    FAQAT tasdiqlangani to'lovga ta'sir qiladi.»
--   * nurse roli: app.is_nurse(); tasdiqlovchi — app.is_finance_mgr() (direktor yoki Moliya menejeri, g'aznachi EMAS).
--     Hamshira o'quvchini faqat ism va sinf bilan ko'radi (students_billing ko'rinishi), ball/davomat/rasm — yo'q.
--   * sick_notes — ma'lumotnoma: kunlar (maktab ish kunlari bazada hisoblanadi), raqam, muassasa, fayl (yopiq «medical»
--     bucket), holat pending → approved | rejected (izoh bilan) | withdrawn. Mijoz faqat INSERT qiladi; holat faqat
--     review_sick_note() / withdraw_sick_note() bilan. Kirituvchi o'zi tasdiqlay olmaydi. Kech keltirilgan (qaytgandan
--     keyin 3 ish kunidan ko'p) — late=true (rad etilmaydi, tasdiqlovchi ko'radi).
--   * O'tish oyi config/finance."sickApprovalFrom" ('YYYY-MM' — shu oy FAKTURASIDAN, ya'ni oldingi oy kasal kunlaridan):
--     undan oldingi fakturalar ESKI qoida (davomatdagi «Bemor»). O'tish oyidan boshlab fakturadagi kasal kunlari faqat
--     tasdiqlangan ma'lumotnomadan: invoices."sickNoteRefs" {noteId: [kunlar]} — baza tekshiradi (kunlar soni, summa =
--     kunlar × sickRate, har kun faqat BIR fakturaga), sick_notes."appliedDays" {kun: fakturaId} shu yerda belgilanadi.
--     Faktura bekor qilinsa/o'chirilsa — kunlar bo'shaydi. Fakturalar bor oy uchun o'tish oyini o'zgartirib bo'lmaydi.
--   * Ketgan/muzlatilgan o'quvchining kech tasdiqlangan kunlari — sick_note_refund(): avansga (faqat tasdiqlovchi amali).
--   * student_health — sog'liq kartasi (hamshira/direktor yozadi, ota-ona o'qiydi); student_private.health bir marta
--     nusxalanadi (eski ustun qoladi). nurse_visits — hamshira jurnali (murojaat, harorat, ko'rik, chora).
--   * Ota-ona va sinf rahbari: my_sick_notes / my_nurse_visits ko'rinishlari (fayl yo'li va tibbiy matnsiz).
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Rol yordamchilari (FAOL hisob — app.my_role(), staff-d6.sql).
create or replace function app.is_nurse() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(app.my_role() = 'nurse', false)
$$;
create or replace function app.is_finance_mgr() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(app.my_role() in ('director', 'finance_mgr'), false)
$$;
revoke all on function app.is_nurse(), app.is_finance_mgr() from public;
-- anon ham: bu funksiyalar ommaviy jadvallar policy'larida (masalan school_holidays) — anonimga false qaytaradi.
grant execute on function app.is_nurse(), app.is_finance_mgr() to anon, authenticated, service_role;

-- 2) Hamshira: o'quvchi ismi va sinfi (students_billing — staff-d6.sql bilan bir xil ustunlar), dam olish kunlari.
--    Buxgalter ham (moliya rejasi F1.21) — app.acc_read() orqali: uni fin-rights.sql boshqaradi («fin_rights_on»: yoqilganda
--    app.is_accountant(), o'chirilganda false). Bu yerda faqat BIRINCHI marta (false) yaratiladi — fin-rights.sql zanjirda bo'lmasa
--    (prod, kassa modulisiz) buxgalterga hech narsa ochilmaydi; qayta ishga tushirish fin-rights.sql qiymatini o'zgartirmaydi.
--    Ta'rif shu yerda yagona: buxgalterning qolgan o'qish ro'yxati — fin-rights.sql.
do $$ begin
  if to_regprocedure('app.acc_read()') is null then
    create function app.acc_read() returns boolean language sql stable set search_path = public, app, pg_temp as 'select false';
  end if;
end $$;
revoke all on function app.acc_read() from public, anon;
grant execute on function app.acc_read() to authenticated, service_role;
create or replace view public.students_billing with (security_barrier = true) as
  select s.id, s."studentId", s.name, s.grade, s."classLetter", s.track, s.lang, s."payStatus", s."activeFrom", s."stopFrom",
         s.pauses, s."order"
    from public.students s
   where (select app.is_admin()) or (select app.is_zavuch()) or (select app.is_reception())
      or (select app.is_finance()) or (select app.is_cashier()) or (select app.is_nurse())
      or (select app.acc_read());
revoke all on public.students_billing from anon;
grant select on public.students_billing to authenticated, service_role;

drop policy if exists hol_sel on public.school_holidays;
create policy hol_sel on public.school_holidays for select using (app.is_staff() or app.is_cashier() or app.is_nurse());

-- 3) O'tish oylari (config/finance): bu oydan boshlab yangi (tasdiqli) qoida — "sickApprovalFrom" (bemor kuni, shu fayl),
--    "bonusApprovalFrom" (100 ball, bonus-100.sql), "discountApprovalFrom" (chegirma/grant). Fakturasi bor oy (va undan
--    keyingi) uchun o'zgartirilmaydi: aks holda qayta hisoblashda o'sha oy fakturalari boshqa qoida bilan qayta hisoblanib,
--    summa o'zgarib ketardi. Bitta umumiy trigger (ustun hali yo'q bo'lsa — o'tkazib yuboriladi).
alter table public.config add column if not exists "sickApprovalFrom" text;
create or replace function app.config_cutover_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare c text; v_old text; v_new text; v_raw text; v_min text; jn jsonb; jo jsonb; v_lbl text;
begin
  if new.id is distinct from 'finance' then return new; end if;
  -- Upsert (setDoc merge): qator BOR bo'lsa haqiqiy o'zgarish ON CONFLICT DO UPDATE'dagi BEFORE UPDATE'da tekshiriladi
  --   (bu yerdagi taklif qatorida yuborilmagan ustun NULL — «tozalandi» deb noto'g'ri tushunilmasin).
  if tg_op = 'INSERT' and exists (select 1 from public.config x where x.id = new.id) then return new; end if;
  jn := to_jsonb(new); jo := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  foreach c in array array['sickApprovalFrom', 'bonusApprovalFrom', 'discountApprovalFrom'] loop
    if not (jn ? c) then continue; end if;
    v_raw := jn->>c;
    v_old := nullif(btrim(coalesce(jo->>c, '')), '');
    v_new := nullif(btrim(coalesce(v_raw, '')), '');
    if v_old is not distinct from v_new then continue; end if;
    v_lbl := case c when 'sickApprovalFrom' then 'Bemor kuni' when 'bonusApprovalFrom' then '100 ball' else 'Chegirma / grant' end;
    if v_new is not null and v_raw !~ '^\d{4}-(0[1-9]|1[0-2])$' then
      raise exception '% qoidasi: o''tish oyi YYYY-MM ko''rinishida bo''lsin (masalan 2026-12)', v_lbl using errcode = '22023';
    end if;
    v_min := least(coalesce(v_old, '9999-99'), coalesce(v_new, '9999-99'));
    if exists (select 1 from public.invoices i
                where i.month >= v_min and coalesce(i.status, '') not in ('canceled', 'reversed')) then
      raise exception '% qoidasining o''tish oyini o''zgartirib bo''lmaydi: % yoki undan keyingi oy uchun hisob-fakturalar allaqachon yaratilgan. Hali faktura yaratilmagan oyni tanlang.', v_lbl, v_min
        using errcode = '23514';
    end if;
  end loop;
  return new;
end $$;
revoke all on function app.config_cutover_guard() from public, anon, authenticated;
drop trigger if exists trg_config_cutover on public.config;
create trigger trg_config_cutover before insert or update on public.config
  for each row execute function app.config_cutover_guard();

-- 4) Maktab ish kunlari (dushanba–juma, school_holidays'siz) — admin.html billingInterval (SA_WORKDAYS) bilan bir xil.
create or replace function app.school_days(p_from date, p_to date) returns jsonb
language sql stable security definer set search_path = public, app, pg_temp as $$
  select coalesce(jsonb_agg(to_char(g.d, 'YYYY-MM-DD') order by g.d), '[]'::jsonb)
    from generate_series(p_from, p_to, interval '1 day') g(d)
   where extract(isodow from g.d) between 1 and 5
     and not exists (select 1 from public.school_holidays h
                      where h.id = to_char(g.d, 'YYYY-MM-DD') or h.day = to_char(g.d, 'YYYY-MM-DD'))
$$;
revoke all on function app.school_days(date, date) from public, anon, authenticated;

-- 5) Ma'lumotnomalar
create table if not exists public.sick_notes (
  id             text primary key default gen_random_uuid()::text,
  "studentId"    text not null,                         -- kanonik: students."studentId" (bo'lmasa id)
  "fromDay"      text not null,                         -- 'YYYY-MM-DD'
  "toDay"        text not null,
  "schoolDays"   jsonb not null default '[]'::jsonb,    -- ["YYYY-MM-DD", ...] — bazada hisoblanadi
  "noteNumber"   text,
  institution    text,
  "issuedDay"    text,
  "filePath"     text,                                  -- medical bucket: notes/<studentId>/<uuid>.<ext>
  status         text not null default 'pending',
  late           boolean not null default false,
  "enteredBy"    text,
  "enteredAt"    timestamptz not null default now(),
  "reviewedBy"   text,
  "reviewedAt"   timestamptz,
  "reviewNote"   text,
  "appliedDays"  jsonb not null default '{}'::jsonb,    -- {"YYYY-MM-DD": "<fakturaId>" | "credit:<jurnalId>"}
  comment        text
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'sick_notes_status_chk') then
    alter table public.sick_notes add constraint sick_notes_status_chk
      check (status in ('pending', 'approved', 'rejected', 'withdrawn'));
  end if;
end $$;
create index if not exists sick_notes_student_idx on public.sick_notes("studentId");
create index if not exists sick_notes_status_idx on public.sick_notes(status);
alter table public.sick_notes enable row level security;
revoke all on public.sick_notes from anon, authenticated;
grant select, insert on public.sick_notes to authenticated;
grant all on public.sick_notes to service_role;
drop policy if exists sn_sel on public.sick_notes;
create policy sn_sel on public.sick_notes for select using (app.is_nurse() or app.is_finance_mgr());
drop policy if exists sn_ins on public.sick_notes;
create policy sn_ins on public.sick_notes for insert with check (
  (app.is_nurse() or app.is_admin()) and status = 'pending' and "enteredBy" = app.uid());

create or replace function app.sick_note_before_ins() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_today date := (now() at time zone 'Asia/Tashkent')::date; v_from date; v_to date; v_after int; v_file text;
begin
  -- Ruxsat AVVAL (BEFORE trigger RLS'dan oldin ishlaydi — ruxsatsiz foydalanuvchiga o'quvchi / ma'lumotnoma borligi
  --   haqida hech narsa aytilmasin).
  if not app.is_system() and not (app.is_nurse() or app.is_admin()) then
    raise exception 'Ruxsat yo''q: ma''lumotnomani faqat hamshira (yoki direktor) kiritadi' using errcode = '42501';
  end if;
  new.id := coalesce(nullif(btrim(coalesce(new.id, '')), ''), gen_random_uuid()::text);
  new."studentId" := btrim(coalesce(new."studentId", ''));
  if new."studentId" = '' then raise exception 'O''quvchi tanlanmagan' using errcode = '23502'; end if;
  if coalesce(new."fromDay", '') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(new."toDay", '') !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'Sana YYYY-MM-DD ko''rinishida bo''lsin' using errcode = '22023';
  end if;
  v_from := new."fromDay"::date; v_to := new."toDay"::date;
  if v_to < v_from then raise exception 'Tugash sanasi boshlanishidan oldin' using errcode = '22023'; end if;
  if v_to - v_from > 62 then raise exception 'Bitta ma''lumotnoma ko''pi bilan 63 kunlik' using errcode = '22023'; end if;
  if v_from > v_today then raise exception 'Kasallik boshlanishi kelajakdagi sana bo''lishi mumkin emas' using errcode = '22023'; end if;
  if coalesce(new."issuedDay", '') <> '' and new."issuedDay" !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'Berilgan sana YYYY-MM-DD ko''rinishida bo''lsin' using errcode = '22023';
  end if;
  if not exists (select 1 from public.students s where s."studentId" = new."studentId" or s.id = new."studentId") then
    raise exception 'O''quvchi topilmadi' using errcode = '23503';
  end if;
  new."schoolDays" := app.school_days(v_from, v_to);
  if jsonb_array_length(new."schoolDays") = 0 then
    raise exception 'Bu oraliqda maktab ish kuni yo''q (dam olish yoki bayram kunlari)' using errcode = '22023';
  end if;
  -- Fayl MAJBURIY: avval yuklangan bo'lsin (medical bucket, notes/<studentId>/<uuid>.<jpg|jpeg|png|pdf>).
  v_file := btrim(coalesce(new."filePath", ''));
  if split_part(v_file, '/', 1) <> 'notes' or split_part(v_file, '/', 2) <> new."studentId" or split_part(v_file, '/', 4) <> ''
     or split_part(v_file, '/', 3) !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|pdf)$' then
    raise exception 'Ma''lumotnoma nusxasi (rasm yoki PDF) biriktirilmagan' using errcode = '23502';
  end if;
  if to_regclass('storage.objects') is not null
     and not exists (select 1 from storage.objects o where o.bucket_id = 'medical' and o.name = v_file) then
    raise exception 'Ma''lumotnoma fayli yuklanmagan — qayta urinib ko''ring' using errcode = '23503';
  end if;
  new."filePath" := v_file;
  new.status := 'pending';
  new."enteredBy" := coalesce(app.uid(), new."enteredBy");
  new."enteredAt" := now();
  new."reviewedBy" := null; new."reviewedAt" := null; new."reviewNote" := null;
  new."appliedDays" := '{}'::jsonb;
  -- Kech keltirilgan: o'quvchi qaytgandan (toDay) keyin 3 ish kunidan ko'p o'tgan.
  select count(*) into v_after
    from jsonb_array_elements_text(case when v_to + 1 <= v_today then app.school_days(v_to + 1, v_today) else '[]'::jsonb end);
  new.late := v_after > 3;
  -- Ustma-ust: shu o'quvchining kutilayotgan/tasdiqlangan ma'lumotnomasi bilan kesishmasin (bir vaqtda ikki kiritish ham).
  perform pg_advisory_xact_lock(hashtext('sick_notes:' || new."studentId"));
  if exists (select 1 from public.sick_notes n
              where n."studentId" = new."studentId" and n.status in ('pending', 'approved')
                and n."fromDay" <= new."toDay" and n."toDay" >= new."fromDay") then
    raise exception 'Bu o''quvchida shu kunlarga ma''lumotnoma allaqachon bor (kutilmoqda yoki tasdiqlangan)' using errcode = '23P01';
  end if;
  return new;
end $$;
revoke all on function app.sick_note_before_ins() from public, anon, authenticated;
drop trigger if exists trg_sick_note_ins on public.sick_notes;
create trigger trg_sick_note_ins before insert on public.sick_notes for each row execute function app.sick_note_before_ins();

-- O'zgartirish: asosiy maydonlar HECH QACHON; holat/ko'rib chiqish/qo'llangan kunlar — faqat shu fayldagi funksiyalar
--   (iqror.sick_rpc = '1'). Mijozda UPDATE/DELETE huquqi umuman yo'q (yuqorida revoke).
create or replace function app.sick_note_before_upd() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if new.id is distinct from old.id or new."studentId" is distinct from old."studentId" or new."fromDay" is distinct from old."fromDay"
     or new."toDay" is distinct from old."toDay" or new."schoolDays" is distinct from old."schoolDays"
     or new."filePath" is distinct from old."filePath" or new."enteredBy" is distinct from old."enteredBy"
     or new."enteredAt" is distinct from old."enteredAt" or new."noteNumber" is distinct from old."noteNumber"
     or new.institution is distinct from old.institution or new."issuedDay" is distinct from old."issuedDay"
     or new.late is distinct from old.late then
    raise exception 'Ma''lumotnomani o''zgartirib bo''lmaydi — kerak bo''lsa qaytarib oling va qaytadan kiriting' using errcode = '42501';
  end if;
  if coalesce(current_setting('iqror.sick_rpc', true), '') <> '1' and not app.is_system() then
    raise exception 'Ma''lumotnoma holati faqat «Tasdiqlash» bo''limidan o''zgaradi' using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (old.status = 'pending' and new.status in ('approved', 'rejected', 'withdrawn')) then
    raise exception 'Ko''rib chiqilgan ma''lumotnoma holati o''zgarmaydi' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function app.sick_note_before_upd() from public, anon, authenticated;
drop trigger if exists trg_sick_note_upd on public.sick_notes;
create trigger trg_sick_note_upd before update on public.sick_notes for each row execute function app.sick_note_before_upd();

-- 6) Ko'rib chiqish (Moliya menejeri / direktor; kirituvchi o'zi emas; faqat kutilayotgan; rad etishda izoh majburiy).
create or replace function public.review_sick_note(p_id text, p_decision text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); n public.sick_notes%rowtype;
begin
  if v_uid is null or not app.is_finance_mgr() then
    raise exception 'Ruxsat yo''q: ma''lumotnomani Moliya menejeri yoki Direktor tasdiqlaydi' using errcode = '42501';
  end if;
  if coalesce(p_decision, '') not in ('approved', 'rejected') then
    raise exception 'Qaror: approved yoki rejected' using errcode = '22023';
  end if;
  select * into n from public.sick_notes where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if n.status <> 'pending' then return jsonb_build_object('ok', false, 'reason', 'not_pending', 'status', n.status); end if;
  if n."enteredBy" = v_uid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  if p_decision = 'rejected' and coalesce(btrim(p_note), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'note_required');
  end if;
  perform set_config('iqror.sick_rpc', '1', true);
  update public.sick_notes
     set status = p_decision, "reviewedBy" = v_uid, "reviewedAt" = now(), "reviewNote" = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_id;
  perform set_config('iqror.sick_rpc', '', true);
  return jsonb_build_object('ok', true, 'status', p_decision);
end $$;
revoke all on function public.review_sick_note(text, text, text) from public, anon;
grant execute on function public.review_sick_note(text, text, text) to authenticated, service_role;

-- Qaytarib olish (xato kiritilgan, hali ko'rib chiqilmagan) — kirituvchi hamshira yoki direktor.
create or replace function public.withdraw_sick_note(p_id text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); n public.sick_notes%rowtype;
begin
  if v_uid is null or not (app.is_nurse() or app.is_admin()) then
    raise exception 'Ruxsat yo''q' using errcode = '42501';
  end if;
  select * into n from public.sick_notes where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if n.status <> 'pending' then return jsonb_build_object('ok', false, 'reason', 'not_pending', 'status', n.status); end if;
  if n."enteredBy" is distinct from v_uid and not app.is_admin() then return jsonb_build_object('ok', false, 'reason', 'not_owner'); end if;
  perform set_config('iqror.sick_rpc', '1', true);
  update public.sick_notes set status = 'withdrawn', "reviewedBy" = v_uid, "reviewedAt" = now() where id = p_id;
  perform set_config('iqror.sick_rpc', '', true);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.withdraw_sick_note(text) from public, anon;
grant execute on function public.withdraw_sick_note(text) to authenticated, service_role;

-- 7) Ziddiyatlar: ma'lumotnoma kunlaridagi davomat belgisi va kamera birinchi kirishi («kasal» kuni maktabga kelgan).
create or replace function public.sick_note_checks(p_id text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare n public.sick_notes%rowtype; v_cam text; v_res jsonb;
begin
  if not app.is_finance_mgr() then
    raise exception 'Ruxsat yo''q: faqat tasdiqlovchi (Moliya menejeri / Direktor)' using errcode = '42501';
  end if;
  select * into n from public.sick_notes where id = p_id;
  if not found then return '[]'::jsonb; end if;
  select btrim(coalesce(s."cameraId", '')) into v_cam from public.students s
   where s."studentId" = n."studentId" or s.id = n."studentId"
   order by (s."studentId" = n."studentId") desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'mark', d.mark, 'firstIn', d.first_in) order by d.day), '[]'::jsonb)
    into v_res
    from (select x.day,
                 (select coalesce(a.days->>substr(x.day, 9, 2), a.days->>ltrim(substr(x.day, 9, 2), '0'))
                    from public.attendance a
                   where a."studentId" = n."studentId" and a.month = substr(x.day, 1, 7) limit 1) as mark,
                 (select min(c.ts) from public.staff_checkins c
                   where coalesce(v_cam, '') <> '' and btrim(c."personId") = v_cam and c.day = x.day
                     and coalesce(nullif(c.status, ''), 'in') in ('in', 'unknown')) as first_in
            from jsonb_array_elements_text(n."schoolDays") x(day)) d;
  return v_res;
end $$;
revoke all on function public.sick_note_checks(text) from public, anon;
grant execute on function public.sick_note_checks(text) to authenticated, service_role;

-- 7b) «Kasal bolalar»: davomatdagi «Bemor» belgilari (faqat shu belgi — boshqa davomat ko'rinmaydi) — hamshira, direktor,
--     O'IBDO'. Ma'lumotnomasi yo'q bolalarni topish uchun (hamshiraga eslatma).
create or replace function public.attendance_sick_marks(p_month text) returns jsonb
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v jsonb;
begin
  if not (app.is_nurse() or app.is_admin() or app.is_zavuch()) then
    raise exception 'Ruxsat yo''q' using errcode = '42501';
  end if;
  if coalesce(p_month, '') !~ '^\d{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Oy YYYY-MM ko''rinishida bo''lsin' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('studentId', x."studentId", 'classKey', x."classKey", 'days', x.days)
                            order by x."studentId"), '[]'::jsonb) into v
    from (select a."studentId", a."classKey",
                 (select jsonb_agg(lpad(e.key, 2, '0') order by lpad(e.key, 2, '0')) from jsonb_each_text(a.days) e where e.value = 'sick') as days
            from public.attendance a
           where a.month = p_month and exists (select 1 from jsonb_each_text(a.days) e where e.value = 'sick')) x;
  return v;
end $$;
revoke all on function public.attendance_sick_marks(text) from public, anon;
grant execute on function public.attendance_sick_marks(text) to authenticated, service_role;

-- 8) Yopiq «medical» bucket: o'qish — hamshira, direktor (imzolangan havola orqali); yozish — hamshira/direktor, faqat
--    notes/<studentId>/<uuid>.<jpg|jpeg|png|pdf>; ustiga yozish (upsert) va o'chirish yo'q. Hajm ≤ 5 MB, tur — haqiqiy
--    Supabase'da bucket sozlamasi (file_size_limit, allowed_mime_types); sinov stub'ida bu ustunlar yo'q.
do $$
begin
  if to_regclass('storage.buckets') is null then return; end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'storage' and table_name = 'buckets' and column_name = 'file_size_limit')
     and exists (select 1 from information_schema.columns
              where table_schema = 'storage' and table_name = 'buckets' and column_name = 'allowed_mime_types') then
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
               values ('medical', 'medical', false, 5242880, array['image/jpeg', 'image/png', 'application/pdf'])
               on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
                                              allowed_mime_types = excluded.allowed_mime_types$q$;
  else
    execute $q$insert into storage.buckets (id, name, public) values ('medical', 'medical', false)
               on conflict (id) do update set public = false$q$;
  end if;
end $$;
do $$
begin
  if to_regclass('storage.objects') is null then return; end if;
  execute 'drop policy if exists iqror_medical_read on storage.objects';
  execute $q$create policy iqror_medical_read on storage.objects for select
             using ( bucket_id = 'medical' and ((select app.is_nurse()) or (select app.is_admin())) )$q$;
  execute 'drop policy if exists iqror_medical_insert on storage.objects';
  execute $q$create policy iqror_medical_insert on storage.objects for insert
             with check ( bucket_id = 'medical' and ((select app.is_nurse()) or (select app.is_admin()))
                          and name ~ '^notes/[A-Za-z0-9_.-]+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|pdf)$' )$q$;
end $$;

-- 9) Sog'liq kartasi
create table if not exists public.student_health (
  id            text primary key,                     -- = "studentId" (shim kaliti: doc(db,'student_health', studentId))
  "studentId"   text not null,
  allergies     text,
  chronic       text,
  medications   text,
  note          text,
  "updatedBy"   text,
  "updatedAt"   timestamptz default now()
);
alter table public.student_health enable row level security;
revoke all on public.student_health from anon, authenticated;
grant select, insert, update on public.student_health to authenticated;
grant all on public.student_health to service_role;
drop policy if exists sh_sel on public.student_health;
create policy sh_sel on public.student_health for select using (app.is_nurse() or app.is_admin() or app.owns_child("studentId"));
drop policy if exists sh_ins on public.student_health;
create policy sh_ins on public.student_health for insert with check (app.is_nurse() or app.is_admin());
drop policy if exists sh_upd on public.student_health;
create policy sh_upd on public.student_health for update using (app.is_nurse() or app.is_admin()) with check (app.is_nurse() or app.is_admin());
create or replace function app.student_health_stamp() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  new.id := coalesce(nullif(btrim(coalesce(new.id, '')), ''), btrim(coalesce(new."studentId", '')));
  new."studentId" := coalesce(nullif(btrim(coalesce(new."studentId", '')), ''), new.id);
  if new.id = '' or new.id <> new."studentId" then
    raise exception 'Sog''liq kartasi kaliti = o''quvchi ID' using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' and new.id is distinct from old.id then
    raise exception 'O''quvchi o''zgarmaydi' using errcode = '42501';
  end if;
  new."updatedBy" := coalesce(app.uid(), new."updatedBy"); new."updatedAt" := now();
  return new;
end $$;
revoke all on function app.student_health_stamp() from public, anon, authenticated;
drop trigger if exists trg_student_health_stamp on public.student_health;
create trigger trg_student_health_stamp before insert or update on public.student_health
  for each row execute function app.student_health_stamp();
-- Bir martalik nusxa: student_private.health -> izoh (mavjud karta bo'lsa tegilmaydi; eski ustun o'chirilmaydi).
insert into public.student_health (id, "studentId", note)
select distinct on (coalesce(nullif(s."studentId", ''), p.id)) coalesce(nullif(s."studentId", ''), p.id), coalesce(nullif(s."studentId", ''), p.id), btrim(p.health)
  from public.student_private p left join public.students s on s.id = p.id
 where coalesce(btrim(p.health), '') <> ''
 order by coalesce(nullif(s."studentId", ''), p.id)
on conflict (id) do nothing;

-- 10) Hamshira jurnali
create table if not exists public.nurse_visits (
  id               text primary key default gen_random_uuid()::text,
  "studentId"      text not null,
  at               timestamptz not null default now(),
  complaint        text,
  temperature      numeric,
  examination      text,
  action           text,                 -- rest | home | parent_call | ambulance | other
  "parentNotified" boolean not null default false,
  "nurseUid"       text
);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'nurse_visits_temp_chk') then
    alter table public.nurse_visits add constraint nurse_visits_temp_chk check (temperature is null or temperature between 34 and 43);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'nurse_visits_action_chk') then
    alter table public.nurse_visits add constraint nurse_visits_action_chk
      check (action is null or action in ('rest', 'home', 'parent_call', 'ambulance', 'other'));
  end if;
end $$;
create index if not exists nurse_visits_student_idx on public.nurse_visits("studentId", at desc);
create index if not exists nurse_visits_at_idx on public.nurse_visits(at desc);
alter table public.nurse_visits enable row level security;
revoke all on public.nurse_visits from anon, authenticated;
grant select, insert, update, delete on public.nurse_visits to authenticated;
grant all on public.nurse_visits to service_role;
drop policy if exists nv_sel on public.nurse_visits;
create policy nv_sel on public.nurse_visits for select using (app.is_nurse() or app.is_admin());
drop policy if exists nv_ins on public.nurse_visits;
create policy nv_ins on public.nurse_visits for insert with check ((app.is_nurse() or app.is_admin()) and "nurseUid" = app.uid());
drop policy if exists nv_upd on public.nurse_visits;
create policy nv_upd on public.nurse_visits for update using (app.is_admin() or (app.is_nurse() and "nurseUid" = app.uid()))
  with check (app.is_admin() or (app.is_nurse() and "nurseUid" = app.uid()));
drop policy if exists nv_del on public.nurse_visits;
create policy nv_del on public.nurse_visits for delete using (app.is_admin());
create or replace function app.nurse_visit_stamp() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if not app.is_system() and not (app.is_nurse() or app.is_admin()) then
    raise exception 'Ruxsat yo''q' using errcode = '42501';
  end if;
  new."studentId" := btrim(coalesce(new."studentId", ''));
  if new."studentId" = '' then raise exception 'O''quvchi tanlanmagan' using errcode = '23502'; end if;
  if tg_op = 'INSERT' then
    new."nurseUid" := coalesce(app.uid(), new."nurseUid");
    if not exists (select 1 from public.students s where s."studentId" = new."studentId" or s.id = new."studentId") then
      raise exception 'O''quvchi topilmadi' using errcode = '23503';
    end if;
  elsif new."studentId" is distinct from old."studentId" or new."nurseUid" is distinct from old."nurseUid" then
    raise exception 'O''quvchi va yozgan hamshira o''zgarmaydi' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function app.nurse_visit_stamp() from public, anon, authenticated;
drop trigger if exists trg_nurse_visit_stamp on public.nurse_visits;
create trigger trg_nurse_visit_stamp before insert or update on public.nurse_visits
  for each row execute function app.nurse_visit_stamp();

-- 11) Ota-ona (o'z farzandi) va sinf rahbari / kurator (o'z sinfi): fayl yo'li va tibbiy matnsiz ko'rinishlar.
--   (Ko'rinish egasi huquqida: students subso'rovi RLS'siz; ko'rinishdagi funksiyalarni esa chaqiruvchi bajara olishi
--    kerak — shuning uchun sinf kaliti alohida SECURITY DEFINER funksiya emas, shu yerda subso'rov.)
create or replace view public.my_sick_notes with (security_barrier = true) as
  select n.id, n."studentId", n."fromDay", n."toDay", n."schoolDays", n.status, n.late, n."enteredAt", n."reviewedAt",
         case when app.owns_child(n."studentId") then n."reviewNote" end as "reviewNote",
         case when app.owns_child(n."studentId") then n.institution end as institution,
         case when app.owns_child(n."studentId") then n."noteNumber" end as "noteNumber",
         (select count(*) from jsonb_object_keys(n."appliedDays"))::int as "appliedCount"
    from public.sick_notes n
   where n.status <> 'withdrawn'
     and (app.owns_child(n."studentId")
          or app.is_homeroom_for((select app.student_class_key(s.lang, s.grade, s."classLetter", s.track) from public.students s
                                where s."studentId" = n."studentId" or s.id = n."studentId" order by (s."studentId" = n."studentId") desc limit 1))
          or app.is_kurator_for((select app.student_class_key(s.lang, s.grade, s."classLetter", s.track) from public.students s
                                where s."studentId" = n."studentId" or s.id = n."studentId" order by (s."studentId" = n."studentId") desc limit 1)));
revoke all on public.my_sick_notes from anon;
grant select on public.my_sick_notes to authenticated, service_role;
create or replace view public.my_nurse_visits with (security_barrier = true) as
  select v.id, v."studentId", v.at, v.action, v."parentNotified",
         case when app.owns_child(v."studentId") then v.complaint end as complaint,
         case when app.owns_child(v."studentId") then v.temperature end as temperature
    from public.nurse_visits v
   where app.owns_child(v."studentId")
      or app.is_homeroom_for((select app.student_class_key(s.lang, s.grade, s."classLetter", s.track) from public.students s
                                where s."studentId" = v."studentId" or s.id = v."studentId" order by (s."studentId" = v."studentId") desc limit 1))
      or app.is_kurator_for((select app.student_class_key(s.lang, s.grade, s."classLetter", s.track) from public.students s
                                where s."studentId" = v."studentId" or s.id = v."studentId" order by (s."studentId" = v."studentId") desc limit 1));
revoke all on public.my_nurse_visits from anon;
grant select on public.my_nurse_visits to authenticated, service_role;

-- 12) Faktura: ma'lumotnoma kunlari (o'tish oyidan boshlab) — baza tekshiradi va qo'llangan kunlarni belgilaydi.
alter table public.invoices add column if not exists "sickNoteRefs" jsonb;
create or replace function app.invoice_sick_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_from text; v_rate numeric; v_refs jsonb; v_cnt int := 0; v_k text; v_v jsonb; v_d text; v_n int; v_nd int;
        v_min text; v_changed boolean; v_restore boolean; n public.sick_notes%rowtype;
begin
  if tg_op = 'INSERT' then
    v_changed := true; v_restore := false;
  else
    v_changed := new."sickNoteRefs" is distinct from old."sickNoteRefs" or new."sickDaysApplied" is distinct from old."sickDaysApplied"
              or new."sickAmount" is distinct from old."sickAmount" or new.month is distinct from old.month
              or new."studentId" is distinct from old."studentId" or new.id is distinct from old.id;
    -- Bekor qilingan faktura qayta tiklanmoqda: kunlari boshqa fakturaga o'tib ketmaganini tekshiramiz (summa — o'zgarmagan).
    v_restore := coalesce(old.status, '') in ('canceled', 'reversed') and coalesce(new.status, '') not in ('canceled', 'reversed');
  end if;
  -- Faqat holat/to'lov o'zgarishi (to'lov serveri, kassa) — tekshirilmaydi: stavka keyin o'zgargan bo'lsa ham to'lov o'tadi.
  if not v_changed and not v_restore then return new; end if;
  select nullif(btrim(coalesce(c."sickApprovalFrom", '')), ''), c."sickRate" into v_from, v_rate
    from public.config c where c.id = 'finance';
  v_refs := coalesce(new."sickNoteRefs", '{}'::jsonb);
  if jsonb_typeof(v_refs) = 'null' then v_refs := '{}'::jsonb; end if;
  if jsonb_typeof(v_refs) <> 'object' then
    raise exception 'sickNoteRefs: {ma''lumotnomaId: [kunlar]} ko''rinishida bo''lsin' using errcode = '22023';
  end if;
  if v_from is null or coalesce(new.month, '') < v_from then
    -- Eski qoida (davomatdagi «Bemor»): ma'lumotnoma kunlari bu fakturaga qo'shilmaydi.
    if v_refs <> '{}'::jsonb then
      raise exception 'Bemor kuni ma''lumotnoma bilan faqat o''tish oyidan (%) boshlab hisoblanadi', coalesce(v_from, 'belgilanmagan')
        using errcode = '23514';
    end if;
    return new;
  end if;
  v_min := to_char((v_from || '-01')::date - interval '1 month', 'YYYY-MM-DD');
  for v_k, v_v in select key, value from jsonb_each(v_refs) loop
    select * into n from public.sick_notes where id = v_k;
    if not found or n.status <> 'approved' then
      raise exception 'Hisob-fakturada tasdiqlanmagan ma''lumotnoma kunlari bor' using errcode = '23514';
    end if;
    if n."studentId" is distinct from new."studentId" then
      raise exception 'Ma''lumotnoma boshqa o''quvchiniki' using errcode = '23514';
    end if;
    if jsonb_typeof(v_v) <> 'array' then
      raise exception 'sickNoteRefs: kunlar ro''yxat bo''lsin' using errcode = '22023';
    end if;
    select count(*), count(distinct x) into v_n, v_nd from jsonb_array_elements_text(v_v) x;
    if v_n <> v_nd then raise exception 'sickNoteRefs: bir kun ikki marta' using errcode = '23514'; end if;
    for v_d in select x from jsonb_array_elements_text(v_v) x loop
      if not (n."schoolDays" ? v_d) then
        raise exception 'Kun (%) ma''lumotnomada yo''q', v_d using errcode = '23514';
      end if;
      if v_d < v_min or v_d >= coalesce(new.month, '') || '-01' then
        raise exception 'Kun (%) bu oy fakturasiga tegishli emas', v_d using errcode = '23514';
      end if;
      if coalesce(n."appliedDays"->>v_d, new.id) <> new.id then
        raise exception 'Kun (%) boshqa hisob-fakturada allaqachon hisoblangan', v_d using errcode = '23505';
      end if;
      v_cnt := v_cnt + 1;
    end loop;
  end loop;
  if v_changed then
    if coalesce(new."sickDaysApplied", 0) <> v_cnt then
      raise exception 'Kasal kunlar soni (%) ma''lumotnoma kunlariga (%) mos emas', coalesce(new."sickDaysApplied", 0), v_cnt
        using errcode = '23514';
    end if;
    if round(coalesce(new."sickAmount", 0)) <> round(v_cnt * coalesce(nullif(v_rate, 0), 40000)) then
      raise exception 'Kasal kun summasi (%) kunlar × stavka (%) ga teng emas', coalesce(new."sickAmount", 0),
        round(v_cnt * coalesce(nullif(v_rate, 0), 40000)) using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
revoke all on function app.invoice_sick_guard() from public, anon, authenticated;
drop trigger if exists trg_invoice_sick_guard on public.invoices;
create trigger trg_invoice_sick_guard before insert or update on public.invoices
  for each row execute function app.invoice_sick_guard();

create or replace function app.invoice_sick_apply() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_k text; v_v jsonb; v_old jsonb; v_new jsonb; v_active boolean;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    v_old := case when jsonb_typeof(old."sickNoteRefs") = 'object' then old."sickNoteRefs" else '{}'::jsonb end;
  else v_old := '{}'::jsonb; end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_new := case when jsonb_typeof(new."sickNoteRefs") = 'object' then new."sickNoteRefs" else '{}'::jsonb end;
    v_active := coalesce(new.status, '') not in ('canceled', 'reversed');
  else v_new := '{}'::jsonb; v_active := false; end if;
  if tg_op = 'UPDATE' then
    if v_old = v_new and new.id = old.id
       and (coalesce(old.status, '') in ('canceled', 'reversed')) = (coalesce(new.status, '') in ('canceled', 'reversed')) then
      return new;
    end if;
  end if;
  if v_old = '{}'::jsonb and v_new = '{}'::jsonb then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  perform set_config('iqror.sick_rpc', '1', true);
  -- Avvalgi bog'lanishlarni bo'shatish (faqat shu fakturaga ko'rsatgan kunlar).
  if tg_op in ('UPDATE', 'DELETE') then
    for v_k in select key from jsonb_each(v_old) loop
      update public.sick_notes n
         set "appliedDays" = coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(n."appliedDays") e
                                        where e.value <> to_jsonb(old.id)), '{}'::jsonb)
       where n.id = v_k;
    end loop;
  end if;
  if tg_op in ('INSERT', 'UPDATE') and v_active then
    for v_k, v_v in select key, value from jsonb_each(v_new) loop
      update public.sick_notes n
         set "appliedDays" = n."appliedDays" || coalesce((select jsonb_object_agg(x, to_jsonb(new.id))
                                                          from jsonb_array_elements_text(v_v) x), '{}'::jsonb)
       where n.id = v_k;
    end loop;
  end if;
  perform set_config('iqror.sick_rpc', '', true);
  return case when tg_op = 'DELETE' then old else new end;
end $$;
revoke all on function app.invoice_sick_apply() from public, anon, authenticated;
drop trigger if exists trg_invoice_sick_apply on public.invoices;
create trigger trg_invoice_sick_apply after insert or update or delete on public.invoices
  for each row execute function app.invoice_sick_apply();

-- 13) Ketgan / muzlatilgan o'quvchi: tasdiqlangan, hali qo'llanmagan kunlar — avansga (faqat tasdiqlovchi amali).
--     Kun hisoblanadi, agar o'sha oy fakturasi bor, bekor/qaytarilgan/grant emas, asosiy narx > 0, kun hisoblangan
--     oraliqda (billedFrom..billedTo) va to'xtatilgan davrda emas bo'lsa (fakturadagi qoida bilan bir xil).
create or replace function public.sick_note_refund(p_id text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); n public.sick_notes%rowtype; s record; v_from text; v_rate numeric; v_min text;
        v_days text[] := '{}'; v_d text; v_inv record; v_amt numeric; v_cr numeric; v_lid text; v_map jsonb := '{}'::jsonb;
begin
  if v_uid is null or not app.is_finance_mgr() then
    raise exception 'Ruxsat yo''q: faqat Moliya menejeri yoki Direktor' using errcode = '42501';
  end if;
  select * into n from public.sick_notes where id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if n.status <> 'approved' then return jsonb_build_object('ok', false, 'reason', 'not_approved'); end if;
  select st.* into s from public.students st where st."studentId" = n."studentId" or st.id = n."studentId"
   order by (st."studentId" = n."studentId") desc limit 1;
  if not found or coalesce(s."payStatus", '') not in ('chiqdi', 'muzlatilgan') then
    return jsonb_build_object('ok', false, 'reason', 'not_left');   -- o'qiyotgan o'quvchida kunlar keyingi fakturada
  end if;
  select nullif(btrim(coalesce(c."sickApprovalFrom", '')), ''), c."sickRate" into v_from, v_rate from public.config c where c.id = 'finance';
  if v_from is null then return jsonb_build_object('ok', false, 'reason', 'no_cutover'); end if;
  v_min := to_char((v_from || '-01')::date - interval '1 month', 'YYYY-MM-DD');
  perform pg_advisory_xact_lock(hashtext('iqror_pay:' || n."studentId"));   -- avans bilan ishlovchi boshqa RPC'lar bilan bir qulf
  for v_d in select x from jsonb_array_elements_text(n."schoolDays") x order by x loop
    if v_d < v_min or n."appliedDays" ? v_d then continue; end if;
    select i.id, i.status, i."isGrant", i.provider, coalesce(i."baseAmount", i.amount) as base, i."billedFrom", i."billedTo"
      into v_inv from public.invoices i where i."studentId" = n."studentId" and i.month = substr(v_d, 1, 7)
     order by (i.id = n."studentId" || '__' || substr(v_d, 1, 7)) desc limit 1;
    if not found or coalesce(v_inv.status, '') in ('canceled', 'reversed') or coalesce(v_inv."isGrant", false)
       or coalesce(v_inv.provider, '') = 'grant' or not (coalesce(v_inv.base, 0) > 0) then continue; end if;
    if coalesce(v_inv."billedFrom", '') <> '' and coalesce(v_inv."billedTo", '') <> ''
       and (v_d < v_inv."billedFrom" or v_d > v_inv."billedTo") then continue; end if;
    if jsonb_typeof(s.pauses) = 'array' and exists (
         select 1 from jsonb_array_elements(s.pauses) p
          where coalesce(p->>'from', '') <> '' and coalesce(p->>'to', '') <> ''
            and v_d between substr(p->>'from', 1, 10) and substr(p->>'to', 1, 10)) then continue; end if;
    v_days := v_days || v_d;
  end loop;
  if coalesce(array_length(v_days, 1), 0) = 0 then return jsonb_build_object('ok', false, 'reason', 'nothing'); end if;
  v_amt := array_length(v_days, 1) * coalesce(nullif(v_rate, 0), 40000);
  v_lid := gen_random_uuid()::text;
  select coalesce(credit, 0) into v_cr from public.student_credit where id = n."studentId" for update;
  if not found then v_cr := 0; end if;
  insert into public.student_credit(id, "studentId", credit, "updatedAt") values (n."studentId", n."studentId", v_cr + v_amt, now())
    on conflict (id) do update set credit = excluded.credit, "updatedAt" = now();
  insert into public.credit_ledger(id, "studentId", "studentName", delta, "balanceAfter", reason, provider, month, note, "at")
    values (v_lid, n."studentId", coalesce(s.name, ''), v_amt, v_cr + v_amt, 'sick_refund', 'sick', substr(v_days[1], 1, 7),
            'Kasal kunlar (ma''lumotnoma, ' || array_length(v_days, 1) || ' kun) — avansga qaytarildi', now());
  select jsonb_object_agg(d, 'credit:' || v_lid) into v_map from unnest(v_days) d;
  perform set_config('iqror.sick_rpc', '1', true);
  update public.sick_notes set "appliedDays" = "appliedDays" || v_map where id = p_id;
  perform set_config('iqror.sick_rpc', '', true);
  return jsonb_build_object('ok', true, 'days', array_length(v_days, 1), 'amount', v_amt);
end $$;
revoke all on function public.sick_note_refund(text) from public, anon;
grant execute on function public.sick_note_refund(text) to authenticated, service_role;

-- 14) O'zgarishlar tarixi (change-log.sql bilan bir xil ro'yxatlar).
select app.chlog_attach('sick_notes',     'studentId,fromDay,toDay,status,reviewNote,appliedDays');
select app.chlog_attach('student_health', '!allergies,!chronic,!medications,!note');
select app.chlog_attach('invoices',       'studentId,month,amount,paidAmount,status,baseAmount,discount,pctApplied,isGrant,sickAmount,sickDaysApplied,sickNoteRefs,billedFrom,billedTo');
select app.chlog_attach('config',         '!refundPin,sickRate,sickApprovalFrom,lessonRate,latePenalty,earlyPenalty,allowedBreakMin,breakPenaltyPerHour,clickServiceId,clickMerchantId,uzumUrlTemplate,flatAmount,perYear,monthsPerYear,tenureYears,yearsCap,degree,category,languages,russian,langLevel');

notify pgrst, 'reload schema';
