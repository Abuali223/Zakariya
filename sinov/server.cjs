#!/usr/bin/env node
// =====================================================================
// IQROR — SINOV NUSXASI serveri (o'qitish / qabul sinovi stendi).  Node.js 18+, npm paketlarisiz.
//
//   Bitta kichik HTTP server (faqat 127.0.0.1; tashqariga nginx 8443-port orqali chiqadi):
//     /                 statik sahifalar (stend «release/web» papkasi, FAQAT o'qish). HTML'da deploy.sh bilan bir xil
//                       almashtirish (https://www.gstatic.com/firebasejs/10.12.5 -> /sb) + «SINOV NUSXASI» belgisi,
//                       X-Robots-Tag: noindex, Cache-Control: no-store, connect-src 'self' (sahifa boshqa serverga
//                       so'rov yubora olmaydi — sinov to'lovi hech qachon haqiqiy bazaga ketmaydi).
//     /sb/sb-config.js  stend uchun yaratiladi: URL = shu sahifaning o'z manzili, anon kalit — STEND siri bilan imzolangan.
//     /sw.js            hech narsa keshlamaydigan va o'zini o'chiradigan service worker.
//     /auth/v1/*        GoTrue'ning ilova ishlatadigan qismi: token (password, refresh_token), user, logout.
//                       Faqat o'rnatishda yaratilgan sinov hisoblari; ro'yxatdan o'tish, Google, parol almashtirish — yo'q.
//     /rest/v1/*        stend PostgREST'iga proksi (iqror_sinov bazasi).
//     /realtime/v1/*    «jim» websocket (ulanadi, lekin hech narsa yubormaydi) — konsolda xato chiqmasligi uchun.
//     /authapi/*, /storage/v1/*, /functions/*, /pay/*, /ai/*  — zararsiz javoblar: SMS, Telegram, to'lov, fayl yuklash YO'Q.
//     /__sinov/health   holat (install.sh va update.sh tekshiradi).
//
//   Hech qachon tashqi serverga ulanmaydi (faqat 127.0.0.1 dagi PostgREST'ga).
//
//   Sozlama (muhit o'zgaruvchilari):
//     SINOV_HOST (127.0.0.1)            SINOV_PORT (8794)
//     SINOV_ROOT (/opt/iqror-sinov/release/web)
//     SINOV_REST_HOST (127.0.0.1)       SINOV_REST_PORT (8793)
//     SINOV_JWT_SECRET  yoki  SINOV_JWT_SECRET_FILE        — stend JWT siri (PostgREST bilan bir xil; >= 32 belgi)
//     SINOV_ACCOUNTS_B64  yoki  SINOV_ACCOUNTS_FILE        — sinov hisoblari: { email: {uid, role, name, salt, hash} }
//     SINOV_RELEASE (ixtiyoriy)         — qaysi versiya ko'rsatilayotgani (health uchun)
//     SINOV_PRINT_MARK=0                — chop etiladigan hujjatlarga «SINOV» belgisini qo'ymaslik
//     SINOV_LOG=all | auth | off        — jurnal (standart: auth — kirishlar va xatolar)
//
//   Qo'shimcha buyruq (install.sh ishlatadi, root):
//     node server.cjs --sync-accounts <accounts.txt> <xeshlar.b64> [stend URL]   (stdin: seed.cjs --accounts JSON)
//       accounts.txt (600) ni yaratadi/yangilaydi — mavjud parollar SAQLANADI, yangi hisobga tasodifiy parol;
//       xeshlar.b64 (600) — parol xeshlari (base64, bitta qator; server.env ga yoziladi). Ochiq parol faqat accounts.txt da.
//       stdout: «yangi=N jami=M».
// =====================================================================
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const BANNER_TEXT = 'SINOV NUSXASI — haqiqiy ma’lumot emas';
const FB_BASE = 'https://www.gstatic.com/firebasejs/10.12.5';   // deploy.sh SHIM bilan bir xil
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 32 };

// ---------------------------------------------------------------- yordamchilar
const b64u = b => Buffer.from(b).toString('base64url');
const nowSec = () => Math.floor(Date.now() / 1000);
function hmac(secret, data) { return crypto.createHmac('sha256', secret).update(data).digest('base64url'); }
function safeEq(a, b) {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}
function jwtSign(secret, payload) {
  const h = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64u(JSON.stringify(payload));
  return `${h}.${p}.${hmac(secret, h + '.' + p)}`;
}
function jwtVerify(secret, tok) {
  const parts = String(tok || '').split('.');
  if (parts.length !== 3) return null;
  if (!safeEq(hmac(secret, parts[0] + '.' + parts[1]), parts[2])) return null;
  try {
    const hd = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
    if (!hd || hd.alg !== 'HS256') return null;
    const p = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    if (!p || typeof p !== 'object') return null;
    if (p.exp != null && Number(p.exp) < nowSec()) return null;
    return p;
  } catch (_) { return null; }
}
function scryptHash(password, saltHex) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(String(password), Buffer.from(saltHex, 'hex'), SCRYPT.keylen, { N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p },
      (e, k) => e ? reject(e) : resolve(k.toString('hex')));
  });
}

