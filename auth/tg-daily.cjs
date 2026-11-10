/**
 * tg-daily.cjs — Direktorga KUNLIK HISOBOT Telegram orqali (PKG-10). CRON bilan (har 15 daqiqada, flock): yuborish vaqti
 *   va kunlari — admin «Xabarnomalar» → «Kunlik hisobot» (notify_settings 'daily_report': enabled, days, hourFrom).
 *   Toshkent vaqti bilan hourFrom'dan keyingi birinchi run'da, bir kunda BIR MARTA (sms_log 'daily__<kun>__<bog'lanish>').
 *   Qabul qiluvchilar — faol Direktorlarning tasdiqlangan Telegram bog'lanishlari (admin «Xabarnomalar»dan bir martalik
 *   havola bilan ulanadi; botdagi /sozlamalar'da o'chirsa — kelmaydi).
 *   Hisobot: bugungi to'lovlar (soni, summa, usul bo'yicha; biriktirilmaganlar), qarzdorlar (1 / 2 / 3+ oy), davomat
 *   kiritilishi, kutilayotgan tasdiqlar (navbatlar bo'yicha, muddati o'tganlari), xizmatlar holati («Tizim holati»).
 *
 *   cd ~/iqror-repo/auth && node tg-daily.cjs           # vaqti kelgan bo'lsa yuboradi
 *   node tg-daily.cjs --dry                             # matnni ko'rsatadi, hech narsa yubormaydi
 *   node tg-daily.cjs --force                           # vaqt/kun tekshiruvisiz (bugun yuborilmagan bo'lsa)
 *   O'rnatish: bash install-tg-cron.sh   (README: «Telegram bot»)
 */
'use strict';
const fs = require('fs');
const path = require('path');

const PROV = { cash: 'naqd', click: 'Click', uzum: 'Uzum', payme: 'Payme', transfer: 'o‘tkazma', bank: 'bank', terminal: 'terminal', boshqa: 'boshqa' };
const fmtNum = n => Math.round(Number(n) || 0).toLocaleString('ru-RU').replace(/[\s,]/g, ' ');
const tkDay = ms => new Date((ms == null ? Date.now() : ms) + 5 * 3600e3).toISOString().slice(0, 10);
const tkHour = ms => new Date((ms == null ? Date.now() : ms) + 5 * 3600e3).getUTCHours();
const tkDow = ms => new Date(tkDay(ms) + 'T12:00:00Z').getUTCDay();

// Hisobot matni (Telegram, oddiy matn). d — director_daily(); checks — health runChecks() yoki null.
function composeDaily(d, checks) {
  d = d || {};
  const p = d.payments || {}, db = d.debt || {}, at = d.attendance || {}, pe = d.pending || {}, od = d.overdue || {};
  const day = String(d.day || '').split('-').reverse().join('.');
  const prov = Object.entries(p.byProvider || {}).sort((a, b) => Number(b[1]) - Number(a[1])).map(([k, v]) => `${PROV[k] || k} ${fmtNum(v)}`).join(' · ');
  const L = [`📊 IQROR Academy — kunlik hisobot (${day})`, ''];
  L.push(`💰 To‘lovlar: ${Number(p.count) || 0} ta · ${fmtNum(p.sum)} so‘m${prov ? ` (${prov})` : ''}`);
  // To'lovlar kassa kuni bo'yicha (admin «To‘lovlar → Hisobot» bilan bir xil): bugun kiritilib, oldingi kun sanasi bilan
  //   yozilganlari o'sha kunga tushadi — direktor ularni ko'rishi uchun alohida qator.
  const late = d.late || {};
  if (Number(late.count) > 0) L.push(`   ↩ Bugun kiritilgan, oldingi kunlar sanasi bilan: ${Number(late.count)} ta · ${fmtNum(late.sum)} so‘m`);
  if (Number(d.unmatched) > 0) L.push(`   ⚠️ O‘quvchiga biriktirilmagan: ${d.unmatched} ta — «To‘lovlar»da biriktiring`);
  L.push(`🧾 Qarzdorlar: 1 oy — ${Number(db.m1) || 0}, 2 oy — ${Number(db.m2) || 0}, 3+ oy — ${Number(db.m3) || 0}`);
  L.push(`📋 Davomat kiritilishi: ${at.rate == null ? '— (bugun dars kuni emas)' : `${String(at.rate).replace('.', ',')}% (${at.marked}/${at.required})`}`);
  const names = { bonus: '100 ball', discount: 'chegirma', sick: '«Bemor» kuni', referral: 'tavsiya', payroll: 'maosh' };
  const pend = Object.keys(names).filter(k => Number(pe[k]) > 0).map(k => `${names[k]} ${pe[k]}`).join(' · ');
  const overdue = Object.keys(names).reduce((s, k) => s + (Number(od[k]) || 0), 0);
  L.push(`✅ Kutilayotgan tasdiqlar: ${pend || 'yo‘q'}${overdue ? ` (muddati o‘tgan: ${overdue})` : ''}`);
  if (Array.isArray(checks)) {
    const bad = checks.filter(c => c && c.ok === false);
    L.push(bad.length ? `🩺 Tizim: ${bad.map(c => `❌ ${c.name}${c.info ? ' — ' + c.info : ''}`).join('; ')}` : '🩺 Tizim: hammasi ishlayapti');
  } else L.push('🩺 Tizim: tekshirilmadi');
  return L.join('\n');
}

