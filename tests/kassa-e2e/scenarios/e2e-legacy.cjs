// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik): kassa ISHGA TUSHMAGAN holatda (yoki kassa funksiyalari umuman yo'q) eski oqimlar o'zgarmagani:
//   maosh berish, xodim avansi, xarajat qo'shish, to'lovni qaytarish — avvalgi yo'l bilan yoziladi; qaytarish oynasi kaliti (g11 live-1):
//   yuborish qulfi, javob yo'qolgach o'zgartirilgan / o'sha ma'lumot bilan qayta yuborish.  node scenarios/e2e-legacy.cjs
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
  // xabarlar (toast ~3 s da yo'qoladi) — hammasi yozib boriladi: { t: matn (bo'shliqlar bitta), err: qizil }
  await ctx.addInitScript(() => { window.__toasts = []; new MutationObserver(ms => { for (const m of ms) for (const n of m.addedNodes) if (n.classList && n.classList.contains('toast')) window.__toasts.push({ t: String(n.textContent).replace(/\s+/g, ' ').trim(), err: n.classList.contains('err') }); }).observe(document, { childList: true, subtree: true }); });
  const pg = await ctx.newPage();
  pg.on('pageerror', e => errs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
  pg.on('dialog', d => d.accept().catch(() => {}));
  await pg.goto(E.BASE + '/admin.html');
  await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 }); await pg.waitForTimeout(800);
  const tab = async k => { await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
  // «Buxgalteriya» tugmalari darhol chiziladi, ishlovchilari esa ma'lumot yuklangach (draw bilan birga) ulanadi — «Yuklanmoqda…» ketguncha kutiladi
  const acReady = async () => { await pg.waitForSelector('#ac-paysal', { timeout: 30000 }); await pg.waitForFunction(() => { const x = document.querySelector('#ac-body'); return x && !x.querySelector('.loading'); }, null, { timeout: 30000 }); };
  ok(hasKassa ? 'kassa o‘rnatilgan, ishga tushmagan: menyuda «Kassa» bor' : 'kassa funksiyalari yo‘q: menyuda «Kassa» yo‘q', !!(await pg.$('#tabs button[data-tab="kassa"]')) === hasKassa);
  // maosh
  await tab('accounting'); await acReady();
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
  // Kassa moduli yo'q (jonli zanjir) — avvalgi oyna (toifa; usul so'ralmaydi). Kassa moduli bor, kassa ishga tushmagan — F2.1 xarajatlar
  //   reyestri (fin-exp.sql): hujjat oynasi, usul (naqd — orderisiz, avvalgidek / bank / karta), statiya qatori; toifa statiyadan.
  const hasReg = q(`select (to_regclass('public.fin_exp_docs') is not null)::text`) === 'true';
  await pg.waitForSelector('#ac-add'); await pg.click('#ac-add');
  if (!hasReg) {
    await pg.waitForSelector('#e-save', { timeout: 10000 });
    ok('xarajat oynasi: to‘lov usuli so‘ralmaydi (avvalgidek)', !(await pg.$('#e-method')) && !(await pg.$('#e-kassa')));
    await pg.selectOption('#e-cat', 'Kommunal'); await pg.fill('#e-amt', '900 000'); await pg.fill('#e-note', 'Sinov kommunal (eski yo‘l)'); await pg.click('#e-save');
    await pg.waitForFunction(() => /Xarajat saqlandi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
    ok('xarajat saqlandi', q(`select category || ':' || trim_scale(amount) from public.expenses where note='Sinov kommunal (eski yo‘l)'`) === 'Kommunal:900000');
    if (col('expenses', 'articleId')) ok('… statiya toifadan o‘zi qo‘yildi, usul bo‘sh', q(`select coalesce("articleId",'-') || ':' || coalesce(method,'-') from public.expenses where note='Sinov kommunal (eski yo‘l)'`) === 'EX-11:-');
    await pg.click('#e-close').catch(() => {}); await pg.waitForTimeout(500);
  } else {
    await pg.waitForSelector('#xe-save', { timeout: 15000 });
    const em = await pg.$$eval('#xe-method option', o => o.map(x => x.value)).catch(() => []);
    ok('xarajat oynasi (F2.1 reyestri, kassa ishga tushmagan): usul — naqd (orderisiz), bank, karta; boshlang‘ichi naqd; «Kassa» yo‘llanmasi yo‘q',
      em.join(',') === 'cash,bank,card' && (await pg.$eval('#xe-method', e => e.value)) === 'cash' && !(await pg.$('#xe-kassa')), em);
    await pg.selectOption('#xe-lines [data-f="articleId"]', 'EX-11'); await pg.fill('#xe-lines [data-f="amount"]', '900 000'); await pg.fill('#xe-note', 'Sinov kommunal (eski yo‘l)'); await pg.click('#xe-save');
    await pg.waitForFunction(() => /Xarajat saqlandi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
    ok('xarajat saqlandi (naqd, orderisiz, hujjat bilan): toifa statiyadan, usul — naqd',
      q(`select e.category || ':' || trim_scale(e.amount) || ':' || e."articleId" || ':' || e.method from public.expenses e join public.fin_exp_docs d on d.id = e."expDocId" where d.note='Sinov kommunal (eski yo‘l)'`) === 'Kommunal:900000:EX-11:cash',
      q(`select e.category, e.amount, e."articleId", e.method from public.expenses e`));
    await pg.click('#xe-close').catch(() => {}); await pg.waitForTimeout(500);
  }
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
  // g11 live-1 (oddiy yo'l — refund_invoice, oyna kaliti p_ref): yuborish qulfi; javob yo'qolgach summa o'zgartirilib qayta yuborilsa — rad
  //   (birinchi yozilgan summa bilan), xuddi shu ma'lumot bilan — «Allaqachon qaytarilgan ✓»; ikkala holda qaytarish faqat bitta.
  //   «Javob yo'qoldi»: birinchi refund_invoice so'rovi serverga yetadi va bajariladi (route.fetch), brauzer esa javob o'rniga tarmoq xatosini oladi.
  {
    const pin = q(`select coalesce("refundPin",'') from public.config where id='security'`);
    const tmark = () => pg.evaluate(() => window.__toasts.length), tsince = n => pg.evaluate(n => window.__toasts.slice(n), n);
    const modalOpen = () => pg.evaluate(() => document.querySelector('#modal-bg').classList.contains('show'));
    // lose — keyingi so'rov javobi «yo'qoladi»; gate — berilsa, so'rov shu va'da bajarilguncha ushlab turiladi (yuborish qulfini ko'rish uchun)
    let nReq = 0, lose = false, held = false, gate = null, openGate = () => {};
    await pg.route('**/rest/v1/rpc/refund_invoice', async route => {
      nReq++;
      if (!lose) return route.continue();
      lose = false; held = true;
      if (gate) await gate;
      try { await route.fetch(); } catch (_) { /* server baribir bajaradi */ }
      held = false; return route.abort('failed');
    });
    const openRf = async id => { await pg.waitForSelector(`#pm-body [data-refund="${id}"]`, { timeout: 30000 }); await pg.click(`#pm-body [data-refund="${id}"]`); await pg.waitForSelector('#rf-do', { timeout: 15000 }); };
    const fillRf = async amt => { await pg.fill('#rf-amt', amt); await pg.fill('#rf-reason', 'Sinov: javob yo‘qolgan qaytarish'); if (await pg.$('#rf-pass')) await pg.fill('#rf-pass', pin); };
    await pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).catch(() => {});
    await pg.waitForSelector('#pm-body [data-refund]', { timeout: 30000 });
    const inv2 = (await pg.$$eval('#pm-body [data-refund]', bs => bs.map(x => x.dataset.refund))).find(x => x !== inv);
    const nRef = () => Number(q(`select count(*) from public.refunds where "targetId"='${inv2}'`));
    const paidOf = () => Number(q(`select coalesce("paidAmount",0)::bigint from public.invoices where id='${inv2}'`));
    const p0 = paidOf(), r0 = nRef();
    // 1) yuborish qulfi: javob kelguncha tugma o'chirilgan («Qaytarilmoqda…»), ikkinchi so'rov ketmaydi
    //    kassa ishga tushmagan / o'rnatilmagan: usul tanlovi (#rf-method) va naqd so'rov bloki yo'q — faqat darhol qaytarish (refund_invoice)
    await openRf(inv2); await fillRf('100 000');
    const noMethod = !(await pg.$('#rf-method')) && !(await pg.$('#rf-cash')) && (await pg.$eval('#rf-do', b => b.textContent)) === 'Qaytarish';
    let tm = await tmark(); gate = new Promise(r => { openGate = r; }); lose = true; nReq = 0;
    await pg.click('#rf-do');
    for (let i = 0; i < 100 && !held; i++) await pg.waitForTimeout(50);
    const busy = await pg.$eval('#rf-do', b => [b.disabled, b.textContent]);
    await pg.$eval('#rf-do', b => b.click()).catch(() => {}); await pg.waitForTimeout(300);
    ok('qaytarish (oddiy yo‘l): usul tanlovi yo‘q; yuborilayotganda tugma qulflangan («Qaytarilmoqda…»), ikkinchi bosish so‘rov yubormaydi', noMethod && held && busy[0] === true && busy[1] === 'Qaytarilmoqda…' && nReq === 1, { noMethod, held, busy, nReq });
    openGate(); gate = null;
    await pg.waitForFunction(() => { const x = document.querySelector('#rf-do'); return x && !x.disabled; }, null, { timeout: 20000 }).catch(() => {});
    const t1 = await tsince(tm);
    ok('javob yo‘qoldi: server qaytarishni yozgan (1 ta), oyna ochiq, tugma qayta faol, xato xabari', nRef() === r0 + 1 && paidOf() === p0 - 100000 && await modalOpen()
      && (await pg.$eval('#rf-do', b => b.textContent)) === 'Qaytarish' && await pg.$eval('#rf-do', b => !b.disabled) && t1.some(t => t.err && /^Xatolik: /.test(t.t)), { n: nRef() - r0, paid: [p0, paidOf()], t1 });
    // 2) summa o'zgartirilib qayta yuborildi — rad: qizil xabar birinchi summa bilan, oyna yopiladi, ikkinchi qaytarish yo'q
    tm = await tmark(); await pg.fill('#rf-amt', '150 000'); await pg.click('#rf-do');
    await pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).catch(() => {});
    const t2 = await tsince(tm);
    ok('o‘sha oynadan boshqa summa bilan — rad: «Bu oynadan avval boshqa ma’lumot bilan qaytarish yozilgan (100 000 so‘m) …», oyna yopildi, qaytarish bitta',
      t2.some(t => t.err && t.t === 'Bu oynadan avval boshqa ma’lumot bilan qaytarish yozilgan (100 000 so‘m) — javob yo‘qolgan bo‘lishi mumkin: ro‘yxatni tekshiring')
      && !(await modalOpen()) && nRef() === r0 + 1 && paidOf() === p0 - 100000, { t2, n: nRef() - r0, paid: paidOf() });
    // 3) yangi oyna: javob yana yo'qoldi — xuddi shu ma'lumot bilan qayta yuborish «Allaqachon qaytarilgan ✓» (ikkinchi marta yozilmaydi)
    if (await modalOpen()) { await pg.click('#m-cancel').catch(() => {}); await pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).catch(() => {}); }
    await openRf(inv2); await fillRf('50 000');
    lose = true; tm = await tmark();
    await pg.click('#rf-do');
    await pg.waitForFunction(() => { const x = document.querySelector('#rf-do'); return x && !x.disabled; }, null, { timeout: 20000 }).catch(() => {});
    const lost3 = nRef() === r0 + 2 && await modalOpen();
    await pg.click('#rf-do');
    await pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).catch(() => {});
    const t3 = await tsince(tm);
    ok('xuddi shu ma’lumot bilan qayta yuborish — «Allaqachon qaytarilgan ✓», oyna yopildi, qaytarish bitta (jami 2 ta, 150 000)',
      lost3 && t3.some(t => !t.err && t.t === 'Allaqachon qaytarilgan ✓') && !(await modalOpen()) && nRef() === r0 + 2 && paidOf() === p0 - 150000, { lost3, t3, n: nRef() - r0, paid: paidOf() });
    await pg.unroute('**/rest/v1/rpc/refund_invoice');
  }
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
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(1); });
