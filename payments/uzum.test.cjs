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
  ok(state.invoices[INV].status === 'reversed', 'INVOICE "reversed" bo\'ldi');
  ok(state.payments['uzum_TX1'].status === 'reversed', 'payments "reversed"');

  // 6) noma'lum operatsiya
  const un = await handleUzum('foo', { serviceId: SID });
  ok(un.errorCode === 10003, 'noma\'lum op -> 10003');

  fs.unlinkSync(CFGFILE);
  console.log('\n' + (fails ? ('❌ ' + fails + ' FAILED') : '✅ ALL PASS — Uzum Merchant API oqimi Supabase backend ustida ishlaydi'));
  process.exit(fails ? 1 : 0);
})().catch(e => { try { fs.unlinkSync(CFGFILE); } catch (_) {} console.error('ERR', e.stack || e.message); process.exit(2); });
