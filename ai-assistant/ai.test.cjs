// =====================================================================
// ai.test.cjs — AI yordamchi: o'quvchi ma'lumoti tashqi AI'ga ketmasligi (/student-summary, /risk — 410, sozlamasiz),
//   /chat konteksti (faqat ommaviy maktab ma'lumoti, «faqat oylik to'lov» qoidasi, eski «yillik chegirma» matni olinadi).
//   Tarmoqsiz: @supabase/supabase-js va @anthropic-ai/sdk soxta (Module._load) — Anthropic'ga so'rov YO'Q.
//   node ai.test.cjs
// =====================================================================
const fs = require('fs'), os = require('os'), path = require('path'), http = require('http'), Module = require('module');

let pass = 0, fail = 0;
const ok = (name, cond, extra) => { if (cond) pass++; else { fail++; console.log('  ✗ FAIL:', name, extra != null ? '→ ' + extra : ''); } };
const sec = s => console.log('\n— ' + s);

// ---- soxta baza (sb-admin.js chaqiradigan qismi) — qaysi jadval o'qilganini yozib boradi ----
const DATA = {
  settings: [{ id: 'site', contact: { address: 'Toshkent', phone: '+998 71 200 00 00', hours: '08:00–18:00' } }],
  plans: [{ id: 'p1', name_uz: 'Standart', price: '1 900 000 so‘m', features_uz: "Ovqat, to'garak. Yillik to‘lovda 10% chegirma." }],
  faq: [
    { id: 'f1', q_uz: 'To‘lov qanday amalga oshiriladi?', a_uz: 'Ha, oylik va choraklik to‘lov imkoniyati bor. Yillik to‘lovda chegirma beriladi.' },
    { id: 'f2', q_uz: 'Qabul qachon?', a_uz: 'Qabul iyun oyida. Oldindan ro‘yxatdan o‘ting.' },
    { id: 'f3', q_uz: 'Yillik to‘lov bormi?', a_uz: 'Bor.' },
    { id: 'f4', q_uz: 'Aka-uka chegirmasi bormi?', a_uz: 'Ha, ikkinchi farzandga 10%.' },
  ],
  admission_steps: [{ id: 'a1', num: 1, title_uz: 'Ariza', text_uz: 'Saytda ariza qoldiring.' }],
  directions: [{ id: 'd1', title_uz: 'IT', desc_uz: 'Dasturlash.' }],
  students: [{ id: 'S1', studentId: 'IQ-0001', name: 'Aliyev Valijon', attendance: 50, score: 40 }],
  student_private: [{ id: 'S1', parentPhone: '+998901112233' }],
  users: [{ id: 'U_DIR', role: 'director' }, { id: 'U_TCH', role: 'teacher' }],
};
// Soxta GoTrue: faqat shu tokenlar yaroqli (qolgani — 401); chaqiruvlar sanaladi (anonim oqim GoTrue'ga yetmasligi uchun).
const TOKENS = { 'tok-dir': 'U_DIR', 'tok-tch': 'U_TCH' };
const GETUSER = [];
const READS = [];
function fakeClient() {
  const from = t => {
    READS.push(t);
    const f = [];
    const rows = () => (DATA[t] || []).filter(r => f.every(([k, v]) => String(r[k]) === String(v))).map(r => ({ ...r }));
    const b = {
      select() { return b; }, eq(k, v) { f.push([k, v]); return b; }, in() { return b; }, contains() { return b; },
      maybeSingle() { return Promise.resolve({ data: rows()[0] || null, error: null }); },
      then(res, rej) { return Promise.resolve({ data: rows(), error: null }).then(res, rej); },
    };
    return b;
  };
  return { from, auth: { getUser: async jwt => { GETUSER.push(jwt); const id = TOKENS[jwt];
    return id ? { data: { user: { id } }, error: null } : { data: { user: null }, error: { status: 401, message: 'invalid' } }; } } };
}
// ---- soxta Anthropic: yuborilgan so'rovni yozib qo'yadi ----
const SENT = [];
class FakeAnthropic { constructor() { this.messages = { create: async p => { SENT.push(p); return { content: [{ type: 'text', text: 'Javob.' }] }; } }; } }
const orig = Module._load;
Module._load = function (req) {
  if (req === '@supabase/supabase-js') return { createClient: () => fakeClient() };
  if (req === '@anthropic-ai/sdk') return FakeAnthropic;
  return orig.apply(this, arguments);
};

