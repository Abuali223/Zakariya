// =====================================================================
// fin-kassa.js — «Kassa» bo'limi (moliya ish rejasi 1a, F1.12). admin.html uni kerak bo'lganda import() bilan yuklaydi.
//   Faqat mavjud komponentlar (.page-head, .card, .acc-kpis, .tablewrap, .btn, .chip, #modal) — yangi CSS yo'q; v1 va v2 da bir xil.
//   Barcha yozish amallari — serverdagi kassa funksiyalari (migration/kassa-docs.sql, kassa-day.sql) orqali; bu fayl faqat
//   ko'rsatadi va so'rov yuboradi. Raqam, sana, qoldiq va huquqni SERVER belgilaydi.
//   Kirish:  renderKassa(ctx)            — sahifa
//            approvalCount(ctx)          — «Tasdiqlash» bo'limidagi navbat soni
//            approvalRender(ctx, el)     — «Tasdiqlash» bo'limidagi navbat ro'yxati
// =====================================================================
let C = null;                                   // admin.html bergan yordamchilar (ctx)
const ST = { desk: 'main', ov: null, refs: null, people: null, students: null };
const NOMINALS = [200000, 100000, 50000, 20000, 10000, 5000, 2000, 1000, 500, 200, 100, 50];
const PARTY_LBL = { student: 'O‘quvchi (to‘lovchi)', employee: 'Xodim', counterparty: 'Kontragent', bank: 'Bank', founder: 'Ta’sischi', other: 'Boshqa (yoziladi)' };
const CP_KIND = { supplier: 'Yetkazib beruvchi', org: 'Tashkilot', person: 'Jismoniy shaxs', bank: 'Bank', founder: 'Ta’sischi', other: 'Boshqa' };
const ST_LBL = { draft: 'Tasdiq kutilmoqda', approved: 'Tasdiqlangan — to‘lanadi', posted: 'O‘tkazilgan', void: 'Bekor qilingan', rejected: 'Rad etilgan', cancelled: 'Bekor qilingan so‘rov' };
const DAY_LBL = { open: 'Ochiq', closed: 'Yopilgan', verified: 'Tekshirilgan' };
const BLOCK_TXT = {
  prev_open: 'Oldingi kun yopilmagan — avval pulni sanab, kunni yoping.',
  day_closed: 'Bugungi kun yopilgan. Yangi hujjat uchun Direktor kunni qayta ochishi kerak.',
  not_started: 'Kassa hali ishga tushirilmagan: Direktor boshlang‘ich qoldiqni kiritishi kerak.',
  clock: 'Server sanasi kassa kunidan orqada — administratorga xabar bering.',
};

const $ = s => C.$(s);
const esc = s => C.esc(s);
const num = v => Number(v) || 0;
// Pul: «1 234 567 so‘m» (tiyin bo'lsa — «1 234,50 so‘m»). admin.html fmtSom tiyinni noto'g'ri ko'rsatadi, shuning uchun o'zimizniki.
const som = v => { const n = Math.round(num(v) * 100) / 100, a = Math.abs(n), w = Math.floor(a), t = Math.round((a - w) * 100);
  return (n < 0 ? '−' : '') + String(w).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + (t ? ',' + String(t).padStart(2, '0') : '') + ' so‘m'; };
