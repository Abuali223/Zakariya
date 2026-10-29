/**
 * sms-worker.cjs — SMS xabarnomalari (CRON bilan ishlaydi, alohida jarayon).
 * -------------------------------------------------------------------
 * 1) YANGI FAKTURA: oxirgi N kunda yaratilgan, hali xabar yuborilmagan
 *    to'lanmagan fakturalar uchun ota-ona telefoniga SMS.
 * 2) QARZDORLIK: oyning 10-sanasidan keyin to'lanmagan fakturalar uchun
 *    haftada 2 marta (config: reminderDays, msln Dushanba+Payshanba) eslatma.
 *
 * Takror ketmasligi uchun har SMS `sms_log` jadvaliga yoziladi:
 *   yangi:  id = "<invoiceId>__new"
 *   qarz:   id = "<invoiceId>__debt__<YYYY-MM-DD>"   (kuniga bittadan -> haftada 2; sana — Toshkent)
 *
 * Ota-onani bezovta qilmaslik:
 *   - TINCH SOATLAR: faqat Toshkent vaqti bilan sms.sendHours oralig'ida (standart 09:00–20:00) yuboriladi; tunda cron
 *     ishlasa ham hech narsa ketmaydi (claim ham qilinmaydi) — xabar ertalabki birinchi run'da ketadi.
 *   - BIR TELEFONGA KUNIGA BITTA SMS (yangi faktura, qarz va qo'lda «Eslatma» birga sanaladi). Qarz eslatmasi — har o'quvchi
 *     uchun BITTA SMS: barcha qarz oylari va jami qarz bilan (qo'lda «Eslatma» bilan bir xil matn). Aka-uka bitta telefonda
 *     bo'lsa — eslatma kunlarida navbatma-navbat (oxirgi eslatmasi eng eski bola birinchi). Yangi faktura xabari keyingi
 *     run'larda (newLookbackDays ichida) ketadi.
 *   - Qarz cron'i sendHours ICHIDA ishlashi kerak: tinch soatda qarz eslatmasi o'sha kuni umuman ketmaydi (id'da sana bor).
 *
 * Ishga tushirish (cron, masalan har 2 soatda):
 *   cd .../payments && node sms-worker.cjs           # ikkalasi (debt faqat reminderDays'da)
 *   node sms-worker.cjs new                          # faqat yangi faktura xabarlari
 *   node sms-worker.cjs debt                         # faqat qarzdorlik (kun tekshiruvisiz majburiy)
 *   node sms-worker.cjs --dry                        # sinov: yubormaydi, faqat log qiladi
 *
 * Sozlash: config.json -> "sms" bloki (config.example.json'ga qarang).
 * ⚠️ CRON yozuvlari ustma-ust tushmasin (bir vaqtda 2 nusxa ishlamasin) — flock ishlating.
 */
const fs = require('fs');
const path = require('path');
const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
const { db, FieldValue } = require('../server/backend.js')({ ...CFG, __dir: __dirname });
const { makeEskiz, DEF_NEW, DEF_DEBT, fmtMonth, tashkentDay, tashkentDayStartISO, tashkentDow, sendWindow, inSendWindow, orderDebtCandidates, sendStatus, definitelyNotSent, canonMobile, smsName } = require('./sms.cjs');
const { composeSms, smsSom, smsMonths } = require('./eskiz-template.cjs');

const SMS = CFG.sms || {};
const log = (...a) => console.log(new Date().toISOString(), ...a);

const tpl = (k, def) => (SMS.templates && SMS.templates[k]) || def;

