// =====================================================================
// _fake-sb.cjs — pul oqimi testlari uchun SOXTA, stateful Supabase mijozi.
//   Ikki qismdan iborat:
//     1) from(table)  — doc/collection ustasi (sb-admin.js shuni chaqiradi):
//        select/eq/maybeSingle/upsert/insert/update/delete/then — in-memory `state` ustida.
//     2) rpc(fn,params) — pul RPC'larini (apply_payment / apply_to_invoice / reverse_payment)
//        HAQIQIY SQL (migration/audit-7.sql, audit-5.sql, reverse-payment.sql) kabi, aynan
//        o'sha jsonb shakllarini qaytarib va o'sha jadval o'zgarishlarini `state` ustida bajaradi.
//        (Ruxsat/JWT tekshiruvi, FOR UPDATE, advisory lock — bir-oqimli jarayonda keraksiz.)
//
//   Ishlatish (test faylida):
//     const { makeFake } = require('./_fake-sb.cjs');
//     const state = { invoices:{}, payments:{}, students:{} };
//     Module._load = (req,...a)=> req==='@supabase/supabase-js'
//        ? { createClient: () => makeFake(state) } : orig(req,...a);
// =====================================================================

const NOW = '2026-08-01T12:00:00+05:00';   // test uchun qat'iy "hozir" (faqat truthy/ketma-ketlik muhim)

function match(r, filters) { return filters.every(([f, v]) => String(r[f]) === String(v)); }

