// «Kassa» brauzer ssenariylari — LOKAL veb-server (repo fayllarini faqat o'qiydi; hech qanday tashqi xostga ulanmaydi).
//   • repo papkasidagi statik fayllar (sahifalardagi gstatic firebase → /sb, deploy.sh dagi kabi) + yaratilgan /sb/sb-config.js;
//   • /rest/v1    → PostgREST 127.0.0.1:$E2E_PGRST_PORT (baza $E2E_DB);
//   • /auth/v1    → minimal GoTrue emulyatsiyasi: seans yangilash, user, logout, settings; parol bilan kirish — faqat
//                   local/accounts.local.json bo'lsa (ixtiyoriy, git'ga kirmaydi; ssenariylar seansni o'zi qo'yadi — parol kerak emas);
//   • /storage/v1 → kichik fayl ombori (local/storage), storage.objects ga CHAQIRUVCHI nomidan yoziladi (repo RLS qoidalari hal qiladi);
//   • /authapi    → health; qolgani — «emulyatsiya qilinmagan» (SMS, Telegram yuborilmaydi).
//   JWT siri — local/jwt-secret.txt («bash stand.sh setup» tasodifiy yaratadi; repo'da sir yo'q).
//   Ishga tushirish: bash stand.sh up (yoki to'g'ridan-to'g'ri: node server.cjs — env.sh o'zgaruvchilari bilan).
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const HERE = __dirname;
const ROOT = process.env.E2E_REPO || path.resolve(HERE, '..', '..');
const LOCAL = process.env.E2E_LOCAL || path.join(HERE, 'local');
const PORT = Number(process.env.E2E_WEB_PORT || 59183), HOST = '127.0.0.1';
const PGRST = { host: '127.0.0.1', port: Number(process.env.E2E_PGRST_PORT || 59182) };
const DB = process.env.E2E_DB || 'fx_e2e';
const PSQL = ['psql', '-h', process.env.E2E_PGHOST || '/var/run/postgresql', '-p', process.env.E2E_PGPORT || '5432', '-U', process.env.E2E_PGUSER || 'postgres', '-X'];
const SELF = `http://${HOST}:${PORT}`;
const FB_BASE = 'https://www.gstatic.com/firebasejs/10.12.5';
let SECRET;
try { SECRET = fs.readFileSync(path.join(LOCAL, 'jwt-secret.txt'), 'utf8').trim(); } catch (_) { SECRET = ''; }
if (SECRET.length < 32) throw new Error(`JWT siri yo'q yoki qisqa (${path.join(LOCAL, 'jwt-secret.txt')}) — avval: bash tests/kassa-e2e/stand.sh setup`);
const ACCT_FILE = path.join(LOCAL, 'accounts.local.json');   // ixtiyoriy: { email: {uid, salt, hash, displayName} } (scrypt)
fs.mkdirSync(path.join(LOCAL, 'logs'), { recursive: true });
const LOG = fs.createWriteStream(path.join(LOCAL, 'logs', 'server.log'), { flags: 'a' });

