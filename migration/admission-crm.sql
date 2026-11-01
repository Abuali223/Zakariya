\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: admission-crm.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- admission-crm.sql — QABUL BO'LIMI (raqib bilan taqqoslash, 2026-10-31):
--   * murojaatlar (enrollments) voronkasi: manba, sinov darsi, rad sababi (majburiy), qabul qilingach o'quvchi ID'si,
--     qayta aloqa sanasi; qabulxona murojaatni yangilaydi va qo'lda qo'shadi (o'chira olmaydi);
--   * enrollment_events — murojaat tarixi (qo'ng'iroq, izoh, bosqich, sinov, qabul) — faqat qo'shiladi;
--   * class_seats — sinf sig'imi; class_seat_stats() — sinf bo'yicha band/bo'sh o'rin (ismsiz sonlar);
--   * o'quvchi ketish sababi (exitReason/exitNote/exitAt/exitBy);
--   * o'chirilgan o'quvchi arxivi (deleted_records) va restore_deleted_student() — faqat direktor.
--   Ommaviy sayt formasi (anon) o'zgarmaydi: u faqat name/phone/grade/direction/lang/ts yuboradi — yangi xodim
--   ustunlariga anon yoza olmaydi (security-2d.sql himoyasi kengaytirildi).
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) Murojaatlar: yangi ustunlar
alter table public.enrollments add column if not exists "childName"    text;
alter table public.enrollments add column if not exists "parentName"   text;
alter table public.enrollments add column if not exists source         text;
alter table public.enrollments add column if not exists "stageAt"      timestamptz;
alter table public.enrollments add column if not exists "trialAt"      timestamptz;
alter table public.enrollments add column if not exists "trialTeacher" text;
alter table public.enrollments add column if not exists "trialResult"  text;
alter table public.enrollments add column if not exists "rejectReason" text;
alter table public.enrollments add column if not exists "rejectNote"   text;
alter table public.enrollments add column if not exists "studentId"    text;
alter table public.enrollments add column if not exists "assignedTo"   text;
alter table public.enrollments add column if not exists "nextActionAt" timestamptz;
alter table public.enrollments add column if not exists "createdBy"    text;
create index if not exists enrollments_status_idx on public.enrollments(status);

-- 2) Ruxsatlar. Ko'rish (enr_sel — reception-access.sql) o'zgarmaydi: director, marketing, admin_head, reception.
--    Yangilash: + reception (qabulxona murojaat bilan ishlaydi). O'chirish — faqat director (enr_del o'zgarmaydi).
--    Qo'shish: xodim (director, admin_head, reception, marketing) — har qanday ustun; anon (sayt formasi) — faqat
--    boshlang'ich holat, izohsiz va xodim ustunlarisiz (manba — faqat 'sayt').
drop policy if exists enr_ins on public.enrollments;
create policy enr_ins on public.enrollments for insert with check (
  app.is_admin() or app.is_admin_head() or app.is_reception() or app.is_marketing()
  or ((status is null or status = 'yangi') and note is null
      and "studentId" is null and "rejectReason" is null and "rejectNote" is null and "assignedTo" is null
      and "trialAt" is null and "trialTeacher" is null and "trialResult" is null and "nextActionAt" is null
      and "createdBy" is null and coalesce(source, 'sayt') = 'sayt')
);
drop policy if exists enr_upd on public.enrollments;
create policy enr_upd on public.enrollments for update
  using (app.is_admin() or app.is_marketing() or app.is_admin_head() or app.is_reception())
  with check (app.is_admin() or app.is_marketing() or app.is_admin_head() or app.is_reception());

