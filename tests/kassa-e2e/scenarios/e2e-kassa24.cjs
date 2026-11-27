// LOCAL ONLY (lokal stend — tests/kassa-e2e/README.md; sintetik ma'lumot, «--dev» zanjiri): F2.7 — hisob-faktura TARKIBI (yalpi summa va
//   chegirma turlari) brauzerda, haqiqiy «To'lovlar» tugmalari bilan. Joriy oy — eski qoidalar (stend urug'ida tasdiq talablari keyingi oydan).
//   Tayyorgarlik (bazada, tizim nomidan): joriy oyning 5 ta to'lanmagan fakturasi o'chiriladi; o'quvchilar maxfiy kartasida — xodim farzandi
//   (IQ-0003), olimpiada granti va oy o'rtasida kelgan (IQ-0006), kontrakt summasi (IQ-0009) va uni tavsiya qilgan o'quvchi (IQ-0012 → IQ-0009),
//   o'tgan oy davomatida 2 «Bemor» kuni (IQ-0012); IQ-0015 — chegirmasiz.
//   1) Direktor: «Hisob-fakturalar yaratish» — 5 ta faktura; sahifa har fakturaga yalpi va tarkibni YUBORGAN (so'rov tanasi) va baza aynan
//      shuni saqlagan; turlar: xodim farzandi 50 %, grant (qisman oy — yalpi = ulush, summa 0), tavsiya (kontrakt), kasal kun, chegirmasiz;
//      har faktura: summa = yalpi − Σ qismlar; tavsiya jurnali.
//   2) Faktura qatori izohida tarkib («Yalpi … · xodim farzandi −…»).
//   3) IQ-0015 ga xodim farzandi toifasi → «↻ Qayta hisoblash»: reprice_invoice meta da tarkib, baza yangi tarkibni saqlagan; tarkibi o'zgarmagan
//      yangi fakturalar qayta yozilmagan (bazadan o'qilgan tarkib hisoblangan bilan bir xil deb topilgan).
//   4) Sahifa xatolari yo'q.
//   Yangi stend bilan (bash stand.sh reset dev):  node scenarios/e2e-kassa24.cjs
const E = require('../lib/common.cjs'); const fs = require('fs');
const OUT = E.OUT;
const { session, ids } = E;
const UI = 'v2';   // yagona dizayn
const q = E.q;
const res = []; const ok = (n, c, x) => { res.push({ n, ok: !!c }); console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  ' + JSON.stringify(x === undefined ? null : x).slice(0, 900))); };
fs.mkdirSync(OUT, { recursive: true });
const allErrs = [];
const nb = s => String(s || '').replace(/[\u00a0\u202f]/g, ' ');
const norm = p => { const o = {}; Object.keys(p || {}).sort().forEach(k => { if (Number(p[k]) !== 0) o[k] = Number(p[k]); }); return JSON.stringify(o); };
(async () => {
  const b = await E.launch();
  const tk = new Date(Date.now() + 5 * 3600e3), P = `${tk.getUTCFullYear()}-${String(tk.getUTCMonth() + 1).padStart(2, '0')}`;
  const PM = (() => { const [y, m] = P.split('-').map(Number); return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, '0')}`; })();
  const SIDS = ['IQ-0003', 'IQ-0006', 'IQ-0009', 'IQ-0012', 'IQ-0015'];
  const inv = sid => { const r = q(`select coalesce(amount::text,'') || '|' || coalesce("grossAmount"::text,'') || '|' || coalesce("discountParts"::text,'null') || '|' || coalesce(status,'') || '|' || coalesce("discountInfo",'') from public.invoices where id = '${sid}__${P}'`);
    if (!r) return null; const [a, g, p, st, info] = r.split('|'); return { amount: Number(a), gross: g === '' ? null : Number(g), parts: JSON.parse(p), status: st, info }; };
  // ---- tayyorgarlik
  const paid0 = q(`select count(*) from public.invoices where id in (${SIDS.map(s => `'${s}__${P}'`).join(',')}) and coalesce("paidAmount",0) > 0`);
  q(`set session_replication_role = replica;
     delete from public.invoices where id in (${SIDS.map(s => `'${s}__${P}'`).join(',')});
     update public.student_private set "specialCategory" = 'teacher_child' where id = 'IQ-0003';
     update public.student_private set "specialCategory" = 'olympiad' where id = 'IQ-0006';
     update public.students set "activeFrom" = '${P}-16' where id = 'IQ-0006';
     update public.student_private set "specialCategory" = 'contract', "contractAmount" = 2000000 where id = 'IQ-0009';
     update public.student_private set "referrerId" = 'IQ-0009' where id = 'IQ-0012';
     insert into public.attendance (id, "studentId", "classKey", month, days) values ('IQ-0012__${PM}', 'IQ-0012', 'ru-7-B', '${PM}', '{"10":"sick","11":"sick","12":"present"}')
       on conflict (id) do update set days = excluded.days;
     set session_replication_role = origin;`);
  ok('tayyorgarlik: 5 ta to‘lanmagan faktura o‘chirildi (to‘lovsiz), toifalar va davomat yozildi',
    paid0 === '0' && q(`select count(*) from public.invoices where id in (${SIDS.map(s => `'${s}__${P}'`).join(',')})`) === '0', paid0);

  // ---- 1) Direktor: generatsiya
  const email = q(`select email from public.users where id='${ids.R_DIR}'`);
  const ctx = await b.newContext({ timezoneId: 'Asia/Tashkent', viewport: { width: 1440, height: 900 } });
  await ctx.addInitScript(([k, v, ui, u]) => { try { if (!localStorage.getItem(k)) localStorage.setItem(k, v); localStorage.setItem('iqror_ui', ui); localStorage.setItem('iqror-enroll-seen', String(Date.now() + 864e5)); localStorage.setItem('iqror_uid', u); } catch (e) {} },
    ['sb-127-auth-token', JSON.stringify(session(ids.R_DIR, email, { displayName: 'SINOV' })), UI, ids.R_DIR]);
  const pg = await ctx.newPage(); const dialogs = [], posts = [], reprices = [];
  pg.on('pageerror', e => allErrs.push(String(e.stack || e.message).split('\n').slice(0, 3).join(' <- ').slice(0, 400)));
  pg.on('dialog', d => { dialogs.push(d.message()); d.accept().catch(() => {}); });
  pg.on('request', r => {
    const u = r.url();
    if (/\/rest\/v1\/invoices(\?|$)/.test(u) && r.method() === 'POST') { try { const x = JSON.parse(r.postData() || 'null'); (Array.isArray(x) ? x : [x]).forEach(y => y && posts.push(y)); } catch (e) {} }
    if (/\/rest\/v1\/rpc\/reprice_invoice/.test(u)) { try { reprices.push(JSON.parse(r.postData() || 'null')); } catch (e) {} }
  });
  await pg.goto(E.BASE + '/admin.html');
  await pg.waitForFunction(() => document.querySelectorAll('#tabs button[data-tab]').length > 0, null, { timeout: 30000 });
  await pg.waitForTimeout(700);
  await pg.waitForSelector('#tabs button[data-tab="payments"]', { state: 'attached', timeout: 15000 });
  await pg.$eval('#tabs button[data-tab="payments"]', x => x.click());
  await pg.waitForSelector('#pm-gen', { timeout: 15000 });
  await pg.waitForFunction(() => document.querySelector('#pm-body') && !document.querySelector('#pm-body .loading'), null, { timeout: 15000 }).catch(() => {});
  const month0 = await pg.$eval('#pm-month', e => e.value);
  await pg.click('#pm-gen');
  await pg.waitForFunction(() => { const b = document.querySelector('#pm-gen'); return b && !b.dataset.busy && /yaratildi|yaratilmadi/.test((document.querySelector('#pm-genmsg') || {}).textContent || ''); }, null, { timeout: 60000 });
  const genMsg = nb(await pg.$eval('#pm-genmsg', e => e.textContent));
  ok('«Hisob-fakturalar yaratish» (joriy oy): 5 ta yaratildi, 4 tasida chegirma, 1 tavsiya bonusi', month0 === P
    && /5 ta hisob-faktura yaratildi \(4 tasida chegirma\)/.test(genMsg) && /1 tavsiya bonusi × 300 000 so‘m/.test(genMsg), [month0, genMsg]);

  const I = {}; SIDS.forEach(s => { I[s] = inv(s); });
  const sum = p => Object.values(p || {}).reduce((a, x) => a + Number(x), 0);
  ok('har yangi faktura: summa = yalpi − Σ qismlar (baza)', SIDS.every(s => I[s] && I[s].gross != null && I[s].amount === I[s].gross - sum(I[s].parts)), I);
  const sent = {}; posts.forEach(x => { if (x && x.studentId && x.month === P) sent[x.studentId] = x; });
  ok('sahifa har fakturaga yalpi va tarkibni yuborgan, baza aynan shuni saqlagan (server qayta hisoblamagan)',
    SIDS.every(s => sent[s] && Number(sent[s].grossAmount) === I[s].gross && norm(sent[s].discountParts) === norm(I[s].parts)),
    SIDS.map(s => [s, sent[s] && sent[s].grossAmount, sent[s] && sent[s].discountParts, I[s] && I[s].gross, I[s] && I[s].parts]));
  const a3 = I['IQ-0003'], a6 = I['IQ-0006'], a9 = I['IQ-0009'], a12 = I['IQ-0012'], a15 = I['IQ-0015'];
  ok('xodim farzandi 50 %: yalpi 2 800 000, teacher_child 1 400 000, summa 1 400 000',
    a3.gross === 2800000 && norm(a3.parts) === norm({ teacher_child: 1400000 }) && a3.amount === 1400000 && a3.info === 'Xodim farzandi 50%', a3);
  const m6 = /(\d+)\/(\d+) ish kuni \(prorata\)/.exec(a6.info || '');
  ok('grant, oy o‘rtasida kelgan: izohda ish kunlari ulushi, yalpi = narx × ulush, grant = yalpi, summa 0 (to‘langan)',
    !!m6 && /^100% grant \(olimpiada\/ijtimoiy\) · /.test(a6.info) && a6.gross === Math.round(3200000 * Number(m6[1]) / Number(m6[2]))
      && norm(a6.parts) === norm({ grant: a6.gross }) && a6.amount === 0 && a6.status === 'paid', a6);
  ok('kontrakt + tavsiya: yalpi = kontrakt summasi 2 000 000, referral 300 000, summa 1 700 000; tavsiya jurnali yozildi',
    a9.gross === 2000000 && norm(a9.parts) === norm({ referral: 300000 }) && a9.amount === 1700000 && /^Kontrakt \(belgilangan summa\) · Referral −300000$/.test(a9.info)
      && q(`select "referrerId" || '/' || trim_scale(amount) || '/' || month from public.referral_ledger where id = 'IQ-0012'`) === `IQ-0009/300000/${P}`, a9);
  ok('kasal kun (eski qoida, 2 kun × 45 000): yalpi 3 600 000, sick 90 000, summa 3 510 000',
    a12.gross === 3600000 && norm(a12.parts) === norm({ sick: 90000 }) && a12.amount === 3510000 && /^2 kasal kun \(−90000\)$/.test(a12.info), a12);
  ok('chegirmasiz: yalpi = summa = 2 500 000, tarkib bo‘sh', a15.gross === 2500000 && norm(a15.parts) === '{}' && a15.amount === 2500000, a15);

  // ---- 2) faktura qatori izohi
  await pg.waitForFunction(() => /IQ-0003/.test((document.querySelector('#pm-body') || {}).textContent || ''), null, { timeout: 15000 }).catch(() => {});
  const tip = nb(await pg.evaluate(() => { const tr = [...document.querySelectorAll('#pm-body tr')].find(t => /IQ-0003/.test(t.textContent));
    const c = tr && tr.querySelector('.chip[title]'); return c ? c.getAttribute('title') : ''; }));
  ok('«To‘lovlar» qatori: chegirma belgisi izohida tarkib — «Yalpi 2 800 000 so‘m · xodim farzandi −1 400 000 so‘m»',
    /^Xodim farzandi 50%\nYalpi 2 800 000 so‘m · xodim farzandi −1 400 000 so‘m$/.test(tip), tip);

  // ---- 3) qayta hisoblash
  q(`set session_replication_role = replica; update public.student_private set "specialCategory" = 'teacher_child' where id = 'IQ-0015'; set session_replication_role = origin;`);
  reprices.length = 0; dialogs.length = 0;
  await pg.click('#pm-recalc');
  await pg.waitForFunction(() => { const b = document.querySelector('#pm-recalc'); return b && !b.dataset.busy && /qayta hisoblandi/.test((document.querySelector('#pm-genmsg') || {}).textContent || ''); }, null, { timeout: 60000 });
  const r15 = reprices.find(x => x && x.p_id === `IQ-0015__${P}`), b15 = inv('IQ-0015');
  ok('«↻ Qayta hisoblash»: reprice_invoice meta da tarkib (yalpi 2 500 000, teacher_child 1 250 000); baza shuni saqladi, summa 1 250 000',
    !!r15 && Number(r15.p_net) === 1250000 && r15.p_meta && Number(r15.p_meta.grossAmount) === 2500000 && norm(r15.p_meta.discountParts) === norm({ teacher_child: 1250000 })
      && b15.gross === 2500000 && norm(b15.parts) === norm({ teacher_child: 1250000 }) && b15.amount === 1250000, [r15, b15]);
  const again = reprices.filter(x => x && ['IQ-0003', 'IQ-0006', 'IQ-0009', 'IQ-0012'].some(s => x.p_id === `${s}__${P}`)).map(x => x.p_id);
  ok('tarkibi o‘zgarmagan yangi fakturalar qayta yozilmadi (bazadan o‘qilgan tarkib hisoblangan bilan bir xil)', again.length === 0 && dialogs.length >= 1, [again, dialogs.length]);

  ok('sahifa xatolari yo‘q', allErrs.length === 0, allErrs);
  await b.close();
  const f = res.filter(r => !r.ok).length;
  console.log(`JAMI (v2): ${res.length - f}/${res.length}`);
  process.exit(f ? 1 : 0);
})().catch(e => { console.error('XATO', e && e.stack || e); process.exit(2); });
