// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): FD-28 — tizimdan chiqadigan fayllar
//   «Moliya» → qarzdorlar CSV, «Buxgalteriya» → A4 oylik hisobot, «Xodimlar davomati» → oylik hisobot (A4, chop etish / PDF).
//   Ismli nusxa — Direktorda (davomat hisobotida HR'da ham); Moliya menejeri, buxgalter va kassirga — ismsiz: o'quvchi — ID, xodim —
//   maosh ID'si, fayl nomida / sarlavhada «-ismsiz», «Ismsiz nusxa (FD-28)» izohi; qolgan ustunlar (qatorma-qator) va jamlar Direktor
//   nusxasi bilan bir xil, har qatordagi ID — Direktor nusxasidagi o'sha shaxsniki (ism → maosh ID bazadan); davomat ro'yxatida yo'q
//   xodimning ruhsati ham maosh ID'si bilan; ekrandagi qarzdorlar ro'yxati ism bilan qoladi.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa17.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn (eski dizayn — v1 — 2026-11-24 da olib tashlangan)
const q = E.q;
const asUser = (uid, sql) => q(`begin; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', true); set local role authenticated; ${sql}; commit;`).split('\n').pop();
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
// CSV qatori (downloadCSV: vergul, qo'shtirnoq ichida vergul / qo'shtirnoq)
const csvRow = line => { const out = []; let cur = '', inQ = false;
  for (let i = 0; i < line.length; i++) { const c = line[i];
    if (inQ) { if (c === '"') { if (line[i + 1] === '"') { cur += '"'; i++; } else inQ = false; } else cur += c; }
    else if (c === '"') inQ = true; else if (c === ',') { out.push(cur); cur = ''; } else cur += c; }
  out.push(cur); return out; };
