// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): yuridik shaxsga kassadan naqd to'lov (F1.27, buxgalter ko'rigi M3).
//   Standart (chegara 0): yetkazib beruvchiga «Xarajat» so'rovida ogohlantirish, so'rov Direktor tasdig'ini kutadi; jismoniy shaxsga —
//   ogohlantirishsiz; Direktor «⚙ Sozlamalar»da chegara qo'yadi → kichik summa Direktorsiz; berilgach nazorat ro'yxatida ko'rinadi.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa9.cjs [v1|v2]
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
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast, #toast, [class*=toast]')].map(e => e.textContent).join(' | '));
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, toasts };
  }
  // tayyorgarlik: ishga tushirish (yuridik shaxs chegarasi qo'yilmagan — standart: har doim Direktor), kontragentlar
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  q(`insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_e9s', 'supplier', 'Sinov Taminot MChJ', '', true), ('cp_e9p', 'person', 'Sinov YaTT Karimov', '', true) on conflict (id) do nothing`);
  // so'rov oynasi: «Xarajat» → kontragent
  const reqForm = async (s, cpId, amount, basis) => {
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'out_expense');
    await s.pg.waitForSelector('#kf-ptype', { state: 'attached' }); await s.pg.selectOption('#kf-ptype', 'counterparty'); await s.pg.waitForSelector('#kf-pc');
    if (cpId) await s.pg.selectOption('#kf-pc', cpId);
    if (amount) { await s.pg.selectOption('#kf-lines [data-art="0"]', 'EX-32'); await s.pg.fill('#kf-lines [data-lamt="0"]', amount); await s.pg.fill('#kf-basis', basis); }
  };
  const orgw = async s => s.pg.evaluate(() => { const w = document.querySelector('#kf-orgw'); return w && w.style.display !== 'none' ? w.textContent : ''; });

  // ---------------- 1) Kassir: yetkazib beruvchiga — ogohlantirish, so'rov Direktorga ham boradi; jismoniy shaxsga — yo'q
  const kas = await login(ids.R_KAS);
  {
    await kas.kassaReady();
    await reqForm(kas, 'cp_e9p');
    ok('jismoniy shaxs (YaTT) tanlansa — ogohlantirish yo‘q', (await orgw(kas)) === '', await orgw(kas));
    await kas.pg.selectOption('#kf-pc', 'cp_e9s');
    const w = await orgw(kas);
    ok('yetkazib beruvchi tanlansa — ogohlantirish: bank yoki hisobdor orqali, kassadan — Direktor tasdig‘i', /Yuridik shaxsga kassadan naqd to‘lov cheklangan/.test(w) && /bank o‘tkazmasi yoki hisobdor shaxs/.test(w) && /Direktor tasdig‘i ham talab qilinadi/.test(w) && !/dan katta summada/.test(w), w);
    await kas.pg.selectOption('#kf-op', 'out_advance'); await kas.pg.waitForTimeout(300);
    ok('operatsiya almashsa ogohlantirish yo‘qoladi', (await orgw(kas)) === '');
    await kas.pg.click('#m-cancel'); await kas.modalGone();
    await reqForm(kas, 'cp_e9s', '50 000', 'Hisob-faktura № 91 (sinov)');
    await kas.pg.click('#kf-save'); await kas.modalGone(); await kas.pg.waitForTimeout(700);
    ok('so‘rov yuborildi: «Direktor tasdig‘i ham kerak» xabari', /yuridik shaxsga naqd to‘lov: Direktor tasdig‘i ham kerak/.test(await kas.toasts()), await kas.toasts());
    ok('server: 50 000 (T1 dan kichik) bo‘lsa ham Direktor tasdig‘i talab qilinadi', q(`select "needsDirector" || ':' || "needsList2" from public.cash_docs where op='out_expense' and "partyId"='cp_e9s'`) === 'true:true');
  }

  // ---------------- 2) Direktor: «⚙ Sozlamalar»da chegara — 200 000
  {
    const d = await login(ids.R_DIR);
    await d.kassaReady(); await d.pg.click('#ks-set'); await d.pg.waitForSelector('#kx-orgmax');
    ok('sozlamalarda yuridik shaxsga naqd to‘lov chegarasi maydoni (bo‘sh — har doim Direktor)', (await d.pg.$eval('#kx-orgmax', e => e.value)) === '' && /Direktor tasdig‘isiz chegara/.test(await d.pg.$eval('#modal', e => e.textContent)));
    await d.pg.fill('#kx-orgmax', '200000'); await d.pg.click('#kx-save'); await d.modalGone();
    ok('chegara saqlandi: 200 000', q(`select extra ->> 'orgCashMax' from public.fin_org where id='main'`) === '200000', q(`select extra from public.fin_org where id='main'`));
    await d.ctx.close();
  }

  // ---------------- 3) Kassir: 150 000 (chegaradan kichik) — Direktorsiz, ogohlantirish chegarani aytadi
  {
    await kas.pg.reload(); await kas.pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 }); await kas.kassaReady();
    await reqForm(kas, 'cp_e9s', '150 000', 'Hisob-faktura № 92 (sinov)');
    const w = await orgw(kas);
    ok('ogohlantirishda chegara: «200 000 so‘mdan katta summada Direktor tasdig‘i»', /200 000 so‘mdan katta summada Direktor tasdig‘i/.test(w), w);
    await kas.pg.click('#kf-save'); await kas.modalGone(); await kas.pg.waitForTimeout(700);
    const id = q(`select id from public.cash_docs where op='out_expense' and amount=150000`);
    ok('150 000 — faqat moliya tasdig‘i (Direktorsiz); oddiy xabar', q(`select "needsDirector"::text from public.cash_docs where id='${id}'`) === 'false' && /tasdiq kutilmoqda/.test(await kas.toasts()), await kas.toasts());
    asUser(ids.R_MOL, `select public.kassa_doc_approve('${id}')::text`);
    asUser(ids.R_KAS, `select public.kassa_doc_pay('${id}')::text`);
    ok('moliya tasdiqladi, kassir berdi', q(`select status from public.cash_docs where id='${id}'`) === 'posted');
    await kas.ctx.close();
  }

  // ---------------- 4) Moliya menejeri: nazorat ro'yxatida yuridik shaxslarga naqd to'lov
  {
    const m = await login(ids.R_MOL);
    await m.kassaReady(); await m.pg.waitForSelector('#ks-ctl-card', { timeout: 15000 }).catch(() => {});
    const row = await m.pg.$eval('#ks-ctl-card tr[data-ctl="orgCash"]', e => e.dataset.level + '|' + e.innerText.replace(/\s+/g, ' ')).catch(() => '');
    ok('nazorat ro‘yxati: «Yuridik shaxslarga kassadan naqd to‘lov — 1 ta · 150 000 so‘m» (diqqat)', /^warn\|/.test(row) && /Yuridik shaxslarga kassadan naqd to‘lov/.test(row) && /1 ta · 150 000 so‘m/.test(row), row);
    await m.pg.screenshot({ path: `${OUT}/org-${UI}-1440.png` });
    await m.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(1); });
