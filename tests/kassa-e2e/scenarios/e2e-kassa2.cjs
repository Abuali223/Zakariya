// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): «Kassa» — qolgan ekran yo'llari.
//   limit ogohlantirishi; asos hujjatisiz xarid (L1), T1 dan katta chiqim (2-ro'yxat + Direktor), rad etish, so'rovni bekor qilish;
//   ikki bosqichli smena topshirish (state-6: qabul qiluvchi o'z hisobidan «Qabul qildim», dalolatnoma ikkala ism bilan; smena qaytariladi);
//   yuborilmagan (navbatdagi) naqd to'lov — yopish oynasida (kaliti bilan e'lon qilinadi); kamomad → Direktor qarori → tekshirish;
//   ertasi kun: kun boshi = kecha oxiri; «oldingi kun yopilmagan» to'sig'i; ortiqcha → qayta ochish → komissiya bilan yopish →
//   qayta ochgan Direktor tekshira olmaydi (crit-4), buxgalter tekshiradi.
//   node scenarios/e2e-kassa2.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
// onlayn kassa Z-hisoboti (F1.26): kassir Z dagi raqamlarni yozadi — sinovda tizimdagi kutilgan summalar bilan (Z mos)
const zFill = async pg => { if (!(await pg.$('#kz-no'))) return; const t = q(`select coalesce(app.kassa_z_state(id), '{}')::text from public.cash_days where desk='main' and status='open'`); const z = t ? JSON.parse(t) : {};
  if (!z.needed) return; await pg.fill('#kz-no', 'Z-' + String(z.nCash || 0) + String(z.nCard || 0)); await pg.fill('#kz-cash', String(Math.round(Number(z.expCash) || 0))); await pg.fill('#kz-card', String(Math.round(Number(z.expCard) || 0))); };
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 700))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()');
  q(`update public.users set "extraRoles" = '["kassir"]'::jsonb where id = '${ids.R_REC}'`);   // ikkinchi kassir (qo'shimcha lavozim) — smena topshirish uchun
  // buxgalter (2-ro'yxat) — kunni qayta ochgan Direktor u kunni tekshirmaydi (crit-4), 2-kunni boshqa 2-ro'yxat xodimi tekshiradi
  const ACC = 'u_acc_e2';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter2@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status, "extraRoles" = '[]'`);
  // role — qo'shimcha lavozimli xodimning faol lavozimi (sarlavhadagi «Rol: …» tanlovi shu brauzerda saqlaydi): qabulxona xodimi «Kassa»ni
  //   kassir lavozimida ko'radi
  async function login(uid, vp, role) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui, ar, uid]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); if (ar) localStorage.setItem('iqror_active_role:' + uid, ar); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI, role || '', uid]);
    const pg = await ctx.newPage(); const dialogs = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(250); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const bodyTxt = async () => pg.$eval('#ks-body', e => e.textContent);
    const toasts = async () => pg.evaluate(() => [...document.querySelectorAll('.toast')].map(e => e.textContent).join(' | '));
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }));
    return { ctx, pg, dialogs, tab, kassaReady, modalGone, bodyTxt, toasts, printed };
  }
  const doc = (where, cols) => q(`select ${cols} from public.cash_docs where ${where}`);
  const bal = () => q(`select trim_scale(app.kassa_day_balance(id)) from public.cash_days where desk='main' and status='open'`);

  // ---------------- 1) Direktor: boshlang'ich qoldiq, sozlamalar (limit bilan)
  const dir = await login(ids.R_DIR);
  {
    const s = dir; await s.kassaReady();
    await s.pg.click('#ks-opening'); await s.pg.waitForSelector('#ko-amt');
    await s.pg.fill('#ko-amt', '2 000 000'); await s.pg.fill('#ko-day', today);
    await s.pg.fill('[data-ct="0"]', 'Direktor o‘rinbosari'); await s.pg.fill('[data-cn="0"]', 'Sinov A.A.');
    await s.pg.fill('[data-ct="1"]', 'Buxgalter'); await s.pg.fill('[data-cn="1"]', 'Sinov B.B.');
    await s.pg.click('#ko-save'); await s.modalGone();
    await s.pg.waitForSelector('#ks-set'); await s.pg.click('#ks-set'); await s.pg.waitForSelector('#kx-name');
    await s.pg.fill('#kx-name', '«SINOV MAKTAB» МЧЖ'); await s.pg.fill('#kx-t1', '500 000'); await s.pg.fill('#kx-l1', '200 000'); await s.pg.fill('#kx-orgmax', '1 000 000 000');
    await s.pg.fill('#kx-limit', '1 500 000'); await s.pg.fill('#kx-live', today);
    await s.pg.click('#kx-save'); await s.modalGone();
    await s.pg.waitForFunction(() => /limitdan/.test(document.querySelector('#ks-body').textContent), null, { timeout: 10000 }).catch(() => {});
    ok('limit ogohlantirishi: qoldiq limitdan oshgan', /Kassa qoldig‘i limitdan \(1 500 000 so‘m\) oshgan/.test(await s.bodyTxt()), (await s.bodyTxt()).slice(0, 300));
  }

  // ---------------- 2) Kassir: so'rovlar (asos hujjatisiz, T1 dan katta, bank, rad etiladigan)
  const kas = await login(ids.R_KAS);
  {
    const s = kas; await s.kassaReady();
    // (a) ikki statiya + «asos hujjati yo'q» — rad; bitta statiya bilan — qabul
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'out_expense'); await s.pg.waitForSelector('#kf-ptype');
    await s.pg.selectOption('#kf-ptype', 'other'); await s.pg.waitForSelector('#kf-po'); await s.pg.fill('#kf-po', 'Sinov Bozor Sotuvchisi');
    const arts = await s.pg.$eval('#kf-lines [data-art="0"]', e => [...e.options].map(o => o.value).filter(Boolean));
    await s.pg.selectOption('#kf-lines [data-art="0"]', arts[0]); await s.pg.fill('#kf-lines [data-lamt="0"]', '100 000');
    await s.pg.click('#kf-addline'); await s.pg.waitForSelector('#kf-lines [data-art="1"]');
    await s.pg.selectOption('#kf-lines [data-art="1"]', arts[1]); await s.pg.fill('#kf-lines [data-lamt="1"]', '50 000');
    ok('ko‘p qatorli xarajat: jami hisoblanadi', /150 000 so‘m/.test(await s.pg.$eval('#kf-total', e => e.textContent)), await s.pg.$eval('#kf-total', e => e.textContent));
    await s.pg.check('#kf-nobasis'); await s.pg.click('#kf-save'); await s.pg.waitForTimeout(900);
    ok('asos hujjatisiz xarid ikki statiya bilan — server rad etadi (oyna ochiq qoladi)', (await s.pg.$('#kf-save')) && doc(`op='out_expense'`, 'count(*)') === '0', await s.toasts());
    await s.pg.click('#kf-lines [data-ldel="1"]'); await s.pg.fill('#kf-lines [data-lamt="0"]', '150 000');
    await s.pg.click('#kf-save'); await s.modalGone();
    ok('(a) asos hujjatisiz xarid (150 000 ≤ L1) — so‘rov yaratildi', doc(`op='out_expense'`, `status || ':' || "noBasis" || ':' || trim_scale(amount)`) === 'draft:true:150000', doc(`op='out_expense'`, 'status, "noBasis", amount'));
    // (b) hisobdorga avans 800 000 > T1 — Direktor tasdig'i ham kerak
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'out_accountable');
    await s.pg.waitForSelector('#kf-pe'); const emp = await s.pg.$eval('#kf-pe', e => [...e.options].map(o => o.value).filter(Boolean)[0]);
    await s.pg.selectOption('#kf-pe', emp); await s.pg.fill('#kf-amt', '800 000'); await s.pg.fill('#kf-basis', 'Direktor buyrug‘i № 5 (sinov)');
    await s.pg.click('#kf-save'); await s.modalGone();
    ok('(b) hisobdorga avans 800 000 > T1: 2-ro‘yxat va Direktor tasdig‘i talab qilinadi', doc(`op='out_accountable'`, `status || ':' || "needsList2" || ':' || "needsDirector" || ':' || "partyType"`) === 'draft:true:true:employee', doc(`op='out_accountable'`, 'status, "needsList2", "needsDirector"'));
    // (c) bankka topshirish — yangi bank; keyin so'rovni o'zi bekor qiladi
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'out_bank');
    await s.pg.waitForSelector('#kf-pnew'); await s.pg.click('#kf-pnew'); await s.pg.fill('#kf-cn', 'Sinov Bank ATB'); await s.pg.click('#kf-cadd');
    await s.pg.waitForFunction(() => { const x = document.querySelector('#kf-pc'); return x && x.value; }, null, { timeout: 10000 });
    await s.pg.fill('#kf-amt', '300 000'); await s.pg.fill('#kf-basis', 'Inkassatsiya e’loni № 1'); await s.pg.click('#kf-save'); await s.modalGone();
    const cId = doc(`op='out_bank'`, 'id');
    await s.pg.waitForSelector(`[data-cancel="${cId}"]`); await s.pg.click(`[data-cancel="${cId}"]`);
    await s.pg.waitForSelector('#ks-reason'); await s.pg.fill('#ks-reason', 'Inkassator kelmadi'); await s.pg.click('#ks-ok'); await s.modalGone();
    ok('(c) kassir o‘z so‘rovini bekor qildi (raqam berilmagan)', doc(`id='${cId}'`, `status || ':' || coalesce(no::text,'-')`) === 'cancelled:-', doc(`id='${cId}'`, 'status, no'));
    // (d) rad etiladigan so'rov
    await s.pg.click('#ks-out'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'out_expense'); await s.pg.waitForSelector('#kf-ptype');
    await s.pg.selectOption('#kf-ptype', 'other'); await s.pg.fill('#kf-po', 'Sinov Rad Etiladigan'); await s.pg.selectOption('#kf-lines [data-art="0"]', arts[0]);
    await s.pg.fill('#kf-lines [data-lamt="0"]', '50 000'); await s.pg.fill('#kf-basis', 'Chek № 9'); await s.pg.click('#kf-save'); await s.modalGone();
  }
  const aId = doc(`op='out_expense' and "noBasis"`, 'id'), bId = doc(`op='out_accountable'`, 'id'), dId = doc(`"partyName"='Sinov Rad Etiladigan'`, 'id');

  // ---------------- 3) Moliya menejeri: (a), (b) ni tasdiqlaydi, (d) ni rad etadi
  {
    const s = await login(ids.R_MOL); await s.kassaReady();
    ok('moliya menejeri: ogohlantirish — tasdiq kutayotgan 3 ta so‘rov', /tasdig‘ingizni kutayotgan so‘rovlar: 3 ta/.test(await s.bodyTxt()), (await s.bodyTxt()).slice(0, 400));
    await s.pg.click(`[data-appr="${aId}"]`); await s.pg.waitForFunction(id => !document.querySelector(`[data-appr="${id}"]`), aId, { timeout: 15000 });
    await s.pg.click(`[data-appr="${bId}"]`); await s.pg.waitForFunction(id => !document.querySelector(`[data-appr="${id}"]`), bId, { timeout: 15000 });
    await s.pg.click(`[data-rej="${dId}"]`); await s.pg.waitForSelector('#ks-reason'); await s.pg.fill('#ks-reason', 'Asos hujjati yetarli emas'); await s.pg.click('#ks-ok'); await s.modalGone();
    ok('(a) tasdiqlandi; (b) hali Direktorni kutadi; (d) rad etildi (sabab bilan)',
      doc(`id='${aId}'`, 'status') === 'approved' && doc(`id='${bId}'`, `status || ':' || ("approvedBy" is not null) || ':' || ("dirApprovedBy" is null)`) === 'draft:true:true'
      && doc(`id='${dId}'`, `status || ':' || "rejectReason"`) === 'rejected:Asos hujjati yetarli emas', [doc(`id='${aId}'`, 'status'), doc(`id='${bId}'`, 'status, "approvedBy", "dirApprovedBy"'), doc(`id='${dId}'`, 'status, "rejectReason"')]);
    await s.ctx.close();
  }
  // ---------------- 4) Direktor: (b) ga ruxsat
  {
    const s = dir; await s.kassaReady();
    await s.pg.waitForSelector(`[data-appr="${bId}"]`, { timeout: 15000 }); await s.pg.click(`[data-appr="${bId}"]`);
    await s.pg.waitForFunction(id => !document.querySelector(`[data-appr="${id}"]`), bId, { timeout: 15000 });
    ok('(b) Direktor tasdiqladi — endi to‘lanadi', doc(`id='${bId}'`, `status || ':' || ("dirApprovedBy" = '${ids.R_DIR}')`) === 'approved:true', doc(`id='${bId}'`, 'status, "dirApprovedBy"'));
  }
  // ---------------- 5) Kassir: to'lash, smena topshirish, navbatdagi naqd to'lov, kamomad bilan yopish
  {
    const s = kas; await s.kassaReady();
    await s.pg.waitForSelector(`[data-pay="${aId}"]`); await s.pg.click(`[data-pay="${aId}"]`); await s.pg.waitForFunction(id => !document.querySelector(`[data-pay="${id}"]`), aId, { timeout: 15000 });
    await s.pg.waitForSelector(`[data-pay="${bId}"]`); await s.pg.click(`[data-pay="${bId}"]`); await s.pg.waitForFunction(id => !document.querySelector(`[data-pay="${id}"]`), bId, { timeout: 15000 });
    ok('chiqimlar o‘tkazildi: Ch-1, Ch-2; qoldiq 1 050 000', doc(`id in ('${aId}','${bId}')`, `string_agg(no::text, ',' order by no)`) === '1,2' && bal() === '1050000', [doc(`id in ('${aId}','${bId}')`, `string_agg(no::text || status, ',')`), bal()]);
    // smena topshirish — ikki bosqichli (state-6): topshiruvchi sanab yozadi (qabul kutiladi) → qabul qiluvchi o'z hisobidan «Qabul qildim»
    await s.pg.click('#ks-hand'); await s.pg.waitForSelector('#kh-to');
    await s.pg.selectOption('#kh-to', ids.R_REC); await s.pg.fill('#kc-counted', '1 050 000'); await s.pg.click('#kh-save'); await s.modalGone();
    await s.pg.waitForSelector('#ks-ho', { timeout: 15000 });
    ok('smena topshirish yozildi — qabul kutilmoqda: kassa egasi o‘zgarmagan, dalolatnoma yo‘q, «Kunni yopish» / «Smena topshirish» yo‘q',
      q(`select h.status || ':' || (h."fromUid" = '${ids.R_KAS}') || ':' || (h."toUid" = '${ids.R_REC}') || ':' || trim_scale(h.counted) || ':' || trim_scale(h.diff) || ':' || (d."cashierUid" = '${ids.R_KAS}') || ':' || (select count(*) from public.cash_counts where kind='handover') from public.cash_handovers h join public.cash_days d on d.id = h."dayId"`) === 'pending:true:true:1050000:0:true:0'
        && /Smena topshirish — qabul kutilmoqda/.test(await s.bodyTxt()) && !(await s.pg.$('#ks-close')) && !(await s.pg.$('#ks-hand')),
      [q(`select status, "fromUid", "toUid", counted, diff from public.cash_handovers`), (await s.bodyTxt()).slice(0, 300)]);
    const rec = await login(ids.R_REC, null, 'kassir');   // qabul qiluvchi — o'z hisobidan (qabulxona xodimi, qo'shimcha «kassir» lavozimida)
    {
      const r = rec; await r.kassaReady(); await r.pg.waitForSelector('[data-hoacc]', { timeout: 15000 });
      ok('qabul qiluvchida «Smenani qabul qilish» kartasi: «Qabul qildim» va «Rad etish»', /Smenani qabul qilish/.test(await r.bodyTxt()) && /Rad etish/.test(await r.pg.$eval('[data-horej]', e => e.textContent)));
      await r.pg.click('[data-hoacc]'); await r.pg.waitForFunction(() => !document.querySelector('[data-hoacc]'), null, { timeout: 15000 }); await r.pg.waitForTimeout(1500);
      ok('smena qabul qilindi: kun kassiri — qabul qiluvchi, sanash dalolatnomasi yozildi', q(`select ("cashierUid" = '${ids.R_REC}') || ':' || (select count(*) from public.cash_counts where kind='handover' and "toUid"='${ids.R_REC}' and "fromUid"='${ids.R_KAS}' and diff = 0) || ':' || (select status from public.cash_handovers) from public.cash_days where desk='main'`) === 'true:1:accepted',
        q(`select "cashierUid", (select status from public.cash_handovers) from public.cash_days where desk='main'`));
      const pa = await r.printed();
      ok('topshirish-qabul dalolatnomasi chop etildi: ikkala ism bilan', pa.some(t => /НАҚД ПУЛНИ САНАШ ДАЛОЛАТНОМАСИ/.test(t) && /сменани топшириш-қабул қилишда/.test(t) && /Топширди\s*Sinov Kassir/.test(t) && /Қабул қилди\s*Sinov Qabulxona/.test(t)), pa.map(t => t.slice(0, 300)));
      // kassa egasi endi qabul qiluvchi: u smenani asosiy kassirga qaytaradi (yana ikki bosqich) — kun oxirigacha kassir ishlaydi
      await r.pg.click('#ks-hand'); await r.pg.waitForSelector('#kh-to');
      await r.pg.selectOption('#kh-to', ids.R_KAS); await r.pg.fill('#kc-counted', '1 050 000'); await r.pg.click('#kh-save'); await r.modalGone();
      await r.ctx.close();
    }
    await s.kassaReady(); await s.pg.waitForSelector('[data-hoacc]', { timeout: 15000 }); await s.pg.click('[data-hoacc]');
    await s.pg.waitForFunction(() => !document.querySelector('[data-hoacc]'), null, { timeout: 15000 }); await s.pg.waitForTimeout(800);
    ok('smena qaytarildi: kun kassiri yana asosiy kassir, ikkala topshirish qabul qilingan', q(`select ("cashierUid" = '${ids.R_KAS}') || ':' || (select string_agg(status, ',') from public.cash_handovers) || ':' || (select count(*) from public.cash_counts where kind='handover') from public.cash_days where desk='main'`) === 'true:accepted,accepted:2',
      q(`select "cashierUid" from public.cash_days where desk='main'`));
    // naqd o'quv to'lovi — server javobi yetib kelmaydi (tarmoq uzilgan kabi) → navbatda qoladi
    await s.pg.route('**/rpc/record_manual_payment', r => r.abort());
    await s.tab('payments'); await s.pg.waitForSelector('#pm-body [data-pay]', { timeout: 30000 });
    const inv = (await s.pg.$$eval('#pm-body [data-pay]', bs => bs.map(x => x.dataset.pay)))[0];
    await s.pg.click(`#pm-body [data-pay="${inv}"]`); await s.pg.waitForSelector('#rp-save');
    await s.pg.selectOption('#rp-m', 'cash'); await s.pg.waitForSelector('#rp-fiscal'); await s.pg.fill('#rp-amt', '100 000'); await s.pg.fill('#rp-fiscal', 'SINOV-0002');
    await s.pg.click('#rp-save');
    await s.pg.waitForFunction(() => /navbatga qo‘yildi/.test((document.querySelector('#modal .modal-h h3') || {}).textContent || ''), null, { timeout: 25000 }).catch(() => {});
    const mt = await s.pg.$eval('#modal', e => e.textContent).catch(() => '');
    ok('yuborilmagan naqd to‘lov navbatda: fiskal № saqlangan, to‘lovchiga tizim varaqasi yo‘q', /navbatga qo‘yildi/.test(mt) && /NKM/.test(mt) && !(await s.pg.$('#rp-print'))
      && (await s.pg.evaluate(() => { const a = JSON.parse(localStorage.getItem('iqror_pay_outbox_v1') || '[]'); return a.length === 1 && a[0].extra && a[0].extra.fiscalNo === 'SINOV-0002'; })), mt.slice(0, 300));
    await s.pg.click('#rp-close').catch(() => {});
    await s.kassaReady(); await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted');
    // state-2: navbat yozuvlari qo'lda kiritilmaydi — oyna ochilishidan oldin navbat yuboriladi (bu yerda tarmoq yo'q), qolgani kaliti bilan e'lon qilinadi
    ok('yopish oynasi: navbatdagi yozuv soni va summasi ko‘rsatilgan (qo‘lda kiritilmaydi), farqda hisobga olinadi', await (async () => {
      const t = await s.pg.$eval('#kc-ob', e => e.textContent).catch(() => '');
      await s.pg.fill('#kc-counted', '1 150 000'); const d = await s.pg.$eval('#kc-diff', e => e.textContent);
      return /hali yuborilmagan naqd to‘lovlar: 1 ta, 100 000 so‘m/.test(t) && !(await s.pg.$('#kc-pcount')) && /Farq yo‘q/.test(d); })(), await s.pg.$eval('#kc-ob', e => e.textContent).catch(() => 'kc-ob yo‘q'));
    await s.pg.click('#m-cancel');
    await s.pg.unroute('**/rpc/record_manual_payment');
    await s.pg.click('#ob-badge'); await s.pg.waitForSelector('#ob-retry'); await s.pg.click('#ob-retry');
    await s.pg.waitForFunction(() => JSON.parse(localStorage.getItem('iqror_pay_outbox_v1') || '[]').length === 0, null, { timeout: 30000 }).catch(() => {});
    ok('ulanish tiklangach navbat yuborildi: K-1, fiskal № bilan; qoldiq 1 150 000', doc(`op='in_tuition'`, `no || ':' || status || ':' || "fiscalNo"`) === '1:posted:SINOV-0002' && bal() === '1150000', [doc(`op='in_tuition'`, 'no, status, "fiscalNo"'), bal()]);
    // kamomad bilan yopish
    await s.kassaReady(); await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted'); await s.pg.fill('#kc-counted', '1 143 000');
    ok('yopish oynasi: kamomad ko‘rsatiladi', /KAMOMAD: 7 000 so‘m/.test(await s.pg.$eval('#kc-diff', e => e.textContent)), await s.pg.$eval('#kc-diff', e => e.textContent));
    await zFill(s.pg); await s.pg.click('#kc-save'); await s.modalGone();
    ok('kun yopildi: farq −7 000 shu kunning tizim hujjati (Ch-3, Dt 5910), kun oxiri = sanalgan',
      q(`select d.status || ':' || trim_scale(d.diff) || ':' || trim_scale(d.closing) || ':' || c.no || ':' || c."isSystem" || ':' || l.debit from public.cash_days d join public.cash_docs c on c.id = d."diffDocId" join public.cash_doc_lines l on l."docId" = c.id where d.desk='main'`) === 'closed:-7000:1143000:3:true:5910',
      q(`select d.status, d.diff, d.closing from public.cash_days d where d.desk='main'`));
    // oyna yopilgach ro'yxat serverdan qayta yuklanadi (act → reload) — ogohlantirish shundan keyin chiziladi
    await s.pg.waitForFunction(() => /Qarori kutilayotgan kamomad/.test((document.querySelector('#ks-body') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
    ok('kassirga: kamomad qarori — Direktorda', /Qarori kutilayotgan kamomad: 1 ta \(Direktor qarori\)/.test(await s.bodyTxt()) && !(await s.pg.$('[data-decide]')), (await s.bodyTxt()).slice(0, 300));
  }
  // ---------------- 6) Direktor: kamomad qarori; moliya menejeri: tekshirish
  {
    const s = dir; await s.kassaReady();
    await s.pg.waitForSelector('[data-decide]', { timeout: 15000 }); await s.pg.click('[data-decide]');
    await s.pg.waitForSelector('#kd-dec'); await s.pg.selectOption('#kd-dec', 'writeoff'); await s.pg.fill('#kd-note', 'Buyruq № 12: aybdor aniqlanmadi'); await s.pg.click('#kd-save'); await s.modalGone();
    ok('Direktor qarori: hisobdan chiqarish — naqdsiz dalolatnoma (Dt 9430 Kt 5910)', q(`select c.decision || ':' || a.form || ':' || a.status || ':' || l.debit || '>' || l.credit from public.cash_docs c join public.cash_docs a on a.id = c."decisionDocId" join public.cash_doc_lines l on l."docId" = a.id where c.op='out_shortage'`) === 'writeoff:ACT:posted:9430>5910',
      q(`select decision, "decisionDocId" from public.cash_docs where op='out_shortage'`));
    const m = await login(ids.R_MOL); await m.kassaReady();
    await m.pg.waitForSelector(`[data-verify="${today}"]`); await m.pg.click(`[data-verify="${today}"]`); await m.pg.waitForSelector('#kv-papers');
    await m.pg.click('#kv-save'); await m.pg.waitForTimeout(500);
    ok('tekshirish: «qog‘ozlar olindi» belgilanmasa — saqlanmaydi', q(`select status from public.cash_days where desk='main'`) === 'closed');
    await m.pg.check('#kv-papers'); await m.pg.click('#kv-save'); await m.modalGone();
    ok('1-kun tekshirildi', q(`select status from public.cash_days where desk='main'`) === 'verified');
    await m.ctx.close();
  }

  // ---------------- 7) Ertasi kun: kun boshi = kecha oxiri; to'siq; ortiqcha; qayta ochish; komissiya bilan yopish
  q(`insert into app.fin_clock (id, t) values (1, now() + interval '1 day') on conflict (id) do update set t = excluded.t`);
  const day2 = q('select app.fin_today()');
  {
    const s = kas; await s.kassaReady();
    ok('ertasi kun: ochiq kun yo‘q, oxirgi qoldiq 1 143 000', /Ochiq kun yo‘q/.test(await s.bodyTxt()) && /1 143 000 so‘m/.test(await s.bodyTxt()), (await s.bodyTxt()).slice(0, 300));
    await s.pg.click('#ks-in'); await s.pg.waitForSelector('#kf-op'); await s.pg.selectOption('#kf-op', 'in_other'); await s.pg.waitForSelector('#kf-ptype');
    await s.pg.selectOption('#kf-ptype', 'other'); await s.pg.fill('#kf-po', 'Sinov Ikkinchi Kun'); await s.pg.selectOption('[data-art="0"]', 'IN-06'); await s.pg.fill('#kf-amt', '57 000');
    await s.pg.fill('#kf-basis', 'Sinov asos № 2'); await s.pg.fill('#kf-note', 'izoh');
    await s.pg.fill('#kf-fiscal', 'SINOV-0201');   // g7: «Boshqa kirim» boshqa shaxsdan — fiskal chek № majburiy
    await s.pg.click('#kf-save'); await s.modalGone();
    ok('yangi kun birinchi hujjat bilan ochildi: kun boshi = kecha oxiri, raqam davom etadi (K-2)', q(`select d.day || ':' || trim_scale(d.opening) || ':' || c.no from public.cash_days d join public.cash_docs c on c."dayId" = d.id where d.status='open'`) === `${day2}:1143000:2`, q(`select day, opening from public.cash_days where status='open'`));
    // soat yana bir kun oldinga: «oldingi kun yopilmagan»
    q(`update app.fin_clock set t = now() + interval '2 days' where id = 1`);
    await s.kassaReady();
    ok('kun almashdi, kecha yopilmagan: ogohlantirish', /Oldingi kun yopilmagan/.test(await s.bodyTxt()), (await s.bodyTxt()).slice(0, 200));
    await s.tab('payments'); await s.pg.waitForSelector('#pm-body [data-pay]', { timeout: 30000 });
    const inv = (await s.pg.$$eval('#pm-body [data-pay]', bs => bs.map(x => x.dataset.pay)))[0];
    await s.pg.click(`#pm-body [data-pay="${inv}"]`); await s.pg.waitForSelector('#rp-save'); await s.pg.selectOption('#rp-m', 'cash'); await s.pg.waitForSelector('#rp-fiscal');
    ok('«To‘lov» shakli: naqd tanlanganda to‘siq sababi ko‘rsatiladi', /Oldingi kassa kuni yopilmagan/.test(await s.pg.$eval('#rp-kassa', e => e.textContent)));
    await s.pg.fill('#rp-amt', '100 000'); await s.pg.fill('#rp-fiscal', 'SINOV-0003'); await s.pg.click('#rp-save'); await s.pg.waitForTimeout(1200);
    ok('to‘siq paytida naqd to‘lov qabul qilinmaydi va navbatga ham qo‘yilmaydi', (await s.pg.evaluate(() => JSON.parse(localStorage.getItem('iqror_pay_outbox_v1') || '[]').length)) === 0 && q(`select count(*) from public.payments where "fiscalNo"='SINOV-0003'`) === '0');
    await s.pg.click('#m-cancel').catch(() => {});
    // 2-kunni ortiqcha bilan yopish
    await s.kassaReady(); await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted'); await s.pg.fill('#kc-counted', '1 203 000');
    ok('yopish oynasi: ortiqcha ko‘rsatiladi', /ORTIQCHA: 3 000 so‘m/.test(await s.pg.$eval('#kc-diff', e => e.textContent)));
    await zFill(s.pg); await s.pg.click('#kc-save'); await s.modalGone();
    ok('2-kun yopildi: ortiqcha +3 000 — kirim hujjati (K-3, Kt 9390), sana — o‘sha kun', q(`select d.status || ':' || trim_scale(d.diff) || ':' || c.no || ':' || c.form || ':' || c."businessDay" || ':' || l.credit from public.cash_days d join public.cash_docs c on c.id = d."diffDocId" join public.cash_doc_lines l on l."docId" = c.id where d.day='${day2}'`) === `closed:3000:3:KO1:${day2}:9390`,
      q(`select status, diff from public.cash_days where day='${day2}'`));
    await s.ctx.close();
  }
  {
    const s = dir; await s.kassaReady();
    await s.pg.waitForSelector(`[data-reopen="${day2}"]`, { timeout: 15000 }); await s.pg.click(`[data-reopen="${day2}"]`);
    await s.pg.waitForSelector('#ks-reason'); await s.pg.fill('#ks-reason', 'Qayta sanash kerak (sinov)'); await s.pg.click('#ks-ok'); await s.modalGone();
    ok('Direktor kunni qayta ochdi: farq hujjati bekor (raqami saqlanadi), kun ochiq', q(`select d.status || ':' || d."reopenCount" || ':' || (select status || ':' || no from public.cash_docs where op='in_surplus') from public.cash_days d where d.day='${day2}'`) === 'open:1:void:3',
      q(`select status, "reopenCount" from public.cash_days where day='${day2}'`));
    ok('tekshirilgan 1-kunda qayta ochish tugmasi yo‘q', !(await s.pg.$(`[data-reopen="${today}"]`)));
    await s.ctx.close();
  }
  {
    const s = await login(ids.R_MOL); await s.kassaReady();
    await s.pg.click('#ks-close'); await s.pg.waitForSelector('#kc-counted'); await s.pg.fill('#kc-counted', '1 200 000');
    await zFill(s.pg); await s.pg.click('#kc-save'); await s.pg.waitForTimeout(600);
    ok('kassir o‘rniga yopish: komissiyasiz — saqlanmaydi', q(`select status from public.cash_days where day='${day2}'`) === 'open');
    await s.pg.fill('[data-ct="0"]', 'Moliya menejeri'); await s.pg.fill('[data-cn="0"]', 'Sinov M.M.'); await s.pg.fill('[data-ct="1"]', 'Hisobchi'); await s.pg.fill('[data-cn="1"]', 'Sinov H.H.');
    await zFill(s.pg); await s.pg.click('#kc-save'); await s.modalGone();
    ok('moliya menejeri komissiya bilan yopdi: farq yo‘q, varaq 2', q(`select status || ':' || trim_scale(diff) || ':' || jsonb_array_length(commission) || ':' || "sheetFrom" || ':' || ("closedBy" = '${ids.R_MOL}') from public.cash_days where day='${day2}'`) === 'closed:0:2:2:true', q(`select status, diff, commission, "sheetFrom" from public.cash_days where day='${day2}'`));
    ok('yopuvchi o‘zi tekshira olmaydi — server rad etadi', await (async () => { await s.pg.click(`[data-verify="${day2}"]`); await s.pg.waitForSelector('#kv-papers'); await s.pg.check('#kv-papers'); await s.pg.click('#kv-save'); await s.pg.waitForTimeout(900);
      const st = q(`select status from public.cash_days where day='${day2}'`); await s.pg.click('#m-cancel').catch(() => {}); return st === 'closed'; })());
    await s.pg.screenshot({ path: `${OUT}/mol-${UI}-1440.png`, fullPage: true });
    await s.ctx.close();
  }
  {
    // crit-4: kunni qayta ochgan xodim (Direktor) uni tekshirmaydi — server sababi bilan rad etadi
    const s = await login(ids.R_DIR); await s.kassaReady();
    await s.pg.click(`[data-verify="${day2}"]`); await s.pg.waitForSelector('#kv-papers'); await s.pg.check('#kv-papers'); await s.pg.click('#kv-save'); await s.pg.waitForTimeout(1000);
    const tt = await s.toasts();
    ok('kunni qayta ochgan Direktor uni tekshira olmaydi — server rad etadi', q(`select status from public.cash_days where day='${day2}'`) === 'closed' && /Kunni o‘zingiz qayta ochgansiz|Kunni o'zingiz qayta ochgansiz/.test(tt), tt);
    await s.pg.click('#m-cancel').catch(() => {});
    await s.ctx.close();
  }
  {
    const s = await login(ACC); await s.kassaReady();
    await s.pg.waitForSelector(`[data-verify="${day2}"]`, { timeout: 15000 }); await s.pg.click(`[data-verify="${day2}"]`); await s.pg.waitForSelector('#kv-papers'); await s.pg.check('#kv-papers'); await s.pg.click('#kv-save'); await s.modalGone();
    ok('buxgalter (2-ro‘yxat) 2-kunni tekshirdi', q(`select status || ':' || ("verifiedBy" = '${ACC}') from public.cash_days where day='${day2}'`) === 'verified:true', q(`select status, "verifiedBy" from public.cash_days where day='${day2}'`));
    await s.ctx.close();
  }
  ok('raqamlashda bo‘shliq yo‘q; chop etish jurnalida qayta chiqarish yo‘q', q(`select jsonb_array_length(app.kassa_gap_check('main', extract(year from date '${today}')::int))`) === '0');
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs);
  q(`delete from app.fin_clock`);
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);   // chiqish kodi: 0 — faqat hammasi o'tsa (README)
})().catch(e => { console.error('XATO', e); try { q(`delete from app.fin_clock`); } catch (_) {} process.exit(1); });
