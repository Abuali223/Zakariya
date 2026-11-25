'use strict';
/**
 * fake-google.cjs — Google Sheets API v4 va OAuth token nuqtasining XOTIRADAGI o'xshashi. FAQAT sinovlar uchun
 *   (sheets.test.cjs; lokal uchdan-uchga sinovda HTTP server sifatida). Ishlab chiqarishda ishlatilmaydi.
 * -------------------------------------------------------------------
 * Qo'llab-quvvatlanadi (sheets/google.cjs ishlatadiganlari): GET jadval (varaqlar, himoyalar), GET values:batchGet, POST :batchUpdate (addSheet,
 *   updateSheetProperties, repeatCell, addProtectedRange, appendDimension, deleteDimension, autoResizeDimensions — atomar:
 *   xato bo'lsa hech biri qo'llanmaydi), POST values:batchUpdate (RAW; panjaradan tashqari — 400), GET values/{oraliq}
 *   (oxiridagi bo'sh kataklar / qatorlar qaytmaydi), POST values:batchClear, POST token (JWT RS256 imzosi ochiq kalit bilan
 *   tekshiriladi, token 1 soat). Xato kiritish: failNext(status, { count, match, retryAfter }).
 */
const crypto = require('crypto');
const http = require('http');

const colIdx = (s) => { let n = 0; for (const ch of s) n = n * 26 + (ch.charCodeAt(0) - 64); return n - 1; };
class HttpErr extends Error { constructor(status, message) { super(message); this.status = status; } }

function parseA1(range) {
  const m = /^(?:'((?:[^']|'')*)'|([^!']+))!([A-Z]*)(\d*)(?::([A-Z]*)(\d*))?$/.exec(String(range));
  if (!m) throw new HttpErr(400, `Unable to parse range: ${range}`);
  const title = m[1] !== undefined ? m[1].replace(/''/g, "'") : m[2];
  const hasEnd = m[5] !== undefined;
  const c1 = m[3] ? colIdx(m[3]) : 0, r1 = m[4] ? Number(m[4]) - 1 : 0;
  const c2 = hasEnd ? (m[5] ? colIdx(m[5]) : Infinity) : c1;
  const r2 = hasEnd ? (m[6] ? Number(m[6]) - 1 : Infinity) : r1;
  return { title, r1, c1, r2, c2 };
}

