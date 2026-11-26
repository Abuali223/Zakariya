// =====================================================================
// fin-cp.js — kontragentlar: ro'yxat, karta (rekvizitlar, shartnoma) va RP-10 kontragent ko'chirmasi (moliya ish rejasi 2-bosqich, F2.2).
//   admin.html («Buxgalteriya» → «🏢 Kontragentlar») kerak bo'lganda import() bilan yuklaydi.
//   Server: migration/fin-cp.sql — fin_cp_save (karta: yangi yoki mavjud, versiya bilan), fin_cp_statement (ko'chirma; faylga — p_file:
//   FD-28 bo'yicha jismoniy shaxs ko'chirmasi Direktordan boshqaga ismsiz). Ro'yxat — fin_counterparties jadvalidan (o'qish — kassa
//   rollari, RLS). Chop etish va Excel varag'i — fin-print.js (cpStatementHtml, cpStatementSheet).
//   Faqat mavjud komponentlar (.modal-*, .btn, .chip, .tablewrap) — yangi CSS yo'q.
//   Kirish:  openCounterparties(ctx, o) — o: { canEdit (karta o'zgartirish — Direktor, Moliya menejeri, buxgalter), today }
//            Sof funksiyalar (fin-cp.test.mjs): cpDigits, cpNameKey, cpPayload, cpMatch, cpFilter, cpUnconf, contractState, fmtAcc,
//            stmtFileName, periodDefault.
// =====================================================================

let C = null;                                    // admin.html bergan yordamchilar (ctx)
let O = {};                                      // oyna sozlamalari
let LIST = [];                                   // fin_counterparties qatorlari (oyna ochilganda yangilanadi)
const FLT = { q: '', kind: '', act: 'on' };      // ro'yxat filtri (sessiya davomida saqlanadi)

export const CP_KIND = { supplier: 'Yetkazib beruvchi', org: 'Tashkilot', bank: 'Bank', person: 'Jismoniy shaxs (YaTT)', founder: 'Ta’sischi', other: 'Boshqa' };
export const KIND_ORDER = ['supplier', 'org', 'bank', 'person', 'founder', 'other'];
const LEGAL = { supplier: 1, org: 1, bank: 1 };
const METHOD = { cash: 'Naqd', bank: 'Bank', card: 'Karta' };
const FLD = 'padding:10px 12px;border:1px solid var(--border);border-radius:10px;font:inherit;width:100%;background:#fff';
const CHK = 'width:auto;flex:none;padding:0;margin:2px 0 0';
const $ = s => C.$(s);
const esc = s => C.esc(s);
const num = v => Number(v) || 0;
const errText = e => String((e && (e.message || e.code)) || e || 'xato');
const som = v => { const n = Math.round(num(v) * 100) / 100, a = Math.abs(n), w = Math.floor(a), t = Math.round((a - w) * 100);
  return (n < 0 ? '−' : '') + String(w).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + (t ? ',' + String(t).padStart(2, '0') : '') + ' so‘m'; };
const dmy = d => { const s = String(d || ''); return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(8, 10) + '.' + s.slice(5, 7) + '.' + s.slice(0, 4) : s; };
const isDay = s => /^\d{4}-\d{2}-\d{2}$/.test(String(s || ''));
const lbl = (t, inner, extra) => `<label class="small" style="font-weight:700;display:flex;flex-direction:column;gap:6px;margin-top:8px${extra || ''}">${t}${inner}</label>`;
const opt = (v, t, sel) => `<option value="${esc(v)}"${v === sel ? ' selected' : ''}>${esc(t)}</option>`;
const chip = (t, fg, bg) => `<span class="chip" style="background:${bg};color:${fg};border-color:transparent">${esc(t)}</span>`;
const cpId = c => (c && (c.id || c._id)) || '';
const hint = e => String((e && e.hint) || '');
const tkd = ts => { try { return ts ? new Date(ts).toLocaleDateString('ru-RU', { timeZone: 'Asia/Tashkent' }) : ''; } catch (_) { return ''; } };
const dayDiff = (a, b) => Math.round((Date.UTC(+b.slice(0, 4), +b.slice(5, 7) - 1, +b.slice(8, 10)) - Date.UTC(+a.slice(0, 4), +a.slice(5, 7) - 1, +a.slice(8, 10))) / 864e5);

