// ai.js — Gibrid AI: online (Supabase Edge Function `tutor`) + offline fallback

// --- Ofline mini lug'at (qisqa) ---
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
    if(n.includes(w.uz)||n.includes(norm(w.tr))||n.includes(norm(w.ar))){
      return [
        `**${w.ar}** (${w.tr}) — *${w.uz}*.`,
        "Misollar:",
        ...w.eg.map((e,i)=>`${i+1}) ${e}`)
      ].join("\n");
    }
  }
  if(/gap|misol|jumla/i.test(q)){
    const w = MINI_DICT[Math.floor(Math.random()*MINI_DICT.length)];
    return `Mana misol: **${w.eg[0]}**\nSo‘z: **${w.ar}** (${w.tr}) = *${w.uz}*.`;
  }
  return "Qisqa yordam: “ko‘k” — **أَزْرَق** (azraq). Yana so‘rasangiz, misol gap ham beraman.";
}

// --- ONLAYN: avval invoke, bo'lmasa to'g'ridan-to'g'ri fetch ---
async function onlineTutor(q, ctx={level:"A1", topic:"general"}) {
  const URL = (window.SUPABASE_URL || "").replace(/\/+$/, "");
  const KEY = window.SUPABASE_ANON_KEY;

  if (!window.supabase || !URL || !KEY) {
    return { answer: localExplain(q), source: "local" };
  }

  // 1) Supabase invoke
  try {
    const supa = window.supabase.createClient(URL, KEY);
    const { data, error } = await supa.functions.invoke("tutor", { body: { q, ...ctx } });
    if (!error && data?.answer) return { answer: data.answer, source: "online (invoke)" };
    console.warn("[AI] invoke error:", error);
  } catch (e) {
    console.warn("[AI] invoke threw:", e);
  }

  // 2) To'g'ridan-to'g'ri fetch
  try {
    const resp = await fetch(`${URL}/functions/v1/tutor`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${KEY}`,
        "apikey": KEY
      },
      body: JSON.stringify({ q, ...ctx })
    });
    const data = await resp.json();
    if (resp.ok && data?.answer) return { answer: data.answer, source: "online (direct)" };
    console.warn("[AI] direct fetch not ok:", resp.status, data);
  } catch (e) {
    console.warn("[AI] direct fetch threw:", e);
  }

  // 3) Ofline fallback
  return { answer: localExplain(q), source: "local" };
}

// Global API — app.js shu obyektni chaqiradi
window.AI = {
  async tutor(q, ctx) { return onlineTutor(q, ctx); }
};