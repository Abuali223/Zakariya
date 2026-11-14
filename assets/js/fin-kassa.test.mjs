// fin-kassa.js sinovi (faqat sof qism):  node --test assets/js/fin-kassa.test.mjs
//   controlRows(checks) — nazorat ro'yxati (RP-06): server faktlaridan (kassa_checks) qator, daraja va matn tuzadi.
//   Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { controlRows, zText, kpiRows, advArticles, goLiveConfirm, restartStaleTxt, cpIsOrg, cpLabel, cpUnconfirmed, canApproveList2, canPayDoc,
  deskHolder, needCommission, handoverRole, diffText, countedAtHandover, canVoidDoc, shortageWhy } from './fin-kassa.js';

const clean = () => ({ ok: true, today: '2027-01-08', isTest: false, gaps: [], staleOpenDay: null, unverifiedDays: [], undecidedShortages: [], diffs30: [], voids30: 0, reopens30: 0,
  waitingApproval: 0, approvedUnpaid: 0, fiscalExempt30: 0, otherParties30: 0, late30: 0, reissues30: 0, staleRefunds: 0, salaryGateOff30: 0, unprintedBooks30: [], pendingDays30: 0,
  limit: { cashLimit: 3000000, set: true, balance: 1200000, exceeded: false, days30: 0 },
  reconcile: { live: true, total: 0, p1: { pay: 0, paySum: 0, doc: 0 }, p4: { row: 0, doc: 0 }, p5: { row: 0, doc: 0 }, p8: { row: 0, doc: 0 } },
  accountable: [], damage: [], handover: { monthCount: 0, monthSum: 0, earlierCount: 0, earlierSum: 0 }, zreport: [], orgCash30: { count: 0, sum: 0 },
  zChanged30: [], cpKinds30: [], cpUnconfirmed: [] });
const by = rows => Object.fromEntries(rows.map(r => [r.key, r]));

test('nazorat ro‘yxati: toza holat — 28 tekshiruvning hammasi «joyida»', () => {
  const rows = controlRows(clean());
  assert.equal(rows.length, 28);   // +1: xodim kartasiga bog'lanmagan kassa hisoblari (sec-4)
  assert.deepEqual(rows.map(r => r.key), ['gaps', 'staleOpenDay', 'unverified', 'shortages', 'diffs', 'voids', 'reopens', 'waiting', 'unpaid', 'staleRefunds', 'fiscal', 'zreport', 'zChanged', 'orgCash', 'cpKinds', 'other',
    'late', 'reissues', 'gateOff', 'unprinted', 'limit', 'reconcile', 'accountable', 'damage', 'unlinked', 'handover', 'preLive', 'restart']);
  assert.ok(rows.every(r => r.level === 'ok'), JSON.stringify(rows.filter(r => r.level !== 'ok')));
  const r = by(rows);
  assert.equal(r.gaps.value, 'uzluksiz'); assert.equal(r.reconcile.value, 'hammasi mos'); assert.equal(r.limit.value, 'limit 3 000 000 so‘m — oshmagan');
  assert.ok(rows.every(x => x.label && x.value), 'har qatorda nom va natija');
});

test('nazorat ro‘yxati: muammolar — daraja va matn', () => {
  const c = clean();
  Object.assign(c, {
    gaps: [{ year: 2027, problems: [{ series: 'KO1', lastNo: 5, count: 4, max: 5 }] }], staleOpenDay: '2027-01-06',
    unverifiedDays: ['2027-01-04', '2027-01-05'], undecidedShortages: [{ id: 'x', no: 9, day: '2027-01-04', amount: 5000 }, { id: 'y', no: 12, day: '2027-01-05', amount: 2500.5 }],
    diffs30: [{ day: '2027-01-04', diff: -5000 }, { day: '2027-01-05', diff: 1200 }], voids30: 3, reopens30: 1, waitingApproval: 2, approvedUnpaid: 1, staleRefunds: 1,
    fiscalExempt30: 2, otherParties30: 4, late30: 1, pendingDays30: 2, reissues30: 1, salaryGateOff30: 1, unprintedBooks30: ['2027-01-05'],
    limit: { cashLimit: 3000000, set: true, balance: 4525000, exceeded: true, days30: 1 },
    reconcile: { live: true, total: 11, p1: { pay: 1, paySum: 111000, doc: 1 }, p4: { row: 1, doc: 1 }, p5: { row: 2, doc: 1, ofs: 1, ret: 1 }, p8: { row: 1, doc: 1 } },
    accountable: [{ partyId: 'staff:st1', name: 'Sinov Zavxoz', given: 400000, returned: 150000, balance: 250000, since: '2027-01-04', workDays: 4, overdue: true }],
    handover: { monthCount: 1, monthSum: 500000, earlierCount: 2, earlierSum: 900000 },
    zreport: [{ day: '2027-01-05', recorded: true, missing: false, diffCash: -10000, diffCard: 0 }, { day: '2027-01-06', recorded: false, missing: false },
              { day: '2027-01-07', recorded: true, missing: true }, { day: '2027-01-07', recorded: true, missing: false, diffCash: 0, diffCard: 2500 }],
    orgCash30: { count: 2, sum: 450000 } });
  const r = by(controlRows(c));
  const lv = k => r[k].level;
  assert.deepEqual(['gaps', 'staleOpenDay', 'shortages', 'staleRefunds', 'reconcile', 'zreport'].map(lv), ['bad', 'bad', 'bad', 'bad', 'bad', 'bad']);
  assert.equal(r.zreport.value, '05.01.2027: farq: naqd −10 000 so‘m; 06.01.2027: kiritilmagan; 07.01.2027: yo‘q; 07.01.2027: farq: karta +2 500 so‘m');
  assert.deepEqual(['unverified', 'diffs', 'reopens', 'fiscal', 'orgCash', 'reissues', 'gateOff', 'unprinted', 'limit', 'accountable', 'handover'].map(lv), Array(11).fill('warn'));
  assert.equal(r.orgCash.value, '2 ta · 450 000 so‘m');
  assert.deepEqual(['voids', 'waiting', 'unpaid', 'other', 'late'].map(lv), Array(5).fill('info'));
  assert.equal(r.gaps.value, '2027: kirim orderlari — bo‘shliq yoki takror');
  assert.equal(r.staleOpenDay.value, '06.01.2027');
  assert.equal(r.unverified.value, '2 ta: 04.01.2027, 05.01.2027');
  assert.equal(r.shortages.value, '2 ta · 7 500,50 so‘m');
  assert.equal(r.diffs.value, '04.01.2027: −5 000 so‘m; 05.01.2027: +1 200 so‘m');
  assert.equal(r.late.value, 'kech yozilgan hujjat: 1 ta; oflayn yozuv bilan yopilgan kun: 2 ta');
  assert.equal(r.limit.value, 'qoldiq 4 525 000 so‘m — limit 3 000 000 so‘mdan oshgan');
  assert.equal(r.reconcile.value, 'kirim orderisiz naqd o‘quv to‘lovi: 1 ta (111 000 so‘m); to‘lov yozuvisiz kirim orderi: 1 ta; chiqim orderisiz naqd xarajat: 1 ta; '
    + '«Buxgalteriya»ga ko‘chmagan xarajat orderi: 1 ta; chiqim orderisiz naqd maosh / avans: 2 ta; yozuvsiz maosh / avans orderi: 1 ta; '
    + 'o‘zaro hisob (dalolatnoma ↔ maosh ↔ o‘quv to‘lovi) mos emas: 1 ta; xodim qaytargan pul (kirim orderi ↔ avans / maosh yozuvi) mos emas: 1 ta; '
    + 'chiqim orderisiz naqd qaytarish: 1 ta; yozuvsiz qaytarish orderi: 1 ta');
  assert.equal(r.accountable.value, 'Sinov Zavxoz: 250 000 so‘m (04.01.2027 dan, 4 ish kuni — muddati o‘tgan)');
  assert.equal(r.handover.value, 'shu oyda: 1 ta · 500 000 so‘m; oldingi oylarda: 2 ta · 900 000 so‘m — tasniflanganini tekshiring');
});

