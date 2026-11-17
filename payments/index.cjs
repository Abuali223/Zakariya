/**
 * Iqror — TO'LOV serveri (Uzum Merchant API + Click → invoices)
 * -------------------------------------------------------------------
 * Ota-ona kabinetdagi hisob-fakturani Uzum (yoki Click) orqali to'laganda,
 * to'lov tizimi shu serverga chaqiruv yuboradi. Server so'rovni tekshirib,
 * `invoices/<id>` ni «paid» qiladi. Maxfiy kalitlar faqat shu serverda.
 *
 * ⚠️ PUL bilan ishlaydi — ishonchli, HTTPS orqasidagi serverda ishlating.
 * Supabase service_role (yoki Firebase Admin) orqali yozadi (RLS chetlab).
 *
 * UZUM Merchant API (server-to-server) — Uzum 5 ta endpoint chaqiradi
 * (har birida Basic auth: login:password kabinetdan):
 *   POST /uzum/check     — hisob-faktura bor/to'lanmaganini tekshiradi
 *   POST /uzum/create    — tranzaksiya yaratadi (rezerv)
 *   POST /uzum/confirm   — to'lov tasdiqlandi → invoice «paid» ★
 *   POST /uzum/reverse   — qaytarish (refund) → invoice «reversed»
 *   POST /uzum/status    — tranzaksiya holatini qaytaradi
 *   Javob status: OK / CREATED / CONFIRMED / REVERSED / FAILED(errorCode).
 *   Hujjat: developer.uzumbank.uz/merchant
 *
 * CLICK SHOP-API (Merchant API) — TO'LIQ, saqlab qolingan (ixtiyoriy):
 *   POST /click/prepare (action=0) · POST /click/complete (action=1)
 *   imzo = md5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id
 *              [+ merchant_prepare_id]  + amount + action + sign_time)
 *
 * Ishga tushirish:
 *   npm install
 *   cp config.example.json config.json   # to'ldiring
 *   node index.cjs                        # :8790 da tinglaydi
 *
 * Batafsil: README.md
 */
const fs = require('fs');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
// Konstant-vaqtли solishtiruv (imzo/parol uchun — timing side-channelни kamaytiradi).
function tseq(a, b){ const ab = Buffer.from(String(a==null?'':a)), bb = Buffer.from(String(b==null?'':b));
  if(ab.length !== bb.length) return false; try{ return crypto.timingSafeEqual(ab, bb); }catch(e){ return false; } }
const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
// Data qatlami: CFG.backend='supabase' -> Supabase service_role, aks holda Firebase (rollback).
const { db, FieldValue } = require('../server/backend.js')({ ...CFG, __dir: __dirname });
const CLICK = CFG.click || {};        // { serviceId, secretKey, merchantId }
const UZUM  = CFG.uzum  || {};        // { serviceId, login, password, accountField?, amountUnit? }
const HIK   = CFG.hik   || {};        // { secret, debug } — Hikvision yuz terminali (xodimlar keldi-ketdi)

const md5 = s => crypto.createHash('md5').update(s).digest('hex');
const amtEq = (a, b) => Math.abs(Number(a) - Number(b)) < 0.5;
const getInvoice = async id => { const s = await db.collection('invoices').doc(String(id||'')).get(); return s.exists ? s.data() : null; };

/* ---------- To'lov identifikatorini invoice'ga aylantirish (moslashuvchan) ----------
 * merchant_trans_id / Uzum account quyidagilardan biri bo'lishi mumkin:
 *   1) "{sid}__{YYYY-MM}"  — ANIQ invoice ID (kabinet «Click» tugmasi) — o'zgarmagan
 *   2) "IQ-0042 KOD"       — o'quvchi ID + maxfiy kod (Click ilova / QR / kassa)
 *   3) "KOD"               — faqat maxfiy kod (kod noyob bo'lsa)
 * Kod = 2b student_codes (admin paneldagi «Kod» ustuni). Server service_role bilan
 * o'qiydi (RLS chetlab). Topilса o'quvchining TO'LANMAGAN hisob-fakturasi qaytadi
 * (mos summali afzal, aks holda eng eski).
 * ALMASHTIRILGAN (eski) kod ham — faqat TO'LOV uchun — qabul qilinadi (student_code_prev, migration/payer-code-mask.sql):
 * ota-ona Click/Uzum'da saqlab qo'ygan eski kod bilan to'lasa ham pul avtomatik biriktirilsin. Farzand ulash
 * (claim_child) esa faqat JORIY kod bilan. */
// Eski kodning egasi (o'quvchi doc id) — kod bitta o'quvchiniki bo'lsa, aks holda / o'qib bo'lmasa null.
async function prevCodeOwner(code){
  try{ const snap = await db.collection('student_code_prev').where('code','==',code).get();
       const docs = snap.docs || []; return docs.length === 1 ? (String((docs[0].data()||{}).studentDocId||'') || null) : null; }
  catch(e){ return null; }
}
async function studentIdByCode(code){
  code = String(code||'').trim().toUpperCase(); if(!code) return null;
  try{ const snap = await db.collection('student_codes').where('code','==',code).get();
       const docs = snap.docs || []; if(docs.length) return docs.length === 1 ? String(docs[0].id) : null; }
  catch(e){ return null; }
  return await prevCodeOwner(code);   // joriy kod emas — almashtirilgan kod bo'lsa, uning egasi
}
async function codeMatches(sid, code){
  code = String(code||'').trim().toUpperCase(); if(!sid || !code) return false;
  try{ const s = await db.collection('student_codes').doc(String(sid)).get();
       if(s.exists && String((s.data()||{}).code||'').toUpperCase() === code) return true; }
  catch(e){ return false; }
  return (await prevCodeOwner(code)) === String(sid);   // shu o'quvchining eski kodi
}

/* ---------- To'lovchi matnidagi MAXFIY KODni yashirish (egasi qarori (a), 2026-11-16) ----------
 * Ota-ona yozgan matn (merchant_trans_id, payerName, payerClass, payerPhone, Uzum so'rovi — raw) payments qatorida
 * saqlanadi va moliya rollariga (moliya menejeri, g'aznachi, kassir) ko'rinadi; kod esa claim_child orqali farzandni
 * ulashga yetadi. Shuning uchun bunday matn SAQLASHDAN (va debug logdan) OLDIN tekshiriladi: joriy yoki almashtirilgan
 * (student_code_prev) kod «[kod]» bo'ladi. Biriktirish ASL matn bilan ishlaydi, Click / Uzum'ga javob ham asl qiymatlarni
 * qaytaradi — faqat saqlanadigan nusxa va log yashiriladi.
 * Bo'lak — harf/raqamning uzluksiz qatori (lotin, kiril); bo'laklar QATORI — orasida ajratgich bo'lgan bo'laklar. Ajratgich: 1–2 ta
 * belgi (bo'sh joy, tab, «.», «,», «-», «_», «/») yoki 3 tagacha bo'sh joy belgisi (bo'sh joy, tab, yangi qator, bo'linmas bo'sh joy):
 * «3FA9 C21B 7D0E», «3FA9-C21B-7D0E», «3FA9  C21B  7D0E», «3FA9_C21B_7D0E», «3FA9/C21B/7D0E», «3FA9, C21B, 7D0E», qatorma-qator
 * yozilgan «3FA9⏎C21B⏎7D0E», «IQ-0042 3FA9C2 1B7D0E». Taqqoslash katta-kichik harfga sezgir emas; kodga o'xshash kiril harflari
 * (А, Б/В, С, Д, Е, Ф) va «O» harfi (nol o'rniga) ham hisobga olinadi.
 * Kod: kodga teng bo'lak yoki qator bo'laklari ulanganda undagi 12 belgili 0-9/A-F oyna (bitta uzun bo'lak ichida ham). Yashiriladigan
 * joy — kod va qatorda unga yondosh HEX-shaklli (normallangandan keyin faqat 0-9/A-F) bo'laklarning eng uzun ketma-ketligi, oradagi
 * ajratgichlar bilan BITTA «[kod]» (kodning bir belgisi farq qiladigan nusxasi ham ochiq qolmasin). IQ uslubidagi ID («IQ» dan
 * keyingi raqam) va hex bo'lmagan bo'lak (ism, so'z) o'zgarmaydi: «IQ-0042 3FA9 C21B 7D0E» -> «IQ-0042 [kod]», «3FA9C21B7D0E
 * 3FA9C21B7D0F» -> «[kod]», «Sinov Ali 3FA9C21B7D0E» -> «Sinov Ali [kod]», «5A 3FA9C21B 7D0E» -> «[kod]», «IQ00423FA9C21B7D0E» ->
 * «IQ0042[kod]» (kod bo'lak o'rtasida bo'lsa — bo'lakning kod oldidagi / ortidagi qismi ham hex bo'lsagina u ham yashiriladi).
 * Bazadan o'qib bo'lmasa (xato) — o'qilmagan kalitlarga FAIL-CLOSED shakl qoidasi: 12 ta 0-9/A-F va kamida bitta harf A–F
 * (app.new_student_code har doim harfli kod beradi) — bo'lak ichida yoki aynan bo'lak chegaralaridagi guruh; telefon
 * («+998 90 123 45 67» — faqat raqam), sana, summa, sinf (5A) va IQ-0042 kabi ID tegilmaydi; harfi faqat boshidagi sinf nomidan
 * bo'lgan guruh ham («5A 998 90 123 45 67», «11B 2026-11-16 1 500 000» — sinf va undan keyingi faqat raqamli bo'laklar).
 * Eski yozuvlar uchun SQL tomoni (migration/payer-code-mask.sql: app.payer_codes_fix / app.payer_mask) — AYNAN shu qoida
 * (shakl qoidasi — faqat shu yerda: bazasiz holat uchun). */
