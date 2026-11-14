// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik): kassa ISHGA TUSHMAGAN holatda (yoki kassa funksiyalari umuman yo'q) eski oqimlar o'zgarmagani:
//   maosh berish, xodim avansi, xarajat qo'shish, to'lovni qaytarish — avvalgi yo'l bilan yoziladi.  node scenarios/e2e-legacy.cjs
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E;
const { session, ids } = E;
const q = E.q;
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 600))); };
const errs = [];
(async () => {
  const b = await E.launch(); const uid = ids.R_DIR, email = q(`select email from public.users where id='${uid}'`);
  const hasKassa = q(`select (to_regclass('public.cash_docs') is not null)::text`) === 'true';
  const col = (t, c) => q(`select count(*) from information_schema.columns where table_schema='public' and table_name='${t}' and column_name='${c}'`) === '1';
  const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 1440, height: 900 } });
  await ctx.addInitScript(([k, v]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} }, ['sb-127-auth-token', JSON.stringify(session(uid, email, {}))]);
  const pg = await ctx.newPage();
  pg.on('pageerror', e => errs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
  pg.on('dialog', d => d.accept().catch(() => {}));
  await pg.goto(E.BASE + '/admin.html');
  await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 }); await pg.waitForTimeout(800);
  const tab = async k => { await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
  ok(hasKassa ? 'kassa o‘rnatilgan, ishga tushmagan: menyuda «Kassa» bor' : 'kassa funksiyalari yo‘q: menyuda «Kassa» yo‘q', !!(await pg.$('#tabs button[data-tab="kassa"]')) === hasKassa);
  // maosh
  await tab('accounting'); await pg.waitForSelector('#ac-paysal', { timeout: 30000 });
  await pg.click('#ac-paysal'); await pg.waitForSelector('#sp-do', { timeout: 30000 });
  ok('maosh oynasi: to‘lov usuli so‘ralmaydi (avvalgidek)', !(await pg.$('#sp-method')));
  await pg.selectOption('#sp-t', 'IQT-001');
  await pg.waitForFunction(() => { const x = document.querySelector('#sp-do'); return x && !x.disabled; }, null, { timeout: 30000 });
  await pg.fill('#sp-paid', '500 000'); await pg.click('#sp-do');
  await pg.waitForFunction(() => /Maosh berildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});
  ok('maosh berildi: avvalgi yo‘l (termal chek tugmasi, kassa orderisiz)', !!(await pg.$('#sp-print')) && !(await pg.$('#sp-ko2')) && q(`select trim_scale(paid) || ':' || ("byUid" = '${uid}') || ':' || ("byEmail" <> '') from public.salary_payments where "teacherId"='IQT-001'`) === '500000:true:true',
    q(`select paid, "byUid", "byEmail" from public.salary_payments where "teacherId"='IQT-001'`));
  if (hasKassa) ok('… usul va kassa havolasi bo‘sh', q(`select coalesce(method,'-') || ':' || coalesce("cashDocId",'-') from public.salary_payments where "teacherId"='IQT-001'`) === '-:-');
  await pg.click('#sp-close').catch(() => {}); await pg.waitForTimeout(700);
  // avans
  await pg.waitForSelector('#ac-adv'); await pg.click('#ac-adv'); await pg.waitForSelector('#av-save', { timeout: 30000 });
  ok('avans oynasi: kassa yo‘llanmasi yo‘q (avvalgidek)', !(await pg.$('#av-kassa')) && (await pg.$eval('#av-save', e => e.textContent)) === 'Saqlash');
  await pg.selectOption('#av-t', 'IQX-001'); await pg.fill('#av-amt', '150 000'); await pg.click('#av-save');
  await pg.waitForFunction(() => /avansi yozildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
  ok('avans yozildi', q(`select trim_scale(amount)::text from public.staff_advances where "teacherId"='IQX-001'`) === '150000', q(`select * from public.staff_advances`));
  await pg.click('#av-close').catch(() => {}); await pg.waitForTimeout(700);
  // xarajat
  await pg.waitForSelector('#ac-add'); await pg.click('#ac-add'); await pg.waitForSelector('#e-save', { timeout: 10000 });
  ok('xarajat oynasi: to‘lov usuli so‘ralmaydi (avvalgidek)', !(await pg.$('#e-method')) && !(await pg.$('#e-kassa')));
  await pg.selectOption('#e-cat', 'Kommunal'); await pg.fill('#e-amt', '900 000'); await pg.fill('#e-note', 'Sinov kommunal (eski yo‘l)'); await pg.click('#e-save');
  await pg.waitForFunction(() => /Xarajat saqlandi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
  ok('xarajat saqlandi', q(`select category || ':' || trim_scale(amount) from public.expenses where note='Sinov kommunal (eski yo‘l)'`) === 'Kommunal:900000');
  if (col('expenses', 'articleId')) ok('… statiya toifadan o‘zi qo‘yildi, usul bo‘sh', q(`select coalesce("articleId",'-') || ':' || coalesce(method,'-') from public.expenses where note='Sinov kommunal (eski yo‘l)'`) === 'EX-11:-');
  await pg.click('#e-close').catch(() => {}); await pg.waitForTimeout(500);
  // qaytarish
  await tab('payments'); await pg.waitForSelector('#pm-body [data-refund]', { timeout: 30000 });
  const inv = (await pg.$$eval('#pm-body [data-refund]', bs => bs.map(x => x.dataset.refund)))[0];
  const paid0 = Number(q(`select coalesce("paidAmount",0)::bigint from public.invoices where id='${inv}'`)), ref0 = Number(q(`select count(*) from public.refunds`));
  await pg.click(`#pm-body [data-refund="${inv}"]`); await pg.waitForSelector('#rf-do', { timeout: 15000 });
  ok('qaytarish oynasi: usul so‘ralmaydi (avvalgidek)', !(await pg.$('#rf-method')) && (await pg.$eval('#rf-do', e => e.textContent)) === 'Qaytarish');
  await pg.fill('#rf-amt', '200 000'); await pg.fill('#rf-reason', 'Sinov qaytarish (eski yo‘l)');
  if (await pg.$('#rf-pass')) await pg.fill('#rf-pass', q(`select coalesce("refundPin",'') from public.config where id='security'`));
  await pg.click('#rf-do');
  await pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).catch(() => {});
  ok('qaytarildi: darhol (faktura kamaydi, jurnal yozildi)', Number(q(`select coalesce("paidAmount",0)::bigint from public.invoices where id='${inv}'`)) === paid0 - 200000 && Number(q(`select count(*) from public.refunds`)) === ref0 + 1,
    [paid0, q(`select "paidAmount" from public.invoices where id='${inv}'`), ref0, q(`select count(*) from public.refunds`)]);
  // Buxgalter roli: kassa moduli bo'lsa — «Kassa» bo'limi; bo'lmasa — bo'limsiz, tushunarli xabar (xatosiz); rol tanlovda faqat modul bilan
  {
    const ACC = 'u_acc_legacy';
    q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter@legacy.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status`);
    const c2 = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 1440, height: 900 } });
    await c2.addInitScript(([k, v]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} }, ['sb-127-auth-token', JSON.stringify(session(ACC, 'buxgalter@legacy.test', { displayName: 'SINOV' }))]);
    const p2 = await c2.newPage();
    p2.on('pageerror', e => errs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    await p2.goto(E.BASE + '/admin.html');
    await p2.waitForFunction(() => { const v = document.querySelector('#view'); return v && /yoqilmagan|Kassa|Tasdiqlash/.test(v.innerText) && !/yuklanmoqda/i.test(v.innerText); }, null, { timeout: 30000 }).catch(() => {});
    await p2.waitForTimeout(600);
    const tabs = await p2.$$eval('#tabs button[data-tab]', a => a.map(x => x.dataset.tab));
    const txt = await p2.$eval('#view', e => e.innerText).catch(() => '');
    ok(hasKassa ? 'buxgalter (kassa o‘rnatilgan): menyuda «Kassa» bor' : 'buxgalter (kassa moduli yo‘q): bo‘limlar yo‘q, «hali yoqilmagan» xabari',
      hasKassa ? tabs.includes('kassa') : (tabs.length === 0 && /«Buxgalter» roli uchun bo‘limlar bu tizimda hali yoqilmagan/.test(txt)), { tabs, txt: txt.slice(0, 200) });
    await c2.close();
  }
  ok('sahifa xatosi yo‘q', errs.length === 0, errs);
  console.log(`JAMI: ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
})().catch(e => { console.error('XATO', e); process.exit(1); });
