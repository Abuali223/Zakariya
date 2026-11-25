'use strict';
/**
 * sheets/index.cjs — «iqror-sheets» xizmati: platforma ma'lumotlarini Google Sheets jadvaliga avtomatik yozadi (egasi 2026-11-25).
 * -------------------------------------------------------------------
 * Nima yoziladi (varaqlar): O'quvchilar, Oylik to'lovlar (hisob-fakturalar), To'lovlar, Qarzdorlik, Oylik hisobot, Xarajatlar,
 *   Qaytarishlar. Faqat platforma -> jadval (jadvaldagi o'zgarish platformaga qaytmaydi).
 * Qachon: har o'zgarish bazada navbatga tushadi (trigger), xizmat navbatni har `pollMs` (standart 2 s) tekshiradi — o'zgarish
 *   odatda bir necha soniyada jadvalda. Ishga tushganda, har kecha 03:00 dan keyin va har xatodan keyin — hammasi to'liq qayta
 *   yoziladi.
 * Xato (internet, Google kvotasi, ruxsat): navbat o'chirilmaydi — tuzalgach o'zi yetkaziladi. Holat bazada (app.sheets_state:
 *   oxirgi muvaffaqiyat / xato) va jurnalda (journalctl -u iqror-sheets).
 * Bir vaqtda faqat BITTA nusxa yozadi (bazadagi ijara). Xizmat to'xtaganda ijarani bo'shatadi — qayta ishga tushgani kutmaydi.
 * Sozlash: sheets/config.json (namuna — config.example.json), Google kaliti — sheets/google-key.json; batafsil — sheets/README.md.
 *   Xizmat o'chiq (sheets.enabled=false) yoki sozlanmagan bo'lsa — jim kutadi (systemd uni qayta-qayta ishga tushirmaydi).
 *
 * Ishga tushirish:  node sheets/index.cjs           (systemd: migration/deploy/iqror-sheets.service)
 *                   node sheets/index.cjs --once    (bitta to'liq yozish va chiqish — sozlashni tekshirish uchun;
 *                                                    xizmat ishlab turgan bo'lsa — rad etadi, avval: sudo systemctl stop iqror-sheets)
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { makeGoogle, explain } = require('./google.cjs');
const { makeSync } = require('./sync.cjs');

const log = (...a) => console.log(new Date().toISOString(), ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ONCE = process.argv.includes('--once');
const INSTANCE = `${os.hostname()}:${ONCE ? 'once:' + process.pid : 'service'}`;   // xizmat nomi barqaror — qayta ishga tushganda ijarasini darhol oladi
const cfgFile = () => path.resolve(__dirname, process.env.IQROR_CONFIG || 'config.json');   // nisbiy — sheets/ ga nisbatan

/** config.json ni o'qiydi. off — xizmat ishlamaydigan sabab (matn), aks holda { cfg, s, key, fromMonth }. */
function readConfig() {
  const cfg = JSON.parse(fs.readFileSync(cfgFile(), 'utf8'));
  const s = cfg.sheets || {};
  if (s.enabled === false) return { cfg, s, off: 'sheets.enabled = false' };
  if (!s.spreadsheetId || /PASTE|JADVAL_ID/i.test(String(s.spreadsheetId))) return { cfg, s, off: 'sheets.spreadsheetId yozilmagan' };
  if (!cfg.supabaseUrl || !cfg.serviceRoleKey || /PASTE/i.test(String(cfg.serviceRoleKey))) return { cfg, s, off: 'supabaseUrl / serviceRoleKey yozilmagan' };
  let fromMonth = null;
  if (s.fromMonth !== undefined && s.fromMonth !== null && s.fromMonth !== '') {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(String(s.fromMonth))) return { cfg, s, off: `sheets.fromMonth «YYYY-MM» bo'lishi kerak (hozir: ${s.fromMonth})` };
    fromMonth = String(s.fromMonth);
  }
  const keyFile = path.resolve(__dirname, s.keyFile || 'google-key.json');
  let key;
  try { key = JSON.parse(fs.readFileSync(keyFile, 'utf8')); } catch (e) { return { cfg, s, off: `Google kaliti o'qilmadi (${keyFile}): ${e.code || e.message}` }; }
  if (!key || !key.client_email || !key.private_key) return { cfg, s, off: `Google kaliti noto'g'ri (${keyFile}): client_email / private_key yo'q` };
  return { cfg, s, key, fromMonth };
}

let stopping = false, current = null;
async function stop(sig) {
  if (stopping) return;
  stopping = true;
  log(`${sig} — xizmat to'xtamoqda, ijara bo'shatilmoqda`);
  try { if (current) await Promise.race([current.release(), sleep(3000)]); } catch (_) { /* jim */ }
  process.exit(0);
}

