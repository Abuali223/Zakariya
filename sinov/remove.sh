#!/usr/bin/env bash
# =====================================================================
# IQROR — SINOV NUSXASI — O'CHIRISH.
#   Ishlatish (sudo'SIZ):
#     bash ~/iqror-repo/sinov/remove.sh --dry-run   # nima o'chirilishini ko'rsatadi
#     bash ~/iqror-repo/sinov/remove.sh             # nginx bloki, firewall qoidasi, xizmat va konteyner o'chiriladi;
#                                                   #   baza va /opt/iqror-sinov (parollar) QOLADI — qayta o'rnatish oson
#     bash ~/iqror-repo/sinov/remove.sh --yes       # yuqoridagilar + «iqror_sinov» bazasi va /opt/iqror-sinov ham o'chiriladi
#
#   Faqat stend obyektlariga tegadi (nomlari qat'iy): nginx fayli «iqror-sinov», xizmat «iqror-sinov», konteyner
#   «iqror-sinov-rest», baza «iqror_sinov», papka /opt/iqror-sinov. Jonli tizimga tegmaydi.
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-preflight.sh
. "$HERE/lib-preflight.sh"
usage(){ echo "Ishlatish: bash remove.sh [--yes] [--dry-run]"; usage_common; }
parse_common "$@"
conf_load
check_numbers
if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then echo "❌ Skriptni sudo'SIZ ishga tushiring: bash $0"; exit 1; fi

say "IQROR — SINOV NUSXASI: o'chirish$([ "$DRY" = 1 ] && echo " (DRY-RUN)")$([ "$YES" = 1 ] && echo " — baza va papka bilan birga")"

# ---- 1) nginx bloki (avval — tashqi kirish yopiladi)
step "nginx: stend bloki"
if [ -e "$NGX_AVAIL" ] || [ -L "$NGX_ENABLED" ] || [ -e "$NGX_CONFD" ]; then
  if ! dry "o'chiriladi: $NGX_ENABLED, $NGX_AVAIL, $NGX_CONFD; sudo nginx -t; sudo systemctl reload nginx"; then
    nginx_remove_files
    if as_root nginx -t >/dev/null 2>&1; then as_root systemctl reload nginx && ok "stend bloki olib tashlandi, nginx qayta yuklandi"
    else warn "DIQQAT: nginx -t xato beryapti (stend fayllari olib tashlangan) — tekshiring: sudo nginx -t"; fi
  fi
else note "stend nginx fayli yo'q"; fi

# ---- 2) firewall qoidasi
step "Firewall (ufw)"
if have ufw && as_root ufw status 2>/dev/null | sed -n 1p | grep_q -v inactive; then
  if as_root ufw status 2>/dev/null | grep_q -E "^$PUBLIC_PORT/tcp[[:space:]]"; then
    dry "sudo ufw delete allow $PUBLIC_PORT/tcp" || { as_root ufw delete allow "$PUBLIC_PORT/tcp" >/dev/null && ok "ufw: $PUBLIC_PORT/tcp qoidasi o'chirildi"; }
  else note "ufw'da $PUBLIC_PORT/tcp qoidasi yo'q"; fi
else note "ufw yo'q yoki o'chiq (hosting panelidagi tashqi firewall'da $PUBLIC_PORT-portni o'zingiz yoping)"; fi

# ---- 3) systemd xizmati
step "systemd xizmati: $SINOV_UNIT"
if have systemctl && { [ -f "$UNIT_FILE" ] || systemctl cat "$SINOV_UNIT" >/dev/null 2>&1; }; then
  if ! dry "systemctl disable --now $SINOV_UNIT; $UNIT_FILE o'chiriladi; daemon-reload"; then
    as_root systemctl disable --now "$SINOV_UNIT" >/dev/null 2>&1 || true
    as_root rm -f "$UNIT_FILE"
    as_root systemctl daemon-reload || true
    ok "xizmat to'xtatildi va o'chirildi"
  fi
else note "xizmat o'rnatilmagan"; fi

# ---- 4) PostgREST konteyneri
step "Konteyner: $SINOV_REST_CONT"
if have docker && as_root docker ps -a --format '{{.Names}}' 2>/dev/null | grep_q -x "$SINOV_REST_CONT"; then
  lbl=$(as_root docker inspect -f "{{index .Config.Labels \"$SINOV_LABEL\"}}" "$SINOV_REST_CONT" 2>/dev/null || true)
  if [ "$lbl" != 1 ]; then warn "«$SINOV_REST_CONT» konteynerida stend belgisi yo'q — tegilmadi (tekshiring: sudo docker inspect $SINOV_REST_CONT)"
  else dry "docker rm -f $SINOV_REST_CONT" || { as_root docker rm -f "$SINOV_REST_CONT" >/dev/null && ok "konteyner o'chirildi"; }; fi
else note "konteyner yo'q"; fi

# ---- 5) baza va papka — faqat --yes bilan
if [ "$YES" = 1 ]; then
  step "Baza: $SINOV_DB"
  if { [ -n "${PSQL_CMD:-}" ] || { have docker && as_root docker ps --format '{{.Names}}' 2>/dev/null | grep_q -x "$DB_CONT"; }; } && db_exists; then db_drop
  else note "«$SINOV_DB» bazasi yo'q (yoki baza konteyneri «$DB_CONT» ishlamayapti)"; fi
  step "Papka: $STAND_DIR"
  [ -n "$STAND_DIR" ] && [ "$STAND_DIR" = "$ROOTFS/opt/iqror-sinov" ] || die "ICHKI XATO: papka yo'li kutilmagan — o'chirilmadi."
  if [ -d "$STAND_DIR" ]; then dry "rm -rf $STAND_DIR (sahifalar nusxasi, sirlar, sinov hisoblari)" || { as_root rm -rf "$STAND_DIR"; ok "papka o'chirildi"; }
  else note "papka yo'q"; fi
  [ "$DRY" = 1 ] && { say ""; say "✅ DRY-RUN tugadi: hech narsa o'chirilmadi."; exit 0; }
  say ""; say "✅ Sinov nusxasi to'liq o'chirildi (baza va parollar bilan birga). Jonli tizimga tegilmadi."
else
  [ "$DRY" = 1 ] && { say ""; say "✅ DRY-RUN tugadi: hech narsa o'chirilmadi."; exit 0; }
  say ""; say "✅ Sinov nusxasi o'chirildi (tashqaridan ochilmaydi, xizmat va konteyner yo'q). Jonli tizimga tegilmadi."
  say "   QOLDI: «$SINOV_DB» bazasi va ${STAND_DIR#"$ROOTFS"} (sinov hisoblari, parollar) — qayta o'rnatsangiz o'sha parollar ishlaydi."
  say "   Ularni ham o'chirish: bash $0 --yes"
fi
