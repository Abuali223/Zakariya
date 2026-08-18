#!/usr/bin/env bash
# =====================================================================
# Iqror — bitta buyruq bilan deploy.
#   Ishlatish:  bash ~/iqror-repo/deploy.sh
# Bajaradi: kod yangilash + paketlar + frontend (to'lov UI) + xizmatlar.
# config.json (maxfiy kalitlar) gitignore — tegilmaydi.
# =====================================================================
set -e
BRANCH="claude/iqror-med-school-impl-iqdntl"
REPO="$HOME/iqror-repo"
cd "$REPO"

echo "==> 1/4 Kod yangilanmoqda (git)..."
git fetch origin "$BRANCH" >/dev/null 2>&1
# Faqat server/backend kodi (index.html/admin.html local o'zgarishlariga tegmaymiz):
git checkout FETCH_HEAD -- ai-assistant payments server migration 2>/dev/null || true

echo "==> 2/4 Paketlar (kerak bo'lsa)..."
npm install --no-save @supabase/supabase-js @anthropic-ai/sdk ws >/dev/null 2>&1 || true

echo "==> 3/4 Frontend (to'lov UI) yangilanmoqda..."
git show FETCH_HEAD:index.html > /tmp/iqror-new-index.html
git show FETCH_HEAD:migration/patch-invoice-ui.cjs > /tmp/iqror-patch.cjs
sudo node /tmp/iqror-patch.cjs /tmp/iqror-new-index.html /var/www/iqror/index.html || echo "   (frontend patch o'tkazib yuborildi)"

echo "==> 4/4 Xizmatlar qayta ishga tushmoqda..."
sudo systemctl restart iqror-ai iqror-pay 2>/dev/null || true
sleep 1
echo "    iqror-ai:  $(systemctl is-active iqror-ai 2>/dev/null || echo yoq)"
echo "    iqror-pay: $(systemctl is-active iqror-pay 2>/dev/null || echo yoq)"

echo ""
echo "✅ Deploy tugadi. Saytda Ctrl+Shift+R bilan yangilang."