// ---------------------------------------------------------------- --sync-accounts (install.sh, root)
// accounts.txt qatorlari:  rol | login (email) | parol | ism      ('#' — izoh)
function parseAccountsTxt(txt) {
  const out = {};
  for (const line of String(txt || '').split('\n')) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    const c = line.split('|').map(s => s.trim());
    if (c.length >= 3 && c[1].includes('@') && c[2]) out[c[1].toLowerCase()] = c[2];
  }
  return out;
}
// O'qilishi oson, adashtirmaydigan belgilar (0/O, 1/l/I yo'q): 3 x 4 belgi, kamida bitta katta, kichik harf va raqam.
function newPassword() {
  const U = 'ABCDEFGHJKLMNPQRSTUVWXYZ', L = 'abcdefghijkmnpqrstuvwxyz', D = '23456789', A = U + L + D;
  for (;;) {
    let s = '';
    for (let i = 0; i < 12; i++) s += A[crypto.randomInt(A.length)];
    if (/[A-Z]/.test(s) && /[a-z]/.test(s) && /[2-9]/.test(s)) return s.slice(0, 4) + '-' + s.slice(4, 8) + '-' + s.slice(8);
  }
}
async function syncAccounts(txtPath, b64Path, publicUrl) {
  const defs = JSON.parse(fs.readFileSync(0, 'utf8'));
  if (!Array.isArray(defs) || !defs.length) throw new Error('hisoblar ro‘yxati bo‘sh (seed.cjs --accounts)');
  let old = {};
  try { old = parseAccountsTxt(fs.readFileSync(txtPath, 'utf8')); } catch (_) {}
  const hashes = {}, lines = [];
  let fresh = 0;
  for (const d of defs) {
    const email = String(d.email || '').toLowerCase();
    if (!/^[a-z0-9._-]+@[a-z0-9.-]+$/.test(email) || !/^[0-9a-f-]{36}$/.test(String(d.uid || ''))) throw new Error('noto‘g‘ri hisob ta’rifi: ' + JSON.stringify(d));
    let pw = old[email];
    if (!pw) { pw = newPassword(); fresh++; }
    const salt = crypto.randomBytes(16).toString('hex');
    hashes[email] = { uid: d.uid, role: d.role || '', name: d.name || '', salt, hash: await scryptHash(pw, salt) };
    lines.push([String(d.label || d.role || '').padEnd(16), email.padEnd(24), pw.padEnd(16), d.name || ''].join(' | '));
  }
  const head = [
    '# IQROR — SINOV NUSXASI: sinov hisoblari. Bu fayl faqat shu serverda (root, 600). Faylni to‘liq hech kimga yubormang —',
    '#   har bir xodimga faqat o‘z qatorini bering. Bu parollar haqiqiy tizimda ISHLAMAYDI (va aksincha).',
    publicUrl ? '# Manzil: ' + publicUrl + '/admin.html' : null,
    '# Bitta hisob parolini yangilash: o‘sha qatorni o‘chirib, «bash install.sh» ni qayta ishga tushiring (yangi parol beriladi).',
    '#',
    '# lavozim | login | parol | ism',
  ].filter(x => x !== null);
  const write600 = (file, text) => { const tmp = file + '.new'; fs.writeFileSync(tmp, text, { mode: 0o600 }); fs.chmodSync(tmp, 0o600); fs.renameSync(tmp, file); };
  write600(txtPath, head.concat(lines).join('\n') + '\n');
  write600(b64Path, Buffer.from(JSON.stringify(hashes)).toString('base64') + '\n');
  process.stdout.write(`yangi=${fresh} jami=${defs.length}\n`);
}
if (process.argv[2] === '--sync-accounts') {
  if (!process.argv[3] || !process.argv[4]) { console.error('ishlatish: node server.cjs --sync-accounts <accounts.txt> <xeshlar.b64> [URL]  < hisoblar.json'); process.exit(2); }
  syncAccounts(process.argv[3], process.argv[4], process.argv[5] || '').then(() => process.exit(0), e => { console.error('❌ ' + (e.message || e)); process.exit(1); });
  return;
}

// ---------------------------------------------------------------- sozlama
const env = process.env;
const int = (v, d) => { const n = parseInt(v, 10); return Number.isFinite(n) && n > 0 ? n : d; };
const HOST = env.SINOV_HOST || '127.0.0.1';
const PORT = int(env.SINOV_PORT, 8794);
const ROOT = path.resolve(env.SINOV_ROOT || '/opt/iqror-sinov/release/web');
const REST = { host: env.SINOV_REST_HOST || '127.0.0.1', port: int(env.SINOV_REST_PORT, 8793) };
const RELEASE = String(env.SINOV_RELEASE || '').slice(0, 80);
const PRINT_MARK = env.SINOV_PRINT_MARK !== '0';
const LOG_MODE = ['all', 'auth', 'off'].includes(env.SINOV_LOG) ? env.SINOV_LOG : 'auth';
const ACCESS_TTL = 3600;                 // kirish tokeni: 1 soat
const REFRESH_TTL = 14 * 86400;          // yangilash tokeni: 14 kun
const MAX_JSON = 64 * 1024;              // /auth, /authapi so'rov tanasi
const MAX_REST = 8 * 1024 * 1024;        // /rest so'rov tanasi (Excel importi ham sig'adi)

function fail(msg) { console.error('❌ sinov serveri: ' + msg); process.exit(1); }
const LOOPBACK = ['127.0.0.1', '::1', 'localhost'];
if (!LOOPBACK.includes(HOST)) fail(`SINOV_HOST=${HOST} — faqat 127.0.0.1 da tinglaydi (tashqariga nginx orqali chiqadi)`);
if (!LOOPBACK.includes(REST.host)) fail(`SINOV_REST_HOST=${REST.host} — stend PostgREST'i faqat 127.0.0.1 da bo'lishi kerak`);
let SECRET = env.SINOV_JWT_SECRET || '';
if (!SECRET && env.SINOV_JWT_SECRET_FILE) { try { SECRET = fs.readFileSync(env.SINOV_JWT_SECRET_FILE, 'utf8').trim(); } catch (e) { fail('JWT siri o‘qilmadi: ' + e.message); } }
if (SECRET.length < 32) fail('SINOV_JWT_SECRET yo‘q yoki qisqa (kamida 32 belgi)');
let ACCOUNTS = {};
try {
  const raw = env.SINOV_ACCOUNTS_B64 ? Buffer.from(env.SINOV_ACCOUNTS_B64, 'base64').toString('utf8')
    : (env.SINOV_ACCOUNTS_FILE ? fs.readFileSync(env.SINOV_ACCOUNTS_FILE, 'utf8') : '{}');
  const j = JSON.parse(raw);
  for (const [k, v] of Object.entries(j)) if (v && v.uid && v.salt && v.hash) ACCOUNTS[k.toLowerCase()] = v;
} catch (e) { fail('sinov hisoblari o‘qilmadi: ' + e.message); }
if (!Object.keys(ACCOUNTS).length) fail('sinov hisoblari yo‘q (SINOV_ACCOUNTS_B64 / SINOV_ACCOUNTS_FILE)');
let rootOk = false; try { rootOk = fs.statSync(ROOT).isDirectory(); } catch (_) {}
if (!rootOk) fail('sahifalar papkasi topilmadi: ' + ROOT);
// Muhitdagi sirlar bola jarayonlarga yoki xato hisobotiga tushmasin.
delete process.env.SINOV_JWT_SECRET; delete process.env.SINOV_ACCOUNTS_B64;

