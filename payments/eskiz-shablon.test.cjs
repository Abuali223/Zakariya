// =====================================================================
// eskiz-shablon.test.cjs — diagnostika buyrug'i (eskiz-shablon.cjs) soxta Eskiz bilan: holatlar, maslahatlar, chiqish kodi.
//   node eskiz-shablon.test.cjs
//   Buyruq alohida jarayonda ishlaydi (process.exit), `https` — --require bilan soxtalashtiriladi (tarmoqsiz).
// =====================================================================
const { spawnSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { DEF_DEBT, DEF_NEW, DEF_OTP } = require('./sms.cjs');

let pass = 0, fail = 0;
const ok = (n, c, x) => { if (c) pass++; else { fail++; console.log('  ✗ FAIL:', n, x !== undefined ? String(x).slice(0, 3000) : ''); } };

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'eskiz-shablon-'));
const loader = path.join(dir, 'fake-https.cjs');
fs.writeFileSync(loader, `
const Module = require('module'); const { EventEmitter } = require('events'); const fs = require('fs'); const path = require('path');
const LIST = JSON.parse(process.env.FAKE_LIST || '[]'); const MODE = process.env.FAKE_MODE || '';
// Soxta fayl tizimi: { yo'l: matn | { code: 'EACCES' | 'ENOENT' } } — /opt/iqror kabi yo'llarni sinash uchun
const FFS = JSON.parse(process.env.FAKE_FS || '{}'); const origRead = fs.readFileSync;
fs.readFileSync = function (p, ...rest) { const k = typeof p === 'string' ? path.resolve(p) : null;
  if (k && Object.prototype.hasOwnProperty.call(FFS, k)) { const v = FFS[k];
    if (typeof v === 'string') return v; const e = new Error(v.code + ': ' + k); e.code = v.code; throw e; }
  return origRead.call(this, p, ...rest); };
const fake = { request(opts, onRes) {
  const req = new EventEmitter(); let body = ''; req.write = b => { body += String(b); }; req.setTimeout = () => {}; req.destroy = () => {};
  req.end = () => setImmediate(() => {
    const s = new EventEmitter(); req.emit('socket', s); s.emit('secureConnect');
    const res = new EventEmitter(); res.complete = true; let st = 200, out;
    if (opts.path === '/api/auth/login' && opts.method === 'POST') {
      if (process.env.FAKE_BADPASS && body.includes(process.env.FAKE_BADPASS)) { st = 401; out = { message: 'Invalid credentials' }; } else out = { data: { token: 'T' } }; }
    else if (opts.path === '/api/user/templates' && opts.method === 'GET') {
      if (MODE === 'http500') { st = 500; out = { message: 'Server Error' }; } else out = { success: true, result: LIST };
    } else { st = 500; out = {}; process.stderr.write('UNEXPECTED ' + opts.method + ' ' + opts.path + '\\n'); }
    res.statusCode = st; onRes(res); res.emit('data', JSON.stringify(out)); res.emit('end');
  });
  return req; } };
const orig = Module._load; Module._load = function (r) { if (r === 'https') return fake; return orig.apply(this, arguments); };
`);
const cfg = (name, obj) => { const p = path.join(dir, name); fs.writeFileSync(p, typeof obj === 'string' ? obj : JSON.stringify(obj)); return p; };
const PAY = cfg('pay.json', { sms: { eskizEmail: 'a@b', eskizPassword: 'p' } });
const AUTH0 = cfg('auth0.json', { auth: { hmacSecret: 'x' }, sms: { eskizEmail: 'a@b', eskizPassword: 'p' } });
const BOTH = ['--config', PAY, '--config', AUTH0];
const CLI = path.join(__dirname, 'eskiz-shablon.cjs');
const advice = r => r.out.split('Nima qilish kerak:')[1] || '';      // faqat maslahatlar bo'limi
// «=== sarlavha» dan keyingi bo'lim (keyingi === gacha)
const rowOf = (r, label) => { const i = r.out.indexOf('=== ' + label); if (i < 0) return ''; const j = r.out.indexOf('\n===', i + 4); const k = r.out.indexOf('\n❌ ', i); const l = r.out.indexOf('\n✅ Hamma', i); const m = r.out.indexOf('\n⚪ ', i);
  return r.out.slice(i, Math.min(...[j, k, l, m].filter(x => x > 0), r.out.length)); };
