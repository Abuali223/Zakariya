// ai.js — Gibrid AI (serversiz + online fallback)

// --- Mini lug‘at va andozalar (serversiz) ---
const MINI_DICT = [
  { ar: "أَزْرَق", tr: "azraq", uz: "ko‘k",   eg: ["السّماءُ أزرقُ.", "الكتابُ أزرقُ."] },
  { ar: "أَحْمَر", tr: "aḥmar", uz: "qizil", eg: ["التُّفّاحُ أَحمرُ.", "البابُ أحمرُ."] },
  { ar: "قِطّ",   tr: "qiṭṭ",  uz: "mushuk", eg: ["عندي قِطّ.", "القِطّ صغير."] },
  { ar: "كِتَاب", tr: "kitāb", uz: "kitob", eg: ["هذا كِتاب.", "أُحبّ الكِتاب."] },
];

function normalize(s){ return (s||"").toLowerCase().trim(); }

function localExplain(q) {
  const n = normalize(q);
  for (const w of MINI_DICT) {
    if (n.includes(w.uz) || n.includes(normalize(w.tr)) || n.includes(normalize(w.ar))) {
      return [
        `**${w.ar}** (${w.tr}) — *${w.uz}*.`,
        `Misollar:`,
        ...w.eg.map((e,i)=>`${i+1}) ${e}`)
      ].join("\n");
    }
  }
  if (/gap|misol|jumla/i.test(q)) {
    const w = MINI_DICT[Math.floor(Math.random()*MINI_DICT.length)];
    return `Mana misol: **${w.eg[0]}**  \nSo‘z: **${w.ar}** (${w.tr}) = *${w.uz}*.`;
  }
  return "Qisqa yordam: “ko‘k” — **أَزْرَق** (azraq). Yana so‘rasangiz, misol gap ham beraman.";
}

// --- Onlayn fallback (Supabase Edge Function: tutor) ---
async function onlineTutor(q, ctx={level:"A1", topic:"general"}) {
  if (!window.supabase || !window.SUPABASE_URL || !window.SUPABASE_ANON_KEY) {
    return { answer: localExplain(q), source: "local" };
  }
  try {
    const supa = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_ANON_KEY);
    const { data, error } = await supa.functions.invoke('tutor', { body: { q, ...ctx } });
    if (error || !data || !data.answer) return { answer: localExplain(q), source: "local" };
    return { answer: data.answer, source: "online" };
  } catch {
    return { answer: localExplain(q), source: "local" };
  }
}

// --- API: window.AI.tutor(query, ctx) ---
window.AI = {
  async tutor(q, ctx) {
    if (navigator.onLine) return onlineTutor(q, ctx);
    return { answer: localExplain(q), source: "local" };
  }
};
