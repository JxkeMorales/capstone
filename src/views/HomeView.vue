<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { Music, Mail, Lock, ArrowRight, User, Calendar, Phone, Activity, Sun, Moon, CheckCircle2, AlertCircle, X, ShieldCheck, FileText, Smartphone, Award, Cpu, Eye, EyeOff, Clock, Shield } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useUIStore } from '@/stores/ui'
import { supabase } from '@/supabase'
import { initRealtimeSync, broadcastSync } from '@/utils/realtime'

const router = useRouter()
const store = useMainStore()
const uiStore = useUIStore()

const activeTab = ref('signin') // 'signin' or 'signup'
const isDark = ref(true)

onMounted(() => {
  initRealtimeSync()
  const savedTheme = localStorage.getItem('smartband_theme')
  if (savedTheme === 'light') {
    isDark.value = false
  } else if (savedTheme === 'dark') {
    isDark.value = true
  } else {
    isDark.value = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
  }
  document.documentElement.classList.toggle('dark', isDark.value)
})
// Password Visibility Toggles
const showPassword = ref(false)

const toggleTheme = () => {
  isDark.value = !isDark.value
  if (isDark.value) {
    document.documentElement.classList.add('dark')
    localStorage.setItem('smartband_theme', 'dark')
  } else {
    document.documentElement.classList.remove('dark')
    localStorage.setItem('smartband_theme', 'light')
  }
}

// Form State
const email = ref('')
const password = ref('')
const fullName = ref('')
const birthDate = ref('')
const sex = ref('')
const contactNumber = ref('')
const primaryInstrument = ref('')
const secondaryInstrument = ref('None / N/A')
const termsAccepted = ref(false)

// Modals State
const showForgotPasswordModal = ref(false)
const resetEmail = ref('')
const resetSent = ref(false)
const resetLoading = ref(false)

const showTermsModal = ref(false)

// Status & Error Feedback State
const isLoading = ref(false)
const errorMessage = ref('')
const signupSuccess = ref(false)

// Philippine Phone Number Formatting & Validation (Starts with 09 and exactly 11 digits)
const handlePhoneInput = (e) => {
  let val = e.target.value.replace(/\D/g, '')
  if (val.length > 11) val = val.slice(0, 11)
  contactNumber.value = val
}

const isPhoneValid = computed(() => {
  if (!contactNumber.value) return true
  return /^09\d{9}$/.test(contactNumber.value)
})

// Complete 18-Instrument / Section Municipal Band List
const instrumentOptions = [
  { value: '', label: 'Select Primary Section / Instrument...' },
  { value: 'Clarinet', label: 'Clarinet' },
  { value: 'Bass Clarinet', label: 'Bass Clarinet' },
  { value: 'Flute', label: 'Flute' },
  { value: 'Piccolo', label: 'Piccolo' },
  { value: 'French Horn', label: 'French Horn' },
  { value: 'Tenor Sax', label: 'Tenor Sax' },
  { value: 'Sax (Alto Sax)', label: 'Sax (Alto Sax)' },
  { value: 'Baritone Sax', label: 'Baritone Sax' },
  { value: 'Trumpet', label: 'Trumpet' },
  { value: 'Trombone', label: 'Trombone' },
  { value: 'Bass Trombone', label: 'Bass Trombone' },
  { value: 'Baritone / Euphonium', label: 'Baritone / Euphonium' },
  { value: 'Bass / Tuba', label: 'Bass / Tuba' },
  { value: 'Bass Drum', label: 'Bass Drum' },
  { value: 'Snare Drum / Drums', label: 'Snare Drum / Drums' },
  { value: 'Cymbals', label: 'Cymbals' },
  { value: 'Majorette', label: 'Majorette' },
  { value: 'Color Guard / Flag', label: 'Color Guard / Flag' }
]