// ---- vaqtinchalik config — worktree'dan TASHQARIDA (index.cjs IQROR_CONFIG'ni __dirname'ga nisbatan o'qiydi) ----
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'iqror-ai-test-'));
const CFGF = path.join(TMP, 'config.json');
process.on('exit', () => { try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (_) {} });
function load(extra) {
  fs.writeFileSync(CFGF, JSON.stringify(Object.assign({ backend: 'supabase', supabaseUrl: 'http://x.invalid', serviceRoleKey: 'k', anthropicKey: 'sk-test-fake' }, extra || {})));
  process.env.IQROR_CONFIG = path.relative(__dirname, CFGF);
  delete require.cache[require.resolve('./index.cjs')];
  return require('./index.cjs');
}
async function withServer(mod, fn) {
  const srv = http.createServer(mod.makeRequestHandler());
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  const port = srv.address().port;
  const call = (method, p, body, headers) => new Promise((res, rej) => {
    const data = body == null ? null : JSON.stringify(body);
    const rq = http.request({ host: '127.0.0.1', port, path: p, method, headers: Object.assign(data ? { 'content-type': 'application/json' } : {}, headers || {}) }, rs => {
      let d = ''; rs.on('data', c => d += c); rs.on('end', () => { let j = null; try { j = JSON.parse(d); } catch (_) {} res({ status: rs.statusCode, json: j, text: d }); });
    });
    rq.on('error', rej); if (data) rq.write(data); rq.end();
  });
  try { await fn(call); } finally { srv.close(); }
}

