// To'lovchi matnidagi MAXFIY KOD (egasi qarori (a), 2026-11-16; migration/payer-code-mask.sql) sinovi, soxta Supabase ustida:
//   - saqlashda kod «[kod]» bo'ladi: Click erkin (merchant_trans_id / payerName / payerClass / payerPhone) va aniq rejim,
//     Uzum create (raw — butun so'rov), confirm / reverse (saqlangan raw qayta yozilganda — eski server yozgani ham), debug log;
//   - biriktirish ASL matn bilan, Click / Uzum javobi provayderning asl qiymatlarini qaytaradi;
//   - almashtirilgan (eski) kod — student_code_prev — TO'LOV uchun ishlaydi (Click erkin, Uzum check / create);
//   - bazadan o'qib bo'lmasa — shakl qoidasi (fail-closed): 12 ta 0-9/A-F va harfli bo'lak; telefon va IQ-0042 tegilmaydi.
//   2-raund: guruhlab yozilgan kod («3FA9 C21B 7D0E», «-», «.», 6+6, sinf bilan) va kiril / «O» harfli kod — yashiriladi VA kod
//   egasiga biriktiriladi (via 'code_norm'; boshqa o'quvchi ID'si yoki ikki ega bo'lsa — yo'q); bitta jadval o'qilmasa ham ikkinchisida
//   topilgan kod yashiriladi; aralash doc id («fbX9kQ2 KOD») biriktiriladi; SQL app.payer_mask bilan bir xil natija.
//   3-raund: matnda BOSHQA o'quvchi tilga olingan bo'lsa («IQ-0043-KOD», «_», «(…)», «№», apostrof, «IQ 0043», «IQ0043KOD», kiril harfli
//   kod, «-» bilan yopishgan doc id, sinf maydonida «5A-IQ-0043», bazada yo'q IQ-raqam) — kod bo'yicha biriktirilmaydi (kod egasi qoidasi
//   ham, aniq kod qoidalari ham); egasining o'z ID'si / telefon / summa / sana / sinf / hex «axlat» bilan — biriktiriladi; o'quvchilar
//   ro'yxati o'qilmasa — yo'q; Uzum'da kod egasi bo'yicha topilgani raw.via = 'code_norm'; «[kod]» — kod va unga yondosh hex bo'laklar
//   (yaqin nusxa ham), IQ-ID va so'z qoladi; ajratgich — 1–2 ta [bo'sh joy, tab . , - _ /] yoki 3 tagacha bo'sh joy belgisi (yangi qator).
//   4-raund: so'z boshidagi «IQ» va raqam orasida 3 tagacha istalgan belgi («IQ,0043», «IQ(0043)», «IQ  -  0043»), kiril «ИҚ» / «ІQ» —
//   boshqa o'quvchi ID'si; ism oxiridagi «…iq» («Rafiq», «Sodiq») — ID emas; aniq kod qoidalarida ham matnda ikkinchi o'quvchining kodi
//   bo'lsa — biriktirilmaydi (T1–T3, U13); telefon (+ ism) bir bolani, kod boshqasini ko'rsatsa — 'code_conflict' (N4, X1–X8);
//   shakl qoidasi sinf + bo'sh joyli telefon / sana / summani kod deb olmaydi (F7b).
//   5-raund: faktura ID («IQ-0050__2026-08», fakturasi yo'q) — matnda boshqa o'quvchining kodi / ID'si yoki 'code_conflict' bo'lsa
//   biriktirilmaydi, Uzum o'zgarmagan (I1–I12); telefon (+ ism) qoidasi matnda boshqa o'quvchining ID'si bo'lsa — 'code_conflict' (Y1–Y8);
//   kodlarni o'qib bo'lmasa telefon / faktura ID qoidasi faqat kodga o'xshash tekshirilmagan bo'lak bo'lmasa ishlaydi (F8–F9b); SID_IQ
//   taniydigan IQ-ID raqami «[kod]» ga qo'shilmaydi (O23, O31–O43, Q15–Q16, P3 = SQL M26); sinf «5-A» / «5 A» / «A5» (F7b, F7c).
//   node payments/mask.test.cjs
const fs = require('fs'), path = require('path'), crypto = require('crypto'), Module = require('module');

const { makeFake } = require('./_fake-sb.cjs');
const state = { student_private: {}, students: {}, student_codes: {}, student_code_prev: {}, payments: {}, invoices: {},
                student_credit: {}, applied_payments: {} };
