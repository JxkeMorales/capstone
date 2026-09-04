<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
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

const router = useRouter()
const isDark = ref(true)

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

// Officers Data
const officers = ref([
  {
    id: 1,
    titleCode: 'BAND PRES',
    role: 'Band President',
    name: 'Capt. Danilo Rivera',
    instrument: 'Lead Trumpet & Principal Brass',
    image: '/officers/officer_2.jpg',
    tenure: '18 Years Active',
    reliability: '99.4%',
    specialty: 'Executive Governance & Civic Parades',
    quote: 'Guiding Band 1870 with discipline, honor, and passion for our municipal musical heritage.',
    bio: 'Oversees executive operations, public representation, and official engagements of Band 1870. Coordinates with municipal authorities, event sponsors, and festival committees.',
    stats: [
      { label: 'Tenure', value: '18 yrs' },
      { label: 'Section', value: 'Lead Trumpet' },
      { label: 'Reliability', value: '99.4%' },
      { label: 'Rank', value: 'Executive 01' }
    ],
    tags: ['Executive Board', 'Principal Brass', 'Master Coordinator']
  },
  {
    id: 2,
    titleCode: 'BAND VP',
    role: 'Band Vice President',
    name: 'Maria Elena Ramos',
    instrument: 'Clarinet & Woodwind Ensemble',
    image: '/officers/officer_3.jpg',
    tenure: '14 Years Active',
    reliability: '98.9%',
    specialty: 'Sectionals & Repertoire Tuning',
    quote: 'Harmonizing our youthful talents with timeless classic band literature.',
    bio: 'Assists the President in daily operational logistics, directs sectional woodwind rehearsals, and serves as primary liaison between section leaders and executive administration.',
    stats: [
      { label: 'Tenure', value: '14 yrs' },
      { label: 'Section', value: 'Woodwinds' },
      { label: 'Reliability', value: '98.9%' },
      { label: 'Rank', value: 'Executive 02' }
    ],
    tags: ['Executive Board', 'Woodwind Lead', 'Repertoire Committee']
  },
  {
    id: 3,
    titleCode: 'BAND SEC',
    role: 'Band Secretary',
    name: 'Arnel Bautista',
    instrument: 'Snare & Field Drill Maces',
    image: '/officers/officer_4.jpg',
    tenure: '11 Years Active',
    reliability: '99.6%',
    specialty: 'Roster Call-Times & Field Marshalling',
    quote: 'Precise schedules, unified cadence, and transparent communication across all sections.',
    bio: 'Maintains official member directories, monitors gig call-times and rehearsal logs, handles official correspondence, and oversees marching parade field drills.',
    stats: [
      { label: 'Tenure', value: '11 yrs' },
      { label: 'Section', value: 'Percussion' },
      { label: 'Reliability', value: '99.6%' },
      { label: 'Rank', value: 'Operations 01' }
    ],
    tags: ['Field Marshall', 'Call-Time Logs', 'Roster Master']
  },
  {
    id: 4,
    titleCode: 'BAND TREAS',
    role: 'Band Treasurer',
    name: 'Carmela De Leon',
    instrument: 'Flute & High Winds',
    image: '/officers/officer_5.jpg',
    tenure: '12 Years Active',
    reliability: '100%',
    specialty: 'Financial Auditing & Uniform Logistics',
    quote: 'Equipping every musician with pride, reliable instruments, and prompt honorariums.',
    bio: 'Manages band finances, member honorarium disbursements, uniform allocations, and instrument maintenance funds with transparent accountability.',
    stats: [
      { label: 'Tenure', value: '12 yrs' },
      { label: 'Section', value: 'High Winds' },
      { label: 'Reliability', value: '100%' },
      { label: 'Rank', value: 'Finance 01' }
    ],
    tags: ['Finance Head', 'Quartermaster', 'Audits']
  },
  {
    id: 5,
    titleCode: 'BAND ADMIN',
    role: 'Band Administrator',
    name: 'Maestro Ricardo Santos',
    instrument: 'French Horn & Conducting Baton',
    image: '/officers/officer_1.jpg',
    tenure: '25 Years Active',
    reliability: '99.8%',
    specialty: 'System Operations, Logistics & Music Direction',
    quote: 'Translating tradition into excellence through digital precision and musical rigor.',
    bio: 'Oversees digital management systems, logistical preparation for municipal tours, equipment inventories, and administrative coordination for Band 1870.',
    stats: [
      { label: 'Tenure', value: '25 yrs' },
      { label: 'Section', value: 'Operations' },
      { label: 'Reliability', value: '99.8%' },
      { label: 'Rank', value: 'System Admin' }
    ],
    tags: ['System Admin', 'Logistics Lead', 'Artistic Advisor']
  }
])

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
</script>

