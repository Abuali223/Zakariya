// kirish.test.mjs — kirish shimi (sb/firebase-auth.js) va kabinet murojaati muallifi (index.html renderKabFeedback).
//   node --test assets/js/kirish.test.mjs
//   1) onAuthStateChanged — Firebase'dagidek faqat foydalanuvchi almashganda: supabase-js SHU foydalanuvchi uchun ham hodisa
//      beradi (tabga qaytish — SIGNED_IN, soatlik TOKEN_REFRESHED, USER_UPDATED) — ular tinglovchini qayta chaqirmasligi kerak
//      (admin.html panelni boshidan qurardi, index.html kabinetni qayta chizardi); joriy obyekt jim yangilanadi.
//   2) signOut — standart faqat shu qurilma (scope 'local'); 'global' — faqat aniq so'ralganda.
//   3) o'quvchi yozgan murojaat 'student' bo'lib yuboriladi (avval doim 'parent').
//   Tarmoqsiz: esm.sh dagi supabase-js o'rniga bo'sh modul (resolve ilgagi), mijoz — soxta (_setClient). Ma'lumotlar to'qima.
import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

register('data:text/javascript,' + encodeURIComponent(`export async function resolve(spec, ctx, next) {
  if (spec.startsWith('https://esm.sh/')) return { url: 'data:text/javascript,' + encodeURIComponent('export function createClient(){ return {}; }'), shortCircuit: true };
  return next(spec, ctx);
}`));
const { _setClient } = await import(new URL('../../sb/_core.js', import.meta.url).href);

// Soxta supabase-js auth: getSession va INITIAL_SESSION haqiqiydagidek bir necha taktdan keyin keladi.
const tick = () => new Promise(r => setTimeout(r, 0));
const settle = () => new Promise(r => setTimeout(r, 25));
const S = (id, user) => ({ access_token: 'at.' + id + '.' + Math.random().toString(36).slice(2),
  user: Object.assign({ id, email: id.toLowerCase() + '@example.org', user_metadata: { displayName: 'Sinov ' + id } }, user || {}) });
function fakeClient(initial, opt) {
  const o = opt || {}, subs = new Set(), calls = { signOut: [] };
  let session = initial || null;
  return {
    calls,
    auth: {
      async getSession() { for (let i = 0; i < (o.getSessionTicks || 1); i++) await tick(); return { data: { session: o.staleSession !== undefined ? o.staleSession : session } }; },
      onAuthStateChange(cb) {
        subs.add(cb);
        (async () => { await tick(); await tick(); if (subs.has(cb)) cb(o.initialEvent || 'INITIAL_SESSION', session); })();
        return { data: { subscription: { unsubscribe() { subs.delete(cb); } } } };
      },
      async signOut(opts) { calls.signOut.push(opts); if (o.signOutError) return { error: { message: o.signOutError } }; session = null; for (const cb of [...subs]) cb('SIGNED_OUT', null); return { error: null }; },
    },
    fire(ev, s) { session = s; for (const cb of [...subs]) cb(ev, s); },
  };
}
// Har sinovga yangi shim nusxasi (modul holati — tinglovchilar, joriy foydalanuvchi — alohida); mijoz umumiy _core.js'da.
let seq = 0;
async function fresh(initial, opt) {
  const client = fakeClient(initial, opt);
  _setClient(client);
  const A = await import(new URL('../../sb/firebase-auth.js?t=' + (++seq), import.meta.url).href);
  return { A, client, auth: A.getAuth() };
}
function listen(A, auth) {
  const rec = [];
  const off = A.onAuthStateChanged(auth, u => rec.push(u));
  return { rec, off, uids: () => rec.map(u => (u ? u.uid : null)) };
}
const count = (arr, v) => arr.filter(x => x === v).length;

test('boshlang‘ich holat: tinglovchi foydalanuvchini BIR MARTA oladi (getSession + INITIAL_SESSION takrorlanmaydi)', async () => {
  const { A, auth } = await fresh(S('U1'));
  const L = listen(A, auth);
  await settle();
  assert.equal(L.uids().at(-1), 'U1');
  assert.equal(count(L.uids(), 'U1'), 1, 'U1 bir marta: ' + JSON.stringify(L.uids()));
  assert.equal(auth.currentUser && auth.currentUser.uid, 'U1');
});

