/**
 * Iqror AI yordamchi — Cloud Function mantiqi.
 * Kalit Firestore `secrets/ai.anthropicKey` dan olinadi (admin paneldan kiritiladi).
 * Firebase Admin SDK avval index.js da initializeApp() qilingan.
 */
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const db = getFirestore();
const MODEL = 'claude-opus-4-8';
const RISK_ATT = 80, RISK_SCORE = 60;

// Chaqiruvchini tekshirish (o'quvchi ma'lumoti maxfiy — faqat admin/zavuch yoki
// shu farzand ota-onasi ko'radi). Kabinet/panel Firebase idToken yuboradi.
async function callerUid(idToken){
  if(!idToken) return null;
  try{ const dec = await getAuth().verifyIdToken(String(idToken)); return dec.uid; }catch(e){ return null; }
}
async function authorizedForStudent(uid, studentId){
  if(!uid) return false;
  try{ const u = await db.collection('users').doc(uid).get(); if(!u.exists) return false;
    const d = u.data();
    if(d.role==='admin' || d.role==='zavuch') return true;
    const kids = Array.isArray(d.childIds) ? d.childIds : (d.childId ? [d.childId] : []);
    return kids.includes(studentId);
  }catch(e){ return false; }
}
async function isStaff(uid){
  if(!uid) return false;
  try{ const u = await db.collection('users').doc(uid).get(); const r=u.exists?u.data().role:''; return r==='admin'||r==='zavuch'; }catch(e){ return false; }
}
function ym(m){ if(m && /^\d{4}-\d{2}$/.test(m)) return m; const d=new Date(); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`; }

const num = v => { const n = Number(v); return isNaN(n) ? null : n; };
const fmtSom = n => (Number(n)||0).toLocaleString('ru-RU').replace(/,/g,' ') + ' so‘m';

let _client = null, _key = null;
async function apiKey(){
  if(_key) return _key;
  _key = process.env.ANTHROPIC_API_KEY || '';
  if(!_key){ try{ const s = await db.collection('secrets').doc('ai').get(); if(s.exists) _key = s.data().anthropicKey || ''; }catch(e){} }
  return _key;
}
async function anthropic(){
  if(_client) return _client;
  const key = await apiKey();
  if(!key) throw new Error('Anthropic kaliti topilmadi (secrets/ai — admin paneldan kiriting).');
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

let _kb = null, _kbAt = 0;
async function loadKnowledge(force){
  if(!force && _kb && (Date.now() - _kbAt) < 5*60*1000) return _kb;
  const [site, plans, faq, adm, courses] = await Promise.all([
    db.collection('settings').doc('site').get().then(d=>d.exists?d.data():{}).catch(()=>({})),
    db.collection('plans').get().then(s=>s.docs.map(d=>d.data())).catch(()=>[]),
    db.collection('faq').get().then(s=>s.docs.map(d=>d.data())).catch(()=>[]),
    db.collection('admission_steps').get().then(s=>s.docs.map(d=>d.data())).catch(()=>[]),
    db.collection('directions').get().then(s=>s.docs.map(d=>d.data())).catch(()=>[])
  ]);
  const c = site.contact || {};
  const L = [];
  L.push('MAKTAB: Iqror Academy — natijaga yo‘naltirilgan zamonaviy maktab (IT va MED yo‘nalishlari).');
  if(c.address_uz||c.address) L.push('Manzil: ' + (c.address_uz||c.address));
  if(c.phone)    L.push('Telefon: ' + c.phone);
  if(c.telegram) L.push('Telegram: ' + c.telegram);
  if(c.hours_uz||c.hours) L.push('Ish vaqti: ' + (c.hours_uz||c.hours));
  if(plans.length){ L.push('\nNARXLAR (tariflar):'); plans.forEach(p=>L.push(`- ${p.name_uz||p.name_ru||''}: ${p.price||''} (oyiga). ${(p.features_uz||'').replace(/\n/g,', ')}`)); }
  if(courses.length){ L.push('\nYO‘NALISHLAR:'); courses.forEach(d=>L.push(`- ${d.title_uz||d.name_uz||d.title||''}: ${d.desc_uz||d.text_uz||''}`)); }
  if(adm.length){ L.push('\nQABUL BOSQICHLARI:'); adm.forEach((a,i)=>L.push(`${a.num||i+1}. ${a.title_uz||''} — ${a.text_uz||''}`)); }
  if(faq.length){ L.push('\nSAVOL-JAVOB:'); faq.forEach(f=>L.push(`S: ${f.q_uz||''}\nJ: ${f.a_uz||''}`)); }
  _kb = L.join('\n'); _kbAt = Date.now();
  return _kb;
}

function makeAI(){
  return {
    async chat(history, message, knowledge){
      const system = `Siz "Iqror Academy" xususiy maktabining rasmiy yordamchisisiz. Ota-onalar va abituriyentlar savollariga do'stona, aniq, qisqa javob bering.
QOIDALAR:
- FAQAT quyidagi maktab ma'lumotidan foydalaning. Bo'lmagan narsani (narx, sana, kafolat) O'YLAB TOPMANG. Bilmasangiz: "Aniq javob uchun ma'muriyatga murojaat qiling" deb telefon/telegramni bering.
- Foydalanuvchi tilida javob bering (o'zbek yoki rus).
- Maktabga aloqasiz mavzularga kirmang.
- 1-4 jumla. Kerak bo'lsa ariza qoldirishni taklif qiling.

MAKTAB MA'LUMOTI:
${knowledge}`;
      const msgs = [];
      (history||[]).slice(-8).forEach(m=>{ if(m && m.content) msgs.push({ role: m.role==='assistant'?'assistant':'user', content: String(m.content).slice(0,2000) }); });
      msgs.push({ role:'user', content: String(message||'').slice(0,2000) });
      return await askText(system, msgs, 600, 'low');
    },
    async studentSummary(dataText, lang){
      const Lg = lang==='ru' ? 'rus' : 'o‘zbek';
      const system = `Siz maktab o'qituvchisisiz. Ota-onaga farzandi haqida iliq, hurmatli, aniq oylik xulosa yozing. ${Lg} tilida. 4-6 jumla. Real raqamlarga tayaning. Tuzilishi: umumiy holat → davomat → o'zlashtirish → e'tibor → to'lov (qarz bo'lsa muloyim eslatma).`;
      return await askText(system, [{ role:'user', content: dataText }], 500, 'low');
    },
    async riskNote(dataText, lang){
      const Lg = lang==='ru' ? 'rus' : 'o‘zbek';
      return await askText(`Siz o'quv ishlari mutaxassisisiz. Orqada qolayotgan o'quvchi raqamlariga qarab, ${Lg} tilida 1-2 jumlali amaliy tavsiya bering. Qisqa.`, [{ role:'user', content: dataText }], 200, 'low');
    }
  };
}

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
  return { s, attPct, present, late, absent, total, mon, paid, due };
}
function studentDataText(d){
  const s=d.s, g=Number(s.grade)||0, L=[];
  L.push(`O‘quvchi: ${s.name||''} (${g===0?'Tayyorlov':g+'-sinf'} ${s.classLetter||s.track||''}, ${s.lang==='ru'?'rus':'o‘zbek'} sinf).`);
  L.push(`Davomat: ${d.attPct==null?'ma’lumot yo‘q':d.attPct+'%'} (kelgan ${d.present}, kechikkan ${d.late}, kelmagan ${d.absent}, jami ${d.total} kun).`);
  L.push(`Umumiy ball: ${s.score==null?'—':s.score}.`);
  if(d.mon.length) L.push('Monitoring: ' + d.mon.map(m=>`${m.subject} ${m.avg}`).join(', ') + '.');
  L.push(`To‘lov: to‘langan ${fmtSom(d.paid)}, qarz ${fmtSom(d.due)}.`);
  return L.join('\n');
}
function assessRisk(s){
  const att = num(s.attendance), score = num(s.score); const r = [];
  if(att!=null && att>0 && att < RISK_ATT) r.push(`past davomat (${att}%)`);
  if(score!=null && score>0 && score < RISK_SCORE) r.push(`past ball (${score})`);
  return r;
}
async function riskScan(withAI, lang){
  const snap = await db.collection('students').get();
  const flagged = [];
  snap.docs.forEach(d=>{ const s=d.data(); const r=assessRisk(s); if(r.length) flagged.push({ studentId:s.studentId||d.id, name:s.name||'', grade:s.grade||0, lang:s.lang||'uz', attendance:num(s.attendance), score:num(s.score), reasons:r }); });
  flagged.sort((a,b)=>(a.score||0)-(b.score||0)||(a.attendance||0)-(b.attendance||0));
  if(withAI){ const ai=makeAI();
    for(const f of flagged){ try{ f.recommendation = await ai.riskNote(`Ism: ${f.name}. Sinf: ${f.grade}. Davomat: ${f.attendance}%. Ball: ${f.score}. Sabab: ${f.reasons.join(', ')}.`, lang||(f.lang==='ru'?'ru':'uz')); }catch(e){ f.recommendation=''; } } }
  return flagged;
}

