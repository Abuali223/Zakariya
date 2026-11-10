// fin-print.js sinovi:  node --test assets/js/fin-print.test.mjs
//   Chop etish shakllarining MATNI tekshiriladi (KO-1 + patta, KO-2, KO-4, sanash dalolatnomasi) — uch tilda.
//   Ma'lumotlar to'qima (haqiqiy ism, summa yo'q). Kutilgan satrlar qo'lda yozilgan.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as W from './fin-words.js';
import { docHtml, bookHtml, countHtml, bookRows } from './fin-print.js';

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