const digits = s => String(s == null ? '' : s).replace(/[^\d]/g, '');
const amtOf = s => { const t = String(s == null ? '' : s).replace(/[\s ]/g, '').replace(',', '.'); return /^\d+(\.\d{1,2})?$/.test(t) ? Number(t) : NaN; };
const dmy = d => { const s = String(d || ''); return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(8, 10) + '.' + s.slice(5, 7) + '.' + s.slice(0, 4) : s; };
const hm = ts => { try { return new Date(ts).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Tashkent' }); } catch (_) { return ''; } };
const newRef = () => 'ks-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);
const errText = e => String((e && (e.message || e.code)) || e || 'xato');
const nameOf = uid => (uid && ST.ov && ST.ov.names && ST.ov.names[uid]) || (uid ? '…' : '—');
const me = () => (ST.ov && ST.ov.state && ST.ov.state.me) || {};
const rule = op => ((ST.refs && ST.refs.rules) || []).find(r => r.op === op) || null;
const opName = op => { const r = rule(op); return r ? r.nameUz : op; };
const artName = id => { const a = ((ST.refs && ST.refs.articles) || []).find(x => x.id === id); return a ? a.nameUz : (id || ''); };
const chip = (txt, fg, bg) => `<span class="chip" style="background:${bg};color:${fg};border-color:transparent">${esc(txt)}</span>`;
const stChip = st => chip(ST_LBL[st] || st, ({ posted: '#157347', void: '#B42318', rejected: '#B42318', cancelled: '#667085', approved: '#175CD3', draft: '#B54708' })[st] || '#475467',
  ({ posted: '#E7F6EC', void: '#FDECEC', rejected: '#FDECEC', cancelled: '#F2F4F7', approved: '#E8F1FD', draft: '#FEF3E2' })[st] || '#F2F4F7');
const dayChip = st => chip(DAY_LBL[st] || st, ({ open: '#B54708', closed: '#175CD3', verified: '#157347' })[st] || '#475467', ({ open: '#FEF3E2', closed: '#E8F1FD', verified: '#E7F6EC' })[st] || '#F2F4F7');
const FLD = 'padding:10px 12px;border:1px solid var(--border);border-radius:10px;font:inherit;width:100%;background:#fff';
const lbl = (t, inner, extra) => `<label class="small" style="font-weight:700;display:flex;flex-direction:column;gap:6px;margin-top:8px${extra || ''}">${t}${inner}</label>`;
const fmtInput = el => { if (el) el.addEventListener('input', () => { const d = digits(el.value); el.value = d.replace(/\B(?=(\d{3})+(?!\d))/g, ' '); }); };

async function call(fn, args) { return await C.rpc(fn, args || {}); }
async function loadOverview() { ST.ov = await call('kassa_overview', { p_desk: ST.desk }); return ST.ov; }
async function loadRefs(force) { if (!ST.refs || force) ST.refs = await call('kassa_refs'); return ST.refs; }
async function loadPeople() { if (!ST.people) ST.people = await call('kassa_people'); return ST.people; }
async function loadStudents() { if (!ST.students) ST.students = await C.students(); return ST.students; }

// ---------------------------------------------------------------- sahifa
export async function renderKassa(ctx) {
  C = ctx;
  ST.refs = null; ST.people = null; ST.students = null;   // bo'lim har ochilganda ma'lumotnomalar yangidan (boshqa foydalanuvchi qo'shgan kontragent va h.k.)
  $('#view').innerHTML = `<div class="page-head"><h2>Kassa</h2><div class="ph-actions" id="ks-actions"></div></div><div id="ks-body"><div class="card"><div class="loading">Yuklanmoqda…</div></div></div>`;
  await reload();
}
async function reload() {
  const body = $('#ks-body'); if (!body) return;
  try { await Promise.all([loadOverview(), loadRefs()]); }
  catch (e) { body.innerHTML = `<div class="card"><div class="empty">Kassa ma’lumotini o‘qib bo‘lmadi: ${esc(errText(e))}</div></div>`; return; }
  if (!$('#ks-body')) return;                    // boshqa bo'limga o'tilgan
  draw();
}
function draw() {
  const s = ST.ov.state, m = me(), od = s.openDay, ld = s.lastDay, started = s.desk && s.desk.started;
  const ready = s.desk && s.desk.startDay && s.desk.openingAmount != null;
  // ---- amallar
  const acts = [];
  const desks = (ST.refs.desks || []);
  if (desks.length > 1 && (m.director || m.list2)) acts.push(`<select id="ks-desk" class="search-inp" style="max-width:170px" title="Kassa">${desks.map(d => `<option value="${esc(d.id)}"${d.id === ST.desk ? ' selected' : ''}>${esc(d.name)}</option>`).join('')}</select>`);
  if (ready && (m.operator || m.director)) acts.push(`<button class="btn gold" id="ks-in">+ Kirim</button>`);
  if (ready && (m.operator || m.director || C.SESSION.role === 'finance_mgr')) acts.push(`<button class="btn ghost2" id="ks-out">+ Chiqim so‘rovi</button>`);
  if (od && (m.operator || m.director || C.SESSION.role === 'finance_mgr')) acts.push(`<button class="btn ghost2" id="ks-close">Kunni yopish</button>`);
  if (od && (m.operator || m.director)) acts.push(`<button class="btn ghost2" id="ks-hand" title="Smena topshirish-qabul (pul sanaladi, kun ochiq qoladi)">Smena topshirish</button>`);
  if (m.director) acts.push(`<button class="btn ghost2" id="ks-set" title="Kassa sozlamalari">⚙ Sozlamalar</button>`);
  $('#ks-actions').innerHTML = acts.join('');

  // ---- ogohlantirishlar
  const warn = [];
  if (s.blockReason) warn.push(['#B42318', '#FDECEC', BLOCK_TXT[s.blockReason] || s.blockReason]);
  if (s.desk && s.desk.isTest) warn.push(['#175CD3', '#E8F1FD', 'Bu — SINOV kassasi: hujjatlari va raqamlari asosiy kassadan alohida, hisobotlarga kirmaydi.']);
  if (!s.kassaGoLive) warn.push(['#B54708', '#FEF3E2', 'Kassa hali «ishga tushirilgan» deb belgilanmagan: naqd o‘quv to‘lovlari kassa orderisiz yozilmoqda' + (m.director ? ' («⚙ Sozlamalar» → ishga tushirish sanasi).' : '.')]);
  if (num(s.pending.toApprove) > 0) warn.push(['#175CD3', '#E8F1FD', `Sizning tasdig‘ingizni kutayotgan so‘rovlar: ${s.pending.toApprove} ta.`]);
  if (num(s.pending.toPay) > 0 && (m.operator || m.director)) warn.push(['#175CD3', '#E8F1FD', `Tasdiqlangan, pul berilishi / qabul qilinishi kerak: ${s.pending.toPay} ta (${som(s.pending.toPaySum)}).`]);
  if (num(s.unverifiedDays) > 0 && (m.list2 || m.director)) warn.push(['#B54708', '#FEF3E2', `Tekshirilmagan (yopilgan) kunlar: ${s.unverifiedDays} ta.`]);
  if (num(s.undecidedShortages) > 0) warn.push(['#B42318', '#FDECEC', `Qarori kutilayotgan kamomad: ${s.undecidedShortages} ta${m.director ? ' — pastda qaror qabul qiling.' : ' (Direktor qarori).'}`]);
  if (s.limit && s.limit.exceeded) warn.push(['#B54708', '#FEF3E2', `Kassa qoldig‘i limitdan (${som(s.limit.cashLimit)}) oshgan — ortiqchasini bankka topshiring.`]);
  const warnHtml = warn.map(w => `<div class="small" style="margin-bottom:8px;color:${w[0]};background:${w[1]};border-radius:10px;padding:10px 12px;font-weight:600">${esc(w[2])}</div>`).join('');

  // ---- kun kartasi
  let top;
  if (!ready) {
    top = `<div class="card"><div class="empty">Kassa hali ishga tushirilmagan.<br><span class="small muted">Birinchi kassa kunidan oldin komissiya kassadagi pulni sanaydi va Direktor shu summani boshlang‘ich qoldiq sifatida kiritadi.</span>
      ${m.director ? '<div style="margin-top:12px"><button class="btn gold" id="ks-opening">Boshlang‘ich qoldiqni kiritish</button></div>' : ''}</div></div>`;
  } else {
    const d = od || ld;
    const opening = od ? od.opening : (ld ? ld.closing : s.desk.openingAmount);
    const rec = od ? od.receiptsLive : 0, pay = od ? od.payoutsLive : 0;
    top = `<div class="acc-kpis">
      <div class="acc-kpi teal"><div><div class="k-l">${od ? 'Kun boshi' : 'Oxirgi qoldiq'}</div><div class="k-v">${esc(som(opening))}</div><div class="k-d">${od ? esc(dmy(od.day)) + ' · ' + DAY_LBL.open : (ld ? esc(dmy(ld.day)) + ' · ' + (DAY_LBL[ld.status] || '') : 'boshlang‘ich qoldiq')}</div></div></div>
      <div class="acc-kpi pos"><div><div class="k-l">Kirim</div><div class="k-v">${esc(som(rec))}</div><div class="k-d">${od ? 'bugungi ochiq kun' : 'ochiq kun yo‘q'}</div></div></div>
      <div class="acc-kpi neg"><div><div class="k-l">Chiqim</div><div class="k-v">${esc(som(pay))}</div><div class="k-d">${od ? esc(String(od.docs)) + ' ta hujjat' + (num(od.voids) ? ', ' + od.voids + ' tasi bekor' : '') : '—'}</div></div></div>
      <div class="acc-kpi gold"><div><div class="k-l">Kassadagi qoldiq</div><div class="k-v">${esc(som(s.balance))}</div><div class="k-d">${od && od.cashierUid ? 'kassir: ' + esc(nameOf(od.cashierUid)) : (!started && m.director ? '<a href="#" id="ks-opening">boshlang‘ich qoldiqni o‘zgartirish</a>' : '&nbsp;')}</div></div></div>
    </div>`;
  }

  // ---- bugungi hujjatlar
  const docs = ST.ov.docs || [];
  const docRows = docs.map(d => {
    const canVoid = od && d.status === 'posted' && !d.isSystem && (!d.sourceTable || d.op === 'in_tuition') && (m.director || m.list2 || (m.operator && d.postedBy === m.uid));
    const isIn = d.form === 'KO1';
    return `<tr${d.status === 'void' ? ' style="opacity:.55"' : ''}>
      <td data-label="№"><b>${isIn ? 'K' : 'Ch'}-${esc(String(d.no))}</b><div class="small muted">${esc(hm(d.postedAt))}</div></td>
      <td data-label="Operatsiya">${esc(opName(d.op))}${d.late ? ' ' + chip('kech', '#B54708', '#FEF3E2') : ''}${d.fiscalExempt ? ' ' + chip('fiskal cheksiz', '#B42318', '#FDECEC') : ''}<div class="small muted">${esc((d.lines || []).filter(l => l.cash).map(l => (isIn ? l.credit : l.debit) + (l.articleId ? ' · ' + l.articleId : '')).filter((v, i, a) => a.indexOf(v) === i).join(', '))}</div></td>
      <td data-label="${isIn ? 'Kimdan' : 'Kimga'}">${esc(d.partyName || '—')}<div class="small muted">${esc(d.basis || '')}</div></td>
      <td data-label="Kirim" style="text-align:right;white-space:nowrap">${isIn ? (d.status === 'void' ? '<s>' + esc(som(d.amount)) + '</s>' : '<b>' + esc(som(d.amount)) + '</b>') : ''}</td>
      <td data-label="Chiqim" style="text-align:right;white-space:nowrap">${!isIn ? (d.status === 'void' ? '<s>' + esc(som(d.amount)) + '</s>' : '<b>' + esc(som(d.amount)) + '</b>') : ''}</td>
      <td data-label="Holat">${stChip(d.status)}${d.status === 'void' && d.voidReason ? `<div class="small muted">${esc(d.voidReason)}</div>` : ''}<div class="small muted">${d.isSystem ? 'tizim' : esc(nameOf(d.postedBy))}</div></td>
      <td data-label="" style="white-space:nowrap"><button class="btn sm" data-print="${esc(d.id)}" title="Orderni chop etish">🖨</button>${canVoid ? ` <button class="btn sm danger" data-void="${esc(d.id)}">Bekor</button>` : ''}</td></tr>`;
  }).join('');
  const docsHtml = ready ? `<div class="card" style="padding:14px 18px;margin-bottom:14px"><div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:8px"><b>${od ? 'Ochiq kun hujjatlari — ' + esc(dmy(od.day)) : 'Ochiq kun yo‘q'}</b>${od ? `<button class="btn sm" data-book="${esc(od.day)}">🖨 Kassa kitobi varag‘i (qoralama)</button>` : ''}</div>
    ${docs.length ? `<div class="tablewrap"><table><thead><tr><th>№</th><th>Operatsiya</th><th>Kimdan / kimga</th><th style="text-align:right">Kirim</th><th style="text-align:right">Chiqim</th><th>Holat</th><th></th></tr></thead><tbody>${docRows}</tbody></table></div>`
      : `<div class="empty">${od ? 'Bu kunda hali hujjat yo‘q.' : 'Birinchi hujjat bilan yangi kun ochiladi (kun boshi = oxirgi qoldiq).'}</div>`}</div>` : '';

  // ---- so'rovlar
  const reqs = ST.ov.requests || [];
  const reqRows = reqs.map(d => {
    const mine = d.requestedBy === m.uid;
    const canAppr = d.status === 'draft' && ((m.list2 && d.needsList2 && !d.approvedBy && !mine) || (m.director && d.needsDirector && !d.dirApprovedBy));
    const canRej = d.status === 'draft' && (m.list2 || m.director);
    const canPay = d.status === 'approved' && (m.operator || m.director) && !d.sourceTable;
    const canCancel = mine || m.director;
    const need = [];
    if (d.needsList2) need.push(d.approvedBy ? '✓ moliya: ' + nameOf(d.approvedBy) : '… moliya (2-ro‘yxat) tasdig‘i');
    if (d.needsDirector) need.push(d.dirApprovedBy ? '✓ Direktor' : '… Direktor tasdig‘i');
    return `<tr>
      <td data-label="Tur">${d.form === 'KO1' ? 'Kirim' : 'Chiqim'}<div class="small muted">${esc(dmy(String(d.requestedAt || d.createdAt).slice(0, 10)))}</div></td>
      <td data-label="Operatsiya">${esc(opName(d.op))}<div class="small muted">${esc((d.lines || []).map(l => artName(l.articleId)).filter((v, i, a) => v && a.indexOf(v) === i).join('; '))}</div></td>
      <td data-label="${d.form === 'KO1' ? 'Kimdan' : 'Kimga'}">${esc(d.partyName || '—')}<div class="small muted">${esc(d.basis || (d.noBasis ? 'asos hujjatisiz' : ''))}</div></td>
      <td data-label="Summa" style="text-align:right;white-space:nowrap"><b>${esc(som(d.amount))}</b></td>
      <td data-label="Holat">${stChip(d.status)}<div class="small muted">so‘radi: ${esc(nameOf(d.requestedBy))}</div><div class="small muted">${esc(need.join(' · '))}</div></td>
      <td data-label="" style="white-space:nowrap">${canAppr ? `<button class="btn sm gold" data-appr="${esc(d.id)}">Tasdiqlash</button> ` : ''}${canPay ? `<button class="btn sm gold" data-pay="${esc(d.id)}">${d.form === 'KO1' ? 'Qabul qilish' : 'Pulni berish'}</button> ` : ''}${canRej ? `<button class="btn sm danger" data-rej="${esc(d.id)}">Rad etish</button> ` : ''}${canCancel ? `<button class="btn sm" data-cancel="${esc(d.id)}">Bekor qilish</button>` : ''}</td></tr>`;
  }).join('');
  const reqHtml = reqs.length ? `<div class="card" style="padding:14px 18px;margin-bottom:14px"><b>So‘rovlar (pul hali berilmagan / qabul qilinmagan)</b><div class="small muted" style="margin:2px 0 8px">Chiqim faqat tasdiqdan keyin beriladi: 2-ro‘yxat (Moliya menejeri / buxgalter), ${esc(som(s.t1))}dan katta summada — Direktor ham.</div>
    <div class="tablewrap"><table><thead><tr><th>Tur</th><th>Operatsiya</th><th>Kimdan / kimga</th><th style="text-align:right">Summa</th><th>Holat</th><th></th></tr></thead><tbody>${reqRows}</tbody></table></div></div>` : '';

  // ---- kamomadlar (Direktor qarori)
  const sh = ST.ov.shortages || [];
  const shHtml = sh.length ? `<div class="card" style="padding:14px 18px;margin-bottom:14px"><b>Qarori kutilayotgan kamomadlar</b>
    <div class="tablewrap"><table><thead><tr><th>Kun</th><th>Hujjat</th><th>Kassir</th><th style="text-align:right">Summa</th><th></th></tr></thead><tbody>${sh.map(x => `<tr>
      <td data-label="Kun">${esc(dmy(x.day))}</td><td data-label="Hujjat">Ch-${esc(String(x.no))}</td><td data-label="Kassir">${esc(nameOf(x.cashierUid))}</td>
      <td data-label="Summa" style="text-align:right"><b>${esc(som(x.amount))}</b></td>
      <td data-label="">${m.director ? `<button class="btn sm gold" data-decide="${esc(x.id)}">Qaror</button>` : '<span class="small muted">Direktor qarori</span>'}</td></tr>`).join('')}</tbody></table></div></div>` : '';

  // ---- kunlar
  const days = ST.ov.days || [];
  const lastId = days.length ? days[0].id : null;
  const dayRows = days.map(d => {
    const closed = d.status !== 'open';
    return `<tr>
      <td data-label="Kun"><b>${esc(dmy(d.day))}</b>${num(d.reopenCount) ? `<div class="small muted">qayta ochilgan: ${esc(String(d.reopenCount))}</div>` : ''}</td>
      <td data-label="Kun boshi" style="text-align:right">${esc(som(d.opening))}</td>
      <td data-label="Kirim" style="text-align:right">${esc(som(closed ? d.receipts : d.receiptsLive))}</td>
      <td data-label="Chiqim" style="text-align:right">${esc(som(closed ? d.payouts : d.payoutsLive))}</td>
      <td data-label="Kun oxiri" style="text-align:right"><b>${esc(som(closed ? d.closing : d.balance))}</b></td>
      <td data-label="Farq" style="text-align:right">${closed ? (num(d.diff) === 0 ? '—' : `<span style="color:${num(d.diff) < 0 ? '#B42318' : '#B54708'};font-weight:700">${num(d.diff) > 0 ? '+' : ''}${esc(som(d.diff))}</span>`) : ''}</td>
      <td data-label="Holat">${dayChip(d.status)}<div class="small muted">${closed ? 'yopdi: ' + esc(nameOf(d.closedBy)) : 'kassir: ' + esc(nameOf(d.cashierUid))}${d.status === 'verified' ? '<br>tekshirdi: ' + esc(nameOf(d.verifiedBy)) : ''}</div></td>
      <td data-label="" style="white-space:nowrap"><button class="btn sm" data-view="${esc(d.day)}" title="Kun hujjatlari, sanashlar, jurnal">Ko‘rish</button> <button class="btn sm" data-book="${esc(d.day)}" title="Kassa kitobi varag‘i (KO-4)">🖨 KO-4</button>${d.status === 'closed' && (m.list2 || m.director) ? ` <button class="btn sm gold" data-verify="${esc(d.day)}">Tekshirish</button>` : ''}${d.status === 'closed' && m.director && d.id === lastId ? ` <button class="btn sm danger" data-reopen="${esc(d.day)}">Qayta ochish</button>` : ''}</td></tr>`;
  }).join('');
  const daysHtml = days.length ? `<div class="card" style="padding:14px 18px"><b>Kassa kunlari</b><div class="small muted" style="margin:2px 0 8px">Kun oxiri = kun boshi + kirim − chiqim. Kun faqat pul sanalgach yopiladi; farq shu kunning hujjati bo‘lib yoziladi.</div>
    <div class="tablewrap"><table><thead><tr><th>Kun</th><th style="text-align:right">Kun boshi</th><th style="text-align:right">Kirim</th><th style="text-align:right">Chiqim</th><th style="text-align:right">Kun oxiri</th><th style="text-align:right">Farq</th><th>Holat</th><th></th></tr></thead><tbody>${dayRows}</tbody></table></div></div>` : '';

  $('#ks-body').innerHTML = warnHtml + top + docsHtml + reqHtml + shHtml + daysHtml;
  bind();
}
function bind() {
  const on = (sel, fn) => { const el = $(sel); if (el) el.onclick = fn; };
  const each = (attr, fn) => $('#ks-body').querySelectorAll('[' + attr + ']').forEach(b => { b.onclick = ev => { ev.preventDefault(); fn(b.getAttribute(attr), b); }; });
  on('#ks-in', () => openDocForm('KO1'));
  on('#ks-out', () => openDocForm('KO2'));
  on('#ks-close', openCloseForm);
  on('#ks-hand', openHandoverForm);
  on('#ks-set', openSettings);
  on('#ks-opening', ev => { if (ev && ev.preventDefault) ev.preventDefault(); openOpeningForm(); });
  const ds = $('#ks-desk'); if (ds) ds.onchange = () => { ST.desk = ds.value; reload(); };
  each('data-void', id => ask('Hujjatni bekor qilish', 'Bekor qilish sababi (kamida 5 belgi). Hujjat raqami saqlanadi va «bekor qilingan» deb belgilanadi.', 5, r => act('kassa_doc_void', { p_id: id, p_reason: r }, 'Hujjat bekor qilindi')));
  each('data-appr', id => { if (confirm('Bu so‘rov tasdiqlansinmi?')) act('kassa_doc_approve', { p_id: id }, 'Tasdiqlandi'); });
  each('data-rej', id => ask('So‘rovni rad etish', 'Rad etish sababi', 3, r => act('kassa_doc_reject', { p_id: id, p_reason: r }, 'Rad etildi')));
  each('data-cancel', id => ask('So‘rovni bekor qilish', 'Sababi', 3, r => act('kassa_doc_cancel', { p_id: id, p_reason: r }, 'So‘rov bekor qilindi')));
  each('data-pay', (id, b) => { const d = (ST.ov.requests || []).find(x => x.id === id); if (!d) return;
    if (!confirm(`${d.form === 'KO1' ? 'Pul QABUL QILINDI' : 'Pul BERILDI'} deb belgilansinmi?\n\n${opName(d.op)} — ${d.partyName || ''}\n${som(d.amount)}\n\nHujjatga raqam beriladi va kassa qoldig‘i o‘zgaradi.`)) return;
    b.disabled = true; act('kassa_doc_pay', { p_id: id }, d.form === 'KO1' ? 'Kirim o‘tkazildi' : 'Chiqim o‘tkazildi', r => offerPrint(r)); });
  each('data-print', id => printDoc(id));
  each('data-book', day => printBook(day));
  each('data-view', day => openDayView(day));
  each('data-verify', day => openVerifyForm(day));
  each('data-reopen', day => ask('Kunni qayta ochish — ' + dmy(day), 'Sababi (kamida 5 belgi). Sanash farqi hujjati bekor bo‘ladi, kun qayta sanab yopiladi.', 5, r => act('kassa_day_reopen', { p_desk: ST.desk, p_day: day, p_reason: r }, 'Kun qayta ochildi')));
  each('data-decide', id => openDecideForm(id));
}
// Server amali: bajaradi, xabar beradi, sahifani yangilaydi. Xato — serverning o'zbekcha matni bilan.
async function act(fn, args, okMsg, after) {
  try { const r = await call(fn, args); C.toast(okMsg + (r && r.dup ? ' (avval bajarilgan)' : '') + ' ✓'); C.closeModal(); await reload(); if (after) after(r); if (C.onChange) C.onChange(); return r; }
  catch (e) { C.toast(errText(e), true); await reload().catch(() => {}); return null; }
}
// Sabab so'raydigan kichik oyna.
function ask(title, hint, minLen, onOk) {
  $('#modal').innerHTML = `<div class="modal-h"><h3>${esc(title)}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small muted">${esc(hint)}</div><textarea id="ks-reason" rows="3" style="${FLD};margin-top:8px"></textarea></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button><button type="button" class="btn gold" id="ks-ok">Tasdiqlash</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  $('#ks-ok').onclick = () => { const r = $('#ks-reason').value.trim(); if (r.length < minLen) { C.toast(`Sabab kamida ${minLen} belgi bo‘lsin`, true); return; } $('#ks-ok').disabled = true; onOk(r); };
  setTimeout(() => { const t = $('#ks-reason'); if (t) t.focus(); }, 50);
}
function offerPrint(r) { if (r && r.id && r.status === 'posted' && confirm('Order chop etilsinmi?')) printDoc(r.id); }

// ---------------------------------------------------------------- kirim / chiqim shakli
async function openDocForm(form) {
  const refs = ST.refs, m = me();
  const ops = (refs.rules || []).filter(r => r.form === form && r.manual && !r.systemOnly);
  if (!ops.length) { C.toast('Bu turdagi operatsiya yo‘q', true); return; }
  const isOut = form === 'KO2';
  $('#modal').innerHTML = `<div class="modal-h"><h3>${isOut ? 'Chiqim so‘rovi (KO-2)' : 'Kirim orderi (KO-1)'}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      ${lbl('Operatsiya', `<select id="kf-op" style="${FLD}">${ops.map(r => `<option value="${esc(r.op)}">${esc(r.nameUz)}</option>`).join('')}</select>`, ';margin-top:0')}
      <div id="kf-dyn"></div>
      <div class="small muted" id="kf-hint" style="margin-top:10px"></div>
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kf-save">${isOut ? 'So‘rov yuborish' : 'Qabul qilish'}</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const F = { party: null, lines: [{ articleId: '', amount: '', note: '' }] };
  const drawDyn = async () => {
    const r = ops.find(x => x.op === $('#kf-op').value);
    const types = r.partyTypes || [];
    const multi = r.op === 'out_expense';
    const arts = r.articleMode === 'choose' ? (refs.articles || []).filter(a => (r.allowedArticles || []).length ? r.allowedArticles.includes(a.id) : a.cashOutAllowed) : [];
    const artSel = (i, v) => `<select data-art="${i}" style="${FLD}"><option value="">— statiya —</option>${arts.map(a => `<option value="${esc(a.id)}"${a.id === v ? ' selected' : ''}>${esc(a.id + ' · ' + a.nameUz)}</option>`).join('')}</select>`;
    $('#kf-dyn').innerHTML = `
      ${types.length ? lbl(isOut ? 'Kimga' : 'Kimdan', `${types.length > 1 ? `<select id="kf-ptype" style="${FLD}">${types.map(t => `<option value="${t}">${esc(PARTY_LBL[t] || t)}</option>`).join('')}</select>` : `<input type="hidden" id="kf-ptype" value="${esc(types[0])}">`}<div id="kf-party"></div>`) : ''}
      ${r.articleMode === 'choose' && !multi ? lbl('Statiya', artSel(0, F.lines[0].articleId)) : ''}
      ${multi ? `<div class="small" style="font-weight:700;margin-top:10px">Statiya va summa <span class="muted" style="font-weight:500">— bir hujjatda bir nechta statiya bo‘lishi mumkin</span></div><div id="kf-lines"></div><button type="button" class="btn sm" id="kf-addline" style="margin-top:6px">+ qator</button>`
        : lbl('Summa (so‘m)', `<input id="kf-amt" type="text" inputmode="numeric" placeholder="0" style="${FLD}">`)}
      ${lbl('Asos <span class="muted" style="font-weight:500">— hujjat nomi, raqami, sanasi</span>', `<input id="kf-basis" type="text" maxlength="300" style="${FLD}">`)}
      ${r.op === 'out_expense' ? `<label class="small" style="display:flex;gap:8px;align-items:center;margin-top:8px"><input type="checkbox" id="kf-nobasis"> Asos hujjati yo‘q (bozordan naqd xarid) — faqat ${esc(som(ST.ov.state.l1))}gacha va bitta statiya</label>` : ''}
      ${lbl('Ilova <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<input id="kf-attach" type="text" maxlength="300" style="${FLD}">`)}
      ${lbl('Izoh' + (r.op === 'in_other' ? ' <span style="color:#B42318">(majburiy)</span>' : ''), `<input id="kf-note" type="text" maxlength="300" style="${FLD}">`)}
      ${r.fiscalRequired ? lbl('Fiskal chek № <span style="color:#B42318">(majburiy)</span>', `<input id="kf-fiscal" type="text" maxlength="40" style="${FLD}">`) + (m.director ? `<label class="small" style="display:flex;gap:8px;align-items:center;margin-top:6px"><input type="checkbox" id="kf-fexempt"> Fiskal cheksiz (istisno — jurnalga yoziladi)</label>` : '') : ''}`;
    fmtInput($('#kf-amt'));
    const hint = [];
    if (r.needsApproval) hint.push('Pul berishdan oldin Moliya menejeri / buxgalter tasdiqlaydi' + (r.directorAlways ? ', Direktor ham' : `; ${som(ST.ov.state.t1)}dan katta summada — Direktor ham`) + '.');
    else if (r.directorAlways) hint.push('Avval Direktor ruxsat beradi, keyin kassir pulni qabul qiladi.');
    else if (!isOut) hint.push('Order darhol o‘tkaziladi: raqam va sana serverdan beriladi.');
    $('#kf-hint').textContent = hint.join(' ');
    if (multi) {
      const drawLines = () => {
        $('#kf-lines').innerHTML = F.lines.map((l, i) => `<div style="display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr) auto;gap:6px;margin-top:6px">${artSel(i, l.articleId)}<input data-lamt="${i}" type="text" inputmode="numeric" placeholder="summa" value="${esc(l.amount)}" style="${FLD}">${F.lines.length > 1 ? `<button type="button" class="btn sm danger" data-ldel="${i}">×</button>` : '<span></span>'}</div>`).join('')
          + `<div class="small muted" style="margin-top:6px">Jami: <b id="kf-total">0</b></div>`;
        const total = () => { $('#kf-total').textContent = som(F.lines.reduce((s, l) => s + num(digits(l.amount)), 0)); };
        $('#kf-lines').querySelectorAll('[data-art]').forEach(el => el.onchange = () => { F.lines[Number(el.dataset.art)].articleId = el.value; });
        $('#kf-lines').querySelectorAll('[data-lamt]').forEach(el => { fmtInput(el); el.addEventListener('input', () => { F.lines[Number(el.dataset.lamt)].amount = el.value; total(); }); });
        $('#kf-lines').querySelectorAll('[data-ldel]').forEach(el => el.onclick = () => { F.lines.splice(Number(el.dataset.ldel), 1); drawLines(); });
        total();
      };
      drawLines(); $('#kf-addline').onclick = () => { if (F.lines.length < 20) { F.lines.push({ articleId: '', amount: '', note: '' }); drawLines(); } };
    } else { const a0 = $('#kf-dyn').querySelector('[data-art="0"]'); if (a0) a0.onchange = () => { F.lines[0].articleId = a0.value; }; }
    const pt = $('#kf-ptype'); if (pt) { pt.onchange = () => drawParty(pt.value); await drawParty(pt.value); }
  };
  const drawParty = async type => {
    F.party = { type, id: '', name: '' };
    const box = $('#kf-party'); if (!box) return;
    if (type === 'student') {
      box.innerHTML = `<input id="kf-ps" type="text" placeholder="O‘quvchi: ism yoki ID…" autocomplete="off" style="${FLD};margin-top:6px"><div id="kf-pl" style="max-height:150px;overflow:auto;margin-top:4px"></div><div id="kf-psel" class="small muted"></div><input id="kf-payer" type="text" placeholder="To‘lovchi (ota-ona) F.I.Sh. — ixtiyoriy" maxlength="200" style="${FLD};margin-top:6px">`;
      const list = await loadStudents().catch(() => []);
      const drawL = q => { q = String(q || '').trim().toLowerCase(); if (!q) { $('#kf-pl').innerHTML = ''; return; }
        $('#kf-pl').innerHTML = list.filter(s => String(s.name || '').toLowerCase().includes(q) || String(s.studentId || s._id || '').toLowerCase().includes(q)).slice(0, 20)
          .map(s => { const sid = s.studentId || s._id; return `<div data-sid="${esc(sid)}" style="padding:6px 8px;border:1px solid var(--border-2);border-radius:7px;margin-bottom:4px;cursor:pointer"><b>${esc(s.name || '')}</b> <span class="small muted">${esc(sid)}</span></div>`; }).join('') || '<div class="small muted">Topilmadi.</div>';
        $('#kf-pl').querySelectorAll('[data-sid]').forEach(el => el.onclick = () => { const s = list.find(x => String(x.studentId || x._id) === el.dataset.sid) || {}; F.party.id = el.dataset.sid; $('#kf-psel').innerHTML = `✓ <b>${esc(s.name || el.dataset.sid)}</b> tanlandi`; $('#kf-pl').innerHTML = ''; $('#kf-ps').value = s.name || el.dataset.sid; }); };
      $('#kf-ps').addEventListener('input', e => { F.party.id = ''; $('#kf-psel').textContent = ''; drawL(e.target.value); });
    } else if (type === 'employee') {
      box.innerHTML = `<div class="small muted" style="margin-top:6px">Yuklanmoqda…</div>`;
      const ppl = await loadPeople().catch(() => []);
      box.innerHTML = `<select id="kf-pe" style="${FLD};margin-top:6px"><option value="">— xodim —</option>${ppl.map(p => `<option value="${esc(p.ref)}">${esc(p.name + (p.pos ? ' · ' + p.pos : ''))}</option>`).join('')}</select>`;
      $('#kf-pe').onchange = () => { F.party.id = $('#kf-pe').value; };
    } else if (type === 'other') {
      box.innerHTML = `<input id="kf-po" type="text" placeholder="F.I.Sh. yoki nomi (to‘liq)" maxlength="200" style="${FLD};margin-top:6px"><div class="small muted" style="margin-top:4px">«Boshqa» tomonlar nazorat ro‘yxatida alohida ko‘rinadi — imkon bo‘lsa kontragentni tanlang.</div>`;
      $('#kf-po').addEventListener('input', () => { F.party.name = $('#kf-po').value.trim(); });
    } else {
      const want = k => type === 'bank' ? k === 'bank' : type === 'founder' ? k === 'founder' : (k !== 'bank' && k !== 'founder');
      const drawC = sel => { const cps = (ST.refs.counterparties || []).filter(c => want(c.kind));
        box.innerHTML = `<div style="display:flex;gap:6px;margin-top:6px"><select id="kf-pc" style="${FLD}"><option value="">— ${esc(PARTY_LBL[type] || type)} —</option>${cps.map(c => `<option value="${esc(c.id)}"${c.id === sel ? ' selected' : ''}>${esc(c.name + (c.stir ? ' · STIR ' + c.stir : ''))}</option>`).join('')}</select><button type="button" class="btn sm" id="kf-pnew" title="Yangi qo‘shish">+ yangi</button></div><div id="kf-pnewbox"></div>`;
        F.party.id = sel || '';
        $('#kf-pc').onchange = () => { F.party.id = $('#kf-pc').value; };
        $('#kf-pnew').onclick = () => {
          const kinds = type === 'bank' ? ['bank'] : type === 'founder' ? ['founder'] : ['supplier', 'org', 'person', 'other'];
          $('#kf-pnewbox').innerHTML = `<div style="border:1px dashed var(--border);border-radius:10px;padding:8px;margin-top:6px"><input id="kf-cn" type="text" placeholder="Nomi (to‘liq)" maxlength="200" style="${FLD}"><div style="display:flex;gap:6px;margin-top:6px"><select id="kf-ck" style="${FLD}">${kinds.map(k => `<option value="${k}">${esc(CP_KIND[k])}</option>`).join('')}</select><input id="kf-cs" type="text" inputmode="numeric" placeholder="STIR (ixtiyoriy)" maxlength="14" style="${FLD}"><button type="button" class="btn sm gold" id="kf-cadd">Qo‘shish</button></div></div>`;
          $('#kf-cadd').onclick = async () => { const nm = $('#kf-cn').value.trim(); if (nm.length < 2) { C.toast('Nomini yozing', true); return; }
            try { const c = await call('fin_counterparty_save', { p_id: null, p_kind: $('#kf-ck').value, p_name: nm, p_stir: digits($('#kf-cs').value) }); await loadRefs(true); drawC(c.id); C.toast('Qo‘shildi ✓'); }
            catch (e) { C.toast(errText(e), true); } };
        }; };
      drawC('');
    }
  };
  $('#kf-op').onchange = () => { F.lines = [{ articleId: '', amount: '', note: '' }]; drawDyn(); };
  await drawDyn();
  let busy = false;
  $('#kf-save').onclick = async () => {
    if (busy) return;
    const r = ops.find(x => x.op === $('#kf-op').value), multi = r.op === 'out_expense';
    const p = { desk: ST.desk, op: r.op, clientRef: F.ref || (F.ref = newRef()), basis: $('#kf-basis').value.trim(), attachment: $('#kf-attach').value.trim(), note: $('#kf-note').value.trim() };
    if ((r.partyTypes || []).length) {
      const t = F.party && F.party.type; p.partyType = t;
      if (t === 'other') { p.partyName = (F.party.name || '').trim(); if (p.partyName.length < 3) { C.toast('Kimdan / kimga — to‘liq yozing', true); return; } }
      else { p.partyId = F.party && F.party.id; if (!p.partyId) { C.toast((isOut ? 'Kimga' : 'Kimdan') + ' — tanlang', true); return; } if (t === 'student') { const py = $('#kf-payer'); if (py && py.value.trim()) p.partyName = py.value.trim(); } }
    }
    if (multi) {
      const ls = F.lines.map(l => ({ articleId: l.articleId, amount: num(digits(l.amount)) })).filter(l => l.articleId || l.amount);
      if (!ls.length || ls.some(l => !l.articleId || !(l.amount > 0))) { C.toast('Har qatorda statiya va summa bo‘lsin', true); return; }
      p.lines = ls; p.amount = ls.reduce((s, l) => s + l.amount, 0);
      if ($('#kf-nobasis') && $('#kf-nobasis').checked) p.noBasis = true;
    } else {
      p.amount = num(digits($('#kf-amt').value));
      if (r.articleMode === 'choose') { p.articleId = F.lines[0].articleId; if (!p.articleId) { C.toast('Statiyani tanlang', true); return; } }
    }
    if (!(p.amount > 0)) { C.toast('Summani kiriting', true); return; }
    if (!p.noBasis && p.basis.length < 3) { C.toast('Asosni yozing (hujjat nomi, raqami, sanasi)', true); return; }
    if (r.fiscalRequired) { const fx = $('#kf-fexempt'); p.fiscalNo = $('#kf-fiscal').value.trim(); if (!p.fiscalNo) { if (fx && fx.checked) p.fiscalExempt = true; else { C.toast('Fiskal chek raqamini kiriting', true); return; } } }
    busy = true; const btn = $('#kf-save'); btn.disabled = true; btn.textContent = 'Yuborilmoqda…';
    try {
      const res = await call(isOut ? 'kassa_payout_request' : 'kassa_receipt', { p });
      C.closeModal();
      if (res.status === 'posted') { C.toast(`Kirim orderi № ${res.no} o‘tkazildi ✓`); await reload(); offerPrint(res); }
      else { C.toast('So‘rov yuborildi — tasdiq kutilmoqda ✓'); await reload(); }
      if (C.onChange) C.onChange();
    } catch (e) { busy = false; btn.disabled = false; btn.textContent = isOut ? 'So‘rov yuborish' : 'Qabul qilish'; C.toast(errText(e), true); }
  };
}

// ---------------------------------------------------------------- sanash: kunni yopish / smena topshirish
function countFields(expected, pend) {
  return `<div class="small" style="background:#eef3f1;border-radius:10px;padding:10px 12px">Hisobdagi qoldiq: <b>${esc(som(expected))}</b></div>
    ${lbl('Kassadagi pul — SANALGAN summa (so‘m)', `<input id="kc-counted" type="text" inputmode="numeric" placeholder="0" style="${FLD}">`)}
    <details style="margin-top:8px"><summary class="small" style="cursor:pointer;font-weight:700">Nominallar bo‘yicha sanash</summary>
      <div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px;margin-top:6px">${NOMINALS.map(n => `<label class="small muted" style="display:flex;flex-direction:column;gap:3px">${n.toLocaleString('ru-RU')}<input data-nom="${n}" type="text" inputmode="numeric" placeholder="dona" style="padding:6px 8px;border:1px solid var(--border);border-radius:8px;font:inherit;width:100%"></label>`).join('')}</div></details>
    <div class="grid2" style="margin-top:4px">${lbl('Hali o‘tkazilmagan yozuvlar — soni', `<input id="kc-pcount" type="text" inputmode="numeric" value="${esc(String(pend.count || ''))}" placeholder="0" style="${FLD}">`)}${lbl('…summasi (so‘m)', `<input id="kc-psum" type="text" inputmode="numeric" value="${pend.sum ? esc(String(pend.sum).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')) : ''}" placeholder="0" style="${FLD}">`)}</div>
    <div class="small muted">Internet yo‘qligida qabul qilingan, hali serverga yetmagan naqd to‘lovlar (shu qurilma navbatida: ${esc(String(pend.count || 0))} ta). Ular kassada bor, lekin hisobda hali yo‘q.</div>
    <div id="kc-diff" class="small" style="margin-top:8px;font-weight:700"></div>
    ${lbl('Izoh', `<input id="kc-note" type="text" maxlength="300" style="${FLD}">`)}`;
}
function countBind(expected) {
  const counted = $('#kc-counted'); fmtInput(counted); fmtInput($('#kc-psum'));
  const noms = () => { const o = {}; let sum = 0, any = false; $('#modal').querySelectorAll('[data-nom]').forEach(el => { const c = num(digits(el.value)); if (c > 0) { o[el.dataset.nom] = c; sum += c * Number(el.dataset.nom); any = true; } }); return { o, sum, any }; };
  const upd = () => { const c = num(digits(counted.value)), p = num(digits($('#kc-psum').value)), d = c - expected - p; const el = $('#kc-diff');
    if (!digits(counted.value)) { el.textContent = ''; return; }
    el.style.color = d === 0 ? '#157347' : (d < 0 ? '#B42318' : '#B54708');
    el.textContent = d === 0 ? 'Farq yo‘q ✓' : (d < 0 ? `KAMOMAD: ${som(-d)} — shu kun sanasi bilan chiqim hujjati yoziladi (qaror — Direktor)` : `ORTIQCHA: ${som(d)} — shu kun sanasi bilan kirim hujjati yoziladi`); };
  $('#modal').querySelectorAll('[data-nom]').forEach(el => el.addEventListener('input', () => { el.value = digits(el.value); const n = noms(); if (n.any) counted.value = String(n.sum).replace(/\B(?=(\d{3})+(?!\d))/g, ' '); upd(); }));
  counted.addEventListener('input', upd); $('#kc-psum').addEventListener('input', upd);
  return () => { const n = noms(), c = num(digits(counted.value)); return { counted: digits(counted.value) === '' ? null : c, denoms: n.any && n.sum === c ? n.o : null, pendingCount: num(digits($('#kc-pcount').value)), pendingSum: num(digits($('#kc-psum').value)), note: $('#kc-note').value.trim() }; };
}
const commissionFields = () => `<div class="small" style="font-weight:700;margin-top:10px">Komissiya (kassir o‘rniga yopilganda kamida 2 kishi)</div>${[0, 1, 2].map(i => `<div class="grid2" style="margin-top:6px"><input data-ct="${i}" type="text" placeholder="Lavozimi" maxlength="120" style="${FLD}"><input data-cn="${i}" type="text" placeholder="F.I.Sh." maxlength="200" style="${FLD}"></div>`).join('')}`;
const commissionRead = () => [0, 1, 2].map(i => ({ title: ($('#modal').querySelector(`[data-ct="${i}"]`) || {}).value || '', name: (($('#modal').querySelector(`[data-cn="${i}"]`) || {}).value || '').trim() })).filter(x => x.name.length >= 3);
function openCloseForm() {
  const od = ST.ov.state.openDay, m = me(); if (!od) return;
  const pend = C.outboxCash ? C.outboxCash() : { count: 0, sum: 0 };
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kunni yopish — ${esc(dmy(od.day))}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">${countFields(num(od.balance), pend)}${m.operator ? '' : commissionFields()}
      <div class="small muted" style="margin-top:8px">Yopilgach bu kunga hujjat yozilmaydi (faqat Direktor qayta ochadi). Kassa kitobi varag‘ini 2 nusxada chop eting va imzolang.</div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kc-save">Sanab yopish</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const read = countBind(num(od.balance));
  $('#kc-save').onclick = async () => {
    const v = read(); if (v.counted == null) { C.toast('Sanalgan summani kiriting (0 bo‘lsa — 0)', true); return; }
    if ((v.pendingSum > 0) !== (v.pendingCount > 0)) { C.toast('Hali o‘tkazilmagan yozuvlar: soni va summasi birga kiritiladi', true); return; }
    const p = { desk: ST.desk, day: od.day, counted: v.counted, pendingCount: v.pendingCount, pendingSum: v.pendingSum, note: v.note };
    if (v.denoms) p.denoms = v.denoms;
    if (!m.operator) { p.commission = commissionRead(); if (p.commission.length < 2) { C.toast('Komissiya a’zolarini kiriting (kamida 2 kishi)', true); return; } }
    const d = v.counted - num(od.balance) - v.pendingSum;
    if (!confirm(`Kun yopilsinmi? ${dmy(od.day)}\n\nSanalgan: ${som(v.counted)}\nHisobda: ${som(od.balance)}${v.pendingSum ? '\nHali o‘tkazilmagan: ' + som(v.pendingSum) : ''}\n${d === 0 ? 'Farq yo‘q.' : (d < 0 ? 'KAMOMAD: ' + som(-d) : 'ORTIQCHA: ' + som(d))}`)) return;
    $('#kc-save').disabled = true;
    await act('kassa_day_close', { p }, 'Kun yopildi', () => { if (confirm('Kassa kitobi varag‘i (KO-4) chop etilsinmi?')) printBook(od.day); });
    const b = $('#kc-save'); if (b) b.disabled = false;
  };
}
function openHandoverForm() {
  const od = ST.ov.state.openDay, m = me(); if (!od) return;
  const opsL = (ST.refs.operators || []).filter(o => o.uid !== m.uid);
  const pend = C.outboxCash ? C.outboxCash() : { count: 0, sum: 0 };
  $('#modal').innerHTML = `<div class="modal-h"><h3>Smena topshirish — ${esc(dmy(od.day))}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">${lbl('Qabul qiluvchi kassir', `<select id="kh-to" style="${FLD}"><option value="">— tanlang —</option>${opsL.map(o => `<option value="${esc(o.uid)}">${esc(o.name)}</option>`).join('')}</select>`, ';margin-top:0')}
      ${countFields(num(od.balance), pend)}<div class="small muted" style="margin-top:8px">Pul ikkala kassir ishtirokida sanaladi. Kun ochiq qoladi; farq bo‘lsa darhol hujjat yoziladi.</div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kh-save">Topshirish</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const read = countBind(num(od.balance));
  $('#kh-save').onclick = async () => { const v = read(), to = $('#kh-to').value;
    if (!to) { C.toast('Qabul qiluvchi kassirni tanlang', true); return; }
    if (v.counted == null) { C.toast('Sanalgan summani kiriting', true); return; }
    const p = { desk: ST.desk, counted: v.counted, pendingSum: v.pendingSum, toUid: to, note: v.note }; if (v.denoms) p.denoms = v.denoms;
    $('#kh-save').disabled = true; await act('kassa_handover', { p }, 'Smena topshirildi'); const b = $('#kh-save'); if (b) b.disabled = false; };
}
function openVerifyForm(day) {
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kunni tekshirish — ${esc(dmy(day))}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small muted">Kassa kitobi varag‘i va unga ilova qilingan kirim / chiqim orderlari qog‘ozda qabul qilinadi va tizimdagi yozuvlar bilan solishtiriladi. Tekshirilgan kun endi o‘zgarmaydi.</div>
      <label class="small" style="display:flex;gap:8px;align-items:flex-start;margin-top:10px;font-weight:700"><input type="checkbox" id="kv-papers" style="margin-top:2px"> Qog‘oz hujjatlar va ilovalarni oldim, yozuvlarni tekshirdim</label>
      ${lbl('Izoh', `<input id="kv-note" type="text" maxlength="300" style="${FLD}">`)}</div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kv-save">Tekshirdim</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  $('#kv-save').onclick = async () => { if (!$('#kv-papers').checked) { C.toast('Avval qog‘oz hujjatlar olinganini belgilang', true); return; }
    $('#kv-save').disabled = true; await act('kassa_day_verify', { p_desk: ST.desk, p_day: day, p_papers: true, p_note: $('#kv-note').value.trim() }, 'Kun tekshirildi'); const b = $('#kv-save'); if (b) b.disabled = false; };
}
function openDecideForm(id) {
  const x = (ST.ov.shortages || []).find(s => s.id === id); if (!x) return;
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kamomad bo‘yicha qaror</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small" style="background:#FDECEC;color:#B42318;border-radius:10px;padding:10px 12px;font-weight:700">${esc(dmy(x.day))} · Ch-${esc(String(x.no))} · ${esc(som(x.amount))} · kassir: ${esc(nameOf(x.cashierUid))}</div>
      ${lbl('Qaror', `<select id="kd-dec" style="${FLD}"><option value="employee">Xodim zimmasiga (yozma rozilik yoki to‘liq moddiy javobgarlik bilan)</option><option value="writeoff">Hisobdan chiqarish (aybdor aniqlanmadi)</option></select>`)}
      ${lbl('Asos <span class="muted" style="font-weight:500">— buyruq / tushuntirish xati</span>', `<input id="kd-note" type="text" maxlength="300" style="${FLD}">`)}</div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kd-save">Qarorni saqlash</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  $('#kd-save').onclick = async () => { const n = $('#kd-note').value.trim(); if (n.length < 5) { C.toast('Qaror asosini yozing', true); return; }
    $('#kd-save').disabled = true; await act('kassa_shortage_decide', { p_doc_id: id, p_decision: $('#kd-dec').value, p_note: n }, 'Qaror saqlandi'); const b = $('#kd-save'); if (b) b.disabled = false; };
}
function openOpeningForm() {
  const s = ST.ov.state;
  $('#modal').innerHTML = `<div class="modal-h"><h3>Boshlang‘ich qoldiq</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small muted">Komissiya kassadagi pulni sanaydi (dalolatnoma). Shu summa birinchi kassa kunining «kun boshi» bo‘ladi. Kassa ishga tushgach bu qiymat o‘zgarmaydi.</div>
      <div class="grid2">${lbl('Sanalgan summa (so‘m)', `<input id="ko-amt" type="text" inputmode="numeric" placeholder="0" value="${s.desk.openingAmount != null ? esc(String(num(s.desk.openingAmount)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')) : ''}" style="${FLD}">`)}${lbl('Birinchi kassa kuni', `<input id="ko-day" type="date" value="${esc(s.desk.startDay || s.today)}" style="${FLD}">`)}</div>
      ${commissionFields().replace('Komissiya (kassir o‘rniga yopilganda kamida 2 kishi)', 'Komissiya a’zolari')}
      ${lbl('Izoh', `<input id="ko-note" type="text" maxlength="300" placeholder="masalan: 31.12 sanash dalolatnomasi № 1" style="${FLD}">`)}</div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="ko-save">Saqlash</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal; fmtInput($('#ko-amt'));
  $('#ko-save').onclick = async () => { const a = digits($('#ko-amt').value); if (a === '') { C.toast('Summani kiriting (pul bo‘lmasa — 0)', true); return; }
    if (!$('#ko-day').value) { C.toast('Birinchi kassa kunini tanlang', true); return; }
    $('#ko-save').disabled = true; await act('kassa_opening_set', { p: { desk: ST.desk, amount: num(a), startDay: $('#ko-day').value, note: $('#ko-note').value.trim(), commission: commissionRead() } }, 'Boshlang‘ich qoldiq saqlandi'); const b = $('#ko-save'); if (b) b.disabled = false; };
}
function openSettings() {
  const o = ST.refs.org || {};
  const v = k => esc(o[k] == null ? '' : String(o[k]));
  const nv = k => esc(num(o[k]) ? String(num(o[k])).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') : '');
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kassa sozlamalari</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      ${lbl('Tashkilot nomi (hujjatlarda)', `<input id="kx-name" type="text" maxlength="300" value="${v('nameUz')}" style="${FLD}">`, ';margin-top:0')}
      <div class="grid2">${lbl('STIR', `<input id="kx-stir" type="text" inputmode="numeric" maxlength="14" value="${v('stir')}" style="${FLD}">`)}${lbl('Joy (shahar / tuman)', `<input id="kx-place" type="text" maxlength="200" value="${v('place')}" style="${FLD}">`)}</div>
      ${lbl('Chop etish tili', `<select id="kx-lang" style="${FLD}">${[['uz-cyrl', 'O‘zbek (kirill)'], ['uz-latn', 'O‘zbek (lotin)'], ['ru', 'Rus']].map(x => `<option value="${x[0]}"${o.printLang === x[0] ? ' selected' : ''}>${x[1]}</option>`).join('')}</select>`)}
      <div class="grid2">${lbl('T1 — shundan katta chiqimga Direktor tasdig‘i (0 — har doim)', `<input id="kx-t1" type="text" inputmode="numeric" value="${nv('t1')}" placeholder="0" style="${FLD}">`)}${lbl('L1 — asos hujjatisiz naqd xarid chegarasi (0 — mumkin emas)', `<input id="kx-l1" type="text" inputmode="numeric" value="${nv('l1')}" placeholder="0" style="${FLD}">`)}</div>
      <div class="grid2">${lbl('Kassa limiti (0 — belgilanmagan)', `<input id="kx-limit" type="text" inputmode="numeric" value="${nv('cashLimit')}" placeholder="0" style="${FLD}">`)}${lbl('Kassa ishga tushadigan kun', `<input id="kx-live" type="date" value="${v('kassaGoLive')}" style="${FLD}">`)}</div>
      <div class="small muted" style="margin-top:8px">«Ishga tushadigan kun»dan boshlab har naqd o‘quv to‘lovi kassa kirim orderi bilan yoziladi: fiskal chek raqami majburiy bo‘ladi, naqd pulni faqat kassir qabul qiladi, kecha yopilmagan bo‘lsa to‘lov qabul qilinmaydi. Bo‘sh qoldirilsa — hozirgidek.</div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kx-save">Saqlash</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  ['#kx-t1', '#kx-l1', '#kx-limit'].forEach(s => fmtInput($(s)));
  $('#kx-save').onclick = async () => {
    const live = $('#kx-live').value || null;
    if (live && live !== (o.kassaGoLive || '') && !confirm(`Kassa ${dmy(live)} dan ishga tushsinmi?\n\nShu kundan naqd o‘quv to‘lovlari faqat kassa orderi va fiskal chek raqami bilan qabul qilinadi.`)) return;
    $('#kx-save').disabled = true;
    try { await call('fin_org_set', { p: { nameUz: $('#kx-name').value.trim(), stir: digits($('#kx-stir').value), place: $('#kx-place').value.trim(), printLang: $('#kx-lang').value,
        t1: num(digits($('#kx-t1').value)), l1: num(digits($('#kx-l1').value)), cashLimit: num(digits($('#kx-limit').value)), kassaGoLive: live } });
      await loadRefs(true); C.closeModal(); C.toast('Sozlamalar saqlandi ✓'); await reload(); if (C.onChange) C.onChange(); }
    catch (e) { $('#kx-save').disabled = false; C.toast(errText(e), true); }
  };
}

// ---------------------------------------------------------------- chop etish (fin-print.js — kerak bo'lganda yuklanadi)
// Har chop etish serverda qayd qilinadi (kassa_print_mark): birinchisi — asl nusxa, keyingilari — «НУСХА» belgisi bilan.
//   «Avvalgisi qog'ozga chiqmadi» tanlansa — asl nusxa qayta chiqadi va buxgalterning nazorat ro'yxatida ko'rinadi.
const printCtx = (names, isTest, mk) => ({ org: (ST.refs && ST.refs.org) || {}, signatories: (ST.refs && ST.refs.signatories) || [], names: names || {}, isTest: !!isTest,
  mark: mk ? { mode: mk.mode, replaced: !!mk.replaced } : {}, printedBy: (mk && mk.byName) || (C.SESSION && C.SESSION.email) || '', printedAt: (mk && mk.at) || new Date().toISOString() });
function askReprint(title, prior, go, back) {
  $('#modal').innerHTML = `<div class="modal-h"><h3>${esc(title)}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small" style="background:#FEF3E2;color:#B54708;border-radius:10px;padding:10px 12px;font-weight:600">Bu hujjat avval chop etishga yuborilgan: ${esc(String(prior))} marta.</div>
      <div class="small muted" style="margin-top:10px">Qog‘ozga chiqqan bo‘lsa — yangi nusxa «НУСХА» belgisi bilan chiqadi. Avvalgisi chiqmagan bo‘lsa (qog‘oz tiqildi, oyna yopildi) — asl nusxani qayta chiqaring; bu amal nazorat ro‘yxatiga yoziladi.</div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn ghost2" id="kp-orig">Avvalgisi chiqmagan — asl nusxa</button><button type="button" class="btn gold" id="kp-copy">«НУСХА» chop etish</button></div>`;
  C.openModal();
  const done = () => { if (back) back(); else C.closeModal(); };
  $('#m-x').onclick = done; $('#m-cancel').onclick = done;
  const run = async reissue => { $('#kp-copy').disabled = true; $('#kp-orig').disabled = true; try { await go(reissue); } catch (e) { C.toast('Chop etib bo‘lmadi: ' + errText(e), true); } done(); };
  $('#kp-copy').onclick = () => run(false); $('#kp-orig').onclick = () => run(true);
}
async function printDoc(id, back) {
  try {
    const [pm, wm, got] = await Promise.all([C.finMod('fin-print'), C.finMod('fin-words'), call('kassa_doc_get', { p_id: id }), loadRefs()]);
    const d = got.doc;
    if (!d || !d.no) { C.toast('Faqat o‘tkazilgan (raqam olgan) hujjat chop etiladi', true); return; }
    const go = async reissue => { const mk = await call('kassa_print_mark', { p_kind: 'doc', p_id: id, p_reissue: !!reissue }); C.printHTML(pm.docHtml(d, printCtx(got.names, got.isTest, mk), wm)); };
    if (num(d.prints) > 0) askReprint(`${d.form === 'KO1' ? 'Kirim orderi' : d.form === 'KO2' ? 'Chiqim orderi' : 'Dalolatnoma'} № ${d.no}`, num(d.prints), go, back);
    else await go(false);
  } catch (e) { C.toast('Chop etib bo‘lmadi: ' + errText(e), true); }
}
async function printBook(day, back) {
  try {
    const [pm, wm, book] = await Promise.all([C.finMod('fin-print'), C.finMod('fin-words'), call('kassa_day_book', { p_desk: ST.desk, p_day: day }), loadRefs()]);
    if (!book || !book.day) { C.toast('Bu kunda kassa varag‘i yo‘q', true); return; }
    const d = book.day;
    if (d.status === 'open') { C.printHTML(pm.bookHtml(book, printCtx(book.names, book.isTest, null), wm)); return; }   // qoralama — jurnalga yozilmaydi
    const go = async reissue => { const mk = await call('kassa_print_mark', { p_kind: 'book', p_id: d.id, p_reissue: !!reissue }); C.printHTML(pm.bookHtml(book, printCtx(book.names, book.isTest, mk), wm)); };
    if (num(d.prints) > 0) askReprint('Kassa kitobi varag‘i — ' + dmy(day), num(d.prints), go, back);
    else await go(false);
  } catch (e) { C.toast('Chop etib bo‘lmadi: ' + errText(e), true); }
}
// Sanash / topshirish-qabul dalolatnomasi (jurnalga yozilmaydi — raqamli hujjat emas).
async function printCount(book, countId) {
  try {
    const [pm, wm] = await Promise.all([C.finMod('fin-print'), C.finMod('fin-words'), loadRefs()]);
    const c = (book.counts || []).find(x => x.id === countId); if (!c) return;
    C.printHTML(pm.countHtml(c, book, printCtx(book.names, book.isTest, null), wm));
  } catch (e) { C.toast('Chop etib bo‘lmadi: ' + errText(e), true); }
}
// «To'lov» oynasidan: naqd o'quv to'lovining kirim orderini chop etish (hujjat id bo'yicha).
export async function printDocById(ctx, docId, back) { C = ctx; await printDoc(docId, back); }