const BY_UID = {};
for (const [email, a] of Object.entries(ACCOUNTS)) BY_UID[a.uid] = Object.assign({ email }, a);
const pwVer = a => String(a.hash).slice(0, 12);      // parol o'zgarsa eski yangilash tokenlari o'z kuchini yo'qotadi
// anon kalit: sir bir xil bo'lsa — kalit ham bir xil (qayta ishga tushirishda o'zgarmaydi).
const ANON_IAT = 1767225600;                          // 2026-01-01
const ANON_KEY = jwtSign(SECRET, { role: 'anon', iss: 'iqror-sinov', iat: ANON_IAT, exp: ANON_IAT + 20 * 365 * 86400 });
const RT_KEY = crypto.createHmac('sha256', SECRET).update('iqror-sinov:refresh-token:v1').digest();
const DUMMY_SALT = crypto.randomBytes(16).toString('hex');

// ---------------------------------------------------------------- jurnal (journald'ga; sirlar yozilmaydi)
function redactUrl(u) {
  return String(u).replace(/([?&](?:apikey|access_token|refresh_token|token|jwt|password)=)[^&#]*/gi, '$1[yashirilgan]').slice(0, 300);
}
function log(kind, req, code, note) {
  if (LOG_MODE === 'off') return;
  if (LOG_MODE === 'auth' && kind !== 'auth' && kind !== 'err' && kind !== 'sys') return;
  const ip = req ? clientIp(req) : '-';
  console.log(`${kind} ${ip} ${req ? req.method : '-'} ${req ? redactUrl(req.url) : '-'} -> ${code}${note ? ' ' + note : ''}`);
}
function clientIp(req) {
  // nginx X-Real-IP ni o'zi qo'yadi; server faqat 127.0.0.1 da tinglagani uchun unga ishonamiz.
  const x = String(req.headers['x-real-ip'] || '').trim();
  return /^[0-9a-fA-F.:]{3,45}$/.test(x) ? x : (req.socket.remoteAddress || '-');
}

// ---------------------------------------------------------------- kirish urinishlari chegarasi (xotirada)
const RL = new Map();   // kalit -> { n, until }
function rlHit(key, max, windowMs) {
  const t = Date.now(); let e = RL.get(key);
  if (!e || e.until <= t) { e = { n: 0, until: t + windowMs }; RL.set(key, e); }
  e.n++;
  return e.n > max ? Math.ceil((e.until - t) / 1000) : 0;       // 0 — ruxsat; aks holda necha soniya kutish
}
function rlPeek(key, max) { const e = RL.get(key); return e && e.until > Date.now() && e.n >= max ? Math.ceil((e.until - Date.now()) / 1000) : 0; }
function rlClear(key) { RL.delete(key); }
setInterval(() => { const t = Date.now(); for (const [k, e] of RL) if (e.until <= t) RL.delete(k); for (const [k, exp] of REVOKED) if (exp <= t) REVOKED.delete(k); }, 60000).unref();
const LOGIN_IP_MAX = 40, LOGIN_IP_WIN = 10 * 60000;       // bitta IP: 10 daqiqada 40 urinish (maktab Wi-Fi'si — bitta IP)
const LOGIN_FAIL_MAX = 8, LOGIN_FAIL_WIN = 15 * 60000;    // bitta hisob: 15 daqiqada 8 xato parol
const REFRESH_IP_MAX = 240, REFRESH_IP_WIN = 10 * 60000;

// ---------------------------------------------------------------- seans
const REVOKED = new Map();   // seans id -> muddati (chiqilgan seanslar; qayta ishga tushirilsa tozalanadi)
const META = new Map();      // uid -> user_metadata (profil ismi; faqat xotirada)
function userMeta(a) { return META.get(a.uid) || { displayName: a.name || '' }; }
function userObj(a) {
  return { id: a.uid, aud: 'authenticated', role: 'authenticated', email: a.email, phone: '',
    email_confirmed_at: '2026-01-01T00:00:00Z', confirmed_at: '2026-01-01T00:00:00Z', last_sign_in_at: new Date().toISOString(),
    app_metadata: { provider: 'email', providers: ['email'] }, user_metadata: userMeta(a), identities: [],
    created_at: '2026-01-01T00:00:00Z', updated_at: new Date().toISOString(), is_anonymous: false };
}
function refreshToken(a, sid) {
  const p = b64u(JSON.stringify({ sub: a.uid, sid, pv: pwVer(a), exp: nowSec() + REFRESH_TTL, n: crypto.randomBytes(6).toString('hex') }));
  return `rt1.${p}.${hmac(RT_KEY, p)}`;
}
function readRefresh(tok) {
  const m = /^rt1\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$/.exec(String(tok || ''));
  if (!m || !safeEq(hmac(RT_KEY, m[1]), m[2])) return null;
  try {
    const p = JSON.parse(Buffer.from(m[1], 'base64url').toString('utf8'));
    const a = BY_UID[p.sub];
    if (!a || p.exp < nowSec() || p.pv !== pwVer(a) || REVOKED.has(p.sid)) return null;
    return { a, sid: p.sid };
  } catch (_) { return null; }
}
function session(a, sid) {
  sid = sid || crypto.randomUUID();
  const iat = nowSec(), exp = iat + ACCESS_TTL;
  const access_token = jwtSign(SECRET, { iss: 'iqror-sinov', sub: a.uid, aud: 'authenticated', role: 'authenticated', email: a.email,
    phone: '', app_metadata: { provider: 'email', providers: ['email'] }, user_metadata: userMeta(a), session_id: sid, is_anonymous: false, iat, exp });
  return { access_token, token_type: 'bearer', expires_in: ACCESS_TTL, expires_at: exp, refresh_token: refreshToken(a, sid), user: userObj(a) };
}
function bearer(req) { const a = String(req.headers.authorization || ''); return /^bearer /i.test(a) ? a.slice(7).trim() : ''; }
// Kirish tokeni -> hisob (faqat shu stend imzolagan, muddati o'tmagan, chiqilmagan seans).
function authed(req) {
  const c = jwtVerify(SECRET, bearer(req));
  if (!c || c.role !== 'authenticated' || !c.sub || !BY_UID[c.sub] || REVOKED.has(c.session_id)) return null;
  return { a: BY_UID[c.sub], claims: c };
}

// ---------------------------------------------------------------- javob yordamchilari
const SEC_HEADERS = { 'X-Robots-Tag': 'noindex, nofollow, noarchive', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer' };
function send(res, code, body, type, extra) {
  const buf = Buffer.isBuffer(body) ? body : Buffer.from(typeof body === 'string' ? body : JSON.stringify(body));
  const h = Object.assign({ 'Content-Type': type || 'application/json; charset=utf-8', 'Content-Length': buf.length, 'Cache-Control': 'no-store' }, SEC_HEADERS, extra || {});
  res.writeHead(code, h);
  res.end(res.req && res.req.method === 'HEAD' ? undefined : buf);
}
function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = []; let n = 0, done = false;
    req.on('data', d => { if (done) return; n += d.length; if (n > limit) { done = true; reject(Object.assign(new Error('juda katta so‘rov'), { status: 413 })); req.resume(); return; } chunks.push(d); });
    req.on('end', () => { if (!done) { done = true; resolve(Buffer.concat(chunks)); } });
    req.on('error', e => { if (!done) { done = true; reject(e); } });
  });
}
async function readJson(req) {
  const b = await readBody(req, MAX_JSON);
  if (!b.length) return {};
  try { const j = JSON.parse(b.toString('utf8')); return j && typeof j === 'object' ? j : {}; } catch (_) { return {}; }
}
const STUB_MSG = 'Sinov nusxasi: bu amal o‘chirilgan — SMS, Telegram, to‘lov tizimi va hisob boshqaruvi ishlamaydi (hech narsa yuborilmaydi).';

