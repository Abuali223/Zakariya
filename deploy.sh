#!/usr/bin/env bash
# =====================================================================
# Iqror — bitta buyruq bilan deploy.
#   Ishlatish:  bash ~/iqror-repo/deploy.sh          (sudo'SIZ — oddiy foydalanuvchi sifatida)
# Bajaradi: kod yangilash (deploy.sh O'ZINI ham) + paketlar + SQL migratsiya (kanonik run-all.sql,
#   BITTA tranzaksiyada) + frontend (admin.html + sw.js + index.html + /sb shimlar) + xizmatlar +
#   baza holati tekshiruvi (prod == repo'dagi kanonik holat?).
# config.json (maxfiy kalitlar) va sb/sb-config.js gitignore — TEGILMAYDI.
# XATO BO'LSA — DARHOL to'xtaydi (jim qisman deploy YO'Q). Xizmat kod papkasi (/opt/iqror) yozib bo'lmasa —
#   bazaga va saytga TEGISHDAN OLDIN to'xtaydi.
# =====================================================================
set -euo pipefail
BRANCH="claude/iqror-med-school-impl-iqdntl"
REPO="$HOME/iqror-repo"
WEB="/var/www/iqror"
DB_CONT="${DB_CONT:-supabase-db}"
SHIM='s#https://www.gstatic.com/firebasejs/10.12.5#/sb#g'   # Firebase importlari -> /sb shim
# sudo bilan EMAS: `sudo bash deploy.sh` HOME=/root qiladi (repo topilmaydi), `sudo -E` esa butun deploy'ni root qilib, repo'da
#   root egali fayllar qoldiradi. (Serverga to'g'ridan-to'g'ri root bo'lib kirilgan bo'lsa — SUDO_USER yo'q — mumkin.)
if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
  echo "❌ deploy.sh'ni sudo'SIZ ishga tushiring: bash ~/iqror-repo/deploy.sh   (kerakli joylarda o'zi sudo so'raydi)"; exit 1
fi
cd "$REPO" 2>/dev/null || { echo "❌ $REPO topilmadi. deploy.sh'ni sudo'SIZ ishga tushiring: bash ~/iqror-repo/deploy.sh"; exit 1; }

echo "==> 1/7 Kod yangilanmoqda (git)..."
git fetch origin "$BRANCH"
# deploy.sh O'ZINI ham yangilaydi: diskdagi nusxa branchdagidan farq qilsa — yangisini olib, QAYTA ishga
#   tushadi. (Eski deploy.sh eski migratsiya ro'yxati bilan ishlab, yangi migratsiyani o'tkazib yuborishining
#   oldini oladi — masalan avvalgi PGRST204 holati.) IQROR_DEPLOY_REEXEC cheksiz aylanishdan saqlaydi.
if [ "${IQROR_DEPLOY_REEXEC:-}" != "1" ] && ! git diff --quiet FETCH_HEAD -- deploy.sh 2>/dev/null; then
  echo "    deploy.sh yangilandi — yangi versiya bilan qayta ishga tushirilmoqda..."
  git checkout FETCH_HEAD -- deploy.sh
  IQROR_DEPLOY_REEXEC=1 exec bash "$REPO/deploy.sh" "$@"
fi
# Server/backend + migratsiya + shim + AUTH kodi (config.json/sb-config.js tegilmaydi — gitignore).
#   auth/ ham: avval ro'yxatda yo'q edi — frontend (index.html, sb/auth-api.js) va umumiy modullar (server/,
#   payments/sms.cjs) yangilanib, auth serveri ESKI kod bilan qolardi.
git checkout FETCH_HEAD -- ai-assistant payments server migration sb auth
# Vaqtinchalik fayllar — har ishga tushishda YANGI shaxsiy papkada. (Avval qat'iy /tmp/iqror-sql.log edi: avvalgi
#   `sudo` ishga tushirishdan qolgan root egali fayl soxta «migratsiya xato» ko'rsatardi.) Faqat yo'li chiqishda
#   aytilganda (SQL xatosi — KEEP=1) qoldiriladi, aks holda o'chiriladi.
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/iqror-deploy.XXXXXX")
SQL_LOG="$TMPD/sql.log"; KEEP=0
trap 'rc=$?; [ "$KEEP" = 1 ] || rm -rf "$TMPD"; exit $rc' EXIT

