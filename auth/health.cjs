/**
 * auth/health.cjs — «🩺 Tizim holati» (admin.html → Sozlamalar): GET /authapi/health/deep — FAQAT FAOL direktor JWT bilan
 *   (Authorization: Bearer <jwt>). Anon -> 401, boshqa rol -> 403, kirish tizimi/baza javob bermasa -> 503.
 *   Ommaviy GET /authapi/health O'ZGARMAGAN («ok», hech qanday ma'lumotsiz — tashqi kuzatuv uchun).
 * -------------------------------------------------------------------
 * Tekshiruvlar (har biri ko'pi bilan 3 s; biri osilib qolsa boshqalari kutmaydi):
 *   auth (shu server), db (supabase-js orqali yengil so'rov), gotrue (/auth/v1/health), eskiz (kalit bormi va AMAL
 *   QILADIMI — Eskiz'ga kirib shablonlar ro'yxati so'raladi, SMS yuborilmaydi; auth.health.eskizCheck: false — faqat kalit
 *   borligi; balans — faqat auth.health.eskizBalance: true bo'lsa), pay / ai (127.0.0.1 dagi /health), payments (oxirgi muvaffaqiyatli
 *   onlayn to'lov — payments jadvalidan), backup (oxirgi «backup OK» — zaxira log faylidan).
 * Javob: { ok, at, checks:[{ key, name, ok:true|false|null, info, at?, ms }] } — ok:null = tekshirilmadi/sozlanmagan.
 *   Javobda SIR YO'Q: kalit, token, parol, ulanish manzili, email, telefon chiqmaydi — faqat holat, vaqt va qisqa sabab.
 * Sozlama (auth/config.json → auth.health, hammasi ixtiyoriy): backupLog (standart /var/log/iqror-backup.log; false — o'chiq),
 *   backupMaxAgeHours (26), payPort (8790; 0 — o'chiq), aiPort (8791; 0 — o'chiq), eskizCheck (true), eskizBalance (false).
 */
const fs = require('fs');

const PROV = { click: 'Click', uzum: 'Uzum' };
const NET = new Set(['ECONNREFUSED', 'ECONNRESET', 'EHOSTUNREACH', 'ENETUNREACH', 'ENOTFOUND', 'EAI_AGAIN', 'EPIPE']);

// Oddiy GET (tashqi paketsiz). { status, body } (tana 64 KB gacha) yoki istisno (e.code).
function httpGet(url, headers, ms) {
  return new Promise((resolve, reject) => {
    let u; try { u = new URL(url); } catch (_) { return reject(Object.assign(new Error('bad_url'), { code: 'BAD_URL' })); }
    const mod = u.protocol === 'https:' ? require('https') : require('http');
    const req = mod.request(u, { method: 'GET', headers: headers || {} }, res => {
      let d = ''; res.setEncoding('utf8');
      res.on('data', c => { if (d.length < 65536) d += c; });
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
      res.on('error', reject);
    });
    req.setTimeout(ms, () => req.destroy(Object.assign(new Error('timeout'), { code: 'TIMEOUT' })));
    req.on('error', reject);
    req.end();
  });
}
// Fayl oxiridagi n bayt (zaxira log'i katta bo'lishi mumkin).
async function readTail(file, n) {
  const fh = await fs.promises.open(file, 'r');
  try {
    const { size, mtimeMs } = await fh.stat();
    const len = Math.min(size, n), buf = Buffer.alloc(len);
    await fh.read(buf, 0, len, size - len);
    return { text: buf.toString('utf8'), mtimeMs };
  } finally { await fh.close(); }
}
function withTimeout(p, ms) {
  let t;
  return Promise.race([Promise.resolve(p), new Promise((_, rej) => { t = setTimeout(() => rej(Object.assign(new Error('timeout'), { code: 'TIMEOUT' })), ms); })])
    .finally(() => clearTimeout(t));
}
// Istisno -> qisqa sabab (xabar matni/manzil chiqarilmaydi — faqat tanish kodlar).
function reason(e, ms) {
  const c = String((e && e.code) || '');
  if (c === 'TIMEOUT') return `javob bermadi (${Math.round(ms / 1000)} s)`;
  if (NET.has(c)) return `ulanib bo‘lmadi (${c})`;
  if (e && e.stage === 'login') return 'Eskiz login xato (parol yoki token)';
  if (c === 'ENOENT') return 'log fayli topilmadi';
  if (c === 'EACCES' || c === 'EPERM') return 'log faylini o‘qishga ruxsat yo‘q';
  return 'xato' + (/^[A-Z0-9_]{2,24}$/.test(c) ? ` (${c})` : '');
}
const iso = v => { const t = Date.parse(v); return Number.isFinite(t) ? new Date(t).toISOString() : null; };
const fmtNum = n => String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
// Eskiz kaliti bormi — payments/eskiz-shablon.cjs (credsProblem) bilan bir xil qoida: token YOKI email+parol;
//   config.example.json'dagi to'ldirilmagan namuna qiymatlar («ESKIZ_EMAIL (…)», «PASTE_…») hisoblanmaydi.
const PLACEHOLDER = /ESKIZ_(EMAIL|PAROL|TOKEN)|PASTE_/;
function eskizCreds(s) {
  const email = String(s.eskizEmail || s.email || '').trim(), pass = String(s.eskizPassword || s.password || '').trim(), tok = String(s.token || '').trim();
  if (!email && tok) return !PLACEHOLDER.test(tok);
  return !!email && /@/.test(email) && !PLACEHOLDER.test(email) && !!pass && !PLACEHOLDER.test(pass);
}
const isActive = u => { const s = String((u && u.status) || ''); return s === '' || s === 'active'; };

