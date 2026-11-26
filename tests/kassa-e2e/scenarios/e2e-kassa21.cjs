// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.13 — qayta tasnif dalolatnomasi brauzerda.
//   Tayyorgarlik (server funksiyalari bilan): kassa ishga tushiriladi, ikki statiyali «Xarajat» KO-2 o'tkaziladi, kun yopiladi, test soati
//   ertangi kunga suriladi. Buxgalter: KO-3 jurnalida orderda «QT» tugmasi → tuzatish oynasi (o'zgarishsiz va sababsiz — yuborilmaydi) →
//   1-qator statiyasi (asosiy vosita), oluvchi va asos bilan so'rov → oynada «Direktor qarorini kutmoqda», yangi so'rov yo'q. Direktor:
//   ogohlantirish va «QT (1)» tugmasi, «Tasdiqlash» bo'limida QT jadvali, ro'yxatdan tasdiqlaydi → «Buxgalteriya» qatori va statiya
//   matritsasi tuzatilgan holatda, asl order o'zgarmagan; dalolatnoma bosmasi (ҚТ-1, tuzatish yozuvi, imzolar); KO-3 da «QT-1» belgisi.
//   Ikkinchi so'rov — Direktor sabab bilan rad etadi (hujjat oynasidan). Kassir — «QT» tugmasi yo'q. Telefon ekrani (390 px).
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa21.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const d0 = q('select app.fin_today()');
  const ACC = 'u_acc_e21';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter21@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status`);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${d0}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${d0}"}'::jsonb)`);
  q(`set session_replication_role = replica;
     insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_s21', 'supplier', 'Sinov Ofis MChJ', '', true),
       ('cp_r21', 'supplier', 'Sinov Ijara MChJ', '', true) on conflict (id) do nothing;
     set session_replication_role = origin;`);
  const c = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_expense","amount":300000,"partyType":"counterparty","partyId":"cp_s21","basis":"Hisob-faktura № 0-21","note":"Sinov xarid","clientRef":"e21-p1-0001","lines":[{"articleId":"EX-32","amount":200000},{"articleId":"EX-49","amount":100000,"note":"Sinov boshqa"}]}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${c.id}')::text`);
  const p1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_doc_pay('${c.id}')::text`));
  const cl = asUser(ids.R_KAS, `select public.kassa_day_close('{"desk":"main","day":"${d0}","counted":700000}'::jsonb) ->> 'ok'`);
  q(`insert into app.fin_clock (id, t) values (1, now() + interval '1 day') on conflict (id) do update set t = excluded.t`);
  const DOC = p1.id;
  ok('tayyorgarlik: ikki statiyali «Xarajat» KO-2 o‘tkazildi, kun yopildi, test soati — ertaga',
    q(`select status || ':' || no || ':' || amount::bigint from public.cash_docs where id = '${DOC}'`) === `posted:${p1.no}:300000` && cl === 'true'
      && q(`select status from public.cash_days where desk = 'main' and day = '${d0}'`) === 'closed', [p1, cl]);

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
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const modalTxt = async () => pg.$eval('#modal', e => e.innerText.replace(/\s+/g, ' ')).catch(() => '');
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const clr = async () => pg.evaluate(() => document.querySelectorAll('.toast').forEach(t => t.remove()));
    const click = async sel => { await clr(); await pg.click(sel); };
    const waitToast = async re => pg.waitForFunction(r => [...document.querySelectorAll('.toast')].some(e => new RegExp(r).test(e.textContent)), re, { timeout: 15000 }).then(() => true).catch(() => false);
    // KO-3 jurnali: o'tkazilgan kun (d0) davri bilan
    const journal = async () => {
      await pg.click('#ks-ko3'); await pg.waitForSelector('#kj-sum', { timeout: 15000 });
      await pg.fill('#kj-from', d0); await pg.fill('#kj-to', d0); await pg.click('#kj-load');
      await pg.waitForFunction(() => { const s = document.querySelector('#kj-sum'); return s && !document.querySelector('#kj-body .loading'); }, null, { timeout: 15000 }); await pg.waitForTimeout(300);
    };
    return { ctx, pg, dialogs, tab, kassaReady, modalTxt, printed, click, waitToast, journal };
  }
  const fx = (cols, where) => q(`select ${cols} from public.cash_doc_fixes where ${where || `"docId" = '${DOC}'`}${/^count\(/.test(cols) ? '' : ' order by "requestedAt"'}`);

  // ---------------- 1) buxgalter: KO-3 → «QT» → tuzatish so'rovi
  const a = await login(ACC);
  await a.kassaReady();
  ok('buxgalter: sarlavhada «QT» tugmasi bor', !!(await a.pg.$('#ks-fix')));
  await a.journal();
  ok('KO-3: o‘tkazilgan kundagi «Xarajat» orderida «QT» tugmasi', !!(await a.pg.$(`[data-kfix="${DOC}"]`)));
  await a.pg.click(`[data-kfix="${DOC}"]`); await a.pg.waitForSelector('#fx-send', { timeout: 15000 });
  {
    const t = await a.modalTxt();
    ok('tuzatish oynasi: order (Ch-raqam, sana, summa), «order o‘zi o‘zgarmaydi», ikki qator va joriy statiyalar',
      new RegExp(`Chiqim orderi Ch-${p1.no}`).test(t) && /300 000 so‘m/.test(t) && /Order o‘zi \(summa, sana, raqam, imzolar\) o‘zgarmaydi/.test(t)
        && (await a.pg.$$('[data-fxart]')).length === 2 && (await a.pg.$eval('[data-fxart="1"]', e => e.value)) === 'EX-32' && (await a.pg.$eval('[data-fxart="2"]', e => e.value)) === 'EX-49', t.slice(0, 600));
  }
  await a.click('#fx-send'); await a.pg.waitForTimeout(300);
  const t0 = await a.pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
  await a.pg.selectOption('[data-fxart="1"]', 'OP-18');
  await a.pg.selectOption('#fx-pc', 'cp_r21');
  await a.pg.fill('#fx-basis', 'Hisob-faktura № 0-21, ijara shartnomasi № 0-3');
  await a.click('#fx-send'); await a.pg.waitForTimeout(300);
  const t1 = await a.pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
  ok('o‘zgarishsiz — «O‘zgarish yo‘q»; sababsiz — «sababini yozing» (serverga yuborilmaydi)', /O‘zgarish yo‘q/.test(t0) && /Tuzatish sababini yozing/.test(t1) && fx('count(*)') === '0', [t0, t1]);
  await a.pg.fill('#fx-reason', 'Printer — asosiy vosita (0820), kanselyariya emas; oluvchi — ijarachi');
  await a.click('#fx-send');
  const sent = await a.waitToast('So‘rov yuborildi');
  await a.pg.waitForFunction(() => /Direktor qarorini kutmoqda/.test((document.querySelector('#modal') || {}).innerText || ''), null, { timeout: 15000 }).catch(() => {});
  const mt1 = await a.modalTxt();
  ok('so‘rov yuborildi: oynada «Direktor qarorini kutmoqda», o‘zgarishlar ro‘yxati, yangi so‘rov tugmasi yo‘q',
    sent && /Direktor qarorini kutmoqda/.test(mt1) && /Statiya \(1-qator, 200 000 so‘m\): EX-32 .*→ OP-18/.test(mt1) && /Oluvchi: Sinov Ofis MChJ → Sinov Ijara MChJ/.test(mt1) && !(await a.pg.$('#fx-send')), mt1.slice(0, 800));
  ok('bazada: kutilayotgan so‘rov — 1-qator OP-18 / 0820, 2-qator o‘zgarmagan, oluvchi cp_r21, so‘ragan — buxgalter',
    fx(`status || ':' || (after -> 'lines' -> 0 ->> 'articleId') || '/' || (after -> 'lines' -> 0 ->> 'debit') || ':' || (after -> 'lines' -> 1 ->> 'articleId') || ':' || (after ->> 'partyId') || ':' || "requestedBy"`)
      === `pending:OP-18/0820:EX-49:cp_r21:${ACC}`, fx('to_jsonb(cash_doc_fixes)::text'));
  await a.pg.screenshot({ path: `${OUT}/k21-acc-${UI}-1440-form.png`, fullPage: false });
  await a.ctx.close();

  // ---------------- 2) Direktor: ogohlantirish, «QT (1)», «Tasdiqlash» bo'limi, ro'yxatdan tasdiqlash
  const d = await login(ids.R_DIR);
  await d.kassaReady();
  {
    const body = await d.pg.$eval('#ks-body', e => e.innerText.replace(/\s+/g, ' ')).catch(() => '');
    const bt = await d.pg.$eval('#ks-fix', e => e.textContent).catch(() => '');
    ok('Direktor: ogohlantirish «Qayta tasnif (QT) so‘rovlari qaroringizni kutmoqda: 1 ta» va «QT (1)» tugmasi', /Qayta tasnif \(QT\) so‘rovlari qaroringizni kutmoqda: 1 ta/.test(body) && /QT \(1\)/.test(bt), [body.slice(0, 400), bt]);
  }
  await d.tab('approvals');
  const apOk = await d.pg.waitForSelector('table[data-fxappr]', { timeout: 20000 }).then(() => true).catch(() => false);
  const apTxt = apOk ? await d.pg.$eval('table[data-fxappr]', e => e.innerText.replace(/\s+/g, ' ')) : '';
  ok('«Tasdiqlash» bo‘limi: QT so‘rovlari jadvali (order, o‘zgarish, so‘ragan)', apOk && new RegExp(`Ch-${p1.no}`).test(apTxt) && /OP-18/.test(apTxt) && /Sinov Buxgalter/.test(apTxt), apTxt.slice(0, 400));
  await d.kassaReady();
  await d.pg.click('#ks-fix'); await d.pg.waitForSelector('#fxl-tbl', { timeout: 15000 });
  const F1 = fx('id');
  await d.click(`[data-fxok="${F1}"]`);
  const okT = await d.waitToast('Tasdiqlandi ✓ QT-1');
  const conf = d.dialogs.find(x => /qayta tasnif tasdiqlansinmi/.test(x)) || '';
  ok('Direktor tasdiqladi: tasdiq so‘rovi, «Tasdiqlandi ✓ QT-1»; bazada — raqam 1, bugungi sana', okT && /«Buxgalteriya»dagi xarajat qatori/.test(conf)
    && fx(`status || ':' || no || ':' || "actDay"`) === `approved:1:${q('select app.fin_today()')}`, [okT, conf, fx('status, no, "actDay"')]);
  ok('«Buxgalteriya»: 1-qator — OP-18, ikkala qator — Sinov Ijara MChJ; asl order o‘zgarmagan',
    q(`select string_agg(id || '=' || "articleId" || '/' || "counterpartyId", ',' order by id) from public.expenses where "cashDocId" = '${DOC}'`) === `kx_${DOC}_1=OP-18/cp_r21,kx_${DOC}_2=EX-49/cp_r21`
      && q(`select "partyId" || ':' || (select string_agg("articleId", ',' order by "lineNo") from public.cash_doc_lines where "docId" = '${DOC}') from public.cash_docs where id = '${DOC}'`) === 'cp_s21:EX-32,EX-49',
    q(`select string_agg(id || '=' || "articleId" || '/' || coalesce("counterpartyId", '-') || '/' || note, ' | ') from public.expenses where "cashDocId" = '${DOC}'`));
  const mx = JSON.parse(asUser(ids.R_MOL, `select public.kassa_matrix('main', '${d0.slice(0, 7)}')::text`));
  const ko2 = (mx.rows || []).filter(r => r.form === 'KO2').map(r => r.articleId + '=' + r.total).sort().join(',');
  ok('statiya matritsasi (RP-08): OP-18 = 200 000, EX-49 = 100 000, EX-32 yo‘q', ko2 === 'EX-49=100000,OP-18=200000', ko2);
  await d.pg.click('#fxl-a'); await d.pg.waitForSelector('#fxl-tbl', { timeout: 15000 });
  await d.pg.click(`[data-fxprint="${F1}"]`); await d.pg.waitForTimeout(1500);
  {
    const pr = (await d.printed()).join(' || ');
    ok('dalolatnoma bosmasi: «ҚАЙТА ТАСНИФ ДАЛОЛАТНОМАСИ № ҚТ-1», tuzatish yozuvi Дт 0820 — Кт 9420, oluvchi, sabab, imzolar',
      /ҚАЙТА ТАСНИФ ДАЛОЛАТНОМАСИ № ҚТ-1/.test(pr) && new RegExp(`чиқим касса ордери № Ч-${p1.no}`).test(pr) && /Дт 0820 — Кт 9420: 200 000=00/.test(pr)
        && /Sinov Ofis MChJ Sinov Ijara MChJ/.test(pr) && /Printer — asosiy vosita/.test(pr) && /Тузди Sinov Buxgalter/.test(pr) && /Тасдиқлади: Директор/.test(pr), pr.slice(0, 900));
  }
  await d.pg.click('#m-cancel').catch(() => {});
  await d.journal();
  {
    const rowTxt = await d.pg.$$eval('#kj-tbl tbody tr', xs => xs.map(x => x.innerText.replace(/\s+/g, ' ')).join(' | '));
    ok('KO-3 da orderda «QT-1» belgisi (order o‘zi — asl: KO-3 summasi o‘zgarmaydi)', /QT-1/.test(rowTxt) && /300 000/.test(rowTxt), rowTxt.slice(0, 400));
  }
  await d.ctx.close();

  // ---------------- 3) ikkinchi so'rov — Direktor hujjat oynasidan sabab bilan rad etadi
  const r2 = JSON.parse(asUser(ACC, `select public.kassa_fix_request('{"docId":"${DOC}","clientRef":"e21-fx2-0001","reason":"Boshqa xarajat — xo‘jalik vositasi","lines":[{"lineNo":2,"articleId":"EX-16"}]}'::jsonb)::text`));
  ok('ikkinchi so‘rov (2-qator EX-16): oldingi holat — QT-1 dan keyingi', fx(`(before -> 'lines' -> 0 ->> 'articleId') || ':' || ("baseFixId" = '${F1}')`, `id = '${r2.id}'`) === 'OP-18:true', r2);
  const d2 = await login(ids.R_DIR);
  await d2.kassaReady(); await d2.journal();
  await d2.pg.click(`[data-kfix="${DOC}"]`); await d2.pg.waitForSelector(`[data-fxno="${r2.id}"]`, { timeout: 15000 });
  ok('Direktor hujjat oynasida: QT-1 (tasdiqlangan) va kutilayotgan so‘rov; so‘rash tugmasi yo‘q', /QT-1/.test(await d2.modalTxt()) && /Direktor qarorini kutmoqda/.test(await d2.modalTxt()) && !(await d2.pg.$('#fx-send')));
  await d2.pg.click(`[data-fxno="${r2.id}"]`); await d2.pg.waitForSelector('#ks-reason', { timeout: 10000 });
  await d2.pg.fill('#ks-reason', 'Hisob-faktura bo‘yicha — ofis jihozi'); await d2.click('#ks-ok');
  const rj = await d2.waitToast('Rad etildi ✓');
  await d2.pg.waitForFunction(() => /Rad etilgan/.test((document.querySelector('#modal') || {}).innerText || ''), null, { timeout: 15000 }).catch(() => {});
  ok('rad etildi: oynada «Rad etilgan» va sabab; «Buxgalteriya» 2-qatori o‘zgarmadi', rj && /Rad etilgan/.test(await d2.modalTxt()) && /Hisob-faktura bo‘yicha — ofis jihozi/.test(await d2.modalTxt())
    && fx(`status || ':' || "decisionNote"`, `id = '${r2.id}'`) === 'rejected:Hisob-faktura bo‘yicha — ofis jihozi' && q(`select "articleId" from public.expenses where id = 'kx_${DOC}_2'`) === 'EX-49');
  await d2.ctx.close();

  // ---------------- 4) kassir — «QT» yo'q; telefon ekrani (390 px)
  {
    const k = await login(ids.R_KAS);
    await k.kassaReady();
    const noBtn = !(await k.pg.$('#ks-fix'));
    await k.journal();
    const rowTxt = await k.pg.$$eval('#kj-tbl tbody tr', xs => xs.map(x => x.innerText.replace(/\s+/g, ' ')).join(' | '));
    ok('kassir: «QT» tugmasi yo‘q; KO-3 da belgi ko‘rinadi, tuzatish tugmasi yo‘q', noBtn && /QT-1/.test(rowTxt) && !(await k.pg.$(`[data-kfix="${DOC}"]`)), rowTxt.slice(0, 300));
    await k.ctx.close();
  }
  {
    const p = await login(ACC, { width: 390, height: 844 });
    await p.kassaReady(); await p.journal();
    await p.pg.click(`[data-kfix="${DOC}"]`); await p.pg.waitForSelector('#fx-send', { timeout: 15000 });
    const ov = await p.pg.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, mw: Math.round(document.querySelector('#modal').getBoundingClientRect().right) }));
    await p.pg.screenshot({ path: `${OUT}/k21-acc-${UI}-390-form.png`, fullPage: false });
    ok('telefon (390 px): tuzatish oynasi ekranga sig‘adi (gorizontal siljish yo‘q)', ov.sw <= ov.cw + 1 && ov.mw <= ov.cw + 1, ov);
    await p.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  q(`delete from app.fin_clock`);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.log('XATO ' + (e.stack || e)); try { q(`delete from app.fin_clock`); } catch (_) {} process.exit(1); });
