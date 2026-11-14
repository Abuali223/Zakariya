// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): KO-3 — kassa orderlari jurnali (F1.22, buxgalter ko'rigi M4).
//   Moliya menejeri «KO-3» oynasi: jamlar, qoldiqlar, ro'yxat (bekor qilingani bilan), chop etish (KO-3 shakli), Excel (XLSX) — fayl
//   o'qilib tekshiriladi; Excel FD-28 bo'yicha: Moliya menejeriga ismsiz, Direktorga to'liq, kassirda tugma yo'q (chop etadi);
//   telefonda oyna sig'adi.  Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa10.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const XLSX = require(E.REPO + '/vendor/xlsx/xlsx.mini.min.js');
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()'), dm = today.slice(8, 10) + '.' + today.slice(5, 7) + '.' + today.slice(0, 4);
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
    return { ctx, pg, tab, kassaReady, printed };
  }
  // tayyorgarlik: ishga tushirish; 2 ta kirim (biri bekor qilinadi), 1 ta chiqim
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  q(`insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_e10', 'supplier', 'Sinov Taminot MChJ', '', true) on conflict (id) do nothing`);
  const r1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_receipt('{"op":"in_other","amount":70000,"partyType":"other","partyName":"Sinov Mehmon","articleId":"IN-06","basis":"Tilxat 1","note":"Sinov","clientRef":"e10-r1-0001"}'::jsonb)::text`));
  const r2 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_receipt('{"op":"in_other","amount":30000,"partyType":"other","partyName":"Sinov Xato","articleId":"IN-06","basis":"Tilxat 2","note":"Sinov","clientRef":"e10-r2-0001"}'::jsonb)::text`));
  asUser(ids.R_KAS, `select public.kassa_doc_void('${r2.id}', 'Xato kiritildi (sinov)')::text`);
  const c1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_expense","amount":45000,"partyType":"counterparty","partyId":"cp_e10","basis":"Hisob-faktura № 10","clientRef":"e10-c1-0001","lines":[{"articleId":"EX-32","amount":45000}]}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${c1.id}')::text`); asUser(ids.R_KAS, `select public.kassa_doc_pay('${c1.id}')::text`);
  ok('tayyorgarlik: kirim 70 000 (+ bekor qilingan 30 000), chiqim 45 000', q(`select string_agg(form || ':' || status || ':' || amount::bigint, ',' order by form, no) from public.cash_docs where form in ('KO1','KO2')`) === 'KO1:posted:70000,KO1:void:30000,KO2:posted:45000'
    && !!r1.id, q(`select string_agg(form || ':' || status, ',') from public.cash_docs`));

  // ---------------- 1) Moliya menejeri: KO-3 oynasi, chop etish, Excel
  {
    const m = await login(ids.R_MOL);
    await m.kassaReady();
    ok('«KO-3» tugmasi bor', !!(await m.pg.$('#ks-ko3')));
    await m.pg.click('#ks-ko3'); await m.pg.waitForSelector('#kj-sum', { timeout: 15000 });
    const sum = await m.pg.$eval('#kj-sum', e => e.textContent.replace(/\s+/g, ' '));
    ok('jamlar: boshi 1 000 000, kirim 70 000 (1 ta), chiqim 45 000 (1 ta), oxiri 1 025 000, bekor 1', /Davr boshi 1 000 000 so‘m · kirim 70 000 so‘m \(1 ta\) · chiqim 45 000 so‘m \(1 ta\) · davr oxiri 1 025 000 so‘m · bekor qilingan: 1 ta/.test(sum) && !/mos emas/.test(sum), sum);
    const rows = await m.pg.$$eval('#kj-tbl tbody tr', xs => xs.map(x => x.innerText.replace(/\s+/g, ' ').trim()));
    ok('ro‘yxat: 3 qator (K-1, K-2 bekor — sababi bilan, Ch-1)', rows.length === 3 && rows.some(r => /K-2/.test(r) && /bekor qilingan: Xato kiritildi/.test(r)) && rows.some(r => /Ch-1/.test(r) && /45 000/.test(r)), rows);
    const before = (await m.printed()).length;
    await m.pg.click('#kj-print'); await m.pg.waitForTimeout(1500);
    const pr = (await m.printed()).slice(before).join(' || ');
    ok('KO-3 chop etildi: sarlavha, davr, jamlar, bekor qilingan', /КИРИМ ВА ЧИҚИМ КАССА ҲУЖЖАТЛАРИНИ РЎЙХАТГА ОЛИШ ЖУРНАЛИ/.test(pr) && pr.includes(dm) && /Жами \(бекор қилинганларсиз\) 70 000=00/.test(pr) && /45 000=00/.test(pr) && /бекор қилинган: Xato kiritildi/.test(pr), pr.slice(0, 500));
    const [dl] = await Promise.all([m.pg.waitForEvent('download', { timeout: 15000 }), m.pg.click('#kj-xlsx')]);
    const file = await dl.path(), nm = dl.suggestedFilename();
    const wb = XLSX.read(fs.readFileSync(file), { type: 'buffer' }), sh = wb.Sheets[wb.SheetNames[0]], data = XLSX.utils.sheet_to_json(sh, { header: 1, raw: true, defval: '' });
    ok('Excel fayl yuklandi: nomi KO-3_main_<davr>-ismsiz.xlsx (FD-28), varaq «KO-3»', /^KO-3_main_\d{4}-\d{2}-01_\d{4}-\d{2}-\d{2}-ismsiz\.xlsx$/.test(nm) && wb.SheetNames[0] === 'KO-3', [nm, wb.SheetNames]);
    const body = data.slice(5).filter(r => r[1]), flat = JSON.stringify(data);
    ok('Excel: 3 qator, summalar son, bekor qilingan — summasiz, jami 70 000 / 45 000', body.length === 3 && body.some(r => r[1] === 'Kirim orderi' && r[6] === 70000) && body.some(r => r[1] === 'Chiqim orderi' && r[7] === 45000)
      && body.some(r => String(r[8]) === 'bekor qilingan (30 000)' && r[6] === '') && data.some(r => r[5] === 'Jami (bekor qilinganlarsiz)' && r[6] === 70000 && r[7] === 45000), data.slice(0, 12));
    ok('Excel ismsiz: «boshqa shaxs» nomi, asosi va bekor qilish sababi yo‘q; yetkazib beruvchi nomi va asosi bor; izoh qatori', !/Sinov Mehmon|Sinov Xato|Tilxat|Xato kiritildi/.test(flat)
      && body.some(r => r[4] === 'Sinov Taminot MChJ' && r[5] === 'Hisob-faktura № 10') && body.some(r => r[4] === 'boshqa shaxs') && /^Ismsiz nusxa \(FD-28\)/.test(String(data[3][0])), data.slice(0, 9));
    const toasts = await m.pg.$$eval('#toasts .toast', xs => xs.map(x => x.textContent));
    ok('xabar: ismsiz saqlandi, to‘liq nusxa Direktorda', toasts.some(x => /Saqlandi: ismsiz/.test(x)), toasts);
    // oy boshi o'zgartirilsa (davr — bir kun) va noto'g'ri davr
    await m.pg.fill('#kj-from', today); await m.pg.fill('#kj-to', today); await m.pg.click('#kj-load'); await m.pg.waitForSelector('#kj-sum');
    ok('davr — bir kun: o‘sha jamlar', /kirim 70 000 so‘m \(1 ta\)/.test(await m.pg.$eval('#kj-sum', e => e.textContent.replace(/\s+/g, ' '))));
    await m.pg.screenshot({ path: `${OUT}/ko3-${UI}-1440.png` });
    await m.ctx.close();
  }
  // ---------------- 2) Direktor: Excel — to'liq (ismlar, asos, sabab bilan)
  {
    const d = await login(ids.R_DIR);
    await d.kassaReady();
    await d.pg.click('#ks-ko3'); await d.pg.waitForSelector('#kj-sum', { timeout: 15000 });
    const [dl] = await Promise.all([d.pg.waitForEvent('download', { timeout: 15000 }), d.pg.click('#kj-xlsx')]);
    const nm = dl.suggestedFilename(), wb = XLSX.read(fs.readFileSync(await dl.path()), { type: 'buffer' });
    const data = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, raw: true, defval: '' }), body = data.slice(5).filter(r => r[1]);
    ok('Direktor Excel: nomi «-ismsiz»siz, ismlar, asos va bekor qilish sababi bor, izoh qatori yo‘q', /^KO-3_main_\d{4}-\d{2}-01_\d{4}-\d{2}-\d{2}\.xlsx$/.test(nm)
      && body.some(r => r[4] === 'Sinov Mehmon' && r[5] === 'Tilxat 1') && body.some(r => /^bekor qilingan: Xato kiritildi/.test(String(r[8]))) && !String((data[3] || [])[0] || ''), [nm, data.slice(0, 9)]);
    await d.ctx.close();
  }
  // ---------------- 3) Kassir: KO-3 va chop etish bor, Excel yo'q (FD-28); telefonda oyna sig'adi
  {
    const k = await login(ids.R_KAS, { width: 390, height: 844 });
    await k.kassaReady();
    ok('kassirda ham «KO-3» tugmasi', !!(await k.pg.$('#ks-ko3')));
    await k.pg.click('#ks-ko3'); await k.pg.waitForSelector('#kj-sum', { timeout: 15000 });
    ok('kassir: «Chop etish» bor, «Excel» yo‘q (FD-28)', !!(await k.pg.$('#kj-print')) && !(await k.pg.$('#kj-xlsx')));
    const mw = await k.pg.evaluate(() => { const m = document.querySelector('#modal'); return m.scrollWidth - m.clientWidth; });
    const sw = await k.pg.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    ok('telefon: KO-3 oynasi va sahifa gorizontal siljimaydi', mw <= 1 && sw <= 1, [mw, sw]);
    await k.pg.screenshot({ path: `${OUT}/ko3-${UI}-390.png`, fullPage: true });
    await k.ctx.close();
  }
  const sqlErr = (uid, sql) => cp.spawnSync(E.PSQL[0], [...E.PSQL.slice(1), '-q', '-At', '-d', E.DB, '-c',
    `begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`], { encoding: 'utf8' }).stderr;
  ok('server: kassir Excel eksportini ololmaydi (42501)', /Ruxsat yo.q: Excel eksporti/.test(sqlErr(ids.R_KAS, `select public.kassa_journal_export('main', '${today}', '${today}')`)));
  ok('server: o‘qituvchi jurnalni ko‘ra olmaydi', /Ruxsat yo/.test(cp.spawnSync(E.PSQL[0], [...E.PSQL.slice(1), '-q', '-At', '-d', E.DB, '-c',
    `begin; select set_config('request.jwt.claims', '{"sub":"${ids.R_TCH}","role":"authenticated"}', true); set local role authenticated; select public.kassa_journal('main', '${today}', '${today}'); commit;`], { encoding: 'utf8' }).stderr));
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(1); });
