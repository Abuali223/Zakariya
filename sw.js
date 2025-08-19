// sw.js — minimal, cross-origin (supabase.co) so'rovlariga tegmaydi
const CACHE = 'arab-pwa-v9';  // <— versiyani har yangilashda oshiring

const CORE = [
  './',
  './index.html',
  './app.js',
  './ai.js',
  './config.js',
  './manifest.json',
  './assets/icons/icon-192.png',
  './assets/icons/icon-512.png'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  try {
    const u = new URL(e.request.url);
    // ⚠️ Tashqi domenlar (masalan, supabase.co) — umuman ushlamaymiz
    if (u.origin !== location.origin) return;

    // SPA navigatsiya fallback
    if (e.request.mode === 'navigate') {
      e.respondWith(caches.match('./index.html').then(r => r || fetch(e.request)));
      return;
    }

    // Oddiy cache-first
    e.respondWith(caches.match(e.request).then(r => r || fetch(e.request)));
  } catch (_) {}
});