// =====================================================================
// fin-words.js — summani SO'Z BILAN yozish va hujjat ko'rinishidagi formatlar (moliya ish rejasi §4.15, F1.14).
//   Kassa hujjatlarini (KO-1 kirim orderi, KO-2 chiqim orderi, KO-4 kassa kitobi, dalolatnomalar) chop etishda ishlatiladi.
//   Tillar: 'uz-cyrl' (o'zbek kirill — standart), 'uz-latn' (o'zbek lotin), 'ru' (rus).
//   Bog'liqliksiz sof funksiyalar; brauzerda import() bilan, Node'da test uchun yuklanadi. Suzuvchi nuqta xatosi yo'q:
//   summa matn sifatida tiyinlargacha (BigInt) aniq hisoblanadi.
// =====================================================================

const L = {
  'uz-cyrl': {
    ones: ['', 'бир', 'икки', 'уч', 'тўрт', 'беш', 'олти', 'етти', 'саккиз', 'тўққиз'],
    tens: ['', 'ўн', 'йигирма', 'ўттиз', 'қирқ', 'эллик', 'олтмиш', 'етмиш', 'саксон', 'тўқсон'],
    hundred: 'юз', scales: ['', 'минг', 'миллион', 'миллиард'], zero: 'ноль', minus: 'минус', sum: 'сўм', tiyin: 'тийин',
    months: ['январь', 'февраль', 'март', 'апрель', 'май', 'июнь', 'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь'],
  },
  'uz-latn': {
    ones: ['', 'bir', 'ikki', 'uch', 'to‘rt', 'besh', 'olti', 'yetti', 'sakkiz', 'to‘qqiz'],
    tens: ['', 'o‘n', 'yigirma', 'o‘ttiz', 'qirq', 'ellik', 'oltmish', 'yetmish', 'sakson', 'to‘qson'],
    hundred: 'yuz', scales: ['', 'ming', 'million', 'milliard'], zero: 'nol', minus: 'minus', sum: 'so‘m', tiyin: 'tiyin',
    months: ['yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun', 'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'],
  },
};
const RU = {
  onesM: ['', 'один', 'два', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'],
  onesF: ['', 'одна', 'две', 'три', 'четыре', 'пять', 'шесть', 'семь', 'восемь', 'девять'],
  teens: ['десять', 'одиннадцать', 'двенадцать', 'тринадцать', 'четырнадцать', 'пятнадцать', 'шестнадцать', 'семнадцать', 'восемнадцать', 'девятнадцать'],
  tens: ['', '', 'двадцать', 'тридцать', 'сорок', 'пятьдесят', 'шестьдесят', 'семьдесят', 'восемьдесят', 'девяносто'],
  hundreds: ['', 'сто', 'двести', 'триста', 'четыреста', 'пятьсот', 'шестьсот', 'семьсот', 'восемьсот', 'девятьсот'],
  scales: [null, ['тысяча', 'тысячи', 'тысяч'], ['миллион', 'миллиона', 'миллионов'], ['миллиард', 'миллиарда', 'миллиардов']],
  sum: ['сум', 'сума', 'сумов'], zero: 'ноль', minus: 'минус', tiyin: 'тийин',
  months: ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'],
};
const langOf = lang => (lang === 'ru' || lang === 'uz-latn' || lang === 'uz-cyrl') ? lang : 'uz-cyrl';
const MAX_TIYIN = 100000000000000n;   // 10^12 so'm (shundan kichik bo'lishi shart)

// Ruscha ko'plik shakli: 1 сум, 2 сума, 5 сумов; 11–14 — сумов.
function ruForm(n, forms) {
  const m100 = n % 100, m10 = n % 10;
  if (m100 >= 11 && m100 <= 14) return forms[2];
  if (m10 === 1) return forms[0];
  if (m10 >= 2 && m10 <= 4) return forms[1];
  return forms[2];
}
// 0…999 — o'zbekcha («бир юз», «бир минг»: «бир» tushirilmaydi).
function uzTriple(n, d) {
  const out = [], h = Math.floor(n / 100), t = Math.floor(n % 100 / 10), o = n % 10;
  if (h) out.push(d.ones[h], d.hundred);
  if (t) out.push(d.tens[t]);
  if (o) out.push(d.ones[o]);
  return out;
}
// 0…999 — ruscha; fem — ayol jinsi (тысяча uchun: одна, две).
function ruTriple(n, fem) {
  const out = [], h = Math.floor(n / 100), r = n % 100;
  if (h) out.push(RU.hundreds[h]);
  if (r >= 10 && r <= 19) out.push(RU.teens[r - 10]);
  else {
    const t = Math.floor(r / 10), o = r % 10;
    if (t) out.push(RU.tens[t]);
    if (o) out.push((fem ? RU.onesF : RU.onesM)[o]);
  }
  return out;
}
// Butun son (BigInt, 0 … 999 999 999 999) so'z bilan, kichik harflarda.
function intWords(n, lang) {
  if (n === 0n) return lang === 'ru' ? RU.zero : L[lang].zero;
  const groups = [];
  for (let x = n; x > 0n; x /= 1000n) groups.push(Number(x % 1000n));
  const out = [];
  for (let i = groups.length - 1; i >= 0; i--) {
    const g = groups[i];
    if (!g) continue;
    if (lang === 'ru') {
      out.push(...ruTriple(g, i === 1));
      if (i > 0) out.push(ruForm(g, RU.scales[i]));
    } else {
      out.push(...uzTriple(g, L[lang]));
      if (i > 0) out.push(L[lang].scales[i]);
    }
  }
  return out.join(' ');
}
// Kirish (son yoki satr) -> { neg, tiyin: BigInt } yoki null. 2 xonagacha yaxlitlash — o'nlik yozuv bo'yicha (0.005 -> 0.01).
function parseAmount(v) {
  let s;
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) return null;
    s = String(v);
    if (/e/i.test(s)) s = v.toFixed(6);
  } else if (typeof v === 'bigint') {
    s = v.toString();
  } else if (typeof v === 'string') {
    s = v.replace(/[\s  ]/g, '').replace(',', '.');
  } else return null;
  if (s.length > 40) return null;
  const m = /^([+-]?)(\d+)(?:\.(\d*))?$/.exec(s);
  if (!m) return null;
  const frac = (m[3] || '') + '000';
  let t = BigInt(m[2]) * 100n + BigInt(frac.slice(0, 2));
  if (frac.charCodeAt(2) >= 53) t += 1n;   // uchinchi kasr raqami >= 5 — yuqoriga
  if (t >= MAX_TIYIN) return null;
  return { neg: m[1] === '-' && t > 0n, tiyin: t };
}
const cap = s => s ? s.charAt(0).toUpperCase() + s.slice(1) : s;

