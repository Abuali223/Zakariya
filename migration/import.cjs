// Zaxira (JSON) -> PostgreSQL (Supabase) import.
// Ustun nomlari Firestore maydonlari bilan bir xil bo'lgani uchun to'g'ridan-to'g'ri.
// __timestamp__ -> timestamptz; jsonb ustunlar -> JSON.stringify. Idempotent (ON CONFLICT UPDATE).
const { Client } = require('pg');
const fs = require('fs'), path = require('path');

const BACKUP = process.env.BACKUP;                       // .../backup
const DB = process.env.DATABASE_URL;                     // postgres ulanish
const SKIP = (process.env.SKIP || 'secrets').split(','); // secrets DB'ga emas (env/vault)

function convVal(v, type){
  if (v && typeof v === 'object' && v.__timestamp__) return v.__timestamp__;      // timestamptz
  if (v && typeof v === 'object' && v.__geopoint__)  return JSON.stringify(v.__geopoint__);
  if (type === 'jsonb') return v === undefined ? null : JSON.stringify(v);
  if (Array.isArray(v)) return JSON.stringify(v);                                  // massiv -> jsonb bo'lmasa ham
  return v === undefined ? null : v;
}

(async () => {
  const c = new Client({ connectionString: DB });
  await c.connect();
  // har jadval uchun ustun turlari
  const meta = {};
  const r = await c.query("select table_name, column_name, data_type from information_schema.columns where table_schema='public'");
  r.rows.forEach(x => { (meta[x.table_name] = meta[x.table_name] || {})[x.column_name] = x.data_type; });

  const dir = path.join(BACKUP, 'firestore');
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.json'));
  let totalRows = 0; const report = {};
  for (const f of files) {
    const table = f.replace('.json', '');
    if (SKIP.includes(table)) { report[table] = 'SKIP (env/vault)'; continue; }
    const cols = meta[table];
    if (!cols) { report[table] = 'JADVAL YO\'Q — o\'tkazildi'; continue; }
    const data = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    const ids = Object.keys(data);
    let n = 0;
    for (const id of ids) {
      const doc = data[id] || {};
      const useCols = ['id'], vals = [convVal(id)];
      for (const k of Object.keys(doc)) {
        if (!(k in cols)) continue;               // jadvalда yo'q maydon -> tashlab ketamiz
        if (k === 'id') continue;
        useCols.push(k); vals.push(convVal(doc[k], cols[k]));
      }
      const qCols = useCols.map(x => '"' + x + '"').join(',');
      const ph = useCols.map((_, i) => '$' + (i + 1)).join(',');
      const upd = useCols.filter(x => x !== 'id').map(x => `"${x}"=excluded."${x}"`).join(',');
      const sql = `insert into "${table}" (${qCols}) values (${ph}) on conflict (id) do update set ${upd || '"id"=excluded."id"'}`;
      await c.query(sql, vals);
      n++;
    }
    report[table] = n; totalRows += n;
  }
  await c.end();
  console.log('=== IMPORT NATIJASI (yozuv soni) ===');
  console.log(JSON.stringify(report, null, 2));
  console.log('Jami import qilingan:', totalRows);
})().catch(e => { console.error('ERR', e.stack || e.message); process.exit(1); });
