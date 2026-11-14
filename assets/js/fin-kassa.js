// =====================================================================
// fin-kassa.js — «Kassa» bo'limi (moliya ish rejasi 1a, F1.12). admin.html uni kerak bo'lganda import() bilan yuklaydi.
//   Faqat mavjud komponentlar (.page-head, .card, .acc-kpis, .tablewrap, .btn, .chip, #modal) — yangi CSS yo'q; v1 va v2 da bir xil.
//   Barcha yozish amallari — serverdagi kassa funksiyalari (migration/kassa-docs.sql, kassa-day.sql) orqali; bu fayl faqat
//   ko'rsatadi va so'rov yuboradi. Raqam, sana, qoldiq va huquqni SERVER belgilaydi.
//   F1.15: kunlik hisobot (RP-02, «kimdan / kimga qancha» — kun oynasida va chop etishda) va nazorat ro'yxati (RP-06).
//   F1.16: «Davr» — davr surati (yil / oy yakuni) va yopilgan davr qulfi.
//   Kirish:  renderKassa(ctx)            — sahifa
//            approvalCount(ctx)          — «Tasdiqlash» bo'limidagi navbat soni
//            approvalRender(ctx, el)     — «Tasdiqlash» bo'limidagi navbat ro'yxati
// =====================================================================
let C = null;                                   // admin.html bergan yordamchilar (ctx)
const ST = { desk: 'main', ov: null, refs: null, people: null, students: null, checks: null };
const SERVER_VER = 10;                           // shu sahifa kutadigan server relizi (migration/fin-version.sql: app.kassa_version) — birga oshiriladi
const NOMINALS = [200000, 100000, 50000, 20000, 10000, 5000, 2000, 1000, 500, 200, 100, 50];
const PARTY_LBL = { student: 'O‘quvchi (to‘lovchi)', employee: 'Xodim', counterparty: 'Kontragent', bank: 'Bank', founder: 'Ta’sischi', other: 'Boshqa (yoziladi)' };
const CP_KIND = { supplier: 'Yetkazib beruvchi', org: 'Tashkilot', person: 'Jismoniy shaxs', bank: 'Bank', founder: 'Ta’sischi', other: 'Boshqa' };
// Kontragent turi tasdig'i (sec-3): «Jismoniy shaxs» / «Boshqa» turini buxgalter yoki Direktor tasdiqlaydi; tasdiqlanguncha kontragent yuridik
//   shaxs hisoblanadi (kassadan naqd to'lovga Direktor tasdig'i). Server qoidasi — kassa_refs: «org» (app.kassa_is_org), «confirmed»;
//   «org» bo'lmagan (eski) javobda — tur bo'yicha. Sof funksiyalar (fin-kassa.test.mjs).
export const cpUnconfirmed = c => !!c && (c.kind === 'person' || c.kind === 'other') && c.confirmed === false;
export const cpIsOrg = c => !!c && (typeof c.org === 'boolean' ? c.org : (c.kind === 'supplier' || c.kind === 'org' || cpUnconfirmed(c)));
export const cpLabel = c => String((c && c.name) || '') + (c && c.stir ? ' · STIR ' + c.stir : '') + (cpUnconfirmed(c) ? ' · turi tasdiqlanmagan' : '');
// Vazifalar ajratilishi (sec-1, sec-5; server — kassa_doc_approve, kassa_doc_pay): 2-ro'yxat xodimi o'zi so'ragan va o'z xodim kartalariga
//   (me.cards — ikkinchi lavozim kartasi ham) beriladigan pulni tasdiqlamaydi; pul oluvchi 2-ro'yxat xodimi bo'lsa (me.l2Cards — faqat
//   Direktorga), 2-ro'yxat bosqichini Direktor imzolaydi; o'zi (2-ro'yxat sifatida) tasdiqlagan so'rov pulini bermaydi. Sof funksiyalar
//   (fin-kassa.test.mjs).
export const canApproveList2 = (d, m) => {
  if (!(d && m && d.status === 'draft' && d.needsList2 && !d.approvedBy && d.requestedBy !== m.uid)) return false;
  const emp = d.partyType === 'employee' && !!d.partyId;
  if (m.list2) return !(emp && (m.cards || []).includes(d.partyId));
  return !!(m.director && emp && (m.l2Cards || []).includes(d.partyId));
};
export const canPayDoc = (d, m) => !!(d && m && d.status === 'approved' && (m.operator || m.director) && (!d.sourceTable || d.op === 'out_refund') && d.approvedBy !== m.uid);
// Kassa egasi va smena topshirish (sec-2, state-6; server — kassa_day_close, kassa_handover, kassa_handover_accept / _cancel). Sof funksiyalar
//   (fin-kassa.test.mjs). Kassa egasi — kun kassiri ("cashierUid"); egasi hali aniqlanmagan kunda kassa operatori o'zi egasi hisoblanadi.
//   Egasi bo'lmagan kassir, Direktor va Moliya menejeri — kassir o'rniga: kunni yopish va smena topshirishda kamida 2 kishilik komissiya.
export const deskHolder = (od, m) => (od && od.cashierUid) || (m && m.operator ? m.uid : null);
export const needCommission = (od, m) => !(m && m.operator) || deskHolder(od, m) !== (m && m.uid);
//   Kutilayotgan smena topshirish (kassa_state → handover) — kim nima qila oladi: qabul qiluvchi — «Qabul qildim» / «Rad etish» (faqat o'z
//   hisobidan); topshiruvchi (kassa egasi yoki yozgan xodim) va Direktor — «Bekor qilish».
export function handoverRole(h, m) {
  if (!h || !m || h.status !== 'pending') return { receiver: false, canAccept: false, canCancel: false };
  const receiver = h.toUid === m.uid, giver = h.byUid === m.uid || (!!h.fromUid && h.fromUid === m.uid);
  return { receiver, giver, canAccept: receiver && !!m.operator, canCancel: receiver || giver || !!m.director };
}
// Smena topshirishda sanalgan order (g6v-2; server — kassa_doc_void, kassa:void_counted): raqami qabul qilingan topshirishlar yozilgan
//   paytdagi eng katta raqamgacha (kun javobida countedKo1 / countedKo2). Kassir uni bekor qilmaydi — 2-ro'yxat yoki Direktor bekor qiladi.
export const countedAtHandover = (d, od) => !!(d && od) && num(d.no) > 0 && num(d.no) <= num(d.form === 'KO1' ? od.countedKo1 : d.form === 'KO2' ? od.countedKo2 : 0);
// «Bekor» tugmasi (server — kassa_doc_void): ochiq kun orderi, tizim hujjati emas; bog'langanlardan faqat naqd o'quv to'lovi va naqd maosh
//   orderi (bog'langan yozuv ham teskari bo'ladi; qaytarish — yo'q); kassir — faqat o'zi o'tkazgan va smena topshirishda sanalmagan orderni.
export const canVoidDoc = (d, m, od) => !!(od && d && m) && d.status === 'posted' && !d.isSystem && (!d.sourceTable || d.op === 'in_tuition' || d.op === 'out_salary')
  && !!(m.director || m.list2 || (m.operator && d.postedBy === m.uid && !countedAtHandover(d, od)));
