/**
 * eskiz-shablon.cjs — Eskiz'dagi SMS matnlaringiz (shablonlar) holatini va tizim yuboradigan SMS ularga MOS kelishini
 * tekshiradi. HECH NARSA YUBORMAYDI (faqat GET /api/user/templates).
 * -------------------------------------------------------------------
 *   cd ~/iqror-repo/payments && node eskiz-shablon.cjs     # ikkala sozlamani o'zi topadi (pastga qarang)
 *   sudo $(which node) eskiz-shablon.cjs                   # /opt/iqror/auth/config.json faqat egasiga o'qilsa
 *   node eskiz-shablon.cjs --config /opt/iqror/auth/config.json --config ./config.json   # aniq fayllar (faqat shular)
 *   node eskiz-shablon.cjs --name "Aliyeva Malika" --months 2026-09,2026-10 --due 5800000
 *
 * Har SMS turi o'zini YUBORADIGAN jarayonning sozlamasidan olinadi:
 *   «Eslatma» tugmasi va OTP — auth serveri: /opt/iqror/auth/config.json (yoki ../auth/config.json);
 *   avtomatik qarz (debt) va yangi faktura (new) — sms-worker: ./config.json (yoki /opt/iqror/payments/config.json).
 *   --config (yoki IQROR_CONFIG) berilsa — faqat o'sha fayl(lar); qaysi turdagi sozlama ekani ichidan aniqlanadi
 *   («auth» bo'limi bor — auth serveri). Sozlamasi o'qilmagan SMS turi «TEKSHIRILMADI» deb chiqadi (✅ hisoblanmaydi).
 *
 * Nega kerak: Eskiz SMS'ni siz yuborgan ASL matn bilan emas, moderator tasdiqlagan NAQSH bilan solishtiradi
 *   ({name} -> %w = 1 so'z, %w{1,3} = 1–3 so'z, {due} -> %d = 1 son ...). Mos kelmasa (yoki matn hali moderatsiyada)
 *   Eskiz «Этот смс текст еще не прошел модерацию» deb rad etadi. Bu buyruq qaysi joy mos kelmayotganini aniq ko'rsatadi.
 * Tekshiruv bir nechta HAR XIL ism/oy/summa/kod bilan qilinadi: moderator misol matnni so'zma-so'z (o'zgaruvchisiz)
 *   tasdiqlagan bo'lsa ham ushlanadi (aks holda faqat o'sha bitta misol o'tadi, haqiqiy SMS'lar rad etiladi).
 * Tekshiruvning o'zi to'g'riligi: OTP (ro'yxat kodi) SMS'i haqiqatan yetib borayotgan bo'lsa, uning qatori ✅ bo'lishi kerak.
 * Chiqish kodi: 0 — hammasi mos; 2 — mos kelmagan yoki tekshirilmagan SMS turi bor; 1 — sozlama/ulanish xatosi.
 */
const fs = require('fs');
const path = require('path');
const { makeEskiz, DEF_NEW, DEF_DEBT, DEF_OTP, smsName, fmtMonth } = require('./sms.cjs');
const T = require('./eskiz-template.cjs');

