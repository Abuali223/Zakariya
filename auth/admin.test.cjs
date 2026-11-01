// =====================================================================
// admin.test.cjs — hisobni bloklash (user-admin.cjs), «Tizim holati» (health.cjs) va HTTP marshrutlash (index.cjs makeRouter):
//   ruxsatlar (anon 401 / boshqa rol 403 / direktor), o'zini va faol direktorsiz qolishni rad etish, rol qaytishi, farzand
//   bog'lanishlari, GoTrue taqig'i va orqaga qaytarish, javobda sir yo'qligi, IP (X-Forwarded-For soxtalashtirish).
//   Tashqi paketsiz, tarmoqsiz (faqat 127.0.0.1 dagi vaqtinchalik test server).   node admin.test.cjs
// =====================================================================
const http = require('http');
const { makeFake } = require('./_fake.cjs');
const { makeUserAdmin } = require('./user-admin.cjs');
const { makeDeepHealth } = require('./health.cjs');
const { makeHandlers, makeRouter } = require('./index.cjs');

let pass = 0, fail = 0;
const ok = (name, cond, extra) => { if (cond) pass++; else { fail++; console.log('  ✗ FAIL:', name, extra != null ? '→ ' + extra : ''); } };
const sec = s => console.log('\n— ' + s);
const J = x => JSON.stringify(x);
const quiet = async fn => { const oe = console.error; console.error = () => {}; try { return await fn(); } finally { console.error = oe; } };

// jwt 'jwt_<uid>' -> uid; 'down' -> GoTrue javob bermayapti; boshqasi — yaroqsiz.
const verifyUser = async jwt => (jwt === 'down' ? { unavailable: true } : (/^jwt_/.test(jwt || '') ? { uid: jwt.slice(4) } : { invalid: true }));
function world() {
  const ago = new Date(Date.now() - 86400e3).toISOString();
  const state = {
    users: [
      { id: 'dir1', role: 'director', status: 'active', verified: true, name: 'Direktor 1' },
      { id: 'dir2', role: 'director', status: '', verified: true, name: 'Direktor 2' },
      { id: 't1', role: 'teacher', status: 'active', verified: true, assignedClasses: ['5-A'] },
      { id: 'p1', role: 'parent', status: 'active', verified: true },
      { id: 'hr1', role: 'hr', status: 'active', verified: true },
      { id: 'new1', role: 'staff', status: 'pending', verified: false },
      { id: 'noauth', role: 'kassir', status: 'active', verified: true },
    ],
    child_claims: [
      { id: 'p1__IQ-1', uid: 'p1', studentId: 'IQ-1', status: 'active' },
      { id: 'p1__IQ-2', uid: 'p1', studentId: 'IQ-2', status: 'revoked', updatedAt: ago },
      { id: 'x__IQ-3', uid: 'x', studentId: 'IQ-3', status: 'active' },
    ],
    sessions: [{ user_id: 't1' }, { user_id: 't1' }, { user_id: 'p1' }, { user_id: 'dir1' }],
    authUsers: ['dir1', 'dir2', 't1', 'p1', 'hr1', 'new1'].map(id => ({ id, email: id + '@x', password: 'p' })),
  };
  const sb = makeFake(state);
  return { state, sb, UA: makeUserAdmin({ sb, admin: sb, verifyUser }) };
}
const U = (state, id) => state.users.find(u => u.id === id);
const A = (state, id) => state.authUsers.find(u => u.id === id) || {};