// ---------------------------------------------------------------- HTML (belgi + shim)
const BANNER_HTML = '<style id="sinov-style">'
  + '#sinov-banner{position:fixed;top:0;left:50%;transform:translateX(-50%);z-index:2147483647;pointer-events:none;'
  + 'background:#B42318;color:#fff;font:700 12px/1 system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif;letter-spacing:.3px;'
  + 'padding:5px 14px 6px;border-radius:0 0 10px 10px;box-shadow:0 2px 8px rgba(0,0,0,.28);white-space:nowrap;max-width:100vw;'
  + 'overflow:hidden;text-overflow:ellipsis;opacity:.96}'
  + '#sinov-frame{position:fixed;inset:0;z-index:2147483646;pointer-events:none;border:3px solid #B42318}'
  + '@media (max-width:480px){#sinov-banner{font-size:10.5px;padding:4px 10px 5px}}'
  + '@media print{#sinov-frame{display:none}#sinov-banner{position:static;transform:none;display:block;border-radius:0;text-align:center;opacity:1;'
  + 'color:#B42318;background:none;box-shadow:none;border-bottom:1px solid #B42318}}'
  + '</style><div id="sinov-frame" aria-hidden="true"></div><div id="sinov-banner" role="note">' + BANNER_TEXT + '</div>'
  // Sahifa <body> ni qayta yozsa ham belgi qaytib qo'yiladi; sarlavhaga [SINOV] qo'shiladi.
  + '<script>(function(){var T=' + JSON.stringify(BANNER_TEXT) + ';function fix(){try{if(!document.body)return;'
  + 'if(!document.getElementById("sinov-frame")){var f=document.createElement("div");f.id="sinov-frame";f.setAttribute("aria-hidden","true");document.body.appendChild(f);}'
  + 'if(!document.getElementById("sinov-banner")){var b=document.createElement("div");b.id="sinov-banner";b.setAttribute("role","note");b.textContent=T;document.body.appendChild(b);}'
  + 'if(document.title.indexOf("[SINOV]")!==0)document.title="[SINOV] "+document.title;}catch(e){}}'
  + 'fix();document.addEventListener("DOMContentLoaded",fix);setInterval(fix,3000);})();</script>';
const HEAD_HTML = '<meta name="robots" content="noindex,nofollow,noarchive">';
// Chop etiladigan hujjat (chek, ma'lumotnoma, hisobot) shablonlari — sahifa ichidagi JS satrlarida «</head><body>» bilan
//   boshlanadi. Belgida qo'shtirnoq, apostrof, ` va $ yo'q — har qanday JS satri ichida xavfsiz.
const PRINT_MARK_HTML = '<center><b><font color=#B42318 size=2>*** SINOV NUSXASI — haqiqiy hujjat emas ***</font></b></center>';
function transformHtml(src) {
  let s = src.split(FB_BASE).join('/sb');
  const hi = s.search(/<head[^>]*>/i);
  if (hi >= 0) { const end = s.indexOf('>', hi) + 1; s = s.slice(0, end) + HEAD_HTML + s.slice(end); }
  const bi = s.search(/<body[^>]*>/i);
  if (bi < 0) return BANNER_HTML + s;
  const end = s.indexOf('>', bi) + 1;
  let rest = s.slice(end);
  if (PRINT_MARK) rest = rest.split('</head><body>').join('</head><body>' + PRINT_MARK_HTML);
  return s.slice(0, end) + BANNER_HTML + rest;
}
const htmlCache = new Map();   // fayl -> { key, buf }
function htmlFor(fp, st) {
  const key = st.mtimeMs + ':' + st.size, c = htmlCache.get(fp);
  if (c && c.key === key) return c.buf;
  const buf = Buffer.from(transformHtml(fs.readFileSync(fp, 'utf8')));
  htmlCache.set(fp, { key, buf });
  return buf;
}

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.webp': 'image/webp', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.txt': 'text/plain; charset=utf-8', '.webmanifest': 'application/manifest+json', '.map': 'application/json',
  '.pdf': 'application/pdf', '.mp4': 'video/mp4', '.webm': 'video/webm', '.xml': 'application/xml' };
const SW_JS = '// IQROR sinov nusxasi: hech narsa keshlanmaydi. Bu service worker o‘zini o‘chiradi (oflayn kesh yo‘q).\n'
  + 'self.addEventListener("install", function () { self.skipWaiting(); });\n'
  + 'self.addEventListener("activate", function (e) { e.waitUntil((async function () {\n'
  + '  try { var ks = await caches.keys(); await Promise.all(ks.map(function (k) { return caches.delete(k); })); } catch (_) {}\n'
  + '  try { await self.registration.unregister(); } catch (_) {}\n'
  + '})()); });\n';
