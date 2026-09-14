import { supabase } from '@/supabase'

// 1. Persistent Native Inter-Tab BroadcastChannels (Support both naming conventions)
let nativeBroadcastMaster = null
let nativeBroadcastLive = null

if (typeof window !== 'undefined' && 'BroadcastChannel' in window) {
  try {
    nativeBroadcastMaster = new BroadcastChannel('smartband_master_sync')
    nativeBroadcastLive = new BroadcastChannel('smartband_live_sync')
  } catch (e) {
    console.warn('BroadcastChannel not supported in this environment')
  }
}

// 2. Persistent Supabase Realtime Channels
let supabaseMasterChannel = null
let supabaseAlertsChannel = null
const listeners = new Set()

const dispatch = (event, payload) => {
  const normalizedEvent = typeof event === 'string' ? event.toLowerCase() : ''
  listeners.forEach(cb => {
    try {
      cb(event, payload)
      if (normalizedEvent && normalizedEvent !== event) {
        cb(normalizedEvent, payload)
      }
    } catch (err) {
      console.error('[Realtime Dispatch Error]', err)
    }
  })
}

// Wire up Native Inter-Tab listeners
if (nativeBroadcastMaster) {
  nativeBroadcastMaster.onmessage = (e) => {
    if (e.data && (e.data.event || e.data.type)) {
      dispatch(e.data.event || e.data.type, e.data.payload || e.data)
    }
  }
}

if (nativeBroadcastLive) {
  nativeBroadcastLive.onmessage = (e) => {
    if (e.data && (e.data.event || e.data.type)) {
      dispatch(e.data.event || e.data.type, e.data.payload || e.data)
    }
  }
}

export const initRealtimeSync = (callback) => {
  if (callback && typeof callback === 'function') {
    listeners.add(callback)
  }

  // 1. Master Sync Channel
  if (!supabaseMasterChannel) {
    supabaseMasterChannel = supabase.channel('smartband-master-sync', {
      config: {
        broadcast: { ack: true, self: true }
      }
    })

    supabaseMasterChannel
      .on('broadcast', { event: '*' }, (data) => {
        dispatch(data.event, data.payload)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, (p) => {
        dispatch('profiles_changed', p)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'events' }, (p) => {
        dispatch('events_changed', p)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'event_rsvps' }, (p) => {
        dispatch('rsvps_changed', p)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'announcements' }, (p) => {
        dispatch('announcements_changed', p)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'member_availability' }, (p) => {
        dispatch('availability_changed', p)
      })
      .subscribe((status) => {
        console.log('[Realtime Master Sync] Status:', status)
      })
  }

  // 2. Broadcast Alerts Channel (for layout and notifications)
  if (!supabaseAlertsChannel) {
    supabaseAlertsChannel = supabase.channel('smartband-broadcast-alerts', {
      config: {
        broadcast: { ack: true, self: true }
      }
    })

    supabaseAlertsChannel
      .on('broadcast', { event: '*' }, (data) => {
        dispatch(data.event, data.payload)
      })
      .subscribe((status) => {
        console.log('[Realtime Alerts Channel] Status:', status)
      })
  }

  // Auto-reconnect / trigger on tab focus or back online
  if (typeof window !== 'undefined' && !window.__smartband_realtime_wired) {
    window.__smartband_realtime_wired = true
    window.addEventListener('online', () => {
      dispatch('network_reconnected', { time: Date.now() })
    })
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        dispatch('tab_focused', { time: Date.now() })
      }
    })
  }

  return () => {
    if (callback) {
      listeners.delete(callback)
    }
  }
}

export const broadcastSync = async (event, payload = {}) => {
  const timestamp = Date.now()
  const upperType = typeof event === 'string' ? event.toUpperCase() : ''
  const lowerEvent = typeof event === 'string' ? event.toLowerCase() : ''

  // 1. Instant local broadcast across open browser tabs
  try {
    const msg = { event, type: upperType, payload, timestamp }
    if (nativeBroadcastMaster) nativeBroadcastMaster.postMessage(msg)
    if (nativeBroadcastLive) nativeBroadcastLive.postMessage(msg)
  } catch (e) {}

  // 2. Dispatch to listeners in the current tab immediately (0ms)
  listeners.forEach(cb => {
    try {
      cb(event, payload)
      if (lowerEvent && lowerEvent !== event) cb(lowerEvent, payload)
    } catch (err) {}
  })

  // 3. Send over Supabase WebSocket across remote devices
  try {
    if (!supabaseMasterChannel) {
      initRealtimeSync()
    }

    // Wait until subscribed (up to 2 seconds)
    if (supabaseMasterChannel && supabaseMasterChannel.state !== 'joined') {
      await new Promise((resolve) => {
        let count = 0
        const iv = setInterval(() => {
          count++
          if (supabaseMasterChannel.state === 'joined' || count > 20) {
            clearInterval(iv)
            resolve()
          }
        }, 100)
      })
    }

    const promises = []

    if (supabaseMasterChannel) {
      promises.push(
        supabaseMasterChannel.send({
          type: 'broadcast',
          event,
          payload: { ...payload, timestamp }
        })
      )
    }

    if (supabaseAlertsChannel) {
      promises.push(
        supabaseAlertsChannel.send({
          type: 'broadcast',
          event,
          payload: { ...payload, timestamp }
        })
      )
    }

    await Promise.allSettled(promises)
  } catch (err) {
    console.warn('[Realtime] broadcastSync error:', err)
  }
}
