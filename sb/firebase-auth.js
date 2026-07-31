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

let _currentUser = null;
const _listeners = new Set();
let _wired = false;
function _emit() { for (const cb of _listeners) { try { cb(_currentUser); } catch (_) {} } }
function _wire() {
  if (_wired) return; _wired = true;
  const sb = supabase();
  sb.auth.getSession().then(({ data }) => { _currentUser = mapUser(data && data.session ? data.session.user : null); _emit(); });
  sb.auth.onAuthStateChange((_ev, session) => { _currentUser = mapUser(session ? session.user : null); _emit(); });
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
  _listeners.add(cb);
  Promise.resolve().then(() => { try { cb(_currentUser); } catch (_) {} });
  return () => _listeners.delete(cb);
}
export async function signOut(_auth) {
  const { error } = await supabase().auth.signOut();
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

export class GoogleAuthProvider {
  constructor() { this.providerId = "google.com"; this.scopes = []; }
  addScope(s) { this.scopes.push(s); return this; }
  setCustomParameters() { return this; }
  static credential() { return null; }
}
async function _oauthGoogle() {
  const redirectTo = (typeof location !== "undefined") ? location.href : undefined;
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
