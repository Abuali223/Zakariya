// platforma-ui.test.mjs — audit-11 (A8-04, A8-05): sahifalar matni va yuklash chegarasi.
//   node --test assets/js/platforma-ui.test.mjs
//   A8-04: admin.html video chegarasi (VIDEO_MAX_MB) api.iqror.uz nginx'idagi client_max_body_size ichida bo'lsin
//          (migration/deploy/nginx.conf.example) — aks holda katta fayl serverda 413 bilan, tushunarsiz xato bilan yiqiladi.
//   A8-05: foydalanuvchiga ko'rinadigan matnda (HTML matni / atributi, JS satri va shabloni) lotin va kirill harflari BITTA so'zda
//          aralashmasin («Yo‘lга chiqdim», «printerда») va «lotincha»ga kirill qo'shimchasi yopishmasin («Tahrirlash»да).
//          Izohlar, regex sinflari ([a-zа-я]) va kod tekshirilmaydi; butunlay ruscha / kirillcha matn (ru tarjimalar, KO-2
//          shaklidagi «Олдим») — aralash so'z emas.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = p => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');

test('A8-04: video chegarasi nginx client_max_body_size ichida (multipart zaxirasi bilan), forma va xabar shu qiymatdan', () => {
  const adm = read('admin.html'), ngx = read('migration/deploy/nginx.conf.example');
  const mb = Number((adm.match(/const VIDEO_MAX_MB=(\d+);/) || [])[1]);
  assert.ok(mb > 0, 'VIDEO_MAX_MB topilmadi');
  const api = ngx.slice(ngx.indexOf('server_name api.iqror.uz'));
  const lim = Number((api.match(/client_max_body_size\s+(\d+)m;/) || [])[1]);
  assert.ok(lim > 0, 'api.iqror.uz client_max_body_size topilmadi');
  assert.ok(mb * 1000 * 1000 + 64 * 1024 <= lim * 1024 * 1024, `video ${mb} MB > nginx ${lim}m`);
  assert.match(adm, /f\.size>VIDEO_MAX_MB\*1000\*1000/, 'tekshiruv VIDEO_MAX_MB bilan');
  assert.match(adm, /qisqa video \(maks\. \$\{VIDEO_MAX_MB\} MB\)/, 'forma izohi VIDEO_MAX_MB bilan');
  assert.doesNotMatch(adm, /f\.size>80\*1024\*1024|qisqa video \(maks\. 80MB\)|Video 80MB dan katta/, 'eski 80 MB va’dasi qolmasin');
});