test('shu foydalanuvchi: TOKEN_REFRESHED, tabga qaytish (SIGNED_IN), USER_UPDATED — tinglovchi chaqirilmaydi, obyekt jim yangilanadi', async () => {
  const { A, client, auth } = await fresh(S('U1'));
  const L = listen(A, auth);
  await settle();
  const n = L.rec.length, u = L.rec.at(-1);
  client.fire('TOKEN_REFRESHED', S('U1', { email: 'u1-yangi@example.org' }));
  await settle();
  assert.equal(L.rec.length, n, 'TOKEN_REFRESHED tinglovchini chaqirmaydi: ' + JSON.stringify(L.uids()));
  assert.equal(auth.currentUser, u, 'o‘sha obyekt (Firebase’dagidek)');
  assert.equal(u.email, 'u1-yangi@example.org', 'obyekt yangilangan');
  client.fire('SIGNED_IN', S('U1'));   // _recoverAndRefresh: har safar ilova/tabga qaytilganda
  await settle();
  assert.equal(L.rec.length, n, 'shu foydalanuvchining SIGNED_IN hodisasi tinglovchini chaqirmaydi');
  client.fire('USER_UPDATED', S('U1', { user_metadata: { displayName: 'Sinov Yangi' } }));
  await settle();
  assert.equal(L.rec.length, n, 'USER_UPDATED tinglovchini chaqirmaydi');
  assert.equal(u.displayName, 'Sinov Yangi', 'displayName shu obyektda yangilandi');
  assert.equal(typeof u.getIdToken, 'function');
});

test('foydalanuvchi almashganda — aynan bir marta: boshqa hisob, chiqish (takroriy chiqish — chaqiruvsiz), qayta kirish', async () => {
  const { A, client, auth } = await fresh(S('U1'));
  const L = listen(A, auth);
  await settle();
  const u1 = L.rec.at(-1);
  let n = L.rec.length;
  client.fire('SIGNED_IN', S('U2'));
  await settle();
  assert.deepEqual(L.uids().slice(n), ['U2'], 'boshqa hisob — bir marta');
  assert.notEqual(L.rec.at(-1), u1, 'yangi foydalanuvchi — yangi obyekt');
  n = L.rec.length;
  client.fire('SIGNED_OUT', null);
  await settle();
  assert.deepEqual(L.uids().slice(n), [null], 'chiqish — bir marta null');
  assert.equal(auth.currentUser, null);
  n = L.rec.length;
  client.fire('SIGNED_OUT', null);
  await settle();
  assert.equal(L.rec.length, n, 'takroriy chiqish hodisasi — chaqiruvsiz');
  client.fire('SIGNED_IN', S('U1'));
  await settle();
  assert.deepEqual(L.uids().slice(n), ['U1'], 'chiqqandan keyin qayta kirish — bir marta (panel qayta quriladi)');
});

test('kech qo‘shilgan tinglovchi joriy holatni bir marta oladi; obunadan chiqqan chaqirilmaydi; xato tashlagan tinglovchi boshqalarga xalaqit bermaydi', async () => {
  const { A, client, auth } = await fresh(S('U1'));
  const L1 = listen(A, auth);
  await settle();
  const L2 = listen(A, auth);
  await settle();
  assert.deepEqual(L2.uids(), ['U1'], 'kech tinglovchi: joriy foydalanuvchi bir marta');
  A.onAuthStateChanged(auth, () => { throw new Error('sinov'); });
  const L3 = listen(A, auth);
  await settle();
  L2.off();
  client.fire('SIGNED_IN', S('U2'));
  await settle();
  assert.equal(L1.uids().at(-1), 'U2');
  assert.equal(L3.uids().at(-1), 'U2', 'xato tashlagan tinglovchidan keyingisi ham chaqirildi');
  assert.deepEqual(L2.uids(), ['U1'], 'obunadan chiqqan tinglovchi chaqirilmadi');
});

