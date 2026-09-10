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

// GLOBAL PWA INSTALL PROMPT CAPTURE
window.deferredPrompt = null
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault()
  window.deferredPrompt = e
  window.dispatchEvent(new CustomEvent('pwa-prompt-ready'))
})

// PERSISTENT AUTH LISTENER: Automatically restores session & handles sign out
supabase.auth.onAuthStateChange(async (event, session) => {
  if (session?.user) {
    store.user = session.user
    await store.fetchProfile(true)
  } else {
    store.user = null
    store.profile = null
    store.currentRole = 'member'
    try {
      localStorage.removeItem('smartband_user_profile_cache')
    } catch (e) {}
  }
})

// GLOBAL AUTO-PROPER CASING: Capitalize first letter of words on input blur
document.addEventListener('blur', (e) => {
  const el = e.target
  if (
    (el.tagName === 'INPUT' && (el.type === 'text' || el.type === 'search')) ||
    el.tagName === 'TEXTAREA'
  ) {
    if (el.value && typeof el.value === 'string') {
      // Ignore text that's already uppercase, URLs, emails, or passwords
      if (el.value.startsWith('http') || el.value.startsWith('www') || el.type === 'email' || el.type === 'password' || el.name === 'email' || el.id?.includes('email') || el.autocomplete === 'email') return
      
      const newVal = el.value.replace(/(^\w{1})|(\s+\w{1})/g, letter => letter.toUpperCase())
      if (el.value !== newVal) {
        el.value = newVal
        el.dispatchEvent(new Event('input')) // Trigger Vue v-model update
      }
    }
  }
}, true)

// GLOBAL AUTO-RECOVERY FOR OUTDATED DEPLOYMENT CHUNKS
window.addEventListener('unhandledrejection', (event) => {
  const reason = event?.reason
  const msg = reason?.message || String(reason || '')
  if (
    msg.includes('Failed to fetch dynamically imported module') ||
    msg.includes('Importing a module script failed') ||
    reason?.name === 'ChunkLoadError'
  ) {
    event.preventDefault()
    console.warn('Recovering from outdated deployment bundle chunk error...', msg)
    const lastReload = parseInt(sessionStorage.getItem('last_chunk_reload') || '0', 10)
    if (Date.now() - lastReload > 8000) {
      sessionStorage.setItem('last_chunk_reload', String(Date.now()))
      window.location.reload()
    }
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
