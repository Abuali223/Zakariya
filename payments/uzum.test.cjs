// Uzum Merchant API oqimi (check → create → confirm → status → reverse)
// uchdan-uchgacha sinovi, Supabase backend (soxta, stateful) ustida.
// @supabase paketini Module._load bilan soxta mijozga almashtiramiz.
// Ishga tushirish:  node payments/uzum.test.cjs
const fs = require('fs'), path = require('path'), Module = require('module');

// ---- soxta, stateful Supabase mijozi (pul RPC'lari bilan — _fake-sb.cjs) ----
const { makeFake } = require('./_fake-sb.cjs');
const state = { invoices: {}, payments: {}, students: {}, student_credit: {}, applied_payments: {} };
const orig = Module._load;
Module._load = function (req) { if (req === '@supabase/supabase-js') return { createClient: () => makeFake(state) }; return orig.apply(this, arguments); };

// ---- vaqtinchalik config (backend=supabase, uzum kalitlari) ----
const CFGFILE = path.join(__dirname, '_uzum-config.json');
const SID = 'SVC-1', LOGIN = 'iqror', PASS = 'p@ss';
fs.writeFileSync(CFGFILE, JSON.stringify({ backend: 'supabase', supabaseUrl: 'http://x', serviceRoleKey: 'k',
  uzum: { serviceId: SID, login: LOGIN, password: PASS, accountField: 'invoice', amountUnit: 'tiyin' } }));
process.env.IQROR_CONFIG = '_uzum-config.json';

const { handleUzum, uzumAuthOK } = require('./index.cjs');

let fails = 0; const ok = (c, m) => { console.log((c ? '✓ ' : '✗ FAIL ') + m); if (!c) fails++; };
const basic = (l, p) => ({ authorization: 'Basic ' + Buffer.from(l + ':' + p).toString('base64') });

