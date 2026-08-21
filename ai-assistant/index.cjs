/**
 * Iqror — AI YORDAMCHI (assistant)
 * -------------------------------------------------------------------
 * Uchta vazifa (barchasi Claude AI orqali, serverda):
 *   1) chat            — sayt uchun ota-onalar yordamchisi (FAQ + qabul).
 *                        Faqat maktab ma'lumoti asosida javob beradi (UZ/RU).
 *   2) studentSummary  — bitta o'quvchi bo'yicha ota-onaga tushunarli oylik
 *                        xulosa (davomat/baho/monitoring/to'lov) yozadi.
 *   3) risk            — orqada qolayotgan o'quvchilarni aniqlaydi (qoida) va
 *                        har biriga qisqa AI tavsiya beradi.
 *
 * Kalit faqat shu serverda (config.json / ANTHROPIC_API_KEY). Saytga tushmaydi.
 * Firestore'ni Admin SDK orqali o'qiydi. HTTPS orqasida ishlating (CORS bor).
 *
 * Ishga tushirish:
 *   npm install
 *   cp config.example.json config.json     # kalit + service account + allowOrigin
 *   node index.cjs test                     # kalit ishlaydimi
 *   node index.cjs serve                     # HTTP server (/chat, /student-summary, /risk)
 *
 * Batafsil: README.md
 */
const fs = require('fs');
const path = require('path');
const http = require('http');

const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
// Data qatlami: CFG.backend='supabase' -> Supabase, aks holda Firebase (rollback).
const { db, verifyToken } = require('../server/backend.js')({ ...CFG, __dir: __dirname });
const MODEL = CFG.model || 'claude-opus-4-8';
const RISK_ATT = Number(CFG.riskAttendance) || 80;   // davomat % — shundan past = xavf
const RISK_SCORE = Number(CFG.riskScore) || 60;      // umumiy ball — shundan past = xavf

const num = v => { const n = Number(v); return isNaN(n) ? null : n; };
const fmtSom = n => (Number(n)||0).toLocaleString('ru-RU').replace(/,/g,' ') + ' so‘m';

/* ---------------- Claude ---------------- */
let _client = null, _key = null;
// Kalit: config.json → ANTHROPIC_API_KEY → Firestore secrets/ai (admin paneldan kiritilgan).
// secrets/ai ni faqat server (Admin SDK) o'qiy oladi; mijozlarga qoidada taqiqlangan.
async function apiKey(){
  if(_key) return _key;
  _key = CFG.anthropicKey || process.env.ANTHROPIC_API_KEY || '';
  if(!_key){ try{ const s = await db.collection('secrets').doc('ai').get(); if(s.exists) _key = s.data().anthropicKey || ''; }catch(e){} }
  return _key;
}
async function anthropic(){
  if(_client) return _client;
  const key = await apiKey();
  if(!key) throw new Error('Anthropic kaliti topilmadi (config.json, ANTHROPIC_API_KEY yoki secrets/ai — admin paneldan kiriting).');
  const Pkg = require('@anthropic-ai/sdk');
  const Anthropic = Pkg.default || Pkg;
  _client = new Anthropic({ apiKey: key });
  return _client;
}
async function askText(system, messages, maxTokens, effort){
  const r = await (await anthropic()).messages.create({
    model: MODEL, max_tokens: maxTokens || 700,
    thinking: { type: 'adaptive' },
    output_config: { effort: effort || 'medium' },
    system, messages
  });
  const block = (r.content || []).find(b => b.type === 'text');
  return ((block && block.text) || '').trim();
}

