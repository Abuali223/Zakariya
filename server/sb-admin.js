// =====================================================================
// sb-admin.js — Firebase Admin SDK (Firestore) yuzasini Supabase service_role
// ustida taqlid qiladi (SERVER tomoni). service_role RLS'ni chetlab o'tadi —
// Admin SDK kabi. Server xizmatlari (ai-assistant, ai-grader, payments) shu
// orqali Supabase'ga o'tadi: biznes-mantiq o'zgarmaydi, faqat data qatlami.
//
// Qoplaydi (xizmatlar aynan shundan foydalanadi):
//   db.collection(t).doc(id).get()/set(data[,{merge}])/update(data)/delete()
//   db.collection(t).get()
//   db.collection(t).where(field,op,value).get()      (chainable)
//   snapshot.docs[i].{id, exists, ref, data()}         (exists = PROPERTY, admin uslubi)
//   FieldValue.serverTimestamp()
//   verifyToken(db, jwt) -> uid | null
//
// Ustun nomlari Firestore maydonlari bilan bir xil -> qator ≈ hujjat.
// =====================================================================
const SERVER_TS = Symbol('serverTimestamp');
const FieldValue = { serverTimestamp: () => SERVER_TS, delete: () => null };

function prep(data) {
  const o = {};
  for (const k in data) { const v = data[k]; o[k] = (v === SERVER_TS) ? new Date().toISOString() : v; }
  return o;
}
const OPS = { '==': 'eq', '!=': 'neq', '>': 'gt', '>=': 'gte', '<': 'lt', '<=': 'lte' };
function applyCons(q, cons) {
  for (const c of cons) {
    if (c.op === 'in') q = q.in(c.field, c.value);
    else if (c.op === 'array-contains') q = q.contains(c.field, JSON.stringify([c.value]));
    else q = q[OPS[c.op] || 'eq'](c.field, c.value);
  }
  return q;
}

function makeDocRef(sb, table, id) {
  const ref = {
    id,
    async get() {
      const { data, error } = await sb.from(table).select('*').eq('id', id).maybeSingle();
      if (error && error.code !== 'PGRST116') throw error;
      return { id, exists: !!data, ref, data: () => (data || undefined) };
    },
    async set(data, _opts) {   // set va set+merge — ikkalasi ham upsert (id konflikti)
      const { error } = await sb.from(table).upsert({ id, ...prep(data) }, { onConflict: 'id' });
      if (error) throw error;
    },
    async update(data) {
      const { error } = await sb.from(table).update(prep(data)).eq('id', id);
      if (error) throw error;
    },
    async delete() {
      const { error } = await sb.from(table).delete().eq('id', id);
      if (error) throw error;
    },
  };
  return ref;
}

function makeQuery(sb, table, cons) {
  return {
    where(field, op, value) { return makeQuery(sb, table, cons.concat([{ field, op, value }])); },
    async get() {
      let q = sb.from(table).select('*');
      q = applyCons(q, cons);
      const { data, error } = await q;
      if (error) throw error;
      const docs = (data || []).map(r => ({ id: r.id, exists: true, ref: makeDocRef(sb, table, r.id), data: () => r }));
      return { docs, size: docs.length, empty: docs.length === 0, forEach: fn => docs.forEach(fn) };
    },
  };
}

function makeDb(cfg) {
  cfg = cfg || {};
  let sb = cfg.client;                       // sinov uchun tayyor mijoz inject qilish mumkin
  if (!sb) {
    const { createClient } = require('@supabase/supabase-js');   // kech-require (VPS'da o'rnatiladi)
    const url = cfg.supabaseUrl || process.env.SUPABASE_URL;
    const key = cfg.serviceRoleKey || process.env.SERVICE_ROLE_KEY;
    sb = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  }
  return {
    _sb: sb,
    collection(name) {
      const q = makeQuery(sb, name, []);
      return {
        doc: (id) => makeDocRef(sb, name, String(id)),
        where: (f, op, v) => q.where(f, op, v),
        get: () => q.get(),
      };
    },
  };
}

// Firebase getAuth().verifyIdToken(token).uid ekvivalenti (Supabase JWT).
async function verifyToken(db, jwt) {
  try {
    const { data, error } = await db._sb.auth.getUser(String(jwt || ''));
    if (error || !data || !data.user) return null;
    return data.user.id;
  } catch (_) { return null; }
}

module.exports = { makeDb, FieldValue, verifyToken };
