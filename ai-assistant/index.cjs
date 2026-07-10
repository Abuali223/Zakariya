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
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
initializeApp({ credential: cert(require(path.resolve(__dirname, CFG.serviceAccount))) });
const db = getFirestore();
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
  const paid = inv.filter(i=>i.status==='paid').reduce((x,i)=>x+(Number(i.amount)||0),0);
  const due  = inv.filter(i=>i.status!=='paid'&&i.status!=='canceled').reduce((x,i)=>x+(Number(i.amount)||0),0);
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

/* ---------------- Server ---------------- */
function serve(){
  const ORIGIN = CFG.allowOrigin || '*';
  const PORT = Number(CFG.port) || 8791;
  const server = http.createServer((req,res)=>{
    res.setHeader('Access-Control-Allow-Origin', ORIGIN);
    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    if(req.method === 'OPTIONS'){ res.writeHead(204); return res.end(); }
    if(req.method !== 'POST'){ res.writeHead(405); return res.end('POST only'); }
    let raw=''; req.on('data',c=>{ raw+=c; if(raw.length>1e6) req.destroy(); });
    req.on('end', async()=>{
      let body={}; try{ body = raw?JSON.parse(raw):{}; }catch(e){ res.writeHead(400); return res.end('{"error":"bad_json"}'); }
      try{
        let out;
        if(req.url.startsWith('/chat')) out = await handleChat(body);
        else if(req.url.startsWith('/student-summary')) out = await handleStudentSummary(body);
        else if(req.url.startsWith('/risk')) out = await handleRisk(body);
        else { res.writeHead(404); return res.end('{"error":"not_found"}'); }
        res.writeHead(200, {'Content-Type':'application/json; charset=utf-8'});
        res.end(JSON.stringify(out));
      }catch(e){ console.error('ERR', e.message); res.writeHead(500); res.end(JSON.stringify({error:'server', detail:e.message})); }
    });
  });
  server.listen(PORT, ()=>console.log(`Iqror AI yordamchi tinglayapti :${PORT}  (/chat, /student-summary, /risk) · model ${MODEL}`));
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

module.exports = { makeAI, loadKnowledge, loadStudentData, studentDataText, assessRisk, riskScan, handleChat, handleStudentSummary, handleRisk };
