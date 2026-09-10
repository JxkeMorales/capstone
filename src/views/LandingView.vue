<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { 
  Music, 
  Sun, 
  Moon, 
  ChevronLeft, 
  ChevronRight, 
  Shield, 
  Award, 
  Sparkles, 
  Activity
} from 'lucide-vue-next'
import { supabase } from '@/supabase'

const router = useRouter()
const isDark = ref(true)

const defaultPositions = [
  {
    key: 'president',
    titleCode: 'BAND PRESIDENT',
    role: 'Band President',
    shortTitle: 'President',
    shortCode: 'PR',
    name: 'Position To Be Appointed',
    image: null,
    responsibility: '',
    defaultInstrument: '',
  },
  {
    key: 'vice_president',
    titleCode: 'BAND VICE PRESIDENT',
    role: 'Band Vice President',
    shortTitle: 'Vice Pres.',
    shortCode: 'VP',
    name: 'Band Vice President',
    image: '/officers/bandvicepres.png',
    responsibility: '',
    defaultInstrument: '',
  },
  {
    key: 'secretary',
    titleCode: 'BAND SECRETARY',
    role: 'Band Secretary',
    shortTitle: 'Secretary',
    shortCode: 'SEC',
    name: 'Band Secretary',
    image: '/officers/bandsecretary.png',
    responsibility: '',
    defaultInstrument: '',
  },
  {
    key: 'treasurer',
    titleCode: 'BAND TREASURER',
    role: 'Band Treasurer',
    shortTitle: 'Treasurer',
    shortCode: 'TRE',
    name: 'Position To Be Appointed',
    image: null,
    responsibility: '',
    defaultInstrument: '',
  },
  {
    key: 'auditor',
    titleCode: 'BAND AUDITOR',
    role: 'Band Auditor',
    shortTitle: 'Auditor',
    shortCode: 'AUD',
    name: 'Band Auditor',
    image: '/officers/bandauditor.png',
    responsibility: '',
    defaultInstrument: '',
  },
  {
    key: 'resident_conductor',
    titleCode: 'RESIDENT CONDUCTOR',
    role: 'Resident Conductor',
    shortTitle: 'Conductor',
    shortCode: 'MA',
    name: 'Resident Conductor',
    image: '/officers/bandconductor.png',
    responsibility: '',
    defaultInstrument: '',
  },
  {
    key: 'band_manager',
    titleCode: 'BAND MANAGER',
    role: 'Band Manager',
    shortTitle: 'Manager',
    shortCode: 'MGR',
    name: 'Band Manager',
    image: '/officers/bandmanager.png',
    responsibility: '',
    defaultInstrument: '',
  },
  {
    key: 'coordinator',
    titleCode: 'BAND COORDINATOR',
    role: 'Band Coordinator',
    shortTitle: 'Coordinator',
    shortCode: 'COO',
    name: 'Band Coordinator',
    image: '/officers/bandcoordinator.png',
    responsibility: '',
    defaultInstrument: '',
  }
]

// Officers Data (Configured with real photos & blank official duties for custom editing)
const officers = ref(
  defaultPositions.map(pos => ({
    id: pos.key,
    titleCode: pos.titleCode,
    role: pos.role,
    shortTitle: pos.shortTitle,
    shortCode: pos.shortCode,
    name: pos.name,
    instrument: pos.defaultInstrument,
    responsibility: pos.responsibility,
    image: pos.image,
    isAssigned: !!pos.image
  }))
)