-- 3) Trigger: manba standarti, bosqich vaqti, xodim yaratganda kim, «rad» — sabab majburiy.
create or replace function app.enrollment_guard() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    new.source := coalesce(nullif(btrim(coalesce(new.source, '')), ''), 'sayt');
    new."stageAt" := now();
    if app.uid() is not null and (app.is_admin() or app.is_admin_head() or app.is_reception() or app.is_marketing()) then
      new."createdBy" := coalesce(nullif(new."createdBy", ''), app.uid());
    end if;
  elsif new.status is distinct from old.status then
    new."stageAt" := now();
  end if;
  if coalesce(new.status, '') = 'rad' and (tg_op = 'INSERT' or coalesce(old.status, '') <> 'rad')
     and coalesce(btrim(new."rejectReason"), '') = '' then
    raise exception 'Rad etish sababini tanlang' using errcode = '23514';
  end if;
  return new;
end $$;
revoke all on function app.enrollment_guard() from public, anon, authenticated;
drop trigger if exists trg_enrollment_guard on public.enrollments;
create trigger trg_enrollment_guard before insert or update on public.enrollments
  for each row execute function app.enrollment_guard();

-- 4) Murojaat tarixi (faqat qo'shiladi)
create table if not exists public.enrollment_events (
  id             text primary key default gen_random_uuid()::text,
  "enrollmentId" text not null,
  type           text not null,
  payload        jsonb not null default '{}'::jsonb,
  at             timestamptz not null default now(),
  by             text
);
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.enrollment_events'::regclass and conname = 'enrollment_events_type_chk') then
    alter table public.enrollment_events add constraint enrollment_events_type_chk check (type in ('call', 'note', 'stage', 'trial', 'convert'));
  end if;
end $$;
create index if not exists enrollment_events_enr_idx on public.enrollment_events("enrollmentId", at);
alter table public.enrollment_events enable row level security;
revoke all on public.enrollment_events from anon;
grant select, insert, delete on public.enrollment_events to authenticated;
revoke update on public.enrollment_events from authenticated;
grant all on public.enrollment_events to service_role;
create or replace function app.enrollment_event_stamp() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  new.by := app.uid(); new.at := now();     -- kim va qachon — mijoz qiymati e'tiborsiz
  return new;
end $$;
revoke all on function app.enrollment_event_stamp() from public, anon, authenticated;
drop trigger if exists trg_enrollment_event_stamp on public.enrollment_events;
create trigger trg_enrollment_event_stamp before insert on public.enrollment_events
  for each row execute function app.enrollment_event_stamp();
drop policy if exists ee_sel on public.enrollment_events;
create policy ee_sel on public.enrollment_events for select
  using (app.is_admin() or app.is_admin_head() or app.is_reception() or app.is_marketing());
drop policy if exists ee_ins on public.enrollment_events;
create policy ee_ins on public.enrollment_events for insert
  with check ((app.is_admin() or app.is_admin_head() or app.is_reception() or app.is_marketing()) and by = app.uid());
drop policy if exists ee_del on public.enrollment_events;
create policy ee_del on public.enrollment_events for delete using (app.is_admin());

-- 5) Sinf sig'imi (id = sinf kaliti: lang-grade-harf, admin.html classKeyOf bilan bir xil)
create table if not exists public.class_seats (
  id          text primary key,
  capacity    int not null default 0,
  "updatedAt" timestamptz default now(),
  "updatedBy" text
);
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.class_seats'::regclass and conname = 'class_seats_capacity_chk') then
    alter table public.class_seats add constraint class_seats_capacity_chk check (capacity between 0 and 500);
  end if;
end $$;
alter table public.class_seats enable row level security;
revoke all on public.class_seats from anon;
grant select, insert, update, delete on public.class_seats to authenticated;
grant all on public.class_seats to service_role;
create or replace function app.class_seats_stamp() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin new."updatedAt" := now(); new."updatedBy" := coalesce(app.uid(), new."updatedBy"); return new; end $$;
revoke all on function app.class_seats_stamp() from public, anon, authenticated;
drop trigger if exists trg_class_seats_stamp on public.class_seats;
create trigger trg_class_seats_stamp before insert or update on public.class_seats
  for each row execute function app.class_seats_stamp();
