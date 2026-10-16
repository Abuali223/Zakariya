// =====================================================================
// sms-remind.test.cjs — «Qarzdorlar» → «Eslatma» (auth/sms-remind.cjs) birlik testlari (tashqi xizmatsiz).
//   node sms-remind.test.cjs
// =====================================================================
const { makeFake } = require('./_fake.cjs');
const { makeSmsRemind, debtOf, smsName, humanEskizError } = require('./sms-remind.cjs');

let pass = 0, fail = 0;
const ok = (name, cond, extra) => { if (cond) pass++; else { fail++; console.log('  ✗ FAIL:', name, extra != null ? '→ ' + JSON.stringify(extra) : ''); } };
const sec = s => console.log('\n— ' + s);

// 2026-10-16 10:00 Toshkent (05:00Z)
const T0 = Date.parse('2026-10-16T05:00:00Z');
function setup(opts) {
  const o = opts || {};
  const state = {};
  let clock = o.now || T0;
  state.__now = () => clock;
  const sb = makeFake(state);
  const sent = [];
  let failNext = o.failNext || 0;
  let throwNext = o.throwNext || 0, resultNext = o.resultNext ? o.resultNext.slice() : [];
  const mkErr = o.throwErr || (() => { const e = new Error('eskiz_timeout'); e.stage = 'send'; return e; });
  const eskiz = o.dry ? null : { send: async (phone, msg) => {
    if (throwNext > 0) { throwNext--; throw mkErr(); }
    if (resultNext.length) return resultNext.shift();
    if (failNext > 0) { failNext--; return { ok: false, error: 'Этот смс текст еще не прошел модерацию' }; }
    sent.push({ phone, msg }); return { ok: true, id: 'esk' + sent.length };
  } };
  state.users = [
    { id: 'uid_dir', role: 'director', status: 'active' },
    { id: 'uid_fin', role: 'finance_mgr', status: '' },
    { id: 'uid_blk', role: 'director', status: 'blocked' },
    { id: 'uid_tch', role: 'teacher', status: 'active' },
    { id: 'uid_kas', role: 'kassir', status: 'active' },
  ];
  state.students = [
    { id: 'd255', studentId: 'IQ-0255', name: 'Qobiljonov Muhammadiy' },
    { id: 'd268', studentId: 'IQ-0268', name: 'Oʻgʻiloy  Qobiljonova' },
    { id: 'IQ-0300', studentId: '', name: 'Hujjat Kalitli' },            // studentId bo'sh -> kalit = id
    { id: 'c1', studentId: 'IQ-0400', name: 'Birinchi' },               // to'qnashuv
    { id: 'c2', studentId: 'IQ-0400', name: 'Ikkinchi' },
    { id: 'd500', studentId: 'IQ-0500', name: 'Taxallus Bola' },        // maxfiy yozuv studentId bilan kalitlangan
    { id: 'd600', studentId: 'IQ-0600', name: 'Begona Taxallus' },
    { id: 'IQ-0600', studentId: 'IQ-0601', name: 'Boshqa Bola' },        // IQ-0600 — boshqa o'quvchining hujjat id'si
    { id: 'IQ-0800', studentId: 'IQ-0801', name: 'Hujjat Bola' },        // to'qnashuv: hujjat id = boshqa bolaning studentId'si
    { id: 'x800', studentId: 'IQ-0800', name: 'Kalit Bola' },
    { id: 'dOld', studentId: 'IQ-0900', name: 'Eski Faktura' },          // eski faktura hujjat id bilan kalitlangan
    { id: 'IQ-0610', studentId: 'IQ-0611', name: 'Taxallussiz' },        // o'z maxfiy yozuvi yo'q; 'IQ-0611' — boshqa bolaning hujjati
    { id: 'IQ-0611', studentId: 'IQ-0612', name: 'Boshqa Oila' },
    ...[1, 2, 3, 4, 5].map(k => ({ id: 'p' + k, studentId: 'IQ-100' + k, name: 'Parallel Bola' + k })),
    { id: 'IQ-0820', studentId: 'IQ-0821', name: 'Ikki Kalitli' },       // hujjat id = BOSHQA bolaning studentId'si
    { id: 'y820', studentId: 'IQ-0820', name: 'Begona Bola' },
    { id: 'm6', studentId: 'IQ-0606', name: 'Ko‘p Oylik' },
    { id: 'd700', studentId: 'IQ-0700', name: 'Qarzsiz Bola' },          // fakturasi bor, lekin qarzi yo'q
    { id: 'i380', studentId: 'IQ-0380', name: 'Obidova Mehrinigor' },     // chet el raqami (+48)
    { id: 'i226', studentId: 'IQ-0226', name: 'Ismoilov Iskandar' },      // '+'siz chet el raqami (noaniq)
    { id: 'i466', studentId: 'IQ-0466', name: 'Ma\'mirjonov Azizbek' },  // ota chet el, ona O'zbekiston
  ];
  state.student_private = [
    { id: 'd255', parentPhone: '+998 70 014 37 77', parentPhone2: '' },
    { id: 'd268', parentPhone: '123', parentPhone2: '901234567' },       // 1-raqam yaroqsiz -> 2-raqam
    { id: 'IQ-0300', parentPhone: '998935554433' },
    { id: 'c1', parentPhone: '998901111111' }, { id: 'c2', parentPhone: '998902222222' },
    { id: 'IQ-0500', parentPhone: '998977777777' },
    { id: 'IQ-0600', parentPhone: '998998888888' },
    { id: 'IQ-0800', parentPhone: '998931111111' }, { id: 'x800', parentPhone: '998932222222' },
    { id: 'dOld', parentPhone: '998933333333' },
    { id: 'IQ-0611', parentPhone: '998934444444' },
    ...[1, 2, 3, 4, 5].map(k => ({ id: 'p' + k, parentPhone: '99890500000' + k })),
    { id: 'IQ-0820', parentPhone: '998935550000' }, { id: 'y820', parentPhone: '998935551111' }, { id: 'm6', parentPhone: '998935552222' },
    { id: 'd700', parentPhone: '998935553333' },
    { id: 'i380', parentPhone: '+48789706619', parentPhone2: '' },
    { id: 'i226', parentPhone: '79031571124', parentPhone2: '' },
    { id: 'i466', parentPhone: '+7 963 768 23 01', parentPhone2: '90 123 45 67' },
  ];
  state.invoices = [
    { id: 'IQ-0255__2026-09', studentId: 'IQ-0255', month: '2026-09', amount: 2610000, paidAmount: 0, status: 'pending' },
    { id: 'IQ-0255__2026-10', studentId: 'IQ-0255', month: '2026-10', amount: 2900000, paidAmount: 1000000, status: 'partial' },
    { id: 'IQ-0255__2026-08', studentId: 'IQ-0255', month: '2026-08', amount: 2900000, paidAmount: 0, status: 'paid' },
    { id: 'IQ-0255__2026-07', studentId: 'IQ-0255', month: '2026-07', amount: 2900000, paidAmount: 0, status: 'canceled' },
    { id: 'IQ-0255__2026-06', studentId: 'IQ-0255', month: '2026-06', amount: 2900000, paidAmount: 0, status: 'reversed' },
    { id: 'IQ-0255__2026-11', studentId: 'IQ-0255', month: '2026-11', amount: 2900000, paidAmount: 0, status: 'pending' },   // kelgusi oy — qarz emas
    { id: 'IQ-0268__2026-10', studentId: 'IQ-0268', month: '2026-10', amount: 2900000, paidAmount: 0, status: 'pending' },
    { id: 'IQ-0300__2026-10', studentId: 'IQ-0300', month: '2026-10', amount: 100000, paidAmount: 0, status: 'pending' },
    { id: 'IQ-0400__2026-10', studentId: 'IQ-0400', month: '2026-10', amount: 100000, paidAmount: 0, status: 'pending' },
    { id: 'IQ-0500__2026-10', studentId: 'IQ-0500', month: '2026-10', amount: 100000, paidAmount: 0, status: 'pending' },
    { id: 'IQ-0600__2026-10', studentId: 'IQ-0600', month: '2026-10', amount: 100000, paidAmount: 0, status: 'pending' },
    { id: 'IQ-0700__2026-10', studentId: 'IQ-0700', month: '2026-10', amount: 0, paidAmount: 0, status: 'paid' },
    { id: 'IQ-0800__2026-10', studentId: 'IQ-0800', month: '2026-10', amount: 100000, paidAmount: 0, status: 'pending' },
    { id: 'dOld__2026-09', studentId: 'dOld', month: '2026-09', amount: 50000, paidAmount: 0, status: 'pending' },
    { id: 'IQ-0610__2026-10', studentId: 'IQ-0610', month: '2026-10', amount: 100000, paidAmount: 0, status: 'pending' },
    { id: 'IQ-0900__2026-10', studentId: 'IQ-0900', month: '2026-10', amount: 70000, paidAmount: 0, status: 'pending' },
    ...[1, 2, 3, 4, 5].map(k => ({ id: 'IQ-100' + k + '__2026-10', studentId: 'IQ-100' + k, month: '2026-10', amount: 100000, paidAmount: 0, status: 'pending' })),
    { id: 'IQ-0821__2026-10', studentId: 'IQ-0821', month: '2026-10', amount: 100000, paidAmount: 0, status: 'pending' },
    { id: 'IQ-0820__2026-10', studentId: 'IQ-0820', month: '2026-10', amount: 555000, paidAmount: 0, status: 'pending' },   // Begona Bola'niki
    ...['2026-05', '2026-06', '2026-08', '2026-09', '2026-10'].map(m => ({ id: 'IQ-0606__' + m, studentId: 'IQ-0606', month: m, amount: 100000, paidAmount: 0, status: 'pending' })),
    ...['IQ-0380', 'IQ-0226', 'IQ-0466'].map(k => ({ id: k + '__2026-10', studentId: k, month: '2026-10', amount: 300000, paidAmount: 0, status: 'pending' })),
  ];
  state.sms_log = [];
  const R = makeSmsRemind({ sb, eskiz, smsCfg: o.smsCfg || {}, now: () => clock,
    verifyJwt: async jwt => (jwt && String(jwt).startsWith('uid_')) ? jwt : null });
  return { state, R, sent, setClock: t => { clock = t; } };
}

