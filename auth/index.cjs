/**
 * Iqror — AUTH serveri (telefon + parol + OTP).  SERVER tomoni, maxfiy kalitlar faqat shu yerda.
 * -------------------------------------------------------------------
 * Identifikator: telefon (+998XXXXXXXXX) -> sintetik email '998XXXXXXXXX@phone.<domen>'.
 * Parol: Supabase Auth (bcrypt) — biz PAROL SAQLAMAYMIZ. OTP: Eskiz SMS, hash holida otp_codes'da.
 * service_role (RLS chetlab) + anon (login/parol-tekshiruv) mijozlari.
 *
 * ⚠️ Tashqi yo'l: /authapi/*  (nginx). «/auth/» BAND — u Supabase GoTrue (kong:8000)ga ketadi.
 *    Port 8792 (8790=to'lov, 8791=AI band). Server yo'lning OXIRGI bo'lagi bo'yicha marshrutlaydi,
 *    shu sabab /authapi/ yoki / prefiksdan qat'i nazar ishlaydi.
 *
 * Endpointlar (nginx /authapi/* -> 127.0.0.1:8792):
 *   POST /auth/request-otp        { phone, purpose:'register'|'reset'|'change_phone', jwt? }
 *   POST /auth/verify-otp         { phone, purpose, code }                 -> { ok, ticket }
 *   POST /auth/register           { ticket, password, firstName, lastName, role:'teacher'|'parent' }
 *   POST /auth/login              { phone, password }                      -> { ok, access_token, refresh_token }
 *   POST /auth/reset-confirm      { ticket, newPassword }
 *   POST /auth/change-phone-confirm { ticket }
 *   GET  /auth/health             -> ok
 *
 * Ishga tushirish:  cp config.example.json config.json (to'ldiring) ; node index.cjs
 * Batafsil: README.md
 */
const fs = require('fs');
const http = require('http');
const path = require('path');
const L = require('./lib.cjs');

const MAX_BODY = 64e3;   // auth payloadlari kichik — 64 KB yetarli
function readBody(req) {
  return new Promise(resolve => {
    const chunks = []; let len = 0, done = false, tooLarge = false;
    const finish = () => { if (done) return; done = true; resolve({ raw: tooLarge ? '' : Buffer.concat(chunks).toString('utf8'), tooLarge }); };
    req.on('data', c => { len += c.length; if (len > MAX_BODY) { tooLarge = true; try { req.destroy(); } catch (_) {} return finish(); } chunks.push(c); });
    req.on('end', finish); req.on('error', finish); req.on('aborted', finish); req.on('close', finish);
  });
}
function parseBody(raw, ctype) {
  if ((ctype || '').includes('application/json')) { try { return JSON.parse(raw || '{}'); } catch (_) { return {}; } }
  return Object.fromEntries(new URLSearchParams(raw || ''));
}
// Logда telefonni qisman yashirish (PII).
const redactPhone = p => { const d = String(p || '').replace(/\D/g, ''); return d.length >= 6 ? d.slice(0, 5) + '***' + d.slice(-2) : '***'; };