function run(list, args, env, opts) {
  const e = Object.assign({}, process.env, { FAKE_LIST: JSON.stringify(list || []) }, env || {});
  if (!env || !('IQROR_CONFIG' in env)) delete e.IQROR_CONFIG;
  const r = spawnSync(process.execPath, ['--require', loader, CLI, ...(args || BOTH)], { env: e, encoding: 'utf8', timeout: 20000, cwd: (opts && opts.cwd) || process.cwd() });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

const SINGLE_DEBT = "Eslatma: %w uchun %w oy to'lovi hali yopilmagan (qarz: %d so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";
const SINGLE_NEW = "Hurmatli ota-ona! %w uchun %w oy to'lovi shakllantirildi: %d so'm. Batafsil: iqroacademy.uz. IQROR Academy";
const OTP_PAT = 'IQROR Academy tasdiqlash kodi: %d. Hech kimga bermang.';
const ALL_OK = [
  { id: 1, template: SINGLE_DEBT, original_text: DEF_DEBT, status: 'service' },
  { id: 2, template: SINGLE_NEW, original_text: DEF_NEW, status: 'service' },
  { id: 3, template: OTP_PAT, original_text: DEF_OTP.replace('{code}', '123456'), status: 'service' },
];
// Buyruq maslahat qilgan HAQIQIY misollar (Eskiz'ga aynan shular yuboriladi)
const LIT_DEBT = "Eslatma: Aliyeva Malika uchun 09.2026,10.2026 oy to'lovi hali yopilmagan (qarz: 5800000 so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";
const LIT_NEW = "Hurmatli ota-ona! Aliyeva Malika uchun 10.2026 oy to'lovi shakllantirildi: 5800000 so'm. Batafsil: iqroacademy.uz. IQROR Academy";
const LIT_OTP = 'IQROR Academy tasdiqlash kodi: 123456. Hech kimga bermang.';

// 1) Hammasi tasdiqlangan (1 so'zli naqsh), ikkala sozlama -> ism qisqartiriladi, oylar/summa bitta so'z; chiqish 0
let r = run(ALL_OK);
ok('hammasi mos -> chiqish 0', r.code === 0 && /✅ Hamma SMS turlari/.test(r.out), r.out);
ok('«Eslatma»: ism naqshga sig\'adigan shaklda (Malika), 09.2026,10.2026, 5800000', r.out.includes("Yuboriladigan SMS: Eslatma: Malika uchun 09.2026,10.2026 oy to'lovi hali yopilmagan (qarz: 5800000 so'm)"), r.out);
ok('OTP qatori ham tekshiriladi va mos', /Ro‘yxat \/ parol kodi \(OTP\)[\s\S]*?✅ MOS — Eskiz shablon #3/.test(r.out), r.out);
ok('har qator 5 xil qiymatlar bilan tekshiriladi (1 so\'zli ism ham)', (r.out.match(/5 xil ism\/oy\/summa/g) || []).length === 4, r.out);
ok('uzunlik ko\'rsatiladi (GSM-7, 1 SMS)', /Uzunligi: \d+ belgi, 1 SMS\n/.test(r.out), r.out);
ok('Eskiz\'ga faqat login + GET (hech narsa yuborilmaydi)', !/UNEXPECTED/.test(r.out), r.out);
ok('ikkala sozlama ko\'rsatiladi', r.out.includes('Sozlama (auth serveri): ' + AUTH0) && r.out.includes('Sozlama (payments / sms-worker): ' + PAY), r.out);
ok('hammasi mos -> «Nima qilish kerak» yo\'q', !/Nima qilish kerak/.test(r.out), r.out);

// 1b) Faqat payments sozlamasi -> «Eslatma»/OTP TEKSHIRILMADI (✅ hisoblanmaydi), chiqish 2
r = run(ALL_OK, ['--config', PAY]);
ok('auth sozlamasi yo\'q -> «Eslatma» va OTP TEKSHIRILMADI, chiqish 2', r.code === 2 && /«Eslatma» tugmasi[\s\S]*?⚪ TEKSHIRILMADI/.test(r.out) && /OTP\)[\s\S]*?⚪ TEKSHIRILMADI/.test(r.out)
  && /2 ta SMS turi tekshirilmadi/.test(r.out) && !/✅ Hamma SMS/.test(r.out) && /Standart matn bilan sinov: ✅ mos/.test(r.out), r.out);
ok('maslahat: sozlamani --config bilan bering; qayta yuborish maslahati YO\'Q', /--config/.test(advice(r)) && !/HAQIQIY misol/.test(r.out), r.out);

// 2) Hali moderatsiyada (naqsh bo'sh) -> ⏳, chiqish 2; maslahat — faqat kutish (qayta yuborish EMAS)
r = run([{ id: 1, template: '', original_text: DEF_DEBT, status: 'moderation' }, { id: 2, template: '', original_text: DEF_NEW, status: 'inproccess' },
  { id: 3, template: OTP_PAT, original_text: DEF_OTP, status: 'service' }]);
ok('moderatsiyada -> ⏳ hali tasdiqlanmagan, chiqish 2', r.code === 2 && /⏳ hali tasdiqlanmagan/.test(r.out) && /— \(hali yo‘q\)/.test(r.out) && /… Moderatsiyada/.test(r.out) && /… Jarayonda/.test(r.out), r.out);
ok('moderatsiyada -> maslahat: «Servis» bo\'lishini kuting; qayta yuborish taklif qilinmaydi', /1\) Eskiz kabinetida .*«Servis»/.test(r.out) && !/HAQIQIY misol bilan yuboring/.test(r.out), r.out);

// 3) So'zma-so'z tasdiqlangan ({name} o'zgaruvchi qilinmagan)
r = run([{ id: 1, template: DEF_DEBT, original_text: DEF_DEBT, status: 'service' }, { id: 3, template: OTP_PAT, original_text: DEF_OTP, status: 'service' }]);
ok('{name} so\'zma-so\'z tasdiqlangan -> O\'ZGARUVCHI qilinmagan, qayta yuborish maslahati', r.code === 2 && /O'ZGARUVCHI qilinmagan/.test(r.out) && /HAQIQIY misol bilan qayta yuboring/.test(r.out)
  && /HAQIQIY misol bilan yuboring/.test(r.out) && r.out.includes('       ' + LIT_DEBT), r.out);
