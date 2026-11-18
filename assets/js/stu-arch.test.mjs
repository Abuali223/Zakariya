// stu-arch.test.mjs — O'quvchilar ARXIVI (egasi 2026-11-18): admin.html STU-ARCH bloki (sof yordamchilar) fayldan o'qib sinaladi.
//   node --test assets/js/stu-arch.test.mjs
//   Qoida: holati 'chiqdi' va chiqqan kuni (exitAt, bo'lmasa stopFrom) bugun yoki o'tgan (yoki sana yo'q) — arxivda: faol ro'yxat,
//   sonlar, sinf tanlovlari va jurnallardan chiqadi. Kelajak sana — shu kungacha ro'yxatda. Bitiruvchi — sababi 'bitirdi'.
//   Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const block = (() => { const a = ADM.indexOf('// STU-ARCH:BEGIN'), b = ADM.indexOf('// STU-ARCH:END'); return a >= 0 && b > a ? ADM.slice(a, b) : ''; })();
const A = (() => {
  // tkDay — admin.html'dagi Toshkent kuni; sinovda doimiy kun (today berilmagan chaqiruvlar uchun).
  const ctx = vm.createContext({ tkDay: () => '2026-11-18' });
  vm.runInContext(block + '\n;this.__a = { addDaysStr, stuExitDay, stuArchived, stuGraduate, activeRoster, stuInPeriod, stuExitPatch, STU_D };', ctx);
  return ctx.__a;
})();
const T = '2026-11-18';

