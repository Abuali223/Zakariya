// =====================================================================
// fin-matrix.js — RP-09: barcha to'lov usullari bo'yicha statiya matritsasi va maosh taqsimoti (moliya ish rejasi 2-bosqich, F2.5).
//   admin.html («Buxgalteriya» → «📊 RP-09») kerak bo'lganda import() bilan yuklaydi.
//   Server: migration/fin-matrix.sql — fin_matrix(p_kind 'school' | 'calendar', p_year) — Direktor, Moliya menejeri, buxgalter; faqat
//   yig'ma summalar (ism yo'q, FD-28). Jadval: statiya × oy (pul harakati — barcha usullar yoki bitta usul), hisobdor xarajatlari va
//   hisoblangan maosh — alohida (pul jamiga kirmaydi); ichki o'tkazma — belgili, sof oqimga kirmaydi; nazorat — Jami = Σ hujjatlar.
//   Faqat mavjud komponentlar (.modal-*, .btn, .chip, .tablewrap) — yangi CSS yo'q. XLSX — window.XLSX (sahifada yuklangan).
//   Kirish:  openMatrix(ctx, o) — o: { today }
//            Sof funksiyalar (fin-matrix.test.mjs): yearDefault, yearOptions, periodLabel, monthLabel, rowMonths, matrixTotals,
//            controlCheck, payrollNote, articleLabel, classifyNotes, matrixSheets, fileName.
//   F2.3: noyabr–yanvar eski xarajatlari — buxgalter tasdiqlaguncha «≈ taxminiy»; oylar holati (M.classify) — xulosada va «Nazorat» varag'ida.
// =====================================================================

let C = null;                                    // admin.html bergan yordamchilar (ctx)
let O = {};                                      // oyna sozlamalari
const SEL = { kind: '', year: 0, view: 'money' };   // tanlov (sessiya davomida saqlanadi)

export const MONEY = ['cash', 'bank', 'card', 'online', 'offset', 'other'];
export const METHOD_LBL = { cash: 'Naqd', bank: 'Bank', card: 'Karta / terminal', online: 'Onlayn (Click, Uzum, Payme)', offset: 'O‘zaro hisob',
  other: 'Boshqa / usuli noma’lum', accountable: 'Hisobdor orqali (avans hisoboti)', accrual: 'Hisoblangan maosh (vedomost)' };
export const SOURCE_LBL = { kassa: 'Kassa: KO-1 / KO-2 (naqd)', payments: 'O‘quv to‘lovlari (kassa orderisiz)', expenses: '«Buxgalteriya» xarajatlari (kassa orderisiz)',
  refunds: 'Qaytarishlar (kassa orderisiz)', salary: 'Maosh to‘lovlari (kassa orderisiz)', advances: 'Avans to‘lovlari (kassa orderisiz)',
  payroll: 'Maosh taqsimoti (vedomost, hisoblash)' };
const RUN_LBL = { draft: 'qoralama', submitted: 'tasdiqda', approved: 'tasdiqlangan', returned: 'qaytarilgan' };
const MO = ['Yan', 'Fev', 'Mar', 'Apr', 'May', 'Iyun', 'Iyul', 'Avg', 'Sen', 'Okt', 'Noy', 'Dek'];
const FLD = 'padding:10px 12px;border:1px solid var(--border);border-radius:10px;font:inherit;width:100%;background:#fff';
const $ = s => C.$(s);
const esc = s => C.esc(s);
const num = v => Number(v) || 0;
const r2 = v => Math.round(num(v) * 100) / 100;
const errText = e => String((e && (e.message || e.code)) || e || 'xato');
const som = v => { const n = r2(v), a = Math.abs(n), w = Math.floor(a), t = Math.round((a - w) * 100);
  return (n < 0 ? '−' : '') + String(w).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + (t ? ',' + String(t).padStart(2, '0') : ''); };
