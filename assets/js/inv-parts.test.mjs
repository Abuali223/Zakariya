// inv-parts.test.mjs — moliya ish rejasi F2.7 (qaror FD-32): hisob-faktura TARKIBI. admin.html'dan HAQIQIY kod o'qiladi (nomi bo'yicha
//   yuqori darajadagi funksiyalar) va bazasiz ishga tushiriladi:
//   • computeTuition yalpi summa (gross: asosiy narx, qisman oyda ish kunlari ulushi) va chegirma turlarini (parts) qaytaradi —
//     net = gross − Σ parts AYNAN; toifa turi foizga mos (invPartKind = baza app.inv_parts_kind); kasal kun — haqiqatan ayirilgani;
//     100 % grantda ham qisman oy ulushi izohga va yalpiga yoziladi; tavsiya bonusi (applyReferral / applyReferralUnits) tarkibga;
//   • «↻ Qayta hisoblash» (reconcileInvoice) tarkib farqini o'zgarish deb biladi; generatsiya va reprice meta tarkibni yuboradi;
//   • faktura qatori izohi (invPartsText).
//   KORPUS — migration/test-inv-parts.sql dagi bilan BIR XIL: sahifa shu kirishlardan aynan shu fakturani hisoblashi (shu sinov), baza
//   esa saqlangan maydonlardan (summa, asosiy narx, foiz, bonus ishorasi, izoh, kasal kun summasi) aynan shu tarkibni chiqarishi shart
//   (SQL sinovi, app.inv_parts_infer). computeTuition ATAYLAB o'zgartirilganda korpusni qayta yozish:
//     INV_PARTS_WRITE=1 node --test assets/js/inv-parts.test.mjs
//   node --test assets/js/inv-parts.test.mjs        Ma'lumotlar to'qima («Sinov …»).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const SQL_URL = new URL('../../migration/test-inv-parts.sql', import.meta.url);
// Yuqori darajadagi e'lon (0-ustundan): function / const — bir qatorli yoki tanasi surilgan ko'p qatorli.
function decl(name) {
  const L = ADM.split('\n');
  const i = L.findIndex(l => l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`) || new RegExp(`^const ${name}\\s*=`).test(l));
  if (i < 0) return '';
  const out = [L[i]];
  for (let j = i + 1; j < L.length; j++) { const l = L[j]; if (l === '' || /^\s/.test(l)) { out.push(l); continue; } if (l.startsWith('}')) out.push(l); break; }
  return out.join('\n');
}
const plain = v => JSON.parse(JSON.stringify(v == null ? null : v));
const BASE = ['SA_WORKDAYS', 'SA_RULES', 'hmToMin', 'personRules', '_saDate', 'saWorkdaysFor', '_pausesOf', 'inPause', 'billingInterval'];
const NAMES = [...BASE, 'trackOf', 'priceKeyOf', 'priceOf', 'pmNum', 'fmtSom', 'INV_PART_LBL', 'invPartKind', 'invPartsNorm', 'invPartsSame',
  'invPartsText', 'computeTuition', 'applyReferral', 'applyReferralUnits', 'reconcileInvoice'];
const T = (() => {
  const ctx = vm.createContext({ tkDay: d => String(d || '').slice(0, 10) });
  vm.runInContext(NAMES.map(decl).join('\n') + '\n;this.__t = { computeTuition, applyReferral, applyReferralUnits, reconcileInvoice, invPartKind, invPartsNorm, invPartsSame, invPartsText };', ctx);
  return ctx.__t;
})();
const KINDS = ['grant', 'monitoring100', 'monitoring20', 'teacher_child', 'siblings', 'referral', 'sick'];
const CAT_KINDS = ['grant', 'monitoring100', 'monitoring20', 'teacher_child', 'siblings'];
const sum = p => Object.values(p || {}).reduce((a, b) => a + b, 0);

// ---- Korpus kirishlari (2026-11: 1-noyabr yakshanba, 21 ish kuni) ----
const STU = {
  full:   { name: 'Sinov Faol', payStatus: '' },
  join16: { name: 'Sinov Keldi', payStatus: '', activeFrom: '2026-11-16' },                        // 11/21 ish kuni
  left03: { name: 'Sinov Ketgan', payStatus: 'chiqdi', stopFrom: '2026-11-03' },                   // 2/21
  frz20:  { name: 'Sinov Muzlatilgan', payStatus: 'muzlatilgan', stopFrom: '2026-11-20' },         // 15/21
  pause:  { name: 'Sinov Tanaffus', payStatus: '', pauses: [{ from: '2026-11-09', to: '2026-11-13' }] },   // 16/21
};
const GRADES = [[5, 'uz', 'A'], [7, 'uz', 'B'], [9, 'ru', 'A'], [11, 'uz', 'B']];
const PRICES = { 'uz-5': 3000000, 'uz-7': 2950000, 'ru-9': 3333333, 'uz-11': 1999997 };   // 1 999 997 × 50% = 999 998,5 — JS yaxlitlashi (yuqoriga) muhim
const CATS = [   // [nom, maxfiy maydonlar, kontekst qo'shimchasi]
  ['none', {}, {}],
  ['sib', {}, { tenHolders: true }],
  ['mon92', {}, { score: 92 }],
  ['mon100', {}, { score: 100 }],
  ['new95', {}, { score: 95, bonusNewRule: true, full: true }],
  ['new100ok', {}, { score: 100, bonusNewRule: true, full: true, bonus: true }],
  ['new100no', {}, { score: 100, bonusNewRule: true, full: true }],
  ['tchild', { specialCategory: 'teacher_child' }, {}],
  ['olymp', { specialCategory: 'olympiad' }, {}],
  ['contract', { specialCategory: 'contract', contractAmount: 2000000 }, {}],
  ['contractOdd', { specialCategory: 'contract', contractAmount: 1234567.5 }, {}],   // kasrli kontrakt summasi — yaxlitlanmaydi
  ['fallback', {}, { noPrice: true }],
];
const SICK = [   // [nom, kunlar, yangi qoida]
  ['s0', 0, true],
  ['s3', 3, true],
  ['s10', 10, true],
  ['s10old', 10, false],
];
const REF = [   // [nom, jurnaldagi summa, kutilayotgan tavsiyalar soni]
  ['r0', 0, 0],
  ['rEx', 300000, 0],
  ['rNew', 0, 1],
  ['rBoth', 300000, 2],
];
const DAYS = ['2026-10-12', '2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16', '2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22', '2026-10-23'];

function runCase(c) {
  const [g, lang, letter] = GRADES[c.g];
  const st = Object.assign({ _id: c.sid, studentId: c.sid, grade: g, classLetter: letter, lang }, STU[c.stu]);
  const cat = CATS.find(x => x[0] === c.cat), sick = SICK.find(x => x[0] === c.sick), ref = REF.find(x => x[0] === c.ref);
  const o = cat[2];
  const ctx = { month: '2026-11', priceMap: o.noPrice ? {} : PRICES, flatAmount: 2500000, sickRate: 40000, sickNewRule: sick[2],
    sickDaysFn: () => sick[1], sickRefsFn: () => (sick[2] && sick[1] ? { N1: DAYS.slice(0, sick[1]) } : {}),
    monScoreFn: o.score != null ? () => o.score : () => null, bonusNewRule: !!o.bonusNewRule, monFullFn: () => !!o.full,
    bonusFn: () => (o.bonus ? { id: 'B-' + c.sid, decidedAt: '2026-10-05' } : null), tenHolders: new Set(o.tenHolders ? [c.sid] : []) };
  const t = T.computeTuition(st, cat[1], ctx);
  if (t.skip) return { t: plain(t) };
  const pend = Array.from({ length: ref[2] }, (_, k) => `${c.sid}-N${k}`);
  T.applyReferralUnits(t, ref[1], pend, 300000);
  return { t: plain(t) };
}
// Har talaba holati × har toifa; kasal kun va tavsiya — aniq aylanish bilan (barcha birikmalar yetarlicha qamraladi), narx — sinf bo'yicha.
const CASES = [];
{
  let n = 0;
  for (const stu of Object.keys(STU)) for (const cat of CATS.map(x => x[0])) {
    n++;
    CASES.push({ id: `${stu}.${cat}`, sid: `IQ-${String(1000 + n)}`, stu, cat, g: (n + Math.floor(n / 12)) % 4, sick: SICK[n % 4][0], ref: REF[(n * 3 + Math.floor(n / 4)) % 4][0] });
  }
  // qo'shimcha chegaralar: har kasal kun / tavsiya varianti to'liq oy va 2/21 oyda, oddiy va aka-uka o'quvchida
  for (const stu of ['full', 'left03']) for (const cat of ['none', 'sib']) for (const s of SICK) for (const r of REF) {
    n++;
    CASES.push({ id: `${stu}.${cat}.${s[0]}.${r[0]}`, sid: `IQ-${String(1000 + n)}`, stu, cat, g: 0, sick: s[0], ref: r[0] });
  }
}
const ROWS = CASES.map(c => { const { t } = runCase(c); return { c, t }; });
const corpusRow = ({ c, t }) => ({ id: c.id, amount: t.net, base: t.base, pct: t.pct, bonus: t.bonusRef || '', info: t.info, sick: t.sickAmt,
  gross: t.gross, parts: t.parts });

test('admin.html: tarkib funksiyalari topildi', () => {
  for (const n of NAMES) assert.ok(decl(n).length > 0, n);
  assert.equal(ROWS.length, CASES.length);
  assert.ok(ROWS.filter(r => !r.t.skip).length >= 120, 'korpus yetarli (faktura chiqqan holatlar)');
});

test('har faktura: net = yalpi − Σ qismlar AYNAN; qismlar musbat, ma’lum turlar, «other» yo‘q; yalpi ≤ asosiy narx', () => {
  for (const { c, t } of ROWS) {
    if (t.skip) continue;
    assert.equal(t.net, t.gross - sum(t.parts), c.id);
    for (const [k, v] of Object.entries(t.parts)) {
      assert.ok(KINDS.includes(k), `${c.id}: tur ${k}`);
      assert.ok(v > 0 && Number.isFinite(v), `${c.id}: ${k}=${v}`);
    }
    assert.ok(t.gross >= t.net && t.gross <= t.base, `${c.id}: yalpi ${t.gross}`);
    assert.ok(Number.isInteger(t.gross) || c.cat === 'contractOdd', `${c.id}: yalpi butun so‘m`);
  }
});

test('toifa turi foizga mos (bitta) — baza app.inv_parts_kind qoidasi; kasal kun qismi ≤ kasal kun summasi', () => {
  const seen = new Set();
  for (const { c, t } of ROWS) {
    if (t.skip) continue;
    const cats = Object.keys(t.parts).filter(k => CAT_KINDS.includes(k));
    assert.ok(cats.length <= 1, c.id);
    const want = T.invPartKind(t.pct, t.bonusRef, t.info);
    if (cats.length) { assert.equal(cats[0], want, c.id); seen.add(cats[0]); }
    else assert.ok(!want || t.gross === t.net + (t.parts.sick || 0) + (t.parts.referral || 0), c.id);
    assert.ok((t.parts.sick || 0) <= t.sickAmt, `${c.id}: kasal kun ${t.parts.sick} > ${t.sickAmt}`);
  }
  for (const k of CAT_KINDS) assert.ok(seen.has(k), `korpusda ${k} bor`);
  // kutilgan toifalar
  const by = id => ROWS.find(r => r.c.id === id).t;
  assert.ok(by('full.sib').parts.siblings > 0); assert.ok(by('full.mon92').parts.monitoring20 > 0);
  assert.ok(by('full.mon100').parts.monitoring100 > 0); assert.ok(by('full.new100ok').parts.monitoring100 > 0);
  assert.ok(by('full.new100no').parts.monitoring20 > 0, 'tasdiqlanmagan 100 — 20%'); assert.ok(by('full.tchild').parts.teacher_child > 0);
  assert.ok(by('full.olymp').parts.grant > 0); assert.equal(by('full.contract').parts.grant, undefined);
});

test('qisman oy: yalpi = asosiy narx × ish kunlari ulushi; 100 % grantda ham — izohda ulush, yalpi = grant qismi, summa 0', () => {
  const by = id => ROWS.find(r => r.c.id === id).t;
  const j = by('join16.none');
  const m = /(\d+)\/(\d+) ish kuni \(prorata\)/.exec(j.info); assert.ok(m, j.info);
  assert.equal(j.gross, Math.round(j.base * (Number(m[1]) / Number(m[2]))));
  const g = by('join16.olymp');
  assert.match(g.info, /^100% grant \(olimpiada\/ijtimoiy\) · 11\/21 ish kuni \(prorata\)$/);
  assert.equal(g.net, 0); assert.equal(g.gross, Math.round(g.base * 11 / 21)); assert.deepEqual(g.parts, { grant: g.gross });
  const mo = by('join16.new100ok');
  assert.match(mo.info, /^Monitoring 100 · tasdiqlangan \(2026-10-05\) · 11\/21 ish kuni \(prorata\)/);
  assert.deepEqual(mo.parts, { monitoring100: mo.gross });
  const f = by('full.olymp'); assert.equal(f.gross, f.base); assert.doesNotMatch(f.info, /prorata/);
});

test('kasal kun: yangi qoida — sig‘gan kunlar qismda; eski qoida — faktura 0 gacha, qism = haqiqatan ayirilgani (sickAmount dan kam)', () => {
  const by = id => ROWS.find(r => r.c.id === id).t;
  const a = by('left03.none.s10.r0');   // 3 000 000 × 2/21 = 285 714; 10 kun — 7 tasi sig'adi (280 000)
  assert.equal(a.gross, 285714); assert.deepEqual(a.parts, { sick: 280000 }); assert.equal(a.net, 5714);
  const b = by('left03.none.s10old.r0');   // eski qoida: 400 000 > 285 714 — faktura 0, qism 285 714
  assert.equal(b.net, 0); assert.equal(b.sickAmt, 400000); assert.deepEqual(b.parts, { sick: 285714 });
  const c = by('full.sib.s3.rBoth');      // 3 000 000 − 10% − 120 000 − tavsiya (300 000 jurnaldan + yangi, sig'ganicha)
  assert.equal(c.parts.siblings, 300000); assert.equal(c.parts.sick, 120000);
  assert.equal(c.parts.referral, 300000 + 2 * 300000, 'yangi tavsiyalar to‘liq sig‘adi');
  assert.equal(c.net, 3000000 - 300000 - 120000 - 900000);
});

test('tavsiya: applyReferral ham tarkibga qo‘shadi; net 0 bo‘lsa qo‘llanmaydi', () => {
  const st = { _id: 'IQ-9001', studentId: 'IQ-9001', grade: 5, classLetter: 'A', lang: 'uz', name: 'Sinov Tavsiya', payStatus: '' };
  const ctx = { month: '2026-11', priceMap: PRICES, flatAmount: 0, sickRate: 40000, sickNewRule: true, sickDaysFn: () => 0, sickRefsFn: () => ({}) };
  const t = T.computeTuition(st, {}, ctx);
  assert.equal(T.applyReferral(t, 300000), 300000);
  assert.deepEqual(plain(t.parts), { referral: 300000 }); assert.equal(t.net, t.gross - 300000);
  const g = T.computeTuition(st, { specialCategory: 'olympiad' }, ctx);
  assert.equal(T.applyReferral(g, 300000), 0); assert.deepEqual(plain(g.parts), { grant: 3000000 });
});

test('«↻ Qayta hisoblash»: tarkib farqi — o‘zgarish (summa bir xil bo‘lsa ham); bir xil tarkib — o‘zgarish yo‘q', () => {
  const t = ROWS.find(r => r.c.id === 'full.sib').t;
  const inv = { amount: t.net, paidAmount: 0, status: t.net === 0 ? 'paid' : 'pending', discountInfo: t.info, isGrant: !!t.isGrant, provider: '',
    grossAmount: t.gross, discountParts: Object.assign({}, t.parts) };
  assert.equal(T.reconcileInvoice(inv, t).changed, false, 'bir xil');
  assert.equal(T.reconcileInvoice(Object.assign({}, inv, { discountParts: Object.assign({ referral: 0 }, t.parts) }), t).changed, false, '0 qism — e’tiborsiz');
  assert.equal(T.reconcileInvoice(Object.assign({}, inv, { grossAmount: t.gross + 1 }), t).changed, true, 'yalpi farq');
  assert.equal(T.reconcileInvoice(Object.assign({}, inv, { discountParts: { other: sum(t.parts) } }), t).changed, true, 'tur farq (server taxmini)');
  assert.equal(T.reconcileInvoice(Object.assign({}, inv, { grossAmount: null, discountParts: null }), t).changed, true, 'tarkib yo‘q');
  assert.equal(T.invPartsSame(inv, { gross: null }), true, 'hisoblanmagan tarkib (eski obyekt) — solishtirilmaydi');
});

test('faktura qatori izohi: yalpi va turlar (0 qismlarsiz); tarkibsiz faktura — bo‘sh', () => {
  const s = T.invPartsText({ grossAmount: 3000000, discountParts: { siblings: 300000, sick: 80000, referral: 0 } });
  assert.equal(s.replace(/[\u00a0\u202f]/g, ' '), 'Yalpi 3 000 000 so‘m · aka-uka −300 000 so‘m · kasal kun −80 000 so‘m');
  assert.equal(T.invPartsText({ grossAmount: null }), '');
  assert.equal(T.invPartsText({}), '');
  assert.match(T.invPartsText({ grossAmount: 0, discountParts: { grant: 0 } }), /^Yalpi 0 so‘m$/);
});

test('generatsiya, qayta hisoblash meta va baza: tarkib yuboriladi va saqlanadi', () => {
  assert.match(ADM, /amount:t\.net, baseAmount:t\.base, discount:t\.discount, discountInfo:t\.info, isGrant:!!t\.isGrant,\n\s+grossAmount:t\.gross, discountParts:t\.parts,/);
  assert.match(ADM, /const metaOf=w=>\(\{[^\n]*\n\s+grossAmount:w\.t\.gross, discountParts:w\.t\.parts,/);
  assert.match(ADM, /title="\$\{esc\(\[r\.discountInfo\|\|'', invPartsText\(r\)\]\.filter\(Boolean\)\.join\('\\n'\)\)\}"/);
  const REP = readFileSync(new URL('../../migration/invoice-guards.sql', import.meta.url), 'utf8');
  assert.match(REP, /"grossAmount"\s+= coalesce\(\(v_meta->>'grossAmount'\)::numeric, "grossAmount"\)/);
  assert.match(REP, /"discountParts"\s+= case when jsonb_typeof\(v_meta->'discountParts'\) = 'object' then v_meta->'discountParts' else "discountParts" end/);
  // toifa turi qoidasi — sahifa va bazada bir xil chegaralar
  const IP = readFileSync(new URL('../../migration/inv-parts.sql', import.meta.url), 'utf8');
  assert.match(IP, /when coalesce\(p_pct, 0\) >= 1 then\s+case when coalesce\(p_bonus, ''\) <> '' or coalesce\(p_info, ''\) ilike 'Monitoring 100%' then 'monitoring100' else 'grant' end\s+when p_pct >= 0\.5 then 'teacher_child'\s+when p_pct >= 0\.2 then 'monitoring20'\s+when p_pct > 0 then 'siblings'/);
  assert.equal(T.invPartKind(1, '', '100% grant (olimpiada/ijtimoiy)'), 'grant');
  assert.equal(T.invPartKind(1, 'B1', 'Monitoring 100 · tasdiqlangan (2026-10-05)'), 'monitoring100');
  assert.equal(T.invPartKind(1, '', 'monitoring 100 · 100% (o‘tgan oy)'), 'monitoring100', 'katta-kichik harf farqsiz (ILIKE)');
  assert.equal(T.invPartKind(0.5, '', ''), 'teacher_child'); assert.equal(T.invPartKind(0.2, '', ''), 'monitoring20');
  assert.equal(T.invPartKind(0.1, '', ''), 'siblings'); assert.equal(T.invPartKind(0, '', 'Kontrakt (belgilangan summa)'), '');
});

// ---- Korpus: migration/test-inv-parts.sql bilan bir xil ----
const MARK_A = "select $korpus$", MARK_B = "$korpus$::jsonb";
function corpusText(rows) { return '[\n' + rows.map(r => JSON.stringify(r)).join(',\n') + '\n]'; }
test('korpus migration/test-inv-parts.sql dagi bilan BIR XIL (baza shu fakturalardan aynan shu tarkibni chiqaradi)', () => {
  const rows = ROWS.filter(r => !r.t.skip).map(corpusRow);
  const sqlText = readFileSync(SQL_URL, 'utf8');
  const a = sqlText.indexOf(MARK_A), b = sqlText.indexOf(MARK_B);
  assert.ok(a >= 0 && b > a, 'test-inv-parts.sql: korpus bloki topilmadi');
  const want = corpusText(rows);
  if (process.env.INV_PARTS_WRITE === '1') {
    writeFileSync(SQL_URL, sqlText.slice(0, a + MARK_A.length) + want + sqlText.slice(b));
    return;
  }
  const have = sqlText.slice(a + MARK_A.length, b);
  assert.equal(have, want, 'korpus eskirgan: computeTuition ataylab o‘zgargan bo‘lsa — INV_PARTS_WRITE=1 node --test assets/js/inv-parts.test.mjs');
});
