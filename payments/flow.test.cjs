// To'lov oqimi (Click prepare -> complete) uchdan-uchgacha sinovi, Supabase
// backend (soxta, stateful) ustida. @supabase paketini Module._load bilan
// soxta mijozga almashtiramiz -> real paket/VPS kerak emas.
// Ishga tushirish:  node payments/flow.test.cjs
const fs = require('fs'), path = require('path'), crypto = require('crypto'), Module = require('module');

// ---- soxta, stateful Supabase mijozi (pul RPC'lari bilan — _fake-sb.cjs) ----
const { makeFake } = require('./_fake-sb.cjs');
const state = { invoices: {}, payments: {}, students: {}, student_credit: {}, applied_payments: {} };
// @supabase/supabase-js ni intercept qilamiz (index.cjs require'idan OLDIN)
const orig = Module._load;
Module._load = function (req) { if (req === '@supabase/supabase-js') return { createClient: () => makeFake(state) }; return orig.apply(this, arguments); };

// ---- vaqtinchalik config (payments/ ichida, backend=supabase) ----
const CFGFILE = path.join(__dirname, '_flow-config.json');
const SECRET = 'TESTSECRET123';
fs.writeFileSync(CFGFILE, JSON.stringify({ backend: 'supabase', supabaseUrl: 'http://x', serviceRoleKey: 'k', click: { serviceId: '111', secretKey: SECRET } }));
process.env.IQROR_CONFIG = '_flow-config.json';

const { handlePrepare, handleComplete, md5 } = require('./index.cjs');

let fails = 0; const ok = (c, m) => { console.log((c ? '✓ ' : '✗ FAIL ') + m); if (!c) fails++; };
function sign(p, isComplete) {
  const parts = [p.click_trans_id, p.service_id, SECRET, p.merchant_trans_id];
  if (isComplete) parts.push(p.merchant_prepare_id);
  parts.push(p.amount, p.action, p.sign_time);
  return md5(parts.join(''));
}

