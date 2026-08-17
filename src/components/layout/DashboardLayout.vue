<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { RouterView, RouterLink, useRoute } from 'vue-router'
import { Home, Calendar, User, Sun, Moon, Music, Users, ShieldCheck, Download, Wifi, WifiOff, LogOut, Bell, BellOff, FileText, X, CheckCircle, AlertCircle, Check, Volume2, AlertTriangle, Clock, MapPin } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useRouter } from 'vue-router'
import { supabase } from '@/supabase'

const route = useRoute()
const router = useRouter()
const store = useMainStore()
const isDark = ref(true)

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
  } else {
    document.documentElement.classList.remove('dark')
  }
}

const handleInstallPWA = async () => {
  if (isAppInstalled.value) {
    alert('SmartBand is already installed on your device!')
    return
  }
  if (!deferredPrompt.value) {
    alert('To install SmartBand:\n• Mobile: Tap Share / Menu → Add to Home Screen.\n• Desktop: Click the Install icon in your browser address bar.')
    return
  }
  deferredPrompt.value.prompt()
  const { outcome } = await deferredPrompt.value.userChoice
  if (outcome === 'accepted') {
    showInstallBanner.value = false
    isAppInstalled.value = true
  }
  deferredPrompt.value = null
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

const syncPushSubscription = async () => {
  if (!store.user) return
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return

  try {
    const reg = await navigator.serviceWorker.ready
    const sub = await reg.pushManager.getSubscription()
    if (sub) {
      const rawKey = sub.getKey ? sub.getKey('p256dh') : null
      const rawAuth = sub.getKey ? sub.getKey('auth') : null
      const p256dh = rawKey ? btoa(String.fromCharCode.apply(null, new Uint8Array(rawKey))) : null
      const auth = rawAuth ? btoa(String.fromCharCode.apply(null, new Uint8Array(rawAuth))) : null

      await supabase.from('push_subscriptions').upsert({
        user_id: store.user.id,
        endpoint: sub.endpoint,
        p256dh: p256dh,
        auth: auth
      }, { onConflict: 'user_id,endpoint' })
    }
  } catch(e) {
    console.warn('Push subscription sync notice:', e)
  }
}

const requestNotificationPermission = async () => {
  if (!('Notification' in window)) {
    alert('Notifications are not supported on this browser.')
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

        playAlarmSiren(5)

        activeAlarmModal.value = {
          title: ev.title,
          location: ev.location,
          timeText: new Date(rawDate).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          countdownText: `Starts in ${diffMinutes} minutes`,
          urgency: 'warning'
        }

        if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
          try {
            new Notification(`🚨 Call-Time Alarm: ${ev.title}`, {
              body: `Starts in ${diffMinutes} min (${activeAlarmModal.value.timeText}) at ${ev.location}!`,
              icon: '/favicon.svg'
            })
          } catch(e){}
        }
      }
    }

    if (diffMs <= 0 && diffMs >= -2 * 60 * 1000) {
      const notifKey0 = `smartband_alarm_0m_${ev.id}`
      if (!localStorage.getItem(notifKey0)) {
        localStorage.setItem(notifKey0, 'true')

        playAlarmSiren(5)

        activeAlarmModal.value = {
          title: ev.title,
          location: ev.location,
          timeText: new Date(rawDate).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          countdownText: `EVENT IS STARTING NOW!`,
          urgency: 'danger'
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

const handleSignOut = async () => {
  await store.signOut()
  router.push('/')
}

onMounted(() => {
  isDark.value = document.documentElement.classList.contains('dark')

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
    if (!isAppInstalled.value) {
      showInstallBanner.value = true
    }
  })

  window.addEventListener('online', updateNetworkStatus)
  window.addEventListener('offline', updateNetworkStatus)

  if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
    const dismissed = localStorage.getItem('smartband_notif_prompt_dismissed')
    if (!dismissed) {
      showFirstTimeNotifPrompt.value = true
    }
  }

  fetchPendingCount()

  checkUpcomingCallTimes()
  callTimeMonitorTimer = setInterval(checkUpcomingCallTimes, 10000)

  if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
    syncPushSubscription()
  }
})

