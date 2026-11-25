// =====================================================================
// sheets.test.cjs — Google Sheets xizmati sinovi (tarmoqsiz): google.cjs (JWT, token, qayta urinish, kvota, xato matnlari),
//   sync.cjs (to'liq / kalitli yozish, o'quvchi bo'yicha yangilash, o'chirish, qo'lda tartiblangan varaq, xatodan tiklanish,
//   kechki to'liq yozish, katta navbat, boshlang'ich oy, format), index.cjs readConfig.
//   node sheets/sheets.test.cjs        (yoki sheets/ ichida: node sheets.test.cjs)
//   Google — fake-google.cjs (xotiradagi o'xshash), baza — soxta RPC. Kalit — sinov paytida yaratiladi (repoda kalit yo'q).
// =====================================================================
'use strict';
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { makeGoogle, GoogleError, explain } = require('./google.cjs');
const { makeSync, TABS, KEYED_MAX, colName, tashkent, cellOf } = require('./sync.cjs');
const { makeFakeSheets, parseA1 } = require('./fake-google.cjs');

let pass = 0, fail = 0;
const ok = (n, c, x) => { if (c) pass++; else { fail++; console.log('  ✗ FAIL:', n, x !== undefined ? String(typeof x === 'string' ? x : JSON.stringify(x)).slice(0, 3000) : ''); } };
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048, publicKeyEncoding: { type: 'spki', format: 'pem' }, privateKeyEncoding: { type: 'pkcs8', format: 'pem' } });
const KEY = { client_email: 'sinov@sinov.iam.gserviceaccount.test', private_key: privateKey };
const TOKEN_URL = 'https://oauth2.sinov.test/token', API = 'https://sheets.sinov.test/v4';

function clock(start = Date.parse('2026-11-15T07:00:00Z')) {   // 12:00 Toshkent
  let t = start; const sleeps = [];
  return { now: () => t, set: (x) => { t = x; }, sleep: async (ms) => { sleeps.push(ms); t += ms; }, sleeps };
}

// ---- soxta baza (sheets_* RPC'lari) ----
function fakeDb() {
  const T = {
    students: { header: ["O'quvchi ID", 'F.I.Sh.', 'Sinf', 'Joriy qarz'], money: [3], rows: [['IQ-1', 'Sinov Bir', '5-A', 600], ['IQ-2', 'Sinov Ikki', '5-B', 1000]] },
    invoices: { header: ['Kalit (ID)', 'Oy', "O'quvchi ID", 'F.I.Sh.', 'Hisoblangan', 'Qarz'], money: [4, 5], sk: 2,
      rows: [['inv1', '2026-10', 'IQ-1', 'Sinov Bir', 1000, 0], ['inv2', '2026-11', 'IQ-1', 'Sinov Bir', 1000, 600], ['inv3', '2026-11', 'IQ-2', 'Sinov Ikki', 1000, 1000]] },
    payments: { header: ['Kalit (ID)', 'Sana', "O'quvchi ID", 'F.I.Sh.', 'Summa'], money: [4], sk: 2, rows: [['P1', '2026-10-05', 'IQ-1', 'Sinov Bir', 1000], ['P2', '2026-11-03', 'IQ-1', 'Sinov Bir', 400]] },
    debts: { header: ["O'quvchi ID", 'F.I.Sh.', 'Jami qarz'], money: [2], rows: [['IQ-2', 'Sinov Ikki', 1000], ['IQ-1', 'Sinov Bir', 600]] },
    monthly: { header: ['Oy', 'Hisoblangan', "Yig'im foizi, %"], money: [1], rows: [['2026-10', 1000, 100], ['2026-11', 2000, 20]] },
    expenses: { header: ['Sana', 'Oy', 'Summa'], money: [2], rows: [['2026-10-15', '2026-10', 300]] },
    refunds: { header: ['Sana', 'Oy', 'Summa'], money: [2], rows: [] },
  };
  const db = { T, outbox: [], seq: 0, calls: [] };
  db.push = (src, key) => { db.outbox.push({ id: ++db.seq, src, key, seen: false }); };
  db.rpc = async (name, args) => {
    db.calls.push({ name, args: JSON.parse(JSON.stringify(args || {})) });
    switch (name) {
      case 'sheets_tab': {
        const t = T[args.p_tab]; if (!t) return { data: null, error: null };
        let rows = t.rows;
        if (Array.isArray(args.p_keys) || Array.isArray(args.p_students)) {
          const ks = new Set(args.p_keys || []), ss = new Set(args.p_students || []);
          rows = rows.filter((r) => ks.has(String(r[0])) || (t.sk !== undefined && ss.has(String(r[t.sk]))));
        }
        return { data: JSON.parse(JSON.stringify({ header: t.header, money: t.money, rows })), error: null };
      }
      case 'sheets_pull': return { data: db.outbox.slice(0, args.p_limit).map(({ id, src, key }) => ({ id, src, key })), error: null };
      case 'sheets_ack': { const ids = new Set(args.p_ids); const n0 = db.outbox.length; db.outbox = db.outbox.filter((x) => !ids.has(x.id)); return { data: n0 - db.outbox.length, error: null }; }
      case 'sheets_full_begin': { let n = 0; db.outbox.forEach((x) => { if (!x.seen) { x.seen = true; n += 1; } }); return { data: n, error: null }; }
      case 'sheets_full_end': { const n0 = db.outbox.length; db.outbox = db.outbox.filter((x) => !x.seen); return { data: n0 - db.outbox.length, error: null }; }
      default: return { data: null, error: { message: 'noma\'lum rpc ' + name } };
    }
  };
  return db;
}

