/* Iqror Academy — network-first service worker.
   Onlaynda doim yangi kontent (fresh), oflaynda keshdan ishlaydi.
   Firebase/Google so'rovlariga tegmaydi (boshqa origin). */
const V = 'iqror-v1';

self.addEventListener('install', () => { self.skipWaiting(); });

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== V).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // faqat o'z origin

  e.respondWith((async () => {
    try {
      const fresh = await fetch(req);
      if (fresh && fresh.status === 200 &&
          (req.mode === 'navigate' || /\.(?:html|png|jpg|jpeg|svg|css|js|json|webmanifest|ico)$/.test(url.pathname))) {
        const cache = await caches.open(V);
        cache.put(req, fresh.clone());
      }
      return fresh;
    } catch (err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      if (req.mode === 'navigate') {
        const idx = (await caches.match('/index.html')) || (await caches.match('/'));
        if (idx) return idx;
      }
      throw err;
    }
  })());
});
