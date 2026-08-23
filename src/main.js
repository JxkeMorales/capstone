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

// GLOBAL AUTO-PROPER CASING: Capitalize first letter of words on input blur
document.addEventListener('blur', (e) => {
  const el = e.target
  if (
    (el.tagName === 'INPUT' && (el.type === 'text' || el.type === 'search')) ||
    el.tagName === 'TEXTAREA'
  ) {
    if (el.value && typeof el.value === 'string') {
      // Ignore text that's already uppercase or seems to be a URL
      if (el.value.startsWith('http') || el.value.startsWith('www')) return
      
      const newVal = el.value.replace(/(^\w{1})|(\s+\w{1})/g, letter => letter.toUpperCase())
      if (el.value !== newVal) {
        el.value = newVal
        el.dispatchEvent(new Event('input')) // Trigger Vue v-model update
      }
    }
  }
}, true) // Use capture phase so it triggers before other blurs

app.mount('#app')

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(err => {
      console.error('Service worker registration failed:', err)
    })
  })
}
