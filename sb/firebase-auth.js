// =====================================================================
// firebase-auth.js (SHIM) — Firebase Auth API'sini Supabase Auth ustida taqlid.
// ⚠️ Bu Firebase EMAS — Supabase adapteri (V -> /sb bo'lganda yuklanadi).
// Qoplaydi: getAuth, setPersistence, browserLocalPersistence,
// signInWithEmailAndPassword, createUserWithEmailAndPassword, onAuthStateChanged,
// signOut, updatePassword, updateProfile, sendEmailVerification,
// GoogleAuthProvider, signInWithPopup, signInWithRedirect, getRedirectResult,
// signInAnonymously.
//
// Firebase user.uid -> Supabase user.id ; displayName -> user_metadata.displayName
// =====================================================================
import { supabase } from "./_core.js";

function mapUser(u) {
  if (!u) return null;
  const md = u.user_metadata || {};
  return {
    uid: u.id,
    email: u.email || null,
    displayName: md.displayName || md.full_name || md.name || null,
    emailVerified: !!(u.email_confirmed_at || u.confirmed_at),
    isAnonymous: !!u.is_anonymous,
    // Firebase moslik: Supabase JWT'da 'admin' custom-claim yo'q — rol users jadvalidan
    // aniqlanadi. Shu sabab claims'ni bo'sh qaytaramiz -> kod users.role fallback'iga o'tadi.
    async getIdToken() { try { const { data } = await supabase().auth.getSession(); return (data.session && data.session.access_token) || ""; } catch (_) { return ""; } },
    async getIdTokenResult() { let t = ""; try { const { data } = await supabase().auth.getSession(); t = (data.session && data.session.access_token) || ""; } catch (_) {} return { token: t, claims: {} }; },
    _raw: u,
  };
}
function mapErr(e) {
  const msg = (e && e.message) || String(e);
  const err = new Error(msg);
  err.status = e && e.status;
  const m = msg.toLowerCase();
  err.code = (e && e.code) ||
    (m.includes("invalid login") || m.includes("credential") ? "auth/invalid-credential" :
     m.includes("already registered") || m.includes("exists") ? "auth/email-already-in-use" :
     m.includes("password") ? "auth/weak-password" :
     m.includes("email") ? "auth/invalid-email" : "auth/error");
  return err;
}

// onAuthStateChanged — Firebase'dagidek FAQAT foydalanuvchi almashganda (kirish, chiqish, boshqa hisob) chaqiriladi.
//   supabase-js esa SHU foydalanuvchi uchun ham hodisa beradi: ilova/tabga har qaytilganda SIGNED_IN (_recoverAndRefresh),
//   taxminan har soatda TOKEN_REFRESHED, profil o'zgarsa USER_UPDATED, boshqa ochiq tablardan (BroadcastChannel) — xuddi shular.
//   Avval har biri tinglovchilarni qayta chaqirardi: admin.html panelni boshidan qurardi (Direktordan boshqa xodim birinchi
//   bo'limga qaytardi, saqlanmagan baho/davomat o'chardi), index.html kabinetni qayta chizardi («Qo'shish» formasi tozalanardi).
//   Endi shu foydalanuvchi hodisasida joriy obyekt JIM yangilanadi (o'sha obyekt — Firebase'dagidek: displayName, email, _raw).
//   _listeners: tinglovchi -> unga oxirgi yetkazilgan uid (undefined — hali chaqirilmagan; null — «kirilmagan» yetkazilgan).
let _currentUser = null;
const _listeners = new Map();
let _wired = false, _gotEvent = false;
function _deliver(cb) {
  if (!_listeners.has(cb)) return;                          // obuna bekor qilingan
  const uid = _currentUser ? _currentUser.uid : null;
  if (_listeners.get(cb) === uid) return;                   // shu holat bu tinglovchiga allaqachon yetkazilgan
  _listeners.set(cb, uid);
  try { cb(_currentUser); } catch (_) {}
}
function _emit() { for (const cb of Array.from(_listeners.keys())) _deliver(cb); }
function _setUser(raw) {
  const next = mapUser(raw);
  if (next && _currentUser && next.uid === _currentUser.uid) { Object.assign(_currentUser, next); return; }   // shu foydalanuvchi
  _currentUser = next;
  _emit();
}
function _wire() {
  if (_wired) return; _wired = true;
  const sb = supabase();
  // Boshlang'ich holat INITIAL_SESSION bilan ham keladi; getSession — zaxira. Hodisa allaqachon kelgan bo'lsa, getSession'ning
  //   eskirgan surati (masalan, shu orada chiqilgan bo'lsa) yangi holatni bosib o'tmasin.
  sb.auth.getSession().then(({ data }) => { if (!_gotEvent) _setUser(data && data.session ? data.session.user : null); }, () => {});
  sb.auth.onAuthStateChange((_ev, session) => { _gotEvent = true; _setUser(session ? session.user : null); });
}

