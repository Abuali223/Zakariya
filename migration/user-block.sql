\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: user-block.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- user-block.sql — HISOBNI BLOKLASH (ishdan bo'shagan xodim, muammoli hisob) va blokdan chiqarish.
--
--   «O'chirish» faqat users qatorini o'chiradi: kirish hisobi (auth.users) qoladi va odam qayta kira oladi.
--   Bloklash esa kirishni DARHOL yopadi:
--     * users.role olinadi (NULL) — RLS rol funksiyalari (app.is_admin(), is_finance() ...) statusni TEKSHIRMAYDI,
--       shuning uchun faqat rol olinishi ochiq seans (hali muddati tugamagan JWT) bilan ham kirishni yopadi;
--       avvalgi rol "blockedRole"ga saqlanadi (blokdan chiqarilganda qaytariladi). status = 'blocked'.
--     * kirish seanslari (auth.sessions / auth.refresh_tokens) o'chiriladi — yangi token olib bo'lmaydi;
--     * ota-ona bo'lsa — FAOL farzand bog'lanishlari (child_claims) 'revoked' (blokdan chiqarilganda aynan shu
--       bloklashda bekor qilinganlari qaytariladi — vaqt belgisi "blockedAt" bilan bir xil);
--     * GoTrue taqig'i (ban) — auth-server qo'yadi (POST /authapi/block-user, admin API).
--   Amalni FAQAT auth-server (service_role) chaqiradi: kim bloklayotganini (FAOL direktor) u JWT'dan aniqlab beradi.
--   O'zini bloklash va oxirgi FAOL direktorni bloklash — rad. Bir vaqtdagi so'rovlar ketma-ket bajariladi (qatorlar
--   qulflanadi): ikki direktor bir-birini bir vaqtda bloklasa ham faol direktorsiz qolinmaydi.
--   O'zgarishlar tarixiga (change_log) amal qilgan direktor nomi bilan yoziladi.
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) users: bloklash ma'lumoti (change-log.sql'dagi users ro'yxatida ham bor).
alter table public.users add column if not exists "blockedRole" text;          -- bloklashdan OLDINGI rol
alter table public.users add column if not exists "blockedAt"   timestamptz;   -- qachon bloklangan
alter table public.users add column if not exists "blockedBy"   text;          -- kim bloklagan (users.id)

