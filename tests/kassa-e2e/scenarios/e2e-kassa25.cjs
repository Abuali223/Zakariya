// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.5 — RP-09 statiya matritsasi brauzerda.
//   Tayyorgarlik (server funksiyalari va tizim nomidan): kassa ishga tushiriladi, ikki statiyali «Xarajat» KO-2 o'tkaziladi; «Buxgalteriya»ga
//   bank xarajati (statiya bilan); qo'shimcha xodim kartasi («HR menejer» — erkin yozilgan lavozim); o'tgan oy (o'quv yilining birinchi
//   oyida — joriy oy) vedomosti tasdiqlangan: o'qituvchi va uch xodim (Kassir, Qorovul, «HR menejer») va «Maosh» hisoblash qatori (vedomost
//   bilan teng).
//   1) Kassir — server rad etadi (42501), tugma yo'q.
//   2) Direktor: «Buxgalteriya» → «📊 RP-09 matritsa» → o'quv yili: jamlar server javobi bilan bir xil, nazorat belgilari (Jami = Σ hujjatlar,
//      kassa orderlari), statiya qatorlari; ko'rinish «Hisoblangan maosh» — EX-01 / EX-02 / EX-03; «Naqd» ko'rinishida — kassa xarajati;
//      maosh taqsimoti — tasdiqlangan oy «mos», lavozimlar statiyasi; XLSX — 4 varaq, jamlar server bilan bir xil; kalendar yili — davr.
//   3) Moliya menejeri va buxgalter (faqat ko'rish) — tugma bor, matritsa ochiladi, jami o'sha.
//   4) Telefon ekrani (390 px): oyna ochiladi, sahifa gorizontal siljimaydi. 5) Sahifa xatolari yo'q.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa25.cjs
const E = require('../lib/common.cjs'); const fs = require('fs'); const cp = require('child_process');
const XLSX = require(E.REPO + '/vendor/xlsx/xlsx.mini.min.js');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
// xato kutilgan chaqiruv: chiqish va xato matni birga (konsolga yozilmaydi)
const tryUser = (uid, sql) => { const r = cp.spawnSync('psql', ['-h', process.env.E2E_PGHOST, '-p', process.env.E2E_PGPORT, '-U', process.env.E2E_PGUSER, '-X', '-q', '-At', '-d', process.env.E2E_DB,
  '-c', `begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`], { encoding: 'utf8' }); return String(r.stdout || '') + String(r.stderr || ''); };
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const nb = s => String(s || '').replace(/[\u00a0\u202f]/g, ' ');
const fmt = v => { const n = Math.round(Number(v) * 100) / 100, a = Math.abs(n), w = Math.floor(a), t = Math.round((a - w) * 100);
  return (n < 0 ? '−' : '') + String(w).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + (t ? ',' + String(t).padStart(2, '0') : ''); };
