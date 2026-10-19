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
// O'quvchi yozuvi tozalanmaydi: koreyscha «O», «Avgust» ismi — so'z; to'lovchi matnida esa izoh so'zi faqat ismda yo'q bo'lsa tashlanadi.
//   Nuqtasiz yakka harf («O», «5-sinf B», «в») — ismdagi so'zga aynan teng bo'lsagina hisobga olinadi: «O Viktoriya» ↔ «Kim Viktoriya»
//   = faqat ism mos (yalang «Viktoriya» bilan bir xil, < 60%) — sinf harfi 3 so'zli yozuvni yiqitmasligi uchun (R10).
ok('koreyscha «O»: to\'liq mos; boshqa familiya — faqat ism mos darajasida (< 60%)', sim('O Viktoriya', 'O Viktoriya Sergeyevna') >= 0.9 && sim('О Виктория', 'O Viktoriya') === 1
  && sim('O Viktoriya', 'Kim Viktoriya') < 0.6 && Math.abs(sim('O Viktoriya', 'Kim Viktoriya') - sim('Viktoriya', 'Kim Viktoriya')) < 1e-9 && sim('Viktoriya', 'O Viktoriya') < 0.6,
  [sim('O Viktoriya', 'Kim Viktoriya'), sim('Viktoriya', 'O Viktoriya')]);
{ const r = N.pickSuggestions(N.rankByName('O Viktoriya', [{ id: 'k', name: 'Kim Viktoriya' }, { id: 'o', name: 'O Viktoriya Sergeyevna' }], { limit: 1000 }), 1500000, it => ({ debt: it.id === 'k' ? 1500000 : 0 }));
  ok('«O Viktoriya»: O Viktoriya birinchi (qarzi summaga teng Kim Viktoriya emas)', r.length >= 1 && r[0].item.id === 'o' && r[0].percent >= 90 && r.every(x => x.item.id === 'o' || x.percent < 75),
    r.map(x => [x.item.id, x.percent])); }
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

// ---- Ko'rik (R10) holatlari ----
// Raqamdan (ID, telefon, summa) keyin yozilgan ism kesilmaydi: apostrofli ism (Ra'no, Jo'ra, G'ayrat, O'tkir) va qisqa ism (Ali, Lola)
['\'', '’', '‘', '`', '´', 'ʻ', 'ʼ'].forEach(a => ok(`raqamdan keyin apostrofli ism (${JSON.stringify(a)}) kesilmaydi`, sim(`IQ-0042 Ra${a}no Karimova`, "Karimova Ra'no") === 1
  && sim(`IQ-0042 Ra${a}no Karimova`, 'Karimova Nodira') < 0.1, [sim(`IQ-0042 Ra${a}no Karimova`, "Karimova Ra'no"), sim(`IQ-0042 Ra${a}no Karimova`, 'Karimova Nodira')]));
ok('ID / telefon / summa + apostrofli ism — 100%', sim("998901112233 Jo'ra Karimov", "Karimov Jo'ra") === 1 && sim("998901112233 Jo'ra Karimov", 'Karimov Ravshan') < 0.1
  && sim("IQ-0042 Turg'unboyeva Xadicha", T) === 1 && sim("1 500 000 Ra'no Karimova", "Karimova Ra'no") === 1 && sim("IQ-0042 G'ayrat Karimov", "Karimov G'ayrat") === 1
  && sim("IQ-0042 O'tkir Karimov", "Karimov O'tkir") === 1 && sim("IQ-0042 Mas'ud Karimov", "Karimov Mas'ud") === 1, sim("IQ-0042 Turg'unboyeva Xadicha", T));
ok('raqamdan keyin bo\'shliq bilan yozilgan qisqa ism — ism (kesilmaydi)', ['IQ-0042 Ali Karimov', '998901112233 Ali Karimov', '1 500 000 Ali Karimov', 'Karimov Ali-5', 'Karimov Ali5',
  'No 5 Ali Karimov'].every(p => sim(p, 'Karimov Ali') === 1) && sim('IQ-0042 Lola Karimova', 'Karimova Lola') === 1 && sim('IQ-0042 Lola Karimova', 'Karimova Malika') < 0.15
  && sim('No 5 Ali Karimov', 'Karimov Nodir') < 0.1 && sim('5 Юлия Ким', 'Ким Юлия') === 1 && sim('IQ-0042 Li Viktoriya', 'Li Viktoriya') === 1,
  ['IQ-0042 Ali Karimov', 'No 5 Ali Karimov'].map(p => sim(p, 'Karimov Ali')));
