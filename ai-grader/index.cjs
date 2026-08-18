/**
 * Iqror — O'qituvchi tanlovi AI-GRADER
 * -------------------------------------------------------------------
 * Ikki vazifa:
 *   1) generate — mutaxassislik bo'yicha professional OCHIQ imtihon savollarini
 *      Claude yordamida yaratadi va `exam_questions/<slug>` ga yozadi.
 *   2) grade    — `applications` dagi yangi (status=submitted) nomzod javoblarini
 *      Claude (kuchli AI ekspert) bilan baholaydi: har bir javobga ball + izoh,
 *      keyin umumiy daraja/ball/kuchli-zaif tomon/tavsiya. Natijani arizaga yozadi.
 *
 * AI baholash serverda ishlaydi — Anthropic (Claude) API kaliti kerak. Kalit faqat
 * shu xizmatda saqlanadi, saytga tushmaydi. Firestore'ga Admin SDK orqali yozadi.
 *
 * Ishga tushirish:
 *   npm install
 *   cp config.example.json config.json         # to'ldiring (kalit + service account)
 *   node index.cjs generate "Matematika" 5     # savollar yaratish
 *   node index.cjs grade                        # yangi arizalarni baholash
 *
 * Batafsil: README.md
 */
const fs = require('fs');
const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const CFG = JSON.parse(fs.readFileSync(path.join(__dirname, process.env.IQROR_CONFIG || 'config.json'), 'utf8'));
initializeApp({ credential: cert(require(path.resolve(__dirname, CFG.serviceAccount))) });
const db = getFirestore();
const MODEL = CFG.model || 'claude-opus-4-8';   // eng kuchli model (skill: default)

const slug = s => (String(s || '').trim().toLowerCase().replace(/[^a-z0-9]+/gi, '_').replace(/^_+|_+$/g, '')) || 'fan';
const clamp = n => { n = Math.round(Number(n)); return isNaN(n) ? 0 : Math.max(0, Math.min(100, n)); };

// ---- JSON schemas for structured outputs (numeric ranges enforced in prompt + clamp) ----
const PER_SCHEMA = { type:'object', additionalProperties:false, required:['score','feedback'],
  properties:{ score:{type:'integer'}, feedback:{type:'string'} } };
const SYNTH_SCHEMA = { type:'object', additionalProperties:false,
  required:['overallScore','level','strengths','weaknesses','recommendation','summary'],
  properties:{ overallScore:{type:'integer'},
    level:{type:'string', enum:['Boshlang‘ich','O‘rta','Yuqori','Ekspert']},
    strengths:{type:'array', items:{type:'string'}},
    weaknesses:{type:'array', items:{type:'string'}},
    recommendation:{type:'string'}, summary:{type:'string'} } };
const GEN_SCHEMA = { type:'object', additionalProperties:false, required:['questions'],
  properties:{ questions:{type:'array', items:{type:'object', additionalProperties:false,
    required:['id','text'], properties:{ id:{type:'string'}, text:{type:'string'} } } } } };

let _client = null;
function anthropic(){
  if(_client) return _client;
  const Pkg = require('@anthropic-ai/sdk');
  const Anthropic = Pkg.default || Pkg;
  _client = new Anthropic({ apiKey: CFG.anthropicKey || process.env.ANTHROPIC_API_KEY });
  return _client;
}
// Claude'dan sxemaga mos JSON so'raydi (adaptive thinking, high effort — skill bo'yicha).
async function askJSON(system, user, schema, maxTokens){
  const r = await anthropic().messages.create({
    model: MODEL, max_tokens: maxTokens || 2000,
    thinking: { type: 'adaptive' },
    output_config: { effort: 'high', format: { type: 'json_schema', schema } },
    system, messages: [{ role: 'user', content: user }]
  });
  const block = (r.content || []).find(b => b.type === 'text');
  return JSON.parse((block && block.text) || '{}');
}