const secondaryInstrumentOptions = [
  { value: 'None / N/A', label: 'None / N/A (Plays 1 Instrument Only)' },
  { value: 'Clarinet', label: 'Clarinet' },
  { value: 'Bass Clarinet', label: 'Bass Clarinet' },
  { value: 'Flute', label: 'Flute' },
  { value: 'Piccolo', label: 'Piccolo' },
  { value: 'French Horn', label: 'French Horn' },
  { value: 'Tenor Sax', label: 'Tenor Sax' },
  { value: 'Sax (Alto Sax)', label: 'Sax (Alto Sax)' },
  { value: 'Baritone Sax', label: 'Baritone Sax' },
  { value: 'Trumpet', label: 'Trumpet' },
  { value: 'Trombone', label: 'Trombone' },
  { value: 'Bass Trombone', label: 'Bass Trombone' },
  { value: 'Baritone / Euphonium', label: 'Baritone / Euphonium' },
  { value: 'Bass / Tuba', label: 'Bass / Tuba' },
  { value: 'Bass Drum', label: 'Bass Drum' },
  { value: 'Snare Drum / Drums', label: 'Snare Drum / Drums' },
  { value: 'Cymbals', label: 'Cymbals' },
  { value: 'Majorette', label: 'Majorette' },
  { value: 'Color Guard / Flag', label: 'Color Guard / Flag' }
]

const handleSubmit = async () => {
  errorMessage.value = ''
  isLoading.value = true

  try {
    const sanitizedEmail = email.value.trim().toLowerCase()
    if (activeTab.value === 'signin') {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: sanitizedEmail,
        password: password.value
      })

      if (error) throw error

      if (data?.user) {
        store.user = data.user
        const prof = await store.fetchProfile(true)
        if (prof && prof.is_verified === false && prof.role === 'member') {
          await supabase.auth.signOut()
          store.user = null
          store.profile = null
          errorMessage.value = 'Account Pending Verification: Your membership has not yet been physically verified by the IT Admin against the municipal master list. Access will be activated once approved.'
          return
        }
      }
      
      try {
        await router.push('/dashboard')
      } catch (navErr) {
        const isChunkErr = 
          navErr?.message?.includes('Failed to fetch dynamically') ||
          navErr?.message?.includes('Importing a module script failed') ||
          navErr?.name === 'ChunkLoadError'
        if (isChunkErr) {
          window.location.href = '/dashboard'
          return
        }
        throw navErr
      }

    } else {
      if (!termsAccepted.value) {
        throw new Error('Please review and accept the Terms & Conditions to register.')
      }

      if (!/^09\d{9}$/.test(contactNumber.value.trim())) {
        throw new Error('Please enter a valid 11-digit Philippine mobile number starting with 09 (e.g. 09123456789).')
      }

      if (!primaryInstrument.value) {
        throw new Error('Please select your primary instrument.')
      }

      const combinedInstrument = secondaryInstrument.value && secondaryInstrument.value !== 'None / N/A'
        ? `${primaryInstrument.value} + ${secondaryInstrument.value}`
        : primaryInstrument.value

      const { data, error } = await supabase.auth.signUp({
        email: sanitizedEmail,
        password: password.value,
        options: {
          data: {
            full_name: fullName.value.trim(),
            birth_date: birthDate.value,
            sex: sex.value,
            contact_number: contactNumber.value.trim(),
            instrument: combinedInstrument
          }
        }
      })

      if (error) throw error

      // Instant global and cross-tab synchronization
      await broadcastSync('new_registration', {
        email: sanitizedEmail,
        full_name: fullName.value.trim(),
        instrument: combinedInstrument,
        timestamp: Date.now()
      })

      signupSuccess.value = true
      password.value = ''
    }
  } catch (err) {
    console.error('Auth Error:', err)
    const isChunkErr = 
      err?.message?.includes('Failed to fetch dynamically') ||
      err?.message?.includes('Importing a module script failed') ||
      err?.name === 'ChunkLoadError'
    if (isChunkErr) {
      window.location.href = '/dashboard'
      return
    }
    errorMessage.value = err?.message || err?.error_description || (typeof err === 'string' ? err : 'Authentication error occurred.')
  } finally {
    isLoading.value = false
  }
}

