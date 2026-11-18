\if :{?iqror_chain}
\else
\set ON_ERROR_STOP on
do $iqror_guard$ begin raise exception 'iqror: audit-11-platforma.sql ALOHIDA ishga tushirilmaydi — zanjirdagi keyingi fayllar uni qayta belgilaydi (alohida ishlatilsa xavfsizlik/moliya qoidalari ESKI holatga qaytadi)' using hint = 'Butun zanjir: bash ~/iqror-repo/deploy.sh  (eski deploy.sh bo''lsa avval: cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash deploy.sh). Qo''lda: bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q'; end $iqror_guard$;
\quit
\endif
-- =====================================================================
-- AUDIT-11 (to'liq audit, 2026-11-18) — PLATFORMA.
--
-- 1) CHEGIRMA «MEROS» NUSXALARI (A8-01, pul).
--    Muammo: discount-approval.sql 4-bo'limi har deployda (zanjir har safar qayta ishlaydi) student_private'dagi chegirmadan
--    muddatsiz (fromMonth/toMonth bo'sh) «meros» tasdiq yaratardi — Direktor va Moliya menejeri tasdiqlagan VAQTINCHALIK yoki
--    KELAJAKDAGI so'rov uchun ham (discount_apply qiymatni darhol yozadi). Natija: keyingi deploydan boshlab grant / 50% /
--    kontrakt / aka-uka 10% tasdiq qamramagan oylarda ham qo'llanardi (fakturalar 0 yoki chegirma bilan, Direktor sahifasida
--    «avvaldan bor (meros)» — ogohlantirishsiz). Endi o'sha INSERT faqat haqiqiy merosga yoziladi; avvalgi deploylar qoldirgan
--    nusxalar SHU YERDA bekor qilinadi (har deployda xavfsiz: topilmasa hech narsa qilmaydi va hech narsa yozmaydi).
--    Noto'g'ri nusxa: legacy, hali 'approved', va shu o'quvchining SHU guruhida (toifa / aka-uka) nusxadan OLDIN so'ralgan oddiy
--    tasdiqlangan so'rov bor. Haqiqiy meros jadval yaratilgan birinchi deployda — hech qanday so'rovdan oldin — yaratilgan, shuning
--    uchun tegilmaydi (keyin «O'zgartirish» bilan qo'shilgan muddatli so'rov ham uni bekor qilmaydi: muddat tugagach meros chegirma
--    yana amal qiladi — avvalgi xulq).
--    Nusxaga ishora qilgan fakturalar (bekor / qaytarilganidan tashqari): shu oy uchun billing (admin.html discountEffective) endi
--    tanlaydigan haqiqiy so'rov — shu guruh, oyni qamragan, eng so'nggi tasdiqlangan — AYNAN shu ta'sirli bo'lsa (toifa, kontrakt
--    summasi, aka-uka belgisi bir xil) summa to'g'ri: faqat ishora ko'chiriladi (aks holda faktura «Pul qoidalari buzilishi»da
--    behuda chiqardi, «↻ Qayta hisoblash» esa summa o'zgarmagani uchun uni tuzatmasdi). Qolganlari TEGILMAYDI — chegirma tasdiqsiz
--    berilgan: Direktor «↻ Qayta hisoblash» qiladi (ro'yxat — deploy chiqishidagi «OGOHLANTIRISH» qatorida va «Pul qoidalari
--    buzilishi» hisobotida). Bir fakturada ko'chirib bo'lmaydigan ishora bo'lsa — faktura butunligicha tegilmaydi.
--    Nusxa O'CHIRILMAYDI, bekor qilinadi (tarix qoladi); bekor qilingan id'ni discount-approval.sql qayta yaratmaydi (on conflict).
--    Migratsiyada (JWT yo'q) faktura qo'riqchisi faqat yangi ishoralarni tekshiradi; o'zgarishlar tarixiga yozilmaydi (iqror.migrating).
--
-- Idempotent — QAYTA ishga tushirishga xavfsiz (create or replace; ma'lumot tuzatish — faqat topilsa, NOTICE bilan).
--   (ALOHIDA ishga tushirilmaydi — faqat butun zanjir ichida: bash deploy.sh yoki migration/chain.sh | psql)
-- =====================================================================

-- ---------- 1) Chegirma «meros» nusxalari ----------
-- Chegirmaning billingdagi ta'siri (discApplyEff bilan bir xil): toifa (ijtimoiy himoya = olimpiada granti), kontrakt summasi,
--   aka-uka belgisi; 'none' / 'sibling_auto' — ta'sirsiz.
create or replace function app.discount_effect(p_kind text, p_params jsonb) returns jsonb
language sql immutable set search_path = pg_catalog as $$
  select case p_kind
           when 'social' then to_jsonb('olympiad'::text)
           when 'contract' then jsonb_build_object('contract', p_params -> 'contractAmount')
           when 'none' then 'null'::jsonb
           when 'sibling_auto' then 'null'::jsonb
           else to_jsonb(p_kind) end
$$;

-- Tuzatish: xulosa jsonb — canceled (bekor qilingan nusxalar soni), students, moved (ishorasi ko'chgan fakturalar), reprice
--   (Direktor qayta hisoblashi kerak bo'lgan fakturalar).
create or replace function app.discount_legacy_repair() returns jsonb
language plpgsql volatile set search_path = public, app, pg_temp as $$
declare v_bogus text[]; v_sids text[]; i record; v_new jsonb; v_moved text[] := '{}'; v_left text[] := '{}';
begin
  select coalesce(array_agg(l.id order by l.id), '{}'), coalesce(array_agg(distinct l."studentId"), '{}')
    into v_bogus, v_sids
    from public.discount_requests l
   where l.legacy and l.status = 'approved'
     and exists (select 1 from public.discount_requests q
                  where not q.legacy and q.status = 'approved' and q."studentId" = l."studentId"
                    and app.discount_group(q.kind) = app.discount_group(l.kind)
                    and q."requestedAt" <= l."requestedAt");
  if cardinality(v_bogus) = 0 then
    return jsonb_build_object('canceled', 0, 'students', '[]'::jsonb, 'moved', '[]'::jsonb, 'reprice', '[]'::jsonb);
  end if;
  for i in select v.id, v."studentId" as sid, v.month, v."approvalRefs" as refs
             from public.invoices v
            where jsonb_typeof(v."approvalRefs") = 'array' and v."approvalRefs" ?| v_bogus
              and coalesce(v.status, '') not in ('canceled', 'reversed')
            order by v.id
  loop
    -- Har ishora: nusxa bo'lmasa — o'zi; nusxa bo'lsa — shu oy uchun o'rnini bosadigan, ta'siri bir xil haqiqiy so'rov (bo'lmasa NULL).
    select case when bool_and(x.rep is not null) then jsonb_agg(to_jsonb(x.rep) order by x.n) end into v_new
      from (select e.n,
                   case when not (e.ref = any(v_bogus)) then e.ref else (
                     select q.id
                       from public.discount_requests l
                       join lateral (select q2.id, q2.kind, q2.params from public.discount_requests q2
                                      where q2."studentId" = i.sid and q2.status = 'approved' and not (q2.id = any(v_bogus))
                                        and app.discount_group(q2.kind) = app.discount_group(l.kind)
                                        and (q2."fromMonth" is null or i.month >= q2."fromMonth")
                                        and (q2."toMonth" is null or i.month <= q2."toMonth")
                                      order by coalesce(q2."appliedAt", q2."financeAt", q2."directorAt", q2."requestedAt") desc nulls last,
                                               q2.id collate "C" desc
                                      limit 1) q on true
                      where l.id = e.ref and l."studentId" = i.sid
                        and app.discount_effect(q.kind, q.params) = app.discount_effect(l.kind, l.params)) end as rep
              from jsonb_array_elements_text(i.refs) with ordinality e(ref, n)) x;
    if v_new is null then
      v_left := v_left || i.id;
    else
      begin
        update public.invoices set "approvalRefs" = v_new where id = i.id;
        v_moved := v_moved || i.id;
      exception when others then
        -- Qo'riqchi (yoki boshqa trigger) rad etsa — faktura tegilmaydi, Direktor ro'yxatiga tushadi; deploy to'xtamaydi.
        raise notice 'chegirma (A8-01): % fakturasining ishorasini ko''chirib bo''lmadi (%) — qayta hisoblash ro''yxatida', i.id, sqlerrm;
        v_left := v_left || i.id;
      end;
    end if;
  end loop;
  update public.discount_requests
     set status = 'canceled',
         reason = coalesce(reason, '') || ' [A8-01: deploy nusxasi — shu guruhda tasdiqlangan haqiqiy so''rov bor; bekor qilindi]'
   where id = any(v_bogus);
  return jsonb_build_object('canceled', cardinality(v_bogus), 'students', to_jsonb(v_sids), 'moved', to_jsonb(v_moved), 'reprice', to_jsonb(v_left));
end $$;

-- deploy.sh «OGOHLANTIRISH» qatorlarini chiqishda ko'rsatadi: o'quvchi va faktura ID'lari (ism yo'q) — Direktor qayta hisoblaydi.
create or replace function app.discount_legacy_repair_notice() returns jsonb
language plpgsql volatile set search_path = public, app, pg_temp as $$
declare r jsonb := app.discount_legacy_repair();
begin
  if (r ->> 'canceled')::int > 0 then
    raise notice 'OGOHLANTIRISH: chegirma (A8-01): % ta noto''g''ri «meros» nusxasi bekor qilindi (avvalgi deploylar tasdiqlangan muddatli / kelajakdagi so''rovdan muddatsiz nusxa olgan edi) — % ta o''quvchi: %; % ta fakturada ishora haqiqiy so''rovga ko''chirildi (summa o''zgarmaydi)',
      r ->> 'canceled', jsonb_array_length(r -> 'students'), (select string_agg(x, ', ') from jsonb_array_elements_text(r -> 'students') x),
      jsonb_array_length(r -> 'moved');
  end if;
  if jsonb_array_length(r -> 'moved') > 0 then   -- iz uchun (SQL logida qoladi): qaysi fakturalarda faqat ishora almashdi
    raise notice 'chegirma (A8-01): ishorasi ko''chirilgan fakturalar (summa o''zgarmagan): %',
      (select string_agg(x, ', ') from jsonb_array_elements_text(r -> 'moved') x);
  end if;
  if jsonb_array_length(r -> 'reprice') > 0 then
    raise notice 'OGOHLANTIRISH: chegirma (A8-01): % ta hisob-faktura tasdiqsiz chegirma / grant bilan chiqqan — Direktor shu oylar uchun «↻ Qayta hisoblash» qilsin (to''langanini qo''lda tekshirsin; ro''yxat «Pul qoidalari buzilishi»da ham): %',
      jsonb_array_length(r -> 'reprice'), (select string_agg(x, ', ') from jsonb_array_elements_text(r -> 'reprice') x);
  end if;
  return r;
end $$;
revoke all on function app.discount_effect(text, jsonb), app.discount_legacy_repair(), app.discount_legacy_repair_notice() from public, anon, authenticated;

do $a801$ begin perform app.discount_legacy_repair_notice(); end $a801$;
