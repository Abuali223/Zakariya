// =====================================================================
// backend.js — server xizmatlari uchun data qatlami (Supabase service_role).
//   -> sb-admin.js (Supabase) ; Qaytaradi: { db, FieldValue, verifyToken(idToken) -> uid|null }
//
// Ilgari bu yerda Firebase Admin SDK "rollback" tarmog'i ham bor edi. Loyiha
// to'liq Supabase'ga ko'chgach (Firebase loyihasi o'chirildi, deploy.sh
// firebase-admin'ni o'rnatmaydi ham), u tarmoq o'lik bo'lib qoldi va olib
// tashlandi. Barcha xizmatlar (ai-assistant, payments/sms-worker) shu bitta
// Supabase yo'li orqali ishlaydi.
// =====================================================================
module.exports = function (CFG) {
  CFG = CFG || {};
  const { makeDb, FieldValue, verifyToken } = require('./sb-admin.js');
  const db = makeDb(CFG);
  return { db, FieldValue, verifyToken: (t) => verifyToken(db, t) };
};
