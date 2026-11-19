// pay-carry.test.mjs — maosh qoldig'i va vedomost yordamchilari (audit-11, H2): admin.html PAY-CARRY bloki (sof funksiyalar) fayldan o'qib sinaladi.
//   node --test assets/js/pay-carry.test.mjs
//   Qoida (baza app.salary_carry bilan bir xil): o'tish oyidan OLDINGI oylar — eski tartib (oy qarzi eng so'nggi yozuvdan, paid bo'sh — to'liq
//   to'langan); o'tish oyidan boshlab — oy qarzi TASDIQLANGAN vedomost qatoridan (maosh − shu oy avanslari − ushlanma + o'rinbosarlik),
//   berilgani — paid yig'indisi; yozuvdagi gross / ushlanma / avans e'tiborsiz; tasdiqlanmagan oy — hisobga kirmaydi. Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const block = (() => { const a = ADM.indexOf('// PAY-CARRY:BEGIN'), b = ADM.indexOf('// PAY-CARRY:END'); return a >= 0 && b > a ? ADM.slice(a, b) : ''; })();
const P = (() => {
  const ctx = vm.createContext({});
  vm.runInContext(block + '\n;this.__p = { carryBalance, payrollCarryCtx, payMonthState, prStale, prDirPending, prWho };', ctx);
  return ctx.__p;
})();
const row = (month, paid, gross, extra) => Object.assign({ teacherId: 'IQX-901', month, paid, gross, advance: 0, deduction: 0, subBonus: 0 }, extra || {});

test('blok bitta va yordamchilar bor', () => {
  assert.ok(block.length > 0, 'PAY-CARRY bloki topilmadi');
  assert.equal((ADM.match(/PAY-CARRY:BEGIN/g) || []).length, 1);
  for (const f of ['carryBalance', 'payrollCarryCtx', 'payMonthState', 'prStale', 'prDirPending', 'prWho']) {
    assert.equal((ADM.match(new RegExp('function ' + f + '\\(', 'g')) || []).length, 1, f + ' bitta (blok ichida)');
  }
});

test('eski tartib (vedomost tasdig‘i yo‘q) — o‘zgarmagan', () => {
  // qisman berilgan: 1 000 000 dan 600 000 -> qoldiq 400 000
  assert.equal(P.carryBalance([row('2026-05', 600000, 1000000, { date: '2026-06-01' })], '2026-06'), 400000);
  // paid bo'sh (eski yozuv) — to'liq to'langan
  assert.equal(P.carryBalance([row('2026-05', null, 1000000)], '2026-06'), 0);
  // oy qarzi eng so'nggi sanali yozuvdan (tuzatish), to'lovlar yig'iladi
  assert.equal(P.carryBalance([row('2026-05', 500000, 1000000, { date: '2026-06-01' }), row('2026-05', 0, 800000, { date: '2026-06-10' })], '2026-06'), 300000);
  // beforeMonth va undan keyingi oylar hisobga kirmaydi
  assert.equal(P.carryBalance([row('2026-06', 0, 1000000)], '2026-06'), 0);
  // pr = null (o'tish oyi yo'q) — xuddi shu natija
  assert.equal(P.carryBalance([row('2026-05', 600000, 1000000)], '2026-06', null), 400000);
});

test('payrollCarryCtx: o‘tish oyi yo‘q — null; tasdiqlangan oylar, qatorlar, avanslar (sana bo‘yicha oy, qaytgani manfiy)', () => {
  assert.equal(P.payrollCarryCtx('', [], [], []), null);
  const pr = P.payrollCarryCtx('2026-09',
    [{ id: '2026-09', status: 'approved' }, { _id: '2026-10', status: 'returned' }],
    [{ runId: '2026-09', personId: 'IQX-901', gross: 2000000, deduction: 0, subBonus: 0 }],
    [{ teacherId: 'IQX-901', month: '2026-09', amount: 300000 }, { teacherId: 'IQX-901', date: '2026-09-20', amount: 100000 }, { teacherId: 'IQX-901', month: '2026-09', amount: -50000 }]);
  assert.equal(pr.from, '2026-09');
  assert.deepEqual(Object.keys(pr.approved), ['2026-09']);
  assert.equal(pr.lines['2026-09|IQX-901'].gross, 2000000);
  assert.equal(pr.adv['2026-09|IQX-901'], 350000);
});

