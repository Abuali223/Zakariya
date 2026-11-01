#!/usr/bin/env bash
# =====================================================================
# install-tg-cron.sh — Direktorga kunlik hisobot (tg-daily.cjs, Telegram) uchun BITTA cron qatori: har 15 daqiqada, flock bilan.
#   IDEMPOTENT — qayta ishga tushirish xavfsiz (qator takrorlanmaydi, yangilanadi).
#
#   bash ~/iqror-repo/auth/install-tg-cron.sh            # o'rnatish / yangilash
#   bash ~/iqror-repo/auth/install-tg-cron.sh --remove   # olib tashlash
#
#   XAVFSIZ: «Xabarnomalar» → «Kunlik hisobot» yoqilmaguncha hech narsa yubormaydi; sozlamani o'qiy olmasa ham — hech narsa
#   (log + chiqish kodi 3). Qaysi kunlari va soat nechadan — Direktor sozlamasidan (notify_settings 'daily_report'); bir kunda bir marta.
#   Qayerdan ishlaydi: iqror-auth xizmatining kod papkasi (config.json — Telegram kaliti va baza ulanishi shu yerda); xizmat
#   bo'lmasa — shu skript turgan auth/ papkasi. Kim nomidan: o'sha xizmat foydalanuvchisi. Boshqa cron qatorlari o'zgarmaydi.
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MARK='# iqror-tg-daily'
LOG=/var/log/iqror-tg-daily.log
SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo

svc_dir=""; RUNAS=""; NODE=""
if systemctl cat iqror-auth >/dev/null 2>&1; then
  wd=$(systemctl show -p WorkingDirectory --value iqror-auth 2>/dev/null || true); wd=${wd#!}
  for d in "$wd" "$wd/auth"; do
    [ -n "$d" ] && $SUDO test -f "$d/tg-daily.cjs" && { svc_dir="$d"; break; }
  done
  RUNAS=$(systemctl show -p User --value iqror-auth 2>/dev/null || true)
  # xizmat ishlatadigan node (cron'da PATH faqat /usr/bin:/bin — to'liq yo'l kerak)
  for a in $(systemctl show -p ExecStart --value iqror-auth 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -1); do
    case "$a" in */node|*/nodejs) NODE="$a";; esac
  done
fi
DIR=${svc_dir:-$HERE}
RUNAS=${RUNAS:-$(id -un)}
[ -n "$NODE" ] || NODE=$(command -v node || true)
[ -n "$NODE" ] || { echo "❌ node topilmadi (command -v node)."; exit 1; }

CUR="$($SUDO crontab -u "$RUNAS" -l 2>/dev/null || true)"
# Bizning (avvalgi) qatorni olib tashlaymiz; boshqa qatorlar o'zgarmaydi.
NEW="$(printf '%s\n' "$CUR" | { grep -av -- "$MARK" || true; } | sed '/^$/d')"

if [ "${1:-}" = "--remove" ]; then
  printf '%s\n' "$NEW" | $SUDO crontab -u "$RUNAS" -
  echo "✓ Kunlik hisobot cron'i olib tashlandi ($RUNAS)."; exit 0
fi

$SUDO test -f "$DIR/config.json" || { echo "❌ $DIR/config.json yo'q — tg-daily Telegram kalitini va baza ulanishini shu fayldan oladi (auth/config.example.json → «telegram» bloki)."; exit 1; }
$SUDO touch "$LOG"; $SUDO chown "$RUNAS": "$LOG" 2>/dev/null || true
LINE="*/15 * * * * cd $DIR && flock -n /tmp/iqror-tg-daily.lock $NODE tg-daily.cjs >> $LOG 2>&1 $MARK"
printf '%s\n%s\n' "$NEW" "$LINE" | sed '/^$/d' | $SUDO crontab -u "$RUNAS" -
echo "✓ Kunlik hisobot cron'i o'rnatildi ($RUNAS):"
echo "    $LINE"
echo "    Sinov (hech narsa yubormaydi): cd $DIR && sudo -u $RUNAS $NODE tg-daily.cjs --dry"
echo "    Jurnal: tail -f $LOG   ·   Yoqish, kunlar, soat — admin panel → «Xabarnomalar» → «Kunlik hisobot»."
