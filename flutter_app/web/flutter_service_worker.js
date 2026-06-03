/* Harisree PWA — cache-first for static assets; API stays network-only. */
const CACHE_VERSION = 'harisree-static-v1';
const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.png',
  '/flutter_bootstrap.js',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
];

const STATIC_EXT =
  /\.(js|wasm|mjs|json|png|jpg|jpeg|gif|webp|svg|ico|woff2?|ttf|otf)$/i;

function isApiRequest(url) {
  return url.pathname.startsWith('/v1/');
}

function isStaticAsset(url) {
  if (url.origin !== self.location.origin) return false;
  if (isApiRequest(url)) return false;
  return STATIC_EXT.test(url.pathname) || url.pathname.startsWith('/canvaskit/');
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_VERSION)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((k) => k !== CACHE_VERSION)
            .map((k) => caches.delete(k)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (isApiRequest(url)) return;

  if (isStaticAsset(url) || PRECACHE_URLS.includes(url.pathname)) {
    event.respondWith(
      caches.match(req).then((cached) => {
        if (cached) return cached;
        return fetch(req).then((res) => {
          if (!res || res.status !== 200 || res.type === 'opaque') return res;
          const copy = res.clone();
          caches.open(CACHE_VERSION).then((cache) => cache.put(req, copy));
          return res;
        });
      }),
    );
  }
});
