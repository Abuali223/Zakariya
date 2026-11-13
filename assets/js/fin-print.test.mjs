// fin-print.js sinovi:  node --test assets/js/fin-print.test.mjs
//   Chop etish shakllarining MATNI tekshiriladi (KO-1 + patta, KO-2, KO-4, sanash dalolatnomasi) — uch tilda;
//   kassirning kunlik hisoboti (RP-02) — o'zbek lotin va rus tilida, jamlari KO-4 bilan solishtiriladi.
//   Ma'lumotlar to'qima (haqiqiy ism, summa yo'q). Kutilgan satrlar qo'lda yozilgan.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as W from './fin-words.js';
import { docHtml, bookHtml, countHtml, bookRows, reportHtml, journalHtml, journalSheet, matrixHtml, matrixSheet, daysSheet, advSheet, packSheets } from './fin-print.js';
import { createRequire } from 'node:module';

const org = { nameUz: '«SINOV MAKTAB» МЧЖ', nameRu: 'ООО «SINOV MAKTAB»', stir: '123456789', place: 'Тошкент ш.', printLang: 'uz-cyrl', extra: {} };
const signatories = [
  { id: 's1', list: 1, uid: 'u_dir', title: 'Директор', fullName: 'Синов Д.Д.', active: true },
  { id: 's2', list: 2, uid: 'u_acc', title: 'Бош бухгалтер', fullName: 'Синов Б.Б.', active: true },
];
const names = { u_kas: 'Sinov Kassir', u_kas2: 'Sinov Kassir 2', u_dir: 'Sinov Direktor', u_acc: 'Sinov Buxgalter', u_mm: 'Sinov Moliya' };
const ctx = (over) => Object.assign({ org, signatories, names, isTest: false, mark: { mode: 'original' }, printedBy: 'Sinov Kassir', printedAt: '2027-01-04T05:11:00Z' }, over || {});
// HTML -> ko'rinadigan matn (teglar olib tashlanadi, bo'shliqlar bittaga keltiriladi)
const text = h => h.replace(/<style[\s\S]*?<\/style>/g, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/\s+/g, ' ').trim();
const count = (s, sub) => s.split(sub).length - 1;

const ko1 = {
  id: 'cd_0001', form: 'KO1', op: 'in_tuition', status: 'posted', no: 12, year: 2027, businessDay: '2027-01-04', amount: 2350000,
  partyType: 'student', partyId: 'IQS-0042', partyName: 'Sinov Ota Onaevich', basis: 'O‘quv to‘lovi: 2027-01 + avans', attachment: '',
  fiscalNo: '000123456789', fiscalExempt: false, postedBy: 'u_kas', postedAt: '2027-01-04T05:10:00Z',
  lines: [
    { lineNo: 1, debit: '5010', credit: '4010', amount: 2000000, articleId: 'IN-01', cash: true, analytics: { studentId: 'IQS-0042', month: '2027-01' } },
    { lineNo: 2, debit: '6310', credit: '4010', amount: 150000, articleId: 'IN-01', cash: false, analytics: { studentId: 'IQS-0042', month: '2027-01', kind: 'credit_applied' } },
    { lineNo: 3, debit: '5010', credit: '6310', amount: 350000, articleId: 'IN-01', cash: true, analytics: { studentId: 'IQS-0042', kind: 'overpay' } },
  ],
};
const ko2 = {
  id: 'cd_0002', form: 'KO2', op: 'out_expense', status: 'posted', no: 7, year: 2027, businessDay: '2027-01-04', amount: 1234567.89,
  partyType: 'counterparty', partyId: 'cp_0123456789abcdef0123', partyName: 'Sinov Ta’minot MChJ', basis: 'Hisob-faktura № 15, 03.01.2027', attachment: 'hisob-faktura, 1 varaq',
  requestedBy: 'u_kas', approvedBy: 'u_mm', dirApprovedBy: 'u_dir', postedBy: 'u_kas', postedAt: '2027-01-04T07:00:00Z',
  lines: [
    { lineNo: 1, debit: '9420', credit: '5010', amount: 1000000, articleId: 'EX-32', cash: true, analytics: {} },
    { lineNo: 2, debit: '9430', credit: '5010', amount: 234567.89, articleId: 'EX-20', cash: true, analytics: {} },
  ],
};
// Kassa kuni: 26 kirim (5-si bekor qilingan), 9 chiqim, 1 tizim kamomadi (Ч-10) — jami 36 hujjat -> 30 qatorli 2 varaq.
function mkBook() {
  const mk = (i, form, amt, st) => ({ id: form + i, form, op: form === 'KO1' ? 'in_other' : 'out_expense', status: st || 'posted', no: i, businessDay: '2027-01-04', amount: amt,
    partyName: (form === 'KO1' ? 'Sinov To‘lovchi ' : 'Sinov Oluvchi ') + i, postedAt: '2027-01-04T0' + (form === 'KO1' ? 3 : 6) + ':' + String(i).padStart(2, '0') + ':00Z', postedBy: 'u_kas',
    lines: [{ debit: form === 'KO1' ? '5010' : '9420', credit: form === 'KO1' ? '9390' : '5010', amount: amt, cash: true }] });
  const docs = [];
  for (let i = 1; i <= 26; i++) docs.push(mk(i, 'KO1', 100000 * i, i === 5 ? 'void' : 'posted'));
  for (let i = 1; i <= 9; i++) docs.push(mk(i, 'KO2', 50000 * i));
  docs.push({ id: 'dx', form: 'KO2', op: 'out_shortage', status: 'posted', no: 10, businessDay: '2027-01-04', amount: 5000, isSystem: true, partyName: 'Kassa kamomadi', basis: 'Kassani sanash dalolatnomasi, 04.01.2027',
    postedAt: '2027-01-04T13:00:00Z', lines: [{ debit: '5910', credit: '5010', amount: 5000, cash: true }] });
  const rec = docs.filter(x => x.form === 'KO1' && x.status === 'posted').reduce((s, x) => s + x.amount, 0);   // 34 600 000
  const pay = docs.filter(x => x.form === 'KO2' && x.status === 'posted').reduce((s, x) => s + x.amount, 0);   // 2 255 000
  const day = { id: 'cd_main_2027-01-04', desk: 'main', day: '2027-01-04', status: 'closed', opening: 1500000, receipts: rec, payouts: pay, closing: 1500000 + rec - pay,
    counted: 1500000 + rec - pay, diff: -5000, diffDocId: 'dx', pendingCount: 0, pendingSum: 0, sheetFrom: 3, sheetTo: 4, sheetRows: 30, hash: 'ab12cd34ef567890aa',
    cashierUid: 'u_kas', closedBy: 'u_kas', verifiedBy: 'u_acc', reopenCount: 0 };
  const counts = [{ id: 'cc_1', kind: 'close', day: '2027-01-04', expected: day.closing + 5000, counted: day.closing, pendingSum: 0, diff: -5000, diffDocId: 'dx',
    denoms: { 100000: 338, 10000: 4, 5000: 1 }, commission: [{ title: 'Директор ўринбосари', name: 'Sinov A.A.' }, { title: 'Бухгалтер', name: 'Sinov B.B.' }], byUid: 'u_kas', at: '2027-01-04T13:00:00Z', note: '' }];
  return { day, docs, counts, rec, pay };
}

test('KO-1 + patta: o‘zbek kirill — barcha rekvizitlar', () => {
  const t = text(docHtml(ko1, ctx(), W));
  for (const must of ['«SINOV MAKTAB» МЧЖ', 'СТИР: 123456789 · Тошкент ш.', 'КИРИМ КАССА ОРДЕРИ № 12', '2027 йил 4 январь',
    'Дебет', 'Кредит', 'корреспонденцияловчи ҳисобварақ, субсчёт', 'аналитик ҳисоб коди', 'Сумма, сўм', 'Мақсадли йўналиш белгиси',
    '5010 4010 IQS-0042 · 01.2027 2 000 000=00 IN-01', '5010 6310 IQS-0042 350 000=00 IN-01',
    'Олинди: Sinov Ota Onaevich (ўқувчи: IQS-0042)', 'Асоси: Ўқув тўлови: 01.2027 + аванс',
    'Сумма: 2 350 000=00 — Икки миллион уч юз эллик минг сўм 00 тийин', 'Иловаси:', 'Фискал чек №: 000123456789',
    'Маълумот учун, нақд пулсиз ёзув: Дебет 6310 — Кредит 4010: 150 000=00',
    'Бош бухгалтер Синов Б.Б.', 'Қабул қилди: кассир Sinov Kassir', 'Тўловчи',
    'Ҳужжат: cd_0001 · чоп этилди: 04.01.2027 10:11, Sinov Kassir',
    'ПАТТА кирим касса ордерига № 12', 'М.Ў.', 'Фискал чек эмас']) assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.equal(count(t, 'Олинди:'), 2, 'order va pattada');
  assert.equal(count(t, 'НУСХА'), 0); assert.equal(count(t, 'СИНОВ'), 0); assert.equal(count(t, 'БЕКОР ҚИЛИНГАН'), 0);
  assert.ok(!t.includes('O‘quv to‘lovi'), 'tizim matni chop etish tilida qayta tuziladi');
});

test('KO-1: belgilar — «НУСХА», «СИНОВ», «БЕКОР ҚИЛИНГАН» order va pattada', () => {
  const v = Object.assign({}, ko1, { status: 'void', voidReason: 'Xato summa', voidedBy: 'u_dir', voidedAt: '2027-01-04T09:00:00Z' });
  const t = text(docHtml(v, ctx({ isTest: true, mark: { mode: 'copy' } }), W));
  assert.equal(count(t, 'НУСХА'), 2); assert.equal(count(t, 'СИНОВ'), 2);
  assert.ok(count(t, 'БЕКОР ҚИЛИНГАН') >= 4, 'belgi + suv belgisi, ikki qismda');
  assert.equal(count(t, 'Бекор қилинди: 04.01.2027 14:00, Sinov Direktor — сабаб: Xato summa'), 2);
  const r = text(docHtml(ko1, ctx({ mark: { mode: 'reissue' } }), W));   // asl nusxa qayta chiqarildi — «НУСХА» emas
  assert.equal(count(r, 'НУСХА'), 0);
});

test('KO-1: rus va lotin', () => {
  const r = text(docHtml(ko1, ctx({ lang: 'ru' }), W));
  for (const must of ['ООО «SINOV MAKTAB»', 'ИНН: 123456789', 'ПРИХОДНЫЙ КАССОВЫЙ ОРДЕР № 12', '4 января 2027 г.', 'Принято от: Sinov Ota Onaevich (учащийся: IQS-0042)',
    'Основание: Оплата за обучение: 01.2027 + аванс', 'Сумма: 2 350 000=00 — Два миллиона триста пятьдесят тысяч сумов 00 тийин', 'Приложение:', 'Фискальный чек №: 000123456789',
    'Код целевого назначения', 'Главный бухгалтер Синов Б.Б.', 'Получил кассир Sinov Kassir', 'Плательщик', 'КВИТАНЦИЯ к приходному кассовому ордеру № 12', 'М.П.', 'Не является фискальным чеком'])
    assert.ok(r.includes(must), 'yo‘q: ' + must + '\n' + r);
  const l = text(docHtml(ko1, ctx({ lang: 'uz-latn' }), W));
  for (const must of ['KIRIM KASSA ORDERI № 12', '2027-yil 4-yanvar', 'Olindi: Sinov Ota Onaevich (o‘quvchi: IQS-0042)', 'Asosi: O‘quv to‘lovi: 01.2027 + avans',
    'Ikki million uch yuz ellik ming so‘m 00 tiyin', 'PATTA kirim kassa orderiga № 12', 'Fiskal chek emas', 'Maqsadli yo‘nalish belgisi'])
    assert.ok(l.includes(must), 'yo‘q: ' + must + '\n' + l);
  // til tashkilot sozlamasidan (printLang) olinadi; noma'lum til — o'zbek kirill
  assert.ok(text(docHtml(ko1, ctx({ org: Object.assign({}, org, { printLang: 'ru' }) }), W)).includes('ПРИХОДНЫЙ КАССОВЫЙ ОРДЕР'));
  assert.ok(text(docHtml(ko1, ctx({ lang: 'xx' }), W)).includes('КИРИМ КАССА ОРДЕРИ'));
});

