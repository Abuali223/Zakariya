// users/{uid}.role == 'admin' bo'lsa foydalanuvchiga admin custom-claim beriladi.
// Shu bilan admin panelidan admin qilingan har bir o'qituvchi rasm/video yuklay oladi
// (Storage qoidalari faqat claim'ni ko'ra oladi, Firestore rolini emas).
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

initializeApp();

exports.syncAdminClaim = onDocumentWritten("users/{uid}", async (event) => {
  const uid = event.params.uid;
  const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
  const wantAdmin = !!(after && after.role === "admin");
  try {
    const user = await getAuth().getUser(uid);
    const hasAdmin = !!(user.customClaims && user.customClaims.admin === true);
    if (hasAdmin === wantAdmin) return;
    const claims = Object.assign({}, user.customClaims || {});
    if (wantAdmin) claims.admin = true; else delete claims.admin;
    await getAuth().setCustomUserClaims(uid, claims);
    // Keyingi tokenда yangi claim bo'lishi uchun
    await getAuth().revokeRefreshTokens(uid);
    console.log("admin claim", wantAdmin ? "granted" : "removed", uid);
  } catch (e) {
    console.error("claim sync failed for", uid, e.message);
  }
});

// ---- AI yordamchi (HTTPS) — chatbot, ota-onaga xulosa, xavf tahlili ----
// URL: shu funksiyaning bazasi. Sayt/admin config/ai.url ga shu manzilni yozadi.
const { onRequest } = require("firebase-functions/v2/https");
const { handleAI } = require("./ailogic");
exports.ai = onRequest(
  { region: "us-central1", cors: true, memory: "512MiB", timeoutSeconds: 120, maxInstances: 5 },
  handleAI
);
