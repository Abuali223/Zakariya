#!/usr/bin/env bash
# =====================================================================
# To'liq deploy — BITTA buyruq: oldindan tekshiruv + zaxiralar + deploy.sh + keyingi tekshiruvlar.
#   Ishlatish (sudo'SIZ, oddiy foydalanuvchi sifatida). Eski serverda ham ishlashi uchun avval yangi skriptlar olinadi:
#     cd ~/iqror-repo && git fetch origin claude/iqror-med-school-impl-iqdntl && git checkout FETCH_HEAD -- deploy.sh migration && bash migration/deploy/full-deploy.sh
#   Butun chiqish ~/iqror-deploy-<vaqt>.log ga ham yoziladi (600).
#   Zaxiralar (root, 600) -> /opt/iqror/backups: db_* (public+app, backup.sh) + storage_* (fayllar) + auth_* (auth sxemasi),
#     web_* (/var/www/iqror), srv_* (xizmatlar kodi papkasi, masalan /opt/iqror: server kodi va config.json'lar, node_modules'siz).
#     web_*/srv_* 14 kundan eskisi o'chiriladi (backup.sh'dagi *.gz qoidasi bilan bir xil).
#   Tartib: oldindan tekshiruv yoki zaxira muvaffaqiyatsiz bo'lsa — deploy BOSHLANMAYDI (hech narsa o'zgarmaydi).
#   Chiqish kodi: 0 — hammasi joyida; 1 — boshlanmadi (oldindan tekshiruv/zaxira); deploy.sh xatosi — uning kodi;
#     2 — deploy bajarildi, lekin keyingi tekshiruvda «!!» bor (yuqoriga qarang).
# =====================================================================
set -uo pipefail
REPO="$HOME/iqror-repo"; WEB=/var/www/iqror; OPT=/opt/iqror
DB_CONT="${DB_CONT:-supabase-db}"; BK="${BACKUP_DIR:-/opt/iqror/backups}"
SHIM='s#https://www.gstatic.com/firebasejs/10.12.5#/sb#g'
# sudo bilan EMAS (HOME=/root bo'lib qoladi yoki butun deploy root bo'lib ketadi). Serverga to'g'ridan-to'g'ri root bo'lib
#   kirilgan bo'lsa (SUDO_USER yo'q, repo /root/iqror-repo da) — mumkin.
if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
  echo "❌ sudo'SIZ ishga tushiring (kerakli joylarda o'zi sudo so'raydi): bash ~/iqror-repo/migration/deploy/full-deploy.sh"; exit 1