// state.__down — shu jadvallarni o'qish xato beradi (baza ishlamay qolgan holat: fail-closed sinovi); state.__downList — faqat
//   ro'yxat so'rovi (collection().get / where) xato beradi, bitta qator (doc().get) o'qiladi; state.__pgrstIn — PostgREST kabi:
//   «in» ro'yxatida qo'shtirnoq / teskari chiziqli qiymat bo'lsa so'rov xato beradi (supabase-js ularni ekranlamaydi).
const mkClient = () => { const f = makeFake(state); const from0 = f.from.bind(f);
  f.from = t => { const api = from0(t);
    const err = { data: null, error: { message: 'fake: down' } };
    if (state.__down && state.__down.has(t)) {
      api.then = res => Promise.resolve(err).then(res); api.maybeSingle = () => Promise.resolve(err); }
    else if (state.__downList && state.__downList.has(t)) api.then = res => Promise.resolve(err).then(res);
    if (state.__pgrstIn) { const in0 = api.in;
      api.in = (fld, vals) => { if ((vals || []).some(v => /["\\]/.test(String(v))))
        api.then = res => Promise.resolve({ data: null, error: { code: 'PGRST100', message: 'fake: in-list parse' } }).then(res);
        return in0(fld, vals); }; }
    return api; };
  return f; };
const orig = Module._load;
Module._load = function (req) { if (req === '@supabase/supabase-js') return { createClient: mkClient }; return orig.apply(this, arguments); };

const CFGFILE = path.join(__dirname, '_mask-config.json');
const SECRET = 'MASKSECRET', SID = 'SVC-9', LOGIN = 'iqror', PASS = 'p@ss';
fs.writeFileSync(CFGFILE, JSON.stringify({ backend: 'supabase', supabaseUrl: 'http://x', serviceRoleKey: 'k', debugClick: true,
  click: { serviceId: '111', secretKey: SECRET }, uzum: { serviceId: SID, login: LOGIN, password: PASS, accountField: 'account', amountUnit: 'tiyin' } }));
process.env.IQROR_CONFIG = '_mask-config.json';
const { handlePrepare, handleComplete, handleUzum, maskPayer, md5 } = require('./index.cjs');

let fails = 0; const ok = (c, m) => { console.log((c ? '✓ ' : '✗ FAIL ') + m); if (!c) fails++; };
function sign(p, isComplete) {
  const parts = [p.click_trans_id, p.service_id, SECRET, p.merchant_trans_id];
  if (isComplete) parts.push(p.merchant_prepare_id);
  parts.push(p.amount, p.action, p.sign_time);
  return md5(parts.join(''));
}
let ctN = 5000;
async function prep(mti, klass, phone, amount) {
  const p = { click_trans_id: String(++ctN), service_id: '111', merchant_trans_id: mti, amount: String(amount || 1000), action: '0',
              sign_time: '2026-09-10 08:00:00', param2: klass || '', param3: phone || '' };
  p.sign_string = sign(p, false);
  const res = await handlePrepare(p);
  return { p, res, row: state.payments['click_' + p.click_trans_id] || {} };
}
const has = (row, s) => JSON.stringify(row).toUpperCase().includes(String(s).toUpperCase());

// Sinov kodlari (to'qima): joriy va almashtirilgan
const CUR = '3FA9C21B7D0E', OLD = '9C0D1E2F3A4B', CUR_U = '5E6F7A8B9C0D', OLD_U = 'ABCDEF012345', CUR_B = '0A1B2C3D4E5F', DIGITS = '123456789012';

(async () => {
  // Import qilingan o'quvchi (doc id != studentId): kod doc id bilan kalitlangan.
  state.students['fbX9kQ2'] = { id: 'fbX9kQ2', studentId: 'IQ-0042', name: 'Sinov Sardor', grade: 5, classLetter: 'A' };
  state.student_codes['fbX9kQ2'] = { id: 'fbX9kQ2', code: CUR };
  state.student_code_prev[OLD] = { code: OLD, studentDocId: 'fbX9kQ2', retiredAt: '2026-11-16T00:00:00Z' };
  state.invoices['IQ-0042__2026-09'] = { id: 'IQ-0042__2026-09', amount: 500000, status: 'unpaid', studentId: 'IQ-0042', month: '2026-09' };
  state.students['IQ-0043'] = { id: 'IQ-0043', studentId: 'IQ-0043', name: 'Sinov Boshqa', grade: 6, classLetter: 'B' };
  state.student_codes['IQ-0043'] = { id: 'IQ-0043', code: CUR_B };
  // Uzum uchun alohida o'quvchi
  state.students['IQ-0050'] = { id: 'IQ-0050', studentId: 'IQ-0050', name: 'Sinov Uzum', grade: 7, classLetter: 'A' };
  state.student_codes['IQ-0050'] = { id: 'IQ-0050', code: CUR_U };
  state.student_code_prev[OLD_U] = { code: OLD_U, studentDocId: 'IQ-0050', retiredAt: '2026-11-16T00:00:00Z' };
  state.invoices['IQ-0050__2026-09'] = { id: 'IQ-0050__2026-09', amount: 300000, status: 'unpaid', studentId: 'IQ-0050', month: '2026-09' };
  state.invoices['IQ-0050__2026-10'] = { id: 'IQ-0050__2026-10', amount: 300000, status: 'unpaid', studentId: 'IQ-0050', month: '2026-10' };
  // Faqat raqamdan iborat kod (gen_student_code bunday kod ham berishi mumkin)
  state.students['IQ-0060'] = { id: 'IQ-0060', studentId: 'IQ-0060', name: 'Sinov Raqam', grade: 8, classLetter: 'A' };
  state.student_codes['IQ-0060'] = { id: 'IQ-0060', code: DIGITS };

  // ---------- Click: erkin rejim ----------
  const logs = []; const ce = console.error; console.error = (...a) => { logs.push(a.join(' ')); };
  let r = await prep('IQ-0042 3fa9c21b7d0e', '5A', '998000000017');
  console.error = ce;
  ok(r.res.error === 0 && r.res.merchant_trans_id === 'IQ-0042 3fa9c21b7d0e', 'M1 javob: Click\'ning asl merchant_trans_id\'si (kod bilan) qaytadi');
  ok(r.row.matched === true && r.row.studentId === 'IQ-0042' && r.row.raw && r.row.raw.via === 'code', `M1 biriktirish asl matn bilan (studentId=${r.row.studentId}, via=${r.row.raw && r.row.raw.via})`);
  ok(r.row.merchant_trans_id === 'IQ-0042 [kod]' && r.row.payerName === 'IQ-0042 [kod]', `M1 saqlangan merchant_trans_id / payerName yashirilgan («${r.row.merchant_trans_id}»)`);
  ok(r.row.payerPhone === '998000000017' && r.row.payerClass === '5A', 'M1 telefon va sinf o\'zgarmagan');
  ok(!has(r.row, CUR), 'M1 to\'lov qatorining hech bir joyida kod yo\'q');
  ok(logs.some(l => l.includes('[CLICK-DEBUG]') && l.includes('[kod]')) && !logs.some(l => l.toUpperCase().includes(CUR)), 'M1 [CLICK-DEBUG] logida ham kod yashirilgan');
  const m1 = r;

  r = await prep('Sinov Sardor', '5A ' + CUR.toLowerCase(), CUR);
  ok(r.row.payerClass === '[kod]' && r.row.payerPhone === '[kod]' && r.row.payerName === 'Sinov Sardor', `M2 payerClass / payerPhone (param2 / param3) ham yashirilgan; «5A» kodga yondosh hex bo'lak — u ham («${r.row.payerClass}», «${r.row.payerPhone}»)`);

  r = await prep('IQ-0042 ' + OLD.toLowerCase());
  ok(r.row.matched === true && r.row.studentId === 'IQ-0042' && r.row.raw.via === 'code', `M3 ESKI kod «ID KOD» bilan -> IQ-0042 (via=${r.row.raw.via})`);
  ok(r.row.merchant_trans_id === 'IQ-0042 [kod]' && !has(r.row, OLD), 'M3 eski kod ham yashirilgan');

  r = await prep(OLD);
  ok(r.row.matched === true && r.row.studentId === 'IQ-0042', `M4 faqat ESKI kod -> IQ-0042 (got ${r.row.studentId})`);
  ok(r.row.payerName === '[kod]', 'M4 saqlangan matn — «[kod]»');

  r = await prep('IQ-0050 ' + OLD_U.toLowerCase());   // kod qatori shu kalit bilan (doc id = studentId)
  ok(r.row.matched === true && r.row.studentId === 'IQ-0050' && r.row.payerName === 'IQ-0050 [kod]', `M5 «ID + ESKI kod» (kod qatori shu ID bilan) -> IQ-0050 (got ${r.row.studentId})`);

  r = await prep('IQ-0043 ' + OLD);
  ok(!(r.row.raw.via === 'code' && r.row.studentId === 'IQ-0043'), `M6 boshqa o'quvchining eski kodi IQ-0043 ga biriktirilmaydi (got ${r.row.studentId}, via=${r.row.raw.via})`);
  ok(r.row.payerName === 'IQ-0043 [kod]', 'M6 ... lekin baribir yashirilgan (kimningdir eski kodi)');

  r = await prep('IQ0042' + CUR);
  ok(r.row.payerName === 'IQ0042[kod]', `M7 bo'sh joysiz «IQ0042KOD» — bo'lak ichidagi kod yashirilgan («${r.row.payerName}»)`);

  r = await prep('Kod: 3FА9С21В7D0Е');   // kiril А, С, В, Е
  ok(r.row.payerName === 'Kod: [kod]', `M8 kiril harfli (ko'rinishi bir xil) kod ham yashirilgan («${r.row.payerName}»)`);
  r = await prep('3FA9C21B7DOE');        // nol o'rniga «O»
  ok(r.row.payerName === '[kod]', 'M8b nol o\'rniga «O» harfi bilan yozilgan kod ham yashirilgan');

  r = await prep('Sinov ABCDEF123456 Ota');
  ok(r.row.payerName === 'Sinov ABCDEF123456 Ota', 'M9 kodga o\'xshash, lekin hech kimning kodi emas — o\'zgarmaydi (baza ishlayapti)');

  r = await prep('Sinov Ota ' + CUR_B + ' va ' + CUR);
  ok(r.row.payerName === 'Sinov Ota [kod] va [kod]', `M10 matndagi ikki o'quvchining kodi ham yashirilgan («${r.row.payerName}»)`);

  // ---------- 2-raund: guruhlab yozilgan / kiril / «O» harfli kod — yashiriladi VA kod egasiga biriktiriladi ----------
  const via = row => `«${row.payerName}», studentId=${row.studentId}, via=${row.raw && row.raw.via}`;
  const norm = (row, sid) => row.matched === true && row.studentId === sid && row.raw && row.raw.via === 'code_norm';
  r = await prep('IQ-0042 3FA9 C21B 7D0E');
  ok(r.row.payerName === 'IQ-0042 [kod]' && r.row.merchant_trans_id === 'IQ-0042 [kod]' && norm(r.row, 'IQ-0042'), `G1 «ID + 4-4-4 guruh» -> «ID [kod]», kod egasiga (${via(r.row)})`);
  r = await prep('3fa9-c21b-7d0e');
  ok(r.row.payerName === '[kod]' && norm(r.row, 'IQ-0042'), `G2 «-» bilan guruh (kichik harf) (${via(r.row)})`);
  r = await prep('IQ-0042 3FA9C2 1B7D0E');
  ok(r.row.payerName === 'IQ-0042 [kod]' && norm(r.row, 'IQ-0042'), `G3 «ID + 6+6 guruh» (${via(r.row)})`);
  r = await prep('IQ-0042 3FA9.C21B.7D0E');
  ok(r.row.payerName === 'IQ-0042 [kod]' && norm(r.row, 'IQ-0042'), `G4 «.» bilan guruh (${via(r.row)})`);
  r = await prep('Sinov Sardor', '5A 3FA9C21B 7D0E');
  ok(r.row.payerClass === '[kod]' && r.row.payerName === 'Sinov Sardor' && norm(r.row, 'IQ-0042'), `G5 payerClass «5A + 8+4 guruh» -> «[kod]» («5A» — yondosh hex bo'lak), ism o'zgarmagan (${r.row.payerClass}; ${via(r.row)})`);
  r = await prep('3FA9C21B7DOE');
  ok(r.row.payerName === '[kod]' && norm(r.row, 'IQ-0042'), `V1 nol o'rniga «O» — yashirildi VA biriktirildi (${via(r.row)})`);
  r = await prep('Kod: 3FА9С21В7D0Е');   // kiril А, С, В, Е
  ok(r.row.payerName === 'Kod: [kod]' && norm(r.row, 'IQ-0042'), `V2 kiril harfli kod — yashirildi VA biriktirildi (${via(r.row)})`);
  r = await prep('IQ-0042 3FА9С21В7D0Е');
  ok(r.row.payerName === 'IQ-0042 [kod]' && norm(r.row, 'IQ-0042'), `V3 «ID + kiril harfli kod» (${via(r.row)})`);
  r = await prep('Kod 9COD 1E2F 3A4B');  // ESKI kod: guruh + «O»
  ok(r.row.payerName === 'Kod [kod]' && norm(r.row, 'IQ-0042'), `V4 ESKI kod guruhlab va «O» bilan — egasiga (${via(r.row)})`);
  r = await prep('IQ-0042 3FA9 C21B 7D0E / 9C0D 1E2F 3A4B');
  ok(r.row.payerName === 'IQ-0042 [kod] / [kod]' && norm(r.row, 'IQ-0042'), `V5 bitta o'quvchining joriy va eski kodi — biriktiriladi (${via(r.row)})`);
  // ehtiyotkorlik: boshqa o'quvchi ID'si, ikki ega, egasi yo'q, mavjud qoidalar ustun
  r = await prep('IQ-0043 3FA9 C21B 7D0E');
  ok(r.row.payerName === 'IQ-0043 [kod]' && r.row.matched === false && r.row.studentId === '' && r.row.raw.via !== 'code_norm', `N1 matnda BOSHQA o'quvchi ID'si (IQ-0043) — biriktirilmaydi, lekin yashirildi (${via(r.row)})`);
  r = await prep('Sinov 3FA9 C21B 7D0E 0A1B 2C3D 4E5F');
  ok(r.row.payerName === 'Sinov [kod]' && r.row.matched === false && r.row.studentId === '', `N2 ikki o'quvchining kodi (bitta hex qatorda — bitta «[kod]») — biriktirilmaydi, ikkalasi yashirildi (${via(r.row)})`);
  state.student_codes['fbGHOST2'] = { id: 'fbGHOST2', code: '0F0E0D0C0B0A' };   // o'chirilgan o'quvchidan qolgan kod qatori
  r = await prep('Kod 0F0E 0D0C 0B0A');
  ok(r.row.payerName === 'Kod [kod]' && r.row.matched === false && r.row.studentId === '', `N3 egasi (o'quvchi) yo'q kod — biriktirilmaydi, yashirildi (${via(r.row)})`);
  state.student_private['IQ-0043'] = { id: 'IQ-0043', parentPhone: '+998000000043' };
  r = await prep('Sinov Boshqa 3FA9 C21B 7D0E', '', '998000000043');
  ok(r.row.payerName === 'Sinov Boshqa [kod]' && r.row.matched === false && r.row.studentId === '' && r.row.raw.via === 'code_conflict',
    `N4 telefon + ism IQ-0043 ni, kod IQ-0042 ni ko'rsatadi — biriktirilmaydi (telefon qoidasi ham, kod egasi qoidasi ham), yashirildi (${via(r.row)})`);
  r = await prep('Sinov Boshqa 0A1B 2C3D 4E5F', '', '998000000043');
  ok(r.row.payerName === 'Sinov Boshqa [kod]' && r.row.studentId === 'IQ-0043' && r.row.raw.via === 'phone', `N4b telefon + ism va kod bitta o'quvchiniki — telefon qoidasi (${via(r.row)})`);
  delete state.student_private['IQ-0043'];
  // telefon (+ ism) qoidasi: aka-uka bir telefonda — matndagi kod ismdagi bolaniki bo'lmasa biriktirilmaydi (via 'code_conflict')
  const CUR_S = '1C2D3E4F5A6B';
  state.students['IQ-0044'] = { id: 'IQ-0044', studentId: 'IQ-0044', name: 'Sinov Bobur', grade: 6, classLetter: 'B' };
  state.student_codes['IQ-0044'] = { id: 'IQ-0044', code: CUR_S };
  state.student_private['fbX9kQ2'] = { id: 'fbX9kQ2', parentPhone: '+998000000044' };
  state.student_private['IQ-0044'] = { id: 'IQ-0044', parentPhone: '+998000000044' };
  for(const [n, mti, want, sid] of [
    ['X1 B ismi + A kodi', 'Bobur ' + CUR, 'Bobur [kod]', ''], ['X2 B ismi + A kodi guruhlab', 'Bobur 3FA9 C21B 7D0E', 'Bobur [kod]', ''],
    ['X3 B ismi + A va B kodlari', 'Bobur ' + CUR_S + ' / ' + CUR, 'Bobur [kod] / [kod]', ''],
    ['X4 B ismi + B kodi', 'Bobur ' + CUR_S, 'Bobur [kod]', 'IQ-0044'], ['X5 faqat B ismi (avvalgidek)', 'Bobur', 'Bobur', 'IQ-0044'],
    // to'liq ism (familiya ikkalasida bir xil): kod ismdan olib tashlanib solishtiriladi — ism B ni, kod A ni ko'rsatsa — yo'q
    ['X6 B ning to\'liq ismi + A kodi', 'Sinov Bobur ' + CUR, 'Sinov Bobur [kod]', ''],
    ['X7 B ning to\'liq ismi + B kodi', 'Sinov Bobur ' + CUR_S, 'Sinov Bobur [kod]', 'IQ-0044'],
    ['X8 A ning to\'liq ismi + A kodi guruhlab', 'Sinov Sardor 3FA9 C21B 7D0E', 'Sinov Sardor [kod]', 'IQ-0042']]){
    r = await prep(mti, '', '998000000044');
    const good = sid ? (r.row.matched === true && r.row.studentId === sid && r.row.raw.via === 'phone')
                     : (r.row.matched === false && r.row.studentId === '' && r.row.raw.via === 'code_conflict');
    ok(r.row.payerName === want && good, `${n}: «${mti}» + umumiy telefon — ${sid || 'biriktirilmadi'} (${via(r.row)})`);
  }
  delete state.students['IQ-0044']; delete state.student_codes['IQ-0044'];
  delete state.student_private['fbX9kQ2']; delete state.student_private['IQ-0044'];
  // aralash harfli doc id (import qilingan Firebase id) + kod — doc id katta-kichik harfga sezgir (R6)
  r = await prep('fbX9kQ2 3fa9c21b7d0e');
  ok(r.row.matched === true && r.row.studentId === 'IQ-0042' && r.row.raw.via === 'code' && r.row.payerName === 'fbX9kQ2 [kod]', `D1 «docId KOD» (fbX9kQ2) -> IQ-0042, via=code (${via(r.row)})`);
  r = await prep('fbX9kQ2 ' + OLD);
  ok(r.row.matched === true && r.row.studentId === 'IQ-0042' && r.row.raw.via === 'code', `D2 «docId ESKI KOD» -> IQ-0042, via=code (${via(r.row)})`);
  r = await prep(CUR + ' fbX9kQ2');
  ok(r.row.matched === true && r.row.studentId === 'IQ-0042' && r.row.raw.via === 'code', `D3 «KOD docId» (teskari tartib) -> IQ-0042, via=code (${via(r.row)})`);
  // IQ-raqam qiymat bo'yicha: «IQ-42» = «IQ-0042» (boshidagi nollarsiz yozilgan egasining ID'si — boshqa o'quvchi emas)
  r = await prep('IQ-42 3FA9 C21B 7D0E');
  ok(r.row.matched === true && r.row.studentId === 'IQ-0042' && r.row.raw.via === 'code_norm' && r.row.payerName === 'IQ-42 [kod]', `O15 egasining ID'si nollarsiz («IQ-42») + guruhlab yozilgan kod -> IQ-0042, via=code_norm (${via(r.row)})`);
  r = await prep('IQ-042 ' + CUR);
  ok(r.row.matched === true && r.row.studentId === 'IQ-0042' && r.row.payerName === 'IQ-042 [kod]', `O15b «IQ-042 KOD» -> IQ-0042 (${via(r.row)})`);
  // 3-raund (C1): matnda BOSHQA o'quvchi (IQ-0043 / fbX9kQ2) quyidagi shakllarda tilga olingan bo'lsa — kod bo'yicha biriktirilmaydi (kod egasi qoidasi
  //   ham, aniq kod qoidalari ham); yashirish baribir ishlaydi
  const refused = row => row.matched === false && row.studentId === '' && !!row.raw && row.raw.via !== 'code_norm' && row.raw.via !== 'code';
  for(const [n, mti, want, klass] of [
    ['O1 «-» bilan yopishgan ID', 'IQ-0043-3FA9C21B7D0E', 'IQ-0043-[kod]'], ['O2 «_»', 'IQ-0043_3FA9C21B7D0E', 'IQ-0043_[kod]'],
    ['O3 qavs ichida', '(IQ-0043)3FA9C21B7D0E', '(IQ-0043)[kod]'], ['O4 «№», guruhlab yozilgan kod', '№IQ-0043 3FA9 C21B 7D0E', '№IQ-0043 [kod]'],
    ['O5 apostrof', "IQ-0043'3FA9C21B7D0E", "IQ-0043'[kod]"], ['O6 kichik harf, hammasi «-» bilan', 'iq-0043-3fa9-c21b-7d0e', 'iq-0043-[kod]'],
    ['O7 ID ichida bo\'sh joy', 'IQ 0043 3FA9 C21B 7D0E', 'IQ 0043 [kod]'], ['O8 ID «-»siz', 'IQ0043 3FA9C21B7D0E', 'IQ0043 [kod]'],
    ['O9 ID kodga ajratgichsiz yopishgan', 'IQ00433FA9C21B7D0E', 'IQ0043[kod]'], ['O10 kiril harfli kod + «-» bilan ID', 'IQ-0043-3FА9С21В7D0Е', 'IQ-0043-[kod]'],
    ['O11 boshqa o\'quvchi ID\'si sinf maydonida «5A-IQ-0043»', '3FA9 C21B 7D0E', '[kod]', '5A-IQ-0043'],
    ['O12 boshqa o\'quvchining doc id\'si (fbX9kQ2) + IQ-0050 kodi guruhlab', 'fbX9kQ2 5E6F 7A8B 9C0D', 'fbX9kQ2 [kod]'],
    ['O13 boshqa o\'quvchining doc id\'si «-» bilan yopishgan', 'fbX9kQ2-5E6F7A8B9C0D', 'fbX9kQ2-[kod]'],
    ['O14 bazada yo\'q IQ-raqam (o\'chirilgan / xato yozilgan ID)', 'IQ-0099 3FA9 C21B 7D0E', 'IQ-0099 [kod]'],
    ['O16 IQ-0050 kodi, hammasi «-» bilan («IQ-0043-5E6F-7A8B-9C0D»)', 'IQ-0043-5E6F-7A8B-9C0D', 'IQ-0043-[kod]'],
    ['O17 «№IQ-0043 5E6F 7A8B 9C0D»', '№IQ-0043 5E6F 7A8B 9C0D', '№IQ-0043 [kod]'],
    ['O18 «faqat kod» qoidasi: kod aniq, sinf maydonida boshqa o\'quvchi ID\'si', CUR_U, '[kod]', '5A-IQ-0043'],
    ['O19 «ID + kod» qoidasi: egasining ID\'si va kodi, yana boshqa o\'quvchi ID\'si', 'IQ-0050 ' + CUR_U + ' IQ-0043', 'IQ-0050 [kod] IQ-0043'],
    ['O20 «faqat kod» qoidasi: sinf maydonida boshqa o\'quvchining doc id\'si', CUR_U, '[kod]', 'fbX9kQ2'],
    ['O23 sinfga ajratgichsiz yopishgan boshqa o\'quvchi ID\'si («5AIQ-0043»; SID_IQ taniydi — raqami qoladi)', '5AIQ-0043 3FA9 C21B 7D0E', '5AIQ-0043 [kod]'],
    // ko'rik misollari aynan: IQ-0042 (doc id fbX9kQ2) — IQ-0050 kodi bilan
    ['O24 «IQ-0042-5E6F-7A8B-9C0D»', 'IQ-0042-5E6F-7A8B-9C0D', 'IQ-0042-[kod]'], ['O25 «№IQ-0042 5E6F 7A8B 9C0D»', '№IQ-0042 5E6F 7A8B 9C0D', '№IQ-0042 [kod]'],
    ['O26 apostrof', "IQ-0042'5E6F7A8B9C0D", "IQ-0042'[kod]"], ['O27 kiril harfli kod', 'IQ-0042-5Е6F7А8В9С0D', 'IQ-0042-[kod]'],
    ['O28 sinf maydonida «5A-IQ-0042», IQ-0050 kodi guruhlab', '5E6F 7A8B 9C0D', '[kod]', '5A-IQ-0042'],
    // so'z boshidagi «IQ» va raqam orasida 3 tagacha istalgan belgi (bo'sh joylar sanalmaydi), kiril harfli «IQ»
    ['O29 «IQ,0043»', 'IQ,0043 3FA9 C21B 7D0E', 'IQ,0043 [kod]'], ['O30 «IQ(0043)»', 'IQ(0043) 3FA9 C21B 7D0E', 'IQ(0043) [kod]'],
    ['O31 «IQ+0043»', 'IQ+0043 3FA9 C21B 7D0E', 'IQ+0043 [kod]'], ['O32 «IQ=0043»', 'IQ=0043 3FA9 C21B 7D0E', 'IQ=0043 [kod]'],
    ["O33 «IQ'0043»", "IQ'0043 3FA9 C21B 7D0E", "IQ'0043 [kod]"], ['O34 «IQ\\0043»', 'IQ\\0043 3FA9 C21B 7D0E', 'IQ\\0043 [kod]'],
    ['O35 «IQ  -  0043»', 'IQ  -  0043 3FA9 C21B 7D0E', 'IQ  -  0043 [kod]'], ['O36 «ID: iq #0043»', 'ID: iq #0043 3FA9 C21B 7D0E', 'ID: iq #0043 [kod]'],
    ['O37 kiril «ИҚ-0043»', 'ИҚ-0043 3FA9 C21B 7D0E', 'ИҚ-0043 [kod]'], ['O38 kiril «І» bilan «ІQ-0043»', 'ІQ-0043 3FA9 C21B 7D0E', 'ІQ-0043 [kod]'],
    ['O39 kiril «ик 0043» (kichik harf)', 'ик 0043 3FA9 C21B 7D0E', 'ик 0043 [kod]'], ['O40 sinf maydonida kiril «ІҚ 0043»', '3FA9 C21B 7D0E', '[kod]', 'ІҚ 0043'],
    ['O41 lotin I + kiril Қ «IҚ_0043»', 'IҚ_0043 3FA9 C21B 7D0E', 'IҚ_0043 [kod]'],
    // IQ belgisidan keyingi raqam kodga yopishgan bo'lsa ham qoladi (SID_IQ ham shu raqamni oladi)
    ['O42 «IQ+0043» kodga yopishgan', 'IQ+00433FA9C21B7D0E', 'IQ+0043[kod]'], ['O43 kiril «ИК 0043» kodga yopishgan', 'ИК 00433FA9C21B7D0E', 'ИК 0043[kod]']]){
    r = await prep(mti, klass || '');
    ok(r.row.payerName === want && refused(r.row), `${n}: «${mti}»${klass ? ' / «' + klass + '»' : ''} — biriktirilmadi, yashirildi (${via(r.row)})`);
  }
  // aniq kod qoidalari ham: matnda boshqa o'quvchining (joriy yoki eski) kodi bo'lsa — biriktirilmaydi (kod egasi qoidasi ham: ikki ega)
  for(const [n, mti, klass, want, wantK] of [
    ['T1 «ID + A kodi + B kodi»', 'IQ-0042 ' + CUR + ' ' + CUR_U, '', 'IQ-0042 [kod]', ''],
    ['T2 «faqat A kodi», sinf maydonida B kodi', CUR, CUR_U, '[kod]', '[kod]'],
    ['T3 «ID + A kodi + B ning ESKI kodi»', 'IQ-0042 ' + CUR + ' ' + OLD_U, '', 'IQ-0042 [kod]', '']]){
    r = await prep(mti, klass);
    ok(r.row.payerName === want && r.row.payerClass === wantK && refused(r.row), `${n} — biriktirilmadi, yashirildi (${via(r.row)}, «${r.row.payerClass}»)`);
  }
  r = await prep('IQ-0042 ' + CUR + ' ' + OLD);
  ok(r.row.payerName === 'IQ-0042 [kod]' && r.row.matched === true && r.row.studentId === 'IQ-0042' && r.row.raw.via === 'code', `T4 «ID + joriy kod + o'zining ESKI kodi» — egasiga, via=code (${via(r.row)})`);
  // ... egasining o'z ID'si / doc id'si va boshqa raqamlar (telefon, summa, sana, sinf, hex «axlat») bilan — biriktiriladi
  for(const [n, mti, want, sid, klass, phone] of [
    ['Q1 egasining doc id\'si «-» bilan yopishgan', 'fbX9kQ2-3FA9-C21B-7D0E', 'fbX9kQ2-[kod]', 'IQ-0042'],
    ['Q2 egasining ID\'si kodga ajratgichsiz yopishgan', 'IQ00423FA9C21B7D0E', 'IQ0042[kod]', 'IQ-0042'],
    ['Q3 egasining ID\'si «-» bilan yopishgan', 'IQ-0042-3FA9C21B7D0E', 'IQ-0042-[kod]', 'IQ-0042'],
    ['Q4 «Sinoviq» (ism oxiridagi «iq» + raqam ID emas), summa kodga yondosh', 'Sinoviq 1 500 000 3FA9 C21B 7D0E', 'Sinoviq [kod]', 'IQ-0042'],
    ['Q5 telefon, summa, sana, sinf bilan', 'Sinov Ota 3FA9 C21B 7D0E +998 90 123 45 67 1 500 000 16.11.2026', 'Sinov Ota [kod] +998 90 123 45 67 1 500 000 16.11.2026', 'IQ-0042', '5A', '998901234567'],
    ['Q6 hex «axlat» bilan', '5E6F 7A8B 9C0D DEADBEEF0000 CAFE', '[kod]', 'IQ-0050'],
    ['Q7 egasining ID\'si sinf maydonida («5A-IQ-0050»)', '5E6F 7A8B 9C0D', '[kod]', 'IQ-0050', '5A-IQ-0050'],
    ['Q8 boshqa o\'quvchining doc id\'si BOSHQA harf o\'lchamida (FBX9KQ2 — R6: doc id emas)', 'FBX9KQ2 5E6F 7A8B 9C0D', 'FBX9KQ2 [kod]', 'IQ-0050'],
    ['Q8b «Sinoviq1500» (ismga yopishgan raqam — ID emas)', 'Sinoviq1500 5E6F 7A8B 9C0D', 'Sinoviq1500 [kod]', 'IQ-0050'],
    // «…iq» bilan tugaydigan ism — harfga yopishgan «iq» ID emas (kengaytirilgan qoidada ham)
    ['Q12 «Rafiq KOD»', 'Rafiq ' + CUR, 'Rafiq [kod]', 'IQ-0042'], ['Q13 «Sodiq» + guruhlab yozilgan kod', 'Sodiq 3FA9 C21B 7D0E', 'Sodiq [kod]', 'IQ-0042'],
    ['Q14 «Sodiq 0043 …» (raqam ID emas)', 'Sodiq 0043 3FA9 C21B 7D0E', 'Sodiq [kod]', 'IQ-0042'],
    ['Q15 egasining o\'z ID\'si kiril harflarda («ИҚ-0050»)', 'ИҚ-0050 5E6F 7A8B 9C0D', 'ИҚ-0050 [kod]', 'IQ-0050'],
    ['Q16 egasining o\'z ID\'si «IQ = 0050»', 'IQ = 0050 5E6F 7A8B 9C0D', 'IQ = 0050 [kod]', 'IQ-0050']]){
    r = await prep(mti, klass || '', phone || '');
    ok(r.row.payerName === want && norm(r.row, sid), `${n}: «${mti}» — ${sid} ga (${via(r.row)})`);
  }
  r = await prep(CUR_U, '7B IQ-0050', '+998 90 123 45 67');
  ok(r.row.matched === true && r.row.studentId === 'IQ-0050' && r.row.raw.via === 'code', `Q9 «faqat kod» + sinfda egasining o'z ID'si va telefon — egasiga, via=code (${via(r.row)})`);
  r = await prep('IQ-0050 ' + CUR_U, '7B');
  ok(r.row.matched === true && r.row.studentId === 'IQ-0050' && r.row.raw.via === 'code', `Q10 «ID + kod» + sinf — egasiga, via=code (${via(r.row)})`);
  state.__pgrstIn = true;   // qo'shtirnoqli bo'lak «in» so'roviga bormaydi — to'lov baribir biriktiriladi
  r = await prep('IQ-0050 ' + CUR_U + ' "Sinov Ota"');
  ok(r.row.matched === true && r.row.studentId === 'IQ-0050' && r.row.raw.via === 'code', `Q11 qo'shtirnoqli matn («"Sinov Ota"») — so'rovga faqat toza nomzodlar, egasiga (${via(r.row)})`);
  r = await prep('"Sinov" 5E6F 7A8B 9C0D');
  ok(r.row.payerName === '"Sinov" [kod]' && norm(r.row, 'IQ-0050'), `Q11b ... kod egasi qoidasi ham (${via(r.row)})`);
  state.__pgrstIn = false;
  // o'quvchilarni o'qib bo'lmasa yoki nomzodlar juda ko'p (so'rov chegarasi) — kod bo'yicha biriktirilmaydi (fail-closed), yashirish ishlaydi
  state.__downList = new Set(['students']);
  r = await prep('5E6F 7A8B 9C0D');
  ok(r.row.payerName === '[kod]' && refused(r.row), `O21 o'quvchilar ro'yxati o'qilmadi — kod egasi bo'yicha biriktirilmadi, yashirildi (${via(r.row)})`);
  r = await prep(CUR_U);
  ok(r.row.payerName === '[kod]' && refused(r.row), `O21b ... «faqat kod» qoidasi ham — biriktirilmadi (${via(r.row)})`);
  state.__downList = null;
  r = await prep('5E6F 7A8B 9C0D');
  ok(r.row.payerName === '[kod]' && norm(r.row, 'IQ-0050'), `O21c ... ro'yxat o'qilsa — o'sha matn kod egasiga (${via(r.row)})`);
  const words = k => Array.from({ length: k }, (_, i) => 'Q' + 'ghjkmnpqrs'[i % 10] + 'ghjkmnpqrs'[Math.floor(i / 10)] + 'x').join(' ');
  r = await prep(words(70) + ' / 5E6F 7A8B 9C0D');   // 140 nomzod > 120
  ok(r.row.payerName.endsWith(' / [kod]') && refused(r.row), `O22 nomzodlar juda ko'p (> 120) — kod egasi bo'yicha biriktirilmadi (${r.row.studentId || '-'}, ${r.row.raw.via})`);
  r = await prep(words(50) + ' / 5E6F 7A8B 9C0D');   // 100 nomzod
  ok(r.row.payerName.endsWith(' / [kod]') && norm(r.row, 'IQ-0050'), `O22b ... chegaradan kam bo'lsa — kod egasiga (${r.row.studentId}, ${r.row.raw.via})`);
  // 3-raund (C5): ajratgich — 1–2 ta [bo'sh joy, tab . , - _ /] yoki 3 tagacha bo'sh joy belgisi (yangi qator): yashiriladi va egasiga
  for(const [n, mti, want, klass, wantK] of [
    ['G6 ikki bo\'sh joy', '3FA9  C21B  7D0E', '[kod]'], ['G7 «_»', '3FA9_C21B_7D0E', '[kod]'], ['G8 «/»', '3FA9/C21B/7D0E', '[kod]'],
    ['G9 «, »', 'Kod: 3FA9, C21B, 7D0E', 'Kod: [kod]'], ['G10 qatorma-qator', 'Kod:\n3FA9\nC21B\n7D0E', 'Kod:\n[kod]'],
    ['G11 ID + «, » + «/»; sinf maydonida «_»', 'IQ-0042, 3FA9/C21B/7D0E', 'IQ-0042, [kod]', '5A_3FA9_C21B_7D0E', '[kod]']]){
    r = await prep(mti, klass || '');
    ok(r.row.payerName === want && (!klass || r.row.payerClass === wantK) && norm(r.row, 'IQ-0042'), `${n}: ${JSON.stringify(mti)} -> ${JSON.stringify(r.row.payerName)}${klass ? ', ' + JSON.stringify(r.row.payerClass) : ''} (${r.row.studentId}, ${r.row.raw && r.row.raw.via})`);
  }
  // SQL app.payer_mask bilan AYNAN bir xil natija (migration/test-payer-codes.sql M19 / M23 — o'sha satrlar va kutilgan natijalar)
  const P1 = [['IQ-0042 3FA9 C21B 7D0E', 'IQ-0042 [kod]'], ['3FA9-C21B-7D0E', '[kod]'], ['IQ-0042 3FA9C2 1B7D0E', 'IQ-0042 [kod]'], ['5A 3FA9C21B 7D0E', '[kod]'],
    ['Sinov  3FA9 C21B 7D0E.', 'Sinov  [kod].'], ['Кod: 3FА9 С21В 7DОЕ', 'Кod: [kod]'], ['AB3FA9 C21B 7D0E12', '[kod]'], ['3FA9 C21B 7D0F', '3FA9 C21B 7D0F'],
    ['+998 90 123 45 67, 16.11.2026, 5A, IQ-0042 5A 998901234567', '+998 90 123 45 67, 16.11.2026, 5A, IQ-0042 5A 998901234567'],
    // C3: kodga yondosh hex bo'laklar (yaqin nusxa ham) — bitta «[kod]»; IQ-ID va so'z qoladi
    ['3FA9C21B7D0E 3FA9C21B7D0F', '[kod]'], ['3FA9C21B7D0F 3FA9C21B7D0E', '[kod]'], ['Sinov Ali 3FA9C21B7D0E', 'Sinov Ali [kod]'],
    ['Kod 3FA9C21B7D0E-3FA9C21B7D0F', 'Kod [kod]'], ['3FA9 C21B 7D0E 3FA9 C21B 7D0', '[kod]'], ['3FA9C21B7D0E3FA9C21B7D0F', '[kod]'],
    ['Kod3FA9C21B7D0E3FA9C21B7D0F', 'Kod[kod]'], ['3FA9C21B7D0E va 3FA9C21B7D0F', '[kod] va 3FA9C21B7D0F'], ['IQ-00423FA9C21B7D0E', 'IQ-0042[kod]'],
    ['IQ00423FA9C21B7D0E', 'IQ0042[kod]'], ['IQ 0042 3FA9C21B7D0E 1234', 'IQ 0042 [kod]'], ['iq_0042_3fa9_c21b_7d0e_7d0f', 'iq_0042_[kod]'],
    ['3FA9C21B7D0E__2026-09', '[kod]'], ['Sinov 0A1B2C3D4E5F 3FA9C21B7D0E Ota', 'Sinov [kod] Ota']];
  const P2 = [['3FA9  C21B  7D0E', '[kod]'], ['3FA9_C21B_7D0E', '[kod]'], ['3FA9/C21B/7D0E', '[kod]'], ['3FA9, C21B, 7D0E', '[kod]'],
    ['3FA9\nC21B\n7D0E', '[kod]'], ['3FA9\tC21B\t7D0E', '[kod]'], ['3FA9\r\nC21B\r\n7D0E', '[kod]'], ['3FA9 \n C21B \n 7D0E', '[kod]'],
    ['3FA9\u00a0C21B\u00a07D0E', '[kod]'], ['3FA9,,C21B._7D0E', '[kod]'], ['IQ-0042, 3FA9/C21B/7D0E', 'IQ-0042, [kod]'],
    // qatorni uzadi: 3 ta aralash belgi, boshqa belgi, 4+ bo'sh joy
    ['3FA9 | C21B | 7D0E', '3FA9 | C21B | 7D0E'], ['3FA9    C21B    7D0E', '3FA9    C21B    7D0E'], ['3FA9 - C21B - 7D0E', '3FA9 - C21B - 7D0E'],
    ['3FA9 / C21B / 7D0E', '3FA9 / C21B / 7D0E'], ['3FA9:C21B:7D0E', '3FA9:C21B:7D0E'], ['3FA9–C21B—7D0E', '3FA9–C21B—7D0E'],
    ['3FA9...C21B...7D0E', '3FA9...C21B...7D0E'], ['3FA9\n\n\n\nC21B\n7D0E', '3FA9\n\n\n\nC21B\n7D0E'], ['IQ-0042 _ 3FA9 C21B 7D0E __', 'IQ-0042 _ [kod] __']];
  // 5-raund: IQ-ID raqami (SID_IQ taniydigan yozilish) «[kod]» ga qo'shilmaydi; harfga yopishgan «…iq», harfdan keyingi «IQ», son belgisi,
  //   3 tadan ortiq belgi — ID emas; kodning o'zi va yaqin nusxasi baribir yashiriladi (SQL M26 — o'sha satrlar)
  const NB = String.fromCharCode(0xA0), IS = String.fromCharCode(0x3000), EM = String.fromCodePoint(0x1F600);
  const P3 = [['IQ+0043 3FA9 C21B 7D0E', 'IQ+0043 [kod]'], ['ИҚ-0043 3FA9C21B7D0E', 'ИҚ-0043 [kod]'], ['IQ#0043 3FA9 C21B 7D0E', 'IQ#0043 [kod]'],
    ['IQ\'0043 3FA9 C21B 7D0E', 'IQ\'0043 [kod]'], ['ІQ-0043 3FA9 C21B 7D0E', 'ІQ-0043 [kod]'], ['IQ = 0043 3FA9 C21B 7D0E', 'IQ = 0043 [kod]'],
    ['ик 0043 3FA9 C21B 7D0E', 'ик 0043 [kod]'], ['IҚ_0043 3FA9 C21B 7D0E', 'IҚ_0043 [kod]'], ['5AIQ-0043 3FA9 C21B 7D0E', '5AIQ-0043 [kod]'],
    ['IQ+00433FA9C21B7D0E', 'IQ+0043[kod]'], ['ИК 00433FA9C21B7D0E', 'ИК 0043[kod]'], ['IQ+0042 3FA9C21B7D0E', 'IQ+0042 [kod]'],
    ['IQ–0043 3FA9C21B7D0E', 'IQ–0043 [kod]'], ['9IQ 0043 3FA9C21B7D0E', '9IQ 0043 [kod]'], ['IQ_ 0043 3FA9C21B7D0E', 'IQ_ 0043 [kod]'],
    ['IQ' + NB + NB + NB + '#' + NB + '0043 3FA9C21B7D0E', 'IQ' + NB + NB + NB + '#' + NB + '0043 [kod]'],
    ['IQ' + IS + ':' + IS + '0043 3FA9C21B7D0E', 'IQ' + IS + ':' + IS + '0043 [kod]'], ['IQ ' + EM + ' 0043 3FA9C21B7D0E', 'IQ ' + EM + ' 0043 [kod]'],
    ['IQ   #   #   #   0043 3FA9C21B7D0E', 'IQ   #   #   #   0043 [kod]'],
    ['Sinov Ota Sinov Ota Sinov Ota Sinov Ota Sinov Ota IQ+0043 3FA9C21B7D0E', 'Sinov Ota Sinov Ota Sinov Ota Sinov Ota Sinov Ota IQ+0043 [kod]'],
    ['Sodiq 0043 3FA9 C21B 7D0E', 'Sodiq [kod]'], ['Rafiq+0043 3FA9 C21B 7D0E', 'Rafiq+[kod]'], ['ўIQ+0043 3FA9 C21B 7D0E', 'ўIQ+[kod]'],
    ['αIQ+0043 3FA9 C21B 7D0E', 'αIQ+[kod]'], ['xIQ   #   #   #   0043 3FA9C21B7D0E', 'xIQ   #   #   #   [kod]'], ['IQ ½ 0043 3FA9 C21B 7D0E', 'IQ ½ [kod]'],
    ['IQ - - - - 0043 3FA9 C21B 7D0E', 'IQ - - - - [kod]'], ['IQ+123456789012', 'IQ+[kod]'], ['IQ+3FA9C21B7D0F 3FA9C21B7D0E', 'IQ+[kod]'],
    ['3FA9C21B7D0E IQ+0043', '[kod] IQ+0043']];
  for(const [name, list] of [['P1 yashirish (C3: yondosh hex bo\'laklar, yaqin nusxa; SQL M19)', P1], ['P2 ajratgichlar (C5; SQL M23)', P2],
                              ['P3 IQ-ID raqami (5-raund; SQL M26)', P3]]){
    const bad = [];
    for(const [s, w] of list){ const m = await maskPayer(s); if(m !== w) bad.push(JSON.stringify(s) + ' -> ' + JSON.stringify(m)); }
    ok(!bad.length, `${name}: ${list.length} ta satr${bad.length ? ' — ' + bad.join('; ') : ''}`);
  }

  // ---------- Click: aniq rejim ----------
  r = await prep('IQ-0042__2026-09', '', '', 1000);
  ok(r.row.merchant_trans_id === 'IQ-0042__2026-09' && r.row.raw && r.row.raw.mode === 'precise' && r.row.invoiceId === 'IQ-0042__2026-09', 'M11 aniq rejim: invoice ID o\'zgarmay saqlanadi');
  const m11 = r;
  r = await prep(CUR + '__2026-09');
  ok(r.row.merchant_trans_id === '[kod]' && r.row.raw.mode === 'freeform', `M12 «KOD__oy» (invoice yo'q -> erkin) — kod yashirilgan, «__2026-09» (yondosh raqamli bo'laklar) ham («${r.row.merchant_trans_id}»)`);
  // 5-raund: faktura ID («IQ-0050__2026-08» — shu oy fakturasi yo'q) bo'yicha biriktirish — faqat telefon / ism qoidasi 'code_conflict'
  //   bermagan, matndagi kodlar faqat shu o'quvchiniki va matnda boshqa o'quvchi tilga olinmagan bo'lsa. IQ-0042 (fbX9kQ2, 5A) va IQ-0050
  //   (7A) — bitta telefonda.
  state.student_private['fbX9kQ2'] = { id: 'fbX9kQ2', parentPhone: '+998000000055' };
  state.student_private['IQ-0050'] = { id: 'IQ-0050', parentPhone: '+998000000055' };
  for(const [n, mti, klass, phone, sid, want] of [
    ['I1 faqat faktura ID', 'IQ-0050__2026-08', '', '', 'IQ-0050', 'IQ-0050__2026-08'],
    ['I2 faktura ID + umumiy telefon (aka-uka — telefon qoidasi aniqlay olmaydi)', 'IQ-0050__2026-08', '', '998000000055', 'IQ-0050', 'IQ-0050__2026-08'],
    ['I3 faktura ID + egasining o\'z kodi', 'IQ-0050__2026-08 ' + CUR_U, '', '', 'IQ-0050', 'IQ-0050__[kod]'],
    ['I4 faktura ID + BOSHQA o\'quvchining (IQ-0042) kodi', 'IQ-0050__2026-08 ' + CUR, '', '', '', 'IQ-0050__[kod]'],
    ['I5 ... + umumiy telefon', 'IQ-0050__2026-08 ' + CUR, '', '998000000055', '', 'IQ-0050__[kod]'],
    ['I6 ... + sinf 7A va umumiy telefon', 'IQ-0050__2026-08 ' + CUR, '7A', '998000000055', '', 'IQ-0050__[kod]'],
    ['I7 ... + sinf 5A va umumiy telefon (telefon qoidasi: code_conflict)', 'IQ-0050__2026-08 ' + CUR, '5A', '998000000055', '', 'IQ-0050__[kod]'],
    ['I8 «IQ-0050__KOD» (oysiz, boshqa o\'quvchining kodi)', 'IQ-0050__' + CUR, '', '', '', 'IQ-0050__[kod]'],
    ['I9 faktura ID + boshqa o\'quvchining ID\'si', 'IQ-0050__2026-08 IQ-0043', '', '', '', 'IQ-0050__2026-08 IQ-0043'],
    ['I10 faktura ID + sinf 5A va umumiy telefon: telefon qoidasi IQ-0042 ni, faktura IQ-0050 ni ko\'rsatadi', 'IQ-0050__2026-08', '5A', '998000000055', '', 'IQ-0050__2026-08'],
    ['I11 faktura ID + egasining ESKI kodi', 'IQ-0050__2026-08 ' + OLD_U, '', '', 'IQ-0050', 'IQ-0050__[kod]']]){
    r = await prep(mti, klass, phone);
    const good = sid ? (r.row.matched === true && r.row.studentId === sid && r.row.raw.via === 'invoice-id') : (r.row.matched === false && r.row.studentId === '');
    ok(good && r.row.payerName === want && !has(r.row, CUR) && !has(r.row, CUR_U), `${n}: «${mti}»${klass ? ' / «' + klass + '»' : ''}${phone ? ' / tel' : ''} — ${sid || 'biriktirilmadi'} (${via(r.row)})`);
  }
  // Uzum — o'zgarmagan: «{sid}__{oy}» faqat aniq faktura (yo'q bo'lsa — rad), kod bilan ham
  for(const [acc, okW] of [['IQ-0050__2026-09', true], ['IQ-0050__2026-08', false], ['IQ-0050__2026-08 ' + CUR, false], ['IQ-0050__2026-08 ' + CUR_U, false]]){
    const u0 = await handleUzum('check', { serviceId: SID, params: { account: acc } });
    ok((u0.status === 'OK') === okW, `I12 Uzum check «${acc.replace(CUR, 'A kodi').replace(CUR_U, 'B kodi')}» — ${okW ? 'OK' : 'rad'} (${u0.status})`);
  }
  // telefon (+ ism / sinf) qoidasi: matnda BOSHQA o'quvchining ID'si (har qanday tanilgan yozilishi) bo'lsa — 'code_conflict' (qo'lda)
  for(const [n, mti, klass, sid] of [
    ['Y1 B ning ID\'si + A kodi, sinf 5A (A)', 'IQ-0050 ' + CUR, '5A', ''], ['Y2 «IQ_0050», sinf 5A', 'IQ_0050', '5A', ''],
    ['Y3 A ismi + B ning ID\'si «IQ+0050»', 'Sardor IQ+0050', '', ''], ['Y4 A ismi, sinf maydonida B ning ID\'si', 'Sardor', '5A IQ-0050', ''],
    ['Y5 A ismi (avvalgidek)', 'Sardor', '', 'IQ-0042'], ['Y6 A ismi + o\'z ID\'si', 'IQ-0042 Sardor', '', 'IQ-0042'],
    ['Y7 B ismi + o\'z ID\'si kiril harflarda', 'ИҚ-0050 Uzum', '', 'IQ-0050'], ['Y8 A ismi + o\'z kodi', 'Sardor ' + CUR, '', 'IQ-0042'],
    ['Y9 A ismi + o\'z ID\'si boshidagi nollarsiz «IQ-42»', 'Sardor IQ-42', '', 'IQ-0042'], ['Y10 «IQ-50» — B ning ID\'si (nollarsiz)', 'Sardor IQ-50', '', '']]){
    r = await prep(mti, klass, '998000000055');
    const good = sid ? (r.row.matched === true && r.row.studentId === sid && r.row.raw.via === 'phone')
                     : (r.row.matched === false && r.row.studentId === '' && r.row.raw.via === 'code_conflict');
    ok(good, `${n}: «${mti}»${klass ? ' / «' + klass + '»' : ''} + umumiy telefon — ${sid || 'biriktirilmadi (code_conflict)'} (${via(r.row)})`);
  }
  delete state.student_private['fbX9kQ2']; delete state.student_private['IQ-0050'];

  // ---------- Click complete: matn qayta yozilmaydi, javob asl ----------
  const cp = Object.assign({}, m1.p, { action: '1', merchant_prepare_id: m1.res.merchant_prepare_id, error: '0' }); cp.sign_string = sign(cp, true);
  const cr = await handleComplete(cp);
  const crow = state.payments['click_' + m1.p.click_trans_id];
  ok(cr.error === 0 && cr.merchant_trans_id === 'IQ-0042 3fa9c21b7d0e', 'M13 complete javobi asl merchant_trans_id');
  ok(crow.status === 'applied' && crow.merchant_trans_id === 'IQ-0042 [kod]' && !has(crow, CUR), `M13 complete: qo'llandi (${crow.status}), saqlangan matn yashirinligicha`);
  const cp2 = Object.assign({}, m11.p, { action: '1', merchant_prepare_id: m11.res.merchant_prepare_id, error: '0' }); cp2.sign_string = sign(cp2, true);
  const cr2 = await handleComplete(cp2);
  const st2 = state.payments['click_' + m11.p.click_trans_id];
  ok(cr2.error === 0 && ['paid', 'applied'].includes(st2.status) && st2.merchant_trans_id === 'IQ-0042__2026-09', `M13b aniq rejim complete ishlaydi (${st2.status})`);

  // ---------- Uzum ----------
  const uz = (op, body) => handleUzum(op, Object.assign({ serviceId: SID }, body));
  let u = await uz('check', { params: { account: OLD_U.toLowerCase() }, amount: 30000000 });
  ok(u.status === 'OK' && u.data && u.data.account.invoice === 'IQ-0050__2026-09', `U1 check: ESKI kod -> IQ-0050 fakturasi (${u.status})`);
  u = await uz('create', { transId: 'T1', params: { account: 'IQ-0050 ' + CUR_U }, amount: 30000000, timestamp: 1763251200000 });
  const urow = state.payments['uzum_T1'] || {};
  ok(u.status === 'CREATED' && u.transId === 'T1' && u.amount === 30000000, 'U2 create javobi Uzum qiymatlari bilan');
  ok(urow.invoiceId === 'IQ-0050__2026-09' && urow.raw && urow.raw.params && urow.raw.params.account === 'IQ-0050 [kod]', `U2 raw.params.account yashirilgan («${urow.raw && urow.raw.params && urow.raw.params.account}»)`);
  ok(urow.raw.transId === 'T1' && urow.raw.amount === 30000000 && urow.raw.timestamp === 1763251200000 && urow.raw.serviceId === SID, 'U2 raw\'ning qolgan maydonlari (son ham) o\'zgarmagan');
  ok(urow.raw.via === undefined, `U2 aniq «ID KOD» — raw.via yo'q (kod egasi qoidasi ishlamadi) (${urow.raw.via})`);
  u = await uz('confirm', { transId: 'T1' });
  const urow2 = state.payments['uzum_T1'];
  ok(u.status === 'CONFIRMED' && urow2.status === 'confirmed' && urow2.raw.appliedTo === 'invoice' && urow2.raw.params.account === 'IQ-0050 [kod]', 'U3 confirm: raw yashirinligicha (appliedTo qo\'shildi)');
  u = await uz('reverse', { transId: 'T1' });
  ok(u.status === 'REVERSED' && state.payments['uzum_T1'].status === 'reversed' && !has(state.payments['uzum_T1'], CUR_U), 'U4 reverse: kod yo\'q');
  u = await uz('create', { transId: 'T2', params: { account: OLD_U.toLowerCase() }, amount: 30000000 });
  ok(u.status === 'CREATED' && (state.payments['uzum_T2'] || {}).invoiceId && state.payments['uzum_T2'].raw.params.account === '[kod]', `U5 create: ESKI kod -> faktura topildi, raw'da «[kod]»`);
  // eski server (deploy oralig'ida) yashirmay yozgan qator: confirm uni qayta yozganda kod yashiriladi
  state.payments['uzum_T3'] = { id: 'uzum_T3', provider: 'uzum', transId: 'T3', invoiceId: 'IQ-0050__2026-10', studentId: 'IQ-0050', amount: 300000,
    status: 'created', raw: { serviceId: SID, transId: 'T3', params: { account: CUR_U }, amount: 30000000 } };
  u = await uz('confirm', { transId: 'T3' });
  ok(u.status === 'CONFIRMED' && state.payments['uzum_T3'].raw.params.account === '[kod]' && !has(state.payments['uzum_T3'], CUR_U), 'U6 eski server yozgan raw confirm\'da yashirildi');
  u = await uz('check', { params: { account: '5e6f 7a8b 9c0d' } });
  ok(u.status === 'OK' && u.data && u.data.account.invoice === 'IQ-0050__2026-09', `U7 check: guruhlab yozilgan kod -> kod egasining fakturasi (${u.status} ${u.data && u.data.account.invoice})`);
  u = await uz('create', { transId: 'T6', params: { account: '5e6f 7a8b 9c0d' }, amount: 30000000 });
  const urow6 = state.payments['uzum_T6'] || {};
  ok(u.status === 'CREATED' && urow6.invoiceId === 'IQ-0050__2026-09' && urow6.raw && urow6.raw.params.account === '[kod]' && urow6.raw.via === 'code_norm',
    `U7b create: guruhlab yozilgan kod -> faktura, raw'da «[kod]» va via = 'code_norm' (kod egasi qoidasi — Direktor ko'radi) (${u.status}, ${urow6.raw && urow6.raw.via})`);
  u = await uz('create', { transId: 'T4', params: { account: 'IQ-0050 5Е6F 7А8В 9С0D' }, amount: 30000000 });   // kiril Е, А, В, С
  ok(u.status === 'CREATED' && (state.payments['uzum_T4'] || {}).invoiceId === 'IQ-0050__2026-09' && state.payments['uzum_T4'].raw.params.account === 'IQ-0050 [kod]',
    `U8 create: kiril harfli guruh -> faktura topildi, raw'da «IQ-0050 [kod]» (${u.status})`);
  ok((state.payments['uzum_T4'] || {}).raw && state.payments['uzum_T4'].raw.via === 'code_norm', `U8 ... kod egasi bo'yicha topilgani raw.via = 'code_norm' bilan saqlandi (${(state.payments['uzum_T4'] || {}).raw && state.payments['uzum_T4'].raw.via})`);
  u = await uz('confirm', { transId: 'T4' });
  ok(u.status === 'CONFIRMED' && state.payments['uzum_T4'].raw.via === 'code_norm' && !!state.payments['uzum_T4'].raw.appliedTo, `U8b confirm: raw.via saqlandi, appliedTo qo'shildi (${state.payments['uzum_T4'].raw.via}, ${state.payments['uzum_T4'].raw.appliedTo})`);
  u = await uz('check', { params: { account: 'IQ-0043 5E6F 7A8B 9C0D' } });
  ok(u.status !== 'OK', `U9 check: matnda boshqa o'quvchi ID'si — kod egasining fakturasi QAYTMAYDI (${u.status})`);
  for(const acc of ['IQ-0043-5E6F7A8B9C0D', 'IQ-0043_5E6F7A8B9C0D', '(IQ-0043)5E6F7A8B9C0D', 'IQ00435E6F7A8B9C0D']){
    u = await uz('check', { params: { account: acc } });
    ok(u.status !== 'OK', `U10 check «${acc}»: boshqa o'quvchi ID'si kodga yopishgan — faktura QAYTMAYDI (${u.status})`);
  }
  u = await uz('create', { transId: 'T5', params: { account: 'IQ-0043-5E6F7A8B9C0D' }, amount: 30000000 });
  ok(u.status !== 'CREATED' && !state.payments['uzum_T5'], `U10b create «IQ-0043-KOD»: yaratilmadi (${u.status})`);
  state.invoices['IQ-0050__2026-11'] = { id: 'IQ-0050__2026-11', amount: 300000, status: 'unpaid', studentId: 'IQ-0050', month: '2026-11' };   // oldingilari U3/U6/U8b da to'landi
  u = await uz('check', { params: { account: '5E6F_7A8B_9C0D' } });
  ok(u.status === 'OK' && u.data && u.data.account.invoice.startsWith('IQ-0050__'), `U11 check: «_» bilan guruh -> kod egasining fakturasi (${u.status} ${u.data && u.data.account.invoice})`);
  u = await uz('check', { params: { account: 'IQ-0050 ' + CUR_U + ' IQ-0043' } });
  ok(u.status !== 'OK', `U12 check «ID KOD» + boshqa o'quvchi ID'si (aniq kod qoidasi) — faktura QAYTMAYDI (${u.status})`);
  u = await uz('check', { params: { account: 'IQ-0050 ' + CUR_U } });
  ok(u.status === 'OK' && u.data.account.invoice.startsWith('IQ-0050__'), `U12b check «ID KOD» — o'z fakturasi (${u.status})`);
  // ikki o'quvchining kodi (aniq «ID KOD» qoidasi ham) — faktura topilmaydi; IQ-0042 ning to'lanmagan fakturasi bor (U13c)
  state.invoices['IQ-0042__2026-12'] = { id: 'IQ-0042__2026-12', amount: 500000, status: 'unpaid', studentId: 'IQ-0042', month: '2026-12' };
  u = await uz('check', { params: { account: 'IQ-0042 ' + CUR + ' ' + CUR_U } });
  ok(u.status !== 'OK', `U13 check «ID + A kodi + B kodi» — faktura QAYTMAYDI (${u.status})`);
  u = await uz('create', { transId: 'T7', params: { account: 'IQ-0042 ' + CUR + ' ' + CUR_U }, amount: 50000000 });
  ok(u.status !== 'CREATED' && !state.payments['uzum_T7'], `U13b create «ID + A kodi + B kodi»: yaratilmadi (${u.status})`);
  u = await uz('check', { params: { account: 'IQ-0042 ' + CUR } });
  ok(u.status === 'OK' && u.data.account.invoice.startsWith('IQ-0042__'), `U13c check faqat A kodi bilan — A fakturasi (${u.status})`);

  // ---------- maskPayer: chuqur, son qiymat, raqamli kod ----------
  const mp = await maskPayer({ a: [DIGITS, 5, { b: Number(DIGITS) }], c: 'IQ-0060', d: null, e: true });
  ok(mp.a[0] === '[kod]' && mp.a[1] === 5 && mp.a[2].b === '[kod]' && mp.c === 'IQ-0060' && mp.d === null && mp.e === true, `K1 ichma-ich obyekt: satr va son qiymatdagi (raqamli) kod yashirilgan (${JSON.stringify(mp)})`);
  r = await prep('Sinov Ota 3FA9C2', '1B7D0E 7A');
  ok(r.row.payerName === 'Sinov Ota 3FA9C2' && r.row.payerClass === '1B7D0E 7A', `K2 ikki maydonga bo'lingan kod — maydon chegarasidan o'tmaydi, har maydon alohida (SQL M24 bilan bir xil) («${r.row.payerName}», «${r.row.payerClass}»)`);

  // ---------- FAIL-CLOSED ----------
  state.__down = new Set(['student_codes', 'student_code_prev']);
  r = await prep('IQ-0042 ' + CUR + ' tel 998000000017', '7A', '998000000017');
  ok(r.res.error === 0, 'F1 baza ishlamasa ham to\'lov qabul qilinadi (biriktirilmagan)');
  ok(r.row.payerName === 'IQ-0042 [kod] tel 998000000017' && r.row.payerPhone === '998000000017' && r.row.payerClass === '7A', `F1 shakl qoidasi: kod yashirildi, telefon / ID / sinf tegilmadi («${r.row.payerName}»)`);
  r = await prep('Sinov ABCDEF123456 Ota IQ00429C0D1E2F3A4B');
  ok(r.row.payerName === 'Sinov [kod] Ota [kod]', `F2 kodga o'xshash har bo'lak (bo'lak ichida ham) yashirildi («${r.row.payerName}»)`);
  const fm = await maskPayer({ params: { account: 'IQ-0050 ' + CUR_U }, transId: 'a1b2c3d4-0000-4000-8000-1234567890ab', amount: 30000000 });
  ok(fm.params.account === 'IQ-0050 [kod]' && fm.amount === 30000000, 'F3 Uzum raw: account yashirildi, summa tegilmadi');
  r = await prep('IQ-0042 3FA9 C21B 7D0E', '5A 3FA9C21B 7D0E');
  ok(r.row.payerName === 'IQ-0042 [kod]' && r.row.payerClass === '[kod]', `F6 shakl qoidasi guruhlab yozilgan kodni ham yashiradi (yondosh «5A» bilan), ID tegilmadi («${r.row.payerName}», «${r.row.payerClass}»)`);
  r = await prep('IQ-0042-3FA9-C21B-7D0E');
  ok(r.row.payerName === 'IQ-0042-[kod]', `F6b ... hammasi «-» bilan ulangan bo'lsa ham ID qoladi («${r.row.payerName}»)`);
  r = await prep('Sinov  3FA9_C21B_7D0E', '5A, 3FA9/C21B/7D0E');
  ok(r.row.payerName === 'Sinov  [kod]' && r.row.payerClass === '[kod]', `F6c shakl qoidasi yangi ajratgichli guruhni ham yashiradi («${r.row.payerName}», «${r.row.payerClass}»)`);
  r = await prep('Kod:\n3FA9\nC21B\n7D0E', '3FA9, C21B, 7D0E');
  ok(r.row.payerName === 'Kod:\n[kod]' && r.row.payerClass === '[kod]', `F6d ... qatorma-qator va «, » bilan ham (${JSON.stringify(r.row.payerName)}, «${r.row.payerClass}»)`);
  r = await prep('Sinov Ota +998 90 123 45 67, 16.11.2026, 1 500 000, IQ-0042 5A 998901234567', '11B', '998901234567');
  ok(r.row.payerName === 'Sinov Ota +998 90 123 45 67, 16.11.2026, 1 500 000, IQ-0042 5A 998901234567' && r.row.payerClass === '11B' && r.row.payerPhone === '998901234567',
    `F7 shakl qoidasi telefon, sana, summa, sinf va ID'ga tegmaydi («${r.row.payerName}»)`);
  const f7b = ['+998 90 123 45 67', '998901234567', '2026-11-16', '16.11.2026', '1 500 000', '5A', '11B', 'IQ-0042',
               'Sinov Ota\n+998 90 123 45 67\n998901234567\n2026-11-16, 16.11.2026\n1 500 000 so\'m\n5A, 11B\nIQ-0042',
               // sinf + bo'sh joy bilan telefon / sana / summa (A–F harfi faqat boshidagi sinfdan) — guruh kod emas
               '5A 998 90 123 45 67', 'Sinov Ali 5A 998 90 123 45 67', '11B 2026-11-16 1 500 000', '9D 16.11.2026 15:30 1 500 000',
               '5В 998 90 123 45 67', '5A, 90 123 45 67 1 500 000',
               // 5-raund: «5-A» / «5 A» (1–2 raqam + bitta harf, kiril ham) va «A5» yozilishidagi sinf
               '5-A 998 90 123 45 67', '5 A 998 90 123 45 67', 'Sinov Ali 5-A 998 90 123 45 67', '11-B 2026-11-16 1 500 000',
               '9-D 16.11.2026 15:30 1 500 000', '5-В 998 90 123 45 67', 'IQ-0042 5-A 998 90 123 45 67', 'A5 998 90 123 45 67',
               '5-A, 998 90 123 45 67', '7 Д 998 90 123 45 67', '5 A 998 90 123 456 7', 'В11 2026-11-16 1 500 000'];
  const f7bad = [];
  for(const s of f7b){ const m = await maskPayer(s); if(m !== s) f7bad.push(JSON.stringify(s) + ' -> ' + JSON.stringify(m)); }
  ok(!f7bad.length, `F7b shakl qoidasi yangi ajratgichlar bilan ham telefon / sana / summa / sinf / ID'ga tegmaydi${f7bad.length ? ': ' + f7bad.join('; ') : ''}`);
  // ... sinf yozilishi kodni «himoya» qilmaydi: sinfdan keyin kodga o'xshash guruh — yashiriladi
  const f7c = [['5-A 3FA9 C21B 7D0E', '[kod]'], ['5 A 3FA9C21B7D0E', '[kod]'], ['A5 3FA9 C21B 7D0E', '[kod]'], ['Sinov 5-A, 3FA9/C21B/7D0E', 'Sinov [kod]'],
               ['5 A 998 90 3FA9 C21B 7D0E', '[kod]']];
  const f7cbad = [];
  for(const [s, w] of f7c){ const m = await maskPayer(s); if(m !== w) f7cbad.push(JSON.stringify(s) + ' -> ' + JSON.stringify(m)); }
  ok(!f7cbad.length, `F7c sinfdan keyingi kodga o'xshash guruh baribir yashiriladi${f7cbad.length ? ': ' + f7cbad.join('; ') : ''}`);
  // kodlarni o'qib bo'lmasa telefon (+ ism) qoidasi: kodga o'xshash tekshirilmagan bo'lak bo'lsa — biriktirmaydi; faqat telefon maydonidagi
  //   raqamli kalit (telefonning o'zi) va ism so'zlari — to'sqinlik qilmaydi
  state.student_private['IQ-0043'] = { id: 'IQ-0043', parentPhone: '+998000000043' };
  for(const [n, mti, phone, klass, sid] of [
    ['F8 ism + telefon (kodga o\'xshash bo\'lak yo\'q)', 'Sinov Boshqa', '998000000043', '', 'IQ-0043'],
    ['F8a ism + «+998 …» telefon, sinf', 'Sinov Boshqa', '+998 00 000 00 43', '6B', 'IQ-0043'],
    ['F8b ism + kod (egasiniki, lekin tekshirib bo\'lmaydi)', 'Sinov Boshqa 0A1B 2C3D 4E5F', '998000000043', '', ''],
    ['F8c matnda 12 raqam (eski faqat raqamli kod bo\'lishi mumkin)', 'Sinov Boshqa 123456789012', '998000000043', '', ''],
    ['F8d telefon maydonida harfli kodga o\'xshash bo\'lak', 'Sinov Boshqa', '0A1B2C3D4E5F 998000000043', '', ''],
    ['F8e telefon matnda ham yozilgan (12 raqam — matn maydonida)', 'Sinov Boshqa 998000000043', '998000000043', '', ''],
    ['F8f sinf maydonida kodga o\'xshash bo\'lak', 'Sinov Boshqa', '998000000043', '6B 0A1B2C3D4E5F', ''],
    ['F8g matnda boshqa o\'quvchining ID\'si', 'Sinov Boshqa IQ-0050', '998000000043', '', '']]){
    r = await prep(mti, klass, phone);
    const good = sid ? (r.row.matched === true && r.row.studentId === sid && r.row.raw.via === 'phone')
                     : (r.row.matched === false && r.row.studentId === '' && r.row.raw.via === 'code_conflict');
    ok(good, `${n}: «${mti}» / tel «${phone}»${klass ? ' / «' + klass + '»' : ''} — kodlarni o'qib bo'lmadi: ${sid || 'biriktirilmadi (code_conflict)'} (${via(r.row)})`);
  }
  delete state.student_private['IQ-0043'];
  // faktura ID qoidasi ham: kodga o'xshash tekshirilmagan bo'lak bo'lsa — yo'q; faqat telefon — to'sqinlik qilmaydi
  r = await prep('IQ-0050__2026-08', '', '998000000001');
  ok(r.row.matched === true && r.row.studentId === 'IQ-0050' && r.row.raw.via === 'invoice-id', `F9 «IQ-0050__2026-08» + telefon, kodlarni o'qib bo'lmadi — faktura ID bo'yicha IQ-0050 (${via(r.row)})`);
  r = await prep('IQ-0050__2026-08 ' + CUR_U);
  ok(r.row.matched === false && r.row.studentId === '' && r.row.payerName === 'IQ-0050__[kod]', `F9b ... matnda kod (tekshirib bo'lmaydi) — biriktirilmadi (${via(r.row)})`);
  state.__down = new Set(['student_code_prev']);   // faqat eski kodlar jadvali o'qilmaydi
  r = await prep('Sinov ' + CUR + ' va ' + DIGITS);
  ok(r.row.payerName === 'Sinov [kod] va [kod]', `F4 qisman xato: joriy kodlar jadvalida topilgan kod (faqat raqamli ham) yashirildi («${r.row.payerName}»)`);
  r = await prep('Sinov ABCDEF123456 tel 998000000017');
  ok(r.row.payerName === 'Sinov [kod] tel 998000000017', `F4b ... tekshirib bo'lmagan kod shaklli bo'lak — shakl qoidasi bilan, telefon tegilmadi («${r.row.payerName}»)`);
  r = await prep('3FA9 C21B 7D0E');
  ok(r.row.payerName === '[kod]' && r.row.matched === false && r.row.studentId === '', `F4c ... biror jadval o'qilmasa kod egasi bo'yicha biriktirilmaydi (${via(r.row)})`);
  state.__down = new Set(['student_codes']);       // faqat joriy kodlar jadvali o'qilmaydi
  r = await prep('Sinov ' + OLD + ' va ' + DIGITS);
  ok(r.row.payerName === 'Sinov [kod] va ' + DIGITS, `F4d eski kodlar jadvalida topilgan kod yashirildi; faqat raqamli joriy kod — shakl qoidasidan tashqarida (yangi kodlar har doim harfli) («${r.row.payerName}»)`);
  state.__down = null;
  const many = Array.from({ length: 70 }, (_, i) => 'SOZ' + String(100 + i) + 'X').join(' ') + ' ' + CUR;   // 140 kalit > 120
  r = await prep(many);
  ok(r.row.payerName.endsWith(' [kod]') && r.row.payerName.startsWith('SOZ100X SOZ101X'), 'F5 juda ko\'p kalit (so\'rov chegarasi) — shakl qoidasi bilan yashirildi');

  fs.unlinkSync(CFGFILE);
  console.log(fails ? `\n❌ ${fails} FAILED` : '\n✅ ALL PASS — to\'lovchi matnidagi kod yashiriladi, eski kod to\'lovda ishlaydi');
  process.exit(fails ? 1 : 0);
})().catch(e => { try { fs.unlinkSync(CFGFILE); } catch (_) {} console.error('ERR', e); process.exit(1); });
