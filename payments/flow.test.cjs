// To'lov oqimi (Click prepare -> complete) uchdan-uchgacha sinovi, Supabase
// backend (soxta, stateful) ustida. @supabase paketini Module._load bilan
// soxta mijozga almashtiramiz -> real paket/VPS kerak emas.
// Ishga tushirish:  node payments/flow.test.cjs
const fs = require('fs'), path = require('path'), crypto = require('crypto'), Module = require('module');

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
// @supabase/supabase-js ni intercept qilamiz
const orig = Module._load;
Module._load = function (req) { if (req === '@supabase/supabase-js') return { createClient: () => makeFake() }; return orig.apply(this, arguments); };

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
  // seed: to'lanmagan invoice 500000
  state.invoices['INV-42'] = { id: 'INV-42', amount: 500000, status: 'unpaid', studentId: 'S1' };

  // 1) PREPARE (to'g'ri imzo)
  const p0 = { click_trans_id: 'CT9', service_id: '111', merchant_trans_id: 'INV-42', amount: '500000', action: '0', sign_time: '2026-01-01 10:00:00' };
  p0.sign_string = sign(p0, false);
  const r1 = await handlePrepare(p0);
  ok(r1.error === 0, 'PREPARE muvaffaqiyat (error=0)');
  ok(!!r1.merchant_prepare_id, 'prepare_id qaytdi');
  ok(state.payments['click_CT9'] && state.payments['click_CT9'].status === 'prepared', 'payments doc "prepared" yozildi');

  // 2) PREPARE yaroqsiz imzo -> rad
  const bad = Object.assign({}, p0, { sign_string: 'deadbeef' });
  const rBad = await handlePrepare(bad);
  ok(rBad.error === -1, 'yaroqsiz imzo -> error=-1 (SIGN FAILED)');

  // 3) COMPLETE (to'g'ri imzo) -> invoice paid
  const p1 = { click_trans_id: 'CT9', service_id: '111', merchant_trans_id: 'INV-42', merchant_prepare_id: r1.merchant_prepare_id, amount: '500000', action: '1', sign_time: '2026-01-01 10:05:00', error: '0' };
  p1.sign_string = sign(p1, true);
  const r2 = await handleComplete(p1);
  ok(r2.error === 0, 'COMPLETE muvaffaqiyat (error=0)');
  ok(state.invoices['INV-42'].status === 'paid', 'INVOICE "paid" bo\'ldi ★');
  ok(state.invoices['INV-42'].provider === 'click' && !!state.invoices['INV-42'].paidAt, 'provider=click + paidAt yozildi');
  ok(state.payments['click_CT9'].status === 'paid', 'payments doc "paid"');

  // 4) noto'g'ri summa -> rad (yangi invoice)
  state.invoices['INV-7'] = { id: 'INV-7', amount: 300000, status: 'unpaid' };
  const pw = { click_trans_id: 'CTX', service_id: '111', merchant_trans_id: 'INV-7', amount: '999999', action: '0', sign_time: 't' };
  pw.sign_string = sign(pw, false);
  const rw = await handlePrepare(pw);
  ok(rw.error === -2, 'summa mos emas -> error=-2');

  fs.unlinkSync(CFGFILE);
  console.log('\n' + (fails ? ('❌ ' + fails + ' FAILED') : '✅ ALL PASS — to\'lov oqimi Supabase backend ustida ishlaydi'));
  process.exit(fails ? 1 : 0);
})().catch(e => { try { fs.unlinkSync(CFGFILE); } catch (_) {} console.error('ERR', e.stack || e.message); process.exit(2); });