test('blok bitta va yordamchilar bor', () => {
  assert.ok(block.length > 0);
  assert.equal((ADM.match(/STU-ARCH:BEGIN/g) || []).length, 1);
  assert.equal((ADM.match(/function stuArchived\(/g) || []).length, 1, 'stuArchived bitta');
  assert.equal((ADM.match(/function addDaysStr\(/g) || []).length, 1, 'addDaysStr bitta (blok ichida)');
});

test('stuExitDay: exitAt ustun, bo‘lmasa stopFrom; noto‘g‘ri sana — e’tiborsiz', () => {
  assert.equal(A.stuExitDay({ exitAt: '2026-11-10', stopFrom: '2026-09-01' }), '2026-11-10');
  assert.equal(A.stuExitDay({ stopFrom: '2026-09-01T00:00:00Z' }), '2026-09-01');
  assert.equal(A.stuExitDay({ exitAt: 'yo‘q', stopFrom: '2026-09-01' }), '2026-09-01');
  assert.equal(A.stuExitDay({}), ''); assert.equal(A.stuExitDay(null), '');
});

test('stuArchived: faqat «chiqdi» va chiqqan kuni kelgan (shu kuni ham) yoki sanasiz', () => {
  assert.equal(A.stuArchived({ payStatus: '' }, T), false);
  assert.equal(A.stuArchived({ payStatus: 'faol' }, T), false);
  assert.equal(A.stuArchived({ payStatus: 'sinov' }, T), false);
  assert.equal(A.stuArchived({ payStatus: 'muzlatilgan', stopFrom: '2026-01-01' }, T), false, 'muzlatilgan — arxiv emas (qaytadi)');
  assert.equal(A.stuArchived({ payStatus: 'chiqdi', exitAt: '2026-11-17' }, T), true);
  assert.equal(A.stuArchived({ payStatus: 'chiqdi', exitAt: T }, T), true, 'chiqarilgan kunining o‘zida — darhol arxivda (son kamayadi)');
  assert.equal(A.stuArchived({ payStatus: 'chiqdi', exitAt: '2026-11-30' }, T), false, 'kelajak sana — shu kungacha ro‘yxatda');
  assert.equal(A.stuArchived({ payStatus: 'chiqdi' }, T), true, 'sanasiz chiqdi — arxivda');
  assert.equal(A.stuArchived({ payStatus: 'chiqdi', stopFrom: '2026-12-05' }, T), false, 'eski yozuv (exitAt yo‘q) — stopFrom bo‘yicha');
  assert.equal(A.stuArchived({ payStatus: 'chiqdi', stopFrom: '2026-09-15', exitAt: '2026-12-01' }, T), false, 'muzlatilgandan keyin kelajak sana bilan chiqarilgan');
  assert.equal(A.stuArchived({ payStatus: 'chiqdi', exitAt: '2026-11-10' }), true, 'today berilmasa — tkDay()');
  assert.equal(A.stuArchived(null, T), false);
});

test('activeRoster: arxivdagilar chiqariladi, kelajak sanalilar qoladi; tartib saqlanadi', () => {
  const L = [
    { _id: 'a', payStatus: '' }, { _id: 'b', payStatus: 'chiqdi', exitAt: '2026-11-01' }, { _id: 'c', payStatus: 'chiqdi', exitAt: '2026-12-01' },
    { _id: 'd', payStatus: 'muzlatilgan' }, { _id: 'e', payStatus: 'chiqdi', exitReason: 'bitirdi', exitAt: '2026-06-01' }, { _id: 'f', payStatus: 'sinov' },
  ];
  // massiv vm kontekstida yaratiladi — solishtirish uchun shu kontekstga ko'chiriladi (Array.from)
  assert.deepEqual(Array.from(A.activeRoster(L, T), x => x._id), ['a', 'c', 'd', 'f']);
  assert.equal(A.activeRoster(null, T).length, 0);
});

test('stuGraduate', () => {
  assert.equal(A.stuGraduate({ exitReason: 'bitirdi' }), true);
  assert.equal(A.stuGraduate({ exitReason: 'kochdi' }), false);
  assert.equal(A.stuGraduate(null), false);
});

test('stuInPeriod: jurnalda arxivdagi o‘quvchi — shu davrda chiqqan yoki yozuvi bo‘lsa', () => {
  const left = { payStatus: 'chiqdi', exitAt: '2026-11-10' }, grad = { payStatus: 'chiqdi', exitReason: 'bitirdi', exitAt: '2026-05-31' };
  assert.equal(A.stuInPeriod({ payStatus: '' }, '2026-09-01', false, T), true, 'faol — doim');
  assert.equal(A.stuInPeriod(left, '2026-09-01', false, T), true, 'shu o‘quv yilida chiqqan');
  assert.equal(A.stuInPeriod(left, '2026-12-01', false, T), false, 'keyingi oy jurnali — yo‘q');
  assert.equal(A.stuInPeriod(left, '2026-12-01', true, T), true, 'shu oyga yozuvi bor — ko‘rinadi');
  assert.equal(A.stuInPeriod(grad, '2026-09-01', false, T), false, 'o‘tgan yil bitiruvchisi yangi o‘quv yili ro‘yxatiga tushmaydi');
  assert.equal(A.stuInPeriod({ payStatus: 'chiqdi' }, '2026-09-01', false, T), false, 'sanasiz chiqdi — faqat yozuvi bo‘lsa');
  assert.equal(A.stuInPeriod({ payStatus: 'chiqdi', exitAt: '2026-12-01' }, '2027-01-01', false, T), true, 'hali chiqmagan (kelajak sana) — doim');
});

test('stuExitPatch: «⏯️ Holat» oynasidagi direktor qoidasi bilan bir xil', () => {
  // faol -> chiqdi
  assert.deepEqual({ ...A.stuExitPatch({ payStatus: '' }, '2027-05-31', 'bitirdi', ' 2026–2027 bitiruvchisi ', 'dir@x') },
    { payStatus: 'chiqdi', exitReason: 'bitirdi', exitNote: '2026–2027 bitiruvchisi', exitAt: '2027-05-31', exitBy: 'dir@x', stopFrom: '2027-05-31' });
  // muzlatilgan, ertaroq to'xtatilgan — to'lov ertaroq sanagacha qoladi (muzlatilgan kunlar qaytmaydi)
  const p1 = A.stuExitPatch({ payStatus: 'muzlatilgan', stopFrom: '2027-03-15' }, '2027-05-31', 'bitirdi', '', 'd');
  assert.equal(p1.stopFrom, '2027-03-15'); assert.equal(p1.exitAt, '2027-05-31'); assert.equal(p1.exitNote, null);
  // muzlatilgan, kechroq sana (kelajakdagi muzlatish) — bitiruv sanasi
  assert.equal(A.stuExitPatch({ payStatus: 'muzlatilgan', stopFrom: '2027-06-15' }, '2027-05-31', 'bitirdi', '', 'd').stopFrom, '2027-05-31');
  // sanasiz muzlatilgan — bitiruv sanasi
  assert.equal(A.stuExitPatch({ payStatus: 'muzlatilgan' }, '2027-05-31', 'bitirdi', '', 'd').stopFrom, '2027-05-31');
  // sinov — to'lov boshlanmagan: activeFrom = keyingi kun
  const p2 = A.stuExitPatch({ payStatus: 'sinov' }, '2027-05-31', 'bitirdi', '', 'd');
  assert.equal(p2.stopFrom, '2027-05-31'); assert.equal(p2.activeFrom, '2027-06-01');
  assert.ok(!('activeFrom' in A.stuExitPatch({ payStatus: '' }, '2027-05-31', 'bitirdi', '', 'd')), 'faolda activeFrom tegilmaydi');
});

test('admin.html: sonlar faol ro‘yxatdan; arxiv sahifasi va ma’lumotnoma ulangan', () => {
  // bosh sahifa (ikkala dizayn) — faol ro'yxat
  assert.ok(ADM.includes('dashCoreStats(activeRoster(students), users)'), 'klassik bosh sahifa');
  assert.ok(/const roster=activeRoster\(students, today\);[^\n]*\n\s*const C=dashCoreStats\(roster, users\);/.test(ADM), 'v2 bosh sahifa');
  // O'quvchilar sahifasi: jami va ro'yxat faol, arxivga havola
  assert.ok(ADM.includes("act=rows.filter(r=>!stuArchived(r, TD))") && ADM.includes('`Jami: ${act.length} ta o‘quvchi`'), 'O‘quvchilar: jami faol');
  assert.ok(ADM.includes('let filtered = act;'), 'O‘quvchilar: ro‘yxat faol');
  assert.ok(ADM.includes("$('#stu-arch').addEventListener('click', ()=>openTab('archive'))"), 'Arxiv tugmasi — «Arxiv» bo‘limi');
  assert.ok(ADM.includes("if(tab==='archive') return renderArchive();") && ADM.includes("keys:['enrollments','students','archive',"), 'Arxiv — menyu bo‘limi');
  assert.ok(/zavuch:\[[^\]]*'archive'\]/.test(ADM) && /reception:\['enrollments','students','archive'\]/.test(ADM), 'O‘IBDO‘ va qabulxona — Arxiv bo‘limi');
  // sinf tanlovlari: shu o'quv yilida o'qiganlar (bitirgan sinf o'quv yili oxirigacha qoladi); jurnallar — o'zlari saralaydi
  assert.ok(ADM.includes("if(!keepArchived){ const ay=acadYearStart(); students=(students||[]).filter(s=>stuInPeriod(s, ay)); }"), 'classGroupsMap — shu o‘quv yili');
  assert.ok(ADM.includes('keys.filter(k=>def.has(k) || ((classes[k]&&classes[k].list)||[]).some(s=>stuInPeriod(s, ay)))'), 'liveClassKeys — shu o‘quv yili');
  assert.equal((ADM.match(/const clsKeysU=\[\.\.\.CLS\.keys, /g) || []).length, 2, 'o‘qituvchi / foydalanuvchi oynasi: biriktirilgan sinf o‘chib ketmaydi');
  assert.equal((ADM.match(/classGroupsMap\(students, true\), keys=liveClassKeys\(classes,_allK\)/g) || []).length, 4, 'davomat, baho, monitoring, xarakteristika');
  assert.equal((ADM.match(/cls\.list\.filter\(s=>stuInPeriod\(s, /g) || []).length, 3, 'baho, monitoring, xarakteristika ro‘yxati davr bo‘yicha');
  // eski «Ketganlar» oynasi Arxivga qo'shildi
  assert.ok(!ADM.includes('function openLeavers('), 'openLeavers yo‘q');
  assert.ok(ADM.includes("['bitirdi','🎓 Maktabni tugatdi (bitiruvchi)']"), 'bitiruv sababi');
  // ma'lumotnoma: QR 'certificate', telefon / sog'liq / to'lov yo'q
  const a = ADM.indexOf("trWrap.id='rep-tr'"), b = ADM.indexOf('// Oylik xulosa muharriri');
  assert.ok(a > 0 && b > a, 'ma’lumotnoma bloki');
  const tr = ADM.slice(a, b);
  assert.ok(tr.includes("p_kind:'certificate'"), 'QR turi certificate');
  assert.ok(tr.includes("rpc('student_certificate'") && tr.indexOf("rpc('student_certificate'") < tr.indexOf("rpc('issue_doc_token'"), 'o‘zlashtirish — server yig‘masidan, QR dan OLDIN');
  for (const k of ["P('parentPhone')", "P('parentPhone2')", "P('health')", 'invRows', 'paidSum', 'dueSum', 'arcReasonLbl', 'exitNote']) assert.ok(!tr.includes(k), 'ma’lumotnomada yo‘q: ' + k);
  assert.ok(tr.includes('(${esc(bd)} yilda tug‘ilgan)'), 'tug‘ilgan sana esc (erkin matn)');
});
