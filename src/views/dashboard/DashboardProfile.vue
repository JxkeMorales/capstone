<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { User, Phone, Music, Activity, Clock, CheckCircle2, LogOut, Edit3, KeyRound, Eye, EyeOff, X, Calendar, AlertCircle } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useUIStore } from '@/stores/ui'
import { supabase } from '@/supabase'

const router = useRouter()
const store = useMainStore()
const uiStore = useUIStore()

const isSaving = ref(false)
const saveSuccess = ref(false)
const availability = ref({})

// Profile Editing Modal State
const showEditProfileModal = ref(false)
const editFullName = ref('')
const editPrimaryInstrument = ref('')
const editSecondaryInstrument = ref('None / N/A')
const editContactNumber = ref('')
const isUpdatingProfile = ref(false)

// Password Change State within Profile
const showPasswordSection = ref(false)
const newPassword = ref('')
const confirmPassword = ref('')
const showNewPass = ref(false)
const showConfirmPass = ref(false)
const passwordChangeSuccess = ref(false)
const passwordChangeError = ref('')

const timeSlots = [
  'Morning (08:00 AM - 12:00 PM)',
  'Afternoon (01:00 PM - 05:00 PM)',
  'Evening (06:00 PM - 10:00 PM)'
]

// Day Names with Accurate Calculated Dates for Current Week
const weekDays = computed(() => {
  const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
  const now = new Date()
  const currentDayIndex = now.getDay() === 0 ? 7 : now.getDay() // 1 is Monday, 7 is Sunday
  
  return dayNames.map((name, index) => {
    const dayNumber = index + 1
    const d = new Date(now)
    const diff = dayNumber - currentDayIndex
    d.setDate(now.getDate() + diff)
    const dateStr = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
    return {
      key: name.toLowerCase(),
      name: name.slice(0, 3),
      fullName: name,
      dateLabel: dateStr
    }
  })
})

const instrumentList = [
  'Clarinet',
  'Bass Clarinet',
  'Flute',
  'Piccolo',
  'French Horn',
  'Tenor Sax',
  'Sax (Alto Sax)',
  'Baritone Sax',
  'Trumpet',
  'Trombone',
  'Bass Trombone',
  'Baritone / Euphonium',
  'Bass / Tuba',
  'Bass Drum',
  'Snare Drum / Drums',
  'Cymbals'
]

const handlePhoneEditInput = (e) => {
  let val = e.target.value.replace(/\D/g, '')
  if (val.length > 11) val = val.slice(0, 11)
  editContactNumber.value = val
}

const isEditPhoneValid = computed(() => {
  if (!editContactNumber.value) return true
  return /^09\d{9}$/.test(editContactNumber.value)
})

const fetchAvailability = async () => {
  if (!store.user) return
  try {
    const { data } = await supabase
      .from('member_availability')
      .select('day_of_week, time_slot, is_free')
      .eq('user_id', store.user.id)

    if (data && data.length > 0) {
      const map = {}
      data.forEach(item => {
        const key = `${item.day_of_week}_${item.time_slot}`
        map[key] = item.is_free
      })
      availability.value = map
    }
  } catch (err) {
    console.error('Error fetching availability:', err)
  }
}

const isSlotFree = (dayKey, slot) => {
  const shortSlot = slot.split(' ')[0]
  const key = `${dayKey}_${shortSlot}`
  return availability.value[key] === true
}

const toggleSlot = (dayKey, slot) => {
  const shortSlot = slot.split(' ')[0]
  const key = `${dayKey}_${shortSlot}`
  availability.value[key] = !availability.value[key]
  saveSuccess.value = false
}

const saveAvailability = async () => {
  if (!store.user) return
  isSaving.value = true
  saveSuccess.value = false

  try {
    const rows = []
    for (const d of weekDays.value) {
      for (const slot of timeSlots) {
        const shortSlot = slot.split(' ')[0]
        const key = `${d.key}_${shortSlot}`
        const isFree = availability.value[key] === true
        rows.push({
          user_id: store.user.id,
          day_of_week: d.key,
          time_slot: shortSlot,
          is_free: isFree
        })
      }
    }

    const { data: existing } = await supabase
      .from('member_availability')
      .select('id, day_of_week, time_slot')
      .eq('user_id', store.user.id)

    const existingMap = {}
    if (existing) {
      existing.forEach(e => { existingMap[`${e.day_of_week}_${e.time_slot}`] = e.id })
    }

    const toUpdate = []
    const toInsert = []

    for (const row of rows) {
      const id = existingMap[`${row.day_of_week}_${row.time_slot}`]
      if (id) {
        toUpdate.push({ id, ...row })
      } else {
        toInsert.push(row)
      }
    }

    if (toInsert.length > 0) {
      const { error: insertErr } = await supabase.from('member_availability').insert(toInsert)
      if (insertErr) throw insertErr
    }

    for (const item of toUpdate) {
      const { id, ...updateData } = item
      await supabase.from('member_availability').update(updateData).eq('id', id)
    }

    saveSuccess.value = true
    setTimeout(() => { saveSuccess.value = false }, 3000)
    uiStore.addToast({ title: 'Availability Saved', message: 'Your weekly availability has been updated.', type: 'success' })
  } catch (err) {
    console.error('Save availability error:', err)
    uiStore.addToast({ title: 'Save Failed', message: 'Failed to save availability.', type: 'error' })
  } finally {
    isSaving.value = false
  }
}

