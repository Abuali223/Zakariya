#!/usr/bin/env bash
# =====================================================================
# Iqror — bitta buyruq bilan deploy.
#   Ishlatish:  bash ~/iqror-repo/deploy.sh
# Bajaradi: kod yangilash + paketlar + SQL migratsiya + frontend
#   (admin.html + sw.js + index.html + /sb shimlar) + xizmatlar.
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

echo "==> 1/6 Kod yangilanmoqda (git)..."
git fetch origin "$BRANCH"
# Server/backend + migratsiya + shim kodi (config.json/sb-config.js tegilmaydi — gitignore):
git checkout FETCH_HEAD -- ai-assistant payments server migration sb

echo "==> 2/6 Paketlar (kerak bo'lsa)..."
npm install --no-save @supabase/supabase-js @anthropic-ai/sdk ws >/dev/null 2>&1 || echo "   (npm o'tkazib yuborildi — paketlar mavjud)"

echo "==> 3/6 SQL migratsiyalar (idempotent audit-*)..."
# Deploy va baza sinxron bo'lsin: yangi frontend eski bazaга tushmasin (masalan apply_payment
# RPC / student_phones view / RLS tuzatmalari). audit-*.sql fayllari QAYTA ishga tushirishга xavfsiz.
if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONT"; then
  for f in audit-2.sql audit-3.sql audit-4.sql; do
    echo "    -> $f"
    if ! sudo docker exec -i "$DB_CONT" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q < "$REPO/migration/$f" >/tmp/iqror-sql.log 2>&1; then
      echo "❌ SQL migratsiya xato: $f"; tail -8 /tmp/iqror-sql.log; exit 1
    fi
  done
  echo "    ✓ migratsiyalar qo'llandi"
else
  echo "⚠️ '$DB_CONT' konteyneri topilmadi — SQL migratsiyalarni QO'LDA ishga tushiring, so'ng qayta deploy:"
  echo "   sudo docker exec -i $DB_CONT psql -U postgres -d postgres < migration/audit-4.sql"
  exit 1
fi

echo "==> 4/6 /sb shimlar joylanmoqda (sb-config.js TEGILMAYDI)..."
sudo mkdir -p "$WEB/sb"
for f in _core.js firebase-app.js firebase-auth.js firebase-firestore.js firebase-storage.js firebase-analytics.js; do
  git show "FETCH_HEAD:sb/$f" | sudo tee "$WEB/sb/$f" >/dev/null
done
if ! grep -q "function rpc" "$WEB/sb/firebase-firestore.js"; then echo "❌ /sb shim eski (rpc yo'q)"; exit 1; fi

echo "==> 5/6 admin.html + sw.js + index.html (shim bilan) joylanmoqda..."
sudo cp "$WEB/admin.html" "$WEB/admin.html.bak" 2>/dev/null || true   # zaxira (rollback uchun)
sudo cp "$WEB/sw.js"      "$WEB/sw.js.bak"      2>/dev/null || true
sudo cp "$WEB/index.html" "$WEB/index.html.bak" 2>/dev/null || true
git show FETCH_HEAD:admin.html | sed "$SHIM" | sudo tee "$WEB/admin.html" >/dev/null
git show FETCH_HEAD:sw.js       | sudo tee "$WEB/sw.js"       >/dev/null
git show FETCH_HEAD:index.html | sed "$SHIM" | sudo tee "$WEB/index.html" >/dev/null
# Legacy sahifalar ham Supabase shim bilan (Firebase -> /sb): imtihon (o'qituvchi tanlovi),
# verify (hujjat tekshiruvi), oquv-platforma (o'quv platforma cloud-sync).
for f in imtihon.html verify.html oquv-platforma.html; do
  sudo cp "$WEB/$f" "$WEB/$f.bak" 2>/dev/null || true
  git show "FETCH_HEAD:$f" | sed "$SHIM" | sudo tee "$WEB/$f" >/dev/null
done
# Markerlar (deploy landdi-mi?):
grep -q iqror_pay_outbox "$WEB/admin.html" || { echo "❌ admin.html deploy landmadi"; exit 1; }
grep -q "apply_payment"  "$WEB/admin.html" || { echo "❌ admin.html eski (apply_payment yo'q)"; exit 1; }
grep -q kab-subjbars     "$WEB/index.html" || { echo "❌ index.html deploy landmadi"; exit 1; }
grep -q "/sb/firebase-firestore.js" "$WEB/verify.html" || { echo "❌ verify.html shim landmadi"; exit 1; }
grep -q "students_public" "$WEB/verify.html" || { echo "❌ verify.html eski (students_public yo'q)"; exit 1; }

echo "==> 6/6 Xizmatlar qayta ishga tushmoqda..."
sudo systemctl restart iqror-ai iqror-pay
sleep 2
ai=$(systemctl is-active iqror-ai || true); pay=$(systemctl is-active iqror-pay || true)
echo "    iqror-ai:  $ai"
echo "    iqror-pay: $pay"
if [ "$ai" != "active" ] || [ "$pay" != "active" ]; then
  echo "❌ Xizmat(lar) ishga tushmadi. Log: sudo journalctl -u iqror-ai -u iqror-pay -n 50 --no-pager"; exit 1
fi

echo ""
echo "✅ Deploy tugadi (SQL + /sb + admin.html + sw.js + index.html + xizmatlar). Saytda Ctrl+Shift+R bilan yangilang."