const KOD_MASK = '[kod]';
const KOD_TOK = /[0-9A-Za-zА-Яа-яЁё]+/g;
// bo'laklar qatori: ajratgich — 1–2 ta [bo'sh joy, tab . , - _ /] yoki 3 tagacha bo'sh joy belgisi (yangi qator ham); SQL bilan bir xil
const KOD_RUN = /[0-9A-Za-zА-Яа-яЁё]+(?:(?:[ \t.,_\/-]{1,2}|[ \t\r\n\u00A0]{1,3})[0-9A-Za-zА-Яа-яЁё]+)*/g;
const KOD_LOOK = { 'А':'A','а':'A','Б':'B','б':'B','В':'B','в':'B','С':'C','с':'C','Д':'D','д':'D','Е':'E','е':'E','Ф':'F','ф':'F','О':'0','о':'0','O':'0','o':'0' };
const kodNorm = t => String(t).replace(/[АаБбВвСсДдЕеФфОоOo]/g, ch => KOD_LOOK[ch]).toUpperCase();
const KOD_WORD = /^[0-9A-Z]{5,16}$/, KOD_HEX12 = /^[0-9A-F]{12}$/;
const kodShape = w => KOD_HEX12.test(w) && /[A-F]/.test(w);
const KOD_CLASS = /^[0-9]{1,2}[A-F]$/;   // sinf nomiga o'xshash bo'lak (normallangan): «5A», «11B», kiril «5В» -> «5B»
const KOD_MAX_KEYS = 120;   // bitta yozuvdagi kalitlar chegarasi (bitta «in» so'roviga sig'sin); oshsa — shakl qoidasi (fail-closed)
// Qator: bo'laklari (s/e — qatordagi o'rni, j — ulangan matndagi o'rni, u — katta harfda, n — normallangan), ulangan
//   normallangan matn J va J'ning har belgisi qatorning qaysi o'rnida (pos).
function kodRun(r){
  const toks = [], pos = [], re = new RegExp(KOD_TOK.source, 'g'); let J = '', m;
  while((m = re.exec(r))){ const t = m[0], n = kodNorm(t);
    toks.push({ s: m.index, e: m.index + t.length, j: J.length, u: t.toUpperCase(), n });
    for(let i = 0; i < t.length; i++) pos.push(m.index + i);
    J += n; }
  return { toks, J, pos };
}
// Qator uchun bazada qidiriladigan kalitlar (SQL app.payer_codes_fix «keys» bilan bir xil): 5–16 belgili bo'lak (katta harfda va
//   normallangan) va ulangan qatordagi har 12 belgili 0-9/A-F oyna.
function kodKeys(r, out){
  const { toks, J } = kodRun(r);
  for(const t of toks){ if(KOD_WORD.test(t.u)) out.add(t.u); if(KOD_WORD.test(t.n)) out.add(t.n); }
  for(let i = 0; i + 12 <= J.length; i++){ const w = J.slice(i, i + 12); if(KOD_HEX12.test(w)) out.add(w); }
}
// Satr va son qiymatlarini (obyekt/massiv ichida ham; kalitlar — provayderniki) yig'adi / almashtiradi.
function kodLeaves(v, acc){
  if(typeof v === 'string') acc.push(v);
  else if(typeof v === 'number') acc.push(String(v));
  else if(Array.isArray(v)) v.forEach(x => kodLeaves(x, acc));
  else if(v && typeof v === 'object') Object.keys(v).forEach(k => kodLeaves(v[k], acc));
  return acc;
}
function kodWalk(v, fn){
  if(typeof v === 'string') return fn(v);
  if(typeof v === 'number'){ const s = String(v), m = fn(s); return m === s ? v : m; }
  if(Array.isArray(v)) return v.map(x => kodWalk(x, fn));
  if(v && typeof v === 'object'){ const o = {}; for(const k of Object.keys(v)) o[k] = kodWalk(v[k], fn); return o; }
  return v;
}
// Yashiriladigan joyni KENGAYTIRADI (base — kod belgilari, oradagi ajratgichlar bilan): kod turgan bo'lakdan chapga va o'ngga
//   qatordagi HEX-shaklli (normallangan: faqat 0-9/A-F) bo'laklar ham — «3FA9C21B7D0E 3FA9C21B7D0F» -> «[kod]». Kod bo'lak o'rtasida
//   bo'lsa — bo'lakning kod oldidagi / ortidagi qismi ham hex bo'lsagina («AB3FA9…» -> «[kod]», «Kod3FA9…» -> «Kod[kod]»). To'xtaydi:
//   hex bo'lmagan bo'lakda (ism, so'z, «IQ») va IQ-ID raqamida («IQ» dan keyingi faqat raqamli bo'lak; «IQ» dan keyingi bo'lakdagi
//   kodning oldi — «IQ-00423FA9…» -> «IQ-0042[kod]»). SQL app.payer_mask bilan AYNAN bir xil.
function kodWiden(r, toks, base){
  const mk = new Uint8Array(r.length), at = new Int32Array(r.length).fill(-1);
  toks.forEach((t, k) => { for(let i = t.s; i < t.e; i++) at[i] = k; });
  const idPos = k => k > 0 && toks[k - 1].u === 'IQ';                                      // «IQ» dan keyingi bo'lak
  const take = k => /^[0-9A-F]+$/.test(toks[k].n) && !(idPos(k) && /^[0-9]+$/.test(toks[k].n));
  for(let a = 0; a < r.length; a++){
    if(!base[a]) continue;
    let b = a; while(b + 1 < r.length && base[b + 1]) b++;
    const ka = at[a], kb = at[b]; let A = a, B = b;
    if(!idPos(ka) && /^[0-9A-F]*$/.test(toks[ka].n.slice(0, a - toks[ka].s))){ A = toks[ka].s; for(let k = ka - 1; k >= 0 && take(k); k--) A = toks[k].s; }
    if(/^[0-9A-F]*$/.test(toks[kb].n.slice(b + 1 - toks[kb].s))){ B = toks[kb].e - 1; for(let k = kb + 1; k < toks.length && take(k); k++) B = toks[k].e - 1; }
    for(let i = A; i <= B; i++) mk[i] = 1;
    a = b;
  }
  return mk;
}
// Bitta qatordagi kodlarni yashiradi. found — bazada topilgan kodlar (Map/Set); unknown(k) — k'ni bazadan tekshirib bo'lmadi;
//   exact — faqat kod belgilari, kengaytirmasdan va bo'sh joy bilan (kodBlank: ID tekshiruvi uchun).
function kodMaskRun(r, found, unknown, exact){
  const { toks, J, pos } = kodRun(r), base = new Uint8Array(r.length), starts = new Map(), ends = new Set(), idNum = new Set();
  const mark = (a, b) => { for(let i = a; i <= b; i++) base[i] = 1; };
  // Shakl qoidasi sinf + raqamlarni kod deb olmasin: oyna (J'da i dan) boshidagi bo'lak sinf nomi (KOD_CLASS), qolganlari faqat raqam —
  //   A–F harfi faqat sinfdan («5A 998 90 123 45 67», «11B 2026-11-16 1 500 000», «9D 16.11.2026 15», kiril «5В …»).
  const classLead = i => { let k = starts.get(i); if(!KOD_CLASS.test(toks[k].n)) return false;
    for(k++; k < toks.length && toks[k].j < i + 12; k++) if(!/^[0-9]+$/.test(toks[k].n)) return false;
    return true; };
  toks.forEach((t, k) => {
    starts.set(t.j, k); ends.add(t.j + t.n.length);
    // «IQ-0042» kabi ID'ning raqam qismi (harfli bo'lak + «-» + faqat raqam) — shakl qoidasida guruh boshi bo'lmaydi
    if(k && r[t.s - 1] === '-' && /^[0-9]+$/.test(r.slice(t.s, t.e)) && /^[A-Za-zА-Яа-яЁё]+$/.test(r.slice(toks[k - 1].s, toks[k - 1].e))) idNum.add(t.j);
    if(found.has(t.u) || found.has(t.n)) mark(t.s, t.e - 1);
    else if(unknown) for(let i = 0; i + 12 <= t.n.length; i++){ const w = t.n.slice(i, i + 12); if(kodShape(w) && unknown(w)){ mark(t.s, t.e - 1); break; } }
  });
  for(let i = 0; i + 12 <= J.length; i++){
    const w = J.slice(i, i + 12); if(!KOD_HEX12.test(w)) continue;
    // Bazadagi kod — istalgan o'rinda; shakl qoidasi — faqat bo'lak chegaralaridagi guruh («5A 998901234567» kabi aralash emas).
    if(found.has(w) || (unknown && starts.has(i) && ends.has(i + 12) && !idNum.has(i) && kodShape(w) && !classLead(i) && unknown(w))) mark(pos[i], pos[i + 11]);
  }
  const mk = exact ? base : kodWiden(r, toks, base), rep = exact ? ' ' : KOD_MASK;
  let out = '';
  for(let i = 0; i < r.length; i++){ if(!mk[i]) out += r[i]; else if(i === 0 || !mk[i - 1]) out += rep; }
  return out;
}
const kodMaskText = (s, found, unknown) => String(s).replace(KOD_RUN, r => kodMaskRun(r, found, unknown, false));
// Matndagi kodlar (faqat kod belgilari) bo'sh joy bilan almashtirilgan nusxa — ID qidirishda kodga yopishgan raqamlar ID'ga qo'shilmasin
//   («IQ00423FA9C21B7D0E» -> «IQ0042 »).
const kodBlank = (s, codes) => String(s).replace(KOD_RUN, r => kodMaskRun(r, codes, null, true));
// Berilgan qiymatlardagi (satr / obyekt) kodlarni bazadan aniqlab (ikki so'rov: joriy va eski kodlar), yashiruvchi funksiya
//   qaytaradi: mask(qiymat) -> nusxa. mask.owners — topilgan har kodning egasi (o'quvchi doc id) to'plami, mask.codes — topilgan
//   kodlar — biriktirish uchun (ownerSid); biror so'rov bajarilmagan bo'lsa — null (matnda tekshirilmay qolgan boshqa kod bo'lishi mumkin).
async function kodMasker(...vals){
  const keys = new Set();
  for(const s of kodLeaves(vals, [])) for(const r of (s.match(KOD_RUN) || [])) kodKeys(r, keys);
  const own = new Map();   // kod -> egalari
  const add = (code, sid) => { code = String(code || '').toUpperCase(); if(!keys.has(code)) return;
    if(!own.has(code)) own.set(code, new Set()); own.get(code).add(String(sid || '')); };
  let failed = keys.size > KOD_MAX_KEYS;
  if(keys.size && !failed){
    const ks = [...keys];
    // allSettled: bitta jadval o'qilmasa ham ikkinchisida topilgan kod yashiriladi; topilmagan kalitlarga — shakl qoidasi.
    const [a, b] = await Promise.allSettled([db.collection('student_codes').where('code', 'in', ks).get(),
                                             db.collection('student_code_prev').where('code', 'in', ks).get()]);
    if(a.status === 'fulfilled') (a.value.docs || []).forEach(d => add((d.data() || {}).code, d.id)); else failed = true;
    if(b.status === 'fulfilled') (b.value.docs || []).forEach(d => add((d.data() || {}).code, (d.data() || {}).studentDocId)); else failed = true;
  }
  const unknown = failed ? (k => !own.has(k)) : null;
  const mask = v => kodWalk(v, s => kodMaskText(s, own, unknown));
  mask.owners = failed ? null : new Set([...own.values()].flatMap(x => [...x]));
  mask.codes = failed ? null : new Set(own.keys());
  mask.own = failed ? null : own;   // kod -> egalari (aniq kod qoidasi: matndagi boshqa kodlar ham shu o'quvchinikimi)
  return mask;
}
const maskPayer = async v => (await kodMasker(v))(v);
async function unpaidInvoices(sid){
  try{ const snap = await db.collection('invoices').where('studentId','==',String(sid)).get();
       return (snap.docs || []).map(d=>d.data())
         .filter(x=>x && x.status!=='paid' && x.status!=='canceled' && x.status!=='reversed')
         .sort((a,b)=>String(a.month||a.id||'').localeCompare(String(b.month||b.id||''))); }
  catch(e){ return []; }
}
// Telefonni normallashtiradi: faqat raqamlar, oxirgi 9 ta (+998/bo'sh joy farqi muhim emas).
const normPhone = p => String(p||'').replace(/\D/g,'').slice(-9);
// Kiril <-> Lotin: ota-ona to'lovда ismни/sinfни ISTALGAN alifboда yozса ham to'lov AYNAN
//   o'sha o'quvchiga tushsin. Ikkala tomon ham UMUMIY "translit kalit"га keltiriladi
//   (kiril->lotin + iotli unlilar folding), so'ng solishtiriladi.
//   Misol: "Хадичахон 6 б" == "Xadichaxon 6b",  "Тиргунбоева" == "Tirgunboyeva".
const CYR2LAT = {
  'а':'a','б':'b','в':'v','г':'g','д':'d','е':'e','ё':'yo','ж':'j','з':'z','и':'i','й':'y',
  'к':'k','л':'l','м':'m','н':'n','о':'o','п':'p','р':'r','с':'s','т':'t','у':'u','ф':'f',
  'х':'x','ц':'ts','ч':'ch','ш':'sh','щ':'sh','ъ':'','ы':'i','ь':'','э':'e','ю':'yu','я':'ya',
  'ў':'o','қ':'q','ғ':'g','ҳ':'h'   // o'zbekcha maxsus harflar
};
const translit = s => {
  let t = String(s||'').toLowerCase();
  t = t.replace(/[Ѐ-ӿ]/g, ch => Object.prototype.hasOwnProperty.call(CYR2LAT, ch) ? CYR2LAT[ch] : ch);  // kiril -> lotin
  // Iotli unlilar / й — ikkala alifbo bir xil ko'rinsin (е≈ye, ё≈yo, ю≈yu, я≈ya):
  t = t.replace(/yo/g,'o').replace(/yu/g,'u').replace(/ya/g,'a').replace(/ye/g,'e').replace(/yi/g,'i');
  t = t.replace(/kh/g,'x');                    // ruscha "kh" -> o'zbekcha "x"
  t = t.replace(/[^a-z0-9\s]/g,'');            // apostrof/tinish belgilar olib tashlanadi (o' -> o, g' -> g)
  return t;
};
const normTxt = s => translit(s).replace(/\s+/g,' ').trim();
const normClass = s => translit(s).replace(/\s+/g,'');
// Ism "mos"mi? Kamida bitta ma'noli so'z (>=3 harf) ustma-ust tushsin. Bir xil telefonli
// BOSHQA bolaning to'lovi shu o'quvchiga noto'g'ri tushmasin (masalan "Qobuljonov" vs "Oyzekov").
const nameOverlap = (a, b) => {
  const ta = new Set(normTxt(a).split(' ').filter(w => w.length >= 3));
  return normTxt(b).split(' ').filter(w => w.length >= 3).some(w => ta.has(w));
};

