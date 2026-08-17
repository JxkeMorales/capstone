import { defineStore } from 'pinia'

export const useUIStore = defineStore('ui', {
  state: () => ({
    toasts: []
  }),
  actions: {
    addToast({ title, message, type = 'info', duration = 4000 }) {
      const id = Date.now().toString() + Math.random().toString(36).substr(2, 9)
      this.toasts.push({ id, title, message, type })
      
      if (duration > 0) {
        setTimeout(() => {
          this.removeToast(id)
        }, duration)
      }
    },
    removeToast(id) {
      const index = this.toasts.findIndex(t => t.id === id)
      if (index > -1) {
        this.toasts.splice(index, 1)
      }
    },
    playChime() {
      try {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext
        if (!AudioContextClass) return
        const ctx = new AudioContextClass()
        if (ctx.state === 'suspended') ctx.resume()
        
        const now = ctx.currentTime
        const osc = ctx.createOscillator()
        const gain = ctx.createGain()
        
        // A soft, pleasant chime frequency
        osc.type = 'sine'
        osc.frequency.setValueAtTime(880, now)
        osc.frequency.exponentialRampToValueAtTime(1760, now + 0.1)
        
        gain.gain.setValueAtTime(0, now)
        gain.gain.linearRampToValueAtTime(0.5, now + 0.05)
        gain.gain.exponentialRampToValueAtTime(0.01, now + 1)
        
        osc.connect(gain)
        gain.connect(ctx.destination)
        
        osc.start(now)
        osc.stop(now + 1)
      } catch (e) {
        console.warn('Audio chime failed:', e)
      }
    }
  }
})