fi
cd "$REPO" 2>/dev/null || { echo "❌ $REPO topilmadi"; exit 1; }
T=$(date +%Y%m%d_%H%M%S); LOG="$HOME/iqror-deploy-$T.log"
install -m 600 /dev/null "$LOG" && exec > >(tee -a "$LOG") 2>&1
psql_at(){ sudo docker exec -i "$DB_CONT" psql -U postgres -d postgres -X -At "$@"; }
# Xizmatlar ishlaydigan kod papkalari (deploy.sh bilan bir xil qoida): repo emas va payments/ai-assistant/auth bor;
#   WorkingDirectory yo'q unit'da — ExecStart'dagi skript yo'lidan yuqoriga qarab.
exec_code_dir(){
  local a d
  for a in $(systemctl show -p ExecStart --value "$1" 2>/dev/null | sed -n 's/.*argv\[\]=\([^;]*\).*/\1/p;t;p' | head -1); do
    case "$a" in /*) ;; *) continue;; esac
    d=$(dirname "$a")
    while [ "$d" != / ] && [ -n "$d" ]; do
      if sudo test -d "$d/payments" || sudo test -d "$d/ai-assistant" || sudo test -d "$d/auth"; then echo "$d"; return 0; fi
      d=$(dirname "$d")
    done
  done
  return 0
}
code_dirs(){
  local s wd seen=" "
  for s in iqror-ai iqror-pay iqror-auth; do
    systemctl cat "$s" >/dev/null 2>&1 || continue
    wd=$(systemctl show -p WorkingDirectory --value "$s" 2>/dev/null); [ -n "$wd" ] || wd=$(exec_code_dir "$s"); [ -n "$wd" ] || continue
    wd=$(realpath -m "$wd"); case "$wd/" in "$(realpath -m "$REPO")/"*) continue;; esac
    case "$seen" in *" $wd "*) continue;; esac; seen="$seen$wd "
    { sudo test -d "$wd/payments" || sudo test -d "$wd/ai-assistant" || sudo test -d "$wd/auth"; } && echo "$wd"
  done
}

echo "######## 0/4 Oldindan tekshiruv (faqat o'qiydi) — $(date '+%F %T')"
git log -1 --format='    yangi versiya: %h %s (%cd)' --date=format:'%F %H:%M' FETCH_HEAD 2>/dev/null \
  || { echo "❌ FETCH_HEAD yo'q — avval: git fetch origin claude/iqror-med-school-impl-iqdntl"; exit 1; }
sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONT" || { echo "❌ '$DB_CONT' baza konteyneri ishlamayapti (boshqa nom bo'lsa: DB_CONT=<nomi> ...)"; exit 1; }
declare -A NR0   # deploy'dan oldingi NRestarts (keyingi tekshiruvda yiqilish/qayta ishga tushishni aniqlash uchun)
for s in iqror-ai iqror-pay iqror-auth; do
  if systemctl cat "$s" >/dev/null 2>&1; then
    NR0[$s]=$(systemctl show -p NRestarts --value "$s" 2>/dev/null); case "${NR0[$s]}" in ''|*[!0-9]*) NR0[$s]=0;; esac
    echo "    $s: papka=$(systemctl show -p WorkingDirectory --value "$s") yoqilgan=$(systemctl is-enabled "$s" 2>/dev/null) holat=$(systemctl is-active "$s")"
  else echo "    $s: o'rnatilmagan"; fi
done
# Disk: baza zaxirasi + storage fayllari + kichik arxivlar uchun joy (yetmasa — boshlanmaydi).
dbkb=$(psql_at -c "select pg_database_size(current_database())/1024" 2>/dev/null); case "$dbkb" in ''|*[!0-9]*) dbkb=0;; esac
stkb=$(sudo du -sk /opt/iqror/supabase/docker/volumes/storage 2>/dev/null | cut -f1); case "$stkb" in ''|*[!0-9]*) stkb=0;; esac
sudo mkdir -p "$BK"; avail=$(sudo df -Pk "$BK" | awk 'NR==2{print $4}'); case "$avail" in ''|*[!0-9]*) avail=0;; esac
need=$(( dbkb / 2 + stkb + 300 * 1024 ))
echo "    disk: bo'sh $((avail / 1024)) MB, kerak ~$((need / 1024)) MB (baza $((dbkb / 1024)) MB, fayllar $((stkb / 1024)) MB)"
[ "$avail" -gt "$need" ] || { echo "❌ Diskda joy yetmaydi — eski zaxiralarni ($BK) boshqa joyga ko'chiring/o'chiring. Deploy BOSHLANMADI."; exit 1; }
# Uzoq tranzaksiyalar deployni 20 s dan keyin bekor qildiradi (baza o'zgarmaydi) — bir oz kutib ko'ramiz.
LONGQ="from pg_stat_activity where datname = current_database() and pid <> pg_backend_pid() and backend_type = 'client backend'
       and (state like 'idle in transaction%' or (state = 'active' and now() - xact_start > interval '30 seconds'))"
for i in 1 2 3 4 5 6 7; do
  n=$(psql_at -c "select count(*) $LONGQ" 2>/dev/null); case "$n" in ''|*[!0-9]*) n=0;; esac
  [ "$n" = 0 ] && break
  [ "$i" = 7 ] && break   # oxirgi tekshiruvdan keyin kutmaymiz (aks holda eskirgan son bilan ogohlantirardi)
  echo "    ⏳ $n ta uzoq tranzaksiya — 10 s kutilmoqda ($i/6)"; sleep 10
done
if [ "$n" != 0 ]; then
  echo "    ⚠️ Uzoq tranzaksiyalar hali bor (deploy baribir uriniladi; band bo'lsa 20 s da bekor bo'ladi — baza o'zgarmaydi, keyinroq qayta ishga tushiring):"
  psql_at -c "select pid || ' ' || coalesce(usename, '') || ' ' || state || ' ' || (now() - xact_start)::text || ' ' || left(query, 80) $LONGQ" | sed 's/^/       /'
fi
echo "---- Ma'lumot tekshiruvi (migration/deploy/predeploy-checks.sql; bo'sh jadval = muammo yo'q)"
sudo docker exec -i "$DB_CONT" psql -U postgres -d postgres -X -P pager=off < "$REPO/migration/deploy/predeploy-checks.sql" 2>&1 | sed 's/^/    /'

echo "######## 1/4 Zaxiralar -> $BK"
sudo env BACKUP_DIR="$BK" DB_CONT="$DB_CONT" bash "$REPO/migration/deploy/backup.sh" \
  || { echo "❌ Baza zaxirasi olinmadi — deploy BOSHLANMADI (hech narsa o'zgarmadi)."; exit 1; }
# auth sxemasi (foydalanuvchilar/parollar) — backup.sh'da yo'q. Deploy auth ma'lumotiga tegmaydi; olinmasa faqat ogohlantiradi.
#   Zaxira fayllari: noclobber (O_EXCL) bilan YANGI fayl, so'ng mv — oldindan qo'yilgan symlink orqali root boshqa faylni
#   ustidan yozib yubormaydi (zaxira papkasi xizmat foydalanuvchisi egaligidagi /opt/iqror ichida).
bk_write(){   # $1 = nishon fayl, $2 = stdout'ga arxiv chiqaradigan buyruq (root sifatida)
  sudo rm -f "$1.part"   # avvalgi uzilgan urinish qoldig'i (symlink bo'lsa — faqat o'zi o'chadi, nishoni emas)
  sudo sh -c "set -C; umask 077; $2 > '$1.part'" && sudo mv -f "$1.part" "$1" || { sudo rm -f "$1.part"; return 1; }
}
A="$BK/auth_$T.sql.gz"; sudo rm -f "$A.part"
if sudo sh -c "set -C; umask 077; docker exec '$DB_CONT' pg_dump -U postgres -d postgres -n auth | gzip > '$A.part'" 2>/dev/null \
   && sudo sh -c "gzip -dc '$A.part' | tail -n 20 | grep -q 'PostgreSQL database dump complete'"; then
  sudo mv -f "$A.part" "$A"; echo "    auth sxemasi: $A"
else
  sudo rm -f "$A.part"; echo "    ⚠️ auth sxemasi zaxirasi olinmadi (deploy auth ma'lumotiga tegmaydi — davom etiladi)"
fi
bk_write "$BK/web_$T.tgz" "tar -czf - -C /var/www iqror" || { echo "❌ Sayt zaxirasi olinmadi — deploy BOSHLANMADI."; exit 1; }
RB=""   # orqaga qaytarish buyruqlari (server kodi)
for wd in $(code_dirs); do
  dirs=$(for d in ai-assistant payments server sb auth; do sudo test -d "$wd/$d" && printf '%s ' "$d"; done)
  [ -n "$dirs" ] || continue
  f="$BK/srv_$(echo "${wd#/}" | tr '/' '_')_$T.tgz"
  bk_write "$f" "tar -czf - -C '$wd' --exclude=node_modules $dirs" || { echo "❌ $wd zaxirasi olinmadi — deploy BOSHLANMADI."; exit 1; }
  RB="${RB}sudo tar -xzf $f -C $wd ; "
done
# Eski web_/srv_ arxivlari (backup.sh faqat *.gz ni tozalaydi):
sudo find "$BK" -maxdepth 1 -type f \( -name 'web_*.tgz' -o -name 'srv_*.tgz' \) -mtime +14 -delete 2>/dev/null || true
sudo ls -lt "$BK" | head -8 | sed 's/^/    /'

echo "######## 2/4 Deploy (deploy.sh) — $(date '+%T')"
DOUT=$(mktemp "${TMPDIR:-/tmp}/iqror-full-deploy.XXXXXX")
DB_CONT="$DB_CONT" bash "$REPO/deploy.sh" 2>&1 | tee "$DOUT"; rc=${PIPESTATUS[0]}
if [ "$rc" != 0 ]; then
  rm -f "$DOUT"
  echo ""
  echo "❌ deploy.sh xato bilan tugadi (kod $rc) — yuqoridagi ❌ qatorini o'qing."
  echo "   «BOSHLANMADI» yoki «SQL migratsiya xato» bo'lsa — baza, sayt va server kodi O'ZGARMAGAN: sababni tuzatib, shu buyruqni qayta ishga tushiring."
  echo "   Keyinroq to'xtagan bo'lsa — sababni tuzatib qayta ishga tushiring (deploy qayta ishga tushirishga xavfsiz)."
  echo "   Log: $LOG"
  exit "$rc"
fi

echo "######## 3/4 Keyingi tekshiruvlar"
bad=0
git log -1 --format='    joylangan versiya: %h %s' FETCH_HEAD
# Sayt fayllari aynan shu versiyadami?
for f in admin.html index.html imtihon.html verify.html oquv-platforma.html haydovchi.html; do
  git show "FETCH_HEAD:$f" | sed "$SHIM" | sudo cmp -s - "$WEB/$f" || { echo "    !! $WEB/$f yangilanmagan"; bad=1; }
done
git show FETCH_HEAD:sw.js | sudo cmp -s - "$WEB/sw.js" || { echo "    !! $WEB/sw.js yangilanmagan"; bad=1; }
for f in _core.js firebase-app.js firebase-auth.js firebase-firestore.js firebase-storage.js firebase-analytics.js auth-api.js name-match.js; do
  git show "FETCH_HEAD:sb/$f" | sudo cmp -s - "$WEB/sb/$f" || { echo "    !! $WEB/sb/$f yangilanmagan"; bad=1; }
done
[ "$bad" = 0 ] && echo "    ✓ sayt fayllari (sahifalar + /sb shimlar) yangi versiyada"
# Server kodi (xizmatlar ishlaydigan papka) aynan shu versiyadami?
for wd in $(code_dirs); do
  nb=0
  while read -r f; do
    git show "FETCH_HEAD:$f" | sudo cmp -s - "$wd/$f" || { echo "    !! $wd/$f yangilanmagan"; nb=1; }
  done < <(git ls-tree -r --name-only FETCH_HEAD ai-assistant payments server sb auth)
  if [ "$nb" = 0 ]; then echo "    ✓ server kodi $wd da yangi versiyada"; else bad=1; fi
done
# Bazada yangi obyektlar (kutilgan: 5 / 1 / 7):
psql_at -c "select '    yangi funksiyalar: ' || count(*) || ' (kutilgan 5)' from pg_proc where proname in ('camera_owners','camera_has_scans','payroll_key_info','rekey_payroll_id','payroll_id_high_water')" \
        -c "select '    config.ratesPrev ustuni: ' || count(*) || ' (kutilgan 1)' from information_schema.columns where table_schema = 'public' and table_name = 'config' and column_name = 'ratesPrev'" \
        -c "select '    ID qo''riqchi triggerlar: ' || count(*) || ' (kutilgan 7)' from pg_trigger where tgname in ('trg_student_keys','trg_teacher_row_id','trg_staff_row_id','trg_salpay_key','trg_staffadv_key','trg_teacher_payroll_id','trg_staff_payroll_id')"
grep -q "BIR XIL" "$DOUT" || { echo "    !! 7/7 baza tekshiruvi «BIR XIL» emas — yuqoridagi 🔴/🟠 qatorlarni ko'rib chiqing"; bad=1; }
rm -f "$DOUT"
# Xizmatlar: ishlayaptimi va deploy'dan keyin YIQILIB qayta ishga tushmadimi. deploy.sh har xizmatni qo'lda qayta ishga
#   tushiradi — systemd bunda NRestarts'ni 0 qiladi; shundan keyin 0 dan katta qiymat = xizmat yiqilib, o'zi qayta
#   ko'tarilgan (3 s kutib yana qaraladi). /health — port config.json'da boshqacha bo'lsa javob bo'lmasligi mumkin, bu xato emas.
sleep 3
for p in "iqror-pay 8790" "iqror-ai 8791" "iqror-auth 8792"; do
  set -- $p
  systemctl cat "$1" >/dev/null 2>&1 || continue
  st=$(systemctl is-active "$1" 2>/dev/null); nr=$(systemctl show -p NRestarts --value "$1" 2>/dev/null)
  case "$nr" in ''|*[!0-9]*) nr=0;; esac; n0=${NR0[$1]:-0}
  hl=$(curl -s -m 5 "http://127.0.0.1:$2/health" 2>/dev/null | head -c 80 || true)
  if [ "$st" = active ] && [ "$nr" = 0 ]; then
    echo "    $1: active  /health: $hl"
  elif ! systemctl is-enabled --quiet "$1" 2>/dev/null && [ "$st" != active ] && [ "$1" = iqror-auth ]; then
    echo "    $1: $st (o'chirilgan — deploy unga tegmaydi)"
  else
    echo "    !! $1: $st (NRestarts $n0 -> $nr) — yiqilmoqda: sudo journalctl -u $1 -n 50 --no-pager"; bad=1
  fi
done

echo "######## 4/4 SMS va cron (ma'lumot uchun)"
if [ -f "$REPO/payments/eskiz-shablon.cjs" ] && command -v node >/dev/null 2>&1; then
  echo "---- Eskiz shablonlari (hech narsa YUBORMAYDI — faqat tekshiradi)"
  (cd "$REPO/payments" && timeout 90 sudo "$(command -v node)" eskiz-shablon.cjs 2>&1 | sed 's/^/    /') || true
fi
if crontab -l 2>/dev/null | grep -q 'sms-worker.cjs'; then echo "    ✓ SMS cron (sms-worker) bor"
else echo "    ℹ️ SMS cron yo'q (avtomatik faktura/qarz SMS kerak bo'lsa — payments/README.md §7.4, crontab -e)"; fi
if sudo crontab -l 2>/dev/null | grep -q 'backup.sh'; then echo "    ✓ kunlik zaxira cron (root) bor"
else echo "    ⚠️ kunlik zaxira cron yo'q: sudo crontab -e  ->  30 22 * * * bash $REPO/migration/deploy/backup.sh >> /var/log/iqror-backup.log 2>&1"; fi

echo ""
if [ "$bad" = 0 ]; then echo "✅ TO'LIQ DEPLOY MUVAFFAQIYATLI ($(date '+%F %T'))."
else echo "⚠️ Deploy bajarildi, lekin yuqorida «!!» qatorlari bor — ko'rib chiqing."; fi
echo "MUHIM: barcha kompyuter/telefonlardagi OCHIQ admin oynalarini yangilang (Ctrl+Shift+R; telefonda sahifani yopib qayta oching)."
echo "Log: $LOG    Zaxiralar: $BK (*$T*, db_*/storage_* — eng oxirgilari)"
echo "Orqaga qaytarish (faqat kerak bo'lsa): sayt — sudo tar -xzf $BK/web_$T.tgz -C /var/www"
[ -n "$RB" ] && echo "   server kodi — ${RB}sudo systemctl restart iqror-pay iqror-ai iqror-auth"
echo "   baza — faqat maslahatlashib (zaxiradan tiklash oddiy emas: migration/deploy/README.md)."
[ "$bad" = 0 ] || exit 2
