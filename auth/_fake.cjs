// =====================================================================
// _fake.cjs — auth testlari uchun SOXTA, stateful Supabase mijozi + auth.admin.
//   Qo'llab-quvvatlaydi: from(t).select/eq/gte/order/limit/insert/update(+eq, +select qaytarish) (thenable),
//   rpc('auth_uid_by_email'), auth.admin.createUser/updateUserById/deleteUser,
//   auth.signInWithPassword.  Hammasi in-memory `state` ustida.
//   QAT'IY: `id` takrori -> 23505 (PK); payments/_schema-columns.json'dagi jadvallarda yo'q ustunni
//   o'qish/yozish -> xato (haqiqiy PostgREST kabi), shunда ustun nomi xatosi testда ko'rinadi.
// =====================================================================
const SCHEMA = (() => { try { return require('../payments/_schema-columns.json'); } catch (e) { return null; } })();
function badCols(t, keys) { const cols = SCHEMA && SCHEMA[t]; if (!Array.isArray(cols)) return null;
  for (const k of keys) if (!cols.includes(k)) return { code: 'PGRST204', message: `Could not find the '${k}' column of '${t}' in the schema cache` };
  return null; }
function cmp(a, b) { return String(a) < String(b) ? -1 : String(a) > String(b) ? 1 : 0; }

