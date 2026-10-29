#!/usr/bin/env bash
# =====================================================================
# backup.sh — zaxira: PostgreSQL (maktab ma'lumotlari: public + app sxemalari) + Supabase Storage fayllari.
#   Bir martalik (zaxira ~/iqror-backups ga):   bash ~/iqror-repo/migration/deploy/backup.sh
#   Har kuni (root crontab: sudo crontab -e; zaxira /opt/iqror/backups ga; server UTC'da — 22:30 = Toshkent 03:30):
#     30 22 * * *  bash /home/ubuntu/iqror-repo/migration/deploy/backup.sh >> /var/log/iqror-backup.log 2>&1
#   Baza Supabase docker konteyneri ichidagi pg_dump bilan olinadi (DB_CONT, standart supabase-db) — parol
#   kerak emas. Tashqi baza bo'lsa: PGURL=postgresql://... (unda host'da pg_dump bo'lishi kerak).
#   Zaxira fayllari faqat egasiga o'qiladi (600): ichida shaxsiy ma'lumot (JSHSHIR, telefon, manzil) bor.
#   Fayl to'liq yozilmasa (dump uzilsa) — saqlanmaydi, xato bilan tugaydi.
#   Zaxirani BOSHQA joyga (kompyuteringiz / boshqa disk / obyekt-xotira) ham ko'chiring!
# =====================================================================
set -euo pipefail
umask 077
# cron'da PATH faqat /usr/bin:/bin — docker (snap'da /snap/bin) va boshqa buyruqlar shunda ham topilsin (oxiriga: mavjud tartib o'zgarmaydi).
export PATH="${PATH:+$PATH:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

if [ "$(id -u)" = 0 ]; then BACKUP_DIR="${BACKUP_DIR:-/opt/iqror/backups}"; else BACKUP_DIR="${BACKUP_DIR:-$HOME/iqror-backups}"; fi
DB_CONT="${DB_CONT:-supabase-db}"
PGURL="${PGURL:-}"
STORAGE_VOL="${STORAGE_VOL:-/opt/iqror/supabase/docker/volumes/storage}"  # Supabase storage hajmi (bo'lmasa o'tkaziladi)
KEEP_DAYS="${KEEP_DAYS:-14}"
DOCKER="docker"; if [ "$(id -u)" != 0 ] && ! docker ps >/dev/null 2>&1; then DOCKER="sudo docker"; fi

STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"; [ -L "$BACKUP_DIR" ] || chmod 700 "$BACKUP_DIR" 2>/dev/null || true   # symlink bo'lsa nishoni o'zgartirilmaydi
# BIR VAQTDA FAQAT BITTA zaxira (masalan tungi cron + deploy, yoki ikki cron qatori): ikkinchisi kutadi (15 daqiqagacha).
if command -v flock >/dev/null 2>&1; then exec 9<"$BACKUP_DIR"; flock -w 900 9 || { echo "❌ [$(date)] boshqa zaxira hali ishlayapti — bu safar olinmadi"; exit 1; }; fi
OUT="$BACKUP_DIR/db_$STAMP.sql.gz"; ST="$BACKUP_DIR/storage_$STAMP.tar.gz"; AU="$BACKUP_DIR/auth_$STAMP.sql.gz"
# Yangi fayllar noclobber (O_EXCL) bilan: oldindan qo'yilgan symlink orqali root boshqa faylni ustidan yozmaydi
#   (zaxira papkasi xizmat foydalanuvchisi egaligidagi /opt/iqror ichida). Tayyor fayl mv -T bilan (symlink kuzatilmaydi).
#   Vaqtinchalik nomlar jarayon raqami bilan ($$) — boshqa nusxaning chala faylini o'chirib yubormaydi.
P=".$$.part"
rm -f "$OUT$P" "$ST$P" "$AU$P"; set -C
trap 'rm -f "$OUT$P" "$ST$P" "$AU$P"' EXIT

# 1) Baza (maktab jadvallari va funksiyalari)
if [ -n "$PGURL" ]; then
  pg_dump "$PGURL" -n public -n app | gzip > "$OUT$P"
elif ! command -v docker >/dev/null 2>&1; then
  echo "❌ [$(date)] docker buyrug'i topilmadi (PATH=$PATH) — zaxira olinmadi"; exit 1
elif $DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONT"; then
  $DOCKER exec "$DB_CONT" pg_dump -U postgres -d postgres -n public -n app | gzip > "$OUT$P"
else
  echo "❌ [$(date)] baza topilmadi: '$DB_CONT' konteyneri ishlamayapti va PGURL berilmagan"; exit 1