// Bugun (Toshkent) SMS ketgan yoki ketishi mumkin bo'lgan telefonlar (sent/sending/unknown — qo'lda «Eslatma» ham).
//   Run boshida bir marta o'qiladi va har claim'dan keyin to'ldiriladi. O'qib bo'lmasa — cheklov faqat shu run ichida.
const SENT_TODAY = new Set();
async function loadSentToday() {
  const sb = db._sb; if (!sb) return;
  try {
    const { data, error } = await sb.from('sms_log').select('phone,status').gte('createdAt', tashkentDayStartISO(tashkentDay())).in('status', ['sent', 'sending', 'unknown']);
    if (error) throw error;
    (data || []).forEach(r => { const p = canonMobile(r.phone); if (p) SENT_TODAY.add(p); });
  } catch (e) { log('⚠️ Bugungi SMS ro\'yxati o\'qilmadi (' + ((e && e.message) || e) + ') — «telefonga kuniga 1 ta» cheklovi faqat shu run ichida ishlaydi.'); }
}
// Oxirgi qarz eslatmasi (avtomatik yoki qo'lda) — o'quvchi kanonik kaliti -> ISO vaqt (45 kun). Aka-uka navbati uchun.
//   O'qib bo'lmasa — bo'sh (navbat eng eski oy bo'yicha; cheklov baribir ishlaydi).
async function loadLastDebtSms() {
  const out = {}; const sb = db._sb; if (!sb) return out;
  const since = new Date(Date.now() - 45 * 864e5).toISOString();
  try {
    for (let from = 0, page = 0; page < 20; page++, from += 1000) {
      const { data, error } = await sb.from('sms_log').select('studentId,createdAt').in('type', ['debt', 'remind']).in('status', ['sent', 'sending', 'unknown'])
        .gte('createdAt', since).order('createdAt', { ascending: true }).range(from, from + 999);
      if (error) throw error;
      (data || []).forEach(r => { const k = CANON[r.studentId] || r.studentId; if (k && String(r.createdAt || '') > String(out[k] || '')) out[k] = String(r.createdAt); });
      if (!data || data.length < 1000) break;
    }
  } catch (e) { log('⚠️ Oxirgi qarz SMS\'lari o\'qilmadi (' + ((e && e.message) || e) + ') — aka-uka navbati bugun eng eski oy bo\'yicha.'); }
  return out;
}
// Tinch soat: haqiqiy rejimda oyna tashqarisida yuborish to'xtaydi (xato emas). DRY — faqat ogohlantiradi.
let QUIET = false;
const utcH = h => String((((h - 5) % 24) + 24) % 24).padStart(2, '0');   // Toshkent soati -> UTC soati (cron uchun maslahat)
const quietNow = dry => !dry && !inSendWindow(SMS);