test('getSession’ning eskirgan surati hodisadan keyin kelsa — e’tiborsiz (chiqqan foydalanuvchi qaytib «kirmaydi»)', async () => {
  const { A, auth } = await fresh(null, { staleSession: S('U1'), getSessionTicks: 6, initialEvent: 'SIGNED_OUT' });
  const L = listen(A, auth);
  await settle();
  assert.equal(auth.currentUser, null, 'joriy holat — chiqilgan');
  assert.equal(count(L.uids(), 'U1'), 0, 'eskirgan U1 tinglovchiga yetkazilmadi: ' + JSON.stringify(L.uids()));
});

test('signOut: standart — faqat shu qurilma (scope local); global — faqat aniq so‘ralganda; xato — rad', async () => {
  const { A, client, auth } = await fresh(S('U1'));
  const L = listen(A, auth);
  await settle();
  await A.signOut(auth);
  assert.deepEqual(client.calls.signOut[0], { scope: 'local' }, 'Chiqish — shu qurilma');
  assert.equal(L.uids().at(-1), null, 'chiqish tinglovchiga yetdi');
  await A.signOut(auth, { scope: 'global' });
  assert.deepEqual(client.calls.signOut[1], { scope: 'global' }, 'global faqat aniq so‘ralganda');
  await A.signOut(auth, { scope: 'others' });
  assert.deepEqual(client.calls.signOut[2], { scope: 'local' }, 'boshqa qiymat — shu qurilma');
  const f = await fresh(S('U1'), { signOutError: 'tarmoq xatosi' });
  await assert.rejects(f.A.signOut(f.auth), /tarmoq xatosi/);
});

// ---- index.html: «Arz-shikoyat» muallifi roli (renderKabFeedback — fayldan o'qib, soxta DOM bilan) ----
const IDX = readFileSync(new URL('../../index.html', import.meta.url), 'utf8');
const FB_SRC = (() => { const a = IDX.indexOf('async function renderKabFeedback(s){'); const b = a >= 0 ? IDX.indexOf('\n}\n', a) : -1; return a >= 0 && b > a ? IDX.slice(a, b + 2) : ''; })();
async function sendFeedbackAs(roleAtRender, roleAtSend) {
  let role = roleAtRender;
  const sent = [];
  const el = { box: { innerHTML: '' }, send: { onclick: null, disabled: false, textContent: '' }, text: { value: 'Sinov murojaat matni' },
    type: { value: 'taklif' }, msg: { style: {}, textContent: '' } };
  const map = { '#kab-feedback': el.box, '#fb-send': el.send, '#fb-text': el.text, '#fb-type': el.type, '#fb-msg': el.msg };
  const ctx = vm.createContext({
    T: { uz: new Proxy({}, { get: (_, k) => String(k) }) }, lang: 'uz', esc: s => String(s == null ? '' : s), $: s => map[s] || null,
    window: { IqrorFB: { submitFeedback: async d => { sent.push(d); return true; }, getMyFeedback: async () => [] }, IqrorAuth: { getRole: () => role, getUser: () => ({ uid: 'U1' }) } },
  });
  vm.runInContext(FB_SRC + '\n;this.__f = renderKabFeedback;', ctx);
  await ctx.__f({ id: 'IQ-0001', name: 'Sinov Bola' });
  role = roleAtSend;
  await el.send.onclick();
  return sent.length ? sent[0].authorRole : '(yuborilmadi)';
}

test('index.html: renderKabFeedback bitta va topildi', () => {
  assert.ok(FB_SRC.length > 0, 'renderKabFeedback topilmadi');
  assert.equal((IDX.match(/async function renderKabFeedback\(/g) || []).length, 1);
});

test('murojaat muallifi: o‘quvchi — student; ota-ona / boshqa rol / rol yo‘q — parent; rol YUBORISH paytida olinadi', async () => {
  assert.equal(await sendFeedbackAs('student', 'student'), 'student', 'o‘quvchi hisobi');
  assert.equal(await sendFeedbackAs('parent', 'parent'), 'parent');
  assert.equal(await sendFeedbackAs('teacher', 'teacher'), 'parent', 'farzandi bor xodim — ota-ona sifatida');
  assert.equal(await sendFeedbackAs(null, null), 'parent', 'rol hali noma’lum — ota-ona');
  assert.equal(await sendFeedbackAs(null, 'student'), 'student', 'rol keyin tanlangan (askRole) — yuborishda yangisi');
});
