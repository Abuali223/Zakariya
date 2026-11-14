#!/usr/bin/env bash
# =====================================================================
# test-kassa-race.sh — KASSA PARALLEL (poyga) sinovi (moliya rejasi F1.3): raqamlash va kassa qulfi.
#   (1) 8 parallel seans × 200 kirim orderi, har 10-chisi ROLLBACK: raqamlar 1…N uzluksiz (bo'shliq yo'q, takror yo'q),
#       bekor qilingan tranzaksiya raqam «yemaydi», deadlock yo'q, qoldiq = hujjatlar yig'indisi;
#   (2) bir xil kalit (clientRef) 8 seansdan — bitta hujjat, qolganlari «takror»;
#   (3) bitta qoldiqqa ikki katta chiqim parallel — faqat BITTASI o'tadi; 8 ta chiqim — qoldiq hech qachon manfiy emas;
#   (4) ikki tasdiq (2-ro'yxat va Direktor) parallel — hujjat «tasdiqlangan» bo'ladi, hech biri yo'qolmaydi;
#   (6) bitta xodimning hisobdor qoldig'i va oy avansiga 8 tadan parallel qaytim — faqat qoldiq yetganlari o'tadi, deadlock yo'q;
#   (7) bitta o'qituvchi va oy: maosh qaytimi (OP-09), naqd maosh va ularni bekor qilish parallel — qulf tartibi bir xil
#       (S → P → L4): deadlock yo'q, berilgan maosh 0 … tasdiqlangan summa oralig'ida, moslik toza;
#   (5) kirimlar davom etayotganda kun yopiladi — yopilgandan keyingi kirimlar rad, kun jami = hujjatlar, tekshiruv o'tadi;
#   (8) sozlama qatori (fin_org) o'zgarayotganda pul yozuvi (state-7): davr qulfi va orqa sana bilan to'lov; kassani to'xtatish va
#       qayta ishga tushirish (ishga tushadigan kun) va naqd o'quv to'lovi — yozuvchi o'zgarish tugashini kutib, yangi qiymat bilan
#       tekshiradi; qayta sanash sozlama qatorini kassa qulfidan oldin kutadi (qulf tartibi); davr surati qulf bilan undan oldin
#       boshlangan to'lovni kutib, uni suratga oladi (8-bo'lim test soatini ertangi va indingi kunga suradi — baza nomi sinov bazasiniki
#       bo'lishi kerak: fx_… / …sinov… / …test…).
#   FAQAT bo'sh sinov bazasida («--dev» zanjiri qurilgan). Baza o'zgaradi — tashlab yuboriladigan baza.
#   Ishlatish:  PSQL_CMD="psql -h <host> -U postgres" bash migration/test-kassa-race.sh <baza>
#   Natija: har tekshiruv PASS/FAIL; xato bo'lsa chiqish kodi 1.
# =====================================================================
set -uo pipefail
DB="${1:?baza nomi kerak}"
PSQL_CMD="${PSQL_CMD:-psql}"
W="${RACE_WORKERS:-8}"; N="${RACE_DOCS:-200}"
q(){ $PSQL_CMD -X -q -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
pass=0; fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1  (olindi: $2 ; kutilgan: $3)"; fi; }
[ "$(q -c "select count(*) from public.cash_docs")" = "0" ] || { echo "test-kassa-race.sh: kassa hujjatlari bor — faqat bo'sh sinov bazasida"; exit 1; }

q >/dev/null <<'SQL'
set session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles") values
  ('R_KAS','rk@x','kassir','active','[]'), ('R_FM','rf@x','finance_mgr','active','[]'), ('R_DIR','rd@x','director','active','[]')
on conflict (id) do nothing;
insert into public.fin_counterparties (id, kind, name) values ('cp_rbank','bank','Poyga Bank'), ('cp_rsup','supplier','Poyga Yetkazuvchi')
on conflict (id) do nothing;
update public.fin_org set t1 = 100000000000, l1 = 0, extra = extra || '{"orgCashMax": 100000000000}'::jsonb where id = 'main';   -- poyga — qoida emas (F1.27)
SQL
as_sess(){   # $1 uid — seans boshida rolni o'rnatadigan satrlar
  printf "select set_config('request.jwt.claims', '{\"sub\":\"%s\",\"role\":\"authenticated\"}', false);\nset role authenticated;\n" "$1"
}
call_raw(){  # $1 uid, $2 SQL ifoda -> psql'ning to'liq chiqishi (xato bo'lsa ERROR / HINT qatorlari bilan)
  { as_sess "$1"; echo "select ($2)::text;"; } | $PSQL_CMD -X -q -At -d "$DB" 2>&1
}
call_as(){   # $1 uid, $2 SQL ifoda -> faqat natija qatori
  call_raw "$1" "$2" | tail -1
}
TODAY=$(q -c "select app.fin_today()")
chk "0 boshlang'ich qoldiq (0 so'm) kiritildi" "$(call_as R_DIR "public.kassa_opening_set('{\"amount\":0,\"startDay\":\"$TODAY\"}') ->> 'ok'")" "true"

TMP=$(mktemp -d)
# ---------- (1) parallel kirimlar, 10 % ROLLBACK ----------
for w in $(seq 1 "$W"); do
  { as_sess R_KAS
    for i in $(seq 1 "$N"); do
      ref=$(printf 'race-w%d-%04d' "$w" "$i")
      stmt="select 'no=' || (public.kassa_receipt('{\"op\":\"in_bank\",\"amount\":$((1000 + w)),\"partyType\":\"bank\",\"partyId\":\"cp_rbank\",\"basis\":\"Poyga cheki\",\"clientRef\":\"$ref\"}'::jsonb) ->> 'no');"
      if [ $((i % 10)) = 0 ]; then echo "begin;"; echo "$stmt"; echo "rollback;"; else echo "$stmt"; fi
    done
  } > "$TMP/w$w.sql"
done
for w in $(seq 1 "$W"); do ( $PSQL_CMD -X -q -At -d "$DB" < "$TMP/w$w.sql" > "$TMP/w$w.out" 2>&1 ) & done
wait
committed=$(( W * (N - N / 10) ))
sum=0; for w in $(seq 1 "$W"); do sum=$(( sum + (N - N / 10) * (1000 + w) )); done
chk "1a xato va deadlock yo'q" "$(cat "$TMP"/w*.out | grep -ci 'error\|deadlock')" "0"
chk "1b saqlangan hujjatlar soni" "$(q -c "select count(*) from public.cash_docs where form = 'KO1' and status = 'posted'")" "$committed"
chk "1c raqamlar 1…N uzluksiz: hisoblagich = soni = eng kattasi = turli raqamlar soni" \
    "$(q -c "select (select \"lastNo\" from public.doc_counters where desk = 'main' and series = 'KO1') || '/' || count(*) || '/' || max(no) || '/' || count(distinct no) from public.cash_docs where form = 'KO1' and no is not null")" \
    "$committed/$committed/$committed/$committed"
chk "1d ROLLBACK qilingan kirimlar iz qoldirmadi" "$(q -c "select count(*) from public.cash_docs where \"clientRef\" ~ '^race-w[0-9]+-[0-9]*0\$'")" "0"
chk "1e qoldiq = hujjatlar yig'indisi" "$(q -c "select trim_scale(app.kassa_day_balance((select id from public.cash_days where desk = 'main' and status = 'open')))")" "$sum"
chk "1f bo'shliq nazorati toza" "$(q -c "select app.kassa_gap_check('main', extract(year from app.fin_today())::int)")" "[]"

