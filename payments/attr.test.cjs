// Attribution (findStudentByPhone) sinovi: bir xil telefonли to'lovlar noto'g'ri
// bolaга ko'r-ko'rona tushmasin. Soxta Supabase ustida handlePrepare (freeform).
//   node payments/attr.test.cjs
const fs = require('fs'), path = require('path'), crypto = require('crypto'), Module = require('module');

const { makeFake } = require('./_fake-sb.cjs');
const state = { student_private: {}, students: {}, student_codes: {}, payments: {}, invoices: {} };
const orig = Module._load;
Module._load = function (req) { if (req === '@supabase/supabase-js') return { createClient: () => makeFake(state) }; return orig.apply(this, arguments); };

const CFGFILE = path.join(__dirname, '_attr-config.json');
const SECRET = 'ATTRSECRET';
fs.writeFileSync(CFGFILE, JSON.stringify({ backend: 'supabase', supabaseUrl: 'http://x', serviceRoleKey: 'k', click: { serviceId: '111', secretKey: SECRET } }));
process.env.IQROR_CONFIG = '_attr-config.json';
const { handlePrepare } = require('./index.cjs');

let fails = 0; const ok = (c, m) => { console.log((c ? '✓ ' : '✗ FAIL ') + m); if (!c) fails++; };
function sign(p) { return crypto.createHash('md5').update([p.click_trans_id, p.service_id, SECRET, p.merchant_trans_id, p.amount, p.action, p.sign_time].join('')).digest('hex'); }
let ctN = 1000;
async function prep(name, phone, klass, amount) {
  const p = { click_trans_id: String(++ctN), service_id: '111', merchant_trans_id: name, amount: String(amount || 2900000), action: '0', sign_time: '2026-09-10 08:00:00', param2: klass || '', param3: phone || '' };
  p.sign_string = sign(p);
  await handlePrepare(p);
  return state.payments['click_' + p.click_trans_id] || {};
}

