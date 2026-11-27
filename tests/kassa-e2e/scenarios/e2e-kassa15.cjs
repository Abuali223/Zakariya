// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri, kassa ishga tushgan): yakuniy ko'rik (g11) oqimlari
//   va pul maydonlari brauzerda:
//   (e) summa maydonlari — «2.900.000» va «1 000 000,50» rad, «1 000 000,00» qabul («💵 To'lov» oynasi va «+ Chiqim so'rovi»);
//   (d) js-1 — «💵 To'lov»: server rad etgan naqd to'lov (fiskal chek № takror) navbatda «Yuborilmadi» bo'lib qoladi, oyna ochiq; o'sha
//       o'quvchi uchun tuzatib qayta kiritilsa — rad etilgani navbatdan olinadi; boshqa o'quvchi tanlansa — qoladi;
//   (b) live-1b — qaytarish oynasi (kassa ishga tushgan): «Naqdsiz» yuborilgach usul qulflanadi; bitta oyna kaliti bilan naqd so'rov va
//       naqdsiz qaytarish bir-birini rad etadi (javob yo'qolgan holat); kassa:refund_pending va fin:locked matnlari;
//   (c) sec-1 — Direktor o'zi yolg'iz tasdiqlagan qaytarish va o'z kartasiga KO-2 pulini bermaydi (kassir beradi), 2-ro'yxat tasdiqlagan
//       uchinchi shaxs pulini beradi; o'ziga naqd maosh — server matni (FD-48), «Xatolik: 42501» siz;
//   (f) kassa to'xtatilganda «Buxgalteriya» oynalarida usul tanlovi (#sp-hmethod, #e-method, #av-hmethod).
//   (a) live-1 oddiy yo'l (kassa ishga tushmagan / o'rnatilmagan) — e2e-legacy.cjs da (dev va prod zanjir).
//   «Javob yo'qoldi» — Playwright route: so'rov serverga yetib bajariladi (route.fetch), brauzer esa javob o'rniga tarmoq xatosini oladi.
//   node scenarios/e2e-kassa15.cjs   (oldin: bash stand.sh reset dev)
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn (eski dizayn — v1 — 2026-11-24 da olib tashlangan)
const q = E.q;
// Foydalanuvchi nomidan funksiya chaqirish (bitta tranzaksiya; natija — oxirgi so'rovniki)
const asUser = (uid, sql) => q(`select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}`);
const tryQ = f => { try { return f(); } catch (e) { return 'XATO: ' + String(e.stderr || e.message || e).split('\n').filter(Boolean).slice(-2).join(' ').slice(0, 300); } };
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
// sahifa matnlari (admin.html UI-MSG, fin-kassa.js amtRead) — aynan shunday ko'rsatiladi
const PM_AMT_ERR = 'Summa noto‘g‘ri: faqat raqamlar, mingliklar orasida bo‘sh joy mumkin (masalan: 2 900 000). Nuqta yoki vergul mingliklar ajratkichi sifatida qabul qilinmaydi';
const PM_AMT_TIYIN = 'Tiyin yozilmaydi — summani butun so‘mda kiriting (masalan: 2 900 000)';
const AMT_ERR = 'Summa noto‘g‘ri: faqat raqamlar, mingliklar orasida bo‘sh joy mumkin (masalan: 1 250 000). Nuqta yoki vergul mingliklar ajratkichi sifatida qabul qilinmaydi';
const AMT_TIYIN = 'Tiyin yozilmaydi — summani butun so‘mda kiriting (masalan: 1 250 000)';
const fmt = n => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
const dmy = d => `${d.slice(8, 10)}.${d.slice(5, 7)}.${d.slice(0, 4)}`;
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()'), month = today.slice(0, 7);
  const prevEnd = q(`select (date '${month}-01' - 1)::text`), prevM = prevEnd.slice(0, 7);
  // tayyorlash: kassa bugundan ishga tushgan, boshlang'ich qoldiq 20 000 000; Direktor hisobi IQX-002 xodim kartasiga bog'langan (sec-1, FD-48);
  //   o'tgan oy sanasi bilan biriktirilmagan to'lov (fin:locked uchun; sintetik to'lovchi)
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","stir":"123456789","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":20000000,"startDay":"${today}"}'::jsonb)::text`);
  q(`update public.users set "staffRefType"='staff', "staffRefId"='${ids.S2}', "staffCode"='IQX-002' where id='${ids.R_DIR}'`);
  const UNM = 'e2e_unm_15';
  q(`insert into public.payments(id,"studentId","invoiceId",provider,amount,status,raw,"payerName","payerPhone","payerClass",matched,"createdAt") values ('${UNM}','',null,'click',450000,'unmatched','{"src":"click"}'::jsonb,'Sinov To‘lovchi 15','','5-A',false,'${prevM}-10T07:00:00Z')`);
  async function login(uid, vp) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    // xabarlar (toast ~3 s da yo'qoladi) — hammasi yozib boriladi: { t: matn (bo'shliqlar bitta), err: qizil }
    await ctx.addInitScript(() => { window.__toasts = []; new MutationObserver(ms => { for (const m of ms) for (const n of m.addedNodes) if (n.classList && n.classList.contains('toast')) window.__toasts.push({ t: String(n.textContent).replace(/\s+/g, ' ').trim(), err: n.classList.contains('err') }); }).observe(document, { childList: true, subtree: true }); });
    const pg = await ctx.newPage(); const dialogs = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    // kassa holati serverdan kelguncha (kassaProbe localStorage'ga yozadi)
    await pg.waitForFunction(() => { try { const c = JSON.parse(localStorage.getItem('iqror_kassa_v1') || 'null'); return !!(c && c.on); } catch (e) { return false; } }, null, { timeout: 20000 }).catch(() => {});
    await pg.waitForTimeout(400);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).catch(() => {});
    const modalOpen = async () => pg.evaluate(() => document.querySelector('#modal-bg').classList.contains('show'));
    const tmark = async () => pg.evaluate(() => window.__toasts.length);
    const tsince = async n => pg.evaluate(n => window.__toasts.slice(n), n);
    const waitToast = async (n, re, ms) => pg.waitForFunction(([n, s]) => window.__toasts.slice(n).some(t => new RegExp(s).test(t.t)), [n, re.source], { timeout: ms || 20000 }).catch(() => {});
    // «Buxgalteriya»: tugmalar darhol chiziladi, ishlovchilari ma'lumot yuklangach ulanadi — «Yuklanmoqda…» ketguncha kutiladi
    const acReady = async () => { await tab('accounting'); await pg.waitForSelector('#ac-paysal', { timeout: 30000 });
      await pg.waitForFunction(() => { const x = document.querySelector('#ac-body'); return x && !x.querySelector('.loading'); }, null, { timeout: 30000 }); };
    const outbox = async () => pg.evaluate(() => JSON.parse(localStorage.getItem('iqror_pay_outbox_v1') || '[]'));
    const header = async () => pg.$eval('#modal .modal-h h3', e => e.textContent).catch(() => '');
    // ochiq oyna (natija yoki shakl) yopiladi — oldingi qadam kutilmagan natija bersa ham keyingi tekshiruvlar ishlasin
    const closeAny = async () => { if (!(await modalOpen())) return;
      for (const sel of ['#rp-close', '#sp-close', '#m-cancel', '#m-x']) { const el = await pg.$(sel); if (el && await el.isVisible().catch(() => false)) { await el.click().catch(() => {}); break; } }
      await modalGone(); };
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, modalOpen, tmark, tsince, waitToast, acReady, outbox, header, closeAny };
  }
  const invOf = sid => `${sid}__${month}`;
  const payRow = sid => q(`select coalesce(string_agg(amount::bigint || ':' || status, ',' order by "createdAt"), '-') from public.payments where "studentId"='${sid}' and raw->>'manual'='true'`);
  const fiscalDoc = no => q(`select coalesce(string_agg(trim_scale(amount) || ':' || status || ':' || form || ':' || coalesce("partyId",'-'), ','), '-') from public.cash_docs where "fiscalNo"='${no}'`);

  // ---------------- 1) Kassir: «💵 To'lov» — (e) summa maydoni, (d) js-1 rad etilgan yozuv
  const kas = await login(ids.R_KAS);
  const A = 'IQ-0003', B = 'IQ-0006', C2 = 'IQ-0009', D = 'IQ-0012';   // joriy oy fakturasi to'lanmagan o'quvchilar (urug')
  {
    const s = kas; await s.tab('payments');
    const openPay = async sid => { await s.closeAny(); await s.pg.waitForSelector(`#pm-body [data-pay="${invOf(sid)}"]`, { timeout: 30000 }); await s.pg.click(`#pm-body [data-pay="${invOf(sid)}"]`);
      await s.pg.waitForSelector('#rp-save', { timeout: 15000 }); await s.pg.selectOption('#rp-m', 'cash'); await s.pg.waitForSelector('#rp-fiscal', { timeout: 10000 }); };
    const trySave = async (amt, fiscal) => { await s.pg.fill('#rp-amt', amt); if (fiscal != null) await s.pg.fill('#rp-fiscal', fiscal); const n = await s.tmark(); await s.pg.click('#rp-save'); return n; };
    const okHead = async () => s.pg.waitForFunction(() => /To‘lov qabul qilindi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});
    const saveOpen = async () => s.pg.$eval('#rp-save', x => !x.disabled && x.textContent === 'Qabul qilish').catch(() => false);
    await openPay(A);
    let n = await trySave('2.900.000', 'SINOV-F-1001'); await s.waitToast(n, /^Summa noto/, 8000);
    let tt = await s.tsince(n);
    ok('«💵 To‘lov»: «2.900.000» — rad (nuqta mingliklar ajratkichi emas — maydon xatosi), yozuv ham, navbat ham yo‘q, oyna ochiq',
      tt.some(t => t.err && t.t === PM_AMT_ERR) && (await s.outbox()).length === 0 && payRow(A) === '-' && await saveOpen(), tt);
    n = await trySave('1 000 000,50'); await s.waitToast(n, /^Tiyin/, 8000);
    tt = await s.tsince(n);
    ok('«💵 To‘lov»: «1 000 000,50» — rad (tiyin yozilmaydi), yozuv yo‘q, oyna ochiq',
      tt.some(t => t.err && t.t === PM_AMT_TIYIN) && (await s.outbox()).length === 0 && payRow(A) === '-' && await saveOpen(), tt);
    n = await trySave('1 000 000,00'); await okHead();
    ok('«💵 To‘lov»: «1 000 000,00» — qabul: 1 000 000 so‘m, kirim orderi fiskal № bilan, navbat bo‘sh',
      /To‘lov qabul qilindi/.test(await s.header()) && payRow(A) === '1000000:applied' && fiscalDoc('SINOV-F-1001') === `1000000:posted:KO1:${A}` && (await s.outbox()).length === 0,
      [await s.header(), payRow(A), fiscalDoc('SINOV-F-1001'), await s.tsince(n)]);
    await s.closeAny(); await s.pg.waitForTimeout(500);
    // (d) o'sha fiskal № boshqa o'quvchiga — server rad etadi (kassa:fiscal_dup)
    await openPay(B);
    n = await trySave('500 000', 'SINOV-F-1001'); await s.waitToast(n, /^Xatolik: /, 25000);
    let ob = await s.outbox(); tt = await s.tsince(n);
    const failB = ob[0] || {};
    ok('js-1: server rad etgan naqd to‘lov (fiskal № takror) navbatda «Yuborilmadi» bo‘lib qoladi, oyna ochiq, xabar — tuzatib qayta bosing',
      ob.length === 1 && failB.sid === B && failB.status === 'failed' && !failB.final && failB.lastHint === 'kassa:fiscal_dup' && Number(failB.amount) === 500000
      && tt.some(t => t.err && t.t === 'Xatolik: Bu fiskal chek raqami boshqa hujjatda ishlatilgan (SINOV-F-1001) — ma’lumotni tuzatib, «Qabul qilish»ni qayta bosing (shu o‘quvchining rad etilgan yozuvi almashtiriladi) yoki «⏳ navbat»da o‘chiring')
      && await s.modalOpen() && /To‘lov qabul qilish/.test(await s.header()) && await saveOpen() && payRow(B) === '-', { ob, tt });
    n = await trySave('500 000', 'SINOV-F-1002'); await okHead();
    ob = await s.outbox();
    ok('js-1: o‘sha o‘quvchi uchun fiskal № tuzatilib qayta kiritildi — rad etilgan yozuv navbatdan olindi (navbat bo‘sh), to‘lov o‘tdi',
      /To‘lov qabul qilindi/.test(await s.header()) && ob.length === 0 && payRow(B) === '500000:applied' && fiscalDoc('SINOV-F-1002') === `500000:posted:KO1:${B}`
      && q(`select count(*) from public.payments where id='${failB.payId}'`) === '0', { ob, pay: payRow(B), doc: fiscalDoc('SINOV-F-1002') });
    await s.closeAny(); await s.pg.waitForTimeout(500);
    // obSupersede o'quvchi filtri (ichki himoya): oynada o'quvchini almashtirib bo'lmaydi — holat yashirin #rp-sid orqali yaratiladi; foydalanuvchi
    //   yo'li (oyna yopilib, boshqa o'quvchi o'z qatoridan to'lanadi) — pastda alohida
    await openPay(C2);
    n = await trySave('600 000', 'SINOV-F-1001'); await s.waitToast(n, /^Xatolik: /, 25000);
    const failC = (await s.outbox()).find(x => x.sid === C2) || {};
    await s.pg.$eval('#rp-sid', (e, v) => { e.value = v; }, D);
    n = await trySave('600 000', 'SINOV-F-1003'); await okHead();
    ob = await s.outbox();
    ok('js-1 (o‘quvchi filtri — yashirin maydon orqali): shu oynada boshqa o‘quvchi uchun saqlansa — rad etilgan yozuv navbatda «Yuborilmadi» bo‘lib qoladi, yangi to‘lov o‘tdi',
      failC.status === 'failed' && ob.length === 1 && ob[0].payId === failC.payId && ob[0].status === 'failed' && ob[0].sid === C2
      && payRow(D) === '600000:applied' && fiscalDoc('SINOV-F-1003') === `600000:posted:KO1:${D}` && payRow(C2) === '-', { failC, ob, pay: payRow(D) });
    // foydalanuvchi yo'li: rad etilgan oyna yopildi, boshqa o'quvchi o'z qatoridan to'landi — yangi oyna rad etilgan yozuvga tegmaydi
    const E2 = 'IQ-0015';
    await openPay(E2);
    n = await trySave('100 000', 'SINOV-F-1004'); await okHead();
    ob = await s.outbox();
    ok('js-1: rad etilgan oyna yopilib, boshqa o‘quvchi o‘z qatoridan to‘landi — rad etilgan yozuv navbatda «Yuborilmadi» bo‘lib qoladi',
      ob.length === 1 && ob[0].payId === failC.payId && ob[0].status === 'failed' && payRow(E2) === '100000:applied' && fiscalDoc('SINOV-F-1004') === `100000:posted:KO1:${E2}`,
      { ob, pay: payRow(E2), doc: fiscalDoc('SINOV-F-1004') });
    await s.closeAny();
  }
  // ---------------- 2) Kassir: «+ Chiqim so'rovi» — (e) summa maydoni; avans so'rovlari (Direktor kartasiga va uchinchi shaxsga)
  const dirCard = q(`select name from public.staff where "staffId"='IQX-002'`), thirdName = q(`select name from public.teachers where "teacherId"='IQT-003'`);
  let R2 = '', R3 = '', peDir = '';
  {
    const s = kas; await s.kassaReady();
    const newAdv = async nm => { await s.closeAny(); await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'out_advance'); await s.pg.waitForSelector('#kf-pe');
      const v = await s.pg.$eval('#kf-pe', (e, nm) => { const o = [...e.options].find(x => x.textContent.split(' · ')[0] === nm); return o ? o.value : ''; }, nm);
      await s.pg.selectOption('#kf-pe', v); await s.pg.fill('#kf-basis', 'Xodim arizasi, ' + today); await s.pg.waitForTimeout(400); return v; };
    const advCnt = () => q(`select count(*) from public.cash_docs where op='out_advance'`);
    const trySave = async amt => { await s.pg.fill('#kf-amt', amt); const n = await s.tmark(); await s.pg.click('#kf-save'); return n; };
    peDir = await newAdv(dirCard);
    let n = await trySave('2.900.000'); await s.waitToast(n, /^Summa noto/, 8000);
    let tt = await s.tsince(n);
    ok('«+ Chiqim so‘rovi»: «2.900.000» — rad (maydon xatosi), so‘rov yozilmadi, oyna ochiq', tt.some(t => t.err && t.t === AMT_ERR) && advCnt() === '0' && await s.modalOpen() && !!peDir, { tt, peDir });
    n = await trySave('1 000 000,50'); await s.waitToast(n, /^Tiyin/, 8000);
    tt = await s.tsince(n);
    ok('«+ Chiqim so‘rovi»: «1 000 000,50» — rad (tiyin), so‘rov yozilmadi, oyna ochiq', tt.some(t => t.err && t.t === AMT_TIYIN) && advCnt() === '0' && await s.modalOpen(), tt);
    n = await trySave('1 000 000,00'); await s.modalGone();
    R2 = q(`select coalesce(max(id),'') from public.cash_docs where op='out_advance' and "partyId"='${peDir}'`);
    ok('«+ Chiqim so‘rovi»: «1 000 000,00» — qabul: 1 000 000 so‘mlik avans so‘rovi (Direktor bog‘langan kartasiga), tasdiq kutilmoqda',
      !!R2 && q(`select trim_scale(amount) || ':' || status || ':' || "partyType" from public.cash_docs where id='${R2}'`) === '1000000:draft:employee' && !(await s.modalOpen()),
      [R2, q(`select amount, status, "partyType", "partyId" from public.cash_docs where op='out_advance'`), await s.tsince(n)]);
    const pe3 = await newAdv(thirdName); await trySave('400 000'); await s.modalGone();
    R3 = q(`select coalesce(max(id),'') from public.cash_docs where op='out_advance' and "partyId"='${pe3}'`);
  }
  // ---------------- 3) Moliya menejeri (2-ro'yxat) ikkala avansni tasdiqlaydi
  {
    const m = await login(ids.R_MOL); await m.kassaReady();
    for (const id of [R2, R3]) { await m.pg.waitForSelector(`[data-appr="${id}"]`, { timeout: 15000 }).catch(() => {}); await m.pg.click(`[data-appr="${id}"]`).catch(() => {});
      await m.pg.waitForFunction(x => !document.querySelector(`[data-appr="${x}"]`), id, { timeout: 15000 }).catch(() => {}); await m.pg.waitForTimeout(300); }
    await m.ctx.close();
  }
  // ---------------- 4) Direktor: qaytarish oynasi, kassa ishga tushgan — (b) live-1b, kassa:refund_pending, fin:locked
  const dir = await login(ids.R_DIR);
  const pin = q(`select coalesce("refundPin",'') from public.config where id='security'`);
  const X = invOf('IQ-0004'), Y = invOf('IQ-0007');   // joriy oy to'langan fakturalar (urug')
  const refCnt = id => q(`select count(*) from public.refunds where "targetId"='${id}'`);
  const krefCnt = id => q(`select count(*) from public.cash_docs where op='out_refund' and "sourceSnapshot"->>'targetId'='${id}'`);
  const paidOf = id => Number(q(`select coalesce("paidAmount",0)::bigint from public.invoices where id='${id}'`));
  let R1 = '';
  {
    const s = dir;
    // lose[fn] — shu funksiyaning keyingi javobi «yo'qoladi»; gate — berilsa, so'rov shu va'da bajarilguncha ushlab turiladi (yuborish qulfini ko'rish)
    const lose = {}; let held = false, gate = null, openGate = () => {}, nReq = 0;
    for (const fn of ['refund_invoice', 'kassa_refund_request', 'fin_refund_credit']) await s.pg.route(`**/rest/v1/rpc/${fn}`, async route => {
      nReq++;
      if (!lose[fn]) return route.continue();
      lose[fn] = false; held = true;
      if (gate) await gate;
      try { await route.fetch(); } catch (_) { /* server baribir bajaradi */ }
      held = false; return route.abort('failed');
    });
    const openRf = async (sel) => { await s.closeAny(); await s.pg.waitForSelector(sel, { timeout: 30000 }); await s.pg.click(sel); await s.pg.waitForSelector('#rf-method', { timeout: 15000 }); };
    const fillRf = async (amt, payee) => { if (amt != null) await s.pg.fill('#rf-amt', amt); await s.pg.fill('#rf-reason', 'Sinov: javob yo‘qolgan qaytarish'); if (payee) await s.pg.fill('#rf-payee', payee);
      if (await s.pg.$('#rf-pass')) await s.pg.fill('#rf-pass', pin); };
    const btnFree = async () => s.pg.waitForFunction(() => { const x = document.querySelector('#rf-do'); return x && !x.disabled; }, null, { timeout: 20000 }).catch(() => {});
    await s.tab('payments');
    // 4a) X: «Naqdsiz» — yuborilayotganda tugma va usul qulflangan; javob yo'qoladi (qaytarish yozilgan), usul qulflangan qoladi
    await openRf(`#pm-body [data-refund="${X}"]`);
    const rfm = await s.pg.$$eval('#rf-method option', o => o.map(x => x.value + '=' + x.textContent));
    await s.pg.selectOption('#rf-method', 'bank'); await fillRf('200 000');
    const px0 = paidOf(X);
    gate = new Promise(r => { openGate = r; }); lose.refund_invoice = true; nReq = 0;
    let n = await s.tmark(); await s.pg.click('#rf-do');
    for (let i = 0; i < 100 && !held; i++) await s.pg.waitForTimeout(50);
    const st = await s.pg.evaluate(() => [document.querySelector('#rf-do').disabled, document.querySelector('#rf-do').textContent, document.querySelector('#rf-method').disabled]);
    ok('qaytarish oynasi (kassa ishga tushgan): usul — naqd / naqdsiz; «Naqdsiz» yuborilayotganda tugma («Qaytarilmoqda…») va usul tanlovi qulflangan',
      rfm.join('|') === 'cash=Naqd — kassadan (chiqim orderi bilan)|bank=Naqdsiz (bank / karta orqali — asl kanal)' && held && st[0] === true && st[1] === 'Qaytarilmoqda…' && st[2] === true && nReq === 1,
      { rfm, st, held, nReq });
    openGate(); gate = null; await btnFree();
    let tt = await s.tsince(n);
    ok('«Naqdsiz» javobi yo‘qoldi: qaytarish yozilgan (1 ta), oyna ochiq, usul tanlovi qulflangan qoladi (shu oynada boshqa usulga o‘tilmaydi)',
      refCnt(X) === '1' && paidOf(X) === px0 - 200000 && await s.modalOpen() && await s.pg.$eval('#rf-method', e => e.disabled) && (await s.pg.$eval('#rf-do', x => x.textContent)) === 'Qaytarish'
      && tt.some(t => t.err && /^Xatolik: /.test(t.t)), { n: refCnt(X), paid: [px0, paidOf(X)], tt });
    // usul majburan «Naqd»ga (qulfsiz eski sahifa / DOM o'zgartirilgan) — server o'sha oyna kalitini rad etadi (kassa:ref_mismatch)
    await s.pg.$eval('#rf-method', e => { e.disabled = false; }); await s.pg.selectOption('#rf-method', 'cash'); await s.pg.fill('#rf-payee', 'Sinov Ota Onaevich');
    n = await s.tmark(); await s.pg.click('#rf-do'); await s.modalGone();
    tt = await s.tsince(n);
    ok('o‘sha oynadan (usul majburan almashtirilib) naqd so‘rov — server rad etadi (kassa:ref_mismatch matni), oyna yopildi, naqd so‘rov yo‘q',
      tt.some(t => t.err && t.t === "Bu oynadan naqdsiz (bank / karta) qaytarish allaqachon yozilgan (javob yo'qolgan bo'lishi mumkin) — «To'lovlar»da tekshiring; naqd qaytarish ham kerak bo'lsa, oynani yopib, qaytadan oching")
      && !(await s.modalOpen()) && krefCnt(X) === '0' && refCnt(X) === '1', { tt, kref: krefCnt(X) });
    await s.pg.waitForTimeout(600);
    // 4b) Y: naqd so'rov — javob yo'qoladi (so'rov yozilgan), keyin o'sha oynadan «Naqdsiz» — rad (via cash)
    await openRf(`#pm-body [data-refund="${Y}"]`);
    await fillRf('300 000', 'Sinov Ota Onaevich');
    const py0 = paidOf(Y);
    lose.kassa_refund_request = true; n = await s.tmark();
    await s.pg.click('#rf-do'); await btnFree();
    R1 = q(`select coalesce(max(id),'') from public.cash_docs where op='out_refund' and "sourceSnapshot"->>'targetId'='${Y}'`);
    ok('naqd qaytarish so‘rovi javobi yo‘qoldi: so‘rov yozilgan (tasdiqlangan — Direktor yolg‘iz tasdig‘i, pul berilmagan), oyna ochiq, usul qulflangan',
      krefCnt(Y) === '1' && q(`select status || ':' || ("dirApprovedBy" = '${ids.R_DIR}') || ':' || coalesce("approvedBy",'-') || ':' || trim_scale(amount) from public.cash_docs where id='${R1}'`) === 'approved:true:-:300000'
      && await s.modalOpen() && await s.pg.$eval('#rf-method', e => e.disabled) && refCnt(Y) === '0', { R1, kref: krefCnt(Y), tt: await s.tsince(n) });
    await s.pg.$eval('#rf-method', e => { e.disabled = false; }); await s.pg.selectOption('#rf-method', 'bank');
    n = await s.tmark(); await s.pg.click('#rf-do'); await s.modalGone();
    tt = await s.tsince(n);
    ok('o‘sha oynadan «Naqdsiz» — rad: «Bu oynadan avval naqd qaytarish so‘rovi yuborilgan …», oyna yopildi, ikkinchi qaytarish yo‘q',
      tt.some(t => t.err && t.t === 'Bu oynadan avval naqd qaytarish so‘rovi yuborilgan — javob yo‘qolgan bo‘lishi mumkin: «Kassa» → «So‘rovlar»ni tekshiring')
      && !(await s.modalOpen()) && refCnt(Y) === '0' && paidOf(Y) === py0 && krefCnt(Y) === '1', { tt, ref: refCnt(Y) });
    await s.pg.waitForTimeout(600);
    // 4c) kassa:refund_pending — Y bo'yicha pul berilmagan naqd so'rov bor: naqdsiz qaytarish bilan jami to'langandan oshadi
    await openRf(`#pm-body [data-refund="${Y}"]`);
    await s.pg.selectOption('#rf-method', 'bank'); await fillRf(fmt(py0 - 300000 + 100000));
    n = await s.tmark(); await s.pg.click('#rf-do'); await s.waitToast(n, /^Xatolik: /); await btnFree();
    tt = await s.tsince(n);
    ok('kassa:refund_pending — naqdsiz qaytarish kutilayotgan naqd so‘rov bilan jami to‘langandan oshsa: rad (o‘zbekcha matn, kodsiz), oyna ochiq',
      tt.some(t => t.err && t.t === `Xatolik: Bu hisob-faktura bo'yicha pul hali berilmagan naqd qaytarish so'rovi bor (300000 so'm): yangisi bilan jami to'langan summadan (${py0} so'm) oshadi — avval o'sha so'rovni kassadan bering yoki «Kassa»da bekor qiling`)
      && await s.modalOpen() && refCnt(Y) === '0', tt);
    await s.closeAny();
    // 4d) fin:locked — o'tgan oy yopildi: shu oy sanali biriktirilmagan to'lovni naqdsiz qaytarish rad etiladi
    const lk = tryQ(() => asUser(ids.R_DIR, `select public.fin_period_lock('${prevEnd}', 'Sinov: o‘tgan oy yopildi')::text`));
    await openRf(`#pm-body [data-refund-pay="${UNM}"]`);
    await s.pg.selectOption('#rf-method', 'bank'); await fillRf(null);
    n = await s.tmark(); await s.pg.click('#rf-do'); await s.waitToast(n, /^Xatolik: /); await btnFree();
    tt = await s.tsince(n);
    ok('fin:locked — yopilgan davrdagi biriktirilmagan to‘lovni qaytarish rad (o‘zbekcha matn, kodsiz), to‘lov va jurnal o‘zgarmadi, oyna ochiq',
      tt.some(t => t.err && t.t === `Xatolik: To‘lov (${dmy(prevM + '-10')} kuni) yopilgan davrga tegishli (${dmy(prevEnd)} gacha yopilgan): uning holati yoki o'quvchisi o'zgarsa (qaytarish, bekor qilish, biriktirish) o'sha oy tushumi o'zgaradi. Kerak bo'lsa Direktor «Davr»da davrni sababi bilan qayta ochadi, amaldan keyin qayta yopadi`)
      && q(`select status from public.payments where id='${UNM}'`) === 'unmatched' && refCnt(UNM) === '0' && await s.modalOpen(), { lk, tt });
    await s.closeAny();
    tryQ(() => asUser(ids.R_DIR, `select public.fin_period_lock(null, 'Sinov: davr qayta ochildi')::text`));
    // 4e) F2.11 (reliz 20): o'quvchi avansini NAQDSIZ qaytarish — «📋» tarix → «↩ Avansni qaytarish»: usul tanlovi (naqd / bank / karta);
    //   «Bank» — javob yo'qoladi (qaytarish yozilgan), o'sha oynadan qayta bosilsa «avval yozilgan» (ikkinchi qaytarish yo'q); bazada avans
    //   kamaydi, qaytarishlar jurnali (bank, kimga), avans harakati (refund, bank), kassa hujjati yo'q; tarixda «Avans qaytarildi (naqdsiz)»
    const CS = 'IQ-0013';   // joriy oy fakturasi to'langan o'quvchi (urug'), avansi sintetik
    q(`set session_replication_role = replica;
       insert into public.student_credit (id, "studentId", credit) values ('${CS}', '${CS}', 700000) on conflict (id) do update set credit = excluded.credit;
       insert into public.credit_ledger (id, "studentId", "studentName", delta, "balanceAfter", reason, note, "at") values ('e2e_cl_15', '${CS}', '', 700000, 700000, 'overpay', 'Sinov: ortiqcha to‘lov', now());
       set session_replication_role = origin;`);
    const crOf = () => q(`select coalesce((select trim_scale(credit)::text from public.student_credit where id = '${CS}'), '-')`);
    const crefRows = () => q(`select count(*) || '|' || coalesce(string_agg(trim_scale(amount) || ':' || coalesce(method, '-') || ':' || coalesce(payee, '-'), ','), '-') from public.refunds where target = 'credit' and "studentId" = '${CS}'`);
    const openHist = async () => { await s.closeAny(); await s.tab('payments'); await s.pg.waitForSelector(`#pm-body [data-hist="${CS}"]`, { timeout: 30000 });
      await s.pg.click(`#pm-body [data-hist="${CS}"]`); await s.pg.waitForFunction(() => { const b = document.querySelector('#ph-body'); return b && !b.querySelector('.loading'); }, null, { timeout: 15000 }); };
    await openHist();
    const hasCref = !!(await s.pg.$('#ph-cref'));
    if (hasCref) { await s.pg.click('#ph-cref'); await s.pg.waitForSelector('#rf-cmethod', { timeout: 15000 }); }
    const cmo = hasCref ? await s.pg.$$eval('#rf-cmethod option', o => o.map(x => x.value)) : [];
    const head = await s.header();
    const reqShown = async () => s.pg.$eval('#rf-reqbox', e => getComputedStyle(e).display !== 'none').catch(() => null);
    const req0 = await reqShown();
    if (hasCref) await s.pg.selectOption('#rf-cmethod', 'bank');
    const cnote = await s.pg.$eval('#rf-cnote', e => e.textContent.replace(/\s+/g, ' ').trim()).catch(() => '');
    const cbtn = await s.pg.$eval('#rf-do', e => e.textContent).catch(() => '');
    const req1 = await reqShown();
    ok('avans (F2.11): «📋» tarix → «↩ Avansni qaytarish» — oyna «O‘quvchi avansini qaytarish», usul: naqd / bank / karta; «Bank» — kassa hujjatisiz, tugma «Qaytarish», ariza sanasi (naqd so‘rov uchun) yashirin',
      hasCref && head.includes('O‘quvchi avansini qaytarish') && cmo.join('|') === 'cash|bank|card' && cnote.startsWith('Avans darhol kamayadi (kassa hujjati yo‘q)')
        && cnote.includes('Dt 6310 Kt 5110') && cbtn === 'Qaytarish' && req0 === true && req1 === false, { hasCref, head, cmo, cnote, cbtn, req0, req1 });
    await s.pg.fill('#rf-amt', '300 000'); await s.pg.fill('#rf-reason', 'Sinov: o‘quvchi maktabdan ketdi'); await s.pg.fill('#rf-payee', 'Sinov Ota Onaevich');
    if (await s.pg.$('#rf-pass')) await s.pg.fill('#rf-pass', pin);
    const dl5 = s.dialogs.length;
    lose.fin_refund_credit = true; n = await s.tmark(); await s.pg.click('#rf-do'); await s.waitToast(n, /^Xatolik: /); await btnFree();
    tt = await s.tsince(n);
    ok('«Bank» — tasdiq matni (bank o‘tkazmasi, kimga, sabab); javob yo‘qoldi: qaytarish yozilgan (avans 400 000), oyna ochiq, usul tanlovi qulflangan',
      s.dialogs.slice(dl5).some(m => m.includes('O‘quvchi avansidan') && m.includes('bank o‘tkazmasi orqali qaytarilsinmi?') && m.includes('Kimga: Sinov Ota Onaevich'))
        && crOf() === '400000' && crefRows() === '1|300000:bank:Sinov Ota Onaevich' && await s.modalOpen() && await s.pg.$eval('#rf-cmethod', e => e.disabled)
        && tt.some(t => t.err && /^Xatolik: /.test(t.t)), { d: s.dialogs.slice(dl5), cr: crOf(), ref: crefRows(), tt });
    n = await s.tmark(); await s.pg.click('#rf-do'); await s.modalGone();
    tt = await s.tsince(n);
    const led = q(`select count(*) || '|' || coalesce(string_agg(trim_scale(delta) || ':' || reason || ':' || coalesce(provider, '-') || ':' || trim_scale("balanceAfter"), ','), '-') from public.credit_ledger where "studentId" = '${CS}' and reason = 'refund'`);
    const kdoc = q(`select count(*) from public.cash_docs where op = 'out_refund' and "sourceSnapshot" ->> 'studentId' = '${CS}'`);
    ok('o‘sha oynadan qayta bosildi — «Qaytarish avval yozilgan ✓» (ikkinchi qaytarish yo‘q), oyna yopildi; bazada: avans harakati (−300 000, refund, bank), kassa hujjati yo‘q',
      tt.some(t => !t.err && t.t.startsWith('Qaytarish avval yozilgan ✓') && t.t.includes('bank o‘tkazmasi')) && !(await s.modalOpen()) && crOf() === '400000'
        && crefRows() === '1|300000:bank:Sinov Ota Onaevich' && led === '1|-300000:refund:bank:400000' && kdoc === '0', { tt, cr: crOf(), ref: crefRows(), led, kdoc });
    await openHist();
    const ph = await s.pg.$eval('#ph-body', e => e.innerText.replace(/\s+/g, ' ')).catch(() => '');
    ok('«📋» tarix: joriy avans 400 000, harakatlarda «Avans qaytarildi (naqdsiz) · Avans bank o‘tkazmasi orqali qaytarildi: …» (izoh — server matni)',
      /joriy avans: 400[ \u00a0]000/.test(ph) && ph.includes("Avans qaytarildi (naqdsiz) · Avans bank o'tkazmasi orqali qaytarildi: Sinov: o‘quvchi maktabdan ketdi"), ph.slice(ph.indexOf('Avans harakat') > 0 ? ph.indexOf('Avans harakat') : 0, 900));
    await s.closeAny();
    await s.pg.unroute('**/rest/v1/rpc/refund_invoice'); await s.pg.unroute('**/rest/v1/rpc/kassa_refund_request'); await s.pg.unroute('**/rest/v1/rpc/fin_refund_credit');
  }
  // ---------------- 5) Direktor: «Kassa» → «So'rovlar» — (c) sec-1: o'zi yolg'iz tasdiqlagan / o'ziga beriladigan pul — tugma yo'q
  const salCnt = tid => q(`select count(*) from public.salary_payments where "teacherId"='${tid}'`);
  {
    const s = dir; await s.kassaReady();
    await s.pg.waitForSelector(`[data-cancel="${R3}"]`, { timeout: 15000 }).catch(() => {});
    ok('Direktor «So‘rovlar»: o‘zi yolg‘iz tasdiqlagan qaytarish so‘rovida «Pulni berish» yo‘q (kassir beradi)',
      !!R1 && !!(await s.pg.$(`[data-cancel="${R1}"]`)) && !(await s.pg.$(`[data-pay="${R1}"]`)), R1);
    ok('Direktor «So‘rovlar»: o‘zining bog‘langan xodim kartasiga KO-2 (2-ro‘yxat tasdiqlagan avans) — «Pulni berish» yo‘q (FD-48)',
      !!R2 && q(`select status from public.cash_docs where id='${R2}'`) === 'approved' && !!(await s.pg.$(`[data-cancel="${R2}"]`)) && !(await s.pg.$(`[data-pay="${R2}"]`)), R2);
    const has3 = !!(await s.pg.$(`[data-pay="${R3}"]`));
    if (has3) { await s.pg.click(`[data-pay="${R3}"]`); await s.pg.waitForFunction(x => !document.querySelector(`[data-pay="${x}"]`), R3, { timeout: 20000 }).catch(() => {}); await s.pg.waitForTimeout(500); }
    ok('Direktor: 2-ro‘yxat tasdiqlagan uchinchi shaxs so‘rovida «Pulni berish» bor — favqulodda pul berdi (order o‘tdi, avans yozildi)',
      has3 && q(`select status from public.cash_docs where id='${R3}'`) === 'posted'
      && q(`select trim_scale(amount) || ':' || ("cashDocId" = '${R3}') from public.staff_advances where "teacherId"='IQT-003'`) === '400000:true', [has3, q(`select status from public.cash_docs where id='${R3}'`)]);
    // «Maosh berish» → «Naqd» o'z kartasiga — server rad etadi; xabar — serverning o'zbekcha matni (prefikssiz)
    await s.closeAny(); await s.acReady(); await s.pg.click('#ac-paysal'); await s.pg.waitForSelector('#sp-method', { timeout: 30000 });
    await s.pg.selectOption('#sp-t', 'IQX-002');
    await s.pg.waitForFunction(() => { const x = document.querySelector('#sp-do'); return x && !x.disabled; }, null, { timeout: 30000 });
    await s.pg.selectOption('#sp-method', 'cash'); await s.pg.fill('#sp-paid', '500 000');
    const n = await s.tmark(); await s.pg.click('#sp-do'); await s.waitToast(n, /FD-48|^Xatolik/);
    await s.pg.waitForFunction(() => { const x = document.querySelector('#sp-do'); return x && !x.disabled; }, null, { timeout: 15000 }).catch(() => {});
    const tt = await s.tsince(n);
    ok('Direktor o‘ziga (bog‘langan kartasiga) naqd maosh: server matni (FD-48) «Xatolik: 42501» prefiksisiz; maosh yozilmadi, oyna ochiq',
      tt.some(t => t.err && t.t === `Bu maosh sizga (bog'langan xodim kartangizga) beriladi — Direktor o'ziga naqd maoshni o'zi bermaydi: pulni kassir beradi (FD-48). ${month} oy maoshi HR tasdiqlagan vedomostsiz (o'tish oyidan oldin) — bunday oyda kassir naqd maosh bermaydi: maoshingizni karta orqali yozing`)
      && !tt.some(t => /^Xatolik/.test(t.t)) && salCnt('IQX-002') === '0' && await s.modalOpen() && !!(await s.pg.$('#sp-method')), tt);
    await s.closeAny();
  }
  // ---------------- 6) Kassir: Direktor bermaydigan pul — kassir beradi (qaytarish va Direktor kartasiga avans)
  {
    const s = kas; await s.kassaReady();
    const seen = [!!(await s.pg.$(`[data-pay="${R1}"]`)), !!(await s.pg.$(`[data-pay="${R2}"]`))];
    ok('Kassir «So‘rovlar»: Direktor tasdiqlagan qaytarish va Direktor kartasiga avans — «Pulni berish» bor', seen[0] && seen[1], seen);
    const py1 = paidOf(Y);
    for (const id of [R1, R2]) { if (!(await s.pg.$(`[data-pay="${id}"]`))) continue; await s.pg.click(`[data-pay="${id}"]`);
      await s.pg.waitForFunction(x => !document.querySelector(`[data-pay="${x}"]`), id, { timeout: 20000 }).catch(() => {}); await s.pg.waitForTimeout(500); }
    ok('Kassir pulni berdi: qaytarish (faktura 300 000 ga kamaydi, jurnal — naqd, kassir) va Direktor kartasiga avans (KO-2 o‘tdi, avans yozildi)',
      q(`select status from public.cash_docs where id='${R1}'`) === 'posted' && paidOf(Y) === py1 - 300000
      && q(`select trim_scale(amount) || ':' || method || ':' || ("byUid" = '${ids.R_KAS}') from public.refunds where "cashDocId"='${R1}'`) === '300000:cash:true'
      && q(`select status from public.cash_docs where id='${R2}'`) === 'posted'
      && q(`select trim_scale(amount) || ':' || method || ':' || ("cashDocId" = '${R2}') from public.staff_advances where "teacherId"='IQX-002'`) === '1000000:cash:true',
      [q(`select id, status from public.cash_docs where id in ('${R1}','${R2}')`), paidOf(Y), q(`select amount, method from public.refunds where "cashDocId"='${R1}'`), q(`select amount, method, "cashDocId" from public.staff_advances where "teacherId"='IQX-002'`)]);
    await s.pg.screenshot({ path: `${OUT}/k15-kas-${UI}-1440.png`, fullPage: true });
  }
  // ---------------- 7) kun yopiladi (kassir), kassa to'xtatiladi (Direktor: «ishga tushadigan kun» bo'shatiladi)
  {
    const bal = q(`select trim_scale(app.kassa_day_balance(id)) from public.cash_days where desk='main' and status='open'`);
    const cl = tryQ(() => asUser(ids.R_KAS, `select public.kassa_day_close('{"desk":"main","day":"${today}","counted":${bal || 0},"expected":${bal || 0},"pendingRefs":[],"note":"Sinov: kun yopildi","commission":[{"title":"Kassir","name":"Sinov Kassir"},{"title":"Moliya menejeri","name":"Sinov Moliyachi"}]}'::jsonb)::text`));
    const ps = tryQ(() => asUser(ids.R_DIR, `select public.fin_org_set('{"kassaGoLive":null}'::jsonb)::text`));
    ok('kassa to‘xtatildi: kun yopilgan, so‘rovlar bajarilgan — «ishga tushadigan kun» bo‘shatildi',
      q(`select ("pausedAt" is not null)::text from public.cash_desks where id='main'`) === 'true' && q(`select coalesce("kassaGoLive"::text,'-') from public.fin_org where id='main'`) === '-'
      && q(`select count(*) from public.cash_days where desk='main' and status='open'`) === '0', { bal, cl: String(cl).slice(0, 300), ps: String(ps).slice(0, 300) });
  }
  // ---------------- 8) Direktor: (f) kassa to'xtatilgan — «Buxgalteriya» oynalarida usul tanlovi
  {
    const s = dir;
    await s.pg.reload();
    await s.pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await s.pg.waitForFunction(() => { try { const c = JSON.parse(localStorage.getItem('iqror_kassa_v1') || 'null'); return !!(c && c.on && !c.goLive); } catch (e) { return false; } }, null, { timeout: 20000 }).catch(() => {});
    await s.pg.waitForTimeout(400);
    await s.acReady(); await s.pg.click('#ac-paysal'); await s.pg.waitForSelector('#sp-do', { timeout: 30000 });
    const hm = await s.pg.$$eval('#sp-hmethod option', o => o.map(x => x.value + '=' + x.textContent)).catch(() => []);
    const mt = await s.pg.$eval('#modal', e => e.textContent).catch(() => '');
    ok('kassa to‘xtatilgan: «Maosh berish»da usul tanlovi (#sp-hmethod: naqd — to‘xtatilgan davr sanasi bilan / karta) va ogohlantirish, kassa usuli yo‘q',
      hm.join('|') === 'cash=Naqd — to‘xtatilgan davr sanasi bilan (orderisiz)|card=Karta / bank orqali' && mt.includes('Kassa to‘xtatilgan (yoki qayta ishga tushirish kunini kutmoqda).') && !(await s.pg.$('#sp-method')),
      { hm, mt: mt.slice(0, 300) });
    await s.pg.selectOption('#sp-t', 'IQT-002');
    await s.pg.waitForFunction(() => { const x = document.querySelector('#sp-do'); return x && !x.disabled; }, null, { timeout: 30000 }).catch(() => {});
    if (await s.pg.$('#sp-hmethod')) await s.pg.selectOption('#sp-hmethod', 'card');
    await s.pg.fill('#sp-paid', '100 000'); await s.pg.click('#sp-do');
    await s.pg.waitForFunction(() => /Maosh berildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 30000 }).catch(() => {});
    ok('… «Karta» tanlansa — maosh karta usuli bilan, kassa orderisiz yozildi',
      q(`select method || ':' || coalesce("cashDocId",'-') || ':' || trim_scale(paid) from public.salary_payments where "teacherId"='IQT-002'`) === 'card:-:100000',
      q(`select method, "cashDocId", paid from public.salary_payments where "teacherId"='IQT-002'`));
    await s.closeAny();
    await s.pg.click('#ac-add'); await s.pg.waitForSelector('#xe-save', { timeout: 15000 });   // F2.1 hujjat oynasi
    const em = await s.pg.$$eval('#xe-method option', o => o.map(x => x.value + '=' + x.textContent)).catch(() => []);
    ok('… xarajat oynasi: usul tanlovi (naqd — to‘xtatilgan davr sanasi bilan / bank / karta)',
      em.join('|') === 'cash=Naqd — to‘xtatilgan davr sanasi bilan (orderisiz)|bank=Bank o‘tkazmasi|card=Korporativ karta' && !(await s.pg.$('#xe-kassa')), em);
    await s.closeAny();
    await s.pg.click('#ac-adv'); await s.pg.waitForSelector('#av-save', { timeout: 30000 });
    const am = await s.pg.$$eval('#av-hmethod option', o => o.map(x => x.value + '=' + x.textContent)).catch(() => []);
    ok('… avans oynasi: usul tanlovi #av-hmethod (naqd — to‘xtatilgan davr sanasi bilan / karta)',
      am.join('|') === 'cash=Naqd — to‘xtatilgan davr sanasi bilan (orderisiz)|card=Karta / bank orqali' && !(await s.pg.$('#av-kassa')), am);
    await s.closeAny();
    await s.pg.screenshot({ path: `${OUT}/k15-dir-${UI}-1440.png`, fullPage: true });
  }
  await dir.ctx.close(); await kas.ctx.close();
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  q(`delete from app.fin_clock`);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); try { q(`delete from app.fin_clock`); } catch (_) {} process.exit(1); });
