import { supabase } from '@/supabase'

/**
 * Dispatch background Web Push Notification via /api/push serverless function.
 * Delivers push messages to registered mobile phones and desktop PCs even when the app is closed.
 */
export const sendPushNotification = async ({ title, message, url = '/dashboard', tag, senderId }) => {
  try {
    const { data: { session } } = await supabase.auth.getSession()
    const token = session?.access_token || ''

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
        senderId: senderId || session?.user?.id || null
      })
    })

    if (!response.ok) {
      const err = await response.json().catch(() => ({}))
      console.warn('[Web Push Delivery Note]:', err)
      return { success: false, error: err }
    }

    const result = await response.json()
    console.log('[Web Push] Delivered to devices:', result)
    return { success: true, ...result }
  } catch (err) {
    console.warn('[Web Push Delivery Network Note]:', err)
    return { success: false, error: err }
  }
}
