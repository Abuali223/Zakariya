// =====================================================================
// fin-class.js — F2.3: noyabr–yanvar «Buxgalteriya» eski xarajatlariga statiya — buxgalter tasnifi va imzosi (moliya rejasi 2-bosqich).
//   admin.html («Buxgalteriya» → «🏷 Statiya tasnifi») kerak bo'lganda import() bilan yuklaydi.
//   Server: migration/fin-class.sql — fin_exp_class_list(oy), fin_exp_classify(qatorlar), fin_exp_class_sign(oy) (buxgalter, Moliya
//   menejeri, Direktor; imzo — faqat buxgalter). Yozuvga bitta statiya qo'yiladi (summa, sana, toifa o'zgarmaydi); toifadagini tasdiqlash
//   ham yoziladi. Bitta yozuvni bir nechta statiyaga bo'lish — Moliya menejeri «Tuzatish» bilan (F2.1).
//   Faqat mavjud komponentlar (.modal-*, .btn, .chip, .tablewrap) — yangi CSS yo'q.
//   Kirish:  openClassify(ctx, o) — o: { today, onDone }
//            Sof funksiyalar (fin-class.test.mjs): monthLabelUz, defaultMonth, monthStatus, rowStatus, buildItems, monthSummary.
// =====================================================================

let C = null;                                    // admin.html bergan yordamchilar (ctx)
let O = {};
const SEL = { month: '' };                       // tanlangan oy (sessiya davomida)

export const MONTHS = ['2026-11', '2026-12', '2027-01'];   // server ham shu davr (app.fin_class_months); javobdagi «months» — asosiy
const MO = ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentyabr', 'Oktyabr', 'Noyabr', 'Dekabr'];
const FLD = 'padding:8px 10px;border:1px solid var(--border);border-radius:10px;font:inherit;width:100%;background:#fff';
const TD = 'padding:10px 8px;vertical-align:top;white-space:normal';   // jadval katagi: umumiy «th,td» nowrap va keng chekinishi o'rniga (oyna 560px)
const $ = s => C.$(s);
const esc = s => C.esc(s);
const num = v => Number(v) || 0;
const errText = e => String((e && (e.message || e.code)) || e || 'xato');
const som = v => { const n = Math.round(num(v) * 100) / 100, a = Math.abs(n), w = Math.floor(a), t = Math.round((a - w) * 100);
  return (n < 0 ? '−' : '') + String(w).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + (t ? ',' + String(t).padStart(2, '0') : ''); };
const dmy = s => { const t = String(s || ''); return /^\d{4}-\d{2}-\d{2}/.test(t) ? `${t.slice(8, 10)}.${t.slice(5, 7)}.${t.slice(0, 4)}` : t; };
const chip = (t, fg, bg, title) => `<span class="chip" style="background:${bg};color:${fg};border-color:transparent"${title ? ` title="${esc(title)}"` : ''}>${esc(t)}</span>`;
const LVL = { ok: ['#027A48', '#ECFDF3'], info: ['#175CD3', '#E8F1FD'], warn: ['#B54708', '#FEF3E2'], bad: ['#B42318', '#FDECEC'], none: ['#475467', '#F2F4F7'] };
const lchip = (st, title) => chip(st.text, LVL[st.level][0], LVL[st.level][1], title);

