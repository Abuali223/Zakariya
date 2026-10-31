#!/usr/bin/env bash
# =====================================================================
# backup.sh — zaxira: PostgreSQL (maktab ma'lumotlari: public + app sxemalari) + kirish hisoblari (auth) + Supabase Storage
#   fayllari va ularning metama'lumoti (storage.buckets/objects) + SIRLAR (kalit/parollar saqlangan sozlama fayllari).
#   Tiklash: migration/deploy/RESTORE.md.
#   Bir martalik (zaxira ~/iqror-backups ga):   bash ~/iqror-repo/migration/deploy/backup.sh
#   Har kuni (root crontab: sudo crontab -e; zaxira /opt/iqror/backups ga; server UTC'da — 22:30 = Toshkent 03:30):
#     30 22 * * *  bash /home/ubuntu/iqror-repo/migration/deploy/backup.sh >> /var/log/iqror-backup.log 2>&1
#   Baza Supabase docker konteyneri ichidagi pg_dump bilan olinadi (DB_CONT, standart supabase-db) — parol
#   kerak emas. Tashqi baza bo'lsa: PGURL=postgresql://... (unda host'da pg_dump bo'lishi kerak).
#   Zaxira fayllari faqat egasiga o'qiladi (600): ichida shaxsiy ma'lumot (JSHSHIR, telefon, manzil) va kalitlar bor.
#   Fayl to'liq yozilmasa (dump uzilsa) — saqlanmaydi, xato bilan tugaydi.
#   Saqlash muddati: KEEP_DAYS (standart 60 kun) — faqat shu skript yaratgan fayllar o'chiriladi.
#
#   SIRLAR (secrets_<vaqt>.tar.gz, 600): Supabase .env, auth/payments/ai-assistant config.json, sb/sb-config.js (bor bo'lsa),
#     nginx sayt sozlamasi, iqror-*.service. Topilmagan fayl JIM o'tkazilmaydi — NOMI logga yoziladi (ichidagi qiymatlar
#     hech qachon logga chiqmaydi). Yo'llar o'zgaruvchi bilan (standartlari — server tuzilishi, migration/deploy/README.md):
#       SUPA_ENV=/opt/iqror/supabase/docker/.env  SRV_DIR=/opt/iqror  WEB_DIR=/var/www/iqror
#       NGINX_SITE=/etc/nginx/sites-available/iqror  UNIT_DIR=/etc/systemd/system  SECRETS_EXTRA="yo'l1 yo'l2" (qo'shimcha)
#     Ixtiyoriy shifrlash (faqat sirlar fayli): BACKUP_GPG_RECIPIENT=<gpg kalit id/email> -> secrets_*.tar.gz.gpg
#       yoki BACKUP_PASSFILE=<parol fayli, 600> -> secrets_*.tar.gz.enc (openssl aes-256-cbc, pbkdf2). Shifrlash xato bo'lsa —
#       sirlar fayli ochiq holda SAQLANMAYDI (ogohlantirish; asosiy zaxira saqlanadi).
#   Ixtiyoriy TASHQI nusxa: RCLONE_REMOTE=<remote:papka> (rclone crypt remote tavsiya etiladi) — shu safargi fayllar
#     `rclone copy` bilan; xato bo'lsa — ogohlantirish, lokal zaxira saqlanadi. RCLONE_FLAGS — qo'shimcha bayroqlar.
# =====================================================================
set -euo pipefail
umask 077
# cron'da PATH faqat /usr/bin:/bin — docker (snap'da /snap/bin) va boshqa buyruqlar shunda ham topilsin (oxiriga: mavjud tartib o'zgarmaydi).
export PATH="${PATH:+$PATH:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