(async () => {
  sec('block-user: ruxsat — anon 401, yaroqsiz JWT 401, GoTrue ishlamasa 503, boshqa rol 403');
  {
    const { state, UA } = world();
    let r = await UA.blockUser({ uid: 't1' });
    ok('JWT yo‘q -> 401', r.ok === false && r.httpStatus === 401, J(r));
    r = await UA.blockUser({ jwt: 'garbage', uid: 't1' });
    ok('yaroqsiz JWT -> 401', r.ok === false && r.httpStatus === 401, J(r));
    r = await UA.blockUser({ jwt: 'down', uid: 't1' });
    ok('GoTrue javob bermadi -> 503', r.ok === false && r.httpStatus === 503, J(r));
    for (const who of ['hr1', 't1', 'p1', 'new1']) {
      r = await UA.blockUser({ jwt: 'jwt_' + who, uid: 'dir2' });
      ok(`${who} (direktor emas) -> 403`, r.ok === false && r.httpStatus === 403, J(r));
    }
    r = await UA.unblockUser({ jwt: 'jwt_hr1', uid: 't1' });
    ok('unblock: direktor emas -> 403', r.ok === false && r.httpStatus === 403, J(r));
    ok('hech narsa o‘zgarmadi, taqiq qo‘yilmadi', U(state, 'dir2').role === 'director' && !(state.__banLog || []).length, J(state.__banLog));
  }

  sec('block-user: o‘zini / mavjud bo‘lmagan / bo‘sh uid — rad');
  {
    const { state, UA } = world();
    let r = await UA.blockUser({ jwt: 'jwt_dir1', uid: 'dir1' });
    ok('o‘zini bloklash -> 400', r.ok === false && r.httpStatus === 400 && /O‘zingizni/.test(r.error), J(r));
    r = await UA.blockUser({ jwt: 'jwt_dir1', uid: 'nobody' });
    ok('topilmadi -> 404', r.ok === false && r.httpStatus === 404, J(r));
    r = await UA.blockUser({ jwt: 'jwt_dir1', uid: '  ' });
    ok('bo‘sh uid -> 400', r.ok === false && r.httpStatus === 400, J(r));
    ok('taqiq qo‘yilmadi', !(state.__banLog || []).length);
  }

  sec('block-user: o‘qituvchi — rol olinadi, avvalgisi saqlanadi, seanslar o‘chadi, GoTrue taqig‘i');
  {
    const { state, UA } = world();
    const r = await UA.blockUser({ jwt: 'jwt_dir1', uid: 't1' });
    ok('ok', r.ok === true && r.prevRole === 'teacher' && r.sessions === 2 && r.already === false, J(r));
    const t = U(state, 't1');
    ok('users: role=null, status=blocked, blockedRole=teacher, blockedBy=dir1, blockedAt', t.role === null && t.status === 'blocked' && t.blockedRole === 'teacher' && t.blockedBy === 'dir1' && !!t.blockedAt, J(t));
    ok('biriktirishlar saqlanadi (qaytganda kerak)', J(t.assignedClasses) === '["5-A"]');
    ok('GoTrue: ban_duration 876000h', A(state, 't1').banned === true && A(state, 't1').banDuration === '876000h', J(A(state, 't1')));
    ok('faqat shu hisob seanslari o‘chdi', state.sessions.length === 2 && !state.sessions.some(s => s.user_id === 't1'), J(state.sessions));
    const r2 = await UA.blockUser({ jwt: 'jwt_dir1', uid: 't1' });
    ok('qayta bloklash — already, blockedRole yo‘qolmaydi', r2.ok === true && r2.already === true && U(state, 't1').blockedRole === 'teacher' && r2.prevRole === 'teacher', J(r2));
    const u = await UA.unblockUser({ jwt: 'jwt_dir1', uid: 't1' });
    ok('unblock -> rol qaytdi (teacher, active)', u.ok === true && u.role === 'teacher' && u.status === 'active', J(u));
    const t2 = U(state, 't1');
    ok('users tiklandi, blocked* tozalandi', t2.role === 'teacher' && t2.status === 'active' && t2.blockedRole === null && t2.blockedAt === null && t2.blockedBy === null, J(t2));
    ok('GoTrue taqig‘i olindi (none)', A(state, 't1').banned === false && A(state, 't1').banDuration === 'none', J(A(state, 't1')));
    const u2 = await UA.unblockUser({ jwt: 'jwt_dir1', uid: 't1' });
    ok('bloklanmagan hisobni unblock — already (rol o‘zgarmaydi)', u2.ok === true && u2.already === true && U(state, 't1').role === 'teacher', J(u2));
  }

  sec('block-user: ota-ona — FAOL farzand bog‘lanishlari revoked; unblock — faqat shu bloklashdagilari qaytadi');
  {
    const { state, UA } = world();
    const r = await UA.blockUser({ jwt: 'jwt_dir2', uid: 'p1' });
    ok('ok, 1 ta bog‘lanish bekor', r.ok === true && r.claims === 1, J(r));
    const c = id => state.child_claims.find(x => x.id === id);
    ok('IQ-1 revoked, IQ-2 (oldin bekor) o‘zgarmadi, begona IQ-3 — active', c('p1__IQ-1').status === 'revoked' && c('p1__IQ-2').updatedAt < U(state, 'p1').blockedAt && c('x__IQ-3').status === 'active', J(state.child_claims));
    const u = await UA.unblockUser({ jwt: 'jwt_dir2', uid: 'p1' });
    ok('unblock -> parent, 1 bog‘lanish qaytdi', u.ok === true && u.role === 'parent' && u.claims === 1, J(u));
    ok('IQ-1 active, IQ-2 revoked qoldi', c('p1__IQ-1').status === 'active' && c('p1__IQ-2').status === 'revoked', J(state.child_claims));
  }

  sec('block-user: tasdiqlanmagan yangi xodim — unblock’dan keyin yana «kutmoqda»; auth hisobi yo‘q — baza baribir bloklanadi');
  {
    const { state, UA } = world();
    let r = await UA.blockUser({ jwt: 'jwt_dir1', uid: 'new1' });
    ok('pending staff bloklandi', r.ok === true && U(state, 'new1').status === 'blocked' && U(state, 'new1').blockedRole === 'staff', J(U(state, 'new1')));
    r = await UA.unblockUser({ jwt: 'jwt_dir1', uid: 'new1' });
    ok('unblock -> staff + pending', r.ok === true && r.role === 'staff' && r.status === 'pending', J(r));
    r = await quiet(() => UA.blockUser({ jwt: 'jwt_dir1', uid: 'noauth' }));
    ok('auth.users yo‘q (GoTrue 404) — baza bloklandi, noAuth', r.ok === true && r.noAuth === true && U(state, 'noauth').status === 'blocked', J(r));
  }

  sec('block-user: direktorlar — boshqa faol direktorni bloklash mumkin; bloklangan direktor hech kimni bloklay olmaydi');
  {
    const { state, UA } = world();
    let r = await UA.blockUser({ jwt: 'jwt_dir1', uid: 'dir2' });
    ok('dir1 dir2 ni blokladi (dir1 faol qoladi)', r.ok === true && U(state, 'dir2').status === 'blocked' && U(state, 'dir1').role === 'director', J(r));
    r = await UA.blockUser({ jwt: 'jwt_dir2', uid: 'dir1' });
    ok('bloklangan dir2 oxirgi faol direktor dir1 ni bloklay olmaydi -> 403', r.ok === false && r.httpStatus === 403 && U(state, 'dir1').status === 'active', J(r));
    r = await UA.blockUser({ jwt: 'jwt_dir1', uid: 'dir1' });
    ok('oxirgi faol direktor o‘zini ham bloklay olmaydi', r.ok === false && r.httpStatus === 400, J(r));
    r = await UA.unblockUser({ jwt: 'jwt_dir1', uid: 'dir2' });
    ok('dir2 qaytdi (director)', r.ok === true && r.role === 'director' && U(state, 'dir2').status === 'active', J(r));
  }

  sec('block-user: ESKI usulda bloklangan (status blocked, rol saqlangan, taqiqsiz) — «🚫 Bloklash» to‘liq bloklaydi');
  {
    const { state, UA } = world();
    U(state, 't1').status = 'blocked';   // eski usul: rol 'teacher' qoldi, GoTrue taqig'i yo'q, seanslar tirik
    let r = await UA.blockUser({ jwt: 'jwt_dir1', uid: 't1' });
    ok('to‘liq bloklandi (already emas), prevRole teacher', r.ok === true && r.already === false && r.prevRole === 'teacher', J(r));
    const t = U(state, 't1');
    ok('rol olindi -> blockedRole, blockedAt/By', t.role === null && t.blockedRole === 'teacher' && t.blockedBy === 'dir1' && !!t.blockedAt && t.status === 'blocked', J(t));
    ok('GoTrue taqig‘i qo‘yildi, seanslar o‘chdi', A(state, 't1').banned === true && !state.sessions.some(s => s.user_id === 't1'), J(A(state, 't1')));
    r = await UA.blockUser({ jwt: 'jwt_dir1', uid: 't1' });
    ok('endi qayta bloklash — already', r.ok === true && r.already === true && U(state, 't1').blockedRole === 'teacher', J(r));
    r = await UA.unblockUser({ jwt: 'jwt_dir1', uid: 't1' });
    ok('unblock -> teacher/active', r.ok === true && r.role === 'teacher' && r.status === 'active', J(r));
    // Eski usulda bloklangan DIREKTOR faol direktorlar sanog'iga kirmaydi — uni to'liq bloklash «oxirgi direktor» emas.
    U(state, 'dir2').status = 'blocked';
    r = await UA.blockUser({ jwt: 'jwt_dir1', uid: 'dir2' });
    ok('eski usulda bloklangan direktor — to‘liq bloklanadi, dir1 faol qoladi', r.ok === true && U(state, 'dir2').role === null && U(state, 'dir2').blockedRole === 'director' && U(state, 'dir1').role === 'director', J(r));
    // RPC xatosi: eski usulda bloklangan hisobga qo'yilgan taqiq orqaga olinadi (avval taqiq yo'q edi).
    U(state, 'hr1').status = 'blocked'; state.__failRpc = { user_block: true }; state.__banLog = [];
    r = await quiet(() => UA.blockUser({ jwt: 'jwt_dir1', uid: 'hr1' }));
    ok('RPC xato -> taqiq orqaga olindi, rol joyida', r.ok === false && J(state.__banLog) === J([['hr1', '876000h'], ['hr1', 'none']]) && U(state, 'hr1').role === 'hr', J(state.__banLog));
    state.__failRpc = null;
  }

  sec('block-user: GoTrue xatosi -> 502, baza o‘zgarmaydi; baza xatosi -> taqiq orqaga qaytariladi');
  {
    const { state, UA } = world();
    state.__failBan = true;
    let r = await quiet(() => UA.blockUser({ jwt: 'jwt_dir1', uid: 't1' }));
    ok('ban xato -> 502, rol joyida', r.ok === false && r.httpStatus === 502 && U(state, 't1').role === 'teacher' && U(state, 't1').status === 'active', J(r));
    state.__failBan = false; state.__failRpc = { user_block: true };
    r = await quiet(() => UA.blockUser({ jwt: 'jwt_dir1', uid: 't1' }));
    ok('RPC xato -> 500, rol joyida', r.ok === false && r.httpStatus === 500 && U(state, 't1').role === 'teacher', J(r));
    ok('taqiq qo‘yildi va orqaga olindi', J(state.__banLog) === J([['t1', '876000h'], ['t1', 'none']]) && A(state, 't1').banned === false, J(state.__banLog));
    state.__failRpc = null;
    await UA.blockUser({ jwt: 'jwt_dir1', uid: 't1' });
    state.__failRpc = { user_unblock: true }; state.__banLog = [];
    r = await quiet(() => UA.unblockUser({ jwt: 'jwt_dir1', uid: 't1' }));
    ok('unblock RPC xato -> taqiq qayta qo‘yildi, hisob bloklangan qoldi', r.ok === false && J(state.__banLog) === J([['t1', 'none'], ['t1', '876000h']]) && A(state, 't1').banned === true && U(state, 't1').status === 'blocked', J(state.__banLog));
    state.__failRpc = null; state.__failBan = true;
    r = await quiet(() => UA.unblockUser({ jwt: 'jwt_dir1', uid: 't1' }));
    ok('unblock: taqiqni olib bo‘lmadi -> 502, hisob bloklangan qoldi', r.ok === false && r.httpStatus === 502 && U(state, 't1').status === 'blocked', J(r));
  }

  // ---------------- «Tizim holati» ----------------
  const SECRETS = { anon: 'ANON.KEY.secret-a1', eskizPw: 'EskizParol-S3cret', token: 'eyJ-eskiz-token-zz9', email: 'maktab@example.test' };
  function healthWorld(opt) {
    opt = opt || {};
    const { state, sb } = world();
    state.config = [{ id: 'security' }];
    state.payments = [
      { id: 'a', provider: 'click', status: 'applied', createdAt: '2026-10-30T10:00:00.000Z' },
      { id: 'b', provider: 'uzum', status: 'confirmed', createdAt: '2026-10-31T08:00:00.000Z' },
      { id: 'c', provider: 'cash', status: 'applied', createdAt: '2026-10-31T09:00:00.000Z' },
      { id: 'd', provider: 'click', status: 'prepared', createdAt: '2026-10-31T09:30:00.000Z' },
    ];
    const now = Date.parse('2026-10-31T12:00:00Z');
    const httpGet = opt.httpGet || (async (url, headers) => {
      if (url.endsWith('/auth/v1/health')) { if (headers.apikey !== SECRETS.anon) return { status: 401, body: '' }; return { status: 200, body: '{"name":"GoTrue"}' }; }
      if (url === 'http://127.0.0.1:8790/health') return { status: 200, body: 'ok' };
      if (url === 'http://127.0.0.1:8791/health') { const e = new Error('connect ECONNREFUSED 127.0.0.1:8791'); e.code = 'ECONNREFUSED'; throw e; }
      return { status: 404, body: '' };
    });
    const log = opt.log != null ? opt.log : '[Fri Oct 30 22:30:01 UTC 2026] backup OK -> /opt/iqror/backups/db_1.sql.gz (1M) + auth + storage\n[Sat Oct 31 08:30:01 UTC 2026] backup OK -> /opt/iqror/backups/db_2.sql.gz (1M) + auth + storage + sirlar; eski >60 kun o\'chirildi\n';
    const readTail = async file => { if (file !== '/var/log/iqror-backup.log') { const e = new Error('no'); e.code = 'ENOENT'; throw e; } return { text: log, mtimeMs: opt.mtimeMs }; };
    const tplCalls = [];
    const eskiz = { balance: opt.balance || (async o => ({ ok: true, balance: 125000, _t: o && o.timeoutMs })),
      templates: opt.templates || (async o => { tplCalls.push(o); return { ok: true, list: [] }; }) };
    const smsCfg = Object.assign({ enabled: true, dryRun: false, eskizEmail: SECRETS.email, eskizPassword: SECRETS.eskizPw }, opt.sms || {});
    const DH = makeDeepHealth({ sb, verifyUser, eskiz, smsCfg, cfg: { health: Object.assign({ eskizBalance: true }, opt.health || {}) },
      supabaseUrl: 'https://api.example.test', anonKey: SECRETS.anon, httpGet, readTail, now: () => now, timeoutMs: opt.timeoutMs || 3000 });
    return { state, DH, tplCalls };
  }
  sec('health/deep: anon 401, yaroqsiz 401, GoTrue ishlamasa 503, boshqa rol 403, bloklangan direktor 403');
  {
    const { state, DH } = healthWorld();
    let r = await DH.handle('');
    ok('anon -> 401', r.httpStatus === 401 && r.body.ok === false && !r.body.checks, J(r));
    r = await DH.handle('garbage'); ok('yaroqsiz -> 401', r.httpStatus === 401, J(r));
    r = await DH.handle('down'); ok('GoTrue javob bermaydi -> 503', r.httpStatus === 503 && !r.body.checks, J(r));
    for (const who of ['t1', 'hr1', 'p1']) { r = await DH.handle('jwt_' + who); ok(`${who} -> 403 (tekshiruvsiz)`, r.httpStatus === 403 && !r.body.checks, J(r)); }
    U(state, 'dir2').status = 'blocked';
    r = await DH.handle('jwt_dir2'); ok('bloklangan direktor -> 403', r.httpStatus === 403, J(r));
  }
  sec('health/deep: direktor -> 200, har xizmat holati, vaqt, qisqa sabab; javobda sir yo‘q');
  {
    const { DH } = healthWorld();
    const r = await DH.handle('jwt_dir1');
    const c = k => (r.body.checks || []).find(x => x.key === k) || {};
    ok('200 + 8 ta tekshiruv', r.httpStatus === 200 && (r.body.checks || []).length === 8, J(r.body));
    ok('auth/db/gotrue — yashil', c('auth').ok === true && c('db').ok === true && c('gotrue').ok === true, J(r.body.checks));
    ok('eskiz — balans (sozlamada yoqilgan, 3 s muddat)', c('eskiz').ok === true && c('eskiz').info === 'balans: 125 000', J(c('eskiz')));
    ok('to‘lov serveri — yashil; AI — qizil «ulanib bo‘lmadi»', c('pay').ok === true && c('ai').ok === false && /ulanib bo‘lmadi \(ECONNREFUSED\)/.test(c('ai').info), J([c('pay'), c('ai')]));
    ok('oxirgi onlayn to‘lov — Uzum 08:00 (naqd va «prepared» hisobga olinmaydi)', c('payments').ok === true && c('payments').info === 'Uzum' && c('payments').at === '2026-10-31T08:00:00.000Z', J(c('payments')));
    ok('oxirgi zaxira — 08:30 (3,5 soat oldin) — yashil', c('backup').ok === true && c('backup').at === '2026-10-31T08:30:01.000Z' && c('backup').info === 'muvaffaqiyatli', J(c('backup')));
    ok('umumiy ok=false (AI ishlamayapti)', r.body.ok === false);
    const txt = J(r.body);
    ok('javobda sir yo‘q (kalit/parol/token/email/manzil/JWT)', !Object.values(SECRETS).some(s => txt.includes(s)) && !/api\.example\.test|jwt_dir1|127\.0\.0\.1|\/opt\/iqror/.test(txt), txt);
    ok('har tekshiruvda ms va name bor', r.body.checks.every(x => typeof x.ms === 'number' && x.name && x.key));
  }
  sec('health/deep: osilib qolgan xizmat — muddat (3 s → testda 150 ms), qolganlari kutmaydi; xato holatlar');
  {
    const hang = () => new Promise(() => {});
    const { DH } = healthWorld({ timeoutMs: 150, httpGet: async url => (url.endsWith('/auth/v1/health') ? hang() : { status: 503, body: '' }), balance: hang });
    const t0 = Date.now();
    const r = await DH.handle('jwt_dir1');
    const c = k => r.body.checks.find(x => x.key === k) || {};
    ok('jami ~150 ms (parallel, osilib qolmaydi)', Date.now() - t0 < 1500, Date.now() - t0);
    ok('gotrue — «javob bermadi»', c('gotrue').ok === false && /javob bermadi/.test(c('gotrue').info), J(c('gotrue')));
    ok('eskiz balansi osildi — qizil', c('eskiz').ok === false && /javob bermadi/.test(c('eskiz').info), J(c('eskiz')));
    ok('pay HTTP 503 — qizil', c('pay').ok === false && c('pay').info === 'HTTP 503', J(c('pay')));
  }
  {
    let r = await healthWorld({ sms: { dryRun: true } }).DH.handle('jwt_dir1');
    ok('eskiz dryRun — kulrang (null), balans so‘ralmaydi', r.body.checks.find(x => x.key === 'eskiz').ok === null, J(r.body.checks.find(x => x.key === 'eskiz')));
    r = await healthWorld({ sms: { eskizEmail: 'ESKIZ_EMAIL (kabinet emaili)', eskizPassword: 'x' } }).DH.handle('jwt_dir1');
    ok('eskiz namunaviy (to‘ldirilmagan) kalit — qizil', r.body.checks.find(x => x.key === 'eskiz').ok === false, J(r.body.checks.find(x => x.key === 'eskiz')));
    // Balans o'chiq (standart): kalit AMAL QILISHI baribir tekshiriladi — shablonlar ro'yxati (SMS yuborilmaydi), 3 s muddat.
    let hw = healthWorld({ health: { eskizBalance: false } });
    r = await hw.DH.handle('jwt_dir1');
    let ce = r.body.checks.find(x => x.key === 'eskiz');
    ok('balans o‘chiq — kalit amal qiladi: yashil, shablonlar so‘raldi (3 s), balans so‘ralmadi', ce.ok === true && ce.info === 'kalit amal qiladi (balans tekshiruvi o‘chiq)' && hw.tplCalls.length === 1 && hw.tplCalls[0].timeoutMs === 3000, J({ ce, calls: hw.tplCalls }));
    r = await healthWorld({ health: { eskizBalance: false }, templates: async () => ({ ok: false, httpStatus: 401, error: 'Unauthorized' }) }).DH.handle('jwt_dir1');
    ce = r.body.checks.find(x => x.key === 'eskiz');
    ok('balans o‘chiq, token/parol yaroqsiz (401) — qizil «token yaroqsiz»', ce.ok === false && ce.info === 'token yaroqsiz', J(ce));
    r = await healthWorld({ health: { eskizBalance: false }, templates: async () => { const e = new Error('Eskiz login muvaffaqiyatsiz: {"message":"Неверный пароль"}'); e.stage = 'login'; throw e; } }).DH.handle('jwt_dir1');
    ce = r.body.checks.find(x => x.key === 'eskiz');
    ok('balans o‘chiq, Eskiz parol xato (login) — qizil, xabar matni chiqmaydi', ce.ok === false && ce.info === 'Eskiz login xato (parol yoki token)' && !/Неверный/.test(J(r.body)), J(ce));
    r = await healthWorld({ health: { eskizBalance: false }, templates: async () => ({ ok: false, httpStatus: 500 }) }).DH.handle('jwt_dir1');
    ok('balans o‘chiq, Eskiz 500 — qizil «Eskiz rad etdi (HTTP 500)»', r.body.checks.find(x => x.key === 'eskiz').info === 'Eskiz rad etdi (HTTP 500)', J(r.body.checks.find(x => x.key === 'eskiz')));
    hw = healthWorld({ health: { eskizBalance: false, eskizCheck: false } });
    r = await hw.DH.handle('jwt_dir1');
    ce = r.body.checks.find(x => x.key === 'eskiz');
    ok('eskizCheck: false — Eskiz’ga so‘rov yo‘q, «amal qilishi tekshirilmadi»', ce.ok === true && /tekshirilmadi/.test(ce.info) && hw.tplCalls.length === 0, J(ce));
    hw = healthWorld({ timeoutMs: 120, health: { eskizBalance: false }, templates: () => new Promise(() => {}) });
    r = await hw.DH.handle('jwt_dir1');
    ok('balans o‘chiq, Eskiz osildi — «javob bermadi»', /javob bermadi/.test(r.body.checks.find(x => x.key === 'eskiz').info), J(r.body.checks.find(x => x.key === 'eskiz')));
    r = await healthWorld({ balance: async () => ({ ok: false, httpStatus: 401 }) }).DH.handle('jwt_dir1');
    ok('Eskiz token yaroqsiz — qizil', r.body.checks.find(x => x.key === 'eskiz').info === 'token yaroqsiz');
    r = await healthWorld({ log: '[Sat Oct 31 08:30:01 UTC 2026] backup OK -> x\n❌ [Sat Oct 31 10:30:01 UTC 2026] baza zaxirasi chala chiqdi — saqlanmadi\n' }).DH.handle('jwt_dir1');
    const b1 = r.body.checks.find(x => x.key === 'backup');
    ok('zaxira: oxirgi urinish xato — qizil, oxirgi muvaffaqiyatli vaqti bilan', b1.ok === false && b1.at === '2026-10-31T08:30:01.000Z' && /xato/.test(b1.info), J(b1));
    r = await healthWorld({ log: '[Thu Oct 29 08:30:01 UTC 2026] backup OK -> x (storage YO‘Q)\n' }).DH.handle('jwt_dir1');
    const b2 = r.body.checks.find(x => x.key === 'backup');
    ok('zaxira 26 soatdan eski — qizil', b2.ok === false && /51 soatdan/.test(b2.info), J(b2));
    // Sana ajratilmaydigan vaqt zonasi («MSK»): «backup OK» oxirgi qator bo'lsa — fayl vaqti; undan keyin qator bo'lsa — qizil.
    r = await healthWorld({ log: '[Sat Oct 31 13:30:01 MSK 2026] backup OK -> x\n', mtimeMs: Date.parse('2026-10-31T10:30:01Z') }).DH.handle('jwt_dir1');
    const b3 = r.body.checks.find(x => x.key === 'backup');
    ok('zaxira: sana ajratilmadi -> fayl vaqti (oxirgi qator)', b3.ok === true && b3.at === '2026-10-31T10:30:01.000Z', J(b3));
    r = await healthWorld({ log: '[Sat Oct 31 13:30:01 MSK 2026] backup OK -> x\n⚠️ [Sat Oct 31 13:31:00 MSK 2026] boshqa yozuv\n', mtimeMs: Date.parse('2026-10-31T10:31:00Z') }).DH.handle('jwt_dir1');
    const b4 = r.body.checks.find(x => x.key === 'backup');
    ok('zaxira: sana ajratilmadi, keyin boshqa qator -> qizil «vaqtini aniqlab bo‘lmadi»', b4.ok === false && /vaqtini aniqlab/.test(b4.info), J(b4));
    r = await healthWorld({ health: { backupLog: '/nope.log' } }).DH.handle('jwt_dir1');
    ok('log fayli yo‘q — qizil «topilmadi»', r.body.checks.find(x => x.key === 'backup').info === 'log fayli topilmadi', J(r.body.checks.find(x => x.key === 'backup')));
    r = await healthWorld({ health: { payPort: 0, aiPort: 0, backupLog: false } }).DH.handle('jwt_dir1');
    ok('o‘chirilgan tekshiruvlar — kulrang', ['pay', 'ai', 'backup'].every(k => r.body.checks.find(x => x.key === k).ok === null), J(r.body.checks));
  }

  // ---------------- HTTP marshrutlash (haqiqiy server, 127.0.0.1) ----------------
  sec('HTTP: /health o‘zgarmagan; /health/deep va block-user — HTTP kodlari; XFF soxtalashtirish limitni chetlab o‘tmaydi');
  {
    const { state, sb, UA } = world();
    const H = makeHandlers({ sb, admin: sb, eskiz: { send: async () => ({ ok: true }) }, cfg: { hmacSecret: 's', otpMaxPerIpHour: 2 }, anon: () => sb, verifyJwt: async () => null });
    const { DH } = healthWorld();
    const srv = http.createServer(makeRouter({ routes: { 'request-otp': H.requestOtp, 'block-user': UA.blockUser, 'unblock-user': UA.unblockUser }, deepHealth: DH.handle }));
    await new Promise(res => srv.listen(0, '127.0.0.1', res));
    const port = srv.address().port;
    const call = (method, p, headers, body) => new Promise((res, rej) => {
      const data = body == null ? null : JSON.stringify(body);
      const rq = http.request({ host: '127.0.0.1', port, path: p, method, headers: Object.assign(data ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(data) } : {}, headers || {}) }, rs => {
        let d = ''; rs.on('data', c => d += c); rs.on('end', () => { let j = null; try { j = JSON.parse(d); } catch (_) {} res({ status: rs.statusCode, text: d, json: j, headers: rs.headers }); });
      });
      rq.on('error', rej); if (data) rq.write(data); rq.end();
    });
    try {
      let r = await call('GET', '/authapi/health');
      ok('GET /authapi/health -> 200 «ok» (o‘zgarmagan)', r.status === 200 && r.text === 'ok', J(r));
      r = await call('GET', '/authapi/health/deep');
      ok('deep: anon -> 401 JSON', r.status === 401 && r.json && r.json.ok === false && !r.json.checks, J(r));
      r = await call('GET', '/authapi/health/deep', { authorization: 'Bearer jwt_t1' });
      ok('deep: o‘qituvchi -> 403', r.status === 403, J(r));
      r = await call('GET', '/authapi/health/deep/', { authorization: 'Bearer jwt_dir1' });
      ok('deep: direktor -> 200, checks, no-store', r.status === 200 && Array.isArray(r.json.checks) && r.headers['cache-control'] === 'no-store', J(r.json));
      r = await call('POST', '/authapi/block-user', {}, { jwt: 'jwt_t1', uid: 'dir2' });
      ok('block-user: o‘qituvchi -> HTTP 403, tanada httpStatus yo‘q', r.status === 403 && r.json.ok === false && !('httpStatus' in r.json), J(r));
      r = await call('POST', '/authapi/block-user', {}, { uid: 't1' });
      ok('block-user: anon -> HTTP 401', r.status === 401, J(r));
      r = await call('POST', '/authapi/block-user', {}, { jwt: 'jwt_dir1', uid: 't1' });
      ok('block-user: direktor -> 200 ok', r.status === 200 && r.json.ok === true && U(state, 't1').status === 'blocked', J(r));
      r = await call('POST', '/authapi/unblock-user', {}, { jwt: 'jwt_dir1', uid: 't1' });
      ok('unblock-user: direktor -> 200, rol qaytdi', r.status === 200 && r.json.ok === true && U(state, 't1').role === 'teacher', J(r));
      r = await call('POST', '/authapi/constructor', {}, {});
      ok('prototip nomli yo‘l -> 404', r.status === 404, J(r));
      // XFF: nginx (loopback) har so'rovga HAQIQIY IP'ni OXIRGI qilib qo'shadi; mijoz chap qiymatlarni o'zgartirib turadi.
      for (let i = 0; i < 2; i++) {
        r = await call('POST', '/authapi/request-otp', { 'x-forwarded-for': `10.0.0.${i}, 198.51.100.9` }, { phone: '99890123080' + i, purpose: 'register' });
        ok(`XFF #${i + 1} -> ok`, r.json && r.json.ok === true, J(r.json));
      }
      ok('bazaga OXIRGI (nginx) IP yozildi', state.otp_codes.every(o => o.ip === '198.51.100.9'), J(state.otp_codes.map(o => o.ip)));
      r = await call('POST', '/authapi/request-otp', { 'x-forwarded-for': '203.0.113.77, 198.51.100.9' }, { phone: '998901230809', purpose: 'register' });
      ok('chap XFF qiymatini almashtirish limitni chetlab o‘tmaydi (3-so‘rov rad)', r.json && r.json.ok === false && /Juda ko‘p/.test(r.json.error || ''), J(r.json));
      r = await call('POST', '/authapi/request-otp', { 'x-real-ip': '203.0.113.88', 'x-forwarded-for': '198.51.100.9' }, { phone: '998901230810', purpose: 'register' });
      ok('soxta X-Real-IP (nginx XFF bilan mos emas) ham chetlab o‘tmaydi', r.json && r.json.ok === false && /Juda ko‘p/.test(r.json.error || ''), J(r.json));
      r = await call('POST', '/authapi/request-otp', { 'x-forwarded-for': '198.51.100.10' }, { phone: '998901230811', purpose: 'register', _ip: '1.1.1.1' });
      ok('boshqa haqiqiy IP — ok; tanadagi _ip e’tiborsiz', r.json && r.json.ok === true && state.otp_codes.some(o => o.phone === '998901230811' && o.ip === '198.51.100.10'), J(r.json));
    } finally { srv.close(); }
  }

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('TEST CRASH:', e); process.exit(1); });
