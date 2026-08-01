<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { RouterView, RouterLink, useRoute } from 'vue-router'
import { Home, Calendar, User, Sun, Moon, Music, Users, ShieldCheck, Download, Wifi, WifiOff, LogOut, Bell, BellOff, FileText, X, CheckCircle, AlertCircle } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useRouter } from 'vue-router'
import { supabase } from '@/supabase'

const route = useRoute()
const router = useRouter()
const store = useMainStore()
const isDark = ref(true)

// PWA Install Event State
const deferredPrompt = ref(null)
const showInstallBanner = ref(false)

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

const updateNetworkStatus = () => {
  const wasOnline = isOnline.value
  isOnline.value = navigator.onLine
  if (!wasOnline && isOnline.value) {
    showNetworkToast('🟢 Back Online! Synchronized latest band data.')
  } else if (wasOnline && !isOnline.value) {
    showNetworkToast('⚡ Operating Offline. Using last synced data.')
  }
}

const showNetworkToast = (msg) => {
  networkToastMsg.value = msg
  setTimeout(() => { networkToastMsg.value = '' }, 4000)
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
  if (!deferredPrompt.value) {
    alert('To install SmartBand:\n• Mobile: Tap Share / Menu → Add to Home Screen.\n• Desktop: Click the Install icon in your browser address bar.')
    return
  }
  deferredPrompt.value.prompt()
  const { outcome } = await deferredPrompt.value.userChoice
  if (outcome === 'accepted') {
    showInstallBanner.value = false
  }
  deferredPrompt.value = null
}

const requestNotificationPermission = async () => {
  if (!('Notification' in window)) {
    alert('Notifications are not supported on this browser.')
    return
  }
  const result = await Notification.requestPermission()
  notificationPermission.value = result
  showFirstTimeNotifPrompt.value = false
}

const dismissFirstTimeNotifPrompt = () => {
  showFirstTimeNotifPrompt.value = false
  localStorage.setItem('smartband_notif_prompt_dismissed', 'true')
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

  // PWA Install Prompt Listener
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault()
    deferredPrompt.value = e
    showInstallBanner.value = true
  })

  // Network State Listener
  window.addEventListener('online', updateNetworkStatus)
  window.addEventListener('offline', updateNetworkStatus)

  // First-Time User Notification Prompt Trigger
  if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
    const dismissed = localStorage.getItem('smartband_notif_prompt_dismissed')
    if (!dismissed) {
      showFirstTimeNotifPrompt.value = true
    }
  }

  fetchPendingCount()
})

onUnmounted(() => {
  window.removeEventListener('online', updateNetworkStatus)
  window.removeEventListener('offline', updateNetworkStatus)
})
</script>

