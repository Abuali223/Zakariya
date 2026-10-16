/**
 * sms-remind.cjs — «Moliya» → «Qarzdorlar» → «Eslatma»: bitta o'quvchining ota-onasiga QO'LDA SMS eslatma (Eskiz).
 * -------------------------------------------------------------------
 *   POST /authapi/sms-remind   { jwt, studentId, preview? }
 *
 *   - KIM: faqat FAOL direktor / moliya menejeri («Moliya» bo'limi kimga ochiq bo'lsa) —
 *     config.json -> sms.remindRoles bilan o'zgartiriladi ([] = hech kim). Rol serverda (users jadvali) tekshiriladi.
 *   - O'QUVCHI: bosilgan kalit (fakturadagi studentId: o'quvchining studentId'si YOKI eski hujjat id'si) BITTA
 *     o'quvchiga mos bo'lishi shart; to'qnashuvda — rad (SMS boshqa oilaga ketmasin). Keyin hamma narsa o'quvchining
 *     KANONIK kaliti (studentId || id) bilan: qarz ikkala kalitdagi fakturalardan, kunlik qulf — kanonik kalit bilan.
 *   - QARZ SERVERDA hisoblanadi (invoices; mijoz yuborgan summaga ishonilmaydi) — «Qarzdorlar» kartasi
 *     bilan BIR XIL qoida: bekor/qaytarilgan -> 0, to'langan -> 0, aks holda summa − to'langan;
 *     faqat joriy (Toshkent) oygacha bo'lgan oylar (oldindan yaratilgan kelgusi oy qarz emas).
 *   - TELEFON: student_private.parentPhone (yaroqsiz/bo'sh bo'lsa parentPhone2), kanonik 998XXXXXXXXX.
 *   - TAKROR / XARAJAT himoyasi: bitta o'quvchiga KUNIGA 1 ta (Toshkent sanasi) — sms_log id
 *     "remind__<kanonik kalit>__<YYYY-MM-DD>" ATOMIK claim (insert; PK to'qnashuvi = allaqachon yuborilmoqda).
 *     Eskiz ANIQ rad etsa (failed) — shu kuni ko'pi bilan remindMaxRetries marta qayta urinish. Holat NOANIQ bo'lsa
 *     (tarmoq xatosi/timeout — SMS ketgan bo'lishi mumkin: 'unknown'; jarayon uzilgan: 'sending') — shu kuni qayta
 *     YUBORILMAYDI (ota-onaga ikki marta SMS ketmasin).
 *     Limit: foydalanuvchiga soatiga remindMaxPerHour ta, maktabga kuniga remindMaxPerDay ta (0 = o'chirilgan).
 *     Limit claim'dan KEYIN ham qayta sanaladi (parallel so'rovlar limitdan oshib keta olmaydi).
 *   - preview:true — hech narsa yubormaydi/yozmaydi: matn, telefon, qarz va bugungi holatni qaytaradi
 *     (admin tasdiqlash oynasida ANIQ nima ketishini ko'radi).
 *   - Matn: sms.templates.remind -> sms.templates.debt -> standart (sms-worker bilan bir xil).
 *     ⚠️ Eskiz faqat TASDIQLANGAN shablonga mos matnni yuboradi (README: «Eskiz SMS shabloni»).
 */
const L = require('./lib.cjs');
const { DEF_DEBT, fmtSom, fmtMonth, fillTpl, tashkentDay, tashkentDayStartISO, definitelyNotSent, sendStatus, smsName } = require('../payments/sms.cjs');

