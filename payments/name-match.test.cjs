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

// ---- Brauzer yo'li (UMD): module yo'q -> globalThis.IqrorNameMatch ----
{ const src = fs.readFileSync(path.join(__dirname, '..', 'sb', 'name-match.js'), 'utf8'); const ctx = {}; vm.createContext(ctx); vm.runInContext(src, ctx);
  ok('brauzerda globalThis.IqrorNameMatch', !!ctx.IqrorNameMatch && ctx.IqrorNameMatch.nameSimilarity("Turg'unboyeva Hadicha", T) === 1);
  ok('tashqi kutubxona yo\'q (require/import yo\'q)', !/\brequire\s*\(|\bimport\s/.test(src.replace(/\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, ''))); }

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