function makeFake(state) {
  state.users = state.users || [];
  state.otp_codes = state.otp_codes || [];
  state.auth_login_attempts = state.auth_login_attempts || [];
  state.authUsers = state.authUsers || [];     // [{id,email,password}]
  state.__otpSeq = state.__otpSeq || 0;
  state.__attSeq = state.__attSeq || 0;
  state.__uidSeq = state.__uidSeq || 0;

  function table(t) { return (state[t] = state[t] || []); }

  function from(t) {
    const rows = table(t);
    const eqs = [], gtes = [], ins = [];
    let mode = 'select', payload = null, order = null, lim = null, selCols = null, selOpts = null, returning = false;
    const matchRow = r => eqs.every(([f, v]) => String(r[f]) === String(v)) && gtes.every(([f, v]) => String(r[f] || '') >= String(v))
      && ins.every(([f, arr]) => arr.map(String).includes(String(r[f])));
    function runSelect() {
      if (selCols && selCols !== '*') { const e = badCols(t, String(selCols).split(',').map(x => x.trim()).filter(Boolean)); if (e) return { data: null, error: { code: '42703', message: e.message } }; }
      const fe = badCols(t, eqs.map(x => x[0]).concat(gtes.map(x => x[0]), ins.map(x => x[0]))); if (fe) return { data: null, error: { code: '42703', message: fe.message } };
      let out = rows.filter(matchRow);
      if (order) out = out.slice().sort((a, b) => order.asc ? cmp(a[order.f], b[order.f]) : cmp(b[order.f], a[order.f]));
      if (lim != null) out = out.slice(0, lim);
      const count = (selOpts && selOpts.count) ? out.length : null;           // select(cols, {count:'exact', head:true})
      return { data: (selOpts && selOpts.head) ? null : out.map(r => ({ ...r })), count, error: null };
    }
    function runWrite() {
      if (mode === 'insert') {
        const arr = Array.isArray(payload) ? payload : [payload];
        for (const obj of arr) {
          const be = badCols(t, Object.keys(obj || {})); if (be) return { data: null, error: be };
          if (obj && obj.id != null && rows.some(r => String(r.id) === String(obj.id))) return { data: null, error: { code: '23505', message: 'duplicate key value violates unique constraint' } };
          const row = { ...obj };
          if (t === 'otp_codes') { row.id = ++state.__otpSeq; if (!row.createdAt) row.createdAt = new Date().toISOString(); }
          else if (t === 'sms_log') { if (!row.createdAt) row.createdAt = new Date(state.__now ? state.__now() : Date.now()).toISOString(); }   // DB: default now()
          else if (t === 'auth_login_attempts') { row.id = ++state.__attSeq; if (!row.at) row.at = new Date().toISOString(); }
          // users unique phone guard
          if (t === 'users' && row.phone) { if (rows.some(r => r.phone === row.phone)) return { data: null, error: { message: 'duplicate phone' } }; }
          rows.push(row);
        }
        return { data: null, error: null };
      }
      if (mode === 'delete') {
        const be = badCols(t, eqs.map(x => x[0])); if (be) return { data: null, error: be };
        for (let i = rows.length - 1; i >= 0; i--) if (matchRow(rows[i])) rows.splice(i, 1);
        return { data: null, error: null };
      }
      if (mode === 'update') {
        const be = badCols(t, Object.keys(payload || {}).concat(eqs.map(x => x[0]))); if (be) return { data: null, error: be };
        const hit = rows.filter(matchRow); hit.forEach(r => Object.assign(r, payload));
        return { data: returning ? hit.map(r => ({ ...r })) : null, error: null };
      }
      return { data: null, error: null };
    }
    const thenable = {
      select(cols, opts) { if (mode === 'update' || mode === 'insert') returning = true; else { mode = 'select'; selCols = cols || null; selOpts = opts || null; } return thenable; },
      eq(f, v) { eqs.push([f, v]); return thenable; },
      in(f, arr) { ins.push([f, Array.isArray(arr) ? arr : []]); return thenable; },
      delete() { mode = 'delete'; return thenable; },
      gte(f, v) { gtes.push([f, v]); return thenable; },
      order(f, opts) { order = { f, asc: !(opts && opts.ascending === false) }; return thenable; },
      limit(n) { lim = n; return thenable; },
      insert(obj) { mode = 'insert'; payload = obj; return thenable; },
      update(patch) { mode = 'update'; payload = patch; return thenable; },
      then(resolve) { resolve(mode === 'select' ? runSelect() : runWrite()); },
    };
    return thenable;
  }

  async function rpc(fn, params) {
    const p = params || {};
    if (fn === 'auth_uid_by_email') {
      const u = state.authUsers.find(a => String(a.email).toLowerCase() === String(p.p_email).toLowerCase());
      return { data: u ? u.id : null, error: null };
    }
    if (fn === 'otp_consume') {
      // migration/auth-hardening.sql otp_consume bilan bir xil mantiq (test uchun — ketma-ket).
      const rows = (state.otp_codes || []).filter(o => o.phone === p.p_phone && o.purpose === p.p_purpose && !o.consumed)
        .sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
      const r = rows[0];
      if (!r) return { data: { ok: false, nocode: true }, error: null };
      if (Date.parse(r.expiresAt) < Date.now()) return { data: { ok: false, expired: true }, error: null };
      if ((r.attempts || 0) >= p.p_max) return { data: { ok: false, locked: true }, error: null };
      if (r.codeHash === p.p_hash) { r.consumed = true; return { data: { ok: true, uid: r.uid || null }, error: null }; }
      r.attempts = (r.attempts || 0) + 1;
      return { data: { ok: false, remaining: Math.max(0, p.p_max - r.attempts), locked: r.attempts >= p.p_max }, error: null };
    }
    return { data: null, error: { message: 'unknown rpc ' + fn } };
  }

  const auth = {
    admin: {
      async createUser({ email, password, user_metadata }) {
        if (state.authUsers.some(a => String(a.email).toLowerCase() === String(email).toLowerCase()))
          return { data: null, error: { message: 'email exists' } };
        const id = 'uid_' + (++state.__uidSeq);
        state.authUsers.push({ id, email, password, user_metadata: user_metadata || {} });
        return { data: { user: { id, email } }, error: null };
      },
      async updateUserById(id, patch) {
        const u = state.authUsers.find(a => a.id === id);
        if (!u) return { data: null, error: { message: 'not found' } };
        if (patch.password != null) u.password = patch.password;
        if (patch.email != null) u.email = patch.email;
        return { data: { user: { id } }, error: null };
      },
      async deleteUser(id) {
        const i = state.authUsers.findIndex(a => a.id === id);
        if (i >= 0) state.authUsers.splice(i, 1);
        return { data: null, error: null };
      },
    },
    async signInWithPassword({ email, password }) {
      const u = state.authUsers.find(a => String(a.email).toLowerCase() === String(email).toLowerCase() && a.password === password);
      if (!u) return { data: null, error: { message: 'Invalid login credentials' } };
      return { data: { session: { access_token: 'at_' + u.id, refresh_token: 'rt_' + u.id, user: { id: u.id } } }, error: null };
    },
  };

  return { from, rpc, auth };
}
module.exports = { makeFake };
