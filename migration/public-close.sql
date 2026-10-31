\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: public-close.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- public-close.sql — OMMAVIY SAYTNI YOPISH (direktor qarorlari D6, D8, D9; PKG-1).
--
--   D6: o'quvchi ma'lumoti ommaga (anon) HECH NARSA. Faqat o'quvchi, ota-onasi, dars beruvchi ustozlar, qabulxona,
--       O'IBDO' va Direktor ko'radi. Avval anon so'rov ommaviy o'quvchi ko'rinishidan 380 qator (ism, sinf, ball, rasm,
--       poster) olardi; saytda «A'lochilar» bo'limi, ismli yutuqlar va ismli sharhlar bor edi; storage 'public' papkasi
--       anon uchun ro'yxatlanardi.
--
--   1) students_public ko'rinishi O'CHIRILADI (rls.sql / security-2c.sql endi uni yaratmaydi — har deployda
--      «yaratib-o'chirish» bo'lmasin). Ota-ona kabineti farzand qatorini xom students jadvalidan (owns_student_doc RLS)
--      oladi; sinfdagi o'rni va o'quvchilar soni — child_card(sid) RPC (faqat yig'ma sonlar, boshqa bolaning ismi/bali yo'q).
--   2) Hujjatni tekshirish TOKEN bilan: issued_documents + issue_doc_token(sid, kind) + verify_doc(token) (anon). QR'da
--      endi o'quvchi ID emas, 128 bitli tasodifiy kod; tekshiruv sahifasi faqat «haqiqiy/emas, turi, berilgan sana, qisqa
--      ism (Aziza K.), sinf raqami»ni ko'rsatadi.
--   3) Ismli yutuqlar/sharhlar: achievements_students.name saytda HECH QACHON chiqmaydi (yangi «label» — «7-sinf
--      o'quvchisi»); testimonials.name faqat «nameConsent» (yozma rozilik) bo'lsa saqlanadi. Mavjud ismlar avval faqat
--      direktor o'qiy oladigan public_names_backup jadvaliga olinadi, keyin tozalanadi; BEFORE trigger REST orqali
--      yozilgan ismni ham tozalaydi.
--   4) Storage: storage.objects SELECT faqat xodimlarga (ro'yxat olish). Ommaviy URL'lar (/storage/v1/object/public/...)
--      Supabase'da RLS'siz beriladi — saytdagi rasmlar ko'rinishda davom etadi, lekin anon papka ro'yxatini ololmaydi.
--
-- Joyi: zanjirda change-log.sql (chlog_attach), parent-link-canon.sql (owns_student_doc), auth-hardening.sql (is_staff,
--   is_reception) va attendance-sync.sql (tashkent_now) DAN KEYIN; rls-initplan.sql (oxirgi) bu yerdagi public
--   policy'larni o'zi o'raydi.
-- Idempotent — QAYTA ishga tushirishga xavfsiz: zaxiraga ikkinchi marta yozilmaydi (tbl, row_id kaliti; bo'sh ism
--   zaxiralanmaydi), tozalangan ism qayta tozalanmaydi.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- ---------- 1) Ommaviy o'quvchi ro'yxati — YO'Q ----------
-- Bog'liq obyekt yo'q (boshqa view/funksiya undan o'qimaydi); bo'lsa — CASCADE'siz xato beradi (jim o'chirib yubormaydi).
drop view if exists public.students_public;

-- ---------- 2) Ism zaxirasi (faqat direktor o'qiydi) ----------
create table if not exists public.public_names_backup (
  tbl       text not null,                         -- qaysi jadvaldan (achievements_students | testimonials)
  row_id    text not null,                         -- o'sha jadvaldagi yozuv id
  name      text not null,                         -- tozalangan ism (saytda endi ko'rinmaydi)
  saved_at  timestamptz not null default now(),
  primary key (tbl, row_id)                        -- bir yozuv ismi bir marta zaxiralanadi
);
alter table public.public_names_backup enable row level security;
revoke all on public.public_names_backup from anon, authenticated;
grant select on public.public_names_backup to authenticated;
grant all on public.public_names_backup to service_role;
drop policy if exists pnb_sel on public.public_names_backup;
create policy pnb_sel on public.public_names_backup for select using (app.is_admin());
-- insert / update / delete siyosati YO'Q: mijoz yozolmaydi (faqat shu migratsiya, postgres huquqida).

-- ---------- 3) O'quvchi yutuqlari — ismsiz ----------
alter table public.achievements_students add column if not exists label    text;   -- «7-sinf o'quvchisi» (ismsiz)
alter table public.achievements_students add column if not exists label_ru text;   -- «ученик 7 класса»

-- BEFORE trigger: ism hech qachon saqlanmaydi (admin panel ham, to'g'ridan-to'g'ri REST ham, eski kesh oyna ham).
create or replace function app.ach_students_noname() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  new.name := null;
  return new;
end $$;

-- ---------- 4) Ota-ona sharhlari — ism faqat yozma rozilik bilan ----------
alter table public.testimonials add column if not exists "nameConsent" boolean not null default false;

