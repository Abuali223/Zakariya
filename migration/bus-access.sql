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
--   Bog'lanish bola HAQIQATAN ro'yxatda bo'lsa va maktabdan KETMAGAN bo'lsa hisoblanadi: child_claims
--   o'chirilmaydi (ID qayta berilmasligi uchun belgi), shuning uchun o'chirilgan yoki «chiqdi» (ketish sanasi
--   kelgan) bolaning sobiq oilasi avtobusni ko'rmaydi. Muzlatilgan bola oilasi — ko'radi (maktabda qoladi).
--   Xodimlar (app.is_staff — direktor ham shu ichida) avvalgidek ko'radi.
--
--   O'CHIRISH (eski xato): bus_positions'da DELETE siyosati yo'q edi — direktor yo'nalishni o'chirganda
--   admin.html joylashuv qatorini ham o'chirmoqchi bo'lardi, RLS esa 0 qatorni jim «o'chirardi»: oxirgi
--   joylashuv va haydovchi ismi qolib ketardi. Endi direktor o'chira oladi; avvalgi yetim qatorlar tozalanadi.
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
      join public.students s on s.id = app.claim_row(cc."studentId", cc.code)   -- bola ro'yxatda (aniq bitta)
     where cc.uid = app.uid()
       and coalesce(nullif(cc.status, ''), 'active') = 'active'
       and not (coalesce(s."payStatus", '') = 'chiqdi'
                and coalesce(nullif(s."stopFrom", ''), '0000-01-01') <= to_char(app.tashkent_now(), 'YYYY-MM-DD')))
$$;
grant execute on function app.has_active_child() to anon, authenticated, service_role;

drop policy if exists bp_sel on public.bus_positions;
create policy bp_sel on public.bus_positions for select
  using (app.is_staff() or app.has_active_child());

drop policy if exists bp_del on public.bus_positions;
create policy bp_del on public.bus_positions for delete
  using (app.is_admin());
-- O'chirilgan yo'nalishlardan qolgan (yetim) joylashuvlar — keraksiz va maxfiy (haydovchi ismi).
delete from public.bus_positions p where not exists (select 1 from public.bus_routes r where r.id = p.id);

notify pgrst, 'reload schema';
