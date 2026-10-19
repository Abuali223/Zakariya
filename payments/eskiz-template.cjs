/**
 * eskiz-template.cjs — SMS matnini Eskiz'da TASDIQLANGAN shablon naqshiga moslash (sof funksiyalar, tarmoqsiz).
 * -------------------------------------------------------------------
 * Eskiz har bir SMS'ni siz yuborgan ASL matn (original_text) bilan emas, moderator tasdiqlagan NAQSH (template) bilan
 * solishtiradi (GET /api/user/templates -> [{ id, template, original_text, status }]). Naqshda o'zgaruvchi joylar:
 *   %w        — bitta «so'z» (bo'shliqsiz har qanday belgilar)
 *   %d        — bitta «son» (bo'shliqsiz, harfsiz, kamida bitta raqam: 5800000, 09.2026, +998901234567)
 *   %w{a,b}   — a dan b gacha so'z (bo'shliq bilan ajratilgan); %d{a,b} — xuddi shunday sonlar
 * Mos kelmasa Eskiz: «Этот смс текст еще не прошел модерацию» (shablon hali moderatsiyada bo'lsa ham shu xato).
 * ⚠️ Eskiz o'z solishtirish qoidasini rasman e'lon qilmagan — bu yerdagi qoida Eskiz misollariga asoslangan (bo'shliqlar
 *    yig'iladi, qolgani harfma-harf). Shuning uchun u faqat TANLASH/OGOHLANTIRISH uchun: yakuniy hakam — Eskiz'ning o'zi.
 *
 * SMS o'zgaruvchilari imkon qadar BITTA «so'z» qilib yoziladi (har qanday naqshga sig'adi):
 *   summa — 5800000 (bo'shliqsiz), oylar — 09.2026 / 09.2026,10.2026 / 05.2026-10.2026, ism — to'liq; naqsh ismga
 *   kamroq so'z ruxsat bersa — avval qisqartirilgan shakli tanlanadi (composeSms).
 */
// Tasdiqlangan holatlar: service (servis) va reklama. moderation / inproccess / rejected — hali/endi yuborib bo'lmaydi.
const APPROVED = new Set(['service', 'reklama']);
const STATUS_UZ = { service: '✓ Servis (tasdiqlangan)', reklama: '✓ Reklama (tasdiqlangan)', moderation: '… Moderatsiyada',
  inproccess: '… Jarayonda', rejected: '✗ Rad etilgan' };

const squash = s => String(s == null ? '' : s).replace(/\s+/g, ' ').trim();
const reEsc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const VAR_RE = /(%[wd](?:\{\d+,\d+\})?)/;
const W_TOK = '\\S+';
const D_TOK = '[^\\s\\p{L}]*\\d[^\\s\\p{L}]*';

// Naqshdagi o'zgaruvchi: { kind:'w'|'d', min, max } (so'zlar soni).
function parseVar(v) {
  const m = String(v).match(/^%([wd])(?:\{(\d+),(\d+)\})?$/);
  if (!m) return null;
  let a = m[2] ? Number(m[2]) : 1, b = m[3] ? Number(m[3]) : 1;
  if (a > b) { const t = a; a = b; b = t; }
  return { kind: m[1], min: Math.max(1, a), max: Math.max(1, b) };
}
// Eskiz naqshi -> RegExp (butun matn).
function tplRegex(template) {
  const body = squash(template).split(VAR_RE).map(p => {
    const v = parseVar(p);
    if (!v) return reEsc(p);
    const tok = v.kind === 'w' ? W_TOK : D_TOK;
    return v.max > 1 ? `${tok}(?: ${tok}){${v.min - 1},${v.max - 1}}` : tok;
  }).join('');
  return new RegExp('^' + body + '$', 'u');
}
function isApproved(t) { return !!t && APPROVED.has(String(t.status || '')); }
// Matnga mos keladigan birinchi TASDIQLANGAN naqsh (yoki null).
function matchApproved(text, list) {
  const s = squash(text);
  for (const t of (list || [])) {
    if (!isApproved(t) || !String(t.template || '').trim()) continue;
    try { if (tplRegex(t.template).test(s)) return t; } catch (_) {}
  }
  return null;
}

