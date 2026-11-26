#!/usr/bin/env bash
# =====================================================================
# «Kassa» brauzer ssenariylari — hammasi ketma-ket, har biri YANGI stend bilan (LOKAL; ishga-tushirish.md §3.2, 3-qadam).
#   bash run-all.sh                     — to'liq to'plam: kassa 1–19 + to'lov va eski oqimlar (dev va prod zanjir) + arxiv, sotuvchi, dizayn
#   bash run-all.sh k5 k3 pay:dev ui     — tanlanganlari (kN, pay:dev|prod, legacy:dev|prod, ar — o'quvchilar arxivi, sl — «Sotuvchi» roli,
#                                          ui — yagona dizayn). Dizayn bitta — yangi (v2); eski dizayn (v1) 2026-11-24 da olib tashlangan,
#                                          «kN:v2» kabi eski yozuv ham qabul qilinadi, «:v1» — rad.
#   Natija: local/out/<vaqt>/summary.txt (har qator: rc, JAMI, fail soni) va har ssenariy chiqishi; oxirida xulosa.
#   Kutilgan sonlar — README.md («Kutilgan natija»). Hamma qatorda fail=0 va rc=0 bo'lishi kerak.
# =====================================================================
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"
OUT="$E2E_LOCAL/out/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"; SUM="$OUT/summary.txt"; : > "$SUM"
export E2E_OUT="$OUT/shots"
fresh(){ timeout 600 bash "$E2E_DIR/stand.sh" reset "$1" > "$OUT/reset.out" 2>&1 < /dev/null || { echo "$2: STEND QURILMADI (reset.out)" >> "$SUM"; return 1; }; }
one(){
  local tag=$1 file=$2 arg=${3:-}
  timeout 600 node "$E2E_DIR/scenarios/$file" $arg > "$OUT/$tag.out" 2>&1 < /dev/null; local rc=$?
  echo "$tag: rc=$rc | $(grep -E 'JAMI' "$OUT/$tag.out" | tail -1) | fail=$(grep -cE '^FAIL|XATO' "$OUT/$tag.out")" >> "$SUM"
}
run(){   # kN | pay:dev|prod | legacy:dev|prod | ar | sl | ui
  local spec=$1 name=${1%%:*} var=${1##*:}
  [ "$var" = "$spec" ] && var=v2   # variant yozilmagan — yagona dizayn
  case "$name:$var" in *:v1) echo "$spec: eski dizayn (v1) olib tashlangan — faqat v2" >> "$SUM"; return ;; esac
  case "$name" in
    k1) fresh dev "$spec" && one "$name.$var" e2e-kassa.cjs "$var" ;;
    k[0-9]|k1[0-9]) fresh dev "$spec" && one "$name.$var" "e2e-kassa${name#k}.cjs" "$var" ;;
    pay|legacy) fresh "$var" "$spec" && one "$name.$var" "e2e-$name.cjs" ;;
    ar) fresh dev "$spec" && one "$name.$var" e2e-arxiv.cjs "$var" ;;   # o'quvchilar arxivi (egasi 2026-11-18)
    sl) fresh dev "$spec" && one "$name.$var" e2e-sales.cjs "$var" ;;   # «Sotuvchi» roli (egasi 2026-11-19)
    ui) fresh dev "$spec" && one "$name" e2e-ui.cjs ;;   # yagona dizayn (egasi 2026-11-24)
    *) echo "$spec: noma'lum ssenariy" >> "$SUM" ;;
  esac
}
if [ $# -gt 0 ]; then SPECS=("$@"); else
  SPECS=(); for n in 5 3 1 2 4 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do SPECS+=("k$n"); done
  SPECS+=(pay:dev legacy:dev pay:prod legacy:prod ar sl ui)
fi
for s in "${SPECS[@]}"; do run "$s"; done
bash "$E2E_DIR/stand.sh" down >/dev/null 2>&1 || true
cat "$SUM"
bad=$(grep -cvE 'rc=0 \| .*JAMI.* \| fail=0$' "$SUM" || true)
echo "----"; [ "$bad" = 0 ] && echo "NATIJA: ${#SPECS[@]} ta o'tish — hammasi o'tdi ($OUT)" || echo "NATIJA: $bad ta qatorda muammo — $OUT"
[ "$bad" = 0 ]
