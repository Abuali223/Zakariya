// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F1.21 — to'liq Buxgalter roli: «To‘lovlar» va «Buxgalteriya» FAQAT
//   KO'RISH (yozish tugmalari yo'q), to'lovlar payments_acc dan (telefon yo'q), o'quvchi ismi students_billing dan, oylik vedomost,
//   A4 hisobot ismsiz (FD-28), qo'shimcha lavozim yo'q; Direktor ko'rinishi o'zgarmagan.  Yangi stend bilan (bash stand.sh reset dev):
//   node scenarios/e2e-kassa13.cjs [v1|v2]
const E = require('../lib/common.cjs'); const cp = require('child_process'); const { chromium } = E; const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const PHONE = '009876543';   // to'qima telefon (+998 00 … — mavjud bo'lmagan kod) — sahifada ko'rinmasligi kerak
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()'); const mon = today.slice(0, 7);
  const ACC = 'u_acc_e13';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values ('${ACC}', 'buxgalter13@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]') on conflict (id) do update set role = excluded.role, status = excluded.status, "extraRoles" = '[]'`);
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  // Sintetik ma'lumot (triggerlarsiz): biriktirilmagan onlayn to'lov (telefon bilan), shu oy fakturasi, bank xarajati, xodim avansi,
  //   berilgan maosh, tasdiqlangan vedomost (2 qator), o'tish oyi.
  q(`set session_replication_role = replica;
     insert into public.payments (id, "studentId", provider, amount, status, raw, "payerName", "payerPhone", "payerClass", matched, "createdAt")
       values ('e13-unm', '', 'click', 770000, 'unmatched', '{"phone":"+998${PHONE}"}', 'Sinov To''lovchi', '+998${PHONE}', 'Z9Q4KX', false, now())
       on conflict (id) do nothing;
     insert into public.invoices (id, "studentId", "studentName", month, amount, "paidAmount", status, "classKey", "sickDaysApplied", "sickAmount", "sickNoteRefs")
       values ('e13-inv', 'IQ-0001', 'Eski Ism', '${mon}', 1500000, 0, 'pending', '4A', 1, 50000, '{"e13sn": ["${today}"]}') on conflict (id) do nothing;
     insert into public.expenses (id, date, month, category, amount, note, method)
       values ('e13-exp', '${today}', '${mon}', 'Kanselyariya', 123000, 'Bank orqali (sinov)', 'bank') on conflict (id) do nothing;
     insert into public.staff_advances (id, "teacherId", "teacherName", amount, month, date, note)
       values ('e13-adv', 'IQX-001', 'Sinov Xodim', 50000, '${mon}', '${today}', 'sinov') on conflict (id) do nothing;
     insert into public.salary_payments (id, "teacherId", "teacherName", month, gross, advance, net, paid, date)
       values ('e13-sal', 'IQT-001', 'Sinov O''qituvchi', '${mon}', 3000000, 0, 3000000, 3000000, '${today}') on conflict (id) do nothing;
     insert into public.payroll_runs (id, status, "preparedBy", "preparedAt", "approvedBy", "approvedAt", totals)
       values ('${mon}', 'approved', '${ids.R_DIR}', now(), '${ids.R_DIR}', now(), '{"count":2,"payable":5000000}') on conflict (id) do nothing;
     insert into public.payroll_lines (id, "runId", "personType", "personId", name, gross, deduction, payable)
       values ('${mon}__IQT-001', '${mon}', 'teachers', 'IQT-001', 'Sinov O''qituvchi', 3000000, 0, 3000000),
              ('${mon}__IQX-001', '${mon}', 'staff', 'IQX-001', 'Sinov Xodim', 2000000, 0, 2000000) on conflict (id) do nothing;
     insert into public.config (id, "payrollApprovalFrom") values ('finance', '${mon}') on conflict (id) do update set "payrollApprovalFrom" = excluded."payrollApprovalFrom";
     set session_replication_role = origin;`);
  const stuName = q(`select name from public.students where "studentId" = 'IQ-0001'`);

  async function login(uid, vp, extraLS) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: vp || { width: 1440, height: 900 }, acceptDownloads: true });
    await ctx.addInitScript(([k, v, ui, ex]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365));
      if (ex && !sessionStorage.getItem('e13-ls')) { Object.keys(ex).forEach(x => localStorage.setItem(x, ex[x])); sessionStorage.setItem('e13-ls', '1'); } } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI, extraLS || null]);
    const pg = await ctx.newPage(); const reqs = [];
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => d.accept().catch(() => {}));
    pg.on('request', r => { const u = r.url(); if (/\/rest\/v1\//.test(u)) reqs.push(r.method() + ' ' + u.replace(/^.*\/rest\/v1\//, '')); });
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(900);
    const tabs = async () => pg.$$eval('#tabs button[data-tab]', a => a.map(x => x.dataset.tab));
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 15000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const view = async () => pg.$eval('#view', e => e.innerText);
    const printed = async () => pg.evaluate(() => [...document.querySelectorAll('iframe')].map(f => { try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }).filter(Boolean));
    return { ctx, pg, reqs, tabs, tab, view, printed };
  }

  // ---------------- 1) Buxgalter: bo'limlar
  const a = await login(ACC);
  {
    await a.pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length >= 4, null, { timeout: 20000 }).catch(() => {});
    const t = await a.tabs();
    ok('buxgalter: menyuda «Tasdiqlash», «To‘lovlar», «Kassa», «Buxgalteriya» (shu tartibda)', t.join(',') === 'approvals,payments,kassa,accounting', t);
    ok('buxgalter: o‘quvchilar / xodimlar / moliya (qarzdorlar) / narx bo‘limlari yo‘q', !t.some(k => ['students', 'teachers', 'staff', 'staffatt', 'finance', 'planfact', 'pricetable', 'users'].includes(k)), t);
  }
  // ---------------- 2) «To‘lovlar» — faqat ko'rish
  {
    await a.tab('payments');
    await a.pg.waitForFunction(() => document.querySelector('#pm-body') && !document.querySelector('#pm-body .loading'), null, { timeout: 30000 });
    await a.pg.waitForTimeout(800);
    const v = await a.view();
    ok('«To‘lovlar»: «Faqat ko‘rish» izohi', /Faqat ko‘rish/.test(v), v.slice(0, 300));
    ok('«To‘lovlar»: o‘quvchi ismi joriy ro‘yxatdan (students_billing), faktura nusxasidagi eski ism emas', v.includes(stuName) && !v.includes('Eski Ism'), [stuName, v.slice(0, 600)]);
    const btns = await a.pg.evaluate(() => ['#pm-gen', '#pm-recalc', '#pm-clear', '#pm-audit', '[data-pay]', '[data-receipt]', '[data-assign]', '[data-cancel]', '[data-refund]', '[data-del]', '[data-refund-pay]', '[data-mrrev]', '#pm-orphan-del'].filter(s => document.querySelector(s)));
    ok('«To‘lovlar»: yozish tugmalari yo‘q (to‘lov, chek, biriktirish, bekor, qaytarish, o‘chirish, faktura yaratish)', btns.length === 0, btns);
    ok('«To‘lovlar»: biriktirilmagan to‘lov kartochkasi bor (sana, provayder, summa); to‘lovchi matni (ism, «sinf»), telefon ustuni va raqami yo‘q', /Biriktirilmagan to‘lovlar/.test(v) && /770\s000/.test(v) && /Click/.test(v) && !v.includes('Z9Q4KX') && !/Sinov To‘lovchi|Sinov To'lovchi/.test(v) && !/telefon/i.test(await a.pg.$eval('#pm-body', e => e.innerText)) && !v.includes(PHONE), v.slice(0, 800));
    ok('«To‘lovlar»: qidiruvda telefon taklif qilinmaydi', !/telefon/i.test(await a.pg.$eval('#pm-search', e => e.placeholder)), await a.pg.$eval('#pm-search', e => e.placeholder));
    const hist = await a.pg.$('[data-hist]');
    if (hist) {
      await hist.click(); await a.pg.waitForSelector('#ph-body', { timeout: 15000 }); await a.pg.waitForFunction(() => !document.querySelector('#ph-body .loading'), null, { timeout: 15000 }).catch(() => {});
      const mh = await a.pg.$eval('#modal', e => e.innerText);
      ok('to‘lov tarixi oynasi ochiladi: avansni tuzatish va bekor qilish tugmalari yo‘q, telefon yo‘q', !(await a.pg.$('#ph-fix')) && !(await a.pg.$('[data-cancelpay]')) && !mh.includes(PHONE), mh.slice(0, 300));
      await a.pg.click('#m-cancel').catch(() => {});
    } else ok('to‘lov tarixi tugmasi (📋) bor', false);
    await a.pg.screenshot({ path: `${OUT}/acc13-pay-${UI}-1440.png` });
  }
  // ---------------- 3) «Buxgalteriya» — faqat ko'rish, vedomost, ismsiz A4
  {
    await a.tab('accounting');
    await a.pg.waitForFunction(() => document.querySelector('#ac-body') && !document.querySelector('#ac-body .loading'), null, { timeout: 30000 });
    await a.pg.waitForTimeout(800);
    const v = await a.view();
    const btns = await a.pg.evaluate(() => ['#ac-add', '#ac-payroll', '#ac-paysal', '#ac-adv', '[data-eedit]', '[data-edel]', '[data-erec]', '[data-adel]', '[data-arec]'].filter(s => document.querySelector(s)));
    ok('«Buxgalteriya»: yozish tugmalari yo‘q (xarajat, maosh yozish/berish, avans, tahrir, o‘chirish, chek)', btns.length === 0, btns);
    ok('«Buxgalteriya»: bank xarajati va xodim avansi ro‘yxatda (faqat ko‘rish)', /Bank orqali \(sinov\)/.test(v) && /Xodim avanslari/.test(v), v.slice(0, 600));
    await a.pg.waitForFunction(() => /Oylik vedomost/.test((document.querySelector('#ac-prc') || {}).innerText || ''), null, { timeout: 20000 }).catch(() => {});
    const prc = await a.pg.$eval('#ac-prc', e => e.innerText).catch(() => '');
    ok('«Buxgalteriya»: oylik vedomost kartochkasi (Tasdiqlangan), yuborish / qayta ochish tugmalari yo‘q', /Oylik vedomost/.test(prc) && /Tasdiqlangan/.test(prc) && !(await a.pg.$('#pr-submit')) && !(await a.pg.$('#pr-reopen')), prc.slice(0, 300));
    ok('vedomost: foydalanuvchi ID o‘rniga «—» (boshqa hisob qatori o‘qilmaydi)', !prc.includes(ids.R_DIR), prc.slice(0, 300));
    const lb = await a.pg.$('#pr-lines');
    if (lb) { await lb.click(); await a.pg.waitForTimeout(400); }
    const lines = await a.pg.$eval('#pr-lines-box', e => e.innerText).catch(() => '');
    ok('vedomost qatorlari: 2 xodim, summalar bilan', /Sinov O.qituvchi/.test(lines) && /Sinov Xodim/.test(lines) && /3\s000\s000/.test(lines), lines.slice(0, 300));
    ok('A4 hisobot kartochkasi buxgalterda «Oylik hisobot (ismsiz)»', /Oylik hisobot \(ismsiz\)/.test(v), v.slice(0, 200));
    await a.pg.click('#ac-report'); await a.pg.waitForTimeout(1200);
    const pr = (await a.printed()).join(' || ');
    ok('A4 hisobot ismsiz: «ismsiz nusxa» belgisi, o‘quvchi va xodim ismlari yo‘q, ID bor, imzo — buxgalter', /ismsiz nusxa/.test(pr) && !pr.includes(stuName) && !/Sinov O.qituvchi|Sinov Xodim/.test(pr) && /IQT-001/.test(pr) && /Buxgalter:/.test(pr), pr.slice(0, 900));
    await a.pg.screenshot({ path: `${OUT}/acc13-acc-${UI}-1440.png`, fullPage: false });
  }
  // ---------------- 4) tarmoq: buxgalter xom payments jadvalini so'ramaydi
  {
    const raw = a.reqs.filter(r => /^GET payments\?/.test(r));
    const viaView = a.reqs.filter(r => /^GET payments_acc\?/.test(r));
    ok('tarmoq: to‘lovlar faqat payments_acc ko‘rinishidan o‘qiladi (xom payments so‘rovi yo‘q)', raw.length === 0 && viaView.length > 0, { raw: raw.slice(0, 3), viaView: viaView.length });
    const invRaw = a.reqs.filter(r => /^GET invoices\?/.test(r)), invView = a.reqs.filter(r => /^GET invoices_acc\?/.test(r));
    ok('tarmoq: fakturalar faqat invoices_acc ko‘rinishidan o‘qiladi (xom invoices so‘rovi yo‘q)', invRaw.length === 0 && invView.length > 0, { raw: invRaw.slice(0, 3), viaView: invView.length });
    ok('tarmoq: buxgalter hech qanday yozish so‘rovi yubormadi', !a.reqs.some(r => /^(POST|PATCH|DELETE) (payments|invoices|expenses|staff_advances|salary_payments|refunds|credit_ledger|student_credit)/.test(r)), a.reqs.filter(r => !/^GET /.test(r)).slice(0, 5));
  }
  // ---------------- 5) «Kassa» ishlaydi (oldingi minimal rol)
  {
    await a.tab('kassa'); await a.pg.waitForSelector('#ks-body', { timeout: 15000 }); await a.pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 });
    const acts = await a.pg.$$eval('#ks-actions button, #ks-actions select', x => x.map(e => e.id));
    ok('«Kassa»: pul amallari yo‘q, «Davr» bor', !acts.includes('ks-in') && !acts.includes('ks-out') && !acts.includes('ks-close') && acts.includes('ks-period'), acts);
  }
  // ---------------- 6) server: to'g'ridan-to'g'ri so'rovlar
  {
    const rawKeys = asUser(ACC, `select coalesce(string_agg(distinct k, ',' order by k), '') from public.payments_acc, jsonb_object_keys(raw) k`);
    ok('server: buxgalter xom payments jadvalidan 0 qator, payments_acc dan qatorlar (to‘lovchi matni va telefon ustuni yo‘q, raw — tozalangan)',
      asUser(ACC, 'select count(*) from public.payments') === '0' && Number(asUser(ACC, 'select count(*) from public.payments_acc')) > 0
      && asUser(ACC, `select count(*) from information_schema.columns where table_name = 'payments_acc' and column_name in ('payerPhone','payerName','payerClass','merchant_trans_id')`) === '0'
      && !/phone|note|byUid/i.test(rawKeys) && !asUser(ACC, `select count(*) from public.payments_acc t where t::text ~ '${PHONE}'`).match(/^[1-9]/), rawKeys);
    ok('server: buxgalter xom invoices dan 0 qator, invoices_acc dan qatorlar (kasallik sanalari ustuni yo‘q)',
      asUser(ACC, 'select count(*) from public.invoices') === '0' && Number(asUser(ACC, 'select count(*) from public.invoices_acc')) > 0
      && asUser(ACC, `select count(*) from information_schema.columns where table_name = 'invoices_acc' and column_name = 'sickNoteRefs'`) === '0');
    let upd = ''; try { upd = asUser(ACC, `with u as (update public.expenses set amount = 1 where id = 'e13-exp' returning 1) select count(*) from u`); } catch (e) { upd = 'ERR'; }
    ok('server: buxgalter xarajatni o‘zgartira olmaydi', upd === '0' || upd === 'ERR', upd);
  }
  // ---------------- 6b) «Profil»: Direktor bo'lmagan xodim ism-familiyasini saqlay oladi (avval upsert server tomonidan rad etilardi)
  {
    await a.pg.click('#btn-pass'); await a.pg.waitForSelector('#pf-first', { timeout: 10000 });
    await a.pg.fill('#pf-first', 'Sinov'); await a.pg.fill('#pf-last', 'Buxgalter-P');
    await a.pg.click('#pf-name-save');
    await a.pg.waitForFunction(() => { const e = document.querySelector('#pf-msg'); return e && e.style.display === 'block' && e.textContent.trim().length > 0; }, null, { timeout: 10000 }).catch(() => {});
    const pm = await a.pg.$eval('#pf-msg', e => e.textContent).catch(() => '');
    ok('«Profil»: buxgalter (Direktor emas) ism-familiyasini saqlay oladi — xabar «saqlandi», bazada yangilandi',
      /saqlandi/.test(pm) && q(`select name || '|' || "firstName" || '|' || "lastName" from public.users where id = '${ACC}'`) === 'Sinov Buxgalter-P|Sinov|Buxgalter-P', pm);
    q(`update public.users set name = 'Sinov Buxgalter', "lastName" = 'Buxgalter' where id = '${ACC}'`);
  }
  await a.ctx.close();
  // ---------------- 7) telefon (390 px)
  {
    const p = await login(ACC, { width: 390, height: 844 });
    await p.pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length >= 4, null, { timeout: 20000 }).catch(() => {});
    for (const k of ['payments', 'accounting']) {
      await p.tab(k); await p.pg.waitForTimeout(2500);
      const sw = await p.pg.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      ok(`telefon: «${k}» sahifasi gorizontal siljimaydi`, sw <= 1, sw);
      await p.pg.screenshot({ path: `${OUT}/acc13-${k}-${UI}-390.png` });
    }
    await p.ctx.close();
  }
  // ---------------- 7b) yangilanish yo'li: eski formatdagi kesh (reliz raqamisiz) — qayta yuklamasdan to'rt bo'lim paydo bo'ladi
  {
    const old = JSON.stringify({ uid: ACC, on: true, goLive: today, me: { uid: ACC, operator: false, list2: true, director: false } });
    const p = await login(ACC, null, { iqror_kassa_v1: old });
    await p.pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length >= 4, null, { timeout: 20000 }).catch(() => {});
    const t = await p.tabs();
    ok('yangilanish: eski kesh bilan ham (reliz serverdan kelgach) «To‘lovlar» va «Buxgalteriya» qayta yuklamasdan qo‘shiladi', t.join(',') === 'approvals,payments,kassa,accounting', t);
    // global qidiruv: summa bo'yicha to'lov (telefon va to'lovchi matnisiz), bosilsa «To‘lovlar» ochiladi
    await p.pg.click('#btn-search'); await p.pg.waitForSelector('#gs-q', { timeout: 10000 });
    ok('qidiruv: buxgalterda «oy, summa» taklif qilinadi, «telefon» — yo‘q', /summa/.test(await p.pg.$eval('#gs-q', e => e.placeholder)) && !/telefon/i.test(await p.pg.$eval('#gs-q', e => e.placeholder)), await p.pg.$eval('#gs-q', e => e.placeholder));
    await p.pg.fill('#gs-q', '770000');
    await p.pg.waitForFunction(() => /To‘lovlar/.test((document.querySelector('#gs-res') || {}).innerText || ''), null, { timeout: 15000 }).catch(() => {});
    const gs = await p.pg.$eval('#gs-res', e => e.innerText).catch(() => '');
    ok('qidiruv: 770 000 so‘mlik to‘lov topiladi («biriktirilmagan»), telefon va to‘lovchi matni yo‘q', /770\s000/.test(gs) && /biriktirilmagan/.test(gs) && !gs.includes(PHONE) && !/Sinov To/.test(gs), gs.slice(0, 300));
    await p.ctx.close();
  }
  // ---------------- 7c) F1.21 o'qish ro'yxati o'chirilgan (fin_rights_on = off) yoki eski server (accRead yo'q): buxgalterda faqat
  //   «Tasdiqlash» va «Kassa», xatosiz; reliz raqami bunga ta'sir qilmaydi
  {
    const setAcc = on => q(`create or replace function app.acc_read() returns boolean language sql stable set search_path = public, app, pg_temp as '${on ? 'select app.is_accountant()' : 'select false'}'`);
    setAcc(false);
    try {
      const p = await login(ACC);
      await p.pg.waitForTimeout(2500);
      const t = await p.tabs();
      ok('o‘qish ro‘yxati o‘chiq (server kaliti accRead = false): buxgalterda faqat «Tasdiqlash» va «Kassa», reliz 10 bo‘lsa ham', t.slice().sort().join(',') === 'approvals,kassa', t);
      ok('o‘qish ro‘yxati o‘chiq: buxgalter o‘quvchilar ro‘yxatini (students_billing) ham o‘qimaydi', asUser(ACC, 'select count(*) from public.students_billing') === '0');
      await p.ctx.close();
    } finally { setAcc(true); }
  }
  // ---------------- 7d) Moliya menejeri: o'zgarmagan
  {
    const m = await login(ids.R_MOL);
    await m.tab('accounting'); await m.pg.waitForSelector('#ac-add', { state: 'attached', timeout: 20000 }).catch(() => {});
    ok('Moliya menejeri: «Buxgalteriya»da xarajat, maosh yozish/berish, avans tugmalari bor, vedomost kartochkasi (buxgalterniki) yo‘q',
      !!(await m.pg.$('#ac-add')) && !!(await m.pg.$('#ac-payroll')) && !!(await m.pg.$('#ac-paysal')) && !!(await m.pg.$('#ac-adv')) && !(await m.pg.$('#ac-prc')));
    await m.tab('payments'); await m.pg.waitForFunction(() => document.querySelector('#pm-body') && !document.querySelector('#pm-body .loading'), null, { timeout: 30000 }); await m.pg.waitForTimeout(800);
    ok('Moliya menejeri: «To‘lovlar»da 💵 To‘lov va Biriktirish bor, to‘lovlar xom jadvaldan', !!(await m.pg.$('[data-pay]')) && !!(await m.pg.$('[data-assign]')) && m.reqs.some(r => /^GET payments\?/.test(r)) && !m.reqs.some(r => /_acc\?/.test(r)));
    await m.ctx.close();
  }
  // ---------------- 8) Direktor: o'zgarmagan; foydalanuvchi tahriri
  {
    const d = await login(ids.R_DIR);
    await d.tab('payments'); await d.pg.waitForFunction(() => document.querySelector('#pm-body') && !document.querySelector('#pm-body .loading'), null, { timeout: 30000 }); await d.pg.waitForTimeout(800);
    const dpb = await d.pg.$eval('#pm-body', e => e.innerText).catch(() => '');
    ok('Direktor: «To‘lovlar»da faktura yaratish va to‘lov tugmalari bor, telefon ustuni bor', !!(await d.pg.$('#pm-gen')) && !!(await d.pg.$('[data-pay]')) && /telefon/i.test(dpb), [!!(await d.pg.$('#pm-gen')), !!(await d.pg.$('[data-pay]')), dpb.slice(0, 500)]);
    ok('Direktor: to‘lovlar xom payments jadvalidan o‘qiladi', d.reqs.some(r => /^GET payments\?/.test(r)) && !d.reqs.some(r => /^GET payments_acc\?/.test(r)), d.reqs.filter(r => /payments/.test(r)).slice(0, 4));
    await d.tab('accounting'); await d.pg.waitForSelector('#ac-add', { state: 'attached', timeout: 20000 }).catch(() => {});
    await d.pg.waitForFunction(() => document.querySelector('#ac-body') && !document.querySelector('#ac-body .loading'), null, { timeout: 30000 }).catch(() => {});
    ok('Direktor: «Buxgalteriya»da xarajat tugmasi bor, vedomost kartochkasi (buxgalterniki) yo‘q, hisobot — «Direktor hisoboti»', !!(await d.pg.$('#ac-add')) && !(await d.pg.$('#ac-prc')) && /Direktor hisoboti/.test(await d.view()), [!!(await d.pg.$('#ac-add')), !!(await d.pg.$('#ac-prc')), (await d.view()).slice(0, 300)]);
    await d.tab('users'); await d.pg.waitForSelector(`[data-edu="${ACC}"]`, { timeout: 30000 }).catch(() => {});
    ok('Direktor: buxgalter qatorida «➕ Lavozim» (qo‘shimcha lavozim) tugmasi yo‘q', !(await d.pg.$(`[data-xru="${ACC}"]`)));
    await d.pg.click(`[data-edu="${ACC}"]`).catch(() => {}); await d.pg.waitForSelector('#u-role', { timeout: 15000 }).catch(() => {});
    const opt = await d.pg.evaluate(() => { const o = [...document.querySelectorAll('#u-role option')].find(x => x.value === 'accountant'); return o ? o.textContent : ''; });
    ok('Direktor: rol tanlovida «Buxgalter (kassa nazorati; … faqat ko‘rish)»', /Buxgalter/.test(opt) && /faqat ko‘rish/.test(opt), opt);
    ok('server: Direktor buxgalterga qo‘shimcha lavozim bera olmaydi', /22023|berilmaydi/.test((() => { try { return asUser(ids.R_DIR, `update public.users set "extraRoles" = '["kassir"]' where id = '${ACC}' returning 1`); } catch (e) { return String(e.stderr || e.message); } })()));
    await d.ctx.close();
  }
  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(2); });
