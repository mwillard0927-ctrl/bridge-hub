// Bridge Hub service worker: phone notifications.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('push', e => {
  let d = {}; try { d = e.data ? e.data.json() : {}; } catch (_) { d = {title: 'Bridge Hub', body: e.data ? e.data.text() : ''}; }
  e.waitUntil(self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(list => {
    if (list.some(c => c.visibilityState === 'visible' && c.focused)) return;  // app is open on screen: it shows its own pop-up
    return self.registration.showNotification(d.title || 'Bridge Hub', {body: d.body || '', tag: d.tag, icon: 'icon-192.png', badge: 'icon-192.png', data: {url: d.url || '/'}});
  }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || '/';
  e.waitUntil(self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(list => {
    for (const c of list) { if ('focus' in c) return c.focus(); }
    return self.clients.openWindow(url);
  }));
});
