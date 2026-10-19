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
vm.runInContext(apiSrc + '\n;this.__w = { normPhone, prettyPhone, maskPhone, wirePhone, phoneHint, bindPhoneInput };', ctxApi);
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
  ['', ''], ['   ', ''], ['+998 ', '+998'], ['+998 9', '+998 9'], ['+998 90 123 45 67', '+998 90 123 45 67'], ['901234567', '+998 90 123 45 67'],
  ['+99', '+99'], ['+9', '+9'], ['+', '+'], ['+7', '+7'], ['+79', '+7 9'], ['+79031571124', '+7 903 157 11 24'],
  ['79031571124', '+7 903 157 11 24'], ['0', '0'], ['00', '+'], ['007', '+7'], ['0048789706619', '+48 789 706 619'],
  // Raqam TASHLANMAYDI: ortiqcha raqam ko'rinadi (raqam yaroqsiz bo'ladi, begona O'zbekiston raqamiga aylanmaydi)
  ['+998 90 123 45 678', '+998 90 123 45 67 8'], ['+998 77012345678', '+998 77 012 34 56 78'], ['+998 998901234567', '+998 99 890 12 34 567'],
  ['0901234567', '0901234567'], ['+0998901234567', '+998 90 123 45 67'],
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
const INVIS = /[\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF]/g;
const wrapMask = s0 => { const s = String(s0 == null ? '' : s0).replace(INVIS, ''); return /^\s*\+\s*998\s*\+/.test(s) ? s.replace(/^\s*\+\s*998\s*/, '') : s; };
const inputs = CANON.map(x => x[0]).concat(MASK.map(x => x[0]), fuzz);
let mism = 0, firstMism = null, inv = 0, firstInv = null;
for (const s of inputs) {
  const c = P.phoneCanon(s);
  const same = BA.phoneCanon(s) === c && AD.pmCanonPhone(s) === c && (W.normPhone(s) || '') === c && (L.normPhone(s) || '') === c
    && BA.phoneMask(s) === P.phoneMask(s) && W.maskPhone(s) === P.phoneMask(wrapMask(s))
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
  // XAVFSIZLIK: yaroqsiz kiritma maska orqali hech qachon YAROQLI O'ZBEKISTON raqamiga aylanmaydi (SMS begonaga ketmasin)
  if (!c) { const m1 = P.phoneCanon(P.phoneMask(s)), m2 = P.phoneCanon(W.maskPhone(s)); good = good && !/^998/.test(m1) && !/^998/.test(m2); }
  if (!good) { inv++; if (!firstInv) firstInv = s; }
}
ok(`${inputs.length} kirish: brauzer nusxalari server bilan bir xil`, mism === 0, { mism, firstMism, srv: firstMism != null && P.phoneCanon(firstMism) });
ok(`${inputs.length} kirish: invariantlar`, inv === 0, { inv, firstInv, canon: firstInv != null && P.phoneCanon(firstInv), mask: firstInv != null && P.phoneMask(firstInv) });
ok('fuzz yaroqli chet el raqamlarini ham qamradi', inputs.filter(s => { const c = P.phoneCanon(s); return c && c.slice(0, 3) !== '998'; }).length > 300);

sec('maskPhone: «+998 » ortidan «+» — chet el raqamiga o\'tish');
ok('+998 + -> +', W.maskPhone('+998 +') === '+', W.maskPhone('+998 +'));
ok('+998 +7 -> +7', W.maskPhone('+998 +7') === '+7', W.maskPhone('+998 +7'));
ok('+998 +79031571124 -> +7 903 157 11 24', W.maskPhone('+998 +79031571124') === '+7 903 157 11 24', W.maskPhone('+998 +79031571124'));
ok('+998 90 (oddiy) o\'zgarmaydi', W.maskPhone('+998 90') === '+998 90');

