const CACHE = 'landbank-sales-pro-v1';
const APP_SHELL = [
  './sales-pro-mobile.html',
  './sales-pro.html',
  './sales-pro-todo.js',
  './sales-pro.webmanifest',
  './sales-pro-icon.svg',
  './sales-pro-pwa-bridge.js'
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.allSettled(APP_SHELL.map(async url => {
      const response = await fetch(url, { cache: 'reload' });
      if (response.ok) await cache.put(url, response.clone());
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // Never cache live Supabase/API traffic.

  const isAppAsset = APP_SHELL.some(item => url.pathname.endsWith(item.replace('./', '')));
  if (!isAppAsset && request.mode !== 'navigate') return;

  event.respondWith((async () => {
    try {
      const fresh = await fetch(request);
      if (fresh && fresh.ok) {
        const cache = await caches.open(CACHE);
        cache.put(request, fresh.clone()).catch(() => {});
      }
      return fresh;
    } catch (error) {
      const cached = await caches.match(request);
      if (cached) return cached;
      if (request.mode === 'navigate') {
        const fallback = await caches.match('./sales-pro-mobile.html');
        if (fallback) return fallback;
      }
      throw error;
    }
  })());
});
