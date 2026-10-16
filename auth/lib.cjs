/**
 * auth/lib.cjs — SOF (toza) yordamchilar: telefon normalizatsiyasi, parol qoidalari,
 * OTP kod generatsiya/hash, va qisqa muddatli imzolangan "ticket" (OTP tasdiqlangani isboti).
 * -------------------------------------------------------------------
 * Hammasi DB'siz, toza funksiyalar -> birlik testlari oson. Maxfiy kalit (hmacSecret)
 * faqat serverda (config.json) bo'ladi — bu modul uni argument sifatida oladi, saqlamaydi.
 *
 * Parol HECH QAchON bu yerda saqlanmaydi/hash qilinmaydi — parolni Supabase Auth (bcrypt)
 * boshqaradi. Bu modul faqat OTP kodini (6 xonali) va ticketni hash/imzolaydi.
 */
const crypto = require('crypto');
const P = require('../server/phone.cjs');

// Konstant-vaqtли solishtiruv (timing side-channel'ni kamaytiradi).
function tseq(a, b) {
  const ab = Buffer.from(String(a == null ? '' : a));
  const bb = Buffer.from(String(b == null ? '' : b));
  if (ab.length !== bb.length) return false;
  try { return crypto.timingSafeEqual(ab, bb); } catch (_) { return false; }
}

// Telefonni KANONIK formatga keltiradi (server/phone.cjs phoneCanon — brauzer sb/auth-api.js va admin.html bilan
//   AYNAN bir xil qoida): O'zbekiston '998XXXXXXXXX' ('+998 90 123 45 67', '998901234567', '901234567'; operator
//   2x/3x/5x/7x/8x/9x) yoki chet el raqami FAQAT '+' (yoki 00) bilan: '+7 903 157 11 24' -> '79031571124'.
//   Yaroqsiz -> null.
function normPhone(input) {
  return P.phoneCanon(input) || null;
}
// Allaqachon KANONIK raqam (ticket / users.phone: chet el raqami '+'siz saqlanadi) yoki kiritilgan raqam -> kanonik | null.
function canonOf(x) {
  return P.canonOf(x) || null;
}

// Xodim/o'qituvchi HR yozuvini telefon bo'yicha hisobga BOG'LASH uchun MOSLIKNI aniqlaydi.
//   MOLIYAVIY XAVFSIZLIK — eng konservativ: FAQAT aniq BITTA bo'sh (bog'lanmagan) moslik bo'lsa
//   bog'laymiz. Noaniqlik (bir nechta yozuvда bir xil telefon) yoki band yozuv -> bog'lamaymiz
//   (admin qo'lда hal qiladi). Bir xatolik noto'g'ri odamга maosh/davomat bog'lashга olib keladi.
//   rows: [{ table:'staff'|'teacher', id, code, phone, name, userUid }]
//   Qaytaradi: { status:'linked'|'none'|'ambiguous'|'taken', match?, count? }
function matchStaffByPhone(canon, rows) {
  const c = canonOf(canon);                                         // ticket'dagi kanonik raqam (chet el ham)
  if (!c) return { status: 'none' };
  const tail = c.slice(-9);
  const all = (rows || []).filter(Boolean);
  const hits = all.filter(r => normPhone(r.phone) === c);          // KANONIK aniq tenglik
  // "Yaqin" mosliklar: oxirgi 9 raqam bir xil, lekin qat'iy normalizatsiya o'tmagan (chala/trunk/
  //   xorijiy formatдаги HR telefonlari). Ular YASHIRIN dublikat bo'lishi mumkin -> avtomatik
  //   bog'lamaymiz (ambiguity). Faqat avtomatik bog'lashni TO'XTATADI (xavfsiz yo'nalish), hech
  //   qachon NOTO'G'RI bog'lash yaratmaydi. (admin.html pmCanonPhone bilan bir xil asosда.)
  const near = all.filter(r => {
    if (normPhone(r.phone) === c) return false;
    const d = String(r.phone == null ? '' : r.phone).replace(/\D/g, '');
    return d.length >= 9 && d.slice(-9) === tail;
  });
  if (hits.length + near.length === 0) return { status: 'none' };
  if (hits.length !== 1 || near.length > 0) return { status: 'ambiguous', count: hits.length + near.length };
  const r = hits[0];
  if (r.userUid) return { status: 'taken', match: r };    // yagona moslik, lekin allaqachon boshqa hisobга bog'langan
  return { status: 'linked', match: r };                  // aniq bitta BO'SH moslik + yaqin nizo yo'q -> bog'laymiz
}

