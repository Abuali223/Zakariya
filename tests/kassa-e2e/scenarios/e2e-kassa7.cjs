// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): Buxgalter roli (2-ro'yxat) — so'rovni tasdiqlash, kunni tekshirish,
//   nazorat ro'yxati, «Davr»; begona bo'limlar va pul amallari yo'q.  Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa7.cjs [v1|v2]
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
  const today = q('select app.fin_today()');
  const ACC = 'u_acc_e2e';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status`);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  q(`insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_e7', 'supplier', 'Sinov Taminot MChJ', '', true) on conflict (id) do nothing`);
  const cp1 = { id: 'cp_e7' };
  const req = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_expense","amount":150000,"partyType":"counterparty","partyId":"${cp1.id}","basis":"Hisob-faktura № 7","clientRef":"e7-req-0001","lines":[{"articleId":"EX-07","amount":150000}]}'::jsonb)::text`));
  async function login(uid, vp) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 }, acceptDownloads: true });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage(); const dialogs = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(900);
    const tabs = async () => pg.$$eval('#tabs button[data-tab]', a => a.map(x => x.dataset.tab));
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
    return { ctx, pg, dialogs, tabs, tab, kassaReady, modalGone, toasts };
  }

  // ---------------- 1) Buxgalter: bo'limlar, «Tasdiqlash» navbati, so'rovni tasdiqlash
  const a = await login(ACC);
  {
    const t = await a.tabs();
    ok('buxgalter: menyuda «Tasdiqlash», «To‘lovlar», «Kassa», «Buxgalteriya» (F1.21)', t.join(',') === 'approvals,payments,kassa,accounting', t);
    ok('buxgalter: yuqorida rol nomi «Buxgalter»', /Buxgalter/.test(await a.pg.$eval('#who', e => e.textContent)), await a.pg.$eval('#who', e => e.textContent));
    await a.tab('approvals'); await a.pg.waitForFunction(() => /Hisob-faktura № 7|150 000/.test(document.querySelector('#view').innerText), null, { timeout: 20000 }).catch(() => {});
    ok('«Tasdiqlash»: kassa so‘rovi navbatda ko‘rinadi', /Kassa: chiqim va kirim so‘rovlari/.test(await a.pg.$eval('#view', e => e.innerText)) && /150 000/.test(await a.pg.$eval('#view', e => e.innerText)), (await a.pg.$eval('#view', e => e.innerText)).slice(0, 300));
    await a.kassaReady();
    const acts = await a.pg.$$eval('#ks-actions button, #ks-actions select', x => x.map(e => e.id));
    ok('«Kassa»: buxgalterda pul amallari yo‘q (kirim, chiqim so‘rovi, yopish, sozlamalar), «Davr» bor', !acts.includes('ks-in') && !acts.includes('ks-out') && !acts.includes('ks-close') && !acts.includes('ks-set') && !acts.includes('ks-hand') && acts.includes('ks-period'), acts);
    ok('«Kassa»: nazorat ro‘yxati ko‘rinadi', !!(await a.pg.waitForSelector('#ks-ctl-card', { timeout: 15000 }).catch(() => null)));
    const btn = await a.pg.waitForSelector(`[data-appr="${req.id}"], [data-kappr="${req.id}"]`, { timeout: 15000 }).catch(() => null);
    ok('so‘rov qatorida «Tasdiqlash» tugmasi bor, «Pulni berish» yo‘q', !!btn && !(await a.pg.$(`[data-pay="${req.id}"]`)));
    if (btn) { await btn.click(); await a.pg.waitForFunction(id => !document.querySelector(`[data-appr="${id}"], [data-kappr="${id}"]`), req.id, { timeout: 15000 }).catch(() => {}); }
    ok('buxgalter tasdiqladi (2-ro‘yxat): hujjat «tasdiqlangan»', q(`select status || ':' || ("approvedBy" = '${ACC}') from public.cash_docs where id='${req.id}'`) === 'approved:true', q(`select status, "approvedBy" from public.cash_docs where id='${req.id}'`));
  }
  // kassir pulni beradi va kunni yopadi (server orqali)
  asUser(ids.R_KAS, `select public.kassa_doc_pay('${req.id}')::text`);
  // hisobdorga avans (2-ro'yxat — buxgalter tasdiqlaydi), kassir beradi: 200 000
  const adv = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_accountable","amount":200000,"partyType":"employee","partyId":"teachers:${ids.T1}","basis":"Xojalik xaridlari","clientRef":"e7-adv-0001"}'::jsonb)::text`));
  asUser(ACC, `select public.kassa_doc_approve('${adv.id}')::text`);
  asUser(ids.R_KAS, `select public.kassa_doc_pay('${adv.id}')::text`);
  const closed = JSON.parse(asUser(ids.R_KAS, `select public.kassa_day_close('{"desk":"main","day":"${today}","counted":650000}'::jsonb)::text`));
  ok('kassir pulni berdi (xarajat 150 000, hisobdorga avans 200 000) va kunni yopdi (qoldiq 650 000)', closed.ok && closed.day && closed.day.status === 'closed' && Number(closed.day.closing) === 650000, closed);

  // ---------------- 2) Buxgalter kunni tekshiradi; «Davr» — faqat ko'rish
  {
    await a.kassaReady();
    const vb = await a.pg.waitForSelector('[data-verify]', { timeout: 15000 }).catch(() => null);
    ok('yopilgan kun qatorida «Tekshirish» tugmasi bor, «Qayta ochish» yo‘q', !!vb && !(await a.pg.$('[data-reopen]')));
    if (vb) {
      await vb.click(); await a.pg.waitForSelector('#kv-save', { timeout: 15000 });
      await a.pg.click('#kv-save'); await a.pg.waitForTimeout(300);
      ok('«qog‘oz va ilovalar olindi» belgisisiz tekshirilmaydi', q(`select status from public.cash_days where desk='main' and day='${today}'`) === 'closed', await a.toasts());
      await a.pg.check('#kv-papers'); await a.pg.click('#kv-save'); await a.modalGone().catch(() => {});
    }
    ok('buxgalter kunni tekshirdi: holat «tekshirilgan», tekshiruvchi — buxgalter', q(`select status || ':' || ("verifiedBy" = '${ACC}') from public.cash_days where desk='main' and day='${today}'`) === 'verified:true', q(`select status, "verifiedBy" from public.cash_days where desk='main' and day='${today}'`));
    await a.kassaReady(); await a.pg.click('#ks-period'); await a.pg.waitForSelector('#kpd-lock', { timeout: 15000 });
    ok('«Davr»: buxgalter ko‘radi, surat olish va qulf tugmalari yo‘q', !(await a.pg.$('#kpd-take')) && !(await a.pg.$('#kpd-setlock')));
    await a.pg.click('#m-cancel').catch(() => {});
    await a.pg.screenshot({ path: `${OUT}/acc-${UI}-1440.png` });
  }
  // ---------------- 2b) Buxgalter: avans hisoboti — «Kassa» → «Avans hisoboti» (hisobdor sarflagan pul, naqdsiz dalolatnoma)
  {
    await a.kassaReady();
    ok('«Avans hisoboti» tugmasi buxgalterda bor', !!(await a.pg.$('#ks-adv')));
    await a.pg.click('#ks-adv'); await a.pg.waitForSelector('#av-p', { timeout: 15000 });
    const opts = await a.pg.$$eval('#av-p option', os => os.map(o => o.value + '|' + o.textContent));
    ok('oynada hisobdor va uning qoldig‘i (200 000) ko‘rinadi', opts.some(o => o.startsWith(`teachers:${ids.T1}|`) && /200\s000/.test(o)), opts);
    await a.pg.selectOption('#av-p', `teachers:${ids.T1}`);
    await a.pg.selectOption('[data-aart="0"]', 'EX-16');
    await a.pg.fill('[data-aamt="0"]', '150000'); await a.pg.fill('[data-anote="0"]', 'Chek 7, bugun');
    const sumTxt = await a.pg.$eval('#av-sum', e => e.textContent);
    ok('jami va qolgan qoldiq hisoblanadi (150 000 → 50 000)', /150\s000/.test(sumTxt) && /50\s000/.test(sumTxt), sumTxt);
    await a.pg.click('#av-save'); await a.modalGone().catch(() => {}); await a.pg.waitForTimeout(1000);
    const adoc = q(`select id from public.cash_docs where op = 'nc_adv_report' order by "createdAt" desc limit 1`);
    const row = q(`select c.status || ':' || c.amount::bigint || ':' || (select count(*) from public.expenses e where e."cashDocId" = c.id and e.method = 'accountable') || ':' || trim_scale(app.kassa_acc_open('teachers:${ids.T1}')) from public.cash_docs c where c.id = '${adoc}'`);
    ok('avans hisoboti o‘tkazildi: 150 000, «Buxgalteriya»da 1 ta xarajat, hisobdorda 50 000 qoldi', row === 'posted:150000:1:50000', row);
    await a.kassaReady();
    ok('dalolatnomalar ro‘yxatida avans hisoboti va «Bekor» tugmasi bor', !!(await a.pg.$(`[data-advvoid="${adoc}"]`)) && /Avans hisoboti/.test(await a.pg.$eval('#ks-acts', e => e.innerText).catch(() => '')));
    await a.pg.waitForSelector('#ks-ctl-card', { timeout: 15000 }).catch(() => {});
    const ctlTxt = await a.pg.$eval('#ks-ctl', e => e.innerText).catch(() => '');
    ok('nazorat ro‘yxati: hisobdorda 50 000', /50\s000/.test(ctlTxt), ctlTxt.slice(0, 400));
    await a.pg.click(`[data-advvoid="${adoc}"]`); await a.pg.waitForSelector('#ks-reason', { timeout: 10000 });
    await a.pg.fill('#ks-reason', 'Sinov: xato kiritilgan'); await a.pg.click('#ks-ok'); await a.modalGone().catch(() => {}); await a.pg.waitForTimeout(1000);
    const vrow = q(`select status || ':' || (select count(*) from public.expenses where "cashDocId" = '${adoc}') || ':' || trim_scale(app.kassa_acc_open('teachers:${ids.T1}')) from public.cash_docs where id = '${adoc}'`);
    ok('bekor qilindi: xarajat olib tashlandi, hisobdordagi qoldiq 200 000 ga qaytdi', vrow === 'void:0:200000', vrow);
    await a.pg.screenshot({ path: `${OUT}/acc-adv-${UI}-1440.png` });
  }
  // server: buxgalter pul amallarini bajara olmaydi
  ok('server: buxgalter kirim yoza olmaydi, so‘rov yubora olmaydi, pul bera olmaydi',
    [asUserErr(ACC, `select public.kassa_receipt('{"op":"in_other","amount":1000,"partyType":"other","partyName":"X","articleId":"IN-06","basis":"T","note":"n","clientRef":"e7-x-0001"}'::jsonb)::text`),
     asUserErr(ACC, `select public.kassa_payout_request('{"op":"out_expense","amount":1000,"partyType":"counterparty","partyId":"${cp1.id}","basis":"H","clientRef":"e7-x-0002","lines":[{"articleId":"EX-07","amount":1000}]}'::jsonb)::text`),
     asUserErr(ACC, `select public.kassa_doc_pay('${req.id}')::text`)].every(x => /ERROR:\s+Ruxsat yo/.test(x)));
  await a.ctx.close();

  // ---------------- 3) Direktor: foydalanuvchilar ro'yxatida «Buxgalter» roli bor; telefon
  {
    const d = await login(ids.R_DIR); await d.tab('users');
    await d.pg.waitForSelector(`[data-edu="${ACC}"]`, { timeout: 30000 }).catch(() => {});
    ok('direktor: foydalanuvchilar ro‘yxatida buxgalter hisobi «Buxgalter» roli bilan', /Buxgalter/.test(await d.pg.$eval('#usr-card', e => e.innerText).catch(() => '')));
    await d.pg.click(`[data-edu="${ACC}"]`).catch(() => {}); await d.pg.waitForSelector('#u-role', { timeout: 15000 }).catch(() => {});
    const has = await d.pg.evaluate(() => [...document.querySelectorAll('#u-role option')].some(o => o.value === 'accountant' && /Buxgalter/.test(o.textContent) && o.selected));
    ok('direktor: hisob tahririda «Buxgalter» roli tanlovda bor va tanlangan', has);
    await d.pg.keyboard.press('Escape').catch(() => {});
    await d.pg.evaluate(() => { const bg = document.querySelector('#modal-bg'); if (bg) bg.classList.remove('show'); });
    await d.tab('accounting'); await d.pg.waitForSelector('#ac-add', { state: 'attached', timeout: 20000 });
    for (let i = 0; i < 6 && !(await d.pg.$('#e-date')); i++) { await d.pg.waitForTimeout(700); await d.pg.$eval('#ac-add', x => x.click()).catch(() => {}); }   // ro'yxat yuklanib, tugma ulangach ochiladi
    await d.pg.waitForSelector('#e-method', { state: 'attached', timeout: 15000 }).catch(() => {});
    const meth = await d.pg.$$eval('#e-method option', os => os.map(o => o.value)).catch(() => []);
    const hint = await d.pg.$eval('#modal', e => e.innerText).catch(() => '');
    ok('«Buxgalteriya» xarajat oynasida «Hisobdor shaxs orqali» usuli yo‘q (avans hisoboti orqali), eslatma bor', meth.join(',') === 'bank,card' && /Avans hisoboti/.test(hint), [meth, hint.slice(0, 300), await d.pg.$eval('#view', e => e.innerText.slice(0, 200)).catch(() => '')]);
    await d.pg.keyboard.press('Escape').catch(() => {});
    await d.pg.evaluate(() => { const bg = document.querySelector('#modal-bg'); if (bg) bg.classList.remove('show'); });
    // M2: hisobotsiz qoldig'i (200 000) bor xodimga yangi avans so'rovi (T1 dan kichik) — Direktor tasdig'i ham; sahifa buni aytadi
    await d.kassaReady();
    await d.pg.click('#ks-out'); await d.pg.waitForSelector('#kf-op'); await d.pg.selectOption('#kf-op', 'out_accountable');
    await d.pg.waitForSelector('#kf-pe'); await d.pg.selectOption('#kf-pe', `teachers:${ids.T1}`);
    await d.pg.fill('#kf-amt', '50 000'); await d.pg.fill('#kf-basis', 'Xo‘jalik xaridlari (sinov)');
    await d.pg.click('#kf-save'); await d.modalGone().catch(() => {}); await d.pg.waitForTimeout(500);
    const t2 = await d.toasts();
    const nd = q(`select status || ':' || "needsDirector" from public.cash_docs where op = 'out_accountable' and amount = 50000 order by "createdAt" desc limit 1`);
    ok('hisobotsiz qoldig‘i bor xodimga yangi avans: so‘rov Direktor tasdig‘ini kutadi, sahifa qoldiqni aytadi', nd === 'draft:true' && /hisobot qilinmagan avans bor/.test(t2) && /200\s000/.test(t2), [nd, t2]);
    await d.ctx.close();
    const p = await login(ACC, { width: 390, height: 844 }); await p.kassaReady();
    const sw = await p.pg.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    ok('telefon: buxgalter «Kassa» sahifasi gorizontal siljimaydi', sw <= 1, sw);
    await p.pg.screenshot({ path: `${OUT}/acc-${UI}-390.png` });
    await p.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(2); });
function asUserErr(uid, sql) { try { return asUser(uid, sql); } catch (e) { return String((e.stderr || e.message || e)).slice(0, 300); } }