echo "==> 2/7 Paketlar (kerak bo'lsa) + oldindan tekshiruv (xizmatlar, kod papkasi)..."
npm install --no-save @supabase/supabase-js @anthropic-ai/sdk ws >/dev/null 2>&1 || echo "   (npm o'tkazib yuborildi — paketlar mavjud)"
# Xizmat YOQILGAN yoki ishlayotgan bo'lsa qayta ishga tushadi (iqror-auth: telefon+parol+OTP — avval deploy uni tashlab
#   ketardi). Ataylab o'chirilgan (disabled va to'xtagan) yoki masklangan xizmatga tegilmaydi (masalan Eskiz shabloni hali
#   tasdiqlanmagan auth; avval masklangan iqror-ai/iqror-pay deployni soxta «BOSHLANMADI» yoki restart xatosi bilan to'xtatardi).
#   O'rnatilmagan unit (masalan iqror-ai yo'q) — ogohlantirib o'tkaziladi (avval `systemctl restart` xatosi deployni
#   baza va sayt yangilangandan KEYIN uzib qo'yardi).
SERVICES=""
for s in iqror-ai iqror-pay iqror-auth; do
  if ! systemctl cat "$s" >/dev/null 2>&1; then
    [ "$s" = iqror-auth ] || echo "⚠️  $s xizmati o'rnatilmagan — qayta ishga tushirilmaydi"; continue
  fi
  if [ "$(systemctl is-enabled "$s" 2>/dev/null || true)" = masked ]; then echo "⚠️  $s xizmati masklangan — tegilmaydi"; continue; fi
  if systemctl is-enabled --quiet "$s" 2>/dev/null || systemctl is-active --quiet "$s" 2>/dev/null; then SERVICES="$SERVICES $s"
  else echo "⚠️  $s xizmati o'chirilgan (disabled, ishlamayapti) — qayta ishga tushirilmaydi"; fi