const fetchOfficers = async () => {
  try {
    const { data } = await supabase
      .from('profiles')
      .select('id, full_name, instrument, role, executive_title, profile_picture')
      .eq('is_verified', true)

    if (data && data.length > 0) {
      const mapOfficer = (pos) => {
        let member = null
        if (pos.key === 'secretary') {
          member = data.find(p => p.executive_title === 'secretary' || (p.role === 'secretary_admin' && !p.executive_title))
        } else if (pos.key === 'coordinator' || pos.key === 'admin') {
          member = data.find(p => p.executive_title === 'coordinator' || p.role === 'super_admin')
        } else {
          member = data.find(p => p.executive_title === pos.key)
        }

        if (member) {
          return {
            id: member.id,
            titleCode: pos.titleCode,
            role: pos.role,
            shortTitle: pos.shortTitle,
            shortCode: member.full_name ? member.full_name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase() : pos.shortCode,
            name: member.full_name || pos.name,
            instrument: member.instrument || pos.defaultInstrument,
            responsibility: pos.responsibility,
            image: member.profile_picture || pos.image,
            isAssigned: true
          }
        }
        return {
          id: pos.key,
          titleCode: pos.titleCode,
          role: pos.role,
          shortTitle: pos.shortTitle,
          shortCode: pos.shortCode,
          name: pos.name,
          instrument: pos.defaultInstrument,
          responsibility: pos.responsibility,
          image: pos.image,
          isAssigned: !!pos.image
        }
      }

      officers.value = defaultPositions.map(pos => mapOfficer(pos))
    }
  } catch (err) {
    console.warn('Could not fetch officers for landing page:', err)
  }
}

onMounted(() => {
  const savedTheme = localStorage.getItem('smartband_theme')
  if (savedTheme === 'light') {
    isDark.value = false
  } else if (savedTheme === 'dark') {
    isDark.value = true
  } else {
    isDark.value = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
  }
  window.addEventListener('keydown', handleKeyDown)
  fetchOfficers()
})

onUnmounted(() => {
  window.removeEventListener('keydown', handleKeyDown)
})

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

const goToLogin = () => {
  router.push('/login')
}

const selectedIndex = ref(0)
const currentOfficer = computed(() => officers.value[selectedIndex.value])
const prevIndex = computed(() => (selectedIndex.value - 1 + officers.value.length) % officers.value.length)
const nextIndex = computed(() => (selectedIndex.value + 1) % officers.value.length)

const selectOfficer = (idx) => {
  selectedIndex.value = idx
}

const nextOfficer = () => {
  selectedIndex.value = (selectedIndex.value + 1) % officers.value.length
}

const prevOfficer = () => {
  selectedIndex.value = (selectedIndex.value - 1 + officers.value.length) % officers.value.length
}

const handleKeyDown = (e) => {
  if (e.key === 'ArrowLeft') {
    prevOfficer()
  } else if (e.key === 'ArrowRight') {
    nextOfficer()
  }
}

// Avatar Container Scrolling & Visibility Helpers
const avatarScrollContainer = ref(null)
const avatarRefs = ref([])

const scrollToActiveAvatar = (idx) => {
  nextTick(() => {
    const el = avatarRefs.value[idx]
    if (el && avatarScrollContainer.value) {
      el.scrollIntoView({
        behavior: 'smooth',
        inline: 'center',
        block: 'nearest'
      })
    }
  })
}

watch(selectedIndex, (newIdx) => {
  scrollToActiveAvatar(newIdx)
})

const handleAvatarWheel = (e) => {
  const container = avatarScrollContainer.value
  if (!container) return
  if (container.scrollWidth > container.clientWidth) {
    if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
      e.preventDefault()
      container.scrollLeft += e.deltaY
    }
  }
}

// Infinite loop navigation for the profile switcher
const scrollAvatars = (direction) => {
  if (direction === 'left') {
    prevOfficer()
  } else {
    nextOfficer()
  }
}

// Touch Swipe Support for Character Carousel Stage
const touchStartX = ref(0)
const handleTouchStart = (e) => {
  if (e.changedTouches && e.changedTouches[0]) {
    touchStartX.value = e.changedTouches[0].screenX
  }
}
const handleTouchEnd = (e) => {
  if (e.changedTouches && e.changedTouches[0]) {
    const touchEndX = e.changedTouches[0].screenX
    const diff = touchStartX.value - touchEndX
    if (Math.abs(diff) > 40) {
      if (diff > 0) {
        nextOfficer()
      } else {
        prevOfficer()
      }
    }
  }
}
</script>