# ---------- (2) bir xil kalit 8 seansdan ----------
for i in $(seq 1 8); do
  ( call_as R_KAS "public.kassa_receipt('{\"op\":\"in_bank\",\"amount\":777,\"partyType\":\"bank\",\"partyId\":\"cp_rbank\",\"basis\":\"Poyga cheki\",\"clientRef\":\"race-same-0001\"}'::jsonb) ->> 'dup'" > "$TMP/same.$i" ) &
done
wait
chk "2a bir xil kalit: bitta yangi, 7 takror, xato yo'q" "$(cat "$TMP"/same.* | grep -c '^false$')/$(cat "$TMP"/same.* | grep -c '^true$')/$(cat "$TMP"/same.* | grep -vc '^\(true\|false\)$')" "1/7/0"
chk "2b bazada bitta hujjat" "$(q -c "select count(*) from public.cash_docs where \"clientRef\" = 'race-same-0001'")" "1"
sum=$(( sum + 777 ))

# ---------- (3) bitta qoldiqqa parallel chiqimlar ----------
mkreq(){   # $1 clientRef, $2 summa -> tasdiqlangan chiqim so'rovi id'si
  local id
  id=$(call_as R_KAS "public.kassa_payout_request('{\"op\":\"out_expense\",\"amount\":$2,\"partyType\":\"counterparty\",\"partyId\":\"cp_rsup\",\"articleId\":\"EX-16\",\"basis\":\"Poyga hujjati\",\"clientRef\":\"$1\"}'::jsonb) ->> 'id'")
  call_as R_FM "public.kassa_doc_approve('$id') ->> 'status'" >/dev/null
  echo "$id"
}
big=$(( sum * 6 / 10 ))
a=$(mkreq race-big-0001 "$big"); b=$(mkreq race-big-0002 "$big")
( call_raw R_KAS "public.kassa_doc_pay('$a') ->> 'status'" > "$TMP/big.1" ) &
( call_raw R_KAS "public.kassa_doc_pay('$b') ->> 'status'" > "$TMP/big.2" ) &
wait
chk "3a ikki katta chiqimdan faqat bittasi o'tdi" "$(cat "$TMP"/big.* | grep -c '^posted$')/$(cat "$TMP"/big.* | grep -c 'kassa:negative')" "1/1"
sum=$(( sum - big ))
part=$(( sum * 3 / 10 ))
ids=""; for i in $(seq 1 8); do ids="$ids $(mkreq "race-part-000$i" "$part")"; done
i=0; for id in $ids; do i=$((i+1)); ( call_raw R_KAS "public.kassa_doc_pay('$id') ->> 'status'" > "$TMP/part.$i" ) & done
wait
chk "3b sakkiz chiqimdan faqat qoldiq yetgani (3 ta) o'tdi" "$(cat "$TMP"/part.* | grep -c '^posted$')/$(cat "$TMP"/part.* | grep -c 'kassa:negative')" "3/5"
sum=$(( sum - 3 * part ))
chk "3c qoldiq manfiy emas va hisobga teng" "$(q -c "select trim_scale(app.kassa_day_balance((select id from public.cash_days where desk = 'main' and status = 'open')))")" "$sum"
chk "3d KO-2 raqamlari uzluksiz (rad etilganlar raqam yemadi)" \
    "$(q -c "select (select \"lastNo\" from public.doc_counters where desk = 'main' and series = 'KO2') || '/' || count(*) || '/' || max(no) from public.cash_docs where form = 'KO2' and no is not null")" "4/4/4"