done
SERVICES="${SERVICES# }"
# Xizmat kodi QAYSI papkadan ishlaydi (systemd WorkingDirectory)? Deploy kodni $REPO da yangilaydi; namuna unit'lar
#   (migration/deploy/*.service) esa /opt/iqror dan ishlaydi. Boshqa papka bo'lsa — server kodi O'SHA papkaga ham
#   yoziladi (6-bosqich; faqat git'dagi fayllar: config.json, node_modules, backups/, supabase/ va boshqalar TEGILMAYDI),
#   aks holda qayta ishga tushirish ESKI kodni ishlatardi. Fayllar papka EGASI nomidan yoziladi: config.json va boshqa
#   git'da yo'q fayllarning egasi/ruxsati, mavjud papkalarning egasi/ruxsati O'ZGARMAYDI (avvalgi `chown -R` maxfiy
#   config.json'ni root'ga o'tkazib, xizmat uni o'qiy olmay qolishi mumkin edi).
#   Hammasi SHU YERDA, bazaga tegishdan OLDIN tekshiriladi (sudo bilan — /opt/iqror 0750 bo'lsa ham ko'radi): egasi
#   yoza olmaydigan papka (masalan qo'lda `sudo cp -r` qilingan root egali server/) bo'lsa yoki papka server kodiga
#   o'xshamasa — deploy BOSHLANMAYDI (avval yarim yo'lda tar xatosi bilan to'xtab, /opt aralash qolardi yoki jim
#   o'tkazib yuborilib, xizmatlar ESKI kod bilan qayta ishga tushardi).
REPO_REAL=$(realpath -m "$REPO"); SYNC=""   # SYNC: "papka:uid:gid" qatorlari (6-bosqich uchun)
CODE_DIRS=$(git ls-tree -r -t FETCH_HEAD ai-assistant payments server sb auth | awk '$2=="tree"{print $4}')
# WorkingDirectory yo'q unit (masalan ExecStart=/usr/bin/node /srv/x/payments/index.cjs) — kod papkasi ExecStart'dagi
#   absolyut yo'llardan yuqoriga qarab topiladi (payments/, ai-assistant/ yoki auth/ bor papka). Avval jim o'tkazilardi.
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
for svc in $SERVICES; do
  wd=$(systemctl show -p WorkingDirectory --value "$svc" 2>/dev/null || true)
  # «WorkingDirectory=-/opt/iqror» systemctl show'da «!/opt/iqror», «WorkingDirectory=~» — «~» (unit User'ining uyi).
  wd=${wd#!}
  if [ "$wd" = "~" ]; then wd=$(getent passwd "$(systemctl show -p User --value "$svc" 2>/dev/null || true)" | cut -d: -f6 || true); fi
  case "$wd" in ''|/*) ;; *)
    echo "❌ $svc: WorkingDirectory=«$wd» — absolyut yo'l emas, kod papkasini aniqlab bo'lmadi. Deploy BOSHLANMADI (baza va sayt o'zgarmadi)."
    echo "   Unit'da WorkingDirectory=/opt/iqror bo'lsin (migration/deploy/*.service)."; exit 1 ;;
  esac
  if [ -z "$wd" ]; then
    wd=$(exec_code_dir "$svc")
    if [ -z "$wd" ]; then
      if [ "${IQROR_ALLOW_UNSYNCED:-}" = "1" ]; then echo "⚠️  $svc: WorkingDirectory yo'q, kod papkasi topilmadi — YANGILANMAYDI (IQROR_ALLOW_UNSYNCED=1)"; continue; fi
      echo "❌ $svc: WorkingDirectory yo'q va ExecStart'dan server kodi papkasi topilmadi — kod qayerdan ishlashi noma'lum."
      echo "   Deploy BOSHLANMADI (baza va sayt o'zgarmadi). Unit'ga WorkingDirectory=/opt/iqror qo'shing (migration/deploy/*.service),"
      echo "   yoki shu xizmatni eski kod bilan qoldirib davom eting: IQROR_ALLOW_UNSYNCED=1 bash ~/iqror-repo/deploy.sh"; exit 1
    fi
  fi
  wd=$(realpath -m "$wd")
  case "$wd/" in "$REPO_REAL/"*) continue;; esac   # repo (yoki uning ichi) — git checkout allaqachon yangiladi
  case $'\n'"$SYNC" in *$'\n'"$wd:"*) continue;; esac
  if ! { sudo test -d "$wd/payments" || sudo test -d "$wd/ai-assistant" || sudo test -d "$wd/auth"; }; then
    if [ "${IQROR_ALLOW_UNSYNCED:-}" = "1" ]; then
      echo "⚠️  $svc WorkingDirectory=$wd — server kodi papkasiga o'xshamaydi, YANGILANMAYDI (IQROR_ALLOW_UNSYNCED=1)"; continue
    fi
    echo "❌ $svc WorkingDirectory=$wd — server kodi papkasiga o'xshamaydi (payments/, ai-assistant/, auth/ yo'q)."
    echo "   Deploy BOSHLANMADI (baza va sayt o'zgarmadi). migration/deploy/README.md, «Xizmat papkasi»."
    echo "   Shu xizmatni eski kod bilan qoldirib davom etish: IQROR_ALLOW_UNSYNCED=1 bash ~/iqror-repo/deploy.sh"; exit 1
  fi
  ref="$wd/payments"; sudo test -e "$ref" || ref="$wd"
  own=$(sudo stat -c %u "$ref"); grp=$(sudo stat -c %g "$ref")
  if ! getent passwd "$own" >/dev/null; then
    echo "❌ $ref egasi (uid $own) tizimda yo'q — deploy BOSHLANMADI. Papka egasini mavjud foydalanuvchiga o'zgartiring: sudo chown -R <user> $wd/{ai-assistant,payments,server,sb,auth}"; exit 1
  fi
  oname=$(getent passwd "$own" | cut -d: -f1); gname=$(getent group "$grp" | cut -d: -f1 || true)
  # Mavjud kod papkalari (root ko'radi) — egasi ularga yoza olishi SHART; yo'qlari 6-bosqichda egasi nomiga yaratiladi.
  have=$(cd / && sudo bash -c 'for d; do [ -d "$d" ] && printf "%s\n" "$d"; done; true' _ $(for d in $CODE_DIRS; do printf '%s ' "$wd/$d"; done)) \
    || { echo "❌ $wd kod papkalarini tekshirib bo'lmadi (sudo) — deploy BOSHLANMADI"; exit 1; }
  # Egasi nomidan 6-bosqichdagi amal sharti: papkaga kirish (cd — x), kod papkalariga yozish (w+x) va ularning EGASI bo'lish —
  #   `tar --no-overwrite-dir` (2026-07 Ubuntu tuzatmasisiz tar 1.34/1.35) mavjud papkani vaqtincha chmod qiladi: egasi
  #   bo'lmasa (guruh/boshqalarga yozish ruxsati bilan ham) 6-bosqichda baza va sayt yangilangandan keyin yiqilardi.
  nowrite=$(cd / && sudo -u "#$own" bash -c 'cd "$1" 2>/dev/null || { printf "%s\n" "$1"; exit 0; }; shift; for d; do { [ -w "$d" ] && [ -x "$d" ] && [ -O "$d" ]; } || printf "%s\n" "$d"; done; true' _ "$wd" $have) \
    || { echo "❌ «sudo -u $oname» ishlamadi — kod $oname nomidan yoziladi, sudoers'da (ALL:ALL) ruxsati kerak. Deploy BOSHLANMADI"; exit 1; }
  if [ -n "$nowrite" ]; then
    echo "❌ Xizmat kodi papkasiga «$oname» (${ref#"$wd"/} egasi) yoza olmaydi yoki uning egasi emas — deploy BOSHLANMADI (baza va sayt o'zgarmadi):"
    printf '%s\n' "$nowrite" | sed 's/^/     /'
    if printf '%s\n' "$nowrite" | grep -qx "$wd"; then
      echo "   Tuzatish: sudo chmod o+x $wd   (yoki egasini: sudo chown $oname $wd)"
    else
      echo "   Tuzatish: sudo chown -R $oname${gname:+:$gname} $(printf '%s ' $nowrite)  (config.json ruxsati o'zgarmaydi)"
    fi
    exit 1
  fi
  SYNC="$SYNC$wd:$own:$grp"$'\n'
done

echo "==> 3/7 SQL migratsiyalar (kanonik run-all.sql zanjiri — BITTA tranzaksiyada)..."
# YAGONA MANBA: migration/run-all.sql — toza o'rnatish bilan AYNAN bir xil fayllar va tartib. Avvalgi
#   qo'lda yozilgan ro'yxat run-all.sql'dan uzoqlashib (drift) prod'ni toza o'rnatishdan farqli holatda
#   qoldirardi (masalan price_table RLS har deployда admin-only'ga qaytib qolardi). Endi:
#   - butun zanjir BITTA tranzaksiyada: yo hammasi qo'llanadi, yo HECH NARSA (yarim holat yo'q, oraliq
#     RLS holati hech kimga ko'rinmaydi);
#   - har bir fayl idempotent (qayta ishga tushirishga xavfsiz, ma'lumotni o'zgartirmaydi);
#   - YANGI migratsiya qo'shish: faqat run-all.sql'ga \ir qatori (deploy.sh'ni o'zgartirish SHART EMAS).
if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONT"; then
  # migration/chain.sh — run-all.sql tartibidagi fayllarni bitta tranzaksiyali oqimga ulaydi (\ir stdin'da ishlamaydi).
  if ! bash "$REPO/migration/chain.sh" | sudo docker exec -i "$DB_CONT" psql -U postgres -d postgres -q >"$SQL_LOG" 2>&1; then
    KEEP=1
    echo "❌ SQL migratsiya xato — tranzaksiya BEKOR qilindi, baza O'ZGARMADI."
    last=$(grep -E '^-> ' "$SQL_LOG" | tail -1 | sed 's/^-> //' || true)
    echo "   Fayl: ${last:-(birinchi fayldan oldin — baza ulanishi/konteyner xatosi)}"
    { grep -E 'ERROR|FATAL|could not|connection|Error response' "$SQL_LOG" || tail -n 3 "$SQL_LOG"; } | tail -5 || true
    if grep -q 'lock timeout' "$SQL_LOG"; then
      echo "   Sabab: bazada boshqa ulanish jadvalni 20 soniyadan ko'p band qildi (uzoq tranzaksiya). Baza O'ZGARMADI —"
      echo "   bir ozdan so'ng shu buyruqni qayta ishga tushiring. Kim band qilgan:"
      echo "   sudo docker exec -i $DB_CONT psql -U postgres -d postgres -c \"select pid, state, now()-xact_start as age, left(query,60) from pg_stat_activity where xact_start is not null order by xact_start\""
    fi
    echo "   To'liq log: $SQL_LOG"; exit 1
  fi
  echo "    ✓ $(grep -c '^-> ' "$SQL_LOG") ta migratsiya fayli qo'llandi (bitta tranzaksiyada)"
  # Muhim NOTICE'lar (log ichida yo'qolib ketmasin): to'qnashuv sabab qoldirilgan to'lovlar, tozalanmagan arvoh kodlar.
  grep -E "OGOHLANTIRISH|g'ayrioddiy" "$SQL_LOG" | sed -E 's/^.*NOTICE: +/    ⚠️  /' || true
else
  echo "⚠️ '$DB_CONT' konteyneri topilmadi — SQL migratsiyalarni QO'LDA ishga tushiring, so'ng qayta deploy:"
  echo "   bash $REPO/migration/chain.sh | sudo docker exec -i <baza-konteyneri> psql -U postgres -d postgres -q"
  echo "   (konteyner nomi boshqa bo'lsa: DB_CONT=<nomi> bash ~/iqror-repo/deploy.sh)"
  exit 1
fi

echo "==> 4/7 /sb shimlar joylanmoqda (sb-config.js TEGILMAYDI)..."
# Fayllar ANIQ ruxsat bilan (0644): sudo UMASK 027 bilan yangi faylni 0640 qilib, nginx o'qiy olmasdi (403).
sudo test -d "$WEB/sb" || sudo install -d -m 0755 "$WEB/sb"
for f in _core.js firebase-app.js firebase-auth.js firebase-firestore.js firebase-storage.js firebase-analytics.js auth-api.js name-match.js; do
  git show "FETCH_HEAD:sb/$f" > "$TMPD/sbf" && sudo install -m 0644 "$TMPD/sbf" "$WEB/sb/$f"
done
if ! grep -q "function rpc" "$WEB/sb/firebase-firestore.js"; then echo "❌ /sb shim eski (rpc yo'q)"; exit 1; fi
if ! grep -q "function createDoc" "$WEB/sb/firebase-firestore.js"; then echo "❌ /sb shim eski (createDoc yo'q — admin.html yuklanmaydi)"; exit 1; fi

echo "==> 5/7 admin.html + sw.js + index.html (shim bilan) joylanmoqda..."
# Zaxira (rollback uchun) *.bak — faqat sahifa HAQIQATAN o'zgarayotganda yangilanadi: qayta ishga tushirish
#   (lock timeout, xizmat xatosidan keyin) deploydan OLDINGI nusxani yangisi bilan almashtirib yubormaydi.
put_page(){   # $1 = fayl, $2 = "shim" (Firebase importlari -> /sb)
  local f=$1 new="$TMPD/page"
  if [ "${2:-}" = shim ]; then git show "FETCH_HEAD:$f" | sed "$SHIM" > "$new"; else git show "FETCH_HEAD:$f" > "$new"; fi
  if sudo test -f "$WEB/$f" && ! sudo cmp -s "$new" "$WEB/$f"; then sudo cp "$WEB/$f" "$WEB/$f.bak"; fi
  sudo install -m 0644 "$new" "$WEB/$f"
}
put_page admin.html shim
put_page sw.js
put_page index.html shim
# Legacy sahifalar ham Supabase shim bilan (Firebase -> /sb): imtihon (o'qituvchi tanlovi),
# verify (hujjat tekshiruvi), oquv-platforma (o'quv platforma cloud-sync).
for f in imtihon.html verify.html oquv-platforma.html haydovchi.html; do put_page "$f" shim; done
# Eski QR havolalari (/verify?id=...): /verify/ papkasidagi kichik sahifa /verify.html ga yo'naltiradi (nginx o'zgarmaydi).
sudo test -d "$WEB/verify" || sudo install -d -m 0755 "$WEB/verify"
put_page verify/index.html
# Markerlar (deploy landdi-mi?):
grep -q iqror_pay_outbox "$WEB/admin.html" || { echo "❌ admin.html deploy landmadi"; exit 1; }
grep -q "apply_payment"  "$WEB/admin.html" || { echo "❌ admin.html eski (apply_payment yo'q)"; exit 1; }
grep -q kab-subjbars     "$WEB/index.html" || { echo "❌ index.html deploy landmadi"; exit 1; }
grep -q "/sb/firebase-firestore.js" "$WEB/verify.html" || { echo "❌ verify.html shim landmadi"; exit 1; }
grep -q "students_public" "$WEB/verify.html" || { echo "❌ verify.html eski (students_public yo'q)"; exit 1; }
grep -q "verify.html" "$WEB/verify/index.html" || { echo "❌ verify/index.html (eski QR yo'naltirish) landmadi"; exit 1; }
grep -q "update_bus_position" "$WEB/haydovchi.html" || { echo "❌ haydovchi.html deploy landmadi"; exit 1; }
grep -q "/sb/firebase-firestore.js" "$WEB/haydovchi.html" || { echo "❌ haydovchi.html shim landmadi"; exit 1; }
grep -q "getBusRoutes" "$WEB/index.html" || { echo "❌ index.html eski (avtobus yo'q)"; exit 1; }

echo "==> 6/7 Xizmatlar qayta ishga tushmoqda..."
while IFS=: read -r wd own grp; do
  [ -n "$wd" ] || continue
  echo "    xizmatlar kodi $wd dan ishlaydi — server kodi o'sha yerga ham yozilmoqda (config.json tegilmaydi)"
  # Yo'q yuqori papkalar (birinchi marta: auth/, sb/) — root sifatida, payments/ egasi nomiga yaratiladi (aks holda egasi
  #   root'ga tegishli /opt/iqror ichida papka yarata olmay deploy yarim yo'lda to'xtardi).
  for d in ai-assistant payments server sb auth; do sudo test -d "$wd/$d" || sudo install -d -o "$own" -g "$grp" -m 0755 "$wd/$d"; done
  # Fayl ruxsatlari ARXIVDAGIdek (0644/0755) — tizim umask'iga bog'liq emas (UMASK 027'da 0640 bo'lib, xizmat kodni o'qiy olmasdi).
  #   `tar -C` papkani ochadi (o'qish huquqi kerak) — 0751 root:root /opt/iqror'da 2-bosqich o'tib, shu yerda yiqilardi.
  #   cd bilan faqat kirish (x) kerak — 2-bosqichdagi tekshiruv bilan AYNAN bir xil.
  if ! git -c tar.umask=0022 archive FETCH_HEAD ai-assistant payments server sb auth \
      | sudo -u "#$own" sh -c 'cd "$1" && exec tar -x --no-same-owner --same-permissions --no-overwrite-dir' _ "$wd"; then
    echo "❌ $wd ga kod yozishda xato (yuqoridagi tar xabarlari). Baza va sayt allaqachon YANGI; xizmatlar qayta"
    echo "   ishga tushirilMADI (eski kod ishlab turibdi). Sababni tuzatib, deploy'ni qayta ishga tushiring."; exit 1
  fi
done <<< "$SYNC"
bad=0
if [ -n "$SERVICES" ]; then
  sudo systemctl restart $SERVICES || true
  # Holat 2 s'da bir marta emas: 5 s kutiladi va avtomatik qayta ishga tushishlar (NRestarts) sanaladi — ishga
  #   tushib, bir necha soniyadan keyin yiqiladigan xizmat ham ushlanadi.
  declare -A nr0; for svc in $SERVICES; do nr0[$svc]=$(systemctl show -p NRestarts --value "$svc" 2>/dev/null || echo 0); done
  sleep 5
  for svc in $SERVICES; do
    st=$(systemctl is-active "$svc" || true); nr=$(systemctl show -p NRestarts --value "$svc" 2>/dev/null || echo 0)
    [ "${nr:-0}" = "${nr0[$svc]:-0}" ] || st="$st (qayta-qayta yiqilmoqda)"
    echo "    $svc: $st"; [ "$st" = "active" ] || bad=1
  done
fi
if [ "$bad" = "1" ]; then
  echo "❌ Xizmat(lar) ishga tushmadi. Log: sudo journalctl $(for s in $SERVICES; do printf -- '-u %s ' "$s"; done)-n 50 --no-pager"; exit 1
fi

echo "==> 7/7 Baza holati tekshiruvi (prod == repo'dagi kanonik holat?)..."
# Vaqtinchalik bazada kanonik holatni quradi va jonli bazaga SOLISHTIRADI (jonli bazaga hech narsa yozmaydi).
#   Farq bo'lsa (masalan repo'da yo'q eski RLS policy) — ogohlantiradi; deployni to'xtatmaydi, lekin yakuniy
#   xabar ✅ emas, ⚠️ bo'ladi (🔴/🟠 qatorlarni qo'lda hal qiling).
vrc=0; DB_CONT="$DB_CONT" bash "$REPO/migration/verify-db.sh" || vrc=$?

echo ""
if [ "$vrc" = 0 ]; then
  echo "✅ Deploy tugadi (SQL + /sb + admin.html + sw.js + index.html + xizmatlar). Saytda Ctrl+Shift+R bilan yangilang."
else
  echo "⚠️ Deploy tugadi (SQL + /sb + sahifalar + xizmatlar), LEKIN 7/7 baza tekshiruvi $([ "$vrc" = 2 ] && echo "FARQ topdi" || echo "bajarilmadi") —"
  echo "   yuqoridagi 🔴/🟠 qatorlarni ko'rib chiqing, so'ng: bash ~/iqror-repo/migration/verify-db.sh"
fi
