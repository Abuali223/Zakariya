// server/sb-admin.js tarjima sinovi (real @supabase paketsiz — soxta mijoz inject).
// Ishga tushirish:  node server/sb-admin.test.cjs
const { makeDb, FieldValue } = require('./sb-admin.js');

let REC = null, CANNED = [];
function builder(table) {
  const rec = { table, ops: [] };
  const b = {
    select(x) { rec.ops.push(['select', x]); return b; },
    eq(f, v) { rec.ops.push(['eq', f, v]); return b; },
    neq(f, v) { rec.ops.push(['neq', f, v]); return b; },
    in(f, v) { rec.ops.push(['in', f, v]); return b; },
    contains(f, v) { rec.ops.push(['contains', f, v]); return b; },
    gt(f, v) { rec.ops.push(['gt', f, v]); return b; },
    gte(f, v) { rec.ops.push(['gte', f, v]); return b; },
    lt(f, v) { rec.ops.push(['lt', f, v]); return b; },
    lte(f, v) { rec.ops.push(['lte', f, v]); return b; },
    upsert(obj, o) { rec.ops.push(['upsert', obj, o]); return b; },
    update(obj) { rec.ops.push(['update', obj]); return b; },
    delete() { rec.ops.push(['delete']); return b; },
    maybeSingle() { rec.single = true; return Promise.resolve({ data: CANNED[0] || null, error: null }); },
    then(res) { return Promise.resolve({ data: CANNED, error: null }).then(res); },
  };
  REC = rec;
  return b;
}
const fake = { from: (t) => builder(t) };

let fails = 0;
const ok = (c, m) => { console.log((c ? '✓ ' : '✗ FAIL ') + m); if (!c) fails++; };
const eq = (a, b, m) => ok(JSON.stringify(a) === JSON.stringify(b), m + '  (got ' + JSON.stringify(a) + ')');

(async () => {
  const db = makeDb({ client: fake });

  // doc().get() -> select().eq(id).maybeSingle(); exists PROPERTY + data()
  CANNED = [{ id: 'INV1', amount: 500000, status: 'unpaid' }];
  const s = await db.collection('invoices').doc('INV1').get();
  eq(REC.ops, [['select', '*'], ['eq', 'id', 'INV1']], 'doc.get -> select().eq(id)');
  ok(REC.single === true, 'doc.get maybeSingle() ishlatadi');
  ok(s.exists === true && s.data().amount === 500000 && s.id === 'INV1', 'snapshot exists(PROPERTY)/data()/id');

  // yo'q hujjat -> exists=false
  CANNED = [];
  const s2 = await db.collection('invoices').doc('NOPE').get();
  ok(s2.exists === false && s2.data() === undefined, 'yo\'q hujjat: exists=false, data()=undefined');

  // collection().where(==).get()  (server faqat == ishlatadi)
  CANNED = [{ id: 'A1' }, { id: 'A2' }];
  const q = await db.collection('applications').where('status', '==', 'submitted').get();
  eq(REC.ops, [['select', '*'], ['eq', 'status', 'submitted']], 'where(==) -> select().eq()');
  ok(q.size === 2 && q.docs[0].id === 'A1' && q.docs[0].exists === true, 'query snapshot docs/size');
  ok(typeof q.docs[0].ref.set === 'function', 'query doc .ref mavjud (set bor)');

  // collection().get() (filtersiz)
  CANNED = [{ id: 'X' }];
  await db.collection('students').get();
  eq(REC.ops, [['select', '*']], 'collection.get -> select() (filtersiz)');

  // doc().set(data) -> upsert(onConflict=id)
  await db.collection('payments').doc('P1').set({ status: 'prepared', amount: 500000 });
  const up = REC.ops.find(x => x[0] === 'upsert');
  ok(up[1].id === 'P1' && up[1].status === 'prepared', 'set -> upsert id+maydon');
  ok(up[2] && up[2].onConflict === 'id', 'upsert onConflict=id');

  // set + FieldValue.serverTimestamp() -> ISO
  await db.collection('invoices').doc('INV1').set({ status: 'paid', paidAt: FieldValue.serverTimestamp() }, { merge: true });
  const up2 = REC.ops.find(x => x[0] === 'upsert');
  ok(typeof up2[1].paidAt === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(up2[1].paidAt), 'serverTimestamp -> ISO string');

  // update() -> update().eq(id)
  await db.collection('invoices').doc('INV1').update({ status: 'paid' });
  eq(REC.ops, [['update', { status: 'paid' }], ['eq', 'id', 'INV1']], 'update -> update().eq(id)');

  // ref.set from query doc (ai-grader/payments uslubi)
  CANNED = [{ id: 'Q1' }];
  const q2 = await db.collection('applications').where('status', '==', 'submitted').get();
  await q2.docs[0].ref.set({ status: 'graded' }, { merge: true });
  const up3 = REC.ops.find(x => x[0] === 'upsert');
  ok(up3[1].id === 'Q1' && up3[1].status === 'graded', 'query doc .ref.set -> upsert');

  console.log('\n' + (fails ? ('❌ ' + fails + ' FAILED') : '✅ ALL PASS — sb-admin Firebase Admin yuzasi bilan mos'));
  process.exit(fails ? 1 : 0);
})().catch(e => { console.error('ERR', e.stack || e.message); process.exit(2); });
