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
  <!-- Global Non-Intrusive iOS-style Toast Banner Container -->
  <div class="fixed top-3 left-1/2 -translate-x-1/2 z-[100] flex flex-col items-center space-y-2 w-11/12 max-w-sm pointer-events-none">
    <TransitionGroup 
      enter-active-class="transition duration-250 ease-out"
      enter-from-class="transform -translate-y-3 opacity-0 scale-95"
      enter-to-class="transform translate-y-0 opacity-100 scale-100"
      leave-active-class="transition duration-200 ease-in"
      leave-from-class="transform translate-y-0 opacity-100 scale-100"
      leave-to-class="transform -translate-y-3 opacity-0 scale-95"
    >
      <div 
        v-for="toast in uiStore.toasts" 
        :key="toast.id"
        class="w-full bg-white dark:bg-[#1e1f20] text-slate-900 dark:text-neutral-100 rounded-2xl shadow-md border border-slate-200 dark:border-[#2d3035] px-3.5 py-2.5 flex items-center space-x-3 pointer-events-auto"
      >
        <!-- Icon (Dual-Coding Sensory Independence Table 6) -->
        <div class="flex-shrink-0">
          <component :is="getIcon(toast.type)" class="w-4 h-4" :class="getIconColor(toast.type)" />
        </div>
        
        <!-- Content -->
        <div class="flex-1 min-w-0 pr-1">
          <h4 v-if="toast.title" class="font-semibold text-xs text-slate-900 dark:text-white tracking-tight truncate">
            {{ toast.title }}
          </h4>
          <p v-if="toast.message" class="text-[11px] text-slate-500 dark:text-neutral-400 leading-tight mt-0.5 line-clamp-2">
            {{ toast.message }}
          </p>
        </div>

        <!-- Close Button (Min 40x40px hit area) -->
        <button 
          @click="uiStore.removeToast(toast.id)"
          class="flex-shrink-0 text-slate-400 hover:text-slate-600 dark:hover:text-neutral-200 transition-colors cursor-pointer min-w-[36px] min-h-[36px] flex items-center justify-center rounded-full hover:bg-slate-100 dark:hover:bg-neutral-800"
          aria-label="Dismiss Notification"
        >
          <X class="w-4 h-4" />
        </button>
      </div>
    </TransitionGroup>
  </div>
</template>