create or replace function app.testimonials_name_consent() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if not coalesce(new."nameConsent", false) then new.name := null; end if;
  return new;
end $$;

-- Mavjud ismlar: AVVAL zaxira (bo'sh ism — yo'q; allaqachon zaxiralangan — qayta yozilmaydi), KEYIN tozalash.
insert into public.public_names_backup (tbl, row_id, name)
select 'achievements_students', a.id, a.name from public.achievements_students a
 where coalesce(btrim(a.name), '') <> ''
on conflict (tbl, row_id) do nothing;
insert into public.public_names_backup (tbl, row_id, name)
select 'testimonials', t.id, t.name from public.testimonials t
 where coalesce(btrim(t.name), '') <> '' and not t."nameConsent"
on conflict (tbl, row_id) do nothing;

drop trigger if exists trg_ach_students_noname on public.achievements_students;
create trigger trg_ach_students_noname before insert or update on public.achievements_students
  for each row execute function app.ach_students_noname();
drop trigger if exists trg_testimonials_name_consent on public.testimonials;
create trigger trg_testimonials_name_consent before insert or update on public.testimonials
  for each row execute function app.testimonials_name_consent();

update public.achievements_students set name = null where name is not null;
update public.testimonials set name = null where name is not null and not "nameConsent";

-- ---------- 5) Storage: papka ro'yxati faqat xodimlarga ----------
-- storage-rls.sql endi ommaviy o'qish siyosatini yaratmaydi (is_staff u yerda hali yo'q). Yuklash (shim upsert:true ->
--   INSERT ... ON CONFLICT DO UPDATE ... RETURNING) va o'chirish SELECT'ni ham talab qiladi — yuklaydiganlar (iqror_admin_insert:
--   direktor, HR, O'IBDO') bu ro'yxatda: is_admin/is_zavuch ATAYLAB status tekshirmaydi (loyiha qoidasi — rahbar tasodifan
--   qulflanmasin), shuning uchun ular alohida qo'shilgan (aks holda status'i o'zgargan direktor rasm yuklay olmay qolardi).
--   Ommaviy havola (getPublicUrl) — so'rovsiz, RLS'siz. (select ...) — so'rov boshida bir marta (rls-initplan storage'ga tegmaydi).
drop policy if exists iqror_public_read on storage.objects;
drop policy if exists iqror_staff_read on storage.objects;
create policy iqror_staff_read on storage.objects
  for select using ( bucket_id = 'public' and ((select app.is_staff()) or (select app.is_admin()) or (select app.is_zavuch())) );