/* ---------------- Maktab bilimi (chatbot uchun kontekst) ---------------- */
let _kb = null, _kbAt = 0;
async function loadKnowledge(force){
  if(!force && _kb && (Date.now() - _kbAt) < 5*60*1000) return _kb;   // 5 daqiqa kesh
  const [site, plans, faq, adm, courses] = await Promise.all([
    db.collection('settings').doc('site').get().then(d=>d.exists?d.data():{}).catch(()=>({})),
    db.collection('plans').get().then(s=>s.docs.map(d=>d.data())).catch(()=>[]),
    db.collection('faq').get().then(s=>s.docs.map(d=>d.data())).catch(()=>[]),
    db.collection('admission_steps').get().then(s=>s.docs.map(d=>d.data())).catch(()=>[]),
    db.collection('directions').get().then(s=>s.docs.map(d=>d.data())).catch(()=>[])
  ]);
  const c = site.contact || {};
  const lines = [];
  lines.push('MAKTAB: Iqror Academy — natijaga yo‘naltirilgan zamonaviy maktab (IT va MED yo‘nalishlari).');
  if(c.address) lines.push('Manzil: ' + c.address);
  if(c.phone)   lines.push('Telefon: ' + c.phone);
  if(c.telegram)lines.push('Telegram: ' + c.telegram);
  if(c.hours)   lines.push('Ish vaqti: ' + c.hours);
  if(plans.length){ lines.push('\nNARXLAR (tariflar):');
    plans.forEach(p=>{ lines.push(`- ${p.name_uz||p.name_ru||''}: ${p.price||''} (oyiga). ${(p.features_uz||'').replace(/\n/g,', ')}`); }); }
  if(courses.length){ lines.push('\nYO‘NALISHLAR:'); courses.forEach(d=>lines.push(`- ${d.title_uz||d.name_uz||d.title||''}: ${d.desc_uz||d.text_uz||''}`)); }
  if(adm.length){ lines.push('\nQABUL BOSQICHLARI:'); adm.forEach((a,i)=>lines.push(`${a.num||i+1}. ${a.title_uz||''} — ${a.text_uz||''}`)); }
  if(faq.length){ lines.push('\nTEZ-TEZ BERILADIGAN SAVOLLAR:'); faq.forEach(f=>lines.push(`S: ${f.q_uz||''}\nJ: ${f.a_uz||''}`)); }
  _kb = lines.join('\n'); _kbAt = Date.now();
  return _kb;
}

/* ---------------- AI (test uchun mock berish mumkin) ---------------- */
function makeAI(){
  return {
    async chat(history, message, knowledge){
      const system = `Siz "Iqror Academy" xususiy maktabining rasmiy yordamchisisiz. Vazifangiz — ota-onalar va abituriyentlarning savollariga do'stona, aniq va qisqa javob berish.
QAT'IY QOIDALAR:
- FAQAT quyidagi maktab ma'lumotidan foydalaning. Ma'lumotda bo'lmagan narsani O'YLAB TOPMANG (ayniqsa narx, sana, kafolat). Bilmasangiz: "Bu savolga aniq javob uchun ma'muriyatga murojaat qiling" deb ayting va telefon/telegramni bering.
- Foydalanuvchi qaysi tilda yozsa (o'zbek yoki rus), o'sha tilda javob bering.
- Siyosat, din, maktabga aloqasiz mavzularга kirmang — muloyim rad eting.
- Javob 1-4 jumla, aniq. Kerak bo'lsa qabul (ariza) qoldirishni taklif qiling.
- KO'RINISH: javobni ODDIY MATN bilan yozing. Markdown ishlatmang — ** yoki * (qalin/kursiv), # (sarlavha) va boshidagi - / * (ro'yxat) belgilarini QO'YMANG. Ro'yxat kerak bo'lsa, har bandni yangi qatordan « • » belgisi bilan boshlang. Narxlarni « • Nomi: 1 900 000 so'm/oy » ko'rinishida yozing.

MAKTAB MA'LUMOTI:
${knowledge}`;
      const msgs = [];
      (history||[]).slice(-8).forEach(m=>{ if(m && m.content) msgs.push({ role: m.role==='assistant'?'assistant':'user', content: String(m.content).slice(0,2000) }); });
      msgs.push({ role:'user', content: String(message||'').slice(0,2000) });
      return await askText(system, msgs, 600, 'low');
    },
    async studentSummary(dataText, lang){
      const L = lang==='ru' ? 'rus' : 'o‘zbek';
      const system = `Siz maktab o'qituvchisi bo'lib, ota-onaga farzandi haqida iliq, hurmatli va aniq oylik xulosa yozasiz. ${L} tilida. 4-6 jumla. Real raqamlarga tayaning, o'ylab topmang. Tuzilishi: umumiy holat → davomat → o'zlashtirish → nimaga e'tibor berish → to'lov holati (agar qarz bo'lsa muloyim eslatma). Ortiqcha rasmiyatchiliksiz.`;
      return await askText(system, [{ role:'user', content: dataText }], 500, 'low');
    },
    async riskNote(dataText, lang){
      const L = lang==='ru' ? 'rus' : 'o‘zbek';
      const system = `Siz o'quv ishlari bo'yicha mutaxassissiz. Orqada qolayotgan o'quvchi haqidagi raqamlarga qarab, ${L} tilida 1-2 jumlali aniq, amaliy tavsiya bering (nima qilish kerak). Qisqa.`;
      return await askText(system, [{ role:'user', content: dataText }], 200, 'low');
    }
  };
}

