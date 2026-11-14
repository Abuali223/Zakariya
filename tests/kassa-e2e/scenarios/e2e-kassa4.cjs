// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F1.15 — kunlik hisobot (RP-02), «kimdan / kimga qancha», nazorat ro'yxati (RP-06).
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa4.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
// foydalanuvchi nomidan RPC (bitta tranzaksiya): oxirgi qator — natija
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()');
  const dm = today.slice(8, 10) + '.' + today.slice(5, 7) + '.' + today.slice(0, 4);
  async function login(uid, vp) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage(); const dialogs = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const ctl = async () => { await pg.waitForSelector('#ks-ctl-card:not([data-stale])', { timeout: 15000 });
      await pg.$eval('#ks-ctl-card details', d => { d.open = true; });   // «joyida» qatorlari ham o'qilsin
      return pg.$$eval('#ks-ctl-card tr[data-ctl]', xs => Object.fromEntries(xs.map(x => [x.dataset.ctl, { level: x.dataset.level, text: x.innerText.replace(/\s+/g, ' ').trim() }]))); };
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, printed, ctl };
  }
  const receipt = async (s, name, amt) => {
    await s.pg.click('#ks-in'); await s.pg.waitForSelector('#kf-op');
    await s.pg.selectOption('#kf-op', 'in_other'); await s.pg.waitForSelector('#kf-ptype');
    await s.pg.selectOption('#kf-ptype', 'other'); await s.pg.waitForSelector('#kf-po'); await s.pg.fill('#kf-po', name);
    await s.pg.selectOption('[data-art="0"]', 'IN-06'); await s.pg.fill('#kf-amt', amt);
    await s.pg.fill('#kf-basis', 'Sinov asos, ' + today); await s.pg.fill('#kf-note', 'Sinov izohi');
    await s.pg.click('#kf-save'); await s.modalGone(); await s.pg.waitForTimeout(700);
  };

  // ---------------- 1) Direktor: boshlang'ich qoldiq, sozlamalar (limit 2 000 000)
  {
    const s = await login(ids.R_DIR); await s.kassaReady();
    await s.pg.click('#ks-opening'); await s.pg.waitForSelector('#ko-amt');
    await s.pg.fill('#ko-amt', '1 000 000'); await s.pg.fill('#ko-day', today);
    await s.pg.fill('[data-ct="0"]', 'Direktor o‘rinbosari'); await s.pg.fill('[data-cn="0"]', 'Sinov A.A.');
    await s.pg.fill('[data-ct="1"]', 'Buxgalter'); await s.pg.fill('[data-cn="1"]', 'Sinov B.B.');
    await s.pg.click('#ko-save'); await s.modalGone();
    await s.pg.waitForSelector('#ks-set'); await s.pg.click('#ks-set'); await s.pg.waitForSelector('#kx-name');
    await s.pg.fill('#kx-name', '«SINOV MAKTAB» МЧЖ'); await s.pg.fill('#kx-t1', '500 000'); await s.pg.fill('#kx-l1', '200 000'); await s.pg.fill('#kx-orgmax', '1 000 000 000');
    await s.pg.fill('#kx-limit', '2 000 000'); await s.pg.fill('#kx-live', today);
    await s.pg.click('#kx-save'); await s.modalGone();
    // sahifa yangi sozlamalar bilan qayta chizilguncha kutamiz (aks holda oldingi yuklashdagi karta o'qiladi)
    await s.pg.waitForFunction(() => !/deb belgilanmagan/.test(document.querySelector('#ks-body').textContent), null, { timeout: 15000 });
    const c = await s.ctl();
    ok('direktor: nazorat ro‘yxati ko‘rinadi — 22 tekshiruv (Z-hisobot, yuridik shaxsga naqd bilan), hammasi joyida', Object.keys(c).length === 22 && Object.values(c).every(x => x.level === 'ok') && /Hammasi joyida/.test(await s.pg.$eval('#ks-ctl-card', e => e.innerText)),
      Object.entries(c).filter(x => x[1].level !== 'ok'));
    ok('nazorat: moslik — «hammasi mos», limit — oshmagan', /hammasi mos/.test(c.reconcile.text) && /limit 2 000 000 so‘m — oshmagan/.test(c.limit.text), [c.reconcile, c.limit]);
    await s.ctx.close();
  }

  // ---------------- 2) Kassir: kirimlar, o'quv to'lovi, chiqim; kun oynasi va kunlik hisobot (ochiq kun)
  const sid = 'IQ-0003', sname = q(`select name from public.students where "studentId"='IQ-0003'`);   // sintetik urug'dagi o'quvchi
  const kas = await login(ids.R_KAS);
  {
    const s = kas; await s.kassaReady();
    ok('kassir: nazorat ro‘yxati yo‘q (2-ro‘yxat va Direktor uchun)', !(await s.pg.$('#ks-ctl-card')) && !(await s.pg.$('#ks-ctl')));
    await receipt(s, 'Sinov To‘lovchi Tashkiloti', '250 000');
    await receipt(s, 'SINOV  to‘lovchi tashkiloti', '50 000');
    // naqd o'quv to'lovi (kassir nomidan; «To'lov» oynasi alohida ssenariyda sinalgan) va Click to'lovi (kassaga kirmaydi)
    const pay = asUser(ids.R_KAS, `select public.record_manual_payment('man_e4_0001', '${sid}', 400000, 'cash', null, '', '', 'Sinov Ota', null, '{"fiscalNo":"900001"}'::jsonb)::text`);
    ok('naqd o‘quv to‘lovi kirim orderi bilan yozildi', /"kassa": \{/.test(pay) && /"no": 3/.test(pay), pay.slice(0, 300));
    q(`set session_replication_role = replica; insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values ('clk_e4_1', '${sid}', 'click', 300000, 'applied', true, '{}', app.fin_now())`);
    // chiqim: yangi kontragentga xarajat 120 000 → Moliya menejeri tasdiqlaydi → kassir beradi
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'out_expense'); await s.pg.waitForSelector('#kf-pnew');
    await s.pg.click('#kf-pnew'); await s.pg.fill('#kf-cn', 'Sinov Ta’minot MChJ'); await s.pg.click('#kf-cadd');
    await s.pg.waitForFunction(() => { const e = document.querySelector('#kf-pc'); return e && e.value; }, null, { timeout: 10000 });
    const arts = await s.pg.$eval('#kf-lines [data-art="0"]', e => [...e.options].map(o => o.value).filter(Boolean));
    await s.pg.selectOption('#kf-lines [data-art="0"]', arts[0]); await s.pg.fill('#kf-lines [data-lamt="0"]', '120 000');
    await s.pg.fill('#kf-basis', 'Hisob-faktura № 7'); await s.pg.click('#kf-save'); await s.modalGone();
    const exId = q(`select id from public.cash_docs where op='out_expense'`);
    asUser(ids.R_MOL, `select public.kassa_doc_approve('${exId}')::text`);
    await s.kassaReady();
    await s.pg.click(`[data-pay="${exId}"]`); await s.pg.waitForTimeout(1500);
    ok('chiqim orderi berildi (Ch-1)', q(`select status || ':' || no from public.cash_docs where id='${exId}'`) === 'posted:1', q(`select status, no from public.cash_docs where id='${exId}'`));
    // yana bir so'rov — tasdiq kutadi («kutilayotganlar»)
    asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_expense","amount":70000,"partyType":"other","partyName":"Sinov Usta","basis":"Shartnoma № 3","clientRef":"e4-w1-0001","lines":[{"articleId":"${arts[0]}","amount":70000}]}'::jsonb)::text`);
    await s.kassaReady();
    ok('ochiq kun kartasida «Kunlik hisobot» tugmasi', !!(await s.pg.$(`[data-report="${today}"]`)));
    // kun oynasi: «kimdan / kimga qancha»
    await s.pg.click(`[data-view="${today}"]`); await s.pg.waitForSelector('#kdv-who', { timeout: 15000 });
    const who = await s.pg.$eval('#kdv-who', e => e.innerText.replace(/\s+/g, ' '));
    ok('kun oynasi: «Kimdan» — «boshqa» tomon bitta qatorga jamlangan (2 hujjat, 300 000)', /Kimdan — 700 000 so‘m/.test(who) && /[Ss](inov|INOV) +[Tt]o‘lovchi [Tt]ashkiloti boshqa 2 300 000 so‘m/.test(who), who.slice(0, 500));
    ok('kun oynasi: o‘quvchi — kaliti (kodi) va ma’lumotnomadagi ismi bilan', who.includes(`${sname} ${sid} o‘quvchi 1 400 000 so‘m`), who.slice(0, 500));
    ok('kun oynasi: «Kimga» — kontragent', /Kimga — 120 000 so‘m/.test(who) && /Sinov Ta’minot MChJ kontragent 1 120 000 so‘m/.test(who), who.slice(0, 600));
    await s.pg.screenshot({ path: `${OUT}/day-who-${UI}-1440.png` });
    const before = (await s.printed()).length;
    await s.pg.click('#kdv-report'); await s.pg.waitForTimeout(1500);
    const pr = (await s.printed()).slice(before);
    const rp = pr.find(t => /KASSIRNING KUNLIK HISOBOTI/.test(t)) || '';
    ok('kunlik hisobot (ochiq kun): sarlavha, «QORALAMA», tashkilot, kun holati', /QORALAMA/.test(rp) && /SINOV MAKTAB/.test(rp) && /kun ochiq/.test(rp) && /Kun hali yopilmagan — pul sanalmagan/.test(rp), rp.slice(0, 400));
    ok('kunlik hisobot: kun boshi 1 000 000 + kirim 700 000 (3 ta) − chiqim 120 000 (1 ta) = 1 580 000',
      /Kun boshiga qoldiq 1 000 000=00/.test(rp) && /Kirim \(3 ta order\) 700 000=00/.test(rp) && /Chiqim \(1 ta order\) 120 000=00/.test(rp) && /Kun oxiriga qoldiq 1 580 000=00/.test(rp), rp.slice(0, 700));
    ok('kunlik hisobot: orderlar ro‘yxati, «kimdan / kimga qancha», statiya bo‘yicha',
      /2\. Kirim orderlari/.test(rp) && /K-3 .*O‘quv haqi \(naqd\) — O‘quv to‘lovi/.test(rp) && /3\. Chiqim orderlari/.test(rp) && /Ch-1 .*Sinov Ta’minot MChJ Xarajat — Hisob-faktura № 7/.test(rp)
      && /4\. Kimdan qancha/.test(rp) && /boshqa \(yozilgan\) 2 300 000=00/.test(rp) && /5\. Kimga qancha/.test(rp) && /6\. Statiya bo‘yicha/.test(rp) && /IN-01 /.test(rp), rp.slice(300, 1700));
    ok('kunlik hisobot: kanallar (naqd + Click) va naqd o‘quv to‘lovi mosligi; kutilayotganlar; limit',
      /Tushumlar kanallar bo‘yicha/.test(rp) && /naqd 1 400 000=00/.test(rp) && /Click 1 300 000=00/.test(rp) && /to‘lovlar jadvalida 400 000=00 — kassa kirim orderlarida 400 000=00: mos\./.test(rp)
      && /Tasdiq kutayotgan so‘rovlar \(1 ta\) 70 000=00/.test(rp) && /Kassa limiti: 2 000 000=00 — kun oxiridagi qoldiq limitdan oshmagan/.test(rp), rp.slice(-900));
    ok('kunlik hisobot chop etish jurnaliga yozilmaydi (raqamli hujjat emas)', q(`select count(*) from public.cash_prints where kind = 'book'`) === '0');
    await s.pg.click('#m-x').catch(() => {}); await s.modalGone().catch(() => {});
    const b2 = (await s.printed()).length;
    await s.pg.click(`[data-report="${today}"]`); await s.pg.waitForTimeout(1500);
    ok('kun kartasidagi tugma ham hisobotni chiqaradi', (await s.printed()).slice(b2).some(t => /KASSIRNING KUNLIK HISOBOTI/.test(t)));
  }

  // ---------------- 3) Moliya menejeri: nazorat ro'yxati; moslik buzilishi ko'rinadi
  const mol = await login(ids.R_MOL);
  {
    const s = mol; await s.kassaReady();
    let c = await s.ctl();
    ok('MM: nazorat ro‘yxati — tasdiq kutayotgan so‘rov va «boshqa» tomonlar ma’lumot sifatida; yagona «diqqat» — yetkazib beruvchiga naqd to‘lov (F1.27), muhim yo‘q',
      c.waiting.level === 'info' && /1 ta/.test(c.waiting.text) && c.other.level === 'info' && /2 ta/.test(c.other.text)
      && c.orgCash && c.orgCash.level === 'warn' && /1 ta · 120 000 so‘m/.test(c.orgCash.text)
      && !Object.entries(c).some(([k, x]) => k !== 'orgCash' && (x.level === 'bad' || x.level === 'warn')), c);
    // kirim orderisiz naqd to'lov (kassani chetlab o'tgan yozuv)
    q(`set session_replication_role = replica; insert into public.payments (id, "studentId", provider, amount, status, matched, raw, "createdAt") values ('cash_e4_x', '${sid}', 'cash', 111000, 'applied', true, '{}', app.fin_now())`);
    await s.kassaReady(); c = await s.ctl();
    ok('MM: moslik buzildi — «muhim», orderisiz naqd to‘lov soni va summasi; sarlavhada «E’tibor talab qiladi»',
      c.reconcile.level === 'bad' && /kirim orderisiz naqd o‘quv to‘lovi: 1 ta \(111 000 so‘m\)/.test(c.reconcile.text) && /E’tibor talab qiladi: 2 ta/.test(await s.pg.$eval('#ks-ctl-card', e => e.innerText)), c.reconcile);
    await s.pg.screenshot({ path: `${OUT}/ctl-${UI}-1440.png`, fullPage: true });
    q(`set session_replication_role = replica; delete from public.payments where id = 'cash_e4_x'`);
  }

  // ---------------- 4) Kassir kunni yopadi; MM: tekshirilmagan kun; yopilgan kun hisoboti
  {
    const s = kas; await s.kassaReady();
    await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted'); await s.pg.fill('#kc-counted', '1 580 000');
    await s.pg.click('#kc-save'); await s.modalGone(); await s.pg.waitForTimeout(1500);
    ok('kun yopildi (farq yo‘q), KO-4 chop etildi', q(`select status || ':' || trim_scale(closing) || ':' || trim_scale(diff) from public.cash_days where desk='main' and day='${today}'`) === 'closed:1580000:0'
      && q(`select count(*) from public.cash_prints where kind = 'book'`) === '1', q(`select status, closing, diff from public.cash_days where desk='main'`));
  }
  {
    const s = mol; await s.kassaReady(); const c = await s.ctl();
    ok('MM: nazorat — tekshirilmagan kun 1 ta (diqqat); KO-4 chop etilgan (joyida)', c.unverified.level === 'warn' && c.unverified.text.includes(`1 ta: ${dm}`) && c.unprinted.level === 'ok', [c.unverified, c.unprinted]);
    await s.pg.click(`[data-view="${today}"]`); await s.pg.waitForSelector('#kdv-report', { timeout: 15000 });
    const before = (await s.printed()).length;
    await s.pg.click('#kdv-report'); await s.pg.waitForTimeout(1500);
    const rp = (await s.printed()).slice(before).find(t => /KASSIRNING KUNLIK HISOBOTI/.test(t)) || '';
    ok('yopilgan kun hisoboti: «QORALAMA» yo‘q, sanalgan summa va farq, kassir ismi',
      !/QORALAMA/.test(rp) && /kun yopilgan/.test(rp) && /Sanab chiqilgan naqd pul 1 580 000=00/.test(rp) && /Farq yo‘q/.test(rp) && /Kassir SINOV|Kassir \S/.test(rp), rp.slice(0, 600));
    // RP-02 = KO-4: shu kunning kassa kitobi varag'idagi jamlar bilan bir xil
    const b3 = (await s.printed()).length;
    await s.pg.click('#kdv-book'); await s.pg.waitForTimeout(1200);
    if (await s.pg.$('#kp-copy')) { await s.pg.click('#kp-copy'); await s.pg.waitForTimeout(1200); }
    const k4 = (await s.printed()).slice(b3).find(t => /КАССА ДАФТАРИ ВАРАҒИ/.test(t)) || '';
    ok('RP-02 = KO-4: kirim 700 000, chiqim 120 000, kun oxiri 1 580 000 — ikkala hujjatda bir xil',
      /Кун бўйича жами X 700 000=00 120 000=00/.test(k4) && /Кун охирига қолдиқ X 1 580 000=00/.test(k4) && /Kirim \(3 ta order\) 700 000=00/.test(rp) && /Chiqim \(1 ta order\) 120 000=00/.test(rp) && /Kun oxiriga qoldiq 1 580 000=00/.test(rp), k4.slice(0, 500));
    await s.ctx.close();
  }

  // ---------------- 5) Telefon (390): nazorat ro'yxati va kun oynasi sig'adi
  {
    const s = await login(ids.R_MOL, { width: 390, height: 844 }); await s.kassaReady(); await s.ctl();
    const over = await s.pg.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    ok('telefon: sahifa gorizontal siljimaydi', over <= 1, over);
    await s.pg.$eval('#ks-ctl-card', e => e.scrollIntoView());
    await s.pg.screenshot({ path: `${OUT}/ctl-${UI}-390.png` });
    await s.pg.$eval(`[data-view="${today}"]`, x => x.click()); await s.pg.waitForSelector('#kdv-who', { timeout: 15000 });
    const mw = await s.pg.evaluate(() => { const m = document.querySelector('#modal'); return m.scrollWidth - m.clientWidth; });
    ok('telefon: kun oynasi sig‘adi', mw <= 1, mw);
    await s.pg.screenshot({ path: `${OUT}/day-who-${UI}-390.png` });
    await s.ctx.close();
  }
  await kas.ctx.close();
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(2); });
