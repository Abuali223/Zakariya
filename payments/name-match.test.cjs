// =====================================================================
// name-match.test.cjs — ism-familiya normallashtirish va solishtirish (sb/name-match.js) birlik testlari.
//   «Biriktirish» oynasidagi «Ehtimol shu o'quvchi» takliflari (admin.html) va keyingi avtomatik biriktirish uchun.
//   node name-match.test.cjs
// =====================================================================
const fs = require('fs'), path = require('path'), vm = require('vm');
const N = require('../sb/name-match.js');
let pass = 0, fail = 0;
const ok = (n, c, x) => { if (c) pass++; else { fail++; console.log('  ✗ FAIL:', n, x !== undefined ? JSON.stringify(x) : ''); } };
const sim = (a, b) => N.nameSimilarity(a, b);
const T = "Turg'unboyeva Xadicha";

// ---- Topshiriqdagi 4 holat — natija konsolga chiqariladi ----
//   «taklif» — pickSuggestions (60% chegara) natijasi; «qarz = summa bo'lsa ham» — eng katta bonus (+10%) bilan.
console.log(`Topshiriqdagi holatlar (o'quvchi: ${JSON.stringify(T)}):`);
[["Turg'unboyeva Hadicha", true], ['Турғунбоева Хадича', true], ['Xadicha Turgunboeva', true], ['Aliyev Jasur', false]].forEach(([payer, high]) => {
  const ns = sim(payer, T), cand = [{ item: { name: T }, nameScore: ns }];
  const plain = N.pickSuggestions(cand, 1500000, () => ({ debt: 0, monthly: 0 }));
  const bonus = N.pickSuggestions(cand, 1500000, () => ({ debt: 1500000, monthly: 1500000 }));
  console.log(`  ${(JSON.stringify(payer) + ' ').padEnd(25, ' ')}↔ ${JSON.stringify(T)}  →  ${String(Math.round(ns * 100)).padStart(3)}% mos — `
    + (plain.length ? 'yuqori moslik, taklif qilinadi' : 'taklif qilinmaydi' + (bonus.length ? '' : ' (qarz = summa bo‘lsa ham)')));
  if (high) ok(`yuqori moslik: ${payer}`, ns >= 0.9 && plain.length === 1 && plain[0].percent >= 90, ns);
  else ok(`taklif qilinmaydi: ${payer}`, ns < 0.5 && plain.length === 0 && bonus.length === 0, ns);
});
console.log('');

// ---- Normallashtirish ----
ok('kirill -> lotin (topshiriq misoli)', N.toLatin('Турғунбоева Хадича') === "turg'unboyeva xadicha", N.toLatin('Турғунбоева Хадича'));
ok('o\'zbek kirill harflari', N.toLatin('ғ қ ў ҳ ё ю я ш ч ц') === "g' q o' h yo yu ya sh ch ts", N.toLatin('ғ қ ў ҳ ё ю я ш ч ц'));
ok('е: so\'z boshida / unlidan keyin ye, undoshdan keyin e', N.toLatin('Елена Алиева Сергеевич') === 'yelena aliyeva sergeyevich', N.toLatin('Елена Алиева Сергеевич'));
ok('kirill va lotin yozuv bir xil normal ko\'rinish', N.normalizeName('Турғунбоева Хадича') === N.normalizeName(T) && N.normalizeName(T) === "turg'unboeva xadicha", N.normalizeName(T));
ok('kichik harf + ortiqcha bo\'shliqlar', N.normalizeName('  TURG‘UNBOYEVA \t  XADICHA  ') === "turg'unboeva xadicha", N.normalizeName('  TURG‘UNBOYEVA \t  XADICHA  '));
["'", 'ʻ', 'ʼ', '‘', '’', '`', '´', '′'].forEach(a => ok(`apostrof ${JSON.stringify(a)} -> '`, N.normalizeName(`Turg${a}unboyeva`) === "turg'unboeva", N.normalizeName(`Turg${a}unboyeva`)));
ok('h -> x', N.normalizeName('Hadicha') === N.normalizeName('Xadicha') && N.normalizeName('Muhammad') === N.normalizeName('Muxammad'), [N.normalizeName('Hadicha'), N.normalizeName('Muhammad')]);
ok('sh / ch o\'zgarmaydi, kh = x', N.normalizeName('Shahzoda Chehra') === 'shaxzoda chexra' && N.normalizeName('Khadicha') === 'xadicha', [N.normalizeName('Shahzoda Chehra'), N.normalizeName('Khadicha')]);
ok('yeva -> eva, yev -> ev, yevich -> evich', N.normalizeName('Aliyeva') === 'alieva' && N.normalizeName('Aliyev') === 'aliev' && N.normalizeName('Valiyevich') === 'valievich'
  && N.normalizeName('Aliyeva') === N.normalizeName('Alieva'), [N.normalizeName('Aliyeva'), N.normalizeName('Valiyevich')]);