(async () => {
  // seed: o'quvchi + aniq (precise) invoice ID '{sid}__{oy}' — "Click" tugmasi shu ko'rinishda yuboradi.
  //   (Balans modeli: invoice ANIQ ID orqali topiladi; summa aynan mos kelishi shart emas.)
  const INV = 'S1__2026-08';
  state.students['S1'] = { id: 'S1', studentId: 'S1', name: 'Ali' };
  state.invoices[INV] = { id: INV, amount: 500000, status: 'unpaid', studentId: 'S1', month: '2026-08' };

  // 1) PREPARE (to'g'ri imzo)
  const p0 = { click_trans_id: 'CT9', service_id: '111', merchant_trans_id: INV, amount: '500000', action: '0', sign_time: '2026-01-01 10:00:00' };
  p0.sign_string = sign(p0, false);
  const r1 = await handlePrepare(p0);
  ok(r1.error === 0, 'PREPARE muvaffaqiyat (error=0)');
  ok(!!r1.merchant_prepare_id, 'prepare_id qaytdi');
  ok(state.payments['click_CT9'] && state.payments['click_CT9'].status === 'prepared', 'payments doc "prepared" yozildi');

  // 2) PREPARE yaroqsiz imzo -> rad
  const bad = Object.assign({}, p0, { sign_string: 'deadbeef' });
  const rBad = await handlePrepare(bad);
  ok(rBad.error === -1, 'yaroqsiz imzo -> error=-1 (SIGN FAILED)');

  // 3) COMPLETE (to'g'ri imzo) -> invoice paid (apply_to_invoice RPC orqali)
  const p1 = { click_trans_id: 'CT9', service_id: '111', merchant_trans_id: INV, merchant_prepare_id: r1.merchant_prepare_id, amount: '500000', action: '1', sign_time: '2026-01-01 10:05:00', error: '0' };
  p1.sign_string = sign(p1, true);
  const r2 = await handleComplete(p1);
  ok(r2.error === 0, 'COMPLETE muvaffaqiyat (error=0)');
  ok(state.invoices[INV].status === 'paid', 'INVOICE "paid" bo\'ldi ★ (apply_to_invoice)');
  ok(state.invoices[INV].provider === 'click' && !!state.invoices[INV].paidAt, 'provider=click + paidAt yozildi');
  ok(state.payments['click_CT9'].status === 'paid', 'payments doc "paid"');

  // 4) summa <= 0 -> rad (-2). (Balans modelida musbat summa HAR DOIM qabul qilinadi — qisman/avans;
  //    faqat <=0 rad etiladi. Ilgari "aynan mos emas" rad etilardi, endi yo'q.)
  const pz = { click_trans_id: 'CTZ', service_id: '111', merchant_trans_id: 'S2__2026-08', amount: '0', action: '0', sign_time: 't' };
  pz.sign_string = sign(pz, false);
  const rz = await handlePrepare(pz);
  ok(rz.error === -2, 'summa <=0 -> error=-2');

  // 5) BALANS modeli: ortiqcha to'lov -> invoice "paid" + ortig'i o'quvchi AVANSIga (student_credit).
  const INV5 = 'S5__2026-08';
  state.students['S5'] = { id: 'S5', studentId: 'S5', name: 'Vali' };
  state.invoices[INV5] = { id: INV5, amount: 300000, status: 'unpaid', studentId: 'S5', month: '2026-08' };
  const pp0 = { click_trans_id: 'CT5', service_id: '111', merchant_trans_id: INV5, amount: '500000', action: '0', sign_time: 't5' };
  pp0.sign_string = sign(pp0, false);
  const pr5 = await handlePrepare(pp0);
  const pp1 = { click_trans_id: 'CT5', service_id: '111', merchant_trans_id: INV5, merchant_prepare_id: pr5.merchant_prepare_id, amount: '500000', action: '1', sign_time: 't5b', error: '0' };
  pp1.sign_string = sign(pp1, true);
  await handleComplete(pp1);
  ok(state.invoices[INV5].status === 'paid', 'ortiqcha to\'lov -> invoice "paid"');
  ok(state.student_credit['S5'] && state.student_credit['S5'].credit === 200000, 'ortig\'i (200000) o\'quvchi avansiga yozildi ★');

  // 6) YO'QOLGAN STATUS YOZUVI (masalan deploy restart): COMPLETE'da pul qo'llandi (posbon bor), lekin payments
  //    'prepared' qolib ketdi. Click qayta urinadi -> «Allaqachon to'langan» (-4) EMAS, MUVAFFAQIYAT bo'lishi
  //    shart (aks holda Click to'lovni bekor qilib pulni qaytaradi, faktura esa to'langan bo'lib qoladi).
  const INV6 = 'S6__2026-08';
  state.students['S6'] = { id: 'S6', studentId: 'S6', name: 'Gani' };
  state.invoices[INV6] = { id: INV6, amount: 400000, status: 'unpaid', studentId: 'S6', month: '2026-08' };
  const q0 = { click_trans_id: 'CT6', service_id: '111', merchant_trans_id: INV6, amount: '400000', action: '0', sign_time: 't6' };
  q0.sign_string = sign(q0, false);
  const qr = await handlePrepare(q0);
  const q1 = { click_trans_id: 'CT6', service_id: '111', merchant_trans_id: INV6, merchant_prepare_id: qr.merchant_prepare_id, amount: '400000', action: '1', sign_time: 't6b', error: '0' };
  q1.sign_string = sign(q1, true);
  await handleComplete(q1);
  state.payments['click_CT6'].status = 'prepared';           // status yozuvi yo'qolgan holatni taqlid qilamiz
  const q2 = await handleComplete(q1);                        // Click retry
  ok(q2.error === 0, 'retry (pul allaqachon qo\'llangan) -> error=0, «allaqachon to\'langan» EMAS ★');
  ok(state.payments['click_CT6'].status === 'paid', 'retry holatni yakunladi (paid)');
  ok(Number(state.invoices[INV6].paidAmount) === 400000, 'pul IKKI marta qo\'llanmadi');

  // 7) Bekor qilingan faktura (prepare'dan keyin) -> pul o'quvchi balansiga; status yozuvi PGRST204 bermasin
  //    (avval `note` ustuni yo'q bo'lgani uchun BUTUN yozuv rad etilib 500 qaytardi).
  const INV7 = 'S7__2026-08';
  state.students['S7'] = { id: 'S7', studentId: 'S7', name: 'Soli' };
  state.invoices[INV7] = { id: INV7, amount: 300000, status: 'unpaid', studentId: 'S7', month: '2026-08' };
  const w0 = { click_trans_id: 'CT7', service_id: '111', merchant_trans_id: INV7, amount: '300000', action: '0', sign_time: 't7' };
  w0.sign_string = sign(w0, false);
  const wr = await handlePrepare(w0);
  state.invoices[INV7].status = 'canceled';                   // admin «Bekor» bosdi
  const w1 = { click_trans_id: 'CT7', service_id: '111', merchant_trans_id: INV7, merchant_prepare_id: wr.merchant_prepare_id, amount: '300000', action: '1', sign_time: 't7b', error: '0' };
  w1.sign_string = sign(w1, true);
  const w2 = await handleComplete(w1);
  ok(w2.error === 0 && state.payments['click_CT7'].status === 'applied', 'bekor faktura -> balansga qo\'llandi, status «applied» (PGRST204 yo\'q)');
  ok(state.student_credit['S7'] && state.student_credit['S7'].credit === 300000, 'pul o\'quvchi avansida (yo\'qolmadi)');
  ok(state.payments['click_CT7'].raw && state.payments['click_CT7'].raw.note, 'izoh raw ichida saqlandi');

  fs.unlinkSync(CFGFILE);
  console.log('\n' + (fails ? ('❌ ' + fails + ' FAILED') : '✅ ALL PASS — to\'lov oqimi Supabase backend ustida ishlaydi'));
  process.exit(fails ? 1 : 0);
})().catch(e => { try { fs.unlinkSync(CFGFILE); } catch (_) {} console.error('ERR', e.stack || e.message); process.exit(2); });
