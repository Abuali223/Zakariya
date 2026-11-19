'use strict';
// Sinov stendi sog'lik tekshiruvi (restProbe) — anon kalit bilan faqat OCHIQ jadvalni so'rashi kerak.
//   rls-timing.sql anon'ga faqat ochiq sayt kontentini (v_pub ro'yxati) qoldiradi; yopiq jadval (masalan users) anon'ga 401
//   qaytaradi va /__sinov/health 503 bo'lib, o'rnatish skriptining yakuniy tekshiruvi yiqiladi.
//   ishlatish: node probe.test.cjs   (sinov/ papkasidan)
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
const ok = (cond, name, info) => { if (cond) { pass++; console.log('PASS ' + name); } else { fail++; console.log('FAIL ' + name + (info ? ' — ' + info : '')); } };

const server = fs.readFileSync(path.join(__dirname, 'server.cjs'), 'utf8');
const timing = fs.readFileSync(path.join(__dirname, '..', 'migration', 'rls-timing.sql'), 'utf8');

const fn = (server.match(/function restProbe\(\)\s*\{[\s\S]*?\n\}/) || [''])[0];
ok(fn.length > 0, 'restProbe topildi');
const m = fn.match(/path:\s*'\/([a-z_]+)\?/);
const table = m ? m[1] : '';
ok(!!table, 'restProbe so\'raydigan jadval aniqlandi', table || 'path topilmadi');
ok(/Bearer ' \+ ANON_KEY/.test(fn), 'restProbe anon kalit bilan so\'raydi (tekshiruv ma\'noli)');

const pubDecl = (timing.match(/v_pub\s+constant\s+text\[\]\s*:=\s*array\[([\s\S]*?)\]/) || ['', ''])[1];
const pub = [...pubDecl.matchAll(/'([a-z_]+)'/g)].map(x => x[1]);
ok(pub.length >= 10, 'rls-timing.sql dagi ochiq ro\'yxat (v_pub) o\'qildi', 'soni: ' + pub.length);
ok(pub.includes(table), 'restProbe jadvali anon uchun ochiq (v_pub)', table + ' ro\'yxatda yo\'q: ' + pub.join(','));

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