ok('nameTokens: raqamdan keyingi ism qoladi', JSON.stringify(N.nameTokens('998901112233 Ali')) === '["ali"]' && JSON.stringify(N.nameTokens('IQ-0042 Lola')) === '["lola"]'
  && JSON.stringify(N.nameTokens("IQ-0042 Ra'no")) === '["ra\'no"]', [N.nameTokens('998901112233 Ali'), N.nameTokens('IQ-0042 Lola')]);
{ const fam = [{ id: 'n', name: 'Karimova Nodira' }, { id: 'r', name: "Karimova Ra'no" }], debt = () => ({ debt: 1500000 });
  const r = N.pickSuggestions(N.rankByName("IQ-0042 Ra'no Karimova", fam, { limit: 1000 }), 1500000, debt);
  ok('opa-singil (ikkalasining qarzi = summa): faqat Ra\'no taklif qilinadi', r.length === 1 && r[0].item.id === 'r' && r[0].percent === 100, r.map(x => [x.item.id, x.percent]));
  const v = N.pickSuggestions(N.rankByName('998901112233 Ali Karimov', [{ id: 'v', name: 'Karimov Vali' }, { id: 'a', name: 'Karimov Ali' }], { limit: 1000 }), 1500000, debt);
  ok('aka-uka Ali / Vali: Ali birinchi (100%)', v.length >= 1 && v[0].item.id === 'a' && v[0].percent === 100 && v.every((x, i) => !i || x.percent < 100), v.map(x => [x.item.id, x.percent])); }
// Bosh harf «O'.» / «Ў.» = u (o' = u qoidasi), «O.» — O yoki O' bilan; «E.» / «Е.» — e yoki ye bilan (Yelena, Yevgeniy)
ok("bosh harf O'. / O‘. / Ў. / U. — O'tkir (Ўткир) ga mos, Otabek/Ойбек ga zid", ["Karimov O'.", 'Karimov O‘.', 'Karimov Oʻ.', 'Karimov U.'].every(p => sim(p, "Karimov O'tkir") > 0.7)
  && sim('Каримов Ў.', 'Каримов Ўткир') > 0.7 && sim('Ахмедова Ў.', 'Ахмедова Ўғилой') > 0.7 && sim("Karimov O'.", 'Karimov Otabek') < 0.1 && sim('Каримов Ў.', 'Каримов Ойбек') < 0.1,
  [sim("Karimov O'.", "Karimov O'tkir"), sim('Каримов Ў.', 'Каримов Ўткир'), sim("Karimov O'.", 'Karimov Otabek')]);
ok('bosh harf O. (apostrofsiz) — O va O\' ga mos', sim('Karimov O.', "Karimov O'tkir") > 0.7 && sim('Karimov O.', 'Karimov Otabek') > 0.7 && sim('Karimov O.', 'Karimov Jasur') < 0.1);
ok('bosh harf E. / Е. / Ye. — Yelena, Elmira, Евгений (yev -> ev)', sim('Karimova E.', 'Karimova Yelena') > 0.7 && sim('Karimova E.', 'Karimova Elmira') > 0.7 && sim('Иванов Е.', 'Иванов Евгений') > 0.7
  && sim('Иванов Е.', 'Ivanov Yevgeniy') > 0.7 && sim('Ivanov Ye.', 'Ivanov Yevgeniy') > 0.7 && sim('Karimova E.', 'Karimova Malika') < 0.1,
  [sim('Karimova E.', 'Karimova Yelena'), sim('Иванов Е.', 'Иванов Евгений')]);
{ const r = N.pickSuggestions(N.rankByName("Karimov O'.", [{ id: 'ot', name: 'Karimov Otabek' }, { id: 'ut', name: "Karimov O'tkir" }], { limit: 1000 }), 1500000, () => ({ debt: 1500000 }));
  const c = N.pickSuggestions(N.rankByName('Каримов Ў.', [{ id: 'oy', name: 'Каримов Ойбек' }, { id: 'ut', name: 'Каримов Ўткир' }], { limit: 1000 }), 1500000, () => ({ debt: 1500000 }));
  ok("«Karimov O'.» / «Каримов Ў.»: faqat O'tkir taklif qilinadi", r.length === 1 && r[0].item.id === 'ut' && c.length === 1 && c[0].item.id === 'ut', [r.map(x => x.item.id), c.map(x => x.item.id)]); }
