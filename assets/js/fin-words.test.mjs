// fin-words.js sinovi:  node --test assets/js/fin-words.test.mjs
//   Kutilgan satrlar qo'lda yozilgan (funksiya natijasidan ko'chirilmagan): har til uchun 45+ summa, chegaraviy holatlar.
import test from 'node:test';
import assert from 'node:assert/strict';
import { sumWords, countWords, fmtMoney, fmtDateLong } from './fin-words.js';

const T = ' 00 тийин', TL = ' 00 tiyin';
const CYRL = [
  [0, 'Ноль сўм' + T], [1, 'Бир сўм' + T], [2, 'Икки сўм' + T], [3, 'Уч сўм' + T], [4, 'Тўрт сўм' + T], [5, 'Беш сўм' + T],
  [6, 'Олти сўм' + T], [7, 'Етти сўм' + T], [8, 'Саккиз сўм' + T], [9, 'Тўққиз сўм' + T],
  [10, 'Ўн сўм' + T], [11, 'Ўн бир сўм' + T], [12, 'Ўн икки сўм' + T], [14, 'Ўн тўрт сўм' + T], [19, 'Ўн тўққиз сўм' + T],
  [20, 'Йигирма сўм' + T], [21, 'Йигирма бир сўм' + T], [22, 'Йигирма икки сўм' + T], [25, 'Йигирма беш сўм' + T],
  [30, 'Ўттиз сўм' + T], [40, 'Қирқ сўм' + T], [50, 'Эллик сўм' + T], [60, 'Олтмиш сўм' + T], [70, 'Етмиш сўм' + T],
  [80, 'Саксон сўм' + T], [90, 'Тўқсон сўм' + T], [99, 'Тўқсон тўққиз сўм' + T],
  [100, 'Бир юз сўм' + T], [101, 'Бир юз бир сўм' + T], [111, 'Бир юз ўн бир сўм' + T], [112, 'Бир юз ўн икки сўм' + T],
  [200, 'Икки юз сўм' + T], [999, 'Тўққиз юз тўқсон тўққиз сўм' + T],
  [1000, 'Бир минг сўм' + T], [1001, 'Бир минг бир сўм' + T], [1100, 'Бир минг бир юз сўм' + T], [2000, 'Икки минг сўм' + T],
  [5000, 'Беш минг сўм' + T], [11000, 'Ўн бир минг сўм' + T], [21000, 'Йигирма бир минг сўм' + T], [100000, 'Бир юз минг сўм' + T],
  [999999, 'Тўққиз юз тўқсон тўққиз минг тўққиз юз тўқсон тўққиз сўм' + T],
  [1000000, 'Бир миллион сўм' + T], [2000000, 'Икки миллион сўм' + T], [5000001, 'Беш миллион бир сўм' + T],
  [2900000, 'Икки миллион тўққиз юз минг сўм' + T], [1000000000, 'Бир миллиард сўм' + T],
  ['999999999999.99', 'Тўққиз юз тўқсон тўққиз миллиард тўққиз юз тўқсон тўққиз миллион тўққиз юз тўқсон тўққиз минг тўққиз юз тўқсон тўққиз сўм 99 тийин'],
  [0.01, 'Ноль сўм 01 тийин'], [0.5, 'Ноль сўм 50 тийин'], [1.05, 'Бир сўм 05 тийин'],
  [1234567.89, 'Бир миллион икки юз ўттиз тўрт минг беш юз олтмиш етти сўм 89 тийин'],
  [0.005, 'Ноль сўм 01 тийин'], [1.995, 'Икки сўм' + T], [0.994, 'Ноль сўм 99 тийин'],
  ['2 900 000', 'Икки миллион тўққиз юз минг сўм' + T], ['1 234,5', 'Бир минг икки юз ўттиз тўрт сўм 50 тийин'],
  [-150000, 'Минус бир юз эллик минг сўм' + T],
];
const LATN = [
  [0, 'Nol so‘m' + TL], [1, 'Bir so‘m' + TL], [2, 'Ikki so‘m' + TL], [3, 'Uch so‘m' + TL], [4, 'To‘rt so‘m' + TL], [5, 'Besh so‘m' + TL],
  [6, 'Olti so‘m' + TL], [7, 'Yetti so‘m' + TL], [8, 'Sakkiz so‘m' + TL], [9, 'To‘qqiz so‘m' + TL],
  [10, 'O‘n so‘m' + TL], [11, 'O‘n bir so‘m' + TL], [12, 'O‘n ikki so‘m' + TL], [14, 'O‘n to‘rt so‘m' + TL], [19, 'O‘n to‘qqiz so‘m' + TL],
  [20, 'Yigirma so‘m' + TL], [21, 'Yigirma bir so‘m' + TL], [22, 'Yigirma ikki so‘m' + TL], [25, 'Yigirma besh so‘m' + TL],
  [30, 'O‘ttiz so‘m' + TL], [40, 'Qirq so‘m' + TL], [50, 'Ellik so‘m' + TL], [60, 'Oltmish so‘m' + TL], [70, 'Yetmish so‘m' + TL],
  [80, 'Sakson so‘m' + TL], [90, 'To‘qson so‘m' + TL], [99, 'To‘qson to‘qqiz so‘m' + TL],
  [100, 'Bir yuz so‘m' + TL], [101, 'Bir yuz bir so‘m' + TL], [111, 'Bir yuz o‘n bir so‘m' + TL], [112, 'Bir yuz o‘n ikki so‘m' + TL],
  [200, 'Ikki yuz so‘m' + TL], [999, 'To‘qqiz yuz to‘qson to‘qqiz so‘m' + TL],
  [1000, 'Bir ming so‘m' + TL], [1001, 'Bir ming bir so‘m' + TL], [1100, 'Bir ming bir yuz so‘m' + TL], [2000, 'Ikki ming so‘m' + TL],
  [5000, 'Besh ming so‘m' + TL], [11000, 'O‘n bir ming so‘m' + TL], [21000, 'Yigirma bir ming so‘m' + TL], [100000, 'Bir yuz ming so‘m' + TL],
  [999999, 'To‘qqiz yuz to‘qson to‘qqiz ming to‘qqiz yuz to‘qson to‘qqiz so‘m' + TL],
  [1000000, 'Bir million so‘m' + TL], [2000000, 'Ikki million so‘m' + TL], [5000001, 'Besh million bir so‘m' + TL],
  [2900000, 'Ikki million to‘qqiz yuz ming so‘m' + TL], [1000000000, 'Bir milliard so‘m' + TL],
  ['999999999999.99', 'To‘qqiz yuz to‘qson to‘qqiz milliard to‘qqiz yuz to‘qson to‘qqiz million to‘qqiz yuz to‘qson to‘qqiz ming to‘qqiz yuz to‘qson to‘qqiz so‘m 99 tiyin'],
  [0.01, 'Nol so‘m 01 tiyin'], [0.5, 'Nol so‘m 50 tiyin'], [1.05, 'Bir so‘m 05 tiyin'],
  [1234567.89, 'Bir million ikki yuz o‘ttiz to‘rt ming besh yuz oltmish yetti so‘m 89 tiyin'],
  [0.005, 'Nol so‘m 01 tiyin'], [1.995, 'Ikki so‘m' + TL], [0.994, 'Nol so‘m 99 tiyin'],
  ['2 900 000', 'Ikki million to‘qqiz yuz ming so‘m' + TL], ['1 234,5', 'Bir ming ikki yuz o‘ttiz to‘rt so‘m 50 tiyin'],
  [-150000, 'Minus bir yuz ellik ming so‘m' + TL],
];
const RUS = [
  [0, 'Ноль сумов' + T], [1, 'Один сум' + T], [2, 'Два сума' + T], [3, 'Три сума' + T], [4, 'Четыре сума' + T], [5, 'Пять сумов' + T],
  [6, 'Шесть сумов' + T], [7, 'Семь сумов' + T], [8, 'Восемь сумов' + T], [9, 'Девять сумов' + T],
  [10, 'Десять сумов' + T], [11, 'Одиннадцать сумов' + T], [12, 'Двенадцать сумов' + T], [13, 'Тринадцать сумов' + T],
  [14, 'Четырнадцать сумов' + T], [15, 'Пятнадцать сумов' + T], [19, 'Девятнадцать сумов' + T],
  [20, 'Двадцать сумов' + T], [21, 'Двадцать один сум' + T], [22, 'Двадцать два сума' + T], [25, 'Двадцать пять сумов' + T],
  [30, 'Тридцать сумов' + T], [40, 'Сорок сумов' + T], [50, 'Пятьдесят сумов' + T], [60, 'Шестьдесят сумов' + T],
  [70, 'Семьдесят сумов' + T], [80, 'Восемьдесят сумов' + T], [90, 'Девяносто сумов' + T], [99, 'Девяносто девять сумов' + T],
  [100, 'Сто сумов' + T], [101, 'Сто один сум' + T], [111, 'Сто одиннадцать сумов' + T], [112, 'Сто двенадцать сумов' + T],
  [114, 'Сто четырнадцать сумов' + T], [200, 'Двести сумов' + T], [300, 'Триста сумов' + T], [400, 'Четыреста сумов' + T],
  [500, 'Пятьсот сумов' + T], [600, 'Шестьсот сумов' + T], [700, 'Семьсот сумов' + T], [800, 'Восемьсот сумов' + T],
  [999, 'Девятьсот девяносто девять сумов' + T],
  [1000, 'Одна тысяча сумов' + T], [1001, 'Одна тысяча один сум' + T], [1100, 'Одна тысяча сто сумов' + T],
  [2000, 'Две тысячи сумов' + T], [2002, 'Две тысячи два сума' + T], [5000, 'Пять тысяч сумов' + T],
  [11000, 'Одиннадцать тысяч сумов' + T], [14000, 'Четырнадцать тысяч сумов' + T], [21000, 'Двадцать одна тысяча сумов' + T],
  [22000, 'Двадцать две тысячи сумов' + T], [100000, 'Сто тысяч сумов' + T],
  [999999, 'Девятьсот девяносто девять тысяч девятьсот девяносто девять сумов' + T],
  [1000000, 'Один миллион сумов' + T], [2000000, 'Два миллиона сумов' + T], [3000000, 'Три миллиона сумов' + T],
  [5000001, 'Пять миллионов один сум' + T], [2900000, 'Два миллиона девятьсот тысяч сумов' + T],
  [1000000000, 'Один миллиард сумов' + T], [1000000001, 'Один миллиард один сум' + T], [2000000000, 'Два миллиарда сумов' + T],
  ['999999999999.99', 'Девятьсот девяносто девять миллиардов девятьсот девяносто девять миллионов девятьсот девяносто девять тысяч девятьсот девяносто девять сумов 99 тийин'],
  [0.01, 'Ноль сумов 01 тийин'], [0.5, 'Ноль сумов 50 тийин'], [1.05, 'Один сум 05 тийин'],
  [1234567.89, 'Один миллион двести тридцать четыре тысячи пятьсот шестьдесят семь сумов 89 тийин'],
  [0.005, 'Ноль сумов 01 тийин'], [1.995, 'Два сума' + T], [0.994, 'Ноль сумов 99 тийин'],
  ['2 900 000', 'Два миллиона девятьсот тысяч сумов' + T], [-150000, 'Минус сто пятьдесят тысяч сумов' + T],
];