(async () => {
  // seed: o'quvchi + aniq (precise) invoice ID '{sid}__{oy}' — Uzum "account" shu ko'rinishda keladi.
  //   500 000 so'm  (Uzum tiyinda: 50 000 000)
  const INV = 'S1__2026-09';
  state.students['S1'] = { id: 'S1', studentId: 'S1', name: 'Ali' };
  state.invoices[INV] = { id: INV, amount: 500000, status: 'unpaid', studentId: 'S1', studentName: 'Ali', month: '2026-09' };
  const AMT = 50000000; // tiyin

  // 0) Basic auth
  ok(uzumAuthOK(basic(LOGIN, PASS)) === true, 'to\'g\'ri login/parol -> auth OK');
  ok(uzumAuthOK(basic(LOGIN, 'wrong')) === false, 'noto\'g\'ri parol -> auth rad');
  ok(uzumAuthOK({}) === false, 'authorization yo\'q -> rad');

  // 1) CHECK — mavjud, to'lanmagan
  const c = await handleUzum('check', { serviceId: SID, params: { invoice: INV }, amount: AMT });
  ok(c.status === 'OK', 'CHECK -> OK');
  ok(c.data && c.data.account && c.data.account.invoice === INV, 'CHECK account.invoice qaytdi');

  // 1b) CHECK — noto'g'ri serviceId
  const cBad = await handleUzum('check', { serviceId: 'X', params: { invoice: INV } });
  ok(cBad.status === 'FAILED' && cBad.errorCode === 10006, 'noto\'g\'ri serviceId -> 10006');

  // 1c) CHECK — invoice topilmadi
  const cNF = await handleUzum('check', { serviceId: SID, params: { invoice: 'YOQ' } });
  ok(cNF.errorCode === 10008, 'invoice yo\'q -> 10008');

  // 2) CREATE
  const cr = await handleUzum('create', { serviceId: SID, params: { invoice: INV }, transId: 'TX1', amount: AMT });
  ok(cr.status === 'CREATED' && cr.transId === 'TX1', 'CREATE -> CREATED');
  ok(state.payments['uzum_TX1'] && state.payments['uzum_TX1'].status === 'created', 'payments "created" yozildi');

  // 2b) CREATE — noto'g'ri summa
  const crAmt = await handleUzum('create', { serviceId: SID, params: { invoice: INV }, transId: 'TXbad', amount: 999 });
  ok(crAmt.errorCode === 99999, 'noto\'g\'ri summa -> 99999');

  // 3) CONFIRM -> invoice PAID
  const cf = await handleUzum('confirm', { serviceId: SID, transId: 'TX1' });
  ok(cf.status === 'CONFIRMED', 'CONFIRM -> CONFIRMED');
  ok(state.invoices[INV].status === 'paid', 'INVOICE "paid" bo\'ldi ★');
  ok(state.invoices[INV].provider === 'uzum' && !!state.invoices[INV].paidAt, 'provider=uzum + paidAt');
  ok(state.payments['uzum_TX1'].status === 'confirmed', 'payments "confirmed"');

  // 3b) CONFIRM idempotent
  const cf2 = await handleUzum('confirm', { serviceId: SID, transId: 'TX1' });
  ok(cf2.status === 'CONFIRMED', 'CONFIRM qayta -> CONFIRMED (idempotent)');

  // 4) STATUS
  const st = await handleUzum('status', { serviceId: SID, transId: 'TX1' });
  ok(st.status === 'CONFIRMED', 'STATUS -> CONFIRMED');

  // 5) REVERSE -> invoice "reversed"
  const rv = await handleUzum('reverse', { serviceId: SID, transId: 'TX1' });
  ok(rv.status === 'REVERSED', 'REVERSE -> REVERSED');
  ok(state.invoices[INV].status === 'pending', 'INVOICE «pending» bo\'ldi (to\'liq qaytarildi — qarz tiriladi, haqiqiy SQL kabi)');
  ok(state.payments['uzum_TX1'].status === 'reversed', 'payments "reversed"');

  // 5b) CONFIRM qayta urinish: avvalgi urinishda pul QO'LLANGAN, lekin 'confirmed' yozuvi yo'qolgan; oraliqda faktura
  //     bekor qilingan -> ikkinchi urinish pulni o'quvchi balansiga YANA qo'shmasligi kerak (applied guard).
  state.invoices['IQ-0001__2026-12'] = { id:'IQ-0001__2026-12', studentId:'IQ-0001', month:'2026-12', amount: 2900000, paidAmount: 0, status:'pending' };
  await handleUzum('create', { serviceId: SID, transId: 'TX2', amount: 2900000*100, params: { invoice: 'IQ-0001__2026-12' } });
  const cfA = await handleUzum('confirm', { serviceId: SID, transId: 'TX2' });
  const credBefore = Number((state.student_credit && state.student_credit['IQ-0001'] && state.student_credit['IQ-0001'].credit) || 0);
  state.payments['uzum_TX2'].status = 'created';                 // javob/holat yozuvi yo'qolgan
  state.invoices['IQ-0001__2026-12'].status = 'canceled';        // oraliqda bekor qilingan
  const cfB = await handleUzum('confirm', { serviceId: SID, transId: 'TX2' });
  const credAfter = Number((state.student_credit && state.student_credit['IQ-0001'] && state.student_credit['IQ-0001'].credit) || 0);
  ok(cfA.status === 'CONFIRMED' && cfB.status === 'CONFIRMED' && credAfter === credBefore && state.payments['uzum_TX2'].status === 'confirmed',
     `CONFIRM qayta urinish (pul allaqachon qo'llangan) -> ikkinchi marta qo'llanmaydi (avans ${credBefore} -> ${credAfter})`);

  // 5c) REVERSE pul QO'LLANGANDAN keyin, lekin 'confirmed' yozuvi yo'qolgan (status 'created' qolgan) -> faktura
  //     baribir qaytariladi (avval faqat 'confirmed'da qaytarilardi: faktura «to'langan» qolib, pul esa qaytib ketardi).
  state.students['S3'] = { id: 'S3', studentId: 'S3', name: 'Sami' };
  state.invoices['S3__2026-09'] = { id: 'S3__2026-09', amount: 400000, status: 'unpaid', studentId: 'S3', month: '2026-09' };
  await handleUzum('create', { serviceId: SID, params: { invoice: 'S3__2026-09' }, transId: 'TX3', amount: 40000000 });
  await handleUzum('confirm', { serviceId: SID, transId: 'TX3' });
  ok(state.invoices['S3__2026-09'].status === 'paid', 'TX3 confirm -> paid');
  state.payments['uzum_TX3'].status = 'created';               // holat yozuvi yo'qolgan
  const rv3 = await handleUzum('reverse', { serviceId: SID, transId: 'TX3' });
  ok(rv3.status === 'REVERSED' && state.invoices['S3__2026-09'].status === 'pending' && Number(state.invoices['S3__2026-09'].paidAmount) === 0,
     'REVERSE (status yo\'qolgan, pul qo\'llangan) -> faktura qaytarildi ★');
  ok(state.payments['uzum_TX3'].status === 'reversed' && !(state.payments['uzum_TX3'].raw && state.payments['uzum_TX3'].raw.needsManualReverse), 'avtomatik — qo\'lda navbat yo\'q');
  const rv3b = await handleUzum('reverse', { serviceId: SID, transId: 'TX3' });
  ok(rv3b.status === 'REVERSED' && state.invoices['S3__2026-09'].status === 'pending', 'REVERSE qayta -> idempotent');

  // 5d) REVERSE qo'llanmagan (confirm bo'lmagan) tranzaksiya -> faktura/avansga tegmaydi.
  state.invoices['S3__2026-10'] = { id: 'S3__2026-10', amount: 400000, status: 'unpaid', studentId: 'S3', month: '2026-10' };
  await handleUzum('create', { serviceId: SID, params: { invoice: 'S3__2026-10' }, transId: 'TX4', amount: 40000000 });
  const rv4 = await handleUzum('reverse', { serviceId: SID, transId: 'TX4' });
  ok(rv4.status === 'REVERSED' && state.invoices['S3__2026-10'].status === 'unpaid' && !state.invoices['S3__2026-10'].reversedAt, 'qo\'llanmagan tranzaksiya REVERSE -> faktura o\'zgarmadi');

  // 6) noma'lum operatsiya
  const un = await handleUzum('foo', { serviceId: SID });
  ok(un.errorCode === 10003, 'noma\'lum op -> 10003');

  fs.unlinkSync(CFGFILE);
  console.log('\n' + (fails ? ('❌ ' + fails + ' FAILED') : '✅ ALL PASS — Uzum Merchant API oqimi Supabase backend ustida ishlaydi'));
  process.exit(fails ? 1 : 0);
})().catch(e => { try { fs.unlinkSync(CFGFILE); } catch (_) {} console.error('ERR', e.stack || e.message); process.exit(2); });