drop policy if exists cs_sel on public.class_seats;
create policy cs_sel on public.class_seats for select
  using (app.is_admin() or app.is_zavuch() or app.is_admin_head() or app.is_reception() or app.is_marketing());
drop policy if exists cs_ins on public.class_seats;
create policy cs_ins on public.class_seats for insert with check (app.is_admin() or app.is_admin_head());
drop policy if exists cs_upd on public.class_seats;
create policy cs_upd on public.class_seats for update using (app.is_admin() or app.is_admin_head()) with check (app.is_admin() or app.is_admin_head());
drop policy if exists cs_del on public.class_seats;
create policy cs_del on public.class_seats for delete using (app.is_admin() or app.is_admin_head());

-- Sinf bo'yicha band o'rinlar: faol + sinovdagi o'quvchilar (chiqqan/muzlatilganlarsiz) — FAQAT sonlar (ism yo'q),
--   qabul bilan ishlaydiganlar uchun (marketing va admin_head o'quvchi ro'yxatini ko'rmasa ham bo'sh o'rinni biladi).
create or replace function public.class_seat_stats() returns table("classKey" text, active int, capacity int)
language plpgsql stable security definer set search_path = public, app, pg_temp as $$
begin
  if not (app.is_admin() or app.is_zavuch() or app.is_admin_head() or app.is_reception() or app.is_marketing()) then
    raise exception 'ruxsat yo''q' using errcode = '42501';
  end if;
  return query
  with k as (
    select coalesce(nullif(s.lang, ''), 'uz') || '-' || coalesce(s.grade, 0)::text || '-'
           || coalesce(nullif(s."classLetter", ''), nullif(s.track, ''), '-') as ck
      from public.students s
     where coalesce(s."payStatus", '') not in ('chiqdi', 'muzlatilgan')
  ), c as (select ck, count(*)::int n from k group by ck)
  select coalesce(c.ck, cs.id), coalesce(c.n, 0), cs.capacity
    from c full join public.class_seats cs on cs.id = c.ck
   order by 1;
end $$;
revoke all on function public.class_seat_stats() from public, anon;
grant execute on function public.class_seat_stats() to authenticated, service_role;

-- 6) O'quvchi ketish sababi
alter table public.students add column if not exists "exitReason" text;
alter table public.students add column if not exists "exitNote"   text;
alter table public.students add column if not exists "exitAt"     text;
alter table public.students add column if not exists "exitBy"     text;

-- 7) O'chirilgan o'quvchi arxivi. students / student_private qatori o'chirilganda TO'LIQ nusxasi saqlanadi (shaxsiy
--    ma'lumot ham — shuning uchun faqat direktor o'qiydi; yozish faqat trigger va restore RPC orqali).
create table if not exists public.deleted_records (
  id           text primary key default gen_random_uuid()::text,
  tbl          text not null,
  "rowId"      text not null,
  row          jsonb not null,
  "deletedAt"  timestamptz not null default now(),
  "deletedBy"  text,
  "restoredAt" timestamptz,
  "restoredBy" text
);
create index if not exists deleted_records_row_idx on public.deleted_records(tbl, "rowId");
alter table public.deleted_records enable row level security;
revoke all on public.deleted_records from anon, authenticated;
grant select on public.deleted_records to authenticated;
grant all on public.deleted_records to service_role;
drop policy if exists dr_sel on public.deleted_records;
create policy dr_sel on public.deleted_records for select using (app.is_admin());
create or replace function app.archive_deleted_row() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  insert into public.deleted_records(tbl, "rowId", row, "deletedBy") values (tg_table_name, old.id, to_jsonb(old), app.uid());
  return old;