// Pul summasi so'z bilan: «Бир миллион икки юз ўттиз тўрт минг беш юз олтмиш етти сўм 89 тийин». Noto'g'ri kirish -> ''.
export function sumWords(amount, lang) {
  const p = parseAmount(amount);
  if (!p) return '';
  lang = langOf(lang);
  const whole = p.tiyin / 100n, tiy = String(p.tiyin % 100n).padStart(2, '0');
  const words = intWords(whole, lang);
  let unit, tiyin, minus;
  if (lang === 'ru') { unit = ruForm(Number(whole % 100n), RU.sum); tiyin = RU.tiyin; minus = RU.minus; }
  else { unit = L[lang].sum; tiyin = L[lang].tiyin; minus = L[lang].minus; }
  return cap((p.neg ? minus + ' ' : '') + words + ' ' + unit + ' ' + tiy + ' ' + tiyin);
}

// Butun son so'z bilan (kichik harflarda): varaqlar, hujjatlar soni. Noto'g'ri kirish -> ''.
export function countWords(n, lang) {
  let s;
  if (typeof n === 'number') { if (!Number.isInteger(n)) return ''; s = String(n); }
  else if (typeof n === 'bigint') s = n.toString();
  else if (typeof n === 'string') s = n.replace(/[\s  ]/g, '');
  else return '';
  if (!/^\d{1,12}$/.test(s)) return '';
  return intWords(BigInt(s), langOf(lang));
}

// Hujjatdagi raqamli ko'rinish: 1234567.89 -> «1 234 567=89»; 0 -> «–»; manfiy -> «-1 234=00». Noto'g'ri kirish -> ''.
export function fmtMoney(amount) {
  const p = parseAmount(amount);
  if (!p) return '';
  if (p.tiyin === 0n) return '–';
  const whole = (p.tiyin / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  return (p.neg ? '-' : '') + whole + '=' + String(p.tiyin % 100n).padStart(2, '0');
}

// Sana to'liq ko'rinishda: '2027-01-04' -> «2027 йил 4 январь» / «2027-yil 4-yanvar» / «4 января 2027 г.». Noto'g'ri sana -> ''.
export function fmtDateLong(isoDay, lang) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(isoDay == null ? '' : isoDay));
  if (!m) return '';
  const y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]);
  const dt = new Date(Date.UTC(y, mo - 1, d));
  if (mo < 1 || mo > 12 || d < 1 || dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return '';
  lang = langOf(lang);
  if (lang === 'ru') return d + ' ' + RU.months[mo - 1] + ' ' + y + ' г.';
  if (lang === 'uz-latn') return y + '-yil ' + d + '-' + L[lang].months[mo - 1];
  return y + ' йил ' + d + ' ' + L[lang].months[mo - 1];
}
