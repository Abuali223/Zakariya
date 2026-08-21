// =====================================================================
// firebase-firestore.js (SHIM) — Firestore (modular) API'sini Supabase ustida taqlid.
// ⚠️ Bu Firebase EMAS — Supabase adapteri. Nomi shu (firebase-firestore.js) chunki
// frontend importlari ${V}/firebase-firestore.js ni chaqiradi; V -> /sb bo'lganda
// shu fayl yuklanadi. Ustun nomlari Firestore maydonlari bilan bir xil bo'lgani
// uchun qaytgan qator ≈ Firestore hujjati.
//
// Qoplaydi: getFirestore, initializeFirestore, persistentLocalCache,
// persistentMultipleTabManager, collection, doc, query, where, orderBy, limit,
// getDoc, getDocs, setDoc, addDoc, updateDoc, deleteDoc, deleteField,
// serverTimestamp, writeBatch, onSnapshot.
// =====================================================================
import { supabase } from "./_core.js";

// db handle (Firestore init funksiyalarini bekorga chiqaramiz)
export function getFirestore() { return { __sb: true }; }
export function initializeFirestore() { return { __sb: true }; }
export function persistentLocalCache() { return {}; }
export function persistentMultipleTabManager() { return {}; }

// ---- sentinels ----
const SERVER_TS = Symbol("serverTimestamp");
const DELETE_FIELD = Symbol("deleteField");
export function serverTimestamp() { return SERVER_TS; }
export function deleteField() { return DELETE_FIELD; }

// ---- timestamptz (ISO satr) -> .toDate() bo'ladigan obyekt ----
function wrapVal(v) {
  if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:/.test(v)) {
    const d = new Date(v);
    return { toDate: () => d, seconds: Math.floor(d.getTime() / 1000), toString: () => v, valueOf: () => v };
  }
  return v;
}
function wrapRow(row) { if (!row) return row; const o = {}; for (const k in row) o[k] = wrapVal(row[k]); return o; }
function prep(data) {
  const o = {};
  for (const k in data) {
    const v = data[k];
    if (v === SERVER_TS) o[k] = new Date().toISOString();
    else if (v === DELETE_FIELD) o[k] = null;
    else o[k] = v;
  }
  return o;
}

// ---- refs ----
export function collection(_db, name) { return { _kind: "coll", _t: name }; }
export function doc(a, b, c) {
  if (a && a._kind === "coll") return { _kind: "doc", _t: a._t, _id: b };  // doc(collRef, id)
  return { _kind: "doc", _t: b, _id: c };                                   // doc(db, name, id)
}
export function query(collRef, ...cons) { return { _kind: "query", _t: collRef._t, _cons: cons }; }
export function where(field, op, value) { return { _c: "where", field, op, value }; }
export function orderBy(field, dir) { return { _c: "order", field, dir: dir || "asc" }; }
export function limit(n) { return { _c: "limit", n }; }

const OPS = { "==": "eq", "!=": "neq", ">": "gt", ">=": "gte", "<": "lt", "<=": "lte" };
function applyCons(q, cons) {
  for (const c of cons || []) {
    if (c._c === "where") {
      if (c.op === "in") q = q.in(c.field, c.value);
      else if (c.op === "array-contains") q = q.contains(c.field, JSON.stringify([c.value]));
      else q = q[OPS[c.op] || "eq"](c.field, c.value);
    } else if (c._c === "order") q = q.order(c.field, { ascending: c.dir !== "desc" });
    else if (c._c === "limit") q = q.limit(c.n);
  }
  return q;
}

// ---- reads ----
export async function getDoc(ref) {
  const { data, error } = await supabase().from(ref._t).select("*").eq("id", ref._id).maybeSingle();
  if (error && error.code !== "PGRST116") throw error;
  return { id: ref._id, exists: () => !!data, data: () => wrapRow(data) };
}
export async function getDocs(refOrQuery) {
  const cons = refOrQuery._kind === "query" ? (refOrQuery._cons || []) : [];
  const hasLimit = cons.some(c => c._c === "limit");
  const PAGE = 1000;
  let all = [], from = 0;
  // PostgREST standart max-rows (odatda 1000) ni chetlab, hamma qatorni sahifalab olamiz.
  // Aniq .limit(n) berilgan so'rovlarda — bitta o'qish (limitni hurmat qilamiz).
  while (true) {
    let q = applyCons(supabase().from(refOrQuery._t).select("*"), cons);
    if (!hasLimit) q = q.range(from, from + PAGE - 1);
    const { data, error } = await q;
    if (error) throw error;
    const rows = data || [];
    all = all.concat(rows);
    if (hasLimit || rows.length < PAGE) break;
    from += PAGE;
  }
  const docs = all.map(r => ({ id: r.id, exists: () => true, data: () => wrapRow(r) }));
  return { docs, size: docs.length, empty: docs.length === 0, forEach: fn => docs.forEach(fn) };
}

// ---- writes ----
export async function setDoc(ref, data, _opts) {
  const { error } = await supabase().from(ref._t).upsert({ id: ref._id, ...prep(data) }, { onConflict: "id" });
  if (error) throw error;
}
export async function addDoc(collRef, data) {
  const id = (globalThis.crypto?.randomUUID?.() || Date.now() + Math.random().toString(36).slice(2));
  const { error } = await supabase().from(collRef._t).insert({ id, ...prep(data) });
  if (error) throw error;
  return { id };
}
export async function updateDoc(ref, data) {
  const { error } = await supabase().from(ref._t).update(prep(data)).eq("id", ref._id);
  if (error) throw error;
}
export async function deleteDoc(ref) {
  const { error } = await supabase().from(ref._t).delete().eq("id", ref._id);
  if (error) throw error;
}
export function writeBatch(_db) {
  const ops = [];
  return {
    set(ref, data, opts) { ops.push(["set", ref, data, opts]); return this; },
    update(ref, data) { ops.push(["update", ref, data]); return this; },
    delete(ref) { ops.push(["delete", ref]); return this; },
    async commit() {
      for (const [k, ref, data, opts] of ops) {
        if (k === "set") await setDoc(ref, data, opts);
        else if (k === "update") await updateDoc(ref, data);
        else if (k === "delete") await deleteDoc(ref);
      }
    }
  };
}

// ---- onSnapshot (boshlang'ich o'qish + realtime) ----
export function onSnapshot(refOrQuery, cb) {
  let alive = true;
  const emit = async () => { try { const s = await getDocs(refOrQuery); if (alive) cb(s); } catch (e) {} };
  emit();
  let ch = null;
  try {
    ch = supabase().channel("c_" + refOrQuery._t + "_" + Math.random().toString(36).slice(2))
      .on("postgres_changes", { event: "*", schema: "public", table: refOrQuery._t }, emit)
      .subscribe();
  } catch (e) {}
  return () => { alive = false; try { ch && supabase().removeChannel(ch); } catch (e) {} };
}
