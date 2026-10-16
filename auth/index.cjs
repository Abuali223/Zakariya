/**
 * Iqror — AUTH serveri (telefon + parol + OTP).  SERVER tomoni, maxfiy kalitlar faqat shu yerda.
 * -------------------------------------------------------------------
 * Identifikator: telefon (+998XXXXXXXXX yoki chet el +7..., +48...) -> sintetik email '<raqam>@phone.<domen>'.
 *   Chet el raqamiga OTP — Eskiz xalqaro SMS (send-global); faqat maktab ma'lumotlarida BOR raqamga (SMS-firibgarlik
 *   himoyasi) va umumiy soatlik/kunlik chegara bilan (README «Chet el raqamlari»).
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
 *   POST /auth/register           { ticket, password, firstName, lastName, role:'staff'|'parent' }  (eski sahifa: 'teacher' = 'staff')
 *   POST /auth/login              { phone, password }                      -> { ok, access_token, refresh_token }
 *   POST /auth/reset-confirm      { ticket, newPassword }
 *   POST /auth/change-phone-confirm { ticket }
 *   POST /auth/sms-remind         { jwt, studentId, preview? }            -> qarzdor ota-onasiga SMS eslatma (sms-remind.cjs)
 *   GET  /auth/health             -> ok
 *
 * Ishga tushirish:  cp config.example.json config.json (to'ldiring) ; node index.cjs
 * Batafsil: README.md
 */
const fs = require('fs');
const http = require('http');
const path = require('path');
const L = require('./lib.cjs');
const { definitelyNotSent } = require('../payments/sms.cjs');

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

