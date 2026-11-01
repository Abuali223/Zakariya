/**
 * sms-tpl-check.cjs — «Sozlamalar → 📱 Xabarnomalar» → «Eskiz shabloniga mosligini tekshirish».
 * -------------------------------------------------------------------
 *   POST /authapi/sms-tpl-check   { jwt, texts: { new_invoice?, debt_reminder?, manual_remind? } }
 *
 *   - KIM: FAOL Direktor yoki Direktor tayinlagan xabarnoma muharriri (notify_settings 'general'.editors) — serverda.
 *   - Eskiz'dagi SMS shablonlari (GET /api/user/templates, 60 s kesh) o'qiladi va har matn bir nechta HAR XIL namunaviy
 *     qiymat (ism / oy / summa) bilan to'ldirilib TASDIQLANGAN naqshlar bilan solishtiriladi (payments/eskiz-template.cjs —
 *     sms-worker va «Eslatma» shu qoida bilan yig'adi). Moderator misol matnni so'zma-so'z tasdiqlagan bo'lsa ham ushlanadi
 *     (bitta namunagina mos keladi -> «faqat ba'zi qiymatlar bilan»).
 *   - HECH NARSA YUBORILMAYDI va hech narsa yozilmaydi. Natija: har matn uchun mos/mos emas, mos naqsh id'si, SMS bo'laklari
 *     soni (GSM-7 160/153, UCS-2 70/67), noma'lum o'zgaruvchilar; Eskiz'dagi shablonlar ro'yxati (holati bilan).
 */
const { smsParts } = require('../payments/sms.cjs');
const T = require('../payments/eskiz-template.cjs');

const KEYS = ['new_invoice', 'debt_reminder', 'manual_remind'];
const VARS = new Set(['name', 'month', 'amount', 'due']);
// Namunalar: har xil uzunlikdagi ism, bitta/bir nechta oy, har xil summa (bitta «so'z» shaklida — haqiqiy SMS kabi).
const SAMPLES = {
  new_invoice: [{ name: 'Aliyeva Malika', month: '10.2026', amount: '2900000', due: '2900000' },
    { name: 'Karimov Jasur Botirovich', month: '09.2026', amount: '3150000', due: '3150000' }],
  debt: [{ name: 'Aliyeva Malika', month: '10.2026', amount: '2900000', due: '2900000' },
    { name: 'Karimov Jasur Botirovich', month: '08.2026-10.2026', amount: '8700000', due: '8700000' }],
};

function makeSmsTplCheck(deps) {
  const { sb, verifyJwt } = deps;
  const src = deps.eskiz || deps.tplReader || null;
  const now = deps.now || (() => Date.now());
  let cache = null, cacheAt = 0;
  async function eskizList() {
    if (!src || typeof src.templates !== 'function') return { ok: false, error: 'Eskiz ulanmagan (serverda sms sozlamasi yo‘q yoki SMS o‘chirilgan).' };
    if (cache && now() - cacheAt >= 0 && now() - cacheAt < 60e3) return cache;
    let r;
    try { r = await src.templates({ timeoutMs: 8000 }); }
    catch (e) { return { ok: false, error: 'Eskiz bilan bog‘lanib bo‘lmadi: ' + String((e && e.message) || e).slice(0, 120) }; }
    if (!r || !r.ok || !Array.isArray(r.list)) return { ok: false, error: 'Eskiz shablonlari o‘qilmadi: ' + String((r && r.error) || '').slice(0, 120) + ((r && r.httpStatus === 401) ? ' (Eskiz login/parol yaroqsiz)' : '') };
    cache = { ok: true, list: r.list }; cacheAt = now();
    return cache;
  }
  async function allowed(uid) {
    const { data: urows, error } = await sb.from('users').select('id,role,status').eq('id', uid).limit(1);
    if (error) return { err: 'Server xatosi (foydalanuvchi). Keyinroq urinib ko‘ring.' };
    const u = urows && urows[0]; const st = String((u && u.status) || '');
    if (!u || !(st === '' || st === 'active')) return { no: true };
    if (String(u.role || '') === 'director') return { yes: true };
    const g = await sb.from('notify_settings').select('id,editors').eq('id', 'general').limit(1);
    if (g.error) return { err: 'Server xatosi (sozlamalar). Keyinroq urinib ko‘ring.' };
    const ed = g.data && g.data[0] && Array.isArray(g.data[0].editors) ? g.data[0].editors.map(String) : [];
    return ed.includes(String(uid)) ? { yes: true } : { no: true };
  }
  return async function smsTplCheck(body) {
    body = body || {};
    const uid = await verifyJwt(body.jwt);
    if (!uid) return { ok: false, error: 'Seans tugagan — qaytadan kiring.' };
    const a = await allowed(uid);
    if (a.err) return { ok: false, error: a.err };
    if (!a.yes) return { ok: false, error: 'Ruxsat yo‘q: faqat Direktor va u tayinlagan xabarnoma muharrirlari.' };
    const texts = body.texts && typeof body.texts === 'object' && !Array.isArray(body.texts) ? body.texts : null;
    if (!texts) return { ok: false, error: 'Tekshiriladigan matn yo‘q.' };
    const keys = KEYS.filter(k => typeof texts[k] === 'string' && texts[k].trim());
    if (!keys.length) return { ok: false, error: 'Tekshiriladigan matn yo‘q.' };
    if (keys.some(k => texts[k].length > 600)) return { ok: false, error: 'Matn juda uzun (600 belgidan oshmasin).' };
    const E = await eskizList();
    const list = E.ok ? E.list : null;
    const checks = {};
    for (const k of keys) {
      const tpl = String(texts[k]);
      const unknown = [...new Set((tpl.match(/\{(\w+)\}/g) || []).map(x => x.slice(1, -1)).filter(v => !VARS.has(v)))];
      const samples = SAMPLES[k === 'new_invoice' ? 'new_invoice' : 'debt'];
      const res = samples.map(v => T.composeSms(tpl, v, list));
      const longest = res.reduce((m, r) => (r.message.length > m.length ? r.message : m), '');
      const fits = res.map(r => r.fit);
      const fit = list ? (fits.every(f => f === true) ? true : (fits.some(f => f === true) ? 'partial' : false)) : null;
      const ids = [...new Set(res.map(r => r.templateId).filter(x => x != null))];
      // Mos kelmasa — eng yaqin tasdiqlangan naqsh bilan birinchi farq (moderatorga qanday matn yuborish kerakligini ko'rsatadi).
      let hint = null;
      if (list && fit !== true) {
        for (const t of list.filter(T.isApproved)) {
          const al = T.alignTemplate(tpl, t.template);
          if (al.ok) { hint = { templateId: t.id == null ? null : t.id, reason: 'matn qismlari mos, lekin o‘zgaruvchi qiymati naqshga sig‘madi (masalan ism so‘zlari soni)' }; break; }
        }
      }
      checks[k] = { sample: res[0].message, fit, templateIds: ids, parts: smsParts(longest), unknownVars: unknown, nameShort: res.some(r => r.shortened), hint };
    }
    const templates = list ? list.slice(0, 50).map(t => ({ id: t.id == null ? null : t.id, status: t.status, statusUz: T.STATUS_UZ[t.status] || t.status || '?', approved: T.isApproved(t), pattern: String(t.template || '').slice(0, 600), original: String(t.original || '').slice(0, 600) })) : [];
    return { ok: true, eskiz: E.ok ? { ok: true, count: list.length, approved: list.filter(T.isApproved).length } : { ok: false, error: E.error }, checks, templates };
  };
}

module.exports = { makeSmsTplCheck, SAMPLES };