ok("o' = u", N.normalizeName("O'dil") === N.normalizeName('Udil') && N.normalizeName('Ўткир') === N.normalizeName('Utkir'), [N.normalizeName("O'dil"), N.normalizeName('Ўткир')]);
ok('takror harflar bittaga', N.normalizeName('Hadichaa') === 'xadicha' && N.normalizeName('Abdullayev') === 'abdulaev' && N.normalizeName('Muhammad') === 'muxamad');
ok('qizi + otasining ismi olib tashlanadi', N.normalizeName("Turg'unboyeva Xadicha Rustam qizi") === "turg'unboeva xadicha", N.normalizeName("Turg'unboyeva Xadicha Rustam qizi"));
ok("o'g'li / ogli / ugli / kizi / ўғли", ["Aliyev Jasur Karim o'g'li", 'Aliyev Jasur Karim ogli', 'Aliyev Jasur Karim ugli', 'Aliyev Jasur Karim o‘g‘li', 'Алиев Жасур Карим ўғли']
  .every(x => N.normalizeName(x) === 'aliev jasur') && N.normalizeName('Aliyeva Malika Karim kizi') === 'alieva malika', ['Алиев Жасур Карим ўғли', N.normalizeName('Алиев Жасур Карим ўғли')]);
ok('raqam/belgilar tashlanadi; bo\'sh ism', N.normalizeName('12345') === '' && N.normalizeName('') === '' && N.normalizeName(null) === '' && N.normalizeName('Aliyev, Jasur!') === 'aliev jasur');
ok('diakritika (é, İ) asos harfga', N.normalizeName('Jasur İsmoilov') === 'jasur ismoilov' && N.toLatin('Renée') === 'renee', [N.normalizeName('Jasur İsmoilov'), N.toLatin('Renée')]);

// ---- Levenshtein ----
ok('levenshtein klassik', N.levenshtein('kitten', 'sitting') === 3 && N.levenshtein('', 'abc') === 3 && N.levenshtein('abc', '') === 3
  && N.levenshtein('abc', 'abc') === 0 && N.levenshtein('flaw', 'lawn') === 2);
ok('levenshtein: almashtirish narxi berilsa', N.levenshtein('odil', 'udil', () => 0.5) === 0.5);
{ let symOk = true, triOk = true; const A = 'abcox';
  const rnd = (n, seed) => { let s = ''; for (let i = 0; i < n; i++) { seed = (seed * 1103515245 + 12345) % 2147483648; s += A[seed % A.length]; } return s; };
  for (let i = 0; i < 300; i++) { const a = rnd(i % 7, i + 1), b = rnd((i * 3) % 8, i + 7), c = rnd((i * 5) % 6, i + 13);
    if (N.levenshtein(a, b) !== N.levenshtein(b, a)) symOk = false;
    if (N.levenshtein(a, c) > N.levenshtein(a, b) + N.levenshtein(b, c)) triOk = false; }
  ok('levenshtein simmetrik', symOk); ok('levenshtein uchburchak tengsizligi', triOk); }
ok('wordSim: o/u yarim farq (Odil / Udil)', N.wordSim('odil', 'udil') === 0.875 && N.wordSim('abc', 'abc') === 1 && N.wordSim('', '') === 1);

