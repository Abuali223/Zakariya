// LOCAL ONLY (lokal stend, sintetik urug' — tests/kassa-e2e/README.md): manual payment as kassir via record_manual_payment — online and offline (outbox).
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E;
const { session, ids } = E;
const q = E.q;
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c, x }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x))); };
(async () => {
  const b = await E.launch(); const uid = ids.R_KAS;
  const email = q(`select email from public.users where id='${uid}'`);
  const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 1440, height: 900 } });
  await ctx.addInitScript(([k, v]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} }, ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'R_KAS' }))]);
  const pg = await ctx.newPage(); const errs = [];
  pg.on('pageerror', e => errs.push(String(e.message).slice(0, 200)));
  const dialogs = []; pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
  await pg.goto(E.BASE + '/admin.html');
  await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
  if (await pg.locator('#tabs button[data-tab="payments"]').isVisible().catch(() => false)) await pg.click('#tabs button[data-tab="payments"]');
  await pg.waitForSelector('#pm-body [data-pay]', { timeout: 30000 });
  const pays = await pg.$$eval('#pm-body [data-pay]', bs => bs.map(x => x.dataset.pay));
  ok('to‘lov tugmalari bor', pays.length >= 2, pays.length);
  async function payOne(invId, amountTxt) {
    const before = q(`select "studentId" || '|' || coalesce("paidAmount",0)::bigint || '|' || amount::bigint from public.invoices where id='${invId}'`).split('|');
    await pg.click(`#pm-body [data-pay="${invId}"]`);
    await pg.waitForSelector('#rp-save', { timeout: 10000 });
    await pg.selectOption('#rp-m', 'cash');
    if (amountTxt) await pg.fill('#rp-amt', amountTxt);
    await pg.click('#rp-save');
    return before;
  }
  // 1) onlayn
  const inv1 = pays[0]; const [sid1, paid1, amt1] = await payOne(inv1);
  await pg.waitForFunction(() => /To‘lov qabul qilindi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 20000 }).catch(() => {});
  const h1 = await pg.$eval('#modal .modal-h h3', e => e.textContent).catch(() => '');
  ok('onlayn: «To‘lov qabul qilindi»', /To‘lov qabul qilindi/.test(h1), h1);
  const row1 = q(`select id || '|' || status || '|' || (abs(extract(epoch from now() - "createdAt")) < 120)::text || '|' || ("statusAt" is not null)::text || '|' || (raw->>'manual') || '|' || coalesce(raw->>'byUid','') from public.payments where "studentId"='${sid1}' and raw->>'manual'='true' order by "createdAt" desc limit 1`).split('|');
  ok('onlayn: payments qatori applied, server vaqti, statusAt, byUid', row1[1] === 'applied' && row1[2] === 'true' && row1[3] === 'true' && row1[4] === 'true' && row1[5] === uid, row1);
  const after1 = Number(q(`select coalesce(sum("paidAmount"),0)::bigint from public.invoices where "studentId"='${sid1}'`));
  ok('onlayn: faktura to‘landi', after1 >= Number(paid1) + Number(amt1) - Number(paid1) - 1, { after1, paid1, amt1 });
  ok('onlayn: navbat bo‘sh', (await pg.evaluate(() => JSON.parse(localStorage.getItem('iqror_pay_outbox_v1') || '[]').length)) === 0);
  await pg.click('#rp-close').catch(() => {});
  await pg.waitForTimeout(800);
  // 1b) takror ogohlantirishi: shu o'quvchiga shu summa yana (server vaqti + capturedAt)
  {
    await pg.waitForSelector('#pm-body [data-pay]', { timeout: 20000 });
    const pp = await pg.$$eval('#pm-body [data-pay]', bs => bs.map(x => x.dataset.pay));
    const invA = pp.find(x => x !== inv1); const sidA = q(`select "studentId" from public.invoices where id='${invA}'`);
    await payOne(invA, '100 000');
    await pg.waitForFunction(() => /To‘lov qabul qilindi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 20000 }).catch(() => {});
    await pg.click('#rp-close').catch(() => {}); await pg.waitForTimeout(800);
    const before = dialogs.length;
    // o'sha o'quvchining hali to'lanmagan fakturasi (yoki o'sha qator) — yana 100 000
    await pg.waitForSelector('#pm-body [data-pay]', { timeout: 20000 });
    const pp2 = await pg.$$eval('#pm-body [data-pay]', bs => bs.map(x => x.dataset.pay));
    const invB = pp2.find(x => q(`select "studentId" from public.invoices where id='${x}'`) === sidA);
    if (invB) { await payOne(invB, '100 000');
      await pg.waitForFunction(() => /To‘lov qabul qilindi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 20000 }).catch(() => {});
      ok('takror ogohlantirishi chiqdi (server vaqti bilan ham)', dialogs.slice(before).some(m => /TAKROR/.test(m)), dialogs.slice(before));
      await pg.click('#rp-close').catch(() => {}); await pg.waitForTimeout(800);
    } else ok('takror sinovi uchun qator topildi', false, 'no row');
  }
  // 2) oflayn → navbat → onlayn bo'lganda yuboriladi
  await pg.waitForSelector('#pm-body [data-pay]', { timeout: 20000 });
  const pays2 = await pg.$$eval('#pm-body [data-pay]', bs => bs.map(x => x.dataset.pay));
  const inv2 = pays2.find(x => x !== inv1); const sid2 = q(`select "studentId" from public.invoices where id='${inv2}'`);
  await ctx.setOffline(true);
  await payOne(inv2);
  await pg.waitForFunction(() => /navbatga qo‘yildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 20000 }).catch(() => {});
  const h2 = await pg.$eval('#modal .modal-h h3', e => e.textContent).catch(() => '');
  ok('oflayn: «navbatga qo‘yildi»', /navbatga qo‘yildi/.test(h2), h2);
  const ob = await pg.evaluate(() => JSON.parse(localStorage.getItem('iqror_pay_outbox_v1') || '[]'));
  ok('oflayn: navbatda 1 ta yozuv', ob.length === 1, ob.length);
  const pid = ob[0] && ob[0].payId;
  ok('oflayn: bazada hali yo‘q', q(`select count(*) from public.payments where id='${pid}'`) === '0');
  await ctx.setOffline(false);
  await pg.waitForFunction(() => JSON.parse(localStorage.getItem('iqror_pay_outbox_v1') || '[]').length === 0, null, { timeout: 45000 }).catch(() => {});
  ok('onlayn bo‘lgach navbat bo‘shadi', (await pg.evaluate(() => JSON.parse(localStorage.getItem('iqror_pay_outbox_v1') || '[]').length)) === 0);
  const row2 = q(`select status || '|' || (raw->>'capturedAt' is not null)::text from public.payments where id='${pid}'`);
  ok('oflayn to‘lov: applied, capturedAt saqlangan', row2 === 'applied|true', row2);
  ok('sahifa xatosi yo‘q', errs.length === 0, errs);
  console.log(`JAMI: ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
})().catch(e => { console.error(e); process.exit(1); });
