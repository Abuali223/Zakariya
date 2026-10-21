\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: attendance-sync.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- attendance-sync.sql — o'quvchi davomati/baholarining HOSILA ma'lumotlarini bazada sinxron ushlash.
--
-- 1) SINF O'ZGARSA — joriy davr yozuvlarining "classKey"i yangi sinfga o'tadi.
--    attendance/grades/monitoring satrlari o'quvchining yozilgan paytidagi sinf kalitini saqlaydi va
--    RLS (att_upd / grades_upd / mon_upd) shu MAVJUD satrdagi kalitni tekshiradi. O'quvchi oy (yil)
--    o'rtasida boshqa sinfga o'tkazilsa (forma, import, «Sinflar»da qayta nomlash), yangi sinf
--    rahbari/o'qituvchisining upserti `new row violates row-level security policy (USING expression)`
--    bilan rad etilardi -> butun sinf davomati saqlanmay qolardi (kurator faqat «Xatolik: 42501»ni
--    ko'rardi), «Bemor» kunlari kasallik chegirmasiga yetib bormasdi.
--    Endi students'da sinf maydonlari (grade/classLetter/track/lang) o'zgarganda o'sha o'quvchining
--    JORIY va keyingi davr satrlari yangi kalitga o'tkaziladi:
--      attendance — month  >= joriy oy (Toshkent);
--      monitoring — period >= joriy oy;
--      grades     — year    = joriy o'quv yili (sentabr–avgust, 'YYYY-YYYY').
--    O'tgan davrlar (tarix) o'zgartirilmaydi. Kalit formulasi admin.html classKeyOf() bilan AYNAN bir xil.
--
-- 2) «DAVOMAT %» (students.attendance) — har davomat yozuvi o'zgarganda AVTOMATIK qayta hisoblanadi.
--    Ilgari faqat DIREKTOR saqlaganda (frontend) yangilanardi; davomatni kunda kurator/sinf rahbari
--    yuritadi va students'ga yozish huquqi yo'q -> «Davomat %» eskirib qolar, ota-ona kabinetida bir
--    sahifada ikki xil raqam chiqardi, xavf ostidagilar ro'yxati noto'g'ri edi.
--    Formula admin.html recomputeAttendancePct() bilan bir xil: (keldi + kech) / (jami − bemor − sababli).
--    Bir martalik tenglash (backfill) ham shu yerda: hosila maydon — har deployda qayta hisoblash xavfsiz
--    (faqat farq qilsa yoziladi; davomat yozuvi yo'q o'quvchiga TEGILMAYDI).
--
-- Ikkala trigger funksiyasi SECURITY DEFINER (kurator students'ga yoza olmaydi; RLS chetlab o'tiladi —
--   faqat hosila ustunlar yangilanadi), search_path qat'iy. Idempotent (run-all.sql zanjirida).
-- =====================================================================

-- O'quvchining sinf kaliti (admin.html classKeyOf: `${lang||'uz'}-${Number(grade)||0}-${classLetter||track||'-'}`).
create or replace function app.student_class_key(p_lang text, p_grade int, p_letter text, p_track text)
returns text language sql immutable set search_path = pg_catalog as $$
  select coalesce(nullif(p_lang, ''), 'uz') || '-' || coalesce(p_grade, 0)::text || '-'
      || coalesce(nullif(p_letter, ''), nullif(p_track, ''), '-')
$$;

-- ---- 1) Sinf o'zgarsa: joriy davr satrlarini yangi kalitga o'tkazish ----
create or replace function app.sync_student_class_rows()
returns trigger language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  v_new  text := app.student_class_key(new.lang, new.grade, new."classLetter", new.track);
  v_old  text := app.student_class_key(old.lang, old.grade, old."classLetter", old.track);
  v_now  timestamp := now() at time zone 'Asia/Tashkent';
  v_mon  text := to_char(v_now, 'YYYY-MM');
  v_y    int  := extract(year from v_now)::int;
  v_ay   text := case when extract(month from v_now) >= 9 then v_y::text || '-' || (v_y + 1)::text
                      else (v_y - 1)::text || '-' || v_y::text end;
  v_sids text[];
