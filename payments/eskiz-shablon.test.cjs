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
const Module = require('module'); const { EventEmitter } = require('events');
const LIST = JSON.parse(process.env.FAKE_LIST || '[]'); const MODE = process.env.FAKE_MODE || '';
const fake = { request(opts, onRes) {
  const req = new EventEmitter(); req.write = () => {}; req.setTimeout = () => {}; req.destroy = () => {};
  req.end = () => setImmediate(() => {
    const s = new EventEmitter(); req.emit('socket', s); s.emit('secureConnect');
    const res = new EventEmitter(); res.complete = true; let st = 200, out;
    if (opts.path === '/api/auth/login' && opts.method === 'POST') out = { data: { token: 'T' } };
    else if (opts.path === '/api/user/templates' && opts.method === 'GET') {
      if (MODE === 'http500') { st = 500; out = { message: 'Server Error' }; } else out = { success: true, result: LIST };
    } else { st = 500; out = {}; process.stderr.write('UNEXPECTED ' + opts.method + ' ' + opts.path + '\\n'); }
    res.statusCode = st; onRes(res); res.emit('data', JSON.stringify(out)); res.emit('end');
  });
  return req; } };
const orig = Module._load; Module._load = function (r) { if (r === 'https') return fake; return orig.apply(this, arguments); };
`);
const cfg = (name, obj) => { const p = path.join(dir, name); fs.writeFileSync(p, JSON.stringify(obj)); return p; };
const PAY = cfg('pay.json', { sms: { eskizEmail: 'a@b', eskizPassword: 'p' } });
const CLI = path.join(__dirname, 'eskiz-shablon.cjs');
const advice = r => r.out.split('Nima qilish kerak:')[1] || '';      // faqat maslahatlar bo'limi
function run(list, args, env) {
  const e = Object.assign({}, process.env, { FAKE_LIST: JSON.stringify(list || []) }, env || {});
  if (!env || !('IQROR_CONFIG' in env)) delete e.IQROR_CONFIG;
  const r = spawnSync(process.execPath, ['--require', loader, CLI, ...(args || ['--config', PAY])], { env: e, encoding: 'utf8', timeout: 20000 });
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

// 1) Hammasi tasdiqlangan (1 so'zli naqsh) -> ism qisqartiriladi, oylar/summa bitta so'z; chiqish 0; faqat login + GET.
let r = run(ALL_OK);
ok('hammasi mos -> chiqish 0', r.code === 0 && /✅ Hamma SMS turlari/.test(r.out), r.out);
ok('«Eslatma»: ism naqshga sig\'adigan shaklda (Malika), 09.2026,10.2026, 5800000', r.out.includes("Yuboriladigan SMS: Eslatma: Malika uchun 09.2026,10.2026 oy to'lovi hali yopilmagan (qarz: 5800000 so'm)"), r.out);
ok('OTP qatori ham tekshiriladi va mos', /Ro‘yxat \/ parol kodi \(OTP\)[\s\S]*?✅ MOS — Eskiz shablon #3/.test(r.out), r.out);
ok('uzunlik ko\'rsatiladi (GSM-7, 1 SMS)', /Uzunligi: \d+ belgi, 1 SMS\n/.test(r.out), r.out);
ok('Eskiz\'ga faqat login + GET (hech narsa yuborilmaydi)', !/UNEXPECTED/.test(r.out), r.out);
ok('payments sozlamasida — remind/OTP matni auth/config.json’da boshqacha bo‘lishi mumkinligi aytiladi', /templates\.remind boshqacha/.test(r.out) && /auth\.otpTemplate boshqacha/.test(r.out), r.out);
ok('hammasi mos -> «Nima qilish kerak» yo\'q', !/Nima qilish kerak/.test(r.out), r.out);

// 2) Hali moderatsiyada (naqsh bo'sh) -> ⏳, chiqish 2; maslahat — faqat kutish (qayta yuborish EMAS)
r = run([{ id: 1, template: '', original_text: DEF_DEBT, status: 'moderation' }, { id: 2, template: '', original_text: DEF_NEW, status: 'inproccess' },
  { id: 3, template: OTP_PAT, original_text: DEF_OTP, status: 'service' }]);
ok('moderatsiyada -> ⏳ hali tasdiqlanmagan, chiqish 2', r.code === 2 && /⏳ hali tasdiqlanmagan/.test(r.out) && /— \(hali yo‘q\)/.test(r.out) && /… Moderatsiyada/.test(r.out) && /… Jarayonda/.test(r.out), r.out);
ok('moderatsiyada -> maslahat: «Servis» bo\'lishini kuting; qayta yuborish taklif qilinmaydi', /1\) Eskiz kabinetida .*«Servis»/.test(r.out) && !/HAQIQIY misol bilan yuboring/.test(r.out), r.out);

// 3) So'zma-so'z tasdiqlangan ({name} o'zgaruvchi qilinmagan)
r = run([{ id: 1, template: DEF_DEBT, original_text: DEF_DEBT, status: 'service' }, { id: 3, template: OTP_PAT, original_text: DEF_OTP, status: 'service' }]);
ok('{name} so\'zma-so\'z tasdiqlangan -> O\'ZGARUVCHI qilinmagan, qayta yuborish maslahati', r.code === 2 && /O'ZGARUVCHI qilinmagan/.test(r.out) && /HAQIQIY misol bilan qayta yuboring/.test(r.out)
  && /HAQIQIY misol bilan yuboring/.test(r.out) && r.out.includes("       Eslatma: Aliyeva Malika uchun 09.2026,10.2026 oy to'lovi hali yopilmagan (qarz: 5800000 so'm)"), r.out);
ok('qayta yuborish: misol to\'liq ism bilan, izoh (ism 1–4 so\'z...), OTP misoli YO\'Q (u mos)', /Izohda yozing: ism — 1–4 so'z/.test(advice(r)) && !/kod — 1 son/.test(advice(r)) && !/IQROR Academy tasdiqlash kodi/.test(advice(r)), r.out);

// 4) Moderator apostrofni o'zgartirgan (‘ U+2018) -> aniq belgi va tuzatish yo'li («Eslatma» — auth/config.json)
r = run([{ id: 1, template: SINGLE_DEBT.replace("to'lovi", 'to‘lovi'), original_text: DEF_DEBT, status: 'service' }]);
ok('apostrof farqi -> U+0027 va U+2018 ko\'rsatiladi, harfma-harf tuzatish', r.code === 2 && /U\+0027/.test(r.out) && /U\+2018/.test(r.out) && /harfma-harf/.test(r.out), r.out);
ok('tuzatish joyi: «Eslatma» -> auth/config.json → sms.templates.remind, debt -> shu sozlama', r.out.includes('Tuzatish: auth/config.json → sms.templates.remind') && r.out.includes(`Tuzatish: ${PAY} → sms.templates.debt`)
  && /Yuqoridagi «Tuzatish» qatorini bajaring/.test(r.out), r.out);

// 4b) Faqat OTP Eskiz'da yo'q -> qayta yuborish misoli faqat OTP, izoh «kod — 1 son»
r = run(ALL_OK.slice(0, 2));
ok('faqat OTP yo\'q -> misol faqat OTP, «kod — 1 son»', r.code === 2 && r.out.includes('       IQROR Academy tasdiqlash kodi: 123456. Hech kimga bermang.') && /kod — 1 son/.test(r.out)
  && !/ism — 1–4/.test(advice(r)) && !/Eslatma:/.test(advice(r)), r.out);

// 5) Rad etilgan
r = run([{ id: 1, template: '', original_text: DEF_DEBT, status: 'rejected' }]);
ok('rad etilgan -> RAD ETGAN, qayta yuborish', r.code === 2 && /RAD ETGAN/.test(r.out) && /✗ Rad etilgan/.test(r.out), r.out);

// 6) Eskiz'da umuman yo'q
r = run([]);
ok('matn Eskiz\'da yo\'q -> «Mening matnlarim»ga yuboring', r.code === 2 && /Eskiz'da bu matn yo'q/.test(r.out) && /0 ta/.test(r.out), r.out);

// 7) Naqsh ism uchun 1 so'z, lekin oy uchun %d va summa %d{1,3}: bo'laklar tahlili (✓/✗) — bizning bitta-so'z qiymatlar mos
r = run([{ id: 1, template: "Eslatma: %w{1,2} uchun %d oy to'lovi hali yopilmagan (qarz: %d{1,3} so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy", original_text: DEF_DEBT, status: 'service' }]);
ok('oraliqli naqsh: «Eslatma» va qarz mos (to\'liq ism)', /«Eslatma» tugmasi[\s\S]*?Yuboriladigan SMS: Eslatma: Aliyeva Malika uchun[\s\S]*?✅ MOS/.test(r.out), r.out);

// 8) Naqsh summa uchun %w (so'z) — %d emas: bizning 5800000 baribir sig'adi; oy uchun %d{2,2} (2 son) -> ✗ tahlili
r = run([{ id: 1, template: "Eslatma: %w uchun %d{2,2} oy to'lovi hali yopilmagan (qarz: %w so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy", original_text: DEF_DEBT, status: 'service' }]);
ok('mos kelmagan o\'zgaruvchi ✗ bilan ko\'rsatiladi (oy: 1 bo\'lak, naqsh 2 ta son)', r.code === 2 && /✗ \{month\} = «09\.2026,10\.2026» — 1 ta bo'lak; naqsh %d\{2,2\}: 2 ta son/.test(r.out) && /✓ \{due\} = «5800000»/.test(r.out), r.out);

// 9) auth sozlamasi: o'z remind/otp matni ishlatiladi, ogohlantirish izohi yo'q
const AUTH = cfg('auth.json', { auth: { otpTemplate: 'Iqror kod: {code}' }, sms: { eskizEmail: 'a@b', eskizPassword: 'p', templates: { remind: 'IQROR: {name} qarz {due}' } } });
r = run([{ id: 9, template: 'Iqror kod: %d', original_text: 'Iqror kod: 123456', status: 'service' }], ['--config', AUTH]);
ok('auth sozlamasi: templates.remind va auth.otpTemplate ishlatiladi', /Tizimdagi matn: IQROR: \{name\} qarz \{due\}/.test(r.out) && /Tizimdagi matn: Iqror kod: \{code\}/.test(r.out)
  && /OTP\)\n[\s\S]*?✅ MOS — Eskiz shablon #9/.test(r.out) && !/boshqacha bo‘lishi mumkin/.test(r.out), r.out);

// 10) IQROR_CONFIG muhit o'zgaruvchisi (--config o'rniga)
r = run(ALL_OK, [], { IQROR_CONFIG: PAY });
ok('IQROR_CONFIG bilan ham ishlaydi', r.code === 0 && r.out.includes('Sozlama: ' + PAY), r.out);

// 11) Sozlama xatolari -> chiqish 1
r = run(ALL_OK, ['--config', cfg('nocreds.json', { sms: {} })]);
ok('Eskiz kaliti yo\'q -> chiqish 1', r.code === 1 && /eskizEmail\/eskizPassword/.test(r.out), r.out);
r = run(ALL_OK, ['--config', path.join(dir, 'yoq.json')]);
ok('fayl yo\'q -> chiqish 1, «fayl yo‘q»', r.code === 1 && /fayl yo‘q/.test(r.out), r.out);
r = run(ALL_OK, ['--config', PAY], { FAKE_MODE: 'http500' });
ok('Eskiz ro\'yxat bermadi -> chiqish 1', r.code === 1 && /ro'yxatini bermadi/.test(r.out), r.out);

// 12) Kirish qiymatlari: --name/--months/--due
r = run(ALL_OK, ['--config', PAY, '--name', 'Valiyev Sardor', '--months', '2026-05,2026-06,2026-10', '--due', '2900000']);
ok('--name/--months/--due: oraliq oylar 05.2026-10.2026, summa 2900000', r.out.includes("Eslatma: Sardor uchun 05.2026-10.2026 oy to'lovi hali yopilmagan (qarz: 2900000 so'm)"), r.out);

try { fs.rmSync(dir, { recursive: true, force: true }); } catch (_) {}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
