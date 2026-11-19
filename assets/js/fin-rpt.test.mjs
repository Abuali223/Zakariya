// fin-rpt.test.mjs — moliya hisobotlarining sof yordamchilari: admin.html FIN-RPT bloki fayldan o'qib sinaladi (audit-11).
//   node --test assets/js/fin-rpt.test.mjs
//   A6-08: to'lov usuli nomlari bitta manbadan (PROV_LBL) — o'zaro hisob ('offset') xom kalit yoki «Boshqa» emas;
//   A6-06: kassa hisoboti «Qaytarilgan (shu davrda)» — faktura VA avans qaytarishi (biriktirilmagan to'lov qaytarilishi — yo'q);
//   A6-09: «Yillik prognoz» — o'rtacha ma'lumot bor oylar bo'yicha (tizim ishga tushishidan oldingi bo'sh oylar bo'luvchiga kirmaydi).
//   A6-02 (2-raund): A4 hisobotida kassa boshqa daromadi — qisqa nom (IN-06 «kassa ortiqchasi»siz), «Kirim» izohi boshqa daromadni ham aytadi.
//   A6-04 (2-raund, avvaldan bor): o'quvchi to'lov tarixida eski 'paid' faktura ("paidAmount" bo'sh) — «To‘langan» to'liq summa (haqiqiy
//          openPayHistory, soxta getDocs bilan).
//   Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const block = (() => { const a = ADM.indexOf('// FIN-RPT:BEGIN'), b = ADM.indexOf('// FIN-RPT:END'); return a >= 0 && b > a ? ADM.slice(a, b) : ''; })();
const PROV = (ADM.match(/^const PROV_LBL = \{.*\};$/m) || [''])[0];   // haqiqiy yorliqlar (blok PROV_LBL dan foydalanadi)
const F = (() => {
  const ctx = vm.createContext({});
  vm.runInContext(PROV + '\n' + block + '\n;this.__f = { PROV_LBL, DF_PMLAB, DF_PMCOL, finPmKey, cashRefundSums, finForecast, finOtherLbl: typeof finOtherLbl === "function" ? finOtherLbl : null };', ctx);
  return ctx.__f;
})();
// Yuqori darajadagi e'lon (0-ustundan): function / async function / const — bir qatorli yoki tanasi surilgan ko'p qatorli.
function decl(name) {
  const L = ADM.split('\n');
  const i = L.findIndex(l => l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`) || new RegExp(`^const ${name}\\s*=`).test(l));
  if (i < 0) return '';
  const out = [L[i]];
  for (let j = i + 1; j < L.length; j++) { const l = L[j]; if (l === '' || /^\s/.test(l)) { out.push(l); continue; } if (l.startsWith('}')) out.push(l); break; }
  return out.join('\n');
}
// admin.html dagi paidAmt bilan bir xil: 'paid' — to'liq summa; bekor / qaytarilgan — 0; aks holda paidAmount
const paidAmt = i => i.status === 'paid' ? (Number(i.amount) || 0) : ((i.status === 'reversed' || i.status === 'canceled') ? 0 : (Number(i.paidAmount) || 0));

test('blok bitta, yordamchilar bitta joyda', () => {
  assert.ok(block.length > 0 && PROV.length > 0);
  assert.equal((ADM.match(/FIN-RPT:BEGIN/g) || []).length, 1);
  for (const n of ['finForecast', 'cashRefundSums', 'finPmKey']) assert.equal((ADM.match(new RegExp(`function ${n}\\(`, 'g')) || []).length, 1, n);
  assert.equal((ADM.match(/const DF_PMLAB=/g) || []).length, 1);
  // eski alohida nusxalar qolmagan: «Moliya» (PM) va A4 (PMlab) umumiy manbadan
  assert.ok(!/const PM=\{click:/.test(ADM), '«Moliya» sahifasidagi alohida PM nusxasi qolmasin');
  assert.ok(!/const PMlab=\{/.test(ADM), 'A4 hisobotidagi alohida PMlab nusxasi qolmasin');
});

test('A6-08: to‘lov usuli nomlari PROV_LBL dan — o‘zaro hisob xom kalit emas', () => {
  assert.equal(F.DF_PMLAB.offset, F.PROV_LBL.offset);
  assert.match(F.DF_PMLAB.offset, /O‘zaro hisob/);
  assert.equal(F.DF_PMLAB[''], 'Boshqa');
  for (const k of ['click', 'uzum', 'cash', 'bank', 'terminal', 'payme', 'mixed', 'credit']) assert.equal(F.DF_PMLAB[k], F.PROV_LBL[k], k);
  // rangi bor har usulning nomi bor (legend xom kalit ko'rsatmasin)
  for (const k of Object.keys(F.DF_PMCOL)) assert.ok(F.DF_PMLAB[k] && F.DF_PMLAB[k] !== k || k === '', 'nomsiz rang: ' + k);
  assert.ok(F.DF_PMCOL.offset && F.DF_PMCOL.offset !== F.DF_PMCOL[''], 'o‘zaro hisob — o‘z rangi («Boshqa» emas)');
  assert.equal(F.finPmKey('offset'), 'offset', '«Moliya» → «To‘lov usuli»: o‘zaro hisob «Boshqa»ga tushmasin');
  assert.equal(F.finPmKey('cash'), 'cash');
  assert.equal(F.finPmKey('noma’lum'), '');
  assert.equal(F.finPmKey(null), '');
  assert.equal(F.finPmKey('constructor'), '', 'prototip kalitlari — «Boshqa»');
});

test('A6-06: «Qaytarilgan (shu davrda)» — faktura va avans qaytarishi; biriktirilmagan to‘lov — yo‘q', () => {
  const r = F.cashRefundSums([
    { target: 'invoice', amount: 500000 }, { target: 'credit', amount: 3000000 }, { target: 'payment', amount: 700000 },
    { target: 'credit', amount: '250000' }, null, { amount: 99 } ]);
  assert.equal(r.total, 3750000);
  assert.equal(r.credit, 3250000);
  assert.deepEqual({ ...F.cashRefundSums([]) }, { total: 0, credit: 0 });
  assert.deepEqual({ ...F.cashRefundSums(null) }, { total: 0, credit: 0 });
});

test('A6-09: yillik prognoz — o‘rtacha ma’lumot bor oylar bo‘yicha', () => {
  // tizim 2026-sentabrda ishga tushgan: sentabr–noyabr, har oy 10 mln yig'ilgan
  const INV = [
    { month: '2026-09', amount: 10e6, status: 'paid' }, { month: '2026-10', amount: 10e6, status: 'paid', paidAmount: null },
    { month: '2026-11', amount: 12e6, status: 'partial', paidAmount: 10e6 }, { month: '2026-11', amount: 5e6, status: 'canceled' },
    { month: '2025-12', amount: 99e6, status: 'paid' }, { month: '2026-12', amount: 7e6, status: 'pending', paidAmount: 0 } ];
  const f = F.finForecast(INV, '2026-11', paidAmt);
  assert.equal(f.ytd, 30e6);
  assert.equal(f.n, 3, 'yanvar–avgust (ma’lumotsiz) bo‘luvchiga kirmaydi');
  assert.equal(f.avgM, 10e6, 'avval 30 mln / 11 = 2,7 mln edi');
  assert.equal(f.remaining, 1);
  assert.equal(f.projected, 40e6);
  assert.equal(f.ok, true);
  // faqat bitta oy ma'lumot — prognoz yo'q; bekor qilingan oy sanalmaydi
  const g = F.finForecast([{ month: '2026-11', amount: 10e6, status: 'paid' }, { month: '2026-10', amount: 9e6, status: 'canceled' }], '2026-11', paidAmt);
  assert.equal(g.n, 1); assert.equal(g.ok, false);
  // to'liq yil — o'rtacha 12 oyga, qolgan 0
  const full = Array.from({ length: 12 }, (_, i) => ({ month: `2027-${String(i + 1).padStart(2, '0')}`, amount: 1e6, status: 'paid' }));
  const h = F.finForecast(full, '2027-12', paidAmt);
  assert.equal(h.n, 12); assert.equal(h.remaining, 0); assert.equal(h.projected, 12e6);
  const e = F.finForecast([], '2026-11', paidAmt);
  assert.equal(e.n, 0); assert.equal(e.avgM, 0); assert.equal(e.ok, false);
});

test('A6-02 (2-raund): A4 hisobotida kassa boshqa daromadi — qisqa nom; «Kirim» izohi boshqa daromadni ham aytadi', () => {
  assert.ok(F.finOtherLbl, 'admin.html FIN-RPT: finOtherLbl yo‘q');
  assert.equal(F.finOtherLbl({ articleId: 'IN-04', nameUz: 'Forma va boshqa tovarlar sotuvi', sum: 25e6 }), 'Forma va tovarlar');
  const in06 = F.finOtherLbl({ articleId: 'IN-06', nameUz: 'Boshqa operatsion daromad (kassa ortiqchasi, hisobdan chiqarilgan qarz, jarima, beg‘araz yordam)', sum: 3e6 });
  assert.equal(in06, 'Boshqa kirim');
  assert.ok(!/ortiqcha/.test(in06), 'kassa ortiqchasi finance_other_income’da hisoblanmaydi — nomda ham bo‘lmasin');
  assert.equal(F.finOtherLbl({ articleId: 'IN-03', nameUz: 'Qo‘shimcha xizmatlar' }), 'Qo‘shimcha xizmatlar', 'boshqa statiya — o‘z nomi');
  assert.equal(F.finOtherLbl({ articleId: 'IN-09' }), 'IN-09', 'nomsiz — kodi');
  assert.equal(F.finOtherLbl(null), '');
  assert.equal(F.finOtherLbl({ articleId: 'constructor' }), 'constructor', 'prototip kaliti — nom emas');
  assert.equal((ADM.match(/function finOtherLbl\(/g) || []).length, 1);
  // A4: qator qisqa nom bilan (statiyaning to'liq nomi emas); izoh — «Kirim» = fakturalarga to'langan + kassadagi boshqa daromad
  assert.match(ADM, /row\('— boshqa daromad \(kassa\): '\+othItems\.map\(x=>esc\(finOtherLbl\(x\)\)\+' '\+S\(x\.sum\)\)/);
  assert.ok(!/othItems\.map\(x=>esc\(x\.nameUz/.test(ADM), 'to‘liq statiya nomi (x.nameUz) A4 qatorida qolmasin');
  assert.match(ADM, /«Kirim» — shu oy hisob-fakturalariga to‘langan summa \+ kassadagi boshqa daromad \(forma \/ tovar sotuvi, «Boshqa kirim»\); avans\/oldingi oy qarzi/);
  assert.ok(!ADM.includes('«Kirim» — shu oy hisob-fakturalariga to‘langan summa;'), 'eski (noto‘g‘ri) A4 izohi qolmasin');
  assert.ok(!ADM.includes('«Kirim» esa shu oy hisob-fakturalariga to‘langan summa — farq'), 'bosh sahifa izohi ham');
});

// ---- A6-04 (2-raund): o'quvchi to'lov tarixi — eski 'paid' faktura «To‘langan» (haqiqiy openPayHistory) ----
const PH = (() => {
  const ctx = vm.createContext({});
  vm.runInContext(decl('openPayHistory') + '\n;this.__p = { openPayHistory, set: o => Object.assign(this, o) };', ctx);
  return ctx.__p;
})();
async function payHistoryHtml(invs) {
  const els = {};
  const $ = sel => {
    if (sel === '#ph-fix' || sel === '#ph-cref') return null;
    return els[sel] || (els[sel] = { innerHTML: '', onclick: null, querySelectorAll: () => [] });
  };
  PH.set({
    $, openModal: () => {}, closeModal: () => {}, db: {}, SESSION: { isAdmin: false }, KASSA: { live: false },
    collection: (_db, name) => ({ name }), where: (...a) => a, query: (c, ...w) => ({ name: c.name, w }),
    getDocs: async q => ({ docs: (q.name === 'invoices' ? invs : []).map((x, i) => ({ id: 'd' + i, data: () => ({ ...x }) })) }),
    getDoc: async () => ({ exists: () => false }), doc: (...a) => a,
    tkDay: v => String(v || '').slice(0, 10), payDay: () => '', PROV_LBL: { cash: 'Naqd', click: 'Click' },
    esc: s => String(s == null ? '' : s), fmtSom: n => String(Math.round(Number(n) || 0)),
    toast: () => {}, rpc: async () => ({}), openRefund: () => {}, setDoc: async () => {}, errMsg: e => String(e),
  });
  await PH.openPayHistory('IQ-0701', 'Sinov O‘quvchi');
  return els['#ph-body'].innerHTML;
}

test('A6-04 (2-raund): to‘lov tarixi — eski \'paid\' faktura ("paidAmount" bo‘sh) to‘liq to‘langan ko‘rinadi; qisman — o‘z summasi', async () => {
  const h = await payHistoryHtml([
    { studentId: 'IQ-0701', month: '2025-09', amount: 1000000, paidAmount: null, status: 'paid', provider: 'cash', paidAt: '2025-09-05' },
    { studentId: 'IQ-0701', month: '2025-10', amount: 1000000, paidAmount: 400000, status: 'partial', provider: 'click' },
    { studentId: 'IQ-0701', month: '2025-11', amount: 1000000, paidAmount: 0, status: 'pending' } ]);
  const row = m => (h.match(new RegExp(`<tr><td>${m}</td>.*?</tr>`)) || [''])[0];
  assert.match(row('2025-09'), /<td style="text-align:right">1000000<\/td><td style="text-align:right">1000000<\/td>/, 'eski \'paid\' — To‘langan = summa (avval 0)');
  assert.match(row('2025-10'), /<td style="text-align:right">1000000<\/td><td style="text-align:right">400000<\/td>/);
  assert.match(row('2025-11'), /<td style="text-align:right">1000000<\/td><td style="text-align:right">0<\/td>/);
  assert.match(decl('openPayHistory'), /const invPaid=invs\.reduce\(\(s,i\)=>s\+invPaidOf\(i\),0\);/, 'diagnostika ham shu qoida bilan');
});