ok('qayta yuborish: misol to\'liq ism bilan, izoh (ism 1–4 so\'z...), OTP misoli YO\'Q (u mos)', /Izohda yozing: ism — 1–4 so'z/.test(advice(r)) && !/kod — 1 son/.test(advice(r)) && !/IQROR Academy tasdiqlash kodi/.test(advice(r)), r.out);

// 4) Moderator apostrofni o'zgartirgan (‘ U+2018) -> aniq belgi va tuzatish yo'li (har qator o'z sozlamasi fayli)
r = run([{ id: 1, template: SINGLE_DEBT.replace("to'lovi", 'to‘lovi'), original_text: DEF_DEBT, status: 'service' }]);
ok('apostrof farqi -> U+0027 va U+2018 ko\'rsatiladi, harfma-harf tuzatish', r.code === 2 && /U\+0027/.test(r.out) && /U\+2018/.test(r.out) && /harfma-harf/.test(r.out), r.out);
ok('tuzatish joyi: «Eslatma» -> auth sozlamasi fayli, debt -> payments fayli', r.out.includes(`Tuzatish: ${AUTH0} → sms.templates.remind`) && r.out.includes(`Tuzatish: ${PAY} → sms.templates.debt`)
  && /Yuqoridagi «Tuzatish» qatorini bajaring/.test(r.out), r.out);

// 4b) Faqat OTP Eskiz'da yo'q -> qayta yuborish misoli faqat OTP, izoh «kod — 1 son»
r = run(ALL_OK.slice(0, 2));
ok('faqat OTP yo\'q -> misol faqat OTP, «kod — 1 son»', r.code === 2 && r.out.includes('       ' + LIT_OTP) && /kod — 1 son/.test(r.out)
  && !/ism — 1–4/.test(advice(r)) && !/Eslatma:/.test(advice(r)), r.out);

// 5) Rad etilgan
r = run([{ id: 1, template: '', original_text: DEF_DEBT, status: 'rejected' }]);
ok('rad etilgan -> RAD ETGAN, qayta yuborish', r.code === 2 && /RAD ETGAN/.test(r.out) && /✗ Rad etilgan/.test(r.out), r.out);

// 6) Eskiz'da umuman yo'q
r = run([]);
ok('matn Eskiz\'da yo\'q -> «Mening matnlarim»ga yuboring', r.code === 2 && /Eskiz'da bu matn yo'q/.test(r.out) && /0 ta/.test(r.out), r.out);

// 7) Naqsh ism uchun 1–2 so'z, oy uchun %d va summa %d{1,3}: bizning bitta-so'z qiymatlar mos
r = run([{ id: 1, template: "Eslatma: %w{1,2} uchun %d oy to'lovi hali yopilmagan (qarz: %d{1,3} so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy", original_text: DEF_DEBT, status: 'service' }]);
ok('oraliqli naqsh: «Eslatma» va qarz mos (to\'liq ism)', /«Eslatma» tugmasi[\s\S]*?Yuboriladigan SMS: Eslatma: Aliyeva Malika uchun[\s\S]*?✅ MOS/.test(r.out), r.out);

// 8) Naqsh summa uchun %w (so'z) — %d emas: bizning 5800000 baribir sig'adi; oy uchun %d{2,2} (2 son) -> ✗ tahlili
r = run([{ id: 1, template: "Eslatma: %w uchun %d{2,2} oy to'lovi hali yopilmagan (qarz: %w so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy", original_text: DEF_DEBT, status: 'service' }]);
ok('mos kelmagan o\'zgaruvchi ✗ bilan ko\'rsatiladi (oy: 1 bo\'lak, naqsh 2 ta son)', r.code === 2 && /✗ \{month\} = «09\.2026,10\.2026» — 1 ta bo'lak; naqsh %d\{2,2\}: 2 ta son/.test(r.out) && /✓ \{due\} = «5800000»/.test(r.out), r.out);

// 9) auth sozlamasi: o'z remind/otp matni ishlatiladi
const AUTH = cfg('auth.json', { auth: { otpTemplate: 'Iqror kod: {code}' }, sms: { eskizEmail: 'a@b', eskizPassword: 'p', templates: { remind: 'IQROR: {name} qarz {due}' } } });
r = run([{ id: 9, template: 'Iqror kod: %d', original_text: 'Iqror kod: 123456', status: 'service' }], ['--config', AUTH, '--config', PAY]);
ok('auth sozlamasi: templates.remind va auth.otpTemplate ishlatiladi', /Tizimdagi matn: IQROR: \{name\} qarz \{due\}/.test(r.out) && /Tizimdagi matn: Iqror kod: \{code\}/.test(r.out)
  && /OTP\)\n[\s\S]*?✅ MOS — Eskiz shablon #9/.test(r.out), r.out);

// 10) IQROR_CONFIG muhit o'zgaruvchisi (--config o'rniga) — faqat shu fayl
r = run(ALL_OK, [], { IQROR_CONFIG: PAY });
ok('IQROR_CONFIG bilan ham ishlaydi (faqat shu fayl)', r.out.includes('Sozlama (payments / sms-worker): ' + PAY) && /Avtomatik qarz eslatmasi \(debt\)[\s\S]*?✅ MOS/.test(r.out) && /⚪ TEKSHIRILMADI/.test(r.out), r.out);

// 11) Sozlama xatolari -> chiqish 1
r = run(ALL_OK, ['--config', cfg('nocreds.json', { sms: {} })]);
ok('Eskiz kaliti yo\'q -> chiqish 1', r.code === 1 && /eskizEmail\/eskizPassword/.test(r.out), r.out);
r = run(ALL_OK, ['--config', path.join(dir, 'yoq.json')]);
ok('fayl yo\'q -> chiqish 1, «fayl yo‘q»', r.code === 1 && /fayl yo‘q/.test(r.out), r.out);
r = run(ALL_OK, BOTH, { FAKE_MODE: 'http500' });
ok('Eskiz ro\'yxat bermadi -> chiqish 1', r.code === 1 && /ro'yxatini bermadi/.test(r.out), r.out);

// 12) Kirish qiymatlari: --name/--months/--due (oraliq faqat ketma-ket oylar uchun)
r = run(ALL_OK, [...BOTH, '--name', 'Valiyev Sardor', '--months', '2026-05,2026-06,2026-07,2026-10', '--due', '2900000']);
ok('--name/--months/--due: 05.2026-07.2026,10.2026, summa 2900000', r.out.includes("Eslatma: Sardor uchun 05.2026-07.2026,10.2026 oy to'lovi hali yopilmagan (qarz: 2900000 so'm)"), r.out);

// ---- Ko'rik (R6) ----
// 13) Moderator buyruq bergan MISOLNI so'zma-so'z (o'zgaruvchisiz) tasdiqlagan -> misol o'tadi, haqiqiy SMS'lar o'tmaydi: ❌
r = run([{ id: 11, template: LIT_DEBT, original_text: LIT_DEBT, status: 'service' }, { id: 2, template: SINGLE_NEW, original_text: LIT_NEW, status: 'service' },
  { id: 3, template: LIT_OTP, original_text: LIT_OTP, status: 'service' }]);
ok('so\'zma-so\'z tasdiqlangan misol (OTP 123456) -> ✅ EMAS, chiqish 2', r.code === 2 && !/OTP\)[\s\S]*?✅ MOS/.test(rowOf(r, 'Ro‘yxat / parol kodi (OTP)'))
  && /Misol mos keladi, lekin boshqa qiymatlar bilan MOS EMAS: IQROR Academy tasdiqlash kodi: 482913/.test(r.out) && /#3 \(✓ Servis \(tasdiqlangan\)\): ⚠️ misol matn SO'ZMA-SO'Z tasdiqlangan/.test(r.out), r.out);
ok('so\'zma-so\'z «Eslatma» misoli -> ❌, qayta yuborish + izoh', /«Eslatma» tugmasi[\s\S]*?Misol mos keladi, lekin boshqa qiymatlar bilan MOS EMAS/.test(r.out) && /#11 [^\n]*SO'ZMA-SO'Z/.test(r.out)
  && /HAQIQIY misol bilan yuboring/.test(r.out) && /kod — 1 son/.test(advice(r)) && /ism — 1–4 so'z/.test(advice(r)), r.out);
ok('to\'g\'ri %w/%d naqsh (new) baribir ✅', /Yangi faktura xabari \(new\)[\s\S]*?✅ MOS — Eskiz shablon #2/.test(r.out), r.out);

// 14) HAQIQIY misol bilan yuborilgan (buyruq maslahati bo'yicha), hali moderatsiyada -> ⏳ + kutish, qayta yuborish YO'Q
r = run([{ id: 11, template: '', original_text: LIT_DEBT, status: 'moderation' }, { id: 12, template: '', original_text: LIT_NEW, status: 'moderation' },
  { id: 3, template: OTP_PAT, original_text: LIT_OTP, status: 'service' }]);
ok('moderatsiyadagi haqiqiy misol taniladi: «Eskiz\'da bu matn yo\'q» EMAS, ⏳ #11/#12', r.code === 2 && !/Eskiz'da bu matn yo'q/.test(r.out)
  && /Eskiz #11 \(… Moderatsiyada\): ⏳/.test(r.out) && /Eskiz #12 \(… Moderatsiyada\): ⏳/.test(r.out), r.out);
ok('moderatsiyadagi haqiqiy misol -> maslahat faqat kutish', /«Servis»/.test(advice(r)) && !/HAQIQIY misol bilan yuboring/.test(r.out), r.out);
// 14a) rad etilgan haqiqiy misol -> RAD ETGAN
r = run([{ id: 11, template: '', original_text: LIT_DEBT, status: 'rejected' }, { id: 2, template: SINGLE_NEW, original_text: LIT_NEW, status: 'service' }, { id: 3, template: OTP_PAT, original_text: LIT_OTP, status: 'service' }]);
ok('rad etilgan haqiqiy misol -> «RAD ETGAN» (Eskiz\'da yo\'q EMAS)', /Eskiz #11 \(✗ Rad etilgan\): ✗ moderator RAD ETGAN/.test(r.out) && !/Eskiz'da bu matn yo'q/.test(r.out) && /HAQIQIY misol bilan yuboring/.test(r.out), r.out);
// 14b) tasdiqlangan, lekin moderator apostrofni o'zgartirgan; asl matn — haqiqiy misol -> U+2018 tahlili + Tuzatish
r = run([{ id: 11, template: SINGLE_DEBT.replace("to'lovi", 'to‘lovi'), original_text: LIT_DEBT, status: 'service' }, { id: 2, template: SINGLE_NEW, original_text: LIT_NEW, status: 'service' }, { id: 3, template: OTP_PAT, original_text: LIT_OTP, status: 'service' }]);
ok('haqiqiy misol + apostrof farqi -> U+2018 va «Tuzatish» (qayta yuborish EMAS)', /U\+2018/.test(r.out) && r.out.includes(`Tuzatish: ${AUTH0} → sms.templates.remind`) && !/Eskiz'da bu matn yo'q/.test(r.out) && !/HAQIQIY misol bilan yuboring/.test(r.out), r.out);
// 14c) eski so'zma-so'z {name} tasdig'i + moderatsiyadagi haqiqiy misol -> ikkalasi ko'rsatiladi, maslahat — kutish
r = run([{ id: 1, template: DEF_DEBT, original_text: DEF_DEBT, status: 'service' }, { id: 11, template: '', original_text: LIT_DEBT, status: 'moderation' },
  { id: 2, template: SINGLE_NEW, original_text: LIT_NEW, status: 'service' }, { id: 3, template: OTP_PAT, original_text: LIT_OTP, status: 'service' }]);
ok('eski {name} tasdig\'i + yangi misol moderatsiyada -> ikkalasi, faqat kutish', /Eskiz #1 [^\n]*O'ZGARUVCHI qilinmagan/.test(r.out) && /Eskiz #11 \(… Moderatsiyada\): ⏳/.test(r.out)
  && /«Servis»/.test(advice(r)) && !/HAQIQIY misol bilan yuboring/.test(r.out), r.out);

// 14d) Moderator faqat ismni o'zgaruvchi qilgan (oy/summa misoldagidek so'zma-so'z) -> qayta yuborish, «Tuzatish» EMAS
r = run([{ id: 21, template: "Eslatma: %w{1,4} uchun 09.2026,10.2026 oy to'lovi hali yopilmagan (qarz: 5800000 so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy", original_text: LIT_DEBT, status: 'service' },
  { id: 2, template: SINGLE_NEW, original_text: LIT_NEW, status: 'service' }, { id: 3, template: OTP_PAT, original_text: LIT_OTP, status: 'service' }]);
ok('qisman o\'zgaruvchi naqsh -> «faqat 1 ta joyni o\'zgaruvchi qilgan», qayta yuborish, Tuzatish yo\'q', r.code === 2 && /#21 [^\n]*faqat 1 ta joyni o'zgaruvchi qilgan/.test(r.out)
  && /HAQIQIY misol bilan yuboring/.test(r.out) && !/Tuzatish:/.test(r.out), r.out);
// 14e) Ism uchun «%w %w» (aniq 2 so'z) -> 1 so'zli ism bilan rad etiladi: ✅ EMAS
r = run([{ id: 22, template: "Eslatma: %w %w uchun %w oy to'lovi hali yopilmagan (qarz: %d so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy", original_text: LIT_DEBT, status: 'service' },
  { id: 2, template: SINGLE_NEW, original_text: LIT_NEW, status: 'service' }, { id: 3, template: OTP_PAT, original_text: LIT_OTP, status: 'service' }]);
ok('«%w %w» ism naqshi -> 1 so\'zli ism bilan MOS EMAS, «o\'zgaruvchilar ko\'p»', r.code === 2 && /Misol mos keladi, lekin boshqa qiymatlar bilan MOS EMAS: Eslatma: Sardor uchun/.test(r.out)
  && /#22 [^\n]*naqshda o'zgaruvchilar ko'p/.test(r.out), r.out);
// 14f) Ikkala sozlamada bir xil email, lekin payments'dagi parol noto'g'ri -> u ham tekshiriladi (login xatosi, qaysi fayl)
const PAY_BAD = cfg('pay_bad.json', { sms: { eskizEmail: 'a@b', eskizPassword: 'NOTOGRI-PAROL' } });
r = run(ALL_OK, ['--config', AUTH0, '--config', PAY_BAD], { FAKE_BADPASS: 'NOTOGRI-PAROL' });
ok('bir xil email, boshqa parol -> payments ham alohida tekshiriladi (login xatosi + fayl), parol CHIQMAYDI', r.code === 1 && r.out.includes(`payments / sms-worker sozlamasi (${PAY_BAD}): Eskiz'ga ulanib bo'lmadi`)
  && !/NOTOGRI-PAROL/.test(r.out), r.out);

// 15) Har SMS turi o'z sozlamasidan: auth'dagi «Eslatma» matni (') ❌, payments'dagi debt (tuzatilgan ‘) ✅ -> chiqish 2
const FIXED = DEF_DEBT.replace("to'lovi", 'to‘lovi');
const PAY_F = cfg('pay_f.json', { sms: { eskizEmail: 'a@b', eskizPassword: 'p', templates: { debt: FIXED } } });
const AUTH_A = cfg('auth_a.json', { auth: { hmacSecret: 'x' }, sms: { eskizEmail: 'a@b', eskizPassword: 'p', templates: { remind: DEF_DEBT } } });
const LQ = [{ id: 1, template: SINGLE_DEBT.replace("to'lovi", 'to‘lovi'), original_text: LIT_DEBT, status: 'service' }, { id: 2, template: SINGLE_NEW, original_text: LIT_NEW, status: 'service' }, { id: 3, template: OTP_PAT, original_text: LIT_OTP, status: 'service' }];
r = run(LQ, ['--config', PAY_F, '--config', AUTH_A]);
ok('«Eslatma» auth sozlamasidan (❌, Tuzatish — auth fayli), debt payments\'dan (✅) -> chiqish 2', r.code === 2 && /Avtomatik qarz eslatmasi \(debt\)[\s\S]*?✅ MOS — Eskiz shablon #1/.test(r.out)
  && r.out.includes(`Tuzatish: ${AUTH_A} → sms.templates.remind`) && !r.out.includes(`Tuzatish: ${PAY_F}`) && /1 ta SMS turi Eskiz naqshiga mos emas/.test(r.out), r.out);

// 16) --config=YO'L shakli; nisbiy yo'l joriy papkaga nisbatan
r = run(ALL_OK, ['--config=pay.json', '--config', 'auth0.json'], null, { cwd: dir });
ok('--config=YO\'L va nisbiy yo\'l (joriy papka) -> ishlaydi', r.code === 0 && r.out.includes('Sozlama (payments / sms-worker): ' + PAY) && r.out.includes('Sozlama (auth serveri): ' + AUTH0), r.out);

// 17) O'qishga ruxsat yo'q -> sudo maslahati BUYRUQ ARGUMENTLARI bilan
r = run(ALL_OK, ['--config', PAY, '--name', 'Ali Valiyev'], { FAKE_FS: JSON.stringify({ [PAY]: { code: 'EACCES' } }) });
ok('EACCES -> sudo maslahati --config va boshqa argumentlar bilan', r.code === 1 && r.out.includes(`o‘qishga ruxsat yo‘q — sudo bilan ishga tushiring: sudo $(which node) `) && r.out.includes(`--config ${PAY} --name 'Ali Valiyev'`), r.out);

// 18) Buzilgan JSON: xato xabari fayl bo'lagini (parolni) chiqarmaydi
for (const bad of ['{"sms": {"eskizEmail": "a@b", "eskizPassword": "SIR-PAROL-123" ,, }}', '{"sms": {"eskizEmail": "a@b", "eskizPassword": SIR-PAROL-123}}']) {
  r = run(ALL_OK, ['--config', cfg('broken.json', bad)]);
  ok('buzilgan JSON -> chiqish 1, «JSON xato», parol bo\'lagi CHIQMAYDI', r.code === 1 && /JSON xato/.test(r.out) && !/SIR-PAROL/.test(r.out) && !/PAROL-1/.test(r.out), r.out);
}

// 19) config.example.json'dan nusxa (to'ldirilmagan) -> chiqish 1, Eskiz'ga so'rov yo'q
r = run(ALL_OK, ['--config', cfg('example.json', { sms: { eskizEmail: 'ESKIZ_EMAIL (kabinet emaili)', eskizPassword: 'ESKIZ_PAROL — MAXFIY (yoki token bilan)', token: '' } })]);
ok('namunadagi kalit -> chiqish 1, «to‘ldirilmagan»', r.code === 1 && /namunadagi qiymat/.test(r.out) && /to‘ldirilmagan/.test(r.out), r.out);

// 20) Avtomatik qidiruv: /opt/iqror/... (soxta fayl tizimi) — har tur o'z faylidan
const REPO_PAY = path.join(__dirname, 'config.json'), REPO_AUTH = path.join(__dirname, '..', 'auth', 'config.json');
const PAYC = JSON.stringify({ sms: { eskizEmail: 'a@b', eskizPassword: 'p' } }), AUTHC = JSON.stringify({ auth: { hmacSecret: 'x' }, sms: { eskizEmail: 'a@b', eskizPassword: 'p' } });
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: { code: 'ENOENT' }, '/opt/iqror/payments/config.json': PAYC, '/opt/iqror/auth/config.json': AUTHC, [REPO_AUTH]: { code: 'ENOENT' } }) });
ok('avtomatik: /opt/iqror/auth va /opt/iqror/payments topiladi -> chiqish 0', r.code === 0 && r.out.includes('Sozlama (auth serveri): /opt/iqror/auth/config.json') && r.out.includes('Sozlama (payments / sms-worker): /opt/iqror/payments/config.json'), r.out);
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAYC, '/opt/iqror/auth/config.json': { code: 'EACCES' }, [REPO_AUTH]: AUTHC }) });
ok('avtomatik: jonli auth sozlamasi o\'qilmasa — boshqasiga O\'TMAYDI, TEKSHIRILMADI + sudo', r.code === 2 && /Sozlama \(auth serveri\): — ishlatib bo‘lmadi \(\/opt\/iqror\/auth\/config\.json: o‘qishga ruxsat yo‘q — sudo/.test(r.out)
  && !r.out.includes('Sozlama (auth serveri): ' + REPO_AUTH) && /⚪ TEKSHIRILMADI/.test(r.out), r.out);
// Ko'rik (R7): sms-worker'ning o'z config.json'ida kalit to'ldirilmagan — /opt'dagi boshqa faylga O'TMAYDI (noto'g'ri ✅ yo'q)
const PAYX = JSON.stringify({ sms: { eskizEmail: 'ESKIZ_EMAIL (kabinet emaili)', eskizPassword: 'ESKIZ_PAROL — MAXFIY (yoki token bilan)' } });
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAYX, '/opt/iqror/payments/config.json': PAYC, '/opt/iqror/auth/config.json': AUTHC, [REPO_AUTH]: { code: 'ENOENT' } }) });
ok('avtomatik: o\'z config.json kaliti to\'ldirilmagan -> TEKSHIRILMADI (boshqa faylga o\'tmaydi), chiqish 2', r.code === 2
  && r.out.includes(`Sozlama (payments / sms-worker): — ishlatib bo‘lmadi (${REPO_PAY}: sms.eskizEmail`) && /bu jarayon SMS yubora olmaydi/.test(r.out)
  && !r.out.includes('Sozlama (payments / sms-worker): /opt/iqror/payments/config.json') && !/✅ Hamma SMS/.test(r.out), r.out);
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: { code: 'ENOENT' }, '/opt/iqror/payments/config.json': { code: 'ENOENT' }, '/opt/iqror/auth/config.json': { code: 'ENOENT' }, [REPO_AUTH]: { code: 'ENOENT' } }) });
ok('avtomatik: hech narsa yo\'q -> chiqish 1, «Sozlama topilmadi»', r.code === 1 && /Sozlama topilmadi/.test(r.out), r.out);

