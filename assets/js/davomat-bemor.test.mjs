// davomat-bemor.test.mjs — audit 2026-11-18 (G3): kasal kun puli va xodim davomati qoidalari. admin.html'dan HAQIQIY kod o'qiladi
//   (nomi bo'yicha yuqori darajadagi funksiyalar) va bazasiz (soxta getDocs / loadCol) ishga tushiriladi.
//   A2-08 — kasal kun summasi kichik (prorata) fakturadan katta: faqat to'liq sig'adigan kunlar yoziladi, qolgani keyingi fakturaga
//           (yangi qoida) / qoplanmagan qism ko'rsatiladi (eski qoida) — jim yo'qolmaydi.
//   A2-03 — kasal kun puli qo'llanmaydigan toifa (xodim farzandi / kontrakt / grant) oxirgi amaldagi fakturadan — bazadagi
//           sick_note_refund bilan bir xil tasnif (migration/test-audit-10-bemor.sql shu holatlarni bazada tekshiradi).
//   A2-06 — xodim «keldi» qoidasi: kunlik sarlavha va oylik «Ishlagan kun» qatordagi «Keldi» / ushlanma bilan bir xil;
//           2-raund: kech kelish — KELISH skanidan (chiqish / tanaffus emas birinchi skan, terminalning noma'lum holati ham) — oylik
//           ushlanma (attMetrics), «Kelgan» (saAgg) va bosh sahifa «kechikdi» (dv2StaffToday) bir xil.
//   A2-07 — «Narx jadvali»dagi kasal kun stavkasi izohi.
//   G3 (2-raund) — «Bemor kunlari» navbati: «Ketgan / muzlatilgan» ro'yxatida faqat harakat kerak bo'lganlar, toifasi chiqarilganlar —
//           bitta yig'iq izoh qatorida; «kutilayotgan yo'q» shu filtrdan keyin (haqiqiy renderSickQueue, soxta getDocs bilan).
//   node --test assets/js/davomat-bemor.test.mjs        Ma'lumotlar to'qima («Sinov …»).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
// Yuqori darajadagi e'lon (0-ustundan): function / async function / const — bir qatorli yoki tanasi surilgan ko'p qatorli.
function decl(name) {
  const L = ADM.split('\n');
  const i = L.findIndex(l => l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`) || new RegExp(`^const ${name}\\s*=`).test(l));
  if (i < 0) return '';
  const out = [L[i]];
  for (let j = i + 1; j < L.length; j++) { const l = L[j]; if (l === '' || /^\s/.test(l)) { out.push(l); continue; } if (l.startsWith('}')) out.push(l); break; }
  return out.join('\n');
}
const plain = v => JSON.parse(JSON.stringify(v == null ? null : v));   // vm kontekstidagi qiymat -> oddiy obyekt
const BASE = ['SA_WORKDAYS', 'SA_RULES', 'hmToMin', 'personRules', '_saDate', 'saWorkdaysFor', '_pausesOf', 'inPause', 'billingInterval'];

// ---- computeTuition (fakturadagi kasal kun) ----
const T = (() => {
  const ctx = vm.createContext({ tkDay: d => String(d || '').slice(0, 10) });
  const names = [...BASE, 'trackOf', 'priceKeyOf', 'priceOf', 'pmNum', 'computeTuition', 'sickExemptCat', 'SICK_EXEMPT_LBL'];
  vm.runInContext(names.map(decl).join('\n') + '\n;this.__t = { computeTuition, sickExemptCat: typeof sickExemptCat === "function" ? sickExemptCat : null };', ctx);
  return ctx.__t;
})();
const OCT = ['2026-10-01', '2026-10-02', '2026-10-05', '2026-10-06', '2026-10-07'];    // N2 — oldingi kunlar
const OCT2 = ['2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16'];  // N1 — keyingi kunlar
const REFS = { N1: OCT2, N2: OCT };
// Noyabr 2026: 1-noyabr yakshanba; 21 ish kuni. 3-noyabrda (seshanba) chiqqan — 2/21 ish kuni.
const LEFT = { _id: 'IQ-0801', studentId: 'IQ-0801', name: 'Sinov Ketgan', grade: 5, classLetter: 'A', lang: 'uz', payStatus: 'chiqdi', stopFrom: '2026-11-03' };
const FULL = { _id: 'IQ-0802', studentId: 'IQ-0802', name: 'Sinov Faol', grade: 5, classLetter: 'A', lang: 'uz', payStatus: '' };
const cx = (o = {}) => ({ month: '2026-11', priceMap: { 'uz-5': 3000000 }, flatAmount: 0, sickRate: 40000, sickNewRule: true,
  sickDaysFn: () => 10, sickRefsFn: () => REFS, ...o });
const daysOf = refs => Object.values(refs || {}).reduce((n, a) => n + a.length, 0);

test('A2-08 yangi qoida: 10 kun (400 000) > 2 kunlik faktura (285 714) — faqat to‘liq sig‘adigan 7 kun (eng oldingilari), 3 kun keyingi fakturaga', () => {
  const t = plain(T.computeTuition(LEFT, {}, cx()));
  assert.equal(t.skip, false);
  assert.equal(t.sickN, 7, 'fakturaga 7 kun');
  assert.equal(t.sickAmt, 280000, 'summa = kunlar × stavka (baza invoice_sick_guard shuni talab qiladi)');
  assert.equal(t.sickAmt, t.sickN * 40000);
  assert.equal(daysOf(t.sickRefs), t.sickN, 'sickNoteRefs kunlari soni = sickDaysApplied');
  assert.deepEqual(t.sickRefs, { N2: OCT, N1: ['2026-10-12', '2026-10-13'] }, 'ma’lumotnomalar aralash — sanalar tartibida eng oldingilari');
  assert.equal(t.sickCarry, 3, '3 kun qo‘llanmagan bo‘lib qoladi (keyingi faktura yoki «Avansga qaytarish»)');
  assert.equal(t.net, 285714 - 280000, 'stavkadan kam qoldiq to‘lanadi — u kunlar keyin to‘liq qoplanadi');
  assert.equal(t.status, 'pending');
  assert.equal(t.sickLost, 0, 'yangi qoidada hech narsa yo‘qolmaydi');
  assert.match(t.info, /7 kasal kun \(−280000; yana 3 kun keyingi fakturada\)/);
  assert.match(t.info, /2\/21 ish kuni \(prorata\)/);
});

test('A2-08 yangi qoida: faktura bir kunlik stavkadan ham kichik — birorta kun yozilmaydi, hammasi keyingi fakturaga', () => {
  const t = plain(T.computeTuition(LEFT, {}, cx({ priceMap: { 'uz-5': 400000 } })));   // 400 000 × 2/21 = 38 095 < 40 000
  assert.equal(t.sickN, 0); assert.equal(t.sickAmt, 0); assert.deepEqual(t.sickRefs, {});
  assert.equal(t.sickCarry, 10); assert.equal(t.net, 38095); assert.match(t.info, /10 kasal kun keyingi fakturada/);
});

test('A2-08: faktura yetarli bo‘lsa — avvalgidek hamma kun shu fakturada (regressiya yo‘q)', () => {
  const t = plain(T.computeTuition(FULL, {}, cx()));
  assert.equal(t.sickN, 10); assert.equal(t.sickAmt, 400000); assert.equal(daysOf(t.sickRefs), 10);
  assert.equal(t.net, 2600000); assert.equal(t.sickCarry, 0); assert.equal(t.sickLost, 0);
  assert.match(t.info, /^10 kasal kun \(−400000\)$/);
  const exact = plain(T.computeTuition(LEFT, {}, cx({ priceMap: { 'uz-5': 4200000 } })));   // 4 200 000 × 2/21 = 400 000 — aynan sig'adi
  assert.equal(exact.sickN, 10); assert.equal(exact.net, 0); assert.equal(exact.sickCarry, 0);
});

test('A2-08 eski qoida (davomatdagi «Bemor», kunlar kuzatilmaydi): faktura 0 gacha, qoplanmagan qism sickLost — xulosada ko‘rsatiladi', () => {
  const t = plain(T.computeTuition(LEFT, {}, cx({ sickNewRule: false, sickRefsFn: () => ({}) })));
  assert.equal(t.net, 0); assert.equal(t.sickN, 10); assert.equal(t.sickAmt, 400000);
  assert.equal(t.sickLost, 400000 - 285714, 'qoplanmagan qism'); assert.equal(t.sickCarry, 0);
  // generatsiya va qayta hisoblash xulosasi uni ko'rsatadi (jim emas)
  assert.match(ADM, /if\(t\.sickLost>0\) sickLostList\.push\(/);
  assert.match(ADM, /if\(t\.sickLost>0\) sickLostL\.push\(/);
  assert.match(ADM, /sickLostL\.length\?` · ⚠️ \$\{sickLostL\.length\} tasida kasal kun summasi fakturadan katta/);
});

