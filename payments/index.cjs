/**
 * Iqror — TO'LOV serveri (Uzum Merchant API + Click → invoices)
 * -------------------------------------------------------------------
 * Ota-ona kabinetdagi hisob-fakturani Uzum (yoki Click) orqali to'laganda,
 * to'lov tizimi shu serverga chaqiruv yuboradi. Server so'rovni tekshirib,
 * `invoices/<id>` ni «paid» qiladi. Maxfiy kalitlar faqat shu serverda.
 *
 * ⚠️ PUL bilan ishlaydi — ishonchli, HTTPS orqasidagi serverda ishlating.
 * Supabase service_role (yoki Firebase Admin) orqali yozadi (RLS chetlab).
 *
 * UZUM Merchant API (server-to-server) — Uzum 5 ta endpoint chaqiradi
 * (har birida Basic auth: login:password kabinetdan):
 *   POST /uzum/check     — hisob-faktura bor/to'lanmaganini tekshiradi
 *   POST /uzum/create    — tranzaksiya yaratadi (rezerv)
 *   POST /uzum/confirm   — to'lov tasdiqlandi → invoice «paid» ★
 *   POST /uzum/reverse   — qaytarish (refund) → invoice «reversed»
 *   POST /uzum/status    — tranzaksiya holatini qaytaradi
 *   Javob status: OK / CREATED / CONFIRMED / REVERSED / FAILED(errorCode).
 *   Hujjat: developer.uzumbank.uz/merchant
 *
 * CLICK SHOP-API (Merchant API) — TO'LIQ, saqlab qolingan (ixtiyoriy):
 *   POST /click/prepare (action=0) · POST /click/complete (action=1)
 *   imzo = md5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id
 *              [+ merchant_prepare_id]  + amount + action + sign_time)
 *
 * Ishga tushirish:
 *   npm install
 *   cp config.example.json config.json   # to'ldiring
 *   node index.cjs                        # :8790 da tinglaydi
 *
 * Batafsil: README.md
 */
const fs = require('fs');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
// Data qatlami: CFG.backend='supabase' -> Supabase service_role, aks holda Firebase (rollback).
const { db, FieldValue } = require('../server/backend.js')({ ...CFG, __dir: __dirname });
const CLICK = CFG.click || {};        // { serviceId, secretKey, merchantId }
const UZUM  = CFG.uzum  || {};        // { serviceId, login, password, accountField?, amountUnit? }

const md5 = s => crypto.createHash('md5').update(s).digest('hex');
const amtEq = (a, b) => Math.abs(Number(a) - Number(b)) < 0.5;
const getInvoice = async id => { const s = await db.collection('invoices').doc(String(id||'')).get(); return s.exists ? s.data() : null; };

/* ---------- To'lov identifikatorini invoice'ga aylantirish (moslashuvchan) ----------
 * merchant_trans_id / Uzum account quyidagilardan biri bo'lishi mumkin:
 *   1) "{sid}__{YYYY-MM}"  — ANIQ invoice ID (kabinet «Click» tugmasi) — o'zgarmagan
 *   2) "IQ-0042 KOD"       — o'quvchi ID + maxfiy kod (Click ilova / QR / kassa)
 *   3) "KOD"               — faqat maxfiy kod (kod noyob bo'lsa)
 * Kod = 2b student_codes (admin paneldagi «Kod» ustuni). Server service_role bilan
 * o'qiydi (RLS chetlab). Topilса o'quvchining TO'LANMAGAN hisob-fakturasi qaytadi
 * (mos summali afzal, aks holda eng eski). */
async function studentIdByCode(code){
  code = String(code||'').trim().toUpperCase(); if(!code) return null;
  try{ const snap = await db.collection('student_codes').where('code','==',code).get();
       const docs = snap.docs || []; return docs.length === 1 ? String(docs[0].id) : null; }
  catch(e){ return null; }
}
async function codeMatches(sid, code){
  code = String(code||'').trim().toUpperCase(); if(!sid || !code) return false;
  try{ const s = await db.collection('student_codes').doc(String(sid)).get();
       return s.exists && String((s.data()||{}).code||'').toUpperCase() === code; }
  catch(e){ return false; }
}
async function unpaidInvoices(sid){
  try{ const snap = await db.collection('invoices').where('studentId','==',String(sid)).get();
       return (snap.docs || []).map(d=>d.data())
         .filter(x=>x && x.status!=='paid' && x.status!=='canceled' && x.status!=='reversed')
         .sort((a,b)=>String(a.month||a.id||'').localeCompare(String(b.month||b.id||''))); }
  catch(e){ return []; }
}
// Telefonni normallashtiradi: faqat raqamlar, oxirgi 9 ta (+998/bo'sh joy farqi muhim emas).
const normPhone = p => String(p||'').replace(/\D/g,'').slice(-9);
const normTxt = s => String(s||'').trim().toLowerCase().replace(/\s+/g,' ');
const normClass = s => String(s||'').trim().toLowerCase().replace(/\s+/g,'');

