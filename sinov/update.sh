#!/usr/bin/env bash
# =====================================================================
# IQROR — SINOV NUSXASI — YANGILASH (har oddiy deploy'dan keyin).
#   Ishlatish (sudo'SIZ):  bash ~/iqror-repo/sinov/update.sh [--dry-run] [--ref REF] [--dev|--no-dev]
#
#   Nima qiladi: yangi versiya sahifalari va migratsiya zanjiri nusxasini oladi -> zanjirni «iqror_sinov» bazasiga qo'llaydi
#   (bitta tranzaksiya; xato bo'lsa stend eski holatida qoladi) -> sahifalarni almashtiradi -> PostgREST sxema keshini
#   yangilaydi -> Node serverni qayta ishga tushiradi -> tekshiradi. Stenddagi mashq ma'lumotlari va parollar SAQLANADI.
#   Jonli tizimga tegmaydi.
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-preflight.sh
. "$HERE/lib-preflight.sh"
usage(){ echo "Ishlatish: bash update.sh [bayroqlar]"; usage_common; }
parse_common "$@"
[ -r "$CONF_FILE" ] || { echo "❌ Sinov nusxasi o'rnatilmagan ($CONF_FILE yo'q). Avval: bash $HERE/install.sh"; exit 1; }
conf_load
check_numbers

say "IQROR — SINOV NUSXASI: yangilash$([ "$DRY" = 1 ] && echo " (DRY-RUN)")"
pf_basics
pf_node
pf_db
[ "$DB_STATE" = bor ] || die "«$SINOV_DB» bazasi yo'q — avval install.sh ni ishga tushiring."
if [ "$TEST_MODE" != 1 ] || have docker; then
  as_root docker ps -a --format '{{.Names}}' 2>/dev/null | grep_q -x "$SINOV_REST_CONT" || die "«$SINOV_REST_CONT» konteyneri yo'q — avval install.sh ni ishga tushiring."
fi
# Stend skriptlari ko'rsatiladigan versiyadan eski bo'lsa — ogohlantirish (server.cjs / seed.cjs shu papkadan olinadi).
rel=$(git -C "$REPO" rev-parse --show-prefix 2>/dev/null || true)
if ! git -C "$HERE" diff --quiet "$REL_SHA" -- . 2>/dev/null; then
  warn "stend skriptlari ($HERE) «$REL_REF» versiyasidagidan farq qiladi — avval yangilang: cd $REPO && git checkout $REL_REF -- ${rel:-<stend papkasi>}"
fi

step_release
step_db update
step_release_swap
step_secrets
if [ "${NEW_ACCOUNTS:-0}" -gt 0 ] && [ "$DRY" != 1 ]; then
  warn "yangi sinov hisobi qo'shildi ($NEW_ACCOUNTS ta) — u bazada «bash reset.sh» dan keyin paydo bo'ladi. Parollar: sudo cat ${ACCOUNTS_TXT#"$ROOTFS"}"
fi
rest_reload
unit_restart
HEALTH_BAD=0
step_health
[ "$DRY" = 1 ] && { say ""; say "✅ DRY-RUN tugadi: hech narsa o'zgartirilmadi."; exit 0; }
say ""
if [ "$HEALTH_BAD" = 0 ]; then say "✅ Sinov nusxasi yangilandi: $REL_REF = $REL_DESC"; say "   https://${PUBLIC_HOST:-<domen>}:$PUBLIC_PORT/admin.html (ochiq oynalarni yangilang: Ctrl+Shift+R)"
else say "⚠️ Yangilandi, lekin tekshiruvda ⚠️ qatorlar bor — yuqoriga qarang."; exit 2; fi
