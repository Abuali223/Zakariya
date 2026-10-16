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
 *   qarz:   id = "<invoiceId>__debt__<YYYY-MM-DD>"   (kuniga bittadan -> haftada 2)
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
const { makeEskiz, DEF_NEW, DEF_DEBT, fmtSom, fmtMonth, fillTpl, tashkentDay, sendStatus, definitelyNotSent, canonMobile, smsName } = require('./sms.cjs');

const SMS = CFG.sms || {};
const log = (...a) => console.log(new Date().toISOString(), ...a);

const todayStr = () => new Date().toISOString().slice(0, 10);
const tpl = (k, def) => (SMS.templates && SMS.templates[k]) || def;

// Faktura kaliti (invoices.studentId: o'quvchining studentId'si YOKI eski hujjat id'si) -> { phone } va KANONIK kalit.
//   auth/sms-remind.cjs bilan BIR XIL qoida: kalit BITTA o'quvchiga mos bo'lishi shart (studentId yoki hujjat id bo'yicha).
//   Bir nechta o'quvchiga mos kalit (bir bolaning hujjat id'si boshqasining studentId'si / studentId takrori) — NOANIQ:
//   SMS yuborilmaydi (bir bolaning qarzi boshqa oilaga ketmasin; «⚠️ Sifat»da ko'rinadi).
//   Telefon: o'quvchining o'z maxfiy yozuvi (hujjat id); yo'q bo'lsa — studentId kalitli yozuv (boshqa bolaning hujjati bo'lmasa).
//   Telefon — parentPhone / parentPhone2 dan BIRINCHI YAROQLI O'zbekiston mobil raqami (auth/sms-remind bilan bir xil);
//   yaroqlisi bo'lmasa — telefon yo'q (SMS claim ham qilinmaydi: noto'g'ri raqam Eskiz xatosi deb sanalmasin).
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
    try { const { data, error } = await sb.from('sms_log').update({ ...rec, status: 'sending', attempts: n + 1, error: '' }).eq('id', id).eq('status', 'failed').eq('attempts', n).select('id');
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
const redactPhone = p => { const d = String(p || '').replace(/\D/g, ''); return d.length >= 6 ? d.slice(0, 5) + '***' + d.slice(-2) : '***'; };

// (1) YANGI FAKTURA xabarlari — oxirgi N kunda yaratilgan, to'lanmagan, amount>0.
async function runNew(eskiz, phones, dry) {
  const lookback = Number(SMS.newLookbackDays || 14);
  const since = new Date(Date.now() - lookback * 864e5).toISOString();
  let invs = [];
  try { invs = (await db.collection('invoices').where('createdAt', '>=', since).get()).docs.map(d => d.data()); }
  catch (e) { log('invoices(new) so\'rov xato:', e.message); return; }
  let sent = 0, skip = 0, fail = 0;
  for (const inv of invs) {
    if (STOP) break;
    const amt = Number(inv.amount) || 0;
    if (amt <= 0) continue;                                          // grant/0 so'mlik — xabar yo'q
    if (['paid', 'canceled', 'reversed'].includes(inv.status)) continue;
    if (AMBIG.has(inv.studentId)) { skip++; log('SMS(new) o\'tkazildi — ID to\'qnashuvi:', inv.studentId); continue; }
    const id = `${inv.id}__new`;
    const dn = await smsDone(id);
    if (dn.skip) { skip++; continue; }
    const phone = (phones[inv.studentId] || {}).phone;
    if (!phone) { skip++; continue; }
    const msg = fillTpl(tpl('new', DEF_NEW), { name: smsName(inv.studentName), month: fmtMonth(inv.month), amount: fmtSom(amt), due: fmtSom(amt) });
    if (dry) { log('[DRY new]', redactPhone(phone), '::', msg); sent++; continue; }
    // CLAIM avval (create) — allaqachon claim qilingan/yuborilgan bo'lsa o'tkazamiz (takror yo'q).
    if (!(await claimSms(id, { invoiceId: inv.id, studentId: inv.studentId || '', phone, type: 'new', message: msg, month: inv.month || '' }))) { skip++; continue; }
    const r = await sendOne(eskiz, id, phone, msg);
    if (r.ok) sent++; else { fail++; log('SMS(new) xato:', redactPhone(phone), r.status, r.error); }
  }
  log(`YANGI: ${sent} yuborildi · ${skip} o'tkazildi · ${fail} xato`);
}

// (2) QARZDORLIK eslatmasi — 10-sanadan keyin to'lanmagan; faqat reminderDays kunlari.
async function runDebt(eskiz, phones, dry, force) {
  const days = Array.isArray(SMS.reminderDays) ? SMS.reminderDays : [1, 4];   // 0=Yak,1=Dush..6=Shan
  const dow = new Date().getDay();
  if (!force && !days.includes(dow)) { log(`QARZ: bugun (dow=${dow}) eslatma kuni emas — o'tkazildi.`); return; }
  const dom = String(Number(SMS.reminderDayOfMonth || 10)).padStart(2, '0');
  const today = todayStr();
  let sent = 0, skip = 0, fail = 0;
  for (const st of ['pending', 'partial']) {
    if (STOP) break;
    let invs = [];
    try { invs = (await db.collection('invoices').where('status', '==', st).get()).docs.map(d => d.data()); }
    catch (e) { log('invoices(debt) so\'rov xato:', e.message); continue; }
    for (const inv of invs) {
      if (STOP) break;
      const due = (Number(inv.amount) || 0) - (Number(inv.paidAmount) || 0);
      if (due <= 0 || !inv.month) continue;
      if (AMBIG.has(inv.studentId)) { skip++; log('SMS(debt) o\'tkazildi — ID to\'qnashuvi:', inv.studentId); continue; }
      if (!(today > `${inv.month}-${dom}`)) continue;                // faqat 10-sanadan keyin
      const id = `${inv.id}__debt__${today}`;
      const dn = await smsDone(id);
      if (dn.skip) { skip++; continue; }
      // Bugun shu o'quvchi ota-onasiga QO'LDA eslatma («Moliya» → «Qarzdorlar» → «Eslatma») ketgan yoki ketayotgan
      //   bo'lsa (holati noaniq ham) — takrorlamaymiz (ota-onaga bir kunda 2 ta SMS ketmasin).
      const man = await getSms(`remind__${CANON[inv.studentId] || inv.studentId}__${tashkentDay()}`);
      if (man && ['sent', 'sending', 'unknown'].includes(man.status)) { skip++; continue; }
      const phone = (phones[inv.studentId] || {}).phone;
      if (!phone) { skip++; continue; }
      const msg = fillTpl(tpl('debt', DEF_DEBT), { name: smsName(inv.studentName), month: fmtMonth(inv.month), amount: fmtSom(inv.amount), due: fmtSom(due) });
      if (dry) { log('[DRY debt]', redactPhone(phone), '::', msg); sent++; continue; }
      if (!(await claimSms(id, { invoiceId: inv.id, studentId: inv.studentId || '', phone, type: 'debt', message: msg, month: inv.month || '' }))) { skip++; continue; }
      const r = await sendOne(eskiz, id, phone, msg);
      if (r.ok) sent++; else { fail++; log('SMS(debt) xato:', redactPhone(phone), r.status, r.error); }
    }
  }
  log(`QARZ: ${sent} yuborildi · ${skip} o'tkazildi · ${fail} xato`);
}

(async () => {
  if (SMS.enabled === false) { log('SMS o\'chirilgan (config.sms.enabled=false). Chiqildi.'); return; }
  const args = process.argv.slice(2);
  const dry = SMS.dryRun === true || args.includes('--dry');
  const mode = (args.find(a => !a.startsWith('--')) || 'both').toLowerCase();   // new | debt | both
  const eskiz = dry ? null : makeEskiz(SMS);
  const phones = await phoneMap();
  if (mode === 'new' || mode === 'both') await runNew(eskiz, phones, dry);
  if ((mode === 'debt' || mode === 'both') && !STOP) await runDebt(eskiz, phones, dry, mode === 'debt');
  if (STOP) { log('TO\'XTATILDI: ' + STOP); process.exitCode = 1; return; }
  log('Tugadi.' + (dry ? ' (DRY — hech narsa yuborilmadi)' : ''));
})().catch(e => { console.error('sms-worker xato:', e && e.message || e); process.exit(1); });