test('nazorat ro‘yxati: oraliq holatlar — limit belgilanmagan, kassa ishga tushmagan, sinov kassasi, bo‘sh javob', () => {
  let c = clean(); c.limit = { cashLimit: 0, set: false, balance: 100, exceeded: false, days30: 0 }; c.reconcile = { live: false, total: 0 };
  c.unverifiedDays = ['2027-01-01', '2027-01-02', '2027-01-03', '2027-01-04', '2027-01-05', '2027-01-06', '2027-01-07'];
  c.accountable = [{ partyId: 'staff:st1', name: 'Sinov Zavxoz', balance: 100000, since: '2027-01-07', workDays: 1, overdue: false }];
  c.handover = { monthCount: 1, monthSum: 500000, earlierCount: 0, earlierSum: 0 };
  let r = by(controlRows(c));
  assert.deepEqual([r.limit.level, r.limit.value], ['info', 'belgilanmagan']);
  assert.deepEqual([r.reconcile.level, r.reconcile.value], ['info', 'kassa hali ishga tushirilmagan']);
  assert.deepEqual([r.unverified.level, r.unverified.value], ['bad', '7 ta: 01.01.2027, 02.01.2027, 03.01.2027, 04.01.2027, 05.01.2027, 06.01.2027 …']);
  assert.deepEqual([r.accountable.level, r.handover.level], ['info', 'info']);
  c = clean(); c.limit.days30 = 2;
  assert.deepEqual([by(controlRows(c)).limit.level, by(controlRows(c)).limit.value], ['info', 'limit 3 000 000 so‘m · 2 kun limitdan oshib yopilgan']);
  c = clean(); c.isTest = true; c.reconcile = { live: false, total: 0 };
  assert.ok(!controlRows(c).some(x => ['reconcile', 'zreport', 'zChanged', 'preLive', 'restart'].includes(x.key)), 'sinov kassasida moslik, Z-hisobot, ishga tushish chegarasi qatorlari yo‘q');
  assert.equal(controlRows(c).length, 23);   // (sinov kassasida ham bog'lanmagan hisoblar qatori — hisoblar kassaga bog'liq emas)
  const empty = controlRows(null);
  assert.ok(empty.length === 28 && empty.filter(x => x.level === 'ok').length === 26, 'bo‘sh javob: xatosiz, limit va moslik — ma’lumot');
});

test('nazorat ro‘yxati: manfiy hisobdor qoldig‘i — qizil, birinchi; xodimlar zimmasidagi kamomad (4730)', () => {
  const c = clean();
  c.accountable = [{ partyId: 'staff:st1', name: 'Sinov Zavxoz', balance: 250000, since: '2027-01-04', workDays: 4, overdue: true },
    { partyId: 'teachers:tch1', name: 'Sinov O‘qituvchi', balance: -20000, since: null, workDays: 0, overdue: false, negative: true }];
  c.damage = [{ partyId: 'teachers:tch1', name: 'Sinov O‘qituvchi', charged: 10000, repaid: 4000, balance: 6000, since: '2027-01-07', linked: true },
    { partyId: null, name: 'Sinov Kassir', charged: 2000, repaid: 0, balance: 2000, since: '2027-01-05', linked: false }];
  let r = by(controlRows(c));
  assert.equal(r.accountable.level, 'bad');
  assert.equal(r.accountable.value, 'Sinov O‘qituvchi: −20 000 so‘m — manfiy qoldiq (qaytim yoki hisobot berilgan avansdan ko‘p), tekshiring; '
    + 'Sinov Zavxoz: 250 000 so‘m (04.01.2027 dan, 4 ish kuni — muddati o‘tgan)');
  assert.equal(r.damage.level, 'info');
  assert.equal(r.damage.value, 'Sinov O‘qituvchi: 6 000 so‘m (07.01.2027 dan, qoplangan 4 000 so‘m); Sinov Kassir: 2 000 so‘m (05.01.2027 dan) — xodim kartasiga bog‘lanmagan');
  c.damage = [{ partyId: 'staff:st1', name: 'Sinov Xodim', charged: 1000, repaid: 1500, balance: -500, since: '2027-01-05', linked: true }];
  r = by(controlRows(c));
  assert.deepEqual([r.damage.level, r.damage.value], ['bad', 'Sinov Xodim: −500 so‘m — qoplangani qarordan ko‘p, tekshiring']);
  c.accountable = []; c.damage = [];
  r = by(controlRows(c));
  assert.deepEqual([r.accountable.level, r.accountable.value, r.damage.level, r.damage.value], ['ok', 'yo‘q', 'ok', 'yo‘q']);
});

