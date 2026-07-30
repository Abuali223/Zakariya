const { initializeApp, cert } = require('firebase-admin/app');
const { getStorage } = require('firebase-admin/storage');
const fs = require('fs'), path = require('path');
initializeApp({ credential: cert(require(process.env.SA)), storageBucket: 'alilazer-cd582.firebasestorage.app' });
const OUT = path.join(process.env.OUT, 'storage');
(async () => {
  const [files] = await getStorage().bucket().getFiles();
  let n = 0, bytes = 0;
  for (const f of files) {
    if (f.name.endsWith('/')) continue;
    const dest = path.join(OUT, f.name);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    await f.download({ destination: dest });
    n++; bytes += Number(f.metadata.size) || 0;
  }
  console.log('Yuklandi:', n, 'fayl,', (bytes/1024/1024).toFixed(1), 'MB');
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