function makeDeepHealth(deps) {
  const { sb, verifyUser, eskiz } = deps;
  const S = deps.smsCfg || {};
  const H = (deps.cfg && deps.cfg.health) || {};
  const T = Number(deps.timeoutMs) > 0 ? Number(deps.timeoutMs) : 3000;
  const get = deps.httpGet || httpGet;
  const tail = deps.readTail || readTail;
  const clock = deps.now || Date.now;
  const supaUrl = String(deps.supabaseUrl || '').replace(/\/+$/, '');
  const port = (v, def) => (v === 0 || v === false) ? 0 : (Number(v) > 0 ? Number(v) : def);
  const PAY = port(H.payPort, 8790), AI = port(H.aiPort, 8791);
  const LOG = H.backupLog === false ? '' : String(H.backupLog || '/var/log/iqror-backup.log');
  const MAXH = Number(H.backupMaxAgeHours) > 0 ? Number(H.backupMaxAgeHours) : 26;

  async function checkDb() {
    const { error } = await sb.from('config').select('id').limit(1);
    if (error) return { ok: false, info: 'so‘rov xatosi' + (/^[A-Z0-9]{5}$/.test(String(error.code || '')) ? ` (${error.code})` : '') };
    return { ok: true, info: 'ishlayapti' };
  }
  async function checkGotrue() {
    if (!supaUrl) return { ok: null, info: 'sozlanmagan' };
    const r = await get(supaUrl + '/auth/v1/health', deps.anonKey ? { apikey: deps.anonKey } : {}, T);
    return (r.status >= 200 && r.status < 300) ? { ok: true, info: 'ishlayapti' } : { ok: false, info: 'HTTP ' + r.status };
  }
  async function checkEskiz() {
    if (S.enabled === false) return { ok: null, info: 'o‘chirilgan (sms.enabled = false)' };
    if (S.dryRun === true) return { ok: null, info: 'SINOV rejimi (dryRun) — SMS yuborilmaydi' };
    if (!eskizCreds(S) || !eskiz) return { ok: false, info: 'Eskiz kaliti kiritilmagan' };
    const rejected = r => ({ ok: false, info: (r && r.httpStatus === 401) ? 'token yaroqsiz' : `Eskiz rad etdi (HTTP ${(r && r.httpStatus) || '?'})` });
    // Balans (sozlamada yoqilgan bo'lsa) — kalitni ham tekshiradi.
    if (H.eskizBalance === true && typeof eskiz.balance === 'function') {
      const r = await eskiz.balance({ timeoutMs: T });
      return (r && r.ok) ? { ok: true, info: 'balans: ' + fmtNum(r.balance) } : rejected(r);
    }
    // Kalit AMAL QILADIMI: Eskiz'ga kirib tasdiqlangan matnlar ro'yxati so'raladi (faqat o'qish — SMS yuborilmaydi; shu so'rov
    //   SMS eslatma va sms-worker'da ham ishlatiladi). Parol/token xato -> login bosqichi istisnosi yoki 401 -> qizil.
    if (H.eskizCheck === false || typeof eskiz.templates !== 'function') return { ok: true, info: 'kalit kiritilgan (amal qilishi tekshirilmadi)' };
    const r = await eskiz.templates({ timeoutMs: T });
    return (r && r.ok) ? { ok: true, info: 'kalit amal qiladi (balans tekshiruvi o‘chiq)' } : rejected(r);
  }
  async function checkLocal(p) {
    if (!p) return { ok: null, info: 'tekshirilmaydi' };
    const r = await get(`http://127.0.0.1:${p}/health`, {}, T);
    return r.status === 200 ? { ok: true, info: 'ishlayapti' } : { ok: false, info: 'HTTP ' + r.status };
  }
  async function checkPayments() {
    const { data, error } = await sb.from('payments').select('createdAt,provider')
      .in('provider', ['click', 'uzum']).in('status', ['applied', 'paid', 'confirmed', 'unmatched', 'split'])
      .order('createdAt', { ascending: false }).limit(1);
    if (error) return { ok: false, info: 'so‘rov xatosi' };
    const p = data && data[0];
    if (!p) return { ok: null, info: 'hali onlayn to‘lov yo‘q' };
    return { ok: true, info: PROV[String(p.provider || '')] || 'onlayn', at: iso(p.createdAt) };
  }
  async function checkBackup() {
    if (!LOG) return { ok: null, info: 'tekshirilmaydi' };
    const { text, mtimeMs } = await tail(LOG, 65536);
    const lines = String(text || '').split('\n');
    let okIdx = -1, errIdx = -1, lastIdx = -1;
    lines.forEach((ln, i) => { if (ln.trim()) lastIdx = i; if (/backup OK/.test(ln)) okIdx = i; else if (/❌/.test(ln)) errIdx = i; });
    const tOf = ln => { const m = /\[([^\]]{6,60})\]/.exec(ln || ''); return m ? iso(m[1]) : null; };
    let at = okIdx >= 0 ? tOf(lines[okIdx]) : null;
    // Qatordagi [sana]ni ajratib bo'lmasa (noodatiy vaqt zonasi qisqartmasi, masalan «MSK») va «backup OK» — log'ning OXIRGI
    //   qatori bo'lsa: faylning o'zgartirilgan vaqti (aynan shu qator yozilgan payt).
    if (okIdx >= 0 && !at && okIdx === lastIdx && Number.isFinite(mtimeMs)) at = new Date(mtimeMs).toISOString();
    // «Haftalik hisobot» (PKG-11): oxirgi 7 sutkada muvaffaqiyatli zaxira bo'lgan kechalar soni (Toshkent sanasi bo'yicha, ≤ 7).
    const WEEK = 7 * 24 * 3600e3, nights = new Set(), now = clock();
    const addNight = t => { const ms = t ? Date.parse(t) : NaN; if (Number.isFinite(ms) && now - ms <= WEEK && ms <= now + 3600e3) nights.add(new Date(ms + 5 * 3600e3).toISOString().slice(0, 10)); };
    lines.forEach((ln, i) => { if (/backup OK/.test(ln)) addNight(i === okIdx ? at : tOf(ln)); });
    const nights7 = Math.min(7, nights.size);
    if (okIdx < 0) return { ok: false, nights7, info: errIdx >= 0 ? 'zaxira xato bilan tugagan (muvaffaqiyatlisi yo‘q)' : 'logda muvaffaqiyatli zaxira yo‘q' };
    if (errIdx > okIdx) return { ok: false, at, nights7, info: 'oxirgi urinish xato bilan tugagan' };
    if (!at) return { ok: false, nights7, info: 'vaqtini aniqlab bo‘lmadi' };
    const ageH = (clock() - Date.parse(at)) / 3600e3;
    const miss = [/auth YO/.test(lines[okIdx]) ? 'auth' : '', /storage YO/.test(lines[okIdx]) ? 'storage' : '', /metama.lumoti YO/.test(lines[okIdx]) ? 'storage metama’lumoti' : '', /sirlar YO/.test(lines[okIdx]) ? 'sirlar' : ''].filter(Boolean);
    if (ageH > MAXH) return { ok: false, at, nights7, info: `${Math.floor(ageH)} soatdan beri yangi zaxira yo‘q` };
    return { ok: true, at, nights7, info: 'muvaffaqiyatli' + (miss.length ? ` (${miss.join(', ')} YO‘Q)` : '') };
  }

  const LIST = [
    ['db', 'Baza (PostgreSQL)', checkDb],
    ['gotrue', 'Kirish tizimi (GoTrue)', checkGotrue],
    ['eskiz', 'SMS (Eskiz)', checkEskiz],
    ['pay', 'To‘lov serveri', () => checkLocal(PAY)],
    ['ai', 'AI yordamchi', () => checkLocal(AI)],
    ['payments', 'Oxirgi onlayn to‘lov', checkPayments],
    ['backup', 'Oxirgi zaxira', checkBackup],
  ];
  async function run(key, name, fn) {
    const t0 = clock();
    let r;
    try { r = await withTimeout(fn(), T); } catch (e) { r = { ok: false, info: reason(e, T) }; }
    return Object.assign({ key, name }, r, { ms: Math.max(0, clock() - t0) });
  }

  // jwt -> { httpStatus, body }
  async function handle(jwt) {
    if (!jwt) return { httpStatus: 401, body: { ok: false, error: 'Avval tizimga kiring.' } };
    let v;
    try { v = await withTimeout(verifyUser(jwt), T); } catch (_) { v = { unavailable: true }; }
    if (v && v.unavailable) return { httpStatus: 503, body: { ok: false, error: 'Kirish tizimi (GoTrue) javob bermayapti — tizim holatini tekshirib bo‘lmadi.' } };
    if (!v || !v.uid) return { httpStatus: 401, body: { ok: false, error: 'Seans eskirgan — qayta kiring.' } };
    let u = null;
    try {
      const { data, error } = await withTimeout(sb.from('users').select('role,status').eq('id', String(v.uid)).limit(1), T);
      if (error) throw error;
      u = (data && data[0]) || null;
    } catch (_) { return { httpStatus: 503, body: { ok: false, error: 'Baza javob bermayapti — tizim holatini tekshirib bo‘lmadi.' } }; }
    if (!u || u.role !== 'director' || !isActive(u)) return { httpStatus: 403, body: { ok: false, error: 'Ruxsat yo‘q: tizim holatini faqat direktor ko‘radi.' } };
    const t0 = clock();
    const checks = await Promise.all(LIST.map(([k, n, f]) => run(k, n, f)));
    checks.unshift({ key: 'auth', name: 'Auth-server (kirish, SMS kod)', ok: true, info: 'ishlayapti', ms: 0 });
    return { httpStatus: 200, body: { ok: checks.every(c => c.ok !== false), at: new Date(clock()).toISOString(), ms: Math.max(0, clock() - t0), checks } };
  }
  // Kunlik hisobot (tg-daily.cjs) — JWT'siz, server o'zi: barcha tekshiruvlar (auth-server holati — tekshirilmaydi).
  async function runChecks() { return Promise.all(LIST.map(([k, n, f]) => run(k, n, f))); }
  return { handle, runChecks };
}

module.exports = { makeDeepHealth, httpGet, readTail, withTimeout, reason };