test('Z-hisobot holati matni (kun javobidagi «z»)', () => {
  assert.equal(zText(null), ''); assert.equal(zText({ applies: false }), '');
  assert.equal(zText({ applies: true, needed: false, recorded: false, ok: true }), '', 'kerak bo‘lmagan va kiritilmagan — ko‘rsatilmaydi');
  assert.equal(zText({ applies: true, needed: true, recorded: false, ok: false }), 'kiritilmagan');
  assert.equal(zText({ applies: true, recorded: true, missing: true, reason: 'Apparat buzilgan', ok: false }), 'yo‘q (Apparat buzilgan)');
  assert.equal(zText({ applies: true, recorded: true, missing: false, ok: false, diffCash: 5000, diffCard: -1200 }), 'farq: naqd +5 000 so‘m, karta −1 200 so‘m');
  assert.equal(zText({ applies: true, recorded: true, missing: false, ok: true, diffCash: 0, diffCard: 0 }), 'mos');
  assert.equal(zText({ applies: true, recorded: true, missing: false, no: 'Z-1', cash: 1, card: 0 }), 'kiritilgan', 'ochiq kun: solishtirish yo‘q');
});

test('RP-22 haftalik KPI qatorlari: darajalar va matn (EX-49 maqsadi ≤ 2 %)', () => {
  const ok0 = kpiRows({ days: 5, closed: 5, onTime: 5, verified: 5, unverified: 0, diffDays: 0, shortage: 0, surplus: 0, ex49Share: 1.5, ex49: 15000, exTotal: 1000000, accOverdue: { n: 0, sum: 0 }, reopened: 0, voids: 0 });
  assert.deepEqual(ok0.map(x => x.key), ['days', 'onTime', 'unverified', 'diffs', 'ex49', 'accOverdue', 'reopened', 'voids']);
  assert.ok(ok0.every(x => x.level === 'ok'), JSON.stringify(ok0));
  assert.equal(ok0.find(x => x.key === 'ex49').value, '1,5% (15 000 so‘m / 1 000 000 so‘m; maqsad ≤ 2%)');
  const bad = kpiRows({ days: 6, closed: 5, onTime: 3, unverified: 2, diffDays: 2, shortage: 5000, surplus: 1200, ex49Share: 25, ex49: 50000, exTotal: 200000, accOverdue: { n: 1, sum: 150000 }, reopened: 1, voids: 2 });
  const L = Object.fromEntries(bad.map(x => [x.key, x]));
  assert.deepEqual([L.onTime.level, L.onTime.value, L.unverified.level, L.diffs.value, L.ex49.level, L.accOverdue.value, L.reopened.level, L.voids.level],
    ['warn', '3 / 5', 'warn', '2 ta · kamomad 5 000 so‘m · ortiqcha 1 200 so‘m', 'warn', '1 ta · 150 000 so‘m', 'warn', 'info']);
  const empty = Object.fromEntries(kpiRows({}).map(x => [x.key, x]));
  assert.deepEqual([empty.days.value, empty.onTime.value, empty.ex49.value, empty.ex49.level], ['yo‘q', '–', 'naqd xarajat yo‘q', 'info']);
});

test('avans hisoboti statiyalari: server bergan «advReport» belgisi bo‘yicha (EX, OP-18, OP-24) — OP-17 va ish haqi yo‘q (acc-5)', () => {
  const refs = { articles: [
    { id: 'EX-01', kind: 'EX', nameUz: 'Ish haqi', accountCode: '9410', cashOutAllowed: false, advReport: false },
    { id: 'EX-20', kind: 'EX', nameUz: 'Oziq-ovqat', accountCode: '1010', cashOutAllowed: true, advReport: true },
    { id: 'OP-17', kind: 'OP', nameUz: 'Yetkazib beruvchilar bilan hisob-kitob', accountCode: '6010', cashOutAllowed: true, advReport: false },
    { id: 'OP-18', kind: 'OP', nameUz: 'Asosiy vosita', accountCode: '0820', cashOutAllowed: true, advReport: true },
    { id: 'OP-24', kind: 'OP', nameUz: 'Sotish uchun tovar xaridi', accountCode: '2910', cashOutAllowed: true, advReport: true },
    { id: 'EX-21', kind: 'EX', nameUz: 'Oshxona inventari', accountCode: '1080', cashOutAllowed: true } ] };   // eski javob (belgisiz) — ro‘yxatga kirmaydi
  assert.deepEqual(advArticles(refs).map(a => a.id), ['EX-20', 'OP-18', 'OP-24']);
  assert.deepEqual(advArticles(null), []); assert.deepEqual(advArticles({}), []);
});

