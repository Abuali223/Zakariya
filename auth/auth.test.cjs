// =====================================================================
// auth.test.cjs — auth lib + server handlerlari birlik testlari (tashqi paketsiz).
//   node auth.test.cjs
// =====================================================================
const assert = require('assert');
const L = require('./lib.cjs');
const { makeFake } = require('./_fake.cjs');
const { makeHandlers } = require('./index.cjs');

let pass = 0, fail = 0;
const ok = (name, cond, extra) => { if (cond) { pass++; } else { fail++; console.log('  ✗ FAIL:', name, extra != null ? '→ ' + extra : ''); } };
const sec = s => console.log('\n— ' + s);

// Handlerlarni toza state + kod-ushlovchi (soxta eskiz) bilan quramiz.
function setup(cfgOverride, opt) {
  opt = opt || {};
  const state = Object.assign({}, opt.state || {});
  const sb = makeFake(state);
  const captured = [];
  const eskiz = { send: async (phone, msg, sopts) => { captured.push({ phone, msg, opts: sopts }); if (opt.sendImpl) return opt.sendImpl(phone, msg, sopts); return { ok: true, id: 'x' }; } };
  const cfg = Object.assign({
    hmacSecret: 'testsecret', phoneEmailDomain: 'phone.test', otpTtlSec: 180, otpMaxAttempts: 5,
    otpResendSec: 60, otpMaxPerHour: 5, ticketTtlSec: 600, loginMaxFails: 10, loginLockMin: 15,
    otpTemplate: 'Iqror kod: {code}',
  }, cfgOverride || {});
  const H = makeHandlers({
    sb, admin: sb, eskiz, cfg, anon: () => sb, smsCfg: opt.smsCfg,
    verifyJwt: async jwt => (jwt && String(jwt).startsWith('uid_')) ? jwt : null,
  });
  const lastCode = () => { const m = captured[captured.length - 1]; const mm = m && m.msg.match(/(\d{6})/); return mm ? mm[1] : null; };
  return { state, sb, H, captured, lastCode, cfg };
}
const otpOf = (state, phone, purpose) => state.otp_codes.filter(o => o.phone === phone && o.purpose === purpose).slice(-1)[0];

