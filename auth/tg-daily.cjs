/**
 * tg-daily.cjs — Direktorga KUNLIK HISOBOT Telegram orqali (PKG-10). CRON bilan (har 15 daqiqada, flock): yuborish vaqti
 *   va kunlari — admin «Xabarnomalar» → «Kunlik hisobot» (notify_settings 'daily_report': enabled, days, hourFrom).
 *   Toshkent vaqti bilan hourFrom'dan keyingi birinchi run'da, bir kunda BIR MARTA (sms_log 'daily__<kun>__<bog'lanish>').
 *   Kunlar standarti (qator kunlarsiz bo'lsa) — Du–Ju: maktab dars kunlari (app.school_days), egasi qarori «du–ju» (A2-02).
 *   Yetkazilmasa (A6-05): ANIQ yetkazilmagan urinish (ulanishdan OLDINGI tarmoq xatosi — DNS, ulanish rad etildi, tarmoq / manzil
 *   yo'q, ulanish muddati, sertifikat; Telegram 5xx; 429 kutishdan keyin ham) — keyingi run'larda qayta yuboriladi (jami MAXTRIES
 *   marta, shartli claim — parallel run'dan bittasi); NOANIQ natija (javob muddati — timeout, ulanishdan keyin uzilgan tarmoq, 2xx
 *   javobning tanasi o'qilmagan — xabar yetgan bo'lishi mumkin; server/telegram.cjs timeout:true) va bloklangan chat — qayta
 *   yuborilmaydi: Direktorga ikki marta ketmaydi. Oxirgi (MAXTRIES-) urinish ham yetkazilmasa — log'da shu aytiladi.
 *   Qabul qiluvchilar — faol Direktorlarning tasdiqlangan Telegram bog'lanishlari (admin «Xabarnomalar»dan bir martalik
 *   havola bilan ulanadi; botdagi /sozlamalar'da o'chirsa — kelmaydi).
 *   Hisobot: bugungi to'lovlar (soni, summa, usul bo'yicha), OLDINGI hisobotdan keyin tushgan to'lovlar (kechqurun, dam olish va
 *   hisobot yuborilmagan kunlar — kassa kuni bo'yicha; A6-01: oyna oldingi muvaffaqiyatli hisobot ma'lumoti olingan paytdan —
 *   director_daily 'asOf' shu yerda jurnal qatori "createdAt"iga yoziladi), bugun orqa sana bilan kiritilganlar, BARCHA
 *   biriktirilmagan to'lovlar (A6-07), qarzdorlar (1 / 2 / 3+ oy; ketgan / muzlatilganlarning eski qarzi ham — A6-03), davomat
 *   kiritilishi, kutilayotgan tasdiqlar (navbatlar bo'yicha, muddati o'tganlari), kassa (kun jamlari, sanash, nazorat qatori —
 *   kassa moduli ishlatilayotgan bo'lsa), xizmatlar holati («Tizim holati»). Sarlavhada — «HH:MM holatiga».
 *
 *   cd ~/iqror-repo/auth && node tg-daily.cjs           # vaqti kelgan bo'lsa yuboradi
 *   node tg-daily.cjs --dry                             # matnni ko'rsatadi, hech narsa yubormaydi
 *   node tg-daily.cjs --force                           # vaqt/kun tekshiruvisiz (bugun yuborilmagan bo'lsa)
 *   O'rnatish: bash install-tg-cron.sh   (README: «Telegram bot»)
 */
'use strict';
const fs = require('fs');
const path = require('path');

const PROV = { cash: 'naqd', click: 'Click', uzum: 'Uzum', payme: 'Payme', transfer: 'o‘tkazma', bank: 'bank', terminal: 'terminal', offset: 'o‘zaro hisob', boshqa: 'boshqa' };
const fmtNum = n => Math.round(Number(n) || 0).toLocaleString('ru-RU').replace(/[\s,]/g, ' ');
const tkDay = ms => new Date((ms == null ? Date.now() : ms) + 5 * 3600e3).toISOString().slice(0, 10);
const tkHour = ms => new Date((ms == null ? Date.now() : ms) + 5 * 3600e3).getUTCHours();
const tkDow = ms => new Date(tkDay(ms) + 'T12:00:00Z').getUTCDay();

