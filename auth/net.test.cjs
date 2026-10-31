// =====================================================================
// net.test.cjs — auth/net.cjs: mijoz IP'si (X-Forwarded-For / X-Real-IP soxtalashtirishga chidamli) va ishonchli IP ro'yxati.
//   node net.test.cjs
// =====================================================================
const N = require('./net.cjs');

let pass = 0, fail = 0;
const ok = (name, cond, extra) => { if (cond) pass++; else { fail++; console.log('  ✗ FAIL:', name, extra != null ? '→ ' + extra : ''); } };
const sec = s => console.log('\n— ' + s);
const req = (peer, headers) => ({ socket: { remoteAddress: peer }, headers: headers || {} });

sec('normIp / isLoopback');
ok('IPv4', N.normIp(' 1.2.3.4 ') === '1.2.3.4');
ok('IPv4-mapped IPv6 -> IPv4', N.normIp('::ffff:10.0.0.7') === '10.0.0.7');
ok('IPv6 kichik harf', N.normIp('2001:DB8::1') === '2001:db8::1');
ok('[IPv6]', N.normIp('[::1]') === '::1');
ok('yaroqsiz -> ""', N.normIp('evil') === '' && N.normIp('1.2.3') === '' && N.normIp('') === '' && N.normIp(null) === '');
ok('loopback: 127.0.0.1, ::1, ::ffff:127.0.0.1, 127.5.5.5', ['127.0.0.1', '::1', '::ffff:127.0.0.1', '127.5.5.5'].every(N.isLoopback));
ok('loopback emas: 10.0.0.1 / bo‘sh', !N.isLoopback('10.0.0.1') && !N.isLoopback(''));

sec('clientIp: to‘g‘ridan-to‘g‘ri ulanish — sarlavhalarga ishonilmaydi');
ok('tashqi peer + soxta XFF -> peer', N.clientIp(req('198.51.100.20', { 'x-forwarded-for': '203.0.113.5' })) === '198.51.100.20');
ok('tashqi peer + soxta X-Real-IP -> peer', N.clientIp(req('198.51.100.20', { 'x-real-ip': '203.0.113.5' })) === '198.51.100.20');
ok('IPv4-mapped peer', N.clientIp(req('::ffff:198.51.100.21')) === '198.51.100.21');

sec('clientIp: nginx (loopback) orqali');
ok('XFF bitta qiymat (nginx: $remote_addr)', N.clientIp(req('127.0.0.1', { 'x-forwarded-for': '198.51.100.30' })) === '198.51.100.30');
ok('XFF zanjiri — OXIRGI (nginx qo‘shgan) qiymat, mijoz yozgan chap qiymat emas',
  N.clientIp(req('127.0.0.1', { 'x-forwarded-for': '203.0.113.5, 198.51.100.31' })) === '198.51.100.31');
ok('X-Real-IP = XFF oxirgisi -> X-Real-IP', N.clientIp(req('::1', { 'x-real-ip': '198.51.100.32', 'x-forwarded-for': '1.1.1.1, 198.51.100.32' })) === '198.51.100.32');
ok('eski nginx (X-Real-IP qo‘yilmagan): mijoz yozgan X-Real-IP e’tiborsiz — XFF oxirgisi',
  N.clientIp(req('127.0.0.1', { 'x-real-ip': '203.0.113.5', 'x-forwarded-for': '198.51.100.33' })) === '198.51.100.33');
ok('faqat X-Real-IP (XFF yo‘q) -> X-Real-IP', N.clientIp(req('127.0.0.1', { 'x-real-ip': '198.51.100.34' })) === '198.51.100.34');
ok('yaroqsiz XFF oxirgisi -> X-Real-IP yoki peer', N.clientIp(req('127.0.0.1', { 'x-forwarded-for': '198.51.100.35, garbage' })) === '127.0.0.1');
ok('sarlavhasiz loopback -> 127.0.0.1', N.clientIp(req('127.0.0.1')) === '127.0.0.1');
ok('socket yo‘q -> ""', N.clientIp({ headers: {} }) === '');

sec('ipMatcher: aniq IP / CIDR / IPv6 / yaroqsiz va juda keng tarmoq');
const m = N.ipMatcher(['203.0.113.7', '198.51.100.0/28', '2001:db8:abcd::/48', 'bad-ip', '0.0.0.0/0', '10.0.0.0/8', '1.2.3.4/33', '  ']);
ok('aniq IP', m.has('203.0.113.7') && !m.has('203.0.113.8'));
ok('CIDR /28 ichida va tashqarisida', m.has('198.51.100.0') && m.has('198.51.100.15') && !m.has('198.51.100.16'));
ok('IPv4-mapped kirish', m.has('::ffff:198.51.100.3'));
ok('IPv6 /48', m.has('2001:db8:abcd:12::1') && !m.has('2001:db8:abce::1'));
ok('yaroqsiz / juda keng yozuvlar bad ro‘yxatida', JSON.stringify(m.bad) === JSON.stringify(['bad-ip', '0.0.0.0/0', '10.0.0.0/8', '1.2.3.4/33']), JSON.stringify(m.bad));
ok('juda keng tarmoq qo‘shilmadi (7.7.7.7 ishonchli emas)', !m.has('7.7.7.7') && !m.has('10.1.2.3'));
ok('size = 3', m.size === 3, m.size);
const m2 = N.ipMatcher('192.0.2.1, 192.0.2.64/26');
ok('vergulli satr', m2.has('192.0.2.1') && m2.has('192.0.2.100') && !m2.has('192.0.2.2'));
const m3 = N.ipMatcher(undefined);
ok('bo‘sh ro‘yxat — hech kim ishonchli emas', m3.size === 0 && !m3.has('127.0.0.1') && !m3.has(''));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
