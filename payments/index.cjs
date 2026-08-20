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
async function resolveInvoice(rawId, amountMatches){
  rawId = String(rawId||'').trim(); if(!rawId) return null;
  if(rawId.includes('__')) return await getInvoice(rawId);                 // 1) aniq invoice ID
  const parts = rawId.toUpperCase().split(/[\s*\/+#:.,;|]+/).filter(Boolean);
  let sid = null;
  if(parts.length >= 2){                                                   // 2) ID + kod (har ikki tartib)
    if(await codeMatches(parts[0], parts[1])) sid = parts[0];
    else if(await codeMatches(parts[1], parts[0])) sid = parts[1];
  } else if(parts.length === 1){                                          // 3) faqat kod
    sid = await studentIdByCode(parts[0]);
  }
  if(!sid) return null;
  const list = await unpaidInvoices(sid); if(!list.length) return null;
  if(amountMatches){ const hit = list.find(x=>amountMatches(x.amount)); if(hit) return hit; }
  return list[0];
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
  const inv = await resolveInvoice(p.merchant_trans_id, amt => amtEq(p.amount, amt));
  if(!inv) return clickErr(p, -5, 'Hisob-faktura topilmadi', false);
  if(inv.status === 'paid') return clickErr(p, -4, 'Allaqachon to\'langan', false);
  if(!amtEq(p.amount, inv.amount)) return clickErr(p, -2, 'Summa mos emas', false);
  const prepareId = String(Date.now());
  await db.collection('payments').doc('click_' + p.click_trans_id).set({
    provider:'click', click_trans_id:String(p.click_trans_id), merchant_trans_id:String(p.merchant_trans_id),
    invoiceId:String(inv.id), merchant_prepare_id:prepareId, amount:Number(p.amount), status:'prepared', createdAt: FieldValue.serverTimestamp()
  });
  return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_prepare_id:prepareId, error:0, error_note:'Success' };
}
async function handleComplete(p){
  if(!clickReady(p)) return clickErr(p, -1, 'SIGN CHECK FAILED', true);
  if(clickSign(p, true) !== String(p.sign_string||'').toLowerCase()) return clickErr(p, -1, 'SIGN CHECK FAILED', true);
  const payRef = db.collection('payments').doc('click_' + p.click_trans_id);
  const paySnap = await payRef.get(); const pay = paySnap.exists ? paySnap.data() : null;
  if(!pay || String(pay.merchant_prepare_id) !== String(p.merchant_prepare_id)) return clickErr(p, -6, 'Tranzaksiya topilmadi', true);
  // Prepare bosqichida hal qilingan HAQIQIY invoice ID (merchant_trans_id kod bo'lishi mumkin).
  const invId = String(pay.invoiceId || p.merchant_trans_id);
  const inv = await getInvoice(invId);
  if(!inv) return clickErr(p, -5, 'Hisob-faktura topilmadi', true);
  if(Number(p.error) < 0){ await payRef.set({ status:'canceled' }, { merge:true }); return clickErr(p, -9, 'Transaction cancelled', true); }
  if(!amtEq(p.amount, inv.amount)) return clickErr(p, -2, 'Summa mos emas', true);
  if(inv.status === 'paid') return clickErr(p, -4, 'Allaqachon to\'langan', true);
  const confirmId = String(Date.now());
  await db.collection('invoices').doc(invId).set({
    status:'paid', provider:'click', providerTrans:String(p.click_trans_id), paidAt: FieldValue.serverTimestamp()
  }, { merge:true });
  await payRef.set({ status:'paid', merchant_confirm_id:confirmId }, { merge:true });
  return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_confirm_id:confirmId, error:0, error_note:'Success' };
}

// Hisob-fakturani «paid» qiladi (Uzum/Click confirm bosqichida chaqiriladi).
async function markInvoicePaid(invoiceId, provider, trans){
  const ref = db.collection('invoices').doc(String(invoiceId||''));
  const s = await ref.get(); if(!s.exists) return { ok:false, reason:'not-found' };
  if(s.data().status === 'paid') return { ok:true, already:true };
  // Qaytarilgan/bekor qilingan hisob-fakturani qayta «paid» qilmaymiz (refund tirilmasin).
  if(s.data().status === 'reversed' || s.data().status === 'canceled') return { ok:false, reason:'terminal' };
  await ref.set({ status:'paid', provider, providerTrans:String(trans||''), paidAt: FieldValue.serverTimestamp() }, { merge:true });
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
  const inv = await resolveInvoice(raw, b.amount!=null ? (amt=>uzAmountOK(b.amount, amt)) : null); if(!inv) return uzFail(UZ.NOT_FOUND);
  if(inv.status === 'paid') return uzFail(UZ.ALREADY_PAID);
  if(b.amount != null && !uzAmountOK(b.amount, inv.amount)) return uzFail(UZ.CHECK_ERROR);
  return { serviceId: UZUM.serviceId, timestamp: uzTs(), status:'OK',
           data: { account: { invoice: inv.id, month: inv.month || '', student: inv.studentName || '' } } };
}
async function uzCreate(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const raw = uzInvoiceId(b.params); if(!raw) return uzFail(UZ.NOT_ENOUGH_PARAMS);
  const inv = await resolveInvoice(raw, amt=>uzAmountOK(b.amount, amt)); if(!inv) return uzFail(UZ.NOT_FOUND);
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
      { status:'reversed', reversedAt: FieldValue.serverTimestamp() }, { merge:true });
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
