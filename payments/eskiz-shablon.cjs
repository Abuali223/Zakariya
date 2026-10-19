/**
 * eskiz-shablon.cjs — Eskiz'dagi SMS matnlaringiz (shablonlar) holatini va tizim yuboradigan SMS ularga MOS kelishini
 * tekshiradi. HECH NARSA YUBORMAYDI (faqat GET /api/user/templates).
 * -------------------------------------------------------------------
 *   cd ~/iqror-repo/payments && node eskiz-shablon.cjs                  # config.json'ni o'zi topadi (pastga qarang)
 *   node eskiz-shablon.cjs --config ../auth/config.json                 # «Eslatma» tugmasi + OTP (auth serveri sozlamasi)
 *   node eskiz-shablon.cjs --name "Aliyeva Malika" --months 2026-09,2026-10 --due 5800000
 *
 * Nega kerak: Eskiz SMS'ni siz yuborgan ASL matn bilan emas, moderator tasdiqlagan NAQSH bilan solishtiradi
 *   ({name} -> %w = 1 so'z, %w{1,3} = 1–3 so'z, {due} -> %d = 1 son ...). Mos kelmasa (yoki matn hali moderatsiyada)
 *   Eskiz «Этот смс текст еще не прошел модерацию» deb rad etadi. Bu buyruq qaysi joy mos kelmayotganini aniq ko'rsatadi.
 * Tekshiruvning o'zi to'g'riligi: OTP (ro'yxat kodi) SMS'i haqiqatan yetib borayotgan bo'lsa, uning qatori ✅ bo'lishi kerak.
 * Chiqish kodi: 0 — hammasi mos; 2 — mos kelmagan SMS turi bor; 1 — sozlama/ulanish xatosi.
 */
const fs = require('fs');
const path = require('path');
const { makeEskiz, DEF_NEW, DEF_DEBT, DEF_OTP, smsName, fmtMonth } = require('./sms.cjs');
const T = require('./eskiz-template.cjs');

function arg(name, def) { const i = process.argv.indexOf('--' + name); return i > 0 && process.argv[i + 1] != null ? process.argv[i + 1] : def; }
const hasCreds = c => !!(c && c.sms && (c.sms.eskizEmail || c.sms.email || c.sms.token));
const cp = ch => 'U+' + ch.codePointAt(0).toString(16).toUpperCase().padStart(4, '0');
// Taxminiy SMS uzunligi: faqat ASCII -> GSM-7 (160 / qismi 153), aks holda UCS-2 (70 / 67) — narx shunga bog'liq.
function smsLen(s) {
  const gsm = /^[\n\r\x20-\x7e]*$/.test(s);
  const n = s.length + (gsm ? (s.match(/[\^{}\\[\]~|]/g) || []).length : 0);
  const [one, many] = gsm ? [160, 153] : [70, 67];
  return `${n} belgi, ${n <= one ? 1 : Math.ceil(n / many)} SMS${gsm ? '' : ' (UCS-2: lotin bo‘lmagan belgi bor — qimmatroq)'}`;
}
// Ikki matn bo'lagining birinchi farqi: belgilar kodi va atrofi (masalan ' U+0027 va ‘ U+2018 — apostrof farqi).
function firstDiff(a, b) {
  a = String(a); b = String(b);
  let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i++;
  const around = s => '«…' + s.slice(Math.max(0, i - 12), i + 12) + '…»';
  const chA = i < a.length ? `«${a[i]}» ${cp(a[i])}` : 'matn tugadi', chB = i < b.length ? `«${b[i]}» ${cp(b[i])}` : 'matn tugadi';
  return `bizda ${chA} ${around(a)}, naqshda ${chB} ${around(b)}`;
}

