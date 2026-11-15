// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): onlayn kassa (NKM) Z-hisoboti (F1.26, buxgalter ko'rigi M6).
//   Kassir kunni Z bilan yopadi (xato raqam) → farq kun qatorida va nazorat ro'yxatida → Moliya menejeri izohsiz tekshira olmaydi →
//   kassir «Z» tugmasi bilan tuzatadi → mos → izohsiz tekshiriladi; kun oynasi va kunlik hisobotda Z; 2-kun: «Z-hisobot yo'q» (telefon).
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa8.cjs [v1|v2]
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
  const sid = 'IQ-0003';
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
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast, #toast, [class*=toast]')].map(e => e.textContent).join(' | '));
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, toasts, printed };
  }
  const bal = () => q(`select trim_scale(app.kassa_day_balance(id)) from public.cash_days where desk='main' and status='open'`);
  const dmy = d => d.slice(8, 10) + '.' + d.slice(5, 7) + '.' + d.slice(0, 4);
  // kassa hujjatlaridagi ism — xodim kartasidan (bog'lanmagan bo'lsa — hisob ismi), server qoidasi bilan
  const kasLbl = q(`select app.kassa_user_label(u.name, u."staffRefType", u."staffRefId", u.id) from public.users u where u.id = '${ids.R_KAS}'`);
  const ctlRow = async (pg, key) => { await pg.waitForSelector('#ks-ctl-card:not([data-stale])', { timeout: 15000 }).catch(() => {});
    return pg.$eval(`#ks-ctl tr[data-ctl="${key}"]`, e => [e.dataset.level, e.innerText.replace(/\s+/g, ' ').trim()]).catch(() => ['', '']); };

  // tayyorgarlik: ishga tushirish, boshlang'ich qoldiq; kassir — fiskal chekli naqd o'quv to'lovi 300 000 va terminal to'lovi 150 000
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  asUser(ids.R_KAS, `select public.record_manual_payment('man_e8_0001', '${sid}', 300000, 'cash', null, '', '', 'Sinov Ota', null, '{"fiscalNo":"800001"}'::jsonb)::text`);
  asUser(ids.R_KAS, `select public.record_manual_payment('man_e8_t001', '${sid}', 150000, 'terminal', null, '', '', 'Sinov Ota', null, '{"fiscalNo":"800002"}'::jsonb)::text`);
  ok('tayyorgarlik: ochiq kun, 1 ta fiskal chekli kirim orderi, 1 ta terminal to‘lovi', q(`select count(*) from public.cash_docs where op='in_tuition' and status='posted' and "fiscalNo" is not null`) === '1'
    && q(`select count(*) from public.payments where provider='terminal' and status='applied'`) === '1' && bal() === '1300000', [bal()]);

  // ---------------- 1) Kassir: kunni Z bilan yopadi (naqd raqami xato yozilgan)
  const kas = await login(ids.R_KAS);
  {
    await kas.kassaReady();
    await kas.pg.click('#ks-close'); await kas.pg.waitForSelector('#kc-counted');
    ok('yopish oynasida Z-hisobot maydonlari bor (raqam, naqd, karta, «Z-hisobot yo‘q»)', !!(await kas.pg.$('#kz-no')) && !!(await kas.pg.$('#kz-cash')) && !!(await kas.pg.$('#kz-card')) && !!(await kas.pg.$('#kz-miss'))
      && !(await kas.pg.isVisible('#kz-why')) && /Onlayn kassa \(NKM\) Z-hisoboti/.test(await kas.pg.$eval('#modal', e => e.textContent)));
    ok('kutilgan Z summalari oynada ko‘rsatilmaydi (kassir Z dagi raqamni yozadi)', !/300 000/.test(await kas.pg.$eval('#modal', e => e.textContent.replace(/Hisobdagi qoldiq[^]*?so‘m/, ''))));
    await kas.pg.fill('#kc-counted', '1 300 000');
    await kas.pg.fill('#kz-no', 'Z-0001'); await kas.pg.fill('#kz-cash', '290000'); await kas.pg.fill('#kz-card', '150 000');
    await kas.pg.click('#kc-save'); await kas.modalGone(); await kas.pg.waitForTimeout(1500);
    const t = await kas.toasts();
    ok('yopishni tasdiqlash oynasida Z-hisobot qatori', kas.dialogs.some(m => /Kun yopilsinmi\?/.test(m) && /Z-hisobot № Z-0001: naqd 290 000 so‘m, karta 150 000 so‘m/.test(m)), kas.dialogs);
    ok('yopilgach: Z farqi haqida xabar (naqd −10 000)', /Z-hisobot farq: naqd −10 000 so‘m — buxgalter kunni izoh bilan tekshiradi/.test(t), t);
    const ev = q(`select count(*) || ':' || max(data ->> 'cash') || ':' || max(data ->> 'no') from public.cash_day_events where kind='zreport'`);
    ok('kun yopildi; Z kun jurnaliga yozildi', q(`select status from public.cash_days where desk='main' and day='${today}'`) === 'closed' && ev === '1:290000:Z-0001', ev);
    await kas.kassaReady();
    const zs = await kas.pg.$eval(`[data-zst="${today}"]`, e => e.textContent).catch(() => '');
    ok('kun qatorida Z holati (qizil) va «Z» tugmasi', /Z: farq: naqd −10 000 so‘m/.test(zs) && !!(await kas.pg.$(`[data-zrep="${today}"]`)), zs);
  }

  // ---------------- 2) Moliya menejeri: nazorat ro'yxati, izohsiz tekshirib bo'lmaydi
  const mol = await login(ids.R_MOL);
  {
    await mol.kassaReady();
    await mol.pg.waitForSelector('#ks-ctl-card', { timeout: 15000 }).catch(() => {});
    const ctl = await mol.pg.$eval('#ks-ctl', e => e.innerText).catch(() => '');
    ok('nazorat ro‘yxati: «Onlayn kassa Z-hisoboti» qatorida kun va farq', /Onlayn kassa Z-hisoboti/.test(ctl) && /naqd −10 000 so‘m/.test(ctl), ctl.slice(0, 600));
    ok('Moliya menejerida «Z» tugmasi ham bor (kassir o‘rniga kiritishi mumkin)', !!(await mol.pg.$(`[data-zrep="${today}"]`)));
    await mol.pg.click(`[data-verify="${today}"]`); await mol.pg.waitForSelector('#kv-papers');
    const w = await mol.pg.$eval('#kv-z', e => e.textContent).catch(() => '');
    ok('tekshirish oynasida Z ogohlantirishi: farq va tizimdagi summalar', /farq: naqd −10 000 so‘m/.test(w) && /Tizimda: naqd 300 000 so‘m \(1 chek\), karta 150 000 so‘m \(1 ta\)/.test(w), w);
    await mol.pg.check('#kv-papers'); await mol.pg.click('#kv-save'); await mol.pg.waitForTimeout(800);
    ok('izohsiz — tekshirilmaydi (sahifa to‘xtatadi)', /Z-hisobot bo‘yicha sababni izohda yozing/.test(await mol.toasts()) && !!(await mol.pg.$('#kv-papers'))
      && q(`select status from public.cash_days where desk='main' and day='${today}'`) === 'closed');
    await mol.pg.click('#m-cancel'); await mol.modalGone();
  }

  // ---------------- 3) Kassir «Z» tugmasi bilan tuzatadi → mos
  {
    await kas.kassaReady();
    await kas.pg.click(`[data-zrep="${today}"]`); await kas.pg.waitForSelector('#kz-save');
    const pre = await kas.pg.evaluate(() => [document.querySelector('#kz-no').value, document.querySelector('#kz-cash').value, document.querySelector('#kz-card').value].join('|'));
    ok('Z oynasi oldingi yozuv bilan to‘ldirilgan', pre === 'Z-0001|290 000|150 000', pre);
    await kas.pg.fill('#kz-cash', '300 000'); await kas.pg.click('#kz-save'); await kas.modalGone(); await kas.pg.waitForTimeout(1000);
    ok('tuzatildi: «Z-hisobot tizim bilan mos ✓»', /Z-hisobot tizim bilan mos ✓/.test(await kas.toasts()), await kas.toasts());
    await kas.kassaReady();
    const zs = await kas.pg.$eval(`[data-zst="${today}"]`, e => e.textContent).catch(() => '');
    ok('kun qatorida «Z: mos»; tarixda 2 ta Z yozuvi', /Z: mos/.test(zs) && q(`select count(*) from public.cash_day_events where kind='zreport'`) === '2', zs);
  }

  // ---------------- 4) Moliya menejeri: izohsiz tekshiradi; kun oynasi va kunlik hisobotda Z
  {
    await mol.kassaReady();
    // crit-4: kun yopilgandan keyin kiritilgan / tuzatilgan Z — nazorat ro'yxatida alohida (kim, necha marta); kunni o'sha xodim tekshirmaydi
    const zc = await ctlRow(mol.pg, 'zChanged');
    ok('nazorat ro‘yxati: «Z-hisobot kun yopilgandan keyin o‘zgartirilgan» — diqqat: kun, 1 marta, oxirgisi — kassir', zc[0] === 'warn' && zc[1].endsWith(`diqqat ${dmy(today)}: 1 marta, oxirgisi — ${kasLbl}`)
      && q(`select count(*) filter (where data ->> 'afterClose' = 'true') || ':' || count(*) from public.cash_day_events where kind = 'zreport'`) === '1:2', zc);
    await mol.pg.click(`[data-verify="${today}"]`); await mol.pg.waitForSelector('#kv-papers');
    ok('Z mos — tekshirish oynasida ogohlantirish yo‘q', !(await mol.pg.$('#kv-z')));
    await mol.pg.check('#kv-papers'); await mol.pg.click('#kv-save'); await mol.modalGone();
    ok('kun tekshirildi (izohsiz)', q(`select status from public.cash_days where desk='main' and day='${today}'`) === 'verified');
    await mol.pg.click(`[data-view="${today}"]`); await mol.pg.waitForSelector('#kdv-report', { timeout: 15000 });
    const zl = await mol.pg.$eval('#kdv-z', e => e.textContent).catch(() => '');
    ok('kun oynasida Z: raqami, summalari, «mos», tizimdagi summalar', /№ Z-0001 · naqd 300 000 so‘m · karta 150 000 so‘m/.test(zl) && /mos/.test(zl) && /tizimda: naqd 300 000 so‘m \(1 chek\), karta 150 000 so‘m \(1 ta\)/.test(zl), zl);
    ok('kun jurnalida «Z-hisobot» yozuvlari', /Z-hisobot/.test(await mol.pg.$eval('#modal', e => e.textContent)));
    await mol.pg.click('#kdv-report'); await mol.pg.waitForTimeout(1500);
    const pr = (await mol.printed()).join(' || ');
    ok('kunlik hisobotda Z bo‘limi: raqam, naqd va karta solishtirish', /Onlayn kassa \(NKM\) Z-hisoboti/.test(pr) && /Z-hisobot № Z-0001/.test(pr) && /Naqd 300 000=00 300 000=00 \(1 chek\) mos/.test(pr) && /Bank kartasi 150 000=00 150 000=00 \(1 ta\) mos/.test(pr), pr.slice(0, 400));
    await mol.pg.click('#m-cancel').catch(() => {}); await mol.modalGone().catch(() => {});   // kun oynasini yopish
  }
  ok('server: Z tekshirilgan kunda o‘zgarmaydi', /kassa:verified|o‘zgarmaydi|o''zgarmaydi|o'zgarmaydi/.test(cp.spawnSync(E.PSQL[0], [...E.PSQL.slice(1), '-q', '-At', '-d', E.DB, '-c',
    `begin; select set_config('request.jwt.claims', '{"sub":"${ids.R_KAS}","role":"authenticated"}', true); set local role authenticated; select public.kassa_day_z('{"day":"${today}","z":{"no":"Z-9","cash":0,"card":0}}'::jsonb); commit;`], { encoding: 'utf8' }).stderr));
  await kas.ctx.close();

  // ---------------- 5) 2-kun (telefon): «Z-hisobot yo'q» — sabab bilan; tekshirishda izoh
  q(`insert into app.fin_clock (id, t) values (1, now() + interval '1 day') on conflict (id) do update set t = excluded.t`);
  const day2 = q('select app.fin_today()');
  asUser(ids.R_KAS, `select public.record_manual_payment('man_e8_0002', '${sid}', 200000, 'cash', null, '', '', 'Sinov Ona', null, '{"fiscalNo":"800003"}'::jsonb)::text`);
  {
    const p = await login(ids.R_KAS, { width: 390, height: 844 });
    await p.kassaReady();
    await p.pg.click('#ks-close'); await p.pg.waitForSelector('#kc-counted');
    const sw = await p.pg.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    ok('telefon: yopish oynasi (Z maydonlari bilan) gorizontal siljimaydi', sw <= 1, sw);
    await p.pg.fill('#kc-counted', bal());
    await p.pg.check('#kz-miss');
    ok('«Z-hisobot yo‘q» belgilansa sabab maydoni ochiladi', await p.pg.isVisible('#kz-why'));
    await p.pg.fill('#kz-why', 'abc'); await p.pg.click('#kc-save'); await p.pg.waitForTimeout(600);
    ok('qisqa sabab bilan yopilmaydi', /sababini yozing/.test(await p.toasts()) && q(`select status from public.cash_days where desk='main' and day='${day2}'`) === 'open', await p.toasts());
    await p.pg.fill('#kz-why', 'Kassa apparati ishlamadi (sinov)'); await p.pg.click('#kc-save'); await p.modalGone(); await p.pg.waitForTimeout(1200);
    await p.kassaReady();
    const zs = await p.pg.$eval(`[data-zst="${day2}"]`, e => e.textContent).catch(() => '');
    ok('kun yopildi, qatorda «Z: yo‘q (sabab)»', q(`select status from public.cash_days where desk='main' and day='${day2}'`) === 'closed' && /Z: yo‘q \(Kassa apparati ishlamadi \(sinov\)\)/.test(zs), zs);
    await p.pg.screenshot({ path: `${OUT}/z-${UI}-390.png`, fullPage: true });
    await p.ctx.close();
  }
  const tz = q(`select (app.kassa_daily('${day2}') -> 'control' -> 'z')::text`);
  ok('Telegram kassa bloki: Z «yo‘q»', /"ok": false/.test(tz) && /"missing": true/.test(tz), tz);
  {
    await mol.kassaReady();
    await mol.pg.click(`[data-verify="${day2}"]`); await mol.pg.waitForSelector('#kv-papers');
    ok('2-kun tekshirish oynasida «Z: yo‘q» ogohlantirishi', /yo‘q \(Kassa apparati ishlamadi \(sinov\)\)/.test(await mol.pg.$eval('#kv-z', e => e.textContent).catch(() => '')));
    await mol.pg.check('#kv-papers'); await mol.pg.fill('#kv-note', 'Apparat ta’mirda, servis dalolatnomasi bor (sinov)'); await mol.pg.click('#kv-save'); await mol.modalGone();
    ok('izoh bilan tekshirildi; izoh saqlandi', q(`select status || ':' || ("verifyNote" like 'Apparat ta%') from public.cash_days where desk='main' and day='${day2}'`) === 'verified:true');
    await mol.pg.screenshot({ path: `${OUT}/z-mol-${UI}-1440.png` });
    await mol.ctx.close();
  }

  // ---------------- 6) g7v-1: oflayn (qurilma navbatidagi) to'lov — NKM cheki 3-kun smenasida urilgan, kech kirim orderi 4-kuni keladi:
  //   u 3-kunning Z iga tegishli (o'sha kun «mos», izoh endi talab qilinmaydi), 4-kunning Z iga qo'shilmaydi (ikki kunda teskari farq yo'q)
  q(`update app.fin_clock set t = now() + interval '2 days' where id = 1`);
  const day3 = q('select app.fin_today()');
  asUser(ids.R_KAS, `select public.record_manual_payment('man_e8_0003', '${sid}', 100000, 'cash', null, '', '', 'Sinov Ota', null, '{"fiscalNo":"800005"}'::jsonb)::text`);
  const cap3 = q(`select app.fin_now()::text`);   // oflayn to'lov olingan payt (chek urilgan, yozuv qurilma navbatida qoldi)
  const c3 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_day_close('{"desk":"main","day":"${day3}","counted":${Number(bal()) + 50000},"pendingRefs":[{"ref":"man_e8_late","amount":50000}],"z":{"no":"Z-0003","cash":150000,"card":0}}'::jsonb)::text`));
  const zs3 = () => q(`select concat_ws(':', z ->> 'expCash', z ->> 'nCash', z ->> 'diffCash', z ->> 'ok') from (select app.kassa_z_state(id) z from public.cash_days where desk='main' and day='${day3}') x`);
  ok('3-kun: navbatdagi 50 000 e’lon qilinib yopildi (farq yo‘q); Z naqd 150 000 — tizimda hozircha 100 000 (1 chek), farq +50 000',
    c3.ok && c3.day && c3.day.status === 'closed' && Number(c3.day.diff) === 0 && zs3() === '100000:1:50000:false', [c3.day && [c3.day.status, c3.day.diff], zs3()]);
  {
    const m = await login(ids.R_MOL); await m.kassaReady();
    const zsB = await m.pg.$eval(`[data-zst="${day3}"]`, e => e.textContent).catch(() => '');
    const zcV = await ctlRow(m.pg, 'zChanged');
    ok('kech order kelguncha: 3-kun qatorida «Z: farq: naqd +50 000 so‘m»; tekshirilgan 1-kun «Z o‘zgartirilgan» qatorida «(tekshirilgan)» belgisi bilan',
      /Z: farq: naqd \+50 000 so‘m/.test(zsB) && zcV[1].includes(`${dmy(today)}: 1 marta, oxirgisi — ${kasLbl} (tekshirilgan)`), [zsB, zcV]);
    await m.pg.click(`[data-verify="${day3}"]`); await m.pg.waitForSelector('#kv-papers');
    const pend = await m.pg.$eval('#kv-pend', e => e.textContent).catch(() => ''), kz = await m.pg.$eval('#kv-z', e => e.textContent).catch(() => '');
    await m.pg.check('#kv-papers'); await m.pg.click('#kv-save'); await m.pg.waitForTimeout(700);
    ok('kech order kelguncha tekshirish oynasi: «hali o‘tkazilmagan yozuv» (50 000) va Z farqi ogohlantirishi; izohsiz tekshirilmaydi',
      /50 000/.test(pend) && /farq: naqd \+50 000 so‘m/.test(kz) && /Tizimda: naqd 100 000 so‘m \(1 chek\)/.test(kz)
      && /Hali o‘tkazilmagan yozuvlar bo‘yicha sababni izohda yozing/.test(await m.toasts()) && q(`select status from public.cash_days where desk='main' and day='${day3}'`) === 'closed', [pend, kz, await m.toasts()]);
    await m.pg.click('#m-cancel'); await m.modalGone();
    await m.ctx.close();
  }
  q(`update app.fin_clock set t = now() + interval '3 days' where id = 1`);
  const day4 = q('select app.fin_today()');
  asUser(ids.R_KAS, `select public.record_manual_payment('man_e8_late', '${sid}', 50000, 'cash', null, '', '', 'Sinov Ota', '${cap3}', '{"fiscalNo":"800006"}'::jsonb)::text`);
  const lateDoc = q(`select c.late || ':' || c."businessDay" || ':' || (c."capturedAt" = '${cap3}'::timestamptz) from public.cash_docs c join public.payments p on p."cashDocId" = c.id where p.id = 'man_e8_late'`);
  ok('4-kun: navbatdagi to‘lov keldi — kech kirim orderi 4-kunga tushdi (olingan payti saqlangan); Z bo‘yicha 3-kunga tegishli: 3-kun tizimda 150 000 (2 chek), mos; 4-kun Z iga qo‘shilmadi',
    lateDoc === `true:${day4}:true` && zs3() === '150000:2:0:true'
    && q(`select (app.kassa_z_state(id) ->> 'expCash') || ':' || (app.kassa_z_state(id) ->> 'nCash') from public.cash_days where desk='main' and day='${day4}'`) === '0:0', [lateDoc, zs3()]);
  {
    const m = await login(ids.R_MOL); await m.kassaReady();
    const zsA = await m.pg.$eval(`[data-zst="${day3}"]`, e => e.textContent).catch(() => '');
    await m.pg.click(`[data-verify="${day3}"]`); await m.pg.waitForSelector('#kv-papers');
    const noWarn = !(await m.pg.$('#kv-pend')) && !(await m.pg.$('#kv-z'));
    await m.pg.check('#kv-papers'); await m.pg.click('#kv-save'); await m.modalGone().catch(() => {});
    ok('kech order kelgach: 3-kun qatorida «Z: mos»; tekshirish oynasida ogohlantirish yo‘q — izohsiz tekshirildi',
      /Z: mos/.test(zsA) && noWarn && q(`select status || ':' || coalesce("verifyNote", '') from public.cash_days where desk='main' and day='${day3}'`) === 'verified:', [zsA, noWarn, await m.toasts()]);
    if (await m.pg.$('#modal-bg.show')) { await m.pg.click('#m-cancel').catch(() => {}); await m.modalGone().catch(() => {}); }   // tekshirilmagan bo'lsa — oyna ochiq qolgan
    await m.kassaReady(); await m.pg.click(`[data-view="${day3}"]`); await m.pg.waitForSelector('#kdv-report', { timeout: 15000 });
    const zl = await m.pg.$eval('#kdv-z', e => e.textContent).catch(() => '');
    ok('3-kun oynasida Z: № Z-0003, naqd 150 000, «mos», tizimda 150 000 (2 chek)', /№ Z-0003 · naqd 150 000 so‘m · karta 0 so‘m/.test(zl) && /mos/.test(zl) && /tizimda: naqd 150 000 so‘m \(2 chek\)/.test(zl), zl);
    await m.pg.screenshot({ path: `${OUT}/z-late-${UI}-1440.png` });
    await m.ctx.close();
  }
  q(`delete from app.fin_clock`);
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); try { q(`delete from app.fin_clock`); } catch (_) {} process.exit(1); });
