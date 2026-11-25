'use strict';
/**
 * sync.cjs — platforma -> Google Sheets sinxronlash mantig'i (xizmatdan alohida — sinov uchun; sheets.test.cjs).
 * -------------------------------------------------------------------
 * Manba: baza triggerlari har o'zgarishni app.sheets_outbox ga yozadi (src = jadval, key = qator yoki o'quvchi kaliti) —
 *   o'zgarish bilan bir tranzaksiyada (migration/sheets-sync.sql). Har aylanishda:
 *   1) navbat o'qiladi (sheets_pull) va qaysi varaqlar o'zgargani aniqlanadi (SRC jadvali);
 *   2) «to'liq» varaqlar (o'quvchilar, qarzdorlik, hisobotlar …) — bazadan butun holat (sheets_tab); oxirgi yozilganidan farq
 *      qilmasa — yozilmaydi. «Kalitli» varaqlar (oylik to'lovlar, to'lovlar) — faqat o'zgargan qatorlar: varaqdagi A ustuni
 *      (kalit) o'qiladi, mavjud qator o'z joyida yangilanadi, yangisi oxiriga qo'shiladi, bazadan o'chgani varaqdan ham
 *      o'chiriladi; o'quvchi kartasi o'zgarsa — shu o'quvchining qatorlari (ism / sinf) yangilanadi;
 *   3) barcha varaqlar BIRGALIKDA yoziladi: A ustunlarini o'qish — bitta so'rov, panjarani kengaytirish — bitta, qiymatlar —
 *      bitta (juda katta bo'lsa bo'laklab), o'chirish / format — bitta, ortiqcha qatorlarni tozalash — bitta. Shunday qilib
 *      o'zgarishlar ko'p bo'lganda ham Google kvotasiga (daqiqasiga 60 so'rov) urilmaydi;
 *   4) faqat Google'ga muvaffaqiyatli yozilgandan KEYIN navbat yozuvlari o'chiriladi (sheets_ack, aynan o'qilgan id'lar) — xato
 *      bo'lsa (internet, kvota, ruxsat) hech narsa yo'qolmaydi; o'qilgandan keyin commit bo'lgan o'zgarish navbatda qoladi.
 *   TO'LIQ QAYTA YOZISH (barcha varaqlar, farq tekshirilmaydi): xizmat ishga tushganda, har kecha Toshkent vaqti bilan 03:00 dan
 *   keyin, har xatodan keyingi birinchi muvaffaqiyatli aylanishda va navbat juda katta bo'lsa. Boshida sheets_full_begin hozir
 *   ko'rinib turgan navbat yozuvlarini belgilaydi, oxirida sheets_full_end faqat ularni o'chiradi (to'liq yozish ularni qamraydi).
 *   Varaqlarni qo'lda tahrirlash tavsiya etilmaydi: platforma ularni qayta yozadi (varaq «ogohlantirish bilan» himoyalangan).
 *   Hisob-kitob uchun alohida varaq oching va formulalar bilan shu varaqlarga murojaat qiling (sheets/README.md).
 */
const crypto = require('crypto');

/** Varaqlar: id — bazadagi sheets_tab nomi; title — jadvaldagi varaq nomi; keyed — kalitli (A ustuni — qator kaliti). */
const TABS = [
  { id: 'students', title: "O'quvchilar" },
  { id: 'invoices', title: "Oylik to'lovlar", keyed: true },
  { id: 'payments', title: "To'lovlar", keyed: true },
  { id: 'debts', title: 'Qarzdorlik' },
  { id: 'monthly', title: 'Oylik hisobot' },
  { id: 'expenses', title: 'Xarajatlar' },
  { id: 'refunds', title: 'Qaytarishlar' },
];
/** Boshlang'ich oy (config.json sheets.fromMonth) qo'llanadigan varaqlar. */
const LEDGER = new Set(['invoices', 'payments', 'monthly', 'expenses', 'refunds']);

/**
 * Qaysi jadval o'zgarishi qaysi varaqlarga ta'sir qiladi:
 *   full — varaq to'liq (farq bo'lsa) yoziladi; keyed — shu varaqda navbat kaliti = qator kaliti; bystudent — navbat kaliti =
 *   o'quvchi kaliti (shu o'quvchining qatorlari yangilanadi).
 */