// 21) Maslahat SABABGA qarab (prod 38f6554: payments/config.json bor, lekin Eskiz kaliti yo'q — «sudo bilan qayta» yordam bermasdi)
const PAY_NOKEY = JSON.stringify({ sms: {} });
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAY_NOKEY, '/opt/iqror/payments/config.json': PAYC, '/opt/iqror/auth/config.json': AUTHC, [REPO_AUTH]: { code: 'ENOENT' } }) });
ok('payments kaliti yo\'q -> maslahat: shu faylga kalit (ixtiyoriy), sudo/--config EMAS; auth qatorlari ✅', r.code === 2
  && advice(r).includes(`${REPO_PAY} da Eskiz kaliti yo‘q yoki to‘ldirilmagan — avtomatik qarz eslatmasi va yangi faktura SMS’lari (sms-worker) yuborilmaydi`)
  && /Kerak bo‘lmasa — bu ⚪ qatorlarga e’tibor bermang/.test(advice(r)) && /§7\.4/.test(advice(r))
  && !/sudo bilan qayta/.test(advice(r)) && !/--config bilan ikkala/.test(advice(r)) && !/Tekshirilmagan SMS turlari sozlamasini/.test(advice(r))
  && /OTP\)[\s\S]*?✅ MOS/.test(r.out) && /2 ta SMS turi tekshirilmadi — sozlamasidan foydalanib bo‘lmadi/.test(r.out)
  && /Kalitni qo‘shgan bo‘lsangiz — shu buyruqni qayta ishga tushiring/.test(advice(r)) && !/So'ng shu buyruqni/.test(advice(r)), r.out);
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAYC, '/opt/iqror/auth/config.json': JSON.stringify({ auth: { hmacSecret: 'x' }, sms: {} }), [REPO_AUTH]: AUTHC }) });
ok('auth kaliti yo\'q -> maslahat: OTP/«Eslatma» YUBORILMAYDI, kalit + restart; sudo EMAS', r.code === 2
  && advice(r).includes('/opt/iqror/auth/config.json da Eskiz kaliti yo‘q yoki to‘ldirilmagan — «Eslatma» tugmasi va ro‘yxat/parol kodi (OTP) SMS’lari YUBORILMAYDI')
  && /systemctl restart iqror-auth/.test(advice(r)) && !/sudo bilan qayta/.test(advice(r)) && !r.out.includes('Sozlama (auth serveri): ' + REPO_AUTH), r.out);
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAYC, '/opt/iqror/auth/config.json': { code: 'EACCES' }, [REPO_AUTH]: AUTHC }) });
ok('auth o\'qishga ruxsat yo\'q -> maslahat: sudo bilan qayta (buyruq bilan), kalit maslahati YO\'Q', r.code === 2
  && /sozlamasini o‘qishga ruxsat yo‘q — sudo bilan qayta ishga tushiring: sudo \$\(which node\) /.test(advice(r))
  && !/--config bilan ikkala/.test(advice(r)) && !/Eskiz kaliti yo‘q/.test(advice(r)), r.out);
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAYC, '/opt/iqror/auth/config.json': { code: 'ENOENT' }, [REPO_AUTH]: { code: 'ENOENT' } }) });
ok('auth fayli topilmadi -> maslahat: --config bilan (sudo EMAS)', r.code === 2
  && /sozlamasi topilmadi yoki ishlatib bo‘lmadi .*--config <xizmat papkasi>\/auth\/config\.json \(papka: systemctl show -p WorkingDirectory --value iqror-auth\)/.test(advice(r))
  && !/sudo bilan qayta/.test(advice(r)), r.out);
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAY_NOKEY, '/opt/iqror/auth/config.json': { code: 'EACCES' }, [REPO_AUTH]: AUTHC }) });
ok('ikkalasi ishlatib bo\'lmaydi (kalit yo\'q + ruxsat yo\'q) -> chiqish 1, «foydalanib bo‘lmadi», har fayl o\'z sababi va maslahati bilan', r.code === 1
  && /❌ Sozlamadan foydalanib bo‘lmadi:/.test(r.out) && /Eskiz kaliti yo‘q yoki to‘ldirilmagan/.test(advice(r)) && /sudo bilan qayta ishga tushiring: /.test(advice(r)) && r.out.includes(`${REPO_PAY}: sms.eskizEmail/eskizPassword (yoki token) yo'q`) && /auth\/config\.json: o‘qishga ruxsat yo‘q — sudo/.test(r.out), r.out);

