// sales.test.mjs — «Sotuvchi» (sales) roli, admin.html (egasi 2026-11-19; migration/sales-role.sql, SESSIYA-ISHLARI.md §85):
//   1) kirish: sotuvchi panelga kiradi, faqat «📞 Ota-onalar bilan aloqa» bo'limi; qo'shimcha lavozimlari (eski qator) hisobga olinmaydi;
//      xabarnoma muharriri / sinf rahbari belgisi ham bo'lim qo'shmaydi; 🔍 qidiruv yashirin, oflayn to'lov navbati ishga tushmaydi;
//   2) renderSales: ro'yxat sales_contacts dan (niqoblangan raqamlar, tel: havolasiz), «📞 Raqamni ko‘rsatish» — sales_reveal, raqamlar
//      tel: havolasi bo'ladi, hisoblagich «Bugun ochilgan: N / 150», kunlik chegara / topilmadi xabarlari, qidiruv (kamida 2 belgi),
//      sahifalash; tahrir, eksport, chop etish, CSV yo'q; Direktor — «Sotuvchilar jurnali» (sales_log);
//   3) qo'shimcha lavozim yo'q (uHas, EXTRA_ROLES_OK), «Sotuvchi» lavozimi -> rol, Foydalanuvchilar ro'yxatida rol, menyu guruhi.
//   Funksiyalar admin.html'dan nomi / blok belgisi bo'yicha o'qiladi; baza (rpc) va DOM — soxta. Ma'lumotlar to'qima («Sinov …», 99800…).
//   node --test assets/js/sales.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ADM = readFileSync(new URL('../../admin.html', import.meta.url), 'utf8');
const IDX = readFileSync(new URL('../../index.html', import.meta.url), 'utf8');
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
// Ko'p qatorli «const NAME = { … };» / «[ … ];» (qavslar muvozanati bo'yicha).
function constBlock(name) {
  const a = ADM.search(new RegExp(`\\nconst ${name}\\s*=\\s*[\\[{]`)); if (a < 0) return '';
  const s = a + 1; let d = 0;
  for (let i = ADM.indexOf('=', s) + 1; i < ADM.length; i++) { const c = ADM[i]; if (c === '{' || c === '[') d++; else if (c === '}' || c === ']') { d--; if (d === 0) return ADM.slice(s, ADM.indexOf(';', i) + 1); } }
  return '';
}
const block = (b, e) => { const i = ADM.indexOf(b), j = ADM.indexOf(e, i); return i >= 0 && j > i ? ADM.slice(i, j + e.length) : ''; };
const PHONE = block('/* PHONE-CANON:BEGIN', '/* PHONE-CANON:END */');
const SALES_UI = block('// SALES-UI:BEGIN', '// SALES-UI:END');
const BOOT_SRC = (() => { const a = ADM.indexOf('let bootUid=null;\nonAuthStateChanged(auth, async user=>{'); const b = a >= 0 ? ADM.indexOf('\n});\nfunction show(which)', a) : -1;
  return a >= 0 && b > a ? ADM.slice(a, b + 4) : ''; })();
const ROLE_SRC = [topConst('ROLE_LABEL'), constBlock('ROLE_TABS'), topConst('EXTRA_ROLES_OK'), fn('uHas'), fn('allowedTabs')].join('\n');

// ---------------- soxta DOM (faqat renderSales ishlatadigan qismi) ----------------
function makeDom() {
  const els = {}, btns = {};
  const reg = h => { const re = /id="([^"]+)"/g; let m; while ((m = re.exec(h))) if (!els['#' + m[1]]) els['#' + m[1]] = mk(); };
  function queryAll(e, sel) {
    const h = e._h || '';
    if (sel === '[data-slk]') { const out = []; const re = /data-slk="([^"]+)"/g; let m;
      while ((m = re.exec(h))) { const k = m[1]; const b = btns[k] || (btns[k] = mk()); b.dataset.slk = k; out.push(b); } return out; }
    if (sel === 'tr[data-slrow]') { const out = []; const re = /<tr data-slrow="([^"]+)">[\s\S]*?<\/tr>/g; let m;
      while ((m = re.exec(h))) { const seg = m[0], k = m[1]; const t = mk(); t.dataset.slrow = k; t.outerHTML = seg; t.replaceWith = nr => { e._h = e._h.replace(seg, nr.outerHTML); }; out.push(t); }
      return out; }
    return [];
  }
  function mk() {
    const e = { style: {}, dataset: {}, disabled: false, value: '', textContent: '', _h: '', onclick: null, listeners: {} };
    Object.defineProperty(e, 'innerHTML', { get: () => e._h, set: h => { e._h = String(h); reg(e._h); } });
    Object.defineProperty(e, 'firstElementChild', { get: () => (/^\s*<tr/.test(e._h) ? { outerHTML: e._h.trim() } : null) });
    e.addEventListener = (t, f) => { (e.listeners[t] = e.listeners[t] || []).push(f); };
    e.querySelectorAll = sel => queryAll(e, sel);
    e.querySelector = sel => queryAll(e, sel)[0] || null;
    return e;
  }
  els['#view'] = mk();
  return { els, btns, mk, $: s => els[s] || null, document: { createElement: () => mk() } };
}

