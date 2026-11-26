// fin-exp.js sinovi (faqat sof qism):  node --test assets/js/fin-exp.test.mjs
//   «Buxgalteriya» xarajatlari reyestri (F2.1): taklif qilinadigan to'lov usullari, oynaning boshlang'ich holati, hujjat raqami kaliti,
//   shakl → server so'rovi (bo'sh qatorlar, majburiy maydonlar, statiya va usul mosligi, summa, izoh). Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { methodOptions, defaultMethod, articleOk, buildPayload, initForm, docNoKey, docNoClean, METHOD_LBL } from './fin-exp.js';

const ARTS = [
  { id: 'EX-11', kind: 'EX', nameUz: 'Elektr energiyasi', needsNote: false, cash: true, bank: true, card: true },
  { id: 'EX-40', kind: 'EX', nameUz: 'Bank komissiyasi', needsNote: false, cash: false, bank: true, card: true },
  { id: 'OP-12', kind: 'OP', nameUz: 'JShDS va INPS (faqat bank)', needsNote: false, cash: false, bank: true, card: false },
  { id: 'EX-49', kind: 'EX', nameUz: 'Boshqa xarajatlar (izoh majburiy)', needsNote: true, cash: true, bank: true, card: true },
];
const base = (o = {}) => ({ ref: 'xe-sinov-0001', method: 'bank', date: '2027-01-08', today: '2027-01-10', lockMin: '', cp: 'cp1', docNo: '№ 145', docDate: '',
  att: '', note: '', replaces: null, lines: [{ articleId: 'EX-11', amount: '1 200 000', note: 'yanvar' }], ...o });

