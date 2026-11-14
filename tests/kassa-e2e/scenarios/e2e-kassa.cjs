// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): «Kassa» bo'limi — to'liq kun sikli brauzerda.
//   Direktor: boshlang'ich qoldiq, sozlamalar (ishga tushirish) → kassir: kirim, chiqim so'rovi → moliya menejeri: tasdiq →
//   kassir: pulni berish, naqd o'quv to'lovi (fiskal № bilan), bekor qilish, kunni yopish → moliya menejeri: tekshirish, qayta chop etish.
//   Chop etish: printHTML() iframe yaratadi — uning matni tekshiriladi.  node scenarios/e2e-kassa.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 600))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()');
  async function login(uid, vp) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage(); const dialogs = [];
    pg.on('pageerror', e => allErrs.push(String(e.message).slice(0, 300)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const toastTxt = async () => pg.evaluate(() => [...document.querySelectorAll('.toast, #toast, [class*=toast]')].map(e => e.textContent).join(' | '));
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    return { ctx, pg, dialogs, tab, toastTxt, printed, kassaReady, modalGone };
  }

  // ------------------------------------------------------------ 1) Direktor: bo'lim, boshlang'ich qoldiq, sozlamalar
  {
    const s = await login(ids.R_DIR);
    await s.kassaReady();
    ok('direktor: «Kassa» bo‘limi ochildi (hali ishga tushirilmagan)', /Kassa hali ishga tushirilmagan/.test(await s.pg.$eval('#ks-body', e => e.textContent)));
    await s.pg.click('#ks-opening'); await s.pg.waitForSelector('#ko-amt');
    await s.pg.fill('#ko-amt', '1 000 000'); await s.pg.fill('#ko-day', today);
    await s.pg.fill('[data-ct="0"]', 'Direktor o‘rinbosari'); await s.pg.fill('[data-cn="0"]', 'Sinov A.A.');
    await s.pg.fill('[data-ct="1"]', 'Buxgalter'); await s.pg.fill('[data-cn="1"]', 'Sinov B.B.');
    await s.pg.fill('#ko-note', 'Sanash dalolatnomasi № 1 (sinov)');
    await s.pg.click('#ko-save'); await s.modalGone();
    ok('boshlang‘ich qoldiq saqlandi', q(`select trim_scale("openingAmount") || ':' || "startDay" from public.cash_desks where id='main'`) === `1000000:${today}`, q(`select "openingAmount", "startDay" from public.cash_desks where id='main'`));
    await s.pg.waitForSelector('#ks-set'); await s.pg.click('#ks-set'); await s.pg.waitForSelector('#kx-name');
    await s.pg.fill('#kx-name', '«SINOV MAKTAB» МЧЖ'); await s.pg.fill('#kx-stir', '123456789'); await s.pg.fill('#kx-place', 'Тошкент ш.');
    await s.pg.fill('#kx-t1', '500 000'); await s.pg.fill('#kx-l1', '200 000'); await s.pg.fill('#kx-orgmax', '1 000 000 000'); await s.pg.fill('#kx-live', today);
    await s.pg.click('#kx-save'); await s.modalGone();
    ok('sozlamalar saqlandi (T1, L1, yuridik shaxsga naqd chegarasi, ishga tushirish kuni)', q(`select trim_scale(t1) || ':' || trim_scale(l1) || ':' || "kassaGoLive" || ':' || stir || ':' || (extra ->> 'orgCashMax') from public.fin_org where id='main'`) === `500000:200000:${today}:123456789:1000000000`, q(`select t1, l1, "kassaGoLive", stir, extra from public.fin_org where id='main'`));
    ok('ishga tushirish tasdig‘i so‘raldi', s.dialogs.some(m => /ishga tushsinmi/.test(m)), s.dialogs);
    await s.pg.waitForFunction(() => /Kassadagi qoldiq/.test(document.querySelector('#ks-body').textContent), null, { timeout: 10000 });
    await s.pg.screenshot({ path: `${OUT}/dir-${UI}-1440.png` });
    await s.ctx.close();
  }

  // ------------------------------------------------------------ 2) Kassir: kirim (darhol o'tadi) va chiqim so'rovi
  const kas = await login(ids.R_KAS);
  {
    const s = kas;
    await s.kassaReady();
    ok('kassir: «Kassa» bo‘limi va amallar', (await s.pg.$('#ks-in')) && (await s.pg.$('#ks-out')) && !(await s.pg.$('#ks-set')));
    await s.pg.click('#ks-in'); await s.pg.waitForSelector('#kf-op');
    await s.pg.selectOption('#kf-op', 'in_other'); await s.pg.waitForSelector('#kf-ptype');
    await s.pg.selectOption('#kf-ptype', 'other'); await s.pg.waitForSelector('#kf-po');
    await s.pg.fill('#kf-po', 'Sinov To‘lovchi Tashkiloti');
    await s.pg.selectOption('[data-art="0"]', 'IN-06'); await s.pg.fill('#kf-amt', '250 000');
    await s.pg.fill('#kf-basis', 'Sinov asos № 1, ' + today); await s.pg.fill('#kf-note', 'Sinov izohi');
    await s.pg.click('#kf-save'); await s.modalGone();
    const d1 = q(`select form || ':' || no || ':' || status || ':' || trim_scale(amount) || ':' || "businessDay" from public.cash_docs where op='in_other'`);
    ok('kirim orderi o‘tkazildi: K-1, kassa kuni — bugun', d1 === `KO1:1:posted:250000:${today}`, d1);
    await s.pg.waitForTimeout(1200);
    const p1 = await s.printed();
    ok('kirim orderi chop etildi: KO-1 + patta, so‘z bilan, tashkilot rekvizitlari', p1.some(t => /КИРИМ КАССА ОРДЕРИ/.test(t) && /ПАТТА/.test(t) && /Икки юз эллик минг сўм 00 тийин/.test(t) && /SINOV MAKTAB/.test(t) && /Фискал чек эмас/.test(t) && !/НУСХА/.test(t)), p1.map(t => t.slice(0, 200)));
    ok('chop etish jurnali: asl nusxa', q(`select string_agg(mode, ',') from public.cash_prints`) === 'original', q(`select string_agg(mode, ',') from public.cash_prints`));
    // chiqim so'rovi: yangi kontragent, bitta statiya
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op');
    await s.pg.selectOption('#kf-op', 'out_expense'); await s.pg.waitForSelector('#kf-pnew');
    await s.pg.click('#kf-pnew'); await s.pg.fill('#kf-cn', 'Sinov Ta’minot MChJ'); await s.pg.click('#kf-cadd');
    await s.pg.waitForFunction(() => { const x = document.querySelector('#kf-pc'); return x && x.value; }, null, { timeout: 10000 });
    const art = await s.pg.$eval('#kf-lines [data-art="0"]', e => [...e.options].map(o => o.value).filter(Boolean)[0]);
    await s.pg.selectOption('#kf-lines [data-art="0"]', art); await s.pg.fill('#kf-lines [data-lamt="0"]', '300 000');
    await s.pg.fill('#kf-basis', 'Hisob-faktura № 7, ' + today);
    await s.pg.click('#kf-save'); await s.modalGone();
    const d2 = q(`select form || ':' || coalesce(no::text,'-') || ':' || status || ':' || "needsList2" || ':' || "needsDirector" from public.cash_docs where op='out_expense'`);
    ok('chiqim so‘rovi: raqamsiz, 2-ro‘yxat tasdig‘ini kutadi (T1 dan kichik — Direktor shart emas)', d2 === 'KO2:-:draft:true:false', d2);
    await s.pg.waitForFunction(() => /Tasdiq kutilmoqda/.test(document.querySelector('#ks-body').textContent), null, { timeout: 10000 });
    ok('kassir o‘z so‘rovini tasdiqlay olmaydi (tugma yo‘q), pul berish tugmasi ham yo‘q', !(await s.pg.$('[data-appr]')) && !(await s.pg.$('[data-pay]')));
  }

  // ------------------------------------------------------------ 3) Moliya menejeri: «Tasdiqlash» navbati
  {
    const s = await login(ids.R_MOL);
    await s.tab('approvals');
    await s.pg.waitForSelector('[data-kappr]', { timeout: 20000 });
    ok('moliya menejeri: «Tasdiqlash»da kassa so‘rovi ko‘rinadi', /Sinov Ta’minot MChJ/.test(await s.pg.$eval('#view', e => e.textContent)));
    await s.pg.click('[data-kappr]');
    await s.pg.waitForFunction(() => !document.querySelector('[data-kappr]'), null, { timeout: 15000 });
    ok('so‘rov tasdiqlandi', q(`select status || ':' || ("approvedBy" = '${ids.R_MOL}') from public.cash_docs where op='out_expense'`) === 'approved:true', q(`select status, "approvedBy" from public.cash_docs where op='out_expense'`));
    await s.kassaReady();
    ok('moliya menejeri: «Kassa»ni ko‘radi, kirim tugmasi yo‘q', !(await s.pg.$('#ks-in')) && !!(await s.pg.$('#ks-out')));
    await s.ctx.close();
  }

  // ------------------------------------------------------------ 4) Kassir: pulni berish; naqd o'quv to'lovi; bekor qilish; kunni yopish
  {
    const s = kas;
    await s.kassaReady();
    await s.pg.waitForSelector('[data-pay]', { timeout: 15000 });
    await s.pg.click('[data-pay]');
    await s.pg.waitForFunction(() => !document.querySelector('[data-pay]'), null, { timeout: 15000 });
    const d2 = q(`select no || ':' || status || ':' || ("postedBy" = '${ids.R_KAS}') from public.cash_docs where op='out_expense'`);
    ok('chiqim orderi o‘tkazildi: Ch-1', d2 === '1:posted:true', d2);
    await s.pg.waitForTimeout(1200);
    const p2 = await s.printed();
    ok('chiqim orderi chop etildi: KO-2, «Берилсин», tasdiqlovchi ismi', p2.some(t => /ЧИҚИМ КАССА ОРДЕРИ/.test(t) && /Берилсин: Sinov Ta’minot MChJ/.test(t) && /Уч юз минг сўм 00 тийин/.test(t) && /Олдим/.test(t)), p2.map(t => t.slice(0, 160)));
    ok('qoldiq: 1 000 000 + 250 000 − 300 000', q(`select trim_scale(app.kassa_day_balance(id)) from public.cash_days where desk='main' and status='open'`) === '950000');

    // naqd o'quv to'lovi — «To'lov» shakli: fiskal № majburiy, termal chek o'rniga KO-1 + patta
    await s.tab('payments'); await s.pg.waitForSelector('#pm-body [data-pay]', { timeout: 30000 });
    const inv = (await s.pg.$$eval('#pm-body [data-pay]', bs => bs.map(x => x.dataset.pay)))[0];
    const sid = q(`select "studentId" from public.invoices where id='${inv}'`);
    const paidBefore = q(`select coalesce(sum("paidAmount"),0)::bigint || ':' || string_agg(coalesce(status,''), ',' order by id) from public.invoices where "studentId"='${sid}'`);
    await s.pg.click(`#pm-body [data-pay="${inv}"]`); await s.pg.waitForSelector('#rp-save');
    await s.pg.selectOption('#rp-m', 'cash'); await s.pg.waitForSelector('#rp-fiscal');
    ok('to‘lov shakli: naqdda fiskal chek № maydoni, sana — kassa kuni (o‘zgartirilmaydi)', await s.pg.$eval('#rp-date', e => e.disabled));
    await s.pg.fill('#rp-amt', '100 000');
    await s.pg.click('#rp-save'); await s.pg.waitForTimeout(600);
    ok('fiskal raqamsiz saqlanmaydi', (await s.pg.$('#rp-fiscal')) && q(`select count(*) from public.payments where "studentId"='${sid}' and raw->>'manual'='true'`) === '0');
    await s.pg.fill('#rp-fiscal', 'SINOV-0001'); await s.pg.click('#rp-save');
    await s.pg.waitForFunction(() => /To‘lov qabul qilindi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 25000 }).catch(() => {});
    const body = await s.pg.$eval('#modal', e => e.textContent).catch(() => '');
    ok('to‘lov qabul qilindi: kirim orderi raqami ko‘rsatildi, termal chek tugmasi yo‘q', /Kassa kirim orderi № 2/.test(body) && !!(await s.pg.$('#rp-ko1')) && !(await s.pg.$('#rp-print')), body.slice(0, 300));
    const pay = q(`select p.status || ':' || coalesce(p."fiscalNo",'') || ':' || c.no || ':' || c.status || ':' || c.op from public.payments p join public.cash_docs c on c.id = p."cashDocId" where p."studentId"='${sid}' and p.raw->>'manual'='true'`);
    ok('to‘lov + KO-1 bitta tranzaksiyada: applied, fiskal №, K-2', pay === 'applied:SINOV-0001:2:posted:in_tuition', pay);
    await s.pg.click('#rp-ko1'); await s.pg.waitForTimeout(1500);
    const p3 = await s.printed();
    ok('o‘quv to‘lovi orderi chop etildi: «Ўқув тўлови», o‘quvchi kodi, fiskal chek №', p3.some(t => /КИРИМ КАССА ОРДЕРИ/.test(t) && /Ўқув тўлови/.test(t) && t.includes('(ўқувчи: ' + sid + ')') && /Фискал чек №: SINOV-0001/.test(t)), p3.map(t => t.slice(0, 200)));
    await s.pg.click('#rp-close').catch(() => {});
    // shu kunda bekor qilish (sabab bilan)
    await s.kassaReady();
    const tuId = q(`select id from public.cash_docs where op='in_tuition'`);
    await s.pg.waitForSelector(`[data-void="${tuId}"]`, { timeout: 15000 }); await s.pg.click(`[data-void="${tuId}"]`);
    await s.pg.waitForSelector('#ks-reason'); await s.pg.fill('#ks-reason', 'Xato kiritilgan (sinov)'); await s.pg.click('#ks-ok'); await s.modalGone();
    const vd = q(`select c.status || ':' || c.no || ':' || p.status from public.cash_docs c join public.payments p on p."cashDocId" = c.id where c.id='${tuId}'`);
    ok('o‘quv to‘lovi bekor qilindi: hujjat raqami saqlandi, to‘lov bekor', vd === 'void:2:canceled', vd);
    ok('fakturalar to‘lovdan oldingi holatga qaytdi', q(`select coalesce(sum("paidAmount"),0)::bigint || ':' || string_agg(coalesce(status,''), ',' order by id) from public.invoices where "studentId"='${sid}'`) === paidBefore, [paidBefore, q(`select id, "paidAmount", status from public.invoices where "studentId"='${sid}'`)]);
    await s.pg.screenshot({ path: `${OUT}/kas-${UI}-1440.png`, fullPage: true });
    // kunni yopish: sanalgan = hisobdagi
    await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted');
    await s.pg.fill('#kc-counted', '950 000');
    ok('yopish oynasi: farq yo‘q', /Farq yo‘q/.test(await s.pg.$eval('#kc-diff', e => e.textContent)));
    await s.pg.click('#kc-save'); await s.modalGone();
    const dd = q(`select status || ':' || trim_scale(closing) || ':' || trim_scale(diff) || ':' || "docCount" || ':' || "sheetFrom" || '-' || "sheetTo" || ':' || "sheetRows" from public.cash_days where desk='main'`);
    ok('kun yopildi: kun oxiri 950 000, farq 0, 3 hujjat, varaq 1', dd === 'closed:950000:0:3:1-1:30', dd);
    await s.pg.waitForTimeout(1500);
    const p4 = await s.printed();
    ok('kassa kitobi chop etildi: 2 nusxa, varaq 1, bekor qilingan hujjat belgilangan, sonlar so‘z bilan', p4.some(t => /КАССА ДАФТАРИ ВАРАҒИ/.test(t) && /КАССИР ҲИСОБОТИ/.test(t) && /Варақ 1/.test(t) && /бекор қилинган/.test(t) && /2 \(икки\) та кирим ва 1 \(бир\) та чиқим/.test(t) && /Тўққиз юз эллик минг сўм/.test(t)), p4.map(t => t.slice(0, 200)));
    ok('yopilgan kunda «+ Kirim» → server rad etadi', await (async () => {
      await s.pg.click('#ks-in'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'in_other'); await s.pg.waitForSelector('#kf-ptype');
      await s.pg.selectOption('#kf-ptype', 'other'); await s.pg.fill('#kf-po', 'Sinov Kech'); await s.pg.selectOption('[data-art="0"]', 'IN-06'); await s.pg.fill('#kf-amt', '1 000');
      await s.pg.fill('#kf-basis', 'Sinov asos 2'); await s.pg.fill('#kf-note', 'izoh'); await s.pg.click('#kf-save'); await s.pg.waitForTimeout(1200);
      const n = q(`select count(*) from public.cash_docs where "partyName"='Sinov Kech' and status='posted'`); await s.pg.click('#m-cancel').catch(() => {}); return n === '0'; })());
    await s.pg.setViewportSize({ width: 390, height: 844 }); await s.kassaReady(); await s.pg.waitForTimeout(400);
    await s.pg.screenshot({ path: `${OUT}/kas-${UI}-390.png`, fullPage: true });
    const wide = await s.pg.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    ok('telefon (390 px): sahifa gorizontal siljimaydi', wide <= 1, wide);
    await s.ctx.close();
  }

  // ------------------------------------------------------------ 5) Moliya menejeri: tekshirish, kun varag'i, qayta chop etish («НУСХА»)
  {
    const s = await login(ids.R_MOL);
    await s.kassaReady();
    await s.pg.waitForSelector(`[data-verify="${today}"]`, { timeout: 15000 }); await s.pg.click(`[data-verify="${today}"]`);
    await s.pg.waitForSelector('#kv-papers'); await s.pg.check('#kv-papers'); await s.pg.click('#kv-save'); await s.modalGone();
    ok('kun tekshirildi (tekshiruvchi ≠ yopuvchi)', q(`select status || ':' || ("verifiedBy" = '${ids.R_MOL}') from public.cash_days where desk='main'`) === 'verified:true', q(`select status, "verifiedBy" from public.cash_days where desk='main'`));
    await s.pg.waitForSelector(`[data-view="${today}"]`); await s.pg.click(`[data-view="${today}"]`);
    await s.pg.waitForSelector('#kdv-book', { timeout: 15000 });
    const dv = await s.pg.$eval('#modal', e => e.textContent);
    ok('kun varag‘i oynasi: 3 hujjat, sanash va jurnal', /Hujjatlar \(3 ta\)/.test(dv) && /Kun yopish sanashi/.test(dv) && /Kun jurnali/.test(dv), dv.slice(0, 300));
    await s.pg.click('#kdv-book'); await s.pg.waitForSelector('#kp-copy', { timeout: 15000 });
    ok('qayta chop etish: avval chop etilgani haqida ogohlantirish', /avval chop etishga yuborilgan: 1 marta/.test(await s.pg.$eval('#modal', e => e.textContent)));
    await s.pg.click('#kp-copy'); await s.pg.waitForTimeout(1500);
    const p5 = await s.printed();
    ok('qayta chop etilgan varaq «НУСХА» belgisi bilan, tekshiruvchi ismi bilan', p5.some(t => /НУСХА/.test(t) && /КАССИР ҲИСОБОТИ/.test(t) && /Бухгалтер/.test(t)), p5.map(t => t.slice(0, 160)));
    ok('chop etish jurnali: varaq — original, keyin copy', q(`select string_agg(mode, ',' order by at) from public.cash_prints where kind='book'`) === 'original,copy', q(`select string_agg(mode, ',' order by at) from public.cash_prints where kind='book'`));
    await s.pg.waitForSelector('#kdv-book', { timeout: 10000 });   // nusxa chop etilgach kun varag'i oynasi qayta ochiladi
    // sanash dalolatnomasi
    await s.pg.click('[data-cprint]'); await s.pg.waitForTimeout(1200);
    const p6 = await s.printed();
    ok('sanash dalolatnomasi chop etildi', p6.some(t => /КАССАДАГИ НАҚД ПУЛНИ САНАШ ДАЛОЛАТНОМАСИ/.test(t) && /Фарқ аниқланмади/.test(t)), p6.map(t => t.slice(0, 120)));
    await s.ctx.close();
  }

  // ------------------------------------------------------------ 6) Huquq: o'qituvchi «Kassa»ni ko'rmaydi
  {
    const s = await login(ids.R_TCH);
    ok('o‘qituvchi: menyuda «Kassa» yo‘q', !(await s.pg.$('#tabs button[data-tab="kassa"]')));
    await s.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
})().catch(e => { console.error('XATO', e); process.exit(1); });
