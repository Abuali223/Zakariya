// ai.js — Gibrid AI: online (Supabase Edge Function `tutor`) + offline fallback

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

// --- ONLAYN chaqiruv (to‘g‘ri yo‘l) ---
async function onlineTutor(q, ctx={level:"A1", topic:"general"}) {
  // Supabase sozlanganmi?
  if (!window.supabase || !window.SUPABASE_URL || !window.SUPABASE_ANON_KEY) {
    return { answer: localExplain(q), source: "local" };
  }

  try {
    const supa = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON_KEY);

    // Edge Function nomi: "tutor" (Supabase’da shuni deploy qilgansiz)
    const { data, error } = await supa.functions.invoke("tutor", {
      body: { q, ...ctx }   // server kodingiz { q, level, topic } ni qabul qiladi
    });

    if (error || !data?.answer) {
      console.error("[AI] tutor error:", error);
      return { answer: localExplain(q), source: "local" };
    }
    return { answer: data.answer, source: "online" };
  } catch (e) {
    console.error("[AI] invoke failed:", e);
    return { answer: localExplain(q), source: "local" };
  }
}

// Global API — app.js shu obyektni chaqiradi
window.AI = {
  async tutor(q, ctx) {
    return navigator.onLine
      ? onlineTutor(q, ctx)
      : { answer: localExplain(q), source: "local" };
  }
};