// Nuqtasiz yakka harf (sinf harfi «6-sinf B», «5 класс А», ruscha «и», xato «X adicha») — bosh harf EMAS: 3 so'zli yozuvni yiqitmaydi
ok('sinf harfi / yakka harf 3 so\'zli yozuvni yiqitmaydi (95%)', ["Turg'unboyeva Xadicha 6-sinf B", 'Турғунбоева Хадича 5 класс А', "Turg'unboyeva Xadicha (A sinf)",
  "Turg'unboyeva Xadicha 6 sinf «B»", "Turg'unboyeva Xadicha A-sinf"].every(p => sim(p, T3) >= 0.9) && sim('Oybekov Abdulloh 3-sinf B', 'Oybekov Abdulloh Xojiakbar') >= 0.9
  && sim('Karimov Ali 5-sinf A', 'Karimov Ali Valiyevich') >= 0.9 && sim("Turg'unboyeva X adicha", T3) >= 0.75,
  ["Turg'unboyeva Xadicha 6-sinf B", 'Турғунбоева Хадича 5 класс А', "Turg'unboyeva X adicha"].map(p => sim(p, T3)));
ok('sinf harfi B — Bobojonova bilan bosh harf sifatida mos kelmaydi', Math.abs(sim('Xadicha 6-sinf B', 'Bobojonova Xadicha') - sim('Xadicha 6-sinf B', T)) < 1e-9
  && Math.abs(sim('Xadicha 6-sinf B', T) - sim('Xadicha', T)) < 1e-9, [sim('Xadicha 6-sinf B', 'Bobojonova Xadicha'), sim('Xadicha 6-sinf B', T)]);
ok('nameTokens: nuqtasiz yakka harf tashlanadi, aniq bosh harf qoladi', JSON.stringify(N.nameTokens('Karimov Ali 5-sinf A')) === '["karimov","ali"]'
  && JSON.stringify(N.nameTokens('Karimov A.')) === '["karimov","a"]' && JSON.stringify(N.nameTokens('Karimov A')) === '["karimov"]', [N.nameTokens('Karimov Ali 5-sinf A'), N.nameTokens('Karimov A')]);
// Faqat izoh (2+ izoh so'zi: «Avgust oyi uchun to'lov») — oy nomi ism emas; yakka «Avgust» — shu ismli o'quvchi uchun ism
ok('faqat izoh matni — Avgust/May ismli o\'quvchi taklif qilinmaydi', sim("Avgust oyi uchun to'lov", 'Karimov Avgust') === 0 && sim("May oyi uchun to'lov", 'Kim May') === 0
  && sim('Оплата за август', 'Karimov Avgust') === 0 && N.rankByName("Avgust oyi uchun to'lov", [{ name: 'Karimov Avgust' }, { name: 'Kim May' }]).length === 0);
ok('«Karimov Jasur avgust uchun»: Jasur 100%, ukasi Avgust emas', sim('Karimov Jasur avgust uchun', 'Karimov Jasur') === 1 && sim('Karimov Jasur avgust uchun', 'Karimov Avgust') < 0.1,
  sim('Karimov Jasur avgust uchun', 'Karimov Avgust'));