for (const [lang, rows] of [['uz-cyrl', CYRL], ['uz-latn', LATN], ['ru', RUS]]) {
  test(`sumWords ${lang}: ${rows.length} misol`, () => {
    assert.ok(rows.length >= 35);
    for (const [v, exp] of rows) assert.equal(sumWords(v, lang), exp, `${lang} ${v}`);
  });
}

test('sumWords: noma’lum til — o‘zbek kirill; noto‘g‘ri kirish — bo‘sh satr', () => {
  assert.equal(sumWords(5, 'en'), 'Беш сўм 00 тийин');
  assert.equal(sumWords(5), 'Беш сўм 00 тийин');
  for (const bad of [NaN, Infinity, -Infinity, null, undefined, '', 'abc', '12abc', '1.2.3', {}, [], true, 1e12, '1000000000000', 1e21, '9'.repeat(60)]) {
    assert.equal(sumWords(bad, 'ru'), '', String(bad));
  }
  assert.equal(sumWords('999999999999.994', 'uz-latn').endsWith('so‘m 99 tiyin'), true);
  assert.equal(sumWords('999999999999.995', 'uz-latn'), '');          // yaxlitlangach 10^12 — chegaradan tashqari
  assert.equal(sumWords(-0, 'ru'), 'Ноль сумов 00 тийин');           // manfiy nol — minussiz
  assert.equal(sumWords('-0.004', 'ru'), 'Ноль сумов 00 тийин');
  assert.equal(sumWords(1e-7, 'ru'), 'Ноль сумов 00 тийин');          // ilmiy yozuv
  assert.equal(sumWords(' 1 500 ', 'ru'), 'Одна тысяча пятьсот сумов 00 тийин');
  assert.equal(sumWords(7n, 'ru'), 'Семь сумов 00 тийин');
});

