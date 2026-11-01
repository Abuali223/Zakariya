// =====================================================================
// sms-tpl-check.test.cjs — «📱 Xabarnomalar» → «Eskiz shabloniga mosligini tekshirish» (auth/sms-tpl-check.cjs).
//   Eskiz — soxta (stub): faqat templates(); send() chaqirilsa — test YIQILADI (hech narsa yuborilmasligi kerak).
//   node sms-tpl-check.test.cjs
// =====================================================================
const { makeFake } = require('./_fake.cjs');
const { makeSmsTplCheck } = require('./sms-tpl-check.cjs');

let pass = 0, fail = 0;
const ok = (name, cond, extra) => { if (cond) pass++; else { fail++; console.log('  ✗ FAIL:', name, extra != null ? '→ ' + JSON.stringify(extra).slice(0, 900) : ''); } };
const sec = s => console.log('\n— ' + s);

const DEBT_TPL = "Eslatma: {name} uchun {month} oy to'lovi hali yopilmagan (qarz: {due} so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";
const DEBT_PAT = "Eslatma: %w{1,3} uchun %w oy to'lovi hali yopilmagan (qarz: %d so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy";
const NEW_PAT_LITERAL = "Hurmatli ota-ona! Aliyeva Malika uchun 10.2026 oy to'lovi shakllantirildi: 2900000 so'm. Batafsil: iqroacademy.uz. IQROR Academy";
const NEW_TPL = "Hurmatli ota-ona! {name} uchun {month} oy to'lovi shakllantirildi: {amount} so'm. Batafsil: iqroacademy.uz. IQROR Academy";

function setup(o) {
  o = o || {};
  const state = {};
  const sb = makeFake(state);
  state.users = [{ id: 'uid_dir', role: 'director', status: 'active' }, { id: 'uid_ed', role: 'teacher', status: 'active' },
    { id: 'uid_fin', role: 'finance_mgr', status: 'active' }, { id: 'uid_edblk', role: 'teacher', status: 'blocked' }];
  state.notify_settings = [{ id: 'general', editors: ['uid_ed', 'uid_edblk'] }];
  let calls = 0, sends = 0;
  const list = o.list || [{ id: 11, status: 'service', template: DEBT_PAT, original: DEBT_TPL }, { id: 12, status: 'moderation', template: 'X %w', original: 'X {name}' },
    { id: 13, status: 'service', template: NEW_PAT_LITERAL, original: NEW_PAT_LITERAL }];
  const eskiz = o.noEskiz ? null : { templates: async () => { calls++; if (o.fail) return { ok: false, httpStatus: 401, error: 'Unauthorized' }; return { ok: true, list }; },
    send: async () => { sends++; throw new Error('send() chaqirilmasligi kerak'); } };
  let t = Date.parse('2026-10-16T05:00:00Z');
  const C = makeSmsTplCheck({ sb, eskiz, now: () => t, verifyJwt: async j => (j && String(j).startsWith('uid_')) ? j : null });
  return { C, state, calls: () => calls, sends: () => sends, tick: ms => { t += ms; } };
}