ok('nameTokens(matn, ism) — solishtirish bilan bir xil qoida', JSON.stringify(N.nameTokens('Avgust')) === '[]' && JSON.stringify(N.nameTokens('Avgust', 'Karimov Avgust')) === '["avgust"]'
  && JSON.stringify(N.nameTokens('Avgust', 'Saidova Kamola')) === '[]' && JSON.stringify(N.nameTokens("Avgust oyi uchun to'lov", 'Karimov Avgust')) === '[]'
  && JSON.stringify(N.nameTokens('O Viktoriya', 'O Viktoriya Sergeyevna')) === '["o","viktoriya"]' && Math.abs(sim('Avgust', 'Karimov Avgust') - sim('Xadicha', T)) < 1e-9);
// Qo'shtirnoq / ko'rinmas belgi so'zlar ORASIDA (bo'shliqsiz) — ajratadi; so'z ICHIDA — apostrof / o'chiriladi
ok('qo\'shtirnoq / ZWSP / LRM so\'zlar orasida — so\'zlar ajraladi (100%)', ["Turg'unboyeva«Xadicha»", "«Turg'unboyeva»Xadicha", 'Turg\'unboyeva"Xadicha"', "Xadicha\u200BTurg'unboyeva",
  "Xadicha\u200ETurg'unboyeva", "Xadicha\u2063Turg'unboyeva"].every(p => sim(p, T) === 1) && sim('Turg”unboyeva Xadicha', T) === 1,
  ["Turg'unboyeva«Xadicha»", "Xadicha\u200BTurg'unboyeva"].map(p => sim(p, T)));
// Kirill «сын» izoh so'zi EMAS (koreyscha familiya Син / Sin bilan to'qnashadi)
ok('«Син Виктория»: Shin/Sin ga mos, Kim Viktoriya ga emas', sim('Син Виктория', 'Shin Viktoriya') > 0.7 && sim('Син Виктория', 'Kim Viktoriya') < 0.15 && sim('Sin Viktoriya', 'Kim Viktoriya') < 0.15
  && sim('Sin Viktoriya', 'Sin Viktoriya') === 1 && JSON.stringify(N.nameTokens('Син')) === '["sin"]', [sim('Син Виктория', 'Shin Viktoriya'), sim('Син Виктория', 'Kim Viktoriya')]);

// ---- Ko'rik (R11) holatlari ----
const R3 = 'Karimov Jasur Rustamovich';
// Yopishgan bosh harflar «J.O.» / «Ж.О.» / «М.А.»: ikkinchisi — otasining ismi bosh harfi (3 so'zli yozuvda tekshiriladi)
ok('yopishgan bosh harflar «J.O.»: otasining ismi bosh harfi tekshiriladi (amakivachcha rad)', sim('Karimov J.O.', 'Karimov Javohir Olimovich') > 0.6
  && sim('Karimov J.O.', 'Karimov Jasur Bahodirovich') < 0.1 && sim('Каримов Ж.О.', 'Karimov Jasur Bahodirovich') < 0.1 && sim('J.O. Karimov', 'Karimov Javohir Olimovich') > 0.6
  && sim('Ivanova M.A.', 'Ivanova Mariya Aleksandrovna') > 0.6 && sim('Ivanova M.A.', 'Ivanova Milana Sergeyevna') < 0.1,
  [sim('Karimov J.O.', 'Karimov Javohir Olimovich'), sim('Karimov J.O.', 'Karimov Jasur Bahodirovich'), sim('Ivanova M.A.', 'Ivanova Milana Sergeyevna')]);
ok('2-bosh harf 2 so\'zli yozuvda hisobga olinmaydi («Karimov J.R.» — Jasur, aka-uka Ravshan emas)', sim('Karimov J.R.', 'Karimov Jasur') > 0.7 && sim('Karimov J.R.', 'Karimov Ravshan') < 0.1
  && sim('Karimov J. R.', 'Karimov Ravshan') < 0.1 && sim('A.B. Karimov', 'Karimov Bobur') < 0.1, [sim('Karimov J.R.', 'Karimov Ravshan'), sim('A.B. Karimov', 'Karimov Bobur')]);
{ const r = N.pickSuggestions(N.rankByName('Karimov J.O.', [{ id: 'b', name: 'Karimov Jasur Bahodirovich' }, { id: 'o', name: 'Karimov Javohir Olimovich' }], { limit: 1000 }), 1500000,
    it => ({ debt: it.id === 'b' ? 1500000 : 3000000 }));
  ok('«Karimov J.O.»: faqat Javohir Olimovich (qarzi summaga teng Jasur Bahodirovich emas)', r.length === 1 && r[0].item.id === 'o', r.map(x => [x.item.id, x.percent])); }