// Telefon (+ ism/sinf bilan aniqlashtirish) bo'yicha o'quvchini topadi.
// Qaytadi: { status:'ok', studentId } | 'notfound' | 'ambiguous' | 'nophone'.
async function findStudentByPhone(phone, name, klass){
  const ph = normPhone(phone); if(ph.length < 7) return { status:'nophone' };
  let privs;
  try{ privs = (await db.collection('student_private').get()).docs.map(d=>({ id:d.id, ...(d.data()||{}) })); }
  catch(e){ return { status:'error' }; }
  const ids = privs.filter(x => normPhone(x.parentPhone) === ph || normPhone(x.parentPhone2) === ph).map(x => x.id);
  if(!ids.length) return { status:'notfound' };
  if(ids.length === 1) return { status:'ok', studentId: ids[0] };
  // Aka-uka (bir telefon) — ism/sinf bilan ajratamiz.
  let studs = [];
  try{ studs = (await db.collection('students').get()).docs.map(d=>({ id:d.id, ...(d.data()||{}) })); }catch(e){}
  const cand = studs.filter(s => ids.includes(s.id));
  const nm = normTxt(name), kl = normClass(klass);
  let hit = nm ? cand.filter(s => normTxt(s.name) === nm) : [];
  if(hit.length !== 1 && kl){ const byCls = cand.filter(s => normClass(String(s.grade||'') + (s.classLetter || s.track || '')) === kl); if(byCls.length === 1) hit = byCls; }
  if(hit.length === 1) return { status:'ok', studentId: hit[0].id };
  return { status:'ambiguous', candidates: ids };
}