test('A2-08: toifalar o‘zgarmagan — xodim farzandi / kontrakt / grantda kasal kun yo‘q', () => {
  for (const pv of [{ specialCategory: 'teacher_child' }, { specialCategory: 'contract', contractAmount: 2000000 }, { specialCategory: 'olympiad' }]) {
    const t = plain(T.computeTuition(FULL, pv, cx()));
    assert.equal(t.sickN, 0, pv.specialCategory); assert.equal(t.sickAmt, 0); assert.deepEqual(t.sickRefs, {});
  }
});

// ---- A2-03: kasal kun puli qo'llanmaydigan toifa (oxirgi amaldagi faktura) ----
test('A2-03 sickExemptCat: invoice_discount_guard tasnifi — xodim farzandi, kontrakt, olimpiada granti; oddiylar — bo‘sh', () => {
  assert.ok(T.sickExemptCat, 'admin.html: sickExemptCat yo‘q');
  const C = (...invs) => T.sickExemptCat(invs);
  const inv = (month, o = {}) => ({ _id: `IQ-1__${month}`, studentId: 'IQ-1', month, status: 'paid', pctApplied: 0, discountInfo: 'Chegirmasiz', isGrant: false, provider: '', bonusRef: '', ...o });
  assert.equal(C(inv('2026-10', { pctApplied: 0.5, discountInfo: 'Xodim farzandi 50%' })), 'teacher_child');
  assert.equal(C(inv('2026-10', { discountInfo: 'Kontrakt (belgilangan summa) · 2/21 ish kuni (prorata)' })), 'contract');
  assert.equal(C(inv('2026-10', { isGrant: true, provider: 'grant', pctApplied: 1, discountInfo: '100% grant (olimpiada/ijtimoiy)' })), 'olympiad');
  assert.equal(C(inv('2026-10', { isGrant: true, provider: 'grant', pctApplied: 1, discountInfo: 'Monitoring 100 · 100% (o‘tgan oy)' })), '', 'monitoring 100 — toifa emas');
  assert.equal(C(inv('2026-10', { isGrant: true, provider: 'grant', pctApplied: 1, discountInfo: 'Monitoring 100 · tasdiqlangan (2026-10-05)', bonusRef: 'B1' })), '');
  assert.equal(C(inv('2026-10', { pctApplied: 0.2, discountInfo: 'Monitoring 90–99 · 20% (o‘tgan oy) + 3 kasal kun (−120000)' })), '');
  assert.equal(C(inv('2026-10', { pctApplied: 0.1, discountInfo: 'Aka-uka · 10%' })), '');
  assert.equal(C(inv('2026-10')), '');
  assert.equal(C(), '', 'fakturasiz — bo‘sh (baza: «nothing»)');
  // OXIRGI amaldagi faktura hal qiladi (ketgan o'quvchining keyingi fakturasi yo'q)
  assert.equal(C(inv('2026-10', { pctApplied: 0.5 }), inv('2026-11')), '', 'oktyabr 50%, noyabr oddiy — oddiy');
  assert.equal(C(inv('2026-10'), inv('2026-11', { pctApplied: 0.5 })), 'teacher_child', 'oktyabr oddiy, noyabr 50% — xodim farzandi');
  assert.equal(C(inv('2026-10', { pctApplied: 0.5 }), inv('2026-11', { status: 'canceled' })), 'teacher_child', 'bekor qilingan oxirgi faktura hisobga olinmaydi');
  assert.equal(C(inv('2026-11', { pctApplied: 0.5 }), inv('2026-10')), 'teacher_child', 'tartibga bog‘liq emas');
});

