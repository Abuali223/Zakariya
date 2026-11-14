// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): eslatmalar (muddati o'tgan avans — F1.24) va RP-22 haftalik KPI (F1.25).
//   Moliya menejeri / Direktor: «KPI» oynasi (joriy hafta, ko'rsatkichlar); avans hisoboti muddati o'tgach (sinov soati bilan) — sahifada
//   eslatma va nazorat ro'yxatida; kassirda «KPI» yo'q; telefonda oyna sig'adi.  Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa12.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const sqlErr = (uid, sql) => cp.spawnSync(E.PSQL[0], [...E.PSQL.slice(1), '-q', '-At', '-d', E.DB, '-c',
  `begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`], { encoding: 'utf8' }).stderr;
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
    const pg = await ctx.newPage();
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => d.accept().catch(() => {}));
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const body = async () => (await pg.textContent('#ks-body')).replace(/\s+/g, ' ');
    return { ctx, pg, tab, kassaReady, body };
  }
  // tayyorgarlik: ishga tushirish; hisobdorga avans (bugun); xarajat EX-49
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  q(`insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_e12', 'supplier', 'Sinov Taminot MChJ', '', true) on conflict (id) do nothing`);
  const stId = q(`select s.id from public.staff s where coalesce(s."staffId", '') <> '' order by s.id limit 1`);
  const c1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_accountable","amount":40000,"partyType":"employee","partyId":"staff:${stId}","basis":"Xo‘jalik xaridi","clientRef":"e12-c1-0001"}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${c1.id}')::text`); asUser(ids.R_KAS, `select public.kassa_doc_pay('${c1.id}')::text`);
  const c2 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_expense","amount":10000,"partyType":"counterparty","partyId":"cp_e12","basis":"Hisob-faktura № 12","clientRef":"e12-c2-0001","lines":[{"articleId":"EX-49","amount":10000,"note":"Tasniflanmagan xarid (sinov)"}]}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${c2.id}')::text`); asUser(ids.R_KAS, `select public.kassa_doc_pay('${c2.id}')::text`);
  ok('tayyorgarlik: avans 40 000 va EX-49 xarajat 10 000 o‘tkazildi', q(`select string_agg(op || ':' || status, ',' order by no) from public.cash_docs where form = 'KO2'`) === 'out_accountable:posted,out_expense:posted',
    q(`select string_agg(op || ':' || status, ',') from public.cash_docs`));
  // ---------------- 1) Moliya menejeri: KPI oynasi; hali eslatma yo'q
  {
    const m = await login(ids.R_MOL);
    await m.kassaReady();
    ok('avans muddatida: eslatma yo‘q', !/Avans hisoboti muddati o‘tgan/.test(await m.body()));
    ok('«KPI» tugmasi bor', !!(await m.pg.$('#ks-kpi')));
    await m.pg.click('#ks-kpi'); await m.pg.waitForSelector('#kk-tbl', { timeout: 15000 });
    const rows = await m.pg.$$eval('#kk-tbl tbody tr', xs => xs.map(x => x.innerText.replace(/\s+/g, ' ').trim()));
    ok('KPI: 8 hafta, birinchisi — joriy hafta; ochiq kun 1 ta, EX-49 ulushi 100% (ogohlantirish)', rows.length === 8 && /joriy hafta/.test(rows[0]) && /Kassa kunlari: 1 ta \(yopilgan 0\)/.test(rows[0])
      && /«Boshqa xarajatlar» \(EX-49\) ulushi: 100% \(10 000 so‘m \/ 10 000 so‘m; maqsad ≤ 2%\)/.test(rows[0]) && /Kassa kunlari: yo‘q/.test(rows[1]), rows.slice(0, 2));
    const warnCol = await m.pg.$$eval('#kk-tbl tbody tr:first-child div.small', xs => xs.filter(x => /EX-49/.test(x.textContent)).map(x => getComputedStyle(x).color));
    ok('EX-49 > 2% — ogohlantirish rangi', warnCol.length === 1 && warnCol[0] === 'rgb(181, 71, 8)', warnCol);
    await m.ctx.close();
  }
  // ---------------- 2) sinov soati: 7 kun keyin — avans hisoboti muddati o'tgan (3 ish kunidan ortiq)
  try {
    q(`insert into app.fin_clock (id, t) values (1, now() + interval '7 days') on conflict (id) do update set t = excluded.t`);
    const st = JSON.parse(asUser(ids.R_MOL, `select public.kassa_state('main')::text`));
    ok('server: 7 kundan keyin muddati o‘tgan avans — 1 ta, 40 000', Number(st.accOverdue && st.accOverdue.n) === 1 && Number(st.accOverdue.sum) === 40000, st.accOverdue);
    const d = await login(ids.R_DIR);
    await d.kassaReady();
    const t = await d.body();
    ok('Direktor sahifasida eslatma: «Avans hisoboti muddati o‘tgan hisobdorlar: 1 ta (40 000 so‘m)»', /Avans hisoboti muddati o‘tgan hisobdorlar: 1 ta \(40 000 so‘m\)/.test(t), t.slice(0, 600));
    const ctl = await d.pg.$eval('#ks-body tr[data-ctl="accountable"]', e => e.getAttribute('data-level') + ' ' + e.innerText.replace(/\s+/g, ' ')).catch(() => '');
    ok('nazorat ro‘yxatida hisobdor — muddati o‘tgan (diqqat)', /^warn /.test(ctl) && /muddati o‘tgan/.test(ctl), ctl);
    const daily = q(`select (app.kassa_daily(app.fin_today()) -> 'control' -> 'accOverdue')::text`);
    ok('Telegram nazorati: accOverdue 1 ta', /"n": 1/.test(daily) && /"sum": 40000/.test(daily), daily);
    await d.ctx.close();
  } finally { q(`delete from app.fin_clock where id = 1`); }
  // ---------------- 3) Kassir: «KPI» yo'q, eslatma yo'q; server rad; telefonda Direktor oynasi sig'adi
  {
    const k = await login(ids.R_KAS);
    await k.kassaReady();
    ok('kassirda «KPI» tugmasi yo‘q', !(await k.pg.$('#ks-kpi')));
    await k.ctx.close();
    ok('server: kassir KPI ni ololmaydi (42501)', /Ruxsat yo.q: haftalik ko.rsatkichlar/.test(sqlErr(ids.R_KAS, `select public.kassa_kpi('main', 4)`)));
    const p = await login(ids.R_DIR, { width: 390, height: 844 });
    await p.kassaReady();
    await p.pg.click('#ks-kpi'); await p.pg.waitForSelector('#kk-tbl', { timeout: 15000 });
    const mw = await p.pg.evaluate(() => { const m = document.querySelector('#modal'); return m.scrollWidth - m.clientWidth; });
    const tw = await p.pg.evaluate(() => { const w = document.querySelector('#kk-tbl').parentElement; return w.scrollWidth - w.clientWidth; });
    const sw = await p.pg.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    ok('telefon: KPI oynasi, jadval va sahifa gorizontal siljimaydi', mw <= 1 && tw <= 1 && sw <= 1, [mw, tw, sw]);
    await p.pg.screenshot({ path: `${OUT}/kpi-${UI}-390.png` });
    await p.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { try { q(`delete from app.fin_clock where id = 1`); } catch (_) {} console.error('XATO', e); process.exit(1); });