// Reja: yoqilgan, bugun tanlangan kunlardan, soat yetgan. -> { run, reason, hour, days }
function dailyPlan(row, nowMs) {
  if (!row) return { run: false, reason: 'sozlama qatori yo‘q (bash deploy.sh)' };
  const hour = Number.isInteger(Number(row.hourFrom)) && row.hourFrom != null ? Number(row.hourFrom) : 19;
  const days = Array.isArray(row.days) ? row.days.map(Number) : [1, 2, 3, 4, 5, 6];
  if (row.enabled !== true) return { run: false, reason: 'o‘chirilgan', hour, days };
  if (!days.includes(tkDow(nowMs))) return { run: false, reason: 'bugun yuborish kuni emas', hour, days };
  if (tkHour(nowMs) < hour) return { run: false, reason: `soat ${hour}:00 dan keyin`, hour, days };
  return { run: true, reason: '', hour, days };
}

// Asosiy ish (sinovda soxta sb/tg bilan chaqiriladi). -> { sent, skipped, reason?, text? }
async function runDaily({ sb, tg, health, dry, force, now, log }) {
  log = log || ((...a) => console.log(new Date().toISOString(), ...a));
  const t = now ? now() : Date.now();
  let row = null;
  try { const { data, error } = await sb.from('notify_settings').select('*').eq('id', 'daily_report').limit(1); if (error) throw error; row = (data || [])[0] || null; }
  catch (e) { log('❌ notify_settings o‘qilmadi:', String((e && e.message) || e).slice(0, 150), '— hech narsa yuborilmadi'); return { sent: 0, skipped: 0, reason: 'settings', exit: 3 }; }
  const plan = dailyPlan(row, t);
  if (!plan.run && !force) { log('Kunlik hisobot: yo‘q —', plan.reason); return { sent: 0, skipped: 0, reason: plan.reason }; }
  // qabul qiluvchilar: faol Direktorlar, faol bog'lanish, kunlik hisobot o'chirilmagan
  const { data: links, error: le } = await sb.from('telegram_links').select('id,uid,chatId,prefs,status,kind').eq('kind', 'staff').eq('status', 'active');
  if (le) { log('❌ telegram_links o‘qilmadi:', le.message); return { sent: 0, skipped: 0, reason: 'links', exit: 1 }; }
  const uids = [...new Set((links || []).map(l => l.uid))];
  let dirs = new Set();
  if (uids.length) {
    const { data: us, error: ue } = await sb.from('users').select('id,role,status').in('id', uids);
    if (ue) { log('❌ users o‘qilmadi:', ue.message); return { sent: 0, skipped: 0, reason: 'users', exit: 1 }; }
    dirs = new Set((us || []).filter(u => u.role === 'director' && String(u.status || 'active') === 'active').map(u => u.id));
  }
  const rcpt = (links || []).filter(l => dirs.has(l.uid) && !(l.prefs && l.prefs.daily === false));
  if (!rcpt.length) { log('Kunlik hisobot: ulangan Direktor yo‘q (admin «Xabarnomalar» → «Telegramni ulash»)'); return { sent: 0, skipped: 0, reason: 'norecipients' }; }
  const { data: d, error: de } = await sb.rpc('director_daily', { p_day: tkDay(t) });
  if (de) { log('❌ director_daily xato:', de.message); return { sent: 0, skipped: 0, reason: 'rpc', exit: 1 }; }
  let checks = null;
  try { checks = health ? await health.runChecks() : null; } catch (e) { checks = null; }
  const text = composeDaily(d, checks);
  if (dry) { log('[DRY daily] qabul qiluvchilar:', rcpt.length, '\n' + text); return { sent: 0, skipped: 0, dry: true, text }; }
  let sent = 0, skipped = 0;
  for (const l of rcpt) {
    const id = `daily__${tkDay(t)}__${l.id}`;
    // bugun yuborilganmi (yoki yuborilmoqda) — takror yo'q
    const ins = await sb.from('sms_log').insert({ id, type: 'daily', status: 'sending', attempts: 1, message: text.slice(0, 1000), channel: 'telegram', phone: '' });
    if (ins.error) { skipped++; continue; }
    const r = await tg.sendMessage(l.chatId, text);
    if (r.ok) { sent++; await sb.from('sms_log').update({ status: 'sent', providerId: 'tg' }).eq('id', id); }
    else {
      await sb.from('sms_log').update({ status: 'failed', error: String(r.error || '').slice(0, 200) }).eq('id', id);
      if (r.blocked) { try { await sb.rpc('tg_blocked', { p_chat: l.chatId }); } catch (_) {} }
      log('Kunlik hisobot yetkazilmadi:', String(r.error || '').slice(0, 120));
    }
  }
  log(`Kunlik hisobot: ${sent} ta Direktorga yuborildi${skipped ? ` · ${skipped} tasiga bugun allaqachon yuborilgan` : ''}`);
  return { sent, skipped, text };
}

