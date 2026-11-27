// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.12 — patta QR va tekshirish sahifasi, kassa
//   kitobi yil muqovasi va guvohnomasi brauzerda. Tayyorgarlik (server funksiyalari bilan): kassa ishga tushiriladi, bankdan naqd kirim
//   (KO-1 № 1, tekshiruv kaliti bilan).
//   1) Kassir: kirim orderi bosmasi — pattada QR (rasm) va «Тўловни текшириш…» yozuvi; orderning o'zida rasm yo'q.
//   2) Mehmon (tizimga kirmagan), telefon ekrani: verify.html?k=<kalit> — «Haqiqiy to'lov hujjati», tashkilot, raqam, sana, summa, holat;
//      to'lovchi va asos yo'q; gorizontal siljish yo'q; ruscha; noto'g'ri kod — format xabari, noma'lum kod — «topilmadi».
//   3) Kassir orderni bekor qiladi (server) — tekshirish sahifasi «bekor qilingan» (sana bilan).
//   4) Direktor: «Kitob» — yil muqovasi oynasi: kunlar, varaqlar, orderlar, «to'liq emas» sabablari; chop etish — muqova va guvohnoma
//      («ҚОРАЛАМА» belgisi bilan); kun yopilgach — varaqlar soni.
//   5) Sahifa xatolari yo'q.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa23.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const dm = d => `${d.slice(8, 10)}.${d.slice(5, 7)}.${d.slice(0, 4)}`;
(async () => {
  const b = await E.launch();
  const d0 = q('select app.fin_today()'), y0 = d0.slice(0, 4);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${d0}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${d0}"}'::jsonb)`);
  q(`set session_replication_role = replica;
     insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_b23', 'bank', 'Sinov Bank', '', true) on conflict (id) do nothing;
     set session_replication_role = origin;`);
  const r1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_receipt('{"op":"in_bank","amount":500000,"partyType":"bank","partyId":"cp_b23","basis":"Chek kitobchasi № 0-23","clientRef":"e23-r1-0001"}'::jsonb)::text`));
  const tok = q(`select coalesce((select token from public.cash_doc_verify where "docId" = '${r1.id}'), '')`);
  ok('tayyorgarlik: kassa ishga tushdi, bankdan naqd kirim — KO-1 № 1, tekshiruv kaliti bor (javobda ham)', r1.status === 'posted' && r1.no === 1 && /^[0-9a-f]{32}$/.test(tok) && r1.vtok === tok, [r1.status, r1.no, tok, r1.vtok]);

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
    await pg.waitForTimeout(700);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const waitPrint = async (n, re) => pg.waitForFunction(([k, r]) => [...document.querySelectorAll('iframe')].slice(k).some(f => { try { return new RegExp(r).test(f.contentDocument.body.innerText); } catch (e) { return false; } }), [n, re], { timeout: 20000 }).then(() => true).catch(() => false);
    return { ctx, pg, dialogs, tab, kassaReady, printed, waitPrint };
  }

  // ---------------- 1) kassir: kirim orderi bosmasi — pattada QR
  const kas = await login(ids.R_KAS);
  await kas.kassaReady();
  await kas.pg.waitForSelector(`[data-print="${r1.id}"]`, { timeout: 15000 });
  let pb = (await kas.printed()).length;
  await kas.pg.click(`[data-print="${r1.id}"]`);
  const pr1 = await kas.waitPrint(pb, 'ПАТТА');
  await kas.pg.waitForFunction(n => [...document.querySelectorAll('iframe')].slice(n).some(f => { try { const i = f.contentDocument.querySelector('.patta .pqr img'); return !!i && i.complete && i.naturalWidth > 0; } catch (e) { return false; } }), pb, { timeout: 10000 }).catch(() => {});
  const qi = await kas.pg.evaluate(n => { for (const f of [...document.querySelectorAll('iframe')].slice(n)) { try { const d = f.contentDocument, img = d.querySelector('.patta .pqr img');
      if (img) return { src: String(img.getAttribute('src') || '').slice(0, 22), imgs: d.querySelectorAll('img').length, hint: d.querySelector('.patta .pqr').innerText.replace(/\s+/g, ' ').trim(), w: img.naturalWidth }; } catch (e) {} } return null; }, pb);
  ok('kirim orderi bosmasi: pattada QR rasm (data:image/gif, yuklangan) va «Тўловни текшириш: QR кодни телефонда сканерланг»; orderning o‘zida rasm yo‘q',
    pr1 && qi && qi.src === 'data:image/gif;base64,' && qi.imgs === 1 && qi.w > 0 && qi.hint === 'Тўловни текшириш: QR кодни телефонда сканерланг', qi);

  // ---------------- 2) mehmon (telefon): tekshirish sahifasi
  const gc = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 390, height: 844 } });
  const gp = await gc.newPage();
  gp.on('pageerror', e => allErrs.push('verify: ' + String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
  const vOpen = async k => { await gp.goto(E.BASE + '/verify.html?k=' + k); await gp.waitForFunction(() => !document.querySelector('#out .badge.wait'), null, { timeout: 20000 }).catch(() => {}); return gp.$eval('#out', e => e.innerText.replace(/\s+/g, ' ').trim()); };
  const v1 = await vOpen(tok);
  ok('mehmon (telefon, 390 px): «Haqiqiy to‘lov hujjati», tashkilot, № 1, sana, summa, holat; to‘lovchi va asos yo‘q; gorizontal siljish yo‘q',
    v1.includes('Haqiqiy to‘lov hujjati — kassa kirim orderi') && v1.includes('«SINOV MAKTAB» МЧЖ') && v1.includes(`№ 1 · ${y0}`) && v1.includes(dm(d0))
      && v1.includes('500 000 so‘m') && v1.includes('Kassaga kirim qilingan') && !/Sinov Bank|Chek kitobchasi|cp_b23/.test(v1)
      && (await gp.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)), v1);
  await gp.screenshot({ path: `${OUT}/verify-patta-390.png`, fullPage: true });
  await gp.click('#l-ru'); await gp.waitForTimeout(200);
  const v1r = await gp.$eval('#out', e => e.innerText.replace(/\s+/g, ' ').trim());
  await gp.click('#l-uz'); await gp.waitForTimeout(200);
  ok('ruscha: «Подлинный платёжный документ — приходный кассовый ордер», «500 000 сум», «Принято в кассу»',
    v1r.includes('Подлинный платёжный документ — приходный кассовый ордер') && v1r.includes('500 000 сум') && v1r.includes('Принято в кассу'), v1r);
  const vBad = await vOpen('abc123'), vNo = await vOpen('0'.repeat(32)), vUp = await vOpen(tok.toUpperCase());
  ok('noto‘g‘ri kod — format xabari; mavjud bo‘lmagan kod — «topilmadi»; katta harfdagi kod — o‘sha order',
    vBad.includes('Kod noto‘g‘ri') && vNo.includes('Bunday to‘lov hujjati topilmadi') && vUp.includes('Haqiqiy to‘lov hujjati'), [vBad, vNo, vUp.slice(0, 80)]);

  // ---------------- 3) bekor qilingan order
  asUser(ids.R_KAS, `select public.kassa_doc_void('${r1.id}', 'Sinov: adashib yozildi')`);
  const vd = q(`select to_char(now() at time zone 'Asia/Tashkent', 'DD.MM.YYYY')`);
  const v2 = await vOpen(tok);
  ok('order bekor qilindi — tekshirish sahifasi: «Bu kirim orderi bekor qilingan», «Bekor qilingan (sana)», tushuntirish',
    q(`select status from public.cash_docs where id = '${r1.id}'`) === 'void' && v2.includes('Bu kirim orderi bekor qilingan') && v2.includes(`Bekor qilingan (${vd})`)
      && v2.includes('Order bekor qilingan — pul qaytarilgan'), v2);
  await gc.close();

  // ---------------- 4) Direktor: «Kitob» — yil muqovasi va guvohnoma
  const dir = await login(ids.R_DIR);
  await dir.kassaReady();
  await dir.pg.waitForSelector('#ks-book', { timeout: 15000 });
  const openBook = async () => { await dir.pg.click('#ks-book'); await dir.pg.waitForSelector('#kb-tbl', { timeout: 20000 });
    return { year: await dir.pg.$eval('#kb-year', e => e.value), tbl: await dir.pg.$eval('#kb-tbl', e => e.innerText.replace(/\s+/g, ' ').trim()),
      state: await dir.pg.$eval('#kb-state', e => e.textContent.replace(/\s+/g, ' ').trim()), sheets: await dir.pg.$eval('#kb-sheets', e => e.textContent.trim()) }; };
  const k1 = await openBook();
  ok(`«Kitob» (${y0}): kassa, kunlar (1, yopilgan 0), varaqlar yo‘q, kirim orderi № 1; to‘liq emas — yil tugamagan, kun yopilmagan, yopilgan kun yo‘q`,
    k1.year === y0 && k1.tbl.includes('Asosiy kassa') && k1.tbl.includes(`1 (yopilgan 0) · ${dm(d0)} — ${dm(d0)}`) && k1.sheets === 'yo‘q' && k1.tbl.includes('№ 1 — № 1 (1 ta)')
      && k1.state === `Kitob hali to‘liq emas: yil hali tugamagan; yopilmagan kunlar: ${dm(d0)}; yopilgan kassa kuni yo‘q. Chop etilsa — «ҚОРАЛАМА» belgisi bilan (tikilmaydi).`, k1);
  pb = (await dir.printed()).length;
  await dir.pg.click('#kb-print');
  const pr2 = await dir.waitPrint(pb, 'ГУВОҲНОМА');
  const cv = (await dir.printed()).slice(pb).join(' || ');
  ok('chop etish: muqova («КАССА КИТОБИ», yil, kassa) va guvohnoma («ГУВОҲНОМА», varaqlar soni so‘z bilan), «ҚОРАЛАМА» va sabablar',
    pr2 && cv.includes('КАССА КИТОБИ') && cv.includes(`${y0} йил`) && cv.includes('Asosiy kassa') && cv.includes('Ушбу касса китобида 0 (ноль) варақ рақамланган')
      && cv.includes('ҚОРАЛАМА') && cv.includes('КИТОБ ТЎЛИҚ ЭМАС: йил ҳали тугамаган'), cv.slice(0, 700));
  await dir.pg.click('#m-cancel').catch(() => {});
  await dir.pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).catch(() => {});
  const cl = JSON.parse(asUser(ids.R_KAS, `select public.kassa_day_close('{"day":"${d0}","counted":1000000,"expected":1000000}'::jsonb)::text`));
  const k2 = await openBook();
  ok('kun yopildi (KO-4 varag‘i № 1) — «Kitob»: varaqlar «№ 1 — № 1 (1 ta)», yopilgan 1; hali to‘liq emas (yil tugamagan)',
    !!cl && q(`select status || ':' || "sheetFrom" || '-' || "sheetTo" from public.cash_days where desk = 'main' and day = '${d0}'`) === 'closed:1-1'
      && k2.sheets === '№ 1 — № 1 (1 ta)' && k2.tbl.includes('1 (yopilgan 1)') && k2.state === 'Kitob hali to‘liq emas: yil hali tugamagan. Chop etilsa — «ҚОРАЛАМА» belgisi bilan (tikilmaydi).', k2);
  await dir.pg.screenshot({ path: `${OUT}/kassa-book-${UI}-1440.png`, fullPage: true });

  await kas.ctx.close(); await dir.ctx.close();
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(1); });
