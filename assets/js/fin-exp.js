// =====================================================================
// fin-exp.js — «Buxgalteriya» xarajatlari reyestri (moliya ish rejasi 2-bosqich, F2.1). admin.html kerak bo'lganda import() bilan yuklaydi.
//   Har xarajat — hujjat: to'lov usuli, sana, kontragent, hujjat № va sanasi, ilova, izoh va STATIYA QATORLARI (har qatorda statiya).
//   Server: migration/fin-exp.sql — fin_exp_refs (ma'lumotnoma), fin_exp_save (kiritish; tuzatish — replaces), fin_exp_void (bekor
//   qilish, sabab bilan). Hujjat qatorlarini «Buxgalteriya» ro'yxatiga (expenses) server yozadi; bu fayl faqat oyna va so'rov.
//   Faqat mavjud komponentlar (.modal-*, .btn, .chip, .tablewrap) — yangi CSS yo'q.
//   Kirish:  openExpenseDoc(ctx, o)  — oyna: o.doc — tuzatiladigan hujjat, o.row — tuzatiladigan eski yozuv, o.k — kassa holati
//                                     ({ live, hold, preLiveOk, preLiveTxt, cashDay(sana), lockMin, today }),
//                                     o.onSaved(res) — saqlangach (ro'yxatni yangilash), o.printReceipt(r) — chek, o.openKassa() — «Kassa»
//            showExpenseDoc(ctx, doc) — hujjatni ko'rish (buxgalter ham)
//            voidExpense(ctx, o)     — bekor qilish: o.id — hujjat yoki eski yozuv, o.what — oynadagi matn, o.onDone(res)
//            Sof funksiyalar (fin-exp.test.mjs): methodOptions, defaultMethod, articleOk, buildPayload, initForm, docNoKey, docNoClean.
// =====================================================================
import { amtRead, amtShow } from './fin-kassa.js';

let C = null;                                    // admin.html bergan yordamchilar (ctx)
let REFS = null;                                 // fin_exp_refs javobi (oyna har ochilganda yangilanadi)
export const METHOD_LBL = { bank: 'Bank o‘tkazmasi', card: 'Korporativ karta', cash: 'Naqd (orderisiz)' };
export const METHOD_CHIP = { bank: 'Bank', card: 'Karta', cash: 'Naqd' };
const CP_KIND = { supplier: 'Yetkazib beruvchi', org: 'Tashkilot', person: 'Jismoniy shaxs', bank: 'Bank', founder: 'Ta’sischi', other: 'Boshqa' };
const FLD = 'padding:10px 12px;border:1px solid var(--border);border-radius:10px;font:inherit;width:100%;background:#fff';
const $ = s => C.$(s);
const esc = s => C.esc(s);
const num = v => Number(v) || 0;
const errText = e => String((e && (e.message || e.code)) || e || 'xato');
const som = v => { const n = Math.round(num(v) * 100) / 100, a = Math.abs(n), w = Math.floor(a), t = Math.round((a - w) * 100);
  return (n < 0 ? '−' : '') + String(w).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + (t ? ',' + String(t).padStart(2, '0') : '') + ' so‘m'; };
const digits = s => String(s == null ? '' : s).replace(/[^\d]/g, '');
const dmy = d => { const s = String(d || ''); return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(8, 10) + '.' + s.slice(5, 7) + '.' + s.slice(0, 4) : s; };
const isDay = s => /^\d{4}-\d{2}-\d{2}$/.test(String(s || ''));
const lbl = (t, inner, extra) => `<label class="small" style="font-weight:700;display:flex;flex-direction:column;gap:6px;margin-top:8px${extra || ''}">${t}${inner}</label>`;
const newRef = () => 'xe-' + ((globalThis.crypto && globalThis.crypto.randomUUID) ? globalThis.crypto.randomUUID()
  : Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 12));