// ---- Solishtirish ----
ok('so\'zlar tartibi muhim emas', sim("Xadicha Turg'unboyeva", T) === 1 && sim('Хадича Турғунбоева', T) === 1);
ok('simmetrik', [["Turg'unboyeva Hadicha", T], ['Xadicha Turgunboeva', T], ['Aliyev Jasur', T], ['Odil Rahimov', 'Udil Raximov']].every(([a, b]) => sim(a, b) === sim(b, a)));
ok('imlo xatolari — yuqori', sim('Odil Rahimov', 'Udil Raximov') >= 0.85 && sim('Otkir Karimov', "O'tkir Karimov") >= 0.85 && sim('Hadichaa Turgunboyeva', T) >= 0.9
  && sim('Turgunboyeva Hadicha Rustamovna', T) >= 0.85, [sim('Odil Rahimov', 'Udil Raximov'), sim('Otkir Karimov', "O'tkir Karimov")]);
ok('faqat ism mos — past (< 60%)', sim('Xadicha Aliyeva', T) < 0.6 && sim('Aliyeva Xadicha', T) < 0.6, sim('Xadicha Aliyeva', T));
ok('faqat familiya mos (aka-uka) — past (< 60%)', sim("Turg'unboyev Rustam", T) < 0.6 && sim('Karimov Jasur', 'Karimova Jasmina') < 0.6 && sim('Karimov Jasur', 'Karimov Javohir') < 0.6,
  [sim("Turg'unboyev Rustam", T), sim('Karimov Jasur', 'Karimova Jasmina'), sim('Karimov Jasur', 'Karimov Javohir')]);
ok('ikkalasi mos > faqat bittasi mos', sim("Turg'unboyeva Xadicha", T) > sim('Xadicha', T) && sim('Xadicha', T) > sim('Xadicha Aliyeva', T));
ok('bitta so\'z (faqat ism yozilgan) — o\'zi yetmaydi, lekin 50%+', sim('Xadicha', T) >= 0.5 && sim('Xadicha', T) < 0.6, sim('Xadicha', T));
ok('qisqa shakl (Jasur / Jasurbek, Malika / Malikaxon) — yuqori', sim('Karimov Jasur', 'Karimov Jasurbek') >= 0.85 && sim('Karimova Malika', 'Karimova Malikaxon') >= 0.85,
  [sim('Karimov Jasur', 'Karimov Jasurbek'), sim('Karimova Malika', 'Karimova Malikaxon')]);
ok('boshqa ism prefiksi (Ali / Alisher) — qisqa shakl emas', sim('Karimov Ali', 'Karimov Alisher') < 0.5, sim('Karimov Ali', 'Karimov Alisher'));
ok('tasodifiy o\'xshashlik (-ov) hisobga olinmaydi: ism bir xil, familiya begona — < 50%', ['Karimov', 'Sobirov', 'Rahimov', 'Yusupov'].every(f => sim('Aliyev Jasur', f + ' Jasur') < 0.5),
  ['Karimov', 'Sobirov', 'Rahimov', 'Yusupov'].map(f => sim('Aliyev Jasur', f + ' Jasur')));
ok('... va qarz = summa bonusi ham uni taklifga chiqarmaydi', N.pickSuggestions(N.rankByName('Aliyev Jasur', [{ name: 'Karimov Jasur' }, { name: 'Sobirov Jasur' }], { minName: 0 }), 1500000, () => ({ debt: 1500000 })).length === 0);
ok('bo\'sh / raqamli ism — 0', sim('', T) === 0 && sim('12345', T) === 0 && sim(T, null) === 0);

// ---- Summa bonusi ----
const sc = (n, i) => N.scoreCandidate(n, Object.assign({ amount: 1500000 }, i));
ok('qarz = summa -> +10%', Math.abs(sc(0.55, { debt: 1500000 }).score - 0.65) < 1e-9 && sc(0.55, { debt: 1500000 }).bonus === 0.10);
ok('oylik = summa -> +5%', Math.abs(sc(0.55, { debt: 300000, monthly: 1500000 }).score - 0.60) < 1e-9 && sc(0.55, { monthly: 1500000 }).bonus === 0.05);
ok('bonuslar qo\'shilmaydi (eng kattasi)', sc(0.7, { debt: 1500000, monthly: 1500000 }).bonus === 0.10);
ok('ism o\'xshamasa bonus 60% ga yetkazmaydi', sc(0.49, { debt: 1500000 }).score === 0.59 && sc(0.3, { debt: 1500000 }).score < 0.6 && sc(0.5, { debt: 1500000 }).score >= 0.6);
ok('qarz noma\'lum / summa 0 — bonus yo\'q', sc(0.7, { debt: null, monthly: null }).bonus === 0 && N.scoreCandidate(0.7, { amount: 0, debt: 0 }).bonus === 0);
ok('summa tiyin farqi yaxlitlanadi', sc(0.7, { debt: 1500000.4 }).bonus === 0.10 && sc(0.7, { debt: 1499999 }).bonus === 0);
ok('ball 100% dan oshmaydi', sc(1, { debt: 1500000 }).score === 1);

