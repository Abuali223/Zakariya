/* =====================================================================
 * name-match.js — ism-familiyani NORMALLASHTIRISH va SOLISHTIRISH (Click to'lovchi ismi ↔ o'quvchi ismi).
 *   Brauzer: admin.html «Biriktirish» oynasidagi «Ehtimol shu o'quvchi» takliflari.
 *   Server:  keyinchalik avtomatik biriktirish mantiqi — require('../sb/name-match.js').
 * BITTA fayl ikkala muhit uchun (UMD): Node'da module.exports, brauzerda import()/<script> -> globalThis.IqrorNameMatch.
 * Tashqi kutubxona yo'q. Bu modul HECH NARSANI o'zi biriktirmaydi — faqat ball hisoblaydi.
 * ===================================================================== */
(function (root, factory) {
  if (typeof module === 'object' && module && module.exports) module.exports = factory();
  else root.IqrorNameMatch = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // ---- O'zbek kirill -> lotin. 'е' so'z boshida, unli yoki ъ/ь dan keyin -> 'ye' (Турғунбоева -> turg'unboyeva) ----
  var CYR = { 'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'ё': 'yo', 'ж': 'j', 'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k',
    'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'x', 'ц': 'ts',
    'ч': 'ch', 'ш': 'sh', 'щ': 'sh', 'ъ': "'", 'ы': 'i', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya', 'ғ': "g'", 'қ': 'q',
    'ў': "o'", 'ҳ': 'h', 'і': 'i' };
  var YE_AFTER = 'аеёиоуўэюяъьыі';
  // Eski lotin / turkcha harflar (ba'zan shunday yoziladi)
  var LAT = { 'ş': 'sh', 'ç': 'ch', 'ğ': "g'", 'ö': "o'", 'ü': 'u', 'ı': 'i', 'â': 'a', 'é': 'e' };
  // Barcha apostrof turlari -> '  — ro'yxat bilan emas, Unicode toifasi bilan: modifikator harf/belgilar (ʻ ʼ ʹ ˊ ˋ ´ ` …),
  //   yakka tirnoqlar (‘ ’ ‚ ‛), ASCII ' va o'xshashlari (′ ‵ ＇ ꞌ ՚). BITTA manba (APC): to'lovchi matnini tozalash qoidalari
  //   ham aynan shu belgilarni «so'z harfi» deb biladi. Qo'shtirnoqlar (″ ham) va ko'rinmas belgilar — fixSeparators.
  var APC = "\\p{Lm}\\p{Sk}'\\u2018\\u2019\\u201A\\u201B\\u2032\\u2035\\uFF07\\uA78C\\u055A";
  var APOS = new RegExp('[' + APC + ']', 'gu');
  // « » ‹ › — doim so'zlarni ajratadi. “ ” „ ‟ " ＂ ″ va ko'rinmas belgi (\p{Cf}: ZWSP, yo'nalish belgilari, yumshoq tire…):
  //   so'z ICHIDA (harflar orasida) — apostrof / o'chiriladi («Turg”unboyeva», «Turg\u200Bunboyeva»); so'zlar ORASIDA (kichik
  //   harfdan keyin Katta harf, yoki so'z chetida) — bo'shliq («Turg'unboyeva“Xadicha”», «Xadicha\u200BTurg'unboyeva»).
  //   Ketma-ket ko'rinmas belgilar — bitta deb qaraladi. (Katta-kichik harf kerak: kichik harfga o'tkazishdan OLDIN ishlaydi.)
  var GUIL = '\u00AB\u00BB\u2039\u203A';
  var DQ = '\u201C\u201D\u201E\u201F"\uFF02\u2033';
  function isCf(c) { return /\p{Cf}/u.test(c); }
  function fixSeparators(s) {
    var out = '', ch = Array.from(s);
    for (var i = 0; i < ch.length; i++) {
      var c = ch[i], dq = DQ.indexOf(c) >= 0;
      if (GUIL.indexOf(c) >= 0) { out += ' '; continue; }
      if (!dq && !isCf(c)) { out += c; continue; }
      var j = i - 1, k = i + 1;
      while (j >= 0 && isCf(ch[j])) j--;
      while (k < ch.length && isCf(ch[k])) k++;
      var a = ch[j] || '', b = ch[k] || '';
      var inWord = /\p{L}/u.test(a) && /\p{L}/u.test(b) && !(/\p{Ll}/u.test(a) && /\p{Lu}/u.test(b));
      out += inWord ? (dq ? "'" : '') : ' ';
    }
    return out;
  }
  // Otasining ismi qo'shimchasi — u va undan OLDINGI so'z hisobga olinmaydi (... Rustam qizi / o'g'li)
  var PATRON = /^(qizi|kizi|o'g'li|og'li|o'gli|ogli|ug'li|ugli|o'gil|o'g'il)$/;
  // Ruscha otasining ismi (-ovich / -ovna / -ichna) — normallashtirilgan so'z oxiri
  var PATRONYMIC = /(vich|vna|ichna)$/;

  function translit(s) {
    var out = '';
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      var p = i ? s.charAt(i - 1) : '';
      if (c === 'е') out += (!p || !/[a-zа-яёғқўҳі]/.test(p) || YE_AFTER.indexOf(p) >= 0) ? 'ye' : 'e';
      else if (c === 'ҳ' && (p === 'с' || p === 'ц')) out += "'h";   // сҳ = s'h (Исҳоқ = Is'hoq), «ш» emas
      else if (Object.prototype.hasOwnProperty.call(CYR, c)) out += CYR[c];
      else if (Object.prototype.hasOwnProperty.call(LAT, c)) out += LAT[c];
      else out += c;
    }
    return out;
  }

  function normWord(w) {
    w = w.replace(/kh/g, 'x');                                              // kh (pasportdagi yozuv: Khadicha) = x
    w = w.replace(/([cs])'h/g, '$1x');                                      // s'h / c'h — alohida harflar (Is'hoq = Isxoq)
    w = w.replace(/([cs]?)h/g, function (m, p) { return p ? m : 'x'; });   // h -> x (Hadicha = Xadicha); ch/sh tegilmaydi
    w = w.replace(/yev/g, 'ev');                                            // yeva/yev/yevich -> eva/ev/evich
    w = w.replace(/o'/g, 'u');                                              // o' = u (O'dil / Udil)
    w = w.replace(/(.)\1+/g, '$1');                                         // takror harflar: hadichaa -> hadicha
    return w.replace(/^'+|'+$/g, '');
  }

  // 1-qadam: kichik harf, kirill -> lotin, apostroflar bitta (') belgiga, ortiqcha bo'shliqlar olib tashlangan.
  //   Турғунбоева Хадича -> turg'unboyeva xadicha. (Lotin harflaridagi diakritika — é, ñ, İ… — asos harfga.)
  function toLatin(name) {
    var s = translit(fixSeparators(String(name == null ? '' : name).slice(0, 500).normalize('NFC')).toLowerCase());
    return s.normalize('NFD').replace(/[\u0300-\u036F]/g, '').replace(APOS, "'").replace(/\s+/g, ' ').trim();
  }

  // Ismni solishtirish uchun yagona ko'rinishga keltiradi: toLatin + h->x, yev->ev, o'->u, takror harfsiz,
  //   «qizi/o'g'li» (va otasining ismi) olib tashlangan. So'zlar bitta bo'shliq bilan.
  function normalizeName(name) {
    var s = toLatin(name).replace(/[^a-z' ]+/g, ' ');
    var toks = s.split(/\s+/).filter(Boolean), kept = [];
    for (var i = 0; i < toks.length; i++) {
      var t = toks[i].replace(/^'+|'+$/g, '');
      if (!t) continue;
      if (PATRON.test(t)) { kept.pop(); continue; }
      kept.push(toks[i]);   // normWord chetdagi apostrofni o'zi olib tashlaydi — undan OLDIN «o'» -> u («O'.» bosh harfi = u)
    }
    return kept.map(normWord).filter(Boolean).join(' ');
  }

  // ---- To'lovchi matni («shovqinli») va o'quvchi ismi (toza yozuv) — ALOHIDA ishlanadi ----
  // To'lovchi matnidagi raqamli bo'laklar ism emas: hex o'quvchi kodi («3fa9c0b21de7»), raqamga YOPISHGAN qisqa bo'laklar —
  //   ID «IQ-0042» (raqam oldidagi 1–2 harf), sinf «5-A» / «11B» / «5«A»», «2026-yil» (raqam ortidagi 1–4 harf), raqamdan
  //   bo'shliq bilan ajralgan YAKKA harf («5 A», «2026 y.»), «No 5» / «N 5», «F.I.O.» yorlig'i. Sinf so'zi yonidagi YAKKA
  //   harf — sinf harfi («5-sinf B.», «A sinf», «5 кл. А», nuqta bilan ham). Apostrof — so'z harfi («IQ-0042 Ra'no» da «Ra»
  //   kesilmaydi); raqamdan keyin bo'shliq bilan yozilgan so'z («IQ-0042 Ali») — ism, tegilmaydi.
  var W = '\\p{L}\\p{M}' + APC;   // so'z belgilari: harf, diakritika, apostrof
  var SEP = '[\\s.,:;()\\-\\u2013\\u2014]';
  var CLASSW = '(?:sinf(?:i|da|ga|dan|idan|iga|ida)?|синф(?:и|да|га|дан|идан)?|класс[аеу]?|klass[aeu]?|кл|kl)';
  var HEX_CODE = /(^|[^\p{L}\p{M}\d])(?=[0-9a-f]*\d)[0-9a-f]{6,}(?![\p{L}\p{M}\d])/gu;
  var CLASS_AFTER = new RegExp('(^|[^' + W + '])(' + CLASSW + SEP + '+)(\\p{L})(?![' + W + '])', 'gu');
  var CLASS_BEFORE = new RegExp('(^|[^' + W + '])(\\p{L})(?=' + SEP + '+' + CLASSW + '(?![' + W + ']))', 'gu');
  // «No 5», «No.5», «No:5», «No-5», «Nº 5», «N° 5», «Nr. 5», «N 5» — raqam belgisi («N.» nuqta bilan — bosh harf: «Popov N. 5 класс», tegilmaydi)
  var NUM_SIGN = new RegExp('(^|[^' + W + '])(?:(?:no|nr)(?:[.:\\-]|\\u00BA|\\u00B0)?|n(?:[:\\-]|\\u00BA|\\u00B0)?)\\s*(?=\\d)', 'gu');
  // Hisob / hujjat yorlig'i (ism emas): «ИНН», «STIR», «л/с», «д/с», «р/с», «S/N», «a/c» — raqamdan oldin keladi
  var LABEL = new RegExp('(^|[^' + W + '])(?:инн|inn|стир|stir|[лдрldr]\\s*/\\s*[сcs]|s\\s*/\\s*n|a\\s*/\\s*c)(?![' + W + '])', 'gu');
  // «F.I.O.:», «Ф.И.Ш.» — yorliq (ism emas)
  var FIO = new RegExp('(^|[^' + W + '])(?:f\\.?\\s*i\\.?\\s*(?:o|sh)|ф\\.?\\s*и\\.?\\s*[ош])\\.?(?![' + W + '])', 'gu');
  var NEAR_DIGIT_BEFORE = new RegExp('(^|[^' + W + '])[\\p{L}\\p{M}]{1,2}(?=[-\\u2013.]?\\d)', 'gu');
  var NEAR_DIGIT_AFTER = new RegExp('(\\d+[-\\u2013\\u2014.]?["\\u00AB\\u201C]?)([' + W + ']{1,4})(?![' + W + '])', 'gu');
  var DIGIT_SPACE_LETTER = new RegExp('(\\d[-\\u2013\\u2014.]?\\s+[-\\u2013\\u2014.]?\\s*)(\\p{L})(?![' + W + '])', 'gu');   // «5 A», «5- A» («5-«A»» qo'shtirnoqdan keyin)
  // ... LEKIN koreyscha «O» familiyasi («5 O Viktoriya») va YOPISHGAN bosh harflar («5 A.S. Usmonov») — tegilmaydi; sinf raqami
  //   bo'la olmaydigan sondan (ID / 12 va undan katta: «IQ-0042. J. Karimov», «0042 - J.», «№ 42 - J. R.», «15. J.»), sanadan
  //   («15.10. J. R. Karimov») yoki raqamlangan ro'yxatdan («1. J. Karimov 2. B. Karimov»; matn boshidagi yakka «1.» — ketidan
  //   bo'shliqli bosh harf va ism kelsa: «1. J. R. Karimov») keyingi NUQTALI harf — bosh harf; sinf raqamidan (1–11) keyin tire /
  //   nuqta bilan («5 - A.», «5- A.», «5. A. Karimov»; «5- J. R.» ham) — sinf harfi. Yil qisqartmasi («2026 y.», «2026 г.»,
  //   «2026 й.») — doim olib tashlanadi (ketidan bosh harf kelsa ham).
  function digitSpaceLetter(m, pre, letter, off, str) {
    var after = str.slice(off + m.length), head = str.slice(0, off + 1), num = (head.match(/\d+$/) || [''])[0];
    if (/^[yгй]$/.test(letter) && /(^|\D)(19|20)\d\d$/.test(head)) return pre + ' ';
    var list = (str.match(/(^|[^\d])\d{1,2}\.\s/g) || []).length >= 2, dotP = /^\d\.\s/.test(pre);
    var noCls = num.length >= 3 || +num > 11 || /\d[.\/]\d{1,2}$/.test(head)
      || (dotP && (list || (/^\s*1$/.test(head) && /^\.\s+\p{L}{1,2}\.\s*\p{L}{3}/u.test(after))));
    var dotted = after.charAt(0) === '.' && /[-–—.]/.test(pre) && noCls;
    return letter === 'o' || letter === 'о' || /^\.\p{L}\./u.test(after) || dotted ? m : pre + ' ';
  }
  // Uzun raqamga (ID, telefon: 3+ raqam) yopishgan 3+ harfli so'z izoh so'zi bo'lmasa — ism («IQ-0042-Ali», «998901112233Ali»);
  //   qisqa raqamdan keyingisi (sinf «5-A», «11B») va izoh so'zi («2026-yil», «1500000so'm») — olib tashlanadi.
  function nearDigitAfter(m, pre, word) {
    return (/\d{3}/.test(pre) && word.replace(/'/g, '').length >= 3 && !FILLER[normalizeName(word)]) ? m : pre + ' ';
  }
  // Sinf so'zi yonidagi YAKKA harf — sinf harfi, LEKIN: koreyscha «O» familiyasi; ketidan YOPISHGAN nuqtali bosh harf kelsa
  //   («5 класс Ж.Р. Каримов»; bo'shliq bilan «5-sinf A. J. Karimov» — A sinf harfi, J. bosh harf); sinf harfi allaqachon yozilgan
  //   bo'lsa («5-A sinf J.R.», «A sinf, B.»); sinf so'zidan OLDINGI nuqtali harf («Karimov J. sinf 5-A», «Novikova V., sinf») —
  //   bosh harf, tegilmaydi.
  function classLetterAfter(m, pre, cls, letter, off, str) {
    if (letter === 'o' || letter === 'о') return m;
    var after = str.slice(off + m.length), before = str.slice(0, off + pre.length);
    if (/^\.\p{L}\./u.test(after)) return m;
    if (/\d\s*[-\u2013\u2014.]?\s*\p{L}\s*$/u.test(before) || new RegExp('(^|[^' + W + '])\\p{L}\\s*$', 'u').test(before)) return m;
    return pre + cls + ' ';
  }
  function classLetterBefore(m, pre, letter, off, str) {
    if (letter === 'o' || letter === 'о') return m;
    if (str.charAt(off + m.length) === '.' && !/\d\s*[-\u2013\u2014]?\s*$/.test(str.slice(0, off + pre.length))) return m;
    return pre + ' ';
  }
  //   Raqamdan keyingi yakka harf (DIGIT_SPACE_LETTER) raqamga yopishgan sinf harfi («5-A», «5A») olib tashlanishidan OLDIN
  //   qidiriladi: aks holda «5-A J. Karimov» → «5- J.» bo'lib, J. ham sinf harfi deb kesilardi.
  function payerClean(text) {
    return fixSeparators(String(text == null ? '' : text).slice(0, 500).normalize('NFC')).toLowerCase()
      .replace(HEX_CODE, '$1 ').replace(FIO, '$1 ').replace(LABEL, '$1 ').replace(CLASS_AFTER, classLetterAfter)
      .replace(CLASS_BEFORE, classLetterBefore).replace(NUM_SIGN, '$1 ')
      .replace(NEAR_DIGIT_BEFORE, '$1 ').replace(DIGIT_SPACE_LETTER, digitSpaceLetter).replace(NEAR_DIGIT_AFTER, nearDigitAfter);
  }

  // To'lov izohidagi umumiy so'zlar (lotin VA kirill yozuvi — normalizeName orqali bir xil ko'rinishga keltiriladi).
  //   Ular to'lovchi matnidan faqat o'quvchi ismida YO'Q bo'lsa tashlanadi («Avgust», «May» — haqiqiy ism ham bo'lishi mumkin).
  //   Bosh harf bo'la oladigan yakka harflar (и, в, с, у, о…) bu ro'yxatda YO'Q; kirill «сын» ham yo'q (koreyscha familiya Син).
  var FILLER = {};
  ("uchun to'lov tolov to'lovi tolovi to'lovni to'lash to'lovlar to'lovlari oy oyi oyga oyiga oylik oyligi sinf sinfi sinfda "
    + "sinfidan sinfida sinfga sinfiga klass klassa maktab maktabi shkola o'quvchi oquvchi o'quvchisi oquvchisi farzand "
    + "farzandi farzandim farzandimiz farzandingiz bola bolam bolasi bolamiz bolangiz qizim qizimiz qizingiz o'g'lim og'lim "
    + "o'g'limiz o'g'lingiz "
    + "ukam akam opam singlim nevaram jiyanim kontrakt kontrakti shartnoma shartnomasi summa summasi pul puli dars darsi kurs "
    + "kursi id iq raqam raqami kod kodi nomer tel telefon ism ismi familiya familiyasi fio ota ona otasi onasi dadasi oyisi "
    + "akasi opasi ukasi singlisi va bilan ham bu ul ta chi yanvar fevral mart aprel may iyun iyul avgust sentabr sentyabr "
    + "oktabr oktyabr noyabr dekabr yanv fev apr avg sent okt noy dek yil yili yilgi kun kuni o'qish oqish o'qishi o'qishga "
    + "haqi ta'lim talim qarz qarzi qarzlar avans ovqat ovqatlanish tushlik nonushta transport avtobus servis kitob kitoblar "
    + "darslik darsliklar forma kiyim chorak choragi semestr so'm so'mlik som sum ming mln mlrd uzs oplata za uchenik uchenika "
    + "uchenitsa mesyats obuchenie click payme uzum iqror iqro akademiya academy "
    + "учун тўлов тулов тўлови тўловлар ой ойи ойлик синф синфи мактаб ўқувчи ўқувчиси фарзанд фарзандим бола болам қизим "
    + "ўғлим укам акам опам синглим контракт шартнома сумма пул дарс курс ота она отаси онаси ва билан январь февраль март "
    + "апрель май июнь июль август сентябрь октябрь ноябрь декабрь йил йили кун куни ўқиш ўқишга ҳақи таълим қарз аванс овқат "
    + "тушлик транспорт китоб сўм сум минг млн оплата за на по до от из во со обучение обучения учеба учёба учебу ученик "
    + "ученика ученица ученицы школа школы класс класса классе классу кл четверть четверти месяц месяца год года году "
    + "января февраля марта апреля мая июня июля августа сентября октября ноября декабря январе феврале марте апреле мае июне "
    + "июле августе сентябре октябре ноябре декабре янв фев апр авг сен сент окт ноя нояб дек тел телефон номер тыс руб "
    + "питание питания обед обеды завтрак "
    + "автобус книги учебники форма формы сына сынок сыну сыночка ребенка ребёнка ребенок ребёнок дети детей внук внука "
    + "внучка внучки внучку племянника племянницы дочь дочка доча дочери дочки дочку дочке "
    // to'lov / to'lovchi so'zlari (familiyadan OLDIN kelib, bosh harfni otasining ismi deb o'qitardi), manzil va yorliq bo'laklari
    + "платеж платёж платежа перевод перевода payment pay paid student students talaba talabasi o'quvchimiz uzcard visa "
    + "karta kartadan kartasi kartaga card orqali карта карты карте картой карту мама мамы папа папы бабушка дедушка buvi buvisi "
    + "bobo bobosi onam otam oyim dadam "
    + "guruh guruhi guruhga группа группы it med kv uy ga da bn кв hamda and for of akademiyasi dada отец отца "
    + "vi vii viii ix xi xii")
    .split(' ').forEach(function (w) { var n = normalizeName(w); if (n) FILLER[n] = 1; });
  // ISM bo'la oladigan izoh so'zlari (SOFT): «мая» = Майя / Maya, «марта» = Марта, «августа» = Августа; koreyscha familiya
  //   bo'la oladigan «на», «до», «со» (Na, Do, So). Izoh so'zlari sanog'iga (comment) kirmaydi; ismda bo'lsa — ism o'rni bo'sh
  //   bo'lsa ism sifatida qoladi; ismda yo'q, lekin ism O'RNIDA bo'lsa — boshqa ism yozilgan (payerTokens: softMiss / loose2).
  //   «сына» — izoh so'zi (Сина ismi kam, «за сына» esa juda ko'p).
  var SOFT = {};
  ("мая марта августа на до со").split(' ').forEach(function (w) { var n = normalizeName(w); if (n) SOFT[n] = n.length <= 2 ? 2 : 1; });
  // Ota so'zi: undan keyingi YAKKA ism — otasining ismi («otasi Bahodir», «(dadasi Bahodir)», «отец Рустам,»).
  var PARENT = {};
  ("ota otasi dada dadasi отец отца папа папы").split(' ').forEach(function (w) { var n = normalizeName(w); if (n) PARENT[n] = 1; });
  // Bog'lovchi: undan keyingi so'zlar — boshqa odam (aka-uka) ismi: «Karimova Malika va Karimov Ali», «… и Каримов Али».
  var CONJ = { va: 1, bilan: 1, hamda: 1, i: 1, and: 1 };
  // Ona so'zi: undan keyingi so'zlar — onasining ismi / familiyasi («Karimov Jasur onasi Rahimova Dilnoza») — o'quvchi otasining
  //   ismi haqida dalil emas (evidence).
  var MOTHER = {};
  ("ona onasi oyisi onam oyim mama mamasi мама мамы мать матери онаси ойиси").split(' ').forEach(function (w) { var n = normalizeName(w); if (n) MOTHER[n] = 1; });
  // «Humo» — qiz ismi (Хумо) ham, karta tizimi ham: karta so'zi yonida («Humo karta», «karta Humo», «Humo/Uzcard», «HUMO|UZCARD»,
  //   «Перевод с карты HUMO»; orada vergul / qavs bo'lmasa) — izoh; boshqa joyda — ism («Karimova Humo», «Humo uchun», «Valiyeva
  //   Humo R.», «Karimova Humo click orqali» — click / orqali yonida ham).
  var CARD = { xumo: 1 }, CARDCTX = {}, CARD_SEP = /[,;()\[\]{}\r\n]/;   // «Humo/Uzcard», «Humo|Uzcard», «Humo-karta» — yonma-yon
  ("karta kartadan kartasi kartaga kartaning card uzcard visa mastercard перевод перевода карта карты карте картой карту")
    .split(' ').forEach(function (w) { var n = normalizeName(w); if (n) CARDCTX[n] = 1; });
  // Manzil: shahar / tuman nomlari va manzil so'zlari — izoh so'zi (ism ham bo'la oladigan nomlar — Navoiy, Bektemir, Guliston,
  //   Nurafshon — ro'yxatda yo'q). Ularning yonidagi qisqartma (sh., t., q., г.) — bosh harf emas: joy nomidan KEYIN — doim
  //   («Toshkent sh.», «Chilonzor t.»); OLDIN — matn boshida, izoh so'zidan yoki to'liq ismdan keyin («г. Ташкент», «Karimov
  //   Jasur t. Chilonzor»); bitta familiyadan keyin esa bosh harf («Karimov Sh. Toshkent», «Каримов Г. Ташкент»).
  var TOPO = {}, ADDR = { sh: 1, t: 1, q: 1, g: 1, tum: 1, vil: 1, obl: 1 };
  ("toshkent tashkent chilonzor yunusobod yunusabad mirobod sergeli yashnobod olmazor uchtepa shayxontohur yakkasaroy yangihayot "
    + "samarqand samarkand buxoro buxara andijon namangan farg'ona fargona qo'qon qarshi jizzax termiz urganch nukus xiva chirchiq "
    + "angren olmaliq bekobod zangiota qibray denov денов денау "
    + "тошкент ташкент чилонзор чиланзар юнусобод юнусабад миробод мирабад сергели яшнобод олмазор алмазар учтепа яккасарой "
    + "самарқанд самарканд бухоро бухара андижон андижан наманган фарғона фергана қарши карши жиззах термиз урганч нукус "
    + "чирчиқ чирчик ангрен олмалиқ алмалык")
    .split(' ').forEach(function (w) { var n = normalizeName(w); if (n) { TOPO[n] = 1; FILLER[n] = 1; } });
  ("shahar shahri tuman tumani viloyat viloyati mahalla mahallasi ko'cha ko'chasi xonadon город района район область улица "
    + "дом махалля шаҳар туман вилоят маҳалла кўча")
    .split(' ').forEach(function (w) { var n = normalizeName(w); if (n) FILLER[n] = 1; });

  // To'lovchi matni bir marta tahlil qilinadi — so'zlar TARTIB bilan: { w, f (izoh so'zi), soft (ism bo'la oladigan izoh so'zi),
  //   ini (aniq bosh harf tartibi: 1, 2…), role, seg (bo'lak), bnd / dig (oldida chegara / raqam bor) }.
  //   Aniq BOSH HARF — NUQTA bilan yozilgan 1–2 harf: «X.», «J.», «Sh.», «Ш.», «O'.», «Ў.», yopishgan «J.O.» / «Ж.О.» ham; bosh
  //   harfdan keyingi nuqtasiz harf ham — yopishgan («М.А», «J.R Karimov») yoki bo'shliq bilan («М. А») bo'lak oxirida / ism
  //   oldida (raqam oldida emas: «Karimov J. в 5 классе»). Nuqtasiz yakka harf bosh harf EMAS. comment — 2+ izoh so'zi («Avgust
  //   oyi uchun»: bunday matnda oy nomi ism emas; ism bo'la oladigan «мая», «на» sanalmaydi). patr — to'lovchi otasining ismini
  //   (-ovich/-ovna) yozgan; fathers — «… Bahodir o'g'li», «otasi Bahodir», «(dadasi Bahodir)» dagi otasining ismi (ism so'zlari
  //   qatoriga kirmaydi). Bo'lak (seg) — vergul, «;», «/», «|», qavs, bo'shliqli tire («Karimov Jasur - Rahimova Dilnoza»; so'z
  //   ichidagi «Abdul-Aziz», raqamga yopishgan «5-A», «IQ-0042», «2026-yil» qoldig'i va bosh harf oldidagi «Jasur - R.» emas) yoki
  //   bog'lovchi («va», «и», «bilan») bilan ajralgan qism. one — bo'shliq bilan yozilgan nuqtasiz yakka harflar soni («Ж К»).
  var BND = /[,;\/|()\[\]{}\r\n]/, DASH = /\s[-–—]|[-–—]\s/, DIGIT_DASH = /\d[-–—]+|[-–—]+\d/g;
  function payerInfo(text) {
    var lat = toLatin(payerClean(text)), re = /[a-z']+/g, m, raw = [], pop = [], gap = '', end = 0, i, t;
    while ((m = re.exec(lat))) {
      gap += lat.slice(end, m.index); end = m.index + m[0].length;
      var core = m[0].replace(/^'+|'+$/g, '');
      if (!core) { gap += m[0]; continue; }
      if (PATRON.test(core)) { var pp = raw.pop(); if (pp) pop.push(pp.s); gap = (pp ? pp.gap : '') + gap + ' '; continue; }
      raw.push({ s: m[0], gap: gap, dot: core.length <= 2 && lat.charAt(end) === '.' });
      gap = '';
    }
    var ws = [], carry = '';
    for (i = 0; i < raw.length; i++) {
      var x = normWord(raw[i].s);
      if (x) { ws.push({ w: x, dot: raw[i].dot, gap: carry + raw[i].gap }); carry = ''; } else carry += raw[i].gap + ' ';
    }
    var tail = carry + gap + lat.slice(end), toks = [], nIni = 0, nf = 0, one = 0, patr = false;
    var isNameW = function (k) { return k >= 0 && !FILLER[ws[k].w] && ws[k].w.length > 2; };
    for (i = 0; i < ws.length; i++) {
      var w = ws[i].w, g = ws[i].gap, pv = toks[i - 1], nx = ws[i + 1], after = nx ? nx.gap : tail;
      var f = !!FILLER[w] || (!!CARD[w] && ((i > 0 && !!CARDCTX[ws[i - 1].w] && !CARD_SEP.test(g)) || (!!nx && !!CARDCTX[nx.w] && !CARD_SEP.test(nx.gap))))
        || (!!ADDR[w] && ((i > 0 && !!TOPO[ws[i - 1].w]) || (!!nx && !!TOPO[nx.w]
        && (i === 0 || !!FILLER[ws[i - 1].w] || ((isNameW(i - 1) || (!!pv && !!pv.ini)) && isNameW(i - 2))))));
      var dot = ws[i].dot || (!f && w.length <= 2 && !!pv && !!pv.ini && /^\.\s*$/.test(g)
        && (g === '.' || (!/\d/.test(after) && (!nx || BND.test(after) || (nx.w.length > 2 && !FILLER[nx.w])))));
      var ini = (!f && dot && w.length <= 2) ? ++nIni : 0, soft = (f && SOFT[w]) || 0;
      if (f && !soft) nf++;
      else if (!f && w.length > 2 && PATRONYMIC.test(w)) patr = true;
      if (!f && !ini && w.length === 1 && w !== 'o' && /^\s*$/.test(g)) one++;
      toks.push({ w: w, f: f, soft: soft, ini: ini, bnd: BND.test(g) || (!ini && DASH.test(g.replace(DIGIT_DASH, ' '))), dig: /\d/.test(g), date: /(^|\D)\d{1,2}[-–—.]?\s*$/.test(g) });
    }
    // Bosh harf roli: otasining ismi bosh harfi (2) — shu bo'lakda boshqa bosh harfdan keyin («J.R.», «J. R.») yoki ketma-ket ikki
    //   ism so'zidan keyin («Karimov Jasur R.», «Li Viktoriya S.»; byW — yozuvga qarab 1 bo'lishi mumkin, payerTokens);
    //   qolganlari — familiya/ism bosh harfi (1): «Karimov J.», «Jo'rayeva G.; 1-chorak», «Karimova Malika, Karimov J.».
    var nameW = function (k) { var y = toks[k]; return !!y && !y.f && !y.ini && (y.w.length >= 2 || y.w === 'o'); };
    for (i = 0; i < toks.length; i++) if ((t = toks[i]).ini) {
      if (i > 0 && toks[i - 1].ini && !t.bnd) t.role = 2;
      else if (nameW(i - 1) && nameW(i - 2) && !t.bnd && !toks[i - 1].bnd) { t.role = 2; t.byW = true; }
      else t.role = 1;
    }
    // Otasining ismi: «… o'g'li / qizi» oldidagi so'z va ota so'zidan keyingi YAKKA ism (bo'lak oxirida): «otasi Bahodir, …»
    var fathers = [];
    pop.forEach(function (s) { var v = normWord(s); if (v && !FILLER[v]) fathers.push(v); });
    for (i = 0; i + 1 < toks.length; i++) {
      var y = toks[i + 1];
      if (PARENT[toks[i].w] && !toks[i].ini && !y.f && !y.ini && y.w.length > 2 && !y.bnd && !y.dig && !PATRONYMIC.test(y.w)
        && (i + 2 === toks.length || toks[i + 2].bnd)) { y.father = true; fathers.push(y.w); }
    }
    var seg = 0;
    for (i = 0; i < toks.length; i++) { if (toks[i].bnd) seg++; toks[i].seg = seg; if (CONJ[toks[i].w] && !toks[i].ini) seg++; }
    // Ism bo'la oladigan izoh so'zi ism O'RNIDA (np): «На Виктория …» — ism oldida, izoh so'zidan keyin emas («Оплата на …»,
    //   «… на октябрь» — yo'q); «Майя», «Petrova Mayya uchun» — ism yonida yoki matnda izoh so'zi yo'q (sanada emas: «до 1 мая»).
    //   wn — hisobga olinmagan qisqa so'z ism sifatida yozilgan (ikki izoh so'zi orasida emas: «сентябрь и октябрь»).
    var nb = function (k) { var v = toks[k]; return !!v && !v.f && (v.w.length >= 2 || v.w === 'o' || !!v.ini); };
    var hard = function (k) { var v = toks[k]; return !!v && v.f && !v.soft; };
    for (i = 0; i < toks.length; i++) {
      t = toks[i];
      var nOK = nb(i + 1) && !toks[i + 1].bnd && !toks[i + 1].dig;
      if (t.soft) t.np = t.soft === 2 ? nOK && (i === 0 || t.bnd || t.dig || nb(i - 1)) : !t.date && ((nb(i - 1) && !t.bnd) || nOK || !nf);
      t.wn = !(hard(i - 1) && hard(i + 1));
    }
    return { toks: toks, comment: nf >= 2, nf: nf, one: one, patr: patr, fathers: fathers };
  }
  // O'quvchi ismi (R — so'zlari) bilan solishtirish uchun to'lovchi so'zlari (ko'pi bilan 5 ta, tozalashdan KEYIN): P — so'zlar,
  //   PI — roli (0 — so'z, 1/2 — bosh harf, 3 — otasining ismi: faqat yozuvdagi otasining ismiga juftlanadi), PX — info.toks
  //   dagi o'rni, fate — har so'z taqdiri ('P' — P da, 'd' — tashlangan 2-bosh harf, 'l' — hisobga olinmagan qisqa so'z, 'f' — izoh).
  //   Izoh so'zi ismda bo'lsa — ism o'rni bo'sh bo'lsa qoladi (to'lovchining ism so'zlari yozuvdagilardan kam; otasining ismi
  //   sanalmaydi), izoh matnida («Petrova Mayya oktyabr uchun») — boshqa so'z ham shu ismga mos kelsa: «Avgust oyi uchun to'lov» —
  //   yo'q; «Karimov Jasur avgust uchun» ↔ Karimov Avgust — ism o'rni band (avgust — oy nomi).
  //   Ism o'rni yana — so'z yonida (shu bo'lakda) yozuvdagi BOSHQA so'zga mos so'z bo'lsa va uning narigi yonida yozuvga mos
  //   kelmaydigan ism so'zi / boshqa harfli ism bosh harfi bo'lmasa (slotFree: «Petrova Mayya Guliston», «Na Viktoriya S.»).
  //   Bosh harf roli yozuvga qarab: ikki so'zdan keyingi bosh harf («Guliston Karimov J.») — oldingi so'z yozuvdagi FAMILIYAGA
  //   (birinchi so'z) mos (≥ 0.8), undan oldingisi hech biriga mos emas (< 0.7) bo'lsa — familiya/ism bosh harfi (1), lekin ball
  //   ≤ 64% (down, ⚠️): undan oldingi so'z boshqa bolaning ismi ham bo'lishi mumkin («Jasur Karimov R.» ↔ Karimov Rustam); «Usmonov
  //   Bekzod A.» ↔ Aliyev Bekzod — yo'q (A. — otasining ismi, adashning familiyasi emas). 1–2 harfli so'z — ismdagi so'zga aynan teng bo'lsa yoki aniq
  //   bosh harf bo'lsa: familiya/ism bosh harfi doim, otasining ismi bosh harfi — faqat 3+ so'zli yozuvda (opt.drop2 — hech qachon).
  //   Qolganlari (nuqtasiz, ismda yo'q — «Ли», «O», «и») hisobga olinmaydi, lekin sanaladi: loose — hammasi, loose2 — 2 harfli,
  //   «o» va ism o'rnidagi «На» / «До» / «Со» (koreyscha familiya bo'la oladiganlar). softMiss — ismda yo'q «Майя» / «Марта» ism
  //   o'rnida (boshqa ism yozilgan). wn — hisobga olinmagan so'z ism sifatida yozilgan («Ли», «Ж К»). opt.fat — P ga qo'shiladigan
  //   otasining ismlari (3-rol). R yo'q (null) — faqat ism so'zlari.
  function hasPat(R) { return R.length >= 3 && PATRONYMIC.test(R[R.length - 1]); }
  function bestSim(w, R, skip) {
    for (var j = 0, b = 0; j < R.length; j++) if (R[j] !== skip) b = Math.max(b, w === R[j] ? 1 : (w.length <= 2 || R[j].length <= 2) ? 0 : wordSim(w, R[j]));
    return b;
  }
  function payerTokens(info, R, opt) {
    opt = opt || {};
    var toks = info.toks, n = toks.length, P = [], PI = [], PX = [], fate = [], i, t, np = 0;
    var loose = 0, loose2 = 0, softMiss = false, wn = false, down = false, big = !!R && R.length >= 3;
    var inR = function (w) { return !!R && R.indexOf(w) >= 0; };
    var role = function (k) {
      var y = toks[k];
      return y.byW && R && bestSim(toks[k - 1].w, R.slice(0, 1)) >= 0.8 && bestSim(toks[k - 2].w, R) < 0.7 ? 1 : y.role || 0;
    };
    for (i = 0; i < n; i++) {
      t = toks[i];
      if (t.father) fate[i] = '';
      else if (t.f) fate[i] = 'f';
      else if (t.w.length > 2) fate[i] = 'P';
      else { var ro = t.ini ? role(i) : 0; fate[i] = inR(t.w) || ro === 1 || (ro === 2 && big && !opt.drop2) ? 'P' : t.ini ? 'd' : 'l'; }
      if (fate[i] === 'P' && !(t.w.length > 2 && PATRONYMIC.test(t.w))) np++;
    }
    var rc = R ? R.length - (hasPat(R) ? 1 : 0) : 0;
    var corrob = function (k) {
      for (var q = 0; q < n; q++) if (q !== k && fate[q] === 'P' && bestSim(toks[q].w, R, toks[k].w) >= 0.8) return true;
      return false;
    };
    var slotFree = function (k) {
      var j = R.indexOf(toks[k].w);
      if (toks[k].soft && !toks[k].np) return false;   // «до 15 октября», «Оплата на …» — ism o'rnida emas
      for (var d = -1; d <= 1; d += 2) {
        var a = k + d, b = a + d, y = toks[b], z = toks[b + d], mt = false, q;
        if (a < 0 || a >= n || fate[a] !== 'P' || toks[a].seg !== toks[k].seg) continue;
        for (q = 0; q < R.length; q++) if (q !== j && R[q] !== toks[k].w && (toks[a].w === R[q] || (toks[a].w.length > 2 && R[q].length > 2 && wordSim(toks[a].w, R[q]) >= 0.8))) mt = true;
        if (!mt) continue;
        //   Ism o'rni band: ism o'rniga — har qanday bosh harf («J.R. Karimov avgust», «May Karimov J.») yoki yozuvga mos kelmaydigan
        //   ism so'zi («Avgust Karimov Jasur»; familiyadan OLDINGI so'z o'zi boshqa to'liq ismning oxiri bo'lsa — yo'q: «Nazarova
        //   Zulfiya Lebedev Avgust»); familiya o'rniga — yozuvda yo'q 2 harfli so'z («Li Mariya до …» ↔ Do Mariya).
        if (y && y.seg === toks[a].seg) {
          if (y.ini) { if (j > 0) continue; }
          else if (fate[b] === 'P' && y.w.length > 2 && !PATRONYMIC.test(y.w) && bestSim(y.w, R) < 0.8
            && !(d < 0 && z && z.seg === y.seg && fate[b + d] === 'P' && !z.ini && z.w.length > 2 && !PATRONYMIC.test(z.w))) continue;
          else if (j === 0 && (fate[b] === 'P' || fate[b] === 'l') && y.w.length <= 2 && R.indexOf(y.w) < 0) continue;
        }
        return true;
      }
      return false;
    };
    for (i = 0; i < n; i++) if (fate[i] === 'f') {
      t = toks[i];
      if (inR(t.w)) { if ((np < rc && (!info.comment || corrob(i))) || slotFree(i)) { fate[i] = 'P'; np++; } }
      else if (t.soft && t.np) { if (t.soft === 2) { loose++; loose2++; wn = true; } else softMiss = true; }
    }
    for (i = 0; i < n; i++) {
      t = toks[i];
      if (fate[i] === 'P') { if (P.length < 5) { var pr = t.ini ? role(i) : 0; P.push(t.w); PI.push(pr); PX.push(i); if (t.byW && pr === 1) down = true; } }
      else if (fate[i] === 'l') {
        loose++;
        if (t.w.length === 2 || t.w === 'o') { loose2++; if (t.wn) wn = true; } else if (info.one >= 2 && !info.nf) wn = true;
      }
    }
    (opt.fat || []).forEach(function (w) { P.push(w); PI.push(3); PX.push(-1); });
    return { P: P, PI: PI, PX: PX, fate: fate, loose: loose, loose2: loose2, softMiss: softMiss, wn: wn, down: down };
  }
  // O'quvchi ismi — toza yozuv: hech narsa tashlanmaydi (bitta harfli koreyscha familiya «O», «Avgust» ismi ham so'z).
  function recordTokens(name) { return normalizeName(name).split(' ').filter(Boolean).slice(0, 5); }
  // To'lovchi matnidagi ism so'zlari (izoh so'zlari, raqamli bo'laklar va nuqtasiz yakka harflarsiz).
  //   record berilsa — shu o'quvchi ismi bilan solishtirishda hisobga olinadigan so'zlar (nameSimilarity bilan BIR XIL qoida:
  //   «Avgust» — Karimov Avgust uchun ism, boshqa o'quvchi uchun izoh so'zi).
  function nameTokens(text, record) { return payerTokens(payerInfo(text), record == null ? null : recordTokens(record)).P; }
  // To'lovchi shu o'quvchi uchun ISM yozganmi (ogohlantirish kerakmi): ism so'zi, ism o'rnidagi «Майя» / «На», yoki ism sifatida
  //   yozilgan qisqa so'z («Ли», «Ж К», «О» — ism yozilgan, faqat boshqa o'quvchiniki bo'lishi mumkin). Faqat izoh / raqam /
  //   yorliq («л/с 0042», «Оплата за сентябрь и октябрь», «IT kursi uchun») — yo'q.
  function wroteName(text, record) {
    var t = payerTokens(payerInfo(text), record == null ? null : recordTokens(record));
    return t.P.length > 0 || t.softMiss || t.wn;
  }

  // Levenshtein masofasi (qo'shish/o'chirish/almashtirish = 1), ikki qatorli dinamik dasturlash.
  //   subCost(x, y) — ixtiyoriy: almashtirish narxi 0..1 (berilmasa — klassik Levenshtein).
  function levenshtein(a, b, subCost) {
    a = String(a); b = String(b);
    if (a === b) return 0;
    if (!a.length) return b.length;
    if (!b.length) return a.length;
    var prev = new Array(b.length + 1), cur = new Array(b.length + 1), i, j;
    for (j = 0; j <= b.length; j++) prev[j] = j;
    for (i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (j = 1; j <= b.length; j++) {
        var x = a.charAt(i - 1), y = b.charAt(j - 1), cost = x === y ? 0 : (subCost ? subCost(x, y) : 1);
        cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
      }
      var t = prev; prev = cur; cur = t;
    }
    return prev[b.length];
  }
  // o <-> u yarim narx: «o'» apostrofsiz yozilsa (O'tkir -> Otkir) yoki o/u adashtirilsa (Odil / Udil) — kichik farq.
  function nameSub(x, y) { return (x === 'o' && y === 'u') || (x === 'u' && y === 'o') ? 0.5 : 1; }
  // Qisqa shakl: Jasur = Jasurbek, Malika = Malikaxon, Ozoda = Ozodajon (qo'shimcha tushib qolgan) — kuchli o'xshashlik.
  var SHORT_SUFFIX = /^(bek|xon|jon)$/;
  // So'z o'xshashligi 0..1 = 1 - Levenshtein / uzunroq so'z uzunligi
  function wordSim(a, b) {
    var m = Math.max(a.length, b.length);
    if (!m) return 1;
    var s = 1 - levenshtein(a, b, nameSub) / m, sh = a.length <= b.length ? a : b, lg = sh === a ? b : a;
    if (sh.length >= 3 && lg.indexOf(sh) === 0 && SHORT_SUFFIX.test(lg.slice(sh.length))) s = Math.max(s, 0.9);
    return s;
  }
  // To'lovchi NUQTA bilan yozgan QISQA so'z (1–2 harf: «X.», «J.», «Sh.», «Ш.» → sh, «Ю.» → yu) — BOSH HARF sifatida tekshiriladi:
  //   o'quvchi so'zi shu harf(lar) bilan boshlansa — o'rtacha dalil (0.75), boshqa harf bilan boshlansa — ZID (0): «Karimov J.»
  //   Karimov Jasur'ga mos, Karimov Bekzod'ga emas. Aynan teng qisqa so'z (koreyscha «Li», «O») — to'liq mos.
  //   «O.» / «Yo.» — O' (= u) bilan ham (O'tkir, Yo'ldosh); «E.»/«Е.» — e va ye bilan; «Y.» — Ye… va Yev… (= ev) bilan ham;
  //   «J.» — ruscha Dj… / Dzh… / Zh… bilan ham (Джамалович, Dzhurayevna: o'zbekcha J = Дж / Ж — boshqa harf emas).
  var INITIAL = 0.75;
  function iniMatch(p, r) {
    if (r.indexOf(p) === 0) return true;
    if (p.charAt(0) === 'j' && r.replace(/^(?:dzx|dzh|dj|zx|zh)/, 'j').indexOf(p) === 0) return true;   // J. = Дж / Ж (Djamshid, Dzhurayevich)
    if (/o$/.test(p) && r.indexOf(p.replace(/o$/, 'u')) === 0) return true;
    if (r.replace(/^ye/, 'e').indexOf(p.replace(/^ye/, 'e')) === 0) return true;
    return p === 'y' && r.indexOf('ev') === 0;
  }
  //   Yozuvda ruscha otasining ismi bo'lsa (rp — r shu so'zmi): ism bosh harfi otasining ismiga, otasining ismi bosh harfi
  //   esa ismga juftlanmaydi («Karimov Z.» — Zafarovich emas, Zuhra; aka-ukalar otasining ismi bir xil). 3-rol — to'lovchi yozgan
  //   otasining ismi («otasi Rustam») — faqat otasining ismiga, o'zagi bilan ham (Rustam ↔ Rustamovich).
  function patRoot(pat) { return pat.replace(/(ovich|evich|ovna|evna|ichna|vich|vna)$/, ''); }
  function pairSim(p, r, ini, rp) {   // p — to'lovchi so'zi, r — o'quvchi ismidagi so'z, ini — bosh harf roli (0 — so'z)
    if (ini === 3) return !rp ? 0 : p.length <= 2 ? (iniMatch(p, r) ? INITIAL : 0) : Math.max(wordSim(p, r), wordSim(p, patRoot(r)));
    if (p === r) return 1;
    if (p.length <= 2) return (ini && (rp == null || (ini === 2) === rp) && iniMatch(p, r)) ? INITIAL : 0;
    if (rp && PATRONYMIC.test(p) && foldKey(p) === foldKey(r)) return 1;   // «Qodirovich» = «Kadyrovich»
    return wordSim(p, r);
  }
  // O'zbekcha ↔ ruscha yozuvdagi BIR ism (Qodir ↔ Kadyr, Qo'chqor ↔ Kuchkar, G'ulom ↔ Gulyam, Jamol ↔ Djamal / Dzhamal, Botir ↔
  //   Batyr, Valijon ↔ Validzhan) — faqat otasining ismini solishtirishda: apostrofsiz, dzh / dj / zh (normWord'dan keyin «dzx»,
  //   «zx») → j, q → k, o → a, undoshlar orasidagi / oxiridagi y → i. foldKey — qolgan y'larsiz (Gulyam = G'ulom); ikki ism faqat
  //   AYNAN teng foldKey bilan bir ism (Sarvar ≠ Sardor, Komil ≠ Kamol).
  function fold(w) {
    return w.replace(/'/g, '').replace(/dzx|dzh|dj|zx|zh/g, 'j').replace(/q/g, 'k').replace(/o/g, 'a').replace(/([^aeiu])y(?![aeiu])/g, '$1i');
  }
  function foldKey(w) { return fold(w).replace(/y/g, ''); }
  // Tasodifiy o'xshashlik chegarasi: begona ismlar ham umumiy harflar (-ov, -eva, -bek…) tufayli ~30% «o'xshaydi»
  //   (Karimov / Sobirov). Shu darajagacha o'xshashlik hisobga olinmaydi, yuqorisi 0..1 ga cho'ziladi.
  var CHANCE = 0.3;
  function pairScore(s) { return Math.max(0.01, (s - CHANCE) / (1 - CHANCE)); }

  // Ikki ism o'xshashligi 0..1. So'zlar tartibi muhim emas: kichik to'plamdagi har so'z kattasidagi BITTA so'zga
  //   juftlanadi (eng yaxshi juftlash). Ball — juftlar balining (pairScore) GEOMETRIK o'rtachasi, 1.5-darajada: bitta
  //   so'z mos kelmasa (faqat ism yoki faqat familiya mos — aka-uka, adash; zid bosh harf) ball 50% dan past bo'ladi va
  //   summa bonusi ham uni 60% ga yetkaza olmaydi; oddiy imlo xatolari (so'zda 1 harf) esa ~80–90% da qoladi. Faqat bitta
  //   so'z mos — dalil kuchsiz (×0.6). Bir tomonda ortiqcha so'z (masalan otasining ismi -ovna) — yengil jarima (−5%).
  //   PI[i] — P[i] roli (0 — so'z, 1/2 — bosh harf, 3 — otasining ismi). usedP / usedR — eng yaxshi juftlashda juftlanganlar.
  function simTokens(P, R, PI) {
    if (!P.length || !R.length) return { s: 0, ini: false, usedP: [], usedR: [] };
    PI = PI || [];
    var pSmall = P.length <= R.length, S = pSmall ? P : R, L = pSmall ? R : P, k = S.length;
    var best = -Infinity, bestIni = false, used = [], asg = [], bestAsg = [], pt = hasPat(R) ? R.length - 1 : -1;
    (function rec(i, acc, byIni) {        // kichik to'plam -> katta to'plam injektiv juftlash (<= 6×5)
      if (i === k) { if (acc > best) { best = acc; bestIni = byIni; bestAsg = asg.slice(); } return; }
      for (var j = 0; j < L.length; j++) {
        if (used[j]) continue;
        var p = pSmall ? S[i] : L[j], r = pSmall ? L[j] : S[i], ri = pSmall ? j : i, pi = pSmall ? PI[i] : PI[j];
        var ps = pairSim(p, r, pi, pt < 0 ? null : ri === pt);
        used[j] = true; asg[i] = j;
        rec(i + 1, acc + Math.log(pairScore(ps)), byIni || (p.length <= 2 && p !== r && ps > 0 && pi !== 3));
        used[j] = false;
      }
    })(0, 0, false);
    var g = Math.pow(Math.exp(best / k), 1.5), usedP = [], usedR = [];
    if (k === 1) g *= 0.6;
    g *= Math.max(0, 1 - 0.05 * (L.length - k));
    for (var q = 0; q < k; q++) { (pSmall ? usedP : usedR)[q] = true; (pSmall ? usedR : usedP)[bestAsg[q]] = true; }
    return { s: Math.max(0, Math.min(1, g)), ini: bestIni, usedP: usedP, usedR: usedR };   // ini — bosh harf bilan juftlangan so'z bor
  }
  // Hisobga olinmagan qisqa so'z (loose2) bor, ismda esa juftsiz so'z qolgan yoki so'z faqat BOSH HARF bilan juftlangan bo'lsa —
  //   o'sha qisqa so'z (masalan koreyscha familiya) shu so'zga zid bo'lishi mumkin («Ли Виктория Сергеевна», «На Виктория …» ↔
  //   «Kim Viktoriya Sergeyevna»; «Em Nikita … sh.» ↔ «Shin Nikita»): ball 64% dan oshmaydi (bonus bilan ham < 75% — ⚠️).
  //   Ism o'rnidagi «Майя» / «Марта» ismda yo'q, ismda esa juftsiz so'z (otasining ismidan boshqa) qolgan bo'lsa — boshqa bola
  //   («Petrova Mayya uchun» ↔ Petrova Anna): ball 45% dan oshmaydi (qarz = summa bonusi bilan ham taklif qilinmaydi).
  //   Bosh harf roli yozuvga qarab o'zgargan (down: «Guliston Karimov J.») — ball 64% dan oshmaydi (⚠️).
  var LOOSE_CAP = 0.64, SOFT_CAP = 0.45;
  function scored(t, R) {
    var r = simTokens(t.P, R, t.PI), pt = hasPat(R) ? R.length - 1 : -1, free = false, nw = 0, j;
    for (j = 0; j < R.length; j++) if (j !== pt && !r.usedR[j]) free = true;
    for (j = 0; j < t.PI.length; j++) if (t.PI[j] !== 3) nw++;
    if (t.softMiss && free) r.s = Math.min(r.s, SOFT_CAP);
    if ((t.loose2 && (R.length > nw || r.ini)) || t.down) r.s = Math.min(r.s, LOOSE_CAP);
    return r;
  }
  // To'lovchi yozgan so'z / bosh harf yozuvdagi otasining ismiga (pat) mosmi: «R.» ↔ Rustamovich; «Rustamovch», «Rustamova» (≥ 0.6);
  //   o'zagi bilan — «Bahodir», «Bahodirov», «Bahodirjon», qisqartma «Bah.» ↔ Bahodirovich; ruscha yozuvdagi AYNAN shu ism ham
  //   («Qodir o'g'li», «Qodirov» ↔ Kadyrovich — foldKey teng; -ov shaklida o'zagi foldKey bilan teng yoki y bilan ham boshi bir:
  //   «G'ulomov» ↔ Gulyamovich, «Qodirjonov» ↔ Kadyrovich; «Ahadov» ↔ Yahyoyevich, «Fozilov» ↔ Fayziyevich — emas). Bosh harf faqat
  //   aynan (O. ≠ Anvarovich); faqat ruscha yozuvda mos bosh harf («Q.» ↔ Kadyrovich, «K.» ↔ Qodirovich) — iniFold: dalil emas,
  //   zid ham emas (R' ≤ 64%, ⚠️).
  function compat(w, pat) {
    if (w.length <= 2) return iniMatch(w, pat);
    var root = patRoot(pat);
    if (wordSim(w, pat) >= 0.6 || (root.length >= 3 && (wordSim(w, root) >= 0.75 || root.indexOf(w) === 0 || w.indexOf(root) === 0))) return true;
    var fw = foldKey(w), fr = foldKey(root);
    return fr.length >= 3 && (fw === fr || (fw.indexOf(fr) === 0 && PATR_FORM.test(w)
      && (fold(w).indexOf(fold(root)) === 0 || foldKey(w.replace(PATR_FORM, '')) === fr)));
  }
  function iniFold(w, pat) { return w.length <= 2 && !iniMatch(w, pat) && iniMatch(fold(w), fold(pat)); }
  // Otasining ismi shaklidagi so'z: -ov / -ev / -ova / -ovna / -ovn / -ovana / -ovch / -ovic / -ovitch / -ovish / -obich / -ovchi…
  var PATR_FORM = /[oe][vb](?:itch|ich|icn|ic|ix|ish|chi|ch|ana|an|na|n|a|i)?$/;
  // Otasining ismisiz (R') solishtirish DALILI: to'lovchining R' ga juftlanmagan so'zlari, 2 so'zli R' da tashlangan otasining ismi
  //   bosh harfi va to'lovchi yozgan otasining ismi yozuvdagi otasining ismi (pat) bilan solishtiriladi. Mos («Bahodir», «Bah.»,
  //   «R.» ↔ Bahodirovich / Rustamovich) — 'for' (R' to'liq); zid — bosh harf, otasining ismi, otasining ismi shaklidagi so'z
  //   (familiyaga o'xshamasa, o'quvchi ismi YONIDA va jinsi mos: «Jasur Rustamov», «Malika Rustamova») yoki to'liq ism ICHIDAGI so'z
  //   («Karimov Jasur Rustam» ↔ Karimov Rustam …) — '' (R' yo'q); boshqa bo'lakdagi («Karimova Malika va Karimov Ali», «…, Karimov
  //   Ali», «Karimov Jasur - Rahimova Dilnoza»), familiyasi o'xshash aka-uka so'zlari, ona so'zidan keyingi («onasi Rahimova») va
  //   boshqa odamning to'liq ismi («Karimov Jasur Rahimova Dilnoza»), o'g'il ismi yonidagi -ova («Jasur Rahimova») — dalil emas;
  //   qolgan noma'lum so'z («Guliston») — 'generic' (R' ≤ 64%, ⚠️); dalil yo'q — 'none' (R' to'liq).
  function evidence(info, t, r, R2, pat) {
    var toks = info.toks, P = t.P, paired = [], isP = {}, vs = [], q, k, female = /(vna|ichna)$/.test(pat);
    for (q = 0; q < P.length; q++) if (r.usedP[q] && t.PX[q] >= 0) { paired.push(t.PX[q]); isP[t.PX[q]] = true; }
    var near = function (x, lo, hi) { return paired.some(function (y) { return toks[y].seg === toks[x].seg && y > lo && y < hi; }); };
    var fam = function (a, d) {
      for (; a >= 0 && a < P.length && !r.usedP[a]; a += d) if (P[a].length > 2 && bestSim(P[a], R2) >= 0.8) return true;
      return false;
    };
    var same = function (x, y) { return y >= 0 && y < toks.length && toks[y].seg === toks[x].seg; };
    //   ona so'zidan keyin (shu bo'lakda, orada o'quvchi ismi yo'q) — bir o'tishda
    var momAt = [], mf = false;
    for (k = 0; k < toks.length; k++) { if (k && toks[k].seg !== toks[k - 1].seg) mf = false; momAt[k] = mf; if (MOTHER[toks[k].w]) mf = true; else if (isP[k]) mf = false; }
    var mom = function (x) { return !!momAt[x]; };
    //   ayol kishining to'liq ismi (familiyasi -ova / -eva + otasining ismi shaklida bo'lmagan ism): «Rahimova Dilnoza» — onasi /
    //   to'lovchi; «Bahodirov Guliston», «Bahodirov Rahimova» (otasining ismi + onasining familiyasi) — emas
    var femSur = function (y) { var v = toks[y].w; return /[oe][vb]a$/.test(v) && v.replace(PATR_FORM, '').length >= 3; };
    var other = function (x) {
      return [x - 1, x + 1].some(function (y) {
        return same(x, y) && !isP[y] && t.fate[y] === 'P' && !toks[y].ini && toks[y].w.length > 2 && bestSim(toks[y].w, R2) < 0.8
          && ((femSur(x) && !PATR_FORM.test(toks[y].w)) || (femSur(y) && !PATR_FORM.test(toks[x].w)));
      });
    };
    for (q = 0; q < P.length; q++) {
      var x = t.PX[q], w = P[q];
      if (r.usedP[q] || x < 0 || !near(x, -1, Infinity) || fam(q, -1) || fam(q, 1)) continue;
      if (compat(w, pat)) { vs.push(1); continue; }
      if (near(x, -1, x) && near(x, x, Infinity)) { vs.push(-1); continue; }
      if (mom(x) || (w.length > 2 && other(x))) continue;
      if (w.length > 2 && PATR_FORM.test(w) && w.replace(PATR_FORM, '').length >= 3 && bestSim(w, R2) < 0.8) {   // «Eva» — ism
        if (/[oe][vb](?:a|n|na|an|ana)$/.test(w) !== female) continue;
        vs.push((isP[x - 1] && same(x, x - 1)) || (isP[x + 1] && same(x, x + 1)) ? -1 : 0);
      } else vs.push(w.length <= 2 && !!toks[x].ini && !iniFold(w, pat) ? -1 : 0);
    }
    for (k = 0; k < toks.length; k++) if (t.fate[k] === 'd' && near(k, -1, Infinity) && !mom(k)) vs.push(compat(toks[k].w, pat) ? 1 : iniFold(toks[k].w, pat) ? 0 : -1);
    info.fathers.forEach(function (w) { vs.push(compat(w, pat) ? 1 : -1); });
    return vs.indexOf(-1) >= 0 ? '' : vs.indexOf(1) >= 0 ? 'for' : vs.length ? 'generic' : 'none';
  }
  // Ism balli. O'quvchi yozuvi 3+ so'zli va oxirgisi ruscha otasining ismi (-ovich/-ovna) bo'lsa, to'lovchi esa otasining ismini
  //   (-ovich/-ovna so'zi bilan) yozmagan bo'lsa — u so'zsiz ham solishtiriladi (R', ×0.95): «Каримов Жасур питание» / «… Guliston»
  //   dagi ortiqcha so'z otasining ismiga majburan juftlanib, to'g'ri o'quvchini 10% ga tushirmasin. Dalil (evidence) zid bo'lsa —
  //   R' yo'q (adash / amakivachcha: «Karimov Jasur Rustamov», «(dadasi Bahodir)» ↔ … Rustamovich), noma'lum so'z — R' ≤ 64%.
  //   To'lovchi yozgan otasining ismi («otasi Rustam», «Rustam o'g'li») yozuvdagisiga zid bo'lsa — u ham juftlanadi (ball tushadi).
  //   Otasining ismisiz 3+ so'zli yozuv (qo'sh ism: «Karimov Muhammad Ali») — 2-bosh harf ixtiyoriy («Karimov M.R.»: ×0.95, ≤ 64%).
  function nameScore(info, R) {
    if (!R.length) return 0;
    var pat = hasPat(R) ? R[R.length - 1] : null, t = payerTokens(info, R), s;
    var fat = pat ? info.fathers.filter(function (w) { return !compat(w, pat); }).slice(0, 1) : [];
    s = scored(fat.length ? payerTokens(info, R, { fat: fat }) : t, R).s;
    if (pat && !info.patr) {
      var R2 = R.slice(0, -1), t2 = payerTokens(info, R2), r2 = scored(t2, R2), ev = evidence(info, t2, r2, R2, pat);
      if (ev) s = Math.max(s, ev === 'generic' ? Math.min(0.95 * r2.s, LOOSE_CAP) : 0.95 * r2.s);
    } else if (!pat && R.length >= 3 && t.PI.indexOf(2) >= 0) {
      s = Math.max(s, Math.min(0.95 * scored(payerTokens(info, R, { drop2: true }), R).s, LOOSE_CAP));
    }
    return s;
  }
  // nameSimilarity(to'lovchi matni, o'quvchi ismi) — tartib MUHIM: birinchisi «shovqinli» matn (raqamli bo'laklar va izoh
  //   so'zlari tozalanadi, nuqtali 1–2 harf — bosh harf), ikkinchisi — o'quvchi yozuvi (o'zgarishsiz).
  function nameSimilarity(payer, record) { return nameScore(payerInfo(payer), recordTokens(record)); }

  // Summa mosligi bonusi: joriy qarz = to'lov summasi -> +10%, oylik to'lov = summa -> +5% (eng kattasi, qo'shilmaydi).
  //   Ism umuman o'xshamasa (< 50%) — bonus uni 60% chegarasiga YETKAZMAYDI (ko'pi bilan 59%).
  function scoreCandidate(nameScore, info) {
    var amt = Math.round(Number(info && info.amount) || 0), bonus = 0;
    if (amt > 0 && info) {
      if (info.debt != null && Math.round(Number(info.debt) || 0) === amt) bonus = 0.10;
      else if (info.monthly != null && Math.round(Number(info.monthly) || 0) === amt) bonus = 0.05;
    }
    var s = (Number(nameScore) || 0) + bonus;
    if ((Number(nameScore) || 0) < 0.5) s = Math.min(s, 0.59);
    return { score: Math.max(0, Math.min(1, s)), bonus: bonus };
  }

  // Ism bo'yicha nomzodlar (bonusdan OLDIN): [{ item, nameScore }] kamayish tartibida, minName dan past — tashlanadi.
  //   items: [{ name, ... }] (chaqiruvchi faqat faol o'quvchilarni beradi), getName — ixtiyoriy.
  function rankByName(payerName, items, opts) {
    opts = opts || {};
    var minName = opts.minName == null ? 0.5 : opts.minName, limit = opts.limit || 8;
    var getName = opts.getName || function (x) { return x && x.name; };
    var info = payerInfo(payerName);
    if (!info.toks.length) return [];
    var out = [];
    (items || []).forEach(function (it) {
      var sc = nameScore(info, recordTokens(getName(it)));
      if (sc >= minName) out.push({ item: it, nameScore: sc });
    });
    out.sort(function (x, y) { return y.nameScore - x.nameScore; });
    return out.slice(0, limit);
  }

  // Bonusdan OLDIN qisqartirish: summa bonusi (ko'pi bilan maxBonus = +10%) bilan eng yaxshi «keep» (3) talikka kira
  //   OLADIGAN har bir nomzod qoladi (chegaradagi teng ballilar ham). Oddiy «birinchi N ta» kesish ro'yxat tartibiga
  //   bog'liq bo'lib, qarzi summaga teng (eng mos) o'quvchini tashlab yuborishi mumkin edi. cap — so'rov hajmi chegarasi.
  function shortlist(ranked, opts) {
    opts = opts || {};
    var keep = opts.keep || 3, room = opts.maxBonus == null ? 0.10 : opts.maxBonus, cap = opts.cap || 40;
    var list = (ranked || []).slice().sort(function (x, y) { return y.nameScore - x.nameScore; });
    if (list.length <= keep) return list;
    var cut = list[keep - 1].nameScore - room - 1e-9;
    return list.filter(function (c) { return c.nameScore >= cut; }).slice(0, cap);
  }

  // Yakuniy takliflar: bonus qo'shilgan ball >= min (60%), ko'pi bilan limit (3) ta. HECH QACHON avtomatik biriktirmaydi.
  //   cands: rankByName natijasi; infoOf(item) -> { debt, monthly } (noma'lum bo'lsa null); amount — to'lov summasi.
  function pickSuggestions(cands, amount, infoOf, opts) {
    opts = opts || {};
    var min = opts.min == null ? 0.6 : opts.min, limit = opts.limit || 3;
    return (cands || []).map(function (c) {
      var info = (infoOf && infoOf(c.item)) || {};
      var r = scoreCandidate(c.nameScore, { amount: amount, debt: info.debt, monthly: info.monthly });
      return { item: c.item, nameScore: c.nameScore, score: r.score, bonus: r.bonus, percent: Math.round(r.score * 100), debt: info.debt, monthly: info.monthly };
    }).filter(function (x) { return x.score >= min; })
      .sort(function (x, y) { return (y.score - x.score) || (y.nameScore - x.nameScore); })
      .slice(0, limit);
  }

  return { toLatin: toLatin, normalizeName: normalizeName, nameTokens: nameTokens, wroteName: wroteName, levenshtein: levenshtein,
    wordSim: wordSim, nameSimilarity: nameSimilarity, scoreCandidate: scoreCandidate, rankByName: rankByName, shortlist: shortlist,
    pickSuggestions: pickSuggestions };
});
