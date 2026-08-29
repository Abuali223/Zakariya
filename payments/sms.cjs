/**
 * sms.cjs — Eskiz.uz SMS jo'natish moduli (SERVER tomoni, tashqi paketsiz — https).
 * -------------------------------------------------------------------
 * Ikki rejim:
 *   1) email + parol  -> avtomatik token oladi (tavsiya — token eskirsa o'zi yangilaydi)
 *   2) token          -> Eskiz panelidan olingan tayyor tokenni to'g'ridan-to'g'ri ishlatadi
 *
 * Eskiz API: https://notify.eskiz.uz/api
 *   POST /api/auth/login          (email,password)          -> { data:{ token } }
 *   POST /api/message/sms/send    (mobile_phone,message,from) -> { id, status }
 *
 * ⚠️ Eskiz SMS matnini OLDINDAN moderatsiyadan o'tkazishни talab qiladi —
 *    yuborilayotgan matn tasdiqlangan shablonga mos bo'lishi kerak.
 * ⚠️ Maxfiy: eskizEmail/eskizPassword/token faqat config.json'da (serverda).
 */
const https = require('https');

function httpsRequest(opts, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(opts, res => {
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => { let j = null; try { j = JSON.parse(d); } catch (_) {} resolve({ status: res.statusCode, json: j, raw: d }); });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

// multipart/form-data qurish (Eskiz /auth/login shu formatni kutadi).
function multipart(fields) {
  const boundary = '----iqror' + Date.now().toString(36);
  let s = '';
  for (const k in fields) s += `--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${fields[k]}\r\n`;
  s += `--${boundary}--\r\n`;
  return { boundary, body: Buffer.from(s, 'utf8') };
}

// Telefonni Eskiz formatiga keltiradi: 998XXXXXXXXX (12 raqam, + va bo'shliqsiz).
function normMobile(p) {
  let d = String(p || '').replace(/\D/g, '');
  if (d.length === 9) d = '998' + d;          // XXXXXXXXX -> 998XXXXXXXXX
  else if (d.length > 12) d = d.slice(-12);   // ortiqcha old raqamlarni kesamiz
  return d;
}

function makeEskiz(cfg) {
  cfg = cfg || {};
  const HOST = cfg.host || 'notify.eskiz.uz';
  const from = cfg.from || '4546';            // jo'natuvchi (nickname) — Eskiz'da tasdiqlangan bo'lishi kerak
  let token = null;

  async function login() {
    // Faqat token berilgan bo'lsa — o'shani ishlatamiz (avtomatik yangilanmaydi).
    if (!cfg.eskizEmail && !cfg.email && cfg.token) { token = cfg.token; return token; }
    const { boundary, body } = multipart({ email: cfg.eskizEmail || cfg.email || '', password: cfg.eskizPassword || cfg.password || '' });
    const r = await httpsRequest({ host: HOST, path: '/api/auth/login', method: 'POST',
      headers: { 'Content-Type': 'multipart/form-data; boundary=' + boundary, 'Content-Length': body.length } }, body);
    const t = r.json && r.json.data && r.json.data.token;
    if (!t) throw new Error('Eskiz login muvaffaqiyatsiz: ' + (r.raw || ('HTTP ' + r.status)));
    token = t; return token;
  }
  async function ensureToken() { if (!token) { if (cfg.token) token = cfg.token; else await login(); } return token; }

  // Bitta SMS jo'natadi. Qaytaradi: { ok:true, id, status } | { ok:false, error }
  async function send(phone, message) {
    const mobile = normMobile(phone);
    if (mobile.length !== 12) return { ok: false, error: 'bad_phone:' + mobile };
    await ensureToken();
    const post = () => {
      const body = new URLSearchParams({ mobile_phone: mobile, message: String(message || ''), from }).toString();
      return httpsRequest({ host: HOST, path: '/api/message/sms/send', method: 'POST',
        headers: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body) } }, body);
    };
    let r = await post();
    if (r.status === 401 && (cfg.eskizEmail || cfg.email)) { await login(); r = await post(); }   // token eskirsa — qayta kirib urinamiz
    const j = r.json || {};
    if (r.status >= 200 && r.status < 300 && (j.id || j.status === 'waiting' || j.status === 'success'))
      return { ok: true, id: String(j.id || ''), status: j.status || 'sent' };
    return { ok: false, error: (j.message || ('http_' + r.status)), raw: r.raw };
  }

  return { login, send, normMobile };
}

module.exports = { makeEskiz, normMobile };
