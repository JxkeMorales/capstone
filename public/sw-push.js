// Web Push Background Listener for SmartBand PWA
// Receives push notifications from server even when the app / browser tab is completely closed.

self.addEventListener('push', function(event) {
  let data = {}
  if (event.data) {
    try {
      data = event.data.json()
    } catch (e) {
      try {
        data = { title: 'Peñaranda Band 1870', body: event.data.text() }
      } catch (err) {
        data = { title: 'Peñaranda Band 1870', body: 'New notification from SmartBand' }
      }
    }
  }

  const title = data.title || '🎷 Peñaranda Band 1870'
  const options = {
    body: data.body || data.message || 'You have an important update from the band.',
    icon: '/favicon.svg',
    badge: '/favicon.svg',
    vibrate: [250, 100, 250, 100, 250],
    tag: data.tag || 'smartband-push-' + Date.now(),
    renotify: true,
    requireInteraction: true,
    data: {
      url: data.url || '/dashboard'
    }
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener('notificationclick', function(event) {
  event.notification.close()
  let targetUrl = event.notification.data?.url || '/dashboard'
  // Validate notification click URL (Item 36): enforce safe relative path
  if (typeof targetUrl !== 'string' || !targetUrl.startsWith('/') || targetUrl.startsWith('//')) {
    targetUrl = '/dashboard'
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(windowClients) {
      for (let client of windowClients) {
        if ('focus' in client) {
          if (client.url.includes(targetUrl) || client.url.includes('/dashboard')) {
            return client.focus()
          }
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl)
      }
    })
  )
})