const NAMES = /sinov/i;   // urug'dagi barcha shaxs ismlari «Sinov …» (o'quvchi, xodim, foydalanuvchi; seans nomi «SINOV»)
(async () => {
  const b = await E.launch();
  const today = q('select app.fin_today()'); const mon = today.slice(0, 7);
  const ACC = 'u_acc_e17', HR = 'u_hr_e17';
  q(`insert into public.users (id, email, name, role, status, verified, "extraRoles") values
       ('${ACC}', 'buxgalter17@e2e.test', 'Sinov Buxgalter', 'accountant', 'active', true, '[]'),
       ('${HR}', 'kadrlar17@e2e.test', 'Sinov Kadrlar', 'hr', 'active', true, '[]')
     on conflict (id) do update set role = excluded.role, status = excluded.status, "extraRoles" = '[]'`);
  // kassa ishga tushgan (buxgalterga «Buxgalteriya» bo'limi faqat shunda)
  asUser(ids.R_DIR, `select public.fin_org_set('{"nameUz":"«SINOV MAKTAB» МЧЖ","t1":1000000,"l1":200000,"orgCashMax":1000000000,"kassaGoLive":"${today}"}'::jsonb)::text`);
  asUser(ids.R_DIR, `select public.kassa_opening_set('{"amount":1000000,"startDay":"${today}"}'::jsonb)::text`);
  // Urug'dagi ikki xodim (bazadan): qorovul S2 — davomat ro'yxatida («Kamera ID» bor), o'qituvchi T2 — ro'yxatda yo'q («Kamera ID»siz)
  const lit = v => `'${String(v).replace(/'/g, "''")}'`;
  const [s2Pid, s2Name, s2Cam] = q(`select coalesce(nullif("staffId", ''), id) || '|' || name || '|' || coalesce("cameraId", '') from public.staff where id = '${ids.S2}'`).split('|');
  const [t2Pid, t2Name, t2Cam] = q(`select coalesce(nullif("teacherId", ''), id) || '|' || name || '|' || coalesce("cameraId", '') from public.teachers where id = '${ids.T2}'`).split('|');
  // Sintetik ma'lumot (triggerlarsiz): berilgan maosh (qorovul), ruhsat (sababi bilan), davomat ro'yxatida yo'q o'qituvchining
  //   kasalligi, tasdiqlangan vedomost (tayyorladi / tasdiqladi)
  q(`set session_replication_role = replica;
     insert into public.salary_payments (id, "teacherId", "teacherName", month, gross, advance, net, paid, date)
       values ('e17-sal', ${lit(s2Pid)}, ${lit(s2Name)}, '${mon}', 3500000, 0, 3500000, 3500000, '${today}') on conflict (id) do nothing;
     insert into public.staff_leaves (id, "refId", "refType", "cameraId", name, type, "startDay", "endDay", reason, "createdBy")
       values ('e17-lv', '${ids.S2}', 'staff', ${lit(s2Cam)}, ${lit(s2Name)}, 'ruhsat', '${mon}-02', '${mon}-03', 'Sinov sabab: oilaviy', 'e2e'),
              ('e17-lv2', '${ids.T2}', 'teacher', '', ${lit(t2Name)}, 'kasallik', '${mon}-04', '${mon}-05', 'Sinov sabab: shamollash', 'e2e') on conflict (id) do nothing;
     insert into public.payroll_runs (id, status, "preparedBy", "preparedAt", "approvedBy", "approvedAt", totals)
       values ('${mon}', 'approved', '${ids.R_MOL}', now(), '${HR}', now(), '{"count":2,"payable":0}') on conflict (id) do nothing;
     set session_replication_role = origin;`);
  // urug'ga bog'liq qiymatlar — bazadan: qarzdorlar (shu oygacha), eng katta qarzdor, avansli o'quvchi, davomat ro'yxatidagi xodimlar
  const debtSql = `select "studentId" as sid, sum(greatest(0, amount - case when status = 'paid' then amount else coalesce("paidAmount", 0) end)) as d
                     from public.invoices where month <= '${mon}' and status not in ('canceled', 'reversed') group by "studentId"`;
  const [debtN, debtSum] = q(`select count(*) || '|' || coalesce(sum(d), 0)::bigint from (${debtSql}) x where d > 0`).split('|').map(Number);
  const topSid = q(`select sid from (${debtSql}) x where d > 0 order by d desc, sid limit 1`), topName = q(`select name from public.students where "studentId" = '${topSid}'`);
  const avSid = q(`select "studentId" from public.student_credit where credit > 0 order by "studentId" limit 1`), avName = q(`select name from public.students where "studentId" = '${avSid}'`);
  const staff = q(`select "staffId" || '|' || name || '|' || position from public.staff where coalesce("cameraId", '') <> '' order by "staffId"`).split('\n').map(x => x.split('|'));
  // ism → maosh ID (bazadan; admin.html saBuildRoster / payIdOf qoidasi: staffId || id, teacherId || id) — qatorma-qator solishtirishda
  //   Direktor nusxasidagi xodim ismi o'rniga shu kutilgan maosh ID qo'yiladi (pastda: rowsDiff)
  const PAY = {};
  q(`select name || '|' || coalesce(nullif("staffId", ''), id) from public.staff union all select name || '|' || coalesce(nullif("teacherId", ''), id) from public.teachers`)
    .split('\n').filter(Boolean).forEach(l => { const i = l.lastIndexOf('|'), n = l.slice(0, i); (PAY[n] = PAY[n] || []).push(l.slice(i + 1)); });
  const people = [...staff.map(x => x[1]), s2Name, t2Name];
  ok('tayyorlov: qarzdorlar, avansli o‘quvchi va kamera ID’li 2 xodim urug‘da bor, ruhsatli o‘qituvchi — «Kamera ID»siz; xodim ismlari takrorlanmaydi (ism → maosh ID)',
    debtN > 0 && debtSum > 0 && !!topName && !!avName && staff.length === 2 && !!s2Cam && !t2Cam && people.every(n => (PAY[n] || []).length === 1),
    { debtN, debtSum, topSid, avSid, staff, s2: [s2Pid, s2Name, s2Cam], t2: [t2Pid, t2Name, t2Cam], pay: people.map(n => [n, PAY[n]]) });

  async function login(uid) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 1440, height: 900 }, acceptDownloads: true });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage();
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => d.accept().catch(() => {}));
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(900);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 20000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const toasts = async () => pg.$$eval('#toasts .toast', xs => xs.map(x => x.textContent));
    const tabs = async () => pg.$$eval('#tabs button[data-tab]', xs => xs.map(x => x.dataset.tab));
    return { ctx, pg, tab, tabs, toasts };
  }
  // «Moliya» → «⬇ CSV» (qarzdorlar): fayl nomi va qatorlari
  async function debtCsv(u) {
    await u.tab('finance'); await u.pg.waitForSelector('#fin-debt-csv', { timeout: 30000 }); await u.pg.waitForTimeout(300);
    const [dl] = await Promise.all([u.pg.waitForEvent('download', { timeout: 15000 }), u.pg.click('#fin-debt-csv')]);
    const raw = fs.readFileSync(await dl.path(), 'utf8');
    return { nm: dl.suggestedFilename(), bom: raw.charCodeAt(0) === 0xFEFF, raw, rows: raw.replace(/^\uFEFF/, '').split(/\r\n/).filter(Boolean).map(csvRow) };
  }
  // chop etish (printHTML — yashirin iframe): sarlavha, matn va bo'laklar; KPI'dan boshqa jadvallar — oldingi h2, ustun sarlavhalari
  //   va tbody qatorlari (har qator — kataklar matni)
  async function printDoc(u, sel) {
    const n0 = await u.pg.evaluate(() => document.querySelectorAll('iframe').length);
    await u.pg.click(sel);
    await u.pg.waitForFunction(n => document.querySelectorAll('iframe').length > n, n0, { timeout: 15000 });
    await u.pg.waitForTimeout(700);
    return u.pg.evaluate(() => { const d = [...document.querySelectorAll('iframe')].pop().contentDocument; const tx = e => (e.innerText || e.textContent || '').replace(/\s+/g, ' ').trim(); const all = s => [...d.querySelectorAll(s)].map(tx);
      const h2of = t => { for (let e = t.previousElementSibling; e; e = e.previousElementSibling) if (e.tagName === 'H2') return tx(e); return ''; };
      // katak bo'laklari: asosiy matn (.sub izohisiz) va izoh — xodim katagida ism / maosh ID va «lavozim · ID N» / «kamera ID N»
      const parts = c => { const k = c.cloneNode(true); const sub = [...k.querySelectorAll('.sub')].map(x => { const v = tx(x); x.remove(); return v; }).join(' '); return [tx(k), sub]; };
      const tables = [...d.querySelectorAll('table')].filter(t => !t.classList.contains('kpi'))
        .map(t => { const trs = [...t.querySelectorAll('tbody tr')];
          return { h2: h2of(t), th: [...t.querySelectorAll('thead th')].map(tx), rows: trs.map(r => [...r.cells].map(tx)), parts: trs.map(r => [...r.cells].map(parts)) }; });
      return { title: d.title, text: tx(d.body), sub: all('.hd .sub').join(' | '), note: all('.fd28').join(' | '), kpi: all('table.kpi').join(' | '), h2: all('h2'), tfoot: all('tfoot').join(' | '), sign: all('.sign').join(' | '), th: all('th'), tables }; });
  }
  const accReport = async u => { await u.tab('accounting'); await u.pg.waitForSelector('#ac-report', { timeout: 30000 });
    await u.pg.waitForFunction(() => document.querySelector('#ac-body') && !document.querySelector('#ac-body .loading'), null, { timeout: 30000 }); await u.pg.waitForTimeout(500);
    return { card: await u.pg.$eval('#ac-body', e => e.innerText.slice(0, 400)), doc: await printDoc(u, '#ac-report') }; };
  const staffReport = async u => { await u.tab('staffatt'); await u.pg.waitForSelector('#sa-mode', { timeout: 20000 }); await u.pg.selectOption('#sa-mode', 'month');
    await u.pg.waitForSelector('#sa-pdf', { timeout: 30000 }); await u.pg.waitForTimeout(400); return printDoc(u, '#sa-pdf'); };
  const rest = r => r.slice(1).join('|');   // CSV qatori: ism / ID ustunidan keyingilar
  const staffIds = staff.map(s => s[0]), staffNames = staff.map(s => s[1]), positions = staff.map(s => s[2]);
  const has = (t, xs) => xs.every(x => t.includes(x)), none = (t, xs) => !xs.some(x => t.includes(x));
  // Qatorma-qator solishtirish: har jadval juftligi (hujjatdagi tartibda) — katak massivlarining tartiblangan to'plami. Direktor nusxasida
  //   «O‘quvchi» ustuni tashlanadi (o'quvchi ID — ikkala nusxada alohida «ID» ustunida) va «Sabab» (faqat ismli nusxada); «Xodim» katagi
  //   bazadagi maosh ID'siga almashtiriladi (PAY), ismsiz nusxada «Xodim (maosh ID)» katagi — o'zi; davomat jadvalida kamera ID ham
  //   (Direktorda «lavozim · ID N», ismsizda «kamera ID N»), «⏱ erkin» va «(N marta)» belgilari saqlanadi. Shunday qilib qaysi maosh ID
  //   (va kamera ID) qaysi qatorda turgani ham Direktor nusxasidagi o'sha xodimga qotiriladi (ruhsat jadvalida: №, maosh ID, tur, dan,
  //   gacha); to'liq bo'lmagan qator («Qarzdorlik yo‘q» kabi) o'zgarmaydi.
  const payId = nm => (PAY[nm] && PAY[nm].length === 1 ? PAY[nm][0] : `?${nm} (${(PAY[nm] || []).length} ta)`);
  const whoCell = ([m, s], named) => { const x = m.match(/^(.*?)( ⏱ erkin)?( \(\d+ marta\))?$/);
    const cam = !s ? '' : ((named ? s.match(/· ID (.+)$/) : s.match(/^kamera ID (.+)$/)) || [null, '?' + s])[1];
    return [named ? payId(x[1]) : x[1], x[2] ? 'erkin' : '', x[3] ? x[3].trim() : '', cam ? 'kamera ' + cam : ''].filter(Boolean).join(' · '); };
  const norm = (t, named) => t.rows.map((r, j) => (r.length !== t.th.length ? r : r.flatMap((c, i) => {
    if (named && (t.th[i] === 'O‘quvchi' || t.th[i] === 'Sabab')) return [];
    return t.th[i] === (named ? 'Xodim' : 'Xodim (maosh ID)') ? [whoCell(t.parts[j][i], named)] : [c]; })));
  const bag = rows => JSON.stringify(rows.map(r => JSON.stringify(r)).sort());
  const rowsDiff = (dd, id) => (dd.tables.length !== id.tables.length ? [{ jadvallar: [dd.tables.length, id.tables.length] }]
    : dd.tables.map((t, k) => ({ h2: t.h2, d: norm(t, true), i: norm(id.tables[k], false) })).filter(x => bag(x.d) !== bag(x.i)).map(x => ({ h2: x.h2, d: x.d.slice(0, 3), i: x.i.slice(0, 3) })));
  const fullRows = (doc, re) => { const t = doc.tables.find(x => re.test(x.h2)); return t ? t.rows.filter(r => r.length === t.th.length && r.length > 2).length : 0; };
  const lvCol = doc => { const t = doc.tables.find(x => /^Oydagi ruhsat/.test(x.h2)); return JSON.stringify(t ? t.rows.map(r => r[1]).sort() : []); };
  const LV_IDS = JSON.stringify([s2Pid, t2Pid].sort()), LV_NAMES = JSON.stringify([s2Name, t2Name].sort()), UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

  // ---------------- 1) Direktor: ismli nusxalar (o'zgarmagan)
  const d = await login(ids.R_DIR);
  const dc = await debtCsv(d);
  const dBody = dc.rows.slice(1), dSum = dBody.reduce((s, r) => s + Number(r[3] || 0), 0);
  ok('Direktor CSV: nomi qarzdorlar-<oy>.csv, sarlavha «O‘quvchi, Sinf, Qarz oylari, Qarz (so‘m)», izoh qatori yo‘q',
    dc.nm === `qarzdorlar-${mon}.csv` && dc.bom && dc.rows[0].join('|') === 'O‘quvchi|Sinf|Qarz oylari|Qarz (so‘m)' && !/FD-28/.test(dc.raw), [dc.nm, dc.rows.slice(0, 2)]);
  ok('Direktor CSV: barcha qarzdorlar ism bilan, jami bazadagi qarz bilan teng', dBody.length === debtN && dSum === debtSum && dBody.some(r => r[0] === topName) && dBody.every(r => NAMES.test(r[0])), { n: dBody.length, debtN, dSum, debtSum, first: dBody[0] });
  const da = await accReport(d);
  ok('Direktor A4 (Buxgalteriya): kartochka «Direktor hisoboti»; o‘quvchi (qarzdor, avans) va xodim ismlari bor, «ismsiz» belgisi yo‘q, imzo — Direktor',
    /Direktor hisoboti/.test(da.card) && has(da.doc.text, [topName, avName, s2Name]) && !/ismsiz/i.test(da.doc.text) && !da.doc.note && /^Direktor:/.test(da.doc.sign) && !/ismsiz/.test(da.doc.title),
    { card: da.card.slice(0, 120), title: da.doc.title, sign: da.doc.sign, text: da.doc.text.slice(0, 600) });
  const ds = await staffReport(d);
  ok('Direktor davomat hisoboti: xodim ismi, lavozimi, ruhsat sababi, vedomostni tayyorlagan va tasdiqlagan bor; «ismsiz» yo‘q',
    has(ds.text, [...staffNames, ...positions, 'Sinov sabab: oilaviy', 'Tayyorladi (Moliya menejeri): Sinov Moliyachi', 'Tasdiqladi (HR): Sinov Kadrlar']) && !/ismsiz/i.test(ds.text + ds.title) && !ds.note,
    { title: ds.title, sign: ds.sign, text: ds.text.slice(0, 700) });
  await d.ctx.close();

  // ---------------- 2) Moliya menejeri: ismsiz nusxalar; ekran — ism bilan
  const m = await login(ids.R_MOL);
  const mc = await debtCsv(m);
  const scr = await m.pg.$eval('#fin-body', e => e.innerText);
  ok('MM «Moliya» ekrani: qarzdorlar ro‘yxati ism bilan (ekran — fayl emas, o‘zgarmagan); CSV tugmasi izohida «ismsiz nusxa (FD-28)»',
    scr.includes(topName) && /ismsiz nusxa \(FD-28\)/.test(await m.pg.$eval('#fin-debt-csv', e => e.title)), [scr.slice(0, 300), await m.pg.$eval('#fin-debt-csv', e => e.title)]);
  const mBody = mc.rows.slice(2), mSum = mBody.reduce((s, r) => s + Number(r[3] || 0), 0);
  ok('MM CSV: nomi qarzdorlar-<oy>-ismsiz.csv; 1-qator — «Ismsiz nusxa (FD-28)» izohi, 2-qator — «O‘quvchi ID, Sinf, Qarz oylari, Qarz (so‘m)»',
    mc.nm === `qarzdorlar-${mon}-ismsiz.csv` && mc.bom && mc.rows[0].length === 1 && /^Ismsiz nusxa \(FD-28\): o‘quvchilar ID bilan; to‘liq nusxa — Direktorda$/.test(mc.rows[0][0]) && mc.rows[1].join('|') === 'O‘quvchi ID|Sinf|Qarz oylari|Qarz (so‘m)', [mc.nm, mc.rows.slice(0, 3)]);
  ok('MM CSV: hech bir shaxs ismi yo‘q, o‘quvchi ID’lari bor (eng katta qarzdor ham)', !NAMES.test(mc.raw) && mBody.some(r => r[0] === topSid) && mBody.every(r => /^IQ-\d{4}$/.test(r[0])), mBody.slice(0, 3));
  ok('MM CSV: qatorlar soni, sinf, oylar va qarz ustunlari Direktor nusxasi bilan bir xil (jami teng)',
    mBody.length === dBody.length && mSum === dSum && JSON.stringify(mBody.map(rest).sort()) === JSON.stringify(dBody.map(rest).sort()), { m: mBody.length, d: dBody.length, mSum, dSum });
  ok('MM CSV: «Saqlandi: ismsiz» xabari', (await m.toasts()).some(x => /Saqlandi: ismsiz/.test(x)), await m.toasts());
  const ma = await accReport(m);
  ok('MM A4: kartochka «Oylik hisobot (ismsiz)»', /Oylik hisobot \(ismsiz\)/.test(ma.card) && !/Direktor hisoboti/.test(ma.card), ma.card.slice(0, 200));
  ok('MM A4: o‘quvchi va xodim ismlari yo‘q (tuzgan xodim — lavozimi bilan, ism / email emas), ID va maosh ID bor',
    !NAMES.test(ma.doc.text) && !/@/.test(ma.doc.text) && has(ma.doc.text, [topSid, avSid, s2Pid]) && /Moliya menejeri/.test(ma.doc.sub), { sub: ma.doc.sub, text: ma.doc.text.slice(0, 700) });
  ok('MM A4: «Ismsiz nusxa (FD-28)» izohi, «ismsiz nusxa» belgisi, sarlavha «-ismsiz», ustun «Xodim (maosh ID)», imzo — Moliya menejeri',
    /^Ismsiz nusxa \(FD-28\): o‘quvchilar ID bilan, xodimlar maosh ID’si bilan; to‘liq nusxa — Direktorda$/.test(ma.doc.note) && /ismsiz nusxa/.test(ma.doc.sub) && /-ismsiz$/.test(ma.doc.title)
      && ma.doc.th.includes('Xodim (maosh ID)') && !ma.doc.th.includes('O‘quvchi') && /^Moliya menejeri:/.test(ma.doc.sign), { note: ma.doc.note, title: ma.doc.title, sign: ma.doc.sign, th: ma.doc.th });
  ok('MM A4: umumiy ko‘rsatkichlar va bo‘lim jamlari (qarz, avans, maosh) Direktor nusxasi bilan bir xil', ma.doc.kpi === da.doc.kpi && JSON.stringify(ma.doc.h2) === JSON.stringify(da.doc.h2), { m: [ma.doc.kpi, ma.doc.h2], d: [da.doc.kpi, da.doc.h2] });
  ok('MM A4: qarzdorlar, avans va maosh jadvallari (qolgan jadvallar ham) qatorma-qator Direktor nusxasi bilan bir xil — o‘quvchi ID va xodim maosh ID’si o‘sha qatorda (Direktor nusxasidagi ism → bazadagi maosh ID)',
    fullRows(da.doc, /^Qarzdorlar/) > 0 && fullRows(da.doc, /^Avans/) > 0 && fullRows(da.doc, /^Oylik maosh/) > 0 && rowsDiff(da.doc, ma.doc).length === 0,
    { diff: rowsDiff(da.doc, ma.doc), n: [fullRows(da.doc, /^Qarzdorlar/), fullRows(da.doc, /^Avans/), fullRows(da.doc, /^Oylik maosh/)] });
  const ms = await staffReport(m);
  ok('MM davomat hisoboti: xodim ismi, lavozimi, ruhsat sababi, tayyorlagan / tasdiqlagan ismi va email yo‘q; maosh ID’lari bor',
    !NAMES.test(ms.text) && none(ms.text, positions) && !/@/.test(ms.text) && has(ms.text, staffIds) && /Tayyorladi \(Moliya menejeri\) \(/.test(ms.sign) && /Tasdiqladi \(HR\) \(/.test(ms.sign), { sign: ms.sign, text: ms.text.slice(0, 700) });
  ok('MM davomat hisoboti: «Ismsiz nusxa (FD-28)» izohi (to‘liq nusxa — Direktor va HR’da), sarlavha «-ismsiz», ustun «Xodim (maosh ID)», «Sabab» ustuni yo‘q',
    /^Ismsiz nusxa \(FD-28\): xodimlar maosh ID’si bilan.*to‘liq nusxa — Direktor va HR’da$/.test(ms.note) && /-ismsiz$/.test(ms.title) && ms.th.includes('Xodim (maosh ID)') && !ms.th.includes('Sabab'), { note: ms.note, title: ms.title, th: ms.th });
  ok('MM davomat hisoboti: JAMI qatori Direktor nusxasi bilan bir xil', !!ms.tfoot && ms.tfoot === ds.tfoot, { m: ms.tfoot, d: ds.tfoot });
  ok('MM davomat hisoboti: xodimlar va ruhsat / kasallik jadvallari qatorma-qator Direktor nusxasi bilan bir xil — har qatorda o‘sha xodimning maosh ID’si (va kamera ID’si; ruhsatda — maosh ID, tur, dan, gacha), Direktor nusxasidagi ism → bazadagi maosh ID, «Sabab»siz',
    fullRows(ds, /^$/) === staff.length && fullRows(ds, /^Oydagi ruhsat/) === 2 && rowsDiff(ds, ms).length === 0,
    { diff: rowsDiff(ds, ms), n: [fullRows(ds, /^$/), fullRows(ds, /^Oydagi ruhsat/)] });
  ok('MM davomat hisoboti: ruhsat / kasallik ro‘yxatida xodim — maosh ID’si bilan, davomat ro‘yxatida yo‘q («Kamera ID»siz) o‘qituvchi ham; ichki qator id yo‘q (Direktor nusxasida — ism)',
    lvCol(ms) === LV_IDS && !UUID.test(ms.text) && lvCol(ds) === LV_NAMES, { m: lvCol(ms), d: lvCol(ds), uuid: (ms.text.match(UUID) || [])[0] });
  await m.ctx.close();

  // ---------------- 3) Buxgalter: A4 — ismsiz
  const a = await login(ACC);
  await a.pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length >= 4, null, { timeout: 20000 }).catch(() => {});
  const at = await a.tabs();
  ok('buxgalter: «Moliya» (qarzdorlar CSV) va «Xodimlar davomati» bo‘limlari yo‘q — bu fayllar unga umuman chiqmaydi', at.includes('accounting') && !at.includes('finance') && !at.includes('staffatt'), at);
  const aa = await accReport(a);
  ok('buxgalter A4: ismlar yo‘q, ID va maosh ID bor, FD-28 izohi, imzo — Buxgalter, jamlar Direktor nusxasi bilan bir xil',
    !NAMES.test(aa.doc.text) && has(aa.doc.text, [topSid, avSid, s2Pid]) && /^Ismsiz nusxa \(FD-28\)/.test(aa.doc.note) && /^Buxgalter:/.test(aa.doc.sign) && /-ismsiz$/.test(aa.doc.title)
      && aa.doc.kpi === da.doc.kpi && JSON.stringify(aa.doc.h2) === JSON.stringify(da.doc.h2), { note: aa.doc.note, sign: aa.doc.sign, kpi: aa.doc.kpi, h2: aa.doc.h2, text: aa.doc.text.slice(0, 500) });
  ok('buxgalter A4: qarzdorlar, avans va maosh jadvallari qatorma-qator Direktor nusxasi bilan bir xil — o‘quvchi ID va xodim maosh ID’si o‘sha qatorda (ism → bazadagi maosh ID)', rowsDiff(da.doc, aa.doc).length === 0, rowsDiff(da.doc, aa.doc));
  await a.ctx.close();

  // ---------------- 4) Kassir: davomat hisoboti — ismsiz (o'z ismi ham chiqmaydi)
  const k = await login(ids.R_KAS);
  const ks = await staffReport(k);
  ok('kassir davomat hisoboti: ismsiz (o‘z ismi ham yo‘q), maosh ID’lari, FD-28 izohi, jamlar Direktor nusxasi bilan bir xil',
    !NAMES.test(ks.text) && has(ks.text, staffIds) && /^Ismsiz nusxa \(FD-28\)/.test(ks.note) && /-ismsiz$/.test(ks.title) && ks.tfoot === ds.tfoot, { note: ks.note, title: ks.title, text: ks.text.slice(0, 500) });
  ok('kassir davomat hisoboti: jadvallar qatorma-qator Direktor nusxasi bilan bir xil (har qatorda o‘sha xodimning maosh ID’si va kamera ID’si), ruhsat / kasallik — maosh ID’si bilan',
    rowsDiff(ds, ks).length === 0 && lvCol(ks) === LV_IDS && !UUID.test(ks.text), { diff: rowsDiff(ds, ks), lv: lvCol(ks) });
  await k.ctx.close();

  // ---------------- 5) HR: davomat hisoboti — ismli (xodimlar hisobini yuritadi)
  const h = await login(HR);
  const hs = await staffReport(h);
  ok('HR davomat hisoboti: ismli (xodim ismi, ruhsat sababi), «ismsiz» yo‘q, jamlar va jadvallar Direktor nusxasi bilan bir xil',
    has(hs.text, [...staffNames, 'Sinov sabab: oilaviy']) && !/ismsiz/i.test(hs.text + hs.title) && hs.tfoot === ds.tfoot && JSON.stringify(hs.tables) === JSON.stringify(ds.tables),
    { title: hs.title, text: hs.text.slice(0, 500), diff: ds.tables.map((t, k) => (JSON.stringify(t) === JSON.stringify(hs.tables[k]) ? null : t.h2)).filter(x => x !== null) });
  await h.ctx.close();

  ok('sahifa xatosi yo‘q', allErrs.length === 0, allErrs.slice(0, 3));
  console.log(`JAMI (${UI}): ${res.filter(r => r.ok).length}/${res.length}`);
  await b.close();
  process.exit(res.every(r => r.ok) ? 0 : 1);
})().catch(e => { console.error('XATO', e); process.exit(2); });
