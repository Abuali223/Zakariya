// Service Worker: cache static + content (stale-while-revalidate)
const CACHE = 'arab-pwa-v1';
const CORE = [
  './',
  './index.html',
  './app.js',
  './manifest.json',
  './assets/icons/icon-192.png',
  './assets/icons/icon-512.png'
];

self.addEventListener('install', e=>{
  e.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)));
  self.skipWaiting();
});

self.addEventListener('activate', e=>{
  e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))));
  self.clients.claim();
});

self.addEventListener('fetch', e=>{
  const url = new URL(e.request.url);
  // Navigation fallback
  if (e.request.mode === 'navigate'){
    e.respondWith(fetch(e.request).catch(()=>caches.match('./index.html')));
    return;
  }
  // Stale-while-revalidate for same-origin
  if (url.origin === location.origin){
    e.respondWith(
      caches.match(e.request).then(cached=>{
        const fetched = fetch(e.request).then(res=>{
          const clone = res.clone();
          caches.open(CACHE).then(c=>c.put(e.request, clone));
          return res;
        }).catch(()=>cached);
        return cached || fetched;
      })
    );
  }
});
