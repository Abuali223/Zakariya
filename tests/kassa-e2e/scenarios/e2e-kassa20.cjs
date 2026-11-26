// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.2 — kontragentlar va RP-10 ko'chirma brauzerda.
//   Moliya menejeri: «Buxgalteriya» → «🏢 Kontragentlar» (ro'yxat, qidiruv, tur va holat filtri); yangi karta (STIR, hisob raqami, MFO,
//   bank, shartnoma) — oynaning o'z tekshiruvlari; shu STIR boshqa kartada — ogohlantirish (tasdiqlansa yoziladi); kartani o'zgartirish va
//   bir vaqtda tahrirlash (boshqa foydalanuvchi saqlagan — karta yangi ma'lumot bilan qayta ochiladi); eski noto'g'ri STIR'li karta (STIR
//   o'zgarmasa saqlanadi); ko'chirma (kassa orderi + bank hujjati, jamlar, yig'ma sof), chop etish, Excel; jismoniy shaxs ko'chirmasi —
//   Moliya menejeriga ismsiz fayl (FD-28), Direktorga to'liq; buxgalter — kartani yuritadi (turini tasdiqlaydi); telefon ekrani (390 px).
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa20.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const XLSX = require(E.REPO + '/vendor/xlsx/xlsx.mini.min.js');
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
  const today = q('select app.fin_today()'), y0 = today.slice(0, 4) + '-01-01';
  const dm = d => d.slice(8, 10) + '.' + d.slice(5, 7) + '.' + d.slice(0, 4);
  const ACC = 'u_acc_e20';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter20@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status`);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)`);
  // Sintetik: bank, YaTT (turi tasdiqlanmagan), eski noto'g'ri STIR'li yetkazib beruvchi; YaTTga naqd to'lov (KO-2 — asosida ism bor)
  q(`set session_replication_role = replica;
     insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_b20', 'bank', 'Sinov Bank ATB', '', true),
       ('cp_p20', 'person', 'Sinov Usta YaTT', '', true), ('cp_o20', 'supplier', 'Eski Taminot', '1234567', true) on conflict (id) do nothing;
     set session_replication_role = origin;`);
  const pay = (party, amt, art, basis, ref) => {
    const c = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_expense","amount":${amt},"partyType":"counterparty","partyId":"${party}","basis":"${basis}","note":"Sinov to‘lov","clientRef":"${ref}","lines":[{"articleId":"${art}","amount":${amt}}]}'::jsonb)::text`));
    asUser(ids.R_MOL, `select public.kassa_doc_approve('${c.id}')::text`);
    return JSON.parse(asUser(ids.R_KAS, `select public.kassa_doc_pay('${c.id}')::text`));
  };
  const p1 = pay('cp_p20', 45000, 'EX-49', 'Xizmat — Sinov Usta', 'e20-p1-0001');
  ok('tayyorgarlik: YaTTga naqd to‘lov (KO-2) o‘tkazildi', q(`select status || ':' || amount::bigint from public.cash_docs where id = '${p1.id || ''}'`) === 'posted:45000', p1);

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
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
    const modalTxt = async () => pg.$eval('#modal', e => e.innerText).catch(() => '');
    const acReady = async () => { await tab('accounting'); await pg.waitForSelector('#ac-month', { state: 'attached', timeout: 30000 });
      await pg.waitForFunction(() => { const x = document.querySelector('#ac-body'); return x && !x.querySelector('.loading'); }, null, { timeout: 30000 }); await pg.waitForTimeout(300); };
    const openList = async () => { for (let i = 0; i < 8 && !(await pg.$('#cp-list table, #cp-list .empty')); i++) { await pg.$eval('#ac-cp', x => x.click()).catch(() => {}); await pg.waitForTimeout(600); }
      await pg.waitForSelector('#cp-list table, #cp-list .empty', { timeout: 15000 }); await pg.waitForTimeout(200); };
    const rows = async () => pg.$$eval('#cp-list tbody tr', xs => xs.map(x => x.innerText.replace(/\s+/g, ' ').trim()));
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const clr = async () => pg.evaluate(() => document.querySelectorAll('.toast').forEach(t => t.remove()));   // eski xabar keyingi tekshiruvni aldamasin
    const click = async sel => { await clr(); await pg.click(sel); };
    const waitToast = async re => pg.waitForFunction(r => [...document.querySelectorAll('.toast')].some(e => new RegExp(r).test(e.textContent)), re, { timeout: 15000 }).then(() => true).catch(() => false);
    return { ctx, pg, dialogs, tab, toasts, modalTxt, acReady, openList, rows, printed, waitToast, click };
  }
  const cp = (where, cols) => q(`select ${cols} from public.fin_counterparties where ${where}`);
  const xlsx = async (u, btn) => {
    const [dl] = await Promise.all([u.pg.waitForEvent('download', { timeout: 20000 }), u.pg.click(btn)]);
    const nm = dl.suggestedFilename(), wb = XLSX.read(fs.readFileSync(await dl.path()), { type: 'buffer' });
    return { nm, sheet: wb.SheetNames[0], data: XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, raw: true, defval: '' }) };
  };

  // ---------------- 1) Moliya menejeri: ro'yxat, qidiruv, filtr
  const m = await login(ids.R_MOL);
  await m.acReady();
  ok('«Buxgalteriya»: «🏢 Kontragentlar» tugmasi bor', !!(await m.pg.$('#ac-cp')));
  await m.openList();
  {
    const r = await m.rows();
    ok('ro‘yxat: 3 ta faol kontragent; YaTT — «turi tasdiqlanmagan»; bank — «Bank» turi', r.length === 3 && r.some(x => /Sinov Usta YaTT/.test(x) && /turi tasdiqlanmagan/.test(x)) && r.some(x => /Sinov Bank ATB/.test(x) && /Bank/.test(x)), r);
    await m.pg.fill('#cp-q', 'usta'); await m.pg.waitForTimeout(200);
    const r1 = await m.rows();
    await m.pg.fill('#cp-q', ''); await m.pg.selectOption('#cp-kind', 'bank'); await m.pg.waitForTimeout(200);
    const r2 = await m.rows();
    await m.pg.selectOption('#cp-kind', ''); await m.pg.selectOption('#cp-act', 'off'); await m.pg.waitForTimeout(200);
    const e3 = await m.pg.$eval('#cp-list', e => e.innerText);
    await m.pg.selectOption('#cp-act', 'on'); await m.pg.waitForTimeout(200);
    ok('qidiruv («usta» — 1), tur filtri (bank — 1), nofaollar — yo‘q', r1.length === 1 && /Sinov Usta YaTT/.test(r1[0]) && r2.length === 1 && /Sinov Bank ATB/.test(r2[0]) && /topilmadi/.test(e3), [r1, r2, e3]);
  }

  // ---------------- 2) yangi karta: oynaning tekshiruvlari, saqlash
  await m.pg.click('#cp-new'); await m.pg.waitForSelector('#cf-save', { timeout: 10000 });
  await m.pg.fill('#cf-name', 'Sinov Elektr MChJ'); await m.pg.fill('#cf-stir', '00000020');
  await m.click('#cf-save'); await m.pg.waitForTimeout(400);
  const t1 = await m.toasts();
  await m.pg.fill('#cf-stir', '000 000 201'); await m.pg.fill('#cf-acc', '0000 0000 0000 0000 0201');
  await m.click('#cf-save'); await m.pg.waitForTimeout(400);
  const t2 = await m.toasts();
  ok('oyna tekshiruvi: STIR 8 raqam — rad; hisob raqami MFO‘siz — rad (serverga yuborilmaydi)', /STIR — 9 ta raqam/.test(t1) && /MFO kodini ham/.test(t2) && cp(`name = 'Sinov Elektr MChJ'`, 'count(*)') === '0', [t1, t2]);
  await m.pg.fill('#cf-mfo', '00201'); await m.pg.fill('#cf-bank', 'Sinov bank filiali');
  await m.pg.fill('#cf-cno', '№ 15'); await m.pg.fill('#cf-cd', today);
  await m.click('#cf-save');
  const sv1 = await m.waitToast('Saqlandi ✓');
  const re1 = await m.pg.waitForFunction(() => /Kontragent kartasi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 15000 }).then(() => true).catch(() => false);
  ok('saqlandi: «Saqlandi ✓», karta qayta ochildi (o‘zgartirish oynasi)', sv1 && re1, [sv1, re1]);
  const S20 = cp(`name = 'Sinov Elektr MChJ'`, 'id');
  ok('bazada: STIR va hisob raqami bo‘shliqsiz, shartnoma №siz, sana; versiya 0; Moliya menejeri — turi tasdiqlanmagan (yuridik shaxs — kerak emas)',
    cp(`id = '${S20}'`, `stir || '|' || account || '|' || mfo || '|' || "bankName" || '|' || "contractNo" || '|' || "contractDate" || '|' || rev || '|' || coalesce("kindConfirmedBy", '-')`)
      === `000000201|00000000000000000201|00201|Sinov bank filiali|15|${today}|0|-`, cp(`id = '${S20}'`, 'to_jsonb(fin_counterparties)::text'));
  ok('karta: hisob raqami guruhlab ko‘rsatiladi (00000 000 0 00000000 201)', (await m.pg.$eval('#cf-acc', e => e.value)) === '00000 000 0 00000000 201');

  // ---------------- 3) shu STIR boshqa kartada — ogohlantirish, tasdiqlansa yoziladi
  await m.pg.click('#cf-back'); await m.pg.waitForSelector('#cp-new', { timeout: 10000 });
  await m.pg.click('#cp-new'); await m.pg.waitForSelector('#cf-save', { timeout: 10000 });
  await m.pg.fill('#cf-name', 'Sinov Elektr filiali'); await m.pg.fill('#cf-stir', '000000201');
  const nd = m.dialogs.length;
  await m.click('#cf-save');
  await m.waitToast('Saqlandi ✓');
  const dg = m.dialogs.slice(nd).join(' || ');
  ok('shu STIR: ogohlantirish (boshqa kartaning nomi bilan), tasdiqlandi — ikkinchi karta yozildi',
    /STIR 000000201 ro‘yxatdagi boshqa kontragentda bor: «Sinov Elektr MChJ»/.test(dg.replace(/'/g, '‘')) && cp(`stir = '000000201'`, 'count(*)') === '2', dg);

  // ---------------- 4) kartani o'zgartirish; bir vaqtda boshqa foydalanuvchi saqlagan
  await m.pg.click('#cf-back'); await m.pg.waitForSelector(`[data-card="${S20}"]`, { timeout: 10000 });
  await m.pg.click(`[data-card="${S20}"]`); await m.pg.waitForSelector('#cf-save', { timeout: 10000 });
  asUser(ACC, `select public.fin_cp_save(jsonb_build_object('id', '${S20}', 'rev', 0, 'kind', 'supplier', 'name', 'Sinov Elektr MChJ', 'stir', '000000201', 'account', '00000000000000000201', 'mfo', '00201', 'bankName', 'Sinov bank filiali', 'contractNo', '15', 'contractDate', '${today}', 'note', 'Buxgalter izohi'))::text`);
  await m.pg.fill('#cf-note', 'Menejer izohi');
  await m.click('#cf-save');
  const chg = await m.waitToast('shu orada boshqa foydalanuvchi');
  await m.pg.waitForTimeout(400);
  ok('bir vaqtda tahrirlash: «karta shu orada o‘zgartirilgan» — karta yangi ma’lumot bilan qayta ochildi; menejer izohi yozilmadi',
    chg && (await m.pg.$eval('#cf-note', e => e.value)) === 'Buxgalter izohi' && cp(`id = '${S20}'`, `note || '|' || rev`) === 'Buxgalter izohi|1', cp(`id = '${S20}'`, `note || '|' || rev`));
  await m.pg.fill('#cf-cu', `${+today.slice(0, 4) + 1}${today.slice(4)}`);
  await m.click('#cf-save');
  ok('qayta saqlandi: shartnoma muddati yozildi, versiya 2', await m.waitToast('Saqlandi ✓') && cp(`id = '${S20}'`, `"contractUntil" || '|' || rev`) === `${+today.slice(0, 4) + 1}${today.slice(4)}|2`, cp(`id = '${S20}'`, `"contractUntil" || '|' || rev`));

  // ---------------- 5) eski noto'g'ri STIR'li karta — STIR o'zgarmasa saqlanadi
  await m.pg.click('#cf-back'); await m.pg.waitForSelector('[data-card="cp_o20"]', { timeout: 10000 });
  await m.pg.click('[data-card="cp_o20"]'); await m.pg.waitForSelector('#cf-save', { timeout: 10000 });
  await m.pg.fill('#cf-bank', 'Sinov bank');
  await m.click('#cf-save');
  ok('eski karta (STIR 7 raqam, o‘zgarmagan): boshqa maydon saqlandi', await m.waitToast('Saqlandi ✓') && cp(`id = 'cp_o20'`, `stir || '|' || "bankName"`) === '1234567|Sinov bank', cp(`id = 'cp_o20'`, `stir || '|' || "bankName"`));
  await m.pg.fill('#cf-stir', '1234568'); await m.click('#cf-save'); await m.pg.waitForTimeout(400);
  ok('… STIR o‘zgartirilsa — 9 raqam talab qilinadi', /STIR — 9 ta raqam/.test(await m.toasts()) && cp(`id = 'cp_o20'`, 'stir') === '1234567');

  // ---------------- 6) ko'chirma: kassa orderi va bank hujjati
  const k2 = pay(S20, 300000, 'EX-32', 'Hisob-faktura № 7', 'e20-k2-0001');
  const xd = JSON.parse(asUser(ids.R_MOL, `select public.fin_exp_save('{"clientRef":"e20-xd-00000001","method":"bank","date":"${today}","counterpartyId":"${S20}","docNo":"501","lines":[{"articleId":"EX-11","amount":1200000}]}'::jsonb)::text`));
  ok('tayyorgarlik: kontragentga KO-2 (300 000) va bank hujjati (1 200 000)', !!k2.id && !!xd.id, [k2, xd]);
  await m.pg.click('#cf-back'); await m.pg.waitForSelector(`[data-stmt="${S20}"]`, { timeout: 10000 });
  await m.pg.click(`[data-stmt="${S20}"]`);
  await m.pg.waitForSelector('#cs-sum', { timeout: 15000 });
  {
    const per = [await m.pg.$eval('#cs-from', e => e.value), await m.pg.$eval('#cs-to', e => e.value)];
    const sum = await m.pg.$eval('#cs-sum', e => e.textContent.replace(/\s+/g, ' '));
    const tr = await m.pg.$$eval('#cs-tbl tbody tr', xs => xs.map(x => x.innerText.replace(/\s+/g, ' ').trim()));
    ok('ko‘chirma: davr — yil boshidan bugungacha; jamlar (davrda berildi 1 500 000, 2 ta; sof 1 500 000)', per[0] === y0 && per[1] === today
      && /davrda: berildi 1 500 000 so‘m, olindi 0 so‘m \(2 ta\)/.test(sum) && /sof 1 500 000 so‘m/.test(sum), [per, sum]);
    ok('ko‘chirma qatorlari: KO-2 (naqd, Kanselyariya, asos) va bank hujjati (№ 501, Elektr energiyasi), yig‘ma sof', tr.length === 2
      && tr.some(x => /KO-2 № \d+/.test(x) && /Naqd/.test(x) && /Hisob-faktura № 7/.test(x) && /300 000/.test(x))
      && tr.some(x => /№ 501/.test(x) && /Bank/.test(x) && /Elektr energiyasi/.test(x) && /1 500 000/.test(x)), tr);
    const before = (await m.printed()).length;
    await m.pg.click('#cs-print'); await m.pg.waitForTimeout(1500);
    const pr = (await m.printed()).slice(before).join(' || ');
    ok('chop etildi: sarlavha, davr, kontragent rekvizitlari, shartnoma, jamlar', /KONTRAGENT KO‘CHIRMASI/.test(pr) && pr.includes(`Davr: ${dm(y0)} – ${dm(today)}`)
      && /Sinov Elektr MChJ/.test(pr) && /000000201/.test(pr) && /MFO 00201/.test(pr) && /№ 15/.test(pr) && /1 500 000/.test(pr) && /2 ta operatsiya/.test(pr), pr.slice(0, 700));
    const x = await xlsx(m, '#cs-xlsx');
    const hi = x.data.findIndex(r => r[0] === '№'), body = x.data.slice(hi + 1).filter(r => typeof r[0] === 'number');
    ok('Excel: nomi RP-10_<id>_<davr>.xlsx (ismsiz emas — yuridik shaxs), varaq «RP-10», 2 qator, summalar — son', x.nm === `RP-10_${S20}_${y0}_${today}.xlsx` && x.sheet === 'RP-10'
      && body.length === 2 && body.some(r => r[6] === 300000) && body.some(r => r[6] === 1200000) && x.data.some(r => r[1] === 'Sinov Elektr MChJ'), [x.nm, x.sheet, body]);
  }

  // ---------------- 7) jismoniy shaxs ko'chirmasi: Moliya menejeriga ismsiz fayl (FD-28)
  await m.pg.click('#cs-back'); await m.pg.waitForSelector('[data-stmt="cp_p20"]', { timeout: 10000 });
  await m.pg.click('[data-stmt="cp_p20"]'); await m.pg.waitForSelector('#cs-sum', { timeout: 15000 });
  {
    const scr = await m.pg.$eval('#cs-tbl', e => e.innerText).catch(() => '');
    const x = await xlsx(m, '#cs-xlsx');
    const flat = x.data.map(r => r.join('|')).join('\n');
    ok('YaTT: ekranda asos bor; Excel — «-ismsiz», izoh qatori, ID bilan; ism va asos matni yo‘q', /Xizmat — Sinov Usta/.test(scr) && /-ismsiz\.xlsx$/.test(x.nm)
      && /Ismsiz nusxa \(FD-28\)/.test(flat) && /ID cp_p20/.test(flat) && !/Sinov Usta/.test(flat) && /\b45000\b/.test(flat), [x.nm, flat.slice(0, 600)]);
    ok('… saqlash xabari: ismli nusxa faqat Direktorda', await m.waitToast('ismli nusxa faqat Direktorda'));
  }
  await m.ctx.close();
  {
    const d = await login(ids.R_DIR);
    await d.acReady(); await d.openList();
    await d.pg.click('[data-stmt="cp_p20"]'); await d.pg.waitForSelector('#cs-sum', { timeout: 15000 });
    const x = await xlsx(d, '#cs-xlsx');
    const flat = x.data.map(r => r.join('|')).join('\n');
    ok('Direktor: YaTT ko‘chirmasi Excel‘da to‘liq (ism, asos), «-ismsiz»siz', !/-ismsiz/.test(x.nm) && /Sinov Usta YaTT/.test(flat) && /Xizmat — Sinov Usta/.test(flat) && !/Ismsiz nusxa/.test(flat), [x.nm, flat.slice(0, 400)]);
    await d.ctx.close();
  }

  // ---------------- 8) buxgalter: kartani yuritadi (turini tasdiqlaydi)
  {
    const a = await login(ACC);
    await a.acReady();
    ok('buxgalter: «🏢 Kontragentlar» bor («Buxgalteriya» faqat ko‘rish bo‘lsa ham), «+ Xarajat qo‘shish» yo‘q', !!(await a.pg.$('#ac-cp')) && !(await a.pg.$('#ac-add')));
    await a.openList();
    await a.pg.click('[data-card="cp_p20"]'); await a.pg.waitForSelector('#cf-save', { timeout: 10000 });
    const t = await a.modalTxt();
    await a.pg.fill('#cf-stir', '000000401');
    await a.click('#cf-save');
    ok('buxgalter saqladi: turi tasdiqlandi, STIR yozildi; ro‘yxatda «turi tasdiqlanmagan» yo‘q', /Turi hali tasdiqlanmagan/.test(t) && await a.waitToast('Saqlandi ✓')
      && cp(`id = 'cp_p20'`, `stir || '|' || coalesce("kindConfirmedBy", '-')`) === `000000401|${ACC}`, cp(`id = 'cp_p20'`, `stir || '|' || coalesce("kindConfirmedBy", '-')`));
    await a.pg.click('#cf-back'); await a.pg.waitForSelector('#cp-list table', { timeout: 10000 });
    ok('… ro‘yxatda YaTT — tasdiqlangan', !(await a.rows()).some(x => /Sinov Usta YaTT/.test(x) && /turi tasdiqlanmagan/.test(x)));
    await a.ctx.close();
  }

  // ---------------- 9) telefon ekrani (390 px): ro'yxat va karta gorizontal siljimaydi
  {
    const p = await login(ids.R_MOL, { width: 390, height: 844 });
    await p.acReady(); await p.openList();
    const ov1 = await p.pg.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, mw: Math.round(document.querySelector('#modal').getBoundingClientRect().right) }));
    await p.pg.screenshot({ path: `${OUT}/k20-mol-${UI}-390-list.png`, fullPage: false });
    await p.pg.click(`[data-card="${S20}"]`); await p.pg.waitForSelector('#cf-save', { timeout: 10000 });
    const ov2 = await p.pg.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, mw: Math.round(document.querySelector('#modal').getBoundingClientRect().right) }));
    await p.pg.screenshot({ path: `${OUT}/k20-mol-${UI}-390-card.png`, fullPage: false });
    ok('telefon (390 px): ro‘yxat va karta ekranga sig‘adi (gorizontal siljish yo‘q)', ov1.sw <= ov1.cw + 1 && ov1.mw <= ov1.cw + 1 && ov2.sw <= ov2.cw + 1 && ov2.mw <= ov2.cw + 1, [ov1, ov2]);
    await p.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.log('XATO ' + (e.stack || e)); process.exit(1); });