sec('klaviatura simulyatsiyasi: «+998 » ortidan yozish (maydon maskasi har tugmada)');
{
  const typeAfterPrefix = (txt) => { let v = '+998 '; for (const ch of txt) v = W.maskPhone(v + ch); return v; };
  let stranger = 0, ex = null, okUz = 0;
  const FOREIGN = ['+77012345678', '+79031571124', '+48789706619', '+996555123456', '+992935123456', '+99365123456', '+994501234567',
    '+995555123456', '+905321234567', '+971501234567', '+821012345678', '+8613812345678', '+12025550123', '+447700900123',
    '77012345678', '79031571124', '996555123456', '998901234567', '00 7 903 157 11 24'];
  for (const f of FOREIGN) { const v = typeAfterPrefix(f); const c = W.normPhone(v); if (c && c.slice(0, 3) === '998' && c !== '998' + f.replace(/\D/g, '').slice(-9) ) { stranger++; if (!ex) ex = [f, v, c]; } }
  ok('chet el raqami «+998 » ortidan yozilsa — begona O\'zbekiston raqami chiqmaydi', stranger === 0, { stranger, ex });
  for (const nat of ['901234567', '936301111', '770143777', '331234567']) { const v = typeAfterPrefix(nat); if (W.normPhone(v) === '998' + nat) okUz++; }
  ok('O\'zbekiston raqami odatdagidek yoziladi', okUz === 4);
  ok('«+998 » + «+7…» -> chet el ko\'rinishi (rad etiladi, begonaga ketmaydi)', typeAfterPrefix('+79031571124') === '+7 903 157 11 24');
  ok('«+998 » + 998901234567 (takror 998) -> yaroqsiz, ko\'rinadi', W.normPhone(typeAfterPrefix('998901234567')) === null);
}

sec('wirePhone (mijoz -> server)');
ok('kanonik chet el -> +', W.wirePhone('79031571124') === '+79031571124' && W.wirePhone(W.normPhone('+48 789 706 619')) === '+48789706619');
ok('kanonik UZ -> +998', W.wirePhone('998901234567') === '+998901234567');
ok('xom 9 xonali -> +998', W.wirePhone('901234567') === '+998901234567');

sec('admin.html: maslahat (pmPhoneHint) va lavozim -> rol (posToRole)');
ok('+ siz chet el -> +7', AD.pmPhoneHint('79031571124') === '+7 903 157 11 24', AD.pmPhoneHint('79031571124'));
ok('Rossiya 8 ... -> +7', AD.pmPhoneHint('8 903 157 11 24') === '+7 903 157 11 24', AD.pmPhoneHint('8 903 157 11 24'));
ok('+ bilan 9 xonali -> maslahat YO\'Q (O\'zbekiston raqami taklif qilinmaydi)', AD.pmPhoneHint('+90 123 45 67') === '', AD.pmPhoneHint('+90 123 45 67'));
ok('PL +siz -> +48', AD.pmPhoneHint('48789706619') === '+48 789 706 619', AD.pmPhoneHint('48789706619'));
for (const v of ['+7 903 157 11', '+996 555 123', '+7 701 234 56', '98 123 45 678', '93 123 45 678', '98 90 123 45 67', '8 371 234 56 78',
  '93 630 11 11 1', '989 90 123 45 67', '77 123 45 67 89', '33 123 45 67 89', '94 123 45 678', '95 123 45 678', '55 123 45 678', '50 123 45 678', '97 312 34 567', '89901234567'])
  ok(`xavfli/noaniq maslahat yo'q: ${v}`, AD.pmPhoneHint(v) === '', AD.pmPhoneHint(v));
{ // 20 000 ta tasodifiy «bitta raqam qo'shilgan» O'zbekiston raqami — hech biriga chet el maslahati berilmaydi
  let s0 = 777, bad = 0, ex = null; const r = n => { s0 = (Math.imul(s0, 1103515245) + 12345) >>> 0; return s0 % n; };
  const OPS = ['90', '91', '93', '94', '95', '97', '98', '99', '33', '50', '55', '77', '88', '20'];
  for (let i = 0; i < 20000; i++) { let n = OPS[r(OPS.length)]; while (n.length < 9) n += String(r(10)); const pos = r(10); const typo = n.slice(0, pos) + String(r(10)) + n.slice(pos);
    for (const v of [typo, '998' + typo]) { const h = AD.pmPhoneHint(v); if (h) { bad++; if (!ex) ex = [v, h]; } } }
  ok('UZ typo -> foreign hint: 0', bad === 0, { bad, ex }); }