// Bizning shablon ('... {name} ... {month} ...') va Eskiz naqshini qatorlash: o'zgarmas qismlar bir xil bo'lsa —
//   { ok:true, vars:{ name:{kind,min,max,raw}, ... } }; aks holda { ok:false, at, ours, theirs } (birinchi farq).
function alignTemplate(ourTpl, eskizTpl) {
  const ours = squash(ourTpl).split(/(\{\w+\})/);
  const theirs = squash(eskizTpl).split(VAR_RE);
  if (ours.length !== theirs.length) return { ok: false, at: -1, ours: ourTpl, theirs: eskizTpl, reason: 'o‘zgaruvchilar soni farq qiladi' };
  const vars = {};
  for (let i = 0; i < ours.length; i++) {
    if (i % 2 === 0) { if (ours[i] !== theirs[i]) return { ok: false, at: i, ours: ours[i], theirs: theirs[i], reason: 'matn qismi farq qiladi' }; }
    else { const v = parseVar(theirs[i]); if (!v) return { ok: false, at: i, ours: ours[i], theirs: theirs[i], reason: 'o‘zgaruvchi naqshi tushunilmadi' };
      vars[ours[i].slice(1, -1)] = Object.assign({ raw: theirs[i] }, v); }
  }
  return { ok: true, vars };
}
// Qiymat naqsh o'zgaruvchisiga sig'adimi? -> { ok, words, need }
function valueFits(value, v) {
  const words = squash(value).split(' ').filter(Boolean);
  const tokOk = words.every(w => v.kind === 'w' ? /^\S+$/u.test(w) : new RegExp('^' + D_TOK + '$', 'u').test(w));
  return { ok: tokOk && words.length >= v.min && words.length <= v.max, words: words.length, need: v.min === v.max ? String(v.min) : `${v.min}–${v.max}`, kindOk: tokOk };
}

// ---- SMS o'zgaruvchilari (bitta «so'z» shaklida) ----
const smsSom = n => String(Math.max(0, Math.round(Number(n) || 0)));          // 5800000
const fmtMonth = m => { const p = String(m || '').split('-'); return p.length === 2 ? `${p[1]}.${p[0]}` : String(m || ''); };
// Oylar: 1 ta -> 09.2026; 2 ta -> 09.2026,10.2026; 3+ -> birinchi-oxirgi (05.2026-10.2026). Har doim BITTA so'z.
function smsMonths(months) {
  const m = [...new Set((months || []).map(String).filter(Boolean))].sort().map(fmtMonth);
  if (!m.length) return '';
  return m.length <= 2 ? m.join(',') : `${m[0]}-${m[m.length - 1]}`;
}
// Ism variantlari (to'liqdan qisqaga): «Familiya Ism Sharif» -> [to'liq, «Familiya Ism», «Ism», «Familiya»].
function nameVariants(name) {
  const w = squash(name).split(' ').filter(Boolean);
  const out = [w.join(' ')];
  if (w.length >= 3) out.push(w.slice(0, 2).join(' '));
  if (w.length >= 2) out.push(w[1], w[0]);
  return [...new Set(out.filter(Boolean))];
}
const fillTpl = (t, v) => String(t || '').replace(/\{(\w+)\}/g, (_, k) => (v[k] != null ? String(v[k]) : ''));

// SMS matnini yig'adi. approved — Eskiz naqshlari ro'yxati (yoki null: noma'lum). Ism variantlaridan birinchi MOS
//   keladigani tanlanadi; hech biri mos kelmasa — to'liq ism bilan (fit:false — Eskiz rad etishi mumkin).
//   -> { message, fit: true|false|null, templateId, shortened (ism qisqartirildimi) }
function composeSms(tpl, vals, approved) {
  const variants = nameVariants(vals && vals.name);
  if (!variants.length) variants.push('');
  const make = nm => fillTpl(tpl, Object.assign({}, vals, { name: nm }));
  const first = make(variants[0]);
  const list = (approved || []).filter(isApproved);
  if (!approved) return { message: first, fit: null, templateId: null, shortened: false };
  for (let i = 0; i < variants.length; i++) {
    const msg = make(variants[i]); const t = matchApproved(msg, list);
    if (t) return { message: msg, fit: true, templateId: t.id == null ? null : t.id, shortened: i > 0 };
  }
  return { message: first, fit: false, templateId: null, shortened: false };
}

module.exports = { APPROVED, STATUS_UZ, squash, parseVar, tplRegex, isApproved, matchApproved, alignTemplate, valueFits,
  smsSom, fmtMonth, smsMonths, nameVariants, fillTpl, composeSms };
