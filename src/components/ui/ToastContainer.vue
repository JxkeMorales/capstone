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
        class="w-full bg-white/95 dark:bg-[#1c1c1e]/95 backdrop-blur-md text-slate-900 dark:text-white rounded-2xl shadow-xl border border-slate-200/80 dark:border-neutral-800/80 px-3.5 py-2.5 flex items-center space-x-3 pointer-events-auto"
      >
        <!-- Icon -->
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

        <!-- Close Button -->
        <button 
          @click="uiStore.removeToast(toast.id)"
          class="flex-shrink-0 text-slate-400 hover:text-slate-600 dark:hover:text-neutral-200 transition-colors cursor-pointer p-1 rounded-full hover:bg-slate-100 dark:hover:bg-neutral-800"
          aria-label="Dismiss Notification"
        >
          <X class="w-3.5 h-3.5" />
        </button>
      </div>
    </TransitionGroup>
  </div>
</template>
