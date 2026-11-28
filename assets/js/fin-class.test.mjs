// fin-class.js (F2.3 — noyabr–yanvar eski xarajatlariga statiya) sinovi (faqat sof qism):  node --test assets/js/fin-class.test.mjs
//   Oy yorlig'i va standart oy, oy holati (qisman / imzo kutilmoqda / imzolangan / eskirgan), yozuv holati, yuboriladigan qatorlar
//   (o'zgargan, faqat izoh, belgilab tasdiqlash, yopilgan davr, statiyasiz, «Boshqa» izohsiz), oy yig'masi («Boshqa» ulushi, statiyalar
//   bo'yicha); tasnif davri server bilan bir xil (fin-class.sql: app.fin_class_months). Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { MONTHS, monthLabelUz, defaultMonth, monthStatus, rowStatus, buildItems, monthSummary } from './fin-class.js';

const months = (a, b, c) => [{ month: '2026-11', ...a }, { month: '2026-12', ...b }, { month: '2027-01', ...c }];
const arts = [{ id: 'EX-16', needsNote: false }, { id: 'EX-49', needsNote: true }, { id: 'EX-32', needsNote: false }];

test('tasnif davri server bilan bir xil (fin-class.sql: app.fin_class_months)', () => {
  const sql = fs.readFileSync(fileURLToPath(new URL('../../migration/fin-class.sql', import.meta.url)), 'utf8');
  const m = sql.match(/fin_class_months\(\) returns text\[\][\s\S]*?array\[([^\]]+)\]/);
  assert.ok(m, 'fin_class_months topilmadi');
  assert.deepEqual(m[1].split(',').map(s => s.trim().replace(/'/g, '')), MONTHS);
});

test('oy yorlig‘i va standart oy: bugungi oy davrda; aks holda tasdiqlanmagani bor birinchi oy; hammasi tayyor — davr oxiri (bugun keyin) yoki boshi', () => {
  assert.equal(monthLabelUz('2026-11'), 'Noyabr 2026'); assert.equal(monthLabelUz('2027-01'), 'Yanvar 2027'); assert.equal(monthLabelUz('x'), 'x');
  const ms = months({ n: 3, confirmed: 3 }, { n: 2, confirmed: 1 }, { n: 0, confirmed: 0 });
  assert.equal(defaultMonth(ms, '2027-01-20'), '2027-01');
  assert.equal(defaultMonth(ms, '2027-03-01'), '2026-12');
  const done = months({ n: 3, confirmed: 3 }, { n: 2, confirmed: 2 }, { n: 0, confirmed: 0 });
  assert.equal(defaultMonth(done, '2027-03-01'), '2027-01');
  assert.equal(defaultMonth(done, '2026-10-01'), '2026-11');
  assert.equal(defaultMonth([], '2026-11-02'), '');
});

test('oy holati: yozuvsiz, qisman (oldingi imzo eskirgan bilan), imzo kutilmoqda, imzolangan (kim, sana), imzo eskirgan', () => {
  assert.deepEqual(monthStatus({ n: 0 }), { level: 'none', text: 'eski yozuv yo‘q' });
  assert.deepEqual(monthStatus({ n: 5, confirmed: 3 }), { level: 'warn', text: 'qisman: 5 tadan 3 tasi tasdiqlangan' });
  assert.match(monthStatus({ n: 5, confirmed: 4, sign: { valid: false } }).text, /oldingi imzo eskirgan$/);
  assert.deepEqual(monthStatus({ n: 2, confirmed: 2, sign: null }), { level: 'info', text: 'hammasi tasdiqlangan — buxgalter imzosi kutilmoqda' });
  assert.deepEqual(monthStatus({ n: 2, confirmed: 2, sign: { valid: true, by: 'Sinov Buxgalter', at: '2026-12-29T10:00:00+05:00' } }),
    { level: 'ok', text: 'imzolangan — Sinov Buxgalter, 29.12.2026' });
  assert.deepEqual(monthStatus({ n: 2, confirmed: 2, sign: { valid: false } }), { level: 'warn', text: 'imzo eskirgan — keyin o‘zgargan, qayta imzolash kerak' });
});

test('yozuv holati: tasdiqlangan (kim), toifadan taxminiy, statiyasiz', () => {
  assert.deepEqual(rowStatus({ confirmed: true, articleId: 'EX-16', last: { by: 'Sinov Buxgalter' } }), { level: 'ok', text: '✓ tasdiqlangan — Sinov Buxgalter' });
  assert.deepEqual(rowStatus({ confirmed: false, articleId: 'EX-11' }), { level: 'warn', text: '≈ taxminiy (toifadan)' });
  assert.deepEqual(rowStatus({ confirmed: false, articleId: null }), { level: 'bad', text: 'statiyasiz' });
});

test('yuboriladigan qatorlar: o‘zgargan statiya, faqat izoh, belgilab tasdiqlash; tasdiqlangan va o‘zgarmagani — yo‘q; yopilgan davr — o‘tkaziladi', () => {
  const rows = [
    { id: 'a', articleId: 'EX-11', confirmed: false },                                   // statiya o'zgaradi
    { id: 'b', articleId: 'EX-32', confirmed: false },                                   // belgilab tasdiqlanadi
    { id: 'c', articleId: 'EX-16', confirmed: true, last: { note: 'eski' } },            // faqat izoh o'zgaradi
    { id: 'd', articleId: 'EX-16', confirmed: true, last: { note: '' } },                // belgilangan, lekin tasdiqlangan — yo'q
    { id: 'e', articleId: 'EX-32', confirmed: false, locked: true },                     // yopilgan davr
    { id: 'f', articleId: 'EX-32', confirmed: false }];                                  // tegilmagan
  const r = buildItems(rows, { a: { articleId: 'EX-16' }, c: { note: '  yangi izoh ' }, e: { articleId: 'EX-16' } }, new Set(['b', 'd', 'e']), arts);
  assert.deepEqual(r, { items: [{ id: 'a', articleId: 'EX-16', note: '' }, { id: 'b', articleId: 'EX-32', note: '' }, { id: 'c', articleId: 'EX-16', note: 'yangi izoh' }], errs: [] });
});

test('yuboriladigan qatorlar: statiya tanlanmagan, «Boshqa» izohsiz — xato; oldingi tasnif izohi saqlanadi; o‘sha statiyaga qaytarish — o‘zgarish emas', () => {
  const rows = [{ id: 'n', articleId: null, confirmed: false }, { id: 'x', articleId: 'EX-11', confirmed: false },
                { id: 'y', articleId: 'EX-49', confirmed: true, last: { note: 'Turli xarid' } }, { id: 'z', articleId: 'EX-16', confirmed: false }];
  const r = buildItems(rows, { x: { articleId: 'EX-49', note: 'ab' }, y: { articleId: 'EX-32' }, z: { articleId: 'EX-16' } }, new Set(['n']), arts);
  assert.deepEqual(r.errs, [{ id: 'n', why: 'statiya tanlanmagan' }, { id: 'x', why: 'bu statiya uchun tasnif izohi majburiy' }]);
  assert.deepEqual(r.items, [{ id: 'y', articleId: 'EX-32', note: 'Turli xarid' }]);
  assert.deepEqual(buildItems([{ id: 'x', articleId: 'EX-11', confirmed: false }], { x: { articleId: 'EX-49', note: 'Mayda xarid' } }, null, arts).items,
    [{ id: 'x', articleId: 'EX-49', note: 'Mayda xarid' }]);
  assert.deepEqual(buildItems(null, null, null, null), { items: [], errs: [] });
});

test('oy yig‘masi: soni, jami, tasdiqlangan, statiyasiz, «Boshqa» summasi va ulushi (2 % dan ko‘p — e’tibor), statiyalar kamayish tartibida', () => {
  const s = monthSummary([{ amount: 900000, articleId: 'EX-10', confirmed: true }, { amount: 60000, articleId: 'EX-49', confirmed: false },
                          { amount: 40000, articleId: null, confirmed: false }]);
  assert.deepEqual(s, { n: 3, total: 1000000, confirmed: 1, none: 1, ex49: 60000, ex49Share: 6, ex49Warn: true,
    byArticle: [{ articleId: 'EX-10', sum: 900000 }, { articleId: 'EX-49', sum: 60000 }, { articleId: '', sum: 40000 }] });
  assert.equal(monthSummary([{ amount: 1000, articleId: 'EX-49' }, { amount: 99000, articleId: 'EX-16' }]).ex49Warn, false);
  assert.deepEqual(monthSummary([]), { n: 0, total: 0, confirmed: 0, none: 0, ex49: 0, ex49Share: 0, ex49Warn: false, byArticle: [] });
});
