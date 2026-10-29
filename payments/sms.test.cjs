// =====================================================================
// sms.test.cjs — payments/sms.cjs (Eskiz) birlik testlari: tarmoqsiz, soxta `https` bilan.
//   node sms.test.cjs
//   Tekshiradi: login/send, 401 -> qayta login, xato bosqichi (e.stage: login | send), timeout (osilib qolmaydi),
//   SMS matni yordamchilari (fmtSom/fmtMonth/fillTpl, Toshkent sanasi).
// =====================================================================
const Module = require('module');
const { EventEmitter } = require('events');

let plan = [];           // har https.request uchun navbatdagi xatti-harakat
const calls = [];
const fakeHttps = {
  request(opts, onRes) {
    const step = plan.shift() || { status: 500, body: '{}' };
    const call = { path: opts.path, method: opts.method, auth: (opts.headers || {}).Authorization || '', body: '' };
    calls.push(call);
    const req = new EventEmitter();
    let timer = null, done = false;
    req.write = (b) => { call.body += String(b); };
    req.setTimeout = (ms, cb) => { if (step.hang) timer = setTimeout(cb, Math.min(ms, 50)); };
    req.destroy = (err) => { if (done) return; done = true; if (timer) clearTimeout(timer); setImmediate(() => req.emit('error', err || new Error('destroyed'))); };
    req.end = () => setImmediate(() => {
      // Haqiqiy Node kabi: avval 'socket', keyin TLS 'secureConnect' (preconn* — ulanish o'rnatilmaydi).
      const sock = new EventEmitter(); req.emit('socket', sock);
      if (step.preconnHang) return;                            // TLS hech qachon ulanmaydi -> ulanish timeout'i
      if (step.preconnErr) { done = true; const e = new Error(step.preconnErr); e.code = step.preconnErr; return req.emit('error', e); }
      sock.emit('secureConnect');
      run();
    });
    const run = () => {
      if (step.hang) return;                                   // javob kelmaydi -> setTimeout ishlaydi
      if (step.cut) {                                          // sarlavha keldi, javob yarmida uzildi
        return setImmediate(() => { const res = new EventEmitter(); res.statusCode = 200; res.complete = false; onRes(res);
          res.emit('data', '{"id":'); res.emit('aborted'); res.emit('close'); });
      }
      if (step.error) { done = true; const e = new Error(step.error); e.code = step.error; return setImmediate(() => req.emit('error', e)); }
      setImmediate(() => { done = true; const res = new EventEmitter(); res.statusCode = step.status; res.complete = true; onRes(res); res.emit('data', step.body); res.emit('end'); });
    };
    return req;
  },
};
const origLoad = Module._load;
Module._load = function (request, parent, isMain) { if (request === 'https') return fakeHttps; return origLoad.apply(this, arguments); };
process.env.ESKIZ_TIMEOUT_MS = '30';
const S = require('./sms.cjs');

let pass = 0, fail = 0;
const ok = (n, c, x) => { if (c) pass++; else { fail++; console.log('  ✗ FAIL:', n, x !== undefined ? JSON.stringify(x) : ''); } };
const LOGIN_OK = { status: 200, body: JSON.stringify({ data: { token: 'T1' } }) };
const SEND_OK = { status: 200, body: JSON.stringify({ id: 'abc', status: 'waiting' }) };

