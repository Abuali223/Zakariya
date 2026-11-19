// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): O'QUVCHILAR ARXIVI (egasi 2026-11-18:
//   «chiqarishni bossa o'quvchi soni kamaymay turibdi; chiqarilsa yoki maktabni tugatsa arxivga o'tishi kerak; boshqa maktab ma'lumot
//   so'rasa yubora olish uchun»). Urug'da 17 o'quvchi: IQ-0016 — muzlatilgan, IQ-0017 — o'tgan oy chiqib ketgan (arxivda).
//   Direktor: «O‘quvchilar» jami va sinf kartasi faol ro'yxatdan; qidiruvda arxivga havola; ⏯️ «Chiqarish» — son darhol kamayadi;
//   kelajak sana — «⏳ Chiqadi» bilan ro'yxatda qoladi; bosh sahifa soni; «🗄 Arxiv» (filtrlar, yig'ma); 📨 Ma'lumotnoma (QR 'certificate',
//   telefon / to'lovsiz); 🎓 Bitiruv (ommaviy); ↩️ qaytarish; jurnallar (baho — shu o'quv yilida chiqqanlar belgi bilan, monitoring —
//   oldingi oyda chiqqan yo'q). Qabulxona: ⏹️ chiqarish → arxiv, 📨 ma'lumotnoma (baho / davomat — student_certificate orqali; qabulxona
//   jadvallarni o'zi o'qiy olmaydi; 📄 ichki ma'lumotnoma va «🖨 Ichki hisobot» ham shu yig'madan), Arxivda ↩️ / 🎓 / CSV yo'q.
//   O'IBDO': menyuda «Arxiv». Kassir: ro'yxat soni (students_billing),
//   qidiruvda arxivdagi o'quvchi haqida eslatma (havolasiz).
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-arxiv.cjs [v1|v2]
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = process.argv[2] === 'v1' ? 'v1' : 'v2';
const q = E.q;
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const st = id => q(`select coalesce("payStatus",'') || '|' || coalesce("exitReason",'') || '|' || coalesce("exitAt",'') || '|' || coalesce("stopFrom",'') from public.students where id='${id}'`);
(async () => {
  const b = await E.launch();
  async function login(uid) {
    const email = q(`select email from public.users where id='${uid}'`);
    const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 1440, height: 900 } });
    await ctx.addInitScript(([k, v, ui]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5 * 365)); } catch (e) {} },
      ['sb-127-auth-token', JSON.stringify(session(uid, email, { displayName: 'SINOV' })), UI]);
    const pg = await ctx.newPage();
    pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
    pg.on('dialog', d => d.accept().catch(() => {}));   // tasdiqlar (chiqarish, bitiruv) va «fakturalar yangilanmaydi» eslatmasi — ha / OK
    await pg.goto(E.BASE + '/admin.html');
    await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
    await pg.waitForTimeout(700);
    const tab = async k => { await pg.waitForSelector(`#tabs button[data-tab="${k}"]`, { state: 'attached', timeout: 20000 }); await pg.$eval(`#tabs button[data-tab="${k}"]`, x => x.click()); };
    const modalGone = async () => pg.waitForFunction(() => !document.querySelector('#modal-bg').classList.contains('show'), null, { timeout: 15000 });
    const students = async () => { await tab('students'); await pg.waitForFunction(() => /Jami: \d+/.test((document.querySelector('#stu-total') || {}).textContent || ''), null, { timeout: 20000 }); await pg.waitForTimeout(400); };
    const total = async () => Number(((await pg.textContent('#stu-total')) || '').replace(/\D+/g, '')) || -1;
    const listed = async id => pg.evaluate(i => [...document.querySelectorAll('#cls-groups td[data-label="ID"]')].some(td => td.textContent.trim() === i), id);
    const archive = async () => { await pg.click('#stu-arch'); await pg.waitForSelector('#ar-list table, #ar-list .empty', { timeout: 20000 }); await pg.waitForTimeout(500); };
    const arRows = async () => pg.evaluate(() => [...document.querySelectorAll('#ar-list tbody tr')].map(tr => (tr.querySelector('td[data-label="O‘quvchi"] .small') || {}).textContent || ''));
    const printOf = async sel => { const n0 = await pg.evaluate(() => document.querySelectorAll('iframe').length); await pg.click(sel);
      await pg.waitForFunction(n => document.querySelectorAll('iframe').length > n, n0, { timeout: 15000 }); await pg.waitForTimeout(700);
      return pg.evaluate(() => { const f = [...document.querySelectorAll('iframe')].pop(); try { return { text: f.contentDocument.body.innerText.replace(/\s+/g, ' '), qr: !!f.contentDocument.querySelector('img[alt="QR"]') }; } catch (e) { return { text: '', qr: false }; } }); };
    return { ctx, pg, tab, modalGone, students, total, listed, archive, arRows, printOf };
  }

  // ===================== DIREKTOR =====================
  const D = await login(ids.R_DIR); const pg = D.pg;
  const today = new Date(Date.now() + 5 * 3600e3).toISOString().slice(0, 10);   // Toshkent kuni (sahifadagi tkDay bilan bir xil)
  const plusDays = n => { const d = new Date(today + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
  // o'zlashtirish ma'lumoti (urug'da yo'q): IQ-0001 va IQ-0003 — baho, davomat (bemor jami kunga kirmaydi), xarakteristika
  const Y = Number(today.slice(0, 4)), AY = Number(today.slice(5, 7)) >= 9 ? `${Y}-${Y + 1}` : `${Y - 1}-${Y}`, M0 = today.slice(0, 7);
  q(`insert into public.grades (id,"studentId","classKey",year,subjects) values ('IQ-0001__${AY}','IQ-0001','uz-4-A','${AY}','{"Matematika":{"q1":5,"q2":4}}'),('IQ-0003__${AY}','IQ-0003','uz-4-A','${AY}','{"Ona tili":{"q1":4}}') on conflict (id) do update set subjects = excluded.subjects`);
  q(`insert into public.attendance (id,"studentId","classKey",month,days) values ('IQ-0001__${M0}','IQ-0001','uz-4-A','${M0}','{"01":"present","02":"late","03":"absent","04":"sick"}'),('IQ-0003__${M0}','IQ-0003','uz-4-A','${M0}','{"01":"present","02":"present"}') on conflict (id) do update set days = excluded.days`);
  q(`insert into public.characteristics (id,"studentId","classKey",year,quarter,term,text) values ('IQ-0003__${AY}-q1','IQ-0003','uz-4-A','${AY}','q1','${AY}-q1','Sinov xarakteristika matni') on conflict (id) do update set text = excluded.text`);
  await D.students();
  ok('O‘quvchilar: jami — faol ro‘yxat (17 dan arxivdagi IQ-0017 siz = 16); «🗄 Arxiv (1)»; IQ-0017 ro‘yxatda yo‘q, muzlatilgan IQ-0016 bor',
    (await D.total()) === 16 && /Arxiv \(1\)/.test(await pg.textContent('#stu-arch')) && !(await D.listed('IQ-0017')) && (await D.listed('IQ-0016')),
    [await D.total(), await pg.textContent('#stu-arch')]);
  const card7 = await pg.evaluate(() => { const c = [...document.querySelectorAll('#cls-groups .cls-card')].find(x => /7-sinf/.test(x.querySelector('h3').textContent) && /«A»/.test(x.querySelector('h3').textContent)); return c ? c.querySelector('.cls-count').textContent : ''; });
  ok('sinf kartasi 7-«A»: «2 o‘quvchi» (chiqib ketgan IQ-0017 hisoblanmaydi)', /^2 o‘quvchi/.test(card7), card7);
  // qidiruv: arxivdagi o'quvchi ro'yxatga qo'shilmaydi — havola bilan
  await pg.fill('#stu-search', '0017'); await pg.dispatchEvent('#stu-search', 'input'); await pg.waitForTimeout(500);
  const hint = await pg.evaluate(() => { const b = document.querySelector('#stu-arch-hit'); return b ? b.closest('.card').textContent.replace(/\s+/g, ' ') : ''; });
  ok('qidiruv «0017»: ro‘yxatda yo‘q, «🗄 Arxivda yana 1 ta mos o‘quvchi bor» havolasi', /Arxivda yana 1 ta/.test(hint) && !(await D.listed('IQ-0017')), hint);
  await pg.click('#stu-arch-hit'); await pg.waitForSelector('#ar-list table', { timeout: 15000 }); await pg.waitForTimeout(400);
  ok('«Arxivda ko‘rish»: Arxiv sahifasi qidiruv bilan ochildi — IQ-0017', (await pg.inputValue('#ar-q')) === '0017' && JSON.stringify(await D.arRows()) === '["IQ-0017"]', await D.arRows());

  // ⏯️ Chiqarish (bugun) — son darhol kamayadi
  await D.students(); await pg.fill('#stu-search', ''); await pg.dispatchEvent('#stu-search', 'input'); await pg.waitForTimeout(300);
  await pg.click('[data-status="IQ-0001"]'); await pg.waitForSelector('#st-sel', { timeout: 10000 });
  await pg.selectOption('#st-sel', 'chiqdi'); await pg.fill('#st-date', today); await pg.selectOption('#st-exit-r', 'boshqa_maktab'); await pg.fill('#st-exit-n', 'Sinov: ko‘chish');
  await pg.click('#st-save'); await D.modalGone(); await pg.waitForTimeout(1500);
  await D.students();
  ok('⏯️ «Chiqarish» bugungi sana bilan: jami 16 → 15, IQ-0001 ro‘yxatdan chiqdi, «🗄 Arxiv (2)»; bazada chiqdi | boshqa_maktab | bugun',
    (await D.total()) === 15 && !(await D.listed('IQ-0001')) && /Arxiv \(2\)/.test(await pg.textContent('#stu-arch')) && st('IQ-0001') === `chiqdi|boshqa_maktab|${today}|${today}`,
    [await D.total(), st('IQ-0001')]);
  // kelajak sana — shu kungacha ro'yxatda «⏳ Chiqadi»
  await pg.click('[data-status="IQ-0002"]'); await pg.waitForSelector('#st-sel', { timeout: 10000 });
  await pg.selectOption('#st-sel', 'chiqdi'); await pg.fill('#st-date', plusDays(10)); await pg.selectOption('#st-exit-r', 'kochdi');
  await pg.click('#st-save'); await D.modalGone(); await pg.waitForTimeout(1500); await D.students();
  const chip2 = await pg.evaluate(() => { const td = [...document.querySelectorAll('#cls-groups td[data-label="ID"]')].find(x => x.textContent.trim() === 'IQ-0002'); return td ? td.parentElement.querySelector('td[data-label="Ism"]').textContent : ''; });
  ok('kelajak sana bilan chiqarilgan IQ-0002: ro‘yxatda qoladi («⏳ Chiqadi»), jami 15', (await D.total()) === 15 && /⏳ Chiqadi/.test(chip2), [await D.total(), chip2]);

  // bosh sahifa — faol ro'yxat soni
  await D.tab('dashboard'); await pg.waitForTimeout(2500);
  const dashN = await pg.evaluate(ui => {
    if (ui === 'v1') { const c = [...document.querySelectorAll('#dash .stat-card')].find(x => /O‘quvchi$/.test(x.textContent.trim())); return c ? c.querySelector('b').textContent : ''; }
    const card = [...document.querySelectorAll('.dv2-card')].find(x => { const h = x.querySelector('.dv2-h h3'); return h && h.textContent.trim() === 'O‘quvchilar'; });
    return card ? (card.querySelector('.dv2-num') || {}).textContent || '' : ''; }, UI);
  ok(`bosh sahifa (${UI}): «O‘quvchi» soni 15 (arxivdagi 2 tasi hisoblanmaydi)`, String(dashN).replace(/\D+/g, '').startsWith('15'), dashN);

  // 🗄 Arxiv sahifasi — ro'yxat, filtrlar, yig'ma
  await D.students(); await D.archive();
  const rows1 = await D.arRows(), sum1 = (await pg.textContent('#ar-sum')).replace(/\s+/g, ' ');
  ok('Arxiv: 2 ta (IQ-0001 bugun, IQ-0017 o‘tgan oy) — yangi chiqqan birinchi; yig‘mada «chiqarilgan: 2 · 🎓 bitirgan: 0» va sabablar',
    JSON.stringify(rows1) === '["IQ-0001","IQ-0017"]' && /chiqarilgan: 2/.test(sum1) && /bitirgan: 0/.test(sum1) && /Boshqa maktabga o‘tdi: 1/.test(sum1), [rows1, sum1]);
  ok('Arxiv tugmalari (direktor): 🎓 Bitiruv, ⬇ CSV, ↩️ va 📨 Ma’lumotnoma bor', !!(await pg.$('#ar-grad')) && !!(await pg.$('#ar-csv')) && !!(await pg.$('[data-arback="IQ-0001"]')) && !!(await pg.$('[data-arcert="IQ-0001"]')));
  await pg.selectOption('#ar-type', 'grad'); await pg.waitForTimeout(300);
  const emptyG = await pg.textContent('#ar-list');
  await pg.selectOption('#ar-type', ''); await pg.waitForTimeout(300);
  ok('filtr «🎓 Bitiruvchilar»: hozircha bo‘sh', /topilmadi/.test(emptyG), emptyG);

  // 📨 Ma'lumotnoma — QR 'certificate', telefon / to'lov ma'lumotisiz
  await pg.click('[data-arcert="IQ-0001"]'); await pg.waitForSelector('#rep-tr', { state: 'visible', timeout: 20000 });
  await pg.fill('#tr-ord', '45-o‘'); await pg.fill('#tr-to', 'Sinov 12-maktab');
  const pr = await D.printOf('#tr-print');
  const phone1 = q(`select "parentPhone" from public.student_private where id='IQ-0001'`);
  ok('📨 Ma’lumotnoma: «O‘QUVCHI HAQIDA MA’LUMOTNOMA», «boshqa ta’lim muassasasiga», ism, holat «O‘qishdan chiqqan», buyruq va manzil, baho va davomat (jami 3 kun); QR bor',
    /O‘QUVCHI HAQIDA MA’LUMOTNOMA/.test(pr.text) && /boshqa ta’lim muassasasiga/.test(pr.text) && /Sinov O‘quvchi 0001/.test(pr.text) && /O‘qishdan chiqqan/.test(pr.text)
    && /№ 45-o‘/.test(pr.text) && /Sinov 12-maktab/.test(pr.text) && /Matematika 5 4/.test(pr.text) && /jami 3 kun/.test(pr.text) && pr.qr, pr.text.slice(0, 900));
  ok('📨 Ma’lumotnomada ichki ketish sababi yozilmaydi («Boshqa maktabga o‘tdi» — yo‘q; izoh ham yo‘q)', !/Boshqa maktabga o‘tdi|Sinov: ko‘chish/.test(pr.text), pr.text.slice(0, 600));
  ok('📨 Ma’lumotnomada telefon raqami, to‘lov (summa / qarz) va sog‘liq yo‘q', !!phone1 && !pr.text.includes(phone1) && !/Jami to‘langan|Qarz|To‘lovlar|Sog‘liq holati/.test(pr.text), pr.text.slice(0, 400));
  ok('QR — issued_documents: IQ-0001 uchun «certificate» bitta', q(`select count(*) from public.issued_documents where "studentDoc"='IQ-0001' and kind='certificate' and "revokedAt" is null`) === '1');
  await pg.click('#m-x'); await D.modalGone();

  // 🎓 Bitiruv — 9-«IT» (IQ-0013, IQ-0014) bugungi sana bilan
  await pg.click('#ar-grad'); await pg.waitForSelector('#gr-cls', { timeout: 10000 });
  await pg.evaluate(() => document.querySelectorAll('#gr-cls [data-grk]').forEach(c => { c.checked = (c.dataset.grk === 'uz-9-IT'); c.dispatchEvent(new Event('change', { bubbles: true })); }));
  const totG = await pg.textContent('#gr-tot');
  await pg.fill('#gr-dt', today); await pg.fill('#gr-note', 'Sinov bitiruvchisi');
  await pg.click('#gr-go'); await D.modalGone(); await pg.waitForTimeout(2500);
  ok('🎓 Bitiruv: «Jami: 2 ta o‘quvchi»; IQ-0013 va IQ-0014 — chiqdi | bitirdi | bugun', /Jami: 2/.test(totG) && st('IQ-0013') === `chiqdi|bitirdi|${today}|${today}` && st('IQ-0014') === `chiqdi|bitirdi|${today}|${today}`,
    [totG, st('IQ-0013'), st('IQ-0014')]);
  await pg.waitForSelector('#ar-list table', { timeout: 15000 }); await pg.selectOption('#ar-type', 'grad'); await pg.waitForTimeout(400);
  const rowsG = await D.arRows();
  ok('Arxiv «🎓 Bitiruvchilar»: IQ-0013, IQ-0014; jami 4', JSON.stringify(rowsG.slice().sort()) === '["IQ-0013","IQ-0014"]' && /4 ta/.test(await pg.textContent('#ar-total')), [rowsG, await pg.textContent('#ar-total')]);
  await pg.selectOption('#ar-type', ''); await pg.waitForTimeout(300);

  // jurnallar: baho — shu o'quv yilida chiqqan/bitirgan belgi bilan; monitoring — oldingi oyda chiqqan IQ-0017 yo'q
  await D.tab('grades'); await pg.waitForSelector('#gr-class', { timeout: 15000 });
  const subj = await pg.evaluate(() => { const s = document.querySelector('#gr-subject'); if (!s) return ''; if (s.tagName === 'SELECT') { const o = [...s.options].find(x => x.value); return o ? o.value : ''; } return 'Matematika'; });
  const setSubj = async sel => { await pg.evaluate(([sel, v]) => { const s = document.querySelector(sel); if (s.tagName === 'SELECT') s.value = v; else s.value = v; s.dispatchEvent(new Event('change', { bubbles: true })); s.dispatchEvent(new Event('input', { bubbles: true })); }, [sel, subj]); };
  await pg.selectOption('#gr-class', 'uz-7-A'); await setSubj('#gr-subject'); await pg.selectOption('#gr-quarter', 'q1'); await pg.waitForTimeout(1500);
  const grTxt = (await pg.textContent('#gr-body')).replace(/\s+/g, ' ');
  ok('Baholar 7-«A»: o‘tgan oy chiqqan IQ-0017 shu o‘quv yili ro‘yxatida «Chiqdi» belgisi bilan', /Sinov O‘quvchi 0017\s*Chiqdi/.test(grTxt), grTxt.slice(0, 300));
  await D.tab('monitoring'); await pg.waitForSelector('#mon-class', { timeout: 15000 });
  await pg.selectOption('#mon-class', 'uz-7-A'); await setSubj('#mon-subject'); await pg.waitForTimeout(1500);
  const monTxt = (await pg.textContent('#mon-body')).replace(/\s+/g, ' ');
  ok('Monitoring (joriy oy) 7-«A»: o‘tgan oy chiqqan IQ-0017 yo‘q; «2 o‘quvchi»', !/0017/.test(monTxt) && /2 o‘quvchi/.test(monTxt), monTxt.slice(0, 300));

  // ↩️ Qaytarish (direktor) — IQ-0001 qayta faollashtiriladi
  await D.students(); await D.archive();
  await pg.click('[data-arback="IQ-0001"]'); await pg.waitForSelector('#st-sel', { timeout: 10000 });
  const defSel = await pg.inputValue('#st-sel'); await pg.fill('#st-date', today);
  await pg.click('#st-save'); await D.modalGone(); await pg.waitForTimeout(1500);
  await pg.waitForSelector('#ar-list table', { timeout: 15000 }); await pg.waitForTimeout(400);
  ok('↩️ Qaytarish: oynada «Faollashtirish» tanlangan; IQ-0001 faol, sababi tozalandi; Arxivda 3 ta', defSel === 'faol' && /^faol\|\|/.test(st('IQ-0001')) && !(await D.arRows()).includes('IQ-0001') && /3 ta/.test(await pg.textContent('#ar-total')),
    [defSel, st('IQ-0001'), await D.arRows()]);
  await D.ctx.close();

  // ===================== QABULXONA =====================
  const R = await login(ids.R_REC); const rp = R.pg;
  await R.students();
  const t0 = await R.total();
  ok('qabulxona: jami faol ro‘yxat (17 − IQ-0017, IQ-0013, IQ-0014 = 14), «🗄 Arxiv (3)»', t0 === 14 && /Arxiv \(3\)/.test(await rp.textContent('#stu-arch')), [t0, await rp.textContent('#stu-arch')]);
  await rp.click('[data-withdraw="IQ-0003"]'); await rp.waitForSelector('#st-exit-r', { timeout: 10000 });
  await rp.fill('#st-date', today); await rp.selectOption('#st-exit-r', 'kochdi');
  await rp.click('#st-save'); await R.modalGone(); await rp.waitForTimeout(1500); await R.students();
  ok('qabulxona ⏹️ «Chiqarish»: IQ-0003 arxivga o‘tdi — jami 13, ro‘yxatda yo‘q', (await R.total()) === 13 && !(await R.listed('IQ-0003')) && /^chiqdi\|kochdi\|/.test(st('IQ-0003')), [await R.total(), st('IQ-0003')]);
  await R.archive();
  ok('qabulxona Arxivi: 4 ta; 📨 Ma’lumotnoma bor; ↩️, 🎓 Bitiruv va CSV yo‘q',
    (await R.arRows()).length === 4 && !!(await rp.$('[data-arcert="IQ-0003"]')) && !(await rp.$('[data-arback]')) && !(await rp.$('#ar-grad')) && !(await rp.$('#ar-csv')), await R.arRows());
  await rp.click('[data-arcert="IQ-0003"]'); await rp.waitForSelector('#rep-tr', { state: 'visible', timeout: 20000 });
  // A3-04 qoldig'i: qabulxona jadvallarni o'zi o'qiy olmaydi — ichki ma'lumotnoma (oyna va «🖨 Ichki hisobot») o'zlashtirish bo'limlarini
  //   student_certificate yig'masidan oladi (avval «Umumiy davomat —», «0 / 0 / 0», baho va xarakteristika «yo'q» deb chiqardi);
  //   yig'mada yo'q oylik xulosa — «Qabulxona uchun ko'rsatilmaydi».
  const secR = await rp.evaluate(() => { const o = {}; document.querySelectorAll('#rep-inner h4.rep-h').forEach(h => { let t = '', n = h.nextElementSibling;
    while (n && n.tagName !== 'H4') { t += ' ' + n.textContent; n = n.nextElementSibling; } o[h.textContent.trim().split(' ')[0]] = t.replace(/\s+/g, ' ').trim(); }); return o; });
  ok('qabulxona ichki ma’lumotnomasi (oyna): davomat 100% (2 kun), «Ona tili» 4, xarakteristika — yig‘madan; oylik xulosa «ko‘rsatilmaydi»',
    /Umumiy davomat ?100%/.test(secR.Davomat) && /2 \/ 0 \/ 0 \(jami 2 kun\)/.test(secR.Davomat) && /Ona tili ?4/.test(secR.Baholar) && !/Ma’lumot yo‘q/.test(secR.Baholar)
      && /Sinov xarakteristika matni/.test(secR.Xarakteristika) && /Qabulxona uchun ko‘rsatilmaydi\./.test(secR['O‘qituvchi']), secR);
  const ichR = await R.printOf('#rep-print');
  ok('qabulxona «🖨 Ichki hisobot»: davomat, baho, xarakteristika chop etiladi; oylik xulosa «ko‘rsatilmaydi»',
    /Umumiy davomat ?100%/.test(ichR.text) && /Ona tili ?4/.test(ichR.text) && /Sinov xarakteristika matni/.test(ichR.text) && /Qabulxona uchun ko‘rsatilmaydi\./.test(ichR.text), ichR.text.slice(0, 900));
  const prR = await R.printOf('#tr-print');
  ok('qabulxona 📨 Ma’lumotnomasi: baho («Ona tili 4»), davomat (jami 2 kun) va xarakteristika bor (student_certificate orqali); QR bor',
    /Sinov O‘quvchi 0003/.test(prR.text) && /Ona tili 4/.test(prR.text) && /jami 2 kun/.test(prR.text) && /Sinov xarakteristika matni/.test(prR.text) && prR.qr, prR.text.slice(0, 900));
  ok('QR — IQ-0003 uchun «certificate» qabulxona nomidan', q(`select count(*) from public.issued_documents where "studentDoc"='IQ-0003' and kind='certificate' and "issuedBy"='${ids.R_REC}'`) === '1');
  await rp.click('#m-x'); await R.modalGone();
  await R.ctx.close();

  // ===================== O'IBDO' (menyuda «Arxiv») =====================
  const Z = await login(ids.R_ZAV); const zp = Z.pg;
  await Z.tab('archive'); await zp.waitForSelector('#ar-list table', { timeout: 20000 }); await zp.waitForTimeout(400);
  ok('O‘IBDO‘: menyuda «Arxiv» — 4 ta; 📨 Ma’lumotnoma bor; ↩️ / 🎓 / CSV va «← O‘quvchilar» yo‘q',
    (await Z.arRows()).length === 4 && !!(await zp.$('[data-arcert="IQ-0003"]')) && !(await zp.$('[data-arback]')) && !(await zp.$('#ar-grad')) && !(await zp.$('#ar-back')), await Z.arRows());
  await Z.ctx.close();

  // ===================== KASSIR (students_billing) =====================
  const K = await login(ids.R_KAS); const kp = K.pg;
  await K.students();
  ok('kassir: «O‘quvchilar» jami ham faol ro‘yxat (13; students_billing — chiqqan kun bilan)', (await K.total()) === 13, await K.total());
  await kp.fill('#stu-search', '0017'); await kp.dispatchEvent('#stu-search', 'input'); await kp.waitForTimeout(500);
  const kNote = (await kp.textContent('#cls-groups')).replace(/\s+/g, ' ');
  ok('kassir qidiruvi «0017»: arxivdagi o‘quvchi haqida eslatma («To‘lovlar»da qidiring), arxiv havolasi yo‘q', /arxivda/.test(kNote) && /To‘lovlar/.test(kNote) && !(await kp.$('#stu-arch-hit')), kNote.slice(0, 300));
  await K.ctx.close();

  ok('sahifa xatolari yo‘q', allErrs.length === 0, allErrs.slice(0, 5));
  await b.close();
  const f = res.filter(x => !x.ok).length;
  console.log(`\nJAMI: ${res.length - f}/${res.length} PASS (${UI})`);
  process.exit(f ? 1 : 0);
})().catch(e => { console.error('XATO', e); process.exit(1); });
