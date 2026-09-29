<script setup>
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { RouterView, RouterLink, useRoute } from 'vue-router'
import { Home, Calendar, User, Sun, Moon, Music, Users, ShieldCheck, Download, Wifi, WifiOff, LogOut, Bell, BellOff, FileText, X, CheckCircle, AlertCircle, Check, Volume2, AlertTriangle, Clock, MapPin, HelpCircle, BookOpen, ChevronRight, Sparkles, Award } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useUIStore } from '@/stores/ui'
import { useRouter } from 'vue-router'
import { supabase } from '@/supabase'

const route = useRoute()
const router = useRouter()
const store = useMainStore()
const uiStore = useUIStore()

const savedTheme = localStorage.getItem('smartband_theme')
const isDark = ref(savedTheme !== 'light')

// Comprehensive User Guide Modal State
const showRoleGuideModal = ref(false)
const activeGuideTab = ref('roles') // 'roles' | 'attendance' | 'availability' | 'pwa'

// User Notification Settings (LocalStorage)
const enableBanners = ref(localStorage.getItem('smartband_banners_enabled') !== 'false')
const enableAlarms = ref(localStorage.getItem('smartband_alarms_enabled') !== 'false')

const toggleBanners = () => {
  enableBanners.value = !enableBanners.value
  localStorage.setItem('smartband_banners_enabled', enableBanners.value)
}

const toggleAlarms = () => {
  enableAlarms.value = !enableAlarms.value
  localStorage.setItem('smartband_alarms_enabled', enableAlarms.value)
}

// PWA Install & Installed Detection State
const deferredPrompt = ref(null)
const showInstallBanner = ref(false)
const isAppInstalled = ref(false)

// Online / Offline Network Monitor State
const isOnline = ref(navigator.onLine)
const networkToastMsg = ref('')

// Notification Permission State for First-Time Users
const notificationPermission = ref(typeof Notification !== 'undefined' ? Notification.permission : 'default')
const showFirstTimeNotifPrompt = ref(false)

// Settings & Notifications Drawer Modal State
const showSettingsDrawer = ref(false)
const showTermsModal = ref(false)
const pendingCount = ref(0)

// Pre-Event Call-Time Alarm Engine State
let callTimeMonitorTimer = null
let audioCtx = null
const activeAlarmModal = ref(null)

// Realtime & Inter-Tab Broadcast References
let announceSub = null
let eventsSub = null
let broadcastSub = null
let syncBroadcast = null
let userProfileSub = null

const checkPwaInstalled = () => {
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true
  isAppInstalled.value = isStandalone
}

const updateNetworkStatus = () => {
  const wasOnline = isOnline.value
  isOnline.value = navigator.onLine
  if (!wasOnline && isOnline.value) {
    showNetworkToast('🟢 Back Online! Synchronized latest band data.')
  } else if (wasOnline && !isOnline.value) {
    showNetworkToast('⚡ Operating Offline. Offline alarm countdown active.')
  }
}

const showNetworkToast = (msg) => {
  networkToastMsg.value = msg
  setTimeout(() => { networkToastMsg.value = '' }, 4500)
}

const toggleTheme = () => {
  isDark.value = !isDark.value
  if (isDark.value) {
    document.documentElement.classList.add('dark')
    localStorage.setItem('smartband_theme', 'dark')
  } else {
    document.documentElement.classList.remove('dark')
    localStorage.setItem('smartband_theme', 'light')
  }
}

const handleInstallPWA = async () => {
  if (isAppInstalled.value) {
    uiStore.addToast({ title: 'Already Installed', message: 'SmartBand is already installed on your device!', type: 'info' })
    return
  }
  const prompt = deferredPrompt.value || window.deferredPrompt
  if (!prompt) {
    uiStore.addToast({ title: 'Manual Install Required', message: 'To install: Tap Share (iOS) / Menu (Android) → Add to Home Screen. On Desktop: Click the Install icon in the address bar.', type: 'warning', duration: 8000 })
    return
  }
  prompt.prompt()
  const { outcome } = await prompt.userChoice
  if (outcome === 'accepted') {
    showInstallBanner.value = false
    isAppInstalled.value = true
  }
  deferredPrompt.value = null
  window.deferredPrompt = null
}

// 5-SECOND AUDIBLE MARCHING BRASS ALARM SYNTHESIZER
const playAlarmSiren = (durationSeconds = 5) => {
  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return
    if (!audioCtx) audioCtx = new AudioContextClass()
    if (audioCtx.state === 'suspended') audioCtx.resume()

    const now = audioCtx.currentTime
    const osc = audioCtx.createOscillator()
    const gain = audioCtx.createGain()

    osc.type = 'sawtooth'

    for (let t = 0; t < durationSeconds; t += 0.5) {
      osc.frequency.setValueAtTime(880, now + t)
      osc.frequency.setValueAtTime(1320, now + t + 0.25)
    }

    gain.gain.setValueAtTime(0.35, now)
    gain.gain.linearRampToValueAtTime(0.01, now + durationSeconds)

    osc.connect(gain)
    gain.connect(audioCtx.destination)

    osc.start(now)
    osc.stop(now + durationSeconds)

    if (navigator.vibrate) {
      navigator.vibrate([400, 200, 400, 200, 400])
    }
  } catch (e) {
    console.warn('Audio alarm notice:', e)
  }
}

const testAlarmTone = () => {
  playAlarmSiren(5)
  showNetworkToast('🔊 Playing 5-second Call-Time Alarm test...')
}

const urlB64ToUint8Array = (base64String) => {
  const padding = '='.repeat((4 - base64String.length % 4) % 4)
  const base64 = (base64String + padding).replace(/\-/g, '+').replace(/_/g, '/')
  const rawData = window.atob(base64)
  const outputArray = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray
}

const syncPushSubscription = async (forceRetry = false) => {
  if (!store.user) return
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return

  // Prevent repeated 404 network spam if push_subscriptions table has not been created in Supabase yet
  const tableMissingTime = localStorage.getItem('smartband_push_table_missing')
  if (!forceRetry && tableMissingTime) {
    const elapsed = Date.now() - parseInt(tableMissingTime, 10)
    if (elapsed < 6 * 60 * 60 * 1000) return // Re-check every 6 hours
  }

  try {
    const reg = await navigator.serviceWorker.ready
    let sub = await reg.pushManager.getSubscription()
    
    if (!sub && typeof Notification !== 'undefined' && Notification.permission === 'granted') {
      try {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlB64ToUint8Array('BGcxQLCkkaTHNWI4PL5UmWQ20X8dHCP6vnsql418_xaDas9cIf9riyfHfyPxXrT9zF47ViQ_B1qO_IqaxcjHzyA')
        })
      } catch (subErr) {
        return
      }
    }

    if (sub) {
      const rawKey = sub.getKey ? sub.getKey('p256dh') : null
      const rawAuth = sub.getKey ? sub.getKey('auth') : null
      const p256dh = rawKey ? btoa(String.fromCharCode.apply(null, new Uint8Array(rawKey))) : null
      const auth = rawAuth ? btoa(String.fromCharCode.apply(null, new Uint8Array(rawAuth))) : null

      const { error } = await supabase.from('push_subscriptions').upsert({
        user_id: store.user.id,
        endpoint: sub.endpoint,
        p256dh: p256dh,
        auth: auth
      }, { onConflict: 'user_id,endpoint' })

      if (error) {
        if (error.code === 'PGRST204' || error.code === '42P01' || error.status === 404 || error.message?.includes('schema cache') || error.message?.includes('not found') || error.message?.includes('relation')) {
          localStorage.setItem('smartband_push_table_missing', Date.now().toString())
        }
      } else {
        localStorage.removeItem('smartband_push_table_missing')
      }
    }
  } catch(e) {
    // Graceful catch for push sync
  }
}

const requestNotificationPermission = async () => {
  if (!('Notification' in window)) {
    uiStore.addToast({ title: 'Unsupported', message: 'Browser push notifications are not supported. Using in-app banners instead.', type: 'warning' })
    return
  }
  const result = await Notification.requestPermission()
  notificationPermission.value = result
  showFirstTimeNotifPrompt.value = false

  if (result === 'granted') {
    showNetworkToast('🔔 Call-Time Alarm & Push Notifications Active!')
    await syncPushSubscription()
    checkUpcomingCallTimes()
  }
}

const dismissFirstTimeNotifPrompt = () => {
  showFirstTimeNotifPrompt.value = false
  localStorage.setItem('smartband_notif_prompt_dismissed', 'true')
}

