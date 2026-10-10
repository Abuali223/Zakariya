// =====================================================================
// auth-api.js — telefon+parol+OTP auth uchun MIJOZ qatlami (frontend shu modulni chaqiradi).
//   UI auth-server endpointlarini (/authapi/*) bilmaydi — faqat shu modulni chaqiradi
//   (Supabase'ga ko'chishga tayyor abstraktsiya). Login/register'dan keyin brauzer seansi
//   (supabase.auth.setSession) shu yerda o'rnatiladi.
//
//   Barcha SOF yordamchilar (normPhone/validatePassword/...) server auth/lib.cjs bilan BIR XIL
//   mantiqда — validatsiya frontend VA backendда ikki marta (spec talabi).
// =====================================================================
import { supabase } from "./_core.js";
import { SUPABASE_URL } from "./sb-config.js";

// Auth-server bazasi: global override bo'lsa — o'shani, aks holda SUPABASE_URL origini + /authapi.
//   (Brauzer api.iqror.uz'ga cross-origin murojaat qiladi — server CORS qaytaradi.)
function base() {
  try { if (typeof window !== "undefined" && window.IQROR_AUTH_BASE) return String(window.IQROR_AUTH_BASE).replace(/\/+$/, ""); } catch (_) {}
  try { return new URL(SUPABASE_URL).origin + "/authapi"; } catch (_) { return "/authapi"; }
}

// ---------- SOF yordamchilar (server lib.cjs bilan bir xil) ----------
export function normPhone(input) {
  let d = String(input == null ? "" : input).replace(/\D/g, "");
  if (d.length === 9) d = "998" + d;
  if (d.length === 12 && d.startsWith("998") && "235789".includes(d[3])) return d;
  return null;
}
export function phoneToEmail(canon, domain) {
  const p = String(canon || "").replace(/\D/g, "");
  return `${p}@${String(domain || "phone.iqroacademy.uz").replace(/^@/, "")}`;
}
// Ko'rsatish uchun: +998 90 123 45 67
export function prettyPhone(canon) {
  const d = String(canon || "").replace(/\D/g, "");
  if (d.length !== 12) return canon || "";
  return `+${d.slice(0, 3)} ${d.slice(3, 5)} ${d.slice(5, 8)} ${d.slice(8, 10)} ${d.slice(10, 12)}`;
}
// Input MASKASI: foydalanuvchi yozganда jonli formatlaydi. Har doim '+998 ' bilan boshlanadi.
//   Qaytaradi: ko'rsatiladigan satr. Kanonik uchun normPhone(shu satr).
export function maskPhone(raw) {
  let d = String(raw == null ? "" : raw).replace(/\D/g, "");
  if (d.startsWith("998")) d = d.slice(3);
  else if (d.length === 9) { /* lokal 9 xona */ }
  d = d.slice(0, 9);                                  // operator(2)+raqam(7)
  let out = "+998";
  if (d.length) out += " " + d.slice(0, 2);
  if (d.length > 2) out += " " + d.slice(2, 5);
  if (d.length > 5) out += " " + d.slice(5, 7);
  if (d.length > 7) out += " " + d.slice(7, 9);
  return out;
}
// Parol qoidalari -> { ok, errors:[], checks:{len,upper,lower,digit} } (jonli ko'rsatkichlar uchun).
export function validatePassword(pw) {
  pw = String(pw == null ? "" : pw);
  const checks = { len: pw.length >= 8, upper: /[A-Z]/.test(pw), lower: /[a-z]/.test(pw), digit: /[0-9]/.test(pw) };
  const errors = [];
  if (!checks.len) errors.push("Kamida 8 ta belgi");
  if (!checks.upper) errors.push("Kamida 1 ta katta harf (A-Z)");
  if (!checks.lower) errors.push("Kamida 1 ta kichik harf (a-z)");
  if (!checks.digit) errors.push("Kamida 1 ta raqam (0-9)");
  if (pw.length > 72) errors.push("Parol juda uzun (maks. 72)");
  return { ok: errors.length === 0, errors, checks };
}

// ---------- HTTP ----------
async function post(path, body) {
  let res;
  try {
    res = await fetch(base() + path, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {}),
    });
  } catch (e) { return { ok: false, error: "Internet aloqasi yo‘q. Qayta urinib ko‘ring." }; }
  let j = null; try { j = await res.json(); } catch (_) {}
  if (!j) return { ok: false, error: "Server javobi noto‘g‘ri. Keyinroq urinib ko‘ring." };
  return j;
}

// ---------- API ----------
// purpose: 'register' | 'reset' | 'change_phone'. change_phone uchun jwt kerak (joriy seans tokeni).
export async function requestOtp(phone, purpose, opts) {
  const o = opts || {};
  return post("/request-otp", { phone, purpose, jwt: o.jwt });
}
export async function verifyOtp(phone, purpose, code) {
  return post("/verify-otp", { phone, purpose, code });
}
// register -> {ok, verified, pending, role, message}. Parol (step1'dan) mijozда saqlanadi.
export async function register(ticket, password, firstName, lastName, role) {
  return post("/register", { ticket, password, firstName, lastName, role });
}
// login -> seansni O'RNATADI (setSession) va {ok, role, verified, status} qaytaradi.
export async function login(phone, password) {
  const r = await post("/login", { phone, password });
  if (r && r.ok && r.access_token && r.refresh_token) {
    try { await supabase().auth.setSession({ access_token: r.access_token, refresh_token: r.refresh_token }); }
    catch (e) { return { ok: false, error: "Seans o‘rnatilmadi. Qayta urinib ko‘ring." }; }
  }
  return r;
}
export async function resetConfirm(ticket, newPassword) {
  return post("/reset-confirm", { ticket, newPassword });
}
export async function changePhoneConfirm(ticket) {
  return post("/change-phone-confirm", { ticket });
}
// Joriy seans JWT (change_phone/profil uchun).
export async function currentJwt() {
  try { const { data } = await supabase().auth.getSession(); return (data.session && data.session.access_token) || ""; }
  catch (_) { return ""; }
}

export default {
  normPhone, phoneToEmail, prettyPhone, maskPhone, validatePassword,
  requestOtp, verifyOtp, register, login, resetConfirm, changePhoneConfirm, currentJwt,
};