test('nazorat ro‘yxati: kassa ishga tushishidan oldingi naqd yozuvlar (crit-1) va kassani to‘xtatish / qayta ishga tushirish (§9)', () => {
  const c = clean();
  c.preLive = { goLive: '2027-01-04', n: 3, in: 500000, out: 120000, items: [{ kind: 'tuition', n: 2, sum: 500000 }, { kind: 'expense', n: 1, sum: 120000 }] };
  let r = by(controlRows(c));
  assert.deepEqual([r.preLive.level, r.preLive.value], ['info', 'o‘quv to‘lovi: 2 ta · 500 000 so‘m; xarajat: 1 ta · 120 000 so‘m']);
  assert.match(r.preLive.hint, /04\.01\.2027/);
  c.paused = { day: '2027-02-01', lastDay: '2027-02-01' };
  r = by(controlRows(c));
  assert.deepEqual([r.restart.level, r.restart.value], ['warn', 'kassa to‘xtatilgan: 01.02.2027 dan (oxirgi kassa kuni 01.02.2027) — naqd pul kassa hujjatisiz yozilmoqda']);
  c.paused = null;
  c.restarts = [{ startDay: '2027-02-03', prevDay: '2027-02-01', prevClosing: 4725000, counted: 4760000, delta: 35000, docNo: 2, started: true,
                  rows: { n: 2, in: 60000, out: 25000, items: [] } }];
  r = by(controlRows(c));
  assert.equal(r.restart.level, 'info');
  assert.equal(r.restart.value, '03.02.2027 dan qayta ishga tushirildi: tizimda 4 725 000 so‘m, sanaldi 4 760 000 so‘m, farq +35 000 so‘m (D-2); '
    + 'to‘xtatilgan davrdagi kassa hujjatisiz naqd: kirim 60 000 so‘m, chiqim 25 000 so‘m (2 ta)');
  c.restarts[0].delta = -1000; c.restarts[0].started = false; c.restarts[0].docNo = null;
  assert.match(by(controlRows(c)).restart.value, /\(hali boshlanmagan\).*farq −1 000 so‘m;/);
  // g4-v1: shu davrda orqa sana bilan kiritilgan yozuvlar alohida; izohlanmagan farq (farq − (kirim − chiqim)) — sariq
  c.restarts = [{ startDay: '2027-01-07', prevDay: '2027-01-05', prevClosing: 1150000, counted: 1230000, delta: 80000, docNo: 2, started: true,
                  rows: { n: 3, in: 100000, out: 20000 }, backdated: { n: 1, in: 0, out: 33000 }, unexplained: 33000 }];
  r = by(controlRows(c));
  assert.equal(r.restart.level, 'warn');
  assert.match(r.restart.value, /kirim 100 000 so‘m, chiqim 20 000 so‘m \(3 ta\); shu davrda orqa sana bilan kiritilgan: kirim 0 so‘m, chiqim 33 000 so‘m \(1 ta\); izohlanmagan farq \+33 000 so‘m — «Қ» jurnali bilan tekshiring$/);
  c.restarts[0].unexplained = 0; c.restarts[0].backdated = { n: 0, in: 0, out: 0 };
  r = by(controlRows(c));
  assert.equal(r.restart.level, 'info'); assert.doesNotMatch(r.restart.value, /orqa sana|izohlanmagan/);
  // g4v-3: «ishga tushishdan oldingi» ro'yxat chegarasi — kassa BIRINCHI ishga tushgan kun (qayta ishga tushirilgandan keyin ham);
  //   to'xtatish bo'lgan bo'lsa — to'xtatilgan davr sanalari qaysi qatorda ekani izohda aytiladi
  c.preLive = { goLive: '2027-01-04', to: '2027-01-03', n: 0, in: 0, out: 0, items: [] };
  assert.match(by(controlRows(c)).preLive.hint, /^Sanasi kassa birinchi ishga tushgan kundan \(04\.01\.2027\) oldin,.*; to‘xtatilgan davr sanalari — «Kassani to‘xtatish va qayta ishga tushirish» qatorida$/);
  c.restarts = [];
  assert.doesNotMatch(by(controlRows(c)).preLive.hint, /to‘xtatilgan davr/);
});

test('eskirgan qayta ishga tushirish sanashi (g4v-2): sanashdan keyin kiritilgan naqd yozuvlar — qayta sanash kerak', () => {
  const rs = { day: '2027-01-07', amount: 1100000, prevClosing: 1100000, delta: 0, countedAt: '2027-01-06T04:00:00Z', stale: { n: 1, in: 7000, out: 0 } };
  let t = restartStaleTxt(rs, true, '2027-01-06', false);
  assert.match(t, /^Qayta ishga tushirish sanashidan \(06\.01\.2027 09:00\) keyin kassa hujjatisiz 1 ta naqd yozuv kiritilgan \(kirim 7 000 so‘m, chiqim 0 so‘m\) — ular komissiya sanagan summaga kirmagan\. Birinchi kassa kuni ochilmaydi: /);
  assert.match(t, /«Qayta ishga tushirish» qoldig‘ini qayta kiriting \(avvalgi dalolatnoma bekor bo‘ladi\)\.$/);
  // qayta ishga tushirish kuni o'tgan (kassa ishga tushadigan kunda, birinchi kun ochilmagan) — avval sanani bo'shatish kerak
  assert.match(restartStaleTxt(rs, true, '2027-01-08', false), /kuni o‘tgan — avval «⚙ Sozlamalar»da ishga tushadigan kunni bo‘shating/);
  assert.doesNotMatch(restartStaleTxt(rs, true, '2027-01-08', true), /bo‘shating/);   // to'xtatilgan kassada — to'g'ridan-to'g'ri qayta sanash
  assert.match(restartStaleTxt(rs, false, '2027-01-06', false), /Direktor komissiya bilan pulni qayta sanab, qoldiqni qayta kiritadi\.$/);
});