function env(opts = {}) {
  const c = clock();
  const fake = makeFakeSheets({ publicKey, clientEmail: KEY.client_email, now: c.now });
  const google = makeGoogle({ key: KEY, fetch: fake.fetch, tokenUrl: TOKEN_URL, apiBase: API, now: c.now, sleep: c.sleep, perMinute: 100000 });
  const db = fakeDb();
  const logs = [];
  const sync = makeSync({ rpc: db.rpc, google, spreadsheetId: fake.state.id, instance: 'sinov:1', log: (m) => logs.push(m), now: c.now, ...opts });
  return { c, fake, google, db, sync, logs };
}
const INV = "Oylik to'lovlar", PAY = "To'lovlar", STU = "O'quvchilar";
const rowsOf = (t) => [t.header, ...t.rows];
const callNames = (db, from = 0) => db.calls.slice(from).map((x) => x.name);

(async () => {
  // ================= google.cjs =================
  {
    const c = clock();
    const fake = makeFakeSheets({ publicKey, clientEmail: KEY.client_email, now: c.now });
    fake.addSheet('A');
    const g = makeGoogle({ key: KEY, fetch: fake.fetch, tokenUrl: TOKEN_URL, apiBase: API, now: c.now, sleep: c.sleep });
    const r = await g.spreadsheet(fake.state.id);
    ok('G1 JWT (RS256) ochiq kalit bilan tekshiriladi, token olinadi, jadval o\'qiladi', r.sheets.length === 1 && r.sheets[0].properties.title === 'A' && fake.state.tokenN === 1);
    await g.spreadsheet(fake.state.id);
    ok('G2 token keshlanadi (ikkinchi so\'rovda yangi token yo\'q)', fake.state.tokenN === 1);
    c.set(c.now() + 3600 * 1000 - 30000);   // tugashiga 30 s qoldi
    await g.spreadsheet(fake.state.id);
    ok('G3 token tugashidan 1 daqiqa oldin yangilanadi', fake.state.tokenN === 2);
    fake.state.tokens.clear();            // server tokenni bekor qildi
    await g.spreadsheet(fake.state.id);
    ok('G4 401 — token bir marta yangilanib qayta so\'raladi', fake.state.tokenN === 3);
    c.sleeps.length = 0;
    fake.failNext(429, { retryAfter: 7, match: /^GET \/v4\/spreadsheets/ });
    fake.failNext(503, { count: 2, match: /^GET \/v4\/spreadsheets/ });
    await g.spreadsheet(fake.state.id);
    ok('G5 429 (Retry-After 7 s) va 503 — kutib qayta urinadi (7 s, 2 s, 4 s)', eq(c.sleeps, [7000, 2000, 4000]), c.sleeps);
    fake.failNext(503, { count: 10, match: /^GET \/v4\/spreadsheets/ });
    let e = null; try { await g.spreadsheet(fake.state.id); } catch (x) { e = x; }
    ok('G6 6 urinishdan keyin — GoogleError 503', e instanceof GoogleError && e.status === 503, e && e.message);
    fake.state.fails.length = 0;
    fake.state.denied = true;
    e = null; c.sleeps.length = 0; try { await g.spreadsheet(fake.state.id); } catch (x) { e = x; }
    ok('G7 403 — darhol (qayta urinishsiz), tushuntirish: jadvalni xizmat hisobiga «Muharrir» qilib ulashing', e && e.status === 403 && !c.sleeps.length && /Muharrir/.test(explain(e)), e && explain(e));
    fake.state.denied = false;
    e = null; try { await g.spreadsheet('BOSHQA-ID'); } catch (x) { e = x; }
    ok('G8 404 — tushuntirish: spreadsheetId', e && e.status === 404 && /spreadsheetId/.test(explain(e)), e && explain(e));
    const g2 = makeGoogle({ key: { client_email: 'boshqa@sinov.test', private_key: privateKey }, fetch: fake.fetch, tokenUrl: TOKEN_URL, apiBase: API, now: c.now, sleep: c.sleep });
    e = null; c.sleeps.length = 0; try { await g2.spreadsheet(fake.state.id); } catch (x) { e = x; }
    ok('G9 noto\'g\'ri kalit (token 400) — darhol xato, tushuntirish: kalit', e && e.status === 400 && !c.sleeps.length && /kaliti noto'g'ri/.test(explain(e)), e && explain(e));
    const other = crypto.generateKeyPairSync('rsa', { modulusLength: 2048, privateKeyEncoding: { type: 'pkcs8', format: 'pem' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });
    const g3 = makeGoogle({ key: { client_email: KEY.client_email, private_key: other.privateKey }, fetch: fake.fetch, tokenUrl: TOKEN_URL, apiBase: API, now: c.now, sleep: c.sleep });
    e = null; try { await g3.spreadsheet(fake.state.id); } catch (x) { e = x; }
    ok('G10 boshqa kalit bilan imzolangan JWT rad etiladi', e && e.status === 400 && /Signature/.test(e.message), e && e.message);
    // kvota: daqiqasiga 3 ta so'rov
    const c2 = clock();
    const f2 = makeFakeSheets({ publicKey, clientEmail: KEY.client_email, now: c2.now });
    const g4 = makeGoogle({ key: KEY, fetch: f2.fetch, tokenUrl: TOKEN_URL, apiBase: API, now: c2.now, sleep: c2.sleep, perMinute: 3 });
    const t0 = c2.now();
    for (let i = 0; i < 4; i++) await g4.spreadsheet(f2.state.id);
    const apiCalls = f2.state.calls.filter((x) => /spreadsheets/.test(x.path));
    ok('G11 kvota: daqiqasiga 3 ta — 4-so\'rov birinchisidan 60 s keyin', apiCalls.length === 4 && apiCalls[3].at - apiCalls[0].at >= 60000 && apiCalls[2].at - t0 < 1000, apiCalls.map((x) => x.at - t0));
    // tarmoq xatosi — qayta urinish
    let n = 0;
    const flaky = async (u, i) => { n += 1; if (n === 2) throw new Error('ECONNRESET'); return f2.fetch(u, i); };
    const g5 = makeGoogle({ key: KEY, fetch: flaky, tokenUrl: TOKEN_URL, apiBase: API, now: c2.now, sleep: c2.sleep });
    const r5 = await g5.spreadsheet(f2.state.id);
    ok('G12 tarmoq xatosi (ECONNRESET) — qayta urinadi', !!r5.spreadsheetId && n === 3, n);
    // vaqt chegarasi — osilgan ulanish uziladi
    const hang = (u, i) => new Promise((res, rej) => { if (i && i.signal) i.signal.addEventListener('abort', () => rej(new Error('aborted'))); });
    const g6 = makeGoogle({ key: KEY, fetch: hang, tokenUrl: TOKEN_URL, apiBase: API, maxTries: 1, timeoutMs: 1000 });
    const t1 = Date.now(); e = null; try { await g6._token(); } catch (x) { e = x; }
    ok('G13 osilgan ulanish vaqt chegarasida uziladi (xizmat to\'xtab qolmaydi)', e && /aborted/.test(e.message) && Date.now() - t1 < 5000, e && e.message);
    e = null; try { makeGoogle({ key: { client_email: 'x' } }); } catch (x) { e = x; }
    ok('G14 kalitda private_key yo\'q — tushunarli xato', e && /private_key/.test(e.message));
    ok('G15 A1 oraliq tahlili (qo\'shtirnoqli nom, ochiq oxir)', eq(parseA1("'O''quvchilar'!B2:C"), { title: "O'quvchilar", r1: 1, c1: 1, r2: Infinity, c2: 2 }) && eq(parseA1('X!A5'), { title: 'X', r1: 4, c1: 0, r2: 4, c2: 0 }));
  }

  // ================= sync.cjs: yordamchilar =================
  ok('S01 ustun nomlari', colName(1) === 'A' && colName(26) === 'Z' && colName(27) === 'AA' && colName(52) === 'AZ' && colName(703) === 'AAA');
  ok('S02 katak qiymati: NaN / cheksiz — bo\'sh, null — bo\'sh, son va mantiqiy — o\'zi, juda uzun matn qisqartiriladi',
    cellOf(NaN) === '' && cellOf(Infinity) === '' && cellOf(null) === '' && cellOf(undefined) === '' && cellOf(5) === 5 && cellOf(false) === false && cellOf('x'.repeat(60000)).length === 45001);
  ok('S03 Toshkent kuni va soati (UTC+5)', eq(tashkent(Date.parse('2026-11-14T22:30:00Z')), { day: '2026-11-15', hour: 3 }) && eq(tashkent(Date.parse('2026-11-14T18:59:00Z')), { day: '2026-11-14', hour: 23 }));

  // ================= sync.cjs: to'liq yozish =================
  {
    const { fake, db, sync } = env();
    db.push('invoices', 'inv1');                               // xizmat ishga tushishidan oldin navbatda turgan yozuv
    const n = await sync.cycle();
    const titles = fake.state.sheets.map((s) => s.title);
    ok('S04 birinchi aylanish — barcha varaqlar to\'liq yoziladi (tartib bilan), oldingi navbat qamrab olinib o\'chiriladi',
      n === 1 && eq(titles, TABS.map((t) => t.title)) && db.outbox.length === 0, { n, titles, outbox: db.outbox });
    ok('S05 to\'liq yozish navbat belgisi bilan: full_begin -> varaqlar -> full_end', (() => { const c = callNames(db); return c[0] === 'sheets_full_begin' && c[c.length - 1] === 'sheets_full_end' && c.filter((x) => x === 'sheets_tab').length === TABS.length; })(), callNames(db));
    ok('S06 varaq qiymatlari bazadagidek (son — son, matn — matn)', eq(fake.grid(INV), rowsOf(db.T.invoices)) && eq(fake.grid(STU), rowsOf(db.T.students)) && eq(fake.grid('Qaytarishlar'), [db.T.refunds.header]),
      fake.grid(INV));
    const s = fake.sheet(INV);
    ok('S07 sarlavha qotirilgan, varaq «ogohlantirish bilan» himoyalangan (bitta), ustun kengligi moslangan',
      fake.state.sheets.every((x) => x.frozen === 1 && x.protected.length === 1 && x.protected[0].warningOnly === true && x.resized >= 1), fake.state.sheets.map((x) => [x.title, x.frozen, x.protected.length, x.resized]));
    const moneyCols = s.formats.filter((f) => f.cell.userEnteredFormat.numberFormat).map((f) => f.range.startColumnIndex);
    ok('S08 pul ustunlari «#,##0» formatida (faqat money ro\'yxatidagilar)', eq(moneyCols, [4, 5]) && s.formats.every((f) => !f.cell.userEnteredFormat.numberFormat || f.cell.userEnteredFormat.numberFormat.pattern === '#,##0'), s.formats);
    ok('S09 holat: oxirgi muvaffaqiyat, kun, qatorlar soni', (() => { const st = sync.status(); return st.lastOk && st.lastFull === '2026-11-15' && st.tabs[INV] === 3 && st.lastError === null && st.instance === 'sinov:1'; })(), sync.status());

    // ---- kalitli yangilash ----
    db.T.invoices.rows[1][5] = 100;                            // inv2 qarzi o'zgardi
    db.T.students.rows[0][3] = 100;
    const payBefore = JSON.stringify(fake.grid(PAY));
    const k0 = db.calls.length;
    db.push('invoices', 'inv2');
    const n2 = await sync.cycle();
    ok('S10 hisob-faktura o\'zgardi — o\'z qatorida yangilanadi, qolganlari joyida', n2 === 1 && eq(fake.grid(INV), rowsOf(db.T.invoices)) && db.outbox.length === 0, fake.grid(INV));
    ok('S11 shu bilan o\'quvchilar / qarzdorlik / oylik hisobot to\'liq qayta yozildi, to\'lovlar varag\'iga tegilmadi',
      eq(fake.grid(STU), rowsOf(db.T.students)) && JSON.stringify(fake.grid(PAY)) === payBefore
      && eq(db.calls.slice(k0).filter((x) => x.name === 'sheets_tab').map((x) => x.args.p_tab), ['students', 'invoices', 'debts', 'monthly']),
      db.calls.slice(k0).map((x) => x.name + ':' + (x.args.p_tab || '')));
    ok('S12 kalitli so\'rov — faqat o\'zgargan kalit (o\'quvchi ro\'yxati bo\'sh)', (() => { const x = db.calls.slice(k0).find((y) => y.name === 'sheets_tab' && y.args.p_tab === 'invoices'); return x && eq(x.args.p_keys, ['inv2']) && eq(x.args.p_students, []); })());
    ok('S13 navbatdan aynan o\'qilgan id\'lar o\'chirildi', (() => { const x = db.calls.slice(k0).find((y) => y.name === 'sheets_ack'); return x && eq(x.args.p_ids, [2]) && x.args.p_instance === 'sinov:1'; })());

    // ---- yangi qator — oxiriga ----
    db.T.invoices.rows.push(['inv4', '2026-12', 'IQ-2', 'Sinov Ikki', 1000, 1000]);
    db.push('invoices', 'inv4');
    await sync.cycle();
    ok('S14 yangi hisob-faktura — varaq oxiriga qo\'shiladi', eq(fake.grid(INV), rowsOf(db.T.invoices)), fake.grid(INV));

    // ---- o'chirilgan — varaqdan ham ----
    db.T.invoices.rows = db.T.invoices.rows.filter((r) => r[0] !== 'inv3');
    db.push('invoices', 'inv3');
    await sync.cycle();
    ok('S15 bazadan o\'chgan hisob-faktura — varaqdan qator o\'chiriladi, qolganlari tartibda', eq(fake.grid(INV), rowsOf(db.T.invoices)) && sync.status().tabs[INV] === 3, fake.grid(INV));

    // ---- qo'lda tartiblangan varaq: kalit A ustunidan topiladi ----
    const sh = fake.sheet(INV);
    [sh.cells[1], sh.cells[2]] = [sh.cells[2], sh.cells[1]];   // foydalanuvchi qatorlarni almashtirdi
    db.T.invoices.rows[0][5] = 55;                             // inv1
    db.push('invoices', 'inv1');
    await sync.cycle();
    const g = fake.grid(INV);
    ok('S16 qo\'lda tartiblangan varaq — o\'zgargan qator yangi joyida topilib yangilanadi, boshqasi tegilmaydi', g[2][0] === 'inv1' && g[2][5] === 55 && g[1][0] === 'inv2' && g[1][5] === 100, g);

    // ---- o'quvchi kartasi o'zgardi: shu o'quvchining qatorlari ----
    db.T.invoices.rows.forEach((r) => { if (r[2] === 'IQ-2') r[3] = 'Sinov Ikki Yangi'; });
    db.T.students.rows[1][1] = 'Sinov Ikki Yangi';
    const k1 = db.calls.length;
    db.push('students', 'IQ-2');
    await sync.cycle();
    const gi = fake.grid(INV);
    ok('S17 o\'quvchi ismi o\'zgardi — uning hisob-faktura qatorlari yangilandi (o\'quvchi kaliti bo\'yicha), o\'quvchilar varag\'i to\'liq',
      gi.find((r) => r[0] === 'inv4')[3] === 'Sinov Ikki Yangi' && fake.grid(STU)[2][1] === 'Sinov Ikki Yangi'
      && (() => { const x = db.calls.slice(k1).find((y) => y.name === 'sheets_tab' && y.args.p_tab === 'invoices'); return x && eq(x.args.p_keys, []) && eq(x.args.p_students, ['IQ-2']); })()
      && eq(db.calls.slice(k1).filter((x) => x.name === 'sheets_tab').map((x) => x.args.p_tab), ['students', 'invoices', 'payments', 'debts', 'refunds']),
      db.calls.slice(k1).map((x) => x.name + ':' + (x.args.p_tab || '')));

    // ---- to'liq varaq qisqardi: ortiqcha qatorlar tozalanadi ----
    db.T.debts.rows = [['IQ-2', 'Sinov Ikki Yangi', 1000]];
    db.push('student_credit', 'IQ-1');
    await sync.cycle();
    ok('S18 qarzdorlik qisqardi — eski qatorlar tozalanadi', eq(fake.grid('Qarzdorlik'), rowsOf(db.T.debts)), fake.grid('Qarzdorlik'));

    // ---- sarlavha o'zgardi (yangi ustun) — kalitli varaq to'liq qayta yoziladi ----
    db.T.invoices.header = [...db.T.invoices.header, 'Holati'];
    db.T.invoices.rows.forEach((r) => r.push('Sinov'));
    db.push('invoices', 'inv1');
    await sync.cycle();
    ok('S19 sarlavha o\'zgardi — kalitli varaq to\'liq qayta yoziladi (barcha qatorlarda yangi ustun)', eq(fake.grid(INV), rowsOf(db.T.invoices)), fake.grid(INV));

    // ---- matn formula bo'lib talqin qilinmaydi (RAW) ----
    db.T.expenses.rows.push(['2026-11-02', '2026-11', 100]);
    db.T.expenses.header = ['Sana', 'Oy', 'Summa', 'Izoh'];
    db.T.expenses.rows.forEach((r) => { if (r.length === 3) r.push('=1+1'); });
    db.push('expenses', 'E2');
    await sync.cycle();
    ok('S20 «=1+1» kabi matn — matn bo\'lib yoziladi (RAW, formula emas)', fake.grid('Xarajatlar')[1][3] === '=1+1', fake.grid('Xarajatlar'));

    // ---- noma'lum manba — o'chiriladi, yozuv yo'q ----
    const k2 = db.calls.length;
    db.push('nomalum_jadval', 'x');
    const n3 = await sync.cycle();
    ok('S21 noma\'lum manba — navbatdan o\'chiriladi, varaqqa tegilmaydi', n3 === 1 && db.outbox.length === 0 && !db.calls.slice(k2).some((x) => x.name === 'sheets_tab'), callNames(db, k2));

    // ---- Google xatosi: navbat saqlanadi, keyin to'liq yozish bilan tiklanadi ----
    db.T.payments.rows[0][4] = 999;
    db.push('payments', 'P1');
    fake.failNext(500, { count: 50, match: /values:batchUpdate/ });
    const kf = db.calls.length;
    let e = null; try { await sync.cycle(); } catch (x) { e = x; }
    ok('S22 Google xatosi — aylanish xato bilan tugaydi, navbat o\'chirilmaydi', e && db.outbox.length === 1 && !callNames(db, kf).includes('sheets_ack'), { m: e && e.message, outbox: db.outbox, calls: callNames(db, kf) });
    sync.failed(e.message);
    ok('S23 holatda xato yozildi', /HTTP 500/.test(sync.status().lastError) && !!sync.status().lastErrorAt);
    fake.state.fails.length = 0;
    const k3 = db.calls.length;
    await sync.cycle();
    ok('S24 xatodan keyin — to\'liq qayta yozish (full_begin / full_end), navbat bo\'shadi, xato tozalandi',
      callNames(db, k3)[0] === 'sheets_full_begin' && db.outbox.length === 0 && fake.grid(PAY)[1][4] === 999 && sync.status().lastError === null, callNames(db, k3));

    // ---- varaqni foydalanuvchi o'chirib yubordi ----
    fake.deleteSheet(INV);
    db.push('invoices', 'inv1');
    e = null; try { await sync.cycle(); } catch (x) { e = x; sync.failed(x.message); }
    await sync.cycle();
    ok('S25 o\'chirilgan varaq — xatodan keyingi to\'liq yozishda qayta yaratiladi', !!e && eq(fake.grid(INV), rowsOf(db.T.invoices)) && fake.sheet(INV).protected.length === 1, e && e.message);

    // ---- juda ko'p kalit — to'liq yozish (A ustuni o'qilmaydi) ----
    const k4 = fake.state.calls.length;
    for (let i = 0; i <= KEYED_MAX; i++) db.push('invoices', 'x' + i);
    await sync.cycle();
    ok('S26 bir aylanishda ' + (KEYED_MAX + 1) + ' ta kalit — varaq to\'liq qayta yoziladi (A ustuni o\'qilmaydi)', !fake.state.calls.slice(k4).some((x) => x.method === 'GET' && /values[:/]/.test(x.path)) && eq(fake.grid(INV), rowsOf(db.T.invoices)) && db.outbox.length === 0);

    // ---- katta navbat — bitta to'liq yozish ----
    for (let i = 0; i < 12; i++) db.push('payments', 'P1');
    const k5 = db.calls.length;
    await sync.cycle({ limit: 5 });
    ok('S27 navbat chegaradan katta — to\'liq yozish, butun navbat (chegaradan ortig\'i ham) bo\'shaydi', callNames(db, k5).includes('sheets_full_begin') && db.outbox.length === 0, callNames(db, k5));

  }
  {
    const { c, db, sync } = env();
    await sync.cycle();
    c.set(Date.parse('2026-11-15T21:59:00Z'));                 // 16-noyabr 02:59 Toshkent
    let k = db.calls.length; await sync.cycle();
    ok('S28 ertasi kuni 03:00 gacha — to\'liq yozish yo\'q', !callNames(db, k).includes('sheets_full_begin'), callNames(db, k));
    c.set(Date.parse('2026-11-15T22:01:00Z'));                 // 03:01
    k = db.calls.length; await sync.cycle();
    ok('S29 03:00 dan keyin — kechki to\'liq yozish (kuniga bir marta)', callNames(db, k)[0] === 'sheets_full_begin' && sync.status().lastFull === '2026-11-16', callNames(db, k));
    c.set(Date.parse('2026-11-15T23:30:00Z'));
    k = db.calls.length; await sync.cycle();
    ok('S30 o\'sha kuni qayta — yo\'q', !callNames(db, k).includes('sheets_full_begin'));
  }
  {
    const { db, sync } = env({ fromMonth: '2026-10' });
    await sync.cycle();
    const tabsWithFrom = db.calls.filter((x) => x.name === 'sheets_tab' && x.args.p_from === '2026-10').map((x) => x.args.p_tab);
    const tabsWithout = db.calls.filter((x) => x.name === 'sheets_tab' && x.args.p_from === undefined).map((x) => x.args.p_tab);
    ok('S31 boshlang\'ich oy — faqat ledger varaqlariga (o\'quvchilar va qarzdorlik — to\'liq)', eq(tabsWithFrom, ['invoices', 'payments', 'monthly', 'expenses', 'refunds']) && eq(tabsWithout, ['students', 'debts']), { tabsWithFrom, tabsWithout });
  }
  {
    // xizmat qayta ishga tushdi — himoya va sarlavha takrorlanmaydi; jadval kattalashsa format yangi qatorlarga ham
    const e1 = env();
    await e1.sync.cycle();
    const sync2 = makeSync({ rpc: e1.db.rpc, google: e1.google, spreadsheetId: e1.fake.state.id, instance: 'sinov:2', now: e1.c.now });
    await sync2.cycle();
    ok('S32 qayta ishga tushgan xizmat — har varaqda baribir bitta himoya', e1.fake.state.sheets.every((s) => s.protected.length === 1), e1.fake.state.sheets.map((s) => s.protected.length));
    for (let i = 0; i < 1200; i++) { e1.db.T.invoices.rows.push(['n' + i, '2026-12', 'IQ-1', 'Sinov Bir', 1, 1]); e1.db.push('invoices', 'n' + i); }
    await sync2.cycle();
    const s = e1.fake.sheet(INV);
    const last = s.formats.filter((f) => f.cell.userEnteredFormat.numberFormat).slice(-2);
    ok('S33 1200 ta yangi qator — panjara kattalashadi, pul formati yangi qatorlarni ham qamraydi', s.rowCount >= 1204 && last.every((f) => f.range.endRowIndex === s.rowCount) && eq(e1.fake.grid(INV), rowsOf(e1.db.T.invoices)), { rows: s.rowCount, last });
  }
  {
    // Google so'rovlari soni (kvota): to'liq yozish va oddiy o'zgarish — bir necha so'rov, o'zgarmagan varaq — so'rovsiz
    const { fake, db, sync } = env();
    const api = (from) => fake.state.calls.slice(from).filter((x) => /\/spreadsheets\//.test(x.path)).map((x) => x.method + ' ' + x.path.replace(/^.*\/spreadsheets\/[^/:]+/, ''));
    let k = fake.state.calls.length;
    await sync.cycle();
    const a1 = api(k);
    ok('S36 yangi jadvalga 7 varaqni to\'liq yozish — 6 ta so\'rov (jadval, varaqlar, bezak, qiymatlar, format, tozalash)', a1.length === 6
      && eq(a1, ['GET ', 'POST :batchUpdate', 'POST :batchUpdate', 'POST /values:batchUpdate', 'POST :batchUpdate', 'POST /values:batchClear']), a1);
    db.T.invoices.rows[1][5] = 7; db.T.students.rows[0][3] = 7;
    db.push('invoices', 'inv2'); db.push('payments', 'P1'); db.push('students', 'IQ-1');
    k = fake.state.calls.length;
    await sync.cycle();
    const a2 = api(k);
    ok('S37 bir aylanishda bir nechta jadval o\'zgardi — 2 ta so\'rov (A ustunlari + barcha qiymatlar)', eq(a2, ['GET /values:batchGet', 'POST /values:batchUpdate']) && eq(fake.grid(INV), rowsOf(db.T.invoices)) && eq(fake.grid(STU), rowsOf(db.T.students)), a2);
    db.push('refunds', 'R9'); db.push('expenses', 'E9');
    k = fake.state.calls.length;
    const n = await sync.cycle();
    ok('S38 ma\'lumoti o\'zgarmagan varaqlar qayta yozilmaydi (Google so\'rovi yo\'q), navbat baribir o\'chiriladi', n === 2 && api(k).length === 0 && db.outbox.length === 0, api(k));
    db.T.monthly.rows.pop();
    db.push('expenses', 'E9');
    k = fake.state.calls.length;
    await sync.cycle();
    ok('S39 varaq qisqardi — qiymatlar va faqat ortgan qator tozalanadi', eq(api(k), ['POST /values:batchUpdate', 'POST /values:batchClear']) && eq(fake.grid('Oylik hisobot'), rowsOf(db.T.monthly)), api(k));
  }
  {
    let e = null; try { makeSync({ rpc: async () => ({}), google: {}, spreadsheetId: 'x' }); } catch (x) { e = x; }
    ok('S34 nusxa nomisiz (instance) ishga tushmaydi', e && /instance/.test(e.message));
    const e2 = env();
    const bad = makeSync({ rpc: async () => ({ data: null, error: { message: 'baza ulanmadi' } }), google: e2.google, spreadsheetId: e2.fake.state.id, instance: 'sinov:3', now: e2.c.now });
    e = null; try { await bad.cycle(); } catch (x) { e = x; }
    ok('S35 baza xatosi — tushunarli matn', e && /baza sheets_full_begin: baza ulanmadi/.test(e.message), e && e.message);
  }

  // ================= index.cjs: readConfig =================
  {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'iqror-sheets-'));
    const keyPath = path.join(dir, 'kalit.json');
    fs.writeFileSync(keyPath, JSON.stringify(KEY));
    const cfg = (o) => { const p = path.join(dir, 'c' + Math.random().toString(36).slice(2) + '.json'); fs.writeFileSync(p, JSON.stringify(o)); return p; };
    const base = { backend: 'supabase', supabaseUrl: 'http://127.0.0.1:1', serviceRoleKey: 'sinov', sheets: { spreadsheetId: 'SINOV', keyFile: keyPath } };
    const rc = (o) => { process.env.IQROR_CONFIG = cfg(o); delete require.cache[require.resolve('./index.cjs')]; return require('./index.cjs').readConfig(); };
    ok('R1 sozlangan — kalit o\'qiladi', (() => { const r = rc(base); return !r.off && r.key.client_email === KEY.client_email && r.fromMonth === null; })());
    ok('R2 sheets.enabled=false — o\'chiq', /enabled = false/.test(rc({ ...base, sheets: { ...base.sheets, enabled: false } }).off));
    ok('R3 jadval ID yozilmagan / namunadagidek', /spreadsheetId/.test(rc({ ...base, sheets: { keyFile: keyPath } }).off) && /spreadsheetId/.test(rc({ ...base, sheets: { ...base.sheets, spreadsheetId: 'PASTE_JADVAL_ID' } }).off));
    ok('R4 serviceRoleKey namunadagidek — o\'chiq', /serviceRoleKey/.test(rc({ ...base, serviceRoleKey: 'PASTE_SERVICE_ROLE_KEY' }).off));
    ok('R5 kalit fayli yo\'q / buzuq', /kaliti o'qilmadi/.test(rc({ ...base, sheets: { ...base.sheets, keyFile: path.join(dir, 'yoq.json') } }).off)
      && (() => { const p = path.join(dir, 'buzuq.json'); fs.writeFileSync(p, '{"client_email":"x"}'); return /private_key/.test(rc({ ...base, sheets: { ...base.sheets, keyFile: p } }).off); })());
    ok('R6 boshlang\'ich oy: to\'g\'ri — qabul, noto\'g\'ri — o\'chiq (tushuntirish bilan)', rc({ ...base, sheets: { ...base.sheets, fromMonth: '2026-09' } }).fromMonth === '2026-09'
      && /fromMonth/.test(rc({ ...base, sheets: { ...base.sheets, fromMonth: '2026-13' } }).off));
    delete process.env.IQROR_CONFIG;
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) { /* jim */ }
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('  ✗ KUTILMAGAN XATO:', e && e.stack); process.exit(1); });
