<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { User, Calendar, Clock, CheckCircle2, Phone, LogOut, Activity, Edit3, X, Lock, Eye, EyeOff, ShieldCheck, KeyRound } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const router = useRouter()
const store = useMainStore()

const availability = ref({})
const isSaving = ref(false)
const saveSuccess = ref(false)

// Edit Profile Modal State
const showEditProfileModal = ref(false)
const editFullName = ref('')
const editPrimaryInstrument = ref('')
const editSecondaryInstrument = ref('None / N/A')
const editContactNumber = ref('')
const isUpdatingProfile = ref(false)

// Password Change State inside Profile
const showPasswordSection = ref(false)
const newPassword = ref('')
const confirmPassword = ref('')
const showNewPass = ref(false)
const showConfirmPass = ref(false)
const passwordChangeError = ref('')
const passwordChangeSuccess = ref(false)

// Philippine Phone Formatting (09XXXXXXXXX)
const handlePhoneEditInput = (e) => {
  let val = e.target.value.replace(/\D/g, '')
  if (val.length > 11) val = val.slice(0, 11)
  editContactNumber.value = val
}

const isEditPhoneValid = computed(() => {
  if (!editContactNumber.value) return true
  return /^09\d{9}$/.test(editContactNumber.value)
})

// Complete 16 Instrument Options
const instrumentList = [
  'Clarinet', 'Bass Clarinet', 'Flute', 'Piccolo', 'French Horn', 
  'Tenor Sax', 'Sax (Alto Sax)', 'Baritone Sax', 'Trumpet', 'Trombone', 
  'Bass Trombone', 'Baritone / Euphonium', 'Bass / Tuba', 'Bass Drum', 
  'Snare Drum / Drums', 'Cymbals'
]

// Dynamic Week Days Generator
const getDynamicWeekDays = () => {
  const now = new Date()
  const currentDay = now.getDay()
  const distanceToMon = currentDay === 0 ? -6 : 1 - currentDay
  const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + distanceToMon)

  const days = []
  for (let i = 0; i < 7; i++) {
    const d = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i)
    const dayName = d.toLocaleDateString('en-US', { weekday: 'short' })
    const monthDay = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
    days.push({
      key: dayName,
      name: dayName,
      dateLabel: monthDay
    })
  }
  return days
}

const weekDays = ref(getDynamicWeekDays())

const timeSlots = [
  'Morning (8am-12pm)',
  'Afternoon (1pm-5pm)',
  'Evening (6pm-9pm)'
]

const toggleSlot = (dayKey, slot) => {
  const key = `${dayKey}::${slot}`
  availability.value = {
    ...availability.value,
    [key]: !availability.value[key]
  }
}

const isSlotFree = (dayKey, slot) => {
  return !!availability.value[`${dayKey}::${slot}`]
}

const fetchAvailability = async () => {
  if (!store.user) return
  const userId = store.user.id
  
  // 1. Read from LocalStorage cache for instant offline recovery
  const localData = localStorage.getItem(`smartband_availability_${userId}`)
  if (localData) {
    try {
      availability.value = JSON.parse(localData)
    } catch (e) {
      console.error(e)
    }
  }

  // 2. Fetch from Supabase DB
  try {
    const { data } = await supabase
      .from('member_availability')
      .select('*')
      .eq('user_id', userId)
      .eq('is_free', true)

    if (data && data.length > 0) {
      const newMap = {}
      data.forEach(item => {
        newMap[`${item.day_of_week}::${item.time_slot}`] = true
      })
      availability.value = newMap
      localStorage.setItem(`smartband_availability_${userId}`, JSON.stringify(newMap))
    }
  } catch (err) {
    console.error('Error fetching availability:', err)
  }
}

const saveAvailability = async () => {
  if (!store.user) return
  const userId = store.user.id
  isSaving.value = true
  saveSuccess.value = false

  localStorage.setItem(`smartband_availability_${userId}`, JSON.stringify(availability.value))

  try {
    await supabase.from('member_availability').delete().eq('user_id', userId)

    const insertData = []
    Object.entries(availability.value).forEach(([key, isFree]) => {
      if (isFree) {
        const parts = key.split('::')
        if (parts.length === 2) {
          const [dayKey, slot] = parts
          insertData.push({
            user_id: userId,
            day_of_week: dayKey,
            time_slot: slot,
            is_free: true
          })
        }
      }
    })

    if (insertData.length > 0) {
      const { error } = await supabase.from('member_availability').insert(insertData)
      if (error) throw error
    }

    saveSuccess.value = true
    setTimeout(() => { saveSuccess.value = false }, 3000)
  } catch (err) {
    console.error('Error saving availability:', err)
    alert('Failed to save availability to database.')
  } finally {
    isSaving.value = false
  }
}

