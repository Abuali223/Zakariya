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
 * Ishga tushirish:
 *   cd .../payments && node sms-worker.cjs auto      # TAVSIYA (cron har 15 daqiqada, flock bilan): qaysi tur, qaysi kun/soat
 *                                                    #   va qaysi matn — admin «Sozlamalar → 📱 Xabarnomalar»dan (notify_settings).
 *                                                    #   Sozlamani o'qib bo'lmasa — HECH NARSA yubormaydi (chiqish kodi 3).
 *   node sms-worker.cjs                              # (eski) ikkalasi config.json bo'yicha (debt faqat reminderDays'da)
 *   node sms-worker.cjs new                          # (eski) faqat yangi faktura xabarlari
 *   node sms-worker.cjs debt                         # (eski) faqat qarzdorlik (kun tekshiruvisiz majburiy)
 *   node sms-worker.cjs auto --dry                   # sinov: yubormaydi, faqat log qiladi
 *
 * Sozlash: config.json -> "sms" bloki (Eskiz ulanishi; config.example.json'ga qarang). auto rejimida yoqish/o'chirish, kunlar,
 *   soatlar va matn — notify_settings'dan; config.json'dagi templates/sendHours/reminderDays — faqat sozlama bo'sh bo'lsa.
 * ⚠️ CRON yozuvlari ustma-ust tushmasin (bir vaqtda 2 nusxa ishlamasin) — flock ishlating.
 *
 * TELEGRAM (PKG-10, D4): ota-ona botga ulangan va raqami kartadagi raqam bilan tasdiqlangan bo'lsa (tg_recipients_bulk) —
 *   xabar AVVAL Telegram orqali; yetkazilmasa (bloklagan/xato) — SMS (faqat +998, tinch soat, kuniga 1 SMS — avvalgi qoidalar).
 *   Bitta xabar id (sms_log) — qaysi kanal bilan ketsa ham bitta qator (kanal: channel). Ota-ona botdagi /sozlamalar'da turni
 *   o'chirgan bo'lsa — o'sha tur Telegram'da kelmaydi (SMS qoidasi avvalgidek).
 *   Navbat (notify_queue — baza trigger yozadi): «To'lov qabul qilindi» (Telegram; SMS faqat «Xabarnomalar»da faol SMS matni
 *   bo'lsa) va sinf e'loni (faqat Telegram). Tur o'chiq bo'lsa — navbatdagilar o'tkaziladi (keyin yoqilganda eski xabar ketmaydi).
 *   Bot kaliti: shu config.json'dagi «telegram» bloki yoki ../auth/config.json'dagisi; yo'q bo'lsa — faqat SMS.
 */
const fs = require('fs');
const path = require('path');
const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
const { db, FieldValue } = require('../server/backend.js')({ ...CFG, __dir: __dirname });
const { makeEskiz, DEF_NEW, DEF_DEBT, DEF_TG, fillTpl, fmtSom, fmtMonth, tashkentDay, tashkentDayStartISO, tashkentDow, sendWindow, inSendWindow, inWindow, orderDebtCandidates, sendStatus, definitelyNotSent, canonMobile, smsName, resolveAutoPlan } = require('./sms.cjs');
const { makeTelegram } = require('../server/telegram.cjs');
const { composeSms, smsSom, smsMonths } = require('./eskiz-template.cjs');

const SMS = CFG.sms || {};
const log = (...a) => console.log(new Date().toISOString(), ...a);

const tpl = (k, def) => (SMS.templates && SMS.templates[k]) || def;

// ---- Telegram (PKG-10) ----
function tgConfig() {
  if (CFG.telegram && CFG.telegram.botToken) return CFG.telegram;
  try { const a = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'auth', 'config.json'), 'utf8')); if (a && a.telegram && a.telegram.botToken) return a.telegram; } catch (_) {}
  return null;
}
const TGC = tgConfig();
const TG = (TGC && TGC.enabled !== false) ? makeTelegram({ token: TGC.botToken, apiBase: TGC.apiBase, timeoutMs: TGC.timeoutMs, perSecond: TGC.perSecond }) : null;
const TGMAP = new Map(), TGBLOCK = new Set();     // o'quvchi kaliti (studentId / hujjat id) -> [{ chat, link, prefs, lang }]
async function loadTg() {
  const sb = db._sb; if (!TG || !sb) return;
  try {
    const { data, error } = await sb.rpc('tg_recipients_bulk'); if (error) throw error;
    (data || []).forEach(r => { [r.student_key, r.student_doc].filter(Boolean).forEach(k => { const a = TGMAP.get(k) || [];
      if (!a.some(x => x.chat === r.chat_id)) a.push({ chat: r.chat_id, link: r.link_id, prefs: r.prefs || {}, lang: r.lang === 'ru' ? 'ru' : 'uz' }); TGMAP.set(k, a); }); });
    log(`Telegram: ${new Set((data || []).map(r => r.chat_id)).size} ta tasdiqlangan chat`);
  } catch (e) { log('⚠️ Telegram qabul qiluvchilari o\'qilmadi (' + String((e && e.message) || e).slice(0, 150) + ') — bu run\'da faqat SMS.'); }
}
const tgFor = (key, pref) => (TGMAP.get(key) || []).filter(x => !TGBLOCK.has(x.chat) && !(x.prefs && x.prefs[pref] === false));
const tgText = (custom, type, lang, vals) => fillTpl(custom || DEF_TG[lang === 'ru' ? 'ru' : 'uz'][type], vals);
async function tgBlocked(chat) { TGBLOCK.add(chat); try { const { error } = await db._sb.rpc('tg_blocked', { p_chat: chat }); if (error) throw error; } catch (e) { log('tg_blocked xato:', (e && e.message) || e); } }
let TGN = 0;

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
//   WIN — joriy yuborish oynasi: eski rejimlarda config.json sendHours; auto rejimda har tur uchun notify_settings'dan.
let QUIET = false;
let WIN = sendWindow(SMS);
const utcH = h => String((((h - 5) % 24) + 24) % 24).padStart(2, '0');   // Toshkent soati -> UTC soati (cron uchun maslahat)
const quietNow = dry => !dry && !inWindow(WIN);

