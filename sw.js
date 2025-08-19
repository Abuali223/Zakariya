// Cache versiya
const CACHE = 'arab-pwa-v2'; // yangi versiya

// Asosiy fayllar (app ishlashi uchun kerak bo'ladiganlar)
const CORE = [
  './',
  './index.html',
  './app.js',
  './manifest.json',
  './assets/icons/icon-192.png',
  './assets/icons/icon-512.png'
];

// Install bosqichi – fayllarni keshlash
self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(CORE))
  );
  self.skipWaiting();
});

// Activate bosqichi – eski keshlardan tozalash
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))
      )
    )
  );
  self.clients.claim();
});

// Fetch bosqichi – keshdan yoki internetdan olish
self.addEventListener('fetch', (e) => {
  if (e.request.mode === 'navigate') {
    e.respondWith(
      fetch(e.request).catch(() => caches.match('./index.html'))
    );
    return;
  }

  e.respondWith(
    caches.match(e.request).then((resp) => resp || fetch(e.request))
  );
});