const SRC = {
  students: { full: ['students', 'debts', 'refunds'], bystudent: ['invoices', 'payments'] },
  student_private: { full: ['students', 'debts'] },
  student_credit: { full: ['students', 'debts'] },
  invoices: { keyed: ['invoices'], full: ['students', 'debts', 'monthly'] },
  payments: { keyed: ['payments'], full: ['monthly'] },
  refunds: { full: ['refunds', 'monthly'] },
  expenses: { full: ['expenses', 'monthly'] },
  cash_docs: { full: ['monthly'] },          // Kassa moduli bo'lsa: oylik hisobotdagi «boshqa kirim»
  cash_doc_lines: { full: ['monthly'] },
};

const KEYED_MAX = 400;                       // bir aylanishda shundan ko'p qator o'zgarsa — varaq to'liq yoziladi
const CHUNK = 2000;                          // bitta yozuv so'rovidagi qatorlar (so'rov hajmi bir necha yuz KB)
const CELL_MAX = 45000;                      // Google katak chegarasi 50 000 belgi
const MONEY = { type: 'NUMBER', pattern: '#,##0' };

const colName = (n) => { let s = ''; for (let x = n; x > 0; x = Math.floor((x - 1) / 26)) s = String.fromCharCode(65 + ((x - 1) % 26)) + s; return s; };
const q = (title) => "'" + String(title).replace(/'/g, "''") + "'";
const cellOf = (v) => {
  if (v === null || v === undefined) return '';
  if (typeof v === 'number') return Number.isFinite(v) ? v : '';
  if (typeof v === 'boolean') return v;
  const s = String(v);
  return s.length > CELL_MAX ? s.slice(0, CELL_MAX) + '…' : s;
};
const hashOf = (tab) => crypto.createHash('sha1').update(JSON.stringify([tab.header, tab.money, tab.rows])).digest('hex');

/** Toshkent kuni (YYYY-MM-DD) va soati (UTC+5, yozgi vaqt yo'q) — kechki to'liq qayta yozish uchun. */
function tashkent(nowMs) {
  const d = new Date(nowMs + 5 * 3600 * 1000);
  return { day: d.toISOString().slice(0, 10), hour: d.getUTCHours() };
}

function makeSync({ rpc, google, spreadsheetId, instance, fromMonth = null, log = () => {}, now = () => Date.now(), tabs = TABS, nightlyHour = 3 }) {
  if (!instance) throw new Error('makeSync: instance kerak');
  const st = {
    sheets: new Map(),        // varaq nomi -> { sheetId, rows, cols, protected } (panjara o'lchami)
    rows: new Map(),          // varaq nomi -> yozilgan qatorlar soni (sarlavha bilan)
    cols: new Map(),          // varaq nomi -> yozilgan ustunlar soni
    headers: new Map(),       // varaq nomi -> shu jarayonda yozilgan sarlavha (JSON)
    hashes: new Map(),        // varaq nomi -> oxirgi to'liq yozilgan ma'lumot izi (o'zgarmagan varaq qayta yozilmaydi)
    styled: new Set(),        // sarlavha bezagi / himoya qo'yilgan varaqlar (jarayon boshida bir marta)
    formatted: new Map(),     // varaq nomi -> pul formati qo'yilgan holat (sarlavha | qatorlar)
    meta: false, needFull: true, lastFull: null, lastOk: null, lastError: null, lastErrorAt: null,
  };

  async function call(name, args) {
    const { data, error } = await rpc(name, args || {});
    if (error) throw new Error(`baza ${name}: ${error.message || error.code || JSON.stringify(error)}`);
    return data;
  }
  const fetchTab = (t, extra) => call('sheets_tab', { p_tab: t.id, ...(LEDGER.has(t.id) && fromMonth ? { p_from: fromMonth } : {}), ...(extra || {}) })
    .then((tab) => { if (!tab || !Array.isArray(tab.header) || !Array.isArray(tab.rows)) throw new Error(`baza sheets_tab(${t.id}): varaq ma'lumoti yo'q`); return tab; });
  const ncolOf = (tab) => Math.max(tab.header.length, 1);

  // ---- Varaq tuzilmasi ----
  async function loadMeta() {
    const m = await google.spreadsheet(spreadsheetId);
    st.sheets.clear();
    for (const s of (m.sheets || [])) {
      const p = s.properties || {}, g = p.gridProperties || {};
      st.sheets.set(p.title, { sheetId: p.sheetId, rows: g.rowCount || 0, cols: g.columnCount || 0, protected: (s.protectedRanges || []).length > 0 });
    }
    st.meta = true;
  }

  /** Varaqlar mavjud va bezatilganmi (yo'qlari bitta so'rovda yaratiladi, bezak — bitta so'rovda). */
  async function prepare(items) {
    if (!st.meta) await loadMeta();
    const missing = items.filter((x) => !st.sheets.has(x.t.title));
    if (missing.length) {
      const r = await google.batchUpdate(spreadsheetId, missing.map((x) => ({ addSheet: { properties: { title: x.t.title, gridProperties: { rowCount: 1000, columnCount: Math.max(ncolOf(x.tab), 10), frozenRowCount: 1 } } } })));
      missing.forEach((x, i) => {
        const p = ((((r.replies || [])[i]) || {}).addSheet || {}).properties || {};
        if (p.sheetId === undefined || p.sheetId === null) throw new Error(`Google: «${x.t.title}» varag'i yaratilmadi (javobda sheetId yo'q)`);
        st.sheets.set(x.t.title, { sheetId: p.sheetId, rows: (p.gridProperties || {}).rowCount || 1000, cols: (p.gridProperties || {}).columnCount || Math.max(ncolOf(x.tab), 10), protected: false });
        st.styled.delete(x.t.title); st.formatted.delete(x.t.title); st.rows.delete(x.t.title); st.cols.delete(x.t.title); st.headers.delete(x.t.title); st.hashes.delete(x.t.title);
        log(`varaq yaratildi: ${x.t.title}`);
      });
    }
    const reqs = [], styledNow = [];
    for (const x of items) {
      if (st.styled.has(x.t.title)) continue;
      const sh = st.sheets.get(x.t.title);
      // Sarlavha: qalin, rangli, qotirilgan; varaq himoyasi — «ogohlantirish bilan» (tasodifiy tahrir oldidan so'raydi, bloklamaydi).
      reqs.push({ updateSheetProperties: { properties: { sheetId: sh.sheetId, gridProperties: { frozenRowCount: 1 } }, fields: 'gridProperties.frozenRowCount' } });
      reqs.push({ repeatCell: { range: { sheetId: sh.sheetId, startRowIndex: 0, endRowIndex: 1 }, cell: { userEnteredFormat: { textFormat: { bold: true }, backgroundColor: { red: 0.93, green: 0.95, blue: 0.98 } } }, fields: 'userEnteredFormat(textFormat,backgroundColor)' } });
      if (!sh.protected) reqs.push({ addProtectedRange: { protectedRange: { range: { sheetId: sh.sheetId }, description: 'Platforma avtomatik yozadi — qo\'lda o\'zgartirmang (keyingi yangilanishda qayta yoziladi)', warningOnly: true } } });
      styledNow.push(x.t.title);
    }
    if (reqs.length) {
      await google.batchUpdate(spreadsheetId, reqs);
      for (const t of styledNow) { st.styled.add(t); st.sheets.get(t).protected = true; }
    }
  }

  function grow(sh, needRows, needCols, reqs) {
    if (needRows > sh.rows) { const add = needRows - sh.rows + 500; reqs.push({ appendDimension: { sheetId: sh.sheetId, dimension: 'ROWS', length: add } }); sh.rows += add; }
    if (needCols > sh.cols) { const add = needCols - sh.cols; reqs.push({ appendDimension: { sheetId: sh.sheetId, dimension: 'COLUMNS', length: add } }); sh.cols += add; }
  }

  async function writeRanges(data) {
    // data: [{ range: "'Varaq'!A5", values }] — CHUNK qatordan kattasi bo'laklanadi; bitta so'rovda ~CHUNK qator.
    let batch = [], n = 0;
    const flush = async () => { if (batch.length) await google.valuesBatchUpdate(spreadsheetId, batch); batch = []; n = 0; };
    for (const d of data) {
      const m = /^(.*)!([A-Z]+)(\d+)$/.exec(d.range);
      for (let i = 0; i < d.values.length; i += CHUNK) {
        const part = d.values.slice(i, i + CHUNK);
        batch.push({ range: `${m[1]}!${m[2]}${Number(m[3]) + i}`, majorDimension: 'ROWS', values: part });
        n += part.length;
        if (n >= CHUNK) await flush();
      }
    }
    await flush();
  }

  // Pul ustunlari «1 500 000» formatida va ustun kengligi — varaq / sarlavha / panjara o'lchami o'zgarganda (jarayonda bir marta).
  function formatReqs(t, sh, tab, ncols, out) {
    const key = `${JSON.stringify(tab.header)}|${sh.rows}`;
    if (st.formatted.get(t.title) === key) return;
    for (const c of (Array.isArray(tab.money) ? tab.money : [])) {
      if (!Number.isInteger(c) || c < 0 || c >= ncols) continue;
      out.push({ repeatCell: { range: { sheetId: sh.sheetId, startRowIndex: 1, endRowIndex: sh.rows, startColumnIndex: c, endColumnIndex: c + 1 }, cell: { userEnteredFormat: { numberFormat: MONEY } }, fields: 'userEnteredFormat.numberFormat' } });
    }
    out.push({ autoResizeDimensions: { dimensions: { sheetId: sh.sheetId, dimension: 'COLUMNS', startIndex: 0, endIndex: ncols } } });
    st.formatted.set(t.title, key);
  }

  /**
   * Bir aylanishdagi barcha yozuvlar. full: [{ t, tab }] — butun varaq; keyed: [{ t, tab, keys }] — faqat tab.rows (keys — so'ralgan
   *   qator kalitlari, bazada yo'qlari varaqdan o'chiriladi). force — o'zgarmagan to'liq varaq ham yoziladi (to'liq qayta yozish).
   */
  async function apply(full, keyed, force) {
    full = full.filter((x) => force || st.hashes.get(x.t.title) !== hashOf(x.tab));
    if (!full.length && !keyed.length) return;
    await prepare([...full, ...keyed]);
    if (keyed.length) {
      const res = await google.valuesBatchGet(spreadsheetId, keyed.map((x) => `${q(x.t.title)}!A1:A`));
      keyed.forEach((x, i) => { x.vals = ((((res.valueRanges || [])[i]) || {}).values || []).map((r) => (r && r.length ? String(r[0]) : '')); });
      for (const x of keyed.filter((y) => !y.vals.length || y.vals[0] !== String(y.tab.header[0]))) {   // varaq bo'sh / sarlavha buzilgan
        keyed.splice(keyed.indexOf(x), 1);
        full.push({ t: x.t, tab: await fetchTab(x.t) });
      }
    }
    const pre = [], data = [], post = [], clears = [], after = [];
    for (const { t, tab } of full) {
      const sh = st.sheets.get(t.title), rows = tab.rows.map((r) => r.map(cellOf)), need = rows.length + 1, nc = ncolOf(tab);
      grow(sh, need, nc, pre);
      data.push({ range: `${q(t.title)}!A1`, values: [tab.header.map(cellOf), ...rows] });
      // Ortib qolgan qatorlar / ustunlar: oldingi yozuv ma'lum bo'lsa — faqat qisqarganda; noma'lum bo'lsa (ishga tushish) — butun qolgan panjara.
      const prev = st.rows.get(t.title), prevCols = st.cols.get(t.title);
      if (prev === undefined ? sh.rows > need : prev > need) clears.push(`${q(t.title)}!A${need + 1}:${colName(sh.cols)}${prev === undefined ? sh.rows : prev}`);
      if (prevCols === undefined ? sh.cols > nc : prevCols > nc) clears.push(`${q(t.title)}!${colName(nc + 1)}1:${colName(prevCols === undefined ? sh.cols : prevCols)}${need}`);
      formatReqs(t, sh, tab, nc, post);
      const h = hashOf(tab), hdr = JSON.stringify(tab.header);
      after.push(() => { st.rows.set(t.title, need); st.cols.set(t.title, nc); st.headers.set(t.title, hdr); st.hashes.set(t.title, h); });
    }
    for (const x of keyed) {
      const { t, tab, keys, vals } = x;
      const sh = st.sheets.get(t.title), nc = ncolOf(tab);
      const pos = new Map();
      vals.forEach((k, i) => { if (i > 0 && k !== '' && !pos.has(k)) pos.set(k, i + 1); });   // kalit -> 1 dan boshlanadigan qator raqami
      let end = vals.length;                                                                    // oxirgi band qator
      const found = new Set();
      for (const r of tab.rows) {
        const k = String(r[0]); found.add(k);
        const row = r.map(cellOf);
        if (pos.has(k)) data.push({ range: `${q(t.title)}!A${pos.get(k)}`, values: [row] });
        else { end += 1; pos.set(k, end); data.push({ range: `${q(t.title)}!A${end}`, values: [row] }); }
      }
      grow(sh, end, nc, pre);
      // Bazada yo'q (o'chirilgan yoki boshlang'ich oydan oldingi) qator kalitlari — varaqdan o'chiriladi (pastdan yuqoriga).
      const gone = [...new Set(keys.map(String))].filter((k) => !found.has(k) && pos.has(k) && pos.get(k) <= vals.length).map((k) => pos.get(k)).sort((a, b) => b - a);
      for (const r of gone) post.push({ deleteDimension: { range: { sheetId: sh.sheetId, dimension: 'ROWS', startIndex: r - 1, endIndex: r } } });
      sh.rows -= gone.length;
      formatReqs(t, sh, tab, nc, post);
      after.push(() => { st.rows.set(t.title, end - gone.length); });
    }
    if (pre.length) await google.batchUpdate(spreadsheetId, pre);
    if (data.length) await writeRanges(data);
    if (post.length) await google.batchUpdate(spreadsheetId, post);
    if (clears.length) await google.valuesBatchClear(spreadsheetId, clears);
    after.forEach((f) => f());
  }

  /** Barcha varaqlarni to'liq qayta yozish (navbat belgisisiz — cycle() ichida sheets_full_begin / end bilan chaqiriladi). */
  async function fullSync() {
    st.meta = false; st.rows.clear(); st.cols.clear(); st.headers.clear(); st.hashes.clear();
    await loadMeta();
    const full = [];
    for (const t of tabs) full.push({ t, tab: await fetchTab(t) });
    await apply(full, [], true);
    st.lastFull = tashkent(now()).day;
  }

  const ok = () => { st.lastOk = now(); st.lastError = null; st.lastErrorAt = null; };

  /** Bitta aylanish. Qaytaradi: qayta ishlangan navbat yozuvlari soni. */
  async function cycle({ limit = 5000 } = {}) {
    const day = tashkent(now());
    const nightly = !!st.lastFull && st.lastFull !== day.day && day.hour >= nightlyHour;
    if (st.needFull || !st.lastFull || nightly) {
      const why = !st.lastFull ? 'ishga tushish' : (nightly ? 'kechki' : 'tiklanish yoki katta navbat');
      await call('sheets_full_begin', { p_instance: instance });
      await fullSync();
      const n = Number(await call('sheets_full_end', { p_instance: instance })) || 0;
      st.needFull = false; ok();
      log(`to'liq yozildi (${why}): ${tabs.length} ta varaq; navbatdan ${n} ta yozuv qamrab olindi`);
      return n;
    }
    const items = (await call('sheets_pull', { p_instance: instance, p_limit: limit })) || [];
    if (!items.length) return 0;
    if (items.length >= limit) { st.needFull = true; return cycle({ limit }); }   // juda katta navbat — bitta to'liq yozish arzonroq
    const fullIds = new Set(), keyedIds = new Map();
    const add = (id, kind, key) => {
      if (key === null || key === undefined || key === '') return;
      if (!keyedIds.has(id)) keyedIds.set(id, { keys: new Set(), studs: new Set() });
      keyedIds.get(id)[kind].add(String(key));
    };
    for (const it of items) {
      const m = SRC[it.src]; if (!m) continue;                                       // noma'lum manba — e'tiborsiz (o'chiriladi)
      (m.full || []).forEach((id) => fullIds.add(id));
      (m.keyed || []).forEach((id) => add(id, 'keys', it.key));
      (m.bystudent || []).forEach((id) => add(id, 'studs', it.key));
    }
    const full = [], keyed = [];
    for (const t of tabs) {
      const k = keyedIds.get(t.id);
      if (fullIds.has(t.id) || (k && k.keys.size + k.studs.size > KEYED_MAX)) { full.push({ t, tab: await fetchTab(t) }); continue; }
      if (!k) continue;
      const tab = await fetchTab(t, { p_keys: [...k.keys], p_students: [...k.studs] });
      if (tab.rows.length > KEYED_MAX || st.headers.get(t.title) !== JSON.stringify(tab.header)) full.push({ t, tab: await fetchTab(t) });
      else keyed.push({ t, tab, keys: [...k.keys] });
    }
    await apply(full, keyed, false);
    await call('sheets_ack', { p_instance: instance, p_ids: items.map((x) => x.id) });
    ok();
    return items.length;
  }

  function status() {
    const tabsInfo = {}; for (const [k, v] of st.rows) tabsInfo[k] = Math.max(0, v - 1);
    return {
      instance, fromMonth: fromMonth || null,
      lastOk: st.lastOk ? new Date(st.lastOk).toISOString() : null, lastFull: st.lastFull,
      lastError: st.lastError, lastErrorAt: st.lastErrorAt ? new Date(st.lastErrorAt).toISOString() : null, tabs: tabsInfo,
    };
  }
  /** Xato: keyingi muvaffaqiyatli aylanish — to'liq qayta yozish (oraliqda nima yozilgani noma'lum). */
  function failed(msg) { st.lastError = String(msg).slice(0, 500); st.lastErrorAt = now(); st.meta = false; st.needFull = true; }

  return { cycle, fullSync, status, failed, _st: st };
}

module.exports = { makeSync, TABS, SRC, LEDGER, KEYED_MAX, colName, tashkent, cellOf };
