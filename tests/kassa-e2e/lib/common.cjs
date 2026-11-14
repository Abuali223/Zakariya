// «Kassa» brauzer ssenariylari uchun umumiy yordamchi (LOKAL stend; tests/kassa-e2e/README.md).
//   Ssenariy boshida:  const E = require('../lib/common.cjs');  →  E.q(sql), E.session(uid, email, meta), E.ids, E.BASE, E.OUT,
//   E.launch() (chromium; tashqi xostlar yopiq, supabase-js — lokal to'plamdan), E.PSQL / E.DB (psql ni o'zi chaqiradigan joylar uchun).
//   Sozlamalar — env.sh dagi bilan bir xil standartlar; local.env (git'ga kirmaydi) va muhit o'zgaruvchilari ustun.
'use strict';
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const DIR = path.resolve(__dirname, '..');
// local.env: KALIT=qiymat qatorlari (env.sh dagi kabi); muhitda berilgani ustun
try {
  for (const line of fs.readFileSync(path.join(DIR, 'local.env'), 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
} catch (_) { /* local.env ixtiyoriy */ }
const env = (k, d) => (process.env[k] === undefined || process.env[k] === '' ? d : process.env[k]);
const REPO = path.resolve(DIR, '..', '..');
const LOCAL = env('E2E_LOCAL', path.join(DIR, 'local'));
const DB = env('E2E_DB', 'fx_e2e');
if (!/^fx_[a-z0-9_]+$/.test(DB)) throw new Error(`E2E_DB fx_* ko'rinishida bo'lishi kerak (hozir: ${DB})`);
const PGHOST = env('E2E_PGHOST', '/var/run/postgresql'), PGPORT = env('E2E_PGPORT', '5432'), PGUSER = env('E2E_PGUSER', 'postgres');
const WEB_PORT = Number(env('E2E_WEB_PORT', '59183')), PGRST_PORT = Number(env('E2E_PGRST_PORT', '59182'));
// server.cjs shu qiymatlarni o'qiydi (ssenariy undan session() ni oladi — bir xil JWT siri)
Object.assign(process.env, { E2E_LOCAL: LOCAL, E2E_DB: DB, E2E_PGHOST: PGHOST, E2E_PGPORT: PGPORT, E2E_PGUSER: PGUSER,
  E2E_WEB_PORT: String(WEB_PORT), E2E_PGRST_PORT: String(PGRST_PORT) });

const PSQL = ['psql', '-h', PGHOST, '-p', PGPORT, '-U', PGUSER, '-X'];
// Bazada so'rov (postgres nomidan, tizim sifatida) — natija matni (bir nechta qator bo'lsa — qatorlar)
const q = sql => cp.execFileSync(PSQL[0], [...PSQL.slice(1), '-q', '-At', '-d', DB, '-c', sql], { encoding: 'utf8' }).trim();

const { session } = require(path.join(DIR, 'server.cjs'));
let ids;
try { ids = JSON.parse(fs.readFileSync(path.join(LOCAL, 'ids.json'), 'utf8')); }
catch (_) { throw new Error(`${path.join(LOCAL, 'ids.json')} topilmadi — avval: bash tests/kassa-e2e/stand.sh reset dev`); }

let chromium;
try { ({ chromium } = require('playwright')); }
catch (_) { ({ chromium } = require(path.join(LOCAL, 'npm', 'node_modules', 'playwright'))); }

const BASE = `http://127.0.0.1:${WEB_PORT}`;
const OUT = env('E2E_OUT', path.join(LOCAL, 'out', 'shots'));
const BUNDLE = env('E2E_SUPABASE_BUNDLE', path.join(LOCAL, 'supabase-js.bundle.mjs'));

// Brauzer konteksti: faqat lokal stend; supabase-js (esm.sh) — lokal to'plamdan (bo'lmasa — esm.sh dan; README, «Talablar»), boshqa tashqi xost yopiq.
async function guard(ctx) {
  const bundle = fs.existsSync(BUNDLE) ? fs.readFileSync(BUNDLE) : null;
  await ctx.route(u => { try { const h = new URL(u).hostname; return h !== '127.0.0.1' && h !== 'localhost'; } catch (_) { return false; } }, route => {
    const u = new URL(route.request().url());
    if (u.hostname === 'esm.sh' && /@supabase\/supabase-js/.test(u.pathname)) {
      if (bundle) return route.fulfill({ status: 200, contentType: 'text/javascript; charset=utf-8', headers: { 'Access-Control-Allow-Origin': '*' }, body: bundle });
      return route.continue();   // to'plam yo'q: esm.sh dan (oflayn ishlash uchun to'plam — README, «Talablar»)
    }
    return route.abort();        // shriftlar, CDN, to'lov va Telegram xostlari — lokal sinovda kerak emas
  });
}
async function launch(opts) {
  const b = await chromium.launch(Object.assign({ headless: true }, opts || {}));
  const newContext = b.newContext.bind(b);
  b.newContext = async o => { const c = await newContext(o); await guard(c); return c; };
  return b;
}

module.exports = { REPO, DIR, LOCAL, DB, PSQL, q, session, ids, chromium, launch, BASE, OUT };
