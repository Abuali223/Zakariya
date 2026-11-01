#!/usr/bin/env bash
# =====================================================================
# install-sms-cron.sh — avtomatik SMS (sms-worker.cjs auto) uchun BITTA cron qatori: har 15 daqiqada, flock bilan.
#   IDEMPOTENT — qayta ishga tushirish xavfsiz (qator takrorlanmaydi, yangilanadi).
#
#   bash ~/iqror-repo/payments/install-sms-cron.sh            # o'rnatish / yangilash
#   bash ~/iqror-repo/payments/install-sms-cron.sh --remove   # olib tashlash
#
#   XAVFSIZ: «Xabarnomalar» (admin panel) da tur yoqilmaguncha hech narsa yubormaydi; sozlamani o'qiy olmasa ham — hech narsa
#   (log + chiqish kodi 3). Qachon, qaysi kunlari, qaysi matn — Direktor sozlamasidan (notify_settings).
#   Qayerdan ishlaydi: iqror-pay xizmatining kod papkasi (deploy kodni shu yerga ko'chiradi; config.json va node_modules shu
#   yerda); xizmat bo'lmasa — shu skript turgan payments/ papkasi. Kim nomidan: o'sha xizmat foydalanuvchisi (config.json faqat
#   unga o'qilishi mumkin). Eski «sms-worker.cjs new/debt/both» qatorlari IZOHGA olinadi — ular Sozlamalarga bo'ysunmaydi
#   (o'chirilgan turni ham yuborardi). Boshqa cron qatorlari o'zgarmaydi.
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MARK='# iqror-sms-auto'
LOG=/var/log/iqror-sms.log
SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo

svc_dir=""; RUNAS=""; NODE=""
if systemctl cat iqror-pay >/dev/null 2>&1; then
  wd=$(systemctl show -p WorkingDirectory --value iqror-pay 2>/dev/null || true); wd=${wd#!}
  for d in "$wd" "$wd/payments"; do
    [ -n "$d" ] && $SUDO test -f "$d/sms-worker.cjs" && { svc_dir="$d"; break; }
  done
  RUNAS=$(systemctl show -p User --value iqror-pay 2>/dev/null || true)
  # xizmat ishlatadigan node (cron'da PATH faqat /usr/bin:/bin — to'liq yo'l kerak)
  for a in $(systemctl show -p ExecStart --value iqror-pay 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -1); do
    case "$a" in */node|*/nodejs) NODE="$a";; esac
  done
fi
DIR=${svc_dir:-$HERE}
RUNAS=${RUNAS:-$(id -un)}
[ -n "$NODE" ] || NODE=$(command -v node || true)
[ -n "$NODE" ] || { echo "❌ node topilmadi (command -v node)."; exit 1; }

CUR="$($SUDO crontab -u "$RUNAS" -l 2>/dev/null || true)"
# Bizning qatorni olib tashlaymiz; eski (auto bo'lmagan) sms-worker qatorlarini izohga olamiz.
NEW="$(printf '%s\n' "$CUR" | { grep -av -- "$MARK" || true; } | awk '
  /^[[:space:]]*#/ { print; next }
  /sms-worker\.cjs/ && !/sms-worker\.cjs[[:space:]]+auto/ { print "# (eski — install-sms-cron.sh: auto rejimi bilan almashtirildi) " $0; next }
  { print }' | sed '/^$/d')"

if [ "${1:-}" = "--remove" ]; then
  printf '%s\n' "$NEW" | $SUDO crontab -u "$RUNAS" -
  echo "✓ Avtomatik SMS cron'i olib tashlandi ($RUNAS)."; exit 0
fi

$SUDO test -f "$DIR/config.json" || { echo "❌ $DIR/config.json yo'q — sms-worker Eskiz ulanishini shu fayldan oladi (payments/config.example.json → «sms» bloki)."; exit 1; }
$SUDO touch "$LOG"; $SUDO chown "$RUNAS": "$LOG" 2>/dev/null || true
LINE="*/15 * * * * cd $DIR && flock -n /tmp/iqror-sms.lock $NODE sms-worker.cjs auto >> $LOG 2>&1 $MARK"
printf '%s\n%s\n' "$NEW" "$LINE" | sed '/^$/d' | $SUDO crontab -u "$RUNAS" -
echo "✓ Avtomatik SMS cron'i o'rnatildi ($RUNAS):"
echo "    $LINE"
old=$(( $(printf '%s\n' "$NEW" | grep -c 'eski — install-sms-cron.sh' || true) - $(printf '%s\n' "$CUR" | grep -c 'eski — install-sms-cron.sh' || true) ))
[ "$old" -gt 0 ] && echo "    ℹ️ $old ta eski sms-worker qatori izohga olindi (Sozlamalarga bo'ysunmasdi)."
echo "    Sinov (hech narsa yubormaydi): cd $DIR && sudo -u $RUNAS $NODE sms-worker.cjs auto --dry"
echo "    Jurnal: tail -f $LOG   ·   Yoqish/o'chirish, kunlar, soatlar, matn — admin panel → «Xabarnomalar»."
