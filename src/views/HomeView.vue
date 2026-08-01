<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { Music, Mail, Lock, ArrowRight, User, Calendar, Phone, Activity, Sun, Moon, CheckCircle2, AlertCircle, X, ShieldCheck, FileText, Smartphone, Award, Cpu } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const router = useRouter()
const store = useMainStore()

const activeTab = ref('signin') // 'signin' or 'signup'
const isDark = ref(true)

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
const instrument = ref('')
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

const instrumentOptions = [
  { value: '', label: 'Select an instrument...' },
  { value: 'trumpet', label: 'Trumpet' },
  { value: 'trombone', label: 'Trombone' },
  { value: 'saxophone', label: 'Saxophone' },
  { value: 'drums', label: 'Drums / Percussion' },
  { value: 'flute', label: 'Flute' },
  { value: 'clarinet', label: 'Clarinet' }
]

const handleSubmit = async () => {
  errorMessage.value = ''
  isLoading.value = true

  try {
    if (activeTab.value === 'signin') {
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
        throw new Error('Please accept the Terms & Conditions to register.')
      }

      const { data, error } = await supabase.auth.signUp({
        email: email.value.trim(),
        password: password.value,
        options: {
          data: {
            full_name: fullName.value.trim(),
            birth_date: birthDate.value,
            sex: sex.value,
            contact_number: contactNumber.value.trim(),
            instrument: instrument.value
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
  <div class="min-h-screen w-full flex flex-col items-center justify-center p-4 sm:p-6 lg:p-12 relative bg-slate-50 dark:bg-black transition-colors duration-300">
    
    <!-- Theme Toggle -->
    <button 
      @click="toggleTheme" 
      type="button"
      class="absolute top-4 right-4 p-3 rounded-full bg-slate-200 dark:bg-neutral-900 text-slate-800 dark:text-yellow-400 hover:bg-slate-300 dark:hover:bg-neutral-800 transition-colors shadow-xs z-10 border border-transparent dark:border-neutral-800 min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"
      :aria-label="isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'"
    >
      <Sun v-if="isDark" class="w-5 h-5" />
      <Moon v-else class="w-5 h-5" />
    </button>

    <!-- Main Container (Responsive Grid: Single column on Mobile, 2-Column Hero on Desktop) -->
    <div class="w-full max-w-md md:max-w-4xl lg:max-w-5xl my-auto py-8">
      
      <div class="grid grid-cols-1 md:grid-cols-2 gap-8 lg:gap-12 items-center">
        
        <!-- Left Hero Section (Visible & Expanded on Desktop) -->
        <div class="space-y-6 text-left hidden md:block">
          <div class="inline-flex items-center space-x-2 px-3.5 py-1.5 rounded-full bg-yellow-400/15 border border-yellow-400/30 text-yellow-600 dark:text-yellow-400 text-xs font-black uppercase tracking-wider">
            <Music class="w-4 h-4" />
            <span>SmartBand Municipal PWA</span>
          </div>

          <h1 class="text-4xl lg:text-5xl font-black text-slate-900 dark:text-white leading-tight tracking-tight">
            Automated Band Operations & Gig Scheduling
          </h1>

          <p class="text-slate-600 dark:text-neutral-300 text-base leading-relaxed font-medium">
            Streamlining rehearsal call-times, fiesta parades, funeral processions, and attendance reliability scoring for municipal musicians and band leaders.
          </p>

          <div class="space-y-3 pt-2">
            <div class="flex items-center space-x-3 text-sm font-bold text-slate-800 dark:text-neutral-200">
              <div class="w-8 h-8 rounded-xl bg-yellow-400 text-slate-900 flex items-center justify-center font-black">
                <Cpu class="w-4 h-4" />
              </div>
              <span>Rule-Based Smart Dispatch & Budget Batching</span>
            </div>

            <div class="flex items-center space-x-3 text-sm font-bold text-slate-800 dark:text-neutral-200">
              <div class="w-8 h-8 rounded-xl bg-yellow-400 text-slate-900 flex items-center justify-center font-black">
                <Award class="w-4 h-4" />
              </div>
              <span>Reliability Score (%) & Pa-Importante Analytics</span>
            </div>

            <div class="flex items-center space-x-3 text-sm font-bold text-slate-800 dark:text-neutral-200">
              <div class="w-8 h-8 rounded-xl bg-yellow-400 text-slate-900 flex items-center justify-center font-black">
                <Smartphone class="w-4 h-4" />
              </div>
              <span>PWA Offline Access & Install Prompting</span>
            </div>
          </div>
        </div>

        <!-- Mobile Header / Logo Area (Visible on Mobile) -->
        <div class="md:hidden flex items-center justify-center space-x-3 mb-2">
          <div class="bg-yellow-400 p-3 rounded-2xl shadow-[0_0_25px_rgba(250,204,21,0.35)] flex items-center justify-center">
            <Music class="w-7 h-7 text-black" stroke-width="3" />
          </div>
          <h1 class="text-3xl font-black tracking-tight text-slate-900 dark:text-white">
            SmartBand
          </h1>
        </div>

        <!-- Right Sign In / Sign Up Card Component -->
        <div class="w-full">
          
          <!-- Sign Up Success Message Modal -->
          <div v-if="signupSuccess" class="bg-white dark:bg-[#121212] rounded-3xl p-6 sm:p-8 shadow-xl border border-slate-200/80 dark:border-neutral-800 text-center space-y-4">
            <div class="w-14 h-14 rounded-full bg-green-100 dark:bg-green-950/60 text-green-600 dark:text-green-400 flex items-center justify-center mx-auto">
              <CheckCircle2 class="w-8 h-8" />
            </div>
            <h2 class="text-2xl font-black text-slate-900 dark:text-white">Account Created!</h2>
            <p class="text-sm text-slate-600 dark:text-neutral-300 leading-relaxed">
              Your registration was sent successfully. Your profile is currently **pending Super Admin verification** against the physical master list.
            </p>
            <button 
              @click="signupSuccess = false; activeTab = 'signin'"
              class="w-full bg-yellow-400 hover:bg-yellow-500 text-slate-900 font-black py-3.5 px-6 rounded-xl transition-all shadow-md active:scale-[0.98] text-base min-h-[44px] cursor-pointer"
            >
              Return to Sign In
            </button>
          </div>

          <!-- Card Container -->
          <div v-else class="bg-white dark:bg-[#121212] rounded-3xl p-6 sm:p-8 shadow-xl border border-slate-200/80 dark:border-neutral-800">
            
            <!-- Segmented Control -->
            <div class="flex rounded-2xl bg-slate-100 dark:bg-[#1a1a1a] p-1.5 mb-6 border border-slate-200 dark:border-neutral-800" role="tablist">
              <button 
                @click="activeTab = 'signin'; errorMessage = ''"
                type="button"
                role="tab"
                :aria-selected="activeTab === 'signin'"
                class="flex-1 py-3 px-4 rounded-xl font-bold text-sm transition-all duration-200 min-h-[44px] cursor-pointer"
                :class="activeTab === 'signin' 
                  ? 'bg-white dark:bg-[#262626] text-slate-900 dark:text-white shadow-sm' 
                  : 'text-slate-500 dark:text-neutral-400 hover:text-slate-700 dark:hover:text-neutral-200'"
              >
                SIGN IN
              </button>
              <button 
                @click="activeTab = 'signup'; errorMessage = ''"
                type="button"
                role="tab"
                :aria-selected="activeTab === 'signup'"
                class="flex-1 py-3 px-4 rounded-xl font-bold text-sm transition-all duration-200 min-h-[44px] cursor-pointer"
                :class="activeTab === 'signup' 
                  ? 'bg-white dark:bg-[#262626] text-slate-900 dark:text-white shadow-sm' 
                  : 'text-slate-500 dark:text-neutral-400 hover:text-slate-700 dark:hover:text-neutral-200'"
              >
                SIGN UP
              </button>
            </div>

            <!-- Error Feedback Banner -->
            <div v-if="errorMessage" class="mb-5 p-3.5 bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-800/60 rounded-xl flex items-start space-x-2 text-red-700 dark:text-red-300 text-xs font-bold" role="alert">
              <AlertCircle class="w-4 h-4 text-red-500 flex-shrink-0 mt-0.5" />
              <span>{{ errorMessage }}</span>
            </div>

            <!-- Form Area -->
            <form @submit.prevent="handleSubmit" class="space-y-5" aria-label="Authentication Form">
              
              <!-- Email Address -->
              <div class="space-y-1.5 text-left">
                <label for="email-input" class="block text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
                  Email Address
                </label>
                <div class="relative">
                  <div class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                    <Mail class="w-5 h-5 text-slate-400 dark:text-neutral-500" />
                  </div>
                  <input 
                    id="email-input"
                    v-model="email"
                    type="email" 
                    placeholder="you@example.com"
                    autocomplete="email"
                    class="w-full pl-12 pr-4 py-3.5 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-300 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:border-transparent transition-all text-base font-medium min-h-[44px]"
                    required
                  >
                </div>
              </div>

              <!-- Password -->
              <div class="space-y-1.5 text-left">
                <div class="flex items-center justify-between">
                  <label for="password-input" class="block text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
                    Password
                  </label>
                  <button 
                    v-if="activeTab === 'signin'" 
                    @click="showForgotPasswordModal = true; resetSent = false; resetEmail = email"
                    type="button" 
                    class="text-xs font-bold text-yellow-600 dark:text-yellow-400 hover:underline cursor-pointer"
                  >
                    Forgot Password?
                  </button>
                </div>
                <div class="relative">
                  <div class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                    <Lock class="w-5 h-5 text-slate-400 dark:text-neutral-500" />
                  </div>
                  <input 
                    id="password-input"
                    v-model="password"
                    type="password" 
                    placeholder="••••••••"
                    autocomplete="current-password"
                    class="w-full pl-12 pr-4 py-3.5 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-300 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:border-transparent transition-all text-base font-medium min-h-[44px]"
                    required
                  >
                </div>
              </div>

              <!-- SIGN UP FIELDS -->
              <template v-if="activeTab === 'signup'">
                
                <div class="space-y-1.5 text-left">
                  <label for="fullname-input" class="block text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
                    Full Name
                  </label>
                  <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                      <User class="w-5 h-5 text-slate-400 dark:text-neutral-500" />
                    </div>
                    <input 
                      id="fullname-input"
                      v-model="fullName"
                      type="text" 
                      placeholder="Juan Dela Cruz"
                      autocomplete="name"
                      class="w-full pl-12 pr-4 py-3.5 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-300 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:border-transparent transition-all text-base font-medium min-h-[44px]"
                      required
                    >
                  </div>
                </div>

                <div class="space-y-1.5 text-left">
                  <label for="birthdate-input" class="block text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
                    Birth Date
                  </label>
                  <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                      <Calendar class="w-5 h-5 text-slate-400 dark:text-neutral-500" />
                    </div>
                    <input 
                      id="birthdate-input"
                      v-model="birthDate"
                      type="date" 
                      class="w-full pl-12 pr-4 py-3.5 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-300 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:border-transparent transition-all text-base font-medium min-h-[44px] [color-scheme:light] dark:[color-scheme:dark]"
                      required
                    >
                  </div>
                </div>

                <div class="space-y-1.5 text-left">
                  <span class="block text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider mb-2">
                    Sex
                  </span>
                  <div class="flex gap-3">
                    <label class="flex-1 cursor-pointer">
                      <input type="radio" v-model="sex" value="Male" class="peer sr-only" required>
                      <div class="text-center py-3.5 rounded-xl border border-slate-300 dark:border-neutral-800 bg-slate-50 dark:bg-[#1c1c1e] peer-checked:border-yellow-400 peer-checked:bg-yellow-50 dark:peer-checked:bg-yellow-400/10 peer-checked:text-yellow-600 dark:peer-checked:text-yellow-400 font-bold text-base transition-all min-h-[44px] flex items-center justify-center">
                        Male
                      </div>
                    </label>
                    <label class="flex-1 cursor-pointer">
                      <input type="radio" v-model="sex" value="Female" class="peer sr-only" required>
                      <div class="text-center py-3.5 rounded-xl border border-slate-300 dark:border-neutral-800 bg-slate-50 dark:bg-[#1c1c1e] peer-checked:border-yellow-400 peer-checked:bg-yellow-50 dark:peer-checked:bg-yellow-400/10 peer-checked:text-yellow-600 dark:peer-checked:text-yellow-400 font-bold text-base transition-all min-h-[44px] flex items-center justify-center">
                        Female
                      </div>
                    </label>
                  </div>
                </div>

                <div class="space-y-1.5 text-left">
                  <label for="phone-input" class="block text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
                    Contact Number
                  </label>
                  <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                      <Phone class="w-5 h-5 text-slate-400 dark:text-neutral-500" />
                    </div>
                    <input 
                      id="phone-input"
                      v-model="contactNumber"
                      type="tel" 
                      placeholder="0912 345 6789"
                      autocomplete="tel"
                      class="w-full pl-12 pr-4 py-3.5 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-300 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:border-transparent transition-all text-base font-medium min-h-[44px]"
                      required
                    >
                  </div>
                </div>

                <div class="space-y-1.5 text-left">
                  <label for="instrument-select" class="block text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
                    Instrument Played
                  </label>
                  <div class="relative">
                    <div class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                      <Activity class="w-5 h-5 text-slate-400 dark:text-neutral-500" />
                    </div>
                    <select 
                      id="instrument-select"
                      v-model="instrument"
                      class="w-full pl-12 pr-10 py-3.5 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-300 dark:border-neutral-800 rounded-xl text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-yellow-400 focus:border-transparent transition-all text-base font-medium appearance-none cursor-pointer min-h-[44px]"
                      required
                    >
                      <option v-for="opt in instrumentOptions" :key="opt.value" :value="opt.value" :disabled="opt.value === ''">
                        {{ opt.label }}
                      </option>
                    </select>
                    <div class="absolute inset-y-0 right-0 pr-4 flex items-center pointer-events-none">
                      <svg class="w-5 h-5 text-slate-400 dark:text-neutral-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path></svg>
                    </div>
                  </div>
                </div>

                <div class="pt-2 pb-1 text-left">
                  <label class="flex items-start space-x-3 cursor-pointer group">
                    <div class="relative flex items-center justify-center mt-0.5">
                      <input 
                        type="checkbox" 
                        v-model="termsAccepted"
                        class="peer sr-only"
                        required
                      >
                      <div class="w-5 h-5 border-2 border-slate-300 dark:border-neutral-700 rounded bg-slate-50 dark:bg-[#1c1c1e] peer-checked:bg-yellow-400 peer-checked:border-yellow-400 transition-all flex items-center justify-center">
                        <svg class="w-3.5 h-3.5 text-slate-900 opacity-0 peer-checked:opacity-100 transition-opacity" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"></path></svg>
                      </div>
                    </div>
                    <span class="text-slate-600 dark:text-neutral-400 text-xs sm:text-sm leading-snug">
                      I accept the 
                      <button 
                        @click.prevent="showTermsModal = true" 
                        type="button" 
                        class="text-yellow-600 dark:text-yellow-400 font-bold hover:underline cursor-pointer inline"
                      >
                        Terms & Conditions
                      </button> 
                      and privacy policy.
                    </span>
                  </label>
                </div>

              </template>

              <!-- Submit Button -->
              <div class="pt-3">
                <button 
                  type="submit"
                  :disabled="isLoading"
                  class="w-full flex items-center justify-center space-x-2 bg-yellow-400 hover:bg-yellow-500 text-slate-900 font-black py-4 px-6 rounded-xl transition-all shadow-md active:scale-[0.98] text-base disabled:opacity-50 cursor-pointer min-h-[44px]"
                >
                  <span v-if="isLoading">Processing...</span>
                  <span v-else>{{ activeTab === 'signin' ? 'ACCESS DASHBOARD' : 'CREATE ACCOUNT' }}</span>
                  <ArrowRight v-if="!isLoading" class="w-5 h-5" stroke-width="3" />
                </button>
              </div>
            </form>

          </div>
        </div>

      </div>

    </div>

    <!-- FORGOT PASSWORD MODAL -->
    <div v-if="showForgotPasswordModal" class="fixed inset-0 bg-black/75 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#121212] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-2 text-yellow-500">
            <Lock class="w-5 h-5" />
            <h3 class="font-black text-lg text-slate-900 dark:text-white">Reset Password</h3>
          </div>
          <button @click="showForgotPasswordModal = false" class="text-slate-400 hover:text-white cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div v-if="resetSent" class="p-4 bg-green-50 dark:bg-green-950/40 border border-green-200 dark:border-green-800/60 rounded-2xl text-center space-y-2">
          <CheckCircle2 class="w-8 h-8 text-green-500 mx-auto" />
          <p class="font-black text-sm text-slate-900 dark:text-white">Reset Link Sent!</p>
          <p class="text-xs text-slate-500 dark:text-neutral-400">Check <b>{{ resetEmail }}</b> for instructions to reset your password.</p>
        </div>

        <div v-else class="space-y-4">
          <p class="text-xs text-slate-500 dark:text-neutral-400 leading-relaxed">
            Enter your registered email address below. We will send you an official link to reset your account password.
          </p>
          <div>
            <label for="reset-email-input" class="block text-xs font-bold text-slate-400 dark:text-neutral-400 uppercase mb-1">Email Address</label>
            <input 
              id="reset-email-input"
              v-model="resetEmail" 
              type="email" 
              placeholder="you@example.com"
              class="w-full p-3 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
            >
          </div>
          <div class="flex space-x-2 pt-2">
            <button @click="showForgotPasswordModal = false" type="button" class="flex-1 py-3 bg-slate-100 dark:bg-neutral-800 font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer">Cancel</button>
            <button @click="handleResetPassword" :disabled="resetLoading" type="button" class="flex-1 py-3 bg-yellow-400 font-black text-xs text-slate-900 rounded-xl shadow-md min-h-[44px] cursor-pointer">
              {{ resetLoading ? 'Sending...' : 'Send Link' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- TERMS AND CONDITIONS MODAL SHEET -->
    <div v-if="showTermsModal" class="fixed inset-0 bg-black/75 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#121212] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left max-h-[80vh] flex flex-col">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2 text-yellow-500">
            <FileText class="w-5 h-5" />
            <h3 class="font-black text-lg text-slate-900 dark:text-white">Terms & Conditions</h3>
          </div>
          <button @click="showTermsModal = false" class="text-slate-400 hover:text-white cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div class="overflow-y-auto flex-1 text-xs text-slate-600 dark:text-neutral-300 space-y-3 pr-1 leading-relaxed">
          <h4 class="font-black text-slate-900 dark:text-white">1. Master List Verification Requirement</h4>
          <p>All sign-ups are subject to physical verification against the municipal band master list by the IT Super Admin. Unverified accounts will remain pending.</p>

          <h4 class="font-black text-slate-900 dark:text-white">2. Attendance & Reliability Policy</h4>
          <p>RSVPing "Will Attend" creates an operational commitment for gig scheduling. Failing to attend without prior excuse affects your personal Reliability Score (%) and Junior/Senior rank status.</p>

          <h4 class="font-black text-slate-900 dark:text-white">3. Data Privacy & Roster Rights</h4>
          <p>Personal phone numbers and private email addresses are protected under Row Level Security (RLS) and will never be exposed to public directory views.</p>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800">
          <button @click="termsAccepted = true; showTermsModal = false" type="button" class="w-full py-3 bg-yellow-400 font-black text-xs text-slate-900 rounded-xl shadow-md min-h-[44px] cursor-pointer">
            I Understand & Agree
          </button>
        </div>
      </div>
    </div>

  </div>
</template>