// ---- Maktab ro'yxatida: rankByName + pickSuggestions ----
const SCHOOL = [
  { id: 's1', name: "Turg'unboyeva Xadicha", debt: 1500000, monthly: 1500000 },
  { id: 's2', name: "Turg'unboyev Rustam", debt: 1500000, monthly: 1500000 },     // aka: faqat familiya
  { id: 's3', name: 'Aliyeva Xadicha', debt: 1500000, monthly: 1500000 },        // faqat ism
  { id: 's4', name: 'Karimova Malika', debt: 0, monthly: 1500000 },
  { id: 's5', name: 'Rahimov Odil', debt: 3000000, monthly: 1500000 },
  { id: 's6', name: 'Rahimova Odila', debt: 1500000, monthly: 1500000 },
  { id: 's7', name: 'Yusupov Sherzod', debt: 0, monthly: 1200000 },
  { id: 's8', name: '', debt: 0 }, { id: 's9', name: null },
];
const suggest = (payer, amount) => N.pickSuggestions(N.rankByName(payer, SCHOOL, { minName: 0.5, limit: 8 }), amount, it => it, { min: 0.6, limit: 3 });
const show = (payer, amount) => { const r = suggest(payer, amount);
  console.log(`  ${JSON.stringify(payer)} (${amount} so'm) -> ${r.length ? r.map(x => `${x.item.name} ${x.percent}%${x.bonus ? ' (+' + Math.round(x.bonus * 100) + '% summa)' : ''}`).join(', ') : 'taklif yo‘q (oddiy ro‘yxat)'}`); return r; };
console.log('Maktab ro\'yxatida takliflar:');
let r = show("Turg'unboyeva Hadicha", 1500000);
ok('to\'g\'ri o\'quvchi birinchi, aka/opa-singil yo\'q', r.length >= 1 && r[0].item.id === 's1' && r.every(x => x.item.id !== 's2' && x.item.id !== 's3'), r.map(x => x.item.id));
r = show('Турғунбоева Хадича', 1500000); ok('kirill to\'lovchi', r.length && r[0].item.id === 's1');
r = show('Xadicha Turgunboeva', 1500000); ok('teskari tartib, apostrofsiz', r.length && r[0].item.id === 's1');
r = show('Aliyev Jasur', 1500000); ok('mos o\'quvchi yo\'q -> taklif yo\'q', r.length === 0, r.map(x => x.item.name));
r = show('Odil Raximov', 3000000);
ok('Odil: qarz = summa ustun', r.length && r[0].item.id === 's5' && r[0].bonus === 0.10, r.map(x => [x.item.id, x.percent]));
ok('takliflar <= 3, >= 60%, kamayish tartibida', ['Odil Raximov', "Turg'unboyeva Hadicha", 'Xadicha', 'Rahimova'].every(p => { const x = suggest(p, 1500000);
  return x.length <= 3 && x.every(y => y.score >= 0.6) && x.every((y, i) => !i || x[i - 1].score >= y.score); }));