// Telefon (+ ism/sinf bilan aniqlashtirish) bo'yicha o'quvchini topadi.
// Qaytadi: { status:'ok', studentId } | 'notfound' | 'ambiguous' | 'nophone'.
async function findStudentByPhone(phone, name, klass){
  const ph = normPhone(phone); if(ph.length < 7) return { status:'nophone' };
  let privs;
  try{ privs = (await db.collection('student_private').get()).docs.map(d=>({ id:d.id, ...(d.data()||{}) })); }
  catch(e){ return { status:'error' }; }
  const ids = privs.filter(x => normPhone(x.parentPhone) === ph || normPhone(x.parentPhone2) === ph).map(x => x.id);
  if(!ids.length) return { status:'notfound' };
  // Nomzod o'quvchilar (ism/sinf tekshiruvi) — BITTA bo'lsa ham yuklaymiz: bir xil telefonли
  // (aka-uka yoki xato kiritilgan) boshqa bolaning to'lovi shu bolaga ko'r-ko'rona tushmasin.
  let studs = [];
  try{ studs = (await db.collection('students').get()).docs.map(d=>({ id:d.id, ...(d.data()||{}) })); }catch(e){}
  const cand = studs.filter(s => ids.includes(s.id));
  const nm = normTxt(name), kl = normClass(klass);
  if(ids.length === 1){
    // Bitta telefon mos. Ism BERILGAN va o'sha o'quvchiga mos kelsagina biriktiramiz.
    // Ism YO'Q (bo'sh) yoki mos emas -> ko'r-ko'rona telefonga ishonmaymiz (bir xil/xato terilган
    // telefon boshqa oilaga tegishli bo'lishi mumkin) -> 'ambiguous' -> admin qo'lда biriktiradi
    // (biriktirilmagan ro'yxatда telefon ko'rinadi, bir bosishда ulanadi).
    if(nm && cand.length === 1 && nameOverlap(cand[0].name, name)) return { status:'ok', studentId: ids[0] };
    return { status:'ambiguous', candidates: ids };
  }
  // Aka-uka (bir telefon) — ism/sinf bilan ajratamiz.
  let hit = nm ? cand.filter(s => normTxt(s.name) === nm) : [];                          // (1) to'liq ism
  if(hit.length !== 1 && nm){ const ov = cand.filter(s => nameOverlap(s.name, name)); if(ov.length === 1) hit = ov; }  // (2) ism-so'z mos
  if(hit.length !== 1 && kl){ const byCls = cand.filter(s => normClass(String(s.grade||'') + (s.classLetter || s.track || '')) === kl); if(byCls.length === 1) hit = byCls; }  // (3) sinf
  if(hit.length === 1) return { status:'ok', studentId: hit[0].id };
  return { status:'ambiguous', candidates: ids };
}

