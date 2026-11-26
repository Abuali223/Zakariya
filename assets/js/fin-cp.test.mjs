// fin-cp.js va fin-print.js (RP-10) sinovi (faqat sof qism):  node --test assets/js/fin-cp.test.mjs
//   Kontragent kartasi (F2.2): raqamli rekvizitlar, nom kaliti, tur tasdig'i, hisob raqami ko'rinishi, shartnoma holati, shakl → server
//   so'rovi (server bilan bir xil qoidalar), qidiruv va filtr, ko'chirma davri va fayl nomi; RP-10 chop etish va Excel varag'i
//   (yig'ma sof, ismsiz nusxa izohi, til, Excel sanasi va soni). Ma'lumotlar to'qima (STIR va hisob raqamlari 0 bilan — haqiqiy emas).
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import * as W from './fin-words.js';
import { cpDigits, cpNameKey, cpUnconf, fmtAcc, contractState, cpPayload, cpMatch, cpFilter, periodDefault, stmtFileName, CP_KIND, KIND_ORDER } from './fin-cp.js';
import { cpStatementRows, cpStatementHtml, cpStatementSheet } from './fin-print.js';

const NB = String.fromCharCode(160), NNB = String.fromCharCode(8239);
const card = (o = {}) => ({ kind: 'supplier', name: 'Sinov MChJ', stir: '000000201', account: '00000000000000000201', mfo: '00201', bankName: 'Sinov bank',
  contractNo: '№ 7', contractDate: '2027-01-15', contractUntil: '2027-12-31', note: 'sinov', ...o });