// merchant_trans_id (+ Click paramlari) dan o'quvchini aniqlaydi.
// Qaytadi: { sid, via } — via: 'code' | 'phone' | (topilmasa) 'notfound'/'ambiguous'/'nophone'.
async function attributeStudent(mti, params){
  mti = String(mti||'').trim();
  const parts = mti.toUpperCase().split(/[\s*\/+#:.,;|]+/).filter(Boolean);
  if(parts.length >= 2){                                     // ID + kod (har ikki tartib)
    if(await codeMatches(parts[0], parts[1])) return { sid: parts[0], via:'code' };
    if(await codeMatches(parts[1], parts[0])) return { sid: parts[1], via:'code' };
  } else if(parts.length === 1 && /^[A-Z0-9]{5,8}$/.test(parts[0])){   // faqat kod (kod-shaklli bo'lsa)
    const s = await studentIdByCode(parts[0]); if(s) return { sid: s, via:'code' };
  }
  const ph = (params && (params.param3 || params.phone)) || '';   // Click: param3 = telefon
  const r = await findStudentByPhone(ph, mti, params && params.param2);
  if(r.status === 'ok') return { sid: r.studentId, via:'phone' };
  return { sid: null, via: r.status };
}

// To'lov summasini o'quvchi BALANSIGA qo'llaydi (waterfall: eng eski invoice avval).
// Kam -> qisman (qarzdorlik qoladi); to'liq -> paid; ortiqcha -> student_credit (avans).
// Mavjud kredit avval ishlatiladi. IDEMPOTENT: transId bo'yicha ikki marta hisoblanmaydi.
async function applyPaymentToStudent(studentId, amount, transId){
  studentId = String(studentId||''); amount = Number(amount)||0;
  const guardRef = db.collection('applied_payments').doc(String(transId||''));
  // ATOMIK band qilish — bir vaqtda kelgan takroriy callback ikki marta hisoblamasin (create id konfliktida xato beradi).
  try{ await guardRef.create({ studentId, amount, createdAt: FieldValue.serverTimestamp() }); }
  catch(e){ try{ const g = await guardRef.get(); return (g.data()||{}).result || { applied:[], leftover:0, dup:true }; }catch(_){ return { dup:true }; } }
  try{
  let credit = 0;
  try{ const c = await db.collection('student_credit').doc(studentId).get(); if(c.exists) credit = Number((c.data()||{}).credit)||0; }catch(e){}
  let available = amount + credit;
  const applied = [];
  const list = await unpaidInvoices(studentId);              // eng eski avval, pending/partial
  for(const inv of list){
    if(available <= 0) break;
    const paidSoFar = Number(inv.paidAmount)||0;
    const remaining = Number(inv.amount) - paidSoFar;
    if(remaining <= 0) continue;
    const pay = Math.min(available, remaining);
    const newPaid = paidSoFar + pay;
    const paidFull = newPaid >= Number(inv.amount) - 0.5;
    await db.collection('invoices').doc(String(inv.id)).set(Object.assign(
      { paidAmount: newPaid, status: paidFull ? 'paid' : 'partial', provider: 'click' },
      paidFull ? { providerTrans: String(transId||''), paidAt: FieldValue.serverTimestamp() } : {}
    ), { merge:true });
    applied.push({ invoiceId: inv.id, amount: pay, status: paidFull ? 'paid' : 'partial' });
    available -= pay;
  }
  await db.collection('student_credit').doc(studentId).set(
    { studentId, credit: available, updatedAt: FieldValue.serverTimestamp() }, { merge:true });
  const result = { applied, leftover: available, usedCredit: credit };
  try{ await guardRef.set({ studentId, amount, result, createdAt: FieldValue.serverTimestamp() }); }catch(e){}
  return result;
  }catch(e){ try{ await guardRef.delete(); }catch(_){}   // mutatsiya xatosi -> band qilishni bo'shatamiz (qayta urinish mumkin)
    throw e; }
}

// Summani BITTA aniq invoice balansiga qo'llaydi (kabinet «Click» tugmasi / precise).
// paidAmount += amount; to'lsa -> paid, kam -> partial, ortiqcha -> student_credit. IDEMPOTENT.
async function applyToInvoice(invoiceId, amount, transId){
  invoiceId = String(invoiceId||''); amount = Number(amount)||0;
  const guardRef = db.collection('applied_payments').doc(String(transId||''));
  // ATOMIK band qilish (idempotentlik) — takroriy/bir vaqtli callback ikki marta hisoblamasin.
  try{ await guardRef.create({ amount, createdAt: FieldValue.serverTimestamp() }); }
  catch(e){ try{ const g = await guardRef.get(); return (g.data()||{}).result || { dup:true }; }catch(_){ return { dup:true }; } }
  const inv = await getInvoice(invoiceId); if(!inv){ try{ await guardRef.delete(); }catch(_){ } return { error:'notfound' }; }
  try{
  const paidSoFar = Number(inv.paidAmount)||0;
  const newPaid = paidSoFar + amount;
  const paidFull = newPaid >= Number(inv.amount) - 0.5;
  const overflow = Math.max(0, newPaid - Number(inv.amount));
  await db.collection('invoices').doc(invoiceId).set(Object.assign(
    { paidAmount: paidFull ? Number(inv.amount) : newPaid, status: paidFull ? 'paid' : 'partial', provider:'click' },
    paidFull ? { providerTrans: String(transId||''), paidAt: FieldValue.serverTimestamp() } : {}
  ), { merge:true });
  if(overflow > 0 && inv.studentId){
    let cr = 0; try{ const c = await db.collection('student_credit').doc(String(inv.studentId)).get(); if(c.exists) cr = Number((c.data()||{}).credit)||0; }catch(e){}
    await db.collection('student_credit').doc(String(inv.studentId)).set({ studentId:String(inv.studentId), credit: cr + overflow, updatedAt: FieldValue.serverTimestamp() }, { merge:true });
  }
  const result = { invoiceId, applied: amount, status: paidFull ? 'paid' : 'partial', overflow, studentId: inv.studentId||'' };
  try{ await guardRef.set({ studentId: String(inv.studentId||''), amount, result, createdAt: FieldValue.serverTimestamp() }); }catch(e){}
  return result;
  }catch(e){ try{ await guardRef.delete(); }catch(_){}   // mutatsiya xatosi -> band qilishni bo'shatamiz
    throw e; }
}

// Uzum uchun: account = aniq invoice ID ({sid}__{oy}) yoki kod -> to'lanmagan invoice (eng eski).
async function resolveInvoiceByCode(rawId){
  rawId = String(rawId||'').trim(); if(!rawId) return null;
  if(rawId.includes('__')) return await getInvoice(rawId);
  const at = await attributeStudent(rawId, {});          // kod-shaklli bo'lsa -> studentId
  if(!at.sid) return null;
  const list = await unpaidInvoices(at.sid);
  return list[0] || null;
}

/* ---------- CLICK ---------- */
function clickSign(p, isComplete){
  const parts = [p.click_trans_id, p.service_id, CLICK.secretKey, p.merchant_trans_id];
  if(isComplete) parts.push(p.merchant_prepare_id);
  parts.push(p.amount, p.action, p.sign_time);
  return md5(parts.join(''));
}
const clickErr = (p, code, note, isComplete) => Object.assign(
  { click_trans_id: p.click_trans_id, merchant_trans_id: p.merchant_trans_id, error: code, error_note: note },
  isComplete ? { merchant_confirm_id: 0 } : { merchant_prepare_id: 0 });

// XAVFSIZLIK: Click faqat secretKey sozlangan VA service_id mos bo'lsagina ishlaydi.
// Aks holda (secret bo'sh/placeholder) imzoni soxtalashtirib istalgan hisob-fakturani
// «to'landi» qilib bo'lardi. Fail-closed — sozlanmagan bo'lsa rad etiladi.
const clickReady = p => !!CLICK.secretKey && (!CLICK.serviceId || String(p.service_id) === String(CLICK.serviceId));

async function handlePrepare(p){
  if(!clickReady(p)) return clickErr(p, -1, 'SIGN CHECK FAILED', false);
  if(CFG.debugClick) console.error('[CLICK-DEBUG]', JSON.stringify({ ct:p.click_trans_id, sid:p.service_id, mti:p.merchant_trans_id, amt:p.amount, act:p.action, st:p.sign_time, recv:String(p.sign_string||'').toLowerCase(), ours:clickSign(p,false), secLen:(CLICK.secretKey||'').length }));
  if(clickSign(p, false) !== String(p.sign_string||'').toLowerCase()) return clickErr(p, -1, 'SIGN CHECK FAILED', false);
  const amount = Number(p.amount);
  if(!(amount > 0)) return clickErr(p, -2, 'Summa mos emas', false);
  const mti = String(p.merchant_trans_id || '');
  const prepareId = String(Date.now());
  const payRef = db.collection('payments').doc('click_' + p.click_trans_id);

  // A) ANIQ invoice ID (kabinet «Click» tugmasi) -> QAT'IY: summa aynan mos kelishi shart.
  if(mti.includes('__')){
    const inv = await getInvoice(mti);
    if(!inv) return clickErr(p, -5, 'Hisob-faktura topilmadi', false);
    if(inv.status === 'paid') return clickErr(p, -4, 'Allaqachon to\'langan', false);
    // Balans modeli: summa aynan mos kelishi shart emas — qolganiga (partial) yoki to'liq tushadi.
    await payRef.set({ provider:'click', click_trans_id:String(p.click_trans_id), merchant_trans_id:mti,
      invoiceId:String(inv.id), studentId:String(inv.studentId||''), merchant_prepare_id:prepareId,
      amount, status:'prepared', matched:true, raw:{ mode:'precise' }, createdAt: FieldValue.serverTimestamp() });
    return { click_trans_id:p.click_trans_id, merchant_trans_id:mti, merchant_prepare_id:prepareId, error:0, error_note:'Success' };
  }

  // B) ERKIN to'lov (ism/telefon + ixtiyoriy summa) -> BALANS modeli. Har doim qabul qilinadi
  //    (pul keladi -> yoziladi; biriktirilmasa admin biriktiradi). Attribution: kod yoki telefon.
  const at = await attributeStudent(mti, p);
  await payRef.set({ provider:'click', click_trans_id:String(p.click_trans_id), merchant_trans_id:mti,
    studentId: at.sid || '', matched: !!at.sid, merchant_prepare_id:prepareId, amount, status:'prepared',
    payerName: mti, payerPhone: String(p.param3||''), payerClass: String(p.param2||''),
    raw:{ mode:'freeform', via: at.via }, createdAt: FieldValue.serverTimestamp() });
  return { click_trans_id:p.click_trans_id, merchant_trans_id:mti, merchant_prepare_id:prepareId, error:0, error_note:'Success' };
}
async function handleComplete(p){
  if(!clickReady(p)) return clickErr(p, -1, 'SIGN CHECK FAILED', true);
  if(clickSign(p, true) !== String(p.sign_string||'').toLowerCase()) return clickErr(p, -1, 'SIGN CHECK FAILED', true);
  const payRef = db.collection('payments').doc('click_' + p.click_trans_id);
  const paySnap = await payRef.get(); const pay = paySnap.exists ? paySnap.data() : null;
  if(!pay || String(pay.merchant_prepare_id) !== String(p.merchant_prepare_id)) return clickErr(p, -6, 'Tranzaksiya topilmadi', true);
  if(Number(p.error) < 0){ await payRef.set({ status:'canceled' }, { merge:true }); return clickErr(p, -9, 'Transaction cancelled', true); }
  const confirmId = String(Date.now());
  // Idempotentlik: allaqachon yakunlangan bo'lsa qayta hisoblamaymiz.
  if(pay.status === 'paid' || pay.status === 'applied' || pay.status === 'unmatched')
    return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_confirm_id:String(pay.merchant_confirm_id||confirmId), error:0, error_note:'Success' };
  const mode = (pay.raw && pay.raw.mode) || 'precise';

  if(mode === 'precise'){
    const inv = await getInvoice(String(pay.invoiceId||''));
    if(!inv) return clickErr(p, -5, 'Hisob-faktura topilmadi', true);
    if(inv.status === 'paid') return clickErr(p, -4, 'Allaqachon to\'langan', true);
    await applyToInvoice(String(pay.invoiceId), Number(p.amount)||0, p.click_trans_id);  // qolganiga/to'liq
    await payRef.set({ status:'paid', studentId:String(inv.studentId||''), merchant_confirm_id:confirmId }, { merge:true });
  } else {
    // ERKIN: balans modeli. Biriktirilgan -> qo'llanadi (qisman/to'liq/avans); aks holda -> biriktirilmagan.
    const amount = Number(pay.amount) || Number(p.amount) || 0;
    let result = { applied:[], leftover:amount };
    if(pay.matched && pay.studentId) result = await applyPaymentToStudent(pay.studentId, amount, p.click_trans_id);
    await payRef.set({ status: (pay.matched && pay.studentId) ? 'applied' : 'unmatched', amount,
      raw: Object.assign({}, pay.raw||{}, { allocation: result.applied, credit: result.leftover }),
      merchant_confirm_id:confirmId }, { merge:true });
  }
  return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_confirm_id:confirmId, error:0, error_note:'Success' };
}