const b64u = b => Buffer.from(b).toString('base64url');
function sign(payload) {
  const h = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64u(JSON.stringify(payload));
  const s = crypto.createHmac('sha256', SECRET).update(h + '.' + p).digest('base64url');
  return `${h}.${p}.${s}`;
}
function verify(tok) {
  const parts = String(tok || '').split('.');
  if (parts.length !== 3) return null;
  const s = crypto.createHmac('sha256', SECRET).update(parts[0] + '.' + parts[1]).digest('base64url');
  if (s.length !== parts[2].length || !crypto.timingSafeEqual(Buffer.from(s), Buffer.from(parts[2]))) return null;
  try { const p = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')); if (p.exp && p.exp * 1000 < Date.now()) return null; return p; } catch (_) { return null; }
}
const now = () => Math.floor(Date.now() / 1000);
const ANON = sign({ role: 'anon', iss: 'supabase', iat: now(), exp: now() + 10 * 365 * 86400 });

function userObj(p) {
  return { id: p.sub, aud: 'authenticated', role: 'authenticated', email: p.email || null, phone: '',
    email_confirmed_at: '2026-01-01T00:00:00Z', confirmed_at: '2026-01-01T00:00:00Z', last_sign_in_at: new Date().toISOString(),
    app_metadata: { provider: 'email', providers: ['email'] }, user_metadata: p.user_metadata || {}, identities: [],
    created_at: '2026-01-01T00:00:00Z', updated_at: new Date().toISOString(), is_anonymous: false };
}
// Ssenariylar seansni brauzer xotirasiga shu funksiya bilan qo'yadi (sb-127-auth-token) — parol kerak emas.
function session(sub, email, user_metadata, ttlSec) {
  const ttl = ttlSec || 3600, exp = now() + ttl;
  const access_token = sign({ sub, role: 'authenticated', aud: 'authenticated', email, exp, iat: now(), user_metadata: user_metadata || {} });
  const refresh_token = 'rt.' + b64u(JSON.stringify({ sub, email, user_metadata: user_metadata || {}, n: crypto.randomBytes(6).toString('hex') }));
  return { access_token, token_type: 'bearer', expires_in: ttl, expires_at: exp, refresh_token, user: userObj({ sub, email, user_metadata }) };
}
module.exports = { sign, session, ANON, SELF };

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.webp': 'image/webp', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8', '.webmanifest': 'application/manifest+json', '.map': 'application/json', '.pdf': 'application/pdf' };