const lbl = (t, inner) => `<label class="small" style="font-weight:700;display:flex;flex-direction:column;gap:6px;margin-top:8px">${t}${inner}</label>`;
const opt = (v, t, sel) => `<option value="${esc(v)}"${String(v) === String(sel) ? ' selected' : ''}>${esc(t)}</option>`;
const chip = (t, fg, bg, title) => `<span class="chip" style="background:${bg};color:${fg};border-color:transparent"${title ? ` title="${esc(title)}"` : ''}>${esc(t)}</span>`;
const zeros = () => Array(12).fill(0);
const add = (a, b) => a.map((x, i) => r2(x + num(b && b[i])));
const sum = a => r2((a || []).reduce((s, x) => s + num(x), 0));
const dmy = v => { const t = String(v || ''); return /^\d{4}-\d{2}-\d{2}/.test(t) ? `${t.slice(8, 10)}.${t.slice(5, 7)}.${t.slice(0, 4)}` : t; };

// ---------------------------------------------------------------- sof funksiyalar
// Standart yil: o'quv yili — 1-sentyabrdan yangisi (avgustda — o'tgan o'quv yili), kalendar — joriy yil.
export function yearDefault(kind, today) {
  const t = String(today || ''); if (!/^\d{4}-\d{2}/.test(t)) return 0;
  const y = +t.slice(0, 4), m = +t.slice(5, 7);
  return kind === 'school' ? (m >= 9 ? y : y - 1) : y;
}
// Tanlash mumkin yillar: 2024 dan joriygacha (server keyingi yilni ham qabul qiladi — bo'sh; ro'yxatda yo'q).
export function yearOptions(kind, today) {
  const hi = yearDefault(kind, today), out = [];
  for (let y = Math.max(hi, 2024); y >= 2024; y--) out.push(y);
  return out;
}
export const periodLabel = (kind, year) => kind === 'school' ? `${year}/${year + 1} o‘quv yili (01.09.${year} – 31.08.${year + 1})` : `${year} kalendar yili (01.01.${year} – 31.12.${year})`;
export const monthLabel = ym => { const s = String(ym || ''); return /^\d{4}-\d{2}$/.test(s) ? `${MO[+s.slice(5, 7) - 1]} ${s.slice(0, 4)}` : s; };
// Qatorning oylari: berilgan usullar yig'indisi ('money' — pul usullari, aks holda bitta usul)
export function rowMonths(r, view) {
  const ms = view === 'money' ? MONEY : [view];
  return ms.reduce((acc, k) => add(acc, (r && r.m && r.m[k]) || null), zeros());
}
// Jamlar: kirim / chiqim (pul), shundan ichki o'tkazma, sof oqim (ichki o'tkazmalarsiz); hisobdor va hisoblash — alohida; usullar bo'yicha.
export function matrixTotals(M) {
  const t = { inAll: zeros(), outAll: zeros(), trIn: zeros(), trOut: zeros(), accountable: zeros(), accrual: zeros(), byMethod: { in: {}, out: {} }, grand: 0 };
  for (const r of (M && M.rows) || []) {
    const mon = rowMonths(r, 'money'), isIn = r.dir === 'in';
    if (isIn) t.inAll = add(t.inAll, mon); else t.outAll = add(t.outAll, mon);
    if (r.transfer) { if (isIn) t.trIn = add(t.trIn, mon); else t.trOut = add(t.trOut, mon); }
    t.accountable = add(t.accountable, rowMonths(r, 'accountable'));
    t.accrual = add(t.accrual, rowMonths(r, 'accrual'));
    for (const k of Object.keys(r.m || {})) { const bm = t.byMethod[isIn ? 'in' : 'out']; bm[k] = r2(num(bm[k]) + sum(r.m[k])); }
    t.grand = r2(t.grand + num(r.money) + num(r.accountable) + num(r.accrual));
  }
  t.netIn = t.inAll.map((x, i) => r2(x - t.trIn[i])); t.netOut = t.outAll.map((x, i) => r2(x - t.trOut[i]));
  t.net = t.netIn.map((x, i) => r2(x - t.netOut[i]));
  return t;
}
// Nazorat: matritsa jami = manbalar jami (Jami = Σ hujjatlar); kassa — order sarlavhalari; maosh — oylar bo'yicha izoh.
export function controlCheck(M) {
  const src = (M && M.sources) || [], tot = matrixTotals(M), srcTotal = r2(src.reduce((s, x) => s + num(x.total), 0));
  const k = src.find(x => x.key === 'kassa') || { docs: 0, total: 0 }, kh = (M && M.kassaHeader) || {};
  const kassaOk = Math.abs(r2(num(kh.in) + num(kh.out)) - r2(k.total)) < 0.005 && num(kh.docs) === num(k.docs);
  const pay = ((M && M.payroll && M.payroll.byMonth) || []).map(p => { const x = payrollNote(p); return x ? { ...p, note: x.text, warn: x.warn } : null; }).filter(Boolean);
  return { rowsTotal: tot.grand, srcTotal, ok: Math.abs(tot.grand - srcTotal) < 0.005, kassaOk, payroll: pay, payrollWarn: pay.filter(p => p.warn).length,
           docs: src.reduce((s, x) => s + num(x.docs), 0), unclassified: (M && M.unclassified) || [] };
}
// Maosh oyi izohi { text, warn }: tasdiqlangan vedomost — «Maosh» qatori bilan mos / farq / qator yozilmagan; tasdiqlanmagan — taqsimlanmagan
//   (vedomostni tasdiqlash kerak); vedomostsiz oy (o'tish oyidan oldingi tartib) — taqsimlanmagan, statiyani buxgalter belgilaydi.
export function payrollNote(p) {
  if (!p || (!p.run && p.accrualRow == null)) return null;
  if (p.run === 'approved') {
    if (p.accrualRow == null) return { text: '«Maosh» hisoblash qatori yozilmagan («💼 Oylik maoshni yozish»)', warn: true };
    return Math.abs(num(p.diff)) < 0.5 ? { text: '✓ «Maosh» qatori bilan mos', warn: false } : { text: `farq: ${som(p.diff)} — «Maosh» qatorini qayta yozing`, warn: true };
  }
  if (!p.run) return { text: 'vedomost yo‘q — «Maosh» qatori taqsimlanmagan (statiyani buxgalter belgilaydi)', warn: false };
  if (p.accrualRow != null) return { text: `vedomost ${RUN_LBL[p.run] || p.run} — «Maosh» qatori taqsimlanmagan`, warn: true };
  return { text: `vedomost ${RUN_LBL[p.run] || p.run}`, warn: false };
}
export function articleLabel(r) {
  if (!r) return '';
  if (r.articleId) return `${r.articleId} ${r.nameUz || ''}`.trim();
  return r.dir === 'in' ? 'Statiyasiz kirim' : 'Statiyasiz / aniqlanmagan';
}
const flagText = r => [r.transfer ? 'ichki o‘tkazma' : '', r.approx ? 'toifadan (taxminiy)' : ''].filter(Boolean).join(', ');
// F2.3: eski xarajatlar statiya tasnifi — yozuvi bor oylar: [{month, n, confirmed, text, warn}] («qisman» — tasdiqlanmagani bor;
//   imzolanmagan yoki imzosi eskirgan oy ham e'tibor talab qiladi)
export function classifyNotes(M) {
  return ((M && M.classify) || []).filter(c => num(c.n) > 0).map(c => {
    const sg = c.sign && typeof c.sign === 'object' ? c.sign : null, n = num(c.n), k = num(c.confirmed), ok = !!(sg && sg.valid);
    const text = ok ? `imzolangan (${sg.by || 'buxgalter'}, ${dmy(sg.at)})` : k < n ? `qisman: ${n} tadan ${k} tasi tasdiqlangan`
      : sg ? 'imzo eskirgan — qayta imzolash kerak' : 'tasdiqlangan, buxgalter imzosi kutilmoqda';
    return { month: c.month, n, confirmed: k, text, warn: !ok };
  });
}
export const fileName = M => `RP-09_${M && M.kind === 'school' ? `oquv-${M.year}-${num(M.year) + 1}` : `kalendar-${(M && M.year) || ''}`}.xlsx`;