end $$;
revoke all on function app.archive_deleted_row() from public, anon, authenticated;
drop trigger if exists trg_archive_deleted on public.students;
create trigger trg_archive_deleted after delete on public.students for each row execute function app.archive_deleted_row();
drop trigger if exists trg_archive_deleted on public.student_private;
create trigger trg_archive_deleted after delete on public.student_private for each row execute function app.archive_deleted_row();
-- Ota-ona kodi ham (panel o'quvchi bilan birga student_codes'ni ham o'chiradi): tiklashda o'sha kod qaytadi.
drop trigger if exists trg_archive_deleted on public.student_codes;
create trigger trg_archive_deleted after delete on public.student_codes for each row execute function app.archive_deleted_row();

-- Tiklash: faqat direktor. O'quvchi qatori (va o'sha o'chirishdagi student_private) qaytadi; ota-ona kodi (student_codes)
--   o'zgarmaydi — bog'langan ota-onalar kirishni yo'qotmaydi (AFTER INSERT trigger yangi kod yozsa ham eskisi qaytariladi).
--   Fakturalar, to'lovlar, davomat o'quvchi o'chirilganda o'chmaydi — ID bir xil bo'lgani uchun qayta bog'lanadi.
create or replace function public.restore_deleted_student(p_id text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare a record; p record; v_code text; v_sid text; v_priv boolean := false;
begin
  if not app.is_admin() then raise exception 'Faqat direktor tiklay oladi' using errcode = '42501'; end if;
  select * into a from public.deleted_records where id = p_id and tbl = 'students' for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'Arxiv yozuvi topilmadi'); end if;
  if a."restoredAt" is not null then return jsonb_build_object('ok', false, 'error', 'Bu yozuv allaqachon tiklangan'); end if;
  v_sid := nullif(btrim(coalesce(a.row->>'studentId', '')), '');
  if exists (select 1 from public.students s where s.id = a."rowId" or (v_sid is not null and s."studentId" = v_sid)) then
    return jsonb_build_object('ok', false, 'error', 'Shu ID bilan o''quvchi bazada bor — tiklab bo''lmaydi');
  end if;
  -- Ota-ona kodi: hali bazada bo'lsa — o'sha, o'chirilgan bo'lsa — arxivdagi eng oxirgisi.
  select sc.code into v_code from public.student_codes sc where sc.id = a."rowId";
  if v_code is null then
    select d.row->>'code' into v_code from public.deleted_records d
     where d.tbl = 'student_codes' and d."rowId" = a."rowId" and d."restoredAt" is null order by d."deletedAt" desc limit 1;
  end if;
  insert into public.students select * from jsonb_populate_record(null::public.students, a.row);
  if nullif(v_code, '') is not null then
    insert into public.student_codes(id, code, "updatedAt") values (a."rowId", v_code, now())
      on conflict (id) do update set code = excluded.code, "updatedAt" = now();
    update public.deleted_records set "restoredAt" = now(), "restoredBy" = app.uid()
     where tbl = 'student_codes' and "rowId" = a."rowId" and "restoredAt" is null;
  end if;
  select * into p from public.deleted_records
   where tbl = 'student_private' and "rowId" = a."rowId" and "restoredAt" is null
   order by "deletedAt" desc limit 1 for update;
  if found and not exists (select 1 from public.student_private sp where sp.id = a."rowId") then
    insert into public.student_private select * from jsonb_populate_record(null::public.student_private, p.row);
    update public.deleted_records set "restoredAt" = now(), "restoredBy" = app.uid() where id = p.id;
    v_priv := true;
  end if;
  update public.deleted_records set "restoredAt" = now(), "restoredBy" = app.uid() where id = a.id;
  return jsonb_build_object('ok', true, 'id', a."rowId", 'private', v_priv);
end $$;
revoke all on function public.restore_deleted_student(text) from public, anon;
grant execute on function public.restore_deleted_student(text) to authenticated, service_role;

-- 8) O'zgarishlar tarixi
select app.chlog_attach('enrollments', 'status,rejectReason,studentId,assignedTo,trialAt,source');
select app.chlog_attach('class_seats', 'capacity');
select app.chlog_attach('students',    'payStatus,activeFrom,stopFrom,pauses,grade,classLetter,track,lang,studentId,exitReason,exitAt');

notify pgrst, 'reload schema';