// Sozlama soni: yaroqsiz/manfiy -> standart (fail-closed). 0 — ruxsat etilgan qiymat (o'chirish).
function cfgNum(v, def) { if (v === undefined || v === null || v === '') return def; const n = Number(v); return (Number.isFinite(n) && n >= 0) ? Math.floor(n) : def; }

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
  // Ro'yxatdagi rol: 'staff' = umumiy xodim (aniq rol — teacher/kassir/qorovul... — admin tasdiqlashda beriladi), 'parent'.
  //   'teacher' — ESKI sahifa (c29e5b5 gacha «O‘qituvchi» tugmasi; brauzerda uzoq ochiq qolgan / keshlangan sahifa) — u ham
  //   XODIM sifatida qabul qilinadi («Noto‘g‘ri rol» bilan ro'yxat yarmida to'xtab qolmasin). Boshqa qiymat (admin,
  //   director...) — rad: mijoz yuqori rolni tanlay olmaydi.
  const ROLE_ALIAS = new Map([['staff', 'staff'], ['teacher', 'staff'], ['parent', 'parent']]);
  const PURPOSES = new Set(['register', 'reset', 'change_phone']);
  // Chet el raqamiga OTP (Eskiz xalqaro SMS). auth.intlOtp=false yoki sms.international=false — o'chiq.
  //   Umumiy chegara (butun tizim, xarajat himoyasi): soatiga / sutkasiga; 0 = chet el raqamiga OTP yo'q.
  const SMS_CFG = deps.smsCfg || {};
  const INTL_OTP = C.intlOtp !== false && SMS_CFG.international !== false;
  const OTP_INTL_HOUR = cfgNum(C.otpIntlMaxPerHour, 20);
  const OTP_INTL_DAY = cfgNum(C.otpIntlMaxPerDay, 60);
  const BAD_PHONE = 'Telefon raqam noto‘g‘ri. O‘zbekiston: +998 90 123 45 67; chet el raqami + bilan, davlat kodi bilan to‘liq (masalan +7 903 123 45 67).';

  const nowISO = () => new Date().toISOString();
  async function userByPhone(phone) {
    const { data } = await sb.from('users').select('*').eq('phone', phone).limit(1);
    return (data && data[0]) || null;
  }
  async function lastOtp(phone, purpose) {
    const { data } = await sb.from('otp_codes').select('*').eq('phone', phone).eq('purpose', purpose).order('createdAt', { ascending: false }).limit(1);
    return (data && data[0]) || null;
  }
  // Chet el raqami maktab ma'lumotlarida BORmi (o'quvchi kartasidagi ota/ona telefoni yoki xodim/o'qituvchi telefoni)?
  //   SMS-firibgarlik (xalqaro SMS «pumping») himoyasi: chet elga kod FAQAT maktab o'zi yozib qo'ygan raqamga ketadi.
  //   Ro'yxat sahifalab o'qiladi (PostgREST 1000 qator chegarasi) va KNOWN_TTL soniya xotirada saqlanadi (har so'rovda
  //   jadvallarni qayta o'qib, bazani band qilmaslik uchun; admin raqam qo'shsa — shu vaqt ichida kuchga kiradi).
  //   Xato -> null (fail-closed: kod yuborilmaydi).
  const KNOWN_TTL = cfgNum(C.knownPhoneCacheSec, 60);
  let knownSet = null, knownAt = 0;
  async function knownPhone(canon) {
    if (!knownSet || Date.now() - knownAt >= KNOWN_TTL * 1000) {
      const SRC = [['student_private', ['parentPhone', 'parentPhone2']], ['staff', ['phone']], ['teachers', ['phone']]];
      const PAGE = 1000, set = new Set();
      for (const [t, cols] of SRC) {
        for (let from = 0; ; from += PAGE) {
          const { data, error } = await sb.from(t).select(['id'].concat(cols).join(',')).order('id', { ascending: true }).range(from, from + PAGE - 1);
          if (error) { console.error('knownPhone fetch fail', t, error.code || '', (error.message || '').slice(0, 120)); return null; }
          for (const r of data || []) for (const c of cols) { const k = L.normPhone(r[c]); if (k && k.slice(0, 3) !== '998') set.add(k); }
          if (!data || data.length < PAGE) break;
        }
      }
      knownSet = set; knownAt = Date.now();
    }
    return knownSet.has(canon);
  }
  // Ma'lumotlarda YO'Q chet el raqami bilan so'rovlar — IP bo'yicha soatiga OTP_MAX_IP_HOUR tadan (xotirada): raqamlarni
  //   ketma-ket «tekshirib chiqish»ga qarshi (bunday so'rov otp_codes'ga yozilmaydi, shuning uchun IP limiti alohida).
  //   Xotira chegaralangan: IP boshiga ko'pi bilan OTP_MAX_IP_HOUR+1 ta vaqt belgisi; 5000 dan ortiq IP bo'lsa — eskirganlari
  //   tozalanadi (baribir ko'p bo'lsa — hammasi).
  const intlMiss = new Map();
  function intlMissLimited(ip) {
    const now = Date.now(), key = ip || '-';
    if (intlMiss.size > 5000) {
      for (const [k, v] of intlMiss) if (!v.some(t => now - t < 3600e3)) intlMiss.delete(k);
      if (intlMiss.size > 5000) intlMiss.clear();
    }
    const arr = (intlMiss.get(key) || []).filter(t => now - t < 3600e3);
    if (arr.length <= OTP_MAX_IP_HOUR) arr.push(now);
    intlMiss.set(key, arr);
    return arr.length > OTP_MAX_IP_HOUR;
  }
  // Oxirgi davrda CHET EL raqamlariga yuborilgan OTP soni (butun tizim). Xato -> null.
  async function intlOtpCount(sinceISO) {
    const r = await sb.from('otp_codes').select('id', { count: 'exact', head: true }).not('phone', 'like', '998%').gte('createdAt', sinceISO);
    if (r.error) { console.error('intl OTP count fail', r.error.code || '', (r.error.message || '').slice(0, 120)); return null; }
    return typeof r.count === 'number' ? r.count : (r.data || []).length;
  }

  async function requestOtp(body) {
    const canon = L.normPhone(body.phone);
    if (!canon) return { ok: false, error: BAD_PHONE };
    const purpose = String(body.purpose || '');
    if (!PURPOSES.has(purpose)) return { ok: false, error: 'Noto‘g‘ri so‘rov.' };
    const intl = canon.slice(0, 3) !== '998';
    if (intl && !INTL_OTP) return { ok: false, error: 'Chet el raqamiga SMS kod yuborish o‘chirilgan. O‘zbekiston raqamidan foydalaning.' };

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
    // Chet el raqami: ro'yxat / telefon almashtirishda — raqam maktab ma'lumotlarida bo'lishi shart (reset — foydalanuvchi
    //   allaqachon mavjud, ya'ni ro'yxatda tekshirilgan).
    if (intl && purpose !== 'reset') {
      const known = await knownPhone(canon);
      if (known === null) return { ok: false, error: 'Server xatosi. Keyinroq urinib ko‘ring.' };
      if (!known) {
        if (intlMissLimited(String(body._ip || '').slice(0, 64))) return { ok: false, error: 'Juda ko‘p so‘rov. Keyinroq urinib ko‘ring.' };
        return { ok: false, error: 'Bu chet el raqami maktab ma’lumotlarida topilmadi. Maktab ma’muriyatidan farzandingiz kartasiga shu raqamni (+ bilan) yozib qo‘yishni so‘rang yoki O‘zbekiston raqamidan foydalaning.' };
      }
    }

    // (2) Anti-abuse: soatlik limit (telefon + IP) + 60s qayta-yuborish (SMS yuboriladigan yo'lда).
    const hourAgo = new Date(Date.now() - 3600e3).toISOString();
    const { data: recent, error: selErr } = await sb.from('otp_codes').select('id').eq('phone', canon).gte('createdAt', hourAgo);
    if (selErr) console.error('OTP select fail:', selErr.code || '', selErr.message || selErr, selErr.details || '', selErr.hint || '');
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

    // Chet el raqamlariga OTP — butun tizim bo'yicha soatlik/sutkalik chegara (xalqaro SMS xarajati himoyasi).
    if (intl) {
      if (!OTP_INTL_HOUR || !OTP_INTL_DAY) return { ok: false, error: 'Chet el raqamiga SMS kod yuborish o‘chirilgan. O‘zbekiston raqamidan foydalaning.' };
      const nH = await intlOtpCount(hourAgo);
      const nD = nH == null ? null : await intlOtpCount(new Date(Date.now() - 864e5).toISOString());
      if (nH == null || nD == null) return { ok: false, error: 'Server xatosi. Keyinroq urinib ko‘ring.' };
      if (nH >= OTP_INTL_HOUR || nD >= OTP_INTL_DAY) return { ok: false, error: 'Chet el raqamlariga kod yuborish vaqtincha cheklangan. Birozdan so‘ng urinib ko‘ring yoki O‘zbekiston raqamidan foydalaning.' };
    }

    const code = L.genCode();
    const codeHash = L.hmacCode(HMAC, canon, purpose, code);
    const expiresAt = new Date(Date.now() + OTP_TTL * 1000).toISOString();
    // Oldingi ishlatilmagan kodlarni bekor qilamiz (faqat oxirgisi amal qilsin).
    await sb.from('otp_codes').update({ consumed: true }).eq('phone', canon).eq('purpose', purpose).eq('consumed', false);
    const { error: insErr } = await sb.from('otp_codes').insert({ phone: canon, codeHash, purpose, expiresAt, attempts: 0, uid, ip });
    if (insErr) { console.error('OTP insert fail:', insErr.code || '', insErr.message || insErr, insErr.details || '', insErr.hint || ''); return { ok: false, error: 'Kod yuborishda xatolik. Qayta urinib ko‘ring.' }; }

    const msg = String(OTP_TPL).replace('{code}', code);
    if (DRY) console.log('[DRY OTP]', redactPhone(canon), purpose, code);
    else {
      let r = null, thrown = null;
      try { r = await eskiz.send(canon, msg); if (!r.ok) console.error('OTP SMS fail', redactPhone(canon), r.error, (r.raw || '').slice(0, 300)); }
      catch (e) { thrown = e || new Error('eskiz'); console.error('OTP SMS exc', redactPhone(canon), (e && (e.message || String(e)) || '').slice(0, 300)); }
      // Chet el raqami: Eskiz ANIQ rad etsa (xalqaro SMS yoqilmagan / balans / taqiqlangan yo'nalish) yoki umuman ulanmasa —
      //   kod KELMAYDI: foydalanuvchiga aytamiz (kod bekor; qayta so'rash 60 soniyadan keyin). Javob noaniq bo'lsa
      //   (timeout/5xx — SMS ketgan bo'lishi mumkin) — odatdagidek «yuborildi».
      if (intl && ((r && !r.ok && !r.ambiguous) || (thrown && definitelyNotSent(thrown)))) {
        try { await sb.from('otp_codes').update({ consumed: true }).eq('phone', canon).eq('purpose', purpose).eq('consumed', false); } catch (_) {}
        return { ok: false, error: 'Chet el raqamiga SMS yuborilmadi (Eskiz’da xalqaro SMS yoqilmagan bo‘lishi mumkin). O‘zbekiston raqamidan foydalaning yoki maktab bilan bog‘laning.' };
      }
    }
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

  // Xodim hisobini bazadagi staff/teachers yozuviga TELEFON bo'yicha AVTOMATIK bog'laydi.
  //   MOLIYAVIY XAVFSIZLIK: faqat aniq BITTA bo'sh moslik bog'lanadi (konservativ). Noaniqlik/band
  //   -> bog'lanmaydi (admin qo'lда hal qiladi). Maosh/davomat summalariga TEGMAYDI — faqat havola.
  //   service_role bilan ishlaydi (RLS chetlab) — bog'lashni FAQAT server/admin o'rnatadi.
  async function linkStaffAccount(uid, canon) {
    const rows = [];
    // HR yozuvlarini o'qiymiz. supabase-js so'rov XATOSINI (timeout/RLS/schema-cache/reset) THROW
    //   QILMAYDI — {data:null,error} qaytaradi. Shuning uchun .error'ni ANIQ tekshiramiz va xato
    //   bo'lsa FAIL-CLOSED (bog'lamaymiz): qisman ro'yxat ambiguity/taken guardни chetlab,
    //   noto'g'ri (boshqa odamга) bog'lashга olib kelardi — moliyaviy xato.
    const { data: st, error: stErr } = await sb.from('staff').select('*');
    if (stErr) { console.error('staff link fetch fail (staff)', stErr.code || '', (stErr.message || '').slice(0, 120)); return { status: 'fetch_fail' }; }
    (st || []).forEach(r => rows.push({ table: 'staff', id: r.id, code: r.staffId || '', phone: r.phone, name: r.name || '', pos: r.position || '', userUid: r.userUid || '' }));
    const { data: te, error: teErr } = await sb.from('teachers').select('*');
    if (teErr) { console.error('staff link fetch fail (teachers)', teErr.code || '', (teErr.message || '').slice(0, 120)); return { status: 'fetch_fail' }; }
    (te || []).forEach(r => rows.push({ table: 'teacher', id: r.id, code: r.teacherId || '', phone: r.phone, name: r.name || '', pos: 'O‘qituvchi', userUid: r.userUid || '' }));
    const res = L.matchStaffByPhone(canon, rows);
    if (res.status !== 'linked') return { status: res.status };     // none | ambiguous | taken -> bog'lanmaydi
    const m = res.match;
    const tbl = m.table === 'teacher' ? 'teachers' : 'staff';
    // 1) Teskari havola — FAQAT yozuv HALI BO'SH bo'lsa (userUid null yoki ''). Bu SHARTLI yozish
    //    read->write orasida boshqa admin bog'lab qo'ygan bo'lsa clobber qilmaydi (TOCTOU yopiq).
    //    Hech qator o'zgarmasa -> konkurrent band qilibdi -> 'taken' (hech narsa yozilmagan, rollback shart emas).
    const { data: bref, error: be } = await sb.from(tbl).update({ userUid: uid }).eq('id', m.id).or('userUid.is.null,userUid.eq.').select('id');
    if (be) { console.error('staff link backref fail', be.code || '', (be.message || '').slice(0, 120)); return { status: 'backref_fail' }; }
    if (!bref || !bref.length) return { status: 'taken' };
    // 2) To'g'ri havola (users). Xato bo'lsa — teskari havolani ORQAGA qaytaramiz (izchillik).
    const { error: fe } = await sb.from('users').update({ staffRefType: m.table, staffRefId: m.id, staffCode: m.code, linkedAt: nowISO(), linkedVia: 'auto' }).eq('id', uid);
    if (fe) { try { await sb.from(tbl).update({ userUid: null }).eq('id', m.id); } catch (_) {} console.error('staff link fwd fail', fe.code || '', (fe.message || '').slice(0, 120)); return { status: 'fwd_fail' }; }
    return { status: 'linked', table: m.table, id: m.id, code: m.code, name: m.name, pos: m.pos || '' };
  }

  async function register(body) {
    const t = L.verifyTicket(HMAC, body.ticket);
    if (!t || t.purpose !== 'register' || !t.phone) return { ok: false, error: 'Tasdiqlash muddati tugagan. Qaytadan boshlang.' };
    const canon = t.phone;
    const role = ROLE_ALIAS.get(String(body.role == null ? '' : body.role).trim().toLowerCase()) || null;
    if (!role) return { ok: false, error: 'Noto‘g‘ri rol. Sahifani yangilang (Ctrl+F5) va «Xodim» yoki «Ota-ona»ni tanlab qaytadan urinib ko‘ring.' };
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
    const verified = (role === 'parent');                 // parent darhol faol; xodim admin tasdig'ini kutadi
    const status = (role === 'staff') ? 'pending' : 'active';
    const { error: uErr } = await sb.from('users').insert({
      id: uid, email, phone: canon, role, verified, status,
      firstName, lastName, name: displayName, createdAt: nowISO(), updatedAt: nowISO(),
    });
    if (uErr) { try { await admin.auth.admin.deleteUser(uid); } catch (_) {} return { ok: false, error: 'Ro‘yxatdan o‘tishda xatolik. Qayta urinib ko‘ring.' }; }
    // Xodim ro'yxatdan o'tganда — HR yozuviga telefon bo'yicha avtomatik bog'lash (registratsiyani BUZMAYDI).
    let linked = null;
    if (role === 'staff') { try { linked = await linkStaffAccount(uid, canon); } catch (e) { console.error('staff link exc', redactPhone(canon), (e && (e.message || String(e)) || '').slice(0, 200)); } }
    const isLinked = !!(linked && linked.status === 'linked');
    return {
      ok: true, role, verified, email, phone: canon, pending: role === 'staff',
      linked: isLinked ? { code: linked.code, name: linked.name, pos: linked.pos || '' } : null,
      message: role === 'staff'
        ? (isLinked
          ? `Ro‘yxatdan o‘tdingiz! Xodimlar ro‘yxatidagi yozuvingiz topildi (${linked.code}${linked.pos ? ' · ' + linked.pos : ''}). Administrator tasdiqlagach (rolingiz tanlangan holda) tizimga kirasiz.`
          : 'Ro‘yxatdan o‘tdingiz! Hisobingiz administrator tasdig‘ini kutmoqda.')
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
    sb, admin: sb, eskiz, cfg: AUTH, smsCfg: SMS,
    anon: () => createClient(supaUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } }),
    verifyJwt: jwt => verifyToken(db, jwt),
  });
  // «Moliya» → «Qarzdorlar» → «Eslatma» (direktor/moliya menejeri JWT bilan; Eskiz — OTP bilan bir xil sozlama).
  //   Modul yuklanmasa ham auth (login/OTP) ISHLAYVERADI — faqat eslatma xizmati vaqtincha o'chadi.
  let smsRemind;
  try { const { makeSmsRemind } = require('./sms-remind.cjs'); smsRemind = makeSmsRemind({ sb, eskiz, smsCfg: SMS, verifyJwt: jwt => verifyToken(db, jwt) }); }
  catch (e) { console.error('sms-remind yuklanmadi:', e && e.message); smsRemind = async () => ({ ok: false, error: 'SMS eslatma xizmati vaqtincha ishlamaydi (server jurnalini tekshiring).' }); }
  const ROUTES = {
    'request-otp': H.requestOtp, 'verify-otp': H.verifyOtp, 'register': H.register,
    'login': H.login, 'reset-confirm': H.resetConfirm, 'change-phone-confirm': H.changePhoneConfirm,
    'sms-remind': smsRemind,
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
  server.listen(PORT, '127.0.0.1', () => console.log(`Iqror AUTH serveri 127.0.0.1:${PORT} (nginx: /authapi/{request-otp,verify-otp,register,login,reset-confirm,change-phone-confirm,sms-remind})`));
}

if (require.main === module) startServer();
module.exports = { makeHandlers, readBody, redactPhone, startServer };