ok('to\'g\'ri raqam -> maslahat yo\'q', AD.pmPhoneHint('+48789706619') === '' && AD.pmPhoneHint('901234567') === '');
ok('tuzatib bo\'lmaydigan -> bo\'sh', AD.pmPhoneHint('12345') === '' && AD.pmPhoneHint('') === '');
ok('pmPrettyPhone', AD.pmPrettyPhone('+79031571124') === '+7 903 157 11 24' && AD.pmPrettyPhone('abc') === 'abc');
ok('posToRole: «Moliya Menejeri» -> finance_mgr', AD.posToRole('Moliya Menejeri') === 'finance_mgr' && AD.posToRole('  moliya   menejeri ') === 'finance_mgr');
ok('posToRole: apostroflar', AD.posToRole('O‘qituvchi') === 'teacher' && AD.posToRole("O'IBDO'") === 'zavuch' && AD.posToRole('Ma‘muriyat rahbari') === 'admin' && AD.posToRole('G‘aznachi') === 'treasurer');
ok('posToRole: mos rol yo\'q / prototip', AD.posToRole('Hamshira') === '' && AD.posToRole('constructor') === '' && AD.posToRole('') === '' && AD.posToRole(null) === '');

sec('maskPhone: ko\'rinmas belgilar (kontaktlardan nusxa) + phoneHint (998 ikki marta)');
ok('yo\'nalish belgilari olib tashlanadi', W.maskPhone('\u202D+998 90 123 45 67\u202C') === '+998 90 123 45 67' && W.maskPhone('+998 \u202D+998 90 123 45 67\u202C') === '+998 90 123 45 67'
  && W.maskPhone('\u200E+7 903 157 11 24') === '+7 903 157 11 24', [W.maskPhone('\u202D+998 90 123 45 67\u202C'), W.maskPhone('+998 \u202D+998 90 123 45 67\u202C')]);
ok('phoneHint: «+998 » + 998901234567 -> maslahat (raqam bilan), avtomatik o\'zgartirilmaydi', /ikki marta/.test(W.phoneHint('+998 998901234567')) && W.phoneHint('+998 998901234567').includes('+998 90 123 45 67')
  && W.normPhone('+998 998901234567') === null, W.phoneHint('+998 998901234567'));
ok('phoneHint: oddiy holatlarda bo\'sh', W.phoneHint('+998 99 890 12 34') === '' && W.phoneHint('+998 99 890 12 34 5') === '' && W.phoneHint('') === '' && W.phoneHint(null) === ''
  && W.phoneHint('+998 998 12 345 67 89') === '');

