self.addEventListener('push', function(event) {
  if (event.data) {
    try {
      const data = event.data.json()
      const title = data.title || 'SmartBand Notification'
      const options = {
        body: data.body || 'You have a new message from SmartBand.',
        icon: '/favicon.svg',
        badge: '/favicon.svg',
        vibrate: [200, 100, 200, 100, 200],
        data: data.url || '/'
      }
      event.waitUntil(self.registration.showNotification(title, options))
    } catch(err) {
      // Fallback if not JSON
      event.waitUntil(self.registration.showNotification('SmartBand', {
        body: event.data.text(),
        icon: '/favicon.svg'
      }))
    }
  }
})

self.addEventListener('notificationclick', function(event) {
  event.notification.close()
  if (event.notification.data) {
    event.waitUntil(clients.openWindow(event.notification.data))
  } else {
    event.waitUntil(clients.openWindow('/'))
  }
})
