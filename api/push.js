import webpush from 'web-push'
import { createClient } from '@supabase/supabase-js'

const VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY || 'BPv95LyDbnjSyofJOBm8iePCEuH9L7NQdYX-nKoqdcvi_lzmKRAGUeXlBvITdkTN53BG--_6scvMvRYZfzKcigk'
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY
const VAPID_SUBJECT = process.env.VAPID_SUBJECT || 'mailto:admin@smartband.local'

if (VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY) {
  webpush.setVapidDetails(
    VAPID_SUBJECT,
    VAPID_PUBLIC_KEY,
    VAPID_PRIVATE_KEY
  )
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export default async function handler(req, res) {
  // 1. CORS & Allow-listed origins
  const origin = req.headers.origin || ''
  const allowedOrigins = [
    process.env.APP_URL,
    process.env.VITE_APP_URL,
    'http://localhost:5173',
    'http://localhost:3000',
    'http://127.0.0.1:5173',
    'http://localhost:4173'
  ].filter(Boolean)

  res.setHeader('Vary', 'Origin')
  if (origin && (allowedOrigins.includes(origin) || origin.endsWith('.vercel.app'))) {
    res.setHeader('Access-Control-Allow-Origin', origin)
  }
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, apikey')

  // 2. Preflight handling (return 204)
  if (req.method === 'OPTIONS') {
    return res.status(204).end()
  }

  // 3. Method validation (return 405 with Allow header)
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS')
    return res.status(405).json({ error: 'Method not allowed' })
  }

  try {
    // 4. Caller Authentication via JWT & Anon client
    const authHeader = req.headers.authorization || ''
    if (!authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized: Missing or invalid Bearer token' })
    }

    const supabaseUrl = process.env.VITE_SUPABASE_URL || 'https://tztlnltutpntzrnsrdvo.supabase.co'
    const supabaseAnonKey = process.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_dsd7V2hfbdaYc3h18s_xGw_cCJ4wSE4'
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || ''

    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } }
    })

    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) {
      return res.status(401).json({ error: 'Unauthorized: Invalid or expired session' })
    }

    // 5. Role authorization: require super_admin or secretary_admin
    const { data: callerRole, error: roleError } = await authClient.rpc('get_auth_role', { user_id: user.id })
    if (roleError || !['super_admin', 'secretary_admin'].includes(callerRole)) {
      return res.status(403).json({ error: 'Forbidden: Only Band Officers (Super Admin / Secretary) can broadcast push notifications' })
    }

    // 6. Strict payload validation
    const { title, message, url, tag, senderId } = req.body || {}
    if (!title || typeof title !== 'string' || title.trim().length === 0 || title.length > 120) {
      return res.status(400).json({ error: 'Validation failed: title must be a non-empty string under 120 characters' })
    }

    if (message && (typeof message !== 'string' || message.length > 500)) {
      return res.status(400).json({ error: 'Validation failed: message must be under 500 characters' })
    }

    // Reject non-relative URLs (prevent open redirect / phishing)
    if (url) {
      if (typeof url !== 'string' || !url.startsWith('/') || url.startsWith('//') || url.includes('\\')) {
        return res.status(400).json({ error: 'Validation failed: url must be a relative path starting with /' })
      }
    }

    // Validate senderId format if provided
    if (senderId && (typeof senderId !== 'string' || !UUID_REGEX.test(senderId))) {
      return res.status(400).json({ error: 'Validation failed: senderId must be a valid UUID' })
    }

    if (!VAPID_PRIVATE_KEY) {
      console.warn('VAPID_PRIVATE_KEY is not configured on the server.')
      return res.status(500).json({ error: 'Push service configuration missing on server' })
    }

    // 7. Database client for subscription retrieval
    const dbClient = serviceRoleKey
      ? createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })
      : authClient

    // Fetch all push subscriptions from Supabase
    let query = dbClient.from('push_subscriptions').select('endpoint, p256dh, auth, user_id')
    if (senderId) {
      query = query.neq('user_id', senderId)
    }

    const { data: subscriptions, error } = await query
    if (error) {
      console.warn('Error fetching subscriptions:', error)
      return res.status(500).json({ error: error.message })
    }

    if (!subscriptions || subscriptions.length === 0) {
      return res.status(200).json({ success: true, count: 0, message: 'No registered push devices found' })
    }

    const notificationPayload = JSON.stringify({
      title: title || '🎷 Peñaranda Band 1870',
      body: message || 'You have an important update.',
      url: url || '/dashboard',
      tag: tag || 'smartband-' + Date.now()
    })

    const results = await Promise.allSettled(
      subscriptions.map(async (sub) => {
        if (!sub.endpoint || !sub.p256dh || !sub.auth) return null
        const pushSubscription = {
          endpoint: sub.endpoint,
          keys: {
            p256dh: sub.p256dh,
            auth: sub.auth
          }
        }
        try {
          return await webpush.sendNotification(pushSubscription, notificationPayload)
        } catch (err) {
          if (err.statusCode === 410 || err.statusCode === 404) {
            await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint)
          }
          throw err
        }
      })
    )

    const delivered = results.filter(r => r.status === 'fulfilled').length
    return res.status(200).json({ success: true, count: delivered, total: subscriptions.length })
  } catch (err) {
    console.error('Push notification handler error:', err)
    return res.status(500).json({ error: err.message })
  }
}
