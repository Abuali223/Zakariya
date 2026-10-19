/**
 * sms.cjs — Eskiz.uz SMS jo'natish moduli (SERVER tomoni, tashqi paketsiz — https).
 * -------------------------------------------------------------------
 * Ikki rejim:
 *   1) email + parol  -> avtomatik token oladi (tavsiya — token eskirsa o'zi yangilaydi)
 *   2) token          -> Eskiz panelidan olingan tayyor tokenni to'g'ridan-to'g'ri ishlatadi
 *
 * Eskiz API: https://notify.eskiz.uz/api
 *   POST /api/auth/login          (email,password)          -> { data:{ token } }
 *   POST /api/message/sms/send    (mobile_phone,message,from) -> { id, status }
 *   GET  /api/user/templates      -> { result:[{ id, template, original_text, status }] }  (tasdiqlangan naqshlar —
 *        SMS shu NAQSH bilan solishtiriladi; payments/eskiz-template.cjs, diagnostika: node eskiz-shablon.cjs)
 *
 * ⚠️ SMS FAQAT O'ZBEKISTON raqamlariga (998XXXXXXXXX) yuboriladi — maktab qoidasi. Chet el raqami (ma'lumot sifatida
 *    to'g'ri bo'lsa ham, server/phone.cjs) -> { ok:false, error:'bad_phone:intl' }, Eskiz'ga so'rov YUBORILMAYDI.
 *
 * ⚠️ Eskiz SMS matnini OLDINDAN moderatsiyadan o'tkazishни talab qiladi —
 *    yuborilayotgan matn tasdiqlangan shablonga mos bo'lishi kerak.
 * ⚠️ Maxfiy: eskizEmail/eskizPassword/token faqat config.json'da (serverda).
 */
const https = require('https');
const PH = require('../server/phone.cjs');

function httpsRequest(opts, body) {
  return new Promise((resolve, reject) => {
    const T = Number(process.env.ESKIZ_TIMEOUT_MS || 20000);
    // sent: so'rov baytlari Eskiz'ga YETGAN bo'lishi mumkinmi (TLS ulanish o'rnatildi yoki qayta ishlatilgan socket)?
    //   Ungacha bo'lgan har qanday xato (TCP/TLS ulanmadi, ulanish timeout'i) — e.preconnect: SMS ANIQ ketmagan.
    let sent = false, ct = null;
    const done = () => { if (ct) { clearTimeout(ct); ct = null; } };
    const fail = e => { done(); if (e && typeof e === 'object' && !sent) e.preconnect = true; reject(e); };
    const req = https.request(opts, res => {
      sent = true; done();
      let d = ''; res.on('data', c => d += c);
      res.on('end', () => { let j = null; try { j = JSON.parse(d); } catch (_) {} resolve({ status: res.statusCode, json: j, raw: d }); });
      // Javob yarmida uzilsa (sarlavhadan keyin ulanish yopildi) — promis osilib qolmasin (so'rov YUBORILGAN -> noaniq).
      res.on('aborted', () => reject(new Error('eskiz_aborted')));
      res.on('error', reject);
      res.on('close', () => { if (!res.complete) reject(new Error('eskiz_aborted')); });
    });
    req.on('socket', sock => {
      if (req.reusedSocket) { sent = true; done(); return; }
      if (sock && typeof sock.once === 'function') sock.once('secureConnect', () => { sent = true; done(); });
    });
    // Ulanish bosqichi timeout'i (req.setTimeout ulanishni qamramaydi) — Eskiz'ga ulana olmasak, osilib qolmaymiz.
    ct = setTimeout(() => { if (!sent) req.destroy(new Error('eskiz_connect_timeout')); }, T);   // javob/xato/ulanishda tozalanadi
    // Eskiz javob bermasa — cheksiz osilib qolmasin (so'rov xato bilan tugaydi; chaqiruvchi holatni «noaniq» deb oladi).
    req.setTimeout(T, () => req.destroy(new Error('eskiz_timeout')));
    req.on('error', fail);
    if (body) req.write(body);
    req.end();
  });
}

// multipart/form-data qurish (Eskiz /auth/login shu formatni kutadi).
function multipart(fields) {
  const boundary = '----iqror' + Date.now().toString(36);
  let s = '';
  for (const k in fields) s += `--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${fields[k]}\r\n`;
  s += `--${boundary}--\r\n`;
  return { boundary, body: Buffer.from(s, 'utf8') };
}