// ---------------------------------------------------------------- sof funksiyalar
export const monthLabelUz = ym => { const s = String(ym || ''); return /^\d{4}-\d{2}$/.test(s) ? `${MO[+s.slice(5, 7) - 1]} ${s.slice(0, 4)}` : s; };
// Standart oy: davrdagi bugungi oy, aks holda — tasdiqlanmagan yozuvi bor birinchi oy, u ham bo'lmasa — davrning oxirgisi (bugun keyin bo'lsa)
//   yoki birinchisi.
export function defaultMonth(months, today) {
  const ms = (months || []).map(m => m.month), t = String(today || '').slice(0, 7);
  if (ms.includes(t)) return t;
  const open = (months || []).find(m => num(m.n) > num(m.confirmed));
  if (open) return open.month;
  return ms.length ? (t > ms[ms.length - 1] ? ms[ms.length - 1] : ms[0]) : '';
}
// Oy holati { level, text }: yozuvsiz; qisman (tasdiqlanmagani bor); hammasi tasdiqlangan — imzo kutilmoqda; imzolangan; imzo eskirgan.
export function monthStatus(m) {
  if (!m || !num(m.n)) return { level: 'none', text: 'eski yozuv yo‘q' };
  const n = num(m.n), c = num(m.confirmed), s = m.sign && typeof m.sign === 'object' ? m.sign : null;
  if (s && s.valid) return { level: 'ok', text: `imzolangan — ${s.by || 'buxgalter'}, ${dmy(s.at)}` };
  if (c < n) return { level: 'warn', text: `qisman: ${n} tadan ${c} tasi tasdiqlangan${s ? ' · oldingi imzo eskirgan' : ''}` };
  if (s) return { level: 'warn', text: 'imzo eskirgan — keyin o‘zgargan, qayta imzolash kerak' };
  return { level: 'info', text: 'hammasi tasdiqlangan — buxgalter imzosi kutilmoqda' };
}
// Yozuv holati: tasdiqlangan (kim) / toifadan — taxminiy / statiyasiz; yopilgan davrda — belgisi bilan
export function rowStatus(r) {
  if (!r) return { level: 'none', text: '' };
  if (r.confirmed) return { level: 'ok', text: '✓ tasdiqlangan' + (r.last && r.last.by ? ` — ${r.last.by}` : '') };
  if (!r.articleId) return { level: 'bad', text: 'statiyasiz' };
  return { level: 'warn', text: '≈ taxminiy (toifadan)' };
}
// Yuboriladigan qatorlar: statiyasi yoki tasnif izohi o'zgargan, yoki belgilab tasdiqlash so'ralgan (hali tasdiqlanmagan) yozuvlar.
//   edits: {id: {articleId, note}}, checked: Set; arts: [{id, needsNote}]. Yopilgan davr yozuvi — o'tkazib yuboriladi (server ham rad etadi).
//   Natija: { items: [{id, articleId, note}], errs: [{id, why}] }
export function buildItems(rows, edits, checked, arts) {
  const need = new Set((arts || []).filter(a => a.needsNote).map(a => a.id)), out = [], errs = [];
  for (const r of rows || []) {
    if (!r || r.locked) continue;
    const e = (edits && edits[r.id]) || {}, lastNote = (r.last && r.last.note) || '';
    const art = e.articleId != null ? String(e.articleId) : (r.articleId || '');
    const note = e.note != null ? String(e.note).trim().slice(0, 300) : lastNote;
    const changed = art !== (r.articleId || '') || note !== lastNote;
    const confirm = !!(checked && checked.has(r.id)) && !r.confirmed;
    if (!changed && !confirm) continue;
    if (!art) { errs.push({ id: r.id, why: 'statiya tanlanmagan' }); continue; }
    if (need.has(art) && note.length < 3) { errs.push({ id: r.id, why: 'bu statiya uchun tasnif izohi majburiy' }); continue; }
    out.push({ id: r.id, articleId: art, note });
  }
  return { items: out, errs };
}
// Oy yig'masi: yozuvlar, jami, tasdiqlangan, statiyasiz, «Boshqa» (EX-49) summasi va ulushi (maqsad ≤ 2 %), statiyalar bo'yicha (kamayish tartibida)
export function monthSummary(rows) {
  const by = {}; let total = 0, ok = 0, none = 0, ex49 = 0;
  for (const r of rows || []) {
    const a = num(r.amount); total += a; if (r.confirmed) ok++; if (!r.articleId) none++;
    if (r.articleId === 'EX-49') ex49 += a;
    const k = r.articleId || ''; by[k] = (by[k] || 0) + a;
  }
  const byArticle = Object.entries(by).map(([articleId, sum]) => ({ articleId, sum })).sort((x, y) => y.sum - x.sum || x.articleId.localeCompare(y.articleId));
  const share = total > 0 ? Math.round(ex49 / total * 1000) / 10 : 0;
  return { n: (rows || []).length, total, confirmed: ok, none, ex49, ex49Share: share, ex49Warn: share > 2, byArticle };
}

