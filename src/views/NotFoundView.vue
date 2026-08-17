<script setup>
import { useRouter } from 'vue-router'
import { AlertCircle, ArrowLeft } from 'lucide-vue-next'

const router = useRouter()
</script>

<template>
  <div class="min-h-screen bg-slate-50 dark:bg-[#09090b] flex flex-col items-center justify-center p-6 text-center transition-colors duration-300 relative overflow-hidden">
    <!-- Abstract Background Blur -->
    <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-blue-600/20 dark:bg-blue-600/10 rounded-full blur-3xl -z-10"></div>
    
    <div class="w-20 h-20 bg-rose-100 dark:bg-rose-500/10 rounded-full flex items-center justify-center mb-6 border border-rose-200 dark:border-rose-500/20 shadow-lg shadow-rose-500/10 animate-bounce">
      <AlertCircle class="w-10 h-10 text-rose-600 dark:text-rose-500" />
    </div>

    <h1 class="text-6xl font-black text-slate-900 dark:text-white tracking-tighter mb-2">
      404
    </h1>
    <h2 class="text-2xl font-extrabold text-slate-700 dark:text-neutral-200 tracking-tight mb-4">
      Page Not Found
    </h2>
    <p class="text-sm font-medium text-slate-500 dark:text-neutral-400 max-w-sm mx-auto mb-10 leading-relaxed">
      The page you are looking for doesn't exist or has been moved. Check the URL and try again.
    </p>

    <button 
      @click="router.push('/')"
      class="px-6 py-3.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-slate-100 text-white dark:text-slate-900 rounded-2xl font-black text-sm flex items-center transition-all shadow-xl shadow-slate-900/10 dark:shadow-white/10 hover:-translate-y-0.5 active:translate-y-0 cursor-pointer"
    >
      <ArrowLeft class="w-4 h-4 mr-2" />
      Return to Dashboard
    </button>
  </div>
</template>
