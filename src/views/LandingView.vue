import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { Music, ArrowRight, ShieldCheck, Calendar, Users, Cpu, Sun, Moon } from 'lucide-vue-next'

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
</script>

<template>
  <div class="min-h-screen bg-white dark:bg-[#121214] text-slate-900 dark:text-white selection:bg-blue-600 selection:text-white font-sans overflow-x-hidden transition-colors duration-300">
    
    <!-- Navigation Bar -->
    <nav class="fixed top-0 left-0 right-0 z-50 bg-white/80 dark:bg-[#121214]/80 backdrop-blur-xl border-b border-slate-200 dark:border-neutral-800/50 transition-colors duration-300">
      <div class="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class="p-2.5 bg-blue-600 rounded-xl shadow-lg shadow-blue-900/20">
            <Music class="w-6 h-6 text-white" />
          </div>
          <span class="text-xl font-black tracking-tight text-slate-900 dark:text-white">SmartBand</span>
        </div>
        <div class="flex items-center space-x-3">
          <button @click="toggleTheme" class="p-2.5 rounded-xl bg-slate-100 dark:bg-white/10 hover:bg-slate-200 dark:hover:bg-white/20 text-slate-600 dark:text-white transition-all cursor-pointer border border-transparent dark:border-white/5">
            <Sun v-if="!isDark" class="w-4 h-4" />
            <Moon v-else class="w-4 h-4" />
          </button>
          <button @click="goToLogin" class="text-sm font-bold bg-slate-100 dark:bg-white/10 hover:bg-slate-200 dark:hover:bg-white/20 text-slate-900 dark:text-white px-5 py-2.5 rounded-xl transition-all border border-transparent dark:border-white/5 cursor-pointer">
            Member Login
          </button>
        </div>
      </div>
    </nav>

    <!-- Hero Section -->
    <main class="relative pt-32 pb-20 lg:pt-48 lg:pb-32 overflow-hidden min-h-[90vh] flex items-center">
      <!-- Background Image with Overlay -->
      <div class="absolute inset-0 z-0">
        <img src="/hero-band.jpg" alt="Municipal Band Performance" class="w-full h-full object-cover object-center opacity-40 scale-105" />
        <div class="absolute inset-0 bg-gradient-to-t from-white via-white/80 dark:from-[#121214] dark:via-[#121214]/80 to-transparent transition-colors duration-300"></div>
        <div class="absolute inset-0 bg-gradient-to-r from-white via-white/70 dark:from-[#121214] dark:via-[#121214]/70 to-transparent transition-colors duration-300"></div>
      </div>

      <div class="relative z-10 max-w-7xl mx-auto px-6 w-full">
        <div class="max-w-3xl">
          <div class="inline-flex items-center space-x-2 bg-blue-500/10 border border-blue-500/20 text-blue-600 dark:text-blue-400 px-4 py-2 rounded-full text-xs font-bold uppercase tracking-widest mb-8">
            <span class="relative flex h-2 w-2 mr-1">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-blue-500"></span>
            </span>
            Enterprise Band Operations
          </div>
          
          <h1 class="text-5xl sm:text-6xl lg:text-7xl font-black text-slate-900 dark:text-white leading-[1.1] tracking-tight mb-8 drop-shadow-2xl">
            Symphonic <br/><span class="text-transparent bg-clip-text bg-gradient-to-r from-blue-600 to-indigo-600 dark:from-blue-400 dark:to-indigo-500">Precision.</span>
          </h1>
          
          <p class="text-lg sm:text-xl text-slate-700 dark:text-neutral-300 font-medium leading-relaxed mb-10 max-w-2xl drop-shadow-lg">
            The all-in-one portal for municipal band members. Access your rehearsal schedules, gig call-times, and attendance reliability scores from one centralized dashboard.
          </p>
          
          <div class="flex flex-col sm:flex-row items-center space-y-4 sm:space-y-0 sm:space-x-4">
            <button @click="goToLogin" class="w-full sm:w-auto bg-blue-600 hover:bg-blue-500 text-white font-black text-sm px-8 py-4 rounded-2xl shadow-xl shadow-blue-900/30 transition-all flex items-center justify-center group cursor-pointer border border-blue-400/20">
              Access Dashboard
              <ArrowRight class="w-4 h-4 ml-2 group-hover:translate-x-1 transition-transform" />
            </button>
          </div>
        </div>
      </div>
    </main>

    <!-- Features Section -->
    <section class="bg-slate-50 dark:bg-[#121214] py-24 relative z-10 transition-colors duration-300">
      <div class="max-w-7xl mx-auto px-6">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div class="p-8 bg-white dark:bg-[#18181b] rounded-3xl border border-slate-200 dark:border-neutral-800 shadow-xl">
            <div class="w-12 h-12 bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 rounded-2xl flex items-center justify-center mb-6">
              <Calendar class="w-6 h-6" />
            </div>
            <h3 class="text-xl font-black text-slate-900 dark:text-white mb-3">Automated Call-Times</h3>
            <p class="text-slate-600 dark:text-neutral-400 text-sm leading-relaxed font-medium">Real-time schedule synchronization for rehearsals, funeral processions, and civic parades.</p>
          </div>
          
          <div class="p-8 bg-white dark:bg-[#18181b] rounded-3xl border border-slate-200 dark:border-neutral-800 shadow-xl">
            <div class="w-12 h-12 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 rounded-2xl flex items-center justify-center mb-6">
              <ShieldCheck class="w-6 h-6" />
            </div>
            <h3 class="text-xl font-black text-slate-900 dark:text-white mb-3">Reliability Scoring</h3>
            <p class="text-slate-600 dark:text-neutral-400 text-sm leading-relaxed font-medium">Transparent tracking of attendance and commitment scores calculated dynamically.</p>
          </div>
          
          <div class="p-8 bg-white dark:bg-[#18181b] rounded-3xl border border-slate-200 dark:border-neutral-800 shadow-xl">
            <div class="w-12 h-12 bg-rose-500/10 text-rose-600 dark:text-rose-400 rounded-2xl flex items-center justify-center mb-6">
              <Cpu class="w-6 h-6" />
            </div>
            <h3 class="text-xl font-black text-slate-900 dark:text-white mb-3">Offline-First PWA</h3>
            <p class="text-slate-600 dark:text-neutral-400 text-sm leading-relaxed font-medium">Built to function flawlessly even with poor connectivity during outdoor gigs and parades.</p>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