// KANONIK o'quvchi kaliti: student_codes / student_private hujjat id'si = students.id (doc _id), butun moliya
//   (invoices / student_credit / to'lov tarixi / Moliya tekshiruvi) esa students.studentId (IQ-xxxx) bilan
//   ishlaydi. payments.studentId'ga doc _id yozilsa: Moliya tekshiruvi bir o'quvchini IKKIGA bo'lib
//   ko'rsatardi va «🔧 Qo'llash» o'sha pulni IKKINCHI marta qo'llardi; to'lov tarixi/chekda ko'rinmasdi.
//   apply_payment (audit-7) bilan bir xil qoida: id YOKI studentId mos -> studentId (bo'sh bo'lsa id).
async function canonSid(sid){
  sid = String(sid||'').trim(); if(!sid) return sid;
  try{ const d = await db.collection('students').doc(sid).get();
       if(d.exists){ const x = d.data()||{}; return String(x.studentId||'').trim() || sid; } }catch(e){}
  return sid;   // doc id emas -> allaqachon studentId (yoki noma'lum) — o'zgarishsiz
}
// Foydalanuvchi yozgan ID (IQ-xxxx yoki doc id) + kod: kod hujjati students.id bilan kalitlangan, shuning uchun
//   IQ-xxxx berilsa avval o'quvchining doc id'sini topamiz (import qilinganlarda id != studentId).
async function codeMatchesAny(idOrSid, code){
  if(await codeMatches(idOrSid, code)) return true;
  try{ const q = await db.collection('students').where('studentId','==',String(idOrSid)).get();
       for(const d of (q.docs||[])){ if(String(d.id) !== String(idOrSid) && await codeMatches(String(d.id), code)) return true; } }catch(e){}
  return false;
}
// O'quvchi hozir MAVJUDmi (doc id yoki studentId bo'yicha)? O'chirilgan o'quvchining kodi (student_codes qatori) qolib
//   ketgan bo'lishi mumkin — u bilan kelgan to'lov «arvoh» kalitga avans bo'lib tushib, biriktirilmagan navbatda ham
//   ko'rinmasdi. Mavjud bo'lmasa kod mos deb hisoblanmaydi (to'lov telefon yo'liga / qo'lda biriktirishga o'tadi).
async function studentExists(x){
  x = String(x||'').trim(); if(!x) return false;
  try{ const d = await db.collection('students').doc(x).get(); if(d.exists) return true; }catch(e){}
  try{ const q = await db.collection('students').where('studentId','==',x).get(); return (q.docs||[]).length > 0; }catch(e){ return false; }
}
// merchant_trans_id (+ Click paramlari) dan o'quvchini aniqlaydi.
// Qaytadi: { sid, via } — via: 'code' | 'phone' | (topilmasa) 'notfound'/'ambiguous'/'nophone'/'code_conflict'.
//   sid — DOIM kanonik (students.studentId). Kod bo'yicha topilgan o'quvchi — matnda (merchant_trans_id, telefon, sinf) BOSHQA
//   o'quvchi tilga olinmagan (otherStudentInText — kod egasi qoidasi bilan bir xil) va matndagi BARCHA kodlar (kodMasker egalari)
//   shu o'quvchiniki bo'lsagina; aks holda kod qoidasi o'tkaziladi (ikki o'quvchining kodi — kod egasi qoidasi ham rad etadi).
//   Telefon (+ ism) bo'yicha topilgan o'quvchi ham — matndagi kod(lar) faqat o'shaniki bo'lsa; boshqa o'quvchining kodi bo'lsa yoki
//   kodlarni o'qib bo'lmasa — 'code_conflict': ism / telefon bir o'quvchini, kod boshqasini ko'rsatadi -> biriktirilmaydi (kod egasi
//   qoidasi ham ishlamaydi), Direktor qo'lda biriktiradi.
async function attributeStudent(mti, params){
  mti = String(mti||'').trim();
  const ph = (params && (params.param3 || params.phone)) || '';   // Click: param3 = telefon, param2 = sinf
  const texts = [mti, ph, params && params.param2];
  let mk0 = null; const masker = async () => mk0 || (mk0 = await kodMasker(...texts));
  // Matndagi BARCHA kodlar faqat docs (o'quvchi doc id'lari) egasiniki-mi? O'qib bo'lmasa — yo'q (fail-closed).
  const onlyOwn = async docs => { const mk = await masker(); return !!mk.owners && [...mk.owners].every(o => docs.has(o)); };
  const solo = async (key, sid, code) => { const mk = await masker(), docs = mk.own && mk.own.get(String(code).toUpperCase());
    return !!docs && await onlyOwn(docs) && (await otherStudentInText(texts, key, sid, new Set([code, ...mk.codes]))) === false; };
  const raw = mti.split(/[\s*\/+#:.,;|]+/).filter(Boolean), parts = raw.map(x => x.toUpperCase());
  if(parts.length >= 2){                                     // ID + kod (har ikki tartib)
    for(const [i, j] of [[0, 1], [1, 0]]){
      // doc id katta-kichik harfga SEZGIR (import qilingan Firebase id, masalan fbX9kQ2) — avval asl yozilishi bilan;
      //   studentId (IQ-xxxx) va katta harfli doc id — katta harfda (avvalgidek).
      if(raw[i] !== parts[i] && await codeMatches(raw[i], parts[j])){ const sid = await canonSid(raw[i]); if(await studentExists(sid) && await solo(raw[i], sid, parts[j])) return { sid, via:'code' }; }
      if(await codeMatchesAny(parts[i], parts[j])){ const sid = await canonSid(parts[i]); if(await studentExists(sid) && await solo(parts[i], sid, parts[j])) return { sid, via:'code' }; }
    }
  } else if(parts.length === 1 && /^[A-Z0-9]{5,16}$/.test(parts[0])){   // faqat kod (kod-shaklli bo'lsa; hozirgi kodlar 12 belgi — audit-4/gen_student_code; topilmasa telefon bo'yicha davom etadi)
    const s = await studentIdByCode(parts[0]);
    if(s){ const sid = await canonSid(s); if(await studentExists(sid) && await solo(s, sid, parts[0])) return { sid, via:'code' }; }
  }
  // Ism solishtirishda matndagi kod xalaqit bermasin: «Sinov Bobur KOD» -> to'liq ism «Sinov Bobur» (aka-ukani ajratadi; kod kimniki —
  //   pastda tekshiriladi).
  let name = mti;
  if(normPhone(ph).length >= 7){ const mk = await masker(); if(mk.codes) name = kodBlank(mti, mk.codes); }
  const r = await findStudentByPhone(ph, name, params && params.param2);
  if(r.status === 'ok'){
    if(!(await onlyOwn(new Set([String(r.studentId)])))) return { sid: null, via: 'code_conflict' };   // matnda boshqa o'quvchining kodi
    return { sid: await canonSid(r.studentId), via:'phone' };
  }
  return { sid: null, via: r.status };
}
// Kod EGASI bo'yicha biriktirish — faqat yuqoridagi qoidalar o'quvchi topmaganda (kod kiril / «O» harfli yoki guruhlab yozilgan):
//   matndagi BARCHA kodlar (kodMasker topgan — joriy yoki eski) BITTA o'quvchiniki, o'quvchi mavjud va matnda BOSHQA o'quvchi
//   tilga olinmagan bo'lsa (otherStudentInText) — o'sha o'quvchi (kanonik studentId), aks holda null. Kodi matnda bo'lmagan
//   o'quvchiga hech qachon biriktirilmaydi (egalar faqat matndagi kodlardan). mk — kodMasker natijasi (owners, codes).
async function ownerSid(mk, ...texts){
  const owners = mk && mk.owners;
  if(!owners || owners.size !== 1) return null;
  const doc = [...owners][0], sid = await canonSid(doc);
  if(!sid || !(await studentExists(sid))) return null;
  return (await otherStudentInText(texts, doc, sid, mk.codes)) === false ? sid : null;   // boshqa o'quvchi yoki o'qib bo'lmadi — yo'q
}
// IQ uslubidagi o'quvchi ID'si matnning istalgan joyida: (1) «IQ» + «-» / «_» / «–» / «—» + raqam — oldida harf bo'lsa ham
//   («IQ-0042», «iq_0042», «IQ-0042'…», «IQ-0042-KOD», «5AIQ-0042»); (2) so'z boshidagi (oldida harf yo'q) «IQ» yoki kiril harfli
//   «ІQ», «IҚ», «ІҚ», «ИҚ», «ИК» — raqam bilan orasida 3 tagacha istalgan belgi (harf va raqamdan boshqa; atrofidagi bo'sh joylar
//   sanalmaydi): «IQ0042», «IQ 0042», «IQ,0042», «IQ(0042)», «IQ'0042», «IQ\0042», «IQ  -  0042», «№IQ-0042», «ИҚ-0042». Harfga
//   yopishgan (2)-shakl — ID emas: ism oxiridagi «…iq» («Rafiq 3FA9…», «Sodiq 0042 …»); shu sabab «AliIQ0042», «5AIQ0042» kabi
//   yozilgan boshqa o'quvchi ID'si ham tanilmaydi (qabul qilingan qoldiq xavf — payments/README.md).
const SID_IQ = /(?:IQ[-_–—][\s_-]{0,2}|(?<!\p{L})(?:IQ|ІQ|IҚ|ІҚ|ИҚ|ИК)(?:\s{0,3}[^\p{L}\p{N}\s]){0,3}\s{0,3})([0-9]+)/giu;
// Matnda BOSHQA o'quvchi tilga olinganmi (kod bo'yicha biriktirishdan oldin)? texts — to'lovchi matnlari, doc — egasining doc id'si
//   (yoki yozilgan kaliti), sid — kanonik studentId, codes — matndagi kodlar (Set). Nomzodlar (3–64 belgi, asl va katta harfda):
//   (1) attributeStudent bo'lgichi bilan bo'laklar; (2) harf / raqam / «-» dan boshqa belgida bo'lingan qismlarning «-» bilan
//   ulangan 1–4 bo'lakli har ketma-ketligi («IQ-0043-KOD» -> «IQ-0043», «0043-KOD», …). Bazada (bitta so'rov juft: students.id —
//   katta-kichik harfga sezgir, studentId — katta harfda) egasidan boshqa o'quvchiga mos nomzod -> true. (3) Kodlar olib tashlangan
//   matndagi har IQ-ID (SID_IQ) egasining o'z studentId'si bo'lmasa (bazada yo'q ID ham) -> true. Nomzod juda ko'p (KOD_MAX_KEYS
//   dan ortiq) yoki o'qib bo'lmasa -> null. Aks holda false. So'rovga faqat ID belgilaridan (harf, raqam, «-», «_») iborat nomzod
//   boradi: qo'shtirnoq / qavsli bo'lak «in» ro'yxatini buzmasin (uning toza qismlari (2) da bor).
async function otherStudentInText(texts, doc, sid, codes){
  const cand = new Set(), iq = new Set();
  const add = x => { if(x.length >= 3 && x.length <= 64 && /^[0-9A-Za-zА-Яа-яЁё_-]+$/.test(x)){ cand.add(x); cand.add(x.toUpperCase()); } };
  for(const t0 of texts){
    const t = String(t0 || ''); if(!t) continue;
    t.split(/[\s*\/+#:.,;|]+/).forEach(add);
    for(const ch of t.split(/[^0-9A-Za-zА-Яа-яЁё-]+/)){
      const ps = ch.split('-');
      for(let i = 0; i < ps.length; i++) if(ps[i]) for(let j = i; j < ps.length && j < i + 4; j++) if(ps[j]) add(ps.slice(i, j + 1).join('-'));
    }
    for(const m of kodBlank(t, codes || new Set()).matchAll(SID_IQ)) iq.add(m[1]);
  }
  const own = new Set();
  for(const k of [doc, sid]){ const m = /^IQ[-_ ]?([0-9]+)$/i.exec(String(k || '').trim()); if(m) own.add(m[1]); }
  for(const n of iq) if(!own.has(n)) return true;          // egasinikidan boshqa (yoki bazada yo'q) IQ-ID
  if(!cand.size) return false;
  if(cand.size > KOD_MAX_KEYS) return null;
  let docs;
  try{
    const ks = [...cand];
    const [a, b] = await Promise.all([db.collection('students').where('id', 'in', ks).get(),
                                      db.collection('students').where('studentId', 'in', ks.filter(x => x === x.toUpperCase())).get()]);
    docs = [...(a.docs || []), ...(b.docs || [])];
  }catch(e){ return null; }
  for(const d of docs){ const id = String(d.id), s = String((d.data() || {}).studentId || '').trim() || id; if(id !== String(doc) && s !== sid) return true; }
  return false;
}

// To'lov summasini o'quvchi BALANSIGA qo'llaydi (waterfall: eng eski invoice avval).
// AVANS HARAKATI jurnali — student_credit har o'zgarishini sababi bilan yozadi (izlanish uchun).
async function logCredit(studentId, delta, balanceAfter, reason, provider){
  if(!studentId || Math.abs(Number(delta)||0) < 0.5) return;
  const id = 'cl_' + Date.now() + '_' + Math.random().toString(36).slice(2,8);
  try{ await db.collection('credit_ledger').doc(id).set({ studentId:String(studentId), delta:Number(delta)||0,
    balanceAfter:Number(balanceAfter)||0, reason, provider:provider||'', at: FieldValue.serverTimestamp() }); }catch(e){}
}
// Kam -> qisman (qarzdorlik qoladi); to'liq -> paid; ortiqcha -> student_credit (avans).
// Mavjud kredit avval ishlatiladi. IDEMPOTENT: transId bo'yicha ikki marta hisoblanmaydi.
async function applyPaymentToStudent(studentId, amount, transId, provider){
  studentId = String(studentId||''); amount = Number(amount)||0; provider = provider || 'click';
  // [P0 tuzatildi] Supabase: ATOMIK + IDEMPOTENT apply_payment RPC (kassir yo'li bilan bir xil yagona
  // haqiqat manbai). Butun waterfall bitta tranzaksiyada; xato bo'lsa TO'LIQ rollback (posbon ham),
  // shuning uchun provayder qayta yuborganда ikki marta hisoblanmaydi. (Eski JS yo'li atomik EMAS edi.)
  if(db.rpc){
    const r = await db.rpc('apply_payment', { p_sid: studentId, p_amount: amount, p_provider: provider, p_pay_id: String(transId||'')||null });
    return (r && r.dup) ? { dup:true } : (r || {});
  }
  // ---- Firebase (rollback) — eski, atomik BO'LMAGAN JS waterfall ----
  const guardRef = db.collection('applied_payments').doc(String(transId||''));
  // ATOMIK band qilish — bir vaqtda kelgan takroriy callback ikki marta hisoblamasin (create id konfliktida xato beradi).
  try{ await guardRef.create({ studentId, amount, createdAt: FieldValue.serverTimestamp() }); }
  catch(e){ try{ const g = await guardRef.get(); return (g.data()||{}).result || { applied:[], leftover:0, dup:true }; }catch(_){ return { dup:true }; } }
  try{
  let credit = 0;
  try{ const c = await db.collection('student_credit').doc(studentId).get(); if(c.exists) credit = Number((c.data()||{}).credit)||0; }catch(e){}
  let available = amount + credit;
  const applied = [];
  const list = await unpaidInvoices(studentId);              // eng eski avval, pending/partial
  for(const inv of list){
    if(available <= 0) break;
    const paidSoFar = Number(inv.paidAmount)||0;
    const remaining = Number(inv.amount) - paidSoFar;
    if(remaining <= 0) continue;
    const pay = Math.min(available, remaining);
    const newPaid = paidSoFar + pay;
    const paidFull = newPaid >= Number(inv.amount) - 0.5;
    await db.collection('invoices').doc(String(inv.id)).set(Object.assign(
      { paidAmount: newPaid, status: paidFull ? 'paid' : 'partial', provider },
      paidFull ? { providerTrans: String(transId||''), paidAt: FieldValue.serverTimestamp() } : {}
    ), { merge:true });
    applied.push({ invoiceId: inv.id, amount: pay, status: paidFull ? 'paid' : 'partial' });
    available -= pay;
  }
  await db.collection('student_credit').doc(studentId).set(
    { studentId, credit: available, updatedAt: FieldValue.serverTimestamp() }, { merge:true });
  await logCredit(studentId, available - credit, available, (available-credit)>0?'overpay':'applied', provider);
  const result = { applied, leftover: available, usedCredit: credit };
  try{ await guardRef.set({ studentId, amount, result, createdAt: FieldValue.serverTimestamp() }); }catch(e){}
  return result;
  }catch(e){ try{ await guardRef.delete(); }catch(_){}   // mutatsiya xatosi -> band qilishni bo'shatamiz (qayta urinish mumkin)
    throw e; }
}

// Summani BITTA aniq invoice balansiga qo'llaydi (kabinet «Click» tugmasi / precise).
// paidAmount += amount; to'lsa -> paid, kam -> partial, ortiqcha -> student_credit. IDEMPOTENT.
async function applyToInvoice(invoiceId, amount, transId, provider){
  invoiceId = String(invoiceId||''); amount = Number(amount)||0; provider = provider || 'click';
  // [P0 tuzatildi] Supabase: ATOMIK + IDEMPOTENT apply_to_invoice RPC (aynan shu invoysга; ortiqcha ->
  // avans). Terminal (bekor/qaytarilgan)/topilmadi holatlarини {error:...} bilan qaytaradi (chaqiruvchi
  // buni o'quvchi balansiga fallback uchun ishlatadi). Eski JS yo'li atomik emas edi -> qisman-yozuv-keyin-
  // xato + posbon o'chirilishi ikki marta hisoblardi.
  if(db.rpc){
    const r = await db.rpc('apply_to_invoice', { p_invoice: invoiceId, p_amount: amount, p_provider: provider, p_pay_id: String(transId||'')||null });
    return (r && r.dup) ? { dup:true } : (r || {});
  }
  // ---- Firebase (rollback) — eski, atomik BO'LMAGAN inkremental JS ----
  const guardRef = db.collection('applied_payments').doc(String(transId||''));
  // ATOMIK band qilish (idempotentlik) — takroriy/bir vaqtli callback ikki marta hisoblamasin.
  try{ await guardRef.create({ amount, createdAt: FieldValue.serverTimestamp() }); }
  catch(e){ try{ const g = await guardRef.get(); return (g.data()||{}).result || { dup:true }; }catch(_){ return { dup:true }; } }
  const inv = await getInvoice(invoiceId); if(!inv){ try{ await guardRef.delete(); }catch(_){ } return { error:'notfound' }; }
  // Qaytarilgan/bekor qilingan hisob-fakturani qayta to'lash mumkin emas (refund tirilmasin).
  if(inv.status==='reversed' || inv.status==='canceled'){ try{ await guardRef.delete(); }catch(_){ } return { error:'terminal' }; }
  try{
  const paidSoFar = Number(inv.paidAmount)||0;
  const newPaid = paidSoFar + amount;
  const paidFull = newPaid >= Number(inv.amount) - 0.5;
  const overflow = Math.max(0, newPaid - Number(inv.amount));
  await db.collection('invoices').doc(invoiceId).set(Object.assign(
    { paidAmount: paidFull ? Number(inv.amount) : newPaid, status: paidFull ? 'paid' : 'partial', provider: provider||'click' },
    paidFull ? { providerTrans: String(transId||''), paidAt: FieldValue.serverTimestamp() } : {}
  ), { merge:true });
  if(overflow > 0 && inv.studentId){
    let cr = 0; try{ const c = await db.collection('student_credit').doc(String(inv.studentId)).get(); if(c.exists) cr = Number((c.data()||{}).credit)||0; }catch(e){}
    await db.collection('student_credit').doc(String(inv.studentId)).set({ studentId:String(inv.studentId), credit: cr + overflow, updatedAt: FieldValue.serverTimestamp() }, { merge:true });
    await logCredit(String(inv.studentId), overflow, cr + overflow, 'overpay', provider||'click');
  }
  const result = { invoiceId, applied: amount, status: paidFull ? 'paid' : 'partial', overflow, studentId: inv.studentId||'' };
  try{ await guardRef.set({ studentId: String(inv.studentId||''), amount, result, createdAt: FieldValue.serverTimestamp() }); }catch(e){}
  return result;
  }catch(e){ try{ await guardRef.delete(); }catch(_){}   // mutatsiya xatosi -> band qilishni bo'shatamiz
    throw e; }
}

// Uzum uchun: account = aniq invoice ID ({sid}__{oy}) yoki kod -> to'lanmagan invoice (eng eski). Qaytadi: { inv, via } —
//   via 'code_norm': kod egasi bo'yicha topilgan (uzCreate uni saqlanadigan raw'ga yozadi — Direktor ko'rsin).
async function resolveInvoiceByCode(rawId){
  rawId = String(rawId||'').trim(); if(!rawId) return { inv: null };
  if(rawId.includes('__')) return { inv: await getInvoice(rawId) };
  let at = await attributeStudent(rawId, {});            // kod-shaklli bo'lsa -> studentId
  if(!at.sid && at.via !== 'code_conflict'){ const sid = await ownerSid(await kodMasker(rawId), rawId); if(sid) at = { sid, via:'code_norm' }; }   // kiril / «O» / guruhlab yozilgan kod
  if(!at.sid) return { inv: null };
  const list = await unpaidInvoices(at.sid);
  return { inv: list[0] || null, via: at.via };
}

/* ---------- CLICK ---------- */
function clickSign(p, isComplete){
  const parts = [p.click_trans_id, p.service_id, CLICK.secretKey, p.merchant_trans_id];
  if(isComplete) parts.push(p.merchant_prepare_id);
  parts.push(p.amount, p.action, p.sign_time);
  return md5(parts.join(''));
}
const clickErr = (p, code, note, isComplete) => Object.assign(
  { click_trans_id: p.click_trans_id, merchant_trans_id: p.merchant_trans_id, error: code, error_note: note },
  isComplete ? { merchant_confirm_id: 0 } : { merchant_prepare_id: 0 });

// XAVFSIZLIK: Click faqat secretKey sozlangan VA service_id mos bo'lsagina ishlaydi.
// Aks holda (secret bo'sh/placeholder) imzoni soxtalashtirib istalgan hisob-fakturani
// «to'landi» qilib bo'lardi. Fail-closed — sozlanmagan bo'lsa rad etiladi.
const clickReady = p => !!CLICK.secretKey && (!CLICK.serviceId || String(p.service_id) === String(CLICK.serviceId));

async function handlePrepare(p){
  if(!clickReady(p)) return clickErr(p, -1, 'SIGN CHECK FAILED', false);
  if(CFG.debugClick) console.error('[CLICK-DEBUG]', JSON.stringify({ ct:p.click_trans_id, sid:p.service_id, mti: await maskPayer(String(p.merchant_trans_id||'')), amt:p.amount, act:p.action, st:p.sign_time, sigMatch:(String(p.sign_string||'').toLowerCase()===clickSign(p,false)), hasSecret:!!CLICK.secretKey }));
  if(!tseq(clickSign(p, false), String(p.sign_string||'').toLowerCase())) return clickErr(p, -1, 'SIGN CHECK FAILED', false);
  const amount = Number(p.amount);
  if(!(amount > 0)) return clickErr(p, -2, 'Summa mos emas', false);
  const mti = String(p.merchant_trans_id || '');
  const prepareId = String(Date.now());
  const payRef = db.collection('payments').doc('click_' + p.click_trans_id);

  // A) ANIQ invoice ID (kabinet «Click» tugmasi).
  if(mti.includes('__')){
    const inv = await getInvoice(mti);
    if(inv && inv.status === 'paid') return clickErr(p, -4, 'Allaqachon to\'langan', false);
    if(inv){
      // Balans modeli: summa aynan mos kelishi shart emas — qolganiga (partial) yoki to'liq tushadi.
      //   Saqlanadigan nusxa — kod yashirilgan (javob esa Click'ning asl merchant_trans_id'si).
      await payRef.set({ provider:'click', click_trans_id:String(p.click_trans_id), merchant_trans_id: await maskPayer(mti),
        invoiceId:String(inv.id), studentId:String(inv.studentId||''), merchant_prepare_id:prepareId,
        amount, status:'prepared', matched:true, raw:{ mode:'precise' }, createdAt: FieldValue.serverTimestamp() });
      return { click_trans_id:p.click_trans_id, merchant_trans_id:mti, merchant_prepare_id:prepareId, error:0, error_note:'Success' };
    }
    // Invoice YO'Q (o'chirilgan / oy noto'g'ri) -> RAD ETMAYMIZ (to'lov yo'qolmasin). Pastga (ERKIN)
    // tushamiz: mti'даги o'quvchi ID sini ajratib, balansiga yoki biriktirilmagan sifatida qabul qilamiz.
  }

  // B) ERKIN to'lov (ism/telefon/kod + ixtiyoriy summa) -> BALANS modeli. HAR DOIM QABUL QILINADI
  //    (pul keladi -> yoziladi; biriktirilmasa admin biriktiradi). Attribution: kod yoki telefon.
  let at = await attributeStudent(mti, p);
  // precise mti (sid__oy) invoice topilmagan bo'lsa — o'quvchi ID sini ajratib olamiz (bor bo'lsa)
  if(!at.sid && mti.includes('__')){ const sidPart = mti.split('__')[0]; if(sidPart){ try{ const ui = await unpaidInvoices(sidPart); if(ui && ui.length) at = { sid: sidPart, via:'invoice-id' }; }catch(e){} } }
  // Biriktirish ASL matn bilan bo'ldi; saqlanadigan to'lovchi matni — kod yashirilgan (moliya rollari o'qiydi).
  const phone = String(p.param3||''), klass = String(p.param2||''), mask = await kodMasker(mti, phone, klass), mtiS = mask(mti);
  // Yuqoridagi qoidalar topmadi — matndagi kod(lar)ning yagona egasi (kiril / «O» harfli, guruhlab yozilgan kod); via 'code_norm'.
  //   'code_conflict' (telefon / ism boshqa o'quvchini ko'rsatdi) — yo'q: qo'lda biriktiriladi.
  if(!at.sid && at.via !== 'code_conflict'){ const sid = await ownerSid(mask, mti, phone, klass); if(sid) at = { sid, via:'code_norm' }; }
  await payRef.set({ provider:'click', click_trans_id:String(p.click_trans_id), merchant_trans_id:mtiS,
    studentId: at.sid || '', matched: !!at.sid, merchant_prepare_id:prepareId, amount, status:'prepared',
    payerName: mtiS, payerPhone: mask(phone), payerClass: mask(klass),
    raw:{ mode:'freeform', via: at.via }, createdAt: FieldValue.serverTimestamp() });
  return { click_trans_id:p.click_trans_id, merchant_trans_id:mti, merchant_prepare_id:prepareId, error:0, error_note:'Success' };
}
// Shu to'lov tranzaksiyasi allaqachon QO'LLANGANmi? (applied_payments posboni — apply_to_invoice / apply_payment
//   bir xil jadvalga yozadi). Topilsa — posbon id'si, aks holda null. O'qib bo'lmasa — null (eski xatti-harakat).
async function appliedGuard(ids){
  for(const id of ids){ if(!id) continue; try{ const g = await db.collection('applied_payments').doc(String(id)).get(); if(g.exists) return String(id); }catch(e){} }
  return null;
}
// MUHIM: payments jadvalida YO'Q ustunga yozish (masalan note/appliedTo) -> PostgREST PGRST204 -> BUTUN yozuv
//   rad etiladi (status yangilanmaydi, webhook 500). Qo'shimcha belgilar shu sabab `raw` jsonb ichida saqlanadi.
const withRaw = (pay, extra) => Object.assign({}, (pay && pay.raw && typeof pay.raw === 'object') ? pay.raw : {}, extra);
// complete to'lovchi matnini YOZMAYDI: holat / summa / id va server o'zi tuzgan raw (mode, via, taqsimot, izoh) — so'rovdagi
//   merchant_trans_id saqlanmaydi; biriktirish prepare'da saqlangan studentId bilan (matn qayta o'qilmaydi).
async function handleComplete(p){
  if(!clickReady(p)) return clickErr(p, -1, 'SIGN CHECK FAILED', true);
  if(!tseq(clickSign(p, true), String(p.sign_string||'').toLowerCase())) return clickErr(p, -1, 'SIGN CHECK FAILED', true);
  const payRef = db.collection('payments').doc('click_' + p.click_trans_id);
  const paySnap = await payRef.get(); const pay = paySnap.exists ? paySnap.data() : null;
  if(!pay || String(pay.merchant_prepare_id) !== String(p.merchant_prepare_id)) return clickErr(p, -6, 'Tranzaksiya topilmadi', true);
  const confirmId = String(Date.now());
  // Idempotentlik AVVAL: yakuniy holatдаги (paid/applied/unmatched) to'lovni CANCEL/apply qilmaymiz
  // (kech kelgan error<0 to'langan to'lovni 'canceled' qilib invoice bilan nomuvofiqlik yaratmasin).
  if(pay.status === 'paid' || pay.status === 'applied' || pay.status === 'unmatched')
    return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_confirm_id:String(pay.merchant_confirm_id||confirmId), error:0, error_note:'Success' };
  if(Number(p.error) < 0){
    // Click BEKOR qildi. Avvalgi urinishda pul ALLAQACHON qo'llangan bo'lsa (RPC commit bo'lib, status yozuvi/javob
    //   yo'qolgan — masalan restart), faktura «to'langan» qolib, pul esa to'lovchiga qaytardi. Shuning uchun posbonni
    //   tekshiramiz: aynan shu fakturaga (precise) qo'llangan -> reverse_payment (atomik, idempotent 'reverse:click_'+id);
    //   balansga (waterfall) qo'llangan / faktura topilmadi / avans allaqachon sarflangan -> «qo'lda qaytarish» navbati.
    const ct = String(p.click_trans_id);
    const g = await appliedGuard([ct, ct+'_cr']);
    if(g){
      const som = Number(pay.amount)||Number(p.amount)||0;
      let note = '';
      if(((pay.raw && pay.raw.mode) || 'precise') === 'precise' && g === ct && pay.invoiceId && db.rpc){
        let rv = null;
        try{ const a = { p_invoice:String(pay.invoiceId), p_amount:som, p_provider:'click', p_ref:'click_'+ct };
          rv = await db.rpc('reverse_payment', a); if(rv && rv.error === 'retry') rv = await db.rpc('reverse_payment', a); }
        catch(e){ rv = { ok:false, error:String((e && (e.code||e.message)) || 'xato') }; }
        const unrec = Number(rv && rv.unrecovered)||0;
        if(rv && rv.ok === false) note = 'faktura '+String(pay.invoiceId)+' avtomatik qaytarilmadi ('+String(rv.error||rv.reason||'xato')+')';
        else if(unrec > 0.5) note = 'avans allaqachon sarflangan — '+unrec+' so‘m qaytarib olinmadi';
      } else note = 'pul o‘quvchi balansiga (eng eski qarz / avans) qo‘llangan edi';
      await payRef.set({ status:'canceled', raw: withRaw(pay, note
        ? { needsManualReverse:true, reverseNote:'Click bekor qildi: '+note+' — QO‘LDA tuzating (som='+som+', studentId='+String(pay.studentId||'')+')' }
        : { reversedApplied:true, needsManualReverse:false, reverseNote:'' }) }, { merge:true });   // qayta urinishda avtomatik qaytdi — eski belgi qolmasin
      return clickErr(p, -9, 'Transaction cancelled', true);
    }
    await payRef.set({ status:'canceled' }, { merge:true }); return clickErr(p, -9, 'Transaction cancelled', true);
  }
  const mode = (pay.raw && pay.raw.mode) || 'precise';

  if(mode === 'precise'){
    const inv = await getInvoice(String(pay.invoiceId||''));
    // Idempotentlik (qayta urinish): SHU tranzaksiya puli allaqachon qo'llangan bo'lsa (avvalgi urinishda RPC
    //   commit bo'lib, status yozuvi/javob yo'qolgan — masalan deploy paytidagi restart) — «Allaqachon
    //   to'langan» (-4) DEMAYMIZ: Click bu tranzaksiyani bekor qilib pulni qaytarardi, invoice esa to'langan
    //   bo'lib qolardi. Holatni yakunlab, MUVAFFAQIYAT qaytaramiz.
    const done = await appliedGuard([String(p.click_trans_id), String(p.click_trans_id)+'_cr']);
    if(done){
      await payRef.set(Object.assign({ status: (inv && !done.endsWith('_cr')) ? 'paid' : 'applied', merchant_confirm_id:confirmId },
        (inv && inv.studentId) ? { studentId:String(inv.studentId) } : {}), { merge:true });
      return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_confirm_id:confirmId, error:0, error_note:'Success' };
    }
    if(inv && inv.status === 'paid') return clickErr(p, -4, 'Allaqachon to\'langan', true);
    if(!inv){
      // Invoice prepare bilan complete orasида o'chirilgan -> pulni YO'QOTMAYMIZ.
      const amount = Number(pay.amount)||Number(p.amount)||0;
      if(pay.studentId){ await applyPaymentToStudent(String(pay.studentId), amount, p.click_trans_id);
        await payRef.set({ status:'applied', amount, merchant_confirm_id:confirmId }, { merge:true }); }
      else { await payRef.set({ status:'unmatched', amount, merchant_confirm_id:confirmId }, { merge:true }); }
      return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_confirm_id:confirmId, error:0, error_note:'Success' };
    }
    const ar = await applyToInvoice(String(pay.invoiceId), Number(p.amount)||0, p.click_trans_id);  // qolganiga/to'liq
    if(ar && ar.error){
      // backend[0]: invoice bekor/qaytarilgan (terminal) yoki topilmadi -> pulni YO'QOTMAYMIZ.
      // O'quvchining boshqa qarzlari/avansiga qo'llaymiz (aks holda pul qabul qilinib "paid" bo'lib,
      // hech qayerga qo'llanmasdan yo'qolardi).
      const amt2 = Number(p.amount)||Number(pay.amount)||0;
      if(inv.studentId){ await applyPaymentToStudent(String(inv.studentId), amt2, p.click_trans_id+'_cr');
        await payRef.set({ status:'applied', studentId:String(inv.studentId), amount:amt2, merchant_confirm_id:confirmId, raw: withRaw(pay, { note:'invoice terminal -> student balans' }) }, { merge:true }); }
      else { await payRef.set({ status:'unmatched', amount:amt2, merchant_confirm_id:confirmId }, { merge:true }); }
    } else {
      await payRef.set({ status:'paid', studentId:String(inv.studentId||''), merchant_confirm_id:confirmId }, { merge:true });
    }
  } else {
    // ERKIN: balans modeli. Biriktirilgan -> qo'llanadi (qisman/to'liq/avans); aks holda -> biriktirilmagan.
    const amount = Number(pay.amount) || Number(p.amount) || 0;
    let result = { applied:[], leftover:amount };
    if(pay.matched && pay.studentId) result = await applyPaymentToStudent(pay.studentId, amount, p.click_trans_id);
    await payRef.set({ status: (pay.matched && pay.studentId) ? 'applied' : 'unmatched', amount,
      raw: Object.assign({}, pay.raw||{}, { allocation: result.applied, credit: result.leftover }),
      merchant_confirm_id:confirmId }, { merge:true });
  }
  return { click_trans_id:p.click_trans_id, merchant_trans_id:p.merchant_trans_id, merchant_confirm_id:confirmId, error:0, error_note:'Success' };
}

/* ---------- UZUM MERCHANT API ---------- */
// Uzum bizning serverga 5 chaqiruv yuboradi (Basic auth): check → create →
// confirm (→ reverse / status). To'lov TASDIQLANGANDA (confirm) invoice «paid».
// Xato kodlari (Uzum Merchant API standarti):
const UZ = { AUTH:10001, PARSE:10002, UNKNOWN_OP:10003, NOT_ENOUGH_PARAMS:10005,
             INVALID_SERVICE:10006, ALREADY_PAID:10007, NOT_FOUND:10008, CANCELLED:10009, CHECK_ERROR:99999 };
const uzTs   = () => Date.now();
const uzFail = code => ({ serviceId: UZUM.serviceId, timestamp: uzTs(), status:'FAILED', errorCode: code });

// Basic auth: Authorization: Basic base64(login:password) — kabinetdagi kalitlar.
function uzumAuthOK(headers){
  const h = String((headers||{}).authorization || '');
  if(!/^Basic\s+/i.test(h)) return false;
  let dec=''; try{ dec = Buffer.from(h.replace(/^Basic\s+/i,''), 'base64').toString('utf8'); }catch(e){ return false; }
  const i = dec.indexOf(':'); if(i < 0) return false;
  return !!UZUM.login && !!UZUM.password && tseq(dec.slice(0,i), UZUM.login) && tseq(dec.slice(i+1), UZUM.password);
}
// Hisob-faktura id sini Uzum `params` ichidan oladi (kabinetda belgilangan maydon).
function uzInvoiceId(params){
  if(!params || typeof params !== 'object') return null;
  const keys = [UZUM.accountField, 'invoice', 'invoiceId', 'order', 'orderId', 'account'].filter(Boolean);
  for(const k of keys){ if(params[k] != null && params[k] !== '') return String(params[k]); }
  const vals = Object.values(params); return vals.length ? String(vals[0]) : null;
}
// Uzum summasi (default: tiyin = so'm×100) hisob-faktura summasiga mos keladimi.
function uzAmountOK(bodyAmount, invAmount){
  const a = Number(bodyAmount);
  return UZUM.amountUnit === 'som' ? amtEq(a, invAmount) : amtEq(a, Number(invAmount) * 100);
}
const uzPayRef = transId => db.collection('payments').doc('uzum_' + String(transId));
// Saqlangan raw'ni (Uzum so'rovi) qayta yozishda ham kod yashiriladi — eski server (deploy oralig'ida) yozgan matn ham.
const uzRaw = async (pay, extra) => maskPayer(withRaw(pay, extra));

async function uzCheck(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const raw = uzInvoiceId(b.params); if(!raw) return uzFail(UZ.NOT_ENOUGH_PARAMS);
  const { inv } = await resolveInvoiceByCode(raw); if(!inv) return uzFail(UZ.NOT_FOUND);
  if(inv.status === 'paid') return uzFail(UZ.ALREADY_PAID);
  if(inv.status === 'reversed' || inv.status === 'canceled') return uzFail(UZ.CANCELLED);   // qaytarilgan/bekor -> qayta to'lanmaydi
  // Qolgan balansga tekshiramiz (qisman to'langan hisobни ham Uzum bilan yopish mumkin bo'lsin).
  if(b.amount != null && !uzAmountOK(b.amount, (Number(inv.amount)||0)-(Number(inv.paidAmount)||0))) return uzFail(UZ.CHECK_ERROR);
  return { serviceId: UZUM.serviceId, timestamp: uzTs(), status:'OK',
           data: { account: { invoice: inv.id, month: inv.month || '', student: inv.studentName || '' } } };
}
async function uzCreate(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const raw = uzInvoiceId(b.params); if(!raw) return uzFail(UZ.NOT_ENOUGH_PARAMS);
  const { inv, via } = await resolveInvoiceByCode(raw); if(!inv) return uzFail(UZ.NOT_FOUND);
  if(inv.status === 'paid') return uzFail(UZ.ALREADY_PAID);
  if(inv.status === 'reversed' || inv.status === 'canceled') return uzFail(UZ.CANCELLED);   // qaytarilgan/bekor -> qayta to'lanmaydi
  if(!uzAmountOK(b.amount, (Number(inv.amount)||0)-(Number(inv.paidAmount)||0))) return uzFail(UZ.CHECK_ERROR);
  // Idempotentlik: allaqachon yakuniy holatdagi tranzaksiyani 'created'ga qaytarmaymiz.
  const _ex = await uzPayRef(b.transId).get();
  if(_ex.exists && (_ex.data().status === 'confirmed' || _ex.data().status === 'reversed'))
    return { serviceId: UZUM.serviceId, timestamp: uzTs(), status:'CREATED', transTime: uzTs(), transId: b.transId, amount: b.amount };
  // MUHIM: payments qatorini SO'M da saqlaymiz (admin «Moliya tekshiruvi»/«To'lovlar tarixi» so'mda
  // o'qiydi). Uzum tiyin (so'm×100) yuboradi — shu yerda normallashtiramiz; protokol javoblari
  // (create/reverse response) b.amount (tiyin) qoladi. Invoice qo'llash pastda so'mda ishlaydi.
  const som = UZUM.amountUnit === 'som' ? Number(b.amount) : Number(b.amount)/100;
  // raw — Uzum so'rovi (params.account'da to'lovchi kodi bo'lishi mumkin): kod yashirilgan nusxa saqlanadi. Kod egasi bo'yicha topilgan
  //   faktura (guruhlab / kiril harfli kod) — raw.via = 'code_norm' (Click'dagi kabi; confirm / reverse withRaw bilan saqlaydi).
  await uzPayRef(b.transId).set({ provider:'uzum', transId:String(b.transId), invoiceId:String(inv.id),
    studentId: inv.studentId || '', amount:som, status:'created',
    raw: await maskPayer(via === 'code_norm' ? Object.assign({}, b, { via }) : b), createdAt: FieldValue.serverTimestamp() });
  return { serviceId: UZUM.serviceId, timestamp: uzTs(), status:'CREATED', transTime: uzTs(), transId: b.transId, amount: b.amount };
}
async function uzConfirm(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const snap = await uzPayRef(b.transId).get(); const pay = snap.exists ? snap.data() : null;
  if(!pay) return uzFail(UZ.NOT_FOUND);
  // Yakuniy holat (qaytarilgan/bekor) — confirm qayta to'lamaydi.
  if(pay.status === 'reversed' || pay.status === 'canceled') return uzFail(UZ.CANCELLED);
  if(pay.status !== 'confirmed'){
    // Idempotentlik (qayta urinish): shu tranzaksiya puli ALLAQACHON qo'llangan (avvalgi urinishda RPC commit bo'lib,
    //   status yozuvi/javob yo'qolgan) — qayta qo'llamaymiz, holatni yakunlaymiz (Click complete bilan bir xil). Aks holda
    //   oraliqda faktura bekor bo'lsa, ikkinchi urinish pulni '_cr' kaliti bilan o'quvchi balansiga YANA qo'shardi.
    const done = await appliedGuard(['uzum_'+b.transId, 'uzum_'+b.transId+'_cr']);
    if(done){
      await uzPayRef(b.transId).set({ status:'confirmed', raw: await uzRaw(pay, { appliedTo: done.endsWith('_cr') ? 'balance' : 'invoice' }) }, { merge:true });
      return { serviceId: UZUM.serviceId, transId: b.transId, status:'CONFIRMED', confirmTime: uzTs() };
    }
    // pay.amount endi SO'M da saqlanadi (uzCreate normallashtiradi) — to'g'ridan-to'g'ri qo'llaymiz.
    const ar = await applyToInvoice(pay.invoiceId, Number(pay.amount)||0, 'uzum_'+b.transId, 'uzum');   // inkremental: qisman to'lovni to'g'ri qo'llaydi, ortiqcha -> avans
    // backend[1]: create->confirm orasида invoice bekor/qaytarilgan bo'lsa pulni yo'qotmaymiz -> o'quvchi balansiga.
    // QAYSI YO'L ishlaganini YOZAMIZ (appliedTo) — reverse paytida to'g'ri target tanlash uchun:
    //   'invoice' -> reverse_payment(invoice); 'balance' -> waterfall (teskarisi qo'lda).
    //   (appliedTo/note `raw` ichida — payments jadvalida bunday ustun YO'Q: alohida ustunga yozish PGRST204
    //   berib, status 'confirmed' bo'lmay qolardi -> Uzum'ga xato, pul esa allaqachon qo'llangan.)
    let appliedTo = 'invoice', note = '';
    if(ar && ar.error){
      appliedTo = 'balance';
      if(pay.studentId){ await applyPaymentToStudent(String(pay.studentId), Number(pay.amount)||0, 'uzum_'+b.transId+'_cr', 'uzum'); }
      else { note = 'invoice terminal, studentId yo‘q — qo‘lda biriktiring'; }
    }
    await uzPayRef(b.transId).set({ status:'confirmed', raw: await uzRaw(pay, note ? { appliedTo, note } : { appliedTo }) }, { merge:true });
  }
  return { serviceId: UZUM.serviceId, transId: b.transId, status:'CONFIRMED', confirmTime: uzTs() };
}
async function uzReverse(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const snap = await uzPayRef(b.transId).get(); const pay = snap.exists ? snap.data() : null;
  if(!pay) return uzFail(UZ.NOT_FOUND);
  if(pay.status !== 'reversed'){
    // Pul QO'LLANGAN to'lovgina invoice/avansga ta'sir qilgan. Butun paidAmount'ni 0 qilmaymiz — AYNAN shu
    // tranzaksiya summasini ayiramiz (boshqa to'lovlar saqlanadi), ortiqcha (avans) qismini student_credit'dan
    // qaytarib olamiz. confirmed -> qo'llangan (appliedTo bo'yicha). confirmed EMAS bo'lsa ham posbonni tekshiramiz:
    // confirm'da RPC commit bo'lib, status yozuvi yo'qolgan (restart) bo'lsa pul turibdi — aks holda faktura
    // «to'langan» qolib, Uzum esa pulni to'lovchiga qaytarardi.
    let applied = (pay.status === 'confirmed') ? (((pay.raw && pay.raw.appliedTo) || pay.appliedTo) || 'invoice') : null;
    if(!applied){ const g = await appliedGuard(['uzum_'+b.transId, 'uzum_'+b.transId+'_cr']); if(g) applied = g.endsWith('_cr') ? 'balance' : 'invoice'; }
    if(applied){
      const som = Number(pay.amount)||0;   // pay.amount SO'M da saqlangan (uzCreate)
      if(applied === 'balance'){
        // Pul invoice'ga EMAS, o'quvchi BALANSIGA qo'llangan edi (confirm paytida invoice terminal bo'lgan).
        // reverse_payment(invoice) bu yerda NOTO'G'RI — u aloqasiz invoice/avansni buzadi. Balansga
        // qo'llangan to'lovni teskari qilish (waterfall'ni ochib) avtomatik qilinmaydi; MA'MURIYATga
        // belgilab qo'yamiz (needsManualReverse) va Uzum'ga REVERSED qaytaramiz (webhook xato bermasin).
        await uzPayRef(b.transId).set({ status:'reversed', raw: await uzRaw(pay, { needsManualReverse:true,
          reverseNote:'Pul o‘quvchi balansiga qo‘llangan edi — QO‘LDA qaytaring (som='+som+', studentId='+String(pay.studentId||'')+')' }) }, { merge:true });
        return { serviceId: UZUM.serviceId, transId: b.transId, status:'REVERSED', reverseTime: uzTs(), amount: (UZUM.amountUnit==='som'?som:som*100) };
      }
      if(db.rpc){
        // [High B tuzatildi] ATOMIK + IDEMPOTENT reverse_payment RPC: invoice↓ + avans clawback +
        // credit_ledger — BITTA tranzaksiya (advisory lock + 'reverse:'+ref posbon). Eski JS yo'li
        // 4 alohida yozuv edi -> crash/parallel'da invoice ikki marta kamayishi mumkin edi.
        // p_ref noyob (transId) -> webhook retry ikki marta pulни qaytarmaydi ({dup:true}).
        const rvArgs = { p_invoice: String(pay.invoiceId), p_amount: som, p_provider: 'uzum', p_ref: 'uzum_'+String(b.transId) };
        let rv = await db.rpc('reverse_payment', rvArgs);
        if(rv && rv.error === 'retry') rv = await db.rpc('reverse_payment', rvArgs);   // qulf ostida kalit o'zgargan (juda kam) — bir marta qayta
        // To'liq avtomatik qaytarilmadi: faktura topilmadi (o'chirilgan) yoki ortiqcha qism avansdan olinmadi (avans
        //   allaqachon sarflangan) — jim yo'qolmasin: «qo'lda qaytarish» navbatiga (admin «↩️ Qo'lda qaytarilishi kerak»).
        const unrec = Number(rv && rv.unrecovered)||0;
        if((rv && rv.ok === false) || unrec > 0.5){
          const why = (rv && rv.ok === false) ? ('faktura '+String(pay.invoiceId)+' avtomatik qaytarilmadi ('+String(rv.error||rv.reason||'xato')+')')
                                              : ('avans allaqachon sarflangan — '+unrec+' so‘m qaytarib olinmadi');
          await uzPayRef(b.transId).set({ status:'reversed', raw: await uzRaw(pay, { needsManualReverse:true,
            reverseNote:'Uzum qaytardi: '+why+' — QO‘LDA tuzating (som='+som+', studentId='+String(pay.studentId||'')+')' }) }, { merge:true });
          return { serviceId: UZUM.serviceId, transId: b.transId, status:'REVERSED', reverseTime: uzTs(), amount: (UZUM.amountUnit==='som'?som:som*100) };
        }
      } else {
        // ---- Firebase (rollback) — eski, atomik BO'LMAGAN yo'l ----
        const inv = await getInvoice(String(pay.invoiceId));
        if(inv){
          const amt = Number(inv.amount)||0, paid0 = Number(inv.paidAmount)||0;
          const fromInvoice = Math.min(som, paid0);            // paidAmount'dan ayiriladigan qism
          const fromCredit  = Math.max(0, som - fromInvoice);  // ortiqcha -> avansdan qaytariladi
          const newPaid = Math.max(0, paid0 - fromInvoice);
          const status = newPaid<=0 ? 'reversed' : (newPaid >= amt-0.5 ? 'paid' : 'partial');
          await db.collection('invoices').doc(String(pay.invoiceId)).set(
            { paidAmount:newPaid, status, reversedAt: FieldValue.serverTimestamp() }, { merge:true });
          if(fromCredit>0 && inv.studentId){
            let cr=0; try{ const c=await db.collection('student_credit').doc(String(inv.studentId)).get(); if(c.exists) cr=Number((c.data()||{}).credit)||0; }catch(e){}
            await db.collection('student_credit').doc(String(inv.studentId)).set({ studentId:String(inv.studentId), credit:Math.max(0,cr-fromCredit), updatedAt: FieldValue.serverTimestamp() }, { merge:true });
            await logCredit(String(inv.studentId), -fromCredit, Math.max(0,cr-fromCredit), 'reversed', 'uzum');
          }
        }
      }
    }
    await uzPayRef(b.transId).set({ status:'reversed' }, { merge:true });
  }
  return { serviceId: UZUM.serviceId, transId: b.transId, status:'REVERSED', reverseTime: uzTs(), amount: (UZUM.amountUnit==='som'?Number(pay.amount)||0:(Number(pay.amount)||0)*100) };
}
async function uzStatus(b){
  if(String(b.serviceId) !== String(UZUM.serviceId)) return uzFail(UZ.INVALID_SERVICE);
  const snap = await uzPayRef(b.transId).get(); const pay = snap.exists ? snap.data() : null;
  if(!pay) return uzFail(UZ.NOT_FOUND);
  const map = { created:'CREATED', confirmed:'CONFIRMED', reversed:'REVERSED' };
  return { serviceId: UZUM.serviceId, transId: b.transId, status: map[pay.status] || 'CREATED' };
}
async function handleUzum(op, body){
  switch(op){
    case 'check':   return uzCheck(body);
    case 'create':  return uzCreate(body);
    case 'confirm': return uzConfirm(body);
    case 'reverse': return uzReverse(body);
    case 'status':  return uzStatus(body);
    default:        return uzFail(UZ.UNKNOWN_OP);
  }
}

/* ---------- HTTP server ---------- */
// Log uchun shaxsiy ma'lumotni yashirish (debug loglari yoqilib qolsa ham PII oqib ketmasin).
function redactPII(o){
  if(!o || typeof o!=='object') return o;
  const SENS=/name|fio|phone|tel|passport|pinfl|jshshir|address|manzil|guardian/i;
  const out=Array.isArray(o)?[]:{};
  for(const k of Object.keys(o)){ const v=o[k];
    if(SENS.test(k)) out[k]='***';
    else if(v && typeof v==='object') out[k]=redactPII(v);
    else out[k]=v; }
  return out;
}
const MAX_BODY = 8e6;   // ~8 MB chegara (Hik multipart hodisasi ham shu ichida)
// Tanani o'qish — HECH QACHON osilib qolmaydi: end/error/aborted/close hammasi resolve qiladi.
//   Chegaradan oshsa {tooLarge:true} qaytaradi (chaqiruvchi 413 beradi), req.destroy()dan keyin
//   'end' kelmasdi va await abadiy osilib qolardi.
function readBody(req){ return new Promise(resolve=>{
  const chunks=[]; let len=0, done=false, tooLarge=false;
  const finish=()=>{ if(done) return; done=true; resolve({ raw: tooLarge?'':Buffer.concat(chunks).toString('utf8'), tooLarge }); };
  req.on('data',c=>{ len+=c.length; if(len>MAX_BODY){ tooLarge=true; try{ req.destroy(); }catch(_){}; return finish(); } chunks.push(c); });
  req.on('end',finish);
  req.on('error',finish);
  req.on('aborted',finish);
  req.on('close',finish);
}); }
function parseBody(raw, ctype){
  if((ctype||'').includes('application/json')){ try{ return JSON.parse(raw||'{}'); }catch(e){ return {}; } }
  return Object.fromEntries(new URLSearchParams(raw||''));
}
// ---------- Hikvision yuz terminali: xodimlar keldi-ketdi + tanaffus ----------
function hikMapStatus(v){
  const x=String(v||'').toLowerCase().replace(/[\s_-]/g,'');
  if(x==='checkin') return 'in';
  if(x==='checkout') return 'out';
  if(x==='breakout') return 'break_out';
  if(x==='breakin') return 'break_in';
  return x||'unknown';
}
// Xom tanadan BALANSLANGAN {...} JSON bloklarini ajratadi (multipart + bitta POSTda bir nechta hodisa).
//   Qavs chuqurligини sanaydi; satr ("...") ichidagi qavs/tirnoqlar hisobga olinmaydi.
function hikJsonBlocks(s){
  s=String(s||''); const out=[]; let depth=0, start=-1, inStr=false, esc=false;
  for(let i=0;i<s.length;i++){ const c=s[i];
    if(inStr){ if(esc) esc=false; else if(c==='\\') esc=true; else if(c==='"') inStr=false; continue; }
    if(c==='"'){ inStr=true; continue; }
    if(c==='{'){ if(depth===0) start=i; depth++; }
    else if(c==='}'){ if(depth>0){ depth--; if(depth===0 && start>=0){ out.push(s.slice(start,i+1)); start=-1; } } }
  }
  return out;
}
// Bitta parsed obyektdan davomat maydonlari.
function hikFields(ev){
  const ace=(ev && (ev.AccessControllerEvent||ev.accessControllerEvent))||ev||{};
  return {
    personId:String(ace.employeeNoString||ace.employeeNo||ace.userID||ace.empNo||'').trim(),
    name:String(ace.name||ev.name||'').trim(),
    status:hikMapStatus(ace.attendanceStatus||ev.attendanceStatus||''),
    ts:String(ev.dateTime||ace.dateTime||ev.time||'').trim(),
    serial:String(ace.serialNo||ev.serialNo||'').trim(),
    device:String(ev.macAddress||ev.ipAddress||ev.deviceID||ace.deviceName||ace.devIndex||ev.devIndex||'').trim(),
    raw:ev
  };
}
// Barqaror (deterministik), QURILMA bilan nomlangan hodisa IDsi — idempotentlik uchun.
//   serialNo bir qurilmada noyob, lekin TURLI qurilmalarda takrorlanishi mumkin -> qurilma bilan namespace.
//   serial bo'lmasa: Date.now() ISHLATILMAYDI (qayta kelgan hodisa yangi ID olib DUBL bo'lardi);
//   o'rniga ts yoki xom hodisadan barqaror kalit.
function hikEventId(ev){
  const dev=(String(ev.device||'').replace(/[^0-9A-Za-z._:-]/g,'')) || 'dev';
  if(ev.serial) return 'hik_'+dev+'_'+ev.serial;
  const tms=Date.parse(ev.ts);
  if(ev.ts && !isNaN(tms)) return 'hik_'+dev+'_'+ev.personId+'_'+tms+'_'+ev.status;
  const h=crypto.createHash('sha1').update(dev+'|'+ev.personId+'|'+ev.status+'|'+JSON.stringify(ev.raw||'')).digest('hex').slice(0,16);
  return 'hik_'+dev+'_'+ev.personId+'_'+h;
}
// Xom tanadan hodisa(lar) massivi: JSON bloklar -> har biri; bo'lmasa butun JSON; bo'lmasa XML.
function hikEvents(raw){
  const s=String(raw||''); const evs=[];
  for(const b of hikJsonBlocks(s)){ try{ const o=JSON.parse(b); if(o && typeof o==='object') evs.push(hikFields(o)); }catch(_){} }
  if(evs.length) return evs;
  try{ const o=JSON.parse(s); if(o && typeof o==='object') return [hikFields(o)]; }catch(_){}
  const g=t=>{ const m=s.match(new RegExp('<'+t+'>([^<]*)</'+t+'>','i')); return m?m[1].trim():''; };
  return [{ personId:(g('employeeNoString')||g('employeeNo')).trim(), name:g('name'), status:hikMapStatus(g('attendanceStatus')), ts:g('dateTime')||g('time'), serial:g('serialNo')||g('serialNumber'), raw:{ xml:s.slice(0,2000) } }];
}
// Eski nom (test/moslik uchun) — bitta hodisa.
function hikParse(raw){ return hikEvents(raw)[0] || { personId:'', name:'', status:'unknown', ts:'', serial:'', raw:null }; }
function hikDay(ts){ const m=String(ts||'').match(/^(\d{4}-\d{2}-\d{2})/); if(m) return m[1];
  try{ return new Date(ts||Date.now()).toISOString().slice(0,10); }catch(e){ return new Date().toISOString().slice(0,10); } }
// Istalgan vaqtni Asia/Tashkent (+05:00, DST yo'q) formatiga keltiradi:
//   tz-ko'rsatilgan (Z yoki ±offset) -> o'sha instant +05:00 da; naive (offsetsiz) -> allaqachon mahalliy.
function toTashkent(raw){
  const s=String(raw||'').trim(); if(!s) return null; const p=n=>String(n).padStart(2,'0');
  if(/[zZ]$|[+-]\d{2}:?\d{2}$/.test(s)){ const d=new Date(s); if(isNaN(d)) return null; const z=new Date(d.getTime()+5*3600000);
    return `${z.getUTCFullYear()}-${p(z.getUTCMonth()+1)}-${p(z.getUTCDate())}T${p(z.getUTCHours())}:${p(z.getUTCMinutes())}:${p(z.getUTCSeconds())}+05:00`; }
  const m=s.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?/);
  if(m) return `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]||'00'}+05:00`;
  return null;
}
async function handleHikEvent(raw){
  const evs=hikEvents(raw);
  // RAW tana ataylab LOGLANMAYDI — Hik multipart ichida yuz-shabloni (biometrik) / ism bo'lishi mumkin.
  if(HIK.debug) console.error('[HIK-EVENT]', JSON.stringify(evs.map(e=>({pid:e.personId,status:e.status,ts:e.ts,serial:e.serial,device:e.device}))));
  let written=0, skipped=0; const ids=[];
  for(const ev of evs){
    // FAQAT attributlanadigan davomat skani yoziladi: shaxs ID SHART.
    //   Eshik/tizim hodisalari va notanish yuz (employeeNo yo'q) -> o'tkazib yuboriladi.
    if(!ev.personId){ skipped++; continue; }
    const id=hikEventId(ev);   // qurilma bilan namespace + deterministik (idempotentlik)
    // Vaqtni DOIM Asia/Tashkent (+05:00, DST yo'q) ga keltiramiz -> sayt mahalliy soatni to'g'ri
    //   ko'rsatadi. Qurilma UTC (...Z) yuborsa — +5 soat suriladi; +05:00 yuborsa — o'zgarmaydi;
    //   offsetsiz (naive) yuborsa — allaqachon mahalliy deb olinadi. (Ilgari ev.ts as-is saqlanib,
    //   qurilma UTC yuborganda 07:37 -> 02:37 bo'lib ko'rinardi.)
    const tsStr = toTashkent(ev.ts) || toTashkent(new Date().toISOString());
    try{
      await db.collection('staff_checkins').doc(id).set({
        id, personId:ev.personId, name:ev.name, status:ev.status, ts:tsStr, day:hikDay(tsStr), raw:ev.raw, createdAt: FieldValue.serverTimestamp()
      }, { merge:true });
      written++; ids.push(id);
    }catch(e){ console.error('[HIK] yozishda xato:', e.message); }
  }
  return { ok:true, written, skipped, ids };
}

