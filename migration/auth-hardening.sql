-- =====================================================================
-- AUTH QATTIQLASHTIRISH (xavfsizlik ko'rigidan keyin).
--   1) otp_consume — ATOMIK OTP tekshiruvi (FOR UPDATE): urinish sanog'ini poyga (race)
--      orqali chetlab o'tib 6-xonali kodni brute-force qilishni yopadi.
--   2) is_staff() / is_teacher_for_class() — endi FAOL (status active) foydalanuvchini talab
--      qiladi: tasdiqlanmagan (pending) yoki bloklangan o'qituvchi, seansi bo'lsa ham, xodim/
--      o'quvchi ro'yxati va sinf ma'lumotini O'QIY OLMAYDI (RLS darajasida — frontend emas).
--      status bo'sh/NULL -> 'active' (mavjud foydalanuvchilar buzilmaydi).
-- Idempotent. run-all.sql + deploy.sh'da (secdef-searchpath'dan OLDIN).
-- =====================================================================

-- 1) ATOMIK OTP tekshiruvi. service_role chaqiradi; hash serverда hisoblanadi (secret serverда).
--    Eng oxirgi ishlatilmagan kodni FOR UPDATE bilan qulflaydi -> parallel so'rovlar
--    ketma-ket bajariladi -> attempts cap haqiqiy ishlaydi.
create or replace function public.otp_consume(p_phone text, p_purpose text, p_hash text, p_max int)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; v_att int;
begin
  select * into r from public.otp_codes
    where phone = p_phone and purpose = p_purpose and consumed = false
    order by "createdAt" desc limit 1
    for update;
  if not found then return jsonb_build_object('ok', false, 'nocode', true); end if;
  if r."expiresAt" < now() then return jsonb_build_object('ok', false, 'expired', true); end if;
  if coalesce(r.attempts,0) >= p_max then return jsonb_build_object('ok', false, 'locked', true); end if;
  if r."codeHash" = p_hash then
    update public.otp_codes set consumed = true where id = r.id;
    return jsonb_build_object('ok', true, 'uid', r.uid);
  end if;
  update public.otp_codes set attempts = coalesce(attempts,0) + 1 where id = r.id returning attempts into v_att;
  return jsonb_build_object('ok', false, 'remaining', greatest(0, p_max - v_att), 'locked', v_att >= p_max);
end $$;
revoke all on function public.otp_consume(text, text, text, int) from public, anon, authenticated;
grant execute on function public.otp_consume(text, text, text, int) to service_role;

-- 2a) is_staff() — FAOL status talab qiladi (pending/blocked -> xodim emas).
create or replace function app.is_staff() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid()
    and role in ('admin','director','zavuch','kurator','teacher',
                 'hr','admin_head','finance_mgr','treasurer','marketing_mgr','reception')
    and coalesce(nullif(status,''),'active') = 'active')
$$;

-- 2b) is_teacher_for_class() — o'qituvchi FAOL bo'lishi shart (mudofaa: tasdiqlanmagan o'qituvchi
--     biriktirilgan sinf baholariga ham kira olmasin).
create or replace function app.is_teacher_for_class(ck text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role='teacher'
    and coalesce(nullif(status,''),'active') = 'active'
    and coalesce("assignedClasses",'[]'::jsonb) ? ck)
$$;

-- 2c) Qolgan sinf-xodim predikatlari ham FAOL status talab qiladi — BLOKLANGAN (yoki pending)
--     kurator/sinf rahbari/kassir, seansi tirik bo'lsa ham, davomat/tavsif/baho ko'ra olmasin.
--     (can_write_general / is_class_staff — shu ikkalasidan tuzilgani uchun avtomatik gated.)
--     is_admin()/is_zavuch() ATAYLAB gated EMAS (superuser/rahbarni tasodifan qulflab qo'ymaslik uchun).
create or replace function app.is_homeroom_for(ck text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('admin','zavuch','kurator','teacher')
    and coalesce(nullif(status,''),'active') = 'active'
    and coalesce("homeroomClasses",'[]'::jsonb) ? ck)
$$;
create or replace function app.is_kurator_for(ck text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role='kurator'
    and coalesce(nullif(status,''),'active') = 'active'
    and coalesce("assignedClasses",'[]'::jsonb) ? ck)
$$;
create or replace function app.teacher_has_subject(subj text) returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid()
    and coalesce(nullif(status,''),'active') = 'active'
    and coalesce("assignedSubjects",'[]'::jsonb) ? subj)
$$;
create or replace function app.is_cashier() returns boolean language sql stable security definer as $$
  select coalesce((select role = 'kassir' and coalesce(nullif(status,''),'active') = 'active'
                   from public.users where id = app.uid()), false)
$$;

notify pgrst, 'reload schema';