function sbConfigJs() {
  return '// IQROR SINOV NUSXASI — bu fayl stend serveri tomonidan yaratiladi (haqiqiy sb-config.js EMAS).\n'
    + '// URL = shu sahifaning o‘z manzili: barcha so‘rovlar faqat sinov bazasiga boradi.\n'
    + 'export const SUPABASE_URL = globalThis.location.origin;\n'
    + 'export const SUPABASE_ANON_KEY = ' + JSON.stringify(ANON_KEY) + ';\n'
    + 'export const STORAGE_BUCKET = "public";\n';
}
function hostOf(req) { const h = String(req.headers.host || ''); return /^[A-Za-z0-9.-]+(:\d{1,5})?$|^\[[0-9a-fA-F:]+\](:\d{1,5})?$/.test(h) ? h : ''; }
function htmlHeaders(req) {
  const h = hostOf(req);
  // Sahifa faqat O'Z manziliga (va o'z websocket'iga) so'rov yubora oladi — haqiqiy API, to'lov yoki AI serveriga emas.
  return { 'Content-Security-Policy': "connect-src 'self'" + (h ? ' wss://' + h + ' ws://' + h : ''), 'X-Frame-Options': 'SAMEORIGIN' };
}

// ---------------------------------------------------------------- statik fayllar (faqat o'qish)
const STATIC_DIRS = new Set(['sb', 'vendor', 'assets', 'uploads', 'verify']);
const ROOT_FILE = /^[A-Za-z0-9][A-Za-z0-9._-]*\.(html|png|jpe?g|svg|ico|webp|webmanifest)$|^manifest\.json$|^[A-Za-z0-9][A-Za-z0-9_-]*$/;
function serveStatic(req, res, p) {
  if (req.method !== 'GET' && req.method !== 'HEAD') { log('err', req, 405); return send(res, 405, { message: 'Sinov nusxasi: bu manzilga faqat GET' }, null, { Allow: 'GET, HEAD' }); }
  if (p.includes('\0') || p.split('/').some(s => s.startsWith('.'))) { log('err', req, 404, 'yashirin yo‘l'); return send(res, 404, 'topilmadi', 'text/plain; charset=utf-8'); }
  if (p === '/robots.txt') return send(res, 200, 'User-agent: *\nDisallow: /\n', 'text/plain; charset=utf-8');
  if (p === '/sw.js') return send(res, 200, SW_JS, MIME['.js']);
  if (p === '/sb/sb-config.js') return send(res, 200, sbConfigJs(), MIME['.js']);
  // Faqat sayt fayllari: ildizdagi sahifa/rasm va ruxsat etilgan papkalar (server kodi, migratsiya, sozlama fayllari — yo'q).
  const seg = p.split('/').filter(Boolean);
  if (seg.length > 1 ? !STATIC_DIRS.has(seg[0]) : (seg.length === 1 && !ROOT_FILE.test(seg[0]))) { log('all', req, 404, 'ruxsat etilmagan yo‘l'); return send(res, 404, 'topilmadi', 'text/plain; charset=utf-8'); }
  let fp = path.normalize(path.join(ROOT, p));
  if (fp !== ROOT && !fp.startsWith(ROOT + path.sep)) { log('err', req, 404, 'papkadan tashqari'); return send(res, 404, 'topilmadi', 'text/plain; charset=utf-8'); }
  let st = null; try { st = fs.statSync(fp); } catch (_) {}
  if (st && st.isDirectory()) { fp = path.join(fp, 'index.html'); try { st = fs.statSync(fp); } catch (_) { st = null; } }
  // nginx'dagi «try_files $uri $uri.html» kabi: /verify -> verify.html
  if (!st && !path.extname(fp)) { try { st = fs.statSync(fp + '.html'); fp += '.html'; } catch (_) { st = null; } }
  const ext = path.extname(fp).toLowerCase();
  if (!st || !st.isFile() || !MIME[ext]) { log('all', req, 404); return send(res, 404, 'topilmadi', 'text/plain; charset=utf-8'); }
  // Havola (symlink) orqali papkadan tashqariga chiqib bo'lmaydi.
  let real = fp; try { real = fs.realpathSync(fp); } catch (_) {}
  let realRoot = ROOT; try { realRoot = fs.realpathSync(ROOT); } catch (_) {}
  if (!real.startsWith(realRoot + path.sep)) { log('err', req, 404, 'havola tashqariga'); return send(res, 404, 'topilmadi', 'text/plain; charset=utf-8'); }
  log('all', req, 200);
  if (ext === '.html') return send(res, 200, htmlFor(fp, st), MIME[ext], htmlHeaders(req));
  if (p === '/manifest.json') {
    // «Ilova sifatida o'rnatish» haqiqiy ilova bilan adashtirilmasin.
    try { const m = JSON.parse(fs.readFileSync(fp, 'utf8')); m.name = 'IQROR — SINOV NUSXASI'; m.short_name = 'SINOV'; m.theme_color = '#B42318'; m.background_color = '#B42318';
      return send(res, 200, JSON.stringify(m), MIME['.webmanifest']); } catch (_) {}
  }
  const code = ['.js', '.mjs', '.json', '.css'].includes(ext);
  const h = Object.assign({ 'Content-Type': MIME[ext], 'Content-Length': st.size, 'Cache-Control': code ? 'no-store' : 'public, max-age=3600' }, SEC_HEADERS);
  res.writeHead(200, h);
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(fp).on('error', () => res.destroy()).pipe(res);
}