ok('bosh harf tartib bilan: nuqtasiz sinf harfi «A» oldingi «A.» tufayli bosh harf bo\'lib qolmaydi', sim('Karimov A. 5-sinf A', 'Karimov Aziz Bahodirovich') > 0.6,
  sim('Karimov A. 5-sinf A', 'Karimov Aziz Bahodirovich'));
// «Y.» — Ye… / Yev… ismlar bilan ham; «Yo.» / «Ё.» — Yo' (= yu) bilan ham
ok('«Y.» — Yelena / Yegor / Yevgeniy ga mos, Elbek ga zid', sim('Petrova Y.', 'Petrova Yelena') > 0.7 && sim('Karimov Y.', 'Karimov Yegor') > 0.7 && sim('Karimov Y.', 'Karimov Yevgeniy') > 0.7
  && sim('Karimov Y.', 'Karimov Elbek') < 0.1, [sim('Petrova Y.', 'Petrova Yelena'), sim('Karimov Y.', 'Karimov Yevgeniy')]);
ok("«Yo.» / «Ё.» — Yo'ldosh ga mos", sim('Karimov Yo.', "Karimov Yo'ldosh") > 0.7 && sim('Каримов Ё.', "Karimov Yo'ldosh") > 0.7 && sim('Karimov Yo.', 'Karimov Jasur') < 0.1);
// Sinf harfi nuqta bilan ham («6-sinf B.», «5 класс А.», «5 кл. А») — bosh harf emas
ok('sinf harfi nuqta bilan — bosh harf emas (3 so\'zli yozuv 95%)', ["Turg'unboyeva Xadicha 6-sinf B.", "Turg'unboyeva Xadicha 6 sinf B.", "Turg'unboyeva Xadicha, 6-sinf, B.",
  'Турғунбоева Хадича 5 класс А.', 'Турғунбоева Хадича 5-синф Б.', "6-sinf B. Turg'unboyeva Xadicha", 'Турғунбоева Хадича 5 кл. А', "Turg'unboyeva Xadicha 5 кл."].every(p => sim(p, T3) >= 0.9),
  ["Turg'unboyeva Xadicha 6-sinf B.", 'Турғунбоева Хадича 5 кл. А'].map(p => sim(p, T3)));
{ const r = N.pickSuggestions(N.rankByName('Karimov Jasur 5-sinf A.', [{ id: 'j', name: 'Karimov Jasur Valiyevich' }, { id: 'a', name: 'Karimov Ali' }], { limit: 1000 }), 1500000, () => ({ debt: 1500000 }));
  const x = N.pickSuggestions(N.rankByName('Xadicha 6-sinf B.', [{ id: 't', name: T }, { id: 'b', name: 'Bobojonova Xadicha' }], { limit: 1000 }), 1500000, () => ({ debt: 1500000 }));
  ok('«Karimov Jasur 5-sinf A.»: faqat Jasur; «Xadicha 6-sinf B.»: B harfi Bobojonova\'ni ustun qilmaydi', r.length === 1 && r[0].item.id === 'j' && x.length === 2 && x[0].percent === x[1].percent,
    [r.map(y => [y.item.id, y.percent]), x.map(y => [y.item.id, y.percent])]); }
ok('«Popov N. 5 класс А»: «N.» — bosh harf (raqam belgisi emas); «No 5» / «Nr. 12» — raqam belgisi', sim('Popov N. 5 класс А', 'Popov Nikita') > 0.7
  && ['No 5 Karimov Ali', 'No. 5 Karimov Ali', 'N 5 Karimov Ali', 'Nr. 12 Karimov Ali'].every(p => sim(p, 'Karimov Ali Valiyevich') >= 0.9));
