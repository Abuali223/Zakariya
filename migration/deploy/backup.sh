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

if [ "$(id -u)" = 0 ]; then BACKUP_DIR="${BACKUP_DIR:-/opt/iqror/backups}"; else BACKUP_DIR="${BACKUP_DIR:-$HOME/iqror-backups}"; fi
DB_CONT="${DB_CONT:-supabase-db}"
PGURL="${PGURL:-}"
STORAGE_VOL="${STORAGE_VOL:-/opt/iqror/supabase/docker/volumes/storage}"  # Supabase storage hajmi (bo'lmasa o'tkaziladi)
KEEP_DAYS="${KEEP_DAYS:-14}"
DOCKER="docker"; if [ "$(id -u)" != 0 ] && ! docker ps >/dev/null 2>&1; then DOCKER="sudo docker"; fi

STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"; [ -L "$BACKUP_DIR" ] || chmod 700 "$BACKUP_DIR" 2>/dev/null || true   # symlink bo'lsa nishoni o'zgartirilmaydi
OUT="$BACKUP_DIR/db_$STAMP.sql.gz"; ST="$BACKUP_DIR/storage_$STAMP.tar.gz"
# Yangi fayllar noclobber (O_EXCL) bilan: oldindan qo'yilgan symlink orqali root boshqa faylni ustidan yozmaydi
#   (zaxira papkasi xizmat foydalanuvchisi egaligidagi /opt/iqror ichida). Tayyor fayl mv -T bilan (symlink kuzatilmaydi).
rm -f "$OUT.part" "$ST.part"; set -C
trap 'rm -f "$OUT.part" "$ST.part"' EXIT

# 1) Baza (maktab jadvallari va funksiyalari)
if [ -n "$PGURL" ]; then
  pg_dump "$PGURL" -n public -n app | gzip > "$OUT.part"
elif $DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONT"; then
  $DOCKER exec "$DB_CONT" pg_dump -U postgres -d postgres -n public -n app | gzip > "$OUT.part"
else
  echo "❌ [$(date)] baza topilmadi: '$DB_CONT' konteyneri ishlamayapti va PGURL berilmagan"; exit 1
fi
# To'liq yozilganini tekshiramiz (pg_dump oxirida «dump complete» yozadi) — chala fayl zaxira bo'lib qolmasin.
gzip -dc "$OUT.part" | tail -n 20 | grep -q 'PostgreSQL database dump complete' \
  || { echo "❌ [$(date)] baza zaxirasi chala chiqdi — saqlanmadi"; exit 1; }
mv -fT "$OUT.part" "$OUT"

# 2) Storage fayllar (rasm/video) — papka bor bo'lsa
if [ -d "$STORAGE_VOL" ]; then
  tar czf - -C "$STORAGE_VOL" . > "$ST.part"
  mv -fT "$ST.part" "$ST"
fi

# 3) Eski zaxiralarni tozalash — FAQAT shu skriptlar yaratganlari (db_/storage_/auth_), papkaning o'zida. Qo'lda qo'yilgan
#   boshqa fayllar (masalan cutover oldidan olingan dump) va ichki papkalar TEGILMAYDI (avval har qanday *.gz o'chirilardi).
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'db_*.sql.gz' -o -name 'storage_*.tar.gz' -o -name 'auth_*.sql.gz' \) -mtime +"$KEEP_DAYS" -print -delete \
  | sed 's/^/   o‘chirildi (eski): /'

echo "[$(date)] backup OK -> $OUT ($(du -h "$OUT" | cut -f1)); eski >$KEEP_DAYS kun o'chirildi"