function makeFake(state, nowFn) {
  const now = nowFn || (() => NOW);
  const tbl = t => (state[t] = state[t] || {});
  const num = v => { const n = Number(v); return isFinite(n) ? n : 0; };
  const ledger = row => { const id = 'cl_' + (state.__cl = (state.__cl || 0) + 1); tbl('credit_ledger')[id] = Object.assign({ id, at: now() }, row); };

  // ---- Kanonik studentId (audit-7.sql:51-54): id==p_sid yoki studentId==p_sid, id mosligi ustun ----
  const canonicalSid = p_sid => {
    const studs = Object.values(state.students || {});
    const byId = studs.find(r => String(r.id) === String(p_sid));
    const bySid = studs.find(r => String(r.studentId) === String(p_sid));
    const hit = byId || bySid;
    return (hit && hit.studentId) ? String(hit.studentId) : String(p_sid);
  };
  const isUnpaid = inv => (inv.status == null) || !['paid', 'canceled', 'reversed'].includes(inv.status);
  const sortKey = inv => String((inv.month && inv.month !== '') ? inv.month : inv.id);

  // ---- apply_payment (migration/audit-7.sql) — avans + waterfall (eski invoicelar oldin) ----
  const apply_payment = p => {
    const amt = num(p.p_amount); if (amt < 0) return { ok: false, reason: 'neg' };
    const provider = (p.p_provider && String(p.p_provider)) || (amt > 0 ? 'click' : 'credit');
    const sid = canonicalSid(p.p_sid);
    if (p.p_pay_id) { const ap = tbl('applied_payments'); if (ap[p.p_pay_id]) return { dup: true };
      ap[p.p_pay_id] = { id: p.p_pay_id, studentId: sid, amount: amt, createdAt: now() }; }
    const sc = tbl('student_credit');
    const credit = (sc[sid] && num(sc[sid].credit)) || 0;
    let available = amt + credit;   // mavjud avans AVVAL sarflanadi
    const unpaid = Object.values(state.invoices || {})
      .filter(inv => String(inv.studentId) === String(sid) && isUnpaid(inv))
      .sort((a, b) => sortKey(a).localeCompare(sortKey(b)));
    for (const inv of unpaid) {
      if (available <= 0) break;
      const paid = num(inv.paidAmount), amount = num(inv.amount), remaining = amount - paid;
      if (remaining <= 0) continue;
      const pay = Math.min(available, remaining), newpaid = paid + pay, full = newpaid >= amount - 0.5;
      inv.paidAmount = newpaid; inv.status = full ? 'paid' : 'partial'; inv.provider = provider; if (full) inv.paidAt = now();
      available -= pay;
    }
    sc[sid] = { id: sid, studentId: sid, credit: available, updatedAt: now() };   // yakuniy avans (absolute)
    const delta = available - credit;
    if (Math.abs(delta) >= 0.5) ledger({ studentId: sid, studentName: (state.students && state.students[sid] && state.students[sid].name) || '', delta, balanceAfter: available, reason: delta > 0 ? 'overpay' : 'applied', provider });
    return { ok: true, credit: available, sid };
  };

  // ---- apply_to_invoice (migration/audit-5.sql) — bitta invoice, ortig'i avansga ----
  const apply_to_invoice = p => {
    const amt = num(p.p_amount); if (amt < 0) return { ok: false, reason: 'neg' };
    const provider = (p.p_provider && String(p.p_provider)) || 'click';
    const inv = (state.invoices || {})[p.p_invoice];
    if (!inv) return { ok: false, error: 'notfound' };                         // guard'dan OLDIN
    if (inv.status === 'reversed' || inv.status === 'canceled') return { ok: false, error: 'terminal' };
    const sid = inv.studentId;
    if (p.p_pay_id) { const ap = tbl('applied_payments'); if (ap[p.p_pay_id]) return { dup: true };
      ap[p.p_pay_id] = { id: p.p_pay_id, studentId: sid, amount: amt, createdAt: now() }; }
    const paid = num(inv.paidAmount), amount = num(inv.amount), newpaid = paid + amt;
    const full = newpaid >= amount - 0.5, overflow = Math.max(0, newpaid - amount);
    inv.paidAmount = full ? amount : newpaid;                                   // to'liqda amount'ga qisiladi
    inv.status = full ? 'paid' : 'partial'; inv.provider = provider; if (full) inv.paidAt = now();
    if (overflow > 0 && sid) { const sc = tbl('student_credit'); const cr = (sc[sid] && num(sc[sid].credit)) || 0;
      sc[sid] = { id: sid, studentId: sid, credit: cr + overflow, updatedAt: now() };   // ortig'i avansga (delta)
      ledger({ studentId: sid, studentName: (state.students && state.students[sid] && state.students[sid].name) || '', delta: overflow, balanceAfter: cr + overflow, reason: 'overpay', provider }); }
    return { ok: true, status: full ? 'paid' : 'partial', overflow, studentId: sid || '' };
  };

  // ---- reverse_payment (migration/reverse-payment.sql) — bitta to'lovni qaytarish ----
  const reverse_payment = p => {
    const amt = num(p.p_amount); if (amt <= 0) return { ok: false, reason: 'amount<=0' };   // <=0 (apply'dagi <0 emas)
    const provider = (p.p_provider && String(p.p_provider)) || 'uzum';
    const inv = (state.invoices || {})[p.p_invoice];
    if (!inv) return { ok: false, error: 'notfound' };
    const sid = inv.studentId;
    if (p.p_ref) { const gid = 'reverse:' + p.p_ref; const ap = tbl('applied_payments');   // ALOHIDA namespace
      if (ap[gid]) return { dup: true, ref: p.p_ref };
      ap[gid] = { id: gid, studentId: sid || '', amount: amt, createdAt: now() }; }
    const paid = num(inv.paidAmount), amount = num(inv.amount);
    const fromInvoice = Math.min(amt, paid), fromCredit = Math.max(0, amt - fromInvoice), newpaid = Math.max(0, paid - fromInvoice);
    const status = newpaid <= 0 ? 'reversed' : (newpaid >= amount - 0.5 ? 'paid' : 'partial');
    inv.paidAmount = newpaid; inv.status = status; inv.reversedAt = now();      // provider'ga TEGMAYDI
    if (fromCredit > 0 && sid) { const sc = tbl('student_credit'); const cr = (sc[sid] && num(sc[sid].credit)) || 0;
      const nc = Math.max(0, cr - fromCredit); sc[sid] = { id: sid, studentId: sid, credit: nc, updatedAt: now() };
      ledger({ studentId: sid, studentName: (state.students && state.students[sid] && state.students[sid].name) || '', delta: -fromCredit, balanceAfter: nc, reason: 'reversed', provider }); }
    return { ok: true, status, fromInvoice, fromCredit, newPaid: newpaid, studentId: sid || '' };
  };

  const RPCS = { apply_payment, apply_to_invoice, reverse_payment };

  return {
    from(table) {
      const filters = [];
      const api = {
        select() { return api; },
        eq(f, v) { filters.push([f, v]); return api; },
        maybeSingle() { const rows = Object.values(state[table] || {}).filter(r => match(r, filters)); return Promise.resolve({ data: rows[0] || null, error: null }); },
        upsert(obj) { tbl(table)[obj.id] = Object.assign({}, state[table][obj.id], obj); return Promise.resolve({ error: null }); },
        insert(obj) { if (tbl(table)[obj.id]) return Promise.resolve({ error: { message: 'dup' } }); state[table][obj.id] = obj; return Promise.resolve({ error: null }); },
        update(obj) { return { eq(f, v) { for (const id in state[table] || {}) if (String(state[table][id][f]) === String(v)) Object.assign(state[table][id], obj); return Promise.resolve({ error: null }); } }; },
        delete() { return { eq(f, v) { for (const id in state[table] || {}) if (String(state[table][id][f]) === String(v)) delete state[table][id]; return Promise.resolve({ error: null }); } }; },
        then(res) { const rows = Object.values(state[table] || {}).filter(r => match(r, filters)); return Promise.resolve({ data: rows, error: null }).then(res); },
      };
      return api;
    },
    // sb-admin.js:94 -> const {data,error}=await sb.rpc(fn,params); if(error) throw error; return data;
    rpc(fn, params) {
      const h = RPCS[fn];
      if (!h) return Promise.resolve({ data: null, error: { message: 'fake: unknown rpc ' + fn } });
      try { return Promise.resolve({ data: h(params || {}), error: null }); }
      catch (e) { return Promise.resolve({ data: null, error: { message: String(e && e.message || e) } }); }
    },
  };
}

module.exports = { makeFake };
