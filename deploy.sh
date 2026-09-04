#!/usr/bin/env bash
# =====================================================================
# Iqror — bitta buyruq bilan deploy.
#   Ishlatish:  bash ~/iqror-repo/deploy.sh
# Bajaradi: kod yangilash + paketlar + frontend (admin.html + sw.js + to'lov UI) + xizmatlar.
# config.json (maxfiy kalitlar) gitignore — tegilmaydi.
# XATO BO'LSA — DARHOL to'xtaydi (jim qisman deploy YO'Q).
# =====================================================================
set -euo pipefail
BRANCH="claude/iqror-med-school-impl-iqdntl"
REPO="$HOME/iqror-repo"
WEB="/var/www/iqror"
SHIM='s#https://www.gstatic.com/firebasejs/10.12.5#/sb#g'   # Firebase importlari -> /sb shim
cd "$REPO"

echo "==> 1/5 Kod yangilanmoqda (git)..."
git fetch origin "$BRANCH"
# Server/backend + migratsiya kodi (config.json tegilmaydi — gitignore):
git checkout FETCH_HEAD -- ai-assistant payments server migration

echo "==> 2/5 Paketlar (kerak bo'lsa)..."
npm install --no-save @supabase/supabase-js @anthropic-ai/sdk ws >/dev/null 2>&1 || echo "   (npm o'tkazib yuborildi — paketlar mavjud)"

echo "==> 3/5 admin.html + sw.js (shim bilan) joylanmoqda..."
git show FETCH_HEAD:admin.html | sed "$SHIM" | sudo tee "$WEB/admin.html" >/dev/null
git show FETCH_HEAD:sw.js       | sudo tee "$WEB/sw.js"       >/dev/null
# Deploy landdid-mi? admin.html'da kutilgan marker borligini tekshiramiz:
if ! grep -q iqror_pay_outbox "$WEB/admin.html"; then echo "❌ admin.html deploy landmadi (marker yo'q)"; exit 1; fi

echo "==> 4/5 index.html (to'lov UI) yangilanmoqda..."
git show FETCH_HEAD:index.html > /tmp/iqror-new-index.html
git show FETCH_HEAD:migration/patch-invoice-ui.cjs > /tmp/iqror-patch.cjs
sudo node /tmp/iqror-patch.cjs /tmp/iqror-new-index.html "$WEB/index.html"

echo "==> 5/5 Xizmatlar qayta ishga tushmoqda..."
sudo systemctl restart iqror-ai iqror-pay
sleep 2
ai=$(systemctl is-active iqror-ai || true); pay=$(systemctl is-active iqror-pay || true)
echo "    iqror-ai:  $ai"
echo "    iqror-pay: $pay"
if [ "$ai" != "active" ] || [ "$pay" != "active" ]; then
  echo "❌ Xizmat(lar) ishga tushmadi. Log: sudo journalctl -u iqror-ai -u iqror-pay -n 50 --no-pager"; exit 1
fi

echo ""
echo "✅ Deploy tugadi (admin.html+sw.js+index.html+xizmatlar). Saytda Ctrl+Shift+R bilan yangilang."
