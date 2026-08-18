// =====================================================================
// switch-backend.cjs — frontend'ni Firebase <-> Supabase orasida almashtiradi.
// Butun almashtirish = bitta bazaviy URL'ni almashtirish, chunki barcha modul
// importlari `<baza>/firebase-<modul>.js` ko'rinishida (V="<baza>" yoki to'liq URL).
//
// Ishlatish (repo ildizida):
//   node migration/switch-backend.cjs supabase        # Supabase shimlarga o'tkazish
//   node migration/switch-backend.cjs firebase         # Firebase'ga qaytarish (rollback)
//   node migration/switch-backend.cjs supabase --dry   # faqat ko'rsatish, yozmaslik
//
// CUTOVER paytida ishlatiladi. Hozir (parallel-sinovгacha) ISHGA TUSHIRMANG —
// ishlab chiqarish Firebase'da qolsin. git — zaxira (o'zgarishni qaytarish oson).
// =====================================================================
const fs = require("fs"), path = require("path");

const FB_BASE = "https://www.gstatic.com/firebasejs/10.12.5";
const SB_BASE = "/sb";
const FILES = ["index.html", "admin.html", "oquv-platforma.html", "imtihon.html", "prezentatsiya.html"];

const dir = (process.argv[2] || "").toLowerCase();
const dry = process.argv.includes("--dry");
if (dir !== "supabase" && dir !== "firebase") {
  console.error("Ishlatish: node migration/switch-backend.cjs <supabase|firebase> [--dry]");
  process.exit(2);
}
const [from, to] = dir === "supabase" ? [FB_BASE, SB_BASE] : [SB_BASE, FB_BASE];

let total = 0;
for (const f of FILES) {
  const p = path.join(process.cwd(), f);
  if (!fs.existsSync(p)) { console.log(`—  ${f} (yo'q, o'tkazildi)`); continue; }
  const src = fs.readFileSync(p, "utf8");
  const n = src.split(from).length - 1;
  if (!n) { console.log(`•  ${f}: o'zgarish yo'q (allaqachon ${dir}?)`); continue; }
  const out = src.split(from).join(to);
  if (!dry) fs.writeFileSync(p, out);
  total += n;
  console.log(`${dry ? "≈" : "✔"}  ${f}: ${n} ta almashtirildi  (${from} → ${to})`);
}
console.log(`\n${dry ? "[DRY] " : ""}Jami ${total} ta o'rin ${dir.toUpperCase()} ga ${dry ? "almashtirilardi" : "almashtirildi"}.`);
if (!dry && dir === "supabase") {
  console.log("Eslatma: sb/sb-config.js to'ldirilganini va /sb/ papka deploy qilinganini tekshiring.");
}
