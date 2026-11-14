// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): kassaga bog'langan oqimlar (F1.5, F1.6, F1.13) brauzerda.
//   naqd maosh (KO-2 bilan), karta orqali maosh; ish haqi avansi (so'rov → tasdiq → pul berish → avans yoziladi);
//   qaytarish (Direktor tasdig'i → kassir pulni beradi → balans o'zgaradi); kassa xarajati «Buxgalteriya»ga ko'chadi;
//   naqdsiz xarajat va avans shakllari.  node scenarios/e2e-kassa3.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
// Foydalanuvchi nomidan funksiya chaqirish (bitta tranzaksiya)
const asUser = (uid, sql) => q(`select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}`);
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 700))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()'), month = today.slice(0, 7);
  const tname = q(`select name from public.teachers where \"teacherId\" = 'IQT-001'`);   // maosh oluvchi o'qituvchi (urug'dagi ismi)
  // tayyorlash: kassa ishga tushirilgan, boshlang'ich qoldiq 20 000 000
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","stir":"123456789","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":20000000,"startDay":"${today}"}'::jsonb)`);
  async function login(uid, vp) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage(); const dialogs = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);   // kassa holati serverdan kelguncha
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(250); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, printed, toasts };
  }
  const doc = (where, cols) => q(`select ${cols} from public.cash_docs where ${where}`);
  const bal = () => q(`select trim_scale(app.kassa_day_balance(id)) from public.cash_days where desk='main' and status='open'`);

  // ---------------- 1) Direktor: naqd maosh (vedomost tasdig'i yoqilmagan — faqat Direktor ruxsati bilan), karta orqali maosh
  const dir = await login(ids.R_DIR);
  {
    const s = dir; await s.tab('accounting'); await s.pg.waitForSelector('#ac-paysal', { timeout: 30000 });
    await s.pg.click('#ac-paysal'); await s.pg.waitForSelector('#sp-method', { timeout: 30000 });
    ok('maosh oynasi: to‘lov usuli tanlanadi (naqd / karta / o‘zaro hisob — Direktorga)', (await s.pg.$$eval('#sp-method option', o => o.map(x => x.value).join(','))) === 'cash,card,offset');
    await s.pg.selectOption('#sp-t', 'IQT-001');
    await s.pg.waitForFunction(() => { const b = document.querySelector('#sp-do'); return b && !b.disabled; }, null, { timeout: 30000 });
    ok('naqd tanlanganda sana — kassa kuni (o‘zgartirilmaydi)', await s.pg.$eval('#sp-date', e => e.disabled));
    await s.pg.fill('#sp-paid', '1 500 000'); await s.pg.click('#sp-do');
    await s.pg.waitForFunction(() => /Maosh berildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});
    const mt = await s.pg.$eval('#modal', e => e.textContent).catch(() => '');
    ok('naqd maosh berildi: chiqim orderi raqami ko‘rsatildi, termal chek o‘rniga order', /Kassa chiqim orderi № 1/.test(mt) && !!(await s.pg.$('#sp-ko2')) && !(await s.pg.$('#sp-print')), mt.slice(0, 300) + ' | ' + await s.toasts());
    ok('maosh to‘lovi va KO-2 bitta tranzaksiyada: Dt 6710 Kt 5010, xodim, vedomostsiz — Direktor ruxsati belgisi',
      q(`select s.method || ':' || trim_scale(s.paid) || ':' || c.no || ':' || c.status || ':' || c."partyType" || ':' || (c."sourceSnapshot" ->> 'gateOff') || ':' || l.debit || '>' || l.credit from public.salary_payments s join public.cash_docs c on c.id = s."cashDocId" join public.cash_doc_lines l on l."docId" = c.id where s."teacherId"='IQT-001'`) === 'cash:1500000:1:posted:employee:true:6710>5010',
      q(`select method, paid, "cashDocId" from public.salary_payments where "teacherId"='IQT-001'`));
    await s.pg.click('#sp-ko2'); await s.pg.waitForTimeout(1500);
    const p1 = await s.printed();
    ok('maosh orderi chop etildi: «Иш ҳақи: MM.YYYY», «Берилсин» — xodim', p1.some(t => /ЧИҚИМ КАССА ОРДЕРИ/.test(t) && t.includes('Асоси: Иш ҳақи: ' + month.slice(5, 7) + '.' + month.slice(0, 4)) && t.includes('Берилсин: ' + tname)), p1.map(t => t.slice(0, 260)));
    await s.pg.click('#sp-close').catch(() => {}); await s.pg.waitForTimeout(600);
    // karta orqali
    await s.pg.waitForSelector('#ac-paysal'); await s.pg.click('#ac-paysal'); await s.pg.waitForSelector('#sp-method', { timeout: 30000 });
    await s.pg.selectOption('#sp-t', 'IQX-002'); await s.pg.selectOption('#sp-method', 'card');
    await s.pg.waitForFunction(() => { const b = document.querySelector('#sp-do'); return b && !b.disabled; }, null, { timeout: 30000 });
    await s.pg.fill('#sp-paid', '700 000'); await s.pg.click('#sp-do');
    await s.pg.waitForFunction(() => /Maosh berildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});
    const mt2 = await s.pg.$eval('#modal', e => e.textContent).catch(() => '');
    ok('karta orqali maosh: kassa hujjatisiz yozildi', /karta \/ bank orqali/.test(mt2) && q(`select method || ':' || coalesce("cashDocId",'-') from public.salary_payments where "teacherId"='IQX-002'`) === 'card:-' && bal() === '18500000', mt2.slice(0, 200));
    await s.pg.click('#sp-close').catch(() => {});
  }
  // ---------------- 2) Kassir: maosh oynasi — vedomostsiz oy uchun server rad etadi; avans so'rovi; xarajat so'rovi
  const kas = await login(ids.R_KAS);
  {
    const s = kas; await s.kassaReady();
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op');
    ok('«+ Chiqim so‘rovi»da «Ish haqi avansi» bor', (await s.pg.$$eval('#kf-op option', o => o.map(x => x.value))).includes('out_advance'));
    await s.pg.selectOption('#kf-op', 'out_advance'); await s.pg.waitForSelector('#kf-pe');
    const emp = await s.pg.$eval('#kf-pe', e => [...e.options].find(o => /Sanjar/.test(o.textContent)).value);
    await s.pg.selectOption('#kf-pe', emp); await s.pg.fill('#kf-amt', '400 000'); await s.pg.fill('#kf-basis', 'Xodim arizasi, ' + today);
    await s.pg.click('#kf-save'); await s.modalGone();
    ok('avans so‘rovi yaratildi (2-ro‘yxat tasdig‘ini kutadi); avans hali yozilmagan', doc(`op='out_advance'`, `status || ':' || "needsList2" || ':' || "needsDirector"`) === 'draft:true:false' && q(`select count(*) from public.staff_advances`) === '0');
    // xarajat so'rovi: yangi kontragent, ikki statiya
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'out_expense'); await s.pg.waitForSelector('#kf-pnew');
    await s.pg.click('#kf-pnew'); await s.pg.fill('#kf-cn', 'Sinov Ta’minot MChJ'); await s.pg.click('#kf-cadd');
    await s.pg.waitForFunction(() => { const x = document.querySelector('#kf-pc'); return x && x.value; }, null, { timeout: 10000 });
    await s.pg.selectOption('#kf-lines [data-art="0"]', 'EX-32'); await s.pg.fill('#kf-lines [data-lamt="0"]', '120 000');
    await s.pg.click('#kf-addline'); await s.pg.selectOption('#kf-lines [data-art="1"]', 'EX-20'); await s.pg.fill('#kf-lines [data-lamt="1"]', '80 000');
    await s.pg.fill('#kf-basis', 'Hisob-faktura № 9, ' + today); await s.pg.click('#kf-save'); await s.modalGone();
  }
  const advId = doc(`op='out_advance'`, 'id'), expId = doc(`op='out_expense'`, 'id');
  // ---------------- 3) Direktor: qaytarish so'rovi (naqd — kassadan)
  let refId;
  {
    const s = dir; await s.tab('payments'); await s.pg.waitForSelector('#pm-body [data-refund]', { timeout: 30000 });
    const inv = (await s.pg.$$eval('#pm-body [data-refund]', bs => bs.map(x => x.dataset.refund)))[0];
    const before = q(`select trim_scale("paidAmount") || ':' || status from public.invoices where id='${inv}'`);
    const refBefore = q(`select count(*) from public.refunds`);   // urug'da avvalgi (kassadan oldingi) qaytarish yozuvi bo'lishi mumkin
    await s.pg.click(`#pm-body [data-refund="${inv}"]`); await s.pg.waitForSelector('#rf-method', { timeout: 15000 });
    ok('qaytarish oynasi: usul tanlanadi, naqdda oluvchi F.I.Sh. va ariza sanasi', (await s.pg.$eval('#rf-method', e => e.value)) === 'cash' && !!(await s.pg.$('#rf-payee')) && !!(await s.pg.$('#rf-reqdate')));
    await s.pg.fill('#rf-amt', '300 000'); await s.pg.fill('#rf-reason', 'Ortiqcha to‘langan (sinov)');
    // lokal urug'da Direktor PIN kodi o'rnatilgan (config/security) — qiymati chiqarilmaydi
    if (await s.pg.$('#rf-pass')) await s.pg.fill('#rf-pass', q(`select coalesce("refundPin",'') from public.config where id='security'`));
    const nDlg = s.dialogs.length;
    await s.pg.click('#rf-do'); await s.pg.waitForTimeout(500);
    ok('oluvchi F.I.Sh. kiritilmasa — tasdiqlanmaydi (tasdiq oynasi ham chiqmaydi)', doc(`op='out_refund'`, 'count(*)') === '0' && s.dialogs.length === nDlg && /to‘liq yozing/.test(await s.toasts()), await s.toasts());
    await s.pg.fill('#rf-payee', 'Sinov Ota Onaevich'); await s.pg.click('#rf-do'); await s.modalGone();
    refId = doc(`op='out_refund'`, 'id');
    ok('qaytarish tasdiqlandi: kassa so‘rovi (tasdiqlangan, raqamsiz); balans hali o‘zgarmagan',
      doc(`op='out_refund'`, `status || ':' || coalesce(no::text,'-') || ':' || trim_scale(amount) || ':' || "partyName" || ':' || ("dirApprovedBy" = '${ids.R_DIR}')`) === 'approved:-:300000:Sinov Ota Onaevich:true'
      && q(`select trim_scale("paidAmount") || ':' || status from public.invoices where id='${inv}'`) === before && q(`select count(*) from public.refunds`) === refBefore,
      [doc(`op='out_refund'`, 'status, no, amount, "partyName"'), before]);
    // ---------------- 4) Moliya menejeri: avans va xarajatni tasdiqlaydi
    const m = await login(ids.R_MOL); await m.kassaReady();
    await m.pg.waitForSelector(`[data-appr="${advId}"]`); await m.pg.click(`[data-appr="${advId}"]`); await m.pg.waitForFunction(id => !document.querySelector(`[data-appr="${id}"]`), advId, { timeout: 15000 });
    await m.pg.click(`[data-appr="${expId}"]`); await m.pg.waitForFunction(id => !document.querySelector(`[data-appr="${id}"]`), expId, { timeout: 15000 });
    ok('moliya menejeri: maosh oynasida faqat «karta» usuli (naqd — kassir)', await (async () => { await m.tab('accounting'); await m.pg.waitForSelector('#ac-paysal', { timeout: 30000 }); await m.pg.click('#ac-paysal'); await m.pg.waitForSelector('#sp-method', { timeout: 30000 });
      const v = await m.pg.$$eval('#sp-method option', o => o.map(x => x.value).join(',')); await m.pg.click('#m-cancel').catch(() => {}); return v === 'card'; })());
    await m.ctx.close();
    // ---------------- 5) Kassir: pulni beradi — avans, xarajat, qaytarish
    const k = kas; await k.kassaReady();
    ok('kassir: uchta tasdiqlangan so‘rov to‘lanishi kerak', (await k.pg.$$('[data-pay]')).length === 3, (await k.pg.$$('[data-pay]')).length);
    for (const id of [advId, expId, refId]) { await k.pg.waitForSelector(`[data-pay="${id}"]`); await k.pg.click(`[data-pay="${id}"]`); await k.pg.waitForFunction(x => !document.querySelector(`[data-pay="${x}"]`), id, { timeout: 20000 }); await k.pg.waitForTimeout(400); }
    ok('avans berildi: order o‘tdi va avans qatori o‘zi yozildi (xodim kodi, oy, usul, order havolasi)',
      q(`select a."teacherId" || ':' || trim_scale(a.amount) || ':' || a.month || ':' || a.method || ':' || c.status || ':' || l.debit from public.staff_advances a join public.cash_docs c on c.id = a."cashDocId" join public.cash_doc_lines l on l."docId" = c.id`) === `IQT-003:400000:${month}:cash:posted:4210`,
      q(`select "teacherId", amount, month, method, "cashDocId" from public.staff_advances`));
    ok('xarajat berildi: har qator «Buxgalteriya»ga ko‘chdi (statiya → toifa, kontragent)',
      q(`select string_agg(category || '=' || trim_scale(amount) || ':' || method || ':' || "articleId" || ':' || ("counterpartyId" is not null), ',' order by id) from public.expenses where "cashDocId" = '${expId}'`) === 'Kanselyariya=120000:cash:EX-32:true,Oziq-ovqat=80000:cash:EX-20:true',
      q(`select category, amount, method, "articleId" from public.expenses`));
    ok('qaytarish berildi: balans KO-2 bilan birga o‘zgardi, jurnal kassa hujjatiga bog‘landi',
      q(`select trim_scale(i."paidAmount") || ':' || i.status from public.invoices i where i.id='${inv}'`) === '2500000:partial'
      && q(`select target || ':' || trim_scale(amount) || ':' || method || ':' || ("byUid" = '${ids.R_KAS}') from public.refunds where "cashDocId" = '${refId}'`) === 'invoice:300000:cash:true'
      && q(`select count(*) from public.refunds`) === String(Number(refBefore) + 1),
      [q(`select "paidAmount", status from public.invoices where id='${inv}'`), q(`select target, amount, method, "byUid" from public.refunds`)]);
    ok('kassa qoldig‘i: 20 000 000 − 1 500 000 − 400 000 − 200 000 − 300 000', bal() === '17600000', bal());
    await k.pg.waitForTimeout(800);
    await k.pg.screenshot({ path: `${OUT}/links-kas-${UI}-1440.png`, fullPage: true });
    // qaytarish orderi: bekor tugmasi yo'q; maosh orderi (boshqa foydalanuvchi o'tkazgan) — kassirga bekor tugmasi yo'q
    ok('qaytarish orderida «Bekor» yo‘q; chop etish bor', !(await k.pg.$(`[data-void="${refId}"]`)) && !!(await k.pg.$(`[data-print="${refId}"]`)));
    await k.pg.click(`[data-print="${refId}"]`); await k.pg.waitForTimeout(1500);
    const p2 = await k.printed();
    ok('qaytarish orderi chop etildi: «Қайтариш», oluvchi F.I.Sh. va o‘quvchi kodi, «Ёзма ариза», Direktor ismi', p2.some(t => /Асоси: Қайтариш: Ortiqcha to‘langan \(sinov\); ариза/.test(t) && /Берилсин: Sinov Ota Onaevich \(ўқувчи: /.test(t) && /Иловаси: Ёзма ариза/.test(t)), p2.map(t => t.slice(0, 300)));
  }
  // ---------------- 6) Direktor: «Buxgalteriya» — kassa xarajati belgisi, naqdsiz xarajat va avans shakllari
  {
    const s = dir; await s.tab('accounting'); await s.pg.waitForSelector('#ac-add', { timeout: 30000 }); await s.pg.waitForTimeout(1500);
    const at = await s.pg.$eval('#ac-body', e => e.textContent);
    ok('«Buxgalteriya»: kassadan ko‘chgan xarajat va avans «Kassa» belgisi bilan (tahrir / o‘chirish tugmasiz)', /Kanselyariya/.test(at) && (await s.pg.$$eval('#ac-body .chip', c => c.filter(x => x.textContent.trim() === 'Kassa').length)) >= 3
      && !(await s.pg.$(`[data-edel="kx_${expId}_1"]`)), at.slice(0, 200));
    await s.pg.click('#ac-add'); await s.pg.waitForSelector('#e-method', { timeout: 10000 });
    ok('xarajat shakli: naqdsiz usullar (hisobdor xarajati — «Avans hisoboti»da) va «Kassa»ga yo‘llanma', (await s.pg.$$eval('#e-method option', o => o.map(x => x.value).join(','))) === 'bank,card' && /Naqd xarajat bu yerda yozilmaydi/.test(await s.pg.$eval('#modal', e => e.textContent)));
    await s.pg.selectOption('#e-cat', 'Ijara'); await s.pg.fill('#e-amt', '5 000 000'); await s.pg.fill('#e-note', 'Sinov ijara, bank orqali');
    await s.pg.waitForFunction(() => document.querySelectorAll('#e-cp option').length > 1, null, { timeout: 10000 }).catch(() => {});
    await s.pg.click('#e-save');
    await s.pg.waitForFunction(() => /Xarajat saqlandi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
    ok('naqdsiz xarajat saqlandi: usul va statiya (toifadan) bilan', q(`select method || ':' || "articleId" || ':' || trim_scale(amount) from public.expenses where note='Sinov ijara, bank orqali'`) === 'bank:EX-10:5000000', q(`select method, "articleId", amount from public.expenses where note='Sinov ijara, bank orqali'`));
    await s.pg.click('#e-close').catch(() => {}); await s.pg.waitForTimeout(500);
    await s.pg.click('#ac-adv'); await s.pg.waitForSelector('#av-save', { timeout: 30000 });
    ok('avans shakli: faqat karta / bank orqali, naqd — «Kassa»ga yo‘llanma', /Naqd avans — «Kassa» bo‘limida/.test(await s.pg.$eval('#modal', e => e.textContent)) && /karta \/ bank/.test(await s.pg.$eval('#av-save', e => e.textContent)));
    await s.pg.selectOption('#av-t', 'IQX-001'); await s.pg.fill('#av-amt', '250 000'); await s.pg.click('#av-save');
    await s.pg.waitForFunction(() => /avansi yozildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
    ok('karta orqali avans yozildi (kassa hujjatisiz)', q(`select method || ':' || coalesce("cashDocId",'-') || ':' || trim_scale(amount) from public.staff_advances where "teacherId"='IQX-001'`) === 'card:-:250000', q(`select "teacherId", method, amount from public.staff_advances`));
    await s.pg.click('#av-close').catch(() => {});
    // maosh orderini shu kunda bekor qilish — maosh to'lovi ham olib tashlanadi
    await s.kassaReady();
    const salId = doc(`op='out_salary'`, 'id');
    await s.pg.waitForSelector(`[data-void="${salId}"]`); await s.pg.click(`[data-void="${salId}"]`);
    await s.pg.waitForSelector('#ks-reason'); await s.pg.fill('#ks-reason', 'Xato summa berilgan (sinov)'); await s.pg.click('#ks-ok'); await s.modalGone();
    ok('maosh orderi bekor qilindi: maosh to‘lovi ham olib tashlandi, qoldiq tiklandi', doc(`id='${salId}'`, 'status') === 'void' && q(`select count(*) from public.salary_payments where "teacherId"='IQT-001'`) === '0' && bal() === '19100000', [doc(`id='${salId}'`, 'status'), bal()]);
    await s.pg.screenshot({ path: `${OUT}/links-dir-${UI}-1440.png`, fullPage: true });
  }
  await dir.ctx.close(); await kas.ctx.close();
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
})().catch(e => { console.error('XATO', e); process.exit(1); });