async function main() {
  process.on('unhandledRejection', (e) => log('⚠️ kutilmagan xato:', (e && e.message) || e));
  process.on('SIGTERM', () => stop('SIGTERM'));
  process.on('SIGINT', () => stop('SIGINT'));
  let warned = '';
  while (!stopping) {
    let c;
    try { c = readConfig(); } catch (e) { c = { off: `config.json o'qilmadi: ${e.code || e.message}` }; }
    if (c.off) {
      if (c.off !== warned) { log(`Google Sheets sinxronlash ishlamayapti: ${c.off} (sheets/README.md). Har 5 daqiqada qayta tekshiriladi.`); warned = c.off; }
      if (ONCE) process.exit(2);
      await sleep(300000); continue;
    }
    warned = '';
    const rc = await run(c).catch((e) => { log('⚠️ xizmat aylanishi to\'xtadi:', explain(e)); return ONCE ? 1 : 0; });
    if (ONCE) process.exit(rc || 0);
    if (!stopping) await sleep(30000);    // qayta ulanish (sozlama o'zgargan bo'lsa ham qayta o'qiladi)
  }
}

/** Bitta ulanish davri: config.json o'zgarguncha yoki to'xtaguncha. Qaytaradi: --once uchun chiqish kodi. */
async function run({ cfg, s, key, fromMonth }) {
  const { db } = require('../server/backend.js')({ ...cfg, backend: 'supabase', __dir: __dirname });
  const rpc = (name, args) => db._sb.rpc(name, args);
  const google = makeGoogle({ key, perMinute: s.perMinute, apiBase: s.apiBase, tokenUrl: s.tokenUrl });
  const sync = makeSync({ rpc, google, spreadsheetId: s.spreadsheetId, instance: INSTANCE, fromMonth, log });
  current = { release: () => rpc('sheets_release', { p_instance: INSTANCE }) };
  const pollMs = Math.max(1000, Number(s.pollMs) || 2000);
  const beatMs = 60000;
  let lastBeat = 0, fails = 0, waiting = false, beatErr = '';
  const cfgStamp = () => { try { return fs.statSync(cfgFile()).mtimeMs; } catch (_) { return 0; } };
  const stamp0 = cfgStamp();
  log(`Google Sheets sinxronlash: jadval ${String(s.spreadsheetId).slice(0, 6)}…, xizmat hisobi ${key.client_email}, nusxa ${INSTANCE}${fromMonth ? `, ${fromMonth} dan` : ''}`);
  try {
    while (!stopping) {
      const t0 = Date.now();
      if (t0 - lastBeat >= beatMs || waiting) {
        // Yurak urishi + ijara: triggerlar navbatga faqat xizmat oxirgi 15 daqiqada tirik bo'lsa yozadi (xizmat yo'q — navbat
        //   o'smaydi; qaytganda baribir to'liq qayta yoziladi). Boshqa nusxa ijarada bo'lsa — kutamiz (--once — rad etadi).
        const { data, error } = await rpc('sheets_beat', { p_instance: INSTANCE, p_info: sync.status() });
        if (error) {
          const m = String(error.message || error.code || JSON.stringify(error));
          // Bir xil xato qayta-qayta yozilmaydi; funksiya yo'q — baza yangilanmagan (migration/sheets-sync.sql deploy bilan qo'llanadi).
          if (m !== beatErr) log(`⚠️ sheets_beat: ${m}${/sheets_beat|PGRST202|Could not find the function/i.test(m) ? ' — bazada sheets-sync.sql yo\'q: avval deploy (bash ~/iqror-repo/deploy.sh)' : ''}`);
          beatErr = m;
          if (ONCE) return 1;
          await sleep(30000); continue;
        }
        beatErr = '';
        if (!data || !data.ok) {
          const who = (data && data.holder) || '?';
          if (ONCE) { log(`❌ Boshqa nusxa ishlayapti (${who}). Avval xizmatni to'xtating: sudo systemctl stop iqror-sheets`); return 3; }
          if (!waiting) log(`boshqa nusxa ishlayapti (${who}) — ijara bo'shashini kutyapman`);
          waiting = true; await sleep(30000); continue;
        }
        if (waiting) log('ijara olindi — sinxronlash boshlandi');
        waiting = false; lastBeat = t0;
      }
      try {
        const n = await sync.cycle();
        if (n && fails) log(`tiklandi: ${n} ta o'zgarish yozildi`);
        fails = 0;
        if (ONCE) { await rpc('sheets_beat', { p_instance: INSTANCE, p_info: sync.status() }); log('bir martalik to\'liq yozish tugadi'); return 0; }
      } catch (e) {
        fails += 1;
        const msg = explain(e);
        sync.failed(msg);
        if (fails === 1 || fails % 30 === 0) log(`⚠️ yozilmadi (${fails}-urinish): ${msg}`);
        await Promise.resolve(rpc('sheets_beat', { p_instance: INSTANCE, p_info: sync.status() })).catch(() => {});
        lastBeat = Date.now();
        if (ONCE) { log(`❌ ${msg}`); return 1; }
        await sleep(Math.min(300000, 5000 * 2 ** Math.min(fails - 1, 6)));
        continue;
      }
      if (cfgStamp() !== stamp0) { log('config.json o\'zgardi — qayta o\'qilmoqda'); return 0; }
      const dt = Date.now() - t0;
      if (dt < pollMs) await sleep(pollMs - dt);
    }
    return 0;
  } finally {
    if (ONCE || !stopping) await Promise.race([Promise.resolve(current.release()).catch(() => {}), sleep(3000)]);
    current = null;
  }
}

if (require.main === module) main();
module.exports = { readConfig, INSTANCE };
