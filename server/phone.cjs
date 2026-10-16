/**
 * phone.cjs — telefon raqamini KANONIK ko'rinishga keltirish: O'zbekiston VA chet el (xalqaro, E.164).
 * -------------------------------------------------------------------
 * Kanonik = faqat raqamlar, davlat kodi bilan, '+'siz: 998901234567, 79031571124, 48789706619.
 *   auth (ro'yxat/login/OTP), SMS (Eskiz), «⚠️ Sifat», ota-ona formasi, xodim↔login bog'lash — HAMMASI shu qoida.
 *
 * Qoidalar (phoneCanon):
 *   - '+'siz 9 raqam -> O'zbekiston lokal raqami: 998 + 9 raqam. ('+' bilan 9 raqam — chala xorijiy raqam
 *     bo'lishi mumkin ('+7 903 157 11') -> yaroqsiz: jimgina boshqa O'zbekiston raqamiga aylanmasin.)
 *   - 998 bilan boshlansa -> O'zbekiston: AYNAN 12 raqam, operator kodi 2x/3x/5x/7x/8x/9x (mobil).
 *   - Boshqa davlat -> FAQAT '+' (yoki '00') bilan yozilganda: '+7 903 157 11 24', '0048 789 706 619'.
 *     Davlat kodi ITU ro'yxatida bo'lishi shart; asosiy davlatlar uchun uzunlik aniq tekshiriladi (PHONE_LEN),
 *     qolganlari uchun umumiy (jami 10..15 raqam — 9 xonali bo'lmasin: u O'zbekiston lokal raqami bilan to'qnashadi).
 *     '+'siz uzun raqam (79031571124, 8 903 ...) — NOANIQ (Rossiya? xato terilgan O'zbekiston raqami?) -> yaroqsiz;
 *     «⚠️ Sifat» uni ko'rsatadi va '+' qo'shishni taklif qiladi.
 *
 * ⚠️ PHONE-CANON bloki AYNAN bir xil matn bilan 3 joyda: shu fayl, sb/auth-api.js (brauzer: ro'yxat/login),
 *    admin.html (Sifat/forma/xodim bog'lash). auth/phone.test.cjs bloklar bir xilligini va xatti-harakatni tekshiradi —
 *    o'zgartirsangiz, UCHALASIGA bir xil ko'chiring.
 */