sec('bindPhoneInput: kursor tahrir joyida qoladi (brauzer simulyatsiyasi)');
// Brauzer semantikasi: value BOSHQA satrga o'zgarsa kursor oxirga o'tadi; o'sha satr bo'lsa — joyida.
class FakeInput {
  constructor(v) { this._v = v; this.selectionStart = this.selectionEnd = v.length; this.L = {}; }
  get value() { return this._v; }
  set value(x) { x = String(x); if (x !== this._v) { this._v = x; this.selectionStart = this.selectionEnd = x.length; } }
  setSelectionRange(a, b) { this.selectionStart = Math.min(a, this._v.length); this.selectionEnd = Math.min(b, this._v.length); }
  addEventListener(t, f) { (this.L[t] = this.L[t] || []).push(f); }
  dispatchEvent(e) { (this.L[e.type] || []).forEach(f => f(e)); return !e.defaultPrevented; }
  edit(text, inputType, dir) {
    let a = this.selectionStart, b = this.selectionEnd; const v = this._v;
    if (a === b && text === '') { if (dir < 0) { if (a === 0) return; a--; } else { if (b >= v.length) return; b++; } }
    this.dispatchEvent({ type: 'beforeinput', inputType });
    this._v = v.slice(0, a) + text + v.slice(b); this.selectionStart = this.selectionEnd = a + text.length;
    this.dispatchEvent({ type: 'input', inputType });
  }
  type(str) { for (const ch of str) this.edit(ch, 'insertText', 0); }
  back() { this.edit('', 'deleteContentBackward', -1); }
  del() { this.edit('', 'deleteContentForward', 1); }
  caret(k) { this.setSelectionRange(k, k); }
  sel(a, b) { this.setSelectionRange(a, b); }
  paste(txt) { const e = { type: 'paste', defaultPrevented: false, clipboardData: { getData: () => txt }, preventDefault() { this.defaultPrevented = true; } };
    this.dispatchEvent(e); if (!e.defaultPrevented) this.edit(txt, 'insertFromPaste', 0); }
  // IME: matnni kompozitsiya bilan (har yangilanish oldingi kompozitsiya matnini almashtiradi), so'ng yakunlash
  compose(text) {
    this.dispatchEvent({ type: 'compositionstart' }); const a = this.selectionStart;
    for (let i = 1; i <= text.length; i++) {
      this.dispatchEvent({ type: 'beforeinput', inputType: 'insertCompositionText', isComposing: true });
      this._v = this._v.slice(0, a) + text.slice(0, i) + this._v.slice(a + i - 1); this.selectionStart = this.selectionEnd = a + i;
      this.dispatchEvent({ type: 'input', inputType: 'insertCompositionText', isComposing: true });
    }
    this.dispatchEvent({ type: 'compositionend' });
  }
}
const field = () => { const f = new FakeInput('+998 '); W.bindPhoneInput(f); return f; };
const typed = d => { const f = field(); f.type(d); return f; };
// Ko'rib chiqish (wf) ssenariylari: avval kursor oxirga sakrab, tuzatish BOSHQA yaroqli raqam berardi.
const SC = [
  ['(a) «91» dan keyin Backspace + 0', '911234567', f => { f.caret(7); f.back(); f.type('0'); }],
  ['(b) «124» belgilab 123', '901244567', f => { f.sel(8, 11); f.type('123'); }],
  ['(c) o\'rtada ortiqcha 5, keyin Backspace', '901234567', f => { f.caret(9); f.type('5'); f.back(); }],
  ['(d) bo\'shliqdan keyin Backspace (bo\'shliq o\'rniga oldingi raqam), keyin 0', '911234567', f => { f.caret(8); f.back(); f.type('0'); f.caret(f.value.indexOf('123')); }],
  ['(e) o\'rtada Delete, keyin to\'g\'ri raqam', '901284567', f => { f.caret(10); f.del(); f.type('3'); }],
  ['(e2) bo\'shliq oldida Delete (keyingi raqam o\'chadi), keyin 1', '901234567', f => { f.caret(7); f.del(); f.type('1'); }],
  ['(f) 54 -> 45 (2 ta Backspace + 45)', '901235467', f => { f.caret(14); f.back(); f.back(); f.type('45'); }],
  ['(g) 2-guruh: «128» dan keyin Backspace + 3', '901284567', f => { f.caret(11); f.back(); f.type('3'); }],
  ['(h) bitta raqamni belgilab almashtirish', '901284567', f => { f.sel(10, 11); f.type('3'); }],
];
for (const [nm, start, act] of SC) {
  const f = typed(start); act(f);
  ok(`${nm}: ${f.value}`, W.normPhone(f.value) === '998901234567', { v: f.value, c: W.normPhone(f.value) });
}
{ const f = typed('911234567'); f.caret(7); f.back();
  ok('Backspace keyin kursor o\'sha joyda («+998 9|1…»)', f.value === '+998 91 234 56 7' && f.selectionEnd === 6, { v: f.value, c: f.selectionEnd }); }
{ const f = typed('901234567'); f.caret(8); f.back();
  ok('bo\'shliqdan keyin Backspace -> oldingi RAQAM o\'chadi (tugma «ishlamay» qolmaydi)', W.normPhone(f.value) === null && f.value === '+998 91 234 56 7' && f.selectionEnd === 6, { v: f.value, c: f.selectionEnd }); }
{ const f = typed('901234567'); f.caret(7); f.del();
  ok('bo\'shliq oldida Delete -> keyingi RAQAM o\'chadi', f.value === '+998 90 234 56 7' && f.selectionEnd === 7, { v: f.value, c: f.selectionEnd }); }
{ const f = field(); f.back();
  ok('«+998 » da Backspace -> faqat bo\'shliq (avvalgidek)', f.value === '+998', f.value); }
{ const f = typed('901234567'); f.caret(5); f.back();
  ok('«+998 |90…» da Backspace -> prefiks raqami o\'chmaydi, kursor 5 da', f.value === '+998 90 123 45 67' && f.selectionEnd === 5, { v: f.value, c: f.selectionEnd }); }
{ const f = typed('901234567'); f.caret(4); f.del();
  ok('«+998| 90…» da Delete -> birinchi milliy raqam o\'chadi (fail-safe: yaroqsiz)', f.value === '+998 01 234 56 7' && W.normPhone(f.value) === null, { v: f.value, c: f.selectionEnd }); }
{ const f = typed('901234567'); f.caret(6); f.back();
  ok('birinchi milliy raqamni o\'chirish -> kursor prefiksdan keyin (5)', f.value === '+998 01 234 56 7' && f.selectionEnd === 5, { v: f.value, c: f.selectionEnd }); }
{ const f = field(); f.type('+79031571124');
  ok('«+998 » + «+» -> chet el rejimi', f.value === '+7 903 157 11 24', f.value); }
{ const f = typed('9x0 1'); ok('raqam bo\'lmagan belgi yozilmaydi', f.value === '+998 90 1', f.value); }
// Nusxa qo'yish (paste)
for (const [txt, want] of [['998901234567', '+998 90 123 45 67'], ['\u202D+998 90 123 45 67\u202C', '+998 90 123 45 67'], ['901234567', '+998 90 123 45 67'],
  ['+998 (90) 123-45-67', '+998 90 123 45 67'], ['+7 903 157 11 24', '+7 903 157 11 24']]) {
  const f = field(); f.paste(txt);
  ok(`paste «${txt.replace(/[\u202A-\u202E]/g, '·')}» -> ${want}`, f.value === want && f.selectionEnd === f.value.length, { v: f.value, c: f.selectionEnd });
}
{ const f = typed('901234567'); f.sel(0, f.value.length); f.paste('+998 93 630 11 11');
  ok('butun maydon belgilab paste -> yangi raqam', f.value === '+998 93 630 11 11', f.value); }
{ const f = typed('90123'); f.caret(f.value.length); f.paste('4567');
  ok('to\'liq bo\'lmagan matn odatdagidek qo\'yiladi', f.value === '+998 90 123 45 67', f.value); }
