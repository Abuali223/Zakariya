// =====================================================================
// backend.js — server xizmatlari uchun data qatlamini tanlaydi.
//   CFG.backend === 'supabase'  -> Supabase service_role (sb-admin.js)
//   aks holda (default)          -> Firebase Admin SDK  (rollback uchun saqlanadi)
// Qaytaradi: { db, FieldValue, verifyToken(idToken) -> uid|null }
//
// Shu tufayli ai-assistant/payments biznes-mantig'i BITTA nusxa qoladi va
// ikkala backendda ham ishlaydi (parallel-sinov + rollback oson).
// =====================================================================
module.exports = function (CFG) {
  CFG = CFG || {};
  if ((CFG.backend || 'firebase') === 'supabase') {
    const { makeDb, FieldValue, verifyToken } = require('./sb-admin.js');
    const db = makeDb(CFG);
    return { db, FieldValue, verifyToken: (t) => verifyToken(db, t) };
  }
  // ---- Firebase (eski) ----
  const path = require('path');
  const { initializeApp, cert } = require('firebase-admin/app');
  const { getFirestore, FieldValue } = require('firebase-admin/firestore');
  const { getAuth } = require('firebase-admin/auth');
  initializeApp({ credential: cert(require(path.resolve(CFG.__dir || process.cwd(), CFG.serviceAccount))) });
  return {
    db: getFirestore(),
    FieldValue,
    verifyToken: async (t) => { try { return (await getAuth().verifyIdToken(String(t))).uid; } catch (_) { return null; } },
  };
};
