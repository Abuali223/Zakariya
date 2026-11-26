// Buxgalter savollari (Sh-8) bo'yicha egasi qarorlari (2026-11-26) — sahifa yordamchilari (fin-kassa.js) va oylik to'plam varaqlari
//   (fin-print.js) sinovi:
//   node --test assets/js/fin-sh8.test.mjs
//   B15: depositDaysText (jadval matni), depositTxt (topshirish kuni eslatmasi), limitHintTxt (kassa limiti tavsiyasi), nazorat qatori
//   «Bankka topshirish (inkassatsiya)»; B19/B20: E5 o'zaro hisob, E6 xodim farzandi chegirmasi, E7 vedomost va to'lovlar — ismli va
//   ismsiz (FD-28) nusxa, jamlar, ogohlantirishlar, uch til, eski server javobi (varaqlar yo'q), sinov kassasi. Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { WEEKDAYS, depositDaysText, depositTxt, limitHintTxt, controlRows } from './fin-kassa.js';
import { packSheets, offsetSheet, staffDiscSheet, payrollSheet } from './fin-print.js';

const org = { nameUz: '«SINOV MAKTAB» МЧЖ', nameRu: 'ООО «SINOV MAKTAB»', stir: '123456789', place: 'Тошкент ш.', printLang: 'uz-cyrl', extra: {} };
const ctx = over => Object.assign({ org }, over || {});
const base = { ok: true, month: '2027-01', from: '2027-01-01', to: '2027-01-31', masked: false, desk: { id: 'main', name: 'Asosiy kassa', isTest: false },
  journal: { docs: [] }, matrix: { rows: [] }, days: [], advances: [] };
const full = Object.assign({}, base, {
  offsets: [
    { day: '2027-01-10', no: 1, month: '2026-12', code: 'T-01', partyName: 'Sinov Muallima', studentId: 'S-1', studentName: 'Sinov Bola Bir', amount: 300000 },
    { day: '2027-01-12', no: 2, month: '2027-01', code: 'T-01', partyName: 'Sinov Muallima', studentId: 'S-2', studentName: 'Sinov Bola Ikki', amount: 150000 },
    { day: '2027-01-20', no: 3, month: '2027-01', code: 'X-01', partyName: 'Sinov Xodima', studentId: 'S-3', studentName: 'Sinov Bola Uch', amount: 200000 }],
  staffDiscounts: [
    { studentId: 'S-1', studentName: 'Sinov Bola Bir', employee: 'T-01', employeeName: 'Sinov Muallima', base: 1000000, discount: 500000, amount: 500000, status: 'paid' },
    { studentId: 'S-4', studentName: 'Sinov Bola To‘rt', employee: null, employeeName: null, base: 900000, discount: 450000, amount: 450000, status: 'pending' }],
  payroll: { status: 'approved', approvedAt: '2027-01-28T07:00:00Z', lines: [
    { code: 'X-01', type: 'staff', name: 'Sinov Xodima', gross: 3000000, deduction: 0, subBonus: 0, advance: 500000, carryIn: -100000, payable: 2400000,
      paidCash: 2400000, paidCard: 0, paidOffset: 0, paidOther: 1000 },
    { code: 'T-01', type: 'teacher', name: 'Sinov Muallima', gross: 5000000, deduction: 100000, subBonus: 50000, advance: 1000000, carryIn: 0, payable: 3950000,
      paidCash: 2000000, paidCard: 1000000, paidOffset: 300000, paidOther: 0 }] } });
const v = c => (c && typeof c === 'object' && 'v' in c) ? c.v : c;       // Excel katagi → qiymat
const flat = sh => JSON.stringify(sh.rows);