test('KO-1: fiskal cheksiz (istisno), kech yozilgan, taqsimoti noma’lum to‘lov', () => {
  const d = Object.assign({}, ko1, { fiscalNo: null, fiscalExempt: true, late: true, capturedAt: '2027-01-03T11:30:00Z',
    lines: [{ debit: '5010', credit: '4010', amount: 2350000, articleId: 'IN-01', cash: true, analytics: { studentId: 'IQS-0042', allocation: 'unknown' } }] });
  const t = text(docHtml(d, ctx(), W));
  assert.ok(t.includes('Фискал чек №: фискал чексиз — Директор рухсати билан'), t);
  assert.ok(t.includes('Пул қабул қилинган сана: 03.01.2027 16:30'), t);
  assert.ok(t.includes('Асоси: Ўқув тўлови Сумма:'), 'oy va avans yo‘q: ' + t);
});

test('KO-2: chiqim orderi — qatorlar, imzolar, qo‘lda to‘ldiriladigan qatorlar', () => {
  const t = text(docHtml(ko2, ctx(), W));
  for (const must of ['ЧИҚИМ КАССА ОРДЕРИ № 7', '2027 йил 4 январь', '9420 X 5010 1 000 000=00 EX-32', '9430 X 5010 234 567=89 EX-20',
    'Берилсин: Sinov Ta’minot MChJ', 'Асоси: Hisob-faktura № 15, 03.01.2027',
    'Сумма: 1 234 567=89 — Бир миллион икки юз ўттиз тўрт минг беш юз олтмиш етти сўм 89 тийин', 'Иловаси: hisob-faktura, 1 varaq',
    'Раҳбар Синов Д.Д.', 'Бош бухгалтер Sinov Moliya', 'Олдим:', '(сумма сўз билан)', 'Сана', 'Имзо',
    'Шахсни тасдиқловчи ҳужжат:', '(номи, серияси ва рақами, ким томонидан ва қачон берилган)', 'Берди: кассир Sinov Kassir', 'Ҳужжат: cd_0002'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(!t.includes('ПАТТА'), 'chiqim orderida patta yo‘q');
  const r = text(docHtml(ko2, ctx({ lang: 'ru' }), W));
  for (const must of ['РАСХОДНЫЙ КАССОВЫЙ ОРДЕР № 7', 'Выдать: Sinov Ta’minot MChJ', 'Получил:', 'По документу, удостоверяющему личность:', 'Выдал кассир Sinov Kassir'])
    assert.ok(r.includes(must), 'yo‘q: ' + must + '\n' + r);
  // tasdiqlovchi ko'rsatilmagan va ro'yxatda bir nechta shaxs bo'lsa — ism qo'yilmaydi (qo'lda imzolanadi)
  const two = signatories.concat([{ id: 's3', list: 2, uid: 'u_x', title: 'Молия менежери', fullName: 'Синов М.М.', active: true }]);
  const n = text(docHtml(Object.assign({}, ko2, { approvedBy: null }), ctx({ signatories: two }), W));
  assert.ok(n.includes('Бош бухгалтер Олдим:'), n);
});

test('Tizim hujjati (sanash farqi) va asos hujjatisiz xarid matni chop etish tilida', () => {
  const sh = { id: 'dx', form: 'KO2', op: 'out_shortage', status: 'posted', no: 10, businessDay: '2027-01-04', amount: 5000, isSystem: true, postedBy: 'u_kas',
    partyName: 'Kassa kamomadi', basis: 'Kassani sanash dalolatnomasi, 04.01.2027', lines: [{ debit: '5910', credit: '5010', amount: 5000, cash: true, articleId: 'OP-22' }] };
  const t = text(docHtml(sh, ctx(), W));
  assert.ok(t.includes('Берилсин: Касса камомади'), t); assert.ok(t.includes('Асоси: Кассани санаш далолатномаси, 04.01.2027'), t);
  assert.ok(t.includes('Берди: кассир Ҳужжат:'), 'tizim hujjatida kassir ismi qo‘yilmaydi: ' + t);
  assert.ok(text(docHtml(sh, ctx({ lang: 'ru' }), W)).includes('Выдать: Недостача кассы'));
  const su = Object.assign({}, sh, { form: 'KO1', op: 'in_surplus', lines: [{ debit: '5010', credit: '9390', amount: 5000, cash: true, articleId: 'IN-06' }] });
  assert.ok(text(docHtml(su, ctx(), W)).includes('Олинди: Касса ортиқчаси'));
  const nb = Object.assign({}, ko2, { basis: '', noBasis: true });
  assert.ok(text(docHtml(nb, ctx(), W)).includes('Асоси: асос ҳужжатисиз нақд харид'));
});

test('Xavfsizlik: foydalanuvchi matni HTML sifatida bajarilmaydi', () => {
  const h = docHtml(Object.assign({}, ko2, { partyName: '<script>alert(1)</script>', basis: '"><img src=x onerror=alert(1)>', attachment: "a'b&c" }), ctx(), W);
  assert.ok(!/<script>alert/.test(h) && !/<img src=x/.test(h), 'teglar ekranlanmagan');
  assert.ok(h.includes('&lt;script&gt;alert(1)&lt;/script&gt;') && h.includes('a&#39;b&amp;c'));
});

test('KO-4: varaqlar soni va raqami, 2 nusxa, qatorlar, jamlar', () => {
  const b = mkBook(), h = bookHtml(b, ctx(), W), t = text(h);
  const pages = h.split('<div class="bk">').slice(1);
  assert.equal(pages.length, 4, '2 varaq × 2 nusxa');
  const rows = pages.map(p => count(p.slice(p.indexOf('<tbody>'), p.indexOf('</tbody>')), '<tr>'));
  assert.deepEqual(rows, [31, 10, 31, 10], 'kun boshi + 30 hujjat | ko‘chirildi + 6 hujjat + 3 yakun qatori');
  assert.equal(count(t, 'КАССА ДАФТАРИ ВАРАҒИ'), 2); assert.equal(count(t, 'КАССИР ҲИСОБОТИ'), 2);
  assert.equal(count(t, 'КАССА 2027 йил 4 январь учун Варақ 3'), 2); assert.equal(count(t, 'КАССА 2027 йил 4 январь учун Варақ 4'), 2);
  for (const must of ['Ҳужжат рақами', 'Кимдан олинди ёки кимга берилди', 'Корреспонденцияловчи ҳисобварақ, субсчёт рақами', 'Кирим', 'Чиқим', '1 2 3 4 5',
    'Кун бошига қолдиқ X 1 500 000=00 X', 'К-1 Sinov To‘lovchi 1 9390 100 000=00', 'К-5 Sinov To‘lovchi 5 — бекор қилинган X X', 'Ч-1 Sinov Oluvchi 1 9420 50 000=00',
    'Ч-10 Касса камомади 5910 5 000=00', 'Олдинги варақдан кўчирилди X 34 600 000=00 500 000=00',
    'Кун бўйича жами X 34 600 000=00 2 255 000=00', 'Кун охирига қолдиқ X 33 845 000=00 X', 'шу жумладан иш ҳақи, ижтимоий тусдаги тўловлар ва стипендиялар учун X – X',
    'Санаб чиқилган нақд пул: 33 845 000=00 (Ўттиз уч миллион саккиз юз қирқ беш минг сўм 00 тийин)', 'Фарқ: Касса камомади 5 000=00 — Ч-10', 'Кассир Sinov Kassir',
    'Касса дафтаридаги ёзувларни текширдим ҳамда 26 (йигирма олти) та кирим ва 10 (ўн) та чиқим ҳужжатини олдим.', 'Бухгалтер Sinov Buxgalter',
    'Ҳужжат: cd_main_2027-01-04 · ab12cd34ef567890'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t.slice(0, 3000));
  assert.equal(count(t, 'ҚОРАЛАМА'), 0);
  // kun oxiri = kun boshi + kirim − chiqim (shakldagi sonlar bir-biriga mos)
  assert.equal(1500000 + b.rec - b.pay, 33845000);
});

test('KO-4: qayta chop etish aynan bir xil — varaqdagi qatorlar soni kun bilan muzlagan', () => {
  const b = mkBook();
  const a1 = bookHtml(b, ctx(), W), a2 = bookHtml(b, ctx({ org: Object.assign({}, org, { extra: { ko4Rows: 12 } }) }), W);
  assert.equal(a1, a2, 'sozlama keyin o‘zgarsa ham yopilgan kun varag‘i o‘zgarmaydi');
  assert.equal(bookRows(undefined), 30); assert.equal(bookRows('5'), 10); assert.equal(bookRows(100), 60); assert.equal(bookRows('abc'), 30);
  assert.equal(bookRows(45), 45); assert.equal(bookRows(0), 30); assert.equal(bookRows(-3), 30); assert.equal(bookRows('12'), 12);
});

test('KO-4: ochiq kun — qoralama (varaq raqamsiz, sanash qatorlarisiz); belgilar; rus prefikslari', () => {
  const b = mkBook();
  const open = { day: Object.assign({}, b.day, { status: 'open', receiptsLive: b.rec, payoutsLive: b.pay, balance: 1500000 + b.rec - b.pay, sheetFrom: null, sheetTo: null, sheetRows: null, counted: null, diff: null, verifiedBy: null }), docs: b.docs };
  const t = text(bookHtml(open, ctx({ mark: {} }), W));
  assert.equal(count(t, 'ҚОРАЛАМА'), 4, 'har varaqda'); assert.ok(t.includes('Варақ —')); assert.ok(!t.includes('Санаб чиқилган нақд пул'));
  assert.ok(t.includes('Кун охирига қолдиқ X 33 845 000=00 X'));
  const rp = text(bookHtml(b, ctx({ mark: { mode: 'copy', replaced: true }, isTest: true }), W));
  assert.equal(count(rp, 'НУСХА'), 4); assert.equal(count(rp, 'АЛМАШТИРИЛДИ'), 4); assert.equal(count(rp, 'СИНОВ'), 4);
  const r = text(bookHtml(b, ctx({ lang: 'ru' }), W));
  for (const must of ['ВКЛАДНОЙ ЛИСТ КАССОВОЙ КНИГИ', 'ОТЧЁТ КАССИРА', 'КАССА за 4 января 2027 г. Лист 3', 'П-1 Sinov To‘lovchi 1', 'Р-10 Недостача кассы', 'Остаток на начало дня', 'Итого за день', 'Остаток на конец дня',
    'Записи в кассовой книге проверил и документы в количестве 26 (двадцать шесть) приходных и 10 (десять) расходных получил.'])
    assert.ok(r.includes(must), 'yo‘q: ' + must);
  // 30 tadan kam hujjat — bitta varaq; hujjatsiz kun ham bitta varaq (faqat kun boshi va yakun)
  const one = bookHtml({ day: Object.assign({}, b.day, { sheetFrom: 9, sheetTo: 9 }), docs: b.docs.slice(0, 7) }, ctx(), W);
  assert.equal(count(one, '<div class="bk">'), 2);
  assert.equal(count(bookHtml({ day: b.day, docs: [] }, ctx(), W), '<div class="bk">'), 2);
});

test('Sanash dalolatnomasi: kun yopish (kamomad) va smena topshirish-qabul', () => {
  const b = mkBook(), t = text(countHtml(b.counts[0], b, ctx(), W));
  for (const must of ['КАССАДАГИ НАҚД ПУЛНИ САНАШ ДАЛОЛАТНОМАСИ', '2027 йил 4 январь — кунни ёпишда, 18:00', 'Комиссия: Директор ўринбосари — Sinov A.A.; Бухгалтер — Sinov B.B.',
    'Санаш пайтидаги охирги ҳужжат рақамлари: кирим ордери № 26, чиқим ордери № 9.', 'Ҳисобдаги қолдиқ 33 850 000=00', 'Санаб чиқилган нақд пул 33 845 000=00',
    'Ҳали ўтказилмаган ёзувлар суммаси –', 'Фарқ (санаб чиқилган − ҳисобдаги − ўтказилмаган) −5 000=00',
    'Санаб чиқилган нақд пул сўз билан: Ўттиз уч миллион саккиз юз қирқ беш минг сўм 00 тийин',
    'Номинал Сони Сумма, сўм 100 000=00 338 33 800 000=00 10 000=00 4 40 000=00 5 000=00 1 5 000=00 Жами 33 845 000=00',
    'Камомад — 5 000=00. Шу кун санаси билан чиқим касса ордери № 10 расмийлаштирилди.', 'Кассирнинг тушунтириши:', 'Раҳбар қарори:',
    'Директор ўринбосари Sinov A.A.', 'Бухгалтер Sinov B.B.', 'Кассир Sinov Kassir', 'Ҳужжат: cc_1'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  const ho = { id: 'cc_2', kind: 'handover', day: '2027-01-04', expected: 500000, counted: 500000, pendingSum: 0, diff: 0, fromUid: 'u_kas', toUid: 'u_kas2', byUid: 'u_kas', at: '2027-01-04T05:00:00Z', commission: [] };
  const h = text(countHtml(ho, b, ctx(), W));
  for (const must of ['сменани топшириш-қабул қилишда, 10:00', 'Фарқ аниқланмади.', 'Топширди Sinov Kassir', 'Қабул қилди Sinov Kassir 2'])
    assert.ok(h.includes(must), 'yo‘q: ' + must + '\n' + h);
  assert.ok(!h.includes('Раҳбар қарори'), 'farq yo‘q — qaror qatori yo‘q');
  // topshirish paytigacha (10:00) o'tkazilgan hujjatlar: kirim 26 ta (08:00–08:26), chiqim hali yo'q (11:00 dan keyin)
  assert.ok(h.includes('кирим ордери № 26, чиқим ордери йўқ.'), h);
  const ru = text(countHtml(b.counts[0], b, ctx({ lang: 'ru' }), W));
  for (const must of ['АКТ ПЕРЕСЧЁТА НАЛИЧНЫХ ДЕНЕГ В КАССЕ', 'при закрытии дня', 'Недостача — 5 000=00. Датой этого дня оформлен расходный кассовый ордер № 10.', 'Решение руководителя:'])
    assert.ok(ru.includes(must), 'yo‘q: ' + must);
});

test('KO-2: maosh va qaytarish orderi — tizim matnlari chop etish tilida', () => {
  const sal = { id: 'kd_s', form: 'KO2', op: 'out_salary', status: 'posted', no: 3, businessDay: '2027-01-04', amount: 1000000, partyType: 'employee', partyId: 'teachers:tch1',
    partyName: 'Sinov O‘qituvchi', basis: 'Ish haqi: 2026-12', sourceTable: 'salary_payments', sourceId: 'sp_x', sourceSnapshot: { month: '2026-12' }, postedBy: 'u_kas',
    lines: [{ debit: '6710', credit: '5010', amount: 1000000, cash: true, articleId: 'OP-09' }] };
  const t = text(docHtml(sal, ctx(), W));
  for (const must of ['ЧИҚИМ КАССА ОРДЕРИ № 3', '6710 teachers:tch1 5010 1 000 000=00 OP-09', 'Берилсин: Sinov O‘qituvchi', 'Асоси: Иш ҳақи: 12.2026', 'Бир миллион сўм 00 тийин'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(text(docHtml(sal, ctx({ lang: 'ru' }), W)).includes('Основание: Заработная плата: 12.2026'));
  // xodim qaytargan pul (acc-1): kassir yozgan asos + qaysi oy avansi / maoshi kamaygani
  const sr = { id: 'kd_sr', form: 'KO1', op: 'in_staff_return', status: 'posted', no: 5, businessDay: '2027-01-04', amount: 100000, partyType: 'employee', partyId: 'teachers:tch1',
    partyName: 'Sinov O‘qituvchi', basis: 'Ariza 04.01.2027', sourceSnapshot: { month: '2026-12' }, postedBy: 'u_kas',
    lines: [{ debit: '5010', credit: '4210', amount: 100000, cash: true, articleId: 'OP-08' }] };
  assert.ok(text(docHtml(sr, ctx(), W)).includes('Асоси: Ariza 04.01.2027; аванс / иш ҳақи ойи: 12.2026'), text(docHtml(sr, ctx(), W)));
  assert.ok(text(docHtml(sr, ctx({ lang: 'ru' }), W)).includes('Основание: Ariza 04.01.2027; месяц аванса / зарплаты: 12.2026'));
  assert.ok(text(docHtml(Object.assign({}, sr, { basis: '' }), ctx({ lang: 'uz-latn' }), W)).includes('Asosi: avans / ish haqi oyi: 12.2026'));
  const rf = { id: 'kd_r', form: 'KO2', op: 'out_refund', status: 'posted', no: 4, businessDay: '2027-01-04', amount: 450000, partyType: 'student', partyId: 'T-1', partyName: 'Sinov Ota Onaevich',
    basis: 'Qaytarish: O‘quvchi ketdi; ariza 03.01.2027', attachment: 'Yozma ariza', sourceTable: 'refunds', dirApprovedBy: 'u_dir', postedBy: 'u_kas',
    lines: [{ debit: '4010', credit: '5010', amount: 300000, cash: true, articleId: 'OP-15', analytics: { studentId: 'T-1', month: '2026-12' } },
            { debit: '6310', credit: '5010', amount: 150000, cash: true, articleId: 'OP-15', analytics: { studentId: 'T-1', kind: 'credit_refund' } }] };
  const r = text(docHtml(rf, ctx(), W));
  for (const must of ['4010 T-1 · 12.2026 5010 300 000=00 OP-15', '6310 T-1 5010 150 000=00 OP-15', 'Берилсин: Sinov Ota Onaevich (ўқувчи: T-1)',
    'Асоси: Қайтариш: O‘quvchi ketdi; ариза 03.01.2027', 'Иловаси: Ёзма ариза', 'Раҳбар Синов Д.Д.'])
    assert.ok(r.includes(must), 'yo‘q: ' + must + '\n' + r);
  const rr = text(docHtml(rf, ctx({ lang: 'ru' }), W));
  for (const must of ['Выдать: Sinov Ota Onaevich (учащийся: T-1)', 'Основание: Возврат: O‘quvchi ketdi; заявление 03.01.2027', 'Приложение: Письменное заявление'])
    assert.ok(rr.includes(must), 'yo‘q: ' + must + '\n' + rr);
});

// ---------------------------------------------------------------- RP-02: kassirning kunlik hisoboti
// Kichik kun: 3 kirim (2 o'quv to'lovi — bitta o'quvchi, 1 bankdan), 3 chiqim (xarajat 2 statiya, bankka, bekor qilingan), yopilgan, farq yo'q.
function mkDay(over) {
  const L = (debit, credit, amount, articleId, extra) => Object.assign({ debit, credit, amount, articleId, cash: true, analytics: {} }, extra || {});
  const docs = [
    { id: 'a1', form: 'KO1', op: 'in_tuition', status: 'posted', no: 1, businessDay: '2027-01-04', amount: 600000, partyType: 'student', partyId: 'IQS-0042', partyName: 'Sinov Ota',
      postedAt: '2027-01-04T04:05:00Z', postedBy: 'u_kas', lines: [L('5010', '4010', 600000, 'IN-01', { analytics: { studentId: 'IQS-0042', month: '2027-01' } })] },
    { id: 'a2', form: 'KO1', op: 'in_tuition', status: 'posted', no: 2, businessDay: '2027-01-04', amount: 400000, partyType: 'student', partyId: 'IQS-0042', partyName: 'Sinov Ona',
      postedAt: '2027-01-04T04:20:00Z', postedBy: 'u_kas', lines: [L('5010', '4010', 400000, 'IN-01', { analytics: { studentId: 'IQS-0042', month: '2027-01' } })] },
    { id: 'a3', form: 'KO1', op: 'in_bank', status: 'posted', no: 3, businessDay: '2027-01-04', amount: 1000000, partyType: 'bank', partyId: 'cp_bank', partyName: 'Sinov Bank', basis: 'Chek № 12',
      postedAt: '2027-01-04T05:00:00Z', postedBy: 'u_kas', lines: [L('5010', '5110', 1000000, 'OP-01')] },
    { id: 'b1', form: 'KO2', op: 'out_expense', status: 'posted', no: 1, businessDay: '2027-01-04', amount: 300000, partyType: 'counterparty', partyId: 'cp_sup', partyName: 'Sinov Ta’minot MChJ', basis: 'Hisob-faktura № 5',
      postedAt: '2027-01-04T06:00:00Z', postedBy: 'u_kas', lines: [L('9420', '5010', 200000, 'EX-32'), L('2010', '5010', 100000, 'EX-07')] },
    { id: 'b2', form: 'KO2', op: 'out_bank', status: 'posted', no: 2, businessDay: '2027-01-04', amount: 1500000, partyType: 'bank', partyId: 'cp_bank', partyName: 'Sinov Bank', basis: 'Inkassatsiya',
      postedAt: '2027-01-04T07:00:00Z', postedBy: 'u_kas', lines: [L('5710', '5010', 1500000, 'OP-02')] },
    { id: 'b3', form: 'KO2', op: 'out_expense', status: 'void', no: 3, businessDay: '2027-01-04', amount: 50000, partyType: 'other', partyName: 'Bozor <sotuvchisi>', noBasis: true, voidReason: 'Xato kiritilgan',
      postedAt: '2027-01-04T07:30:00Z', postedBy: 'u_kas', lines: [L('2010', '5010', 50000, 'EX-07')] },
  ];
  const day = { id: 'cd_main_2027-01-04', desk: 'main', day: '2027-01-04', status: 'closed', opening: 2000000, receipts: 2000000, payouts: 1800000, closing: 2200000, counted: 2200000,
    diff: 0, pendingCount: 0, pendingSum: 0, sheetFrom: 1, sheetTo: 1, sheetRows: 30, hash: 'ab12cd34ef567890aa', cashierUid: 'u_kas', closedBy: 'u_kas', verifiedBy: 'u_mm', reopenCount: 0 };
  return Object.assign({ day, docs, counts: [], events: [],
    byParty: [
      { form: 'KO1', partyType: 'bank', partyId: 'cp_bank', name: 'Sinov Bank', ops: ['in_bank'], count: 1, amount: 1000000 },
      { form: 'KO1', partyType: 'student', partyId: 'IQS-0042', name: 'Sinov O‘quvchi', ops: ['in_tuition'], count: 2, amount: 1000000 },
      { form: 'KO2', partyType: 'bank', partyId: 'cp_bank', name: 'Sinov Bank', ops: ['out_bank'], count: 1, amount: 1500000 },
      { form: 'KO2', partyType: 'counterparty', partyId: 'cp_sup', name: 'Sinov Ta’minot MChJ', ops: ['out_expense'], count: 1, amount: 300000 }],
    byArticle: [
      { form: 'KO1', articleId: 'IN-01', kind: 'IN', nameUz: 'Ta’lim xizmati (oylik to‘lov)', nameRu: 'Образовательные услуги', debit: '5010', credit: '4010', amount: 1000000, transfer: false },
      { form: 'KO1', articleId: 'OP-01', kind: 'OP', nameUz: 'Bankdan naqd olish', nameRu: 'Получение наличных из банка', debit: '5010', credit: '5110', amount: 1000000, transfer: true },
      { form: 'KO2', articleId: 'EX-07', kind: 'EX', nameUz: 'Oziq-ovqat', nameRu: 'Продукты питания', debit: '2010', credit: '5010', amount: 100000, transfer: false },
      { form: 'KO2', articleId: 'EX-32', kind: 'EX', nameUz: 'Kanselyariya', nameRu: 'Канцтовары', debit: '9420', credit: '5010', amount: 200000, transfer: false },
      { form: 'KO2', articleId: 'OP-02', kind: 'OP', nameUz: 'Bankka topshirish', nameRu: 'Сдача в банк', debit: '5710', credit: '5010', amount: 1500000, transfer: true }],
    transfers: { inCount: 1, inAmount: 1000000, outCount: 1, outAmount: 1500000 },
    channels: [{ provider: 'cash', count: 2, amount: 1000000 }, { provider: 'click', count: 1, amount: 300000 }],
    pending: { waiting: 1, waitingSum: 70000, toPay: 2, toPaySum: 150000 },
    limit: { cashLimit: 3000000, set: true, exceeded: false } }, over || {});
}
const rules = [{ op: 'in_tuition', nameUz: 'O‘quv haqi (naqd)', nameRu: 'Оплата за обучение (наличные)' }, { op: 'in_bank', nameUz: 'Bankdan naqd', nameRu: 'Наличные из банка' },
  { op: 'out_expense', nameUz: 'Xarajat', nameRu: 'Расход' }, { op: 'out_bank', nameUz: 'Bankka topshirish', nameRu: 'Сдача в банк' }];

test('RP-02 kunlik hisobot: o‘zbek lotin (chop etish tili kirill bo‘lsa ham) — barcha bo‘limlar', () => {
  const t = text(reportHtml(mkDay(), ctx({ rules }), W));
  for (const must of ['«SINOV MAKTAB» МЧЖ', 'KASSIRNING KUNLIK HISOBOTI', '2027-yil 4-yanvar · kun yopilgan',
    '1. Kun yakuni', 'Kun boshiga qoldiq 2 000 000=00', 'Kirim (3 ta order) 2 000 000=00', 'Chiqim (2 ta order) 1 800 000=00', 'Kun oxiriga qoldiq 2 200 000=00',
    'Sanab chiqilgan naqd pul 2 200 000=00', 'Farq yo‘q', 'Bekor qilingan hujjatlar 1 ta',
    '2. Kirim orderlari', 'K-1 09:05 Sinov Ota (o‘quvchi: IQS-0042) O‘quv haqi (naqd) — O‘quv to‘lovi: 01.2027 IN-01 600 000=00',
    'K-3 10:00 Sinov Bank Bankdan naqd — Chek № 12 OP-01 1 000 000=00', 'Jami 2 000 000=00',
    '3. Chiqim orderlari', 'Ch-1 11:00 Sinov Ta’minot MChJ Xarajat — Hisob-faktura № 5 EX-32, EX-07 300 000=00',
    'Ch-3 12:30 Bozor <sotuvchisi> Xarajat — asos hujjatisiz naqd xarid (bekor qilingan: Xato kiritilgan) EX-07 50 000=00', 'Jami 1 800 000=00',
    '4. Kimdan qancha (kirim — tomon bo‘yicha)', 'Sinov O‘quvchi (IQS-0042) o‘quvchi 2 1 000 000=00', 'Sinov Bank bank 1 1 000 000=00', 'Jami 3 2 000 000=00',
    '5. Kimga qancha (chiqim — tomon bo‘yicha)', 'Sinov Ta’minot MChJ kontragent 1 300 000=00', 'Jami 2 1 800 000=00',
    '6. Statiya bo‘yicha', 'IN-01 Ta’lim xizmati (oylik to‘lov) 4010 1 000 000=00', 'OP-01 Bankdan naqd olish (ichki o‘tkazma) 5110 1 000 000=00',
    'EX-32 Kanselyariya 9420 200 000=00', 'OP-02 Bankka topshirish (ichki o‘tkazma) 5710 1 500 000=00', 'Jami 2 000 000=00 1 800 000=00',
    '7. Ichki o‘tkazmalar (daromad ham, xarajat ham emas)', 'Bankdan naqd olindi (1 ta) 1 000 000=00', 'Bankka topshirildi (1 ta) 1 500 000=00',
    '8. Tushumlar kanallar bo‘yicha', 'naqd 2 1 000 000=00', 'Click 1 300 000=00', 'Jami 3 1 300 000=00',
    'Naqd o‘quv to‘lovi: to‘lovlar jadvalida 1 000 000=00 — kassa kirim orderlarida 1 000 000=00: mos.',
    '9. Kutilayotganlar (hisobot olingan paytda)', 'Tasdiq kutayotgan so‘rovlar (1 ta) 70 000=00', 'Tasdiqlangan, pul hali berilmagan / qabul qilinmagan (2 ta) 150 000=00',
    '10. Kassa limiti', 'Kassa limiti: 3 000 000=00 — kun oxiridagi qoldiq limitdan oshmagan.',
    'Kassir Sinov Kassir', 'Tekshirdi Sinov Moliya', 'Kun: cd_main_2027-01-04 · ab12cd34ef567890 · chop etildi: 04.01.2027 10:11, Sinov Kassir'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(!t.includes('QORALAMA') && !t.includes('SINOV ·') && !/\bSINOV\b(?! MAKTAB)/.test(t), 'belgisiz');
  assert.ok(!/[А-Яа-яЎўҚқҒғҲҳ]/.test(t.replace('«SINOV MAKTAB» МЧЖ', '').replace('Тошкент ш.', '')), 'hisobot matni lotinda (tashkilot rekvizitidan tashqari)');
});

test('RP-02 = KO-4: kunlik hisobot jamlari kassa kitobi varag‘idagi jamlar bilan bir xil', () => {
  const b = mkBook();   // 26 kirim (1 tasi bekor), 10 chiqim — KO-4 testidagi kun
  const k4 = text(bookHtml(b, ctx(), W)), rp = text(reportHtml(b, ctx({ rules }), W));
  const rec = W.fmtMoney(b.rec), pay = W.fmtMoney(b.pay), end = W.fmtMoney(1500000 + b.rec - b.pay);
  assert.ok(k4.includes(`Кун бўйича жами X ${rec} ${pay}`) && k4.includes(`Кун охирига қолдиқ X ${end} X`), k4);
  assert.ok(rp.includes(`Kirim (25 ta order) ${rec}`) && rp.includes(`Chiqim (10 ta order) ${pay}`) && rp.includes(`Kun oxiriga qoldiq ${end}`), rp);
  assert.ok(rp.includes(`Jami ${rec}`) && rp.includes(`Jami ${pay}`), 'orderlar ro‘yxati jami = kun jami');
  assert.ok(rp.includes('Farq kamomad 5 000=00 — Ch-10'), rp);
  assert.ok(rp.includes('Kassa kamomadi') && rp.includes('Kassani sanash dalolatnomasi, 04.01.2027'), 'tizim hujjati matni');
  // bo'sh bloklar (tomon, statiya, o'tkazma, kanal, kutilayotgan) tushib qoladi — raqamlar ketma-ket: 1, 2, 3, 4 (limit)
  assert.ok(rp.includes('1. Kun yakuni') && rp.includes('2. Kirim orderlari') && rp.includes('3. Chiqim orderlari') && rp.includes('4. Kassa limiti') && !rp.includes('5. '), rp);
  assert.ok(rp.includes('Kassa limiti belgilanmagan.'), rp);
});

test('RP-02: ochiq kun — «QORALAMA», sanash yo‘q; sinov kassasi — «SINOV», kanallar yo‘q; limitdan oshgan; moslik buzilgan', () => {
  const open = mkDay(); Object.assign(open.day, { status: 'open', receipts: null, payouts: null, closing: null, counted: null, diff: null, receiptsLive: 2000000, payoutsLive: 1800000, balance: 2200000, hash: null, verifiedBy: null });
  let t = text(reportHtml(open, ctx({ rules }), W));
  assert.ok(t.includes('QORALAMA') && t.includes('kun ochiq') && t.includes('Kun hali yopilmagan — pul sanalmagan.') && !t.includes('Sanab chiqilgan'), t);
  assert.ok(t.includes('Kirim (3 ta order) 2 000 000=00') && t.includes('Kun oxiriga qoldiq 2 200 000=00') && t.includes('Tekshirdi') && !t.includes('Tekshirdi Sinov'), t);
  t = text(reportHtml(mkDay({ channels: [] }), ctx({ rules, isTest: true }), W));
  assert.ok(t.includes('SINOV') && !t.includes('Tushumlar kanallar bo‘yicha') && t.includes('8. Kutilayotganlar') && t.includes('9. Kassa limiti'), t);
  t = text(reportHtml(mkDay({ limit: { cashLimit: 2000000, set: true, exceeded: true }, channels: [{ provider: 'cash', count: 1, amount: 600000 }], pending: { waiting: 0, toPay: 0 } }), ctx({ rules }), W));
  assert.ok(t.includes('Kassa limiti: 2 000 000=00 — KUN OXIRIDAGI QOLDIQ LIMITDAN OSHGAN — ortiqchasi bankka topshiriladi.'), t);
  assert.ok(t.includes('to‘lovlar jadvalida 600 000=00 — kassa kirim orderlarida 1 000 000=00: FARQ BOR — tekshiring.'), t);
  assert.ok(!t.includes('Kutilayotganlar') && t.includes('9. Kassa limiti'), t);
});

test('RP-02: rus tilida; HTML xavfsizligi', () => {
  const h = reportHtml(mkDay(), ctx({ rules, lang: 'ru' }), W), t = text(h);
  for (const must of ['ООО «SINOV MAKTAB»', 'ЕЖЕДНЕВНЫЙ ОТЧЁТ КАССИРА', '4 января 2027 г. · день закрыт', 'Остаток на начало дня 2 000 000=00', 'Приход (ордеров: 3) 2 000 000=00',
    'Остаток на конец дня 2 200 000=00', 'Расхождение нет', 'П-1 09:05 Sinov Ota (учащийся: IQS-0042) Оплата за обучение (наличные) — Оплата за обучение: 01.2027 IN-01 600 000=00',
    'Р-2 12:00 Sinov Bank Сдача в банк — Inkassatsiya OP-02 1 500 000=00', 'От кого сколько (приход — по контрагентам)', 'Sinov O‘quvchi (IQS-0042) учащийся 2 1 000 000=00',
    'OP-01 Получение наличных из банка (внутреннее перемещение) 5110 1 000 000=00', 'Получено наличных из банка (1 шт.) 1 000 000=00', 'наличные 2 1 000 000=00',
    'Наличная оплата за обучение: в таблице платежей 1 000 000=00 — в приходных ордерах 1 000 000=00: совпадает.',
    'Лимит кассы: 3 000 000=00 — остаток на конец дня не превышает лимит.', 'Кассир Sinov Kassir', 'Проверил Sinov Moliya'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(h.includes('Bozor &lt;sotuvchisi&gt;') && !h.includes('<sotuvchisi>'), 'foydalanuvchi matni ekranlanadi');
  assert.ok(/^<!DOCTYPE html><html lang="ru">/.test(h) && h.includes('@page{size:A4 portrait;margin:12mm 10mm 12mm 18mm}'), 'o‘z sahifa chegaralari');
});

// ---------------------------------------------------------------- o'zaro hisob dalolatnomasi (nc_offset, naqdsiz)
const ofsDoc = {
  id: 'kd_ofs1', form: 'ACT', op: 'nc_offset', status: 'posted', no: 3, year: 2027, businessDay: '2027-01-04', amount: 1300000,
  partyType: 'employee', partyId: 'teachers:tch1', partyName: 'Sinov O‘qituvchi', attachment: 'Yozma ariza', note: '',
  basis: 'O‘zaro hisob: ish haqi 2026-12 hisobidan o‘quv to‘lovi — Sinov B (T-2); ariza 03.01.2027',
  dirApprovedBy: 'u_dir', postedBy: 'u_dir', postedAt: '2027-01-04T06:00:00Z',
  sourceSnapshot: { month: '2026-12', studentId: 'T-2', studentName: 'Sinov B', requestDate: '2027-01-03', paymentId: 'ofs_x', allocation: 'exact' },
  lines: [
    { lineNo: 1, debit: '6710', credit: '4010', amount: 1000000, articleId: 'IN-01', cash: false, analytics: { studentId: 'T-2', month: '2027-01' } },
    { lineNo: 2, debit: '6710', credit: '6310', amount: 300000, articleId: 'IN-01', cash: false, analytics: { studentId: 'T-2', month: '2027-03' } },
  ],
};
test('o‘zaro hisob dalolatnomasi: o‘zbek kirill — matn, qatorlar, xodim, o‘quvchi, asos, imzolar', () => {
  const t = text(docHtml(ofsDoc, ctx(), W));
  for (const must of ['ЎЗАРО ҲИСОБ ДАЛОЛАТНОМАСИ № ЎҲ-3', '2027 йил 4 январь',
    'Ходимнинг ёзма аризасига асосан унинг 12.2026 ойи учун иш ҳақидан 1 300 000=00 сўм фарзандининг ўқув тўлови ҳисобига ўтказилди. Нақд пул берилмади ва қабул қилинмади.',
    '6710 4010 T-2 · 01.2027 1 000 000=00 IN-01', '6710 6310 T-2 · 03.2027 300 000=00 IN-01',
    'Ходим: Sinov O‘qituvchi', 'Ўқувчи: Sinov B (T-2)', 'Асоси: Ўзаро ҳисоб: 12.2026 ойи иш ҳақи ҳисобидан ўқув тўлови — Sinov B (T-2); ариза 03.01.2027',
    'Сумма: 1 300 000=00 — Бир миллион уч юз минг сўм 00 тийин', 'Иловаси: Ёзма ариза',
    'Раҳбар Синов Д.Д.', 'Бош бухгалтер Синов Б.Б.', 'Танишдим, розиман: ходим Sinov O‘qituvchi', 'Ҳужжат: kd_ofs1'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(!t.includes('Берилсин') && !t.includes('O‘zaro hisob'), 'chiqim orderi yorlig‘i yo‘q; tizim matni chop etish tilida');
  const v = text(docHtml(Object.assign({}, ofsDoc, { status: 'void', voidedBy: 'u_dir', voidedAt: '2027-01-04T09:00:00Z', voidReason: 'Xato o‘quvchi tanlangan' }), ctx(), W));
  assert.ok(v.includes('БЕКОР ҚИЛИНГАН') && v.includes('Бекор қилинди: 04.01.2027 14:00, Sinov Direktor — сабаб: Xato o‘quvchi tanlangan'), v);
});
test('o‘zaro hisob dalolatnomasi: rus va lotin; boshqa dalolatnomalarda «tomon» qatori yo‘q', () => {
  const r = text(docHtml(ofsDoc, ctx({ lang: 'ru' }), W));
  for (const must of ['АКТ ВЗАИМОЗАЧЁТА № ВЗ-3', '4 января 2027 г.', 'На основании письменного заявления сотрудника из его заработной платы за 12.2026 сумма 1 300 000=00 сум зачтена в счёт оплаты за обучение ребёнка.',
    'Сотрудник: Sinov O‘qituvchi', 'Учащийся: Sinov B (T-2)', 'Основание: Взаимозачёт: оплата за обучение в счёт заработной платы за 12.2026 — Sinov B (T-2); заявление от 03.01.2027',
    'Приложение: Письменное заявление', 'Ознакомлен, согласен: сотрудник Sinov O‘qituvchi'])
    assert.ok(r.includes(must), 'yo‘q: ' + must + '\n' + r);
  const l = text(docHtml(ofsDoc, ctx({ lang: 'uz-latn' }), W));
  assert.ok(l.includes('O‘ZARO HISOB DALOLATNOMASI № O‘H-3') && l.includes('Xodim: Sinov O‘qituvchi') && l.includes('O‘quvchi: Sinov B (T-2)') && l.includes('Tanishdim, roziman: xodim Sinov O‘qituvchi'), l);
  const op = text(docHtml({ id: 'kd_op', form: 'ACT', op: 'nc_opening', status: 'posted', no: 1, businessDay: '2027-01-04', amount: 2000000, partyName: 'Boshlang‘ich qoldiq',
    basis: 'Kassani sanash dalolatnomasi (boshlang‘ich qoldiq)', lines: [{ debit: '5010', credit: '0000', amount: 2000000, articleId: 'OP-23', cash: true }] }, ctx(), W));
  assert.ok(op.includes('ДАЛОЛАТНОМА № Д-1') && op.includes('Кассанинг бошланғич қолдиғи — 2027 йил 4 январь') && !op.includes('Берилсин') && !op.includes('Ходим:') && !op.includes('Танишдим'), op);
  const dec = text(docHtml({ id: 'kd_dec', form: 'ACT', op: 'nc_shortage_dec', status: 'posted', no: 2, businessDay: '2027-01-05', amount: 5000, partyType: 'employee', partyId: 'staff:st1', partyName: 'Sinov Kassir',
    basis: 'Buyruq № 3', decidedBy: 'u_dir', lines: [{ debit: '4730', credit: '5910', amount: 5000, articleId: 'OP-22', cash: false }] }, ctx(), W));
  assert.ok(dec.includes('Камомад бўйича қарор') && dec.includes('Жавобгар шахс: Sinov Kassir') && !dec.includes('Берилсин'), dec);
});

// ---------------------------------------------------------------- avans hisoboti (nc_adv_report, naqdsiz)
const advDoc = {
  id: 'kd_adv1', form: 'ACT', op: 'nc_adv_report', status: 'posted', no: 5, year: 2027, businessDay: '2027-01-11', amount: 200000,
  partyType: 'employee', partyId: 'staff:st1', partyName: 'Sinov Zavxoz', attachment: 'Cheklar va hujjatlar: 2 ta', note: '',
  basis: 'Avans hisoboti 10.01.2027; Oziq-ovqat xaridi', postedBy: 'u_acc', postedAt: '2027-01-11T06:00:00Z',
  sourceSnapshot: { reportDate: '2027-01-10', openBefore: 250000, openAfter: 50000 },
  lines: [
    { lineNo: 1, debit: '1010', credit: '4230', amount: 150000, articleId: 'EX-20', cash: false, note: 'Chek 15, 09.01', analytics: { partyId: 'staff:st1' } },
    { lineNo: 2, debit: '2010', credit: '4230', amount: 50000, articleId: 'EX-16', cash: false, note: 'Chek 16, 09.01', analytics: { partyId: 'staff:st1' } },
  ],
};
test('avans hisoboti: o‘zbek kirill va rus — qatorlar (chek), hisobdor, asos, qoldiq, imzolar', () => {
  const t = text(docHtml(advDoc, ctx(), W));
  for (const must of ['АВАНС ҲИСОБОТИ № А-5', '2027 йил 11 январь', 'Чек, ҳужжат',
    '1010 4230 Chek 15, 09.01 150 000=00 EX-20', '2010 4230 Chek 16, 09.01 50 000=00 EX-16',
    'Ҳисобдор шахс: Sinov Zavxoz', 'Асоси: Аванс ҳисоботи 10.01.2027; Oziq-ovqat xaridi',
    'Сумма: 200 000=00 — Икки юз минг сўм 00 тийин', 'Иловаси: Чеклар ва ҳужжатлар: 2 та',
    'Ҳисобдордаги аванс қолдиғи: ҳисоботдан олдин 250 000=00 сўм, кейин 50 000=00 сўм.',
    'Раҳбар', 'Бош бухгалтер', 'Ҳисобдор шахс Sinov Zavxoz', 'Ҳужжат: kd_adv1'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(!t.includes('Avans hisoboti') && !t.includes('Берилсин'), 'tizim matni chop etish tilida; chiqim orderi yorlig‘i yo‘q');
  const r = text(docHtml(advDoc, ctx({ lang: 'ru' }), W));
  for (const must of ['АВАНСОВЫЙ ОТЧЁТ № АО-5', '11 января 2027 г.', 'Подотчётное лицо: Sinov Zavxoz', 'Основание: Авансовый отчёт 10.01.2027; Oziq-ovqat xaridi',
    'Приложение: Чеки и документы: 2 шт.', 'Остаток аванса у подотчётного лица: до отчёта 250 000=00 сум, после 50 000=00 сум.'])
    assert.ok(r.includes(must), 'yo‘q: ' + must + '\n' + r);
});

test('RP-02: onlayn kassa Z-hisoboti — solishtirish, «yo‘q», kiritilmagan, ochiq kun, sinov kassasi', () => {
  const zb = { applies: true, needed: true, recorded: true, missing: false, no: 'Z-0104', cash: 990000, card: 150000, expCash: 1000000, nCash: 2, expCard: 150000, nCard: 1, ok: false, diffCash: -10000, diffCard: 0 };
  const withZ = z => { const b = mkDay(); b.day.z = z; return b; };
  let t = text(reportHtml(withZ(zb), ctx({ rules }), W));
  for (const must of ['8. Tushumlar kanallar bo‘yicha', '9. Onlayn kassa (NKM) Z-hisoboti', 'Z-hisobot № Z-0104', 'Z-hisobotda Tizimda Farq',
    'Naqd 990 000=00 1 000 000=00 (2 chek) −10 000=00', 'Bank kartasi 150 000=00 150 000=00 (1 ta) mos',
    'Tizimda: naqd — fiskal chekli kirim orderlari, karta — terminal to‘lovlari.', '10. Kutilayotganlar', '11. Kassa limiti'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  t = text(reportHtml(withZ(Object.assign({}, zb, { missing: true, reason: 'Apparat <buzilgan>', no: null, cash: null, card: null, diffCash: null, diffCard: null })), ctx({ rules }), W));
  assert.ok(t.includes('Z-hisobot yo‘q: Apparat <buzilgan>.') && t.includes('Tizimda: Naqd 1 000 000=00 (2 chek), Bank kartasi 150 000=00 (1 ta).'), t);
  t = text(reportHtml(withZ(Object.assign({}, zb, { recorded: false, no: null, cash: null, card: null, diffCash: null, diffCard: null })), ctx({ rules }), W));
  assert.ok(t.includes('Z-hisobot kiritilmagan.'), t);
  t = text(reportHtml(withZ({ applies: true, needed: false, recorded: false, ok: true, expCash: 0, expCard: 0 }), ctx({ rules }), W));
  assert.ok(!t.includes('Z-hisobot'), 'kerak bo‘lmagan va kiritilmagan — bo‘lim yo‘q');
  const open = withZ({ applies: true, needed: true, recorded: true, missing: false, no: 'Z-1', cash: 500000, card: 0 });
  Object.assign(open.day, { status: 'open', receipts: null, payouts: null, closing: null, counted: null, diff: null, receiptsLive: 2000000, payoutsLive: 1800000, balance: 2200000, hash: null, verifiedBy: null });
  t = text(reportHtml(open, ctx({ rules }), W));
  assert.ok(t.includes('Z-hisobot № Z-1: Naqd 500 000=00, Bank kartasi – (kun yopilgach solishtiriladi).') && !t.includes('Tizimda'), t);
  t = text(reportHtml(withZ(zb), ctx({ rules, isTest: true }), W));
  assert.ok(!t.includes('Z-hisobot'), 'sinov kassasida Z bo‘limi yo‘q');
  const h = reportHtml(withZ(zb), ctx({ rules, lang: 'ru' }), W), tr = text(h);
  assert.ok(tr.includes('Z-отчёт онлайн-ККМ') && tr.includes('Наличные 990 000=00 1 000 000=00 (чеков: 2) −10 000=00') && tr.includes('Банковские карты 150 000=00 150 000=00 (операций: 1) совпадает'), tr);
  assert.ok(!reportHtml(withZ(Object.assign({}, zb, { missing: true, reason: '<script>x</script>' })), ctx({ rules }), W).includes('<script>x'), 'sabab ekranlanadi');
});

// ---------------------------------------------------------------- KO-3: kassa orderlari jurnali (F1.22)
const mkJournal = over => Object.assign({ ok: true, from: '2027-01-01', to: '2027-01-31', desk: { id: 'main', name: 'Asosiy kassa', isTest: false },
  opening: 1000000, closing: 2115432.11, balanced: true,
  totals: { in: 2350000, nIn: 1, out: 1234567.89, nOut: 1, voids: 1, firstKo1: 12, lastKo1: 13, firstKo2: 7, lastKo2: 7 },
  docs: [ko1, Object.assign({}, ko1, { id: 'cd_0003', no: 13, status: 'void', voidReason: 'Xato <summa>', partyName: 'Sinov Bobo', amount: 50000 }), ko2] }, over || {});
const rulesJ = [{ op: 'in_tuition', nameUz: 'O‘quv haqi (naqd)', nameRu: 'Оплата за обучение (наличные)' }, { op: 'out_expense', nameUz: 'Xarajat', nameRu: 'Расход' }];

test('KO-3 jurnal: kirill (standart) — ikki tomonlama jadval, bekor qilingan chizilgan, jamlar va qoldiqlar', () => {
  const h = journalHtml(mkJournal(), ctx(), W), t = text(h);
  for (const must of ['«SINOV MAKTAB» МЧЖ', 'КО-3 шакли', 'КИРИМ ВА ЧИҚИМ КАССА ҲУЖЖАТЛАРИНИ РЎЙХАТГА ОЛИШ ЖУРНАЛИ', '01.01.2027 – 31.01.2027 · Asosiy kassa',
    'Кирим касса ҳужжатлари', 'Чиқим касса ҳужжатлари', 'Сана Рақами Сумма Изоҳ Сана Рақами Сумма Изоҳ',
    '04.01.2027 12 2 350 000=00', '04.01.2027 7 1 234 567=89 Sinov Ta’minot MChJ', '04.01.2027 13 50 000=00 бекор қилинган: Xato <summa>',
    'Жами (бекор қилинганларсиз) 2 350 000=00 Жами (бекор қилинганларсиз) 1 234 567=89',
    'Давр бошига қолдиқ: 1 000 000=00 · Давр охирига қолдиқ: 2 115 432=11', 'Кирим: 1 та, чиқим: 1 та, бекор қилинган: 1 та · Рақамлар: кирим 12–13, чиқим 7–7',
    'Бош бухгалтер Синов Б.Б.', 'Кассир'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(h.includes('<s>50 000=00</s>') && !h.includes('<summa>'), 'bekor qilingan summa chizilgan; sabab ekranlangan');
  assert.ok(!t.includes('ДИҚҚАТ') && !t.includes('СИНОВ'), 'mos jurnalda ogohlantirish yo‘q');
});

test('KO-3 jurnal: rus va lotin; qoldiq mos emas — ogohlantirish; sinov kassasi — belgi; bo‘sh davr', () => {
  let t = text(journalHtml(mkJournal(), ctx({ lang: 'ru' }), W));
  assert.ok(t.includes('ЖУРНАЛ РЕГИСТРАЦИИ ПРИХОДНЫХ И РАСХОДНЫХ КАССОВЫХ ДОКУМЕНТОВ') && t.includes('Форма КО-3') && t.includes('Итого (без аннулированных) 2 350 000=00')
    && t.includes('Номера: приход 12–13, расход 7–7') && t.includes('аннулирован: Xato <summa>') && t.includes('Главный бухгалтер'), t);
  t = text(journalHtml(mkJournal({ balanced: false }), ctx({ lang: 'uz-latn' }), W));
  assert.ok(t.includes('KIRIM VA CHIQIM KASSA HUJJATLARINI RO‘YXATGA OLISH JURNALI') && t.includes('DIQQAT: davr boshi + kirim − chiqim davr oxiriga teng emas'), t);
  t = text(journalHtml(mkJournal({ desk: { id: 'sinov', name: 'Sinov kassasi', isTest: true } }), ctx(), W));
  assert.ok(t.includes('СИНОВ'), 'sinov kassasi belgisi');
  t = text(journalHtml(mkJournal({ docs: [], totals: { in: 0, nIn: 0, out: 0, nOut: 0, voids: 0 } }), ctx(), W));
  assert.ok(t.includes('Рақамлар: кирим йўқ, чиқим йўқ') && t.includes('Жами (бекор қилинганларсиз) –'), t);
});

test('KO-3 XLSX varag‘i: sarlavha, xronologik qatorlar (son va sana katakchalari), jamlar; SheetJS bilan yozib-o‘qiladi', () => {
  const sh = journalSheet(mkJournal(), ctx({ rules: rulesJ }));
  assert.equal(sh.name, 'KO-3');
  assert.deepEqual(sh.rows[4], ['Sana', 'Hujjat', '№', 'Operatsiya', 'Kimdan / kimga', 'Asos', 'Kirim, so‘m', 'Chiqim, so‘m', 'Holat', 'Fiskal chek №']);
  const r1 = sh.rows[5], r2 = sh.rows[6], r3 = sh.rows[7];
  assert.deepEqual(r1[0], { t: 'n', v: 46391, z: 'dd\\.mm\\.yyyy' }, '04.01.2027 — Excel sanasi');
  assert.deepEqual([r1[1], r1[2], r1[3], r1[6], r1[7], r1[8], r1[9]], ['Kirim orderi', 12, 'O‘quv haqi (naqd)', { t: 'n', v: 2350000, z: '#,##0.00' }, '', 'o‘tkazilgan', '000123456789']);
  assert.deepEqual([r2[2], r2[6], r2[7], r2[8]], [13, '', '', 'bekor qilingan: Xato <summa> (50 000)'], 'bekor qilingan — summa ustunlarda yo‘q, holatda');
  assert.deepEqual([r3[1], r3[2], r3[3], r3[7]], ['Chiqim orderi', 7, 'Xarajat', { t: 'n', v: 1234567.89, z: '#,##0.00' }]);
  const tot = sh.rows.find(r => r[5] === 'Jami (bekor qilinganlarsiz)');
  assert.ok(tot && tot[6].v === 2350000 && tot[7].v === 1234567.89, 'jami qatori');
  assert.ok(sh.rows.some(r => r[5] === 'Davr oxiriga qoldiq' && r[6].v === 2115432.11));
  const require = createRequire(import.meta.url), X = require('../../vendor/xlsx/xlsx.mini.min.js');
  const ws = X.utils.aoa_to_sheet(sh.rows); ws['!cols'] = sh.cols;
  const wb = X.utils.book_new(); X.utils.book_append_sheet(wb, ws, sh.name);
  const back = X.read(X.write(wb, { type: 'buffer', bookType: 'xlsx' }), { type: 'buffer' });
  const rows = X.utils.sheet_to_json(back.Sheets['KO-3'], { header: 1, raw: true, defval: '' });
  assert.equal(rows[1][0], 'KIRIM VA CHIQIM KASSA HUJJATLARINI RO‘YXATGA OLISH JURNALI (KO-3 shakli)');
  assert.deepEqual([rows[5][0], rows[5][2], rows[5][6], rows[7][7]], [46391, 12, 2350000, 1234567.89], 'raqamlar Excel’da son bo‘lib qoladi');
  assert.equal(X.SSF.format(sh.rows[5][0].z, rows[5][0]), '04.01.2027');
  const ru = journalSheet(mkJournal(), ctx({ lang: 'ru', rules: rulesJ }));
  assert.ok(ru.rows[4][0] === 'Дата' && ru.rows[5][1] === 'ПКО' && ru.rows[5][3] === 'Оплата за обучение (наличные)' && ru.rows[7][1] === 'РКО');
});

test('KO-3 XLSX ismsiz nusxa (FD-28): shaxs ID bilan, yuridik shaxs nomi va asosi qoladi, izoh qatori; sarlavha joyida', () => {
  const m = mkJournal({ masked: true, docs: [
    { id: 'cd_1', form: 'KO1', no: 12, businessDay: '2027-01-04', op: 'in_tuition', amount: 2350000, status: 'posted', partyType: 'student', partyId: 'T-7', partyName: null, partyKept: false, basis: null, voidReason: null, fiscalNo: '000123456789' },
    { id: 'cd_2', form: 'KO1', no: 13, businessDay: '2027-01-04', op: 'in_other', amount: 50000, status: 'void', partyType: 'other', partyId: null, partyName: null, partyKept: false, basis: null, voidReason: null },
    { id: 'cd_3', form: 'KO2', no: 7, businessDay: '2027-01-04', op: 'out_expense', amount: 1234567.89, status: 'posted', partyType: 'counterparty', partyId: 'cp_sup', partyName: 'Sinov Ta’minot MChJ', partyKept: true, basis: 'Hisob-faktura № 5' },
    { id: 'cd_4', form: 'KO2', no: 8, businessDay: '2027-01-05', op: 'out_salary', amount: 900000, status: 'posted', partyType: 'employee', partyId: 'IQX-T1', partyName: null, partyKept: false, basis: null },
    { id: 'cd_5', form: 'KO2', no: 9, businessDay: '2027-01-05', op: 'out_shortage', amount: 5000, status: 'posted', partyType: null, partyId: null, partyName: 'Kassa kamomadi', partyKept: true, isSystem: true, basis: 'Kassani sanash dalolatnomasi, 05.01.2027' }] });
  const sh = journalSheet(m, ctx({ rules: rulesJ }));
  assert.match(sh.rows[3][0], /^Ismsiz nusxa \(FD-28\): jismoniy shaxslar ID bilan/);
  assert.equal(sh.rows[4][0], 'Sana', 'ustun sarlavhasi o‘z joyida (5-qator)');
  assert.deepEqual(sh.rows.slice(5, 10).map(r => [r[4], r[5]]), [['o‘quvchi T-7', ''], ['boshqa shaxs', ''], ['Sinov Ta’minot MChJ', 'Hisob-faktura № 5'],
    ['xodim IQX-T1', ''], ['Kassa kamomadi', 'Kassani sanash dalolatnomasi, 05.01.2027']]);
  assert.equal(sh.rows[6][8], 'bekor qilingan (50 000)', 'sababsiz — faqat holat va summa');
  assert.deepEqual(sh.rows[5][6], { t: 'n', v: 2350000, z: '#,##0.00' }, 'summa son bo‘lib qoladi');
  const ru = journalSheet(m, ctx({ lang: 'ru', rules: rulesJ }));
  assert.match(ru.rows[3][0], /^Обезличенная копия \(FD-28\)/);
  assert.deepEqual([ru.rows[5][4], ru.rows[8][4], ru.rows[6][8]], ['учащийся T-7', 'сотрудник IQX-T1', 'аннулирован (50 000)']);
  assert.deepEqual(journalSheet(mkJournal(), ctx({ rules: rulesJ })).rows[3], [], 'to‘liq nusxada izoh qatori bo‘sh');
});

// ---------------------------------------------------------------- RP-08: oylik statiya matritsasi va oylik kassa to'plami (F1.22)
const arr = (n, o) => Array.from({ length: n }, (_, i) => o[i + 1] || 0);
const run = (n, open, din, dout) => { let b = open; return Array.from({ length: n }, (_, i) => (b += num0(din[i]) - num0(dout[i]))); };
const num0 = v => Number(v) || 0;
const mkMatrix = over => {
  const dayIn = arr(31, { 4: 600000, 8: 2000000, 12: 500000 }), dayOut = arr(31, { 4: 450000, 12: 1500000, 29: 500000 });
  return Object.assign({ ok: true, month: '2027-01', from: '2027-01-01', to: '2027-01-31', nDays: 31, desk: { id: 'main', name: 'Asosiy kassa', isTest: false },
    opening: 1000000, closing: 1650000, balanced: true, in: 3100000, out: 2450000, transferIn: 2000000, transferOut: 1500000,
    rows: [
      { form: 'KO1', articleId: 'IN-01', kind: 'IN', nameUz: 'Ta’lim xizmati (oylik to‘lov)', nameRu: 'Образовательные услуги', transfer: false, byDay: arr(31, { 4: 600000, 12: 500000 }), total: 1100000 },
      { form: 'KO1', articleId: 'OP-01', kind: 'OP', nameUz: 'Bankdan naqd olish', nameRu: 'Получение наличных в банке', transfer: true, byDay: arr(31, { 8: 2000000 }), total: 2000000 },
      { form: 'KO2', articleId: 'EX-20', kind: 'EX', nameUz: 'Oziq-ovqat mahsulotlari', nameRu: 'Продукты питания', transfer: false, byDay: arr(31, { 4: 450000, 29: 500000 }), total: 950000 },
      { form: 'KO2', articleId: 'OP-02', kind: 'OP', nameUz: 'Bankka topshirish', nameRu: 'Сдача в банк', transfer: true, byDay: arr(31, { 12: 1500000 }), total: 1500000 }],
    dayIn, dayOut, dayBal: run(31, 1000000, dayIn, dayOut),
    days: [{ day: '2027-01-04', status: 'verified', closing: 1150000 }, { day: '2027-01-08', status: 'verified', closing: 3150000 },
           { day: '2027-01-12', status: 'closed', closing: 2150000 }, { day: '2027-01-29', status: 'open', closing: 1650000 }] }, over || {});
};

test('RP-08 matritsa (chop etish): haftalar bo‘yicha, bo‘limlar va jamlar, ichki o‘tkazma belgisi, qoldiqlar, imzolar; uch tilda', () => {
  const h = matrixHtml(mkMatrix(), ctx(), W), t = text(h);
  for (const must of ['«SINOV MAKTAB» МЧЖ', 'КАССА БЎЙИЧА ОЙЛИК СТАТИЯЛАР МАТРИЦАСИ', '2027 йил январь · Asosiy kassa', 'Код Статья Ой кунлари Жами 1–7 8–14 15–21 22–28 29–31',
    'КИРИМ IN-01 Ta’lim xizmati (oylik to‘lov) 600 000=00 500 000=00 1 100 000=00', 'OP-01 Bankdan naqd olish (ички ўтказма) 2 000 000=00 2 000 000=00',
    'Жами кирим 600 000=00 2 500 000=00 3 100 000=00', 'ЧИҚИМ EX-20 Oziq-ovqat mahsulotlari 450 000=00 500 000=00 950 000=00',
    'Жами чиқим 450 000=00 1 500 000=00 500 000=00 2 450 000=00',
    'Давр охирига қолдиқ 1 150 000=00 2 150 000=00 2 150 000=00 2 150 000=00 1 650 000=00 1 650 000=00',
    'Ой бошига қолдиқ: 1 000 000=00 · Жами кирим: 3 100 000=00 · Жами чиқим: 2 450 000=00 · Ой охирига қолдиқ: 1 650 000=00',
    'Ички ўтказмаларсиз (банк): кирим 1 100 000=00, чиқим 950 000=00', 'Тузди: бухгалтер', 'Бош бухгалтер Синов Б.Б.'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(!t.includes('ДИҚҚАТ') && !t.includes('СИНОВ'), 'mos matritsada ogohlantirish va sinov belgisi yo‘q');
  let r = text(matrixHtml(mkMatrix(), ctx({ lang: 'ru' }), W));
  assert.ok(r.includes('МЕСЯЧНАЯ МАТРИЦА СТАТЕЙ ПО КАССЕ') && r.includes('Январь 2027 г.') && r.includes('Образовательные услуги') && r.includes('(внутреннее перемещение)')
    && r.includes('Итого приход') && r.includes('Без внутренних перемещений (банк): приход 1 100 000=00, расход 950 000=00') && r.includes('Составил: бухгалтер'), r);
  r = text(matrixHtml(mkMatrix({ balanced: false, desk: { id: 'sinov', name: 'Sinov kassasi', isTest: true } }), ctx({ lang: 'uz-latn' }), W));
  assert.ok(r.includes('KASSA BO‘YICHA OYLIK STATIYALAR MATRITSASI') && r.includes('2027-yil yanvar') && r.includes('DIQQAT: davr boshi + kirim − chiqim davr oxiriga teng emas') && r.includes('SINOV'), r);
  const feb = text(matrixHtml(mkMatrix({ month: '2027-02', nDays: 28, rows: [], dayIn: arr(28, {}), dayOut: arr(28, {}), dayBal: arr(28, {}), in: 0, out: 0, transferIn: 0, transferOut: 0, opening: 0, closing: 0 }), ctx({ lang: 'uz-latn' }), W));
  assert.ok(feb.includes('Bu oyda o‘tkazilgan order yo‘q.') && feb.includes('2027-yil fevral'), feb);
  assert.ok(!matrixHtml(mkMatrix({ rows: [Object.assign({}, mkMatrix().rows[0], { nameUz: '<b>x</b>' })] }), ctx(), W).includes('<b>x</b>'), 'nom ekranlanadi');
});

test('RP-08 XLSX varag‘i: kunlar bo‘yicha (son katakchalar), bo‘limlar, kun oxiri qoldig‘i faqat kassa kunlarida; SheetJS bilan yozib-o‘qiladi', () => {
  const sh = matrixSheet(mkMatrix(), ctx());
  assert.equal(sh.name, 'E2 Statiyalar');
  assert.deepEqual(sh.rows[4].slice(0, 4).concat(sh.rows[4].slice(-2)), ['Kod', 'Statiya', '1', '2', '31', 'Jami']);
  assert.equal(sh.rows[4].length, 34);
  assert.deepEqual([sh.rows[5][1], sh.rows[6][0], sh.rows[6][1], sh.rows[6][5], sh.rows[6][6], sh.rows[6][33]],
    ['KIRIM', 'IN-01', 'Ta’lim xizmati (oylik to‘lov)', { t: 'n', v: 600000, z: '#,##0.00' }, '', { t: 'n', v: 1100000, z: '#,##0.00' }]);
  assert.equal(sh.rows[7][1], 'Bankdan naqd olish (ichki o‘tkazma)');
  assert.deepEqual([sh.rows[8][1], sh.rows[8][33].v, sh.rows[9][1], sh.rows[12][1], sh.rows[12][33].v], ['Jami kirim', 3100000, 'CHIQIM', 'Jami chiqim', 2450000]);
  const bal = sh.rows[13];
  assert.deepEqual([bal[1], bal[5].v, bal[6], bal[9].v, bal[13].v, bal[30].v, bal[31], bal[33].v], ['Kun oxiriga qoldiq', 1150000, '', 3150000, 2150000, 1650000, '', 1650000], 'faqat kassa kunlari');
  assert.ok(sh.rows.some(r => r[1] === 'Oy boshiga qoldiq' && r[2].v === 1000000) && sh.rows.some(r => r[1] === 'Jami kirim — ichki o‘tkazma' && r[2].v === 2000000));
  const require = createRequire(import.meta.url), X = require('../../vendor/xlsx/xlsx.mini.min.js');
  const wb = X.utils.book_new(); const ws = X.utils.aoa_to_sheet(sh.rows); ws['!cols'] = sh.cols; X.utils.book_append_sheet(wb, ws, sh.name);
  const back = X.read(X.write(wb, { type: 'buffer', bookType: 'xlsx' }), { type: 'buffer' });
  const rows = X.utils.sheet_to_json(back.Sheets['E2 Statiyalar'], { header: 1, raw: true, defval: '' });
  assert.equal(rows[6].slice(2, 33).reduce((s, v) => s + (Number(v) || 0), 0), rows[6][33], 'kunlar yig‘indisi = jami (Excel’da son)');
  const ru = matrixSheet(mkMatrix(), ctx({ lang: 'ru' }));
  assert.ok(ru.name === 'E2 Статьи' && ru.rows[4][1] === 'Статья' && ru.rows[5][1] === 'ПРИХОД' && ru.rows[6][1] === 'Образовательные услуги', JSON.stringify(ru.rows.slice(4, 7)));
});

test('Qayta ishga tushirish farqi (ui-5, ishga-tushirish §9): KO-3 va RP-08 — chop etishda va XLSX da alohida qator; 0 bo‘lsa yo‘q', () => {
  const j = mkJournal({ closing: 2150432.11, restartAdj: 35000 });
  let t = text(journalHtml(j, ctx(), W));
  assert.ok(t.includes('Давр бошига қолдиқ: 1 000 000=00 · Қайта ишга тушириш фарқи (техник далолатнома «Д-»): +35 000=00 · Давр охирига қолдиқ: 2 150 432=11'), t);
  t = text(journalHtml(mkJournal({ closing: 2114432.11, restartAdj: -1000 }), ctx({ lang: 'ru' }), W));
  assert.ok(t.includes('Разница при повторном запуске кассы (технический акт «Д-»): -1 000=00'), t);
  assert.ok(!text(journalHtml(mkJournal({ restartAdj: 0 }), ctx(), W)).includes('Қайта ишга'), 'farq 0 — qator yo‘q');
  const sh = journalSheet(j, ctx({ rules: rulesJ }));
  const i = sh.rows.findIndex(r => r[5] === 'Qayta ishga tushirish farqi (texnik dalolatnoma «Д-»)');
  assert.ok(i > 0 && sh.rows[i][6].v === 35000 && sh.rows[i - 1][5] === 'Davr boshiga qoldiq' && sh.rows[i + 1][5] === 'Davr oxiriga qoldiq', JSON.stringify(sh.rows.slice(-4)));
  assert.ok(!journalSheet(mkJournal(), ctx({ rules: rulesJ })).rows.some(r => r[5] === 'Qayta ishga tushirish farqi (texnik dalolatnoma «Д-»)'), 'farqsiz — XLSX da yo‘q');
  const m = mkMatrix({ closing: 1685000, restartAdj: 35000 });
  t = text(matrixHtml(m, ctx({ lang: 'uz-latn' }), W));
  assert.ok(t.includes('Jami chiqim: 2 450 000=00 · Qayta ishga tushirish farqi (texnik dalolatnoma «Д-»): +35 000=00 · Oy oxiriga qoldiq: 1 685 000=00'), t);
  const ms = matrixSheet(m, ctx());
  const k = ms.rows.findIndex(r => r[1] === 'Qayta ishga tushirish farqi (texnik dalolatnoma «Д-»)');
  assert.ok(k > 0 && ms.rows[k][2].v === 35000 && ms.rows[k - 1][1] === 'Oy boshiga qoldiq' && ms.rows[k + 1][1] === 'Oy oxiriga qoldiq', JSON.stringify(ms.rows.slice(-6)));
  assert.ok(!matrixSheet(mkMatrix(), ctx()).rows.some(r => r[1] === 'Qayta ishga tushirish farqi (texnik dalolatnoma «Д-»)'));
});

test('Oylik kassa to‘plami: E1–E4 varaqlari; kunlar (KO-4, Z holati), hisobdorlar — ismsiz va to‘liq; bitta kitobga yoziladi', () => {
  const pack = { ok: true, month: '2027-01', from: '2027-01-01', to: '2027-01-31', masked: true, desk: { id: 'main', name: 'Asosiy kassa', isTest: false },
    journal: mkJournal({ masked: true }), matrix: mkMatrix(),
    days: [
      { day: '2027-01-04', status: 'verified', opening: 1000000, receipts: 600000, payouts: 450000, closing: 1150000, counted: 1150000, diff: 0, docs: 3, voids: 1, reopens: 0, z: { needed: true, recorded: true, missing: false, no: 'Z-1', cash: 600000, card: 0, ok: true } },
      { day: '2027-01-08', status: 'verified', opening: 1150000, receipts: 2000000, payouts: 0, closing: 3150000, counted: 3150000, diff: 0, docs: 1, voids: 0, reopens: 0, z: { needed: true, recorded: true, missing: true, reason: 'Apparat buzilgan' } },
      { day: '2027-01-12', status: 'closed', opening: 3150000, receipts: 500000, payouts: 1500000, closing: 2150000, counted: 2140000, diff: -10000, docs: 2, voids: 0, reopens: 1, z: { needed: true, recorded: true, missing: false, no: 'Z-2', cash: 490000, card: 0, ok: false, diffCash: -10000, diffCard: 0 } },
      { day: '2027-01-29', status: 'open', opening: 2150000, receipts: 0, payouts: 500000, closing: 1650000, counted: null, diff: null, docs: 1, voids: 0, reopens: 0, z: { needed: true, recorded: false, missing: false } }],
    advances: [{ code: 'IQT-T1', partyName: null, opening: 0, issued: 50000, returned: 0, reported: 0, closing: 50000 },
               { code: 'IQX-T1', partyName: null, opening: 100000, issued: 500000, returned: 150000, reported: 200000, closing: 250000 }] };
  const sheets = packSheets(pack, ctx());
  assert.deepEqual(sheets.map(x => x.name), ['E1 KO-3', 'E2 Statiyalar', 'E3 Kassa kunlari', 'E4 Hisobdorlar']);
  assert.match(sheets[0].rows[3][0], /^Ismsiz nusxa \(FD-28\)/, 'E1 — ismsiz KO-3');
  const d = sheets[2].rows;
  assert.deepEqual(d[4].slice(0, 4), ['Sana', 'Holat', 'Kun boshi', 'Kirim']);
  assert.deepEqual(d.slice(5, 9).map(r => [r[1], r[11], r[14]]), [['tekshirilgan', 'Z-1', 'mos'], ['tekshirilgan', '', 'yo‘q: Apparat buzilgan'],
    ['yopilgan', 'Z-2', 'farq: naqd -10 000, karta 0'], ['ochiq', '', 'kiritilmagan']]);
  assert.deepEqual([d[5][0].v, d[7][7].v, d[8][6], d[7][10]], [46391, -10000, '', 1], 'sana — Excel sanasi, farq — son, ochiq kunda sanalgan yo‘q');
  const tot = d[d.length - 1];
  assert.deepEqual([tot[0], tot[3].v, tot[4].v, tot[7].v, tot[8], tot[9]], ['Jami', 3100000, 2450000, -10000, 7, 1]);
  const a = sheets[3].rows;
  assert.match(a[3][0], /^Ismsiz nusxa \(FD-28\): xodimlar tabel kodi bilan/);
  assert.deepEqual(a[4], ['Xodim (tabel kodi)', 'Oy boshiga qoldiq', 'Berildi (avans)', 'Qaytdi (qaytim)', 'Avans hisobotlari', 'Oy oxiriga qoldiq'], 'ismsizda F.I.Sh. ustuni yo‘q');
  assert.deepEqual([a[6][0], a[6][1].v, a[6][5].v, a[a.length - 1][0], a[a.length - 1][5].v], ['IQX-T1', 100000, 250000, 'Jami', 300000]);
  const full = advSheet(Object.assign({}, pack, { masked: false, advances: [Object.assign({}, pack.advances[1], { partyName: 'Sinov Zavxoz' })] }), ctx());
  assert.deepEqual([full.rows[3], full.rows[4][1], full.rows[5][1], full.rows[5][6].v], [[], 'F.I.Sh.', 'Sinov Zavxoz', 250000], 'Direktor nusxasi — ism bilan');
  assert.equal(advSheet(Object.assign({}, pack, { advances: [] }), ctx()).rows[5][0], 'Harakat va qoldiq yo‘q');
  assert.ok(!a.some(r => /manfiy/.test(String(r[0] || ''))), 'manfiy qoldiq bo‘lmasa — eslatma yo‘q');
  const neg = advSheet(Object.assign({}, pack, { advances: pack.advances.concat([{ code: 'IQT-T9', partyName: null, opening: 0, issued: 50000, returned: 70000, reported: 0, closing: -20000 }]) }), ctx()).rows;
  assert.deepEqual([neg[neg.length - 3][0], neg[neg.length - 3][5].v, neg[neg.length - 1][0]],
    ['Jami', 280000, 'Diqqat: oy oxiriga manfiy qoldiq (qaytim yoki avans hisoboti berilgan avansdan ko‘p) — tekshiring: IQT-T9'], 'acc-3 / state-5: manfiy qoldiq belgilanadi');
  const require = createRequire(import.meta.url), X = require('../../vendor/xlsx/xlsx.mini.min.js');
  const wb = X.utils.book_new();
  sheets.forEach(s => { const ws = X.utils.aoa_to_sheet(s.rows); ws['!cols'] = s.cols; X.utils.book_append_sheet(wb, ws, s.name); });
  const back = X.read(X.write(wb, { type: 'buffer', bookType: 'xlsx' }), { type: 'buffer' });
  assert.deepEqual(back.SheetNames, ['E1 KO-3', 'E2 Statiyalar', 'E3 Kassa kunlari', 'E4 Hisobdorlar']);
  const ru = packSheets(pack, ctx({ lang: 'ru' }));
  assert.deepEqual(ru.map(x => x.name), ['E1 КО-3', 'E2 Статьи', 'E3 Кассовые дни', 'E4 Подотчётные']);
  assert.ok(ru[2].rows[5][1] === 'проверен' && ru[2].rows[7][14] === 'расхождение: наличные -10 000, карты 0' && ru[3].rows[4][0] === 'Сотрудник (табельный №)');
});

// ---------------------------------------------------------------- ko'rik 2-guruhi (acc-2, acc-5, crit-2)
test('o‘zaro hisob (eski avans bilan, acc-2): avans qo‘llangan qator jadvalda emas — ma’lumot qatori; jadval jami = dalolatnoma summasi; uch tilda', () => {
  const d = Object.assign({}, ofsDoc, { id: 'kd_ofs2', no: 4, amount: 100000,
    basis: 'O‘zaro hisob: ish haqi 2026-12 hisobidan o‘quv to‘lovi — Sinov D (T-4); ariza 06.01.2027',
    sourceSnapshot: { month: '2026-12', studentId: 'T-4', studentName: 'Sinov D', requestDate: '2027-01-06', paymentId: 'ofs_y', allocation: 'exact' },
    lines: [
      { lineNo: 1, debit: '6710', credit: '4010', amount: 50000, articleId: 'IN-01', cash: false, analytics: { studentId: 'T-4', invoiceId: 'ic4', month: '2027-01' } },
      { lineNo: 2, debit: '6310', credit: '4010', amount: 50000, articleId: 'IN-01', cash: false, analytics: { studentId: 'T-4', invoiceId: 'ic4', month: '2027-01', kind: 'credit_applied' } },
      { lineNo: 3, debit: '6710', credit: '6310', amount: 50000, articleId: 'IN-01', cash: false, analytics: { studentId: 'T-4', kind: 'overpay' } },
    ] });
  const t = text(docHtml(d, ctx(), W));
  for (const must of ['ЎЗАРО ҲИСОБ ДАЛОЛАТНОМАСИ № ЎҲ-4', '6710 4010 T-4 · 01.2027 50 000=00 IN-01', '6710 6310 T-4 50 000=00 IN-01',
    'Маълумот учун — ўқувчининг аввалги аванси фактурага қўлланди (далолатнома суммасига кирмайди): Дебет 6310 — Кредит 4010: 50 000=00 (T-4 · 01.2027)',
    'Сумма: 100 000=00 — Бир юз минг сўм 00 тийин'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(!t.includes('6310 4010 T-4'), 'avans qatori jadvalda emas (jadval jami = summa)');
  const h = docHtml(d, ctx(), W), body = h.slice(h.indexOf('<tbody>'), h.indexOf('</tbody>'));
  assert.equal(count(body, '<tr>'), 2, 'jadvalda 2 qator: 50 000 + 50 000 = 100 000');
  const r = text(docHtml(d, ctx({ lang: 'ru' }), W));
  assert.ok(r.includes('Справочно — ранее внесённый аванс учащегося зачтён в счёт (в сумму акта не входит): Дебет 6310 — Кредит 4010: 50 000=00 (T-4 · 01.2027)'), r);
  const l = text(docHtml(d, ctx({ lang: 'uz-latn' }), W));
  assert.ok(l.includes('Ma’lumot uchun — o‘quvchining avvalgi avansi fakturaga qo‘llandi (dalolatnoma summasiga kirmaydi): Debet 6310 — Kredit 4010: 50 000=00 (T-4 · 01.2027)'), l);
  assert.ok(!text(docHtml(ofsDoc, ctx(), W)).includes('Маълумот учун'), 'avanssiz o‘zaro hisobda ma’lumot qatori yo‘q');
});

test('avans hisoboti (acc-5): asosiy vosita va sotish uchun tovar — haqiqiy debet hisobvaraqlari (0820, 2910)', () => {
  const d = Object.assign({}, advDoc, { id: 'kd_adv2', no: 6, amount: 100000, basis: 'Avans hisoboti 11.01.2027; Noutbuk va forma',
    sourceSnapshot: { reportDate: '2027-01-11', openBefore: 150000, openAfter: 50000 },
    lines: [
      { lineNo: 1, debit: '0820', credit: '4230', amount: 70000, articleId: 'OP-18', cash: false, note: 'Chek 31, noutbuk', analytics: { partyId: 'staff:st1' } },
      { lineNo: 2, debit: '2910', credit: '4230', amount: 30000, articleId: 'OP-24', cash: false, note: 'Chek 32, forma', analytics: { partyId: 'staff:st1' } },
    ] });
  const t = text(docHtml(d, ctx(), W));
  for (const must of ['АВАНС ҲИСОБОТИ № А-6', '0820 4230 Chek 31, noutbuk 70 000=00 OP-18', '2910 4230 Chek 32, forma 30 000=00 OP-24',
    'Ҳисобдордаги аванс қолдиғи: ҳисоботдан олдин 150 000=00 сўм, кейин 50 000=00 сўм.'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
});

test('o‘quvchi avansini naqd qaytarish (crit-2): KO-2 — Dt 6310, asos chop etish tilida, o‘quvchi kodi', () => {
  const d = { id: 'kd_rc', form: 'KO2', op: 'out_refund', status: 'posted', no: 9, businessDay: '2027-01-06', amount: 200000, partyType: 'student', partyId: 'T-6',
    partyName: 'Sinov Ota Onaevich', basis: 'Qaytarish: o‘quvchi avansi — O‘quvchi ketdi; ariza 05.01.2027', attachment: 'Yozma ariza', sourceTable: 'refunds',
    sourceSnapshot: { target: 'credit', targetId: 'T-6', studentId: 'T-6', amount: 200000 }, dirApprovedBy: 'u_dir', postedBy: 'u_kas',
    lines: [{ debit: '6310', credit: '5010', amount: 200000, cash: true, articleId: 'OP-15', analytics: { studentId: 'T-6', kind: 'credit_refund' } }] };
  const t = text(docHtml(d, ctx(), W));
  for (const must of ['ЧИҚИМ КАССА ОРДЕРИ № 9', '6310 T-6 5010 200 000=00 OP-15', 'Берилсин: Sinov Ota Onaevich (ўқувчи: T-6)',
    'Асоси: Қайтариш: ўқувчи аванси — O‘quvchi ketdi; ариза 05.01.2027', 'Иловаси: Ёзма ариза', 'Икки юз минг сўм 00 тийин'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(text(docHtml(d, ctx({ lang: 'ru' }), W)).includes('Основание: Возврат: аванс учащегося — O‘quvchi ketdi; заявление 05.01.2027'));
  assert.ok(text(docHtml(d, ctx({ lang: 'uz-latn' }), W)).includes('Asosi: Qaytarish: o‘quvchi avansi — O‘quvchi ketdi; ariza 05.01.2027'));
});