// Ko'rik (R7): chet el kodi yozilgandan keyin 9 xonali milliy raqam qo'yilsa — +998 raqamga ALMASHMAYDI
{ const f = field(); f.type('+48 '); f.paste('789706619');
  ok('«+48 » + paste 789706619 -> +48 789 706 619 (begona +998 YO\'Q)', W.normPhone(f.value) === '48789706619', { v: f.value, n: W.normPhone(f.value) }); }
{ const f = field(); f.type('+'); f.paste('789706619');
  ok('«+» + paste 9 raqam -> +998 raqamga aylanmaydi', !/^\+998/.test(f.value) && W.normPhone(f.value) !== '998789706619', f.value); }
{ const f = field(); f.type('+7'); f.paste('901234567');
  ok('«+7» + paste 901234567 -> +998 90… EMAS', W.normPhone(f.value) !== '998901234567', f.value); }
{ const f = typed('901234567'); f.caret(f.value.length); f.paste('+998 93 630 11 11');
  ok('to\'liq raqam ustiga (belgilamasdan) paste -> jimgina almashtirilmaydi', f.value !== '+998 93 630 11 11' && W.normPhone(f.value) === null, f.value); }
{ const f = typed('901234567'); f.sel(5, f.value.length); f.paste('+998 93 630 11 11');
  ok('raqam qismini belgilab paste («+998 » qoladi) -> yangi raqam', f.value === '+998 93 630 11 11', f.value); }
{ const f = field(); f.value = ''; f.caret(0); f.paste('901234567');
  ok('bo\'sh maydonga 9 raqam paste -> +998 90 123 45 67', f.value === '+998 90 123 45 67', f.value); }
{ const f = typed('9045'); f.caret(7); f.paste('123');
  ok('o\'rtaga qo\'yish -> kursor qo\'yilgan matndan keyin', f.value === '+998 90 123 45' && f.selectionEnd === 11, { v: f.value, c: f.selectionEnd }); }
