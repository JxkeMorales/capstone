<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { Music, Mail, Lock, ArrowRight, User, Calendar, Phone, Activity, Sun, Moon, CheckCircle2, AlertCircle, X, ShieldCheck, FileText, Smartphone, Award, Cpu, Eye, EyeOff } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const router = useRouter()
const store = useMainStore()

const activeTab = ref('signin') // 'signin' or 'signup'
const isDark = ref(true)

// Password Visibility Toggles
const showPassword = ref(false)

const toggleTheme = () => {
  isDark.value = !isDark.value
  if (isDark.value) {
    document.documentElement.classList.add('dark')
  } else {
    document.documentElement.classList.remove('dark')
  }
}

onMounted(() => {
  isDark.value = document.documentElement.classList.contains('dark')
})

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
  let val = e.target.value.replace(/\D/g, '') // remove non-digits
  if (val.length > 11) val = val.slice(0, 11)
  contactNumber.value = val
}

const isPhoneValid = computed(() => {
  if (!contactNumber.value) return true
  return /^09\d{9}$/.test(contactNumber.value)
})

// Complete 16-Instrument Municipal Band Section List
const instrumentOptions = [
  { value: '', label: 'Select Primary Instrument...' },
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
  { value: 'Cymbals', label: 'Cymbals' }
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
  { value: 'Cymbals', label: 'Cymbals' }
]

const handleSubmit = async () => {
  errorMessage.value = ''
  isLoading.value = true

  try {
    if (activeTab === 'signin') {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: email.value.trim(),
        password: password.value
      })

      if (error) throw error

      if (data?.user) {
        store.user = data.user
        await store.fetchProfile()
      }
      
      await router.push('/dashboard')

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
        ? `${primaryInstrument.value} / ${secondaryInstrument.value}`
        : primaryInstrument.value

      const { data, error } = await supabase.auth.signUp({
        email: email.value.trim(),
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

      signupSuccess.value = true
    }
  } catch (err) {
    console.error('Auth Error:', err)
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
    const { error } = await supabase.auth.resetPasswordForEmail(resetEmail.value.trim(), {
      redirectTo: `${window.location.origin}/dashboard/profile`
    })
    if (error) throw error
    resetSent.value = true
  } catch (err) {
    console.error('Reset password error:', err)
    alert(err?.message || 'Failed to send password reset email.')
  } finally {
    resetLoading.value = false
  }
}
</script>

