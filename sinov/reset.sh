#!/usr/bin/env bash
# =====================================================================
# IQROR — SINOV NUSXASI — YANGIDAN BOSHLASH (takroriy mashg'ulot uchun).
#   Ishlatish (sudo'SIZ):  bash ~/iqror-repo/sinov/reset.sh [--yes] [--dry-run]
#
#   «iqror_sinov» bazasini O'CHIRIB, qaytadan quradi (hozir ko'rsatilayotgan versiya zanjiri bilan) va yangi sintetik
#   ma'lumot yuklaydi. Stendda kiritilgan barcha mashq yozuvlari o'chadi. Sinov hisoblari va parollari SAQLANADI.
#   Faqat «iqror_sinov» bazasiga tegadi — jonli bazaga emas (nom skriptda qat'iy tekshiriladi).
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-preflight.sh
. "$HERE/lib-preflight.sh"
usage(){ echo "Ishlatish: bash reset.sh [--yes] [--dry-run]"; usage_common; }
parse_common "$@"
[ -r "$CONF_FILE" ] || { echo "❌ Sinov nusxasi o'rnatilmagan ($CONF_FILE yo'q). Avval: bash $HERE/install.sh"; exit 1; }
conf_load
check_numbers

say "IQROR — SINOV NUSXASI: yangidan boshlash$([ "$DRY" = 1 ] && echo " (DRY-RUN)")"
[ -f "$REL_DIR/migration/chain.sh" ] && [ -f "$APP_DIR/seed.cjs" ] || die "Stend nusxasi to'liq emas ($REL_DIR) — avval: bash $HERE/install.sh"
[ -n "$NODE_BIN" ] && [ -x "$NODE_BIN" ] || die "Node.js topilmadi (sozlamada: «${NODE_BIN:-yo‘q}») — bash $HERE/install.sh ni qayta ishga tushiring."
pf_db
say "    versiya: $(sed -n 3p "$REL_DIR/REF" 2>/dev/null || echo '?')"
[ "$DRY" = 1 ] || confirm "«$SINOV_DB» bazasidagi BARCHA mashq ma'lumotlari o'chiriladi va yangi sintetik ma'lumot yuklanadi (parollar saqlanadi). Davom etilsinmi?"

has_cont=0
if have docker && as_root docker ps -a --format '{{.Names}}' 2>/dev/null | grep_q -x "$SINOV_REST_CONT"; then has_cont=1; fi
if [ "$has_cont" = 1 ]; then
  step "Stend PostgREST'i vaqtincha to'xtatiladi (baza bo'shashi uchun)"
  dry "docker stop $SINOV_REST_CONT" || { as_root docker stop "$SINOV_REST_CONT" >/dev/null; ok "to'xtatildi"; }
fi
# Baza qayta qurilmasa ham PostgREST qayta ishga tushsin (stend «yarim» holatda qolmasin).
restart_rest(){ if [ "$has_cont" = 1 ] && [ "$DRY" != 1 ]; then as_root docker start "$SINOV_REST_CONT" >/dev/null 2>&1 || true; fi; }
trap restart_rest EXIT
step_db reset
trap - EXIT
if [ "$has_cont" = 1 ]; then
  step "Stend PostgREST'i qayta ishga tushiriladi"
  dry "docker start $SINOV_REST_CONT" || { as_root docker start "$SINOV_REST_CONT" >/dev/null; rest_wait || die "Stend PostgREST'i javob bermayapti (127.0.0.1:$REST_PORT)." "Jurnal: sudo docker logs --tail 20 $SINOV_REST_CONT"; ok "PostgREST ishlayapti"; }
fi
if have systemctl && [ -f "$UNIT_FILE" ]; then unit_restart; fi
HEALTH_BAD=0
step_health
[ "$DRY" = 1 ] && { say ""; say "✅ DRY-RUN tugadi: hech narsa o'zgartirilmadi."; exit 0; }
say ""
if [ "$HEALTH_BAD" = 0 ]; then say "✅ Sinov nusxasi yangidan boshlandi: toza sintetik ma'lumot yuklandi (hisoblar va parollar avvalgidek)."
  say "   Ochiq oynalarni yangilang (Ctrl+Shift+R). Parollar: sudo cat ${ACCOUNTS_TXT#"$ROOTFS"}"
else say "⚠️ Baza qayta qurildi, lekin tekshiruvda ⚠️ qatorlar bor — yuqoriga qarang."; exit 2; fi