test('countWords', () => {
  assert.equal(countWords(12, 'uz-cyrl'), 'ўн икки');
  assert.equal(countWords(12, 'uz-latn'), 'o‘n ikki');
  assert.equal(countWords(12, 'ru'), 'двенадцать');
  assert.equal(countWords(0, 'uz-cyrl'), 'ноль');
  assert.equal(countWords(0, 'uz-latn'), 'nol');
  assert.equal(countWords(0, 'ru'), 'ноль');
  assert.equal(countWords(21, 'ru'), 'двадцать один');
  assert.equal(countWords(1000, 'ru'), 'одна тысяча');
  assert.equal(countWords(1000, 'uz-cyrl'), 'бир минг');
  assert.equal(countWords('3', 'uz-latn'), 'uch');
  assert.equal(countWords(999999999999, 'uz-latn'), 'to‘qqiz yuz to‘qson to‘qqiz milliard to‘qqiz yuz to‘qson to‘qqiz million to‘qqiz yuz to‘qson to‘qqiz ming to‘qqiz yuz to‘qson to‘qqiz');
  for (const bad of [1.5, -1, 'x', '', null, undefined, NaN, 1e12, '1000000000000']) assert.equal(countWords(bad, 'ru'), '', String(bad));
});

test('fmtMoney', () => {
  assert.equal(fmtMoney(1234567.89), '1 234 567=89');
  assert.equal(fmtMoney(0), '–');
  assert.equal(fmtMoney('0.004'), '–');
  assert.equal(fmtMoney(-1234), '-1 234=00');
  assert.equal(fmtMoney(5), '5=00');
  assert.equal(fmtMoney(1000), '1 000=00');
  assert.equal(fmtMoney('2900000'), '2 900 000=00');
  assert.equal(fmtMoney(0.5), '0=50');
  assert.equal(fmtMoney('x'), '');
  assert.equal(fmtMoney(null), '');
});

test('fmtDateLong', () => {
  assert.equal(fmtDateLong('2027-01-04', 'uz-cyrl'), '2027 йил 4 январь');
  assert.equal(fmtDateLong('2027-01-04', 'uz-latn'), '2027-yil 4-yanvar');
  assert.equal(fmtDateLong('2027-01-04', 'ru'), '4 января 2027 г.');
  assert.equal(fmtDateLong('2027-01-04'), '2027 йил 4 январь');
  assert.equal(fmtDateLong('2026-12-31', 'ru'), '31 декабря 2026 г.');
  assert.equal(fmtDateLong('2026-12-31', 'uz-latn'), '2026-yil 31-dekabr');
  assert.equal(fmtDateLong('2028-02-29', 'uz-cyrl'), '2028 йил 29 февраль');   // kabisa yili
  assert.equal(fmtDateLong('2027-05-09', 'ru'), '9 мая 2027 г.');
  for (const bad of ['2027-02-29', '2027-13-01', '2027-00-10', '2027-04-31', '2027-1-4', '', null, undefined, '04.01.2027', 20270104]) {
    assert.equal(fmtDateLong(bad, 'ru'), '', String(bad));
  }
});
