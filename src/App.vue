<script setup>
import { onMounted } from 'vue'
import { RouterView } from 'vue-router'
import { useMainStore } from './stores/main'
import ToastContainer from './components/ui/ToastContainer.vue'

const store = useMainStore()

onMounted(() => {
  store.fetchSession()
  // Initialize theme based on preference or default to dark
  if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
    document.documentElement.classList.remove('dark')
  } else {
    document.documentElement.classList.add('dark')
  }
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
