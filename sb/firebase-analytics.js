// =====================================================================
// firebase-analytics.js (SHIM) — Supabase'да Firebase Analytics yo'q.
// Frontend faqat isSupported() + getAnalytics() ni chaqiradi -> no-op qaytaramiz.
// (Xohlasangiz keyinchalik o'z analitikangizni shu yerga ulash mumkin.)
// =====================================================================
export function isSupported() { return Promise.resolve(false); }
export function getAnalytics() { return null; }
export function logEvent() {}