// Faktura kaliti (invoices.studentId: o'quvchining studentId'si YOKI eski hujjat id'si) -> { phone } va KANONIK kalit.
//   auth/sms-remind.cjs bilan BIR XIL qoida: kalit BITTA o'quvchiga mos bo'lishi shart (studentId yoki hujjat id bo'yicha).
//   Bir nechta o'quvchiga mos kalit (bir bolaning hujjat id'si boshqasining studentId'si / studentId takrori) — NOANIQ:
//   SMS yuborilmaydi (bir bolaning qarzi boshqa oilaga ketmasin; «⚠️ Sifat»da ko'rinadi).
//   Telefon: o'quvchining o'z maxfiy yozuvi (hujjat id); yo'q bo'lsa — studentId kalitli yozuv (boshqa bolaning hujjati bo'lmasa).
//   Telefon — parentPhone / parentPhone2 dan BIRINCHI O'ZBEKISTON mobil raqami (auth/sms-remind bilan bir xil). SMS FAQAT
//   O'zbekiston raqamlariga: otaniki chet el raqami bo'lsa — onaniki (O'zbekiston) olinadi; O'zbekiston raqami umuman
//   bo'lmasa — telefon yo'q (SMS claim ham qilinmaydi: noto'g'ri/chet el raqami Eskiz xatosi deb sanalmasin).
//   KANONIK kalit (studentId || id) — qo'lda eslatma qulfi (remind__<kanonik>__<sana>) shu bilan tekshiriladi.
const CANON = {}; const AMBIG = new Set(); const NAMES = {};
async function phoneMap() {
  const priv = {}, m = {};
  try {
    const snap = await db.collection('student_private').get();
    snap.docs.forEach(d => { const p = d.data() || {}; priv[d.id] = canonMobile(p.parentPhone) || canonMobile(p.parentPhone2) || ''; });
  } catch (e) { log('phoneMap xato:', e.message); }
  try {
    const rows = (await db.collection('students').get()).docs.map(d => ({ id: d.id, sid: String((d.data() || {}).studentId || '').trim(), name: String((d.data() || {}).name || '').trim() }));
    const idSet = new Set(rows.map(r => r.id)), byId = {}, byKey = {};
    rows.forEach(r => { byId[r.id] = r; [r.sid, r.id].filter(Boolean).forEach(k => { (byKey[k] = byKey[k] || new Set()).add(r.id); }); });
    Object.entries(byKey).forEach(([k, ids]) => {
      if (ids.size > 1) { AMBIG.add(k); return; }
      const r = byId[[...ids][0]];
      CANON[k] = r.sid || r.id; NAMES[k] = r.name;
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
// Telegram orqali yuborish — xabar id (sms_log) bitta: avval claim (kanal 'telegram'), kamida bitta chatga yetsa — 'sent'.
//   Hech biriga yetmasa — qator 'failed' (REJ — aniq ketmagan) bo'ladi va chaqiruvchi SMS'ga o'tadi: claimSms o'sha qatorni
//   qayta oladi (urinishlar ikki kanal bo'yicha birga sanaladi, MAXTRIES gacha). -> 'sent' | 'skip' | 'fallback'
async function deliverTg(id, rec, recips, textOf, dry) {
  if (dry) { recips.forEach(r => log(`[DRY tg ${rec.type}]`, 'chat …' + String(r.chat).slice(-3), '::', textOf(r.lang))); TGN++; return 'sent'; }
  if (!(await claimSms(id, Object.assign({}, rec, { phone: '', message: textOf('uz'), channel: 'telegram' })))) return 'skip';
  let ok = 0; const errs = [];
  for (const r of recips) {
    const res = await TG.sendMessage(r.chat, textOf(r.lang));
    if (res.ok) ok++; else { errs.push(String(res.error || 'xato').slice(0, 120)); if (res.blocked) await tgBlocked(r.chat); }
  }
  if (ok) { await markSms(id, { status: 'sent', providerId: `tg:${ok}/${recips.length}`, error: errs.join('; ').slice(0, 300) }); TGN++; return 'sent'; }
  await markSms(id, { status: 'failed', error: REJ + 'telegram: ' + errs.join('; ').slice(0, 250) });
  log(`Telegram yetkazilmadi (${rec.type}) — SMS'ga o'tiladi:`, errs.join('; ').slice(0, 200));
  return 'fallback';
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
//   o (auto rejim): { since — shu vaqtdan keyin yaratilganlar (yoqilgan vaqtdan oldingisi emas), template — faol matn }.
async function runNew(eskiz, phones, dry, o) {
  o = o || {};
  const lookback = Number(SMS.newLookbackDays || 14);
  const since = o.since || new Date(Date.now() - lookback * 864e5).toISOString();
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
    const tgr = TG ? tgFor(inv.studentId, 'invoice') : [];
    if (tgr.length) {
      const v = { name: String(inv.studentName || '').trim() || 'o‘quvchi', month: fmtMonth(inv.month), amount: fmtSom(amt), due: fmtSom(amt) };
      const out = await deliverTg(id, { invoiceId: inv.id, studentId: inv.studentId || '', type: 'new', month: inv.month || '' }, tgr, lang => tgText(o.tgTemplate, 'new', lang, v), dry);
      if (out === 'sent') { sent++; continue; }
      if (out === 'skip') { skip++; continue; }
    }
    const phone = (phones[inv.studentId] || {}).phone;
    if (!phone) { skip++; continue; }
    if (SENT_TODAY.has(phone)) { later++; continue; }               // bugun shu raqamga SMS ketgan — ertaga (lookback ichida)
    const msg = smsText(o.template || tpl('new', DEF_NEW), { name: smsName(inv.studentName), month: fmtMonth(inv.month), amount: smsSom(amt), due: smsSom(amt) });
    if (dry) { SENT_TODAY.add(phone); log('[DRY new]', redactPhone(phone), '::', msg); sent++; continue; }
    // CLAIM avval (create) — allaqachon claim qilingan/yuborilgan bo'lsa o'tkazamiz (takror yo'q).
    if (!(await claimSms(id, { invoiceId: inv.id, studentId: inv.studentId || '', phone, type: 'new', message: msg, month: inv.month || '', channel: 'sms' }))) { skip++; continue; }
    SENT_TODAY.add(phone);
    const r = await sendOne(eskiz, id, phone, msg);
    if (r.ok) sent++; else { fail++; log('SMS(new) xato:', redactPhone(phone), r.status, r.error); }
  }
  log(`YANGI: ${sent} yuborildi · ${skip} o'tkazildi · ${later} keyingi kunga (bugun shu raqamga SMS ketgan) · ${fail} xato`);
}

// (2) QARZDORLIK eslatmasi — 10-sanadan keyin to'lanmagan; faqat reminderDays kunlari.
//   Har O'QUVCHI uchun bitta SMS: barcha qarz oylari (smsMonths) + jami qarz (qo'lda «Eslatma» bilan bir xil). sms_log id —
//   eng eski qarz fakturasi: "<invoiceId>__debt__<sana>" (kuniga bitta; takror yo'q).
//   o (auto rejim): { days, dayOfMonth, template } — notify_settings'dan.
async function runDebt(eskiz, phones, dry, force, o) {
  o = o || {};
  const days = Array.isArray(o.days) ? o.days : (Array.isArray(SMS.reminderDays) ? SMS.reminderDays : [1, 4]);   // 0=Yak,1=Dush..6=Shan
  const dow = tashkentDow();                                        // Toshkent kuni (server UTC bo'lsa ham)
  if (!force && !days.includes(dow)) { log(`QARZ: bugun (dow=${dow}) eslatma kuni emas — o'tkazildi.`); return; }
  const dom = String(Number(o.dayOfMonth || SMS.reminderDayOfMonth || 10)).padStart(2, '0');
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
    const tgr = TG ? tgFor(inv.studentId, 'debt') : [];
    if (tgr.length) {
      const v = { name: String(c.name || inv.studentName || '').trim() || 'o‘quvchi', month: c.months.map(fmtMonth).join(', '), amount: fmtSom(c.due), due: fmtSom(c.due) };
      const out = await deliverTg(id, { invoiceId: inv.id, studentId: inv.studentId || '', type: 'debt', month: c.months[c.months.length - 1] || inv.month || '' }, tgr, lang => tgText(o.tgTemplate, 'debt', lang, v), dry);
      if (out === 'sent') { sent++; continue; }
      if (out === 'skip') { skip++; continue; }
    }
    const phone = (phones[inv.studentId] || {}).phone;
    if (!phone) { skip++; continue; }
    if (SENT_TODAY.has(phone)) { later++; continue; }               // bugun shu raqamga SMS ketgan (aka-uka / yangi faktura)
    const msg = smsText(o.template || tpl('debt', DEF_DEBT), { name: smsName(c.name || inv.studentName), month: smsMonths(c.months), amount: smsSom(c.due), due: smsSom(c.due) });
    if (dry) { SENT_TODAY.add(phone); log('[DRY debt]', redactPhone(phone), '::', msg); sent++; continue; }
    if (!(await claimSms(id, { invoiceId: inv.id, studentId: inv.studentId || '', phone, type: 'debt', message: msg, month: c.months[c.months.length - 1] || inv.month || '', channel: 'sms' }))) { skip++; continue; }
    SENT_TODAY.add(phone);
    const r = await sendOne(eskiz, id, phone, msg);
    if (r.ok) sent++; else { fail++; log('SMS(debt) xato:', redactPhone(phone), r.status, r.error); }
  }
  log(`QARZ: ${sent} yuborildi · ${skip} o'tkazildi · ${later} bitta raqamga kuniga 1 ta qoidasi bilan qoldirildi (aka-uka — keyingi eslatma kunida) · ${fail} xato`);
  if (quietLeft) log(`⚠️ QARZ: tinch soat boshlandi — qolgan ${quietLeft} ta o'quvchiga BUGUNGI qarz eslatmasi yuborilmaydi (keyingi eslatma kunida ketadi). Qarz cron'ini ertaroq (sendHours ichida) qo'ying.`);
}

// (3) NAVBAT (notify_queue): «To'lov qabul qilindi» va sinf e'loni. Tur o'chiq — 'skipped' (keyin yoqilganda eski xabar
//   ketmaydi); tinch soat — navbatda qoladi; 3 kundan eskisi — 'skipped'. To'lov: Telegram, yetmasa — SMS faqat faol SMS matni
//   bo'lsa (+998, kuniga 1 SMS). E'lon — faqat Telegram (SMS'ga emas).
const tkDate = v => { const d = new Date(v || Date.now()); return isNaN(d) ? '' : new Date(d.getTime() + 5 * 3600e3).toISOString().slice(0, 10).split('-').reverse().join('.'); };
async function queuePending() {
  const sb = db._sb; if (!sb) return [];
  try { const { data, error } = await sb.from('notify_queue').select('*').eq('status', 'pending').order('createdAt', { ascending: true }).limit(300); if (error) throw error; return data || []; }
  catch (e) { log('⚠️ Xabar navbati (notify_queue) o\'qilmadi:', String((e && e.message) || e).slice(0, 150)); return []; }
}
async function markQueue(q, status, note) {
  try { const { error } = await db._sb.from('notify_queue').update({ status, error: String(note || '').slice(0, 300), attempts: (Number(q.attempts) || 0) + 1, processedAt: new Date().toISOString() }).eq('id', q.id).eq('status', 'pending'); if (error) throw error; }
  catch (e) { log('notify_queue yangilanmadi:', (e && e.message) || e); }
}
async function runQueue(eskiz, phones, dry, plan, rows) {
  let tg = 0, sms = 0, skipN = 0, laterN = 0, failN = 0;
  for (const q of rows) {
    if (STOP) break;
    const P = q.type === 'payment' ? plan.payment : plan.announce;
    if (!P || !P.enabled) { if (!dry) await markQueue(q, 'skipped', 'tur o‘chirilgan'); skipN++; continue; }
    if (!P.inWindow && !dry) { laterN++; continue; }                       // tinch soat — keyingi run
    if (Date.now() - Date.parse(q.createdAt || 0) > 3 * 864e5) { if (!dry) await markQueue(q, 'skipped', 'eskirgan (3 kundan oshgan)'); skipN++; continue; }
    const pl = q.payload || {};
    if (q.type === 'announce') {
      if (!TG) { if (!dry) await markQueue(q, 'skipped', 'Telegram sozlanmagan'); skipN++; continue; }
      let rec = [];
      try { const { data, error } = await db._sb.rpc('tg_announce_recipients', { p_keys: pl.classKeys || [] }); if (error) throw error; rec = data || []; }
      catch (e) { if ((Number(q.attempts) || 0) >= 2) { if (!dry) await markQueue(q, 'failed', String((e && e.message) || e)); failN++; } laterN++; continue; }
      rec = rec.filter(r => !TGBLOCK.has(r.chat_id) && !(r.prefs && r.prefs.announce === false));
      const text = `📢 ${String(pl.title || '').trim()}${pl.body ? '\n' + String(pl.body).trim() : ''}`.slice(0, 3800);
      if (dry) { log(`[DRY tg announce] ${rec.length} ta chat ::`, text.split('\n')[0]); tg += rec.length; continue; }
      let ok = 0;
      for (const r of rec) { const res = await TG.sendMessage(r.chat_id, text); if (res.ok) ok++; else if (res.blocked) await tgBlocked(r.chat_id); }
      await markQueue(q, 'done', `${ok}/${rec.length} ta chatga yuborildi`); tg += ok; continue;
    }
    // payment
    const sid = String(pl.studentId || ''), amt = Number(pl.amount) || 0;
    if (!sid || amt <= 0 || AMBIG.has(sid)) { if (!dry) await markQueue(q, 'skipped', AMBIG.has(sid) ? 'ID to‘qnashuvi' : 'o‘quvchi/summa yo‘q'); skipN++; continue; }
    const id = `pay__${q.ref || q.id}`;
    const dn = await smsDone(id);
    if (dn.skip) { if (!dry) await markQueue(q, 'done', 'avval yuborilgan'); continue; }
    const v = { name: NAMES[sid] || NAMES[CANON[sid]] || 'o‘quvchi', amount: fmtSom(amt), due: fmtSom(amt), date: tkDate(pl.at || q.createdAt), month: '' };
    const vs = Object.assign({}, v, { name: smsName(v.name), amount: smsSom(amt), due: smsSom(amt) });   // SMS (Eskiz shabloni) uchun
    const tgr = TG ? tgFor(sid, 'payment') : [];
    let out = '';
    if (tgr.length) {
      out = await deliverTg(id, { studentId: sid, type: 'payment', month: '' }, tgr, lang => tgText(P.tgTemplate, 'payment', lang, v), dry);
      if (out === 'sent') { tg++; if (!dry) await markQueue(q, 'done', 'Telegram'); continue; }
      if (out === 'skip') { if (!dry) await markQueue(q, 'done', 'avval yuborilgan'); continue; }
    }
    const phone = (phones[sid] || {}).phone;
    if (!P.smsTemplate || !phone || !eskiz && !dry) { if (!dry) await markQueue(q, out === 'fallback' ? 'failed' : 'skipped', out === 'fallback' ? 'Telegram yetkazilmadi; SMS matni/raqami yo‘q' : (!P.smsTemplate ? 'Telegram ulanmagan; SMS matni yo‘q' : 'O‘zbekiston raqami yo‘q')); skipN++; continue; }
    if (SENT_TODAY.has(phone)) { if (!dry) await markQueue(q, 'skipped', 'bugun shu raqamga SMS ketgan'); skipN++; continue; }
    const msg = smsText(P.smsTemplate, vs);
    if (dry) { SENT_TODAY.add(phone); log('[DRY payment]', redactPhone(phone), '::', msg); sms++; continue; }
    if (!(await claimSms(id, { studentId: sid, phone, type: 'payment', message: msg, month: '', channel: 'sms' }))) { await markQueue(q, 'done', 'avval yuborilgan'); continue; }
    SENT_TODAY.add(phone);
    const r = await sendOne(eskiz, id, phone, msg);
    if (r.ok) { sms++; await markQueue(q, 'done', 'SMS'); } else { failN++; await markQueue(q, 'failed', 'SMS: ' + (r.error || r.status)); }
  }
  log(`NAVBAT: Telegram ${tg} · SMS ${sms} · ${skipN} o'tkazildi · ${laterN} keyinga · ${failN} xato`);
}

// auto rejim: notify_settings (service_role) -> reja. O'qib bo'lmasa — null (chaqiruvchi HECH NARSA yubormaydi, kod 3).
async function loadAutoPlan(dry) {
  const sb = db._sb;
  if (!sb) { log('❌ auto rejimi Supabase (service_role) ulanishini talab qiladi — HECH NARSA yuborilmadi.'); return null; }
  let rows = null;
  try { const { data, error } = await sb.from('notify_settings').select('*'); if (error) throw error; rows = data; }
  catch (e) { log('❌ Xabarnoma sozlamalari (notify_settings) o\'qilmadi: ' + String((e && e.message) || e).slice(0, 200) + ' — HECH NARSA yuborilmadi (migratsiya: bash deploy.sh).'); return null; }
  const plan = resolveAutoPlan(rows, Date.now(), SMS, { ignoreWindow: dry });
  if (!plan.ok) { log('❌ ' + plan.error + ' — HECH NARSA yuborilmadi.'); return null; }
  const st = (p, nm) => p.run ? `${nm}: HA (matn: ${p.tplSource === 'settings' ? 'Sozlamalar' : p.tplSource === 'config' ? 'config.json' : 'standart'})` : `${nm}: yo'q — ${p.reason}`;
  log('AUTO: ' + st(plan.new, 'yangi faktura') + ' · ' + st(plan.debt, 'qarz eslatmasi')
    + (plan.payment && plan.payment.enabled ? ' · to‘lov xabari: HA' : '') + (plan.announce && plan.announce.enabled ? ' · sinf e’loni (Telegram): HA' : '') + (TG ? ' · Telegram: ulangan' : ''));
  return plan;
}

(async () => {
  if (SMS.enabled === false) { log('SMS o\'chirilgan (config.sms.enabled=false). Chiqildi.'); return; }
  const args = process.argv.slice(2);
  const dry = SMS.dryRun === true || args.includes('--dry');
  const mode = (args.find(a => !a.startsWith('--')) || 'both').toLowerCase();   // auto | new | debt | both
  // auto: avval sozlama (arzon) — bu run'da yuboriladigan tur bo'lmasa Eskiz'ga ham murojaat qilinmaydi.
  let plan = null, queue = [];
  if (mode === 'auto') {
    plan = await loadAutoPlan(dry);
    if (!plan) { process.exitCode = 3; return; }
    queue = await queuePending();
    // Navbatda faqat o'chiq turlar bo'lsa — ular 'skipped' qilinadi (sinovda — tegilmaydi) va boshqa ish bo'lmasa chiqiladi.
    const qOn = q => !!((q.type === 'payment' ? plan.payment : plan.announce) || {}).enabled;
    if (!plan.new.run && !plan.debt.run && !queue.some(qOn)) {
      if (!dry) for (const q of queue) await markQueue(q, 'skipped', 'tur o‘chirilgan');
      log('Tugadi (bu run’da yuboriladigan xabar turi yo‘q).'); return;
    }
  }
  const eskiz = dry ? null : makeEskiz(SMS);
  // Naqshlar faqat O'QILADI (GET) — sinov (--dry) rejimida ham, kalit bo'lsa: logdagi matn haqiqatda ketadigan bilan bir xil.
  const reader = eskiz || ((SMS.eskizEmail || SMS.email || SMS.token) ? makeEskiz(SMS) : null);
  if (reader && typeof reader.templates === 'function') {
    try { const r = await reader.templates(); if (r && r.ok) APPROVED = r.list; else log('Eskiz shablonlari o\'qilmadi:', (r && r.error) || ''); }
    catch (e) { log('Eskiz shablonlari xato:', (e && e.message) || e); }
  }
  if (plan) {
    await loadSentToday();
    const phones = await phoneMap();
    await loadTg();
    if (plan.new.run) {
      WIN = plan.new.window;
      if (dry && !inWindow(WIN)) log(`(DRY) yangi faktura: hozir tinch soat — haqiqiy rejimda yuborilmasdi.`);
      await runNew(eskiz, phones, dry, { since: plan.new.since, template: plan.new.template, tgTemplate: plan.new.tgTemplate });
    }
    if (plan.debt.run && !STOP) {
      QUIET = false; WIN = plan.debt.window;
      if (dry && !inWindow(WIN)) log(`(DRY) qarz eslatmasi: hozir tinch soat — haqiqiy rejimda yuborilmasdi.`);
      await runDebt(eskiz, phones, dry, false, { days: plan.debt.days, dayOfMonth: plan.debt.dayOfMonth, template: plan.debt.template, tgTemplate: plan.debt.tgTemplate });
    }
    if (queue.length && !STOP) { QUIET = false; await runQueue(eskiz, phones, dry, plan, queue); }
    if (TG && TGN) log(`Telegram orqali: ${TGN} ta xabar`);
    if (STOP) { log('TO\'XTATILDI: ' + STOP); process.exitCode = 1; return; }
    if (QUIET) { log('TINCH SOAT boshlandi — qolgan xabarlar keyingi ish vaqtidagi run\'da ketadi.'); return; }
    log('Tugadi.' + (dry ? ' (DRY — hech narsa yuborilmadi)' : ''));
    return;
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
