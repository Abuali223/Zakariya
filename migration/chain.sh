#!/usr/bin/env bash
# =====================================================================
# Kanonik migratsiya zanjirini (run-all.sql'dagi \ir qatorlari TARTIBIDA) BITTA tranzaksiyali SQL
#   oqimi sifatida stdout'ga chiqaradi. Sabab: `docker exec -i ... psql < run-all.sql` ISHLAMAYDI —
#   \ir konteyner ichida yo'l qidiradi (fayllar u yerda yo'q). Shu sabab fayllar shu yerda ulanadi.
#
#   Ishlatish:  bash ~/iqror-repo/migration/chain.sh | sudo docker exec -i supabase-db psql -U postgres -d postgres -q
#   (deploy.sh va verify-db.sh ham shuni ishlatadi.)
#
#   Xato bo'lsa (ON_ERROR_STOP) — tranzaksiya BEKOR qilinadi, baza O'ZGARMAYDI; chiqishdagi oxirgi
#   "-> fayl.sql" qatori xato qaysi faylda ekanini ko'rsatadi.
#   --no-lock-timeout : lock_timeout qo'ymaslik (vaqtinchalik bazada — verify-db.sh).
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "\\set ON_ERROR_STOP on"
# Jonli bazada ilova so'rovlari qulfini uzoq kutib qolmasin — tez xato beradi (qayta urinish mumkin).
[ "${1:-}" = "--no-lock-timeout" ] || echo "set lock_timeout = '20s';"
echo "begin;"
for f in $(grep -oE '^\\ir [A-Za-z0-9._-]+\.sql' "$HERE/run-all.sql" | awk '{print $2}'); do
  [ -f "$HERE/$f" ] || { echo "chain.sh: '$f' topilmadi (run-all.sql'da bor, papkada yo'q)" >&2; exit 1; }
  echo "\\echo '-> $f'"
  cat "$HERE/$f"; echo
done
echo "commit;"
