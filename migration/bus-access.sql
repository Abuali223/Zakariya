\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: bus-access.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- bus-access.sql — avtobusning JONLI joylashuvini faqat xodim va farzandi bog'langan ota-ona ko'radi.
--
--   MUAMMO (jonli saytda 2026-10-30 tekshiruvda aniqlandi): bus.sql'dagi bp_sel «kirgan HAR KIM»
--   edi (app.uid() is not null). Ro'yxatdan o'tish ochiq — istalgan odam telefon/email bilan hisob
--   ochadi -> begona odam ham bolalar avtobusining joylashuvi, tezligi, yo'nalishi va haydovchi
--   ismini real vaqtda REST orqali o'qiy olardi (tasdiqlanmagan, farzandsiz sinov hisobi bilan
--   tekshirildi: 2 qator ko'rindi). Kabinet esa avtobusni faqat farzandi bog'langan ota-onaga
--   ko'rsatadi — endi baza ham shunday.
--
--   «Bog'langan» = child_claims'da FAOL yozuv. U faqat claim_child RPC orqali, maktab bergan maxfiy
--   kod bilan yoziladi (to'g'ridan-to'g'ri INSERT yopiq — cc_ins = false; UPDATE siyosati yo'q).
--   Kelajakdagi 'pending'/'revoked' holatlari kirish bermaydi (app.owns_child bilan bir xil qoida).
--   Xodimlar (app.is_staff — direktor ham shu ichida) avvalgidek ko'radi.
--
--   Joyi: parent-student-links.sql (child_claims.status) va auth-hardening.sql (is_staff) DAN KEYIN —
--   bus.sql zanjirda ulardan oldin turadi, shuning uchun yakuniy qoida shu yerda.
-- Idempotent — QAYTA ishga tushirishga xavfsiz.
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- Joriy foydalanuvchida kamida bitta FAOL bog'langan farzand bormi (argumentsiz — rls-initplan.sql uni
--   so'rov boshida bir marta hisoblanadigan qilib o'raydi).
create or replace function app.has_active_child() returns boolean
language sql stable security definer set search_path = public, app, pg_temp as $$
  select app.uid() is not null and exists(
    select 1 from public.child_claims cc
     where cc.uid = app.uid()
       and coalesce(nullif(cc.status, ''), 'active') = 'active')
$$;
grant execute on function app.has_active_child() to anon, authenticated, service_role;

drop policy if exists bp_sel on public.bus_positions;
create policy bp_sel on public.bus_positions for select
  using (app.is_staff() or app.has_active_child());

notify pgrst, 'reload schema';