if [ "$(id -u)" = 0 ]; then BACKUP_DIR="${BACKUP_DIR:-/opt/iqror/backups}"; else BACKUP_DIR="${BACKUP_DIR:-$HOME/iqror-backups}"; fi
DB_CONT="${DB_CONT:-supabase-db}"
PGURL="${PGURL:-}"
STORAGE_VOL="${STORAGE_VOL:-/opt/iqror/supabase/docker/volumes/storage}"  # Supabase storage hajmi (bo'lmasa o'tkaziladi)
KEEP_DAYS="${KEEP_DAYS:-60}"
case "$KEEP_DAYS" in ''|*[!0-9]*) echo "❌ [$(date)] KEEP_DAYS butun son bo'lishi kerak (hozir: '$KEEP_DAYS') — zaxira olinmadi"; exit 1;; esac
SUPA_ENV="${SUPA_ENV:-/opt/iqror/supabase/docker/.env}"
SRV_DIR="${SRV_DIR:-/opt/iqror}"
WEB_DIR="${WEB_DIR:-/var/www/iqror}"
NGINX_SITE="${NGINX_SITE:-/etc/nginx/sites-available/iqror}"
UNIT_DIR="${UNIT_DIR:-/etc/systemd/system}"
SECRETS_EXTRA="${SECRETS_EXTRA:-}"
BACKUP_GPG_RECIPIENT="${BACKUP_GPG_RECIPIENT:-}"
BACKUP_PASSFILE="${BACKUP_PASSFILE:-}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}"
DOCKER="docker"; if [ "$(id -u)" != 0 ] && ! docker ps >/dev/null 2>&1; then DOCKER="sudo docker"; fi

STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"; [ -L "$BACKUP_DIR" ] || chmod 700 "$BACKUP_DIR" 2>/dev/null || true   # symlink bo'lsa nishoni o'zgartirilmaydi
# BIR VAQTDA FAQAT BITTA zaxira (masalan tungi cron + deploy, yoki ikki cron qatori): ikkinchisi kutadi (15 daqiqagacha).
if command -v flock >/dev/null 2>&1; then exec 9<"$BACKUP_DIR"; flock -w 900 9 || { echo "❌ [$(date)] boshqa zaxira hali ishlayapti — bu safar olinmadi"; exit 1; }; fi
OUT="$BACKUP_DIR/db_$STAMP.sql.gz"; ST="$BACKUP_DIR/storage_$STAMP.tar.gz"; AU="$BACKUP_DIR/auth_$STAMP.sql.gz"
SM="$BACKUP_DIR/storage_meta_$STAMP.sql.gz"; SE="$BACKUP_DIR/secrets_$STAMP.tar.gz"
if [ -n "$BACKUP_GPG_RECIPIENT" ]; then SE="$SE.gpg"; elif [ -n "$BACKUP_PASSFILE" ]; then SE="$SE.enc"; fi
# Yangi fayllar noclobber (O_EXCL) bilan: oldindan qo'yilgan symlink orqali root boshqa faylni ustidan yozmaydi
#   (zaxira papkasi xizmat foydalanuvchisi egaligidagi /opt/iqror ichida). Tayyor fayl mv -T bilan (symlink kuzatilmaydi).
#   Vaqtinchalik nomlar jarayon raqami bilan ($$) — boshqa nusxaning chala faylini o'chirib yubormaydi.
P=".$$.part"
rm -f "$OUT$P" "$ST$P" "$AU$P" "$SM$P" "$SE$P"; set -C
trap 'rm -f "$OUT$P" "$ST$P" "$AU$P" "$SM$P" "$SE$P"' EXIT

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
# 2b) Storage METAMA'LUMOTI (storage.buckets / storage.objects jadvallari — qaysi fayl qaysi bucket/yo'l/versiyada). Bu
#   jadvallarsiz diskdagi fayllarni tiklab bo'lmaydi (Supabase faylni shu yozuv orqali topadi). Faqat MA'LUMOT (tuzilishini
#   Supabase o'zi yaratadi; INSERT … ON CONFLICT DO NOTHING — qayta yuklasa ham takrorlanmaydi) — tiklash: RESTORE.md.
#   Olinmasa — ogohlantirish.
SMOK=0; SMSAVED=0
SMARGS="--data-only --column-inserts --on-conflict-do-nothing --table=storage.buckets --table=storage.objects"   # qayta yuklash xavfsiz
if [ -n "$PGURL" ]; then
  if pg_dump "$PGURL" $SMARGS 2>/dev/null | gzip > "$SM$P"; then SMOK=1; fi