function makeFakeSheets({ id = 'SINOV-JADVAL', publicKey = null, clientEmail = 'sinov@sinov.iam.gserviceaccount.test', now = () => Date.now() } = {}) {
  const st = { id, sheets: [], nextSheetId: 100, nextProt: 1, tokens: new Map(), tokenN: 0, denied: false, calls: [], fails: [] };
  const byTitle = (t) => st.sheets.find((s) => s.title === t);
  const byId = (sid) => st.sheets.find((s) => s.sheetId === sid);
  const need = (sid) => { const s = byId(sid); if (!s) throw new HttpErr(400, `No grid with id: ${sid}`); return s; };

  function addSheet(title, rows = 1000, cols = 26) {
    if (byTitle(title)) throw new HttpErr(400, `A sheet with the name "${title}" already exists. Please enter another name.`);
    const s = { sheetId: st.nextSheetId++, title, index: st.sheets.length, rowCount: rows, columnCount: cols, frozen: 0, cells: [], protected: [], formats: [], resized: 0 };
    st.sheets.push(s);
    return s;
  }
  const props = (s) => ({ sheetId: s.sheetId, title: s.title, index: s.index, gridProperties: { rowCount: s.rowCount, columnCount: s.columnCount, frozenRowCount: s.frozen } });

  function applyRequest(r) {
    const k = Object.keys(r)[0], v = r[k];
    switch (k) {
      case 'addSheet': {
        const p = v.properties || {}, g = p.gridProperties || {};
        const s = addSheet(p.title, g.rowCount || 1000, g.columnCount || 26);
        s.frozen = g.frozenRowCount || 0;
        return { addSheet: { properties: props(s) } };
      }
      case 'updateSheetProperties': { const s = need(v.properties.sheetId); if (v.properties.gridProperties) s.frozen = v.properties.gridProperties.frozenRowCount || 0; return {}; }
      case 'repeatCell': { need(v.range.sheetId).formats.push({ range: v.range, cell: v.cell, fields: v.fields }); return {}; }
      case 'addProtectedRange': {
        const s = need(v.protectedRange.range.sheetId);
        const pr = { protectedRangeId: st.nextProt++, ...v.protectedRange };
        s.protected.push(pr);
        return { addProtectedRange: { protectedRange: pr } };
      }
      case 'appendDimension': {
        const s = need(v.sheetId);
        if (!(v.length > 0)) throw new HttpErr(400, 'length must be > 0');
        if (v.dimension === 'ROWS') s.rowCount += v.length; else if (v.dimension === 'COLUMNS') s.columnCount += v.length; else throw new HttpErr(400, 'bad dimension');
        return {};
      }
      case 'deleteDimension': {
        const g = v.range, s = need(g.sheetId);
        if (g.dimension !== 'ROWS') throw new HttpErr(400, 'only ROWS in fake');
        if (!(g.startIndex >= 0 && g.endIndex > g.startIndex && g.endIndex <= s.rowCount)) throw new HttpErr(400, `Invalid deleteDimension range ${g.startIndex}-${g.endIndex}`);
        if (s.rowCount - (g.endIndex - g.startIndex) < 1) throw new HttpErr(400, 'You can\'t delete all the rows on the sheet.');
        s.cells.splice(g.startIndex, g.endIndex - g.startIndex);
        s.rowCount -= g.endIndex - g.startIndex;
        return {};
      }
      case 'autoResizeDimensions': { need(v.dimensions.sheetId).resized += 1; return {}; }
      default: throw new HttpErr(400, `Unknown request ${k}`);
    }
  }

  const snapshot = () => JSON.stringify({ sheets: st.sheets, nextSheetId: st.nextSheetId, nextProt: st.nextProt });
  const restore = (j) => { const o = JSON.parse(j); st.sheets = o.sheets; st.nextSheetId = o.nextSheetId; st.nextProt = o.nextProt; };

  function writeValues(range, values) {
    const a = parseA1(range), s = byTitle(a.title);
    if (!s) throw new HttpErr(400, `Unable to parse range: ${range}`);
    values.forEach((row, i) => {
      const r = a.r1 + i;
      if (r >= s.rowCount) throw new HttpErr(400, `Range (${range}) exceeds grid limits. Max rows: ${s.rowCount}`);
      row.forEach((val, j) => {
        const c = a.c1 + j;
        if (c >= s.columnCount) throw new HttpErr(400, `Range (${range}) exceeds grid limits. Max columns: ${s.columnCount}`);
        if (!s.cells[r]) s.cells[r] = [];
        if (val !== null && typeof val === 'object') throw new HttpErr(400, 'Invalid value');
        s.cells[r][c] = val === '' ? undefined : val;
      });
    });
    return values.reduce((n, row) => n + row.length, 0);
  }
  function readValues(range) {
    const a = parseA1(range), s = byTitle(a.title);
    if (!s) throw new HttpErr(400, `Unable to parse range: ${range}`);
    const out = [];
    for (let r = a.r1; r <= Math.min(a.r2, s.rowCount - 1); r++) {
      const row = [];
      for (let c = a.c1; c <= Math.min(a.c2, s.columnCount - 1); c++) { const v = (s.cells[r] || [])[c]; row.push(v === undefined || v === null ? '' : v); }
      while (row.length && row[row.length - 1] === '') row.pop();
      out.push(row);
    }
    while (out.length && !out[out.length - 1].length) out.pop();
    return out;
  }
  function clearValues(range) {
    const a = parseA1(range), s = byTitle(a.title);
    if (!s) throw new HttpErr(400, `Unable to parse range: ${range}`);
    for (let r = a.r1; r <= Math.min(a.r2, s.rowCount - 1); r++) {
      if (!s.cells[r]) continue;
      for (let c = a.c1; c <= Math.min(a.c2, s.columnCount - 1); c++) s.cells[r][c] = undefined;
    }
  }

  function b64urlDecode(x) { return Buffer.from(x.replace(/-/g, '+').replace(/_/g, '/'), 'base64'); }
  function token(body, url) {
    const p = new URLSearchParams(body || '');
    if (p.get('grant_type') !== 'urn:ietf:params:oauth:grant-type:jwt-bearer') throw new HttpErr(400, 'unsupported_grant_type');
    const parts = String(p.get('assertion') || '').split('.');
    if (parts.length !== 3) throw new HttpErr(400, 'invalid_grant: Invalid JWT');
    const head = JSON.parse(b64urlDecode(parts[0]).toString()), claim = JSON.parse(b64urlDecode(parts[1]).toString());
    if (head.alg !== 'RS256') throw new HttpErr(400, 'invalid_grant: alg');
    if (publicKey && !crypto.createVerify('RSA-SHA256').update(parts[0] + '.' + parts[1]).verify(publicKey, b64urlDecode(parts[2]))) throw new HttpErr(400, 'invalid_grant: Invalid JWT Signature.');
    if (claim.iss !== clientEmail) throw new HttpErr(400, 'invalid_client');
    if (!/\/auth\/spreadsheets(\s|$)/.test(claim.scope || '')) throw new HttpErr(400, 'invalid_scope');
    if (claim.aud !== url) throw new HttpErr(400, 'invalid_grant: aud');
    if (!(claim.exp > claim.iat) || claim.exp - claim.iat > 3600) throw new HttpErr(400, 'invalid_grant: exp');
    const t = 'tok-' + (++st.tokenN);
    st.tokens.set(t, now() + 3600 * 1000);
    return { access_token: t, expires_in: 3600, token_type: 'Bearer', _claim: claim };
  }

  /** So'rovni bajaradi: { status, body, headers }. */
  function handle(method, urlStr, bodyText, headers = {}) {
    const u = new URL(urlStr);
    st.calls.push({ method, path: decodeURIComponent(u.pathname), at: now() });
    const f = st.fails.find((x) => x.count > 0 && (!x.match || x.match.test(method + ' ' + decodeURIComponent(u.pathname))));
    if (f) { f.count -= 1; return { status: f.status, body: { error: { code: f.status, message: f.message || `fake ${f.status}`, status: 'FAKE' } }, headers: f.retryAfter ? { 'retry-after': String(f.retryAfter) } : {} }; }
    try {
      if (method === 'POST' && /\/token$/.test(u.pathname)) return { status: 200, body: token(bodyText, u.origin + u.pathname) };
      const auth = headers.authorization || headers.Authorization || '';
      const tk = auth.replace(/^Bearer /, '');
      if (!st.tokens.has(tk) || st.tokens.get(tk) <= now()) throw new HttpErr(401, 'Request had invalid authentication credentials.');
      const m = /\/spreadsheets\/([^/:]+)(.*)$/.exec(u.pathname);
      if (!m) throw new HttpErr(404, 'Not found');
      if (decodeURIComponent(m[1]) !== st.id) throw new HttpErr(404, 'Requested entity was not found.');
      if (st.denied) throw new HttpErr(403, 'The caller does not have permission');
      const rest = m[2], body = bodyText ? JSON.parse(bodyText) : {};
      if (method === 'GET' && rest === '') return { status: 200, body: { spreadsheetId: st.id, properties: { title: 'Sinov jadvali' }, sheets: st.sheets.map((s) => ({ properties: props(s), ...(s.protected.length ? { protectedRanges: s.protected.map((p) => ({ protectedRangeId: p.protectedRangeId, range: { sheetId: s.sheetId } })) } : {}) })) } };
      if (method === 'POST' && rest === ':batchUpdate') {
        const snap = snapshot();
        try { return { status: 200, body: { spreadsheetId: st.id, replies: (body.requests || []).map(applyRequest) } }; } catch (e) { restore(snap); throw e; }
      }
      if (method === 'POST' && rest === '/values:batchUpdate') {
        if (body.valueInputOption !== 'RAW') throw new HttpErr(400, 'fake: faqat RAW');
        const snap = snapshot();
        try { let n = 0; for (const d of body.data || []) n += writeValues(d.range, d.values || []); return { status: 200, body: { spreadsheetId: st.id, totalUpdatedCells: n } }; } catch (e) { restore(snap); throw e; }
      }
      if (method === 'POST' && rest === '/values:batchClear') { for (const r of body.ranges || []) clearValues(r); return { status: 200, body: { spreadsheetId: st.id, clearedRanges: body.ranges || [] } }; }
      if (method === 'GET' && rest === '/values:batchGet') {
        const ranges = u.searchParams.getAll('ranges');
        return { status: 200, body: { spreadsheetId: st.id, valueRanges: ranges.map((range) => { const values = readValues(range); return { range, majorDimension: 'ROWS', ...(values.length ? { values } : {}) }; }) } };
      }
      const g = /^\/values\/(.+)$/.exec(rest);
      if (method === 'GET' && g) { const range = decodeURIComponent(g[1]); const values = readValues(range); return { status: 200, body: { range, majorDimension: 'ROWS', ...(values.length ? { values } : {}) } }; }
      throw new HttpErr(404, `fake: ${method} ${rest}`);
    } catch (e) {
      const status = e.status || 500;
      if (/\/token$/.test(u.pathname) && status === 400) return { status, body: { error: String(e.message).split(':')[0], error_description: e.message } };
      return { status, body: { error: { code: status, message: e.message, status: 'FAKE' } } };
    }
  }

  /** google.cjs uchun fetch o'rnini bosuvchi (tarmoqsiz). */
  const fetch = async (url, init = {}) => {
    const h = {}; for (const [k, v] of Object.entries(init.headers || {})) h[k.toLowerCase()] = v;
    const r = handle(init.method || 'GET', String(url), init.body, h);
    return { ok: r.status >= 200 && r.status < 300, status: r.status, headers: { get: (n) => (r.headers || {})[String(n).toLowerCase()] ?? null }, json: async () => JSON.parse(JSON.stringify(r.body)) };
  };

  /** Lokal HTTP server (uchdan-uchga sinov uchun): 127.0.0.1 da. */
  function serve(port = 0) {
    const srv = http.createServer((req, res) => {
      let b = ''; req.on('data', (c) => { b += c; });
      req.on('end', () => {
        const r = handle(req.method, `http://${req.headers.host}${req.url}`, b, req.headers);
        res.writeHead(r.status, { 'content-type': 'application/json', ...(r.headers || {}) });
        res.end(JSON.stringify(r.body));
      });
    });
    return new Promise((ok) => srv.listen(port, '127.0.0.1', () => ok(srv)));
  }

  return {
    state: st, handle, fetch, serve, addSheet,
    /** varaq qiymatlari (2 o'lchamli massiv, bo'sh — '') */
    grid: (title) => { const s = byTitle(title); return s ? readValues(`'${title.replace(/'/g, "''")}'!A1:${'ZZ'}${s.rowCount}`) : null; },
    sheet: byTitle,
    failNext: (status, { count = 1, match = null, retryAfter = null, message = null } = {}) => { st.fails.push({ status, count, match, retryAfter, message }); },
    deleteSheet: (title) => { st.sheets = st.sheets.filter((s) => s.title !== title); st.sheets.forEach((s, i) => { s.index = i; }); },
  };
}

module.exports = { makeFakeSheets, parseA1 };
