'use strict';
/**
 * google.cjs — Google Sheets API v4 uchun kichik mijoz (tashqi paketsiz).
 * -------------------------------------------------------------------
 * Kirish: Google Cloud XIZMAT HISOBI (service account) kaliti — JSON fayl (client_email, private_key). Kalit bilan JWT (RS256)
 *   imzolanadi va oauth2 token olinadi (1 soat; tugashidan 1 daqiqa oldin yangilanadi). Kalit faqat serverda turadi
 *   (sheets/google-key.json, gitignore) — repoga va chatga yozilmaydi.
 * Qayta urinish: 429 (kvota) va 5xx / tarmoq xatosida — 1, 2, 4, … 32 s kutib (Retry-After bo'lsa — shuncha), 6 martagacha;
 *   401 — token yangilanib bir marta qayta. Boshqa xato (403 — jadval xizmat hisobiga ulashilmagan, 404 — noto'g'ri ID, 400) —
 *   darhol xato (tushunarli matn bilan).
 * Kvota: Google bir foydalanuvchiga daqiqasiga 60 ta so'rov beradi — mijoz o'zi daqiqasiga ko'pi bilan `perMinute` (standart 50)
 *   so'rov yuboradi, ortig'ini kutadi.
 */
const crypto = require('crypto');

const b64url = (b) => Buffer.from(b).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

class GoogleError extends Error {
  constructor(what, status, body) {
    const msg = (body && body.error && (body.error.message || body.error_description || body.error)) || '';
    super(`Google ${what}: HTTP ${status}${msg ? ' — ' + String(typeof msg === 'string' ? msg : JSON.stringify(msg)).slice(0, 300) : ''}`);
    this.status = status; this.body = body;
  }
}

/** Xato matnini Direktor / administrator uchun tushunarli qiladi (log va holat uchun). */
function explain(e) {
  const s = e && e.status;
  if (s === 403) return 'Jadvalga ruxsat yo\'q: jadvalni xizmat hisobi emailiga «Muharrir» sifatida ulashing (sheets/README.md, 4-qadam). ' + e.message;
  if (s === 404) return 'Jadval topilmadi: config.json dagi spreadsheetId ni tekshiring. ' + e.message;
  if (s === 400 && /invalid_grant|invalid_client|Invalid JWT/i.test(e.message)) return 'Xizmat hisobi kaliti noto\'g\'ri yoki o\'chirilgan (google-key.json). ' + e.message;
  return (e && e.message) || String(e);
}