test('to‘lov usullari: kassa ishga tushmagan — naqd, bank, karta; boshlang‘ichi naqd', () => {
  assert.deepEqual(methodOptions({}).map(m => m[0]), ['cash', 'bank', 'card']);
  assert.equal(defaultMethod({}), 'cash');
});
test('to‘lov usullari: kassa ishlayapti — bank va karta; naqd faqat Direktorga (kassa ishlamagan kun sanasi bilan)', () => {
  assert.deepEqual(methodOptions({ live: true }).map(m => m[0]), ['bank', 'card']);
  const d = methodOptions({ live: true, preLiveOk: true, preLiveTxt: 'kassa ishga tushishidan (04.01.2027) oldin' });
  assert.deepEqual(d.map(m => m[0]), ['bank', 'card', 'cash']);
  assert.match(d[2][1], /04\.01\.2027/);
  assert.equal(defaultMethod({ live: true }), 'bank');
  assert.equal(defaultMethod({ live: true }, 'cash'), 'bank', 'naqd taklif qilinmasa — bank');
  assert.equal(defaultMethod({ live: true }, 'card'), 'card', 'tuzatishda avvalgi usul');
});
test('to‘lov usullari: kassa to‘xtatilgan — naqd (to‘xtatilgan davr), bank, karta', () => {
  const h = methodOptions({ hold: true });
  assert.deepEqual(h.map(m => m[0]), ['cash', 'bank', 'card']);
  assert.match(h[0][1], /to‘xtatilgan davr/);
});
test('statiya va usul: server belgisi bo‘yicha', () => {
  assert.equal(articleOk(ARTS[1], 'cash'), false); assert.equal(articleOk(ARTS[1], 'bank'), true);
  assert.equal(articleOk(ARTS[2], 'card'), false); assert.equal(articleOk(ARTS[2], 'bank'), true);
  assert.equal(articleOk(null, 'bank'), false); assert.equal(articleOk(ARTS[0], 'accountable'), false);
});
test('hujjat raqami: «№», «#», bo‘shliq — server bilan bir xil kalit; saqlanadigan ko‘rinish — boshidagi «№» siz', () => {
  assert.equal(docNoKey('№ 145'), '145'); assert.equal(docNoKey('145'), '145'); assert.equal(docNoKey(' # 12-A '), '12-a');
  assert.equal(docNoClean('№ 145'), '145'); assert.equal(docNoClean('#12-A'), '12-A'); assert.equal(docNoClean(' № '), '');
  assert.equal(docNoClean('PP-7 № 2'), 'PP-7 № 2', 'o‘rtadagi belgi saqlanadi');
  assert.equal(docNoClean('x'.repeat(70)).length, 60);
});
test('oyna: yangi — bugungi sana, bitta bo‘sh qator', () => {
  const f = initForm({}, { live: true }, '2027-01-10');
  assert.equal(f.method, 'bank'); assert.equal(f.date, '2027-01-10'); assert.equal(f.replaces, null);
  assert.deepEqual(f.lines, [{ articleId: '', amount: '', note: '' }]);
});
test('oyna: hujjatni tuzatish — qatorlari, summalar mingliklar bilan, replaces = hujjat', () => {
  const doc = { id: 'xd_1', method: 'card', date: '2027-01-09', counterpartyId: 'cp1', docNo: '77', docDate: '2027-01-08', attachment: 'chek', note: 'n',
    lines: [{ lineNo: 1, articleId: 'EX-11', amount: 1200000, note: 'a' }, { lineNo: 2, articleId: 'EX-40', amount: 300000, note: '' }] };
  const f = initForm({ doc }, { live: true }, '2027-01-10');
  assert.equal(f.method, 'card'); assert.equal(f.replaces, 'xd_1'); assert.equal(f.docDate, '2027-01-08');
  assert.deepEqual(f.lines, [{ articleId: 'EX-11', amount: '1 200 000', note: 'a' }, { articleId: 'EX-40', amount: '300 000', note: '' }]);
});
test('oyna: eski yozuvni tuzatish — izoh hujjat izohiga, statiya va summa — qatorga, noto‘g‘ri sana — bugun', () => {
  const row = { _id: 'e_old', date: '2027-1-5', category: 'Kommunal', amount: 900000, note: ' eski izoh ', method: null, articleId: 'EX-11' };
  const f = initForm({ row }, {}, '2027-01-10');
  assert.equal(f.method, 'cash'); assert.equal(f.replaces, 'e_old'); assert.equal(f.date, '2027-01-10'); assert.equal(f.note, 'eski izoh');
  assert.deepEqual(f.lines, [{ articleId: 'EX-11', amount: '900 000', note: '' }]);
});
test('so‘rov: to‘g‘ri bank hujjati — № tozalangan, summa son, jami', () => {
  const r = buildPayload(base({ lines: [{ articleId: 'EX-11', amount: '1 200 000', note: ' yanvar ' }, { articleId: '', amount: '', note: '' }, { articleId: 'OP-12', amount: '300000', note: '' }] }), ARTS);
  assert.equal(r.err, undefined);
  assert.equal(r.total, 1500000);
  assert.deepEqual(r.p, { clientRef: 'xe-sinov-0001', method: 'bank', date: '2027-01-08', counterpartyId: 'cp1', docNo: '145', docDate: null, attachment: '', note: '',
    lines: [{ articleId: 'EX-11', amount: 1200000, note: 'yanvar' }, { articleId: 'OP-12', amount: 300000, note: '' }] });
  assert.equal(buildPayload(base({ replaces: 'xd_9' }), ARTS).p.replaces, 'xd_9');
});
test('so‘rov: sana — bo‘sh, kelajak, yopilgan davr', () => {
  assert.match(buildPayload(base({ date: '' }), ARTS).err, /Sanani tanlang/);
  assert.match(buildPayload(base({ date: '2027-01-11' }), ARTS).err, /bugundan keyin/);
  assert.match(buildPayload(base({ lockMin: '2027-01-09' }), ARTS).err, /yopilgan davr.*09\.01\.2027/);
  assert.match(buildPayload(base({ docDate: '2027-01-12' }), ARTS).err, /Hujjat sanasi bugundan keyin/);
});
test('so‘rov: bank — kontragent va № majburiy; karta va naqd — ixtiyoriy', () => {
  assert.match(buildPayload(base({ cp: '' }), ARTS).err, /kontragent/);
  assert.match(buildPayload(base({ docNo: ' № ' }), ARTS).err, /raqami majburiy/);
  assert.equal(buildPayload(base({ method: 'card', cp: '', docNo: '' }), ARTS).err, undefined);
  assert.equal(buildPayload(base({ method: 'cash', cp: '', docNo: '' }), ARTS).err, undefined);
  assert.match(buildPayload(base({ method: 'accountable' }), ARTS).err, /usulini tanlang/);
});
test('so‘rov: qatorlar — yo‘q, statiyasiz, ro‘yxatda yo‘q, usulga mos emas, 21 ta', () => {
  assert.match(buildPayload(base({ lines: [{ articleId: '', amount: ' ', note: '' }] }), ARTS).err, /Kamida bitta/);
  assert.match(buildPayload(base({ lines: [{ articleId: '', amount: '5000', note: '' }] }), ARTS).err, /1-qator: statiyani tanlang/);
  assert.match(buildPayload(base({ lines: [{ articleId: 'ZZ-1', amount: '5000' }] }), ARTS).err, /ro‘yxatda yo‘q/);
  assert.match(buildPayload(base({ method: 'cash', cp: '', lines: [{ articleId: 'EX-40', amount: '5000' }] }), ARTS).err, new RegExp('«Bank komissiyasi».*' + METHOD_LBL.cash.toLowerCase().replace(/[()]/g, '.')));
  assert.match(buildPayload(base({ method: 'card', lines: [{ articleId: 'OP-12', amount: '5000' }] }), ARTS).err, /korporativ karta orqali/);
  assert.match(buildPayload(base({ lines: Array.from({ length: 21 }, () => ({ articleId: 'EX-11', amount: '10' })) }), ARTS).err, /20 qator/);
});
test('so‘rov: summa — bo‘sh, nol, tiyin, ajratkich, juda katta', () => {
  assert.match(buildPayload(base({ lines: [{ articleId: 'EX-11', amount: '' }] }), ARTS).err, /summani kiriting/);
  assert.match(buildPayload(base({ lines: [{ articleId: 'EX-11', amount: '0' }] }), ARTS).err, /summani kiriting/);
  assert.match(buildPayload(base({ lines: [{ articleId: 'EX-11', amount: '1 000,50' }] }), ARTS).err, /Tiyin/);
  assert.match(buildPayload(base({ lines: [{ articleId: 'EX-11', amount: '1.000.000' }] }), ARTS).err, /Summa noto‘g‘ri/);
  assert.match(buildPayload(base({ lines: [{ articleId: 'EX-11', amount: '999999999999' }, { articleId: 'EX-40', amount: '1' }] }), ARTS).err, /juda katta/);
});
test('so‘rov: izoh majburiy statiya — qator izohi yoki hujjat izohi (kamida 3 belgi)', () => {
  assert.match(buildPayload(base({ lines: [{ articleId: 'EX-49', amount: '1000', note: 'ab' }] }), ARTS).err, /izoh majburiy/);
  assert.equal(buildPayload(base({ lines: [{ articleId: 'EX-49', amount: '1000', note: 'gullar' }] }), ARTS).err, undefined);
  assert.equal(buildPayload(base({ note: 'Bayram uchun', lines: [{ articleId: 'EX-49', amount: '1000' }] }), ARTS).err, undefined);
});
test('so‘rov: kassa ishlayotganda naqd — faqat kassa ishlamagan kun sanasi bilan (oynaning o‘zi rad etadi)', () => {
  const day = d => d < '2027-01-04';
  assert.match(buildPayload(base({ method: 'cash', cp: '', cashDay: day, cashTxt: 'kassa ishga tushishidan (04.01.2027) oldin' }), ARTS).err,
    /^Naqd xarajat — «Kassa» → «\+ Chiqim so‘rovi»\. Bu yerda faqat sanasi kassa ishga tushishidan \(04\.01\.2027\) oldin bo‘lsa$/);
  assert.equal(buildPayload(base({ method: 'cash', cp: '', date: '2027-01-03', cashDay: day }), ARTS).err, undefined);
  assert.equal(buildPayload(base({ method: 'bank', cashDay: day }), ARTS).err, undefined, 'bank — sana cheklovisiz');
});