// Hisob-fakturani «paid» qiladi (Uzum/Click confirm bosqichida chaqiriladi).
async function markInvoicePaid(invoiceId, provider, trans){
  const ref = db.collection('invoices').doc(String(invoiceId||''));
  const s = await ref.get(); if(!s.exists) return { ok:false, reason:'not-found' };
  if(s.data().status === 'paid') return { ok:true, already:true };
  // Qaytarilgan/bekor qilingan hisob-fakturani qayta «paid» qilmaymiz (refund tirilmasin).
  if(s.data().status === 'reversed' || s.data().status === 'canceled') return { ok:false, reason:'terminal' };
  // Balans modeli: to'liq to'langan -> paidAmount = amount (qarzdorlik/yig'ildi to'g'ri chiqsin).
  await ref.set({ status:'paid', paidAmount:Number(s.data().amount)||0, provider, providerTrans:String(trans||''), paidAt: FieldValue.serverTimestamp() }, { merge:true });
  return { ok:true };
}

/* ---------- UZUM MERCHANT API ---------- */
// Uzum bizning serverga 5 chaqiruv yuboradi (Basic auth): check → create →
// confirm (→ reverse / status). To'lov TASDIQLANGANDA (confirm) invoice «paid».
// Xato kodlari (Uzum Merchant API standarti):
const UZ = { AUTH:10001, PARSE:10002, UNKNOWN_OP:10003, NOT_ENOUGH_PARAMS:10005,
             INVALID_SERVICE:10006, ALREADY_PAID:10007, NOT_FOUND:10008, CANCELLED:10009, CHECK_ERROR:99999 };
