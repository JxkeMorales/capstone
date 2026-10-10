<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { RouterView, RouterLink, useRoute } from 'vue-router'
import { Home, Calendar, User, Sun, Moon, Music, Users, ShieldCheck, Download, Wifi, WifiOff, LogOut, Bell, BellOff, FileText, X, CheckCircle, AlertCircle, Check, Volume2, AlertTriangle, Clock, MapPin, HelpCircle, BookOpen, ChevronRight, Sparkles, Award } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useUIStore } from '@/stores/ui'
import { useRouter } from 'vue-router'
import { supabase } from '@/supabase'
import { sendPushNotification } from '@/utils/push'

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

// M3 Dynamic View Title & Role Badges
const currentViewTitle = computed(() => {
  switch (route.name) {
    case 'dashboard-home': return 'Dashboard'
    case 'dashboard-schedule': return 'Schedule & Gigs'
    case 'dashboard-members': return store.isOfficerOrAdmin ? 'Band Directory & Ranks' : 'Band Directory'
    case 'dashboard-leaderboard': return 'Reliability & Ranks'
    case 'dashboard-profile': return 'My Profile'
    case 'dashboard-admin': return store.isSuperAdmin ? 'Admin Operations' : store.isSecretaryAdmin ? 'Band Operations' : 'Executive Analytics'
    default: return 'Portal'
  }
})

const currentRoleBadge = computed(() => {
  if (!store.currentRole) return 'Musician'
  if (store.currentRole === 'super_admin') return 'IT Super Admin'
  if (store.currentRole === 'secretary_admin') return 'Band Secretary'
  if (store.currentRole === 'executive') return 'Executive'
  if (store.currentRole === 'section_leader') return 'Section Leader'
  return 'Musician'
})

// Pre-Event Call-Time Alarm Engine State
let callTimeMonitorTimer = null
let pendingCountTimer = null
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
    // Open the visual step-by-step installation guide
    activeGuideTab.value = 'pwa'
    showRoleGuideModal.value = true
    uiStore.addToast({ 
      title: 'Manual Install Instructions', 
      message: 'Follow the on-screen steps for your browser (Android Menu ⋮ or iOS Share).', 
      type: 'info', 
      duration: 6000 
    })
    return
  }
  try {
    prompt.prompt()
    const { outcome } = await prompt.userChoice
    if (outcome === 'accepted') {
      showInstallBanner.value = false
      isAppInstalled.value = true
      uiStore.addToast({ title: 'Installing SmartBand', message: 'App is being added to your home screen!', type: 'success' })
    }
  } catch (err) {
    console.warn('[PWA Install Prompt Error]', err)
    activeGuideTab.value = 'pwa'
    showRoleGuideModal.value = true
  } finally {
    deferredPrompt.value = null
    window.deferredPrompt = null
  }
}

// NORMAL, PLEASANT iOS NOTIFICATION CHIME SYNTHESIZER
const playAlarmSiren = (durationSeconds = 5) => {
  uiStore.playIOSNotificationSound()
  if (navigator.vibrate) {
    navigator.vibrate([100, 50, 100])
  }
}

const testAlarmTone = () => {
  playAlarmSiren()
  showNetworkToast('🔊 Playing iOS notification chime...')
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

const isTestingPush = ref(false)
const testBackgroundPush = async () => {
  if (isTestingPush.value) return
  isTestingPush.value = true
  try {
    uiStore.playIOSNotificationSound()
    uiStore.addToast({
      title: 'Testing Push Notification...',
      message: 'Dispatching background test push to your registered device.',
      type: 'info',
      duration: 3500
    })

    // 1. Direct browser local service worker notification test
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.ready.then(reg => {
        reg.showNotification('🎷 Peñaranda Band 1870 (Local Test)', {
          body: 'System notifications are active on this device!',
          icon: '/favicon.svg',
          badge: '/favicon.svg',
          vibrate: [150, 80, 150]
        })
      }).catch(() => {})
    }

    // 2. Remote background Web Push through serverless function
    await sendPushNotification({
      title: '🎷 Peñaranda Band 1870 (Background Test)',
      message: 'Background push active! You will receive alerts even when this app is closed.',
      url: '/dashboard'
    })
  } catch (err) {
    console.warn('Test push notice:', err)
  } finally {
    isTestingPush.value = false
  }
}

const syncPushSubscription = async (forceRetry = false) => {
  if (!store.user) return
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return

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
        console.warn('[Push Manager Subscribe Notice]:', subErr)
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
        console.warn('[Push Subscriptions Save Notice]:', error)
      } else {
        console.log('[Push] Device subscription synchronized with server')
      }
    }
  } catch(e) {
    console.warn('[Push Sync Catch]:', e)
  }
}

const requestNotificationPermission = async () => {
  if (!('Notification' in window)) {
    uiStore.addToast({ title: 'Unsupported', message: 'Browser push notifications are not supported on this device. Using in-app banners.', type: 'warning' })
    return
  }

  try {
    const result = await Notification.requestPermission()
    notificationPermission.value = result
    showFirstTimeNotifPrompt.value = false

    if (result === 'granted') {
      uiStore.playIOSNotificationSound()
      uiStore.addToast({
        title: '🔔 Push Notifications Active!',
        message: 'You will receive alerts for gigs, call-times, and rehearsals even when the app is closed.',
        type: 'success',
        duration: 4500
      })
      await syncPushSubscription(true)
      checkUpcomingCallTimes()

      // Show immediate native system confirmation notification
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.ready.then(reg => {
          reg.showNotification('🎷 Peñaranda Band 1870', {
            body: 'Background notifications enabled! You will stay informed even when the app is closed.',
            icon: '/favicon.svg',
            badge: '/favicon.svg',
            vibrate: [150, 80, 150]
          })
        }).catch(() => {})
      }
    } else if (result === 'denied') {
      uiStore.addToast({
        title: 'Notifications Blocked',
        message: 'Click the tune/padlock icon in your browser address bar to allow notifications.',
        type: 'warning',
        duration: 6000
      })
    }
  } catch (err) {
    console.error('Notification permission request error:', err)
  }
}