r = show('Xadicha', 1500000);
ok('faqat ism yozilgan: ikkala Xadicha teng (noaniq), faqat summa mos kelgani uchun', r.length === 2 && r[0].percent === r[1].percent && r.every(x => x.bonus === 0.10));
ok('faqat ism yozilgan, summa mos emas -> taklif yo\'q', suggest('Xadicha', 999000).length === 0);
ok('rankByName limit va minName', N.rankByName('Rahimov', SCHOOL, { limit: 1 }).length <= 1 && N.rankByName('Aliyev Jasur', SCHOOL).every(x => x.nameScore >= 0.5));
ok('rankByName: bo\'sh to\'lovchi ismi -> []', N.rankByName('', SCHOOL).length === 0 && N.rankByName('123', SCHOOL).length === 0 && N.rankByName(T, null).length === 0);
ok('kirish ma\'lumoti o\'zgartirilmaydi', JSON.stringify(SCHOOL[0]) === JSON.stringify({ id: 's1', name: "Turg'unboyeva Xadicha", debt: 1500000, monthly: 1500000 }));
{ const big = []; for (let i = 0; i < 3000; i++) big.push({ name: ['Aliyev', 'Karimova', 'Rahimov', "Turg'unboyev", 'Yusupova'][i % 5] + ' ' + ['Jasur', 'Malika', 'Odil', 'Xadicha', 'Sherzod', 'Madina'][i % 6] + (i % 7 ? '' : ' Rustam qizi') });
  const t0 = Date.now(); N.rankByName("Turg'unboyeva Hadicha", big); const ms = Date.now() - t0;
  ok('3000 o\'quvchi — tez (< 1.5 s)', ms < 1500, ms); }

// ---- Ko'rik (R8/R9) holatlari ----
// To'lovchi matnidagi izoh so'zlari, sinf/ID/raqamli bo'laklar ism balini yiqitmaydi (ilgari majburiy juftlanib ~3% bo'lardi)
const T3 = "Turg'unboyeva Xadicha Rustamovna";
ok('sinf / «uchun» / ID / so\'m — yalang ism bilan bir xil', ['Xadicha 5-A', 'Xadicha 5 «A»', 'Xadicha 11B', 'Xadicha uchun', "Xadicha uchun to'lov", 'IQ-0042 Xadicha',
  "Xadicha 1 500 000 so'm", 'Хадича 1 500 000 сўм', 'Xadicha qizim uchun', 'Хадича оплата за обучение', 'Xadicha 2026-yil'].every(p => Math.abs(sim(p, T) - sim('Xadicha', T)) < 1e-9),
  ['Xadicha 5-A', 'IQ-0042 Xadicha', 'Хадича оплата за обучение'].map(p => sim(p, T)));
ok('izohdagi so\'zlar (sinf, oy nomi) — ism oxirida bo\'lsa ham topiladi', sim("5-A sinf oktyabr oyi uchun Turg'unboyeva Xadicha", T) === 1
  && sim('Октябрь ойи учун Турғунбоева Хадича', T) === 1, sim("5-A sinf oktyabr oyi uchun Turg'unboyeva Xadicha", T));
ok('3 so\'zli yozuv + to\'liq ism + ortiqcha so\'z / ID / hex kod — yuqori (95%)', ["Turg'unboyeva Xadicha", "Turg'unboyeva Xadicha 5-A", "Turg'unboyeva Xadicha uchun",
  "Turg'unboyeva Xadicha IQ-0042", "Turg'unboyeva Xadicha 3FA9C0B21DE7", "Турғунбоева Хадича оплата за обучение"].every(p => sim(p, T3) >= 0.9),
  ["Turg'unboyeva Xadicha 3FA9C0B21DE7", "Турғунбоева Хадича оплата за обучение"].map(p => sim(p, T3)));
ok('nameTokens: raqamli bo\'laklar va izoh so\'zlari tashlanadi, bosh harf qoladi; normalizeName o\'zgarmaydi', JSON.stringify(N.nameTokens('Xadicha 5-A uchun T.')) === '["xadicha","t"]'
  && N.normalizeName('Xadicha uchun') === 'xadicha uchun' && N.nameTokens('Oktyabr uchun to\'lov').length === 0, N.nameTokens('Xadicha 5-A uchun T.'));
ok('faqat izoh so\'zlari — nomzod yo\'q', N.rankByName("Oktyabr oyi uchun to'lov", SCHOOL).length === 0);
// Bosh harf (1–2 harf: X., J., Sh., Ш., Ю., Я., Ё.) — TEKSHIRILADI: mos — o'rtacha dalil (~72%), zid — rad (~3%)
ok('mos bosh harf: familiya + bosh harf ~72% (yalang familiyadan yuqori)', ["Turg'unboyeva X.", "X. Turg'unboyeva", 'Xadicha T.', 'Xadicha T. uchun'].every(p => sim(p, T) > 0.7 && sim(p, T) < 0.75)
  && sim("Turg'unboyeva X.", T) > sim("Turg'unboyeva", T), ["Turg'unboyeva X.", 'Xadicha T.'].map(p => sim(p, T)));
