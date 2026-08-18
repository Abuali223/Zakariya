// =====================================================================
// rewrite-storage-urls.cjs — bazadagi Firebase Storage URL'larini Supabase'ga.
// import.cjs + import-auth-storage.cjs DAN KEYIN, VPS'da ishga tushiriladi.
//
// Firebase:  https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<ENC_PATH>?alt=media&token=...
// Supabase:  <SUPABASE_URL>/storage/v1/object/public/<BUCKET>/<PATH>
// Rasm yo'llari bir xil ko'chirilgani uchun faqat prefiks o'zgaradi.
//
// Muhit o'zgaruvchilari:
//   DATABASE_URL   = Supabase Postgres
//   SUPABASE_URL   = https://api.iqror.uz  (yoki http://<vps>:8000)
//   STORAGE_BUCKET = 'public'
//   DRY=1          = faqat ko'rsatish (yozmaslik)
const { Client } = require("pg");

const SB = (process.env.SUPABASE_URL || "").replace(/\/+$/, "");
const BUCKET = process.env.STORAGE_BUCKET || "public";
const DRY = process.env.DRY === "1";
if (!SB) { console.error("SUPABASE_URL kerak"); process.exit(2); }

const RE = /https?:\/\/firebasestorage\.googleapis\.com\/v0\/b\/[^/]+\/o\/([^?"'\s\\]+)(\?[^"'\s\\]*)?/g;
function rw(str) {
  return str.replace(RE, (_m, enc) => `${SB}/storage/v1/object/public/${BUCKET}/${decodeURIComponent(enc)}`);
}
function rewriteVal(v) {
  if (v == null) return v;
  if (typeof v === "string") return rw(v);
  if (typeof v === "object") { try { return JSON.parse(rw(JSON.stringify(v))); } catch { return v; } }
  return v;
}

(async () => {
  const pg = new Client({ connectionString: process.env.DATABASE_URL });
  await pg.connect();
  // matn/jsonb ustunlar (id bor jadvallarda)
  const cols = await pg.query(`
    select c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.columns idc
      on idc.table_name=c.table_name and idc.table_schema='public' and idc.column_name='id'
    where c.table_schema='public'
      and c.data_type in ('text','character varying','jsonb','json')
      and c.column_name<>'id'
    order by c.table_name`);
  const byTable = {};
  for (const r of cols.rows) (byTable[r.table_name] ||= []).push(r.column_name);

  let scanned = 0, changed = 0;
  for (const [t, columns] of Object.entries(byTable)) {
    const sel = `select id, ${columns.map(c => `"${c}"`).join(", ")} from "${t}"`;
    const rows = (await pg.query(sel)).rows;
    for (const row of rows) {
      scanned++;
      const sets = [], vals = [];
      for (const c of columns) {
        const nv = rewriteVal(row[c]);
        if (JSON.stringify(nv) !== JSON.stringify(row[c])) { vals.push(nv); sets.push(`"${c}"=$${vals.length}`); }
      }
      if (!sets.length) continue;
      changed++;
      if (DRY) { console.log(`  ${t}#${row.id}: ${sets.length} ustun`); continue; }
      vals.push(row.id);
      await pg.query(`update "${t}" set ${sets.join(", ")} where id=$${vals.length}`, vals);
    }
  }
  await pg.end();
  console.log(`\n${DRY ? "[DRY] " : ""}${scanned} qator ko'rildi, ${changed} qatorда URL yangilandi.`);
})().catch(e => { console.error("ERR", e.stack || e.message); process.exit(1); });
