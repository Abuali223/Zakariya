// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): RP-08 oylik statiya matritsasi va buxgalter uchun oylik kassa to'plami (F1.22).
//   Moliya menejeri «Statiyalar» oynasi: jamlar (ichki o'tkazmasiz ham), haftalik jadval, chop etish, oylik to'plam (Excel, 4 varaq, ismsiz) —
//   fayl o'qilib tekshiriladi; Direktor to'plami to'liq; kassirda Excel yo'q; telefonda oyna sig'adi.  Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa11.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const XLSX = require(E.REPO + '/vendor/xlsx/xlsx.mini.min.js');
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const sqlErr = (uid, sql) => cp.spawnSync(E.PSQL[0], [...E.PSQL.slice(1), '-q', '-At', '-d', E.DB, '-c',
  `begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`], { encoding: 'utf8' }).stderr;
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const book = file => { const wb = XLSX.read(fs.readFileSync(file), { type: 'buffer' }); const S = {}; wb.SheetNames.forEach(n => { S[n] = XLSX.utils.sheet_to_json(wb.Sheets[n], { header: 1, raw: true, defval: '' }); }); return { names: wb.SheetNames, S }; };
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()'), month = today.slice(0, 7);
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
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const openMx = async () => { await pg.click('#ks-mx'); await pg.waitForSelector('#km-sum', { timeout: 15000 }); };
    return { ctx, pg, tab, kassaReady, printed, openMx };
  }
  // tayyorgarlik: ishga tushirish; kirim (boshqa shaxs, IN-06), bankdan naqd (ichki o'tkazma), yetkazib beruvchiga xarajat, hisobdorga avans
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  q(`insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_e11', 'supplier', 'Sinov Taminot MChJ', '', true), ('cp_b11', 'bank', 'Sinov Bank', '', true) on conflict (id) do nothing`);
  const st = q(`select s.id || '|' || s."staffId" || '|' || s.name from public.staff s where coalesce(s."staffId", '') <> '' and coalesce(s.name, '') <> '' order by s.id limit 1`).split('|');
  const [stId, stCode, stName] = st;
  asUser(ids.R_KAS, `select public.kassa_receipt('{"op":"in_other","amount":70000,"partyType":"other","partyName":"Sinov Mehmon","articleId":"IN-06","basis":"Tilxat 1","note":"Sinov","clientRef":"e11-r1-0001"}'::jsonb)::text`);
  asUser(ids.R_KAS, `select public.kassa_receipt('{"op":"in_bank","amount":500000,"partyType":"bank","partyId":"cp_b11","basis":"Chek № 7","clientRef":"e11-r2-0001"}'::jsonb)::text`);
  const c1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_expense","amount":45000,"partyType":"counterparty","partyId":"cp_e11","basis":"Hisob-faktura № 11","clientRef":"e11-c1-0001","lines":[{"articleId":"EX-32","amount":45000}]}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${c1.id}')::text`); asUser(ids.R_KAS, `select public.kassa_doc_pay('${c1.id}')::text`);
  const c2 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_accountable","amount":30000,"partyType":"employee","partyId":"staff:${stId}","basis":"Xo‘jalik xaridi","clientRef":"e11-c2-0001"}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${c2.id}')::text`); asUser(ids.R_KAS, `select public.kassa_doc_pay('${c2.id}')::text`);
  ok('tayyorgarlik: kirim 70 000 + 500 000 (bank), chiqim 45 000 + 30 000 (avans)', q(`select string_agg(form || ':' || op || ':' || amount::bigint, ',' order by form, no) from public.cash_docs where status = 'posted' and form in ('KO1','KO2') and desk = 'main'`)
    === 'KO1:in_other:70000,KO1:in_bank:500000,KO2:out_expense:45000,KO2:out_accountable:30000' && !!stCode, q(`select string_agg(form || ':' || op || ':' || status, ',') from public.cash_docs`));

  // ---------------- 1) Moliya menejeri: oyna, chop etish, oylik to'plam (ismsiz)
  {
    const m = await login(ids.R_MOL);
    await m.kassaReady();
    ok('«Statiyalar» tugmasi bor', !!(await m.pg.$('#ks-mx')));
    await m.openMx();
    const sum = await m.pg.$eval('#km-sum', e => e.textContent.replace(/\s+/g, ' '));
    ok('jamlar: oy boshi 1 000 000, kirim 570 000, chiqim 75 000, oy oxiri 1 495 000; ichki o‘tkazmasiz kirim 70 000, chiqim 75 000',
      /Oy boshi 1 000 000 so‘m · kirim 570 000 so‘m · chiqim 75 000 so‘m · oy oxiri 1 495 000 so‘m/.test(sum) && /Ichki o‘tkazmalarsiz \(bank\): kirim 70 000 so‘m, chiqim 75 000 so‘m/.test(sum) && !/mos emas/.test(sum), sum);
    const rows = await m.pg.$$eval('#km-tbl tbody tr', xs => xs.map(x => x.innerText.replace(/\s+/g, ' ').trim()));
    ok('jadval: Kirim / Chiqim bo‘limlari, statiyalar (bank — ichki o‘tkazma), jami qatorlari', rows.some(r => /^Kirim$/.test(r)) && rows.some(r => /IN-06/.test(r) && /70 000/.test(r))
      && rows.some(r => /OP-01 · ichki o‘tkazma/.test(r) && /500 000/.test(r)) && rows.some(r => /EX-32/.test(r) && /45 000/.test(r)) && rows.some(r => /OP-06/.test(r) && /30 000/.test(r))
      && rows.some(r => /^Jami kirim/.test(r) && /570 000 so‘m/.test(r)) && rows.some(r => /^Jami chiqim/.test(r) && /75 000 so‘m/.test(r)), rows);
    const before = (await m.printed()).length;
    await m.pg.click('#km-print'); await m.pg.waitForTimeout(1500);
    const pr = (await m.printed()).slice(before).join(' || ');
    ok('chop etildi: sarlavha, bo‘limlar, ichki o‘tkazma belgisi, jamlar, imzolar', /КАССА БЎЙИЧА ОЙЛИК СТАТИЯЛАР МАТРИЦАСИ/.test(pr) && /Жами кирим/.test(pr) && /570 000=00/.test(pr)
      && /\(ички ўтказма\)/.test(pr) && /Ички ўтказмаларсиз \(банк\): кирим 70 000=00, чиқим 75 000=00/.test(pr) && /Бош бухгалтер/.test(pr), pr.slice(0, 600));
    const [dl] = await Promise.all([m.pg.waitForEvent('download', { timeout: 20000 }), m.pg.click('#km-pack')]);
    const nm = dl.suggestedFilename(), B = book(await dl.path()), flat = JSON.stringify(B.S);
    ok('oylik to‘plam yuklandi: nomi Kassa_main_<oy>-ismsiz.xlsx, 4 varaq E1–E4', nm === `Kassa_main_${month}-ismsiz.xlsx` && B.names.join(',') === 'E1 KO-3,E2 Statiyalar,E3 Kassa kunlari,E4 Hisobdorlar', [nm, B.names]);
    const e2 = B.S['E2 Statiyalar'], e3 = B.S['E3 Kassa kunlari'], e4 = B.S['E4 Hisobdorlar'], dIdx = +today.slice(8, 10) + 1;
    ok('E2 statiyalar: kun ustunida son, jami ustuni; bank qatori «ichki o‘tkazma»', e2.some(r => r[0] === 'IN-06' && r[dIdx] === 70000 && r[r.length - 1] === 70000)
      && e2.some(r => r[0] === 'OP-01' && /ichki o‘tkazma/.test(r[1]) && r[dIdx] === 500000) && e2.some(r => r[1] === 'Jami kirim' && r[r.length - 1] === 570000), e2.slice(4, 12).map(r => [r[0], r[1], r[dIdx], r[r.length - 1]]));
    const dRow = e3.find(r => typeof r[0] === 'number' && r[3] === 570000);
    ok('E3 kassa kunlari: bugungi kun — ochiq, kirim 570 000, chiqim 75 000 (son)', !!dRow && dRow[1] === 'ochiq' && dRow[4] === 75000 && XLSX.SSF.format('dd\\.mm\\.yyyy', dRow[0]) === today.slice(8, 10) + '.' + today.slice(5, 7) + '.' + today.slice(0, 4), e3.slice(4, 8));
    ok('E4 hisobdorlar: tabel kodi bilan, ism ustuni yo‘q; berildi 30 000, oy oxiri 30 000', e4[4][1] === 'Oy boshiga qoldiq' && e4.some(r => r[0] === stCode && r[2] === 30000 && r[5] === 30000) && /^Ismsiz nusxa/.test(String(e4[3][0])), e4.slice(3, 8));
    ok('ismsiz to‘plamda «boshqa» tomon va xodim ismi yo‘q; yetkazib beruvchi nomi bor', !flat.includes('Sinov Mehmon') && !flat.includes(stName) && flat.includes('Sinov Taminot MChJ'), flat.slice(0, 300));
    const toasts = await m.pg.$$eval('#toasts .toast', xs => xs.map(x => x.textContent));
    ok('xabar: ismsiz saqlandi', toasts.some(x => /Saqlandi: ismsiz/.test(x)), toasts);
    await m.pg.screenshot({ path: `${OUT}/mx-${UI}-1440.png` });
    await m.ctx.close();
  }
  // ---------------- 2) Direktor: to'plam to'liq
  {
    const d = await login(ids.R_DIR);
    await d.kassaReady(); await d.openMx();
    const [dl] = await Promise.all([d.pg.waitForEvent('download', { timeout: 20000 }), d.pg.click('#km-pack')]);
    const nm = dl.suggestedFilename(), B = book(await dl.path()), e4 = B.S['E4 Hisobdorlar'];
    ok('Direktor to‘plami: nomi «-ismsiz»siz; KO-3 da ism, E4 da F.I.Sh. ustuni va ism', nm === `Kassa_main_${month}.xlsx` && JSON.stringify(B.S['E1 KO-3']).includes('Sinov Mehmon')
      && e4[4][1] === 'F.I.Sh.' && e4.some(r => r[0] === stCode && r[1] === stName && r[3] === 30000), [nm, e4.slice(3, 7)]);
    await d.ctx.close();
  }
  // ---------------- 3) Kassir: oyna va chop etish bor, Excel yo'q; telefonda oyna sig'adi
  {
    const k = await login(ids.R_KAS, { width: 390, height: 844 });
    await k.kassaReady();
    ok('kassirda ham «Statiyalar» tugmasi', !!(await k.pg.$('#ks-mx')));
    await k.openMx();
    ok('kassir: «Chop etish» bor, «Oylik to‘plam» yo‘q (FD-28)', !!(await k.pg.$('#km-print')) && !(await k.pg.$('#km-pack')));
    const mw = await k.pg.evaluate(() => { const m = document.querySelector('#modal'); return m.scrollWidth - m.clientWidth; });
    const sw = await k.pg.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    const tw = await k.pg.evaluate(() => { const w = document.querySelector('#km-tbl').parentElement; return w.scrollWidth - w.clientWidth; });
    ok('telefon: oyna, jadval va sahifa gorizontal siljimaydi (oy jami ko‘rinadi)', mw <= 1 && sw <= 1 && tw <= 1, [mw, sw, tw]);
    await k.pg.screenshot({ path: `${OUT}/mx-${UI}-390.png` });
    await k.ctx.close();
  }
  ok('server: kassir oylik to‘plamni ololmaydi, o‘qituvchi matritsani ko‘rmaydi (42501)', /Ruxsat yo.q: oylik kassa to.plami/.test(sqlErr(ids.R_KAS, `select public.kassa_month_pack('main', '${month}')`))
    && /Ruxsat yo/.test(sqlErr(ids.R_TCH, `select public.kassa_matrix('main', '${month}')`)));
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(1); });
