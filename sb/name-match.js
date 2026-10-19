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
  // Barcha apostrof turlari -> '  (' ʻ ʼ ‘ ’ ‛ ` ´ ′ ʹ ʽ ʾ ʿ ˈ ꞌ ＇ ՚)
  var APOS = /[\u2018\u2019\u201B\u02BB\u02BC\u02B9\u02BD\u02BE\u02BF\u02C8\uA78C\uFF07\u055A`\u00B4\u2032']/g;
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
    var s = translit(String(name == null ? '' : name).normalize('NFC').toLowerCase());
    return s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(APOS, "'").replace(/\s+/g, ' ').trim();
  }

  // Ismni solishtirish uchun yagona ko'rinishga keltiradi: toLatin + h->x, yev->ev, o'->u, takror harfsiz,
  //   «qizi/o'g'li» (va otasining ismi) olib tashlangan. So'zlar bitta bo'shliq bilan.
  function normalizeName(name) {
    var s = toLatin(name).replace(/[^a-z' ]+/g, ' ');
    var toks = s.split(/\s+/).map(function (t) { return t.replace(/^'+|'+$/g, ''); }).filter(Boolean);
    var kept = [];
    for (var i = 0; i < toks.length; i++) {
      if (PATRON.test(toks[i])) { kept.pop(); continue; }
      kept.push(toks[i]);
    }
    return kept.map(normWord).filter(Boolean).join(' ');
  }

  // Solishtirishda hisobga olinmaydigan so'zlar: bitta harf (bosh harf «X.», sinf harfi «5-A») va to'lov izohidagi
  //   umumiy so'zlar («uchun», «to'lov», «sinf», oy nomlari…). Aks holda ular haqiqiy ism so'ziga majburan juftlanib,
  //   to'g'ri o'quvchining balini ~3% ga yiqitardi («Xadicha uchun» — «Xadicha» dan past chiqardi).
  var FILLER = {};
  ("uchun to'lov tolov to'lovi tolovi to'lovni oy oyi oyga oylik oyligi sinf sinfi sinfda sinfidan klass klassa maktab maktabi "
    + "shkola o'quvchi oquvchi o'quvchisi oquvchisi farzand farzandi farzandim bola bolam bolasi kontrakt kontrakti shartnoma "
    + "shartnomasi summa summasi pul puli dars darsi kurs kursi id raqam raqami kod kodi ism ismi familiya familiyasi fio ota ona "
    + "otasi onasi va bilan ham yanvar fevral mart aprel may iyun iyul avgust sentabr sentyabr oktabr oktyabr noyabr dekabr "
    + "oplata za uchenik uchenika uchenitsa mesyats obuchenie click payme uzum iqror iqro akademiya academy")
    .split(' ').forEach(function (w) { FILLER[normalizeName(w)] = 1; });
  // Solishtirish uchun so'zlar: normalizeName + bitta harfli va to'ldiruvchi so'zlarsiz; ko'pi bilan 5 ta (tozalashdan KEYIN —
  //   «5-A sinf oktyabr oyi uchun Turg'unboyeva Xadicha» da ism tushib qolmasin).
  function nameTokens(name) {
    return normalizeName(name).split(' ').filter(function (t) { return t.length > 1 && !FILLER[t]; }).slice(0, 5);
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
  // Tasodifiy o'xshashlik chegarasi: begona ismlar ham umumiy harflar (-ov, -eva, -bek…) tufayli ~30% «o'xshaydi»
  //   (Karimov / Sobirov). Shu darajagacha o'xshashlik hisobga olinmaydi, yuqorisi 0..1 ga cho'ziladi.
  var CHANCE = 0.3;
  function pairScore(s) { return Math.max(0.01, (s - CHANCE) / (1 - CHANCE)); }

  // Ikki ism o'xshashligi 0..1. So'zlar tartibi muhim emas: kichik to'plamdagi har so'z kattasidagi BITTA so'zga
  //   juftlanadi (eng yaxshi juftlash). Ball — juftlar balining (pairScore) GEOMETRIK o'rtachasi, 1.5-darajada: bitta
  //   so'z mos kelmasa (faqat ism yoki faqat familiya mos — aka-uka, adash) ball 50% dan past bo'ladi va summa bonusi
  //   ham uni 60% ga yetkaza olmaydi; oddiy imlo xatolari (so'zda 1 harf) esa ~80–90% da qoladi. Faqat bitta so'zli
  //   ism — dalil kuchsiz (×0.6). Bir tomonda ortiqcha so'z (masalan otasining ismi -ovna) — yengil jarima.
  function nameSimilarity(a, b) {
    var A = nameTokens(a), B = nameTokens(b);
    if (!A.length || !B.length) return 0;
    var S = A.length <= B.length ? A : B, L = S === A ? B : A, k = S.length;
    var best = -Infinity, used = [];
    (function rec(i, acc) {               // kichik to'plam -> katta to'plam injektiv juftlash (<= 5×5)
      if (i === k) { if (acc > best) best = acc; return; }
      for (var j = 0; j < L.length; j++) {
        if (used[j]) continue;
        used[j] = true; rec(i + 1, acc + Math.log(pairScore(wordSim(S[i], L[j])))); used[j] = false;
      }
    })(0, 0);
    var g = Math.pow(Math.exp(best / k), 1.5);
    if (k === 1) g *= 0.6;
    g *= Math.max(0, 1 - 0.05 * (L.length - k));
    return Math.max(0, Math.min(1, g));
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
    if (!nameTokens(payerName).length) return [];
    var out = [];
    (items || []).forEach(function (it) {
      var sc = nameSimilarity(payerName, getName(it));
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