fi
# To'liq yozilganini tekshiramiz (pg_dump oxirida «dump complete» yozadi) — chala fayl zaxira bo'lib qolmasin.
gzip -dc "$OUT$P" | tail -n 20 | grep -q 'PostgreSQL database dump complete' \
  || { echo "❌ [$(date)] baza zaxirasi chala chiqdi — saqlanmadi"; exit 1; }
mv -fT "$OUT$P" "$OUT"

# 1b) Kirish hisoblari (auth sxemasi: xodim va ota-ona hisoblari, parol xeshlari). Ilgari faqat deploy olardi va 14 kundan
#   keyin o'chib ketardi — server yo'qolsa hamma qayta ro'yxatdan o'tishi kerak bo'lardi. Olinmasa — OGOHLANTIRISH
#   (asosiy zaxira saqlangan; cron log'ida ko'rinadi). Fayl ham 600: ichida parol xeshlari bor.
#   Sessiya/token jadvallarining MA'LUMOTI olinmaydi (tuzilishi olinadi): refresh token — tayyor kirish kaliti; zaxira nusxasi
#   kimning qo'liga tushsa, hisobga parolsiz kirardi. Tiklashda ular kerak emas — foydalanuvchilar qayta kiradi.
AUX="--exclude-table-data=auth.refresh_tokens --exclude-table-data=auth.sessions --exclude-table-data=auth.flow_state --exclude-table-data=auth.one_time_tokens --exclude-table-data=auth.mfa_challenges --exclude-table-data=auth.mfa_amr_claims --exclude-table-data=auth.audit_log_entries"
AUOK=0; AUSAVED=0
if [ -n "$PGURL" ]; then
  if pg_dump "$PGURL" -n auth $AUX 2>/dev/null | gzip > "$AU$P"; then AUOK=1; fi
elif $DOCKER exec "$DB_CONT" pg_dump -U postgres -d postgres -n auth $AUX 2>/dev/null | gzip > "$AU$P"; then AUOK=1; fi
if [ "$AUOK" = 1 ] && gzip -dc "$AU$P" | tail -n 20 | grep -q 'PostgreSQL database dump complete'; then mv -fT "$AU$P" "$AU"; AUSAVED=1
else rm -f "$AU$P"; echo "⚠️ [$(date)] kirish hisoblari (auth) zaxirasi olinmadi — asosiy zaxira saqlandi"; fi

# 2) Storage fayllar (rasm/video). Papka standart joyda bo'lmasa — Supabase storage konteyneridan topiladi; umuman topilmasa
#   JIM o'tkazilmaydi: ogohlantirish yoziladi va xulosada «storage YO'Q» chiqadi (rasm/videolar zaxiralanmayapti).
STSAVED=0
if [ ! -d "$STORAGE_VOL" ] && [ -z "$PGURL" ] && command -v docker >/dev/null 2>&1; then
  sv="$($DOCKER inspect supabase-storage --format '{{range .Mounts}}{{if eq .Destination "/var/lib/storage"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)"
  [ -n "$sv" ] && [ -d "$sv" ] && STORAGE_VOL="$sv"
fi
if [ -d "$STORAGE_VOL" ]; then
  tar czf - -C "$STORAGE_VOL" . > "$ST$P"
  mv -fT "$ST$P" "$ST"; STSAVED=1
else
  echo "⚠️ [$(date)] storage papkasi topilmadi ($STORAGE_VOL) — rasm/video fayllar ZAXIRALANMADI (STORAGE_VOL=... bilan to'g'ri yo'lni bering)"
fi

# 3) Eski zaxiralarni tozalash — FAQAT shu skriptlar yaratganlari (db_/storage_/auth_), papkaning o'zida. Qo'lda qo'yilgan
#   boshqa fayllar (masalan cutover oldidan olingan dump) va ichki papkalar TEGILMAYDI (avval har qanday *.gz o'chirilardi).
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'db_*.sql.gz' -o -name 'storage_*.tar.gz' -o -name 'auth_*.sql.gz' \) -mtime +"$KEEP_DAYS" -print -delete \
  | sed 's/^/   o‘chirildi (eski): /'

echo "[$(date)] backup OK -> $OUT ($(du -h "$OUT" | cut -f1))$([ "$AUSAVED" = 1 ] && echo ' + auth' || echo ' (auth YO‘Q)')$([ "$STSAVED" = 1 ] && echo ' + storage' || echo ' (storage YO‘Q)'); eski >$KEEP_DAYS kun o'chirildi"