(async () => {
  sec('yordamchilar');
  ok('debtOf partial', debtOf({ amount: 2900000, paidAmount: 1000000, status: 'partial' }) === 1900000);
  ok('debtOf paid/canceled/reversed = 0', [ 'paid', 'canceled', 'reversed' ].every(s => debtOf({ amount: 5, paidAmount: 0, status: s }) === 0));
  ok('smsName apostrof + bo\'shliq', smsName('Oʻgʻiloy  Qobiljonova') === "O'g'iloy Qobiljonova", smsName('Oʻgʻiloy  Qobiljonova'));
  ok('Eskiz moderatsiya xatosi tushunarli', /SHABLON/.test(humanEskizError('Этот смс текст еще не прошел модерацию')));

  sec('kim yubora oladi');
  { const { R, sent } = setup();
    ok('JWT yo\'q -> rad', /Seans/.test((await R({ studentId: 'IQ-0255' })).error || ''));
    ok('o\'qituvchi -> rad', /Ruxsat/.test((await R({ jwt: 'uid_tch', studentId: 'IQ-0255' })).error || ''));
    ok('kassir (standart) -> rad', /Ruxsat/.test((await R({ jwt: 'uid_kas', studentId: 'IQ-0255' })).error || ''));
    ok('bloklangan direktor -> rad', /Ruxsat/.test((await R({ jwt: 'uid_blk', studentId: 'IQ-0255' })).error || ''));
    ok('noma\'lum foydalanuvchi -> rad', /Ruxsat/.test((await R({ jwt: 'uid_xxx', studentId: 'IQ-0255' })).error || ''));
    ok('hech narsa yuborilmadi', sent.length === 0);
    const f = await R({ jwt: 'uid_fin', studentId: 'IQ-0255', preview: true });
    ok('moliya menejeri (status bo\'sh = faol) -> ruxsat', f.ok === true, f); }
  { const { R } = setup({ smsCfg: { remindRoles: ['director', 'finance_mgr', 'kassir'] } });
    ok('config remindRoles: kassir qo\'shilsa -> ruxsat', (await R({ jwt: 'uid_kas', studentId: 'IQ-0255', preview: true })).ok === true); }

  sec('preview — qarz SERVERDA, hech narsa yuborilmaydi/yozilmaydi');
  { const { R, sent, state } = setup();
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0255', preview: true });
    ok('ok + preview', p.ok && p.preview, p);
    ok('qarz = 2 610 000 + 1 900 000 (to\'langan/bekor/qaytarilgan/kelgusi oy hisobga olinmaydi)', p.due === 4510000, p.due);
    ok('oylar: 2026-09, 2026-10', JSON.stringify(p.months) === JSON.stringify(['2026-09', '2026-10']), p.months);
    ok('telefon chiroyli', p.phone === '+998 70 014 37 77', p.phone);
    ok('matn: ism + oylar + summa', p.message === "Eslatma: Qobiljonov Muhammadiy uchun 09.2026, 10.2026 oy to'lovi hali yopilmagan (qarz: 4 510 000 so'm). Iltimos, to'lovni amalga oshiring. IQROR Academy", p.message);
    ok('bugun hali yuborilmagan', p.today === null);
    ok('SMS ketmadi', sent.length === 0);
    ok('jurnalga yozilmadi', state.sms_log.length === 0); }

  sec('yuborish — kuniga bitta, jurnal');
  { const { R, sent, state } = setup();
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0255' });
    ok('yuborildi', r.ok && r.sent, r);
    ok('Eskiz: kanonik telefon', sent.length === 1 && sent[0].phone === '998700143777', sent);
    const row = state.sms_log.find(x => x.id === 'remind__IQ-0255__2026-10-16');
    ok('jurnal: sent, remind, sentBy, attempts=1', row && row.status === 'sent' && row.type === 'remind' && row.sentBy === 'uid_dir' && row.attempts === 1 && row.providerId === 'esk1', row);
    ok('jurnal: oxirgi qarz fakturasi + oy', row && row.invoiceId === 'IQ-0255__2026-10' && row.month === '2026-10', row);
    const r2 = await R({ jwt: 'uid_fin', studentId: 'IQ-0255' });
    ok('shu kuni 2-marta -> already=sent, SMS yo\'q', !r2.ok && r2.already === 'sent' && sent.length === 1, r2);
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0255', preview: true });
    ok('preview: bugun yuborilgan', p.today && p.today.status === 'sent', p.today); }

  sec('Toshkent sanasi (UTC 20:00 = ertasi kun)');
  { const { R, state } = setup({ now: Date.parse('2026-10-15T20:30:00Z') });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('id Toshkent sanasi bilan', !!state.sms_log.find(x => x.id === 'remind__IQ-0268__2026-10-16'), state.sms_log.map(x => x.id)); }
  { const { R } = setup({ now: Date.parse('2026-10-31T19:30:00Z') });   // Toshkent: 2026-11-01 00:30
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0255', preview: true });
    ok('oy chegarasi: Toshkentda noyabr boshlandi -> noyabr fakturasi ham qarz', p.months.includes('2026-11') && p.due === 4510000 + 2900000, p); }

  sec('Eskiz xatosi -> failed, qayta urinish, maks. urinish');
  { const { R, sent, state } = setup({ failNext: 1 });
    const r1 = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('1-urinish xato (moderatsiya — tushunarli xabar)', !r1.ok && /SHABLON/.test(r1.error || ''), r1);
    const row = () => state.sms_log.find(x => x.id === 'remind__IQ-0268__2026-10-16');
    ok('jurnal: failed, attempts=1', row().status === 'failed' && row().attempts === 1, row());
    const r2 = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('2-urinish yuborildi', r2.ok && sent.length === 1, r2);
    ok('jurnal: sent, attempts=2', row().status === 'sent' && row().attempts === 2, row());
    ok('2-raqam ishlatildi (1-raqam yaroqsiz)', sent[0].phone === '998901234567', sent[0]);
    ok('ism SMS uchun tozalandi', /O'g'iloy Qobiljonova uchun 10\.2026/.test(sent[0].msg), sent[0].msg); }
  { const { R, sent, state } = setup({ failNext: 10, smsCfg: { remindMaxRetries: 2 } });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0268' }); await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    const r3 = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('maks. urinishdan keyin rad (Eskiz chaqirilmaydi)', !r3.ok && /2 marta urinildi/.test(r3.error || '') && sent.length === 0, r3);
    ok('attempts=2 da qoldi', state.sms_log[0].attempts === 2, state.sms_log[0]); }
  { const { R, sent, state } = setup();
    state.sms_log.push({ id: 'remind__IQ-0268__2026-10-16', status: 'sending', attempts: 1, createdAt: '2026-10-16T04:00:00.000Z', type: 'remind' });
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('noaniq (sending) holat -> qayta YUBORILMAYDI', !r.ok && r.already === 'sending' && sent.length === 0, r); }

  sec('parallel bosish — faqat BITTA SMS');
  { const { R, sent } = setup();
    const rs = await Promise.all([1, 2, 3].map(() => R({ jwt: 'uid_dir', studentId: 'IQ-0255' })));
    ok('3 parallel so\'rov -> 1 SMS', sent.length === 1, sent.length);
    ok('qolganlari already=sending', rs.filter(x => x.ok).length === 1 && rs.filter(x => x.already === 'sending').length === 2, rs); }

  sec('o\'quvchi/telefon aniqlash');
  { const { R, sent } = setup();
    const a = await R({ jwt: 'uid_dir', studentId: 'IQ-0300' });
    ok('studentId bo\'sh -> hujjat id kalit', a.ok && sent[0].phone === '998935554433', a);
    const c = await R({ jwt: 'uid_dir', studentId: 'IQ-0400' });
    ok('ID to\'qnashuvi -> rad (boshqa oilaga ketmasin)', !c.ok && /bir nechta/.test(c.error || '') && sent.length === 1, c);
    const t = await R({ jwt: 'uid_dir', studentId: 'IQ-0500' });
    ok('maxfiy yozuv studentId bilan (taxallus) -> topiladi', t.ok && sent[1].phone === '998977777777', t);
    const b = await R({ jwt: 'uid_dir', studentId: 'IQ-0600' });
    ok('kalit bir bolaning studentId\'si + boshqasining hujjat id\'si -> rad', !b.ok && /bir nechta/.test(b.error || '') && sent.length === 2, b);
    const b2 = await R({ jwt: 'uid_dir', studentId: 'IQ-0610' });
    ok('taxallus BOSHQA o\'quvchining hujjati -> ishlatilmaydi', !b2.ok && /telefoni/.test(b2.error || '') && sent.length === 2, b2);
    const cc = await R({ jwt: 'uid_dir', studentId: 'IQ-0800' });
    ok('hujjat id ↔ studentId to\'qnashuvi -> rad', !cc.ok && /bir nechta/.test(cc.error || '') && sent.length === 2, cc);
    const lg = await R({ jwt: 'uid_dir', studentId: 'dOld', preview: true });
    ok('eski (hujjat id kalitli) + yangi faktura -> o\'quvchining JAMI qarzi', lg.ok && lg.due === 120000 && lg.phone === '+998 93 333 33 33', lg);
    const n = await R({ jwt: 'uid_dir', studentId: 'IQ-9999' });
    ok('topilmadi', !n.ok && /topilmadi/.test(n.error || ''), n);
    const z = await R({ jwt: 'uid_dir', studentId: 'IQ-0700' });
    ok('qarz yo\'q -> SMS yo\'q', !z.ok && /qarz yo‘q/.test(z.error || '') && sent.length === 2, z);
    ok('bo\'sh ID -> rad', !(await R({ jwt: 'uid_dir', studentId: '  ' })).ok); }

  sec('limitlar, DRY, shablon, avtomatik eslatma');
  { const { R, sent } = setup({ smsCfg: { remindMaxPerHour: 1 } });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0255' });
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('soatlik limit (foydalanuvchi)', !r.ok && /Soatiga 1/.test(r.error || '') && sent.length === 1, r);
    const r2 = await R({ jwt: 'uid_fin', studentId: 'IQ-0268' });
    ok('boshqa foydalanuvchining limiti alohida', r2.ok && sent.length === 2, r2); }
  { const { R, sent } = setup({ smsCfg: { remindMaxPerDay: 1 } });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0255' });
    const r = await R({ jwt: 'uid_fin', studentId: 'IQ-0268' });
    ok('kunlik umumiy limit', !r.ok && /chegarasi/.test(r.error || '') && sent.length === 1, r); }
  { const { R, state } = setup({ dry: true });
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0255' });
    ok('DRY: ok+dry, jurnal yozilmaydi', r.ok && r.dry && state.sms_log.length === 0, r); }
  { const { R, sent } = setup({ smsCfg: { templates: { remind: 'IQROR: {name} — qarz {due} so\'m ({month}).' } } });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0255' });
    ok('templates.remind ishlatiladi', sent[0].msg === "IQROR: Qobiljonov Muhammadiy — qarz 4 510 000 so'm (09.2026, 10.2026).", sent[0].msg); }
  { const { R, sent } = setup({ smsCfg: { templates: { debt: 'D {name} {due}' } } });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0255' });
    ok('remind yo\'q -> templates.debt', sent[0].msg === 'D Qobiljonov Muhammadiy 4 510 000', sent[0].msg); }
  { const { R, state } = setup();
    state.sms_log.push({ id: 'IQ-0255__2026-10__debt__2026-10-16', studentId: 'IQ-0255', type: 'debt', status: 'sent', createdAt: '2026-10-16T04:30:00.000Z' });
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0255', preview: true });
    ok('preview: bugun avtomatik eslatma ham ketgan', p.autoToday === 1, p.autoToday); }

  sec('ko\'rik tuzatmalari: atomik limit, noaniq holat, kanonik qulf, fail-closed sozlama');
  { const { R, sent, state } = setup({ smsCfg: { remindMaxPerHour: 2 } });
    const rs = await Promise.all([1, 2, 3, 4, 5].map(k => R({ jwt: 'uid_dir', studentId: 'IQ-100' + k })));
    ok('5 parallel (turli o\'quvchi), soatiga 2 -> ko\'pi bilan 2 SMS', sent.length <= 2, { sent: sent.length, rs: rs.map(x => x.ok ? 'ok' : x.error) });
    ok('rad etilganlar claim\'i o\'chirildi (sending qolmadi)', state.sms_log.filter(x => x.status === 'sending').length === 0, state.sms_log);
    ok('jurnaldagi remind qatorlari = yuborilganlar', state.sms_log.filter(x => x.type === 'remind').length === sent.length, state.sms_log.length);
    const more = await R({ jwt: 'uid_dir', studentId: 'IQ-1005' });
    ok('ketma-ket: limitga yetgach rad', !more.ok || sent.length <= 2, more); }
  { const { R, sent, state } = setup({ throwNext: 1 });
    const a = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('Eskiz istisno (timeout) -> noaniq xabar', !a.ok && /noaniq/.test(a.error || ''), a);
    ok('jurnal: unknown', state.sms_log[0] && state.sms_log[0].status === 'unknown', state.sms_log[0]);
    const b = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('noaniq holatdan keyin bugun qayta YUBORILMAYDI', !b.ok && b.already === 'sending' && sent.length === 0, b); }
  { const { R, sent } = setup();
    const a = await R({ jwt: 'uid_dir', studentId: 'dOld' });
    ok('eski kalit bilan yuborildi (jami qarz)', a.ok && a.due === 120000, a);
    const b = await R({ jwt: 'uid_dir', studentId: 'IQ-0900' });
    ok('kanonik kalit bilan 2-marta -> already (bitta qulf)', !b.ok && b.already === 'sent' && sent.length === 1, b); }
  { const { R } = setup({ smsCfg: { remindRoles: [] } });
    ok('remindRoles: [] -> hech kim', /Ruxsat/.test((await R({ jwt: 'uid_dir', studentId: 'IQ-0255', preview: true })).error || '')); }
  { const { R, sent } = setup({ smsCfg: { remindMaxPerHour: 0 } });
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0255' });
    ok('remindMaxPerHour: 0 -> o\'chirilgan', !r.ok && /o‘chirilgan/.test(r.error || '') && sent.length === 0, r); }
  { const { R, sent } = setup({ smsCfg: { remindMaxPerHour: 'abc', remindMaxPerDay: -5, remindMaxRetries: 'x' } });
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0255' });
    ok('yaroqsiz sozlama -> standart (NaN cheksiz emas), yuboriladi', r.ok && sent.length === 1, r); }
  { const { cfgNum } = require('./sms-remind.cjs');
    ok('cfgNum', cfgNum('abc', 60) === 60 && cfgNum(-1, 5) === 5 && cfgNum(0, 5) === 0 && cfgNum('7', 5) === 7 && cfgNum(undefined, 3) === 3 && cfgNum(null, 3) === 3); }

  sec('3-ko\'rik tuzatmalari: ikkinchi kalit to\'qnashuvi, aniq/noaniq Eskiz xatosi, ASCII oylar');
  { const { R } = setup();
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0821', preview: true });
    ok('hujjat id boshqa bolaning studentId\'si -> uning fakturasi QO\'SHILMAYDI', p.ok && p.due === 100000 && JSON.stringify(p.months) === '["2026-10"]', p); }
  { const { R, sent, state } = setup({ throwNext: 1, throwErr: () => { const e = new Error('Eskiz login muvaffaqiyatsiz: 401'); e.stage = 'login'; return e; } });
    const a = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('login xatosi -> failed (aniq ketmagan)', !a.ok && state.sms_log[0].status === 'failed', state.sms_log[0]);
    const b = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('login xatosidan keyin qayta urinish yuborildi', b.ok && sent.length === 1, b); }
  { const { R, state } = setup({ throwNext: 1, throwErr: () => { const e = new Error('connect ECONNREFUSED'); e.code = 'ECONNREFUSED'; e.stage = 'send'; return e; } });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('ECONNREFUSED -> failed (ulanish bo\'lmagan)', state.sms_log[0].status === 'failed', state.sms_log[0]); }
  { const { R, state } = setup({ throwNext: 1, throwErr: () => { const e = new Error('socket hang up'); e.code = 'ECONNRESET'; e.stage = 'send'; return e; } });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('ECONNRESET yuborish paytida -> unknown', state.sms_log[0].status === 'unknown', state.sms_log[0]); }
  { const { R } = setup();
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0606', preview: true });
    ok('5 oy -> «… va yana 2 oy», faqat ASCII', /05\.2026, 06\.2026, 08\.2026 va yana 2 oy/.test(p.message) && /^[\x00-\x7F]*$/.test(p.message), p.message); }
  { const { definitelyNotSent } = require('./sms-remind.cjs');
    ok('definitelyNotSent', definitelyNotSent({ stage: 'login' }) && definitelyNotSent({ code: 'ENOTFOUND' }) && definitelyNotSent({ code: 'CERT_HAS_EXPIRED' }) && !definitelyNotSent({ code: 'ECONNRESET', stage: 'send' }) && !definitelyNotSent(new Error('eskiz_timeout')) && !definitelyNotSent(null)); }

  sec('UI ko\'rigi tuzatmalari: preview bloklash sababi, tasdiq bilan bog\'lash');
  { const { R, sent, state } = setup();
    const p0 = await R({ jwt: 'uid_dir', studentId: 'IQ-0255', preview: true });
    ok('preview: bloklanmagan', p0.blocked === null && p0.blockedMsg === '', p0);
    const bad = await R({ jwt: 'uid_dir', studentId: 'IQ-0255', expect: { message: p0.message.replace('4 510 000', '9 999 999'), phone: p0.phone } });
    ok('tasdiqlangan matn farq qiladi -> changed, SMS yo\'q', !bad.ok && bad.changed && sent.length === 0 && state.sms_log.length === 0, bad);
    const bad2 = await R({ jwt: 'uid_dir', studentId: 'IQ-0255', expect: { message: p0.message, phone: '+998 90 000 00 00' } });
    ok('tasdiqlangan telefon farq qiladi -> changed', !bad2.ok && bad2.changed && sent.length === 0, bad2);
    const good = await R({ jwt: 'uid_dir', studentId: 'IQ-0255', expect: { message: p0.message, phone: p0.phone } });
    ok('mos -> yuborildi', good.ok && sent.length === 1, good);
    const p1 = await R({ jwt: 'uid_dir', studentId: 'IQ-0255', preview: true });
    ok('preview: blocked=sent', p1.blocked === 'sent' && /allaqachon/.test(p1.blockedMsg), p1); }
  { const { R, state } = setup();
    state.sms_log.push({ id: 'remind__IQ-0268__2026-10-16', status: 'unknown', attempts: 1, createdAt: '2026-10-16T04:00:00.000Z', type: 'remind' });
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0268', preview: true });
    ok('preview: noaniq -> blocked=uncertain', p.blocked === 'uncertain', p); }
  { const { R, state } = setup({ smsCfg: { remindMaxRetries: 1 } });
    state.sms_log.push({ id: 'remind__IQ-0268__2026-10-16', status: 'failed', attempts: 1, error: 'x', createdAt: '2026-10-16T04:00:00.000Z', type: 'remind' });
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0268', preview: true });
    ok('preview: urinishlar tugagan -> blocked=retries', p.blocked === 'retries', p); }
  { const { R } = setup();
    ok('preview: qarz yo\'q -> nodebt', (await R({ jwt: 'uid_dir', studentId: 'IQ-0700', preview: true })).blocked === 'nodebt');
    ok('preview: telefon yo\'q -> nophone', (await R({ jwt: 'uid_dir', studentId: 'IQ-0610', preview: true })).blocked === 'nophone'); }

  sec('deploy ko\'rigi tuzatmalari: Eskiz 5xx/noaniq javob, qayta urinish limiti');
  { const { R, sent, state } = setup({ resultNext: [{ ok: false, error: 'http_502', httpStatus: 502, ambiguous: true }] });
    const a = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('Eskiz 502 -> unknown (noaniq)', !a.ok && /noaniq/.test(a.error || '') && state.sms_log[0].status === 'unknown', { a, row: state.sms_log[0] });
    const b = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('noaniq 502 dan keyin qayta YUBORILMAYDI', !b.ok && b.already === 'sending' && sent.length === 0, b); }
  { const { R, state } = setup({ resultNext: [{ ok: false, error: 'Этот смс текст еще не прошел модерацию', httpStatus: 400, ambiguous: false }] });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('Eskiz 400 JSON rad -> failed (aniq)', state.sms_log[0].status === 'failed', state.sms_log[0]); }
  { const { R, sent, state } = setup({ smsCfg: { remindMaxPerHour: 1 }, failNext: 1 });
    await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });                                   // failed (1 qator)
    state.sms_log.push({ id: 'remind__X__2026-10-16', type: 'remind', sentBy: 'uid_dir', status: 'sent', createdAt: new Date(T0 - 60e3).toISOString() });
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0268' });
    ok('qayta urinish ham soatlik limitga bo\'ysunadi', !r.ok && /Soatiga 1/.test(r.error || '') && sent.length === 0, r); }


  sec('chet el raqami (+ bilan) — xalqaro SMS');
  { const { R, sent, state } = setup();
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0380', preview: true });
    ok('preview: chet el raqami chiroyli + intl', p.ok && p.phone === '+48 789 706 619' && p.intl === true && !p.blocked, p);
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0380', expect: { message: p.message, phone: p.phone } });
    ok('yuborildi (Eskiz: kanonik 48789706619)', r.ok && sent.length === 1 && sent[0].phone === '48789706619', { r, sent });
    const row = state.sms_log.find(x => x.id === 'remind__IQ-0380__2026-10-16');
    ok('jurnal: kanonik telefon', row && row.phone === '48789706619' && row.status === 'sent', row);
    const u = await R({ jwt: 'uid_dir', studentId: 'IQ-0226', preview: true });
    ok("'+'siz chet el raqami -> telefon yo'q (+ bilan yozish maslahati)", u.ok && u.blocked === 'nophone' && /\+ bilan/.test(u.blockedMsg || ''), u);
    const k = await R({ jwt: 'uid_dir', studentId: 'IQ-0466', preview: true });
    ok('ota (chet el) birinchi tanlanadi', k.ok && k.phone === '+7 963 768 23 01' && k.intl === true, k); }
  { const { R, sent } = setup({ smsCfg: { international: false } });
    const k = await R({ jwt: 'uid_dir', studentId: 'IQ-0466', preview: true });
    ok('international=false: ona (O\'zbekiston) raqami tanlanadi', k.ok && k.phone === '+998 90 123 45 67' && k.intl === false, k);
    const p = await R({ jwt: 'uid_dir', studentId: 'IQ-0380', preview: true });
    ok('international=false: faqat chet el raqami -> aniq sabab', p.ok && p.blocked === 'nophone' && /xalqaro SMS/.test(p.blockedMsg || ''), p);
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0380' });
    ok('international=false: yuborilmaydi', !r.ok && sent.length === 0, r); }
  { const { R } = setup({ resultNext: [{ ok: false, error: 'International SMS not enabled', httpStatus: 400, ambiguous: false }] });
    const r = await R({ jwt: 'uid_dir', studentId: 'IQ-0380' });
    ok('Eskiz xalqaro SMS rad -> tushunarli xabar', !r.ok && /Chet el raqamiga SMS yuborilmadi/.test(r.error || '') && /xalqaro SMS/.test(r.error || ''), r); }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
