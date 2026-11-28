// fin-matrix.js (RP-09) sinovi (faqat sof qism):  node --test assets/js/fin-matrix.test.mjs
//   Statiya matritsasi (F2.5): standart yil va yillar ro'yxati, davr va oy yorlig'i, qator oylari (pul / bitta usul), jamlar (ichki
//   o'tkazma sof oqimga kirmaydi, hisobdor va hisoblash — alohida), nazorat (Jami = Σ hujjatlar, kassa sarlavhasi, maosh izohlari),
//   XLSX varaqlari va fayl nomi; lavozim -> statiya ro'yxati admin.html dagi «Xodimlar» lavozimlari bilan mos (server fin-matrix.sql).
//   Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { yearDefault, yearOptions, periodLabel, monthLabel, rowMonths, matrixTotals, controlCheck, payrollNote, articleLabel, matrixSheets, fileName,
         classifyNotes, MONEY, METHOD_LBL, SOURCE_LBL } from './fin-matrix.js';

const z = () => Array(12).fill(0);
const at = (i, v) => { const a = z(); a[i] = v; return a; };
const M0 = () => ({
  ok: true, kind: 'school', year: 2026, from: '2026-09-01', to: '2027-08-31', generatedAt: '2027-02-10T10:00:00+05:00',
  months: ['2026-09', '2026-10', '2026-11', '2026-12', '2027-01', '2027-02', '2027-03', '2027-04', '2027-05', '2027-06', '2027-07', '2027-08'],
  methods: ['cash', 'bank', 'card', 'online', 'offset', 'other', 'accountable', 'accrual'],
  rows: [
    { dir: 'in', articleId: 'IN-01', nameUz: 'Ta’lim xizmati', transfer: false, approx: false, sources: ['kassa', 'payments'],
      m: { cash: at(1, 300000), online: at(1, 200000) }, money: 500000, accountable: 0, accrual: 0 },
    { dir: 'out', articleId: 'EX-01', nameUz: 'O‘qituvchilar ish haqi', transfer: false, approx: false, sources: ['payroll'], m: { accrual: at(1, 510000) }, money: 0, accountable: 0, accrual: 510000 },
    { dir: 'out', articleId: 'EX-16', nameUz: 'Xo‘jalik vositalari', transfer: false, approx: false, sources: ['expenses'], m: { accountable: at(4, 27000) }, money: 0, accountable: 27000, accrual: 0 },
    { dir: 'out', articleId: 'EX-32', nameUz: 'Kanselyariya', transfer: false, approx: true, sources: ['expenses', 'kassa'],
      m: { cash: at(1, 100000), card: at(2, 40000) }, money: 140000, accountable: 0, accrual: 0 },
    { dir: 'out', articleId: 'OP-02', nameUz: 'Bankka topshirish', transfer: true, approx: false, sources: ['kassa'], m: { cash: at(2, 50000) }, money: 50000, accountable: 0, accrual: 0 },
    { dir: 'out', articleId: null, transfer: false, approx: false, sources: ['expenses', 'payroll'], m: { other: at(3, 33000), accrual: at(2, 800000) }, money: 33000, accountable: 0, accrual: 800000 },
  ],
  sources: [{ key: 'kassa', docs: 3, total: 450000 }, { key: 'payments', docs: 2, total: 200000 }, { key: 'expenses', docs: 3, total: 100000 },
            { key: 'payroll', docs: 2, total: 1310000 }],
  kassaHeader: { in: 300000, out: 150000, docs: 3 },
  payroll: { byMonth: [
    { month: '2026-09', run: null, split: 0, accrualRow: null, diff: null },
    { month: '2026-10', run: 'approved', split: 510000, accrualRow: 510000, diff: 0 },
    { month: '2026-11', run: 'submitted', split: 0, accrualRow: 800000, diff: null },
    { month: '2026-12', run: 'approved', split: 450000, accrualRow: null, diff: null },
    { month: '2027-01', run: 'approved', split: 300000, accrualRow: 290000, diff: 10000 },
    { month: '2027-02', run: null, split: 0, accrualRow: 700000, diff: null },
    ...['2027-03', '2027-04', '2027-05', '2027-06', '2027-07', '2027-08'].map(m => ({ month: m, run: null, split: 0, accrualRow: null, diff: null }))],
    positions: [{ type: 'teacher', position: null, articleId: 'EX-01', lines: 2, total: 960000 }, { type: 'staff', position: 'Psixolog', articleId: null, lines: 1, total: 120000 }] },
  unclassified: [{ category: 'Noma’lum toifa', rows: 1, total: 33000 }],
});