test('depositDaysText: jadval matni (tartib, noto‘g‘ri qiymatlar, ish kunlari, bo‘sh)', () => {
  assert.equal(depositDaysText([5]), 'har juma');
  assert.equal(depositDaysText([5, 2]), 'har seshanba va juma');
  assert.equal(depositDaysText([1, 3, 5]), 'har dushanba, chorshanba va juma');
  assert.equal(depositDaysText([1, 2, 3, 4, 5]), 'har ish kuni');
  assert.equal(depositDaysText([1, 2, 3, 4, 5, 6, 7]), 'har kuni');
  assert.equal(depositDaysText([1, 2, 3, 4, 5, 6]), 'har dushanba, seshanba, chorshanba, payshanba, juma va shanba', '6 kun — «har kuni» emas');
  assert.equal(depositDaysText([1, 2, 3, 4, 6]), 'har dushanba, seshanba, chorshanba, payshanba va shanba');
  assert.equal(depositDaysText([6, 7]), 'har shanba va yakshanba');
  assert.equal(depositDaysText(['5', 9, 0]), 'har juma', 'satr son sifatida o‘qiladi, 1–7 dan tashqarisi tashlanadi');
  assert.equal(depositDaysText([]), 'jadval yo‘q');
  assert.equal(depositDaysText(null), 'jadval yo‘q');
  assert.deepEqual(WEEKDAYS.map(x => x[0]), [1, 2, 3, 4, 5, 6, 7]);
  assert.deepEqual(WEEKDAYS.map(x => x[1]), ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya']);
});

test('depositTxt: topshirish kuni eslatmasi — qoldiq, maydalik, topshiriladigan summa', () => {
  assert.equal(depositTxt({ keep: 100000, amount: 550000 }, 650000),
    'Bugun — bankka topshirish (inkassatsiya) kuni: kassada 650 000 so‘m, 100 000 so‘m maydalik qoldirib — 550 000 so‘m bankka topshiriladi («+ Chiqim so‘rovi» → «Bankka topshirish»).');
  assert.equal(depositTxt({ keep: 0, amount: 650000 }, 650000),
    'Bugun — bankka topshirish (inkassatsiya) kuni: kassada 650 000 so‘m — 650 000 so‘m bankka topshiriladi («+ Chiqim so‘rovi» → «Bankka topshirish»).');
});

test('limitHintTxt: kassa limiti tavsiyasi (bankka ariza uchun); ma’lumot yo‘q — izoh', () => {
  assert.equal(limitHintTxt({ receipts: 1500000, days: 6, avgDaily: 250000, interval: 5, suggest: 1250000 }),
    'Kassa limiti bank bilan kelishiladi. Tavsiya (bankka ariza uchun): oxirgi 6 ish kunida o‘rtacha kunlik naqd tushum 250 000 so‘m × topshirish oralig‘i 5 ish kuni ≈ 1 250 000 so‘m.');
  assert.match(limitHintTxt({ receipts: 0, days: 0, avgDaily: 0, interval: 5, suggest: 0 }), /^Kassa limiti bank bilan kelishiladi; tavsiya kassa kamida bir necha kun ishlagach hisoblanadi\.$/);
  assert.match(limitHintTxt(null), /^Kassa limiti bank bilan kelishiladi;/);
});

test('nazorat qatori «Bankka topshirish»: o‘tkazib yuborilgan kunlar — ogohlantirish; o‘z vaqtida — ok; jadval yo‘q — ma’lumot; eski server — qator yo‘q', () => {
  const row = c => controlRows(c).find(x => x.key === 'deposit');
  let r = row({ deposit: { days: [5], keep: 0 }, depositMissed30: ['2027-01-08', '2027-01-15'] });
  assert.deepEqual([r.label, r.level, r.value], ['Bankka topshirish (inkassatsiya)', 'warn', '2 ta kun topshirilmagan: 08.01.2027, 15.01.2027']);
  assert.match(r.hint, /^Jadvaldagi kunda kun oxiridagi qoldiq \(maydalikdan ortig‘i\) bankka topshiriladi; jadval va kassa limiti — «⚙ Sozlamalar»/);
  r = row({ deposit: { days: [2, 5], keep: 100000 }, depositMissed30: [] });
  assert.deepEqual([r.level, r.value], ['ok', 'har seshanba va juma — o‘z vaqtida']);
  r = row({ deposit: { days: [], keep: 0 }, depositMissed30: [] });
  assert.deepEqual([r.level, r.value], ['info', 'jadval belgilanmagan']);
  const many = Array.from({ length: 8 }, (_, i) => `2027-01-${String(i + 1).padStart(2, '0')}`);
  assert.match(row({ deposit: { days: [1, 2, 3, 4, 5, 6, 7] }, depositMissed30: many }).value, /^8 ta kun topshirilmagan: 01\.01\.2027, .*06\.01\.2027 …$/);
  assert.equal(row({}), undefined, '15-relizdan oldingi server — qator yo‘q');
  // qator «Vedomost tasdig‘isiz naqd maosh» dan oldin (nazorat ro'yxatidagi tartib)
  const keys = controlRows({ deposit: { days: [5] }, depositMissed30: [] }).map(x => x.key);
  assert.equal(keys.indexOf('deposit') + 1, keys.indexOf('gateOff'));
});

test('oylik to‘plam: yangi server — 7 varaq (uz va ru), eski server — 4 varaq, sinov kassasi — E6 va E7 yo‘q; varaq nomlari Excel qoidasiga mos', () => {
  const uz = packSheets(full, ctx());
  assert.deepEqual(uz.map(x => x.name), ['E1 KO-3', 'E2 Statiyalar', 'E3 Kassa kunlari', 'E4 Hisobdorlar', 'E5 O‘zaro hisob', 'E6 Xodim farzandi', 'E7 Vedomost']);
  const ru = packSheets(full, ctx({ lang: 'ru' }));
  assert.deepEqual(ru.slice(4).map(x => x.name), ['E5 Взаимозачёт', 'E6 Скидка сотрудникам', 'E7 Ведомость']);
  for (const sh of uz.concat(ru)) {
    assert.ok(sh.name.length <= 31 && !/[:\\/?*[\]]/.test(sh.name), 'varaq nomi: ' + sh.name);
    assert.equal(sh.cols.length, Math.max(...sh.rows.filter(r => r.length > 1).map(r => r.length)), 'ustun kengliklari soni = eng keng qator: ' + sh.name);
  }
  assert.equal(packSheets(base, ctx()).length, 4, 'eski server javobi (offsets / staffDiscounts / payroll yo‘q)');
  const t = packSheets(Object.assign({}, full, { desk: { id: 'sinov', name: 'SINOV', isTest: true }, staffDiscounts: [], payroll: null }), ctx());
  assert.deepEqual(t.map(x => x.name).slice(4), ['E5 O‘zaro hisob']);
});

test('E5 o‘zaro hisob: ro‘yxat (dalolatnoma seriyasi chop etish tilida), jami, xodim bo‘yicha jami, izoh; ismsiz nusxada ism ustunlari yo‘q', () => {
  const sh = offsetSheet(full, ctx());
  const r = sh.rows;
  assert.deepEqual(r[1], ['O‘ZARO HISOB: XODIM FARZANDINING O‘QISHI UCHUN ISH HAQIDAN TO‘LOV']);
  assert.deepEqual(r[4], ['Sana', 'Dalolatnoma №', 'Ish haqi oyi', 'Xodim (tabel kodi)', 'Xodim F.I.Sh.', 'O‘quvchi (ID)', 'O‘quvchi F.I.Sh.', 'Summa']);
  assert.deepEqual(r[5].map(v), [46397, 'O‘H-1', '2026-12', 'T-01', 'Sinov Muallima', 'S-1', 'Sinov Bola Bir', 300000]);
  const tot = r.find(x => x[0] === 'Jami');
  assert.deepEqual([tot.length, v(tot[7])], [8, 650000]);
  const i = r.findIndex(x => x[0] === 'Xodim bo‘yicha jami');
  assert.deepEqual(r[i + 1], ['Xodim (tabel kodi)', 'Xodim F.I.Sh.', 'Dalolatnomalar', 'Summa']);
  assert.deepEqual(r.slice(i + 2, i + 4).map(x => x.map(v)), [['T-01', 'Sinov Muallima', 2, 450000], ['X-01', 'Sinov Xodima', 1, 200000]]);
  assert.match(r[r.length - 1][0], /daromad solig‘idan ozod \(buxgalter, Sh-8 B20\)/);
  const m = offsetSheet(Object.assign({}, full, { masked: true }), ctx());
  assert.deepEqual(m.rows[3], ['Ismsiz nusxa (FD-28): xodimlar tabel kodi, o‘quvchilar ID bilan; to‘liq nusxa — Direktorda']);
  assert.deepEqual(m.rows[4], ['Sana', 'Dalolatnoma №', 'Ish haqi oyi', 'Xodim (tabel kodi)', 'O‘quvchi (ID)', 'Summa']);
  assert.deepEqual(m.rows[5].map(v), [46397, 'O‘H-1', '2026-12', 'T-01', 'S-1', 300000]);
  assert.ok(!/Sinov Muallima|Sinov Xodima|Sinov Bola/.test(flat(m)), 'ismsiz nusxada ism yo‘q');
  assert.equal(m.cols.length, 6);
  const ru = offsetSheet(full, ctx({ lang: 'ru' }));
  assert.equal(ru.rows[5][1], 'ВЗ-1');
  assert.match(ru.rows[ru.rows.length - 1][0], /освобождается от НДФЛ/);
  const none = offsetSheet(Object.assign({}, base, { offsets: [] }), ctx());
  assert.deepEqual(none.rows[5], ['Shu oyda o‘zaro hisob yo‘q']);
  assert.ok(!none.rows.some(x => x[0] === 'Xodim bo‘yicha jami'));
});

test('E6 xodim farzandi chegirmasi: asosiy narx, chegirma, hisoblangan, holat; bog‘lanishsiz — ogohlantirish; buxgalter xulosasi izohi; ismsiz', () => {
  const sh = staffDiscSheet(full, ctx());
  const r = sh.rows;
  assert.deepEqual(r[4], ['Xodim (tabel kodi)', 'Xodim F.I.Sh.', 'O‘quvchi (ID)', 'O‘quvchi F.I.Sh.', 'Asosiy narx', 'Chegirma', 'Hisoblangan', 'Hisob holati']);
  assert.deepEqual(r[5].map(v), ['T-01', 'Sinov Muallima', 'S-1', 'Sinov Bola Bir', 1000000, 500000, 500000, 'to‘langan']);
  assert.deepEqual(r[6].map(v), ['—', '', 'S-4', 'Sinov Bola To‘rt', 900000, 450000, 450000, 'to‘lanmagan']);
  const tot = r.find(x => x[0] === 'Jami');
  assert.deepEqual(tot.map(v), ['Jami', '', '', '', 1900000, 950000, 950000]);
  assert.ok(r.some(x => /^Diqqat: tabel kodisiz hisoblarda «xodim farzandi» bog‘lanishi yo‘q — o‘quvchi kartasini tekshiring: 1$/.test(x[0] || '')));
  assert.match(r[r.length - 1][0], /moddiy nafi \(SK 376-modda\) hisoblanadimi .* tizim soliq hisoblamaydi\.$/);
  const m = staffDiscSheet(Object.assign({}, full, { masked: true }), ctx());
  assert.deepEqual(m.rows[4], ['Xodim (tabel kodi)', 'O‘quvchi (ID)', 'Asosiy narx', 'Chegirma', 'Hisoblangan', 'Hisob holati']);
  assert.deepEqual(m.rows.find(x => x[0] === 'Jami').map(v), ['Jami', '', 1900000, 950000, 950000]);
  assert.ok(!/Sinov Muallima|Sinov Bola/.test(flat(m)));
  const ru = staffDiscSheet(full, ctx({ lang: 'ru' }));
  assert.deepEqual([ru.rows[5][7], ru.rows[6][7]], ['оплачен', 'не оплачен']);
  const none = staffDiscSheet(Object.assign({}, base, { staffDiscounts: [] }), ctx());
  assert.deepEqual(none.rows[5], ['Shu oyda xodim farzandi chegirmali hisob yo‘q']);
});

test('E7 vedomost: holati va tasdiq sanasi (Toshkent vaqti), qatorlar, qoldiq = to‘lanadigan − to‘langan, jamlar, ortiqcha to‘lov, ismsiz, vedomost yo‘q', () => {
  const sh = payrollSheet(full, ctx());
  const r = sh.rows;
  assert.equal(r[2][0], '2027-yil yanvar · vedomost: tasdiqlangan (28.01.2027)');
  assert.deepEqual(r[4], ['Tabel kodi', 'Toifa', 'F.I.Sh.', 'Hisoblangan', 'Ushlanma', 'O‘rinbosarlik', 'Avans', 'Oldingi oylar qoldig‘i', 'To‘lanadigan',
    'To‘landi: naqd', 'To‘landi: karta', 'To‘landi: o‘zaro hisob', 'To‘landi: boshqa', 'To‘lanmagan qoldiq']);
  assert.deepEqual(r[5].map(v), ['X-01', 'xodim', 'Sinov Xodima', 3000000, 0, 0, 500000, -100000, 2400000, 2400000, 0, 0, 1000, -1000]);
  assert.deepEqual(r[6].map(v), ['T-01', 'o‘qituvchi', 'Sinov Muallima', 5000000, 100000, 50000, 1000000, 0, 3950000, 2000000, 1000000, 300000, 0, 650000]);
  const tot = r.find(x => x[0] === 'Jami');
  assert.deepEqual(tot.map(v), ['Jami', '', '', 8000000, 100000, 50000, 1500000, -100000, 6350000, 4400000, 1000000, 300000, 1000, 649000]);
  assert.ok(r.some(x => /^Diqqat: to‘langani «To‘lanadigan»dan ko‘p \(ortiqchasi keyingi oyga o‘tadi\): X-01$/.test(x[0] || '')));
  assert.match(r[r.length - 1][0], /buxgalter 1C dagi fond bilan solishtirib, yozma tasdiqlaydi \(Sh-8 B19, FD-44\)/);
  const m = payrollSheet(Object.assign({}, full, { masked: true }), ctx());
  assert.equal(m.rows[4].length, 13);
  assert.deepEqual(m.rows[6].slice(0, 3).map(v), ['T-01', 'o‘qituvchi', 5000000]);
  assert.equal(m.rows.find(x => x[0] === 'Jami').length, 13);
  assert.ok(!/Sinov Muallima|Sinov Xodima/.test(flat(m)));
  const ru = payrollSheet(full, ctx({ lang: 'ru' }));
  assert.equal(ru.rows[2][0], 'Январь 2027 г. · ведомость: утверждена (28.01.2027)');
  assert.deepEqual([ru.rows[5][1], ru.rows[6][1]], ['сотрудник', 'учитель']);
  const none = payrollSheet(Object.assign({}, base, { payroll: null }), ctx());
  assert.deepEqual([none.rows[2][0], none.rows[5]], ['2027-yil yanvar', ['Shu oy vedomosti tuzilmagan']]);
  const draft = payrollSheet(Object.assign({}, base, { payroll: { status: 'draft', approvedAt: null, lines: [] } }), ctx());
  assert.deepEqual([draft.rows[2][0], draft.rows[5]], ['2027-yil yanvar · vedomost: qoralama', ['Vedomostda qator yo‘q']]);
});
