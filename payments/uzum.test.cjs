// Uzum Merchant API oqimi (check → create → confirm → status → reverse)
// uchdan-uchgacha sinovi, Supabase backend (soxta, stateful) ustida.
// @supabase paketini Module._load bilan soxta mijozga almashtiramiz.
// Ishga tushirish:  node payments/uzum.test.cjs
const fs = require('fs'), path = require('path'), Module = require('module');

// ---- soxta, stateful Supabase mijozi (in-memory jadvallar) ----
const state = { invoices: {}, payments: {} };
function match(r, filters) { return filters.every(([f, v]) => String(r[f]) === String(v)); }
function makeFake() {
  return { from(table) {
    const filters = [];
    const api = {
      select() { return api; },
      eq(f, v) { filters.push([f, v]); return api; },
      maybeSingle() { const rows = Object.values(state[table] || {}).filter(r => match(r, filters)); return Promise.resolve({ data: rows[0] || null, error: null }); },
      upsert(obj) { state[table] = state[table] || {}; state[table][obj.id] = Object.assign({}, state[table][obj.id], obj); return Promise.resolve({ error: null }); },
      update(obj) { return { eq(f, v) { for (const id in state[table] || {}) if (String(state[table][id][f]) === String(v)) Object.assign(state[table][id], obj); return Promise.resolve({ error: null }); } }; },
      delete() { return { eq(f, v) { for (const id in state[table] || {}) if (String(state[table][id][f]) === String(v)) delete state[table][id]; return Promise.resolve({ error: null }); } }; },
      then(res) { const rows = Object.values(state[table] || {}).filter(r => match(r, filters)); return Promise.resolve({ data: rows, error: null }).then(res); },
    };
    return api;
  } };
}
const orig = Module._load;
Module._load = function (req) { if (req === '@supabase/supabase-js') return { createClient: () => makeFake() }; return orig.apply(this, arguments); };

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
  // seed: to'lanmagan invoice — 500 000 so'm  (Uzum tiyinda: 50 000 000)
  state.invoices['INV-42'] = { id: 'INV-42', amount: 500000, status: 'unpaid', studentId: 'S1', studentName: 'Ali', month: '2026-08' };
  const AMT = 50000000; // tiyin

  // 0) Basic auth
  ok(uzumAuthOK(basic(LOGIN, PASS)) === true, 'to\'g\'ri login/parol -> auth OK');
  ok(uzumAuthOK(basic(LOGIN, 'wrong')) === false, 'noto\'g\'ri parol -> auth rad');
  ok(uzumAuthOK({}) === false, 'authorization yo\'q -> rad');

  // 1) CHECK — mavjud, to'lanmagan
  const c = await handleUzum('check', { serviceId: SID, params: { invoice: 'INV-42' }, amount: AMT });
  ok(c.status === 'OK', 'CHECK -> OK');
  ok(c.data && c.data.account && c.data.account.invoice === 'INV-42', 'CHECK account.invoice qaytdi');

  // 1b) CHECK — noto'g'ri serviceId
  const cBad = await handleUzum('check', { serviceId: 'X', params: { invoice: 'INV-42' } });
  ok(cBad.status === 'FAILED' && cBad.errorCode === 10006, 'noto\'g\'ri serviceId -> 10006');

  // 1c) CHECK — invoice topilmadi
  const cNF = await handleUzum('check', { serviceId: SID, params: { invoice: 'YOQ' } });
  ok(cNF.errorCode === 10008, 'invoice yo\'q -> 10008');

  // 2) CREATE
  const cr = await handleUzum('create', { serviceId: SID, params: { invoice: 'INV-42' }, transId: 'TX1', amount: AMT });
  ok(cr.status === 'CREATED' && cr.transId === 'TX1', 'CREATE -> CREATED');
  ok(state.payments['uzum_TX1'] && state.payments['uzum_TX1'].status === 'created', 'payments "created" yozildi');

  // 2b) CREATE — noto'g'ri summa
  const crAmt = await handleUzum('create', { serviceId: SID, params: { invoice: 'INV-42' }, transId: 'TXbad', amount: 999 });
  ok(crAmt.errorCode === 99999, 'noto\'g\'ri summa -> 99999');

  // 3) CONFIRM -> invoice PAID
  const cf = await handleUzum('confirm', { serviceId: SID, transId: 'TX1' });
  ok(cf.status === 'CONFIRMED', 'CONFIRM -> CONFIRMED');
  ok(state.invoices['INV-42'].status === 'paid', 'INVOICE "paid" bo\'ldi ★');
  ok(state.invoices['INV-42'].provider === 'uzum' && !!state.invoices['INV-42'].paidAt, 'provider=uzum + paidAt');
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
  ok(state.invoices['INV-42'].status === 'reversed', 'INVOICE "reversed" bo\'ldi');
  ok(state.payments['uzum_TX1'].status === 'reversed', 'payments "reversed"');

  // 6) noma'lum operatsiya
  const un = await handleUzum('foo', { serviceId: SID });
  ok(un.errorCode === 10003, 'noma\'lum op -> 10003');

  fs.unlinkSync(CFGFILE);
  console.log('\n' + (fails ? ('❌ ' + fails + ' FAILED') : '✅ ALL PASS — Uzum Merchant API oqimi Supabase backend ustida ishlaydi'));
  process.exit(fails ? 1 : 0);
})().catch(e => { try { fs.unlinkSync(CFGFILE); } catch (_) {} console.error('ERR', e.stack || e.message); process.exit(2); });
