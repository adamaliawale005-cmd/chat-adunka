// AduChat notification service worker. Its scope is only "notify/", so it
// never controls or caches the app itself. It opens the right chat when a
// notification is tapped.
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var data = event.notification.data || {};
  var payload = data.payload || '';
  var appUrl = data.url || new URL('../', self.registration.scope).href;
  event.waitUntil((async function () {
    var all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    var base = new URL('../', self.registration.scope).href;
    for (var i = 0; i < all.length; i++) {
      var c = all[i];
      if (c.url.indexOf(base) === 0) {
        try { await c.focus(); } catch (e) { /* ignore */ }
        c.postMessage({ type: 'aduchat-open', payload: payload });
        return;
      }
    }
    var url = appUrl + (payload ? '?open=' + encodeURIComponent(payload) : '');
    await self.clients.openWindow(url);
  })());
});