// «Kuchli AI ekspert» — har bir javobni mustaqil ekspert baholaydi, so'ng sintez qiladi.
function makeClaudeAI(){
  return {
    async gradeAnswer(spec, question, answer){
      if(!answer || !answer.trim()) return { score:0, feedback:'Javob berilmagan.' };
      const j = await askJSON(
        `Siz "${spec}" fani bo'yicha tajribali ekspert va imtihon oluvchisiz. Nomzodning javobini xolisona baholang: kasbiy chuqurlik, ilmiy to'g'rilik, misollar, metodik/pedagogik yondashuv. Faqat javob mazmuniga qarang, uslubiga emas.`,
        `SAVOL:\n${question || '(savol matni saqlanmagan — javobning o\'zini baholang)'}\n\nNOMZOD JAVOBI:\n${answer}\n\nJavobni 0 dan 100 gacha ballda baholang va bir-ikki jumlali izoh bering (o'zbek tilida).`,
        PER_SCHEMA, 1500);
      return { score: clamp(j.score), feedback: String(j.feedback || '') };
    },
    async synthesize(spec, items){
      const lines = items.map((it,i)=>`${i+1}-savol: ${it.score}/100 — ${it.feedback}`).join('\n');
      const j = await askJSON(
        `Siz "${spec}" bo'yicha o'qituvchi tanlash komissiyasining a'zosisiz. Har bir javob bahosiga tayanib, nomzodning umumiy darajasini xolisona aniqlang.`,
        `Nomzodning javob baholari:\n${lines}\n\nQuyidagilarni bering: umumiy ball (0-100), daraja (Boshlang‘ich / O‘rta / Yuqori / Ekspert), kuchli tomonlari (ro'yxat), zaif tomonlari (ro'yxat), tavsiya (masalan «Ishga olish tavsiya etiladi», «Ehtiyotkorlik bilan», yoki «Tavsiya etilmaydi») va 2-3 jumlali qisqa xulosa. Hammasi o'zbek tilida.`,
        SYNTH_SCHEMA, 2200);
      return { overallScore: clamp(j.overallScore), level: j.level || 'O‘rta',
        strengths: Array.isArray(j.strengths)?j.strengths:[], weaknesses: Array.isArray(j.weaknesses)?j.weaknesses:[],
        recommendation: String(j.recommendation || ''), summary: String(j.summary || '') };
    }
  };
}

// Bitta arizani baholaydi (ai — kirituvchi; test uchun mock berish mumkin).
async function gradeApplication(ref, app, qmap, ai){
  await ref.set({ status:'grading' }, { merge:true });
  const per = [], items = [];
  for(const a of (Array.isArray(app.answers)?app.answers:[])){
    const g = await ai.gradeAnswer(app.specialty || '', qmap[a.qid] || '', a.text || '');
    per.push({ qid:a.qid, score:g.score, feedback:g.feedback });
    items.push({ score:g.score, feedback:g.feedback });
  }
  const syn = await ai.synthesize(app.specialty || '', items);
  const result = Object.assign({}, syn, { perQuestion: per, model: MODEL, gradedBy:'ai' });
  await ref.set({ status:'graded', result, gradedAt: FieldValue.serverTimestamp() }, { merge:true });
  return result;
}

async function loadQuestionMap(spec){
  try{ const s = await db.collection('exam_questions').doc(slug(spec)).get();
    const qs = (s.exists && s.data().questions) || []; const m = {}; qs.forEach(q=>{ m[q.id]=q.text; }); return m;
  }catch(e){ return {}; }
}

