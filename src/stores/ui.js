import { defineStore } from 'pinia'

export const useUIStore = defineStore('ui', {
  state: () => ({
    toasts: []
  }),
  actions: {
    addToast({ title, message, type = 'info', duration = 4000 }) {
      const trimmedTitle = (title || '').trim()
      const trimmedMsg = (message || '').trim()

      // Deduplication: Avoid stacking identical or same-title notifications
      const isDuplicate = this.toasts.some(t => 
        (t.title === trimmedTitle && t.message === trimmedMsg) ||
        (trimmedTitle && t.title === trimmedTitle)
      )
      if (isDuplicate) return

      // Cap visible toasts to maximum 2 so it never clutters or blocks the UI
      while (this.toasts.length >= 2) {
        this.toasts.shift()
      }

      const id = Date.now().toString() + Math.random().toString(36).substr(2, 9)
      this.toasts.push({ id, title: trimmedTitle, message: trimmedMsg, type })
      
      const effectiveDuration = duration > 0 ? Math.min(duration, 5000) : 4000
      setTimeout(() => {
        this.removeToast(id)
      }, effectiveDuration)
    },
    removeToast(id) {
      const index = this.toasts.findIndex(t => t.id === id)
      if (index > -1) {
        this.toasts.splice(index, 1)
      }
    },
    clearAllToasts() {
      this.toasts = []
    },
    // Authentic iOS Notification Chime (Tri-Tone / Note)
    playIOSNotificationSound() {
      try {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext
        if (!AudioContextClass) return
        const ctx = new AudioContextClass()
        if (ctx.state === 'suspended') ctx.resume()
        
        const now = ctx.currentTime

        // Authentic iOS Tri-Tone frequency progression:
        // Note 1: G#5 (830.61 Hz)
        // Note 2: B5 (987.77 Hz)
        // Note 3: E6 (1318.51 Hz)
        const notes = [
          { freq: 830.61, start: now, dur: 0.085, gain: 0.18 },
          { freq: 987.77, start: now + 0.085, dur: 0.085, gain: 0.20 },
          { freq: 1318.51, start: now + 0.17, dur: 0.45, gain: 0.24 }
        ]

        notes.forEach(({ freq, start, dur, gain }) => {
          const osc = ctx.createOscillator()
          const gainNode = ctx.createGain()
          osc.type = 'sine'
          osc.frequency.setValueAtTime(freq, start)

          // Smooth 4ms linear attack prevents speaker pop, followed by gentle exponential bell ring-out
          gainNode.gain.setValueAtTime(0.0001, start)
          gainNode.gain.linearRampToValueAtTime(gain, start + 0.005)
          gainNode.gain.exponentialRampToValueAtTime(0.0001, start + dur)

          // Delicate second harmonic (octave overtone) adds characteristic Apple bell resonance
          const overtone = ctx.createOscillator()
          const overtoneGain = ctx.createGain()
          overtone.type = 'sine'
          overtoneGain.gain.setValueAtTime(0.0001, start)
          overtoneGain.gain.linearRampToValueAtTime(gain * 0.15, start + 0.005)
          overtoneGain.gain.exponentialRampToValueAtTime(0.0001, start + (dur * 0.7))

          osc.connect(gainNode)
          gainNode.connect(ctx.destination)
          overtone.connect(overtoneGain)
          overtoneGain.connect(ctx.destination)

          osc.start(start)
          overtone.start(start)
          osc.stop(start + dur)
          overtone.stop(start + dur)
        })
      } catch (e) {
        console.warn('iOS audio notification notice:', e)
      }
    },
    playChime() {
      this.playIOSNotificationSound()
    },
    // Authentic 5-Second Brass Fanfare Siren for Urgent Call-Times (ISO/IEC 25010 Safety & TC-04)
    playCallTimeFanfare() {
      try {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext
        if (!AudioContextClass) return
        const ctx = new AudioContextClass()
        if (ctx.state === 'suspended') ctx.resume()
        const now = ctx.currentTime

        // Authentic Bb Major Brass Triad Fanfare (Bb4 466Hz, D5 587Hz, F5 698Hz, High Bb5 932Hz)
        // Staccato herald progression followed by a sustained triumphal brass chord
        const notes = [
          { freq: 466.16, start: now + 0.00, dur: 0.35, gain: 0.28 },
          { freq: 587.33, start: now + 0.40, dur: 0.35, gain: 0.30 },
          { freq: 698.46, start: now + 0.80, dur: 0.45, gain: 0.32 },
          { freq: 466.16, start: now + 1.35, dur: 0.22, gain: 0.28 },
          { freq: 587.33, start: now + 1.62, dur: 0.22, gain: 0.30 },
          { freq: 698.46, start: now + 1.90, dur: 0.30, gain: 0.32 },
          { freq: 932.33, start: now + 2.25, dur: 2.25, gain: 0.35 }
        ]

        notes.forEach(({ freq, start, dur, gain }) => {
          const osc = ctx.createOscillator()
          const gainNode = ctx.createGain()
          // Rich brass horn timbre via triangle wave
          osc.type = 'triangle'
          osc.frequency.setValueAtTime(freq, start)

          gainNode.gain.setValueAtTime(0.0001, start)
          gainNode.gain.linearRampToValueAtTime(gain, start + 0.035)
          gainNode.gain.exponentialRampToValueAtTime(0.0001, start + dur)

          // Harmonic overtone adds realistic brass resonance
          const overtone = ctx.createOscillator()
          const overtoneGain = ctx.createGain()
          overtone.type = 'sine'
          overtone.frequency.setValueAtTime(freq * 2, start)
          overtoneGain.gain.setValueAtTime(0.0001, start)
          overtoneGain.gain.linearRampToValueAtTime(gain * 0.2, start + 0.035)
          overtoneGain.gain.exponentialRampToValueAtTime(0.0001, start + dur)

          osc.connect(gainNode)
          gainNode.connect(ctx.destination)
          overtone.connect(overtoneGain)
          overtoneGain.connect(ctx.destination)

          osc.start(start)
          overtone.start(start)
          osc.stop(start + dur)
          overtone.stop(start + dur)
        })

        // Standard emergency alert vibration pattern: [300ms pulse, 150ms rest, 300ms pulse, 150ms rest, 600ms pulse]
        if (typeof navigator !== 'undefined' && navigator.vibrate) {
          navigator.vibrate([300, 150, 300, 150, 600])
        }
      } catch (e) {
        console.warn('Call-time brass fanfare audio notice:', e)
      }
    },
    playAlarmSiren() {
      this.playCallTimeFanfare()
    }
  }
})