elif $DOCKER exec "$DB_CONT" pg_dump -U postgres -d postgres $SMARGS 2>/dev/null | gzip > "$SM$P"; then SMOK=1; fi
if [ "$SMOK" = 1 ] && gzip -dc "$SM$P" | tail -n 20 | grep -q 'PostgreSQL database dump complete'; then mv -fT "$SM$P" "$SM"; SMSAVED=1
else rm -f "$SM$P"; echo "⚠️ [$(date)] storage metama'lumoti (buckets/objects) olinmadi — asosiy zaxira saqlandi"; fi

# 3) SIRLAR — server qayta qurilganda kerak bo'ladigan kalit va sozlamalar (baza zaxirasida yo'q). Majburiy ro'yxatdagi
#   topilmagan fayl — logda «YO'Q» deb nomi bilan yoziladi; sb-config.js — bor bo'lsa (u /var/www/iqror/sb da yoki repo'da).
#   Fayl NOMLARI logga yoziladi, ICHIDAGI qiymatlar hech qachon chiqarilmaydi.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd || true)"
SEC_REQ=("$SUPA_ENV" "$SRV_DIR/auth/config.json" "$SRV_DIR/payments/config.json" "$SRV_DIR/ai-assistant/config.json" "$NGINX_SITE")
SEC_OPT=("$WEB_DIR/sb/sb-config.js" "$SRV_DIR/sb/sb-config.js")
[ -n "$REPO_DIR" ] && SEC_OPT+=("$REPO_DIR/sb/sb-config.js")
for f in $SECRETS_EXTRA; do SEC_REQ+=("$f"); done
SEC_HAVE=(); SEC_MISS=()
for f in "${SEC_REQ[@]}"; do if [ -f "$f" ]; then SEC_HAVE+=("$f"); else SEC_MISS+=("$f"); fi; done
for f in "${SEC_OPT[@]}"; do [ -f "$f" ] && SEC_HAVE+=("$f"); done
UNITS=0
for f in "$UNIT_DIR"/iqror-*.service; do [ -f "$f" ] && { SEC_HAVE+=("$f"); UNITS=$((UNITS + 1)); }; done
[ "$UNITS" -gt 0 ] || SEC_MISS+=("$UNIT_DIR/iqror-*.service")
# Takrorlarsiz (masalan SRV_DIR va repo'dagi sb-config.js — bir xil fayl bo'lsa) va tar uchun «/» siz nisbiy yo'l.
SEC_REL=(); declare -A SEEN=()
for f in "${SEC_HAVE[@]}"; do r="$(realpath -m "$f")"; [ -n "${SEEN[$r]:-}" ] && continue; SEEN[$r]=1; SEC_REL+=("${r#/}"); done
SESAVED=0; SENOTE=""
if [ "${#SEC_REL[@]}" -gt 0 ]; then
  echo "   sirlar: ${#SEC_REL[@]} ta fayl — $(printf '/%s ' "${SEC_REL[@]}")"
  sec_ok=0
  if [ -n "$BACKUP_GPG_RECIPIENT" ]; then
    if command -v gpg >/dev/null 2>&1 && tar -C / -czf - "${SEC_REL[@]}" | gpg --batch --quiet --trust-model always --recipient "$BACKUP_GPG_RECIPIENT" --encrypt > "$SE$P" 2>/dev/null && [ -s "$SE$P" ]; then
      sec_ok=1; SENOTE=" (gpg bilan shifrlangan)"
    else echo "⚠️ [$(date)] sirlar faylini gpg bilan shifrlab bo'lmadi (gpg yo'q yoki '$BACKUP_GPG_RECIPIENT' kaliti topilmadi) — sirlar fayli SAQLANMADI"; fi
  elif [ -n "$BACKUP_PASSFILE" ]; then
    if [ -s "$BACKUP_PASSFILE" ] && command -v openssl >/dev/null 2>&1 \
       && tar -C / -czf - "${SEC_REL[@]}" | openssl enc -aes-256-cbc -pbkdf2 -salt -pass "file:$BACKUP_PASSFILE" > "$SE$P" 2>/dev/null \
       && openssl enc -d -aes-256-cbc -pbkdf2 -pass "file:$BACKUP_PASSFILE" -in "$SE$P" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
      sec_ok=1; SENOTE=" (openssl bilan shifrlangan)"
    else echo "⚠️ [$(date)] sirlar faylini parol fayli bilan shifrlab bo'lmadi (BACKUP_PASSFILE bo'sh/yo'q yoki openssl yo'q) — sirlar fayli SAQLANMADI"; fi
  elif tar -C / -czf - "${SEC_REL[@]}" > "$SE$P" && tar -tzf "$SE$P" >/dev/null 2>&1; then
    sec_ok=1
  else echo "⚠️ [$(date)] sirlar arxivi yozilmadi — sirlar fayli SAQLANMADI"; fi
  if [ "$sec_ok" = 1 ]; then mv -fT "$SE$P" "$SE"; SESAVED=1; else rm -f "$SE$P"; fi