// Telefonni Eskiz formatiga keltiradi: 998XXXXXXXXX (12 raqam, + va bo'shliqsiz).
function normMobile(p) {
  let d = String(p || '').replace(/\D/g, '');
  if (d.length === 9) d = '998' + d;          // XXXXXXXXX -> 998XXXXXXXXX
  else if (d.length > 12) d = d.slice(-12);   // ortiqcha old raqamlarni kesamiz
  return d;
}

function makeEskiz(cfg) {
  cfg = cfg || {};
  const HOST = cfg.host || 'notify.eskiz.uz';
  const from = cfg.from || '4546';            // jo'natuvchi (nickname) — Eskiz'da tasdiqlangan bo'lishi kerak
  let token = null;

  async function login() {
    // Faqat token berilgan bo'lsa — o'shani ishlatamiz (avtomatik yangilanmaydi).
    if (!cfg.eskizEmail && !cfg.email && cfg.token) { token = cfg.token; return token; }
    const { boundary, body } = multipart({ email: cfg.eskizEmail || cfg.email || '', password: cfg.eskizPassword || cfg.password || '' });
    const r = await httpsRequest({ host: HOST, path: '/api/auth/login', method: 'POST',
      headers: { 'Content-Type': 'multipart/form-data; boundary=' + boundary, 'Content-Length': body.length } }, body);
    const t = r.json && r.json.data && r.json.data.token;
    if (!t) throw new Error('Eskiz login muvaffaqiyatsiz: ' + (r.raw || ('HTTP ' + r.status)));
    token = t; return token;
  }
  async function ensureToken() { if (!token) { if (cfg.token) token = cfg.token; else await login(); } return token; }
  const stage = (st, fn) => fn().catch(e => { if (e && typeof e === 'object' && !e.stage) e.stage = st; throw e; });

  // Eskiz'dagi SMS matnlari (shablonlar): [{ id, template (moderator naqshi: %w/%d), original (asl matn), status }].
  //   status: service/reklama — tasdiqlangan; moderation/inproccess — kutilmoqda; rejected — rad etilgan.
  async function templates() {
    await stage('login', ensureToken);
    const get = () => stage('send', () => httpsRequest({ host: HOST, path: '/api/user/templates', method: 'GET',
      headers: { 'Authorization': 'Bearer ' + token, 'Accept': 'application/json' } }));
    let r = await get();
    if (r.status === 401 && (cfg.eskizEmail || cfg.email)) { await stage('login', login); r = await get(); }
    const j = r.json || {};
    const list = Array.isArray(j.result) ? j.result : (Array.isArray(j.data) ? j.data : (Array.isArray(j) ? j : null));
    if (r.status >= 200 && r.status < 300 && list) {
      return { ok: true, list: list.map(t => ({ id: t && t.id, template: String((t && t.template) || ''), original: String((t && t.original_text) || ''), status: String((t && t.status) || '') })) };
    }
    return { ok: false, error: (typeof j.message === 'string' ? j.message : ('http_' + r.status)) };
  }

  // Bitta SMS jo'natadi. Qaytaradi: { ok:true, id, status } | { ok:false, error }
  //   Kirish — kanonik raqam (998901234567) yoki kiritilgan raqam. Yaroqsiz raqam -> 'bad_phone:…'; chet el raqami ->
  //   'bad_phone:intl' (SMS faqat O'zbekistonga) — ikkalasida ham Eskiz'ga so'rov YUBORILMAYDI.
  //   Istisno (throw) bo'lsa e.stage: 'login' — SMS so'rovi HALI yuborilmagan (aniq ketmagan);
  //   'send' — SMS so'rovi yuborilayotganda uzildi (e.code ECONNREFUSED/ENOTFOUND... bo'lsa ulanish umuman bo'lmagan).
  async function send(phone, message) {
    const canon = PH.canonOf(phone);
    if (!canon) return { ok: false, error: 'bad_phone:' + String(phone == null ? '' : phone).replace(/\D/g, '').slice(0, 20) };
    if (!PH.isUzPhone(canon)) return { ok: false, intl: true, error: 'bad_phone:intl' };
    const mobile = canon;
    await stage('login', ensureToken);
    const post = () => stage('send', () => {
      const body = new URLSearchParams({ mobile_phone: mobile, message: String(message || ''), from }).toString();
      return httpsRequest({ host: HOST, path: '/api/message/sms/send', method: 'POST',
        headers: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body) } }, body);
    });
    let r = await post();
    if (r.status === 401 && (cfg.eskizEmail || cfg.email)) { await stage('login', login); r = await post(); }   // token eskirsa — qayta kirib urinamiz
    const j = r.json || {};
    if (r.status >= 200 && r.status < 300 && (j.id || j.status === 'waiting' || j.status === 'success'))
      return { ok: true, id: String(j.id || ''), status: j.status || 'sent' };
    // ANIQ rad = har qanday 4xx (JSON bo'lmasa ham, masalan 429/403 HTML) — so'rov rad etilgan, SMS ketmagan.
    //   5xx / 3xx / 2xx lekin id yo'q — NOANIQ: Eskiz SMS'ni navbatga qo'ygan bo'lishi mumkin (qayta yuborilmasin).
    const ambiguous = !(r.status >= 400 && r.status < 500);
    return { ok: false, error: (typeof j.message === 'string' ? j.message : (j.message ? JSON.stringify(j.message) : ('http_' + r.status))), raw: r.raw, httpStatus: r.status, ambiguous };
  }

  return { login, send, templates, normMobile };
}

