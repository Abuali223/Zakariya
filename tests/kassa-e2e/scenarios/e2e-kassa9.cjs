// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): yuridik shaxsga kassadan naqd to'lov (F1.27, buxgalter ko'rigi M3).
//   Standart (chegara 0): yetkazib beruvchiga «Xarajat» so'rovida ogohlantirish, so'rov Direktor tasdig'ini kutadi; jismoniy shaxsga —
//   ogohlantirishsiz; Direktor «⚙ Sozlamalar»da chegara qo'yadi → kichik summa Direktorsiz; berilgach nazorat ro'yxatida ko'rinadi.
//   Kontragent turi (sec-3, ui-13): kassir «+ yangi» bilan qo'shgan «Jismoniy shaxs» — «Qo'shish» ikki marta bosilsa ham bitta; turi
//   tasdiqlanguncha yuridik shaxs hisoblanadi (ogohlantirish); yaratgan kassir (va Moliya menejeri) tasdiqlay olmaydi — buxgalter
//   nazorat ro'yxatida tasdiqlaydi, shundan keyin ogohlantirish yo'q.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa9.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const sp = s => String(s || '').replace(/[\u00a0\u202f]/g, ' ').replace(/\s+/g, ' ').trim();
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
// server rad etish matni (psql stderr dagi ERROR qatori; rad etilmasa — bo'sh)
const refusedMsg = (uid, sql) => ((String(cp.spawnSync(E.PSQL[0], [...E.PSQL.slice(1), '-q', '-At', '-d', E.DB, '-c',
  `begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`], { encoding: 'utf8' }).stderr || '').match(/ERROR:\s+(.*)/) || [])[1] || '').trim();
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
  q(`insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_e9s', 'supplier', 'Sinov Taminot MChJ', '', true) on conflict (id) do nothing`);
  const ACC = 'u_acc_e9';   // buxgalter — kontragent turini tasdiqlaydigan ikkinchi xodim
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter9@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status`);
  const YATT = 'Sinov YaTT Karimov';
  const UNCONF_W = 'Kontragent turi («Jismoniy shaxs») hali tasdiqlanmagan — yuridik shaxs hisoblanadi. Buxgalter yoki Direktor turini tasdiqlaguncha kassadan naqd to‘lov Direktor tasdig‘i ham talab qilinadi; buxgalter nazorat ro‘yxatida ko‘radi.';
  // so'rov oynasi: «Xarajat» → kontragent
  const reqForm = async (s, cpId, amount, basis) => {
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'out_expense');
    await s.pg.waitForSelector('#kf-ptype', { state: 'attached' }); await s.pg.selectOption('#kf-ptype', 'counterparty'); await s.pg.waitForSelector('#kf-pc');
    if (cpId) await s.pg.selectOption('#kf-pc', cpId);
    if (amount) { await s.pg.selectOption('#kf-lines [data-art="0"]', 'EX-32'); await s.pg.fill('#kf-lines [data-lamt="0"]', amount); await s.pg.fill('#kf-basis', basis); }
  };
  const orgw = async s => s.pg.evaluate(() => { const w = document.querySelector('#kf-orgw'); return w && w.style.display !== 'none' ? w.textContent : ''; });

  // ---------------- 1) Kassir: yangi «Jismoniy shaxs» (ikki marta bosish), tasdiqlanmagan tur — ogohlantirish; yetkazib beruvchiga —
  //                    ogohlantirish, so'rov Direktorga ham boradi
  const kas = await login(ids.R_KAS);
  let cpP = '';
  {
    await kas.kassaReady();
    await reqForm(kas, '');
    let cpCalls = 0; kas.pg.on('request', r => { if (/\/rpc\/fin_counterparty_save/.test(r.url())) cpCalls++; });
    await kas.pg.click('#kf-pnew'); await kas.pg.waitForSelector('#kf-cn');
    const note = sp(await kas.pg.$eval('#kf-pnewbox', e => e.innerText));
    await kas.pg.fill('#kf-cn', YATT); await kas.pg.selectOption('#kf-ck', 'person');
    await kas.pg.dblclick('#kf-cadd'); await kas.pg.waitForFunction(n => [...document.querySelectorAll('#kf-pc option')].some(o => o.selected && o.textContent.startsWith(n)), YATT, { timeout: 15000 }).catch(() => {});
    await kas.pg.waitForTimeout(800);
    cpP = q(`select coalesce(min(id), '') from public.fin_counterparties where name='${YATT}'`);
    const row = q(`select count(*) || ':' || min(kind) || ':' || bool_and("createdBy" = '${ids.R_KAS}') || ':' || bool_and("kindConfirmedBy" is null) from public.fin_counterparties where name='${YATT}'`);
    ok('«+ yangi» → «Jismoniy shaxs», «Qo‘shish» ikki marta bosildi: serverga bitta so‘rov, bitta kontragent (kassir qo‘shdi, turi tasdiqlanmagan); oynada izoh — turini buxgalter yoki Direktor tasdiqlaydi',
      cpCalls === 1 && row === '1:person:true:true' && note.includes('«Jismoniy shaxs» va «Boshqa» turini buxgalter yoki Direktor tasdiqlaydi'), [cpCalls, row, note]);
    const sel = await kas.pg.$eval('#kf-pc', e => e.value + '|' + (e.selectedOptions[0] || {}).textContent);
    ok('yangi kontragent tanlangan («… · turi tasdiqlanmagan»): ogohlantirish — tasdiqlanguncha yuridik shaxs, Direktor tasdig‘i ham kerak',
      sel === `${cpP}|${YATT} · turi tasdiqlanmagan` && sp(await orgw(kas)) === UNCONF_W, [sel, await orgw(kas)]);
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

  // ---------------- 1b) Kontragent turini tasdiqlash: yaratgan kassir va Moliya menejeri — yo'q; buxgalter — nazorat ro'yxatida
  {
    const dup = JSON.parse(asUser(ids.R_KAS, `select public.fin_counterparty_save(null, 'person', 'sinov  yatt karimov', '')::text`));
    ok('server: shu tur, nom (katta-kichik harf, bo‘shliq farqi) va STIR bilan qayta qo‘shilsa — mavjudi qaytadi (dup), yangisi yaratilmaydi',
      dup.dup === true && dup.id === cpP && q(`select count(*) from public.fin_counterparties where kind='person'`) === '1', dup);
    const rk = refusedMsg(ids.R_KAS, `select public.fin_counterparty_confirm('${cpP}', 'person', '${YATT}')::text`);
    const rm = refusedMsg(ids.R_MOL, `select public.fin_counterparty_confirm('${cpP}', 'person', '${YATT}')::text`);
    ok('kontragentni qo‘shgan kassir turini o‘zi tasdiqlay olmaydi, Moliya menejeri ham (rad: «… buxgalter yoki Direktor tasdiqlaydi»); tur tasdiqlanmagan',
      /Ruxsat yo.q: kontragent turini buxgalter yoki Direktor tasdiqlaydi/.test(rk) && /Ruxsat yo.q: kontragent turini buxgalter yoki Direktor tasdiqlaydi/.test(rm)
      && q(`select ("kindConfirmedBy" is null)::text from public.fin_counterparties where id='${cpP}'`) === 'true', [rk, rm]);
    const a = await login(ACC);
    await a.kassaReady(); await a.pg.waitForSelector('#ks-ctl-card:not([data-stale])', { timeout: 15000 }).catch(() => {});
    await a.pg.$$eval('#ks-ctl-card details', ds => ds.forEach(d => { d.open = true; }));
    const crow = sp(await a.pg.$eval('#ks-ctl-card tr[data-ctl="cpKinds"]', e => e.innerText).catch(() => ''));
    const btn = sp(await a.pg.$eval(`#ks-ctl-card [data-cpok="${cpP}"]`, e => e.textContent).catch(() => ''));
    ok('buxgalter: nazorat ro‘yxatida «Kontragent turi — turi tasdiqlanmagan: 1 ta — …» va «✓ … — Jismoniy shaxs» tugmasi', crow.includes(`turi tasdiqlanmagan: 1 ta — ${YATT}`) && btn === `✓ ${YATT} — Jismoniy shaxs`, [crow, btn]);
    await a.pg.click(`#ks-ctl-card [data-cpok="${cpP}"]`);
    await a.pg.waitForFunction(id => !document.querySelector(`[data-cpok="${id}"]`), cpP, { timeout: 15000 }).catch(() => {});
    ok('buxgalter tasdiqladi (so‘ralgan: tur va nom): kontragent turi tasdiqlangan — kim tasdiqlagani yozildi, tugma yo‘qoldi',
      a.dialogs.some(m => m.startsWith(`«${YATT}» turi — «Jismoniy shaxs» — tasdiqlansinmi?`)) && q(`select coalesce("kindConfirmedBy", '') from public.fin_counterparties where id='${cpP}'`) === ACC
      && !(await a.pg.$(`[data-cpok="${cpP}"]`)), [a.dialogs, q(`select "kindConfirmedBy" from public.fin_counterparties where id='${cpP}'`)]);
    await a.ctx.close();
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
    await reqForm(kas, cpP);
    ok('jismoniy shaxs (YaTT, turi buxgalter tasdiqlagan) tanlansa — ogohlantirish yo‘q, ro‘yxatda «turi tasdiqlanmagan» belgisi yo‘q',
      (await orgw(kas)) === '' && (await kas.pg.$eval('#kf-pc', e => (e.selectedOptions[0] || {}).textContent)) === YATT, [await orgw(kas), await kas.pg.$eval('#kf-pc', e => (e.selectedOptions[0] || {}).textContent)]);
    await kas.pg.click('#m-cancel'); await kas.modalGone();
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