# ---------- (4) ikki tasdiq parallel ----------
q >/dev/null -c "update public.fin_org set t1 = 0 where id = 'main'"
dids=""; for i in $(seq 1 8); do
  dids="$dids $(call_as R_KAS "public.kassa_payout_request('{\"op\":\"out_expense\",\"amount\":10,\"partyType\":\"counterparty\",\"partyId\":\"cp_rsup\",\"articleId\":\"EX-16\",\"basis\":\"Poyga hujjati\",\"clientRef\":\"race-two-000$i\"}'::jsonb) ->> 'id'")"
done
i=0; for id in $dids; do i=$((i+1))
  ( call_as R_FM "public.kassa_doc_approve('$id') ->> 'ok'" > "$TMP/ap.fm.$i" ) &
  ( call_as R_DIR "public.kassa_doc_approve('$id') ->> 'ok'" > "$TMP/ap.dir.$i" ) &
done
wait
chk "4a parallel ikki tasdiq: 16 tasi ham qabul qilindi" "$(cat "$TMP"/ap.* | grep -c '^true$')" "16"
chk "4b sakkiz hujjat ham «tasdiqlangan» (ikkala imzo joyida)" \
    "$(q -c "select count(*) from public.cash_docs where \"clientRef\" like 'race-two-%' and status = 'approved' and \"approvedBy\" = 'R_FM' and \"dirApprovedBy\" = 'R_DIR'")" "8"

# ---------- (6) xodim qoldig'i: parallel qaytimlar qoldiqdan oshmaydi (acc-3 hisobdor qulfi, acc-1 avans navbati) ----------
q >/dev/null <<'SQL'
set session_replication_role = replica;
insert into public.staff (id, "staffId", name, position) values ('r_st1','IQX-R1','Poyga Xodim','Farrosh') on conflict (id) do nothing;
SQL
mkpaid(){   # $1 operatsiya, $2 clientRef, $3 summa -> xodimga berilgan chiqim hujjati holati (T1 = 0: 2-ro'yxat va Direktor tasdig'i)
  local id
  id=$(call_as R_KAS "public.kassa_payout_request('{\"op\":\"$1\",\"amount\":$3,\"partyType\":\"employee\",\"partyId\":\"staff:r_st1\",\"basis\":\"Poyga avansi\",\"clientRef\":\"$2\"}'::jsonb) ->> 'id'")
  call_as R_FM "public.kassa_doc_approve('$id') ->> 'status'" >/dev/null
  call_as R_DIR "public.kassa_doc_approve('$id') ->> 'status'" >/dev/null
  call_as R_KAS "public.kassa_doc_pay('$id') ->> 'status'"
}
adv=$(( sum / 5 / 10 * 10 )); ret=$(( adv * 3 / 10 ))   # 3 ta qaytim sig'adi (90 %), 4-chisi — yo'q
chk "6a hisobdorga avans va ish haqi avansi berildi (qoldiqning 1/5 qismidan)" "$(mkpaid out_accountable race-acc-0001 $adv)/$(mkpaid out_advance race-adv-0001 $adv)" "posted/posted"
sum=$(( sum - 2 * adv ))
for i in $(seq 1 8); do
  ( call_raw R_KAS "public.kassa_receipt('{\"op\":\"in_acc_return\",\"amount\":$ret,\"partyType\":\"employee\",\"partyId\":\"staff:r_st1\",\"basis\":\"Poyga qaytimi\",\"clientRef\":\"race-ret-000$i\"}'::jsonb) ->> 'status'" > "$TMP/ret.$i" ) &
  ( call_raw R_KAS "public.kassa_receipt('{\"op\":\"in_staff_return\",\"amount\":$ret,\"month\":\"${TODAY:0:7}\",\"partyType\":\"employee\",\"partyId\":\"staff:r_st1\",\"articleId\":\"OP-08\",\"basis\":\"Poyga avans qaytimi\",\"clientRef\":\"race-sret-000$i\"}'::jsonb) ->> 'status'" > "$TMP/sret.$i" ) &
