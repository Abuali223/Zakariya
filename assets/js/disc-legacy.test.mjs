// disc-legacy.test.mjs — A8-01: admin.html discountEffective / discApplyEff (billing chegirmani tasdiqlangan so'rovlardan oladi).
//   node --test assets/js/disc-legacy.test.mjs
//   Qoida: eski deploy tasdiqlangan muddatli / kelajakdagi so'rovdan olgan muddatsiz «meros» nusxa (shu guruhda undan OLDIN so'ralgan
//   oddiy tasdiqlangan so'rov bor) hisobga olinmaydi; haqiqiy meros (hech qanday so'rovdan oldin) — avvalgidek, muddatli so'rov
//   tugagach yana amal qiladi. Funksiyalar admin.html'dan o'qiladi (nusxa emas). Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
// «function nom(» dan mos yopuvchi qavsgacha (funksiyalar ichida qavsli satr yo'q).
function fnSrc(name) {
  const i = ADM.indexOf('function ' + name + '(');
  assert.ok(i >= 0, name + ' topilmadi');
  assert.equal(ADM.indexOf('function ' + name + '(', i + 1), -1, name + ' bitta bo‘lsin');
  let d = 0;
  for (let k = ADM.indexOf('{', i); k < ADM.length; k++) {
    if (ADM[k] === '{') d++;
    else if (ADM[k] === '}' && --d === 0) return ADM.slice(i, k + 1);
  }
  throw new Error(name + ' yopilmadi');
}
const ctx = vm.createContext({});
vm.runInContext([fnSrc('discGroup'), fnSrc('discountEffective'), fnSrc('discApplyEff')].join('\n')
  + '\n;this.__d = { discountEffective, discApplyEff };', ctx);
const { discountEffective, discApplyEff } = ctx.__d;
// PostgREST timestamptz (mikrosoniya) va shim o'rami (sb/firebase-firestore.js wrapVal: toString/valueOf — ISO satr).
const ts = s => ({ toDate: () => new Date(s), toString: () => s, valueOf: () => s });
const R = o => Object.assign({ status: 'approved', legacy: false, params: {} }, o);
const cat = (reqs, sid, m) => { const e = discountEffective(reqs, m).bySid[sid]; return e && e.cat ? e.cat.id : null; };
const sib = (reqs, sid, m) => { const e = discountEffective(reqs, m).bySid[sid]; return e && e.sib ? e.sib.id : null; };

// (a) 50% faqat 2026-12 (so'rov 15-oktabr, tasdiq 16-oktabr); eski deploy nusxasi 1-noyabr.
const ra = R({ id: 'ra', studentId: 'IQ-1', kind: 'teacher_child', fromMonth: '2026-12', toMonth: '2026-12',
  requestedAt: '2026-10-15T09:00:00.123456+00:00', directorAt: '2026-10-16T08:00:00+00:00', financeAt: '2026-10-16T09:00:00+00:00', appliedAt: '2026-10-16T09:00:00+00:00' });
const la = R({ id: 'legacy__IQ-1__cat', studentId: 'IQ-1', kind: 'teacher_child', legacy: true, requestedAt: '2026-11-01T03:00:00+00:00', appliedAt: '2026-11-01T03:00:00+00:00' });
// (b) 100% grant 2027-06 dan; nusxa.
const rb = R({ id: 'rb', studentId: 'IQ-2', kind: 'olympiad', fromMonth: '2027-06', toMonth: null, requestedAt: ts('2026-10-20T09:00:00+00:00'), appliedAt: ts('2026-10-21T09:00:00+00:00') });
const lb = R({ id: 'legacy__IQ-2__cat', studentId: 'IQ-2', kind: 'olympiad', legacy: true, requestedAt: ts('2026-11-01T03:00:00+00:00'), appliedAt: ts('2026-11-01T03:00:00+00:00') });
// (c) haqiqiy meros 50% (1-avgust, birinchi deploy) + keyin faqat 2027-01 uchun grant; aka-uka merosi ham bor (boshqa guruh).
const lc = R({ id: 'legacy__IQ-3__cat', studentId: 'IQ-3', kind: 'teacher_child', legacy: true, requestedAt: '2026-08-01T03:00:00+00:00', appliedAt: '2026-08-01T03:00:00+00:00' });
const rc = R({ id: 'rc', studentId: 'IQ-3', kind: 'social', fromMonth: '2027-01', toMonth: '2027-01', requestedAt: '2026-10-15T09:00:00+00:00', appliedAt: '2026-10-16T09:00:00+00:00' });
const lcs = R({ id: 'legacy__IQ-3__sib', studentId: 'IQ-3', kind: 'sibling_force', legacy: true, requestedAt: '2026-11-01T03:00:00+00:00', appliedAt: '2026-11-01T03:00:00+00:00' });
const ALL = [ra, la, rb, lb, lc, rc, lcs];