test('ishga tushadigan kun o‘zgarishi (ui-5): to‘xtatish, qayta ishga tushirish, ishga tushirish — har biri o‘z tasdig‘i bilan', () => {
  const live = { started: true, pausedAt: null, restart: null };
  assert.equal(goLiveConfirm('2027-01-04', '2027-01-04', '2027-01-10', live).kind, 'none');
  // ishlagan kassa: sanani bo'shatish yoki surish — to'xtatish (oqibatlari yozilgan, ishga tushirish tasdig'idan boshqa matn)
  let g = goLiveConfirm('2027-01-04', null, '2027-01-10', live);
  assert.equal(g.kind, 'stop');
  assert.match(g.text, /KASSANI TO‘XTATISH/); assert.match(g.text, /kirim orderisiz va fiskal chek raqamisiz/); assert.match(g.text, /«Қ» blankalari/);
  assert.match(g.text, /komissiya sanashi/); assert.match(g.text, /ishga-tushirish §9/); assert.doesNotMatch(g.text, /ishga tushsinmi/);
  g = goLiveConfirm('2027-01-04', '2027-02-01', '2027-01-10', live);
  assert.equal(g.kind, 'stop'); assert.match(g.text, /keyinga surish/); assert.match(g.text, /01\.02\.2027 — faqat rejalashtirilgan kun/);
  // hali kelmagan sana yoki kassa ishlamagan — oddiy ishga tushirish; bo'shatish — tasdiqsiz
  assert.equal(goLiveConfirm('2027-01-20', '2027-01-25', '2027-01-10', live).kind, 'launch');
  // g4-v1 (a): kelgan sana, kassa kuni hali ochilmagan — ishga tushirish tasdig'i emas, o'z «to'xtatish» uslubidagi tasdig'i
  g = goLiveConfirm('2027-01-04', '2027-02-01', '2027-01-10', { started: false });
  assert.equal(g.kind, 'stop'); assert.match(g.text, /KASSANI ISHGA TUSHIRISH SURILADI/); assert.match(g.text, /01\.02\.2027 gacha/);
  assert.match(g.text, /kirim orderisiz va fiskal chek raqamisiz/); assert.match(g.text, /«Boshlang‘ich qoldiq» yangi kun bilan qayta kiritiladi/);
  assert.doesNotMatch(g.text, /ishga tushsinmi/);
  g = goLiveConfirm('2027-01-04', null, '2027-01-10', { started: false });
  assert.equal(g.kind, 'stop'); assert.match(g.text, /BEKOR QILINADI/); assert.match(g.text, /Ishga tushirish bekor qilinsinmi\?$/);
  assert.equal(goLiveConfirm('2027-01-10', '2027-01-08', '2027-01-10', { started: false }).kind, 'launch');   // oldinga surish — ishga tushirish
  assert.equal(goLiveConfirm('2027-01-20', null, '2027-01-10', live).kind, 'none');
  assert.match(goLiveConfirm(null, '2027-01-04', '2027-01-03', {}).text, /^Kassa 04\.01\.2027 dan ishga tushsinmi\?/);
  // to'xtatilgan kassa: avval qayta ishga tushirish qoldig'i; sana — faqat o'sha kun
  const paused = { started: true, pausedAt: '2027-02-01T05:00:00Z', restart: null };
  assert.equal(goLiveConfirm(null, '2027-02-03', '2027-02-02', paused).kind, 'block');
  assert.equal(goLiveConfirm(null, null, '2027-02-02', paused).kind, 'none');
  const ready = Object.assign({}, paused, { restart: { day: '2027-02-03', amount: 4760000, prevClosing: 4725000, delta: 35000, docNo: 2 } });
  assert.deepEqual([goLiveConfirm(null, '2027-02-04', '2027-02-02', ready).kind, goLiveConfirm(null, '2027-02-04', '2027-02-02', ready).text.slice(0, 40)],
    ['block', 'Qayta ishga tushirish kuni — 03.02.2027:']);
  g = goLiveConfirm(null, '2027-02-03', '2027-02-02', ready);
  assert.equal(g.kind, 'relaunch'); assert.match(g.text, /QAYTA ishga tushsinmi/); assert.match(g.text, /4 760 000 so‘m.*farq \+35 000 so‘m — dalolatnoma D-2/);
  // tayyorlangan (hali boshlanmagan) qayta ishga tushirishni bekor qilish — kassa to'xtatilgan holatga qaytadi
  const pending = { started: true, pausedAt: null, restart: ready.restart };
  assert.equal(goLiveConfirm('2027-02-03', null, '2027-02-02', pending).kind, 'stop');
  assert.equal(goLiveConfirm('2027-02-03', '2027-02-05', '2027-02-02', pending).kind, 'block');
  // (b): ishga tushadigan kun allaqachon qayta ishga tushirish kunida — boshqa kun uchun avval sanani bo'shatish kerakligi aytiladi;
  //   to'xtatilgan kassada esa — to'g'ridan-to'g'ri qayta sanash
  assert.match(goLiveConfirm('2027-02-03', '2027-02-05', '2027-02-02', pending).text, /avval ishga tushadigan kunni bo‘shating \(kassa yana to‘xtatiladi\), keyin «Qayta ishga tushirish»/);
  assert.doesNotMatch(goLiveConfirm(null, '2027-02-04', '2027-02-02', ready).text, /bo‘shating/);
  // g4b-v1 (ishga-tushirish §9 (1)): oxirgi yopilgan kun qurilma navbatidagi hali o'tkazilmagan yozuvlar bilan — to'xtatish tasdig'i emas,
  //   tushuntirish bilan to'siq (server ham rad etadi — kassa:rollback_pending); navbat yuborilib kun qayta yopilgach — oddiy to'xtatish
  const lastPend = { day: '2027-01-09', status: 'closed', pendingCount: 1, pendingSum: 5000 };
  g = goLiveConfirm('2027-01-04', null, '2027-01-10', live, lastPend);
  assert.equal(g.kind, 'block');
  assert.match(g.text, /^Kassani to‘xtatib bo‘lmaydi: oxirgi kassa kuni \(09\.01\.2027\) qurilma navbatidagi hali o‘tkazilmagan 1 ta yozuv \(5 000 so‘m\) bilan yopilgan — /);
  assert.match(g.text, /kunni qayta oching, qurilmalar navbati o‘tgach kunni qayta sanab yoping.*keyin kassani to‘xtating \(ishga-tushirish §9\)\.$/);
  assert.equal(goLiveConfirm('2027-01-04', '2027-02-01', '2027-01-10', live, lastPend).kind, 'block');   // surish ham — to'xtatish
  g = goLiveConfirm('2027-01-04', null, '2027-01-10', live, Object.assign({}, lastPend, { pendingCount: 0, pendingSum: 0 }));
  assert.equal(g.kind, 'stop'); assert.match(g.text, /qurilma navbatida qolgan \(«hali o‘tkazilmagan»\) yozuvlar bilan yopilgan oxirgi kun/);
  // (hali boshlanmagan qayta ishga tushirishni bekor qilish va kelmagan sana — bu to'siq yo'q)
  assert.equal(goLiveConfirm('2027-02-03', null, '2027-02-02', pending, lastPend).kind, 'stop');
  assert.equal(goLiveConfirm('2027-01-20', '2027-01-25', '2027-01-10', live, lastPend).kind, 'launch');
});