test('o‘tish oyidan: soxta gross / manfiy summa qoldiqni oshirmaydi; qarz — tasdiqlangan qatordan (A5-01)', () => {
  const pr = P.payrollCarryCtx('2026-09', [{ id: '2026-09', status: 'approved' }],
    [{ runId: '2026-09', personId: 'IQX-901', gross: 2000000, deduction: 0, subBonus: 0 }], []);
  // kassir 2 000 000 berdi, yozuvga gross 9 000 000 yozdi; keyin 0 so'mlik soxta yozuv — eski qoida 7 000 000 ko'rsatardi
  const pays = [row('2026-09', 2000000, 9000000, { date: '2026-10-01' }), row('2026-09', 0, 9000000, { date: '2026-10-05' })];
  assert.equal(P.carryBalance(pays, '2026-10', pr), 0);
  assert.equal(P.carryBalance(pays, '2026-10'), 7000000, 'eski qoida (pr yo‘q) — farqni ko‘rsatish uchun');
  // qisman berilgan: 1 500 000 -> qoldiq 500 000 (qator qarzi 2 000 000)
  assert.equal(P.carryBalance([row('2026-09', 1500000, 9000000)], '2026-10', pr), 500000);
});

test('qayta ochilib kamroq summa bilan qayta tasdiqlangan oy — ortiqcha keyingi oyga manfiy (A5-02)', () => {
  const pr = P.payrollCarryCtx('2026-09', [{ id: '2026-10', status: 'approved' }],
    [{ runId: '2026-10', personId: 'IQX-901', gross: 2000000, deduction: 500000, subBonus: 0 }], []);
  // to'lov paytidagi yozuvda ushlanma 0 edi (eski versiya), qayta tasdiqlangan qatorda — 500 000
  const pays = [row('2026-10', 2000000, 2000000, { deduction: 0 }), row('2026-10', 0, 2000000, { deduction: 500000, date: '2026-11-20' })];
  assert.equal(P.carryBalance(pays, '2026-11', pr), -500000);
});

test('o‘tish oyidan: avans — shu oy avanslari (hozirgi), o‘rinbosarlik qo‘shiladi; tasdiqlanmagan oy kirmaydi; qatori yo‘q — qarz 0', () => {
  const pr = P.payrollCarryCtx('2026-09', [{ id: '2026-09', status: 'approved' }, { id: '2026-10', status: 'submitted' }],
    [{ runId: '2026-09', personId: 'IQX-901', gross: 2000000, deduction: 100000, subBonus: 80000 }],
    [{ teacherId: 'IQX-901', month: '2026-09', amount: 300000 }]);
  // qarz: 2 000 000 − 300 000 − 100 000 + 80 000 = 1 680 000; berilgan 1 600 000 -> 80 000
  assert.equal(P.carryBalance([row('2026-09', 1600000, 2000000)], '2026-10', pr), 80000);
  // 2026-10 — HR hali tasdiqlamagan (qayta yuborilgan): hisobga kirmaydi
  assert.equal(P.carryBalance([row('2026-09', 1600000, 2000000), row('2026-10', 500000, 2000000)], '2026-11', pr), 80000);
  // tasdiqlangan oyda qatori yo'q xodimga berilgan — butunlay ortiqcha
  const pr2 = P.payrollCarryCtx('2026-09', [{ id: '2026-09', status: 'approved' }], [], []);
  assert.equal(P.carryBalance([row('2026-09', 400000, 400000)], '2026-10', pr2), -400000);
  // o'tish oyidan oldingi oy — eski qoida bilan qo'shiladi
  assert.equal(P.carryBalance([row('2026-08', 600000, 1000000), row('2026-09', 1600000, 2000000)], '2026-10', pr), 400000 + 80000);
});