done
wait
chk "6b sakkiz parallel hisobdor qaytimidan faqat qoldiq yetgani (3 ta) o'tdi" "$(cat "$TMP"/ret.* | grep -c '^posted$')/$(cat "$TMP"/ret.* | grep -c 'kassa:acc_over')" "3/5"
chk "6c sakkiz parallel avans qaytimidan faqat avans qoldig'i yetgani (3 ta) o'tdi; deadlock yo'q" \
    "$(cat "$TMP"/sret.* | grep -c '^posted$')/$(cat "$TMP"/sret.* | grep -c 'kassa:staff_over')/$(cat "$TMP"/ret.* "$TMP"/sret.* | grep -ci 'deadlock')" "3/5/0"
chk "6d qoldiqlar manfiy emas: hisobdorda va oy avansida — avansning 10 % i (manfiy avans yozuvlari 3 ta)" \
    "$(q -c "select trim_scale(app.kassa_acc_open('staff:r_st1')) || '/' || trim_scale(app.payroll_adv('IQX-R1', '${TODAY:0:7}')) || '/' || (select count(*) from public.staff_advances where amount < 0)")" "$(( adv - 3 * ret ))/$(( adv - 3 * ret ))/3"
sum=$(( sum + 6 * ret ))

# ---------- (7) bitta o'qituvchi va oy: maosh qaytimi (OP-09), naqd maosh va bekor qilish parallel — qulf tartibi S → P → L4 ----------
#   Naqd maosh (kassa_salary_pay) maosh navbatini (S, darvoza trigeri) xodim kaliti navbatidan (P, kalit trigeri) OLDIN oladi;
#   qaytim va uni bekor qilish ham shu tartibda (kassa_link_prelock) — teskari tartib deadlock berardi; maosh orderini bekor qilish —
#   P bilan (undan yozilgan qaytimlar bilan bir navbat). O'tgan oy vedomosti tasdiqlangan: 3 000 000. Natija tartibga bog'liq —
#   tekshiruvlar invariant: har amal yo o'tadi, yo o'z qoidasi bilan rad etiladi; deadlock yo'q; berilgan maosh = o'tganlar yig'indisi,
#   0 … 3 000 000 oralig'ida (manfiy ham, tasdiqlangandan ko'p ham emas); moslik toza; kassa qoldig'i = hisob.
PREV=$(q -c "select to_char(app.fin_today() - interval '1 month', 'YYYY-MM')")
q >/dev/null <<SQL
set session_replication_role = replica;
insert into public.teachers (id, "teacherId", name, pauses) values ('r_t1','IQT-R1','Poyga Oqituvchi','[]') on conflict (id) do nothing;
insert into public.config (id, "payrollApprovalFrom") values ('finance', '$PREV')
  on conflict (id) do update set "payrollApprovalFrom" = excluded."payrollApprovalFrom";
insert into public.payroll_runs (id, status, "approvedBy", "approvedAt") values ('$PREV', 'approved', 'R_DIR', now()) on conflict (id) do nothing;
insert into public.payroll_lines (id, "runId", "personType", "personId", "refId", name, gross, payable)
  values ('${PREV}__teacher__IQT-R1', '$PREV', 'teacher', 'IQT-R1', 'r_t1', 'Poyga', 3000000, 3000000) on conflict (id) do nothing;
SQL
salp(){ echo "{\"id\":\"$1\",\"method\":\"cash\",\"teacherId\":\"IQT-R1\",\"payeeRef\":\"teachers:r_t1\",\"teacherName\":\"Poyga\",\"month\":\"$PREV\",\"paid\":$2,\"gross\":3000000,\"advance\":0,\"deduction\":0,\"subBonus\":0,\"net\":3000000,\"carryIn\":0,\"carryOut\":0}"; }
op9(){ echo "{\"op\":\"in_staff_return\",\"amount\":$2,\"month\":\"$PREV\",\"partyType\":\"employee\",\"partyId\":\"teachers:r_t1\",\"articleId\":\"OP-09\",\"basis\":\"Poyga maosh qaytimi\",\"clientRef\":\"$1\"}"; }
state7(){ q -c "select coalesce(trim_scale(sum(paid)), 0) from public.salary_payments where \"teacherId\" = 'IQT-R1' and month = '$PREV'" | tr '\n' '/'
          q -c "select (app.kassa_reconcile(null, null) ->> 'total') || '/' || trim_scale(app.kassa_day_balance((select id from public.cash_days where desk = 'main' and status = 'open')))"; }
