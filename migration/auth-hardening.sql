\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: auth-hardening.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
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

-- 2d) OFIS ROLLARI (moliya/HR/qabul/marketing/ma'muriyat rahbari) ham FAOL status talab qiladi.
--     Audit (H1): auth-hardening is_staff/is_cashier'ga status tekshiruvini qo'shgan, LEKIN bu
--     predikatlar (roles-rbac.sql / reception-access.sql'da ta'riflangan) gated EMAS edi. Natijada
--     status='blocked' qilingan finance/HR/reception hisob, GoTrue tokeni tirik bo'lgani uchun,
--     RLS orqali OYLIK / PII / to'lov (apply_payment) ni O'QIY/YOZA olardi. Bu yerda QAYTA ta'riflaymiz
--     (auth-hardening roles-rbac/reception-access'DAN KEYIN, secdef-searchpath'DAN OLDIN ishga tushadi,
--     shuning uchun bu ta'riflar g'olib bo'ladi; search_path keyin secdef-searchpath'da qayta mahkamlanadi).
--     Rol ro'yxatlari roles-rbac.sql bilan BIR XIL — faqat status sharti qo'shildi (a'zolik o'zgarmadi).
--     is_admin()/is_zavuch() ATAYLAB gated EMAS (superuser/rahbarni tasodifan qulflamaslik uchun).
create or replace function app.is_admin_head() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('director','admin','admin_head')
    and coalesce(nullif(status,''),'active') = 'active')
$$;
create or replace function app.is_hr() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('director','hr')
    and coalesce(nullif(status,''),'active') = 'active')
$$;
create or replace function app.is_finance() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('director','finance_mgr','treasurer')
    and coalesce(nullif(status,''),'active') = 'active')
$$;
create or replace function app.is_marketing() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role in ('director','marketing_mgr')
    and coalesce(nullif(status,''),'active') = 'active')
$$;
create or replace function app.is_reception() returns boolean language sql stable security definer as $$
  select exists(select 1 from public.users where id = app.uid() and role = 'reception'
    and coalesce(nullif(status,''),'active') = 'active')
$$;

notify pgrst, 'reload schema';