test('raqamli rekvizit: oddiy, bo‘linmas va tor bo‘shliqlar olib tashlanadi; boshqa belgi qoladi (server rad etadi)', () => {
  assert.equal(cpDigits(' 000 000' + NB + '201' + NNB), '000000201');
  assert.equal(cpDigits('0000-1'), '0000-1');
  assert.equal(cpDigits(null), '');
});
test('nom kaliti: apostrof turlari, bo‘shliqlar, katta-kichik harf', () => {
  assert.equal(cpNameKey('  Sinov  TA’MINOTCHI '), "sinov ta'minotchi");
  assert.equal(cpNameKey('Sinov taʻminotchi'), cpNameKey("sinov ta'minotchi"));
});
test('tur tasdig‘i: tasdiqlanmagan jismoniy shaxs / boshqa — yuridik shaxs hisoblanadi; yuridik turlar — tasdiq kerak emas', () => {
  assert.equal(cpUnconf({ kind: 'person' }), true);
  assert.equal(cpUnconf({ kind: 'other', confirmed: false }), true);
  assert.equal(cpUnconf({ kind: 'person', kindConfirmedBy: 'U1' }), false);
  assert.equal(cpUnconf({ kind: 'person', confirmed: true }), false);
  assert.equal(cpUnconf({ kind: 'supplier' }), false);
  assert.deepEqual(KIND_ORDER.slice().sort(), Object.keys(CP_KIND).sort());
});
test('hisob raqami ko‘rinishi: 5 · 3 · 1 · 8 · 3; 20 raqam bo‘lmasa — o‘z holicha', () => {
  assert.equal(fmtAcc('00000000000000000201'), '00000 000 0 00000000 201');
  assert.equal(fmtAcc('0000 0000 0000 0000 0201'), '00000 000 0 00000000 201');
  assert.equal(fmtAcc('123'), '123');
  assert.equal(fmtAcc(''), '');
});
test('shartnoma holati: yo‘q, muddatsiz, amalda, 30 kun ichida tugaydi, muddati o‘tgan', () => {
  assert.equal(contractState({}, '2027-02-10').st, 'none');
  assert.deepEqual(contractState({ contractNo: '7', contractDate: '2027-01-15' }, '2027-02-10'), { st: 'ok', txt: '№ 7 · 15.01.2027' });
  assert.equal(contractState({ contractNo: '7', contractDate: '2027-01-15', contractUntil: '2027-12-31' }, '2027-02-10').st, 'ok');
  assert.match(contractState({ contractNo: '7', contractDate: '2027-01-15', contractUntil: '2027-03-12' }, '2027-02-10').txt, /tugaydi: 12\.03\.2027/);
  assert.equal(contractState({ contractNo: '7', contractDate: '2027-01-15', contractUntil: '2027-03-13' }, '2027-02-10').st, 'ok', '31 kun — hali amalda');
  const e = contractState({ contractNo: '7', contractDate: '2026-01-15', contractUntil: '2027-02-09' }, '2027-02-10');
  assert.equal(e.st, 'expired'); assert.match(e.txt, /muddati o‘tgan \(09\.02\.2027\)/);
});
test('so‘rov: yangi karta — bo‘shliqlar olib tashlanadi, shartnoma №siz, bo‘sh sanalar null', () => {
  const r = cpPayload(card({ stir: '000 000 201', account: '0000 0000 0000 0000 0201', mfo: ' 00201 ', name: '  Sinov MChJ ' }), '2027-02-10');
  assert.equal(r.err, undefined);
  assert.deepEqual(r.p, { kind: 'supplier', name: 'Sinov MChJ', stir: '000000201', account: '00000000000000000201', mfo: '00201', bankName: 'Sinov bank',
    contractNo: '7', contractDate: '2027-01-15', contractUntil: '2027-12-31', note: 'sinov', active: true });
  const b = cpPayload({ kind: 'bank', name: 'Sinov Bank filiali', mfo: '00301' }, '2027-02-10');
  assert.equal(b.err, undefined); assert.equal(b.p.contractDate, null); assert.equal(b.p.account, '');
});
test('so‘rov: mavjud karta — id va versiya; dupOk; nofaol', () => {
  const r = cpPayload(card({ id: 'cp_1', rev: '3', active: false, dupOk: true }), '2027-02-10');
  assert.equal(r.p.id, 'cp_1'); assert.equal(r.p.rev, 3); assert.equal(r.p.dupOk, true); assert.equal(r.p.active, false);
  assert.equal(cpPayload(card(), '2027-02-10').p.id, undefined);
});
test('so‘rov: tur, nom, STIR (9 raqam; JShShIR yo‘q; o‘zgarmagan eski qiymat — rad etilmaydi)', () => {
  assert.match(cpPayload(card({ kind: 'xodim' })).err, /turini tanlang/);
  assert.match(cpPayload(card({ kind: 'toString' })).err, /turini tanlang/);
  assert.match(cpPayload(card({ name: ' a ' })).err, /2–200/);
  assert.match(cpPayload(card({ stir: '00000020' })).err, /STIR — 9 ta raqam/);
  assert.match(cpPayload(card({ kind: 'person', stir: '00000000000201' })).err, /JShShIR/);
  assert.equal(cpPayload(card({ stir: '12345678', stirOld: '12345678' })).err, undefined, 'eski noto‘g‘ri STIR o‘zgarmasa');
  assert.match(cpPayload(card({ stir: '1234567', stirOld: '12345678' })).err, /STIR/);
  assert.equal(cpPayload(card({ stir: '' })).err, undefined);
});
test('so‘rov: hisob raqami (20, uzunlik xabarda), MFO (5), hisob raqami MFO‘siz, bank nomi', () => {
  assert.equal(cpPayload(card({ account: '0000000000000000020' })).err, 'Hisob raqami — 20 ta raqam (hozir: 19)');
  assert.match(cpPayload(card({ account: '0000000000000000020A' })).err, /20 ta raqam/);
  assert.match(cpPayload(card({ mfo: '0020' })).err, /MFO kodi — 5/);
  assert.match(cpPayload(card({ mfo: '' })).err, /MFO kodini ham/);
  assert.match(cpPayload(card({ bankName: 'b'.repeat(201) })).err, /Bank nomi/);
});
test('so‘rov: shartnoma — raqami va sanasi birga, kelajak sana, muddat sanadan oldin, sana shakli; izoh', () => {
  const t = '2027-02-10';
  assert.match(cpPayload(card({ contractNo: '' }), t).err, /raqamini kiriting/);
  assert.match(cpPayload(card({ contractDate: '', contractUntil: '' }), t).err, /sanasini kiriting/);
  assert.match(cpPayload(card({ contractNo: '7'.repeat(61) }), t).err, /60 belgidan/);
  assert.match(cpPayload(card({ contractDate: '2027-02-11', contractUntil: '' }), t).err, /bugundan keyin/);
  assert.equal(cpPayload(card({ contractDate: '2027-02-10', contractUntil: '' }), t).err, undefined);
  assert.match(cpPayload(card({ contractUntil: '2027-01-14' }), t).err, /muddati uning sanasidan oldin/);
  assert.match(cpPayload(card({ contractDate: '15.01.2027' }), t).err, /sanasi noto‘g‘ri/);
  assert.match(cpPayload(card({ contractDate: '1990-12-31', contractUntil: '' }), t).err, /sanasi noto‘g‘ri/);
  assert.match(cpPayload(card({ note: 'i'.repeat(501) }), t).err, /Izoh 500/);
  assert.equal(cpPayload(card({ contractNo: '#12', contractDate: '2027-01-15', contractUntil: '' }), t).p.contractNo, '12');
});
test('qidiruv va filtr: nom, STIR / hisob raqami (kamida 3 raqam), shartnoma №; tur va faollik; nom bo‘yicha tartib', () => {
  const L = [
    { id: 'a', kind: 'supplier', name: 'Sinov Ta’minotchi', stir: '000000101', account: '', contractNo: 'SH-12', active: true },
    { id: 'b', kind: 'bank', name: 'Alfa sinov bank', stir: '', account: '00000000000000000777', mfo: '00777', active: true },
    { id: 'c', kind: 'supplier', name: 'Eski sinov', stir: '000000105', active: false },
  ];
  assert.deepEqual(cpFilter(L, { q: "ta'minot", act: 'on' }).map(c => c.id), ['a']);
  assert.deepEqual(cpFilter(L, { q: '777', act: 'on' }).map(c => c.id), ['b']);
  assert.deepEqual(cpFilter(L, { q: '10', act: 'all' }).map(c => c.id), [], 'raqam bo‘yicha — kamida 3 raqam');
  assert.deepEqual(cpFilter(L, { q: '0000001', act: 'all' }).map(c => c.id), ['c', 'a']);
  assert.deepEqual(cpFilter(L, { q: 'sh-12' }).map(c => c.id), ['a']);
  assert.deepEqual(cpFilter(L, { act: 'off' }).map(c => c.id), ['c']);
  assert.deepEqual(cpFilter(L, { kind: 'supplier', act: 'all' }).map(c => c.id), ['c', 'a']);
  assert.deepEqual(cpFilter(L, {}).map(c => c.id), ['b', 'a']);
  assert.equal(cpMatch(L[0], ''), true);
});
test('ko‘chirma davri va fayl nomi (ID bilan; ismsiz nusxada «-ismsiz»)', () => {
  assert.deepEqual(periodDefault('2027-02-10'), { from: '2027-01-01', to: '2027-02-10' });
  assert.deepEqual(periodDefault(''), { from: '', to: '' });
  assert.equal(stmtFileName({ cp: { id: 'cp_ab12' }, from: '2027-01-01', to: '2027-01-31' }), 'RP-10_cp_ab12_2027-01-01_2027-01-31.xlsx');
  assert.equal(stmtFileName({ cp: { id: 'cp/../x' }, from: '2027-01-01', to: '2027-01-31', masked: true }), 'RP-10_cpx_2027-01-01_2027-01-31-ismsiz.xlsx');
});