// Kamomad qarori: nega standart javobgar yo'q (g6v-3) — server matni (kassa_overview → shortages: defaultWhy; qaror xatosi ham shu manbadan);
//   eski serverda (defaultWhy yo'q) — sahifaning avvalgi matni. Standart javobgar bor bo'lsa — bo'sh.
export function shortageWhy(x) {
  if (!x || x.defaultParty) return '';
  if (typeof x.defaultWhy === 'string' && x.defaultWhy) return x.defaultWhy;
  const byOther = !!(x.countedBy && x.countedBy !== x.cashierUid);
  return !x.cashierUid ? 'Kassa egasi (kun kassiri) aniqlanmagan' : byOther ? 'Pulni kassa egasining o‘zi sanamagan (kassir o‘rniga sanalgan)' : 'Kassir hisobi xodim kartasiga bog‘lanmagan';
}
// Kun farqi matni (acc-6): kunni yopishdagi farq va smena topshirishdagi farqlar yonma-yon; smena farqi bo'lmasa — avvalgidek (faqat summa).
const sgnS = v => `${num(v) > 0 ? '+' : ''}${som(v)}`;
export function diffText(closeDiff, handovers) {
  const hd = (handovers || []).map(num).filter(x => x !== 0);
  if (!hd.length) return sgnS(closeDiff);
  return [num(closeDiff) ? 'yopishda ' + sgnS(closeDiff) : '', ...hd.map(x => 'smenada ' + sgnS(x))].filter(Boolean).join(', ');
}
// Kunni yopish / smena topshirish — qurilma navbatidagi hali yuborilmagan naqd to'lovlar (state-2; server — kassa_day_close / kassa_handover
//   pendingRefs): har biri kaliti (payId) va summasi bilan yuboriladi. Server shu payt o'tib ketganlarini hisobga olmaydi (ular qoldiqda bor),
//   qolganini sanashdan ayiradi va saqlaydi — keyin kelgan kech kirim orderi shu kalit bilan bog'lanadi. ob — admin.html outboxCash().
//   «old» — eski sahifa (kalitlarsiz soni / summa): yuborilmaydi, sahifani yangilash kerak. Sof funksiya (fin-kassa.test.mjs).
export function outboxRefs(ob) {
  const seen = new Set(), refs = [];
  for (const r of ((ob && ob.refs) || [])) {
    const ref = String((r && r.ref) || ''), amount = Math.round(num(r && r.amount) * 100) / 100;
    if (!/^man_[A-Za-z0-9_]{3,64}$/.test(ref) || !(amount > 0) || seen.has(ref)) continue;
    seen.add(ref); refs.push({ ref, amount });
  }
  return { refs, count: refs.length, sum: Math.round(refs.reduce((t, r) => t + r.amount, 0) * 100) / 100, old: !!ob && !Array.isArray(ob.refs) && num(ob.count) > 0 };
}
// g7v-3: shu kungi qabul qilingan smena topshirishlarida e'lon qilingan, hali kelmagan navbat yozuvlari (kun javobidagi pendingOpen.refs,
//   kind 'handover'; ochiq kunda boshqasi yo'q) — shu qurilma navbatidagilaridan (own — outboxRefs().refs) tashqari. Server kunni yopish va
//   smena topshirishda ularni o'zi qo'shadi (app.kassa_pending_merge): oyna ko'rsatadi va farqqa qo'shadi — oldindan ko'rilgan farq server
//   natijasiga teng. room (berilsa) — qolgan joy: sanalgan − shu qurilma navbati − «Қ» blankalari; server kabi kichigidan boshlab sig'guncha
//   olinadi, sig'maganlari ayirilmaydi (left / leftSum — soni va summasi; g7b-v1). Sof funksiya (fin-kassa.test.mjs).
export function handoverRefs(po, own, room) {
  const skip = new Set((own || []).map(r => String((r && r.ref) || ''))), seen = new Set(), all = [];
  for (const r of ((po && po.refs) || [])) {
    const ref = String((r && r.ref) || ''), amount = Math.round(num(r && r.amount) * 100) / 100;
    if (!r || r.kind !== 'handover' || !ref || !(amount > 0) || skip.has(ref) || seen.has(ref)) continue;
    seen.add(ref); all.push({ ref, amount });
  }
  let refs = all;
  if (room != null && Number.isFinite(Number(room))) {
    let rest = Math.round(Number(room) * 100); refs = [];
    for (const r of all.slice().sort((a, b) => a.amount - b.amount || (a.ref < b.ref ? -1 : a.ref > b.ref ? 1 : 0))) {
      const c = Math.round(r.amount * 100); if (c > rest) break;   // kichigidan boshlab: keyingilari ham sig'maydi
      refs.push(r); rest -= c;
    }
  }
  const tot = a => Math.round(a.reduce((t, r) => t + r.amount, 0) * 100) / 100, sum = tot(refs);
  return { refs, count: refs.length, sum, left: all.length - refs.length, leftSum: Math.round((tot(all) - sum) * 100) / 100 };
}
// Server ishlamagan paytdagi «Қ» blankalari (crit-3; server — kassa_day_close paper): soni, summasi va raqamlari birga; hammasi bo'sh — yo'q.
//   Natija: {paper: {count, sum, nos}} | {err} | {}. Sof funksiya (fin-kassa.test.mjs).
export function paperRead(cnt, sum, nos) {
  const c = String(cnt == null ? '' : cnt).replace(/[^\d]/g, ''), s = String(sum == null ? '' : sum).replace(/[^\d]/g, ''), n = String(nos == null ? '' : nos).trim();
  if (!c && !s && !n) return {};
  if (!(num(c) > 0) || !(num(s) > 0) || !n) return { err: '«Қ» blankalari: soni, summasi va raqamlari birga kiritiladi' };
  return { paper: { count: num(c), sum: num(s), nos: n.slice(0, 300) } };
}
// Yopish / smena topshirish natijasi — SERVER hisoblagan farq (oynadagi taxmin emas; takror javobda — kun farqi) va hisobga olinmagan
//   (allaqachon o'tib ketgan) navbat yozuvlari. Sof funksiya (fin-kassa.test.mjs).
export function countResultText(r) {
  r = r || {};
  const d = num(r.diff != null ? r.diff : (r.day && r.day.diff)), ign = (r.ignoredRefs || []).length;
  return (d === 0 ? 'farq yo‘q' : d < 0 ? `KAMOMAD ${som(-d)}` : `ORTIQCHA ${som(d)}`)
    + (ign ? ` · navbatdagi ${ign} ta yozuv allaqachon o‘tgan edi — ayirilmadi` : '');
}
// Kunning hali bog'lanmagan yozuvlari (kun javobidagi pendingOpen; nazorat ro'yxatidagi pendingOpen qatori; server — app.kassa_day_pending):
//   qurilma navbati yozuvining kech kirim orderi hali kelmagan va «Қ» blankalari — matn ('' — yo'q). Sof funksiya (fin-kassa.test.mjs).
export function pendingText(p) {
  if (!p) return '';
  const a = [];
  if (num(p.n) > 0) a.push(`qurilma navbatidagi ${num(p.n)} ta yozuvning (${som(p.sum)}) kirim orderi hali kelmagan`);
  if (num(p.paperCount) > 0) a.push(`«Қ» blankalari — ${num(p.paperCount)} ta, ${som(p.paperSum)}${p.paperNos ? ` (№: ${p.paperNos})` : ''}`);
  return a.join('; ');
}
const ST_LBL = { draft: 'Tasdiq kutilmoqda', approved: 'Tasdiqlangan — to‘lanadi', posted: 'O‘tkazilgan', void: 'Bekor qilingan', rejected: 'Rad etilgan', cancelled: 'Bekor qilingan so‘rov' };
const DAY_LBL = { open: 'Ochiq', closed: 'Yopilgan', verified: 'Tekshirilgan' };
const BLOCK_TXT = {
  prev_open: 'Oldingi kun yopilmagan — avval pulni sanab, kunni yoping.',
  day_closed: 'Bugungi kun yopilgan. Yangi hujjat uchun Direktor kunni qayta ochishi kerak.',
  not_started: 'Kassa hali ishga tushirilmagan: Direktor boshlang‘ich qoldiqni kiritishi kerak.',
  clock: 'Server sanasi kassa kunidan orqada — administratorga xabar bering.',
  // ishga-tushirish §9 (ui-5): to'xtatilgan kassa va qayta ishga tushirishni kutayotgan kassa (batafsil matn — draw() da, sana bilan)
  paused: 'Kassa to‘xtatilgan: kassa hujjatlari yozilmaydi. Qayta ishga tushirish — komissiya sanashi bilan (Direktor).',
  restart: 'Kassa qayta ishga tushirish kunini kutmoqda.',
  restart_recount: 'Qayta ishga tushirish sanashidan keyin kassa hujjatisiz naqd yozuv kiritilgan — komissiya pulni qayta sanab, qoldiq qayta kiritilmaguncha birinchi kassa kuni ochilmaydi (Direktor).',
  // state-6: smena topshirish qabul qilinmagan (batafsil — «Smena topshirish» kartasida)
  handover: 'Smena topshirilmoqda: qabul qiluvchi o‘z hisobidan «Qabul qildim» deguncha yoki topshirish bekor qilinguncha kassada hujjat yozilmaydi va kun yopilmaydi.',
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
const CHK = 'width:auto;flex:none;padding:0;margin:2px 0 0';   // belgilash katagi: umumiy «input{width:100%}» qoidasi uni cho'zib yubormasin
const lbl = (t, inner, extra) => `<label class="small" style="font-weight:700;display:flex;flex-direction:column;gap:6px;margin-top:8px${extra || ''}">${t}${inner}</label>`;
const fmtInput = el => { if (el) el.addEventListener('input', () => { const d = digits(el.value); el.value = d.replace(/\B(?=(\d{3})+(?!\d))/g, ' '); }); };
// KO-3 / statiyalar: davr ichidagi qayta ishga tushirish farqi (texnik dalolatnoma, kassa kitobidan tashqari) — boshi + kirim − chiqim + farq = oxiri
//   (sgnSom — ishorali summa, Z-hisobot bo'limida ta'riflangan)
const restartAdjTxt = v => num(v) ? ` · qayta ishga tushirish farqi (dalolatnoma) <b>${esc(sgnSom(v))}</b>` : '';

// «Kassa ishga tushadigan kun» o'zgarishi (ui-5; ishga-tushirish §9) — qanday amal va qanday tasdiq: sof funksiya (fin-kassa.test.mjs).
//   oldDay — hozirgi sana, newDay — kiritilgani (bo'sh — null), today — server sanasi, desk — asosiy kassa holati (kassa_state('main').desk):
//   started, pausedAt, restart {day, amount, prevClosing, delta, docNo}. Natija: {kind, text}:
//   'stop' — ishlagan kassada kelgan sanani bo'shatish / surish (kassa TO'XTATILADI) yoki tayyorlangan qayta ishga tushirishni bekor qilish;
//   'relaunch' — to'xtatilgan kassani qayta ishga tushirish; 'launch' — ishga tushirish / hali kelmagan sanani o'zgartirish;
//   'block' — avval komissiya sanashi kerak yoki sana qayta ishga tushirish kuniga teng emas (saqlanmaydi); 'none' — tasdiq kerak emas.
//   last — oxirgi YOPILGAN kassa kuni (kassa_state('main').lastDay; ochiq kun bo'lsa — berilmaydi): u qurilma navbatidagi hali
//   o'tkazilmagan (kech kirim orderi hali kelmagan — pendingOpen, state-2) yozuvlar yoki hali kiritilmagan «Қ» blankalari (crit-3) bilan
//   yopilgan bo'lsa kassa to'xtatilmaydi (g4b-v1; server ham rad etadi — kassa:rollback_pending).
export function goLiveConfirm(oldDay, newDay, today, desk, last) {
  oldDay = oldDay || null; newDay = newDay || null; desk = desk || {};
  if (oldDay === newDay) return { kind: 'none', text: '' };
  const rs = desk.restart || null, paused = !!desk.pausedAt;
  // set — ishga tushadigan kun allaqachon qayta ishga tushirish kunida (boshqa kun uchun avval uni bo'shatish kerak)
  const notDay = (d, set) => `Qayta ishga tushirish kuni — ${dmy(d)}: ishga tushadigan kun shu sana bo‘ladi. Boshqa sana kerak bo‘lsa — ${set ? 'avval ishga tushadigan kunni bo‘shating (kassa yana to‘xtatiladi), keyin ' : ''}«Qayta ishga tushirish» qoldig‘ini o‘sha sana bilan qayta kiriting.`;
  if (paused) {
    if (!newDay) return { kind: 'none', text: '' };
    if (!rs) return { kind: 'block', text: 'Kassa to‘xtatilgan: avval komissiya sanashi bilan «Qayta ishga tushirish» qoldig‘ini kiriting — ishga tushadigan kun shundan keyin qo‘yiladi.' };
    if (newDay !== rs.day) return { kind: 'block', text: notDay(rs.day, false) };
    return { kind: 'relaunch', text: `Kassa ${dmy(newDay)} dan QAYTA ishga tushsinmi?\n\nKun boshi — komissiya sanagan ${som(rs.amount)} (tizimdagi oxirgi qoldiq ${som(rs.prevClosing)}, farq ${sgnSom(rs.delta)}${rs.docNo ? ' — dalolatnoma D-' + rs.docNo : ''}).\nShu kundan naqd o‘quv to‘lovlari yana faqat kassa orderi va fiskal chek raqami bilan qabul qilinadi.` };
  }
  if (rs) {   // tayyorlangan, hali boshlanmagan qayta ishga tushirish (sana — rs.day)
    if (!newDay) return { kind: 'stop', text: `Qayta ishga tushirish (${dmy(rs.day)}) bekor qilinsinmi?\n\nKassa to‘xtatilgan holatda qoladi: naqd pul kassa hujjatisiz yoziladi, «Kassa»da hujjat yozilmaydi. Qayta ishga tushirish — yana shu oynada o‘sha kun (yoki yangi komissiya sanashi bilan boshqa kun).` };
    return { kind: 'block', text: notDay(rs.day, true) };
  }
  const reached = !!oldDay && !!today && String(oldDay) <= String(today);
  if (reached && (!newDay || newDay > oldDay) && desk.started) {
    // state-2, crit-3: kech kirim orderi hali kelmagan navbat yozuvlari va hali kiritilmagan «Қ» blankalari (kun javobidagi pendingOpen;
    //   eski server — pendingCount / pendingSum)
    const po = last && last.pendingOpen, pn = last ? num(po ? po.n : last.pendingCount) : 0, ps = last ? num(po ? po.sum : last.pendingSum) : 0;
    const qn = po ? num(po.paperCount) : 0, qs = po ? num(po.paperSum) : 0;
    if (pn > 0) return { kind: 'block', text: `Kassani to‘xtatib bo‘lmaydi: oxirgi kassa kuni (${dmy(last.day)}) qurilma navbatidagi hali o‘tkazilmagan ${pn} ta yozuv (${som(ps)})${qn ? ` va hali kiritilmagan «Қ» blankalari (${qn} ta, ${som(qs)})` : ''} bilan yopilgan — bu pul kassada bor, hisobda hali yo‘q. Avval navbat yuborilsin: kunni qayta oching, qurilmalar navbati o‘tgach kunni qayta sanab yoping (kun tekshirilgan bo‘lsa — navbat keyingi kassa kuniga «kech» tushadi, o‘sha kunni yoping), keyin kassani to‘xtating (ishga-tushirish §9).` };
    if (qn > 0) return { kind: 'block', text: `Kassani to‘xtatib bo‘lmaydi: oxirgi kassa kuni (${dmy(last.day)}) server ishlamagan paytdagi hali kiritilmagan «Қ» blankalari (${qn} ta, ${som(qs)}) bilan yopilgan — bu pul kassada bor, hisobda hali yo‘q. Avval «Қ» yozuvlarini kiriting (ular yangi kassa kuniga tushadi), o‘sha kunni sanab yoping, keyin kassani to‘xtating (ishga-tushirish §8, §9).` };
    return { kind: 'stop', text: `DIQQAT — KASSANI TO‘XTATISH (ishga-tushirish §9).\n\nKassa ${dmy(oldDay)} dan ishlayapti. Sanani ${newDay ? 'keyinga surish' : 'bo‘shatish'} kassani to‘xtatadi:\n`
      + '• naqd o‘quv to‘lovlari kirim orderisiz va fiskal chek raqamisiz yoziladi; naqd maosh, avans, xarajat va qaytarish — avvalgi (ordersiz) tartibda;\n'
      + '• «Kassa»da yangi hujjat yozilmaydi — kassa nazorati o‘chadi, kassa «Қ» blankalari va jurnali bilan ishlaydi (blankalar o‘z raqamlari bilan; tizim raqamlari qayta ishga tushganda davom etadi);\n'
      + '• qayta ishga tushirish — faqat yangi komissiya sanashi bilan: «Qayta ishga tushirish» (sanalgan summa va kun), keyin shu yerda o‘sha kun.\n'
      + (newDay ? `Kiritilgan ${dmy(newDay)} — faqat rejalashtirilgan kun sifatida yoziladi, sana maydoni bo‘sh qoladi.\n` : '')
      + 'Ochiq kassa kuni, qurilma navbatida qolgan («hali o‘tkazilmagan») yozuvlar bilan yopilgan oxirgi kun yoki pul berilmagan so‘rovlar bo‘lsa — tizim to‘xtatmaydi (avval qurilmalar navbati yuborilsin va kun yopilsin, so‘rovlarni bekor qiling yoki pulini bering).\n\nKassa to‘xtatilsinmi?' };
  }
  if (reached && (!newDay || newDay > oldDay)) {   // ishga tushgan deb belgilangan, kassa kuni hali ochilmagan — ishga tushirish bekor qilinadi / suriladi
    return { kind: 'stop', text: `DIQQAT — KASSANI ISHGA TUSHIRISH ${newDay ? 'SURILADI' : 'BEKOR QILINADI'}.\n\nKassa ${dmy(oldDay)} dan ishga tushgan deb belgilangan (kassa kuni hali ochilmagan). ${newDay ? dmy(newDay) + ' gacha' : 'Sana yana qo‘yilguncha'}:\n`
      + '• naqd o‘quv to‘lovlari kirim orderisiz va fiskal chek raqamisiz yoziladi; naqd maosh, avans, xarajat va qaytarish — avvalgi (ordersiz) tartibda; «Kassa»da hujjat yozilmaydi;\n'
      + '• bu oraliqdagi naqd harakat boshlang‘ich qoldiqqa ta’sir qiladi: ishga tushish arafasida komissiya kassani qayta sanaydi va «Boshlang‘ich qoldiq» yangi kun bilan qayta kiritiladi (ishga-tushirish §4).\n\n'
      + (newDay ? 'Ishga tushirish surilsinmi?' : 'Ishga tushirish bekor qilinsinmi?') };
  }
  if (!newDay) return { kind: 'none', text: '' };
  return { kind: 'launch', text: `Kassa ${dmy(newDay)} dan ishga tushsinmi?\n\nShu kundan naqd o‘quv to‘lovlari faqat kassa orderi va fiskal chek raqami bilan qabul qilinadi.` };
}

// Eskirgan qayta ishga tushirish sanashi (g4v-2): sanashdan keyin kiritilgan, sanasi qayta ishga tushirish kunidan oldingi kassa
//   hujjatisiz naqd yozuvlar (kassa_state('main').desk.restart.stale {n, in, out}; countedAt — sanash payti). Server birinchi qayta
//   ochilgan kunni ochmaydi (kassa:restart_recount) — sof funksiya (fin-kassa.test.mjs). today — server sanasi, paused — kassa to'xtatilgan.
const tkDate = ts => { try { return new Date(ts).toLocaleDateString('en-CA', { timeZone: 'Asia/Tashkent' }); } catch (_) { return ''; } };
export function restartStaleTxt(rs, director, today, paused) {
  rs = rs || {}; const st = rs.stale || {};
  const at = rs.countedAt ? ` (${dmy(tkDate(rs.countedAt))} ${hm(rs.countedAt)})` : '';
  const passed = !paused && !!today && !!rs.day && String(today) > String(rs.day);
  return `Qayta ishga tushirish sanashidan${at} keyin kassa hujjatisiz ${num(st.n)} ta naqd yozuv kiritilgan (kirim ${som(st.in)}, chiqim ${som(st.out)}) — ular komissiya sanagan summaga kirmagan. Birinchi kassa kuni ochilmaydi: `
    + (director ? 'komissiya pulni qayta sanaydi, «Qayta ishga tushirish» qoldig‘ini qayta kiriting'
        + (passed ? ' (qayta ishga tushirish kuni o‘tgan — avval «⚙ Sozlamalar»da ishga tushadigan kunni bo‘shating, keyin yangi kun bilan).' : ' (avvalgi dalolatnoma bekor bo‘ladi).')
      : 'Direktor komissiya bilan pulni qayta sanab, qoldiqni qayta kiritadi.');
}

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
  loadControl();                                 // nazorat ro'yxati — alohida so'rov, sahifani kutdirmaydi
}
// Nazorat ro'yxati (RP-06): 2-ro'yxat (Moliya menejeri, buxgalter) va Direktor uchun. Ketma-ket ikki so'rovdan faqat OXIRGISINING
//   javobi ko'rsatiladi (oldingisi kech kelsa — tashlab yuboriladi), aks holda eskirgan holat yangi bo'lib ko'rinishi mumkin.
let CTL_SEQ = 0;
async function loadControl() {
  const m = me(); if (!$('#ks-ctl') || !(m.list2 || m.director)) return;
  const desk = ST.desk, seq = ++CTL_SEQ;
  let c;
  try { c = await call('kassa_checks', { p_desk: desk }); }
  catch (e) {
    if (seq !== CTL_SEQ) return;
    const b = $('#ks-ctl'); if (b) b.innerHTML = `<div class="card" style="padding:14px 18px;margin-bottom:14px"><b>Nazorat ro‘yxati</b><div class="small muted" style="margin-top:6px">O‘qib bo‘lmadi: ${esc(errText(e))}</div></div>`;
    return;
  }
  if (seq !== CTL_SEQ || desk !== ST.desk) return;
  ST.checks = Object.assign(c || {}, { _desk: desk });
  const b2 = $('#ks-ctl'); if (b2) { b2.innerHTML = controlHtml(ST.checks); bindControl(b2); }
}
// Nazorat ro'yxatidagi «✓ Tasdiqlash» (kontragent turi, sec-3): ko'rilgan tur va nom bilan — shu orada o'zgargan bo'lsa server rad etadi.
function bindControl(el) {
  if (!el) return;
  el.querySelectorAll('[data-cpok]').forEach(b => { b.onclick = async ev => {
    ev.preventDefault();
    const kind = b.dataset.cpkind, name = b.dataset.cpname;
    if (!confirm(`«${name}» turi — «${CP_KIND[kind] || kind}» — tasdiqlansinmi?\n\nTasdiqlangach u yuridik shaxs hisoblanmaydi: kassadan naqd to‘lovga Direktor tasdig‘i talab qilinmaydi. Korxona (MChJ, AJ) bo‘lsa — tasdiqlamang, turini o‘zgartiring.`)) return;
    b.disabled = true;
    try { await call('fin_counterparty_confirm', { p_id: b.dataset.cpok, p_kind: kind, p_name: name }); C.toast('Kontragent turi tasdiqlandi ✓'); await loadRefs(true); loadControl(); }
    catch (e) { b.disabled = false; C.toast(errText(e), true); }
  }; });
}
function draw() {
  const s = ST.ov.state, m = me(), od = s.openDay, ld = s.lastDay, started = s.desk && s.desk.started;
  const ready = s.desk && s.desk.startDay && s.desk.openingAmount != null;
  // ishga-tushirish §9 (ui-5): to'xtatilgan kassa va tayyorlangan (hali boshlanmagan) qayta ishga tushirish
  const paused = !!(s.desk && s.desk.pausedAt), rs = (s.desk && s.desk.restart) || null;
  // ---- amallar
  const acts = [];
  const desks = (ST.refs.desks || []);
  if (desks.length > 1 && (m.director || m.list2)) acts.push(`<select id="ks-desk" class="search-inp" style="max-width:170px" title="Kassa">${desks.map(d => `<option value="${esc(d.id)}"${d.id === ST.desk ? ' selected' : ''}>${esc(d.name)}</option>`).join('')}</select>`);
  if (ready && (m.operator || m.director)) acts.push(`<button class="btn gold" id="ks-in">+ Kirim</button>`);
  if (ready && (m.operator || m.director || C.SESSION.role === 'finance_mgr')) acts.push(`<button class="btn ghost2" id="ks-out">+ Chiqim so‘rovi</button>`);
  if (ready && s.kassaGoLive && (m.list2 || m.director)) acts.push(`<button class="btn ghost2" id="ks-adv" title="Hisobdor shaxsning avans hisoboti — qog‘oz hisobot va cheklar bo‘yicha">Avans hisoboti</button>`);
  // state-6: smena topshirish qabul qilinmagan bo'lsa — kunni yopish va yangi topshirish yo'q (kartadagi «Qabul qildim» / «Bekor qilish»)
  const ho = s.handover || null;
  if (od && !ho && (m.operator || m.director || C.SESSION.role === 'finance_mgr')) acts.push(`<button class="btn ghost2" id="ks-close">Kunni yopish</button>`);
  if (od && !ho && (m.operator || m.director)) acts.push(`<button class="btn ghost2" id="ks-hand" title="Smena topshirish-qabul: pul birga sanaladi, qabul qiluvchi o‘z hisobidan qabul qiladi (kun ochiq qoladi)">Smena topshirish</button>`);
  if (m.director || m.list2) acts.push(`<button class="btn ghost2" id="ks-period" title="Davr surati (yil / oy yakuni) va yopilgan davr qulfi">Davr</button>`);
  if (started && (m.director || m.list2 || m.operator)) acts.push(`<button class="btn ghost2" id="ks-ko3" title="KO-3: kirim va chiqim orderlari jurnali — chop etish va Excel">KO-3</button>`);
  if (started && (m.director || m.list2 || m.operator)) acts.push(`<button class="btn ghost2" id="ks-mx" title="Oylik statiya matritsasi (RP-08) — chop etish; buxgalter uchun oylik kassa to‘plami (Excel)">Statiyalar</button>`);
  if (started && (m.director || m.list2)) acts.push(`<button class="btn ghost2" id="ks-kpi" title="Haftalik ko‘rsatkichlar (RP-22): o‘z vaqtida yopilgan kunlar, tekshirilmagan, farqlar, EX-49 ulushi, muddati o‘tgan avanslar">KPI</button>`);
  // (tayyorlangan, hali boshlanmagan qayta ishga tushirishda ham — qayta sanash uchun, g4v-2)
  if (ready && (paused || rs) && m.director) acts.push(`<button class="btn gold" id="ks-restart" title="Komissiya sanashi bo‘yicha qayta ishga tushirish qoldig‘i (ishga-tushirish §9)">Qayta ishga tushirish</button>`);
  if (m.director) acts.push(`<button class="btn ghost2" id="ks-set" title="Kassa sozlamalari">⚙ Sozlamalar</button>`);
  $('#ks-actions').innerHTML = acts.join('');

  // ---- ogohlantirishlar
  const warn = [];
  if (s.version != null && Number(s.version) !== SERVER_VER) warn.push(['#B42318', '#FDECEC', Number(s.version) > SERVER_VER
    ? 'Tizim yangilangan, bu sahifa esa eski: sahifani yangilang (Ctrl+Shift+R; telefonda — sahifani yopib qayta oching).'
    : 'Serverdagi kassa moduli bu sahifadan eski relizda — administratorga xabar bering (o‘rnatish to‘liq bajarilmagan).']);
  if (s.blockReason && !(s.blockReason === 'restart_recount' && rs && rs.stale)) warn.push(['#B42318', '#FDECEC', (s.blockReason === 'day_closed' && ld && ld.status === 'verified')   // (restart_recount — batafsil pastda)
    ? 'Bugungi kun yopilgan va tekshirilgan — bugun yangi hujjat yozilmaydi (tekshirilgan kun qayta ochilmaydi).'
    : s.blockReason === 'paused'
      ? `Kassa to‘xtatilgan (${dmy(s.desk.pausedDay)} dan): kassa hujjatlari yozilmaydi, naqd o‘quv to‘lovi kirim orderisiz yozilmoqda. Qayta ishga tushirish — yangi komissiya sanashi bilan${m.director ? ': «Qayta ishga tushirish», keyin «⚙ Sozlamalar»da ishga tushadigan kun' : ' (Direktor)'} (ishga-tushirish §9).`
      : (s.blockReason === 'restart' && rs ? `Kassa ${dmy(rs.day)} dan qayta ishga tushadi — o‘shangacha hujjat yozilmaydi.` : (BLOCK_TXT[s.blockReason] || s.blockReason))]);
  if (rs) warn.push(['#175CD3', '#E8F1FD', `Qayta ishga tushirish tayyorlangan: ${dmy(rs.day)} dan, kun boshi ${som(rs.amount)} (tizimdagi oxirgi qoldiq ${som(rs.prevClosing)}; farq ${sgnSom(rs.delta)}${rs.docNo ? ' — dalolatnoma D-' + rs.docNo : ''}).`
    + (paused ? (m.director ? ' Endi «⚙ Sozlamalar»da ishga tushadigan kunni shu sanaga qo‘ying.' : ' Ishga tushadigan kunni Direktor belgilaydi.') : '')
    + ' Sanashdan keyin kassa hujjatisiz naqd yozuv kiritilsa — u sanashga kirmaydi: qayta sanash kerak bo‘ladi (aks holda birinchi kassa kuni ochilmaydi).']);
  // g4v-2: sanashdan keyin kiritilgan, sanasi qayta ishga tushirish kunidan oldingi kassa hujjatisiz naqd yozuvlar — server birinchi kunni ochmaydi
  if (rs && rs.stale && num(rs.stale.n) > 0) warn.push(['#B42318', '#FDECEC', restartStaleTxt(rs, m.director, s.today, paused)]);
  if (s.desk && s.desk.isTest) warn.push(['#175CD3', '#E8F1FD', 'Bu — SINOV kassasi: hujjatlari va raqamlari asosiy kassadan alohida, hisobotlarga kirmaydi.']);
  if (!s.kassaGoLive && !paused && !rs) warn.push(['#B54708', '#FEF3E2', 'Kassa hali «ishga tushirilgan» deb belgilanmagan: naqd o‘quv to‘lovlari kassa orderisiz yozilmoqda' + (m.director ? ' («⚙ Sozlamalar» → ishga tushirish sanasi).' : '.')]);
  if (num(s.pending.toApprove) > 0) warn.push(['#175CD3', '#E8F1FD', `Sizning tasdig‘ingizni kutayotgan so‘rovlar: ${s.pending.toApprove} ta.`]);
  if (num(s.pending.toPay) > 0 && (m.operator || m.director)) warn.push(['#175CD3', '#E8F1FD', `Tasdiqlangan, pul berilishi / qabul qilinishi kerak: ${s.pending.toPay} ta (${som(s.pending.toPaySum)}).`]);
  if (num(s.pending.refundsLate) > 0) warn.push(['#B42318', '#FDECEC', `Direktor tasdiqlagan qaytarish 1 kundan ortiq berilmay turibdi: ${s.pending.refundsLate} ta.`]);
  if (num(s.unverifiedDays) > 0 && (m.list2 || m.director)) warn.push(['#B54708', '#FEF3E2', `Tekshirilmagan (yopilgan) kunlar: ${s.unverifiedDays} ta.`]);
  if (num(s.undecidedShortages) > 0) warn.push(['#B42318', '#FDECEC', `Qarori kutilayotgan kamomad: ${s.undecidedShortages} ta${m.director ? ' — pastda qaror qabul qiling.' : ' (Direktor qarori).'}`]);
  // eslatma (F1.24): avans hisoboti muddati (3 ish kuni) o'tgan hisobdorlar — ismlar nazorat ro'yxatida
  if (s.accOverdue && num(s.accOverdue.n) > 0 && (m.list2 || m.director)) warn.push(['#B54708', '#FEF3E2', `Avans hisoboti muddati o‘tgan hisobdorlar: ${num(s.accOverdue.n)} ta (${som(s.accOverdue.sum)}) — «Avans hisoboti» yoki qaytim; ismlar — nazorat ro‘yxatida.`]);
  if (s.lockedThrough && (m.director || m.list2)) warn.push(['#475467', '#F2F4F7', `Davr ${dmy(s.lockedThrough)} gacha yopilgan: shu sanagacha to‘lov, xarajat, maosh va avans yozuvlari kiritilmaydi va o‘zgartirilmaydi.`]);
  if (s.limit && s.limit.exceeded) warn.push(['#B54708', '#FEF3E2', `Kassa qoldig‘i limitdan (${som(s.limit.cashLimit)}) oshgan — ortiqchasini bankka topshiring.`]);
  const warnHtml = warn.map(w => `<div class="small" style="margin-bottom:8px;color:${w[0]};background:${w[1]};border-radius:10px;padding:10px 12px;font-weight:600">${esc(w[2])}</div>`).join('');

  // ---- kun kartasi
  let top;
  if (!ready) {
    top = `<div class="card"><div class="empty">Kassa hali ishga tushirilmagan.<br><span class="small muted">Birinchi kassa kunidan oldin komissiya kassadagi pulni sanaydi va Direktor shu summani boshlang‘ich qoldiq sifatida kiritadi.</span>
      ${m.director ? '<div style="margin-top:12px"><button class="btn gold" id="ks-opening">Boshlang‘ich qoldiqni kiritish</button></div>' : ''}</div></div>`;
  } else {
    const d = od || ld;
    const opening = od ? od.opening : (rs ? rs.amount : (ld ? ld.closing : s.desk.openingAmount));
    const rec = od ? od.receiptsLive : 0, pay = od ? od.payoutsLive : 0;
    top = `<div class="acc-kpis">
      <div class="acc-kpi teal"><div><div class="k-l">${od ? 'Kun boshi' : (rs ? 'Qayta ishga tushirish qoldig‘i' : 'Oxirgi qoldiq')}</div><div class="k-v">${esc(som(opening))}</div><div class="k-d">${od ? esc(dmy(od.day)) + ' · ' + DAY_LBL.open : (rs ? esc(dmy(rs.day)) + ' dan · komissiya sanashi' : (ld ? esc(dmy(ld.day)) + ' · ' + (DAY_LBL[ld.status] || '') : 'boshlang‘ich qoldiq'))}</div></div></div>
      <div class="acc-kpi pos"><div><div class="k-l">Kirim</div><div class="k-v">${esc(som(rec))}</div><div class="k-d">${od ? 'bugungi ochiq kun' : 'ochiq kun yo‘q'}</div></div></div>
      <div class="acc-kpi neg"><div><div class="k-l">Chiqim</div><div class="k-v">${esc(som(pay))}</div><div class="k-d">${od ? esc(String(od.docs)) + ' ta hujjat' + (num(od.voids) ? ', ' + od.voids + ' tasi bekor' : '') : '—'}</div></div></div>
      <div class="acc-kpi gold"><div><div class="k-l">Kassadagi qoldiq</div><div class="k-v">${esc(som(s.balance))}</div><div class="k-d">${od && od.cashierUid ? 'kassir: ' + esc(od.cashierName || nameOf(od.cashierUid)) : (!started && m.director ? '<a href="#" id="ks-opening">boshlang‘ich qoldiqni o‘zgartirish</a>' : '&nbsp;')}</div></div></div>
    </div>`;
  }

  // ---- bugungi hujjatlar
  const docs = ST.ov.docs || [];
  const docRows = docs.map(d => {
    // bekor qilinadi: qo'lda kiritilganlar, naqd o'quv to'lovi va naqd maosh orderi (bog'langan yozuv ham teskari bo'ladi); qaytarish — yo'q;
    //   kassir — smena topshirishda sanalgan o'z orderini ham emas (g6v-2)
    const canVoid = canVoidDoc(d, m, od);
    const isIn = d.form === 'KO1';
    return `<tr${d.status === 'void' ? ' style="opacity:.55"' : ''}>
      <td data-label="№"><b>${isIn ? 'K' : 'Ch'}-${esc(String(d.no))}</b><div class="small muted">${esc(hm(d.postedAt))}</div></td>
      <td data-label="Operatsiya">${esc(opName(d.op))}${d.late ? ' ' + chip('kech', '#B54708', '#FEF3E2') : ''}${d.fiscalExempt ? ' ' + chip('fiskal cheksiz', '#B42318', '#FDECEC') : ''}<div class="small muted">${esc((d.lines || []).filter(l => l.cash).map(l => (isIn ? l.credit : l.debit) + (l.articleId ? ' · ' + l.articleId : '')).filter((v, i, a) => a.indexOf(v) === i).join(', '))}</div></td>
      <td data-label="${isIn ? 'Kimdan' : 'Kimga'}">${esc(d.partyName || '—')}<div class="small muted">${esc(d.basis || '')}</div></td>
      <td data-label="Kirim" style="text-align:right;white-space:nowrap">${isIn ? (d.status === 'void' ? '<s>' + esc(som(d.amount)) + '</s>' : '<b>' + esc(som(d.amount)) + '</b>') : ''}</td>
      <td data-label="Chiqim" style="text-align:right;white-space:nowrap">${!isIn ? (d.status === 'void' ? '<s>' + esc(som(d.amount)) + '</s>' : '<b>' + esc(som(d.amount)) + '</b>') : ''}</td>
      <td data-label="Holat">${stChip(d.status)}${d.status === 'void' && d.voidReason ? `<div class="small muted">${esc(d.voidReason)}</div>` : ''}<div class="small muted">${d.isSystem ? 'tizim' : esc(d.postedByName || nameOf(d.postedBy))}</div></td>
      <td data-label="" style="white-space:nowrap"><button class="btn sm" data-print="${esc(d.id)}" title="Orderni chop etish">🖨</button>${canVoid ? ` <button class="btn sm danger" data-void="${esc(d.id)}">Bekor</button>` : ''}</td></tr>`;
  }).join('');
  const docsHtml = ready ? `<div class="card" style="padding:14px 18px;margin-bottom:14px"><div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:8px"><b>${od ? 'Ochiq kun hujjatlari — ' + esc(dmy(od.day)) : 'Ochiq kun yo‘q'}</b>${od ? `<span style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn sm" data-report="${esc(od.day)}" title="Kunlik hisobot: kimdan / kimga qancha">🖨 Kunlik hisobot</button><button class="btn sm" data-book="${esc(od.day)}">🖨 Kassa kitobi varag‘i (qoralama)</button></span>` : ''}</div>
    ${docs.length ? `<div class="tablewrap"><table><thead><tr><th>№</th><th>Operatsiya</th><th>Kimdan / kimga</th><th style="text-align:right">Kirim</th><th style="text-align:right">Chiqim</th><th>Holat</th><th></th></tr></thead><tbody>${docRows}</tbody></table></div>`
      : `<div class="empty">${od ? 'Bu kunda hali hujjat yo‘q.' : 'Birinchi hujjat bilan yangi kun ochiladi (kun boshi = oxirgi qoldiq).'}</div>`}</div>` : '';

  // ---- so'rovlar
  const reqs = ST.ov.requests || [];
  const reqRows = reqs.map(d => {
    const mine = d.requestedBy === m.uid;
    const canAppr = d.status === 'draft' && (canApproveList2(d, m) || (m.director && d.needsDirector && !d.dirApprovedBy));
    const canRej = d.status === 'draft' && (m.list2 || m.director);
    const canPay = canPayDoc(d, m);   // tasdiqlangan qaytarish ham shu yerdan beriladi; o'zi tasdiqlagan so'rov puli — yo'q (sec-5)
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
  // sec-2: kassa egasi (kun kassiri) va pulni sanagan xodim alohida (ismlar — sanash paytidagi); smenada — qabul qiluvchi ham
  const shWho = x => { const nm = u => (u && x.names && x.names[u]) || nameOf(u);
    return esc(x.cashierUid ? nm(x.cashierUid) : 'aniqlanmagan') + (x.countedBy && x.countedBy !== x.cashierUid ? `<div class="small muted">sanadi: ${esc(nm(x.countedBy))} (kassir o‘rniga)</div>` : '')
      + (x.kind === 'handover' ? `<div class="small muted">smena topshirishda${x.toUid ? ' → ' + esc(nm(x.toUid)) : ''}</div>` : ''); };
  const shHtml = sh.length ? `<div class="card" style="padding:14px 18px;margin-bottom:14px"><b>Qarori kutilayotgan kamomadlar</b>
    <div class="tablewrap"><table><thead><tr><th>Kun</th><th>Hujjat</th><th>Kassir</th><th style="text-align:right">Summa</th><th></th></tr></thead><tbody>${sh.map(x => `<tr>
      <td data-label="Kun">${esc(dmy(x.day))}</td><td data-label="Hujjat">Ch-${esc(String(x.no))}</td><td data-label="Kassir">${shWho(x)}</td>
      <td data-label="Summa" style="text-align:right"><b>${esc(som(x.amount))}</b></td>
      <td data-label="">${m.director ? `<button class="btn sm gold" data-decide="${esc(x.id)}">Qaror</button>` : '<span class="small muted">Direktor qarori</span>'}</td></tr>`).join('')}</tbody></table></div></div>` : '';

  // ---- kunlar
  const days = ST.ov.days || [];
  const lastId = days.length ? days[0].id : null;
  const zOp = !(s.desk && s.desk.isTest) && (m.operator || m.director || C.SESSION.role === 'finance_mgr');   // Z-hisobotni kiritadi / tuzatadi
  const dayRows = days.map(d => {
    const closed = d.status !== 'open', zt = closed ? zText(d.z) : '', zBad = closed && d.z && d.z.applies && d.z.ok === false;
    return `<tr>
      <td data-label="Kun"><b>${esc(dmy(d.day))}</b>${num(d.reopenCount) ? `<div class="small muted">qayta ochilgan: ${esc(String(d.reopenCount))}</div>` : ''}</td>
      <td data-label="Kun boshi" style="text-align:right">${esc(som(d.opening))}</td>
      <td data-label="Kirim" style="text-align:right">${esc(som(closed ? d.receipts : d.receiptsLive))}</td>
      <td data-label="Chiqim" style="text-align:right">${esc(som(closed ? d.payouts : d.payoutsLive))}</td>
      <td data-label="Kun oxiri" style="text-align:right"><b>${esc(som(closed ? d.closing : d.balance))}</b></td>
      <td data-label="Farq" style="text-align:right">${closed ? (num(d.diff) === 0 ? '—' : `<span style="color:${num(d.diff) < 0 ? '#B42318' : '#B54708'};font-weight:700">${num(d.diff) > 0 ? '+' : ''}${esc(som(d.diff))}</span>`) : ''}${(d.handoverDiffs || []).filter(x => num(x)).length ? `<div class="small" style="color:#B54708">smenada ${esc((d.handoverDiffs || []).filter(x => num(x)).map(sgnS).join(', '))}</div>` : ''}</td>
      <td data-label="Holat">${dayChip(d.status)}<div class="small muted">${closed ? 'yopdi: ' + esc(d.closedByName || nameOf(d.closedBy)) : 'kassir: ' + esc(d.cashierName || nameOf(d.cashierUid))}${d.status === 'verified' ? '<br>tekshirdi: ' + esc(d.verifiedByName || nameOf(d.verifiedBy)) : ''}</div>${closed && pendingText(d.pendingOpen) ? `<div class="small" data-pend="${esc(d.day)}" style="color:#B54708">hali o‘tkazilmagan: ${esc(pendingText(d.pendingOpen))}</div>` : ''}${zt ? `<div class="small" data-zst="${esc(d.day)}" style="${zBad ? (d.status === 'closed' ? 'color:#B42318;font-weight:700' : 'color:#B54708') : 'color:var(--muted)'}">Z: ${esc(zt)}</div>` : ''}</td>
      <td data-label="" style="white-space:nowrap"><button class="btn sm" data-view="${esc(d.day)}" title="Kun hujjatlari, sanashlar, jurnal">Ko‘rish</button> <button class="btn sm" data-book="${esc(d.day)}" title="Kassa kitobi varag‘i (KO-4)">🖨 KO-4</button>${d.status === 'closed' && zOp ? ` <button class="btn sm" data-zrep="${esc(d.day)}" title="Onlayn kassa Z-hisobotini kiritish / tuzatish">Z</button>` : ''}${d.status === 'closed' && (m.list2 || m.director) ? ` <button class="btn sm gold" data-verify="${esc(d.day)}">Tekshirish</button>` : ''}${d.status === 'closed' && m.director && d.id === lastId ? ` <button class="btn sm danger" data-reopen="${esc(d.day)}">Qayta ochish</button>` : ''}</td></tr>`;
  }).join('');
  const daysHtml = days.length ? `<div class="card" style="padding:14px 18px"><b>Kassa kunlari</b><div class="small muted" style="margin:2px 0 8px">Kun oxiri = kun boshi + kirim − chiqim. Kun faqat pul sanalgach yopiladi; farq shu kunning hujjati bo‘lib yoziladi.</div>
    <div class="tablewrap"><table><thead><tr><th>Kun</th><th style="text-align:right">Kun boshi</th><th style="text-align:right">Kirim</th><th style="text-align:right">Chiqim</th><th style="text-align:right">Kun oxiri</th><th style="text-align:right">Farq</th><th>Holat</th><th></th></tr></thead><tbody>${dayRows}</tbody></table></div></div>` : '';

  const ctlHtml = (m.list2 || m.director) && ready ? `<div id="ks-ctl">${ST.checks && ST.checks._desk === ST.desk ? controlHtml(ST.checks, true) : ''}</div>` : '';

  // ---- kutilayotgan smena topshirish (state-6): qabul qiluvchiga «Smenani qabul qilish», topshiruvchi va Direktorga «Bekor qilish»
  let hoHtml = '';
  if (ho) {
    const hr = handoverRole(ho, m), hn = u => (u && ho.names && ho.names[u]) || nameOf(u), d0 = num(ho.diff);
    const sum = `sanalgan <b>${esc(som(ho.counted))}</b> (hisobda ${esc(som(ho.expected))}${num(ho.pendingSum) ? ', hali o‘tkazilmagan ' + esc(som(ho.pendingSum)) + ((ho.pendingRefs || []).length ? ` — ${(ho.pendingRefs || []).length} ta navbat yozuvi` : '') : ''}) · `
      + (d0 === 0 ? 'farq yo‘q' : `<b style="color:${d0 < 0 ? '#B42318' : '#B54708'}">${d0 < 0 ? 'KAMOMAD ' + esc(som(-d0)) : 'ORTIQCHA ' + esc(som(d0))}</b>`);
    const who = `${esc(ho.fromUid ? hn(ho.fromUid) : '—')} → <b>${esc(hn(ho.toUid))}</b>${ho.byUid && ho.byUid !== ho.fromUid ? ` · sanadi: ${esc(hn(ho.byUid))} (komissiya bilan)` : ''} · ${esc(hm(ho.createdAt))}`;
    hoHtml = `<div class="card" id="ks-ho" style="padding:14px 18px;margin-bottom:14px;border-color:#F5C26B">
      <b>${hr.receiver ? 'Smenani qabul qilish' : 'Smena topshirish — qabul kutilmoqda'}</b>
      <div class="small" style="margin-top:6px">${who}</div><div class="small" style="margin-top:4px">${sum}</div>
      <div class="small muted" style="margin-top:6px">${hr.receiver ? 'Pulni birga sanang. «Qabul qildim» — kassa siz zimmangizda; farq bo‘lsa, shu kun hujjati topshiruvchi (kassa egasi) nomidan yoziladi. Summa mos kelmasa — «Rad etish» (sababi bilan).'
        : 'Qabul qiluvchi o‘z hisobidan «Qabul qildim» deguncha yoki topshirish bekor qilinguncha kassada hujjat yozilmaydi va kun yopilmaydi.'}</div>
      ${hr.canAccept || hr.canCancel ? `<div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:10px">${hr.canAccept ? `<button class="btn sm gold" data-hoacc="${esc(ho.id)}">Qabul qildim</button>` : ''}${hr.canCancel ? `<button class="btn sm danger" data-horej="${esc(ho.id)}">${hr.receiver && !hr.giver ? 'Rad etish' : 'Bekor qilish'}</button>` : ''}</div>` : ''}</div>`;
  }

  // ---- naqdsiz dalolatnomalar: kassa kitobiga kirmaydi (boshlang'ich qoldiq, kamomad bo'yicha qaror, o'zaro hisob)
  const actDocs = ST.ov.acts || [];
  const actRows = actDocs.map(d => { const v = d.status === 'void';
    const canVoid = m.director && d.op === 'nc_offset' && d.status === 'posted' && String(d.businessDay) === String(s.today);   // o'zaro hisob — faqat shu kunda, Direktor
    const canVoidAdv = (m.list2 || m.director) && d.op === 'nc_adv_report' && d.status === 'posted' && String(d.businessDay) === String(s.today);   // avans hisoboti — shu kunda
    return `<tr${v ? ' style="opacity:.55"' : ''}>
      <td data-label="№"><b>${esc(({ OFS: 'O‘H', ADV: 'A' })[d.series] || 'D')}-${esc(String(d.no))}</b><div class="small muted">${esc(dmy(d.businessDay))}</div></td>
      <td data-label="Tur">${esc(opName(d.op))}</td>
      <td data-label="Tomon / asos"><div>${esc(d.partyName || '—')}<div class="small muted">${esc(d.basis || '')}</div></div></td>
      <td data-label="Summa" style="text-align:right;white-space:nowrap">${v ? '<s>' + esc(som(d.amount)) + '</s>' : '<b>' + esc(som(d.amount)) + '</b>'}</td>
      <td data-label="Holat">${v ? stChip('void') + (d.voidReason ? `<div class="small muted">${esc(d.voidReason)}</div>` : '') : `<span class="small muted">${esc(d.postedByName || nameOf(d.postedBy))}</span>`}</td>
      <td data-label="" style="white-space:nowrap"><button class="btn sm" data-print="${esc(d.id)}" title="Dalolatnomani chop etish">🖨</button>${canVoid ? ` <button class="btn sm danger" data-ofsvoid="${esc(d.id)}">Bekor</button>` : ''}${canVoidAdv ? ` <button class="btn sm danger" data-advvoid="${esc(d.id)}">Bekor</button>` : ''}</td></tr>`; }).join('');
  const actsHtml = actDocs.length ? `<div class="card" style="padding:14px 18px;margin-top:14px" id="ks-acts"><b>Naqdsiz dalolatnomalar</b><div class="small muted" style="margin:2px 0 8px">Kassa kitobiga kirmaydi: boshlang‘ich qoldiq, kamomad bo‘yicha qaror, o‘zaro hisob (ish haqidan o‘quv to‘lovi — «Maosh berish» oynasida, faqat Direktor), avans hisoboti. Oxirgi 3 oy.</div>
    <div class="tablewrap"><table><thead><tr><th>№</th><th>Tur</th><th>Tomon / asos</th><th style="text-align:right">Summa</th><th>Holat</th><th></th></tr></thead><tbody>${actRows}</tbody></table></div></div>` : '';
  $('#ks-body').innerHTML = warnHtml + hoHtml + top + docsHtml + reqHtml + shHtml + ctlHtml + daysHtml + actsHtml;
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
  on('#ks-period', openPeriodForm);
  on('#ks-ko3', openJournal);
  on('#ks-mx', openMatrix);
  on('#ks-kpi', openKpi);
  on('#ks-adv', openAdvForm);
  on('#ks-opening', ev => { if (ev && ev.preventDefault) ev.preventDefault(); openOpeningForm(); });
  on('#ks-restart', openRestartForm);
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
  each('data-report', day => printReport(day));
  each('data-view', day => openDayView(day));
  each('data-verify', day => openVerifyForm(day));
  each('data-zrep', day => openZForm(day));
  each('data-reopen', day => ask('Kunni qayta ochish — ' + dmy(day), 'Sababi (kamida 5 belgi). Sanash farqi hujjati bekor bo‘ladi, kun qayta sanab yopiladi.', 5, r => act('kassa_day_reopen', { p_desk: ST.desk, p_day: day, p_reason: r }, 'Kun qayta ochildi')));
  each('data-decide', id => openDecideForm(id));
  each('data-hoacc', id => acceptHandover(id));
  each('data-horej', id => { const h = ST.ov.state.handover || {}, rej = h.toUid === me().uid && h.byUid !== me().uid && h.fromUid !== me().uid;
    ask(rej ? 'Smenani qabul qilmaslik (rad etish)' : 'Smena topshirishni bekor qilish', rej ? 'Sababi (masalan: sanalgan summa mos emas). Topshiruvchi pulni qayta sanab, yangidan topshiradi.' : 'Sababi. Kassa egasi o‘zgarmaydi, hujjat yozilmaydi.', 3,
      r => act('kassa_handover_cancel', { p_id: id, p_reason: r }, rej ? 'Smena qabul qilinmadi (rad etildi)' : 'Smena topshirish bekor qilindi')); });
  each('data-ofsvoid', id => ask('O‘zaro hisobni bekor qilish', 'Sababi (kamida 5 belgi). O‘quv to‘lovi teskari qilinadi, maosh to‘lovi olib tashlanadi; dalolatnoma raqami saqlanadi. Faqat rasmiylashtirilgan kunning o‘zida.', 5,
    r => act('kassa_offset_void', { p_id: id, p_reason: r }, 'O‘zaro hisob bekor qilindi')));
  each('data-advvoid', id => ask('Avans hisobotini bekor qilish', 'Sababi (kamida 5 belgi). Xarajatlar «Buxgalteriya»dan olib tashlanadi, hisobdordagi qoldiq tiklanadi; dalolatnoma raqami saqlanadi. Faqat kiritilgan kunning o‘zida.', 5,
    r => act('kassa_adv_report_void', { p_id: id, p_reason: r }, 'Avans hisoboti bekor qilindi')));
  bindControl($('#ks-ctl'));   // nazorat ro'yxati (oldingi yuklash ma'lumoti bilan chizilgan bo'lsa)
}
// Server amali: bajaradi, xabar beradi, sahifani yangilaydi. Xato — serverning o'zbekcha matni bilan.
//   ok = false — server rad etdi, lekin holatni saqlab qoldi (kassa_doc_pay: so'rov Direktor tasdig'iga qaytarildi, sec-3): matn — message.
//   okMsg — matn yoki javobdan matn tuzadigan funksiya (masalan, server hisoblagan farq); onErr(e) — true qaytarsa, xatoni o'zi hal qilgan.
async function act(fn, args, okMsg, after, onErr) {
  try {
    const r = await call(fn, args);
    if (r && r.ok === false) { C.toast(String(r.message || 'Rad etildi'), true); C.closeModal(); await reload().catch(() => {}); if (C.onChange) C.onChange(); return null; }
    C.toast((typeof okMsg === 'function' ? okMsg(r) : okMsg) + (r && r.dup ? ' (avval bajarilgan)' : '') + ' ✓'); C.closeModal(); await reload(); if (after) after(r); if (C.onChange) C.onChange(); return r;
  }
  catch (e) { if (onErr && await onErr(e)) return null; C.toast(errText(e), true); await reload().catch(() => {}); return null; }
}
// state-2: oyna ochilgandan keyin kassa qoldig'i o'zgargan (server — kassa:stale; masalan, qurilma navbati shu orada o'tgan): xabar,
//   oyna yangi qoldiq va navbat bilan qayta ochiladi — pul qayta sanaladi.
const staleReopen = open => async e => {
  if (String((e && e.hint) || '') !== 'kassa:stale') return false;
  C.toast(errText(e), true); C.closeModal(); await reload().catch(() => {}); open(); return true;
};
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

// ---------------------------------------------------------------- avans hisoboti (hisobdor shaxs, naqdsiz dalolatnoma)
//   Qog'ozdagi hisobot va cheklar bo'yicha 2-ro'yxat (Moliya menejeri, buxgalter) yoki Direktor kiritadi. Har qator — bitta chek yoki
//   hujjat; xarajat «Buxgalteriya»ga o'zi ko'chadi, hisobdordagi qoldiq kamayadi (server: kassa_adv_report).
// Avans hisoboti qatoriga tanlanadigan statiyalar — server qabul qiladigan ro'yxatning o'zi (acc-5): kassa_refs har statiyaga «advReport»
//   belgisini serverdagi qoidadan (app.kassa_adv_article: EX — kassa xarajati, OP-18 asosiy vosita, OP-24 sotish uchun tovar) beradi.
export const advArticles = refs => ((refs && refs.articles) || []).filter(a => a && a.advReport === true);
async function openAdvForm() {
  const refs = ST.refs;
  // Hisobdorlar qoldig'i — har doim asosiy kassa bo'yicha (server ham sinov kassasini hisobga olmaydi).
  let c = ST.checks && ST.checks._desk === 'main' ? ST.checks : null;
  if (!c) { try { c = await call('kassa_checks', { p_desk: 'main' }); } catch (e) { C.toast(errText(e), true); return; } }
  const acc = (c.accountable || []).filter(x => num(x.balance) > 0);
  if (!acc.length) { C.toast('Hisobot qilinmagan avansi bor hisobdor yo‘q', true); return; }
  const arts = advArticles(refs);
  const today = ST.ov.state.today;
  const F = { ref: null, lines: [{ articleId: '', amount: '', note: '' }] };
  $('#modal').innerHTML = `<div class="modal-h"><h3>Avans hisoboti</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      <div class="small muted">Hisobdor topshirgan qog‘oz hisobot va cheklar bo‘yicha. Har qator — bitta chek yoki hujjat. Xarajat «Buxgalteriya»ga o‘zi ko‘chadi, hisobdordagi qoldiq kamayadi.</div>
      ${lbl('Hisobdor shaxs', `<select id="av-p" style="${FLD}"><option value="">— tanlang —</option>${acc.map(x => `<option value="${esc(x.partyId)}">${esc((x.name || x.partyId) + ' — qoldiq ' + som(x.balance))}</option>`).join('')}</select>`)}
      <div class="grid2">${lbl('Hisobot sanasi', `<input id="av-d" type="date" value="${esc(today)}" max="${esc(today)}" style="${FLD}">`)}${lbl('Izoh <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<input id="av-b" type="text" maxlength="300" style="${FLD}">`)}</div>
      <div class="small" style="font-weight:700;margin-top:10px">Xarajatlar <span class="muted" style="font-weight:500">— statiya, summa, chek yoki hujjat</span></div>
      <div id="av-lines"></div><button type="button" class="btn sm" id="av-add" style="margin-top:6px">+ qator</button>
      <div class="small" id="av-sum" style="margin-top:8px"></div>
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="av-save">Saqlash</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const bal = () => { const x = acc.find(a => a.partyId === $('#av-p').value); return x ? num(x.balance) : 0; };
  const total = () => F.lines.reduce((t2, l) => t2 + num(digits(l.amount)), 0);
  const sum = () => { const b = bal(), tt = total(), over = b && tt > b;
    $('#av-sum').innerHTML = `Jami: <b>${esc(som(tt))}</b>` + (b ? ` · qoldiq: ${esc(som(b))} → <b${over ? ' style="color:#B42318"' : ''}>${esc(som(b - tt))}</b>` : '')
      + (over ? ' — qoldiqdan katta: ortiqcha sarfni alohida «Xarajat» orderi bilan bering' : ''); };
  const artSel = (i, v) => `<select data-aart="${i}" style="${FLD}"><option value="">— statiya —</option>${arts.map(a => `<option value="${esc(a.id)}"${a.id === v ? ' selected' : ''}>${esc(a.id + ' · ' + a.nameUz)}</option>`).join('')}</select>`;
  const draw = () => {
    $('#av-lines').innerHTML = F.lines.map((l, i) => `<div style="display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr) minmax(0,1.4fr) auto;gap:6px;margin-top:6px">${artSel(i, l.articleId)}<input data-aamt="${i}" type="text" inputmode="numeric" placeholder="summa" value="${esc(l.amount)}" style="${FLD}"><input data-anote="${i}" type="text" maxlength="300" placeholder="chek № va sana" value="${esc(l.note)}" style="${FLD}">${F.lines.length > 1 ? `<button type="button" class="btn sm danger" data-adel="${i}">×</button>` : '<span></span>'}</div>`).join('');
    $('#av-lines').querySelectorAll('[data-aart]').forEach(el => el.onchange = () => { F.lines[Number(el.dataset.aart)].articleId = el.value; });
    $('#av-lines').querySelectorAll('[data-aamt]').forEach(el => { fmtInput(el); el.addEventListener('input', () => { F.lines[Number(el.dataset.aamt)].amount = el.value; sum(); }); });
    $('#av-lines').querySelectorAll('[data-anote]').forEach(el => el.addEventListener('input', () => { F.lines[Number(el.dataset.anote)].note = el.value; }));
    $('#av-lines').querySelectorAll('[data-adel]').forEach(el => el.onclick = () => { F.lines.splice(Number(el.dataset.adel), 1); draw(); sum(); });
  };
  draw(); sum();
  $('#av-p').onchange = sum;
  $('#av-add').onclick = () => { if (F.lines.length < 40) { F.lines.push({ articleId: '', amount: '', note: '' }); draw(); sum(); } };
  let busy = false;
  $('#av-save').onclick = async () => {
    if (busy) return;
    const pid = $('#av-p').value; if (!pid) { C.toast('Hisobdor shaxsni tanlang', true); return; }
    const ls = F.lines.map(l => ({ articleId: l.articleId, amount: num(digits(l.amount)), note: String(l.note || '').trim() })).filter(l => l.articleId || l.amount || l.note);
    if (!ls.length || ls.some(l => !l.articleId || !(l.amount > 0) || l.note.length < 3)) { C.toast('Har qatorda statiya, summa va chek yoki hujjat bo‘lsin', true); return; }
    if (ls.reduce((t2, l) => t2 + l.amount, 0) > bal()) { C.toast('Hisobot summasi hisobdordagi qoldiqdan katta', true); return; }
    busy = true; $('#av-save').disabled = true;
    const r = await act('kassa_adv_report', { p: { clientRef: F.ref || (F.ref = newRef()), partyId: pid, reportDate: $('#av-d').value, basis: $('#av-b').value.trim(), lines: ls } }, 'Avans hisoboti saqlandi');
    if (r) { if (r.id && confirm('Avans hisoboti chop etilsinmi?')) printDoc(r.id); }
    else { busy = false; const b = $('#av-save'); if (b) b.disabled = false; }
  };
}

// ---------------------------------------------------------------- kirim / chiqim shakli
//   Xodim bilan hisob-kitob kirimlari (acc-1, acc-3, acc-4): xodim (va «Xodim qaytargan pul»da oy) tanlangach oynada qoldiq ko'rinadi
//   (kassa_staff_open) — qaytim / qoplash shundan oshmaydi; qoida baribir serverda (kassa_receipt).
const STAFF_OPS = ['in_staff_return', 'in_acc_return', 'in_damage_repay'];
async function openDocForm(form) {
  const refs = ST.refs, m = me();
  const ops = (refs.rules || []).filter(r => r.form === form && r.manual && !r.systemOnly);
  if (!ops.length) { C.toast('Bu turdagi operatsiya yo‘q', true); return; }
  const isOut = form === 'KO2';
  $('#modal').innerHTML = `<div class="modal-h"><h3>${isOut ? 'Chiqim so‘rovi (KO-2)' : 'Kirim orderi (KO-1)'}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      ${lbl('Operatsiya', `<select id="kf-op" style="${FLD}">${ops.map(r => `<option value="${esc(r.op)}">${esc(r.nameUz)}</option>`).join('')}</select>`, ';margin-top:0')}
      <div id="kf-dyn"></div>
      <div class="small" id="kf-orgw" style="display:none;margin-top:10px;background:#FEF3E2;color:#B54708;border-radius:10px;padding:10px 12px"></div>
      <div class="small muted" id="kf-hint" style="margin-top:10px"></div>
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kf-save">${isOut ? 'So‘rov yuborish' : 'Qabul qilish'}</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const F = { party: null, lines: [{ articleId: '', amount: '', note: '' }], limit: null };
  // xodim qoldig'i (faqat ko'rsatish va oldindan ogohlantirish uchun)
  let infoSeq = 0;
  const staffInfo = async () => {
    const r = ops.find(x => x.op === $('#kf-op').value), box = $('#kf-staff');
    F.limit = null;
    if (!box || !r || !STAFF_OPS.includes(r.op)) return;
    const pid = F.party && F.party.type === 'employee' ? F.party.id : '';
    const mon = r.op === 'in_staff_return' ? String(($('#kf-month') || {}).value || '') : '';
    if (!pid || (r.op === 'in_staff_return' && !/^\d{4}-\d{2}$/.test(mon))) { box.style.display = 'none'; return; }
    const seq = ++infoSeq;
    box.style.display = ''; box.textContent = 'Qoldiq tekshirilmoqda…';
    let j;
    try { j = await call('kassa_staff_open', { p_desk: ST.desk, p_party: pid, p_month: mon || null }); }
    catch (e) { if (seq === infoSeq && $('#kf-staff')) $('#kf-staff').textContent = errText(e); return; }
    if (seq !== infoSeq || !$('#kf-staff')) return;
    const a = j.advance || {}, s = j.salary || {}, art = F.lines[0].articleId;
    let html;
    if (r.op === 'in_acc_return') { F.limit = num(j.accountable); html = `Hisobdordagi hisobot qilinmagan avans: <b>${esc(som(j.accountable))}</b> — qaytim shundan oshmaydi.`; }
    else if (r.op === 'in_damage_repay') { F.limit = num(j.damage); html = `Xodim zimmasidagi kamomad (Direktor qarori bilan): <b>${esc(som(j.damage))}</b> — qoplash shundan oshmaydi.`; }
    else if (art === 'OP-08') {
      F.limit = j.locked ? 0 : num(a.open);
      html = j.locked ? `<span style="color:#B42318">${esc(mon)} oy vedomosti tasdiqlangan — avans maoshdan ushlab qolingan. Pulni «OP-09» (ish haqi to‘lovi) statiyasi bilan qabul qiling yoki Direktor oyni qayta ochsin.</span>`
        : `${esc(mon)} oy naqd avansi: berilgan ${esc(som(a.given))}${num(a.returned) ? `, qaytgan ${esc(som(a.returned))}` : ''} — qoldiq <b>${esc(som(a.open))}</b>. Qaytim avansdan ayiriladi (vedomost sof avansni ushlaydi).`;
    } else if (art === 'OP-09') {
      F.limit = num(s.net);
      html = `${esc(mon)} oy uchun naqd berilgan maosh: ${esc(som(s.paid))}${num(s.returned) ? `, qaytgan ${esc(som(s.returned))}` : ''} — sof <b>${esc(som(s.net))}</b>. Qaytgan pul shu oy yana berilishi yoki keyingi oyga qoldiq bo‘lib o‘tishi mumkin.`;
    } else html = `${esc(mon)}: naqd avans qoldig‘i ${esc(som(a.open))}, naqd berilgan maosh ${esc(som(s.net))} — statiyani tanlang (avans yoki ish haqi).`;
    $('#kf-staff').innerHTML = html;
  };
  const drawDyn = async () => {
    const r = ops.find(x => x.op === $('#kf-op').value);
    const types = r.partyTypes || [];
    const multi = r.op === 'out_expense';
    const arts = r.articleMode === 'choose' ? (refs.articles || []).filter(a => (r.allowedArticles || []).length ? r.allowedArticles.includes(a.id) : a.cashOutAllowed) : [];
    const artSel = (i, v) => `<select data-art="${i}" style="${FLD}"><option value="">— statiya —</option>${arts.map(a => `<option value="${esc(a.id)}"${a.id === v ? ' selected' : ''}>${esc(a.id + ' · ' + a.nameUz)}</option>`).join('')}</select>`;
    $('#kf-dyn').innerHTML = `
      ${types.length ? lbl(isOut ? 'Kimga' : 'Kimdan', `${types.length > 1 ? `<select id="kf-ptype" style="${FLD}">${types.map(t => `<option value="${t}">${esc(PARTY_LBL[t] || t)}</option>`).join('')}</select>` : `<input type="hidden" id="kf-ptype" value="${esc(types[0])}">`}<div id="kf-party"></div>`) : ''}
      ${r.articleMode === 'choose' && !multi ? lbl('Statiya', artSel(0, F.lines[0].articleId)) : ''}
      ${r.op === 'in_staff_return' ? lbl('Qaysi oy avansi / maoshi <span style="color:#B42318">(majburiy)</span>', `<input id="kf-month" type="month" value="${esc(String((ST.ov && ST.ov.state && ST.ov.state.today) || '').slice(0, 7))}" style="${FLD}">`) : ''}
      ${STAFF_OPS.includes(r.op) ? `<div class="small" id="kf-staff" style="display:none;margin-top:8px;background:#eef3f1;border-radius:10px;padding:10px 12px"></div>` : ''}
      ${multi ? `<div class="small" style="font-weight:700;margin-top:10px">Statiya va summa <span class="muted" style="font-weight:500">— bir hujjatda bir nechta statiya bo‘lishi mumkin</span></div><div id="kf-lines"></div><button type="button" class="btn sm" id="kf-addline" style="margin-top:6px">+ qator</button>`
        : lbl('Summa (so‘m)', `<input id="kf-amt" type="text" inputmode="numeric" placeholder="0" style="${FLD}">`)}
      ${lbl('Asos <span class="muted" style="font-weight:500">— hujjat nomi, raqami, sanasi</span>', `<input id="kf-basis" type="text" maxlength="300" style="${FLD}">`)}
      ${r.op === 'out_expense' ? `<label class="small" style="display:flex;gap:8px;align-items:center;margin-top:8px"><input type="checkbox" id="kf-nobasis" style="${CHK}"> Asos hujjati yo‘q (bozordan naqd xarid) — faqat ${esc(som(ST.ov.state.l1))}gacha va bitta statiya</label>` : ''}
      ${lbl('Ilova <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<input id="kf-attach" type="text" maxlength="300" style="${FLD}">`)}
      ${lbl('Izoh' + (r.op === 'in_other' ? ' <span style="color:#B42318">(majburiy)</span>' : ''), `<input id="kf-note" type="text" maxlength="300" style="${FLD}">`)}
      ${r.fiscalRequired ? lbl('Fiskal chek № <span style="color:#B42318">(majburiy)</span>', `<input id="kf-fiscal" type="text" maxlength="40" style="${FLD}">`) + (m.director ? `<label class="small" style="display:flex;gap:8px;align-items:center;margin-top:6px"><input type="checkbox" id="kf-fexempt" style="${CHK}"> Fiskal cheksiz (istisno — jurnalga yoziladi)</label>` : '') : ''}`;
    fmtInput($('#kf-amt'));
    const hint = [];
    if (r.needsApproval) hint.push('Pul berishdan oldin Moliya menejeri / buxgalter tasdiqlaydi' + (r.directorAlways ? ', Direktor ham' : `; ${som(ST.ov.state.t1)}dan katta summada — Direktor ham`) + '.');
    else if (r.directorAlways) hint.push('Avval Direktor ruxsat beradi, keyin kassir pulni qabul qiladi.');
    else if (!isOut) hint.push('Order darhol o‘tkaziladi: raqam va sana serverdan beriladi.');
    if (r.op === 'in_staff_return') hint.push('Avans qaytsa (OP-08) — shu oy avansidan ayiriladi (oy vedomosti hali tasdiqlanmagan bo‘lsin); berilgan maosh qaytsa (OP-09) — shu oy berilgan maoshdan.');
    if (r.op === 'in_damage_repay') hint.push('Direktor qarori bilan xodim zimmasiga yozilgan kassa kamomadi naqd qoplanadi.');
    $('#kf-hint').textContent = hint.join(' ');
    const km = $('#kf-month'); if (km) km.addEventListener('change', staffInfo);
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
    } else { const a0 = $('#kf-dyn').querySelector('[data-art="0"]'); if (a0) a0.onchange = () => { F.lines[0].articleId = a0.value; staffInfo(); }; }
    const pt = $('#kf-ptype'); if (pt) { pt.onchange = () => drawParty(pt.value); await drawParty(pt.value); }
  };
  const drawParty = async type => {
    F.party = { type, id: '', name: '' };
    F.limit = null; infoSeq++;   // tomon almashdi — oldingi xodim qoldig'i (va kechikkan javobi) amal qilmaydi
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
      $('#kf-pe').onchange = () => { F.party.id = $('#kf-pe').value; staffInfo(); };
    } else if (type === 'other') {
      box.innerHTML = `<input id="kf-po" type="text" placeholder="F.I.Sh. yoki nomi (to‘liq)" maxlength="200" style="${FLD};margin-top:6px"><div class="small muted" style="margin-top:4px">«Boshqa» tomonlar nazorat ro‘yxatida alohida ko‘rinadi — imkon bo‘lsa kontragentni tanlang.</div>`;
      $('#kf-po').addEventListener('input', () => { F.party.name = $('#kf-po').value.trim(); });
    } else {
      const want = k => type === 'bank' ? k === 'bank' : type === 'founder' ? k === 'founder' : (k !== 'bank' && k !== 'founder');
      const drawC = sel => { const cps = (ST.refs.counterparties || []).filter(c => want(c.kind));
        box.innerHTML = `<div style="display:flex;gap:6px;margin-top:6px"><select id="kf-pc" style="${FLD}"><option value="">— ${esc(PARTY_LBL[type] || type)} —</option>${cps.map(c => `<option value="${esc(c.id)}"${c.id === sel ? ' selected' : ''}>${esc(cpLabel(c))}</option>`).join('')}</select><button type="button" class="btn sm" id="kf-pnew" title="Yangi qo‘shish">+ yangi</button></div><div id="kf-pnewbox"></div>`;
        F.party.id = sel || '';
        // yuridik shaxsga naqd (F1.27): server qoidasi (kassa_refs → org) — turi tasdiqlanmagan «jismoniy shaxs» / «boshqa» ham (sec-3)
        const orgWarn = () => { const op = $('#kf-op').value, c = (ST.refs.counterparties || []).find(x => x.id === F.party.id), w = $('#kf-orgw');
          const on = isOut && op === 'out_expense' && type === 'counterparty' && cpIsOrg(c);
          const mx = num(((ST.refs.org || {}).extra || {}).orgCashMax);
          if (w) { w.style.display = on ? '' : 'none'; if (on) w.innerHTML = (cpUnconfirmed(c) ? `<b>Kontragent turi («${esc(CP_KIND[c.kind] || c.kind)}») hali tasdiqlanmagan — yuridik shaxs hisoblanadi.</b> Buxgalter yoki Direktor turini tasdiqlaguncha kassadan naqd to‘lov `
            : `<b>Yuridik shaxsga kassadan naqd to‘lov cheklangan.</b> Asosiy yo‘l — bank o‘tkazmasi yoki hisobdor shaxs orqali (avans hisoboti). Kassadan berilsa — `)
            + `${mx ? esc(som(mx)) + 'dan katta summada ' : ''}Direktor tasdig‘i ham talab qilinadi; buxgalter nazorat ro‘yxatida ko‘radi.`; } };
        $('#kf-pc').onchange = () => { F.party.id = $('#kf-pc').value; orgWarn(); };
        orgWarn();
        $('#kf-pnew').onclick = () => {
          const kinds = type === 'bank' ? ['bank'] : type === 'founder' ? ['founder'] : ['supplier', 'org', 'person', 'other'];
          // sec-3: «Jismoniy shaxs» / «Boshqa» turini buxgalter yoki Direktor tasdiqlaydi (ular kiritsa — darhol tasdiqlangan)
          const confNote = kinds.includes('person') && !me().kindConfirm
            ? `<div class="small muted" style="margin-top:6px">«Jismoniy shaxs» va «Boshqa» turini buxgalter yoki Direktor tasdiqlaydi; tasdiqlanguncha kontragent yuridik shaxs hisoblanadi (kassadan naqd to‘lovga Direktor tasdig‘i kerak). Korxona (MChJ, AJ) — «Yetkazib beruvchi» yoki «Tashkilot».</div>` : '';
          $('#kf-pnewbox').innerHTML = `<div style="border:1px dashed var(--border);border-radius:10px;padding:8px;margin-top:6px"><input id="kf-cn" type="text" placeholder="Nomi (to‘liq)" maxlength="200" style="${FLD}"><div style="display:flex;gap:6px;margin-top:6px"><select id="kf-ck" style="${FLD}">${kinds.map(k => `<option value="${k}">${esc(CP_KIND[k])}</option>`).join('')}</select><input id="kf-cs" type="text" inputmode="numeric" placeholder="STIR (ixtiyoriy)" maxlength="14" style="${FLD}"><button type="button" class="btn sm gold" id="kf-cadd">Qo‘shish</button></div>${confNote}</div>`;
          $('#kf-cadd').onclick = async () => { const nm = $('#kf-cn').value.trim(); if (nm.length < 2) { C.toast('Nomini yozing', true); return; }
            try { const c = await call('fin_counterparty_save', { p_id: null, p_kind: $('#kf-ck').value, p_name: nm, p_stir: digits($('#kf-cs').value) }); await loadRefs(true); drawC(c.id); C.toast('Qo‘shildi ✓'); }
            catch (e) { C.toast(errText(e), true); } };
        }; };
      drawC('');
    }
  };
  $('#kf-op').onchange = () => { F.lines = [{ articleId: '', amount: '', note: '' }]; const w = $('#kf-orgw'); if (w) w.style.display = 'none'; drawDyn(); };
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
    if (r.op === 'in_staff_return') { p.month = String(($('#kf-month') || {}).value || ''); if (!/^\d{4}-\d{2}$/.test(p.month)) { C.toast('Qaysi oy avansi / maoshi qaytarilayotganini tanlang', true); return; } }
    if (STAFF_OPS.includes(r.op) && F.limit != null && p.amount > F.limit) { C.toast(`Summa xodim qoldig‘idan (${som(F.limit)}) katta`, true); return; }
    if (!p.noBasis && p.basis.length < 3) { C.toast('Asosni yozing (hujjat nomi, raqami, sanasi)', true); return; }
    if (r.fiscalRequired) { const fx = $('#kf-fexempt'); p.fiscalNo = $('#kf-fiscal').value.trim(); if (!p.fiscalNo) { if (fx && fx.checked) p.fiscalExempt = true; else { C.toast('Fiskal chek raqamini kiriting', true); return; } } }
    busy = true; const btn = $('#kf-save'); btn.disabled = true; btn.textContent = 'Yuborilmoqda…';
    try {
      const res = await call(isOut ? 'kassa_payout_request' : 'kassa_receipt', { p });
      C.closeModal();
      if (res.status === 'posted') { C.toast(`Kirim orderi № ${res.no} o‘tkazildi ✓`); await reload(); offerPrint(res); }
      else { C.toast(num(res.accOpen) > 0 ? `So‘rov yuborildi — hisobdorda ${som(res.accOpen)} hisobot qilinmagan avans bor, Direktor tasdig‘i ham kerak ✓`
        : res.orgCash && res.needsDirector ? 'So‘rov yuborildi — yuridik shaxsga naqd to‘lov: Direktor tasdig‘i ham kerak ✓' : 'So‘rov yuborildi — tasdiq kutilmoqda ✓'); await reload(); }
      if (C.onChange) C.onChange();
    } catch (e) { busy = false; btn.disabled = false; btn.textContent = isOut ? 'So‘rov yuborish' : 'Qabul qilish'; C.toast(errText(e), true); }
  };
}

// ---------------------------------------------------------------- sanash: kunni yopish / smena topshirish
// state-2: qurilma navbatidagi hali yuborilmagan naqd to'lovlar — oyna ochilganda o'qiladi va kaliti bilan yuboriladi (qo'lda kiritilmaydi:
//   server o'tib ketganlarini o'zi hisobga olmaydi); crit-3: «Қ» blankalari — alohida qo'lda (faqat kunni yopishda).
//   opts: paper — «Қ» blankalari maydonlari; late — o'tgan kun yopilmoqda (server ishlamagan kun bo'lishi mumkin — ajratib ko'rsatiladi);
//   po — kun javobidagi pendingOpen (g7v-3: smena topshirishda e'lon qilingan, hali kelmagan yozuvlar — server o'zi hisobga oladi,
//   sanalgan pulga sig'ganicha: oyna farqi ham shunday — countBind).
//   g7v-2: pul kassaga tegishli emas deb server rad etgan navbat yozuvlari e'lon qilinmaydi — soni bitta qatorda (ob.skipped).
function countFields(expected, ob, opts) {
  opts = opts || {};
  const o = outboxRefs(ob), h = handoverRefs(opts.po, o.refs), sk = num(ob && ob.skipped);
  return `<div class="small" style="background:#eef3f1;border-radius:10px;padding:10px 12px">Hisobdagi qoldiq: <b>${esc(som(expected))}</b></div>
    ${lbl('Kassadagi pul — SANALGAN summa (so‘m)', `<input id="kc-counted" type="text" inputmode="numeric" placeholder="0" style="${FLD}">`)}
    <details style="margin-top:8px"><summary class="small" style="cursor:pointer;font-weight:700">Nominallar bo‘yicha sanash</summary>
      <div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:6px;margin-top:6px">${NOMINALS.map(n => `<label class="small muted" style="display:flex;flex-direction:column;gap:3px">${n.toLocaleString('ru-RU')}<input data-nom="${n}" type="text" inputmode="numeric" placeholder="dona" style="padding:6px 8px;border:1px solid var(--border);border-radius:8px;font:inherit;width:100%"></label>`).join('')}</div></details>
    <div class="small" id="kc-ob" style="margin-top:8px;border-radius:10px;padding:8px 10px;${o.count ? 'background:#FEF3E2;color:#B54708' : 'background:#F2F4F7;color:#475467'}">${o.count
      ? `Shu qurilma navbatida hali yuborilmagan naqd to‘lovlar: <b>${esc(String(o.count))} ta, ${esc(som(o.sum))}</b> — «hali o‘tkazilmagan yozuvlar» sifatida hisobga olinadi (pul kassada bor, hisobda hali yo‘q). Keyin o‘tganda «kech» bo‘lib tushadi va shu kun bilan bog‘lanadi.`
      : 'Shu qurilma navbatida yuborilmagan naqd to‘lov yo‘q.'}${o.old ? ' <b>Sahifani yangilang</b> (Ctrl+Shift+R) — navbat yozuvlari kalitsiz.' : ''}</div>
    ${h.count ? `<div class="small" id="kc-ho" style="margin-top:6px;border-radius:10px;padding:8px 10px;background:#FEF3E2;color:#B54708">Smena topshirishda e’lon qilingan, hali kelmagan: <b>${esc(String(h.count))} ta, ${esc(som(h.sum))}</b> — boshqa qurilma navbatida (pul kassada bor, hisobda hali yo‘q): tizim o‘zi hisobga oladi (sanalgan pulga sig‘ganicha).</div>` : ''}
    ${sk ? `<div class="small muted" id="kc-skip" style="margin-top:6px">${esc(String(sk))} ta navbat yozuvi hisobga olinmadi — kassa ishga tushishidan oldingi pul; ⏳ navbatda ko‘ring</div>` : ''}
    ${opts.paper ? paperFields(!!opts.late) : ''}
    <div id="kc-diff" class="small" style="margin-top:8px;font-weight:700"></div>
    ${lbl('Izoh', `<input id="kc-note" type="text" maxlength="300" style="${FLD}">`)}`;
}
// crit-3: server ishlamagan paytdagi «Қ» blankalari (kassada pul bor, hisobda hali yo'q); o'tgan kun yopilayotganda — ajratib ko'rsatiladi.
function paperFields(late) {
  return `<div id="kc-paper" style="margin-top:10px;border-radius:10px;padding:${late ? '8px 10px;background:#FEF3E2' : '0'}">
    <div class="small" style="font-weight:700">Server ishlamagan paytdagi «Қ» blankalari <span class="muted" style="font-weight:500">— bo‘lmasa, bo‘sh qoldiring</span></div>
    <div class="small muted">Tizim (server) ishlamagan paytda to‘ldirilgan, hali kiritilmagan «Қ» blankalari: pul kassada bor, hisobda hali yo‘q. Kun yopilgach har birini «Қ» raqami bilan (izohda) kiriting — ishga-tushirish §8.</div>
    ${late ? `<div class="small" style="color:#B54708;font-weight:700;margin-top:4px">O‘tgan kun yopilmoqda: shu kuni server ishlamagan bo‘lsa — to‘ldirilgan «Қ» blankalarini shu yerda ko‘rsating (aks holda ular bugun ortiqcha, keyin kamomad bo‘lib chiqadi).</div>` : ''}
    <div class="grid2" style="margin-top:4px">${lbl('Soni', `<input id="kc-qcnt" type="text" inputmode="numeric" placeholder="0" style="${FLD}">`)}${lbl('Summasi (so‘m)', `<input id="kc-qsum" type="text" inputmode="numeric" placeholder="0" style="${FLD}">`)}</div>
    ${lbl('Blanka raqamlari', `<input id="kc-qnos" type="text" maxlength="300" placeholder="masalan: Қ-0012, Қ-0013" style="${FLD}">`)}</div>`;
}
function countBind(expected, ob, po) {
  const counted = $('#kc-counted'); fmtInput(counted); fmtInput($('#kc-qsum'));
  const o = outboxRefs(ob), qsum = () => { const el = $('#kc-qsum'); return el ? num(digits(el.value)) : 0; };
  // g7b-v1: smena topshirishda e'lon qilingan yozuvlar — server kabi sanalgan pulga sig'ganicha (qolgan joy: sanalgan − navbat − «Қ»)
  const hand = c => handoverRefs(po, o.refs, c - o.sum - qsum());
  const noms = () => { const o2 = {}; let sum = 0, any = false; $('#modal').querySelectorAll('[data-nom]').forEach(el => { const c = num(digits(el.value)); if (c > 0) { o2[el.dataset.nom] = c; sum += c * Number(el.dataset.nom); any = true; } }); return { o: o2, sum, any }; };
  // farq — server bilan bir xil: sanalgan − hisobdagi − qurilma navbati − smena topshirishda e'lon qilingan, hali kelmagan (g7v-3) − «Қ» blankalari
  const upd = () => { const c = num(digits(counted.value)), h = hand(c), d = c - expected - o.sum - h.sum - qsum(); const el = $('#kc-diff');
    if (!digits(counted.value)) { el.textContent = ''; return; }
    el.style.color = d === 0 ? '#157347' : (d < 0 ? '#B42318' : '#B54708');
    el.textContent = (d === 0 ? 'Farq yo‘q ✓' : (d < 0 ? `KAMOMAD: ${som(-d)} — shu kun sanasi bilan chiqim hujjati yoziladi (qaror — Direktor)` : `ORTIQCHA: ${som(d)} — shu kun sanasi bilan kirim hujjati yoziladi`))
      + (h.left ? ` · smena yozuvlaridan ${h.left} tasi (${som(h.leftSum)}) sanalgan pulga sig‘madi — ayirilmaydi` : ''); };
  $('#modal').querySelectorAll('[data-nom]').forEach(el => el.addEventListener('input', () => { el.value = digits(el.value); const n = noms(); if (n.any) counted.value = String(n.sum).replace(/\B(?=(\d{3})+(?!\d))/g, ' '); upd(); }));
  counted.addEventListener('input', upd); const qs = $('#kc-qsum'); if (qs) qs.addEventListener('input', upd);
  return () => { const n = noms(), c = num(digits(counted.value)), h = hand(c), q = $('#kc-qcnt') ? paperRead($('#kc-qcnt').value, $('#kc-qsum').value, $('#kc-qnos').value) : {};
    return { counted: digits(counted.value) === '' ? null : c, denoms: n.any && n.sum === c ? n.o : null, pendingRefs: o.refs, pending: o.sum, pendingCount: o.count,
             handSum: h.sum, handCount: h.count, handLeft: h.left, handLeftSum: h.leftSum, paper: q.paper || null, paperErr: q.err || '', note: $('#kc-note').value.trim() }; };
}
// ---- onlayn kassa (NKM) Z-hisoboti (F1.26): Z dagi SOTUV jamlari yoziladi; tizim fiskal chekli kirim orderlari va terminal
//   to'lovlari bilan solishtiradi (kutilgan summa oldindan ko'rsatilmaydi — kassir Z dagi raqamni yozadi).
const sgnSom = v => `${num(v) > 0 ? '+' : '−'}${som(Math.abs(num(v)))}`;
export function zText(z) {   // kun javobidagi «z» → qisqa holat matni ('' — ko'rsatiladigan narsa yo'q)
  if (!z || !z.applies) return '';
  if (!z.recorded) return z.needed ? 'kiritilmagan' : '';
  if (z.missing) return 'yo‘q' + (z.reason ? ` (${z.reason})` : '');
  if (z.ok === false) return 'farq: ' + [num(z.diffCash) ? `naqd ${sgnSom(z.diffCash)}` : '', num(z.diffCard) ? `karta ${sgnSom(z.diffCard)}` : ''].filter(Boolean).join(', ');
  return z.ok === true ? 'mos' : 'kiritilgan';
}
function zFields(z) {
  z = z || {};
  const v = x => x == null ? '' : String(num(x)).replace(/\B(?=(\d{3})+(?!\d))/g, ' '), m = !!z.missing;
  return `<div class="small" style="font-weight:700;margin-top:12px">Onlayn kassa (NKM) Z-hisoboti${z.needed === false ? ' <span class="muted" style="font-weight:500">— shu kuni fiskal chek bo‘lmagan bo‘lsa, shart emas</span>' : ''}</div>
    <div class="small muted">Kun oxirida kassa apparati chiqargan Z-hisobotdagi sotuv jamlari (qaytarishlarsiz). Tizim fiskal chekli kirim orderlari va terminal to‘lovlari bilan solishtiradi.</div>
    <div class="grid2" style="margin-top:4px">${lbl('Z-hisobot №', `<input id="kz-no" type="text" maxlength="20" value="${esc(m ? '' : (z.no || ''))}" style="${FLD}">`)}${lbl('Naqd (so‘m)', `<input id="kz-cash" type="text" inputmode="numeric" placeholder="0" value="${esc(m ? '' : v(z.cash))}" style="${FLD}">`)}</div>
    <div class="grid2">${lbl('Bank kartasi (so‘m)', `<input id="kz-card" type="text" inputmode="numeric" placeholder="0" value="${esc(m ? '' : v(z.card))}" style="${FLD}">`)}<span></span></div>
    <label class="small" style="display:flex;gap:8px;align-items:flex-start;margin-top:6px"><input type="checkbox" id="kz-miss" style="${CHK}"${m ? ' checked' : ''}> Z-hisobot yo‘q (kassa apparati ishlamadi yoki hisobot hozir qo‘lda emas — keyin «Z» tugmasi bilan kiritiladi)</label>
    <div id="kz-why-box"${m ? '' : ' style="display:none"'}>${lbl('Sababi', `<input id="kz-why" type="text" maxlength="300" value="${esc(m ? (z.reason || '') : '')}" style="${FLD}">`)}</div>`;
}
function zBind() {   // o'qish funksiyasini qaytaradi: {z} | {err} | {} (hech narsa kiritilmagan)
  ['#kz-cash', '#kz-card'].forEach(s => { const el = $(s); if (el) fmtInput(el); });
  const mb = $('#kz-miss'); if (mb) mb.onchange = () => { $('#kz-why-box').style.display = mb.checked ? '' : 'none'; };
  return () => {
    if (!$('#kz-no')) return {};
    if ($('#kz-miss').checked) { const r = $('#kz-why').value.trim(); return r.length < 5 ? { err: 'Z-hisobot yo‘qligi sababini yozing (kamida 5 belgi)' } : { z: { missing: true, reason: r } }; }
    const no = $('#kz-no').value.trim(), c = digits($('#kz-cash').value), k = digits($('#kz-card').value);
    if (!no && c === '' && k === '') return {};
    if (!/^[0-9A-Za-z/-]{1,20}$/.test(no)) return { err: 'Z-hisobot raqamini kiriting (harf, raqam, «-» yoki «/»)' };
    if (c === '' || k === '') return { err: 'Z-hisobotdagi naqd va bank kartasi summalarini kiriting (bo‘lmasa — 0)' };
    return { z: { no, cash: num(c), card: num(k) } };
  };
}
function zToast(z) {   // yopish / kiritishdan keyin solishtirish natijasi
  if (!z || !z.applies || !z.recorded || z.missing) return;
  if (z.ok) C.toast('Z-hisobot tizim bilan mos ✓');
  else C.toast(`Z-hisobot ${zText(z)} — buxgalter kunni izoh bilan tekshiradi`, true);
}
function zSummary(z) { return z.missing ? `Z-hisobot: yo‘q (${z.reason})` : `Z-hisobot № ${z.no}: naqd ${som(z.cash)}, karta ${som(z.card)}`; }
function openZForm(day) {
  const d = (ST.ov.days || []).find(x => String(x.day) === String(day)); if (!d) return;
  $('#modal').innerHTML = `<div class="modal-h"><h3>Z-hisobot — ${esc(dmy(day))}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">${zFields(d.z)}<div class="small muted" style="margin-top:8px">Kun tekshirilguncha kiritiladi yoki tuzatiladi; har o‘zgarish kun jurnalida qoladi.</div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kz-save">Saqlash</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const read = zBind();
  $('#kz-save').onclick = async () => { const zr = read();
    if (zr.err) { C.toast(zr.err, true); return; }
    if (!zr.z) { C.toast('Z-hisobot ma’lumotini kiriting yoki «Z-hisobot yo‘q»ni belgilang', true); return; }
    $('#kz-save').disabled = true;
    await act('kassa_day_z', { p: { desk: ST.desk, day, z: zr.z } }, 'Z-hisobot saqlandi', r => zToast(r && r.day && r.day.z));
    const b = $('#kz-save'); if (b) b.disabled = false; };
}
const commissionFields = () => `<div class="small" style="font-weight:700;margin-top:10px">Komissiya (kassir o‘rniga yopilganda kamida 2 kishi)</div>${[0, 1, 2].map(i => `<div class="grid2" style="margin-top:6px"><input data-ct="${i}" type="text" placeholder="Lavozimi" maxlength="120" style="${FLD}"><input data-cn="${i}" type="text" placeholder="F.I.Sh." maxlength="200" style="${FLD}"></div>`).join('')}`;
const commissionRead = () => [0, 1, 2].map(i => ({ title: ($('#modal').querySelector(`[data-ct="${i}"]`) || {}).value || '', name: (($('#modal').querySelector(`[data-cn="${i}"]`) || {}).value || '').trim() })).filter(x => x.name.length >= 3);
// Kunni yopish (state-2, CT-15): avval qurilma navbati yuboriladi (internet bo'lsa), keyin oyna yangi qoldiq bilan ochiladi — qolgan (yuborilmagan)
//   navbat yozuvlari kaliti bilan «hali o'tkazilmagan» bo'lib yuboriladi (yopish bloklanmaydi); server qoldiq oyna ochilgandan keyin o'zgargan
//   bo'lsa rad etadi (kassa:stale) — oyna qayta ochiladi. Natija xabarida — server hisoblagan farq. crit-3: «Қ» blankalari — alohida.
async function openCloseForm() {
  if (C.flushOutbox) { try { await C.flushOutbox(); } catch (_) { /* internet yo'q — navbatda qolganlari e'lon qilinadi */ } await reload().catch(() => {}); }
  const od = ST.ov && ST.ov.state.openDay, m = me(); if (!od) return;
  const ob = C.outboxCash ? C.outboxCash() : { count: 0, sum: 0, refs: [] };
  const isTest = !!(ST.ov.state.desk && ST.ov.state.desk.isTest), oz = od.z || {}, late = String(od.day) < String(ST.ov.state.today || '');
  // sec-2: kassa egasi (kun kassiri) bo'lmagan kassir, Direktor, Moliya menejeri — kassir o'rniga: komissiya (server ham tekshiradi)
  const needC = needCommission(od, m);
  const instead = needC && od.cashierUid ? `<div class="small" style="margin-top:8px;background:#FEF3E2;color:#B54708;border-radius:10px;padding:8px 10px;font-weight:600">Kassa egasi — ${esc(od.cashierName || nameOf(od.cashierUid))}. Uning o‘rniga yopilmoqda: komissiya (kamida 2 kishi) dalolatnomani imzolaydi; kamomad bo‘lsa, javobgarni Direktor tanlaydi.</div>` : '';
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kunni yopish — ${esc(dmy(od.day))}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">${countFields(num(od.balance), ob, { paper: true, late, po: od.pendingOpen })}${instead}${needC ? commissionFields() : ''}${isTest ? '' : zFields(oz)}
      <div class="small muted" style="margin-top:8px">Yopilgach bu kunga hujjat yozilmaydi (faqat Direktor qayta ochadi). Kassa kitobi varag‘ini 2 nusxada chop eting va imzolang.</div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kc-save">Sanab yopish</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const read = countBind(num(od.balance), ob, od.pendingOpen), zRead = zBind();
  $('#kc-save').onclick = async () => {
    const v = read(); if (v.counted == null) { C.toast('Sanalgan summani kiriting (0 bo‘lsa — 0)', true); return; }
    if (v.paperErr) { C.toast(v.paperErr, true); return; }
    // expected — oynadagi qoldiq (state-2: shu orada o'zgargan bo'lsa server rad etadi); pendingRefs — navbat yozuvlari kaliti bilan
    const p = { desk: ST.desk, day: od.day, counted: v.counted, expected: num(od.balance), pendingRefs: v.pendingRefs, note: v.note };
    if (v.paper) p.paper = v.paper;
    if (v.denoms) p.denoms = v.denoms;
    if (needC) { p.commission = commissionRead(); if (p.commission.length < 2) { C.toast('Komissiya a’zolarini kiriting (kamida 2 kishi)', true); return; } }
    const zr = zRead(); if (zr.err) { C.toast(zr.err, true); return; }
    if (zr.z) p.z = zr.z;
    else if (!isTest && oz.needed && !confirm('Onlayn kassa Z-hisoboti kiritilmadi.\n\nKun yopiladi, lekin nazorat ro‘yxatida ko‘rinadi va kunni tekshirishda izoh talab qilinadi. Z-hisobotni keyin «Z» tugmasi bilan kiritish mumkin.\n\nDavom etilsinmi?')) return;
    const qs = v.paper ? v.paper.sum : 0, d = v.counted - num(od.balance) - v.pending - v.handSum - qs;   // g7v-3: server ham shunday hisoblaydi
    if (!confirm(`Kun yopilsinmi? ${dmy(od.day)}\n\nSanalgan: ${som(v.counted)}\nHisobda: ${som(od.balance)}${v.pending ? `\nQurilma navbatida (hali o‘tkazilmagan): ${som(v.pending)} (${v.pendingCount} ta)` : ''}${v.handSum ? `\nSmena topshirishda e’lon qilingan, hali kelmagan: ${som(v.handSum)} (${v.handCount} ta)` : ''}${v.handLeft ? `\nSanalgan pulga sig‘magan smena yozuvlari (ayirilmaydi): ${som(v.handLeftSum)} (${v.handLeft} ta)` : ''}${qs ? `\n«Қ» blankalari: ${som(qs)} (${v.paper.count} ta, № ${v.paper.nos})` : ''}\n${d === 0 ? 'Farq yo‘q.' : (d < 0 ? 'KAMOMAD: ' + som(-d) : 'ORTIQCHA: ' + som(d))}${p.z ? '\n' + zSummary(p.z) : ''}`)) return;
    $('#kc-save').disabled = true;
    await act('kassa_day_close', { p }, r => 'Kun yopildi: ' + countResultText(r), r => { zToast(r && r.day && r.day.z); if (confirm('Kassa kitobi varag‘i (KO-4) chop etilsinmi?')) printBook(od.day); },
      staleReopen(openCloseForm));
    const b = $('#kc-save'); if (b) b.disabled = false;
  };
}
// Smena topshirish (state-6): IKKI BOSQICH — topshiruvchi pulni qabul qiluvchi bilan birga sanaydi va yozadi (qabul kutiladi); qabul qiluvchi
//   o'z hisobidan «Qabul qildim» deydi (kartadagi tugma) — shundagina dalolatnoma, farq hujjati va yangi kassa egasi. Kassa egasi bo'lmagan
//   kassir yoki Direktor — kassir o'rniga, komissiya bilan (sec-2; o'zi qabul qiluvchi bo'lishi ham mumkin).
async function openHandoverForm() {
  if (C.flushOutbox) { try { await C.flushOutbox(); } catch (_) { /* internet yo'q */ } await reload().catch(() => {}); }   // state-2: avval navbat yuboriladi
  const od = ST.ov && ST.ov.state.openDay, m = me(); if (!od || ST.ov.state.handover) return;
  const holder = deskHolder(od, m), needC = needCommission(od, m);
  const opsL = (ST.refs.operators || []).filter(o => o.uid !== holder);
  const ob = C.outboxCash ? C.outboxCash() : { count: 0, sum: 0, refs: [] };
  $('#modal').innerHTML = `<div class="modal-h"><h3>Smena topshirish — ${esc(dmy(od.day))}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">${lbl('Qabul qiluvchi kassir', `<select id="kh-to" style="${FLD}"><option value="">— tanlang —</option>${opsL.map(o => `<option value="${esc(o.uid)}">${esc(o.name)}${o.uid === m.uid ? ' (o‘zim)' : ''}</option>`).join('')}</select>`, ';margin-top:0')}
      ${needC ? `<div class="small" style="margin-top:8px;background:#FEF3E2;color:#B54708;border-radius:10px;padding:8px 10px;font-weight:600">${holder ? `Kassa egasi — ${esc(od.cashierName || nameOf(holder))}. ` : ''}Siz kassir o‘rniga topshiryapsiz: komissiya (kamida 2 kishi) bilan.</div>` : ''}
      ${countFields(num(od.balance), ob, { po: od.pendingOpen })}${needC ? commissionFields() : ''}<div class="small muted" style="margin-top:8px">Pul ikkala kassir ishtirokida sanaladi. Topshirilgach qabul qiluvchi o‘z hisobidan «Qabul qildim» deydi — shundagina smena o‘tadi va farq bo‘lsa hujjat yoziladi (kassa egasi — topshiruvchi nomidan). Qabul qilinguncha kassada hujjat yozilmaydi; kun ochiq qoladi.</div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kh-save">Topshirish</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const read = countBind(num(od.balance), ob, od.pendingOpen);
  $('#kh-save').onclick = async () => { const v = read(), to = $('#kh-to').value;
    if (!to) { C.toast('Qabul qiluvchi kassirni tanlang', true); return; }
    if (v.counted == null) { C.toast('Sanalgan summani kiriting', true); return; }
    const p = { desk: ST.desk, counted: v.counted, expected: num(od.balance), pendingRefs: v.pendingRefs, toUid: to, note: v.note }; if (v.denoms) p.denoms = v.denoms;
    if (needC) { p.commission = commissionRead(); if (p.commission.length < 2) { C.toast('Komissiya a’zolarini kiriting (kamida 2 kishi)', true); return; } }
    $('#kh-save').disabled = true;
    await act('kassa_handover', { p }, r => 'Smena topshirish yozildi (' + countResultText(r) + ') — qabul qiluvchi o‘z hisobidan «Qabul qildim» desin', null, staleReopen(openHandoverForm));
    const b = $('#kh-save'); if (b) b.disabled = false; };
}
// Smenani qabul qilish (qabul qiluvchi): tasdiqdan keyin topshirish-qabul dalolatnomasi chop etishga taklif qilinadi (ikkala ism bilan).
function acceptHandover(id) {
  const h = ST.ov.state.handover; if (!h || h.id !== id) return;
  const d0 = num(h.diff), hn = u => (u && h.names && h.names[u]) || nameOf(u);
  // state-2: topshirishda saqlangan hali o'tkazilmagan navbat yozuvlari (topshiruvchi qurilmasidan; g7v-3: shu kungi oldingi smena
  //   topshirishlaridan qolganlari ham — shuning uchun qaysi qurilmada ekani aytilmaydi) — dalolatnomaga o'zgarmay o'tadi
  const np = (h.pendingRefs || []).length;
  if (!confirm(`Smenani qabul qilasizmi?\n\nTopshiruvchi: ${h.fromUid ? hn(h.fromUid) : '—'}\nSanalgan: ${som(h.counted)}\nHisobda: ${som(h.expected)}${num(h.pendingSum) ? '\nHali o‘tkazilmagan navbat yozuvlari: ' + som(h.pendingSum) + (np ? ` (${np} ta)` : '') : ''}\n${d0 === 0 ? 'Farq yo‘q.' : (d0 < 0 ? 'KAMOMAD: ' + som(-d0) : 'ORTIQCHA: ' + som(d0)) + ' — shu kun hujjati topshiruvchi nomidan yoziladi.'}\n\nQabul qilgach kassa siz zimmangizda bo‘ladi.`)) return;
  act('kassa_handover_accept', { p_id: id }, 'Smena qabul qilindi', async r => {
    if (!(r && r.count && r.count.id) || !confirm('Smena topshirish-qabul dalolatnomasi chop etilsinmi?')) return;
    try { const book = await call('kassa_day_book', { p_desk: ST.desk, p_day: r.count.day }); await printCount(book, r.count.id); } catch (e) { C.toast('Chop etib bo‘lmadi: ' + errText(e), true); }
  });
}
function openVerifyForm(day) {
  const dd = (ST.ov.days || []).find(x => String(x.day) === String(day)) || {}, zz = dd.z || {}, zNeed = !!(zz.applies && zz.ok === false);
  // state-2, crit-3: kun hali bog'lanmagan yozuvlar bilan yopilgan (navbat yozuvining kech kirim orderi hali kelmagan; «Қ» blankalari) — izoh majburiy
  const pTxt = pendingText(dd.pendingOpen);
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kunni tekshirish — ${esc(dmy(day))}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small muted">Kassa kitobi varag‘i va unga ilova qilingan kirim / chiqim orderlari qog‘ozda qabul qilinadi va tizimdagi yozuvlar bilan solishtiriladi. Tekshirilgan kun endi o‘zgarmaydi.</div>
      ${pTxt ? `<div class="small" id="kv-pend" style="margin-top:10px;background:#FDECEC;color:#B42318;border-radius:10px;padding:10px 12px"><b>Kun hali o‘tkazilmagan yozuvlar bilan yopilgan:</b> ${esc(pTxt)}. Kassir bilan aniqlang (navbat yuborilmaganmi, «Қ» yozuvlari kiritilganmi — izohida «Қ» raqami); sababini izohda yozing (majburiy).</div>` : ''}
      ${zNeed ? `<div class="small" id="kv-z" style="margin-top:10px;background:#FDECEC;color:#B42318;border-radius:10px;padding:10px 12px"><b>Onlayn kassa Z-hisoboti: ${esc(zText(zz))}.</b>${zz.recorded && !zz.missing ? ` Tizimda: naqd ${esc(som(zz.expCash))} (${esc(String(num(zz.nCash)))} chek), karta ${esc(som(zz.expCard))} (${esc(String(num(zz.nCard)))} ta).` : ''} Qog‘ozdagi Z-hisobot bilan solishtiring; sababini izohda yozing (majburiy).</div>` : ''}
      <label class="small" style="display:flex;gap:8px;align-items:flex-start;margin-top:10px;font-weight:700"><input type="checkbox" id="kv-papers" style="${CHK}"> Qog‘oz hujjatlar va ilovalarni oldim, yozuvlarni tekshirdim</label>
      ${lbl('Izoh', `<input id="kv-note" type="text" maxlength="300" style="${FLD}">`)}</div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kv-save">Tekshirdim</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  $('#kv-save').onclick = async () => { if (!$('#kv-papers').checked) { C.toast('Avval qog‘oz hujjatlar olinganini belgilang', true); return; }
    if (pTxt && $('#kv-note').value.trim().length < 5) { C.toast('Hali o‘tkazilmagan yozuvlar bo‘yicha sababni izohda yozing (kamida 5 belgi)', true); return; }
    if (zNeed && $('#kv-note').value.trim().length < 5) { C.toast('Z-hisobot bo‘yicha sababni izohda yozing (kamida 5 belgi)', true); return; }
    $('#kv-save').disabled = true; await act('kassa_day_verify', { p_desk: ST.desk, p_day: day, p_papers: true, p_note: $('#kv-note').value.trim() }, 'Kun tekshirildi'); const b = $('#kv-save'); if (b) b.disabled = false; };
}
// Kamomad bo'yicha qaror (sec-2, sec-4): kassa egasi va pulni sanagan xodim alohida, shu kungi smena topshirishlar. «Xodim zimmasiga» —
//   FAQAT xodim kartasiga: standart javobgar faqat kassa egasi o'zi sanagan va kassaga boshqa hech kim tegmagan bo'lsa (server — defaultParty);
//   aks holda Direktor kartani tanlaydi — sababi server matnidan (defaultWhy, g6v-3), kassa egasidan boshqa kassa orderi o'tkazgan / bekor
//   qilganlar ismi bilan (others, g6v-1).
async function openDecideForm(id) {
  const x = (ST.ov.shortages || []).find(s => s.id === id); if (!x) return;
  let people = [];
  try { people = await loadPeople(); } catch (_) { people = []; }
  const nm = u => (u && x.names && x.names[u]) || nameOf(u);
  const ST_HO = { pending: 'qabul kutilmoqda', accepted: 'qabul qilingan', cancelled: 'bekor qilingan' };
  const hist = (x.handovers || []).map(h => { const hn = u => (u && h.names && h.names[u]) || nameOf(u);
    return `<div>${esc(hm(h.createdAt))} · ${esc(h.fromUid ? hn(h.fromUid) : '—')} → ${esc(hn(h.toUid))} · sanalgan ${esc(som(h.counted))}${num(h.diff) ? ' · farq ' + esc(sgnS(h.diff)) : ''} · ${esc(ST_HO[h.status] || h.status)}${h.byUid && h.byUid !== h.fromUid ? ' · sanadi: ' + esc(hn(h.byUid)) : ''}${h.cancelReason ? ' — ' + esc(h.cancelReason) : ''}</div>`; }).join('');
  const byOther = !!(x.countedBy && x.countedBy !== x.cashierUid);
  const why = shortageWhy(x), others = (Array.isArray(x.others) ? x.others : []).map(nm);
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kamomad bo‘yicha qaror</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small" style="background:#FDECEC;color:#B42318;border-radius:10px;padding:10px 12px;font-weight:700">${esc(dmy(x.day))} · Ch-${esc(String(x.no))} · ${esc(som(x.amount))} · ${x.kind === 'handover' ? 'smena topshirishda' : 'kunni yopishda'}</div>
      <div class="small" style="margin-top:8px" id="kd-who">Kassa egasi (kassir): <b>${esc(x.cashierUid ? nm(x.cashierUid) : 'aniqlanmagan')}</b>${x.countedBy ? ` · sanadi: <b>${esc(nm(x.countedBy))}</b>${byOther ? ' (kassir o‘rniga, komissiya bilan)' : ''}` : ''}${x.kind === 'handover' && x.toUid ? ` · qabul qildi: <b>${esc(nm(x.toUid))}</b>` : ''}</div>
      ${others.length ? `<div class="small" style="margin-top:4px" id="kd-others">Kassa egasidan boshqa kassa orderi o‘tkazgan yoki bekor qilgan: <b>${esc(others.join(', '))}</b></div>` : ''}
      ${hist ? `<div class="small muted" style="margin-top:6px"><b>Shu kungi smena topshirishlar:</b>${hist}</div>` : ''}
      ${lbl('Qaror', `<select id="kd-dec" style="${FLD}"><option value="employee">Xodim zimmasiga (yozma rozilik yoki to‘liq moddiy javobgarlik bilan)</option><option value="writeoff">Hisobdan chiqarish (aybdor aniqlanmadi)</option></select>`)}
      <div id="kd-emp">${lbl('Javobgar xodim (xodim kartasi)', `<select id="kd-party" style="${FLD}"><option value="">— tanlang —</option>${(people || []).map(p => `<option value="${esc(p.ref)}"${p.ref === x.defaultParty ? ' selected' : ''}>${esc(p.name)}${p.pos ? ' · ' + esc(p.pos) : ''}</option>`).join('')}</select>`)}
        <div class="small muted" style="margin-top:4px">${x.defaultParty ? 'Kassa egasi pulni o‘zi sanagan — uning kartasi tanlangan (boshqasini tanlash mumkin).' : esc(why) + ' — javobgar xodim kartasini tanlang.'}</div></div>
      ${lbl('Asos <span class="muted" style="font-weight:500">— buyruq / tushuntirish xati</span>', `<input id="kd-note" type="text" maxlength="300" style="${FLD}">`)}</div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kd-save">Qarorni saqlash</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const sync = () => { $('#kd-emp').style.display = $('#kd-dec').value === 'employee' ? '' : 'none'; };
  $('#kd-dec').onchange = sync; sync();
  $('#kd-save').onclick = async () => { const n = $('#kd-note').value.trim(), dec = $('#kd-dec').value, party = $('#kd-party').value;
    if (n.length < 5) { C.toast('Qaror asosini yozing', true); return; }
    if (dec === 'employee' && !party) { C.toast('Javobgar xodim kartasini tanlang', true); return; }
    const args = { p_doc_id: id, p_decision: dec, p_note: n }; if (dec === 'employee') args.p_party = party;
    $('#kd-save').disabled = true; await act('kassa_shortage_decide', args, 'Qaror saqlandi'); const b = $('#kd-save'); if (b) b.disabled = false; };
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
// Qayta ishga tushirish (ishga-tushirish §9; ui-5): to'xtatilgan kassada komissiya pulni sanaydi; sanalgan summa qayta ochilgan birinchi
//   kun boshi bo'ladi, oxirgi kun oxiri bilan farqi — texnik dalolatnoma (D-, OP-23). Kassirga kamomad / ortiqcha yozilmaydi. Keyin —
//   «⚙ Sozlamalar»da ishga tushadigan kun = shu kun (server boshqa sanani qabul qilmaydi).
function openRestartForm() {
  const s = ST.ov.state, ld = s.lastDay || {}, rs = (s.desk && s.desk.restart) || null, X = num(ld.closing);
  const next = ld.day ? new Date(Date.parse(String(ld.day) + 'T00:00:00Z') + 864e5).toISOString().slice(0, 10) : '';
  const minDay = [String(s.today || ''), next].sort().pop();
  $('#modal').innerHTML = `<div class="modal-h"><h3>Qayta ishga tushirish</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small muted">To‘xtatilgan kassa yangi komissiya sanashi bilan qayta ishga tushadi. Sanalgan summa qayta ochilgan birinchi kun boshi bo‘ladi; tizimdagi oxirgi qoldiq bilan farqi — to‘xtatilgan davrdagi naqd harakat: texnik dalolatnoma (D-) bilan yoziladi, kassirga kamomad yoki ortiqcha bo‘lmaydi. Buxgalter farqni nazorat ro‘yxati bo‘yicha solishtiradi. Qayta ishga tushirish kuni — to‘xtatilgan davrdagi oxirgi naqd yozuvdan keyin (bugun kassa hujjatisiz naqd yozuv bo‘lgan bo‘lsa — ertangi kun); sanashdan keyin qayta ishga tushguncha naqd yozuv bo‘lsa — qayta sanang.</div>
      <div class="small" style="margin-top:8px;background:#eef3f1;border-radius:10px;padding:8px 10px">Oxirgi kassa kuni: <b>${esc(dmy(ld.day))}</b> · tizimdagi kun oxiri <b>${esc(som(X))}</b></div>
      <div class="grid2">${lbl('Sanalgan summa (so‘m)', `<input id="kr-amt" type="text" inputmode="numeric" placeholder="0" value="${rs ? esc(String(num(rs.amount)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')) : ''}" style="${FLD}">`)}${lbl('Qayta ishga tushirish kuni', `<input id="kr-day" type="date" min="${esc(minDay)}" value="${esc(rs ? rs.day : minDay)}" style="${FLD}">`)}</div>
      <div class="small" id="kr-diff" style="margin-top:6px"></div>
      ${commissionFields().replace('Komissiya (kassir o‘rniga yopilganda kamida 2 kishi)', 'Komissiya a’zolari')}
      ${lbl('Izoh', `<input id="kr-note" type="text" maxlength="300" placeholder="masalan: sanash dalolatnomasi № 2" style="${FLD}">`)}</div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kr-save">Saqlash</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal; fmtInput($('#kr-amt'));
  const diffTxt = () => { const a = digits($('#kr-amt').value); const el = $('#kr-diff'); if (!el) return;
    if (a === '') { el.innerHTML = ''; return; }
    const d = num(a) - X;
    el.innerHTML = d === 0 ? '<span class="muted">Farq yo‘q — dalolatnoma yozilmaydi.</span>'
      : `<b style="color:${d < 0 ? '#B42318' : '#B54708'}">Farq: ${esc(sgnSom(d))}</b> <span class="muted">— texnik dalolatnoma (${d > 0 ? 'Dt 5010 Kt 0000' : 'Dt 0000 Kt 5010'}): to‘xtatilgan davrdagi naqd ${d > 0 ? 'kirim' : 'chiqim'} ko‘p bo‘lgan</span>`; };
  $('#kr-amt').addEventListener('input', diffTxt); diffTxt();
  $('#kr-save').onclick = async () => {
    const a = digits($('#kr-amt').value), day = $('#kr-day').value;
    if (a === '') { C.toast('Komissiya sanagan summani kiriting (pul bo‘lmasa — 0)', true); return; }
    if (!day) { C.toast('Qayta ishga tushirish kunini tanlang', true); return; }
    const d = num(a) - X;
    if (!confirm(`Qayta ishga tushirish qoldig‘i saqlansinmi?\n\nKun: ${dmy(day)} · sanalgan ${som(num(a))} · tizimda ${som(X)}\n${d === 0 ? 'Farq yo‘q.' : 'Farq ' + sgnSom(d) + ' — texnik dalolatnoma yoziladi.'}\n\nKeyin «⚙ Sozlamalar»da ishga tushadigan kunni ${dmy(day)} ga qo‘ying.`)) return;
    $('#kr-save').disabled = true;
    await act('kassa_opening_set', { p: { desk: ST.desk, amount: num(a), startDay: day, note: $('#kr-note').value.trim(), commission: commissionRead() } },
      `Qayta ishga tushirish qoldig‘i saqlandi — endi «⚙ Sozlamalar»da ishga tushadigan kunni ${dmy(day)} ga qo‘ying`);
    const b = $('#kr-save'); if (b) b.disabled = false;
  };
}
// Imzo egalari (chop etiladigan hujjatlardagi «Rahbar» / «Bosh buxgalter» F.I.Sh.): 1-ro'yxat — rahbariyat, 2-ro'yxat — buxgalteriya / moliya.
function sigRows() {
  const a = (ST.refs && ST.refs.signatories) || [];
  if (!a.length) return '<div class="small muted" style="margin-top:6px">Hali kiritilmagan — hujjatlarda F.I.Sh. qo‘lda yoziladi.</div>';
  return a.map(x => `<div class="small" style="display:flex;gap:8px;align-items:center;justify-content:space-between;margin-top:6px;padding:8px 10px;border:1px solid var(--border);border-radius:10px">
    <span><b>${esc(x.fullName || '')}</b>${x.title ? ' — ' + esc(x.title) : ''} <span class="muted">· ${Number(x.list) === 1 ? '1-ro‘yxat' : '2-ro‘yxat'}${x.uid ? ' · hisobi bog‘langan' : ''}</span></span>
    <button type="button" class="btn ghost2" data-sdel="${esc(x.id)}" style="flex:none">O‘chirish</button></div>`).join('');
}
function openSettings() {
  const o = ST.refs.org || {};
  const v = k => esc(o[k] == null ? '' : String(o[k]));
  const nv = k => esc(num(o[k]) ? String(num(o[k])).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') : '');
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kassa sozlamalari</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      ${lbl('Tashkilot nomi (hujjatlarda)', `<input id="kx-name" type="text" maxlength="300" value="${v('nameUz')}" style="${FLD}">`, ';margin-top:0')}
      ${lbl('Tashkilot nomi ruscha hujjatlarda <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<input id="kx-name-ru" type="text" maxlength="300" value="${v('nameRu')}" style="${FLD}">`)}
      <div class="grid2">${lbl('STIR', `<input id="kx-stir" type="text" inputmode="numeric" maxlength="14" value="${v('stir')}" style="${FLD}">`)}${lbl('Joy (shahar / tuman)', `<input id="kx-place" type="text" maxlength="200" value="${v('place')}" style="${FLD}">`)}</div>
      ${lbl('Chop etish tili', `<select id="kx-lang" style="${FLD}">${[['uz-cyrl', 'O‘zbek (kirill)'], ['uz-latn', 'O‘zbek (lotin)'], ['ru', 'Rus']].map(x => `<option value="${x[0]}"${o.printLang === x[0] ? ' selected' : ''}>${x[1]}</option>`).join('')}</select>`)}
      <div class="grid2">${lbl('T1 — shundan katta chiqimga Direktor tasdig‘i (0 — har doim)', `<input id="kx-t1" type="text" inputmode="numeric" value="${nv('t1')}" placeholder="0" style="${FLD}">`)}${lbl('L1 — asos hujjatisiz naqd xarid chegarasi (0 — mumkin emas)', `<input id="kx-l1" type="text" inputmode="numeric" value="${nv('l1')}" placeholder="0" style="${FLD}">`)}</div>
      <div class="grid2">${lbl('Kassa limiti (0 — belgilanmagan)', `<input id="kx-limit" type="text" inputmode="numeric" value="${nv('cashLimit')}" placeholder="0" style="${FLD}">`)}${lbl('Kassa ishga tushadigan kun', `<input id="kx-live" type="date" value="${v('kassaGoLive')}" style="${FLD}">`)}</div>
      ${lbl('Yuridik shaxsga (yetkazib beruvchi / tashkilot) kassadan naqd to‘lov — Direktor tasdig‘isiz chegara (0 — har doim Direktor)', `<input id="kx-orgmax" type="text" inputmode="numeric" value="${esc(num((o.extra || {}).orgCashMax) ? String(num(o.extra.orgCashMax)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') : '')}" placeholder="0" style="${FLD}">`)}
      <div class="small muted" style="margin-top:4px">Yuridik shaxslar bilan hisob-kitob asosan bank orqali (yoki hisobdor shaxs — avans hisoboti bilan); chegarani buxgalter hisob siyosatida tasdiqlaydi.</div>
      <div class="small muted" style="margin-top:8px">«Ishga tushadigan kun»dan boshlab har naqd o‘quv to‘lovi kassa kirim orderi bilan yoziladi: fiskal chek raqami majburiy bo‘ladi, naqd pulni faqat kassir qabul qiladi, kecha yopilmagan bo‘lsa to‘lov qabul qilinmaydi. Bo‘sh qoldirilsa — hozirgidek. Kassa ishlagandan keyin sanani bo‘shatish yoki surish — kassani <b>to‘xtatish</b> (ishga-tushirish §9: ochiq kun, qurilma navbatida qolgan yozuvlar bilan yopilgan oxirgi kun va pul berilmagan so‘rovlar bo‘lmasligi kerak); qayta ishga tushirish — komissiya sanashi bilan («Qayta ishga tushirish»).</div>
      <div class="small" style="font-weight:700;margin-top:16px">Imzo egalari (chop etiladigan hujjatlarda)</div>
      <div class="small muted" style="margin-top:4px">1-ro‘yxat — rahbar; 2-ro‘yxat — bosh buxgalter / moliya. Ro‘yxatda bitta shaxs bo‘lsa — hujjatga o‘zi yoziladi; bir nechta bo‘lsa — hujjatni tizimda tasdiqlagan shaxs (hisobi bog‘langan bo‘lsa — shu yerdagi to‘liq F.I.Sh. bilan). Qo‘shish va o‘chirish darhol saqlanadi.</div>
      <div id="kx-sigs">${sigRows()}</div>
      <div class="grid2">${lbl('Ro‘yxat', `<select id="kx-slist" style="${FLD}"><option value="1">1-ro‘yxat — rahbar</option><option value="2">2-ro‘yxat — bosh buxgalter / moliya</option></select>`)}${lbl('Lavozimi', `<input id="kx-stitle" type="text" maxlength="200" placeholder="masalan: Direktor" style="${FLD}">`)}</div>
      <div class="grid2">${lbl('F.I.Sh. (to‘liq)', `<input id="kx-sname" type="text" maxlength="200" style="${FLD}">`)}${lbl('Tizimdagi hisobi <span class="muted" style="font-weight:500">— ixtiyoriy</span>', `<select id="kx-suid" style="${FLD}"><option value="">—</option>${((ST.refs && ST.refs.signers) || []).map(u => `<option value="${esc(u.uid)}">${esc(u.name)}</option>`).join('')}</select>`)}</div>
      <div style="margin-top:8px"><button type="button" class="btn ghost2" id="kx-sadd">+ Imzo egasini qo‘shish</button></div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Bekor</button><button type="button" class="btn gold" id="kx-save">Saqlash</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  ['#kx-t1', '#kx-l1', '#kx-limit', '#kx-orgmax'].forEach(s => fmtInput($(s)));
  const sigSave = (x, active) => call('fin_signatory_save', { p_id: x.id || null, p_list: Number(x.list), p_uid: x.uid || null, p_title: x.title || '', p_full_name: x.fullName, p_active: active });
  const drawSigs = () => {
    const box = $('#kx-sigs'); if (!box) return;
    box.innerHTML = sigRows();
    box.querySelectorAll('[data-sdel]').forEach(b => b.onclick = async () => {
      const x = ((ST.refs && ST.refs.signatories) || []).find(y => y.id === b.dataset.sdel);
      if (!x || !confirm(`${x.fullName} imzo egalari ro‘yxatidan olib tashlansinmi?`)) return;
      b.disabled = true;
      try { await sigSave(x, false); await loadRefs(true); drawSigs(); C.toast('Ro‘yxatdan olib tashlandi ✓'); }
      catch (e) { b.disabled = false; C.toast(errText(e), true); }
    });
  };
  drawSigs();
  $('#kx-sadd').onclick = async () => {
    const x = { list: $('#kx-slist').value, title: $('#kx-stitle').value.trim(), fullName: $('#kx-sname').value.trim(), uid: $('#kx-suid').value || null };
    if (x.fullName.length < 5) { C.toast('F.I.Sh. ni to‘liq yozing', true); $('#kx-sname').focus(); return; }
    if (((ST.refs && ST.refs.signatories) || []).some(y => Number(y.list) === Number(x.list) && String(y.fullName || '').toLowerCase() === x.fullName.toLowerCase())) { C.toast('Bu shaxs shu ro‘yxatda bor', true); return; }
    $('#kx-sadd').disabled = true;
    try { await sigSave(x, true); await loadRefs(true); drawSigs(); $('#kx-stitle').value = ''; $('#kx-sname').value = ''; $('#kx-suid').value = ''; C.toast('Imzo egasi qo‘shildi ✓'); }
    catch (e) { C.toast(errText(e), true); }
    $('#kx-sadd').disabled = false;
  };
  $('#kx-save').onclick = async () => {
    const live = $('#kx-live').value || null;
    // ui-5: kelgan sanani bo'shatish / surish — kassani to'xtatish (alohida, oqibatlari yozilgan tasdiq); to'xtatilgan kassada — qayta
    //   ishga tushirish kuni. Holat — asosiy kassaniki (sahifada sinov kassasi tanlangan bo'lishi mumkin); server baribir tekshiradi.
    if (live !== (o.kassaGoLive || null)) {
      let sm = null; try { sm = await call('kassa_state', { p_desk: 'main' }); } catch (_) { sm = null; }
      const g = goLiveConfirm(o.kassaGoLive || null, live, sm ? sm.today : (ST.ov.state && ST.ov.state.today), sm ? sm.desk : null,
        sm && !sm.openDay ? sm.lastDay : null);
      if (g.kind === 'block') { C.toast(g.text, true); return; }
      if (g.text && !confirm(g.text)) return;
    }
    $('#kx-save').disabled = true;
    try { await call('fin_org_set', { p: { nameUz: $('#kx-name').value.trim(), nameRu: $('#kx-name-ru').value.trim(), stir: digits($('#kx-stir').value), place: $('#kx-place').value.trim(), printLang: $('#kx-lang').value,
        t1: num(digits($('#kx-t1').value)), l1: num(digits($('#kx-l1').value)), cashLimit: num(digits($('#kx-limit').value)), orgCashMax: num(digits($('#kx-orgmax').value)), kassaGoLive: live } });
      await loadRefs(true); C.closeModal(); C.toast('Sozlamalar saqlandi ✓'); await reload(); if (C.onChange) C.onChange(); }
    catch (e) { $('#kx-save').disabled = false; C.toast(errText(e), true); }
  };
}

// ---------------------------------------------------------------- davr surati va qulfi (F1.16)
// Surat — davr oxiridagi holat (qarzdorlik, avanslar, kassa qoldig'i, to'lanmagan ish haqi …): o'zgarmaydi, xeshi bilan saqlanadi.
//   Qulf — shu sanagacha pul yozuvlari kiritilmaydi va o'zgartirilmaydi. Olish va qulfni surish — faqat Direktor; ko'rish — 2-ro'yxat ham.
const SNAP_KIND = { year_end: 'Yil yakuni', month_end: 'Oy yakuni', manual: 'Qo‘lda' };
const prevMonthEnd = today => { const d = new Date(String(today).slice(0, 7) + '-01T12:00:00Z'); d.setUTCDate(0); return d.toISOString().slice(0, 10); };
function saveJson(name, obj) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([JSON.stringify(obj, null, 1)], { type: 'application/json' }));
  a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
}
async function openPeriodForm() {
  const m = me();
  $('#modal').innerHTML = `<div class="modal-h"><h3>Davr surati va qulfi</h3><button class="x" id="m-x">×</button></div><div class="modal-b"><div class="loading">Yuklanmoqda…</div></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal;
  let L;
  try { L = await call('fin_snapshots_list'); } catch (e) { C.toast(errText(e), true); C.closeModal(); return; }
  const items = L.items || [], today = L.today || (ST.ov && ST.ov.state && ST.ov.state.today) || '';
  const def = prevMonthEnd(today);
  const tot = t => { t = t || {}; return `qarzdorlik ${som(t.receivable)} · avans va oldindan to‘lov ${som(num(t.credit) + num(t.prepaid))} · kassa ${som(t.cash)}${num(t.salaryPayable) ? ' · to‘lanmagan ish haqi ' + som(t.salaryPayable) : ''}${num(t.unmatched) ? ' · biriktirilmagan ' + som(t.unmatched) : ''}`; };
  const rows = items.map(x => `<div data-snap="${esc(x.id)}" style="border:1px solid var(--border-2);border-radius:10px;padding:10px 12px;margin-top:8px">
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap"><div><b>${esc(dmy(x.asOf))}</b> <span class="small muted">${esc(SNAP_KIND[x.kind] || x.kind)}${num(x.version) > 1 ? ' · ' + esc(String(x.version)) + '-surat' : ''}</span>${x.late ? ' ' + chip('kechikib olingan', '#B54708', '#FEF3E2') : ''}</div>
        <span style="display:flex;gap:6px"><button class="btn sm" data-snap-chk="${esc(x.id)}">Tekshirish</button><button class="btn sm" data-snap-dl="${esc(x.id)}" title="To‘liq suratni fayl sifatida saqlash">⬇ JSON</button></span></div>
      <div class="small muted" style="margin-top:4px">olindi: ${esc(dmy(String(x.takenAt).slice(0, 10)))} ${esc(hm(x.takenAt))}${x.byName ? ' · ' + esc(x.byName) : ''}${x.note ? ' · ' + esc(x.note) : ''}</div>
      <div class="small" style="margin-top:4px">${esc(tot(x.totals))}</div>
      <div class="small muted" style="margin-top:2px;overflow-wrap:anywhere" title="${esc(x.hash)}">xesh: ${esc(String(x.hash).slice(0, 16))}…</div></div>`).join('');
  $('#modal').innerHTML = `<div class="modal-h"><h3>Davr surati va qulfi</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      <div class="small" id="kpd-lock" style="background:#eef3f1;border-radius:10px;padding:10px 12px;font-weight:600">${L.lockedThrough ? `Davr <b>${esc(dmy(L.lockedThrough))}</b> gacha yopilgan — shu sanagacha to‘lov, xarajat, maosh va avans yozuvlari kiritilmaydi va o‘zgartirilmaydi.` : 'Davr yopilmagan: orqaga sanali yozuvlar cheklanmagan (to‘lovda — 31 kungacha).'}</div>
      ${m.director ? `<div style="margin-top:12px"><b>Yangi surat</b>
        <div class="small muted" style="margin-top:2px">Davr oxiridagi holat saqlanadi: o‘quvchilar bo‘yicha qarzdorlik va avanslar, biriktirilmagan tushumlar, kassa qoldig‘i, to‘lanmagan ish haqi. Surat keyin o‘zgarmaydi. Yil yakuni — 31-dekabr holati, yanvar yozuvlari boshlanguncha olinadi.</div>
        <div class="grid2">${lbl('Qaysi kun oxiri holati', `<input id="kpd-day" type="date" value="${esc(def)}" max="${esc(today)}" style="${FLD}">`)}${lbl('Izoh', `<input id="kpd-note" type="text" maxlength="300" placeholder="masalan: 2026-yil yakuni" style="${FLD}">`)}</div>
        <label class="small" style="display:flex;gap:8px;align-items:flex-start;margin-top:8px;font-weight:700"><input type="checkbox" id="kpd-lockit" checked style="${CHK}"> Shu sanagacha davrni yopish (orqaga sanali yozuvlar taqiqlanadi)</label>
        <div style="margin-top:10px"><button type="button" class="btn gold" id="kpd-take">Surat olish</button></div>
        <details style="margin-top:12px"><summary class="small" style="cursor:pointer;font-weight:700">Davr qulfini o‘zgartirish</summary>
          <div class="small muted" style="margin-top:4px">Oldinga surish — erkin. Orqaga surish yoki olib tashlash (yopilgan davrni qayta ochish) — faqat sabab bilan; o‘zgarishlar tarixiga yoziladi.</div>
          <div class="grid2">${lbl('Shu sanagacha yopiq (bo‘sh — qulf yo‘q)', `<input id="kpd-through" type="date" value="${esc(L.lockedThrough || '')}" max="${esc(today)}" style="${FLD}">`)}${lbl('Sabab', `<input id="kpd-reason" type="text" maxlength="300" style="${FLD}">`)}</div>
          <div style="margin-top:8px"><button type="button" class="btn ghost2" id="kpd-setlock">Qulfni saqlash</button></div></details></div>` : ''}
      <div style="margin-top:14px"><b>Olingan suratlar</b></div>
      ${items.length ? rows : '<div class="small muted" style="margin-top:6px">Hali surat olinmagan.</div>'}
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button></div>`;
  $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const day = $('#kpd-day'), lk = $('#kpd-lockit');
  if (day && lk) { const upd = () => { const can = day.value && day.value < today; lk.disabled = !can; if (!can) lk.checked = false; }; day.onchange = upd; upd(); }
  const take = $('#kpd-take');
  if (take) take.onclick = async () => {
    if (!day.value) { C.toast('Sanani tanlang', true); return; }
    if (!confirm(`${dmy(day.value)} kuni oxiridagi holat surati olinsinmi?${lk.checked ? `\n\nDavr ${dmy(day.value)} gacha YOPILADI: shu sanagacha to‘lov, xarajat, maosh va avans yozuvlari kiritilmaydi va o‘zgartirilmaydi.` : ''}`)) return;
    take.disabled = true;
    try { const r = await call('fin_snapshot_take', { p: { asOf: day.value, note: $('#kpd-note').value.trim(), lock: !!lk.checked } });
      C.toast(`Surat olindi ✓${r.late ? ' (kechikib — keyingi kunlar harakati aralashgan bo‘lishi mumkin)' : ''}`); await reload().catch(() => {}); if (C.onChange) C.onChange(); await openPeriodForm(); }
    catch (e) { take.disabled = false; C.toast(errText(e), true); }
  };
  const sl = $('#kpd-setlock');
  if (sl) sl.onclick = async () => {
    const v = $('#kpd-through').value || null, why = $('#kpd-reason').value.trim();
    if (!confirm(v ? `Davr ${dmy(v)} gacha yopilsinmi?` : 'Davr qulfi olib tashlansinmi?')) return;
    sl.disabled = true;
    try { await call('fin_period_lock', { p_through: v, p_note: why }); C.toast('Davr qulfi saqlandi ✓'); await reload().catch(() => {}); if (C.onChange) C.onChange(); await openPeriodForm(); }
    catch (e) { sl.disabled = false; C.toast(errText(e), true); }
  };
  $('#modal').querySelectorAll('[data-snap-chk]').forEach(b => b.onclick = async () => { b.disabled = true;
    try { const g = await call('fin_snapshot_get', { p_id: b.dataset.snapChk }); C.toast(g.hashOk ? 'Surat butun: xesh mos ✓' : 'DIQQAT: surat xeshi mos emas — administratorga xabar bering', !g.hashOk); }
    catch (e) { C.toast(errText(e), true); } b.disabled = false; });
  $('#modal').querySelectorAll('[data-snap-dl]').forEach(b => b.onclick = async () => { b.disabled = true;
    try { const g = await call('fin_snapshot_get', { p_id: b.dataset.snapDl }); saveJson(`davr-surati-${g.asOf}-${g.version}${g.masked ? '-ismsiz' : ''}.json`, { id: g.id, kind: g.kind, asOf: g.asOf, version: g.version, takenAt: g.takenAt, hash: g.hash, masked: !!g.masked, data: g.data });
      if (g.masked) C.toast('Saqlandi: ismsiz (ID bilan) — ismli nusxa faqat Direktorda'); }
    catch (e) { C.toast(errText(e), true); } b.disabled = false; });
}

// ---------------------------------------------------------------- chop etish (fin-print.js — kerak bo'lganda yuklanadi)
// Har chop etish serverda qayd qilinadi (kassa_print_mark): birinchisi — asl nusxa, keyingilari — «НУСХА» belgisi bilan.
//   «Avvalgisi qog'ozga chiqmadi» tanlansa — asl nusxa qayta chiqadi va buxgalterning nazorat ro'yxatida ko'rinadi.
const printCtx = (names, isTest, mk) => ({ org: (ST.refs && ST.refs.org) || {}, signatories: (ST.refs && ST.refs.signatories) || [], rules: (ST.refs && ST.refs.rules) || [], names: names || {}, isTest: !!isTest,
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
// Kassirning kunlik hisoboti (RP-02): raqamli hujjat emas — jurnalga yozilmaydi; ochiq kunda «QORALAMA» belgisi bilan.
//   Ma'lumot KO-4 bilan bir manbadan (kassa_day_book) — jamlari bir xil.
async function printReport(day, bookOrNull) {
  try {
    const [pm, wm, book] = await Promise.all([C.finMod('fin-print'), C.finMod('fin-words'), bookOrNull || call('kassa_day_book', { p_desk: ST.desk, p_day: day }), loadRefs()]);
    if (!book || !book.day) { C.toast('Bu kunda kassa varag‘i yo‘q', true); return; }
    C.printHTML(pm.reportHtml(book, printCtx(book.names, book.isTest, null), wm));
  } catch (e) { C.toast('Chop etib bo‘lmadi: ' + errText(e), true); }
}
// ---------------------------------------------------------------- KO-3: kirim va chiqim orderlari jurnali (F1.22)
//   Davr (oy yoki chorak) bo'yicha barcha orderlar, bekor qilinganlari bilan; chop etish (KO-3 shakli) va Excel (buxgalter dasturi uchun).
async function openJournal() {
  const today = String(ST.ov.state.today || ''), m0 = today.slice(0, 8) + '01', m = me();
  const canX = !!(m.director || m.list2);   // Excel eksporti (FD-28): kassirga yo'q — jurnalni chop etadi; 2-ro'yxatga — ismsiz
  $('#modal').innerHTML = `<div class="modal-h"><h3>KO-3 — kassa orderlari jurnali</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small muted">Kirim va chiqim kassa orderlari (bekor qilinganlari raqami bilan) — oy yoki chorak bo‘yicha. Chop etilib, bosh buxgalter imzolaydi; Excel — buxgalter dasturi uchun${canX && !m.director ? ' (ismsiz: shaxslar ID bilan; ismli nusxa — Direktorda)' : ''}.</div>
      <div class="grid2">${lbl('Davr boshi', `<input id="kj-from" type="date" value="${esc(m0)}" max="${esc(today)}" style="${FLD}">`)}${lbl('Davr oxiri', `<input id="kj-to" type="date" value="${esc(today)}" max="${esc(today)}" style="${FLD}">`)}</div>
      <div style="margin-top:8px"><button type="button" class="btn ghost2" id="kj-load">Ko‘rsatish</button></div>
      <div id="kj-body" style="margin-top:10px"></div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button>${canX ? '<button type="button" class="btn ghost2" id="kj-xlsx" disabled>⬇ Excel (XLSX)</button>' : ''}<button type="button" class="btn gold" id="kj-print" disabled>🖨 KO-3</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  let J = null;
  const load = async () => {
    const from = $('#kj-from').value, to = $('#kj-to').value;
    if (!from || !to || from > to) { C.toast('Davrni to‘g‘ri tanlang (boshi oxiridan keyin bo‘lmasin)', true); return; }
    const xb = () => $('#kj-xlsx');
    $('#kj-body').innerHTML = '<div class="loading">Yuklanmoqda…</div>'; $('#kj-print').disabled = true; if (xb()) xb().disabled = true; J = null;
    try { J = await call('kassa_journal', { p_desk: ST.desk, p_from: from, p_to: to }); }
    catch (e) { $('#kj-body').innerHTML = ''; C.toast(errText(e), true); return; }
    const t = J.totals || {}, docs = J.docs || [];
    const row = x => { const isIn = x.form === 'KO1', v = x.status === 'void', a = v ? '<s>' + esc(som(x.amount)) + '</s>' : esc(som(x.amount));
      return `<tr${v ? ' style="opacity:.55"' : ''}><td data-label="Sana">${esc(dmy(x.businessDay))}</td><td data-label="№"><b>${isIn ? 'K' : 'Ch'}-${esc(String(x.no))}</b></td>
        <td data-label="Operatsiya">${esc(opName(x.op))}<div class="small muted">${esc(x.partyName || '')}${v ? ' — bekor qilingan' + (x.voidReason ? ': ' + esc(x.voidReason) : '') : ''}</div></td>
        <td data-label="Kirim" style="text-align:right;white-space:nowrap">${isIn ? a : ''}</td><td data-label="Chiqim" style="text-align:right;white-space:nowrap">${isIn ? '' : a}</td></tr>`; };
    $('#kj-body').innerHTML = `<div class="small" id="kj-sum" style="background:#eef3f1;border-radius:10px;padding:10px 12px">Davr boshi <b>${esc(som(J.opening))}</b> · kirim <b>${esc(som(t.in))}</b> (${esc(String(num(t.nIn)))} ta) · chiqim <b>${esc(som(t.out))}</b> (${esc(String(num(t.nOut)))} ta)${restartAdjTxt(J.restartAdj)} · davr oxiri <b>${esc(som(J.closing))}</b>${num(t.voids) ? ` · bekor qilingan: ${esc(String(num(t.voids)))} ta` : ''}${J.balanced === false ? ' · <b style="color:#B42318">qoldiqlar mos emas — Direktorga xabar bering</b>' : ''}</div>
      ${docs.length ? `<div class="tablewrap" style="max-height:340px;overflow:auto;margin-top:8px"><table id="kj-tbl"><thead><tr><th>Sana</th><th>№</th><th>Operatsiya / tomon</th><th style="text-align:right">Kirim</th><th style="text-align:right">Chiqim</th></tr></thead><tbody>${docs.map(row).join('')}</tbody></table></div>` : '<div class="empty" style="margin-top:8px">Bu davrda order yo‘q.</div>'}`;
    $('#kj-print').disabled = false; if (xb()) xb().disabled = false;
  };
  $('#kj-load').onclick = load;
  $('#kj-print').onclick = async () => {
    if (!J) return;
    try { const [pm, wm] = await Promise.all([C.finMod('fin-print'), C.finMod('fin-words'), loadRefs()]); C.printHTML(pm.journalHtml(J, printCtx({}, J.desk && J.desk.isTest, null), wm)); }
    catch (e) { C.toast('Chop etib bo‘lmadi: ' + errText(e), true); }
  };
  if (canX) $('#kj-xlsx').onclick = async () => {
    if (!J) return;
    const X = window.XLSX;
    if (!X || !X.utils || !X.writeFile) { C.toast('Excel kutubxonasi hali yuklanmadi — sahifani yangilab qayta urining', true); return; }
    try {
      // eksport ma'lumoti serverdan alohida (FD-28: 2-ro'yxatga — ismsiz, Direktorga — to'liq)
      const [pm, E] = await Promise.all([C.finMod('fin-print'), call('kassa_journal_export', { p_desk: ST.desk, p_from: J.from, p_to: J.to }), loadRefs()]);
      const sh = pm.journalSheet(E, printCtx({}, false, null));
      const ws = X.utils.aoa_to_sheet(sh.rows); ws['!cols'] = sh.cols;
      const wb = X.utils.book_new(); X.utils.book_append_sheet(wb, ws, sh.name);
      X.writeFile(wb, `KO-3_${(E.desk && E.desk.id) || 'kassa'}_${E.from}_${E.to}${E.masked ? '-ismsiz' : ''}.xlsx`);
      if (E.masked) C.toast('Saqlandi: ismsiz (ID bilan) — ismli nusxa faqat Direktorda');
    } catch (e) { C.toast('Excel fayl tuzilmadi: ' + errText(e), true); }
  };
  await load();
}
// ---------------------------------------------------------------- RP-08: oylik statiya matritsasi (F1.22) va oylik kassa to'plami
//   Ekranda va chop etishda — haftalar bo'yicha; Excel (oylik to'plam: KO-3, statiyalar kunlar bo'yicha, kassa kunlari, hisobdorlar) —
//   faqat Moliya menejeri, buxgalter va Direktor (FD-28: 2-ro'yxatga ismsiz).
const MONTHS_UZ = ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'];
async function openMatrix() {
  const today = String(ST.ov.state.today || ''), m = me(), canX = !!(m.director || m.list2);
  const opts = []; let y = +today.slice(0, 4), mo = +today.slice(5, 7);
  for (let i = 0; i < 24 && y > 2000; i++) { opts.push(`${y}-${String(mo).padStart(2, '0')}`); if (--mo < 1) { mo = 12; y--; } }
  $('#modal').innerHTML = `<div class="modal-h"><h3>Statiyalar — oylik matritsa</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small muted">Kassadagi naqd kirim va chiqim statiyalar bo‘yicha, haftalar kesimida (Excel’da — kunlar bo‘yicha). Ichki o‘tkazma (bank) daromad ham, xarajat ham emas.${canX ? ` «Oylik to‘plam» — buxgalter uchun bitta Excel: KO-3, statiyalar, kassa kunlari, hisobdorlar${m.director ? '' : ' (ismsiz: shaxslar ID bilan; to‘liq nusxa — Direktorda)'}.` : ''}</div>
      <div class="grid2">${lbl('Oy', `<select id="km-month" style="${FLD}">${opts.map(v => `<option value="${esc(v)}">${esc(MONTHS_UZ[+v.slice(5, 7) - 1] + ' ' + v.slice(0, 4))}</option>`).join('')}</select>`)}
        <div style="display:flex;align-items:flex-end"><button type="button" class="btn ghost2" id="km-load">Ko‘rsatish</button></div></div>
      <div id="km-body" style="margin-top:10px"></div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button>${canX ? '<button type="button" class="btn ghost2" id="km-pack" disabled>⬇ Oylik to‘plam (Excel)</button>' : ''}<button type="button" class="btn gold" id="km-print" disabled>🖨 Chop etish</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  let M = null;
  const pb = () => $('#km-pack');
  const load = async () => {
    const month = $('#km-month').value;
    $('#km-body').innerHTML = '<div class="loading">Yuklanmoqda…</div>'; $('#km-print').disabled = true; if (pb()) pb().disabled = true; M = null;
    try { M = await call('kassa_matrix', { p_desk: ST.desk, p_month: month }); }
    catch (e) { $('#km-body').innerHTML = ''; C.toast(errText(e), true); return; }
    const n = num(M.nDays), wk = []; for (let a = 1; a <= n; a += 7) wk.push([a, Math.min(a + 6, n)]);
    const sumW = (arr, a, b) => { let v = 0; for (let i = a - 1; i < b; i++) v += num(arr && arr[i]); return Math.round(v * 100) / 100; };
    // ekranda — «statiya | oy jami», haftalar bo'yicha taqsimot nom ostida (to'liq jadval — chop etishda va Excel'da)
    const amt = v => esc(som(v).replace(' so‘m', ''));
    const weeks = arr => wk.map(([a, b]) => [a, b, sumW(arr, a, b)]).filter(w => w[2]).map(([a, b, v]) => `${a}–${b}: ${amt(v)}`).join(' · ');
    const sec = (form, title, totLabel, dayArr, tot) => {
      const rs = (M.rows || []).filter(x => x.form === form);
      return `<tr><td colspan="2" style="font-weight:700;background:#eef3f1">${esc(title)}</td></tr>`
        + rs.map(x => `<tr><td data-label="Statiya" style="white-space:normal;overflow-wrap:anywhere">${esc(x.nameUz || x.articleId || '(statiyasiz)')}<div class="small muted">${esc(x.articleId || '')}${x.transfer ? ' · ichki o‘tkazma' : ''}</div><div class="small muted">${weeks(x.byDay)}</div></td>
            <td data-label="Oy jami" style="text-align:right;white-space:nowrap;vertical-align:top"><b>${amt(x.total)}</b></td></tr>`).join('')
        + `<tr style="font-weight:700"><td data-label="" style="white-space:normal">${esc(totLabel)}<div class="small muted" style="font-weight:400">${weeks(dayArr)}</div></td><td data-label="Oy jami" style="text-align:right;white-space:nowrap;vertical-align:top">${esc(som(tot))}</td></tr>`;
    };
    const exIn = num(M.in) - num(M.transferIn), exOut = num(M.out) - num(M.transferOut);
    $('#km-body').innerHTML = `<div class="small" id="km-sum" style="background:#eef3f1;border-radius:10px;padding:10px 12px">Oy boshi <b>${esc(som(M.opening))}</b> · kirim <b>${esc(som(M.in))}</b> · chiqim <b>${esc(som(M.out))}</b>${restartAdjTxt(M.restartAdj)} · oy oxiri <b>${esc(som(M.closing))}</b><br>Ichki o‘tkazmalarsiz (bank): kirim <b>${esc(som(exIn))}</b>, chiqim <b>${esc(som(exOut))}</b>${M.balanced === false ? ' · <b style="color:#B42318">qoldiqlar mos emas — Direktorga xabar bering</b>' : ''}</div>
      ${(M.rows || []).length ? `<div class="tablewrap" style="max-height:360px;overflow:auto;margin-top:8px"><table id="km-tbl"><thead><tr><th style="white-space:normal">Statiya · haftalar (kunlar)</th><th style="text-align:right">Oy jami</th></tr></thead>
        <tbody>${sec('KO1', 'Kirim', 'Jami kirim', M.dayIn, M.in)}${sec('KO2', 'Chiqim', 'Jami chiqim', M.dayOut, M.out)}</tbody></table></div>` : '<div class="empty" style="margin-top:8px">Bu oyda o‘tkazilgan order yo‘q.</div>'}`;
    $('#km-print').disabled = false; if (pb()) pb().disabled = false;
  };
  $('#km-load').onclick = load; $('#km-month').onchange = load;
  $('#km-print').onclick = async () => {
    if (!M) return;
    try { const [pm, wm] = await Promise.all([C.finMod('fin-print'), C.finMod('fin-words'), loadRefs()]); C.printHTML(pm.matrixHtml(M, printCtx({}, M.desk && M.desk.isTest, null), wm)); }
    catch (e) { C.toast('Chop etib bo‘lmadi: ' + errText(e), true); }
  };
  if (canX) pb().onclick = async () => {
    if (!M) return;
    const X = window.XLSX;
    if (!X || !X.utils || !X.writeFile) { C.toast('Excel kutubxonasi hali yuklanmadi — sahifani yangilab qayta urining', true); return; }
    try {
      const [pm, P] = await Promise.all([C.finMod('fin-print'), call('kassa_month_pack', { p_desk: ST.desk, p_month: M.month }), loadRefs()]);
      const wb = X.utils.book_new();
      pm.packSheets(P, printCtx({}, false, null)).forEach(sh => { const ws = X.utils.aoa_to_sheet(sh.rows); ws['!cols'] = sh.cols; X.utils.book_append_sheet(wb, ws, sh.name); });
      X.writeFile(wb, `Kassa_${(P.desk && P.desk.id) || 'kassa'}_${P.month}${P.masked ? '-ismsiz' : ''}.xlsx`);
      C.toast(P.masked ? 'Saqlandi: ismsiz (ID bilan) — ismli nusxa faqat Direktorda' : 'Saqlandi: oylik kassa to‘plami');
    } catch (e) { C.toast('Excel fayl tuzilmadi: ' + errText(e), true); }
  };
  await load();
}
// ---------------------------------------------------------------- RP-22: haftalik ko'rsatkichlar (F1.25) — Direktor va 2-ro'yxat
//   Bir hafta uchun qatorlar (sof funksiya — sinovda ham ishlatiladi). EX-49 maqsadi — ≤ 2 % (reja, 4.4).
export function kpiRows(w) {
  w = w || {};
  const r = [], add = (key, label, level, value) => r.push({ key, label, level, value });
  const d = num(w.days), cl = num(w.closed), ao = w.accOverdue || {};
  add('days', 'Kassa kunlari', d ? 'ok' : 'info', d ? `${d} ta (yopilgan ${cl})` : 'yo‘q');
  add('onTime', 'O‘sha kuni yopilgan', !cl ? 'info' : num(w.onTime) === cl ? 'ok' : 'warn', cl ? `${num(w.onTime)} / ${cl}` : '–');
  add('unverified', 'Tekshirilmagan', num(w.unverified) ? 'warn' : 'ok', num(w.unverified) ? `${num(w.unverified)} ta` : 'yo‘q');
  // acc-6: kunni yopish va smena topshirishdagi farqlar birga (har sanash alohida); shundan smena topshirishdagilari soni
  add('diffs', 'Sanash farqi bo‘lgan kunlar', num(w.diffDays) ? 'warn' : 'ok',
    num(w.diffDays) ? `${num(w.diffDays)} ta` + (num(w.shortage) ? ` · kamomad ${som(w.shortage)}` : '') + (num(w.surplus) ? ` · ortiqcha ${som(w.surplus)}` : '')
      + (num(w.handoverDiffs) ? ` (smena topshirishda: ${num(w.handoverDiffs)} ta)` : '') : 'yo‘q');
  add('ex49', '«Boshqa xarajatlar» (EX-49) ulushi', w.ex49Share == null ? 'info' : num(w.ex49Share) > 2 ? 'warn' : 'ok',
    w.ex49Share == null ? 'naqd xarajat yo‘q' : `${String(w.ex49Share).replace('.', ',')}% (${som(w.ex49)} / ${som(w.exTotal)}; maqsad ≤ 2%)`);
  add('accOverdue', 'Muddati o‘tgan avans (hafta oxirida)', num(ao.n) ? 'warn' : 'ok', num(ao.n) ? `${num(ao.n)} ta · ${som(ao.sum)}` : 'yo‘q');
  add('reopened', 'Qayta ochilgan kunlar', num(w.reopened) ? 'warn' : 'ok', num(w.reopened) ? `${num(w.reopened)} ta` : 'yo‘q');
  add('voids', 'Bekor qilingan hujjatlar', num(w.voids) ? 'info' : 'ok', num(w.voids) ? `${num(w.voids)} ta` : 'yo‘q');
  return r;
}
async function openKpi() {
  $('#modal').innerHTML = `<div class="modal-h"><h3>Haftalik ko‘rsatkichlar (KPI)</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b"><div class="small muted">Kassa intizomi haftalar bo‘yicha (dushanba — yakshanba; joriy hafta — bugungacha): kun o‘sha kuni yopildimi, tekshirildimi, sanashda farq, «Boshqa xarajatlar» (EX-49) ulushi va hafta oxirida avans hisoboti muddati o‘tgan hisobdorlar. O‘tgan hafta — dushanba kungi Telegram hisobotida ham.</div>
      <div id="kk-body" style="margin-top:10px"><div class="loading">Yuklanmoqda…</div></div></div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button></div>`;
  C.openModal(); $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  let K;
  try { K = await call('kassa_kpi', { p_desk: ST.desk, p_weeks: 8 }); }
  catch (e) { $('#kk-body').innerHTML = ''; C.toast(errText(e), true); return; }
  const dm = d => dmy(d).slice(0, 5);
  const tr = (w, i) => `<tr data-week="${esc(String(w.from))}"><td data-label="Hafta" style="vertical-align:top"><b>${esc(dm(w.from))}–${esc(dm(w.to))}</b>${i === 0 ? '<div class="small muted">joriy hafta</div>' : ''}</td>
    <td data-label="Ko‘rsatkichlar" style="white-space:normal">${kpiRows(w).map(x => `<div class="small" style="${x.level === 'warn' ? 'color:#B54708;font-weight:700' : ''}">${esc(x.label)}: ${esc(x.value)}</div>`).join('')}</td></tr>`;
  $('#kk-body').innerHTML = `<div class="tablewrap" style="max-height:420px;overflow:auto"><table id="kk-tbl"><thead><tr><th>Hafta</th><th style="white-space:normal">Ko‘rsatkichlar</th></tr></thead><tbody>${(K.weeks || []).map(tr).join('')}</tbody></table></div>`;
}
// «To'lov» oynasidan: naqd o'quv to'lovining kirim orderini chop etish (hujjat id bo'yicha).
export async function printDocById(ctx, docId, back) { C = ctx; await printDoc(docId, back); }

// ---------------------------------------------------------------- nazorat ro'yxati (RP-06)
// Server faktlarni beradi (kassa_checks) — baho va matn shu yerda. Daraja: bad — darhol hal qilinadi; warn — ko'rib chiqiladi;
//   info — ma'lumot; ok — joyida. Muddatli ko'rsatkichlar — oxirgi 30 kun.
const SERIES = { KO1: 'kirim orderlari', KO2: 'chiqim orderlari', ACT: 'dalolatnomalar', OFS: 'o‘zaro hisob dalolatnomalari', ADV: 'avans hisobotlari' };
const LVL = { bad: ['muhim', '#B42318', '#FDECEC'], warn: ['diqqat', '#B54708', '#FEF3E2'], info: ['ma’lumot', '#175CD3', '#E8F1FD'], ok: ['joyida', '#157347', '#E7F6EC'] };
export function controlRows(c) {
  c = c || {};
  const rows = [], add = (key, label, level, value, hint) => rows.push({ key, label, level, value, hint: hint || '' });
  const cnt = (v, unit) => `${num(v)} ${unit || 'ta'}`, days = a => (a || []).slice(0, 6).map(dmy).join(', ') + ((a || []).length > 6 ? ' …' : '');
  const gaps = c.gaps || [];
  add('gaps', 'Hujjat raqamlari uzluksizligi', gaps.length ? 'bad' : 'ok',
    gaps.length ? gaps.map(g => `${g.year}: ${(g.problems || []).map(x => SERIES[x.series] || x.series).join(', ')}`).join('; ') + ' — bo‘shliq yoki takror' : 'uzluksiz',
    'Hisoblagich = hujjatlar soni = eng katta raqam');
  add('staleOpenDay', 'Yopilmagan o‘tgan kun', c.staleOpenDay ? 'bad' : 'ok', c.staleOpenDay ? dmy(c.staleOpenDay) : 'yo‘q', 'Kecha yopilmaguncha bugun hujjat yozilmaydi');
  const uv = c.unverifiedDays || [];
  add('unverified', 'Tekshirilmagan (yopilgan) kunlar', uv.length > 3 ? 'bad' : uv.length ? 'warn' : 'ok', uv.length ? `${uv.length} ta: ${days(uv)}` : 'yo‘q', 'Qog‘oz varaq va orderlar olinib, «Tekshirish» bosiladi');
  const sh = c.undecidedShortages || [];
  add('shortages', 'Qarori kutilayotgan kamomad', sh.length ? 'bad' : 'ok', sh.length ? `${sh.length} ta · ${som(sh.reduce((a, x) => a + num(x.amount), 0))}` : 'yo‘q', 'Direktor qarori: xodim zimmasiga yoki hisobdan chiqarish');
  const df = c.diffs30 || [];
  add('diffs', 'Sanash farqlari', df.length ? 'warn' : 'ok', df.length ? df.slice(0, 6).map(x => `${dmy(x.day)}: ${diffText(x.diff, x.handover)}`).join('; ') + (df.length > 6 ? ' …' : '') : 'yo‘q',
    'Kunni yopish va smena topshirishdagi kamomad / ortiqcha (har sanash alohida)');   // acc-6
  add('voids', 'Bekor qilingan hujjatlar', num(c.voids30) ? 'info' : 'ok', num(c.voids30) ? cnt(c.voids30) : 'yo‘q', 'Sababi har hujjatda yozilgan; raqami saqlanadi');
  add('reopens', 'Kunni qayta ochishlar', num(c.reopens30) ? 'warn' : 'ok', num(c.reopens30) ? cnt(c.reopens30, 'marta') : 'yo‘q', 'Faqat Direktor, sabab bilan');
  add('waiting', 'Tasdiq kutayotgan so‘rovlar', num(c.waitingApproval) ? 'info' : 'ok', num(c.waitingApproval) ? cnt(c.waitingApproval) : 'yo‘q', 'Chiqim faqat tasdiqdan keyin beriladi');
  add('unpaid', 'Tasdiqlangan, pul hali berilmagan', num(c.approvedUnpaid) ? 'info' : 'ok', num(c.approvedUnpaid) ? cnt(c.approvedUnpaid) : 'yo‘q', '');
  add('staleRefunds', 'Kechikkan qaytarishlar', num(c.staleRefunds) ? 'bad' : 'ok', num(c.staleRefunds) ? cnt(c.staleRefunds) : 'yo‘q', 'Direktor tasdiqlagan qaytarish 1 kundan ortiq berilmagan');
  add('fiscal', 'Fiskal cheksiz kirimlar', num(c.fiscalExempt30) ? 'warn' : 'ok', num(c.fiscalExempt30) ? cnt(c.fiscalExempt30) : 'yo‘q', 'Direktor istisnosi bilan o‘tkazilgan');
  if (!c.isTest) {
    const zr = c.zreport || [];
    add('zreport', 'Onlayn kassa Z-hisoboti', zr.length ? 'bad' : 'ok',
      zr.length ? zr.slice(0, 6).map(x => `${dmy(x.day)}: ${zText(Object.assign({ applies: true, needed: true, ok: false }, x))}`).join('; ') + (zr.length > 6 ? ' …' : '') : 'tekshirilmagan kunlarda mos',
      'Kun yopishda Z dagi naqd va karta sotuvi kiritiladi; tizim fiskal chekli kirim orderlari va terminal to‘lovlari bilan solishtiradi. Farq bo‘lsa — buxgalter izoh bilan tekshiradi');
    // crit-4: Z-hisobot kun yopilgandan keyin kiritilgan / tuzatilgan kunlar (kim, necha marta) — kunni o'sha xodim tekshira olmaydi
    const zc = c.zChanged30 || [];
    add('zChanged', 'Z-hisobot kun yopilgandan keyin o‘zgartirilgan', zc.length ? 'warn' : 'ok',
      zc.length ? zc.slice(0, 6).map(x => `${dmy(x.day)}: ${num(x.n)} marta, oxirgisi — ${x.byName || '—'}${x.status === 'verified' ? ' (tekshirilgan)' : ''}`).join('; ') + (zc.length > 6 ? ' …' : '') : 'yo‘q',
      'Yopilgandan keyin kiritilgan yoki tuzatilgan Z qog‘ozdagi Z bilan solishtiriladi (farqni yashirish mumkin); kunni Z ni o‘zgartirgan xodim tekshira olmaydi');
  }
  const oc = c.orgCash30 || {};
  add('orgCash', 'Yuridik shaxslarga kassadan naqd to‘lov', num(oc.count) ? 'warn' : 'ok', num(oc.count) ? `${cnt(oc.count)} · ${som(oc.sum)}` : 'yo‘q',
    'Yetkazib beruvchi / tashkilot bilan hisob-kitob asosan bankdan; kassadan berilganlari — Direktor tasdig‘i bilan, buxgalter ko‘rib chiqadi');
  // sec-3: kontragent turi o'zgarishlari (30 kun; kim, qachon, eski → yangi) va turi tasdiqlanmagan «jismoniy shaxs» / «boshqa» lar —
  //   «acts»: buxgalter / Direktor sahifada «✓ Tasdiqlash» tugmasi bilan tasdiqlaydi
  const ck = c.cpKinds30 || [], cu = c.cpUnconfirmed || [], kd = k => k ? (CP_KIND[k] || k) : 'yangi';
  add('cpKinds', 'Kontragent turi', ck.length || cu.length ? 'info' : 'ok',
    [ck.length ? ck.slice(0, 6).map(x => `${x.name || '—'}: ${kd(x.from)} → ${kd(x.to)} (${x.byName || 'tizim'}, ${dmy(tkDate(x.at))}${!x.confirmed && (x.to === 'person' || x.to === 'other') ? ', tasdiqlanmagan' : ''})`).join('; ') + (ck.length > 6 ? ' …' : '') : '',
     cu.length ? `turi tasdiqlanmagan: ${cnt(cu.length)} — ${cu.slice(0, 6).map(x => x.name).join(', ')}${cu.length > 6 ? ' …' : ''}` : ''].filter(Boolean).join('; ') || 'yo‘q',
    '«Jismoniy shaxs» / «Boshqa» turini buxgalter yoki Direktor tasdiqlaydi; tasdiqlanguncha kontragent yuridik shaxs hisoblanadi (kassadan naqd to‘lovga Direktor tasdig‘i)');
  rows[rows.length - 1].acts = cu.map(x => ({ id: x.id, kind: x.kind, name: x.name }));
  add('other', '«Boshqa» tomonli hujjatlar', num(c.otherParties30) ? 'info' : 'ok', num(c.otherParties30) ? cnt(c.otherParties30) : 'yo‘q', 'Imkon bo‘lsa kontragent ma’lumotnomasidan tanlanadi');
  const lateTxt = [num(c.late30) ? `kech yozilgan hujjat: ${cnt(c.late30)}` : '', num(c.pendingDays30) ? `oflayn yozuv bilan yopilgan kun: ${cnt(c.pendingDays30)}` : ''].filter(Boolean).join('; ');
  add('late', 'Oflayn va kech kiritilgan yozuvlar', lateTxt ? 'info' : 'ok', lateTxt || 'yo‘q', 'Pul olingan kun yopilgani uchun keyingi kunga yozilgan');
  // state-2, crit-3: kunni yopishda e'lon qilingan, hali bog'lanmagan yozuvlar — qurilma navbati yozuvi 2 kundan (48 soat) beri kelmagan;
  //   «Қ» blankalari — kun tekshirilguncha
  const po = c.pendingOpen || [];
  add('pending', 'Hali kelmagan «hali o‘tkazilmagan» yozuvlar', po.length ? 'warn' : 'ok',
    po.length ? po.slice(0, 6).map(x => `${dmy(x.day)}${x.status === 'verified' ? ' (tekshirilgan)' : ''}: ${pendingText(x)}`).join('; ') + (po.length > 6 ? ' …' : '') : 'yo‘q',
    'Kunni yopishda e’lon qilingan qurilma navbati yozuvining kech kirim orderi 2 kun (48 soat) ichida kelmagan — navbat yo‘qolgan, o‘chirilgan yoki yozuv o‘ylab topilgan bo‘lishi mumkin (kassir bilan aniqlang); «Қ» blankalari — yozuvlar «Қ» raqami bilan kiritilib, kun izoh bilan tekshirilguncha');
  add('reissues', 'Asl nusxani qayta chop etish', num(c.reissues30) ? 'warn' : 'ok', num(c.reissues30) ? cnt(c.reissues30, 'marta') : 'yo‘q', '«Avvalgisi qog‘ozga chiqmadi» deb qayta chiqarilgan');
  add('gateOff', 'Vedomost tasdig‘isiz naqd maosh', num(c.salaryGateOff30) ? 'warn' : 'ok', num(c.salaryGateOff30) ? cnt(c.salaryGateOff30) : 'yo‘q', 'Direktor ruxsati bilan berilgan');
  const ub = c.unprintedBooks30 || [];
  add('unprinted', 'Kassa kitobi varag‘i chop etilmagan kunlar', ub.length ? 'warn' : 'ok', ub.length ? `${ub.length} ta: ${days(ub)}` : 'yo‘q', 'KO-4 ikki nusxada chop etilib imzolanadi');
  const lim = c.limit || {};
  add('limit', 'Kassa limiti', !lim.set ? 'info' : lim.exceeded ? 'warn' : num(lim.days30) ? 'info' : 'ok',
    !lim.set ? 'belgilanmagan' : lim.exceeded ? `qoldiq ${som(lim.balance)} — limit ${som(lim.cashLimit)}dan oshgan` : `limit ${som(lim.cashLimit)}` + (num(lim.days30) ? ` · ${cnt(lim.days30, 'kun')} limitdan oshib yopilgan` : ' — oshmagan'),
    'Ortiqchasi bankka topshiriladi');
  const rc = c.reconcile || {};
  if (!c.isTest) {
    if (!rc.live) add('reconcile', 'Moslik: kassa hujjatlari ↔ pul yozuvlari', 'info', 'kassa hali ishga tushirilmagan', 'Ishga tushgan kundan har kuni tekshiriladi');
    else {
      const p1 = rc.p1 || {}, p4 = rc.p4 || {}, p5 = rc.p5 || {}, p8 = rc.p8 || {};
      const bad = [num(p1.pay) ? `kirim orderisiz naqd o‘quv to‘lovi: ${cnt(p1.pay)} (${som(p1.paySum)})` : '', num(p1.doc) ? `to‘lov yozuvisiz kirim orderi: ${cnt(p1.doc)}` : '',
        num(p4.row) ? `chiqim orderisiz naqd xarajat: ${cnt(p4.row)}` : '', num(p4.doc) ? `«Buxgalteriya»ga ko‘chmagan xarajat orderi: ${cnt(p4.doc)}` : '',
        num(p5.row) ? `chiqim orderisiz naqd maosh / avans: ${cnt(p5.row)}` : '', num(p5.doc) ? `yozuvsiz maosh / avans orderi: ${cnt(p5.doc)}` : '',
        num(p5.ofs) ? `o‘zaro hisob (dalolatnoma ↔ maosh ↔ o‘quv to‘lovi) mos emas: ${cnt(p5.ofs)}` : '',
        num(p5.ret) ? `xodim qaytargan pul (kirim orderi ↔ avans / maosh yozuvi) mos emas: ${cnt(p5.ret)}` : '',
        num(p4.adv) ? `avans hisoboti ↔ «Buxgalteriya» xarajatlari mos emas: ${cnt(p4.adv)}` : '',
        num(p8.row) ? `chiqim orderisiz naqd qaytarish: ${cnt(p8.row)}` : '', num(p8.doc) ? `yozuvsiz qaytarish orderi: ${cnt(p8.doc)}` : ''].filter(Boolean);
      add('reconcile', 'Moslik: kassa hujjatlari ↔ pul yozuvlari', num(rc.total) ? 'bad' : 'ok', num(rc.total) ? bad.join('; ') : 'hammasi mos',
        'Naqd o‘quv to‘lovi, xarajat, maosh / avans, qaytarish — har biri o‘z orderi bilan; o‘zaro hisob va avans hisoboti — dalolatnomasi bilan');
    }
  }
  // manfiy qoldiq (qaytim yoki hisobot berilgan avansdan ko'p) — xato yozuv izi: yashirilmaydi, qizil (acc-3, state-5)
  const ac = c.accountable || [], acNeg = ac.filter(x => num(x.balance) < 0), acPos = ac.filter(x => num(x.balance) >= 0);
  add('accountable', 'Hisobdorlardagi pul', acNeg.length ? 'bad' : acPos.some(x => x.overdue) ? 'warn' : acPos.length ? 'info' : 'ok',
    ac.length ? acNeg.map(x => `${x.name || '—'}: ${som(x.balance)} — manfiy qoldiq (qaytim yoki hisobot berilgan avansdan ko‘p), tekshiring`)
      .concat(acPos.map(x => `${x.name || '—'}: ${som(x.balance)} (${dmy(x.since)} dan, ${num(x.workDays)} ish kuni${x.overdue ? ' — muddati o‘tgan' : ''})`)).join('; ') : 'yo‘q',
    'Berilgan − naqd qaytarilgan − avans hisobotlari («Avans hisoboti» tugmasi); hisobot muddati — 3 ish kuni');
  // xodimlar zimmasidagi kamomad (4730, acc-4): Direktor qarori − kassaga qoplangani; xodim kartasiga bog'lanmagan kassir qarori — alohida belgi
  const dm = c.damage || [], dmNeg = dm.filter(x => num(x.balance) < 0);
  add('damage', 'Xodimlar zimmasidagi kamomad', dmNeg.length ? 'bad' : dm.length ? 'info' : 'ok',
    dm.length ? dm.map(x => `${x.name || '—'}: ${som(x.balance)}${num(x.balance) < 0 ? ' — qoplangani qarordan ko‘p, tekshiring' : ` (${dmy(x.since)} dan${num(x.repaid) ? `, qoplangan ${som(x.repaid)}` : ''})`}${x.linked === false ? ' — xodim kartasiga bog‘lanmagan' : ''}`).join('; ') : 'yo‘q',
    'Direktor qarori bilan xodim zimmasiga yozilgan kamomad: kassaga «Kamomadni qoplash (xodim)» kirim orderi bilan qoplanadi yoki buxgalter ish haqidan ushlaydi');
  // sec-4: xodim kartasiga bog'lanmagan kassa hisoblari — ism foydalanuvchining o'zi yozgani (o'zgartira oladi), kamomad qarorida standart javobgar yo'q
  const ul = c.unlinkedUsers || [], RL = { treasurer: 'g‘aznachi', finance_mgr: 'moliya menejeri', accountant: 'buxgalter', kassir: 'kassir' };
  add('unlinked', 'Xodim kartasiga bog‘lanmagan kassa hisoblari', ul.length ? 'warn' : 'ok',
    ul.length ? ul.map(x => `${x.name || x.uid} (${[RL[x.role] || x.role, x.kassir && x.role !== 'kassir' ? 'kassir' : ''].filter(Boolean).join(' + ')})`).join(', ') : 'yo‘q',
    'Kassa hujjatlaridagi ism xodim kartasidan (HR) olinadi; bog‘lanmagan hisobda — foydalanuvchi o‘zi yozgan ism. Direktor «Foydalanuvchilar» → «Tahrirlash»da hisobni HR yozuviga bog‘laydi');
  const ho = c.handover || {};
  add('handover', 'Rahbar / ta’sischiga berilgan pul', num(ho.earlierCount) ? 'warn' : num(ho.monthCount) ? 'info' : 'ok',
    [num(ho.monthCount) ? `shu oyda: ${cnt(ho.monthCount)} · ${som(ho.monthSum)}` : '', num(ho.earlierCount) ? `oldingi oylarda: ${cnt(ho.earlierCount)} · ${som(ho.earlierSum)} — tasniflanganini tekshiring` : ''].filter(Boolean).join('; ') || 'yo‘q',
    'Buxgalter shu oy ichida tasniflaydi (dividend, ish haqi …) — xarajat emas');
  if (!c.isTest) {
    // crit-1: ishga tushish kunidan oldingi sana bilan, keyin kiritilgan kassa hujjatisiz naqd yozuvlar (Direktor — kech kelgan qog'oz)
    //   chegara — kassa BIRINCHI ishga tushgan kun (g4v-3: qayta ishga tushirilgandan keyin ham); to'xtatilgan davr sanalari — pastdagi qatorda,
    //   kassa ishlagan kunlarniki — «Moslik» qatorida
    const pl = c.preLive || {}, pli = pl.items || [];
    add('preLive', 'Kassa ishga tushishidan oldingi naqd yozuvlar (keyin kiritilgan)', pli.length ? 'info' : 'ok',
      pli.length ? pli.map(x => `${CASH_KIND[x.kind] || x.kind}: ${cnt(x.n)} · ${som(x.sum)}`).join('; ') : 'yo‘q',
      `Sanasi kassa birinchi ishga tushgan kundan${pl.goLive ? ' (' + dmy(pl.goLive) + ')' : ''} oldin, kassa hujjatisiz — boshlang‘ich qoldiq sanashi bilan solishtiriladi (o‘sha pul sanashga kirgan bo‘lishi va bugungi sana bilan ikkinchi marta kiritilmagan bo‘lishi kerak)`
      + ((c.restarts || []).length ? '; to‘xtatilgan davr sanalari — «Kassani to‘xtatish va qayta ishga tushirish» qatorida' : ''));
    // ishga-tushirish §9: to'xtatilgan kassa; qayta ishga tushirishlar — farq dalolatnomasi va to'xtatilgan davrdagi kassa hujjatisiz naqd harakat
    //   (sanasi shu davrda — rows; shu davrda orqa sana bilan kiritilgan — backdated); izohlanmagan farq bo'lsa — sariq
    const pz = c.paused, rsl = c.restarts || [], rowTxt = (o, t) => `${t}: kirim ${som((o || {}).in)}, chiqim ${som((o || {}).out)} (${cnt((o || {}).n)})`;
    add('restart', 'Kassani to‘xtatish va qayta ishga tushirish', pz || rsl.some(r => num(r.unexplained)) ? 'warn' : rsl.length ? 'info' : 'ok',
      [pz ? `kassa to‘xtatilgan: ${dmy(pz.day)} dan (oxirgi kassa kuni ${dmy(pz.lastDay)}) — naqd pul kassa hujjatisiz yozilmoqda` : '']
        .concat(rsl.map(r => `${dmy(r.startDay)} dan qayta ishga tushirildi${r.started ? '' : ' (hali boshlanmagan)'}: tizimda ${som(r.prevClosing)}, sanaldi ${som(r.counted)}, farq ${sgnSom(r.delta)}${r.docNo ? ' (D-' + r.docNo + ')' : ''}`
          + `; ${rowTxt(r.rows, 'to‘xtatilgan davrdagi kassa hujjatisiz naqd')}`
          + (num((r.backdated || {}).n) ? `; ${rowTxt(r.backdated, 'shu davrda orqa sana bilan kiritilgan')}` : '')
          + (num(r.unexplained) ? `; izohlanmagan farq ${sgnSom(r.unexplained)} — «Қ» jurnali bilan tekshiring` : '')))
        .filter(Boolean).join('; ') || 'yo‘q',
      'To‘xtatilgan davrda naqd pul kassa hujjatisiz yoziladi; qayta ishga tushirishda sanalgan summa bilan oxirgi qoldiq farqi texnik dalolatnoma (0000) — buxgalter uni shu davrdagi kirim − chiqim bilan solishtiradi (izohlanmagan farq qolmasligi kerak: aks holda u kamomad yoki ortiqcha)');
  }
  return rows;
}
const CASH_KIND = { tuition: 'o‘quv to‘lovi', expense: 'xarajat', salary: 'maosh', advance: 'avans', refund: 'qaytarish' };
function controlHtml(c, stale) {   // stale — oldingi yuklashdagi ma'lumot (yangisi kelguncha ko'rsatiladi)
  const rows = controlRows(c), ord = { bad: 0, warn: 1, info: 2, ok: 3 };
  const att = rows.filter(r => r.level === 'bad' || r.level === 'warn'), rest = rows.filter(r => r.level === 'info'), ok = rows.filter(r => r.level === 'ok');
  // kontragent turini tasdiqlash (sec-3) — buxgalter va Direktor (kassa_state → me.kindConfirm); server ham tekshiradi
  const acts = r => (r.acts || []).length && me().kindConfirm ? `<div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:6px">${r.acts.map(a => `<button type="button" class="btn sm" data-cpok="${esc(a.id)}" data-cpkind="${esc(a.kind)}" data-cpname="${esc(a.name)}" title="Turini tasdiqlash: ${esc(CP_KIND[a.kind] || a.kind)}">✓ ${esc(a.name)} — ${esc(CP_KIND[a.kind] || a.kind)}</button>`).join('')}</div>` : '';
  const tr = r => `<tr data-ctl="${esc(r.key)}" data-level="${esc(r.level)}"><td data-label="Tekshiruv"><div><b>${esc(r.label)}</b>${r.hint ? `<div class="small muted">${esc(r.hint)}</div>` : ''}</div></td>
    <td data-label="Holat">${chip(LVL[r.level][0], LVL[r.level][1], LVL[r.level][2])}</td><td data-label="Natija">${esc(r.value)}${acts(r)}</td></tr>`;
  const tbl = xs => `<div class="tablewrap"><table><thead><tr><th>Tekshiruv</th><th>Holat</th><th>Natija</th></tr></thead><tbody>${xs.slice().sort((a, b) => ord[a.level] - ord[b.level]).map(tr).join('')}</tbody></table></div>`;
  const nBad = att.filter(r => r.level === 'bad').length;
  const head = att.length ? chip(`E’tibor talab qiladi: ${att.length} ta`, nBad ? '#B42318' : '#B54708', nBad ? '#FDECEC' : '#FEF3E2') : chip('Hammasi joyida', '#157347', '#E7F6EC');
  return `<div class="card" style="padding:14px 18px;margin-bottom:14px" id="ks-ctl-card"${stale ? ' data-stale="1"' : ''}><div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap"><b>Nazorat ro‘yxati</b>${head}</div>
    <div class="small muted" style="margin:2px 0 8px">Moliya menejeri va buxgalter har kuni ko‘rib chiqadi. Muddatli ko‘rsatkichlar — oxirgi 30 kun${c && c.isTest ? ' · SINOV kassasi' : ''}.</div>
    ${att.length || rest.length ? tbl(att.concat(rest)) : ''}
    <details style="margin-top:${att.length || rest.length ? 10 : 0}px"><summary class="small" style="cursor:pointer;font-weight:700">Joyida bo‘lgan tekshiruvlar (${ok.length} ta)</summary><div style="margin-top:6px">${ok.length ? tbl(ok) : '<div class="small muted">—</div>'}</div></details></div>`;
}

// ---------------------------------------------------------------- kun varag'i: hujjatlar, sanashlar, jurnal (tekshiruvchi uchun)
const CNT_LBL = { close: 'Kun yopish sanashi', handover: 'Smena topshirish-qabul', opening: 'Boshlang‘ich qoldiq', monthly: 'Oylik sanash', yearly: 'Yillik sanash', surprise: 'To‘satdan sanash' };
const EV_LBL = { open: 'Kun ochildi', close: 'Kun yopildi', verify: 'Tekshirildi', reopen: 'Qayta ochildi', handover: 'Smena topshirildi', opening: 'Boshlang‘ich qoldiq', decision: 'Kamomad qarori', zreport: 'Z-hisobot',
  resplit: 'Qaytarish hisobvarag‘i (4010 / 6310) qayta aniqlandi' };
// smena topshirish bosqichlari (state-6; eski yozuvda bosqich yo'q — bir bosqichli topshirish)
const HO_STEP = { pending: 'Smena topshirish yozildi (qabul kutilmoqda)', accept: 'Smena qabul qilindi', cancel: 'Smena topshirish bekor qilindi', reject: 'Smena qabul qilinmadi (rad etildi)' };
const HO_ST = { pending: 'qabul kutilmoqda', accepted: 'qabul qilingan', cancelled: 'bekor qilingan' };
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
      <td data-label="Holat">${v ? stChip('void') : '<span class="small muted">' + (x.isSystem ? 'tizim' : esc(x.postedByName || nm(x.postedBy))) + '</span>'}${num(x.prints) ? `<div class="small muted">chop etilgan: ${esc(String(x.prints))}</div>` : ''}</td>
      <td data-label=""><button class="btn sm" data-dprint="${esc(x.id)}" title="Orderni chop etish">🖨</button></td></tr>`; }).join('');
  // sanashlar: ismlar — sanash paytidagi (sec-4); kassa egasi va sanagan xodim alohida (sec-2); smenada — topshirdi → qabul qildi
  const cn = (c, u) => (u && c.names && c.names[u]) || nm(u);
  const cnts = (book.counts || []).map(c => `<div style="display:flex;justify-content:space-between;gap:8px;align-items:center;padding:6px 0;border-bottom:1px solid var(--border-2)">
      <div class="small"><b>${esc(CNT_LBL[c.kind] || c.kind)}</b> · ${esc(hm(c.at))} · sanalgan ${esc(som(c.counted))}${num(c.diff) ? ` · <span style="color:${num(c.diff) < 0 ? '#B42318' : '#B54708'};font-weight:700">farq ${num(c.diff) > 0 ? '+' : ''}${esc(som(c.diff))}</span>` : ' · farq yo‘q'}<div class="muted">${c.kind === 'handover'
        ? esc(cn(c, c.fromUid || c.byUid)) + (c.toUid ? ' → ' + esc(cn(c, c.toUid)) : '') + (c.byUid && c.fromUid && c.byUid !== c.fromUid ? ' · sanadi: ' + esc(cn(c, c.byUid)) : '')
        : esc(cn(c, c.byUid)) + (c.cashierUid && c.cashierUid !== c.byUid ? ' · kassa egasi: ' + esc(cn(c, c.cashierUid)) + ' (kassir o‘rniga)' : '')}</div></div>
      <button class="btn sm" data-cprint="${esc(c.id)}">🖨 Dalolatnoma</button></div>`).join('');
  // qabul qilinmagan (kutilayotgan, bekor qilingan / rad etilgan) smena topshirishlar — dalolatnomasiz, ma'lumot uchun
  const hos = (book.handovers || []).filter(h => h.status !== 'accepted').map(h => { const hn = u => (u && h.names && h.names[u]) || nm(u);
    return `<div class="small muted" style="padding:4px 0">Smena topshirish · ${esc(hm(h.createdAt))} · ${esc(h.fromUid ? hn(h.fromUid) : '—')} → ${esc(hn(h.toUid))} · sanalgan ${esc(som(h.counted))} · ${esc(HO_ST[h.status] || h.status)}${h.cancelReason ? ' — ' + esc(h.cancelReason) : ''}</div>`; }).join('');
  const evs = (book.events || []).map(e => `<div class="small muted">${esc(hm(e.at))} · ${esc((e.kind === 'handover' && HO_STEP[(e.data || {}).step]) || EV_LBL[e.kind] || e.kind)} · ${esc(nm(e.byUid))}${e.reason ? ' — ' + esc(e.reason) : ''}</div>`).join('');
  // «kimdan / kimga qancha» — tomon KALITI bo'yicha (server guruhlaydi); tizim hujjati (sanash farqi) — alohida qator
  const PT = { student: 'o‘quvchi', employee: 'xodim', counterparty: 'kontragent', bank: 'bank', founder: 'ta’sischi', other: 'boshqa', system: 'tizim', none: '' };
  const pName = x => x.partyType === 'system' ? (x.ops || []).map(opName).join(', ') : (x.name || '—');
  const partyTbl = (form, who) => { const xs = (book.byParty || []).filter(x => x.form === form); if (!xs.length) return '';
    return `<div class="small" style="font-weight:700;margin:8px 0 4px">${who} — ${esc(som(xs.reduce((a, x) => a + num(x.amount), 0)))}</div><div class="tablewrap"><table data-party="${form}"><thead><tr><th>${who}</th><th>Turi</th><th style="text-align:right">Hujjat</th><th style="text-align:right">Summa</th></tr></thead><tbody>${xs.map(x => `<tr>
      <td data-label="${who}"><div>${esc(pName(x))}${x.partyType === 'student' && x.partyId ? ` <span class="small muted">${esc(x.partyId)}</span>` : ''}</div></td><td data-label="Turi"><span class="small muted">${esc(PT[x.partyType] || x.partyType || '')}</span></td>
      <td data-label="Hujjat" style="text-align:right">${esc(String(num(x.count)))}</td><td data-label="Summa" style="text-align:right;white-space:nowrap"><b>${esc(som(x.amount))}</b></td></tr>`).join('')}</tbody></table></div>`; };
  const tr = book.transfers || {};
  const trTxt = (num(tr.inCount) || num(tr.outCount)) ? `<div class="small muted" style="margin-top:6px">Ichki o‘tkazmalar (daromad ham, xarajat ham emas): bankdan olindi ${esc(som(tr.inAmount))} · bankka topshirildi ${esc(som(tr.outAmount))}</div>` : '';
  const who = partyTbl('KO1', 'Kimdan') + partyTbl('KO2', 'Kimga');
  // onlayn kassa Z-hisoboti (F1.26): kiritilgan raqamlar; yopilgan kunda — tizim bilan solishtirish
  const z = d.z || {}, zp = [];
  if (z.applies) {
    if (z.recorded && !z.missing) zp.push(`№ ${esc(z.no)} · naqd ${esc(som(z.cash))} · karta ${esc(som(z.card))}`);
    if (closed) { const zt = zText(z); if (zt) zp.push(esc(zt));
      if (z.recorded && !z.missing) zp.push(`tizimda: naqd ${esc(som(z.expCash))} (${esc(String(num(z.nCash)))} chek), karta ${esc(som(z.expCard))} (${esc(String(num(z.nCard)))} ta)`); }
    else if (z.missing) zp.push(esc(zText(z)));
  }
  const zLine = zp.length ? `<div class="small" id="kdv-z" style="margin-top:8px${closed && z.ok === false ? ';color:#B42318;font-weight:700' : ''}">Onlayn kassa Z-hisoboti: ${zp.join(' — ')}</div>` : '';
  $('#modal').innerHTML = `<div class="modal-h"><h3>Kassa kuni — ${esc(dmy(day))}</h3><button class="x" id="m-x">×</button></div>
    <div class="modal-b">
      <div class="small" style="background:#eef3f1;border-radius:10px;padding:10px 12px">${dayChip(d.status)} Kun boshi <b>${esc(som(d.opening))}</b> · kirim <b>${esc(som(closed ? d.receipts : d.receiptsLive))}</b> · chiqim <b>${esc(som(closed ? d.payouts : d.payoutsLive))}</b> · kun oxiri <b>${esc(som(closed ? d.closing : d.balance))}</b>${closed ? ` · sanalgan <b>${esc(som(d.counted))}</b>` : ''}${(d.handoverDiffs || []).filter(x => num(x)).length ? ` · smena topshirishda farq <b>${esc((d.handoverDiffs || []).filter(x => num(x)).map(sgnS).join(', '))}</b>` : ''}${closed && d.sheetFrom ? ` · varaq ${esc(String(d.sheetFrom))}${d.sheetTo > d.sheetFrom ? '–' + esc(String(d.sheetTo)) : ''}` : ''}</div>
      ${zLine}
      <div style="display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;margin:10px 0 6px"><b>Hujjatlar (${docs.length} ta)</b><span style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn sm" id="kdv-report" title="Kunlik hisobot: kimdan / kimga qancha">🖨 Kunlik hisobot</button><button class="btn sm" id="kdv-book">🖨 Kassa kitobi varag‘i${closed ? '' : ' (qoralama)'}</button></span></div>
      ${docs.length ? `<div class="tablewrap"><table><thead><tr><th>№</th><th>Operatsiya / tomon</th><th style="text-align:right">Kirim</th><th style="text-align:right">Chiqim</th><th>Kim</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>` : '<div class="empty">Hujjat yo‘q.</div>'}
      ${who ? `<details style="margin-top:12px" open id="kdv-who"><summary class="small" style="cursor:pointer;font-weight:700">Kimdan / kimga qancha</summary>${who}${trTxt}</details>` : ''}
      ${cnts || hos ? `<div style="margin-top:12px"><b>Sanashlar</b>${cnts}${hos}</div>` : ''}
      ${evs ? `<details style="margin-top:12px"><summary class="small" style="cursor:pointer;font-weight:700">Kun jurnali</summary><div style="margin-top:6px">${evs}</div></details>` : ''}
    </div>
    <div class="modal-f"><button type="button" class="btn ghost" id="m-cancel">Yopish</button></div>`;
  $('#m-x').onclick = C.closeModal; $('#m-cancel').onclick = C.closeModal;
  const back = () => openDayView(day);
  $('#kdv-book').onclick = () => printBook(day, back);
  $('#kdv-report').onclick = () => printReport(day, book);
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
  const mineToDo = (ST.ov.requests || []).filter(d => d.status === 'draft' && (canApproveList2(d, m) || (m.director && d.needsDirector && !d.dirApprovedBy)));
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