test('vazifalar ajratilishi — RP-06: Z yopilgandan keyin o‘zgartirilgan kunlar (crit-4), kontragent turi o‘zgarishlari va tasdiqlash tugmalari (sec-3)', () => {
  const c = clean();
  c.zChanged30 = [{ day: '2027-01-05', status: 'closed', n: 2, at: '2027-01-06T04:00:00Z', byName: 'Sinov Moliyachi' }, { day: '2027-01-04', status: 'verified', n: 1, byName: 'Sinov Kassir' }];
  c.cpKinds30 = [{ id: 'cp1', name: 'Alfa Qurilish MChJ', from: 'supplier', to: 'person', byName: 'Sinov Moliyachi', at: '2027-01-05T20:30:00Z', confirmed: false },
                 { id: 'cp2', name: 'Beta Savdo', from: null, to: 'other', byName: 'Sinov Kassir', at: '2027-01-06T05:00:00Z', confirmed: true },
                 { id: 'cp3', name: 'Gamma MChJ', from: 'person', to: 'org', byName: null, at: '2027-01-06T05:00:00Z', confirmed: false }];
  c.cpUnconfirmed = [{ id: 'cp1', name: 'Alfa Qurilish MChJ', kind: 'person', stir: '301234567' }];
  const r = by(controlRows(c));
  assert.deepEqual([r.zChanged.level, r.zChanged.value], ['warn', '05.01.2027: 2 marta, oxirgisi — Sinov Moliyachi; 04.01.2027: 1 marta, oxirgisi — Sinov Kassir (tekshirilgan)']);
  assert.match(r.zChanged.hint, /Z ni o‘zgartirgan xodim tekshira olmaydi/);
  assert.equal(r.cpKinds.level, 'info');
  // vaqt — Toshkent bo'yicha (20:30 UTC = ertasi kun 01:30)
  assert.equal(r.cpKinds.value, 'Alfa Qurilish MChJ: Yetkazib beruvchi → Jismoniy shaxs (Sinov Moliyachi, 06.01.2027, tasdiqlanmagan); '
    + 'Beta Savdo: yangi → Boshqa (Sinov Kassir, 06.01.2027); Gamma MChJ: Jismoniy shaxs → Tashkilot (tizim, 06.01.2027); turi tasdiqlanmagan: 1 ta — Alfa Qurilish MChJ');
  assert.deepEqual(r.cpKinds.acts, [{ id: 'cp1', kind: 'person', name: 'Alfa Qurilish MChJ' }]);
  assert.ok(controlRows(clean()).every(x => !(x.acts || []).length), 'toza holatda tasdiqlash tugmasi yo‘q');
  c.isTest = true; c.reconcile = { live: false, total: 0 };
  const t = by(controlRows(c));
  assert.ok(!t.zChanged && t.cpKinds, 'sinov kassasida Z qatori yo‘q, kontragent turi (umumiy ma’lumotnoma) — bor');
});

test('kontragent turi (sec-3): yuridik shaxs belgisi server qoidasidan, tasdiqlanmagan «jismoniy shaxs» / «boshqa» — yuridik shaxs', () => {
  assert.equal(cpIsOrg({ kind: 'person', confirmed: false, org: true }), true);
  assert.equal(cpIsOrg({ kind: 'person', confirmed: true, org: false }), false);
  assert.equal(cpIsOrg({ kind: 'supplier', org: true }), true);
  // eski javob («org» yo'q) — tur bo'yicha: tasdiqlanmagan jismoniy shaxs ham yuridik shaxs; bank / ta'sischi — yo'q
  assert.deepEqual([{ kind: 'org' }, { kind: 'other', confirmed: false }, { kind: 'person' }, { kind: 'bank' }, { kind: 'founder', confirmed: false }].map(cpIsOrg), [true, true, false, false, false]);
  assert.equal(cpIsOrg(null), false);
  assert.deepEqual([cpUnconfirmed({ kind: 'person', confirmed: false }), cpUnconfirmed({ kind: 'supplier', confirmed: false }), cpUnconfirmed({ kind: 'other', confirmed: true })], [true, false, false]);
  assert.equal(cpLabel({ name: 'Beta Qurilish MChJ', stir: '309876543', kind: 'person', confirmed: false }), 'Beta Qurilish MChJ · STIR 309876543 · turi tasdiqlanmagan');
  assert.equal(cpLabel({ name: 'Sinov Bank', kind: 'bank', confirmed: false }), 'Sinov Bank');
  assert.equal(cpLabel({ name: 'Sinov YaTT', kind: 'person', confirmed: true }), 'Sinov YaTT');
});