// Logda telefonni qisman yashirish (PII).
const redact = p => { const d = String(p || '').replace(/\D/g, ''); return d.length >= 6 ? d.slice(0, 5) + '***' + d.slice(-2) : '***'; };
// Qatorlar SONI (PostgREST count=exact, head) — max_rows (1000) chegarasiga bog'liq emas. Xato -> null.
async function countRows(q) { const r = await q; if (r.error) return null; return typeof r.count === 'number' ? r.count : (r.data || []).length; }
// Sozlama soni: yaroqsiz/manfiy -> standart (fail-closed: NaN limitni «cheksiz» qilib qo'ymasin). 0 — ruxsat etilgan qiymat.
function cfgNum(v, def) { if (v === undefined || v === null || v === '') return def; const n = Number(v); return (Number.isFinite(n) && n >= 0) ? Math.floor(n) : def; }
// Fakturadagi qolgan qarz — admin.html renderFinance (debtAmt) bilan AYNAN bir xil.
function debtOf(i) {
  const st = String(i.status || '');
  if (st === 'canceled' || st === 'reversed' || st === 'paid') return 0;
  return Math.max(0, (Number(i.amount) || 0) - (Number(i.paidAmount) || 0));
}
// Eskiz xatosini admin uchun tushunarli qilish.
function humanEskizError(e) {
  const t = String(e || '');
  if (/модерац|moderat|шаблон|templat/i.test(t)) return 'Eskiz bu matnni rad etdi: SMS matni Eskiz kabinetida SHABLON sifatida tasdiqlanmagan. config.json → sms.templates.remind (yoki debt) dagi matnni Eskiz «Shablonlar» bo‘limiga yuborib tasdiqlating.';
  if (/баланс|balance|средств|insufficient|limit/i.test(t)) return 'Eskiz: balans yoki limit yetarli emas — Eskiz hisobini tekshiring.';
  if (/bad_phone/.test(t)) return 'Telefon raqam noto‘g‘ri.';
  return 'SMS yuborilmadi (Eskiz): ' + t.slice(0, 200);
}
const UNCERTAIN = 'Bugun eslatma yuborish boshlangan, lekin natijasi noaniq (SMS ketgan bo‘lishi mumkin) — ota-onaga ikki marta SMS ketmasligi uchun bugun qayta yuborilmaydi.';