const uzTs   = () => Date.now();
const uzFail = code => ({ serviceId: UZUM.serviceId, timestamp: uzTs(), status:'FAILED', errorCode: code });

// Basic auth: Authorization: Basic base64(login:password) — kabinetdagi kalitlar.
function uzumAuthOK(headers){
  const h = String((headers||{}).authorization || '');
  if(!/^Basic\s+/i.test(h)) return false;
  let dec=''; try{ dec = Buffer.from(h.replace(/^Basic\s+/i,''), 'base64').toString('utf8'); }catch(e){ return false; }
  const i = dec.indexOf(':'); if(i < 0) return false;
  return !!UZUM.login && !!UZUM.password && dec.slice(0,i) === UZUM.login && dec.slice(i+1) === UZUM.password;
}
// Hisob-faktura id sini Uzum `params` ichidan oladi (kabinetda belgilangan maydon).
function uzInvoiceId(params){
  if(!params || typeof params !== 'object') return null;
  const keys = [UZUM.accountField, 'invoice', 'invoiceId', 'order', 'orderId', 'account'].filter(Boolean);
  for(const k of keys){ if(params[k] != null && params[k] !== '') return String(params[k]); }
  const vals = Object.values(params); return vals.length ? String(vals[0]) : null;
}
// Uzum summasi (default: tiyin = so'm×100) hisob-faktura summasiga mos keladimi.
function uzAmountOK(bodyAmount, invAmount){
  const a = Number(bodyAmount);
  return UZUM.amountUnit === 'som' ? amtEq(a, invAmount) : amtEq(a, Number(invAmount) * 100);
}
const uzPayRef = transId => db.collection('payments').doc('uzum_' + String(transId));

