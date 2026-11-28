// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.6 2-qism (reliz 25) — avans hisoboti cheklari
//   surati va hisobot muddati sozlamasi / yangi avansni bloklash brauzerda.
//   1) Moliya menejeri: «Avans hisoboti» — cheklar surati (PNG va PDF; matn fayli — rad), «Tasdiqqa yuborish»: fayllar yopiq «receipts»
//      bucket'iga yuklanadi va hujjatga biriktiriladi (bazada va saqlash joyida 2 ta).
//   2) Direktor: so'rovlar jadvalida «📎 2» — ro'yxat (asl nomlari), «Ochish» — imzolangan havola yangi oynada; fayl qo'shish (3 ta); «Tasdiqlash»
//      bo'limida ham «📎 3»; tasdiq oynasida «Cheklar surati: 3 ta»; tasdiqdan keyin dalolatnomalar ro'yxatida «📎 3».
//   3) Kassir: «📎» tugmasi yo'q; REST — fayllar ro'yxati va imzolangan havola rad.
//   4) Direktor: «⚙ Sozlamalar» — avans hisoboti muddati (standart 3; 31 — rad) → 2, bloklash yoqildi (bazada).
//   5) Server soati +5 kun: kassir «Hisobdorga avans» — rad (muddati o'tgan avans), hujjat yozilmaydi; RP-07 — muddat 2 ish kuni, «muddati o'tgan».
//   6) Telefon (390 px) — fayllar oynasi. 7) Sahifa xatolari yo'q.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa27.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const denied = (uid, sql) => { try { asUser(uid, sql); return false; } catch (e) { return /Ruxsat yo|42501|permission denied/.test(String((e && (e.stderr || e.message)) || '')); } };
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const nb = s => String(s || '').replace(/[\u00a0\u202f]/g, ' ');
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=', 'base64');
const PDF = Buffer.from('%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n');
(async () => {
  const b = await E.launch();
  const d0 = q('select app.fin_today()');
  const T1 = `teachers:${ids.T1}`;
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${d0}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${d0}"}'::jsonb)`);
  const a0 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_accountable","amount":100000,"partyType":"employee","partyId":"${T1}","basis":"Xojalik xaridi","clientRef":"e27-adv-0001"}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${a0.id}')::text`); asUser(ids.R_KAS, `select public.kassa_doc_pay('${a0.id}')::text`);
  ok('tayyorgarlik: o‘qituvchida 100 000 hisobot qilinmagan avans', q(`select trim_scale(app.kassa_acc_open('${T1}'))`) === '100000');

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
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, toasts };
  }

  // ---- 1) Moliya menejeri: avans hisoboti cheklar surati bilan
  const m = await login(ids.R_MOL); await m.kassaReady();
  await m.pg.click('#ks-adv'); await m.pg.waitForSelector('#av-p', { timeout: 15000 });
  await m.pg.selectOption('#av-p', T1);
  await m.pg.selectOption('[data-aart="0"]', 'EX-16');
  await m.pg.fill('[data-aamt="0"]', '30000'); await m.pg.fill('[data-anote="0"]', 'Chek 5, bugun');
  ok('«Avans hisoboti» oynasida «Cheklar surati» maydoni (rasm yoki PDF, bir nechta)', (await m.pg.$eval('#av-files', e => e.accept + ':' + e.multiple).catch(() => '')) === 'image/jpeg,image/png,application/pdf:true');
  await m.pg.setInputFiles('#av-files', [{ name: 'eslatma.txt', mimeType: 'text/plain', buffer: Buffer.from('x') }]);
  await m.pg.waitForTimeout(300);
  const t1 = await m.toasts();
  ok('matn fayli — rad (faqat rasm yoki PDF), ro‘yxatga qo‘shilmaydi', /faqat rasm \(JPEG, PNG\) yoki PDF/.test(t1) && !/eslatma/.test(await m.pg.$eval('#av-flist', e => e.textContent)), t1);
  await m.pg.setInputFiles('#av-files', [{ name: 'chek-5.png', mimeType: 'image/png', buffer: PNG }, { name: 'hisob-faktura.pdf', mimeType: 'application/pdf', buffer: PDF }]);
  await m.pg.waitForTimeout(300);
  const fl = nb(await m.pg.$eval('#av-flist', e => e.textContent));
  ok('tanlangan fayllar ro‘yxatda (2 ta)', /chek-5\.png/.test(fl) && /hisob-faktura\.pdf/.test(fl), fl);
  await m.pg.click('#av-save'); await m.modalGone().catch(() => {}); await m.pg.waitForTimeout(1000);
  const adoc = q(`select id from public.cash_docs where op = 'nc_adv_report' order by "createdAt" desc limit 1`);
  const fr = q(`select string_agg(name, ',' order by name) || ':' || count(*) || ':' || count(*) filter (where "addedBy" = '${ids.R_MOL}') from public.cash_doc_files where "docId" = '${adoc}'`);
  const so = q(`select count(*) from storage.objects o join public.cash_doc_files f on f.path = o.name where o.bucket_id = 'receipts' and f."docId" = '${adoc}'`);
  ok('hisobot tasdiqqa yuborildi: 2 ta fayl yopiq «receipts» saqlash joyiga yuklandi va hujjatga biriktirildi (asl nomi, kim yuklagan)', q(`select status from public.cash_docs where id = '${adoc}'`) === 'draft' && fr === 'chek-5.png,hisob-faktura.pdf:2:2' && so === '2', [fr, so]);
  await m.ctx.close();

  // ---- 2) Direktor: ko'rish, ochish, qo'shish, tasdiq
  const d = await login(ids.R_DIR); await d.kassaReady();
  const fb = await d.pg.waitForSelector(`[data-advreq="${adoc}"] [data-advfiles="${adoc}"]`, { timeout: 15000 }).catch(() => null);
  ok('Direktor: so‘rovlar jadvalidagi avans hisobotida «📎 2» tugmasi', !!fb && /📎 2/.test(nb(await fb.textContent())), fb && await fb.textContent());
  if (fb) await fb.click();
  await d.pg.waitForSelector('#af-table', { timeout: 15000 }).catch(() => {});
  const lt = nb(await d.pg.$eval('#af-list', e => e.innerText).catch(() => ''));
  ok('fayllar oynasi: asl nomlari va kim qo‘shgan', /chek-5\.png/.test(lt) && /hisob-faktura\.pdf/.test(lt) && (await d.pg.$$('#af-table tbody tr')).length === 2, lt.slice(0, 300));
  const ob = await d.pg.$('xpath=//table[@id="af-table"]//tr[td[contains(., "chek-5.png")]]//button[@data-fopen]');
  let popUrl = '', popType = '';
  if (ob) {
    const [pop] = await Promise.all([d.ctx.waitForEvent('page', { timeout: 15000 }), ob.click()]);
    await pop.waitForURL(/\/storage\/v1\/object\/sign\/receipts\/adv\//, { timeout: 15000 }).catch(() => {});
    await pop.waitForLoadState().catch(() => {});
    popUrl = pop.url(); popType = await pop.evaluate(() => document.contentType).catch(() => ''); await pop.close();
  }
  ok('«Ochish» — fayl yangi oynada imzolangan havola bilan ochiladi (rasm)', /\/storage\/v1\/object\/sign\/receipts\/adv\/[0-9a-f-]{36}\.png\?token=/.test(popUrl) && popType === 'image/png', [popUrl, popType]);
  await d.pg.setInputFiles('#af-files', [{ name: 'chek-6.png', mimeType: 'image/png', buffer: PNG }]);
  await d.pg.click('#af-add');
  await d.pg.waitForFunction(() => document.querySelectorAll('#af-table tbody tr').length === 3, null, { timeout: 15000 }).catch(() => {});
  ok('fayl keyin qo‘shildi: oynada va bazada 3 ta', (await d.pg.$$('#af-table tbody tr')).length === 3 && q(`select count(*) from public.cash_doc_files where "docId" = '${adoc}'`) === '3' && /qo‘shildi: 1 ta/.test(await d.toasts()), await d.toasts());
  await d.pg.click('#m-cancel'); await d.modalGone().catch(() => {});
  await d.tab('approvals');
  const kf = await d.pg.waitForSelector(`[data-kfiles="${adoc}"]`, { timeout: 20000 }).catch(() => null);
  const kft = kf ? nb(await kf.textContent()) : ''; let kfn = 0;
  if (kf) { await kf.click(); await d.pg.waitForSelector('#af-table', { timeout: 15000 }).catch(() => {}); kfn = (await d.pg.$$('#af-table tbody tr')).length;
    await d.pg.click('#m-cancel').catch(() => {}); await d.modalGone().catch(() => {}); }
  ok('«Tasdiqlash» bo‘limida ham «📎 3» — fayllar oynasi ochiladi', !!kf && /📎 3/.test(kft) && kfn === 3, [kft, kfn]);
  await d.kassaReady();
  const ab = await d.pg.waitForSelector(`[data-appr="${adoc}"]`, { timeout: 15000 }).catch(() => null);
  if (ab) { await ab.click(); await d.pg.waitForFunction(id => !document.querySelector(`[data-appr="${id}"]`), adoc, { timeout: 15000 }).catch(() => {}); await d.pg.waitForTimeout(800); }
  ok('tasdiq oynasida «Cheklar surati: 3 ta»; hisobot o‘tkazildi', d.dialogs.some(x => /Avans hisoboti tasdiqlansinmi/.test(x) && /Cheklar surati: 3 ta/.test(x)) && q(`select status from public.cash_docs where id = '${adoc}'`) === 'posted', d.dialogs);
  await d.kassaReady();
  const fb2 = await d.pg.$(`#ks-acts [data-advfiles="${adoc}"]`);
  ok('dalolatnomalar ro‘yxatida (o‘tkazilgan hisobot) «📎 3»', !!fb2 && /📎 3/.test(nb(await fb2.textContent())), fb2 && await fb2.textContent());
  await d.ctx.close();

  // ---- 3) Kassir: fayllarga kirish yo'q
  const k = await login(ids.R_KAS); await k.kassaReady();
  ok('kassir: «📎» tugmasi yo‘q', !(await k.pg.$('[data-advfiles]')));
  const path0 = q(`select path from public.cash_doc_files where "docId" = '${adoc}' order by path limit 1`);
  const sig = await k.pg.evaluate(async p => { const s = JSON.parse(localStorage.getItem('sb-127-auth-token') || '{}');
    const r = await fetch('/storage/v1/object/sign/receipts/' + p, { method: 'POST', headers: { Authorization: 'Bearer ' + s.access_token, 'Content-Type': 'application/json' }, body: '{"expiresIn":60}' });
    return r.status; }, path0);
  ok('kassir: fayllar ro‘yxati (REST) va imzolangan havola — rad', denied(ids.R_KAS, `select public.kassa_doc_files('${adoc}')::text`) && sig === 400, sig);
  await k.ctx.close();

  // ---- 4) Direktor: «⚙ Sozlamalar» — avans hisoboti muddati va bloklash
  const d2 = await login(ids.R_DIR); await d2.kassaReady();
  await d2.pg.click('#ks-set'); await d2.pg.waitForSelector('#kx-advdays', { timeout: 15000 });
  const dv = await d2.pg.$eval('#kx-advdays', e => e.value), bv = await d2.pg.$eval('#kx-advblock', e => e.checked);
  ok('«⚙ Sozlamalar»: avans hisoboti muddati — standart 3 ish kuni, bloklash o‘chiq', dv === '3' && bv === false, [dv, bv]);
  await d2.pg.fill('#kx-advdays', '31'); await d2.pg.click('#kx-save'); await d2.pg.waitForTimeout(500);
  ok('noto‘g‘ri muddat (31) — saqlanmaydi', /1 dan 30 gacha/.test(await d2.toasts()) && q(`select coalesce(extra ->> 'advDays', '-') from public.fin_org where id = 'main'`) === '-', await d2.toasts());
  await d2.pg.fill('#kx-advdays', '2'); await d2.pg.check('#kx-advblock'); await d2.pg.click('#kx-save'); await d2.modalGone().catch(() => {}); await d2.pg.waitForTimeout(600);
  ok('saqlandi: muddat 2 ish kuni, bloklash yoqiq (bazada)', q(`select (extra ->> 'advDays') || ':' || (extra ->> 'advBlock') from public.fin_org where id = 'main'`) === '2:true',
    q(`select extra::text from public.fin_org where id = 'main'`));
  await d2.ctx.close();

  // ---- 5) Server soati +5 kun: muddati o'tgan avans — yangi avans rad (kun yopiladi — keyingi kun sahifasi odatdagidek)
  const bal = q(`select app.kassa_day_balance(d.id) from public.cash_days d where d.desk = 'main' and d.day = '${d0}'`);
  asUser(ids.R_KAS, `select public.kassa_day_close('{"desk":"main","day":"${d0}","counted":${bal}}'::jsonb)::text`);
  q(`insert into app.fin_clock (id, t) values (1, now() + interval '5 days') on conflict (id) do update set t = excluded.t`);
  try {
    const k2 = await login(ids.R_KAS); await k2.kassaReady();
    await k2.pg.click('#ks-out'); await k2.pg.waitForSelector('#kf-op', { timeout: 15000 });
    await k2.pg.selectOption('#kf-op', 'out_accountable'); await k2.pg.waitForSelector('#kf-pe', { timeout: 15000 });
    await k2.pg.selectOption('#kf-pe', T1); await k2.pg.fill('#kf-amt', '50000'); await k2.pg.fill('#kf-basis', 'Yana xarid');
    const n0 = q(`select count(*) from public.cash_docs where op = 'out_accountable'`);
    await k2.pg.click('#kf-save'); await k2.pg.waitForTimeout(1500);
    const tt = await k2.toasts();
    ok('bloklash: muddati o‘tgan avansi bor o‘qituvchiga yangi «Hisobdorga avans» — rad (sana va muddat bilan), hujjat yozilmaydi',
      /hisobot qilinmagan avans bor/.test(tt) && /2 ish kuni/.test(tt) && q(`select count(*) from public.cash_docs where op = 'out_accountable'`) === n0, tt);
    await k2.pg.click('#m-cancel').catch(() => {}); await k2.modalGone().catch(() => {});
    await k2.pg.click('#ks-acc'); await k2.pg.waitForSelector('#acc-list', { timeout: 15000 }).catch(() => {});
    const al = nb(await k2.pg.$eval('#modal', e => e.innerText).catch(() => ''));
    ok('RP-07: muddat — 2 ish kuni, o‘qituvchi avansi «muddati o‘tgan»', /Avans hisoboti muddati — 2 ish kuni/.test(al) && /muddati o‘tgan/.test(al), al.slice(0, 400));
    await k2.ctx.close();
  } finally { q(`delete from app.fin_clock where id = 1`); }

  // ---- 6) telefon: fayllar oynasi
  const ph = await login(ids.R_DIR, { width: 390, height: 844 }); await ph.kassaReady();
  const pb = await ph.pg.$(`#ks-acts [data-advfiles="${adoc}"]`);
  if (pb) { await pb.click(); await ph.pg.waitForSelector('#af-table', { timeout: 15000 }).catch(() => {}); }
  const ov = await ph.pg.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  await ph.pg.screenshot({ path: `${OUT}/k27-telefon.png` }).catch(() => {});
  ok('telefon (390 px): fayllar oynasi ochildi, sahifa gorizontal siljimaydi', !!pb && !!(await ph.pg.$('#af-table')) && ov <= 1, ov);
  await ph.ctx.close();

  ok('sahifa xatolari yo‘q', allErrs.length === 0, allErrs);
  await b.close();
  const f = res.filter(r => !r.ok).length;
  console.log(`JAMI (v2): ${res.length - f}/${res.length}`);
  process.exit(f ? 1 : 0);
})().catch(e => { try { q(`delete from app.fin_clock where id = 1`); } catch (_) {} console.error('XATO', e && e.stack || e); process.exit(2); });
