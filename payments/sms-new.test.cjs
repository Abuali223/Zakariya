// =====================================================================
// sms-new.test.cjs — sms-worker.cjs «YANGI FAKTURA» xabari (runNew) uchdan-uchgacha, SINOV (--dry) rejimida: tarmoqsiz, haqiqiy
//   Supabase / Eskiz kerak emas (@supabase/supabase-js soxta mijozga almashtiriladi, Eskiz kaliti yo'q — hech narsa yuborilmaydi).
//   node payments/sms-new.test.cjs
//   Tekshiradi (A4-04, audit-10): avans yangi fakturani qisman yopgan bo'lsa — xabarda QOLGAN summa (to'liq summa emas); avans to'liq
//   yopgan bo'lsa (0,5 so'mgacha qoldiq) — xabar yo'q; to'lanmagan faktura — to'liq summa; to'langan / 0 so'mlik — xabar yo'q.
//   Ma'lumot to'qima (Sinov ismlar; telefonlar — boshqa SMS sinovlaridagi kabi takroriy raqamlar).
// =====================================================================
const fs = require('fs'), path = require('path'), Module = require('module');

const NOW = new Date().toISOString();
const state = {
  students: {}, student_private: {}, sms_log: {},
  invoices: {},
};
const stu = (sid, name, phone) => { state.students[sid] = { id: sid, studentId: sid, name }; state.student_private[sid] = { id: sid, parentPhone: phone }; };
stu('IQ-0901', 'Sinov Bir', '998901111111');
stu('IQ-0902', 'Sinov Ikki', '998902222222');
stu('IQ-0903', 'Sinov Uch', '998903333333');
stu('IQ-0904', 'Sinov Tort', '998904444444');
stu('IQ-0905', 'Sinov Besh', '998905555555');
const inv = (sid, amount, paidAmount, status) => { const id = sid + '__2026-11';
  state.invoices[id] = { id, studentId: sid, studentName: state.students[sid].name, month: '2026-11', amount, paidAmount, status, createdAt: NOW }; };
inv('IQ-0901', 2000000, 1500000, 'partial');     // avans 1 500 000 shu zahoti qo'llangan — qoldiq 500 000
inv('IQ-0902', 2000000, 1999999.6, 'partial');   // avans deyarli to'liq yopgan (0,4 so'm qoldiq) — xabar yo'q
inv('IQ-0903', 2000000, 0, 'pending');           // avanssiz — to'liq summa (avvalgidek)
inv('IQ-0904', 2000000, 2000000, 'paid');        // to'langan — xabar yo'q (avvalgidek)
inv('IQ-0905', 0, 0, 'paid');                    // grant / 0 so'm — xabar yo'q (avvalgidek)

// ---- soxta Supabase mijozi: sms-worker ishlatadigan o'qish so'rovlari (select/eq/in/gte, maybeSingle, thenable) ----
function from(table) {
  const filters = [];
  const rows = () => Object.values(state[table] || {}).filter(r => filters.every(f => f(r)));
  const api = {
    select() { return api; },
    eq(f, v) { filters.push(r => String(r[f]) === String(v)); return api; },
    in(f, vals) { const s = Array.from(vals || []).map(String); filters.push(r => s.includes(String(r[f]))); return api; },
    gte(f, v) { filters.push(r => String(r[f] || '') >= String(v)); return api; },
    order() { return api; }, range() { return api; }, limit() { return api; },
    maybeSingle() { return Promise.resolve({ data: rows()[0] || null, error: null }); },
    then(res, rej) { return Promise.resolve({ data: rows(), error: null }).then(res, rej); },
    // --dry rejimida yozuv bo'lmasligi kerak — bo'lsa, sinov buni ko'radi
    upsert() { WRITES.push(table); return Promise.resolve({ error: null }); },
    insert() { WRITES.push(table); return Promise.resolve({ error: null }); },
    update() { WRITES.push(table); return { eq: () => Promise.resolve({ error: null }) }; },
    delete() { WRITES.push(table); return { eq: () => Promise.resolve({ error: null }) }; },
  };
  return api;
}
const WRITES = [];
const fake = { from, rpc: async () => ({ data: [], error: null }), auth: { getUser: async () => ({ data: null, error: null }) } };
const orig = Module._load;
Module._load = function (req) { if (req === '@supabase/supabase-js') return { createClient: () => fake }; return orig.apply(this, arguments); };