// Ko'rik (R6): boshidagi '+' ga tegadigan qisman tahrir begona raqam bermasligi kerak
{ const f = field(); f.type('+4791234567'); const v0 = f.value; f.caret(0); f.del();
  ok('chet el raqami: «+» oldida Delete -> o\'zgarmaydi (begona +998 raqam YO\'Q)', f.value === v0 && v0 === '+47 912 345 67', { v0, v: f.value }); }
{ const f = field(); f.type('+4791234567'); const v0 = f.value; f.sel(0, 1); f.del();
  ok('«+» ni belgilab Delete -> o\'zgarmaydi', f.value === v0, f.value); }
{ const f = field(); f.type('+7903157112'); const v0 = f.value; f.caret(0); f.del();
  ok('chala RU raqam: «+» oldida Delete -> o\'zgarmaydi', f.value === v0 && W.normPhone(f.value) === null, { v0, v: f.value }); }
{ const f = typed('901234'); const v0 = f.value; f.caret(1); f.back();
  ok('«+998 90 123 4» da «+» ni Backspace -> o\'zgarmaydi (998998… emas)', f.value === v0, { v0, v: f.value }); }
{ const f = typed('53698'); const v0 = f.value; f.caret(0); f.type('9');
  ok('«+» OLDIGA raqam yozish -> e\'tiborsiz (begona raqam yo\'q)', f.value === v0, { v0, v: f.value }); }
{ const f = field(); f.type('+33612345'); const v0 = f.value; f.caret(0); f.del();
  ok('9 xonali chet el: «+» oldida Delete -> o\'zgarmaydi', f.value === v0, { v0, v: f.value }); }
{ const f = typed('901234567'); f.sel(0, f.value.length); f.type('9');
  ok('hammasini belgilab yozish — ruxsat (+998 9)', f.value === '+998 9', f.value); }
{ const f = typed('901234567'); f.sel(0, f.value.length); f.back();
  ok('hammasini belgilab o\'chirish — bo\'sh', f.value === '', f.value); }
{ const f = field(); f.compose('901234567');
  ok('IME (kompozitsiya) -> tugagach bir marta maskalanadi, raqam takrorlanmaydi', f.value === '+998 90 123 45 67', f.value); }
{ const f = typed('9011'); f.compose('89');
  ok('IME o\'rtada davom etadi -> to\'g\'ri ketma-ketlik', W.normPhone(f.value) === null && f.value.replace(/\D/g, '') === '998901189', f.value); }
// Ko'rik (R7): kompozitsiya compositionend'siz tugasa — maska o'chib qolmasin; ko'rinib turgan '+998' ni belgilab yozish
{ const f = field(); f.dispatchEvent({ type: 'compositionstart' });
  f.dispatchEvent({ type: 'beforeinput', inputType: 'insertCompositionText', isComposing: true }); f._v = '+998 9'; f.selectionStart = f.selectionEnd = 6;
  f.dispatchEvent({ type: 'input', inputType: 'insertCompositionText', isComposing: true });
  f.sel(0, f.value.length); f.paste('+998 93 630 11 11');               // kompozitsiya o'rtasida to'liq raqam qo'yildi (compositionend yo'q)
  f.caret(8); f.back();                                                   // bo'shliqdan keyin Backspace — faqat maska ishlasa '3' o'chadi
  ok('kompozitsiya o\'rtasida paste -> keyin maska ishlaydi (bayroq osilmaydi)', f.value === '+998 96 301 11 1', f.value); }
{ const f = field(); f.dispatchEvent({ type: 'compositionstart' });
  f.dispatchEvent({ type: 'beforeinput', inputType: 'insertCompositionText', isComposing: true }); f._v = '+998 90'; f.selectionStart = f.selectionEnd = 7;
  f.dispatchEvent({ type: 'input', inputType: 'insertCompositionText', isComposing: true });
  f.dispatchEvent({ type: 'beforeinput', inputType: 'insertText', isComposing: false }); f._v = '+998 901'; f.selectionStart = f.selectionEnd = 8;
  f.dispatchEvent({ type: 'input', inputType: 'insertText', isComposing: false });
  f.type('234567');
  ok('compositionend\'siz oddiy kiritish -> maska qayta ishlaydi', f.value === '+998 90 123 45 67', f.value); }
{ const f = field(); f.dispatchEvent({ type: 'compositionstart' });
  f._v = '+998 901234567'; f.selectionStart = f.selectionEnd = 14; f.dispatchEvent({ type: 'input', inputType: 'insertCompositionText', isComposing: true });
  f.dispatchEvent({ type: 'blur' });
  ok('kompozitsiya paytida fokus ketdi -> maskalanadi', f.value === '+998 90 123 45 67', f.value); }
{ const f = field(); f.sel(0, 4); f.type('9');
  ok('ko\'rinib turgan «+998» ni belgilab yozish -> +998 9 (tugma yutilmaydi)', f.value === '+998 9', f.value); }
{ const f = typed('901'); const v0 = f.value; f.sel(0, 4); f.type('7');
  ok('«+998» ni belgilab yozish, ortida raqamlar bor -> o\'zgarmaydi (begona raqam yo\'q)', f.value === v0, { v0, v: f.value }); }
{ const f = field(); f._v = '901234567'; f.selectionStart = f.selectionEnd = 9; f.dispatchEvent({ type: 'input' });
  ok('avtoto\'ldirish (inputType yo\'q) -> maskalanadi, bloklanmaydi', f.value === '+998 90 123 45 67', f.value); }
{ const f = field(); let prevented = false; f.dispatchEvent({ type: 'dragstart', preventDefault() { prevented = true; } });
  ok('maydon ichida sudrab ko\'chirish o\'chiq', prevented); }