// ---------------------------------------------------------------- kun varag'i: hujjatlar, sanashlar, jurnal (tekshiruvchi uchun)
const CNT_LBL = { close: 'Kun yopish sanashi', handover: 'Smena topshirish-qabul', opening: 'Boshlang‘ich qoldiq', monthly: 'Oylik sanash', yearly: 'Yillik sanash', surprise: 'To‘satdan sanash' };
const EV_LBL = { open: 'Kun ochildi', close: 'Kun yopildi', verify: 'Tekshirildi', reopen: 'Qayta ochildi', handover: 'Smena topshirildi', opening: 'Boshlang‘ich qoldiq', decision: 'Kamomad qarori' };
async function openDayView(day) {
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kassa kuni — ${esc(dmy(day))}</h3><button class="x" id="m-x">×</button></div><div class="modal-b"><div class="loading">Yuklanmoqda…</div></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal;
  let book;
  try { book = await call('kassa_day_book', { p_desk: ST.desk, p_day: day }); } catch (e) { C.toast(errText(e), true); C.closeModal(); return; }
  if (!book || !book.day) { C.toast('Bu kunda kassa varag‘i yo‘q', true); C.closeModal(); return; }
  const d = book.day, closed = d.status !== 'open', nm = uid => (uid && book.names && book.names[uid]) || (uid ? '…' : '—');
  const docs = book.docs || [];
  const rows = docs.map(x => { const isIn = x.form === 'KO1', v = x.status === 'void';
    return `<tr${v ? ' style="opacity:.55"' : ''}><td data-label="№"><b>${isIn ? 'K' : 'Ch'}-${esc(String(x.no))}</b><div class="small muted">${esc(hm(x.postedAt))}</div></td>
      <td data-label="Operatsiya">${esc(opName(x.op))}<div class="small muted">${esc(x.partyName || '')}</div></td>
      <td data-label="Kirim" style="text-align:right;white-space:nowrap">${isIn ? (v ? '<s>' + esc(som(x.amount)) + '</s>' : esc(som(x.amount))) : ''}</td>
      <td data-label="Chiqim" style="text-align:right;white-space:nowrap">${!isIn ? (v ? '<s>' + esc(som(x.amount)) + '</s>' : esc(som(x.amount))) : ''}</td>
      <td data-label="Holat">${v ? stChip('void') : '<span class="small muted">' + (x.isSystem ? 'tizim' : esc(nm(x.postedBy))) + '</span>'}${num(x.prints) ? `<div class="small muted">chop etilgan: ${esc(String(x.prints))}</div>` : ''}</td>
      <td data-label=""><button class="btn sm" data-dprint="${esc(x.id)}" title="Orderni chop etish">🖨</button></td></tr>`; }).join('');
  const cnts = (book.counts || []).map(c => `<div style="display:flex;justify-content:space-between;gap:8px;align-items:center;padding:6px 0;border-bottom:1px solid var(--border-2)">
      <div class="small"><b>${esc(CNT_LBL[c.kind] || c.kind)}</b> · ${esc(hm(c.at))} · sanalgan ${esc(som(c.counted))}${num(c.diff) ? ` · <span style="color:${num(c.diff) < 0 ? '#B42318' : '#B54708'};font-weight:700">farq ${num(c.diff) > 0 ? '+' : ''}${esc(som(c.diff))}</span>` : ' · farq yo‘q'}<div class="muted">${esc(nm(c.byUid))}${c.toUid ? ' → ' + esc(nm(c.toUid)) : ''}</div></div>
      <button class="btn sm" data-cprint="${esc(c.id)}">🖨 Dalolatnoma</button></div>`).join('');
  const evs = (book.events || []).map(e => `<div class="small muted">${esc(hm(e.at))} · ${esc(EV_LBL[e.kind] || e.kind)} · ${esc(nm(e.byUid))}${e.reason ? ' — ' + esc(e.reason) : ''}</div>`).join('');
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kassa kuni — ${esc(dmy(day))}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      <div class="small" style="background:#eef3f1;border-radius:10px;padding:10px 12px">${dayChip(d.status)} Kun boshi <b>${esc(som(d.opening))}</b> · kirim <b>${esc(som(closed ? d.receipts : d.receiptsLive))}</b> · chiqim <b>${esc(som(closed ? d.payouts : d.payoutsLive))}</b> · kun oxiri <b>${esc(som(closed ? d.closing : d.balance))}</b>${closed ? ` · sanalgan <b>${esc(som(d.counted))}</b>` : ''}${closed && d.sheetFrom ? ` · varaq ${esc(String(d.sheetFrom))}${d.sheetTo > d.sheetFrom ? '–' + esc(String(d.sheetTo)) : ''}` : ''}</div>
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;margin:10px 0 6px"><b>Hujjatlar (${docs.length} ta)</b><button class="btn sm" id="kdv-book">🖨 Kassa kitobi varag‘i${closed ? '' : ' (qoralama)'}</button></div>
      ${docs.length ? `<div class="tablewrap"><table><thead><tr><th>№</th><th>Operatsiya / tomon</th><th style="text-align:right">Kirim</th><th style="text-align:right">Chiqim</th><th>Kim</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>` : '<div class="empty">Hujjat yo‘q.</div>'}
      ${cnts ? `<div style="margin-top:12px"><b>Sanashlar</b>${cnts}</div>` : ''}
      ${evs ? `<details style="margin-top:12px"><summary class="small" style="cursor:pointer;font-weight:700">Kun jurnali</summary><div style="margin-top:6px">${evs}</div></details>` : ''}
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button></div>`;
  $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const back = () => openDayView(day);
  $('#kdv-book').onclick = () => printBook(day, back);
  $('#modal').querySelectorAll('[data-dprint]').forEach(b => b.onclick = () => printDoc(b.dataset.dprint, back));
  $('#modal').querySelectorAll('[data-cprint]').forEach(b => b.onclick = () => printCount(book, b.dataset.cprint));
}

// ---------------------------------------------------------------- «Tasdiqlash» bo'limi uchun navbat
export async function approvalCount(ctx) {
  C = ctx;
  try { const s = await call('kassa_state', { p_desk: 'main' }); return num(s && s.pending && s.pending.toApprove); } catch (_) { return 0; }
}
export async function approvalRender(ctx, el) {
  C = ctx; ST.desk = 'main';
  try { await Promise.all([loadOverview(), loadRefs()]); } catch (e) { el.innerHTML = `<div class="empty">O‘qib bo‘lmadi: ${esc(errText(e))}</div>`; return; }
  const m = me();
  const mineToDo = (ST.ov.requests || []).filter(d => d.status === 'draft' && ((m.list2 && d.needsList2 && !d.approvedBy && d.requestedBy !== m.uid) || (m.director && d.needsDirector && !d.dirApprovedBy)));
  if (!mineToDo.length) { el.innerHTML = '<div class="small muted">Tasdiq kutayotgan kassa so‘rovi yo‘q.</div>'; return; }
  el.innerHTML = `<div class="tablewrap"><table><thead><tr><th>Operatsiya</th><th>Kimga / kimdan</th><th style="text-align:right">Summa</th><th>So‘radi</th><th></th></tr></thead><tbody>${mineToDo.map(d => `<tr>
    <td data-label="Operatsiya">${esc(opName(d.op))}<div class="small muted">${esc((d.lines || []).map(l => artName(l.articleId)).filter((v, i, a) => v && a.indexOf(v) === i).join('; '))}</div></td>
    <td data-label="Kimga">${esc(d.partyName || '—')}<div class="small muted">${esc(d.basis || (d.noBasis ? 'asos hujjatisiz' : ''))}</div></td>
    <td data-label="Summa" style="text-align:right;white-space:nowrap"><b>${esc(som(d.amount))}</b></td>
    <td data-label="So‘radi">${esc(nameOf(d.requestedBy))}</td>
    <td data-label="" style="white-space:nowrap"><button class="btn sm gold" data-kappr="${esc(d.id)}">Tasdiqlash</button> <button class="btn sm danger" data-krej="${esc(d.id)}">Rad etish</button></td></tr>`).join('')}</tbody></table></div>`;
  const again = () => approvalRender(ctx, el);
  el.querySelectorAll('[data-kappr]').forEach(b => b.onclick = async () => { if (!confirm('Bu so‘rov tasdiqlansinmi?')) return; b.disabled = true;
    try { await call('kassa_doc_approve', { p_id: b.dataset.kappr }); C.toast('Tasdiqlandi ✓'); } catch (e) { C.toast(errText(e), true); } await again(); if (C.onChange) C.onChange(); });
  el.querySelectorAll('[data-krej]').forEach(b => b.onclick = () => ask('So‘rovni rad etish', 'Rad etish sababi', 3, async r => {
    try { await call('kassa_doc_reject', { p_id: b.dataset.krej, p_reason: r }); C.toast('Rad etildi ✓'); } catch (e) { C.toast(errText(e), true); } C.closeModal(); await again(); if (C.onChange) C.onChange(); }));
}