function makeGoogle(opt) {
  const key = opt.key || {};
  if (!key.client_email || !key.private_key) throw new Error('Google kaliti noto\'g\'ri: client_email / private_key yo\'q (google-key.json)');
  const tokenUrl = opt.tokenUrl || key.token_uri || 'https://oauth2.googleapis.com/token';
  const api = String(opt.apiBase || 'https://sheets.googleapis.com/v4').replace(/\/+$/, '');
  const fetchFn = opt.fetch || globalThis.fetch;
  if (typeof fetchFn !== 'function') throw new Error('fetch yo\'q: Node 18+ kerak');
  const sleep = opt.sleep || ((ms) => new Promise((r) => setTimeout(r, ms)));
  const now = opt.now || (() => Date.now());
  const perMinute = Math.max(1, Number(opt.perMinute) || 50);
  const maxTries = Math.max(1, Number(opt.maxTries) || 6);
  const timeoutMs = Math.max(1000, Number(opt.timeoutMs) || 60000);
  let tok = null, tokExp = 0;
  const sent = [];   // so'nggi 60 s dagi so'rovlar vaqti (kvota)

  async function quota() {
    for (;;) {
      const t = now();
      while (sent.length && t - sent[0] >= 60000) sent.shift();
      if (sent.length < perMinute) { sent.push(t); return; }
      await sleep(60000 - (t - sent[0]) + 50);
    }
  }

  async function fetchT(url, init) {
    // Har so'rovga vaqt chegarasi (osilib qolgan ulanish xizmatni to'xtatib qo'ymasin).
    if (typeof AbortController !== 'function') return fetchFn(url, init);
    const ac = new AbortController(); const tm = setTimeout(() => ac.abort(), timeoutMs);
    try { return await fetchFn(url, { ...init, signal: ac.signal }); } finally { clearTimeout(tm); }
  }

  async function token(force) {
    if (!force && tok && now() < tokExp - 60000) return tok;
    const iat = Math.floor(now() / 1000);
    const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claim = b64url(JSON.stringify({ iss: key.client_email, scope: 'https://www.googleapis.com/auth/spreadsheets', aud: tokenUrl, iat, exp: iat + 3600 }));
    const sig = crypto.createSign('RSA-SHA256').update(head + '.' + claim).sign(key.private_key);
    const body = new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: head + '.' + claim + '.' + b64url(sig) }).toString();
    const res = await fetchT(tokenUrl, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body });
    const j = await res.json().catch(() => ({}));
    if (!res.ok || !j.access_token) throw new GoogleError('token', res.status, j);
    tok = j.access_token; tokExp = now() + (Number(j.expires_in) || 3600) * 1000;
    return tok;
  }

  async function call(method, path, body) {
    let refreshed = false;
    for (let attempt = 1; ; attempt++) {
      let res, j;
      try {
        const t = await token(false);
        await quota();
        res = await fetchT(api + path, {
          method,
          headers: { authorization: 'Bearer ' + t, ...(body !== undefined ? { 'content-type': 'application/json' } : {}) },
          ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
        });
        j = await res.json().catch(() => ({}));
      } catch (e) {
        if (e instanceof GoogleError && e.status && e.status < 500 && e.status !== 429) throw e;   // token: kalit xatosi — qayta urinish foydasiz
        if (attempt >= maxTries) throw e;
        await sleep(Math.min(32000, 1000 * 2 ** (attempt - 1)));
        continue;
      }
      if (res.ok) return j;
      if (res.status === 401 && !refreshed) { refreshed = true; tok = null; continue; }
      if ((res.status === 429 || res.status >= 500) && attempt < maxTries) {
        const ra = Number(res.headers && res.headers.get && res.headers.get('retry-after'));
        await sleep(ra > 0 ? Math.min(60000, ra * 1000) : Math.min(32000, 1000 * 2 ** (attempt - 1)));
        continue;
      }
      throw new GoogleError(method + ' ' + path.split('?')[0], res.status, j);
    }
  }

  const enc = encodeURIComponent;
  return {
    /** Jadval va varaqlar haqida (fields — kerakli maydonlar). */
    spreadsheet: (id) => call('GET', `/spreadsheets/${enc(id)}?fields=${enc('spreadsheetId,properties.title,sheets(properties(sheetId,title,index,gridProperties(rowCount,columnCount)),protectedRanges(protectedRangeId,range(sheetId)))')}`),
    batchUpdate: (id, requests) => call('POST', `/spreadsheets/${enc(id)}:batchUpdate`, { requests }),
    /** Bir nechta oraliqqa qiymat yozish — RAW: matn formula / son / sana bo'lib talqin qilinmaydi («+998 …», «=…» — aynan matn). */
    valuesBatchUpdate: (id, data) => call('POST', `/spreadsheets/${enc(id)}/values:batchUpdate`, { valueInputOption: 'RAW', data }),
    valuesGet: (id, range) => call('GET', `/spreadsheets/${enc(id)}/values/${enc(range)}?majorDimension=ROWS&valueRenderOption=UNFORMATTED_VALUE`),
    /** Bir nechta oraliqni bitta so'rovda o'qish (javob — so'ralgan tartibda valueRanges). */
    valuesBatchGet: (id, ranges) => call('GET', `/spreadsheets/${enc(id)}/values:batchGet?${ranges.map((r) => 'ranges=' + enc(r)).join('&')}&majorDimension=ROWS&valueRenderOption=UNFORMATTED_VALUE`),
    valuesBatchClear: (id, ranges) => call('POST', `/spreadsheets/${enc(id)}/values:batchClear`, { ranges }),
    _token: token,
  };
}

module.exports = { makeGoogle, GoogleError, explain };