const ARGV = process.argv.slice(2);
// --nom QIYMAT va --nom=QIYMAT (bir necha marta berilishi mumkin)
function argAll(name) {
  const out = [];
  for (let i = 0; i < ARGV.length; i++) {
    if (ARGV[i] === '--' + name) { if (ARGV[i + 1] != null) out.push(ARGV[++i]); }
    else if (ARGV[i].startsWith('--' + name + '=')) out.push(ARGV[i].slice(name.length + 3));
  }
  return out;
}
const arg = (name, def) => { const v = argAll(name); return v.length ? v[v.length - 1] : def; };
const shq = s => /^[\w@%+=:,./-]+$/.test(s) ? s : `'${String(s).replace(/'/g, `'\\''`)}'`;
const RERUN = ['sudo', '$(which node)', shq(path.relative(process.cwd(), __filename) || __filename), ...ARGV.map(shq)].join(' ');
const cp = ch => 'U+' + ch.codePointAt(0).toString(16).toUpperCase().padStart(4, '0');
// Taxminiy SMS uzunligi: faqat ASCII -> GSM-7 (160 / qismi 153), aks holda UCS-2 (70 / 67) — narx shunga bog'liq.
function smsParts(s) {
  const gsm = /^[\n\r\x20-\x7e]*$/.test(s);
  const n = s.length + (gsm ? (s.match(/[\^{}\\[\]~|]/g) || []).length : 0);
  const [one, many] = gsm ? [160, 153] : [70, 67];
  return { n, parts: n <= one ? 1 : Math.ceil(n / many), gsm };
}
const smsLen = s => { const p = smsParts(s); return `${p.n} belgi, ${p.parts} SMS${p.gsm ? '' : ' (UCS-2: lotin bo‘lmagan belgi bor — qimmatroq)'}`; };
// Ikki matn bo'lagining birinchi farqi: belgilar kodi va atrofi (masalan ' U+0027 va ‘ U+2018 — apostrof farqi).
function firstDiff(a, b) {
  a = String(a); b = String(b);
  let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i++;
  const around = s => '«…' + s.slice(Math.max(0, i - 12), i + 12) + '…»';
  const chA = i < a.length ? `«${a[i]}» ${cp(a[i])}` : 'matn tugadi', chB = i < b.length ? `«${b[i]}» ${cp(b[i])}` : 'matn tugadi';
  return `bizda ${chA} ${around(a)}, naqshda ${chB} ${around(b)}`;
}

// ---- Sozlamalar ----
// Eskiz kaliti: token yoki email+parol; config.example.json'dagi to'ldirilmagan qiymatlar hisoblanmaydi.
const PLACEHOLDER = /ESKIZ_(EMAIL|PAROL|TOKEN)|PASTE_/;
function credsProblem(c) {
  const s = (c && c.sms) || {};
  const email = String(s.eskizEmail || s.email || '').trim(), pass = String(s.eskizPassword || s.password || '').trim(), tok = String(s.token || '').trim();
  if (!email && tok) return PLACEHOLDER.test(tok) ? 'sms.token — namunadagi qiymat (to‘ldirilmagan)' : null;
  if (!email && !pass) return "sms.eskizEmail/eskizPassword (yoki token) yo'q";
  if (PLACEHOLDER.test(email) || !/@/.test(email)) return 'sms.eskizEmail — namunadagi qiymat yoki email emas (to‘ldirilmagan)';
  if (!pass || PLACEHOLDER.test(pass)) return "sms.eskizPassword — bo'sh yoki namunadagi qiymat (to‘ldirilmagan)";
  return null;
}
// Fayl matni (va JSON xato xabari — unda fayl bo'lagi, masalan parol, bo'lishi mumkin) HECH QACHON chiqarilmaydi.
function readCfg(full) {
  try { return { cfg: JSON.parse(fs.readFileSync(full, 'utf8')) }; }
  catch (e) {
    if (e && e.code === 'ENOENT') return { err: 'fayl yo‘q', missing: true };
    if (e && (e.code === 'EACCES' || e.code === 'EPERM')) return { err: `o‘qishga ruxsat yo‘q — sudo bilan ishga tushiring: ${RERUN}`, perm: true };
    if (e && e.code === 'EISDIR') return { err: 'bu papka, fayl emas', broken: true };
    if (e instanceof SyntaxError) { const lc = /line (\d+) column (\d+)/.exec(e.message);
      return { err: `JSON xato — fayl buzilgan${lc ? ` (${lc[1]}-qator, ${lc[2]}-ustun atrofi)` : ''}; tahrirlagichda tekshiring`, broken: true }; }
    return { err: `o‘qib bo‘lmadi (${(e && e.code) || 'xato'})` };
  }
}
const roleOf = c => (c && c.auth && typeof c.auth === 'object') ? 'auth' : 'pay';
const ROLE_UZ = { auth: 'auth serveri', pay: 'payments / sms-worker' };
const AUTO = { pay: ['config.json', '/opt/iqror/payments/config.json'], auth: ['/opt/iqror/auth/config.json', '../auth/config.json'] };

(async () => {
  const cfgs = {};                     // role -> { path, cfg }
  const notes = { pay: [], auth: [] }; // topilmagan sozlama sabablari
  // Sozlama nega ishlatilmadi (maslahat sababga qarab): 'creds' — fayl o'qildi, lekin Eskiz kaliti yo'q/to'ldirilmagan (sudo ham,
  //   --config ham yordam bermaydi — kalitni yozish kerak); 'broken' — JSON buzilgan / papka (SHU faylni tuzatish); 'perm' —
  //   o'qishga ruxsat yo'q (sudo); 'missing' / 'other' / 'notgiven' — aniq faylni --config bilan.
  const why = {}, credsAt = {}, brokenAt = {};
  const explicitArgs = argAll('config');
  const explicit = explicitArgs.length ? explicitArgs.map(p => path.resolve(process.cwd(), p))
    : process.env.IQROR_CONFIG ? [path.resolve(__dirname, process.env.IQROR_CONFIG)] : [];
  // JSON tekshiruvi — faqat OK / «JSON xato» chiqaradi (Node'ning o'z xatosi fayl qatorini — parol bilan — ekranga chiqarardi).
  const jsonCheck = f => `sudo $(which node) -e 'try{JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log("OK")}catch(e){console.log("JSON xato — fayl buzilgan (yoki o‘qilmadi)");process.exit(1)}' ${shq(f)}`;
  function roleTip(r) {
    const proc = r === 'auth' ? 'auth serveri («Eslatma» tugmasi, OTP)' : 'sms-worker (avtomatik qarz / yangi faktura SMS)';
    if (why[r] === 'creds' && r === 'auth')
      return `${credsAt.auth} da Eskiz kaliti yo‘q yoki to‘ldirilmagan — «Eslatma» tugmasi va ro‘yxat/parol kodi (OTP) SMS’lari YUBORILMAYDI. `
        + `Avval nusxa oling (sudo cp ${shq(credsAt.auth)} ${shq(credsAt.auth + '.bak')}), sms.eskizEmail va sms.eskizPassword ni yozing, so‘ng tekshirib auth serverini qayta ishga tushiring: ${jsonCheck(credsAt.auth)} && sudo systemctl restart iqror-auth`;
    if (why[r] === 'creds')
      return `${credsAt.pay} da Eskiz kaliti yo‘q yoki to‘ldirilmagan — avtomatik qarz eslatmasi va yangi faktura SMS’lari (sms-worker) yuborilmaydi. `
        + `Ular kerak bo‘lsa: avval nusxa oling (sudo cp ${shq(credsAt.pay)} ${shq(credsAt.pay + '.bak')}), sms.eskizEmail va sms.eskizPassword ni auth serveri sozlamasidagi qiymatlar bilan yozing (sms.from ham bir xil; sms.enabled false bo‘lmasin), `
        + `JSON’ni tekshiring (${jsonCheck(credsAt.pay)}) va SMS cron’ini qo‘ying (payments/README.md §7.4). Kerak bo‘lmasa — bu ⚪ qatorlarga e’tibor bermang.`;
    if (why[r] === 'broken')
      return `${brokenAt[r]} buzilgan (yuqoridagi «Sozlama» qatori) — sudo ham, --config ham yordam bermaydi: SHU faylni tuzating. `
        + `${r === 'auth' ? 'Auth serveri' : 'To‘lov serveri (iqror-pay) va sms-worker'} aynan shu faylni o‘qiydi — buzilgan holda qayta ishga tushsa ISHLAMAYDI. Tekshirish: ${jsonCheck(brokenAt[r])}`;
    if (why[r] === 'perm') return `${proc} sozlamasini o‘qishga ruxsat yo‘q — sudo bilan qayta ishga tushiring: ${RERUN}`;
    if (why[r] === 'notgiven') return `${proc} sozlamasini ham bering: yana --config /yo‘l/config.json`;
    return `${proc} sozlamasi topilmadi yoki ishlatib bo‘lmadi (yuqoridagi «Sozlama» qatori) — aniq faylni ko‘rsating: --config <xizmat papkasi>/${r === 'auth' ? 'auth' : 'payments'}/config.json`
      + ` (papka: systemctl show -p WorkingDirectory --value ${r === 'auth' ? 'iqror-auth' : 'iqror-pay'})`;
  }
  if (explicit.length) {
    for (const full of explicit) {
      const r = readCfg(full);
      if (r.err) { console.error(`❌ Sozlama: ${full}: ${r.err}`); process.exit(1); }
      const role = roleOf(r.cfg);
      const prob = credsProblem(r.cfg);
      // Kalit yo'q/to'ldirilmagan — shu jarayon ⚪ (boshqa berilgan fayl baribir tekshiriladi; hech biri yaroqsiz bo'lsa — pastda chiqish 1)
      if (prob) { notes[role].push(`${full}: ${prob} — bu jarayon SMS yubora olmaydi`); if (!cfgs[role] && !why[role]) { why[role] = 'creds'; credsAt[role] = full; } continue; }
      if (cfgs[role]) { console.log(`⚠️ ${full}: ikkinchi ${ROLE_UZ[role]} sozlamasi — e'tiborsiz (${cfgs[role].path} ishlatiladi).`); continue; }
      cfgs[role] = { path: full, cfg: r.cfg };
    }
    for (const role of ['auth', 'pay']) if (!cfgs[role] && !why[role]) { notes[role].push(`--config bilan berilmadi`); why[role] = 'notgiven'; }
  } else {
    for (const role of ['pay', 'auth']) {
      const seen = new Set();
      for (const p of AUTO[role]) {
        const full = path.resolve(__dirname, p);
        if (seen.has(full)) continue; seen.add(full);
        const r = readCfg(full);
        if (r.missing) { notes[role].push(`${full}: fayl yo‘q`); continue; }
        if (r.err) {                                                             // bor, lekin o'qilmadi — keyingisiga o'tmaymiz
          notes[role].push(`${full}: ${r.err}`); why[role] = r.perm ? 'perm' : r.broken ? 'broken' : 'other'; if (r.broken) brokenAt[role] = full; break; }
        if (roleOf(r.cfg) !== role) { notes[role].push(`${full}: ${ROLE_UZ[role]} sozlamasi emas`); why[role] = 'other'; break; }
        // Birinchi MAVJUD fayl — shu jarayonning jonli sozlamasi: kaliti yo'q/to'ldirilmagan bo'lsa ham boshqa faylga
        //   o'tilmaydi (aks holda boshqa fayl bilan noto'g'ri ✅ chiqardi — jarayon esa SMS yubora olmaydi).
        const prob = credsProblem(r.cfg);
        if (prob) { notes[role].push(`${full}: ${prob} — bu jarayon SMS yubora olmaydi`); why[role] = 'creds'; credsAt[role] = full; break; }
        cfgs[role] = { path: full, cfg: r.cfg }; break;
      }
      if (!cfgs[role] && !why[role]) why[role] = 'missing';
    }
  }
  const absent = r => why[r] === 'missing' || why[r] === 'notgiven';   // fayl umuman yo'q / berilmagan (bor, lekin yaroqsiz — emas)
  if (!cfgs.pay && !cfgs.auth) {
    console.error(`❌ ${['pay', 'auth'].every(absent) ? 'Sozlama topilmadi' : 'Sozlamadan foydalanib bo‘lmadi'}:\n   ` + [...notes.pay, ...notes.auth].join('\n   ')
      + '\n\nNima qilish kerak:\n' + ['auth', 'pay'].map((r, i) => `  ${i + 1}) ${roleTip(r)}`).join('\n'));
    process.exit(1);
  }
  for (const role of ['auth', 'pay']) console.log(`Sozlama (${ROLE_UZ[role]}): ${cfgs[role] ? cfgs[role].path : `— ${absent(role) ? 'topilmadi' : 'ishlatib bo‘lmadi'} (` + notes[role].join('; ') + ')'}`);

  // 1) Eskiz'dagi matnlar — har Eskiz hisobi uchun bir marta (odatda ikkala sozlamada bitta hisob)
  // Kalit parol/token bilan (faqat xotirada, hech qayerga chiqarilmaydi): bir xil email, lekin boshqa parol — alohida tekshiriladi
  const keyOf = c => { const s = c.sms || {}; return JSON.stringify([s.host || '', s.eskizEmail || s.email || '', s.eskizPassword || s.password || '', (s.eskizEmail || s.email) ? '' : (s.token || '')]); };
  const lists = new Map();
  for (const role of ['auth', 'pay']) {
    if (!cfgs[role]) continue;
    const k = keyOf(cfgs[role].cfg);
    if (!lists.has(k)) {
      let res;
      const src = `${ROLE_UZ[role]} sozlamasi (${cfgs[role].path})`;
      try { res = await makeEskiz(cfgs[role].cfg.sms).templates(); }
      catch (e) { console.error(`❌ ${src}: Eskiz'ga ulanib bo'lmadi (${e.stage || ''}): ${e.message}`); process.exit(1); }
      if (!res.ok) { console.error(`❌ ${src}: Eskiz shablonlar ro'yxatini bermadi: ${res.error}`); process.exit(1); }
      lists.set(k, { list: res.list || [], roles: [] });
    }
    lists.get(k).roles.push(role);
    cfgs[role].list = lists.get(k).list;
  }
  for (const { list, roles } of lists.values()) {
    console.log(`\nEskiz'dagi SMS matnlaringiz${lists.size > 1 ? ` (${roles.map(r => ROLE_UZ[r]).join(', ')} sozlamasidagi Eskiz hisobi)` : ''}: ${list.length} ta`);
    list.forEach(t => {
      console.log(`\n  #${t.id}  ${T.STATUS_UZ[t.status] || t.status}`);
      console.log(`    Naqsh (Eskiz shu bilan solishtiradi): ${t.template || '— (hali yo‘q)'}`);
      if (t.original) console.log(`    Asl matn:                            ${t.original}`);
    });
  }
  const anyList = (cfgs.auth || cfgs.pay).list;

  // 2) Tizim yuboradigan SMS'lar. Ko'rsatiladigan misol (va Eskiz'ga yuborish uchun maslahat) — 1-qiymatlar to'plami;
  //    tekshiruv — u + boshqa 3 ta to'plam (hammasi mos kelishi shart).
  const SHOW = { name: smsName(arg('name', 'Aliyeva Malika')), months: String(arg('months', '2026-09,2026-10')).split(',').map(s => s.trim()).filter(Boolean),
    due: Number(arg('due', 5800000)) || 0, code: '123456' };
  const PROBES = [SHOW,
    { name: 'Karimov Jasur', months: ['2026-10'], due: 1200000, code: '482913' },
    { name: smsName("Qobuljonov Muhammadiy Akmal o'g'li"), months: ['2026-08', '2026-09', '2026-10'], due: 14500000, code: '000731' },
    { name: 'Rahimova Dilnoza', months: ['2026-05', '2026-07'], due: 450000, code: '905518' },
    { name: 'Sardor', months: ['2026-09'], due: 300000, code: '271828' }];                 // 1 so'zli ism (bazada uchraydi)
  const lastM = p => fmtMonth(p.months[p.months.length - 1] || '');
  const tplOf = (c, k) => ((c && c.sms && c.sms.templates) || {})[k];
  const ROWS = [
    { key: 'remind', role: 'auth', label: '«Eslatma» tugmasi (remind)', field: 'sms.templates.remind',
      text: c => tplOf(c, 'remind') || tplOf(c, 'debt') || DEF_DEBT, vals: p => ({ name: p.name, month: T.smsMonths(p.months), due: T.smsSom(p.due), amount: T.smsSom(p.due) }) },
    { key: 'debt', role: 'pay', label: 'Avtomatik qarz eslatmasi (debt)', field: 'sms.templates.debt',
      text: c => tplOf(c, 'debt') || DEF_DEBT, vals: p => ({ name: p.name, month: lastM(p), due: T.smsSom(p.due), amount: T.smsSom(p.due) }) },
    { key: 'new', role: 'pay', label: 'Yangi faktura xabari (new)', field: 'sms.templates.new',
      text: c => tplOf(c, 'new') || DEF_NEW, vals: p => ({ name: p.name, month: lastM(p), due: T.smsSom(p.due), amount: T.smsSom(p.due) }) },
    { key: 'otp', role: 'auth', label: 'Ro‘yxat / parol kodi (OTP)', field: 'auth.otpTemplate',
      text: c => (c && c.auth && c.auth.otpTemplate) || DEF_OTP, vals: p => ({ code: p.code }) },
  ];
  const where = row => `${cfgs[row.role] ? cfgs[row.role].path : `${ROLE_UZ[row.role]} sozlamasi (${AUTO[row.role].map(p => path.resolve(__dirname, p)).join(' yoki ')})`} → ${row.field}`;

  // Qaysi Eskiz yozuvi «bizniki»? Naqshi bizning matnga qatorlanadi, YOKI asl matni / naqshi bizning shablonga ({...} —
  //   istalgan matn) mos keladi (masalan HAQIQIY misol bilan yuborilgan, moderatsiyadagi yozuv), YOKI boshi va oxiri bir xil.
  const normQ = s => T.squash(s).replace(/[ʻʼ‘’`´]/g, "'");
  const reEsc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  function isOurs(tpl, t) {
    const pat = String(t.template || ''), orig = String(t.original || '');
    if (pat.trim() && T.alignTemplate(tpl, pat).ok) return true;
    const parts = normQ(tpl).split(/(\{\w+\})/);
    const re = new RegExp('^' + parts.map((p, i) => i % 2 ? '.+?' : reEsc(p)).join('') + '$', 'u');
    const patText = normQ(pat.replace(/%[wd](?:\{\d+,\d+\})?/g, 'X'));
    if ((orig && re.test(normQ(orig))) || (pat.trim() && re.test(patText))) return true;
    const head = parts[0].toLowerCase(), tail = parts[parts.length - 1].toLowerCase();
    const looks = s => s && head.length >= 8 && tail.length >= 8 && s.toLowerCase().startsWith(head) && s.toLowerCase().endsWith(tail);
    return !!(looks(normQ(orig)) || (pat.trim() && looks(patText)));
  }

  let bad = 0, unverified = 0, pending = false, fixText = false;
  const resubmit = new Map();          // tizimdagi matn -> { key, text: HAQIQIY misol } (Eskiz'ga qayta yuborish uchun)
  for (const row of ROWS) {
    const C = cfgs[row.role];
    const tpl = row.text(C && C.cfg);
    const list = C ? C.list : anyList;
    console.log(`\n=== ${row.label}\n  Tizimdagi matn: ${tpl}${C ? '' : '  (standart — sozlamadan foydalanib bo‘lmadi)'}`);
    const showVals = row.vals(SHOW);
    const res = PROBES.map(p => ({ p, vals: row.vals(p), cm: T.composeSms(tpl, row.vals(p), list) }));
    const cm = res[0].cm;
    console.log(`  Yuboriladigan SMS: ${cm.message}\n  Uzunligi: ${smsLen(cm.message)}`);
    const longest = res.map(x => smsParts(x.cm.message)).reduce((a, b) => (b.parts > a.parts ? b : a));
    if (longest.parts > smsParts(cm.message).parts) console.log(`  (uzunroq ism/summa bilan: ${longest.n} belgi, ${longest.parts} SMS)`);
    const failed = res.filter(x => x.cm.fit !== true);
    if (!C) {
      unverified++;
      console.log(`  ⚪ TEKSHIRILMADI — ${ROLE_UZ[row.role]} sozlamasidan foydalanib bo‘lmadi (${notes[row.role].join('; ')}).`
        + ` Standart matn bilan sinov: ${failed.length ? '❌ mos emas (pastga qarang)' : '✅ mos'} — lekin server o‘z sozlamasidagi matnni yuboradi.`);
      if (!failed.length) continue;
    } else if (!failed.length) { console.log(`  ✅ MOS — Eskiz shablon #${cm.templateId} ga to'g'ri keladi (${PROBES.length} xil ism/oy/summa${row.key === 'otp' ? '/kod' : ''} bilan tekshirildi).`); continue; }
    else bad++;
    const fx = failed[0];                         // tahlil — birinchi mos kelmagan qiymatlar bilan
    if (fx !== res[0]) console.log(`  ❌ Misol mos keladi, lekin boshqa qiymatlar bilan MOS EMAS: ${fx.cm.message}`);
    const wantResubmit = () => { if (!resubmit.has(tpl)) resubmit.set(tpl, { key: row.key, text: T.fillTpl(tpl, showVals) }); };
    const cands = list.filter(t => isOurs(tpl, t));
    if (!cands.length) {
      console.log(`  ❌ MOS EMAS: Eskiz'da bu matn yo'q — uni Eskiz kabinetida «SMS → Mening matnlarim»ga yuborib tasdiqlating (pastga qarang).`);
      if (C) wantResubmit(); continue;
    }
    if (fx === res[0]) console.log(`  ❌ MOS EMAS. Sababi:`); else console.log(`  Sababi:`);
    let rowPending = false, rowResubmit = false, rowFix = false;
    for (const t of cands) {
      const al = T.alignTemplate(tpl, t.template || '');
      const head = `     Eskiz #${t.id} (${T.STATUS_UZ[t.status] || t.status})`;
      const pat = String(t.template || '');
      if (t.status === 'rejected') { console.log(`${head}: ✗ moderator RAD ETGAN — matnni qayta yuboring (pastga qarang).`); rowResubmit = true; continue; }
      if (!T.isApproved(t)) { console.log(`${head}: ⏳ hali tasdiqlanmagan — tasdiqlangach SMS ketadi.`); rowPending = true; continue; }
      if (!pat.trim()) { console.log(`${head}: naqsh bo'sh — Eskiz hali naqsh yozmagan. Biroz kuting yoki Eskiz qo'llab-quvvatlashiga yozing.`); rowPending = true; continue; }
      if (!/%[wd]/.test(pat) && /\{\w+\}/.test(pat)) {
        console.log(`${head}: ⚠️ naqshda {name}, {month}... O'ZGARUVCHI qilinmagan — moderator matnni so'zma-so'z tasdiqlagan, Eskiz faqat aynan «{name}» yozilgan SMSni qabul qiladi. Matnni HAQIQIY misol bilan qayta yuboring (pastga qarang).`);
        rowResubmit = true; continue;
      }
      if (!/%[wd]/.test(pat) && /\{\w+\}/.test(tpl)) {
        console.log(`${head}: ⚠️ misol matn SO'ZMA-SO'Z tasdiqlangan (naqshda %w/%d yo'q) — faqat aynan «${pat}» o'tadi, boshqa ism/summa${row.key === 'otp' ? '/kod' : ''} bilan Eskiz rad etadi. Qayta yuboring va izohda o'zgaruvchi joylarni yozing (pastga qarang).`);
        rowResubmit = true; continue;
      }
      const nOurs = (tpl.match(/\{\w+\}/g) || []).length, nTheirs = (pat.match(/%[wd](?:\{\d+,\d+\})?/g) || []).length;
      if (!al.ok && nTheirs < nOurs) {
        console.log(`${head}: ⚠️ moderator faqat ${nTheirs} ta joyni o'zgaruvchi qilgan (bizda ${nOurs} ta: ${(tpl.match(/\{\w+\}/g) || []).join(', ')}) — qolganlari misoldagi qiymat bilan so'zma-so'z qolgan, boshqa oy/summa bilan Eskiz rad etadi. Matnni qayta yuboring va izohda HAMMA o'zgaruvchi joylarni yozing (pastga qarang).`);
        rowResubmit = true; continue;
      }
      if (!al.ok && nTheirs > nOurs) {
        console.log(`${head}: ⚠️ naqshda o'zgaruvchilar ko'p (${nTheirs} ta, bizda ${nOurs} ta) — masalan ism uchun «%w %w» (aniq 2 so'z): 1 so'zli yoki 3 so'zli ism bilan Eskiz rad etadi. Qayta yuboring, izohda «ism — 1–4 so'z» deb yozing (pastga qarang).`);
        rowResubmit = true; continue;
      }
      if (!al.ok) {
        console.log(`${head}: ${al.reason || 'matn qismi farq qiladi'} — ${al.at >= 0 ? firstDiff(al.ours, al.theirs) : `bizda «${tpl}», naqshda «${pat}»`}.`);
        console.log(`       Tuzatish: ${where(row)} matnining o'zgarmas qismini Eskiz NAQSHI bilan harfma-harf bir xil qiling (yoki Eskiz'ga matnni qayta yuboring).`);
        rowFix = true; continue;
      }
      console.log(`${head}:`);
      for (const [k, v] of Object.entries(al.vars)) {
        const val = fx.vals[k] != null ? String(fx.vals[k]) : '';
        const f = T.valueFits(val, v);
        const kindTxt = v.kind === 'w' ? 'so‘z' : 'son';
        console.log(`       ${f.ok ? '✓' : '✗'} {${k}} = «${val}» — ${f.words} ta bo'lak; naqsh ${v.raw}: ${f.need} ta ${kindTxt}${f.kindOk ? '' : ` (${v.kind === 'd' ? 'son bo‘lishi kerak — harf bor' : 'noto‘g‘ri'})`}`);
        if (!f.ok) rowResubmit = true;
      }
    }
    // Sozlamasi o'qilmagan tur — maslahat faqat «sozlamani bering» (haqiqiy matn boshqacha bo'lishi mumkin).
    //   Moderatsiyada kutayotgan yozuv bor — qayta yuborish shart emas (navbatdagisini kuting).
    if (!C) continue;
    if (rowFix) fixText = true;
    if (rowPending) pending = true; else if (rowResubmit) wantResubmit();
  }
  const sum = [];
  if (bad) sum.push(`❌ ${bad} ta SMS turi Eskiz naqshiga mos emas.`);
  if (unverified) sum.push(`⚪ ${unverified} ta SMS turi tekshirilmadi — sozlamasidan foydalanib bo‘lmadi (yuqoridagi «Sozlama» qatorlari).`);
  console.log('\n' + (sum.length ? sum.join('\n') : '✅ Hamma SMS turlari tasdiqlangan naqshlarga mos.'));
  if (bad || unverified) {
    const tips = [];
    // Maslahat — sababga qarab (roleTip): kalit yo'q — kalitni yozish (sms-worker uchun ixtiyoriy); buzilgan — shu faylni tuzatish;
    //   ruxsat yo'q — sudo; topilmadi — aniq fayl --config bilan.
    const unv = ['auth', 'pay'].filter(r => !cfgs[r]);
    for (const r of unv) tips.push(roleTip(r));
    if (pending) tips.push(`Eskiz kabinetida (my.eskiz.uz → SMS → Mening matnlarim) matn holati «Servis» (tasdiqlangan) bo'lishini kuting.`);
    if (resubmit.size) {
      const ex = [...resubmit.values()], nts = [];
      if (ex.some(e => e.key !== 'otp')) nts.push(`ism — 1–4 so'z, oy — 1 so'z (09.2026 yoki 09.2026,10.2026 yoki 08.2026-10.2026), summa — 1 son`);
      if (ex.some(e => e.key === 'otp')) nts.push('kod — 1 son (6 xonali)');
      tips.push(`Eskiz'ga matnni {name} kabi belgilar bilan EMAS, HAQIQIY misol bilan yuboring (moderator o'zgaruvchi joylarni misoldan aniqlaydi):\n`
        + ex.map(e => '       ' + e.text).join('\n')
        + `\n     Izohda yozing: ${nts.join('; ')} — bu joylar har SMS'da o'zgaradi.${ex.some(e => e.key !== 'otp') ? ' (Naqsh ismga 1 so‘z bersa ham tizim ismni o‘zi qisqartiradi.)' : ''}`);
    }
    if (fixText) tips.push(`Yuqoridagi «Tuzatish» qatorini bajaring — SMS matnining o'zgarmas qismi Eskiz naqshi bilan harfma-harf bir xil bo'lishi kerak.`);
    // Ixtiyoriy sms-worker kaliti yo'q: «hamma qator ✅» faqat kalit yozilganda (aks holda uning ⚪ qatorlari — normal).
    const optPay = unv.includes('pay') && why.pay === 'creds';
    const onlyOptional = !bad && !pending && !resubmit.size && !fixText && unv.length === 1 && optPay;
    tips.push(onlyOptional ? `Kalitni qo‘shgan bo‘lsangiz — shu buyruqni qayta ishga tushiring: hamma qator ✅ bo‘lishi kerak.`
      : `So'ng shu buyruqni qayta ishga tushiring — hamma qator ✅ bo'lishi kerak${optPay ? ' (sms-worker kaliti yozilmagan bo‘lsa — uning ⚪ qatorlaridan tashqari)' : ''}.`);
    console.log('\nNima qilish kerak:\n' + tips.map((s, i) => `  ${i + 1}) ${s}`).join('\n'));
  }
  process.exit(bad || unverified ? 2 : 0);
})().catch(e => { console.error('Xato:', e && e.message || e); process.exit(1); });
