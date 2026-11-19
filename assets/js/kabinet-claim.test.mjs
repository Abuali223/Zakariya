// kabinet-claim.test.mjs — ota-ona kabineti (index.html), audit 2026-11-18 mustaqil tekshiruv 2-raund (A7-01, A7-09):
//   1) Direktor tasdig'ini kutayotgan farzand bog'lanishi (kod ko'radigan xodim hisobi) kabinetda «⏳ Direktor tasdig'ini kutmoqda»
//      belgisi bilan ko'rinadi va × bilan bekor qilinadi — avval jim yo'qolar, kabinet «Farzandlaringiz 0» deb turardi. Farzand
//      ma'lumoti ochilmaydi (tugma o'chirilgan).
//   2) Telegram «Uzish» faqat kartada ko'rsatilgan bog'lanishni uzadi (linkId) — bitta oila hisobida ikki ota-onaning Telegrami bo'lsa,
//      ikkinchisi jim uzilmasin.
//   Funksiyalar index.html'dan o'qiladi (renderKabinet, renderKabTelegram), DOM — soxta. Ma'lumotlar to'qima.
//   node --test assets/js/kabinet-claim.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const IDX = readFileSync(new URL('../../index.html', import.meta.url), 'utf8');
// Yuqori darajadagi funksiya: «function nom(» / «async function nom(» qatoridan 0-ustundagi «}» gacha.
function fnSrc(name) {
  const L = IDX.split('\n'), i = L.findIndex(l => l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`));
  if (i < 0) return '';
  const out = [L[i]];
  for (let j = i + 1; j < L.length; j++) { out.push(L[j]); if (L[j].startsWith('}')) break; }
  return out.join('\n');
}
const KAB = fnSrc('renderKabinet'), TG = fnSrc('renderKabTelegram');

// Soxta element: innerHTML dagi data-* tugmalari querySelectorAll bilan topiladi (onclick'ni sinov chaqiradi).
function el() {
  const e = { innerHTML: '', style: {}, value: '', disabled: false, onclick: null, _btn: {} };
  e.querySelectorAll = sel => {
    const m = /^\[data-([a-z]+)\]$/.exec(sel); if (!m) return [];
    const key = m[1], re = new RegExp(`data-${key}="([^"]*)"`, 'g'), out = [];
    let x; while ((x = re.exec(e.innerHTML))) { const b = { dataset: { [key]: x[1] }, onclick: null }; out.push(b); (e._btn[key] = e._btn[key] || []).push(b); }
    return out;
  };
  return e;
}
function ctxFor({ childIds = [], pending = [], links = [] } = {}) {
  const els = { '#kabinet-body': el(), '#kab-tg': el(), '#kab-tg-off': el(), '#kab-tg-out': el(), '#kab-msg': el() };
  const calls = { removed: [], tg: [] };
  const T = { uz: new Proxy({}, { get: (o, k) => (typeof k === 'string' ? k : undefined) }) };   // matn o'rniga kalit nomi
  const ctx = vm.createContext({
    T, lang: 'uz', esc: s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    $: s => els[s] || null, confirm: () => true, findStudent: () => null, studentCardHTML: () => '', renderKabBus: () => {},
    window: {
      IqrorAuth: {
        getUser: () => ({ uid: 'U_SINOV' }), getChildIds: () => childIds.slice(), getActiveChild: () => childIds[0] || '',
        getPendingChildIds: () => pending.slice(), async removeChild(id) { calls.removed.push(id); pending = pending.filter(x => x !== id); },
        async setActiveChild() {}, async addChild() { return { ok: false }; },
      },
      IqrorFB: { async tgCall(name, body) { calls.tg.push([name, body]); return name === 'tg-link-status' ? { ok: true, configured: true, links } : { ok: true }; } },
    },
  });
  vm.runInContext(KAB + '\n' + TG + '\n;this.__k = renderKabinet; this.__t = renderKabTelegram;', ctx);
  return { ctx, els, calls };
}

test('index.html: renderKabinet / renderKabTelegram topildi, tarjimalar bor', () => {
  assert.ok(KAB.length > 0 && TG.length > 0);
  assert.ok(IDX.includes('kab_pending_chip:"Direktor tasdig‘ini kutmoqda"'), 'o‘zbekcha');
  assert.ok(IDX.includes('kab_pending_chip:"Ожидает подтверждения директора"'), 'ruscha');
  assert.ok(IDX.includes("getPendingChildIds: ()=>pendingChildIds.filter(x=>!childIds.includes(x)),"), 'IqrorAuth');
  assert.ok(IDX.includes("pendingChildIds=rows.filter(x=>String(x.status||'')==='pending')"), 'loadChildIds kutilayotganlarni ham o‘qiydi');
});

test('A7-01: faol farzandsiz, bitta kutilayotgan — belgi ko‘rinadi, ochilmaydi; × bekor qiladi', async () => {
  const { ctx, els, calls } = ctxFor({ pending: ['IQ-0009'] });
  ctx.__k();
  const h = els['#kabinet-body'].innerHTML;
  assert.match(h, /<b>IQ-0009<\/b><span>⏳ kab_pending_chip<\/span>/);
  assert.match(h, /<button class="kab-chip-main" type="button" disabled/, 'farzand ma’lumoti ochilmaydi');
  assert.match(h, /data-rm="IQ-0009"/);
  assert.ok(!/data-sel="IQ-0009"/.test(h), 'tanlab bo‘lmaydi');
  const rm = els['#kabinet-body']._btn.rm[0];
  await rm.onclick({ stopPropagation() {} });
  assert.deepEqual(calls.removed, ['IQ-0009']);
});

test('A7-01: faol farzand + kutilayotgan — ikkalasi bir qatorda, faoli tanlanadi, kutilayotgani o‘chirilgan', () => {
  const { ctx, els } = ctxFor({ childIds: ['IQ-0001'], pending: ['IQ-0009'] });
  ctx.__k();
  const h = els['#kabinet-body'].innerHTML;
  assert.match(h, /data-sel="IQ-0001"/);
  assert.match(h, /<b>IQ-0009<\/b><span>⏳ kab_pending_chip<\/span>/);
  assert.match(h, /<span class="kab-cnt">1<\/span>/, 'son — faol farzandlar');
});

test('A7-09: «Uzish» faqat kartadagi bog‘lanishni uzadi (linkId)', async () => {
  const links = [
    { id: 'L_OTA', kind: 'parent', status: 'active', students: ['IQ-0001'] },
    { id: 'L_ONA', kind: 'parent', status: 'active', students: ['IQ-0001'] },
    { id: 'L_STAFF', kind: 'staff', status: 'active' },
  ];
  const { ctx, els, calls } = ctxFor({ childIds: ['IQ-0001'], links });
  await ctx.__t();
  assert.match(els['#kab-tg'].innerHTML, /id="kab-tg-off"/);
  await els['#kab-tg-off'].onclick();
  const un = calls.tg.filter(c => c[0] === 'tg-unlink');
  assert.equal(un.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(un[0][1])), { linkId: 'L_OTA' });
});
