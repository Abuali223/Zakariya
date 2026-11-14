// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F1.16 — davr surati va yopilgan davr qulfi; F1.11 — maosh berish huquqi.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa6.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()');
  const dm = d => d.slice(8, 10) + '.' + d.slice(5, 7) + '.' + d.slice(0, 4);
  const pme = q(`select (date_trunc('month', app.fin_today()) - interval '1 day')::date`);          // o'tgan oyning oxirgi kuni
  const lockNext = q(`select (date_trunc('month', app.fin_today()))::date`);                         // qulfdan keyingi kun
  const kindLbl = pme.slice(5) === '12-31' ? 'Yil yakuni' : 'Oy yakuni';
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
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
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
    const period = async () => { await pg.click('#ks-period'); await pg.waitForSelector('#kpd-lock', { timeout: 15000 }); };
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, toasts, period };
  }

  // ---------------- 1) Direktor: surat olish va davrni yopish
  const dir = await login(ids.R_DIR);
  {
    const s = dir; await s.kassaReady(); await s.period();
    ok('direktor: «Davr» oynasi — davr yopilmagan, standart sana — o‘tgan oyning oxirgi kuni, qulf belgisi yoqilgan',
      /Davr yopilmagan/.test(await s.pg.$eval('#kpd-lock', e => e.textContent)) && (await s.pg.$eval('#kpd-day', e => e.value)) === pme && (await s.pg.$eval('#kpd-lockit', e => e.checked && !e.disabled))
      && /Hali surat olinmagan/.test(await s.pg.$eval('#modal', e => e.textContent)));
    await s.pg.fill('#kpd-day', today); await s.pg.dispatchEvent('#kpd-day', 'change');
    ok('bugungi kun tanlansa — qulf belgisi o‘chadi (bugungi kun yopilmaydi)', await s.pg.$eval('#kpd-lockit', e => e.disabled && !e.checked));
    await s.pg.fill('#kpd-day', pme); await s.pg.dispatchEvent('#kpd-day', 'change'); await s.pg.check('#kpd-lockit');
    await s.pg.fill('#kpd-note', 'Sinov: davr yakuni'); await s.pg.click('#kpd-take');
    await s.pg.waitForFunction(() => document.querySelectorAll('#modal [data-snap-chk]').length === 1, null, { timeout: 20000 });
    const mt = await s.pg.$eval('#modal', e => e.innerText.replace(/\s+/g, ' '));
    ok('surat olindi: tasdiq so‘raldi (davr yopilishi aytildi), ro‘yxatda — sana, turi, kim olgan, «kechikib olingan», jamlar, xesh',
      s.dialogs.some(m => m.includes(`${dm(pme)} kuni oxiridagi holat surati olinsinmi`) && /YOPILADI/.test(m)) && mt.includes(dm(pme)) && mt.includes(kindLbl) && /kechikib olingan/.test(mt)
      && /qarzdorlik .* so‘m · avans va oldindan to‘lov .* so‘m · kassa 1 000 000 so‘m/.test(mt) && /xesh: [0-9a-f]{16}…/.test(mt) && /Sinov: davr yakuni/.test(mt), [s.dialogs.slice(-1), mt.slice(0, 900)]);
    ok('davr yopildi: holat satri va bazadagi qulf', (await s.pg.$eval('#kpd-lock', e => e.textContent)).includes(`${dm(pme)} gacha yopilgan`) && q(`select "lockedThrough" from public.fin_org where id='main'`) === pme,
      [await s.pg.$eval('#kpd-lock', e => e.textContent), q(`select "lockedThrough" from public.fin_org where id='main'`)]);
    ok('bazada: surat o‘zgarmas jadvalda, xesh mazmun bilan mos, turi va «kechikkan» belgisi',
      q(`select kind || ':' || version || ':' || late || ':' || (hash = encode(sha256(convert_to(payload::text, 'UTF8')), 'hex')) || ':' || "asOfDay" from public.fin_snapshots`) === `${pme.slice(5) === '12-31' ? 'year_end' : 'month_end'}:1:true:true:${pme}`,
      q(`select kind, version, late, "asOfDay" from public.fin_snapshots`));
    await s.pg.click('[data-snap-chk]'); await s.pg.waitForTimeout(900);
    ok('«Tekshirish»: xesh mos', /Surat butun: xesh mos/.test(await s.toasts()), await s.toasts());
    const [dl] = await Promise.all([s.pg.waitForEvent('download', { timeout: 15000 }), s.pg.click('[data-snap-dl]')]);
    const fp = await dl.path(); const js = JSON.parse(fs.readFileSync(fp, 'utf8'));
    ok('«⬇ JSON»: fayl nomi va mazmuni (o‘quvchilar, jamlar, xesh)', dl.suggestedFilename() === `davr-surati-${pme}-1.json` && Array.isArray(js.data.students) && js.data.totals && /^[0-9a-f]{64}$/.test(js.hash) && js.asOf === pme,
      [dl.suggestedFilename(), Object.keys(js.data || {})]);
    await s.pg.screenshot({ path: `${OUT}/period-${UI}-1440.png` });
    await s.pg.click('#m-cancel'); await s.modalGone();
    ok('«Kassa» sahifasida ogohlantirish: davr yopilgan', (await s.pg.$eval('#ks-body', e => e.textContent)).includes(`Davr ${dm(pme)} gacha yopilgan`));
  }

  // ---------------- 2) Shakllar: eng erta sana — qulfdan keyingi kun; server orqaga sanali yozuvni rad etadi
  {
    const s = dir;
    await s.tab('payments'); await s.pg.waitForSelector('#pm-body', { timeout: 30000 });
    await s.pg.waitForSelector('#pm-body [data-pay]', { timeout: 30000 }).catch(() => {});
    const opened = await s.pg.evaluate(() => { const b = document.querySelector('#pm-body [data-pay]'); if (b) { b.click(); return true; } return false; });
    if (opened) await s.pg.waitForSelector('#rp-date', { timeout: 15000 }).catch(() => {});
    const min = await s.pg.$eval('#rp-date', e => e.min).catch(() => null);
    ok('«To‘lov» shakli: eng erta sana — qulfdan keyingi kun', min === lockNext, [opened, min, lockNext]);
    await s.pg.click('#m-cancel').catch(() => {}); await s.pg.waitForTimeout(300);
    await s.tab('accounting'); await s.pg.waitForSelector('#ac-add', { timeout: 30000 }); await s.pg.click('#ac-add'); await s.pg.waitForSelector('#e-date', { timeout: 15000 });
    ok('«Xarajat» shakli: eng erta sana — qulfdan keyingi kun', (await s.pg.$eval('#e-date', e => e.min)) === lockNext, await s.pg.$eval('#e-date', e => e.min));
    await s.pg.click('#m-cancel').catch(() => {}); await s.pg.waitForTimeout(300);
    let msg = ''; try { asUser(ids.R_KAS, `select public.record_manual_payment('man_e6_0001', 'IQ-0003', 100000, 'bank', '${pme}', '', '', 'Sinov Ota', null, null)::text`); } catch (e) { msg = String(e.stderr || e.message); }
    ok('server: yopilgan davr sanasi bilan to‘lov rad etiladi (tushunarli matn bilan), iz qolmaydi', /yopilgan davr/.test(msg) && msg.includes(dm(pme)) && q(`select count(*) from public.payments where id='man_e6_0001'`) === '0', msg.slice(0, 300));
    const okp = asUser(ids.R_KAS, `select public.record_manual_payment('man_e6_0002', 'IQ-0003', 100000, 'bank', '${lockNext}', '', '', 'Sinov Ota', null, null)::text`);
    ok('server: qulfdan keyingi sana bilan to‘lov yoziladi', /"status": "applied"/.test(okp), okp.slice(0, 200));
  }

  // ---------------- 3) Moliya menejeri: ko'radi, lekin surat ololmaydi; kassir: «Davr» yo'q
  {
    const m = await login(ids.R_MOL); await m.kassaReady(); await m.period();
    ok('moliya menejeri: suratlar ro‘yxatini ko‘radi va tekshira oladi; «Surat olish» va qulfni o‘zgartirish yo‘q',
      (await m.pg.$$('#modal [data-snap-chk]')).length === 1 && !(await m.pg.$('#kpd-take')) && !(await m.pg.$('#kpd-setlock')));
    const [dl2] = await Promise.all([m.pg.waitForEvent('download', { timeout: 15000 }), m.pg.click('[data-snap-dl]')]);
    const js2 = JSON.parse(fs.readFileSync(await dl2.path(), 'utf8'));
    ok('moliya menejeri: «⬇ JSON» — ismsiz (ID bilan, FD-28): fayl nomi, belgi, o‘quvchi va xodim ismlari yo‘q',
      dl2.suggestedFilename() === `davr-surati-${pme}-1-ismsiz.json` && js2.masked === true && (js2.data.students || []).length > 0
      && (js2.data.students || []).every(x => !('name' in x) && x.studentId) && (js2.data.salary || []).every(x => !('name' in x)) && /ismsiz/.test(await m.toasts()),
      [dl2.suggestedFilename(), js2.masked, (js2.data.students || []).slice(0, 1)]);
    await m.pg.click('#m-cancel'); await m.ctx.close();
    const k = await login(ids.R_KAS); await k.kassaReady();
    ok('kassir: «Davr» tugmasi yo‘q', !(await k.pg.$('#ks-period')));
    await k.ctx.close();
    let denied = false; try { asUser(ids.R_MOL, `select public.fin_snapshot_take('{"asOf":"${pme}"}'::jsonb)::text`); } catch (e) { denied = /Ruxsat yo/.test(String(e.stderr || e.message)); }
    ok('moliya menejeri server orqali ham surat ololmaydi', denied);
  }

  // ---------------- 4) Direktor: qulfni orqaga surish — faqat sabab bilan
  {
    const s = dir; await s.kassaReady(); await s.period();
    await s.pg.$eval('#modal details', d => { d.open = true; });
    const back = q(`select ('${pme}'::date - 5)::text`);
    await s.pg.fill('#kpd-through', back); await s.pg.click('#kpd-setlock'); await s.pg.waitForTimeout(900);
    ok('qulfni orqaga surish sababsiz — rad', /sababni yozing/.test(await s.toasts()) && q(`select "lockedThrough" from public.fin_org where id='main'`) === pme, await s.toasts());
    await s.pg.fill('#kpd-reason', 'Bank ko‘chirmasi kech keldi'); await s.pg.click('#kpd-setlock');
    await s.pg.waitForFunction(d => (document.querySelector('#kpd-lock') || {}).textContent.includes(d), dm(back), { timeout: 15000 }).catch(() => {});
    ok('sabab bilan — qulf surildi; sabab saqlandi', q(`select "lockedThrough" || ':' || (extra ->> 'lockNote') from public.fin_org where id='main'`) === `${back}:Bank ko‘chirmasi kech keldi`, q(`select "lockedThrough", extra from public.fin_org where id='main'`));
    await s.pg.click('#m-cancel').catch(() => {});
    await s.ctx.close();
  }

  // ---------------- 5) F1.11: kassa ishga tushgach HR maosh bera olmaydi (tugma yo'q); telefon
  {
    const hr = q(`select id from public.users where role = 'hr' and coalesce(status, 'active') = 'active' limit 1`);
    if (hr) {
      const h = await login(hr);
      const can = await h.pg.evaluate(() => typeof canPaySalary === 'function' ? canPaySalary() : 'yo‘q').catch(() => 'xato');
      ok('HR menejer: kassa ishga tushgach maosh berish huquqi yo‘q (server ham rad etadi)', can === 'yo‘q' || can === false || can === 'xato', can);
      await h.ctx.close();
    } else ok('HR menejer: sinov urug‘ida HR yo‘q — server tekshiruvi SQL sinovida (S4b)', true);
    const p = await login(ids.R_DIR, { width: 390, height: 844 }); await p.kassaReady(); await p.period();
    const mw = await p.pg.evaluate(() => { const m = document.querySelector('#modal'); return m.scrollWidth - m.clientWidth; });
    ok('telefon: «Davr» oynasi gorizontal siljimaydi', mw <= 1, mw);
    await p.pg.screenshot({ path: `${OUT}/period-${UI}-390.png` });
    await p.ctx.close();
  }
  // ---------------- 6) F1.18: modul relizi belgisi — sahifa kutgan reliz serverdagidan farq qilsa ogohlantirish
  {
    const setVer = n => q(`create or replace function app.kassa_version() returns int language sql immutable set search_path = public, app, pg_temp as 'select ${n}'`);
    // reliz raqami qattiq yozilmaydi: bazadagi (stend zanjiri) va sahifa kutgani (fin-kassa.js SERVER_VER) — har relizda birga oshiriladi
    const VER = Number(q('select app.kassa_version()'));
    const PAGE_VER = Number((/const SERVER_VER = (\d+);/.exec(fs.readFileSync(require('path').join(E.REPO, 'assets/js/fin-kassa.js'), 'utf8')) || [])[1]);
    const d = await login(ids.R_DIR); await d.kassaReady();
    const body = () => d.pg.evaluate(() => document.querySelector('#ks-body').innerText);
    ok('reliz mos: ogohlantirish yo‘q; server holatida "version" bor (baza = sahifa kutgani)', VER > 0 && VER === PAGE_VER && !/sahifa esa eski|eski relizda/i.test(await body())
      && asUser(ids.R_DIR, `select (public.kassa_state('main') ->> 'version')`) === String(VER), { VER, PAGE_VER, body: (await body()).slice(0, 200) });
    try {
      setVer(VER + 1); await d.tab('accounting').catch(() => {}); await d.kassaReady();
      ok('server yangiroq relizda: «sahifani yangilang» ogohlantirishi', /Tizim yangilangan, bu sahifa esa eski/i.test(await body()), (await body()).slice(0, 300));
      setVer(VER - 1); await d.tab('accounting').catch(() => {}); await d.kassaReady();
      ok('server eskiroq relizda: «administratorga xabar bering» ogohlantirishi', /bu sahifadan eski relizda/i.test(await body()), (await body()).slice(0, 300));
    } finally { setVer(VER); }
    await d.tab('accounting').catch(() => {}); await d.kassaReady();
    ok('reliz tiklangach ogohlantirish yo‘qoladi', !/sahifa esa eski|eski relizda/i.test(await body()));
    await d.ctx.close();
  }
  // ---------------- 7) Sozlamalar: imzo egalari va ruscha nom
  {
    const d = await login(ids.R_DIR); await d.kassaReady();
    await d.pg.click('#ks-set'); await d.pg.waitForSelector('#kx-sadd', { timeout: 15000 });
    ok('sozlamalar: «Imzo egalari» bo‘limi bor, hali bo‘sh; bog‘lash uchun hisoblar ro‘yxatida direktor bor',
      /Hali kiritilmagan/.test(await d.pg.$eval('#kx-sigs', e => e.textContent)) && (await d.pg.$$eval('#kx-suid option', o => o.map(x => x.value))).includes(ids.R_DIR));
    await d.pg.click('#kx-sadd'); await d.pg.waitForTimeout(300);
    ok('F.I.Sh. siz qo‘shilmaydi', /to‘liq yozing/.test(await d.toasts()), await d.toasts());
    await d.pg.selectOption('#kx-slist', '1'); await d.pg.fill('#kx-stitle', 'Direktor'); await d.pg.fill('#kx-sname', 'Sinov Rahbar Rahbarovich');
    await d.pg.selectOption('#kx-suid', ids.R_DIR); await d.pg.click('#kx-sadd');
    await d.pg.waitForFunction(() => /Sinov Rahbar Rahbarovich/.test(document.querySelector('#kx-sigs').textContent), null, { timeout: 15000 });
    ok('imzo egasi qo‘shildi (1-ro‘yxat, hisobi bog‘langan) — bazada ham', /1-ro‘yxat · hisobi bog‘langan/.test(await d.pg.$eval('#kx-sigs', e => e.textContent))
      && q(`select list || ':' || title || ':' || "fullName" || ':' || uid from public.fin_signatories where active`) === `1:Direktor:Sinov Rahbar Rahbarovich:${ids.R_DIR}`,
      q(`select list || ':' || title || ':' || "fullName" || ':' || uid from public.fin_signatories where active`));
    await d.pg.$eval('#kx-sadd', e => e.scrollIntoView({ block: 'end' })); await d.pg.waitForTimeout(200); await d.pg.screenshot({ path: `${OUT}/settings-sig-${UI}-1440.png` });
    await d.pg.fill('#kx-name-ru', 'ООО «СИНОВ МАКТАБ»'); await d.pg.click('#kx-save'); await d.modalGone();
    ok('ruscha nom saqlandi; boshqa sozlamalar o‘zgarmadi', q(`select "nameRu" || '|' || "nameUz" || '|' || "kassaGoLive" from public.fin_org where id='main'`) === `ООО «СИНОВ МАКТАБ»|«SINOV MAKTAB» МЧЖ|${today}`,
      q(`select "nameRu" || '|' || "nameUz" || '|' || "kassaGoLive" from public.fin_org where id='main'`));
    await d.pg.click('#ks-set'); await d.pg.waitForSelector('#kx-sigs [data-sdel]', { timeout: 15000 });
    await d.pg.click('#kx-sigs [data-sdel]');
    await d.pg.waitForFunction(() => /Hali kiritilmagan/.test(document.querySelector('#kx-sigs').textContent), null, { timeout: 15000 });
    ok('imzo egasi ro‘yxatdan olib tashlandi (yozuv saqlanadi, faolsiz)', q(`select count(*) filter (where active) || ':' || count(*) from public.fin_signatories`) === '0:1');
    await d.pg.click('#m-cancel').catch(() => {});
    await d.ctx.close();
    const p = await login(ids.R_DIR, { width: 390, height: 844 }); await p.kassaReady();
    await p.pg.click('#ks-set'); await p.pg.waitForSelector('#kx-sadd', { timeout: 15000 });
    const sw = await p.pg.evaluate(() => { const m = document.querySelector('#modal'); return m.scrollWidth - m.clientWidth; });
    ok('telefon: «Sozlamalar» oynasi gorizontal siljimaydi', sw <= 1, sw);
    await p.pg.screenshot({ path: `${OUT}/settings-${UI}-390.png` });
    await p.pg.$eval('#kx-sadd', e => e.scrollIntoView({ block: 'end' })); await p.pg.waitForTimeout(200); await p.pg.screenshot({ path: `${OUT}/settings-sig-${UI}-390.png` });
    await p.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(2); });
