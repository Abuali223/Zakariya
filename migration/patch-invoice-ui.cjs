// patch-invoice-ui.cjs
// Jonli /var/www/iqror/index.html dagi TO'LOV (invoice) bo'limini yangi dizaynga
// o'tkazadi. Faqat invoice CSS blokini (.inv-list ... .inv-soon) va
// renderKabInvoices funksiyasini almashtiradi — boshqa hech narsaga tegmaydi.
// Har qanday oldingi versiyadan ishlaydi. Zaxira: <live>.bak
//
// Ishlatish:  node patch-invoice-ui.cjs <yangi-index.html> <jonli-index.html>
const fs = require('fs');
const NEW = process.argv[2], LIVE = process.argv[3];
if (!NEW || !LIVE) { console.error('Ishlatish: node patch-invoice-ui.cjs <yangi> <jonli>'); process.exit(1); }

const CSS_RE = /\.inv-list\{[\s\S]*?\.inv-soon\{[^}]*\}/;   // invoice CSS bloki
function fnBlock(s) {                                       // renderKabInvoices funksiyasi
  const a = 'async function renderKabInvoices(studentId){';
  const b = '\nasync function renderKabMonitoring';
  const i = s.indexOf(a); if (i < 0) return null;
  const e = s.indexOf(b, i); if (e < 0) return null;
  return s.slice(i, e);
}

const newHtml = fs.readFileSync(NEW, 'utf8');
const newCSS = (newHtml.match(CSS_RE) || [null])[0];
const newFn = fnBlock(newHtml);
if (!newCSS || !newFn) { console.error('XATO: yangi bloklar topilmadi (yangi index.html noto\'g\'ri)'); process.exit(1); }

let live = fs.readFileSync(LIVE, 'utf8');
const oldFn = fnBlock(live);
if (!CSS_RE.test(live) || !oldFn) { console.error('XATO: jonli faylda invoice bloklari topilmadi'); process.exit(1); }

fs.writeFileSync(LIVE + '.bak', live);                     // zaxira
live = live.replace(CSS_RE, () => newCSS).replace(oldFn, () => newFn);
fs.writeFileSync(LIVE, live);
console.log('OK: to\'lov UI yangilandi. Zaxira:', LIVE + '.bak');
console.log('inv-card:', (live.match(/inv-card/g) || []).length, '· inv-plogo:', (live.match(/inv-plogo/g) || []).length);