// Faktura kaliti (invoices.studentId: o'quvchining studentId'si YOKI eski hujjat id'si) -> { phone } va KANONIK kalit.
//   auth/sms-remind.cjs bilan BIR XIL qoida: kalit BITTA o'quvchiga mos bo'lishi shart (studentId yoki hujjat id bo'yicha).
//   Bir nechta o'quvchiga mos kalit (bir bolaning hujjat id'si boshqasining studentId'si / studentId takrori) — NOANIQ:
//   SMS yuborilmaydi (bir bolaning qarzi boshqa oilaga ketmasin; «⚠️ Sifat»da ko'rinadi).
//   Telefon: o'quvchining o'z maxfiy yozuvi (hujjat id); yo'q bo'lsa — studentId kalitli yozuv (boshqa bolaning hujjati bo'lmasa).
//   Telefon — parentPhone / parentPhone2 dan BIRINCHI O'ZBEKISTON mobil raqami (auth/sms-remind bilan bir xil). SMS FAQAT
//   O'zbekiston raqamlariga: otaniki chet el raqami bo'lsa — onaniki (O'zbekiston) olinadi; O'zbekiston raqami umuman
//   bo'lmasa — telefon yo'q (SMS claim ham qilinmaydi: noto'g'ri/chet el raqami Eskiz xatosi deb sanalmasin).
//   KANONIK kalit (studentId || id) — qo'lda eslatma qulfi (remind__<kanonik>__<sana>) shu bilan tekshiriladi.
const CANON = {}; const AMBIG = new Set();
async function phoneMap() {
  const priv = {}, m = {};
  try {
    const snap = await db.collection('student_private').get();
    snap.docs.forEach(d => { const p = d.data() || {}; priv[d.id] = canonMobile(p.parentPhone) || canonMobile(p.parentPhone2) || ''; });
  } catch (e) { log('phoneMap xato:', e.message); }
  try {
    const rows = (await db.collection('students').get()).docs.map(d => ({ id: d.id, sid: String((d.data() || {}).studentId || '').trim() }));
    const idSet = new Set(rows.map(r => r.id)), byId = {}, byKey = {};
    rows.forEach(r => { byId[r.id] = r; [r.sid, r.id].filter(Boolean).forEach(k => { (byKey[k] = byKey[k] || new Set()).add(r.id); }); });
    Object.entries(byKey).forEach(([k, ids]) => {
      if (ids.size > 1) { AMBIG.add(k); return; }
      const r = byId[[...ids][0]];
      CANON[k] = r.sid || r.id;
      let phone = priv[r.id] || '';
      if (!phone && r.sid && r.sid !== r.id && !idSet.has(r.sid)) phone = priv[r.sid] || '';
      m[k] = { phone };
    });
  } catch (e) { log('phoneMap (o\'quvchilar) xato:', e.message); }
  return m;
}
const MAXTRIES = Number(SMS.maxRetries || 3);   // xato bo'lsa shuncha marta qayta uriniladi, keyin to'xtaydi
async function getSms(id) { try { const s = await db.collection('sms_log').doc(id).get(); return s.exists ? (s.data() || {}) : null; } catch (e) { return null; } }
// SMS allaqachon YUBORILGANmi (sent) yoki qayta urinishlar tugaganmi? -> {skip, attempts}
async function smsDone(id) { const p = await getSms(id); return { skip: !!(p && (p.status === 'sent' || (Number(p.attempts) || 0) >= MAXTRIES)), attempts: Number(p && p.attempts) || 0 }; }
async function logSms(id, rec) { try { await db.collection('sms_log').doc(id).set({ ...rec, createdAt: FieldValue.serverTimestamp() }); } catch (e) { log('logSms xato:', e.message); } }
// TAKROR YUBORISHDAN HIMOYA: yuborishдан OLDIN sms_log'ni ATOMIK CLAIM qilamiz (create -> id konfliktida
// xato -> false). Shunda jarayon send bilan log orasида uzilса YOKI javob no-aniq bo'lса, keyingi cron
// QAYTA yubormaydi (SMS puli behuda ketmaydi). Parallel cron nusxalari ham bittasi claim oladi.
// ANIQ rad etilgan (Eskiz'ning o'zi 4xx bilan rad etgan / umuman ulanmagan) urinish shu prefiks bilan yoziladi — faqat
//   shular qayta yuboriladi. Eski worker 'failed' ni noaniq holatlar (5xx/id'siz javob) uchun ham yozgan — prefikssiz
//   eski qatorlar QAYTA YUBORILMAYDI (ikki marta SMS ketmasin).
const REJ = 'rejected: ';
async function claimSms(id, rec) {
  try { await db.collection('sms_log').doc(id).create({ ...rec, status: 'sending', attempts: 1, createdAt: FieldValue.serverTimestamp() }); return true; }
  catch (e) {
    // Avvalgi urinish ANIQ rad etilgan ('failed' + REJ prefiksi) bo'lsa — SHARTLI qayta claim (holat/urinish o'zgarmagan
    //   bo'lsa), MAXTRIES gacha. 'sending'/'unknown'/'sent'/eski 'failed' — qayta yuborilmaydi (ikki marta SMS ketmasin).
    const sb = db._sb; if (!sb) return false;
    const p = await getSms(id); const n = Number(p && p.attempts) || 0;
    if (!p || p.status !== 'failed' || n >= MAXTRIES || String(p.error || '').indexOf(REJ) !== 0) return false;
    // createdAt — oxirgi urinish vaqti: «bugun shu raqamga SMS ketgan» cheklovi (loadSentToday) qayta yuborilganni ham ko'rsin.
    try { const { data, error } = await sb.from('sms_log').update({ ...rec, status: 'sending', attempts: n + 1, error: '', createdAt: new Date().toISOString() }).eq('id', id).eq('status', 'failed').eq('attempts', n).select('id');
      return !error && (data || []).length === 1; } catch (e2) { return false; }
  }
}
async function unclaimSms(id) { try { await db.collection('sms_log').doc(id).delete(); } catch (e) { log('unclaim xato:', e.message); } }
async function markSms(id, patch) { try { await db.collection('sms_log').doc(id).update(patch); } catch (e) { log('markSms xato:', e.message); } }
// Bitta SMS — status: sent | failed (aniq ketmagan) | unknown (ketgan bo'lishi mumkin) — payments/sms.cjs sendStatus.
//   Eskiz'ga UMUMAN yetib bo'lmasa (kirish/ulanish xatosi) — claim o'chiriladi (keyingi cron qayta yuboradi) va run TO'XTAYDI
//   (avvalgidek: hamma navbatdagi xabarni «failed» qilib yo'qotmaslik uchun). Ketma-ket CB_MAX ta xato — ham to'xtaydi.
const CB_MAX = Math.max(1, Number(SMS.maxConsecutiveFailures || 5));
let STOP = null, consecFail = 0;
async function sendOne(eskiz, id, phone, msg) {
  let r, thrown = null;
  try { r = await eskiz.send(phone, msg); } catch (e) { thrown = e || new Error('eskiz'); r = { ok: false, error: (e && e.message) || String(e) }; }
  const status = sendStatus(r, thrown);
  if (thrown && definitelyNotSent(thrown)) {
    await unclaimSms(id);
    STOP = `Eskiz bilan bog'lanib bo'lmadi (${r.error}) — run to'xtatildi; xabarlar keyingi cron'da yuboriladi.`;
    return Object.assign({}, r, { status: 'failed' });
  }
  // Mahalliy tekshiruv (noto'g'ri raqam — Eskiz'ga so'rov ketmagan): yakuniy, qayta urinilmaydi, Eskiz xatosi sanalmaydi.
  if (!r.ok && /^bad_phone/.test(String(r.error || ''))) {
    await markSms(id, { status: 'failed', attempts: MAXTRIES, error: String(r.error || '') });
    return Object.assign({}, r, { status: 'failed' });
  }
  await markSms(id, { status, providerId: r.id || '', error: r.ok ? '' : ((status === 'failed' ? REJ : '') + String(r.error || '')) });
  if (r.ok) consecFail = 0;
  else if (++consecFail >= CB_MAX) STOP = `${CB_MAX} ta ketma-ket SMS xatosi — run to'xtatildi (Eskiz holati / shablonni tekshiring).`;
  return Object.assign({}, r, { status });
}
// Eskiz'dagi tasdiqlangan shablon naqshlari (run boshida bir marta o'qiladi; o'qib bo'lmasa — null: matn oddiy yig'iladi).
//   SMS matni naqshga sig'adigan shaklda yig'iladi (eskiz-template.cjs composeSms) — Eskiz «moderatsiyadan o'tmagan» deb rad etmasin.
let APPROVED = null, warnedFit = false;
function smsText(tplStr, vals) {
  const cm = composeSms(tplStr, vals, APPROVED);
  if (cm.fit === false && !warnedFit) { warnedFit = true; log('⚠️ SMS matni Eskiz’dagi tasdiqlangan shablon naqshiga mos kelmayapti — Eskiz rad etishi mumkin. Tekshiruv: node eskiz-shablon.cjs'); }
  return cm.message;
}
const redactPhone = p => { const d = String(p || '').replace(/\D/g, ''); return d.length >= 6 ? d.slice(0, 5) + '***' + d.slice(-2) : '***'; };

