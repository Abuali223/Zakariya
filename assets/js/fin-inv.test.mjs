// F2.8 (oylik sanash dalolatnomasi — INV-16, moddiy javobgar almashganda topshirish, oy oxiri ro'yxati) — bosma (fin-print.js: countHtml)
//   va sahifa yordamchilari (fin-kassa.js) sinovi:
//   node --test assets/js/fin-inv.test.mjs
//   countHtml — INV-16 (oylik / yillik / moddiy javobgar almashganda): sarlavha va shakl kodi, sababi, tilxat, blankalar, rahbar qarori,
//   komissiya imzolari (rais / a'zo), uch tilda; oddiy sanash o'zgarmagan. lastWorkday, blanksRead, monthCheckRows / monthCheckSummary,
//   controlRows (invMissing), lockScope (davr qulfi qamrovi — reliz 19, F2.8 2-qism). Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as W from './fin-words.js';
import { countHtml } from './fin-print.js';
import { lastWorkday, blanksRead, monthCheckRows, monthCheckSummary, controlRows, lockScope } from './fin-kassa.js';

const text = h => h.replace(/<style[\s\S]*?<\/style>/g, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
  .replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim();
const org = { nameUz: '«SINOV MAKTAB» МЧЖ', nameRu: 'ООО «SINOV MAKTAB»', stir: '123456789', place: 'Тошкент ш.', printLang: 'uz-cyrl', extra: {} };
const ctx = over => Object.assign({ org, signatories: [], names: { u_kas: 'Sinov Kassir', u_kas2: 'Sinov Kassir 2', u_dir: 'Sinov Direktor' },
  printedBy: 'Sinov Kassir', printedAt: '2027-01-28T13:10:00Z' }, over || {});
const book = {
  day: { id: 'cd1', day: '2027-01-28', status: 'closed', cashierUid: 'u_kas' },
  docs: [
    { id: 'k1', form: 'KO1', no: 41, status: 'posted', postedAt: '2027-01-28T05:00:00Z' },
    { id: 'c1', form: 'KO2', no: 17, status: 'posted', postedAt: '2027-01-28T06:00:00Z' },
    { id: 'dx', form: 'KO2', no: 18, status: 'posted', op: 'out_shortage', isSystem: true, postedAt: '2027-01-28T13:00:00Z' }],
  handovers: [{ id: 'ho1', createdAt: '2027-01-28T10:00:00Z', acceptedAt: '2027-01-28T10:05:00Z' }],
};
const comm = [{ title: 'Rais — direktor', name: 'Sinov Direktor' }, { title: '', name: 'Sinov Buxgalter' }, { title: '', name: 'Sinov Moliyachi' }];
const inv = over => Object.assign({ id: 'cc_9', kind: 'monthly', day: '2027-01-28', expected: 1200000, counted: 1199000, pendingSum: 0, diff: -1000, diffDocId: 'dx',
  byUid: 'u_kas', cashierUid: 'u_kas', at: '2027-01-28T13:00:00Z', commission: comm, molChange: false, blanks: { count: 38, nos: '0013-0050' },
  denoms: { 100000: 11, 50000: 1, 10000: 4, 5000: 1, 2000: 2 } }, over || {});

test('INV-16 (oylik, kun yopishda): sarlavha, shakl kodi, sababi, tilxat, blankalar, kamomad, rahbar qarori, komissiya imzolari', () => {
  const t = text(countHtml(inv(), book, ctx(), W));
  for (const must of ['ИНВ-16', 'НАҚД ПУЛ МАБЛАҒЛАРИНИ ИНВЕНТАРИЗАЦИЯ ҚИЛИШ ДАЛОЛАТНОМАСИ', '— ойлик инвентаризация (ойнинг охирги иш куни)',
    'Комиссия: Rais — direktor — Sinov Direktor; Sinov Buxgalter; Sinov Moliyachi',
    'ТИЛХАТ. Инвентаризация бошлангунига қадар барча кирим ва чиқим ҳужжатлари касса китобига киритилган', 'Моддий жавобгар шахс (кассир) Sinov Kassir',
    'Санаш пайтидаги охирги ҳужжат рақамлари: кирим ордери № 41, чиқим ордери № 17.',
    'Қатъий ҳисобдаги бланкалар («Қ» квитанциялари), фойдаланилмаган: 38 та (№ 0013-0050).',
    'Камомад — 1 000=00. Шу кун санаси билан чиқим касса ордери № 18 расмийлаштирилди.', 'Кассирнинг тушунтириши:',
    'Инвентаризация натижалари бўйича раҳбар қарори:', 'Rais — direktor Sinov Direktor', 'Комиссия аъзоси Sinov Buxgalter', 'Комиссия аъзоси Sinov Moliyachi', 'Кассир Sinov Kassir'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  for (const no of ['КАССАДАГИ НАҚД ПУЛНИ САНАШ ДАЛОЛАТНОМАСИ', 'Раҳбар қарори:', '— кунни ёпишда'])
    assert.ok(!t.includes(no), 'ortiqcha: ' + no);
  // ruxsat etilmagan HTML yo'q (esc): blanka raqamlari matnda
  assert.ok(!countHtml(inv({ blanks: { count: 1, nos: '<b>x</b>' } }), book, ctx(), W).includes('<b>x</b>'));
});

test('INV-16: yillik; rais lavozimi yozilmagan — «Комиссия раиси»; blankalar 0 ta; farqsiz — qaror qatori baribir bor', () => {
  const t = text(countHtml(inv({ kind: 'yearly', day: '2027-12-30', counted: 1200000, diff: 0, diffDocId: null, blanks: { count: 0, nos: '' },
    commission: [{ title: '', name: 'Sinov Direktor' }, { title: '', name: 'Sinov Buxgalter' }] }), book, ctx(), W));
  for (const must of ['— йиллик инвентаризация', 'фойдаланилмаган: 0 та.', 'Фарқ аниқланмади.', 'Инвентаризация натижалари бўйича раҳбар қарори:',
    'Комиссия раиси Sinov Direktor', 'Комиссия аъзоси Sinov Buxgalter'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(!t.includes('Кассирнинг тушунтириши'), 'farq yo‘q — tushuntirish qatori yo‘q');
});

test('INV-16: lotin va rus tillarida', () => {
  const l = text(countHtml(inv(), book, ctx({ lang: 'uz-latn' }), W));
  for (const must of ['INV-16', 'NAQD PUL MABLAG‘LARINI INVENTARIZATSIYA QILISH DALOLATNOMASI', '— oylik inventarizatsiya (oyning oxirgi ish kuni)', 'TILXAT. Inventarizatsiya boshlanguniga qadar',
    'Moddiy javobgar shaxs (kassir) Sinov Kassir', 'Qat’iy hisobdagi blankalar («Қ» kvitansiyalari), foydalanilmagan: 38 ta (№ 0013-0050).',
    'Inventarizatsiya natijalari bo‘yicha rahbar qarori:', 'Komissiya a’zosi Sinov Buxgalter'])
    assert.ok(l.includes(must), 'yo‘q (lotin): ' + must + '\n' + l);
  const r = text(countHtml(inv({ commission: [{ title: '', name: 'Sinov Direktor' }, { title: '', name: 'Sinov Buxgalter' }] }), book, ctx({ lang: 'ru' }), W));
  for (const must of ['ИНВ-16', 'АКТ ИНВЕНТАРИЗАЦИИ НАЛИЧНЫХ ДЕНЕЖНЫХ СРЕДСТВ', '— ежемесячная инвентаризация (последний рабочий день месяца)', 'РАСПИСКА. К началу проведения инвентаризации',
    'Материально ответственное лицо (кассир) Sinov Kassir', 'Бланки строгой отчётности (квитанции «Қ»), неиспользованные: 38 шт. (№ 0013-0050).',
    'Решение руководителя по результатам инвентаризации:', 'Председатель комиссии Sinov Direktor', 'Член комиссии Sinov Buxgalter'])
    assert.ok(r.includes(must), 'yo‘q (rus): ' + must + '\n' + r);
});

test('INV-16: moddiy javobgar almashganda (smena topshirish) — tilxatni topshiruvchi imzolaydi; oddiy topshirish va kun yopish o‘zgarmagan', () => {
  const ho = { id: 'cc_3', kind: 'handover', handoverId: 'ho1', day: '2027-01-28', expected: 1499000, counted: 1499000, pendingSum: 0, diff: 0, fromUid: 'u_kas', toUid: 'u_kas2',
    byUid: 'u_kas', at: '2027-01-28T10:05:00Z', commission: [{ title: 'Rais', name: 'Sinov Direktor' }, { title: 'A’zo', name: 'Sinov Buxgalter' }], molChange: true, blanks: null };
  const t = text(countHtml(ho, book, ctx(), W));
  for (const must of ['ИНВ-16', 'НАҚД ПУЛ МАБЛАҒЛАРИНИ ИНВЕНТАРИЗАЦИЯ ҚИЛИШ ДАЛОЛАТНОМАСИ', '— моддий жавобгар шахс алмашганда', 'Саналди: 28.01.2027 15:00 · Қабул қилинди: 28.01.2027 15:05',
    'Моддий жавобгар шахс (кассир) Sinov Kassir', 'Фарқ аниқланмади.', 'Инвентаризация натижалари бўйича раҳбар қарори:', 'Rais Sinov Direktor', 'Топширди Sinov Kassir', 'Қабул қилди Sinov Kassir 2'])
    assert.ok(t.includes(must), 'yo‘q: ' + must + '\n' + t);
  assert.ok(!t.includes('бланкалар'), 'blankalar kiritilmagan — qator yo‘q');
  const plain = text(countHtml(Object.assign({}, ho, { molChange: false, commission: [] }), book, ctx(), W));
  assert.ok(plain.includes('КАССАДАГИ НАҚД ПУЛНИ САНАШ ДАЛОЛАТНОМАСИ') && plain.includes('— сменани топшириш-қабул қилишда'));
  for (const no of ['ИНВ-16', 'ТИЛХАТ', 'раҳбар қарори']) assert.ok(!plain.includes(no), 'oddiy topshirishda ortiqcha: ' + no);
  // oddiy kun yopish: blankalar maydoni bo'lsa ham chiqmaydi (faqat inventarizatsiyada)
  const cl = text(countHtml(inv({ kind: 'close', diff: 0, counted: 1200000, diffDocId: null, commission: [] }), book, ctx(), W));
  assert.ok(cl.includes('КАССАДАГИ НАҚД ПУЛНИ САНАШ ДАЛОЛАТНОМАСИ') && cl.includes('— кунни ёпишда'));
  for (const no of ['ИНВ-16', 'ТИЛХАТ', 'бланкалар', 'раҳбар қарори']) assert.ok(!cl.includes(no), 'kun yopishda ortiqcha: ' + no);
});

test('lastWorkday: oyning oxirgi ish kuni (dushanba–juma)', () => {
  assert.equal(lastWorkday('2027-01-29'), true, 'juma, keyingi ish kuni — 1-fevral');
  assert.equal(lastWorkday('2027-01-28'), false);
  assert.equal(lastWorkday('2026-11-30'), true, 'dushanba — oyning oxirgi kuni');
  assert.equal(lastWorkday('2026-11-27'), false, 'juma, lekin 30-noyabr (dushanba) bor');
  assert.equal(lastWorkday('2027-07-30'), true, '31-iyul — shanba');
  assert.equal(lastWorkday('2027-12-31'), true);
  assert.equal(lastWorkday(''), false); assert.equal(lastWorkday(null), false); assert.equal(lastWorkday('xato'), false);
});

test('blanksRead: soni va raqamlari birga; bo‘sh — yozilmaydi', () => {
  assert.deepEqual(blanksRead('', ''), {}); assert.deepEqual(blanksRead(null, undefined), {});
  assert.deepEqual(blanksRead(' 38 ', ' 0013-0050 '), { blanks: { count: 38, nos: '0013-0050' } });
  assert.deepEqual(blanksRead('0', ''), { blanks: { count: 0, nos: '' } });
  for (const [c, n] of [['3', ''], ['0', 'x'], ['2.5', '1-2'], ['-1', 'x'], ['abc', 'x'], ['123456', '1'], ['', '0001']])
    assert.ok(blanksRead(c, n).err, `xato kutilgan: ${c} / ${n}`);
  assert.equal(blanksRead('5', 'x'.repeat(400)).blanks.nos.length, 300);
});

test('monthCheckRows / monthCheckSummary: matn va daraja', () => {
  const items = [
    { code: 'days_open', level: 'block', n: 1, days: ['2027-01-29'] }, { code: 'days_pending', level: 'ok', n: 0, days: [] },
    { code: 'unverified', level: 'warn', n: 2, days: ['2027-01-28', '2027-01-29'] },
    { code: 'inv', level: 'warn', n: 1, lastDay: '2027-01-29', kind: 'close', invDays: ['2027-01-28'] },
    { code: 'shortages', level: 'warn', n: 1, sum: 1000 }, { code: 'fixes', level: 'ok', n: 0 }, { code: 'z', level: 'ok', n: 0, days: [] },
    { code: 'advances', level: 'warn', n: 2, sum: 350000, asOf: '2027-01-31' }, { code: 'limit', level: 'ok', n: 0, days: [], cashLimit: null },
    { code: 'unmatched', level: 'warn', n: 1, sum: 50000 }, { code: 'refunds', level: 'ok', n: 0, sum: 0 },
    { code: 'payroll', level: 'info', run: 'approved', n: 1, sum: 600000 }, { code: 'snapshot', level: 'info', n: 0, snapshot: null },
    { code: 'lock', level: 'info', n: 0, lockedThrough: '2026-12-31' }];
  const mc = { month: '2027-01', ended: true, items, blockers: 1, warnings: 5, ready: false, readyWhy: 'Davrni yopib bo‘lmaydi: 29.01.2027 kassa kuni hali yopilmagan', canLock: false };
  const r = Object.fromEntries(monthCheckRows(mc).map(x => [x.code, x]));
  assert.equal(r.days_open.level, 'bad'); assert.equal(r.days_open.value, '1 ta: 29.01.2027'); assert.equal(r.days_open.label, 'Yopilmagan kassa kunlari');
  assert.equal(r.days_pending.value, 'yo‘q'); assert.equal(r.days_pending.level, 'ok');
  assert.equal(r.unverified.value, '2 ta: 28.01.2027, 29.01.2027');
  assert.equal(r.inv.value, 'oxirgi kun (29.01.2027) oddiy yopilgan; inventarizatsiya: 28.01.2027'); assert.equal(r.inv.level, 'warn'); assert.ok(r.inv.hint.includes('qayta ochadi'));
  assert.ok(r.shortages.value.startsWith('1 ta · 1 000')); assert.equal(r.z.value, 'mos'); assert.ok(r.advances.value.startsWith('2 kishi · 350 000') && r.advances.value.endsWith('(31.01.2027 holatiga)'));
  assert.equal(r.limit.value, 'limit belgilanmagan'); assert.ok(r.unmatched.value.startsWith('1 ta · 50 000'));
  assert.ok(r.payroll.value.startsWith('vedomost — tasdiqlangan; to‘lanmagan: 1 kishi · 600 000')); assert.equal(r.payroll.level, 'info');
  assert.equal(r.snapshot.value, 'olinmagan'); assert.equal(r.lock.value, '31.12.2026 gacha yopilgan — bu oy hali ochiq');
  assert.ok(monthCheckSummary(mc).startsWith('Davrni yopib bo‘lmaydi: 1 ta to‘siq — Davrni yopib bo‘lmaydi: 29.01.2027'));
  // INV — joyida / yillik / kassa kuni yo'q / oy tugamagan; surat va qulf
  const one = it => monthCheckRows({ ended: it.ended !== false, items: [it] })[0].value;
  assert.equal(one({ code: 'inv', level: 'ok', n: 0, lastDay: '2027-01-29', kind: 'monthly' }), 'o‘tkazilgan — 29.01.2027');
  assert.equal(one({ code: 'inv', level: 'ok', n: 0, lastDay: '2027-12-30', kind: 'yearly' }), 'o‘tkazilgan — 30.12.2027 (yillik)');
  assert.equal(one({ code: 'inv', level: 'info', n: 0, lastDay: null }), 'shu oyda yopilgan kassa kuni yo‘q');
  assert.equal(one({ code: 'inv', level: 'info', n: 1, lastDay: '2027-02-01', kind: 'close', ended: false }), 'oyning oxirgi ish kunida o‘tkaziladi');
  assert.equal(one({ code: 'snapshot', level: 'ok', n: 1, snapshot: { version: 2, late: true } }), 'olingan (2-surat, kechikib)');
  assert.equal(one({ code: 'lock', level: 'ok', n: 1, lockedThrough: '2027-01-31' }), '31.01.2027 gacha yopilgan');
  assert.equal(one({ code: 'payroll', level: 'ok', run: 'approved', n: 0, sum: 0 }), 'vedomost — tasdiqlangan; to‘lanmagan qoldiq yo‘q');
  assert.equal(one({ code: 'payroll', level: 'info', run: 'none', n: 0, sum: 0 }), 'vedomost — tuzilmagan; to‘lanmagan qoldiq yo‘q');
  assert.equal(monthCheckSummary({ ended: true, locked: true, lockedThrough: '2027-01-31' }), 'Davr 31.01.2027 gacha yopilgan ✓');
  assert.equal(monthCheckSummary({ ended: false }), 'Oy hali tugamagan — ro‘yxat oldindan ko‘rish uchun.');
  assert.equal(monthCheckSummary({ ended: true, ready: true, warnings: 2, canLock: true }), '2 ta ogohlantirish — tuzating yoki izoh bilan qabul qiling; davrni yopish mumkin.');
  assert.equal(monthCheckSummary({ ended: true, ready: true, warnings: 0, canLock: false }), 'Hammasi joyida — davrni Direktor yopadi.');
  assert.ok(monthCheckSummary({ isTest: true, ended: true }).startsWith('Sinov kassasi'));
});

test('controlRows: invMissing — oylik komissiya inventarizatsiyasi qatori (sinov kassasida yo‘q, eski serverda yo‘q)', () => {
  const row = c => controlRows(c).find(x => x.key === 'inv');
  const w = row({ invMissing: [{ month: '2027-01', lastDay: '2027-01-29' }, { month: '2026-12', lastDay: '2026-12-30' }] });
  assert.equal(w.level, 'warn'); assert.equal(w.label, 'Oylik komissiya inventarizatsiyasi (INV-16)');
  assert.equal(w.value, 'Yanvar 2027: oxirgi kun 29.01.2027 oddiy yopilgan; Dekabr 2026: oxirgi kun 30.12.2026 oddiy yopilgan');
  const ok = row({ invMissing: [] }); assert.equal(ok.level, 'ok'); assert.equal(ok.value, 'kamchilik yo‘q');
  assert.equal(row({ invMissing: [{ month: '2027-01', lastDay: '2027-01-29' }], isTest: true }), undefined);
  assert.equal(row({}), undefined);
});

test('lockScope (F2.8, 2-qism): 19-relizdan qulf matni — fakturalar, avans harakatlari, qaytarishlar, vedomost; eski serverda — avvalgi matn', () => {
  const v19 = lockScope(19), v18 = lockScope(18);
  assert.equal(v18, 'to‘lov, xarajat, maosh va avans yozuvlari kiritilmaydi va o‘zgartirilmaydi');
  for (const w of ['to‘lov, xarajat, maosh, xodim avansi, qaytarish va o‘quvchi avansi yozuvlari', 'hisob-fakturalari yaratilmaydi, qayta hisoblanmaydi va bekor qilinmaydi',
    'oylik vedomost yuborilmaydi, tasdiqlanmaydi va qayta ochilmaydi', 'eski qarzga to‘lov qabul qilinadi']) assert.ok(v19.includes(w), w);
  assert.equal(lockScope(undefined), v18); assert.equal(lockScope('20'), v19);
  // vedomost bandi: tasdiqlanmagan (warn) — ko'rsatma «davr yopilishidan OLDIN»
  const r = monthCheckRows({ ended: true, items: [{ code: 'payroll', level: 'warn', run: 'submitted', n: 0, sum: 0, approvalFrom: '2026-11' }] })[0];
  assert.equal(r.level, 'warn'); assert.equal(r.value, 'vedomost — tasdiqqa yuborilgan; to‘lanmagan qoldiq yo‘q');
  assert.ok(r.hint.startsWith('Vedomost davr yopilishidan OLDIN tasdiqlanadi'));
});
