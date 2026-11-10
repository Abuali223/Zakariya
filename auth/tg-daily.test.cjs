// tg-daily.cjs — Direktorga kunlik hisobot: reja (yoqilgan / kun / soat), qabul qiluvchilar (faqat faol Direktor, /sozlamalar),
//   bir kunda bir marta, bloklangan chat -> tg_blocked, matn (to'lovlar, qarzdorlar, davomat, tasdiqlar, tizim holati).
const { makeFake } = require('./_fake.cjs');
const { composeDaily, dailyPlan, runDaily } = require('./tg-daily.cjs');
let pass = 0, fail = 0;
const ok = (name, cond, extra) => { if (cond) pass++; else { fail++; console.log('  ✗ FAIL:', name, extra != null ? '→ ' + extra : ''); } };
const J = x => JSON.stringify(x);
const T = h => Date.parse(`2026-11-02T${String(h - 5).padStart(2, '0')}:30:00Z`);   // 2026-11-02 dushanba, Toshkent soati h:30
const DAILY = { day: '2026-11-02', payments: { count: 3, sum: 2750000, byProvider: { cash: 2000000, click: 750000 } }, unmatched: 1,
  debt: { m1: 4, m2: 1, m3: 0 }, attendance: { required: 40, marked: 35, rate: 87.5 },
  pending: { bonus: 0, discount: 2, sick: 1, referral: 0, payroll: 1 }, overdue: { bonus: 0, discount: 1, sick: 0, referral: 0, payroll: 0 } };