// rows: [{k, father:{name, phone}, mother}], reveal: k -> javob
function salesEnv({ isAdmin = false, rows = [], total = null, todayUsed = 0, reveal = {}, contactsErr = null, log = null } = {}) {
  const D = makeDom(), calls = [], toasts = [];
  const ctx = vm.createContext({
    auth: { currentUser: { uid: isAdmin ? 'U_DIR' : 'U_SAL' } },
    SESSION: { role: isAdmin ? 'director' : 'sales', isAdmin, roles: [isAdmin ? 'director' : 'sales'] }, VIEW_GEN: 1,
    $: D.$, document: D.document, setTimeout, clearTimeout, console,
    toast: (m, err) => toasts.push([String(m), !!err]),
    rpc: async (name, args) => {
      calls.push([name, { ...args }]);
      if (name === 'sales_contacts') {
        if (contactsErr) throw contactsErr;
        const q = args.p_q, list = q ? rows.filter(r => JSON.stringify([r.father && r.father.name, r.mother && r.mother.name]).toLowerCase().includes(q.toLowerCase())) : rows;
        return { ok: true, rows: list.slice(args.p_offset, args.p_offset + args.p_limit), total: total == null ? list.length : total, limit: args.p_limit, offset: args.p_offset, todayUsed, dailyCap: 150 };
      }
      if (name === 'sales_reveal') { const r = reveal[args.p_k]; if (r instanceof Error) throw r; return r || { ok: false, reason: 'not_found' }; }
      if (name === 'sales_log') return log || { ok: true, days: [], recent: [], dailyCap: 150 };
      throw Object.assign(new Error('Could not find the function public.' + name), { code: 'PGRST202' });
    },
  });
  vm.runInContext([topConst('esc'), topConst('errMsg'), topConst('ROLE_LABEL'), PHONE, fn('pmPrettyPhone'), fn('fmtWhen'), fn('rpcMissing'), SALES_UI,
    ';this.__render = renderSales; this.__open = SALES_OPEN;'].join('\n'), ctx);
  return { ctx, calls, toasts, D, render: () => ctx.__render(), list: () => (D.els['#sl-list'] || {})._h || '', used: () => (D.els['#sl-used'] || {}).textContent };
}
const R1 = { k: 'a'.repeat(32), father: { name: 'Sinov Ota Alfa', phone: '+998 00 *** ** 01' }, mother: { name: 'Sinov Ona Alfa', phone: '+998 00 *** ** 01' } };
const R2 = { k: 'b'.repeat(32), father: { name: 'Sinov Ota Beta', phone: '+998 00 *** ** 02' }, mother: null };
const R3 = { k: 'c'.repeat(32), father: { name: 'Sinov Ota Gamma', phone: null }, mother: { name: 'Sinov Ona Gamma', phone: '+998 00 *** ** 03' } };
const REV1 = { ok: true, k: R1.k, father: { name: 'Sinov Ota Alfa', phone: '+998001110001' }, mother: { name: 'Sinov Ona Alfa', phone: '+998002220001' }, todayUsed: 4, dailyCap: 150 };
const tick = (ms = 0) => new Promise(r => setTimeout(r, ms));

test('admin.html: kerakli bloklar topildi (SALES-UI, kirish ishlovchisi, rol jadvallari)', () => {
  assert.ok(SALES_UI.length > 500, 'SALES-UI bloki');
  assert.ok(BOOT_SRC.length > 0, 'onAuthStateChanged ishlovchisi');
  for (const n of ['uHas', 'allowedTabs', 'pmPrettyPhone', 'fmtWhen', 'rpcMissing', 'posToRole', 'openGlobalSearch']) assert.ok(fn(n).length > 0, n);
  assert.ok(constBlock('ROLE_TABS').includes('sales:'), 'ROLE_TABS.sales');
  assert.equal((ADM.match(/SALES-UI:BEGIN/g) || []).length, 1);
});

test('rol: ROLE_LABEL «Sotuvchi», ROLE_TABS faqat [sales]; qo‘shimcha lavozim bo‘la olmaydi va olmaydi (uHas)', () => {
  const ctx = vm.createContext({ SESSION: {} });
  vm.runInContext(ROLE_SRC + '\n;this.__r = { ROLE_LABEL, ROLE_TABS, EXTRA_ROLES_OK, uHas };', ctx);
  const { ROLE_LABEL, ROLE_TABS, EXTRA_ROLES_OK, uHas } = ctx.__r;
  assert.equal(ROLE_LABEL.sales, 'Sotuvchi');
  assert.deepEqual([...ROLE_TABS.sales], ['sales']);
  assert.ok(!EXTRA_ROLES_OK.includes('sales'), 'sales qo‘shimcha lavozim bo‘la olmaydi');
  assert.equal(uHas({ role: 'sales', extraRoles: ['kassir', 'reception'] }, 'kassir'), false, 'sotuvchining eski qo‘shimchasi hisobga olinmaydi');
  assert.equal(uHas({ role: 'sales', extraRoles: ['teacher'] }, 'teacher'), false);
  assert.equal(uHas({ role: 'guard', extraRoles: ['kassir'] }, 'kassir'), true, 'boshqa rolda qo‘shimcha — avvalgidek');
  assert.equal(uHas({ role: 'sales' }, 'sales'), true);
  // marketing menejeri — avvalgidek (sotuvchi undan alohida rol)
  assert.deepEqual([...ROLE_TABS.marketing_mgr], ['marketing', 'enrollments']);
});

