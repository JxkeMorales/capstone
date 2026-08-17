<script setup>
import { useUIStore } from '@/stores/ui'
import { CheckCircle2, AlertCircle, Info, AlertTriangle, X } from 'lucide-vue-next'

const uiStore = useUIStore()

const getIcon = (type) => {
  switch (type) {
    case 'success': return CheckCircle2
    case 'error': return AlertCircle
    case 'warning': return AlertTriangle
    default: return Info
  }
}

const getIconColor = (type) => {
  switch (type) {
    case 'success': return 'text-emerald-500'
    case 'error': return 'text-rose-500'
    case 'warning': return 'text-amber-500'
    default: return 'text-blue-500'
  }
}
</script>

<template>
  <!-- Global Toast Container -->
  <div class="fixed top-4 left-1/2 -translate-x-1/2 z-[100] flex flex-col items-center space-y-3 w-11/12 max-w-md pointer-events-none">
    <TransitionGroup 
      enter-active-class="transition duration-300 ease-out"
      enter-from-class="transform -translate-y-4 opacity-0 scale-95"
      enter-to-class="transform translate-y-0 opacity-100 scale-100"
      leave-active-class="transition duration-200 ease-in"
      leave-from-class="transform translate-y-0 opacity-100 scale-100"
      leave-to-class="transform -translate-y-4 opacity-0 scale-95"
    >
      <div 
        v-for="toast in uiStore.toasts" 
        :key="toast.id"
        class="w-full bg-white dark:bg-[#1c1c1e] text-slate-900 dark:text-white rounded-2xl shadow-2xl border border-slate-200 dark:border-neutral-800 p-4 flex items-start space-x-3 pointer-events-auto"
      >
        <!-- Icon -->
        <div class="flex-shrink-0 mt-0.5">
          <component :is="getIcon(toast.type)" class="w-5 h-5" :class="getIconColor(toast.type)" />
        </div>
        
        <!-- Content -->
        <div class="flex-1 min-w-0">
          <h4 v-if="toast.title" class="font-black text-sm text-slate-900 dark:text-white tracking-tight">
            {{ toast.title }}
          </h4>
          <p class="text-xs font-bold text-slate-600 dark:text-neutral-400 mt-0.5 leading-relaxed">
            {{ toast.message }}
          </p>
        </div>

        <!-- Close Button -->
        <button 
          @click="uiStore.removeToast(toast.id)"
          class="flex-shrink-0 text-slate-400 hover:text-slate-600 dark:hover:text-white transition-colors cursor-pointer"
        >
          <X class="w-4 h-4" />
        </button>
      </div>
    </TransitionGroup>
  </div>
</template>