else
  echo "⚠️ [$(date)] sirlar: hech bir fayl topilmadi — sirlar ZAXIRALANMADI (SUPA_ENV / SRV_DIR / NGINX_SITE yo'llarini tekshiring)"
fi
[ "${#SEC_MISS[@]}" -eq 0 ] || echo "⚠️ [$(date)] sirlar: topilmadi (zaxirada YO'Q) — $(printf '%s ' "${SEC_MISS[@]}")"

# 4) Eski zaxiralarni tozalash — FAQAT shu skriptlar yaratganlari (db_/storage_/auth_/storage_meta_/secrets_), papkaning o'zida.
#   Qo'lda qo'yilgan boshqa fayllar (masalan cutover oldidan olingan dump) va ichki papkalar TEGILMAYDI (avval har qanday *.gz o'chirilardi).
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'db_*.sql.gz' -o -name 'storage_*.tar.gz' -o -name 'auth_*.sql.gz' -o -name 'storage_meta_*.sql.gz' \
     -o -name 'secrets_*.tar.gz' -o -name 'secrets_*.tar.gz.gpg' -o -name 'secrets_*.tar.gz.enc' \) -mtime +"$KEEP_DAYS" -print -delete \
  | sed 's/^/   o‘chirildi (eski): /'

# 5) Ixtiyoriy tashqi nusxa (rclone): faqat SHU safargi fayllar. Xato — ogohlantirish (lokal zaxira saqlanadi).
RCNOTE=""
if [ -n "$RCLONE_REMOTE" ]; then
  if ! command -v rclone >/dev/null 2>&1; then
    echo "⚠️ [$(date)] RCLONE_REMOTE berilgan, lekin rclone o'rnatilmagan — tashqi nusxa OLINMADI (lokal zaxira saqlandi)"; RCNOTE=" (tashqi nusxa YO‘Q)"
  elif timeout 3600 rclone copy "$BACKUP_DIR" "$RCLONE_REMOTE" --max-depth 1 --include "*_${STAMP}.*" ${RCLONE_FLAGS:-} >/dev/null 2>&1; then
    RCNOTE=" + tashqi nusxa ($RCLONE_REMOTE)"
  else
    echo "⚠️ [$(date)] tashqi nusxa (rclone -> $RCLONE_REMOTE) muvaffaqiyatsiz — lokal zaxira saqlandi"; RCNOTE=" (tashqi nusxa XATO)"
  fi
fi

echo "[$(date)] backup OK -> $OUT ($(du -h "$OUT" | cut -f1))$([ "$AUSAVED" = 1 ] && echo ' + auth' || echo ' (auth YO‘Q)')$([ "$STSAVED" = 1 ] && echo ' + storage' || echo ' (storage YO‘Q)')$([ "$SMSAVED" = 1 ] && echo ' + storage metama’lumoti' || echo ' (storage metama’lumoti YO‘Q)')$([ "$SESAVED" = 1 ] && echo " + sirlar (${#SEC_REL[@]} fayl${SENOTE}$([ "${#SEC_MISS[@]}" -eq 0 ] || echo ", ${#SEC_MISS[@]} tasi yo‘q"))" || echo ' (sirlar YO‘Q)')${RCNOTE}; eski >$KEEP_DAYS kun o'chirildi"
