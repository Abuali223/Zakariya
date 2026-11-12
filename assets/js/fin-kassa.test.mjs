// fin-kassa.js sinovi (faqat sof qism):  node --test assets/js/fin-kassa.test.mjs
//   controlRows(checks) — nazorat ro'yxati (RP-06): server faktlaridan (kassa_checks) qator, daraja va matn tuzadi.
//   Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { controlRows, zText } from './fin-kassa.js';

const clean = () => ({ ok: true, today: '2027-01-08', isTest: false, gaps: [], staleOpenDay: null, unverifiedDays: [], undecidedShortages: [], diffs30: [], voids30: 0, reopens30: 0,
  waitingApproval: 0, approvedUnpaid: 0, fiscalExempt30: 0, otherParties30: 0, late30: 0, reissues30: 0, staleRefunds: 0, salaryGateOff30: 0, unprintedBooks30: [], pendingDays30: 0,
  limit: { cashLimit: 3000000, set: true, balance: 1200000, exceeded: false, days30: 0 },
  reconcile: { live: true, total: 0, p1: { pay: 0, paySum: 0, doc: 0 }, p4: { row: 0, doc: 0 }, p5: { row: 0, doc: 0 }, p8: { row: 0, doc: 0 } },
  accountable: [], handover: { monthCount: 0, monthSum: 0, earlierCount: 0, earlierSum: 0 }, zreport: [] });
const by = rows => Object.fromEntries(rows.map(r => [r.key, r]));

test('nazorat ro‘yxati: toza holat — 21 tekshiruvning hammasi «joyida»', () => {
  const rows = controlRows(clean());
  assert.equal(rows.length, 21);
  assert.deepEqual(rows.map(r => r.key), ['gaps', 'staleOpenDay', 'unverified', 'shortages', 'diffs', 'voids', 'reopens', 'waiting', 'unpaid', 'staleRefunds', 'fiscal', 'zreport', 'other',
    'late', 'reissues', 'gateOff', 'unprinted', 'limit', 'reconcile', 'accountable', 'handover']);
  assert.ok(rows.every(r => r.level === 'ok'), JSON.stringify(rows.filter(r => r.level !== 'ok')));
  const r = by(rows);
  assert.equal(r.gaps.value, 'uzluksiz'); assert.equal(r.reconcile.value, 'hammasi mos'); assert.equal(r.limit.value, 'limit 3 000 000 so‘m — oshmagan');
  assert.ok(rows.every(x => x.label && x.value), 'har qatorda nom va natija');
});

test('nazorat ro‘yxati: muammolar — daraja va matn', () => {
  const c = clean();
  Object.assign(c, {
    gaps: [{ year: 2027, problems: [{ series: 'KO1', lastNo: 5, count: 4, max: 5 }] }], staleOpenDay: '2027-01-06',
    unverifiedDays: ['2027-01-04', '2027-01-05'], undecidedShortages: [{ id: 'x', no: 9, day: '2027-01-04', amount: 5000 }, { id: 'y', no: 12, day: '2027-01-05', amount: 2500.5 }],
    diffs30: [{ day: '2027-01-04', diff: -5000 }, { day: '2027-01-05', diff: 1200 }], voids30: 3, reopens30: 1, waitingApproval: 2, approvedUnpaid: 1, staleRefunds: 1,
    fiscalExempt30: 2, otherParties30: 4, late30: 1, pendingDays30: 2, reissues30: 1, salaryGateOff30: 1, unprintedBooks30: ['2027-01-05'],
    limit: { cashLimit: 3000000, set: true, balance: 4525000, exceeded: true, days30: 1 },
    reconcile: { live: true, total: 10, p1: { pay: 1, paySum: 111000, doc: 1 }, p4: { row: 1, doc: 1 }, p5: { row: 2, doc: 1, ofs: 1 }, p8: { row: 1, doc: 1 } },
    accountable: [{ partyId: 'staff:st1', name: 'Sinov Zavxoz', given: 400000, returned: 150000, balance: 250000, since: '2027-01-04', workDays: 4, overdue: true }],
    handover: { monthCount: 1, monthSum: 500000, earlierCount: 2, earlierSum: 900000 },
    zreport: [{ day: '2027-01-05', recorded: true, missing: false, diffCash: -10000, diffCard: 0 }, { day: '2027-01-06', recorded: false, missing: false },
              { day: '2027-01-07', recorded: true, missing: true }, { day: '2027-01-07', recorded: true, missing: false, diffCash: 0, diffCard: 2500 }] });
  const r = by(controlRows(c));
  const lv = k => r[k].level;
  assert.deepEqual(['gaps', 'staleOpenDay', 'shortages', 'staleRefunds', 'reconcile', 'zreport'].map(lv), ['bad', 'bad', 'bad', 'bad', 'bad', 'bad']);
  assert.equal(r.zreport.value, '05.01.2027: farq: naqd −10 000 so‘m; 06.01.2027: kiritilmagan; 07.01.2027: yo‘q; 07.01.2027: farq: karta +2 500 so‘m');
  assert.deepEqual(['unverified', 'diffs', 'reopens', 'fiscal', 'reissues', 'gateOff', 'unprinted', 'limit', 'accountable', 'handover'].map(lv), Array(10).fill('warn'));
  assert.deepEqual(['voids', 'waiting', 'unpaid', 'other', 'late'].map(lv), Array(5).fill('info'));
  assert.equal(r.gaps.value, '2027: kirim orderlari — bo‘shliq yoki takror');
  assert.equal(r.staleOpenDay.value, '06.01.2027');
  assert.equal(r.unverified.value, '2 ta: 04.01.2027, 05.01.2027');
  assert.equal(r.shortages.value, '2 ta · 7 500,50 so‘m');
  assert.equal(r.diffs.value, '04.01.2027: −5 000 so‘m; 05.01.2027: +1 200 so‘m');
  assert.equal(r.late.value, 'kech yozilgan hujjat: 1 ta; oflayn yozuv bilan yopilgan kun: 2 ta');
  assert.equal(r.limit.value, 'qoldiq 4 525 000 so‘m — limit 3 000 000 so‘mdan oshgan');
  assert.equal(r.reconcile.value, 'kirim orderisiz naqd o‘quv to‘lovi: 1 ta (111 000 so‘m); to‘lov yozuvisiz kirim orderi: 1 ta; chiqim orderisiz naqd xarajat: 1 ta; '
    + '«Buxgalteriya»ga ko‘chmagan xarajat orderi: 1 ta; chiqim orderisiz naqd maosh / avans: 2 ta; yozuvsiz maosh / avans orderi: 1 ta; '
    + 'o‘zaro hisob (dalolatnoma ↔ maosh ↔ o‘quv to‘lovi) mos emas: 1 ta; chiqim orderisiz naqd qaytarish: 1 ta; yozuvsiz qaytarish orderi: 1 ta');
  assert.equal(r.accountable.value, 'Sinov Zavxoz: 250 000 so‘m (04.01.2027 dan, 4 ish kuni — muddati o‘tgan)');
  assert.equal(r.handover.value, 'shu oyda: 1 ta · 500 000 so‘m; oldingi oylarda: 2 ta · 900 000 so‘m — tasniflanganini tekshiring');
});

