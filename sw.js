// sw.js — migratsiya uchun: eski Arab Tili service worker keshini tozalaydi va o‘zini o‘chiradi.
// Yangi Iqror IT MED School sayti (index.html) service worker ishlatmaydi; bu fayl faqat
// avval ro‘yxatdan o‘tgan eski SW ni yangilab, eskirgan keshlangan sahifani ko‘rsatmasligi uchun.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    } catch (e) {}
    try { await self.registration.unregister(); } catch (e) {}
    try {
      const clients = await self.clients.matchAll({ type: 'window' });
      clients.forEach((c) => c.navigate(c.url));
    } catch (e) {}
  })());
});

// Barcha so‘rovlarni tarmoqqa o‘tkazib yuboramiz (keshdan bermaymiz).
self.addEventListener('fetch', () => {});
