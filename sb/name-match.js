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
  //   yakka tirnoqlar (‘ ’ ‚ ‛), ASCII ' va o'xshashlari (′ ″ ‵ ＇ ꞌ ՚). Qo'shtirnoqlar va ko'rinmas belgilar — fixSeparators.
  var APOS = /[\p{Lm}\p{Sk}'\u2018\u2019\u201A\u201B\u2032\u2033\u2035\uFF07\uA78C\u055A]/gu;
  // Qo'shtirnoq (« » “ ” " …) va ko'rinmas belgi (\p{Cf}): so'z ICHIDA (harflar orasida) — apostrof / o'chiriladi
  //   («Turg”unboyeva», «Turg\u200Bunboyeva»); so'zlar ORASIDA (kichik harfdan keyin Katta harf, yoki so'z chetida) — bo'shliq
  //   («Turg'unboyeva«Xadicha»», «Xadicha\u200BTurg'unboyeva»). Yumshoq tire — doim o'chiriladi. (Katta-kichik harf kerak:
  //   kichik harfga o'tkazishdan OLDIN ishlaydi.)
  var DQ = '\u00AB\u00BB\u201C\u201D\u201E\u201F\u2039\u203A"\uFF02';
  function fixSeparators(s) {
    var out = '', ch = Array.from(s.replace(/\u00AD/g, ''));
    for (var i = 0; i < ch.length; i++) {
      var c = ch[i], dq = DQ.indexOf(c) >= 0;
      if (!dq && !/\p{Cf}/u.test(c)) { out += c; continue; }
      var a = ch[i - 1] || '', b = ch[i + 1] || '';
      var inWord = /\p{L}/u.test(a) && /\p{L}/u.test(b) && !(/\p{Ll}/u.test(a) && /\p{Lu}/u.test(b));
      out += inWord ? (dq ? "'" : '') : ' ';
    }
    return out;
  }
  // Otasining ismi qo'shimchasi — u va undan OLDINGI so'z hisobga olinmaydi (... Rustam qizi / o'g'li)
  var PATRON = /^(qizi|kizi|o'g'li|og'li|o'gli|ogli|ug'li|ugli|o'gil|o'g'il)$/;

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
    return s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(APOS, "'").replace(/\s+/g, ' ').trim();
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
  //   bo'shliq bilan ajralgan YAKKA harf («5 A», «5 «A»»). Apostrof — so'z harfi («IQ-0042 Ra'no» da «Ra» kesilmaydi);
  //   raqamdan keyin bo'shliq bilan yozilgan so'z («IQ-0042 Ali») — ism, tegilmaydi.
  var AP = "'\\u2018\\u2019\\u02BB\\u02BC`\\u00B4";
  var HEX_CODE = /(^|[^\p{L}\p{M}\d])(?=[0-9a-f]*\d)[0-9a-f]{6,}(?![\p{L}\p{M}\d])/gu;
  var NEAR_DIGIT_BEFORE = new RegExp('(^|[^\\p{L}\\p{M}' + AP + '])[\\p{L}\\p{M}]{1,2}(?=[-\\u2013.]?\\d)', 'gu');
  var NEAR_DIGIT_AFTER = new RegExp('(\\d[-\\u2013\\u2014.]?["\\u00AB\\u201C]?)[\\p{L}\\p{M}' + AP + ']{1,4}(?![\\p{L}\\p{M}' + AP + '])', 'gu');
  var DIGIT_SPACE_LETTER = new RegExp('(\\d\\s+[-\\u2013\\u2014.]?\\s*["\\u00AB\\u201C]?)\\p{L}(?![\\p{L}\\p{M}' + AP + '])', 'gu');
  function payerClean(text) {
    return fixSeparators(String(text == null ? '' : text).slice(0, 500).normalize('NFC')).toLowerCase()
      .replace(HEX_CODE, '$1 ').replace(NEAR_DIGIT_BEFORE, '$1 ').replace(NEAR_DIGIT_AFTER, '$1 ').replace(DIGIT_SPACE_LETTER, '$1 ');
  }
  // Aniq BOSH HARF — nuqta bilan yozilgan 1–2 harf: «X.», «J.», «Sh.», «Ш.», «O'.», «Ў.». Nuqtasiz yakka harf («5-sinf A»,
  //   ruscha «в»/«и», «X adicha» kabi xato) bosh harf EMAS — ismdagi so'zga aynan teng bo'lmasa, hisobga olinmaydi.
  var INI_RE = new RegExp('(^|[^\\p{L}\\p{M}' + AP + '])([\\p{L}\\p{M}]{1,2}[' + AP + ']?)\\.', 'gu');

  // To'lov izohidagi umumiy so'zlar (lotin VA kirill yozuvi — normalizeName orqali bir xil ko'rinishga keltiriladi).
  //   Ular to'lovchi matnidan faqat o'quvchi ismida YO'Q bo'lsa tashlanadi («Avgust», «May» — haqiqiy ism ham bo'lishi mumkin).
  var FILLER = {};
  ("uchun to'lov tolov to'lovi tolovi to'lovni to'lash oy oyi oyga oyiga oylik oyligi sinf sinfi sinfda sinfidan klass klassa "
    + "maktab maktabi shkola o'quvchi oquvchi o'quvchisi oquvchisi farzand farzandi farzandim farzandimiz farzandingiz bola bolam "
    + "bolasi bolamiz bolangiz qizim qizimiz qizingiz o'g'lim og'lim o'g'limiz o'g'lingiz kontrakt kontrakti shartnoma shartnomasi "
    + "summa summasi pul puli dars darsi kurs kursi id raqam raqami kod kodi ism ismi familiya familiyasi fio ota ona otasi onasi "
    + "dadasi oyisi akasi opasi ukasi singlisi va bilan ham yanvar fevral mart aprel may iyun iyul avgust sentabr sentyabr oktabr "
    + "oktyabr noyabr dekabr yil yili yilgi o'qish oqish o'qishi haqi ta'lim talim qarz qarzi qarzlar avans ovqat so'm som sum ming "
    + "mln mlrd uzs oplata za uchenik uchenika uchenitsa mesyats obuchenie click payme uzum iqror iqro akademiya academy "
    + "учун тўлов тулов тўлови ой ойи ойлик синф синфи мактаб ўқувчи ўқувчиси фарзанд фарзандим бола болам қизим ўғлим контракт "
    + "шартнома сумма пул дарс курс ота она отаси онаси ва билан январь февраль март апрель май июнь июль август сентябрь октябрь "
    + "ноябрь декабрь йил йили ўқиш ҳақи таълим қарз аванс овқат сўм сум минг млн оплата за обучение обучения учеба учёба учебу "
    + "ученик ученика ученица ученицы школа школы класс класса месяц месяца дочь дочка доча дочери")
    .split(' ').forEach(function (w) { var n = normalizeName(w); if (n) FILLER[n] = 1; });

  // To'lovchi matni bir marta tahlil qilinadi: so'zlar (all), aniq bosh harflar (ini) va «izoh»mi (comment: 2+ izoh so'zi —
  //   masalan «Avgust oyi uchun», «Karimov Jasur avgust uchun»: bunday matnda oy nomi ism emas).
  function payerInfo(text) {
    var clean = payerClean(text), ini = {}, m;
    INI_RE.lastIndex = 0;
    while ((m = INI_RE.exec(clean))) { var k = normalizeName(m[2]); if (k) ini[k] = 1; }
    var all = normalizeName(clean).split(' ').filter(Boolean), nf = 0;
    for (var i = 0; i < all.length; i++) if (FILLER[all[i]]) nf++;
    return { all: all, ini: ini, comment: nf >= 2 };
  }
  // O'quvchi ismi (recTok) bilan solishtirish uchun to'lovchi so'zlari (ko'pi bilan 5 ta, tozalashdan KEYIN):
  //   izoh so'zi — faqat yakka (matn izoh emas) va ismda ham bo'lsa qoladi («Avgust», «May» — haqiqiy ism ham);
  //   1–2 harfli so'z — aniq bosh harf bo'lsa yoki ismdagi so'zga aynan teng bo'lsa (koreyscha «O», «Li»). recTok yo'q bo'lsa —
  //   faqat «ism so'zlari» (izoh va yakka harflarsiz).
  function payerTokens(info, recTok) {
    return info.all.filter(function (w) {
      var inRec = !!recTok && recTok.indexOf(w) >= 0;
      if (FILLER[w]) return !info.comment && inRec;
      if (w.length <= 2) return !!info.ini[w] || inRec;
      return true;
    }).slice(0, 5);
  }
  // O'quvchi ismi — toza yozuv: hech narsa tashlanmaydi (bitta harfli koreyscha familiya «O», «Avgust» ismi ham so'z).
  function recordTokens(name) { return normalizeName(name).split(' ').filter(Boolean).slice(0, 5); }
  // To'lovchi matnidagi ism so'zlari (izoh so'zlari, raqamli bo'laklar va nuqtasiz yakka harflarsiz) — «ism yozganmi?» tekshiruvi.
  //   record berilsa — shu o'quvchi ismi bilan solishtirishda hisobga olinadigan so'zlar (nameSimilarity bilan BIR XIL qoida:
  //   «Avgust» — Karimov Avgust uchun ism, boshqa o'quvchi uchun izoh so'zi).
  function nameTokens(text, record) { return payerTokens(payerInfo(text), record == null ? null : recordTokens(record)); }

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
  // To'lovchi NUQTA bilan yozgan QISQA so'z (1–2 harf: «X.», «J.», «Sh.», «Ш.» → sh, «Ю.» → yu; INI_RE) — BOSH HARF sifatida tekshiriladi:
  //   o'quvchi so'zi shu harf(lar) bilan boshlansa — o'rtacha dalil (0.75), boshqa harf bilan boshlansa — ZID (0): «Karimov J.»
  //   Karimov Jasur'ga mos, Karimov Bekzod'ga emas. Aynan teng qisqa so'z (koreyscha «Li», «O») — to'liq mos.
  //   «O.» (apostrofsiz) — O yoki O' (=u) bilan boshlanuvchi so'zga mos; «E.»/«Е.» — e yoki ye bilan (Yelena, Yevgeniy=evgeniy).
  var INITIAL = 0.75;
  function iniMatch(p, r) {
    if (p === 'o') return r.charAt(0) === 'o' || r.charAt(0) === 'u';
    return r.replace(/^ye/, 'e').indexOf(p.replace(/^ye/, 'e')) === 0;
  }
  function pairSim(p, r, ini) {   // p — to'lovchi so'zi, r — o'quvchi ismidagi so'z, ini — p aniq bosh harfmi
    if (p === r) return 1;
    if (p.length <= 2) return (ini && iniMatch(p, r)) ? INITIAL : 0;
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
  function simTokens(P, R, ini) {
    if (!P.length || !R.length) return 0;
    ini = ini || {};
    var pSmall = P.length <= R.length, S = pSmall ? P : R, L = pSmall ? R : P, k = S.length;
    var best = -Infinity, used = [];
    (function rec(i, acc) {               // kichik to'plam -> katta to'plam injektiv juftlash (<= 5×5)
      if (i === k) { if (acc > best) best = acc; return; }
      for (var j = 0; j < L.length; j++) {
        if (used[j]) continue;
        var ps = pSmall ? pairSim(S[i], L[j], ini[S[i]]) : pairSim(L[j], S[i], ini[L[j]]);
        used[j] = true; rec(i + 1, acc + Math.log(pairScore(ps))); used[j] = false;
      }
    })(0, 0);
    var g = Math.pow(Math.exp(best / k), 1.5);
    if (k === 1) g *= 0.6;
    g *= Math.max(0, 1 - 0.05 * (L.length - k));
    return Math.max(0, Math.min(1, g));
  }
  // nameSimilarity(to'lovchi matni, o'quvchi ismi) — tartib MUHIM: birinchisi «shovqinli» matn (raqamli bo'laklar va izoh
  //   so'zlari tozalanadi, nuqtali 1–2 harf — bosh harf), ikkinchisi — o'quvchi yozuvi (o'zgarishsiz).
  function nameSimilarity(payer, record) {
    var R = recordTokens(record), info = payerInfo(payer);
    return simTokens(payerTokens(info, R), R, info.ini);
  }

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
    if (!info.all.length) return [];
    var out = [];
    (items || []).forEach(function (it) {
      var R = recordTokens(getName(it)), sc = simTokens(payerTokens(info, R), R, info.ini);
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

  return { toLatin: toLatin, normalizeName: normalizeName, nameTokens: nameTokens, levenshtein: levenshtein, wordSim: wordSim,
    nameSimilarity: nameSimilarity, scoreCandidate: scoreCandidate, rankByName: rankByName, shortlist: shortlist,
    pickSuggestions: pickSuggestions };
});