onUnmounted(() => {
  window.removeEventListener('online', updateNetworkStatus)
  window.removeEventListener('offline', updateNetworkStatus)
  if (callTimeMonitorTimer) clearInterval(callTimeMonitorTimer)
})
</script>

<template>
  <div class="min-h-screen bg-[#f8fafc] dark:bg-[#121214] text-slate-900 dark:text-neutral-100 flex transition-colors duration-300">
    
    <!-- DESKTOP LEFT NAVIGATION SIDEBAR (Neutral Matte Charcoal) -->
    <aside class="hidden md:flex md:w-64 lg:w-72 flex-col bg-white dark:bg-[#1c1c1e] border-r border-slate-200 dark:border-neutral-800/80 p-5 space-y-6 flex-shrink-0 min-h-screen sticky top-0 h-screen overflow-y-auto">
      
      <!-- Brand Logo -->
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class="bg-blue-600 p-2 rounded-2xl shadow-md text-white">
            <Music class="w-6 h-6" stroke-width="2.5" />
          </div>
          <div>
            <span class="font-black text-xl tracking-tight text-slate-900 dark:text-white block leading-none">SmartBand</span>
            <span class="text-[10px] font-bold text-slate-400 dark:text-neutral-500 uppercase tracking-widest">Enterprise PWA</span>
          </div>
        </div>

        <!-- Desktop Theme Toggle -->
        <button 
          @click="toggleTheme" 
          type="button"
          class="p-2 rounded-xl bg-slate-100 dark:bg-[#27272a] text-slate-700 dark:text-blue-400 hover:bg-slate-200 dark:hover:bg-[#323238] transition-colors border border-transparent dark:border-neutral-700/60 cursor-pointer min-w-[40px] min-h-[40px] flex items-center justify-center"
          :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
          title="Toggle Light/Dark Theme"
        >
          <Sun v-if="isDark" class="w-4 h-4 text-amber-400" />
          <Moon v-else class="w-4 h-4 text-blue-600" />
        </button>
      </div>

      <!-- Desktop Sidebar Menu -->
      <nav class="space-y-1.5 flex-1" aria-label="Desktop Navigation Menu">
        
        <RouterLink 
          to="/dashboard" 
          class="flex items-center px-4 py-3.5 rounded-2xl font-bold text-xs transition-all space-x-3 cursor-pointer min-h-[44px]"
          :class="route.name === 'dashboard-home' 
            ? 'bg-blue-600 text-white shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#27272a]'"
        >
          <Home class="w-5 h-5 flex-shrink-0" />
          <span>Home Dashboard</span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/schedule" 
          class="flex items-center px-4 py-3.5 rounded-2xl font-bold text-xs transition-all space-x-3 cursor-pointer min-h-[44px]"
          :class="route.name === 'dashboard-schedule' 
            ? 'bg-blue-600 text-white shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#27272a]'"
        >
          <Calendar class="w-5 h-5 flex-shrink-0" />
          <span>Schedule & Events</span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/members" 
          class="flex items-center px-4 py-3.5 rounded-2xl font-bold text-xs transition-all space-x-3 cursor-pointer min-h-[44px]"
          :class="route.name === 'dashboard-members' 
            ? 'bg-blue-600 text-white shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#27272a]'"
        >
          <Users class="w-5 h-5 flex-shrink-0" />
          <span>Band Directory & Ranks</span>
        </RouterLink>

        <!-- Dynamic Admin / Secretary Tab Labeling -->
        <RouterLink 
          v-if="store.isSuperAdmin || store.isSecretaryAdmin"
          to="/dashboard/admin" 
          class="flex items-center justify-between px-4 py-3.5 rounded-2xl font-bold text-xs transition-all cursor-pointer min-h-[44px]"
          :class="route.name === 'dashboard-admin' 
            ? 'bg-blue-600 text-white shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#27272a]'"
        >
          <div class="flex items-center space-x-3">
            <ShieldCheck class="w-5 h-5 flex-shrink-0 text-blue-400" />
            <span>{{ store.isSuperAdmin ? 'Admin Operations' : 'Secretary Hub' }}</span>
          </div>
          <span v-if="pendingCount > 0" class="px-2 py-0.5 rounded-full bg-rose-500 text-white font-black text-[10px]">
            {{ pendingCount }}
          </span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/profile" 
          class="flex items-center px-4 py-3.5 rounded-2xl font-bold text-xs transition-all space-x-3 cursor-pointer min-h-[44px]"
          :class="route.name === 'dashboard-profile' 
            ? 'bg-blue-600 text-white shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#27272a]'"
        >
          <User class="w-5 h-5 flex-shrink-0" />
          <span>My Profile</span>
        </RouterLink>

      </nav>

      <!-- Desktop PWA Install Banner -->
      <div v-if="!isAppInstalled" class="p-4 bg-blue-500/10 border border-blue-500/30 rounded-2xl space-y-2">
        <div class="flex items-center space-x-2 text-blue-600 dark:text-blue-400 font-black text-xs">
          <Download class="w-4 h-4" />
          <span>Install SmartBand PWA</span>
        </div>
        <p class="text-[11px] text-slate-600 dark:text-neutral-400 leading-tight">Install SmartBand directly on your device for instant offline access.</p>
        <button @click="handleInstallPWA" type="button" class="w-full py-2.5 bg-blue-600 hover:bg-blue-500 text-white font-extrabold text-xs rounded-xl shadow-xs cursor-pointer min-h-[44px]">
          Install App
        </button>
      </div>

      <!-- Desktop Installed Badge -->
      <div v-else class="p-3.5 bg-emerald-500/10 border border-emerald-500/30 rounded-2xl flex items-center space-x-2 text-emerald-600 dark:text-emerald-400 font-black text-xs">
        <CheckCircle class="w-4 h-4 flex-shrink-0" />
        <span>App Installed & Ready</span>
      </div>

      <!-- User Profile Summary & Sign Out -->
      <div class="pt-4 border-t border-slate-200 dark:border-neutral-800/80 flex items-center justify-between">
        <div class="min-w-0 pr-2">
          <p class="font-black text-xs text-slate-900 dark:text-white truncate">{{ store.profile?.full_name || 'Member' }}</p>
          <p class="text-[10px] text-slate-400 dark:text-neutral-500 uppercase tracking-wider font-extrabold">{{ store.profile?.role || 'Member' }}</p>
        </div>
        <button @click="handleSignOut" type="button" class="p-2 rounded-xl text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-950/40 cursor-pointer min-w-[44px] min-h-[44px] flex items-center justify-center" title="Sign Out">
          <LogOut class="w-4 h-4" />
        </button>
      </div>

    </aside>

    <!-- MAIN RESPONSIVE CANVAS AREA -->
    <div class="flex-1 min-w-0 min-h-screen flex flex-col max-w-6xl mx-auto w-full">
      
      <!-- MATTE BLACK MOBILE TOP HEADER -->
      <header class="sticky top-0 z-40 bg-white/90 dark:bg-[#121214]/95 backdrop-blur-xl border-b border-slate-200/80 dark:border-neutral-800/80 px-4 py-3 flex items-center justify-between shadow-xs">
        <div class="flex items-center space-x-2.5">
          <div class="bg-blue-600 p-1.5 rounded-xl shadow-sm text-white">
            <Music class="w-5 h-5" stroke-width="2.5" />
          </div>
          <span class="font-black text-lg tracking-tight text-slate-900 dark:text-white">SmartBand</span>
        </div>

        <div class="flex items-center space-x-2">
          <!-- Install App Header Trigger -->
          <button 
            v-if="!isAppInstalled"
            @click="handleInstallPWA"
            type="button"
            class="p-2 rounded-xl bg-blue-600 text-white font-extrabold text-xs flex items-center hover:bg-blue-500 transition-colors shadow-xs cursor-pointer min-h-[44px]"
            aria-label="Install SmartBand App"
          >
            <Download class="w-4 h-4 mr-1" /> Install App
          </button>

          <!-- Quick Mobile Theme Switcher (Sun/Moon) -->
          <button 
            @click="toggleTheme" 
            type="button"
            class="p-2 rounded-full bg-slate-100 dark:bg-[#27272a] text-slate-700 dark:text-blue-400 hover:bg-slate-200 dark:hover:bg-[#323238] transition-colors border border-transparent dark:border-neutral-700/60 min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"
            :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
            title="Toggle Light/Dark Theme"
          >
            <Sun v-if="isDark" class="w-5 h-5 text-amber-400" />
            <Moon v-else class="w-5 h-5 text-blue-600" />
          </button>

          <!-- Notification & Settings Drawer Bell Trigger -->
          <button 
            @click="showSettingsDrawer = true"
            type="button"
            class="p-2 rounded-full bg-slate-100 dark:bg-[#27272a] text-slate-700 dark:text-blue-400 hover:bg-slate-200 dark:hover:bg-[#323238] transition-colors border border-transparent dark:border-neutral-700/60 min-w-[44px] min-h-[44px] flex items-center justify-center relative cursor-pointer"
            aria-label="Open App Settings & Alerts Drawer"
            title="Open App Settings"
          >
            <Bell class="w-5 h-5" />
            <span v-if="pendingCount > 0" class="absolute top-1 right-1 w-2.5 h-2.5 bg-rose-500 rounded-full animate-pulse"></span>
          </button>
        </div>
      </header>

      <!-- FIRST-TIME USER NOTIFICATION PROMPT BANNER -->
      <Transition name="toast">
        <div 
          v-if="showFirstTimeNotifPrompt"
          class="bg-gradient-to-r from-blue-600 to-indigo-700 text-white px-4 py-3 shadow-lg flex items-center justify-between border-b border-blue-500/40 text-xs font-bold"
        >
          <div class="flex items-center space-x-2.5 pr-2 min-w-0">
            <Bell class="w-5 h-5 flex-shrink-0 animate-bounce text-yellow-300" />
            <div class="min-w-0">
              <span class="font-black block text-white">Enable 10–15m Call-Time Alarm?</span>
              <span class="text-[11px] font-semibold opacity-90 block truncate">Audible siren & notifications for upcoming rehearsals and gigs.</span>
            </div>
          </div>
          <div class="flex items-center space-x-1.5 flex-shrink-0">
            <button 
              @click="requestNotificationPermission" 
              type="button" 
              class="px-3 py-1.5 bg-white text-blue-700 font-black rounded-xl shadow-xs text-[11px] hover:bg-slate-100 min-h-[36px] cursor-pointer"
            >
              Allow
            </button>
            <button 
              @click="dismissFirstTimeNotifPrompt" 
              type="button" 
              class="p-1.5 text-white/80 hover:text-white min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer"
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
          class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-sm w-11/12 bg-slate-900 dark:bg-[#1c1c1e] text-white px-4 py-3 rounded-2xl shadow-2xl border border-neutral-700/80 flex items-center justify-between font-extrabold text-xs"
        >
          <div class="flex items-center space-x-2">
            <CheckCircle class="w-4 h-4 text-emerald-400 flex-shrink-0" />
            <span>{{ networkToastMsg }}</span>
          </div>
        </div>
      </Transition>

      <!-- Main Router Page Body -->
      <main class="flex-1 p-4 sm:p-6 lg:p-8 overflow-y-auto pb-24 md:pb-8">
        <RouterView />
      </main>

      <!-- MOBILE BOTTOM NAVIGATION BAR (Neutral Matte Charcoal) -->
      <nav 
        class="md:hidden fixed bottom-0 left-0 w-full bg-white/95 dark:bg-[#1c1c1e]/95 backdrop-blur-xl border-t border-slate-200 dark:border-neutral-800/80 shadow-[0_-4px_16px_rgba(0,0,0,0.1)] dark:shadow-[0_-4px_16px_rgba(0,0,0,0.6)] pb-safe z-50"
        aria-label="Bottom Navigation Bar"
      >
        <div class="flex justify-around items-center h-16 px-1 max-w-md mx-auto" role="menubar">
          
          <RouterLink 
            to="/dashboard" 
            role="menuitem"
            aria-label="Home Dashboard Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors group min-h-[44px]"
            :class="route.name === 'dashboard-home' ? 'text-blue-600 dark:text-blue-400 font-black' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
          >
            <Home class="w-5 h-5 mb-0.5 group-active:scale-95 transition-transform" :stroke-width="route.name === 'dashboard-home' ? 2.5 : 2" />
            <span class="text-[9px] sm:text-[10px] font-bold">Home</span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/schedule" 
            role="menuitem"
            aria-label="Events Schedule Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors group min-h-[44px]"
            :class="route.name === 'dashboard-schedule' ? 'text-blue-600 dark:text-blue-400 font-black' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
          >
            <Calendar class="w-5 h-5 mb-0.5 group-active:scale-95 transition-transform" :stroke-width="route.name === 'dashboard-schedule' ? 2.5 : 2" />
            <span class="text-[9px] sm:text-[10px] font-bold">Events</span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/members" 
            role="menuitem"
            aria-label="Band Member Directory Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors group min-h-[44px]"
            :class="route.name === 'dashboard-members' ? 'text-blue-600 dark:text-blue-400 font-black' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
          >
            <Users class="w-5 h-5 mb-0.5 group-active:scale-95 transition-transform" :stroke-width="route.name === 'dashboard-members' ? 2.5 : 2" />
            <span class="text-[9px] sm:text-[10px] font-bold">Roster</span>
          </RouterLink>

          <RouterLink 
            v-if="store.isSuperAdmin || store.isSecretaryAdmin"
            to="/dashboard/admin" 
            role="menuitem"
            aria-label="Admin Operations Hub Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors group relative min-h-[44px]"
            :class="route.name === 'dashboard-admin' ? 'text-blue-600 dark:text-blue-400 font-black' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
          >
            <ShieldCheck class="w-5 h-5 mb-0.5 group-active:scale-95 transition-transform text-blue-500" :stroke-width="route.name === 'dashboard-admin' ? 2.5 : 2" />
            <span class="text-[9px] sm:text-[10px] font-bold">{{ store.isSuperAdmin ? 'Admin' : 'Secretary' }}</span>
            <span v-if="pendingCount > 0" class="absolute top-2 right-3 w-2 h-2 bg-rose-500 rounded-full animate-ping"></span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/profile" 
            role="menuitem"
            aria-label="User Profile Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors group min-h-[44px]"
            :class="route.name === 'dashboard-profile' ? 'text-blue-600 dark:text-blue-400 font-black' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
          >
            <User class="w-5 h-5 mb-0.5 group-active:scale-95 transition-transform" :stroke-width="route.name === 'dashboard-profile' ? 2.5 : 2" />
            <span class="text-[9px] sm:text-[10px] font-bold">Profile</span>
          </RouterLink>

        </div>
      </nav>

    </div>

    <!-- HIGH-VISIBILITY 5-SECOND CALL-TIME ALARM MODAL -->
    <Transition name="toast">
      <div v-if="activeAlarmModal" class="fixed inset-0 bg-black/90 backdrop-blur-md z-50 flex items-center justify-center p-4">
        <div class="bg-gradient-to-b from-amber-400 via-yellow-400 to-amber-500 text-slate-900 border-4 border-slate-900 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-center animate-bounce">
          
          <div class="w-16 h-16 rounded-full bg-slate-900 text-yellow-400 flex items-center justify-center mx-auto shadow-lg">
            <Volume2 class="w-8 h-8 animate-pulse" />
          </div>

          <div>
            <span class="inline-block px-3 py-1 bg-slate-900 text-white text-[11px] font-black uppercase rounded-full tracking-wider mb-2">
              🚨 CALL-TIME ALARM ACTIVE
            </span>
            <h2 class="text-2xl font-black text-slate-900 leading-tight">
              {{ activeAlarmModal.title }}
            </h2>
            <p class="text-sm font-black text-rose-950 mt-1 uppercase tracking-wide">
              {{ activeAlarmModal.countdownText }}
            </p>
          </div>

          <div class="bg-white/90 p-3 rounded-2xl space-y-1.5 text-xs font-bold text-slate-900 text-left">
            <div class="flex items-center"><Clock class="w-4 h-4 mr-2 text-slate-700" /> Scheduled Time: {{ activeAlarmModal.timeText }}</div>
            <div class="flex items-center"><MapPin class="w-4 h-4 mr-2 text-slate-700" /> Location: {{ activeAlarmModal.location }}</div>
          </div>

          <button 
            @click="dismissActiveAlarm"
            type="button"
            class="w-full py-4 bg-slate-900 hover:bg-black text-white font-black text-sm rounded-2xl shadow-xl active:scale-95 cursor-pointer min-h-[52px]"
          >
            ✓ I Am Ready / Stop Alarm
          </button>

        </div>
      </div>
    </Transition>

    <!-- APP SETTINGS & NOTIFICATIONS DRAWER MODAL (Neutral Matte Black) -->
    <div v-if="showSettingsDrawer" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left">
        
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2 text-blue-600 dark:text-blue-400">
            <Bell class="w-5 h-5" />
            <h3 class="font-black text-lg text-slate-900 dark:text-white">App Settings & Alerts</h3>
          </div>
          <button @click="showSettingsDrawer = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div class="space-y-3">
          <!-- Network Sync Badge -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80">
            <div class="flex items-center space-x-2">
              <Wifi v-if="isOnline" class="w-4 h-4 text-emerald-500" />
              <WifiOff v-else class="w-4 h-4 text-rose-500" />
              <span class="text-xs font-bold text-slate-900 dark:text-neutral-200">{{ isOnline ? 'PWA Online Sync' : 'Offline Countdown Mode' }}</span>
            </div>
            <span class="w-2 h-2 rounded-full" :class="isOnline ? 'bg-emerald-500 animate-pulse' : 'bg-rose-500'"></span>
          </div>

          <!-- Test Alarm Tone Button -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80">
            <div>
              <p class="font-bold text-xs text-slate-900 dark:text-white">Band Call-Time Siren</p>
              <p class="text-[10px] text-slate-400 dark:text-neutral-500">5-second brass alarm tone</p>
            </div>
            <button 
              @click="testAlarmTone"
              type="button"
              class="px-3 py-2 bg-blue-600 hover:bg-blue-500 text-white font-extrabold text-xs rounded-xl shadow-xs cursor-pointer min-h-[44px] flex items-center"
            >
              <Volume2 class="w-4 h-4 mr-1" /> Test Alarm
            </button>
          </div>

          <!-- PWA Install Status in Drawer -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80">
            <div>
              <p class="font-bold text-xs text-slate-900 dark:text-white">App Installation</p>
              <p class="text-[10px] text-slate-400 dark:text-neutral-500">
                {{ isAppInstalled ? 'Installed as standalone app' : 'Install for offline home screen launch' }}
              </p>
            </div>
            
            <div v-if="isAppInstalled" class="flex items-center space-x-1 px-3 py-1.5 bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 rounded-xl font-extrabold text-xs">
              <Check class="w-4 h-4" />
              <span>Installed</span>
            </div>
            
            <button 
              v-else
              @click="handleInstallPWA"
              type="button"
              class="px-3 py-2 bg-blue-600 hover:bg-blue-500 text-white font-extrabold text-xs rounded-xl shadow-xs cursor-pointer min-h-[44px]"
            >
              Install App
            </button>
          </div>

          <!-- Push Notifications Toggle -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80">
            <div>
              <p class="font-bold text-xs text-slate-900 dark:text-white">10–15m Call-Time Alerts</p>
              <p class="text-[10px] text-slate-400 dark:text-neutral-500 capitalize">Status: {{ notificationPermission }}</p>
            </div>
            <button 
              @click="requestNotificationPermission"
              type="button"
              class="px-3 py-2 bg-slate-200 dark:bg-[#323238] text-slate-900 dark:text-white font-extrabold text-xs rounded-xl cursor-pointer min-h-[44px]"
            >
              {{ notificationPermission === 'granted' ? 'Active ✓' : 'Enable' }}
            </button>
          </div>

          <!-- Theme Mode Toggle -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80">
            <div class="flex items-center space-x-2">
              <Sun v-if="isDark" class="w-4 h-4 text-amber-400" />
              <Moon v-else class="w-4 h-4 text-blue-600" />
              <span class="text-xs font-bold text-slate-900 dark:text-neutral-200">Theme Mode</span>
            </div>
            <button 
              @click="toggleTheme"
              type="button"
              class="px-3 py-2 bg-slate-200 dark:bg-[#323238] text-slate-900 dark:text-white font-extrabold text-xs rounded-xl cursor-pointer min-h-[44px]"
            >
              {{ isDark ? 'Dark Mode' : 'Light Mode' }}
            </button>
          </div>

          <!-- View Terms & Conditions -->
          <button 
            @click="showTermsModal = true"
            type="button"
            class="w-full flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 text-xs font-bold text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer"
          >
            <span class="flex items-center"><FileText class="w-4 h-4 mr-2 text-blue-500" /> View Terms & Conditions</span>
            <span class="text-slate-400">→</span>
          </button>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800 pb-1 flex justify-end">
          <button @click="showSettingsDrawer = false" type="button" class="py-2.5 px-4 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl min-h-[44px] cursor-pointer">
            Close Settings
          </button>
        </div>

      </div>
    </div>

    <!-- TERMS & CONDITIONS MODAL (Neutral Matte Black) -->
    <div v-if="showTermsModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left max-h-[80vh] flex flex-col">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2 text-blue-600 dark:text-blue-400">
            <FileText class="w-5 h-5" />
            <h3 class="font-black text-lg text-slate-900 dark:text-white">Terms & Conditions</h3>
          </div>
          <button @click="showTermsModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div class="overflow-y-auto flex-1 text-xs text-slate-600 dark:text-neutral-300 space-y-3.5 pr-2 leading-relaxed font-medium">
          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 1: Master List Verification Requirement</h4>
            <p>All sign-ups are provisional until physically verified by the IT Super Admin against the official municipal band registry.</p>
          </div>

          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 2: Attendance & RSVP Reliability Scoring</h4>
            <p>RSVPing "I Will Attend" creates an operational commitment for gig planning. Unexcused absences or sudden cancellations directly impact your personal Reliability Score (%).</p>
          </div>

          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 3: Call-Time Punctuality & Alert Protocols</h4>
            <p>Musicians must adhere to designated call times for rehearsals, parades, funeral services, and concerts. The in-app 10–15m call-time alarms serve as operational notifications.</p>
          </div>

          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 4: Band Property & Instrument Care</h4>
            <p>Members issued municipal band instruments, uniforms, or sheet music folios are strictly responsible for their maintenance, safekeeping, and prompt return upon request.</p>
          </div>

          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 5: Data Privacy & Security</h4>
            <p>Member contact numbers and personal birth dates are protected under Row Level Security (RLS) and will never be exposed to public directory views.</p>
          </div>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800">
          <button @click="showTermsModal = false" type="button" class="w-full py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer">
            Close
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