async function gradeAll(ai){
  ai = ai || makeClaudeAI();
  const snap = await db.collection('applications').where('status','==','submitted').get();
  if(snap.empty){ console.log('Baholanadigan yangi ariza yo\'q.'); return 0; }
  const qcache = {}; let n=0;
  for(const docSnap of snap.docs){
    const app = docSnap.data(), spec = app.specialty || '';
    if(!(spec in qcache)) qcache[spec] = await loadQuestionMap(spec);
    try{
      const r = await gradeApplication(docSnap.ref, app, qcache[spec], ai);
      console.log(`✓ ${app.name || docSnap.id} · ${spec} → ${r.level} (${r.overallScore}) · ${r.recommendation}`);
      n++;
    }catch(e){ console.error(`✗ ${docSnap.id}: ${e.message}`); await docSnap.ref.set({status:'submitted'},{merge:true}).catch(()=>{}); }
  }
  return n;
}

async function generate(specialty, count){
  count = Math.max(1, Math.min(20, Number(count) || 5));
  const j = await askJSON(
    `Siz "${specialty}" fani bo'yicha o'qituvchilarni tanlash uchun imtihon tuzuvchi ekspertsiz.`,
    `${count} ta OCHIQ (yozma, batafsil javob talab qiladigan), kasbiy va yuqori darajadagi imtihon savoli tuzing. Savollar fan bilimini, o'qitish metodikasini va amaliy/pedagogik yondashuvni chuqur tekshirsin — «ha/yo'q» yoki bir so'zli javoblardan qoching. Har biriga id ("q1","q2"...) va matn bering. O'zbek tilida. Matematik formula yoki belgilar bo'lsa, ularni LaTeX ko'rinishida $...$ ichida yozing (masalan $p^2$, $a^2+b^2$, $\\frac{a}{b}$) — Unicode yuqori/pastki indeks belgilaridan foydalanmang.`,
    GEN_SCHEMA, 3000);
  const questions = (j.questions || []).map((q,i)=>({ id: q.id || ('q'+(i+1)), text: String(q.text||'') })).filter(q=>q.text);
  await db.collection('exam_questions').doc(slug(specialty)).set({
    specialty, slug: slug(specialty), questions, count: questions.length,
    generatedBy:'ai', model: MODEL, updatedAt: FieldValue.serverTimestamp()
  });
  return questions;
}

// ---- CLI (faqat to'g'ridan-to'g'ri ishga tushirilganda) ----
if(require.main === module){
  const mode = process.argv[2];
  (async()=>{
    if(mode === 'generate'){
      const spec = process.argv[3]; const count = process.argv[4];
      if(!spec){ console.error('Foydalanish: node index.cjs generate "Matematika" 5'); process.exit(1); }
      const qs = await generate(spec, count);
      console.log(`✓ "${spec}" uchun ${qs.length} ta savol yaratildi (exam_questions/${slug(spec)}).`);
    } else if(mode === 'grade'){
      const n = await gradeAll();
      console.log(`Baholash tugadi: ${n} ta ariza.`);
    } else if(mode === 'test'){
      // API kaliti va model ishlashini tekshiradi (bitta arzon so'rov)
      process.stdout.write(`Model: ${MODEL} · kalit tekshirilmoqda… `);
      const j = await askJSON('Siz sinov yordamchisisiz.', 'Faqat {"ok": true} JSON qaytaring.',
        { type:'object', additionalProperties:false, required:['ok'], properties:{ ok:{type:'boolean'} } }, 200);
      console.log(j && j.ok ? '✓ ISHLAYAPTI — kalit to‘g‘ri.' : '⚠ javob kutilganidek emas: '+JSON.stringify(j));
    } else {
      console.error('Buyruqlar:\n  node index.cjs test\n  node index.cjs generate "<mutaxassislik>" [savollar soni]\n  node index.cjs grade');
      process.exit(1);
    }
    process.exit(0);
  })().catch(e=>{ console.error('Xatolik:', e.stack || e.message); process.exit(1); });
}

module.exports = { slug, clamp, gradeApplication, gradeAll, generate, makeClaudeAI, PER_SCHEMA, SYNTH_SCHEMA, GEN_SCHEMA };
