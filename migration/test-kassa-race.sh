#!/usr/bin/env bash
# =====================================================================
# test-kassa-race.sh — KASSA PARALLEL (poyga) sinovi (moliya rejasi F1.3): raqamlash va kassa qulfi.
#   (1) 8 parallel seans × 200 kirim orderi, har 10-chisi ROLLBACK: raqamlar 1…N uzluksiz (bo'shliq yo'q, takror yo'q),
#       bekor qilingan tranzaksiya raqam «yemaydi», deadlock yo'q, qoldiq = hujjatlar yig'indisi;
#   (2) bir xil kalit (clientRef) 8 seansdan — bitta hujjat, qolganlari «takror»;
#   (3) bitta qoldiqqa ikki katta chiqim parallel — faqat BITTASI o'tadi; 8 ta chiqim — qoldiq hech qachon manfiy emas;
#   (4) ikki tasdiq (2-ro'yxat va Direktor) parallel — hujjat «tasdiqlangan» bo'ladi, hech biri yo'qolmaydi;
#   (5) kirimlar davom etayotganda kun yopiladi — yopilgandan keyingi kirimlar rad, kun jami = hujjatlar, tekshiruv o'tadi.
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
update public.fin_org set t1 = 100000000000, l1 = 0 where id = 'main';
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
rm -rf "$TMP"
echo "JAMI: $pass/$((pass+fail)) o'tdi"
[ "$fail" = 0 ]
