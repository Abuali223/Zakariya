// acad-save.test.mjs — jurnal ekranlarini saqlash rejasi (audit A3-01, A3-03, A3-06, A3-07, A3-08): admin.html ACAD-SAVE bloki (sof
//   yordamchilar) fayldan o'qib sinaladi; oxirida — «Monitoring baholari» ekrani (renderMonitoring, soxta DOM / baza bilan): saqlash yoki
//   yuklash davom etayotganda tanlov / bo'lim almashsa, eski so'rov yangi ekranni bo'yamaydi.  node --test assets/js/acad-save.test.mjs
//   Qoida: faqat foydalanuvchi shu ekranda o'zgartirgan qatorlar yoziladi; saqlash paytida bazadan qayta o'qilgan qiymat ochilgandagidan
//   farq qilsa — ustiga yozilmaydi (conflict). Monitoring: ball 0–100; O'IBDO' «Saqlash» tasdiqlamaydi; «Saqlash va tasdiqlash» faqat
//   ekranda ko'rilgan qiymatni tasdiqlaydi; bo'shatilgan maydon — o'chirish (o'qituvchi — faqat o'zi kiritgan, tasdiqlanmagan). Ma'lumot to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const block = (() => { const a = ADM.indexOf('// ACAD-SAVE:BEGIN'), b = ADM.indexOf('// ACAD-SAVE:END'); return a >= 0 && b > a ? ADM.slice(a, b) : ''; })();
const S = (() => {
  const ctx = vm.createContext({});
  vm.runInContext(block + '\n;this.__s = { acadPlan, monScoreErr, monNum, monSameRec, monPlan };', ctx);
  return ctx.__s;
})();
const P = rec => JSON.parse(JSON.stringify(rec));   // vm kontekstidagi massivlarni oddiy obyektga (deepEqual uchun)
const pend = (score, by = 'U_T') => ({ score, status: 'pending', by });
const appr = (score, by = 'U_T') => ({ score, status: 'approved', by });