// =====================================================================
// SOF-ROQ handlerlar fabrikasi — deps inject qilinadi (test uchun soxta sb/anon/admin/eskiz).
//   sb    : service_role supabase mijozi (.from(...), RLS chetlab)
//   anon  : () => anon supabase mijozi (signInWithPassword — parol tekshiruvi/login)
//   admin : service_role mijoz (admin.auth.admin.createUser/updateUserById/deleteUser)
//   eskiz : { send(phone,msg) } yoki null (DRY)
//   verifyJwt(jwt) -> uid|null
// =====================================================================
function makeHandlers(deps) {
  const { sb, anon, admin, eskiz, verifyJwt, cfg } = deps;
  const C = cfg || {};
  const HMAC = C.hmacSecret || '';
  const DOMAIN = C.phoneEmailDomain || 'phone.iqroacademy.uz';
  const OTP_TTL = Number(C.otpTtlSec || 180);
  const OTP_MAX_ATTEMPTS = Number(C.otpMaxAttempts || 5);
  const OTP_RESEND = Number(C.otpResendSec || 60);
  const OTP_MAX_HOUR = Number(C.otpMaxPerHour || 5);
  const OTP_MAX_IP_HOUR = Number(C.otpMaxPerIpHour || 20);   // bitta IP soatiga qancha OTP so'rovi (SMS flood)
  const TICKET_TTL = Number(C.ticketTtlSec || 600);
  const LOGIN_MAX_FAILS = Number(C.loginMaxFails || 10);
  const LOGIN_LOCK_MIN = Number(C.loginLockMin || 15);
  const OTP_TPL = C.otpTemplate || 'IQROR Academy tasdiqlash kodi: {code}. Hech kimga bermang.';
  const DRY = !eskiz;
  const ALLOWED_ROLES = new Set(['teacher', 'parent']);
  const PURPOSES = new Set(['register', 'reset', 'change_phone']);

  const nowISO = () => new Date().toISOString();
  async function userByPhone(phone) {
    const { data } = await sb.from('users').select('*').eq('phone', phone).limit(1);
    return (data && data[0]) || null;
  }
  async function lastOtp(phone, purpose) {
    const { data } = await sb.from('otp_codes').select('*').eq('phone', phone).eq('purpose', purpose).order('createdAt', { ascending: false }).limit(1);
    return (data && data[0]) || null;
  }

  async function requestOtp(body) {
    const canon = L.normPhone(body.phone);
    if (!canon) return { ok: false, error: 'Telefon raqam noto‘g‘ri. +998 bilan 12 raqam kiriting.' };
    const purpose = String(body.purpose || '');
    if (!PURPOSES.has(purpose)) return { ok: false, error: 'Noto‘g‘ri so‘rov.' };

    // (1) Maqsad bo'yicha TERMINAL tekshiruvlar — anti-abuse chegaralaridan OLDIN, foydalanuvchiga
    //     eng aniq xabar berish uchun (masalan «allaqachon ro'yxatdan o'tgan» — 60s throttle yashirmasin).
    let uid = null;
    if (purpose === 'register') {
      // Spec: telefon band bo'lsa ANIQ ayt + login'ga yo'naltir (bu yerda enumeration ATAYLAB).
      if (await userByPhone(canon)) return { ok: false, error: 'Bu telefon allaqachon ro‘yxatdan o‘tgan. Kirish sahifasiga o‘ting.', redirect: 'login' };
    } else if (purpose === 'reset') {
      // Enumeration'ni oldini olish: user bo'lmasa ham ok (SMS yubormaymiz, otp yozmaymiz).
      if (!(await userByPhone(canon))) return { ok: true, resendAfter: OTP_RESEND };
    } else if (purpose === 'change_phone') {
      uid = await verifyJwt(body.jwt);
      if (!uid) return { ok: false, error: 'Avval tizimga kiring.' };
      if (await userByPhone(canon)) return { ok: false, error: 'Bu telefon band.' };
    }

    // (2) Anti-abuse: soatlik limit (telefon + IP) + 60s qayta-yuborish (SMS yuboriladigan yo'lда).
    const hourAgo = new Date(Date.now() - 3600e3).toISOString();
    const { data: recent } = await sb.from('otp_codes').select('id').eq('phone', canon).gte('createdAt', hourAgo);
    if ((recent || []).length >= OTP_MAX_HOUR) return { ok: false, error: `Soatiga ${OTP_MAX_HOUR} martadan ortiq kod so‘rab bo‘lmaydi. Keyinroq urinib ko‘ring.` };
    // IP bo'yicha limit — bitta manba ko'p raqamga SMS «pompalamasin» (toll fraud).
    const ip = String(body._ip || '').slice(0, 64);
    if (ip) {
      const { data: byIp } = await sb.from('otp_codes').select('id').eq('ip', ip).gte('createdAt', hourAgo);
      if ((byIp || []).length >= OTP_MAX_IP_HOUR) return { ok: false, error: 'Juda ko‘p so‘rov. Keyinroq urinib ko‘ring.' };
    }
    const last = await lastOtp(canon, purpose);
    if (last && last.createdAt) {
      const age = (Date.now() - Date.parse(last.createdAt)) / 1000;
      if (age < OTP_RESEND) { const wait = Math.ceil(OTP_RESEND - age); return { ok: false, error: `Yangi kodni ${wait} soniyadan so‘ng so‘rang.`, resendAfter: wait }; }
    }

    const code = L.genCode();
    const codeHash = L.hmacCode(HMAC, canon, purpose, code);
    const expiresAt = new Date(Date.now() + OTP_TTL * 1000).toISOString();
    // Oldingi ishlatilmagan kodlarni bekor qilamiz (faqat oxirgisi amal qilsin).
    await sb.from('otp_codes').update({ consumed: true }).eq('phone', canon).eq('purpose', purpose).eq('consumed', false);
    const { error: insErr } = await sb.from('otp_codes').insert({ phone: canon, codeHash, purpose, expiresAt, attempts: 0, uid, ip });
    if (insErr) return { ok: false, error: 'Kod yuborishda xatolik. Qayta urinib ko‘ring.' };

    const msg = String(OTP_TPL).replace('{code}', code);
    if (DRY) console.log('[DRY OTP]', redactPhone(canon), purpose, code);
    else { try { const r = await eskiz.send(canon, msg); if (!r.ok) console.error('OTP SMS fail', redactPhone(canon), r.error); } catch (e) { console.error('OTP SMS exc', redactPhone(canon)); } }
    return { ok: true, resendAfter: OTP_RESEND };
  }

  async function verifyOtp(body) {
    const canon = L.normPhone(body.phone);
    const purpose = String(body.purpose || '');
    if (!canon || !PURPOSES.has(purpose)) return { ok: false, error: 'Noto‘g‘ri so‘rov.' };
    const hash = L.hmacCode(HMAC, canon, purpose, String(body.code || '').trim());
    // ATOMIK tekshiruv (otp_consume FOR UPDATE) — urinish sanog'i poyga (race) orqali chetlab
    //   o'tilmaydi; cap haqiqiy ishlaydi (brute-force yopiq). Hash serverда hisoblanadi.
    const { data, error } = await sb.rpc('otp_consume', { p_phone: canon, p_purpose: purpose, p_hash: hash, p_max: OTP_MAX_ATTEMPTS });
    if (error) return { ok: false, error: 'Server xatosi. Qayta urinib ko‘ring.' };
    const r = data || {};
    if (r.ok) {
      const payload = { phone: canon, purpose };
      if (purpose === 'change_phone') { payload.uid = r.uid; payload.newPhone = canon; }
      return { ok: true, ticket: L.signTicket(HMAC, payload, TICKET_TTL) };
    }
    if (r.nocode) return { ok: false, error: 'Kod topilmadi. «Qayta yuborish»ni bosing.' };
    if (r.expired) return { ok: false, expired: true, error: 'Kod muddati tugagan. «Qayta yuborish»ni bosing.' };
    if (r.locked && r.remaining === undefined) return { ok: false, locked: true, error: 'Juda ko‘p urinish. Kodni qayta yuboring.' };
    const remaining = r.remaining || 0;
    return { ok: false, remaining, locked: !!r.locked, error: 'Kod noto‘g‘ri.' + (remaining ? ` Qolgan urinish: ${remaining}.` : ' Kodni qayta yuboring.') };
  }

  async function register(body) {
    const t = L.verifyTicket(HMAC, body.ticket);
    if (!t || t.purpose !== 'register' || !t.phone) return { ok: false, error: 'Tasdiqlash muddati tugagan. Qaytadan boshlang.' };
    const canon = t.phone;
    const role = ALLOWED_ROLES.has(body.role) ? body.role : null;
    if (!role) return { ok: false, error: 'Noto‘g‘ri rol.' };
    const pv = L.validatePassword(body.password);
    if (!pv.ok) return { ok: false, error: pv.errors.join('. ') };
    const firstName = String(body.firstName || '').trim();
    const lastName = String(body.lastName || '').trim();
    if (!firstName || !lastName) return { ok: false, error: 'Ism va familiya majburiy.' };
    if (await userByPhone(canon)) return { ok: false, error: 'Bu telefon allaqachon ro‘yxatdan o‘tgan. Kirish sahifasiga o‘ting.', redirect: 'login' };

    const email = L.phoneToEmail(canon, DOMAIN);
    const displayName = (firstName + ' ' + lastName).trim();
    let cr = await admin.auth.admin.createUser({ email, password: String(body.password), email_confirm: true, user_metadata: { displayName } });
    if (cr.error) {
      // Email band. FAQAT haqiqiy YETIM (public.users qatori YO'Q) auth hisobini o'chirib qayta
      //   yaratamiz. Agar o'sha auth hisobda users qatori BO'LSA — bu TIRIK hisob (telefon
      //   o'zgartirish desync'i va h.k.) — uni O'CHIRMAYMIZ (aks holda hisobni yo'q qilardik).
      let orphanId = null;
      try { const { data } = await sb.rpc('auth_uid_by_email', { p_email: email }); orphanId = data || null; } catch (_) {}
      let orphanHasRow = false;
      if (orphanId) { const { data: ur } = await sb.from('users').select('id').eq('id', orphanId).limit(1); orphanHasRow = !!(ur && ur[0]); }
      if (orphanId && !orphanHasRow) {
        try { await admin.auth.admin.deleteUser(orphanId); } catch (_) {}
        cr = await admin.auth.admin.createUser({ email, password: String(body.password), email_confirm: true, user_metadata: { displayName } });
      }
      if (cr.error) return { ok: false, error: 'Bu telefon allaqachon ro‘yxatdan o‘tgan. Kirish sahifasiga o‘ting.', redirect: 'login' };
    }
    const uid = cr.data.user.id;
    const verified = (role === 'parent');                 // parent darhol faol; teacher admin tasdig'ini kutadi
    const status = (role === 'teacher') ? 'pending' : 'active';
    const { error: uErr } = await sb.from('users').insert({
      id: uid, email, phone: canon, role, verified, status,
      firstName, lastName, name: displayName, createdAt: nowISO(), updatedAt: nowISO(),
    });
    if (uErr) { try { await admin.auth.admin.deleteUser(uid); } catch (_) {} return { ok: false, error: 'Ro‘yxatdan o‘tishda xatolik. Qayta urinib ko‘ring.' }; }
    return {
      ok: true, role, verified, email, phone: canon, pending: role === 'teacher',
      message: role === 'teacher'
        ? 'Ro‘yxatdan o‘tdingiz! Hisobingiz administrator tasdig‘ini kutmoqda.'
        : 'Ro‘yxatdan o‘tdingiz! Endi kirishingiz mumkin.',
    };
  }

  async function login(body) {
    const canon = L.normPhone(body.phone);
    if (!canon) return { ok: false, error: 'Telefon yoki parol noto‘g‘ri.' };   // umumiy (qaysi biri — oshkor emas)
    const since = new Date(Date.now() - LOGIN_LOCK_MIN * 60e3).toISOString();
    const { data: fails } = await sb.from('auth_login_attempts').select('id').eq('phone', canon).eq('ok', false).gte('at', since);
    if ((fails || []).length >= LOGIN_MAX_FAILS) return { ok: false, locked: true, error: `Juda ko‘p urinish. ${LOGIN_LOCK_MIN} daqiqadan so‘ng urinib ko‘ring.` };
    const email = L.phoneToEmail(canon, DOMAIN);
    const { data, error } = await anon().auth.signInWithPassword({ email, password: String(body.password || '') });
    if (error || !data || !data.session) {
      await sb.from('auth_login_attempts').insert({ phone: canon, ok: false, ip: String(body._ip||'').slice(0,64) });
      return { ok: false, error: 'Telefon yoki parol noto‘g‘ri.' };
    }
    await sb.from('auth_login_attempts').insert({ phone: canon, ok: true, ip: String(body._ip||'').slice(0,64) });
    const urow = await userByPhone(canon);
    // Tasdiqlanmagan (pending) / bloklangan hisobga TOKEN BERMAYMIZ (frontend gate'ga qo'shimcha
    //   server himoyasi). RLS ham is_staff()'да status='active' talab qiladi (defence-in-depth).
    const us = String((urow && urow.status) || 'active');
    if (us === 'pending' || us === 'blocked') {
      return { ok: false, status: us, error: (us === 'blocked')
        ? 'Hisobingiz bloklangan. Administratorga murojaat qiling.'
        : 'Hisobingiz administrator tasdig‘ini kutmoqda. Tasdiqlangach kiring.' };
    }
    return {
      ok: true, access_token: data.session.access_token, refresh_token: data.session.refresh_token,
      role: (urow && urow.role) || '', verified: !!(urow && urow.verified), status: us,
    };
  }

  async function resetConfirm(body) {
    const t = L.verifyTicket(HMAC, body.ticket);
    if (!t || t.purpose !== 'reset' || !t.phone) return { ok: false, error: 'Tasdiqlash muddati tugagan. Qaytadan boshlang.' };
    const urow = await userByPhone(t.phone);
    if (!urow) return { ok: false, error: 'Foydalanuvchi topilmadi.' };
    const pv = L.validatePassword(body.newPassword);
    if (!pv.ok) return { ok: false, error: pv.errors.join('. ') };
    // DIQQAT: «yangi parol eskisidan farqli» tekshiruvi BU YERDA QILINMAYDI. Avval eski parol bilan
    //   signInWithPassword(newPassword) sinovi bor edi — u JORIY parolni oshkor qiladigan ORAKUL
    //   edi (ticketli hujumchi nomzod parollarni tekshirib eski parolni bilib olardi). Parol
    //   TIKLASHДА foydalanuvchi eski parolni bilmaydi, shuning uchun bu tekshiruv keraksiz.
    //   «Farqli bo'lsin» qoidasi profil «parolni o'zgartirish»да (foydalanuvchi joriy parolni
    //   kiritadigan joyда) saqlanadi — u xavfsiz.
    const { error } = await admin.auth.admin.updateUserById(urow.id, { password: String(body.newPassword) });
    if (error) return { ok: false, error: 'Parolni yangilashda xatolik.' };
    return { ok: true, message: 'Parol yangilandi. Endi yangi parol bilan kiring.' };
  }

  async function changePhoneConfirm(body) {
    const t = L.verifyTicket(HMAC, body.ticket);
    if (!t || t.purpose !== 'change_phone' || !t.uid || !t.newPhone) return { ok: false, error: 'Tasdiqlash muddati tugagan.' };
    const taken = await userByPhone(t.newPhone);
    if (taken && taken.id !== t.uid) return { ok: false, error: 'Bu telefon band.' };
    const email = L.phoneToEmail(t.newPhone, DOMAIN);
    // Avval public.users (service_role), KEYIN auth email. Auth xato bo'lsa users'ni ORQAGA qaytaramiz
    //   -> auth va profil hech qachon desync bo'lmaydi (register orphan-reclaim xavfi yo'q).
    const { data: cur } = await sb.from('users').select('phone,email').eq('id', t.uid).limit(1);
    const oldPhone = (cur && cur[0] && cur[0].phone) || null;
    const oldEmail = (cur && cur[0] && cur[0].email) || null;
    const { error: uErr } = await sb.from('users').update({ phone: t.newPhone, email, updatedAt: nowISO() }).eq('id', t.uid);
    if (uErr) return { ok: false, error: 'Telefonni yangilashda xatolik (profil).' };
    const { error: aErr } = await admin.auth.admin.updateUserById(t.uid, { email });
    if (aErr) {
      await sb.from('users').update({ phone: oldPhone, email: oldEmail, updatedAt: nowISO() }).eq('id', t.uid);   // revert
      return { ok: false, error: 'Telefonni yangilashda xatolik.' };
    }
    return { ok: true, message: 'Telefon raqam yangilandi.' };
  }

  return { requestOtp, verifyOtp, register, login, resetConfirm, changePhoneConfirm };
}

