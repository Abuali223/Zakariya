// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.1 — «Buxgalteriya» xarajatlari reyestri brauzerda.
//   Moliya menejeri: bank hujjati (yangi kontragent, hujjat №, ilova, ikki statiya qatori, jami), statiyalar usulga qarab, takror to'lov
//   ogohlantirishi (tasdiqlansa yoziladi), hujjatni ko'rish, bekor qilish (sabab bilan), tuzatish (eski hujjat bekor — yangisi yoziladi),
//   eski (hujjatsiz) yozuvni tuzatish va bekor qilish, oylik maosh hisobi qatori (avvalgidek o'chiriladi); telefon ekrani (390 px);
//   buxgalter — faqat ko'radi (hujjat oynasi bor, yozish tugmalari yo'q).  Yangi stend bilan (bash stand.sh reset dev):
//   node scenarios/e2e-kassa19.cjs
const E = require('../lib/common.cjs'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const asUser = (uid, sql) => q(`select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}`);
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()'), month = today.slice(0, 7);
  const ACC = 'u_acc_e19';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter19@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status, "extraRoles" = '[]'`);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)`);
  // Sintetik: bank kontragenti; ikki eski (hujjatsiz) xarajat — bank orqali ijara va usulsiz kanselyariya; oylik maosh hisobi qatori
  q(`set session_replication_role = replica;
     insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_b19', 'bank', 'Sinov Bank ATB', '', true) on conflict (id) do nothing;
     insert into public.expenses (id, date, month, category, amount, note, method, "articleId") values
       ('e19-old1', '${today}', '${month}', 'Ijara', 5000000, 'Sinov ijara (eski)', 'bank', 'EX-10'),
       ('e19-old2', '${today}', '${month}', 'Kanselyariya', 120000, 'Sinov qog‘oz (eski)', null, 'EX-32'),
       ('payroll__${month}', '${month}-01', '${month}', 'Maosh', 9000000, 'Avtomatik: sinov', null, null) on conflict (id) do nothing;
     update public.expenses set kind = 'accrual' where id = 'payroll__${month}';
     set session_replication_role = origin;`);   // F2.4: replica rejimida turni o'rnatuvchi trigger ham ishlamaydi
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
    await pg.waitForTimeout(700);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
    const modalTxt = async () => pg.$eval('#modal', e => e.innerText).catch(() => '');
    const modalH = async () => pg.$eval('#modal .modal-h h3', e => e.textContent).catch(() => '');
    const closeAny = async () => { await pg.keyboard.press('Escape').catch(() => {}); await pg.waitForTimeout(200); };
    const acReady = async sel => { await tab('accounting'); await pg.waitForSelector(sel || '#ac-paysal', { state: 'attached', timeout: 30000 });
      await pg.waitForFunction(() => { const x = document.querySelector('#ac-body'); return x && !x.querySelector('.loading'); }, null, { timeout: 30000 }); await pg.waitForTimeout(300); };
    const openForm = async () => { for (let i = 0; i < 8 && !(await pg.$('#xe-save')); i++) { await pg.$eval('#ac-add', x => x.click()).catch(() => {}); await pg.waitForTimeout(500); }
      await pg.waitForSelector('#xe-save', { timeout: 15000 }); await pg.waitForTimeout(200); };
    const saved = async () => pg.waitForFunction(() => /Xarajat saqlandi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 15000 }).then(() => true).catch(() => false);
    return { ctx, pg, dialogs, tab, toasts, modalTxt, modalH, closeAny, acReady, openForm, saved };
  }
  const docs = (where, cols) => q(`select ${cols} from public.fin_exp_docs where ${where}`);

  // ---------------- 1) Moliya menejeri: ro'yxat amallari va yangi bank hujjati
  const m = await login(ids.R_MOL);
  await m.acReady();
  {
    const has = async s => !!(await m.pg.$(s));
    ok('ro‘yxat: eski yozuvda «Tuzatish» / «Bekor» (eski «Tahrir» / «O‘chir» yo‘q); maosh hisobi qatori — «Maosh hisobi» belgisi va «O‘chir»',
      await has('[data-xfixr="e19-old1"]') && await has('[data-xvoidr="e19-old1"]') && await has('[data-xvoidr="e19-old2"]') && !(await has('[data-eedit]'))
      && await has(`[data-edel="payroll__${month}"]`) && !(await has(`[data-xfixr="payroll__${month}"]`))
      && (await m.pg.$$eval('#ac-body .chip', c => c.filter(x => x.textContent.trim() === 'Maosh hisobi').length)) === 1);
    await m.openForm();
    const meth = await m.pg.$$eval('#xe-method option', o => o.map(x => x.value));
    const mt = await m.modalTxt();
    ok('oyna: Moliya menejerida usul — bank va karta (naqd — «Kassa» orqali), boshlang‘ichi bank; kontragent va № — majburiy belgisi bilan',
      meth.join(',') === 'bank,card' && (await m.pg.$eval('#xe-method', e => e.value)) === 'bank' && /Kontragent \*/.test(mt) && /Hujjat № \*/.test(mt) && /Kassa ishga tushgan/.test(mt), [meth, mt.slice(0, 500)]);
    const opts = async () => m.pg.$eval('#xe-lines [data-f="articleId"]', s => [...s.options].map(o => o.value));
    const bankOpts = await opts();
    await m.pg.selectOption('#xe-method', 'card'); await m.pg.waitForTimeout(150);
    const cardOpts = await opts();
    await m.pg.selectOption('#xe-method', 'bank'); await m.pg.waitForTimeout(150);
    ok('statiyalar usulga qarab: bankda soliq (OP-12) va bank komissiyasi bor, kartada soliq yo‘q; ish haqi, maosh to‘lovi, kartani to‘ldirish, daromad — hech qayerda',
      bankOpts.includes('OP-12') && bankOpts.includes('EX-40') && !cardOpts.includes('OP-12') && cardOpts.includes('EX-40')
      && !['EX-01', 'OP-09', 'OP-04', 'IN-01', 'OP-15'].some(x => bankOpts.includes(x) || cardOpts.includes(x)), [bankOpts.length, cardOpts.length]);
    await m.pg.click('#xe-save'); await m.pg.waitForTimeout(400);
    ok('bo‘sh oyna saqlanmaydi: «kontragent majburiy»', (await m.toasts()).includes('Bank o‘tkazmasida kontragent (kimga to‘langani) majburiy'), await m.toasts());
    // yangi kontragent shu oynaning o'zidan
    await m.pg.click('#xe-cpnew'); await m.pg.waitForSelector('#xe-cn');
    await m.pg.fill('#xe-cn', 'Sinov Elektr MChJ'); await m.pg.selectOption('#xe-ck', 'supplier'); await m.pg.fill('#xe-cs', '300 000 019'); await m.pg.click('#xe-cadd');
    await m.pg.waitForFunction(() => { const s = document.querySelector('#xe-cp'); return s && s.value !== ''; }, null, { timeout: 15000 }).catch(() => {});
    const cpId = q(`select id from public.fin_counterparties where name = 'Sinov Elektr MChJ'`);
    ok('yangi kontragent qo‘shildi va tanlandi (tur, STIR — faqat raqamlar)', !!cpId && (await m.pg.$eval('#xe-cp', e => e.value)) === cpId
      && q(`select kind || ':' || stir from public.fin_counterparties where id = '${cpId}'`) === 'supplier:300000019', cpId);
    await m.pg.fill('#xe-no', '№ 77'); await m.pg.fill('#xe-dd', today); await m.pg.fill('#xe-att', 'Hisob-faktura № 77, dalolatnoma'); await m.pg.fill('#xe-note', 'Yanvar kommunal');
    await m.pg.selectOption('#xe-lines [data-i="0"] [data-f="articleId"]', 'EX-11'); await m.pg.fill('#xe-lines [data-i="0"] [data-f="amount"]', '1200000'); await m.pg.fill('#xe-lines [data-i="0"] [data-f="note"]', 'Elektr');
    await m.pg.click('#xe-add'); await m.pg.waitForSelector('#xe-lines [data-i="1"]');
    await m.pg.selectOption('#xe-lines [data-i="1"] [data-f="articleId"]', 'EX-13'); await m.pg.fill('#xe-lines [data-i="1"] [data-f="amount"]', '300 000');
    ok('summa maydoni mingliklar bilan; jami — 1 500 000 so‘m', (await m.pg.$eval('#xe-lines [data-i="0"] [data-f="amount"]', e => e.value)) === '1 200 000'
      && (await m.pg.$eval('#xe-total', e => e.textContent)) === '1 500 000 so‘m', await m.pg.$eval('#xe-total', e => e.textContent));
    await m.pg.click('#xe-save');
    const sv = await m.saved(); const smt = await m.modalTxt();
    const d1 = docs(`"docNo" = '77' and status = 'posted'`, 'id');
    ok('saqlandi: natija oynasi (statiyalar, summa, usul, №, kontragent), chek tugmasi', sv && /Elektr energiyasi, Suv, kanalizatsiya, chiqindi — 1 500 000 so‘m/.test(smt)
      && /Bank o‘tkazmasi · № 77 · Sinov Elektr MChJ/.test(smt) && !!(await m.pg.$('#xe-print')), smt.slice(0, 400));
    ok('bazada: hujjat (bank, № 77 — tozalangan, ilova, 2 qator, muallif — Moliya menejeri) va «Buxgalteriya»da 2 qator (toifa statiyadan)',
      !!d1 && docs(`id = '${d1}'`, `method || ':' || "docNo" || ':' || "docDate" || ':' || attachment || ':' || jsonb_array_length(lines) || ':' || trim_scale(amount) || ':' || "createdBy" || ':' || "createdByName"`)
        === `bank:77:${today}:Hisob-faktura № 77, dalolatnoma:2:1500000:${ids.R_MOL}:Sinov Moliyachi`
      && q(`select string_agg(category || '=' || trim_scale(amount) || ':' || method, ',' order by id) from public.expenses where "expDocId" = '${d1}'`) === 'Kommunal=1200000:bank,Boshqa=300000:bank',
      [d1, q(`select id, category, amount, method from public.expenses where "expDocId" is not null`)]);
    await m.pg.click('#xe-close').catch(() => {}); await m.pg.waitForTimeout(500);
    ok('ro‘yxatda: ikkala qator «Bank № 77» belgisi, «Hujjat», «Tuzatish», «Bekor» bilan',
      (await m.pg.$$eval('#ac-body .chip', c => c.filter(x => x.textContent.trim() === 'Bank № 77').length)) === 2
      && (await m.pg.$$(`[data-xdoc="${d1}"]`)).length === 2 && (await m.pg.$$(`[data-xfixd="${d1}"]`)).length === 2 && (await m.pg.$$(`[data-xvoidd="${d1}"]`)).length === 2);
    // hujjatni ko'rish
    await m.pg.click(`[data-xdoc="${d1}"]`); await m.pg.waitForTimeout(500);
    const vt = await m.modalTxt();
    ok('«Hujjat»: kontragent, №, sana, ilova, statiya qatorlari, jami, kim kiritgani', /Xarajat hujjati/.test(vt) && /Kiritilgan/.test(vt) && vt.includes('Sinov Elektr MChJ') && vt.includes('№ 77')
      && vt.includes('Hisob-faktura № 77, dalolatnoma') && vt.includes('Elektr energiyasi') && vt.includes('Suv, kanalizatsiya, chiqindi') && vt.includes('1 500 000 so‘m') && vt.includes('Sinov Moliyachi'), vt.slice(0, 600));
    await m.closeAny();

    // ---------------- 2) takror to'lov: ogohlantirish (tasdiqlansa yoziladi), keyin bekor qilish
    await m.openForm();
    await m.pg.selectOption('#xe-cp', cpId); await m.pg.fill('#xe-no', '77');
    await m.pg.selectOption('#xe-lines [data-f="articleId"]', 'EX-11'); await m.pg.fill('#xe-lines [data-f="amount"]', '100 000');
    const nd = m.dialogs.length;
    await m.pg.click('#xe-save'); const sv2 = await m.saved();
    const dupMsg = m.dialogs.slice(nd).join(' | ');
    const d2 = docs(`"docNo" = '77' and status = 'posted' and id <> '${d1}'`, 'id');
    ok('takror (shu kontragent va № 77): ogohlantirish — kim, qachon, qancha; tasdiqlangach yozildi', sv2 && /Takror bo'lishi mumkin/.test(dupMsg) && dupMsg.includes('№ 77') && dupMsg.includes("1 500 000 so'm") && dupMsg.includes('Sinov Moliyachi') && !!d2, [dupMsg, d2]);
    await m.pg.click('#xe-close').catch(() => {}); await m.pg.waitForTimeout(500);
    await m.pg.click(`[data-xvoidd="${d2}"]`); await m.pg.waitForSelector('#xe-reason');
    const vmt = await m.modalTxt();
    await m.pg.click('#xe-vok'); await m.pg.waitForTimeout(300);
    const tShort = await m.toasts();
    await m.pg.fill('#xe-reason', 'Takror kiritilgan (sinov)'); await m.pg.click('#xe-vok');
    await m.pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).catch(() => {});
    await m.pg.waitForTimeout(500);
    ok('«Bekor»: oynada summa va kontragent, sababsiz — rad; sabab bilan — hujjat bekor (sabab, kim), qatori «Buxgalteriya»dan chiqdi, ro‘yxatda yo‘q',
      vmt.includes('100 000 so‘m') && vmt.includes('Sinov Elektr MChJ') && tShort.includes('sababini yozing')
      && docs(`id = '${d2}'`, `status || ':' || "voidReason" || ':' || "voidedBy"`) === `void:Takror kiritilgan (sinov):${ids.R_MOL}`
      && q(`select count(*) from public.expenses where "expDocId" = '${d2}'`) === '0' && !(await m.pg.$(`[data-xdoc="${d2}"]`)), [vmt.slice(0, 300), tShort]);

    // ---------------- 3) tuzatish: eski hujjat bekor, yangisi yoziladi
    await m.pg.click(`[data-xfixd="${d1}"]`); await m.pg.waitForSelector('#xe-save'); await m.pg.waitForTimeout(300);
    const fv = { no: await m.pg.$eval('#xe-no', e => e.value), cp: await m.pg.$eval('#xe-cp', e => e.value), h: await m.modalH(), t: await m.modalTxt(),
      amts: await m.pg.$$eval('#xe-lines [data-f="amount"]', a => a.map(x => x.value)) };
    ok('«Tuzatish»: oyna hujjat ma’lumoti bilan to‘ldirilgan (№, kontragent, qatorlar), ogohlantirish matni', fv.h === 'Xarajatni tuzatish' && fv.no === '77' && fv.cp === cpId
      && fv.amts.join('|') === '1 200 000|300 000' && /eski hujjat bekor qilinadi va o‘rniga shu hujjat yoziladi/.test(fv.t), fv);
    await m.pg.fill('#xe-lines [data-i="1"] [data-f="amount"]', '250 000'); await m.pg.click('#xe-save');
    await m.saved();
    const d3 = docs(`replaces = '${d1}'`, 'id');
    ok('tuzatildi: yangi hujjat (1 450 000, replaces), eskisi bekor (replacedBy, sabab); «Buxgalteriya»da faqat yangisi',
      !!d3 && docs(`id = '${d3}'`, `status || ':' || trim_scale(amount)`) === 'posted:1450000'
      && docs(`id = '${d1}'`, `status || ':' || ("replacedBy" = '${d3}') || ':' || "voidReason"`) === "void:true:Tuzatildi: o'rniga yangi hujjat yozildi"
      && q(`select count(*) from public.expenses where "expDocId" = '${d1}'`) === '0' && q(`select string_agg(trim_scale(amount)::text, ',' order by id) from public.expenses where "expDocId" = '${d3}'`) === '1200000,250000',
      [d3, docs(`id in ('${d1}', '${d3}')`, `string_agg(id || ':' || status || ':' || coalesce("voidReason", '-'), ' ; ')`)]);
    await m.pg.click('#xe-close').catch(() => {}); await m.pg.waitForTimeout(500);

    // ---------------- 4) eski (hujjatsiz) yozuvlar: tuzatish va bekor qilish
    await m.pg.click('[data-xfixr="e19-old1"]'); await m.pg.waitForSelector('#xe-save'); await m.pg.waitForTimeout(300);
    const lv = { m: await m.pg.$eval('#xe-method', e => e.value), art: await m.pg.$eval('#xe-lines [data-f="articleId"]', e => e.value), amt: await m.pg.$eval('#xe-lines [data-f="amount"]', e => e.value),
      note: await m.pg.$eval('#xe-note', e => e.value), t: await m.modalTxt() };
    ok('eski yozuvni «Tuzatish»: usul, statiya, summa va izoh oldindan to‘ldirilgan; ogohlantirish — «eski yozuv bekor qilinadi»',
      lv.m === 'bank' && lv.art === 'EX-10' && lv.amt === '5 000 000' && lv.note === 'Sinov ijara (eski)' && /eski yozuv bekor qilinadi/.test(lv.t), lv);
    await m.pg.selectOption('#xe-cp', 'cp_b19'); await m.pg.fill('#xe-no', 'IJ-1'); await m.pg.click('#xe-save');
    await m.saved();
    const snap1 = docs(`"clientRef" = 'legacy:e19-old1'`, `id || ':' || status || ':' || origin`);
    const d4 = docs(`"docNo" = 'IJ-1'`, 'id');
    ok('eski yozuv tuzatildi: reyestrda «eski yozuv» surati (bekor), yangi hujjat uni tuzatgan; eski qator olib tashlandi',
      /^xl_[0-9a-f]{32}:void:legacy$/.test(snap1) && docs(`id = '${d4}'`, `replaces`) === snap1.split(':')[0] && q(`select count(*) from public.expenses where id = 'e19-old1'`) === '0'
      && q(`select category || ':' || trim_scale(amount) || ':' || method from public.expenses where "expDocId" = '${d4}'`) === 'Ijara:5000000:bank', [snap1, d4]);
    await m.pg.click('#xe-close').catch(() => {}); await m.pg.waitForTimeout(500);
    await m.pg.click('[data-xvoidr="e19-old2"]'); await m.pg.waitForSelector('#xe-reason');
    await m.pg.fill('#xe-reason', 'Ikki marta yozilgan (sinov)'); await m.pg.click('#xe-vok');
    await m.pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).catch(() => {});
    await m.pg.waitForTimeout(500);
    ok('eski yozuv bekor qilindi: surat (sabab, statiya, summa) reyestrda, qator «Buxgalteriya»dan chiqdi',
      docs(`"clientRef" = 'legacy:e19-old2'`, `status || ':' || "voidReason" || ':' || (lines -> 0 ->> 'articleId') || ':' || trim_scale(amount)`) === 'void:Ikki marta yozilgan (sinov):EX-32:120000'
      && q(`select count(*) from public.expenses where id = 'e19-old2'`) === '0' && !(await m.pg.$('[data-xvoidr="e19-old2"]')));
    // oylik maosh hisobi qatori — avvalgidek to'g'ridan-to'g'ri o'chiriladi (server ruxsat beradigan yagona to'g'ridan-to'g'ri yozuv)
    await m.pg.click(`[data-edel="payroll__${month}"]`); await m.pg.waitForTimeout(1200);
    ok('maosh hisobi qatori o‘chirildi (tasdiq bilan)', q(`select count(*) from public.expenses where id = 'payroll__${month}'`) === '0' && m.dialogs.some(x => /Xarajat o‘chirilsinmi/.test(x)), m.dialogs.slice(-2));
    await m.pg.screenshot({ path: `${OUT}/k19-mol-${UI}-1440.png`, fullPage: true });
  }
  await m.ctx.close();

  // ---------------- 5) telefon ekrani (390 px): oyna gorizontal siljimaydi
  {
    const p = await login(ids.R_MOL, { width: 390, height: 844 });
    await p.acReady(); await p.openForm();
    await p.pg.click('#xe-add'); await p.pg.waitForTimeout(200);
    const ov = await p.pg.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth,
      mw: Math.round(document.querySelector('#modal').getBoundingClientRect().right) }));
    await p.pg.screenshot({ path: `${OUT}/k19-mol-${UI}-390-form.png`, fullPage: false });
    ok('telefon (390 px): xarajat oynasi ekranga sig‘adi (gorizontal siljish yo‘q)', ov.sw <= ov.cw + 1 && ov.mw <= ov.cw + 1, ov);
    await p.ctx.close();
  }

  // ---------------- 6) buxgalter: faqat ko'radi
  {
    const a = await login(ACC);
    await a.acReady('#ac-body');
    const d3 = docs(`status = 'posted' and "docNo" = '77'`, 'id');
    const bt = await a.pg.evaluate(() => ['#ac-add', '[data-xfixd]', '[data-xvoidd]', '[data-xfixr]', '[data-xvoidr]', '[data-erec]', '[data-edel]', '[data-eedit]'].filter(s => document.querySelector(s)));
    ok('buxgalter: yozish tugmalari yo‘q; hujjat qatorida «Hujjat» bor', bt.length === 0 && !!(await a.pg.$(`[data-xdoc="${d3}"]`)), bt);
    await a.pg.click(`[data-xdoc="${d3}"]`); await a.pg.waitForTimeout(500);
    const at = await a.modalTxt();
    ok('buxgalter: hujjat oynasi (kontragent, №, statiyalar, jami)', at.includes('Sinov Elektr MChJ') && at.includes('№ 77') && at.includes('Elektr energiyasi') && at.includes('1 450 000 so‘m'), at.slice(0, 400));
    await a.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.log('XATO ' + (e.stack || e)); process.exit(1); });