<template>
  <div class="min-h-screen w-full flex flex-col items-center justify-center p-4 sm:p-6 lg:p-12 relative bg-[#f8fafc] dark:bg-[#090a0f] text-slate-900 dark:text-neutral-100 transition-colors duration-300">
    
    <!-- Theme Toggle (Sun / Moon) -->
    <button 
      @click="toggleTheme" 
      type="button"
      class="absolute top-4 right-4 p-3 rounded-2xl bg-white dark:bg-[#121522] text-slate-700 dark:text-blue-400 hover:bg-slate-100 dark:hover:bg-[#181d2f] transition-colors shadow-xs z-10 border border-slate-200 dark:border-slate-800/80 min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"
      :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
    >
      <Sun v-if="isDark" class="w-5 h-5 text-amber-400" />
      <Moon v-else class="w-5 h-5 text-blue-600" />
    </button>

    <!-- Main Container -->
    <div class="w-full max-w-md md:max-w-4xl lg:max-w-5xl my-auto py-8">
      
      <div class="grid grid-cols-1 md:grid-cols-2 gap-8 lg:gap-12 items-center">
        
        <!-- Left Hero Section (Desktop View) -->
        <div class="space-y-6 text-left hidden md:block">
          <div class="inline-flex items-center space-x-2 px-3.5 py-1.5 rounded-full bg-blue-500/10 border border-blue-500/30 text-blue-600 dark:text-blue-400 text-xs font-black uppercase tracking-wider">
            <Music class="w-4 h-4" />
            <span>SmartBand Municipal PWA</span>
          </div>

          <h1 class="text-4xl lg:text-5xl font-black text-slate-900 dark:text-white leading-tight tracking-tight">
            Automated Band Operations & Gig Scheduling
          </h1>

          <p class="text-slate-600 dark:text-slate-300 text-base leading-relaxed font-medium">
            Streamlining rehearsal call-times, civic parades, funeral processions, and attendance reliability scoring for municipal musicians and band leaders.
          </p>

          <div class="space-y-3.5 pt-2">
            <div class="flex items-center space-x-3 text-sm font-bold text-slate-800 dark:text-neutral-200">
              <div class="w-9 h-9 rounded-2xl bg-blue-600 text-white flex items-center justify-center font-black shadow-xs flex-shrink-0">
                <Cpu class="w-4 h-4" />
              </div>
              <span>Automated Call-Time Siren & Section Dispatch</span>
            </div>

            <div class="flex items-center space-x-3 text-sm font-bold text-slate-800 dark:text-neutral-200">
              <div class="w-9 h-9 rounded-2xl bg-blue-600 text-white flex items-center justify-center font-black shadow-xs flex-shrink-0">
                <Award class="w-4 h-4" />
              </div>
              <span>Attendance Reliability Score (%) & Roll Call</span>
            </div>

            <div class="flex items-center space-x-3 text-sm font-bold text-slate-800 dark:text-neutral-200">
              <div class="w-9 h-9 rounded-2xl bg-blue-600 text-white flex items-center justify-center font-black shadow-xs flex-shrink-0">
                <Smartphone class="w-4 h-4" />
              </div>
              <span>Offline-First PWA Cache & Instant Launch</span>
            </div>
          </div>
        </div>

        <!-- Right Authentication Card -->
        <div class="w-full">
          
          <div class="bg-white dark:bg-[#121522] border border-slate-200/90 dark:border-slate-800/80 rounded-3xl p-6 sm:p-8 shadow-xl relative overflow-hidden backdrop-blur-md">
            
            <!-- Mobile Brand Header -->
            <div class="text-center md:hidden mb-6 space-y-2">
              <div class="inline-flex p-3 bg-blue-600 rounded-2xl shadow-sm text-white mx-auto">
                <Music class="w-8 h-8" stroke-width="2.5" />
              </div>
              <h2 class="text-2xl font-black text-slate-900 dark:text-white tracking-tight">SmartBand</h2>
              <p class="text-xs font-bold text-slate-500 dark:text-slate-400">Municipal Band Operations System</p>
            </div>

            <!-- Sign In / Sign Up Segmented Tab Bar -->
            <div class="flex p-1 bg-slate-100 dark:bg-[#181d2f] rounded-2xl mb-6 border border-slate-200/60 dark:border-slate-700/60" role="tablist">
              <button 
                @click="activeTab = 'signin'; errorMessage = ''; signupSuccess = false"
                type="button" 
                role="tab"
                :aria-selected="activeTab === 'signin'"
                class="flex-1 py-3 text-xs sm:text-sm font-extrabold rounded-xl transition-all cursor-pointer min-h-[44px]"
                :class="activeTab === 'signin' 
                  ? 'bg-blue-600 text-white shadow-xs font-black' 
                  : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white'"
              >
                Sign In
              </button>
              <button 
                @click="activeTab = 'signup'; errorMessage = ''; signupSuccess = false"
                type="button" 
                role="tab"
                :aria-selected="activeTab === 'signup'"
                class="flex-1 py-3 text-xs sm:text-sm font-extrabold rounded-xl transition-all cursor-pointer min-h-[44px]"
                :class="activeTab === 'signup' 
                  ? 'bg-blue-600 text-white shadow-xs font-black' 
                  : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white'"
              >
                New Musician Register
              </button>
            </div>

            <!-- Success Alert after Sign Up -->
            <div v-if="signupSuccess" class="mb-5 p-4 bg-emerald-50 dark:bg-emerald-950/40 border border-emerald-200 dark:border-emerald-800/60 rounded-2xl text-left space-y-2">
              <div class="flex items-center space-x-2 text-emerald-700 dark:text-emerald-300 font-black text-sm">
                <CheckCircle2 class="w-5 h-5 flex-shrink-0 text-emerald-500" />
                <span>Registration Submitted!</span>
              </div>
              <p class="text-xs text-slate-600 dark:text-slate-300 leading-relaxed font-medium">
                Your account is queued for physical verification by the IT Admin against the municipal band master list. You may now sign in.
              </p>
            </div>

            <!-- Error Banner -->
            <div v-if="errorMessage" class="mb-5 p-3.5 bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-800/60 rounded-2xl flex items-start space-x-2 text-rose-700 dark:text-rose-300 text-xs font-bold text-left" role="alert">
              <AlertCircle class="w-4 h-4 text-rose-500 flex-shrink-0 mt-0.5" />
              <span>{{ errorMessage }}</span>
            </div>

            <!-- Form Area -->
            <form @submit.prevent="handleSubmit" class="space-y-4" aria-label="Authentication Form">
              
              <!-- Email Address -->
              <div class="space-y-1.5 text-left">
                <label for="email-input" class="block text-xs font-black text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                  Email Address
                </label>
                <div class="relative">
                  <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                    <Mail class="w-4 h-4 text-slate-400 dark:text-slate-500" />
                  </div>
                  <input 
                    id="email-input"
                    v-model="email"
                    type="email" 
                    placeholder="you@example.com"
                    autocomplete="email"
                    class="w-full pl-10 pr-4 py-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 text-xs font-semibold min-h-[44px]"
                    required
                  >
                </div>
              </div>

              <!-- Password -->
              <div class="space-y-1.5 text-left">
                <div class="flex items-center justify-between">
                  <label for="password-input" class="block text-xs font-black text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                    Password
                  </label>
                  <button 
                    v-if="activeTab === 'signin'" 
                    @click="showForgotPasswordModal = true; resetSent = false; resetEmail = email"
                    type="button" 
                    class="text-xs font-bold text-blue-600 dark:text-blue-400 hover:underline cursor-pointer"
                  >
                    Forgot Password?
                  </button>
                </div>
                <div class="relative">
                  <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                    <Lock class="w-4 h-4 text-slate-400 dark:text-slate-500" />
                  </div>
                  <input 
                    id="password-input"
                    v-model="password"
                    :type="showPassword ? 'text' : 'password'"
                    placeholder="••••••••"
                    autocomplete="current-password"
                    class="w-full pl-10 pr-10 py-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 text-xs font-semibold min-h-[44px]"
                    required
                  >
                  <button 
                    type="button" 
                    @click="showPassword = !showPassword"
                    class="absolute inset-y-0 right-0 pr-3 flex items-center text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 cursor-pointer"
                  >
                    <Eye v-if="!showPassword" class="w-4 h-4" />
                    <EyeOff v-else class="w-4 h-4" />
                  </button>
                </div>
              </div>

              <!-- SIGN UP SPECIFIC FIELDS -->
              <template v-if="activeTab === 'signup'">
                
                <!-- Full Name -->
                <div class="space-y-1.5 text-left">
                  <label for="fullname-input" class="block text-xs font-black text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                    Full Name (As listed on Band Master List)
                  </label>
                  <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                      <User class="w-4 h-4 text-slate-400 dark:text-slate-500" />
                    </div>
                    <input 
                      id="fullname-input"
                      v-model="fullName"
                      type="text" 
                      placeholder="Juan Dela Cruz"
                      autocomplete="name"
                      class="w-full pl-10 pr-4 py-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 text-xs font-semibold min-h-[44px]"
                      required
                    >
                  </div>
                </div>

                <!-- Birth Date & Sex (2 columns) -->
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 text-left">
                  <div class="space-y-1.5">
                    <label for="birthdate-input" class="block text-xs font-black text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                      Birth Date
                    </label>
                    <div class="relative">
                      <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                        <Calendar class="w-4 h-4 text-slate-400 dark:text-slate-500" />
                      </div>
                      <input 
                        id="birthdate-input"
                        v-model="birthDate"
                        type="date" 
                        class="w-full pl-10 pr-3 py-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-slate-900 dark:text-white text-xs font-semibold min-h-[44px]"
                        required
                      >
                    </div>
                  </div>

                  <div class="space-y-1.5">
                    <span class="block text-xs font-black text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                      Sex
                    </span>
                    <div class="flex gap-2">
                      <label class="flex-1 cursor-pointer">
                        <input type="radio" v-model="sex" value="Male" class="peer sr-only" required>
                        <div class="text-center py-2.5 rounded-xl border border-slate-200 dark:border-slate-700/80 bg-slate-50 dark:bg-[#181d2f] peer-checked:border-blue-600 peer-checked:bg-blue-500/10 peer-checked:text-blue-600 dark:peer-checked:text-blue-400 font-bold text-xs transition-all min-h-[44px] flex items-center justify-center">
                          Male
                        </div>
                      </label>
                      <label class="flex-1 cursor-pointer">
                        <input type="radio" v-model="sex" value="Female" class="peer sr-only" required>
                        <div class="text-center py-2.5 rounded-xl border border-slate-200 dark:border-slate-700/80 bg-slate-50 dark:bg-[#181d2f] peer-checked:border-blue-600 peer-checked:bg-blue-500/10 peer-checked:text-blue-600 dark:peer-checked:text-blue-400 font-bold text-xs transition-all min-h-[44px] flex items-center justify-center">
                          Female
                        </div>
                      </label>
                    </div>
                  </div>
                </div>

                <!-- Strict Philippine Mobile Number (09XXXXXXXXX) -->
                <div class="space-y-1.5 text-left">
                  <div class="flex items-center justify-between">
                    <label for="phone-input" class="block text-xs font-black text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                      Philippine Mobile Number (11 digits)
                    </label>
                    <span class="text-[10px] font-black" :class="contactNumber.length === 11 && contactNumber.startsWith('09') ? 'text-emerald-500' : 'text-slate-400'">
                      {{ contactNumber.length }}/11 digits
                    </span>
                  </div>
                  <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                      <Phone class="w-4 h-4 text-slate-400 dark:text-slate-500" />
                    </div>
                    <input 
                      id="phone-input"
                      :value="contactNumber"
                      @input="handlePhoneInput"
                      type="tel" 
                      placeholder="09123456789"
                      maxlength="11"
                      autocomplete="tel"
                      class="w-full pl-10 pr-4 py-3 bg-slate-50 dark:bg-[#181d2f] border rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 text-xs font-semibold min-h-[44px]"
                      :class="!isPhoneValid ? 'border-rose-500 focus:ring-rose-500' : 'border-slate-200 dark:border-slate-700/80'"
                      required
                    >
                  </div>
                  <p v-if="!isPhoneValid" class="text-[10px] font-bold text-rose-500 mt-1">
                    Must start with 09 and contain exactly 11 digits (e.g. 09123456789).
                  </p>
                </div>

                <!-- Primary Instrument Played -->
                <div class="space-y-1.5 text-left">
                  <label for="primary-instrument-select" class="block text-xs font-black text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                    Primary Instrument (Required)
                  </label>
                  <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                      <Activity class="w-4 h-4 text-slate-400 dark:text-slate-500" />
                    </div>
                    <select 
                      id="primary-instrument-select"
                      v-model="primaryInstrument"
                      class="w-full pl-10 pr-4 py-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-slate-900 dark:text-white text-xs font-semibold focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[44px]"
                      required
                    >
                      <option v-for="inst in instrumentOptions" :key="inst.value" :value="inst.value">
                        {{ inst.label }}
                      </option>
                    </select>
                  </div>
                </div>

                <!-- Secondary Instrument -->
                <div class="space-y-1.5 text-left">
                  <label for="secondary-instrument-select" class="block text-xs font-black text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                    Secondary Instrument (Optional / N/A)
                  </label>
                  <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none">
                      <Activity class="w-4 h-4 text-slate-400 dark:text-slate-500" />
                    </div>
                    <select 
                      id="secondary-instrument-select"
                      v-model="secondaryInstrument"
                      class="w-full pl-10 pr-4 py-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-slate-900 dark:text-white text-xs font-semibold focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[44px]"
                    >
                      <option v-for="inst in secondaryInstrumentOptions" :key="inst.value" :value="inst.value">
                        {{ inst.label }}
                      </option>
                    </select>
                  </div>
                </div>

                <!-- Terms and Conditions Agreement Checkbox -->
                <div class="pt-1 text-left">
                  <label class="flex items-start space-x-2.5 cursor-pointer">
                    <input 
                      type="checkbox" 
                      v-model="termsAccepted" 
                      class="mt-1 w-4 h-4 text-blue-600 bg-slate-100 dark:bg-[#181d2f] border-slate-300 dark:border-slate-700 rounded focus:ring-blue-500 cursor-pointer"
                      required
                    >
                    <span class="text-xs text-slate-600 dark:text-slate-300 leading-relaxed font-medium">
                      I agree to the 
                      <button 
                        @click="showTermsModal = true" 
                        type="button" 
                        class="font-black text-blue-600 dark:text-blue-400 hover:underline cursor-pointer"
                      >
                        Municipal Band Terms & Conditions
                      </button> 
                      and physical master list verification.
                    </span>
                  </label>
                </div>

              </template>

              <!-- Submit Button -->
              <div class="pt-2">
                <button 
                  type="submit" 
                  :disabled="isLoading"
                  class="w-full py-3.5 px-4 bg-blue-600 hover:bg-blue-500 active:scale-98 text-white font-black text-sm rounded-2xl flex items-center justify-center space-x-2 transition-all shadow-md cursor-pointer disabled:opacity-50 min-h-[48px]"
                >
                  <span v-if="isLoading">Processing...</span>
                  <span v-else-if="activeTab === 'signin'" class="flex items-center">
                    Sign In to Band Dashboard <ArrowRight class="w-4 h-4 ml-1.5" />
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
    <div v-if="showTermsModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#121522] border border-slate-200 dark:border-slate-800 rounded-3xl p-6 max-w-lg w-full space-y-4 shadow-2xl text-left max-h-[85vh] flex flex-col">
        
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-slate-800/80 pb-3">
          <div class="flex items-center space-x-2 text-blue-600 dark:text-blue-400">
            <FileText class="w-5 h-5" />
            <h3 class="font-black text-lg text-slate-900 dark:text-white">Municipal Band Terms & Conditions</h3>
          </div>
          <button @click="showTermsModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div class="overflow-y-auto flex-1 text-xs text-slate-600 dark:text-slate-300 space-y-3.5 pr-2 leading-relaxed font-medium">
          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 1: Master List Verification Requirement</h4>
            <p>All sign-up applications are provisional until physically verified by the IT Super Admin against the official municipal band registry. Unverified accounts cannot view private contact rosters or access secretary dispatch controls.</p>
          </div>

          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 2: Attendance & RSVP Reliability Scoring</h4>
            <p>Submitting an RSVP of "I Will Attend" is an operational commitment for gig planning. Unexcused absences or sudden cancellations directly impact your personal Reliability Score (%) and future gig prioritization.</p>
          </div>

          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 3: Call-Time Punctuality & Alert Protocols</h4>
            <p>Musicians must adhere to designated call times for rehearsals, parades, funeral services, and civic concerts. The automated in-app 10–15m call-time alarms serve as operational notifications.</p>
          </div>

          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 4: Band Property & Instrument Accountability</h4>
            <p>Members issued municipal band instruments, uniforms, lyres, or sheet music folios are strictly responsible for their maintenance, safekeeping, and prompt return upon request.</p>
          </div>

          <div>
            <h4 class="font-black text-slate-900 dark:text-white text-sm">Article 5: Data Privacy & Security</h4>
            <p>Member contact numbers and personal birth dates are protected under Row Level Security (RLS) policies and will never be shared publicly.</p>
          </div>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-slate-800/80 flex justify-end">
          <button 
            @click="showTermsModal = false; termsAccepted = true" 
            type="button" 
            class="py-3 px-6 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer"
          >
            I Accept Terms
          </button>
        </div>

      </div>
    </div>

    <!-- FORGOT PASSWORD MODAL -->
    <div v-if="showForgotPasswordModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#121522] border border-slate-200 dark:border-slate-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left">
        
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-slate-800/80 pb-3">
          <h3 class="font-black text-base text-slate-900 dark:text-white">Reset Password</h3>
          <button @click="showForgotPasswordModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div v-if="resetSent" class="p-3 bg-emerald-50 dark:bg-emerald-950/40 border border-emerald-200 dark:border-emerald-800 rounded-xl text-emerald-800 dark:text-emerald-300 text-xs font-bold space-y-1">
          <p>✓ Reset instructions sent! Please check your email inbox to create a new password.</p>
        </div>

        <div v-else class="space-y-3">
          <p class="text-xs text-slate-600 dark:text-slate-400">Enter your registered email address to receive password reset instructions.</p>
          <input 
            v-model="resetEmail" 
            type="email" 
            placeholder="you@example.com" 
            class="w-full p-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
          >
          <button 
            @click="handleResetPassword" 
            :disabled="resetLoading" 
            type="button" 
            class="w-full py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer"
          >
            {{ resetLoading ? 'Sending...' : 'Send Reset Link' }}
          </button>
        </div>

      </div>
    </div>

  </div>
</template>