test('payMonthState: tugagan / joriy / kelgusi oy (A5-03)', () => {
  assert.equal(P.payMonthState('2026-11', '2026-12'), 'past');
  assert.equal(P.payMonthState('2026-12', '2026-12'), 'current');
  assert.equal(P.payMonthState('2027-01', '2026-12'), 'future');
});

test('prStale: oy tugamasdan yuborilgan vedomostni oy tugagach ham HR tasdiqlamaydi — baza payroll_decide \'stale\' bilan bir xil (A5-03, r4)', () => {
  // 2026-12 vedomosti 10-dekabrda yuborilgan — ushlanma o'sha kungacha qotgan: 1-yanvarda ham eskirgan (qayta yuborilmaguncha)
  assert.equal(P.prStale('2026-12', '2026-12-10'), true);
  assert.equal(P.prStale('2026-12', '2026-12-31'), true);
  // oy tugagach (keyingi oyning 1-kunidan) yuborilgan — HR tasdiqlaydi; yil chegarasi (dekabr -> yanvar)
  assert.equal(P.prStale('2026-12', '2027-01-01'), false);
  assert.equal(P.prStale('2026-12', '2027-02-15'), false);
  assert.equal(P.prStale('2026-11', '2026-12-01'), false);
  assert.equal(P.prStale('2026-11', '2026-11-30'), true);
  assert.equal(P.prStale('2026-09', '2026-10-01'), false);
  // yuborilgan kun noma'lum — eskirgan (baza: "submittedAt" bo'sh — 'stale')
  assert.equal(P.prStale('2026-12', ''), true);
  assert.equal(P.prStale('2026-12', null), true);
  // oy noto'g'ri — false (tugma holati boshqa tekshiruvlarga qoladi)
  assert.equal(P.prStale('', '2026-12-10'), false);
  assert.equal(P.prStale('2026-1', '2026-12-10'), false);
});

test('prDirPending: faqat yuborilgan / tasdiqlangan oy qatorlari, Direktor hali tasdiqlamagan (A5-07)', () => {
  const runs = [{ id: '2026-10', status: 'returned' }, { id: '2026-11', status: 'submitted' }, { _id: '2026-12', status: 'approved' }, { id: '2027-01', status: 'draft' }];
  const lines = [
    { id: 'a', runId: '2026-10', needsDirector: true },
    { id: 'b', runId: '2026-11', needsDirector: true },
    { id: 'c', runId: '2026-12', needsDirector: true },
    { id: 'd', runId: '2026-12', needsDirector: true, directorOkAt: '2026-12-05' },
    { id: 'e', runId: '2027-01', needsDirector: true },
    { id: 'f', runId: '2026-11', needsDirector: false },
  ];
  assert.deepEqual(Array.from(P.prDirPending(lines, runs), l => l.id), ['b', 'c']);
  assert.equal(P.prDirPending(null, runs).length, 0);
});

test('prWho: ism, bo‘lmasa rol; topilmasa «—» — ichki ID (UUID) hech qachon chiqmaydi (A5-08)', () => {
  const uid = '3f2a9c1e-0000-4000-8000-000000000001';
  assert.equal(P.prWho(uid, { [uid]: { name: 'Sinov Moliyachi', role: 'Moliya menejeri' } }), 'Sinov Moliyachi');
  assert.equal(P.prWho(uid, { [uid]: { name: '', role: 'Moliya menejeri' } }), 'Moliya menejeri');
  assert.equal(P.prWho(uid, {}), '—');
  assert.equal(P.prWho(uid, null), '—');
  assert.equal(P.prWho('', {}), '—');
});