begin
  if v_new = v_old then return new; end if;
  -- Davomat/baho satrlari o'quvchining studentId'si (bo'lmasa doc id) bilan kalitlangan (admin.html: s.studentId||s._id).
  --   Doc id faqat studentId bo'sh bo'lsa yoki boshqa o'quvchining studentId'si bilan TO'QNASHMASA qo'shiladi
  --   (aks holda boshqa o'quvchining davomat/baho qatorlari shu o'quvchining yangi sinfiga ko'chib ketardi).
  v_sids := array[coalesce(nullif(new."studentId", ''), new.id)];
  if coalesce(new."studentId", '') <> '' and new.id <> new."studentId"
     and not exists (select 1 from public.students s2 where s2."studentId" = new.id and s2.id <> new.id) then
    v_sids := v_sids || new.id;
  end if;
  if coalesce(array_length(v_sids, 1), 0) = 0 then return new; end if;
  update public.attendance set "classKey" = v_new
   where "studentId" = any(v_sids) and month >= v_mon and "classKey" is distinct from v_new;
  update public.monitoring set "classKey" = v_new
   where "studentId" = any(v_sids) and period >= v_mon and "classKey" is distinct from v_new;
  update public.grades set "classKey" = v_new
   where "studentId" = any(v_sids) and year = v_ay and "classKey" is distinct from v_new;
  -- Tavsifnoma / fan izohlari / oylik xulosa ham sinf kaliti bilan (RLS yangi sinf rahbariga shu kalit bo'yicha ruxsat beradi).
  update public.characteristics set "classKey" = v_new
   where "studentId" = any(v_sids) and year = v_ay and "classKey" is distinct from v_new;
  update public.subject_notes set "classKey" = v_new
   where "studentId" = any(v_sids) and year = v_ay and "classKey" is distinct from v_new;
  update public.student_summaries set "classKey" = v_new
   where "studentId" = any(v_sids) and month >= v_mon and "classKey" is distinct from v_new;
  return new;
end $$;
revoke all on function app.sync_student_class_rows() from public, anon, authenticated;
grant execute on function app.sync_student_class_rows() to service_role;   -- supabase-grants.sql bilan bir xil (qayta deployda farq chiqmasin)
drop trigger if exists trg_student_class_rows on public.students;
create trigger trg_student_class_rows after update of grade, "classLetter", track, lang on public.students
  for each row execute function app.sync_student_class_rows();

-- ---- 2) «Davomat %» — davomat yozuvi o'zgarganda avtomatik ----
-- Bitta o'quvchi (studentId yoki doc id) bo'yicha foiz. Hisoblanadigan kun bo'lmasa — NULL (tegilmaydi).
create or replace function app.student_attendance_pct(p_sid text)
returns int language sql stable security definer set search_path = public, app, pg_temp as $$
  select case when x.total > 0 then round(100.0 * x.pres / x.total)::int end
    from (select count(*) filter (where coalesce(e.v, '') in ('present', 'late')) as pres,
                 count(*) filter (where coalesce(e.v, '') not in ('sick', 'excused')) as total
            from public.attendance a
            cross join lateral jsonb_each_text(case when jsonb_typeof(a.days) = 'object' then a.days else '{}'::jsonb end) as e(k, v)
           where a."studentId" = p_sid) x
$$;
revoke all on function app.student_attendance_pct(text) from public, anon;
grant execute on function app.student_attendance_pct(text) to authenticated, service_role;

create or replace function app.sync_student_attendance_pct()
returns trigger language plpgsql security definer set search_path = public, app, pg_temp as $$
declare v_pct int;
begin
  if coalesce(new."studentId", '') = '' then return new; end if;
  v_pct := app.student_attendance_pct(new."studentId");
  if v_pct is null then return new; end if;
  -- students'da davomat kaliti: studentId; studentId bo'sh (eski) yozuvlarda — doc id.
  update public.students s set attendance = v_pct
   where (s."studentId" = new."studentId" or (coalesce(s."studentId", '') = '' and s.id = new."studentId"))
     and s.attendance is distinct from v_pct;
  return new;
end $$;
revoke all on function app.sync_student_attendance_pct() from public, anon, authenticated;
grant execute on function app.sync_student_attendance_pct() to service_role;
drop trigger if exists trg_attendance_pct on public.attendance;
create trigger trg_attendance_pct after insert or update of days on public.attendance
  for each row execute function app.sync_student_attendance_pct();

-- Bir martalik (va har deployda xavfsiz) tenglash: davomat yozuvi bor o'quvchilarning «Davomat %»i
--   haqiqiy davomatdan hisoblanadi (faqat farq qilsa yoziladi).
--   MATERIALIZED: aks holda planner `x.pct is not null` ni skanga tushirib, funksiyani har davomat QATORI uchun
--   chaqirardi (3000 o'quvchi / 35k qator: ~4.9 s qulf ostida); endi har o'quvchi uchun bir marta.
with x as materialized (
  select d.sid, app.student_attendance_pct(d.sid) as pct
    from (select distinct a."studentId" as sid from public.attendance a where coalesce(a."studentId", '') <> '') d)
update public.students s set attendance = x.pct
  from x
 where x.pct is not null
   and (s."studentId" = x.sid or (coalesce(s."studentId", '') = '' and s.id = x.sid))
   and s.attendance is distinct from x.pct;

notify pgrst, 'reload schema';
