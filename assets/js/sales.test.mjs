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
    accFinOk: () => false, canSeeSalary: () => false, currentTab: 'dashboard',
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