async function handleChat(body){ const kb=await loadKnowledge(); return { reply: await makeAI().chat(body.history||[], body.message||'', kb) }; }
async function handleStudentSummary(body){
  const uid = await callerUid(body.idToken);
  if(!(await authorizedForStudent(uid, body.studentId))) return { error:'forbidden' };
  const d = await loadStudentData(body.studentId);
  if(!d) return { error:'not_found' };
  const month = ym(body.month);
  const lang = body.lang || (d.s.lang==='ru'?'ru':'uz');
  // Kesh imzosi — akademik natija (davomat, ball, monitoring). O'zgarsa AI qayta yozadi.
  const sig = JSON.stringify({ sc: d.s.score==null?null:Number(d.s.score), at: d.attPct, mon: d.mon.map(m=>m.subject+':'+m.avg).sort(), lang });
  const ref = db.collection('student_summaries').doc(`${body.studentId}__${month}`);
  try{ const c = await ref.get(); if(c.exists && c.data().sig===sig && c.data().text) return { summary: c.data().text, month, cached:true }; }catch(e){}
  const text = await makeAI().studentSummary(studentDataText(d), lang);
  try{ await ref.set({ studentId: body.studentId, month, lang, sig, text, updatedAt: new Date().toISOString() }); }catch(e){}
  return { summary: text, month, cached:false };
}
async function handleRisk(body){
  if(!(await isStaff(await callerUid(body.idToken)))) return { error:'forbidden' };
  const students=await riskScan(body.withAI!==false, body.lang); return { count: students.length, students };
}

