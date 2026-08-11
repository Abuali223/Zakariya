// patch-invoice-ui.cjs
// Jonli /var/www/iqror/index.html dagi TO'LOV (invoice) bo'limini yangi dizaynga
// o'tkazadi. Yangi bloklarni yangi index.html dan oladi, jonli fayldagi ESKI
// bloklarnigina almashtiradi — boshqa hech narsaga (Supabase ulanishi, skriptlar)
// tegmaydi. Zaxira: <live>.bak
//
// Ishlatish:  node patch-invoice-ui.cjs <yangi-index.html> <jonli-index.html>
const fs = require('fs');
const NEW  = process.argv[2];   // yangi versiya (git'dan)
const LIVE = process.argv[3];   // jonli fayl (/var/www/iqror/index.html)
if (!NEW || !LIVE) { console.error('Ishlatish: node patch-invoice-ui.cjs <yangi> <jonli>'); process.exit(1); }

function slice(str, a, b, incEnd) {
  const s = str.indexOf(a); if (s < 0) return null;
  const e = str.indexOf(b, s); if (e < 0) return null;
  return str.slice(s, incEnd ? e + b.length : e);
}

const newHtml = fs.readFileSync(NEW, 'utf8');
const newCSS = slice(newHtml,
  '.inv-list{display:flex;flex-direction:column;gap:12px}',
  '.inv-soon{margin-top:12px;font-size:13px;color:var(--muted)}', true);
const newFn = slice(newHtml,
  'async function renderKabInvoices(studentId){',
  '\nasync function renderKabMonitoring', false);
if (!newCSS || !newFn) { console.error('XATO: yangi bloklar topilmadi (yangi index.html eski bo\'lishi mumkin)'); process.exit(1); }

let live = fs.readFileSync(LIVE, 'utf8');
const oldCSS = slice(live,
  '.inv-list{display:flex;flex-direction:column;gap:8px}',
  '.inv-paid{color:#1d7a44;font-weight:700;font-size:14px}', true);
const oldFn = slice(live,
  'async function renderKabInvoices(studentId){',
  '\nasync function renderKabMonitoring', false);
if (!oldCSS || !oldFn) {
  console.error('XATO: jonli faylda eski bloklar topilmadi. Ehtimol allaqachon yangilangan (inv-card bormi tekshiring).');
  process.exit(1);
}

fs.writeFileSync(LIVE + '.bak', live);                 // zaxira
live = live.replace(oldCSS, () => newCSS).replace(oldFn, () => newFn);
fs.writeFileSync(LIVE, live);
console.log('OK: to\'lov UI yangilandi.');
console.log('Zaxira nusxa:', LIVE + '.bak');
console.log('inv-card belgilari:', (live.match(/inv-card/g) || []).length);