// ---- A8-05: kichik leksik tahlil (izoh / satr / regex / kod) ----
// Kontekst: 'h' — HTML matni va atributi, 's' — JS satri / shabloni, 'c' — izoh, 'r' — regex, 'k' — kod, 'x' — CSS.
function jsLex(src, base, out) {
  const n = src.length, stack = []; let i = 0, prevSig = '', prevWord = '';
  const mark = (a, b, lab) => { for (let k = a; k < b; k++) out[base + k] = lab; };
  const tmplEnd = from => { let j = from; while (j < n) { if (src[j] === '\\') { j += 2; continue; } if (src[j] === '`' || (src[j] === '$' && src[j + 1] === '{')) break; j++; } return j; };
  const afterTmpl = j => { if (j < n && src[j] === '`') { prevSig = '`'; return j + 1; } if (j < n) { stack.push(0); prevSig = '{'; return j + 2; } return j; };
  while (i < n) {
    const c = src[i];
    if (stack.length && c === '}' && stack[stack.length - 1] === 0) { stack.pop(); const j = tmplEnd(i + 1); mark(i + 1, j, 's'); i = afterTmpl(j); continue; }
    if (c === '{' && stack.length) stack[stack.length - 1]++;
    else if (c === '}' && stack.length) stack[stack.length - 1]--;
    if (c === '/' && src[i + 1] === '/') { let j = src.indexOf('\n', i); if (j < 0) j = n; mark(i, j, 'c'); i = j; continue; }
    if (c === '/' && src[i + 1] === '*') { let j = src.indexOf('*/', i + 2); j = j < 0 ? n : j + 2; mark(i, j, 'c'); i = j; continue; }
    if (c === '\'' || c === '"') { let j = i + 1; while (j < n && src[j] !== c && src[j] !== '\n') { if (src[j] === '\\') { j += 2; continue; } j++; } mark(i, j + 1, 's'); i = j + 1; prevSig = c; continue; }
    if (c === '`') { const j = tmplEnd(i + 1); mark(i, j, 's'); i = afterTmpl(j); continue; }
    if (c === '/' && ('(,=:[!&|?{};+-*%<>~^'.includes(prevSig) || ['return', 'typeof', 'case', 'in', 'of'].includes(prevWord))) {
      let j = i + 1, cls = false;
      while (j < n && src[j] !== '\n') { if (src[j] === '\\') { j += 2; continue; } if (src[j] === '[') cls = true; else if (src[j] === ']') cls = false; else if (src[j] === '/' && !cls) break; j++; }
      j++; while (j < n && /[a-z]/i.test(src[j])) j++;
      mark(i, j, 'r'); i = j; prevSig = '/'; continue;
    }
    if (!/\s/.test(c)) {
      if (/[\w$]/.test(c)) { let j = i; while (j < n && /[\w$]/.test(src[j])) j++; prevWord = src.slice(i, j); prevSig = 'a'; mark(i, j, 'k'); i = j; continue; }
      prevSig = c; prevWord = '';
    }
    out[base + i] = 'k'; i++;
  }
}
function contexts(text) {
  const n = text.length, out = new Array(n).fill('h'), low = text.toLowerCase(); let i = 0;
  const reS = /<script\b[^>]*>/iy, reC = /<style\b[^>]*>/iy;
  while (i < n) {
    if (text.startsWith('<!--', i)) { let j = text.indexOf('-->', i); j = j < 0 ? n : j + 3; for (let k = i; k < j; k++) out[k] = 'c'; i = j; continue; }
    reS.lastIndex = i; let m = reS.exec(text);
    if (m) { const e = i + m[0].length; let j = low.indexOf('</script>', e); if (j < 0) j = n; jsLex(text.slice(e, j), e, out); i = j; continue; }
    reC.lastIndex = i; m = reC.exec(text);
    if (m) { const e = i + m[0].length; let j = low.indexOf('</style>', e); if (j < 0) j = n; for (let k = e; k < j; k++) out[k] = 'x'; i = j; continue; }
    i++;
  }
  return out;
}
const LAT = /[A-Za-z]/, CYR = /[Ѐ-ӿ]/;
function mixedVisible(file) {
  const text = read(file), ctx = contexts(text), bad = [];
  const at = k => text.slice(0, k).split('\n').length;
  for (const m of text.matchAll(/[\p{L}\p{M}]+(?:[‘’'ʼʻ`][\p{L}\p{M}]+)*/gu)) {
    // «\nОплата» — satr ichidagi \n (yangi qator) va keyingi so'z, aralash so'z emas
    const w = text[m.index - 1] === '\\' ? m[0].slice(1) : m[0];
    if (LAT.test(w) && CYR.test(w) && 'hs'.includes(ctx[m.index])) bad.push(`${file}:${at(m.index)} ${w}`);
  }
  for (const m of text.matchAll(/«[^«»\n]*[A-Za-z][^«»\n]*»(?=[Ѐ-ӿ])/g)) {
    const k = m.index + m[0].length;
    if ('hs'.includes(ctx[k])) bad.push(`${file}:${at(k)} ${m[0]}${text.slice(k, k + 4)}`);
  }
  return bad;
}

test('A8-05: tahlilchi o‘zi — izoh, regex sinfi va butunlay kirillcha so‘z hisoblanmaydi; satr va HTML matni — hisoblanadi', () => {
  const t = '<p>Yo‘lга</p><script>// telefonда\nconst a=/[a-zа-я]/, b=\'printerда\', c=`x ${1}kabinetда`, d=\'Олдим\';</script><!-- faylда -->';
  const ctx = contexts(t), words = [];
  for (const m of t.matchAll(/[\p{L}\p{M}]+(?:[‘’'ʼʻ`][\p{L}\p{M}]+)*/gu)) if (LAT.test(m[0]) && CYR.test(m[0]) && 'hs'.includes(ctx[m.index])) words.push(m[0]);
  assert.deepEqual(words, ['Yo‘lга', 'printerда', 'kabinetда']);
});

for (const f of ['haydovchi.html', 'index.html', 'admin.html', 'taqdimot.html', 'prezentatsiya.html']) {
  test(`A8-05: ${f} — ko‘rinadigan matnda aralash (lotin + kirill) so‘z yo‘q`, () => {
    assert.deepEqual(mixedVisible(f), []);
  });
}