test('allowedTabs: sotuvchi — faqat «sales» (muharrir / sinf rahbari / tasdiq navbati / kassa qo‘shmaydi)', () => {
  const ctx = vm.createContext({ SESSION: {}, approvalQueuesForMe: () => [{ key: 'x' }], kassaTabOk: () => true, accFinOk: () => true, canSeeSalary: () => true });
  vm.runInContext(ROLE_SRC + '\n;this.__a = allowedTabs;', ctx);
  ctx.SESSION = { role: 'sales', isAdmin: false, roles: ['sales'], homeroomClasses: ['uz-5-A'], notifyEditor: true };
  assert.deepEqual([...ctx.__a()], ['sales']);
  ctx.SESSION = { role: 'marketing_mgr', isAdmin: false, roles: ['marketing_mgr'], homeroomClasses: [], notifyEditor: false };
  const mk = [...ctx.__a()];
  assert.ok(mk.includes('marketing') && mk.includes('enrollments') && !mk.includes('sales'), 'marketing menejeri bo‘limlari o‘zgarmagan: ' + mk);
});

// ---------------- kirish ishlovchisi (onAuthStateChanged) — haqiqiy kod, soxta baza ----------------
async function bootAs(usersRow) {
  const el = () => ({ style: {}, textContent: '' });
  const ui = { '#who': el(), '#btn-search': el(), '#login-err': el() }, rec = { shown: [], open: [], outbox: 0, kassaProbe: 0, kassaInit: 0, signOut: 0 };
  const ctx = vm.createContext({
    SESSION: {}, auth: {}, db: {}, doc: (_d, c, id) => ({ c, id }),
    getDoc: async ref => (ref.c === 'users' ? { exists: () => true, data: () => ({ ...usersRow }) } : { exists: () => false, data: () => ({}) }),
    signOut: async () => { rec.signOut++; }, $: s => ui[s] || null, show: w => rec.shown.push(w), loginAttempted: false, localStorage: { getItem: () => null },
    kassaInit: () => { rec.kassaInit++; }, buildTabs: () => {}, setupRoleSwitch: () => {}, openTab: t => rec.open.push(t), watchBadges: () => {},
    startOutboxSync: () => { rec.outbox++; }, kassaProbe: () => { rec.kassaProbe++; }, approvalQueuesForMe: () => [], kassaTabOk: () => false,
    accFinOk: () => false, canSeeSalary: () => false, currentTab: 'dashboard', VIEW_GEN: 0, SALES_OPEN: new Map(), SALES_OPEN_UID: '',
    onAuthStateChanged: (_a, cb) => { ctx.__cb = cb; },
  });
  vm.runInContext(ROLE_SRC + '\n' + BOOT_SRC, ctx);
  await ctx.__cb({ uid: 'U_SAL', email: 's@example.org', getIdTokenResult: async () => ({ claims: {} }) });
  return { ctx, ui, rec };
}

test('kirish: sotuvchi panelga kiradi — faqat «sales» bo‘limi, qo‘shimcha lavozimlari yo‘q, 🔍 yashirin, to‘lov navbati ishga tushmaydi', async () => {
  const { ctx, ui, rec } = await bootAs({ role: 'sales', status: 'active', extraRoles: ['kassir', 'reception'], homeroomClasses: ['uz-5-A'] });
  assert.equal(rec.signOut, 0, 'chiqarib yuborilmadi');
  assert.equal(ctx.SESSION.role, 'sales');
  assert.deepEqual([...ctx.SESSION.roles], ['sales'], 'eski qo‘shimcha lavozimlar panelga o‘tmaydi');
  assert.equal(ctx.SESSION.isAdmin, false);
  assert.deepEqual(rec.shown, ['app']);
  assert.deepEqual(rec.open, ['sales'], 'birinchi (yagona) bo‘lim ochildi');
  assert.equal(rec.outbox, 0, 'oflayn to‘lov navbati ishga tushmadi');
  assert.equal(ui['#btn-search'].style.display, 'none', '🔍 qidiruv yashirin');
  assert.match(ui['#who'].textContent, /Sotuvchi/);
});

test('chiqish (yoki seans tugashi): ochilgan ota-ona raqamlari va joriy bo‘lim tozalanadi, kech kelgan javob chizilmaydi (VIEW_GEN)', async () => {
  const { ctx, ui, rec } = await bootAs({ role: 'sales', status: 'active' });
  ui['#view'] = { innerHTML: '<tr><td><a href="tel:+998001110001">+998 00 111 00 01</a></td></tr>' };
  ctx.SALES_OPEN.set('a'.repeat(32), { father: { name: 'Sinov Ota', phone: '+998001110001' } }); ctx.SALES_OPEN_UID = 'U_SAL';
  const g0 = ctx.VIEW_GEN;
  await ctx.__cb(null);
  assert.equal(ui['#view'].innerHTML, '', 'sahifada raqam qolmadi');
  assert.equal(ctx.SALES_OPEN.size, 0, 'xotiradagi ochilgan raqamlar tozalandi');
  assert.equal(ctx.SALES_OPEN_UID, '');
  assert.ok(ctx.VIEW_GEN > g0, 'kech kelgan javob eskirgan deb tashlanadi');
  assert.equal(rec.shown.at(-1), 'login');
});

test('kirish: boshqa rol — avvalgidek (navbat ishga tushadi, 🔍 ko‘rinadi); bloklangan sotuvchi — kirmaydi', async () => {
  const m = await bootAs({ role: 'marketing_mgr', status: 'active', extraRoles: [] });
  assert.equal(m.rec.outbox, 1);
  assert.equal(m.ui['#btn-search'].style.display, '');
  assert.deepEqual(m.rec.open, ['marketing']);
  const b = await bootAs({ role: '', status: 'blocked', blockedRole: 'sales' });
  assert.equal(b.rec.signOut, 1);
  assert.deepEqual(b.rec.shown, ['login']);
});

