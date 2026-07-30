// Firebase -> to'liq JSON zaxira (FAQAT O'QIYDI, hech nima o'zgartirmaydi).
// Chiqish: firestore/<collection>.json, auth_users.json, storage_files.json
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, Timestamp, GeoPoint } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { getStorage } = require('firebase-admin/storage');
const fs = require('fs'), path = require('path');

initializeApp({ credential: cert(require(process.env.SA)), storageBucket: 'alilazer-cd582.firebasestorage.app' });
const db = getFirestore(), auth = getAuth();

const OUT = process.env.OUT;
fs.mkdirSync(path.join(OUT, 'firestore'), { recursive: true });

// Firestore qiymatlarini (Timestamp/GeoPoint) qayta tiklanadigan shaklga o'giramiz
function conv(v){
  if (v instanceof Timestamp) return { __timestamp__: v.toDate().toISOString(), __ts_seconds__: v.seconds };
  if (v instanceof GeoPoint)  return { __geopoint__: [v.latitude, v.longitude] };
  if (Array.isArray(v)) return v.map(conv);
  if (v && typeof v === 'object' && v.constructor === Object) { const o = {}; for (const k in v) o[k] = conv(v[k]); return o; }
  return v;
}

(async () => {
  const summary = {}; let totalDocs = 0;
  const cols = await db.listCollections();
  for (const col of cols) {
    const snap = await col.get();
    const docs = {};
    snap.forEach(d => { docs[d.id] = conv(d.data()); });
    fs.writeFileSync(path.join(OUT, 'firestore', col.id + '.json'), JSON.stringify(docs, null, 2));
    summary[col.id] = snap.size; totalDocs += snap.size;
  }
  // Auth foydalanuvchilar (parol HASH bilan — migratsiyada login saqlanadi)
  let users = [], pageToken;
  do {
    const res = await auth.listUsers(1000, pageToken);
    users.push(...res.users.map(u => u.toJSON()));
    pageToken = res.pageToken;
  } while (pageToken);
  fs.writeFileSync(path.join(OUT, 'auth_users.json'), JSON.stringify(users, null, 2));
  summary['__auth_users'] = users.length;
  // Storage fayllar ro'yxati (rasmlar)
  try {
    const [files] = await getStorage().bucket().getFiles();
    const list = files.map(f => ({ name: f.name, size: Number(f.metadata.size) || 0, contentType: f.metadata.contentType }));
    fs.writeFileSync(path.join(OUT, 'storage_files.json'), JSON.stringify(list, null, 2));
    summary['__storage_files'] = list.length;
    summary['__storage_bytes'] = list.reduce((a, b) => a + b.size, 0);
  } catch (e) { summary['__storage_files'] = 'ERR: ' + (e.message || e); }
  fs.writeFileSync(path.join(OUT, '_summary.json'), JSON.stringify({ exportedAt_note: 'stamped after run', totalDocs, summary }, null, 2));
  console.log('=== EXPORT SUMMARY (soni; PII/sirlar KO\'RSATILMAYDI) ===');
  console.log(JSON.stringify(summary, null, 2));
  console.log('Jami hujjat:', totalDocs);
})().catch(e => { console.error('ERR', e.stack || e.message); process.exit(1); });