test('standart yil: o‘quv yili 1-sentyabrdan, avgustda — o‘tgan yil; kalendar — joriy; noto‘g‘ri sana — 0', () => {
  assert.equal(yearDefault('school', '2026-11-27'), 2026);
  assert.equal(yearDefault('school', '2026-08-31'), 2025);
  assert.equal(yearDefault('school', '2026-09-01'), 2026);
  assert.equal(yearDefault('calendar', '2026-11-27'), 2026);
  assert.equal(yearDefault('calendar', ''), 0);
});
test('yillar ro‘yxati: joriydan 2024 gacha (kamayish tartibida); sana yo‘q — faqat 2024', () => {
  assert.deepEqual(yearOptions('school', '2026-11-27'), [2026, 2025, 2024]);
  assert.deepEqual(yearOptions('school', '2024-08-15'), [2024]);
  assert.deepEqual(yearOptions('calendar', '2027-02-10'), [2027, 2026, 2025, 2024]);
  assert.deepEqual(yearOptions('calendar', ''), [2024]);
});
test('davr va oy yorlig‘i', () => {
  assert.equal(periodLabel('school', 2026), '2026/2027 o‘quv yili (01.09.2026 – 31.08.2027)');
  assert.equal(periodLabel('calendar', 2027), '2027 kalendar yili (01.01.2027 – 31.12.2027)');
  assert.equal(monthLabel('2026-09'), 'Sen 2026');
  assert.equal(monthLabel('2027-01'), 'Yan 2027');
  assert.equal(monthLabel('x'), 'x');
});
test('qator oylari: pul — barcha pul usullari (hisobdor va hisoblashsiz); bitta usul; yo‘q usul — nollar', () => {
  const M = M0();
  assert.deepEqual(rowMonths(M.rows[0], 'money'), at(1, 500000));
  assert.deepEqual(rowMonths(M.rows[5], 'money'), at(3, 33000));
  assert.deepEqual(rowMonths(M.rows[5], 'accrual'), at(2, 800000));
  assert.deepEqual(rowMonths(M.rows[0], 'bank'), z());
  assert.deepEqual(MONEY, ['cash', 'bank', 'card', 'online', 'offset', 'other']);
});
test('jamlar: kirim / chiqim, ichki o‘tkazma sof oqimga kirmaydi; hisobdor va hisoblash alohida; usullar bo‘yicha; umumiy jami', () => {
  const T = matrixTotals(M0());
  assert.deepEqual(T.inAll, at(1, 500000));
  assert.equal(T.outAll.reduce((s, x) => s + x, 0), 100000 + 40000 + 50000 + 33000);
  assert.deepEqual(T.trOut, at(2, 50000));
  assert.deepEqual(T.net, [0, 400000, -40000, -33000, 0, 0, 0, 0, 0, 0, 0, 0]);
  assert.deepEqual(T.accountable, at(4, 27000));
  assert.equal(T.accrual.reduce((s, x) => s + x, 0), 1310000);
  assert.deepEqual(T.byMethod.in, { cash: 300000, online: 200000 });
  assert.deepEqual(T.byMethod.out, { accrual: 1310000, accountable: 27000, cash: 150000, card: 40000, other: 33000 });
  assert.equal(T.grand, 500000 + 510000 + 27000 + 140000 + 50000 + 833000);
});
test('nazorat: matritsa jami = manbalar jami, kassa sarlavhasi; buzilganda — «mos emas»', () => {
  const M = M0(), K = controlCheck(M);
  assert.equal(K.rowsTotal, 2060000); assert.equal(K.srcTotal, 2060000);
  assert.equal(K.ok, true); assert.equal(K.docs, 10); assert.equal(K.kassaOk, true);
  M.sources.push({ key: 'refunds', docs: 1, total: 1 });
  const K2 = controlCheck(M); assert.equal(K2.ok, false); assert.equal(K2.docs, 11);
  M.sources.pop();
  M.kassaHeader.out = 149999; assert.equal(controlCheck(M).kassaOk, false);
  M.kassaHeader.out = 150000; M.kassaHeader.docs = 4; assert.equal(controlCheck(M).kassaOk, false);
});
test('maosh izohlari: mos, qator yozilmagan, farq, tasdiqlanmagan (e’tibor), vedomostsiz oy (taqsimlanmagan, e’tiborsiz); bo‘sh oylar yo‘q', () => {
  const K = controlCheck(M0());
  assert.deepEqual(K.payroll.map(p => [p.month, p.warn]), [['2026-10', false], ['2026-11', true], ['2026-12', true], ['2027-01', true], ['2027-02', false]]);
  assert.equal(K.payrollWarn, 3);
  assert.match(payrollNote({ run: 'approved', accrualRow: 510000, diff: 0 }).text, /mos/);
  assert.match(payrollNote({ run: 'approved', accrualRow: null }).text, /yozilmagan/);
  assert.match(payrollNote({ run: 'approved', accrualRow: 290000, diff: 10000 }).text, /^farq: 10 000/);
  assert.match(payrollNote({ run: 'submitted', accrualRow: 800000 }).text, /tasdiqda — «Maosh» qatori taqsimlanmagan/);
  assert.match(payrollNote({ run: null, accrualRow: 700000 }).text, /vedomost yo‘q/);
  assert.equal(payrollNote({ run: null, accrualRow: null }), null);
  assert.equal(payrollNote(null), null);
});
test('statiya yorlig‘i: kod + nom; statiyasiz kirim / chiqim', () => {
  assert.equal(articleLabel({ articleId: 'EX-32', nameUz: 'Kanselyariya' }), 'EX-32 Kanselyariya');
  assert.equal(articleLabel({ dir: 'in', articleId: null }), 'Statiyasiz kirim');
  assert.equal(articleLabel({ dir: 'out' }), 'Statiyasiz / aniqlanmagan');
});
test('XLSX: 4 varaq, sarlavhalar, jami qatorlari, hisobdor va hisoblash bloklari; ism yo‘q', () => {
  const M = M0(), sh = matrixSheets(M, { org: 'Sinov maktabi' });
  assert.deepEqual(sh.map(s => s.name), ['Matritsa', 'Usullar', 'Maosh taqsimoti', 'Nazorat']);
  const m1 = sh[0].rows, find = (rows, a, b) => rows.find(r => r[0] === a && (b === undefined || r[1] === b));
  assert.equal(m1[0][0], 'RP-09 — barcha to‘lov usullari bo‘yicha statiya matritsasi');
  assert.equal(m1[1][0], '2026/2027 o‘quv yili (01.09.2026 – 31.08.2027) · Sinov maktabi');
  assert.deepEqual(m1[4].slice(0, 4), ['Yo‘nalish', 'Statiya', 'Belgi', 'Sen 2026']);
  assert.equal(m1[4].length, 3 + 12 + 1);
  assert.equal(find(m1, 'Kirim', 'IN-01 Ta’lim xizmati')[3 + 1], 500000);
  assert.equal(find(m1, 'JAMI KIRIM').at(-1), 500000);
  assert.equal(find(m1, 'JAMI CHIQIM').at(-1), 223000);
  assert.equal(find(m1, 'Chiqim', 'EX-32 Kanselyariya')[2], 'toifadan (taxminiy)');
  assert.equal(find(m1, 'Chiqim', 'OP-02 Bankka topshirish')[2], 'ichki o‘tkazma');
  assert.equal(find(m1, 'SOF PUL OQIMI').at(-1), 500000 - 173000);
  assert.equal(find(m1, 'Hisobdor', 'EX-16 Xo‘jalik vositalari').at(-1), 27000);
  assert.equal(find(m1, 'JAMI', 'hisobdor').at(-1), 27000);
  assert.equal(find(m1, 'Hisoblash', 'Statiyasiz / aniqlanmagan').at(-1), 800000);
  assert.equal(find(m1, 'JAMI', 'hisoblangan maosh').at(-1), 1310000);
  assert.equal(m1.some(r => r[1] === 'EX-01 O‘qituvchilar ish haqi' && r[0] === 'Chiqim'), false);   // pul blokida hisoblash qatori yo'q
  const m2 = sh[1].rows;
  assert.deepEqual(m2.filter(r => r[1] === 'EX-32 Kanselyariya').map(r => r[2]), ['Naqd', 'Karta / terminal']);   // usullar tartibi — methods
  assert.equal(m2.find(r => r[1] === 'IN-01 Ta’lim xizmati' && r[2] === METHOD_LBL.online).at(-1), 200000);
  const m3 = sh[2].rows;
  assert.deepEqual(m3.find(r => r[0] === 'Yan 2027'), ['Yan 2027', 'tasdiqlangan', 300000, 290000, 10000, 'farq: 10 000 — «Maosh» qatorini qayta yozing']);
  assert.equal(m3.some(r => r[0] === 'Sen 2026'), false);
  assert.deepEqual(m3.find(r => r[0] === 'O‘qituvchilar ro‘yxati'), ['O‘qituvchilar ro‘yxati', 'EX-01', 2, 960000]);
  assert.deepEqual(m3.find(r => r[0] === 'Psixolog'), ['Psixolog', 'aniqlanmagan', 1, 120000]);
  const m4 = sh[3].rows;
  assert.deepEqual(m4.find(r => r[0] === SOURCE_LBL.kassa), [SOURCE_LBL.kassa, 3, 450000]);
  assert.deepEqual(m4.find(r => r[0] === 'Moslik'), ['Moslik', '', 'mos']);
  M.sources[0].total = 1; assert.deepEqual(matrixSheets(M, {})[3].rows.find(r => r[0] === 'Moslik'), ['Moslik', '', 'MOS EMAS']);
  assert.deepEqual(m4.find(r => r[0] === 'Noma’lum toifa'), ['Noma’lum toifa', 1, 33000]);
  assert.equal(sh[0].cols.length, 16);
});
test('F2.3 eski xarajatlar tasnifi (M.classify): yozuvi bor oylar — qisman / imzo kutilmoqda / imzolangan / eskirgan; «Nazorat» varag‘ida', () => {
  const M = { ...M0(), classify: [
    { month: '2026-11', n: 5, confirmed: 4, sign: { valid: false, by: 'Sinov Buxgalter', at: '2026-12-29T10:00:00+05:00' } },
    { month: '2026-12', n: 2, confirmed: 2, sign: null },
    { month: '2027-01', n: 3, confirmed: 3, sign: { valid: true, by: 'Sinov Buxgalter', at: '2027-02-02T10:00:00+05:00' } },
    { month: '2027-02', n: 0, confirmed: 0, sign: null }] };
  assert.deepEqual(classifyNotes(M), [
    { month: '2026-11', n: 5, confirmed: 4, text: 'qisman: 5 tadan 4 tasi tasdiqlangan', warn: true },
    { month: '2026-12', n: 2, confirmed: 2, text: 'tasdiqlangan, buxgalter imzosi kutilmoqda', warn: true },
    { month: '2027-01', n: 3, confirmed: 3, text: 'imzolangan (Sinov Buxgalter, 02.02.2027)', warn: false }]);
  assert.deepEqual(classifyNotes({ classify: [{ month: '2026-12', n: 2, confirmed: 2, sign: { valid: false } }] })[0].text, 'imzo eskirgan — qayta imzolash kerak');
  assert.deepEqual(classifyNotes(M0()), []); assert.deepEqual(classifyNotes(null), []);
  const nz = matrixSheets(M, {}).find(x => x.name === 'Nazorat').rows;
  const i = nz.findIndex(r => r[0] === 'Eski xarajatlar statiya tasnifi (noyabr–yanvar, F2.3)');
  assert.ok(i > 0, 'Nazorat varag‘ida tasnif bloki');
  assert.deepEqual(nz.slice(i + 1, i + 4), [['Noy 2026', 5, 'qisman: 5 tadan 4 tasi tasdiqlangan'], ['Dek 2026', 2, 'tasdiqlangan, buxgalter imzosi kutilmoqda'],
                                             ['Yan 2027', 3, 'imzolangan (Sinov Buxgalter, 02.02.2027)']]);
  assert.ok(!matrixSheets(M0(), {}).find(x => x.name === 'Nazorat').rows.some(r => String(r[0]).startsWith('Eski xarajatlar')), 'tasnif oyi yo‘q — blok yo‘q');
});

