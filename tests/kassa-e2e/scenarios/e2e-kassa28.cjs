// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.9 «Huquqlar II» (reliz 26) brauzerda —
//   pul jadvallariga to'g'ridan-to'g'ri yozuv detektori / qulfi va uni almashtirgan funksiyalar.
//   1) Direktor: to'lov tarixida «🚫 Bekor» (qo'llanmagan yozuv) — server funksiyasi (kim — server), detektor jurnali bo'sh.
//   2) Direktor: «↩️ Qo'lda qaytarilishi kerak» ro'yxatida «✓ Bajarildi» — server funksiyasi, jurnal bo'sh.
//   3) Direktor: «🔍 Moliya tekshiruvi» → «🔧 Qo'llash» — kanal 'fix' (naqd emas), jurnal bo'sh.
//   4) G'aznachi (RF-11 — kassir bilan teng): fakturani bekor qilish tugmasi yo'q (moliya menejerida bor), bazada moliya huquqi yo'q.
//   5) Marketing (RF-12): sahifa xarajatlarni yig'ma funksiyadan oladi (fin_marketing_spend), «Buxgalteriya» qatorlarini so'ramaydi.
//   6) Direktor «⚙ Sozlamalar»: detektor holati; 7 kun bo'lmaguncha yopish belgisi o'chiq; 7 kun toza — yopildi (tasdiq oynasi bilan),
//      nazorat ro'yxatida «yopilgan»; qulf ostida «Bekor» funksiyasi ishlaydi, eski sahifaning to'g'ridan-to'g'ri yozuvi — rad (fin:direct);
//      orqaga qaytarish (ochish); yozuv bo'lsa — ro'yxat va soni, yopish belgisi o'chiq, nazorat ro'yxatida «diqqat».
//   7) Telefon (390 px) — sozlamalar. 8) Sahifa xatolari yo'q; oxirida detektor jurnali bo'sh (sahifaning birorta amali pul jadvaliga
//      to'g'ridan-to'g'ri yozmadi).
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa28.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const deniedRe = (uid, sql, re) => { try { asUser(uid, sql); return false; } catch (e) { return re.test(String((e && (e.stderr || e.message)) || '')); } };
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const nb = s => String(s || '').replace(/[\u00a0\u202f]/g, ' ');
const nlog = () => q('select count(*) from public.fin_direct_log');
(async () => {
  const b = await E.launch();
  const d0 = q('select app.fin_today()'), mon = d0.slice(0, 7);
  const TRS = 'e28-trs-0001', MKT = 'e28-mkt-0001';
  // ---- tayyorgarlik (psql — detektor yozmaydi): yangi o'quvchi, to'lovlar, faktura, marketing xarajati, g'aznachi va marketing hisoblari
  const SID = 'IQ-9928';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values
       ('${TRS}', 'gaznachi28@e2e.test', 'Sinov G''aznachi', 'treasurer', 'active', true, '[]'),
       ('${MKT}', 'marketing28@e2e.test', 'Sinov Marketolog', 'marketing_mgr', 'active', true, '[]')
     on conflict (id) do update set role = excluded.role, status = excluded.status`);
  const S1 = q(`select "studentId" from public.students where "studentId" is not null and "studentId" <> '' order by "studentId" limit 1`);
  q(`insert into public.students (id, "studentId", name, grade, "classLetter", lang, track, "payStatus", "activeFrom") values ('${SID}', '${SID}', 'Sinov Tekshiruv', 4, 'A', 'uz', 'umumiy', 'active', '${mon}-01') on conflict (id) do nothing`);
  q(`insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status) values ('${SID}__${mon}', '${SID}', 'Sinov Tekshiruv', '${mon}', 300000, 0, 'pending')`);
  q(`insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values
       ('e28-p1', '${S1}', 'bank', 100000, 'pending', true, '{}', now()),
       ('e28-p4', '${S1}', 'bank', 70000, 'pending', true, '{}', now()),
       ('e28-p2', '${S1}', 'uzum', 50000, 'reversed', true, '{"needsManualReverse": true, "reverseNote": "Sinov: qo''lda qaytaring"}', now()),
       ('e28-p3', '${SID}', 'click', 300000, 'applied', true, '{}', now())`);
  q(`insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values
       ('e28-p5', '${S1}', 'uzum', 40000, 'reversed', true, '{"needsManualReverse": true, "reverseNote": "Sinov: ikkinchi"}', now())`);
  // kassa ishga tushgan (nazorat ro'yxati — RP-06 — faqat ishlayotgan kassada ko'rinadi)
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${d0}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${d0}"}'::jsonb)`);
  q(`insert into public.expenses (id, date, month, category, amount, note, method) values ('e28-e1', '${d0}', '${mon}', 'Marketing', 1200000, 'Sinov reklama', 'bank'), ('e28-e2', '${d0}', '${mon}', 'Boshqa', 700000, 'Sinov', 'bank')`);
  ok('tayyorgarlik: to‘lovlar, faktura, xarajatlar yozildi, detektor jurnali bo‘sh', nlog() === '0' && q(`select count(*) from public.payments where id like 'e28-%'`) === '5', nlog());

  async function login(uid, vp) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 }, acceptDownloads: true });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (_) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage(); const dialogs = []; const reqs = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    pg.on('request', r => { const u = r.url(); if (u.includes('/rest/v1/')) reqs.push(u.replace(/^.*\/rest\/v1\//, '')); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(600); };
    const payReady = async () => { await tab('payments'); await pg.waitForFunction(() => document.querySelector('#pm-body') && !document.querySelector('#pm-body .loading'), null, { timeout: 30000 }); await pg.waitForTimeout(800); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const toasts = async () => nb(await pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | ')));
    return { ctx, pg, dialogs, reqs, tab, kassaReady, payReady, modalGone, toasts };
  }

  // ---- 1) Direktor: «🚫 Bekor» to'lov tarixida
  const d = await login(ids.R_DIR); await d.payReady();
  const ph1 = await d.pg.waitForSelector(`#pm-body [data-ph="${S1}"]`, { timeout: 15000 }).catch(() => null);
  if (ph1) await ph1.click();
  const hb = await d.pg.waitForSelector('[data-cancelpay="e28-p1"]', { timeout: 15000 }).catch(() => null);
  ok('to‘lov tarixida qo‘llanmagan yozuvga «🚫 Bekor» tugmasi', !!hb);
  if (hb) { await hb.click(); await d.pg.waitForTimeout(1200); }
  ok('«Bekor» server funksiyasi orqali: holat «bekor», kim — server qo‘ydi (Direktor), detektor jurnali bo‘sh',
    q(`select status || ':' || coalesce(raw ->> 'canceledBy', '-') from public.payments where id = 'e28-p1'`) === `canceled:${ids.R_DIR}` && nlog() === '0'
      && d.reqs.some(u => u.startsWith('rpc/fin_pay_cancel')), [q(`select status || ':' || coalesce(raw ->> 'canceledBy', '-') from public.payments where id = 'e28-p1'`), nlog()]);
  await d.pg.click('#m-cancel').catch(() => {}); await d.modalGone().catch(() => {});

  // ---- 2) «✓ Bajarildi» qo'lda qaytarish ro'yxatida
  await d.payReady();
  const mb = await d.pg.waitForSelector('[data-mrdone="e28-p2"]', { timeout: 15000 }).catch(() => null);
  ok('«↩️ Qo‘lda qaytarilishi kerak» ro‘yxatida «✓ Bajarildi» tugmasi', !!mb);
  if (mb) { await mb.click(); await d.pg.waitForTimeout(1200); }
  ok('«✓ Bajarildi» server funksiyasi orqali: belgi, kim — uid (email emas), jurnal bo‘sh',
    q(`select coalesce(raw ->> 'manualReverseDone', '-') || ':' || coalesce(raw ->> 'manualReverseBy', '-') from public.payments where id = 'e28-p2'`) === `true:${ids.R_DIR}` && nlog() === '0',
    [q(`select raw::text from public.payments where id = 'e28-p2'`), nlog()]);

  // ---- 3) «🔍 Moliya tekshiruvi» → «🔧 Qo'llash» — kanal 'fix'
  await d.payReady();
  await d.pg.click('#pm-audit').catch(() => {});
  const fx = await d.pg.waitForSelector(`[data-fix="${SID}"]`, { timeout: 20000 }).catch(() => null);
  ok('moliya tekshiruvida osilib qolgan pulga «🔧 Qo‘llash» tugmasi', !!fx);
  if (fx) { await fx.click(); await d.pg.waitForTimeout(1500); }
  ok('«Qo‘llash»: faktura to‘landi, kanal — «fix» (naqd emas), jurnal bo‘sh',
    q(`select status || ':' || coalesce(provider, '-') from public.invoices where id = '${SID}__${mon}'`) === 'paid:fix' && nlog() === '0',
    [q(`select status || ':' || coalesce(provider, '-') from public.invoices where id = '${SID}__${mon}'`), nlog(), await d.toasts()]);
  await d.pg.click('#m-cancel').catch(() => {}); await d.modalGone().catch(() => {});
  await d.ctx.close();

  // ---- 4) G'aznachi = kassir: fakturani bekor qilish tugmasi yo'q (moliya menejerida bor)
  const m = await login(ids.R_MOL); await m.payReady();
  const nm = await m.pg.$$eval('[data-cancel]', xs => xs.length).catch(() => 0);
  await m.ctx.close();
  const t = await login(TRS); await t.payReady();
  const nt = await t.pg.$$eval('[data-cancel]', xs => xs.length).catch(() => -1);
  const tv = nb(await t.pg.$eval('#pm-body', e => e.innerText).catch(() => ''));
  await t.ctx.close();
  ok('g‘aznachi: «To‘lovlar» ochiladi, fakturani bekor qilish tugmasi yo‘q; moliya menejerida — bor', nm > 0 && nt === 0 && tv.length > 0, [nm, nt]);
  ok('g‘aznachi bazada: moliya emas, kassir; fakturani bekor qilish (moliya huquqi) — rad',
    asUser(TRS, `select app.is_finance()::text || ':' || app.is_cashier()::text`) === 'false:true'
      && deniedRe(TRS, `select public.cancel_invoice('${S1}__${mon}')::text`, /forbidden|42501/));

  // ---- 5) Marketing: yig'ma funksiya, «Buxgalteriya» qatorlari so'ralmaydi
  const k = await login(MKT); await k.tab('marketing');
  await k.pg.waitForFunction(() => document.querySelector('#mk-body') && !document.querySelector('#mk-body .loading'), null, { timeout: 30000 }).catch(() => {});
  await k.pg.waitForTimeout(800);
  const kv = nb(await k.pg.$eval('#mk-body', e => e.innerText).catch(() => ''));
  ok('marketing sahifasi ochildi (CAC kartasi), xarajat yig‘ma funksiyadan (fin_marketing_spend) — expenses jadvali so‘ralmadi',
    /CAC/.test(kv) && k.reqs.some(u => u.startsWith('rpc/fin_marketing_spend')) && !k.reqs.some(u => /^expenses(\?|$)/.test(u)), [kv.slice(0, 200), k.reqs.filter(u => /expenses|marketing/.test(u))]);
  ok('marketing bazada: expenses qatorlari ko‘rinmaydi, yig‘ma — shu oy «Marketing» summasi',
    asUser(MKT, `select count(*)::text from public.expenses`) === '0' && JSON.parse(asUser(MKT, `select public.fin_marketing_spend()::text`))[mon] === 1200000);
  await k.ctx.close();

  // ---- 6) Direktor «⚙ Sozlamalar»: detektor va qulf
  const g = await login(ids.R_DIR); await g.kassaReady();
  const openSet = async () => { await g.pg.click('#ks-set'); await g.pg.waitForSelector('#kx-dguard', { timeout: 15000 }); await g.pg.waitForFunction(() => !/yuklanmoqda/i.test((document.querySelector('#kx-guard') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {}); };
  await openSet();
  let gt = nb(await g.pg.$eval('#kx-guard', e => e.textContent)), dis = await g.pg.$eval('#kx-dguard', e => e.disabled);
  ok('sozlamalar: detektor ishlayapti, 7 kunda yozuv yo‘q; 7 kun to‘lmaguncha yopish belgisi o‘chiq (sanasi bilan)',
    /ishlayapti; oxirgi 7 kunda — yozuv yo‘q/.test(gt) && /Yopish mumkin: \d{2}\.\d{2}\.\d{4} dan/.test(gt) && dis === true, [gt, dis]);
  await g.pg.click('#m-cancel').catch(() => {}); await g.modalGone().catch(() => {});
  q(`update public.fin_org set extra = extra || jsonb_build_object('guardSince', app.fin_today() - 8) where id = 'main'`);
  await openSet();
  gt = nb(await g.pg.$eval('#kx-guard', e => e.textContent)); dis = await g.pg.$eval('#kx-dguard', e => e.disabled);
  ok('7 kun toza: «Yopish mumkin», belgi faol', /Yopish mumkin \(7 kun yozuvsiz\)/.test(gt) && dis === false, [gt, dis]);
  await g.pg.check('#kx-dguard'); g.dialogs.length = 0;
  await g.pg.click('#kx-save'); await g.modalGone().catch(() => {}); await g.pg.waitForTimeout(800);
  ok('yopildi: tasdiq oynasi, bazada qulf yoqiq', g.dialogs.some(x => /To‘g‘ridan-to‘g‘ri yozuv yopilsinmi/.test(x)) && q(`select extra ->> 'directGuard' from public.fin_org where id = 'main'`) === 'true', [g.dialogs, q(`select extra::text from public.fin_org where id = 'main'`)]);
  await g.kassaReady();
  await g.pg.waitForSelector('[data-ctl="direct"]', { state: 'attached', timeout: 20000 }).catch(() => {});
  const cr = nb(await g.pg.$eval('[data-ctl="direct"]', e => e.dataset.level + ' | ' + e.textContent).catch(() => ''));
  ok('nazorat ro‘yxatida (RP-06) «To‘g‘ridan-to‘g‘ri yozuvlar» — yopilgan', /^ok \|/.test(cr) && /To‘g‘ridan-to‘g‘ri yozuvlar/.test(cr) && /yopilgan/.test(cr), cr);
  // qulf ostida: «Bekor» funksiyasi ishlaydi; eski sahifaning to'g'ridan-to'g'ri yozuvi — rad
  await g.payReady();
  const ph2 = await g.pg.waitForSelector(`#pm-body [data-ph="${S1}"]`, { timeout: 15000 }).catch(() => null);
  if (ph2) await ph2.click();
  const hb2 = await g.pg.waitForSelector('[data-cancelpay="e28-p4"]', { timeout: 15000 }).catch(() => null);
  if (hb2) { await hb2.click(); await g.pg.waitForTimeout(1200); }
  ok('qulf ostida «🚫 Bekor» (funksiya) ishlaydi; eski sahifadagidek to‘g‘ridan-to‘g‘ri yozuv — rad (fin:direct)',
    !!hb2 && q(`select status from public.payments where id = 'e28-p4'`) === 'canceled'
      && deniedRe(ids.R_DIR, `update public.payments set raw = raw || '{"e28": 1}' where id = 'e28-p4'`, /fin:direct|To'lov yozuvini faqat/));
  await g.pg.click('#m-cancel').catch(() => {}); await g.modalGone().catch(() => {});
  // orqaga qaytarish
  await g.kassaReady(); await openSet();
  await g.pg.uncheck('#kx-dguard'); g.dialogs.length = 0;
  await g.pg.click('#kx-save'); await g.modalGone().catch(() => {}); await g.pg.waitForTimeout(800);
  ok('ochildi (orqaga qaytarish): tasdiq oynasi, bazada qulf o‘chiq', g.dialogs.some(x => /Qulf ochilsinmi/.test(x)) && q(`select extra ->> 'directGuard' from public.fin_org where id = 'main'`) === 'false', g.dialogs);
  // yozuv bo'lsa — ro'yxat, soni, belgi o'chiq, nazoratda «diqqat»
  q(`insert into public.fin_direct_log (at, grp, tbl, op, row_id, via, api_role, actor_uid, actor_role, cols) values (app.fin_now(), 'payments', 'payments', 'UPDATE', 'e28-x', 'rest', 'authenticated', '${ids.R_DIR}', 'director', '{raw}')`);
  await g.kassaReady(); await openSet();
  gt = nb(await g.pg.$eval('#kx-guard', e => e.textContent)); dis = await g.pg.$eval('#kx-dguard', e => e.disabled);
  ok('yozuv bor: soni, ro‘yxat (nima, qayerda, manba, kim), yopish belgisi o‘chiq',
    /oxirgi 7 kunda — 1 ta yozuv/.test(gt) && /to‘lov yozuvi o‘zgardi \(payments · e28-x\) · sahifa · Sinov Direktor/.test(gt) && dis === true, [gt, dis]);
  await g.pg.click('#m-cancel').catch(() => {}); await g.modalGone().catch(() => {});
  await g.kassaReady();
  await g.pg.waitForSelector('[data-ctl="direct"]', { state: 'attached', timeout: 20000 }).catch(() => {});
  const cr2 = await g.pg.$eval('[data-ctl="direct"]', e => e.dataset.level + ' | ' + e.textContent).catch(() => '');
  ok('nazorat ro‘yxatida — «diqqat», soni bilan', /^warn \|/.test(cr2) && /1 ta/.test(nb(cr2)), cr2);
  q(`delete from public.fin_direct_log where row_id = 'e28-x'`);
  await g.ctx.close();

  // ---- 7) telefon: sozlamalar
  const ph = await login(ids.R_DIR, { width: 390, height: 844 }); await ph.kassaReady();
  await ph.pg.click('#ks-set').catch(() => {}); await ph.pg.waitForSelector('#kx-guard', { timeout: 15000 }).catch(() => {});
  await ph.pg.waitForTimeout(800);
  const ov = await ph.pg.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  await ph.pg.screenshot({ path: `${OUT}/k28-telefon.png` }).catch(() => {});
  ok('telefon (390 px): sozlamalarda detektor bo‘limi, sahifa gorizontal siljimaydi', !!(await ph.pg.$('#kx-guard')) && ov <= 1, ov);
  await ph.ctx.close();

  ok('sahifa xatolari yo‘q', allErrs.length === 0, allErrs);
  ok('oxirida detektor jurnali bo‘sh — sahifaning birorta amali pul jadvaliga to‘g‘ridan-to‘g‘ri yozmadi', nlog() === '0', q(`select string_agg(tbl || ':' || op || ':' || row_id, ', ') from public.fin_direct_log`));
  await b.close();
  const f = res.filter(r => !r.ok).length;
  console.log(`JAMI (v2): ${res.length - f}/${res.length}`);
  process.exit(f ? 1 : 0);
})().catch(e => { console.error('XATO', e && e.stack || e); process.exit(2); });