// Google Sheets → CSV (server orqali; brauzerdagi CORS to'sig'ini chetlab o'tadi).
// Faqat docs.google.com ruxsat etiladi (SSRF himoyasi). Jadval "havolasi bor har kim ko'ra oladi" bo'lishi kerak.
function parseSheetUrl(u){
  try{ const url=new URL(String(u||''));
    if(!/(^|\.)docs\.google\.com$/.test(url.hostname)) return null;
    const m=url.pathname.match(/\/spreadsheets\/d\/([a-zA-Z0-9\-_]+)/); if(!m) return null;
    let gid='0'; const qg=url.searchParams.get('gid'); const hg=(url.hash||'').match(/gid=(\d+)/);
    if(qg) gid=qg; else if(hg) gid=hg[1];
    return 'https://docs.google.com/spreadsheets/d/'+m[1]+'/export?format=csv&gid='+gid;
  }catch(e){ return null; }
}
async function handleSheet(body){
  const exp=parseSheetUrl(body.url);
  if(!exp) return { error:'bad_url' };
  let r, text;
  try{ r=await fetch(exp,{redirect:'follow'}); text=await r.text(); }catch(e){ return { error:'fetch_failed' }; }
  if(!r.ok || /^\s*<(!doctype|html)/i.test(text)) return { error:'not_public' };
  return { csv: text };
}

// HTTPS handler (yo'nalish bo'yicha)
async function handleAI(req, res){
  const p = ((req.path||'/').replace(/\/+$/,'')) || '/';
  if(req.method==='GET' && (p==='/health' || p==='/')) return res.json({ ok:true, model:MODEL });
  if(req.method!=='POST') return res.status(405).json({ error:'POST only' });
  const body = req.body || {};
  try{
    if(p==='/chat') return res.json(await handleChat(body));
    if(p==='/student-summary') return res.json(await handleStudentSummary(body));
    if(p==='/risk') return res.json(await handleRisk(body));
    if(p==='/sheet') return res.json(await handleSheet(body));
    return res.status(404).json({ error:'not_found' });
  }catch(e){ console.error('AI err', e.message); return res.status(500).json({ error:'server', detail:e.message }); }
}

module.exports = { handleAI, callerUid, authorizedForStudent, isStaff, ym, parseSheetUrl, handleStudentSummary };
