// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.8 — komissiya inventarizatsiyasi (INV-16) va
//   oy oxiri ro'yxati brauzerda. Tayyorgarlik (server funksiyalari bilan): kassa ishga tushiriladi, bankdan naqd kirim (kun ochiladi),
//   ikkinchi kassir (qabulxona xodimiga qo'shimcha «Kassir» lavozimi).
//   1) Kassir: «Smena topshirish» → «Moddiy javobgar shaxs almashadi» belgisi — komissiya bloki va lavozimlar taklifi; komissiyasiz — rad;
//      komissiya va «Қ» blankalari bilan yoziladi (bazada belgi va blankalar).
//   2) Ikkinchi kassir: «Qabul qildim» — tasdiqda INV-16 aytiladi; INV-16 dalolatnomasi bosmasi (sarlavha, sabab, tilxat, blankalar,
//      rahbar qarori qatori).
//   3) Ikkinchi kassir (endi kassa egasi): «Kunni yopish» — belgi oldindan qo'yilmagan, komissiya bloki yashirin; belgilanadi → komissiya
//      (lavozimlar taklif qilingan), blankalar; tasdiq oynasida INV-16; INV-16 va KO-4 bosmasi; kunlar ro'yxatida «INV-16» belgisi; kun
//      oynasida dalolatnoma nomi.
//   4) Direktor: «Davr» → «Oy oxiri ro'yxati»: joriy oy — oldindan ko'rish (INV joyida, «Oy hali tugamagan», yopish tugmasi yo'q); o'tgan oy —
//      «Oy oxiri surati va davrni … gacha yopish» → tasdiq → surat va qulf (bazada); moliya menejeri — ro'yxat bor, yopish tugmasi yo'q.
//   4b) Direktor, «To'lovlar» (F2.8, 2-qism — reliz 19): joriy oy ochiq; yopilgan o'tgan oy — 🔒 izoh, faktura yaratish / qayta hisoblash /
//      tozalash tugmalari o'chiq.
//   5) Telefon ekrani (390 px) — «Davr» oynasi; sahifa xatolari yo'q.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa22.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const fmt = v => String(v).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
const dm = d => `${d.slice(8, 10)}.${d.slice(5, 7)}.${d.slice(0, 4)}`;
(async () => {
  const b = await E.launch();
  const d0 = q('select app.fin_today()');
  const ym0 = d0.slice(0, 7), dec = d0.slice(5, 7) === '12';
  const pme = q(`select to_char(date_trunc('month', date '${d0}') - interval '1 day', 'YYYY-MM-DD')`), ymP = pme.slice(0, 7);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${d0}"}'::jsonb)`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${d0}"}'::jsonb)`);
  q(`set session_replication_role = replica;
     insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_b22', 'bank', 'Sinov Bank', '', true) on conflict (id) do nothing;
     set session_replication_role = origin;`);
  q(`update public.users set "extraRoles" = '["kassir"]'::jsonb where id = '${ids.R_REC}'`);   // ikkinchi kassir (qo'shimcha lavozim)
  const r1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_receipt('{"op":"in_bank","amount":500000,"partyType":"bank","partyId":"cp_b22","basis":"Chek kitobchasi № 0-22","clientRef":"e22-r1-0001"}'::jsonb)::text`));
  const bal = () => q(`select trim_scale(app.kassa_day_balance(id)) from public.cash_days where desk = 'main' and status = 'open'`);
  ok('tayyorgarlik: kassa ishga tushdi, bankdan naqd kirim — kun ochildi (qoldiq 1 500 000)', r1.status === 'posted' && bal() === '1500000', [r1.status, bal()]);

  async function login(uid, vp, role) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui, u, r]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); if (r) localStorage.setItem('iqror_active_role:' + u, r); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI, uid, role || '']);
    const pg = await ctx.newPage(); const dialogs = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const modalTxt = async () => pg.$eval('#modal', e => e.innerText.replace(/\s+/g, ' ')).catch(() => '');
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const waitPrint = async (n, re) => pg.waitForFunction(([k, r]) => [...document.querySelectorAll('iframe')].slice(k).some(f => { try { return new RegExp(r).test(f.contentDocument.body.innerText); } catch (e) { return false; } }), [n, re], { timeout: 20000 }).then(() => true).catch(() => false);
    const clr = async () => pg.evaluate(() => document.querySelectorAll('.toast').forEach(t => t.remove()));
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
    const visible = async sel => pg.$eval(sel, e => getComputedStyle(e).display !== 'none').catch(() => false);
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, modalTxt, printed, waitPrint, clr, toasts, visible };
  }

  // ---------------- 1) kassir: moddiy javobgar almashganda smena topshirish (INV-16)
  const kas = await login(ids.R_KAS);
  await kas.kassaReady();
  await kas.pg.click('#ks-hand'); await kas.pg.waitForSelector('#kh-to', { timeout: 15000 });
  const hideComm0 = !(await kas.visible('#kc-comm')), invBox0 = !(await kas.visible('#kh-inv-box'));
  await kas.pg.check('#kh-inv');
  const titles = await kas.pg.$$eval('#modal [data-ct]', xs => xs.map(x => x.value));
  ok('smena topshirish: «Moddiy javobgar shaxs almashadi» belgisi — belgilanmaganda komissiya va blankalar yashirin; belgilanganda ko‘rinadi, lavozimlar taklif qilingan',
    hideComm0 && invBox0 && (await kas.visible('#kc-comm')) && (await kas.visible('#kh-inv-box')) && titles.join('|') === 'Rais — direktor|A’zo — bosh buxgalter|A’zo — moliya menejeri'
      && /Moddiy javobgar shaxs almashadi/.test(await kas.modalTxt()) && (await kas.pg.$eval('#kcm-h', e => e.textContent)).includes('Inventarizatsiya komissiyasi'), [hideComm0, invBox0, titles]);
  await kas.pg.selectOption('#kh-to', ids.R_REC); await kas.pg.fill('#kc-counted', fmt(1500000));
  await kas.clr(); await kas.pg.click('#kh-save'); await kas.pg.waitForTimeout(500);
  const t1 = await kas.toasts();
  await kas.pg.fill('#modal [data-cn="0"]', 'Sinov Direktor'); await kas.pg.fill('#modal [data-cn="1"]', 'Sinov Buxgalter');
  await kas.pg.fill('#kh-bcnt', '3'); await kas.clr(); await kas.pg.click('#kh-save'); await kas.pg.waitForTimeout(500);
  const t2 = await kas.toasts();
  await kas.pg.fill('#kh-bnos', '0048–0050'); await kas.clr(); await kas.pg.click('#kh-save'); await kas.modalGone(); await kas.pg.waitForTimeout(800);
  const ho = q(`select status || '|' || "molChange" || '|' || (blanks ->> 'count') || '|' || (blanks ->> 'nos') || '|' || jsonb_array_length(commission) from public.cash_handovers order by "createdAt" desc limit 1`);
  ok('komissiyasiz — rad; blanka raqamisiz — rad; to‘liq — yozildi (bazada: belgi, «Қ» blankalari 3 ta, komissiya 2 kishi)',
    /Inventarizatsiya komissiyasini kiriting: kamida 2 kishi/.test(t1) && /«Қ» blankalari raqamlarini yozing/.test(t2) && ho === 'pending|true|3|0048–0050|2', [t1, t2, ho]);

  // ---------------- 2) ikkinchi kassir: qabul — INV-16 dalolatnomasi
  const rec = await login(ids.R_REC, null, 'kassir');
  await rec.kassaReady();
  await rec.pg.waitForSelector('[data-hoacc]', { timeout: 15000 });
  let pb = (await rec.printed()).length;
  await rec.pg.click('[data-hoacc]');
  const pr1 = await rec.waitPrint(pb, 'ИНВЕНТАРИЗАЦИЯ ҚИЛИШ ДАЛОЛАТНОМАСИ');
  const act1 = (await rec.printed()).slice(pb).join(' || ');
  ok('qabul: tasdiqda INV-16 aytiladi; INV-16 dalolatnomasi — sarlavha, shakl kodi, «моддий жавобгар шахс алмашганда», tilxat, blankalar, rahbar qarori qatori, topshirdi / qabul qildi',
    rec.dialogs.some(m => /Smenani qabul qilasizmi\? \(moddiy javobgar almashganda — komissiya inventarizatsiyasi, INV-16\)/.test(m)) && rec.dialogs.some(m => /Inventarizatsiya dalolatnomasi \(INV-16\) chop etilsinmi/.test(m))
      && pr1 && act1.includes('НАҚД ПУЛ МАБЛАҒЛАРИНИ ИНВЕНТАРИЗАЦИЯ ҚИЛИШ ДАЛОЛАТНОМАСИ') && act1.includes('ИНВ-16') && act1.includes('моддий жавобгар шахс алмашганда')
      && act1.includes('ТИЛХАТ.') && act1.includes('фойдаланилмаган: 3 та (№ 0048–0050)') && act1.includes('Инвентаризация натижалари бўйича раҳбар қарори:')
      && act1.includes('Rais — direktor Sinov Direktor') && /Топширди .*Қабул қилди/.test(act1),
    [rec.dialogs, act1.slice(0, 900)]);
  ok('bazada: qabul qilingan topshirish dalolatnomasi — handover, belgi, blankalar', q(`select kind || '|' || "molChange" || '|' || (blanks ->> 'count') from public.cash_counts where kind = 'handover' order by at desc limit 1`) === 'handover|true|3');

  // ---------------- 3) ikkinchi kassir (kassa egasi): kunni oylik / yillik komissiya inventarizatsiyasi bilan yopish
  await rec.kassaReady();
  await rec.pg.click('#ks-close'); await rec.pg.waitForSelector('#kc-inv', { timeout: 15000 });
  const inv0 = await rec.pg.$eval('#kc-inv', e => e.checked), comm0 = await rec.visible('#kc-comm');
  const lbl = await rec.pg.$eval('#kc-inv', e => e.closest('label').textContent.trim());
  await rec.pg.check('#kc-inv');
  ok(`kunni yopish: «${dec ? 'Yillik' : 'Oylik'} komissiya inventarizatsiyasi (INV-16)» — oldindan belgilanmagan, komissiya bloki yashirin; belgilanganda ko‘rinadi`,
    !inv0 && !comm0 && lbl === `${dec ? 'Yillik' : 'Oylik'} komissiya inventarizatsiyasi (INV-16)` && (await rec.visible('#kc-comm')) && (await rec.visible('#kc-inv-box'))
      && (await rec.pg.$eval('#modal [data-ct="0"]', e => e.value)) === 'Rais — direktor', [inv0, comm0, lbl]);
  await rec.pg.fill('#kc-counted', fmt(1500000));
  await rec.pg.fill('#modal [data-cn="0"]', 'Sinov Direktor'); await rec.pg.fill('#modal [data-cn="1"]', 'Sinov Buxgalter'); await rec.pg.fill('#modal [data-cn="2"]', 'Sinov Moliyachi');
  await rec.pg.fill('#kc-bcnt', '2'); await rec.pg.fill('#kc-bnos', '0049–0050');
  pb = (await rec.printed()).length; const dl0 = rec.dialogs.length;
  await rec.pg.click('#kc-save');
  const pr2 = await rec.waitPrint(pb, 'ИНВЕНТАРИЗАЦИЯ ҚИЛИШ ДАЛОЛАТНОМАСИ');
  await rec.waitPrint(pb, 'КАССА КИТОБИ|KASSA KITOBI|ВКЛАДНОЙ');
  const act2 = (await rec.printed()).slice(pb).join(' || '), dlg2 = rec.dialogs.slice(dl0);
  ok('yopish: tasdiqda INV-16 va blankalar; INV-16 dalolatnomasi (sababi, komissiya uch kishi, blankalar 2 ta, farq yo‘q) va KO-4 chop etildi',
    dlg2.some(m => /Kun yopilsinmi\?/.test(m) && m.includes('Komissiya inventarizatsiyasi (INV-16) · «Қ» blankalari: 2 ta, № 0049–0050')) && dlg2.some(m => /Inventarizatsiya dalolatnomasi \(INV-16\) chop etilsinmi/.test(m))
      && dlg2.some(m => /Kassa kitobi varag‘i \(KO-4\) chop etilsinmi/.test(m)) && pr2 && act2.includes(dec ? 'йиллик инвентаризация' : 'ойлик инвентаризация (ойнинг охирги иш куни)')
      && act2.includes('Комиссия: Rais — direktor — Sinov Direktor; A’zo — bosh buxgalter — Sinov Buxgalter; A’zo — moliya menejeri — Sinov Moliyachi')
      && act2.includes('фойдаланилмаган: 2 та (№ 0049–0050)') && act2.includes('Фарқ аниқланмади.'), [dlg2, act2.slice(0, 900)]);
  const cnt = q(`select kind || '|' || (blanks ->> 'count') || '|' || jsonb_array_length(commission) from public.cash_counts where kind in ('close', 'monthly', 'yearly') order by at desc limit 1`);
  ok(`bazada: kun yopildi — dalolatnoma ${dec ? 'yearly' : 'monthly'}, blankalar 2, komissiya 3`, cnt === `${dec ? 'yearly' : 'monthly'}|2|3` && q(`select status from public.cash_days where day = '${d0}' and desk = 'main'`) === 'closed', cnt);
  await rec.kassaReady();
  const chip = await rec.pg.$eval(`#ks-body [data-inv="${d0}"]`, e => e.textContent.trim()).catch(() => '');
  ok('kunlar ro‘yxatida «INV-16» belgisi', chip === `INV-16: ${dec ? 'yillik' : 'oylik'} komissiya inventarizatsiyasi`, chip);
  await rec.pg.screenshot({ path: `${OUT}/inv-days-${UI}-1440.png`, fullPage: true });

  // ---------------- 4) Direktor: «Davr» → oy oxiri ro'yxati; o'tgan oyni yopish
  const dir = await login(ids.R_DIR);
  await dir.kassaReady();
  await dir.pg.click('#ks-period'); await dir.pg.waitForSelector('#kpd-month', { timeout: 15000 });
  await dir.pg.selectOption('#kpd-month', ym0);
  await dir.pg.waitForFunction(() => document.querySelector('#kpd-mc-sum'), null, { timeout: 15000 });
  const rows0 = await dir.pg.$$eval('#kpd-mc-tbl tr[data-mc]', xs => Object.fromEntries(xs.map(x => [x.dataset.mc, { lv: x.dataset.mclv, t: x.innerText.replace(/\s+/g, ' ').trim() }])));
  const sum0 = await dir.pg.$eval('#kpd-mc-sum', e => e.textContent.trim());
  ok('«Davr» → oy oxiri ro‘yxati, joriy oy: INV joyida (o‘tkazilgan — bugun), yopilmagan kun yo‘q, «Oy hali tugamagan», yopish tugmasi yo‘q',
    rows0.inv && rows0.inv.lv === 'ok' && rows0.inv.t.includes(`o‘tkazilgan — ${dm(d0)}`) && rows0.days_open.lv === 'ok' && Object.keys(rows0).length === 14
      && sum0 === 'Oy hali tugamagan — ro‘yxat oldindan ko‘rish uchun.' && !(await dir.pg.$('#kpd-mc-lock')), [rows0, sum0]);
  await dir.pg.selectOption('#kpd-month', ymP);
  await dir.pg.waitForFunction(m => document.querySelector('#kpd-mc-lock') || /Davrni yopib/.test((document.querySelector('#kpd-mc-sum') || {}).textContent || ''), ymP, { timeout: 15000 }).catch(() => {});
  const rowsP = await dir.pg.$$eval('#kpd-mc-tbl tr[data-mc]', xs => Object.fromEntries(xs.map(x => [x.dataset.mc, { lv: x.dataset.mclv, t: x.innerText.replace(/\s+/g, ' ').trim() }])));
  const btn = await dir.pg.$eval('#kpd-mc-lock', e => e.textContent.trim()).catch(() => '');
  ok('o‘tgan oy: kassa kuni yo‘q (INV — ma’lumot), surat olinmagan, davr yopilmagan; «Oy oxiri surati va davrni … gacha yopish» tugmasi',
    rowsP.inv && rowsP.inv.t.includes('shu oyda yopilgan kassa kuni yo‘q') && rowsP.snapshot.t.includes('olinmagan') && rowsP.lock.t.includes('davr yopilmagan')
      && btn === `Oy oxiri surati va davrni ${dm(pme)} gacha yopish`, [rowsP.inv, rowsP.snapshot, rowsP.lock, btn]);
  const dl1 = dir.dialogs.length;
  await dir.pg.click('#kpd-mc-lock');
  await dir.pg.waitForFunction(p => (document.querySelector('#kpd-lock') || {}).textContent && document.querySelector('#kpd-lock').textContent.includes(p), dm(pme), { timeout: 20000 }).catch(() => {});
  const lk = q(`select "lockedThrough" from public.fin_org where id = 'main'`), sn = q(`select kind || '|' || "asOfDay" || '|' || note from public.fin_snapshots order by "createdAt" desc limit 1`);
  ok('oyni yopish: tasdiq (surat va qulf aytildi) → bazada qulf o‘tgan oy oxirigacha, oy oxiri surati («… yakuni» izohi bilan)',
    dir.dialogs.slice(dl1).some(m => /yopilsinmi\?/.test(m) && m.includes(`${dm(pme)} kuni oxiridagi holat surati olinadi va davr ${dm(pme)} gacha YOPILADI`))
      && lk === pme && sn.startsWith(`${pme.slice(5) === '12-31' ? 'year_end' : 'month_end'}|${pme}|`) && sn.endsWith(' yakuni'), [dir.dialogs.slice(dl1), lk, sn]);
  await dir.pg.screenshot({ path: `${OUT}/inv-period-${UI}-1440.png`, fullPage: true });
  await dir.pg.click('#m-cancel').catch(() => {}); await dir.modalGone().catch(() => {});
  // ---------------- 4b) «To'lovlar» (F2.8, 2-qism): yopilgan oy — 🔒 izoh, faktura yaratish / qayta hisoblash / tozalash o'chiq; joriy oy — ochiq
  await dir.tab('payments'); await dir.pg.waitForSelector('#pm-month', { timeout: 15000 });
  await dir.pg.waitForFunction(() => document.querySelector('#pm-body') && !document.querySelector('#pm-body .loading'), null, { timeout: 15000 }).catch(() => {});
  const pmState = async () => dir.pg.evaluate(() => { const m = document.querySelector('#pm-lockmsg');
    return { msg: m ? m.textContent : '', shown: !!m && getComputedStyle(m).display !== 'none', dis: ['#pm-gen', '#pm-recalc', '#pm-clear'].map(s => !!(document.querySelector(s) || {}).disabled) }; });
  const pmCur = await pmState();
  await dir.pg.$eval('#pm-month', (e, v) => { e.value = v; e.dispatchEvent(new Event('change')); }, ymP);
  await dir.pg.waitForFunction(() => { const e = document.querySelector('#pm-lockmsg'); return e && getComputedStyle(e).display !== 'none'; }, null, { timeout: 15000 }).catch(() => {});
  const pmOld = await pmState();
  ok('«To‘lovlar»: joriy oy — ochiq (izoh yo‘q, tugmalar faol); yopilgan o‘tgan oy — 🔒 izoh (qulf sanasi, to‘lov qabul qilinadi), faktura yaratish / qayta hisoblash / tozalash o‘chiq',
    !pmCur.shown && pmCur.dis.every(x => !x) && pmOld.shown && pmOld.msg.includes(`🔒 ${ymP} — yopilgan davr (${dm(pme)} gacha yopilgan)`)
      && pmOld.msg.includes('To‘lov qabul qilish mumkin') && pmOld.dis.every(Boolean), [pmCur, pmOld]);

  // ---------------- 5) moliya menejeri: ro'yxat bor, yopish tugmasi yo'q; telefon ekrani
  const mol = await login(ids.R_MOL, { width: 390, height: 844 });
  await mol.kassaReady();
  await mol.pg.click('#ks-period'); await mol.pg.waitForSelector('#kpd-month', { timeout: 15000 });
  await mol.pg.waitForFunction(() => document.querySelector('#kpd-mc-sum'), null, { timeout: 15000 });
  const sumM = await mol.pg.$eval('#kpd-mc-sum', e => e.textContent.trim());
  ok('moliya menejeri (telefon, 390 px): «Oy oxiri ro‘yxati» — o‘tgan oy yopilgan, yopish tugmasi yo‘q',
    (await mol.pg.$eval('#kpd-month', e => e.value)) === ymP && sumM === `Davr ${dm(pme)} gacha yopilgan ✓` && !(await mol.pg.$('#kpd-mc-lock'))
      && (await mol.pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)), [sumM]);
  await mol.pg.screenshot({ path: `${OUT}/inv-period-${UI}-390.png`, fullPage: true });

  await kas.ctx.close(); await rec.ctx.close(); await dir.ctx.close(); await mol.ctx.close();
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(1); });
