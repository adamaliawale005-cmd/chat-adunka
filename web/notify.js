// AduChat browser notifications (no server needed).
//
// Shows system notifications for new messages and calls while the AduChat
// page or installed web app is running, including when it is in the
// background. Notifications when the page is completely closed need
// Firebase Cloud Messaging Web Push and server functions (not set up).
//
// The Flutter app calls these functions through window.aduchatNotify.
(function () {
  'use strict';
  var pending = null;
  var onOpen = null;
  var registration = null;

  // "?open=chat:<id>" is used when a notification is tapped after the
  // page was closed.
  try {
    var params = new URLSearchParams(window.location.search);
    if (params.get('open')) {
      pending = params.get('open');
      params.delete('open');
      var q = params.toString();
      history.replaceState(null, '', window.location.pathname + (q ? '?' + q : '') + window.location.hash);
    }
  } catch (e) { /* ignore */ }

  function deliver(payload) {
    if (!payload) return;
    try { window.focus(); } catch (e) { /* ignore */ }
    if (onOpen) { onOpen(payload); } else { pending = payload; }
  }

  // A dedicated service worker with its own scope: it only handles
  // notification clicks and never caches or intercepts page requests.
  if ('serviceWorker' in navigator) {
    try {
      navigator.serviceWorker.register('notify/sw.js', { scope: 'notify/' })
        .then(function (r) { registration = r; })
        .catch(function () { /* unsupported or blocked */ });
      navigator.serviceWorker.addEventListener('message', function (e) {
        var d = e.data || {};
        if (d.type === 'aduchat-open') deliver(d.payload);
      });
      if (navigator.serviceWorker.startMessages) navigator.serviceWorker.startMessages();
    } catch (e) { /* ignore */ }
  }

  function supported() { return 'Notification' in window; }

  window.aduchatNotify = {
    supported: function () { return supported(); },
    permission: function () { return supported() ? Notification.permission : 'unsupported'; },
    request: function () {
      if (!supported()) return Promise.resolve('unsupported');
      try {
        var r = Notification.requestPermission(function () {});
        return (r && r.then) ? r.catch(function () { return Notification.permission; })
                             : Promise.resolve(Notification.permission);
      } catch (e) { return Promise.resolve(Notification.permission); }
    },
    // True when the person is looking at AduChat right now.
    visible: function () {
      return document.visibilityState === 'visible' &&
        (typeof document.hasFocus !== 'function' || document.hasFocus());
    },
    show: function (title, body, tag, payload, urgent) {
      if (!supported() || Notification.permission !== 'granted') return Promise.resolve(false);
      var options = {
        body: body || '',
        tag: tag || undefined,
        renotify: !!tag,           // only allowed together with a tag
        icon: 'icons/Icon-192.png',
        badge: 'icons/Icon-maskable-192.png',
        requireInteraction: !!urgent,
        data: { payload: payload || '', url: window.location.href.split('?')[0].split('#')[0] }
      };
      function viaPage() {
        try {
          var n = new Notification(title, options);
          n.onclick = function () { n.close(); deliver(payload); };
          return true;
        } catch (e) { return false; }   // Android Chrome only allows the service worker way
      }
      var reg = registration;
      var p = reg ? Promise.resolve(reg)
                  : ('serviceWorker' in navigator ? navigator.serviceWorker.getRegistration('notify/') : Promise.resolve(null));
      return p.then(function (r) {
        if (r && r.showNotification) {
          return r.showNotification(title, options).then(function () { return true; }, viaPage);
        }
        return viaPage();
      }).catch(function () { return viaPage(); });
    },
    close: function (tag) {
      if (!('serviceWorker' in navigator)) return;
      navigator.serviceWorker.getRegistration('notify/').then(function (r) {
        if (!r || !r.getNotifications) return;
        r.getNotifications({ tag: tag }).then(function (list) { list.forEach(function (n) { n.close(); }); });
      }).catch(function () {});
    },
    // Number on the installed app icon, where the device supports it.
    setBadge: function (count) {
      try {
        if (count > 0 && navigator.setAppBadge) navigator.setAppBadge(count).catch(function () {});
        else if (navigator.clearAppBadge) navigator.clearAppBadge().catch(function () {});
      } catch (e) { /* ignore */ }
    },
    // Called by the app once it can open chats.
    listen: function (handler) {
      onOpen = handler;
      var p = pending;
      pending = null;
      if (p) handler(p);
    }
  };
})();