// OPEN EDIT PROFILE MODAL
const openEditProfile = () => {
  editFullName.value = store.profile?.full_name || ''
  
  // Parse existing combined instrument if present
  const currentInst = store.profile?.instrument || ''
  if (currentInst.includes('/')) {
    const parts = currentInst.split('/').map(s => s.trim())
    editPrimaryInstrument.value = parts[0] || ''
    editSecondaryInstrument.value = parts[1] || 'None / N/A'
  } else {
    editPrimaryInstrument.value = currentInst
    editSecondaryInstrument.value = 'None / N/A'
  }

  editContactNumber.value = store.profile?.contact_number || ''
  newPassword.value = ''
  confirmPassword.value = ''
  passwordChangeError.value = ''
  passwordChangeSuccess.value = false
  showPasswordSection.value = false
  showEditProfileModal.value = true
}

// SAVE PROFILE EDITS
const handleUpdateProfile = async () => {
  if (!store.user) return
  isUpdatingProfile.value = true
  passwordChangeError.value = ''

  try {
    if (editContactNumber.value && !/^09\d{9}$/.test(editContactNumber.value.trim())) {
      throw new Error('Contact number must be an 11-digit Philippine number starting with 09.')
    }

    const combinedInstrument = editSecondaryInstrument.value && editSecondaryInstrument.value !== 'None / N/A'
      ? `${editPrimaryInstrument.value} / ${editSecondaryInstrument.value}`
      : editPrimaryInstrument.value

    const { error: profileErr } = await supabase
      .from('profiles')
      .update({
        full_name: editFullName.value.trim(),
        instrument: combinedInstrument,
        contact_number: editContactNumber.value.trim()
      })
      .eq('id', store.user.id)

    if (profileErr) throw profileErr

    // Handle Password Update if entered
    if (newPassword.value.trim() !== '') {
      if (newPassword.value.length < 8) {
        throw new Error('New password must be at least 8 characters long.')
      }
      if (newPassword.value !== confirmPassword.value) {
        throw new Error('New passwords do not match. Please re-type.')
      }

      const { error: passErr } = await supabase.auth.updateUser({ password: newPassword.value.trim() })
      if (passErr) throw passErr
      passwordChangeSuccess.value = true
    }

    await store.fetchProfile()
    showEditProfileModal.value = false
    alert('Profile updated successfully!')
  } catch (err) {
    console.error('Update profile error:', err)
    passwordChangeError.value = err?.message || 'Failed to update profile.'
    alert(err?.message || 'Failed to update profile.')
  } finally {
    isUpdatingProfile.value = false
  }
}

const handleSignOut = async () => {
  await store.signOut()
  router.push('/')
}

onMounted(() => {
  fetchAvailability()
})
</script>