test('vazifalar ajratilishi (sec-1, sec-5): tasdiqlash va pul berish tugmalari — o‘zi so‘ragan, o‘z kartasiga, o‘zi tasdiqlagan', () => {
  const fm = { uid: 'U_FM', list2: true, cards: ['staff:st2', 'teachers:tch5'] }, acc = { uid: 'U_ACC', list2: true, cards: [] };
  const d = { status: 'draft', needsList2: true, approvedBy: null, requestedBy: 'U_KAS', partyType: 'employee', partyId: 'staff:st2' };
  assert.deepEqual([canApproveList2(d, fm), canApproveList2(d, acc)], [false, true], 'o‘z kartasiga — boshqa 2-ro‘yxat xodimi tasdiqlaydi');
  assert.equal(canApproveList2(Object.assign({}, d, { partyId: 'teachers:tch5' }), fm), false, 'ikkinchi lavozim kartasi ham o‘ziniki');
  assert.equal(canApproveList2(Object.assign({}, d, { partyId: 'staff:st9' }), fm), true);
  assert.equal(canApproveList2(Object.assign({}, d, { requestedBy: 'U_ACC' }), acc), false, 'o‘zi so‘ragan (CT-07)');
  assert.equal(canApproveList2(Object.assign({}, d, { partyType: 'counterparty', partyId: 'staff:st2' }), fm), true, 'faqat xodim tomoni (kontragent kaliti — karta emas)');
  assert.equal(canApproveList2(Object.assign({}, d, { approvedBy: 'U_ACC' }), fm), false);
  // Direktor 2-ro'yxat bosqichini faqat 2-ro'yxat xodimiga beriladigan pulda imzolaydi (me.l2Cards)
  const dir = { uid: 'U_DIR', director: true, l2Cards: ['staff:st2', 'staff:st3'] };
  assert.equal(canApproveList2(d, { uid: 'U_DIR', director: true }), false, 'Direktor — o‘z bosqichida');
  assert.deepEqual([canApproveList2(d, dir), canApproveList2(Object.assign({}, d, { partyId: 'staff:st1' }), dir)], [true, false], 'pul oluvchi 2-ro‘yxat xodimi — Direktor imzolaydi');
  assert.equal(canApproveList2(Object.assign({}, d, { requestedBy: 'U_DIR' }), dir), false, 'Direktor o‘zi so‘ragan (CT-07)');
  assert.equal(canApproveList2(Object.assign({}, d, { partyType: 'counterparty' }), dir), false);
  const fmk = { uid: 'U_FMK', list2: true, operator: true }, kas = { uid: 'U_KAS', operator: true };
  const a = { status: 'approved', approvedBy: 'U_FMK', op: 'out_expense', sourceTable: null };
  assert.deepEqual([canPayDoc(a, fmk), canPayDoc(a, kas), canPayDoc(a, { uid: 'U_DIR', director: true })], [false, true, true]);
  assert.equal(canPayDoc(Object.assign({}, a, { status: 'draft' }), kas), false);
  assert.equal(canPayDoc(Object.assign({}, a, { sourceTable: 'salary_payments', op: 'out_salary' }), kas), false, 'boshqa bo‘limdan yozilgan');
  assert.equal(canPayDoc(Object.assign({}, a, { sourceTable: 'refunds', op: 'out_refund' }), kas), true, 'tasdiqlangan qaytarish');
});

// ---------------------------------------------------------------- ko'rik 6-guruhi (sec-2, state-6, sec-4, acc-6)
test('kassa egasi va komissiya (sec-2): egasi bo‘lmagan kassir, Direktor, Moliya menejeri — kassir o‘rniga', () => {
  const kas = { uid: 'u_kas', operator: true }, kas2 = { uid: 'u_kas2', operator: true }, dir = { uid: 'u_dir', director: true }, fm = { uid: 'u_fm', list2: true };
  assert.deepEqual([deskHolder({ cashierUid: 'u_kas' }, kas2), deskHolder({ cashierUid: null }, kas), deskHolder({ cashierUid: null }, dir), deskHolder(null, kas)],
    ['u_kas', 'u_kas', null, 'u_kas'], 'egasi aniqlanmagan kunda kassa operatori — o‘zi');
  assert.deepEqual([needCommission({ cashierUid: 'u_kas' }, kas), needCommission({ cashierUid: 'u_kas' }, kas2), needCommission({ cashierUid: null }, kas2),
    needCommission({ cashierUid: 'u_kas' }, dir), needCommission({ cashierUid: null }, fm), needCommission({}, null)],
    [false, true, false, true, true, true]);
});

test('kutilayotgan smena topshirish (state-6): qabul qiluvchi qabul qiladi / rad etadi, topshiruvchi va Direktor bekor qiladi', () => {
  const h = { id: 'ho_1', status: 'pending', fromUid: 'u_kas', toUid: 'u_kas2', byUid: 'u_kas' };
  assert.deepEqual(handoverRole(h, { uid: 'u_kas2', operator: true }), { receiver: true, giver: false, canAccept: true, canCancel: true });
  assert.deepEqual(handoverRole(h, { uid: 'u_kas', operator: true }), { receiver: false, giver: true, canAccept: false, canCancel: true });
  assert.deepEqual(handoverRole(h, { uid: 'u_dir', director: true }), { receiver: false, giver: false, canAccept: false, canCancel: true });
  assert.deepEqual(handoverRole(h, { uid: 'u_tre', operator: true }), { receiver: false, giver: false, canAccept: false, canCancel: false }, 'ishtirok etmagan kassir — hech narsa');
  // kassir o'rniga (komissiya bilan) yozilgan: yozgan xodim ham bekor qila oladi
  assert.equal(handoverRole(Object.assign({}, h, { byUid: 'u_tre' }), { uid: 'u_tre', operator: true }).canCancel, true);
  assert.deepEqual(handoverRole(Object.assign({}, h, { status: 'accepted' }), { uid: 'u_kas2', operator: true }), { receiver: false, canAccept: false, canCancel: false });
  assert.deepEqual(handoverRole(null, { uid: 'u_kas2' }), { receiver: false, canAccept: false, canCancel: false });
});

test('kun farqi (acc-6): smena topshirishdagi farqlar yopish farqi yonida; nazorat ro‘yxati va KPI', () => {
  assert.equal(diffText(-5000, []), '−5 000 so‘m', 'smena farqi yo‘q — avvalgidek');
  assert.equal(diffText(1200), '+1 200 so‘m');
  assert.equal(diffText(-2000, [5000, 0]), 'yopishda −2 000 so‘m, smenada +5 000 so‘m');
  assert.equal(diffText(0, [-7000]), 'smenada −7 000 so‘m', 'ochiq yoki farqsiz yopilgan kunda — faqat smena farqi');
  const c = clean();
  c.diffs30 = [{ day: '2027-01-04', diff: -5000, handover: [] }, { day: '2027-01-06', diff: -2000, handover: [5000] }, { day: '2027-01-07', diff: 0, handover: [-7000] }];
  const r = by(controlRows(c));
  assert.deepEqual([r.diffs.level, r.diffs.value], ['warn', '04.01.2027: −5 000 so‘m; 06.01.2027: yopishda −2 000 so‘m, smenada +5 000 so‘m; 07.01.2027: smenada −7 000 so‘m']);
  assert.match(r.diffs.hint, /smena topshirish/);
  const k = Object.fromEntries(kpiRows({ days: 2, closed: 2, onTime: 2, diffDays: 2, shortage: 2000, surplus: 5000, handoverDiffs: 1 }).map(x => [x.key, x]));
  assert.equal(k.diffs.value, '2 ta · kamomad 2 000 so‘m · ortiqcha 5 000 so‘m (smena topshirishda: 1 ta)');
});