<template>
  <div class="min-h-screen bg-[#edf1f5] dark:bg-[#121214] text-slate-800 dark:text-white selection:bg-blue-600 selection:text-white font-sans overflow-x-hidden transition-colors duration-300">
    
    <!-- Navigation Bar (Soft Dimmed Glassmorphism in Light Mode) -->
    <nav class="fixed top-0 left-0 right-0 z-50 bg-[#edf1f5]/85 dark:bg-[#121214]/80 backdrop-blur-xl border-b border-slate-300/80 dark:border-neutral-800/50 transition-colors duration-300">
      <div class="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class="p-2.5 bg-blue-600 rounded-xl shadow-lg shadow-blue-900/20">
            <Music class="w-6 h-6 text-white" />
          </div>
          <span class="text-xl font-black tracking-tight text-slate-800 dark:text-white">SmartBand</span>
        </div>
        <div class="flex items-center space-x-3">
          <button 
            @click="toggleTheme" 
            title="Toggle theme"
            class="p-2.5 rounded-xl bg-slate-200/90 hover:bg-slate-300 dark:bg-white/10 dark:hover:bg-white/20 text-slate-700 dark:text-white transition-all cursor-pointer border border-slate-300/60 dark:border-white/5"
          >
            <Sun v-if="!isDark" class="w-4 h-4 text-amber-600" />
            <Moon v-else class="w-4 h-4 text-blue-400" />
          </button>
          <button 
            @click="goToLogin" 
            class="text-sm font-bold bg-slate-200/90 hover:bg-slate-300 dark:bg-white/10 dark:hover:bg-white/20 text-slate-800 dark:text-white px-5 py-2.5 rounded-xl transition-all border border-slate-300/60 dark:border-white/5 cursor-pointer shadow-xs"
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
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-10 items-center">
          
          <!-- LEFT SIDE: Character Selection Stage -->
          <div class="lg:col-span-6 xl:col-span-7 flex flex-col items-center">
            
            <!-- Character Cards Carousel Stage -->
            <div class="relative w-full flex items-center justify-center min-h-[440px] sm:min-h-[480px] overflow-hidden py-4 select-none">
              
              <!-- Left Navigation Arrow -->
              <button 
                @click="prevOfficer"
                title="Previous Officer (Left Arrow)"
                class="absolute left-2 sm:left-4 z-40 w-11 h-11 sm:w-13 sm:h-13 rounded-2xl bg-[#f8fafc] dark:bg-[#1c1c21]/90 backdrop-blur-md border border-slate-300/90 dark:border-white/10 text-slate-700 dark:text-white flex items-center justify-center shadow-xl hover:scale-110 active:scale-95 hover:bg-blue-600 hover:text-white hover:border-blue-600 dark:hover:bg-blue-600 transition-all cursor-pointer group"
              >
                <ChevronLeft class="w-6 h-6 group-hover:-translate-x-0.5 transition-transform" />
              </button>

              <!-- Carousel Cards Wrapper -->
              <div class="flex items-center justify-center space-x-3 sm:space-x-5 w-full">
                
                <!-- PREVIOUS CARD (Zoom in on hover like preparing to switch; switches ONLY on click) -->
                <div 
                  @click="prevOfficer"
                  class="hidden sm:flex flex-col relative w-36 md:w-44 h-[360px] md:h-[390px] rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 transform scale-95 border border-slate-300 dark:border-white/10 shadow-lg group opacity-60 hover:opacity-100 hover:scale-105 hover:blur-none hover:border-blue-500 hover:shadow-2xl hover:shadow-blue-500/25 filter blur-[1.5px] z-10 hover:z-30"
                >
                  <img 
                    :src="officers[prevIndex].image" 
                    :alt="officers[prevIndex].name"
                    class="w-full h-full object-cover object-top brightness-90 group-hover:brightness-100 group-hover:scale-110 transition-all duration-500"
                  />
                  <div class="absolute inset-0 bg-gradient-to-t from-slate-950 via-slate-950/40 to-transparent"></div>
                  
                  <!-- Top Preview Tag -->
                  <div class="absolute top-3 left-3 z-10">
                    <span class="px-2.5 py-1 text-[10px] font-black uppercase tracking-wider bg-black/70 backdrop-blur-md text-white/90 rounded-md border border-white/20">
                      {{ officers[prevIndex].titleCode }}
                    </span>
                  </div>

                  <!-- Hover Ready Indicator Overlay -->
                  <div class="absolute inset-0 bg-blue-600/15 opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-center justify-center pointer-events-none">
                    <span class="px-2.5 py-1 rounded-lg bg-black/80 backdrop-blur-md text-white font-mono text-[9px] uppercase tracking-wider border border-white/20 shadow-xl flex items-center space-x-1">
                      <ChevronLeft class="w-3 h-3 text-blue-400" />
                      <span>Click To Select</span>
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
                  class="relative w-64 sm:w-72 md:w-80 h-[420px] sm:h-[450px] md:h-[470px] rounded-3xl overflow-hidden shadow-2xl transition-all duration-300 transform scale-100 z-20 border-2 border-blue-500 ring-4 ring-blue-500/20 bg-slate-900 group"
                >
                  <img 
                    :src="currentOfficer.image" 
                    :alt="currentOfficer.name"
                    class="w-full h-full object-cover object-top brightness-95 group-hover:scale-105 transition-transform duration-700 ease-out"
                  />
                  
                  <!-- Cinematic Vignette & Gradient Overlay -->
                  <div class="absolute inset-0 bg-gradient-to-t from-slate-950 via-slate-950/40 to-transparent"></div>
                  <div class="absolute inset-0 bg-gradient-to-b from-slate-950/40 via-transparent to-transparent"></div>

                  <!-- Top Card Badges -->
                  <div class="absolute top-4 left-4 right-4 flex items-center justify-between z-10">
                    <span class="px-3.5 py-1.5 text-xs font-black uppercase tracking-wider bg-blue-600 text-white rounded-xl shadow-lg shadow-blue-600/30 flex items-center space-x-1.5 border border-blue-400/40">
                      <Shield class="w-3.5 h-3.5" />
                      <span>{{ currentOfficer.titleCode }}</span>
                    </span>
                    <span class="px-2.5 py-1 text-[11px] font-black font-mono tracking-widest bg-black/70 backdrop-blur-md text-white/90 rounded-lg border border-white/10">
                      0{{ selectedIndex + 1 }}/0{{ officers.length }}
                    </span>
                  </div>

                  <!-- Card Center Subtle Accent -->
                  <div class="absolute inset-x-4 top-1/2 -translate-y-1/2 pointer-events-none opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex justify-center">
                    <span class="text-[10px] font-mono tracking-widest text-blue-300 uppercase px-3 py-1 bg-black/60 rounded-full border border-blue-400/30 backdrop-blur-md">
                      ACTIVE SELECTION
                    </span>
                  </div>

                  <!-- Bottom Card Details -->
                  <div class="absolute bottom-5 left-5 right-5 z-10 text-left">
                    <span class="text-[11px] font-black text-blue-400 tracking-wider uppercase drop-shadow flex items-center space-x-1 mb-1">
                      <Activity class="w-3 h-3 mr-1" />
                      {{ currentOfficer.role }}
                    </span>
                    <h3 class="text-xl sm:text-2xl font-black text-white tracking-tight leading-tight mb-1 drop-shadow-md">
                      {{ currentOfficer.name }}
                    </h3>
                    <p class="text-xs font-medium text-slate-300/90 truncate flex items-center">
                      <Music class="w-3 h-3 mr-1.5 text-blue-400 inline shrink-0" />
                      {{ currentOfficer.instrument }}
                    </p>
                  </div>
                </div>

                <!-- NEXT CARD (Zoom in on hover like preparing to switch; switches ONLY on click) -->
                <div 
                  @click="nextOfficer"
                  class="hidden sm:flex flex-col relative w-36 md:w-44 h-[360px] md:h-[390px] rounded-2xl overflow-hidden cursor-pointer transition-all duration-300 transform scale-95 border border-slate-300 dark:border-white/10 shadow-lg group opacity-60 hover:opacity-100 hover:scale-105 hover:blur-none hover:border-blue-500 hover:shadow-2xl hover:shadow-blue-500/25 filter blur-[1.5px] z-10 hover:z-30"
                >
                  <img 
                    :src="officers[nextIndex].image" 
                    :alt="officers[nextIndex].name"
                    class="w-full h-full object-cover object-top brightness-90 group-hover:brightness-100 group-hover:scale-110 transition-all duration-500"
                  />
                  <div class="absolute inset-0 bg-gradient-to-t from-slate-950 via-slate-950/40 to-transparent"></div>
                  
                  <!-- Top Preview Tag -->
                  <div class="absolute top-3 left-3 z-10">
                    <span class="px-2.5 py-1 text-[10px] font-black uppercase tracking-wider bg-black/70 backdrop-blur-md text-white/90 rounded-md border border-white/20">
                      {{ officers[nextIndex].titleCode }}
                    </span>
                  </div>

                  <!-- Hover Ready Indicator Overlay -->
                  <div class="absolute inset-0 bg-blue-600/15 opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-center justify-center pointer-events-none">
                    <span class="px-2.5 py-1 rounded-lg bg-black/80 backdrop-blur-md text-white font-mono text-[9px] uppercase tracking-wider border border-white/20 shadow-xl flex items-center space-x-1">
                      <span>Click To Select</span>
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
                class="absolute right-2 sm:right-4 z-40 w-11 h-11 sm:w-13 sm:h-13 rounded-2xl bg-[#f8fafc] dark:bg-[#1c1c21]/90 backdrop-blur-md border border-slate-300/90 dark:border-white/10 text-slate-700 dark:text-white flex items-center justify-center shadow-xl hover:scale-110 active:scale-95 hover:bg-blue-600 hover:text-white hover:border-blue-600 dark:hover:bg-blue-600 transition-all cursor-pointer group"
              >
                <ChevronRight class="w-6 h-6 group-hover:translate-x-0.5 transition-transform" />
              </button>
            </div>

            <!-- ROSTER SELECTOR BELOW: Circular Profiles with Flat 'C' Indicator circling the selected one -->
            <div class="w-full max-w-xl mt-6 bg-[#f8fafc]/95 dark:bg-[#18181b]/80 backdrop-blur-xl p-3.5 sm:p-4 rounded-3xl border border-slate-300/80 dark:border-neutral-800 shadow-xl">
              <div class="flex items-center justify-around gap-1 sm:gap-2">
                
                <button
                  v-for="(officer, idx) in officers"
                  :key="officer.id"
                  @click="selectOfficer(idx)"
                  class="group flex flex-col items-center transition-all duration-300 cursor-pointer relative py-1 focus:outline-none"
                  :class="selectedIndex === idx ? 'scale-105 -translate-y-1' : 'opacity-65 hover:opacity-100 hover:scale-105'"
                >
                  <!-- Circular Profile Avatar with Flat 'C' Indicator -->
                  <div class="relative w-14 h-14 sm:w-16 sm:h-16 flex items-center justify-center">
                    
                    <!-- Flat "C" Bracket SVG hugging the selected circular avatar (NOT a full "O", but an open flat "C" caliper) -->
                    <svg 
                      v-if="selectedIndex === idx"
                      viewBox="0 0 68 68" 
                      class="absolute -inset-1.5 w-[76px] h-[76px] pointer-events-none text-blue-600 dark:text-blue-400 drop-shadow-[0_0_8px_rgba(37,99,235,0.6)] animate-pulse"
                    >
                      <!-- Flat "C" caliper: horizontal top, smooth curve left, horizontal bottom -->
                      <path 
                        d="M 48 8 L 24 8 C 13 8, 7 17, 7 34 C 7 51, 13 60, 24 60 L 48 60" 
                        fill="none" 
                        stroke="currentColor" 
                        stroke-width="3.5" 
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      />
                      <!-- Flat accent end nodes -->
                      <circle cx="48" cy="8" r="2.5" fill="currentColor" />
                      <circle cx="48" cy="60" r="2.5" fill="currentColor" />
                    </svg>

                    <!-- Circular Avatar Image -->
                    <div 
                      class="w-12 h-12 sm:w-14 sm:h-14 rounded-full overflow-hidden transition-all duration-300"
                      :class="selectedIndex === idx 
                        ? 'ring-2 ring-blue-500 shadow-lg shadow-blue-500/30' 
                        : 'border-2 border-slate-300 dark:border-neutral-700/80 group-hover:border-blue-400'"
                    >
                      <img 
                        :src="officer.image" 
                        :alt="officer.name" 
                        class="w-full h-full object-cover object-top"
                      />
                    </div>

                    <!-- Active Green Ping Dot -->
                    <span 
                      v-if="selectedIndex === idx" 
                      class="absolute -top-0.5 right-1 w-2.5 h-2.5 rounded-full bg-emerald-500 ring-2 ring-white dark:ring-[#18181b]"
                    ></span>
                  </div>

                  <!-- Role Pill Tag Underneath -->
                  <div class="mt-1.5 text-center">
                    <span 
                      class="text-[9px] sm:text-[10px] font-black tracking-wider uppercase px-2 py-0.5 rounded-full transition-all block truncate max-w-[70px] sm:max-w-[85px]"
                      :class="selectedIndex === idx 
                        ? 'bg-blue-600 text-white shadow-xs' 
                        : 'text-slate-600 dark:text-neutral-400 group-hover:text-blue-600 dark:group-hover:text-blue-400'"
                    >
                      {{ officer.titleCode.replace('BAND ', '') }}
                    </span>
                  </div>
                </button>

              </div>
            </div>

            <!-- Interactive Hint -->
            <div class="mt-3 flex items-center space-x-2 text-slate-500 dark:text-neutral-500 text-[11px] font-medium font-mono">
              <span>← Hover cards to preview • Click to switch officers →</span>
            </div>

          </div>

          <!-- RIGHT SIDE: Profile Details Dossier (Dimmed Surfaces in Light Mode) -->
          <div class="lg:col-span-6 xl:col-span-5">
            <div class="p-8 sm:p-10 rounded-3xl bg-[#f8fafc] dark:bg-[#18181b] border border-slate-300/80 dark:border-neutral-800 shadow-xl relative overflow-hidden transition-all duration-300">
              
              <!-- Subtle Background Watermark Glow -->
              <div class="absolute -top-20 -right-20 w-56 h-56 bg-blue-500/10 dark:bg-blue-500/15 rounded-full blur-3xl pointer-events-none"></div>

              <!-- Top Status HUD -->
              <div class="flex items-center justify-between pb-6 border-b border-slate-200/80 dark:border-neutral-800/80 mb-6">
                <div class="flex items-center space-x-2">
                  <span class="w-2.5 h-2.5 rounded-full bg-emerald-500 animate-pulse"></span>
                  <span class="text-xs font-black font-mono uppercase tracking-widest text-slate-500 dark:text-neutral-400">
                    STATUS: ACTIVE ROSTER
                  </span>
                </div>
                <span class="text-xs font-mono font-bold text-blue-700 dark:text-blue-400 bg-blue-600/10 dark:bg-blue-500/10 px-2.5 py-1 rounded-md border border-blue-300/60 dark:border-blue-500/20">
                  DOSSIER #0{{ selectedIndex + 1 }}
                </span>
              </div>

              <!-- Role & Title Display -->
              <div class="mb-4">
                <div class="inline-flex items-center space-x-2 bg-gradient-to-r from-blue-600 to-indigo-600 text-white font-black text-xs px-3 py-1.5 rounded-lg uppercase tracking-wider mb-3 shadow-md shadow-blue-500/20">
                  <Award class="w-3.5 h-3.5" />
                  <span>{{ currentOfficer.role }}</span>
                  <span class="opacity-75 font-normal">({{ currentOfficer.titleCode }})</span>
                </div>
                
                <h3 class="text-3xl sm:text-4xl font-black text-slate-800 dark:text-white tracking-tight mb-2">
                  {{ currentOfficer.name }}
                </h3>

                <p class="text-sm font-bold text-blue-700 dark:text-blue-400 flex items-center">
                  <Music class="w-4 h-4 mr-2" />
                  {{ currentOfficer.instrument }}
                </p>
              </div>

              <!-- Quote Card (Dimmed in light mode) -->
              <div class="p-4 rounded-2xl bg-[#edf1f5] dark:bg-neutral-900/70 border border-slate-300/70 dark:border-neutral-800 mb-6 italic text-sm text-slate-700 dark:text-neutral-300 leading-relaxed font-medium">
                “{{ currentOfficer.quote }}”
              </div>

              <!-- Bio Description -->
              <p class="text-sm text-slate-600 dark:text-neutral-400 leading-relaxed mb-6 font-medium">
                {{ currentOfficer.bio }}
              </p>

              <!-- Game Character Stat HUD (2x2 Grid with Dimmed Surfaces) -->
              <div class="grid grid-cols-2 gap-3 mb-6">
                <div 
                  v-for="(stat, sIdx) in currentOfficer.stats" 
                  :key="sIdx"
                  class="p-3.5 rounded-xl bg-[#edf1f5] dark:bg-neutral-900/60 border border-slate-300/70 dark:border-neutral-800/80 flex flex-col"
                >
                  <span class="text-[10px] font-bold uppercase tracking-wider text-slate-400 dark:text-neutral-500 mb-1">
                    {{ stat.label }}
                  </span>
                  <span class="text-sm font-black text-slate-800 dark:text-white">
                    {{ stat.value }}
                  </span>
                </div>
              </div>

              <!-- Specialization Tags -->
              <div>
                <span class="text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-neutral-500 block mb-2 font-mono">
                  KEY RESPONSIBILITIES //
                </span>
                <div class="flex flex-wrap gap-2">
                  <span 
                    v-for="(tag, tIdx) in currentOfficer.tags" 
                    :key="tIdx"
                    class="text-xs font-semibold px-3 py-1 rounded-lg bg-blue-600/10 text-blue-800 dark:text-blue-300 border border-blue-300/60 dark:border-blue-500/20"
                  >
                    {{ tag }}
                  </span>
                </div>
              </div>

            </div>
          </div>

        </div>

      </div>
    </section>

  </div>
</template>
