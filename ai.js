/* ai.js — Arab Tili (Gibrid AI: online + offline fallback)
   Talablar:
   - index.html: supabase.js → config.js → ai.js → app.js (hammasi defer)
   - config.js: window.SUPABASE_URL va window.SUPABASE_ANON_KEY to'ldirilgan
*/

/* ---------- Oflayn mini-lug'at ---------- */
const MINI_DICT = [
  { ar:"أَزْرَق", tr:"azraq", uz:"ko‘k",   eg:["السّماءُ أزرقُ.","الكتابُ أزرقُ."] },
  { ar:"أَحْمَر", tr:"aḥmar", uz:"qizil", eg:["التُّفّاحُ أَحمرُ.","البابُ أحمرُ."] },
  { ar:"قِطّ",   tr:"qiṭṭ",  uz:"mushuk", eg:["عندي قِطّ.","القِطّ صغير."] },
  { ar:"كِتَاب", tr:"kitāb", uz:"kitob", eg:["هذا كِتاب.","أُحبّ الكِتاب."] }
];
const norm = s => (s||"").toLowerCase().trim();
function localExplain(q){
  const n = norm(q);
  for(const w of MINI_DICT){
    if(n.includes(w.uz) || n.includes(norm(w.tr)) || n.includes(norm(w.ar))){
      return [
        `**${w.ar}** (${w.tr}) — *${w.uz}*.`,
        "Misollar:",
        ...w.eg.map((e,i)=>`${i+1}) ${e}`)
      ].join("\n");
    }
  }
  if(/gap|misol|jumla/.test(n)){
    const w = MINI_DICT[Math.floor(Math.random()*MINI_DICT.length)];
    return `Mana misol: **${w.eg[0]}**\nSo‘z: **${w.ar}** (${w.tr}) = *${w.uz}*.`;
  }
  return "Qisqa yordam: “ko‘k” — **أَزْرَق** (azraq). Yana so‘rasangiz, misol gap ham beraman.";
}

/* ---------- Onlayn (Supabase Edge Function) ---------- */
async function onlineTutor(question, ctx={ level:"A1", topic:"general" }) {
  const URL = (window.SUPABASE_URL || "").replace(/\/+$/,"");
  const KEY = window.SUPABASE_ANON_KEY;

  // Config yo'q bo'lsa – darhol lokal
  if(!window.supabase || !URL || !KEY){
    return { answer: localExplain(question), source: "local" };
  }

  // 1) supabase.functions.invoke (tavsiya etiladi)
  try{
    const supa = window.supabase.createClient(URL, KEY);
    const { data, error } = await supa.functions.invoke("tutor", {
      body: { q: question, ...ctx }
    });
    if(!error && data?.answer){
      return { answer: data.answer, source: "online (invoke)" };
    }
    console.warn("[AI] invoke error:", error);
  }catch(e){ console.warn("[AI] invoke threw:", e); }

  // 2) To'g'ridan-to'g'ri fetch (ba'zi JWT/CORS holatlarida)
  try{
    const r = await fetch(`${URL}/functions/v1/tutor`, {
      method: "POST",
      headers: {
        "Content-Type":"application/json",
        "Authorization": `Bearer ${KEY}`,
        "apikey": KEY
      },
      body: JSON.stringify({ q: question, ...ctx })
    });
    const data = await r.json().catch(()=> ({}));
    if(r.ok && data?.answer){
      return { answer: data.answer, source: "online (direct)" };
    }
    console.warn("[AI] direct fetch not ok:", r.status, data);
  }catch(e){ console.warn("[AI] direct fetch threw:", e); }

  // 3) Fallback: lokal
  return { answer: localExplain(question), source: "local" };
}

/* ---------- Global API ---------- */
window.AI = {
  /**
   * @param {string} q  Foydalanuvchi savoli
   * @param {{level?:string, topic?:string}} ctx  (ixtiyoriy)
   * @returns {Promise<{answer:string, source:'online (invoke)'|'online (direct)'|'local'>}>
   */
  async tutor(q, ctx){ return onlineTutor(q, ctx); }
};