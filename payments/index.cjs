/**
 * Iqror — TO'LOV serveri (Click + Uzum → invoices)
 * -------------------------------------------------------------------
 * Ota-ona kabinetdagi hisob-fakturani Click yoki Uzum orqali to'laganda,
 * to'lov tizimi shu serverga chaqiruv yuboradi. Server imzoni tekshirib,
 * `invoices/<id>` ni «paid» qiladi. Maxfiy kalit faqat shu serverda.
 *
 * ⚠️ PUL bilan ishlaydi — ishonchli, HTTPS orqasidagi serverda ishlating.
 * Firestore'ga Admin SDK orqali yozadi (qoidalarni chetlab o'tadi).
 *
 * Click SHOP-API (Merchant API) TO'LIQ va sinovdan o'tgan:
 *   POST /click/prepare   (action=0)
 *   POST /click/complete  (action=1)
 *   imzo = md5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id
 *              [+ merchant_prepare_id]  + amount + action + sign_time)
 *
 * Uzum — ASOS (scaffold): /uzum/webhook. Uzum merchant hisobingizdagi aniq
 *   maydon nomlari va imzo sxemasi bilan yakunlanadi (README ga qarang).
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
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
initializeApp({ credential: cert(require(path.resolve(__dirname, CFG.serviceAccount))) });
const db = getFirestore();
const CLICK = CFG.click || {};        // { serviceId, secretKey, merchantId }
const UZUM  = CFG.uzum  || {};        // { secret, ... }

const md5 = s => crypto.createHash('md5').update(s).digest('hex');
const amtEq = (a, b) => Math.abs(Number(a) - Number(b)) < 0.5;
const getInvoice = async id => { const s = await db.collection('invoices').doc(String(id||'')).get(); return s.exists ? s.data() : null; };

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

async function handlePrepare(p){
  if(clickSign(p, false) !== String(p.sign_string||'').toLowerCase()) return clickErr(p, -1, 'SIGN CHECK FAILED', false);
  const inv = await getInvoice(p.merchant_trans_id);
  if(!inv) return clickErr(p, -5, 'Hisob-faktura topilmadi', false);
  if(inv.status === 'paid') return clickErr(p, -4, 'Allaqachon to\'langan', false);
  if(!amtEq(p.amount, inv.amount)) return clickErr(p, -2, 'Summa mos emas', false);
  const prepareId = String(Date.now());
  await db.collection('payments').doc('click_' + p.click_trans_id).set({
    provider:'click', click_trans_id:String(p.click_trans_id), merchant_trans_id:String(p.merchant_trans_id),
    merchant_prepare_id:prepareId, amount:Number(p.amount), status:'prepared', createdAt: FieldValue.serverTimestamp()
  });
  return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_prepare_id:prepareId, error:0, error_note:'Success' };
}
async function handleComplete(p){
  if(clickSign(p, true) !== String(p.sign_string||'').toLowerCase()) return clickErr(p, -1, 'SIGN CHECK FAILED', true);
  const inv = await getInvoice(p.merchant_trans_id);
  if(!inv) return clickErr(p, -5, 'Hisob-faktura topilmadi', true);
  const payRef = db.collection('payments').doc('click_' + p.click_trans_id);
  const paySnap = await payRef.get(); const pay = paySnap.exists ? paySnap.data() : null;
  if(!pay || String(pay.merchant_prepare_id) !== String(p.merchant_prepare_id)) return clickErr(p, -6, 'Tranzaksiya topilmadi', true);
  if(Number(p.error) < 0){ await payRef.set({ status:'canceled' }, { merge:true }); return clickErr(p, -9, 'Transaction cancelled', true); }
  if(!amtEq(p.amount, inv.amount)) return clickErr(p, -2, 'Summa mos emas', true);
  if(inv.status === 'paid') return clickErr(p, -4, 'Allaqachon to\'langan', true);
  const confirmId = String(Date.now());
  await db.collection('invoices').doc(String(p.merchant_trans_id)).set({
    status:'paid', provider:'click', providerTrans:String(p.click_trans_id), paidAt: FieldValue.serverTimestamp()
  }, { merge:true });
  await payRef.set({ status:'paid', merchant_confirm_id:confirmId }, { merge:true });
  return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_confirm_id:confirmId, error:0, error_note:'Success' };
}

/* ---------- UZUM (asos — merchant hujjatlari bilan yakunlanadi) ---------- */
// Hisobni to'langan qiladi (Uzum handler tayyor bo'lганда shuni chaqiradi).
async function markInvoicePaid(invoiceId, provider, trans){
  const ref = db.collection('invoices').doc(String(invoiceId||''));
  const s = await ref.get(); if(!s.exists) return { ok:false, reason:'not-found' };
  if(s.data().status === 'paid') return { ok:true, already:true };
  await ref.set({ status:'paid', provider, providerTrans:String(trans||''), paidAt: FieldValue.serverTimestamp() }, { merge:true });
  return { ok:true };
}
// TODO: Uzum merchant API aniq shakli (maydon nomlari + imzo) bilan to'ldiriladi.
async function handleUzum(body){
  // Uzum odatda: invoice (bizning id) + amount + imzo (HMAC/shared secret) yuboradi.
  // Namuna (Uzum hujjatiga moslang): body.orderId, body.amount, body.signature.
  const invoiceId = body.invoice || body.orderId || body.merchant_trans_id;
  // XAVFSIZLIK: imzoni tekshiring (Uzum sxemasi bilan). Hozircha shared-secret placeholder:
  if(UZUM.secret && body.signature !== undefined){
    const expect = md5(String(invoiceId) + String(body.amount) + UZUM.secret);
    if(expect !== String(body.signature).toLowerCase()) return { ok:false, error:'sign' };
  }
  if(!invoiceId) return { ok:false, error:'no-invoice' };
  const inv = await getInvoice(invoiceId);
  if(!inv) return { ok:false, error:'not-found' };
  if(!amtEq(body.amount, inv.amount)) return { ok:false, error:'amount' };
  const r = await markInvoicePaid(invoiceId, 'uzum', body.transactionId || body.txn || '');
  return r.ok ? { ok:true } : { ok:false, error:r.reason };
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
    const send = obj => { res.writeHead(200, { 'Content-Type':'application/json' }); res.end(JSON.stringify(obj)); };
    try{
      if(req.url.startsWith('/click/prepare'))       send(await handlePrepare(body));
      else if(req.url.startsWith('/click/complete')) send(await handleComplete(body));
      else if(req.url.startsWith('/uzum'))           send(await handleUzum(body));
      else { res.writeHead(404); res.end('not found'); }
    }catch(e){ console.error('Xatolik:', e.message); res.writeHead(500); res.end('xatolik'); }
  });
  server.listen(PORT, () => console.log(`Iqror to'lov serveri tinglayapti :${PORT}  (/click/prepare, /click/complete, /uzum)`));
}

module.exports = { handlePrepare, handleComplete, handleUzum, markInvoicePaid, clickSign, md5 };