(async () => {
  // 1) oddiy: login + send
  plan = [LOGIN_OK, SEND_OK]; calls.length = 0;
  let E = S.makeEskiz({ eskizEmail: 'a@b', eskizPassword: 'p', from: '4546' });
  let r = await E.send('+998 90 123 45 67', 'Salom');
  ok('yuborildi', r.ok && r.id === 'abc', r);
  ok('kanonik raqam + Bearer token', calls[1].path === '/api/message/sms/send' && calls[1].auth === 'Bearer T1', calls);

  // 2) noto'g'ri raqam — so'rov yuborilmaydi
  plan = []; calls.length = 0;
  r = await E.send('12345', 'x');
  ok('bad_phone', !r.ok && /bad_phone/.test(r.error) && calls.length === 0, r);

  // 3) 401 -> qayta login -> yuborildi
  plan = [{ status: 401, body: '{}' }, { status: 200, body: JSON.stringify({ data: { token: 'T2' } }) }, SEND_OK]; calls.length = 0;
  r = await E.send('901234567', 'x');
  ok('401 -> qayta login -> ok', r.ok && calls.length === 3 && calls[2].auth === 'Bearer T2', calls);

  // 4) login rad etildi -> istisno, stage=login (SMS aniq ketmagan)
  plan = [{ status: 200, body: JSON.stringify({ message: 'Invalid' }) }]; calls.length = 0;
  E = S.makeEskiz({ eskizEmail: 'a@b', eskizPassword: 'bad' });
  let err = null; try { await E.send('901234567', 'x'); } catch (e) { err = e; }
  ok('login xatosi -> stage=login', err && err.stage === 'login' && /login muvaffaqiyatsiz/.test(err.message), err && { stage: err.stage, msg: err.message });

  // 5) yuborish paytida ulanish rad etildi -> stage=send, code=ECONNREFUSED
  plan = [LOGIN_OK, { error: 'ECONNREFUSED' }]; calls.length = 0;
  E = S.makeEskiz({ eskizEmail: 'a@b', eskizPassword: 'p' });
  err = null; try { await E.send('901234567', 'x'); } catch (e) { err = e; }
  ok('ECONNREFUSED -> stage=send, code', err && err.stage === 'send' && err.code === 'ECONNREFUSED', err && { stage: err.stage, code: err.code });

  // 6) javob kelmaydi -> timeout (osilib qolmaydi), stage=send
  plan = [LOGIN_OK, { hang: true }]; calls.length = 0;
  E = S.makeEskiz({ eskizEmail: 'a@b', eskizPassword: 'p' });
  err = null; const t0 = Date.now(); try { await E.send('901234567', 'x'); } catch (e) { err = e; }
  ok('timeout -> eskiz_timeout, stage=send, tez tugadi', err && /eskiz_timeout/.test(err.message) && err.stage === 'send' && Date.now() - t0 < 2000, err && { msg: err.message, stage: err.stage });

  // 7) Eskiz rad javobi (istisno emas) -> {ok:false, error}, ANIQ (ambiguous=false) -> 'failed'
  plan = [LOGIN_OK, { status: 400, body: JSON.stringify({ message: 'Этот смс текст еще не прошел модерацию' }) }];
  E = S.makeEskiz({ eskizEmail: 'a@b', eskizPassword: 'p' });
  r = await E.send('901234567', 'x');
  ok('rad javobi -> ok:false + matn, aniq', !r.ok && /модерац/.test(r.error) && r.ambiguous === false && S.sendStatus(r) === 'failed', r);
  // 7b) gateway 502 HTML -> noaniq ('unknown')
  plan = [LOGIN_OK, { status: 502, body: '<html>Bad Gateway</html>' }];
  r = await E.send('901234567', 'x');
  ok('502 HTML -> ambiguous -> unknown', !r.ok && r.ambiguous === true && S.sendStatus(r) === 'unknown', r);
  // 7c) 200, lekin id/status yo'q -> noaniq
  plan = [LOGIN_OK, { status: 200, body: JSON.stringify({ message: 'ok?' }) }];
  r = await E.send('901234567', 'x');
  ok('200 id yo\'q -> unknown', !r.ok && S.sendStatus(r) === 'unknown', r);
  // 7d) istisno tasnifi
  ok('sendStatus: login istisnosi -> failed; ECONNRESET -> unknown; ok -> sent',
    S.sendStatus(null, Object.assign(new Error('x'), { stage: 'login' })) === 'failed' &&
    S.sendStatus(null, Object.assign(new Error('x'), { code: 'ECONNRESET', stage: 'send' })) === 'unknown' &&
    S.sendStatus(null, Object.assign(new Error('x'), { code: 'ENOTFOUND', stage: 'send' })) === 'failed' &&
    S.sendStatus({ ok: true }) === 'sent');

  // 7e) 429 HTML (JSON emas) — 4xx: aniq rad -> failed
  plan = [{ status: 429, body: '<html>Too Many Requests</html>' }];   // token keshda — login so'rovi yo'q
  r = await E.send('901234567', 'x');
  ok('429 HTML -> aniq rad (failed)', !r.ok && r.ambiguous === false && S.sendStatus(r) === 'failed', r);
  // 7f) javob yarmida uzildi -> osilib qolmaydi, eskiz_aborted (stage=send -> unknown)
  plan = [{ cut: true }];
  err = null; const t1 = Date.now(); try { await E.send('901234567', 'x'); } catch (e) { err = e; }
  ok('javob uzildi -> eskiz_aborted, stage=send, unknown', err && /eskiz_aborted/.test(err.message) && err.stage === 'send' && S.sendStatus(null, err) === 'unknown' && Date.now() - t1 < 2000, err && { msg: err.message, stage: err.stage });

  // 7g) TLS ulanish o'rnatilmasdan xato (masalan ETIMEDOUT) -> preconnect -> ANIQ ketmagan (failed, qayta urinish mumkin)
  plan = [{ preconnErr: 'ETIMEDOUT' }];
  err = null; try { await E.send('901234567', 'x'); } catch (e) { err = e; }
  ok('ulanishgacha xato -> preconnect, definitelyNotSent, failed', err && err.preconnect === true && S.definitelyNotSent(err) && S.sendStatus(null, err) === 'failed', err && { code: err.code, pre: err.preconnect });
  // 7h) TLS umuman ulanmaydi -> ulanish timeout'i (osilib qolmaydi), preconnect
  plan = [{ preconnHang: true }];
  err = null; const t2 = Date.now(); try { await E.send('901234567', 'x'); } catch (e) { err = e; }
  ok('ulanish timeout -> eskiz_connect_timeout, preconnect, tez', err && /eskiz_connect_timeout/.test(err.message) && err.preconnect === true && Date.now() - t2 < 2000, err && { msg: err.message, pre: err.preconnect });
  // 7i) ulangandan keyin uzilish (ECONNRESET) -> preconnect EMAS -> unknown
  plan = [{ error: 'ECONNRESET' }];
  err = null; try { await E.send('901234567', 'x'); } catch (e) { err = e; }
  ok('ulangandan keyin ECONNRESET -> unknown', err && !err.preconnect && S.sendStatus(null, err) === 'unknown', err && { code: err.code, pre: err.preconnect });
  // canonMobile / smsName
  ok('canonMobile: UZ mobil ha, 8-xx/landline/+siz chet el yo\'q', S.canonMobile('+998 70 014 37 77') === '998700143777' && S.canonMobile('901234567') === '998901234567' && S.canonMobile('8 90 123 45 67') === '' && S.canonMobile('998611234567') === '' && S.canonMobile('79161234567') === '');
  ok('canonMobile: chet el raqami (+ bilan, ma\'lumot sifatida to\'g\'ri) — SMS uchun yo\'q', S.canonMobile('+7 916 123 45 67') === '' && S.canonMobile('+48 789 706 619') === '');

  // 7j) SMS FAQAT O'zbekiston raqamlariga: chet el raqami -> bad_phone:intl, Eskiz'ga so'rov YO'Q (kanonik yoki + bilan)
  plan = [SEND_OK]; calls.length = 0;
  r = await E.send('+7 903 157 11 24', 'Salom');
  ok('chet el (+7) -> bad_phone:intl, so\'rov yo\'q', !r.ok && r.error === 'bad_phone:intl' && r.intl === true && calls.length === 0, { r, calls });
  r = await E.send('48789706619', 'Salom');          // bazadagi kanonik (+siz) chet el raqami
  ok('kanonik chet el -> bad_phone:intl, so\'rov yo\'q', !r.ok && r.error === 'bad_phone:intl' && calls.length === 0, { r, calls });
  plan = [SEND_OK]; calls.length = 0;
  r = await E.send('+998 90 123 45 67', 'x');
  { const q = new URLSearchParams(calls[0] && calls[0].body);
    ok('O\'zbekiston: /sms/send + from', r.ok && calls[0].path === '/api/message/sms/send' && q.get('mobile_phone') === '998901234567' && q.get('from') === '4546', calls); }
  plan = []; calls.length = 0;
  r = await E.send('8 903 157 11 24', 'x');
  ok('noaniq (+siz) chet el -> bad_phone, so\'rov yo\'q', !r.ok && /^bad_phone/.test(r.error) && calls.length === 0, r);
  r = await E.send('+7 903 157 11', 'x');
  ok('chala chet el (+, 9 raqam) -> bad_phone (O\'zbekistonga aylanmaydi)', !r.ok && /^bad_phone/.test(r.error) && calls.length === 0, r);
  plan = [{ status: 400, body: JSON.stringify({ message: { mobile_phone: ['invalid'] } }) }]; calls.length = 0;
  r = await E.send('+998 90 123 45 67', 'x');
  ok('rad javobidagi obyekt xabar -> matn (aniq rad)', !r.ok && /mobile_phone/.test(r.error) && r.ambiguous === false, r);
  ok('smsName: GSM-7 apostrof', S.smsName('Oʻgʻiloy  Qobiljonova') === "O'g'iloy Qobiljonova");

  // 7k) templates(): GET /api/user/templates — Eskiz'dagi matnlar (naqsh, asl matn, holat); hech narsa yuborilmaydi
  const TPLS = { success: true, result: [{ id: 5, template: "Eslatma: %w uchun %w oy to'lovi", original_text: "Eslatma: {name} uchun {month} oy to'lovi", status: 'service' },
    { id: 6, template: '', original_text: 'Boshqa {name}', status: 'moderation' }] };
  plan = [LOGIN_OK, { status: 200, body: JSON.stringify(TPLS) }]; calls.length = 0;
  E = S.makeEskiz({ eskizEmail: 'a@b', eskizPassword: 'p' });
  r = await E.templates();
  ok('templates: ro\'yxat (id, naqsh, asl matn, holat)', r.ok && r.list.length === 2 && r.list[0].id === 5 && r.list[0].template === TPLS.result[0].template
    && r.list[0].original === TPLS.result[0].original_text && r.list[0].status === 'service' && r.list[1].template === '' && r.list[1].status === 'moderation', r);
  ok('templates: login + GET /api/user/templates (Bearer), SMS so\'rovi YO\'Q', calls.length === 2 && calls[1].path === '/api/user/templates' && calls[1].method === 'GET'
    && calls[1].auth === 'Bearer T1' && !calls.some(c => /sms\/send/.test(c.path)), calls);
  plan = [{ status: 401, body: '{}' }, { status: 200, body: JSON.stringify({ data: { token: 'T9' } }) }, { status: 200, body: JSON.stringify(TPLS) }]; calls.length = 0;
  r = await E.templates();
  ok('templates: 401 -> qayta login -> ro\'yxat', r.ok && r.list.length === 2 && calls.length === 3 && calls[2].auth === 'Bearer T9', calls);
  plan = [{ status: 500, body: '<html>err</html>' }];
  r = await E.templates();
  ok('templates: 500 -> ok:false http_500 (istisno emas)', !r.ok && r.error === 'http_500', r);
  plan = [{ status: 403, body: JSON.stringify({ message: 'Forbidden' }) }];
  r = await E.templates();
  ok('templates: rad xabari matni', !r.ok && r.error === 'Forbidden', r);
  plan = [{ status: 200, body: JSON.stringify({ data: [{ id: 1, template: 'A %w', original_text: 'A {x}', status: 'reklama' }] }) }];
  r = await E.templates();
  ok('templates: {data:[...]} shakli ham', r.ok && r.list.length === 1 && r.list[0].status === 'reklama', r);
  plan = [{ status: 200, body: JSON.stringify({ success: true, result: [null, { id: 2 }] }) }];
  r = await E.templates();
  ok('templates: chala yozuvlar xatosiz (bo\'sh satrlar)', r.ok && r.list.length === 2 && r.list[0].template === '' && r.list[1].status === '', r);
  plan = [{ error: 'ECONNREFUSED' }];
  err = null; try { await E.templates(); } catch (e) { err = e; }
  ok('templates: ulanish xatosi -> istisno (stage=send) — chaqiruvchi ushlaydi', err && err.code === 'ECONNREFUSED' && err.stage === 'send', err && { code: err.code, stage: err.stage });
  plan = [{ status: 200, body: JSON.stringify(TPLS) }]; calls.length = 0;
  r = await S.makeEskiz({ token: 'TOK' }).templates();
  ok('templates: faqat token bilan — login yo\'q', r.ok && calls.length === 1 && calls[0].auth === 'Bearer TOK', calls);
  ok('DEF_OTP ASCII (GSM-7) va {code} bor', /^[\x00-\x7F]*$/.test(S.DEF_OTP) && /\{code\}/.test(S.DEF_OTP));

  // 8) matn yordamchilari
  ok('fmtSom', S.fmtSom(4510000) === '4 510 000' && S.fmtSom(0) === '0');
  ok('fmtMonth', S.fmtMonth('2026-09') === '09.2026');
  ok('fillTpl', S.fillTpl('A {name} {due} {x}', { name: 'Ali', due: '5' }) === 'A Ali 5 ');
  ok('tashkentDay (UTC 20:30 -> ertasi)', S.tashkentDay(Date.parse('2026-10-15T20:30:00Z')) === '2026-10-16');
  ok('tashkentDayStartISO', S.tashkentDayStartISO('2026-10-16') === '2026-10-15T19:00:00.000Z');
  ok('DEF_DEBT ASCII (GSM-7)', /^[\x00-\x7F]*$/.test(S.DEF_DEBT) && /^[\x00-\x7F]*$/.test(S.DEF_NEW));

  // 9) tinch soatlar va kuniga 1 SMS navbati
  const T = iso => Date.parse(iso);
  ok('tashkentHour (UTC+5)', S.tashkentHour(T('2026-10-30T03:59:00Z')) === 8 && S.tashkentHour(T('2026-10-30T04:00:00Z')) === 9 && S.tashkentHour(T('2026-10-30T19:30:00Z')) === 0);
  ok('tashkentDow: UTC shanba kechasi = Toshkent yakshanba', S.tashkentDow(T('2026-10-31T12:00:00Z')) === 6 && S.tashkentDow(T('2026-10-31T20:00:00Z')) === 0);
  ok('sendWindow: standart [9,20]', JSON.stringify(S.sendWindow({})) === '[9,20]' && JSON.stringify(S.sendWindow(null)) === '[9,20]');
  ok('sendWindow: false -> cheklovsiz (null)', S.sendWindow({ sendHours: false }) === null);
  ok('sendWindow: to\'g\'ri oraliq (satr raqamlar ham)', JSON.stringify(S.sendWindow({ sendHours: [8, 21] })) === '[8,21]' && JSON.stringify(S.sendWindow({ sendHours: ['8', '21'] })) === '[8,21]' && JSON.stringify(S.sendWindow({ sendHours: [0, 24] })) === '[0,24]');
  ok('sendWindow: noto\'g\'ri -> standart', [[20, 9], [9, 9], [-1, 5], [8.5, 20], [9, 25], [9], 'x'].every(h => JSON.stringify(S.sendWindow({ sendHours: h })) === '[9,20]'));
  ok('inSendWindow: 09:00 ichida, 08:59 / 20:00 tashqarida', S.inSendWindow({}, T('2026-10-30T04:00:00Z')) && S.inSendWindow({}, T('2026-10-30T14:59:00Z'))
    && !S.inSendWindow({}, T('2026-10-30T03:59:00Z')) && !S.inSendWindow({}, T('2026-10-30T15:00:00Z')));
  ok('inSendWindow: sendHours=false -> doim ruxsat', S.inSendWindow({ sendHours: false }, T('2026-10-30T22:00:00Z')));
  const cands = [{ id: 'b', month: '2026-10', due: 100 }, { id: 'a', month: '2026-09', due: 50 }, { id: 'c', month: '2026-10', due: 300 }, { id: 'd', month: '2026-10', due: 300 }];
  const ord = S.orderDebtCandidates(cands).map(x => x.id).join('');
  ok('orderDebtCandidates: eng eski oy, keyin katta qarz, keyin id', ord === 'acdb', ord);
  ok('orderDebtCandidates: asl ro\'yxat o\'zgarmaydi', cands.map(x => x.id).join('') === 'bacd' && S.orderDebtCandidates(null).length === 0);
  const sib = [{ key: 'A', id: 'a', month: '2026-09', due: 900 }, { key: 'B', id: 'b', month: '2026-10', due: 100 }];
  ok('orderDebtCandidates: hech yuborilmagan bola birinchi (aka-uka navbati)', S.orderDebtCandidates(sib, { A: '2026-11-02T05:00:00Z' }).map(x => x.key).join('') === 'BA'
    && S.orderDebtCandidates(sib, { A: '2026-11-02T05:00:00Z', B: '2026-11-05T05:00:00Z' }).map(x => x.key).join('') === 'AB'
    && S.orderDebtCandidates(sib, {}).map(x => x.key).join('') === 'AB');

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
