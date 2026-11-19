// stu-report.test.mjs — o'quvchi ma'lumotnomasi oynasi va «🖨 Ichki hisobot» (admin.html openStudentReport), audit A3-04 qoldig'i
//   (mustaqil tekshiruv 3-raund): qabulxona davomat / monitoring / baho / xarakteristika / oylik xulosa jadvallarini RLS bilan o'qiy
//   olmaydi (D6) — oyna va ichki hisobot bu bo'limlarni «Ma'lumot yo'q», «Umumiy davomat —» deb chiqarardi (go'yo yozuv yo'qdek).
//   Endi ular 📨 ma'lumotnoma / 🎓 rasmiy profil bilan bir xil yig'madan (student_certificate); yig'mada yo'q bo'lim (oylik xulosa) yoki
//   yig'ma olinmasa — «qabulxona uchun ko'rsatilmaydi». Direktor / O'IBDO' — avvalgidek o'zi o'qigan jadvallardan (yig'ma chaqirilmaydi).
//   Funksiya admin.html'dan nomi bo'yicha o'qiladi; baza (RLS natijasi) va DOM — soxta. Ma'lumotlar to'qima («Sinov …», 99800… raqam).
//   node --test assets/js/stu-report.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const AL = ADM.split('\n');
// Yuqori darajadagi funksiya (0-ustundan): bir qatorli yoki tanasi surilgan va «}» bilan yopiladigan ko'p qatorli.
function fn(name) {
  const i = AL.findIndex(l => l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`));
  if (i < 0) return '';
  const out = [AL[i]];
  for (let j = i + 1; j < AL.length; j++) { const l = AL[j]; if (l === '' || /^\s/.test(l)) { out.push(l); continue; } if (l.startsWith('}')) out.push(l); break; }
  return out.join('\n');
}
const topConst = name => AL.find(l => new RegExp(`^const ${name}\\s*=`).test(l)) || '';
const SRC = [topConst('esc'), topConst('QUARTERS'), topConst('PROV_LBL'), ...['fmtSom', 'fmtWhen', 'gradeName', 'classKeyOf', 'supervisedClasses', 'stuGradesHtml', 'openStudentReport'].map(fn)].join('\n');

const ROW = { _id: 'IQ-0701', studentId: 'IQ-0701', name: 'Sinov Yetti', grade: 7, classLetter: 'B', lang: 'uz', score: 88 };
const PRIV = { birthDate: '2015-03-04', pinfl: '12345678901234', parentPhone: '998001112233', address: 'Sinov ko‘chasi 1' };
const INV = [{ id: 'inv1', studentId: 'IQ-0701', month: '2026-10', amount: 1900000, status: 'paid', provider: 'cash', paidAt: '2026-10-05' }];
// student_certificate javobi (student-archive.sql): baho, davomat soni, tasdiqlangan monitoring o'rtachasi, xarakteristikalar, fan izohlari
const CERT = {
  sid: 'IQ-0701',
  grades: [{ year: '2026-2027', subjects: { Matematika: { q1: 5, q2: 4 } } }],
  att: { present: 15, late: 3, absent: 2, sick: 4, total: 20 },
  mon: [{ subject: 'Fizika', avg: 88 }, { subject: 'Matematika', avg: 92 }],
  char: { term: '2026-2027-q1', text: 'Sinov: faol o‘quvchi' },
  chars: [{ term: '2026-2027-q1', text: 'Sinov: faol o‘quvchi', by: 'Sinov Kurator', at: '2026-10-20T10:00:00+05:00' }],
  notes: [{ term: '2026-2027-q1', subject: 'Fizika', text: 'Sinov: tajribalarda faol', by: 'Sinov Ustoz', at: '2026-10-21T10:00:00+05:00' }],
  ach: [],
};

function env({ role = 'reception', isAdmin = false, cert = CERT, certErr = null, rows = { invoices: INV } } = {}) {
  const els = {}, calls = { rpc: [], reads: [], printed: [] };
  // innerHTML / appendChild bilan qo'shilgan id'lar $('#id') bilan topiladi (haqiqiy DOM kabi).
  const reg = h => { const re = /id="([^"]+)"/g; let m; while ((m = re.exec(h))) els['#' + m[1]] = mk(); };
  function mk() {
    const e = { style: {}, onclick: null, disabled: false, value: '', checked: true, children: [], _h: '' };
    Object.defineProperty(e, 'innerHTML', { get: () => e._h, set: h => { e._h = String(h); reg(e._h); } });
    e.appendChild = c => { e.children.push(c); reg(c.innerHTML || ''); return c; };
    return e;
  }
  for (const k of ['#modal', '#modal .modal-b', '#modal .modal-f']) els[k] = mk();
  const ctx = vm.createContext({
    SESSION: { role, isAdmin, roles: [role], homeroomClasses: [], assignedClasses: [] },
    $: s => els[s] || null, document: { createElement: () => mk() }, openModal: () => {}, closeModal: () => {}, renderMath: () => {},
    db: {}, doc: (_d, c, id) => ({ c, id }), collection: (_d, c) => c, where: (f, op, v) => ({ f, op, v }), query: (c, w) => ({ c, w }),
    getDoc: async ref => { calls.reads.push(ref.c); return ref.c === 'student_private' ? { exists: () => true, data: () => ({ ...PRIV }) } : { exists: () => false, data: () => ({}) }; },
    getDocs: async q => { calls.reads.push(q.c); return { docs: (rows[q.c] || []).map((d, i) => ({ id: d.id || q.c + i, data: () => ({ ...d }) })) }; },
    rpc: async (name, args) => { calls.rpc.push([name, { ...args }]); if (certErr) throw certErr; return cert; },
    printHTML: h => calls.printed.push(h), toast: () => {}, cache: {}, renderStudents: () => {}, openRecordPayment: () => {},
  });
  vm.runInContext(SRC + '\n;this.__open = openStudentReport;', ctx);
  return { open: () => ctx.__open(ROW._id, { ...ROW }), els, calls, body: () => els['#modal .modal-b'].innerHTML };
}
const section = (html, title) => { const a = html.indexOf(`<h4 class="rep-h">${title}`); const b = html.indexOf('<h4 class="rep-h">', a + 10); return a < 0 ? '' : html.slice(a, b < 0 ? undefined : b); };

test('openStudentReport va yordamchilari topildi', () => {
  for (const n of ['openStudentReport', 'stuGradesHtml', 'fmtWhen', 'fmtSom']) assert.ok(fn(n).length > 0, n);
  assert.ok(topConst('QUARTERS') && topConst('PROV_LBL') && topConst('esc'));
});

test('A3-04 qoldig‘i: qabulxona — davomat, monitoring, baholar, xarakteristika student_certificate yig‘masidan (oynada ham, ichki hisobotda ham)', async () => {
  const E = env();
  await E.open();
  const h = E.body();
  assert.deepEqual(E.calls.rpc, [['student_certificate', { p_sid: 'IQ-0701' }]], 'yig‘ma bir marta, hujjat id bilan');
  assert.match(section(h, 'Davomat'), /Umumiy davomat<\/td><td><b>90%<\/b>/, 'avval: «Umumiy davomat —»');
  assert.match(section(h, 'Davomat'), /15 \/ 3 \/ 2 \(jami 20 kun\)/);
  assert.match(h, /Davomat<\/td><td><b>90%<\/b>/, 'yuqoridagi jadvaldagi «Davomat» qatori ham');
  assert.match(section(h, 'Monitoring'), /<td>Fizika<\/td><td style="text-align:center">88<\/td>.*<td>Matematika<\/td><td style="text-align:center">92<\/td>/s);
  assert.match(section(h, 'Baholar'), /2026-2027-o‘quv yili[\s\S]*<td>Matematika<\/td><td style="text-align:center">5<\/td><td style="text-align:center">4<\/td>/);
  assert.match(section(h, 'Xarakteristika'), /Sinov: faol o‘quvchi[\s\S]*Sinov Kurator[\s\S]*Fizika[\s\S]*Sinov: tajribalarda faol/);
  assert.match(section(h, 'O‘qituvchi xulosasi'), /Qabulxona uchun ko‘rsatilmaydi\./, 'oylik xulosa yig‘mada yo‘q — «ko‘rsatilmaydi», «Yozuv yo‘q» emas');
  for (const t of ['Davomat', 'Monitoring', 'Baholar', 'Xarakteristika', 'O‘qituvchi xulosasi']) {
    assert.doesNotMatch(section(h, t), /Ma’lumot yo‘q|Yozuv yo‘q/, `${t}: bo‘sh deb ko‘rsatilmaydi`);
  }
  // To'lovlar bo'limi o'zgarmagan (qabulxona fakturalarni RLS bilan o'qiydi); sog'liq / tibbiy jadvallar o'qilmaydi.
  assert.match(section(h, 'To‘lovlar'), /2026-10[\s\S]*To‘landi/);
  assert.ok(!E.calls.reads.some(c => /health|nurse|sick/.test(c)), JSON.stringify(E.calls.reads));
  // «🖨 Ichki hisobot» — oynadagi bilan bir xil bo'limlar
  E.els['#rep-print'].onclick();
  const p = E.calls.printed[0] || '';
  assert.match(p, /Umumiy davomat<\/td><td><b>90%<\/b>/);
  assert.match(p, /<td>Fizika<\/td><td style="text-align:center">88<\/td>/);
  assert.match(p, /Sinov: tajribalarda faol/);
  assert.match(section(p, 'O‘qituvchi xulosasi'), /Qabulxona uchun ko‘rsatilmaydi\./);
  assert.doesNotMatch(section(p, 'Monitoring') + section(p, 'Baholar'), /Ma’lumot yo‘q/);
});

test('qabulxona, yig‘ma olinmadi (eski baza / tarmoq) — bo‘limlar «ko‘rsatilmaydi», «Ma’lumot yo‘q» / «Umumiy davomat —» emas', async () => {
  const E = env({ certErr: Object.assign(new Error('Could not find the function public.student_certificate'), { code: 'PGRST202' }) });
  await E.open();
  const h = E.body();
  for (const t of ['Davomat', 'Monitoring', 'Baholar', 'Xarakteristika', 'O‘qituvchi xulosasi']) {
    assert.match(section(h, t), /Qabulxona uchun ko‘rsatilmaydi \(ma’lumot olinmadi\)\./, t);
    assert.doesNotMatch(section(h, t), /Ma’lumot yo‘q|Yozuv yo‘q|Umumiy davomat/, t);
  }
  assert.match(h, /Davomat<\/td><td><b>qabulxona uchun ko‘rsatilmaydi<\/b>/);
});

test('Direktor — avvalgidek o‘zi o‘qigan jadvallardan (yig‘ma chaqirilmaydi); bo‘sh bo‘lim — «Ma’lumot yo‘q» / «Yozuv yo‘q»', async () => {
  const E = env({ role: 'director', isAdmin: true, rows: {
    invoices: INV,
    attendance: [{ studentId: 'IQ-0701', month: '2026-10', days: { '01': 'present', '02': 'late', '03': 'absent', '06': 'sick', '07': 'present' } }],
    monitoring: [{ studentId: 'IQ-0701', subject: 'Fizika', score: 81, status: 'approved' }, { studentId: 'IQ-0701', subject: 'Fizika', score: 99, status: 'pending' }],
  } });
  await E.open();
  const h = E.body();
  assert.deepEqual(E.calls.rpc, [], 'Direktor uchun yig‘ma chaqirilmaydi');
  assert.match(section(h, 'Davomat'), /Umumiy davomat<\/td><td><b>75%<\/b>[\s\S]*2 \/ 1 \/ 1 \(jami 4 kun\)/);
  assert.match(section(h, 'Monitoring'), /<td>Fizika<\/td><td style="text-align:center">81<\/td>/);
  assert.match(section(h, 'Baholar'), /Ma’lumot yo‘q\./);
  assert.match(section(h, 'O‘qituvchi xulosasi'), /Yozuv yo‘q\./);
  assert.doesNotMatch(h, /ko‘rsatilmaydi/);
});