function world(o) {
  o = o || {};
  const state = {
    notify_settings: [Object.assign({ id: 'daily_report', enabled: true, days: [1, 2, 3, 4, 5, 6], hourFrom: 19 }, o.row || {})],
    telegram_links: [
      { id: 'L1', uid: 'D1', kind: 'staff', chatId: 9001, prefs: {}, status: 'active' },
      { id: 'L2', uid: 'D2', kind: 'staff', chatId: 9002, prefs: { daily: false }, status: 'active' },   // /sozlamalar'da o'chirgan
      { id: 'L3', uid: 'T1', kind: 'staff', chatId: 9003, prefs: {}, status: 'active' },                // endi Direktor emas
      { id: 'L4', uid: 'D3', kind: 'staff', chatId: 9004, prefs: {}, status: 'unlinked' },
      { id: 'L5', uid: 'P1', kind: 'parent', chatId: 9005, prefs: {}, status: 'active' },
      { id: 'L6', uid: 'DB', kind: 'staff', chatId: 9006, prefs: {}, status: 'active' }],               // bloklangan Direktor
    users: [{ id: 'D1', role: 'director', status: 'active' }, { id: 'D2', role: 'director', status: 'active' }, { id: 'T1', role: 'teacher', status: 'active' },
            { id: 'D3', role: 'director', status: 'active' }, { id: 'P1', role: 'parent', status: 'active' }, { id: 'DB', role: 'director', status: 'blocked' }],
    sms_log: [],
  };
  const fk = makeFake(state);
  const rpcCalls = [];
  const sb = { from: fk.from, rpc: async (fn, args) => { rpcCalls.push([fn, args]); if (fn === 'director_daily') return o.rpcErr ? { data: null, error: { message: 'boom' } } : { data: DAILY, error: null }; if (fn === 'tg_blocked') return { data: 1, error: null }; return { data: null, error: { message: 'unknown rpc ' + fn } }; } };
  const sent = [];
  const tg = { sendMessage: async (chat, text) => { sent.push({ chat, text }); return (o.block || []).includes(chat) ? { ok: false, blocked: true, error: 'blocked: Forbidden' } : { ok: true, id: sent.length }; } };
  const health = { runChecks: async () => o.checks || [{ key: 'db', name: 'Baza', ok: true }, { key: 'ai', name: 'AI yordamchi', ok: false, info: 'ulanib bo‘lmadi' }] };
  return { state, sb, tg, health, sent, rpcCalls, log: () => {} };
}
(async () => {
  console.log('\n— reja: o‘chiq / kun emas / soat yetmagan / yetgan');
  ok('o‘chiq', dailyPlan({ enabled: false, days: [1], hourFrom: 19 }, T(20)).reason === 'o‘chirilgan');
  ok('yakshanba — kun emas', dailyPlan({ enabled: true, days: [1, 2, 3, 4, 5, 6], hourFrom: 19 }, Date.parse('2026-11-01T15:00:00Z')).run === false);
  ok('18:30 — hali erta', /19:00/.test(dailyPlan({ enabled: true, days: [1], hourFrom: 19 }, T(18)).reason));
  ok('19:30 — yuboriladi', dailyPlan({ enabled: true, days: [1], hourFrom: 19 }, T(19)).run === true);
  ok('qator yo‘q — yo‘q', dailyPlan(null, T(20)).run === false);

  console.log('\n— matn');
  const txt = composeDaily(DAILY, [{ name: 'Baza', ok: true }, { name: 'AI yordamchi', ok: false, info: 'ulanib bo‘lmadi' }]);
  ok('sarlavha va sana', /kunlik hisobot \(02\.11\.2026\)/.test(txt), txt);
  ok('to‘lovlar: soni, summa, usul bo‘yicha', /To‘lovlar: 3 ta · 2 750 000 so‘m \(naqd 2 000 000 · Click 750 000\)/.test(txt), txt);
  ok('biriktirilmagan to‘lov ogohlantirishi', /biriktirilmagan: 1 ta/.test(txt));
  ok('qarzdorlar 1/2/3+', /1 oy — 4, 2 oy — 1, 3\+ oy — 0/.test(txt));
  ok('davomat 87,5% (35/40)', /87,5% \(35\/40\)/.test(txt), txt);
  ok('tasdiqlar navbatlar bo‘yicha + muddati o‘tgan', /chegirma 2 · «Bemor» kuni 1 · maosh 1 \(muddati o‘tgan: 1\)/.test(txt), txt);
  ok('tizim: faqat ishlamayotgan xizmat', /🩺 Tizim: ❌ AI yordamchi — ulanib bo‘lmadi/.test(txt) && !/Baza/.test(txt.split('🩺')[1]), txt);
  ok('hammasi ishlasa', /hammasi ishlayapti/.test(composeDaily(DAILY, [{ name: 'x', ok: true }, { name: 'y', ok: null }])));
  ok('dars kuni emas (davomat null)', /— \(bugun dars kuni emas\)/.test(composeDaily(Object.assign({}, DAILY, { attendance: { rate: null } }), null)));
  ok('kechikib kiritilgan yo‘q — qator yo‘q', !/oldingi kunlar sanasi/.test(txt), txt);
  {
    const t2 = composeDaily(Object.assign({}, DAILY, { late: { count: 2, sum: 1500000 }, payments: { count: 1, sum: 300000, byProvider: { terminal: 300000 } } }), null);
    ok('kechikib kiritilgan to‘lovlar alohida qator', /↩ Bugun kiritilgan, oldingi kunlar sanasi bilan: 2 ta · 1 500 000 so‘m/.test(t2), t2);
    ok('terminal nomi', /\(terminal 300 000\)/.test(t2), t2);
  }

  console.log('\n— yuborish: faqat faol Direktor, /sozlamalar, bir kunda bir marta');
  {
    const w = world();
    let r = await runDaily({ sb: w.sb, tg: w.tg, health: w.health, now: () => T(19), log: w.log });
    ok('1 ta yuborildi (D1); o‘chirgan, o‘qituvchi, uzilgan, ota-ona, bloklangan Direktor — yo‘q', r.sent === 1 && J(w.sent.map(s => s.chat)) === '[9001]', J([r, w.sent.map(s => s.chat)]));
    ok('director_daily — bugungi kun bilan', w.rpcCalls.some(([fn, a]) => fn === 'director_daily' && a.p_day === '2026-11-02'), J(w.rpcCalls));
    const lg = w.state.sms_log.find(x => x.id === 'daily__2026-11-02__L1');
    ok('sms_log: daily, telegram, sent', lg && lg.type === 'daily' && lg.channel === 'telegram' && lg.status === 'sent', J(lg));
    r = await runDaily({ sb: w.sb, tg: w.tg, health: w.health, now: () => T(20), log: w.log });
    ok('20:30 da qayta — yuborilmaydi (bugun yuborilgan)', r.sent === 0 && r.skipped === 1 && w.sent.length === 1, J(r));
    const w2 = world();
    const r2 = await runDaily({ sb: w2.sb, tg: w2.tg, health: w2.health, now: () => T(18), log: w2.log });
    ok('18:30 — yuborilmaydi', r2.sent === 0 && w2.sent.length === 0 && /19:00/.test(r2.reason), J(r2));
    const r3 = await runDaily({ sb: w2.sb, tg: w2.tg, health: w2.health, now: () => T(18), force: true, log: w2.log });
    ok('--force — vaqtdan oldin ham', r3.sent === 1, J(r3));
    const w3 = world({ row: { enabled: false } });
    ok('o‘chiq — yuborilmaydi', (await runDaily({ sb: w3.sb, tg: w3.tg, health: w3.health, now: () => T(20), log: w3.log })).sent === 0 && w3.sent.length === 0);
  }
  console.log('\n— --dry, bloklangan chat, RPC xatosi');
  {
    const w = world();
    const r = await runDaily({ sb: w.sb, tg: w.tg, health: w.health, now: () => T(19), dry: true, log: w.log });
    ok('--dry: matn qaytadi, hech narsa yuborilmaydi va yozilmaydi', r.dry && /kunlik hisobot/.test(r.text) && w.sent.length === 0 && w.state.sms_log.length === 0, J(r));
    const wb = world({ block: [9001] });
    const rb = await runDaily({ sb: wb.sb, tg: wb.tg, health: wb.health, now: () => T(19), log: wb.log });
    ok('bloklagan Direktor: failed + tg_blocked', rb.sent === 0 && wb.state.sms_log[0].status === 'failed' && wb.rpcCalls.some(([fn, a]) => fn === 'tg_blocked' && a.p_chat === 9001), J([rb, wb.state.sms_log, wb.rpcCalls]));
    const we = world({ rpcErr: true });
    const re = await runDaily({ sb: we.sb, tg: we.tg, health: we.health, now: () => T(19), log: we.log });
    ok('director_daily xatosi — yuborilmaydi, kod 1', re.sent === 0 && re.exit === 1 && we.sent.length === 0, J(re));
    const wn = world(); wn.state.telegram_links.length = 0;
    const rn = await runDaily({ sb: wn.sb, tg: wn.tg, health: wn.health, now: () => T(19), log: wn.log });
    ok('ulangan Direktor yo‘q', rn.reason === 'norecipients', J(rn));
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