(async () => {
  sec('kim tekshira oladi');
  { const { C, sends } = setup();
    ok('JWT yo‘q -> rad', /Seans/.test((await C({ texts: { debt_reminder: DEBT_TPL } })).error || ''));
    ok('moliya menejeri (muharrir emas) -> rad', /Ruxsat/.test((await C({ jwt: 'uid_fin', texts: { debt_reminder: DEBT_TPL } })).error || ''));
    ok('bloklangan muharrir -> rad', /Ruxsat/.test((await C({ jwt: 'uid_edblk', texts: { debt_reminder: DEBT_TPL } })).error || ''));
    ok('Direktor -> ruxsat', (await C({ jwt: 'uid_dir', texts: { debt_reminder: DEBT_TPL } })).ok === true);
    ok('muharrir (editors ro‘yxatida) -> ruxsat', (await C({ jwt: 'uid_ed', texts: { debt_reminder: DEBT_TPL } })).ok === true);
    ok('matn yo‘q -> xato', /matn yo‘q/.test((await C({ jwt: 'uid_dir', texts: {} })).error || ''));
    ok('noma’lum tur e’tiborsiz -> matn yo‘q', /matn yo‘q/.test((await C({ jwt: 'uid_dir', texts: { otp: 'x' } })).error || ''));
    ok('600 belgidan uzun -> rad', /uzun/.test((await C({ jwt: 'uid_dir', texts: { debt_reminder: 'a'.repeat(601) } })).error || ''));
    ok('HECH NARSA yuborilmadi (send chaqirilmadi)', sends() === 0); }

  sec('moslik natijasi');
  { const { C, calls } = setup();
    const r = await C({ jwt: 'uid_dir', texts: { debt_reminder: DEBT_TPL, manual_remind: DEBT_TPL.replace('Eslatma:', 'Eslatma!'), new_invoice: NEW_TPL } });
    ok('Eskiz: 3 shablon, 2 tasdiqlangan', r.ok && r.eskiz.ok && r.eskiz.count === 3 && r.eskiz.approved === 2, r.eskiz);
    ok('qarz matni — tasdiqlangan naqshga MOS (ikkala namuna bilan), id 11', r.checks.debt_reminder.fit === true && JSON.stringify(r.checks.debt_reminder.templateIds) === '[11]', r.checks.debt_reminder);
    ok('namuna matni to‘ldirilgan', /^Eslatma: Aliyeva Malika uchun 10\.2026 oy/.test(r.checks.debt_reminder.sample), r.checks.debt_reminder.sample);
    ok('bitta belgi farq (Eslatma!) -> mos EMAS', r.checks.manual_remind.fit === false, r.checks.manual_remind);
    ok('moderator misolni so‘zma-so‘z tasdiqlagan -> faqat bitta namuna mos: «partial»', r.checks.new_invoice.fit === 'partial', r.checks.new_invoice);
    ok('bo‘laklar: GSM-7, 1 SMS (≤160)', r.checks.debt_reminder.parts.gsm === true && r.checks.debt_reminder.parts.parts === 1, r.checks.debt_reminder.parts);
    ok('shablonlar ro‘yxati: holat o‘zbekcha, moderatsiyadagi — tasdiqlanmagan', r.templates.length === 3 && r.templates[1].approved === false && /Moderatsiyada/.test(r.templates[1].statusUz), r.templates);
    await C({ jwt: 'uid_dir', texts: { debt_reminder: DEBT_TPL } });
    ok('Eskiz ro‘yxati 60 s keshlanadi (2-so‘rovda qayta chaqirilmaydi)', calls() === 1, calls()); }
  { const { C } = setup();
    const r = await C({ jwt: 'uid_dir', texts: { debt_reminder: 'Qarz: {name} {sum} {due}' } });
    ok('noma’lum o‘zgaruvchi ({sum}) ko‘rsatiladi', JSON.stringify(r.checks.debt_reminder.unknownVars) === '["sum"]', r.checks.debt_reminder); }
  { const { C } = setup();
    const r = await C({ jwt: 'uid_dir', texts: { debt_reminder: 'Hurmatli ota-ona, farzandingiz {name} uchun {month} oy to‘lovi qarzi {due} so‘m. Iltimos, to‘lovni amalga oshiring. IQROR Academy' } });
    ok('o‘zbekcha ‘ (U+2018) -> UCS-2: 157 belgi = 3 SMS (67 dan)', r.checks.debt_reminder.parts.gsm === false && r.checks.debt_reminder.parts.parts === 3, r.checks.debt_reminder.parts); }
  { const { C } = setup({ list: [{ id: 21, status: 'service', template: "Eslatma: %w uchun %w oy to'lovi hali yopilmagan (qarz: %d so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy" }] });
    const r = await C({ jwt: 'uid_dir', texts: { debt_reminder: DEBT_TPL } });
    ok('ism 1 so‘zli naqsh -> ism qisqartiriladi (nameShort), mos', r.checks.debt_reminder.fit === true && r.checks.debt_reminder.nameShort === true, r.checks.debt_reminder); }
  { const { C } = setup({ fail: true });
    const r = await C({ jwt: 'uid_dir', texts: { debt_reminder: DEBT_TPL } });
    ok('Eskiz 401 -> eskiz.ok=false (sababi), moslik noma’lum (null), bo‘laklar baribir', r.ok && r.eskiz.ok === false && /login\/parol/.test(r.eskiz.error) && r.checks.debt_reminder.fit === null && r.checks.debt_reminder.parts.parts === 1, r); }
  { const { C } = setup({ noEskiz: true });
    const r = await C({ jwt: 'uid_dir', texts: { debt_reminder: DEBT_TPL } });
    ok('Eskiz ulanmagan -> eskiz.ok=false, moslik null', r.ok && r.eskiz.ok === false && /ulanmagan/.test(r.eskiz.error) && r.checks.debt_reminder.fit === null, r); }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
