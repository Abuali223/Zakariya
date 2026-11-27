// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.6 — avans hisoboti to'liq (ikki bosqich, ortiqcha sarf,
//   «Ortiqcha sarfni qoplash», RP-07 hisobdor kartochkasi) brauzerda.
//   1) Kassir: «+ Chiqim so'rovi» → «Hisobdorga avans» — avans maqsadi (statiya) tanlanadi; so'rov hujjat suratida maqsad bilan. Moliya menejeri
//      tasdiqlaydi, kassir pulni beradi (server orqali).
//   2) Buxgalter: «Avans hisoboti» — hisobdor tanlanganda yopilmagan avans va maqsadi ko'rinadi, birinchi qator statiyasi shundan taklif qilinadi;
//      qoldiqdan katta summa — ortiqcha sarf ogohlantirishi; saqlash — tasdiq kutadi (qatorlar 4230 / 6970 bo'lingan), kirituvchida «Tasdiqlash»
//      tugmasi yo'q; RP-07 ro'yxatida — «hisoboti tasdiq kutmoqda».
//   3) Direktor: «Tasdiqlash» bo'limida avans hisoboti (ortiqcha sarf bilan) — tasdiqlaydi: o'tkaziladi, qarzimiz 30 000; АО-1 chop etishda ortiqcha
//      sarf qatori; nazorat ro'yxatida «Hisobdorlarga qarzimiz».
//   4) Kassir: «Ortiqcha sarfni qoplash» — qarz ko'rinadi va summa to'ldiriladi, qarzdan katta summa — rad (oyna ochiq qoladi); so'rov → tasdiq →
//      pulni berish: qarz 0.
//   5) Moliya menejeri: RP-07 kartochkasi — hujjatlar (4230 / 6970 ta'siri), chop etish. 6) Telefon (390 px). 7) Sahifa xatolari yo'q.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa26.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const nb = s => String(s || '').replace(/[\u00a0\u202f]/g, ' ');
(async () => {
  const b = await E.launch();
  const d0 = q('select app.fin_today()');
  const ACC = 'u_acc_e26', T1 = `teachers:${ids.T1}`;
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter26@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status`);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${d0}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${d0}"}'::jsonb)`);

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
    await pg.waitForTimeout(700);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(400); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const toasts = async () => nb(await pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | ')));
    const printed = async () => nb((await pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText; } catch (e) { return ''; } }).join(' || '))).replace(/\s+/g, ' '));
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, toasts, printed };
  }

  // ---- 1) Kassir: hisobdorga avans — maqsadi bilan
  const k = await login(ids.R_KAS); await k.kassaReady();
  await k.pg.click('#ks-out'); await k.pg.waitForSelector('#kf-op', { timeout: 15000 });
  await k.pg.selectOption('#kf-op', 'out_accountable');
  await k.pg.waitForSelector('#kf-purpose', { timeout: 15000 }); await k.pg.waitForSelector('#kf-pe', { timeout: 15000 });
  const popts = await k.pg.$$eval('#kf-purpose option', os => os.map(o => o.value));
  ok('KO-2 «Hisobdorga avans»: «Avans maqsadi» ro‘yxati — avans hisobotidagi statiyalar (ish haqi va OP-17 yo‘q)', popts[0] === '' && popts.includes('EX-32') && popts.includes('OP-18') && !popts.includes('EX-01') && !popts.includes('OP-17'), popts.slice(0, 8));
  await k.pg.selectOption('#kf-pe', T1); await k.pg.selectOption('#kf-purpose', 'EX-32');
  await k.pg.fill('#kf-amt', '100000'); await k.pg.fill('#kf-basis', 'Kanselyariya xaridi uchun');
  await k.pg.click('#kf-save'); await k.modalGone().catch(() => {}); await k.pg.waitForTimeout(800);
  const a0 = q(`select id from public.cash_docs where op = 'out_accountable' order by "createdAt" desc limit 1`);
  ok('so‘rov yozildi: tasdiq kutadi, hujjat suratida maqsad EX-32', q(`select status || ':' || coalesce("sourceSnapshot" ->> 'purposeArticle', '-') from public.cash_docs where id = '${a0}'`) === 'draft:EX-32', q(`select status, "sourceSnapshot" from public.cash_docs where id = '${a0}'`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${a0}')::text`);
  asUser(ids.R_KAS, `select public.kassa_doc_pay('${a0}')::text`);
  ok('Moliya menejeri tasdiqladi, kassir berdi: hisobdorda 100 000', q(`select status || ':' || trim_scale(app.kassa_acc_open('${T1}')) from public.cash_docs where id = '${a0}'`) === 'posted:100000');
  await k.ctx.close();

  // ---- 2) Buxgalter: avans hisoboti (ortiqcha sarf bilan) — tasdiqqa
  const a = await login(ACC); await a.kassaReady();
  await a.pg.click('#ks-adv'); await a.pg.waitForSelector('#av-p', { timeout: 15000 });
  await a.pg.selectOption('#av-p', T1);
  await a.pg.waitForFunction(() => /Yopilmagan avanslar/.test((document.querySelector('#av-pinfo') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
  const info = nb(await a.pg.$eval('#av-pinfo', e => e.textContent).catch(() => ''));
  const pre = await a.pg.$eval('[data-aart="0"]', e => e.value).catch(() => '');
  ok('hisobdor tanlanganda: yopilmagan avans (100 000, maqsadi — Kanselyariya) ko‘rinadi, birinchi qator statiyasi taklif qilindi (EX-32)', /100 000 so‘m \(Kanselyariya/.test(info) && pre === 'EX-32', [info, pre]);
  await a.pg.fill('[data-aamt="0"]', '130000'); await a.pg.fill('[data-anote="0"]', 'Chek 21, bugun');
  const over = nb(await a.pg.$eval('#av-over', e => e.textContent).catch(() => ''));
  ok('qoldiqdan katta summa — ortiqcha sarf ogohlantirishi (30 000, hisobdorga qarzimiz)', /qoldiqdan 30 000 so‘m katta/.test(over) && /ortiqcha sarf/.test(over), over);
  await a.pg.click('#av-save'); await a.modalGone().catch(() => {}); await a.pg.waitForTimeout(1000);
  const r1 = q(`select id from public.cash_docs where op = 'nc_adv_report' order by "createdAt" desc limit 1`);
  const lines = q(`select string_agg(l."lineNo" || ':' || l."articleId" || ':' || trim_scale(l.amount) || ':' || l.credit, ',' order by l."lineNo") from public.cash_doc_lines l where l."docId" = '${r1}'`);
  ok('saqlandi — tasdiq kutadi; qatorlar: 100 000 Kt 4230, 30 000 Kt 6970; tasdiqdan oldin ortiqcha sarf so‘raldi', q(`select status from public.cash_docs where id = '${r1}'`) === 'draft'
    && lines === '1:EX-32:100000:4230,2:EX-32:30000:6970' && a.dialogs.some(d => /Hisobot qoldiqdan 30 000 so‘m katta/.test(nb(d))), [lines, a.dialogs]);
  await a.kassaReady();
  const reqTxt = nb(await a.pg.$eval(`[data-advreq="${r1}"]`, e => e.innerText).catch(() => ''));
  ok('so‘rovlar jadvalida: qatorlar va «ortiqcha sarf 30 000»; kirituvchida «Tasdiqlash» yo‘q', /ortiqcha sarf 30 000 so‘m — hisobdorga qarzimiz/.test(reqTxt) && !(await a.pg.$(`[data-appr="${r1}"]`)), reqTxt);
  await a.pg.click('#ks-acc'); await a.pg.waitForSelector('#acc-list', { timeout: 15000 }).catch(() => {});
  const accRow = nb(await a.pg.$eval(`[data-accrow="${T1}"]`, e => e.innerText).catch(() => ''));
  ok('RP-07 ro‘yxati: hisobdor — qoldiq 100 000, «hisoboti tasdiq kutmoqda»', /hisoboti tasdiq kutmoqda/.test(accRow) && /100 000/.test(accRow), accRow);
  await a.ctx.close();

  // ---- 3) Direktor: «Tasdiqlash» → avans hisoboti
  const d = await login(ids.R_DIR);
  await d.tab('approvals');
  const kb = await d.pg.waitForSelector(`[data-kappr="${r1}"]`, { timeout: 20000 }).catch(() => null);
  const apTxt = nb(await d.pg.$eval('#view', e => e.innerText).catch(() => ''));
  ok('«Tasdiqlash»: Direktor navbatida avans hisoboti (ortiqcha sarf bilan)', !!kb && /ortiqcha sarf 30 000 so‘m — hisobdorga qarzimiz/.test(apTxt), apTxt.slice(0, 600));
  if (kb) { await kb.click(); await d.pg.waitForFunction(id => !document.querySelector(`[data-kappr="${id}"]`), r1, { timeout: 20000 }).catch(() => {}); }
  await d.pg.waitForFunction(() => [...document.querySelectorAll('iframe')].some(f => { try { return /6970/.test(f.contentDocument.body.innerText); } catch (e) { return false; } }), null, { timeout: 15000 }).catch(() => {});
  const pr = await d.printed();
  ok('tasdiqlandi — o‘tkazildi («А-» raqami), qarzimiz 30 000, hisobdor qoldig‘i 0; tasdiq oynasida ortiqcha sarf izohi',
    q(`select status || ':' || (no is not null) || ':' || trim_scale(app.kassa_acc_due('${T1}')) || ':' || trim_scale(app.kassa_acc_open('${T1}')) from public.cash_docs where id = '${r1}'`) === 'posted:true:30000:0'
      && d.dialogs.some(x => /Avans hisoboti tasdiqlansinmi/.test(x) && /Ortiqcha sarf 30 000 so‘m — hisobdorga qarzimiz/.test(nb(x))), d.dialogs);
  ok('АО-1 chop etish: ortiqcha sarf qatori (6970) va eslatmasi, kiritgan / tasdiqlagan', /Ортиқча сарф \(ҳисобдорга қарзимиз, 6970\): 30 000=00 сўм/.test(pr) && /Киритди: .+; тасдиқлади: .+\./.test(pr), pr.slice(0, 900));
  await d.kassaReady();
  await d.pg.waitForSelector('tr[data-ctl="accDue"]', { timeout: 15000 }).catch(() => {});
  const due = await d.pg.$eval('tr[data-ctl="accDue"]', e => e.dataset.level + '|' + e.innerText).catch(() => '');
  ok('nazorat ro‘yxati: «Hisobdorlarga qarzimiz (ortiqcha sarf)» — diqqat, 30 000', /^warn\|/.test(due) && /30 000/.test(nb(due)), due);
  await d.ctx.close();

  // ---- 4) Kassir: «Ortiqcha sarfni qoplash»
  const k2 = await login(ids.R_KAS); await k2.kassaReady();
  await k2.pg.click('#ks-out'); await k2.pg.waitForSelector('#kf-op', { timeout: 15000 });
  await k2.pg.selectOption('#kf-op', 'out_overspend'); await k2.pg.waitForSelector('#kf-pe', { timeout: 15000 });
  await k2.pg.selectOption('#kf-pe', T1);
  await k2.pg.waitForFunction(() => /qarzimiz/.test((document.querySelector('#kf-staff') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
  const stf = nb(await k2.pg.$eval('#kf-staff', e => e.textContent).catch(() => '')), am = nb(await k2.pg.$eval('#kf-amt', e => e.value).catch(() => ''));
  ok('«Ortiqcha sarfni qoplash»: hisobdorga qarzimiz 30 000 ko‘rinadi, summa to‘ldirildi', /Hisobdorga qarzimiz .*30 000 so‘m/.test(stf) && am === '30 000', [stf, am]);
  await k2.pg.fill('#kf-amt', '40000'); await k2.pg.fill('#kf-basis', 'Avans hisoboti bo‘yicha');
  await k2.pg.click('#kf-save'); await k2.pg.waitForTimeout(600);
  ok('qarzdan katta summa — rad, oyna ochiq', /hisobdorga qarzimizdan \(30 000 so‘m\) katta/.test(await k2.toasts()) && !!(await k2.pg.$('#kf-save')), await k2.toasts());
  await k2.pg.fill('#kf-amt', '30000'); await k2.pg.click('#kf-save'); await k2.modalGone().catch(() => {}); await k2.pg.waitForTimeout(800);
  const o1 = q(`select id from public.cash_docs where op = 'out_overspend' order by "createdAt" desc limit 1`);
  ok('so‘rov yozildi: 30 000, 2-ro‘yxat tasdig‘i kerak; qator Dt 6970 Kt 5010', q(`select status || ':' || amount::bigint || ':' || "needsList2" from public.cash_docs where id = '${o1}'`) === 'draft:30000:true'
    && q(`select debit || '>' || credit from public.cash_doc_lines where "docId" = '${o1}'`) === '6970>5010');
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${o1}')::text`);
  await k2.kassaReady();
  const pb = await k2.pg.waitForSelector(`[data-pay="${o1}"]`, { timeout: 15000 }).catch(() => null);
  if (pb) { await pb.click(); await k2.pg.waitForFunction(id => !document.querySelector(`[data-pay="${id}"]`), o1, { timeout: 15000 }).catch(() => {}); await k2.pg.waitForTimeout(600); }
  ok('kassir pulni berdi: order o‘tkazildi, qarzimiz 0', !!pb && q(`select status || ':' || trim_scale(app.kassa_acc_due('${T1}')) from public.cash_docs where id = '${o1}'`) === 'posted:0');
  await k2.ctx.close();

  // ---- 5) Moliya menejeri: RP-07 kartochkasi
  const m = await login(ids.R_MOL); await m.kassaReady();
  await m.pg.click('#ks-acc'); await m.pg.waitForSelector('#modal .modal-b', { timeout: 15000 });
  await m.pg.waitForFunction(() => !document.querySelector('#modal .loading'), null, { timeout: 15000 }).catch(() => {});
  const listTxt = nb(await m.pg.$eval('#modal', e => e.innerText).catch(() => ''));
  ok('RP-07: hisobdor endi ro‘yxatda yo‘q (qoldiq 0, qarz 0)', /Hisobdorlarda pul yo‘q/.test(listTxt) && !(await m.pg.$(`[data-acccard="${T1}"]`)), listTxt.slice(0, 300));
  await m.ctx.close();
  // kartochka — RPC orqali (ro'yxatda yo'q xodim ham ochiladi): sahifa tugmasi bilan tekshirish uchun yangi avans
  const a2 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_accountable","amount":20000,"partyType":"employee","partyId":"${T1}","basis":"Xojalik xaridi","purposeArticle":"EX-16","clientRef":"e26-adv-0002"}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${a2.id}')::text`); asUser(ids.R_KAS, `select public.kassa_doc_pay('${a2.id}')::text`);
  const m2 = await login(ids.R_MOL); await m2.kassaReady();
  await m2.pg.click('#ks-acc');
  const cb = await m2.pg.waitForSelector(`[data-acccard="${T1}"]`, { timeout: 15000 }).catch(() => null);
  if (cb) { await cb.click(); await m2.pg.waitForSelector('#acc-card', { timeout: 15000 }).catch(() => {}); }
  const card = nb(await m2.pg.$eval('#acc-card', e => e.innerText.replace(/\s+/g, ' ')).catch(() => ''));
  ok('kartochka: qoldiq 20 000, qarz 0; yopilmagan avans maqsadi bilan; hujjatlar — avanslar, avans hisoboti (−100 000 / +30 000), qoplash (−30 000)',
    !!cb && /Hisobot qilinmagan avans \(4230\) 20 000 so‘m/i.test(card) && /EX-16 · /.test(card) && /\+30 000 so‘m/.test(card) && /−30 000 so‘m/.test(card) && /−100 000 so‘m/.test(card), card.slice(0, 900));
  await m2.pg.click('#acc-print');
  await m2.pg.waitForFunction(() => [...document.querySelectorAll('iframe')].some(f => { try { return /КАРТОЧКА|KARTOCHKA/.test(f.contentDocument.body.innerText); } catch (e) { return false; } }), null, { timeout: 15000 }).catch(() => {});
  ok('kartochka chop etiladi (RP-07)', /ҲИСОБДОР ШАХС КАРТОЧКАСИ|HISOBDOR SHAXS KARTOCHKASI/.test(await m2.printed()), (await m2.printed()).slice(0, 300));
  await m2.ctx.close();

  // ---- 6) telefon
  const ph = await login(ids.R_MOL, { width: 390, height: 844 }); await ph.kassaReady();
  await ph.pg.click('#ks-acc').catch(() => {}); await ph.pg.waitForSelector('#acc-list', { timeout: 15000 }).catch(() => {});
  const ov2 = await ph.pg.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  await ph.pg.screenshot({ path: `${OUT}/k26-telefon.png` }).catch(() => {});
  ok('telefon (390 px): RP-07 oynasi ochildi, sahifa gorizontal siljimaydi', ov2 <= 1 && !!(await ph.pg.$('#acc-list')), ov2);
  await ph.ctx.close();

  ok('sahifa xatolari yo‘q', allErrs.length === 0, allErrs);
  await b.close();
  const f = res.filter(r => !r.ok).length;
  console.log(`JAMI (v2): ${res.length - f}/${res.length}`);
  process.exit(f ? 1 : 0);
})().catch(e => { console.error('XATO', e && e.stack || e); process.exit(2); });
