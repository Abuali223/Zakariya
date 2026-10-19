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
// Telefon: O'zbekiston VA chet el (+ bilan) — server/phone.cjs bilan AYNAN bir xil blok (auth/phone.test.cjs tekshiradi).
/* PHONE-CANON:BEGIN — server/phone.cjs, sb/auth-api.js, admin.html: AYNAN bir xil (auth/phone.test.cjs tekshiradi) */
// Xalqaro telefon kodlari (ITU E.164) -> davlat (ISO 3166-1 alpha-2; Eskiz xalqaro SMS country_code ham shu).
var PHONE_CC = {
  '1': 'US', '7': 'RU',
  '20': 'EG', '27': 'ZA', '30': 'GR', '31': 'NL', '32': 'BE', '33': 'FR', '34': 'ES', '36': 'HU', '39': 'IT',
  '40': 'RO', '41': 'CH', '43': 'AT', '44': 'GB', '45': 'DK', '46': 'SE', '47': 'NO', '48': 'PL', '49': 'DE',
  '51': 'PE', '52': 'MX', '53': 'CU', '54': 'AR', '55': 'BR', '56': 'CL', '57': 'CO', '58': 'VE',
  '60': 'MY', '61': 'AU', '62': 'ID', '63': 'PH', '64': 'NZ', '65': 'SG', '66': 'TH',
  '81': 'JP', '82': 'KR', '84': 'VN', '86': 'CN',
  '90': 'TR', '91': 'IN', '92': 'PK', '93': 'AF', '94': 'LK', '95': 'MM', '98': 'IR',
  '211': 'SS', '212': 'MA', '213': 'DZ', '216': 'TN', '218': 'LY', '220': 'GM', '221': 'SN', '222': 'MR', '223': 'ML',
  '224': 'GN', '225': 'CI', '226': 'BF', '227': 'NE', '228': 'TG', '229': 'BJ', '230': 'MU', '231': 'LR', '232': 'SL',
  '233': 'GH', '234': 'NG', '235': 'TD', '236': 'CF', '237': 'CM', '238': 'CV', '239': 'ST', '240': 'GQ', '241': 'GA',
  '242': 'CG', '243': 'CD', '244': 'AO', '245': 'GW', '248': 'SC', '249': 'SD', '250': 'RW', '251': 'ET', '252': 'SO',
  '253': 'DJ', '254': 'KE', '255': 'TZ', '256': 'UG', '257': 'BI', '258': 'MZ', '260': 'ZM', '261': 'MG', '262': 'RE',
  '263': 'ZW', '264': 'NA', '265': 'MW', '266': 'LS', '267': 'BW', '268': 'SZ', '269': 'KM', '290': 'SH', '291': 'ER',
  '297': 'AW', '298': 'FO', '299': 'GL',
  '350': 'GI', '351': 'PT', '352': 'LU', '353': 'IE', '354': 'IS', '355': 'AL', '356': 'MT', '357': 'CY', '358': 'FI',
  '359': 'BG', '370': 'LT', '371': 'LV', '372': 'EE', '373': 'MD', '374': 'AM', '375': 'BY', '376': 'AD', '377': 'MC',
  '378': 'SM', '380': 'UA', '381': 'RS', '382': 'ME', '383': 'XK', '385': 'HR', '386': 'SI', '387': 'BA', '389': 'MK',
  '420': 'CZ', '421': 'SK', '423': 'LI',
  '500': 'FK', '501': 'BZ', '502': 'GT', '503': 'SV', '504': 'HN', '505': 'NI', '506': 'CR', '507': 'PA', '508': 'PM',
  '509': 'HT', '590': 'GP', '591': 'BO', '592': 'GY', '593': 'EC', '594': 'GF', '595': 'PY', '596': 'MQ', '597': 'SR',
  '598': 'UY', '599': 'CW',
  '670': 'TL', '672': 'NF', '673': 'BN', '674': 'NR', '675': 'PG', '676': 'TO', '677': 'SB', '678': 'VU', '679': 'FJ',
  '680': 'PW', '681': 'WF', '682': 'CK', '683': 'NU', '685': 'WS', '686': 'KI', '687': 'NC', '688': 'TV', '689': 'PF',
  '690': 'TK', '691': 'FM', '692': 'MH',
  '850': 'KP', '852': 'HK', '853': 'MO', '855': 'KH', '856': 'LA', '880': 'BD', '886': 'TW',
  '960': 'MV', '961': 'LB', '962': 'JO', '963': 'SY', '964': 'IQ', '965': 'KW', '966': 'SA', '967': 'YE', '968': 'OM',
  '970': 'PS', '971': 'AE', '972': 'IL', '973': 'BH', '974': 'QA', '975': 'BT', '976': 'MN', '977': 'NP',
  '992': 'TJ', '993': 'TM', '994': 'AZ', '995': 'GE', '996': 'KG', '998': 'UZ'
};
// Asosiy davlatlar: mobil raqamning JAMI uzunligi (davlat kodi bilan). Ro'yxatda yo'q davlat — umumiy qoida.
var PHONE_LEN = {
  '1': [11], '7': [11], '20': [12], '33': [11], '34': [11], '39': [11, 12], '44': [12], '48': [11], '49': [12, 13],
  '61': [11], '81': [12], '82': [11, 12], '86': [13], '90': [12], '91': [12], '92': [12],
  '370': [11], '371': [11], '372': [10, 11], '373': [11], '374': [11], '375': [12], '380': [12], '420': [12], '421': [12],
  '965': [11], '966': [12], '971': [12], '972': [12], '974': [11],
  '992': [12], '993': [11], '994': [12], '995': [12], '996': [12], '998': [12]
};
// Raqam boshidagi davlat kodi (eng uzuni: 3 -> 2 -> 1 raqam) yoki ''.
function phoneCc(d) {
  d = String(d == null ? '' : d);
  for (var n = 3; n >= 1; n--) {
    var c = d.slice(0, n);
    if (c.length === n && Object.prototype.hasOwnProperty.call(PHONE_CC, c)) return c;
  }
  return '';
}
// KANONIK raqam (faqat raqamlar, davlat kodi bilan) yoki '' (yaroqsiz). Qoidalar — fayl boshidagi izohda.
function phoneCanon(input) {
  var s = String(input == null ? '' : input).trim();
  var d = s.replace(/\D/g, '');
  var plus = /^[^0-9]*\+/.test(s);                 // '+' birinchi raqamdan OLDIN (masalan '+7 ...', '(+7) ...')
  if (d.slice(0, 2) === '00') { plus = true; d = d.slice(2); }   // 00 — xalqaro chiqish prefiksi (0048 ... = +48 ...)
  if (plus) d = d.replace(/^0+/, '');              // '+0…' — davlat kodi 0 bilan boshlanmaydi (phoneMask bilan bir xil)
  // Lokal O'zbekiston raqami — FAQAT '+'siz: '+7 903 157 11' (chala xorijiy, 9 raqam) jimgina O'zbekiston
  //   raqamiga (998790315711) aylanib, SMS begonaga ketmasin.
  if (!plus && d.length === 9) d = '998' + d;
  if (d.slice(0, 3) === '998') return (d.length === 12 && '235789'.indexOf(d.charAt(3)) >= 0) ? d : '';
  if (!plus || d.length > 15) return '';           // chet el raqami FAQAT '+' (yoki 00) bilan; E.164: ≤ 15 raqam
  var cc = phoneCc(d);
  if (!cc) return '';
  var lens = PHONE_LEN[cc];
  // Umumiy qoida: jami kamida 10 raqam — kanonik chet el raqami hech qachon 9 xonali bo'lmaydi (9 xonali = O'zbekiston
  //   lokal raqami; aks holda bazadagi '+'siz kanonik raqamni qayta o'qishda O'zbekiston raqamiga aylanib ketardi).
  if (lens ? lens.indexOf(d.length) < 0 : d.length < 10) return '';
  return d;
}
// Kanonik raqamning davlati (ISO): +7 6xx/7xx — Qozog'iston, qolgan +7 — Rossiya.
function phoneIso(canon) {
  var d = String(canon == null ? '' : canon);
  var cc = phoneCc(d);
  if (!cc) return '';
  if (cc === '7') return /^7[67]/.test(d) ? 'KZ' : 'RU';
  return PHONE_CC[cc];
}
// Milliy qism guruhlari: 3-3-2-2 (oxirgi guruh 3 bo'lishi mumkin) — faqat ko'rsatish uchun.
function phoneGroup(n) {
  n = String(n == null ? '' : n);
  var out = [], i = 0, k;
  for (k = 0; k < 2 && n.length - i > 4; k++) { out.push(n.slice(i, i + 3)); i += 3; }
  while (n.length - i > 3) { out.push(n.slice(i, i + 2)); i += 2; }
  if (i < n.length) out.push(n.slice(i));
  return out.join(' ');
}
// Ko'rsatish: +998 90 123 45 67 · +7 903 157 11 24. Kanonik bo'lmasa — o'zgarishsiz qaytadi.
function phonePretty(canon) {
  var raw = canon == null ? '' : String(canon);
  var d = raw.replace(/\D/g, '');
  if (d.length === 12 && d.slice(0, 3) === '998') return '+998 ' + d.slice(3, 5) + ' ' + d.slice(5, 8) + ' ' + d.slice(8, 10) + ' ' + d.slice(10);
  if (!d || phoneCanon('+' + d) !== d) return raw;
  var cc = phoneCc(d);
  return '+' + cc + ' ' + phoneGroup(d.slice(cc.length));
}
// Kiritish MASKASI (brauzer, jonli): '+'siz qisqa raqam — O'zbekiston ('+998 90 123 45 67');
//   '+' (yoki 00) bilan, yoki '+'siz 10+ raqam 998 bilan boshlanmasa — xorijiy ('+7 903 157 11 24').
//   Idempotent: maska natijasini qayta maskalash o'zgartirmaydi; yaroqli raqamni (phoneCanon) o'zgartirmaydi.
//   Raqamlar HECH QACHON tashlab yuborilmaydi: ortiqcha raqam ko'rinib turadi va raqam yaroqsiz bo'ladi (aks holda
//   '+998 ' ortidan yozilgan chet el raqami 9 xonaga kesilib, BOSHQA odamning O'zbekiston raqamiga aylanardi).
function phoneMask(raw) {
  var s = String(raw == null ? '' : raw);
  var d = s.replace(/\D/g, '');
  var plus = /^[^0-9]*\+/.test(s);
  if (d.slice(0, 2) === '00') { plus = true; d = d.slice(2); }
  else if (!plus && d.charAt(0) === '0') return d.slice(0, 15);   // '0…' — '00' yozilmoqda yoki noaniq: o'zgarishsiz
  else if (!plus && !d) return '';                 // maydon tozalandi — bo'sh qoladi ('+998' qaytib «yopishmasin»)
  if (plus) d = d.replace(/^0+/, '');              // xalqaro raqam: davlat kodi 0 bilan boshlanmaydi
  if (d.slice(0, 3) === '998' || (!plus && d.length <= 9)) {
    // '+'siz AYNAN 9 raqam — lokal raqam (998 bilan boshlansa ham: 99 812 34 56), phoneCanon bilan bir xil.
    if (d.slice(0, 3) === '998' && (plus || d.length !== 9)) d = d.slice(3);
    var rest = d.slice(9, 15); d = d.slice(0, 9);  // operator(2) + raqam(7); ortig'i — alohida, ko'rinadi
    var out = '+998';
    if (d.length) out += ' ' + d.slice(0, 2);
    if (d.length > 2) out += ' ' + d.slice(2, 5);
    if (d.length > 5) out += ' ' + d.slice(5, 7);
    if (d.length > 7) out += ' ' + d.slice(7, 9);
    if (rest) out += ' ' + rest;
    return out;
  }
  d = d.slice(0, 15);
  if (!d) return '+';
  var cc = phoneCc(d);
  if (!cc || d.length <= cc.length) return '+' + d;
  return '+' + cc + ' ' + phoneGroup(d.slice(cc.length));
}
/* PHONE-CANON:END */
// Kanonik raqam ('998901234567' | '79031571124') yoki null.
export function normPhone(input) {
  return phoneCanon(input) || null;
}
export function phoneToEmail(canon, domain) {
  const p = String(canon || "").replace(/\D/g, "");
  return `${p}@${String(domain || "phone.iqroacademy.uz").replace(/^@/, "")}`;
}
// Ko'rsatish uchun: +998 90 123 45 67 · +7 903 157 11 24
export function prettyPhone(canon) {
  return phonePretty(canon || "");
}
// Input MASKASI: foydalanuvchi yozganда jonli formatlaydi. Odatda '+998 ' (O'zbekiston); '+' (yoki 00) bilan boshlansa —
//   chet el raqami ('+7 903 157 11 24'). Qaytaradi: ko'rsatiladigan satr. Kanonik uchun normPhone(shu satr).
//   Maydonda oldindan '+998 ' turadi: foydalanuvchi uning ortidan yana '+' yozsa ('+998 +7…') — chet el raqamini
//   boshlamoqchi: '+998' olib tashlanadi (aks holda raqam O'zbekiston formatiga «yopishib» buzilardi).
//   Ko'rinmas belgilar (kontaktlardan nusxa olinganda: yo'nalish belgilari U+200E/U+202D…, BOM) avval olib tashlanadi.
const INVIS = /[\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF]/g;
export function maskPhone(raw) {
  const s = String(raw == null ? "" : raw).replace(INVIS, "");
  return phoneMask(/^\s*\+\s*998\s*\+/.test(s) ? s.replace(/^\s*\+\s*998\s*/, "") : s);
}
// Yaroqsiz raqam uchun aniqroq sabab (bo'lmasa ''): «+998 » ortidan yana to'liq 998… yozilgan (998 998 90 123 45 67).
//   Faqat MASLAHAT — raqam avtomatik o'zgartirilmaydi (foydalanuvchi o'zi tekshirib tuzatadi).
export function phoneHint(raw) {
  const d = String(raw == null ? "" : raw).replace(INVIS, "").replace(/\D/g, "");
  if (d.length === 15 && d.slice(0, 6) === "998998" && phoneCanon(d.slice(3)))
    return `Raqam boshida «998» ikki marta yozilgan. Raqamingiz ${phonePretty(d.slice(3))} bo‘lsa — boshidagi ortiqcha «998» ni o‘chiring.`;
  return "";
}
// Telefon maydonini maskaga ulash. Har kiritishda maska qo'llanadi, lekin KURSOR TAHRIR JOYIDA qoladi (o'ngidagi raqamlar
//   soni saqlanadi): value qayta yozilganda brauzer kursorni oxirga sakratadi va o'rtadagi tuzatishdan keyingi raqamlar
//   oxirga tushib, tartib buzilardi — boshqa YAROQLI +998 raqam chiqib, kod begona odamga ketishi mumkin edi.
//   - faqat bo'shliq/ajratgich o'chirilsa (maska uni qaytarib, tugma «ishlamay» qolardi) — yonidagi raqam o'chadi;
//   - to'liq raqam qo'yilsa (paste: '998901234567', '+998 90 …', ko'rinmas belgilar bilan ham) — maydon shu raqam bilan
//     almashtiriladi ('+998 ' ortiga yopishib '998998…' bo'lib qolmaydi). To'liq bo'lmagan matn odatdagidek qo'yiladi.
export function bindPhoneInput(el) {
  if (!el || el.__iqPhone) return;
  el.__iqPhone = true;
  const digits = s => String(s).replace(/\D/g, "");
  const uz = s => /^\+998( |$)/.test(s);                            // O'zbekiston ko'rinishi: '+998 …'
  let prev = el.value;
  el.addEventListener("beforeinput", () => { prev = el.value; });     // tahrirdan OLDINGI qiymat (dastur o'zgartirgan bo'lsa ham)
  const put = (m, after) => {           // m — maskalangan qiymat; kursor o'ngida `after` ta raqam qoladi
    el.value = m;
    let k = m.length, n = 0;
    while (k > 0 && n < after) { k--; if (/\d/.test(m.charAt(k))) n++; }
    const lo = uz(m) ? Math.min(5, m.length) : 0;                    // '+998 ' ichiga qadam qo'ymaymiz
    if (after > 0) while (k > lo && m.charAt(k - 1) === " ") k--;
    try { el.setSelectionRange(k, k); } catch (_) {}
  };
  el.addEventListener("input", e => {
    let v = el.value;
    let pos = typeof el.selectionEnd === "number" ? el.selectionEnd : v.length;
    const t = (e && e.inputType) || "";
    if ((t === "deleteContentBackward" || t === "deleteContentForward") && v.length < prev.length && maskPhone(v) === prev) {
      // Faqat ajratgich o'chirildi: o'chirish yo'nalishidagi eng yaqin RAQAMni o'chiramiz ('+998' prefiksi raqamlaridan
      //   tashqari — u yerda tugma avvalgidek hech narsa qilmaydi).
      const lo = uz(prev) ? 4 : 0;
      if (t === "deleteContentForward") {
        let k = pos; while (k < v.length && !/\d/.test(v.charAt(k))) k++;
        if (k < v.length && k >= lo) v = v.slice(0, k) + v.slice(k + 1);
      } else {
        let k = pos; while (k > 0 && !/\d/.test(v.charAt(k - 1))) k--;
        if (k > 0 && k - 1 >= lo) { v = v.slice(0, k - 1) + v.slice(k); pos = k - 1; }
      }
    }
    const after = digits(v.slice(pos)).length;
    const m = maskPhone(v);
    if (m !== el.value) put(m, after);
    prev = el.value;
  });
  el.addEventListener("paste", e => {
    const cd = e.clipboardData || (typeof window !== "undefined" && window.clipboardData);
    const txt = cd && typeof cd.getData === "function" ? String(cd.getData("text") || "") : "";
    const clean = txt.replace(INVIS, "").trim();
    if (!clean || !phoneCanon(clean)) return;          // to'liq raqam emas — brauzer odatdagidek qo'yadi
    e.preventDefault();
    put(maskPhone(clean), 0);
    prev = el.value;
    try { el.dispatchEvent(new Event("input", { bubbles: true })); } catch (_) {}
  });
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
// Serverga raqam DOIM '+' bilan (E.164) yuboriladi: normPhone() natijasi — kanonik raqam ('+'siz: '998901234567',
//   chet el '79031571124'); chet el raqami '+'siz serverda yaroqsiz (noaniq) — shuning uchun '+' qo'shamiz.
//   Xom kiritma berilsa ham ishlaydi (avval kanoniklashtiriladi).
function wirePhone(p) {
  const c = phoneCanon(p);
  if (c) return "+" + c;
  const d = String(p == null ? "" : p).replace(/\D/g, "");
  return d ? "+" + d : String(p == null ? "" : p);
}
// purpose: 'register' | 'reset' | 'change_phone'. change_phone uchun jwt kerak (joriy seans tokeni).
export async function requestOtp(phone, purpose, opts) {
  const o = opts || {};
  return post("/request-otp", { phone: wirePhone(phone), purpose, jwt: o.jwt });
}
export async function verifyOtp(phone, purpose, code) {
  return post("/verify-otp", { phone: wirePhone(phone), purpose, code });
}
// register -> {ok, verified, pending, role, message}. Parol (step1'dan) mijozда saqlanadi.
export async function register(ticket, password, firstName, lastName, role) {
  return post("/register", { ticket, password, firstName, lastName, role });
}
// login -> seansni O'RNATADI (setSession) va {ok, role, verified, status} qaytaradi.
export async function login(phone, password) {
  const r = await post("/login", { phone: wirePhone(phone), password });
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
  normPhone, phoneToEmail, prettyPhone, maskPhone, phoneHint, bindPhoneInput, validatePassword,
  requestOtp, verifyOtp, register, login, resetConfirm, changePhoneConfirm, currentJwt,
};
