<script setup>
import { onMounted } from 'vue'
import { RouterView } from 'vue-router'
import { useMainStore } from './stores/main'
import ToastContainer from './components/ui/ToastContainer.vue'

const store = useMainStore()

onMounted(() => {
  store.fetchSession()
  // Initialize theme globally based on localStorage
  const savedTheme = localStorage.getItem('smartband_theme')
  if (savedTheme === 'light') {
    document.documentElement.classList.remove('dark')
  } else {
    document.documentElement.classList.add('dark')
  }

  // ANTI-LOGOUT SLEEPING TAB FIX
  // Prevents Supabase from revoking sessions when a PC wakes up from sleep and tries to use an old token
  let hiddenTime = 0
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      hiddenTime = Date.now()
    } else {
      // If tab was hidden/sleeping for more than 45 minutes, hard refresh to grab latest state & connect to Wi-Fi
      if (hiddenTime && (Date.now() - hiddenTime > 2700000)) {
        window.location.reload()
      } else {
        // Just sync memory with localStorage to prevent cross-tab out-of-sync tokens
        import('@/supabase').then(({ supabase }) => {
          supabase.auth.getSession()
        })
      }
    }
  })
})
</script>

<template>
  <div class="min-h-screen bg-slate-50 dark:bg-slate-900 text-slate-900 dark:text-slate-100 transition-colors duration-300">
    <ToastContainer />
    <RouterView />
  </div>
</template>

<style scoped>
</style>