// ---------------------------------------------------------------- PostgREST proksi
const HOP = new Set(['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade', 'host', 'content-length']);
function proxyRest(req, res, url) {
  // Supabase'dagi Kong kabi: «apikey» shart (stend siri bilan imzolangan bo'lishi kerak). Haqiqiy tizim kaliti bu yerda o'tmaydi.
  const key = String(req.headers.apikey || url.searchParams.get('apikey') || '');
  const kc = jwtVerify(SECRET, key);
  if (!kc) { log('err', req, 401, 'apikey yo‘q/noto‘g‘ri'); return send(res, 401, { message: key ? 'Invalid API key' : 'No API key found in request', hint: 'Sinov nusxasi: faqat shu stendning kaliti qabul qilinadi' }); }
  const tok = bearer(req);
  if (tok) {
    const c = jwtVerify(SECRET, tok);
    // Brauzerga faqat anon va authenticated tokenlar beriladi — boshqa rol (masalan service_role) bu yerdan o'tmaydi.
    if (!c || (c.role !== 'anon' && c.role !== 'authenticated') || (c.session_id && REVOKED.has(c.session_id))) {
      log('err', req, 401, 'token noto‘g‘ri/eskirgan');
      return send(res, 401, { code: 'PGRST301', message: 'JWT expired', details: null, hint: null });
    }
  }
  const cl = Number(req.headers['content-length'] || 0);
  if (cl > MAX_REST) { log('err', req, 413); return send(res, 413, { message: 'Sinov nusxasi: so‘rov juda katta' }, null, { Connection: 'close' }); }
  url.searchParams.delete('apikey');
  const qs = url.searchParams.toString();
  const target = (url.pathname.slice('/rest/v1'.length) || '/') + (qs ? '?' + qs : '');
  const headers = {};
  for (const [k, v] of Object.entries(req.headers)) if (!HOP.has(k) && !k.startsWith('x-forwarded') && k !== 'x-real-ip') headers[k] = v;
  headers.host = `${REST.host}:${REST.port}`;
  if (req.headers['content-length'] != null) headers['content-length'] = req.headers['content-length'];
  const t0 = Date.now();
  const pr = http.request({ host: REST.host, port: REST.port, method: req.method, path: target, headers, timeout: 60000 }, up => {
    const h = {};
    for (const [k, v] of Object.entries(up.headers)) if (!HOP.has(k) || k === 'content-length') h[k] = v;
    Object.assign(h, { 'Cache-Control': 'no-store', 'X-Robots-Tag': SEC_HEADERS['X-Robots-Tag'] });
    res.writeHead(up.statusCode, h);
    up.pipe(res);
    up.on('end', () => log(up.statusCode >= 400 ? 'err' : 'all', req, up.statusCode, `rest ${Date.now() - t0}ms`));
  });
  pr.on('timeout', () => pr.destroy(new Error('vaqt tugadi')));
  pr.on('error', e => {
    log('err', req, 502, 'PostgREST: ' + e.message);
    if (!res.headersSent) send(res, 502, { code: 'SINOV502', message: 'Sinov bazasi bilan aloqa yo‘q (PostgREST ishlamayapti) — administratorga xabar bering.' });
    else res.destroy();
  });
  let seen = 0;
  req.on('data', d => { seen += d.length; if (seen > MAX_REST) { pr.destroy(new Error('juda katta so‘rov')); req.destroy(); } });
  req.pipe(pr);
}
function restProbe() {
  return new Promise(resolve => {
    const r = http.request({ host: REST.host, port: REST.port, method: 'GET', path: '/users?select=id&limit=1', timeout: 4000,
      headers: { Authorization: 'Bearer ' + ANON_KEY, Accept: 'application/json' } }, up => { up.resume(); up.on('end', () => resolve({ ok: up.statusCode === 200, status: up.statusCode })); });
    r.on('timeout', () => r.destroy(new Error('timeout')));
    r.on('error', e => resolve({ ok: false, status: 0, error: e.code || e.message }));
    r.end();
  });
}

