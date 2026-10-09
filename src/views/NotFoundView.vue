<script setup>
import { useRouter } from 'vue-router'
import { AlertCircle, ArrowLeft } from 'lucide-vue-next'

const router = useRouter()
</script>

<template>
  <main id="main-content" class="min-h-dvh bg-[#f8fafc] dark:bg-[#121214] flex flex-col items-center justify-center p-6 text-center transition-colors duration-200">
    
    <div class="m3-surface-card max-w-md w-full p-8 sm:p-10 flex flex-col items-center text-center shadow-xs">
      <div class="w-16 h-16 bg-rose-50 dark:bg-rose-950/40 border border-rose-200/80 dark:border-rose-900/40 rounded-full flex items-center justify-center mb-6 text-rose-600 dark:text-rose-400">
        <AlertCircle class="w-8 h-8" />
      </div>

      <h1 class="m3-display-small text-slate-900 dark:text-white font-bold mb-2">
        404
      </h1>
      
      <h2 class="m3-headline-small text-slate-700 dark:text-neutral-200 font-semibold mb-3">
        Page Not Found
      </h2>
      
      <p class="m3-body-medium text-slate-500 dark:text-neutral-400 mb-8 leading-relaxed">
        The page you are looking for doesn't exist or has been moved. Check the URL and try again.
      </p>

      <button 
        @click="router.push('/dashboard')"
        type="button"
        class="m3-btn-filled w-full"
      >
        <ArrowLeft class="w-4 h-4 mr-1" />
        <span>Return to Dashboard</span>
      </button>
    </div>

  </main>
</template>
