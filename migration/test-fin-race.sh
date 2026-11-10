#!/usr/bin/env bash
# =====================================================================
# test-fin-race.sh — record_manual_payment PARALLEL (poyga) sinovi (moliya rejasi F0.11 / F0.15).
#   (1) bir xil payId 8 ta parallel seansdan (ikkinchi tab / qayta urinish / oflayn navbat) — pul FAQAT bir marta qo'llanadi;
#   (2) bitta o'quvchiga 8 ta har xil to'lov parallel — hammasi qo'llanadi, yo'qolmaydi, deadlock yo'q (advisory lock);
#   (3) payments: yetim «pending» qator qolmaydi.
#   FAQAT bo'sh sinov bazasida (kanonik zanjir qurilgan, o'quvchilar jadvali bo'sh). Baza o'zgaradi — tashlab yuboriladigan baza.
#   Ishlatish:  PSQL_CMD="psql -h <host> -U postgres" bash migration/test-fin-race.sh <baza>
#   Natija: har tekshiruv PASS/FAIL; xato bo'lsa chiqish kodi 1.
# =====================================================================
set -uo pipefail
DB="${1:?baza nomi kerak}"
PSQL_CMD="${PSQL_CMD:-psql}"
q(){ $PSQL_CMD -X -q -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
pass=0; fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1  (olindi: $2 ; kutilgan: $3)"; fi; }

[ "$(q -c "select count(*) from public.students")" = "0" ] || { echo "test-fin-race.sh: o'quvchilar jadvali bo'sh emas — faqat bo'sh sinov bazasida"; exit 1; }
q >/dev/null <<'SQL'
set session_replication_role = replica;
insert into public.users (id, email, role, status, "extraRoles") values ('R_KAS','rk@x','kassir','active','[]'), ('R_FM','rf@x','finance_mgr','active','[]');
insert into public.students (id, "studentId", name, grade, "classLetter", lang, "payStatus", "order", pauses) values
  ('rs1','R-1','Poyga A',5,'A','uz','',1,'[]'), ('rs2','R-2','Poyga B',5,'A','uz','',2,'[]');
insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values
  ('ri1','R-1','Poyga A','2026-09',1000000,0,'pending'), ('ri2','R-1','Poyga A','2026-10',1000000,0,'pending'),
  ('ri3','R-1','Poyga A','2026-11',1000000,0,'pending'), ('ri4','R-2','Poyga B','2026-11',5000000,0,'pending');
SQL

call_as(){   # $1 uid, $2 SQL ifoda
  $PSQL_CMD -X -q -At -d "$DB" -c "begin; select set_config('request.jwt.claims', json_build_object('sub','$1','role','authenticated')::text, true); set local role authenticated; select ($2)::text; commit;" 2>&1 | grep -v '^\(BEGIN\|SET\|COMMIT\)$' | tail -1
}

# (1) bir xil payId — 8 parallel
TMP=$(mktemp -d)
for i in $(seq 1 8); do
  ( call_as R_KAS "public.record_manual_payment('man_race_same_00001','R-1',1500000,'cash',null,'poyga','','',null) ->> 'dup'" > "$TMP/same.$i" ) &
done
wait
dupf=$(cat "$TMP"/same.* | grep -c '^false$'); dupt=$(cat "$TMP"/same.* | grep -c '^true$'); errs=$(cat "$TMP"/same.* | grep -vc '^\(true\|false\)$')
chk "1a bir xil payId: faqat bitta qo'llash (dup=false)" "$dupf" "1"
chk "1b qolgan 7 tasi dup=true, xato yo'q" "$dupt/$errs" "7/0"
chk "1c payments qatori bitta, applied" "$(q -c "select count(*) || '/' || min(status) from public.payments where id = 'man_race_same_00001'")" "1/applied"
chk "1d applied_payments posboni bitta" "$(q -c "select count(*) from public.applied_payments where id = 'man_race_same_00001'")" "1"
chk "1e fakturalarga jami 1 500 000 qo'llangan" "$(q -c "select sum(\"paidAmount\")::bigint from public.invoices where \"studentId\" = 'R-1'")" "1500000"

# (2) bitta o'quvchiga 8 ta har xil to'lov parallel
for i in $(seq 1 8); do
  ( call_as R_KAS "public.record_manual_payment('man_race_diff_0000$i','R-2',100000,'cash',null,'','','',null) ->> 'ok'" > "$TMP/diff.$i" ) &
done
wait
chk "2a 8 ta to'lov — hammasi ok" "$(cat "$TMP"/diff.* | grep -c '^true$')" "8"
chk "2b R-2 fakturasiga jami 800 000" "$(q -c "select \"paidAmount\"::bigint from public.invoices where id = 'ri4'")" "800000"
chk "2c payments: 8 ta applied" "$(q -c "select count(*) from public.payments where id like 'man_race_diff_%' and status = 'applied'")" "8"

# (3) yetim «pending» yo'q
chk "3 yetim pending qator yo'q" "$(q -c "select count(*) from public.payments where id like 'man_race_%' and status = 'pending'")" "0"
rm -rf "$TMP"
echo "JAMI: $pass/$((pass+fail)) o'tdi"
[ "$fail" = 0 ]
