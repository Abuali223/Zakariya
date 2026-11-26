// F2.13 qayta tasnif dalolatnomasi — sahifa yordamchilari (fin-kassa.js) va bosma (fin-print.js) sinovi:
//   node --test assets/js/fin-fix.test.mjs
//   fixable (kim, qaysi order), fixBadge (belgi), fixCurrent (amaldagi holat), fixPayload / fixChanged (faqat o'zgargan qismlar),
//   fixDiff (o'zgarishlar ro'yxati), fixNo va fixActHtml (uch tilda: sarlavha, raqam, avval / keyin jadvali, tuzatish yozuvi, imzolar,
//   belgilar). Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as W from './fin-words.js';
import { fixable, fixBadge, fixCurrent, fixPayload, fixChanged } from './fin-kassa.js';
import { fixDiff, fixNo, fixActHtml } from './fin-print.js';

const text = h => h.replace(/<style[\s\S]*?<\/style>/g, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
  .replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim();
const org = { nameUz: '«SINOV MAKTAB» МЧЖ', nameRu: 'ООО «SINOV MAKTAB»', stir: '123456789', place: 'Тошкент ш.', printLang: 'uz-cyrl', extra: {} };
const articles = [{ id: 'EX-32', nameUz: 'Kanselyariya', nameRu: 'Канцелярия' }, { id: 'OP-18', nameUz: 'Asosiy vosita', nameRu: 'Основное средство' },
  { id: 'EX-49', nameUz: 'Boshqa xarajatlar', nameRu: 'Прочие расходы' }, { id: 'EX-16', nameUz: 'Xo‘jalik vositalari', nameRu: 'Хозтовары' }];
const doc = { id: 'd1', status: 'posted', form: 'KO2', op: 'out_expense', no: 3, businessDay: '2027-01-05', amount: 600000, partyType: 'counterparty',
  partyId: 'cp1', partyName: 'Sinov Ta‘minotchi', basis: 'Hisob-faktura № 0-12', fixes: [],
  lines: [{ lineNo: 1, articleId: 'EX-32', debit: '9420', amount: 400000, cash: true }, { lineNo: 2, articleId: 'EX-49', debit: '9430', amount: 200000, cash: true }] };
const L2 = { list2: true }, DIR = { director: true };

test('fixable: faqat 2-ro‘yxat, o‘tkazilgan «Xarajat» KO-2, kuni bugundan oldin', () => {
  assert.equal(fixable(doc, L2, '2027-02-10'), true);
  assert.equal(fixable(doc, DIR, '2027-02-10'), false, 'Direktor so‘ramaydi');
  assert.equal(fixable(doc, { operator: true }, '2027-02-10'), false);
  assert.equal(fixable(doc, L2, '2027-01-05'), false, 'bugungi (ochiq) kun — kassir bekor qilib qayta yozadi');
  assert.equal(fixable(Object.assign({}, doc, { status: 'void' }), L2, '2027-02-10'), false);
  assert.equal(fixable(Object.assign({}, doc, { op: 'out_salary' }), L2, '2027-02-10'), false);
  assert.equal(fixable(Object.assign({}, doc, { form: 'KO1', op: 'in_other' }), L2, '2027-02-10'), false);
  assert.equal(fixable(Object.assign({}, doc, { businessDay: null }), L2, '2027-02-10'), false);
  assert.equal(fixable(null, L2, '2027-02-10'), false);
});

test('fixBadge: tasdiqlangan raqamlar va kutilayotgan so‘rov', () => {
  assert.equal(fixBadge(doc), '');
  assert.equal(fixBadge({ fixes: [{ status: 'approved', no: 1 }, { status: 'approved', no: 4 }] }), 'QT-1 · QT-4');
  assert.equal(fixBadge({ fixes: [{ status: 'approved', no: 2 }, { status: 'pending' }] }), 'QT-2 · QT kutilmoqda');
  assert.equal(fixBadge({ fixes: [{ status: 'pending' }] }), 'QT kutilmoqda');
});

test('fixCurrent: asl order (naqd qatorlar) yoki server bergan amaldagi holat', () => {
  const c = fixCurrent(Object.assign({}, doc, { lines: doc.lines.concat([{ lineNo: 3, articleId: 'X', debit: '6310', amount: 1, cash: false }]) }));
  assert.deepEqual(c, { partyType: 'counterparty', partyId: 'cp1', partyName: 'Sinov Ta‘minotchi', basis: 'Hisob-faktura № 0-12',
    lines: [{ lineNo: 1, articleId: 'EX-32', debit: '9420', amount: 400000 }, { lineNo: 2, articleId: 'EX-49', debit: '9430', amount: 200000 }] });
  const eff = { partyType: 'other', partyId: null, partyName: 'Sinov Shaxs', basis: 'b', lines: [], fixNo: 2 };
  assert.equal(fixCurrent(Object.assign({}, doc, { eff })), eff);
});

test('fixPayload: faqat o‘zgargan qismlar; sabab har doim', () => {
  const cur = fixCurrent(doc);
  const same = fixPayload(cur, { arts: { 1: 'EX-32', 2: 'EX-49' }, ptype: 'counterparty', pid: 'cp1', basis: ' Hisob-faktura № 0-12 ', reason: ' x ' });
  assert.deepEqual(same, { reason: 'x' }); assert.equal(fixChanged(same), false);
  const p = fixPayload(cur, { arts: { 1: 'OP-18', 2: 'EX-49' }, ptype: 'counterparty', pid: 'cp2', basis: 'Yangi asos', reason: 'Printer — asosiy vosita' });
  assert.deepEqual(p, { lines: [{ lineNo: 1, articleId: 'OP-18' }], party: { type: 'counterparty', id: 'cp2' }, basis: 'Yangi asos', reason: 'Printer — asosiy vosita' });
  assert.equal(fixChanged(p), true);
  assert.deepEqual(fixPayload(cur, { arts: {}, ptype: 'other', pname: '  Sinov Shaxs ', basis: cur.basis, reason: 'r' }), { party: { type: 'other', name: 'Sinov Shaxs' }, reason: 'r' });
  // «boshqa» tomonning ismi o'zgarmasa — tomon yo'q; o'zgarsa — bor
  const oc = { partyType: 'other', partyId: null, partyName: 'Sinov Shaxs', basis: '', lines: [] };
  assert.deepEqual(fixPayload(oc, { ptype: 'other', pname: 'Sinov Shaxs', basis: '', reason: 'r' }), { reason: 'r' });
  assert.deepEqual(fixPayload(oc, { ptype: 'other', pname: 'Sinov Boshqa', basis: '', reason: 'r' }), { party: { type: 'other', name: 'Sinov Boshqa' }, reason: 'r' });
  // asosni bo'shatish ham o'zgarish (server 3 belgidan qisqasini rad etadi)
  assert.equal(fixChanged(fixPayload(cur, { ptype: 'counterparty', pid: 'cp1', basis: '', reason: 'r' })), true);
});

const fix = { id: 'fx_1', no: 7, year: 2027, actDay: '2027-02-10', status: 'approved', reason: 'Printer — asosiy vosita, kanselyariya emas',
  decisionNote: 'Roziman', requestedByName: 'Sinov Buxgalter', decidedByName: 'Sinov Direktor',
  doc: { no: 3, businessDay: '2027-01-05', amount: 600000, postedByName: 'Sinov Kassir' },
  before: { partyType: 'counterparty', partyId: 'cp1', partyName: 'Sinov Ta‘minotchi', basis: 'Hisob-faktura № 0-12',
    lines: [{ lineNo: 1, articleId: 'EX-32', debit: '9420', amount: 400000 }, { lineNo: 2, articleId: 'EX-49', debit: '9430', amount: 200000 }] },
  after: { partyType: 'counterparty', partyId: 'cp2', partyName: 'Sinov Ijarachi', basis: 'Hisob-faktura № 0-12',
    lines: [{ lineNo: 1, articleId: 'OP-18', debit: '0820', amount: 400000 }, { lineNo: 2, articleId: 'EX-16', debit: '9430', amount: 200000 }] } };

test('fixDiff: statiya (qator, summa), oluvchi, asos — faqat o‘zgarganlari', () => {
  assert.deepEqual(fixDiff(fix), [
    { kind: 'article', lineNo: 1, amount: 400000, from: { articleId: 'EX-32', debit: '9420' }, to: { articleId: 'OP-18', debit: '0820' } },
    { kind: 'article', lineNo: 2, amount: 200000, from: { articleId: 'EX-49', debit: '9430' }, to: { articleId: 'EX-16', debit: '9430' } },
    { kind: 'party', from: { type: 'counterparty', id: 'cp1', name: 'Sinov Ta‘minotchi' }, to: { type: 'counterparty', id: 'cp2', name: 'Sinov Ijarachi' } }]);
  assert.deepEqual(fixDiff({ before: { basis: '' }, after: { basis: 'Chek № 0-55' } }), [{ kind: 'basis', from: '', to: 'Chek № 0-55' }]);
  assert.deepEqual(fixDiff({}), []);
});

test('fixActHtml (o‘zbek kirill): sarlavha, raqam, order, jadval, tuzatish yozuvi, imzolar', () => {
  const h = fixActHtml(fix, { org, articles, printedBy: 'Sinov Buxgalter', printedAt: '2027-02-10T05:00:00Z' }, W), t = text(h);
  assert.equal(fixNo(fix, { org }), 'ҚТ-7');
  assert.match(t, /ҚАЙТА ТАСНИФ ДАЛОЛАТНОМАСИ № ҚТ-7/);
  assert.match(t, /Тузатилаётган ҳужжат: чиқим касса ордери № Ч-3; сана 05\.01\.2027; сумма 600 000=00 ?; кассир Sinov Kassir/);
  assert.match(t, /Низом 143, 25-банд/);
  assert.match(t, /Статья \(1-қатор, 400 000=00\) EX-32 Kanselyariya \(Дт 9420\) OP-18 Asosiy vosita \(Дт 0820\)/);
  assert.match(t, /Статья \(2-қатор, 200 000=00\) EX-49 Boshqa xarajatlar \(Дт 9430\) EX-16 Xo‘jalik vositalari \(Дт 9430\)/);
  assert.match(t, /Олувчи Sinov Ta‘minotchi Sinov Ijarachi/);
  assert.doesNotMatch(t, /Асоси Hisob/, 'asos o‘zgarmagan — jadvalda yo‘q');
  assert.match(t, /Тузатиш ёзуви: Дт 0820 — Кт 9420: 400 000=00/);
  assert.doesNotMatch(t, /Кт 9430/, 'hisobvaraq o‘zgarmagan qator — tuzatish yozuvi yo‘q');
  assert.match(t, /Тузатиш сабаби: Printer — asosiy vosita, kanselyariya emas/);
  assert.match(t, /Директор изоҳи: Roziman/);
  assert.match(t, /Тузди .*Sinov Buxgalter/); assert.match(t, /Тасдиқлади: Директор .*Sinov Direktor/);
  assert.doesNotMatch(t, /ҚОРАЛАМА|СИНОВ/);
  assert.match(h, /^<!DOCTYPE html><html lang="uz">/);
});

test('fixActHtml: rus va o‘zbek lotin tili; qoralama va sinov belgisi; faqat statiya o‘zgarganda — hisobvaraq yozuvi yo‘q', () => {
  const ru = text(fixActHtml(fix, { org: Object.assign({}, org, { printLang: 'ru' }), articles }, W));
  assert.match(ru, /АКТ ПЕРЕКЛАССИФИКАЦИИ № АП-7/);
  assert.match(ru, /расходный кассовый ордер № Р-3/);
  assert.match(ru, /Статья \(строка 1, 400 000=00\) EX-32 Канцелярия \(Дт 9420\) OP-18 Основное средство \(Дт 0820\)/);
  assert.match(ru, /Утвердил: директор/);
  const la = text(fixActHtml(fix, { org: Object.assign({}, org, { printLang: 'uz-latn' }), articles }, W));
  assert.match(la, /QAYTA TASNIF DALOLATNOMASI № QT-7/); assert.match(la, /\(Dt 0820\)/); assert.match(la, /Tuzatish yozuvi: Dt 0820 — Kt 9420/);
  const only = Object.assign({}, fix, { status: 'pending', no: null, decidedByName: null,
    after: Object.assign({}, fix.before, { lines: [fix.before.lines[0], { lineNo: 2, articleId: 'EX-16', debit: '9430', amount: 200000 }] }) });
  const t = text(fixActHtml(only, { org, articles, isTest: true }, W));
  assert.match(t, /СИНОВ/); assert.match(t, /ҚОРАЛАМА/); assert.match(t, /№ —/);
  assert.match(t, /Тузатиш ёзуви: Ҳисобварақ ўзгармади — фақат таҳлилий тасниф/);
  assert.doesNotMatch(t, /Олувчи Sinov/, 'oluvchi o‘zgarmagan');
});