// FULLY OFFLINE-CAPABLE PRE-EVENT CALL-TIME ALARM & COUNTDOWN ENGINE
const checkUpcomingCallTimes = async () => {
  let attendingEvents = []

  const cachedEvents = localStorage.getItem('smartband_raw_events_cache')
  if (cachedEvents) {
    try {
      const parsed = JSON.parse(cachedEvents)
      parsed.forEach(ev => {
        const localRsvp = localStorage.getItem(`smartband_rsvp_${ev.id}`)
        if (localRsvp === 'attending' || ev.rsvpStatus === 'attending' || store.canManageEvents) {
          attendingEvents.push(ev)
        }
      })
    } catch(e){}
  }

  if (navigator.onLine && store.user) {
    try {
      const { data: rsvps } = await supabase
        .from('event_rsvps')
        .select('event_id, status, events(id, title, event_date, location, event_type)')
        .eq('user_id', store.user.id)
        .eq('status', 'attending')

      if (rsvps && rsvps.length > 0) {
        rsvps.forEach(r => {
          if (r.events && r.events.event_date) {
            if (!attendingEvents.some(e => e.id === r.events.id)) {
              attendingEvents.push({
                id: r.events.id,
                title: r.events.title,
                rawDate: r.events.event_date,
                location: r.events.location,
                type: r.events.event_type
              })
            }
          }
        })
      }
    } catch (err) {
      console.warn('Offline mode: using cached schedule for alarm countdown')
    }
  }

  if (attendingEvents.length === 0) return

  const now = Date.now()

  for (const ev of attendingEvents) {
    const rawDate = ev.rawDate || ev.event_date
    if (!rawDate) continue

    const evTime = new Date(rawDate).getTime()
    const diffMs = evTime - now
    const diffMinutes = Math.round(diffMs / (60 * 1000))

    if (diffMs > 0 && diffMinutes <= 15) {
      const notifKey15 = `smartband_alarm_15m_${ev.id}`
      if (!localStorage.getItem(notifKey15)) {
        localStorage.setItem(notifKey15, 'true')

        if (enableAlarms.value) {
          playAlarmSiren(5)
          activeAlarmModal.value = {
            title: ev.title,
            location: ev.location,
            timeText: new Date(rawDate).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
            countdownText: `Starts in ${diffMinutes} minutes`,
            urgency: 'warning'
          }
        }

        if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
          if ('serviceWorker' in navigator) {
            navigator.serviceWorker.ready.then(reg => {
              reg.showNotification(`🚨 Call-Time: ${ev.title}`, {
                body: `Starts in ${diffMinutes} min at ${ev.location}!`,
                icon: '/favicon.svg',
                vibrate: [200, 100, 200]
              })
            }).catch(e => console.warn(e))
          } else {
            try {
              new Notification(`🚨 Call-Time: ${ev.title}`, {
                body: `Starts in ${diffMinutes} min at ${ev.location}!`,
                icon: '/favicon.svg'
              })
            } catch(e){}
          }
        }

        if (enableBanners.value) {
          uiStore.playChime()
          uiStore.addToast({
            title: `🚨 Call-Time: ${ev.title}`,
            message: `Starts in ${diffMinutes} min at ${ev.location}!`,
            type: 'warning',
            duration: 10000
          })
        }
      }
    }

    if (diffMs <= 0 && diffMs >= -2 * 60 * 1000) {
      const notifKey0 = `smartband_alarm_0m_${ev.id}`
      if (!localStorage.getItem(notifKey0)) {
        localStorage.setItem(notifKey0, 'true')

        if (enableAlarms.value) {
          playAlarmSiren(5)
          activeAlarmModal.value = {
            title: ev.title,
            location: ev.location,
            timeText: new Date(rawDate).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
            countdownText: `EVENT IS STARTING NOW!`,
            urgency: 'danger'
          }
        }

        if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
          if ('serviceWorker' in navigator) {
            navigator.serviceWorker.ready.then(reg => {
              reg.showNotification(`🚨 Event Starting!`, {
                body: `${ev.title} is starting right now at ${ev.location}!`,
                icon: '/favicon.svg',
                vibrate: [400, 200, 400]
              })
            }).catch(e => console.warn(e))
          } else {
            try {
              new Notification(`🚨 Event Starting!`, {
                body: `${ev.title} is starting right now at ${ev.location}!`,
                icon: '/favicon.svg'
              })
            } catch(e){}
          }
        }

        if (enableBanners.value) {
          uiStore.playChime()
          uiStore.addToast({
            title: `🚨 Event Starting!`,
            message: `${ev.title} is starting right now at ${ev.location}!`,
            type: 'error',
            duration: 10000
          })
        }
      }
    }
  }
}

const dismissActiveAlarm = () => {
  activeAlarmModal.value = null
}

const fetchPendingCount = async () => {
  if (store.isSuperAdmin) {
    const { data } = await supabase.from('profiles').select('id').eq('is_verified', false)
    if (data) pendingCount.value = data.length
  }
}

const showSignOutModal = ref(false)

const triggerSignOut = () => {
  showSignOutModal.value = true
}

const handleSignOut = async () => {
  showSignOutModal.value = false
  await store.signOut()
  router.push('/')
}

