#!/usr/bin/env bash
# =====================================================================
# Iqror — bitta buyruq bilan deploy.
#   Ishlatish:  bash ~/iqror-repo/deploy.sh
# Bajaradi: kod yangilash (deploy.sh O'ZINI ham) + paketlar + SQL migratsiya (kanonik run-all.sql,
#   BITTA tranzaksiyada) + frontend (admin.html + sw.js + index.html + /sb shimlar) + xizmatlar +
#   baza holati tekshiruvi (prod == repo'dagi kanonik holat?).
# config.json (maxfiy kalitlar) va sb/sb-config.js gitignore — TEGILMAYDI.
# XATO BO'LSA — DARHOL to'xtaydi (jim qisman deploy YO'Q).
# =====================================================================
set -euo pipefail
BRANCH="claude/iqror-med-school-impl-iqdntl"
REPO="$HOME/iqror-repo"
WEB="/var/www/iqror"
DB_CONT="supabase-db"
SHIM='s#https://www.gstatic.com/firebasejs/10.12.5#/sb#g'   # Firebase importlari -> /sb shim
cd "$REPO"

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

echo "==> 2/7 Paketlar (kerak bo'lsa)..."
npm install --no-save @supabase/supabase-js @anthropic-ai/sdk ws >/dev/null 2>&1 || echo "   (npm o'tkazib yuborildi — paketlar mavjud)"

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
  if ! bash "$REPO/migration/chain.sh" | sudo docker exec -i "$DB_CONT" psql -U postgres -d postgres -q >/tmp/iqror-sql.log 2>&1; then
    echo "❌ SQL migratsiya xato — tranzaksiya BEKOR qilindi, baza O'ZGARMADI."
    echo "   Fayl: $(grep -E '^-> ' /tmp/iqror-sql.log | tail -1 | sed 's/^-> //')"; grep -E 'ERROR' /tmp/iqror-sql.log | tail -5; exit 1
  fi
  echo "    ✓ $(grep -c '^-> ' /tmp/iqror-sql.log) ta migratsiya fayli qo'llandi (bitta tranzaksiyada)"
else
  echo "⚠️ '$DB_CONT' konteyneri topilmadi — SQL migratsiyalarni QO'LDA ishga tushiring, so'ng qayta deploy:"
  echo "   bash $REPO/migration/chain.sh | sudo docker exec -i <baza-konteyneri> psql -U postgres -d postgres -q"
  exit 1
fi

echo "==> 4/7 /sb shimlar joylanmoqda (sb-config.js TEGILMAYDI)..."
sudo mkdir -p "$WEB/sb"
for f in _core.js firebase-app.js firebase-auth.js firebase-firestore.js firebase-storage.js firebase-analytics.js auth-api.js name-match.js; do
  git show "FETCH_HEAD:sb/$f" | sudo tee "$WEB/sb/$f" >/dev/null
done
if ! grep -q "function rpc" "$WEB/sb/firebase-firestore.js"; then echo "❌ /sb shim eski (rpc yo'q)"; exit 1; fi
if ! grep -q "function createDoc" "$WEB/sb/firebase-firestore.js"; then echo "❌ /sb shim eski (createDoc yo'q — admin.html yuklanmaydi)"; exit 1; fi

echo "==> 5/7 admin.html + sw.js + index.html (shim bilan) joylanmoqda..."
sudo cp "$WEB/admin.html" "$WEB/admin.html.bak" 2>/dev/null || true   # zaxira (rollback uchun)
sudo cp "$WEB/sw.js"      "$WEB/sw.js.bak"      2>/dev/null || true
sudo cp "$WEB/index.html" "$WEB/index.html.bak" 2>/dev/null || true
git show FETCH_HEAD:admin.html | sed "$SHIM" | sudo tee "$WEB/admin.html" >/dev/null
git show FETCH_HEAD:sw.js       | sudo tee "$WEB/sw.js"       >/dev/null
git show FETCH_HEAD:index.html | sed "$SHIM" | sudo tee "$WEB/index.html" >/dev/null
# Legacy sahifalar ham Supabase shim bilan (Firebase -> /sb): imtihon (o'qituvchi tanlovi),
# verify (hujjat tekshiruvi), oquv-platforma (o'quv platforma cloud-sync).
for f in imtihon.html verify.html oquv-platforma.html haydovchi.html; do
  sudo cp "$WEB/$f" "$WEB/$f.bak" 2>/dev/null || true
  git show "FETCH_HEAD:$f" | sed "$SHIM" | sudo tee "$WEB/$f" >/dev/null
done
# Markerlar (deploy landdi-mi?):
grep -q iqror_pay_outbox "$WEB/admin.html" || { echo "❌ admin.html deploy landmadi"; exit 1; }
grep -q "apply_payment"  "$WEB/admin.html" || { echo "❌ admin.html eski (apply_payment yo'q)"; exit 1; }
grep -q kab-subjbars     "$WEB/index.html" || { echo "❌ index.html deploy landmadi"; exit 1; }
grep -q "/sb/firebase-firestore.js" "$WEB/verify.html" || { echo "❌ verify.html shim landmadi"; exit 1; }
grep -q "students_public" "$WEB/verify.html" || { echo "❌ verify.html eski (students_public yo'q)"; exit 1; }
grep -q "update_bus_position" "$WEB/haydovchi.html" || { echo "❌ haydovchi.html deploy landmadi"; exit 1; }
grep -q "/sb/firebase-firestore.js" "$WEB/haydovchi.html" || { echo "❌ haydovchi.html shim landmadi"; exit 1; }
grep -q "getBusRoutes" "$WEB/index.html" || { echo "❌ index.html eski (avtobus yo'q)"; exit 1; }

