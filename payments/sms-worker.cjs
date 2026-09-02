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
const { makeEskiz } = require('./sms.cjs');

const SMS = CFG.sms || {};
const log = (...a) => console.log(new Date().toISOString(), ...a);

const DEF_NEW  = "Hurmatli ota-ona! {name} uchun {month} oy to'lovi shakllantirildi: {amount} so'm. Batafsil: iqroacademy.uz. IQROR Academy";
const DEF_DEBT = "Eslatma: {name} uchun {month} oy to'lovi hali yopilmagan (qarz: {due} so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";

const fmtSom = n => String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
const fmtMonth = m => { const p = String(m || '').split('-'); return p.length === 2 ? `${p[1]}.${p[0]}` : String(m || ''); };
const fillTpl = (t, v) => String(t || '').replace(/\{(\w+)\}/g, (_, k) => (v[k] != null ? String(v[k]) : ''));
const todayStr = () => new Date().toISOString().slice(0, 10);
const tpl = (k, def) => (SMS.templates && SMS.templates[k]) || def;

// studentId -> { phone } (maxfiy jadvaldan; parentPhone, bo'lmasa parentPhone2).
async function phoneMap() {
  const m = {};
  try {
    const snap = await db.collection('student_private').get();
    snap.docs.forEach(d => { const p = d.data() || {}; m[d.id] = { phone: p.parentPhone || p.parentPhone2 || '' }; });
  } catch (e) { log('phoneMap xato:', e.message); }
  return m;
}
const MAXTRIES = Number(SMS.maxRetries || 3);   // xato bo'lsa shuncha marta qayta uriniladi, keyin to'xtaydi
async function getSms(id) { try { const s = await db.collection('sms_log').doc(id).get(); return s.exists ? (s.data() || {}) : null; } catch (e) { return null; } }
// SMS allaqachon YUBORILGANmi (sent) yoki qayta urinishlar tugaganmi? -> {skip, attempts}
async function smsDone(id) { const p = await getSms(id); return { skip: !!(p && (p.status === 'sent' || (Number(p.attempts) || 0) >= MAXTRIES)), attempts: Number(p && p.attempts) || 0 }; }
async function logSms(id, rec) { try { await db.collection('sms_log').doc(id).set({ ...rec, createdAt: FieldValue.serverTimestamp() }); } catch (e) { log('logSms xato:', e.message); } }

// (1) YANGI FAKTURA xabarlari — oxirgi N kunda yaratilgan, to'lanmagan, amount>0.
async function runNew(eskiz, phones, dry) {
  const lookback = Number(SMS.newLookbackDays || 14);
  const since = new Date(Date.now() - lookback * 864e5).toISOString();
  let invs = [];
  try { invs = (await db.collection('invoices').where('createdAt', '>=', since).get()).docs.map(d => d.data()); }
  catch (e) { log('invoices(new) so\'rov xato:', e.message); return; }
  let sent = 0, skip = 0, fail = 0;
  for (const inv of invs) {
    const amt = Number(inv.amount) || 0;
    if (amt <= 0) continue;                                          // grant/0 so'mlik — xabar yo'q
    if (['paid', 'canceled', 'reversed'].includes(inv.status)) continue;
    const id = `${inv.id}__new`;
    const dn = await smsDone(id);
    if (dn.skip) { skip++; continue; }
    const phone = (phones[inv.studentId] || {}).phone;
    if (!phone) { skip++; continue; }
    const msg = fillTpl(tpl('new', DEF_NEW), { name: inv.studentName || '', month: fmtMonth(inv.month), amount: fmtSom(amt), due: fmtSom(amt) });
    if (dry) { log('[DRY new]', phone, '::', msg); sent++; continue; }
    const r = await eskiz.send(phone, msg);
    await logSms(id, { invoiceId: inv.id, studentId: inv.studentId || '', phone, type: 'new', message: msg, status: r.ok ? 'sent' : 'failed', attempts: dn.attempts + 1, providerId: r.id || '', error: r.ok ? '' : String(r.error || ''), month: inv.month || '' });
    if (r.ok) sent++; else { fail++; log('SMS(new) xato:', phone, r.error); }
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
    let invs = [];
    try { invs = (await db.collection('invoices').where('status', '==', st).get()).docs.map(d => d.data()); }
    catch (e) { log('invoices(debt) so\'rov xato:', e.message); continue; }
    for (const inv of invs) {
      const due = (Number(inv.amount) || 0) - (Number(inv.paidAmount) || 0);
      if (due <= 0 || !inv.month) continue;
      if (!(today > `${inv.month}-${dom}`)) continue;                // faqat 10-sanadan keyin
      const id = `${inv.id}__debt__${today}`;
      const dn = await smsDone(id);
      if (dn.skip) { skip++; continue; }
      const phone = (phones[inv.studentId] || {}).phone;
      if (!phone) { skip++; continue; }
      const msg = fillTpl(tpl('debt', DEF_DEBT), { name: inv.studentName || '', month: fmtMonth(inv.month), amount: fmtSom(inv.amount), due: fmtSom(due) });
      if (dry) { log('[DRY debt]', phone, '::', msg); sent++; continue; }
      const r = await eskiz.send(phone, msg);
      await logSms(id, { invoiceId: inv.id, studentId: inv.studentId || '', phone, type: 'debt', message: msg, status: r.ok ? 'sent' : 'failed', attempts: dn.attempts + 1, providerId: r.id || '', error: r.ok ? '' : String(r.error || ''), month: inv.month || '' });
      if (r.ok) sent++; else { fail++; log('SMS(debt) xato:', phone, r.error); }
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
  if (mode === 'debt' || mode === 'both') await runDebt(eskiz, phones, dry, mode === 'debt');
  log('Tugadi.' + (dry ? ' (DRY — hech narsa yuborilmadi)' : ''));
})().catch(e => { console.error('sms-worker xato:', e && e.message || e); process.exit(1); });
