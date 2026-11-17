// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): «Kassir» roli (egasi, 2026-11-17) —
//   kassa xodimi (HR lavozimi «G‘aznachi») tizimda «Kassir» rolini oladi, kirim-chiqimni kiritadi va kunlik hisobotni tayyorlaydi.
//   Asosiy rol «Kassir» (ids.R_KAS) bilan boshqa ssenariylarda: «+ Kirim» (KO-1), «+ Chiqim so‘rovi» (KO-2), tasdiqlangan so‘rov
//   bo'yicha pul berish, kunni yopish va KO-4 (kassa kitobi varag'i + kassir hisoboti), qayta chop etish — k1; ochiq kunning
//   «🖨 Kunlik hisobot»i — k4. Bu yerda qolgani: kassir ochiq kunda «🖨 Kassa kitobi varag‘i (qoralama)», kunni yopgach kun
//   oynasidan YAKUNIY «🖨 Kunlik hisobot» (qoralamasiz, sanalgan summa, farq) va «🖨 Kassa kitobi varag‘i» («НУСХА»);
//   Direktor: rol tanlovidagi yangi «Kassir» / «G‘aznachi» yozuvlari, «G‘aznachi» lavozimli kartaga bog'langan yangi xodimni
//   tasdiqlashda «Kassir» oldindan tanlanadi.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa18.cjs [v1|v2]
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const KAS_OPT = 'Kassir (to‘lov qabul qiladi; «Kassa»da — kirim, chiqim, kunlik hisobot)', TRE_OPT = 'G‘aznachi (kassir uchun — «Kassir» roli)';
// onlayn kassa Z-hisoboti (F1.26): fiskal chekli kirim bor kunda kassir Z dagi raqamlarni yozadi (e2e-kassa.cjs dagi kabi — kutilgan summalar)
const zFill = async pg => { if (!(await pg.$('#kz-no'))) return false; const t = q(`select coalesce(app.kassa_z_state(id), '{}')::text from public.cash_days where desk='main' and status='open'`); const z = t ? JSON.parse(t) : {};
  if (!z.needed) return false; await pg.fill('#kz-no', 'Z-' + String(z.nCash || 0) + String(z.nCard || 0)); await pg.fill('#kz-cash', String(Math.round(Number(z.expCash) || 0))); await pg.fill('#kz-card', String(Math.round(Number(z.expCard) || 0))); return true; };
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()');
  // tayyorgarlik: kassa ishga tushgan; kassir (asosiy rol, qo'shimcha lavozimsiz) — kirim va chiqim (so'rov kassirniki, MM tasdig'i, pulni
  //   kassir beradi). Bu amallarning ekran oqimi — e2e-kassa.cjs (k1).
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  q(`insert into public.fin_counterparties (id, kind, name, stir, active) values ('cp_e18', 'supplier', 'Sinov Taminot 18 MChJ', '', true) on conflict (id) do nothing`);
  const r1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_receipt('{"op":"in_other","amount":180000,"partyType":"other","partyName":"Sinov Mehmon 18","articleId":"IN-06","basis":"Tilxat 18","note":"Sinov","fiscalNo":"FS-E18-0001","clientRef":"e18-r1-0001"}'::jsonb)::text`));
  const c1 = JSON.parse(asUser(ids.R_KAS, `select public.kassa_payout_request('{"op":"out_expense","amount":45000,"partyType":"counterparty","partyId":"cp_e18","basis":"Hisob-faktura № 18","clientRef":"e18-c1-0001","lines":[{"articleId":"EX-32","amount":45000}]}'::jsonb)::text`));
  asUser(ids.R_MOL, `select public.kassa_doc_approve('${c1.id}')::text`); asUser(ids.R_KAS, `select public.kassa_doc_pay('${c1.id}')::text`);
  ok('tayyorlov: ids.R_KAS — asosiy rol «Kassir», qo‘shimcha lavozimsiz; kirim K-1 180 000 va chiqim Ch-1 45 000 kassir nomidan o‘tkazildi',
    q(`select role || ':' || coalesce("extraRoles"::text, '[]') from public.users where id = '${ids.R_KAS}'`) === 'kassir:[]' && !!r1.id
    && q(`select string_agg(form || ':' || no || ':' || status || ':' || amount::bigint || ':' || ("postedBy" = '${ids.R_KAS}'), ',' order by form) from public.cash_docs where form in ('KO1', 'KO2')`) === 'KO1:1:posted:180000:true,KO2:1:posted:45000:true',
    q(`select string_agg(form || ':' || status || ':' || coalesce("postedBy", '-'), ',') from public.cash_docs`));

  async function login(uid) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage();
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => d.accept().catch(() => {}));   // «Kassa kitobi varag‘i (KO-4) chop etilsinmi?» — ha
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 20000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const kassaReady = async () => { await tab('kassa'); await pg.waitForSelector('#ks-body', { timeout: 15000 }); await pg.waitForFunction(() => !document.querySelector('#ks-body .loading'), null, { timeout: 15000 }); await pg.waitForTimeout(300); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    // chop etish (printHTML — har safar yangi yashirin iframe): bosilgandan keyin paydo bo'lgan oxirgi iframe matni
    const printOf = async sel => { const n0 = await pg.evaluate(() => document.querySelectorAll('iframe').length); await pg.click(sel);
      await pg.waitForFunction(n => document.querySelectorAll('iframe').length > n, n0, { timeout: 15000 }); await pg.waitForTimeout(700);
      return pg.evaluate(() => { const f = [...document.querySelectorAll('iframe')].pop(); try { return f.contentDocument.body.innerText.replace(/\s+/g, ' '); } catch (e) { return ''; } }); };
    return { ctx, pg, tab, kassaReady, modalGone, printOf };
  }
  const prints = () => q(`select coalesce(string_agg(mode || '/' || ("byUid" = '${ids.R_KAS}'), ',' order by at), '-') from public.cash_prints where kind = 'book'`);

  // ---------------- 1) Kassir: ochiq kun varag'i (qoralama) → kunni yopish → yakuniy kunlik hisobot va kassa kitobi varag'i
  {
    const k = await login(ids.R_KAS); await k.kassaReady();
    const DRAFT = `button[data-book="${today}"]:has-text("qoralama")`;
    ok('kassir: ochiq kun kartasida «🖨 Kunlik hisobot» va «🖨 Kassa kitobi varag‘i (qoralama)», kunni yopish tugmasi bor',
      !!(await k.pg.$(`button[data-report="${today}"]:has-text("Kunlik hisobot")`)) && !!(await k.pg.$(DRAFT)) && !!(await k.pg.$('#ks-close')));
    const dr = await k.printOf(DRAFT);
    ok('kassir: ochiq kun kassa kitobi varag‘i — «ҚОРАЛАМА», ikki nusxa (varaq + kassir hisoboti), chop etish jurnaliga yozilmaydi',
      /КАССА ДАФТАРИ ВАРАҒИ/.test(dr) && /КАССИР ҲИСОБОТИ/.test(dr) && /ҚОРАЛАМА/.test(dr) && prints() === '-', [dr.slice(0, 300), prints()]);
    await k.pg.click('#ks-close'); await k.pg.waitForSelector('#kc-counted');
    await k.pg.fill('#kc-counted', '1 135 000'); await zFill(k.pg);
    await k.pg.click('#kc-save'); await k.modalGone(); await k.pg.waitForTimeout(1500);
    ok('kassir kunni yopdi: 1 000 000 + 180 000 − 45 000 = 1 135 000, farq 0; KO-4 asl nusxasi chop etildi (jurnalda — kassir)',
      q(`select status || ':' || trim_scale(closing) || ':' || trim_scale(diff) || ':' || ("closedBy" = '${ids.R_KAS}') from public.cash_days where desk = 'main' and day = '${today}'`) === 'closed:1135000:0:true' && prints() === 'original/true',
      [q(`select status, closing, diff, "closedBy" from public.cash_days where desk = 'main'`), prints()]);
    await k.kassaReady(); await k.pg.click(`[data-view="${today}"]`); await k.pg.waitForSelector('#kdv-report', { timeout: 15000 });
    const rp = await k.printOf('#kdv-report');
    ok('kassir: yopilgan kunning «🖨 Kunlik hisobot»i — qoralamasiz, «kun yopilgan», sanalgan summa va farq, kirim / chiqim / qoldiq, kassir',
      /KASSIRNING KUNLIK HISOBOTI/.test(rp) && !/QORALAMA/.test(rp) && /kun yopilgan/.test(rp) && /Sanab chiqilgan naqd pul 1 135 000=00/.test(rp) && /Farq yo‘q/.test(rp)
      && /Kirim \(1 ta order\) 180 000=00/.test(rp) && /Chiqim \(1 ta order\) 45 000=00/.test(rp) && /Kun oxiriga qoldiq 1 135 000=00/.test(rp) && /Kassir \S/.test(rp), rp.slice(0, 700));
    await k.pg.click('#kdv-book'); await k.pg.waitForSelector('#kp-copy', { timeout: 15000 });
    const bk = await k.printOf('#kp-copy');
    ok('kassir: kun oynasidan «🖨 Kassa kitobi varag‘i» — avval chop etilgani so‘raladi, «НУСХА» bilan, jamlar kunlik hisobot bilan bir xil',
      /КАССА ДАФТАРИ ВАРАҒИ/.test(bk) && /НУСХА/.test(bk) && /Кун бўйича жами X 180 000=00 45 000=00/.test(bk) && /Кун охирига қолдиқ X 1 135 000=00/.test(bk) && prints() === 'original/true,copy/true',
      [bk.slice(0, 500), prints()]);
    await k.ctx.close();
  }

  // ---------------- 2) Direktor: «Foydalanuvchilar» — rol tanlovi; «G‘aznachi» lavozimli karta bilan kelgan yangi xodim → «Kassir»
  //   Urug' (sintetik, triggerlarsiz): ro'yxatdan o'tgan, hali tasdiqlanmagan xodim; server uni telefon bo'yicha «G‘aznachi» kartasiga
  //   bog'lagandek (asosiy va teskari havola).
  q(`set session_replication_role = replica;
     insert into public.users (id, email, name, role, status, verified, "extraRoles", "staffRefType", "staffRefId", "staffCode")
       values ('u_e18_g', 'gaznachi18@e2e.test', 'Sinov G‘aznachi 18', 'staff', 'pending', false, '[]', 'staff', 'e18-st-g', 'IQX-018') on conflict (id) do nothing;
     insert into public.staff (id, "staffId", name, position, "userUid") values ('e18-st-g', 'IQX-018', 'Sinov G‘aznachi 18', 'G‘aznachi', 'u_e18_g') on conflict (id) do nothing;
     set session_replication_role = origin;`);
  {
    const d = await login(ids.R_DIR); await d.tab('users');
    await d.pg.waitForSelector(`[data-approve="u_e18_g"]`, { timeout: 30000 });
    await d.pg.click(`[data-edu="${ids.R_KAS}"]`); await d.pg.waitForSelector('#u-role', { timeout: 15000 });
    const opts = await d.pg.$$eval('#u-role option', os => os.map(o => [o.value, o.textContent, o.selected]));
    const kas = opts.find(o => o[0] === 'kassir') || [], tre = opts.find(o => o[0] === 'treasurer') || [];
    ok('Direktor: rol tanlovida «Kassir» — kassa amallari bilan (eski «faqat to‘lov qabul qiladi» yo‘q), «G‘aznachi» kassirni «Kassir» roliga yo‘naltiradi',
      kas[1] === KAS_OPT && kas[2] === true && tre[1] === TRE_OPT && !opts.some(o => /faqat to‘lov/.test(o[1])), opts.filter(o => ['kassir', 'treasurer'].includes(o[0])));
    await d.pg.click('#u-x'); await d.pg.waitForFunction(() => !document.querySelector('#u-role'), null, { timeout: 10000 });
    await d.pg.click(`[data-approve="u_e18_g"]`); await d.pg.waitForSelector('#u-role', { timeout: 15000 });
    const sel = await d.pg.$eval('#u-role', s => [s.value, (s.options[s.selectedIndex] || {}).textContent || '', (s.parentElement || {}).innerText || '']);
    ok('Direktor: «G‘aznachi» lavozimli kartaga bog‘langan yangi xodimni tasdiqlashda «Kassir» oldindan tanlangan (G‘aznachi emas), izohda HR yozuvi',
      sel[0] === 'kassir' && sel[1] === KAS_OPT && /IQX-018 · G‘aznachi → rol oldindan tanlandi: Kassir \(to‘lov qabul qiladi/.test(sel[2]), sel);
    await d.ctx.close();
  }

  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(2); });