/* ---------------- Ma'lumot yuklash (Firestore) ---------------- */
async function loadStudentData(sid){
  const sDoc = await db.collection('students').doc(sid).get();
  if(!sDoc.exists) return null;
  const s = sDoc.data();
  const [attSnap, monSnap, invSnap, grdSnap] = await Promise.all([
    db.collection('attendance').where('studentId','==',sid).get(),
    db.collection('monitoring').where('studentId','==',sid).get(),
    db.collection('invoices').where('studentId','==',sid).get(),
    db.collection('grades').where('studentId','==',sid).get()
  ]);
  let present=0,late=0,absent=0,total=0;
  attSnap.docs.forEach(d=>{ const days=(d.data()||{}).days||{}; Object.values(days).forEach(st=>{ total++; if(st==='present')present++; else if(st==='late')late++; else if(st==='absent')absent++; }); });
  const attPct = total?Math.round((present+late)/total*100):null;
  const monBySub={}; monSnap.docs.forEach(d=>{ const m=d.data(); if(m && m.status==='approved' && typeof m.score==='number') (monBySub[m.subject||'—']=monBySub[m.subject||'—']||[]).push(m.score); });
  const mon = Object.keys(monBySub).map(k=>({ subject:k, avg: Math.round(monBySub[k].reduce((a,b)=>a+b,0)/monBySub[k].length) }));
  const inv = invSnap.docs.map(d=>d.data());
  // Balans-aware: qisman to'lov (paidAmount) ham hisobga olinadi.
  const paidAmt = i => i.status==='paid' ? (Number(i.amount)||0) : (i.status==='reversed'?0:(Number(i.paidAmount)||0));
  const paid = inv.reduce((x,i)=>x+paidAmt(i),0);
  const due  = inv.reduce((x,i)=>x+((i.status==='canceled'||i.status==='reversed')?0:Math.max(0,(Number(i.amount)||0)-paidAmt(i))),0);
  const grades = grdSnap.docs.map(d=>d.data());
  return { s, attPct, present, late, absent, total, mon, paid, due, grades };
}
function studentDataText(d){
  const s=d.s; const g=Number(s.grade)||0;
  const L=[];
  L.push(`O‘quvchi: ${s.name||''} (${g===0?'Tayyorlov':g+'-sinf'} ${s.classLetter||s.track||''}, ${s.lang==='ru'?'rus':'o‘zbek'} sinf).`);
  L.push(`Davomat: ${d.attPct==null?'ma’lumot yo‘q':d.attPct+'%'} (kelgan ${d.present}, kechikkan ${d.late}, kelmagan ${d.absent}, jami ${d.total} kun).`);
  L.push(`Umumiy ball: ${s.score==null?'—':s.score}.`);
  if(d.mon.length) L.push('Monitoring (fan — ball): ' + d.mon.map(m=>`${m.subject} ${m.avg}`).join(', ') + '.');
  L.push(`To‘lov: to‘langan ${fmtSom(d.paid)}, qarz ${fmtSom(d.due)}.`);
  return L.join('\n');
}

