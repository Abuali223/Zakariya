// =====================================================================
// eskiz-template.test.cjs — SMS matnini Eskiz shablon NAQSHIGA moslash (payments/eskiz-template.cjs) birlik testlari.
//   node eskiz-template.test.cjs
// =====================================================================
const T = require('./eskiz-template.cjs');
let pass = 0, fail = 0;
const ok = (n, c, x) => { if (c) pass++; else { fail++; console.log('  ✗ FAIL:', n, x !== undefined ? JSON.stringify(x) : ''); } };

const OUR_DEBT = "Eslatma: {name} uchun {month} oy to'lovi hali yopilmagan (qarz: {due} so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";
const OUR_NEW = "Hurmatli ota-ona! {name} uchun {month} oy to'lovi shakllantirildi: {amount} so'm. Batafsil: iqroacademy.uz. IQROR Academy";
const P_SINGLE = "Eslatma: %w uchun %w oy to'lovi hali yopilmagan (qarz: %d so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";
const P_RANGE = "Eslatma: %w{1,4} uchun %w{1,3} oy to'lovi hali yopilmagan (qarz: %d{1,3} so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";
const OLD_SENT = "Eslatma: Aliyeva Malika uchun 09.2026, 10.2026 oy to'lovi hali yopilmagan (qarz: 5 800 000 so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";

// tplRegex — Eskiz misollari (haqiqiy hisobdan: matn -> naqsh)
const MISSED = "Sizga afsus bog'lana olmadik.  \n%w{1,15} uchun %d{1,3} ga qayta aloqaga chiqing.";
ok('Eskiz misoli: %w{1,15} + %d{1,3} mos', T.tplRegex(MISSED).test(T.squash("Sizga afsus bog'lana olmadik.  \n23-25 oktabrdagi Tog' safari uchun +998555160077 ga qayta aloqaga chiqing.")));
ok('o\'zgarmas matn farq qilsa — mos emas', !T.tplRegex(MISSED).test(T.squash("Sizga bog'lana olmadik. Safar uchun +998555160077 ga qayta aloqaga chiqing.")));
ok('%d o\'rnida so\'z — mos emas', !T.tplRegex(MISSED).test(T.squash("Sizga afsus bog'lana olmadik. Safar uchun telefon ga qayta aloqaga chiqing.")));
ok('eski SMS (2 so\'zli ism, 2 oy, bo\'shliqli summa) bitta-so\'z naqshga mos EMAS', !T.tplRegex(P_SINGLE).test(T.squash(OLD_SENT)));
ok('eski SMS oraliqli naqshga MOS (ism 2 so\'z ≤ 4, oy «09.2026, 10.2026» 2 so\'z ≤ 3, summa «5 800 000» 3 son ≤ 3)', T.tplRegex(P_RANGE).test(T.squash(OLD_SENT)) === true);
ok('%d harfli bo\'lakni qabul qilmaydi', !T.tplRegex('qarz: %d so\'m').test("qarz: 58abc so'm") && T.tplRegex('qarz: %d so\'m').test("qarz: 5800000 so'm") && T.tplRegex('%d oy').test('09.2026,10.2026 oy'));
ok('bo\'shliqlar yig\'iladi', T.tplRegex('A  %w\nB').test(T.squash('A x   B')));
ok('teskari oraliq {3,1} ham ishlaydi', T.tplRegex('%w{3,1}').test('a b'));

// SMS o'zgaruvchilari — bitta «so'z»
ok('smsSom bo\'shliqsiz', T.smsSom(5800000) === '5800000' && T.smsSom(0) === '0' && T.smsSom(-5) === '0' && T.smsSom('1234.6') === '1235');
ok('smsMonths: 1 / 2 / 3+ / takror / tartib', T.smsMonths(['2026-10']) === '10.2026' && T.smsMonths(['2026-10', '2026-09']) === '09.2026,10.2026'
  && T.smsMonths(['2026-05', '2026-06', '2026-08', '2026-10']) === '05.2026-10.2026' && T.smsMonths(['2026-09', '2026-09']) === '09.2026' && T.smsMonths([]) === '');