function makeSmsRemind(deps) {
  const { sb, eskiz, verifyJwt } = deps;
  const S = deps.smsCfg || {};
  // Rollar: ro'yxat berilgan bo'lsa — AYNAN o'sha ([] = hech kim); berilmagan bo'lsa — direktor + moliya menejeri.
  const ROLES = new Set(Array.isArray(S.remindRoles) ? S.remindRoles.map(String) : ['director', 'finance_mgr']);
  const MAX_HOUR = cfgNum(S.remindMaxPerHour, 60);      // bitta foydalanuvchi soatiga (0 = o'chirilgan)
  const MAX_DAY = cfgNum(S.remindMaxPerDay, 500);       // butun maktab kuniga — xarajat chegarasi (0 = o'chirilgan)
  const MAX_TRIES = Math.max(1, cfgNum(S.remindMaxRetries, 3));   // Eskiz ANIQ rad etgandan keyin urinishlar (bir kunda)
  const TPL = (S.templates && (S.templates.remind || S.templates.debt)) || DEF_DEBT;
  const now = deps.now || (() => Date.now());
  const DRY = !eskiz;

  return async function smsRemind(body) {
    body = body || {};
    // 1) Kim? — JWT + FAOL rol (serverda).
    const uid = await verifyJwt(body.jwt);
    if (!uid) return { ok: false, error: 'Seans tugagan — qaytadan kiring.' };
    const { data: urows, error: uErr } = await sb.from('users').select('id,role,status').eq('id', uid).limit(1);
    if (uErr) return { ok: false, error: 'Server xatosi (foydalanuvchi). Keyinroq urinib ko‘ring.' };
    const u = urows && urows[0];
    const ust = String((u && u.status) || '');
    if (!u || !ROLES.has(String(u.role || '')) || !(ust === '' || ust === 'active')) return { ok: false, error: 'Ruxsat yo‘q: SMS eslatmani faqat direktor / moliya menejeri yuboradi.' };

    // 2) Qaysi o'quvchi? Kalit BIRDAN ORTIQ o'quvchiga to'g'ri kelsa (bir bolaning hujjat id'si boshqasining
    //    studentId'si / studentId takrori) — RAD (ota-ona kabineti qoidasi bilan bir xil).
    const sid = String(body.studentId || '').trim();
    if (!sid || sid.length > 80 || /[\u0000-\u001f]/.test(sid)) return { ok: false, error: 'O‘quvchi ko‘rsatilmagan.' };
    const cols = 'id,studentId,name';
    const r1 = await sb.from('students').select(cols).eq('studentId', sid);
    const r2 = await sb.from('students').select(cols).eq('id', sid);
    if (r1.error || r2.error) return { ok: false, error: 'Server xatosi (o‘quvchi). Keyinroq urinib ko‘ring.' };
    const cand = new Map();
    [...(r1.data || []), ...(r2.data || [])].forEach(r => cand.set(r.id, r));
    if (cand.size > 1) return { ok: false, error: 'Bu ID bir nechta o‘quvchiga to‘g‘ri keldi — «O‘quvchilar» → «⚠️ Sifat»dagi ID to‘qnashuvini hal qiling (SMS boshqa oilaga ketmasin).' };
    const st = cand.size === 1 ? [...cand.values()][0] : null;
    if (!st) return { ok: false, error: 'O‘quvchi topilmadi (o‘chirilgan yoki ID o‘zgargan).' };
    const code = String(st.studentId || '').trim();
    const canon = code || st.id;                                    // kanonik kalit (billing bilan bir xil)
    // Fakturalar kanonik kalit bilan; eski fakturalar hujjat id bilan bo'lishi mumkin — lekin hujjat id BOSHQA bolaning
    //   studentId'si bo'lsa, u kalitdagi fakturalar O'SHA bolaniki (qo'shilmaydi: begona qarz boshqa oilaga SMS'da ketmasin).
    const keys = [canon];
    if (st.id !== canon) {
      const o = await sb.from('students').select('id').eq('studentId', st.id).limit(1);
      if (o.error) return { ok: false, error: 'Server xatosi (o‘quvchi). Keyinroq urinib ko‘ring.' };
      if (!(o.data || []).length) keys.push(st.id);
    }

    // 3) Telefon — maxfiy jadval (hujjat id = students.id). Faqat shu bola uchun aniq bo'lsa studentId taxallusi.
    const pcols = 'id,parentPhone,parentPhone2';
    const p1 = await sb.from('student_private').select(pcols).eq('id', st.id).limit(1);
    if (p1.error) return { ok: false, error: 'Server xatosi (telefon). Keyinroq urinib ko‘ring.' };
    let pv = p1.data && p1.data[0];
    if (!pv && code && code !== st.id) {
      const other = await sb.from('students').select('id').eq('id', code).limit(1);   // boshqa o'quvchining hujjati emasmi?
      if (!other.error && !(other.data || []).length) {
        const p2 = await sb.from('student_private').select(pcols).eq('id', code).limit(1);
        if (!p2.error) pv = p2.data && p2.data[0];
      }
    }
    const phone = (pv && (L.normPhone(pv.parentPhone) || L.normPhone(pv.parentPhone2))) || null;

    // 4) Qarz — serverda (o'quvchining BARCHA kalitlaridagi fakturalar).
    const curMonth = tashkentDay(now()).slice(0, 7);
    const ir = await sb.from('invoices').select('id,month,amount,paidAmount,status,studentName').in('studentId', keys);
    if (ir.error) return { ok: false, error: 'Server xatosi (fakturalar). Keyinroq urinib ko‘ring.' };
    const debts = (ir.data || []).filter(i => i.month && String(i.month) <= curMonth)
      .map(i => ({ id: i.id, month: String(i.month), due: debtOf(i), nm: i.studentName }))
      .filter(x => x.due > 0).sort((a, b) => (a.month < b.month ? -1 : a.month > b.month ? 1 : 0));
    const due = debts.reduce((s, x) => s + x.due, 0);
    const months = [...new Set(debts.map(x => x.month))];
    const name = smsName(st.name || (debts[0] && debts[0].nm) || canon);
    // Faqat ASCII (GSM-7): tire/boshqa belgi butun SMS'ni UCS-2 ga o'tkazib, qismlar sonini (narxini) oshiradi.
    const monthTxt = months.length > 4 ? `${months.slice(0, 3).map(fmtMonth).join(', ')} va yana ${months.length - 3} oy` : months.map(fmtMonth).join(', ');
    const message = fillTpl(TPL, { name, month: monthTxt, due: fmtSom(due), amount: fmtSom(due) });

    // 5) Bugungi holat (qo'lda + avtomatik).
    const day = tashkentDay(now());
    const logId = `remind__${canon}__${day}`;
    const ex = await sb.from('sms_log').select('id,status,attempts,error,createdAt').eq('id', logId).limit(1);
    if (ex.error) return { ok: false, error: 'Server xatosi (SMS jurnali). Keyinroq urinib ko‘ring.' };
    const prev = ex.data && ex.data[0];
    const dayStart = tashkentDayStartISO(day);
    const autoToday = (await countRows(sb.from('sms_log').select('id', { count: 'exact', head: true }).in('studentId', keys).eq('type', 'debt').eq('status', 'sent').gte('createdAt', dayStart))) || 0;
    const pretty = phone ? L.prettyPhone(phone) : '';
    // 6) Yuborish shartlari — ko'rib chiqishda ham AYNAN shular qaytariladi (admin bloklangan holatda tasdiq oynasini ko'rmaydi).
    let block = null;
    if (!(due > 0)) block = { code: 'nodebt', error: 'Bu o‘quvchida joriy oygacha qarz yo‘q — SMS yuborilmadi.' };
    else if (!phone) block = { code: 'nophone', error: 'Ota-ona telefoni kiritilmagan yoki noto‘g‘ri (o‘quvchi kartasi → «Ota-ona telefoni»).' };
    else if (prev && prev.status === 'sent') block = { code: 'sent', already: 'sent', error: 'Bugun bu o‘quvchining ota-onasiga eslatma allaqachon yuborilgan ✓' };
    else if (prev && prev.status !== 'failed') block = { code: 'uncertain', already: 'sending', error: UNCERTAIN };
    else if (prev && (Number(prev.attempts) || 0) >= MAX_TRIES) block = { code: 'retries', error: `Bugun ${MAX_TRIES} marta urinildi, SMS ketmadi: ${humanEskizError(prev.error)}` };
    else if (!MAX_HOUR || !MAX_DAY) block = { code: 'disabled', error: 'SMS eslatma serverda o‘chirilgan (limit 0).' };
    const info = { name, phone: pretty, due, months, message, dry: DRY,
      today: prev ? { status: String(prev.status || ''), at: prev.createdAt || null } : null, autoToday,
      blocked: block ? block.code : null, blockedMsg: block ? block.error : '' };

    if (body.preview) return Object.assign({ ok: true, preview: true }, info);

    if (block) return block.already ? { ok: false, already: block.already, error: block.error } : { ok: false, error: block.error };
    // Tasdiq bilan BOG'LASH: admin ko'rib tasdiqlagan matn va telefon (body.expect) hozirgisidan farq qilsa (oraliqda to'lov
    //   kelgan / telefon tahrirlangan) — yubormaymiz, qayta ko'rib chiqishni so'raymiz.
    if (body.expect && (String(body.expect.message || '') !== message || String(body.expect.phone || '') !== pretty)) {
      return Object.assign({ ok: false, changed: true, error: 'Ma’lumot o‘zgardi (qarz yoki telefon) — «Eslatma»ni qayta bosib, yangi matnni tasdiqlang.' }, info);
    }
    const hourAgo = new Date(now() - 3600e3).toISOString();
    const overLimit = async () => {
      const nHour = await countRows(sb.from('sms_log').select('id', { count: 'exact', head: true }).eq('type', 'remind').eq('sentBy', uid).gte('createdAt', hourAgo));
      if (nHour == null) return 'Server xatosi (limit). Keyinroq urinib ko‘ring.';
      if (nHour > MAX_HOUR) return `Soatiga ${MAX_HOUR} tadan ortiq eslatma yuborib bo‘lmaydi. Keyinroq urinib ko‘ring.`;
      const nDay = await countRows(sb.from('sms_log').select('id', { count: 'exact', head: true }).eq('type', 'remind').gte('createdAt', dayStart));
      if (nDay == null) return 'Server xatosi (limit). Keyinroq urinib ko‘ring.';
      if (nDay > MAX_DAY) return `Bugungi umumiy SMS eslatma chegarasi (${MAX_DAY}) tugadi.`;
      return null; };
    // Oldindan tekshiruv (yangi qator hali yo'q -> «+1» bilan): limit to'lgan bo'lsa claim ham qilinmaydi.
    if (!prev) {
      const nHour0 = await countRows(sb.from('sms_log').select('id', { count: 'exact', head: true }).eq('type', 'remind').eq('sentBy', uid).gte('createdAt', hourAgo));
      if (nHour0 == null) return { ok: false, error: 'Server xatosi (limit). Keyinroq urinib ko‘ring.' };
      if (nHour0 >= MAX_HOUR) return { ok: false, error: `Soatiga ${MAX_HOUR} tadan ortiq eslatma yuborib bo‘lmaydi. Keyinroq urinib ko‘ring.` };
      const nDay0 = await countRows(sb.from('sms_log').select('id', { count: 'exact', head: true }).eq('type', 'remind').gte('createdAt', dayStart));
      if (nDay0 == null) return { ok: false, error: 'Server xatosi (limit). Keyinroq urinib ko‘ring.' };
      if (nDay0 >= MAX_DAY) return { ok: false, error: `Bugungi umumiy SMS eslatma chegarasi (${MAX_DAY}) tugadi.` };
    }
    if (DRY) { console.log('[DRY remind]', redact(phone), '::', message); return Object.assign({ ok: true, dry: true }, info); }

    // 7) ATOMIK claim — parallel/takror bosishda faqat BITTA so'rov yuboradi.
    const rec = { studentId: canon, invoiceId: (debts[debts.length - 1] || {}).id || '', phone, type: 'remind', message,
      month: months[months.length - 1] || '', sentBy: uid, status: 'sending', providerId: '', error: '' };
    if (!prev) {
      const ins = await sb.from('sms_log').insert(Object.assign({ id: logId, attempts: 1 }, rec));
      if (ins.error) {
        if (String(ins.error.code || '') === '23505' || /duplicate|unique/i.test(String(ins.error.message || ''))) return { ok: false, already: 'sending', error: 'Bu eslatma hozirgina yuborilmoqda (takror bosildi).' };
        return { ok: false, error: 'Server xatosi (SMS jurnali yozilmadi).' };
      }
      // Limit claim'dan KEYIN qayta sanaladi (o'z qatori ham ichida): parallel so'rovlar oldindan tekshiruvdan birga
      //   o'tib ketgan bo'lsa ham, limitdan oshganlari o'z claim'ini o'chirib rad etiladi (SMS ketmaydi).
      const over = await overLimit();
      if (over) {
        const del = await sb.from('sms_log').delete().eq('id', logId).eq('status', 'sending');
        if (del.error) console.error('sms-remind claim delete fail', logId, (del.error.message || '').slice(0, 120));
        return { ok: false, error: over };
      }
    } else {
      // Qayta urinish ham limitga bo'ysunadi (bu qator — o'z vaqtida sanalgan; oyna ichida bo'lsa ham «>» bilan).
      const over = await overLimit();
      if (over) return { ok: false, error: over };
      const n0 = Number(prev.attempts) || 0;
      const up = await sb.from('sms_log').update(Object.assign({}, rec, { attempts: n0 + 1 })).eq('id', logId).eq('status', 'failed').eq('attempts', n0).select('id');
      if (up.error) return { ok: false, error: 'Server xatosi (SMS jurnali yozilmadi).' };
      if (!(up.data || []).length) return { ok: false, already: 'sending', error: 'Bu eslatma hozirgina yuborilmoqda (takror bosildi).' };
    }
    // Eskiz natijasi (payments/sms.cjs sendStatus): ok -> sent; Eskiz'ning o'zi 4xx JSON bilan rad etdi yoki kirish (login)/
    //   ulanish umuman bo'lmadi (ECONNREFUSED/DNS/TLS) -> failed (aniq ketmagan, qayta urinish mumkin); 5xx / JSON emas /
    //   SMS so'rovi paytida uzilish yoki timeout -> 'unknown' (SMS ketgan bo'lishi mumkin — bugun qayta yuborilmaydi).
    let r, thrown = null;
    try { r = await eskiz.send(phone, message); } catch (e) { thrown = e || new Error('eskiz'); r = { ok: false, error: (e && e.message) || String(e) }; }
    const status = sendStatus(r, thrown);           // sent | failed (aniq ketmagan) | unknown (5xx/JSON emas/uzilish — ketgan bo'lishi mumkin)
    const uncertain = status === 'unknown';
    const mk = await sb.from('sms_log').update({ status, providerId: String((r && r.id) || ''), error: r.ok ? '' : String(r.error || '').slice(0, 300) }).eq('id', logId);
    if (mk.error) console.error('sms-remind log update fail', logId, (mk.error.message || '').slice(0, 120));
    if (!r.ok) {
      console.error('sms-remind fail', redact(phone), status, String(r.error || '').slice(0, 200));
      return { ok: false, error: uncertain ? 'Eskiz javobi noaniq (aloqa uzildi yoki Eskiz serveri xatosi) — SMS ketgan-ketmagani noma’lum. Ikki marta ketmasligi uchun bugun qayta yuborilmaydi.' : humanEskizError(r.error) };
    }
    return { ok: true, sent: true, phone: pretty, due, months };
  };
}

module.exports = { makeSmsRemind, debtOf, smsName, humanEskizError, cfgNum, definitelyNotSent };