onMounted(() => {
  // Apply initial theme from localStorage
  if (isDark.value) {
    document.documentElement.classList.add('dark')
  } else {
    document.documentElement.classList.remove('dark')
  }

  checkPwaInstalled()

  const mediaQuery = window.matchMedia('(display-mode: standalone)')
  if (mediaQuery.addEventListener) {
    mediaQuery.addEventListener('change', checkPwaInstalled)
  }

  window.addEventListener('appinstalled', () => {
    isAppInstalled.value = true
    showInstallBanner.value = false
  })

  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault()
    deferredPrompt.value = e
    window.deferredPrompt = e
    if (!isAppInstalled.value) {
      showInstallBanner.value = true
    }
  })

  // Sync with globally captured prompt
  if (window.deferredPrompt && !isAppInstalled.value) {
    deferredPrompt.value = window.deferredPrompt
    showInstallBanner.value = true
  }
  window.addEventListener('pwa-prompt-ready', () => {
    if (window.deferredPrompt && !isAppInstalled.value) {
      deferredPrompt.value = window.deferredPrompt
      showInstallBanner.value = true
    }
  })

  window.addEventListener('online', updateNetworkStatus)
  window.addEventListener('offline', updateNetworkStatus)

  const isPromptDismissed = localStorage.getItem('smartband_notif_prompt_dismissed') === 'true'
  if (typeof Notification !== 'undefined' && Notification.permission === 'default' && !isPromptDismissed) {
    showFirstTimeNotifPrompt.value = true
  }

  fetchPendingCount()

  checkUpcomingCallTimes()
  callTimeMonitorTimer = setInterval(checkUpcomingCallTimes, 30000)

  // 1. Realtime subscription for new announcements
  announceSub = supabase.channel('public:announcements')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'announcements' }, payload => {
      if (enableBanners.value) {
        const isUrgent = payload.new?.category?.toLowerCase().includes('urgent') || payload.new?.title?.toLowerCase().includes('urgent')
        if (isUrgent && enableAlarms.value) {
          playAlarmSiren(3)
        } else {
          uiStore.playChime()
        }
        uiStore.addToast({
          title: `📢 ${payload.new.title}`,
          message: payload.new.content || payload.new.category || 'Band Update',
          type: isUrgent ? 'warning' : 'info',
          duration: 12000
        })
      }
    })
    .subscribe()

  // 2. Realtime subscription for events with instant local cache updating and Availability Grid Matching
  eventsSub = supabase.channel('public:events_realtime_layout')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'events' }, async (payload) => {
      const eventType = payload.eventType || 'INSERT'
      const newEv = payload.new
      const oldEv = payload.old

      // Immediate cache sync so dashboard views and offline state have the latest event data instantly
      try {
        const cachedStr = localStorage.getItem('smartband_raw_events_cache')
        let cacheList = cachedStr ? JSON.parse(cachedStr) : []
        if (eventType === 'DELETE' && oldEv?.id) {
          cacheList = cacheList.filter(e => e.id !== oldEv.id)
        } else if (newEv && newEv.id) {
          const evDate = new Date(newEv.event_date)
          const formatted = {
            id: newEv.id,
            rawDate: newEv.event_date,
            title: newEv.title,
            date: evDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }),
            time: evDate.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
            location: newEv.location,
            type: newEv.event_type,
            rsvpStatus: localStorage.getItem(`smartband_rsvp_${newEv.id}`) || null,
            createdAt: newEv.created_at || new Date().toISOString()
          }
          const idx = cacheList.findIndex(e => e.id === newEv.id)
          if (idx !== -1) {
            cacheList[idx] = { ...cacheList[idx], ...formatted }
          } else {
            cacheList.unshift(formatted)
          }
        }
        localStorage.setItem('smartband_raw_events_cache', JSON.stringify(cacheList))
      } catch (err) {
        console.warn('Cache update on event realtime error:', err)
      }

      // Dispatch instant custom event to update active views (DashboardHome, DashboardSchedule) without page reload
      window.dispatchEvent(new CustomEvent('smartband_event_changed', { detail: payload }))
      if (syncBroadcast) {
        try { syncBroadcast.postMessage({ type: 'EVENT_CHANGED', payload: newEv || oldEv }) } catch(e){}
      }

      // If not an insert, availability checking and announcements are skipped
      if (eventType !== 'INSERT' || !newEv) return

      let isMemberFree = false
      let matchDay = ''
      let matchSlot = ''

      if (store.user?.id && newEv.event_date) {
        try {
          const evDate = new Date(newEv.event_date)
          const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
          matchDay = dayNames[evDate.getDay()]
          const hr = evDate.getHours()
          matchSlot = hr < 12 ? 'Morning' : (hr < 18 ? 'Afternoon' : 'Evening')

          const { data } = await supabase
            .from('member_availability')
            .select('is_free')
            .eq('user_id', store.user.id)
            .eq('day_of_week', matchDay)
            .eq('time_slot', matchSlot)
            .maybeSingle()

          if (data && data.is_free === true) {
            isMemberFree = true
          }
        } catch (e) {
          console.warn('Availability check error for new event:', e)
        }
      }

      if (enableBanners.value) {
        uiStore.playChime()
        if (isMemberFree) {
          uiStore.addToast({
            title: `🎯 Gig Matches Your Availability: ${newEv.title}`,
            message: `You marked yourself free on ${matchDay} (${matchSlot}). Please confirm your attendance!`,
            type: 'success',
            duration: 12000
          })
        } else {
          uiStore.addToast({
            title: `🎷 New Event Scheduled: ${newEv.title}`,
            message: `${newEv.event_type || 'Band Gig'} on ${new Date(newEv.event_date).toLocaleDateString()}. Please confirm RSVP.`,
            type: 'info',
            duration: 10000
          })
        }
      }

      if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
        const notifTitle = isMemberFree ? `🎯 Matching Gig: ${newEv.title}` : `🎷 New Event: ${newEv.title}`
        const notifBody = isMemberFree 
          ? `You are free on ${matchDay} (${matchSlot})! Confirm attendance at ${newEv.location}.` 
          : `${newEv.event_type} at ${newEv.location} on ${new Date(newEv.event_date).toLocaleDateString()}`
        
        if ('serviceWorker' in navigator) {
          navigator.serviceWorker.ready.then(reg => {
            reg.showNotification(notifTitle, {
              body: notifBody,
              icon: '/favicon.svg',
              vibrate: [200, 100, 200]
            })
          }).catch(() => {})
        } else {
          try { new Notification(notifTitle, { body: notifBody, icon: '/favicon.svg' }) } catch(e){}
        }
      }
    })
    .subscribe()

  // 3. Supabase Realtime Broadcast Alerts (Immediate RSVP Re-notifications & Registration Sync)
  broadcastSub = supabase.channel('smartband-broadcast-alerts', {
    config: { broadcast: { ack: true } }
  })
    .on('broadcast', { event: 'new_registration' }, () => {
      fetchPendingCount()
    })
    .on('broadcast', { event: 'account_status_changed' }, () => {
      fetchPendingCount()
    })
    .on('broadcast', { event: 'rsvp_reminder' }, (payload) => {
      const p = payload?.payload || payload || {}
      if (enableBanners.value) {
        if (enableAlarms.value) {
          playAlarmSiren(3)
        } else {
          uiStore.playChime()
        }
        uiStore.addToast({
          title: p.title || '🚨 Urgent: RSVP Attendance Confirmation Required',
          message: p.message || 'The Band Secretary requests you confirm attendance for upcoming gigs.',
          type: 'warning',
          duration: 12000
        })
      }

      if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
        const title = p.title || '🚨 RSVP Attendance Reminder'
        const body = p.message || 'Please confirm your attendance for upcoming band events.'
        if ('serviceWorker' in navigator) {
          navigator.serviceWorker.ready.then(reg => {
            reg.showNotification(title, { body, icon: '/favicon.svg', vibrate: [300, 100, 300, 100, 300] })
          }).catch(() => {})
        } else {
          try { new Notification(title, { body, icon: '/favicon.svg' }) } catch(e){}
        }
      }
    })
    .subscribe((status) => {
      console.log('[DashboardLayout] smartband-broadcast-alerts status:', status)
    })

  // 4. Inter-Tab / Local BroadcastChannel Sync
  if ('BroadcastChannel' in window) {
    syncBroadcast = new BroadcastChannel('smartband_live_sync')
    syncBroadcast.onmessage = (e) => {
      if (e.data?.type === 'NEW_REGISTRATION' || e.data?.type === 'ACCOUNT_STATUS_CHANGED') {
        fetchPendingCount()
      }
      if (e.data?.type === 'RSVP_REMINDER_BROADCAST') {
        if (enableBanners.value) {
          if (enableAlarms.value) {
            playAlarmSiren(3)
          } else {
            uiStore.playChime()
          }
          uiStore.addToast({
            title: e.data.title || '🚨 Urgent RSVP Call-to-Action!',
            message: e.data.message || 'The Band Secretary requests attendance confirmation for upcoming gigs.',
            type: 'warning',
            duration: 12000
          })
        }
        if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
          try {
            new Notification('🚨 RSVP Reminder: Confirm Attendance', {
              body: 'The Band Secretary requests you confirm your attendance for upcoming events.',
              icon: '/favicon.svg'
            })
          } catch(e){}
        }
      }
    }
  }

  window.addEventListener('focus', fetchPendingCount)
  setInterval(() => {
    if (typeof document !== 'undefined' && !document.hidden) {
      fetchPendingCount()
    }
  }, 15000)

  // 5. Realtime subscription for current user's profile updates (avatar approvals, role changes, etc.)
  const setupUserProfileSub = (userId) => {
    if (!userId) return
    if (userProfileSub) {
      supabase.removeChannel(userProfileSub)
      userProfileSub = null
    }
    userProfileSub = supabase.channel(`user_profile_${userId}`)
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'profiles',
        filter: `id=eq.${userId}`
      }, payload => {
        if (payload.new) {
          store.profile = payload.new
          store.currentRole = payload.new.role || 'member'
          store.executiveTitle = payload.new.executive_title || null
          try {
            localStorage.setItem('smartband_user_profile_cache', JSON.stringify(payload.new))
          } catch (e) {}
          if (payload.new.profile_picture_status === 'approved' && payload.old?.profile_picture_status === 'pending') {
            uiStore.addToast({
              title: 'Photo Approved! 📸',
              message: 'Your profile picture has been approved by the admin.',
              type: 'success'
            })
          }
        }
      })
      .subscribe()
  }

  if (store.user?.id) {
    setupUserProfileSub(store.user.id)
  }

  watch(() => store.user?.id, (newId) => {
    if (newId) {
      setupUserProfileSub(newId)
    }
  })

  if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
    syncPushSubscription()
  }
})

onUnmounted(() => {
  window.removeEventListener('online', updateNetworkStatus)
  window.removeEventListener('offline', updateNetworkStatus)
  if (callTimeMonitorTimer) clearInterval(callTimeMonitorTimer)
  if (announceSub) supabase.removeChannel(announceSub)
  if (eventsSub) supabase.removeChannel(eventsSub)
  if (broadcastSub) supabase.removeChannel(broadcastSub)
  if (syncBroadcast) syncBroadcast.close()
  if (userProfileSub) supabase.removeChannel(userProfileSub)
})
</script>

