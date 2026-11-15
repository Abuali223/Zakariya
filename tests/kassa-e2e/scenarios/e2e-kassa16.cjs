// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): kassa ko'rigidan keyingi oqimlar (g8, g11).
//   (a) T1: T1 dan katta kirim yana bir bor so'raladi (rad etilsa — yozilmaydi); T1 dan katta chiqim so'rovi 2-ro'yxat + Direktor
//       tasdig'iga boradi (kichigi — faqat 2-ro'yxat); Direktor «Tasdiqlash» navbatidan tasdiqlaydi.
//   (d) server rad etsa: «So'rovlar» → «Rad etish» oynasidagi «Tasdiqlash» va «Tasdiqlash» navbatidagi tugma qayta yoqiladi (ui-12).
//   (e) ishdan ketgan xodim: ro'yxatda «(ketgan)», yangi avans berilmaydi (kassa:emp_left), yakuniy hisob-kitob — mumkin.
//   (c) kassani almashtirish (asosiy ↔ SINOV): har kassa holati alohida, kech kelgan eski javob olinmaydi (ui-11); sinov kassasida
//       qurilma navbati ko'rsatilmaydi va server ham rad etadi (g11 js-3, kassa:pending_test).
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa16.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
// server rad etishi: { msg, hint } — psql stderr dagi ERROR va HINT qatorlari (rad etilmasa — bo'sh)
const refused = (uid, sql) => { const t = String(cp.spawnSync(E.PSQL[0], [...E.PSQL.slice(1), '-q', '-At', '-d', E.DB, '-c',
  `begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`], { encoding: 'utf8' }).stderr || '');
  return { msg: ((t.match(/ERROR:\s+(.*)/) || [])[1] || '').trim(), hint: ((t.match(/HINT:\s+(.*)/) || [])[1] || '').trim() }; };
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
const sp = s => String(s || '').replace(/[  ]/g, ' ').replace(/\s+/g, ' ').trim();
const som = n => String(Math.round(Number(n))).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' so‘m';
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()'), yday = q('select (app.fin_today() - 1)::text');
  // tayyorgarlik: ishga tushirish (T1 = 1 000 000), kontragent (tur tasdiqlangan), buxgalter (ikkinchi 2-ro'yxat xodimi), sinov kassasi
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  q(`insert into public.fin_counterparties (id, kind, name, stir, active, "kindConfirmedBy", "kindConfirmedAt") values ('cp_e16', 'supplier', 'Sinov Taminot MChJ', '', true, '${ids.R_DIR}', now()) on conflict (id) do nothing`);
  const ACC = 'u_acc_e16';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter16@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status`);
  const t1Ref = 'teachers:' + ids.T1, t1Name = q(`select name from public.teachers where id='${ids.T1}'`);
  const t2Ref = 'teachers:' + ids.T2;
  const qRef = 'staff:' + ids.S2, qName = q(`select name from public.staff where id='${ids.S2}'`), qPos = q(`select coalesce(position, '') from public.staff where id='${ids.S2}'`);
  async function login(uid, vp, ob) {
    const email = q(`select coalesce(email, '') from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui, obv]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365));
      if (obv && !localStorage.getItem('iqror_pay_outbox_v1')) localStorage.setItem('iqror_pay_outbox_v1', obv); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI, ob ? JSON.stringify(ob) : '']);
    const pg = await ctx.newPage(); const s = { ctx, pg, dialogs: [], dismissOnce: null };
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    // «… qabul qilinsinmi?» — kerak bo'lsa bir marta rad etiladi (dismissOnce); chop etish takliflari — rad (sinovda chop etish shart emas)
    pg.on('dialog', d => { const m = sp(d.message()); s.dialogs.push(m); const no = (s.dismissOnce && s.dismissOnce.test(m)) || /chop etilsinmi/.test(m);
      if (s.dismissOnce && s.dismissOnce.test(m)) s.dismissOnce = null; (no ? d.dismiss() : d.accept()).catch(() => {}); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);
    s.tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    s.kassaReady = async () => { await s.tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    s.modalOpen = () => pg.evaluate(() => document.querySelector('#modal-bg').classList.contains('show'));
    s.modalGone = () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    s.toasts = async () => sp(await pg.evaluate(() => [...document.querySelectorAll('#toasts .toast')].map(e => e.textContent).join(' | ')));
    s.toastWait = re => pg.waitForFunction(r => [...document.querySelectorAll('#toasts .toast')].some(t => new RegExp(r).test(t.textContent.replace(/[  ]/g, ' '))), re.source, { timeout: 15000 }).catch(() => {});
    s.body = async () => sp(await pg.$eval('#ks-body', e => e.innerText));
    return s;
  }

  // ---------------- (a) Kassir: T1 dan katta kirim yana bir bor so'raladi; T1 dan katta chiqim so'rovi — 2-ro'yxat + Direktor
  const kas = await login(ids.R_KAS);
  let idBig = '', idSmall = '';
  {
    await kas.kassaReady();
    const recForm = async (amount, basis) => {
      await kas.pg.click('#ks-in'); await kas.pg.waitForSelector('#kf-op'); await kas.pg.selectOption('#kf-op', 'in_other');
      await kas.pg.waitForSelector('#kf-ptype', { state: 'attached' }); await kas.pg.selectOption('#kf-ptype', 'counterparty'); await kas.pg.waitForSelector('#kf-pc');
      await kas.pg.selectOption('#kf-pc', 'cp_e16'); await kas.pg.selectOption('#kf-dyn [data-art="0"]', 'IN-06');
      await kas.pg.fill('#kf-amt', amount); await kas.pg.fill('#kf-basis', basis); await kas.pg.fill('#kf-note', 'Sinov kirim');
    };
    await recForm('1 500 000', 'Shartnoma № 16-1 (sinov)');
    kas.dismissOnce = /qabul qilinsinmi/; await kas.pg.click('#kf-save'); await kas.pg.waitForTimeout(800);
    // ui-6: matn — summa va operatsiya (kontragent tanlanganda nomi qo'shilmaydi: F.party.name faqat «boshqa shaxs» / o'quvchida)
    ok('T1 dan katta kirim (1 500 000 > 1 000 000): «1 500 000 so‘m qabul qilinsinmi? Boshqa kirim»; rad etilsa — oyna ochiq, hujjat yozilmadi',
      kas.dialogs.some(m => m === '1 500 000 so‘m qabul qilinsinmi? Boshqa kirim') && (await kas.modalOpen())
      && !(await kas.pg.$eval('#kf-save', e => e.disabled)) && q(`select count(*) from public.cash_docs where op='in_other'`) === '0', [kas.dialogs, await kas.toasts()]);
    const n0 = kas.dialogs.length;
    await kas.pg.click('#kf-save'); await kas.modalGone(); await kas.toastWait(/Kirim orderi № 1 o‘tkazildi/);
    ok('tasdiqlansa — kirim orderi o‘tkazildi (K-1, 1 500 000)', kas.dialogs.slice(n0).some(m => /1 500 000 so‘m qabul qilinsinmi\?/.test(m))
      && q(`select form || ':' || no || ':' || status || ':' || trim_scale(amount) from public.cash_docs where op='in_other'`) === 'KO1:1:posted:1500000' && /Kirim orderi № 1 o‘tkazildi/.test(await kas.toasts()), [await kas.toasts(), q(`select form, no, status, amount from public.cash_docs where op='in_other'`)]);
    await kas.pg.waitForTimeout(400);
    await recForm('900 000', 'Shartnoma № 16-2 (sinov)');
    const n1 = kas.dialogs.length;
    await kas.pg.click('#kf-save'); await kas.modalGone(); await kas.pg.waitForTimeout(700);
    ok('T1 dan kichik kirim (900 000) — qayta so‘ralmaydi, darhol o‘tkaziladi', !kas.dialogs.slice(n1).some(m => /qabul qilinsinmi/.test(m))
      && q(`select count(*) from public.cash_docs where op='in_other' and status='posted' and amount=900000`) === '1', kas.dialogs.slice(n1));
    // chiqim so'rovi: «Hisobdorga avans» 1 200 000 — xodimga (yuridik shaxs emas: Direktor talabi faqat T1 dan)
    await kas.pg.click('#ks-out'); await kas.pg.waitForSelector('#kf-op'); await kas.pg.selectOption('#kf-op', 'out_accountable');
    await kas.pg.waitForSelector(`#kf-pe option[value="${t1Ref}"]`, { state: 'attached', timeout: 15000 }); await kas.pg.selectOption('#kf-pe', t1Ref);
    await kas.pg.fill('#kf-amt', '1 200 000'); await kas.pg.fill('#kf-basis', 'Xizmat safari buyrug‘i № 16 (sinov)');
    const hint = sp(await kas.pg.$eval('#kf-hint', e => e.textContent));
    ok('chiqim so‘rovi oynasida: «Moliya menejeri / buxgalter tasdiqlaydi; 1 000 000 so‘mdan katta summada — Direktor ham»', hint === 'Pul berishdan oldin Moliya menejeri / buxgalter tasdiqlaydi; 1 000 000 so‘mdan katta summada — Direktor ham.', hint);
    const n2 = kas.dialogs.length;
    await kas.pg.click('#kf-save'); await kas.modalGone(); await kas.toastWait(/So‘rov yuborildi/);
    idBig = q(`select id from public.cash_docs where op='out_accountable' and amount=1200000`);
    ok('T1 dan katta chiqim so‘rovi yuborildi (so‘rov — tasdiqqa, qayta so‘ralmaydi): server — 2-ro‘yxat + Direktor tasdig‘i, holati «draft»',
      !!idBig && kas.dialogs.length === n2 && /So‘rov yuborildi — tasdiq kutilmoqda/.test(await kas.toasts())
      && q(`select status || ':' || "needsList2" || ':' || "needsDirector" || ':' || coalesce("partyId", '') from public.cash_docs where id='${idBig}'`) === `draft:true:true:${t1Ref}`,
      [await kas.toasts(), kas.dialogs.slice(n2), q(`select status, "needsList2", "needsDirector" from public.cash_docs where op='out_accountable'`)]);
    // T1 dan kichik so'rov (server orqali) — faqat 2-ro'yxat
    idSmall = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_accountable","amount":300000,"partyType":"employee","partyId":"${t2Ref}","basis":"Xizmat safari buyrug‘i № 17 (sinov)","clientRef":"e16-c2-0001"}'::jsonb)::text`)).id;
    ok('T1 dan kichik chiqim so‘rovi (300 000) — faqat 2-ro‘yxat tasdig‘i (Direktorsiz)', q(`select status || ':' || "needsList2" || ':' || "needsDirector" from public.cash_docs where id='${idSmall}'`) === 'draft:true:false');
  }

  // ---------------- (d) Moliya menejeri: «Rad etish» oynasi — server rad etsa oyna ochiq, «Tasdiqlash» qayta yoqiladi; (a) 2-ro'yxat tasdig'i
  {
    const mol = await login(ids.R_MOL); await mol.kassaReady();
    await mol.pg.waitForSelector(`[data-rej="${idSmall}"]`, { timeout: 15000 }); await mol.pg.click(`[data-rej="${idSmall}"]`); await mol.pg.waitForSelector('#ks-reason');
    asUser(ACC, `select public.kassa_doc_approve('${idSmall}')::text`);   // shu orada boshqa 2-ro'yxat xodimi (buxgalter) tasdiqladi
    await mol.pg.fill('#ks-reason', 'Hujjat to‘liq emas (sinov)'); await mol.pg.click('#ks-ok');
    await mol.toastWait(/Faqat tasdiq kutayotgan hujjat rad etiladi/); await mol.pg.waitForTimeout(300);
    ok('server rad etdi («Faqat tasdiq kutayotgan hujjat rad etiladi (holati: approved)»): oyna ochiq, sabab saqlangan, «Tasdiqlash» tugmasi qayta yoqilgan',
      /Faqat tasdiq kutayotgan hujjat rad etiladi \(holati: approved\)/.test(await mol.toasts()) && (await mol.modalOpen()) && (await mol.pg.$eval('#ks-ok', e => !e.disabled && /Tasdiqlash/.test(e.textContent)))
      && (await mol.pg.$eval('#ks-reason', e => e.value)) === 'Hujjat to‘liq emas (sinov)', [await mol.toasts(), await mol.modalOpen(), await mol.pg.$eval('#ks-ok', e => e.disabled).catch(() => 'yo‘q')]);
    ok('so‘rov rad etilmadi: buxgalter tasdig‘i bilan «approved» (T1 dan kichik — Direktorsiz)', q(`select status || ':' || ("approvedBy" = '${ACC}') || ':' || coalesce("dirApprovedBy", '-') from public.cash_docs where id='${idSmall}'`) === 'approved:true:-');
    await mol.pg.click('#m-cancel'); await mol.modalGone();
    // T1 dan katta so'rov: 2-ro'yxat tasdiqlaydi — Direktor tasdig'ini kutadi
    await mol.pg.waitForSelector(`[data-appr="${idBig}"]`, { timeout: 15000 }); await mol.pg.click(`[data-appr="${idBig}"]`);
    await mol.pg.waitForFunction(id => !document.querySelector(`[data-appr="${id}"]`), idBig, { timeout: 15000 }).catch(() => {}); await mol.pg.waitForTimeout(500);
    const row = sp(await mol.pg.evaluate(id => { const x = document.querySelector(`[data-rej="${id}"]`); return x ? x.closest('tr').innerText : ''; }, idBig));
    ok('2-ro‘yxat tasdiqladi: so‘rov hali «draft» — «✓ moliya», «… Direktor tasdig‘i»',
      q(`select status || ':' || ("approvedBy" = '${ids.R_MOL}') || ':' || coalesce("dirApprovedBy", '-') from public.cash_docs where id='${idBig}'`) === 'draft:true:-' && /✓ moliya: .*… Direktor tasdig‘i/.test(row), row);
    await mol.ctx.close();
  }
  {
    await kas.kassaReady();
    ok('kassir: Direktor tasdig‘igacha T1 dan katta so‘rovga «Pulni berish» yo‘q; kichigiga — bor', !(await kas.pg.$(`[data-pay="${idBig}"]`)) && !!(await kas.pg.$(`[data-pay="${idSmall}"]`)));
  }

  // ---------------- (a)+(d) Direktor: «Tasdiqlash» navbati — server rad etsa tugma qayta yoqiladi, qayta bosilganda tasdiqlanadi
  const OBX = [{ payId: 'man_e16_ob1', method: 'cash', amount: 50000, sid: 'IQ-0005', nm: 'Sinov navbat yozuvi', status: 'failed', lastError: 'Fiskal chek raqami kiritilmagan', lastHint: 'kassa:fiscal', ts: Date.now() }];
  const dir = await login(ids.R_DIR, null, OBX);
  {
    await dir.tab('approvals'); await dir.pg.waitForSelector(`[data-kappr="${idBig}"]`, { timeout: 20000 });
    const v = sp(await dir.pg.$eval('#view', e => e.innerText));
    ok('Direktor «Tasdiqlash»da: T1 dan katta so‘rov (xodim, 1 200 000); kichigi yo‘q (Direktor tasdig‘i talab qilinmaydi)', v.includes(t1Name) && v.includes('1 200 000 so‘m') && !(await dir.pg.$(`[data-kappr="${idSmall}"]`)), v.slice(0, 400));
    let refuse = true;
    await dir.pg.route('**/rest/v1/rpc/kassa_doc_approve', route => { if (!refuse) return route.continue(); refuse = false;
      return route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'P0001', message: 'Sinov: server vaqtincha rad etdi', details: null, hint: 'kassa:sinov' }) }); });
    await dir.pg.click(`[data-kappr="${idBig}"]`); await dir.toastWait(/Sinov: server vaqtincha rad etdi/); await dir.pg.waitForTimeout(600);
    ok('server rad etdi: xabar ko‘rsatildi, so‘rov navbatda qoldi, «Tasdiqlash» tugmasi yana faol (bosish mumkin)', /Sinov: server vaqtincha rad etdi/.test(await dir.toasts())
      && (await dir.pg.$eval(`[data-kappr="${idBig}"]`, e => !e.disabled).catch(() => false)) && q(`select status || ':' || coalesce("dirApprovedBy", '-') from public.cash_docs where id='${idBig}'`) === 'draft:-', await dir.toasts());
    await dir.pg.click(`[data-kappr="${idBig}"]`);
    await dir.pg.waitForFunction(id => !document.querySelector(`[data-kappr="${id}"]`), idBig, { timeout: 15000 }).catch(() => {});
    ok('qayta bosildi — Direktor tasdiqladi: so‘rov «approved» (2-ro‘yxat + Direktor)', q(`select status || ':' || ("approvedBy" = '${ids.R_MOL}') || ':' || ("dirApprovedBy" = '${ids.R_DIR}') from public.cash_docs where id='${idBig}'`) === 'approved:true:true');
    await dir.pg.unroute('**/rest/v1/rpc/kassa_doc_approve');
  }

  // ---------------- (e) Ishdan ketgan xodim: «(ketgan)», yangi avans yo'q (kassa:emp_left), yakuniy hisob-kitob — mumkin
  {
    // ketishidan oldin: hisobdorga avans 100 000 berilgan, ish haqi avansi 50 000 tasdiqlangan (pul berilmagan)
    const a1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_accountable","amount":100000,"partyType":"employee","partyId":"${qRef}","basis":"Xo‘jalik mollari uchun (sinov)","clientRef":"e16-e1-0001"}'::jsonb)::text`)).id;
    asUser(ids.R_MOL, `select public.kassa_doc_approve('${a1}')::text`); asUser(ids.R_KAS, `select public.kassa_doc_pay('${a1}')::text`);
    const a2 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_advance","amount":50000,"partyType":"employee","partyId":"${qRef}","basis":"Ariza (sinov)","clientRef":"e16-e2-0001"}'::jsonb)::text`)).id;
    asUser(ids.R_MOL, `select public.kassa_doc_approve('${a2}')::text`);
    ok('tayyorgarlik: xodimga hisobdorga avans 100 000 berildi, ish haqi avansi 50 000 tasdiqlangan', q(`select string_agg(op || ':' || status, ',' order by op) from public.cash_docs where id in ('${a1}', '${a2}')`) === 'out_accountable:posted,out_advance:approved');
    q(`update public.staff set "payStatus" = 'chiqdi', "stopFrom" = '${yday}' where id = '${ids.S2}'`);   // kadrlar: ishdan chiqdi (kecha)
    await kas.kassaReady();
    await kas.pg.click('#ks-out'); await kas.pg.waitForSelector('#kf-op'); await kas.pg.selectOption('#kf-op', 'out_advance');
    await kas.pg.waitForSelector(`#kf-pe option[value="${qRef}"]`, { state: 'attached', timeout: 15000 });
    const optA = await kas.pg.$eval(`#kf-pe option[value="${qRef}"]`, o => o.textContent + '|' + o.disabled);
    const othersA = await kas.pg.$$eval('#kf-pe option', (os, r) => os.filter(o => o.value && o.value !== r).map(o => o.textContent + '|' + o.disabled), qRef);
    const noteA = sp(await kas.pg.$eval('#kf-party', e => e.innerText));
    ok('«Ish haqi avansi»: ketgan xodim «(ketgan)» belgisi bilan, tanlab bo‘lmaydi; izoh; boshqalar — belgisiz, faol',
      optA === `${qName} (ketgan)${qPos ? ' · ' + qPos : ''}|true` && noteA.includes('Ishdan ketgan xodimga yangi avans berilmaydi; yakuniy hisob-kitob — maosh, qaytim, avans hisoboti.')
      && othersA.length > 0 && othersA.every(x => /\|false$/.test(x) && !/\(ketgan\)/.test(x)), [optA, noteA, othersA]);
    await kas.pg.selectOption('#kf-op', 'out_accountable'); await kas.pg.waitForSelector(`#kf-pe option[value="${qRef}"]`, { state: 'attached', timeout: 15000 });
    ok('«Hisobdorga avans»: ketgan xodim ham tanlab bo‘lmaydi', (await kas.pg.$eval(`#kf-pe option[value="${qRef}"]`, o => o.disabled && /\(ketgan\)/.test(o.textContent))));
    await kas.pg.click('#m-cancel'); await kas.modalGone();
    const r1 = refused(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_advance","amount":30000,"partyType":"employee","partyId":"${qRef}","basis":"Ariza 2 (sinov)","clientRef":"e16-e3-0001"}'::jsonb)::text`);
    ok('server: ketgan xodimga yangi ish haqi avansi so‘rovi rad etiladi (kassa:emp_left, yakuniy hisob-kitob mumkinligi aytiladi)',
      r1.hint === 'kassa:emp_left' && r1.msg.startsWith(`«${qName}» ishdan ketgan: unga yangi ish haqi avansi berilmaydi.`) && /Yakuniy hisob-kitob/.test(r1.msg)
      && q(`select count(*) from public.cash_docs where "clientRef"='e16-e3-0001'`) === '0', r1);
    const r2 = refused(ids.R_KAS, `select public.kassa_doc_pay('${a2}')::text`);
    ok('server: ketishidan oldin tasdiqlangan avans puli ham berilmaydi (kassa:emp_left), so‘rov «approved» bo‘lib qoladi', r2.hint === 'kassa:emp_left' && q(`select status from public.cash_docs where id='${a2}'`) === 'approved', r2);
    // yakuniy hisob-kitob: «Hisobdordan qaytim» — ketgan xodim tanlanadi, qoldig'i ko'rinadi, kirim o'tkaziladi
    await kas.pg.click('#ks-in'); await kas.pg.waitForSelector('#kf-op'); await kas.pg.selectOption('#kf-op', 'in_acc_return');
    await kas.pg.waitForSelector(`#kf-pe option[value="${qRef}"]`, { state: 'attached', timeout: 15000 });
    const optR = await kas.pg.$eval(`#kf-pe option[value="${qRef}"]`, o => o.textContent + '|' + o.disabled);
    await kas.pg.selectOption('#kf-pe', qRef);
    await kas.pg.waitForFunction(() => { const e = document.querySelector('#kf-staff'); return e && e.style.display !== 'none' && /\d/.test(e.textContent); }, null, { timeout: 15000 }).catch(() => {});
    const staffInfo = sp(await kas.pg.$eval('#kf-staff', e => e.innerText).catch(() => ''));
    await kas.pg.fill('#kf-amt', '100 000'); await kas.pg.fill('#kf-basis', 'Hisobdor qaytimi (sinov)');
    await kas.pg.click('#kf-save'); await kas.modalGone(); await kas.pg.waitForTimeout(700);
    ok('yakuniy hisob-kitob: «Hisobdordan qaytim»da ketgan xodim faol («(ketgan)» belgisi bilan), qoldig‘i 100 000 ko‘rinadi, kirim o‘tkazildi',
      optR === `${qName} (ketgan)${qPos ? ' · ' + qPos : ''}|false` && staffInfo === 'Hisobdordagi hisobot qilinmagan avans: 100 000 so‘m — qaytim shundan oshmaydi.'
      && q(`select status || ':' || trim_scale(amount) || ':' || "partyId" from public.cash_docs where op='in_acc_return'`) === `posted:100000:${qRef}`, [optR, staffInfo, await kas.toasts(), q(`select status, amount from public.cash_docs where op='in_acc_return'`)]);
  }

  // ---------------- (c) Direktor: asosiy ↔ SINOV kassa — holat alohida, eski javob olinmaydi, sinov kassasida qurilma navbati yo'q (g11)
  {
    asUser(ids.R_DIR, `select public.kassa_opening_set('{"desk":"sinov","amount":500000,"startDay":"${today}"}'::jsonb)::text`);
    asUser(ids.R_KAS, `select public.kassa_receipt('{"desk":"sinov","op":"in_other","amount":20000,"partyType":"counterparty","partyId":"cp_e16","articleId":"IN-06","basis":"Tilxat S-1 (sinov)","note":"Sinov kassasi","clientRef":"e16-s1-0001"}'::jsonb)::text`);
    const bal = d => q(`select trim_scale(coalesce((select "openingAmount" from public.cash_desks where id='${d}'), 0) + coalesce((select sum(case when form = 'KO1' then amount else -amount end) from public.cash_docs where desk='${d}' and status='posted' and form in ('KO1', 'KO2')), 0))`);
    const mainBal = som(bal('main')), testBal = som(bal('sinov'));
    const SINOV_BANNER = 'Bu — SINOV kassasi: hujjatlari va raqamlari asosiy kassadan alohida, hisobotlarga kirmaydi.';
    await dir.kassaReady();
    const m1 = await dir.body();
    ok(`asosiy kassa: qoldiq ${mainBal}, asosiy hujjatlar; SINOV belgisi va sinov hujjati yo‘q`, m1.includes('KASSADAGI QOLDIQ ' + mainBal) && m1.includes('Shartnoma № 16-1') && !m1.includes(SINOV_BANNER) && !m1.includes('Tilxat S-1'), m1.slice(0, 500));
    await dir.pg.selectOption('#ks-desk', 'sinov');
    await dir.pg.waitForFunction(t => document.querySelector('#ks-body').innerText.includes(t), SINOV_BANNER, { timeout: 15000 }).catch(() => {});
    const s1 = await dir.body();
    ok(`SINOV kassa: belgisi, qoldig‘i ${testBal}, faqat o‘z hujjati (K-1, 20 000); asosiy kassa hujjatlari yo‘q; raqamlash alohida`,
      s1.includes(SINOV_BANNER) && s1.includes('KASSADAGI QOLDIQ ' + testBal) && /K-1 .*Tilxat S-1 \(sinov\) 20 000 so‘m/.test(s1) && !s1.includes('Shartnoma № 16-1')
      && q(`select string_agg(desk || ':' || no, ',' order by desk, no) from public.cash_docs where form='KO1'`) === 'main:1,main:2,main:3,sinov:1', [s1.slice(0, 500), q(`select string_agg(desk || ':' || no, ',' order by desk, no) from public.cash_docs where form='KO1'`)]);
    await dir.pg.selectOption('#ks-desk', 'main');
    await dir.pg.waitForFunction(t => !document.querySelector('#ks-body').innerText.includes(t), SINOV_BANNER, { timeout: 15000 }).catch(() => {});
    const m2 = await dir.body();
    ok('asosiy kassaga qaytildi: o‘sha qoldiq va hujjatlar, SINOV belgisi yo‘q', m2.includes('KASSADAGI QOLDIQ ' + mainBal) && m2.includes('Shartnoma № 16-1') && !m2.includes(SINOV_BANNER) && !m2.includes('Tilxat S-1'), m2.slice(0, 400));
    // ui-11: SINOV javobi kechiksa (1,5 s) va shu orada asosiy kassa tanlansa — kech kelgan SINOV javobi olinmaydi
    let slow = false;
    await dir.pg.route('**/rest/v1/rpc/kassa_overview', async route => { if (slow && /"p_desk":"sinov"/.test(route.request().postData() || '')) await new Promise(r => setTimeout(r, 1500)); return route.continue(); });
    slow = true;
    const late = dir.pg.waitForResponse(r => /\/rpc\/kassa_overview/.test(r.url()) && /"p_desk":"sinov"/.test(r.request().postData() || ''), { timeout: 20000 }).catch(() => null);
    await dir.pg.selectOption('#ks-desk', 'sinov'); await dir.pg.waitForTimeout(150); await dir.pg.selectOption('#ks-desk', 'main');
    const lateOk = !!(await late); await dir.pg.waitForTimeout(700);   // kech kelgan SINOV javobi keldi — sahifa unga qanday javob berdi
    slow = false;
    const m3 = await dir.body();
    ok('tez almashtirish (SINOV → asosiy, SINOV javobi kech keldi): asosiy kassa ko‘rsatiladi, tanlov «Asosiy kassa»', lateOk && (await dir.pg.$eval('#ks-desk', e => e.value)) === 'main'
      && m3.includes('KASSADAGI QOLDIQ ' + mainBal) && !m3.includes(SINOV_BANNER), [await dir.pg.$eval('#ks-desk', e => e.value), m3.slice(0, 300)]);
    await dir.pg.unroute('**/rest/v1/rpc/kassa_overview');
    // qurilma navbati (shu qurilmada server rad etgan naqd to'lov) — asosiy kassani yopish oynasida bor, SINOV kassasida yo'q
    await dir.pg.click('#ks-close'); await dir.pg.waitForSelector('#kc-counted', { timeout: 15000 });
    const fm = sp(await dir.pg.$eval('#kc-failed', e => e.innerText).catch(() => ''));
    ok('asosiy kassa — kunni yopish: qurilma navbati qatori va «Yuborilmadi» yozuvi (summa, ikki tanlov) bor', !!(await dir.pg.$('#kc-ob')) && fm.includes('Sinov navbat yozuvi — 50 000 so‘m')
      && (await dir.pg.$$('[data-flref="man_e16_ob1"]')).length === 2, fm);
    await dir.pg.click('#m-cancel'); await dir.modalGone();
    await dir.pg.click('#ks-hand'); await dir.pg.waitForSelector('#kh-to', { timeout: 15000 });
    ok('asosiy kassa — smena topshirish: qurilma navbati qatori va «Yuborilmadi» yozuvi (ikki tanlov) bor', !!(await dir.pg.$('#kc-ob')) && !!(await dir.pg.$('#kc-failed'))
      && (await dir.pg.$$('[data-flref="man_e16_ob1"]')).length === 2);
    await dir.pg.click('#m-cancel'); await dir.modalGone();
    await dir.pg.selectOption('#ks-desk', 'sinov');
    await dir.pg.waitForFunction(t => document.querySelector('#ks-body').innerText.includes(t), SINOV_BANNER, { timeout: 15000 }).catch(() => {});
    await dir.pg.waitForSelector('#ks-close', { timeout: 15000 }); await dir.pg.click('#ks-close'); await dir.pg.waitForSelector('#kc-counted', { timeout: 15000 });
    const sm = sp(await dir.pg.$eval('#modal', e => e.innerText));
    ok('SINOV kassa — kunni yopish: qurilma navbati ham, «Yuborilmadi» tanlovi ham yo‘q (g11, js-3)', /Hisobdagi qoldiq: 520 000 so‘m/.test(sm) && !(await dir.pg.$('#kc-ob')) && !(await dir.pg.$('#kc-failed')) && !(await dir.pg.$('[data-flref]'))
      && !/navbatida/.test(sm), sm.slice(0, 400));
    await dir.pg.click('#m-cancel'); await dir.modalGone();
    await dir.pg.click('#ks-hand'); await dir.pg.waitForSelector('#kh-to', { timeout: 15000 });
    const hm = sp(await dir.pg.$eval('#modal', e => e.innerText));
    ok('SINOV kassa — smena topshirish: qurilma navbati ham, «Yuborilmadi» tanlovi ham yo‘q (g11, js-3)', /Hisobdagi qoldiq: 520 000 so‘m/.test(hm) && !(await dir.pg.$('#kc-ob')) && !(await dir.pg.$('#kc-failed'))
      && !(await dir.pg.$('[data-flref]')), hm.slice(0, 300));
    await dir.pg.click('#m-cancel'); await dir.modalGone();
    const r3 = refused(ids.R_KAS, `select public.kassa_day_close('{"desk":"sinov","day":"${today}","counted":520000,"expected":520000,"pendingRefs":[{"ref":"man_e16_ob1","amount":50000}]}'::jsonb)::text`);
    ok('server: SINOV kassani yopishda navbat yozuvi e’lon qilinsa — rad (kassa:pending_test), kun ochiq qoladi', r3.hint === 'kassa:pending_test'
      && q(`select status from public.cash_days where desk='sinov' and day='${today}'`) === 'open', r3);
    const r4 = refused(ids.R_KAS, `select public.kassa_handover('{"desk":"sinov","counted":520000,"expected":520000,"pendingRefs":[{"ref":"man_e16_ob1","amount":50000}],"toUid":"${ids.R_DIR}"}'::jsonb)::text`);
    ok('server: SINOV kassada smena topshirishda ham navbat yozuvi rad etiladi (kassa:pending_test), topshirish yozilmaydi', r4.hint === 'kassa:pending_test'
      && q(`select count(*) from public.cash_handovers`) === '0', r4);
    ok('qurilma navbati o‘zgarmadi (yozuv shu qurilmada qoldi)', /man_e16_ob1/.test(await dir.pg.evaluate(() => localStorage.getItem('iqror_pay_outbox_v1') || '')));
    await dir.pg.screenshot({ path: `${OUT}/desk-${UI}-1440.png` });
    await dir.ctx.close();
  }
  await kas.ctx.close();
  q(`delete from app.fin_clock`);
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { try { q(`delete from app.fin_clock`); } catch (_) {} console.error('XATO', e); process.exit(1); });