export function getAuth(_app) {
  _wire();
  return { __sb: true, get currentUser() { return _currentUser; } };
}

export const browserLocalPersistence = "local";
export const browserSessionPersistence = "session";
export const indexedDBLocalPersistence = "local";
export function setPersistence(_auth, _p) { return Promise.resolve(); }

export async function signInWithEmailAndPassword(_auth, email, password) {
  const { data, error } = await supabase().auth.signInWithPassword({ email, password });
  if (error) throw mapErr(error);
  return { user: mapUser(data.user) };
}
export async function createUserWithEmailAndPassword(_auth, email, password) {
  const { data, error } = await supabase().auth.signUp({ email, password });
  if (error) throw mapErr(error);
  return { user: mapUser(data.user) };
}

export function onAuthStateChanged(_auth, cb) {
  _wire();
  if (!_listeners.has(cb)) _listeners.set(cb, undefined);
  Promise.resolve().then(() => _deliver(cb));   // joriy holat bir marta (keyin — faqat foydalanuvchi almashganda)
  return () => { _listeners.delete(cb); };
}
// Chiqish — FAQAT SHU QURILMA (scope 'local', Firebase signOut semantikasi). supabase-js standarti 'global' — foydalanuvchining
//   BARCHA qurilmalaridagi seanslarini bekor qiladi: umumiy maktab kompyuterida «Chiqish» bosgan o'qituvchi telefonidan ham
//   chiqib ketardi; admin.html'ni ochgan ota-onaning kabineti boshqa qurilmalarda ham yopilardi. 'local' seansni avval shu
//   brauzerdan o'chiradi — tarmoq bo'lmasa ham chiqiladi. Hamma qurilmadan chiqarish faqat ataylab so'ralganda:
//   signOut(auth, { scope: 'global' }) (masalan, bloklangan hisob — admin.html).
export async function signOut(_auth, opts) {
  const scope = (opts && opts.scope === "global") ? "global" : "local";
  const { error } = await supabase().auth.signOut({ scope });
  if (error) throw mapErr(error);
}

export async function updatePassword(_user, newPassword) {
  const { error } = await supabase().auth.updateUser({ password: newPassword });
  if (error) throw mapErr(error);
}
export async function updateProfile(_user, profile) {
  const data = {};
  if (profile && profile.displayName != null) data.displayName = profile.displayName;
  if (profile && profile.photoURL != null) data.photoURL = profile.photoURL;
  const { error } = await supabase().auth.updateUser({ data });
  if (error) throw mapErr(error);
}
export async function sendEmailVerification(user) {
  const email = (user && user.email) || (_currentUser && _currentUser.email);
  try { if (email) await supabase().auth.resend({ type: "signup", email }); } catch (_) {}
}
// Parolni tiklash xati (recovery). Foydalanuvchi havolani bosganда recovery seansi bilan
// qaytadi -> updatePassword(...) bilan yangi parol qo'yadi. redirectTo'да fragment BO'LMASIN.
export async function sendPasswordResetEmail(_auth, email) {
  const redirectTo = (typeof location !== "undefined") ? location.href.split("#")[0] : undefined;
  const { error } = await supabase().auth.resetPasswordForEmail(String(email || "").trim(), { redirectTo });
  if (error) throw mapErr(error);
}

export class GoogleAuthProvider {
  constructor() { this.providerId = "google.com"; this.scopes = []; }
  addScope(s) { this.scopes.push(s); return this; }
  setCustomParameters() { return this; }
  static credential() { return null; }
}
async function _oauthGoogle() {
  // MUHIM: redirectTo'да fragment (#...) BO'LMASLIGI kerak — OAuth token ham fragmentда
  // qaytadi va #ariza kabi mavjud fragment bilan to'qnashib, seans o'rnatilmaydi
  // (bad_oauth_state). Shu sabab hash'ni olib tashlaymiz (origin+path+query qoladi).
  const redirectTo = (typeof location !== "undefined") ? location.href.split("#")[0] : undefined;
  const { error } = await supabase().auth.signInWithOAuth({ provider: "google", options: { redirectTo } });
  if (error) throw mapErr(error);
  return new Promise(() => {});   // brauzer Google'ga yo'naltiriladi (sahifa almashadi)
}
export function signInWithPopup(_auth, _provider) { return _oauthGoogle(); }
export function signInWithRedirect(_auth, _provider) { return _oauthGoogle(); }
export async function getRedirectResult(_auth) {
  _wire();
  const { data } = await supabase().auth.getSession();
  const u = data && data.session ? data.session.user : null;
  return u ? { user: mapUser(u) } : null;
}

export async function signInAnonymously(_auth) {
  const { data, error } = await supabase().auth.signInAnonymously();
  if (error) throw mapErr(error);
  return { user: mapUser(data.user) };
}
