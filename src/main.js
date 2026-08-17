import { createApp } from 'vue'
import { createPinia } from 'pinia'
import './style.css'
import App from './App.vue'
import router from './router'
import { supabase } from './supabase'
import { useMainStore } from './stores/main'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)

const store = useMainStore()

// PERSISTENT AUTH LISTENER: Automatically restores session & handles sign out
supabase.auth.onAuthStateChange(async (event, session) => {
  if (session?.user) {
    store.user = session.user
    await store.fetchProfile()
  } else {
    store.user = null
    store.profile = null
    store.currentRole = 'member'
  }
})

app.mount('#app')

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(err => {
      console.error('Service worker registration failed:', err)
    })
  })
}