test('nazorat ro‘yxati (sec-4): xodim kartasiga bog‘lanmagan kassa hisoblari — «diqqat», ism va lavozim', () => {
  const c = clean();
  c.unlinkedUsers = [{ uid: 'U_HRK', name: 'Sinov HR', role: 'hr', kassir: true }, { uid: 'U_TRE', name: 'U_TRE', role: 'treasurer', kassir: false }];
  const r = by(controlRows(c));
  assert.deepEqual([r.unlinked.level, r.unlinked.value], ['warn', 'Sinov HR (hr + kassir), U_TRE (g‘aznachi)']);
  assert.match(r.unlinked.hint, /Foydalanuvchilar/);
  assert.equal(by(controlRows(clean())).unlinked.value, 'yo‘q');
});

// ---------------------------------------------------------------- ko'rik 6b-guruhi (g6v-1, g6v-2, g6v-3)
test('smena topshirishda sanalgan order (g6v-2): kassir bekor qilmaydi, 2-ro‘yxat va Direktor — bekor qiladi; boshqa qoidalar avvalgidek', () => {
  const od = { id: 'cd_main_2028-01-13', status: 'open', countedKo1: 7, countedKo2: 3 };
  const kas = { uid: 'u_kas', operator: true }, fm = { uid: 'u_fm', list2: true }, dir = { uid: 'u_dir', director: true };
  const k1 = no => ({ id: 'd' + no, form: 'KO1', no, status: 'posted', postedBy: 'u_kas', isSystem: false, sourceTable: null, op: 'in_bank' });
  assert.deepEqual([countedAtHandover(k1(7), od), countedAtHandover(k1(8), od), countedAtHandover(Object.assign(k1(3), { form: 'KO2' }), od),
    countedAtHandover(Object.assign(k1(4), { form: 'KO2' }), od)], [true, false, true, false], 'raqam — topshirish yozilgan paytdagi eng katta raqamgacha');
  assert.equal(countedAtHandover(k1(1), { id: 'x', countedKo1: null, countedKo2: null }), false, 'qabul qilingan topshirish yo‘q');
  assert.equal(countedAtHandover(k1(5), null), false);
  assert.deepEqual([canVoidDoc(k1(7), kas, od), canVoidDoc(k1(8), kas, od)], [false, true], 'kassir: sanalgani — yo‘q, keyingisi — o‘zi o‘tkazgan bo‘lsa, bor');
  assert.deepEqual([canVoidDoc(k1(7), fm, od), canVoidDoc(k1(7), dir, od)], [true, true], '2-ro‘yxat va Direktor — sanalganini ham');
  assert.equal(canVoidDoc(Object.assign(k1(8), { postedBy: 'u_kas2' }), kas, od), false, 'kassir boshqa kassir orderini bekor qilmaydi');
  assert.equal(canVoidDoc(Object.assign(k1(8), { isSystem: true }), dir, od), false, 'tizim hujjati (sanash farqi) — hech kim');
  assert.equal(canVoidDoc(Object.assign(k1(8), { sourceTable: 'refunds', op: 'out_refund' }), dir, od), false, 'qaytarish orderi — yo‘q');
  assert.equal(canVoidDoc(Object.assign(k1(8), { sourceTable: 'payments', op: 'in_tuition' }), kas, od), true, 'naqd o‘quv to‘lovi — bor');
  assert.deepEqual([canVoidDoc(Object.assign(k1(8), { status: 'void' }), dir, od), canVoidDoc(k1(8), kas, null)], [false, false], 'bekor qilingan / ochiq kun yo‘q');
  assert.equal(canVoidDoc(k1(7), kas, { id: 'x' }), true, 'eski server (countedKo1 yo‘q) — avvalgidek, server baribir tekshiradi');
});

test('kamomad qarori (g6v-3): nega standart javobgar yo‘q — server matni (defaultWhy), eski serverda — avvalgi matn', () => {
  assert.equal(shortageWhy({ defaultParty: 'staff:st1', defaultWhy: null }), '', 'standart javobgar bor — matn yo‘q');
  assert.equal(shortageWhy({ cashierUid: 'u_kas', countedBy: 'u_kas', defaultParty: null,
    defaultWhy: 'Shu kuni kassa egasidan boshqa xodim ham kassa orderini o\'tkazgan yoki bekor qilgan: Sinov Direktor' }),
    'Shu kuni kassa egasidan boshqa xodim ham kassa orderini o\'tkazgan yoki bekor qilgan: Sinov Direktor');
  assert.equal(shortageWhy({ cashierUid: 'u_kas', defaultParty: null, defaultWhy: 'Eski hujjat: pulni kim sanagani yozilmagan' }), 'Eski hujjat: pulni kim sanagani yozilmagan');
  // eski server (defaultWhy yo'q) — sahifaning avvalgi matni
  assert.equal(shortageWhy({ cashierUid: null, countedBy: 'u_dir' }), 'Kassa egasi (kun kassiri) aniqlanmagan');
  assert.equal(shortageWhy({ cashierUid: 'u_kas', countedBy: 'u_kas2' }), 'Pulni kassa egasining o‘zi sanamagan (kassir o‘rniga sanalgan)');
  assert.equal(shortageWhy({ cashierUid: 'u_kas', countedBy: 'u_kas' }), 'Kassir hisobi xodim kartasiga bog‘lanmagan');
  assert.equal(shortageWhy(null), '');
});
