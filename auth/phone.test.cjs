// =====================================================================
// phone.test.cjs — telefon qoidasi (server/phone.cjs) + uning brauzer nusxalari (sb/auth-api.js, admin.html) testlari.
//   node phone.test.cjs
//   1) PHONE-CANON bloki uchala faylda AYNAN bir xil (biri o'zgarib, qolgani eski qolmasin).
//   2) Xatti-harakat: O'zbekiston / chet el ('+' bilan) / noaniq ('+'siz uzun) / chala raqamlar.
//   3) Brauzer nusxalari (auth-api.js, admin.html bloklari va o'ramlari) server bilan bir xil natija beradi (korpus + fuzz).
//   4) Mijoz -> server zanjiri: normPhone() natijasi wirePhone() bilan serverга ketganda AYNAN shu kanonik raqam chiqadi
//      (chet el kanonik raqami '+'siz serverda yaroqsiz — '+' qo'shilishi shart).
// =====================================================================
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const P = require('../server/phone.cjs');
const L = require('./lib.cjs');

let pass = 0, fail = 0;
const ok = (name, cond, extra) => { if (cond) pass++; else { fail++; console.log('  ✗ FAIL:', name, extra !== undefined ? '→ ' + JSON.stringify(extra) : ''); } };
const sec = s => console.log('\n— ' + s);
const ROOT = path.join(__dirname, '..');
const read = f => fs.readFileSync(path.join(ROOT, f), 'utf8');
const blockOf = (src, f) => { const m = src.match(/\/\* PHONE-CANON:BEGIN[\s\S]*?\/\* PHONE-CANON:END \*\//); if (!m) throw new Error('PHONE-CANON bloki topilmadi: ' + f); return m[0]; };

// ---------- 1) bloklar bir xil ----------
sec('PHONE-CANON bloklari bir xil');
const SRV = read('server/phone.cjs'), API = read('sb/auth-api.js'), ADM = read('admin.html');
const bS = blockOf(SRV, 'server/phone.cjs'), bA = blockOf(API, 'sb/auth-api.js'), bD = blockOf(ADM, 'admin.html');
ok('sb/auth-api.js bloki == server/phone.cjs', bA === bS);
ok('admin.html bloki == server/phone.cjs', bD === bS);
ok('har faylda bittadan blok', [SRV, API, ADM].every(s => (s.match(/PHONE-CANON:BEGIN/g) || []).length === 1));

// ---------- brauzer nusxalarini ajratib olish ----------
const ctxBlock = vm.createContext({});
vm.runInContext(bA + '\n;this.__api = { phoneCanon, phoneIso, phonePretty, phoneMask, phoneCc };', ctxBlock);
const BA = ctxBlock.__api;
// sb/auth-api.js o'ramlari (normPhone/prettyPhone/maskPhone/wirePhone): import/export olib tashlanadi, tarmoq chaqirilmaydi.
const apiSrc = API.replace(/^import .*$/mg, '').replace(/^export default\s*\{[\s\S]*?\};?\s*$/m, '').replace(/^export (async )?function/mg, (m, a) => (a || '') + 'function');
const ctxApi = vm.createContext({ console });
vm.runInContext(apiSrc + '\n;this.__w = { normPhone, prettyPhone, maskPhone, wirePhone };', ctxApi);
const W = ctxApi.__w;
// admin.html: blok + pmCanonPhone/pmCanonStored/pmPrettyPhone/pmPhoneHint (blokdan «// Narx kaliti:» gacha) va posToRole.
const admStart = ADM.indexOf(bD), admEnd = ADM.indexOf('// Narx kaliti:', admStart);
const admPhone = ADM.slice(admStart, admEnd);
const pStart = ADM.indexOf('// HR lavozimi'), pEnd = ADM.indexOf('// Rol + sinf/fan biriktirish oynasi', pStart);
const ctxAdm = vm.createContext({});
vm.runInContext(admPhone + '\n' + ADM.slice(pStart, pEnd) + '\n;this.__a = { pmCanonPhone, pmCanonStored, pmPrettyPhone, pmPhoneHint, posToRole, phoneCanon };', ctxAdm);
const AD = ctxAdm.__a;
ok('admin.html ajratildi', typeof AD.pmCanonPhone === 'function' && typeof AD.posToRole === 'function' && admEnd > admStart && pEnd > pStart);

// ---------- 2) xatti-harakat korpusi ----------
sec('phoneCanon korpusi');
const CANON = [
  // O'zbekiston
  ['+998 90 123 45 67', '998901234567'], ['998901234567', '998901234567'], ['901234567', '998901234567'],
  ['+998 (93) 630-11-11', '998936301111'], ['+998936301111', '998936301111'], ['  90 123 45 67 ', '998901234567'],
  ['998611234567', ''], ['+998 66 200 45 45', ''], ['99890123456', ''], ['9989012345678', ''], ['998101234567', ''],
  // Chet el — '+' (yoki 00) bilan
  ['+48789706619', '48789706619'], ['+79637682301', '79637682301'], ['+79031571124', '79031571124'],
  ['+7 (903) 157-11-24', '79031571124'], ['0048 789 706 619', '48789706619'], ['007 903 157 11 24', '79031571124'],
  ['+7 701 234 56 78', '77012345678'], ['+996 555 123 456', '996555123456'], ['+992 93 123 4567', '992931234567'],
  ['+993 65 123456', '99365123456'], ['+90 532 123 45 67', '905321234567'], ['+82 10 1234 5678', '821012345678'],
  ['+1 202 555 0123', '12025550123'], ['+44 7700 900123', '447700900123'], ['+49 151 12345678', '4915112345678'],
  ['+86 138 1234 5678', '8613812345678'], ['+380 50 123 4567', '380501234567'], ['+971 50 123 4567', '971501234567'],
  ['Ota: +7 903 157 11 24', '79031571124'],
  // Noaniq / chala / xato
  ['79031571124', ''], ['8 903 157 11 24', ''], ['+7 903 157 11', ''], ['+790315711', ''], ['+90 123 45 67', ''],
  ['+7 903 157 11 245', ''], ['+48 789 706 61', ''], ['+999 123 456 789', ''], ['+0 123 456 789', ''], ['12345', ''],
  ['', ''], [null, ''], [undefined, ''], ['+', ''], ['00', ''], ['+79031571124, +998901234567', ''],
  ['+1234567890123456', ''], ['abc', ''],
];
for (const [inp, exp] of CANON) ok(`phoneCanon(${JSON.stringify(inp)}) = ${JSON.stringify(exp)}`, P.phoneCanon(inp) === exp, P.phoneCanon(inp));
ok('lib.normPhone: null yaroqsizга', L.normPhone('79031571124') === null && L.normPhone('+79031571124') === '79031571124');

sec('canonOf (saqlangan kanonik raqam)');
ok('kanonik chet el (+siz) tan olinadi', P.canonOf('79031571124') === '79031571124' && L.canonOf('48789706619') === '48789706619');
ok('kanonik O\'zbekiston', P.canonOf('998901234567') === '998901234567');
ok('xom kiritma ham', P.canonOf('+7 903 157 11 24') === '79031571124' && P.canonOf('901234567') === '998901234567');
ok('yaroqsiz kanonik emas', P.canonOf('89031571124') === '' && P.canonOf('7903157112') === '' && P.canonOf('') === '');

sec('phoneIso / phonePretty');
ok('ISO', P.phoneIso('79031571124') === 'RU' && P.phoneIso('77012345678') === 'KZ' && P.phoneIso('76012345678') === 'KZ' && P.phoneIso('48789706619') === 'PL'
  && P.phoneIso('998901234567') === 'UZ' && P.phoneIso('12025550123') === 'US' && P.phoneIso('996555123456') === 'KG' && P.phoneIso('') === '');
ok('pretty UZ', P.phonePretty('998901234567') === '+998 90 123 45 67');
ok('pretty RU', P.phonePretty('79031571124') === '+7 903 157 11 24');
ok('pretty PL', P.phonePretty('48789706619') === '+48 789 706 619');
ok('pretty yaroqsiz -> o\'zgarishsiz', P.phonePretty('12345') === '12345' && P.phonePretty('') === '' && P.phonePretty(null) === '');
ok('lib.prettyPhone chet el', L.prettyPhone('79031571124') === '+7 903 157 11 24' && L.prettyPhone('998901234567') === '+998 90 123 45 67');

sec('phoneMask');
const MASK = [
  ['', '+998'], ['+998 ', '+998'], ['+998 9', '+998 9'], ['+998 90 123 45 67', '+998 90 123 45 67'], ['901234567', '+998 90 123 45 67'],
  ['+99', '+99'], ['+9', '+9'], ['+', '+'], ['+7', '+7'], ['+79', '+7 9'], ['+79031571124', '+7 903 157 11 24'],
  ['79031571124', '+7 903 157 11 24'], ['0', '0'], ['00', '+'], ['007', '+7'], ['0048789706619', '+48 789 706 619'],
  ['+998 90 123 45 678', '+998 90 123 45 67'],
];
for (const [inp, exp] of MASK) ok(`phoneMask(${JSON.stringify(inp)}) = ${JSON.stringify(exp)}`, P.phoneMask(inp) === exp, P.phoneMask(inp));

// ---------- 3) brauzer nusxalari server bilan bir xil (korpus + fuzz) ----------
sec('brauzer nusxalari == server (korpus + fuzz)');
let seed = 12345; const rnd = n => { seed = (Math.imul(seed, 1103515245) + 12345) >>> 0; return seed % n; };
const PIECES = ['+', '00', '998', '7', '48', '996', '90', '1', '8', ' ', '-', '(', ')', '9', '0', '3', '5', 'a', '.', '+7 ', '+998 '];
const fuzz = [];
for (let i = 0; i < 30000; i++) {
  let s = ''; const parts = 1 + rnd(8);
  for (let j = 0; j < parts; j++) s += rnd(3) ? String(rnd(10 ** (1 + rnd(5)))) : PIECES[rnd(PIECES.length)];
  fuzz.push(s);
}
// Valid raqamlar ham ko'p bo'lsin: ma'lum davlat kodlari + to'g'ri uzunlik.
for (const cc of Object.keys(P.PHONE_CC)) {
  const lens = P.PHONE_LEN[cc] || [cc.length + 6, Math.min(15, cc.length + 9)];
  for (const L0 of lens) { let n = ''; for (let k = cc.length; k < L0; k++) n += String(rnd(10)); fuzz.push('+' + cc + n); fuzz.push('+' + cc + ' ' + n); fuzz.push(cc + n); }
}
const inputs = CANON.map(x => x[0]).concat(MASK.map(x => x[0]), fuzz);
let mism = 0, firstMism = null, inv = 0, firstInv = null;
for (const s of inputs) {
  const c = P.phoneCanon(s);
  const same = BA.phoneCanon(s) === c && AD.pmCanonPhone(s) === c && (W.normPhone(s) || '') === c && (L.normPhone(s) || '') === c
    && BA.phoneMask(s) === P.phoneMask(s) && W.maskPhone(s) === P.phoneMask(s)
    && BA.phonePretty(s) === P.phonePretty(s) && W.prettyPhone(s) === P.phonePretty(s || '')
    && AD.pmCanonStored(s) === P.canonOf(s);
  if (!same) { mism++; if (!firstMism) firstMism = s; }
  // Invariantlar
  let good = true;
  if (c) {
    good = /^\d{10,15}$/.test(c)                                           // faqat raqamlar
      && P.canonOf(c) === c                                                // saqlangan kanonik qayta tan olinadi
      && P.phoneCanon(P.phonePretty(c)) === c                              // chiroyli ko'rinish qayta o'qiladi
      && P.phoneCanon(P.phoneMask(s)) === c                                // maska raqamni o'zgartirmaydi
      && (L.normPhone(W.wirePhone(W.normPhone(s))) === c)                  // mijoz -> server zanjiri
      && (c.slice(0, 3) === '998' ? c.length === 12 : P.phoneIso(c) !== '');
  }
  good = good && P.phoneMask(P.phoneMask(s)) === P.phoneMask(s);          // maska idempotent
  if (!good) { inv++; if (!firstInv) firstInv = s; }
}
ok(`${inputs.length} kirish: brauzer nusxalari server bilan bir xil`, mism === 0, { mism, firstMism, srv: firstMism != null && P.phoneCanon(firstMism) });
ok(`${inputs.length} kirish: invariantlar`, inv === 0, { inv, firstInv, canon: firstInv != null && P.phoneCanon(firstInv), mask: firstInv != null && P.phoneMask(firstInv) });
ok('fuzz yaroqli chet el raqamlarini ham qamradi', inputs.filter(s => { const c = P.phoneCanon(s); return c && c.slice(0, 3) !== '998'; }).length > 300);

sec('wirePhone (mijoz -> server)');
ok('kanonik chet el -> +', W.wirePhone('79031571124') === '+79031571124' && W.wirePhone(W.normPhone('+48 789 706 619')) === '+48789706619');
ok('kanonik UZ -> +998', W.wirePhone('998901234567') === '+998901234567');
ok('xom 9 xonali -> +998', W.wirePhone('901234567') === '+998901234567');

sec('admin.html: maslahat (pmPhoneHint) va lavozim -> rol (posToRole)');
ok('+ siz chet el -> +7', AD.pmPhoneHint('79031571124') === '+7 903 157 11 24', AD.pmPhoneHint('79031571124'));
ok('Rossiya 8 ... -> +7', AD.pmPhoneHint('8 903 157 11 24') === '+7 903 157 11 24', AD.pmPhoneHint('8 903 157 11 24'));
ok('+ bilan 9 xonali -> +998', AD.pmPhoneHint('+90 123 45 67') === '+998 90 123 45 67', AD.pmPhoneHint('+90 123 45 67'));
ok('to\'g\'ri raqam -> maslahat yo\'q', AD.pmPhoneHint('+48789706619') === '' && AD.pmPhoneHint('901234567') === '');
ok('tuzatib bo\'lmaydigan -> bo\'sh', AD.pmPhoneHint('12345') === '' && AD.pmPhoneHint('') === '');
ok('pmPrettyPhone', AD.pmPrettyPhone('+79031571124') === '+7 903 157 11 24' && AD.pmPrettyPhone('abc') === 'abc');
ok('posToRole: «Moliya Menejeri» -> finance_mgr', AD.posToRole('Moliya Menejeri') === 'finance_mgr' && AD.posToRole('  moliya   menejeri ') === 'finance_mgr');
ok('posToRole: apostroflar', AD.posToRole('O‘qituvchi') === 'teacher' && AD.posToRole("O'IBDO'") === 'zavuch' && AD.posToRole('Ma‘muriyat rahbari') === 'admin' && AD.posToRole('G‘aznachi') === 'treasurer');
ok('posToRole: mos rol yo\'q / prototip', AD.posToRole('Hamshira') === '' && AD.posToRole('constructor') === '' && AD.posToRole('') === '' && AD.posToRole(null) === '');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