in7(){ [ "$net" -ge 0 ] && [ "$net" -le 3000000 ] && echo ichida; }
chk "7a kassa bugundan ishga tushirildi (shu kungi hujjatlar moslikdan o'tdi); kassaga bankdan 20 000 000 kirdi; o'qituvchiga o'tgan oy uchun naqd maosh 1 000 000 berildi" \
    "$(call_as R_DIR "public.fin_org_set('{\"kassaGoLive\":\"$TODAY\"}') ->> 'kassaGoLive'")/$(call_as R_KAS "public.kassa_receipt('{\"op\":\"in_bank\",\"amount\":20000000,\"partyType\":\"bank\",\"partyId\":\"cp_rbank\",\"basis\":\"Poyga cheki\",\"clientRef\":\"race-fund-0001\"}'::jsonb) ->> 'status'")/$(call_as R_KAS "public.kassa_salary_pay('$(salp sp_race_s0000 1000000)'::jsonb) -> 'kassa' ->> 'status'")" "$TODAY/posted/posted"
sum=$(( sum + 20000000 - 1000000 )); net=1000000
# 1-to'lqin: 8 ta qaytim (200 000) va 8 ta maosh (300 000)
for i in $(seq 1 8); do
  ( call_raw R_KAS "public.kassa_receipt('$(op9 race-op9-000$i 200000)'::jsonb) ->> 'status'" > "$TMP/r7.$i" ) &
  ( call_raw R_KAS "public.kassa_salary_pay('$(salp sp_race_s000$i 300000)'::jsonb) -> 'kassa' ->> 'status'" > "$TMP/s7.$i" ) &
done
wait
pr=$(cat "$TMP"/r7.* | grep -c '^posted$'); ps=$(cat "$TMP"/s7.* | grep -c '^posted$')
chk "7b sakkiz qaytim (200 000) va sakkiz maosh (300 000) parallel: o'tdi yoki rad (qaytim — berilgandan katta, maosh — tasdiqlangandan ko'p); deadlock yo'q" \
    "$(( pr + $(cat "$TMP"/r7.* | grep -c 'kassa:staff_over') ))/$(( ps + $(cat "$TMP"/s7.* | grep -c 'tasdiqlangan summadan oshadi') ))/$(cat "$TMP"/r7.* "$TMP"/s7.* | grep -ci 'deadlock')" "8/8/0"
sum=$(( sum + 200000 * pr - 300000 * ps )); net=$(( net + 300000 * ps - 200000 * pr ))
chk "7c berilgan maosh = 1 000 000 + o'tgan maoshlar − o'tgan qaytimlar (0 … 3 000 000); moslik toza; kassa qoldig'i hisobga teng" "$(state7)/$(in7)" "$net/0/$sum/ichida"
# 2-to'lqin: o'tgan qaytimlar bekor qilinadi (darvoza bilan bir navbat — S) va yana 8 ta maosh beriladi
ids7=$(q -c "select string_agg(id, ' ' order by id) from public.cash_docs where \"clientRef\" like 'race-op9-%' and status = 'posted'")
i=0; for id in $ids7; do i=$((i+1)); ( call_raw R_KAS "public.kassa_doc_void('$id', 'Poyga bekor') ->> 'status'" > "$TMP/v7.$i" ) & done
for i in $(seq 1 8); do ( call_raw R_KAS "public.kassa_salary_pay('$(salp sp_race_s001$i 300000)'::jsonb) -> 'kassa' ->> 'status'" > "$TMP/t7.$i" ) & done
wait
pv=$(cat "$TMP"/v7.* | grep -c '^void$'); pt=$(cat "$TMP"/t7.* | grep -c '^posted$')
chk "7d qaytimlarni bekor qilish (qaytgan pul qayta berilgan bo'lsa — rad) va yana 8 ta maosh parallel: o'tdi yoki o'z qoidasi bilan rad; deadlock yo'q" \
    "$(( pv + $(cat "$TMP"/v7.* | grep -c 'kassa:salary_repaid') ))/$(( pt + $(cat "$TMP"/t7.* | grep -c 'tasdiqlangan summadan oshadi') ))/$(cat "$TMP"/v7.* "$TMP"/t7.* | grep -ci 'deadlock')" "$pr/8/0"
sum=$(( sum - 200000 * pv - 300000 * pt )); net=$(( net + 200000 * pv + 300000 * pt ))
chk "7e berilgan maosh tasdiqlangandan oshmadi (0 … 3 000 000) va o'tganlar yig'indisiga teng; moslik toza; kassa qoldig'i hisobga teng" "$(state7)/$(in7)" "$net/0/$sum/ichida"
# 3-to'lqin: 8 ta katta qaytim (2 100 000) va shu payt birinchi maosh orderi (1 000 000) bekor qilinadi — bir navbatda (P): kim oldin
#   o'tsa, ikkinchisi rad etiladi (qaytimdan keyin bekor qilinsa yoki bekor qilingandan keyin qaytim bo'lsa sof berilgan manfiy bo'lardi)
s0=$(q -c "select \"cashDocId\" from public.salary_payments where id = 'sp_race_s0000'")
for i in $(seq 1 8); do ( call_raw R_KAS "public.kassa_receipt('$(op9 race-op9-001$i 2100000)'::jsonb) ->> 'status'" > "$TMP/u7.$i" ) & done
( call_raw R_KAS "public.kassa_doc_void('$s0', 'Poyga bekor') ->> 'status'" > "$TMP/w7.0" ) &
wait
pw=$(grep -c '^void$' "$TMP/w7.0"); pu=$(cat "$TMP"/u7.* | grep -c '^posted$')
chk "7f 8 ta katta qaytim va birinchi maoshni bekor qilish parallel: o'tdi yoki o'z qoidasi bilan rad (qaytim — berilgandan katta, bekor qilish — undan qaytim bor); deadlock yo'q" \
    "$(( pw + $(grep -c 'kassa:staff_returned' "$TMP/w7.0") ))/$(( pu + $(cat "$TMP"/u7.* | grep -c 'kassa:staff_over') ))/$(cat "$TMP"/w7.0 "$TMP"/u7.* | grep -ci 'deadlock')" "1/8/0"