// 22) Ko'rik (post-deploy): buzilgan sozlama -> «SHU faylni tuzating» (--config EMAS); explicit rejimda kalitsiz fayl -> ⚪ (chiqish 1 EMAS)
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: '{"sms": {"eskizEmail": "a@b", "eskizPassword": "p",}}', '/opt/iqror/auth/config.json': AUTHC, [REPO_AUTH]: { code: 'ENOENT' } }) });
ok('payments JSON buzilgan -> maslahat: SHU faylni tuzating (+ tekshiruv buyrug\'i), --config EMAS', r.code === 2
  && advice(r).includes(`${REPO_PAY} buzilgan`) && /SHU faylni tuzating/.test(advice(r)) && /To‘lov serveri \(iqror-pay\) va sms-worker aynan shu faylni o‘qiydi/.test(advice(r))
  && /JSON\.parse\(require\("fs"\)\.readFileSync\(process\.argv\[1\],"utf8"\)\)/.test(advice(r)) && !/--config <xizmat papkasi>/.test(advice(r))
  && /Sozlama \(payments \/ sms-worker\): — ishlatib bo‘lmadi \([^)]*JSON xato/.test(r.out), r.out);
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAYC, '/opt/iqror/auth/config.json': { code: 'EISDIR' }, [REPO_AUTH]: AUTHC }) });
ok('auth sozlamasi papka (EISDIR) -> «Auth serveri aynan shu faylni o‘qiydi», boshqa faylga O\'TMAYDI', r.code === 2
  && advice(r).includes('/opt/iqror/auth/config.json buzilgan') && /Auth serveri aynan shu faylni o‘qiydi/.test(advice(r)) && !r.out.includes('Sozlama (auth serveri): ' + REPO_AUTH), r.out);