<template>
  <div class="min-h-screen bg-[#f8f9fa] dark:bg-[#18191a] text-slate-900 dark:text-neutral-100 flex transition-colors duration-300">
    
    <!-- DESKTOP LEFT NAVIGATION SIDEBAR (Fixed Viewport, Never Scrolls With Page) -->
    <aside class="hidden md:flex md:w-64 lg:w-72 flex-col bg-[#f8f9fa] dark:bg-[#1e1f20] border-r border-slate-200 dark:border-neutral-800 p-5 space-y-6 flex-shrink-0 fixed top-0 left-0 bottom-0 z-30 h-screen overflow-y-auto">
      
      <!-- Brand Logo -->
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class="w-9 h-9 rounded-xl overflow-hidden border border-slate-200 dark:border-neutral-700 bg-white flex-shrink-0 flex items-center justify-center p-0.5 shadow-xs">
            <img src="/band1870logo.jpg" alt="Peñaranda Band 1870" class="w-full h-full object-contain" />
          </div>
          <div>
            <span class="font-bold text-lg tracking-tight text-slate-900 dark:text-white block leading-none">SmartBand</span>
            <span class="text-[10px] text-slate-500 dark:text-neutral-400 font-medium">Band 1870 PWA</span>
          </div>
        </div>

        <!-- Desktop Theme Toggle -->
        <button 
          @click="toggleTheme" 
          type="button"
          class="p-2 rounded-full text-slate-600 dark:text-neutral-300 hover:bg-slate-200/70 dark:hover:bg-neutral-800 transition-colors cursor-pointer min-w-[38px] min-h-[38px] flex items-center justify-center"
          :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
          title="Toggle Light/Dark Theme"
        >
          <Sun v-if="isDark" class="w-4 h-4 text-slate-700" />
          <Moon v-else class="w-4 h-4 text-neutral-300" />
        </button>
      </div>

      <!-- Desktop Sidebar Menu -->
      <nav class="space-y-1 flex-1" aria-label="Desktop Navigation Menu">
        
        <RouterLink 
          to="/dashboard" 
          class="flex items-center px-4 py-3 rounded-full font-medium text-xs transition-colors space-x-3 cursor-pointer min-h-[42px]"
          :class="route.name === 'dashboard-home' 
            ? 'bg-slate-200 text-slate-900 font-semibold dark:bg-[#282a2c] dark:text-white' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#282a2c]/60'"
        >
          <Home class="w-4 h-4 flex-shrink-0" />
          <span>Home Dashboard</span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/schedule" 
          class="flex items-center px-4 py-3 rounded-full font-medium text-xs transition-colors space-x-3 cursor-pointer min-h-[42px]"
          :class="route.name === 'dashboard-schedule' 
            ? 'bg-slate-200 text-slate-900 font-semibold dark:bg-[#282a2c] dark:text-white' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#282a2c]/60'"
        >
          <Calendar class="w-4 h-4 flex-shrink-0" />
          <span>Schedule & Events</span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/members" 
          class="flex items-center px-4 py-3 rounded-full font-medium text-xs transition-colors space-x-3 cursor-pointer min-h-[42px]"
          :class="route.name === 'dashboard-members' 
            ? 'bg-slate-200 text-slate-900 font-semibold dark:bg-[#282a2c] dark:text-white' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#282a2c]/60'"
        >
          <Users class="w-4 h-4 flex-shrink-0" />
          <span>{{ store.isOfficerOrAdmin ? 'Band Directory & Ranks' : 'Band Directory' }}</span>
        </RouterLink>

        <!-- Dynamic Admin / Secretary / Executive Analytics Tab Labeling -->
        <RouterLink 
          v-if="store.isSuperAdmin || store.isSecretaryAdmin || store.isExecutive"
          to="/dashboard/admin" 
          class="flex items-center justify-between px-4 py-3 rounded-full font-medium text-xs transition-colors cursor-pointer min-h-[42px]"
          :class="route.name === 'dashboard-admin' 
            ? 'bg-slate-200 text-slate-900 font-semibold dark:bg-[#282a2c] dark:text-white' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#282a2c]/60'"
        >
          <div class="flex items-center space-x-3">
            <ShieldCheck class="w-4 h-4 flex-shrink-0 text-slate-700 dark:text-neutral-300" />
            <span>{{ store.isSuperAdmin ? 'Admin Operations' : store.isSecretaryAdmin ? 'Band Operations' : 'Executive Analytics' }}</span>
          </div>
          <span v-if="pendingCount > 0 && store.isSuperAdmin" class="px-2 py-0.5 rounded-full bg-slate-900 text-white dark:bg-white dark:text-slate-900 font-semibold text-[10px]">
            {{ pendingCount }}
          </span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/profile" 
          class="flex items-center px-4 py-3 rounded-full font-medium text-xs transition-colors space-x-3 cursor-pointer min-h-[42px]"
          :class="route.name === 'dashboard-profile' 
            ? 'bg-slate-200 text-slate-900 font-semibold dark:bg-[#282a2c] dark:text-white' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#282a2c]/60'"
        >
          <User class="w-4 h-4 flex-shrink-0" />
          <span>My Profile</span>
        </RouterLink>

        <!-- Role & Operational User Guide Modal Trigger -->
        <button 
          @click="showRoleGuideModal = true" 
          type="button"
          class="w-full flex items-center px-4 py-3 rounded-full font-medium text-xs transition-colors space-x-3 cursor-pointer min-h-[42px] text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#282a2c]/60 text-left"
        >
          <HelpCircle class="w-4 h-4 flex-shrink-0 text-slate-500" />
          <span>Role & User Guide</span>
        </button>

      </nav>

      <!-- Desktop PWA Install Banner -->
      <div v-if="!isAppInstalled" class="p-3.5 bg-slate-100 dark:bg-neutral-800/80 border border-slate-200 dark:border-neutral-700 rounded-2xl space-y-2">
        <div class="flex items-center space-x-2 text-slate-800 dark:text-neutral-200 font-semibold text-xs">
          <Download class="w-4 h-4" />
          <span>Install SmartBand App</span>
        </div>
        <p class="text-[11px] text-slate-500 dark:text-neutral-400 leading-tight">Install on your device for instant offline access.</p>
        <button @click="handleInstallPWA" type="button" class="w-full py-2 bg-slate-900 hover:bg-slate-800 dark:bg-neutral-100 dark:hover:bg-white text-white dark:text-slate-900 font-medium text-xs rounded-full cursor-pointer min-h-[38px] transition-colors">
          Install App
        </button>
      </div>

      <!-- Desktop Installed Badge -->
      <div v-else class="p-3 bg-slate-100 dark:bg-neutral-800/80 border border-slate-200 dark:border-neutral-700 rounded-2xl flex items-center space-x-2 text-slate-700 dark:text-neutral-300 font-medium text-xs">
        <CheckCircle class="w-4 h-4 text-emerald-600 dark:text-emerald-400 flex-shrink-0" />
        <span>App Installed & Ready</span>
      </div>

      <!-- User Profile Summary & Sign Out -->
      <div class="pt-4 border-t border-slate-200 dark:border-neutral-800 flex items-center justify-between">
        <div class="flex items-center space-x-2.5 min-w-0 pr-2">
          <div class="w-9 h-9 rounded-full overflow-hidden flex-shrink-0 border border-slate-200 dark:border-neutral-700 shadow-xs">
            <img v-if="store.profile?.profile_picture" 
                 :src="store.profile.profile_picture" 
                 alt="Avatar" 
                 class="w-full h-full object-cover" />
            <div v-else class="w-full h-full bg-slate-700 text-white flex items-center justify-center font-bold text-xs">
              {{ store.profile?.full_name ? store.profile.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB' }}
            </div>
          </div>
          <div class="min-w-0">
            <p class="font-semibold text-xs text-slate-900 dark:text-white truncate">{{ store.profile?.full_name || 'Member' }}</p>
          </div>
        </div>
        <button @click="triggerSignOut" type="button" class="p-2 rounded-full text-slate-500 hover:text-rose-600 hover:bg-slate-100 dark:hover:bg-neutral-800 cursor-pointer min-w-[38px] min-h-[38px] flex items-center justify-center transition-colors" title="Sign Out">
          <LogOut class="w-4 h-4" />
        </button>
      </div>

    </aside>

    <!-- MAIN RESPONSIVE CANVAS AREA (Offset on desktop for fixed sidebar) -->
    <div class="flex-1 min-w-0 min-h-screen flex flex-col w-full md:pl-64 lg:pl-72">
      <div class="flex-1 min-w-0 flex flex-col max-w-6xl mx-auto w-full">
      
      <!-- TOP HEADER (Desktop breadcrumb / Mobile Brand) -->
      <header class="sticky top-0 z-40 bg-[#f8f9fa] dark:bg-[#18191a] border-b border-slate-200 dark:border-neutral-800 px-4 py-3 flex items-center justify-between shadow-xs">
        <div class="flex items-center space-x-2.5">
          <!-- Mobile Brand Logo (Visible only on mobile screens when sidebar is hidden) -->
          <div class="flex items-center space-x-2.5 md:hidden">
            <div class="w-8 h-8 rounded-xl overflow-hidden border border-slate-200 dark:border-neutral-700 bg-white flex items-center justify-center p-0.5 shadow-xs">
              <img src="/band1870logo.jpg" alt="Logo" class="w-full h-full object-contain" />
            </div>
            <span class="font-bold text-base tracking-tight text-slate-900 dark:text-white">SmartBand</span>
          </div>

          <!-- Desktop Page Breadcrumb (Visible only when sidebar is present) -->
          <div class="hidden md:flex items-center space-x-2 text-xs font-medium text-slate-500 dark:text-neutral-400">
            <span class="text-slate-500 dark:text-neutral-400 uppercase tracking-wider">Portal</span>
            <span>/</span>
            <span class="text-slate-900 dark:text-white capitalize font-semibold">{{ route.name ? route.name.toString().replace('dashboard-', '').replace('-', ' ') : 'Dashboard' }}</span>
          </div>
        </div>

        <div class="flex items-center space-x-1 sm:space-x-1.5">
          <!-- Install App Header Trigger (Visible on mobile where sidebar install card is hidden) -->
          <button 
            v-if="!isAppInstalled"
            @click="handleInstallPWA"
            type="button"
            class="md:hidden px-3 py-1.5 rounded-full bg-slate-900 dark:bg-white text-white dark:text-slate-900 font-medium text-xs flex items-center hover:bg-slate-800 transition-colors shadow-xs cursor-pointer min-h-[36px] shrink-0"
            aria-label="Install SmartBand App"
          >
            <Download class="w-3.5 h-3.5 sm:mr-1" />
            <span class="hidden sm:inline">Install</span>
          </button>

          <!-- User Guide & Roles Help Trigger -->
          <button 
            @click="showRoleGuideModal = true" 
            type="button"
            class="p-2 rounded-full text-slate-600 dark:text-neutral-300 hover:bg-slate-200/70 dark:hover:bg-neutral-800 transition-colors min-w-[38px] min-h-[38px] flex items-center justify-center cursor-pointer shrink-0"
            aria-label="Open Role & User Guide"
            title="Role Guide & Operational Manual"
          >
            <HelpCircle class="w-4 h-4" />
          </button>

          <!-- Quick Mobile Theme Switcher (Sun/Moon) -->
          <button 
            @click="toggleTheme" 
            type="button"
            class="p-2 rounded-full text-slate-600 dark:text-neutral-300 hover:bg-slate-200/70 dark:hover:bg-neutral-800 transition-colors min-w-[38px] min-h-[38px] flex items-center justify-center cursor-pointer shrink-0"
            :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
            title="Toggle Light/Dark Theme"
          >
            <Sun v-if="isDark" class="w-4 h-4 text-slate-700" />
            <Moon v-else class="w-4 h-4 text-neutral-300" />
          </button>

          <!-- Notification & Settings Drawer Bell Trigger -->
          <button 
            @click="showSettingsDrawer = true" 
            type="button"
            class="p-2 rounded-full text-slate-600 dark:text-neutral-300 hover:bg-slate-200/70 dark:hover:bg-neutral-800 transition-colors min-w-[38px] min-h-[38px] flex items-center justify-center relative cursor-pointer shrink-0"
            aria-label="Open App Settings & Alerts Drawer"
            title="Open App Settings"
          >
            <Bell class="w-4 h-4" />
            <span v-if="pendingCount > 0" class="absolute top-1.5 right-1.5 w-2 h-2 bg-rose-500 rounded-full"></span>
          </button>
        </div>
      </header>

      <!-- FIRST-TIME USER NOTIFICATION PROMPT BANNER -->
      <Transition name="toast">
        <div 
          v-if="showFirstTimeNotifPrompt"
          class="bg-slate-100 dark:bg-neutral-800/90 text-slate-800 dark:text-neutral-200 px-4 py-2.5 shadow-xs flex items-center justify-between border-b border-slate-200 dark:border-neutral-700 text-xs"
        >
          <div class="flex items-center space-x-2.5 pr-2 min-w-0">
            <Bell class="w-4 h-4 flex-shrink-0 text-slate-600 dark:text-neutral-400" />
            <div class="min-w-0">
              <span class="font-semibold block text-slate-900 dark:text-white">Enable 10–15m Call-Time Alarm?</span>
              <span class="text-[11px] text-slate-500 dark:text-neutral-400 block truncate">Audible siren & notifications for upcoming rehearsals and gigs.</span>
            </div>
          </div>
          <div class="flex items-center space-x-1.5 flex-shrink-0">
            <button 
              @click="requestNotificationPermission" 
              type="button" 
              class="px-3 py-1.5 bg-slate-900 dark:bg-white text-white dark:text-slate-900 font-medium rounded-full shadow-xs text-xs hover:bg-slate-800 cursor-pointer min-h-[32px]"
            >
              Allow
            </button>
            <button 
              @click="dismissFirstTimeNotifPrompt" 
              type="button" 
              class="p-1 text-slate-400 hover:text-slate-600 dark:hover:text-white min-w-[32px] min-h-[32px] flex items-center justify-center cursor-pointer"
              aria-label="Dismiss Notification Prompt"
            >
              <X class="w-4 h-4" />
            </button>
          </div>
        </div>
      </Transition>

      <!-- NETWORK RECONNECT TOAST -->
      <Transition name="toast">
        <div 
          v-if="networkToastMsg"
          class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-sm w-11/12 bg-slate-900 dark:bg-neutral-800 text-white px-4 py-2.5 rounded-full shadow-lg border border-slate-700/80 flex items-center justify-between text-xs font-medium"
        >
          <div class="flex items-center space-x-1.5">
            <CheckCircle class="w-4 h-4 text-emerald-400 flex-shrink-0" />
            <span>{{ networkToastMsg }}</span>
          </div>
        </div>
      </Transition>

      <!-- Main Router Page Body (Generous bottom padding so bottom bar never covers buttons) -->
      <main class="flex-1 p-3.5 sm:p-6 lg:p-8 overflow-y-auto pb-32 md:pb-12">
        <RouterView />
      </main>

      <!-- MOBILE BOTTOM NAVIGATION BAR (Google Material 3 clean flat style) -->
      <nav 
        class="md:hidden fixed bottom-0 left-0 w-full bg-[#f8f9fa] dark:bg-[#1e1f20] border-t border-slate-200 dark:border-neutral-800 shadow-sm pb-safe z-30"
        aria-label="Bottom Navigation Bar"
      >
        <div class="flex justify-around items-center h-16 px-1 max-w-md mx-auto" role="menubar">
          
          <RouterLink 
            to="/dashboard" 
            role="menuitem"
            aria-label="Home Dashboard Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors min-h-[44px]"
            :class="route.name === 'dashboard-home' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400'"
          >
            <div :class="route.name === 'dashboard-home' ? 'px-3.5 py-1 rounded-full bg-slate-200/80 dark:bg-neutral-800' : 'px-3.5 py-1'">
              <Home class="w-5 h-5" :stroke-width="route.name === 'dashboard-home' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5">Home</span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/schedule" 
            role="menuitem"
            aria-label="Events Schedule Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors min-h-[44px]"
            :class="route.name === 'dashboard-schedule' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400'"
          >
            <div :class="route.name === 'dashboard-schedule' ? 'px-3.5 py-1 rounded-full bg-slate-200/80 dark:bg-neutral-800' : 'px-3.5 py-1'">
              <Calendar class="w-5 h-5" :stroke-width="route.name === 'dashboard-schedule' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5">Events</span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/members" 
            role="menuitem"
            aria-label="Band Member Directory Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors min-h-[44px]"
            :class="route.name === 'dashboard-members' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400'"
          >
            <div :class="route.name === 'dashboard-members' ? 'px-3.5 py-1 rounded-full bg-slate-200/80 dark:bg-neutral-800' : 'px-3.5 py-1'">
              <Users class="w-5 h-5" :stroke-width="route.name === 'dashboard-members' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5">Roster</span>
          </RouterLink>

          <RouterLink 
            v-if="store.isSuperAdmin || store.isSecretaryAdmin || store.isExecutive"
            to="/dashboard/admin" 
            role="menuitem"
            aria-label="Admin Operations Hub Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors relative min-h-[44px]"
            :class="route.name === 'dashboard-admin' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400'"
          >
            <div :class="route.name === 'dashboard-admin' ? 'px-3.5 py-1 rounded-full bg-slate-200/80 dark:bg-neutral-800' : 'px-3.5 py-1'">
              <ShieldCheck class="w-5 h-5" :stroke-width="route.name === 'dashboard-admin' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5">{{ store.isSuperAdmin ? 'Admin' : store.isSecretaryAdmin ? 'Operations' : 'Analytics' }}</span>
            <span v-if="pendingCount > 0 && store.isSuperAdmin" class="absolute top-2 right-4 w-2 h-2 bg-rose-500 rounded-full"></span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/profile" 
            role="menuitem"
            aria-label="User Profile Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors min-h-[44px]"
            :class="route.name === 'dashboard-profile' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400'"
          >
            <div :class="route.name === 'dashboard-profile' ? 'px-3.5 py-1 rounded-full bg-slate-200/80 dark:bg-neutral-800' : 'px-3.5 py-1'">
              <User class="w-5 h-5" :stroke-width="route.name === 'dashboard-profile' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5">Profile</span>
          </RouterLink>

        </div>
      </nav>

      </div>
    </div>

    <!-- HIGH-VISIBILITY CALL-TIME ALARM DIALOG (Clean Material 3 Dialog) -->
    <Transition name="toast">
      <div v-if="activeAlarmModal" class="fixed inset-0 bg-black/60 backdrop-blur-xs z-50 flex items-center justify-center p-4">
        <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-center">
          
          <div class="w-14 h-14 rounded-full bg-slate-100 dark:bg-neutral-800 text-slate-800 dark:text-white flex items-center justify-center mx-auto">
            <Volume2 class="w-7 h-7" />
          </div>

          <div>
            <span class="inline-block px-3 py-1 bg-slate-100 dark:bg-neutral-800 text-slate-700 dark:text-neutral-300 text-[11px] font-semibold uppercase rounded-full tracking-wider mb-2">
              Call-Time Alarm
            </span>
            <h2 class="text-xl font-bold text-slate-900 dark:text-white leading-snug">
              {{ activeAlarmModal.title }}
            </h2>
            <p class="text-sm font-semibold text-rose-600 dark:text-rose-400 mt-1 uppercase tracking-wide">
              {{ activeAlarmModal.countdownText }}
            </p>
          </div>

          <div class="bg-slate-50 dark:bg-neutral-900/60 p-3.5 rounded-2xl space-y-1.5 text-xs text-slate-700 dark:text-neutral-300 text-left border border-slate-200/60 dark:border-neutral-800">
            <div class="flex items-center"><Clock class="w-4 h-4 mr-2 text-slate-500" /> Scheduled: {{ activeAlarmModal.timeText }}</div>
            <div class="flex items-center"><MapPin class="w-4 h-4 mr-2 text-slate-500" /> Location: {{ activeAlarmModal.location }}</div>
          </div>

          <button 
            @click="dismissActiveAlarm"
            type="button"
            class="w-full py-3 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:text-slate-900 text-white font-medium text-sm rounded-full shadow-xs cursor-pointer min-h-[46px] transition-colors"
          >
            I Am Ready / Dismiss
          </button>
        </div>
      </div>
    </Transition>

    <!-- APP SETTINGS & NOTIFICATIONS DRAWER MODAL (Clean Google Material 3 Surface) -->
    <div v-if="showSettingsDrawer" class="fixed inset-0 bg-black/50 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-xl text-left">
        
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2 text-slate-800 dark:text-neutral-200">
            <Bell class="w-4 h-4" />
            <h3 class="font-bold text-base text-slate-900 dark:text-white">Settings & Notifications</h3>
          </div>
          <button @click="showSettingsDrawer = false" class="text-slate-400 hover:text-slate-600 dark:hover:text-white min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer"><X class="w-4 h-4" /></button>
        </div>

        <div class="space-y-2.5">
          <!-- Network Sync Badge -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-neutral-900/60 border border-slate-200/60 dark:border-neutral-800">
            <div class="flex items-center space-x-2">
              <Wifi v-if="isOnline" class="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
              <WifiOff v-else class="w-4 h-4 text-rose-500" />
              <span class="text-xs font-medium text-slate-800 dark:text-neutral-200">{{ isOnline ? 'Online Sync Active' : 'Offline Mode' }}</span>
            </div>
            <span class="w-2 h-2 rounded-full" :class="isOnline ? 'bg-emerald-500' : 'bg-rose-500'"></span>
          </div>

          <!-- Audible Alarms Toggle -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-neutral-900/60 border border-slate-200/60 dark:border-neutral-800">
            <div>
              <p class="font-semibold text-xs text-slate-900 dark:text-white">Call-Time Alarm</p>
              <p class="text-[10px] text-slate-500 dark:text-neutral-400">Audible call-time alert</p>
            </div>
            <div class="flex items-center space-x-1.5">
              <button 
                @click="testAlarmTone"
                type="button"
                class="p-2 bg-slate-200/80 dark:bg-neutral-800 hover:bg-slate-300 dark:hover:bg-neutral-700 text-slate-700 dark:text-neutral-300 rounded-full cursor-pointer transition-colors"
                title="Test Alarm"
              >
                <Volume2 class="w-3.5 h-3.5" />
              </button>
              <button 
                @click="toggleAlarms"
                type="button"
                class="px-3 py-1.5 font-medium text-xs rounded-full cursor-pointer min-h-[34px] transition-colors"
                :class="enableAlarms ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900' : 'bg-slate-200 dark:bg-neutral-800 text-slate-700 dark:text-neutral-300'"
              >
                {{ enableAlarms ? 'Enabled' : 'Disabled' }}
              </button>
            </div>
          </div>

          <!-- PWA Install Status in Drawer -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-neutral-900/60 border border-slate-200/60 dark:border-neutral-800">
            <div>
              <p class="font-semibold text-xs text-slate-900 dark:text-white">App Installation</p>
              <p class="text-[10px] text-slate-500 dark:text-neutral-400">
                {{ isAppInstalled ? 'Installed on device' : 'Install for offline launch' }}
              </p>
            </div>
            
            <div v-if="isAppInstalled" class="flex items-center space-x-1 px-3 py-1 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 rounded-full font-medium text-xs">
              <Check class="w-3.5 h-3.5" />
              <span>Installed</span>
            </div>
            
            <button 
              v-else
              @click="handleInstallPWA"
              type="button"
              class="px-3 py-1.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:text-slate-900 text-white font-medium text-xs rounded-full cursor-pointer min-h-[34px]"
            >
              Install
            </button>
          </div>

          <!-- In-App Banners Toggle -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-neutral-900/60 border border-slate-200/60 dark:border-neutral-800">
            <div>
              <p class="font-semibold text-xs text-slate-900 dark:text-white">In-App Banners</p>
              <p class="text-[10px] text-slate-500 dark:text-neutral-400">Visual reminders & chimes</p>
            </div>
            <button 
              @click="toggleBanners"
              type="button"
              class="px-3 py-1.5 font-medium text-xs rounded-full cursor-pointer min-h-[34px] transition-colors"
              :class="enableBanners ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900' : 'bg-slate-200 dark:bg-neutral-800 text-slate-700 dark:text-neutral-300'"
            >
              {{ enableBanners ? 'Enabled' : 'Disabled' }}
            </button>
          </div>

          <!-- Theme Mode Toggle -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-neutral-900/60 border border-slate-200/60 dark:border-neutral-800">
            <div class="flex items-center space-x-1.5">
              <Sun v-if="isDark" class="w-4 h-4 text-slate-400" />
              <Moon v-else class="w-4 h-4 text-slate-700" />
              <span class="text-xs font-medium text-slate-800 dark:text-neutral-200">Theme</span>
            </div>
            <button 
              @click="toggleTheme" 
              type="button"
              class="px-3 py-1.5 bg-slate-200 dark:bg-neutral-800 text-slate-800 dark:text-neutral-200 font-medium text-xs rounded-full cursor-pointer min-h-[34px]"
            >
              {{ isDark ? 'Dark' : 'Light' }}
            </button>
          </div>

          <!-- View Terms & Conditions -->
          <button 
            @click="showTermsModal = true"
            type="button"
            class="w-full flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-neutral-900/60 border border-slate-200/60 dark:border-neutral-800 text-xs font-medium text-slate-700 dark:text-neutral-300 min-h-[42px] cursor-pointer"
          >
            <span class="flex items-center"><FileText class="w-4 h-4 mr-2 text-slate-500" /> View Terms & Conditions</span>
            <span class="text-slate-400">→</span>
          </button>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800 pb-1 flex justify-end">
          <button @click="showSettingsDrawer = false" type="button" class="py-2 px-5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:text-slate-900 font-medium text-xs text-white rounded-full min-h-[38px] cursor-pointer">
            Close
          </button>
        </div>

      </div>
    </div>

    <!-- TERMS & CONDITIONS MODAL (Clean Google Material 3 Dialog) -->
    <div v-if="showTermsModal" class="fixed inset-0 bg-black/50 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-xl text-left max-h-[80vh] flex flex-col">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2 text-slate-800 dark:text-neutral-200">
            <FileText class="w-4 h-4" />
            <h3 class="font-bold text-base text-slate-900 dark:text-white">Terms & Conditions</h3>
          </div>
          <button @click="showTermsModal = false" class="text-slate-400 hover:text-slate-600 dark:hover:text-white min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer"><X class="w-4 h-4" /></button>
        </div>

        <div class="overflow-y-auto flex-1 text-xs text-slate-600 dark:text-neutral-300 space-y-3.5 pr-2 leading-relaxed font-normal">
          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 1: Master List Verification Requirement</h4>
            <p>All sign-ups are provisional until physically verified by the IT Super Admin against the official municipal band registry.</p>
          </div>

          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 2: Attendance & RSVP Reliability Scoring</h4>
            <p>RSVPing "I Will Attend" creates an operational commitment for gig planning. Unexcused absences or sudden cancellations directly impact your personal Reliability Score (%).</p>
          </div>

          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 3: Call-Time Punctuality & Alert Protocols</h4>
            <p>Musicians must adhere to designated call times for rehearsals, parades, funeral services, and concerts. The in-app 10–15m call-time alarms serve as operational notifications.</p>
          </div>

          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 4: Band Property & Instrument Care</h4>
            <p>Members issued municipal band instruments, uniforms, or sheet music folios are strictly responsible for their maintenance, safekeeping, and prompt return upon request.</p>
          </div>

          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 5: Data Privacy & Security</h4>
            <p>Member contact numbers and personal birth dates are protected under Row Level Security (RLS) and will never be exposed to public directory views.</p>
          </div>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800">
          <button @click="showTermsModal = false" type="button" class="w-full py-2.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:text-slate-900 font-medium text-xs text-white rounded-full shadow-xs min-h-[40px] cursor-pointer transition-colors">
            Close
          </button>
        </div>
      </div>
    </div>

    <!-- COMPREHENSIVE ROLE & OPERATIONAL USER GUIDE MODAL (Clean Google Material 3 Dialog) -->
    <div v-if="showRoleGuideModal" class="fixed inset-0 bg-black/50 backdrop-blur-xs z-50 flex items-center justify-center p-3 sm:p-4">
      <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-neutral-800 rounded-3xl p-5 sm:p-6 max-w-xl w-full space-y-4 shadow-xl text-left max-h-[90vh] flex flex-col">
        
        <!-- Modal Header -->
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2.5">
            <div class="p-2 rounded-full bg-slate-100 dark:bg-neutral-800 text-slate-700 dark:text-neutral-300">
              <BookOpen class="w-4 h-4" />
            </div>
            <div>
              <h3 class="font-bold text-base text-slate-900 dark:text-white leading-tight">SmartBand User & Role Guide</h3>
              <p class="text-[11px] text-slate-500 dark:text-neutral-400">Operational responsibilities, turnout rules, and quick manuals</p>
            </div>
          </div>
          <button @click="showRoleGuideModal = false" class="text-slate-400 hover:text-slate-600 dark:hover:text-white min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer">
            <X class="w-4 h-4" />
          </button>
        </div>

        <!-- Navigation Tabs -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-1 p-1 bg-slate-100 dark:bg-neutral-800 rounded-full text-xs font-medium shrink-0">
          <button 
            @click="activeGuideTab = 'roles'"
            type="button"
            class="py-1.5 px-2 rounded-full text-center transition-all cursor-pointer min-h-[32px]"
            :class="activeGuideTab === 'roles' ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
          >
            Role Powers
          </button>
          <button 
            @click="activeGuideTab = 'attendance'"
            type="button"
            class="py-1.5 px-2 rounded-full text-center transition-all cursor-pointer min-h-[32px]"
            :class="activeGuideTab === 'attendance' ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
          >
            Turnout Math
          </button>
          <button 
            @click="activeGuideTab = 'availability'"
            type="button"
            class="py-1.5 px-2 rounded-full text-center transition-all cursor-pointer min-h-[32px]"
            :class="activeGuideTab === 'availability' ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
          >
            Availability
          </button>
          <button 
            @click="activeGuideTab = 'pwa'"
            type="button"
            class="py-1.5 px-2 rounded-full text-center transition-all cursor-pointer min-h-[32px]"
            :class="activeGuideTab === 'pwa' ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
          >
            PWA & Offline
          </button>
        </div>

        <!-- Tab Body (Scrollable) -->
        <div class="flex-1 overflow-y-auto space-y-3 pr-1 text-xs text-slate-600 dark:text-neutral-300 leading-relaxed">
          
          <!-- TAB 1: ROLES & RESPONSIBILITIES -->
          <div v-if="activeGuideTab === 'roles'" class="space-y-3">
            <div class="p-3.5 bg-slate-50 dark:bg-[#27272a]/60 rounded-2xl border border-slate-200 dark:border-neutral-700/80 space-y-1.5">
              <div class="flex items-center space-x-2">
                <span class="px-2 py-0.5 rounded bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-400 font-black text-[10px] uppercase">Musician</span>
                <h4 class="font-black text-slate-900 dark:text-white text-sm">Regular Band Member</h4>
              </div>
              <ul class="list-disc list-inside space-y-1 text-[11px] text-slate-500 dark:text-neutral-400">
                <li>RSVP to upcoming gigs and rehearsals (Attending or Declined).</li>
                <li>Maintain your 7-day recurring weekly availability in <strong>My Profile</strong>.</li>
                <li>Receive automated call-time alarms 10–15 minutes before rehearsals.</li>
                <li>Maintain a high Reliability Score (100% baseline).</li>
              </ul>
            </div>

            <div class="p-3.5 bg-slate-50 dark:bg-[#27272a]/60 rounded-2xl border border-slate-200 dark:border-neutral-700/80 space-y-1.5">
              <div class="flex items-center space-x-2">
                <span class="px-2 py-0.5 rounded bg-amber-100 dark:bg-amber-950/60 text-amber-700 dark:text-amber-400 font-black text-[10px] uppercase">Secretary</span>
                <h4 class="font-black text-slate-900 dark:text-white text-sm">Band Secretary</h4>
              </div>
              <ul class="list-disc list-inside space-y-1 text-[11px] text-slate-500 dark:text-neutral-400">
                <li>Schedule and announce new band rehearsals, civic parades, and feast processions.</li>
                <li>Conduct live roll-calls with the <strong>Roll Call Log</strong> (mark Present, Absent, or Excused).</li>
                <li>Use <strong>Check Member Availability</strong> to see who is free for upcoming days and sections.</li>
                <li>Broadcast urgent RSVP reminder alerts to unconfirmed musicians.</li>
              </ul>
            </div>

            <div class="p-3.5 bg-slate-50 dark:bg-[#27272a]/60 rounded-2xl border border-slate-200 dark:border-neutral-700/80 space-y-1.5">
              <div class="flex items-center space-x-2">
                <span class="px-2 py-0.5 rounded bg-purple-100 dark:bg-purple-950/60 text-purple-700 dark:text-purple-400 font-black text-[10px] uppercase">Executive</span>
                <h4 class="font-black text-slate-900 dark:text-white text-sm">President, Conductor & Board</h4>
              </div>
              <ul class="list-disc list-inside space-y-1 text-[11px] text-slate-500 dark:text-neutral-400">
                <li>Inspect roster-wide turnout analytics and section performance (Woodwinds, Brass, Percussion).</li>
                <li>Review the <strong>Musician Commitment Matrix</strong> to identify high flake risk members.</li>
                <li>Sort members by most no-shows or lowest reliability to resolve lineup bottlenecks.</li>
              </ul>
            </div>

            <div class="p-3.5 bg-slate-50 dark:bg-[#27272a]/60 rounded-2xl border border-slate-200 dark:border-neutral-700/80 space-y-1.5">
              <div class="flex items-center space-x-2">
                <span class="px-2 py-0.5 rounded bg-rose-100 dark:bg-rose-950/60 text-rose-700 dark:text-rose-400 font-black text-[10px] uppercase">Super Admin</span>
                <h4 class="font-black text-slate-900 dark:text-white text-sm">IT Super Admin</h4>
              </div>
              <ul class="list-disc list-inside space-y-1 text-[11px] text-slate-500 dark:text-neutral-400">
                <li>Approve or decline new member account registrations and verify identity.</li>
                <li>Moderate profile avatar photo uploads.</li>
                <li>Promote musicians to appointed officer posts (Band Secretary, Conductor, etc.).</li>
                <li>Generate and directly download official standardized PDF reports for municipal review.</li>
              </ul>
            </div>
          </div>

          <!-- TAB 2: TURNOUT MATH & FLAKE DETECTION -->
          <div v-else-if="activeGuideTab === 'attendance'" class="space-y-3">
            <div class="p-4 bg-blue-50/50 dark:bg-blue-950/20 rounded-2xl border border-blue-200/80 dark:border-blue-900/40 space-y-2">
              <h4 class="font-black text-slate-900 dark:text-white text-sm">How Attendance Scoring Works</h4>
              <p class="text-[11px]">
                Every member begins with a <strong>100% Reliability Score</strong>. Reliability reflects follow-through on commitments.
              </p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              <div class="p-3 bg-slate-50 dark:bg-[#27272a] rounded-xl border border-slate-200 dark:border-neutral-700 space-y-1">
                <div class="flex items-center space-x-1.5 text-emerald-600 dark:text-emerald-400 font-black text-xs">
                  <CheckCircle class="w-4 h-4" />
                  <span>Present</span>
                </div>
                <p class="text-[11px] text-slate-500 dark:text-neutral-400">Musician confirmed attending and showed up to perform. Positive follow-through recorded.</p>
              </div>

              <div class="p-3 bg-slate-50 dark:bg-[#27272a] rounded-xl border border-slate-200 dark:border-neutral-700 space-y-1">
                <div class="flex items-center space-x-1.5 text-blue-600 dark:text-blue-400 font-black text-xs">
                  <Check class="w-4 h-4" />
                  <span>Declined in Advance</span>
                </div>
                <p class="text-[11px] text-slate-500 dark:text-neutral-400"><strong>0% penalty!</strong> Declining early allows section leaders to find instrument substitutes in time.</p>
              </div>

              <div class="p-3 bg-slate-50 dark:bg-[#27272a] rounded-xl border border-slate-200 dark:border-neutral-700 space-y-1">
                <div class="flex items-center space-x-1.5 text-rose-600 dark:text-rose-400 font-black text-xs">
                  <AlertCircle class="w-4 h-4" />
                  <span>Unexcused No-Show (Flake)</span>
                </div>
                <p class="text-[11px] text-slate-500 dark:text-neutral-400">Musician RSVP'd "Attending" but failed to show up without prior notice. Applies a <strong>-10% Reliability penalty</strong>.</p>
              </div>

              <div class="p-3 bg-slate-50 dark:bg-[#27272a] rounded-xl border border-slate-200 dark:border-neutral-700 space-y-1">
                <div class="flex items-center space-x-1.5 text-slate-600 dark:text-neutral-300 font-black text-xs">
                  <ShieldCheck class="w-4 h-4 text-purple-500" />
                  <span>Excused Absence</span>
                </div>
                <p class="text-[11px] text-slate-500 dark:text-neutral-400">Valid medical emergency or documented prior notice granted by Band Secretary. <strong>0% penalty</strong>.</p>
              </div>
            </div>
          </div>

          <!-- TAB 3: AVAILABILITY RULES -->
          <div v-else-if="activeGuideTab === 'availability'" class="space-y-3">
            <div class="p-4 bg-slate-50 dark:bg-[#27272a] rounded-2xl border border-slate-200 dark:border-neutral-700 space-y-2">
              <h4 class="font-black text-slate-900 dark:text-white text-sm">Weekly Recurring Grid vs Events</h4>
              <p class="text-[11px] text-slate-500 dark:text-neutral-400">
                In <strong>My Profile > Availability Grid</strong>, musicians configure their regular 7-day routine (Monday–Sunday, with Morning, Afternoon, and Evening slots).
              </p>
              <p class="text-[11px] text-slate-500 dark:text-neutral-400">
                When Secretary or Admin creates a new gig, the system cross-references this routine and notifies available musicians automatically!
              </p>
            </div>

            <div class="p-3.5 bg-amber-500/10 border border-amber-500/30 rounded-2xl space-y-1 text-amber-800 dark:text-amber-300">
              <h5 class="font-bold text-xs flex items-center">
                <AlertTriangle class="w-3.5 h-3.5 mr-1" /> Past Dates in Availability Checker
              </h5>
              <p class="text-[11px]">
                In the Secretary/Admin availability checker, earlier weekdays that have already passed in the current week are disabled and greyed out to prevent querying historical days.
              </p>
            </div>
          </div>

          <!-- TAB 4: PWA & OFFLINE -->
          <div v-else-if="activeGuideTab === 'pwa'" class="space-y-3">
            <div class="p-4 bg-slate-50 dark:bg-[#27272a] rounded-2xl border border-slate-200 dark:border-neutral-700 space-y-2">
              <h4 class="font-black text-slate-900 dark:text-white text-sm">Install as a Native App</h4>
              <p class="text-[11px] text-slate-500 dark:text-neutral-400">
                SmartBand is a certified Progressive Web App (PWA). You can install it on your Android phone, iPhone, iPad, Windows PC, or Mac.
              </p>
              <ul class="list-disc list-inside space-y-1 text-[11px] text-slate-500 dark:text-neutral-400 pt-1">
                <li><strong>Chrome / Edge (PC/Mac/Android):</strong> Tap "Install App" in the top bar or click the install icon in your address bar.</li>
                <li><strong>Safari (iOS / iPhone):</strong> Tap the <em>Share</em> button (square with arrow) → tap <em>Add to Home Screen</em>.</li>
              </ul>
            </div>

            <div class="p-3.5 bg-emerald-500/10 border border-emerald-500/30 rounded-2xl space-y-1 text-emerald-800 dark:text-emerald-300">
              <h5 class="font-bold text-xs flex items-center">
                <CheckCircle class="w-3.5 h-3.5 mr-1" /> Offline Access
              </h5>
              <p class="text-[11px]">
                Once installed, schedules, rosters, and emergency alarms remain active even when marching in remote parade routes without cellular reception.
              </p>
            </div>
          </div>

        </div>

        <!-- Footer -->
        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800">
          <button @click="showRoleGuideModal = false" type="button" class="w-full py-2.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:text-slate-900 font-medium text-xs text-white rounded-full shadow-xs min-h-[40px] cursor-pointer transition-colors">
            Close Guide
          </button>
        </div>

      </div>
    </div>

    <!-- SIGN OUT CONFIRMATION MODAL (Clean Google Material 3 Dialog) -->
    <div v-if="showSignOutModal" class="fixed inset-0 bg-black/50 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-xl text-center">
        <div class="w-12 h-12 rounded-full bg-slate-100 dark:bg-neutral-800 flex items-center justify-center mx-auto text-slate-700 dark:text-neutral-300">
          <LogOut class="w-5 h-5" />
        </div>
        <div class="space-y-1">
          <h3 class="font-bold text-base text-slate-900 dark:text-white">Sign Out of SmartBand?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 font-normal">Are you sure you want to sign out? You will need to log back in to access event schedules and receive operational alarms.</p>
        </div>
        <div class="grid grid-cols-2 gap-2.5 pt-2">
          <button 
            @click="showSignOutModal = false" 
            type="button" 
            class="py-2.5 px-4 bg-slate-100 hover:bg-slate-200 dark:bg-neutral-800 dark:hover:bg-neutral-700 text-slate-700 dark:text-neutral-200 font-medium text-xs rounded-full min-h-[40px] cursor-pointer transition-colors"
          >
            Cancel
          </button>
          <button 
            @click="handleSignOut" 
            type="button" 
            class="py-2.5 px-4 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:text-slate-900 text-white font-medium text-xs rounded-full shadow-xs min-h-[40px] cursor-pointer transition-colors"
          >
            Sign Out
          </button>
        </div>
      </div>
    </div>

  </div>
</template>

<style scoped>
.pb-safe {
  padding-bottom: env(safe-area-inset-bottom);
}
</style>