/* ---------------- Xavf tahlili (qoida) ---------------- */
function assessRisk(s){
  const att = num(s.attendance), score = num(s.score);
  const reasons = [];
  if(att!=null && att < RISK_ATT) reasons.push(`past davomat (${att}%)`);
  if(score!=null && score>0 && score < RISK_SCORE) reasons.push(`past ball (${score})`);
  return reasons;
}
async function riskScan(withAI, lang){
  const snap = await db.collection('students').get();
  const flagged = [];
  snap.docs.forEach(d=>{ const s=d.data(); const reasons=assessRisk(s); if(reasons.length) flagged.push({ studentId: s.studentId||d.id, name: s.name||'', grade: s.grade||0, classLetter: s.classLetter||s.track||'', lang: s.lang||'uz', attendance: num(s.attendance), score: num(s.score), reasons }); });
  flagged.sort((a,b)=>(a.score||0)-(b.score||0) || (a.attendance||0)-(b.attendance||0));
  if(withAI){ const ai = makeAI();
    for(const f of flagged){
      try{ f.recommendation = await ai.riskNote(`Ism: ${f.name}. Sinf: ${f.grade}. Davomat: ${f.attendance}%. Ball: ${f.score}. Sabab: ${f.reasons.join(', ')}.`, lang||(f.lang==='ru'?'ru':'uz')); }
      catch(e){ f.recommendation=''; }
    }
  }
  return flagged;
}

/* ---------------- Autentifikatsiya / ruxsat (RLS bilan bir xil model) ----------------
 * verifyToken(jwt) -> uid (Supabase). Rol users.role'dan, farzand egaligi
 * child_claims'dan (2b). Bu server service_role bilan ishlaydi (RLS'ni chetlab
 * o'tadi), shuning uchun maxfiy endpointlarda ruxsatni O'ZIMIZ tekshiramiz. */
function bearer(req){
  const h = req.headers['authorization'] || req.headers['Authorization'] || '';
  const m = /^Bearer\s+(.+)$/i.exec(String(h).trim());
  return m ? m[1].trim() : '';
}
async function userRole(uid){
  try{ const d = await db.collection('users').doc(uid).get(); return d.exists ? String((d.data()||{}).role||'') : ''; }
  catch(e){ return ''; }
}
async function ownsChild(uid, sid){
  if(!uid || !sid) return false;
  try{ const snap = await db.collection('child_claims').where('uid','==',uid).where('studentId','==',sid).get(); return (snap.docs||[]).length > 0; }
  catch(e){ return false; }
}
// /chat — jamoat endpointi (kirmagan tashrifchilar uchun). Auth emas, lekin
// token-burn/DoS'ni kamaytirish uchun oddiy IP throttle.
const _hits = new Map();
function chatAllowed(req){
  const ip = String(req.headers['x-forwarded-for']||'').split(',')[0].trim() || (req.socket && req.socket.remoteAddress) || '?';
  const now = Date.now(), win = 60*1000, LIM = Number(CFG.chatRateLimit) || 20;
  const arr = (_hits.get(ip)||[]).filter(t => now - t < win);
  arr.push(now); _hits.set(ip, arr);
  if(_hits.size > 5000) _hits.clear();   // xotira himoyasi (soddaligicha)
  return arr.length <= LIM;
}

/* ---------------- HTTP handlerlar ---------------- */
async function handleChat(body){
  const knowledge = await loadKnowledge();
  const reply = await makeAI().chat(body.history || [], body.message || '', knowledge);
  return { reply };
}
async function handleStudentSummary(body){
  const d = await loadStudentData(body.studentId);
  if(!d) return { error: 'not_found' };
  const summary = await makeAI().studentSummary(studentDataText(d), body.lang || (d.s.lang==='ru'?'ru':'uz'));
  return { summary };
}
async function handleRisk(body){
  const students = await riskScan(body.withAI !== false, body.lang);
  return { count: students.length, students };
}