const handleResetPassword = async () => {
  if (!resetEmail.value) return
  resetLoading.value = true
  errorMessage.value = ''
  try {
    const targetEmail = resetEmail.value.trim().toLowerCase()
    const { error } = await supabase.auth.resetPasswordForEmail(targetEmail, {
      redirectTo: `${window.location.origin}/dashboard/profile`
    })
    if (error) throw error
    resetSent.value = true
  } catch (err) {
    console.error('Reset password error:', err)
    uiStore.addToast({ title: 'Reset Failed', message: err?.message || 'Failed to send password reset email.', type: 'error' })
  } finally {
    resetLoading.value = false
  }
}
</script>

<template>
  <div class="min-h-screen w-full flex flex-col items-center justify-center p-4 sm:p-6 lg:p-12 relative bg-[#f8f9fa] dark:bg-[#18191a] text-slate-800 dark:text-neutral-100 transition-colors duration-300">
    
    <!-- Top Action Bar -->
    <div class="absolute top-4 left-4 right-4 flex items-center justify-between z-10">
      <router-link 
        to="/" 
        class="inline-flex items-center space-x-2 px-3.5 py-2 rounded-full bg-white dark:bg-[#202124] text-slate-600 dark:text-neutral-300 hover:text-slate-900 dark:hover:text-white border border-slate-200 dark:border-neutral-800 text-xs font-medium transition-colors shadow-xs"
      >
        <span>← Band Heritage</span>
      </router-link>

      <!-- Theme Toggle (Sun / Moon) -->
      <button 
        @click="toggleTheme" 
        type="button"
        class="p-2.5 rounded-full bg-white dark:bg-[#202124] text-slate-600 dark:text-neutral-300 hover:bg-slate-100 dark:hover:bg-[#282a2c] transition-colors shadow-xs border border-slate-200 dark:border-neutral-800 min-w-[40px] min-h-[40px] flex items-center justify-center cursor-pointer"
        :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
      >
        <Sun v-if="isDark" class="w-4 h-4 text-amber-400" />
        <Moon v-else class="w-4 h-4 text-slate-600" />
      </button>
    </div>

    <!-- Main Container -->
    <div class="w-full max-w-md md:max-w-4xl lg:max-w-5xl my-auto py-8 pt-16">
      
      <div class="grid grid-cols-1 md:grid-cols-2 gap-8 lg:gap-14 items-center">
        
        <!-- Left Hero Section (Desktop View) -->
        <div class="space-y-6 text-left hidden md:block">
          <div class="flex items-center space-x-3">
            <div class="w-12 h-12 rounded-2xl overflow-hidden border border-slate-200 dark:border-neutral-800 bg-white dark:bg-[#202124] flex items-center justify-center p-1 shrink-0">
              <img src="/band1870logo.jpg" alt="Peñaranda Band 1870" class="w-full h-full object-contain" />
            </div>
            <div>
              <div class="inline-flex items-center px-3 py-1 rounded-full bg-slate-100 dark:bg-neutral-800 text-slate-700 dark:text-neutral-300 text-xs font-medium">
                <span>Peñaranda Band 1870</span>
              </div>
              <p class="text-[11px] font-medium text-slate-400 dark:text-neutral-500 uppercase tracking-wider mt-0.5">Municipal Enterprise PWA</p>
            </div>
          </div>

          <h1 class="text-3xl lg:text-4xl font-bold text-slate-900 dark:text-white leading-tight tracking-tight">
            Automated Band Operations &amp; Gig Scheduling
          </h1>

          <p class="text-slate-600 dark:text-neutral-400 text-sm leading-relaxed">
            Streamlining rehearsal call-times, civic parades, funeral processions, and attendance reliability scoring for municipal musicians and band leaders.
          </p>

          <div class="space-y-3 pt-2">
            <div class="flex items-center space-x-3 text-sm font-medium text-slate-700 dark:text-neutral-300">
              <div class="w-8 h-8 rounded-full bg-slate-100 dark:bg-neutral-800 text-slate-600 dark:text-neutral-400 flex items-center justify-center flex-shrink-0">
                <Cpu class="w-4 h-4" />
              </div>
              <span>Automated Call-Time Siren &amp; Section Dispatch</span>
            </div>

            <div class="flex items-center space-x-3 text-sm font-medium text-slate-700 dark:text-neutral-300">
              <div class="w-8 h-8 rounded-full bg-slate-100 dark:bg-neutral-800 text-slate-600 dark:text-neutral-400 flex items-center justify-center flex-shrink-0">
                <Award class="w-4 h-4" />
              </div>
              <span>Attendance Reliability Score (%) &amp; Roll Call</span>
            </div>

            <div class="flex items-center space-x-3 text-sm font-medium text-slate-700 dark:text-neutral-300">
              <div class="w-8 h-8 rounded-full bg-slate-100 dark:bg-neutral-800 text-slate-600 dark:text-neutral-400 flex items-center justify-center flex-shrink-0">
                <Smartphone class="w-4 h-4" />
              </div>
              <span>Offline-First PWA Cache &amp; Instant Launch</span>
            </div>
          </div>
        </div>

        <!-- Right Authentication Card (Google Material 3 Style) -->
        <div class="w-full">
          
          <div class="bg-white dark:bg-[#202124] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 sm:p-8 shadow-sm relative overflow-hidden">
            
            <!-- Mobile Brand Header -->
            <div class="text-center md:hidden mb-6 space-y-2">
              <div class="w-14 h-14 rounded-2xl overflow-hidden border border-slate-200 dark:border-neutral-800 bg-white mx-auto flex items-center justify-center p-1">
                <img src="/band1870logo.jpg" alt="Peñaranda Band 1870" class="w-full h-full object-contain" />
              </div>
              <h2 class="text-2xl font-bold text-slate-900 dark:text-white tracking-tight">SmartBand</h2>
              <p class="text-xs text-slate-500 dark:text-neutral-400">Peñaranda Band 1870 • Municipal Operations</p>
            </div>

            <!-- Sign In / Sign Up Segmented Tab Bar (Google-style Pill Segment) -->
            <div class="flex p-1 bg-slate-100 dark:bg-[#18191a] rounded-full mb-6 border border-slate-200/80 dark:border-neutral-800" role="tablist">
              <button 
                @click="activeTab = 'signin'; errorMessage = ''; signupSuccess = false"
                type="button" 
                role="tab"
                :aria-selected="activeTab === 'signin'"
                class="flex-1 py-2.5 text-xs sm:text-sm font-semibold rounded-full transition-all cursor-pointer min-h-[40px]"
                :class="activeTab === 'signin' 
                  ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' 
                  : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
              >
                Sign In
              </button>
              <button 
                @click="activeTab = 'signup'; errorMessage = ''; signupSuccess = false"
                type="button" 
                role="tab"
                :aria-selected="activeTab === 'signup'"
                class="flex-1 py-2.5 text-xs sm:text-sm font-semibold rounded-full transition-all cursor-pointer min-h-[40px]"
                :class="activeTab === 'signup' 
                  ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' 
                  : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
              >
                Register
              </button>
            </div>

            <!-- Success Alert after Sign Up (Clear Notice of Pending Verification) -->
            <div v-if="signupSuccess" class="mb-5 p-4 bg-amber-50 dark:bg-amber-950/30 border border-amber-200/80 dark:border-amber-900/40 rounded-2xl text-left space-y-2">
              <div class="flex items-center space-x-2 text-amber-800 dark:text-amber-300 font-semibold text-xs">
                <Clock class="w-4 h-4 flex-shrink-0 text-amber-600 dark:text-amber-400" />
                <span>Registration Submitted for Verification</span>
              </div>
              <p class="text-xs text-slate-600 dark:text-neutral-400 leading-relaxed">
                Your membership application has been queued for verification against the official municipal band master list.
              </p>
              <div class="p-2.5 bg-amber-100/60 dark:bg-amber-900/20 rounded-xl text-[11px] text-amber-900 dark:text-amber-200 flex items-center space-x-2">
                <Shield class="w-3.5 h-3.5 text-amber-600 dark:text-amber-400 flex-shrink-0" />
                <span>You will be able to sign in once your account has been approved.</span>
              </div>
            </div>

            <!-- Error Banner -->
            <div v-if="errorMessage" class="mb-5 p-3.5 bg-rose-50 dark:bg-rose-950/30 border border-rose-200/80 dark:border-rose-900/40 rounded-2xl flex items-start space-x-2 text-rose-700 dark:text-rose-300 text-xs font-medium text-left" role="alert">
              <AlertCircle class="w-4 h-4 text-rose-500 flex-shrink-0 mt-0.5" />
              <span>{{ errorMessage }}</span>
            </div>

            <!-- Form Area -->
            <form @submit.prevent="handleSubmit" class="space-y-4" aria-label="Authentication Form">
              
              <!-- Email Address -->
              <div class="space-y-1.5 text-left">
                <label for="email-input" class="block text-xs font-medium text-slate-700 dark:text-neutral-300">
                  Email Address
                </label>
                <div class="relative">
                  <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                    <Mail class="w-4 h-4 text-slate-400 dark:text-neutral-500" />
                  </div>
                  <input 
                    id="email-input"
                    v-model="email"
                    type="email" 
                    placeholder="you@example.com"
                    autocomplete="email"
                    class="w-full pl-10 pr-4 py-2.5 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600 text-xs min-h-[42px]"
                    required
                  >
                </div>
              </div>

              <!-- Password -->
              <div class="space-y-1.5 text-left">
                <div class="flex items-center justify-between">
                  <label for="password-input" class="block text-xs font-medium text-slate-700 dark:text-neutral-300">
                    Password
                  </label>
                  <button 
                    v-if="activeTab === 'signin'" 
                    @click="showForgotPasswordModal = true; resetSent = false; resetEmail = email"
                    type="button" 
                    class="text-xs font-medium text-slate-600 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white hover:underline cursor-pointer"
                  >
                    Forgot Password?
                  </button>
                </div>
                <div class="relative">
                  <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                    <Lock class="w-4 h-4 text-slate-400 dark:text-neutral-500" />
                  </div>
                  <input 
                    id="password-input"
                    v-model="password"
                    :type="showPassword ? 'text' : 'password'"
                    placeholder="••••••••"
                    autocomplete="current-password"
                    class="w-full pl-10 pr-10 py-2.5 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600 text-xs min-h-[42px]"
                    required
                  >
                  <button 
                    type="button" 
                    @click="showPassword = !showPassword"
                    class="absolute inset-y-0 right-0 pr-3 flex items-center text-slate-400 hover:text-slate-600 dark:hover:text-neutral-200 cursor-pointer"
                  >
                    <Eye v-if="!showPassword" class="w-4 h-4" />
                    <EyeOff v-else class="w-4 h-4" />
                  </button>
                </div>
              </div>

              <!-- SIGN UP SPECIFIC FIELDS -->
              <template v-if="activeTab === 'signup'">
                
                <!-- Full Name & Mobile Number (2 columns on sm+) -->
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 text-left">
                  <div class="space-y-1.5">
                    <label for="fullname-input" class="block text-xs font-medium text-slate-700 dark:text-neutral-300">
                      Full Name
                    </label>
                    <div class="relative">
                      <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                        <User class="w-4 h-4 text-slate-400 dark:text-neutral-500" />
                      </div>
                      <input 
                        id="fullname-input"
                        v-model="fullName"
                        type="text" 
                        placeholder="Juan Dela Cruz"
                        autocomplete="name"
                        class="w-full pl-10 pr-4 py-2.5 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600 text-xs min-h-[42px]"
                        required
                      >
                    </div>
                  </div>

                  <div class="space-y-1.5">
                    <div class="flex items-center justify-between">
                      <label for="phone-input" class="block text-xs font-medium text-slate-700 dark:text-neutral-300">
                        Mobile (11 digits)
                      </label>
                      <span class="text-[10px] font-medium" :class="contactNumber.length === 11 && contactNumber.startsWith('09') ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-400'">
                        {{ contactNumber.length }}/11
                      </span>
                    </div>
                    <div class="relative">
                      <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                        <Phone class="w-4 h-4 text-slate-400 dark:text-neutral-500" />
                      </div>
                      <input 
                        id="phone-input"
                        :value="contactNumber"
                        @input="handlePhoneInput"
                        type="tel" 
                        placeholder="09123456789"
                        maxlength="11"
                        autocomplete="tel"
                        class="w-full pl-10 pr-4 py-2.5 bg-slate-50 dark:bg-[#18191a] border rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none text-xs min-h-[42px]"
                        :class="!isPhoneValid ? 'border-rose-400 focus:border-rose-500' : 'border-slate-200 dark:border-neutral-800 focus:border-slate-400 dark:focus:border-neutral-600'"
                        required
                      >
                    </div>
                  </div>
                </div>
                <p v-if="!isPhoneValid" class="text-[10px] text-rose-500 text-left -mt-1">
                  Must start with 09 and contain exactly 11 digits (e.g. 09123456789).
                </p>

                <!-- Birth Date & Sex (2 columns) -->
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 text-left">
                  <div class="space-y-1.5">
                    <label for="birthdate-input" class="block text-xs font-medium text-slate-700 dark:text-neutral-300">
                      Birth Date
                    </label>
                    <div class="relative">
                      <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                        <Calendar class="w-4 h-4 text-slate-400 dark:text-neutral-500" />
                      </div>
                      <input 
                        id="birthdate-input"
                        v-model="birthDate"
                        type="date" 
                        class="w-full pl-10 pr-3 py-2.5 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white text-xs min-h-[42px] focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600"
                        required
                      >
                    </div>
                  </div>

                  <div class="space-y-1.5">
                    <span class="block text-xs font-medium text-slate-700 dark:text-neutral-300">
                      Sex
                    </span>
                    <div class="flex gap-2">
                      <label class="flex-1 cursor-pointer">
                        <input type="radio" v-model="sex" value="Male" class="peer sr-only" required>
                        <div class="text-center py-2 rounded-xl border border-slate-200 dark:border-neutral-800 bg-slate-50 dark:bg-[#18191a] peer-checked:border-slate-900 dark:peer-checked:border-white peer-checked:bg-slate-100 dark:peer-checked:bg-neutral-800 peer-checked:text-slate-900 dark:peer-checked:text-white font-medium text-xs transition-all min-h-[42px] flex items-center justify-center">
                          Male
                        </div>
                      </label>
                      <label class="flex-1 cursor-pointer">
                        <input type="radio" v-model="sex" value="Female" class="peer sr-only" required>
                        <div class="text-center py-2 rounded-xl border border-slate-200 dark:border-neutral-800 bg-slate-50 dark:bg-[#18191a] peer-checked:border-slate-900 dark:peer-checked:border-white peer-checked:bg-slate-100 dark:peer-checked:bg-neutral-800 peer-checked:text-slate-900 dark:peer-checked:text-white font-medium text-xs transition-all min-h-[42px] flex items-center justify-center">
                          Female
                        </div>
                      </label>
                    </div>
                  </div>
                </div>

                <!-- Primary & Secondary Instruments (2 columns on sm+) -->
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 text-left">
                  <div class="space-y-1.5">
                    <label for="primary-instrument-select" class="block text-xs font-medium text-slate-700 dark:text-neutral-300">
                      Primary Instrument
                    </label>
                    <div class="relative">
                      <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                        <Activity class="w-4 h-4 text-slate-400 dark:text-neutral-500" />
                      </div>
                      <select 
                        id="primary-instrument-select"
                        v-model="primaryInstrument"
                        class="w-full pl-10 pr-4 py-2.5 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white text-xs font-medium focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600 min-h-[42px]"
                        required
                      >
                        <option v-for="inst in instrumentOptions" :key="inst.value" :value="inst.value">
                          {{ inst.label }}
                        </option>
                      </select>
                    </div>
                  </div>

                  <div class="space-y-1.5">
                    <label for="secondary-instrument-select" class="block text-xs font-medium text-slate-700 dark:text-neutral-300">
                      Secondary Instrument
                    </label>
                    <div class="relative">
                      <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                        <Activity class="w-4 h-4 text-slate-400 dark:text-neutral-500" />
                      </div>
                      <select 
                        id="secondary-instrument-select"
                        v-model="secondaryInstrument"
                        class="w-full pl-10 pr-4 py-2.5 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white text-xs font-medium focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600 min-h-[42px]"
                      >
                        <option v-for="inst in secondaryInstrumentOptions" :key="inst.value" :value="inst.value">
                          {{ inst.label }}
                        </option>
                      </select>
                    </div>
                  </div>
                </div>

                <!-- Terms and Conditions Agreement Checkbox -->
                <div class="pt-1 text-left">
                  <label class="flex items-start space-x-2.5 cursor-pointer">
                    <input 
                      type="checkbox" 
                      v-model="termsAccepted" 
                      class="mt-1 w-4 h-4 text-slate-900 dark:text-white bg-slate-100 dark:bg-[#18191a] border-slate-300 dark:border-neutral-700 rounded focus:ring-0 cursor-pointer"
                      required
                    >
                    <span class="text-xs text-slate-600 dark:text-neutral-400 leading-relaxed">
                      I agree to the 
                      <button 
                        @click="showTermsModal = true" 
                        type="button" 
                        class="font-medium text-slate-900 dark:text-neutral-200 hover:underline cursor-pointer"
                      >
                        Municipal Band Terms &amp; Conditions
                      </button> 
                      and physical master list verification.
                    </span>
                  </label>
                </div>

              </template>

              <!-- Submit Button (Google Material 3 Pill Button) -->
              <div class="pt-2">
                <button 
                  type="submit" 
                  :disabled="isLoading"
                  class="w-full py-3 px-5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-slate-100 text-white dark:text-slate-900 font-semibold text-xs sm:text-sm rounded-full flex items-center justify-center space-x-2 transition-all shadow-xs cursor-pointer disabled:opacity-50 min-h-[46px]"
                >
                  <span v-if="isLoading">Processing...</span>
                  <span v-else-if="activeTab === 'signin'" class="flex items-center">
                    Sign In <ArrowRight class="w-4 h-4 ml-1.5" />
                  </span>
                  <span v-else class="flex items-center">
                    Submit Registration <ArrowRight class="w-4 h-4 ml-1.5" />
                  </span>
                </button>
              </div>

            </form>

          </div>

        </div>

      </div>

    </div>

    <!-- TERMS & CONDITIONS MODAL -->
    <div v-if="showTermsModal" class="fixed inset-0 bg-black/60 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#202124] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-lg w-full space-y-4 shadow-xl text-left max-h-[85vh] flex flex-col">
        
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2 text-slate-800 dark:text-neutral-200">
            <FileText class="w-4 h-4" />
            <h3 class="font-bold text-base text-slate-900 dark:text-white">Municipal Band Terms &amp; Conditions</h3>
          </div>
          <button @click="showTermsModal = false" class="text-slate-400 hover:text-slate-600 dark:hover:text-white min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer rounded-full hover:bg-slate-100 dark:hover:bg-neutral-800">
            <X class="w-4 h-4" />
          </button>
        </div>

        <div class="overflow-y-auto flex-1 text-xs text-slate-600 dark:text-neutral-300 space-y-3.5 pr-2 leading-relaxed">
          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 1: Master List Verification Requirement</h4>
            <p>All sign-up applications are provisional until physically verified by the IT Super Admin against the official municipal band registry. Unverified accounts cannot view private contact rosters or access secretary dispatch controls.</p>
          </div>

          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 2: Attendance &amp; RSVP Reliability Scoring</h4>
            <p>Submitting an RSVP of "I Will Attend" is an operational commitment for gig planning. Unexcused absences or sudden cancellations directly impact your personal Reliability Score (%) and future gig prioritization.</p>
          </div>

          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 3: Call-Time Punctuality &amp; Alert Protocols</h4>
            <p>Musicians must adhere to designated call times for rehearsals, parades, funeral services, and civic concerts. The automated in-app 10–15m call-time alarms serve as operational notifications.</p>
          </div>

          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 4: Band Property &amp; Instrument Accountability</h4>
            <p>Members issued municipal band instruments, uniforms, lyres, or sheet music folios are strictly responsible for their maintenance, safekeeping, and prompt return upon request.</p>
          </div>

          <div>
            <h4 class="font-semibold text-slate-900 dark:text-white text-xs">Article 5: Data Privacy &amp; Security</h4>
            <p>Member contact numbers and personal birth dates are protected under Row Level Security (RLS) policies and will never be shared publicly.</p>
          </div>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800 flex justify-end">
          <button 
            @click="showTermsModal = false; termsAccepted = true" 
            type="button" 
            class="py-2.5 px-5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:text-slate-900 text-white font-semibold text-xs rounded-full shadow-xs min-h-[40px] cursor-pointer"
          >
            I Accept Terms
          </button>
        </div>

      </div>
    </div>

    <!-- FORGOT PASSWORD MODAL -->
    <div v-if="showForgotPasswordModal" class="fixed inset-0 bg-black/60 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#202124] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-xl text-left">
        
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <h3 class="font-bold text-sm text-slate-900 dark:text-white">Reset Password</h3>
          <button @click="showForgotPasswordModal = false" class="text-slate-400 hover:text-slate-600 dark:hover:text-white min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer rounded-full hover:bg-slate-100 dark:hover:bg-neutral-800">
            <X class="w-4 h-4" />
          </button>
        </div>

        <div v-if="resetSent" class="p-3 bg-emerald-50 dark:bg-emerald-950/30 border border-emerald-200/80 dark:border-emerald-800/50 rounded-xl text-emerald-800 dark:text-emerald-300 text-xs font-medium space-y-1">
          <p>✓ Reset instructions sent! Please check your email inbox to create a new password.</p>
        </div>

        <div v-else class="space-y-3">
          <p class="text-xs text-slate-600 dark:text-neutral-400">Enter your registered email address to receive password reset instructions.</p>
          <input 
            v-model="resetEmail" 
            type="email" 
            placeholder="you@example.com" 
            class="w-full p-2.5 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-neutral-800 rounded-xl text-xs text-slate-900 dark:text-white min-h-[42px] focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600"
          >
          <button 
            @click="handleResetPassword" 
            :disabled="resetLoading" 
            type="button" 
            class="w-full py-2.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:text-slate-900 text-white font-semibold text-xs rounded-full shadow-xs min-h-[42px] cursor-pointer"
          >
            {{ resetLoading ? 'Sending...' : 'Send Reset Link' }}
          </button>
        </div>

      </div>
    </div>

  </div>
</template>