// (1) YANGI FAKTURA xabarlari — oxirgi N kunda yaratilgan, to'lanmagan, amount>0.
async function runNew(eskiz, phones, dry) {
  const lookback = Number(SMS.newLookbackDays || 14);
  const since = new Date(Date.now() - lookback * 864e5).toISOString();
  let invs = [];
  try { invs = (await db.collection('invoices').where('createdAt', '>=', since).get()).docs.map(d => d.data()); }
  catch (e) { log('invoices(new) so\'rov xato:', e.message); return; }
  let sent = 0, skip = 0, fail = 0, later = 0;
  for (const inv of invs) {
    if (STOP) break;
    if (quietNow(dry)) { QUIET = true; break; }
    const amt = Number(inv.amount) || 0;
    if (amt <= 0) continue;                                          // grant/0 so'mlik — xabar yo'q
    if (['paid', 'canceled', 'reversed'].includes(inv.status)) continue;
    if (AMBIG.has(inv.studentId)) { skip++; log('SMS(new) o\'tkazildi — ID to\'qnashuvi:', inv.studentId); continue; }
    const id = `${inv.id}__new`;
    const dn = await smsDone(id);
    if (dn.skip) { skip++; continue; }
    const phone = (phones[inv.studentId] || {}).phone;
    if (!phone) { skip++; continue; }
    if (SENT_TODAY.has(phone)) { later++; continue; }               // bugun shu raqamga SMS ketgan — ertaga (lookback ichida)
    const msg = smsText(tpl('new', DEF_NEW), { name: smsName(inv.studentName), month: fmtMonth(inv.month), amount: smsSom(amt), due: smsSom(amt) });
    if (dry) { SENT_TODAY.add(phone); log('[DRY new]', redactPhone(phone), '::', msg); sent++; continue; }
    // CLAIM avval (create) — allaqachon claim qilingan/yuborilgan bo'lsa o'tkazamiz (takror yo'q).
    if (!(await claimSms(id, { invoiceId: inv.id, studentId: inv.studentId || '', phone, type: 'new', message: msg, month: inv.month || '' }))) { skip++; continue; }
    SENT_TODAY.add(phone);
    const r = await sendOne(eskiz, id, phone, msg);
    if (r.ok) sent++; else { fail++; log('SMS(new) xato:', redactPhone(phone), r.status, r.error); }
  }
  log(`YANGI: ${sent} yuborildi · ${skip} o'tkazildi · ${later} keyingi kunga (bugun shu raqamga SMS ketgan) · ${fail} xato`);
}