test('nazorat ro‘yxati: oraliq holatlar — limit belgilanmagan, kassa ishga tushmagan, sinov kassasi, bo‘sh javob', () => {
  let c = clean(); c.limit = { cashLimit: 0, set: false, balance: 100, exceeded: false, days30: 0 }; c.reconcile = { live: false, total: 0 };
  c.unverifiedDays = ['2027-01-01', '2027-01-02', '2027-01-03', '2027-01-04', '2027-01-05', '2027-01-06', '2027-01-07'];
  c.accountable = [{ partyId: 'staff:st1', name: 'Sinov Zavxoz', balance: 100000, since: '2027-01-07', workDays: 1, overdue: false }];
  c.handover = { monthCount: 1, monthSum: 500000, earlierCount: 0, earlierSum: 0 };
  let r = by(controlRows(c));
  assert.deepEqual([r.limit.level, r.limit.value], ['info', 'belgilanmagan']);
  assert.deepEqual([r.reconcile.level, r.reconcile.value], ['info', 'kassa hali ishga tushirilmagan']);
  assert.deepEqual([r.unverified.level, r.unverified.value], ['bad', '7 ta: 01.01.2027, 02.01.2027, 03.01.2027, 04.01.2027, 05.01.2027, 06.01.2027 …']);
  assert.deepEqual([r.accountable.level, r.handover.level], ['info', 'info']);
  c = clean(); c.limit.days30 = 2;
  assert.deepEqual([by(controlRows(c)).limit.level, by(controlRows(c)).limit.value], ['info', 'limit 3 000 000 so‘m · 2 kun limitdan oshib yopilgan']);
  c = clean(); c.isTest = true; c.reconcile = { live: false, total: 0 };
  assert.ok(!controlRows(c).some(x => x.key === 'reconcile' || x.key === 'zreport'), 'sinov kassasida moslik va Z-hisobot qatorlari yo‘q');
  assert.equal(controlRows(c).length, 19);
  const empty = controlRows(null);
  assert.ok(empty.length === 21 && empty.filter(x => x.level === 'ok').length === 19, 'bo‘sh javob: xatosiz, limit va moslik — ma’lumot');
});

test('Z-hisobot holati matni (kun javobidagi «z»)', () => {
  assert.equal(zText(null), ''); assert.equal(zText({ applies: false }), '');
  assert.equal(zText({ applies: true, needed: false, recorded: false, ok: true }), '', 'kerak bo‘lmagan va kiritilmagan — ko‘rsatilmaydi');
  assert.equal(zText({ applies: true, needed: true, recorded: false, ok: false }), 'kiritilmagan');
  assert.equal(zText({ applies: true, recorded: true, missing: true, reason: 'Apparat buzilgan', ok: false }), 'yo‘q (Apparat buzilgan)');
  assert.equal(zText({ applies: true, recorded: true, missing: false, ok: false, diffCash: 5000, diffCard: -1200 }), 'farq: naqd +5 000 so‘m, karta −1 200 so‘m');
  assert.equal(zText({ applies: true, recorded: true, missing: false, ok: true, diffCash: 0, diffCard: 0 }), 'mos');
  assert.equal(zText({ applies: true, recorded: true, missing: false, no: 'Z-1', cash: 1, card: 0 }), 'kiritilgan', 'ochiq kun: solishtirish yo‘q');
});