// XLSX varaqlari: Matritsa (pul harakati + hisobdor + hisoblash), Usullar (statiya × usul), Maosh taqsimoti, Nazorat.
export function matrixSheets(M, o) {
  const ms = (M && M.months) || [], mh = ms.map(monthLabel), head = periodLabel(M.kind, num(M.year)), org = (o && o.org) || '';
  const top = t => [[t], [head + (org ? ' · ' + org : '')], ['Tuzilgan: ' + String(M.generatedAt || '').replace('T', ' ').slice(0, 16) + ' · summalar so‘mda'], []];
  const rows = (M && M.rows) || [], T = matrixTotals(M);
  const line = (a, b, c, arr) => [a, b, c, ...arr.map(r2), sum(arr)];
  // 1) Matritsa
  const m1 = [...top('RP-09 — barcha to‘lov usullari bo‘yicha statiya matritsasi'), ['Yo‘nalish', 'Statiya', 'Belgi', ...mh, 'Jami']];
  for (const dir of ['in', 'out']) {
    for (const r of rows.filter(x => x.dir === dir && num(x.money) !== 0)) m1.push(line(dir === 'in' ? 'Kirim' : 'Chiqim', articleLabel(r), flagText(r), rowMonths(r, 'money')));
    m1.push(line(dir === 'in' ? 'JAMI KIRIM' : 'JAMI CHIQIM', '', '', dir === 'in' ? T.inAll : T.outAll));
  }
  m1.push(line('Ichki o‘tkazma', 'kirim', '', T.trIn), line('Ichki o‘tkazma', 'chiqim', '', T.trOut), line('SOF PUL OQIMI', 'ichki o‘tkazmalarsiz', '', T.net), []);
  m1.push(['Hisobdor orqali (avans hisoboti) — pul oldin OP-06 bilan berilgan, jamiga qo‘shilmaydi']);
  for (const r of rows.filter(x => num(x.accountable) !== 0)) m1.push(line('Hisobdor', articleLabel(r), flagText(r), rowMonths(r, 'accountable')));
  m1.push(line('JAMI', 'hisobdor', '', T.accountable), []);
  m1.push(['Hisoblangan maosh (tasdiqlangan vedomost × lavozim) — hisoblash, pul emas (to‘lov — OP-09)']);
  for (const r of rows.filter(x => num(x.accrual) !== 0)) m1.push(line('Hisoblash', articleLabel(r), '', rowMonths(r, 'accrual')));
  m1.push(line('JAMI', 'hisoblangan maosh', '', T.accrual));
  // 2) Usullar
  const m2 = [...top('RP-09 — statiya va to‘lov usuli bo‘yicha'), ['Yo‘nalish', 'Statiya', 'Usul', ...mh, 'Jami']];
  for (const r of rows) for (const k of Object.keys(r.m || {}).sort((a, b) => (M.methods || []).indexOf(a) - (M.methods || []).indexOf(b)))
    m2.push(line(r.dir === 'in' ? 'Kirim' : 'Chiqim', articleLabel(r), METHOD_LBL[k] || k, r.m[k]));
  // 3) Maosh taqsimoti
  const m3 = [...top('RP-09 — maosh taqsimoti (vedomost × lavozim -> EX-01…EX-04)'), ['Oy', 'Vedomost', 'Taqsimot', '«Maosh» qatori', 'Farq', 'Izoh']];
  for (const p of (M.payroll && M.payroll.byMonth) || []) {
    if (!p.run && p.accrualRow == null) continue;
    m3.push([monthLabel(p.month), RUN_LBL[p.run] || '—', r2(p.split), p.accrualRow == null ? '' : r2(p.accrualRow), p.diff == null ? '' : r2(p.diff), (payrollNote(p) || {}).text || '']);
  }
  m3.push([], ['Lavozim', 'Statiya', 'Qatorlar', 'Summa']);
  for (const p of (M.payroll && M.payroll.positions) || []) m3.push([p.type === 'teacher' ? 'O‘qituvchilar ro‘yxati' : (p.position || '(xodim kartasi yo‘q)'), p.articleId || 'aniqlanmagan', num(p.lines), r2(p.total)]);
  // 4) Nazorat
  const K = controlCheck(M), kh = M.kassaHeader || {};
  const m4 = [...top('RP-09 — nazorat: Jami = Σ hujjatlar'), ['Manba', 'Hujjatlar', 'Jami']];
  for (const s of M.sources || []) m4.push([SOURCE_LBL[s.key] || s.key, num(s.docs), r2(s.total)]);
  m4.push(['Manbalar jami', K.docs, K.srcTotal], ['Matritsa jami (pul + hisobdor + hisoblash)', '', K.rowsTotal], ['Moslik', '', K.ok ? 'mos' : 'MOS EMAS'], [],
    ['Kassa: order sarlavhalari (kirim / chiqim / soni)', num(kh.docs), r2(num(kh.in) + num(kh.out))], ['Kassa moslik', '', K.kassaOk ? 'mos' : 'MOS EMAS']);
  if (K.unclassified.length) { m4.push([], ['Statiyasiz xarajat toifalari', 'Yozuvlar', 'Jami']); for (const u of K.unclassified) m4.push([u.category || '(toifasiz)', num(u.rows), r2(u.total)]); }
  const CN = classifyNotes(M);
  if (CN.length) { m4.push([], ['Eski xarajatlar statiya tasnifi (noyabr–yanvar, F2.3)', 'Yozuvlar', 'Holat']); for (const c of CN) m4.push([monthLabel(c.month), c.n, c.text]); }
  const wide = [12, 34, 18, ...ms.map(() => 13), 15];
  return [{ name: 'Matritsa', rows: m1, cols: wide.map(w => ({ wch: w })) }, { name: 'Usullar', rows: m2, cols: wide.map(w => ({ wch: w })) },
          { name: 'Maosh taqsimoti', rows: m3, cols: [16, 30, 14, 16, 14, 52].map(w => ({ wch: w })) },
          { name: 'Nazorat', rows: m4, cols: [52, 12, 18].map(w => ({ wch: w })) }];
}