/* ---------------- Google Sheets import (ommaviy CSV proksi) ----------------
 * Faqat docs.google.com — SSRF yo'q: id/gid ichki quriladi, boshqa host mumkin emas.
 * Ommaviy («havolasi bor hamma ko'radi») jadval CSV'sini qaytaradi. Bazaga tegmaydi. */
function parseSheetRef(u){
  try{
    const url = new URL(String(u||''));
    if(!/(^|\.)docs\.google\.com$/.test(url.hostname)) return null;
    const m = url.pathname.match(/\/spreadsheets\/d\/([a-zA-Z0-9\-_]+)/); if(!m) return null;
    let gid = null;
    const qg = url.searchParams.get('gid'); const hg = (url.hash||'').match(/gid=(\d+)/);
    if(qg && /^\d+$/.test(qg)) gid = qg; else if(hg) gid = hg[1];
    return { id: m[1], gid };
  }catch(e){ return null; }
}
async function fetchCsv(u){
  let r, text;
  try{ r = await fetch(u, { redirect:'follow' }); text = await r.text(); }
  catch(e){ return { err:'fetch_failed' }; }
  if(!r.ok) return { err: (r.status===401||r.status===403||r.status===404) ? 'not_public' : 'fetch_failed' };
  if(/^\s*<(!doctype|html)/i.test(text)) return { err:'not_public' };   // login/HTML sahifa = ochiq emas
  return { text };
}
async function handleSheet(body){
  const ref = parseSheetRef(body.url);
  if(!ref) return { error:'bad_url' };
  const base = 'https://docs.google.com/spreadsheets/d/' + ref.id;
  const g = ref.gid!=null ? ('&gid=' + ref.gid) : '';
  // 1) export?format=csv (gid bo'lsa — o'sha varaq, bo'lmasa — birinchi varaq)
  // 2) gviz/tq (ba'zan export bo'sh qaytadi, gviz ishlaydi) — zaxira
  const urls = [ base + '/export?format=csv' + g, base + '/gviz/tq?tqx=out:csv' + g ];
  let lastErr = 'not_public';
  for(const u of urls){
    const res = await fetchCsv(u);
    if(res.err){ lastErr = res.err; continue; }
    if(res.text && res.text.replace(/[\s,]/g,'').length){ return { csv: res.text }; }  // bo'sh emas
    lastErr = 'empty_sheet';   // varaq bo'sh yoki noto'g'ri varaq (gid)
  }
  return { error: lastErr };
}