/* PHONE-CANON:BEGIN — server/phone.cjs, sb/auth-api.js, admin.html: AYNAN bir xil (auth/phone.test.cjs tekshiradi) */
// Xalqaro telefon kodlari (ITU E.164) -> davlat (ISO 3166-1 alpha-2; Eskiz xalqaro SMS country_code ham shu).
var PHONE_CC = {
  '1': 'US', '7': 'RU',
  '20': 'EG', '27': 'ZA', '30': 'GR', '31': 'NL', '32': 'BE', '33': 'FR', '34': 'ES', '36': 'HU', '39': 'IT',
  '40': 'RO', '41': 'CH', '43': 'AT', '44': 'GB', '45': 'DK', '46': 'SE', '47': 'NO', '48': 'PL', '49': 'DE',
  '51': 'PE', '52': 'MX', '53': 'CU', '54': 'AR', '55': 'BR', '56': 'CL', '57': 'CO', '58': 'VE',
  '60': 'MY', '61': 'AU', '62': 'ID', '63': 'PH', '64': 'NZ', '65': 'SG', '66': 'TH',
  '81': 'JP', '82': 'KR', '84': 'VN', '86': 'CN',
  '90': 'TR', '91': 'IN', '92': 'PK', '93': 'AF', '94': 'LK', '95': 'MM', '98': 'IR',
  '211': 'SS', '212': 'MA', '213': 'DZ', '216': 'TN', '218': 'LY', '220': 'GM', '221': 'SN', '222': 'MR', '223': 'ML',
  '224': 'GN', '225': 'CI', '226': 'BF', '227': 'NE', '228': 'TG', '229': 'BJ', '230': 'MU', '231': 'LR', '232': 'SL',
  '233': 'GH', '234': 'NG', '235': 'TD', '236': 'CF', '237': 'CM', '238': 'CV', '239': 'ST', '240': 'GQ', '241': 'GA',
  '242': 'CG', '243': 'CD', '244': 'AO', '245': 'GW', '248': 'SC', '249': 'SD', '250': 'RW', '251': 'ET', '252': 'SO',
  '253': 'DJ', '254': 'KE', '255': 'TZ', '256': 'UG', '257': 'BI', '258': 'MZ', '260': 'ZM', '261': 'MG', '262': 'RE',
  '263': 'ZW', '264': 'NA', '265': 'MW', '266': 'LS', '267': 'BW', '268': 'SZ', '269': 'KM', '290': 'SH', '291': 'ER',
  '297': 'AW', '298': 'FO', '299': 'GL',
  '350': 'GI', '351': 'PT', '352': 'LU', '353': 'IE', '354': 'IS', '355': 'AL', '356': 'MT', '357': 'CY', '358': 'FI',
  '359': 'BG', '370': 'LT', '371': 'LV', '372': 'EE', '373': 'MD', '374': 'AM', '375': 'BY', '376': 'AD', '377': 'MC',
  '378': 'SM', '380': 'UA', '381': 'RS', '382': 'ME', '383': 'XK', '385': 'HR', '386': 'SI', '387': 'BA', '389': 'MK',
  '420': 'CZ', '421': 'SK', '423': 'LI',
  '500': 'FK', '501': 'BZ', '502': 'GT', '503': 'SV', '504': 'HN', '505': 'NI', '506': 'CR', '507': 'PA', '508': 'PM',
  '509': 'HT', '590': 'GP', '591': 'BO', '592': 'GY', '593': 'EC', '594': 'GF', '595': 'PY', '596': 'MQ', '597': 'SR',
  '598': 'UY', '599': 'CW',
  '670': 'TL', '672': 'NF', '673': 'BN', '674': 'NR', '675': 'PG', '676': 'TO', '677': 'SB', '678': 'VU', '679': 'FJ',
  '680': 'PW', '681': 'WF', '682': 'CK', '683': 'NU', '685': 'WS', '686': 'KI', '687': 'NC', '688': 'TV', '689': 'PF',
  '690': 'TK', '691': 'FM', '692': 'MH',
  '850': 'KP', '852': 'HK', '853': 'MO', '855': 'KH', '856': 'LA', '880': 'BD', '886': 'TW',
  '960': 'MV', '961': 'LB', '962': 'JO', '963': 'SY', '964': 'IQ', '965': 'KW', '966': 'SA', '967': 'YE', '968': 'OM',
  '970': 'PS', '971': 'AE', '972': 'IL', '973': 'BH', '974': 'QA', '975': 'BT', '976': 'MN', '977': 'NP',
  '992': 'TJ', '993': 'TM', '994': 'AZ', '995': 'GE', '996': 'KG', '998': 'UZ'
};
// Asosiy davlatlar: mobil raqamning JAMI uzunligi (davlat kodi bilan). Ro'yxatda yo'q davlat — umumiy qoida.
var PHONE_LEN = {
  '1': [11], '7': [11], '20': [12], '33': [11], '34': [11], '39': [11, 12], '44': [12], '48': [11], '49': [12, 13],
  '61': [11], '81': [12], '82': [11, 12], '86': [13], '90': [12], '91': [12], '92': [12],
  '370': [11], '371': [11], '372': [10, 11], '373': [11], '374': [11], '375': [12], '380': [12], '420': [12], '421': [12],
  '965': [11], '966': [12], '971': [12], '972': [12], '974': [11],
  '992': [12], '993': [11], '994': [12], '995': [12], '996': [12], '998': [12]
};
// Raqam boshidagi davlat kodi (eng uzuni: 3 -> 2 -> 1 raqam) yoki ''.
function phoneCc(d) {
  d = String(d == null ? '' : d);
  for (var n = 3; n >= 1; n--) {
    var c = d.slice(0, n);
    if (c.length === n && Object.prototype.hasOwnProperty.call(PHONE_CC, c)) return c;
  }
  return '';
}
// KANONIK raqam (faqat raqamlar, davlat kodi bilan) yoki '' (yaroqsiz). Qoidalar — fayl boshidagi izohda.
function phoneCanon(input) {
  var s = String(input == null ? '' : input).trim();
  var d = s.replace(/\D/g, '');
  var plus = /^[^0-9]*\+/.test(s);                 // '+' birinchi raqamdan OLDIN (masalan '+7 ...', '(+7) ...')
  if (d.slice(0, 2) === '00') { plus = true; d = d.slice(2); }   // 00 — xalqaro chiqish prefiksi (0048 ... = +48 ...)
  // Lokal O'zbekiston raqami — FAQAT '+'siz: '+7 903 157 11' (chala xorijiy, 9 raqam) jimgina O'zbekiston
  //   raqamiga (998790315711) aylanib, SMS begonaga ketmasin.
  if (!plus && d.length === 9) d = '998' + d;
  if (d.slice(0, 3) === '998') return (d.length === 12 && '235789'.indexOf(d.charAt(3)) >= 0) ? d : '';
  if (!plus || d.length > 15) return '';           // chet el raqami FAQAT '+' (yoki 00) bilan; E.164: ≤ 15 raqam
  var cc = phoneCc(d);
  if (!cc) return '';
  var lens = PHONE_LEN[cc];
  // Umumiy qoida: jami kamida 10 raqam — kanonik chet el raqami hech qachon 9 xonali bo'lmaydi (9 xonali = O'zbekiston
  //   lokal raqami; aks holda bazadagi '+'siz kanonik raqamni qayta o'qishda O'zbekiston raqamiga aylanib ketardi).
  if (lens ? lens.indexOf(d.length) < 0 : d.length < 10) return '';
  return d;
}
// Kanonik raqamning davlati (ISO): +7 6xx/7xx — Qozog'iston, qolgan +7 — Rossiya.
function phoneIso(canon) {
  var d = String(canon == null ? '' : canon);
  var cc = phoneCc(d);
  if (!cc) return '';
  if (cc === '7') return /^7[67]/.test(d) ? 'KZ' : 'RU';
  return PHONE_CC[cc];
}
// Milliy qism guruhlari: 3-3-2-2 (oxirgi guruh 3 bo'lishi mumkin) — faqat ko'rsatish uchun.
function phoneGroup(n) {
  n = String(n == null ? '' : n);
  var out = [], i = 0, k;
  for (k = 0; k < 2 && n.length - i > 4; k++) { out.push(n.slice(i, i + 3)); i += 3; }
  while (n.length - i > 3) { out.push(n.slice(i, i + 2)); i += 2; }
  if (i < n.length) out.push(n.slice(i));
  return out.join(' ');
}
// Ko'rsatish: +998 90 123 45 67 · +7 903 157 11 24. Kanonik bo'lmasa — o'zgarishsiz qaytadi.
function phonePretty(canon) {
  var raw = canon == null ? '' : String(canon);
  var d = raw.replace(/\D/g, '');
  if (d.length === 12 && d.slice(0, 3) === '998') return '+998 ' + d.slice(3, 5) + ' ' + d.slice(5, 8) + ' ' + d.slice(8, 10) + ' ' + d.slice(10);
  if (!d || phoneCanon('+' + d) !== d) return raw;
  var cc = phoneCc(d);
  return '+' + cc + ' ' + phoneGroup(d.slice(cc.length));
}
// Kiritish MASKASI (brauzer, jonli): '+'siz qisqa raqam — O'zbekiston ('+998 90 123 45 67');
//   '+' (yoki 00) bilan, yoki '+'siz 10+ raqam 998 bilan boshlanmasa — xorijiy ('+7 903 157 11 24').
//   Idempotent: maska natijasini qayta maskalash o'zgartirmaydi; yaroqli raqamni (phoneCanon) o'zgartirmaydi.
function phoneMask(raw) {
  var s = String(raw == null ? '' : raw);
  var d = s.replace(/\D/g, '');
  var plus = /^[^0-9]*\+/.test(s);
  if (d.slice(0, 2) === '00') { plus = true; d = d.slice(2); }
  else if (!plus && d === '0') return '0';         // '00' (xalqaro prefiks) yozilmoqda
  if (plus || d.length > 9) d = d.replace(/^0+/, '');   // xalqaro raqam: davlat kodi 0 bilan boshlanmaydi
  if (d.slice(0, 3) === '998' || (!plus && d.length <= 9)) {
    // '+'siz AYNAN 9 raqam — lokal raqam (998 bilan boshlansa ham: 99 812 34 56), phoneCanon bilan bir xil.
    if (d.slice(0, 3) === '998' && (plus || d.length !== 9)) d = d.slice(3);
    d = d.slice(0, 9);                             // operator(2) + raqam(7)
    var out = '+998';
    if (d.length) out += ' ' + d.slice(0, 2);
    if (d.length > 2) out += ' ' + d.slice(2, 5);
    if (d.length > 5) out += ' ' + d.slice(5, 7);
    if (d.length > 7) out += ' ' + d.slice(7, 9);
    return out;
  }
  d = d.slice(0, 15);
  if (!d) return '+';
  var cc = phoneCc(d);
  if (!cc || d.length <= cc.length) return '+' + d;
  return '+' + cc + ' ' + phoneGroup(d.slice(cc.length));
}
/* PHONE-CANON:END */

