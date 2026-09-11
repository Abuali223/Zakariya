// Attribution (findStudentByPhone) sinovi: bir xil telefonли to'lovlar noto'g'ri
// bolaга ko'r-ko'rona tushmasin. Soxta Supabase ustida handlePrepare (freeform).
//   node payments/attr.test.cjs
const fs = require('fs'), path = require('path'), crypto = require('crypto'), Module = require('module');

const state = { student_private: {}, students: {}, student_codes: {}, payments: {}, invoices: {} };
function match(r, filters) { return filters.every(([f, v]) => String(r[f]) === String(v)); }
function makeFake() {
  return { from(table) {
    const filters = [];
    const api = {
      select() { return api; },
      eq(f, v) { filters.push([f, v]); return api; },
      maybeSingle() { const rows = Object.values(state[table] || {}).filter(r => match(r, filters)); return Promise.resolve({ data: rows[0] || null, error: null }); },
      upsert(obj) { state[table] = state[table] || {}; state[table][obj.id] = Object.assign({}, state[table][obj.id], obj); return Promise.resolve({ error: null }); },
      insert(obj) { state[table] = state[table] || {}; if (state[table][obj.id]) return Promise.resolve({ error: { message: 'dup' } }); state[table][obj.id] = obj; return Promise.resolve({ error: null }); },
      update(obj) { return { eq(f, v) { for (const id in state[table] || {}) if (String(state[table][id][f]) === String(v)) Object.assign(state[table][id], obj); return Promise.resolve({ error: null }); } }; },
      delete() { return { eq(f, v) { for (const id in state[table] || {}) if (String(state[table][id][f]) === String(v)) delete state[table][id]; return Promise.resolve({ error: null }); } }; },
      then(res) { const rows = Object.values(state[table] || {}).filter(r => match(r, filters)); return Promise.resolve({ data: rows, error: null }).then(res); },
    };
    return api;
  } };
}
const orig = Module._load;
Module._load = function (req) { if (req === '@supabase/supabase-js') return { createClient: () => makeFake() }; return orig.apply(this, arguments); };

const CFGFILE = path.join(__dirname, '_attr-config.json');
const SECRET = 'ATTRSECRET';
fs.writeFileSync(CFGFILE, JSON.stringify({ backend: 'supabase', supabaseUrl: 'http://x', serviceRoleKey: 'k', click: { serviceId: '111', secretKey: SECRET } }));
process.env.IQROR_CONFIG = '_attr-config.json';
const { handlePrepare } = require('./index.cjs');

let fails = 0; const ok = (c, m) => { console.log((c ? '✓ ' : '✗ FAIL ') + m); if (!c) fails++; };
function sign(p) { return crypto.createHash('md5').update([p.click_trans_id, p.service_id, SECRET, p.merchant_trans_id, p.amount, p.action, p.sign_time].join('')).digest('hex'); }
let ctN = 1000;
async function prep(name, phone, klass, amount) {
  const p = { click_trans_id: String(++ctN), service_id: '111', merchant_trans_id: name, amount: String(amount || 2900000), action: '0', sign_time: '2026-09-10 08:00:00', param2: klass || '', param3: phone || '' };
  p.sign_string = sign(p);
  await handlePrepare(p);
  return state.payments['click_' + p.click_trans_id] || {};
}

(async () => {
  // Seed: IQ-0259 (Oybekov Abdulloh) parent phone 979980808. Siblings do NOT have this phone.
  state.student_private['IQ-0259'] = { id: 'IQ-0259', parentPhone: '+998979980808' };
  state.students['IQ-0259'] = { id: 'IQ-0259', studentId: 'IQ-0259', name: 'Oybekov Abdulloh Xojiakbar', grade: 3, classLetter: 'B' };

  // T1: correct child name -> matched to IQ-0259
  let r = await prep('Oybekov Abdulloh Xojiakbar', '979980808', '3B');
  ok(r.matched === true && r.studentId === 'IQ-0259', `T1 to'g'ri ism -> IQ-0259 (via=${r.raw && r.raw.via})`);

  // T2: DIFFERENT child (Qobiljonov), same phone -> name mismatch -> NOT credited (unmatched)
  r = await prep('Qobiljonov Abdurrohman', '979980808', '5A');
  ok(r.matched === false && !r.studentId, `T2 boshqa ism (Qobiljonov) -> biriktirilmagan (via=${r.raw && r.raw.via})`);

  // T3: no name provided -> trust phone -> matched
  r = await prep('', '979980808', '');
  ok(r.matched === true && r.studentId === 'IQ-0259', 'T3 ism yo\'q -> telefonga ishonadi -> IQ-0259');

  // T4: two siblings share phone -> disambiguate by name
  state.student_private['IQ-0256'] = { id: 'IQ-0256', parentPhone: '+998910000000' };
  state.students['IQ-0256'] = { id: 'IQ-0256', studentId: 'IQ-0256', name: 'Oybekov Muhammadulloh', grade: 2, classLetter: 'B' };
  state.student_private['IQ-0259'].parentPhone2 = '910000000';   // both now share 910000000
  state.student_private['IQ-0256'].parentPhone = '910000000';
  r = await prep('Oybekov Muhammadulloh', '910000000', '2B');
  ok(r.matched === true && r.studentId === 'IQ-0256', `T4 aka-uka -> ism bilan Muhammadulloh=IQ-0256 (via=${r.raw && r.raw.via})`);
  r = await prep('Oybekov Abdulloh Xojiakbar', '910000000', '3B');
  ok(r.matched === true && r.studentId === 'IQ-0259', 'T4b aka-uka -> ism bilan Abdulloh=IQ-0259');

  // T5: siblings share phone, name matches NEITHER -> ambiguous -> unmatched
  r = await prep('Butunlay Boshqa Odam', '910000000', 'ZZ');
  ok(r.matched === false && !r.studentId, 'T5 aka-uka, ism hech kimга mos emas -> biriktirilmagan');

  fs.unlinkSync(CFGFILE);
  console.log(fails ? `\n❌ ${fails} FAILED` : '\n✅ ALL PASS — attribution ismni tekshiradi');
  process.exit(fails ? 1 : 0);
})().catch(e => { try { fs.unlinkSync(CFGFILE); } catch (_) {} console.error('ERR', e); process.exit(1); });