// (2) QARZDORLIK eslatmasi — 10-sanadan keyin to'lanmagan; faqat reminderDays kunlari.
//   Har O'QUVCHI uchun bitta SMS: barcha qarz oylari (smsMonths) + jami qarz (qo'lda «Eslatma» bilan bir xil). sms_log id —
//   eng eski qarz fakturasi: "<invoiceId>__debt__<sana>" (kuniga bitta; takror yo'q).
async function runDebt(eskiz, phones, dry, force) {
  const days = Array.isArray(SMS.reminderDays) ? SMS.reminderDays : [1, 4];   // 0=Yak,1=Dush..6=Shan
  const dow = tashkentDow();                                        // Toshkent kuni (server UTC bo'lsa ham)
  if (!force && !days.includes(dow)) { log(`QARZ: bugun (dow=${dow}) eslatma kuni emas — o'tkazildi.`); return; }
  const dom = String(Number(SMS.reminderDayOfMonth || 10)).padStart(2, '0');
  const today = tashkentDay();
  let sent = 0, skip = 0, fail = 0, later = 0, quietLeft = 0;
  const byStu = new Map();
  for (const st of ['pending', 'partial']) {
    let invs = [];
    try { invs = (await db.collection('invoices').where('status', '==', st).get()).docs.map(d => d.data()); }
    catch (e) { log('invoices(debt) so\'rov xato:', e.message); continue; }
    for (const inv of invs) {
      const due = (Number(inv.amount) || 0) - (Number(inv.paidAmount) || 0);
      if (due <= 0 || !inv.month) continue;
      if (AMBIG.has(inv.studentId)) { skip++; log('SMS(debt) o\'tkazildi — ID to\'qnashuvi:', inv.studentId); continue; }
      if (!(today > `${inv.month}-${dom}`)) continue;                // faqat 10-sanadan keyin
      const key = CANON[inv.studentId] || inv.studentId;
      const g = byStu.get(key) || { key, sid: inv.studentId, name: inv.studentName, items: [] };
      g.items.push({ inv, due }); if (!g.name && inv.studentName) g.name = inv.studentName; byStu.set(key, g);
    }
  }
  const cands = [...byStu.values()].map(g => {
    g.items.sort((a, b) => String(a.inv.month).localeCompare(String(b.inv.month)) || String(a.inv.id).localeCompare(String(b.inv.id)));
    const first = g.items[0].inv;
    return { key: g.key, name: g.name, inv: first, id: first.id, month: first.month, due: g.items.reduce((s, x) => s + x.due, 0), months: [...new Set(g.items.map(x => String(x.inv.month)))] };
  });
  const lastSent = await loadLastDebtSms();
  const ordered = orderDebtCandidates(cands, lastSent);
  for (let i = 0; i < ordered.length; i++) {
    const c = ordered[i], inv = c.inv;
    if (STOP) break;
    if (quietNow(dry)) { QUIET = true; quietLeft = ordered.length - i; break; }
    const id = `${inv.id}__debt__${today}`;
    const dn = await smsDone(id);
    if (dn.skip) { skip++; continue; }
    // Bugun shu o'quvchi ota-onasiga QO'LDA eslatma («Moliya» → «Qarzdorlar» → «Eslatma») ketgan yoki ketayotgan
    //   bo'lsa (holati noaniq ham) — takrorlamaymiz (ota-onaga bir kunda 2 ta SMS ketmasin).
    const man = await getSms(`remind__${c.key}__${today}`);
    if (man && ['sent', 'sending', 'unknown'].includes(man.status)) { skip++; continue; }
    const phone = (phones[inv.studentId] || {}).phone;
    if (!phone) { skip++; continue; }
    if (SENT_TODAY.has(phone)) { later++; continue; }               // bugun shu raqamga SMS ketgan (aka-uka / yangi faktura)
    const msg = smsText(tpl('debt', DEF_DEBT), { name: smsName(c.name || inv.studentName), month: smsMonths(c.months), amount: smsSom(c.due), due: smsSom(c.due) });
    if (dry) { SENT_TODAY.add(phone); log('[DRY debt]', redactPhone(phone), '::', msg); sent++; continue; }
    if (!(await claimSms(id, { invoiceId: inv.id, studentId: inv.studentId || '', phone, type: 'debt', message: msg, month: c.months[c.months.length - 1] || inv.month || '' }))) { skip++; continue; }
    SENT_TODAY.add(phone);
    const r = await sendOne(eskiz, id, phone, msg);
    if (r.ok) sent++; else { fail++; log('SMS(debt) xato:', redactPhone(phone), r.status, r.error); }
  }
  log(`QARZ: ${sent} yuborildi · ${skip} o'tkazildi · ${later} bitta raqamga kuniga 1 ta qoidasi bilan qoldirildi (aka-uka — keyingi eslatma kunida) · ${fail} xato`);
  if (quietLeft) log(`⚠️ QARZ: tinch soat boshlandi — qolgan ${quietLeft} ta o'quvchiga BUGUNGI qarz eslatmasi yuborilmaydi (keyingi eslatma kunida ketadi). Qarz cron'ini ertaroq (sendHours ichida) qo'ying.`);
}

