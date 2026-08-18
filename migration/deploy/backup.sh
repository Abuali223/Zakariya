#!/usr/bin/env bash
# =====================================================================
# backup.sh — kunlik zaxira: PostgreSQL (pg_dump) + Supabase Storage.
# Cron bilan (masalan har kuni 03:00):
#   0 3 * * *  /opt/iqror/migration/deploy/backup.sh >> /var/log/iqror-backup.log 2>&1
# Zaxirani BOSHQA joyga (masalan aHost obyekt-xotira yoki boshqa disk) ham ko'chiring!
# =====================================================================
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/iqror/backups}"
PGURL="${PGURL:-postgresql://postgres:PAROL@localhost:5432/postgres}"
STORAGE_VOL="${STORAGE_VOL:-/opt/iqror/supabase/docker/volumes/storage}"  # Supabase storage hajmi
KEEP_DAYS="${KEEP_DAYS:-14}"

STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# 1) Baza
pg_dump "$PGURL" | gzip > "$BACKUP_DIR/db_$STAMP.sql.gz"

# 2) Storage fayllar (rasm/video)
if [ -d "$STORAGE_VOL" ]; then
  tar czf "$BACKUP_DIR/storage_$STAMP.tar.gz" -C "$STORAGE_VOL" .
fi

# 3) Eski zaxiralarni tozalash
find "$BACKUP_DIR" -name '*.gz' -mtime +"$KEEP_DAYS" -delete

echo "[$(date)] backup OK -> $BACKUP_DIR (db + storage), eski >$KEEP_DAYS kun o'chirildi"
