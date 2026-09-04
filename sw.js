/* Iqror Academy — network-first service worker.
   Onlaynda doim yangi kontent (fresh), oflaynda keshdan ishlaydi.
   Firebase/Google so'rovlariga tegmaydi (boshqa origin).
   MUHIM: kod fayllari (HTML/JS/JSON) uchun fetch {cache:'reload'} — brauzer HTTP/CDN
   keshini chetlab, serverdan DOIM yangi oladi (deploy darhol ko'rinadi). */
const V = 'iqror-v3';

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

  // Kod/ma'lumot (HTML/JS/JSON) — HAR DOIM serverdan yangi (brauzer keshi chetlanadi).
  const isCode = req.mode === 'navigate' || /\.(?:html|js|json|webmanifest)$/.test(url.pathname);
  // Statik aktivlar (rasm/css/shrift) — oddiy (kesh foydali).
  const isAsset = /\.(?:png|jpg|jpeg|svg|css|ico|woff2?|ttf)$/.test(url.pathname);

  e.respondWith((async () => {
    try {
      const fresh = await fetch(req, isCode ? { cache: 'reload' } : undefined);
      if (fresh && fresh.status === 200 && (isCode || isAsset)) {
        const cache = await caches.open(V);
        cache.put(req, fresh.clone());
      }
      return fresh;
    } catch (err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      if (req.mode === 'navigate') {
        // Avval AYNI sahifani (masalan admin.html) keshdan; bo'lmasa bosh sahifa.
        const idx = (await caches.match(req.url)) || (await caches.match('/index.html')) || (await caches.match('/'));
        if (idx) return idx;
      }
      throw err;
    }
  })());
});