// =====================================================================
// HTTP server (faqat `node index.cjs` bilan ishga tushganда).
// =====================================================================
function startServer() {
  const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
  const AUTH = CFG.auth || {};
  if (!AUTH.hmacSecret) { console.error('❌ config.auth.hmacSecret majburiy (uzun tasodifiy satr).'); process.exit(1); }
  const { db } = require('../server/backend.js')({ ...CFG, __dir: __dirname });
  const { verifyToken } = require('../server/sb-admin.js');
  const { createClient } = require('@supabase/supabase-js');
  const { makeEskiz } = require('../payments/sms.cjs');
  const sb = db._sb;
  const supaUrl = CFG.supabaseUrl || process.env.SUPABASE_URL;
  const anonKey = CFG.anonKey || AUTH.anonKey || process.env.ANON_KEY;
  if (!anonKey) { console.error('❌ config.anonKey (yoki auth.anonKey) majburiy — login uchun.'); process.exit(1); }
  const SMS = CFG.sms || {};
  const eskiz = (SMS.enabled === false || SMS.dryRun === true) ? null : makeEskiz(SMS);
  const H = makeHandlers({
    sb, admin: sb, eskiz, cfg: AUTH,
    anon: () => createClient(supaUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } }),
    verifyJwt: jwt => verifyToken(db, jwt),
  });
  const ROUTES = {
    'request-otp': H.requestOtp, 'verify-otp': H.verifyOtp, 'register': H.register,
    'login': H.login, 'reset-confirm': H.resetConfirm, 'change-phone-confirm': H.changePhoneConfirm,
  };
  // CORS: ruxsat etilgan origin(lar) ro'yxati (vergul bilan yoki massiv). Brauzer api.iqror.uz'ga
  //   cross-origin murojaat qiladi (sayt iqroacademy.uz'да) — shuning uchun mos originни qaytaramiz.
  const CORS_LIST = (Array.isArray(AUTH.corsOrigin) ? AUTH.corsOrigin : String(AUTH.corsOrigin || '').split(','))
    .map(s => String(s).trim()).filter(Boolean);
  const corsFor = req => {
    if (!CORS_LIST.length) return {};
    const origin = req.headers.origin || '';
    const allow = CORS_LIST.includes('*') ? '*' : (CORS_LIST.includes(origin) ? origin : '');
    if (!allow) return {};
    return { 'Access-Control-Allow-Origin': allow, 'Vary': 'Origin', 'Access-Control-Allow-Headers': 'content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
  };
  const PORT = Number(AUTH.port || CFG.authPort || 8792);   // 8790=to'lov, 8791=AI — band

  const server = http.createServer(async (req, res) => {
    const seg = (req.url || '').split('?')[0].replace(/\/+$/, '').split('/').pop();
    const cors = corsFor(req);
    if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
    if (req.method === 'GET' && (seg === 'health' || req.url === '/health')) { res.writeHead(200, cors); return res.end('ok'); }
    if (req.method !== 'POST') { res.writeHead(405, cors); return res.end('POST kutiladi'); }
    const fn = ROUTES[seg];
    if (!fn) { res.writeHead(404, cors); return res.end('not found'); }
    const { raw, tooLarge } = await readBody(req);
    if (tooLarge) { res.writeHead(413, cors); return res.end('payload too large'); }
    const send = (obj, code) => { res.writeHead(code || 200, { 'Content-Type': 'application/json', ...cors }); res.end(JSON.stringify(obj)); };
    try {
      const body = parseBody(raw, req.headers['content-type']);
      // Mijoz IP (nginx X-Forwarded-For'ni $remote_addr'ga o'rnatadi — mijoz spoof qila olmaydi).
      body._ip = (String(req.headers['x-forwarded-for'] || '').split(',')[0].trim()) || (req.socket && req.socket.remoteAddress) || '';
      const out = await fn(body);
      send(out, out && out.ok === false && (out.locked ? 429 : 200));
    } catch (e) {
      console.error('auth xato:', seg, e && e.message);
      send({ ok: false, error: 'Server xatosi. Keyinroq urinib ko‘ring.' }, 500);
    }
  });
  server.listen(PORT, '127.0.0.1', () => console.log(`Iqror AUTH serveri 127.0.0.1:${PORT} (nginx: /authapi/{request-otp,verify-otp,register,login,reset-confirm,change-phone-confirm})`));
}

if (require.main === module) startServer();
module.exports = { makeHandlers, readBody, redactPhone, startServer };