const ST = {
  cp: { id: 'cp1', kind: 'supplier', name: 'Sinov <MChJ>', stir: '000000101', account: '00000000000000000201', mfo: '00201', bankName: 'Sinov bank',
        contractNo: '7', contractDate: '2027-01-15', contractUntil: null, active: true },
  org: { nameUz: 'Sinov maktabi', stir: '000000001', printLang: 'uz-cyrl' }, chief: 'Sinov Bosh Buxgalter', me: 'Sinov Moliyachi',
  from: '2027-01-01', to: '2027-01-31', masked: false,
  opening: { in: 0, out: 300000 }, totals: { in: 100000, out: 2000000, n: 3 }, closing: { in: 100000, out: 2300000 },
  rows: [
    { day: '2027-01-05', src: 'cash', ref: 'd1', doc: 'KO-2 № 3', method: 'cash', op: 'out_expense', opName: 'Xarajat', opNameRu: 'Расход', arts: ['EX-32'], text: 'Qog‘oz <b>', in: 0, out: 500000 },
    { day: '2027-01-06', src: 'cash', ref: 'd2', doc: 'KO-1 № 4', method: 'cash', op: 'in_other', opName: 'Boshqa kirim', opNameRu: 'Прочий приход', arts: ['IN-06'], text: '', in: 100000, out: 0 },
    { day: '2027-01-08', src: 'exp', ref: 'x1', doc: '№ 145 · 07.01.2027', method: 'bank', op: 'expense', opName: 'Xarajat', opNameRu: 'Расход', arts: ['EX-11', 'EX-13'], text: 'Yanvar', in: 0, out: 1500000 },
  ],
  articles: { 'EX-32': { uz: 'Kanselyariya', ru: 'Канцтовары' }, 'IN-06': { uz: 'Boshqa daromad', ru: '' }, 'EX-11': { uz: 'Elektr energiyasi', ru: 'Электроэнергия' }, 'EX-13': { uz: 'Suv', ru: 'Вода' } },
};
test('RP-10: yig‘ma sof (berildi − olindi) davr boshigacha qiymatdan boshlanadi', () => {
  assert.deepEqual(cpStatementRows(ST).map(r => r.bal), [800000, 700000, 2200000]);
  assert.deepEqual(cpStatementRows({}), []);
});
test('RP-10 chop etish: sarlavha, rekvizitlar, qatorlar, jamlar, imzo; HTML qochiriladi; ichki hisobot — o‘zbek lotin', () => {
  const h = cpStatementHtml(ST, { org: ST.org, printedBy: ST.me, printedAt: '2027-02-10T05:00:00Z' }, W);
  assert.match(h, /^<!DOCTYPE html>/);
  assert.match(h, /KONTRAGENT KO‘CHIRMASI/);
  assert.match(h, /Davr: 01\.01\.2027 – 31\.01\.2027/);
  assert.match(h, /Sinov &lt;MChJ&gt;/); assert.doesNotMatch(h, /<MChJ>/);
  assert.match(h, /Qog‘oz &lt;b&gt;/);
  assert.match(h, /00000000000000000201 · MFO 00201 · Sinov bank/);
  assert.match(h, /№ 7 \(15\.01\.2027\)/);
  assert.match(h, /EX-11 Elektr energiyasi; EX-13 Suv/);
  assert.match(h, /3 ta operatsiya/);
  assert.match(h, /Sinov Bosh Buxgalter/); assert.match(h, /Sinov Moliyachi/);
  assert.doesNotMatch(h, /Ismsiz nusxa/);
  assert.match(h, /2 200 000/, 'yig‘ma sof');
});
test('RP-10 chop etish: ismsiz nusxa (ID, izoh), bo‘sh davr, rus tili (statiya va operatsiya nomlari)', () => {
  const m = cpStatementHtml({ ...ST, masked: true, cp: { id: 'cp3', kind: 'person', contractNo: '', active: true }, rows: [], totals: { in: 0, out: 0, n: 0 } }, {}, W);
  assert.match(m, /Ismsiz nusxa \(FD-28\)/); assert.match(m, /ID cp3/); assert.match(m, /jismoniy shaxs/); assert.match(m, /Davrda operatsiya yo‘q/);
  const r = cpStatementHtml(ST, { org: { ...ST.org, printLang: 'ru' } }, W);
  assert.match(r, /ВЫПИСКА ПО КОНТРАГЕНТУ/); assert.match(r, /Прочий приход/); assert.match(r, /EX-11 Электроэнергия/); assert.match(r, /IN-06 Boshqa daromad/, 'ruscha nomi bo‘lmasa — o‘zbekcha');
  assert.match(r, /ИНН/);
});
test('RP-10 Excel varag‘i: sarlavha, rekvizitlar, sarlavha qatori, Excel sanasi va soni, jamlar; ismsiz izoh; SheetJS bilan o‘qiladi', () => {
  const sh = cpStatementSheet(ST, { org: ST.org });
  assert.equal(sh.name, 'RP-10');
  assert.equal(sh.rows[0][0], 'Sinov maktabi');
  const hi = sh.rows.findIndex(r => r[0] === '№');
  assert.ok(hi > 0);
  const r1 = sh.rows[hi + 1];
  assert.equal(r1[0], 1); assert.deepEqual(r1[1], { t: 'n', v: 46392, z: 'dd\\.mm\\.yyyy' });
  assert.equal(r1[2], 'KO-2 № 3'); assert.match(r1[3], /^Xarajat — EX-32 Kanselyariya — Qog‘oz <b>$/); assert.equal(r1[4], 'naqd');
  assert.equal(r1[5], ''); assert.deepEqual(r1[6], { t: 'n', v: 500000, z: '#,##0.00' }); assert.deepEqual(r1[7], { t: 'n', v: 800000, z: '#,##0.00' });
  assert.ok(sh.rows.some(r => r[3] === 'Davr oxirigacha' && r[5].v === 100000 && r[6].v === 2300000));
  assert.ok(sh.rows.some(r => r[3] === 'Sof: berildi − olindi' && r[7].v === 2200000));
  assert.ok(!sh.rows.some(r => String(r[0]).startsWith('Ismsiz')));
  const m = cpStatementSheet({ ...ST, masked: true, cp: { id: 'cp3', kind: 'person' } }, {});
  assert.ok(m.rows.some(r => String(r[0]).startsWith('Ismsiz nusxa (FD-28)')));
  assert.ok(m.rows.some(r => r[0] === 'Kontragent' && r[1] === 'ID cp3'));
  const require = createRequire(import.meta.url), X = require('../../vendor/xlsx/xlsx.mini.min.js');
  const ws = X.utils.aoa_to_sheet(sh.rows), back = X.utils.sheet_to_json(ws, { header: 1, raw: true });
  assert.equal(back[hi + 1][6], 500000);
  assert.equal(back[hi + 1][1], 46392);
});