// Otasining ismi bilan yozilgan (3 so'zli) yozuv + to'lovchining ortiqcha so'zi — majburiy juftlanmaydi
ok('3 so\'zli yozuv + ortiqcha so\'z (tel., okt, кл., тыс., kun, chi, Toshkent, питание…) — 90%+', ['tel.901234567', '12 okt', '5 кл.', '1 500 тыс. сум', '10 kun', '5 chi sinf',
  'Toshkent', 'tushlik', "o'qishga", "to'lovlar", 'ukam uchun', 'питание', 'transport'].every(x => sim('Karimov Jasur ' + x, R3) >= 0.9)
  && sim('Оплата за ребенка Каримов Жасур', 'Karimov Jasur Bahodirovich') >= 0.9 && sim('Karimova Malika va Karimov Ali uchun', 'Karimova Malika Bahodirovna') >= 0.8,
  ['Toshkent', 'питание', '12 okt'].map(x => sim('Karimov Jasur ' + x, R3)));
ok('... aka-uka / adash baribir rad etiladi', sim('Karimov Bekzod Bahodirovich', 'Karimov Jasur Bahodirovich') < 0.15 && sim('Karimov Bekzod', 'Karimov Jasur Bahodirovich') < 0.1
  && sim('Aliyeva Xadicha', T3) < 0.1 && sim('Karimov J. B.', 'Karimov Jasur Olimovich') < 0.1 && sim('Karimov Bekzod Toshkent', R3) < 0.1,
  [sim('Karimov Bekzod Bahodirovich', 'Karimov Jasur Bahodirovich'), sim('Karimov Bekzod Toshkent', R3)]);
ok('«F.I.O.» / «Ф.И.О.:» yorlig\'i — ism emas', ['F.I.O. Karimov Jasur', 'Ф.И.О.: Каримов Жасур', 'F.I.SH. Karimov Jasur', 'F. I. O. Karimov Jasur'].every(p => sim(p, R3) >= 0.9));
// Uzun raqamga (ID, telefon) yopishgan ism — ism; qisqa raqamga yopishgan sinf harfi / izoh so'zi — olib tashlanadi
ok('«IQ-0042-Ali Karimov», «998901112233Ali» — ism; «5-A», «11B», «2026-yil», «1500000so\'m» — yo\'q', sim('IQ-0042-Ali Karimov', 'Karimov Ali') === 1
  && sim('IQ-0042-Ali Karimov', 'Karimov Vali') < 0.75 && sim('998901112233Ali Karimov', 'Karimov Ali') === 1 && sim('IQ-0042.Lola Karimova', 'Karimova Lola') === 1
  && ['5-A', '11B', '2026-yil', "1500000so'm", '10-sinf', '2026y.', '2026-oy'].every(x => sim('Karimov Ali ' + x, 'Karimov Ali Valiyevich') >= 0.9),
  [sim('IQ-0042-Ali Karimov', 'Karimov Ali'), sim('Karimov Ali 2026-yil', 'Karimov Ali Valiyevich')]);
// Otasining ismi bosh harfi: to'liq ismdan keyin («Karimov Jasur R.») yoki yopishgan («J.R.») — mos bo'lsa tasdiq, zid bo'lsa amakivachcha rad / ⚠️
ok('«Karimov Jasur R.» / «Karimov J.R.» ↔ … Rustamovich (mos) va … Bahodirovich (amakivachcha)', sim('Karimov Jasur R.', R3) >= 0.9
  && sim('Karimov Jasur R.', 'Karimov Jasur Bahodirovich') <= 0.64 && sim('Karimov J.R.', R3) > 0.65 && sim('Karimov J.R.', 'Karimov Jasur Bahodirovich') < 0.1,
  [sim('Karimov Jasur R.', R3), sim('Karimov Jasur R.', 'Karimov Jasur Bahodirovich'), sim('Karimov J.R.', R3)]);