const dmy = s => String(s || '').slice(0, 10).split('-').reverse().join('.');
const dm = s => String(s || '').slice(5, 10).split('-').reverse().join('.');   // 'YYYY-MM-DD' -> 'DD.MM'
const tkHm = s => { const ms = Date.parse(String(s || '')); return Number.isFinite(ms) ? new Date(ms + 5 * 3600e3).toISOString().slice(11, 16) : ''; };
const tkDmyHm = s => { const ms = Date.parse(String(s || '')); return Number.isFinite(ms) ? `${dmy(tkDay(ms))} ${new Date(ms + 5 * 3600e3).toISOString().slice(11, 16)}` : ''; };
// Qayta urinish (A6-05): sms_log.error shu prefiks bilan — urinish ANIQ yetkazilmagan, keyingi run qayta yuboradi (jami MAXTRIES marta).
const RETRY = 'retry: ';
const MAXTRIES = 3;
// Kassa bloki (0–3 qator) va nazorat qatori. k — director_daily().kassa (yo'q bo'lsa — bo'sh ro'yxat).
//   Smena topshirishdagi sanash farqlari (handoverDiffs — kassa moduli acc-6) kunni yopishdagi farq yonida; bo'lmasa — matn avvalgidek.
function kassaLines(k) {
  if (!k || typeof k !== 'object') return [];
  const L = [], kd = k.day, c = k.control || {}, n = v => Number(v) || 0;
  const hds = a => (Array.isArray(a) ? a : []).map(n).filter(x => x !== 0);
  if (kd) {
    const st = { open: 'ochiq', closed: 'yopilgan', verified: 'tekshirilgan' }[kd.status] || String(kd.status || '');
    L.push(`🏦 Kassa (${st}): kun boshi ${fmtNum(kd.opening)} + kirim ${fmtNum(kd.receipts)} (${n(kd.n1)} ta) − chiqim ${fmtNum(kd.payouts)} (${n(kd.n2)} ta) = ${fmtNum(kd.closing)} so‘m`);
    const dTxt = x => x === 0 ? 'farq yo‘q' : x < 0 ? `⚠️ KAMOMAD ${fmtNum(-x)} so‘m` : `⚠️ ortiqcha ${fmtNum(x)} so‘m`;
    const hd = hds(kd.handoverDiffs), hTxt = hd.length ? ` · smena topshirishda: ${hd.map(dTxt).join(', ')}` : '';
    if (kd.status === 'open') L.push('   ⏳ Kun hali yopilmagan — pul sanalmagan' + hTxt);
    else {
      const df = n(kd.diff);
      L.push(`   Sanaldi: ${fmtNum(kd.counted)} so‘m · ${hd.length ? 'kunni yopishda: ' : ''}${dTxt(df)}${hTxt}`);
    }
    const tr = kd.transfers || {};
    if (n(tr.inAmount) > 0 || n(tr.outAmount) > 0) L.push(`   Bank (ichki o‘tkazma): olindi ${fmtNum(tr.inAmount)} · topshirildi ${fmtNum(tr.outAmount)} so‘m`);
  } else L.push(`🏦 Kassa: bugun harakat yo‘q · qoldiq ${fmtNum(k.balance)} so‘m`);
  // nazorat qatori: moslik, ochiq kun, bekor qilishlar va farq — doim; qolganlari — faqat bor bo'lsa
  const w = [];
  w.push(n(c.reconcile) > 0 ? `⚠️ moslik buzilgan: ${n(c.reconcile)} ta` : (k.live === false ? 'moslik — kassa hali ishga tushmagan' : 'moslik ✓'));
  w.push(c.staleOpenDay ? `⚠️ yopilmagan kun: ${dmy(c.staleOpenDay)}` : 'yopilmagan o‘tgan kun yo‘q');
  w.push(`bekor qilingan: ${n(c.voids)}`);
  const sgd = v => `${v > 0 ? '+' : '−'}${fmtNum(Math.abs(v))}`, chd = hds(c.handoverDiffs);
  if (!chd.length) w.push(n(c.diff) === 0 ? 'farq yo‘q' : `⚠️ farq: ${n(c.diff) > 0 ? '+' : '−'}${fmtNum(Math.abs(n(c.diff)))}`);
  else w.push(`⚠️ farq: ${[n(c.diff) ? `yopishda ${sgd(n(c.diff))}` : '', ...chd.map(x => `smenada ${sgd(x)}`)].filter(Boolean).join(', ')}`);
  if (n(c.undecidedShortages) > 0) w.push(`⚠️ qarorsiz kamomad: ${n(c.undecidedShortages)}`);
  if (n(c.unverifiedDays) > 0) w.push(`tekshirilmagan kun: ${n(c.unverifiedDays)}`);
  if (n(c.waitingApproval) > 0) w.push(`tasdiq kutmoqda: ${n(c.waitingApproval)}`);
  if (n(c.approvedUnpaid) > 0) w.push(`pul berilmagan: ${n(c.approvedUnpaid)}`);
  if (n(c.staleRefunds) > 0) w.push(`⚠️ kechikkan qaytarish: ${n(c.staleRefunds)}`);
  // qabul qilinmay qolgan smena topshirish (kassa moduli g9: o'tgan kassa kuni yoki 2 soatdan oshgan) — faqat bor bo'lsa; ismsiz (qolgan qatorlar kabi)
  const sh = c.staleHandover;
  if (sh && typeof sh === 'object') w.push(`⚠️ qabul qilinmagan smena topshirish${tkDmyHm(sh.createdAt) ? ` (${tkDmyHm(sh.createdAt)} dan)` : ''}`);
  if (n(c.gaps) > 0) w.push('⚠️ raqamlashda bo‘shliq');
  if (n(c.fiscalExempt) > 0) w.push(`fiskal cheksiz: ${n(c.fiscalExempt)}`);
  if (c.limitExceeded === true) w.push('⚠️ qoldiq limitdan oshgan');
  // eslatma (F1.24): avans hisoboti muddati o'tgan hisobdorlar
  const ao = c.accOverdue;
  if (ao && typeof ao === 'object' && n(ao.n) > 0) w.push(`⚠️ muddati o‘tgan avans: ${n(ao.n)} (${fmtNum(ao.sum)} so‘m)`);
  // onlayn kassa (NKM) Z-hisoboti — shu kun yopilgan bo'lsa (F1.26): faqat muammo bo'lsa
  const z = c.z;
  if (z && typeof z === 'object' && z.ok === false) {
    const sg = v => `${n(v) > 0 ? '+' : '−'}${fmtNum(Math.abs(n(v)))}`;
    w.push(z.recorded !== true ? '⚠️ Z-hisobot kiritilmagan' : z.missing === true ? '⚠️ Z-hisobot yo‘q (sababi yozilgan)'
      : `⚠️ Z-hisobot farqi: ${[n(z.diffCash) ? `naqd ${sg(z.diffCash)}` : '', n(z.diffCard) ? `karta ${sg(z.diffCard)}` : ''].filter(Boolean).join(', ')}`);
  }
  L.push(`🔎 Kassa nazorati: ${w.join(' · ')}`);
  // RP-22 (F1.25): dushanba kungi hisobotda o'tgan hafta ko'rsatkichlari (k.week — faqat dushanba)
  const wk = k.week;
  if (wk && typeof wk === 'object') {
    const p = [`o‘sha kuni yopilgan ${n(wk.onTime)}/${n(wk.closed)} kun`];
    if (n(wk.unverified) > 0) p.push(`tekshirilmagan ${n(wk.unverified)}`);
    p.push(n(wk.diffDays) > 0 ? `farqli kun ${n(wk.diffDays)}${n(wk.shortage) ? ` (kamomad ${fmtNum(wk.shortage)})` : ''}${n(wk.surplus) ? ` (ortiqcha ${fmtNum(wk.surplus)})` : ''}${n(wk.handoverDiffs) ? ` (smena topshirishda ${n(wk.handoverDiffs)})` : ''}` : 'farq yo‘q');
    if (wk.ex49Share != null) p.push(`«Boshqa xarajatlar» ${String(wk.ex49Share).replace('.', ',')}%${Number(wk.ex49Share) > 2 ? ' ⚠️' : ''}`);
    const wa = wk.accOverdue || {};
    if (n(wa.n) > 0) p.push(`⚠️ muddati o‘tgan avans ${n(wa.n)}`);
    if (n(wk.reopened) > 0) p.push(`qayta ochilgan ${n(wk.reopened)}`);
    L.push(`📈 Kassa — o‘tgan hafta (${dmy(wk.from)}–${dmy(wk.to)}): ${p.join(' · ')}`);
  }
  return L;
}
// Hisobot matni (Telegram, oddiy matn). d — director_daily(); checks — health runChecks() yoki null.
function composeDaily(d, checks) {
  d = d || {};
  const p = d.payments || {}, db = d.debt || {}, at = d.attendance || {}, pe = d.pending || {}, od = d.overdue || {};
  const day = String(d.day || '').split('-').reverse().join('.');
  const prov = Object.entries(p.byProvider || {}).sort((a, b) => Number(b[1]) - Number(a[1])).map(([k, v]) => `${PROV[k] || k} ${fmtNum(v)}`).join(' · ');
  // «HH:MM holatiga» — ma'lumot olingan payt (A6-01): shundan keyin tushgan to'lov keyingi hisobotning «oldingi hisobotdan keyin» qatorida
  const hm = tkHm(d.asOf);
  const L = [`📊 IQROR Academy — kunlik hisobot (${day}${hm ? `, ${hm} holatiga` : ''})`, ''];
  L.push(`💰 To‘lovlar: ${Number(p.count) || 0} ta · ${fmtNum(p.sum)} so‘m${prov ? ` (${prov})` : ''}`);
  // Oldingi hisobotdan keyin tushgan to'lovlar (A6-01): kechqurun (hisobot yuborilgandan keyin) va hisobot yuborilmagan kunlarda
  //   (shanba, yakshanba, bayram, yetkazilmagan kun) — kassa kuni bo'yicha. Avval ular hech qaysi hisobotda chiqmasdi.
  const sc = d.since;
  if (sc && typeof sc === 'object' && Number(sc.count) > 0) {
    const bd = Array.isArray(sc.byDay) ? sc.byDay : [];
    const byDay = bd.length && bd.length <= 7 ? ` (${bd.map(x => `${dm(x.day)} — ${fmtNum(x.sum)}`).join(' · ')})` : '';
    L.push(`   🌙 Oldingi hisobotdan keyin${tkDmyHm(sc.from) ? ` (${tkDmyHm(sc.from)} dan)` : ''} tushgan: ${Number(sc.count)} ta · ${fmtNum(sc.sum)} so‘m${byDay}`);
  }
  // To'lovlar kassa kuni bo'yicha (admin «To‘lovlar → Hisobot» bilan bir xil): bugun kiritilib, oldingi kun sanasi bilan
  //   yozilganlari o'sha kunga tushadi — direktor ularni ko'rishi uchun alohida qator.
  const late = d.late || {};
  if (Number(late.count) > 0) L.push(`   ↩ Bugun kiritilgan, oldingi kunlar sanasi bilan: ${Number(late.count)} ta · ${fmtNum(late.sum)} so‘m`);
  // Biriktirilmagan — BARCHASI («To‘lovlar»dagi ro'yxat bilan bir xil; A6-07): avval faqat bugungilar — kechagisi ertasi kuni yo'qolardi
  if (Number(d.unmatched) > 0) L.push(`   ⚠️ O‘quvchiga biriktirilmagan: ${d.unmatched} ta${Number(d.unmatchedSum) > 0 ? ` · ${fmtNum(d.unmatchedSum)} so‘m` : ''}${d.unmatchedSince ? ` (eng eskisi ${dmy(d.unmatchedSince)})` : ''} — «To‘lovlar»da biriktiring`);
  // Qarzdorlar — barcha o'quvchilar (A6-03): chiqib ketgan / muzlatilganlarning eski qarzi ham (undiriladi) — soni va summasi alohida
  const ina = db.inactive && typeof db.inactive === 'object' && Number(db.inactive.n) > 0 ? db.inactive : null;
  L.push(`🧾 Qarzdorlar: 1 oy — ${Number(db.m1) || 0}, 2 oy — ${Number(db.m2) || 0}, 3+ oy — ${Number(db.m3) || 0}${ina ? ` (shu jumladan ketgan / muzlatilgan: ${Number(ina.n)} · ${fmtNum(ina.sum)} so‘m — eski qarz, undiriladi)` : ''}`);
  L.push(`📋 Davomat kiritilishi: ${at.rate == null ? '— (bugun dars kuni emas)' : `${String(at.rate).replace('.', ',')}% (${at.marked}/${at.required})`}`);
  const names = { bonus: '100 ball', discount: 'chegirma', sick: '«Bemor» kuni', referral: 'tavsiya', payroll: 'maosh' };
  const pend = Object.keys(names).filter(k => Number(pe[k]) > 0).map(k => `${names[k]} ${pe[k]}`).join(' · ');
  const overdue = Object.keys(names).reduce((s, k) => s + (Number(od[k]) || 0), 0);
  L.push(`✅ Kutilayotgan tasdiqlar: ${pend || 'yo‘q'}${overdue ? ` (muddati o‘tgan: ${overdue})` : ''}`);
  // Kassa bloki va nazorat qatori (moliya ish rejasi RP-05) — faqat kassa moduli ishlatilayotgan bo'lsa (d.kassa bor).
  //   Raqamlar kassirning kunlik hisoboti (RP-02) va kassa kitobi (KO-4) bilan bir manbadan: director_daily → app.kassa_daily.
  kassaLines(d.kassa).forEach(x => L.push(x));
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
  // kunlar tanlanmagan bo'lsa — Du–Ju (dars kunlari, A2-02; avval shanba ham — davomat «0%» bo'lardi)
  const days = Array.isArray(row.days) ? row.days.map(Number) : [1, 2, 3, 4, 5];
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
  // Ma'lumot olingan payt (A6-01) — jurnal qatorining "createdAt"i: keyingi hisobotning «oldingi hisobotdan keyin» oynasi aynan shundan
  //   boshlanadi (ma'lumot olinib, yuborilguncha — masalan «Tizim holati» tekshiruvi paytida — tushgan to'lov ham yo'qolmaydi).
  const asOf = d && typeof d.asOf === 'string' && Number.isFinite(Date.parse(d.asOf)) ? d.asOf : null;
  let sent = 0, skipped = 0, retried = 0;
  for (const l of rcpt) {
    const id = `daily__${tkDay(t)}__${l.id}`;
    const rec = { type: 'daily', status: 'sending', attempts: 1, message: text.slice(0, 1000), channel: 'telegram', phone: '' };
    if (asOf) rec.createdAt = asOf;
    // bugun yuborilganmi (yoki yuborilmoqda / natijasi noaniq) — takror yo'q; oldingi urinish ANIQ yetkazilmagan bo'lsa — qayta (A6-05)
    let att = 1;   // shu urinishning tartib raqami (qayta claim — oldingisidan bitta ko'p)
    const ins = await sb.from('sms_log').insert(Object.assign({ id }, rec));
    if (ins.error) {
      att = await reclaimDaily(sb, id, rec);
      if (!att) { skipped++; continue; }
      retried++;
    }
    const r = await tg.sendMessage(l.chatId, text);
    if (r.ok) { sent++; await sb.from('sms_log').update({ status: 'sent', providerId: 'tg' }).eq('id', id); }
    else {
      // Bloklangan chat — qayta yuborilmaydi (bog'lanish 'blocked'); NOANIQ natija (timeout:true — javob muddati, ulanishdan keyin uzilish,
      //   2xx javob tanasi o'qilmagan: xabar yetgan bo'lishi mumkin) — qayta yuborilmaydi (Direktorga ikki marta ketmasin). Qolgani
      //   (ulanishdan oldingi tarmoq xatosi, Telegram 5xx, 429 kutishdan keyin ham) — ANIQ yetkazilmagan: RETRY belgisi bilan, keyingi
      //   run'da (cron — har 15 daqiqa) qayta yuboriladi. Avval bitta vaqtinchalik xato butun kunlik hisobotni yo'qotardi: keyingi run'lar
      //   qatorni «bugun yuborilgan» deb o'tkazib yuborardi. Oxirgi (MAXTRIES-) urinish — belgisiz (reclaimDaily baribir olmaydi) va log'da
      //   «oxirgi urinish» (avval «keyingi run qayta yuboradi» deyilardi, holbuki qayta urinilmasdi).
      const again = !r.blocked && !r.timeout, last = again && att >= MAXTRIES;
      await sb.from('sms_log').update({ status: 'failed', error: (again && !last ? RETRY : '') + String(r.error || '').slice(0, 200) }).eq('id', id);
      if (r.blocked) { try { await sb.rpc('tg_blocked', { p_chat: l.chatId }); } catch (_) {} }
      log('Kunlik hisobot yetkazilmadi:', String(r.error || '').slice(0, 120),
        last ? `— bu oxirgi (${att}-) urinish edi, bugun qayta yuborilmaydi`
          : again ? `— keyingi run qayta yuboradi (${att}/${MAXTRIES} urinish)`
          : r.timeout ? '— natija noaniq (xabar yetgan bo‘lishi mumkin), qayta yuborilmaydi' : '');
    }
  }
  log(`Kunlik hisobot: ${sent} ta Direktorga yuborildi${retried ? ` (shundan qayta urinish: ${retried})` : ''}${skipped ? ` · ${skipped} tasiga bugun yuborilgan yoki yuborilmoqda (takror yo‘q)` : ''}`);
  return { sent, skipped, retried, text };
}
// Shu kun qatori bor (insert — takror kalit). Faqat oldingi urinish ANIQ yetkazilmagan ('failed' + RETRY) va urinishlar MAXTRIES dan
//   kam bo'lsa — SHARTLI qayta claim (holat va urinishlar soni o'zgarmagan bo'lsa: parallel run'lardan faqat bittasi oladi; payments/
//   sms-worker.cjs claimSms bilan bir xil usul). 'sent', 'sending', prefikssiz 'failed' (noaniq, blok, oxirgi urinish, eski yozuv) —
//   o'tkaziladi. -> olingan bo'lsa shu urinishning tartib raqami (2…MAXTRIES), aks holda 0.
async function reclaimDaily(sb, id, rec) {
  try {
    const { data, error } = await sb.from('sms_log').select('status,attempts,error').eq('id', id).limit(1);
    const p = !error && (data || [])[0], n = Number(p && p.attempts) || 0;
    if (!p || p.status !== 'failed' || n >= MAXTRIES || String(p.error || '').indexOf(RETRY) !== 0) return 0;
    const u = await sb.from('sms_log').update(Object.assign({}, rec, { attempts: n + 1, error: '' }))
      .eq('id', id).eq('status', 'failed').eq('attempts', n).select('id');
    return (!u.error && (u.data || []).length === 1) ? n + 1 : 0;
  } catch (e) { return 0; }
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
module.exports = { composeDaily, kassaLines, dailyPlan, runDaily };