// ---- vaqtinchalik config (payments/ ichida — sms-worker IQROR_CONFIG ni o'z papkasiga nisbatan o'qiydi) ----
const CFGFILE = path.join(__dirname, '_smsnew-config.json');
fs.writeFileSync(CFGFILE, JSON.stringify({ backend: 'supabase', supabaseUrl: 'http://x', serviceRoleKey: 'k', sms: { dryRun: true } }));
process.env.IQROR_CONFIG = '_smsnew-config.json';
process.argv = [process.argv[0], path.join(__dirname, 'sms-worker.cjs'), 'new', '--dry'];

const lines = [];
const origLog = console.log, origErr = console.error;
console.log = (...a) => { lines.push(a.map(String).join(' ')); };
console.error = (...a) => { lines.push('ERR ' + a.map(String).join(' ')); };

let fails = 0;
const ok = (c, m, x) => { origLog((c ? '✓ ' : '✗ FAIL ') + m + (c ? '' : '  ' + JSON.stringify(x))); if (!c) fails++; };
const done = () => lines.some(l => /Tugadi\.|sms-worker xato|^ERR /.test(l));

(async () => {
  try {
    require('./sms-worker.cjs');
    for (let i = 0; i < 250 && !done(); i++) await new Promise(r => setTimeout(r, 20));
  } finally {
    console.log = origLog; console.error = origErr;
    try { fs.unlinkSync(CFGFILE); } catch (_) {}
  }
  const dry = lines.filter(l => l.includes('[DRY new]'));
  const msgOf = name => dry.filter(l => l.includes(name));
  ok(done() && !lines.some(l => /sms-worker xato|^ERR /.test(l)), 'worker --dry rejimida xatosiz tugadi', lines.slice(-5));
  ok(msgOf('Sinov Bir').length === 1 && /: 500000 so'm/.test(msgOf('Sinov Bir')[0]) && !/2000000/.test(msgOf('Sinov Bir')[0]),
     'avans qisman yopgan faktura — xabarda QOLGAN summa (500 000), to\'liq 2 000 000 emas', msgOf('Sinov Bir'));
  ok(msgOf('Sinov Ikki').length === 0, 'avans to\'liq yopgan (0,4 so\'m qoldiq) — xabar yo\'q', msgOf('Sinov Ikki'));
  ok(msgOf('Sinov Uch').length === 1 && /: 2000000 so'm/.test(msgOf('Sinov Uch')[0]), 'avanssiz faktura — to\'liq summa (avvalgidek)', msgOf('Sinov Uch'));
  ok(msgOf('Sinov Tort').length === 0 && msgOf('Sinov Besh').length === 0, 'to\'langan / 0 so\'mlik — xabar yo\'q (avvalgidek)', dry);
  ok(dry.length === 2, 'jami 2 ta xabar', dry);
  ok(WRITES.length === 0, '--dry: bazaga hech narsa yozilmadi', WRITES);
  ok(!fs.existsSync(CFGFILE), 'vaqtinchalik config o\'chirildi');
  origLog(`\n${fails ? fails + ' ta FAIL' : 'hammasi o\'tdi'}`);
  process.exit(fails ? 1 : 0);
})().catch(e => { console.log = origLog; console.error = origErr; try { fs.unlinkSync(CFGFILE); } catch (_) {} origErr('ERR', e && (e.stack || e.message)); process.exit(2); });