// ---------------------------------------------------------------- oyna
export async function openMatrix(ctx, o) {
  C = ctx; O = o || {};
  const today = O.today || '';
  if (!SEL.kind) SEL.kind = 'school';
  if (!yearOptions(SEL.kind, today).includes(SEL.year)) SEL.year = yearOptions(SEL.kind, today)[0];
  $('#modal').innerHTML = `<div class="modal-h"><h3>📊 RP-09 — statiya matritsasi</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      <div class="small muted">Barcha pul harakati statiyalar bo‘yicha, oylar kesimida: kassa orderlari, kassadan tashqari o‘quv to‘lovlari (onlayn, terminal, bank, o‘zaro hisob), «Buxgalteriya» xarajatlari, qaytarishlar, maosh va avans to‘lovlari. Hisobdor xarajatlari va hisoblangan maosh (vedomost × lavozim) — alohida, pul jamiga kirmaydi.</div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:0 10px">
        ${lbl('Davr turi', `<select id="mx-kind" style="${FLD}">${opt('school', 'O‘quv yili (sentyabr–avgust)', SEL.kind)}${opt('calendar', 'Kalendar yili (yanvar–dekabr)', SEL.kind)}</select>`)}
        ${lbl('Yil', `<select id="mx-year" style="${FLD}"></select>`)}
        ${lbl('Ko‘rinish', `<select id="mx-view" style="${FLD}">${opt('money', 'Pul harakati (barcha usullar)', SEL.view)}${[...MONEY, 'accountable', 'accrual'].map(k => opt(k, METHOD_LBL[k], SEL.view)).join('')}</select>`)}
      </div>
      <div style="margin-top:8px"><button type="button" class="btn ghost2" id="mx-load">Ko‘rsatish</button></div>
      <div id="mx-body" style="margin-top:10px"></div>
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button><button type="button" class="btn gold" id="mx-xlsx" disabled>⬇ Excel (XLSX)</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const fillYears = () => { $('#mx-year').innerHTML = yearOptions(SEL.kind, today).map(y => opt(y, SEL.kind === 'school' ? `${y}/${y + 1}` : String(y), SEL.year)).join(''); };
  fillYears();
  let M = null, busy = false;
  $('#mx-kind').onchange = () => { SEL.kind = $('#mx-kind').value; SEL.year = yearOptions(SEL.kind, today)[0]; fillYears(); };
  $('#mx-year').onchange = () => { SEL.year = +$('#mx-year').value; };
  $('#mx-view').onchange = () => { SEL.view = $('#mx-view').value; if (M) draw(M); };
  const load = async () => {
    if (busy) return; busy = true; $('#mx-xlsx').disabled = true; M = null;
    $('#mx-body').innerHTML = '<div class="loading">Yuklanmoqda…</div>';
    try { M = await C.rpc('fin_matrix', { p_kind: SEL.kind, p_year: SEL.year }); draw(M); $('#mx-xlsx').disabled = false; }
    catch (e) { $('#mx-body').innerHTML = ''; C.toast(errText(e), true); }
    finally { busy = false; }
  };
  $('#mx-load').onclick = load;
  $('#mx-xlsx').onclick = () => {
    if (!M) return;
    const X = window.XLSX;
    if (!X || !X.utils || !X.writeFile) { C.toast('Excel kutubxonasi hali yuklanmadi — sahifani yangilab qayta urining', true); return; }
    try { const wb = X.utils.book_new();
      for (const sh of matrixSheets(M, { org: O.org || '' })) { const ws = X.utils.aoa_to_sheet(sh.rows); ws['!cols'] = sh.cols; X.utils.book_append_sheet(wb, ws, sh.name); }
      X.writeFile(wb, fileName(M)); C.toast('Saqlandi: RP-09 (4 varaq)'); }
    catch (e) { C.toast('Excel fayl tuzilmadi: ' + errText(e), true); }
  };
  load();
}

function draw(M) {
  const nw = (v, bold) => `<${bold ? 'b' : 'span'} style="white-space:nowrap">${esc(som(v))}</${bold ? 'b' : 'span'}>`;   // summa qator o'rtasida bo'linmasin
  const view = SEL.view, T = matrixTotals(M), K = controlCheck(M), mh = (M.months || []).map(monthLabel);
  const rows = (M.rows || []).filter(r => sum(rowMonths(r, view)) !== 0);
  const cells = arr => arr.map(x => `<td style="text-align:right;white-space:nowrap">${x ? esc(som(x)) : ''}</td>`).join('') + `<td style="text-align:right;white-space:nowrap"><b>${esc(som(sum(arr)))}</b></td>`;
  const flag = r => (r.transfer ? chip('ichki o‘tkazma', '#344054', '#F2F4F7', 'Bankka topshirish / bankdan olish, o‘z hisoblari orasida — daromad ham, xarajat ham emas') : '')
    + (r.approx ? chip('≈ toifadan', '#B54708', '#FEF3E2', 'Statiya xarajat toifasidan olingan (taxminiy): yozuvda statiya yo‘q yoki (noyabr–yanvar eski yozuvlari) buxgalter hali tasdiqlamagan — «🏷 Statiya tasnifi»') : '');
  const CN = classifyNotes(M);
  const trs = dir => rows.filter(r => r.dir === dir).map(r => `<tr><td data-label="Statiya" style="min-width:200px">${esc(articleLabel(r))}<div style="display:flex;gap:4px;flex-wrap:wrap">${flag(r)}</div></td>${cells(rowMonths(r, view))}</tr>`).join('');
  const tot = (t, arr) => `<tr><td><b>${esc(t)}</b></td>${cells(arr)}</tr>`;
  const sub = dir => { const arr = rows.filter(r => r.dir === dir).reduce((a, r) => add(a, rowMonths(r, view)), zeros()); return tot(dir === 'in' ? 'Jami kirim' : 'Jami chiqim', arr); };
  const hasIn = rows.some(r => r.dir === 'in'), hasOut = rows.some(r => r.dir === 'out');
  const ok = (b, t) => b ? chip('✓ ' + t, '#027A48', '#ECFDF3') : chip('✗ ' + t, '#B42318', '#FDECEC');
  const payRows = K.payroll.map(p => `<tr><td data-label="Oy">${esc(monthLabel(p.month))}</td><td data-label="Vedomost">${esc(RUN_LBL[p.run] || '—')}</td>
      <td data-label="Taqsimot" style="text-align:right;white-space:nowrap">${esc(som(p.split))}</td><td data-label="«Maosh» qatori" style="text-align:right;white-space:nowrap">${p.accrualRow == null ? '—' : esc(som(p.accrualRow))}</td>
      <td data-label="Izoh">${p.warn ? chip(p.note, '#B54708', '#FEF3E2') : esc(p.note)}</td></tr>`).join('');
  const posRows = ((M.payroll && M.payroll.positions) || []).map(p => `<tr><td data-label="Lavozim">${esc(p.type === 'teacher' ? 'O‘qituvchilar ro‘yxati' : (p.position || '(xodim kartasi yo‘q)'))}</td>
      <td data-label="Statiya">${p.articleId ? esc(p.articleId) : chip('aniqlanmagan', '#B54708', '#FEF3E2', 'Lavozim ro‘yxatda yo‘q — statiya buxgalter bilan kelishiladi')}</td>
      <td data-label="Qatorlar" style="text-align:right">${num(p.lines)}</td><td data-label="Summa" style="text-align:right;white-space:nowrap">${esc(som(p.total))}</td></tr>`).join('');
  const srcRows = (M.sources || []).map(s => `<tr><td data-label="Manba">${esc(SOURCE_LBL[s.key] || s.key)}</td><td data-label="Hujjatlar" style="text-align:right">${num(s.docs)}</td><td data-label="Jami" style="text-align:right;white-space:nowrap">${esc(som(s.total))}</td></tr>`).join('');
  $('#mx-body').innerHTML = `<div class="small" id="mx-sum" style="background:#eef3f1;border-radius:10px;padding:10px 12px">
      <b>${esc(periodLabel(M.kind, num(M.year)))}</b><br>
      Pul harakati: kirim ${nw(sum(T.inAll), 1)}, chiqim ${nw(sum(T.outAll), 1)}${sum(T.trIn) || sum(T.trOut) ? ` (shundan ichki o‘tkazma: kirim ${nw(sum(T.trIn))}, chiqim ${nw(sum(T.trOut))})` : ''} · sof oqim (ichki o‘tkazmalarsiz) ${nw(sum(T.net), 1)}
      <br>Hisobdor orqali: ${nw(sum(T.accountable))} · hisoblangan maosh: ${nw(sum(T.accrual))} (pul jamiga kirmaydi)
      <div style="display:flex;gap:4px;flex-wrap:wrap;margin-top:6px">${ok(K.ok, `Jami = Σ hujjatlar (${K.docs} ta)`)}${ok(K.kassaOk, 'kassa orderlari')}${K.payrollWarn ? chip(`maosh: ${K.payrollWarn} oyda e’tibor`, '#B54708', '#FEF3E2') : ''}${K.unclassified.length ? chip(`statiyasiz toifalar: ${K.unclassified.length}`, '#B54708', '#FEF3E2') : ''}</div>
      ${CN.length ? `<div id="mx-cls" style="margin-top:6px">Eski xarajatlar statiyasi (noyabr–yanvar): ${CN.map(c => `<span data-clm="${esc(c.month)}">${esc(monthLabel(c.month))} — ${c.warn ? chip(c.text, '#B54708', '#FEF3E2') : esc(c.text)}</span>`).join(' · ')}</div>` : ''}</div>
    <div class="small muted" style="margin-top:8px">Ko‘rinish: <b>${esc(view === 'money' ? 'pul harakati (barcha usullar)' : METHOD_LBL[view] || view)}</b></div>
    ${rows.length ? `<div class="tablewrap" style="max-height:420px;overflow:auto;margin-top:6px"><table id="mx-tbl"><thead><tr><th>Statiya</th>${mh.map(h => `<th style="text-align:right;white-space:nowrap">${esc(h)}</th>`).join('')}<th style="text-align:right">Jami</th></tr></thead><tbody>
      ${hasIn ? trs('in') + sub('in') : ''}${hasOut ? trs('out') + sub('out') : ''}
      ${view === 'money' ? tot('Sof pul oqimi (ichki o‘tkazmalarsiz)', T.net) : ''}</tbody></table></div>` : '<div class="empty" style="margin-top:8px">Bu davrda tanlangan ko‘rinish bo‘yicha harakat yo‘q.</div>'}
    <h4 style="margin:14px 0 6px">Maosh taqsimoti (vedomost × lavozim)</h4>
    ${payRows ? `<div class="tablewrap"><table id="mx-pay"><thead><tr><th>Oy</th><th>Vedomost</th><th style="text-align:right">Taqsimot</th><th style="text-align:right">«Maosh» qatori</th><th>Izoh</th></tr></thead><tbody>${payRows}</tbody></table></div>` : '<div class="empty">Bu davrda vedomost va «Maosh» qatori yo‘q.</div>'}
    ${posRows ? `<div class="tablewrap" style="margin-top:6px"><table id="mx-pos"><thead><tr><th>Lavozim</th><th>Statiya</th><th style="text-align:right">Qatorlar</th><th style="text-align:right">Summa</th></tr></thead><tbody>${posRows}</tbody></table></div>` : ''}
    <h4 style="margin:14px 0 6px">Nazorat: Jami = Σ hujjatlar</h4>
    ${srcRows ? `<div class="tablewrap"><table id="mx-src"><thead><tr><th>Manba</th><th style="text-align:right">Hujjatlar</th><th style="text-align:right">Jami</th></tr></thead><tbody>${srcRows}
      <tr><td><b>Manbalar jami</b></td><td style="text-align:right"><b>${K.docs}</b></td><td style="text-align:right;white-space:nowrap"><b>${esc(som(K.srcTotal))}</b></td></tr>
      <tr><td>Matritsa jami (pul + hisobdor + hisoblash)</td><td></td><td style="text-align:right;white-space:nowrap">${esc(som(K.rowsTotal))}</td></tr></tbody></table></div>` : '<div class="empty">Hujjat yo‘q.</div>'}
    ${K.unclassified.length ? `<div class="small" style="margin-top:6px">Statiyasiz xarajat toifalari (statiya tanlab qayta saqlang): ${K.unclassified.map(u => esc(`${u.category || '(toifasiz)'} — ${u.rows} ta, ${som(u.total)}`)).join('; ')}</div>` : ''}`;
}
