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
    [ "$(systemctl is-enabled "$s" 2>/dev/null || true)" = masked ] && continue
    wd=$(systemctl show -p WorkingDirectory --value "$s" 2>/dev/null); wd=${wd#!}
    [ "$wd" = "~" ] && wd=$(getent passwd "$(systemctl show -p User --value "$s" 2>/dev/null)" | cut -d: -f6)
    [ -n "$wd" ] || wd=$(exec_code_dir "$s"); case "$wd" in /*) ;; *) continue;; esac
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
# auth sxemasi (foydalanuvchilar/parol xeshlari) — backup.sh o'zi oladi (sessiya/token ma'lumotisiz, auth_*). Zaxira fayllari:
#   noclobber (O_EXCL) bilan YANGI fayl, so'ng mv — oldindan qo'yilgan symlink orqali root boshqa faylni ustidan yozib yubormaydi
#   (zaxira papkasi xizmat foydalanuvchisi egaligidagi /opt/iqror ichida).
bk_write(){   # $1 = nishon fayl, $2 = stdout'ga arxiv chiqaradigan buyruq (root sifatida)
  sudo rm -f "$1.part"   # avvalgi uzilgan urinish qoldig'i (symlink bo'lsa — faqat o'zi o'chadi, nishoni emas)
  sudo sh -c "set -C; umask 077; $2 > '$1.part'" && sudo mv -fT "$1.part" "$1" || { sudo rm -f "$1.part"; return 1; }
}
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
for f in sw.js verify/index.html taqdimot.html prezentatsiya.html; do   # shimsiz sahifalar
  git show "FETCH_HEAD:$f" | sudo cmp -s - "$WEB/$f" || { echo "    !! $WEB/$f yangilanmagan"; bad=1; }
done
# Statik fayllar (vendor/, assets/, uploads/, manifest, ikonalar) — deploy.sh ro'yxati bilan bir xil.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  git show "FETCH_HEAD:$f" | sudo cmp -s - "$WEB/$f" 2>/dev/null || { echo "    !! $WEB/$f yangilanmagan"; bad=1; }
done < <(git ls-tree -r --name-only FETCH_HEAD -- vendor assets uploads manifest.json icon-192.png icon-512.png)
for f in _core.js firebase-app.js firebase-auth.js firebase-firestore.js firebase-storage.js firebase-analytics.js auth-api.js name-match.js; do
  git show "FETCH_HEAD:sb/$f" | sudo cmp -s - "$WEB/sb/$f" || { echo "    !! $WEB/sb/$f yangilanmagan"; bad=1; }
done
# nginx o'qiy oladimi (hamma o'qishi mumkin bo'lishi shart; *.bak — shart emas)?
unread=$(sudo find "$WEB" -maxdepth 2 -type f ! -name '*.bak' \( -name '*.html' -o -name '*.js' -o -name '*.json' -o -name '*.css' \) ! -perm -o=r -print 2>/dev/null)
[ -z "$unread" ] || { printf '    !! nginx o‘qiy olmaydi (403): %s — tuzatish: sudo chmod a+r <fayl>\n' $unread; bad=1; }
[ "$bad" = 0 ] && echo "    ✓ sayt fayllari (sahifalar + /sb shimlar) yangi versiyada"
# Server kodi (xizmatlar ishlaydigan papka) aynan shu versiyadami?
for wd in $(code_dirs); do
  nb=0
  while read -r f; do
    git show "FETCH_HEAD:$f" | sudo cmp -s - "$wd/$f" || { echo "    !! $wd/$f yangilanmagan"; nb=1; }
  done < <(git ls-tree -r --name-only FETCH_HEAD ai-assistant payments server sb auth)
  if [ "$nb" = 0 ]; then echo "    ✓ server kodi $wd da yangi versiyada"; else bad=1; fi
done
# Bazada yangi obyektlar (kutilgan: 10 / 1 / 10) + o'qituvchi/xodim ID reyestri (pasport ID: payroll_ids):
psql_at -c "select '    yangi funksiyalar: ' || count(*) || ' (kutilgan 10)' from pg_proc where proname in ('camera_owners','camera_has_scans','payroll_key_info','rekey_payroll_id','payroll_id_high_water','payroll_id_state','payroll_hw','record_payroll_id','pid_key','guard_private_teacher_link')" \
        -c "select '    config.ratesPrev ustuni: ' || count(*) || ' (kutilgan 1)' from information_schema.columns where table_schema = 'public' and table_name = 'config' and column_name = 'ratesPrev'" \
        -c "select '    ID qo''riqchi triggerlar: ' || count(*) || ' (kutilgan 10, yoqilgan: ' || count(*) filter (where tgenabled <> 'D') || ')' from pg_trigger where tgname in ('trg_student_keys','trg_teacher_row_id','trg_staff_row_id','trg_salpay_key','trg_staffadv_key','trg_teacher_payroll_id','trg_staff_payroll_id','trg_teacher_payroll_reg','trg_staff_payroll_reg','trg_private_teacher_link')" \
        -c "select '    ID reyestri (payroll_ids): ' || count(*) || ' ta ID, ' || count(*) filter (where released_at is not null) || ' tasi bo''shatilgan (qayta berilmaydi); RLS ' || coalesce((select case when relrowsecurity then 'yoqilgan' else 'O''CHIQ!' end from pg_class where oid = to_regclass('public.payroll_ids')), '?') from public.payroll_ids" \
        -c "select '    reyestrda yo''q joriy ID: ' || count(*) || ' (kutilgan 0)' from (select app.pid_key(\"teacherId\") k from public.teachers union all select app.pid_key(\"staffId\") from public.staff) x where k <> '' and not exists (select 1 from public.payroll_ids p where p.id = x.k)" \
        -c "select '    takroriy o''qituvchi/xodim ID''lari: ' || count(*) || case when count(*) > 0 then ' — kartochkada «Yangi noyob ID berish» bilan bir martalik tuzating (migration/deploy/README.md)' else ' ✓' end from (select k from (select app.pid_key(\"teacherId\") k from public.teachers union all select app.pid_key(\"staffId\") from public.staff) x where k <> '' group by k having count(*) > 1) d" \
        -c "select '    o''zgarishlar tarixi (change_log): ' || case when to_regclass('public.change_log') is null then 'YO''Q!' else 'bor, RLS ' || (select case when relrowsecurity then 'yoqilgan' else 'O''CHIQ!' end from pg_class where oid = to_regclass('public.change_log')) end || '; triggerlar: ' || (select count(*) from pg_trigger where tgname in ('trg_change_log','trg_change_log_sick') and tgenabled <> 'D') || ' (kutilgan 24)'" \
        -c "select '    kamera kunlari funksiyasi (camera_days): ' || count(*) || ' (kutilgan 1)' from pg_proc where proname = 'camera_days'"
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
  elif ! systemctl is-enabled --quiet "$1" 2>/dev/null && [ "$st" != active ]; then
    echo "    $1: $st (o'chirilgan/masklangan — deploy unga tegmaydi)"
  else
    echo "    !! $1: $st (NRestarts $n0 -> $nr) — yiqilmoqda: sudo journalctl -u $1 -n 50 --no-pager"; bad=1
  fi
done

echo "######## 4/4 SMS va kunlik zaxira cron"
if [ -f "$REPO/payments/eskiz-shablon.cjs" ] && command -v node >/dev/null 2>&1; then
  echo "---- Eskiz shablonlari (hech narsa YUBORMAYDI — faqat tekshiradi)"
  (cd "$REPO/payments" && timeout 90 sudo "$(command -v node)" eskiz-shablon.cjs 2>&1 | sed 's/^/    /') || true
fi
if crontab -l 2>/dev/null | grep -q 'sms-worker.cjs'; then echo "    ✓ SMS cron (sms-worker) bor"
else echo "    ℹ️ SMS cron yo'q (avtomatik faktura/qarz SMS kerak bo'lsa — payments/README.md §7.4, crontab -e)"; fi
# KUNLIK ZAXIRA CRON'i (root). Yo'q bo'lsa — deploy o'zi o'rnatadi: BITTA sudo, root crontab'ning boshqa qatorlari saqlanadi
#   (grep -a — UTF-8 bo'lmagan qatorlar ham), eski/boshqa yo'ldagi backup.sh qatorlari almashtiriladi, takrorlanmaydi. 22:30 server
#   vaqti (UTC bo'lsa Toshkent 03:30). DB_CONT / BACKUP_DIR standart bo'lmasa — qatorga yoziladi (tunda ham shu baza/papka).
#   Izohga olingan (#) qator bo'lsa — atayin o'chirilgan deb olinadi: QAYTA YOQILMAYDI (faqat ogohlantirish). O'rnatmaslik:
#   IQROR_NO_BACKUP_CRON=1 bash migration/deploy/full-deploy.sh
BKCMD="bash $REPO/migration/deploy/backup.sh"
[ "$BK" = /opt/iqror/backups ] || BKCMD="BACKUP_DIR=$BK $BKCMD"
[ "$DB_CONT" = supabase-db ] || BKCMD="DB_CONT=$DB_CONT $BKCMD"
BKLINE="30 22 * * * $BKCMD >> /var/log/iqror-backup.log 2>&1"
CUR="$(sudo crontab -l 2>/dev/null || true)"   # o'zgaruvchiga — pipefail + grep -q erta chiqishi (SIGPIPE) soxta «yo'q» bermasin
ACTIVE="$(printf '%s\n' "$CUR" | grep -av '^[[:space:]]*#' | grep -aF "$REPO/migration/deploy/backup.sh" || true)"
if [ -n "$ACTIVE" ]; then
  echo "    ✓ kunlik zaxira cron (root) bor: $(printf '%s' "$ACTIVE" | head -n 1 | cut -c1-140)"
  if sudo test -f /var/log/iqror-backup.log && [ -n "$(sudo find /var/log/iqror-backup.log -mmin +1560 2>/dev/null)" ]; then
    echo "    ⚠️ oxirgi tungi zaxira log'i 26 soatdan eski — tekshiring: sudo tail -n 5 /var/log/iqror-backup.log"
  elif sudo test -f /var/log/iqror-backup.log && sudo tail -n 3 /var/log/iqror-backup.log 2>/dev/null | grep -q '❌'; then
    echo "    !! oxirgi tungi zaxira XATO bilan tugagan: sudo tail -n 5 /var/log/iqror-backup.log"; bad=1
  fi
elif printf '%s\n' "$CUR" | grep -a '^[[:space:]]*#' | grep -aq 'migration/deploy/backup\.sh'; then
  echo "    ⚠️ kunlik zaxira cron izohga olingan (o'chirilgan) — qayta yoqilmadi. Yoqish: sudo crontab -e (qator boshidagi # ni olib tashlang)"
elif [ "${IQROR_NO_BACKUP_CRON:-}" = 1 ]; then
  echo "    ⚠️ kunlik zaxira cron yo'q (IQROR_NO_BACKUP_CRON=1 — o'rnatilmadi)"
elif ! sudo sh -c 'command -v crontab' >/dev/null 2>&1; then
  echo "    !! kunlik zaxira cron o'rnatib bo'lmadi: cron o'rnatilmagan — sudo apt install -y cron && sudo systemctl enable --now cron, so'ng deployni qayta ishga tushiring"; bad=1
elif { printf '%s\n' "$CUR" | grep -av 'migration/deploy/backup\.sh' || true; printf '%s\n' "$BKLINE"; } | sudo crontab - 2>/dev/null \
     && sudo crontab -l 2>/dev/null | grep -aF "$REPO/migration/deploy/backup.sh" >/dev/null; then
  echo "    ✓ kunlik zaxira cron (root) O'RNATILDI — har kuni 22:30 (server vaqti): $BKLINE"
  echo "      Ertaga tekshiring: sudo tail -n 3 /var/log/iqror-backup.log"
else echo "    !! kunlik zaxira cron yo'q va o'rnatib bo'lmadi — migration/deploy/README.md «kunlik zaxira cron yo'q» bandini bajaring"; bad=1; fi
# cron xizmatining o'zi ishlayaptimi (qator bor, lekin xizmat to'xtagan bo'lsa — zaxira hech qachon olinmaydi).
if sudo crontab -l 2>/dev/null | grep -av '^[[:space:]]*#' | grep -aF 'migration/deploy/backup.sh' >/dev/null && command -v pgrep >/dev/null 2>&1 \
   && ! pgrep -x cron >/dev/null 2>&1 && ! pgrep -x crond >/dev/null 2>&1; then
  echo "    !! cron xizmati ishlamayapti — tungi zaxira olinmaydi: sudo systemctl enable --now cron"; bad=1
fi

echo ""
if [ "$bad" = 0 ]; then echo "✅ TO'LIQ DEPLOY MUVAFFAQIYATLI ($(date '+%F %T'))."
else echo "⚠️ Deploy bajarildi, lekin yuqorida «!!» qatorlari bor — ko'rib chiqing."; fi
echo "MUHIM: barcha kompyuter/telefonlardagi OCHIQ admin oynalarini yangilang (Ctrl+Shift+R; telefonda sahifani yopib qayta oching)."
echo "Log: $LOG    Zaxiralar: $BK (*$T*, db_*/storage_* — eng oxirgilari)"
echo "Orqaga qaytarish (faqat kerak bo'lsa): sayt — sudo tar -xzf $BK/web_$T.tgz -C /var/www"
[ -n "$RB" ] && echo "   server kodi — ${RB}sudo systemctl restart iqror-pay iqror-ai iqror-auth"
echo "   baza — faqat maslahatlashib (zaxiradan tiklash oddiy emas: migration/deploy/README.md)."
[ "$bad" = 0 ] || exit 2