ok('zid bosh harf: aka-uka/adash rad', sim('Karimov J.', 'Karimov Bekzod') < 0.1 && sim('Xadicha R.', T) < 0.1 && sim('Xadicha T. uchun', 'Aliyeva Xadicha') < 0.1,
  [sim('Karimov J.', 'Karimov Bekzod'), sim('Xadicha R.', T)]);
ok('ikki harfli bosh harflar (Sh., Ш., Ю., Ya., Ё.)', sim('Karimov Sh.', 'Karimov Shohruh') > 0.7 && sim('Каримов Ш.', 'Karimov Sherzod') > 0.7 && sim('Юсупова Ю.', 'Yusupova Yulduz') > 0.7
  && sim('Yusupova Ya.', 'Yusupova Yasmina') > 0.7 && sim('Турсунов Ё.', 'Tursunov Yoqub') > 0.7 && sim('Karimov Sh.', 'Karimov Jasur') < 0.1);
ok('3 so\'zli yozuv: otasining ismi bosh harfi ham mos keladi', sim("Turg'unboyeva Xadicha R.", T3) >= 0.75, sim("Turg'unboyeva Xadicha R.", T3));
{ const K = [{ id: 'a', name: 'Karimov Aziz' }, { id: 'b', name: 'Karimov Bobur' }, { id: 'd', name: 'Karimov Doniyor' }, { id: 'j', name: 'Karimov Jasur' }];
  const r = N.pickSuggestions(N.rankByName('Karimov J.', K, { limit: 1000 }), 1500000, () => ({ debt: 1500000 }));
  ok('«Karimov J.»: faqat Jasur taklif qilinadi (qarz = summa bo\'lgan aka-ukalar emas)', r.length === 1 && r[0].item.id === 'j', r.map(x => [x.item.id, x.percent])); }
// O'quvchi yozuvi tozalanmaydi: koreyscha «O», «Avgust» ismi — so'z; to'lovchi matnida esa izoh so'zi faqat ismda yo'q bo'lsa tashlanadi
ok('koreyscha «O»: to\'liq mos, boshqa familiya bilan adashmaydi', sim('O Viktoriya', 'O Viktoriya Sergeyevna') >= 0.9 && sim('О Виктория', 'O Viktoriya') === 1
  && sim('O Viktoriya', 'Kim Viktoriya') < 0.1 && sim('Viktoriya', 'O Viktoriya') < 0.6, [sim('O Viktoriya', 'Kim Viktoriya'), sim('Viktoriya', 'O Viktoriya')]);
ok('«Avgust» — ism bo\'lsa saqlanadi, izoh bo\'lsa tashlanadi', sim('Karimov Avgust', 'Karimov Avgust') === 1 && sim('Karimov R. uchun', 'Karimov Avgust') < 0.1
  && Math.abs(sim('Xadicha avgust uchun', T) - sim('Xadicha', T)) < 1e-9);
ok('asimmetriya hujjatlangan: (to\'lovchi, yozuv) — yozuvdagi bitta harf tashlanmaydi', sim('Viktoriya', 'O Viktoriya') < sim('O Viktoriya', 'O Viktoriya'));
// Barcha apostrof turlari (‛ ʹ ʽ ʾ ʿ ˈ ꞌ ＇ ՚ ham)
['‛', 'ʹ', 'ʽ', 'ʾ', 'ʿ', 'ˈ', 'ꞌ', '＇', '՚', 'ˊ', 'ˋ', '‵', '“', '”', '"', 'ˮ', '΄', '˝', '″'].forEach(a => ok(`apostrof ${JSON.stringify(a)} -> '`,
  N.normalizeName(`Turg${a}unboyeva Xadicha`) === "turg'unboeva xadicha" && sim(`O${a}tkir Karimov`, "O'tkir Karimov") === 1, N.normalizeName(`Turg${a}unboyeva Xadicha`)));
