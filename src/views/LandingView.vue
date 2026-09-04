<script setup>
import { useRouter } from 'vue-router'
import { Music, ArrowRight, ShieldCheck, Calendar, Users, Cpu } from 'lucide-vue-next'

const router = useRouter()

const goToLogin = () => {
  router.push('/login')
}
</script>

<template>
  <div class="min-h-screen bg-[#121214] text-white selection:bg-blue-600 selection:text-white font-sans overflow-x-hidden">
    
    <!-- Navigation Bar -->
    <nav class="fixed top-0 left-0 right-0 z-50 bg-[#121214]/80 backdrop-blur-xl border-b border-neutral-800/50">
      <div class="max-w-7xl mx-auto px-6 h-20 flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <div class="p-2.5 bg-blue-600 rounded-xl shadow-lg shadow-blue-900/20">
            <Music class="w-6 h-6 text-white" />
          </div>
          <span class="text-xl font-black tracking-tight text-white">SmartBand</span>
        </div>
        <div>
          <button @click="goToLogin" class="text-sm font-bold bg-white/10 hover:bg-white/20 text-white px-5 py-2.5 rounded-xl transition-all border border-white/5 cursor-pointer">
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
        <div class="absolute inset-0 bg-gradient-to-t from-[#121214] via-[#121214]/80 to-transparent"></div>
        <div class="absolute inset-0 bg-gradient-to-r from-[#121214] via-[#121214]/70 to-transparent"></div>
      </div>

      <div class="relative z-10 max-w-7xl mx-auto px-6 w-full">
        <div class="max-w-3xl">
          <div class="inline-flex items-center space-x-2 bg-blue-500/10 border border-blue-500/20 text-blue-400 px-4 py-2 rounded-full text-xs font-bold uppercase tracking-widest mb-8">
            <span class="relative flex h-2 w-2 mr-1">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75"></span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-blue-500"></span>
            </span>
            Enterprise Band Operations
          </div>
          
          <h1 class="text-5xl sm:text-6xl lg:text-7xl font-black text-white leading-[1.1] tracking-tight mb-8 drop-shadow-2xl">
            Symphonic <br/><span class="text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-indigo-500">Precision.</span>
          </h1>
          
          <p class="text-lg sm:text-xl text-neutral-300 font-medium leading-relaxed mb-10 max-w-2xl drop-shadow-lg">
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
    <section class="bg-[#121214] py-24 relative z-10">
      <div class="max-w-7xl mx-auto px-6">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <div class="p-8 bg-[#18181b] rounded-3xl border border-neutral-800 shadow-xl">
            <div class="w-12 h-12 bg-indigo-500/10 text-indigo-400 rounded-2xl flex items-center justify-center mb-6">
              <Calendar class="w-6 h-6" />
            </div>
            <h3 class="text-xl font-black text-white mb-3">Automated Call-Times</h3>
            <p class="text-neutral-400 text-sm leading-relaxed font-medium">Real-time schedule synchronization for rehearsals, funeral processions, and civic parades.</p>
          </div>
          
          <div class="p-8 bg-[#18181b] rounded-3xl border border-neutral-800 shadow-xl">
            <div class="w-12 h-12 bg-emerald-500/10 text-emerald-400 rounded-2xl flex items-center justify-center mb-6">
              <ShieldCheck class="w-6 h-6" />
            </div>
            <h3 class="text-xl font-black text-white mb-3">Reliability Scoring</h3>
            <p class="text-neutral-400 text-sm leading-relaxed font-medium">Transparent tracking of attendance and commitment scores calculated dynamically.</p>
          </div>
          
          <div class="p-8 bg-[#18181b] rounded-3xl border border-neutral-800 shadow-xl">
            <div class="w-12 h-12 bg-rose-500/10 text-rose-400 rounded-2xl flex items-center justify-center mb-6">
              <Cpu class="w-6 h-6" />
            </div>
            <h3 class="text-xl font-black text-white mb-3">Offline-First PWA</h3>
            <p class="text-neutral-400 text-sm leading-relaxed font-medium">Built to function flawlessly even with poor connectivity during outdoor gigs and parades.</p>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