// Manzil: shahar / tuman nomi va uning qisqartmasi («Toshkent sh.», «Chilonzor t.», matn boshidagi «г. Ташкент») — ism emas, bosh harf emas
ok('manzil («Toshkent sh.», «Chilonzor t.», «г. Ташкент») — ism / bosh harf emas', sim('Em Nikita Toshkent sh.', 'Em Nikita Vladimirovich') >= 0.9
  && sim('Em Nikita Toshkent sh.', 'Shin Nikita Viktorovich') < 0.6 && sim('Karimov Jasur Toshkent sh.', 'Karimov Shohruh Anvarovich') < 0.1
  && sim('г. Ташкент Каримов Жасур', 'Karimov Jasur') === 1 && sim('Toshkent sh., Chilonzor t., Karimov Jasur', R3) >= 0.9
  && sim('Karimov Sh. Toshkent', 'Karimov Shohruh') > 0.7 && sim('Каримов Г. Ташкент', "Karimov G'ayrat") > 0.7 && sim('Karimov Jasur t. Chilonzor', R3) >= 0.9,
  [sim('Em Nikita Toshkent sh.', 'Shin Nikita Viktorovich'), sim('Karimov Sh. Toshkent', 'Karimov Shohruh')]);
ok('noma\'lum joy + qisqartma: bosh harf bilan juftlangan begona familiya (Shin) ≤ 64%, to\'g\'ri o\'quvchi undan yuqori', sim('Em Nikita Gazalkent sh.', 'Shin Nikita Viktorovich') <= 0.64
  && sim('Em Nikita Gazalkent sh.', 'Em Nikita Vladimirovich') > sim('Em Nikita Gazalkent sh.', 'Shin Nikita Viktorovich'),
  [sim('Em Nikita Gazalkent sh.', 'Shin Nikita Viktorovich'), sim('Em Nikita Gazalkent sh.', 'Em Nikita Vladimirovich')]);
ok('ruscha yakka harf («в 5 классе») ishonchni pasaytirmaydi', sim('Karimov J. в 5 классе', 'Karimov Jasur') > 0.7 && sim('Каримов Жасур в 5 классе', 'Karimov Jasur') === 1,
  sim('Karimov J. в 5 классе', 'Karimov Jasur'));
ok('bosh harf roli: «Toshmatov Jasur A.» Ahmad\'ga, «Karimov Z.» aka-uka … Zafarovich\'ga mos emas; «… G.; 1-chorak» — ism bosh harfi',
  sim('Toshmatov Jasur A.', "Toshmatov Ahmad Ulug'bekovich") < 0.1 && sim('Toshmatov Jasur A.', 'Toshmatov Jasur Akmalovich') >= 0.9
  && sim('Karimov Z.', 'Karimov Jasur Zafarovich') < 0.1 && sim('Karimov Z.', 'Karimov Zafar Rustamovich') > 0.6 && sim('Karimov J.R.', 'Karimov Ravshan Jasurovich') < 0.1
  && sim("Jo'rayeva G.; Toshkent; 1-chorak", "Jo'rayeva Gulnoza") > 0.7 && sim("Eshmatov D. 1 500 000 so'mlik", 'Eshmatov Doniyor') > 0.7,
  [sim('Toshmatov Jasur A.', "Toshmatov Ahmad Ulug'bekovich"), sim('Karimov Z.', 'Karimov Jasur Zafarovich'), sim("Jo'rayeva G.; Toshkent; 1-chorak", "Jo'rayeva Gulnoza")]);
// «сына» / «сынок» — izoh so'zi (faqat «сын» emas: koreyscha familiya Син)
ok('«Оплата за обучение сына …» — 3 so\'zli yozuv 95%', sim('Оплата за обучение сына Каримов Жасур', R3) >= 0.9 && sim('Каримов Жасур сынок', R3) >= 0.9
  && sim('Оплата за сына Каримов Жасур', 'Karimov Jasur Bahodirovich') >= 0.9, sim('Оплата за обучение сына Каримов Жасур', R3));
// Hisobga olinmagan qisqa so'z (koreyscha «Ли»/«O», ismda yo'q) + ismda juftsiz so'z — ball ≤ 64% (bonus bilan ham ⚠️)
ok('«Ли Виктория Сергеевна» ↔ boshqa oila «Kim Viktoriya Sergeyevna» — ≤ 64%, «Li …» — 100%', sim('Ли Виктория Сергеевна', 'Kim Viktoriya Sergeyevna') <= 0.64
  && sim('O Viktoriya Sergeyevna', 'Kim Viktoriya Sergeyevna') <= 0.64 && sim('Ли Виктория Сергеевна', 'Li Viktoriya Sergeyevna') === 1
  && N.scoreCandidate(sim('Ли Виктория Сергеевна', 'Kim Viktoriya Sergeyevna'), { amount: 1, debt: 1 }).score < 0.75, sim('Ли Виктория Сергеевна', 'Kim Viktoriya Sergeyevna'));
