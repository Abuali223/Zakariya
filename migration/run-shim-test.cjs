// Firestore-shim tarjima sinovini avtomatik ishga tushiradi (Playwright).
// Repo ildizida: node migration/run-shim-test.cjs
// (statik serverni o'zi ochadi; NODE_PATH kerak bo'lsa Playwright uchun beriladi)
const http = require("http");
const fs = require("fs");
const path = require("path");
const ROOT = process.cwd();
const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css" };

const server = http.createServer((req, res) => {
  const p = path.join(ROOT, decodeURIComponent(req.url.split("?")[0]));
  if (!p.startsWith(ROOT) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "Content-Type": MIME[path.extname(p)] || "application/octet-stream" });
  fs.createReadStream(p).pipe(res);
});

server.listen(8799, async () => {
  let code = 2;
  try {
    const { chromium } = require("playwright");
    const b = await chromium.launch();
    const pg = await b.newPage();
    const errs = [];
    pg.on("pageerror", e => errs.push("PAGEERROR: " + e.message));
    await pg.goto("http://localhost:8799/migration/shim-selftest.html", { waitUntil: "load" });
    await pg.waitForFunction(() => document.title !== "shim-selftest", { timeout: 8000 }).catch(() => {});
    console.log(await pg.$eval("#out", el => el.textContent));
    const title = await pg.title();
    console.log("\nTITLE:", title);
    if (errs.length) console.log(errs.join("\n"));
    await b.close();
    code = title === "PASS" ? 0 : 1;
  } catch (e) { console.error("Playwright kerak (NODE_PATH):", e.message); }
  server.close(); process.exit(code);
});
