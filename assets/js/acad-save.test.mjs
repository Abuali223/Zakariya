// acad-save.test.mjs — jurnal ekranlarini saqlash rejasi (audit A3-01, A3-03, A3-06, A3-07, A3-08): admin.html ACAD-SAVE bloki (sof
//   yordamchilar) fayldan o'qib sinaladi.  node --test assets/js/acad-save.test.mjs
//   Qoida: faqat foydalanuvchi shu ekranda o'zgartirgan qatorlar yoziladi; saqlash paytida bazadan qayta o'qilgan qiymat ochilgandagidan
//   farq qilsa — ustiga yozilmaydi (conflict). Monitoring: ball 0–100; O'IBDO' «Saqlash» tasdiqlamaydi; «Saqlash va tasdiqlash» faqat
//   ekranda ko'rilgan qiymatni tasdiqlaydi; bo'shatilgan maydon — o'chirish (o'qituvchi — faqat o'zi kiritgan, tasdiqlanmagan). Ma'lumot to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const block = (() => { const a = ADM.indexOf('// ACAD-SAVE:BEGIN'), b = ADM.indexOf('// ACAD-SAVE:END'); return a >= 0 && b > a ? ADM.slice(a, b) : ''; })();
const S = (() => {
  const ctx = vm.createContext({});
  vm.runInContext(block + '\n;this.__s = { acadPlan, monScoreErr, monNum, monSameRec, monPlan };', ctx);
  return ctx.__s;
})();
const P = rec => JSON.parse(JSON.stringify(rec));   // vm kontekstidagi massivlarni oddiy obyektga (deepEqual uchun)
const pend = (score, by = 'U_T') => ({ score, status: 'pending', by });
const appr = (score, by = 'U_T') => ({ score, status: 'approved', by });