const openEditProfile = () => {
  editFullName.value = store.profile?.full_name || ''
  const currentInst = store.profile?.instrument || ''
  
  if (currentInst.includes(' + ')) {
    const parts = currentInst.split(' + ')
    editPrimaryInstrument.value = instrumentList.includes(parts[0]) ? parts[0] : 'Trumpet'
    editSecondaryInstrument.value = instrumentList.includes(parts[1]) ? parts[1] : 'None / N/A'
  } else {
    // Legacy slash support or single instrument
    const possibleMatch = instrumentList.find(inst => currentInst.startsWith(inst + ' / ') && currentInst !== inst)
    if (possibleMatch) {
       editPrimaryInstrument.value = possibleMatch
       const secondary = currentInst.substring(possibleMatch.length + 3)
       editSecondaryInstrument.value = instrumentList.includes(secondary) ? secondary : 'None / N/A'
    } else {
       editPrimaryInstrument.value = instrumentList.includes(currentInst) ? currentInst : 'Trumpet'
       editSecondaryInstrument.value = 'None / N/A'
    }
  }
  editContactNumber.value = store.profile?.contact_number || ''
  showPasswordSection.value = false
  newPassword.value = ''
  confirmPassword.value = ''
  passwordChangeSuccess.value = false
  passwordChangeError.value = ''
  showEditProfileModal.value = true
}