const MONEY = ['cash', 'bank', 'card', 'online', 'offset', 'other'];
const sumArr = a => (a || []).reduce((s, x) => s + Number(x), 0);
const rowMoney = r => MONEY.reduce((s, k) => s + sumArr(r.m[k]), 0);
(async () => {
  const b = await E.launch();
  const d0 = q('select app.fin_today()'), CUR = d0.slice(0, 7);
  const SY = +d0.slice(5, 7) >= 9 ? +d0.slice(0, 4) : +d0.slice(0, 4) - 1;
  const PREV = (() => { const [y, m] = CUR.split('-').map(Number); return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, '0')}`; })();
  const PM = PREV >= `${SY}-09` ? PREV : CUR;   // vedomost oyi — joriy o'quv yili ichida
  const ACC = 'u_acc_e25';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter25@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status`);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${d0}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${d0}"}'::jsonb)`);
  q(`set session_replication_role = replica;
     insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_s25', 'supplier', 'Sinov Ofis MChJ', '', true) on conflict (id) do nothing;
     set session_replication_role = origin;`);
  const c = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_expense","amount":180000,"partyType":"counterparty","partyId":"cp_s25","basis":"Hisob-faktura № 0-25","note":"Sinov xarid","clientRef":"e25-p1-0001","lines":[{"articleId":"EX-32","amount":130000},{"articleId":"EX-16","amount":50000}]}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${c.id}')::text`);
  const p1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_doc_pay('${c.id}')::text`));
  const st = n => q(`select id from public.staff where "staffId" = 'IQX-00${n}'`), t1 = q(`select id from public.teachers where "teacherId" = 'IQT-001'`);
  const st1 = st(1), st2 = st(2);
  q(`set session_replication_role = replica;
     insert into public.expenses (id, date, month, category, amount, note, method, "articleId", kind) values
       ('exp_e25_bank', '${CUR}-01', '${CUR}', 'Ijara', 7000000, 'Sinov bank o''tkazmasi', 'bank', 'EX-10', 'expense');
     insert into public.staff (id, "staffId", name, position, salary, "order") values ('st_e25_hr', 'IQX-925', 'Sinov Xodim 925', 'HR menejer', '3600000', 925)
       on conflict (id) do nothing;
     insert into public.payroll_runs (id, status, "approvedBy", "approvedAt") values ('${PM}', 'approved', '${ids.R_DIR}', now())
       on conflict (id) do update set status = 'approved';
     delete from public.payroll_lines where "runId" = '${PM}';
     insert into public.payroll_lines (id, "runId", "personType", "personId", "refId", name, gross, deduction, "subBonus") values
       ('${PM}__teacher__IQT-001', '${PM}', 'teacher', 'IQT-001', '${t1}', 'Sinov', 5000000, 200000, 100000),
       ('${PM}__staff__IQX-001', '${PM}', 'staff', 'IQX-001', '${st1}', 'Sinov', 3000000, 0, 0),
       ('${PM}__staff__IQX-002', '${PM}', 'staff', 'IQX-002', '${st2}', 'Sinov', 4200000, 0, 0),
       ('${PM}__staff__IQX-925', '${PM}', 'staff', 'IQX-925', 'st_e25_hr', 'Sinov', 3600000, 0, 0);
     insert into public.expenses (id, date, month, category, amount, note, kind) values ('payroll__${PM}', '${PM}-01', '${PM}', 'Maosh', 15700000, 'Avtomatik: tasdiqlangan vedomost (4 xodim)', 'accrual')
       on conflict (id) do update set amount = excluded.amount;
     set session_replication_role = origin;`);
  const J = JSON.parse(asUser(ids.R_DIR, `select public.fin_matrix('school', ${SY})::text`));
  const jin = J.rows.filter(r => r.dir === 'in').reduce((s, r) => s + rowMoney(r), 0), jout = J.rows.filter(r => r.dir === 'out').reduce((s, r) => s + rowMoney(r), 0);
  const jsrc = J.sources.reduce((s, x) => s + Number(x.total), 0), jdocs = J.sources.reduce((s, x) => s + Number(x.docs), 0);
  const jrow = (dir, a) => J.rows.find(r => r.dir === dir && r.articleId === a);
  ok('tayyorgarlik: KO-2 o‘tkazildi; server matritsasida kassa, to‘lovlar, xarajatlar, maosh taqsimoti; Jami = Σ hujjatlar',
    p1.status === 'posted' && !!st1 && !!st2 && ['kassa', 'payments', 'expenses', 'payroll'].every(k => J.sources.some(s => s.key === k))
      && Math.abs(J.rows.reduce((s, r) => s + Number(r.money) + Number(r.accountable) + Number(r.accrual), 0) - jsrc) < 0.01
      && Number(J.kassaHeader.out) === 180000 && jrow('out', 'EX-01') && Number(jrow('out', 'EX-01').accrual) === 4900000
      && Number(jrow('out', 'EX-03').accrual) === 6600000 && Number(jrow('out', 'EX-02').accrual) === 4200000, [p1.status, J.sources, J.kassaHeader]);
  const kr = tryUser(ids.R_KAS, `select public.fin_matrix('school', ${SY})::text`);
  ok('kassir — server rad etadi (42501)', /Ruxsat yo'q: RP-09/.test(kr) && !/"ok"/.test(kr), kr.slice(0, 300));

  async function login(uid, vp) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 }, acceptDownloads: true });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage();
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => d.accept().catch(() => {}));
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);
    const hasTab = async k => !!(await pg.$(`#tabs button[data-tab="${k}"]`));
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const acc = async () => { await tab('accounting'); await pg.waitForFunction(() => document.querySelector('#ac-body') && !document.querySelector('#ac-body .loading'), null, { timeout: 30000 }).catch(() => {}); await pg.waitForTimeout(500); };
    const open = async () => { await pg.click('#ac-rp09'); await pg.waitForSelector('#mx-load', { timeout: 15000 });
      await pg.waitForFunction(() => document.querySelector('#mx-body') && document.querySelector('#mx-sum'), null, { timeout: 30000 }); };
    const sumTxt = async () => nb(await pg.$eval('#mx-sum', e => e.innerText.replace(/\s+/g, ' ')));
    const tbl = async id => pg.evaluate(i => [...document.querySelectorAll(`#${i} tr`)].map(tr => [...tr.children].map(td => td.innerText.replace(/\s+/g, ' ').trim())), id);
    return { ctx, pg, hasTab, tab, acc, open, sumTxt, tbl };
  }

  // ---- 1) kassir
  const k = await login(ids.R_KAS);
  const kAcc = await k.hasTab('accounting');
  let kBtn = false; if (kAcc) { await k.acc(); kBtn = !!(await k.pg.$('#ac-rp09')); }
  ok('kassir: «📊 RP-09» tugmasi yo‘q', !kBtn, [kAcc, kBtn]);
  await k.ctx.close();

  // ---- 2) Direktor
  const d = await login(ids.R_DIR);
  await d.acc();
  ok('Direktor: «Buxgalteriya»da «📊 RP-09 matritsa» tugmasi', /RP-09/.test(await d.pg.$eval('#ac-rp09', e => e.textContent).catch(() => '')));
  await d.open();
  const s1 = await d.sumTxt();
  ok('o‘quv yili: davr, kirim / chiqim jami server bilan bir xil; nazorat — «Jami = Σ hujjatlar» va kassa orderlari ✓',
    s1.includes(`${SY}/${SY + 1} o‘quv yili`) && s1.includes(`kirim ${fmt(jin)}`) && s1.includes(`chiqim ${fmt(jout)}`)
      && s1.includes(`✓ Jami = Σ hujjatlar (${jdocs} ta)`) && s1.includes('✓ kassa orderlari'), [s1, jin, jout, jdocs]);
  await d.pg.screenshot({ path: `${OUT}/k25-matritsa.png` }).catch(() => {});
  const t1r = await d.tbl('mx-tbl');
  const findRow = (rows, re) => rows.find(r => re.test(r[0] || ''));
  const totIn = findRow(t1r, /^Jami kirim/), totOut = findRow(t1r, /^Jami chiqim/), ex32 = findRow(t1r, /^EX-32 /), in01 = findRow(t1r, /^IN-01 /);
  ok('jadval: «Jami kirim» / «Jami chiqim» oxirgi ustuni server jamiga teng; IN-01 va EX-32 qatorlari; 12 oy + jami ustuni',
    totIn && totOut && totIn.at(-1) === fmt(jin) && totOut.at(-1) === fmt(jout) && !!in01 && !!ex32 && t1r[0].length === 14
      && ex32.at(-1) === fmt(rowMoney(jrow('out', 'EX-32'))), [totIn, totOut, ex32 && ex32.at(-1), t1r[0]]);
  await d.pg.selectOption('#mx-view', 'accrual'); await d.pg.waitForTimeout(300);
  const t2 = await d.tbl('mx-tbl');
  ok('ko‘rinish «Hisoblangan maosh»: EX-01 4 900 000, EX-02 4 200 000 (Qorovul), EX-03 6 600 000 (Kassir + «HR menejer»)',
    (findRow(t2, /^EX-01 /) || []).at(-1) === '4 900 000' && (findRow(t2, /^EX-02 /) || []).at(-1) === '4 200 000' && (findRow(t2, /^EX-03 /) || []).at(-1) === '6 600 000'
      && !findRow(t2, /^IN-01 /), t2.map(r => [r[0], r.at(-1)]));
  await d.pg.selectOption('#mx-view', 'cash'); await d.pg.waitForTimeout(300);
  const t3 = await d.tbl('mx-tbl');
  ok('ko‘rinish «Naqd»: kassa xarajati EX-32 130 000, EX-16 50 000 (bank xarajati — yo‘q)',
    (findRow(t3, /^EX-32 /) || []).at(-1) === fmt(sumArr(jrow('out', 'EX-32').m.cash)) && (findRow(t3, /^EX-16 /) || []).at(-1) === fmt(sumArr(jrow('out', 'EX-16').m.cash))
      && !findRow(t3, /^EX-10 /), t3.map(r => [r[0], r.at(-1)]));
  const pay = await d.tbl('mx-pay'), pos = await d.tbl('mx-pos');
  const pmLbl = ['Yan', 'Fev', 'Mar', 'Apr', 'May', 'Iyun', 'Iyul', 'Avg', 'Sen', 'Okt', 'Noy', 'Dek'][+PM.slice(5, 7) - 1] + ' ' + PM.slice(0, 4);
  ok('maosh taqsimoti: tasdiqlangan oy — taqsimot = «Maosh» qatori (✓ mos); lavozimlar statiyasi (o‘qituvchilar — EX-01, «HR menejer» — EX-03)',
    pay.some(r => r[0] === pmLbl && r[1] === 'tasdiqlangan' && r[2] === '15 700 000' && r[3] === '15 700 000' && /mos/.test(r[4]))
      && pos.some(r => r[0] === 'O‘qituvchilar ro‘yxati' && r[1] === 'EX-01' && r[3] === '4 900 000')
      && pos.some(r => r[0] === 'HR menejer' && r[1] === 'EX-03') && pos.some(r => r[0] === 'Qorovul' && r[1] === 'EX-02'), [pmLbl, pay, pos]);
  const src = await d.tbl('mx-src');
  ok('nazorat jadvali: manbalar jami = matritsa jami (server)', src.some(r => r[0] === 'Manbalar jami' && r[2] === fmt(jsrc)) && src.some(r => /^Matritsa jami/.test(r[0]) && r[2] === fmt(jsrc)), src);
  // XLSX
  const [dl] = await Promise.all([d.pg.waitForEvent('download', { timeout: 15000 }), d.pg.click('#mx-xlsx')]);
  const nm = dl.suggestedFilename(), wb = XLSX.read(fs.readFileSync(await dl.path()), { type: 'buffer' });
  const sh = n => XLSX.utils.sheet_to_json(wb.Sheets[n], { header: 1, raw: true, defval: '' });
  const m1 = sh('Matritsa'), m3 = sh('Maosh taqsimoti'), m4 = sh('Nazorat');
  const xr = (rows, a, b2) => rows.find(r => r[0] === a && (b2 === undefined || r[1] === b2));
  ok('XLSX: fayl nomi, 4 varaq; «JAMI KIRIM / CHIQIM» server bilan bir xil; maosh oyi; nazorat «mos»',
    nm === `RP-09_oquv-${SY}-${SY + 1}.xlsx` && wb.SheetNames.join('|') === 'Matritsa|Usullar|Maosh taqsimoti|Nazorat'
      && Math.abs(Number(xr(m1, 'JAMI KIRIM').at(-1)) - jin) < 0.01 && Math.abs(Number(xr(m1, 'JAMI CHIQIM').at(-1)) - jout) < 0.01
      && !!xr(m3, pmLbl, 'tasdiqlangan') && xr(m4, 'Moslik')[2] === 'mos' && xr(m4, 'Kassa moslik')[2] === 'mos', [nm, wb.SheetNames, xr(m1, 'JAMI KIRIM'), xr(m4, 'Moslik')]);
  // kalendar yili
  await d.pg.selectOption('#mx-kind', 'calendar'); await d.pg.click('#mx-load');
  await d.pg.waitForFunction(y => /kalendar yili/.test((document.querySelector('#mx-sum') || {}).innerText || '') && (document.querySelector('#mx-sum').innerText || '').includes(String(y)), +d0.slice(0, 4), { timeout: 20000 }).catch(() => {});
  const s2 = await d.sumTxt();
  ok('kalendar yili: davr yorlig‘i, nazorat ✓', s2.includes(`${d0.slice(0, 4)} kalendar yili (01.01.${d0.slice(0, 4)} – 31.12.${d0.slice(0, 4)})`) && s2.includes('✓ Jami = Σ hujjatlar'), s2);
  await d.ctx.close();

  // ---- 3) Moliya menejeri va buxgalter
  const m = await login(ids.R_MOL); await m.acc(); await m.open();
  const sm = await m.sumTxt();
  const a = await login(ACC); await a.acc();
  const aRO = !(await a.pg.$('#ac-add')); await a.open();
  const sa = await a.sumTxt();
  ok('Moliya menejeri va buxgalter (faqat ko‘rish): oyna ochiladi, jami — o‘sha', sm.includes(`chiqim ${fmt(jout)}`) && aRO && sa.includes(`chiqim ${fmt(jout)}`), [sm.slice(0, 200), aRO, sa.slice(0, 200)]);
  await m.ctx.close(); await a.ctx.close();

  // ---- 4) telefon
  const ph = await login(ids.R_DIR, { width: 390, height: 844 });
  await ph.acc(); await ph.open();
  const ov = await ph.pg.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  await ph.pg.screenshot({ path: `${OUT}/k25-telefon.png` }).catch(() => {});
  ok('telefon (390 px): oyna ochildi, sahifa gorizontal siljimaydi (jadval o‘z oynasida)', ov <= 1 && !!(await ph.pg.$('#mx-tbl')), ov);
  await ph.ctx.close();

  ok('sahifa xatolari yo‘q', allErrs.length === 0, allErrs);
  await b.close();
  const f = res.filter(r => !r.ok).length;
  console.log(`JAMI (v2): ${res.length - f}/${res.length}`);
  process.exit(f ? 1 : 0);
})().catch(e => { console.error('XATO', e && e.stack || e); process.exit(2); });
