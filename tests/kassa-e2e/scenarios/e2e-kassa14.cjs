// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): «Kassa» — ko'rikdan keyingi smena va yopish oqimlari.
//   (a) ikki bosqichli smena topshirish (state-6): qabul kutilayotganda kassada hujjat yozilmaydi (kassa:handover_pending); qabul qiluvchi
//       o'z hisobidan «Rad etish» / «Qabul qildim»; dalolatnoma ikkala ism bilan; kassa egasi bo'lmagan xodim — 2 kishilik komissiya bilan;
//   (b) yopish va topshirish oynalari avval qurilma navbatini yuboradi, expected + pendingRefs yuboradi; oyna ochiq paytda qoldiq o'zgarsa —
//       server rad etadi (kassa:stale), oyna yangi qoldiq bilan qayta ochiladi;
//   (c) g11 js-1: «Yuborilmadi» navbat yozuvlari (#kc-failed) — har biriga tanlov (pul kassada / navbatdan o'chirilsin), tanlovsiz
//       saqlanmaydi, farq tanlovga ergashadi; «o'chirilsin» — faqat muvaffaqiyatli yopish / topshirishdan keyin; «pul kassada» — pendingRefs da;
//   (d) g11 js-3: SINOV kassasini yopishda qurilma navbati ko'rsatilmaydi, pendingRefs bo'sh, navbat yozuvlari o'chirilmaydi / o'zgartirilmaydi;
//   (e) o'tgan (server ishlamagan) kunni yopishda «Қ» blankalari; #kc-ho, #kc-skip qatorlari; «… sig'madi — ayirilmaydi» izohi;
//   (f) kamomad qarori: «xodim zimmasiga» — Direktor javobgar xodim kartasini tanlaydi (#kd-party).
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa14.cjs
const E = require('../lib/common.cjs'); const cp = require('child_process'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn (eski dizayn — v1 — 2026-11-24 da olib tashlangan)
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const sqlErr = (uid, sql) => cp.spawnSync(E.PSQL[0], [...E.PSQL.slice(1), '-q', '-At', '-d', E.DB, '-c',
  `begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`], { encoding: 'utf8' }).stderr;
// onlayn kassa Z-hisoboti (F1.26): kassir Z dagi raqamlarni yozadi — sinovda tizimdagi kutilgan summalar bilan (Z mos; e2e-kassa2.cjs dagi kabi)
const zFill = async pg => { if (!(await pg.$('#kz-no'))) return false; const t = q(`select coalesce(app.kassa_z_state(id), '{}')::text from public.cash_days where desk='main' and status='open'`); const z = t ? JSON.parse(t) : {};
  if (!z.needed) return false; await pg.fill('#kz-no', 'Z-' + String(z.nCash || 0) + String(z.nCard || 0)); await pg.fill('#kz-cash', String(Math.round(Number(z.expCash) || 0))); await pg.fill('#kz-card', String(Math.round(Number(z.expCard) || 0))); return true; };
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
const rx = s => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const OBK = 'iqror_pay_outbox_v1';   // qurilma navbati (admin.html OUTBOX_KEY)
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()');
  const dmy = d => d.slice(8, 10) + '.' + d.slice(5, 7) + '.' + d.slice(0, 4);
  const NM = uid => q(`select app.kassa_names(array['${uid}']) ->> '${uid}'`);   // ismlar — bazadan (urug'ga yozib qo'yilmaydi)
  const nKas = NM(ids.R_KAS), nRec = NM(ids.R_REC), nDir = NM(ids.R_DIR);
  const sid = q(`select id from public.students order by id limit 1`);
  // navbat yozuvi (admin.html obAdd shakli); «Yuborilmadi» — status 'failed' (3 urinish), server xatosi bilan; hint 'kassa:pre_live' — pul kassaga tegishli emas
  const obItem = (payId, amount, nm, x) => Object.assign({ payId, sid: String(sid), amount, method: 'cash', date: today, note: '', period: '', nm, ts: Date.now() - 2 * 3600e3,
    extra: { fiscalNo: 'SINOV-' + payId.slice(-4).toUpperCase() } }, x || {});
  const failed = (payId, amount, nm, err, hint) => obItem(payId, amount, nm, Object.assign({ status: 'failed', attempts: 3, lastError: err }, hint ? { lastHint: hint } : {}));
  const FA = `man_e14fa${UI}01`, FB = `man_e14fb${UI}01`, FC = `man_e14fc${UI}01`, P2 = `man_e14pd${UI}01`, F2 = `man_e14fe${UI}01`, K2 = `man_e14kf${UI}01`, K3 = `man_e14kg${UI}01`;
  let rn = 0;
  const bankSql = (amount, desk) => `select public.kassa_receipt('${JSON.stringify({ desk: desk || 'main', op: 'in_bank', amount, partyType: 'bank', partyId: 'cp_b14', basis: 'Sinov bank cheki № 14-' + (++rn), clientRef: `e14-in-${UI}-${String(rn).padStart(4, '0')}` })}'::jsonb)::text`;
  const bankIn = (uid, amount, desk) => JSON.parse(asUser(uid, bankSql(amount, desk)));
  // oyna ochiq paytdagi «boshqa xodim kirimi» — rad etilsa ham ssenariy davom etadi (xato keyingi tekshiruvda ko'rinadi)
  const tryIn = (uid, amount) => { try { return bankIn(uid, amount); } catch (e) { return { err: String((e && e.message) || e).slice(0, 300) }; } };
  const status = (desk, day) => q(`select status from public.cash_days where desk = '${desk}' and day = '${day}'`);
  const tuition = fno => q(`select coalesce(string_agg(status || ':' || "fiscalNo", ','), '') from public.cash_docs where op = 'in_tuition' and "fiscalNo" = '${fno}'`);
  // naqd o'quv to'lovi «To'lovlar» bo'limidan — server javobi yetib kelmaydi (tarmoq uzilgandek) → qurilma navbatida qoladi (e2e-kassa2.cjs dagi
  //   kabi); yo'l yopiq qoladi — chaqiruvchi o'zi ochadi (unroute). Navbat yozuvi kaliti (payId) qaytadi.
  const queuePay = async (s, amount, fiscal) => {
    await s.pg.route('**/rpc/record_manual_payment', r => r.abort());
    await s.tab('payments'); await s.pg.waitForSelector('#pm-body [data-pay]', { timeout: 30000 });
    const inv = (await s.pg.$$eval('#pm-body [data-pay]', bs => bs.map(x => x.dataset.pay)))[0];
    await s.pg.click(`#pm-body [data-pay="${inv}"]`); await s.pg.waitForSelector('#rp-save');
    await s.pg.selectOption('#rp-m', 'cash'); await s.pg.waitForSelector('#rp-fiscal'); await s.pg.fill('#rp-amt', amount); await s.pg.fill('#rp-fiscal', fiscal);
    await s.pg.click('#rp-save');
    await s.pg.waitForFunction(() => /navbatga qo‘yildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 25000 }).catch(() => {});
    await s.pg.click('#rp-close').catch(() => {}); await s.modalGone();
    const it = (await s.obGet()).find(x => x.status !== 'failed' && x.extra && x.extra.fiscalNo === fiscal);
    return it ? it.payId : '';
  };

  async function login(uid, role) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui, ar, u]) => {
      try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); if (ar) localStorage.setItem('iqror_active_role:' + u, ar); } catch (e) {}
      // toast xabarlari 2,6 s da yo'qoladi — hammasi yozib boriladi
      window.__toasts = []; try { new MutationObserver(ms => { for (const m of ms) for (const n of m.addedNodes) if (n.nodeType === 1 && n.classList && n.classList.contains('toast')) window.__toasts.push(n.textContent); }).observe(document, { childList: true, subtree: true }); } catch (e) {}
    }, ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI, role || '', uid]);
    const pg = await ctx.newPage(); const dialogs = [], reqs = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    // kunni yopish / smena topshirish so'rovlari — yuborilgan ma'lumot (expected, pendingRefs) tekshiriladi
    pg.on('request', r => { const m = r.url().match(/\/rpc\/(kassa_handover|kassa_day_close)(?:\?|$)/); if (!m || r.method() !== 'POST') return; let p = null; try { p = (r.postDataJSON() || {}).p || null; } catch (e) {} reqs.push({ fn: m[1], p }); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(250); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 }).then(() => true, () => false);
    const txt = async sel => pg.$eval(sel, e => e.textContent).catch(() => null);
    const bodyTxt = async () => (await txt('#ks-body')) || '';
    const modalTxt = async () => (await txt('#modal')) || '';
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    const waitPrinted = async re => pg.waitForFunction(s => [...document.querySelectorAll('iframe')].some(f => { try { return new RegExp(s).test(f.contentDocument.body.innerText.replace(/\s+/g, ' ')); } catch (e) { return false; } }),
      re.source, { timeout: 15000 }).then(() => true, () => false);
    const toastN = async () => pg.evaluate(() => window.__toasts.length);
    const toastWait = async (re, n, t) => { await pg.waitForFunction(([s, k]) => window.__toasts.slice(k).some(x => new RegExp(s).test(x)), [re.source, n], { timeout: t || 15000 }).catch(() => {});
      return pg.evaluate(k => window.__toasts.slice(k).join(' | '), n); };
    const toastsSince = async n => pg.evaluate(k => window.__toasts.slice(k).join(' | '), n);
    const obGet = async () => pg.evaluate(k => JSON.parse(localStorage.getItem(k) || '[]'), OBK);
    const obSet = async a => pg.evaluate(([k, v]) => localStorage.setItem(k, JSON.stringify(v)), [OBK, a]);
    const obIds = async () => (await obGet()).map(x => x.payId).sort().join(',');
    // radio tanlovi (js-1) → #kc-diff matni; element yo'q bo'lsa (kutilmagan holat) — keyingi tekshiruvlar davom etadi
    const pick = async (ref, v) => { const el = await pg.$(`[data-flref="${ref}"][value="${v}"]`); if (!el) return '(tanlov yo‘q)'; await el.check(); await pg.waitForTimeout(120); return (await txt('#kc-diff')) || ''; };
    const waitModal = async re => pg.waitForFunction(s => new RegExp(s).test((document.querySelector('#modal') || {}).textContent || '') && document.querySelector('#modal-bg').classList.contains('show'), re.source, { timeout: 20000 }).then(() => true, () => false);
    return { ctx, pg, dialogs, reqs, tab, kassaReady, modalGone, txt, bodyTxt, modalTxt, printed, toastN, toastWait, toastsSince, waitPrinted, obGet, obSet, obIds, pick, waitModal };
  }

  // ---------------- 0) tayyorgarlik (Direktor, server orqali): ishga tushirish, boshlang'ich qoldiqlar; asosiy kassada kassir birinchi hujjatni yozadi
  q(`update public.users set "extraRoles" = '["kassir"]'::jsonb where id = '${ids.R_REC}'`);   // ikkinchi kassir (qo'shimcha lavozim) — smena qabul qiluvchi
  q(`insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_b14', 'bank', 'Sinov Bank ATB', '', true) on conflict (id) do nothing`);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":5000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"desk":"sinov","amount":500000,"startDay":"${today}"}'::jsonb)::text`);
  bankIn(ids.R_KAS, 100000);            // asosiy kassa: kun ochildi, kassa egasi — kassir
  bankIn(ids.R_DIR, 20000, 'sinov');    // SINOV kassasi: kun ochildi
  ok('tayyorgarlik: asosiy kassa 1 100 000 (kassa egasi — kassir), SINOV kassasi 520 000',
    q(`select string_agg(desk || ':' || trim_scale(app.kassa_day_balance(id)) || ':' || coalesce(("cashierUid" = '${ids.R_KAS}')::text, '-'), ',' order by desk) from public.cash_days where status = 'open'`) === 'main:1100000:true,sinov:520000:-',
    q(`select string_agg(desk || ':' || status, ',') from public.cash_days`));

  // ---------------- 1) (a) smena topshirish → qabul kutilmoqda: kassada hujjat yozilmaydi; qabul qiluvchi «Rad etish»
  const kas = await login(ids.R_KAS);
  let h1 = '';
  {
    const s = kas; await s.kassaReady();
    await s.pg.click('#ks-hand'); await s.pg.waitForSelector('#kh-to');
    await s.pg.selectOption('#kh-to', ids.R_REC); await s.pg.fill('#kc-counted', '1 100 000'); await s.pg.click('#kh-save'); await s.modalGone();
    await s.pg.waitForSelector('#ks-ho', { timeout: 15000 }).catch(() => {});
    h1 = q(`select coalesce(max(id), '') from public.cash_handovers where status = 'pending'`);
    ok('(a) topshirish yozildi — qabul kutilmoqda: kassa egasi o‘zgarmagan; topshiruvchida «Bekor qilish», «Qabul qildim» yo‘q',
      q(`select h.status || ':' || (h."fromUid" = '${ids.R_KAS}') || ':' || (h."toUid" = '${ids.R_REC}') || ':' || trim_scale(h.counted) || ':' || trim_scale(h.diff) || ':' || (d."cashierUid" = '${ids.R_KAS}') from public.cash_handovers h join public.cash_days d on d.id = h."dayId" where h.id = '${h1}'`) === 'pending:true:true:1100000:0:true'
        && !(await s.pg.$('[data-hoacc]')) && /Bekor qilish/.test((await s.txt('[data-horej]')) || ''), [q(`select status, counted, diff from public.cash_handovers`), (await s.bodyTxt()).slice(0, 300)]);
    // kassir «+ Kirim» yozadi — server rad etadi; Direktor kirimi ham (server orqali)
    const n0 = await s.toastN();
    await s.pg.click('#ks-in'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'in_other'); await s.pg.waitForSelector('#kf-ptype');
    await s.pg.selectOption('#kf-ptype', 'other'); await s.pg.fill('#kf-po', 'Sinov Kutilgan Kirim'); await s.pg.selectOption('[data-art="0"]', 'IN-06'); await s.pg.fill('#kf-amt', '5 000');
    await s.pg.fill('#kf-basis', 'Sinov asos № 14'); await s.pg.fill('#kf-note', 'izoh'); await s.pg.waitForSelector('#kf-fiscal'); await s.pg.fill('#kf-fiscal', 'SINOV-1400'); await s.pg.click('#kf-save');
    const t0 = await s.toastWait(/Smena topshirilmoqda/, n0);
    const e0 = sqlErr(ids.R_DIR, bankSql(7000));
    ok('(a) qabul kutilayotganda kassada hujjat yozilmaydi: kassir «+ Kirim» va Direktor kirimi — server rad etadi (kassa:handover_pending)',
      new RegExp(`Smena topshirilmoqda \\(${rx(nKas)} → ${rx(nRec)}, sanalgan 1100000 so.m\\)`).test(t0) && /Smena topshirilmoqda/.test(e0) && !!(await s.pg.$('#kf-save'))
        && q(`select count(*) from public.cash_docs where desk = 'main' and form in ('KO1', 'KO2') and status = 'posted'`) === '1', [t0, e0.slice(0, 300)]);
    await s.pg.click('#m-cancel').catch(() => {});
  }
  const rec = await login(ids.R_REC, 'kassir');   // qabul qiluvchi — o'z hisobidan (qabulxona xodimi, qo'shimcha «kassir» lavozimida)
  {
    const r = rec; await r.kassaReady(); await r.pg.waitForSelector('[data-hoacc]', { timeout: 15000 }).catch(() => {});
    const card = (await r.txt('#ks-ho')) || '';
    ok('(a) qabul qiluvchida «Smenani qabul qilish» kartasi: topshiruvchi, sanalgan summa, «Qabul qildim» va «Rad etish»',
      /Smenani qabul qilish/.test(card) && new RegExp(`${rx(nKas)} → ${rx(nRec)}`).test(card) && /sanalgan 1 100 000 so‘m/.test(card)
        && /Qabul qildim/.test((await r.txt('[data-hoacc]')) || '') && /Rad etish/.test((await r.txt('[data-horej]')) || ''), card.slice(0, 300));
    await r.pg.click('[data-horej]'); await r.pg.waitForSelector('#ks-reason');
    const ask = await r.modalTxt();
    await r.pg.fill('#ks-reason', 'Sanalgan summa mos emas (sinov)'); await r.pg.click('#ks-ok'); await r.modalGone();
    await r.pg.waitForFunction(() => !document.querySelector('[data-hoacc]'), null, { timeout: 15000 }).catch(() => {});
    await kas.kassaReady();
    ok('(a) «Rad etish»: topshirish bekor (sabab bilan, jurnalda — rad etish), kassa egasi o‘zgarmadi, dalolatnoma yo‘q; kassirda «Smena topshirish» yana bor',
      /Smenani qabul qilmaslik \(rad etish\)/.test(ask)
        && q(`select h.status || ':' || (h."cancelledBy" = '${ids.R_REC}') || ':' || h."cancelReason" || ':' || (select count(*) from public.cash_day_events e where e.kind = 'handover' and e.data ->> 'step' = 'reject' and e.data ->> 'handoverId' = h.id) || ':' || (d."cashierUid" = '${ids.R_KAS}') || ':' || (select count(*) from public.cash_counts where kind = 'handover') from public.cash_handovers h join public.cash_days d on d.id = h."dayId" where h.id = '${h1}'`) === 'cancelled:true:Sanalgan summa mos emas (sinov):1:true:0'
        && !(await kas.pg.$('#ks-ho')) && !!(await kas.pg.$('#ks-hand')), [ask.slice(0, 120), q(`select status, "cancelledBy", "cancelReason" from public.cash_handovers where id = '${h1}'`)]);
  }

  // ---------------- 2) (c) + (b) smena topshirish oynasi: «Yuborilmadi» yozuvlari, tanlov; oyna ochiq paytda qoldiq o'zgaradi (kassa:stale)
  let h2 = '';
  {
    const s = kas;
    const P0 = await queuePay(s, '50 000', 'SINOV-1402');   // navbatda — topshirish oynasi uni avval yuboradi
    await s.obSet([...(await s.obGet()), failed(FA, 20000, 'Sinov O‘quvchi A', 'To‘lov qabul qilinmadi: fiskal chek raqami takrorlangan (sinov)'), failed(FB, 30000, 'Sinov O‘quvchi B', 'To‘lov qabul qilinmadi: sinov xatosi (B)')]);
    await s.kassaReady();
    const pre0 = !!P0 && (await s.obIds()) === [P0, FA, FB].sort().join(',') && tuition('SINOV-1402') === '';
    await s.pg.unroute('**/rpc/record_manual_payment');
    s.reqs.length = 0;
    await s.pg.click('#ks-hand'); await s.pg.waitForSelector('#kh-to', { timeout: 30000 });
    ok('(b) topshirish oynasi avval qurilma navbatini yubordi: o‘quv to‘lovi o‘tdi (fiskal № bilan), navbatdan olindi; oyna yangi qoldiq bilan (1 150 000), navbat qatori — «yuborilmagan to‘lov yo‘q»',
      pre0 && tuition('SINOV-1402') === 'posted:SINOV-1402' && (await s.obIds()) === [FA, FB].sort().join(',') && /Hisobdagi qoldiq: 1 150 000 so‘m/.test(await s.modalTxt())
        && /Shu qurilma navbatida yuborilmagan naqd to‘lov yo‘q/.test((await s.txt('#kc-ob')) || ''), [pre0, P0, tuition('SINOV-1402'), await s.obIds(), ((await s.modalTxt()) || '').slice(0, 160)]);
    const fl = (await s.txt('#kc-failed')) || '';
    const radios = await s.pg.$$eval('[data-flref]', es => es.map(e => e.dataset.flref + '=' + e.value + (e.checked ? '*' : '')).sort().join(','));
    ok('(c) topshirish oynasi: «Yuborilmadi» yozuvlari (#kc-failed) — 2 ta, server xatosi bilan; har biriga tanlov (pul kassada / navbatdan o‘chirilsin), oldindan tanlanmagan',
      /Server rad etgan \(«Yuborilmadi»\) naqd to‘lovlar — 2 ta\./.test(fl) && /Sinov O‘quvchi A — 20 000 so‘m · To‘lov qabul qilinmadi: fiskal chek raqami takrorlangan \(sinov\)/.test(fl)
        && /Sinov O‘quvchi B — 30 000 so‘m · To‘lov qabul qilinmadi: sinov xatosi \(B\)/.test(fl) && radios === [`${FA}=cash`, `${FA}=drop`, `${FB}=cash`, `${FB}=drop`].sort().join(','), [fl.slice(0, 400), radios]);
    await s.pg.selectOption('#kh-to', ids.R_REC); await s.pg.fill('#kc-counted', '1 180 000');
    const d0 = (await s.txt('#kc-diff')) || '';
    const n1 = await s.toastN(); await s.pg.click('#kh-save'); const t1 = await s.toastWait(/har bir to‘lov uchun tanlang/, n1);
    ok('(c) tanlovsiz topshirilmaydi: xabar, so‘rov yuborilmaydi, oyna ochiq',
      /Server rad etgan \(«Yuborilmadi»\) har bir to‘lov uchun tanlang/.test(t1) && !!(await s.pg.$('#kh-save')) && s.reqs.length === 0 && q(`select count(*) from public.cash_handovers where status = 'pending'`) === '0', [t1, s.reqs.length]);
    const dA = await s.pick(FA, 'drop'), dB = await s.pick(FB, 'cash'), dC = await s.pick(FA, 'cash'), dD = await s.pick(FA, 'drop');
    ok('(c) farq tanlovga ergashadi: tanlovsiz +30 000; A — o‘chirilsin, B — pul kassada: farq yo‘q; A ham pul kassada: kamomad 20 000',
      /ORTIQCHA: 30 000 so‘m/.test(d0) && /ORTIQCHA: 30 000 so‘m/.test(dA) && /Farq yo‘q/.test(dB) && /KAMOMAD: 20 000 so‘m/.test(dC) && /Farq yo‘q/.test(dD), [d0, dA, dB, dC, dD]);
    const st = tryIn(ids.R_DIR, 10000);   // oyna ochiq paytda boshqa xodim kirim yozdi — qoldiq 1 160 000
    const n2 = await s.toastN(); await s.pg.click('#kh-save').catch(() => {}); const t2 = await s.toastWait(/oyna ochilgandan keyin/, n2);
    const reopened = await s.waitModal(/Hisobdagi qoldiq: 1 160 000 so‘m[\s\S]*Topshirish/);
    const rq = s.reqs.filter(r => r.fn === 'kassa_handover'), p1 = (rq[0] || {}).p || {};
    ok('(b) oyna ochiq paytda qoldiq o‘zgardi: server rad etdi (kassa:stale), oyna yangi qoldiq bilan qayta ochildi; yuborilgan expected (oynadagi) va pendingRefs (faqat «pul kassada»)',
      !st.err && /Kassa qoldig.i oyna ochilgandan keyin o.zgargan \(oynada 1150000 so.m, hozir 1160000 so.m\)/.test(t2) && reopened && !!(await s.pg.$('#kh-save'))
        && rq.length === 1 && p1.expected === 1150000 && JSON.stringify(p1.pendingRefs) === JSON.stringify([{ ref: FB, amount: 30000 }]) && p1.toUid === ids.R_REC
        && q(`select count(*) from public.cash_handovers where status = 'pending'`) === '0', [st.err, t2, reopened, rq]);
    ok('(c) topshirish rad etilganda «navbatdan o‘chirilsin» yozuvi navbatda qoladi', (await s.obIds()) === [FA, FB].sort().join(','), await s.obIds());
    await s.pg.selectOption('#kh-to', ids.R_REC).catch(() => {}); await s.pick(FA, 'drop'); await s.pick(FB, 'cash');
    await s.pg.fill('#kc-counted', '1 190 000').catch(() => {}); const d5 = (await s.txt('#kc-diff')) || '';
    await s.pg.click('#kh-save').catch(() => {}); await s.modalGone();
    await s.pg.waitForSelector('#ks-ho', { timeout: 15000 }).catch(() => {});
    await s.pg.waitForFunction(([k, fa]) => !JSON.parse(localStorage.getItem(k) || '[]').some(x => x.payId === fa), [OBK, FA], { timeout: 10000 }).catch(() => {});
    h2 = q(`select coalesce(max(id), '') from public.cash_handovers where status = 'pending'`);
    const rq2 = s.reqs.filter(r => r.fn === 'kassa_handover'), p2 = (rq2[1] || {}).p || {};
    ok('(b)(c) topshirish yozildi: expected — yangi qoldiq, «pul kassada» yozuvi pendingRefs da (topshirishda saqlandi), farq yo‘q',
      /Farq yo‘q/.test(d5) && rq2.length === 2 && p2.expected === 1160000 && JSON.stringify(p2.pendingRefs) === JSON.stringify([{ ref: FB, amount: 30000 }])
        && q(`select trim_scale(expected) || ':' || trim_scale(counted) || ':' || trim_scale("pendingSum") || ':' || trim_scale(diff) || ':' || ("pendingRefs" = '[{"ref":"${FB}","amount":30000}]'::jsonb) from public.cash_handovers where id = '${h2}'`) === '1160000:1190000:30000:0:true',
      [d5, rq2, q(`select expected, counted, "pendingSum", diff, "pendingRefs" from public.cash_handovers where status = 'pending'`)]);
    const ls3 = await s.obGet();
    ok('(c) muvaffaqiyatli topshirishdan keyin «navbatdan o‘chirilsin» yozuvi navbatdan olindi, «pul kassada» yozuvi qoldi', ls3.map(x => x.payId).join(',') === FB && ls3[0].status === 'failed', ls3.map(x => x.payId + ':' + x.status));
  }
  {
    // (a) qabul qiluvchi «Qabul qildim»: dalolatnoma — ikkala ism bilan; e'lon qilingan navbat yozuvi dalolatnomaga o'tadi
    const r = rec; await r.kassaReady(); await r.pg.waitForSelector('[data-hoacc]', { timeout: 15000 }).catch(() => {});
    const card = (await r.txt('#ks-ho')) || '';
    await r.pg.click('[data-hoacc]').catch(() => {}); await r.pg.waitForFunction(() => !document.querySelector('[data-hoacc]'), null, { timeout: 15000 }).catch(() => {});
    await r.waitPrinted(/сменани топшириш-қабул қилишда/);   // qabuldan keyin dalolatnoma chop etishga taklif qilinadi (tasdiq — avtomatik)
    ok('(a) «Qabul qildim»: kassa egasi — qabul qiluvchi; sanash dalolatnomasida «pul kassada» navbat yozuvi (hali o‘tkazilmagan), farq yo‘q',
      /hali o‘tkazilmagan 30 000 so‘m — 1 ta navbat yozuvi/.test(card)
        && q(`select h.status || ':' || (d."cashierUid" = '${ids.R_REC}') || ':' || (n."pendingRefs" = '[{"ref":"${FB}","amount":30000}]'::jsonb) || ':' || trim_scale(n.diff) || ':' || (n."fromUid" = '${ids.R_KAS}') from public.cash_handovers h join public.cash_days d on d.id = h."dayId" join public.cash_counts n on n.id = h."countId" where h.id = '${h2}'`) === 'accepted:true:true:0:true',
      [card.slice(0, 300), q(`select status, "countId" from public.cash_handovers where id = '${h2}'`)]);
    const pa = await r.printed();
    ok('(a) topshirish-qabul dalolatnomasi chop etildi: «Топширди» — kassir, «Қабул қилди» — qabul qiluvchi', pa.some(t => /НАҚД ПУЛНИ САНАШ ДАЛОЛАТНОМАСИ/.test(t) && /сменани топшириш-қабул қилишда/.test(t)
      && new RegExp('Топширди\\s*' + rx(nKas)).test(t) && new RegExp('Қабул қилди\\s*' + rx(nRec)).test(t)), pa.map(t => t.slice(0, 300)));
    await r.ctx.close();
  }

  // ---------------- 3) (a) kassa egasi bo'lmagan xodim (Direktor) topshiradi — komissiya bilan; (e) #kc-ho; kamomad → (f) qaror
  const dir = await login(ids.R_DIR);
  let h3 = '';
  {
    const s = dir; await s.kassaReady();
    await s.pg.click('#ks-hand'); await s.pg.waitForSelector('#kh-to');
    const mt = await s.modalTxt(), hoT = (await s.txt('#kc-ho')) || '', obT = (await s.txt('#kc-ob')) || '';
    ok('(a)(e) Direktor (kassa egasi emas) topshiradi: «kassir o‘rniga — komissiya bilan» va komissiya maydonlari; #kc-ho — qabul qilingan topshirishda e’lon qilingan, hali kelmagan yozuv; qurilma navbati bo‘sh',
      new RegExp(`Kassa egasi — ${rx(nRec)}\\. Siz kassir o‘rniga topshiryapsiz: komissiya \\(kamida 2 kishi\\) bilan`).test(mt) && !!(await s.pg.$('[data-cn="1"]'))
        && /Smena topshirishda e’lon qilingan, hali kelmagan: 1 ta, 30 000 so‘m/.test(hoT) && /Shu qurilma navbatida yuborilmagan naqd to‘lov yo‘q/.test(obT), [mt.slice(0, 300), hoT, obT]);
    await s.pg.selectOption('#kh-to', ids.R_KAS); await s.pg.fill('#kc-counted', '1 185 000');
    const dd = (await s.txt('#kc-diff')) || '';
    const n1 = await s.toastN(); await s.pg.click('#kh-save'); const t1 = await s.toastWait(/Komissiya a’zolarini kiriting/, n1);
    // kassa egasi bo'lmagan kassir ham (server orqali, komissiyasiz) — rad (kassa:commission)
    const eC = sqlErr(ids.R_KAS, `select public.kassa_handover('{"desk":"main","counted":1185000,"toUid":"${ids.R_KAS}"}'::jsonb)::text`);
    ok('(a) kassa egasi bo‘lmagan xodim komissiyasiz topshirmaydi: Direktor oynasi — xabar, kassir — server rad etadi (kassa:commission); oynadagi farq — e’lon qilingan yozuv bilan (kamomad 5 000)',
      /Komissiya a’zolarini kiriting \(kamida 2 kishi\)/.test(t1) && new RegExp(`Smenani kassa egasi — ${rx(nRec)} — topshiradi: uning o.rniga topshirishda kamida 2 kishilik komissiya`).test(eC)
        && q(`select count(*) from public.cash_handovers where status = 'pending'`) === '0' && /KAMOMAD: 5 000 so‘m/.test(dd), [t1, eC.slice(0, 300), dd]);
    await s.pg.fill('[data-ct="0"]', 'Direktor o‘rinbosari'); await s.pg.fill('[data-cn="0"]', 'Sinov A.A.'); await s.pg.fill('[data-ct="1"]', 'Buxgalter'); await s.pg.fill('[data-cn="1"]', 'Sinov B.B.');
    await s.pg.click('#kh-save'); await s.modalGone(); await s.pg.waitForSelector('#ks-ho', { timeout: 15000 }).catch(() => {});
    h3 = q(`select coalesce(max(id), '') from public.cash_handovers where status = 'pending'`);
    ok('(a) komissiya bilan yozildi: topshiruvchi — kassa egasi, sanagan — Direktor, server e’lon qilingan yozuvni qo‘shdi; farq −5 000; kartada «sanadi: … (komissiya bilan)»',
      q(`select ("fromUid" = '${ids.R_REC}') || ':' || ("byUid" = '${ids.R_DIR}') || ':' || ("toUid" = '${ids.R_KAS}') || ':' || jsonb_array_length(commission) || ':' || trim_scale("pendingSum") || ':' || trim_scale(diff) from public.cash_handovers where id = '${h3}'`) === 'true:true:true:2:30000:-5000'
        && new RegExp(`sanadi: ${rx(nDir)} \\(komissiya bilan\\)`).test((await s.txt('#ks-ho')) || ''), [q(`select "fromUid", "byUid", "toUid", commission, "pendingSum", diff from public.cash_handovers where id = '${h3}'`), ((await s.txt('#ks-ho')) || '').slice(0, 300)]);
  }
  {
    const s = kas; await s.kassaReady(); await s.pg.waitForSelector('[data-hoacc]', { timeout: 15000 }).catch(() => {}); await s.pg.click('[data-hoacc]').catch(() => {});
    await s.pg.waitForFunction(() => !document.querySelector('[data-hoacc]'), null, { timeout: 15000 }).catch(() => {}); await s.waitPrinted(/Санади/);
    ok('(a) kassir qabul qildi: kamomad hujjati (smena topshirishda; kassa egasi — topshiruvchi, sanagan — Direktor), kassa egasi — kassir',
      q(`select c.op || ':' || trim_scale(c.amount) || ':' || (c."sourceSnapshot" ->> 'kind') || ':' || (c."sourceSnapshot" ->> 'cashierUid' = '${ids.R_REC}') || ':' || (c."sourceSnapshot" ->> 'countedBy' = '${ids.R_DIR}') || ':' || (d."cashierUid" = '${ids.R_KAS}') from public.cash_handovers h join public.cash_docs c on c.id = h."diffDocId" join public.cash_days d on d.id = h."dayId" where h.id = '${h3}'`) === 'out_shortage:5000:handover:true:true:true',
      q(`select status, "diffDocId" from public.cash_handovers where id = '${h3}'`));
    const pa = await s.printed();
    ok('(a) dalolatnoma: komissiya, «Топширди» — kassa egasi, «Қабул қилди» — kassir, «Санади» — Direktor', pa.some(t => /Комиссия:/.test(t) && /Sinov A\.A\./.test(t) && new RegExp('Топширди\\s*' + rx(nRec)).test(t)
      && new RegExp('Қабул қилди\\s*' + rx(nKas)).test(t) && new RegExp('Санади\\s*' + rx(nDir)).test(t)), pa.map(t => t.slice(0, 400)));
  }
  {
    // (f) Direktor: kamomad «xodim zimmasiga» — standart javobgar yo'q (kassir o'rniga sanalgan), karta tanlanadi
    const s = dir; await s.kassaReady();
    await s.pg.waitForSelector('[data-decide]', { timeout: 15000 }).catch(() => {}); await s.pg.click('[data-decide]').catch(() => {}); await s.pg.waitForSelector('#kd-party').catch(() => {});
    const who = (await s.txt('#kd-who')) || '', mt = await s.modalTxt();
    const opts = await s.pg.$$eval('#kd-party option', os => os.map(o => o.value)).catch(() => []);
    const sel0 = await s.pg.$eval('#kd-party', e => e.value).catch(() => null);
    ok('(f) qaror oynasi: kassa egasi, sanagan (kassir o‘rniga), qabul qilgan; standart javobgar yo‘q — sababi; javobgar kartasi tanlanmagan, ro‘yxatda xodim kartalari',
      new RegExp(`Kassa egasi \\(kassir\\): ${rx(nRec)} · sanadi: ${rx(nDir)} \\(kassir o‘rniga, komissiya bilan\\) · qabul qildi: ${rx(nKas)}`).test(who)
        && /Pulni kassa egasining o.zi sanamagan \(kassir o.rniga sanalgan\) — javobgar xodim kartasini tanlang/.test(mt) && sel0 === '' && opts.includes(`staff:${ids.S2}`), [who, sel0, opts.slice(0, 8), (mt.match(/Javobgar xodim[\s\S]{0,200}/) || [''])[0]]);
    await s.pg.selectOption('#kd-dec', 'employee'); await s.pg.fill('#kd-note', 'Buyruq № 14: tushuntirish xati olindi (sinov)');
    const n1 = await s.toastN(); await s.pg.click('#kd-save'); const t1 = await s.toastWait(/Javobgar xodim kartasini tanlang/, n1);
    ok('(f) «Xodim zimmasiga» — karta tanlanmasa saqlanmaydi', /Javobgar xodim kartasini tanlang/.test(t1) && q(`select coalesce(decision, '-') from public.cash_docs where op = 'out_shortage'`) === '-', t1);
    await s.pg.selectOption('#kd-party', `staff:${ids.S2}`).catch(() => {}); await s.pg.click('#kd-save'); await s.modalGone();
    ok('(f) Direktor qarori — tanlangan xodim kartasi zimmasiga: dalolatnoma (Dt 4730 Kt 5910), tomon — karta ismi',
      q(`select c.decision || ':' || a.op || ':' || a."partyType" || ':' || a."partyId" || ':' || (a."partyName" = (select name from public.staff where id = '${ids.S2}')) || ':' || (a."sourceSnapshot" ->> 'picked') || ':' || l.debit || '>' || l.credit from public.cash_docs c join public.cash_docs a on a.id = c."decisionDocId" join public.cash_doc_lines l on l."docId" = a.id where c.op = 'out_shortage'`) === `employee:nc_shortage_dec:employee:staff:${ids.S2}:true:true:4730>5910`,
      q(`select decision, "decisionDocId" from public.cash_docs where op = 'out_shortage'`));
  }

  // ---------------- 4) (d) SINOV kassasi: Direktor qurilmasi navbatida asosiy kassa yozuvlari bor — sinov kunini yopishda e'lon qilinmaydi
  {
    const s = dir;
    await s.pg.route('**/rpc/record_manual_payment', r => r.abort());   // navbatdagi yozuv asosiy kassaga o'tib ketmasin (tarmoq uzilgandek)
    const q0 = [obItem(P2, 45000, 'Sinov O‘quvchi D'), failed(F2, 15000, 'Sinov O‘quvchi E', 'To‘lov qabul qilinmadi: sinov xatosi (E)'),
      failed(K2, 12000, 'Sinov O‘quvchi F', 'Kassa ishga tushishidan oldingi sana (sinov)', 'kassa:pre_live')];
    await s.obSet(q0); const q0s = JSON.stringify(q0);
    await s.kassaReady(); await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted');
    const ob = (await s.txt('#kc-ob')) || '', fl = (await s.txt('#kc-failed')) || '', sk = (await s.txt('#kc-skip')) || '';
    ok('(d)(e) asosiy kassani yopish oynasi (shu qurilma): navbat — 1 ta, 45 000; «Yuborilmadi» — 1 ta; ishga tushishdan oldingi yozuv — #kc-skip qatori',
      /Shu qurilma navbatida hali yuborilmagan naqd to‘lovlar: 1 ta, 45 000 so‘m/.test(ob) && /naqd to‘lovlar — 1 ta\./.test(fl) && /To‘lov qabul qilinmadi: sinov xatosi \(E\)/.test(fl)
        && /1 ta navbat yozuvi hisobga olinmadi — kassa ishga tushishidan oldingi pul/.test(sk), [ob, fl.slice(0, 200), sk]);
    await s.pg.click('#m-cancel'); await s.modalGone();
    await s.pg.selectOption('#ks-desk', 'sinov');
    await s.pg.waitForFunction(() => /SINOV kassasi/.test((document.querySelector('#ks-body') || {}).textContent || '') && !!document.querySelector('#ks-close'), null, { timeout: 15000 }).catch(() => {});
    s.reqs.length = 0;
    await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted');
    const mt = await s.modalTxt();
    ok('(d) SINOV kassasini yopish oynasi: navbat qatori (#kc-ob), «Yuborilmadi» (#kc-failed), #kc-skip va Z-hisobot yo‘q',
      /Hisobdagi qoldiq: 520 000 so‘m/.test(mt) && !(await s.pg.$('#kc-ob')) && !(await s.pg.$('#kc-failed')) && !(await s.pg.$('#kc-skip')) && !(await s.pg.$('#kz-no')) && !(await s.pg.$('[data-flref]')), mt.slice(0, 400));
    await s.pg.fill('#kc-counted', '520 000');
    await s.pg.fill('[data-ct="0"]', 'Direktor o‘rinbosari'); await s.pg.fill('[data-cn="0"]', 'Sinov A.A.'); await s.pg.fill('[data-ct="1"]', 'Buxgalter'); await s.pg.fill('[data-cn="1"]', 'Sinov B.B.');
    const n1 = await s.toastN(); await s.pg.click('#kc-save'); const gone = await s.modalGone(); await s.pg.waitForTimeout(800);
    const rq = s.reqs.filter(r => r.fn === 'kassa_day_close'), p = (rq[0] || {}).p || {};
    ok('(d) SINOV kuni yopildi: pendingRefs bo‘sh yuborildi (qurilma navbatida asosiy kassa yozuvi bo‘lsa ham), kunda e’lon qilingan yozuv yo‘q',
      gone && rq.length === 1 && p.desk === 'sinov' && Array.isArray(p.pendingRefs) && p.pendingRefs.length === 0
        && q(`select status || ':' || trim_scale(diff) || ':' || "pendingRefs"::text || ':' || trim_scale("pendingSum") from public.cash_days where desk = 'sinov'`) === 'closed:0:[]:0',
      [rq, q(`select status, diff, "pendingRefs" from public.cash_days where desk = 'sinov'`), await s.toastsSince(n1)]);
    // (yuborish bu yerda tarmoq uzilgandek to'silgan — route.abort; tekshiriladigani: SINOV yopilishi navbatdan hech narsani o'chirmadi va o'zgartirmadi)
    ok('(d) SINOV kunini yopish qurilma navbatidagi yozuvlarni o‘chirmadi va o‘zgartirmadi (asosiy kassa yozuvlari, «Yuborilmadi» ham — joyida)', JSON.stringify(await s.obGet()) === q0s, await s.obIds());
    await s.obSet([]); await s.ctx.close();   // Direktor qurilmasi navbati tozalanadi — yozuv keyin asosiy kassaga tushib qolmasin
  }

  // ---------------- 5) 1-kunni yopish (kassir): (b) avval navbat yuboriladi; (c) «Yuborilmadi» — tanlov; (e) #kc-ho, «sig'madi»; (b) kassa:stale
  {
    const s = kas; await s.kassaReady();
    const P = await queuePay(s, '40 000', 'SINOV-1401');   // navbatda — yopish oynasi uni avval yuboradi
    await s.obSet([...(await s.obGet()), failed(FC, 25000, 'Sinov O‘quvchi C', 'To‘lov qabul qilinmadi: sinov xatosi (C)')]);
    await s.kassaReady();
    const pre = !!P && (await s.obIds()) === [P, FB, FC].sort().join(',') && tuition('SINOV-1401') === '';
    await s.pg.unroute('**/rpc/record_manual_payment');
    s.reqs.length = 0; const dl0 = s.dialogs.length;
    await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted', { timeout: 30000 });
    ok('(b) yopish oynasi avval qurilma navbatini yubordi: o‘quv to‘lovi o‘tdi (fiskal № bilan), navbatdan olindi; oyna yangi qoldiq bilan (1 195 000), navbat qatori — «yuborilmagan to‘lov yo‘q»',
      pre && tuition('SINOV-1401') === 'posted:SINOV-1401' && (await s.obIds()) === [FB, FC].sort().join(',')
        && /Hisobdagi qoldiq: 1 195 000 so‘m/.test(await s.modalTxt()) && /Shu qurilma navbatida yuborilmagan naqd to‘lov yo‘q/.test((await s.txt('#kc-ob')) || ''),
      [pre, P, tuition('SINOV-1401'), await s.obIds(), ((await s.modalTxt()) || '').slice(0, 160)]);
    const fl = (await s.txt('#kc-failed')) || '', ho = (await s.txt('#kc-ho')) || '';
    await s.pg.fill('#kc-counted', '10 000'); const dCap = (await s.txt('#kc-diff')) || '';
    ok('(c)(e) yopish oynasi: «Yuborilmadi» — 2 ta; #kc-ho — smena topshirishda e’lon qilingan, hali kelmagan 1 ta (30 000); sanalgan pulga sig‘maganda — «… sig‘madi — ayirilmaydi» izohi',
      /naqd to‘lovlar — 2 ta\./.test(fl) && /Sinov O‘quvchi C — 25 000 so‘m · To‘lov qabul qilinmadi: sinov xatosi \(C\)/.test(fl) && /Sinov O‘quvchi B — 30 000 so‘m/.test(fl)
        && /Smena topshirishda e’lon qilingan, hali kelmagan: 1 ta, 30 000 so‘m/.test(ho) && /smena yozuvlaridan 1 tasi \(30 000 so‘m\) sanalgan pulga sig‘madi — ayirilmaydi/.test(dCap), [fl.slice(0, 300), ho, dCap]);
    await s.pg.fill('#kc-counted', '1 225 000');
    const n1 = await s.toastN(); await s.pg.click('#kc-save'); const t1 = await s.toastWait(/har bir to‘lov uchun tanlang/, n1);
    ok('(c) tanlovsiz yopilmaydi: xabar, tasdiq so‘ralmaydi, so‘rov yuborilmaydi',
      /Server rad etgan \(«Yuborilmadi»\) har bir to‘lov uchun tanlang/.test(t1) && s.dialogs.length === dl0 && s.reqs.length === 0 && status('main', today) === 'open', [t1, s.dialogs.slice(dl0), s.reqs.length]);
    const dB = await s.pick(FB, 'cash'), hoHidden = await s.pg.$eval('#kc-ho', e => e.style.display === 'none').catch(() => false);
    const dC = await s.pick(FC, 'drop'), dC2 = await s.pick(FC, 'cash'), dC3 = await s.pick(FC, 'drop');
    ok('(c) tanlov: B — pul kassada → #kc-ho dan chiqadi (ikki marta sanalmaydi), farq yo‘q; C ham pul kassada → kamomad 25 000; C — o‘chirilsin → farq yo‘q',
      /Farq yo‘q/.test(dB) && hoHidden && /Farq yo‘q/.test(dC) && /KAMOMAD: 25 000 so‘m/.test(dC2) && /Farq yo‘q/.test(dC3), [dB, hoHidden, dC, dC2, dC3]);
    await zFill(s.pg);
    const st = tryIn(ids.R_DIR, 15000);   // oyna ochiq paytda boshqa xodim kirim yozdi — qoldiq 1 210 000
    const n2 = await s.toastN(); await s.pg.click('#kc-save').catch(() => {}); const t2 = await s.toastWait(/oyna ochilgandan keyin/, n2);
    const reopened = await s.waitModal(/Hisobdagi qoldiq: 1 210 000 so‘m[\s\S]*Sanab yopish/);
    const rq = s.reqs.filter(r => r.fn === 'kassa_day_close'), p1 = (rq[0] || {}).p || {};
    ok('(b) yopish oynasi ochiq paytda qoldiq o‘zgardi: server rad etdi (kassa:stale), oyna yangi qoldiq bilan qayta ochildi; yuborilgan expected va pendingRefs (faqat «pul kassada»)',
      !st.err && /Kassa qoldig.i oyna ochilgandan keyin o.zgargan \(oynada 1195000 so.m, hozir 1210000 so.m\)/.test(t2) && reopened && rq.length === 1 && p1.expected === 1195000 && p1.day === today
        && JSON.stringify(p1.pendingRefs) === JSON.stringify([{ ref: FB, amount: 30000 }]) && status('main', today) === 'open', [st.err, t2, reopened, rq]);
    ok('(c) yopish rad etilganda «navbatdan o‘chirilsin» yozuvi navbatda qoladi', (await s.obIds()) === [FB, FC].sort().join(','), await s.obIds());
    await s.pick(FB, 'cash'); await s.pick(FC, 'drop'); await s.pg.fill('#kc-counted', '1 240 000').catch(() => {}); await zFill(s.pg);
    const dl1 = s.dialogs.length; await s.pg.click('#kc-save').catch(() => {}); await s.modalGone();
    await s.pg.waitForFunction(([k, fc]) => !JSON.parse(localStorage.getItem(k) || '[]').some(x => x.payId === fc), [OBK, FC], { timeout: 10000 }).catch(() => {});
    const cMsg = s.dialogs.slice(dl1).find(m => /Kun yopilsinmi/.test(m)) || '';
    ok('(c) yopish tasdig‘ida: «pul kassada» yozuvi — hali o‘tkazilmagan (30 000, 1 ta); «navbatdan o‘chiriladi: 1 ta»; farq yo‘q',
      /Qurilma navbatida \(hali o‘tkazilmagan\): 30 000 so‘m \(1 ta\)/.test(cMsg) && /Navbatdan o‘chiriladi \(qayta kiritilgan \/ pul qaytarilgan\): 1 ta/.test(cMsg) && /Farq yo‘q\./.test(cMsg) && !/Smena topshirishda e’lon qilingan/.test(cMsg), cMsg);
    ok('(c) 1-kun yopildi: «pul kassada» yozuvi pendingRefs da (kun va yopish sanashi), farq 0',
      q(`select d.status || ':' || trim_scale(d.diff) || ':' || trim_scale(d."pendingSum") || ':' || (d."pendingRefs" = '[{"ref":"${FB}","amount":30000}]'::jsonb) || ':' || (n."pendingRefs" = d."pendingRefs") from public.cash_days d join public.cash_counts n on n."dayId" = d.id and n.kind = 'close' where d.desk = 'main' and d.day = '${today}'`) === 'closed:0:30000:true:true',
      q(`select status, diff, "pendingSum", "pendingRefs" from public.cash_days where desk = 'main' and day = '${today}'`));
    ok('(c) muvaffaqiyatli yopishdan keyin «navbatdan o‘chirilsin» yozuvi navbatdan olindi, «pul kassada» yozuvi qoldi', (await s.obIds()) === FB, await s.obIds());
  }

  // ---------------- 6) (e) o'tgan (server ishlamagan) kunni yopish: «Қ» blankalari; ishga tushishdan oldingi navbat yozuvi — #kc-skip
  q(`insert into app.fin_clock (id, t) values (1, now() + interval '1 day') on conflict (id) do update set t = excluded.t`);
  const day2 = q('select app.fin_today()');
  bankIn(ids.R_KAS, 20000);   // 2-kun ochildi (kun boshi = 1-kun oxiri 1 210 000)
  q(`update app.fin_clock set t = now() + interval '2 days' where id = 1`);
  {
    const s = kas;
    await s.obSet([failed(K3, 12000, 'Sinov O‘quvchi G', 'Kassa ishga tushishidan oldingi sana (sinov)', 'kassa:pre_live')]); const ks = JSON.stringify(await s.obGet());
    await s.kassaReady(); const body = await s.bodyTxt();
    s.reqs.length = 0;
    await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted');
    const mt = await s.modalTxt();
    ok('(e) o‘tgan kunni yopish: «Қ» blankalari maydonlari (soni, summasi, raqamlari) va «o‘tgan kun» ogohlantirishi; #kc-skip — ishga tushishdan oldingi yozuv; «Yuborilmadi» yo‘q',
      /Oldingi kun yopilmagan/.test(body) && new RegExp(`Kunni yopish — ${rx(dmy(day2))}`).test(mt) && /Hisobdagi qoldiq: 1 230 000 so‘m/.test(mt) && /O‘tgan kun yopilmoqda: shu kuni server ishlamagan bo‘lsa/.test(mt)
        && !!(await s.pg.$('#kc-qcnt')) && !!(await s.pg.$('#kc-qsum')) && !!(await s.pg.$('#kc-qnos'))
        && /1 ta navbat yozuvi hisobga olinmadi — kassa ishga tushishidan oldingi pul/.test((await s.txt('#kc-skip')) || '') && !(await s.pg.$('#kc-failed')), [body.slice(0, 200), mt.slice(0, 500)]);
    await s.pg.fill('#kc-counted', '1 280 000'); await s.pg.fill('#kc-qcnt', '2'); await s.pg.fill('#kc-qsum', '50 000');
    const dq = (await s.txt('#kc-diff')) || '';
    const n1 = await s.toastN(), dl0 = s.dialogs.length; await s.pg.click('#kc-save'); const t1 = await s.toastWait(/«Қ» blankalari: soni, summasi va raqamlari birga kiritiladi/, n1);
    ok('(e) «Қ» blankalari farqda hisobga olinadi (sanalgan − hisobdagi = blankalar summasi); raqamlarisiz saqlanmaydi',
      /Farq yo‘q/.test(dq) && /«Қ» blankalari: soni, summasi va raqamlari birga kiritiladi/.test(t1) && s.dialogs.length === dl0 && s.reqs.length === 0 && status('main', day2) === 'open', [dq, t1]);
    await s.pg.fill('#kc-qnos', 'Қ-0012, Қ-0013'); const dl1 = s.dialogs.length; await s.pg.click('#kc-save'); await s.modalGone(); await s.pg.waitForTimeout(500);
    const cMsg = s.dialogs.slice(dl1).find(m => /Kun yopilsinmi/.test(m)) || '';
    ok('(e) o‘tgan kun «Қ» blankalari bilan yopildi: soni, summasi, raqamlari saqlandi (hali o‘tkazilmagan), farq 0; tasdiqda — blankalar',
      /«Қ» blankalari: 50 000 so‘m \(2 ta, № Қ-0012, Қ-0013\)/.test(cMsg) && /Farq yo‘q\./.test(cMsg)
        && q(`select status || ':' || "paperCount" || ':' || trim_scale("paperSum") || ':' || "paperNos" || ':' || trim_scale("pendingSum") || ':' || "pendingCount" || ':' || trim_scale(diff) || ':' || "pendingRefs"::text from public.cash_days where desk = 'main' and day = '${day2}'`) === 'closed:2:50000:Қ-0012, Қ-0013:50000:2:0:[]',
      [cMsg, q(`select status, "paperCount", "paperSum", "paperNos", "pendingSum", diff from public.cash_days where desk = 'main' and day = '${day2}'`)]);
    const pz = ((s.reqs.filter(r => r.fn === 'kassa_day_close').pop() || {}).p) || {};
    ok('(e) ishga tushishdan oldingi navbat yozuvi e’lon qilinmadi (pendingRefs bo‘sh) va navbatda qoldi', JSON.stringify(pz.pendingRefs) === '[]' && JSON.stringify(pz.paper) === JSON.stringify({ count: 2, sum: 50000, nos: 'Қ-0012, Қ-0013' }) && JSON.stringify(await s.obGet()) === ks,
      [pz, await s.obIds()]);
    await s.pg.screenshot({ path: `${OUT}/kas14-${UI}-1440.png`, fullPage: true });
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  q(`delete from app.fin_clock`);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); try { q(`delete from app.fin_clock`); } catch (_) {} process.exit(1); });