test('fayl nomi', () => {
  assert.equal(fileName({ kind: 'school', year: 2026 }), 'RP-09_oquv-2026-2027.xlsx');
  assert.equal(fileName({ kind: 'calendar', year: 2027 }), 'RP-09_kalendar-2027.xlsx');
});
test('lavozim -> statiya: admin.html dagi har «Xodimlar» lavozimi server ro‘yxatida bor (fin-matrix.sql: app.fin_pos_article)', () => {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const html = fs.readFileSync(root + 'admin.html', 'utf8'), sql = fs.readFileSync(root + 'migration/fin-matrix.sql', 'utf8');
  const lst = /const STAFF_POSITIONS = \[([^\]]*)\]/.exec(html);
  assert.ok(lst, 'STAFF_POSITIONS topilmadi');
  const norm = s => s.replace(/[‘’ʻʼ`´]/g, "'").trim().replace(/\s+/g, ' ').toLowerCase();
  const pos = [...lst[1].matchAll(/'([^']*)'/g)].map(m => norm(m[1]));
  const fn = sql.slice(sql.indexOf('create or replace function app.fin_pos_article'), sql.indexOf('revoke all on function app.fin_pos_article'));
  const known = new Set([...fn.matchAll(/'((?:[^']|'')*)'/g)].map(m => m[1].replace(/''/g, "'")).filter(x => /^[a-z' ]+$/.test(x) && x.length > 1));
  const missing = pos.filter(p => !known.has(p));
  assert.equal(pos.length, 24);
  assert.deepEqual(missing, []);
});