-- ---------- 6) Hujjat tokenlari ----------
create table if not exists public.issued_documents (
  id          text primary key default gen_random_uuid()::text,
  token       text not null unique,                -- 32 hex (128 bit tasodifiy) — QR ichida
  sid         text not null,                       -- o'quvchi KANONIK kaliti (studentId, bo'sh bo'lsa doc id)
  kind        text not null,                       -- profile | certificate
  "issuedAt"  timestamptz not null default now(),
  "issuedBy"  text,                                -- users.id
  "revokedAt" timestamptz,
  "revokedBy" text
);
-- Bir (o'quvchi, hujjat turi) uchun bitta amaldagi kod: hujjat qayta chop etilsa ham QR o'zgarmaydi.
create unique index if not exists issued_documents_active_uq on public.issued_documents (sid, kind) where "revokedAt" is null;
alter table public.issued_documents enable row level security;
revoke all on public.issued_documents from anon, authenticated;
grant all on public.issued_documents to service_role;
-- Siyosat YO'Q: mijoz to'g'ridan-to'g'ri o'qiy/yoza olmaydi — faqat issue_doc_token / verify_doc orqali.
-- Kim, qachon, kimga hujjat bergani — o'zgarishlar tarixida (kod qiymati yozilmaydi).
select app.chlog_attach('issued_documents', 'sid,kind,issuedBy,revokedAt,revokedBy,!token');

-- Qisqa ism: «Aziza Karimova» -> «Aziza K.». Birinchi so'z familiyaga o'xshasa («Karimova Aziza») — ikkinchisi ism.
create or replace function app.short_name(p text) returns text
language plpgsql immutable set search_path = pg_catalog, pg_temp as $$
declare w text[]; f text; l text;
begin
  w := regexp_split_to_array(btrim(coalesce(p, '')), '\s+');
  if coalesce(array_length(w, 1), 0) = 0 or w[1] = '' then return null; end if;
  if array_length(w, 1) = 1 then return w[1]; end if;
  f := w[1]; l := w[2];
  if char_length(w[1]) > 4 and w[1] ~* '(ov|ova|ev|eva|yev|yeva)$|(ов|ова|ев|ева|ОВ|ОВА|ЕВ|ЕВА)$'
     and not (w[2] ~* '(ov|ova|ev|eva|yev|yeva)$|(ов|ова|ев|ева|ОВ|ОВА|ЕВ|ЕВА)$') then
    f := w[2]; l := w[1];
  end if;
  return f || ' ' || upper(left(l, 1)) || '.';
end $$;

-- Hujjat kodi berish: direktor, O'IBDO', qabulxona (rasmiy profilni chop etadiganlar) — istalgan o'quvchiga;
--   o'quvchining FAOL egasi (ota-ona / o'quvchi o'zi — child_claims) — faqat o'z farzandiga va faqat 'profile'.
--   Amaldagi kod bo'lsa — o'shani qaytaradi (hujjatga bitta kod, ko'p marta tekshiriladi).
create or replace function public.issue_doc_token(p_sid text, p_kind text)
returns text language plpgsql volatile security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_staff boolean; v_n int; v_doc text; v_canon text; v_tok text;
begin
  if v_uid is null then raise exception 'auth required' using errcode = '42501'; end if;
  p_sid := btrim(coalesce(p_sid, '')); p_kind := btrim(coalesce(p_kind, ''));
  if p_kind not in ('profile', 'certificate') then raise exception 'noma''lum hujjat turi' using errcode = '22023'; end if;
  v_staff := app.is_admin() or app.is_zavuch() or app.is_reception();
  if v_staff then
    select count(*), min(t.id) into v_n, v_doc from public.students t
     where p_sid <> '' and (t.id = p_sid or t."studentId" = p_sid);
    if v_n <> 1 then raise exception 'o''quvchi topilmadi yoki ID takrorlangan' using errcode = 'P0002'; end if;
  else
    -- Egasi: ruxsat tekshiruvi AVVAL (begona ID mavjudligi ham bilinmasin).
    if p_kind <> 'profile' then raise exception 'ruxsat yo''q' using errcode = '42501'; end if;
    select count(*), min(t.id) into v_n, v_doc from public.students t
     where p_sid <> '' and (t.id = p_sid or t."studentId" = p_sid) and app.owns_student_doc(t.id);
    if v_n <> 1 then raise exception 'ruxsat yo''q' using errcode = '42501'; end if;
  end if;
  select coalesce(nullif(btrim(t."studentId"), ''), t.id) into v_canon from public.students t where t.id = v_doc;
  select d.token into v_tok from public.issued_documents d
   where d.sid = v_canon and d.kind = p_kind and d."revokedAt" is null;
  if v_tok is not null then return v_tok; end if;
  insert into public.issued_documents (token, sid, kind, "issuedBy")
  values (left(encode(sha256(convert_to(gen_random_uuid()::text || gen_random_uuid()::text, 'UTF8')), 'hex'), 32),
          v_canon, p_kind, v_uid)
  on conflict (sid, kind) where "revokedAt" is null do nothing
  returning token into v_tok;
  if v_tok is null then   -- parallel chaqiruv birinchi yozdi — o'shaniki
    select d.token into v_tok from public.issued_documents d
     where d.sid = v_canon and d.kind = p_kind and d."revokedAt" is null;
  end if;
  return v_tok;
end $$;
revoke all on function public.issue_doc_token(text, text) from public, anon;
grant execute on function public.issue_doc_token(text, text) to authenticated, service_role;

-- Hujjatni tekshirish (anon ham): FAQAT valid, kind, issuedAt (sana), qisqa ism, sinf raqami. ID, JSHSHIR, ball,
--   telefon — yo'q. Noto'g'ri formatdagi kod bazaga so'rov qilmaydi; noto'g'ri / bekor qilingan kod — valid=false.
create or replace function public.verify_doc(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare d public.issued_documents%rowtype; v_n int; v_name text; v_grade int;
begin
  p_token := lower(btrim(coalesce(p_token, '')));
  if p_token !~ '^[0-9a-f]{32}$' then return jsonb_build_object('valid', false); end if;
  select * into d from public.issued_documents x where x.token = p_token;
  if not found or d."revokedAt" is not null then return jsonb_build_object('valid', false); end if;
  select count(*), min(s.name), min(s.grade) into v_n, v_name, v_grade
    from public.students s where s.id = d.sid or s."studentId" = d.sid;
  return jsonb_build_object('valid', true, 'kind', d.kind,
    'issuedAt', to_char(d."issuedAt" at time zone 'Asia/Tashkent', 'YYYY-MM-DD'),
    'name', case when v_n = 1 then app.short_name(v_name) end,
    'grade', case when v_n = 1 then v_grade end);
end $$;
revoke all on function public.verify_doc(text) from public;
grant execute on function public.verify_doc(text) to anon, authenticated, service_role;

-- ---------- 7) Kabinet kartasi: sinfdagi o'rni va o'quvchilar soni ----------
-- Faqat chaqiruvchi shu o'quvchining FAOL egasi bo'lsa (owns_student_doc — ota-ona yoki o'quvchi o'zi), aks holda xato.
--   Sinf = classKeyOf (admin.html): til-sinf-guruh (guruh bo'sh bo'lsa yo'nalish). Ketganlar («chiqdi», ketish sanasi
--   kelgan) sanalmaydi (o'chirilganlar jadvalda yo'q); o'quvchi o'zi doim sanaladi. O'rni = 1 + undan yuqori balli
--   sinfdoshlar soni (ball kiritilmagan bo'lsa — null). Boshqa bolaning ismi/bali QAYTARILMAYDI.
create or replace function public.child_card(p_sid text)
returns jsonb language plpgsql stable security definer set search_path = public, app, pg_temp as $$
declare v_uid text := app.uid(); v_n int; v_doc text; v_s public.students%rowtype; v_ck text; v_today text;
        v_size int; v_rank int;
begin
  if v_uid is null then raise exception 'auth required' using errcode = '42501'; end if;
  p_sid := btrim(coalesce(p_sid, ''));
  select count(*), min(t.id) into v_n, v_doc from public.students t
   where p_sid <> '' and (t.id = p_sid or t."studentId" = p_sid) and app.owns_student_doc(t.id);
  if v_n <> 1 then raise exception 'ruxsat yo''q' using errcode = '42501'; end if;
  select * into v_s from public.students where id = v_doc;
  v_today := to_char(app.tashkent_now()::date, 'YYYY-MM-DD');
  v_ck := coalesce(nullif(v_s.lang, ''), 'uz') || '-' || coalesce(v_s.grade, 0)::text || '-'
       || coalesce(nullif(v_s."classLetter", ''), nullif(v_s.track, ''), '-');
  with cls as (
    select t.id, t.score from public.students t
     where coalesce(nullif(t.lang, ''), 'uz') || '-' || coalesce(t.grade, 0)::text || '-'
           || coalesce(nullif(t."classLetter", ''), nullif(t.track, ''), '-') = v_ck
       and (t.id = v_s.id
            or not (coalesce(t."payStatus", '') = 'chiqdi'
                    and not (left(coalesce(t."stopFrom", ''), 10) ~ '^\d{4}-\d{2}-\d{2}$'
                             and left(t."stopFrom", 10) >= v_today))))
  select count(*), case when v_s.score is null then null
                        else 1 + count(*) filter (where c.id <> v_s.id and c.score > v_s.score) end
    into v_size, v_rank from cls c;
  return jsonb_build_object('rank', v_rank, 'size', v_size);
end $$;
revoke all on function public.child_card(text) from public, anon;
grant execute on function public.child_card(text) to authenticated, service_role;

notify pgrst, 'reload schema';