(async () => {
  // Sozlama: --config (yoki IQROR_CONFIG) berilsa — o'sha; aks holda Eskiz kaliti bor birinchi config.json.
  const explicit = arg('config', process.env.IQROR_CONFIG || '');
  const tries = explicit ? [explicit] : ['config.json', '../auth/config.json', '/opt/iqror/payments/config.json', '/opt/iqror/auth/config.json'];
  let cfgPath = null, CFG = null; const errs = [];
  for (const p of tries) {
    const full = path.resolve(__dirname, p);
    try { const c = JSON.parse(fs.readFileSync(full, 'utf8')); if (hasCreds(c) || explicit) { cfgPath = full; CFG = c; break; } errs.push(`${full}: sms.eskizEmail/eskizPassword (yoki token) yo'q`); }
    catch (e) { errs.push(`${full}: ${e.code === 'ENOENT' ? 'fayl yo‘q' : e.code === 'EACCES' ? 'o‘qishga ruxsat yo‘q (sudo bilan ishga tushiring: sudo $(which node) eskiz-shablon.cjs)' : e.message}`); }
  }
  if (!CFG) { console.error('❌ Sozlama topilmadi:\n   ' + errs.join('\n   ')); process.exit(1); }
  const SMS = CFG.sms || {};
  if (!hasCreds(CFG)) { console.error(`❌ ${cfgPath}: sms.eskizEmail/eskizPassword (yoki token) yo'q.`); process.exit(1); }
  console.log(`Sozlama: ${cfgPath}`);

  // 1) Eskiz'dagi matnlar
  let res;
  try { res = await makeEskiz(SMS).templates(); }
  catch (e) { console.error(`❌ Eskiz'ga ulanib bo'lmadi (${e.stage || ''}): ${e.message}`); process.exit(1); }
  if (!res.ok) { console.error(`❌ Eskiz shablonlar ro'yxatini bermadi: ${res.error}`); process.exit(1); }
  const list = res.list || [];
  console.log(`\nEskiz'dagi SMS matnlaringiz: ${list.length} ta`);
  list.forEach(t => {
    console.log(`\n  #${t.id}  ${T.STATUS_UZ[t.status] || t.status}`);
    console.log(`    Naqsh (Eskiz shu bilan solishtiradi): ${t.template || '— (hali yo‘q)'}`);
    if (t.original) console.log(`    Asl matn:                            ${t.original}`);
  });

  // 2) Tizim yuboradigan SMS'lar
  const name = smsName(arg('name', 'Aliyeva Malika'));
  const months = String(arg('months', '2026-09,2026-10')).split(',').map(s => s.trim()).filter(Boolean);
  const due = Number(arg('due', 5800000)) || 0;
  const tpls = SMS.templates || {};
  const last = fmtMonth(months[months.length - 1] || '');
  const isAuthCfg = !!CFG.auth;
  const ours = [
    ['«Eslatma» tugmasi (remind)' + (isAuthCfg ? '' : ' — auth/config.json’dagi templates.remind boshqacha bo‘lishi mumkin'),
      'remind', tpls.remind || tpls.debt || DEF_DEBT, { name, month: T.smsMonths(months), due: T.smsSom(due), amount: T.smsSom(due) }],
    ['Avtomatik qarz eslatmasi (debt)', 'debt', tpls.debt || DEF_DEBT, { name, month: last, due: T.smsSom(due), amount: T.smsSom(due) }],
    ['Yangi faktura xabari (new)', 'new', tpls.new || DEF_NEW, { name, month: last, due: T.smsSom(due), amount: T.smsSom(due) }],
    ['Ro‘yxat / parol kodi (OTP)' + (isAuthCfg ? '' : ' — standart matn; auth/config.json’dagi auth.otpTemplate boshqacha bo‘lishi mumkin'),
      'otp', (CFG.auth && CFG.auth.otpTemplate) || DEF_OTP, { code: '123456' }],
  ];
  // Matn qayerda sozlanadi: «Eslatma» va OTP — auth serveri (auth/config.json), avtomatik debt/new — sms-worker
  //   (payments/config.json).
  const where = key => (key === 'remind' || key === 'otp')
    ? `${isAuthCfg ? cfgPath : 'auth/config.json'} → ${key === 'otp' ? 'auth.otpTemplate' : 'sms.templates.remind'}`
    : `${isAuthCfg ? 'payments/config.json' : cfgPath} → sms.templates.${key}`;
  let bad = 0, pending = false, fixText = false;
  const resubmit = new Map();          // tizimdagi matn -> { key, text: HAQIQIY misol } (Eskiz'ga qayta yuborish uchun)
  const wantResubmit = (key, tpl, vals) => { if (!resubmit.has(tpl)) resubmit.set(tpl, { key, text: T.fillTpl(tpl, vals) }); };
  for (const [label, key, tpl, vals] of ours) {
    console.log(`\n=== ${label}\n  Tizimdagi matn: ${tpl}`);
    const cm = T.composeSms(tpl, vals, list);
    console.log(`  Yuboriladigan SMS: ${cm.message}\n  Uzunligi: ${smsLen(cm.message)}`);
    if (cm.fit) { console.log(`  ✅ MOS — Eskiz shablon #${cm.templateId} ga to'g'ri keladi.`); continue; }
    bad++;
    // Qaysi Eskiz matni «bizniki»? Asl matni bir xil yoki naqshining o'zgarmas qismlari bir xil bo'lganlar.
    const cands = list.map(t => ({ t, al: T.alignTemplate(tpl, t.template || '') }))
      .filter(x => x.al.ok || T.squash(x.t.original) === T.squash(tpl));
    if (!cands.length) {
      console.log(`  ❌ MOS EMAS: Eskiz'da bu matn yo'q — uni Eskiz kabinetida «SMS → Mening matnlarim»ga yuborib tasdiqlating (pastga qarang).`);
      wantResubmit(key, tpl, vals); continue;
    }
    console.log(`  ❌ MOS EMAS. Sababi:`);
    for (const { t, al } of cands) {
      const head = `     Eskiz #${t.id} (${T.STATUS_UZ[t.status] || t.status})`;
      const pat = String(t.template || '');
      if (t.status === 'rejected') { console.log(`${head}: ✗ moderator RAD ETGAN — matnni qayta yuboring (pastga qarang).`); wantResubmit(key, tpl, vals); continue; }
      if (!T.isApproved(t)) { console.log(`${head}: ⏳ hali tasdiqlanmagan — tasdiqlangach SMS ketadi.`); pending = true; continue; }
      if (!pat.trim()) { console.log(`${head}: naqsh bo'sh — Eskiz hali naqsh yozmagan. Biroz kuting yoki Eskiz qo'llab-quvvatlashiga yozing.`); pending = true; continue; }
      if (!/%[wd]/.test(pat) && /\{\w+\}/.test(pat)) {
        console.log(`${head}: ⚠️ naqshda {name}, {month}... O'ZGARUVCHI qilinmagan — moderator matnni so'zma-so'z tasdiqlagan, Eskiz faqat aynan «{name}» yozilgan SMSni qabul qiladi. Matnni HAQIQIY misol bilan qayta yuboring (pastga qarang).`);
        wantResubmit(key, tpl, vals); continue;
      }
      if (!al.ok) {
        console.log(`${head}: ${al.reason || 'matn qismi farq qiladi'} — ${al.at >= 0 ? firstDiff(al.ours, al.theirs) : `bizda «${tpl}», naqshda «${pat}»`}.`);
        console.log(`       Tuzatish: ${where(key)} matnining o'zgarmas qismini Eskiz NAQSHI bilan harfma-harf bir xil qiling (yoki Eskiz'ga matnni qayta yuboring).`);
        fixText = true; continue;
      }
      console.log(`${head}:`);
      for (const [k, v] of Object.entries(al.vars)) {
        const val = vals[k] != null ? String(vals[k]) : '';
        const f = T.valueFits(val, v);
        const kindTxt = v.kind === 'w' ? 'so‘z' : 'son';
        console.log(`       ${f.ok ? '✓' : '✗'} {${k}} = «${val}» — ${f.words} ta bo'lak; naqsh ${v.raw}: ${f.need} ta ${kindTxt}${f.kindOk ? '' : ` (${v.kind === 'd' ? 'son bo‘lishi kerak — harf bor' : 'noto‘g‘ri'})`}`);
        if (!f.ok) wantResubmit(key, tpl, vals);
      }
    }
  }
  console.log(`\n${bad ? `❌ ${bad} ta SMS turi Eskiz naqshiga mos emas.` : '✅ Hamma SMS turlari tasdiqlangan naqshlarga mos.'}`);
  if (bad) {
    const tips = [];
    if (pending) tips.push(`Eskiz kabinetida (my.eskiz.uz → SMS → Mening matnlarim) matn holati «Servis» (tasdiqlangan) bo'lishini kuting.`);
    if (resubmit.size) {
      const ex = [...resubmit.values()], notes = [];
      if (ex.some(e => e.key !== 'otp')) notes.push(`ism — 1–4 so'z, oy — 1 so'z (09.2026 yoki 09.2026,10.2026 yoki 05.2026-10.2026), summa — 1 son`);
      if (ex.some(e => e.key === 'otp')) notes.push('kod — 1 son (6 xonali)');
      tips.push(`Eskiz'ga matnni {name} kabi belgilar bilan EMAS, HAQIQIY misol bilan yuboring (moderator o'zgaruvchi joylarni misoldan aniqlaydi):\n`
        + ex.map(e => '       ' + e.text).join('\n')
        + `\n     Izohda yozing: ${notes.join('; ')}.${ex.some(e => e.key !== 'otp') ? ' (Naqsh ismga 1 so‘z bersa ham tizim ismni o‘zi qisqartiradi.)' : ''}`);
    }
    if (fixText) tips.push(`Yuqoridagi «Tuzatish» qatorini bajaring — SMS matnining o'zgarmas qismi Eskiz naqshi bilan harfma-harf bir xil bo'lishi kerak.`);
    tips.push(`So'ng shu buyruqni qayta ishga tushiring — hamma qator ✅ bo'lishi kerak.`);
    console.log('\nNima qilish kerak:\n' + tips.map((s, i) => `  ${i + 1}) ${s}`).join('\n'));
  }
  process.exit(bad ? 2 : 0);
})().catch(e => { console.error('Xato:', e && e.message || e); process.exit(1); });