const dismissFirstTimeNotifPrompt = () => {
  showFirstTimeNotifPrompt.value = false
  // Snooze for 24 hours instead of dismissing permanently
  localStorage.setItem('smartband_notif_snooze_until', (Date.now() + 24 * 60 * 60 * 1000).toString())
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

  // Notification Permission & Push Sync Check
  localStorage.removeItem('smartband_notif_prompt_dismissed') // Remove legacy key so users are properly asked
  const snoozeUntil = parseInt(localStorage.getItem('smartband_notif_snooze_until') || '0', 10)
  if (typeof Notification !== 'undefined') {
    notificationPermission.value = Notification.permission
    if (Notification.permission === 'default' && Date.now() > snoozeUntil) {
      showFirstTimeNotifPrompt.value = true
    } else if (Notification.permission === 'granted') {
      syncPushSubscription()
    }
  }

  fetchPendingCount()

  checkUpcomingCallTimes()
  callTimeMonitorTimer = setInterval(checkUpcomingCallTimes, 30000)

  let lastRsvpAlertTimestamp = 0

  // 1. Realtime subscription for new announcements
  announceSub = supabase.channel('public:announcements')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'announcements' }, payload => {
      const isUrgent = payload.new?.category?.toLowerCase().includes('urgent') || payload.new?.title?.toLowerCase().includes('urgent')
      // Prevent duplicate announcement toast if an RSVP alert was already triggered right now
      if (isUrgent && Date.now() - lastRsvpAlertTimestamp < 15000) {
        return
      }
      if (enableBanners.value) {
        uiStore.playIOSNotificationSound()
        uiStore.addToast({
          title: `📢 ${payload.new.title}`,
          message: payload.new.content || payload.new.category || 'Band Update',
          type: isUrgent ? 'warning' : 'info',
          duration: 4500
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
      // If current user sent this alert, do not show reminder to themselves
      if (p.senderId && store.user?.id && p.senderId === store.user.id) {
        return
      }
      // Debounce duplicate broadcasts within 15 seconds
      if (Date.now() - lastRsvpAlertTimestamp < 15000) {
        return
      }
      lastRsvpAlertTimestamp = Date.now()

      if (enableBanners.value) {
        uiStore.playIOSNotificationSound()
        uiStore.addToast({
          title: p.title || '🚨 Urgent: RSVP Attendance Confirmation Required',
          message: p.message || 'The Band Secretary requests you confirm attendance for upcoming gigs.',
          type: 'warning',
          duration: 4500
        })
      }

      if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
        const title = p.title || '🚨 RSVP Attendance Reminder'
        const body = p.message || 'Please confirm your attendance for upcoming band events.'
        if ('serviceWorker' in navigator) {
          navigator.serviceWorker.ready.then(reg => {
            reg.showNotification(title, { body, icon: '/favicon.svg', vibrate: [100, 50, 100] })
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
        if (e.data?.senderId && store.user?.id && e.data.senderId === store.user.id) {
          return
        }
        if (Date.now() - lastRsvpAlertTimestamp < 15000) {
          return
        }
        lastRsvpAlertTimestamp = Date.now()

        if (enableBanners.value) {
          uiStore.playIOSNotificationSound()
          uiStore.addToast({
            title: e.data.title || '🚨 Urgent RSVP Call-to-Action!',
            message: e.data.message || 'The Band Secretary requests attendance confirmation for upcoming gigs.',
            type: 'warning',
            duration: 4500
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
  pendingCountTimer = setInterval(() => {
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
  window.removeEventListener('focus', fetchPendingCount)
  window.removeEventListener('online', updateNetworkStatus)
  window.removeEventListener('offline', updateNetworkStatus)
  if (pendingCountTimer) clearInterval(pendingCountTimer)
  if (callTimeMonitorTimer) clearInterval(callTimeMonitorTimer)
  if (announceSub) supabase.removeChannel(announceSub)
  if (eventsSub) supabase.removeChannel(eventsSub)
  if (broadcastSub) supabase.removeChannel(broadcastSub)
  if (syncBroadcast) syncBroadcast.close()
  if (userProfileSub) supabase.removeChannel(userProfileSub)
})
</script>

<template>
  <!-- Skip to main content link for keyboard navigation (WCAG 2.4.1 Bypass Blocks) -->
  <a 
    href="#main-content" 
    class="sr-only focus:not-sr-only focus:fixed focus:top-3 focus:left-3 focus:z-[200] focus:px-4 focus:py-2.5 focus:bg-amber-500 focus:text-slate-950 focus:font-semibold focus:rounded-xl focus:shadow-xl focus:outline-none"
  >
    Skip to main content
  </a>

  <div class="min-h-dvh bg-[#f8fafc] dark:bg-[#121214] text-slate-900 dark:text-neutral-100 flex transition-colors duration-200">
    
    <!-- 1. TABLET NAVIGATION RAIL (600px - 1024px: Fixed 72px Left Rail, Table 8) -->
    <aside 
      class="hidden sm:flex lg:hidden w-[72px] flex-col items-center justify-between bg-[#f8fafc] dark:bg-[#1e1f20] border-r border-slate-200 dark:border-[#2d3035] py-4 flex-shrink-0 fixed top-0 left-0 bottom-0 z-30 h-screen select-none"
      aria-label="Tablet Navigation Rail"
    >
      <!-- Top Rail Brand Icon -->
      <div class="flex flex-col items-center space-y-4">
        <div class="w-10 h-10 rounded-2xl overflow-hidden border border-slate-200 dark:border-neutral-700 bg-white flex items-center justify-center p-1 shadow-xs">
          <img src="/band1870logo.jpg" alt="Logo" width="40" height="40" class="w-full h-full object-contain" />
        </div>

        <!-- Rail Navigation Items Stack -->
        <nav class="flex flex-col items-center space-y-3 pt-2" aria-label="Rail Menu">
          
          <RouterLink 
            to="/dashboard" 
            class="flex flex-col items-center justify-center min-w-[48px] min-h-[48px] p-1.5 rounded-2xl transition-colors cursor-pointer group"
            :class="route.name === 'dashboard-home' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
            title="Home Dashboard"
          >
            <div :class="route.name === 'dashboard-home' ? 'px-3 py-1 rounded-full bg-slate-200 dark:bg-[#282a2c]' : 'px-3 py-1'">
              <Home class="w-5 h-5" :stroke-width="route.name === 'dashboard-home' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5 tracking-tight">Home</span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/schedule" 
            class="flex flex-col items-center justify-center min-w-[48px] min-h-[48px] p-1.5 rounded-2xl transition-colors cursor-pointer group"
            :class="route.name === 'dashboard-schedule' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
            title="Schedule & Events"
          >
            <div :class="route.name === 'dashboard-schedule' ? 'px-3 py-1 rounded-full bg-slate-200 dark:bg-[#282a2c]' : 'px-3 py-1'">
              <Calendar class="w-5 h-5" :stroke-width="route.name === 'dashboard-schedule' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5 tracking-tight">Events</span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/members" 
            class="flex flex-col items-center justify-center min-w-[48px] min-h-[48px] p-1.5 rounded-2xl transition-colors cursor-pointer group"
            :class="route.name === 'dashboard-members' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
            title="Band Directory"
          >
            <div :class="route.name === 'dashboard-members' ? 'px-3 py-1 rounded-full bg-slate-200 dark:bg-[#282a2c]' : 'px-3 py-1'">
              <Users class="w-5 h-5" :stroke-width="route.name === 'dashboard-members' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5 tracking-tight">Roster</span>
          </RouterLink>

          <RouterLink 
            v-if="store.isSuperAdmin || store.isSecretaryAdmin || store.isExecutive"
            to="/dashboard/admin" 
            class="flex flex-col items-center justify-center min-w-[48px] min-h-[48px] p-1.5 rounded-2xl transition-colors cursor-pointer group relative"
            :class="route.name === 'dashboard-admin' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
            :title="store.isSuperAdmin ? 'Admin Operations' : store.isSecretaryAdmin ? 'Band Operations' : 'Executive Analytics'"
          >
            <div :class="route.name === 'dashboard-admin' ? 'px-3 py-1 rounded-full bg-slate-200 dark:bg-[#282a2c]' : 'px-3 py-1'">
              <ShieldCheck class="w-5 h-5" :stroke-width="route.name === 'dashboard-admin' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5 tracking-tight">{{ store.isSuperAdmin ? 'Admin' : 'Ops' }}</span>
            <span v-if="pendingCount > 0 && store.isSuperAdmin" class="absolute top-1 right-2 w-2 h-2 bg-rose-500 rounded-full"></span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/profile" 
            class="flex flex-col items-center justify-center min-w-[48px] min-h-[48px] p-1.5 rounded-2xl transition-colors cursor-pointer group"
            :class="route.name === 'dashboard-profile' ? 'text-slate-900 dark:text-white font-semibold' : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
            title="My Profile"
          >
            <div :class="route.name === 'dashboard-profile' ? 'px-3 py-1 rounded-full bg-slate-200 dark:bg-[#282a2c]' : 'px-3 py-1'">
              <User class="w-5 h-5" :stroke-width="route.name === 'dashboard-profile' ? 2.5 : 2" />
            </div>
            <span class="text-[10px] mt-0.5 tracking-tight">Profile</span>
          </RouterLink>

        </nav>
      </div>

      <!-- Bottom Rail Actions (Theme Toggle & Sign Out) -->
      <div class="flex flex-col items-center space-y-2 pt-2 border-t border-slate-200 dark:border-[#2d3035] w-full">
        <button 
          @click="toggleTheme" 
          type="button"
          class="min-w-[48px] min-h-[48px] rounded-full text-slate-600 dark:text-neutral-300 hover:bg-slate-200/70 dark:hover:bg-neutral-800 flex items-center justify-center cursor-pointer transition-colors"
          :title="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
          aria-label="Toggle Theme"
        >
          <Sun v-if="isDark" class="w-5 h-5 text-slate-700" />
          <Moon v-else class="w-5 h-5 text-neutral-300" />
        </button>

        <button 
          @click="triggerSignOut" 
          type="button" 
          class="min-w-[48px] min-h-[48px] rounded-full text-slate-500 hover:text-rose-600 hover:bg-slate-100 dark:hover:bg-neutral-800 flex items-center justify-center cursor-pointer transition-colors"
          title="Sign Out"
          aria-label="Sign Out"
        >
          <LogOut class="w-5 h-5" />
        </button>
      </div>
    </aside>

    <!-- 2. DESKTOP LEFT NAVIGATION DRAWER (> 1024px: Fixed 260px - 280px Drawer, Table 8) -->
    <aside 
      class="hidden lg:flex lg:w-64 xl:w-72 flex-col bg-[#f8fafc] dark:bg-[#1e1f20] border-r border-slate-200/60 dark:border-white/[0.05] p-5 space-y-5 flex-shrink-0 fixed top-0 left-0 bottom-0 z-30 h-screen overflow-y-auto select-none"
      aria-label="Desktop Navigation Drawer"
    >
      <!-- Brand Logo & Title -->
      <div class="flex items-center space-x-3 pb-3 border-b border-slate-200/60 dark:border-white/[0.05]">
        <div class="w-10 h-10 rounded-2xl overflow-hidden border border-slate-200 dark:border-neutral-700 bg-white flex-shrink-0 flex items-center justify-center p-1 shadow-xs">
          <img src="/band1870logo.jpg" alt="Peñaranda Band 1870" width="40" height="40" class="w-full h-full object-contain" />
        </div>
        <div>
          <span class="font-bold text-base tracking-tight text-slate-900 dark:text-white block leading-none">SmartBand</span>
          <span class="text-[10px] text-slate-500 dark:text-neutral-400 font-medium mt-1 block">Band 1870 PWA</span>
        </div>
      </div>

      <!-- Desktop Sidebar Menu (Official M3 Navigation Drawer Items) -->
      <nav class="space-y-1.5 flex-1" aria-label="Desktop Navigation Menu">
        
        <RouterLink 
          to="/dashboard" 
          class="flex items-center px-4 py-3.5 rounded-full font-medium text-xs sm:text-sm transition-all space-x-3 cursor-pointer min-h-[48px]"
          :class="route.name === 'dashboard-home' 
            ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)] font-semibold shadow-2xs' 
            : 'text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)]'"
        >
          <Home class="w-5 h-5 flex-shrink-0" />
          <span>Home Dashboard</span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/schedule" 
          class="flex items-center px-4 py-3.5 rounded-full font-medium text-xs sm:text-sm transition-all space-x-3 cursor-pointer min-h-[48px]"
          :class="route.name === 'dashboard-schedule' 
            ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)] font-semibold shadow-2xs' 
            : 'text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)]'"
        >
          <Calendar class="w-5 h-5 flex-shrink-0" />
          <span>Schedule & Events</span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/members" 
          class="flex items-center px-4 py-3.5 rounded-full font-medium text-xs sm:text-sm transition-all space-x-3 cursor-pointer min-h-[48px]"
          :class="route.name === 'dashboard-members' 
            ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)] font-semibold shadow-2xs' 
            : 'text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)]'"
        >
          <Users class="w-5 h-5 flex-shrink-0" />
          <span>{{ store.isOfficerOrAdmin ? 'Band Directory & Ranks' : 'Band Directory' }}</span>
        </RouterLink>

        <!-- Dynamic Admin / Secretary / Executive Analytics Tab Labeling -->
        <RouterLink 
          v-if="store.isSuperAdmin || store.isSecretaryAdmin || store.isExecutive"
          to="/dashboard/admin" 
          class="flex items-center justify-between px-4 py-3.5 rounded-full font-medium text-xs sm:text-sm transition-all cursor-pointer min-h-[48px]"
          :class="route.name === 'dashboard-admin' 
            ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)] font-semibold shadow-2xs' 
            : 'text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)]'"
        >
          <div class="flex items-center space-x-3">
            <ShieldCheck class="w-5 h-5 flex-shrink-0" />
            <span>{{ store.isSuperAdmin ? 'Admin Operations' : store.isSecretaryAdmin ? 'Band Operations' : 'Executive Analytics' }}</span>
          </div>
          <span v-if="pendingCount > 0 && store.isSuperAdmin" class="px-2 py-0.5 rounded-full bg-[var(--md-error)] text-[var(--md-on-error)] font-bold text-[11px]">
            {{ pendingCount }}
          </span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/profile" 
          class="flex items-center px-4 py-3.5 rounded-full font-medium text-xs sm:text-sm transition-all space-x-3 cursor-pointer min-h-[48px]"
          :class="route.name === 'dashboard-profile' 
            ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)] font-semibold shadow-2xs' 
            : 'text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)]'"
        >
          <User class="w-5 h-5 flex-shrink-0" />
          <span>My Profile</span>
        </RouterLink>

        <!-- Role & Operational User Guide Modal Trigger -->
        <button 
          @click="showRoleGuideModal = true" 
          type="button"
          class="w-full flex items-center px-4 py-3.5 rounded-full font-medium text-xs sm:text-sm transition-all space-x-3 cursor-pointer min-h-[48px] text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)] text-left"
        >
          <HelpCircle class="w-5 h-5 flex-shrink-0 text-[var(--md-outline)]" />
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
        <button @click="handleInstallPWA" type="button" class="w-full py-2 bg-slate-900 hover:bg-slate-800 dark:bg-neutral-100 dark:hover:bg-white text-white dark:text-slate-900 font-medium text-xs rounded-full cursor-pointer min-h-[40px] transition-colors">
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
                 width="36"
                 height="36"
                 class="w-full h-full object-cover" />
            <div v-else class="w-full h-full bg-slate-700 text-white flex items-center justify-center font-bold text-xs">
              {{ store.profile?.full_name ? store.profile.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB' }}
            </div>
          </div>
          <div class="min-w-0">
            <p class="font-semibold text-xs text-slate-900 dark:text-white truncate">{{ store.profile?.full_name || 'Member' }}</p>
          </div>
        </div>
        <button 
          @click="triggerSignOut" 
          type="button" 
          class="min-w-[48px] min-h-[48px] rounded-full text-slate-500 hover:text-rose-600 hover:bg-slate-100 dark:hover:bg-neutral-800 cursor-pointer flex items-center justify-center transition-colors" 
          title="Sign Out"
          aria-label="Sign Out"
        >
          <LogOut class="w-4 h-4" />
        </button>
      </div>

    </aside>

    <!-- 3. MAIN RESPONSIVE CANVAS AREA (Adaptive Offsets: 0 on mobile, 72px on tablet, 260px on desktop) -->
    <div class="flex-1 min-w-0 min-h-dvh flex flex-col w-full sm:pl-[72px] lg:pl-64 xl:pl-72">
      <div class="flex-1 min-w-0 flex flex-col max-w-[1200px] mx-auto w-full">
      
      <!-- TOP APP BAR (Official Material 3 Small Top App Bar) -->
      <header class="sticky top-0 z-40 bg-[var(--md-surface)]/95 border-b border-[var(--md-outline-variant)]/30 px-4 sm:px-6 h-16 flex items-center justify-between transition-colors">
        <div class="flex items-center space-x-3">
          <!-- Mobile Brand Logo (Visible only on <600px mobile screens) -->
          <div class="flex items-center space-x-2.5 sm:hidden">
            <div class="w-8 h-8 rounded-xl overflow-hidden border border-[var(--md-outline-variant)] bg-white flex items-center justify-center p-0.5 shadow-xs">
              <img src="/band1870logo.jpg" alt="Logo" width="32" height="32" class="w-full h-full object-contain" />
            </div>
            <span class="font-bold text-base tracking-tight text-[var(--md-on-surface)]">SmartBand</span>
          </div>

          <!-- Tablet & Desktop View Title (Official M3 Title Large) -->
          <div class="hidden sm:flex items-center space-x-2.5">
            <p class="text-lg sm:text-xl font-medium tracking-tight text-[var(--md-on-surface)]">
              {{ currentViewTitle }}
            </p>
            <span v-if="store.currentRole" class="m3-chip m3-chip-assist h-7 text-xs px-3">
              {{ currentRoleBadge }}
            </span>
          </div>
        </div>

        <!-- Trailing Action Icons (M3 48x48dp Touch Targets) -->
        <div class="flex items-center space-x-1 sm:space-x-1.5">
          <!-- Theme Switcher (Available on all form factors) -->
          <button 
            @click="toggleTheme" 
            type="button"
            class="min-w-[48px] min-h-[48px] rounded-full text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)] transition-colors flex items-center justify-center cursor-pointer shrink-0"
            :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
            :title="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
          >
            <Sun v-if="isDark" class="w-5 h-5 text-[var(--md-on-surface)]" />
            <Moon v-else class="w-5 h-5 text-[var(--md-on-surface-variant)]" />
          </button>

          <!-- Notification & Settings Drawer Bell Trigger -->
          <button 
            @click="showSettingsDrawer = true" 
            type="button"
            class="min-w-[48px] min-h-[48px] rounded-full text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)] transition-colors flex items-center justify-center relative cursor-pointer shrink-0"
            :aria-label="notificationPermission !== 'granted' ? 'Enable Push Notifications & Settings' : 'Open App Settings & Alerts'"
            :title="notificationPermission !== 'granted' ? 'Enable Push Notifications' : 'App Settings & Alerts'"
          >
            <Bell class="w-5 h-5" />
            <span v-if="notificationPermission !== 'granted'" class="absolute top-2.5 right-2.5 w-2 h-2 bg-amber-500 rounded-full animate-pulse" title="Push notifications disabled"></span>
            <span v-else-if="pendingCount > 0" class="absolute top-2.5 right-2.5 w-2 h-2 bg-[var(--md-error)] rounded-full"></span>
          </button>
        </div>
      </header>

      <!-- NOTIFICATION PERMISSION PROMPT BANNER -->
      <Transition name="toast">
        <div 
          v-if="showFirstTimeNotifPrompt"
          class="bg-amber-500/10 dark:bg-amber-500/15 text-slate-800 dark:text-neutral-200 px-4 py-3 flex items-center justify-between border-b border-amber-500/20 text-xs"
        >
          <div class="flex items-center space-x-3 pr-2 min-w-0">
            <div class="w-7 h-7 rounded-full bg-amber-500/20 flex items-center justify-center shrink-0">
              <Bell class="w-3.5 h-3.5 text-amber-600 dark:text-amber-400" />
            </div>
            <div class="min-w-0">
              <span class="font-bold block text-slate-900 dark:text-white">Enable Device Push Notifications?</span>
              <span class="text-[11px] text-slate-600 dark:text-neutral-400 block truncate">
                Get alerted for call-times, gig updates, and urgent notices even when this app is closed.
              </span>
            </div>
          </div>
          <div class="flex items-center space-x-2 flex-shrink-0">
            <button 
              @click="requestNotificationPermission" 
              type="button" 
              class="px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-slate-100 text-white dark:text-slate-900 font-semibold rounded-full shadow-xs text-xs cursor-pointer min-h-[36px] transition-all"
            >
              Turn On
            </button>
            <button 
              @click="dismissFirstTimeNotifPrompt" 
              type="button" 
              class="px-2.5 py-1.5 text-slate-500 hover:text-slate-700 dark:text-neutral-400 dark:hover:text-white text-xs font-medium cursor-pointer min-h-[36px]"
              title="Remind me later"
            >
              Not Now
            </button>
          </div>
        </div>
      </Transition>

      <!-- NETWORK RECONNECT TOAST -->
      <Transition name="toast">
        <div 
          v-if="networkToastMsg"
          class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-sm w-11/12 bg-slate-900 dark:bg-neutral-800 text-white px-4 py-2.5 rounded-full shadow-md border border-slate-700/80 flex items-center justify-between text-xs font-medium"
        >
          <div class="flex items-center space-x-1.5">
            <CheckCircle class="w-4 h-4 text-emerald-400 flex-shrink-0" />
            <span>{{ networkToastMsg }}</span>
          </div>
        </div>
      </Transition>

      <!-- Main Router Page Body (Safe spacing at bottom so mobile bar never overlaps) -->
      <main id="main-content" class="flex-1 p-3.5 sm:p-6 lg:p-8 overflow-y-auto pb-32 sm:pb-12 max-w-[1200px] w-full mx-auto">
        <RouterView />
      </main>

      <!-- 4. OFFICIAL MATERIAL 3 NAVIGATION BAR (80dp Height with 32x64dp Pill Active Indicator, Table 8) -->
      <nav 
        class="sm:hidden fixed bottom-0 left-0 w-full bg-[var(--md-surface-container)] border-t border-[var(--md-outline-variant)]/30 shadow-xs pb-safe z-30 select-none"
        aria-label="Mobile Navigation Bar"
      >
        <div class="flex justify-around items-center h-20 px-2 max-w-md mx-auto">
          
          <!-- Tab 1: Home Dashboard -->
          <RouterLink 
            to="/dashboard" 
            class="flex flex-col items-center justify-center flex-1 h-full py-1 min-h-[48px]"
          >
            <div 
              class="w-16 h-8 rounded-full flex items-center justify-center transition-all duration-200"
              :class="route.name === 'dashboard-home' ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)]' : 'text-[var(--md-on-surface-variant)]'"
            >
              <Home class="w-6 h-6" :stroke-width="route.name === 'dashboard-home' ? 2.4 : 2" />
            </div>
            <span 
              class="text-xs mt-1 transition-colors tracking-tight"
              :class="route.name === 'dashboard-home' ? 'font-semibold text-[var(--md-on-surface)]' : 'font-normal text-[var(--md-on-surface-variant)]'"
            >
              Home
            </span>
          </RouterLink>

          <!-- Tab 2: Events Schedule -->
          <RouterLink 
            to="/dashboard/schedule" 
            class="flex flex-col items-center justify-center flex-1 h-full py-1 min-h-[48px]"
          >
            <div 
              class="w-16 h-8 rounded-full flex items-center justify-center transition-all duration-200"
              :class="route.name === 'dashboard-schedule' ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)]' : 'text-[var(--md-on-surface-variant)]'"
            >
              <Calendar class="w-6 h-6" :stroke-width="route.name === 'dashboard-schedule' ? 2.4 : 2" />
            </div>
            <span 
              class="text-xs mt-1 transition-colors tracking-tight"
              :class="route.name === 'dashboard-schedule' ? 'font-semibold text-[var(--md-on-surface)]' : 'font-normal text-[var(--md-on-surface-variant)]'"
            >
              Events
            </span>
          </RouterLink>

          <!-- Tab 3: Member Directory -->
          <RouterLink 
            to="/dashboard/members" 
            class="flex flex-col items-center justify-center flex-1 h-full py-1 min-h-[48px]"
          >
            <div 
              class="w-16 h-8 rounded-full flex items-center justify-center transition-all duration-200"
              :class="route.name === 'dashboard-members' ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)]' : 'text-[var(--md-on-surface-variant)]'"
            >
              <Users class="w-6 h-6" :stroke-width="route.name === 'dashboard-members' ? 2.4 : 2" />
            </div>
            <span 
              class="text-xs mt-1 transition-colors tracking-tight"
              :class="route.name === 'dashboard-members' ? 'font-semibold text-[var(--md-on-surface)]' : 'font-normal text-[var(--md-on-surface-variant)]'"
            >
              Roster
            </span>
          </RouterLink>

          <!-- Tab 4: Admin Operations -->
          <RouterLink 
            v-if="store.isSuperAdmin || store.isSecretaryAdmin || store.isExecutive"
            to="/dashboard/admin" 
            class="flex flex-col items-center justify-center flex-1 h-full py-1 relative min-h-[48px]"
          >
            <div 
              class="w-16 h-8 rounded-full flex items-center justify-center transition-all duration-200 relative"
              :class="route.name === 'dashboard-admin' ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)]' : 'text-[var(--md-on-surface-variant)]'"
            >
              <ShieldCheck class="w-6 h-6" :stroke-width="route.name === 'dashboard-admin' ? 2.4 : 2" />
              <span v-if="pendingCount > 0 && store.isSuperAdmin" class="absolute top-1 right-3 w-2 h-2 bg-[var(--md-error)] rounded-full"></span>
            </div>
            <span 
              class="text-xs mt-1 transition-colors tracking-tight"
              :class="route.name === 'dashboard-admin' ? 'font-semibold text-[var(--md-on-surface)]' : 'font-normal text-[var(--md-on-surface-variant)]'"
            >
              {{ store.isSuperAdmin ? 'Admin' : 'Ops' }}
            </span>
          </RouterLink>

          <!-- Tab 5: Profile -->
          <RouterLink 
            to="/dashboard/profile" 
            class="flex flex-col items-center justify-center flex-1 h-full py-1 min-h-[48px]"
          >
            <div 
              class="w-16 h-8 rounded-full flex items-center justify-center transition-all duration-200"
              :class="route.name === 'dashboard-profile' ? 'bg-[var(--md-secondary-container)] text-[var(--md-on-secondary-container)]' : 'text-[var(--md-on-surface-variant)]'"
            >
              <User class="w-6 h-6" :stroke-width="route.name === 'dashboard-profile' ? 2.4 : 2" />
            </div>
            <span 
              class="text-xs mt-1 transition-colors tracking-tight"
              :class="route.name === 'dashboard-profile' ? 'font-semibold text-[var(--md-on-surface)]' : 'font-normal text-[var(--md-on-surface-variant)]'"
            >
              Profile
            </span>
          </RouterLink>
        </div>
      </nav>

      </div>
    </div>

    <!-- HIGH-VISIBILITY CALL-TIME ALARM DIALOG (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <Transition name="toast">
      <div v-if="activeAlarmModal" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4">
        <div 
          role="dialog" 
          aria-modal="true" 
          aria-labelledby="alarm-modal-title"
          tabindex="-1"
          @keydown.escape="dismissActiveAlarm"
          class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-[#2d3035] rounded-[28px] p-6 max-w-sm w-full space-y-4 shadow-xl text-center"
        >
          
          <div class="w-14 h-14 rounded-full bg-slate-100 dark:bg-[#282a2c] text-slate-800 dark:text-white flex items-center justify-center mx-auto">
            <Volume2 class="w-7 h-7" />
          </div>

          <div>
            <span class="inline-block px-3 py-1 bg-slate-100 dark:bg-[#282a2c] text-slate-700 dark:text-neutral-300 text-[11px] font-semibold uppercase rounded-full tracking-wider mb-2">
              Call-Time Alarm
            </span>
            <h2 id="alarm-modal-title" class="text-xl font-bold text-slate-900 dark:text-white leading-snug">
              {{ activeAlarmModal.title }}
            </h2>
            <p class="text-sm font-semibold text-rose-600 dark:text-rose-400 mt-1 uppercase tracking-wide">
              {{ activeAlarmModal.countdownText }}
            </p>
          </div>

          <div class="bg-slate-50 dark:bg-[#282a2c]/60 p-3.5 rounded-2xl space-y-1.5 text-xs text-slate-700 dark:text-neutral-300 text-left border border-slate-200/60 dark:border-[#2d3035]">
            <div class="flex items-center"><Clock class="w-4 h-4 mr-2 text-slate-500" /> Scheduled: {{ activeAlarmModal.timeText }}</div>
            <div class="flex items-center"><MapPin class="w-4 h-4 mr-2 text-slate-500" /> Location: {{ activeAlarmModal.location }}</div>
          </div>

          <button 
            @click="dismissActiveAlarm"
            type="button"
            class="w-full py-3 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:text-slate-900 text-white font-medium text-sm rounded-full shadow-xs cursor-pointer min-h-[48px] transition-colors"
          >
            I Am Ready / Dismiss
          </button>
        </div>
      </div>
    </Transition>

    <!-- APP SETTINGS & NOTIFICATIONS DRAWER MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showSettingsDrawer" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-3 sm:p-4" @click.self="showSettingsDrawer = false">
      <div 
        role="dialog" 
        aria-modal="true" 
        aria-labelledby="settings-drawer-title"
        tabindex="-1"
        @keydown.escape="showSettingsDrawer = false"
        class="m3-surface-modal bg-[var(--md-surface-container-high)] text-[var(--md-on-surface)] border border-[var(--md-outline-variant)]/60 rounded-[28px] p-5 sm:p-6 max-w-md w-full space-y-4 shadow-xl text-left"
      >
        
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/30 pb-3">
          <div class="flex items-center space-x-2">
            <Bell class="w-5 h-5 text-[var(--md-on-surface-variant)]" />
            <h3 id="settings-drawer-title" class="font-bold text-base text-[var(--md-on-surface)]">Settings &amp; Notifications</h3>
          </div>
          <button @click="showSettingsDrawer = false" class="min-w-[48px] min-h-[48px] rounded-full text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container)] transition-colors flex items-center justify-center cursor-pointer" aria-label="Close Settings">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div class="space-y-2.5">
          <!-- Network Sync Badge -->
          <div class="flex items-center justify-between p-3.5 rounded-2xl bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)]/40">
            <div class="flex items-center space-x-2.5">
              <Wifi v-if="isOnline" class="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
              <WifiOff v-else class="w-4 h-4 text-[var(--md-error)]" />
              <span class="text-xs font-semibold text-[var(--md-on-surface)]">{{ isOnline ? 'Online Sync Active' : 'Offline Mode' }}</span>
            </div>
            <span class="w-2.5 h-2.5 rounded-full" :class="isOnline ? 'bg-emerald-500' : 'bg-[var(--md-error)]'"></span>
          </div>

          <!-- Device Push Notifications Row -->
          <div class="p-3.5 rounded-2xl bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)]/40 space-y-2.5">
            <div class="flex items-center justify-between gap-2">
              <div>
                <p class="font-bold text-xs text-[var(--md-on-surface)]">Device Push Notifications</p>
                <p class="text-[11px] text-[var(--md-on-surface-variant)]">
                  Alerts when app is closed (Phone / PC)
                </p>
              </div>
              <div v-if="notificationPermission === 'granted'" class="m3-chip m3-chip-info h-7 px-3 text-[11px] font-semibold shrink-0">
                <Check class="w-3.5 h-3.5" />
                <span>Active</span>
              </div>
              <button 
                v-else
                @click="requestNotificationPermission" 
                type="button" 
                class="m3-btn-filled min-h-[44px] text-xs font-semibold px-4 cursor-pointer shrink-0"
              >
                Turn On
              </button>
            </div>
            
            <!-- Test Push Button when permission is granted -->
            <div v-if="notificationPermission === 'granted'" class="pt-2 border-t border-[var(--md-outline-variant)]/20 flex items-center justify-between">
              <span class="text-[11px] text-[var(--md-on-surface-variant)]">Test background delivery:</span>
              <button 
                @click="testBackgroundPush" 
                :disabled="isTestingPush" 
                type="button" 
                class="m3-btn-tonal min-h-[38px] text-xs font-medium px-3.5 cursor-pointer disabled:opacity-50"
              >
                {{ isTestingPush ? 'Sending...' : 'Send Test Push' }}
              </button>
            </div>
          </div>

          <!-- Audible Alarms Toggle -->
          <div class="flex items-center justify-between p-3.5 rounded-2xl bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)]/40">
            <div>
              <p class="font-bold text-xs text-[var(--md-on-surface)]">Call-Time Alarm</p>
              <p class="text-[11px] text-[var(--md-on-surface-variant)]">Audible call-time reminder</p>
            </div>
            <div class="flex items-center space-x-2 shrink-0">
              <button 
                @click="testAlarmTone" 
                type="button" 
                class="min-w-[44px] min-h-[44px] rounded-full bg-[var(--md-surface-container-high)] hover:bg-[var(--md-surface-container-highest)] text-[var(--md-on-surface)] border border-[var(--md-outline-variant)]/40 transition-colors flex items-center justify-center cursor-pointer"
                title="Test Alarm Chime"
                aria-label="Test Alarm Chime"
              >
                <Volume2 class="w-4 h-4" />
              </button>
              <button 
                @click="toggleAlarms" 
                type="button" 
                class="min-h-[44px] px-4 font-semibold text-xs rounded-full cursor-pointer transition-colors"
                :class="enableAlarms ? 'bg-[var(--md-primary)] text-[var(--md-on-primary)] shadow-xs' : 'bg-[var(--md-surface-container-highest)] text-[var(--md-on-surface-variant)]'"
              >
                {{ enableAlarms ? 'Enabled' : 'Disabled' }}
              </button>
            </div>
          </div>

          <!-- PWA Install Status in Drawer -->
          <div class="flex items-center justify-between p-3.5 rounded-2xl bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)]/40">
            <div>
              <p class="font-bold text-xs text-[var(--md-on-surface)]">App Installation</p>
              <p class="text-[11px] text-[var(--md-on-surface-variant)]">
                {{ isAppInstalled ? 'Installed on device' : 'Install for offline launch' }}
              </p>
            </div>
            
            <div v-if="isAppInstalled" class="m3-chip m3-chip-info h-7 px-3 text-[11px] font-semibold shrink-0">
              <Check class="w-3.5 h-3.5" />
              <span>Installed</span>
            </div>
            
            <button 
              v-else
              @click="handleInstallPWA" 
              type="button" 
              class="m3-btn-filled min-h-[44px] text-xs font-semibold px-4 cursor-pointer shrink-0"
            >
              Install
            </button>
          </div>

          <!-- In-App Banners Toggle -->
          <div class="flex items-center justify-between p-3.5 rounded-2xl bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)]/40">
            <div>
              <p class="font-bold text-xs text-[var(--md-on-surface)]">In-App Banners</p>
              <p class="text-[11px] text-[var(--md-on-surface-variant)]">Visual reminders &amp; chimes</p>
            </div>
            <button 
              @click="toggleBanners" 
              type="button" 
              class="min-h-[44px] px-4 font-semibold text-xs rounded-full cursor-pointer transition-colors shrink-0"
              :class="enableBanners ? 'bg-[var(--md-primary)] text-[var(--md-on-primary)] shadow-xs' : 'bg-[var(--md-surface-container-highest)] text-[var(--md-on-surface-variant)]'"
            >
              {{ enableBanners ? 'Enabled' : 'Disabled' }}
            </button>
          </div>

          <!-- Theme Mode Toggle -->
          <div class="flex items-center justify-between p-3.5 rounded-2xl bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)]/40">
            <div class="flex items-center space-x-2">
              <Sun v-if="isDark" class="w-4 h-4 text-[var(--md-tertiary)]" />
              <Moon v-else class="w-4 h-4 text-[var(--md-on-surface)]" />
              <span class="text-xs font-semibold text-[var(--md-on-surface)]">Theme Mode</span>
            </div>
            <button 
              @click="toggleTheme" 
              type="button" 
              class="min-h-[44px] px-4 font-semibold text-xs rounded-full cursor-pointer transition-colors bg-[var(--md-surface-container-highest)] text-[var(--md-on-surface)] hover:bg-[var(--md-outline-variant)]/30 shrink-0"
            >
              {{ isDark ? 'Dark Theme' : 'Light Theme' }}
            </button>
          </div>

          <!-- View Terms & Conditions -->
          <button 
            @click="showTermsModal = true" 
            type="button" 
            class="w-full flex items-center justify-between p-3.5 rounded-2xl bg-[var(--md-surface-container)] hover:bg-[var(--md-surface-container-highest)] border border-[var(--md-outline-variant)]/40 text-xs font-semibold text-[var(--md-on-surface)] min-h-[48px] cursor-pointer transition-colors"
          >
            <span class="flex items-center"><FileText class="w-4 h-4 mr-2 text-[var(--md-outline)]" /> View Terms &amp; Conditions</span>
            <span class="text-[var(--md-on-surface-variant)] font-bold">→</span>
          </button>
        </div>

        <div class="pt-3 border-t border-[var(--md-outline-variant)]/30 pb-1 flex justify-end">
          <button @click="showSettingsDrawer = false" type="button" class="m3-btn-tonal min-h-[48px] text-xs font-semibold px-6 w-full sm:w-auto cursor-pointer">
            Close
          </button>
        </div>

      </div>
    </div>

    <!-- TERMS & CONDITIONS MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showTermsModal" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-3 sm:p-4" @click.self="showTermsModal = false">
      <div 
        role="dialog" 
        aria-modal="true" 
        aria-labelledby="terms-modal-title"
        tabindex="-1"
        @keydown.escape="showTermsModal = false"
        class="m3-surface-modal bg-[var(--md-surface-container-high)] text-[var(--md-on-surface)] border border-[var(--md-outline-variant)]/60 rounded-[28px] p-5 sm:p-6 max-w-md w-full space-y-4 shadow-xl text-left max-h-[80vh] flex flex-col"
      >
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/30 pb-3">
          <div class="flex items-center space-x-2">
            <FileText class="w-5 h-5 text-[var(--md-on-surface-variant)]" />
            <h3 id="terms-modal-title" class="font-bold text-base text-[var(--md-on-surface)]">Terms &amp; Conditions</h3>
          </div>
          <button @click="showTermsModal = false" class="min-w-[48px] min-h-[48px] rounded-full text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container)] transition-colors flex items-center justify-center cursor-pointer" aria-label="Close Terms">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div class="overflow-y-auto flex-1 text-xs text-[var(--md-on-surface-variant)] space-y-3.5 pr-2 leading-relaxed font-normal">
          <div>
            <h4 class="font-bold text-[var(--md-on-surface)] text-xs mb-1">Article 1: Master List Verification Requirement</h4>
            <p>All sign-ups are provisional until physically verified by the IT Super Admin against the official municipal band registry.</p>
          </div>

          <div>
            <h4 class="font-bold text-[var(--md-on-surface)] text-xs mb-1">Article 2: Attendance Confirmation Reliability Scoring</h4>
            <p>Confirming attendance creates an operational commitment for gig planning. Unexcused absences or sudden cancellations directly impact your personal Reliability Score (%).</p>
          </div>

          <div>
            <h4 class="font-bold text-[var(--md-on-surface)] text-xs mb-1">Article 3: Call-Time Punctuality &amp; Alert Protocols</h4>
            <p>Musicians must adhere to designated call times for rehearsals, parades, funeral services, and concerts. The in-app call-time alarms serve as operational notifications.</p>
          </div>

          <div>
            <h4 class="font-bold text-[var(--md-on-surface)] text-xs mb-1">Article 4: Band Property &amp; Instrument Care</h4>
            <p>Members issued municipal band instruments, uniforms, or sheet music folios are strictly responsible for their maintenance, safekeeping, and prompt return upon request.</p>
          </div>

          <div>
            <h4 class="font-bold text-[var(--md-on-surface)] text-xs mb-1">Article 5: Data Privacy &amp; Security</h4>
            <p>Member contact numbers and personal birth dates are protected under Row Level Security (RLS) and will never be exposed to public directory views.</p>
          </div>
        </div>

        <div class="pt-3 border-t border-[var(--md-outline-variant)]/30">
          <button @click="showTermsModal = false" type="button" class="m3-btn-tonal w-full min-h-[48px] text-xs font-semibold cursor-pointer">
            Close
          </button>
        </div>
      </div>
    </div>

    <!-- COMPREHENSIVE ROLE & OPERATIONAL USER GUIDE MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showRoleGuideModal" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-3 sm:p-4" @click.self="showRoleGuideModal = false">
      <div 
        role="dialog" 
        aria-modal="true" 
        aria-labelledby="role-guide-modal-title"
        tabindex="-1"
        @keydown.escape="showRoleGuideModal = false"
        class="m3-surface-modal bg-[var(--md-surface-container-high)] text-[var(--md-on-surface)] border border-[var(--md-outline-variant)]/60 rounded-[28px] p-5 sm:p-6 max-w-xl w-full space-y-4 shadow-xl text-left max-h-[90vh] flex flex-col"
      >
        
        <!-- Modal Header -->
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/30 pb-3">
          <div class="flex items-center space-x-2.5">
            <div class="p-2 rounded-full bg-[var(--md-surface-container)] text-[var(--md-on-surface)]">
              <BookOpen class="w-4 h-4" />
            </div>
            <div>
              <h3 id="role-guide-modal-title" class="font-bold text-base text-[var(--md-on-surface)] leading-tight">SmartBand User &amp; Role Guide</h3>
              <p class="text-[11px] text-[var(--md-on-surface-variant)]">Operational responsibilities, turnout rules, and quick manuals</p>
            </div>
          </div>
          <button @click="showRoleGuideModal = false" class="min-w-[48px] min-h-[48px] rounded-full text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container)] transition-colors flex items-center justify-center cursor-pointer" aria-label="Close Guide">
            <X class="w-4 h-4" />
          </button>
        </div>

        <!-- Navigation Tabs (M3 Segmented Button) -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-1 p-1 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 text-xs font-medium shrink-0">
          <button 
            @click="activeGuideTab = 'roles'"
            type="button"
            class="py-2 px-2 rounded-xl text-center transition-all cursor-pointer min-h-[40px] flex items-center justify-center"
            :class="activeGuideTab === 'roles' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Role Powers
          </button>
          <button 
            @click="activeGuideTab = 'attendance'"
            type="button"
            class="py-2 px-2 rounded-xl text-center transition-all cursor-pointer min-h-[40px] flex items-center justify-center"
            :class="activeGuideTab === 'attendance' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Turnout Math
          </button>
          <button 
            @click="activeGuideTab = 'availability'"
            type="button"
            class="py-2 px-2 rounded-xl text-center transition-all cursor-pointer min-h-[40px] flex items-center justify-center"
            :class="activeGuideTab === 'availability' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Availability
          </button>
          <button 
            @click="activeGuideTab = 'pwa'"
            type="button"
            class="py-2 px-2 rounded-xl text-center transition-all cursor-pointer min-h-[40px] flex items-center justify-center"
            :class="activeGuideTab === 'pwa' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            PWA &amp; Offline
          </button>
        </div>

        <!-- Tab Body (Scrollable) -->
        <div class="flex-1 overflow-y-auto space-y-3 pr-1 text-xs text-[var(--md-on-surface-variant)] leading-relaxed">
          
          <!-- TAB 1: ROLES & RESPONSIBILITIES -->
          <div v-if="activeGuideTab === 'roles'" class="space-y-3">
            <div class="p-3.5 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 space-y-1.5">
              <div class="flex items-center space-x-2">
                <span class="m3-chip m3-chip-info h-6 text-xs px-2.5 font-semibold">Musician</span>
                <h4 class="font-bold text-[var(--md-on-surface)] text-sm">Regular Band Member</h4>
              </div>
              <ul class="list-disc list-inside space-y-1 text-[11px] text-[var(--md-on-surface-variant)]">
                <li>Confirm attendance to upcoming gigs and rehearsals (Attending or Not Attending).</li>
                <li>Maintain your 7-day recurring weekly availability in <strong>My Profile</strong>.</li>
                <li>Receive automated call-time alarms before gigs and rehearsals.</li>
                <li>Maintain a high Reliability Score (100% baseline).</li>
              </ul>
            </div>

            <div class="p-3.5 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 space-y-1.5">
              <div class="flex items-center space-x-2">
                <span class="m3-chip m3-chip-rsvp h-6 text-xs px-2.5 font-semibold">Secretary</span>
                <h4 class="font-bold text-[var(--md-on-surface)] text-sm">Band Secretary</h4>
              </div>
              <ul class="list-disc list-inside space-y-1 text-[11px] text-[var(--md-on-surface-variant)]">
                <li>Schedule and announce new band rehearsals, civic parades, and feast processions.</li>
                <li>Conduct attendance checks with the <strong>Attendance Log</strong> (mark Present, Absent, or Excused).</li>
                <li>Use <strong>Check Member Availability</strong> to see who is free for upcoming days and sections.</li>
                <li>Broadcast urgent attendance reminder alerts to pending musicians.</li>
              </ul>
            </div>

            <div class="p-3.5 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 space-y-1.5">
              <div class="flex items-center space-x-2">
                <span class="m3-chip m3-chip-assist h-6 text-xs px-2.5 font-semibold">Executive</span>
                <h4 class="font-bold text-[var(--md-on-surface)] text-sm">President, Conductor &amp; Board</h4>
              </div>
              <ul class="list-disc list-inside space-y-1 text-[11px] text-[var(--md-on-surface-variant)]">
                <li>Inspect roster-wide turnout analytics and section performance (Woodwinds, Brass, Percussion).</li>
                <li>Review the <strong>Musician Reliability Matrix</strong> to identify attendance trends.</li>
                <li>Sort members by attendance reliability to resolve lineup bottlenecks.</li>
              </ul>
            </div>

            <div class="p-3.5 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 space-y-1.5">
              <div class="flex items-center space-x-2">
                <span class="m3-chip m3-chip-urgent h-6 text-xs px-2.5 font-semibold">Super Admin</span>
                <h4 class="font-bold text-[var(--md-on-surface)] text-sm">IT Super Admin</h4>
              </div>
              <ul class="list-disc list-inside space-y-1 text-[11px] text-[var(--md-on-surface-variant)]">
                <li>Approve or decline new member account registrations and verify identity.</li>
                <li>Moderate profile avatar photo uploads.</li>
                <li>Promote musicians to appointed officer posts (Band Secretary, Conductor, etc.).</li>
                <li>Generate and download official standardized PDF reports for municipal review.</li>
              </ul>
            </div>
          </div>

          <!-- TAB 2: TURNOUT MATH & RELIABILITY -->
          <div v-else-if="activeGuideTab === 'attendance'" class="space-y-3">
            <div class="p-4 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 space-y-2">
              <h4 class="font-bold text-[var(--md-on-surface)] text-sm">How Attendance Scoring Works</h4>
              <p class="text-[11px]">
                Every member begins with a <strong>100% Reliability Score</strong>. Reliability reflects follow-through on commitments.
              </p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
              <div class="p-3 bg-[var(--md-surface-container-low)] rounded-xl border border-[var(--md-outline-variant)]/30 space-y-1">
                <div class="flex items-center space-x-1.5 text-emerald-600 dark:text-emerald-400 font-bold text-xs">
                  <CheckCircle class="w-4 h-4" />
                  <span>Present</span>
                </div>
                <p class="text-[11px] text-[var(--md-on-surface-variant)]">Musician confirmed attending and showed up to perform. Positive follow-through recorded.</p>
              </div>

              <div class="p-3 bg-[var(--md-surface-container-low)] rounded-xl border border-[var(--md-outline-variant)]/30 space-y-1">
                <div class="flex items-center space-x-1.5 text-blue-600 dark:text-blue-400 font-bold text-xs">
                  <Check class="w-4 h-4" />
                  <span>Declined in Advance</span>
                </div>
                <p class="text-[11px] text-[var(--md-on-surface-variant)]"><strong>0% penalty!</strong> Declining early allows section leaders to find instrument substitutes in time.</p>
              </div>

              <div class="p-3 bg-[var(--md-surface-container-low)] rounded-xl border border-[var(--md-outline-variant)]/30 space-y-1">
                <div class="flex items-center space-x-1.5 text-[var(--md-error)] font-bold text-xs">
                  <AlertCircle class="w-4 h-4" />
                  <span>Unexcused No-Show</span>
                </div>
                <p class="text-[11px] text-[var(--md-on-surface-variant)]">Musician confirmed "Attending" but failed to show up without prior notice. Applies a <strong>-10% Reliability penalty</strong>.</p>
              </div>

              <div class="p-3 bg-[var(--md-surface-container-low)] rounded-xl border border-[var(--md-outline-variant)]/30 space-y-1">
                <div class="flex items-center space-x-1.5 text-[var(--md-on-surface)] font-bold text-xs">
                  <ShieldCheck class="w-4 h-4 text-[var(--md-tertiary)]" />
                  <span>Excused Absence</span>
                </div>
                <p class="text-[11px] text-[var(--md-on-surface-variant)]">Valid medical or documented prior notice granted by Band Secretary. <strong>0% penalty</strong>.</p>
              </div>
            </div>
          </div>

          <!-- TAB 3: AVAILABILITY RULES -->
          <div v-else-if="activeGuideTab === 'availability'" class="space-y-3">
            <div class="p-4 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 space-y-2">
              <h4 class="font-bold text-[var(--md-on-surface)] text-sm">Weekly Recurring Grid vs Events</h4>
              <p class="text-[11px] text-[var(--md-on-surface-variant)]">
                In <strong>My Profile &gt; Availability Grid</strong>, musicians configure their regular 7-day routine (Monday–Sunday, with Morning, Afternoon, and Evening slots).
              </p>
              <p class="text-[11px] text-[var(--md-on-surface-variant)]">
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
            <div class="p-4 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 space-y-2">
              <h4 class="font-bold text-[var(--md-on-surface)] text-sm flex items-center">
                <Download class="w-4 h-4 mr-1.5 text-[var(--md-primary)]" /> Install SmartBand App
              </h4>
              <p class="text-[11px] text-[var(--md-on-surface-variant)] leading-relaxed">
                SmartBand installs directly to your home screen or desktop without needing Google Play or Apple App Store.
              </p>
            </div>

            <!-- Platform-Specific Step Cards -->
            <div class="space-y-2">
              <!-- Android -->
              <div class="p-3 bg-[var(--md-surface-container-low)] rounded-xl border border-[var(--md-outline-variant)]/30 space-y-1">
                <div class="font-bold text-xs text-[var(--md-on-surface)] flex items-center gap-1.5">
                  <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
                  <span>Android (Chrome / Samsung / Brave)</span>
                </div>
                <p class="text-[11px] text-[var(--md-on-surface-variant)] leading-relaxed">
                  1. Tap the browser <strong>Menu (⋮)</strong> in the top-right corner.<br />
                  2. Select <strong>"Install app"</strong> or <strong>"Add to Home screen"</strong>.<br />
                  3. Tap <strong>Install</strong> to add the app icon to your home screen.
                </p>
              </div>

              <!-- iPhone / iPad -->
              <div class="p-3 bg-[var(--md-surface-container-low)] rounded-xl border border-[var(--md-outline-variant)]/30 space-y-1">
                <div class="font-bold text-xs text-[var(--md-on-surface)] flex items-center gap-1.5">
                  <span class="w-2 h-2 rounded-full bg-blue-500"></span>
                  <span>iPhone &amp; iPad (Safari)</span>
                </div>
                <p class="text-[11px] text-[var(--md-on-surface-variant)] leading-relaxed">
                  1. Tap the <strong>Share</strong> button (square with arrow pointing up).<br />
                  2. Scroll down and tap <strong>"Add to Home Screen"</strong>.<br />
                  3. Tap <strong>Add</strong> in the top right.
                </p>
              </div>

              <!-- Desktop PC / Mac -->
              <div class="p-3 bg-[var(--md-surface-container-low)] rounded-xl border border-[var(--md-outline-variant)]/30 space-y-1">
                <div class="font-bold text-xs text-[var(--md-on-surface)] flex items-center gap-1.5">
                  <span class="w-2 h-2 rounded-full bg-indigo-500"></span>
                  <span>Desktop (Chrome, Edge)</span>
                </div>
                <p class="text-[11px] text-[var(--md-on-surface-variant)] leading-relaxed">
                  Click the <strong>Install icon</strong> in your address bar on the right, or click Menu (⋮) &rarr; <strong>"Install SmartBand"</strong>.
                </p>
              </div>
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
        <div class="pt-3 border-t border-[var(--md-outline-variant)]/30">
          <button @click="showRoleGuideModal = false" type="button" class="m3-btn-tonal w-full min-h-[48px] text-xs font-semibold cursor-pointer">
            Close Guide
          </button>
        </div>

      </div>
    </div>

    <!-- SIGN OUT CONFIRMATION MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showSignOutModal" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4" @click.self="showSignOutModal = false">
      <div 
        role="dialog" 
        aria-modal="true" 
        aria-labelledby="signout-modal-title"
        tabindex="-1"
        @keydown.escape="showSignOutModal = false"
        class="m3-surface-modal bg-[var(--md-surface-container-high)] text-[var(--md-on-surface)] border border-[var(--md-outline-variant)]/60 rounded-[28px] p-6 max-w-sm w-full space-y-4 shadow-xl text-center"
      >
        <div class="w-12 h-12 rounded-full bg-[var(--md-surface-container)] flex items-center justify-center mx-auto text-[var(--md-on-surface)]">
          <LogOut class="w-5 h-5 text-[var(--md-error)]" />
        </div>
        <div class="space-y-1">
          <h3 id="signout-modal-title" class="font-bold text-base text-[var(--md-on-surface)]">Sign Out of SmartBand?</h3>
          <p class="text-xs text-[var(--md-on-surface-variant)] font-normal">Are you sure you want to sign out? You will need to log back in to access event schedules and receive operational alarms.</p>
        </div>
        <div class="grid grid-cols-2 gap-2.5 pt-2">
          <button 
            @click="showSignOutModal = false" 
            type="button" 
            class="m3-btn-tonal min-h-[48px] text-xs font-semibold cursor-pointer"
          >
            Cancel
          </button>
          <button 
            @click="handleSignOut" 
            type="button" 
            class="m3-btn-filled bg-[var(--md-error)] text-white hover:bg-rose-700 min-h-[48px] text-xs font-semibold cursor-pointer"
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
  padding-bottom: max(16px, env(safe-area-inset-bottom));
}
</style>