(async () => {
  if (SMS.enabled === false) { log('SMS o\'chirilgan (config.sms.enabled=false). Chiqildi.'); return; }
  const args = process.argv.slice(2);
  const dry = SMS.dryRun === true || args.includes('--dry');
  const mode = (args.find(a => !a.startsWith('--')) || 'both').toLowerCase();   // new | debt | both
  const eskiz = dry ? null : makeEskiz(SMS);
  // Naqshlar faqat O'QILADI (GET) — sinov (--dry) rejimida ham, kalit bo'lsa: logdagi matn haqiqatda ketadigan bilan bir xil.
  const reader = eskiz || ((SMS.eskizEmail || SMS.email || SMS.token) ? makeEskiz(SMS) : null);
  if (reader && typeof reader.templates === 'function') {
    try { const r = await reader.templates(); if (r && r.ok) APPROVED = r.list; else log('Eskiz shablonlari o\'qilmadi:', (r && r.error) || ''); }
    catch (e) { log('Eskiz shablonlari xato:', (e && e.message) || e); }
  }
  const w = sendWindow(SMS);
  if (quietNow(dry)) {
    log(`TINCH SOAT: Toshkent vaqti ${w[0]}:00–${w[1]}:00 oralig'idan tashqarida — SMS yuborilmadi (yangi faktura xabarlari keyingi ish vaqtidagi run'da ketadi).`);
    // Qarz eslatmasi id'sida sana bor: tinch soatdagi qarz run'i shu kungi eslatmalarni YO'QOTADI (keyin «yetib olinmaydi»).
    if (mode === 'debt') { log(`⚠️ QARZ eslatmalari bugun YUBORILMAYDI: qarz cron'i tinch soatga to'g'ri kelgan. Cron vaqtini sendHours ichiga qo'ying (server UTC bo'lsa ${utcH(w[0])}:00–${utcH(w[1])}:00 UTC oralig'i).`); process.exitCode = 2; }
    return;
  }
  if (dry && w && !inSendWindow(SMS)) log(`(DRY) Hozir tinch soat — haqiqiy rejimda hech narsa yuborilmasdi (${w[0]}:00–${w[1]}:00).`);
  await loadSentToday();
  const phones = await phoneMap();
  if (mode === 'new' || mode === 'both') await runNew(eskiz, phones, dry);
  if ((mode === 'debt' || mode === 'both') && !STOP && !QUIET) await runDebt(eskiz, phones, dry, mode === 'debt');
  if (STOP) { log('TO\'XTATILDI: ' + STOP); process.exitCode = 1; return; }
  if (QUIET) { log('TINCH SOAT boshlandi — qolgan xabarlar keyingi ish vaqtidagi run\'da ketadi.'); return; }
  log('Tugadi.' + (dry ? ' (DRY — hech narsa yuborilmadi)' : ''));
})().catch(e => { console.error('sms-worker xato:', e && e.message || e); process.exit(1); });