(async () => {
  // ---------------- lib ----------------
  sec('lib: normPhone');
  ok('local 9-digit -> 998', L.normPhone('901234567') === '998901234567');
  ok('+998 formatted', L.normPhone('+998 90 123 45 67') === '998901234567');
  ok('already canonical', L.normPhone('998901234567') === '998901234567');
  ok('reject non-UZ country', L.normPhone('79161234567') === null, L.normPhone('79161234567'));
  ok('reject too short', L.normPhone('12345') === null);
  ok('reject landline-ish op 1', L.normPhone('998101234567') === null, L.normPhone('998101234567'));
  // Chet el raqami — FAQAT '+' bilan (server/phone.cjs; batafsil: phone.test.cjs).
  ok('intl +7 accepted', L.normPhone('+7 903 157 11 24') === '79031571124');
  ok('intl +48 accepted', L.normPhone('+48 789 706 619') === '48789706619');
  ok('intl without + rejected (ambiguous)', L.normPhone('48789706619') === null);
  ok('partial intl not turned into UZ', L.normPhone('+7 903 157 11') === null);

  sec('lib: validatePassword');
  ok('ok strong', L.validatePassword('Passw0rd').ok === true);
  ok('reject short', L.validatePassword('Pa0').ok === false);
  ok('reject no-upper', L.validatePassword('passw0rd').ok === false);
  ok('reject no-digit', L.validatePassword('Password').ok === false);
  ok('reject no-lower', L.validatePassword('PASSW0RD').ok === false);

  sec('lib: phoneToEmail + ticket');
  ok('synthetic email', L.phoneToEmail('998901234567', 'phone.test') === '998901234567@phone.test');
  const tk = L.signTicket('s', { phone: '998901112233', purpose: 'register' }, 600);
  ok('ticket verifies', (L.verifyTicket('s', tk) || {}).phone === '998901112233');
  ok('ticket wrong secret', L.verifyTicket('other', tk) === null);
  ok('ticket tampered', L.verifyTicket('s', tk.slice(0, -2) + 'xy') === null);
  ok('ticket expired', L.verifyTicket('s', L.signTicket('s', { purpose: 'register' }, -1)) === null);
  ok('genCode 6 digits', /^\d{6}$/.test(L.genCode()));

  // ---------------- teacher registration (admin approval) ----------------
  sec('flow: teacher registration -> verified=false, pending');
  {
    const { H, state, lastCode } = setup();
    const ph = '+998901112233';
    let r = await H.requestOtp({ phone: ph, purpose: 'register' }); ok('request ok', r.ok === true, JSON.stringify(r));
    const code = lastCode(); ok('sms had 6-digit code', /^\d{6}$/.test(code || ''));
    // wrong code first
    let bad = '000000'; if (bad === code) bad = '111111';
    r = await H.verifyOtp({ phone: ph, purpose: 'register', code: bad }); ok('wrong code rejected', r.ok === false && r.remaining === 4, JSON.stringify(r));
    r = await H.verifyOtp({ phone: ph, purpose: 'register', code }); ok('correct code -> ticket', r.ok === true && !!r.ticket, JSON.stringify(r));
    const ticket = r.ticket;
    r = await H.register({ ticket, password: 'Passw0rd', firstName: 'Ali', lastName: 'Valiyev', role: 'staff' });
    ok('register ok', r.ok === true, JSON.stringify(r));
    ok('staff (xodim) verified=false', r.verified === false && r.pending === true);
    const u = state.users.find(x => x.phone === '998901112233');
    // c29e5b5: ro'yxatdan o'tishda rol — umumiy «staff» (Xodim); aniq rolni (teacher/kassir…) admin tasdiqlashda beradi.
    ok('users row: role=staff, status=pending', u && u.role === 'staff' && u.verified === false && u.status === 'pending', JSON.stringify(u));
    ok('auth user created (synthetic email)', state.authUsers.some(a => a.email === '998901112233@phone.test'));
    ok('name composed', u && u.name === 'Ali Valiyev' && u.firstName === 'Ali' && u.lastName === 'Valiyev');
  }

  // ---------------- parent registration (instant active) ----------------
  sec('flow: parent registration -> verified=true, active');
  {
    const { H, state, lastCode } = setup();
    const ph = '998907776655';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    const r = await H.register({ ticket: r1.ticket, password: 'Parol123', firstName: 'Ona', lastName: 'Xonim', role: 'parent' });
    ok('parent register ok', r.ok === true && r.verified === true && r.pending === false, JSON.stringify(r));
    const u = state.users.find(x => x.phone === ph);
    ok('parent row active', u && u.role === 'parent' && u.verified === true && u.status === 'active');
  }

  // ---------------- role is forced server-side ----------------
  sec('security: client cannot pick admin/director role');
  {
    const { H, lastCode } = setup();
    const ph = '998901234501';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    const r = await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'X', lastName: 'Y', role: 'admin' });
    ok('role=admin rejected', r.ok === false, JSON.stringify(r));
    const r2 = await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'X', lastName: 'Y', role: 'director' });
    ok('role=director rejected', r2.ok === false);
  }

  // ---------------- password rules enforced server-side ----------------
  sec('security: weak password rejected at register');
  {
    const { H, lastCode } = setup();
    const ph = '998901234502';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    const r = await H.register({ ticket: r1.ticket, password: 'weak', firstName: 'X', lastName: 'Y', role: 'staff' });
    ok('weak pw rejected', r.ok === false && /8 ta belgi|katta harf/.test(r.error || ''), JSON.stringify(r));
  }

  // ---------------- duplicate phone -> redirect login ----------------
  sec('flow: existing phone register -> redirect login');
  {
    const { H, lastCode } = setup();
    const ph = '998903334455';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'A', lastName: 'B', role: 'parent' });
    const r = await H.requestOtp({ phone: ph, purpose: 'register' });
    ok('existing -> redirect login', r.ok === false && r.redirect === 'login', JSON.stringify(r));
  }

  // ---------------- resend throttle (60s) ----------------
  sec('flow: resend within 60s blocked');
  {
    const { H } = setup();
    const ph = '998901230000';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const r = await H.requestOtp({ phone: ph, purpose: 'register' });
    ok('2nd immediate blocked', r.ok === false && r.resendAfter > 0, JSON.stringify(r));
  }

  // ---------------- hourly limit ----------------
  sec('flow: >5 codes/hour blocked');
  {
    const { H, state } = setup();
    const ph = '998901230001';
    // 5 ta yaqinda yuborilgan kodни to'g'ridan-to'g'ri qo'yamiz (resend throttle'ni chetlab)
    for (let i = 0; i < 5; i++) state.otp_codes.push({ id: ++state.__otpSeq, phone: ph, purpose: 'register', codeHash: 'x', expiresAt: new Date(Date.now() + 1e5).toISOString(), attempts: 0, consumed: true, createdAt: new Date(Date.now() - (i + 2) * 1000).toISOString() });
    const r = await H.requestOtp({ phone: ph, purpose: 'register' });
    ok('hourly limit hit', r.ok === false && /Soatiga/.test(r.error || ''), JSON.stringify(r));
  }

  // ---------------- OTP expiry ----------------
  sec('flow: OTP expired');
  {
    const { H, state, lastCode } = setup();
    const ph = '998901230002';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const code = lastCode();
    otpOf(state, ph, 'register').expiresAt = new Date(Date.now() - 1000).toISOString();   // o'tgan
    const r = await H.verifyOtp({ phone: ph, purpose: 'register', code });
    ok('expired rejected', r.ok === false && r.expired === true, JSON.stringify(r));
  }

  // ---------------- OTP attempt lockout ----------------
  sec('flow: 5 wrong codes -> locked');
  {
    const { H, lastCode } = setup();
    const ph = '998901230003';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const code = lastCode(); let bad = '000001'; if (bad === code) bad = '222222';
    let r;
    for (let i = 0; i < 5; i++) r = await H.verifyOtp({ phone: ph, purpose: 'register', code: bad });
    ok('locked after 5', r.ok === false && r.locked === true, JSON.stringify(r));
    // even correct code now rejected (attempts cap)
    r = await H.verifyOtp({ phone: ph, purpose: 'register', code });
    ok('correct after lock still blocked', r.ok === false && r.locked === true, JSON.stringify(r));
  }

  // ---------------- login success + wrong + lockout ----------------
  sec('flow: login');
  {
    const { H, state, lastCode } = setup();
    const ph = '998901239999';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'Log', lastName: 'In', role: 'parent' });
    let r = await H.login({ phone: ph, password: 'Passw0rd' });
    ok('login ok -> tokens', r.ok === true && !!r.access_token && r.role === 'parent', JSON.stringify(r));
    r = await H.login({ phone: ph, password: 'WrongPass9' });
    ok('wrong pw generic error', r.ok === false && /noto‘g‘ri/.test(r.error || ''), JSON.stringify(r));
    ok('failed attempt logged', state.auth_login_attempts.some(a => a.phone === ph && a.ok === false));
    // lockout: seed 10 recent fails
    for (let i = 0; i < 10; i++) state.auth_login_attempts.push({ id: ++state.__attSeq, phone: ph, ok: false, at: new Date().toISOString() });
    r = await H.login({ phone: ph, password: 'Passw0rd' });
    ok('locked after many fails', r.ok === false && r.locked === true, JSON.stringify(r));
  }

  // ---------------- pending teacher cannot log in (no tokens) ----------------
  sec('security: pending teacher login refused (no tokens)');
  {
    const { H, lastCode } = setup();
    const ph = '998901237777';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    await H.register({ ticket: r1.ticket, password: 'Teach0rd', firstName: 'O', lastName: 'Q', role: 'staff' });
    const r = await H.login({ phone: ph, password: 'Teach0rd' });
    ok('pending teacher refused', r.ok === false && r.status === 'pending' && !r.access_token, JSON.stringify(r));
  }

  // ---------------- password reset ----------------
  sec('flow: password reset (new must differ)');
  {
    const { H, state, lastCode } = setup();
    const ph = '998901238888';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    let r1 = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    await H.register({ ticket: r1.ticket, password: 'OldPass01', firstName: 'R', lastName: 'P', role: 'parent' });
    // reset otp
    let r = await H.requestOtp({ phone: ph, purpose: 'reset' }); ok('reset otp ok', r.ok === true);
    r1 = await H.verifyOtp({ phone: ph, purpose: 'reset', code: lastCode() }); ok('reset verify -> ticket', r1.ok === true && !!r1.ticket);
    // Xavfsizlik: «yangi≠eski» orakuli olib tashlangan — reset parol o'rnatadi (eski parolni oshkor qilmaydi).
    r = await H.resetConfirm({ ticket: r1.ticket, newPassword: 'NewPass02' });
    ok('reset ok', r.ok === true, JSON.stringify(r));
    // login old fails, new works
    ok('old pw now fails', (await H.login({ phone: ph, password: 'OldPass01' })).ok === false);
    ok('new pw works', (await H.login({ phone: ph, password: 'NewPass02' })).ok === true);
  }

  // ---------------- reset for unknown phone: no enumeration ----------------
  sec('security: reset unknown phone -> ok, no SMS, no otp row');
  {
    const { H, state, captured } = setup();
    const r = await H.requestOtp({ phone: '998909990011', purpose: 'reset' });
    ok('reset unknown returns ok', r.ok === true, JSON.stringify(r));
    ok('no SMS sent', captured.length === 0);
    ok('no otp row', !state.otp_codes.some(o => o.phone === '998909990011'));
  }

  // ---------------- bloklangan hisob (GoTrue taqig'i + users.status='blocked') ----------------
  sec('bloklangan hisob: login — «Hisobingiz bloklangan» (urinish sanalmaydi); reset — SMS yo‘q; telefon almashtirish — rad');
  {
    const BLK = 'Hisobingiz bloklangan. Administratorga murojaat qiling.';
    const { H, state, lastCode, captured } = setup();
    const ph = '998901236666';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    let t = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    await H.register({ ticket: t.ticket, password: 'Blok0123', firstName: 'B', lastName: 'L', role: 'parent' });
    const uid = state.users.find(u => u.phone === ph).id;
    // Bloklashdan OLDIN olingan reset kodi (keyin tasdiqlanadi) — parol baribir o'zgarmasligi kerak.
    state.otp_codes.forEach(o => { o.createdAt = new Date(Date.now() - 61e3).toISOString(); });
    await H.requestOtp({ phone: ph, purpose: 'reset' });
    const preTicket = (await H.verifyOtp({ phone: ph, purpose: 'reset', code: lastCode() })).ticket;
    // auth-server bloklashi (user-admin.cjs): GoTrue ban + users.status='blocked', rol olinadi
    const au = state.authUsers.find(a => a.id === uid); au.banned = true;
    Object.assign(state.users.find(u => u.id === uid), { status: 'blocked', role: null, blockedRole: 'parent' });
    const fails0 = state.auth_login_attempts.filter(a => a.phone === ph && !a.ok).length;
    let r = await H.login({ phone: ph, password: 'Blok0123' });
    ok('login (to‘g‘ri parol): status blocked + aniq matn, token yo‘q', r.ok === false && r.status === 'blocked' && r.error === BLK && !r.access_token, JSON.stringify(r));
    r = await H.login({ phone: ph, password: 'Notog1ri9' });
    ok('login (noto‘g‘ri parol): GoTrue «banned» — xuddi shu matn', r.ok === false && r.status === 'blocked' && r.error === BLK, JSON.stringify(r));
    ok('bloklangan hisob urinishlari sanalmaydi (lockout yo‘q)', state.auth_login_attempts.filter(a => a.phone === ph && !a.ok).length === fails0, JSON.stringify(state.auth_login_attempts));
    const n0 = captured.length, rows0 = state.otp_codes.length;
    state.otp_codes.forEach(o => { o.createdAt = new Date(Date.now() - 61e3).toISOString(); });
    r = await H.requestOtp({ phone: ph, purpose: 'reset' });
    ok('reset: noma’lum raqam kabi javob (ok), SMS YUBORILMAYDI, kod yozilmaydi', r.ok === true && captured.length === n0 && state.otp_codes.length === rows0, JSON.stringify(r));
    r = await H.resetConfirm({ ticket: preTicket, newPassword: 'Yangi0123' });
    ok('reset-confirm (bloklashdan oldingi ticket) — rad, parol o‘zgarmadi', r.ok === false && r.status === 'blocked' && au.password === 'Blok0123', JSON.stringify(r));
    r = await H.requestOtp({ phone: '998901236667', purpose: 'change_phone', jwt: uid });
    ok('change_phone (muddati tugamagan JWT bilan) — rad, SMS yo‘q', r.ok === false && r.status === 'blocked' && r.error === BLK && captured.length === n0, JSON.stringify(r));
    // Eski usulda bloklangan (GoTrue taqig'isiz, status='blocked') — to'g'ri parol bilan ham token berilmaydi (avvalgidek).
    au.banned = false;
    r = await H.login({ phone: ph, password: 'Blok0123' });
    ok('taqiqsiz, status blocked — token yo‘q, aniq matn', r.ok === false && r.status === 'blocked' && r.error === BLK && !r.access_token, JSON.stringify(r));
  }

  // ---------------- orphan (squat) reclaim ----------------
  sec('security: orphan auth account reclaimed on register');
  {
    const { H, state, lastCode } = setup();
    const ph = '998905556677';
    // squat: auth user bor, users qatori YO'Q
    state.authUsers.push({ id: 'orphan1', email: '998905556677@phone.test', password: 'squatter' });
    await H.requestOtp({ phone: ph, purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    const r = await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'Real', lastName: 'Owner', role: 'parent' });
    ok('register reclaims orphan', r.ok === true, JSON.stringify(r));
    ok('orphan deleted', !state.authUsers.some(a => a.id === 'orphan1'));
    ok('new auth user exists', state.authUsers.some(a => a.email === ph + '@phone.test' && a.password === 'Passw0rd'));
    ok('users row created', state.users.some(u => u.phone === ph));
  }

  // ---------------- change phone (authed) ----------------
  sec('flow: change phone (authed via OTP to new number)');
  {
    const { H, state, lastCode } = setup();
    const ph = '998901112200';
    await H.requestOtp({ phone: ph, purpose: 'register' });
    let r1 = await H.verifyOtp({ phone: ph, purpose: 'register', code: lastCode() });
    await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'C', lastName: 'P', role: 'staff' });
    const uid = state.users.find(u => u.phone === ph).id;
    const newPh = '998901112299';
    // auth majburiy: jwt'siz -> rad
    let r = await H.requestOtp({ phone: newPh, purpose: 'change_phone' });
    ok('change_phone requires auth', r.ok === false && /kiring/.test(r.error || ''), JSON.stringify(r));
    // authed -> OTP yuboriladi (lastCode captured'ning oxirgisi = shu SMS)
    r = await H.requestOtp({ phone: newPh, purpose: 'change_phone', jwt: uid });
    ok('change_phone otp ok (authed)', r.ok === true, JSON.stringify(r));
    r1 = await H.verifyOtp({ phone: newPh, purpose: 'change_phone', code: lastCode() });
    ok('change_phone verify -> ticket', r1.ok === true && !!r1.ticket, JSON.stringify(r1));
    r = await H.changePhoneConfirm({ ticket: r1.ticket });
    ok('phone updated', r.ok === true, JSON.stringify(r));
    const u = state.users.find(x => x.id === uid);
    ok('users.phone is new', u && u.phone === newPh, JSON.stringify(u));
    ok('auth email updated', state.authUsers.some(a => a.id === uid && a.email === newPh + '@phone.test'));
  }


  // ---------------- ESKI sahifa: role 'teacher' -> xodim (pending) ----------------
  sec('compat: old cached page sends role=teacher -> staff/pending (not "Noto‘g‘ri rol")');
  {
    const { H, state, lastCode } = setup();
    const ph = '998936301111';
    await H.requestOtp({ phone: '+998 93 630 11 11', purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: '+998936301111', purpose: 'register', code: lastCode() });
    const r = await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'MuhammadAmin', lastName: 'Sobirov', role: 'teacher' });
    ok('teacher -> ok', r.ok === true && r.role === 'staff' && r.pending === true, JSON.stringify(r));
    const u = state.users.find(x => x.phone === ph);
    ok('users row role=staff pending', u && u.role === 'staff' && u.status === 'pending' && u.verified === false, JSON.stringify(u));
  }
  {
    const { H, lastCode } = setup();
    await H.requestOtp({ phone: '998901230100', purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: '998901230100', purpose: 'register', code: lastCode() });
    const r = await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'A', lastName: 'B', role: ' Staff ' });
    ok('role case/space-insensitive', r.ok === true && r.role === 'staff', JSON.stringify(r));
  }
  {
    const { H, lastCode } = setup();
    await H.requestOtp({ phone: '998901230101', purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: '998901230101', purpose: 'register', code: lastCode() });
    for (const bad of ['admin', 'director', 'finance_mgr', 'constructor', '__proto__', 'toString', '', undefined, null, 'student']) {
      const r = await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'X', lastName: 'Y', role: bad });
      ok(`role=${JSON.stringify(bad)} rejected with refresh hint`, r.ok === false && /Sahifani yangilang/.test(r.error || ''), JSON.stringify(r));
    }
  }

  // ---------------- xodim: HR yozuviga bog'lanish + xabarда kod/lavozim ----------------
  sec('staff registration links to HR record (message shows code + position)');
  {
    const { H, state, lastCode } = setup(null, { state: { staff: [{ id: 'st1', staffId: 'IQX-001', name: 'Sobirov MuhammadAmin', position: 'Moliya Menejeri', phone: '+998936301111', userUid: '' }], teachers: [] } });
    await H.requestOtp({ phone: '+998 93 630 11 11', purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: '+998936301111', purpose: 'register', code: lastCode() });
    const r = await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'MuhammadAmin', lastName: 'Sobirov', role: 'staff' });
    ok('linked returned', r.ok === true && r.linked && r.linked.code === 'IQX-001' && r.linked.pos === 'Moliya Menejeri', JSON.stringify(r));
    ok('message mentions code + position', /IQX-001/.test(r.message) && /Moliya Menejeri/.test(r.message), r.message);
    const u = state.users.find(x => x.phone === '998936301111');
    ok('users forward link', u && u.staffRefType === 'staff' && u.staffRefId === 'st1' && u.staffCode === 'IQX-001', JSON.stringify(u));
    ok('staff back link', state.staff[0].userUid === u.id, JSON.stringify(state.staff[0]));
  }
  {
    // HR maydonlarida HTML (admin/HR qo'lda yozadi) — xabarga faqat zararsiz matn (eski sahifalar innerHTML ishlatadi).
    const { H, lastCode } = setup(null, { state: { staff: [{ id: 'sx', staffId: 'IQX-<b>7</b>', name: 'X', position: 'Kassir<img src=x onerror=alert(1)>', phone: '+998901239000', userUid: '' }], teachers: [] } });
    await H.requestOtp({ phone: '998901239000', purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: '+998901239000', purpose: 'register', code: lastCode() });
    const r = await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'X', lastName: 'Y', role: 'staff' });
    ok('HR HTML stripped from message/linked', r.ok === true && !/[<>&]/.test(r.message) && !/[<>&]/.test(JSON.stringify(r.linked)) && /Kassir/.test(r.message), JSON.stringify(r));
  }
  sec('lib: staff match by stored canonical foreign phone (data rule)');
  ok('matchStaffByPhone canonical foreign -> linked', L.matchStaffByPhone('79031571124', [{ table: 'staff', id: 's9', code: 'IQX-009', phone: '+7 903 157 11 24', userUid: '' }]).status === 'linked');

  // ---------------- SMS faqat O'zbekiston raqamlariga ----------------
  sec('UZ-only SMS: foreign number -> OTP refused for every purpose (no SMS, no otp row, no enumeration)');
  {
    const SP = { student_private: [{ id: 'S380', parentPhone: '+48789706619' }], staff: [{ id: 's9', staffId: 'IQX-009', phone: '+7 903 157 11 24', userUid: '' }], teachers: [] };
    const { H, state, captured, lastCode } = setup(null, { state: SP });
    let r = await H.requestOtp({ phone: '+48 789 706 619', purpose: 'register', _ip: '1.2.3.4' });
    ok('register foreign (even in school records) -> UZ-only message', r.ok === false && /faqat O‘zbekiston/.test(r.error || '') && /Email yoki Google/.test(r.error || ''), JSON.stringify(r));
    r = await H.requestOtp({ phone: '+7 903 157 11 24', purpose: 'register' });
    ok('register foreign staff phone -> refused', r.ok === false && /faqat O‘zbekiston/.test(r.error || ''), JSON.stringify(r));
    r = await H.requestOtp({ phone: '+7 916 123 45 67', purpose: 'reset' });
    ok('reset foreign (unknown) -> same UZ-only message (no enumeration)', r.ok === false && /faqat O‘zbekiston/.test(r.error || ''), JSON.stringify(r));
    ok('no SMS, no otp rows for foreign', captured.length === 0 && state.otp_codes.length === 0, JSON.stringify({ captured, otp: state.otp_codes }));
    // change_phone (authed) — ham rad
    await H.requestOtp({ phone: '998901112201', purpose: 'register' });
    const r1 = await H.verifyOtp({ phone: '998901112201', purpose: 'register', code: lastCode() });
    await H.register({ ticket: r1.ticket, password: 'Passw0rd', firstName: 'C', lastName: 'P', role: 'parent' });
    const uid = state.users.find(u => u.phone === '998901112201').id;
    const n0 = captured.length;
    r = await H.requestOtp({ phone: '+7 903 157 11 24', purpose: 'change_phone', jwt: uid });
    ok('change_phone to foreign -> refused, no SMS', r.ok === false && /faqat O‘zbekiston/.test(r.error || '') && captured.length === n0, JSON.stringify(r));
    // verify for foreign (no code ever issued) -> no ticket
    r = await H.verifyOtp({ phone: '+48789706619', purpose: 'register', code: '123456' });
    ok('verify foreign -> no ticket', r.ok === false && !r.ticket, JSON.stringify(r));
    // login with foreign number (no such account) -> generic error
    r = await H.login({ phone: '+48 789 706 619', password: 'Parol123' });
    ok('login foreign (no account) -> generic error', r.ok === false && /noto‘g‘ri/.test(r.error || ''), JSON.stringify(r));
  }
  sec('UZ-only SMS: malformed inputs');
  {
    const { H, captured } = setup();
    let r = await H.requestOtp({ phone: '+90 123 45 67', purpose: 'register' });
    ok('+ with 9 digits (partial foreign) -> bad phone, no SMS', r.ok === false && /noto‘g‘ri/.test(r.error || '') && captured.length === 0, JSON.stringify(r));
    r = await H.requestOtp({ phone: '79161234567', purpose: 'register' });
    ok('foreign without + -> bad phone (UZ hint)', r.ok === false && /\+998/.test(r.error || ''), JSON.stringify(r));
    r = await H.requestOtp({ phone: '+998 90 123 45 67 8', purpose: 'register' });
    ok('UZ with extra digit (mask shows it) -> bad phone', r.ok === false && /noto‘g‘ri/.test(r.error || ''), JSON.stringify(r));
  }
  {
    // Avval Eskiz rad etsa ham {ok:true} qaytardi (kelmaydigan kodni kutish). Endi — aniq xato (pastda batafsil).
    const s4 = setup(null, { sendImpl: async () => ({ ok: false, error: 'x', httpStatus: 400, ambiguous: false }) });
    const r = await s4.H.requestOtp({ phone: '998901230555', purpose: 'register' });
    ok('UZ: Eskiz rad etdi -> ok:false, smsFailed (endi «ok» emas)', r.ok === false && r.smsFailed === true, JSON.stringify(r));
  }

  // ---------------- OTP yetib bormasa — aniq xato, limitga sanalmaydi ----------------
  const SMS_FAILED = 'SMS yuborilmadi. Birozdan so‘ng qayta urinib ko‘ring yoki maktabga murojaat qiling.';
  sec('OTP: Eskiz xatosi -> {ok:false, smsFailed, aniq matn}; qator o‘chadi; qayta yuborish DARHOL');
  {
    let failNow = true;
    const s = setup(null, { sendImpl: async () => failNow ? { ok: false, error: 'Этот смс текст еще не прошел модерацию', httpStatus: 400, ambiguous: false } : { ok: true, id: 'y' } });
    const ph = '998901230777';
    let r = await s.H.requestOtp({ phone: ph, purpose: 'register', _ip: '5.5.5.5' });
    ok('ok:false + smsFailed + spec matni', r.ok === false && r.smsFailed === true && r.error === SMS_FAILED && r.resendAfter === undefined, JSON.stringify(r));
    ok('yaratilgan otp_codes qatori o‘chirildi', !s.state.otp_codes.some(o => o.phone === ph), JSON.stringify(s.state.otp_codes));
    failNow = false;
    r = await s.H.requestOtp({ phone: ph, purpose: 'register', _ip: '5.5.5.5' });
    ok('darhol qayta urinish — 60 s kutish YO‘Q, SMS ketdi', r.ok === true && s.captured.length === 2, JSON.stringify(r));
    const v = await s.H.verifyOtp({ phone: ph, purpose: 'register', code: s.lastCode() });
    ok('ikkinchi (yetib borgan) kod ishlaydi', v.ok === true && !!v.ticket, JSON.stringify(v));
  }
  {
    // ANIQ yuborilmagan istisnolar (payments/sms.cjs definitelyNotSent): kirish (login) bosqichi, ulanish o'rnatilmagan.
    const sL = setup(null, { sendImpl: async () => { const e = new Error('Eskiz login muvaffaqiyatsiz'); e.stage = 'login'; throw e; } });
    let r = await sL.H.requestOtp({ phone: '998901230776', purpose: 'register' });
    ok('istisno: Eskiz login xato -> smsFailed, qator yo‘q', r.ok === false && r.smsFailed === true && r.error === SMS_FAILED && sL.state.otp_codes.length === 0, JSON.stringify(r));
    ok('Eskiz so‘roviga ~8 s muddat uzatiladi (timeoutMs=8000)', sL.captured[0] && sL.captured[0].opts && sL.captured[0].opts.timeoutMs === 8000, JSON.stringify(sL.captured[0]));
    const sC = setup(null, { sendImpl: async () => { const e = new Error('connect ECONNREFUSED'); e.code = 'ECONNREFUSED'; e.preconnect = true; e.stage = 'send'; throw e; } });
    r = await sC.H.requestOtp({ phone: '998901230777', purpose: 'register' });
    ok('istisno: ulanib bo‘lmadi (preconnect) -> smsFailed, qator yo‘q', r.ok === false && r.smsFailed === true && sC.state.otp_codes.length === 0, JSON.stringify(r));
    const s2 = setup({ otpSmsTimeoutMs: 5000 });
    await s2.H.requestOtp({ phone: '998901230779', purpose: 'register' });
    ok('otpSmsTimeoutMs sozlamasi ishlaydi', s2.captured[0].opts.timeoutMs === 5000, JSON.stringify(s2.captured[0]));
  }
  sec('OTP: NOANIQ natija (SMS ketgan bo‘lishi mumkin) -> kod faol, kodni kiritish bosqichi, urinish SANALADI');
  const SMS_UNCERTAIN = 'SMS kechikishi mumkin: kod bir necha daqiqada kelmasa, 60 soniyadan so‘ng «Qayta yuborish»ni bosing yoki maktabga murojaat qiling.';
  {
    // So'rov Eskiz'ga yetgandan keyin uzilish/muddat (stage 'send', preconnect yo'q) — SMS ketgan bo'lishi mumkin.
    const s = setup(null, { sendImpl: async () => { const e = new Error('eskiz_timeout'); e.stage = 'send'; throw e; } });
    const ph = '998901230778';
    const r = await s.H.requestOtp({ phone: ph, purpose: 'register', _ip: '7.7.7.1' });
    ok('istisno (yuborilgandan keyingi timeout) -> ok:true, smsUncertain, ogohlantirish, resendAfter 60', r.ok === true && r.smsUncertain === true && r.warning === SMS_UNCERTAIN && r.resendAfter === 60 && !r.smsFailed, JSON.stringify(r));
    const row = otpOf(s.state, ph, 'register');
    ok('qator faol (consumed=false) — kech kelgan SMS kodi ishlaydi', row && row.consumed === false, JSON.stringify(row));
    const r2 = await s.H.requestOtp({ phone: ph, purpose: 'register', _ip: '7.7.7.1' });
    ok('darhol qayta so‘rov — 60 s kutish (sanaladi)', r2.ok === false && r2.resendAfter > 0 && !r2.smsFailed && s.captured.length === 1, JSON.stringify(r2));
    const v = await s.H.verifyOtp({ phone: ph, purpose: 'register', code: s.lastCode() });
    ok('kech kelgan kod tasdiqlanadi', v.ok === true && !!v.ticket, JSON.stringify(v));
  }
  {
    // Eskiz umuman javob bermaydi (sms.cjs muddati ishlamagan holat) — qat'iy chegara: muddat + ≤2 s ichida javob (noaniq).
    const s3 = setup({ otpSmsTimeoutMs: 200 }, { sendImpl: () => new Promise(() => {}) });
    const t0 = Date.now();
    const r3 = await s3.H.requestOtp({ phone: '998901230780', purpose: 'register' });
    const ms = Date.now() - t0;
    const row = otpOf(s3.state, '998901230780', 'register');
    ok('osilib qolgan Eskiz -> ~200+50 ms da noaniq javob, kod faol', r3.ok === true && r3.smsUncertain === true && ms >= 200 && ms < 1500 && row && row.consumed === false, JSON.stringify({ r3, ms, row }));
  }
  {
    // Eskiz SMS'ni yuboradi, lekin javob muddatdan KEYIN keladi — foydalanuvchiga kelgan kod ishlashi shart (avval o'chirilardi).
    const s2 = setup({ otpSmsTimeoutMs: 40 }, { sendImpl: () => new Promise(res => setTimeout(() => res({ ok: true, id: 'late' }), 150)) });
    const ph = '998901230784';
    const r2 = await s2.H.requestOtp({ phone: ph, purpose: 'register', _ip: '7.7.7.2' });
    await new Promise(res => setTimeout(res, 200));
    const v = await s2.H.verifyOtp({ phone: ph, purpose: 'register', code: s2.lastCode() });
    ok('javob muddatdan keyin: noaniq, kech yetib borgan SMS kodi tasdiqlanadi', r2.ok === true && r2.smsUncertain === true && v.ok === true, JSON.stringify({ r2, v }));
  }
  sec('OTP: ANIQ xato limitga SANALMAYDI; NOANIQ xato (5xx) — SANALADI (SMS-bombing / ortiqcha xarajat yo‘q)');
  {
    // Aniq rad (4xx): 8 marta ketma-ket — hech biri limitga sanalmaydi; Eskiz tiklangach darhol yuboriladi.
    let failNow = true;
    const s = setup({ otpMaxPerIpHour: 3 }, { sendImpl: async () => failNow ? { ok: false, error: 'x', httpStatus: 400, ambiguous: false } : { ok: true } });
    const ph = '998901230785';
    let all = true;
    for (let i = 0; i < 8; i++) { const r = await s.H.requestOtp({ phone: ph, purpose: 'register', _ip: '6.6.6.6' }); if (!(r.ok === false && r.smsFailed === true)) all = false; }
    ok('4xx: 8 marta ketma-ket — hech biri «Soatiga…» / «…soniyadan so‘ng» / «Juda ko‘p so‘rov» emas', all);
    for (let i = 0; i < 5; i++) await s.H.requestOtp({ phone: '99890123079' + i, purpose: 'register', _ip: '6.6.6.6' });
    ok('4xx: IP bo‘yicha ham sanalmadi (5 boshqa raqam, limit 3)', s.state.otp_codes.length === 0, s.state.otp_codes.length);
    failNow = false;
    const r = await s.H.requestOtp({ phone: ph, purpose: 'register', _ip: '6.6.6.6' });
    ok('Eskiz tiklangach — darhol yuboriladi', r.ok === true && !r.smsUncertain, JSON.stringify(r));
  }
  {
    // Noaniq (5xx — Eskiz SMS'ni navbatga qo'ygan bo'lishi mumkin): har urinish sanaladi — telefon, IP va 60 s kutish ishlaydi.
    const s = setup({ otpMaxPerIpHour: 3 }, { sendImpl: async () => ({ ok: false, error: 'http_500', httpStatus: 500, ambiguous: true }) });
    const res = [];
    for (let i = 0; i < 10; i++) { const r = await s.H.requestOtp({ phone: '9989012308' + String(10 + i), purpose: 'register', _ip: '6.6.6.7' }); res.push(r.ok ? (r.smsUncertain ? 'uncertain' : 'ok') : (r.smsFailed ? 'smsFailed' : 'refused')); }
    ok('5xx: bitta IP — 3 tasi noaniq, qolgan 7 tasi IP limiti bilan rad', JSON.stringify(res) === JSON.stringify(['uncertain', 'uncertain', 'uncertain'].concat(Array(7).fill('refused'))), JSON.stringify(res));
    ok('5xx: Eskiz’ga faqat 3 marta murojaat (limitsiz SMS yo‘q)', s.captured.length === 3, s.captured.length);
    const same = [];
    for (let i = 0; i < 8; i++) { const r = await s.H.requestOtp({ phone: '998901230830', purpose: 'register', _ip: '198.51.100.' + i }); same.push(r.ok ? 'uncertain' : 'refused'); }
    ok('5xx: bitta telefon x8 (har xil IP) — 1 noaniq, 7 tasi 60 s kutish bilan rad', JSON.stringify(same) === JSON.stringify(['uncertain'].concat(Array(7).fill('refused'))) && s.captured.length === 4, JSON.stringify({ same, calls: s.captured.length }));
  }
  sec('OTP: aniq xatoda avvalgi (yetib borgan) kod amal qilaveradi');
  {
    // Muvaffaqiyatli kod (1) -> 60 s o'tdi -> qayta yuborish xato -> (1)-kod hali amal qiladi (bekor qilinmadi).
    let failNow = false;
    const s = setup(null, { sendImpl: async () => failNow ? { ok: false, error: 'x', httpStatus: 400 } : { ok: true } });
    const ph = '998901230781';
    await s.H.requestOtp({ phone: ph, purpose: 'register' });
    const code1 = s.lastCode();
    s.state.otp_codes.forEach(o => { o.createdAt = new Date(Date.now() - 61e3).toISOString(); });
    failNow = true;
    const r = await s.H.requestOtp({ phone: ph, purpose: 'register' });
    ok('qayta yuborish xato -> smsFailed', r.ok === false && r.smsFailed === true, JSON.stringify(r));
    const v = await s.H.verifyOtp({ phone: ph, purpose: 'register', code: code1 });
    ok('avvalgi (yetib borgan) kod amal qilaveradi', v.ok === true, JSON.stringify(v));
  }
  {
    // Kamyob holat: yangi kod tasodifan oldingisi bilan BIR XIL (xesh bir xil). SMS yuborilmasa — faqat yangi qator
    //   (id bo'yicha) o'chadi, oldingi faol kod qoladi; yuborilsa — eski qator bekor, yangisi faol.
    const realGen = L.genCode;
    let failNow = false;
    const s = setup(null, { sendImpl: async () => failNow ? { ok: false, error: 'x' } : { ok: true } });
    const ph = '998901230783';
    try {
      L.genCode = () => '424242';
      await s.H.requestOtp({ phone: ph, purpose: 'register' });
      s.state.otp_codes.forEach(o => { o.createdAt = new Date(Date.now() - 61e3).toISOString(); });
      failNow = true;
      const r = await s.H.requestOtp({ phone: ph, purpose: 'register' });
      const rows = s.state.otp_codes.filter(o => o.phone === ph);
      ok('bir xil kod + SMS xato: faqat yangi qator o‘chdi, oldingisi faol', r.smsFailed === true && rows.length === 1 && rows[0].consumed === false, JSON.stringify(rows));
      s.state.otp_codes.forEach(o => { o.createdAt = new Date(Date.now() - 61e3).toISOString(); });
      failNow = false;
      const r2 = await s.H.requestOtp({ phone: ph, purpose: 'register' });
      const rows2 = s.state.otp_codes.filter(o => o.phone === ph).sort((a, b) => a.id - b.id);
      ok('bir xil kod + SMS yuborildi: eski bekor, yangisi faol (bitta faol qator)', r2.ok === true && rows2.length === 2 && rows2[0].consumed === true && rows2[1].consumed === false, JSON.stringify(rows2));
      const v = await s.H.verifyOtp({ phone: ph, purpose: 'register', code: '424242' });
      ok('kod tasdiqlanadi', v.ok === true, JSON.stringify(v));
    } finally { L.genCode = realGen; }
  }
  {
    // SMS yuborilayotganda: yangi kod hali tekshirilmaydi; parallel ikkinchi so'rov ikkinchi SMS yubormaydi.
    let release; const gate = new Promise(res => { release = res; });
    const s = setup(null, { sendImpl: async () => { await gate; return { ok: true }; } });
    const ph = '998901230782';
    const p1 = s.H.requestOtp({ phone: ph, purpose: 'register' });
    await new Promise(res => setTimeout(res, 20));
    const pending = await s.H.verifyOtp({ phone: ph, purpose: 'register', code: s.lastCode() });
    ok('yuborilayotgan kod hali tekshirilmaydi (nocode)', pending.ok === false && /topilmadi/.test(pending.error || ''), JSON.stringify(pending));
    const r2 = await s.H.requestOtp({ phone: ph, purpose: 'register' });
    ok('parallel so‘rov — 60 s kutish (ikkinchi SMS yo‘q)', r2.ok === false && r2.resendAfter > 0 && s.captured.length === 1, JSON.stringify(r2));
    release();
    const r1 = await p1;
    ok('birinchi so‘rov — ok', r1.ok === true, JSON.stringify(r1));
    const v = await s.H.verifyOtp({ phone: ph, purpose: 'register', code: s.lastCode() });
    ok('yetib borgan kod — ishlaydi', v.ok === true, JSON.stringify(v));
  }
  {
    // DRY (sinov) rejimi: o'zgarmagan — SMS yo'q, ok:true, kod tekshiriladi.
    const state = {};
    const sb = makeFake(state);
    const H = makeHandlers({ sb, admin: sb, eskiz: null, cfg: { hmacSecret: 's', otpResendSec: 60 }, anon: () => sb, verifyJwt: async () => null });
    const logs = []; const ol = console.log; console.log = (...a) => logs.push(a.join(' '));
    let r; try { r = await H.requestOtp({ phone: '998901230783', purpose: 'register' }); } finally { console.log = ol; }
    const m = (logs.find(l => l.includes('[DRY OTP]')) || '').match(/(\d{6})\s*$/);
    ok('DRY: ok:true, resendAfter=60', r.ok === true && r.resendAfter === 60, JSON.stringify(r));
    const v = await H.verifyOtp({ phone: '998901230783', purpose: 'register', code: m && m[1] });
    ok('DRY: kod faol (tekshiriladi)', v.ok === true, JSON.stringify(v));
  }
  sec('OTP: ishonchli (maktab) IP — IP limiti otpMaxPerTrustedIpHour; telefon limiti o‘zgarmaydi');
  {
    const seedIp = (state, ip, n) => { for (let i = 0; i < n; i++) state.otp_codes.push({ id: ++state.__otpSeq, phone: '9989' + String(10000000 + i), purpose: 'register', codeHash: 'h' + i, expiresAt: new Date(Date.now() + 1e5).toISOString(), attempts: 0, consumed: true, ip, createdAt: new Date(Date.now() - 5000).toISOString() }); };
    const s = setup({ otpTrustedIps: ['203.0.113.0/28', '198.51.100.7'], otpMaxPerTrustedIpHour: 30 });
    seedIp(s.state, '203.0.113.5', 25);
    let r = await s.H.requestOtp({ phone: '998901230790', purpose: 'register', _ip: '203.0.113.5' });
    ok('maktab IP (CIDR): 25 ta so‘rovdan keyin ham ok (limit 30)', r.ok === true, JSON.stringify(r));
    seedIp(s.state, '203.0.113.99', 25);
    r = await s.H.requestOtp({ phone: '998901230791', purpose: 'register', _ip: '203.0.113.99' });
    ok('CIDR tashqarisidagi IP — oddiy limit (20) -> rad', r.ok === false && /Juda ko‘p/.test(r.error || ''), JSON.stringify(r));
    seedIp(s.state, '198.51.100.7', 29);
    r = await s.H.requestOtp({ phone: '998901230792', purpose: 'register', _ip: '198.51.100.7' });
    ok('aniq IP: 29 dan keyin ok', r.ok === true, JSON.stringify(r));
    r = await s.H.requestOtp({ phone: '998901230793', purpose: 'register', _ip: '198.51.100.7' });
    ok('aniq IP: 30 ga yetganda — rad', r.ok === false && /Juda ko‘p/.test(r.error || ''), JSON.stringify(r));
    const ph = '998901230794';
    for (let i = 0; i < 5; i++) s.state.otp_codes.push({ id: ++s.state.__otpSeq, phone: ph, purpose: 'register', codeHash: 'p' + i, expiresAt: new Date(Date.now() + 1e5).toISOString(), attempts: 0, consumed: true, ip: '203.0.113.1', createdAt: new Date(Date.now() - (i + 2) * 1000).toISOString() });
    r = await s.H.requestOtp({ phone: ph, purpose: 'register', _ip: '203.0.113.1' });
    ok('maktab IP’da ham telefon limiti (5/soat) o‘zgarmaydi', r.ok === false && /Soatiga 5/.test(r.error || ''), JSON.stringify(r));
    const s2 = setup({ otpTrustedIps: '192.0.2.10' });
    seedIp(s2.state, '192.0.2.10', 299);
    r = await s2.H.requestOtp({ phone: '998901230795', purpose: 'register', _ip: '192.0.2.10' });
    ok('standart ishonchli limit — 300 (299 dan keyin ok)', r.ok === true, JSON.stringify(r));
    r = await s2.H.requestOtp({ phone: '998901230796', purpose: 'register', _ip: '192.0.2.10' });
    ok('standart ishonchli limit — 300 ga yetganda rad', r.ok === false && /Juda ko‘p/.test(r.error || ''), JSON.stringify(r));
    const s3 = setup({ otpTrustedIps: ['0.0.0.0/0'] });
    seedIp(s3.state, '7.7.7.7', 20);
    r = await s3.H.requestOtp({ phone: '998901230797', purpose: 'register', _ip: '7.7.7.7' });
    ok('juda keng tarmoq (0.0.0.0/0) qabul qilinmaydi — oddiy limit', r.ok === false && /Juda ko‘p/.test(r.error || ''), JSON.stringify(r));
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('TEST CRASH:', e); process.exit(1); });