// Ruscha predloglar (на, до, по…) — izoh so'zi: koreyscha familiya «Na», «Do» bilan adashmaydi
ok('«Ким Виктория на октябрь» — Na Viktoriya emas', sim('Ким Виктория на октябрь', 'Na Viktoriya') < 0.1 && sim('Ким Виктория до октября', 'Do Viktoriya') < 0.1
  && sim('Na Viktoriya', 'Na Viktoriya') === 1 && sim('Ким Виктория на октябрь', 'Kim Viktoriya Sergeyevna') >= 0.9);
// wroteName — «to'lovchi ism yozganmi?» (ogohlantirish uchun): qisqa familiya ham ism
ok('wroteName: «Ли», «Ж К», «Ni 5-A» — ism; faqat izoh / raqam / sinf — yo\'q', N.wroteName('Ли', 'Kim Anna') && N.wroteName('Ж К', 'Aliyev Bekzod') && N.wroteName('Ni 5-A', 'Kim Anna')
  && N.wroteName('Avgust', 'Karimov Avgust') && !N.wroteName('Avgust', 'Saidova Kamola') && !N.wroteName('998901234567', 'Kim Anna')
  && !N.wroteName("Avgust oyi uchun to'lov", 'Karimov Avgust') && !N.wroteName('5 A', 'Kim Anna') && !N.wroteName('', 'Kim Anna') && !N.wroteName(null, 'Kim Anna'));
// Apostrof belgilari bitta manbadan: raqamdan keyingi ism va bosh harf uchun ham (′ ＇ ‛ ‚ ՚ ‵ ^ ¨)
['′', '＇', '‛', '‚', '՚', '‵', '^', '¨'].forEach(a => ok(`raqamdan keyin ${JSON.stringify(a)} apostrofli ism; «O${a}.» bosh harfi`, sim(`IQ-0042 G${a}ayrat Karimov`, "Karimov G'ayrat") === 1
  && sim(`Karimov O${a}.`, "Karimov O'tkir") > 0.7, [sim(`IQ-0042 G${a}ayrat Karimov`, "Karimov G'ayrat"), sim(`Karimov O${a}.`, "Karimov O'tkir")]));
// Ajratgichlar: « » — doim; ″ va yumshoq tire — so'zlar orasida bo'shliq, so'z ichida apostrof / o'chiriladi
ok('« » doim ajratadi (kichik harf bilan ham); ″ va yumshoq tire so\'zlar orasida', sim("turg'unboyeva«xadicha»", T) === 1 && sim("Turg'unboyeva«xadicha»", T) === 1
  && sim("Turg'unboyeva″Xadicha", T) === 1 && sim("Xadicha\u00ADTurg'unboyeva", T) === 1 && sim('G″ayrat Karimov', "Karimov G'ayrat") === 1
  && N.normalizeName('Turg\u200B\u200Bunboyeva') === 'turgunboeva', [sim("turg'unboyeva«xadicha»", T), N.normalizeName('Turg\u200B\u200Bunboyeva')]);

// ---- Brauzer yo'li (UMD): module yo'q -> globalThis.IqrorNameMatch ----
{ const src = fs.readFileSync(path.join(__dirname, '..', 'sb', 'name-match.js'), 'utf8'); const ctx = {}; vm.createContext(ctx); vm.runInContext(src, ctx);
  ok('brauzerda globalThis.IqrorNameMatch', !!ctx.IqrorNameMatch && ctx.IqrorNameMatch.nameSimilarity("Turg'unboyeva Hadicha", T) === 1);
  ok('tashqi kutubxona yo\'q (require/import yo\'q)', !/\brequire\s*\(|\bimport\s/.test(src.replace(/\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, ''))); }

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