test('blok bitta va yordamchilar bor', () => {
  assert.ok(block.length > 0);
  assert.equal((ADM.match(/ACAD-SAVE:BEGIN/g) || []).length, 1);
  assert.equal((ADM.match(/function monPlan\(/g) || []).length, 1, 'monPlan bitta');
  assert.equal((ADM.match(/function acadPlan\(/g) || []).length, 1, 'acadPlan bitta');
});

test('acadPlan: faqat o‘zgartirilgan qatorlar; shu orada bazada o‘zgargani — conflict', () => {
  const r = P(S.acadPlan([
    { id: 'a', loaded: '4', val: '5', cur: '4', touched: true },        // o'zgartirildi — yoziladi
    { id: 'b', loaded: '4', val: '4', cur: '3', touched: false },       // tegilmagan — yozilmaydi (boshqa xodim qo'ygan 3 saqlanadi)
    { id: 'c', loaded: '3', val: '5', cur: '4', touched: true },        // O'IBDO' shu orada 4 qilgan — eski nusxa ustiga yozilmaydi
    { id: 'd', loaded: '3', val: '4', cur: '4', touched: true },        // bazada allaqachon shu qiymat
    { id: 'e', loaded: 'Matn', val: '', cur: 'Matn', touched: true },   // bo'shatildi — o'chiriladi
    { id: 'f', loaded: '', val: '', cur: '', touched: true },           // yozib, qayta o'chirdi — hech narsa
    { id: 'g', loaded: '', val: 'Yangi', cur: '', touched: true },      // yangi
    { id: 'h', loaded: '5', val: '5', cur: '5', touched: true },        // o'zgartirib, qaytardi — hech narsa
  ]));
  assert.deepEqual(r, { write: ['a', 'g'], del: ['e'], conflict: ['c'], same: ['d'] });
});

test('monScoreErr: 0–100, ko‘pi bilan bir kasr xonasi (A3-03)', () => {
  for (const ok of ['', '0', '95', '95.5', '100', '100.0', '07']) assert.equal(S.monScoreErr(ok), '', ok);
  for (const bad of ['950', '101', '100.5', '-40', '95.55', 'abc', '1e2', '9 5']) assert.notEqual(S.monScoreErr(bad), '', bad);
  assert.match(S.monScoreErr('950'), /0–100/);
});

test('A3-01: o‘qituvchining eskirgan sahifasi — O‘IBDO‘ tasdiqlagan qatorlar qayta «Kutilmoqda»ga tushmaydi', () => {
  // 30 o'quvchi ochilganda kutilmoqda edi; O'IBDO' hammasini tasdiqladi; o'qituvchi bitta xatoni tuzatib «Saqlash» bosdi.
  const rows = Array.from({ length: 30 }, (_, i) => ({ id: 'S' + i, loaded: pend(80 + (i % 10)), cur: appr(80 + (i % 10)), val: String(80 + (i % 10)), touched: false }));
  rows[7] = Object.assign({}, rows[7], { val: '88', touched: true });
  const r = P(S.monPlan(rows, { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.write, [], 'hech narsa yozilmaydi (avval 30 tasi ham pending bo‘lib yozilardi)');
  assert.deepEqual(r.conflict, ['S7'], 'tuzatilgan qator — shu orada tasdiqlangan: ogohlantiriladi');
});

test('o‘qituvchi: o‘zgartirilgan kutilayotgan ball — pending; tegilmaganlar yozilmaydi', () => {
  const r = P(S.monPlan([
    { id: 'a', loaded: pend(70), cur: pend(70), val: '75', touched: true },
    { id: 'b', loaded: pend(60), cur: pend(60), val: '60', touched: false },
    { id: 'c', loaded: null, cur: null, val: '90', touched: true },
    { id: 'd', loaded: null, cur: null, val: '', touched: false },
  ], { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.write, [{ id: 'a', score: 75, status: 'pending' }, { id: 'c', score: 90, status: 'pending' }]);
  assert.deepEqual([r.del, r.conflict, r.locked, r.errors], [[], [], [], []]);
});

test('A3-06: o‘qituvchi o‘zi kiritgan tasdiqlanmagan ballni o‘chiradi; boshqanikini / tasdiqlanganini — yo‘q', () => {
  const r = P(S.monPlan([
    { id: 'own', loaded: pend(70, 'U_T'), cur: pend(70, 'U_T'), val: '', touched: true },
    { id: 'other', loaded: pend(70, 'U_X'), cur: pend(70, 'U_X'), val: '', touched: true },
    { id: 'ok', loaded: appr(70, 'U_T'), cur: appr(70, 'U_T'), val: '', touched: true },
  ], { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.del, ['own']);
  assert.deepEqual(r.locked, [{ id: 'other', why: 'notmine' }, { id: 'ok', why: 'approved' }]);
});

test('A3-08: O‘IBDO‘ «Saqlash» — tasdiqlamaydi; faqat o‘zgartirilgan qatorlar (kutilmoqda)', () => {
  const r = P(S.monPlan([
    { id: 'a', loaded: pend(70), cur: pend(70), val: '72', touched: true },
    { id: 'b', loaded: pend(60), cur: pend(60), val: '60', touched: false },
    { id: 'c', loaded: appr(90), cur: appr(90), val: '95', touched: true },   // tasdiqlangan ball o'zgardi — qayta tasdiqlashga
  ], { approve: false, canApprove: true, me: 'U_Z' }));
  assert.deepEqual(r.write, [{ id: 'a', score: 72, status: 'pending' }, { id: 'c', score: 95, status: 'pending' }]);
});

test('«Saqlash va tasdiqlash»: o‘zgartirilganlar + ekranda ko‘rilgan kutilayotgan ballar; o‘qituvchi shu orada tuzatgani — tegilmaydi', () => {
  const r = P(S.monPlan([
    { id: 'chg', loaded: pend(70), cur: pend(70), val: '74', touched: true },     // O'IBDO' tuzatib tasdiqlaydi
    { id: 'seen', loaded: pend(85), cur: pend(85), val: '85', touched: false },   // ko'rilgan qiymat — tasdiqlanadi
    { id: 'moved', loaded: pend(60), cur: pend(66), val: '60', touched: false },  // o'qituvchi shu orada 66 qilgan — eski 60 tasdiqlanmaydi
    { id: 'done', loaded: appr(99), cur: appr(99), val: '99', touched: false },   // allaqachon tasdiqlangan — yozilmaydi
    { id: 'byother', loaded: pend(50), cur: appr(50), val: '50', touched: false },// boshqa O'IBDO' shu qiymatni tasdiqlagan — yozilmaydi
    { id: 'gone', loaded: pend(40), cur: null, val: '40', touched: false },       // o'chirilgan — qayta yaratilmaydi
  ], { approve: true, canApprove: true, me: 'U_Z' }));
  assert.deepEqual(r.write, [{ id: 'chg', score: 74, status: 'approved' }, { id: 'seen', score: 85, status: 'approved' }]);
  assert.deepEqual(r.conflict, ['moved', 'gone']);
  assert.deepEqual(r.same, ['byother']);
});

test('O‘IBDO‘ bo‘shatgan maydon — o‘chiriladi (tasdiqlangani ham); yangi ball shu orada boshqa yozgan bo‘lsa — conflict', () => {
  const r = P(S.monPlan([
    { id: 'x', loaded: appr(70, 'U_T'), cur: appr(70, 'U_T'), val: '', touched: true },
    { id: 'n1', loaded: null, cur: null, val: '81', touched: true },
    { id: 'n2', loaded: null, cur: pend(70), val: '81', touched: true },
    { id: 'n3', loaded: null, cur: appr(81), val: '81', touched: true },
  ], { approve: true, canApprove: true, me: 'U_Z' }));
  assert.deepEqual(r.del, ['x']);
  assert.deepEqual(r.write, [{ id: 'n1', score: 81, status: 'approved' }]);
  assert.deepEqual(r.conflict, ['n2']);
  assert.deepEqual(r.same, ['n3']);
});

test('A3-03: noto‘g‘ri ball (950, brauzer o‘qiy olmagan matn) — xato ro‘yxati; to‘g‘rilari reja qilinadi, lekin ekran saqlashni to‘xtatadi', () => {
  const r = P(S.monPlan([
    { id: 'a', loaded: null, cur: null, val: '950', touched: true },
    { id: 'b', loaded: pend(70), cur: pend(70), val: '', bad: true, touched: true },   // type=number: «9 5» -> value '' (o'chirish EMAS)
    { id: 'c', loaded: null, cur: null, val: '95', touched: true },
  ], { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.errors.map(e => e.id), ['a', 'b']);
  assert.deepEqual(r.del, [], 'brauzer o‘qiy olmagan qiymat o‘chirish deb olinmaydi');
  assert.deepEqual(r.write, [{ id: 'c', score: 95, status: 'pending' }]);
});

test('balsiz eski qator — yo‘q hisoblanadi (soxta conflict bo‘lmaydi)', () => {
  const r = P(S.monPlan([{ id: 'a', loaded: { score: null, status: 'pending' }, cur: { score: null, status: 'pending' }, val: '77', touched: true }],
    { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.write, [{ id: 'a', score: 77, status: 'pending' }]);
});
