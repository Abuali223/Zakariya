\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: leave-paid.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- leave-paid.sql — XODIM TA'TILI: HAQLI / HAQSIZ (direktor qarori D5, 2026-10-30).
--   «Xodimning o'z arizasi bilan olgan ta'tiliga haq to'lanmaydi.» Kasallik va yillik mehnat ta'tili — haqli.
--   Turlar: 'ruhsat'   — o'z arizasi bilan (HAQSIZ: ish kuniga kunlik stavka ushlanadi — admin.html attMetrics);
--           'kasallik' — bemorlik (haqli, ushlanma yo'q);
--           'mehnat'   — yillik mehnat ta'tili (haqli, ushlanma yo'q).
--   "paid" — turdan bazada aniqlanadi (mijoz yuborgan qiymat e'tiborsiz): ekran yoki REST orqali «ruhsat + paid=true»
--   yozib bo'lmaydi. Bir xodimga ustma-ust tushadigan ta'til yozilmaydi (aks holda bitta kun ikki marta sanalardi).
--   Jonli bazada 2026-10-30 holatida staff_leaves bo'sh — eski oylar hisobiga ta'sir yo'q.
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

alter table public.staff_leaves add column if not exists paid boolean;

-- 1) Mavjud qatorlarni tozalash: bo'sh/noma'lum tur — 'ruhsat' (ekran faqat ruhsat/kasallik yozgan; noma'lum qiymat
--    bo'lmasligi kerak, bo'lsa — o'z arizasi deb olinadi va HR ro'yxatda ko'radi), sanalar teskari bo'lsa — almashtiriladi.
update public.staff_leaves set type = 'ruhsat'
 where type is null or btrim(type) = '' or btrim(type) not in ('ruhsat', 'kasallik', 'mehnat');
update public.staff_leaves set type = btrim(type) where type <> btrim(type);
update public.staff_leaves set "endDay" = "startDay" where coalesce("endDay", '') = '' and coalesce("startDay", '') <> '';
update public.staff_leaves set "startDay" = "endDay", "endDay" = "startDay"
 where coalesce("startDay", '') <> '' and coalesce("endDay", '') <> '' and "startDay" > "endDay";
update public.staff_leaves set paid = (type <> 'ruhsat') where paid is distinct from (type <> 'ruhsat');

-- 2) Qoidalar.
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.staff_leaves'::regclass and conname = 'staff_leaves_type_chk') then
    alter table public.staff_leaves add constraint staff_leaves_type_chk check (type in ('ruhsat', 'kasallik', 'mehnat'));
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.staff_leaves'::regclass and conname = 'staff_leaves_days_chk') then
    alter table public.staff_leaves add constraint staff_leaves_days_chk check (
      "startDay" ~ '^\d{4}-\d{2}-\d{2}$' and "endDay" ~ '^\d{4}-\d{2}-\d{2}$' and "startDay" <= "endDay") not valid;
    -- NOT VALID: eski buzuq qator (sana yo'q) bo'lsa deploy to'xtamasin — yangi va o'zgargan qatorlarga baribir qo'llanadi.
  end if;
end $$;

-- 3) Trigger: "paid" turdan; tur bo'sh bo'lsa — 'ruhsat'; «Gacha» bo'sh — «Dan»; ustma-ust ta'til — rad.
-- Bazaning o'zi (psql / migratsiya — JWT va SET ROLE yo'q) yoki server (service_role). Anonim va oddiy foydalanuvchi — EMAS.
--   BEFORE trigger'lar RLS'dan OLDIN ishlaydi: «app.uid() is null» anonimni ham o'z ichiga olardi (anonim INSERT urinib
--   23P01 / 23503 kabi xatolardan boshqa yozuvlar borligini bilib olardi) — shuning uchun alohida tekshiruv.
create or replace function app.is_system() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.uid() is null
     and coalesce(nullif(current_setting('role', true), ''), 'none') not in ('anon', 'authenticated')
     and coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') not in ('anon', 'authenticated')
$$;
create or replace function app.staff_leave_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_other text;
begin
  new.type := coalesce(nullif(btrim(coalesce(new.type, '')), ''), 'ruhsat');
  if coalesce(new."endDay", '') = '' then new."endDay" := new."startDay"; end if;
  new.paid := (new.type <> 'ruhsat');
  -- Ustma-ust tekshiruvi faqat yozish huquqi borlarga (director/HR, server): aks holda ruxsatsiz foydalanuvchi INSERT urinib
  --   23P01 / 42501 farqidan boshqa xodimning ta'tili borligini bilib olardi (trigger RLS tekshiruvidan OLDIN ishlaydi).
  if (app.is_system() or app.is_admin() or app.is_hr())
     and coalesce(new."refType", '') <> '' and coalesce(new."refId", '') <> ''
     and coalesce(new."startDay", '') <> '' and coalesce(new."endDay", '') <> '' then
    select l.id into v_other from public.staff_leaves l
     where l."refType" = new."refType" and l."refId" = new."refId" and l.id <> new.id
       and l."startDay" <= new."endDay" and l."endDay" >= new."startDay"
     limit 1;
    if v_other is not null then
      raise exception 'Bu xodimga shu kunlarda ta''til allaqachon kiritilgan — avvalgisini o''chiring yoki boshqa sana tanlang'
        using errcode = '23P01';
    end if;
  end if;
  return new;
end $$;
revoke all on function app.staff_leave_guard() from public, anon, authenticated;
drop trigger if exists trg_staff_leave_guard on public.staff_leaves;
create trigger trg_staff_leave_guard before insert or update on public.staff_leaves
  for each row execute function app.staff_leave_guard();

-- 4) O'zgarishlar tarixi: "paid" ham yoziladi (change-log.sql'dagi ro'yxat bilan bir xil).
select app.chlog_attach('staff_leaves', 'refType,refId,type,paid,startDay,endDay');

notify pgrst, 'reload schema';
