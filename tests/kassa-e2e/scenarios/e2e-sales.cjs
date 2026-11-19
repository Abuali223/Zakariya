// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): «SOTUVCHI» roli (egasi 2026-11-19: «ikkita
//   sotuvchi … ota-onalar ismi va telefon raqamini o'zini ko'ra olishi kerak; qolgan ma'lumotlar ko'rinmasligi va o'zgartira olmasligi
//   kerak»; migration/sales-role.sql, SESSIYA-ISHLARI.md §85).
//   Sotuvchi: menyuda yagona «Ota-onalar bilan aloqa» bo'limi, faol o'quvchilar oilalari (arxivdagi IQ-0017 siz) niqoblangan raqam bilan,
//   «📞 Raqamni ko‘rsatish» → tel: havolasi va jurnal yozuvi, hisoblagich, ota-ona ismi bo'yicha qidiruv; 🔍 qidiruv va to'lov navbati
//   yo'q, tahrir / eksport tugmasi yo'q; REST orqali o'quvchi va shaxsiy karta jadvallari bo'sh, jurnal va Direktor jurnali — rad;
//   sahifa va konsol xatolari yo'q. Direktor: bo'lim «O‘quvchilar» guruhida, «Sotuvchilar jurnali»da sotuvchining ochishi;
//   «Foydalanuvchilar» → rol tanlovida «Sotuvchi …».
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-sales.cjs [v1|v2]
const E = require('../lib/common.cjs'); const fs = require('fs'); const crypto = require('crypto');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [], conErrs = [], netErrs = [];   // konsol xatolari; 4xx/5xx javoblar va uzilgan so'rovlar (har seans — teg bilan)
const SALES_OPT = 'Sotuvchi (marketing) — faqat ota-onalar ismi va telefoni, o‘zgartirish yo‘q';
(async () => {
  const b = await E.launch();
  // tayyorgarlik: sotuvchi hisobi (asosiy rol «Sotuvchi», qo'shimcha lavozimsiz). Qo'shimcha lavozim bilan yaratib bo'lmaydi (baza rad etadi).
  let xr = 'ok'; try { q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${crypto.randomUUID()}', 'sotuvchi2@example.org', 'Sinov Sotuvchi Ikki', 'sales', 'active', true, '["kassir"]')`); } catch (e) { xr = String(e.message || e); }
  const SAL = crypto.randomUUID();
  q(`insert into public.users (id, email, name, role, status, verified, phone) values ('${SAL}', 'sotuvchi@example.org', 'Sinov Sotuvchi', 'sales', 'active', true, '998000000013')`);
  ok('tayyorlov: sotuvchi hisobi yaratildi; qo‘shimcha lavozimli sotuvchi hisobini baza rad etadi',
    q(`select role || ':' || "extraRoles"::text from public.users where id = '${SAL}'`) === 'sales:[]' && /qo'shimcha lavozim berilmaydi/i.test(xr), xr);
  const famN = Number(q('select count(*) from app.sales_families(false)'));
  const famAll = Number(q('select count(*) from app.sales_families(true)'));

  async function login(uid) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage();
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    const who = uid === SAL ? 'sotuvchi' : 'direktor';
    pg.on('console', m => { if (m.type() === 'error') conErrs.push(who + ': ' + m.text().slice(0, 300)); });
    pg.on('response', r => { if (r.status() >= 400) netErrs.push(who + ': ' + r.status() + ' ' + r.url().slice(0, 160)); });
    pg.on('requestfailed', r => netErrs.push(who + ': uzildi ' + r.url().slice(0, 160)));
    pg.on('dialog', d => d.accept().catch(() => {}));
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);
    return { ctx, pg };
  }
  const rowsOf = pg => pg.evaluate(() => [...document.querySelectorAll('#sl-list tr[data-slrow]')].map(tr => ({ k: tr.dataset.slrow,
    cells: [...tr.querySelectorAll('td[data-label]')].map(td => ({ name: (td.querySelector('div') || {}).textContent || '', phone: ((td.querySelectorAll('div')[1]) || {}).textContent || '' })),
    tel: [...tr.querySelectorAll('a[href^="tel:"]')].map(a => a.getAttribute('href')), btn: !!tr.querySelector('[data-slk]') })));

  // ===================== SOTUVCHI =====================
  const S = await login(SAL); const pg = S.pg;
  await pg.waitForSelector('#sl-list table, #sl-list .empty', { timeout: 20000 }); await pg.waitForTimeout(400);
  const tabs = await pg.evaluate(() => [...document.querySelectorAll('#tabs button[data-tab]')].map(x => x.dataset.tab));
  ok('sotuvchi: menyuda yagona bo‘lim — «Ota-onalar bilan aloqa»; sahifa sarlavhasi', tabs.join(',') === 'sales' && /📞 Ota-onalar bilan aloqa/.test(await pg.textContent('#view h2')), tabs);
  const rows = await rowsOf(pg);
  ok(`faol oilalar ro‘yxati: ${famN} ta (arxivdagi o‘quvchi oilasi yo‘q — jami ${famAll}); jami yozuvi`,
    famN > 0 && famN < famAll && rows.length === Math.min(famN, 50) && (await pg.textContent('#sl-total')).trim() === `${famN} ta oila`, [famN, famAll, rows.length, await pg.textContent('#sl-total')]);
  const phones = rows.flatMap(r => r.cells.map(c => c.phone)).filter(Boolean);
  ok('raqamlar niqoblangan («+998 00 *** ** NN»), tel: havolasi yo‘q; har oilada «📞 Raqamni ko‘rsatish»',
    phones.length > 0 && phones.every(p => /^\+998 \d{2} \*\*\* \*\* \d{2}$|^raqam yo‘q$/.test(p.trim())) && rows.every(r => !r.tel.length && r.btn), phones.slice(0, 4));
  const ui = await pg.evaluate(() => ({ search: getComputedStyle(document.getElementById('btn-search')).display, ob: !!document.getElementById('ob-badge'),
    btns: [...document.querySelectorAll('#view button')].filter(x => !x.hasAttribute('data-slk') && !/^sl-(prev|next)$/.test(x.id)).map(x => x.textContent.trim()),
    inputs: [...document.querySelectorAll('#view input, #view textarea, #view select')].map(x => x.id), used: document.getElementById('sl-used').textContent,
    text: document.getElementById('view').innerText }));
  ok('🔍 qidiruv yashirin, to‘lov navbati belgisi yo‘q; ochish tugmasidan boshqa tugma, qidiruvdan boshqa maydon yo‘q; o‘quvchi ismi ko‘rinmaydi',
    ui.search === 'none' && !ui.ob && ui.btns.length === 0 && ui.inputs.join(',') === 'sl-q' && !/IQ-00|Sinov Bola|Sinov manzil/.test(ui.text), ui);
  ok('hisoblagich: «Bugun ochilgan: 0 / 150»', ui.used.trim() === 'Bugun ochilgan: 0 / 150', ui.used);
  // ochish
  const r0 = rows[0];
  await pg.click(`#sl-list [data-slk="${r0.k}"]`);
  await pg.waitForFunction(k => !!document.querySelector(`#sl-list tr[data-slrow="${k}"] a[href^="tel:"]`), r0.k, { timeout: 15000 });
  const r0b = (await rowsOf(pg)).find(r => r.k === r0.k);
  const fam = q(`select coalesce(f_phone, '') || '|' || coalesce(m_phone, '') from app.sales_families(false) where fkey = '${r0.k}'`).split('|').filter(Boolean);
  ok('«📞 Raqamni ko‘rsatish»: raqamlar tel: havolasi (kartadagi raqam), tugma o‘rnida «✓ Raqam ochilgan»; hisoblagich 1 / 150; jurnalda 1 yozuv',
    r0b && r0b.tel.length === fam.length && r0b.tel.every(t => fam.includes(t.replace(/^tel:\+/, ''))) && !r0b.btn
    && (await pg.textContent('#sl-used')).trim() === 'Bugun ochilgan: 1 / 150'
    && q(`select count(*) || ':' || min(fkey) from public.sales_contact_log where uid = '${SAL}'`) === `1:${r0.k}`, [r0b, fam, await pg.textContent('#sl-used')]);
  // qidiruv (ota ismi)
  const r1 = rows[1]; const nm = r1.cells[0].name.trim();
  await pg.fill('#sl-q', nm.split(' ').slice(-2).join(' ')); await pg.waitForTimeout(900);
  const rs = await rowsOf(pg);
  ok('qidiruv — ota-ona ismi bo‘yicha: natijada shu ism, jami «(qidiruv bo‘yicha)»',
    rs.length >= 1 && rs.every(r => r.cells.some(c => c.name.includes(nm.split(' ').slice(-2).join(' ')))) && /qidiruv bo‘yicha/.test(await pg.textContent('#sl-total')), [nm, rs.length]);
  // Kirish va ish davomida (REST sinovlaridan OLDIN): konsolda xato yo'q, rad etilgan / uzilgan so'rov yo'q — stend tashqi xostlarni
  //   (Google shriftlari) yopadi, o'shalar hisobga olinmaydi.
  const extOk = x => / uzildi https?:\/\/(?!127\.0\.0\.1)/.test(x);
  const sNet = netErrs.filter(x => x.startsWith('sotuvchi:') && !extOk(x)), sCon = conErrs.filter(x => x.startsWith('sotuvchi:') && !/net::ERR_FAILED/.test(x));
  ok('sotuvchi seansi: konsolda xato yo‘q, RLS rad etgan (4xx) yoki uzilgan lokal so‘rov yo‘q (kuzatuv, kassa, belgilar, muharrir — jim)',
    sNet.length === 0 && sCon.length === 0, { sNet, sCon });
  // REST orqali (sotuvchi seansi bilan): jadvallar bo'sh, jurnal va Direktor jurnali — rad
  const rest = await pg.evaluate(async () => {
    const at = JSON.parse(localStorage.getItem('sb-127-auth-token') || '{}').access_token;
    const h = { Authorization: 'Bearer ' + at, 'Content-Type': 'application/json' };
    const get = async p => { const r = await fetch('/rest/v1/' + p, { headers: h }); return r.status + ':' + (await r.text()).slice(0, 60); };
    const rpc = async (f, a) => { const r = await fetch('/rest/v1/rpc/' + f, { method: 'POST', headers: h, body: JSON.stringify(a || {}) }); return r.status + ':' + (await r.text()).slice(0, 80); };
    return { stu: await get('students?select=id'), priv: await get('student_private?select=id'), inv: await get('invoices?select=id'), log: await get('sales_contact_log?select=id'),
      slog: await rpc('sales_log', {}), upd: await (async () => { const r = await fetch('/rest/v1/users?id=eq.' + JSON.parse(atob(at.split('.')[1])).sub, { method: 'PATCH', headers: Object.assign({ Prefer: 'return=representation' }, h), body: JSON.stringify({ role: 'director' }) }); return r.status + ':' + (await r.text()).slice(0, 60); })() };
  });
  ok('REST (sotuvchi seansi): o‘quvchilar, shaxsiy karta, fakturalar — bo‘sh; jurnal jadvali va Direktor jurnali — rad; o‘zini Direktor qila olmaydi',
    rest.stu === '200:[]' && rest.priv === '200:[]' && rest.inv === '200:[]' && /^(401|403):/.test(rest.log) && /^(401|403):.*42501/.test(rest.slog) && /^(401|403):/.test(rest.upd)
    && q(`select role from public.users where id = '${SAL}'`) === 'sales', rest);
  await S.ctx.close();

  // ===================== DIREKTOR =====================
  const D = await login(ids.R_DIR); const pd = D.pg;
  const grp = await pd.evaluate(() => { const bt = document.querySelector('#tabs button[data-tab="sales"]'); return bt ? ((bt.closest('.nav-grp') || {}).dataset || {}).grp || 'yo‘q' : null; });
  ok('Direktor: «Ota-onalar bilan aloqa» bo‘limi «O‘quvchilar» guruhida', grp === 'qabul', grp);
  await pd.$eval('#tabs button[data-tab="sales"]', x => x.click());
  await pd.waitForSelector('#sl-log table, #sl-log .empty', { timeout: 20000 }); await pd.waitForTimeout(400);
  const lg = await pd.evaluate(() => document.getElementById('sl-log').innerText);
  const fn0 = r0.cells[0].name.trim();
  ok('Direktor: ro‘yxat (niqoblangan) va «Sotuvchilar jurnali» — sotuvchi, 1 / 150, ochilgan oila ismi; telefon raqami yo‘q',
    (await rowsOf(pd)).length === Math.min(famN, 50) && /Sinov Sotuvchi/.test(lg) && /1 \/ 150/.test(lg) && lg.includes(fn0) && !/\d{7,}/.test(lg.replace(/\s/g, '')), lg.slice(0, 400));
  // Foydalanuvchilar → sotuvchi hisobi «Tahrirlash»: rol tanlovi
  await pd.$eval('#tabs button[data-tab="users"]', x => x.click());
  await pd.waitForSelector(`#usr-card [data-edu="${SAL}"]`, { timeout: 20000 });
  const xrb = await pd.$(`#usr-card [data-xru="${SAL}"]`);
  await pd.click(`#usr-card [data-edu="${SAL}"]`); await pd.waitForSelector('#u-role', { timeout: 10000 });
  const opt = await pd.evaluate(() => { const o = document.querySelector('#u-role option[value="sales"]'); return o ? { t: o.textContent, sel: o.selected } : null; });
  ok('Foydalanuvchilar: sotuvchida «➕ Lavozim» tugmasi yo‘q; rol tanlovida «Sotuvchi (marketing) — …» va u tanlangan',
    !xrb && opt && opt.t === SALES_OPT && opt.sel, [!!xrb, opt]);
  await D.ctx.close();

  ok('sahifa xatolari yo‘q', allErrs.length === 0, allErrs.slice(0, 5));
  await b.close();
  const f = res.filter(r => !r.ok).length;
  console.log(`\nJAMI: ${res.length - f}/${res.length} PASS (${UI})`);
  process.exit(f ? 1 : 0);
})().catch(e => { console.error('XATO', e); process.exit(1); });