ok('smsMonths har doim bitta so\'z', ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05'].every((_, i, arr) => !/\s/.test(T.smsMonths(arr.slice(0, i + 1)))));
ok('nameVariants', JSON.stringify(T.nameVariants('Aliyeva  Malika')) === JSON.stringify(['Aliyeva Malika', 'Malika', 'Aliyeva'])
  && JSON.stringify(T.nameVariants("Qobiljonov Muhammadiy Akmal o'g'li")) === JSON.stringify(["Qobiljonov Muhammadiy Akmal o'g'li", 'Qobiljonov Muhammadiy', 'Muhammadiy', 'Qobiljonov'])
  && JSON.stringify(T.nameVariants('Ali')) === JSON.stringify(['Ali']) && JSON.stringify(T.nameVariants('')) === '[]');

// composeSms
const V = { name: 'Aliyeva Malika', month: T.smsMonths(['2026-09', '2026-10']), due: T.smsSom(5800000), amount: T.smsSom(5800000) };
let r = T.composeSms(OUR_DEBT, V, [{ id: 1, status: 'service', template: P_SINGLE }]);
ok('bitta-so\'z naqsh: ism qisqartiriladi (Malika), mos', r.fit === true && r.templateId === 1 && r.shortened === true && r.message.startsWith('Eslatma: Malika uchun 09.2026,10.2026 oy') && r.message.includes('qarz: 5800000 so'), r);
r = T.composeSms(OUR_DEBT, V, [{ id: 2, status: 'service', template: P_RANGE }]);
ok('oraliqli naqsh: to\'liq ism', r.fit === true && r.shortened === false && r.message.startsWith('Eslatma: Aliyeva Malika uchun'), r);
r = T.composeSms(OUR_DEBT, V, [{ id: 3, status: 'moderation', template: P_SINGLE }]);
ok('faqat moderatsiyadagi naqsh -> fit=false, to\'liq ism', r.fit === false && r.message.startsWith('Eslatma: Aliyeva Malika uchun'), r);
r = T.composeSms(OUR_DEBT, V, [{ id: 4, status: 'service', template: OUR_DEBT }]);
ok('so\'zma-so\'z ({name}) tasdiqlangan naqsh -> fit=false', r.fit === false, r);
r = T.composeSms(OUR_DEBT, V, null);
ok('naqshlar noma\'lum -> fit=null, to\'liq ism', r.fit === null && r.shortened === false && r.message.startsWith('Eslatma: Aliyeva Malika uchun'), r);
r = T.composeSms(OUR_NEW, { name: 'Valiyev Sardor', month: '10.2026', amount: '2900000' }, [{ id: 5, status: 'reklama', template: "Hurmatli ota-ona! %w{1,3} uchun %d oy to'lovi shakllantirildi: %d so'm. Batafsil: iqroacademy.uz. IQROR Academy" }]);
ok('yangi faktura matni (reklama holati ham tasdiqlangan)', r.fit === true && r.message === "Hurmatli ota-ona! Valiyev Sardor uchun 10.2026 oy to'lovi shakllantirildi: 2900000 so'm. Batafsil: iqroacademy.uz. IQROR Academy", r);
r = T.composeSms(OUR_DEBT, V, [{ id: 6, status: 'service', template: 'boshqa matn %w' }, { id: 7, status: 'rejected', template: P_RANGE }]);
ok('boshqa matn / rad etilgan naqsh -> fit=false', r.fit === false, r);

// alignTemplate / valueFits (diagnostika)
const al = T.alignTemplate(OUR_DEBT, P_SINGLE);
ok('alignTemplate: o\'zgaruvchilar xaritasi', al.ok && al.vars.name.raw === '%w' && al.vars.month.max === 1 && al.vars.due.kind === 'd', al);
ok('alignTemplate: matn farqi topiladi', !T.alignTemplate(OUR_DEBT, P_SINGLE.replace('hali', 'hanuz')).ok);
ok('valueFits', T.valueFits('Aliyeva Malika', T.parseVar('%w')).ok === false && T.valueFits('Malika', T.parseVar('%w')).ok === true
  && T.valueFits('5 800 000', T.parseVar('%d')).ok === false && T.valueFits('5800000', T.parseVar('%d')).ok === true && T.valueFits('5800000so', T.parseVar('%d')).kindOk === false);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
