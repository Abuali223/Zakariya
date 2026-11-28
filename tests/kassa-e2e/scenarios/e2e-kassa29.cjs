// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.3 (reliz 27) — noyabr–yanvar eski
//   xarajatlariga statiya: buxgalter tasnifi va imzosi brauzerda.
//   Tayyorgarlik (tizim nomidan): «Buxgalteriya»ga eski shakldagi xarajatlar (toifa bilan, hujjatsiz) — 2026-yil noyabr («Boshqa»,
//   «Kommunal», «Kanselyariya») va dekabr («Ijara»); urug'dagi joriy oy yozuvlari (toifasi kichik harfda — statiyasiz) ham shu ro'yxatda.
//   1) Kassir: tugma yo'q, server rad etadi.
//   2) Buxgalter: «Buxgalteriya» → «🏷 Statiya tasnifi» → noyabr: yozuvlar «≈ taxminiy» / «statiyasiz», imzo tugmasi o'chiq;
//      «Kommunal» → EX-13 (saqlandi — yozuvda va jurnalda); «Boshqa» (EX-49) izohsiz tasdiqlanmaydi (sahifa to'xtatadi), izoh bilan —
//      tasdiqlandi; statiyasiz yozuvlarga statiya; qolganini belgilab tasdiqlash; hammasi tasdiqlangach «✍ Imzolash» → «imzolangan»;
//      dekabr tugmasi — boshqa oy ro'yxati.
//   3) Moliya menejeri: imzo tugmasi yo'q; bitta yozuv statiyasini o'zgartiradi — oy holati «imzo eskirgan».
//   4) Direktor: «📊 RP-09» — tasdiqlangan statiya qatorida «≈ toifadan» belgisi yo'q, xulosada noyabr holati.
//   5) Telefon (390 px): oyna, sahifa gorizontal siljimaydi. 6) Sahifa xatolari yo'q; detektor jurnali bo'sh.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa29.cjs
const E = require('../lib/common.cjs'); const fs = require('fs'); const cp = require('child_process');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const tryUser = (uid, sql) => { const r = cp.spawnSync('psql', ['-h', process.env.E2E_PGHOST, '-p', process.env.E2E_PGPORT, '-U', process.env.E2E_PGUSER, '-X', '-q', '-At', '-d', process.env.E2E_DB,
  '-c', `begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`], { encoding: 'utf8' }); return String(r.stdout || '') + String(r.stderr || ''); };
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const nb = s => String(s || '').replace(/[\u00a0\u202f]/g, ' ');
const M = '2026-11', MD = '2026-12';
(async () => {
  const b = await E.launch();
  const ACC = 'u_acc_e29';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter29@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]')
     on conflict (id) do update set role = excluded.role, status = excluded.status, name = excluded.name`);
  // eski shakldagi xarajatlar (psql — triggerlar bilan: statiya toifadan qo'yiladi)
  q(`insert into public.expenses (id, date, month, category, amount, note) values
       ('e29-n1', '${M}-03', '${M}', 'Boshqa', 150000, 'Sinov mayda xarid'), ('e29-n2', '${M}-06', '${M}', 'Kommunal', 420000, 'Sinov kommunal'),
       ('e29-n3', '${M}-09', '${M}', 'Kanselyariya', 60000, 'Sinov qog‘oz'), ('e29-d1', '${MD}-02', '${MD}', 'Ijara', 900000, 'Sinov ijara')`);
  const L = JSON.parse(asUser(ACC, `select public.fin_exp_class_list('${M}')::text`));
  const ids0 = L.rows.map(r => r.id), bare = L.rows.filter(r => !r.articleId).map(r => r.id);
  const art = id => q(`select coalesce("articleId", '-') from public.expenses where id = '${id}'`);
  const nlog = () => q('select count(*) from public.fin_direct_log');
  ok('tayyorgarlik: noyabr ro‘yxatida e29 yozuvlari (toifadan: EX-49, EX-11, EX-32), hech biri tasdiqlanmagan; dekabr yozuvi alohida',
    ['e29-n1', 'e29-n2', 'e29-n3'].every(i => ids0.includes(i)) && !ids0.includes('e29-d1') && L.rows.every(r => !r.confirmed)
      && art('e29-n1') === 'EX-49' && art('e29-n2') === 'EX-11' && art('e29-n3') === 'EX-32' && nlog() === '0', [ids0, bare]);
  const kr = tryUser(ids.R_KAS, `select public.fin_exp_class_list('${M}')::text`);
  ok('kassir — server rad etadi (42501)', /Ruxsat yo'q: statiya tasnifini/.test(kr) && !/"ok"/.test(kr), kr.slice(0, 200));

  async function login(uid, vp) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage();
    const dialogs = [], toasts = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);
    const hasTab = async k => !!(await pg.$(`#tabs button[data-tab="${k}"]`));
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const acc = async () => { await tab('accounting'); await pg.waitForFunction(() => document.querySelector('#ac-body') && !document.querySelector('#ac-body .loading'), null, { timeout: 30000 }).catch(() => {}); await pg.waitForTimeout(500); };
    // oyna: kerakli oy tugmasi bosilgach ro'yxat yuklanguncha kutadi
    const month = async m => {
      await pg.waitForSelector(`#cl-months [data-cm="${m}"]`, { timeout: 15000 });
      const on = await pg.$eval(`#cl-months [data-cm="${m}"]`, e => e.classList.contains('gold'));
      if (!on) await pg.click(`#cl-months [data-cm="${m}"]`);
      await pg.waitForFunction(mm => { const b2 = document.querySelector(`#cl-months [data-cm="${mm}"]`); return b2 && b2.classList.contains('gold') && document.querySelector('#cl-sum'); }, m, { timeout: 15000 });
      await pg.waitForTimeout(300);
    };
    const open = async () => { await pg.click('#ac-cls'); await pg.waitForSelector('#cl-months [data-cm]', { timeout: 15000 }); await month(M); };
    const rowSt = async id => nb(await pg.$eval(`#cl-tbl tr[data-cl="${id}"] td[data-label="Holat"]`, e => e.innerText).catch(() => ''));
    const sumTxt = async () => nb(await pg.$eval('#cl-sum', e => e.innerText.replace(/\s+/g, ' ')).catch(() => ''));
    const toastTxt = async () => nb(await pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | ')).catch(() => ''));
    const save = async () => { await pg.click('#cl-save'); await pg.waitForTimeout(1200); await pg.waitForFunction(() => document.querySelector('#cl-sum'), null, { timeout: 15000 }).catch(() => {}); };
    return { ctx, pg, dialogs, toasts, hasTab, tab, acc, open, month, rowSt, sumTxt, toastTxt, save };
  }

  // ---- 1) kassir
  const k = await login(ids.R_KAS);
  const kAcc = await k.hasTab('accounting');
  let kBtn = false; if (kAcc) { await k.acc(); kBtn = !!(await k.pg.$('#ac-cls')); }
  ok('kassir: «🏷 Statiya tasnifi» tugmasi yo‘q', !kBtn, [kAcc, kBtn]);
  await k.ctx.close();

  // ---- 2) buxgalter
  const a = await login(ACC);
  await a.acc();
  ok('buxgalter: «Buxgalteriya»da «🏷 Statiya tasnifi» tugmasi', /Statiya tasnifi/.test(await a.pg.$eval('#ac-cls', e => e.textContent).catch(() => '')));
  await a.open();
  const s0 = await a.sumTxt(), st1 = await a.rowSt('e29-n1');
  const signDis0 = await a.pg.$eval('#cl-sign', e => e.style.display !== 'none' && e.disabled).catch(() => null);
  const mbtn = nb(await a.pg.$eval('#cl-months', e => e.innerText.replace(/\s+/g, ' ')));
  ok('noyabr: oylar tugmalari (Noyabr 2026 · 0/N, Dekabr 2026, Yanvar 2027), xulosa «qisman», yozuv — «≈ taxminiy», imzo tugmasi bor, lekin o‘chiq',
    /Noyabr 2026 · 0\/\d+/.test(mbtn) && /Dekabr 2026/.test(mbtn) && /Yanvar 2027/.test(mbtn) && /Noyabr 2026/.test(s0) && /qisman/.test(s0)
      && /taxminiy/.test(st1) && signDis0 === true, [mbtn, s0, st1, signDis0]);
  await a.pg.screenshot({ path: `${OUT}/k29-tasnif.png` }).catch(() => {});
  // «Kommunal» → EX-13
  await a.pg.selectOption('#cl-tbl select[data-art="e29-n2"]', 'EX-13'); await a.save();
  ok('«Kommunal» → EX-13 saqlandi: yozuvda yangi statiya, jurnalda EX-11 → EX-13 (buxgalter), qatorda «✓ tasdiqlangan»',
    art('e29-n2') === 'EX-13' && q(`select "oldArticle" || '>' || "newArticle" || ':' || "byRole" from public.fin_exp_class where "expenseId" = 'e29-n2' order by id desc limit 1`) === 'EX-11>EX-13:accountant'
      && /tasdiqlangan/.test(await a.rowSt('e29-n2')), [art('e29-n2'), await a.rowSt('e29-n2')]);
  // «Boshqa» (EX-49): izohsiz tasdiqlanmaydi
  await a.pg.check('#cl-tbl input[data-ck="e29-n1"]');
  const nj0 = q(`select count(*) from public.fin_exp_class where "expenseId" = 'e29-n1'`);
  await a.pg.click('#cl-save'); await a.pg.waitForTimeout(800);
  const t1 = await a.toastTxt();
  ok('«Boshqa» (EX-49) izohsiz — sahifa to‘xtatadi (izoh majburiy), serverga yuborilmaydi', /izohi majburiy/.test(t1) && q(`select count(*) from public.fin_exp_class where "expenseId" = 'e29-n1'`) === nj0, [t1, nj0]);
  await a.pg.fill('#cl-tbl input[data-note="e29-n1"]', 'Mayda xo‘jalik xaridlari'); await a.save();
  ok('izoh bilan — «Boshqa» tasdiqlandi (statiya o‘zgarmadi, jurnalda izoh)',
    art('e29-n1') === 'EX-49' && q(`select note from public.fin_exp_class where "expenseId" = 'e29-n1' order by id desc limit 1`) === 'Mayda xo‘jalik xaridlari'
      && /tasdiqlangan/.test(await a.rowSt('e29-n1')), await a.rowSt('e29-n1'));
  // statiyasiz yozuvlar (urug') — statiya tanlanadi; qolganlari belgilab tasdiqlanadi
  for (const id of bare) await a.pg.selectOption(`#cl-tbl select[data-art="${id}"]`, 'EX-16');
  await a.pg.check('#cl-all');
  await a.save();
  const L2 = JSON.parse(asUser(ACC, `select public.fin_exp_class_list('${M}')::text`));
  const sum2 = await a.sumTxt(), mbtn2 = nb(await a.pg.$eval('#cl-months', e => e.innerText.replace(/\s+/g, ' ')));
  const signEn = await a.pg.$eval('#cl-sign', e => !e.disabled).catch(() => false);
  ok('statiyasiz yozuvlarga EX-16, qolganlari belgilab tasdiqlandi: oy — hammasi tasdiqlangan, «imzo kutilmoqda», imzo tugmasi faol',
    L2.rows.every(r => r.confirmed) && bare.every(id => art(id) === 'EX-16') && art('e29-n3') === 'EX-32' && /imzosi kutilmoqda/.test(sum2)
      && new RegExp(`Noyabr 2026 · ${L2.rows.length}/${L2.rows.length}`).test(mbtn2) && signEn, [L2.rows.map(r => [r.id, r.articleId, r.confirmed]), sum2, mbtn2, signEn]);
  // imzo
  a.dialogs.length = 0;
  await a.pg.click('#cl-sign'); await a.pg.waitForTimeout(1200);
  await a.pg.waitForFunction(() => /imzolangan/.test((document.querySelector('#cl-sum') || {}).innerText || ''), null, { timeout: 15000 }).catch(() => {});
  const sum3 = await a.sumTxt();
  ok('«✍ Imzolash»: tasdiq oynasi (yozuvlar soni va jami), oy holati «imzolangan — Sinov Buxgalter», bazada imzo yozuvi',
    a.dialogs.some(x => /statiya tasnifini imzolaysizmi/.test(x) && x.includes(`${L2.rows.length} ta eski xarajat`)) && /imzolangan — Sinov Buxgalter/.test(sum3)
      && q(`select count(*) from public.fin_exp_class_sign where month = '${M}' and "byUid" = '${ACC}'`) === '1', [a.dialogs, sum3]);
  // dekabr
  await a.month(MD);
  const dRows = await a.pg.$$eval('#cl-tbl tr[data-cl]', xs => xs.map(x => x.dataset.cl));
  ok('dekabr tugmasi: o‘sha oy ro‘yxati (e29-d1, «≈ taxminiy»)', dRows.includes('e29-d1') && !dRows.includes('e29-n1') && /taxminiy/.test(await a.rowSt('e29-d1')), dRows);
  await a.ctx.close();

  // ---- 3) Moliya menejeri
  const m = await login(ids.R_MOL);
  await m.acc(); await m.open();
  const mSign = await m.pg.$eval('#cl-sign', e => e.style.display).catch(() => 'yoq');
  const ms0 = await m.sumTxt();
  await m.pg.selectOption('#cl-tbl select[data-art="e29-n3"]', 'EX-26'); await m.save();
  const ms1 = await m.sumTxt();
  ok('Moliya menejeri: imzo tugmasi yo‘q; oy «imzolangan» edi; statiyani o‘zgartirdi (EX-32 → EX-26) — oy holati «imzo eskirgan»',
    mSign === 'none' && /imzolangan/.test(ms0) && art('e29-n3') === 'EX-26' && /imzo eskirgan/.test(ms1), [mSign, ms0, ms1]);
  await m.ctx.close();

  // ---- 4) Direktor: RP-09
  const d = await login(ids.R_DIR);
  await d.acc();
  await d.pg.click('#ac-rp09'); await d.pg.waitForSelector('#mx-load', { timeout: 15000 });
  await d.pg.waitForFunction(() => document.querySelector('#mx-sum'), null, { timeout: 30000 });
  const mxs = nb(await d.pg.$eval('#mx-sum', e => e.innerText.replace(/\s+/g, ' ')));
  const ex13 = await d.pg.evaluate(() => { const tr = [...document.querySelectorAll('#mx-tbl tr')].find(t => /^EX-13 /.test((t.children[0] || {}).innerText || '')); return tr ? tr.children[0].innerText : null; });
  ok('RP-09: tasdiqlangan EX-13 qatorida «≈ toifadan» yo‘q; xulosada «Eski xarajatlar statiyasi» — noyabr: imzo eskirgan',
    ex13 && !/toifadan/.test(ex13) && /Eski xarajatlar statiyasi \(noyabr–yanvar\): Noy 2026 — imzo eskirgan/.test(mxs), [ex13, mxs.slice(0, 600)]);
  await d.ctx.close();

  // ---- 5) telefon
  const ph = await login(ACC, { width: 390, height: 844 });
  await ph.acc(); await ph.open();
  const ov = await ph.pg.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  await ph.pg.screenshot({ path: `${OUT}/k29-telefon.png` }).catch(() => {});
  ok('telefon (390 px): oyna ochildi, sahifa gorizontal siljimaydi', ov <= 1 && !!(await ph.pg.$('#cl-tbl')), ov);
  await ph.ctx.close();

  ok('sahifa xatolari yo‘q', allErrs.length === 0, allErrs);
  ok('oxirida detektor jurnali bo‘sh — tasnif pul jadvaliga funksiya orqali yozdi', nlog() === '0', q(`select string_agg(tbl || ':' || op || ':' || row_id, ', ') from public.fin_direct_log`));
  await b.close();
  const f = res.filter(r => !r.ok).length;
  console.log(`JAMI (v2): ${res.length - f}/${res.length}`);
  process.exit(f ? 1 : 0);
})().catch(e => { console.error('XATO', e && e.stack || e); process.exit(2); });