<template>
  <div class="p-4 sm:p-5 space-y-6">
    
    <header class="pt-1 flex items-center justify-between">
      <h1 class="text-2xl font-black text-slate-900 dark:text-white">My Profile</h1>
      <button 
        @click="handleSignOut"
        type="button"
        class="text-xs font-bold text-rose-600 dark:text-rose-400 bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-900/40 px-3.5 py-2 rounded-xl flex items-center hover:bg-rose-100 transition-colors min-h-[44px] cursor-pointer"
        aria-label="Sign Out of Account"
      >
        <LogOut class="w-3.5 h-3.5 mr-1" /> Sign Out
      </button>
    </header>

    <!-- Profile Info Card with Edit Trigger -->
    <section class="bg-white dark:bg-[#121522] rounded-3xl p-5 shadow-xs border border-slate-200/80 dark:border-slate-800/80">
      <div class="flex items-center justify-between mb-5">
        <div class="flex items-center space-x-4 min-w-0 pr-2">
          <div class="w-14 h-14 rounded-2xl bg-blue-600 text-white flex items-center justify-center text-xl font-black shadow-md flex-shrink-0">
            {{ store.profile?.full_name ? store.profile.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB' }}
          </div>
          <div class="min-w-0">
            <h2 class="text-lg font-black text-slate-900 dark:text-white truncate">
              {{ store.profile?.full_name || 'Member' }}
            </h2>
            <p class="text-xs font-bold text-slate-500 dark:text-slate-400 mt-0.5 capitalize">
              {{ store.profile?.instrument || 'Musician' }} • {{ store.profile?.rank || 'Junior' }} Rank
            </p>
          </div>
        </div>

        <button 
          @click="openEditProfile"
          type="button"
          class="p-2.5 bg-blue-500/10 text-blue-600 dark:text-blue-400 hover:bg-blue-600 hover:text-white rounded-2xl transition-all min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"
          aria-label="Edit Profile Details"
        >
          <Edit3 class="w-5 h-5" />
        </button>
      </div>

      <div class="space-y-2.5">
        <div class="flex items-center text-xs font-semibold text-slate-700 dark:text-slate-300">
          <Phone class="w-4 h-4 mr-3 text-slate-400 dark:text-slate-500 flex-shrink-0" />
          <span>{{ store.profile?.contact_number || store.profile?.email || 'No contact specified' }}</span>
        </div>
        <div class="flex items-center text-xs font-semibold text-slate-700 dark:text-slate-300">
          <Activity class="w-4 h-4 mr-3 text-slate-400 dark:text-slate-500 flex-shrink-0" />
          <span>Verification Status: {{ store.profile?.is_verified ? 'Verified Master List' : 'Pending Verification' }}</span>
        </div>
      </div>
    </section>

    <!-- Dynamic Weekly Availability Grid with Exact Dates -->
    <section class="space-y-3">
      <div class="flex justify-between items-end px-1">
        <div>
          <h2 class="text-xs font-extrabold text-slate-500 dark:text-slate-400 uppercase tracking-wider flex items-center">
            <Calendar class="w-3.5 h-3.5 mr-1 text-blue-500" /> Weekly Availability Grid
          </h2>
          <p class="text-[11px] text-slate-400 dark:text-slate-500 mt-0.5">Tap slots when FREE. Saved directly to database.</p>
        </div>
        <button 
          @click="saveAvailability"
          :disabled="isSaving"
          class="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white font-black text-xs rounded-xl shadow-xs active:scale-95 transition-all flex items-center min-h-[44px] cursor-pointer"
        >
          <CheckCircle2 v-if="saveSuccess" class="w-4 h-4 mr-1 text-white" />
          {{ isSaving ? 'Saving...' : saveSuccess ? 'Saved!' : 'Save Availability' }}
        </button>
      </div>

      <div class="bg-white dark:bg-[#121522] rounded-3xl p-4 shadow-xs border border-slate-200/80 dark:border-slate-800/80 overflow-x-auto">
        <table class="w-full text-center border-collapse">
          <thead>
            <tr>
              <th class="p-2 text-left text-[11px] font-black text-slate-400 uppercase tracking-wider">Time Slot</th>
              <th v-for="d in weekDays" :key="d.key" class="p-2 text-[11px] font-black text-slate-700 dark:text-slate-200">
                <div class="uppercase">{{ d.name }}</div>
                <div class="text-[9px] font-bold text-slate-400 lowercase">{{ d.dateLabel }}</div>
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100 dark:divide-slate-800/60">
            <tr v-for="slot in timeSlots" :key="slot">
              <td class="p-2 text-left text-xs font-bold text-slate-600 dark:text-slate-400 whitespace-nowrap">
                <Clock class="w-3 h-3 inline mr-1 text-slate-400" />
                {{ slot.split(' ')[0] }}
              </td>
              <td v-for="d in weekDays" :key="d.key" class="p-1">
                <button 
                  @click="toggleSlot(d.key, slot)"
                  type="button"
                  :aria-label="`Toggle ${d.name} ${slot}`"
                  class="w-full py-2.5 rounded-xl font-black text-xs transition-all cursor-pointer min-h-[44px] flex items-center justify-center"
                  :class="isSlotFree(d.key, slot) 
                    ? 'bg-blue-600 text-white shadow-xs scale-95' 
                    : 'bg-slate-100 dark:bg-[#181d2f] text-slate-400 hover:bg-slate-200 dark:hover:bg-slate-800'"
                >
                  {{ isSlotFree(d.key, slot) ? 'FREE' : '—' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- EDIT PROFILE & SECURE PASSWORD CHANGE MODAL -->
    <div v-if="showEditProfileModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#121522] border border-slate-200 dark:border-slate-800 rounded-3xl p-6 max-w-md w-full space-y-4 shadow-2xl text-left max-h-[85vh] flex flex-col">
        
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-slate-800/80 pb-3">
          <h3 class="font-black text-base text-slate-900 dark:text-white">Edit Profile & Credentials</h3>
          <button @click="showEditProfileModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div class="overflow-y-auto flex-1 space-y-4 pr-1">
          <!-- Full Name -->
          <div class="space-y-1 text-left">
            <label class="text-xs font-black text-slate-700 dark:text-slate-300 uppercase">Full Name</label>
            <input 
              v-model="editFullName" 
              type="text" 
              class="w-full p-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
            >
          </div>

          <!-- Primary Instrument -->
          <div class="space-y-1 text-left">
            <label class="text-xs font-black text-slate-700 dark:text-slate-300 uppercase">Primary Instrument</label>
            <select 
              v-model="editPrimaryInstrument" 
              class="w-full p-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
            >
              <option v-for="inst in instrumentList" :key="inst" :value="inst">{{ inst }}</option>
            </select>
          </div>

          <!-- Secondary Instrument -->
          <div class="space-y-1 text-left">
            <label class="text-xs font-black text-slate-700 dark:text-slate-300 uppercase">Secondary Instrument (Optional)</label>
            <select 
              v-model="editSecondaryInstrument" 
              class="w-full p-3 bg-slate-50 dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
            >
              <option value="None / N/A">None / N/A</option>
              <option v-for="inst in instrumentList" :key="inst" :value="inst">{{ inst }}</option>
            </select>
          </div>

          <!-- Philippine Mobile Number -->
          <div class="space-y-1 text-left">
            <div class="flex justify-between items-center">
              <label class="text-xs font-black text-slate-700 dark:text-slate-300 uppercase">Contact Number (11 digits)</label>
              <span class="text-[10px] font-black" :class="editContactNumber.length === 11 && editContactNumber.startsWith('09') ? 'text-emerald-500' : 'text-slate-400'">
                {{ editContactNumber.length }}/11
              </span>
            </div>
            <input 
              :value="editContactNumber" 
              @input="handlePhoneEditInput"
              type="tel" 
              maxlength="11"
              placeholder="09123456789"
              class="w-full p-3 bg-slate-50 dark:bg-[#181d2f] border rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
              :class="!isEditPhoneValid ? 'border-rose-500' : 'border-slate-200 dark:border-slate-700/80'"
            >
          </div>

          <!-- SECURE PASSWORD CHANGE COLLAPSIBLE SECTION -->
          <div class="pt-2 border-t border-slate-100 dark:border-slate-800/80">
            <button 
              type="button" 
              @click="showPasswordSection = !showPasswordSection"
              class="w-full flex items-center justify-between p-3 rounded-xl bg-slate-100 dark:bg-[#181d2f] text-xs font-black text-slate-800 dark:text-slate-200 min-h-[44px] cursor-pointer"
            >
              <span class="flex items-center"><KeyRound class="w-4 h-4 mr-2 text-blue-500" /> Change Account Password</span>
              <span>{{ showPasswordSection ? '▲' : '▼' }}</span>
            </button>

            <div v-if="showPasswordSection" class="mt-3 space-y-3 p-3 bg-slate-50 dark:bg-[#0f111a] rounded-2xl border border-slate-200 dark:border-slate-800">
              <div class="space-y-1">
                <label class="text-[11px] font-black text-slate-600 dark:text-slate-400 uppercase">New Password</label>
                <div class="relative">
                  <input 
                    v-model="newPassword" 
                    :type="showNewPass ? 'text' : 'password'" 
                    placeholder="Min. 8 characters"
                    class="w-full p-2.5 pr-9 bg-white dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[40px]"
                  >
                  <button type="button" @click="showNewPass = !showNewPass" class="absolute inset-y-0 right-0 pr-2.5 flex items-center text-slate-400">
                    <Eye v-if="!showNewPass" class="w-3.5 h-3.5" />
                    <EyeOff v-else class="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>

              <div class="space-y-1">
                <label class="text-[11px] font-black text-slate-600 dark:text-slate-400 uppercase">Confirm New Password</label>
                <div class="relative">
                  <input 
                    v-model="confirmPassword" 
                    :type="showConfirmPass ? 'text' : 'password'" 
                    placeholder="Re-type new password"
                    class="w-full p-2.5 pr-9 bg-white dark:bg-[#181d2f] border border-slate-200 dark:border-slate-700 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[40px]"
                  >
                  <button type="button" @click="showConfirmPass = !showConfirmPass" class="absolute inset-y-0 right-0 pr-2.5 flex items-center text-slate-400">
                    <Eye v-if="!showConfirmPass" class="w-3.5 h-3.5" />
                    <EyeOff v-else class="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>

              <p v-if="newPassword && newPassword === confirmPassword" class="text-[10px] font-bold text-emerald-500">
                ✓ Passwords match!
              </p>
            </div>
          </div>
        </div>

        <div class="flex space-x-2 pt-3 border-t border-slate-100 dark:border-slate-800/80">
          <button 
            @click="showEditProfileModal = false" 
            type="button" 
            class="flex-1 py-3 bg-slate-100 dark:bg-[#181d2f] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer"
          >
            Cancel
          </button>
          <button 
            @click="handleUpdateProfile" 
            :disabled="isUpdatingProfile" 
            type="button" 
            class="flex-1 py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer"
          >
            {{ isUpdatingProfile ? 'Saving...' : 'Save Changes' }}
          </button>
        </div>

      </div>
    </div>

  </div>
</template>
