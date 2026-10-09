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

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, apikey')

  if (req.method === 'OPTIONS') {
    return res.status(200).end()
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' })
  }

  try {
    const { title, message, url, tag, senderId } = req.body || {}
    if (!title) {
      return res.status(400).json({ error: 'Missing title' })
    }

    const authHeader = req.headers.authorization || ''
    const supabaseUrl = process.env.VITE_SUPABASE_URL || 'https://tztlnltutpntzrnsrdvo.supabase.co'
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || ''
    const supabaseAnonKey = process.env.VITE_SUPABASE_ANON_KEY || 'sb_publishable_dsd7V2hfbdaYc3h18s_xGw_cCJ4wSE4'
    const activeKey = serviceRoleKey || supabaseAnonKey

    const supabase = createClient(supabaseUrl, activeKey, {
      auth: { persistSession: false },
      global: {
        headers: (!serviceRoleKey && authHeader) ? { Authorization: authHeader } : {}
      }
    })

    // Fetch all push subscriptions from Supabase
    let query = supabase.from('push_subscriptions').select('endpoint, p256dh, auth, user_id')
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
