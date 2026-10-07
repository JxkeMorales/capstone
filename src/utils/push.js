import { supabase } from '@/supabase'

/**
 * Dispatch background Web Push Notification via /api/push serverless function.
 * Delivers push messages to registered mobile phones and desktop PCs even when the app is closed.
 * 
 * @returns {{ success: boolean, error?: string, permission?: 'default'|'granted'|'denied' }}
 */
export const sendPushNotification = async ({ title, message, url = '/dashboard', tag, senderId }) => {
  try {
    const { data: { session } } = await supabase.auth.getSession()
    const token = session?.access_token || ''
    const userId = session?.user?.id || null

    // Check browser push permission status
    let permission = 'default'
    if ('Notification' in window) {
      permission = Notification.permission
    }

    const response = await fetch('/api/push', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { 'Authorization': `Bearer ${token}` } : {})
      },
      body: JSON.stringify({
        title,
        message,
        url,
        tag: tag || 'smartband-' + Date.now(),
        senderId: senderId || userId || null,
        // Include permission status for server-side tracking
        permission
      })
    })

    if (!response.ok) {
      const err = await response.json().catch(() => ({ message: 'Unknown push delivery error' }))
      console.warn('[Web Push Delivery Note]:', err)
      // Return permission info even on delivery failure
      return { 
        success: false, 
        error: err.message || 'Delivery failed',
        permission 
      }
    }

    const result = await response.json()
    console.log('[Web Push] Delivered to devices:', result)
    return { success: true, ...result, permission }
  } catch (err) {
    console.warn('[Web Push Delivery Network Note]:', err)
    return { success: false, error: (err && err.message) || 'Network error', permission: Notification?.permission || 'default' }
  }
}

/**
 * Request notification permission from the user.
 * Returns the granted permission status.
 */
export const requestPushPermission = async () => {
  if (!('Notification' in window)) {
    return 'denied'
  }
  
  // If permission already granted or denied, return current status
  if (Notification.permission !== 'default') {
    return Notification.permission
  }
  
  try {
    const permission = await Notification.requestPermission()
    return permission
  } catch (err) {
    console.warn('[Push Permission Request Error]:', err)
    return 'denied'
  }
}