sum=$(( sum + 1000000 * pw + 2100000 * pu )); net=$(( net - 1000000 * pw - 2100000 * pu ))
chk "7g sof berilgan maosh manfiy emas (0 … 3 000 000) va o'tganlar yig'indisiga teng; moslik toza; kassa qoldig'i hisobga teng" "$(state7)/$(in7)" "$net/0/$sum/ichida"

# ---------- (5) kirimlar davom etayotganda kun yopiladi ----------
for w in 1 2 3 4; do
  { as_sess R_KAS
    for i in $(seq 1 60); do
      echo "select 'r=' || coalesce(public.kassa_receipt('{\"op\":\"in_bank\",\"amount\":500,\"partyType\":\"bank\",\"partyId\":\"cp_rbank\",\"basis\":\"Poyga cheki\",\"clientRef\":\"$(printf 'race-c%d-%04d' "$w" "$i")\"}'::jsonb) ->> 'no', '?');"
    done
  } > "$TMP/c$w.sql"
done
for w in 1 2 3 4; do ( $PSQL_CMD -X -q -At -d "$DB" < "$TMP/c$w.sql" > "$TMP/c$w.out" 2>&1 ) & done
sleep 0.15
call_as R_KAS "public.kassa_day_close('{\"day\":\"$TODAY\",\"counted\":$sum}'::jsonb) ->> 'ok'" > "$TMP/close.out"
wait
chk "5a kun yopildi" "$(cat "$TMP/close.out")" "true"
ok5=$(cat "$TMP"/c*.out | grep -c '^r=[0-9]'); rej5=$(cat "$TMP"/c*.out | grep -c 'kassa kuni yopilgan'); oth5=$(cat "$TMP"/c*.out | grep -ci 'deadlock')
chk "5b har kirim yo o'tdi, yo «kun yopilgan» deb rad etildi; deadlock yo'q" "$((ok5 + rej5))/$oth5" "240/0"
chk "5c yopilgan kunda o'tgan kirimlar soni bazadagi bilan bir xil" "$(q -c "select count(*) from public.cash_docs where \"clientRef\" like 'race-c%' and status = 'posted'")" "$ok5"
chk "5d I4: kun oxiri = kun boshi + kirim − chiqim (hujjatlardan qayta hisoblangan) = sanalgan" \
    "$(q -c "select (d.closing = d.opening + (select coalesce(sum(amount) filter (where form = 'KO1'), 0) - coalesce(sum(amount) filter (where form = 'KO2'), 0) from public.cash_docs c where c.\"dayId\" = d.id and c.status = 'posted'))::text || '/' || (d.counted = d.closing)::text from public.cash_days d where d.desk = 'main' and d.day = '$TODAY'")" "true/true"
chk "5e farq hujjati: yopish paytigacha o'tgan kirimlar summasi" \
    "$(q -c "select (abs(d.diff) = (select coalesce(sum(amount), 0) from public.cash_docs c where c.\"dayId\" = d.id and c.status = 'posted' and c.\"clientRef\" like 'race-c%'))::text from public.cash_days d where d.desk = 'main' and d.day = '$TODAY'")" "true"
chk "5f Moliya menejeri tekshirdi (xesh, jamlar, raqamlar)" "$(call_as R_FM "public.kassa_day_verify('main', '$TODAY', true) -> 'day' ->> 'status'")" "verified"
chk "5g raqamlash yakunda ham uzluksiz" "$(q -c "select app.kassa_gap_check('main', extract(year from app.fin_today())::int)")" "[]"

# ---------- (8) sozlama qatori (fin_org) o'zgarishi va pul yozuvi parallel (state-7) ----------
#   Davr qulfi / ishga tushadigan kun FOR UPDATE bilan o'zgarayotganda yozuvchi qatorni FOR SHARE bilan o'qiydi: o'zgarish tugashini
#   kutadi va YANGI qiymat bilan tekshiradi (avval eski qiymat bilan o'tib ketardi: yopilgan davrga to'lov, KO-1 siz naqd to'lov).
#   A — Direktor tranzaksiyasi (o'zgarish + 2 s kutish + commit), B — 0,5 s keyin boshlangan pul yozuvi.
q >/dev/null <<'SQL'
set session_replication_role = replica;
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values ('r_s1','R-1','Poyga Oquvchi',5,'A','uz','',1,'[]') on conflict (id) do nothing;
SQL
slow_tx(){   # $1 uid, $2 SQL ifoda — tranzaksiya ichida bajariladi, 2 s kutib commit qilinadi; $3 — chiqish fayli
  { as_sess "$1"; echo "begin;"; echo "select 'A|' || ($2)::text;"; echo "select pg_sleep(2);"; echo "commit;"; } | $PSQL_CMD -X -q -At -d "$DB" > "$3" 2>&1
}
PREV_DAY=$(q -c "select app.fin_today() - 1"); NEXT_DAY=$(q -c "select app.fin_today() + 1")
( slow_tx R_DIR "public.fin_period_lock('$PREV_DAY', 'poyga') ->> 'lockedThrough'" "$TMP/8a.A" ) &
sleep 0.5
call_raw R_FM "public.record_manual_payment('man_race8_0001', 'R-1', 100000, 'bank', '$PREV_DAY', '', '', '', null, null) ->> 'ok'" > "$TMP/8a.B"
wait
chk "8a davr qulfi o'rnatilayotganda orqa sana bilan to'lov: qulf tugashini kutdi va yangi qulf bilan rad etildi (yopilgan davrga to'lov tushmadi)" \
    "$(grep -c "^A|$PREV_DAY" "$TMP/8a.A")/$(grep -c 'fin:locked' "$TMP/8a.B")/$(q -c "select count(*) from public.payments where id = 'man_race8_0001'")" "1/1/0"
# Kassani to'xtatish uchun: pul berilmagan so'rovlar bekor qilinadi (Direktor); bugungi kun yopilgan va tekshirilgan (5-bo'lim)
for id in $(q -c "select id from public.cash_docs where desk = 'main' and status in ('draft', 'approved') order by id"); do
  call_as R_DIR "public.kassa_doc_cancel('$id', 'Poyga: to''xtatishdan oldin') ->> 'status'" >/dev/null
done
( slow_tx R_DIR "coalesce(public.fin_org_set('{\"kassaGoLive\":null}') ->> 'kassaGoLive', 'bo''sh')" "$TMP/8b.A" ) &
sleep 0.5
call_raw R_KAS "coalesce(public.record_manual_payment('man_race8_0002', 'R-1', 60000, 'cash', null, '', '', '', null, '{\"fiscalNo\":\"F-R8-2\"}'::jsonb) ->> 'kassa', 'KO-1 siz')" > "$TMP/8b.B"
wait
# (g4r-2: bugun — oxirgi kassa kuni: to'xtatilgan kassada bu sana bilan kassa hujjatisiz naqd to'lov yozilmaydi — yangi qiymat shu; eski
#   qiymat bilan esa kassa hujjatiga urinib, yopilgan kun xatosini olardi — kassa:day_closed)
chk "8b kassa to'xtatilayotganda naqd o'quv to'lovi: to'xtatish tugashini kutdi va yangi holat bilan tekshirildi (to'xtatilgan kassa, oxirgi kassa kuni — kassa:paused_live_day; eskicha «ishlaydi» deb kassa hujjatiga urinmadi)" \
    "$(grep -c '^A|bo.sh' "$TMP/8b.A")/$(grep -c 'kassa:paused_live_day' "$TMP/8b.B")/$(grep -c 'kassa:day_closed' "$TMP/8b.B")/$(q -c "select (\"pausedAt\" is not null)::text from public.cash_desks where id = 'main'")/$(q -c "select count(*) from public.payments where id = 'man_race8_0002'")" "1/1/0/true/0"
# Ertasi kun (test soati — sinov bazasi): to'xtatilgan davr puli — bugungi sana bilan; komissiya sanashi va qayta ishga tushirish — indinga
#   (to'xtatilgan davr yozuvi qayta ishga tushirish kunidan oldin bo'lsin)
DAY2=$(q -c "select app.fin_today() + 2")
q >/dev/null -c "insert into app.fin_clock (id, t) values (1, ('$NEXT_DAY 08:30')::timestamp at time zone 'Asia/Tashkent') on conflict (id) do update set t = excluded.t"
chk "8b2 to'xtatilgan davr sanasi (ertasi kun): naqd o'quv to'lovi KO-1 siz" \
    "$(call_as R_KAS "coalesce(public.record_manual_payment('man_race8_0005', 'R-1', 60000, 'cash', null, '', '', '', null, null) ->> 'kassa', 'KO-1 siz')")" "KO-1 siz"
q >/dev/null -c "insert into app.fin_clock (id, t) values (1, ('$NEXT_DAY 09:00')::timestamp at time zone 'Asia/Tashkent') on conflict (id) do update set t = excluded.t"
X8=$(q -c "select trim_scale(closing) from public.cash_days where desk = 'main' and day = '$TODAY'")
chk "8c qayta ishga tushirish qoldig'i (komissiya: oxirgi kun oxiri + to'xtatilgan davrdagi 60 000) indinga uchun kiritildi" \
    "$(call_as R_DIR "public.kassa_opening_set('{\"amount\":$((X8 + 60000)),\"startDay\":\"$DAY2\"}') ->> 'delta'")" "60000"
# (8c2) qulf tartibi (g4-v1): kassa_opening_set sozlama qatorini kassa qulfi (L4) va kassa qatoridan OLDIN oladi — fin_org shu payt
#   o'zgarayotgan bo'lsa ularni ushlamay kutadi (aksincha: fin_org_set → app.kassa_golive_guard kassa qatorini yangilashda o'zaro qulflanish).
#   A — sozlama qatorini 2 s ushlab turadi; O — 0,5 s keyin qayta sanash; yana 0,5 s keyin tekshiruv: L4 va kassa qatori bo'sh.
T1=$(q -c "select trim_scale(t1) from public.fin_org where id = 'main'")
( slow_tx R_DIR "public.fin_org_set('{\"t1\":$T1}') ->> 't1'" "$TMP/8c2.A" ) &
sleep 0.5
( call_raw R_DIR "public.kassa_opening_set('{\"amount\":$((X8 + 60000)),\"startDay\":\"$DAY2\",\"note\":\"Poyga: qayta sanaldi\"}') ->> 'delta'" > "$TMP/8c2.O" ) &
sleep 0.5
P8=$(q -c "select pg_try_advisory_xact_lock(hashtext('iqror_desk:main'))::text || '/' || (select count(*) from (select 1 from public.cash_desks where id = 'main' for update skip locked) x)")
wait
chk "8c2 qulf tartibi: sozlama qatori o'zgarayotganda qayta sanash kassa qulfini va kassa qatorini ushlamay kutdi, keyin o'tdi" \
    "$P8/$(grep -c '^A|' "$TMP/8c2.A")/$(tail -1 "$TMP/8c2.O")" "true/1/1/60000"
q >/dev/null -c "insert into app.fin_clock (id, t) values (1, ('$DAY2 09:00')::timestamp at time zone 'Asia/Tashkent') on conflict (id) do update set t = excluded.t"
( slow_tx R_DIR "public.fin_org_set('{\"kassaGoLive\":\"$DAY2\"}') ->> 'kassaGoLive'" "$TMP/8d.A" ) &
sleep 0.5
call_raw R_KAS "public.record_manual_payment('man_race8_0003', 'R-1', 40000, 'cash', null, '', '', '', null, '{\"fiscalNo\":\"F-R8-3\"}'::jsonb) #>> '{kassa,day}'" > "$TMP/8d.B"
wait
chk "8d kassa qayta ishga tushirilayotganda naqd o'quv to'lovi: tugashini kutdi va KO-1 bilan yozildi (kun boshi — sanalgan summa); moslik toza" \
    "$(grep -c "^A|$DAY2" "$TMP/8d.A")/$(tail -1 "$TMP/8d.B")/$(q -c "select trim_scale(opening) from public.cash_days where desk = 'main' and day = '$DAY2'")/$(q -c "select app.kassa_reconcile(null, null) ->> 'total'")" \
    "1/$DAY2/$((X8 + 60000))/0"
# (8e) davr surati qulf bilan va undan OLDIN boshlangan orqa sanali to'lov (g4-v1): surat sozlama qatorini mazmundan oldin oladi —
#   to'lov tugashini kutadi va to'lov suratga kiradi (avval mazmun darhol hisoblanib, qulf keyin qo'yilardi: to'lov yopilgan davrda,
#   lekin suratda yo'q). B — 2 s ochiq turadigan to'lov (bugungi kassa kunidan oldingi sana), A — 0,5 s keyin surat + qulf.
( slow_tx R_FM "public.record_manual_payment('man_race8_0004', 'R-1', 70000, 'bank', '$TODAY', '', '', '', null, null) ->> 'ok'" "$TMP/8e.B" ) &
sleep 0.5
call_raw R_DIR "public.fin_snapshot_take('{\"asOf\":\"$TODAY\",\"lock\":true}') ->> 'id'" > "$TMP/8e.A"
wait
SNAP=$(tail -1 "$TMP/8e.A")
chk "8e davr surati (qulf bilan) shu payt yozilayotgan orqa sanali to'lovni kutdi: to'lov qo'llangan, davr yopilgan va to'lov suratda (o'quvchi avansi = hozirgi)" \
    "$(grep -c '^A|true' "$TMP/8e.B")/$(q -c "select (\"lockedThrough\" = '$TODAY')::text from public.fin_org where id = 'main'")/$(q -c "select status from public.payments where id = 'man_race8_0004'")/$(q -c "select (coalesce((select (s ->> 'credit')::numeric from public.fin_snapshots f, jsonb_array_elements(f.payload -> 'students') s where f.id = '$SNAP' and s ->> 'studentId' = 'R-1'), -1) = (select credit from public.student_credit where id = 'R-1'))::text")" \
    "1/true/applied/true"
rm -rf "$TMP"
echo "JAMI: $pass/$((pass+fail)) o'tdi"
[ "$fail" = 0 ]