// ---------------------------------------------------------------- oyna
export async function openClassify(ctx, o) {
  C = ctx; O = o || {};
  let D = null, busy = false, saved = false;
  const edits = {}, checked = new Set();
  $('#modal').innerHTML = `<div class="modal-h"><h3>🏷 Statiya tasnifi — eski xarajatlar</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      <div class="small muted">Kassa moduli ishga tushgunga qadar «Buxgalteriya»ga kiritilgan xarajatlar (noyabr–yanvar) statiyasi eski toifadan taxminan olingan.
        Har yozuvga aniq statiyani qo‘ying yoki toifadagini tasdiqlang (belgilab — «Saqlash»); oyning hammasi tasdiqlangach buxgalter imzolaydi.
        Summa va sana o‘zgarmaydi. Bitta yozuvni bir nechta statiyaga bo‘lish kerak bo‘lsa — Moliya menejeri «Tuzatish» bilan hujjat qatorlariga ajratadi.</div>
      <div id="cl-months" style="display:flex;gap:6px;flex-wrap:wrap;margin-top:10px"></div>
      <div id="cl-body" style="margin-top:10px"></div>
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button>
      <button type="button" class="btn ghost2" id="cl-sign" style="display:none">✍ Imzolash</button>
      <button type="button" class="btn gold" id="cl-save" disabled>✓ Saqlash</button></div>`;
  C.openModal();
  const close = () => { C.closeModal(); if (saved && typeof O.onDone === 'function') O.onDone(); };
  $('#m-x').onclick = close; $('#m-cancel').onclick = close;

  const pending = () => buildItems(D ? D.rows : [], edits, checked, D ? D.articles : []);
  const refreshButtons = () => {
    if (!D) return;
    const p = pending(), st = (D.months || []).find(m => m.month === D.month) || null;
    $('#cl-save').disabled = busy || (p.items.length === 0 && p.errs.length === 0);
    const canSign = !!D.canSign, signable = st && num(st.n) > 0 && num(st.confirmed) === num(st.n) && !(st.sign && st.sign.valid);
    const sb = $('#cl-sign'); sb.style.display = canSign ? '' : 'none';
    sb.disabled = busy || !signable || p.items.length > 0;
    sb.title = !signable ? (st && num(st.n) && st.sign && st.sign.valid ? 'Oy imzolangan' : 'Imzolash uchun oyning hamma yozuvi tasdiqlangan bo‘lishi kerak')
      : (p.items.length ? 'Avval o‘zgarishlarni saqlang' : 'Oy tasnifini imzolash');
  };
  const drawMonths = () => {
    $('#cl-months').innerHTML = (D.months || []).map(m => {
      const st = monthStatus(m), on = m.month === D.month;
      return `<button type="button" class="btn ${on ? 'gold' : 'ghost2'}" data-cm="${esc(m.month)}" title="${esc(st.text)}">${esc(monthLabelUz(m.month))}
        <span class="small" style="opacity:.85">· ${num(m.confirmed)}/${num(m.n)}</span></button>`;
    }).join('');
    for (const b of document.querySelectorAll('#cl-months [data-cm]')) b.onclick = () => { if (busy || b.dataset.cm === D.month) return; if (pending().items.length && !confirm('Saqlanmagan o‘zgarishlar bor — boshqa oyga o‘tilsinmi (o‘zgarishlar yo‘qoladi)?')) return; load(b.dataset.cm); };
  };
  const draw = () => {
    drawMonths();
    const rows = D.rows || [], st = (D.months || []).find(m => m.month === D.month) || {}, S = monthSummary(rows), arts = D.articles || [];
    const anyLocked = rows.some(r => r.locked);
    const artOpts = sel => `<option value=""${sel ? '' : ' selected'}>— statiya —</option>`
      + ['EX', 'OP'].map(k => `<optgroup label="${k === 'EX' ? 'Xarajat (EX)' : 'Operatsiya (OP)'}">${arts.filter(a => a.kind === k)
        .map(a => `<option value="${esc(a.id)}"${a.id === sel ? ' selected' : ''}>${esc(a.id + ' ' + a.nameUz)}</option>`).join('')}</optgroup>`).join('');
    const nameOf = id => { const a = arts.find(x => x.id === id); return a ? `${a.id} ${a.nameUz}` : (id || 'statiyasiz'); };
    const tr = r => {
      const e = edits[r.id] || {}, art = e.articleId != null ? e.articleId : (r.articleId || ''), note = e.note != null ? e.note : ((r.last && r.last.note) || '');
      const dis = r.locked ? ' disabled' : '';
      return `<tr data-cl="${esc(r.id)}"><td data-label="Belgi" style="${TD};width:24px"><input type="checkbox" data-ck="${esc(r.id)}"${checked.has(r.id) ? ' checked' : ''}${dis}></td>
        <td data-label="Xarajat" style="${TD};min-width:120px"><b style="white-space:nowrap">${esc(som(r.amount))}</b> <span class="small muted" style="white-space:nowrap">· ${esc(dmy(r.date) || r.month || '')}</span>
          <div class="small">${esc(r.category || '—')}${r.mapArticle ? ` <span class="muted">(toifadan: ${esc(r.mapArticle)})</span>` : ''}</div>${r.note ? `<div class="small muted">${esc(r.note)}</div>` : ''}</td>
        <td data-label="Statiya va izoh" style="${TD};min-width:180px"><select data-art="${esc(r.id)}" style="${FLD};display:block"${dis}>${artOpts(art)}</select>
          <input data-note="${esc(r.id)}" value="${esc(note)}" maxlength="300" placeholder="tasnif izohi («Boshqa» — majburiy)" style="${FLD};display:block;margin-top:4px"${dis}></td>
        <td data-label="Holat" style="${TD};min-width:100px">${lchip(rowStatus(r), r.last ? `${r.last.by || ''} · ${dmy(r.last.at)}${r.last.old && r.last.old !== r.last.new ? ` · ${r.last.old} → ${r.last.new}` : ''}` : '')}${r.locked ? ' ' + chip('🔒 yopilgan davr', '#475467', '#F2F4F7') : ''}</td></tr>`;
    };
    $('#cl-body').innerHTML = `<div class="small" id="cl-sum" style="background:#eef3f1;border-radius:10px;padding:10px 12px">
        <b>${esc(monthLabelUz(D.month))}</b> · ${S.n} ta eski yozuv · jami ${esc(som(S.total))} so‘m · tasdiqlangan ${S.confirmed}${S.none ? ` · statiyasiz ${S.none}` : ''}
        <div style="margin-top:4px">«Boshqa» (EX-49): ${esc(som(S.ex49))} so‘m (${S.ex49Share} %; maqsad ≤ 2 %)${S.ex49Warn ? ' ' + chip('2 % dan ko‘p — qayta ko‘rib chiqing', '#B54708', '#FEF3E2') : ''}</div>
        <div style="display:flex;gap:4px;flex-wrap:wrap;margin-top:6px">${lchip(monthStatus(st))}</div>
        ${S.byArticle.length ? `<div class="small muted" style="margin-top:6px">${S.byArticle.slice(0, 8).map(x => esc(`${nameOf(x.articleId)} — ${som(x.sum)}`)).join(' · ')}${S.byArticle.length > 8 ? ' …' : ''}</div>` : ''}</div>
      ${anyLocked ? `<div class="small" style="margin-top:8px;background:#F2F4F7;color:#344054;border-radius:10px;padding:8px 12px">🔒 Davr ${esc(dmy(D.lockedThrough))} gacha yopilgan: o‘sha sanagacha yozuvlar tasnifi o‘zgarmaydi (kerak bo‘lsa Direktor «Davr»da qayta ochadi).</div>` : ''}
      ${rows.length ? `<div style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-top:10px">
          <label class="small" style="display:flex;gap:6px;align-items:center;white-space:nowrap"><input type="checkbox" id="cl-all" style="width:auto;margin:0"> Hammasini belgilash</label>
          <select id="cl-bulk" style="${FLD};max-width:280px">${artOpts('')}</select>
          <button type="button" class="btn ghost2" id="cl-bulk-apply">Belgilanganlarga qo‘yish</button></div>
        <div class="tablewrap" style="max-height:420px;overflow:auto;margin-top:8px"><table id="cl-tbl"><thead><tr><th style="${TD}"></th><th style="${TD}">Xarajat</th><th style="${TD}">Statiya va izoh</th><th style="${TD}">Holat</th></tr></thead>
          <tbody>${rows.map(tr).join('')}</tbody></table></div>`
        : '<div class="empty" style="margin-top:8px">Bu oyda tasniflanadigan eski yozuv yo‘q (hujjat bilan kiritilgan va kassa xarajatlari statiyasi o‘z hujjatida).</div>'}`;
    for (const s of document.querySelectorAll('#cl-tbl [data-art]')) s.onchange = () => { (edits[s.dataset.art] = edits[s.dataset.art] || {}).articleId = s.value; refreshButtons(); };
    for (const i of document.querySelectorAll('#cl-tbl [data-note]')) i.oninput = () => { (edits[i.dataset.note] = edits[i.dataset.note] || {}).note = i.value; refreshButtons(); };
    for (const c of document.querySelectorAll('#cl-tbl [data-ck]')) c.onchange = () => { if (c.checked) checked.add(c.dataset.ck); else checked.delete(c.dataset.ck); refreshButtons(); };
    if ($('#cl-all')) $('#cl-all').onchange = () => {
      const on = $('#cl-all').checked;
      for (const c of document.querySelectorAll('#cl-tbl [data-ck]')) { if (c.disabled) continue; c.checked = on; if (on) checked.add(c.dataset.ck); else checked.delete(c.dataset.ck); }
      refreshButtons();
    };
    if ($('#cl-bulk-apply')) $('#cl-bulk-apply').onclick = () => {
      const v = $('#cl-bulk').value;
      if (!v) { C.toast('Avval statiyani tanlang', true); return; }
      if (!checked.size) { C.toast('Avval yozuvlarni belgilang', true); return; }
      for (const id of checked) {
        const s = document.querySelector(`#cl-tbl [data-art="${CSS.escape(id)}"]`);
        if (!s || s.disabled) continue;
        s.value = v; (edits[id] = edits[id] || {}).articleId = v;
      }
      refreshButtons();
    };
    refreshButtons();
  };
  const load = async m => {
    busy = true; $('#cl-save').disabled = true; $('#cl-sign').disabled = true;
    $('#cl-body').innerHTML = '<div class="loading">Yuklanmoqda…</div>';
    try {
      D = await C.rpc('fin_exp_class_list', { p_month: m });
      SEL.month = D.month;
      for (const k of Object.keys(edits)) delete edits[k];
      checked.clear();
      busy = false; draw();
    } catch (e) { busy = false; $('#cl-body').innerHTML = ''; C.toast(errText(e), true); }
  };
  $('#cl-save').onclick = async () => {
    if (busy || !D) return;
    const p = pending();
    if (p.errs.length) {
      const r = (D.rows || []).find(x => x.id === p.errs[0].id);
      C.toast(`${r ? `${dmy(r.date)} · ${r.category} · ${som(r.amount)}` : p.errs[0].id}: ${p.errs[0].why}${p.errs.length > 1 ? ` (yana ${p.errs.length - 1} ta)` : ''}`, true);
      return;
    }
    if (!p.items.length) return;
    busy = true; $('#cl-save').disabled = true; $('#cl-save').textContent = 'Saqlanmoqda…';
    try {
      const res = await C.rpc('fin_exp_classify', { p_items: p.items });
      saved = true;
      C.toast(`Saqlandi: ${num(res && res.changed)} ta statiya o‘zgardi, ${num(res && res.confirmed)} ta tasdiqlandi${num(res && res.unchanged) ? `, ${num(res.unchanged)} ta o‘zgarishsiz` : ''}`);
      $('#cl-save').textContent = '✓ Saqlash'; busy = false;
      await load(D.month);
    } catch (e) { busy = false; $('#cl-save').textContent = '✓ Saqlash'; refreshButtons(); C.toast(errText(e), true); }
  };
  $('#cl-sign').onclick = async () => {
    if (busy || !D) return;
    const st = (D.months || []).find(m => m.month === D.month) || {};
    if (!confirm(`«${monthLabelUz(D.month)}» — ${num(st.n)} ta eski xarajat (jami ${som(st.total)} so‘m) statiya tasnifini imzolaysizmi?\n\nImzodan keyin tasnif yoki summa o‘zgarsa — imzo eskiradi va qayta imzolanadi.`)) return;
    busy = true; $('#cl-sign').disabled = true;
    try {
      const res = await C.rpc('fin_exp_class_sign', { p_month: D.month });
      saved = true;
      C.toast(res && res.dup ? 'Bu oy allaqachon imzolangan' : `Imzolandi: ${monthLabelUz(D.month)} — ${num(res && res.n)} ta yozuv`);
      busy = false; await load(D.month);
    } catch (e) { busy = false; refreshButtons(); C.toast(errText(e), true); }
  };
  // birinchi yuklash: oylar holati bilan (standart oy — bugungi yoki tasdiqlanmagani bor birinchi oy)
  try {
    const first = await C.rpc('fin_exp_class_list', { p_month: SEL.month || MONTHS[0] });
    const m = SEL.month || defaultMonth(first.months, O.today);
    if (m && m !== first.month) await load(m); else { D = first; SEL.month = D.month; draw(); }
  } catch (e) { $('#cl-body').innerHTML = ''; C.toast(errText(e), true); }
}