// FUZZ: tasodifiy tahrirlar (yozish/Backspace/Delete/belgilab yozish, kursor raqamlar ORASIDA yoki bo'shliq yonida) —
//   maydondagi raqamlar va kursor o'rni «foydalanuvchi niyati» (raqamlar ketma-ketligi) bilan doim bir xil.
{
  const dig = s => s.replace(/\D/g, '');
  const posOf = (v, c, late) => { if (c === 0) return 0; let n = 0, k = 0; for (; k < v.length; k++) { if (/\d/.test(v[k])) { n++; if (n === c) { k++; break; } } }
    if (late) while (k < v.length && v[k] === ' ') k++; return k; };          // c ta raqamdan keyin (yoki keyingi bo'shliqdan ham keyin)
  let bad = 0, ex = null, ops = 0;
  for (let run = 0; run < 3000 && !bad; run++) {
    const f = field(); let D = '998', c = 3;
    for (let step = 0; step < 25 && !bad; step++) {
      const op = rnd(5), late = rnd(2) === 1;
      if (op === 0 || D.length <= 4) { if (D.length >= 15) continue; const cc = 3 + rnd(D.length - 2); f.caret(posOf(f.value, cc, late)); const x = String(rnd(10)); f.type(x); D = D.slice(0, cc) + x + D.slice(cc); c = cc + 1; }
      else if (op === 1) { const cc = 4 + rnd(D.length - 3); f.caret(posOf(f.value, cc, late)); f.back(); D = D.slice(0, cc - 1) + D.slice(cc); c = cc - 1; }
      else if (op === 2) { const cc = 3 + rnd(D.length - 3); f.caret(posOf(f.value, cc, late)); f.del(); D = D.slice(0, cc) + D.slice(cc + 1); c = cc; }
      else if (op === 3) { const a = 3 + rnd(D.length - 3), b = a + 1 + rnd(Math.min(3, D.length - a)); if (b > D.length) continue;
        const pa = posOf(f.value, a, false); const pb = posOf(f.value, b, false); f.sel(pa === 0 ? 0 : pa, pb); const x = String(rnd(10)); f.type(x); D = D.slice(0, a) + x + D.slice(b); c = a + 1; }
      else { const cc = 3 + rnd(D.length - 2); f.caret(posOf(f.value, cc, late)); f.paste(String(rnd(10)) + String(rnd(10))); if (D.length + 2 > 15) { bad = 0; break; }
        D = D.slice(0, cc) + f.value.replace(/\D/g, '').slice(cc, cc + 2) + D.slice(cc); c = cc + 2; }
      ops++;
      const got = dig(f.value), gc = dig(f.value.slice(0, f.selectionEnd)).length;
      if (got !== D || gc !== c) { bad++; ex = { run, step, op, value: f.value, got, want: D, caret: gc, wantCaret: c }; }
    }
  }
  ok(`fuzz: ${ops} ta tahrir — raqamlar ketma-ketligi va kursor doim niyatdagidek`, bad === 0 && ops > 30000, ex || ops);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
