// F2.14 (xodimning o'quv yili ish haqi to'lov qaydnomasi, Sh-8 B17) va F2.15 (1C ga yuklash — E8 provodkalar, Sh-8 B1) — sahifa
//   yordamchilari (fin-kassa.js) va bosma / Excel (fin-print.js) sinovi:
//   node --test assets/js/fin-paysheet.test.mjs
//   eduYearOf / eduMonths (o'quv yili), paySheetRef (order → xodim va yil), paySheetHtml (uch tilda: sarlavha, yil, xodim, 12 oy qatori,
//   to'lov turlari, qaytim — minus bilan, jamlar, so'z bilan, kassagacha yozuvlar, imzolar, boshqa xodim yo'q), postingsSheet (1-qator —
//   sarlavha, Excel sanasi / matn hisobvaraq / son summa, QT tuzatish yozuvi, jamlar, korrespondensiya, ismsiz nusxa izohi, ru). Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as W from './fin-words.js';
import { paySheetRef } from './fin-kassa.js';
import { eduYearOf, eduMonths, paySheetHtml, postingsSheet, packSheets } from './fin-print.js';

const text = h => h.replace(/<style[\s\S]*?<\/style>/g, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
  .replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim();
const org = { nameUz: '«SINOV MAKTAB» МЧЖ', nameRu: 'ООО «SINOV MAKTAB»', stir: '123456789', place: 'Тошкент ш.', printLang: 'uz-cyrl', extra: {} };
const signatories = [{ id: 's2', list: 2, uid: 'u_acc', title: 'Бош бухгалтер', fullName: 'Синов Б.Б.', active: true }];
const ctx = over => Object.assign({ org, signatories, printedBy: 'Sinov Kassir', printedAt: '2027-02-02T05:11:00Z' }, over || {});
const sheet = {
  ok: true, year: 2026, from: '2026-09', to: '2027-08',
  party: { id: 'teachers:t1', code: 'IQT-1', name: 'Sinov Muallima', kind: 'teacher', position: null },
  rows: [
    { id: 'pa', form: 'KO2', series: 'KO2', op: 'out_advance', no: 1, day: '2026-09-15', month: '2026-09', kind: 'advance', amount: 500000 },
    { id: 'pe', form: 'KO1', series: 'KO1', op: 'in_staff_return', no: 1, day: '2026-09-20', month: '2026-09', kind: 'advanceReturn', amount: 50000 },
    { id: 'pb', form: 'KO2', series: 'KO2', op: 'out_salary', no: 2, day: '2026-10-05', month: '2026-09', kind: 'salary', amount: 2000000 },
    { id: 'pd', form: 'KO1', series: 'KO1', op: 'in_staff_return', no: 2, day: '2026-10-07', month: '2026-09', kind: 'salaryReturn', amount: 100000 },
    { id: 'pc', form: 'KO2', series: 'KO2', op: 'out_salary', no: 1, day: '2027-09-05', month: '2027-08', kind: 'salary', amount: 2100000 }],
  totals: { salary: 4100000, advance: 500000, salaryReturn: 100000, advanceReturn: 50000, paid: 4600000, returned: 150000, net: 4450000 },
  legacy: { n: 3, sum: 900000 },
};

test('eduYearOf / eduMonths: o‘quv yili sentyabrdan; 12 oy', () => {
  assert.equal(eduYearOf('2027-01'), 2026);
  assert.equal(eduYearOf('2026-09-01'), 2026);
  assert.equal(eduYearOf('2026-08-31'), 2025);
  assert.equal(eduYearOf('2026-12'), 2026);
  assert.equal(eduYearOf('2026-13'), null);
  assert.equal(eduYearOf(''), null);
  assert.equal(eduYearOf(null), null);
  assert.deepEqual(eduMonths(2026), ['2026-09', '2026-10', '2026-11', '2026-12', '2027-01', '2027-02', '2027-03', '2027-04', '2027-05', '2027-06', '2027-07', '2027-08']);
});

test('paySheetRef: maosh / avans / qaytim orderi → xodim kaliti va o‘quv yili (surat oyi, yo‘q bo‘lsa — kun oyi); boshqalari — yo‘q', () => {
  const d = { status: 'posted', op: 'out_salary', partyType: 'employee', partyId: 'teachers:t1', sourceSnapshot: { month: '2027-08' }, businessDay: '2027-09-05' };
  assert.deepEqual(paySheetRef(d), ['teachers:t1', 2026], 'avgust maoshi sentyabrda berilsa — avgust (2026/27)');
  assert.deepEqual(paySheetRef(Object.assign({}, d, { op: 'out_advance', sourceSnapshot: null, businessDay: '2026-09-15' })), ['teachers:t1', 2026]);
  assert.deepEqual(paySheetRef(Object.assign({}, d, { op: 'in_staff_return', partyId: 'staff:s1', sourceSnapshot: { month: '2027-01' } })), ['staff:s1', 2026]);
  assert.deepEqual(paySheetRef(Object.assign({}, d, { sourceSnapshot: { month: 'yomon' }, businessDay: '2026-08-28' })), ['teachers:t1', 2025], 'noto‘g‘ri surat oyi — kun oyi');
  assert.equal(paySheetRef(Object.assign({}, d, { status: 'void' })), null);
  assert.equal(paySheetRef(Object.assign({}, d, { op: 'out_accountable' })), null);
  assert.equal(paySheetRef(Object.assign({}, d, { partyType: 'other' })), null);
  assert.equal(paySheetRef(Object.assign({}, d, { partyId: 'cp1' })), null);
  assert.equal(paySheetRef(null), null);
});

test('paySheetHtml (kirill): sarlavha, yil, xodim, 12 oy qatori, to‘lovlar va qaytimlar, jamlar, so‘z bilan, kassagacha yozuvlar, imzolar', () => {
  const t = text(paySheetHtml(sheet, ctx(), W));
  assert.match(t, /ИШ ҲАҚИ ТЎЛОВ ҚАЙДНОМАСИ 2026\/2027 ўқув йили \(сентябрь – август\)/);
  assert.match(t, /Ходим: Sinov Muallima Табел рақами: IQT-1 Лавозими: Ўқитувчи/);
  assert.match(t, /№ Ой Тўлов тури Ҳужжат Сана Сумма Олувчи имзоси/);
  assert.match(t, /1 сентябрь 2026 Иш ҳақи аванси Ч-1 15\.09\.2026 500 000=00 2 Аванс кассага қайтарилди К-1 20\.09\.2026 −50 000=00 3 Иш ҳақи Ч-2 05\.10\.2026 2 000 000=00 4 Иш ҳақи кассага қайтарилди К-2 07\.10\.2026 −100 000=00 октябрь 2026 — — — —/);
  assert.match(t, /июль 2027 — — — — 5 август 2027 Иш ҳақи Ч-1 05\.09\.2027 2 100 000=00/);
  for (const m of ['сентябрь 2026', 'декабрь 2026', 'январь 2027', 'август 2027']) assert.ok(t.includes(m), m);
  assert.match(t, /Жами берилди \(чиқим касса ордерлари\): 4 600 000=00 Кассага қайтарилди \(кирим касса ордерлари\): −150 000=00 Соф тўланди: 4 450 000=00 \(сўз билан: Тўрт миллион тўрт юз эллик минг сўм 00 тийин\)/);
  assert.match(t, /Касса ишга тушгунга қадар касса ҳужжатисиз ёзилган нақд тўловлар: 3 та, 900 000=00 — бу қайдномага киритилмаган\./);
  assert.match(t, /Қайднома фақат шу ходимга тегишли; бошқа ходимларнинг суммалари кўрсатилмайди\./);
  assert.match(t, /Кассир .*Бош бухгалтер Синов Б\.Б\. .*Танишдим: ходим Sinov Muallima/);
  assert.match(t, /IQT-1 · 2026\/2027 · чоп этилди: 02\.02\.2027 10:11, Sinov Kassir$/);
});

test('paySheetHtml (lotin, rus): sarlavha, lavozim, turlar; qaytimsiz va kassagacha yozuvsiz — o‘sha qatorlar yo‘q; bo‘sh yil', () => {
  const lt = text(paySheetHtml(sheet, ctx({ lang: 'uz-latn' }), W));
  assert.match(lt, /ISH HAQI TO‘LOV QAYDNOMASI 2026\/2027 o‘quv yili \(sentyabr – avgust\)/);
  assert.match(lt, /1 sentyabr 2026 Ish haqi avansi Ch-1 15\.09\.2026 500 000=00 2 Avans kassaga qaytarildi K-1/);
  const st = Object.assign({}, sheet, { party: { id: 'staff:s1', code: 'IQX-1', name: 'Sinov Xodima', kind: 'staff', position: 'Hamshira' },
    rows: [sheet.rows[0]], totals: { paid: 500000, returned: 0, net: 500000 }, legacy: { n: 0, sum: 0 } });
  const ru = text(paySheetHtml(st, ctx({ lang: 'ru' }), W));
  assert.match(ru, /ПЛАТЁЖНАЯ ВЕДОМОСТЬ ПО ЗАРАБОТНОЙ ПЛАТЕ 2026\/2027 учебный год \(сентябрь – август\) Сотрудник: Sinov Xodima Табельный номер: IQX-1 Должность: Hamshira/);
  assert.match(ru, /1 сентябрь 2026 Аванс по заработной плате Р-1 15\.09\.2026 500 000=00/);
  assert.match(ru, /Итого выдано \(расходные кассовые ордера\): 500 000=00 Чистая выплата: 500 000=00 \(прописью: Пятьсот тысяч сумов 00 тийин\)/);
  assert.ok(!/Возвращено в кассу/.test(ru) && !/до запуска кассы/.test(ru), 'qaytim va kassagacha yozuv bo‘lmasa — qatorlari yo‘q');
  const empty = text(paySheetHtml({ year: 2024, party: { name: 'X', code: 'C', kind: 'teacher' }, rows: [], totals: {}, legacy: { n: 0 } }, ctx({ lang: 'uz-latn' }), W));
  assert.equal((empty.match(/ — — — —/g) || []).length, 12, '12 oy — bo‘sh qatorlar');
  assert.match(empty, /Jami berildi \(chiqim kassa orderlari\): – Sof to‘landi: – \(so‘z bilan: Nol so‘m 00 tiyin\)/, 'nol — chiziqcha (bosma qoidasi)');
});

test('postingsSheet (E8): 1-qator — sarlavha; Excel sanasi, matn hisobvaraq, son summa; QT tuzatish yozuvi; jamlar; korrespondensiya; ismsiz izoh', () => {
  const p = { masked: true, postings: [
    { day: '2026-10-05', form: 'KO2', series: 'KO2', no: 2, op: 'out_salary', docId: 'pb', lineNo: 1, debit: '6710', credit: '5010', amount: 2000000, articleId: 'OP-09', cash: true, partyType: 'employee', code: 'IQT-1', partyName: null, basis: null },
    { day: '2026-10-06', form: 'KO2', series: 'KO2', no: 7, op: 'out_expense', docId: 'px', lineNo: 1, debit: '9420', credit: '5010', amount: 100000, articleId: 'EX-32', cash: true, partyType: 'counterparty', code: 'cp1', partyName: 'Sinov Ta‘minotchi', basis: 'Hisob-faktura № 0-5' },
    { day: '2026-10-07', form: 'KO1', series: 'KO1', no: 2, op: 'in_staff_return', docId: 'pd', lineNo: 1, debit: '5010', credit: '6710', amount: 100000, articleId: 'OP-09', cash: true, partyType: 'employee', code: 'IQT-1', partyName: null, basis: null },
    { day: '2026-10-10', form: 'ACT', series: 'OFS', no: 1, op: 'nc_offset', docId: 'po', lineNo: 1, debit: '6710', credit: '4010', amount: 300000, articleId: 'OP-11', cash: false, partyType: 'employee', code: 'IQT-1', partyName: null, basis: null },
    { day: '2026-10-25', form: 'FIX', series: 'FIX', no: 1, op: 'fix', docId: 'px', fixId: 'fx1', lineNo: 1, debit: '2010', credit: '9420', amount: 100000, articleId: 'EX-16', fromArticle: 'EX-32', cash: false,
      srcSeries: 'KO2', srcNo: 7, srcDay: '2026-10-06', partyType: 'counterparty', code: 'cp1', partyName: 'Sinov Ta‘minotchi' }] };
  const sh = postingsSheet(p, ctx({ lang: 'uz-latn' }));
  const v = c => (c && typeof c === 'object' && 'v' in c) ? c.v : c, r = sh.rows;
  assert.equal(sh.name, 'E8 Provodkalar');
  assert.deepEqual(r[0], ['Sana', 'Hujjat №', 'Dt hisobvaraq', 'Kt hisobvaraq', 'Summa', 'Statiya', 'Tomon turi', 'Tomon kodi', 'Nomi (tashkilotlar)', 'Mazmun', 'Hujjat ID']);
  assert.deepEqual(r[1].map(v), [46300, 'Ch-2', '6710', '5010', 2000000, 'OP-09', 'xodim', 'IQT-1', '', '', 'pb']);
  assert.equal(r[1][0].z, 'dd\\.mm\\.yyyy'); assert.equal(typeof r[1][2], 'string', 'hisobvaraq — matn');
  assert.deepEqual(r[2].map(v).slice(1, 10), ['Ch-7', '9420', '5010', 100000, 'EX-32', 'kontragent', 'cp1', 'Sinov Ta‘minotchi', 'Hisob-faktura № 0-5']);
  assert.deepEqual(r[4].map(v).slice(1, 7), ['O‘H-1', '6710', '4010', 300000, 'OP-11', 'xodim']);
  assert.deepEqual(r[5].map(v).slice(1, 10), ['QT-1', '2010', '9420', 100000, 'EX-16', 'kontragent', 'cp1', 'Sinov Ta‘minotchi', 'QT-1: Ch-7 (06.10.2026) tuzatish, statiya EX-32 → EX-16']);
  assert.deepEqual(r[6], [], 'ma’lumotdan keyin bo‘sh qator (1C yuklash oralig‘i)');
  assert.deepEqual(r[7].map(v), ['Jami', '', '', '', 2600000]);
  assert.deepEqual([r[8].map(v)[4], r[9].map(v)[4]], [100000, 2100000], 'Dt 5010 = kirim, Kt 5010 = chiqim');
  const i = r.findIndex(x => x[0] === 'Hisobvaraqlar korrespondensiyasi bo‘yicha aylanma');
  assert.deepEqual(r.slice(i + 2, i + 7).map(x => x.map(v)), [['2010', '9420', 100000], ['5010', '6710', 100000], ['6710', '4010', 300000], ['6710', '5010', 2000000], ['9420', '5010', 100000]]);
  assert.match(r[r.length - 1][0], /^Ismsiz nusxa \(FD-28\)/);
  assert.equal(sh.cols.length, r[0].length);
  const ru = postingsSheet(Object.assign({}, p, { masked: false }), ctx({ lang: 'ru' }));
  assert.equal(ru.name, 'E8 Проводки');
  assert.deepEqual(ru.rows[0].slice(0, 5), ['Дата', 'Номер документа', 'Счёт Дт', 'Счёт Кт', 'Сумма']);
  assert.equal(ru.rows[0][8], 'Наименование');
  assert.deepEqual([ru.rows[1][1], ru.rows[4][1], ru.rows[5][1]], ['Р-2', 'ВЗ-1', 'АП-1']);
  assert.match(ru.rows[5][9], /^АП-1: исправление Р-7 от 06\.10\.2026, статья EX-32 → EX-16$/);
  assert.ok(!/Обезличенная/.test(JSON.stringify(ru.rows)), 'Direktor nusxasida ismsiz izoh yo‘q');
  const none = postingsSheet({ postings: [] }, ctx({ lang: 'uz-latn' }));
  assert.deepEqual(none.rows[1], ['Shu oyda provodka yo‘q']);
  assert.ok(!none.rows.some(x => x[0] === 'Hisobvaraqlar korrespondensiyasi bo‘yicha aylanma'));
});

test('packSheets: 17-reliz javobida E8 qo‘shiladi (8 varaq); postings yo‘q (eski server) — 7', () => {
  const base = { month: '2026-10', journal: {}, matrix: {}, days: [], advances: [], offsets: [], staffDiscounts: [], payroll: null };
  assert.deepEqual(packSheets(Object.assign({}, base, { postings: [] }), ctx({ lang: 'uz-latn' })).map(x => x.name).slice(4),
    ['E5 O‘zaro hisob', 'E6 Xodim farzandi', 'E7 Vedomost', 'E8 Provodkalar']);
  assert.equal(packSheets(base, ctx({ lang: 'uz-latn' })).length, 7);
});