test('blok bitta va yordamchilar bor', () => {
  assert.ok(block.length > 0);
  assert.equal((ADM.match(/ACAD-SAVE:BEGIN/g) || []).length, 1);
  assert.equal((ADM.match(/function monPlan\(/g) || []).length, 1, 'monPlan bitta');
  assert.equal((ADM.match(/function acadPlan\(/g) || []).length, 1, 'acadPlan bitta');
});

test('acadPlan: faqat o‘zgartirilgan qatorlar; shu orada bazada o‘zgargani — conflict', () => {
  const r = P(S.acadPlan([
    { id: 'a', loaded: '4', val: '5', cur: '4', touched: true },        // o'zgartirildi — yoziladi
    { id: 'b', loaded: '4', val: '4', cur: '3', touched: false },       // tegilmagan — yozilmaydi (boshqa xodim qo'ygan 3 saqlanadi)
    { id: 'c', loaded: '3', val: '5', cur: '4', touched: true },        // O'IBDO' shu orada 4 qilgan — eski nusxa ustiga yozilmaydi
    { id: 'd', loaded: '3', val: '4', cur: '4', touched: true },        // bazada allaqachon shu qiymat
    { id: 'e', loaded: 'Matn', val: '', cur: 'Matn', touched: true },   // bo'shatildi — o'chiriladi
    { id: 'f', loaded: '', val: '', cur: '', touched: true },           // yozib, qayta o'chirdi — hech narsa
    { id: 'g', loaded: '', val: 'Yangi', cur: '', touched: true },      // yangi
    { id: 'h', loaded: '5', val: '5', cur: '5', touched: true },        // o'zgartirib, qaytardi — hech narsa
  ]));
  assert.deepEqual(r, { write: ['a', 'g'], del: ['e'], conflict: ['c'], same: ['d'] });
});

test('monScoreErr: 0–100, ko‘pi bilan bir kasr xonasi (A3-03)', () => {
  for (const ok of ['', '0', '95', '95.5', '100', '100.0', '07']) assert.equal(S.monScoreErr(ok), '', ok);
  for (const bad of ['950', '101', '100.5', '-40', '95.55', 'abc', '1e2', '9 5']) assert.notEqual(S.monScoreErr(bad), '', bad);
  assert.match(S.monScoreErr('950'), /0–100/);
});

test('A3-01: o‘qituvchining eskirgan sahifasi — O‘IBDO‘ tasdiqlagan qatorlar qayta «Kutilmoqda»ga tushmaydi', () => {
  // 30 o'quvchi ochilganda kutilmoqda edi; O'IBDO' hammasini tasdiqladi; o'qituvchi bitta xatoni tuzatib «Saqlash» bosdi.
  const rows = Array.from({ length: 30 }, (_, i) => ({ id: 'S' + i, loaded: pend(80 + (i % 10)), cur: appr(80 + (i % 10)), val: String(80 + (i % 10)), touched: false }));
  rows[7] = Object.assign({}, rows[7], { val: '88', touched: true });
  const r = P(S.monPlan(rows, { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.write, [], 'hech narsa yozilmaydi (avval 30 tasi ham pending bo‘lib yozilardi)');
  assert.deepEqual(r.conflict, ['S7'], 'tuzatilgan qator — shu orada tasdiqlangan: ogohlantiriladi');
});

test('o‘qituvchi: o‘zgartirilgan kutilayotgan ball — pending; tegilmaganlar yozilmaydi', () => {
  const r = P(S.monPlan([
    { id: 'a', loaded: pend(70), cur: pend(70), val: '75', touched: true },
    { id: 'b', loaded: pend(60), cur: pend(60), val: '60', touched: false },
    { id: 'c', loaded: null, cur: null, val: '90', touched: true },
    { id: 'd', loaded: null, cur: null, val: '', touched: false },
  ], { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.write, [{ id: 'a', score: 75, status: 'pending' }, { id: 'c', score: 90, status: 'pending' }]);
  assert.deepEqual([r.del, r.conflict, r.locked, r.errors], [[], [], [], []]);
});

test('A3-06: o‘qituvchi o‘zi kiritgan tasdiqlanmagan ballni o‘chiradi; boshqanikini / tasdiqlanganini — yo‘q', () => {
  const r = P(S.monPlan([
    { id: 'own', loaded: pend(70, 'U_T'), cur: pend(70, 'U_T'), val: '', touched: true },
    { id: 'other', loaded: pend(70, 'U_X'), cur: pend(70, 'U_X'), val: '', touched: true },
    { id: 'ok', loaded: appr(70, 'U_T'), cur: appr(70, 'U_T'), val: '', touched: true },
  ], { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.del, ['own']);
  assert.deepEqual(r.locked, [{ id: 'other', why: 'notmine' }, { id: 'ok', why: 'approved' }]);
});

test('A3-08: O‘IBDO‘ «Saqlash» — tasdiqlamaydi; faqat o‘zgartirilgan qatorlar (kutilmoqda)', () => {
  const r = P(S.monPlan([
    { id: 'a', loaded: pend(70), cur: pend(70), val: '72', touched: true },
    { id: 'b', loaded: pend(60), cur: pend(60), val: '60', touched: false },
    { id: 'c', loaded: appr(90), cur: appr(90), val: '95', touched: true },   // tasdiqlangan ball o'zgardi — qayta tasdiqlashga
  ], { approve: false, canApprove: true, me: 'U_Z' }));
  assert.deepEqual(r.write, [{ id: 'a', score: 72, status: 'pending' }, { id: 'c', score: 95, status: 'pending' }]);
});

test('«Saqlash va tasdiqlash»: o‘zgartirilganlar + ekranda ko‘rilgan kutilayotgan ballar; o‘qituvchi shu orada tuzatgani — tegilmaydi', () => {
  const r = P(S.monPlan([
    { id: 'chg', loaded: pend(70), cur: pend(70), val: '74', touched: true },     // O'IBDO' tuzatib tasdiqlaydi
    { id: 'seen', loaded: pend(85), cur: pend(85), val: '85', touched: false },   // ko'rilgan qiymat — tasdiqlanadi
    { id: 'moved', loaded: pend(60), cur: pend(66), val: '60', touched: false },  // o'qituvchi shu orada 66 qilgan — eski 60 tasdiqlanmaydi
    { id: 'done', loaded: appr(99), cur: appr(99), val: '99', touched: false },   // allaqachon tasdiqlangan — yozilmaydi
    { id: 'byother', loaded: pend(50), cur: appr(50), val: '50', touched: false },// boshqa O'IBDO' shu qiymatni tasdiqlagan — yozilmaydi
    { id: 'gone', loaded: pend(40), cur: null, val: '40', touched: false },       // o'chirilgan — qayta yaratilmaydi
  ], { approve: true, canApprove: true, me: 'U_Z' }));
  assert.deepEqual(r.write, [{ id: 'chg', score: 74, status: 'approved' }, { id: 'seen', score: 85, status: 'approved' }]);
  assert.deepEqual(r.conflict, ['moved', 'gone']);
  assert.deepEqual(r.same, ['byother']);
});

test('O‘IBDO‘ bo‘shatgan maydon — o‘chiriladi (tasdiqlangani ham); yangi ball shu orada boshqa yozgan bo‘lsa — conflict', () => {
  const r = P(S.monPlan([
    { id: 'x', loaded: appr(70, 'U_T'), cur: appr(70, 'U_T'), val: '', touched: true },
    { id: 'n1', loaded: null, cur: null, val: '81', touched: true },
    { id: 'n2', loaded: null, cur: pend(70), val: '81', touched: true },
    { id: 'n3', loaded: null, cur: appr(81), val: '81', touched: true },
  ], { approve: true, canApprove: true, me: 'U_Z' }));
  assert.deepEqual(r.del, ['x']);
  assert.deepEqual(r.write, [{ id: 'n1', score: 81, status: 'approved' }]);
  assert.deepEqual(r.conflict, ['n2']);
  assert.deepEqual(r.same, ['n3']);
});

test('A3-03: noto‘g‘ri ball (950, brauzer o‘qiy olmagan matn) — xato ro‘yxati; to‘g‘rilari reja qilinadi, lekin ekran saqlashni to‘xtatadi', () => {
  const r = P(S.monPlan([
    { id: 'a', loaded: null, cur: null, val: '950', touched: true },
    { id: 'b', loaded: pend(70), cur: pend(70), val: '', bad: true, touched: true },   // type=number: «9 5» -> value '' (o'chirish EMAS)
    { id: 'c', loaded: null, cur: null, val: '95', touched: true },
  ], { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.errors.map(e => e.id), ['a', 'b']);
  assert.deepEqual(r.del, [], 'brauzer o‘qiy olmagan qiymat o‘chirish deb olinmaydi');
  assert.deepEqual(r.write, [{ id: 'c', score: 95, status: 'pending' }]);
});

test('balsiz eski qator — yo‘q hisoblanadi (soxta conflict bo‘lmaydi)', () => {
  const r = P(S.monPlan([{ id: 'a', loaded: { score: null, status: 'pending' }, cur: { score: null, status: 'pending' }, val: '77', touched: true }],
    { approve: false, canApprove: false, me: 'U_T' }));
  assert.deepEqual(r.write, [{ id: 'a', score: 77, status: 'pending' }]);
});

// ---- renderMonitoring ekrani (A3-01 qoldig'i, mustaqil tekshiruv 3-raund): saqlash davom etayotganda sinf / fan / oy almashtirilsa,
//   ESKI saqlash YANGI ekranni o'z qiymatlari bilan bo'yamasligi kerak (avval paint() global #mon-list'ni eski yopilish qiymatlari bilan
//   yangilardi: yangi fan qatorlariga oldingi fan ballari va «Tasdiqlangan» tushardi, «Saqlash va tasdiqlash» esa ekrandagidan boshqa
//   qiymatlarni tasdiqlardi). Funksiya admin.html'dan nomi bo'yicha o'qiladi; DOM va baza — soxta (yozuvlar «darvoza»da kutadi).
const AL = ADM.split('\n');
function topFn(name) {   // yuqori darajadagi funksiya: tanasi surilgan, 0-ustundagi «}» bilan yopiladi (bir qatorlisi ham)
  const i = AL.findIndex(l => l.startsWith(`function ${name}(`) || l.startsWith(`async function ${name}(`));
  if (i < 0) return '';
  const out = [AL[i]];
  for (let j = i + 1; j < AL.length; j++) { const l = AL[j]; if (l === '' || /^\s/.test(l)) { out.push(l); continue; } if (l.startsWith('}')) out.push(l); break; }
  return out.join('\n');
}
const topConst = name => AL.find(l => l.startsWith(`const ${name}=`)) || '';
const MON_SRC = [topConst('MON_HINT_NEW'), topConst('MON_HINT_OLD'), topFn('monSlug'), topFn('monBadge'), topFn('renderMonitoring')].join('\n');
const tickM = () => new Promise(r => setTimeout(r, 5));

function monEnv(dbRows, role = 'zavuch') {
  const DB = new Map(Object.entries(dbRows).map(([k, v]) => [k, { ...v }]));   // monitoring jadvali: id -> qator
  const gates = [], rgates = []; let hold = false, holdR = false;   // yozuvlar / o'qishlar «darvozasi»
  const calls = { toast: [], round: [], recompute: [], writes: [] };
  const mk = () => ({ value: '', innerHTML: '', style: {}, disabled: false, _on: {}, addEventListener(ev, fn) { (this._on[ev] = this._on[ev] || []).push(fn); } });
  // Hujjatdagi HOZIRGI elementlar (haqiqiy DOM kabi: $('#id') — joriy ekrandagi). #view qayta yozilsa — yangi tanlagichlar va ro'yxat.
  const els = {}; let list = null, btns = {};
  // #mon-body ga yozilgan HTML'dan qatorlar (data-sid, maydon qiymati / disabled, holat belgisi) va tugmalar quriladi.
  const parse = h => {
    list = null; btns = {};
    if (!h.includes('id="mon-list"')) return;
    const rows = h.split('<div class="att-row" data-sid="').slice(1).map(ch => {
      const sid = ch.slice(0, ch.indexOf('"'));
      const tag = (ch.match(/<input [^>]*class="mon-inp"[^>]*>/) || [''])[0];
      const inp = Object.assign(mk(), { dataset: { sid }, value: (tag.match(/ value="([^"]*)"/) || [])[1] || '', disabled: / disabled /.test(tag), validity: { badInput: false } });
      const ms = ch.indexOf('class="mon-st"'), st = { innerHTML: ch.slice(ch.indexOf('>', ms) + 1, ch.indexOf('</div>', ms)) };
      return { dataset: { sid }, inp, st, querySelector: s => (s === '.mon-inp' ? inp : s === '.mon-st' ? st : null) };
    });
    list = { rows, querySelectorAll: s => (s === '.att-row' ? rows.slice() : s === '.mon-inp' ? rows.map(r => r.inp) : []) };
    if (h.includes('id="mon-save"')) btns.save = mk();
    if (h.includes('id="mon-approve"')) btns.approve = mk();
  };
  const freshView = () => {
    for (const k of ['#mon-class', '#mon-subject', '#mon-period', '#mon-hint', '#mon-round']) els[k] = mk();
    let h = ''; els['#mon-body'] = { style: {}, get innerHTML() { return h; }, set innerHTML(v) { h = v; parse(v); } };
    list = null; btns = {};
  };
  els['#view'] = { get innerHTML() { return ''; }, set innerHTML(v) { freshView(); } };
  const $ = s => (s === '#mon-list' ? list : s === '#mon-save' ? (btns.save || null) : s === '#mon-approve' ? (btns.approve || null) : (els[s] || null));
  const students = [
    { _id: 'IQ-1', studentId: 'IQ-1', name: 'Sinov Bir', grade: 5, classLetter: 'A', lang: 'uz' },
    { _id: 'IQ-2', studentId: 'IQ-2', name: 'Sinov Ikki', grade: 5, classLetter: 'A', lang: 'uz' },
  ];
  let subjectCb = null;
  const write = async (id, fn) => { if (hold) await new Promise(r => gates.push(r)); fn(id); };
  const ctx = vm.createContext({
    VIEW_GEN: 1, SESSION: { isAdmin: false, role, assignedClasses: ['uz-5-A'] }, cache: { students }, loadCol: async () => students, loadDefinedClasses: async () => [],
    classGroupsMap: () => ({ classes: { 'uz-5-A': { label: '5-A', list: students } }, keys: ['uz-5-A'] }), liveClassKeys: (c, k) => k,
    academicYear: () => '2026-2027', curMonth: () => '2026-11', fanPicker: id => `<input id="${id}">`, wireSubjectPicker: (id, cb) => { subjectCb = cb; },
    stuInPeriod: () => true, stuArcChip: () => '', esc: v => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    $, db: {}, doc: (_d, coll, id) => ({ coll, id }), collection: (_d, c) => c, where: (f, op, v) => ({ f, op, v }), query: (c, w) => ({ c, w }),
    getDoc: async ref => { if (holdR) await new Promise(r => rgates.push(r)); const r = DB.get(ref.id); return { exists: () => !!r, data: () => ({ ...r }) }; },
    getDocs: async q => ({ docs: q.w.v.filter(id => DB.has(id)).map(id => ({ id, data: () => ({ ...DB.get(id) }) })) }),
    setDoc: (ref, d) => { calls.writes.push([ref.id, d.score, d.status]); return write(ref.id, id => DB.set(id, { ...(DB.get(id) || {}), score: d.score, status: d.status })); },
    deleteDoc: ref => write(ref.id, id => DB.delete(id)),
    serverTimestamp: () => 'TS', auth: { currentUser: { uid: 'U_Z' } }, confirm: () => true, document: { createElement: () => ({ querySelectorAll: () => [] }) },
    toast: (m, bad) => calls.toast.push([m, !!bad]), errMsg: e => String((e && e.message) || e),
    recomputeMonitoringScore: async sids => { calls.recompute.push([...sids]); }, renderMonRound: (box, ck, period) => { calls.round.push(`${ck}|${period}`); },
  });
  vm.runInContext(block + '\n' + MON_SRC + '\n;this.__rm = renderMonitoring;', ctx);
  const row = sid => { const r = list && list.rows.find(x => x.dataset.sid === sid); if (!r) return null;
    const b = r.st.innerHTML; return { value: r.inp.value, disabled: r.inp.disabled, badge: /Tasdiqlangan/.test(b) ? 'Tasdiqlangan' : /Kutilmoqda/.test(b) ? 'Kutilmoqda' : '' }; };
  return {
    DB, calls, row, render: () => ctx.__rm(),
    nav: () => { ctx.VIEW_GEN++; },   // openTab: boshqa bo'limga o'tildi (VIEW_GEN++)
    // Sinf tanlagichi «change» — load() + raund kartasi (haqiqiy ishlovchi)
    open: (ck, subject, period) => { els['#mon-class'].value = ck; els['#mon-subject'].value = subject; els['#mon-period'].value = period; els['#mon-class']._on.change.forEach(f => f()); },
    pickSubject: subject => { els['#mon-subject'].value = subject; subjectCb(); },
    click: which => btns[which]._on.click[0](),
    hold: v => { hold = v; }, release: () => { hold = false; gates.splice(0).forEach(r => r()); },
    holdReads: v => { holdR = v; }, releaseReads: () => { rgates.splice(0).forEach(r => r()); },
  };
}
const MON_DB = {
  'IQ-1__2026-11__matematika': { score: 70, status: 'pending', enteredBy: 'U_T' },
  'IQ-2__2026-11__matematika': { score: 80, status: 'pending', enteredBy: 'U_T' },
  'IQ-1__2026-11__fizika': { score: 55, status: 'pending', enteredBy: 'U_F' },
};
const FIZ = [{ value: '55', disabled: false, badge: 'Kutilmoqda' }, { value: '', disabled: false, badge: '' }];   // Fizika ekrani: IQ-1, IQ-2

test('renderMonitoring topildi (monGen bilan)', () => {
  assert.ok(topFn('renderMonitoring').includes('let monGen=0;'));
  assert.ok(topConst('MON_HINT_NEW') && topFn('monSlug') && topFn('monBadge'));
});

test('A3-01 qoldig‘i: saqlash paytida fan almashtirildi — eski saqlash yangi ekranni bo‘yamaydi, «Umumiy ball» baribir yangilanadi', async () => {
  const E = monEnv(MON_DB);
  await E.render();
  E.open('uz-5-A', 'Matematika', '2026-11'); await tickM();
  assert.deepEqual(E.row('IQ-1'), { value: '70', disabled: false, badge: 'Kutilmoqda' });
  const roundBefore = E.calls.round.length;
  // O'IBDO' «Saqlash va tasdiqlash» bosdi — yozuvlar sekin (darvoza yopiq); shu orada fan «Fizika»ga almashtirildi.
  E.hold(true); E.click('approve'); await tickM();
  assert.equal(E.calls.writes.length, 2, 'tasdiqlash yozuvlari yuborildi (javob kutilmoqda)');
  E.pickSubject('Fizika'); await tickM();
  assert.deepEqual([E.row('IQ-1'), E.row('IQ-2')], FIZ, 'yangi ekran — Fizika');
  E.release(); await tickM(); await tickM();
  // Eski saqlash tugadi: bazada Matematika tasdiqlangan, lekin ekrandagi Fizika qatorlari o'zgarmagan.
  assert.deepEqual([E.DB.get('IQ-1__2026-11__matematika').status, E.DB.get('IQ-2__2026-11__matematika').status], ['approved', 'approved']);
  assert.deepEqual(E.row('IQ-1'), FIZ[0], 'avval: 70 va «Tasdiqlangan» (Matematika balli Fizika ekranida)');
  assert.deepEqual(E.row('IQ-2'), FIZ[1], 'avval: 80 va «Tasdiqlangan»');
  assert.equal(E.calls.round.length, roundBefore, 'eski saqlash raund kartasini qayta chizmadi');
  assert.deepEqual(E.calls.recompute, [['IQ-1', 'IQ-2']], '«Umumiy ball» ekran almashganda ham qayta hisoblandi');
  assert.match(E.calls.toast.at(-1)[0], /2 ta saqlandi va tasdiqlandi/, 'natija xabari ko‘rsatildi');
  // Yangi ekranning «Saqlash va tasdiqlash»i aynan ekrandagi qiymatni tasdiqlaydi; ekran almashmagan saqlash joyida bo'yaladi.
  E.click('approve'); await tickM(); await tickM();
  assert.deepEqual(E.DB.get('IQ-1__2026-11__fizika'), { score: 55, status: 'approved', enteredBy: 'U_F' });
  assert.deepEqual(E.row('IQ-1'), { value: '55', disabled: false, badge: 'Tasdiqlangan' }, 'joriy ekran saqlashdan keyin yangilanadi');
  assert.equal(E.calls.round.at(-1), 'uz-5-A|2026-11', 'joriy ekran raund kartasi yangilandi');
});

test('A3-01 qoldig‘i: saqlash paytida boshqa bo‘limga o‘tib Monitoringga qaytildi — eski saqlash yangi ekranni bo‘yamaydi', async () => {
  const E = monEnv(MON_DB);
  await E.render();
  E.open('uz-5-A', 'Matematika', '2026-11'); await tickM();
  E.hold(true); E.click('approve'); await tickM();
  E.nav(); await E.render();   // boshqa bo'lim, so'ng yana «Monitoring» — yangi renderMonitoring (o'z monGen'i 0 dan)
  E.open('uz-5-A', 'Fizika', '2026-11'); await tickM();
  assert.deepEqual([E.row('IQ-1'), E.row('IQ-2')], FIZ);
  const roundBefore = E.calls.round.length;
  E.release(); await tickM(); await tickM();
  assert.equal(E.DB.get('IQ-1__2026-11__matematika').status, 'approved', 'eski saqlash bazaga yozildi');
  assert.deepEqual([E.row('IQ-1'), E.row('IQ-2')], FIZ, 'yangi ekran o‘zgarmadi (monGen o‘zgarmagan bo‘lsa ham — ko‘rinish avlodi boshqa)');
  assert.equal(E.calls.round.length, roundBefore);
});

test('kech tugagan yuklash: bo‘limdan chiqib qaytilgandan keyin eski (Matematika) ro‘yxati yangi (Fizika) ekranga yozilmaydi', async () => {
  const E = monEnv(MON_DB);
  await E.render();
  E.holdReads(true); E.open('uz-5-A', 'Matematika', '2026-11'); await tickM();   // o'qish sekin — ro'yxat hali chizilmagan
  E.holdReads(false);
  E.nav(); await E.render(); E.open('uz-5-A', 'Fizika', '2026-11'); await tickM();
  assert.deepEqual([E.row('IQ-1'), E.row('IQ-2')], FIZ);
  E.releaseReads(); await tickM(); await tickM();
  assert.deepEqual([E.row('IQ-1'), E.row('IQ-2')], FIZ, 'avval eski yuklash Matematika (70 / 80) ro‘yxatini Fizika tanlovi ostiga chizardi');
});

test('ziddiyat xabari: «ballini» (ball — baho; «bal» — asal); «O‘zgarishlar tarixi» yorlig‘i «Monitoring balli»', async () => {
  const E = monEnv(MON_DB);
  await E.render();
  E.open('uz-5-A', 'Matematika', '2026-11'); await tickM();
  E.DB.set('IQ-2__2026-11__matematika', { score: 85, status: 'pending', enteredBy: 'U_T' });   // o'qituvchi shu orada tuzatdi
  E.click('approve'); await tickM(); await tickM();
  const msg = E.calls.toast.at(-1)[0];
  assert.match(msg, /1 ta o‘quvchining ballini shu orada boshqa xodim o‘zgartirgan yoki tasdiqlagan — tegilmadi, sahifani yangilang: Sinov Ikki/);
  assert.deepEqual([E.DB.get('IQ-1__2026-11__matematika').status, E.DB.get('IQ-2__2026-11__matematika').status], ['approved', 'pending'], 'tuzatilgan ball tasdiqlanmadi');
  assert.doesNotMatch(ADM, /o‘quvchining balini|'Monitoring bali'/);
  assert.ok(ADM.includes("monitoring:'Monitoring balli'"));
});
