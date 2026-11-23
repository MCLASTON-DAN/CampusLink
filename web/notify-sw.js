// CampusLink notifications worker. Shows notifications (Android Chrome needs a
// worker for this) and opens the right page when one is tapped.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL((event.notification.data && event.notification.data.url) || '/', self.location.origin).href;
  event.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of all) {
      if (c.url.startsWith(self.location.origin)) {
        await c.focus();
        if ('navigate' in c) { try { await c.navigate(url); } catch (_) {} }
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});

// Ready for real push messages later (needs a server key).
self.addEventListener('push', (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (_) { d = { title: 'CampusLink', body: event.data && event.data.text() }; }
  event.waitUntil(self.registration.showNotification(d.title || 'CampusLink', {
    body: d.body || '', icon: '/icons/Icon-192.png', badge: '/icons/Icon-192.png', data: { url: d.url || '/' },
  }));
});