function send(res, code, body, type, extra) {
  const buf = Buffer.isBuffer(body) ? body : Buffer.from(typeof body === 'string' ? body : JSON.stringify(body));
  res.writeHead(code, Object.assign({ 'Content-Type': type || 'application/json', 'Content-Length': buf.length, 'Cache-Control': 'no-store' }, extra || {}));
  res.end(buf);
}
function readBody(req) { return new Promise(r => { const c = []; req.on('data', d => c.push(d)); req.on('end', () => r(Buffer.concat(c))); }); }
function bearer(req) { const a = String(req.headers.authorization || ''); return a.toLowerCase().startsWith('bearer ') ? a.slice(7).trim() : ''; }
function logLine(req, code, note) {
  const u = String(req.url).replace(/(apikey|access_token|refresh_token|token)=[^&]+/gi, '$1=[redacted]')
    .replace(/([?&]"?refundPin"?=)[^&#]*/gi, '$1[redacted]');
  LOG.write(`${new Date().toISOString()} ${req.method} ${u} -> ${code}${note ? ' ' + note : ''}\n`);
}
function loadAccounts() { try { return JSON.parse(fs.readFileSync(ACCT_FILE, 'utf8')); } catch (_) { return {}; } }
function checkPassword(email, password) {
  const A = loadAccounts(); const a = A[String(email || '').toLowerCase()];
  if (!a || !a.salt || !a.hash) return null;
  const h = Buffer.from(crypto.scryptSync(String(password || ''), Buffer.from(a.salt, 'hex'), 32).toString('hex'), 'hex');
  const want = Buffer.from(String(a.hash), 'hex');
  return want.length === h.length && crypto.timingSafeEqual(h, want) ? a : null;   // buzuq yozuv — rad (xato emas)
}

const STORE = path.join(LOCAL, 'storage');
function storePath(bucket, p) {
  const fp = path.normalize(path.join(STORE, bucket, p));
  if (!fp.startsWith(STORE + path.sep)) throw new Error('bad path');
  return fp;
}
// storage.objects CHAQIRUVCHI nomidan (authenticated + JWT claims) — repo'dagi storage RLS qoidalari hal qiladi (Supabase kabi).
function objSql(claims, sqlText, vars) {
  const args = PSQL.slice(1).concat(['-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', DB]);
  for (const [k, v] of Object.entries(vars || {})) args.push('-v', `${k}=${v}`);
  const pre = `begin;\nset local role ${claims ? 'authenticated' : 'anon'};\nselect set_config('request.jwt.claims', :'claims', true);\n`;
  return execFileSync(PSQL[0], args, { input: pre + sqlText + '\ncommit;\n', stdio: ['pipe', 'pipe', 'pipe'] }).toString().trim();
}
function objInsert(claims, bucket, name, size, mime) {
  try {
    objSql(claims, `insert into storage.objects(bucket_id,name,owner,metadata) values (:'b', :'n', nullif(:'o','')::uuid, jsonb_build_object('size', :'s'::int, 'mimetype', :'m'));`,
      { claims: JSON.stringify(claims || { role: 'anon' }), b: bucket, n: name, o: (claims && claims.sub) || '', s: String(size), m: mime || '' });
    return null;
  } catch (e) { return String((e.stderr || e.message || '')).split('\n').filter(Boolean).slice(-1)[0] || 'insert failed'; }
}
function objVisible(claims, bucket, name) {
  try {
    const out = objSql(claims, `select count(*) from storage.objects where bucket_id = :'b' and name = :'n';`,
      { claims: JSON.stringify(claims || { role: 'anon' }), b: bucket, n: name });
    return /(^|\n)1$/.test(out);
  } catch (_) { return false; }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, SELF);
  const p = decodeURIComponent(url.pathname);
  try {
    if (p === '/sb/sb-config.js') {
      logLine(req, 200, 'generated');
      return send(res, 200, `// LOKAL sinov stendi (tests/kassa-e2e/server.cjs) yaratgan\nexport const SUPABASE_URL = ${JSON.stringify(SELF)};\nexport const SUPABASE_ANON_KEY = ${JSON.stringify(ANON)};\nexport const STORAGE_BUCKET = "public";\n`, MIME['.js']);
    }
    // ---- PostgREST ----
    if (p.startsWith('/rest/v1/') || p === '/rest/v1') {
      const target = url.pathname.slice('/rest/v1'.length) + url.search;
      const headers = Object.assign({}, req.headers); headers.host = `${PGRST.host}:${PGRST.port}`;
      const pr = http.request({ host: PGRST.host, port: PGRST.port, method: req.method, path: target || '/', headers }, up => {
        const chunks = [];
        up.on('data', d => chunks.push(d));
        up.on('end', () => {
          const body = Buffer.concat(chunks);
          let note = '';
          if (up.statusCode >= 400) { try { const j = JSON.parse(body.toString('utf8')); note = `[${j.code || ''}] ${String(j.message || '').slice(0, 200)}`; } catch (_) { note = body.toString('utf8').slice(0, 200); } }
          logLine(req, up.statusCode, note);
          const h = Object.assign({}, up.headers); delete h['transfer-encoding']; h['content-length'] = body.length;
          res.writeHead(up.statusCode, h); res.end(body);
        });
      });
      pr.on('error', e => { logLine(req, 502, e.message); send(res, 502, { message: 'proxy error: ' + e.message }); });
      req.pipe(pr);
      return;
    }
    // ---- GoTrue emulyatsiyasi ----
    if (p.startsWith('/auth/v1/')) {
      const rest = p.slice('/auth/v1/'.length);
      const body = await readBody(req);
      let j = {}; try { j = JSON.parse(body.toString('utf8') || '{}'); } catch (_) {}
      if (rest === 'settings') {
        logLine(req, 200, 'settings');
        return send(res, 200, { disable_signup: false, mailer_autoconfirm: false, phone_autoconfirm: true, sms_provider: '',
          external: { email: true, phone: true, google: true, anonymous_users: true } });
      }
      if (rest === 'user') {
        const claims = verify(bearer(req));
        if (!claims || !claims.sub) { logLine(req, 401, 'no/invalid bearer'); return send(res, 401, { code: 401, error_code: 'bad_jwt', msg: 'invalid JWT' }); }
        let md = claims.user_metadata || {};
        if (req.method === 'PUT') { if (j.data) md = Object.assign({}, md, j.data); }
        logLine(req, 200, 'user ' + claims.sub);
        return send(res, 200, userObj(Object.assign({}, claims, { user_metadata: md })));
      }
      if (rest === 'token') {
        const gt = url.searchParams.get('grant_type');
        if (gt === 'refresh_token' && String(j.refresh_token || '').startsWith('rt.')) {
          try { const d = JSON.parse(Buffer.from(String(j.refresh_token).slice(3), 'base64url').toString('utf8'));
            logLine(req, 200, 'refresh ' + d.sub); return send(res, 200, session(d.sub, d.email, d.user_metadata)); } catch (_) {}
        }
        if (gt === 'password') {
          const a = checkPassword(j.email, j.password);
          if (a) { logLine(req, 200, 'password grant ' + a.uid); return send(res, 200, session(a.uid, String(j.email).toLowerCase(), { displayName: a.displayName || '' })); }
          logLine(req, 400, 'password grant refused');
          return send(res, 400, { code: 400, error_code: 'invalid_credentials', msg: 'Invalid login credentials', error: 'invalid_grant', error_description: 'Invalid login credentials' });
        }
        logLine(req, 400, 'token: unsupported grant');
        return send(res, 400, { error: 'invalid_grant', error_description: 'local stub: unsupported grant' });
      }
      if (rest === 'logout') { logLine(req, 204, 'logout'); res.writeHead(204); return res.end(); }
      logLine(req, 403, 'auth route refused locally');
      return send(res, 403, { code: 403, msg: 'local stub: route not emulated (' + rest + ')' });
    }
    // ---- Storage ----
    if (p.startsWith('/storage/v1/')) {
      const rest = p.slice('/storage/v1/'.length);
      const body = await readBody(req);
      let m;
      const claims = verify(bearer(req));
      const caller = claims && claims.sub ? claims : null;
      if (req.method === 'POST' && (m = rest.match(/^object\/sign\/([^/]+)\/(.+)$/))) {
        const fp = storePath(m[1], m[2]);
        if (!fs.existsSync(fp) || !objVisible(caller, m[1], m[2])) { logLine(req, 400, 'sign: not found / not allowed'); return send(res, 400, { statusCode: '404', error: 'not_found', message: 'Object not found' }); }
        logLine(req, 200, 'sign');
        return send(res, 200, { signedURL: `/object/sign/${m[1]}/${m[2]}?token=local` });
      }
      if ((req.method === 'POST' || req.method === 'PUT') && (m = rest.match(/^object\/([^/]+)\/(.+)$/))) {
        const fp = storePath(m[1], m[2]);
        const upsert = String(req.headers['x-upsert'] || '') === 'true';
        if (fs.existsSync(fp) && !upsert) { logLine(req, 400, 'exists'); return send(res, 400, { statusCode: '409', error: 'Duplicate', message: 'The resource already exists' }); }
        let data = body, mime = String(req.headers['content-type'] || '');
        const bm = mime.match(/boundary=(.+)$/);
        if (/^multipart\/form-data/.test(mime) && bm) {
          const s = body.toString('latin1'), b = '--' + bm[1];
          const parts = s.split(b).filter(x => x.includes('\r\n\r\n'));
          const fileP = parts.find(x => /filename=|name="file"|name=""/.test(x)) || parts[parts.length - 1];
          if (fileP) { const hdr = fileP.slice(0, fileP.indexOf('\r\n\r\n')); const ct = hdr.match(/Content-Type:\s*([^\r\n]+)/i); mime = ct ? ct[1] : 'application/octet-stream';
            data = Buffer.from(fileP.slice(fileP.indexOf('\r\n\r\n') + 4).replace(/\r\n$/, ''), 'latin1'); }
        }
        const err = objInsert(caller, m[1], m[2], data.length, mime);
        if (err) { logLine(req, 403, 'storage RLS refused: ' + err.slice(0, 160)); return send(res, 403, { statusCode: '403', error: 'Unauthorized', message: 'new row violates row-level security policy' }); }
        fs.mkdirSync(path.dirname(fp), { recursive: true }); fs.writeFileSync(fp, data);
        logLine(req, 200, 'stored ' + data.length + 'B as ' + (caller ? caller.sub : 'anon'));
        return send(res, 200, { Key: `${m[1]}/${m[2]}`, Id: crypto.randomUUID() });
      }
      if (req.method === 'GET' && (m = rest.match(/^object\/(?:sign|public|authenticated)\/([^/]+)\/(.+)$/))) {
        const fp = storePath(m[1], m[2]);
        if (!fs.existsSync(fp)) { logLine(req, 404, 'get: no file'); return send(res, 404, { statusCode: '404', error: 'not_found', message: 'Object not found' }); }
        logLine(req, 200, 'get');
        return send(res, 200, fs.readFileSync(fp), MIME[path.extname(fp).toLowerCase()] || 'application/octet-stream');
      }
      logLine(req, 404, 'storage route not emulated');
      return send(res, 404, { statusCode: '404', error: 'not_found', message: 'local storage stub' });
    }
    // ---- auth-server (/authapi): faqat health; SMS / Telegram yuborilmaydi ----
    if (p.startsWith('/authapi/') || p === '/authapi') {
      const seg = p.replace(/^\/authapi\/?/, '').replace(/\/+$/, '');
      await readBody(req);
      if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
      if (req.method === 'GET' && seg === 'health') { logLine(req, 200, 'health'); res.writeHead(200, { 'Content-Type': 'text/plain' }); return res.end('ok'); }
      if (req.method === 'POST' && seg === 'tg-link-status') { logLine(req, 200, 'tg stub'); return send(res, 200, { ok: true, configured: false, links: [] }); }
      logLine(req, 200, 'authapi route not emulated: ' + seg);
      return send(res, 200, { ok: false, error: 'local stub: /authapi/' + seg + ' is not emulated in the local stand' });
    }
    // ---- statik (faqat o'qish; .git, node_modules, config.json, tests/ — berilmaydi) ----
    let fp = path.normalize(path.join(ROOT, p));
    if (!fp.startsWith(ROOT + path.sep) && fp !== ROOT) { logLine(req, 403); return send(res, 403, 'forbidden', 'text/plain'); }
    const segs = path.relative(ROOT, fp).split(path.sep);
    if (segs.some(s => s === '.git' || s === 'node_modules') || segs[0] === 'tests' || /config\.json$/.test(fp) || /(^|\/)\.env/.test(fp)) {
      logLine(req, 403); return send(res, 403, 'forbidden', 'text/plain');
    }
    let st = null; try { st = fs.statSync(fp); } catch (_) {}
    if (st && st.isDirectory()) { fp = path.join(fp, 'index.html'); try { st = fs.statSync(fp); } catch (_) { st = null; } }
    if (!st || !st.isFile()) { logLine(req, 404); return send(res, 404, 'not found', 'text/plain'); }
    const ext = path.extname(fp).toLowerCase();
    let data = fs.readFileSync(fp);
    if (ext === '.html') data = Buffer.from(data.toString('utf8').split(FB_BASE).join('/sb'));
    logLine(req, 200);
    return send(res, 200, data, MIME[ext] || 'application/octet-stream');
  } catch (e) {
    logLine(req, 500, e.message);
    try { send(res, 500, { message: String(e.message || e) }); } catch (_) {}
  }
});
if (require.main === module) {
  server.listen(PORT, HOST, () => { LOG.write(`${new Date().toISOString()} listening ${SELF}\n`); console.log('listening ' + SELF); });
}