echo "==> 6/7 Xizmatlar qayta ishga tushmoqda..."
# iqror-auth (telefon+parol+OTP) — YOQILGAN yoki ishlayotgan bo'lsa qayta ishga tushadi (avval deploy uni tashlab ketardi).
#   O'rnatilgan, lekin ataylab o'chirilgan/masklangan auth'ga tegilmaydi (masalan Eskiz shabloni hali tasdiqlanmagan).
SERVICES="iqror-ai iqror-pay"
if systemctl is-enabled --quiet iqror-auth 2>/dev/null || systemctl is-active --quiet iqror-auth 2>/dev/null; then SERVICES="$SERVICES iqror-auth"; fi
# Xizmat kodi QAYSI papkadan ishlaydi (systemd WorkingDirectory)? Deploy kodni $REPO da yangilaydi; namuna unit'lar
#   (migration/deploy/*.service) esa /opt/iqror dan ishlaydi. Boshqa papka bo'lsa — server kodi O'SHA papkaga ham
#   yoziladi (faqat git'dagi fayllar: config.json, node_modules, backups/, supabase/ va boshqalar TEGILMAYDI),
#   aks holda qayta ishga tushirish ESKI kodni ishlatardi. Fayllar papka EGASI nomidan yoziladi: config.json va boshqa
#   git'da yo'q fayllarning egasi/ruxsati, mavjud papkalarning egasi/ruxsati O'ZGARMAYDI (avvalgi `chown -R` maxfiy
#   config.json'ni root'ga o'tkazib, xizmat uni o'qiy olmay qolishi mumkin edi). Egasi yoza olmasa — deploy shu yerda
#   to'xtaydi (xizmatlar qayta ishga tushirilmaydi, eski kod ishlab turadi).
REPO_REAL=$(realpath -m "$REPO"); synced=" "
for svc in $SERVICES; do
  wd=$(systemctl show -p WorkingDirectory --value "$svc" 2>/dev/null || true)
  [ -n "$wd" ] || continue
  wd=$(realpath -m "$wd"); [ "$wd" = "$REPO_REAL" ] && continue
  case "$synced" in *" $wd "*) continue;; esac
  if [ -d "$wd/payments" ] || [ -d "$wd/ai-assistant" ] || [ -d "$wd/auth" ]; then
    echo "    $svc kodi $wd dan ishlaydi — server kodi o'sha yerga ham yozilmoqda (config.json tegilmaydi)"
    ref="$wd/payments"; [ -e "$ref" ] || ref="$wd"
    own=$(sudo stat -c %u "$ref"); grp=$(sudo stat -c %g "$ref")
    if ! getent passwd "$own" >/dev/null; then
      echo "❌ $ref egasi (uid $own) tizimda yo'q — kod yozilmadi. Papka egasini mavjud foydalanuvchiga o'zgartiring: sudo chown -R <user> $wd/{ai-assistant,payments,server,sb,auth}"; exit 1
    fi
    # Yo'q yuqori papkalar (birinchi marta: auth/, sb/) — root sifatida, payments/ egasi nomiga yaratiladi (aks holda egasi
    #   root'ga tegishli /opt/iqror ichida papka yarata olmay deploy yarim yo'lda to'xtardi).
    for d in ai-assistant payments server sb auth; do [ -d "$wd/$d" ] || sudo install -d -o "$own" -g "$grp" -m 0755 "$wd/$d"; done
    # Fayl ruxsatlari ARXIVDAGIdek (0644/0755) — tizim umask'iga bog'liq emas (UMASK 027'da 0640 bo'lib, xizmat kodni o'qiy olmasdi).
    git -c tar.umask=0022 archive FETCH_HEAD ai-assistant payments server sb auth \
      | sudo -u "#$own" tar -x --no-same-owner --same-permissions --no-overwrite-dir -C "$wd"
    synced="$synced$wd "
  else
    echo "⚠️  $svc WorkingDirectory=$wd — server kodi papkasiga o'xshamaydi, yangilanmadi (migration/deploy/README.md, «Xizmat papkasi»)"
  fi
done
sudo systemctl restart $SERVICES
sleep 2
bad=0
for svc in $SERVICES; do st=$(systemctl is-active "$svc" || true); echo "    $svc: $st"; [ "$st" = "active" ] || bad=1; done
if [ "$bad" = "1" ]; then
  echo "❌ Xizmat(lar) ishga tushmadi. Log: sudo journalctl $(for s in $SERVICES; do printf -- '-u %s ' "$s"; done)-n 50 --no-pager"; exit 1
fi

echo "==> 7/7 Baza holati tekshiruvi (prod == repo'dagi kanonik holat?)..."
# Vaqtinchalik bazada kanonik holatni quradi va jonli bazaga SOLISHTIRADI (jonli bazaga hech narsa yozmaydi).
#   Farq bo'lsa (masalan repo'da yo'q eski RLS policy) — ogohlantiradi; deployni to'xtatmaydi.
bash "$REPO/migration/verify-db.sh" || echo "    (yuqoridagi farqlarni ko'rib chiqing — deploy baribir yakunlandi)"

echo ""
echo "✅ Deploy tugadi (SQL + /sb + admin.html + sw.js + index.html + xizmatlar). Saytda Ctrl+Shift+R bilan yangilang."