// Hujjat raqami kaliti — server bilan bir xil (app.fin_exp_docno_key): «№», «#» va bo'shliqlar tashlanadi, kichik harf («№ 145» = «145»).
export const docNoKey = s => String(s == null ? '' : s).replace(/№/g, '').replace(/[\s#]+/g, '').toLowerCase();
// Saqlanadigan ko'rinish — server bilan bir xil: boshidagi «№» / «#» olib tashlanadi, 60 belgigacha.
export const docNoClean = s => String(s == null ? '' : s).trim().replace(/^(?:№|#)+\s*/, '').trim().slice(0, 60);

// Taklif qilinadigan to'lov usullari (sof). k — kassa holati: { live, hold, preLiveOk, preLiveTxt }.
//   Kassa ishga tushgan: bank, karta; naqd — faqat Direktorga, kassa ishlamagan kun sanasi bilan (server ham: kassa:pre_live).
//   Kassa to'xtatilgan / qayta ishga tushishni kutmoqda: naqd (to'xtatilgan davr sanasi bilan), bank, karta.
//   Kassa hali ishga tushmagan: naqd, bank, karta (naqd — orderisiz, avvalgidek).
export function methodOptions(k) {
  k = k || {};
  if (k.live) return [['bank', METHOD_LBL.bank], ['card', METHOD_LBL.card]]
    .concat(k.preLiveOk ? [['cash', `Naqd — ${k.preLiveTxt || 'kassa ishlamagan kun'} berilgan (orderisiz)`]] : []);
  if (k.hold) return [['cash', 'Naqd — to‘xtatilgan davr sanasi bilan (orderisiz)'], ['bank', METHOD_LBL.bank], ['card', METHOD_LBL.card]];
  return [['cash', 'Naqd (orderisiz — kassa hali ishga tushmagan)'], ['bank', METHOD_LBL.bank], ['card', METHOD_LBL.card]];
}
// Boshlang'ich usul: tuzatishda — avvalgisi (taklif qilinsa); kassa ishlasa — bank; aks holda — ro'yxatning birinchisi (naqd).
export function defaultMethod(k, cur) {
  const ms = methodOptions(k).map(m => m[0]);
  if (cur && ms.includes(cur)) return cur;
  return k && k.live ? 'bank' : ms[0];
}
// Statiya shu usulda tanlanadimi — server ma'lumotnomasidagi belgi (fin_exp_refs: app.fin_exp_article_ok bilan bir xil).
export const articleOk = (a, m) => !!(a && (m === 'bank' ? a.bank : m === 'card' ? a.card : m === 'cash' ? a.cash : false));

// Oynaning boshlang'ich holati (sof): yangi; o.doc — hujjatni tuzatish (qatorlari bilan); o.row — eski (hujjatsiz) yozuvni tuzatish.
export function initForm(o, k, today) {
  o = o || {};
  const d = o.doc, r = o.row, amt = v => (v === null || v === undefined || v === '') ? '' : amtShow(String(v));
  if (d) return { method: defaultMethod(k, d.method), date: isDay(d.date) ? d.date : today, cp: d.counterpartyId || '', docNo: d.docNo || '',
    docDate: isDay(d.docDate) ? d.docDate : '', att: d.attachment || '', note: d.note || '', replaces: d.id,
    lines: (Array.isArray(d.lines) && d.lines.length ? d.lines : [{}]).map(l => ({ articleId: l.articleId || '', amount: amt(l.amount), note: l.note || '' })) };
  if (r) return { method: defaultMethod(k, r.method), date: isDay(r.date) ? r.date : today, cp: r.counterpartyId || '', docNo: '', docDate: '', att: '',
    note: String(r.note || '').trim().slice(0, 300), replaces: r._id || r.id,
    lines: [{ articleId: r.articleId || '', amount: amt(r.amount), note: '' }] };
  return { method: defaultMethod(k), date: today, cp: '', docNo: '', docDate: '', att: '', note: '', replaces: null, lines: [{ articleId: '', amount: '', note: '' }] };
}

// Shakl → server so'rovi (sof). Bo'sh qatorlar tashlanadi; xato bo'lsa — { err } (server ham xuddi shu qoidalarni tekshiradi).
//   f: { ref, method, date, today, lockMin, cp, docNo, docDate, att, note, replaces, lines: [{ articleId, amount (matn), note }],
//        cashDay (kassa ishlayotganda: sana kassa ishlamagan kunmi — funksiya), cashTxt };
//   arts — ma'lumotnoma statiyalari (fin_exp_refs.articles). Natija: { p, total } | { err }.
export function buildPayload(f, arts) {
  f = f || {};
  const A = new Map((arts || []).map(a => [a.id, a]));
  const date = String(f.date || '');
  if (!isDay(date)) return { err: 'Sanani tanlang' };
  if (f.today && date > f.today) return { err: 'Sana bugundan keyin bo‘lmaydi' };
  if (f.lockMin && date < f.lockMin) return { err: `Bu sana yopilgan davrda — ${dmy(f.lockMin)} yoki keyingi sana bo‘lsin` };
  const method = f.method;
  if (!['bank', 'card', 'cash'].includes(method)) return { err: 'To‘lov usulini tanlang' };
  // kassa ishlayotganda naqd — faqat kassa ishlamagan kun sanasi bilan (f.cashDay — admin.html kassaPreLiveDay; server ham: kassa:pre_live)
  if (method === 'cash' && typeof f.cashDay === 'function' && !f.cashDay(date))
    return { err: `Naqd xarajat — «Kassa» → «+ Chiqim so‘rovi». Bu yerda faqat sanasi ${f.cashTxt || 'kassa ishlamagan kun'} bo‘lsa` };
  const docNo = docNoClean(f.docNo);
  if (method === 'bank' && !f.cp) return { err: 'Bank o‘tkazmasida kontragent (kimga to‘langani) majburiy' };
  if (method === 'bank' && !docNoKey(docNo)) return { err: 'Bank o‘tkazmasida hujjat (to‘lov topshiriqnomasi) raqami majburiy' };
  const docDate = String(f.docDate || '');
  if (docDate && !isDay(docDate)) return { err: 'Hujjat sanasi noto‘g‘ri' };
  if (docDate && f.today && docDate > f.today) return { err: 'Hujjat sanasi bugundan keyin bo‘lmaydi' };
  const note = String(f.note || '').trim().slice(0, 300);
  const rows = (f.lines || []).filter(l => l && (l.articleId || String(l.amount == null ? '' : l.amount).trim() || String(l.note || '').trim()));
  if (!rows.length) return { err: 'Kamida bitta statiya qatori kerak' };
  if (rows.length > 20) return { err: 'Bitta hujjatda ko‘pi bilan 20 qator' };
  const lines = []; let total = 0;
  for (let i = 0; i < rows.length; i++) {
    const l = rows[i], n = i + 1, a = A.get(l.articleId);
    if (!l.articleId) return { err: `${n}-qator: statiyani tanlang` };
    if (!a) return { err: `${n}-qator: statiya ro‘yxatda yo‘q — oynani yopib, qayta oching` };
    if (!articleOk(a, method)) return { err: `${n}-qator: «${a.nameUz}» statiyasi bo‘yicha ${METHOD_LBL[method].toLowerCase()} orqali xarajat yozilmaydi` };
    const r = amtRead(l.amount);
    if (r.err) return { err: `${n}-qator: ${r.err}` };
    if (!(r.v > 0)) return { err: `${n}-qator: summani kiriting` };
    const ln = String(l.note || '').trim().slice(0, 300);
    if (a.needsNote && ln.length < 3 && note.length < 3) return { err: `${n}-qator: «${a.nameUz}» statiyasi uchun izoh majburiy` };
    lines.push({ articleId: a.id, amount: r.v, note: ln }); total += r.v;
  }
  if (!(total < 1e12)) return { err: 'Hujjat summasi juda katta' };
  const p = { clientRef: f.ref, method, date, counterpartyId: f.cp || null, docNo, docDate: docDate || null,
              attachment: String(f.att || '').trim().slice(0, 500), note, lines };
  if (f.replaces) p.replaces = f.replaces;
  return { p, total };
}

async function loadRefs() { REFS = await C.rpc('fin_exp_refs', {}); return REFS; }
const artName = id => { const a = ((REFS && REFS.articles) || []).find(x => x.id === id); return a ? a.nameUz : (id || '—'); };

// ---------------------------------------------------------------- hujjat oynasi
export async function openExpenseDoc(ctx, o) {
  C = ctx; o = o || {};
  const k = o.k || {};
  $('#modal').innerHTML = `<div class="modal-h"><h3>${o.doc || o.row ? 'Xarajatni tuzatish' : 'Xarajat qo‘shish'}</h3><button class="x" id="m-x">×</button></div><div class="modal-b"><div class="loading">Yuklanmoqda…</div></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal;
  try { await loadRefs(); } catch (e) { $('#modal').querySelector('.modal-b').innerHTML = `<div class="empty">Ma’lumotnoma yuklanmadi: ${esc(errText(e))}</div>`; return; }
  const today = isDay(REFS.today) ? REFS.today : (k.today || '');
  const F = initForm(o, k, today);
  F.ref = newRef();
  const A = new Map((REFS.articles || []).map(a => [a.id, a]));
  const methods = methodOptions(k);
  const lockMin = k.lockMin || '';
  const repTxt = o.doc ? 'hujjat' : 'yozuv';
  $('#modal').innerHTML = `<div class="modal-h"><h3>${o.doc || o.row ? 'Xarajatni tuzatish' : 'Xarajat qo‘shish'}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      ${F.replaces ? `<div class="small" style="background:#FEF3E2;color:#B54708;border-radius:10px;padding:10px 12px"><b>Tuzatish:</b> eski ${repTxt} bekor qilinadi va o‘rniga shu hujjat yoziladi — ikkalasi ham reyestrda qoladi (kim, qachon, nima o‘zgargani ko‘rinadi).</div>` : ''}
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:0 10px">
        ${lbl('To‘lov sanasi', `<input type="date" id="xe-date" value="${esc(F.date)}"${today ? ` max="${esc(today)}"` : ''}${lockMin ? ` min="${esc(lockMin)}"` : ''} style="${FLD}">`)}
        ${lbl('To‘lov usuli', `<select id="xe-method" style="${FLD}">${methods.map(m => `<option value="${m[0]}"${m[0] === F.method ? ' selected' : ''}>${esc(m[1])}</option>`).join('')}</select>`)}
      </div>
      <div class="small" id="xe-mhint" style="margin-top:6px"></div>
      <div id="xe-cplbl" class="small" style="font-weight:700;margin-top:10px"></div><div id="xe-cpbox" style="margin-top:6px"></div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:0 10px">
        ${lbl('<span id="xe-nolbl">Hujjat №</span>', `<input type="text" id="xe-no" maxlength="60" value="${esc(F.docNo)}" placeholder="to‘lov topshiriqnomasi / hisob-faktura / chek" style="${FLD}">`)}
        ${lbl('Hujjat sanasi <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<input type="date" id="xe-dd" value="${esc(F.docDate)}"${today ? ` max="${esc(today)}"` : ''} style="${FLD}">`)}
      </div>
      <div class="small" style="font-weight:700;margin-top:12px">Statiyalar <span class="muted" style="font-weight:500">— har qatorda statiya va summa; bitta to‘lov bir necha statiyaga bo‘linishi mumkin</span></div>
      <div id="xe-lines"></div>
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;margin-top:8px">
        <button type="button" class="btn sm ghost2" id="xe-add">+ Qator qo‘shish</button>
        <div class="small">Jami: <b id="xe-total" style="color:var(--bad)">0 so‘m</b></div>
      </div>
      ${lbl('Ilova <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<input type="text" id="xe-att" maxlength="500" value="${esc(F.att)}" placeholder="masalan: hisob-faktura, dalolatnoma, chek (qog‘ozda — papkada)" style="${FLD}">`)}
      ${lbl('Izoh <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<input type="text" id="xe-note" maxlength="300" value="${esc(F.note)}" placeholder="masalan: yanvar oyi uchun" style="${FLD}">`)}
      ${k.live ? `<div class="small" style="margin-top:10px;background:#E8F1FD;color:#175CD3;border-radius:10px;padding:10px 12px"><b>Kassa ishga tushgan.</b> Naqd xarajat — «Kassa» bo‘limida: «+ Chiqim so‘rovi» → «Xarajat» (pul berilgach xarajat bu ro‘yxatga o‘zi tushadi).${k.preLiveOk ? ` Bu yerda naqd — faqat sanasi ${esc(k.preLiveTxt || '')} bo‘lgan, kechikib topilgan xarajat (kassa orderisiz, haqiqiy sanasi bilan).` : ''} Hisobdor shaxs (zavxoz va b.) sarflagan pul — «Kassa» → «Avans hisoboti». ${o.openKassa ? '<a href="#" id="xe-kassa" style="font-weight:700">Kassaga o‘tish</a>' : ''}</div>` : ''}
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="xe-save">Saqlash</button></div>`;
  $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  { const ek = $('#xe-kassa'); if (ek) ek.onclick = ev => { ev.preventDefault(); C.closeModal(); o.openKassa(); }; }

  const total = () => F.lines.reduce((s, l) => { const r = amtRead(l.amount); return s + (r.v || 0); }, 0);
  const showTotal = () => { const t = $('#xe-total'); if (t) t.textContent = som(total()); };
  const artOpts = sel => {
    const arts = (REFS.articles || []).filter(a => articleOk(a, F.method));
    const grp = (kind, title) => { const xs = arts.filter(a => a.kind === kind);
      return xs.length ? `<optgroup label="${esc(title)}">${xs.map(a => `<option value="${esc(a.id)}"${a.id === sel ? ' selected' : ''}>${esc(a.nameUz)}</option>`).join('')}</optgroup>` : ''; };
    return '<option value="">— statiya —</option>' + grp('EX', 'Xarajatlar') + grp('OP', 'Soliq, yetkazib beruvchi, asosiy vosita, tovar');
  };
  const drawLines = () => {
    $('#xe-lines').innerHTML = F.lines.map((l, i) => `<div data-i="${i}" style="display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin-top:6px;padding:8px;border:1px solid var(--border);border-radius:10px">
        <select data-f="articleId" aria-label="Statiya" style="${FLD};flex:2 1 220px;width:auto">${artOpts(l.articleId)}</select>
        <input data-f="amount" type="text" inputmode="numeric" aria-label="Summa" placeholder="Summa (so‘m)" value="${esc(l.amount)}" style="${FLD};flex:1 1 120px;width:auto">
        <input data-f="note" type="text" maxlength="300" aria-label="Qator izohi" placeholder="Izoh (ixtiyoriy)" value="${esc(l.note)}" style="${FLD};flex:2 1 160px;width:auto">
        ${F.lines.length > 1 ? `<button type="button" class="btn sm ghost" data-del="${i}" title="Qatorni olib tashlash" aria-label="Qatorni olib tashlash">✕</button>` : ''}
      </div>`).join('');
    $('#xe-lines').querySelectorAll('[data-i]').forEach(row => {
      const i = Number(row.dataset.i);
      row.querySelectorAll('[data-f]').forEach(el => el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', () => {
        if (el.dataset.f === 'amount') { const v = amtShow(el.value); if (v !== el.value) el.value = v; }   // mingliklar; ajratkich jim o'chirilmaydi
        F.lines[i][el.dataset.f] = el.value; showTotal();
      }));
    });
    $('#xe-lines').querySelectorAll('[data-del]').forEach(b => b.onclick = () => { F.lines.splice(Number(b.dataset.del), 1); drawLines(); });
    showTotal();
  };
  const drawCp = sel => {
    const req = F.method === 'bank';
    $('#xe-cplbl').innerHTML = 'Kontragent ' + (req ? '<span style="color:var(--bad)">*</span> <span class="muted" style="font-weight:500">— kimga to‘langani</span>' : '<span class="muted" style="font-weight:500">— ixtiyoriy</span>');
    const cps = REFS.counterparties || [];
    $('#xe-cpbox').innerHTML = `<div style="display:flex;gap:6px"><select id="xe-cp" aria-label="Kontragent" style="${FLD}"><option value="">— ${req ? 'tanlang' : 'ko‘rsatilmagan'} —</option>${cps.map(c => `<option value="${esc(c.id)}"${c.id === sel ? ' selected' : ''}>${esc(c.name + (c.stir ? ' · STIR ' + c.stir : ''))}</option>`).join('')}</select><button type="button" class="btn sm" id="xe-cpnew" title="Yangi kontragent">+ yangi</button></div><div id="xe-cpnewbox"></div>`;
    F.cp = cps.some(c => c.id === sel) ? sel : '';
    $('#xe-cp').onchange = () => { F.cp = $('#xe-cp').value; };
    $('#xe-cpnew').onclick = () => {
      $('#xe-cpnewbox').innerHTML = `<div style="border:1px dashed var(--border);border-radius:10px;padding:8px;margin-top:6px"><input id="xe-cn" type="text" placeholder="Nomi (to‘liq)" maxlength="200" style="${FLD}"><div style="display:flex;gap:6px;margin-top:6px;flex-wrap:wrap"><select id="xe-ck" style="${FLD};flex:1 1 150px;width:auto">${['supplier', 'org', 'bank', 'person', 'other'].map(x => `<option value="${x}">${esc(CP_KIND[x])}</option>`).join('')}</select><input id="xe-cs" type="text" inputmode="numeric" placeholder="STIR — 9 raqam (ixtiyoriy)" maxlength="14" style="${FLD};flex:1 1 130px;width:auto"><button type="button" class="btn sm gold" id="xe-cadd">Qo‘shish</button></div></div>`;
      let busy = false;
      $('#xe-cadd').onclick = async () => {
        if (busy) return; const nm = $('#xe-cn').value.trim(); if (nm.length < 2) { C.toast('Kontragent nomini yozing', true); return; }
        busy = true; const b = $('#xe-cadd'); b.disabled = true;
        try { const c = await C.rpc('fin_counterparty_save', { p_id: null, p_kind: $('#xe-ck').value, p_name: nm, p_stir: digits($('#xe-cs').value) });
          await loadRefs(); drawCp(c.id); C.toast(c.dup ? 'Bu kontragent ro‘yxatda bor — o‘sha tanlandi ✓' : 'Kontragent qo‘shildi ✓'); }
        catch (e) { C.toast('Xatolik: ' + errText(e), true); }
        finally { busy = false; if (b.isConnected) b.disabled = false; }
      };
    };
  };
  const drawMethod = () => {
    let dropped = 0;
    F.lines.forEach(l => { if (l.articleId && !articleOk(A.get(l.articleId), F.method)) { l.articleId = ''; dropped++; } });
    const hint = F.method === 'bank' ? 'Bank o‘tkazmasi: kontragent va to‘lov topshiriqnomasi raqami majburiy.'
      : F.method === 'card' ? 'Korporativ karta: har xarid alohida, chek bo‘yicha (kontragent va chek № — ixtiyoriy). Kartani to‘ldirish xarajat emas — yozilmaydi.'
      : k.live ? `Naqd — faqat sanasi ${esc(k.preLiveTxt || 'kassa ishlamagan kun')} bo‘lgan, kechikib topilgan xarajat (kassa orderisiz, haqiqiy sanasi bilan).`
      : k.hold ? 'Kassa to‘xtatilgan: naqd — faqat to‘xtatilgan davr sanasi bilan (oxirgi kassa kuni va undan oldingi sana bilan yozilmaydi).'
      : 'Naqd (orderisiz): kassa hali ishga tushmagan.';
    $('#xe-mhint').innerHTML = `<span class="muted">${hint}</span>` + (dropped ? ` <b style="color:var(--bad)">${dropped} qatordagi statiya bu usulda yo‘q — qayta tanlang.</b>` : '');
    $('#xe-nolbl').innerHTML = 'Hujjat № ' + (F.method === 'bank' ? '<span style="color:var(--bad)">*</span>' : '<span class="muted" style="font-weight:500">— ixtiyoriy</span>');
    drawCp(F.cp); drawLines();
  };
  $('#xe-method').onchange = () => { F.method = $('#xe-method').value; drawMethod(); };
  $('#xe-add').onclick = () => { if (F.lines.length >= 20) { C.toast('Bitta hujjatda ko‘pi bilan 20 qator', true); return; } F.lines.push({ articleId: '', amount: '', note: '' }); drawLines(); };
  drawMethod();

  let busy = false;
  $('#xe-save').onclick = async () => {
    if (busy) return;
    Object.assign(F, { date: $('#xe-date').value, docNo: $('#xe-no').value, docDate: $('#xe-dd').value, att: $('#xe-att').value, note: $('#xe-note').value, cp: $('#xe-cp') ? $('#xe-cp').value : F.cp });
    const b = buildPayload({ ...F, today, lockMin, cashDay: k.live ? k.cashDay : null, cashTxt: k.preLiveTxt }, REFS.articles);
    if (b.err) { C.toast(b.err, true); return; }
    busy = true; const btn = $('#xe-save'); btn.disabled = true; btn.textContent = 'Saqlanmoqda…';
    let res = null;
    try {
      try { res = await C.rpc('fin_exp_save', { p: b.p }); }
      catch (e) {
        // boshqa oynadan shu to'lov allaqachon kiritilgan bo'lishi mumkin (fin:exp_dup) — tasdiqlansa o'sha kalit bilan qayta yuboriladi
        if (String((e && e.hint) || '') !== 'fin:exp_dup') throw e;
        if (!confirm(`${errText(e)}\n\nSaqlansinmi?`)) { busy = false; btn.disabled = false; btn.textContent = 'Saqlash'; return; }
        res = await C.rpc('fin_exp_save', { p: { ...b.p, dupOk: true } });
      }
    } catch (e) {
      C.toast('Xatolik: ' + errText(e), true); busy = false;
      if (btn.isConnected) { btn.disabled = false; btn.textContent = 'Saqlash'; }
      return;
    }
    C.toast(res && res.dup ? 'Bu hujjat allaqachon saqlangan ✓' : 'Saqlandi ✓');
    try { if (o.onSaved) await o.onSaved(res); } catch (_) { /* ro'yxat keyin yangilanadi */ }
    savedModal(res, b.total, o);
  };
}

// Saqlangandan keyin: qisqa natija va chek (80/58 mm) tugmasi
function savedModal(res, total, o) {
  const lines = (res && Array.isArray(res.lines)) ? res.lines : [];
  const what = lines.map(l => artName(l.articleId)).filter((x, i, a) => a.indexOf(x) === i).join(', ');
  $('#modal').innerHTML = `<div class="modal-h"><h3>✓ Xarajat saqlandi</h3><button class="x" id="m-x2">×</button></div>
    <div class="modal-b"><div class="small" style="background:#fdecec;color:#B42318;border-radius:10px;padding:12px;font-weight:700">${esc(what || 'Xarajat')} — ${esc(som(total || (res && res.amount)))}</div>
      <div class="small muted" style="margin-top:8px">${esc(METHOD_LBL[res && res.method] || '')}${res && res.docNo ? ' · № ' + esc(res.docNo) : ''}${res && res.partyName ? ' · ' + esc(res.partyName) : ''}. Termal printerda (80/58 mm) chek chiqarishingiz mumkin.</div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="xe-close">Yopish</button>${o.printReceipt ? '<button type="button" class="btn gold" id="xe-print">🧾 Chek chiqarish</button>' : ''}</div>`;
  C.openModal();
  $('#m-x2').onclick = C.closeModal; $('#xe-close').onclick = C.closeModal;
  const pb = $('#xe-print');
  if (pb) pb.onclick = () => o.printReceipt({ kind: 'expense', who: (res && res.partyName) || '', amount: total || (res && res.amount),
    reason: `${what}${res && res.note ? ' · ' + res.note : ''}`, period: String((res && res.date) || '').slice(0, 7), date: (res && res.date) || '' });
}

// ---------------------------------------------------------------- hujjatni ko'rish
export async function showExpenseDoc(ctx, d) {
  C = ctx;
  if (!d) return;
  if (!REFS) { try { await loadRefs(); } catch (_) { /* statiya kodi ko'rsatiladi */ } }
  const st = d.status === 'void' ? `<span class="chip" style="background:#FDECEC;color:#B42318;border-color:transparent">Bekor qilingan</span>` : `<span class="chip" style="background:#E7F6EC;color:#157347;border-color:transparent">Kiritilgan</span>`;
  const row = (k, v) => v ? `<tr><td class="small muted" style="white-space:nowrap">${esc(k)}</td><td>${v}</td></tr>` : '';
  const lines = Array.isArray(d.lines) ? d.lines : [];
  $('#modal').innerHTML = `<div class="modal-h"><h3>Xarajat hujjati ${st}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      <div class="tablewrap"><table><tbody>
        ${row('To‘lov sanasi', esc(dmy(d.date)))}
        ${row('Usul', esc(d.origin === 'legacy' ? 'Eski yozuv (reyestrdan oldin)' + (d.method ? ' · ' + (METHOD_LBL[d.method] || d.method) : '') : METHOD_LBL[d.method] || d.method || ''))}
        ${row('Kontragent', esc(d.partyName || ''))}
        ${row('Hujjat', esc([d.docNo ? '№ ' + d.docNo : '', d.docDate ? dmy(d.docDate) : ''].filter(Boolean).join(' · ')))}
        ${row('Ilova', esc(d.attachment || ''))}
        ${row('Izoh', esc(d.note || ''))}
        ${row('Kiritdi', esc([d.createdByName || '', d.createdAt ? new Date(d.createdAt).toLocaleString('ru-RU', { timeZone: 'Asia/Tashkent' }) : ''].filter(Boolean).join(' · ')))}
        ${d.status === 'void' ? row('Bekor qildi', esc([d.voidedByName || '', d.voidedAt ? new Date(d.voidedAt).toLocaleString('ru-RU', { timeZone: 'Asia/Tashkent' }) : '', d.voidReason || ''].filter(Boolean).join(' · '))) : ''}
        ${d.replaces ? row('Tuzatilgan hujjat', '<span class="small muted">' + esc(d.replaces) + '</span>') : ''}
        ${d.replacedBy ? row('O‘rniga yozilgan', '<span class="small muted">' + esc(d.replacedBy) + '</span>') : ''}
      </tbody></table></div>
      <div class="tablewrap" style="margin-top:10px"><table><thead><tr><th>№</th><th>Statiya</th><th>Izoh</th><th style="text-align:right">Summa</th></tr></thead><tbody>
        ${lines.map((l, i) => `<tr><td class="num">${i + 1}</td><td>${esc(l.articleId ? artName(l.articleId) : (l.category || '—'))}</td><td>${esc(l.note || '')}</td><td style="text-align:right;white-space:nowrap">${esc(som(l.amount))}</td></tr>`).join('')}
        <tr><td></td><td colspan="2"><b>Jami</b></td><td style="text-align:right;white-space:nowrap"><b>${esc(som(d.amount))}</b></td></tr>
      </tbody></table></div>
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
}

// ---------------------------------------------------------------- bekor qilish
export function voidExpense(ctx, o) {
  C = ctx; o = o || {};
  $('#modal').innerHTML = `<div class="modal-h"><h3>Xarajatni bekor qilish</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small">${esc(o.what || '')}</div>
      <div class="small muted" style="margin-top:8px">Xarajat «Buxgalteriya» hisobidan chiqadi; reyestrda «bekor qilingan» bo‘lib qoladi (kim, qachon, nima sababdan — ko‘rinadi). Sababi (kamida 3 belgi):</div>
      <textarea id="xe-reason" rows="3" maxlength="500" style="${FLD};margin-top:8px"></textarea></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button><button type="button" class="btn danger" id="xe-vok">Bekor qilish</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  let busy = false;
  $('#xe-vok').onclick = async () => {
    if (busy) return;
    const r = $('#xe-reason').value.trim(); if (r.length < 3) { C.toast('Bekor qilish sababini yozing (kamida 3 belgi)', true); return; }
    busy = true; const b = $('#xe-vok'); b.disabled = true;
    try { const res = await C.rpc('fin_exp_void', { p_id: o.id, p_reason: r }); C.closeModal(); C.toast(res && res.dup ? 'Allaqachon bekor qilingan' : 'Bekor qilindi ✓'); if (o.onDone) await o.onDone(res); }
    catch (e) { C.toast('Xatolik: ' + errText(e), true); }
    finally { busy = false; if (b.isConnected) b.disabled = false; }
  };
  setTimeout(() => { const t = $('#xe-reason'); if (t) t.focus(); }, 50);
}
