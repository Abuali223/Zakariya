// tg-daily.cjs — Direktorga kunlik hisobot: reja (yoqilgan / kun / soat), qabul qiluvchilar (faqat faol Direktor, /sozlamalar),
//   bir kunda bir marta, bloklangan chat -> tg_blocked, matn (to'lovlar, qarzdorlar, davomat, tasdiqlar, kassa bloki va nazorat
//   qatori, tizim holati); A6-05: qayta yuborish faqat ANIQ yetkazilmaganda (haqiqiy server/telegram.cjs mijozi bilan ham), oxirgi urinish.
const { makeFake } = require('./_fake.cjs');
const { composeDaily, kassaLines, dailyPlan, runDaily } = require('./tg-daily.cjs');
const { makeTelegram } = require('../server/telegram.cjs');
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
  // o.daily — director_daily javobi (obyekt yoki chaqiruv tartib raqami bo'yicha funksiya); o.tgRes — Telegram javobi (n-chi yuborish)
  const dailyOf = () => (typeof o.daily === 'function' ? o.daily(rpcCalls.filter(c => c[0] === 'director_daily').length) : (o.daily || DAILY));
  const sb = { from: fk.from, rpc: async (fn, args) => { rpcCalls.push([fn, args]); if (fn === 'director_daily') return o.rpcErr ? { data: null, error: { message: 'boom' } } : { data: dailyOf(), error: null }; if (fn === 'tg_blocked') return { data: 1, error: null }; return { data: null, error: { message: 'unknown rpc ' + fn } }; } };
  const sent = [];
  const tg = { sendMessage: async (chat, text) => { sent.push({ chat, text }); if (o.tgRes) return o.tgRes(sent.length, chat); return (o.block || []).includes(chat) ? { ok: false, blocked: true, error: 'blocked: Forbidden' } : { ok: true, id: sent.length }; } };
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
  // A2-02: kunlar tanlanmagan qatorda standart — Du–Ju (dars kunlari): shanba yuborilmaydi, dushanba — yuboriladi
  {
    const sat = Date.parse('2026-11-07T15:00:00Z');   // 2026-11-07 shanba, Toshkent 20:00
    const ps = dailyPlan({ enabled: true, hourFrom: 19 }, sat), pm = dailyPlan({ enabled: true, hourFrom: 19 }, T(20));
    ok('standart kunlar Du–Ju: shanba — kun emas, dushanba — yuboriladi', ps.run === false && ps.reason === 'bugun yuborish kuni emas' && pm.run === true && JSON.stringify(pm.days) === '[1,2,3,4,5]', JSON.stringify([ps, pm]));
  }

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
  // A6-01: sarlavhada «HH:MM holatiga»; oldingi hisobotdan keyin (kechqurun, shanba, yakshanba) tushgan to'lovlar — kassa kuni bo'yicha
  {
    const SINCE = { from: '2026-11-13T14:00:05+00:00', count: 3, sum: 1400000,
      byDay: [{ day: '2026-11-13', count: 1, sum: 200000 }, { day: '2026-11-14', count: 1, sum: 400000 }, { day: '2026-11-15', count: 1, sum: 800000 }] };
    const ts = composeDaily(Object.assign({}, DAILY, { day: '2026-11-16', asOf: '2026-11-16T14:00:01.123456+00:00', since: SINCE, late: { count: 1, sum: 50000 } }), null);
    ok('sarlavha: kun va ma’lumot olingan payt (Toshkent)', /kunlik hisobot \(16\.11\.2026, 19:00 holatiga\)/.test(ts), ts);
    ok('oldingi hisobotdan keyin tushgan: vaqti, soni, summa va kunlar bo‘yicha',
      /\n   🌙 Oldingi hisobotdan keyin \(13\.11\.2026 19:00 dan\) tushgan: 3 ta · 1 400 000 so‘m \(13\.11 — 200 000 · 14\.11 — 400 000 · 15\.11 — 800 000\)\n/.test(ts), ts);
    ok('tartib: bugungi to‘lovlar → oldingi hisobotdan keyin → bugun orqa sana bilan', ts.indexOf('💰 To‘lovlar') < ts.indexOf('🌙') && ts.indexOf('🌙') < ts.indexOf('↩ Bugun kiritilgan'), ts);
    ok('hech narsa tushmagan yoki oldingi hisobot yo‘q — qator yo‘q', !/🌙/.test(composeDaily(Object.assign({}, DAILY, { since: Object.assign({}, SINCE, { count: 0, sum: 0, byDay: [] }) }), null))
      && !/🌙/.test(composeDaily(Object.assign({}, DAILY, { since: null }), null)) && !/holatiga/.test(txt), txt);
    const long = Array.from({ length: 9 }, (_, i) => ({ day: `2026-11-0${i + 1}`, count: 1, sum: 1000 }));
    const tl = composeDaily(Object.assign({}, DAILY, { since: { from: '2026-11-01T00:00:00Z', count: 9, sum: 9000, byDay: long } }), null);
    ok('7 kundan ko‘p — faqat jami (ro‘yxatsiz)', /🌙 Oldingi hisobotdan keyin \(01\.11\.2026 05:00 dan\) tushgan: 9 ta · 9 000 so‘m\n/.test(tl), tl);
  }
  // A6-07: biriktirilmaganlar — BARCHASI, summa va eng eskisi bilan; A6-03: ketgan / muzlatilganlarning eski qarzi alohida yorliq bilan
  {
    const tu = composeDaily(Object.assign({}, DAILY, { unmatched: 2, unmatchedSum: 750000, unmatchedSince: '2026-11-10',
      debt: { m1: 1, m2: 1, m3: 1, inactive: { n: 2, m2plus: 2, sum: 5000000 } } }), null);
    ok('biriktirilmagan: soni, summa, eng eskisi', /⚠️ O‘quvchiga biriktirilmagan: 2 ta · 750 000 so‘m \(eng eskisi 10\.11\.2026\) — «To‘lovlar»da biriktiring/.test(tu), tu);
    ok('qarzdorlar: ketgan / muzlatilgan alohida (eski qarz)', /🧾 Qarzdorlar: 1 oy — 1, 2 oy — 1, 3\+ oy — 1 \(shu jumladan ketgan \/ muzlatilgan: 2 · 5 000 000 so‘m — eski qarz, undiriladi\)/.test(tu), tu);
    ok('ketgan / muzlatilgan qarzdor yo‘q — yorliq yo‘q', !/ketgan/.test(txt) && !/ketgan/.test(composeDaily(Object.assign({}, DAILY, { debt: { m1: 1, m2: 0, m3: 0, inactive: { n: 0, m2plus: 0, sum: 0 } } }), null)), txt);
  }

  console.log('\n— kassa bloki va nazorat qatori (RP-05)');
  {
    ok('kassa moduli yo‘q — blok ham, nazorat qatori ham yo‘q', !/Kassa/.test(txt), txt);
    const K = { live: true, balance: 2525000,
      day: { day: '2026-11-02', status: 'closed', opening: 2000000, receipts: 2730000, payouts: 2205000, closing: 2525000, counted: 2525000, diff: -5000, n1: 7, n2: 4, voids: 1,
             transfers: { inCount: 1, inAmount: 1000000, outCount: 1, outAmount: 1500000 } },
      control: { reconcile: 0, openDay: null, staleOpenDay: null, unverifiedDays: 1, voids: 1, diff: -5000, undecidedShortages: 1, waitingApproval: 1, approvedUnpaid: 2, staleRefunds: 0, gaps: 0, fiscalExempt: 0, limitExceeded: false } };
    const tk = composeDaily(Object.assign({}, DAILY, { kassa: K }), null);
    ok('kassa: kun jamlari (kun boshi + kirim − chiqim = kun oxiri) — kunlik hisobot bilan bir xil raqamlar',
      /🏦 Kassa \(yopilgan\): kun boshi 2 000 000 \+ kirim 2 730 000 \(7 ta\) − chiqim 2 205 000 \(4 ta\) = 2 525 000 so‘m/.test(tk), tk);
    ok('kassa: sanash va kamomad', /Sanaldi: 2 525 000 so‘m · ⚠️ KAMOMAD 5 000 so‘m/.test(tk), tk);
    ok('kassa: bank o‘tkazmalari alohida (kirim / xarajat emas)', /Bank \(ichki o‘tkazma\): olindi 1 000 000 · topshirildi 1 500 000 so‘m/.test(tk), tk);
    ok('nazorat qatori: moslik, ochiq kun, bekor qilishlar, farq — doim; qolganlari — bor bo‘lsa',
      /🔎 Kassa nazorati: moslik ✓ · yopilmagan o‘tgan kun yo‘q · bekor qilingan: 1 · ⚠️ farq: −5 000 · ⚠️ qarorsiz kamomad: 1 · tekshirilmagan kun: 1 · tasdiq kutmoqda: 1 · pul berilmagan: 2$/m.test(tk), tk);
    ok('kassa bloki to‘lovlar va tizim qatorlari orasida, tartib saqlangan', tk.indexOf('✅ Kutilayotgan') < tk.indexOf('🏦 Kassa') && tk.indexOf('🔎 Kassa nazorati') < tk.indexOf('🩺 Tizim'), tk);
    const K2 = { live: true, balance: 2530000, day: { status: 'open', opening: 2000000, receipts: 2730000, payouts: 2200000, closing: 2530000, counted: null, diff: null, n1: 7, n2: 3, voids: 0, transfers: { inAmount: 0, outAmount: 0 } },
      control: { reconcile: 3, staleOpenDay: '2026-10-31', voids: 0, diff: 0, gaps: 1, limitExceeded: true, staleRefunds: 2, fiscalExempt: 1 } };
    const t2 = composeDaily(Object.assign({}, DAILY, { kassa: K2 }), null);
    ok('ochiq kun: «hali yopilmagan», sanash qatori yo‘q, bank qatori yo‘q', /🏦 Kassa \(ochiq\): .* = 2 530 000 so‘m\n   ⏳ Kun hali yopilmagan — pul sanalmagan\n🔎/.test(t2) && !/Sanaldi|Bank \(ichki/.test(t2), t2);
    ok('nazorat: moslik buzilgan, eski ochiq kun, kechikkan qaytarish, bo‘shliq, fiskal cheksiz, limit',
      /⚠️ moslik buzilgan: 3 ta · ⚠️ yopilmagan kun: 31\.10\.2026 · bekor qilingan: 0 · farq yo‘q · ⚠️ kechikkan qaytarish: 2 · ⚠️ raqamlashda bo‘shliq · fiskal cheksiz: 1 · ⚠️ qoldiq limitdan oshgan/.test(t2), t2);
    const t3 = composeDaily(Object.assign({}, DAILY, { kassa: { live: false, balance: 500000, day: null, control: { reconcile: 0, voids: 0, diff: 0 } } }), null);
    ok('harakatsiz kun: qoldiq; kassa ishga tushmagan — moslik hisoblanmaydi', /🏦 Kassa: bugun harakat yo‘q · qoldiq 500 000 so‘m\n🔎 Kassa nazorati: moslik — kassa hali ishga tushmagan · yopilmagan o‘tgan kun yo‘q · bekor qilingan: 0 · farq yo‘q/.test(t3), t3);
    ok('ortiqcha', /⚠️ ortiqcha 1 200 so‘m/.test(kassaLines({ day: { status: 'verified', opening: 0, receipts: 0, payouts: 0, closing: 1200, counted: 1200, diff: 1200 }, control: { diff: 1200 } }).join('\n')));
    ok('noto‘g‘ri kirish — bo‘sh', kassaLines(null).length === 0 && kassaLines('x').length === 0);
    // acc-6: smena topshirishdagi farq — kun qatorida va nazorat qatorida yopish farqi yonida (bo'lmasa — avvalgi matn)
    const hl = kassaLines({ live: true, balance: 0, day: { status: 'closed', opening: 0, receipts: 0, payouts: 0, closing: 0, counted: 0, diff: -2000, handoverDiffs: [5000, 0], n1: 0, n2: 0 },
      control: { reconcile: 0, voids: 0, diff: -2000, handoverDiffs: [5000] } }).join('\n');
    ok('smena topshirishdagi farq: kun qatori', /Sanaldi: 0 so‘m · kunni yopishda: ⚠️ KAMOMAD 2 000 so‘m · smena topshirishda: ⚠️ ortiqcha 5 000 so‘m/.test(hl), hl);
    ok('smena topshirishdagi farq: nazorat qatori', /· ⚠️ farq: yopishda −2 000, smenada \+5 000 ·|· ⚠️ farq: yopishda −2 000, smenada \+5 000$/m.test(hl), hl);
    const ho = kassaLines({ live: true, balance: 0, day: { status: 'open', opening: 0, receipts: 0, payouts: 0, closing: 0, handoverDiffs: [-7000] }, control: { reconcile: 0, voids: 0, diff: 0, handoverDiffs: [-7000] } }).join('\n');
    ok('ochiq kun: smena topshirishdagi farq ko‘rinadi; yopish farqi yo‘q bo‘lsa — faqat smena', /⏳ Kun hali yopilmagan — pul sanalmagan · smena topshirishda: ⚠️ KAMOMAD 7 000 so‘m/.test(ho) && /· ⚠️ farq: smenada −7 000( ·|$)/m.test(ho), ho);
    ok('dushanba KPI: smena topshirishdagi farqlar soni', /farqli kun 1 \(kamomad 2 000\) \(ortiqcha 5 000\) \(smena topshirishda 1\)/.test(
      kassaLines({ day: null, balance: 0, control: { reconcile: 0, voids: 0, diff: 0 }, week: { from: '2027-01-04', to: '2027-01-10', closed: 1, onTime: 1, diffDays: 1, shortage: 2000, surplus: 5000, handoverDiffs: 1 } }).join('\n')));
    const zl = z => kassaLines({ day: null, balance: 0, control: { reconcile: 0, voids: 0, diff: 0, z } }).join('\n');
    ok('Z-hisobot: mos yoki kun yopilmagan — qator yo‘q', !/Z-hisobot/.test(zl({ ok: true, recorded: true })) && !/Z-hisobot/.test(zl(null)), zl({ ok: true }));
    ok('Z-hisobot farqi: naqd −10 000, karta +5 000', /· ⚠️ Z-hisobot farqi: naqd −10 000, karta \+5 000$/.test(zl({ ok: false, recorded: true, missing: false, diffCash: -10000, diffCard: 5000 })), zl({ ok: false, recorded: true, diffCash: -10000, diffCard: 5000 }));
    ok('Z-hisobot kiritilmagan / yo‘q', /⚠️ Z-hisobot kiritilmagan$/.test(zl({ ok: false, recorded: false })) && /⚠️ Z-hisobot yo‘q \(sababi yozilgan\)$/.test(zl({ ok: false, recorded: true, missing: true })));
    const shl = sh => kassaLines({ day: null, balance: 0, control: { reconcile: 0, voids: 0, diff: 0, staleHandover: sh } }).join('\n');
    ok('qabul qilinmagan smena topshirish: vaqti bilan, ismsiz; yo‘q bo‘lsa — qator yo‘q',
      /· ⚠️ qabul qilinmagan smena topshirish \(16\.01\.2027 09:05 dan\)$/.test(shl({ id: 'h1', day: '2027-01-16', createdAt: '2027-01-16T04:05:00+00:00', fromName: 'Sinov Kassir', toName: 'Sinov Kassir Ikki', counted: 1000 }))
      && !/Sinov/.test(shl({ createdAt: '2027-01-16T04:05:00Z', fromName: 'Sinov Kassir' })) && !/smena topshirish/.test(shl(null)) && !/smena topshirish/.test(shl(undefined))
      && /· ⚠️ qabul qilinmagan smena topshirish$/.test(shl({ createdAt: 'x' })), shl({ createdAt: '2027-01-16T04:05:00+00:00' }));
    const al = ao => kassaLines({ day: null, balance: 0, control: { reconcile: 0, voids: 0, diff: 0, accOverdue: ao } }).join('\n');
    ok('eslatma: muddati o‘tgan avans — nazorat qatorida; yo‘q bo‘lsa — qator yo‘q', /· ⚠️ muddati o‘tgan avans: 2 \(200 000 so‘m\)$/.test(al({ n: 2, sum: 200000 })) && !/avans/.test(al({ n: 0, sum: 0 })) && !/avans/.test(al(null)), al({ n: 2, sum: 200000 }));
    const wl = wk => kassaLines({ day: null, balance: 0, control: { reconcile: 0, voids: 0, diff: 0 }, week: wk }).join('\n');
    ok('dushanba: o‘tgan hafta KPI qatori', /\n📈 Kassa — o‘tgan hafta \(04\.01\.2027–10\.01\.2027\): o‘sha kuni yopilgan 2\/3 kun · tekshirilmagan 1 · farqli kun 1 \(kamomad 5 000\) · «Boshqa xarajatlar» 25% ⚠️ · ⚠️ muddati o‘tgan avans 1 · qayta ochilgan 1$/.test(
      wl({ from: '2027-01-04', to: '2027-01-10', closed: 3, onTime: 2, unverified: 1, diffDays: 1, shortage: 5000, surplus: 0, ex49Share: 25, accOverdue: { n: 1, sum: 150000 }, reopened: 1 })),
      wl({ from: '2027-01-04', to: '2027-01-10', closed: 3, onTime: 2, unverified: 1, diffDays: 1, shortage: 5000, ex49Share: 25, accOverdue: { n: 1 }, reopened: 1 }));
    ok('toza hafta: farq yo‘q, EX-49 yo‘q bo‘lsa — ko‘rsatilmaydi; boshqa kunlari — qator yo‘q', /📈 Kassa — o‘tgan hafta \(04\.01\.2027–10\.01\.2027\): o‘sha kuni yopilgan 5\/5 kun · farq yo‘q$/.test(
      wl({ from: '2027-01-04', to: '2027-01-10', closed: 5, onTime: 5, diffDays: 0, ex49Share: null, accOverdue: { n: 0 } })) && !/📈/.test(wl(null)), wl({ from: '2027-01-04', to: '2027-01-10', closed: 5, onTime: 5 }));
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
    const rb2 = await runDaily({ sb: wb.sb, tg: wb.tg, health: wb.health, now: () => T(20), log: wb.log });
    ok('bloklagan Direktorga keyingi run ham qayta yubormaydi', rb2.sent === 0 && rb2.skipped === 1 && wb.sent.length === 1, J([rb2, wb.state.sms_log]));
  }
  console.log('\n— A6-01: jurnal qatori vaqti = ma’lumot olingan payt (keyingi hisobot oynasi shundan)');
  {
    const AS = '2026-11-02T14:30:00.654321+00:00';
    const w = world({ daily: Object.assign({}, DAILY, { asOf: AS }) });
    await runDaily({ sb: w.sb, tg: w.tg, health: w.health, now: () => T(19), log: w.log });
    const lg = w.state.sms_log.find(x => x.id === 'daily__2026-11-02__L1');
    ok('sms_log.createdAt = director_daily.asOf (yuborish payti emas)', lg && lg.createdAt === AS && lg.status === 'sent', J(lg));
    const w0 = world();
    await runDaily({ sb: w0.sb, tg: w0.tg, health: w0.health, now: () => T(19), log: w0.log });
    ok('asOf yo‘q (eski baza) — createdAt baza standarti', !!(w0.state.sms_log[0] && w0.state.sms_log[0].createdAt && w0.state.sms_log[0].createdAt !== AS), J(w0.state.sms_log));
  }
  console.log('\n— A6-05: vaqtinchalik xatodan keyin qayta yuborish (takrorsiz)');
  {
    // 1-urinish tarmoq xatosi, keyingisi — muvaffaqiyatli; har run yangi ma'lumot (asOf) bilan
    const asOfN = n => Object.assign({}, DAILY, { asOf: `2026-11-02T14:${String(15 * n).padStart(2, '0')}:00+00:00` });
    const w = world({ daily: asOfN, tgRes: n => (n === 1 ? { ok: false, status: 0, error: 'network: ECONNREFUSED' } : { ok: true, id: n }) });
    const r1 = await runDaily({ sb: w.sb, tg: w.tg, health: w.health, now: () => T(19), log: w.log });
    const lg = () => w.state.sms_log.find(x => x.id === 'daily__2026-11-02__L1');
    ok('1-run: yetkazilmadi — failed, qayta urinish belgisi bilan', r1.sent === 0 && lg().status === 'failed' && /^retry: network/.test(lg().error) && Number(lg().attempts) === 1, J([r1, lg()]));
    const r2 = await runDaily({ sb: w.sb, tg: w.tg, health: w.health, now: () => T(19) + 15 * 60e3, log: w.log });
    ok('2-run (15 daqiqadan keyin): qayta yuborildi — sent, 2-urinish, yangi ma’lumot vaqti', r2.sent === 1 && r2.retried === 1 && lg().status === 'sent' && Number(lg().attempts) === 2 && lg().error === ''
      && lg().createdAt === asOfN(2).asOf && w.sent.length === 2, J([r2, lg()]));
    const r3 = await runDaily({ sb: w.sb, tg: w.tg, health: w.health, now: () => T(20), log: w.log });
    ok('3-run: bugun yuborilgan — takror yo‘q', r3.sent === 0 && r3.skipped === 1 && w.sent.length === 2, J([r3, lg()]));
    // timeout — xabar yetgan bo'lishi mumkin: qayta yuborilmaydi (Direktorga ikki marta ketmasin)
    const wt = world({ tgRes: () => ({ ok: false, status: 0, timeout: true, error: 'timeout' }) });
    await runDaily({ sb: wt.sb, tg: wt.tg, health: wt.health, now: () => T(19), log: wt.log });
    const rt = await runDaily({ sb: wt.sb, tg: wt.tg, health: wt.health, now: () => T(19) + 15 * 60e3, log: wt.log });
    ok('timeout (noaniq) — qayta yuborilmaydi', rt.sent === 0 && rt.skipped === 1 && wt.sent.length === 1 && wt.state.sms_log[0].status === 'failed' && !/^retry: /.test(wt.state.sms_log[0].error), J([rt, wt.state.sms_log]));
    // doim 5xx — jami MAXTRIES (3) urinish, keyin to'xtaydi
    const wf = world({ tgRes: () => ({ ok: false, status: 502, error: 'Bad Gateway' }) });
    for (let i = 0; i < 5; i++) await runDaily({ sb: wf.sb, tg: wf.tg, health: wf.health, now: () => T(19) + i * 15 * 60e3, log: wf.log });
    ok('doim xato (5xx): 3 urinishdan keyin to‘xtaydi', wf.sent.length === 3 && Number(wf.state.sms_log[0].attempts) === 3 && wf.state.sms_log[0].status === 'failed', J([wf.sent.length, wf.state.sms_log]));
    // eski (tuzatishdan oldingi) prefikssiz 'failed' qator — qayta yuborilmaydi
    const wo = world(); wo.state.sms_log.push({ id: 'daily__2026-11-02__L1', type: 'daily', status: 'failed', attempts: 1, error: 'network: x', channel: 'telegram', phone: '' });
    const ro = await runDaily({ sb: wo.sb, tg: wo.tg, health: wo.health, now: () => T(19), log: wo.log });
    ok('prefikssiz eski xato qatori — o‘tkaziladi', ro.sent === 0 && ro.skipped === 1 && wo.sent.length === 0, J(ro));
    // 'sending' (boshqa run yuborayotgan yoki uzilgan — noaniq) — o'tkaziladi
    const ws = world(); ws.state.sms_log.push({ id: 'daily__2026-11-02__L1', type: 'daily', status: 'sending', attempts: 1, error: '', channel: 'telegram', phone: '' });
    const rs = await runDaily({ sb: ws.sb, tg: ws.tg, health: ws.health, now: () => T(19), log: ws.log });
    ok('yuborilmoqda (sending) — o‘tkaziladi', rs.sent === 0 && rs.skipped === 1 && ws.sent.length === 0, J(rs));
  }
  console.log('\n— A6-05 (2-raund): haqiqiy Telegram mijozi — Telegram xabarni qabul qilgan bo‘lishi mumkin bo‘lsa qayta yuborilmaydi; oxirgi urinish');
  {
    // world() ning soxta tg o'rniga haqiqiy server/telegram.cjs (soxta fetch bilan) — natija tasnifi (timeout) tg-daily qaroriga yetadi
    const fetchFailed = code => { const e = new TypeError('fetch failed'); e.cause = Object.assign(new Error('x ' + code), { code }); return e; };
    const realTg = step => { const calls = []; const tg = makeTelegram({ token: '1:T', timeoutMs: 1000, sleep: async () => {}, fetchImpl: async () => {
      calls.push(1); const s = typeof step === 'function' ? step(calls.length) : step;
      if (s.throw) throw s.throw;
      return { status: s.status, json: async () => { if (s.badJson) throw new SyntaxError('Unexpected end of JSON input'); return s.json; } }; } });
      return { tg, calls }; };
    const twoRuns = async step => {
      const w = world(), c = realTg(step);
      await runDaily({ sb: w.sb, tg: c.tg, health: w.health, now: () => T(19), log: w.log });
      const lg1 = Object.assign({}, w.state.sms_log.find(x => x.id === 'daily__2026-11-02__L1'));
      const r2 = await runDaily({ sb: w.sb, tg: c.tg, health: w.health, now: () => T(19) + 15 * 60e3, log: w.log });
      return { lg1, r2, n: c.calls.length, lg2: w.state.sms_log.find(x => x.id === 'daily__2026-11-02__L1') };
    };
    // ulanishdan KEYIN uzilish (Telegram xabarni qabul qilgan bo'lishi mumkin) — avval 'network: fetch failed' bo'lib qayta yuborilardi
    const a = await twoRuns({ throw: fetchFailed('ECONNRESET') });
    ok('ECONNRESET (so‘rov yuborilgan bo‘lishi mumkin) — failed, belgisiz; keyingi run qayta YUBORMAYDI', a.lg1.status === 'failed' && !/^retry: /.test(a.lg1.error) && /ECONNRESET/.test(a.lg1.error)
      && a.r2.sent === 0 && a.r2.skipped === 1 && a.n === 1, J(a));
    // 200 keldi, lekin tanasi o'qilmadi — Telegram qabul qilgan: avval 'HTTP 200' bo'lib qayta yuborilardi (Direktorga takror hisobot)
    const b = await twoRuns({ status: 200, badJson: true });
    ok('200, tanasi o‘qilmadi — failed, belgisiz; keyingi run qayta YUBORMAYDI', b.lg1.status === 'failed' && !/^retry: /.test(b.lg1.error) && b.r2.sent === 0 && b.r2.skipped === 1 && b.n === 1, J(b));
    // ulanishdan OLDIN (DNS / rad etildi) — aniq ketmagan: qayta yuboriladi (avvalgidek)
    const c = await twoRuns(n => (n === 1 ? { throw: fetchFailed('ECONNREFUSED') } : { status: 200, json: { ok: true, result: { message_id: 5 } } }));
    ok('ECONNREFUSED (so‘rov ketmagan) — retry belgisi; keyingi run qayta yuboradi va yetkazadi', /^retry: network: ECONNREFUSED/.test(c.lg1.error) && c.r2.sent === 1 && c.r2.retried === 1
      && c.lg2.status === 'sent' && Number(c.lg2.attempts) === 2 && c.n === 2, J(c));
    // doim 5xx: 1- va 2-urinish — «keyingi run qayta yuboradi», 3- (oxirgi) — «oxirgi urinish», belgisiz; 4-run — yubormaydi
    const logs = [];
    const wf = world({ tgRes: () => ({ ok: false, status: 502, error: 'Bad Gateway' }) });
    for (let i = 0; i < 4; i++) await runDaily({ sb: wf.sb, tg: wf.tg, health: wf.health, now: () => T(19) + i * 15 * 60e3, log: (...m) => logs.push(m.join(' ')) });
    const fl = logs.filter(x => /yetkazilmadi/.test(x));
    ok('oxirgi (3-) urinish log’da aytiladi; oldingilari — «keyingi run qayta yuboradi»', fl.length === 3 && /keyingi run qayta yuboradi \(1\/3/.test(fl[0]) && /keyingi run qayta yuboradi \(2\/3/.test(fl[1])
      && /oxirgi \(3-\) urinish edi/.test(fl[2]) && !/keyingi run/.test(fl[2]), J(fl));
    ok('oxirgi urinishdan keyin: 3 urinish, belgisiz xato, 4-run yubormaydi', wf.sent.length === 3 && Number(wf.state.sms_log[0].attempts) === 3 && wf.state.sms_log[0].error === 'Bad Gateway', J([wf.sent.length, wf.state.sms_log]));
    // noaniq (timeout) — log'da sababi bilan
    const lt = [];
    const wt = world({ tgRes: () => ({ ok: false, status: 0, timeout: true, error: 'timeout' }) });
    await runDaily({ sb: wt.sb, tg: wt.tg, health: wt.health, now: () => T(19), log: (...m) => lt.push(m.join(' ')) });
    ok('noaniq natija — log: «qayta yuborilmaydi»', lt.some(x => /yetkazilmadi: timeout — natija noaniq .*qayta yuborilmaydi/.test(x)), J(lt));
  }
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