<template>
  <div class="min-h-screen bg-slate-100 dark:bg-black text-slate-900 dark:text-neutral-100 flex transition-colors duration-300">
    
    <!-- DESKTOP LEFT NAVIGATION SIDEBAR -->
    <aside class="hidden md:flex md:w-64 lg:w-72 flex-col bg-white dark:bg-[#121214] border-r border-slate-200 dark:border-neutral-800 p-5 space-y-6 flex-shrink-0 min-h-screen sticky top-0 h-screen overflow-y-auto">
      
      <!-- Brand Logo -->
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class="bg-yellow-400 p-2 rounded-2xl shadow-md">
            <Music class="w-6 h-6 text-slate-900" stroke-width="3" />
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
          class="p-2 rounded-xl bg-slate-100 dark:bg-[#1c1c1e] text-slate-700 dark:text-yellow-400 hover:bg-slate-200 dark:hover:bg-neutral-800 transition-colors border border-transparent dark:border-neutral-800 cursor-pointer min-w-[40px] min-h-[40px] flex items-center justify-center"
          :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
          title="Toggle Light/Dark Theme"
        >
          <Sun v-if="isDark" class="w-4 h-4 text-yellow-400" />
          <Moon v-else class="w-4 h-4 text-slate-700" />
        </button>
      </div>

      <!-- Desktop Sidebar Menu -->
      <nav class="space-y-1.5 flex-1" aria-label="Desktop Navigation Menu">
        
        <RouterLink 
          to="/dashboard" 
          class="flex items-center px-4 py-3.5 rounded-2xl font-bold text-xs transition-all space-x-3 cursor-pointer min-h-[44px]"
          :class="route.name === 'dashboard-home' 
            ? 'bg-yellow-400 text-slate-900 shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#1c1c1e]'"
        >
          <Home class="w-5 h-5 flex-shrink-0" />
          <span>Home Dashboard</span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/schedule" 
          class="flex items-center px-4 py-3.5 rounded-2xl font-bold text-xs transition-all space-x-3 cursor-pointer min-h-[44px]"
          :class="route.name === 'dashboard-schedule' 
            ? 'bg-yellow-400 text-slate-900 shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#1c1c1e]'"
        >
          <Calendar class="w-5 h-5 flex-shrink-0" />
          <span>Schedule & Events</span>
        </RouterLink>

        <RouterLink 
          to="/dashboard/members" 
          class="flex items-center px-4 py-3.5 rounded-2xl font-bold text-xs transition-all space-x-3 cursor-pointer min-h-[44px]"
          :class="route.name === 'dashboard-members' 
            ? 'bg-yellow-400 text-slate-900 shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#1c1c1e]'"
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
            ? 'bg-yellow-400 text-slate-900 shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#1c1c1e]'"
        >
          <div class="flex items-center space-x-3">
            <ShieldCheck class="w-5 h-5 flex-shrink-0 text-amber-500" />
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
            ? 'bg-yellow-400 text-slate-900 shadow-md font-black' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#1c1c1e]'"
        >
          <User class="w-5 h-5 flex-shrink-0" />
          <span>My Profile</span>
        </RouterLink>

      </nav>

      <!-- Desktop PWA Install Button Banner -->
      <div class="p-4 bg-yellow-400/10 border border-yellow-400/30 rounded-2xl space-y-2">
        <div class="flex items-center space-x-2 text-yellow-600 dark:text-yellow-400 font-black text-xs">
          <Download class="w-4 h-4" />
          <span>Install SmartBand PWA</span>
        </div>
        <p class="text-[11px] text-slate-600 dark:text-neutral-400 leading-tight">Install SmartBand directly on your device for instant offline access.</p>
        <button @click="handleInstallPWA" type="button" class="w-full py-2.5 bg-yellow-400 text-slate-900 font-extrabold text-xs rounded-xl shadow-xs cursor-pointer min-h-[44px]">
          Install App
        </button>
      </div>

      <!-- User Profile Summary & Sign Out -->
      <div class="pt-4 border-t border-slate-200 dark:border-neutral-800 flex items-center justify-between">
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
    <div class="flex-1 min-h-screen flex flex-col max-w-6xl mx-auto w-full">
      
      <!-- MATTE BLACK MOBILE TOP HEADER -->
      <header class="sticky top-0 z-40 bg-white/85 dark:bg-black/90 backdrop-blur-xl border-b border-slate-200/80 dark:border-neutral-800/80 px-4 py-3 flex items-center justify-between shadow-xs">
        <div class="flex items-center space-x-2.5">
          <div class="bg-yellow-400 p-1.5 rounded-xl shadow-sm">
            <Music class="w-5 h-5 text-slate-900" stroke-width="3" />
          </div>
          <span class="font-black text-lg tracking-tight text-slate-900 dark:text-white">SmartBand</span>
        </div>

        <div class="flex items-center space-x-2">
          <!-- Install App Header Trigger -->
          <button 
            @click="handleInstallPWA"
            type="button"
            class="p-2 rounded-xl bg-yellow-400 text-slate-900 font-extrabold text-xs flex items-center hover:bg-yellow-500 transition-colors shadow-xs cursor-pointer min-h-[44px]"
            aria-label="Install SmartBand App"
          >
            <Download class="w-4 h-4 mr-1" /> Install App
          </button>

          <!-- Quick Mobile Theme Switcher (Sun/Moon) -->
          <button 
            @click="toggleTheme" 
            type="button"
            class="p-2 rounded-full bg-slate-100 dark:bg-[#1c1c1e] text-slate-700 dark:text-yellow-400 hover:bg-slate-200 dark:hover:bg-neutral-800 transition-colors border border-transparent dark:border-neutral-800 min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"
            :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
            title="Toggle Light/Dark Theme"
          >
            <Sun v-if="isDark" class="w-5 h-5 text-yellow-400" />
            <Moon v-else class="w-5 h-5 text-slate-700" />
          </button>

          <!-- Notification & Settings Drawer Bell Trigger -->
          <button 
            @click="showSettingsDrawer = true"
            type="button"
            class="p-2 rounded-full bg-slate-100 dark:bg-[#1c1c1e] text-slate-700 dark:text-yellow-400 hover:bg-slate-200 dark:hover:bg-neutral-800 transition-colors border border-transparent dark:border-neutral-800 min-w-[44px] min-h-[44px] flex items-center justify-center relative cursor-pointer"
            aria-label="Open App Settings & Alerts Drawer"
            title="Open App Settings"
          >
            <Bell class="w-5 h-5" />
            <span v-if="pendingCount > 0" class="absolute top-1 right-1 w-2.5 h-2.5 bg-rose-500 rounded-full animate-pulse"></span>
          </button>
        </div>
      </header>

      <!-- FIRST-TIME USER AUTOMATIC NOTIFICATION PROMPT BANNER -->
      <Transition name="toast">
        <div 
          v-if="showFirstTimeNotifPrompt"
          class="bg-gradient-to-r from-yellow-400 via-amber-400 to-yellow-500 text-slate-900 px-4 py-3 shadow-lg flex items-center justify-between border-b border-yellow-500/40 text-xs font-bold"
        >
          <div class="flex items-center space-x-2.5 pr-2 min-w-0">
            <Bell class="w-5 h-5 flex-shrink-0 animate-bounce text-slate-900" />
            <div class="min-w-0">
              <span class="font-black block text-slate-900">Enable Push Notifications?</span>
              <span class="text-[11px] font-semibold opacity-90 block truncate">Get instant call-time alerts & urgent schedule updates.</span>
            </div>
          </div>
          <div class="flex items-center space-x-1.5 flex-shrink-0">
            <button 
              @click="requestNotificationPermission" 
              type="button" 
              class="px-3 py-1.5 bg-slate-900 text-white font-extrabold rounded-xl shadow-xs text-[11px] hover:bg-black min-h-[36px] cursor-pointer"
            >
              Allow
            </button>
            <button 
              @click="dismissFirstTimeNotifPrompt" 
              type="button" 
              class="p-1.5 text-slate-800 hover:text-black min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer"
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
          class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-xs w-11/12 bg-slate-900 dark:bg-[#121214] text-white px-4 py-3 rounded-2xl shadow-2xl border border-yellow-400/40 flex items-center justify-between font-extrabold text-xs"
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

      <!-- MATTE BLACK MOBILE BOTTOM NAVIGATION BAR -->
      <nav 
        class="md:hidden fixed bottom-0 left-0 w-full bg-white/90 dark:bg-[#121214]/95 backdrop-blur-xl border-t border-slate-200 dark:border-neutral-800 shadow-[0_-4px_16px_rgba(0,0,0,0.1)] dark:shadow-[0_-4px_16px_rgba(0,0,0,0.6)] pb-safe z-50"
        aria-label="Bottom Navigation Bar"
      >
        <div class="flex justify-around items-center h-16 px-1 max-w-md mx-auto" role="menubar">
          
          <RouterLink 
            to="/dashboard" 
            role="menuitem"
            aria-label="Home Dashboard Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors group min-h-[44px]"
            :class="route.name === 'dashboard-home' ? 'text-yellow-500 dark:text-yellow-400' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
          >
            <Home class="w-5 h-5 mb-0.5 group-active:scale-95 transition-transform" :stroke-width="route.name === 'dashboard-home' ? 2.5 : 2" />
            <span class="text-[9px] sm:text-[10px] font-bold">Home</span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/schedule" 
            role="menuitem"
            aria-label="Events Schedule Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors group min-h-[44px]"
            :class="route.name === 'dashboard-schedule' ? 'text-yellow-500 dark:text-yellow-400' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
          >
            <Calendar class="w-5 h-5 mb-0.5 group-active:scale-95 transition-transform" :stroke-width="route.name === 'dashboard-schedule' ? 2.5 : 2" />
            <span class="text-[9px] sm:text-[10px] font-bold">Events</span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/members" 
            role="menuitem"
            aria-label="Band Member Directory Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors group min-h-[44px]"
            :class="route.name === 'dashboard-members' ? 'text-yellow-500 dark:text-yellow-400' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
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
            :class="route.name === 'dashboard-admin' ? 'text-yellow-500 dark:text-yellow-400' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
          >
            <ShieldCheck class="w-5 h-5 mb-0.5 group-active:scale-95 transition-transform text-amber-500" :stroke-width="route.name === 'dashboard-admin' ? 2.5 : 2" />
            <span class="text-[9px] sm:text-[10px] font-bold">{{ store.isSuperAdmin ? 'Admin' : 'Secretary' }}</span>
            <span v-if="pendingCount > 0" class="absolute top-2 right-3 w-2 h-2 bg-rose-500 rounded-full animate-ping"></span>
          </RouterLink>

          <RouterLink 
            to="/dashboard/profile" 
            role="menuitem"
            aria-label="User Profile Tab"
            class="flex flex-col items-center justify-center flex-1 h-full transition-colors group min-h-[44px]"
            :class="route.name === 'dashboard-profile' ? 'text-yellow-500 dark:text-yellow-400' : 'text-slate-400 dark:text-neutral-500 hover:text-slate-600 dark:hover:text-neutral-300'"
          >
            <User class="w-5 h-5 mb-0.5 group-active:scale-95 transition-transform" :stroke-width="route.name === 'dashboard-profile' ? 2.5 : 2" />
            <span class="text-[9px] sm:text-[10px] font-bold">Profile</span>
          </RouterLink>

        </div>
      </nav>

    </div>

    <!-- DEDICATED APP SETTINGS & NOTIFICATIONS DRAWER MODAL -->
    <div v-if="showSettingsDrawer" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#121214] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left">
        
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2 text-yellow-500">
            <Bell class="w-5 h-5" />
            <h3 class="font-black text-lg text-slate-900 dark:text-white">App Settings & Alerts</h3>
          </div>
          <button @click="showSettingsDrawer = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div class="space-y-3">
          <!-- Network Sync Badge -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800">
            <div class="flex items-center space-x-2">
              <Wifi v-if="isOnline" class="w-4 h-4 text-emerald-500" />
              <WifiOff v-else class="w-4 h-4 text-rose-500" />
              <span class="text-xs font-bold text-slate-900 dark:text-neutral-200">{{ isOnline ? 'PWA Online Sync' : 'Offline Mode' }}</span>
            </div>
            <span class="w-2 h-2 rounded-full" :class="isOnline ? 'bg-emerald-500 animate-pulse' : 'bg-rose-500'"></span>
          </div>

          <!-- PWA Install Button in Drawer -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800">
            <div>
              <p class="font-bold text-xs text-slate-900 dark:text-white">PWA App Installation</p>
              <p class="text-[10px] text-slate-400 dark:text-neutral-500">Install for offline home screen launch</p>
            </div>
            <button 
              @click="handleInstallPWA"
              type="button"
              class="px-3 py-2 bg-yellow-400 text-slate-900 font-extrabold text-xs rounded-xl shadow-xs cursor-pointer min-h-[44px]"
            >
              Install App
            </button>
          </div>

          <!-- Push Notifications Toggle -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800">
            <div>
              <p class="font-bold text-xs text-slate-900 dark:text-white">Push Notifications</p>
              <p class="text-[10px] text-slate-400 dark:text-neutral-500 capitalize">Status: {{ notificationPermission }}</p>
            </div>
            <button 
              @click="requestNotificationPermission"
              type="button"
              class="px-3 py-2 bg-slate-200 dark:bg-[#27272a] text-slate-900 dark:text-white font-extrabold text-xs rounded-xl cursor-pointer min-h-[44px]"
            >
              {{ notificationPermission === 'granted' ? 'Enabled' : 'Enable' }}
            </button>
          </div>

          <!-- Theme Mode Toggle -->
          <div class="flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800">
            <div class="flex items-center space-x-2">
              <Sun v-if="isDark" class="w-4 h-4 text-yellow-400" />
              <Moon v-else class="w-4 h-4 text-slate-700" />
              <span class="text-xs font-bold text-slate-900 dark:text-neutral-200">Theme Mode</span>
            </div>
            <button 
              @click="toggleTheme"
              type="button"
              class="px-3 py-2 bg-slate-200 dark:bg-[#27272a] text-slate-900 dark:text-white font-extrabold text-xs rounded-xl cursor-pointer min-h-[44px]"
            >
              {{ isDark ? 'Dark Mode' : 'Light Mode' }}
            </button>
          </div>

          <!-- View Terms & Conditions -->
          <button 
            @click="showTermsModal = true"
            type="button"
            class="w-full flex items-center justify-between p-3 rounded-2xl bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 text-xs font-bold text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer"
          >
            <span class="flex items-center"><FileText class="w-4 h-4 mr-2 text-yellow-500" /> View Terms & Conditions</span>
            <span class="text-slate-400">→</span>
          </button>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800 flex justify-end">
          <button @click="showSettingsDrawer = false" type="button" class="py-2.5 px-4 bg-yellow-400 font-black text-xs text-slate-900 rounded-xl min-h-[44px] cursor-pointer">
            Close Settings
          </button>
        </div>

      </div>
    </div>

    <!-- TERMS & CONDITIONS MODAL -->
    <div v-if="showTermsModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#121214] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left max-h-[80vh] flex flex-col">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2 text-yellow-500">
            <FileText class="w-5 h-5" />
            <h3 class="font-black text-lg text-slate-900 dark:text-white">Terms & Conditions</h3>
          </div>
          <button @click="showTermsModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div class="overflow-y-auto flex-1 text-xs text-slate-600 dark:text-neutral-300 space-y-3 pr-1 leading-relaxed">
          <h4 class="font-black text-slate-900 dark:text-white">1. Master List Verification Requirement</h4>
          <p>All sign-ups are subject to physical verification against the municipal band master list by the IT Super Admin.</p>

          <h4 class="font-black text-slate-900 dark:text-white">2. Attendance & Reliability Policy</h4>
          <p>RSVPing "Will Attend" creates an operational commitment for gig scheduling. Failing to attend without prior excuse affects your personal Reliability Score (%).</p>

          <h4 class="font-black text-slate-900 dark:text-white">3. Data Privacy & Roster Rights</h4>
          <p>Personal phone numbers and private email addresses are protected under Row Level Security (RLS) and will never be exposed to public directory views.</p>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800">
          <button @click="showTermsModal = false" type="button" class="w-full py-3 bg-yellow-400 font-black text-xs text-slate-900 rounded-xl shadow-md min-h-[44px] cursor-pointer">
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