// Kanonik telefon -> sintetik email. Masalan 998901234567 -> '998901234567@phone.iqroacademy.uz'.
function phoneToEmail(canonicalPhone, domain) {
  const p = String(canonicalPhone || '').replace(/\D/g, '');
  const dom = String(domain || 'phone.iqroacademy.uz').replace(/^@/, '');
  return `${p}@${dom}`;
}

// Telefonni ko'rsatish uchun chiroyli format: +998 90 123 45 67 · +7 903 157 11 24
function prettyPhone(canonicalPhone) {
  return P.phonePretty(canonicalPhone || '');
}

// Parol qoidalari (server + frontend bir xil ishlatadi). { ok, errors:[...] }.
//   >=8 belgi; >=1 katta harf (A-Z); >=1 kichik harf (a-z); >=1 raqam (0-9).
function validatePassword(pw) {
  pw = String(pw == null ? '' : pw);
  const errors = [];
  if (pw.length < 8) errors.push('Kamida 8 ta belgi');
  if (!/[A-Z]/.test(pw)) errors.push('Kamida 1 ta katta harf (A-Z)');
  if (!/[a-z]/.test(pw)) errors.push('Kamida 1 ta kichik harf (a-z)');
  if (!/[0-9]/.test(pw)) errors.push('Kamida 1 ta raqam (0-9)');
  if (pw.length > 72) errors.push('Parol juda uzun (maks. 72 belgi)');   // bcrypt chegarasi
  return { ok: errors.length === 0, errors };
}

// 6 xonali tasodifiy OTP kod (kriptografik). '000000'..'999999'.
function genCode() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, '0');
}

// OTP kodini hash qiladi — telefon+maqsadga BOG'LANGAN (kodni boshqa telefon/maqsadда
//   qayta ishlatib bo'lmasin). HMAC-SHA256(secret, 'phone|purpose|code') hex.
function hmacCode(secret, phone, purpose, code) {
  return crypto.createHmac('sha256', String(secret || ''))
    .update(`${phone}|${purpose}|${code}`).digest('hex');
}

function b64url(buf) { return Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); }
function b64urlDecode(s) { s = String(s || '').replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '='; return Buffer.from(s, 'base64'); }

// Qisqa muddatli imzolangan ticket: "OTP tasdiqlandi" holatini DB'siz tashiydi.
//   payload — ixtiyoriy obyekt (masalan {phone, purpose, uid, newPhone}). exp qo'shiladi.
//   Format: base64url(json).hmacHex . Server maxfiy kaliti bilan tekshiriladi.
function signTicket(secret, payload, ttlSec, nowMs) {
  const now = Number(nowMs || Date.now());
  const body = { ...(payload || {}), exp: Math.floor(now / 1000) + Number(ttlSec || 600) };
  const p = b64url(JSON.stringify(body));
  const sig = crypto.createHmac('sha256', String(secret || '')).update(p).digest('hex');
  return `${p}.${sig}`;
}
// Ticketni tekshiradi -> payload obyekti | null (imzo noto'g'ri yoki muddati o'tgan).
function verifyTicket(secret, token, nowMs) {
  const s = String(token || '');
  const dot = s.indexOf('.');
  if (dot < 1) return null;
  const p = s.slice(0, dot), sig = s.slice(dot + 1);
  const expect = crypto.createHmac('sha256', String(secret || '')).update(p).digest('hex');
  if (!tseq(sig, expect)) return null;
  let body; try { body = JSON.parse(b64urlDecode(p).toString('utf8')); } catch (_) { return null; }
  const now = Math.floor(Number(nowMs || Date.now()) / 1000);
  if (!body || typeof body.exp !== 'number' || body.exp < now) return null;
  return body;
}

module.exports = {
  tseq, normPhone, canonOf, phoneToEmail, prettyPhone, validatePassword,
  genCode, hmacCode, signTicket, verifyTicket, matchStaffByPhone,
};