if (require.main === module) {
  (async () => {
    const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
    const TGC = CFG.telegram || {};
    const args = process.argv.slice(2), dry = args.includes('--dry'), force = args.includes('--force');
    if (!TGC.botToken && !dry) { console.log('Telegram sozlanmagan (config.telegram.botToken) — kunlik hisobot yuborilmaydi.'); return; }
    const { db } = require('../server/backend.js')({ ...CFG, __dir: __dirname });
    const sb = db._sb;
    const { makeTelegram } = require('../server/telegram.cjs');
    const tg = makeTelegram({ token: TGC.botToken || 'dry', apiBase: TGC.apiBase, timeoutMs: TGC.timeoutMs });
    let health = null;
    try {
      const { makeDeepHealth } = require('./health.cjs');
      const { makeEskiz } = require('../payments/sms.cjs');
      const SMS = CFG.sms || {};
      const eskiz = (SMS.enabled === false || SMS.dryRun === true) ? null : makeEskiz(SMS);
      health = makeDeepHealth({ sb, verifyUser: async () => ({ invalid: true }), eskiz, smsCfg: SMS, cfg: CFG.auth || {}, supabaseUrl: CFG.supabaseUrl, anonKey: CFG.anonKey || (CFG.auth || {}).anonKey });
    } catch (e) { console.error('health yuklanmadi:', e && e.message); }
    const r = await runDaily({ sb, tg, health, dry, force });
    if (r.exit) process.exitCode = r.exit;
  })().catch(e => { console.error('tg-daily xato:', (e && e.message) || e); process.exit(1); });
}
module.exports = { composeDaily, dailyPlan, runDaily };