/* ---------------- Server ---------------- */
function serve(){
  const ORIGIN = CFG.allowOrigin || '*';
  const PORT = Number(CFG.port) || 8791;
  const server = http.createServer((req,res)=>{
    res.setHeader('Access-Control-Allow-Origin', ORIGIN);
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    if(req.method === 'OPTIONS'){ res.writeHead(204); return res.end(); }
    // Sog'liq tekshiruvi — sayt shu orqali server tirikligini biladi (AI so'rovsiz, arzon)
    if(req.method === 'GET' && req.url.startsWith('/health')){ res.writeHead(200,{'Content-Type':'application/json'}); return res.end(JSON.stringify({ ok:true, model: MODEL })); }
    if(req.method !== 'POST'){ res.writeHead(405); return res.end('POST only'); }
    let raw=''; req.on('data',c=>{ raw+=c; if(raw.length>1e6) req.destroy(); });
    req.on('end', async()=>{
      let body={}; try{ body = raw?JSON.parse(raw):{}; }catch(e){ res.writeHead(400); return res.end('{"error":"bad_json"}'); }
      try{
        let out;
        if(req.url.startsWith('/chat')){
          if(!chatAllowed(req)){ res.writeHead(429, {'Content-Type':'application/json'}); return res.end('{"error":"rate_limited"}'); }
          out = await handleChat(body);
        }
        else if(req.url.startsWith('/student-summary')){
          // Maxfiy: o'quvchi bahosi/davomati/qarzi. Faqat admin/zavuch YOKI shu farzand egasi.
          const uid = await verifyToken(bearer(req));
          if(!uid){ res.writeHead(401, {'Content-Type':'application/json'}); return res.end('{"error":"auth_required"}'); }
          const role = await userRole(uid);
          const allowed = role==='admin' || role==='zavuch' || await ownsChild(uid, String(body.studentId||''));
          if(!allowed){ res.writeHead(403, {'Content-Type':'application/json'}); return res.end('{"error":"forbidden"}'); }
          out = await handleStudentSummary(body);
        }
        else if(req.url.startsWith('/risk')){
          // Maxfiy: barcha xavf ostidagi o'quvchilar ro'yxati. Faqat admin/zavuch.
          const uid = await verifyToken(bearer(req));
          if(!uid){ res.writeHead(401, {'Content-Type':'application/json'}); return res.end('{"error":"auth_required"}'); }
          const role = await userRole(uid);
          if(!(role==='admin' || role==='zavuch')){ res.writeHead(403, {'Content-Type':'application/json'}); return res.end('{"error":"forbidden"}'); }
          out = await handleRisk(body);
        }
        else if(req.url.startsWith('/sheet')){
          // Ommaviy Google Sheets CSV'sini o'qib beradi (import uchun). Bazaga tegmaydi.
          if(!chatAllowed(req)){ res.writeHead(429, {'Content-Type':'application/json'}); return res.end('{"error":"rate_limited"}'); }
          out = await handleSheet(body);
        }
        else { res.writeHead(404); return res.end('{"error":"not_found"}'); }
        res.writeHead(200, {'Content-Type':'application/json; charset=utf-8'});
        res.end(JSON.stringify(out));
      }catch(e){ console.error('ERR', e.message); res.writeHead(500); res.end(JSON.stringify({error:'server', detail:e.message})); }
    });
  });
  server.listen(PORT, ()=>console.log(`Iqror AI yordamchi tinglayapti :${PORT}  (/chat, /student-summary, /risk, /sheet) · model ${MODEL}`));
}

/* ---------------- CLI ---------------- */
if(require.main === module){
  const mode = process.argv[2];
  (async()=>{
    if(mode === 'serve'){ serve(); return; }               // process ochiq qoladi
    if(mode === 'test'){
      process.stdout.write(`Model: ${MODEL} · kalit tekshirilmoqda… `);
      const t = await askText('Siz sinov yordamchisisiz.', [{role:'user',content:'Faqat "ok" deb javob bering.'}], 20, 'low');
      console.log(/ok/i.test(t) ? '✓ ISHLAYAPTI — kalit to‘g‘ri.' : '⚠ javob: '+t);
    } else if(mode === 'chat'){
      const kb = await loadKnowledge(); const msg = process.argv.slice(3).join(' ') || 'Narxlar qancha?';
      console.log('SAVOL:', msg); console.log('JAVOB:', await makeAI().chat([], msg, kb));
    } else if(mode === 'summary'){
      const sid = process.argv[3]; if(!sid){ console.error('node index.cjs summary IQ-0002'); process.exit(1); }
      const d = await loadStudentData(sid); if(!d){ console.error('topilmadi'); process.exit(1); }
      console.log(await makeAI().studentSummary(studentDataText(d), process.argv[4]||'uz'));
    } else if(mode === 'risk'){
      const list = await riskScan(process.argv[3]!=='norec', 'uz');
      console.log(`Xavf ostida: ${list.length} o‘quvchi`);
      list.forEach(f=>console.log(`- ${f.name} (${f.studentId}): ${f.reasons.join(', ')}${f.recommendation?' → '+f.recommendation:''}`));
    } else {
      console.error('Buyruqlar:\n  node index.cjs test\n  node index.cjs serve\n  node index.cjs chat "narx qancha?"\n  node index.cjs summary IQ-0002 [uz|ru]\n  node index.cjs risk');
      process.exit(1);
    }
    process.exit(0);
  })().catch(e=>{ console.error('Xatolik:', e.stack||e.message); process.exit(1); });
}

module.exports = { makeAI, loadKnowledge, loadStudentData, studentDataText, assessRisk, riskScan, handleChat, handleStudentSummary, handleRisk, handleSheet, parseSheetRef };