async function uzCheck(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const raw = uzInvoiceId(b.params); if(!raw) return uzFail(UZ.NOT_ENOUGH_PARAMS);
  const inv = await resolveInvoiceByCode(raw); if(!inv) return uzFail(UZ.NOT_FOUND);
  if(inv.status === 'paid') return uzFail(UZ.ALREADY_PAID);
  if(b.amount != null && !uzAmountOK(b.amount, inv.amount)) return uzFail(UZ.CHECK_ERROR);
  return { serviceId: UZUM.serviceId, timestamp: uzTs(), status:'OK',
           data: { account: { invoice: inv.id, month: inv.month || '', student: inv.studentName || '' } } };
}
async function uzCreate(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const raw = uzInvoiceId(b.params); if(!raw) return uzFail(UZ.NOT_ENOUGH_PARAMS);
  const inv = await resolveInvoiceByCode(raw); if(!inv) return uzFail(UZ.NOT_FOUND);
  if(inv.status === 'paid') return uzFail(UZ.ALREADY_PAID);
  if(!uzAmountOK(b.amount, inv.amount)) return uzFail(UZ.CHECK_ERROR);
  // Idempotentlik: allaqachon yakuniy holatdagi tranzaksiyani 'created'ga qaytarmaymiz.
  const _ex = await uzPayRef(b.transId).get();
  if(_ex.exists && (_ex.data().status === 'confirmed' || _ex.data().status === 'reversed'))
    return { serviceId: UZUM.serviceId, timestamp: uzTs(), status:'CREATED', transTime: uzTs(), transId: b.transId, amount: b.amount };
  await uzPayRef(b.transId).set({ provider:'uzum', transId:String(b.transId), invoiceId:String(inv.id),
    studentId: inv.studentId || '', amount:Number(b.amount), status:'created',
    raw:b, createdAt: FieldValue.serverTimestamp() });
  return { serviceId: UZUM.serviceId, timestamp: uzTs(), status:'CREATED', transTime: uzTs(), transId: b.transId, amount: b.amount };
}
async function uzConfirm(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const snap = await uzPayRef(b.transId).get(); const pay = snap.exists ? snap.data() : null;
  if(!pay) return uzFail(UZ.NOT_FOUND);
  // Yakuniy holat (qaytarilgan/bekor) — confirm qayta to'lamaydi.
  if(pay.status === 'reversed' || pay.status === 'canceled') return uzFail(UZ.CANCELLED);
  if(pay.status !== 'confirmed'){
    await markInvoicePaid(pay.invoiceId, 'uzum', b.transId);
    await uzPayRef(b.transId).set({ status:'confirmed' }, { merge:true });
  }
  return { serviceId: UZUM.serviceId, transId: b.transId, status:'CONFIRMED', confirmTime: uzTs() };
}
async function uzReverse(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const snap = await uzPayRef(b.transId).get(); const pay = snap.exists ? snap.data() : null;
  if(!pay) return uzFail(UZ.NOT_FOUND);
  if(pay.status !== 'reversed'){
    await db.collection('invoices').doc(String(pay.invoiceId)).set(
      { status:'reversed', paidAmount:0, reversedAt: FieldValue.serverTimestamp() }, { merge:true });
    await uzPayRef(b.transId).set({ status:'reversed' }, { merge:true });
  }
  return { serviceId: UZUM.serviceId, transId: b.transId, status:'REVERSED', reverseTime: uzTs(), amount: pay.amount };
}
async function uzStatus(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const snap = await uzPayRef(b.transId).get(); const pay = snap.exists ? snap.data() : null;
  if(!pay) return uzFail(UZ.NOT_FOUND);
  const map = { created:'CREATED', confirmed:'CONFIRMED', reversed:'REVERSED' };
  return { serviceId: UZUM.serviceId, transId: b.transId, status: map[pay.status] || 'CREATED' };
}
async function handleUzum(op, body){
  switch(op){
    case 'check':   return uzCheck(body);
    case 'create':  return uzCreate(body);
    case 'confirm': return uzConfirm(body);
    case 'reverse': return uzReverse(body);
    case 'status':  return uzStatus(body);
    default:        return uzFail(UZ.UNKNOWN_OP);
  }
}