// ---------------------------------------------------------------- /auth/v1 (GoTrue'ning kerakli qismi)
const tooMany = (res, sec) => send(res, 429, { code: 429, error_code: 'over_request_rate_limit', msg: `Juda ko‘p urinish. ${Math.max(1, Math.ceil(sec / 60))} daqiqadan so‘ng qayta urining.` }, null, { 'Retry-After': String(sec) });
const authOff = (res, what) => send(res, 422, { code: 422, error_code: 'sinov_disabled', msg: `Sinov nusxasi: ${what} o‘chirilgan. Sinov hisobi (login va parol) bilan kiring.` });
async function handleAuth(req, res, url, rest) {
  if (req.method === 'OPTIONS') { res.writeHead(204, SEC_HEADERS); return res.end(); }
  if (rest === 'settings' && req.method === 'GET') {
    return send(res, 200, { external: { email: true, phone: false, google: false, anonymous_users: false }, disable_signup: true, mailer_autoconfirm: true, phone_autoconfirm: false, sms_provider: '' });
  }
  if (rest === 'health' && req.method === 'GET') return send(res, 200, { name: 'iqror-sinov', description: 'GoTrue emulyatsiyasi (sinov nusxasi)' });
  if (rest === 'token' && req.method === 'POST') {
    const gt = url.searchParams.get('grant_type'), ip = clientIp(req), j = await readJson(req);
    if (gt === 'password') {
      const email = String(j.email || '').trim().toLowerCase();
      let wait = rlHit('ip:' + ip, LOGIN_IP_MAX, LOGIN_IP_WIN) || rlPeek('fail:' + email, LOGIN_FAIL_MAX);
      if (wait) { log('auth', req, 429, 'kirish: chegara'); return tooMany(res, wait); }
      const a = email && ACCOUNTS[email] ? Object.assign({ email }, ACCOUNTS[email]) : null;
      // Hisob yo'q bo'lsa ham bir xil vaqt sarflanadi (hisob bor-yo'qligi javob vaqtidan bilinmasin).
      const h = await scryptHash(String(j.password || ''), a ? a.salt : DUMMY_SALT);
      if (a && safeEq(h, a.hash)) {
        rlClear('fail:' + email);
        log('auth', req, 200, 'kirdi: ' + email);
        return send(res, 200, session(BY_UID[a.uid]));
      }
      if (email) rlHit('fail:' + email, LOGIN_FAIL_MAX, LOGIN_FAIL_WIN);
      log('auth', req, 400, 'kirish rad etildi');
      // «error_code»siz (GoTrue'ning eski ko'rinishi): ilova xabar matniga qarab o'zbekcha «Telefon/email yoki parol noto‘g‘ri» ko'rsatadi.
      return send(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials' });
    }
    if (gt === 'refresh_token') {
      const wait = rlHit('rf:' + ip, REFRESH_IP_MAX, REFRESH_IP_WIN);
      if (wait) return tooMany(res, wait);
      const r = readRefresh(j.refresh_token);
      if (r) { log('all', req, 200, 'token yangilandi'); return send(res, 200, session(r.a, r.sid)); }
      log('auth', req, 400, 'yangilash tokeni noto‘g‘ri');
      return send(res, 400, { code: 400, error_code: 'refresh_token_not_found', msg: 'Invalid Refresh Token: Refresh Token Not Found' });
    }
    return send(res, 400, { code: 400, error_code: 'invalid_grant', msg: 'Sinov nusxasi: bu kirish usuli yo‘q (faqat login va parol)' });
  }
  if (rest === 'user') {
    const s = authed(req);
    if (!s) { log('all', req, 403, 'token yo‘q/noto‘g‘ri'); return send(res, 403, { code: 403, error_code: 'bad_jwt', msg: 'invalid JWT: token is expired or invalid' }); }
    if (req.method === 'GET') return send(res, 200, userObj(s.a));
    if (req.method === 'PUT') {
      const j = await readJson(req);
      if (j.password != null || j.email != null || j.phone != null) {
        log('auth', req, 422, 'parol/email almashtirish rad etildi');
        return send(res, 422, { code: 422, error_code: 'sinov_disabled', msg: 'Sinov nusxasida parol, email va telefon o‘zgartirilmaydi — sinov hisoblari parollari serverda saqlanadi.' });
      }
      if (j.data && typeof j.data === 'object') {
        const md = Object.assign({}, userMeta(s.a));
        for (const k of ['displayName', 'photoURL']) if (typeof j.data[k] === 'string') md[k] = j.data[k].slice(0, 200);
        META.set(s.a.uid, md);
      }
      return send(res, 200, userObj(s.a));
    }
  }
  if (rest === 'logout' && req.method === 'POST') {
    const c = jwtVerify(SECRET, bearer(req));
    if (c && c.session_id) REVOKED.set(c.session_id, Date.now() + REFRESH_TTL * 1000);
    log('auth', req, 204, 'chiqdi');
    res.writeHead(204, SEC_HEADERS); return res.end();
  }
  if (rest === 'authorize') {   // «Google bilan kirish» — brauzer shu manzilga o'tadi
    log('auth', req, 200, 'google: yo‘q');
    return send(res, 200, '<!doctype html><html lang="uz"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>[SINOV] Kirish</title>'
      + '<body style="font-family:system-ui,sans-serif;padding:32px;max-width:560px;margin:auto"><h2 style="color:#B42318">' + BANNER_TEXT + '</h2>'
      + '<p>Sinov nusxasida «Google bilan kirish» yo‘q. Sizga berilgan <b>sinov login va paroli</b> bilan kiring.</p><p><a href="/admin.html">← Admin panelga qaytish</a></p></body></html>', MIME['.html']);
  }
  const what = { signup: 'ro‘yxatdan o‘tish', recover: 'parolni tiklash', otp: 'SMS / email kod', verify: 'kod bilan tasdiqlash', resend: 'qayta yuborish', magiclink: 'havola bilan kirish' }[rest.split('/')[0]];
  await readBody(req, MAX_JSON).catch(() => {});
  log('auth', req, 422, 'emulyatsiya qilinmaydi: ' + rest.slice(0, 40));
  return authOff(res, what || 'bu amal');
}

// ---------------------------------------------------------------- zararsiz javoblar (/authapi, /storage, /functions, /pay, /ai)
async function handleAuthApi(req, res, seg) {
  if (req.method === 'OPTIONS') { res.writeHead(204, SEC_HEADERS); return res.end(); }
  if (req.method === 'GET' && seg === 'health') return send(res, 200, 'ok', 'text/plain; charset=utf-8');
  if (req.method === 'GET' && seg === 'health/deep') {
    if (!authed(req)) return send(res, 401, { ok: false, error: 'Seans topilmadi — qayta kiring.' });
    const pr = await restProbe();
    const at = new Date().toISOString();
    return send(res, 200, { ok: pr.ok, at, sinov: true, checks: [
      { key: 'db', name: 'Sinov bazasi (iqror_sinov)', ok: pr.ok, info: pr.ok ? 'ishlayapti' : 'javob yo‘q', at },
      { key: 'auth', name: 'Kirish tizimi', ok: true, info: 'sinov hisoblari (' + Object.keys(ACCOUNTS).length + ' ta)', at },
      { key: 'sms', name: 'SMS (Eskiz)', ok: null, info: 'sinov nusxasida o‘chirilgan — hech narsa yuborilmaydi' },
      { key: 'tg', name: 'Telegram', ok: null, info: 'sinov nusxasida o‘chirilgan' },
      { key: 'pay', name: 'To‘lov serveri (Click / Uzum)', ok: null, info: 'sinov nusxasida o‘chirilgan' },
      { key: 'ai', name: 'AI yordamchi', ok: null, info: 'sinov nusxasida o‘chirilgan' } ] });
  }
  await readBody(req, MAX_JSON).catch(() => {});
  if (req.method === 'POST' && seg === 'tg-link-status') return send(res, 200, { ok: true, configured: false, links: [] });
  log('all', req, 200, 'authapi o‘chirilgan: ' + seg.slice(0, 40));
  return send(res, 200, { ok: false, sinov: true, error: STUB_MSG });
}
function handleStorage(req, res, rest) {
  // Fayl yuklash yo'q: so'rov tanasi o'qilmaydi, ulanish yopiladi.
  if (req.method === 'POST' && /^object\/list\//.test(rest)) { req.resume(); return send(res, 200, []); }
  if (req.method === 'GET' || req.method === 'HEAD') return send(res, 404, { statusCode: '404', error: 'not_found', message: 'Sinov nusxasi: fayl ombori yo‘q' });
  log('all', req, 403, 'fayl ombori o‘chirilgan');
  send(res, 403, { statusCode: '403', error: 'Unauthorized', message: 'Sinov nusxasida fayl (rasm, hujjat) yuklash o‘chirilgan' }, null, { Connection: 'close' });
  req.on('error', () => {}); req.resume(); setTimeout(() => { try { req.destroy(); } catch (_) {} }, 2000).unref();
}

// ---------------------------------------------------------------- «jim» realtime websocket (Phoenix: join/heartbeat -> ok)
let wsCount = 0;
function wsFrame(op, payload) {
  const b = Buffer.isBuffer(payload) ? payload : Buffer.from(String(payload));
  const head = b.length < 126 ? Buffer.from([0x80 | op, b.length]) : Buffer.from([0x80 | op, 126, b.length >> 8, b.length & 255]);
  return Buffer.concat([head, b]);
}
function handleUpgrade(req, socket) {
  let p = '/'; try { p = new URL(req.url, 'http://x').pathname; } catch (_) {}
  const key = String(req.headers['sec-websocket-key'] || '');
  if (!p.startsWith('/realtime/v1/') || !/websocket/i.test(String(req.headers.upgrade || '')) || !key || wsCount >= 300) {
    socket.end('HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n'); return;
  }
  const accept = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n');
  wsCount++;
  let buf = Buffer.alloc(0), frag = null, closed = false;
  const close = () => { if (closed) return; closed = true; wsCount--; try { socket.destroy(); } catch (_) {} };
  const reply = msg => {
    let m; try { m = JSON.parse(msg); } catch (_) { return; }
    if (Array.isArray(m)) {              // [join_ref, ref, topic, event, payload]
      if (['phx_join', 'heartbeat', 'phx_leave', 'access_token'].includes(m[3])) socket.write(wsFrame(1, JSON.stringify([m[0], m[1], m[2], 'phx_reply', { status: 'ok', response: {} }])));
    } else if (m && typeof m === 'object' && ['phx_join', 'heartbeat', 'phx_leave'].includes(m.event)) {
      socket.write(wsFrame(1, JSON.stringify({ topic: m.topic, event: 'phx_reply', payload: { status: 'ok', response: {} }, ref: m.ref, join_ref: m.join_ref })));
    }
  };
  socket.setTimeout(10 * 60000, close);
  socket.on('error', close); socket.on('close', close); socket.on('end', close);
  socket.on('data', d => {
    buf = Buffer.concat([buf, d]);
    if (buf.length > 256 * 1024) return close();
    for (;;) {
      if (buf.length < 2) return;
      const fin = (buf[0] & 0x80) !== 0, op = buf[0] & 0x0f, masked = (buf[1] & 0x80) !== 0;
      let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) return close();                      // 64 KB dan katta xabar — kerak emas
      if (!masked) return close();                               // brauzer har doim niqoblaydi
      if (buf.length < off + 4 + len) return;
      const mask = buf.subarray(off, off + 4), data = Buffer.from(buf.subarray(off + 4, off + 4 + len));
      for (let i = 0; i < data.length; i++) data[i] ^= mask[i & 3];
      buf = buf.subarray(off + 4 + len);
      if (op === 8) { try { socket.write(wsFrame(8, data.subarray(0, 2))); } catch (_) {} return close(); }
      if (op === 9) { socket.write(wsFrame(10, data)); continue; }
      if (op === 10) continue;
      if (op === 1 || op === 0) {
        frag = frag ? Buffer.concat([frag, data]) : data;
        if (frag.length > 128 * 1024) return close();
        if (fin) { const text = frag.toString('utf8'); frag = null; try { reply(text); } catch (_) {} }
        continue;
      }
      if (op === 2) { frag = null; continue; }                   // ikkilik xabarlar e'tiborsiz
      return close();
    }
  });
}

// ---------------------------------------------------------------- server
const server = http.createServer(async (req, res) => {
  let url, p;
  try { url = new URL(req.url, 'http://sinov.local'); p = decodeURIComponent(url.pathname); }
  catch (_) { return send(res, 400, { message: 'noto‘g‘ri manzil' }); }
  try {
    if (p === '/__sinov/health') {
      const pr = await restProbe();
      return send(res, pr.ok ? 200 : 503, { ok: pr.ok, stand: 'iqror-sinov', release: RELEASE, rest: pr, accounts: Object.keys(ACCOUNTS).length, time: new Date().toISOString() });
    }
    if (p === '/rest/v1' || p.startsWith('/rest/v1/')) return proxyRest(req, res, url);
    if (p.startsWith('/auth/v1/')) return await handleAuth(req, res, url, p.slice('/auth/v1/'.length).replace(/\/+$/, ''));
    if (p === '/authapi' || p.startsWith('/authapi/')) return await handleAuthApi(req, res, p.replace(/^\/authapi\/?/, '').replace(/\/+$/, ''));
    if (p.startsWith('/storage/v1/')) return handleStorage(req, res, p.slice('/storage/v1/'.length));
    if (p.startsWith('/realtime/')) return send(res, 426, { message: 'Sinov nusxasi: faqat websocket' });
    if (/^\/(functions|pay|ai)(\/|$)/.test(p)) { req.resume(); log('all', req, 404, 'o‘chirilgan xizmat'); return send(res, 404, { ok: false, sinov: true, error: STUB_MSG }); }
    return serveStatic(req, res, p);
  } catch (e) {
    const code = e && e.status ? e.status : 500;
    log('err', req, code, String(e && e.message || e).slice(0, 200));
    if (!res.headersSent) { try { send(res, code, { message: code === 413 ? 'Sinov nusxasi: so‘rov juda katta' : 'Sinov serveri xatosi' }); } catch (_) {} }
    else { try { res.destroy(); } catch (_) {} }
  }
});
server.on('upgrade', (req, socket) => { try { handleUpgrade(req, socket); } catch (_) { try { socket.destroy(); } catch (__) {} } });
server.on('clientError', (e, socket) => { try { socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'); } catch (_) {} });
server.headersTimeout = 20000; server.requestTimeout = 120000; server.keepAliveTimeout = 65000;
process.on('uncaughtException', e => { console.error('❌ kutilmagan xato: ' + (e && e.stack || e)); process.exit(1); });
process.on('unhandledRejection', e => { console.error('⚠️ ushlanmagan rad: ' + (e && e.stack || e)); });
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => { server.close(() => process.exit(0)); setTimeout(() => process.exit(0), 3000).unref(); });
server.listen(PORT, HOST, () => {
  console.log(`sys IQROR sinov nusxasi serveri: http://${HOST}:${PORT}  sahifalar=${ROOT}  PostgREST=${REST.host}:${REST.port}  hisoblar=${Object.keys(ACCOUNTS).length}${RELEASE ? '  versiya=' + RELEASE : ''}`);
});