(async () => {
  sec('/student-summary va /risk — standart holda 410 «Bu xizmat vaqtincha o‘chirilgan», bazaga tegmaydi');
  let M = load();
  await withServer(M, async call => {
    READS.length = 0; SENT.length = 0;
    for (const [p, h] of [['/student-summary', {}], ['/student-summary', { authorization: 'Bearer anything' }], ['/risk', {}], ['/risk', { authorization: 'Bearer x' }], ['/risk?withAI=1', {}]]) {
      const r = await call('POST', p, { studentId: 'IQ-0001', withAI: true }, h);
      ok(`${p} ${h.authorization ? '(token bilan)' : '(tokensiz)'} -> 410`, r.status === 410 && r.json && r.json.error === 'disabled' && r.json.message === 'Bu xizmat vaqtincha o‘chirilgan', `${r.status} ${r.text}`);
    }
    ok('o‘quvchi jadvallari o‘qilmadi, AI’ga hech narsa ketmadi', READS.length === 0 && SENT.length === 0, JSON.stringify({ READS, SENT: SENT.length }));
    const h = await call('GET', '/health');
    ok('GET /health o‘zgarmagan ({ok:true, model})', h.status === 200 && h.json && h.json.ok === true && 'model' in h.json, h.text);
  });

  sec('/chat — kontekstda faqat ommaviy maktab ma’lumoti; «faqat oylik to‘lov» qoidasi; eski «yillik chegirma» matni yo‘q');
  await withServer(M, async call => {
    READS.length = 0; SENT.length = 0;
    const r = await call('POST', '/chat', { message: 'Yillik to‘lasam chegirma bormi?', history: [{ role: 'user', content: 'Salom' }] });
    ok('/chat -> 200, javob', r.status === 200 && r.json && r.json.reply === 'Javob.', r.text);
    const p = SENT[0] || {}; const sys = String(p.system || '');
    ok('tizim matnida qoida: FAQAT OYLIK, yillik/choraklik/oldindan chegirma YO‘Q', /FAQAT OYLIK/.test(sys) && /Yillik, yarim yillik yoki choraklik/.test(sys) && /oldindan to'lov uchun chegirma YO'Q/.test(sys), sys.slice(0, 300));
    ok('eski FAQ («choraklik to‘lov… Yillik to‘lovda chegirma») va «Yillik to‘lov bormi?» savoli olib tashlandi', !/choraklik to‘lov/.test(sys) && !/Yillik to‘lovda/.test(sys) && !/Yillik to‘lov bormi/.test(sys), sys);
    ok('tarifdagi «10% chegirma» jumlasi olindi, qolgan qismi bor', /Ovqat, to'garak\./.test(sys) && !/10% chegirma/.test(sys), sys);
    ok('boshqa FAQ (qabul, aka-uka chegirmasi) saqlandi', /Qabul qachon\?/.test(sys) && /Qabul iyun oyida/.test(sys) && /Aka-uka chegirmasi bormi/.test(sys), sys);
    ok('o‘quvchi ismi/telefoni/ID kontekstda YO‘Q', !/Aliyev|Valijon|901112233|IQ-0001/.test(JSON.stringify(p)), JSON.stringify(p).slice(0, 400));
    const allowed = new Set(['settings', 'plans', 'faq', 'admission_steps', 'directions', 'secrets']);
    ok('faqat ommaviy jadvallar o‘qildi (students / student_private / users — yo‘q)', READS.length > 0 && READS.every(t => allowed.has(t)), JSON.stringify(READS));
    ok('foydalanuvchi xabari va tarix o‘zgarmay uzatildi', (p.messages || []).length === 2 && p.messages[1].content === 'Yillik to‘lasam chegirma bormi?', JSON.stringify(p.messages));
  });

  sec('dropNonMonthly — faqat yillik/choraklik/oldindan to‘lov va shunday chegirma jumlalari');
  const D = M.dropNonMonthly;
  ok('UZ jumlalar olinadi', D('To‘lov oylik. Yillik to‘lovda chegirma bor. Yarim yillik to‘lov ham mumkin.') === 'To‘lov oylik.', D('To‘lov oylik. Yillik to‘lovda chegirma bor. Yarim yillik to‘lov ham mumkin.'));
  ok('«oldindan to‘lov» chegirmasi olinadi', D("Oldindan to'lov qilsangiz 5% chegirma. Darslar 8:00 da.") === 'Darslar 8:00 da.');
  ok('RU jumlalar olinadi', D('Есть поквартальная оплата. При годовой оплате действует скидка. Обучение полного дня.') === 'Обучение полного дня.', D('Есть поквартальная оплата. При годовой оплате действует скидка. Обучение полного дня.'));
  ok('RU предоплата olinadi', D('Предоплата за год со скидкой.') === '');
  ok('aloqasiz matn tegilmaydi (yillik tajriba, choraklik baholar, aka-uka chegirmasi, oldindan ro‘yxat)', D('Ustozlar 10 yillik tajribaga ega. Choraklik baholar kabinetda. Aka-uka chegirmasi 10%. Oldindan ro‘yxatdan o‘ting.') === 'Ustozlar 10 yillik tajribaga ega. Choraklik baholar kabinetda. Aka-uka chegirmasi 10%. Oldindan ro‘yxatdan o‘ting.');
  ok('bo‘sh / null', D('') === '' && D(null) === '');

  sec('isArchived — arxivdagi (chiqarilgan / bitirgan) o‘quvchi xavf tahliliga kirmaydi (admin.html stuArchived bilan bir qoida)');
  {
    const A = M.isArchived, T = '2026-11-18';
    ok('faol — arxivda emas', A({ payStatus: '' }, T) === false && A({ payStatus: 'faol' }, T) === false && A({ payStatus: 'muzlatilgan', stopFrom: '2026-01-01' }, T) === false);
    ok('chiqdi, sana o‘tgan — arxivda', A({ payStatus: 'chiqdi', exitAt: '2026-11-10' }, T) === true);
    ok('chiqdi, bugun — arxivda (chiqarilgan kunidan)', A({ payStatus: 'chiqdi', exitAt: T }, T) === true);
    ok('chiqdi, kelajak sana — hali ro‘yxatda', A({ payStatus: 'chiqdi', exitAt: '2026-12-01' }, T) === false);
    ok('chiqdi, sanasiz — arxivda', A({ payStatus: 'chiqdi' }, T) === true);
    ok('eski yozuv: exitAt yo‘q — stopFrom bo‘yicha', A({ payStatus: 'chiqdi', stopFrom: '2026-12-05' }, T) === false && A({ payStatus: 'chiqdi', stopFrom: '2026-10-05' }, T) === true);
    ok('exitAt stopFrom’dan ustun (muzlatilgandan keyin chiqarilgan)', A({ payStatus: 'chiqdi', stopFrom: '2026-09-15', exitAt: '2026-12-01' }, T) === false);
  }

  sec('allowStudentData: true — yo‘llar qaytadi (kod o‘chirilmagan): avvalgidek ruxsat tekshiruvi');
  M = load({ allowStudentData: true });
  await withServer(M, async call => {
    let r = await call('POST', '/student-summary', { studentId: 'IQ-0001' });
    ok('/student-summary tokensiz -> 401 (410 emas)', r.status === 401 && r.json && r.json.error === 'auth_required', r.text);
    r = await call('POST', '/risk', {}, { authorization: 'Bearer bad' });
    ok('/risk yaroqsiz token -> 401', r.status === 401, r.text);
  });

  sec('/sheet (Google Sheets importi) — faqat Direktor tokeni bilan, O‘Z cheklovi: /chat’ning kunlik AI chegarasiga tegmaydi');
  {
    // Tarmoqsiz: Google o'rniga soxta CSV (qaysi manzil so'ralgani yoziladi).
    const realFetch = globalThis.fetch, FETCHED = [];
    globalThis.fetch = async u => { FETCHED.push(String(u)); return { ok: true, status: 200, text: async () => 'Ism,Sinf\nSinov Bola,5\n' }; };
    const SHEET = { url: 'https://docs.google.com/spreadsheets/d/abcDEF123/edit#gid=0' };
    const dir = { authorization: 'Bearer tok-dir' };
    try {
      M = load({ chatDailyCap: 2, sheetDailyCap: 3 });
      await withServer(M, async call => {
        let r = await call('POST', '/sheet', SHEET);
        ok('/sheet tokensiz -> 401 auth_required', r.status === 401 && r.json && r.json.error === 'auth_required', r.text);
        r = await call('POST', '/sheet', SHEET, { authorization: 'Bearer yaroqsiz' });
        ok('/sheet yaroqsiz token -> 401', r.status === 401, r.text);
        r = await call('POST', '/sheet', SHEET, { authorization: 'Bearer tok-tch' });
        ok('/sheet o‘qituvchi tokeni -> 403 forbidden (import faqat Direktorda)', r.status === 403 && r.json && r.json.error === 'forbidden', r.text);
        ok('ruxsatsiz so‘rovlarda Google’ga murojaat yo‘q', FETCHED.length === 0, JSON.stringify(FETCHED));
        for (let i = 0; i < 3; i++) r = await call('POST', '/sheet', SHEET, dir);
        ok('/sheet Direktor tokeni -> 200, CSV', r.status === 200 && r.json && /Sinov Bola/.test(r.json.csv || ''), r.text);
        ok('so‘rov faqat docs.google.com ga, manzil ichki quriladi', FETCHED.length >= 3 && FETCHED.every(u => u.startsWith('https://docs.google.com/spreadsheets/d/abcDEF123/')), JSON.stringify(FETCHED));
        r = await call('POST', '/chat', { message: 'Salom' });
        ok('6 ta /sheet so‘rovi /chat kunlik chegarasini (chatDailyCap=2) yemadi -> /chat 200', r.status === 200 && r.json && r.json.reply === 'Javob.', r.text);
        r = await call('POST', '/sheet', SHEET, dir);
        // Kunlik chegara — o'z xatosi (daily_cap): admin.html «ertaga qayta urinib ko'ring» deydi (avval 'rate_limited' — «bir daqiqadan so'ng»).
        ok('/sheet o‘z kunlik chegarasi (sheetDailyCap=3) -> 429 daily_cap (daqiqa oynasi xatosi emas)', r.status === 429 && r.json && r.json.error === 'daily_cap', r.text);
        r = await call('POST', '/chat', { message: 'Salom' });
        ok('/chat o‘z hisoblagichi bilan ishlayveradi (2-so‘rov) -> 200', r.status === 200, r.text);
      });
      M = load({ sheetIpRateLimit: 3, sheetRateLimit: 2 });
      await withServer(M, async call => {
        GETUSER.length = 0;
        let r;
        for (let i = 0; i < 5; i++) r = await call('POST', '/sheet', SHEET);
        ok('IP oynasi (sheetIpRateLimit=3): tokensiz oqim 4-so‘rovdan 429 rate_limited, token tekshiruviga (GoTrue) faqat 3 tasi yetdi', r.status === 429 && r.json && r.json.error === 'rate_limited' && GETUSER.length === 3, `${r.status} ${r.text} getUser=${GETUSER.length}`);
        const c = await call('POST', '/chat', { message: 'Salom' });
        ok('anonim /sheet oqimi /chat’ni to‘xtatmaydi', c.status === 200, c.text);
      });
      M = load({ sheetRateLimit: 2 });
      await withServer(M, async call => {
        const a = await call('POST', '/sheet', SHEET, dir), b = await call('POST', '/sheet', SHEET, dir), c = await call('POST', '/sheet', SHEET, dir);
        ok('foydalanuvchi oynasi (sheetRateLimit=2): 3-so‘rov daqiqa ichida -> 429 rate_limited (kunlik chegara emas)', a.status === 200 && b.status === 200 && c.status === 429 && c.json && c.json.error === 'rate_limited', `${a.status} ${b.status} ${c.status} ${c.text}`);
      });
    } finally { globalThis.fetch = realFetch; }
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('TEST CRASH:', e); process.exit(1); });