ok('ko\'rinmas belgilar (yumshoq tire, ZWSP…) so\'zni bo\'lmaydi', ['\u00AD', '\u200B', '\u200C', '\u200D', '\u2060', '\uFEFF'].every(c => N.normalizeName(`Turg${c}unboyeva`) === 'turgunboeva'));
// Kirill «сҳ» = s'h (Исҳоқ = Is'hoq), «ш» emas
ok('сҳ -> s\'h (toLatin), h->x bilan Isxoqov ga teng', N.toLatin('Исҳоқов') === "is'hoqov" && N.normalizeName('Исҳоқов') === 'isxoqov' && N.normalizeName("Is'hoqov") === 'isxoqov'
  && N.normalizeName('Исхоқов') === 'isxoqov' && N.normalizeName('Isxoqov') === 'isxoqov' && N.normalizeName('Шерзод') === 'sherzod', [N.toLatin('Исҳоқов'), N.normalizeName('Исҳоқов')]);
ok('сҳ: to\'liq ism 100%, norasmiy «Ishoqov» ham taklifga yetadi', sim('Исҳоқов Жасур', 'Isxoqov Jasur') === 1 && sim('Исҳоқова Мадина', "Is'hoqova Madina") === 1
  && sim('Ishoqov Jasur', 'Isxoqov Jasur') >= 0.8, sim('Ishoqov Jasur', 'Isxoqov Jasur'));
// shortlist: bonus (+10%) bilan top-3 ga kira oladigan barcha nomzodlar qoladi — ro'yxat tartibiga bog'liq emas
{ const many = []; ['Aliyeva', 'Karimova', 'Yusupova', 'Rahimova', 'Nazarova', 'Saidova', 'Ergasheva', 'Qodirova', 'Toshmatova', 'Sobirova', 'Olimova', 'Umarova']
    .forEach((f, i) => many.push({ id: 'm' + i, name: f + ' Xadicha', debt: i === 11 ? 1500000 : 0, monthly: 1500000 }));
  const ranked = N.rankByName('Xadicha', many, { limit: 1000 }), sl = N.shortlist(ranked, { keep: 3, maxBonus: 0.10 });
  ok('shortlist: 12 teng adash — hammasi qoladi (12-si ham)', ranked.length === 12 && sl.length === 12 && sl.some(c => c.item.id === 'm11'), [ranked.length, sl.length]);
  const pick = N.pickSuggestions(sl, 1500000, it => it, { min: 0.6, limit: 3 });
  ok('shortlist + bonus: qarzi summaga teng 12-o\'quvchi birinchi (67%)', pick[0].item.id === 'm11' && pick[0].percent === 67, pick.map(x => [x.item.id, x.percent]));
  const mixed = N.rankByName("Turg'unboyeva Hadicha", [{ name: "Turg'unboyeva Xadicha" }, { name: 'Turgunboyeva Xadicha' }, { name: "Turg'unboyeva Xadicha Rustamovna" }, { name: 'Aliyeva Xadicha' }, { name: 'Xadicha Turgunova' }], { limit: 1000 });
  const ms = N.shortlist(mixed, { keep: 3, maxBonus: 0.10 });
  ok('shortlist: 3-o\'rindan 10% dan ko\'p past nomzodlar tashlanadi', ms.length === 3 && ms.every(c => c.nameScore >= mixed[2].nameScore - 0.10 - 1e-9), [mixed.map(c => Math.round(c.nameScore * 100)), ms.length]);
  ok('shortlist: cap', N.shortlist(ranked, { keep: 3, cap: 5 }).length === 5 && N.shortlist([], {}).length === 0); }

// ---- Brauzer yo'li (UMD): module yo'q -> globalThis.IqrorNameMatch ----
{ const src = fs.readFileSync(path.join(__dirname, '..', 'sb', 'name-match.js'), 'utf8'); const ctx = {}; vm.createContext(ctx); vm.runInContext(src, ctx);
  ok('brauzerda globalThis.IqrorNameMatch', !!ctx.IqrorNameMatch && ctx.IqrorNameMatch.nameSimilarity("Turg'unboyeva Hadicha", T) === 1);
  ok('tashqi kutubxona yo\'q (require/import yo\'q)', !/\brequire\s*\(|\bimport\s/.test(src.replace(/\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, ''))); }

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