if(require.main === module){
  const PORT = Number(CFG.port || 8790);
  const server = http.createServer(async (req, res) => {
    if(req.method === 'GET' && req.url === '/health'){ res.writeHead(200); return res.end('ok'); }
    if(req.method !== 'POST'){ res.writeHead(405); return res.end('POST kutiladi'); }
    const { raw, tooLarge } = await readBody(req);
    if(tooLarge){ res.writeHead(413); return res.end('payload too large'); }
    const body = parseBody(raw, req.headers['content-type']);
    // DIAGNOSTIKA: Click/Uzum aynan nima yuborishini ko'rish uchun (config.json: "debugPay": true).
    // Aniqlab bo'lgach o'chiring — loglar shaxsiy ma'lumot (ism/telefon/summa) o'z ichiga oladi.
    //   To'lovchi matnidagi maxfiy kod logda ham «[kod]» (maskPayer).
    if(CFG.debugPay && /^\/(click|uzum)\//.test(req.url)) console.error('[PAY-BODY]', req.url, JSON.stringify(await maskPayer(redactPII(body))));
    const send = obj => { res.writeHead(200, { 'Content-Type':'application/json' }); res.end(JSON.stringify(obj)); };
    try{
      if(req.url.startsWith('/click/prepare'))       send(await handlePrepare(body));
      else if(req.url.startsWith('/click/complete')) send(await handleComplete(body));
      else if(req.url.startsWith('/uzum/')){
        if(!uzumAuthOK(req.headers)){ res.writeHead(401, { 'Content-Type':'application/json' }); return res.end(JSON.stringify(uzFail(UZ.AUTH))); }
        const op = (req.url.split('?')[0].split('/')[2] || '');
        send(await handleUzum(op, body));
      }
      else if(req.url.startsWith('/hik/')){
        // Hikvision yuz terminali -> xodimlar keldi-ketdi. URL'dagi maxfiy segment bilan himoyalangan
        //   (qurilma qo'shimcha auth yubora olmaydi). Hodisa RAW tanada (multipart/XML/JSON).
        const seg = (req.url.split('?')[0].split('/')[2] || '');
        if(!HIK.secret || !tseq(seg, HIK.secret)){ res.writeHead(404); return res.end('not found'); }
        send(await handleHikEvent(raw));
      }
      else { res.writeHead(404); res.end('not found'); }
    }catch(e){ console.error('Xatolik:', e.message); res.writeHead(500); res.end('xatolik'); }
  });
  // FAQAT localhost — nginx (TLS) shu portga proxy qiladi. Provayder webhooklari api.iqror.uz (nginx) orqali keladi.
  server.listen(PORT, '127.0.0.1', () => console.log(`Iqror to'lov serveri tinglayapti 127.0.0.1:${PORT}  (/uzum/{check,create,confirm,reverse,status}, /click/prepare, /click/complete)`));
}

module.exports = { handlePrepare, handleComplete, handleUzum, uzumAuthOK, clickSign, md5, hikParse, hikEvents, hikFields, hikMapStatus, hikEventId, handleHikEvent, readBody, redactPII, maskPayer };
