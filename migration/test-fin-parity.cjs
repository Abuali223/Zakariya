#!/usr/bin/env node
// =====================================================================
// test-fin-parity.cjs — YAGONA «tushgan pul» ta'rifi (moliya rejasi F0.12): admin.html dagi isCashPay() / payDay() va bazadagi
//   app.counts_as_receipt() / app.pay_day() BIR XIL natija berishi shart (Telegram kunlik hisobot = «To‘lovlar → Hisobot»).
//   admin.html dan HAQIQIY funksiyalar ajratib olinadi (nusxa emas) va ~600 ta tasodifiy + chegaraviy to'lov qatorida solishtiriladi.
//   Ishlatish:  PSQL_CMD="psql -h <host> -U postgres" node migration/test-fin-parity.cjs <kanonik zanjir qurilgan baza>
//   Bazaga hech narsa yozilmaydi (faqat SELECT).
// =====================================================================
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm'), cp = require('child_process');
const DB = process.argv[2];
if (!DB) { console.error('baza nomi kerak'); process.exit(2); }
const PSQL = (process.env.PSQL_CMD || 'psql').split(/\s+/).filter(Boolean);
const html = fs.readFileSync(path.join(__dirname, '..', 'admin.html'), 'utf8');

// --- admin.html dan funksiyalarni ajratib olish ---
function grab(re, name) { const m = html.match(re); if (!m) { console.error('admin.html: topilmadi — ' + name); process.exit(2); } return m[0]; }
const src = [
  grab(/const CASH_PAY_ST = new Set\([^\n]*\);/, 'CASH_PAY_ST'),
  grab(/function tkDay\(v\)\{[^\n]*\}/, 'tkDay'),
  grab(/function isCashPay\(p\)\{[^\n]*\}/, 'isCashPay'),
  grab(/function payDay\(p\)\{[\s\S]*?return \(r<=c && r>=lo\) \? r : c; \}/, 'payDay'),
].join('\n') + '\nthis.isCashPay = isCashPay; this.payDay = payDay;';
const ctx = {}; vm.createContext(ctx); vm.runInContext(src, ctx);

// --- sinov qatorlari (deterministik tasodif) ---
let seed = 20261110; const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
const pick = a => a[Math.floor(rnd() * a.length)];
const pad = n => String(n).padStart(2, '0');
const isoDay = ms => { const d = new Date(ms); return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`; };
const STATUSES = ['applied', 'paid', 'confirmed', 'unmatched', 'split', 'pending', 'canceled', 'reversed', 'refunded', 'failed', '', null];
const PROVS = ['cash', 'click', 'uzum', 'bank', 'terminal', 'reattr', 'credit', '', null];
const rows = [];
const base = Date.parse('2026-11-10T00:00:00Z');
for (let i = 0; i < 600; i++) {
  // Toshkent yarim tuni atrofidagi vaqtlar ham (UTC 18:30–19:30) ko'p bo'lsin
  const created = base - Math.floor(rnd() * 90) * 864e5 + (rnd() < 0.3 ? (18.5 + rnd()) * 3600e3 : Math.floor(rnd() * 864e5));
  const cDay = isoDay(created + 5 * 3600e3);
  let raw = null;
  const k = rnd();
  if (k < 0.55) {
    const off = Math.floor(rnd() * 70) - 20;   // -20 (kelajak) … +49 kun orqaga
    const dd = isoDay(Date.parse(cDay + 'T00:00:00Z') - off * 864e5);
    raw = { manual: pick([true, true, true, false, 1, 'yes']), date: pick([dd, dd, dd, '', 'bad', dd.replace(/-/g, '.')]) };
  } else if (k < 0.7) raw = { date: isoDay(created) };
  const id = pick(['man_', 'click_', 'uz_', 'pay_']) + i + (rnd() < 0.15 ? ':s:S' + i : '');
  rows.push({ id, status: pick(STATUSES), provider: pick(PROVS), amount: pick([0, -100, 100, 2900000, 1500000.5, null]), created: new Date(created).toISOString(), raw });
}
// chegaraviy holatlar
rows.push({ id: 'b1', status: 'applied', provider: 'cash', amount: 1, created: '2026-11-09T18:59:59Z', raw: null });          // 23:59:59 Toshkent
rows.push({ id: 'b2', status: 'applied', provider: 'cash', amount: 1, created: '2026-11-09T19:00:00Z', raw: null });          // 00:00 ertasi
rows.push({ id: 'b3', status: 'applied', provider: 'bank', amount: 1, created: '2026-11-10T06:00:00Z', raw: { manual: true, date: '2026-10-10' } });   // aynan 31 kun
rows.push({ id: 'b4', status: 'applied', provider: 'bank', amount: 1, created: '2026-11-10T06:00:00Z', raw: { manual: true, date: '2026-10-09' } });   // 32 kun
rows.push({ id: 'b5', status: 'split', provider: 'click', amount: 5, created: '2026-11-10T06:00:00Z', raw: null });

// --- JS natija ---
const js = rows.map(r => {
  const p = { id: r.id, status: r.status, provider: r.provider, amount: r.amount, createdAt: r.created, raw: r.raw };
  return { id: r.id, rc: !!ctx.isCashPay(p), day: ctx.payDay(p) };
});

// --- SQL natija ---
const payload = JSON.stringify(rows).replace(/'/g, "''");
const sql = `select x.id || '|' || app.counts_as_receipt(x.id, x.status, x.provider, x.amount)::text || '|' || coalesce(app.pay_day(x.created, x.raw)::text, '')
  from jsonb_to_recordset('${payload}'::jsonb) as x(id text, status text, provider text, amount numeric, created timestamptz, raw jsonb)`;
const out = cp.execFileSync(PSQL[0], [...PSQL.slice(1), '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', DB], { input: sql, encoding: 'utf8', maxBuffer: 64 << 20 });
const sqlRes = new Map(out.trim().split('\n').map(l => { const [id, rc, day] = l.split('|'); return [id, { rc: rc === 'true', day }]; }));

let pass = 0, fail = 0;
for (const j of js) {
  const s = sqlRes.get(j.id);
  if (s && s.rc === j.rc && s.day === j.day) pass++;
  else { fail++; if (fail <= 10) console.log('FAIL', j.id, 'js=', j.rc, j.day, 'sql=', s && s.rc, s && s.day, JSON.stringify(rows.find(r => r.id === j.id))); }
}
const rc = js.filter(j => j.rc).length;
console.log(`JS↔SQL moslik: ${pass}/${js.length} qator bir xil (tushgan deb hisoblangan: ${rc})`);
process.exit(fail ? 1 : 0);
