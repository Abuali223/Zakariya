/**
 * auth/net.cjs — mijoz IP manzili va ishonchli (maktab Wi‑Fi) IP ro'yxati. SOF funksiyalar (DB'siz) — birlik testlari oson.
 * -------------------------------------------------------------------
 * Mijoz IP'si (OTP/IP limiti shunga bog'liq):
 *   - So'rov to'g'ridan-to'g'ri (loopback EMAS) kelsa — faqat soket manzili; X-Real-IP / X-Forwarded-For sarlavhalariga
 *     ISHONILMAYDI (ularni mijozning o'zi yozadi).
 *   - So'rov loopback'dan (nginx) kelsa: X-Forwarded-For'ning OXIRGI qiymati — uni nginx qo'shadi
 *     (proxy_set_header X-Forwarded-For $remote_addr yoki $proxy_add_x_forwarded_for); mijoz yozgan chap qiymatlar
 *     hisobga olinmaydi. X-Real-IP (nginx: $remote_addr) bo'lsa — afzal, LEKIN faqat XFF'ning oxirgi qiymati bilan mos
 *     kelsa yoki XFF umuman bo'lmasa: eski nginx sozlamasida (X-Real-IP qo'yilmagan) mijoz yozgan X-Real-IP nginx'dan
 *     o'zgarmay o'tadi — u bilan limitni chetlab o'tib (yoki maktab IP'sini «da'vo qilib») bo'lmasin.
 * Ishonchli ro'yxat: aniq IP yoki CIDR ('203.0.113.7', '198.51.100.0/28', '2001:db8::/48'). Juda keng tarmoq
 *   (IPv4 /16 dan, IPv6 /32 dan keng — masalan 0.0.0.0/0) va yaroqsiz yozuvlar QABUL QILINMAYDI (bad ro'yxatda) — xato
 *   sozlama hammaga oshirilgan limit bermasin.
 */
const net = require('net');

// '::ffff:1.2.3.4' (IPv4-mapped IPv6) -> '1.2.3.4'; [kvadrat qavs] va bo'shliqlar olinadi. Yaroqsiz -> ''.
function normIp(v) {
  let s = String(v == null ? '' : v).trim();
  if (s.startsWith('[') && s.endsWith(']')) s = s.slice(1, -1);
  const m = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(s);
  if (m) s = m[1];
  return net.isIP(s) ? s.toLowerCase() : '';
}
function isLoopback(ip) {
  const s = normIp(ip);
  return s === '::1' || /^127\./.test(s);
}
// So'rovchi IP'si (yuqoridagi qoida). req: { socket:{remoteAddress}, headers }.
function clientIp(req) {
  const peer = normIp(req && req.socket && req.socket.remoteAddress);
  if (!isLoopback(peer)) return peer;
  const h = (req && req.headers) || {};
  const xr = normIp(String(h['x-real-ip'] || '').split(',')[0]);
  const xff = String(h['x-forwarded-for'] || '').split(',').map(s => s.trim()).filter(Boolean);
  const xl = xff.length ? normIp(xff[xff.length - 1]) : '';
  if (xr && xl) return xr === xl ? xr : xl;
  return xr || xl || peer;
}

// Ishonchli IP ro'yxati -> { has(ip), size, bad:[...] }. list: massiv yoki vergulli satr.
function ipMatcher(list) {
  const bl = new net.BlockList();
  const bad = [];
  let size = 0;
  const items = Array.isArray(list) ? list : String(list == null ? '' : list).split(',');
  for (const raw of items) {
    const s = String(raw == null ? '' : raw).trim();
    if (!s) continue;
    const slash = s.indexOf('/');
    const ip = normIp(slash >= 0 ? s.slice(0, slash) : s);
    if (!ip) { bad.push(s); continue; }
    const fam = net.isIP(ip) === 6 ? 'ipv6' : 'ipv4';
    if (slash < 0) { bl.addAddress(ip, fam); size++; continue; }
    const bits = s.slice(slash + 1);
    const b = Number(bits), max = fam === 'ipv6' ? 128 : 32, min = fam === 'ipv6' ? 32 : 16;
    if (!/^\d{1,3}$/.test(bits) || b < min || b > max) { bad.push(s); continue; }
    bl.addSubnet(ip, b, fam); size++;
  }
  const has = ip => {
    const s = normIp(ip);
    if (!s || !size) return false;
    try { return bl.check(s, net.isIP(s) === 6 ? 'ipv6' : 'ipv4'); } catch (_) { return false; }
  };
  return { has, size, bad };
}

module.exports = { normIp, isLoopback, clientIp, ipMatcher };