test('(a) vaqtinchalik chegirma: faqat o‘z oyida; deploy nusxasi boshqa oylarga tarqatmaydi', () => {
  assert.equal(cat(ALL, 'IQ-1', '2026-12'), 'ra');
  assert.equal(cat(ALL, 'IQ-1', '2027-02'), null);
  assert.equal(cat(ALL, 'IQ-1', '2026-11'), null);
});

test('(b) kelajakdagi grant: boshlanishidan oldin yo‘q, keyin — so‘rovning o‘zi (shim o‘ralgan vaqt bilan ham)', () => {
  assert.equal(cat(ALL, 'IQ-2', '2027-01'), null);
  assert.equal(cat(ALL, 'IQ-2', '2027-07'), 'rb');
});

test('(c) haqiqiy meros saqlanadi: muddatli grant oyida — grant, undan keyin — yana meros; boshqa guruh merosiga tegilmaydi', () => {
  assert.equal(cat(ALL, 'IQ-3', '2026-12'), 'legacy__IQ-3__cat');
  assert.equal(cat(ALL, 'IQ-3', '2027-01'), 'rc');
  assert.equal(cat(ALL, 'IQ-3', '2027-02'), 'legacy__IQ-3__cat');
  assert.equal(sib(ALL, 'IQ-3', '2027-02'), 'legacy__IQ-3__sib', 'aka-uka guruhida oddiy so‘rov yo‘q — meros');
});

test('bekor qilingan (bazada tuzatilgan) nusxa ham, rad etilgan so‘rov ham hisobga olinmaydi', () => {
  const L = [ra, Object.assign({}, la, { status: 'canceled' }), R({ id: 'rx', studentId: 'IQ-1', kind: 'olympiad', status: 'rejected', fromMonth: '2027-02', requestedAt: '2026-10-01T00:00:00+00:00' })];
  assert.equal(cat(L, 'IQ-1', '2027-02'), null);
  assert.equal(cat(L, 'IQ-1', '2026-12'), 'ra');
});

test('vaqti noma’lum meros (requestedAt yo‘q) — ehtiyotkorlik bilan saqlanadi (eski xulq)', () => {
  const L = [ra, Object.assign({}, la, { requestedAt: null })];
  assert.equal(cat(L, 'IQ-1', '2027-02'), 'legacy__IQ-1__cat');
});

test('discApplyEff (yangi qoida): nusxa ishorasi fakturaga tushmaydi, toifa bo‘sh — oddiy narx', () => {
  const eff = discountEffective(ALL, '2027-02');
  const o = discApplyEff({ specialCategory: 'teacher_child' }, eff, 'IQ-1', true);
  assert.equal(o.specialCategory, '');
  assert.deepEqual(Array.from(o._approvalRefs), []);
  const d = discApplyEff({}, discountEffective(ALL, '2026-12'), 'IQ-1', true);
  assert.equal(d.specialCategory, 'teacher_child');
  assert.deepEqual(Array.from(d._approvalRefs), ['ra']);
  const g = discApplyEff({}, discountEffective(ALL, '2027-01'), 'IQ-3', true);
  assert.equal(g.specialCategory, 'olympiad', 'ijtimoiy himoya — olimpiada granti kabi');
  assert.deepEqual(Array.from(g._approvalRefs), ['rc', 'legacy__IQ-3__sib']);
});