// ---------------- renderSales ----------------
test('renderSales (sotuvchi): ro‘yxat niqoblangan, tel: havolasiz; hisoblagich; jurnal chaqirilmaydi; tahrir / eksport / chop etish yo‘q', async () => {
  const E = salesEnv({ rows: [R1, R2, R3], todayUsed: 3 });
  await E.render();
  assert.deepEqual(E.calls, [['sales_contacts', { p_q: null, p_limit: 50, p_offset: 0 }]], 'faqat ro‘yxat, jurnal emas');
  const h = E.list();
  assert.match(h, /Sinov Ota Alfa[\s\S]*\+998 00 \*\*\* \*\* 01[\s\S]*Sinov Ona Alfa/);
  assert.match(h, /Sinov Ota Beta[\s\S]*\+998 00 \*\*\* \*\* 02/);
  assert.match(h, /Sinov Ota Gamma[\s\S]*raqam yo‘q/, 'raqamsiz ota');
  assert.doesNotMatch(h, /tel:/, 'ochilmaguncha tel: havolasi yo‘q');
  assert.equal((h.match(/data-slk="/g) || []).length, 3, 'har oilaga «📞 Raqamni ko‘rsatish»');
  assert.match(h, /📞 Raqamni ko‘rsatish/);
  assert.equal(E.used(), 'Bugun ochilgan: 3 / 150');
  const view = E.D.els['#view']._h;
  assert.match(view, /📞 Ota-onalar bilan aloqa/);
  assert.ok(!E.D.els['#sl-log'], 'sotuvchida jurnal kartasi yo‘q');
  // tugmalar: faqat ochish (va sahifalash); kiritish maydoni — faqat qidiruv
  const allHtml = view + h + ((E.D.els['#sl-pager'] || {})._h || '');
  for (const b of allHtml.match(/<button[^>]*>/g) || []) assert.match(b, /data-slk=|id="sl-(prev|next)"/, 'ortiqcha tugma: ' + b);
  assert.deepEqual(allHtml.match(/<(input|textarea|select)[^>]*>/g).map(x => /id="([^"]+)"/.exec(x)[1]), ['sl-q']);
  assert.doesNotMatch(SALES_UI, /downloadCSV|printHTML|window\.print|XLSX|\.csv|setDoc|updateDoc|deleteDoc|addDoc|createDoc|writeBatch/, 'blokda eksport / chop etish / yozish yo‘q');
});

test('renderSales: «📞 Raqamni ko‘rsatish» — sales_reveal, raqamlar tel: havolasi; hisoblagich yangilanadi; boshqa oilalar niqoblangan qoladi', async () => {
  const E = salesEnv({ rows: [R1, R2], todayUsed: 3, reveal: { [R1.k]: REV1 } });
  await E.render();
  const [b1] = E.D.els['#sl-list'].querySelectorAll('[data-slk]');
  assert.equal(b1.dataset.slk, R1.k);
  await b1.onclick();
  assert.deepEqual(E.calls.at(-1), ['sales_reveal', { p_k: R1.k }]);
  const h = E.list();
  assert.match(h, /<a href="tel:\+998001110001"[^>]*>\+998 00 111 00 01<\/a>/, 'ota raqami — bir bosishda qo‘ng‘iroq');
  assert.match(h, /<a href="tel:\+998002220001"[^>]*>\+998 00 222 00 01<\/a>/, 'ona raqami');
  assert.match(h, /✓ Raqam ochilgan/);
  assert.equal((h.match(/data-slk="/g) || []).length, 1, 'ochilgan oilada tugma qolmadi, ikkinchisida bor');
  assert.match(h, /Sinov Ota Beta[\s\S]*\+998 00 \*\*\* \*\* 02/, 'boshqa oila — niqoblangan');
  assert.equal(E.used(), 'Bugun ochilgan: 4 / 150');
  assert.equal(E.toasts.length, 0);
  assert.ok(E.ctx.__open.has(R1.k), 'shu seans xotirasida');
  // bo'limga qayta kirish — ochilgan raqam shu foydalanuvchida qoladi (qayta so'ralmaydi)
  await E.render();
  assert.match(E.list(), /tel:\+998001110001/);
  // boshqa hisob shu oynada kirdi (chiqib-kirish, sahifa yangilanmasdan) — oldingi foydalanuvchi ochgan raqamlar ko'rinmaydi
  E.ctx.auth.currentUser = { uid: 'U_SAL2' };
  await E.render();
  assert.doesNotMatch(E.list(), /tel:/, 'boshqa foydalanuvchi — yana niqoblangan');
  assert.equal(E.ctx.__open.size, 0);
});

test('renderSales: bir katakda ikki raqam (valid:false, asl yozuv) — har biri alohida qo‘ng‘iroq havolasi; xorij raqami — havola; «8 916…» va uzunligi noto‘g‘ri — havolasiz, izoh bilan', async () => {
  const R4 = { k: 'd'.repeat(32), father: { name: 'Sinov Ota Sigma', phone: '*** ** 32', valid: false }, mother: { name: 'Sinov Ona Sigma', phone: '*** ** 33', valid: true } };
  const REV4 = { ok: true, k: R4.k, father: { name: 'Sinov Ota Sigma', phone: '+998 00 111 00 31, +998 00 111 00 32', valid: false },
    mother: { name: 'Sinov Ona Sigma', phone: '+447700900033', valid: true }, todayUsed: 1, dailyCap: 150 };
  const R5 = { k: 'e'.repeat(32), father: { name: 'Sinov Ota Rus', phone: '*** ** 67', valid: true }, mother: { name: 'Sinov Ona Xato', phone: '*** ** 78', valid: true } };
  const REV5 = { ok: true, k: R5.k, father: { name: 'Sinov Ota Rus', phone: '+89161234567', valid: true },
    mother: { name: 'Sinov Ona Xato', phone: '+9012345678', valid: true }, todayUsed: 2, dailyCap: 150 };
  const E = salesEnv({ rows: [R4, R5], reveal: { [R4.k]: REV4, [R5.k]: REV5 } });
  await E.render();
  assert.match(E.list(), /\*\*\* \*\* 32[\s\S]*\*\*\* \*\* 33/, 'ochilmaguncha — niqob');
  const [b4, b5] = E.D.els['#sl-list'].querySelectorAll('[data-slk]');
  await b4.onclick(); await b5.onclick();
  const h = E.list();
  assert.match(h, /<a href="tel:\+998001110031"[^>]*>[^<]*<\/a>, <a href="tel:\+998001110032"[^>]*>[^<]*<\/a> <span[^>]*>\(bir katakda bir nechta raqam yozilgan\)/, 'ota: ikki raqam — ikki havola');
  assert.match(h, /<a href="tel:\+447700900033"/, 'ona: xorij raqami — qo‘ng‘iroq havolasi');
  assert.doesNotMatch(h, /tel:\+?8916|tel:\+?9012345678/, '«8 916…» va uzunligi noto‘g‘ri — havola yo‘q');
  assert.match(h, /\+89161234567<\/span> <span[^>]*>\(raqam noto‘g‘ri yozilgan bo‘lishi mumkin — ma’muriyatga xabar bering\)/);
  assert.equal((h.match(/href="tel:/g) || []).length, 3);
});

test('salesTel: «+» / 00 bilan boshlangan 9 xonali qism O‘zbekiston raqamiga aylanmaydi (chala xorijiy raqam — begona odamga havola yo‘q); 00 — xalqaro prefiks; raqamsiz qism (izoh qoldig‘i) ko‘rsatilmaydi', () => {
  const E = salesEnv();
  const t = (p, v) => E.ctx.salesTel(p, v);
  const h1 = t('+44 7700 900', false);
  assert.doesNotMatch(h1, /tel:/, 'chala xorijiy (9 raqam, «+» bilan) — havola yo‘q (avval tel:+998447700900 bo‘lardi)');
  assert.match(h1, /\+44 7700 900<\/span> <span[^>]*>\(raqam noto‘g‘ri yozilgan bo‘lishi mumkin — ma’muriyatga xabar bering\)/);
  const h2 = t('+998 00 111 00 31, +44 7700 900', false);
  assert.equal((h2.match(/href="tel:/g) || []).length, 1, 'bir katakda: to‘g‘ri raqam — havola, chala xorijiy — matn');
  assert.match(h2, /href="tel:\+998001110031"/);
  assert.doesNotMatch(h2, /tel:\+?998447700900/);
  assert.match(h2, /\(bir katakda bir nechta raqam yozilgan, biri noto‘g‘ri bo‘lishi mumkin — ma’muriyatga xabar bering\)/, 'havolasiz qism bor — ogohlantirish');
  assert.match(t('00 44 7700 900033', false), /href="tel:\+447700900033"/, '00 — xalqaro chiqish prefiksi');
  assert.doesNotMatch(t('00 44 7700 9', false), /tel:/, '00 bilan chala raqam — havola yo‘q');
  const h5 = t('+998 00 888 00 05, +998 00 888 00 06 (         ,                )', false);   // raqamsiz qism (server endi bunday qismni yubormaydi — sahifa ham ko'rsatmaydi)
  assert.equal((h5.match(/href="tel:/g) || []).length, 2);
  assert.doesNotMatch(h5, /<span style="white-space:nowrap">\)<\/span>/, 'raqamsiz qism («)») ko‘rsatilmaydi');
  assert.match(h5, /\(bir katakda bir nechta raqam yozilgan\)/);
});

test('renderSales: kunlik chegara va topilmadi — xabar, raqam ochilmaydi, tugma qayta yoqiladi; tarmoq xatosi — xabar', async () => {
  const E = salesEnv({ rows: [R1, R2], todayUsed: 149, reveal: { [R1.k]: { ok: false, reason: 'daily_cap', todayUsed: 150, dailyCap: 150 }, [R2.k]: { ok: false, reason: 'not_found' } } });
  await E.render();
  const [b1, b2] = E.D.els['#sl-list'].querySelectorAll('[data-slk]');
  await b1.onclick();
  assert.match(E.toasts.at(-1)[0], /Bugungi chegara tugadi — kuniga 150 ta oila/);
  assert.equal(E.toasts.at(-1)[1], true);
  assert.equal(b1.disabled, false, 'tugma qayta yoqildi');
  assert.equal(E.used(), 'Bugun ochilgan: 150 / 150');
  assert.doesNotMatch(E.list(), /tel:/);
  await b2.onclick();
  assert.match(E.toasts.at(-1)[0], /endi ro‘yxatda yo‘q/);
  const E2 = salesEnv({ rows: [R1], reveal: { [R1.k]: Object.assign(new Error('Failed to fetch'), { code: '' }) } });
  await E2.render();
  await E2.D.els['#sl-list'].querySelectorAll('[data-slk]')[0].onclick();
  assert.match(E2.toasts.at(-1)[0], /^Xatolik: Failed to fetch/);
  assert.doesNotMatch(E2.list(), /tel:/);
});

test('renderSales: qidiruv (kamida 2 belgi, faqat ota-ona ismi) va sahifalash', async () => {
  const many = Array.from({ length: 120 }, (_, i) => ({ k: i.toString(16).padStart(32, '0'), father: { name: 'Sinov Ota ' + i, phone: '+998 00 *** ** ' + String(i % 100).padStart(2, '0') }, mother: null }));
  const E = salesEnv({ rows: many });
  await E.render();
  assert.match(E.D.els['#sl-pager']._h, /1–50 \/ 120/);
  assert.match(E.D.els['#sl-total'].textContent, /^120 ta oila$/);
  await E.D.els['#sl-next'].onclick(); await tick();
  assert.deepEqual(E.calls.at(-1), ['sales_contacts', { p_q: null, p_limit: 50, p_offset: 50 }]);
  assert.match(E.D.els['#sl-pager']._h, /51–100 \/ 120/);
  const qi = E.D.els['#sl-q'];
  qi.value = 'a'; qi.listeners.input[0](); await tick(350);
  assert.deepEqual(E.calls.at(-1), ['sales_contacts', { p_q: null, p_limit: 50, p_offset: 0 }], '1 belgi — filtrsiz, birinchi sahifadan');
  qi.value = '  Ota 11 '; qi.listeners.input[0](); await tick(350);
  assert.deepEqual(E.calls.at(-1), ['sales_contacts', { p_q: 'Ota 11', p_limit: 50, p_offset: 0 }]);
  assert.match(E.D.els['#sl-total'].textContent, /\(qidiruv bo‘yicha\)/);
});

test('renderSales: server hali yangilanmagan / ruxsat yo‘q — tushunarli xabar', async () => {
  const E = salesEnv({ contactsErr: Object.assign(new Error('Could not find the function public.sales_contacts'), { code: 'PGRST202' }) });
  await E.render();
  assert.match(E.list(), /serverda hali yoqilmagan/);
  const E2 = salesEnv({ contactsErr: Object.assign(new Error('Ruxsat yo‘q'), { code: '42501' }) });
  await E2.render();
  assert.match(E2.list(), /Ruxsat yo‘q: bu bo‘lim faqat sotuvchi va Direktor uchun/);
});

test('renderSales (Direktor): ro‘yxat + «Sotuvchilar jurnali» (sales_log, telefonsiz)', async () => {
  const log = { ok: true, dailyCap: 150, days: [{ day: '2026-11-19', uid: 'U_SAL', name: 'Sinov Sotuvchi', role: 'sales', count: 12 }],
    recent: [{ at: '2026-11-19T10:15:00+05:00', day: '2026-11-19', uid: 'U_SAL', name: 'Sinov Sotuvchi', role: 'sales', father: 'Sinov Ota Alfa', mother: 'Sinov Ona Alfa' },
             { at: '2026-11-19T10:10:00+05:00', day: '2026-11-19', uid: 'U_DIR', name: 'Sinov Direktor', role: 'director', father: null, mother: null }] };
  const E = salesEnv({ isAdmin: true, rows: [R1], log });
  await E.render();
  assert.deepEqual(E.calls.map(c => c[0]).sort(), ['sales_contacts', 'sales_log']);
  assert.deepEqual(E.calls.find(c => c[0] === 'sales_log')[1], { p_days: 30 });
  const lg = E.D.els['#sl-log']._h;
  assert.match(lg, /Kunlar bo‘yicha[\s\S]*19\.11\.2026[\s\S]*Sinov Sotuvchi[\s\S]*Sotuvchi[\s\S]*<b>12<\/b> \/ 150/);
  assert.match(lg, /Oxirgi ochishlar \(2\)[\s\S]*Sinov Sotuvchi[\s\S]*Sinov Ota Alfa[\s\S]*Sinov Ona Alfa[\s\S]*Sinov Direktor/);
  assert.doesNotMatch(lg, /\d{7,}|tel:/, 'jurnalda telefon yo‘q');
  assert.match(E.D.els['#view']._h, /Sotuvchilar jurnali/);
});

test('Foydalanuvchilar / HR / menyu / qidiruv / muharrirlar / sayt: sotuvchi roli to‘g‘ri ulangan', () => {
  // Foydalanuvchilar → rol tanlovi
  assert.match(ADM, /\['sales','Sotuvchi \(marketing\) — faqat ota-onalar ismi va telefoni, o‘zgartirish yo‘q'\]/);
  // «➕ Lavozim» tugmasi va tahrir oynasidagi qo'shimcha rol qoidasi sotuvchini qo'shimchasiz deb biladi
  assert.match(ADM, /const xrBtn=r=> \(!SESSION\.isAdmin \|\| String\(r\._id\)===myUid \|\| \['director','parent','student','accountant','sales','staff',''\]/);
  assert.match(ADM, /const xrOk=r=>!\['director','parent','student','accountant','sales',''\]/);
  // HR lavozimi «Sotuvchi» -> rol
  const ctx = vm.createContext({});
  vm.runInContext(block('// HR lavozimi', '// Rol + sinf/fan biriktirish oynasi') + '\n;this.__p = posToRole;', ctx);
  assert.equal(ctx.__p('Sotuvchi'), 'sales');
  assert.equal(ctx.__p('  sotuvchi '), 'sales');
  assert.equal(ctx.__p('Marketing menejeri'), 'marketing_mgr', 'marketing menejeri — avvalgidek');
  assert.ok(topConst('STAFF_POSITIONS').includes("'Sotuvchi'"));
  // menyu: bo'lim «O‘quvchilar» guruhida, ikonasi bor, render ulangan
  const ng = vm.runInContext(constBlock('NAV_GROUPS') + ';NAV_GROUPS', vm.createContext({}));
  assert.ok(ng.find(g => g.g === 'qabul').keys.includes('sales'));
  assert.match(ADM, /\{k:'sales', icon:mi\('M[^']+'\), t:'Ota-onalar bilan aloqa'\}/);
  assert.match(ADM, /if\(tab==='sales'\) return renderSales\(\);/);
  // 🔍 qidiruv sotuvchiga ochilmaydi (DOM'ga tegmasdan qaytadi)
  const g = vm.createContext({ SESSION: { role: 'sales', isAdmin: false }, $: () => { throw new Error('DOM ga tegdi'); } });
  vm.runInContext(fn('openGlobalSearch') + '\n;this.__g = openGlobalSearch;', g);
  assert.doesNotThrow(() => g.__g());
  // xabarnoma muharriri ro'yxatiga sotuvchi tushmaydi
  assert.match(ADM, /const NO=new Set\(\['parent','student','director','sales',''\]\);/);
  // saytdagi «Admin panel» havolasi (admin.html STAFF bilan bir xil)
  assert.match(IDX, /let adminOk = \[[^\]]*'accountant','sales'\]\.includes\(role\)/);
  assert.match(BOOT_SRC, /const STAFF = \[[^\]]*'accountant','sales'\];/);
});

// ---------------- 4-mustaqil tekshiruv: jurnal / raqam matni ekranlanishi, Direktor oynasida ism yozilishi ----------------
test('Jurnal (4-tekshiruv): jurnal: ism / hozirgi ism / ota ismi — matn sifatida (ekranlangan); «(hozir: …)» ko‘rinadi', async () => {
  const bad = '<img src=x onerror=alert(1)>';
  const log = { ok: true, dailyCap: 150,
    days: [{ day: '2026-11-19', uid: 'U_SAL', name: bad, nameNow: '<b>x</b>', role: 'sales', count: 1 }],
    recent: [{ at: '2026-11-19T10:15:00+05:00', day: '2026-11-19', uid: 'U_SAL', name: bad, nameNow: '<b>x</b>', role: 'sales', father: '<i>f</i>', mother: null }] };
  const E = salesEnv({ isAdmin: true, rows: [], log });
  await E.render();
  const lg = E.D.els['#sl-log']._h;
  assert.doesNotMatch(lg, /<img|<b>x|<i>f/, 'xom HTML yo‘q');
  assert.equal((lg.match(/&lt;img src=x onerror=alert\(1\)&gt; <span class="small muted">\(hozir: &lt;b&gt;x&lt;\/b&gt;\)<\/span>/g) || []).length, 2, 'kunlar va oxirgi ochishlar: «(hozir: …)»');
  assert.match(lg, /&lt;i&gt;f&lt;\/i&gt;/);
});

test('salesTel (4-tekshiruv): salesTel: havolasiz matn qismi ekranlanadi', () => {
  const E = salesEnv();
  const h = E.ctx.salesTel('<img src=x onerror=alert(1)> 1234567', false);
  assert.doesNotMatch(h, /<img/);
  assert.match(h, /&lt;img src=x onerror=alert\(1\)&gt; 1234567<\/span>/);
});

// openUserEditor — haqiqiy kod (admin.html), soxta DOM va baza.
function editorEnv(u) {
  const alerts = [], writes = [], byId = {};
  const unesc = s => s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  const mkEl = id => ({ id, value: '', checked: false, disabled: false, textContent: '', style: {}, onclick: null, addEventListener() {}, remove() {} });
  const ov = { style: {}, _h: '', addEventListener() {}, remove() {}, querySelector: s => byId[s] || null, querySelectorAll: () => [] };
  Object.defineProperty(ov, 'innerHTML', { get: () => ov._h, set: h => { ov._h = String(h);
    for (const m of ov._h.matchAll(/<(input|select|button|div)\b[^>]*?\bid="([^"]+)"[^>]*>/g)) {
      const e = mkEl(m[2]); const v = /\bvalue="([^"]*)"/.exec(m[0]);
      if (m[1] === 'input' && v) e.value = unesc(v[1]);
      if (m[1] === 'input' && /\schecked\b/.test(m[0])) e.checked = true;
      byId['#' + m[2]] = e;
    }
    const sel = /<select id="u-role"[\s\S]*?<\/select>/.exec(ov._h); if (sel) { const o = /<option value="([^"]*)" selected>/.exec(sel[0]); byId['#u-role'].value = o ? o[1] : ''; }
  } });
  const ctx = vm.createContext({
    auth: { currentUser: { uid: 'U_DIR' } }, alert: m => alerts.push(String(m)), toast: () => {}, cache: {}, renderUsers: () => {},
    document: { createElement: () => ov, body: { appendChild() {} }, addEventListener() {}, removeEventListener() {} },
    db: {}, doc: (...a) => a, getDoc: async () => ({ exists: () => true, data: () => ({ status: 'active' }) }),
    setDoc: async (_r, p) => { writes.push({ ...p }); }, updateDoc: async () => {}, serverTimestamp: () => 'TS',
  });
  vm.runInContext([topConst('esc'), topConst('EXTRA_ROLES_OK'), topConst('SUBJECTS'), PHONE, fn('pmCanonStored'), fn('classKeyLabel'),
    block('// HR lavozimi', '// Rol + sinf/fan biriktirish oynasi'), fn('openUserEditor'), ';this.__ed = openUserEditor;'].join('\n'), ctx);
  ctx.__ed(u, { keys: [], classes: {} }, [['teacher', 'O‘qituvchi'], ['guard', 'Qorovul'], ['sales', 'Sotuvchi']], {});
  return { byId, alerts, writes, save: () => byId['#u-save'].onclick() };
}

test('Direktor oynasi (4-tekshiruv): openUserEditor: ismga tegilmasa — ism yozilmaydi (bir so‘zli ism rol saqlashni to‘smaydi); bo‘sh / faqat probel — ogohlantirish; o‘zgarsa — yoziladi', async () => {
  const base = { _id: 'U1', role: 'teacher', status: 'active', verified: true };
  // bir so'zli ism, firstName/lastName yo'q — faqat rol o'zgaradi
  const A = editorEnv({ ...base, name: 'Madonna' });
  assert.equal(A.byId['#u-first'].value, 'Madonna'); assert.equal(A.byId['#u-last'].value, '');
  A.byId['#u-role'].value = 'guard';
  await A.save();
  assert.deepEqual(A.alerts, []);
  assert.equal(A.writes.length, 1);
  assert.equal(A.writes[0].role, 'guard');
  for (const k of ['name', 'firstName', 'lastName']) assert.ok(!(k in A.writes[0]), 'tegilmagan ism yozildi: ' + k);
  // ikki so'zli ism (firstName/lastName yo'q): oldindan bo'lingan, tegilmasa yozilmaydi
  const B = editorEnv({ ...base, name: 'Sinov  Sotuvchi Ikki' });
  assert.equal(B.byId['#u-first'].value, 'Sinov'); assert.equal(B.byId['#u-last'].value, 'Sotuvchi Ikki');
  await B.save();
  assert.equal(B.writes.length, 1); assert.ok(!('name' in B.writes[0]));
  // faqat probel — ogohlantirish, yozuv yo'q
  const C = editorEnv({ ...base, name: 'Madonna' });
  C.byId['#u-first'].value = '   '; C.byId['#u-last'].value = '  ';
  await C.save();
  assert.equal(C.alerts.length, 1); assert.match(C.alerts[0], /Ism va familiyani kiriting/); assert.equal(C.writes.length, 0);
  // o'zgardi — ikkalasi ham yoziladi
  const D = editorEnv({ ...base, name: 'Madonna' });
  D.byId['#u-first'].value = ' Ali '; D.byId['#u-last'].value = 'Valiyev';
  await D.save();
  assert.equal(D.writes.length, 1);
  assert.deepEqual([D.writes[0].firstName, D.writes[0].lastName, D.writes[0].name], ['Ali', 'Valiyev', 'Ali Valiyev']);
});

test('Raqam qoidasi (5-tekshiruv): migration/sales-role.sql (app.sales_intl_ok) davlat kodlari va uzunliklari — admin.html PHONE_CC / PHONE_LEN bilan AYNAN bir xil', () => {
  const SQL = readFileSync(new URL('../../migration/sales-role.sql', import.meta.url), 'utf8');
  const a = SQL.indexOf('create or replace function app.sales_intl_ok'), b = a >= 0 ? SQL.indexOf('$$;', a) : -1;
  assert.ok(a >= 0 && b > a, 'app.sales_intl_ok topilmadi');
  const src = SQL.slice(a, b);
  const ctx = {}; vm.runInNewContext(PHONE, ctx);
  assert.ok(ctx.PHONE_CC && ctx.PHONE_LEN, 'admin.html PHONE-CANON bloki o‘qilmadi');
  const lenM = src.match(/'(\{"[^']*\})'::jsonb/);
  assert.ok(lenM, 'PHONE_LEN jsonb topilmadi');
  assert.deepEqual(JSON.parse(lenM[1]), JSON.parse(JSON.stringify(ctx.PHONE_LEN)));
  const arrs = [...src.matchAll(/left\(d, (\d)\) = any\('\{([0-9,]+)\}'::text\[\]\)/g)].map(m => ({ n: +m[1], keys: m[2].split(',') }));
  assert.deepEqual(arrs.map(x => x.n), [3, 2, 1], 'davlat kodi eng uzunidan boshlab tekshirilsin (phoneCc kabi)');
  for (const x of arrs) for (const k of x.keys) assert.equal(k.length, x.n, `${k} — ${x.n} xonali ro‘yxatda`);
  assert.deepEqual(arrs.flatMap(x => x.keys).sort(), Object.keys(ctx.PHONE_CC).sort());
});

test('salesTel (7-tekshiruv): «+» / 00 dan keyingi nollar tashlanadi (server app.tg_phone va phoneCanon kabi) — server qo‘ng‘iroq qilsa bo‘ladi degan qism havolasiz qolmaydi; chala raqam — havolasiz', () => {
  const E = salesEnv();
  const t = (p, v) => E.ctx.salesTel(p, v);
  const h1 = t('+0998 00 123 45 67, +998 00 765 43 21', false);
  assert.match(h1, /href="tel:\+998001234567"/, '«+0998 …» — havola (avval matn bo‘lib qolardi)');
  assert.match(h1, /href="tel:\+998007654321"/);
  assert.match(h1, /\(bir katakda bir nechta raqam yozilgan\)/, 'ikkala qism ham havola — «biri noto‘g‘ri» deyilmaydi');
  for (const p of ['+0 44 7700 900123', '00 0 44 7700 900123', '0000 44 7700 900123'])
    assert.match(t(p, false), /href="tel:\+447700900123"/, p);
  assert.match(t('+0998 00 123 45 67', false), /href="tel:\+998001234567"/);
  assert.doesNotMatch(t('+0 44 7700 9001', false), /tel:/, 'chala xorijiy raqam — havola yo‘q');
  assert.doesNotMatch(t('+0 01 234 56 78', false), /tel:/, '«+0» bilan 8 raqam — O‘zbekiston raqamiga aylanmaydi');
});