<template>
  <div class="min-h-screen bg-[#edf1f5] dark:bg-[#121214] text-slate-800 dark:text-white selection:bg-blue-600 selection:text-white font-sans overflow-x-hidden transition-colors duration-300">
    
    <!-- Navigation Bar (Soft Dimmed Glassmorphism in Light Mode) -->
    <nav class="fixed top-0 left-0 right-0 z-50 bg-[#edf1f5]/85 dark:bg-[#121214]/80 backdrop-blur-xl border-b border-slate-300/80 dark:border-neutral-800/50 transition-colors duration-300">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 h-20 flex items-center justify-between">
        <div class="flex items-center space-x-2.5 sm:space-x-3">
          <div class="p-2 sm:p-2.5 bg-blue-600 rounded-xl shadow-lg shadow-blue-900/20">
            <Music class="w-5 h-5 sm:w-6 sm:h-6 text-white" />
          </div>
          <span class="text-lg sm:text-xl font-black tracking-tight text-slate-800 dark:text-white">SmartBand</span>
        </div>
        <div class="flex items-center space-x-2 sm:space-x-3">
          <button 
            @click="toggleTheme" 
            title="Toggle theme"
            class="p-2 sm:p-2.5 rounded-xl bg-slate-200/90 hover:bg-slate-300 dark:bg-white/10 dark:hover:bg-white/20 text-slate-700 dark:text-white transition-all cursor-pointer border border-slate-300/60 dark:border-white/5 min-h-[40px] min-w-[40px] flex items-center justify-center"
          >
            <Sun v-if="!isDark" class="w-4 h-4 text-amber-600" />
            <Moon v-else class="w-4 h-4 text-blue-400" />
          </button>
          <button 
            @click="goToLogin" 
            class="text-xs sm:text-sm font-bold bg-slate-200/90 hover:bg-slate-300 dark:bg-white/10 dark:hover:bg-white/20 text-slate-800 dark:text-white px-3.5 sm:px-5 py-2 sm:py-2.5 rounded-xl transition-all border border-slate-300/60 dark:border-white/5 cursor-pointer shadow-xs min-h-[40px] flex items-center"
          >
            Member Login
          </button>
        </div>
      </div>
    </nav>

    <!-- Hero Section (Dimmed Light Palette, Non-Blinding) -->
    <main class="relative pt-32 pb-16 lg:pt-44 lg:pb-24 overflow-hidden flex items-center">
      <!-- Background Image with Dimmed Overlays -->
      <div class="absolute inset-0 z-0">
        <img 
          src="/hero-band.jpg" 
          alt="Municipal Band Performance" 
          class="w-full h-full object-cover object-center opacity-30 dark:opacity-40 scale-105" 
        />
        <div class="absolute inset-0 bg-gradient-to-t from-[#edf1f5] via-[#edf1f5]/85 dark:from-[#121214] dark:via-[#121214]/85 to-transparent transition-colors duration-300"></div>
        <div class="absolute inset-0 bg-gradient-to-r from-[#edf1f5] via-[#edf1f5]/75 dark:from-[#121214] dark:via-[#121214]/75 to-transparent transition-colors duration-300"></div>
      </div>

      <div class="relative z-10 max-w-7xl mx-auto px-6 w-full">
        <div class="max-w-3xl">
          <div class="inline-flex items-center space-x-2 bg-blue-600/10 border border-blue-600/20 text-blue-700 dark:text-blue-400 px-4 py-2 rounded-full text-xs font-bold uppercase tracking-widest mb-6">
            <span class="relative flex h-2 w-2 mr-1">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-500 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-blue-600"></span>
            </span>
            Band 1870
          </div>
          
          <h1 class="text-5xl sm:text-6xl lg:text-7xl font-black text-slate-800 dark:text-white leading-[1.08] tracking-tight mb-6 drop-shadow-xs">
            Symphonic <br/>
            <span class="text-transparent bg-clip-text bg-gradient-to-r from-blue-700 via-indigo-600 to-sky-600 dark:from-blue-400 dark:via-indigo-400 dark:to-sky-400">
              Precision.
            </span>
          </h1>
          
          <p class="text-lg sm:text-xl text-slate-600 dark:text-neutral-300 font-medium leading-relaxed max-w-2xl">
            The official portal for municipal band musicians. Synchronize rehearsal schedules, gig call-times, and performance reliability scores across the entire ensemble.
          </p>
        </div>
      </div>
    </main>

    <!-- Officers Character Selection Section -->
    <section class="py-16 lg:py-24 relative z-10 bg-[#e5ecf3]/70 dark:bg-[#151518]/90 border-t border-slate-300/80 dark:border-neutral-800/80 transition-colors duration-300">
      <div class="max-w-7xl mx-auto px-6">
        
        <!-- Section Header -->
        <div class="flex flex-col md:flex-row md:items-end justify-between mb-12">
          <div>
            <div class="inline-flex items-center space-x-2 text-blue-700 dark:text-blue-400 text-xs font-black uppercase tracking-widest mb-2 font-mono">
              <Sparkles class="w-4 h-4 text-blue-600 dark:text-blue-400" />
              <span>ROSTER // LEADERSHIP ARCHIVE</span>
            </div>
            <h2 class="text-3xl sm:text-4xl font-black text-slate-800 dark:text-white tracking-tight">
              Band 1870 Officers
            </h2>
          </div>
          <p class="text-sm text-slate-500 dark:text-neutral-400 max-w-md mt-2 md:mt-0 font-medium">
            Explore the executive officers, section leaders, and musical masters directing our ensemble's century-old legacy.
          </p>
        </div>

        <!-- Main Character Select Grid -->
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-10 items-center">
          
          <!-- LEFT SIDE: Character Selection Stage -->
          <div class="lg:col-span-6 xl:col-span-7 flex flex-col items-center w-full">
            
            <!-- Character Cards Carousel Stage -->
            <div 
              @touchstart="handleTouchStart"
              @touchend="handleTouchEnd"
              class="relative w-full flex items-center justify-center min-h-[420px] sm:min-h-[460px] overflow-hidden py-4 select-none"
            >
              
              <!-- Left Navigation Arrow -->
              <button 
                @click="prevOfficer"
                title="Previous Officer (Left Arrow)"
                class="absolute left-1 sm:left-3 z-40 w-11 h-11 sm:w-12 sm:h-12 rounded-2xl bg-[#f8fafc] dark:bg-[#1c1c21]/90 backdrop-blur-md border border-slate-300/90 dark:border-white/10 text-slate-700 dark:text-white flex items-center justify-center shadow-xl hover:scale-110 active:scale-95 hover:bg-blue-600 hover:text-white hover:border-blue-600 dark:hover:bg-blue-600 transition-all cursor-pointer group"
              >
                <ChevronLeft class="w-6 h-6 group-hover:-translate-x-0.5 transition-transform" />
              </button>

              <!-- Carousel Cards Wrapper -->
              <div class="flex items-center justify-center space-x-3 sm:space-x-5 w-full">
                
                <!-- PREVIOUS CARD (Visible on Tablets & Desktops) -->
                <div 
                  @click="prevOfficer"
                  class="hidden sm:flex flex-col relative w-36 md:w-44 h-[350px] md:h-[380px] rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 transform scale-95 border border-slate-300 dark:border-white/10 shadow-lg group opacity-60 hover:opacity-100 hover:scale-105 hover:border-blue-500 hover:shadow-2xl hover:shadow-blue-500/25 filter blur-[1px] z-10 hover:z-30 bg-slate-900"
                >
                  <img 
                    v-if="officers[prevIndex].image"
                    :src="officers[prevIndex].image" 
                    :alt="officers[prevIndex].name"
                    class="w-full h-full object-cover object-top brightness-90 group-hover:brightness-100 group-hover:scale-110 transition-all duration-500"
                  />
                  <div v-else class="w-full h-full flex flex-col items-center justify-center bg-gradient-to-b from-slate-800 to-slate-950 p-3 text-center">
                    <div class="w-12 h-12 rounded-xl bg-blue-600/20 border border-blue-500/30 flex items-center justify-center text-blue-400 mb-2">
                      <Music class="w-6 h-6" />
                    </div>
                  </div>
                  <div class="absolute inset-0 bg-gradient-to-t from-slate-950 via-slate-950/40 to-transparent pointer-events-none"></div>
                  
                  <!-- Top Preview Tag -->
                  <div class="absolute top-3 left-3 z-10">
                    <span class="px-2 py-0.5 text-[9px] font-black uppercase tracking-wider bg-black/75 backdrop-blur-md text-white/90 rounded-md border border-white/20">
                      {{ officers[prevIndex].titleCode }}
                    </span>
                  </div>

                  <!-- Hover Ready Indicator Overlay -->
                  <div class="absolute inset-0 bg-blue-600/15 opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-center justify-center pointer-events-none">
                    <span class="px-2.5 py-1 rounded-lg bg-black/80 backdrop-blur-md text-white font-mono text-[9px] uppercase tracking-wider border border-white/20 shadow-xl flex items-center space-x-1">
                      <ChevronLeft class="w-3 h-3 text-blue-400" />
                      <span>Switch</span>
                    </span>
                  </div>

                  <!-- Bottom Preview Name -->
                  <div class="absolute bottom-3 left-3 right-3 z-10 text-left">
                    <p class="text-xs font-black text-white truncate drop-shadow">{{ officers[prevIndex].name }}</p>
                    <p class="text-[10px] text-blue-300 font-medium truncate">{{ officers[prevIndex].role }}</p>
                  </div>
                </div>

                <!-- ACTIVE SELECTED CARD (In Center Focus) -->
                <div 
                  class="relative w-64 sm:w-72 md:w-80 h-[400px] sm:h-[430px] md:h-[450px] rounded-3xl overflow-hidden shadow-2xl transition-all duration-300 transform scale-100 z-20 border-2 border-blue-500 ring-4 ring-blue-500/20 bg-slate-900 group"
                >
                  <img 
                    v-if="currentOfficer.image"
                    :src="currentOfficer.image" 
                    :alt="currentOfficer.name"
                    class="w-full h-full object-cover object-top brightness-95 group-hover:scale-105 transition-transform duration-700 ease-out"
                  />
                  <div v-else class="w-full h-full flex flex-col items-center justify-center bg-gradient-to-b from-slate-800 via-slate-900 to-slate-950 p-6 text-center">
                    <div class="w-20 h-20 rounded-3xl bg-blue-600/20 border-2 border-blue-500/40 flex items-center justify-center text-blue-400 shadow-xl shadow-blue-900/30">
                      <Music class="w-10 h-10" />
                    </div>
                  </div>
                  
                  <!-- Cinematic Vignette & Gradient Overlays -->
                  <div class="absolute inset-0 bg-gradient-to-t from-slate-950 via-slate-950/40 to-transparent pointer-events-none"></div>
                  <div class="absolute inset-0 bg-gradient-to-b from-slate-950/50 via-transparent to-transparent pointer-events-none"></div>

                  <!-- Top Card Badges -->
                  <div class="absolute top-4 left-4 right-4 flex items-center justify-between z-10">
                    <span class="px-3 py-1 text-xs font-black uppercase tracking-wider bg-blue-600 text-white rounded-xl shadow-lg shadow-blue-600/30 flex items-center space-x-1.5 border border-blue-400/40">
                      <Shield class="w-3.5 h-3.5" />
                      <span>{{ currentOfficer.titleCode }}</span>
                    </span>
                    <span class="px-2.5 py-1 text-[11px] font-black font-mono tracking-widest bg-black/70 backdrop-blur-md text-white/90 rounded-lg border border-white/10">
                      0{{ selectedIndex + 1 }}/0{{ officers.length }}
                    </span>
                  </div>

                  <!-- Bottom Card Details (Single, Clean, High-Contrast Scrim) -->
                  <div class="absolute bottom-4 left-4 right-4 z-10 text-left">
                    <span class="text-[11px] font-black text-blue-400 tracking-wider uppercase drop-shadow flex items-center space-x-1 mb-1">
                      <Activity class="w-3 h-3 mr-1" />
                      {{ currentOfficer.role }}
                    </span>
                    <h3 class="text-xl sm:text-2xl font-black text-white tracking-tight leading-tight mb-1 drop-shadow-md">
                      {{ currentOfficer.name }}
                    </h3>
                    <p v-if="currentOfficer.instrument" class="text-xs font-medium text-slate-300 truncate flex items-center">
                      <Music class="w-3.5 h-3.5 mr-1.5 text-blue-400 inline shrink-0" />
                      {{ currentOfficer.instrument }}
                    </p>
                  </div>
                </div>

                <!-- NEXT CARD (Visible on Tablets & Desktops) -->
                <div 
                  @click="nextOfficer"
                  class="hidden sm:flex flex-col relative w-36 md:w-44 h-[350px] md:h-[380px] rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 transform scale-95 border border-slate-300 dark:border-white/10 shadow-lg group opacity-60 hover:opacity-100 hover:scale-105 hover:border-blue-500 hover:shadow-2xl hover:shadow-blue-500/25 filter blur-[1px] z-10 hover:z-30 bg-slate-900"
                >
                  <img 
                    v-if="officers[nextIndex].image"
                    :src="officers[nextIndex].image" 
                    :alt="officers[nextIndex].name"
                    class="w-full h-full object-cover object-top brightness-90 group-hover:brightness-100 group-hover:scale-110 transition-all duration-500"
                  />
                  <div v-else class="w-full h-full flex flex-col items-center justify-center bg-gradient-to-b from-slate-800 to-slate-950 p-3 text-center">
                    <div class="w-12 h-12 rounded-xl bg-blue-600/20 border border-blue-500/30 flex items-center justify-center text-blue-400 mb-2">
                      <Music class="w-6 h-6" />
                    </div>
                  </div>
                  <div class="absolute inset-0 bg-gradient-to-t from-slate-950 via-slate-950/40 to-transparent pointer-events-none"></div>
                  
                  <!-- Top Preview Tag -->
                  <div class="absolute top-3 left-3 z-10">
                    <span class="px-2 py-0.5 text-[9px] font-black uppercase tracking-wider bg-black/75 backdrop-blur-md text-white/90 rounded-md border border-white/20">
                      {{ officers[nextIndex].titleCode }}
                    </span>
                  </div>

                  <!-- Hover Ready Indicator Overlay -->
                  <div class="absolute inset-0 bg-blue-600/15 opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-center justify-center pointer-events-none">
                    <span class="px-2.5 py-1 rounded-lg bg-black/80 backdrop-blur-md text-white font-mono text-[9px] uppercase tracking-wider border border-white/20 shadow-xl flex items-center space-x-1">
                      <span>Switch</span>
                      <ChevronRight class="w-3 h-3 text-blue-400" />
                    </span>
                  </div>

                  <!-- Bottom Preview Name -->
                  <div class="absolute bottom-3 left-3 right-3 z-10 text-left">
                    <p class="text-xs font-black text-white truncate drop-shadow">{{ officers[nextIndex].name }}</p>
                    <p class="text-[10px] text-blue-300 font-medium truncate">{{ officers[nextIndex].role }}</p>
                  </div>
                </div>

              </div>

              <!-- Right Navigation Arrow -->
              <button 
                @click="nextOfficer"
                title="Next Officer (Right Arrow)"
                class="absolute right-1 sm:right-3 z-40 w-11 h-11 sm:w-12 sm:h-12 rounded-2xl bg-[#f8fafc] dark:bg-[#1c1c21]/90 backdrop-blur-md border border-slate-300/90 dark:border-white/10 text-slate-700 dark:text-white flex items-center justify-center shadow-xl hover:scale-110 active:scale-95 hover:bg-blue-600 hover:text-white hover:border-blue-600 dark:hover:bg-blue-600 transition-all cursor-pointer group"
              >
                <ChevronRight class="w-6 h-6 group-hover:translate-x-0.5 transition-transform" />
              </button>
            </div>

            <!-- ROSTER QUICK-SELECT BAR (Infinite Style: Loops between 1st and last officer) -->
            <div class="w-full max-w-2xl mt-4 bg-[#f8fafc]/95 dark:bg-[#18181b]/90 backdrop-blur-xl p-2.5 sm:p-3 md:p-4 rounded-3xl border border-slate-300/80 dark:border-neutral-800 shadow-xl relative flex items-center">
              
              <!-- Left Profile Selector Arrow (Loops First to Last) -->
              <button 
                @click="prevOfficer" 
                title="Previous Officer (Infinite: Loops First to Last)"
                aria-label="Previous Officer"
                class="absolute left-1.5 sm:left-2 z-20 w-8 h-8 sm:w-9 sm:h-9 rounded-full bg-slate-900/90 hover:bg-blue-600 text-white flex items-center justify-center backdrop-blur shadow-lg border border-white/20 active:scale-90 hover:scale-110 transition-all cursor-pointer group"
              >
                <ChevronLeft class="w-4 h-4 sm:w-5 sm:h-5 group-hover:-translate-x-0.5 transition-transform" />
              </button>

              <div 
                ref="avatarScrollContainer"
                @wheel="handleAvatarWheel"
                class="flex items-center space-x-2 sm:space-x-1 sm:justify-between overflow-x-auto pb-1 pt-1 px-10 sm:px-11 scrollbar-none sm:overflow-visible snap-x scroll-smooth w-full"
              >
                <button
                  v-for="(officer, idx) in officers"
                  :key="officer.id"
                  :ref="el => { if (el) avatarRefs[idx] = el }"
                  @click="selectOfficer(idx)"
                  class="group flex flex-col items-center shrink-0 sm:shrink snap-center transition-all duration-300 cursor-pointer focus:outline-none min-w-[62px] sm:min-w-0 sm:flex-1 py-1"
                  :class="selectedIndex === idx ? 'scale-105' : 'opacity-65 hover:opacity-100 hover:scale-102'"
                >
                  <!-- Circular Profile Avatar with Glowing Ring -->
                  <div class="relative w-11 h-11 sm:w-12 sm:h-12 md:w-13 md:h-13 flex items-center justify-center">
                    <div 
                      class="w-11 h-11 sm:w-12 sm:h-12 md:w-13 md:h-13 rounded-full overflow-hidden transition-all duration-300 bg-slate-800 flex items-center justify-center"
                      :class="selectedIndex === idx 
                        ? 'ring-3 ring-blue-500 ring-offset-2 ring-offset-[#f8fafc] dark:ring-offset-[#18181b] shadow-lg shadow-blue-500/40' 
                        : 'border-2 border-slate-300 dark:border-neutral-700/80 group-hover:border-blue-400'"
                    >
                      <img 
                        v-if="officer.image"
                        :src="officer.image" 
                        :alt="officer.name" 
                        class="w-full h-full object-cover object-top"
                      />
                      <div v-else class="w-full h-full bg-gradient-to-br from-blue-700 to-indigo-900 text-white flex items-center justify-center font-black text-xs font-mono">
                        {{ officer.shortCode }}
                      </div>
                    </div>

                    <!-- Active Status Dot -->
                    <span 
                      v-if="selectedIndex === idx" 
                      class="absolute -top-0.5 right-0.5 w-2.5 h-2.5 rounded-full bg-emerald-500 ring-2 ring-white dark:ring-[#18181b]"
                    ></span>
                  </div>

                  <!-- Complete Role Label (Never Truncated with ellipsis) -->
                  <div class="mt-1 text-center w-full">
                    <span 
                      class="text-[9px] sm:text-[10px] md:text-[10.5px] font-black tracking-wide px-1 sm:px-0.5 py-0.5 rounded-full transition-all block text-center"
                      :class="selectedIndex === idx 
                        ? 'bg-blue-600 text-white shadow-xs' 
                        : 'text-slate-600 dark:text-neutral-400 group-hover:text-blue-600 dark:group-hover:text-blue-400'"
                    >
                      {{ officer.shortTitle }}
                    </span>
                  </div>
                </button>
              </div>

              <!-- Right Profile Selector Arrow (Loops Last to First) -->
              <button 
                @click="nextOfficer" 
                title="Next Officer (Infinite: Loops Last to First)"
                aria-label="Next Officer"
                class="absolute right-1.5 sm:right-2 z-20 w-8 h-8 sm:w-9 sm:h-9 rounded-full bg-slate-900/90 hover:bg-blue-600 text-white flex items-center justify-center backdrop-blur shadow-lg border border-white/20 active:scale-90 hover:scale-110 transition-all cursor-pointer group"
              >
                <ChevronRight class="w-4 h-4 sm:w-5 sm:h-5 group-hover:translate-x-0.5 transition-transform" />
              </button>

            </div>

            <!-- Interactive Hint -->
            <div class="mt-2.5 flex items-center space-x-1 text-slate-500 dark:text-neutral-500 text-[11px] font-medium font-mono">
              <span>← Infinite Profile Selector: Click arrows or avatars to cycle (1 ⇄ 8) →</span>
            </div>

          </div>

          <!-- RIGHT SIDE: Concise Officer Details Dossier -->
          <div class="lg:col-span-6 xl:col-span-5 w-full">
            <div class="p-6 sm:p-8 md:p-10 rounded-3xl bg-[#f8fafc] dark:bg-[#18181b] border border-slate-300/80 dark:border-neutral-800 shadow-xl relative overflow-hidden transition-all duration-300">
              
              <!-- Subtle Background Glow -->
              <div class="absolute -top-20 -right-20 w-56 h-56 bg-blue-500/10 dark:bg-blue-500/15 rounded-full blur-3xl pointer-events-none"></div>

              <!-- Top Status HUD -->
              <div class="flex flex-wrap items-center justify-between gap-2 pb-4 border-b border-slate-200/80 dark:border-neutral-800/80 mb-5">
                <div class="flex items-center space-x-2">
                  <span class="w-2.5 h-2.5 rounded-full" :class="currentOfficer.isAssigned ? 'bg-emerald-500 animate-pulse' : 'bg-amber-500'"></span>
                  <span class="text-[11px] sm:text-xs font-black font-mono uppercase tracking-wider text-slate-500 dark:text-neutral-400">
                    {{ currentOfficer.isAssigned ? 'STATUS // ACTIVE EXECUTIVE COUNCIL' : 'STATUS // APPOINTMENT PENDING' }}
                  </span>
                </div>
                <span class="text-xs font-mono font-bold text-blue-700 dark:text-blue-400 bg-blue-600/10 dark:bg-blue-500/10 px-2.5 py-1 rounded-md border border-blue-300/60 dark:border-blue-500/20">
                  OFFICER 0{{ selectedIndex + 1 }} / 08
                </span>
              </div>

              <!-- Complete Rank Name & Title Display -->
              <div class="mb-5">
                <div class="inline-flex items-center space-x-2 bg-gradient-to-r from-blue-600 to-indigo-600 text-white font-black text-xs px-3.5 py-1.5 rounded-xl uppercase tracking-wider mb-3 shadow-md shadow-blue-500/20">
                  <Award class="w-4 h-4" />
                  <span>{{ currentOfficer.role }}</span>
                </div>
                
                <h3 class="text-2xl sm:text-3xl lg:text-4xl font-black text-slate-800 dark:text-white tracking-tight leading-tight mb-2">
                  {{ currentOfficer.name }}
                </h3>

                <p v-if="currentOfficer.instrument" class="text-sm font-bold text-blue-700 dark:text-blue-400 flex items-center">
                  <Music class="w-4 h-4 mr-2 flex-shrink-0" />
                  <span>{{ currentOfficer.instrument }}</span>
                </p>
              </div>

              <!-- Operational Responsibility -->
              <div class="p-5 rounded-2xl bg-[#edf1f5] dark:bg-neutral-900/70 border border-slate-300/70 dark:border-neutral-800 text-sm text-slate-700 dark:text-neutral-300 leading-relaxed font-medium">
                <p class="text-[10px] font-black uppercase tracking-wider text-slate-400 dark:text-neutral-500 mb-2 font-mono">Official Duty</p>
                <p v-if="currentOfficer.responsibility" class="text-xs sm:text-sm">{{ currentOfficer.responsibility }}</p>
                <p v-else class="text-xs text-slate-400 dark:text-neutral-600 italic">No duties specified yet.</p>
              </div>

            </div>
          </div>

        </div>

      </div>
    </section>

  </div>
</template>
