// =====================================================================
// firebase-app.js (SHIM) — initializeApp() Firebase config'ni oladi (frontend
// o'zgarmaydi), lekin aslida Supabase mijozini sb-config.js qiymatlari bilan
// ishga tushiradi. ⚠️ Bu Firebase EMAS — Supabase adapteri (V -> /sb).
// =====================================================================
import { initSupabase } from "./_core.js";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./sb-config.js";

export function initializeApp(_firebaseConfig) {
  initSupabase(SUPABASE_URL, SUPABASE_ANON_KEY);
  return { __sb: true, name: "[DEFAULT]" };
}
export function getApp() { return { __sb: true, name: "[DEFAULT]" }; }
export function getApps() { return [{ __sb: true, name: "[DEFAULT]" }]; }
