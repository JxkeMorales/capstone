<script setup>
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue'
import { useRouter } from 'vue-router'
import { 
  Music, 
  Sun, 
  Moon, 
  ChevronLeft, 
  ChevronRight, 
  Shield
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
    name: 'Band President',
    image: '/officers/bandpres.png',
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
    name: 'Band Treasurer',
    image: '/officers/bandtreas.png',
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
      .from('public_roster')
      .select('id, full_name, instrument, role, executive_title, profile_picture')

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
  document.documentElement.classList.toggle('dark', isDark.value)
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
const currentOfficer = computed(() => officers.value[selectedIndex.value] || {})
const prevIndex = computed(() => (selectedIndex.value - 1 + officers.value.length) % officers.value.length)
const nextIndex = computed(() => (selectedIndex.value + 1) % officers.value.length)
const prevOfficerObj = computed(() => officers.value[prevIndex.value] || {})
const nextOfficerObj = computed(() => officers.value[nextIndex.value] || {})

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
const setAvatarRef = (el, idx) => {
  if (el) avatarRefs.value[idx] = el
}

const scrollToActiveAvatar = (idx) => {
  nextTick(() => {
    const el = avatarRefs.value[idx] || (avatarRefs[idx])
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
  <div class="min-h-screen bg-[#f8f9fa] dark:bg-[#18191a] text-slate-900 dark:text-neutral-100 selection:bg-slate-800 selection:text-white dark:selection:bg-neutral-200 dark:selection:text-slate-900 font-sans overflow-x-hidden transition-colors duration-300">
    
    <!-- Navigation Bar (Clean M3 Top App Bar, Flat Surface) -->
    <nav class="fixed top-0 left-0 right-0 z-50 bg-[#f8fafc] dark:bg-[#121214] border-b border-slate-200/50 dark:border-white/[0.04] transition-colors">
      <div class="max-w-6xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class="w-9 h-9 rounded-xl overflow-hidden border border-slate-200 dark:border-neutral-700 bg-white flex items-center justify-center p-0.5 shadow-xs">
            <img src="/band1870logo.jpg" alt="Peñaranda Band 1870" class="w-full h-full object-contain" />
          </div>
          <div>
            <span class="text-base sm:text-lg font-bold tracking-tight text-slate-900 dark:text-white block leading-none">SmartBand</span>
            <span class="text-[10px] text-slate-500 dark:text-neutral-400 font-medium">Municipal Band 1870</span>
          </div>
        </div>
        <div class="flex items-center space-x-1 sm:space-x-2">
          <button 
            @click="toggleTheme" 
            title="Toggle theme"
            type="button"
            class="min-w-[48px] min-h-[48px] rounded-full text-slate-600 dark:text-neutral-300 hover:bg-slate-200/70 dark:hover:bg-neutral-800 transition-colors cursor-pointer flex items-center justify-center"
            :aria-label="!isDark ? 'Switch to Dark Mode' : 'Switch to Light Mode'"
          >
            <Sun v-if="!isDark" class="w-5 h-5 text-slate-700" />
            <Moon v-else class="w-5 h-5 text-neutral-300" />
          </button>
          <button 
            @click="goToLogin" 
            type="button"
            class="m3-btn-filled"
          >
            Member Login
          </button>
        </div>
      </div>
    </nav>

    <!-- Hero Section -->
    <main class="relative pt-28 pb-16 sm:pt-36 sm:pb-20 overflow-hidden flex items-center">
      <!-- Background Image with Soft Flat Overlays -->
      <div class="absolute inset-0 z-0">
        <img 
          src="/hero-band.jpg" 
          alt="Municipal Band Performance" 
          class="w-full h-full object-cover object-center opacity-15 dark:opacity-20" 
        />
        <div class="absolute inset-0 bg-gradient-to-t from-[#f8fafc] via-[#f8fafc]/90 dark:from-[#121214] dark:via-[#121214]/90 to-transparent transition-colors"></div>
        <div class="absolute inset-0 bg-gradient-to-r from-[#f8fafc] via-[#f8fafc]/80 dark:from-[#121214] dark:via-[#121214]/80 to-transparent transition-colors"></div>
      </div>

      <div class="relative z-10 max-w-6xl mx-auto px-4 sm:px-6 w-full">
        <div class="max-w-2xl">
          <div class="inline-flex items-center space-x-2 bg-slate-200/70 dark:bg-neutral-800/80 border border-slate-300/60 dark:border-neutral-700 text-slate-700 dark:text-neutral-300 px-3.5 py-1 rounded-full text-xs font-medium mb-4">
            <span class="w-1.5 h-1.5 rounded-full bg-slate-500 dark:bg-neutral-400"></span>
            <span>Band 1870 Portal</span>
          </div>
          
          <h1 class="text-3xl sm:text-5xl lg:text-6xl font-bold text-slate-900 dark:text-white leading-tight tracking-tight mb-4">
            Peñaranda marching band 1870.
          </h1>
          
          <p class="m3-body-large text-slate-600 dark:text-neutral-400 leading-relaxed font-normal mb-6 max-w-xl">
            The official portal for municipal band musicians. Synchronize rehearsal schedules, gig call-times, and performance reliability scores across the entire ensemble.
          </p>

          <div class="flex flex-wrap items-center gap-3">
            <button 
              @click="goToLogin" 
              type="button"
              class="m3-btn-filled text-sm"
            >
              Sign In to Portal
            </button>
            <a 
              href="#officers" 
              class="m3-btn-outlined text-sm"
            >
              View Officers
            </a>
          </div>
        </div>
      </div>
    </main>

    <!-- Officers Section (Clean Material 3 Card Showcase) -->
    <section id="officers" class="scroll-mt-20 py-12 sm:py-16 relative z-10 border-t border-slate-200 dark:border-[#2d3035] transition-colors">
      <div class="max-w-6xl mx-auto px-4 sm:px-6">
        
        <!-- Clean Section Header -->
        <div class="mb-8">
          <h2 class="text-2xl sm:text-3xl font-bold text-slate-900 dark:text-white tracking-tight">
            Band Officers
          </h2>
          <p class="m3-body-small text-slate-500 dark:text-neutral-400 mt-1">
            Executive leadership and section coordinators of Peñaranda Band 1870.
          </p>
        </div>

        <!-- Main Responsive Officer Layout -->
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 sm:gap-8 items-start">
          
          <!-- LEFT: Officer Card Carousel -->
          <div class="lg:col-span-6 xl:col-span-7 flex flex-col items-center w-full">
            
            <div 
              @touchstart="handleTouchStart"
              @touchend="handleTouchEnd"
              class="relative w-full flex items-center justify-center min-h-[380px] sm:min-h-[420px] overflow-hidden py-2 select-none"
            >
              
              <!-- Previous Button (Min 48x48px hit target) -->
              <button 
                @click="prevOfficer"
                type="button"
                title="Previous Officer"
                aria-label="Previous Officer"
                class="absolute left-1 sm:left-2 z-30 min-w-[48px] min-h-[48px] rounded-full bg-white dark:bg-neutral-800 border border-slate-200 dark:border-neutral-700 text-slate-700 dark:text-neutral-200 flex items-center justify-center shadow-md hover:bg-slate-100 dark:hover:bg-neutral-700 transition-all cursor-pointer"
              >
                <ChevronLeft class="w-5 h-5" />
              </button>

              <!-- Carousel Cards Wrapper -->
              <div class="flex items-center justify-center space-x-3 w-full">
                
                <!-- PREVIOUS CARD PREVIEW (Desktop / Tablet) -->
                <div 
                  @click="prevOfficer"
                  class="hidden sm:flex flex-col relative w-32 md:w-36 h-[320px] md:h-[350px] rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 transform scale-95 border border-slate-200 dark:border-neutral-800 shadow-sm opacity-50 hover:opacity-80 bg-slate-900"
                >
                  <img 
                    v-if="prevOfficerObj.image"
                    :src="prevOfficerObj.image" 
                    :alt="prevOfficerObj.name"
                    class="w-full h-full object-cover object-top"
                  />
                  <div v-else class="w-full h-full flex flex-col items-center justify-center bg-slate-800 p-3 text-center">
                    <Music class="w-8 h-8 text-slate-400 mb-1" />
                  </div>
                  <div class="absolute inset-0 bg-gradient-to-t from-slate-950/80 via-transparent to-transparent pointer-events-none"></div>
                  <div class="absolute bottom-2.5 left-2.5 right-2.5 z-10 text-left">
                    <p class="text-xs font-semibold text-white truncate">{{ prevOfficerObj.name }}</p>
                    <p class="text-[10px] text-slate-300 truncate">{{ prevOfficerObj.role }}</p>
                  </div>
                </div>

                <!-- ACTIVE SELECTED CARD -->
                <div 
                  class="relative w-64 sm:w-72 md:w-80 h-[380px] sm:h-[400px] md:h-[420px] rounded-3xl overflow-hidden shadow-lg transition-all duration-300 transform scale-100 z-20 border border-slate-300/80 dark:border-neutral-700 bg-slate-900 group"
                >
                  <img 
                    v-if="currentOfficer.image"
                    :src="currentOfficer.image" 
                    :alt="currentOfficer.name"
                    class="w-full h-full object-cover object-top"
                  />
                  <div v-else class="w-full h-full flex flex-col items-center justify-center bg-slate-800 p-6 text-center">
                    <div class="w-16 h-16 rounded-2xl bg-slate-700/60 flex items-center justify-center text-slate-300 mb-3">
                      <Music class="w-8 h-8" />
                    </div>
                  </div>
                  
                  <div class="absolute inset-0 bg-gradient-to-t from-slate-950 via-slate-950/30 to-transparent pointer-events-none"></div>

                  <!-- Role Pill on Image (Zero Blur Flat Surface) -->
                  <div class="absolute top-3 left-3 z-10">
                    <span class="px-2.5 py-1 text-[11px] font-semibold tracking-wide bg-slate-900/90 text-white rounded-lg border border-white/10">
                      {{ currentOfficer.role }}
                    </span>
                  </div>

                  <!-- Bottom Card Details -->
                  <div class="absolute bottom-4 left-4 right-4 z-10 text-left">
                    <h3 class="text-lg sm:text-xl font-bold text-white tracking-tight leading-snug mb-0.5 drop-shadow-sm">
                      {{ currentOfficer.name }}
                    </h3>
                    <p v-if="currentOfficer.instrument" class="text-xs font-medium text-slate-300 truncate flex items-center">
                      <Music class="w-3.5 h-3.5 mr-1.5 text-slate-400 shrink-0" />
                      {{ currentOfficer.instrument }}
                    </p>
                  </div>
                </div>

                <!-- NEXT CARD PREVIEW (Desktop / Tablet) -->
                <div 
                  @click="nextOfficer"
                  class="hidden sm:flex flex-col relative w-32 md:w-36 h-[320px] md:h-[350px] rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 transform scale-95 border border-slate-200 dark:border-neutral-800 shadow-sm opacity-50 hover:opacity-80 bg-slate-900"
                >
                  <img 
                    v-if="nextOfficerObj.image"
                    :src="nextOfficerObj.image" 
                    :alt="nextOfficerObj.name"
                    class="w-full h-full object-cover object-top"
                  />
                  <div v-else class="w-full h-full flex flex-col items-center justify-center bg-slate-800 p-3 text-center">
                    <Music class="w-8 h-8 text-slate-400 mb-1" />
                  </div>
                  <div class="absolute inset-0 bg-gradient-to-t from-slate-950/80 via-transparent to-transparent pointer-events-none"></div>
                  <div class="absolute bottom-2.5 left-2.5 right-2.5 z-10 text-left">
                    <p class="text-xs font-semibold text-white truncate">{{ nextOfficerObj.name }}</p>
                    <p class="text-[10px] text-slate-300 truncate">{{ nextOfficerObj.role }}</p>
                  </div>
                </div>

              </div>

              <!-- Next Button (Min 48x48px hit target) -->
              <button 
                @click="nextOfficer"
                type="button"
                title="Next Officer"
                aria-label="Next Officer"
                class="absolute right-1 sm:right-2 z-30 min-w-[48px] min-h-[48px] rounded-full bg-white dark:bg-neutral-800 border border-slate-200 dark:border-neutral-700 text-slate-700 dark:text-neutral-200 flex items-center justify-center shadow-md hover:bg-slate-100 dark:hover:bg-neutral-700 transition-all cursor-pointer"
              >
                <ChevronRight class="w-5 h-5" />
              </button>
            </div>

            <!-- CLEAN AVATAR SELECTOR STRIP -->
            <div class="w-full max-w-xl mt-4 bg-white dark:bg-[#1f2023] p-2 sm:p-2.5 rounded-2xl border border-slate-200 dark:border-neutral-800 shadow-xs">
              <div 
                ref="avatarScrollContainer"
                @wheel="handleAvatarWheel"
                class="flex items-center space-x-2 overflow-x-auto pb-1 pt-1 px-1 scrollbar-none snap-x scroll-smooth w-full"
              >
                <button
                  v-for="(officer, idx) in officers"
                  :key="officer.id"
                  :ref="el => setAvatarRef(el, idx)"
                  @click="selectOfficer(idx)"
                  type="button"
                  class="group flex flex-col items-center shrink-0 snap-center transition-all duration-200 cursor-pointer focus:outline-none min-w-[56px] min-h-[48px] sm:min-w-0 sm:flex-1 py-1 rounded-xl"
                  :class="selectedIndex === idx ? 'bg-slate-100 dark:bg-neutral-800' : 'opacity-70 hover:opacity-100'"
                >
                  <div class="relative w-10 h-10 sm:w-11 sm:h-11 flex items-center justify-center">
                    <div 
                      class="w-10 h-10 sm:w-11 sm:h-11 rounded-full overflow-hidden transition-all duration-200 bg-slate-800 flex items-center justify-center"
                      :class="selectedIndex === idx 
                        ? 'ring-2 ring-slate-800 dark:ring-neutral-200 ring-offset-1 ring-offset-white dark:ring-offset-[#1f2023]' 
                        : 'border border-slate-300 dark:border-neutral-700'"
                    >
                      <img 
                        v-if="officer.image"
                        :src="officer.image" 
                        :alt="officer.name" 
                        class="w-full h-full object-cover object-top"
                      />
                      <div v-else class="w-full h-full bg-slate-700 text-white flex items-center justify-center font-bold text-xs">
                        {{ officer.shortCode }}
                      </div>
                    </div>
                  </div>

                  <div class="mt-1 text-center w-full px-1">
                    <span 
                      class="text-[10px] font-medium tracking-tight block text-center truncate"
                      :class="selectedIndex === idx 
                        ? 'text-slate-900 dark:text-white font-semibold' 
                        : 'text-slate-500 dark:text-neutral-400'"
                    >
                      {{ officer.shortTitle }}
                    </span>
                  </div>
                </button>
              </div>
            </div>

          </div>

          <!-- RIGHT: Officer Details Card (Google Material 3 Info Surface) -->
          <div class="lg:col-span-6 xl:col-span-5 w-full">
            <div class="p-6 sm:p-7 rounded-3xl bg-white dark:bg-[#1f2023] border border-slate-200 dark:border-neutral-800 shadow-xs relative transition-all duration-300">
              
              <!-- Clean Position Badge -->
              <div class="mb-4">
                <span class="inline-flex items-center space-x-1.5 bg-slate-100 dark:bg-neutral-800 text-slate-800 dark:text-neutral-200 font-semibold text-xs px-3 py-1.5 rounded-full border border-slate-200/80 dark:border-neutral-700">
                  <Shield class="w-3.5 h-3.5 text-slate-600 dark:text-neutral-400" />
                  <span>{{ currentOfficer.role }}</span>
                </span>
              </div>

              <!-- Officer Name -->
              <h3 class="text-xl sm:text-2xl font-bold text-slate-900 dark:text-white tracking-tight leading-snug mb-1">
                {{ currentOfficer.name }}
              </h3>

              <p v-if="currentOfficer.instrument" class="text-xs sm:text-sm font-medium text-slate-600 dark:text-neutral-400 flex items-center mb-5">
                <Music class="w-3.5 h-3.5 mr-1.5 text-slate-500 shrink-0" />
                <span>{{ currentOfficer.instrument }}</span>
              </p>
              <div v-else class="mb-5"></div>

              <!-- Official Duty Box -->
              <div class="p-4 rounded-2xl bg-slate-50 dark:bg-neutral-900/60 border border-slate-200/70 dark:border-neutral-800 text-xs sm:text-sm text-slate-700 dark:text-neutral-300 leading-relaxed font-normal">
                <p class="text-[11px] font-semibold text-slate-400 dark:text-neutral-500 mb-1 uppercase tracking-wider">Duties & Responsibilities</p>
                <p v-if="currentOfficer.responsibility" class="text-slate-800 dark:text-neutral-200">{{ currentOfficer.responsibility }}</p>
                <p v-else class="text-slate-400 dark:text-neutral-500 italic">No specific operational duties assigned yet.</p>
              </div>

            </div>
          </div>

        </div>

      </div>
    </section>

  </div>
</template>
