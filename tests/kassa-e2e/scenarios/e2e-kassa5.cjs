// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): o'zaro hisob (nc_offset) — xodimning ish haqidan farzandining o'quv to'lovi.
//   Direktor «Maosh berish» oynasida rasmiylashtiradi → naqdsiz dalolatnoma; «Kassa»da dalolatnomalar ro'yxati; shu kuni bekor qilish.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa5.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()'), month = today.slice(0, 7), mmyyyy = month.slice(5, 7) + '.' + month.slice(0, 4);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","stir":"123456789","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  const sid = 'IQ-0003', sname = q(`select name from public.students where "studentId"='${sid}'`);
  const tname = q(`select name from public.teachers where \"teacherId\" = 'IQT-001'`);   // o'qituvchi (urug'dagi ismi)
  const inv0 = q(`select coalesce(string_agg(id || '=' || coalesce(status, '') || ':' || coalesce("paidAmount", 0), ',' order by id), '') from public.invoices where "studentId"='${sid}'`);
  const cr0 = q(`select coalesce((select credit from public.student_credit where id='${sid}'), 0)`);
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
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
    const salModal = async () => { await tab('accounting'); await pg.waitForSelector('#ac-paysal', { timeout: 30000 }); await pg.click('#ac-paysal'); await pg.waitForSelector('#sp-method', { timeout: 30000 }); };
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, printed, toasts, salModal };
  }

  // ---------------- 1) Direktor: «Maosh berish» → «O'zaro hisob»
  const dir = await login(ids.R_DIR);
  let docId = '';
  {
    const s = dir; await s.salModal();
    ok('direktor: maosh oynasida usullar — naqd, karta, o‘zaro hisob', (await s.pg.$$eval('#sp-method option', o => o.map(x => x.value).join(','))) === 'cash,card,offset');
    await s.pg.selectOption('#sp-t', 'IQT-001'); await s.pg.selectOption('#sp-method', 'offset');
    await s.pg.waitForFunction(() => { const b = document.querySelector('#sp-do'); return b && !b.disabled; }, null, { timeout: 30000 });
    ok('o‘zaro hisob tanlanganda: o‘quvchi va ariza sanasi maydonlari, sana — bugun (o‘zgarmaydi), tugma va yorliq mos',
      (await s.pg.$eval('#sp-ofs', e => e.style.display !== 'none')) && (await s.pg.$eval('#sp-date', e => e.disabled)) && /O‘zaro hisobni rasmiylashtirish/.test(await s.pg.$eval('#sp-do', e => e.textContent))
      && /O‘quv to‘loviga o‘tkaziladigan summa/.test(await s.pg.$eval('#sp-paid-lbl', e => e.textContent)) && /yozma arizasi asosida/.test(await s.pg.$eval('#sp-method-info', e => e.textContent)));
    await s.pg.fill('#sp-paid', '800 000'); await s.pg.click('#sp-do'); await s.pg.waitForTimeout(900);
    ok('o‘quvchi tanlanmasa — yozilmaydi', /O‘quvchini .* tanlang/.test(await s.toasts()) && q(`select count(*) from public.cash_docs where op='nc_offset'`) === '0', await s.toasts());
    await s.pg.fill('#sp-ofs-q', sname.slice(0, 5)); await s.pg.waitForSelector(`[data-ofs-sid="${sid}"]`, { timeout: 15000 }); await s.pg.click(`[data-ofs-sid="${sid}"]`);
    ok('o‘quvchi ro‘yxatdan tanlandi (ism va kod)', (await s.pg.$eval('#sp-ofs-sel', e => e.textContent)).includes(sname) && (await s.pg.$eval('#sp-ofs-sel', e => e.textContent)).includes(sid));
    await s.pg.waitForFunction(() => { const b = document.querySelector('#sp-do'); return b && !b.disabled; }, null, { timeout: 30000 });
    await s.pg.click('#sp-do');
    await s.pg.waitForFunction(() => /O‘zaro hisob rasmiylashtirildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});
    const mt = await s.pg.$eval('#modal', e => e.textContent).catch(() => '');
    ok('tasdiq so‘raldi (xodim, summa, o‘quvchi); natija: o‘zaro hisob dalolatnomasi raqami (o‘z seriyasi «O‘H-»), «Dalolatnoma» tugmasi, termal chek yo‘q',
      s.dialogs.some(m => /O‘zaro hisob rasmiylashtirilsinmi/.test(m) && m.includes('800 000') && m.includes(sname)) && /O‘zaro hisob dalolatnomasi № O‘H-1 yozildi/.test(mt) && /o‘zaro hisob/.test(mt)
      && /Dalolatnoma/.test(await s.pg.$eval('#sp-ko2', e => e.textContent).catch(() => '')) && !(await s.pg.$('#sp-print')), [s.dialogs.slice(-2), mt.slice(0, 400), await s.toasts()]);
    docId = q(`select id from public.cash_docs where op='nc_offset'`);
    ok('bitta tranzaksiya: maosh to‘lovi («offset») + o‘quv to‘lovi («offset», qo‘llangan) + dalolatnoma (ACT, o‘tkazilgan, Dt 6710)',
      q(`select s.method || ':' || trim_scale(s.paid) || ':' || p.provider || ':' || p.status || ':' || trim_scale(p.amount) || ':' || p."studentId" || ':' || c.form || ':' || c.status || ':' || c.series || '-' || c.no || ':' || coalesce(c."dayId", 'kunsiz')
           || ':' || (select string_agg(distinct l.debit, ',') from public.cash_doc_lines l where l."docId" = c.id) || ':' || (select trim_scale(sum(l.amount)) from public.cash_doc_lines l where l."docId" = c.id)
           from public.cash_docs c join public.salary_payments s on s."cashDocId" = c.id join public.payments p on p."cashDocId" = c.id where c.id = '${docId}'`) === `offset:800000:offset:applied:800000:${sid}:ACT:posted:OFS-1:kunsiz:6710:800000`,
      q(`select s.method, s.paid, p.provider, p.status, c.form, c.status, c.no from public.cash_docs c left join public.salary_payments s on s."cashDocId" = c.id left join public.payments p on p."cashDocId" = c.id where c.op = 'nc_offset'`));
    ok('kassadan pul chiqmadi: kassa kuni ochilmadi, naqd hujjat yo‘q', q(`select count(*) from public.cash_days`) === '0' && q(`select count(*) from public.cash_docs where form in ('KO1','KO2')`) === '0');
    const before = (await s.printed()).length;
    await s.pg.click('#sp-ko2'); await s.pg.waitForTimeout(1500);
    const pr = (await s.printed()).slice(before).find(t => /ДАЛОЛАТНОМА/.test(t)) || '';
    ok('dalolatnoma chop etildi: «Ўзаро ҳисоб далолатномаси № ЎҲ-1» (o‘z seriyasi), matn, xodim, o‘quvchi, asos (oy va ariza sanasi), imzolar',
      /ЎЗАРО ҲИСОБ ДАЛОЛАТНОМАСИ № ЎҲ-1/.test(pr) && pr.includes(`${mmyyyy} ойи учун иш ҳақидан 800 000=00 сўм`) && pr.includes('Ходим: ' + tname) && pr.includes(`Ўқувчи: ${sname} (${sid})`)
      && pr.includes(`Асоси: Ўзаро ҳисоб: ${mmyyyy} ойи иш ҳақи ҳисобидан ўқув тўлови — ${sname} (${sid}); ариза ${today.slice(8, 10)}.${today.slice(5, 7)}.${today.slice(0, 4)}`)
      && /Иловаси: Ёзма ариза/.test(pr) && pr.includes('Танишдим, розиман: ходим ' + tname) && /SINOV MAKTAB/.test(pr), pr.slice(0, 900));
    await s.pg.click('#sp-close').catch(() => {}); await s.pg.waitForTimeout(600);
    // «To'lovlar»da usul yorlig'i
    await s.tab('payments'); await s.pg.waitForSelector('#pm-body', { timeout: 30000 }); await s.pg.waitForTimeout(1500);
    const pm = await s.pg.$eval('#view', e => e.innerText.replace(/\s+/g, ' '));
    ok('«To‘lovlar»da o‘quv to‘lovi «O‘zaro hisob (ish haqidan)» usuli bilan ko‘rinadi', /O‘zaro hisob \(ish haqidan\)/.test(pm), pm.slice(0, 500));
    // «Kassa»: dalolatnomalar kartasi
    await s.kassaReady(); await s.pg.waitForSelector('#ks-acts', { timeout: 15000 });
    const at = await s.pg.$eval('#ks-acts', e => e.innerText.replace(/\s+/g, ' '));
    ok('«Kassa»: naqdsiz dalolatnomalar ro‘yxati — O‘H-1 o‘zaro hisob (xodim, summa), D-1 boshlang‘ich qoldiq; Direktorga «Bekor»',
      new RegExp('O‘H-1 .*O‘zaro hisob .*' + tname + ' .*800 000 so‘m').test(at) && /D-1 .*Boshlang‘ich qoldiq .*1 000 000 so‘m/.test(at) && !!(await s.pg.$(`[data-ofsvoid="${docId}"]`)), at.slice(0, 600));
    ok('kassa qoldig‘i o‘zgarmagan (1 000 000) — o‘zaro hisob kassa kitobiga kirmaydi', /Kassadagi qoldiq\s*1 000 000 so‘m/i.test(await s.pg.$eval('#ks-body', e => e.innerText.replace(/\s+/g, ' '))), (await s.pg.$eval('#ks-body', e => e.innerText.replace(/\s+/g, ' '))).slice(0, 300));
    await s.pg.screenshot({ path: `${OUT}/ofs-${UI}-1440.png`, fullPage: true });
  }

  // ---------------- 2) Moliya menejeri: o'zaro hisob usuli yo'q, ro'yxatni ko'radi, bekor qila olmaydi; kassir — funksiya rad etadi
  {
    const m = await login(ids.R_MOL); await m.salModal();
    ok('moliya menejeri: maosh oynasida faqat «karta» (o‘zaro hisob — yo‘q)', (await m.pg.$$eval('#sp-method option', o => o.map(x => x.value).join(','))) === 'card' && !(await m.pg.$('#sp-ofs:not([style*="none"])')));
    await m.pg.click('#m-cancel').catch(() => {});
    await m.kassaReady(); await m.pg.waitForSelector('#ks-acts', { timeout: 15000 });
    ok('moliya menejeri: dalolatnomalarni ko‘radi va chop eta oladi, «Bekor» tugmasi yo‘q', !!(await m.pg.$(`#ks-acts [data-print="${docId}"]`)) && !(await m.pg.$('[data-ofsvoid]')));
    await m.pg.waitForSelector('#ks-ctl-card:not([data-stale])', { timeout: 15000 });
    await m.pg.$eval('#ks-ctl-card details', d => { d.open = true; });
    ok('nazorat ro‘yxati: moslik — «hammasi mos»', /hammasi mos/.test(await m.pg.$eval('#ks-ctl-card tr[data-ctl="reconcile"]', e => e.innerText)));
    let denied = false; try { asUser(ids.R_MOL, `select public.kassa_offset_void('${docId}', 'Sinov uchun bekor')::text`); } catch (e) { denied = /Ruxsat yo/.test(String(e.stderr || e.message)); }
    ok('moliya menejeri: bekor qilish funksiyasi rad etadi (faqat Direktor)', denied);
    await m.ctx.close();
    // kassir (server orqali): o'zaro hisobni rasmiylashtira olmaydi
    let kd = false; try { asUser(ids.R_KAS, `select public.kassa_offset('{"id":"sp_e5_kas_0001","teacherId":"IQT-001","payeeRef":"teachers:x","month":"${month}","paid":1000,"studentId":"${sid}","requestDate":"${today}"}'::jsonb)::text`); } catch (e) { kd = /Ruxsat yo/.test(String(e.stderr || e.message)); }
    ok('kassir: o‘zaro hisob funksiyasi rad etadi (faqat Direktor)', kd);
  }
  ok('moliya menejeri server orqali ham bekor qila olmaydi', q(`select status from public.cash_docs where id='${docId}'`) === 'posted');

  // ---------------- 3) Direktor shu kuni bekor qiladi
  {
    const s = dir; await s.kassaReady(); await s.pg.waitForSelector(`[data-ofsvoid="${docId}"]`, { timeout: 15000 });
    await s.pg.click(`[data-ofsvoid="${docId}"]`); await s.pg.waitForSelector('#ks-reason');
    await s.pg.fill('#ks-reason', 'Xato o‘quvchi tanlangan'); await s.pg.click('#ks-ok'); await s.modalGone(); await s.pg.waitForTimeout(800);
    ok('bekor qilindi: dalolatnoma raqami saqlandi, maosh to‘lovi olib tashlandi, o‘quv to‘lovi bekor, faktura va avans avvalgidek',
      q(`select status || ':' || series || '-' || no from public.cash_docs where id='${docId}'`) === 'void:OFS-1' && q(`select count(*) from public.salary_payments where method='offset'`) === '0'
      && q(`select status from public.payments where provider='offset'`) === 'canceled'
      && q(`select coalesce(string_agg(id || '=' || coalesce(status, '') || ':' || coalesce("paidAmount", 0), ',' order by id), '') from public.invoices where "studentId"='${sid}'`) === inv0
      && q(`select coalesce((select credit from public.student_credit where id='${sid}'), 0)`) === cr0,
      [q(`select status, no from public.cash_docs where id='${docId}'`), q(`select status from public.payments where provider='offset'`), inv0,
       q(`select coalesce(string_agg(id || '=' || coalesce(status, '') || ':' || coalesce("paidAmount", 0), ',' order by id), '') from public.invoices where "studentId"='${sid}'`)]);
    await s.pg.waitForSelector('#ks-acts', { timeout: 15000 });
    const at = await s.pg.$eval('#ks-acts', e => e.innerText.replace(/\s+/g, ' '));
    ok('ro‘yxatda «Bekor qilingan» va sababi; «Bekor» tugmasi yo‘qoldi', /O‘H-1 .*Bekor qilingan .*Xato o‘quvchi tanlangan/.test(at) && !(await s.pg.$('[data-ofsvoid]')), at.slice(0, 500));
    // bekor qilingan dalolatnoma chop etilsa — «БЕКОР ҚИЛИНГАН»
    const before = (await s.printed()).length;
    await s.pg.click(`#ks-acts [data-print="${docId}"]`); await s.pg.waitForTimeout(1200);
    if (await s.pg.$('#kp-copy')) { await s.pg.click('#kp-copy'); await s.pg.waitForTimeout(1200); }
    const pr = (await s.printed()).slice(before).find(t => /ДАЛОЛАТНОМА/.test(t)) || '';
    ok('bekor qilingan dalolatnoma «БЕКОР ҚИЛИНГАН» va «НУСХА» belgisi bilan chop etiladi', /БЕКОР ҚИЛИНГАН/.test(pr) && /НУСХА/.test(pr) && /сабаб: Xato o‘quvchi tanlangan/.test(pr), pr.slice(0, 500));
    await s.pg.screenshot({ path: `${OUT}/ofs-void-${UI}-1440.png`, fullPage: true });
    await s.ctx.close();
  }
  // ---------------- 4) Telefon: maosh oynasida o'zaro hisob maydonlari sig'adi
  {
    const s = await login(ids.R_DIR, { width: 390, height: 844 }); await s.salModal();
    await s.pg.selectOption('#sp-method', 'offset'); await s.pg.waitForTimeout(300);
    const mw = await s.pg.evaluate(() => { const m = document.querySelector('#modal'); return m.scrollWidth - m.clientWidth; });
    ok('telefon: maosh oynasi (o‘zaro hisob) gorizontal siljimaydi', mw <= 1, mw);
    await s.pg.$eval('#sp-ofs', e => e.scrollIntoView());
    await s.pg.screenshot({ path: `${OUT}/ofs-modal-${UI}-390.png` });
    await s.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(2); });
