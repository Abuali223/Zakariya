// server/telegram.cjs — Telegram Bot API mijozi: tarmoqsiz (soxta fetch) sinov.
//   429 retry_after bilan qayta urinish, 403 / «chat not found» -> blocked, tarmoq xatosi, muddat (timeout), kalitsiz,
//   tezlik cheklovi, kalit (token) xato matnida chiqmasligi.
const { makeTelegram } = require('../server/telegram.cjs');
let pass = 0, fail = 0;
const ok = (name, cond, extra) => { if (cond) pass++; else { fail++; console.log('  ✗ FAIL:', name, extra != null ? '→ ' + extra : ''); } };
const J = x => JSON.stringify(x);
const TOKEN = '123456:SECRET-TOKEN-xyz';
function fakeFetch(script) {
  const calls = [];
  const f = async (url, init) => {
    calls.push({ url, body: JSON.parse(init.body || '{}') });
    const step = script.length ? script.shift() : { status: 200, json: { ok: true, result: { message_id: 1 } } };
    if (step.throw) throw step.throw;
    if (step.hang) return new Promise((_, rej) => init.signal.addEventListener('abort', () => { const e = new Error('The operation was aborted'); e.name = 'AbortError'; rej(e); }));
    return { status: step.status, json: async () => step.json };
  };
  f.calls = calls; return f;
}
(async () => {
  console.log('\n— sendMessage: muvaffaqiyat, metod va manzil');
  {
    const f = fakeFetch([{ status: 200, json: { ok: true, result: { message_id: 77 } } }]);
    const tg = makeTelegram({ token: TOKEN, fetchImpl: f, apiBase: 'https://api.telegram.org/', sleep: async () => {} });
    const r = await tg.sendMessage(42, 'Salom', { reply_markup: { remove_keyboard: true } });
    ok('ok + message_id', r.ok === true && r.id === 77, J(r));
    ok('manzil: /bot<token>/sendMessage', f.calls[0].url === `https://api.telegram.org/bot${TOKEN}/sendMessage`, f.calls[0].url);
    ok('tana: chat_id, text, web preview o‘chiq, reply_markup', f.calls[0].body.chat_id === 42 && f.calls[0].body.text === 'Salom' && f.calls[0].body.disable_web_page_preview === true && !!f.calls[0].body.reply_markup, J(f.calls[0].body));
    const long = await tg.sendMessage(1, 'x'.repeat(5000));
    ok('4096 belgidan uzun matn qisqartiriladi', long.ok && f.calls[1].body.text.length === 4096);
  }
  console.log('\n— 429: retry_after soniya kutib qayta urinish; juda uzun kutish — urinmaydi');
  {
    const slept = [];
    const f = fakeFetch([{ status: 429, json: { ok: false, error_code: 429, description: 'Too Many Requests: retry after 2', parameters: { retry_after: 2 } } },
                         { status: 200, json: { ok: true, result: { message_id: 5 } } }]);
    const tg = makeTelegram({ token: TOKEN, fetchImpl: f, sleep: async ms => { slept.push(ms); } });
    const r = await tg.sendMessage(1, 'a');
    ok('2-urinishda yuborildi', r.ok && f.calls.length === 2, J(r));
    ok('2000 ms kutildi', slept.includes(2000), J(slept));
    const f2 = fakeFetch([{ status: 429, json: { ok: false, error_code: 429, description: 'Too Many Requests', parameters: { retry_after: 120 } } }]);
    const tg2 = makeTelegram({ token: TOKEN, fetchImpl: f2, sleep: async () => {} });
    const r2 = await tg2.sendMessage(1, 'a');
    ok('retry_after 120 s > 30 s — urinmaydi, retryAfter qaytadi', !r2.ok && r2.status === 429 && r2.retryAfter === 120 && f2.calls.length === 1, J(r2));
    const f3 = fakeFetch([1, 2, 3].map(() => ({ status: 429, json: { ok: false, error_code: 429, description: 'x', parameters: { retry_after: 1 } } })));
    const tg3 = makeTelegram({ token: TOKEN, fetchImpl: f3, sleep: async () => {}, maxRetries: 2 });
    const r3 = await tg3.sendMessage(1, 'a');
    ok('maxRetries (2) tugagach — xato', !r3.ok && f3.calls.length === 3, J(r3));
  }
  console.log('\n— 403 / chat not found -> blocked; boshqa 400 — blocked emas');
  {
    const f = fakeFetch([{ status: 403, json: { ok: false, error_code: 403, description: 'Forbidden: bot was blocked by the user' } },
                         { status: 400, json: { ok: false, error_code: 400, description: 'Bad Request: chat not found' } },
                         { status: 400, json: { ok: false, error_code: 400, description: "Bad Request: can't parse entities" } }]);
    const tg = makeTelegram({ token: TOKEN, fetchImpl: f, sleep: async () => {} });
    const a = await tg.sendMessage(1, 'a'), b = await tg.sendMessage(2, 'b'), c = await tg.sendMessage(3, 'c');
    ok('403 -> blocked', !a.ok && a.blocked === true && a.status === 403, J(a));
    ok('chat not found -> blocked', !b.ok && b.blocked === true, J(b));
    ok('boshqa 400 -> blocked emas', !c.ok && !c.blocked && c.status === 400, J(c));
  }
  console.log('\n— tarmoq xatosi, muddat, kalitsiz; kalit xato matnida yo‘q');
  {
    const e = new Error(`connect ECONNREFUSED https://api.telegram.org/bot${TOKEN}/sendMessage`); e.code = 'ECONNREFUSED';
    const f = fakeFetch([{ throw: e }]);
    const tg = makeTelegram({ token: TOKEN, fetchImpl: f, sleep: async () => {} });
    const r = await tg.sendMessage(1, 'a');
    ok('tarmoq xatosi -> ok:false, status 0', !r.ok && r.status === 0 && /^network: ECONNREFUSED$/.test(r.error), J(r));
    ok('xato matnida kalit yo‘q', !J(r).includes('SECRET-TOKEN'), J(r));
    const e2 = new Error(`request to https://api.telegram.org/bot${TOKEN}/sendMessage failed`);
    const r2 = await makeTelegram({ token: TOKEN, fetchImpl: fakeFetch([{ throw: e2 }]), sleep: async () => {} }).sendMessage(1, 'a');
    ok('kodsiz xato matnida ham kalit yo‘q (***)', !r2.ok && !J(r2).includes('SECRET-TOKEN') && /\*\*\*/.test(r2.error), J(r2));
    const fh = fakeFetch([{ hang: true }]);
    const tgh = makeTelegram({ token: TOKEN, fetchImpl: fh, timeoutMs: 1000, sleep: async () => {} });
    const t0 = Date.now(); const rh = await tgh.sendMessage(1, 'a');
    ok('javobsiz -> ~1 s da timeout:true', !rh.ok && rh.timeout === true && Date.now() - t0 < 3000, J(rh));
    const tn = makeTelegram({ token: '', fetchImpl: fakeFetch([]) });
    const rn = await tn.sendMessage(1, 'a');
    ok('kalitsiz -> no_token (so‘rov yo‘q)', !rn.ok && rn.error === 'no_token');
  }
  console.log('\n— tezlik: soniyasiga perSecond ta (oddiy navbat); xizmat chaqiruvlari navbatsiz');
  {
    let clock = 1000; const waits = [];
    const f = fakeFetch([]);
    const tg = makeTelegram({ token: TOKEN, fetchImpl: f, perSecond: 4, now: () => clock, sleep: async ms => { waits.push(ms); clock += ms; } });
    await Promise.all([tg.sendMessage(1, 'a'), tg.sendMessage(2, 'b'), tg.sendMessage(3, 'c')]);
    ok('3 ta xabar: 2 ta 250 ms kutish', waits.length === 2 && waits.every(w => w === 250), J(waits));
    ok('tartib saqlanadi', J(f.calls.map(c => c.body.chat_id)) === '[1,2,3]', J(f.calls.map(c => c.body.chat_id)));
    const before = waits.length;
    await tg.answerCallbackQuery('q1', 'ok'); await tg.leaveChat(5);
    ok('answerCallbackQuery / leaveChat — navbatsiz', waits.length === before);
    const sw = await makeTelegram({ token: TOKEN, fetchImpl: fakeFetch([]) }).setWebhook('https://x/authapi/tg-webhook', 'sec', null);
    ok('setWebhook ok', sw.ok === true);
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