test('A2-03: «Bemor kunlari» navbati toifani tekshiradi — «Pul ta’siri» yo‘q, «Avansga qaytarish» tugmasi chiqmaydi, baza javobi tushuntiriladi', () => {
  const q = decl('renderSickQueue');
  assert.match(q, /exempt\[sid\]=sickExemptCat\(/);
  // toifadagi o'quvchi tugmali ro'yxatga umuman kirmaydi (G3, 2-raund — quyidagi ish vaqtidagi sinov)
  assert.match(q, /const leftAct=left\.filter\(n=>!exempt\[String\(n\.studentId\|\|''\)\]\)/, 'tugmali ro‘yxat — faqat toifasi qo‘llanadiganlar');
  assert.match(q, /exTxt\(n\.studentId\) \|\|/, '«Pul ta’siri» — toifa matni');
  assert.match(q, /not_eligible:/, 'baza «not_eligible» javobi uchun xabar');
});

// ---- G3 (2-raund): «Ketgan / muzlatilgan» — faqat harakat kerak bo'lganlar (haqiqiy renderSickQueue) ----
const SQ = (() => {
  const ctx = vm.createContext({ CSS: { escape: s => String(s) } });
  vm.runInContext(['sickExemptCat', 'SICK_EXEMPT_LBL', 'sickCfg', 'renderSickQueue'].map(decl).join('\n') +
    '\n;this.__q = { renderSickQueue, set: o => Object.assign(this, o) };', ctx);
  return ctx.__q;
})();
const SQ_STU = [
  { _id: 'IQ-0901', studentId: 'IQ-0901', name: 'Sinov Xodim Farzandi', payStatus: 'chiqdi' },
  { _id: 'IQ-0902', studentId: 'IQ-0902', name: 'Sinov Oddiy', payStatus: 'chiqdi' },
  { _id: 'IQ-0903', studentId: 'IQ-0903', name: 'Sinov Kontrakt', payStatus: 'muzlatilgan' }];
const SQ_INV = {
  'IQ-0901': [{ _id: 'IQ-0901__2026-11', studentId: 'IQ-0901', month: '2026-11', status: 'paid', pctApplied: 0.5, discountInfo: 'Xodim farzandi 50%' }],
  'IQ-0902': [{ _id: 'IQ-0902__2026-11', studentId: 'IQ-0902', month: '2026-11', status: 'paid', pctApplied: 0, discountInfo: 'Chegirmasiz' }],
  'IQ-0903': [{ _id: 'IQ-0903__2026-11', studentId: 'IQ-0903', month: '2026-11', status: 'pending', pctApplied: 0, discountInfo: 'Kontrakt (belgilangan summa)' }] };
// tasdiqlangan, kunlari hali qo'llanmagan ma'lumotnoma (ketgan / muzlatilgan o'quvchi — keyingi faktura yo'q)
const sqNote = (id, sid) => ({ _id: id, studentId: sid, status: 'approved', schoolDays: ['2026-11-03', '2026-11-04'], appliedDays: {}, fromDay: '2026-11-03', toDay: '2026-11-04' });
async function sickRender({ pending = [], approved = [], invErr = false } = {}) {
  SQ.set({
    SESSION: { isAdmin: false }, auth: { currentUser: { uid: 'U_FM' } }, db: {}, cache: { students: SQ_STU }, loadCol: async () => SQ_STU,
    collection: (_db, name) => ({ name }), where: (f, op, v) => ({ f, op, v }), query: (c, ...w) => ({ name: c.name, w }),
    getDocs: async q => {
      const w = q.w[0] || {}; let rows = [];
      if (q.name === 'sick_notes') rows = w.v === 'pending' ? pending : approved;
      else if (q.name === 'invoices') { if (invErr) throw new Error('o‘qilmadi'); rows = SQ_INV[w.v] || []; }
      return { size: rows.length, docs: rows.map(x => ({ id: x._id, data: () => ({ ...x }) })) };
    },
    getDoc: async () => ({ exists: () => true, data: () => ({ sickRate: 40000, sickApprovalFrom: '2026-12' }) }), doc: (...a) => a,
    classLabelOf: () => '5-A', esc: s => String(s == null ? '' : s), fmtSom: n => String(Math.round(Number(n) || 0)),
    prevMonthStr: m => m, nextMonthOf: m => m, fmtDayUz: d => String(d || ''),
    renderApprovals: () => {}, openMedicalFile: () => {}, rpc: async () => [], toast: () => {}, errMsg: e => String(e),
  });
  const el = { innerHTML: '', querySelectorAll: () => [], querySelector: () => null };
  await SQ.renderSickQueue(el);
  return el.innerHTML;
}
const SQ_LIST_H = /Ketgan \/ muzlatilgan o‘quvchilar — tasdiqlangan/;

test('G3 (2-raund): faqat toifasi chiqarilgan ketgan o‘quvchi qolsa — «kutilayotgan yo‘q», ro‘yxatda emas, bitta yig‘iq izoh qatorida', async () => {
  const h = await sickRender({ approved: [sqNote('N1', 'IQ-0901')] });
  assert.match(h, /Kutilayotgan ma’lumotnoma yo‘q ✓/);
  assert.ok(!SQ_LIST_H.test(h), 'harakatsiz yozuv «Ketgan / muzlatilgan» ro‘yxatida qolmasin (avval tugmasiz kartochka abadiy turardi)');
  assert.ok(!/data-ref=/.test(h), 'tugma yo‘q');
  assert.match(h, /<details[^>]*data-sick-exempt="1"/, 'bitta yig‘iq izoh qatori');
  assert.match(h, /<summary>[^<]*kasal kun puli qo‘llanmaydigan toifa: 1 ta — avansga qaytarilmaydi, harakat kerak emas<\/summary>/);
  assert.match(h, /Sinov Xodim Farzandi<\/b>.*— xodim farzandi \(50%\)/s);
});

test('G3 (2-raund): aralash — tugmali ro‘yxatda faqat oddiy o‘quvchi; xodim farzandi va kontrakt — izoh qatorida', async () => {
  const h = await sickRender({ approved: [sqNote('N1', 'IQ-0901'), sqNote('N2', 'IQ-0902'), sqNote('N3', 'IQ-0903')] });
  assert.match(h, SQ_LIST_H);
  assert.equal((h.match(/data-ref="/g) || []).length, 1); assert.match(h, /data-ref="N2"/);
  const list = h.split('<details')[0];
  assert.match(list, /Sinov Oddiy/);
  assert.ok(!/Sinov Xodim Farzandi|Sinov Kontrakt/.test(list), 'toifasi chiqarilganlar ro‘yxat kartochkasi emas');
  assert.match(h, /data-sick-exempt="2"/); assert.match(h, /— kontrakt<\/div>/);
});

test('G3 (2-raund): toifa o‘qilmasa — harakatli (tugma bor, baza tekshiradi); hech narsa yo‘q — avvalgidek', async () => {
  const h = await sickRender({ approved: [sqNote('N1', 'IQ-0901')], invErr: true });
  assert.match(h, SQ_LIST_H); assert.match(h, /data-ref="N1"/); assert.ok(!/<details/.test(h));
  const e = await sickRender({});
  assert.match(e, /Kutilayotgan ma’lumotnoma yo‘q ✓/); assert.ok(!/<details|data-ref=/.test(e));
});

// ---- A2-06: xodim «keldi» qoidasi ----
const P = (() => {
  const T0 = '2026-11-18';
  const ctx = vm.createContext({ todayStr: () => T0, pidKey: v => String(v == null ? '' : v), computeSalary: () => ({ total: 0 }), db: {} });
  const names = [...BASE, 'scanBreakMin', 'SA_NOT_ARRIVAL', 'saArrival', 'tzHMParts', 'saMin', 'attMetrics', 'leavePaidOf', 'leaveDayMap', 'dailyRateFor', 'dailyWorkMinFor',
    'SUB_LESSON_RATE_DEFAULT', 'subCredit', 'carryBalance', 'salaryNum', 'CAMDOWN_MIN_RATIO', 'camDownDays', 'saAgg', 'saPresent', 'saBuildRoster', 'saExpandDays',
    'payrollComputeMonth', 'dv2Dow', 'dv2StaffToday'];
  vm.runInContext('let SA_HOLIDAYS=new Map(), SA_HOLIDAYS_OK=true, SALARY_RATES_OK=true;\n' + names.map(decl).join('\n') +
    '\n;this.__p = { payrollComputeMonth, saAgg, attMetrics, dv2StaffToday, saPresent: typeof saPresent === "function" ? saPresent : null, set: o => Object.assign(this, o) };', ctx);
  return ctx.__p;
})();
// Bitta xodim (Kamera ID C1), oktyabr 2026 (22 ish kuni, hammasi o'tgan): 4 kun skan bor — biri oddiy (kirish+chiqish), qolganlari
//   faqat chiqish / terminal noma'lum holat ('undefined' — hikMapStatus o'tkazib yuboradi) / faqat tanaffus.
const SC = [
  { personId: 'C1', day: '2026-10-01', status: 'in', ts: '2026-10-01T08:05:00+05:00' }, { personId: 'C1', day: '2026-10-01', status: 'out', ts: '2026-10-01T17:02:00+05:00' },
  { personId: 'C1', day: '2026-10-02', status: 'out', ts: '2026-10-02T17:01:00+05:00' },
  { personId: 'C1', day: '2026-10-05', status: 'undefined', ts: '2026-10-05T07:58:00+05:00' },
  { personId: 'C1', day: '2026-10-06', status: 'break_out', ts: '2026-10-06T12:00:00+05:00' }, { personId: 'C1', day: '2026-10-06', status: 'break_in', ts: '2026-10-06T12:40:00+05:00' },
];
function payrollEnv() {
  P.set({
    loadCol: async n => (n === 'staff' ? [{ _id: 'S1', staffId: 'IQX-001', name: 'Sinov Xodim', position: 'Qorovul', cameraId: 'C1', salary: '2 200 000' }] : []),
    collection: (_db, name) => ({ name }), where: (...a) => a, query: (c, ...w) => ({ name: c.name, w }),
    getDocs: async q => ({ docs: (q.name === 'staff_checkins' ? SC : []).map((x, i) => ({ id: 'c' + i, data: () => ({ ...x }) })) }),
    loadSalaryRates: async () => ({}), loadSaRates: async () => true,
  });
}

test('A2-06 saPresent: kunning istalgan skani — kelgan (qatordagi «Keldi» va saAgg bilan bir xil); skansiz — yo‘q', () => {
  assert.ok(P.saPresent, 'admin.html: saPresent yo‘q');
  for (const d of ['2026-10-01', '2026-10-02', '2026-10-05', '2026-10-06']) {
    const l = SC.filter(x => x.day === d);
    assert.equal(P.saPresent(l), true, d); assert.equal(P.saPresent(l), !!P.saAgg(l).kelgan, d + ' — saAgg bilan bir xil');
  }
  assert.equal(P.saPresent([]), false); assert.equal(P.saPresent(null), false);
});

test('A2-06 oylik «Ishlagan kun» = skani bor kunlar; ushlanmadagi yo‘qlama bilan birga oydagi ish kunlariga teng', async () => {
  payrollEnv();
  const r = await P.payrollComputeMonth('2026-10');
  assert.equal(r.ok, true);
  const o = r.bodyRows[0];
  assert.equal(o.present, 4, 'faqat chiqish / noma’lum holat / tanaffus skani bo‘lgan kun ham — ishlagan kun (ilgari 1)');
  assert.equal(o.dm.absent, 18, 'ushlanma: skani bor kun yo‘qlama emas (22 − 4)');
  assert.equal(o.present + o.dm.absent, 22, 'oydagi ish kunlari — ikkalasi bir qoida bilan');
});

// ---- A2-06 (2-raund): kech kelish — KELISH skanidan (chiqish / tanaffus emas birinchi skan) ----
const STAFF1 = [{ _id: 'S1', staffId: 'IQX-001', name: 'Sinov Xodim', position: 'Qorovul', cameraId: 'C1', salary: '2 200 000' }];
function payrollEnvWith(scans) {
  P.set({
    loadCol: async n => (n === 'staff' ? STAFF1 : []),
    collection: (_db, name) => ({ name }), where: (...a) => a, query: (c, ...w) => ({ name: c.name, w }),
    getDocs: async q => ({ docs: (q.name === 'staff_checkins' ? scans : []).map((x, i) => ({ id: 'k' + i, data: () => ({ ...x }) })) }),
    loadSalaryRates: async () => ({}), loadSaRates: async () => true,
  });
}
const scanDay = (d, list) => list.map(([status, hm]) => ({ personId: 'C1', day: d, status, ts: `${d}T${hm}:00+05:00` }));
const monthDm = async scans => { payrollEnvWith(scans); const r = await P.payrollComputeMonth('2026-10'); assert.equal(r.ok, true); return plain(r.bodyRows[0].dm); };
const dash = (scans, d) => plain(P.dv2StaffToday(STAFF1, [], scans.filter(x => x.day === d), [], d));

test('A2-06 (2-raund): bitta noma’lum holatli skan 09:30 (ish 08:00) — oylik ushlanmadagi kech kelish \'in\' skan bilan bir xil; bosh sahifa ham «kechikdi»', async () => {
  const one = st => scanDay('2026-10-07', [[st, '09:30']]);   // 2026-10-07 — chorshanba
  const inn = await monthDm(one('in')), unk = await monthDm(one('unknown'));
  assert.equal(inn.late, 1); assert.equal(inn.lateMin, 80, '90 daqiqa − 10 daqiqa grace'); assert.equal(inn.lateAmt, 16667);
  assert.equal(unk.late, inn.late, 'noma’lum holat — kech kelish sanaladi (avval 0)');
  assert.equal(unk.lateMin, inn.lateMin); assert.equal(unk.lateAmt, inn.lateAmt); assert.equal(unk.total, inn.total);
  for (const st of ['in', 'unknown']) { const d = dash(one(st), '2026-10-07'); assert.equal(d.came, 1, st); assert.equal(d.late, 1, st + ' — bosh sahifa ham, oylik hisobot ham kechikkan'); }
  // «Kelgan» (saAgg) — o'sha kelish skani
  const a = P.saAgg(one('unknown')); assert.match(a.kelgan, /T09:30/); assert.equal(a.arrival, a.kelgan);
});

test('A2-06 (2-raund): oddiy kunlar (kirish → tanaffus → chiqish, avval chiqish, adashgan tanaffus) — o‘zgarmagan; faqat chiqish / tanaffus — kech emas, lekin keldi', async () => {
  const S = [
    ...scanDay('2026-10-01', [['in', '08:30'], ['break_out', '12:00'], ['break_in', '12:40'], ['out', '17:00']]),   // 20 daq kech (grace keyin)
    ...scanDay('2026-10-02', [['out', '07:00'], ['in', '08:25']]),                                                  // chiqish kelish emas — 15 daq kech
    ...scanDay('2026-10-05', [['break_in', '07:50'], ['in', '08:00']]),                                             // adashgan tanaffus — o'z vaqtida
    ...scanDay('2026-10-06', [['break_out', '12:00'], ['break_in', '12:40']]),                                      // faqat tanaffus
    ...scanDay('2026-10-07', [['out', '17:01']]) ];                                                                 // faqat chiqish
  const dm = await monthDm(S);
  assert.equal(dm.late, 2); assert.equal(dm.lateMin, 35, 'kech kelish — birinchi \'in\' skanidan, avvalgidek');
  assert.deepEqual(['2026-10-01', '2026-10-02', '2026-10-05'].map(d => dash(S, d).late), [1, 1, 0], 'bosh sahifa — avvalgidek');
  for (const d of ['2026-10-06', '2026-10-07']) {
    const r = dash(S, d);
    assert.equal(r.came, 1, d + ' — keldi (istalgan skan, saPresent)');
    assert.equal(r.late, 0, d + ' — chiqish / tanaffus vaqti «kelgan» emas: oylik ushlanmada ham kech yo‘q (avval bosh sahifa «kechikdi» derdi)');
    const a = P.saAgg(S.filter(x => x.day === d)); assert.equal(a.arrival, ''); assert.ok(a.kelgan, 'kelgan — birinchi ko‘rilgan skan (saPresent)');
  }
  for (const d of ['2026-10-01', '2026-10-02', '2026-10-05']) { const a = P.saAgg(S.filter(x => x.day === d)); assert.equal(a.kelgan, S.find(x => x.day === d && x.status === 'in').ts, d + ' — «Kelgan» birinchi \'in\', avvalgidek'); }
});

test('A2-06 (3-raund): Hikvision ortiqcha ish skanlari (overtimein / overtimeout) — kelish emas: kech kelish ushlanmasi yo‘q, tungi overtime keyingi kirishni yashirmaydi', async () => {
  const S = [
    ...scanDay('2026-10-01', [['overtimeout', '20:00']]),                                       // faqat ortiqcha ishdan chiqish
    ...scanDay('2026-10-02', [['out', '17:00'], ['overtimein', '17:05'], ['overtimeout', '20:00']]),
    ...scanDay('2026-10-05', [['overtimeout', '02:00'], ['in', '08:30']]) ];                   // tungi overtime, keyin 08:30 kirish — 20 daq kech
  const dm = await monthDm(S);
  assert.equal(dm.late, 1, 'faqat 2026-10-05 dagi \'in\' 08:30 — kech (avval overtimeout 20:00 kunlik haqqa teng kech kelish bo‘lardi)');
  assert.equal(dm.lateMin, 20, 'tungi overtimeout 02:00 kelish emas — kech kelish 08:30 dagi kirishdan');
  assert.equal(dm.lateAmt, 4167);
  assert.deepEqual(['2026-10-01', '2026-10-02', '2026-10-05'].map(d => dash(S, d).late), [0, 0, 1], 'bosh sahifa ham shu qoida bilan');
  for (const d of ['2026-10-01', '2026-10-02']) { const r = dash(S, d); assert.equal(r.came, 1, d + ' — keldi (istalgan skan)'); assert.equal(P.saAgg(S.filter(x => x.day === d)).arrival, ''); }
  assert.match(P.saAgg(S.filter(x => x.day === '2026-10-05')).arrival, /T08:30/);
});

test('A2-06 kunlik sarlavha «keldi / kelmadi» soni qatordagi «Keldi» qoidasi bilan (faqat \'in\' skan emas)', () => {
  assert.equal((ADM.match(/\.some\(x=>x\.status==='in'\)/g) || []).length, 0, 'faqat \'in\' skanni «keldi» deb sanash qolmasin');
  assert.match(ADM, /const came=roster\.filter\(r=>saPresent\(byPerson\[r\.cam\]\|\|\[\]\)\)\.length;/);
  assert.match(ADM, /const flexAbsent=roster\.filter\(r=>personRules\(r\)\.flexible && !saPresent\(byPerson\[r\.cam\]\|\|\[\]\)\)\.length;/);
  assert.match(ADM, /const present=Object\.keys\(byDay\)\.filter\(d=>saPresent\(byDay\[d\]\)\)\.length;/);
});

// ---- A2-07: «Narx jadvali» izohi ----
test('A2-07 kasal kun stavkasi izohi: tasdiqlangan ma’lumotnoma (o‘tishdan oldin «Bemor»), barcha oddiy o‘quvchilar; grant / kontrakt / xodim farzandi — yo‘q', () => {
  assert.ok(!ADM.includes('10%/20% chegirmali o‘quvchilarga'), 'eski noto‘g‘ri matn qolmasin');
  const i = ADM.indexOf('id="pt-msg"'); assert.ok(i > 0);
  const msg = ADM.slice(i, ADM.indexOf('<b>Tushlik/tanaffus', i));
  assert.match(msg, /tasdiqlagan ma’lumotnoma kunlari/);
  assert.match(msg, /davomatdagi «Bemor» belgisi/);
  assert.match(msg, /barcha oddiy o‘quvchilarga \(chegirmasiz ham, aka-uka 10%, monitoring 20%\)/);
  assert.match(msg, /grant \(100%\), kontrakt va xodim farzandiga \(50%\) qo‘llanmaydi/);
  assert.match(msg, /keyingi fakturaga o‘tadi/);
});