// ---- SMS matni yordamchilari (sms-worker.cjs va auth/sms-remind.cjs UMUMIY ishlatadi — matn bir xil bo'lsin) ----
const DEF_NEW  = "Hurmatli ota-ona! {name} uchun {month} oy to'lovi shakllantirildi: {amount} so'm. Batafsil: iqroacademy.uz. IQROR Academy";
const DEF_DEBT = "Eslatma: {name} uchun {month} oy to'lovi hali yopilmagan (qarz: {due} so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";
const DEF_OTP  = 'IQROR Academy tasdiqlash kodi: {code}. Hech kimga bermang.';   // auth serveri (auth.otpTemplate bo'lmasa)
const fmtSom = n => String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
const fmtMonth = m => { const p = String(m || '').split('-'); return p.length === 2 ? `${p[1]}.${p[0]}` : String(m || ''); };
const fillTpl = (t, v) => String(t || '').replace(/\{(\w+)\}/g, (_, k) => (v[k] != null ? String(v[k]) : ''));
// Toshkent (UTC+5, yozgi vaqt yo'q) sanasi 'YYYY-MM-DD' va shu kun boshining UTC ISO vaqti.
const tashkentDay = (ms) => new Date((ms == null ? Date.now() : ms) + 5 * 3600e3).toISOString().slice(0, 10);
const tashkentDayStartISO = (day) => new Date(Date.parse(day + 'T00:00:00Z') - 5 * 3600e3).toISOString();

// Yuborish natijasi holati (sms_log.status): 'sent' | 'failed' (ANIQ ketmagan — qayta urinish mumkin) | 'unknown' (ketgan
//   bo'lishi mumkin — qayta YUBORILMAYDI). Istisno: kirish (login) bosqichi yoki ulanish umuman o'rnatilmagan
//   (ECONNREFUSED/DNS/TLS, ulanish timeout'i — e.preconnect) -> aniq ketmagan; SMS so'rovi paytida uzilish/timeout -> noaniq.
const PRECONN = new Set(['ECONNREFUSED', 'ENOTFOUND', 'EAI_AGAIN', 'EHOSTUNREACH', 'ENETUNREACH']);
function definitelyNotSent(e) {
  if (!e || typeof e !== 'object') return false;
  const c = String(e.code || '');
  return e.stage === 'login' || e.preconnect === true || e.syscall === 'connect' || PRECONN.has(c) || /^(CERT_|ERR_TLS|UNABLE_TO_|DEPTH_ZERO|SELF_SIGNED)/.test(c);
}
// SMS uchun yaroqli raqam: O'zbekiston mobil raqami KANONIK (998XXXXXXXXX; auth/lib.cjs normPhone bilan bir xil qoida —
//   server/phone.cjs) yoki ''. Chet el raqami ('+7 903 …') — ma'lumot sifatida to'g'ri, lekin SMS yuborilmaydi -> ''.
function canonMobile(p) {
  const c = PH.phoneCanon(p);
  return PH.isUzPhone(c) ? c : '';
}
// SMS uchun ism: tipografik apostroflarni oddiyiga (GSM-7 — SMS qismlari ko'paymasin), bo'shliqlarni yig'ish.
const smsName = s => String(s || '').replace(/[ʻʼ‘’`´]/g, "'").replace(/\s+/g, ' ').trim().slice(0, 40);
function sendStatus(r, thrown) {
  if (thrown) return definitelyNotSent(thrown) ? 'failed' : 'unknown';
  if (r && r.ok) return 'sent';
  return (r && r.ambiguous) ? 'unknown' : 'failed';
}

module.exports = { makeEskiz, normMobile, canonMobile, smsName, DEF_NEW, DEF_DEBT, DEF_OTP, fmtSom, fmtMonth, fillTpl, tashkentDay, tashkentDayStartISO, definitelyNotSent, sendStatus };