// Foydalanuvchi kiritgan raqam YOKI allaqachon KANONIK raqam (bazadagi users.phone, OTP ticket, sms_log.phone — faqat
//   raqamlar, '+'siz: chet el raqami '79031571124' phoneCanon'dan o'tmaydi, chunki '+' yo'q) -> kanonik yoki ''.
//   Faqat raqamlardan iborat satr uchun '+' bilan qayta tekshiriladi. ⚠️ Foydalanuvchi kiritgan XOM qiymat uchun emas
//   ('+'siz chet el raqami noaniq) — xom qiymat uchun phoneCanon.
function canonOf(x) {
  const s = String(x == null ? '' : x).trim();
  return phoneCanon(s) || (/^\d{10,15}$/.test(s) ? phoneCanon('+' + s) : '');
}
// SMS/OTP uchun: { canon, intl, iso, cc } yoki null (yaroqsiz). Kirish — kanonik raqam yoki kiritilgan raqam (canonOf).
function phoneInfo(input) {
  const canon = canonOf(input);
  if (!canon) return null;
  return { canon, intl: canon.slice(0, 3) !== '998', iso: phoneIso(canon), cc: phoneCc(canon) };
}

module.exports = { PHONE_CC, PHONE_LEN, phoneCc, phoneCanon, phoneIso, phoneGroup, phonePretty, phoneMask, canonOf, phoneInfo };