(async () => {
  // Seed: IQ-0259 (Oybekov Abdulloh) parent phone 979980808. Siblings do NOT have this phone.
  state.student_private['IQ-0259'] = { id: 'IQ-0259', parentPhone: '+998979980808' };
  state.students['IQ-0259'] = { id: 'IQ-0259', studentId: 'IQ-0259', name: 'Oybekov Abdulloh Xojiakbar', grade: 3, classLetter: 'B' };

  // T1: correct child name -> matched to IQ-0259
  let r = await prep('Oybekov Abdulloh Xojiakbar', '979980808', '3B');
  ok(r.matched === true && r.studentId === 'IQ-0259', `T1 to'g'ri ism -> IQ-0259 (via=${r.raw && r.raw.via})`);

  // T2: DIFFERENT child (Qobiljonov), same phone -> name mismatch -> NOT credited (unmatched)
  r = await prep('Qobiljonov Abdurrohman', '979980808', '5A');
  ok(r.matched === false && !r.studentId, `T2 boshqa ism (Qobiljonov) -> biriktirilmagan (via=${r.raw && r.raw.via})`);

  // T3: no name provided -> DON'T blindly trust phone -> unmatched (admin qo'lda biriktiradi)
  r = await prep('', '979980808', '');
  ok(r.matched === false && !r.studentId, `T3 ism yo'q -> biriktirilmagan (via=${r.raw && r.raw.via})`);

  // T4: two siblings share phone -> disambiguate by name
  state.student_private['IQ-0256'] = { id: 'IQ-0256', parentPhone: '+998910000000' };
  state.students['IQ-0256'] = { id: 'IQ-0256', studentId: 'IQ-0256', name: 'Oybekov Muhammadulloh', grade: 2, classLetter: 'B' };
  state.student_private['IQ-0259'].parentPhone2 = '910000000';   // both now share 910000000
  state.student_private['IQ-0256'].parentPhone = '910000000';
  r = await prep('Oybekov Muhammadulloh', '910000000', '2B');
  ok(r.matched === true && r.studentId === 'IQ-0256', `T4 aka-uka -> ism bilan Muhammadulloh=IQ-0256 (via=${r.raw && r.raw.via})`);
  r = await prep('Oybekov Abdulloh Xojiakbar', '910000000', '3B');
  ok(r.matched === true && r.studentId === 'IQ-0259', 'T4b aka-uka -> ism bilan Abdulloh=IQ-0259');

  // T5: siblings share phone, name matches NEITHER -> ambiguous -> unmatched
  r = await prep('Butunlay Boshqa Odam', '910000000', 'ZZ');
  ok(r.matched === false && !r.studentId, 'T5 aka-uka, ism hech kimга mos emas -> biriktirilmagan');

  // T6: KIRIL alifbosida ism (baza LOTINда) -> translit bilan mos -> AYNAN o'sha o'quvchiga.
  //   IQ-0259 = "Oybekov Abdulloh Xojiakbar" (lotin). Ota-ona kirilда yozadi (979980808 -> yolg'iz IQ-0259).
  state.student_private['IQ-0259'].parentPhone2 = '';   // 979980808 yana yolg'iz IQ-0259 bo'lsin
  r = await prep('Ойбеков Абдуллоҳ Хожиакбар', '979980808', '3 б');
  ok(r.matched === true && r.studentId === 'IQ-0259', `T6 kiril ism (lotin baza) -> IQ-0259 (via=${r.raw && r.raw.via})`);

  // T7: aka-uka (bir telefon), KIRIL ism bilan to'g'ri bolага -> IQ-0256 (Muhammadulloh).
  state.student_private['IQ-0259'].parentPhone2 = '910000000';   // yana ikkalasi 910000000
  r = await prep('Ойбеков Муҳаммадуллоҳ', '910000000', '2 б');
  ok(r.matched === true && r.studentId === 'IQ-0256', `T7 aka-uka kiril ism -> Muhammadulloh=IQ-0256 (via=${r.raw && r.raw.via})`);

  // T8: LOTIN ism, sinf KIRILда ("6 б") — translit sinf mosligини ta'minlaydi (nomlar farq qilса ham).
  //   Bu yerда ism aniq (Xadicha) bo'lgani uchun ism bo'yicha mos keladi; sinf kirilда ham buzmaydi.
  state.student_private['IQ-0300'] = { id: 'IQ-0300', parentPhone: '+998915151777' };
  state.students['IQ-0300'] = { id: 'IQ-0300', studentId: 'IQ-0300', name: 'Turgunboyeva Xadicha', grade: 6, classLetter: 'b' };
  r = await prep('Тургунбоева Хадича', '915151777', '6 б');
  ok(r.matched === true && r.studentId === 'IQ-0300', `T8 kiril ism+sinf -> IQ-0300 (via=${r.raw && r.raw.via})`);

  // T9: IMPORT qilingan o'quvchi (doc id != studentId). student_private/student_codes doc id = students.id —
  //   to'lov yozuvida KANONIK studentId bo'lishi shart (aks holda Moliya tekshiruvi o'quvchini ikkiga bo'lib,
  //   «Qo'llash» pulni ikki marta qo'llardi; to'lov tarixi/chekda ko'rinmasdi).
  state.student_private['fbX9kQ2'] = { id: 'fbX9kQ2', parentPhone: '+998901112233' };
  state.students['fbX9kQ2'] = { id: 'fbX9kQ2', studentId: 'IQ-0042', name: 'Karimov Sardor', grade: 5, classLetter: 'A' };
  r = await prep('Karimov Sardor', '901112233', '5A');
  ok(r.matched === true && r.studentId === 'IQ-0042', `T9 telefon (doc id fbX9kQ2) -> KANONIK IQ-0042 (got ${r.studentId})`);
  state.student_codes['fbX9kQ2'] = { id: 'fbX9kQ2', code: 'K7Q2ZP' };
  r = await prep('IQ-0042 K7Q2ZP', '', '');
  ok(r.matched === true && r.studentId === 'IQ-0042', `T10 «IQ-0042 KOD» (kod doc id bo'yicha) -> IQ-0042 (got ${r.studentId}, via=${r.raw && r.raw.via})`);
  r = await prep('K7Q2ZP', '', '');
  ok(r.matched === true && r.studentId === 'IQ-0042', `T11 faqat KOD -> KANONIK IQ-0042 (got ${r.studentId})`);
  // T12: HOZIRGI kod formati — 12 belgi (audit-4.sql / gen_student_code: upper(md5) 1..12). Avval regex {5,8}
  //   bo'lgani uchun «faqat kod» bilan to'lov topilmay, 'unmatched' bo'lib qolardi.
  state.student_codes['fbX9kQ2'] = { id: 'fbX9kQ2', code: '3FA9C21B7D0E' };
  r = await prep('3fa9c21b7d0e', '', '');
  ok(r.matched === true && r.studentId === 'IQ-0042', `T12 faqat 12 belgili KOD -> KANONIK IQ-0042 (got ${r.studentId}, via=${r.raw && r.raw.via})`);
  r = await prep('IQ-0042 3FA9C21B7D0E', '', '');
  ok(r.matched === true && r.studentId === 'IQ-0042', `T12b «IQ-0042 + 12 belgili KOD» -> IQ-0042 (got ${r.studentId})`);
  // T13: 12 xonali telefon raqami «kod» deb adashtirilmaydi — kod topilmasa avvalgidek telefon yo'liga o'tadi
  //   (ism yo'q -> 'ambiguous' -> admin qo'lda biriktiradi; avvalgi xatti-harakat bilan bir xil).
  r = await prep('998901112233', '901112233', '');
  ok(r.raw && r.raw.via !== 'code' && r.matched !== true, `T13 12 xonali raqam kod emas -> telefon yo'li (via=${r.raw && r.raw.via}, matched=${r.matched})`);

  fs.unlinkSync(CFGFILE);
  console.log(fails ? `\n❌ ${fails} FAILED` : '\n✅ ALL PASS — attribution ismni tekshiradi');
  process.exit(fails ? 1 : 0);
})().catch(e => { try { fs.unlinkSync(CFGFILE); } catch (_) {} console.error('ERR', e); process.exit(1); });