/* ---------- HTTP server ---------- */
function readBody(req){ return new Promise(res=>{ let d=''; req.on('data',c=>{ d+=c; if(d.length>1e6) req.destroy(); }); req.on('end',()=>res(d)); }); }
function parseBody(raw, ctype){
  if((ctype||'').includes('application/json')){ try{ return JSON.parse(raw||'{}'); }catch(e){ return {}; } }
  return Object.fromEntries(new URLSearchParams(raw||''));
}
if(require.main === module){
  const PORT = Number(CFG.port || 8790);
  const server = http.createServer(async (req, res) => {
    if(req.method === 'GET' && req.url === '/health'){ res.writeHead(200); return res.end('ok'); }
    if(req.method !== 'POST'){ res.writeHead(405); return res.end('POST kutiladi'); }
    const raw = await readBody(req);
    const body = parseBody(raw, req.headers['content-type']);
    // DIAGNOSTIKA: Click/Uzum aynan nima yuborishini ko'rish uchun (config.json: "debugPay": true).
    // Aniqlab bo'lgach o'chiring — loglar shaxsiy ma'lumot (ism/telefon/summa) o'z ichiga oladi.
    if(CFG.debugPay && /^\/(click|uzum)\//.test(req.url)) console.error('[PAY-BODY]', req.url, JSON.stringify(body));
    const send = obj => { res.writeHead(200, { 'Content-Type':'application/json' }); res.end(JSON.stringify(obj)); };
    try{
      if(req.url.startsWith('/click/prepare'))       send(await handlePrepare(body));
      else if(req.url.startsWith('/click/complete')) send(await handleComplete(body));
      else if(req.url.startsWith('/uzum/')){
        if(!uzumAuthOK(req.headers)){ res.writeHead(401, { 'Content-Type':'application/json' }); return res.end(JSON.stringify(uzFail(UZ.AUTH))); }
        const op = (req.url.split('?')[0].split('/')[2] || '');
        send(await handleUzum(op, body));
      }
      else { res.writeHead(404); res.end('not found'); }
    }catch(e){ console.error('Xatolik:', e.message); res.writeHead(500); res.end('xatolik'); }
  });
  server.listen(PORT, () => console.log(`Iqror to'lov serveri tinglayapti :${PORT}  (/uzum/{check,create,confirm,reverse,status}, /click/prepare, /click/complete)`));
}

module.exports = { handlePrepare, handleComplete, handleUzum, uzumAuthOK, markInvoicePaid, clickSign, md5 };
