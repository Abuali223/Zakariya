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
  var CLASS_AFTER = new RegExp('(^|[^' + W + '])(' + CLASSW + SEP + '+)\\p{L}(?![' + W + '])', 'gu');
  var CLASS_BEFORE = new RegExp('(^|[^' + W + '])\\p{L}(?=' + SEP + '+' + CLASSW + '(?![' + W + ']))', 'gu');
  var NUM_SIGN = new RegExp('(^|[^' + W + '])(?:no\\.?|nr\\.?|n)\\s*(?=\\d)', 'gu');   // «N.» (nuqta bilan) — bosh harf, tegilmaydi
  // «F.I.O.:», «Ф.И.Ш.» — yorliq (ism emas)
  var FIO = new RegExp('(^|[^' + W + '])(?:f\\.?\\s*i\\.?\\s*(?:o|sh)|ф\\.?\\s*и\\.?\\s*[ош])\\.?(?![' + W + '])', 'gu');
  var NEAR_DIGIT_BEFORE = new RegExp('(^|[^' + W + '])[\\p{L}\\p{M}]{1,2}(?=[-\\u2013.]?\\d)', 'gu');
  var NEAR_DIGIT_AFTER = new RegExp('(\\d+[-\\u2013\\u2014.]?["\\u00AB\\u201C]?)([' + W + ']{1,4})(?![' + W + '])', 'gu');
  var DIGIT_SPACE_LETTER = new RegExp('(\\d\\s+[-\\u2013\\u2014.]?\\s*)\\p{L}(?![' + W + '])', 'gu');
  // Uzun raqamga (ID, telefon: 3+ raqam) yopishgan 3+ harfli so'z izoh so'zi bo'lmasa — ism («IQ-0042-Ali», «998901112233Ali»);
  //   qisqa raqamdan keyingisi (sinf «5-A», «11B») va izoh so'zi («2026-yil», «1500000so'm») — olib tashlanadi.
  function nearDigitAfter(m, pre, word) {
    return (/\d{3}/.test(pre) && word.replace(/'/g, '').length >= 3 && !FILLER[normalizeName(word)]) ? m : pre + ' ';
  }
  function payerClean(text) {
    return fixSeparators(String(text == null ? '' : text).slice(0, 500).normalize('NFC')).toLowerCase()
      .replace(HEX_CODE, '$1 ').replace(FIO, '$1 ').replace(CLASS_AFTER, '$1$2 ').replace(CLASS_BEFORE, '$1 ').replace(NUM_SIGN, '$1 ')
      .replace(NEAR_DIGIT_BEFORE, '$1 ').replace(NEAR_DIGIT_AFTER, nearDigitAfter).replace(DIGIT_SPACE_LETTER, '$1 ');
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
    + "внучка внучки внучку племянника племянницы дочь дочка доча дочери дочки дочку дочке")
    .split(' ').forEach(function (w) { var n = normalizeName(w); if (n) FILLER[n] = 1; });
  // Manzil: shahar / tuman nomlari va manzil so'zlari — izoh so'zi (ism ham bo'la oladigan nomlar — Navoiy, Bektemir, Guliston,
  //   Nurafshon — ro'yxatda yo'q). Ularning yonidagi qisqartma (sh., t., q., г.) — bosh harf emas: joy nomidan KEYIN — doim
  //   («Toshkent sh.», «Chilonzor t.»); OLDIN — matn boshida, izoh so'zidan yoki to'liq ismdan keyin («г. Ташкент», «Karimov
  //   Jasur t. Chilonzor»); bitta familiyadan keyin esa bosh harf («Karimov Sh. Toshkent», «Каримов Г. Ташкент»).
  var TOPO = {}, ADDR = { sh: 1, t: 1, q: 1, g: 1, tum: 1, vil: 1, obl: 1 };
  ("toshkent tashkent chilonzor yunusobod yunusabad mirobod sergeli yashnobod olmazor uchtepa shayxontohur yakkasaroy yangihayot "
    + "samarqand samarkand buxoro buxara andijon namangan farg'ona fargona qo'qon qarshi jizzax termiz urganch nukus xiva chirchiq "
    + "angren olmaliq bekobod zangiota qibray "
    + "тошкент ташкент чилонзор чиланзар юнусобод юнусабад миробод мирабад сергели яшнобод олмазор алмазар учтепа яккасарой "
    + "самарқанд самарканд бухоро бухара андижон андижан наманган фарғона фергана қарши карши жиззах термиз урганч нукус "
    + "чирчиқ чирчик ангрен олмалиқ алмалык")
    .split(' ').forEach(function (w) { var n = normalizeName(w); if (n) { TOPO[n] = 1; FILLER[n] = 1; } });
  ("shahar shahri tuman tumani viloyat viloyati mahalla mahallasi ko'cha ko'chasi xonadon город района район область улица "
    + "дом махалля шаҳар туман вилоят маҳалла кўча")
    .split(' ').forEach(function (w) { var n = normalizeName(w); if (n) FILLER[n] = 1; });

  // To'lovchi matni bir marta tahlil qilinadi — so'zlar TARTIB bilan: { w, f (izoh so'zi), ini (aniq bosh harf tartibi: 1, 2…) }.
  //   Aniq BOSH HARF — NUQTA bilan yozilgan 1–2 harf: «X.», «J.», «Sh.», «Ш.», «O'.», «Ў.», yopishgan «J.O.» / «Ж.О.» ham
  //   (ikkinchisi — otasining ismi bosh harfi). Nuqtasiz yakka harf bosh harf EMAS. comment — 2+ izoh so'zi («Avgust oyi
  //   uchun»: bunday matnda oy nomi ism emas). patr — to'lovchi otasining ismini (-ovich/-ovna) yozgan; role — bosh harf roli
  //   (1 — familiya/ism, 2 — otasining ismi); ini2 — 2-roldagi bosh harflar.
  function payerInfo(text) {
    var lat = toLatin(payerClean(text)), re = /[a-z']+/g, m, raw = [];
    while ((m = re.exec(lat))) {
      var core = m[0].replace(/^'+|'+$/g, '');
      if (!core) continue;
      if (PATRON.test(core)) { raw.pop(); continue; }
      raw.push({ s: m[0], dot: core.length <= 2 && lat.charAt(m.index + m[0].length) === '.' });
    }
    var ws = [], toks = [], nIni = 0, nf = 0, patr = false, ini2 = [], i;
    for (i = 0; i < raw.length; i++) { var x = normWord(raw[i].s); if (x) ws.push({ w: x, dot: raw[i].dot }); }
    var isNameW = function (k) { return k >= 0 && !FILLER[ws[k].w] && ws[k].w.length > 2; };
    for (i = 0; i < ws.length; i++) {
      var w = ws[i].w, f = !!FILLER[w] || (!!ADDR[w] && ((i > 0 && !!TOPO[ws[i - 1].w])
        || (i + 1 < ws.length && !!TOPO[ws[i + 1].w] && (i === 0 || !!FILLER[ws[i - 1].w] || (isNameW(i - 1) && isNameW(i - 2))))));
      var ini = (!f && ws[i].dot && w.length <= 2) ? ++nIni : 0;
      if (f) nf++;
      else if (w.length > 2 && PATRONYMIC.test(w)) patr = true;
      toks.push({ w: w, f: f, ini: ini });
    }
    // Bosh harf roli: otasining ismi bosh harfi (2) — boshqa bosh harfdan keyin («J.R.», «J. R.») yoki ketma-ket ikki to'liq
    //   so'zdan keyin («Karimov Jasur R.»); qolganlari — familiya/ism bosh harfi (1): «Karimov J.», «Jo'rayeva G.; 1-chorak».
    var nameW = function (t) { return !!t && !t.f && !t.ini && t.w.length > 2; };
    for (i = 0; i < toks.length; i++) if (toks[i].ini) {
      toks[i].role = (i > 0 && toks[i - 1].ini) || (nameW(toks[i - 1]) && nameW(toks[i - 2])) ? 2 : 1;
      if (toks[i].role === 2) ini2.push(toks[i].w);
    }
    return { toks: toks, comment: nf >= 2, patr: patr, ini2: ini2 };
  }
  // O'quvchi ismi (R — so'zlari) bilan solishtirish uchun to'lovchi so'zlari (ko'pi bilan 5 ta, tozalashdan KEYIN):
  //   izoh so'zi — faqat matn izoh bo'lmasa va ismda ham bo'lsa qoladi («Avgust», «May» — haqiqiy ism ham);
  //   1–2 harfli so'z — ismdagi so'zga aynan teng bo'lsa (koreyscha «O», «Li») yoki aniq bosh harf bo'lsa: familiya/ism bosh
  //   harfi doim, otasining ismi bosh harfi — faqat 3+ so'zli yozuvda; PI — har so'z roli (0 — so'z, 1/2 — bosh harf).
  //   Qolgan 1–2 harfli so'zlar (nuqtasiz, ismda yo'q — «Ли», «O», «и», xato «X adicha») hisobga olinmaydi, lekin sanaladi:
  //   loose — hammasi, loose2 — 2 harfli va «o» (koreyscha familiya bo'la oladiganlar; ruscha «в», «и» kabi yakka harflar emas).
  //   R yo'q (null) — faqat ism so'zlari.
  function payerTokens(info, R) {
    var P = [], PI = [], loose = 0, loose2 = 0, big = !!R && R.length >= 3;
    for (var i = 0; i < info.toks.length; i++) {
      var t = info.toks[i], inRec = !!R && R.indexOf(t.w) >= 0;
      if (t.f) { if (!info.comment && inRec) { P.push(t.w); PI.push(0); } continue; }
      if (t.w.length <= 2) {
        if (inRec || t.role === 1 || (t.role === 2 && big)) { P.push(t.w); PI.push(t.role || 0); }
        else if (!t.ini) { loose++; if (t.w.length === 2 || t.w === 'o') loose2++; }
        continue;
      }
      P.push(t.w); PI.push(0);
    }
    return { P: P.slice(0, 5), PI: PI.slice(0, 5), loose: loose, loose2: loose2 };
  }
  // O'quvchi ismi — toza yozuv: hech narsa tashlanmaydi (bitta harfli koreyscha familiya «O», «Avgust» ismi ham so'z).
  function recordTokens(name) { return normalizeName(name).split(' ').filter(Boolean).slice(0, 5); }
  // To'lovchi matnidagi ism so'zlari (izoh so'zlari, raqamli bo'laklar va nuqtasiz yakka harflarsiz).
  //   record berilsa — shu o'quvchi ismi bilan solishtirishda hisobga olinadigan so'zlar (nameSimilarity bilan BIR XIL qoida:
  //   «Avgust» — Karimov Avgust uchun ism, boshqa o'quvchi uchun izoh so'zi).
  function nameTokens(text, record) { return payerTokens(payerInfo(text), record == null ? null : recordTokens(record)).P; }
  // To'lovchi shu o'quvchi uchun ISM yozganmi (ogohlantirish kerakmi): ism so'zi yoki hisobga olinmagan qisqa so'z bor
  //   («Ли», «Ж К» ham — ism yozilgan, faqat boshqa o'quvchiniki bo'lishi mumkin). Faqat izoh / raqam — yo'q.
  function wroteName(text, record) {
    var t = payerTokens(payerInfo(text), record == null ? null : recordTokens(record));
    return t.P.length > 0 || t.loose > 0;
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
  //   «O.» / «Yo.» — O' (= u) bilan ham (O'tkir, Yo'ldosh); «E.»/«Е.» — e va ye bilan; «Y.» — Ye… va Yev… (= ev) bilan ham.
  var INITIAL = 0.75;
  function iniMatch(p, r) {
    if (r.indexOf(p) === 0) return true;
    if (/o$/.test(p) && r.indexOf(p.replace(/o$/, 'u')) === 0) return true;
    if (r.replace(/^ye/, 'e').indexOf(p.replace(/^ye/, 'e')) === 0) return true;
    return p === 'y' && r.indexOf('ev') === 0;
  }
  //   Yozuvda ruscha otasining ismi bo'lsa (rp — r shu so'zmi): ism bosh harfi otasining ismiga, otasining ismi bosh harfi
  //   esa ismga juftlanmaydi («Karimov Z.» — Zafarovich emas, Zuhra; aka-ukalar otasining ismi bir xil).
  function pairSim(p, r, ini, rp) {   // p — to'lovchi so'zi, r — o'quvchi ismidagi so'z, ini — bosh harf roli (0 — so'z)
    if (p === r) return 1;
    if (p.length <= 2) return (ini && (rp == null || (ini === 2) === rp) && iniMatch(p, r)) ? INITIAL : 0;
    return wordSim(p, r);
  }
  // Tasodifiy o'xshashlik chegarasi: begona ismlar ham umumiy harflar (-ov, -eva, -bek…) tufayli ~30% «o'xshaydi»
  //   (Karimov / Sobirov). Shu darajagacha o'xshashlik hisobga olinmaydi, yuqorisi 0..1 ga cho'ziladi.
  var CHANCE = 0.3;
  function pairScore(s) { return Math.max(0.01, (s - CHANCE) / (1 - CHANCE)); }

  // Ikki ism o'xshashligi 0..1. So'zlar tartibi muhim emas: kichik to'plamdagi har so'z kattasidagi BITTA so'zga
  //   juftlanadi (eng yaxshi juftlash). Ball — juftlar balining (pairScore) GEOMETRIK o'rtachasi, 1.5-darajada: bitta
  //   so'z mos kelmasa (faqat ism yoki faqat familiya mos — aka-uka, adash; zid bosh harf) ball 50% dan past bo'ladi va
  //   summa bonusi ham uni 60% ga yetkaza olmaydi; oddiy imlo xatolari (so'zda 1 harf) esa ~80–90% da qoladi. Faqat bitta
  //   so'z mos — dalil kuchsiz (×0.6). Bir tomonda ortiqcha so'z (masalan otasining ismi -ovna) — yengil jarima (−5%).
  //   PI[i] — P[i] bosh harf roli (0 — so'z).
  function simTokens(P, R, PI) {
    if (!P.length || !R.length) return { s: 0, ini: false };
    PI = PI || [];
    var pSmall = P.length <= R.length, S = pSmall ? P : R, L = pSmall ? R : P, k = S.length;
    var best = -Infinity, bestIni = false, used = [], pt = R.length >= 3 && PATRONYMIC.test(R[R.length - 1]) ? R.length - 1 : -1;
    (function rec(i, acc, byIni) {        // kichik to'plam -> katta to'plam injektiv juftlash (<= 5×5)
      if (i === k) { if (acc > best) { best = acc; bestIni = byIni; } return; }
      for (var j = 0; j < L.length; j++) {
        if (used[j]) continue;
        var p = pSmall ? S[i] : L[j], r = pSmall ? L[j] : S[i], ri = pSmall ? j : i;
        var ps = pairSim(p, r, pSmall ? PI[i] : PI[j], pt < 0 ? null : ri === pt);
        used[j] = true; rec(i + 1, acc + Math.log(pairScore(ps)), byIni || (p.length <= 2 && p !== r && ps > 0)); used[j] = false;
      }
    })(0, 0, false);
    var g = Math.pow(Math.exp(best / k), 1.5);
    if (k === 1) g *= 0.6;
    g *= Math.max(0, 1 - 0.05 * (L.length - k));
    return { s: Math.max(0, Math.min(1, g)), ini: bestIni };   // ini — eng yaxshi juftlashda bosh harf bilan juftlangan so'z bor
  }
  // Hisobga olinmagan qisqa so'z (loose2) bor, ismda esa juftsiz so'z qolgan yoki so'z faqat BOSH HARF bilan juftlangan bo'lsa —
  //   o'sha qisqa so'z (masalan koreyscha familiya) shu so'zga zid bo'lishi mumkin («Ли Виктория Сергеевна» ↔ «Kim Viktoriya
  //   Sergeyevna»; «Em Nikita … sh.» ↔ «Shin Nikita»): ball 64% dan oshmaydi (bonus bilan ham < 75% — ⚠️ ko'rinadi).
  var LOOSE_CAP = 0.64;
  function scoreRec(info, R) {
    var t = payerTokens(info, R), r = simTokens(t.P, R, t.PI);
    return t.loose2 && (R.length > t.P.length || r.ini) ? Math.min(r.s, LOOSE_CAP) : r.s;
  }
  // Ism balli. O'quvchi yozuvi 3+ so'zli va oxirgisi ruscha otasining ismi (-ovich/-ovna) bo'lsa, to'lovchi esa otasining
  //   ismini yozmagan (yoki faqat MOS bosh harfini yozgan: «Karimov J.R.», «Karimov Jasur R.» ↔ … Rustamovich) bo'lsa — u
  //   so'zsiz ham solishtiriladi (×0.95): «Каримов Жасур питание» / «… Toshkent» dagi ortiqcha so'z otasining ismiga majburan
  //   juftlanib, to'g'ri o'quvchini 10% ga tushirmasin. Aka-uka (boshqa ism) va zid bosh harf («J.R.» ↔ … Bahodirovich)
  //   baribir rad etiladi.
  function nameScore(info, R) {
    if (!R.length) return 0;
    var s = scoreRec(info, R), last = R[R.length - 1];
    if (R.length >= 3 && !info.patr && PATRONYMIC.test(last) && info.ini2.every(function (p) { return iniMatch(p, last); }))
      s = Math.max(s, 0.95 * scoreRec(info, R.slice(0, -1)));
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