-- 2) Bu uch ustunni faqat direktor yoki server (service_role / migratsiya — JWT'siz) o'zgartiradi. Aks holda
--    foydalanuvchi o'z "blockedRole"iga yuqori rol yozib qo'yib, blokdan chiqarilganda uni olib qolishi mumkin edi.
--    Yangi qatorda (o'zini ro'yxatdan o'tkazish) — jim tozalanadi; mavjud qatorda o'zgartirish — xato (42501).
create or replace function app.guard_users_block_cols() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if app.uid() is null or app.is_admin() then return new; end if;
  if tg_op = 'INSERT' then
    new."blockedRole" := null; new."blockedAt" := null; new."blockedBy" := null;
  elsif new."blockedRole" is distinct from old."blockedRole" or new."blockedAt" is distinct from old."blockedAt"
     or new."blockedBy" is distinct from old."blockedBy" then
    raise exception 'Bloklash ma''lumotini faqat direktor o''zgartira oladi' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function app.guard_users_block_cols() from public, anon, authenticated;
drop trigger if exists trg_users_block_cols on public.users;
create trigger trg_users_block_cols before insert or update on public.users
  for each row execute function app.guard_users_block_cols();

-- 3) Bloklash. Natija: {ok, code?, already, prevRole, claims, sessions, tokens, sessionsError}.
--    code: bad_request | forbidden (chaqiruvchi faol direktor emas) | self | not_found | last_director.
--    Allaqachon bloklangan hisob — "blockedRole" o'zgarmaydi (asl rol yo'qolmasin); seanslar va FAOL bog'lanishlar
--    qayta tozalanadi (taqiqni qayta qo'yish — auth-server).
create or replace function public.user_block(p_uid text, p_actor text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  a record; t record; v_now timestamptz := now(); v_others int; v_was boolean;
  v_claims int := 0; v_rt int := 0; v_ss int := 0; v_serr text;
begin
  p_uid := btrim(coalesce(p_uid, '')); p_actor := btrim(coalesce(p_actor, ''));
  if p_uid = '' or p_actor = '' then return jsonb_build_object('ok', false, 'code', 'bad_request'); end if;
  -- Ketma-ketlik: direktorlar, chaqiruvchi va nishon qatorlari id tartibida qulflanadi (deadlock yo'q).
  perform 1 from public.users u where u.role = 'director' or u.id in (p_uid, p_actor) order by u.id for update;
  select u.role, u.status into a from public.users u where u.id = p_actor;
  if not found or a.role is distinct from 'director' or coalesce(nullif(a.status, ''), 'active') <> 'active' then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;
  if p_uid = p_actor then return jsonb_build_object('ok', false, 'code', 'self'); end if;
  select u.role, u.status, u."blockedRole" into t from public.users u where u.id = p_uid;
  if not found then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  v_was := coalesce(t.status, '') = 'blocked';
  perform set_config('app.uid', p_actor, true);   -- change_log: kim blokladi (shu tranzaksiya ichida)
  if not v_was then
    if t.role = 'director' then
      select count(*) into v_others from public.users u
       where u.role = 'director' and coalesce(nullif(u.status, ''), 'active') = 'active' and u.id <> p_uid;
      if v_others < 1 then return jsonb_build_object('ok', false, 'code', 'last_director'); end if;
    end if;
    update public.users
       set "blockedRole" = nullif(role, ''), role = null, status = 'blocked',
           "blockedAt" = v_now, "blockedBy" = p_actor, "updatedAt" = v_now
     where id = p_uid;
  end if;
  update public.child_claims set status = 'revoked', "updatedAt" = v_now
   where uid = p_uid and coalesce(nullif(status, ''), 'active') = 'active';
  get diagnostics v_claims = row_count;
  -- Kirish seanslari: refresh token'lar va seanslar o'chiriladi (jadvallar bo'lmasa — o'tkaziladi). Xato bloklashni
  --   to'xtatmaydi (rol baribir olingan) — auth-server javobida ko'rsatiladi.
  begin
    if to_regclass('auth.refresh_tokens') is not null then
      execute 'delete from auth.refresh_tokens where user_id::text = $1' using p_uid;
      get diagnostics v_rt = row_count;
    end if;
    if to_regclass('auth.sessions') is not null then
      execute 'delete from auth.sessions where user_id::text = $1' using p_uid;
      get diagnostics v_ss = row_count;
    end if;
  exception when others then v_serr := sqlstate;
  end;
  return jsonb_build_object('ok', true, 'already', v_was,
    'prevRole', case when v_was then t."blockedRole" else nullif(t.role, '') end,
    'claims', v_claims, 'sessions', v_ss, 'tokens', v_rt, 'sessionsError', v_serr);
end $$;

-- 4) Blokdan chiqarish. Rol: bloklangan paytda direktor qo'lda rol bergan bo'lsa — o'sha, aks holda "blockedRole".
--    Holat: rol tayinlanmagan tasdiqlanmagan xodim ('staff', verified=false) — yana tasdiq kutadi (pending), qolganlar — faol.
--    Shu bloklashda bekor qilingan farzand bog'lanishlari qaytariladi (oldin boshqa sabab bilan bekor qilinganlari — yo'q).
--    Bloklanmagan hisob — hech narsa o'zgarmaydi (already=true; taqiqni olish — auth-server).
create or replace function public.user_unblock(p_uid text, p_actor text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare a record; t record; v_now timestamptz := now(); v_role text; v_status text; v_claims int := 0;
begin
  p_uid := btrim(coalesce(p_uid, '')); p_actor := btrim(coalesce(p_actor, ''));
  if p_uid = '' or p_actor = '' then return jsonb_build_object('ok', false, 'code', 'bad_request'); end if;
  perform 1 from public.users u where u.role = 'director' or u.id in (p_uid, p_actor) order by u.id for update;
  select u.role, u.status into a from public.users u where u.id = p_actor;
  if not found or a.role is distinct from 'director' or coalesce(nullif(a.status, ''), 'active') <> 'active' then
    return jsonb_build_object('ok', false, 'code', 'forbidden');
  end if;
  select u.role, u.status, u.verified, u."blockedRole", u."blockedAt" into t from public.users u where u.id = p_uid;
  if not found then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  if coalesce(t.status, '') <> 'blocked' then
    return jsonb_build_object('ok', true, 'already', true, 'role', t.role, 'status', t.status, 'claims', 0);
  end if;
  v_role := coalesce(nullif(t.role, ''), nullif(t."blockedRole", ''));
  v_status := case when coalesce(v_role, 'staff') = 'staff' and not coalesce(t.verified, false) then 'pending' else 'active' end;
  perform set_config('app.uid', p_actor, true);   -- change_log: kim blokdan chiqardi
  update public.users
     set role = v_role, status = v_status, "blockedRole" = null, "blockedAt" = null, "blockedBy" = null, "updatedAt" = v_now
   where id = p_uid;
  if t."blockedAt" is not null then
    update public.child_claims set status = 'active', "updatedAt" = v_now
     where uid = p_uid and status = 'revoked' and "updatedAt" = t."blockedAt";
    get diagnostics v_claims = row_count;
  end if;
  return jsonb_build_object('ok', true, 'already', false, 'role', v_role, 'status', v_status, 'claims', v_claims);
end $$;

-- Faqat auth-server (service_role). Supabase standart huquqlari public sxemadagi yangi funksiyani anon/authenticated'ga
--   ham ochadi — shuning uchun aniq olib tashlanadi.
revoke all on function public.user_block(text, text) from public, anon, authenticated;
revoke all on function public.user_unblock(text, text) from public, anon, authenticated;
grant execute on function public.user_block(text, text) to service_role;
grant execute on function public.user_unblock(text, text) to service_role;

notify pgrst, 'reload schema';
