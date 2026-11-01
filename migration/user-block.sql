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
--   Bloklangan hisob (muddati tugamagan JWT bilan ham) farzand ma'lumotini ko'rmaydi va farzand biriktira olmaydi —
--   app.owns_child / owns_student_doc / has_active_child va claim_child status='blocked'ni tekshiradi
--   (parent-link-canon.sql, bus-access.sql).
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- 1) users: bloklash ma'lumoti (change-log.sql'dagi users ro'yxatida ham bor).
alter table public.users add column if not exists "blockedRole" text;          -- bloklashdan OLDINGI rol
alter table public.users add column if not exists "blockedAt"   timestamptz;   -- qachon bloklangan
alter table public.users add column if not exists "blockedBy"   text;          -- kim bloklagan (users.id)

-- 2) Himoya trigger'i — mijoz JWT'si bilan (ekran / PostgREST) qilingan o'zgartirishlar:
--    * "blockedRole" / "blockedAt" / "blockedBy" — faqat public.user_block / user_unblock (auth-server) o'zgartiradi. Aks
--      holda foydalanuvchi o'z "blockedRole"iga yuqori rol yozib, blokdan chiqarilganda uni olib qolardi; direktor ham bu
--      ustunlarni qo'lda o'zgartirmaydi (bloklash tarixi va blokdan chiqarish buzilmasin).
--    * Bloklangan hisobning roli va holati faqat «Blokdan chiqarish» (user_unblock) bilan o'zgaradi: eskirgan tahrir oynasi
--      (ro'yxat bloklashdan oldin ochilgan yoki boshqa direktor/oyna shu orada bloklagan) «Saqlash» bilan rolni qaytarib
--      qo'ymasin — aks holda GoTrue taqig'i qolib, muddati tugamagan JWT bilan rol huquqlari qaytardi.
--    * status = 'blocked' faqat user_block bilan (qo'lda yozilsa rol qolib, kirish taqiqlanmay qolardi).
--    Server (service_role) va migratsiya (JWT'siz) — cheklanmaydi. Ikki RPC ichida — tranzaksiya bayrog'i
--    iqror.user_block = '1' (faqat shu funksiyalar qo'yadi; mijoz SET qila olmaydi). Yangi qatorda (o'zini ro'yxatdan
--    o'tkazish, upsert) — direktor bo'lmasa blocked* jim tozalanadi (upsert'da BEFORE INSERT taklif qilingan qatorga
--    ham ishlaydi, shuning uchun INSERT'da xato berilmaydi).
create or replace function app.guard_users_block_cols() returns trigger
language plpgsql security definer set search_path = public, app, pg_temp as $$
begin
  if app.uid() is null or coalesce(current_setting('iqror.user_block', true), '') = '1' then return new; end if;
  if tg_op = 'INSERT' then
    if not app.is_admin() then new."blockedRole" := null; new."blockedAt" := null; new."blockedBy" := null; end if;
    return new;
  end if;
  if new."blockedRole" is distinct from old."blockedRole" or new."blockedAt" is distinct from old."blockedAt"
     or new."blockedBy" is distinct from old."blockedBy" then
    raise exception 'Bloklash ma''lumotini qo''lda o''zgartirib bo''lmaydi — «🚫 Bloklash» / «Blokdan chiqarish» tugmasidan foydalaning'
      using errcode = '42501';
  end if;
  if coalesce(old.status, '') = 'blocked' and (new.role is distinct from old.role or new.status is distinct from old.status) then
    raise exception 'Bu hisob bloklangan — rol va holat faqat «Blokdan chiqarish» tugmasi bilan o''zgaradi (sahifani yangilang)'
      using errcode = '42501';
  end if;
  if coalesce(new.status, '') = 'blocked' and coalesce(old.status, '') <> 'blocked' then
    raise exception 'Hisob faqat «🚫 Bloklash» tugmasi bilan bloklanadi (rol olinadi, kirish taqiqlanadi)'
      using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function app.guard_users_block_cols() from public, anon, authenticated;
drop trigger if exists trg_users_block_cols on public.users;
create trigger trg_users_block_cols before insert or update on public.users
  for each row execute function app.guard_users_block_cols();

-- 3) Bloklash. Natija: {ok, code?, already, prevRole, claims, sessions, tokens, sessionsError}.
--    code: bad_request | forbidden (chaqiruvchi faol direktor emas) | self | not_found | last_director.
--    To'liq bloklangan hisob (status 'blocked' va rol olingan) — "blockedRole" o'zgarmaydi (asl rol yo'qolmasin), already;
--    seanslar va FAOL bog'lanishlar qayta tozalanadi (taqiqni qayta qo'yish — auth-server).
--    ESKI usulda bloklangan hisob (status 'blocked', rol SAQLANGAN — rol funksiyalari statusni tekshirmagani uchun ochiq seans
--    bilan huquqlar ishlayverardi) — shu yerda to'liq bloklanadi: rol "blockedRole"ga o'tadi.
create or replace function public.user_block(p_uid text, p_actor text) returns jsonb
language plpgsql security definer set search_path = public, app, pg_temp as $$
declare
  a record; t record; v_now timestamptz := now(); v_others int; v_full boolean;
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
  v_full := coalesce(t.status, '') = 'blocked' and coalesce(t.role, '') = '';
  perform set_config('app.uid', p_actor, true);   -- change_log: kim blokladi (shu tranzaksiya ichida)
  if not v_full then
    -- Oxirgi FAOL direktor qolishi shart (eski usulda bloklangan direktor faol hisoblanmaydi — sanoqqa ta'sir qilmaydi).
    if t.role = 'director' and coalesce(nullif(t.status, ''), 'active') = 'active' then
      select count(*) into v_others from public.users u
       where u.role = 'director' and coalesce(nullif(u.status, ''), 'active') = 'active' and u.id <> p_uid;
      if v_others < 1 then return jsonb_build_object('ok', false, 'code', 'last_director'); end if;
    end if;
    perform set_config('iqror.user_block', '1', true);   -- himoya trigger'i: shu RPC o'zgartirmoqda
    update public.users
       set "blockedRole" = coalesce(nullif(role, ''), nullif("blockedRole", '')), role = null, status = 'blocked',
           "blockedAt" = v_now, "blockedBy" = p_actor, "updatedAt" = v_now
     where id = p_uid;
    perform set_config('iqror.user_block', '', true);
  end if;
  update public.child_claims set status = 'revoked', "updatedAt" = v_now
   where uid = p_uid and coalesce(nullif(status, ''), 'active') = 'active';
  get diagnostics v_claims = row_count;
  -- Kirish seanslari: refresh token'lar va seanslar o'chiriladi (jadval bo'lmasa — o'tkaziladi). Har biri ALOHIDA: biri xato
  --   bersa ikkinchisi baribir bajariladi va soni to'g'ri qaytadi. Xato bloklashni to'xtatmaydi (rol baribir olingan, GoTrue
  --   taqig'i token yangilashni ham yopadi) — auth-server javobida ko'rsatiladi.
  if to_regclass('auth.refresh_tokens') is not null then
    begin
      execute 'delete from auth.refresh_tokens where user_id::text = $1' using p_uid;
      get diagnostics v_rt = row_count;
    exception when others then v_rt := 0; v_serr := sqlstate;
    end;
  end if;
  if to_regclass('auth.sessions') is not null then
    begin
      execute 'delete from auth.sessions where user_id::text = $1' using p_uid;
      get diagnostics v_ss = row_count;
    exception when others then v_ss := 0; v_serr := coalesce(v_serr, sqlstate);
    end;
  end if;
  return jsonb_build_object('ok', true, 'already', v_full,
    'prevRole', case when v_full then t."blockedRole" else coalesce(nullif(t.role, ''), t."blockedRole") end,
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
  perform set_config('iqror.user_block', '1', true);   -- himoya trigger'i: shu RPC o'zgartirmoqda
  update public.users
     set role = v_role, status = v_status, "blockedRole" = null, "blockedAt" = null, "blockedBy" = null, "updatedAt" = v_now
   where id = p_uid;
  perform set_config('iqror.user_block', '', true);
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

-- 5) Bloklangan ota-ona (muddati tugamagan JWT bilan) o'z farzand bog'lanishini o'chira olmaydi: aks holda «revoked»
--    bog'lanishni o'chirib, blokdan chiqarilganda uni qaytarib bo'lmasdi. (security-2b.sql cc_del'ning davomi — boshqa
--    hamma uchun qoida o'zgarmagan: o'z bog'lanishi yoki direktor.)
drop policy if exists cc_del on public.child_claims;
create policy cc_del on public.child_claims for delete
  using ((uid = app.uid() and not exists (select 1 from public.users u where u.id = app.uid() and u.status = 'blocked'))
         or app.is_admin());

notify pgrst, 'reload schema';
