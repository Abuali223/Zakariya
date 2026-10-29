\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: change-log.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- change_log — O'ZGARISHLAR TARIXI (audit jurnali).
--   Pulga (faktura, to'lov, avans), maoshga va huquqlarga (rol, biriktirish, ota-ona bog'lanishi) ta'sir qiladigan har o'zgarish yoziladi: KIM (foydalanuvchi, rol), QACHON,
--   QAYSI jadval/yozuv, QAYSI maydon: eski -> yangi. Yozuvni FAQAT bazaning triggerlari qiladi — ekranni yoki
--   eski oynani chetlab o'tib bo'lmaydi. Ko'rish — faqat direktor («O'zgarishlar tarixi» bo'limi).
--   Server (Click/Uzum to'lovi, avtomatik ishlar) qilgan o'zgarish: actor bo'sh = «Tizim».
--   Deploy (migratsiya) paytidagi ma'lumot tuzatishlari yozilmaydi (iqror.migrating = '1' — run-all.sql).
--   Maxfiy qiymatlar (qaytarish PIN'i, farzand kodi, login telefon/email) yozilmaydi — faqat «o'zgardi» belgisi ('!' prefiksli ustun).
--   Jurnal yozilmasa (kutilmagan xato) — asosiy amal TO'XTAMAYDI (WARNING logga): maktab ishi to'xtab qolmasin.
--   Qatnashadigan jadval va ustunlar — pastdagi app.chlog_attach(...) ro'yxati.
-- Idempotent (run-all.sql zanjirida; deploy har safar qayta qo'llaydi).
-- =====================================================================

create table if not exists public.change_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  actor_uid   text,                          -- users.id (null = tizim / server)
  actor_role  text,                          -- o'sha paytdagi rol
  actor_name  text,                          -- o'sha paytdagi ism (yoki email/telefon)
  tbl         text not null,                 -- jadval
  row_id      text not null,                 -- yozuv id
  op          text not null,                 -- INSERT | UPDATE | DELETE
  changes     jsonb not null default '{}'::jsonb   -- {maydon: [eski, yangi]} ; davomat: {sick_added:[..], sick_removed:[..]}
);
create index if not exists change_log_at_idx  on public.change_log (at desc);
create index if not exists change_log_row_idx on public.change_log (tbl, row_id);

alter table public.change_log enable row level security;
revoke all on public.change_log from anon, authenticated;
grant select on public.change_log to authenticated;
grant all on public.change_log to service_role;
drop policy if exists chlog_sel on public.change_log;
create policy chlog_sel on public.change_log for select using (app.is_admin());
-- insert / update / delete siyosati YO'Q: mijoz yozolmaydi va o'chira olmaydi (faqat trigger — security definer).

-- Kim o'zgartirdi (JWT bo'lmasa — null: tizim).
create or replace function app.chlog_actor(out o_uid text, out o_role text, out o_name text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  begin o_uid := app.uid(); exception when others then o_uid := null; end;
  if o_uid is not null then
    select u.role, coalesce(nullif(btrim(u.name), ''), nullif(btrim(u.email), ''), u.phone)
      into o_role, o_name from public.users u where u.id = o_uid;
  end if;
end $$;

-- Umumiy trigger: tg_argv[0] = kuzatiladigan ustunlar ('a,b,!maxfiy'). UPDATE — faqat o'zgargan ustunlar;
--   INSERT/DELETE — bo'sh bo'lmagan ustunlar qiymati. Kuzatilgan ustun o'zgarmagan UPDATE — yozilmaydi.
create or replace function app.log_change() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_cols text[] := string_to_array(coalesce(tg_argv[0], ''), ',');
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_ch jsonb := '{}'::jsonb;
  c text; k text; secret boolean; o jsonb; n jsonb; a record;
begin
  if coalesce(current_setting('iqror.migrating', true), '') = '1' then return null; end if;
  foreach c in array v_cols loop
    c := btrim(c);
    continue when c = '';
    secret := left(c, 1) = '!';
    k := case when secret then substr(c, 2) else c end;
    o := v_old -> k;
    n := v_new -> k;
    if tg_op = 'UPDATE' and o is not distinct from n then continue; end if;
    if tg_op = 'INSERT' and (n is null or n = 'null'::jsonb or n = '""'::jsonb) then continue; end if;
    if tg_op = 'DELETE' and (o is null or o = 'null'::jsonb or o = '""'::jsonb) then continue; end if;
    v_ch := v_ch || jsonb_build_object(k, case when secret then jsonb_build_array('***', '***') else jsonb_build_array(o, n) end);
  end loop;
  if tg_op = 'UPDATE' and v_ch = '{}'::jsonb then return null; end if;
  a := app.chlog_actor();
  insert into public.change_log (actor_uid, actor_role, actor_name, tbl, row_id, op, changes)
  values (a.o_uid, a.o_role, a.o_name, tg_table_name, coalesce(v_new ->> 'id', v_old ->> 'id', ''), tg_op, v_ch);
  return null;
exception when others then
  raise warning 'change_log yozilmadi (%): %', tg_table_name, sqlerrm;
  return null;
end $$;

-- Davomat: faqat «Bemor» (sick) kunlari o'zgarganda yoziladi — har kuni har sinf saqlanganda jurnal to'lmasin.
--   «Bemor» kuni keyingi oy to'lovini kamaytiradi, shuning uchun kim qo'yganini bilish kerak.
create or replace function app.log_sick_change() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_o text[] := '{}'; v_n text[] := '{}'; v_add text[]; v_rem text[]; a record;
begin
  if coalesce(current_setting('iqror.migrating', true), '') = '1' then return null; end if;
  if tg_op <> 'INSERT' and jsonb_typeof(old.days) = 'object' then
    select coalesce(array_agg(e.key order by e.key), '{}') into v_o from jsonb_each_text(old.days) e where e.value = 'sick';
  end if;
  if tg_op <> 'DELETE' and jsonb_typeof(new.days) = 'object' then
    select coalesce(array_agg(e.key order by e.key), '{}') into v_n from jsonb_each_text(new.days) e where e.value = 'sick';
  end if;
  v_add := array(select x from unnest(v_n) x except select y from unnest(v_o) y order by 1);
  v_rem := array(select x from unnest(v_o) x except select y from unnest(v_n) y order by 1);
  if cardinality(v_add) = 0 and cardinality(v_rem) = 0 then return null; end if;
  a := app.chlog_actor();
  insert into public.change_log (actor_uid, actor_role, actor_name, tbl, row_id, op, changes)
  values (a.o_uid, a.o_role, a.o_name, tg_table_name,
          coalesce(case when tg_op <> 'DELETE' then new.id end, old.id, ''), tg_op,
          jsonb_build_object('month', coalesce(case when tg_op <> 'DELETE' then new.month end, old.month),
                             'studentId', coalesce(case when tg_op <> 'DELETE' then new."studentId" end, old."studentId"),
                             'sick_added', to_jsonb(v_add), 'sick_removed', to_jsonb(v_rem)));
  return null;
exception when others then
  raise warning 'change_log (davomat) yozilmadi: %', sqlerrm;
  return null;
end $$;

-- Trigger ulash (jadval bo'lmasa — o'tkaziladi; har deployda qayta yaratiladi, ustun ro'yxati yangilanadi).
create or replace function app.chlog_attach(p_tbl text, p_cols text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if to_regclass('public.' || quote_ident(p_tbl)) is null then return; end if;
  execute format('drop trigger if exists trg_change_log on public.%I', p_tbl);
  execute format('create trigger trg_change_log after insert or update or delete on public.%I for each row execute function app.log_change(%L)', p_tbl, p_cols);
end $$;

select app.chlog_attach('student_private', 'specialCategory,contractAmount,siblingDiscount,referrerId,teacherId');
select app.chlog_attach('students',        'payStatus,activeFrom,stopFrom,pauses,grade,classLetter,track,lang,studentId');
select app.chlog_attach('invoices',        'studentId,month,amount,paidAmount,status,baseAmount,discount,pctApplied,isGrant,sickAmount,sickDaysApplied,billedFrom,billedTo');
select app.chlog_attach('payments',        'studentId,invoiceId,provider,amount,status,matched');
select app.chlog_attach('refunds',         'target,targetId,studentId,amount,reason,month');
select app.chlog_attach('expenses',        'date,month,category,amount,note');
select app.chlog_attach('price_table',     'grade,track,lang,amount');
select app.chlog_attach('config',          '!refundPin,sickRate,lessonRate,latePenalty,earlyPenalty,allowedBreakMin,breakPenaltyPerHour,clickServiceId,clickMerchantId,uzumUrlTemplate,flatAmount,perYear,monthsPerYear,tenureYears,yearsCap,degree,category,languages,russian,langLevel');
select app.chlog_attach('monitoring',      'studentId,subject,period,score,status');
select app.chlog_attach('salary_payments', 'teacherId,payeeRef,month,gross,advance,deduction,subBonus,net,paid,carryIn,carryOut');
select app.chlog_attach('staff_advances',  'teacherId,payeeRef,amount,month');
select app.chlog_attach('staff_substitutions', 'day,absentRefType,absentRefId,subRefType,subRefId,lessons,ratePerLesson');
select app.chlog_attach('staff_leaves',    'refType,refId,type,startDay,endDay');
select app.chlog_attach('staff_break_marks', 'refType,refId,day,type,awayMin');
select app.chlog_attach('school_holidays', 'day,name');
select app.chlog_attach('teachers',        'teacherId,salary,baseSalary,salaryBonus,payStatus,activeFrom,stopFrom,pauses,cameraId,workStart,workEnd,workDays,flexibleHours,degree,category,languages,russian,langLevel');
select app.chlog_attach('staff',           'staffId,position,salary,payStatus,activeFrom,stopFrom,pauses,cameraId,workStart,workEnd,workDays,flexibleHours');
-- users: rol/holat + RLS tekshiradigan biriktirishlar (sinf/fan/sinf rahbarligi/farzandlar) + login (telefon/email — qiymati
--   yozilmaydi, faqat «o'zgardi»: hisobni boshqa telefonga o'tkazish = hisobni egallash xavfi).
select app.chlog_attach('users',           'role,status,verified,staffRefType,staffRefId,staffCode,assignedClasses,assignedSubjects,homeroomClasses,childIds,childId,!phone,!email');
-- Avans: balans (to'g'ridan-to'g'ri yozish RLS'da direktor/moliyaga ochiq — keyingi faktura avtomatik yopiladi) va jurnali.
select app.chlog_attach('student_credit',  'studentId,credit');
select app.chlog_attach('credit_ledger',   'studentId,delta,balanceAfter,reason,provider,month');
-- Tavsiya bonusi jurnali (300 000 so'mlik chegirmalar; faktura yaratish/qayta hisoblashda mijoz yozadi). Yozuv id = tavsiya qilingan bola.
select app.chlog_attach('referral_ledger', 'referrerId,amount,month');
-- Ota-ona <-> farzand bog'lanishi (farzandning shaxsiy ma'lumoti va to'lovlariga kirish) va farzand kodi (qiymati yozilmaydi).
select app.chlog_attach('child_claims',    'uid,studentId,status,!code');
select app.chlog_attach('student_codes',   '!code');

drop trigger if exists trg_change_log_sick on public.attendance;
create trigger trg_change_log_sick after insert or update or delete on public.attendance
  for each row execute function app.log_sick_change();

revoke all on function app.log_change() from public, anon, authenticated;
revoke all on function app.log_sick_change() from public, anon, authenticated;
revoke all on function app.chlog_attach(text, text) from public, anon, authenticated;
revoke all on function app.chlog_actor() from public, anon, authenticated;

notify pgrst, 'reload schema';