const handleUpdateProfile = async () => {
  isUpdatingProfile.value = true
  passwordChangeError.value = ''
  
  try {
    if (editContactNumber.value && !/^09\d{9}$/.test(editContactNumber.value.trim())) {
      throw new Error('Contact number must be an 11-digit Philippine number starting with 09.')
    }

    const combinedInstrument = editSecondaryInstrument.value && editSecondaryInstrument.value !== 'None / N/A'
      ? `${editPrimaryInstrument.value} + ${editSecondaryInstrument.value}`
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

    await store.fetchProfile(true)
    showEditProfileModal.value = false
    uiStore.addToast({ title: 'Profile Updated', message: 'Your profile has been updated successfully!', type: 'success' })
  } catch (err) {
    console.error('Update profile error:', err)
    passwordChangeError.value = err?.message || 'Failed to update profile.'
    uiStore.addToast({ title: 'Update Failed', message: err?.message || 'Failed to update profile.', type: 'error' })
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

    <!-- Profile Info Card with Edit Trigger (Lighter Matte Black) -->
    <section class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-5 shadow-xs border border-slate-200/80 dark:border-neutral-800">
      <div class="flex items-center justify-between mb-5">
        <div class="flex items-center space-x-4 min-w-0 pr-2">
          <div class="w-14 h-14 rounded-2xl bg-blue-600 text-white flex items-center justify-center text-xl font-black shadow-md flex-shrink-0">
            {{ store.profile?.full_name ? store.profile.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB' }}
          </div>
          <div class="min-w-0">
            <h2 class="text-lg font-black text-slate-900 dark:text-white truncate">
              {{ store.profile?.full_name || 'Member' }}
            </h2>
            <p class="text-xs font-bold text-slate-500 dark:text-neutral-400 mt-0.5 capitalize">
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
        <div class="flex items-center text-xs font-semibold text-slate-700 dark:text-neutral-300">
          <Phone class="w-4 h-4 mr-3 text-slate-400 dark:text-neutral-500 flex-shrink-0" />
          <span>{{ store.profile?.contact_number || store.profile?.email || 'No contact specified' }}</span>
        </div>
        <div class="flex items-center text-xs font-semibold text-slate-700 dark:text-neutral-300">
          <Activity class="w-4 h-4 mr-3 text-slate-400 dark:text-neutral-500 flex-shrink-0" />
          <span>Verification Status: {{ store.profile?.is_verified ? 'Verified Master List' : 'Pending Verification' }}</span>
        </div>
      </div>
    </section>

    <!-- Dynamic Weekly Availability Grid with Exact Dates -->
    <section class="space-y-3">
      <div class="flex justify-between items-end px-1">
        <div>
          <h2 class="text-xs font-extrabold text-slate-500 dark:text-neutral-400 uppercase tracking-wider flex items-center">
            <Calendar class="w-3.5 h-3.5 mr-1 text-blue-500" /> Weekly Availability Grid
          </h2>
          <p class="text-[11px] text-slate-400 dark:text-neutral-500 mt-0.5">Tap slots when FREE. Saved directly to database.</p>
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

      <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-x-auto">
        <table class="w-full text-center border-collapse">
          <thead>
            <tr>
              <th class="p-2 text-left text-[11px] font-black text-slate-400 uppercase tracking-wider">Time Slot</th>
              <th v-for="d in weekDays" :key="d.key" class="p-2 text-[11px] font-black text-slate-700 dark:text-neutral-200">
                <div class="uppercase">{{ d.name }}</div>
                <div class="text-[9px] font-bold text-slate-400 lowercase">{{ d.dateLabel }}</div>
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100 dark:divide-neutral-800/60">
            <tr v-for="slot in timeSlots" :key="slot">
              <td class="p-2 text-left text-xs font-bold text-slate-600 dark:text-neutral-400 whitespace-nowrap">
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
                    : 'bg-slate-100 dark:bg-[#27272a] text-slate-400 hover:bg-slate-200 dark:hover:bg-[#323238]'"
                >
                  {{ isSlotFree(d.key, slot) ? 'FREE' : '—' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- EDIT PROFILE & SECURE PASSWORD CHANGE MODAL (Lighter Matte Black) -->
    <div v-if="showEditProfileModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-md w-full space-y-4 shadow-2xl text-left max-h-[85vh] flex flex-col">
        
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <h3 class="font-black text-base text-slate-900 dark:text-white">Edit Profile & Credentials</h3>
          <button @click="showEditProfileModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div class="overflow-y-auto flex-1 space-y-4 pr-1">
          <!-- Full Name -->
          <div class="space-y-1 text-left">
            <label class="text-xs font-black text-slate-700 dark:text-neutral-300 uppercase">Full Name</label>
            <input 
              v-model="editFullName" 
              type="text" 
              class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
            >
          </div>

          <!-- Primary Instrument -->
          <div class="space-y-1 text-left">
            <label class="text-xs font-black text-slate-700 dark:text-neutral-300 uppercase">Primary Instrument</label>
            <select 
              v-model="editPrimaryInstrument" 
              class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
            >
              <option v-for="inst in instrumentList" :key="inst" :value="inst">{{ inst }}</option>
            </select>
          </div>

          <!-- Secondary Instrument -->
          <div class="space-y-1 text-left">
            <label class="text-xs font-black text-slate-700 dark:text-neutral-300 uppercase">Secondary Instrument (Optional)</label>
            <select 
              v-model="editSecondaryInstrument" 
              class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
            >
              <option value="None / N/A">None / N/A</option>
              <option v-for="inst in instrumentList" :key="inst" :value="inst">{{ inst }}</option>
            </select>
          </div>

          <!-- Philippine Mobile Number -->
          <div class="space-y-1 text-left">
            <div class="flex justify-between items-center">
              <label class="text-xs font-black text-slate-700 dark:text-neutral-300 uppercase">Contact Number (11 digits)</label>
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
              class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
              :class="!isEditPhoneValid ? 'border-rose-500' : 'border-slate-200 dark:border-neutral-700/80'"
            >
          </div>

          <!-- SECURE PASSWORD CHANGE COLLAPSIBLE SECTION -->
          <div class="pt-2 border-t border-slate-100 dark:border-neutral-800">
            <button 
              type="button" 
              @click="showPasswordSection = !showPasswordSection"
              class="w-full flex items-center justify-between p-3 rounded-xl bg-slate-100 dark:bg-[#27272a] text-xs font-black text-slate-800 dark:text-neutral-200 min-h-[44px] cursor-pointer"
            >
              <span class="flex items-center"><KeyRound class="w-4 h-4 mr-2 text-blue-500" /> Change Account Password</span>
              <span>{{ showPasswordSection ? '▲' : '▼' }}</span>
            </button>

            <div v-if="showPasswordSection" class="mt-3 space-y-3 p-3 bg-slate-50 dark:bg-[#18181b] rounded-2xl border border-slate-200 dark:border-neutral-800">
              <div class="space-y-1">
                <label class="text-[11px] font-black text-slate-600 dark:text-neutral-400 uppercase">New Password</label>
                <div class="relative">
                  <input 
                    v-model="newPassword" 
                    :type="showNewPass ? 'text' : 'password'" 
                    placeholder="Min. 8 characters"
                    class="w-full p-2.5 pr-9 bg-white dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[40px]"
                  >
                  <button type="button" @click="showNewPass = !showNewPass" class="absolute inset-y-0 right-0 pr-2.5 flex items-center text-slate-400">
                    <Eye v-if="!showNewPass" class="w-3.5 h-3.5" />
                    <EyeOff v-else class="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>

              <div class="space-y-1">
                <label class="text-[11px] font-black text-slate-600 dark:text-neutral-400 uppercase">Confirm New Password</label>
                <div class="relative">
                  <input 
                    v-model="confirmPassword" 
                    :type="showConfirmPass ? 'text' : 'password'" 
                    placeholder="Re-type new password"
                    class="w-full p-2.5 pr-9 bg-white dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[40px]"
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

        <div class="flex space-x-2 pt-3 border-t border-slate-100 dark:border-neutral-800">
          <button 
            @click="showEditProfileModal = false" 
            type="button" 
            class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer"
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