// ---------------------------------------------------------------- sof funksiyalar
// Raqamli rekvizit: bo'shliqlar (oddiy, bo'linmas, tor — JS \s) olib tashlanadi — server bilan bir xil (app.fin_cp_digits).
export const cpDigits = s => String(s == null ? '' : s).replace(/\s+/g, '');
// Nom kaliti (qidiruv va takrorni oldindan ko'rish): apostrof turlari, bo'shliqlar, katta-kichik harf — server qoidasiga yaqin.
export const cpNameKey = s => String(s == null ? '' : s).trim().replace(/[‘’ʻʼ`´]/g, "'").replace(/\s+/g, ' ').toLowerCase();
// Turi tasdiqlanmagan «Jismoniy shaxs» / «Boshqa» — yuridik shaxs hisoblanadi (kassadan naqd to'lovga Direktor tasdig'i; sec-3).
export const cpUnconf = c => !!c && (c.kind === 'person' || c.kind === 'other') && !(c.confirmed === true || !!c.kindConfirmedBy);
// Hisob raqami ko'rinishi: 20208 000 9 00123456 001 (balans hisobi, valyuta, kalit, mijoz, tartib raqami)
export const fmtAcc = s => { const d = cpDigits(s); return /^\d{20}$/.test(d) ? d.replace(/^(\d{5})(\d{3})(\d)(\d{8})(\d{3})$/, '$1 $2 $3 $4 $5') : String(s || ''); };

// Shartnoma holati (ro'yxat va karta): yo'q / amalda / 30 kun ichida tugaydi / muddati o'tgan.
export function contractState(c, today) {
  if (!c || !c.contractNo) return { st: 'none', txt: '' };
  const base = `№ ${c.contractNo}${isDay(c.contractDate) ? ' · ' + dmy(c.contractDate) : ''}`, u = String(c.contractUntil || '');
  if (!isDay(u)) return { st: 'ok', txt: base };
  if (isDay(today) && u < today) return { st: 'expired', txt: `${base} · muddati o‘tgan (${dmy(u)})` };
  if (isDay(today) && dayDiff(today, u) <= 30) return { st: 'soon', txt: `${base} · muddati tugaydi: ${dmy(u)}` };
  return { st: 'ok', txt: `${base} · ${dmy(u)} gacha` };
}

// Karta shakli → server so'rovi (sof). Xato bo'lsa — { err } (server ham xuddi shu qoidalarni tekshiradi).
//   f: { id, rev, kind, name, stir, stirOld (kartadagi hozirgi STIR — o'zgarmagan eski qiymat rad etilmaydi), account, mfo, bankName,
//        contractNo, contractDate, contractUntil, note, active, dupOk }; today — server sanasi.
export function cpPayload(f, today) {
  f = f || {};
  const kind = String(f.kind || ''), name = String(f.name || '').trim();
  const stir = cpDigits(f.stir), account = cpDigits(f.account), mfo = cpDigits(f.mfo);
  const bankName = String(f.bankName || '').trim(), note = String(f.note || '').trim();
  const contractNo = String(f.contractNo || '').trim().replace(/^(?:№|#)+\s*/, '').trim();
  const cd = String(f.contractDate || '').trim(), cu = String(f.contractUntil || '').trim();
  if (!Object.prototype.hasOwnProperty.call(CP_KIND, kind)) return { err: 'Kontragent turini tanlang' };
  if (name.length < 2 || name.length > 200) return { err: 'Kontragent nomi 2–200 belgi bo‘lsin' };
  if (stir && !/^\d{9}$/.test(stir) && stir !== String(f.stirOld == null ? '' : f.stirOld))
    return { err: 'STIR — 9 ta raqam (yuridik shaxs yoki YaTT); jismoniy shaxsning JShShIR’i (14 raqam) kiritilmaydi' };
  if (account && !/^\d{20}$/.test(account)) return { err: `Hisob raqami — 20 ta raqam (hozir: ${account.length})` };
  if (mfo && !/^\d{5}$/.test(mfo)) return { err: 'Bank MFO kodi — 5 ta raqam' };
  if (account && !mfo) return { err: 'Hisob raqami bilan bankning MFO kodini ham kiriting' };
  if (bankName.length > 200) return { err: 'Bank nomi 200 belgidan oshmasin' };
  if (contractNo.length > 60) return { err: 'Shartnoma raqami 60 belgidan oshmasin' };
  if ((cd && !isDay(cd)) || (cu && !isDay(cu))) return { err: 'Shartnoma sanasi noto‘g‘ri' };
  if (!contractNo && (cd || cu)) return { err: 'Shartnoma raqamini kiriting (sanasi bor)' };
  if (contractNo && !cd) return { err: 'Shartnoma sanasini kiriting' };
  if (cd && isDay(today) && cd > today) return { err: 'Shartnoma sanasi bugundan keyin bo‘lmasin' };
  if (cd && cd < '1991-01-01') return { err: 'Shartnoma sanasi noto‘g‘ri' };
  if (cu && cd && cu < cd) return { err: 'Shartnoma muddati uning sanasidan oldin bo‘lmasin' };
  if (note.length > 500) return { err: 'Izoh 500 belgidan oshmasin' };
  const p = { kind, name, stir, account, mfo, bankName, contractNo, contractDate: cd || null, contractUntil: cu || null, note, active: f.active !== false };
  if (f.id) { p.id = f.id; p.rev = Number(f.rev) || 0; }
  if (f.dupOk) p.dupOk = true;
  return { p };
}

// Qidiruv: nom (kalit bo'yicha), STIR / hisob raqami / MFO (kamida 3 raqam), shartnoma №, bank nomi.
export function cpMatch(c, q) {
  const k = cpNameKey(q); if (!k) return true;
  const d = cpDigits(q);
  if (cpNameKey(c && c.name).includes(k) || cpNameKey(c && c.contractNo).includes(k) || cpNameKey(c && c.bankName).includes(k)) return true;
  return /^\d{3,}$/.test(d) && [c && c.stir, c && c.account, c && c.mfo].some(x => cpDigits(x).includes(d));
}
// Ro'yxat filtri (sof): tur, faollik ('on' — faol, 'off' — nofaol, 'all'), qidiruv; nom bo'yicha tartib.
export function cpFilter(list, o) {
  o = o || {};
  return (list || []).filter(c => c && (!o.kind || c.kind === o.kind) && (o.act === 'all' || (o.act === 'off' ? c.active === false : c.active !== false)) && cpMatch(c, o.q))
    .sort((a, b) => cpNameKey(a.name).localeCompare(cpNameKey(b.name)) || cpId(a).localeCompare(cpId(b)));
}
// Ko'chirma davri: yil boshidan bugungacha.
export const periodDefault = today => isDay(today) ? { from: today.slice(0, 4) + '-01-01', to: today } : { from: '', to: '' };
// Excel fayl nomi: kontragent ID (ism emas), davr; ismsiz nusxada «-ismsiz».
export const stmtFileName = st => `RP-10_${String((st && st.cp && st.cp.id) || 'kontragent').replace(/[^\w-]/g, '')}_${(st && st.from) || ''}_${(st && st.to) || ''}${st && st.masked ? '-ismsiz' : ''}.xlsx`;

// ---------------------------------------------------------------- ro'yxat
export async function openCounterparties(ctx, o) {
  C = ctx; O = o || {};
  $('#modal').innerHTML = `<div class="modal-h"><h3>🏢 Kontragentlar</h3><button class="x" id="m-x">×</button></div><div class="modal-b"><div class="loading">Yuklanmoqda…</div></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal;
  try { await reloadList(); } catch (e) { $('#modal').querySelector('.modal-b').innerHTML = `<div class="empty">Ro‘yxat yuklanmadi: ${esc(errText(e))}</div>`; return; }
  drawList();
}
async function reloadList() { LIST = (await C.cpList()) || []; }
function drawList() {
  $('#modal').innerHTML = `<div class="modal-h"><h3>🏢 Kontragentlar</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      <div class="small muted">Yetkazib beruvchi, tashkilot, bank, YaTT va boshqalar: rekvizitlar (STIR, hisob raqami, MFO), shartnoma; «Ko‘chirma» — kontragent bilan barcha to‘lovlar (kassa, bank, karta).</div>
      <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:8px">
        <input id="cp-q" type="search" aria-label="Qidirish" placeholder="Qidirish: nom, STIR, hisob raqami, shartnoma №" value="${esc(FLT.q)}" style="${FLD};flex:2 1 220px;width:auto">
        <select id="cp-kind" aria-label="Turi" style="${FLD};flex:1 1 150px;width:auto">${opt('', 'Barcha turlar', FLT.kind)}${KIND_ORDER.map(k => opt(k, CP_KIND[k], FLT.kind)).join('')}</select>
        <select id="cp-act" aria-label="Holati" style="${FLD};flex:1 1 120px;width:auto">${opt('on', 'Faollar', FLT.act)}${opt('off', 'Nofaollar', FLT.act)}${opt('all', 'Hammasi', FLT.act)}</select>
      </div>
      <div id="cp-list" style="margin-top:8px"></div>
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button>${O.canEdit ? '<button type="button" class="btn gold" id="cp-new">+ Yangi kontragent</button>' : ''}</div>`;
  $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const nb = $('#cp-new'); if (nb) nb.onclick = () => openCard(null);
  const redraw = () => { FLT.q = $('#cp-q').value; FLT.kind = $('#cp-kind').value; FLT.act = $('#cp-act').value; drawRows(); };
  $('#cp-q').addEventListener('input', redraw); $('#cp-kind').onchange = redraw; $('#cp-act').onchange = redraw;
  drawRows();
}
function drawRows() {
  const xs = cpFilter(LIST, FLT), today = O.today || '';
  const kChip = c => chip(CP_KIND[c.kind] || c.kind, '#344054', '#F2F4F7');
  const st = c => { const s = contractState(c, today);
    return s.st === 'none' ? '<span class="muted">—</span>' : s.st === 'expired' ? chip(s.txt, '#B42318', '#FDECEC') : s.st === 'soon' ? chip(s.txt, '#B54708', '#FEF3E2') : esc(s.txt); };
  // tugmalar nom katagida — telefonda jadval o'ngga siljitilmasa ham ko'rinadi
  $('#cp-list').innerHTML = xs.length ? `<div class="small muted" style="margin-bottom:4px">${xs.length} ta</div><div class="tablewrap" style="max-height:420px;overflow:auto"><table><thead><tr><th>Nomi</th><th>STIR</th><th>Bank rekvizitlari</th><th>Shartnoma</th></tr></thead><tbody>
    ${xs.map(c => `<tr><td data-label="Nomi" style="min-width:190px"><b>${esc(c.name)}</b><div style="display:flex;gap:4px;flex-wrap:wrap;margin-top:3px">${kChip(c)}${cpUnconf(c) ? chip('turi tasdiqlanmagan', '#B54708', '#FEF3E2') : ''}${c.active === false ? chip('nofaol', '#667085', '#F2F4F7') : ''}</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:6px"><button type="button" class="btn sm ghost2" data-card="${esc(cpId(c))}">Karta</button><button type="button" class="btn sm ghost2" data-stmt="${esc(cpId(c))}">Ko‘chirma</button></div></td>
      <td data-label="STIR" style="white-space:nowrap">${esc(c.stir || '—')}</td>
      <td data-label="Bank rekvizitlari" class="small">${c.account || c.mfo ? esc([fmtAcc(c.account), c.mfo ? 'MFO ' + c.mfo : '', c.bankName || ''].filter(Boolean).join(' · ')) : '<span class="muted">—</span>'}</td>
      <td data-label="Shartnoma" class="small">${st(c)}</td></tr>`).join('')}
    </tbody></table></div>` : `<div class="empty">${LIST.length ? 'Filtr bo‘yicha kontragent topilmadi.' : 'Kontragentlar hali yo‘q.'}</div>`;
  const find = id => LIST.find(c => cpId(c) === id);
  $('#cp-list').querySelectorAll('[data-card]').forEach(b => b.onclick = () => openCard(find(b.dataset.card)));
  $('#cp-list').querySelectorAll('[data-stmt]').forEach(b => b.onclick = () => openStatement(find(b.dataset.stmt)));
}

// ---------------------------------------------------------------- karta
function openCard(c) {
  const isNew = !c, ro = !O.canEdit, today = O.today || '';
  const F = isNew ? { kind: 'supplier', name: '', stir: '', account: '', mfo: '', bankName: '', contractNo: '', contractDate: '', contractUntil: '', note: '', active: true }
    : { id: cpId(c), rev: num(c.rev), kind: c.kind, name: c.name || '', stir: c.stir || '', stirOld: c.stir || '', account: c.account || '', mfo: c.mfo || '', bankName: c.bankName || '',
        contractNo: c.contractNo || '', contractDate: c.contractDate || '', contractUntil: c.contractUntil || '', note: c.note || '', active: c.active !== false };
  const dis = ro ? ' disabled' : '';
  const conf = !c ? '' : cpUnconf(c)
    ? `<div class="small" style="margin-top:8px;background:#FEF3E2;color:#B54708;border-radius:10px;padding:10px 12px"><b>Turi hali tasdiqlanmagan</b> — yuridik shaxs hisoblanadi (kassadan naqd to‘lovga Direktor tasdig‘i kerak). Turini buxgalter yoki Direktor tasdiqlaydi: kartani saqlash yoki «Kassa» → nazorat ro‘yxati.</div>`
    : (c.kindConfirmedBy || c.confirmed) ? `<div class="small muted" style="margin-top:8px">Turi tasdiqlangan${c.kindConfirmedAt ? ' · ' + esc(tkd(c.kindConfirmedAt)) : ''}.</div>` : '';
  $('#modal').innerHTML = `<div class="modal-h"><h3>${isNew ? 'Yangi kontragent' : 'Kontragent kartasi'}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      ${ro ? '<div class="small" style="background:#E8F1FD;color:#175CD3;border-radius:10px;padding:10px 12px"><b>Faqat ko‘rish.</b> Kartani Moliya menejeri, buxgalter yoki Direktor o‘zgartiradi.</div>' : ''}
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:0 10px">
        ${lbl('Turi', `<select id="cf-kind" style="${FLD}"${dis}>${KIND_ORDER.map(k => opt(k, CP_KIND[k], F.kind)).join('')}</select>`)}
        ${lbl('STIR <span class="muted" style="font-weight:500">— 9 raqam</span>', `<input id="cf-stir" type="text" inputmode="numeric" maxlength="14" value="${esc(F.stir)}" placeholder="masalan: 3XX XXX XXX" style="${FLD}"${dis}>`)}
      </div>
      ${lbl('Nomi <span class="muted" style="font-weight:500">— to‘liq, hujjatdagidek</span>', `<input id="cf-name" type="text" maxlength="200" value="${esc(F.name)}" style="${FLD}"${dis}>`)}
      <div class="small muted" id="cf-khint" style="margin-top:6px"></div>
      <div class="small" style="font-weight:700;margin-top:12px">Bank rekvizitlari <span class="muted" style="font-weight:500">— ixtiyoriy; bank o‘tkazmasi uchun</span></div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:0 10px">
        ${lbl('Hisob raqami <span class="muted" style="font-weight:500">— 20 raqam</span>', `<input id="cf-acc" type="text" inputmode="numeric" maxlength="26" value="${esc(fmtAcc(F.account))}" style="${FLD}"${dis}>`)}
        ${lbl('Bank MFO kodi <span class="muted" style="font-weight:500">— 5 raqam</span>', `<input id="cf-mfo" type="text" inputmode="numeric" maxlength="7" value="${esc(F.mfo)}" style="${FLD}"${dis}>`)}
      </div>
      ${lbl('Bank nomi', `<input id="cf-bank" type="text" maxlength="200" value="${esc(F.bankName)}" placeholder="masalan: «…» bankining … filiali" style="${FLD}"${dis}>`)}
      <div class="small" style="font-weight:700;margin-top:12px">Shartnoma <span class="muted" style="font-weight:500">— ixtiyoriy; raqami va sanasi birga</span></div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:0 10px">
        ${lbl('Raqami', `<input id="cf-cno" type="text" maxlength="60" value="${esc(F.contractNo)}" style="${FLD}"${dis}>`)}
        ${lbl('Sanasi', `<input id="cf-cd" type="date" value="${esc(F.contractDate)}"${today ? ` max="${esc(today)}"` : ''} style="${FLD}"${dis}>`)}
        ${lbl('Amal qilish muddati <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<input id="cf-cu" type="date" value="${esc(F.contractUntil)}" style="${FLD}"${dis}>`)}
      </div>
      ${lbl('Izoh <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<input id="cf-note" type="text" maxlength="500" value="${esc(F.note)}" style="${FLD}"${dis}>`)}
      ${isNew ? '' : `<label class="small" style="display:flex;gap:8px;align-items:flex-start;margin-top:10px"><input type="checkbox" id="cf-act" style="${CHK}"${F.active ? ' checked' : ''}${dis}><span><b>Faol</b> — kassa va xarajat oynalarida tanlanadi (nofaol — tarixda qoladi, yangi to‘lovda tanlanmaydi)</span></label>`}
      ${conf}
      ${c && (c.createdAt || c.updatedAt) ? `<div class="small muted" style="margin-top:8px">${c.createdAt ? 'Qo‘shilgan: ' + esc(tkd(c.createdAt)) : ''}${c.updatedAt ? ' · oxirgi o‘zgarish: ' + esc(tkd(c.updatedAt)) : ''} (o‘zgarishlar tarixi — Direktorda)</div>` : ''}
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="cf-back">← Ro‘yxat</button>${isNew ? '' : '<button type="button" class="btn ghost2" id="cf-stmt">Ko‘chirma</button>'}${ro ? '' : '<button type="button" class="btn gold" id="cf-save">Saqlash</button>'}</div>`;
  $('#m-x').onclick = C.closeModal; $('#cf-back').onclick = drawList;
  const sb = $('#cf-stmt'); if (sb) sb.onclick = () => openStatement(c);
  const khint = () => { const k = $('#cf-kind').value;
    $('#cf-khint').textContent = k === 'person' ? 'YaTT — STIR bilan (9 raqam). Jismoniy shaxsning JShShIR’i (14 raqam) kiritilmaydi — shaxsiy ma’lumot. Turini buxgalter yoki Direktor tasdiqlaydi.'
      : k === 'bank' ? 'Bank: MFO kodi hisob raqamisiz ham kiritiladi (bank filiali).' : LEGAL[k] ? 'Yuridik shaxs: kassadan naqd to‘lovga Direktor tasdig‘i kerak (asosiy yo‘l — bank o‘tkazmasi).' : ''; };
  $('#cf-kind').onchange = khint; khint();
  if (ro) return;
  let busy = false;
  const save = async dupOk => {
    if (busy) return;
    Object.assign(F, { kind: $('#cf-kind').value, name: $('#cf-name').value, stir: $('#cf-stir').value, account: $('#cf-acc').value, mfo: $('#cf-mfo').value,
      bankName: $('#cf-bank').value, contractNo: $('#cf-cno').value, contractDate: $('#cf-cd').value, contractUntil: $('#cf-cu').value, note: $('#cf-note').value,
      active: $('#cf-act') ? $('#cf-act').checked : true, dupOk: !!dupOk });
    const b = cpPayload(F, today);
    if (b.err) { C.toast(b.err, true); return; }
    busy = true; const btn = $('#cf-save'); btn.disabled = true; btn.textContent = 'Saqlanmoqda…';
    let res = null;
    try { res = await C.rpc('fin_cp_save', { p: b.p }); }
    catch (e) {
      busy = false; if (btn.isConnected) { btn.disabled = false; btn.textContent = 'Saqlash'; }
      if (hint(e) === 'fin:cp_stir_dup') {
        if (confirm(`${errText(e)}\n\nBoshqa kontragent bo‘lsa (masalan, bankning boshqa filiali) — baribir saqlansinmi?`)) save(true);
        return;
      }
      if (hint(e) === 'fin:cp_changed') {
        C.toast('Karta shu orada boshqa foydalanuvchi tomonidan o‘zgartirilgan — yangi ma’lumot bilan qayta ochildi', true);
        try { await reloadList(); } catch (_) { /* eski ro'yxat qoladi */ }
        const fresh = LIST.find(x => cpId(x) === F.id); if (fresh) openCard(fresh); else drawList();
        return;
      }
      C.toast('Xatolik: ' + errText(e), true);
      return;
    }
    C.toast(res && res.dup && isNew ? 'Bu kontragent ro‘yxatda bor — o‘sha karta ochildi' : res && res.dup ? 'Karta allaqachon saqlangan ✓' : 'Saqlandi ✓');
    try { await reloadList(); } catch (_) { LIST = LIST.filter(x => cpId(x) !== cpId(res)).concat([res]); }
    openCard(LIST.find(x => cpId(x) === cpId(res)) || res);
  };
  $('#cf-save').onclick = () => save(false);
  if (isNew) setTimeout(() => { const t = $('#cf-name'); if (t) t.focus(); }, 50);
}

// ---------------------------------------------------------------- RP-10 ko'chirma
function openStatement(c) {
  if (!c) return;
  const today = O.today || '', p0 = periodDefault(today);
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kontragent ko‘chirmasi</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      <div><b>${esc(c.name)}</b> <span class="small muted">${esc(CP_KIND[c.kind] || c.kind)}${c.stir ? ' · STIR ' + esc(c.stir) : ''}</span></div>
      <div class="small muted" style="margin-top:4px">Pul harakati: kassa orderlari (naqd), bank o‘tkazmalari va korporativ karta to‘lovlari. Hisob-kitob qoldig‘i (qarz) — bosh kitob bilan (keyingi bosqich).</div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:0 10px">
        ${lbl('Davr boshi', `<input id="cs-from" type="date" value="${esc(p0.from)}"${today ? ` max="${esc(today)}"` : ''} style="${FLD}">`)}
        ${lbl('Davr oxiri', `<input id="cs-to" type="date" value="${esc(p0.to)}"${today ? ` max="${esc(today)}"` : ''} style="${FLD}">`)}
      </div>
      <div style="margin-top:8px"><button type="button" class="btn ghost2" id="cs-load">Ko‘rsatish</button></div>
      <div id="cs-body" style="margin-top:10px"></div>
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="cs-back">← Ro‘yxat</button><button type="button" class="btn ghost2" id="cs-xlsx" disabled>⬇ Excel (XLSX)</button><button type="button" class="btn gold" id="cs-print" disabled>🖨 Chop etish</button></div>`;
  $('#m-x').onclick = C.closeModal; $('#cs-back').onclick = drawList;
  let ST = null, busy = false;
  const btns = on => { $('#cs-print').disabled = !on; $('#cs-xlsx').disabled = !on; };
  const load = async () => {
    const from = $('#cs-from').value, to = $('#cs-to').value;
    if (!isDay(from) || !isDay(to) || from > to) { C.toast('Davrni to‘g‘ri tanlang (boshi oxiridan keyin bo‘lmasin)', true); return; }
    $('#cs-body').innerHTML = '<div class="loading">Yuklanmoqda…</div>'; btns(false); ST = null;
    try { ST = await C.rpc('fin_cp_statement', { p_id: cpId(c), p_from: from, p_to: to }); }
    catch (e) { $('#cs-body').innerHTML = ''; C.toast(errText(e), true); return; }
    const op = ST.opening || {}, tt = ST.totals || {}, cl = ST.closing || {}, A = ST.articles || {};
    let bal = num(op.out) - num(op.in);
    const arts = ids => (ids || []).map(id => (A[id] && A[id].uz) ? A[id].uz : id).join(', ');
    const rows = (ST.rows || []).map(x => { bal += num(x.out) - num(x.in);
      return `<tr><td data-label="Sana" style="white-space:nowrap">${esc(dmy(x.day))}</td><td data-label="Hujjat">${esc(x.doc || (x.src === 'legacy' ? 'eski yozuv' : ''))}</td>
        <td data-label="Operatsiya">${esc(x.opName || x.op || '')}${arts(x.arts) ? `<div class="small muted">${esc(arts(x.arts))}</div>` : ''}${x.text ? `<div class="small muted">${esc(x.text)}</div>` : ''}</td>
        <td data-label="Usul">${esc(METHOD[x.method] || x.method || '—')}</td>
        <td data-label="Olindi" style="text-align:right;white-space:nowrap">${num(x.in) ? esc(som(x.in)) : ''}</td><td data-label="Berildi" style="text-align:right;white-space:nowrap">${num(x.out) ? esc(som(x.out)) : ''}</td>
        <td data-label="Sof (yig‘ma)" style="text-align:right;white-space:nowrap">${esc(som(bal))}</td></tr>`; }).join('');
    $('#cs-body').innerHTML = `<div class="small" id="cs-sum" style="background:#eef3f1;border-radius:10px;padding:10px 12px">Davr boshigacha: berildi <b>${esc(som(op.out))}</b>, olindi <b>${esc(som(op.in))}</b> · davrda: berildi <b>${esc(som(tt.out))}</b>, olindi <b>${esc(som(tt.in))}</b> (${esc(String(num(tt.n)))} ta) · davr oxirigacha: berildi <b>${esc(som(cl.out))}</b>, olindi <b>${esc(som(cl.in))}</b> · sof <b>${esc(som(num(cl.out) - num(cl.in)))}</b></div>
      ${rows ? `<div class="tablewrap" style="max-height:360px;overflow:auto;margin-top:8px"><table id="cs-tbl"><thead><tr><th>Sana</th><th>Hujjat</th><th>Operatsiya / statiya</th><th>Usul</th><th style="text-align:right">Olindi</th><th style="text-align:right">Berildi</th><th style="text-align:right">Sof (yig‘ma)</th></tr></thead><tbody>${rows}</tbody></table></div>`
        : '<div class="empty" style="margin-top:8px">Bu davrda operatsiya yo‘q.</div>'}`;
    btns(true);
  };
  // fayl va chop etish — serverdan alohida (FD-28: jismoniy shaxs ko'chirmasi Direktordan boshqaga ismsiz)
  const fileData = () => C.rpc('fin_cp_statement', { p_id: cpId(c), p_from: ST.from, p_to: ST.to, p_file: true });
  $('#cs-load').onclick = load;
  $('#cs-print').onclick = async () => {
    if (!ST || busy) return; busy = true;
    try { const [pm, wm, F] = await Promise.all([C.finMod('fin-print'), C.finMod('fin-words'), fileData()]);
      C.printHTML(pm.cpStatementHtml(F, { org: F.org, printedBy: F.me || '', printedAt: new Date().toISOString() }, wm));
      if (F.masked) C.toast('Ismsiz nusxa (FD-28) — ismli nusxa faqat Direktorda'); }
    catch (e) { C.toast('Chop etib bo‘lmadi: ' + errText(e), true); }
    finally { busy = false; }
  };
  $('#cs-xlsx').onclick = async () => {
    if (!ST || busy) return;
    const X = window.XLSX;
    if (!X || !X.utils || !X.writeFile) { C.toast('Excel kutubxonasi hali yuklanmadi — sahifani yangilab qayta urining', true); return; }
    busy = true;
    try { const [pm, F] = await Promise.all([C.finMod('fin-print'), fileData()]);
      const sh = pm.cpStatementSheet(F, { org: F.org });
      const ws = X.utils.aoa_to_sheet(sh.rows); ws['!cols'] = sh.cols;
      const wb = X.utils.book_new(); X.utils.book_append_sheet(wb, ws, sh.name);
      X.writeFile(wb, stmtFileName(F));
      C.toast(F.masked ? 'Saqlandi: ismsiz (ID bilan) — ismli nusxa faqat Direktorda' : 'Saqlandi: kontragent ko‘chirmasi'); }
    catch (e) { C.toast('Excel fayl tuzilmadi: ' + errText(e), true); }
    finally { busy = false; }
  };
  load();
}