const PAY_NOKEY_F = cfg('pay_nokey.json', { sms: {} });
r = run(ALL_OK, ['--config', AUTH0, '--config', PAY_NOKEY_F]);
ok('explicit: auth OK + kalitsiz payments -> chiqish 2 (1 EMAS), auth qatorlari ✅, ixtiyoriy kalit maslahati', r.code === 2
  && /OTP\)[\s\S]*?✅ MOS/.test(r.out) && /«Eslatma» tugmasi[\s\S]*?✅ MOS/.test(r.out) && advice(r).includes(`${PAY_NOKEY_F} da Eskiz kaliti yo‘q yoki to‘ldirilmagan`)
  && /Kalitni qo‘shgan bo‘lsangiz/.test(advice(r)), r.out);
r = run(ALL_OK.slice(0, 2), [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAY_NOKEY, '/opt/iqror/auth/config.json': AUTHC, [REPO_AUTH]: { code: 'ENOENT' } }) });
ok('aralash: OTP Eskiz\'da yo\'q + payments kalitsiz -> oxirgi maslahat «⚪ qatorlaridan tashqari»', r.code === 2 && /kod — 1 son/.test(advice(r))
  && /hamma qator ✅ bo'lishi kerak \(sms-worker kaliti yozilmagan bo‘lsa — uning ⚪ qatorlaridan tashqari\)/.test(advice(r)) && !/Kalitni qo‘shgan bo‘lsangiz/.test(advice(r)), r.out);
r = run(ALL_OK, [], { FAKE_FS: JSON.stringify({ [REPO_PAY]: PAY_NOKEY, '/opt/iqror/auth/config.json': JSON.stringify({ auth: { hmacSecret: 'x' }, sms: {} }), [REPO_AUTH]: AUTHC }) });
ok('ikkalasi kalitsiz -> chiqish 1, «foydalanib bo‘lmadi» + ikkala kalit maslahati (auth — restart bilan)', r.code === 1 && /❌ Sozlamadan foydalanib bo‘lmadi:/.test(r.out)
  && advice(r).includes('/opt/iqror/auth/config.json da Eskiz kaliti yo‘q yoki to‘ldirilmagan') && advice(r).includes(`${REPO_PAY} da Eskiz kaliti yo‘q yoki to‘ldirilmagan`)
  && /&& sudo systemctl restart iqror-auth/.test(advice(r)) && !/\(aniq fayl: --config/.test(r.out), r.out);

try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) {}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
