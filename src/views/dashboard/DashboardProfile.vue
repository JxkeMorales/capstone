<script setup>
import { ref, onMounted, computed } from 'vue'
import { Phone, Activity, Save, LogOut, Edit3, ShieldCheck, X, Calendar } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'
import { useRouter } from 'vue-router'

const router = useRouter()
const store = useMainStore()

// Dynamic Date Generator for Current Week (Mon to Sun with exact dates e.g. Mon, Aug 3)
const getWeekDays = () => {
  const now = new Date()
  const currentDay = now.getDay()
  const distanceToMon = currentDay === 0 ? -6 : 1 - currentDay
  const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + distanceToMon)

  const week = []
  for (let i = 0; i < 7; i++) {
    const d = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i)
    const dayName = d.toLocaleDateString('en-US', { weekday: 'short' })
    const monthDay = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
    week.push({
      key: dayName,
      fullLabel: `${dayName} (${monthDay})`,
      dateStr: monthDay
    })
  }
  return week
}

const weekDays = computed(() => getWeekDays())
const timeSlots = ['Morning (8am-12pm)', 'Afternoon (1pm-5pm)', 'Evening (6pm-10pm)']

// Vue 3 Fully Reactive Availability Object Map: key `${dayName}::${slot}` -> boolean
const availability = ref({})
const isSaving = ref(false)
const saveSuccess = ref(false)

// Edit Profile Modal State
const showEditProfileModal = ref(false)
const editFullName = ref('')
const editInstrument = ref('')
const editContactNumber = ref('')
const editPassword = ref('')
const isUpdatingProfile = ref(false)

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
  editInstrument.value = store.profile?.instrument || ''
  editContactNumber.value = store.profile?.contact_number || ''
  editPassword.value = ''
  showEditProfileModal.value = true
}

// SAVE PROFILE EDITS
const handleUpdateProfile = async () => {
  if (!store.user) return
  isUpdatingProfile.value = true

  try {
    const { error: profileErr } = await supabase
      .from('profiles')
      .update({
        full_name: editFullName.value.trim(),
        instrument: editInstrument.value,
        contact_number: editContactNumber.value.trim()
      })
      .eq('id', store.user.id)

    if (profileErr) throw profileErr

    if (editPassword.value.trim() !== '') {
      const { error: passErr } = await supabase.auth.updateUser({ password: editPassword.value.trim() })
      if (passErr) throw passErr
    }

    await store.fetchProfile()
    showEditProfileModal.value = false
    alert('Profile updated successfully!')
  } catch (err) {
    console.error('Update profile error:', err)
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
    <section class="bg-white dark:bg-[#121214] rounded-3xl p-5 shadow-xs border border-slate-200/80 dark:border-neutral-800">
      <div class="flex items-center justify-between mb-5">
        <div class="flex items-center space-x-4 min-w-0 pr-2">
          <div class="w-14 h-14 rounded-2xl bg-yellow-400 text-slate-900 flex items-center justify-center text-xl font-black shadow-md flex-shrink-0">
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
          class="p-2.5 bg-yellow-400/20 text-yellow-600 dark:text-yellow-400 hover:bg-yellow-400 hover:text-slate-900 rounded-2xl transition-all min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"
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
            <Calendar class="w-3.5 h-3.5 mr-1 text-yellow-500" /> Weekly Availability Grid
          </h2>
          <p class="text-[11px] text-slate-400 dark:text-neutral-500 mt-0.5">Tap slots when FREE. Saved directly to database.</p>
        </div>
        <button 
          @click="saveAvailability"
          type="button"
          :disabled="isSaving"
          class="text-xs font-black bg-yellow-400 hover:bg-yellow-500 text-slate-900 px-4 py-2.5 rounded-xl flex items-center shadow-md active:scale-95 transition-all disabled:opacity-50 min-h-[44px] cursor-pointer"
        >
          <Save class="w-4 h-4 mr-1.5" /> {{ isSaving ? 'Saving...' : saveSuccess ? 'Saved!' : 'Save Availability' }}
        </button>
      </div>
      
      <div class="bg-white dark:bg-[#121214] rounded-2xl shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-x-auto">
        <table class="w-full text-left border-collapse min-w-[340px]">
          <thead>
            <tr>
              <th class="p-3 text-[10px] font-black text-slate-400 dark:text-neutral-500 uppercase border-b border-r border-slate-100 dark:border-neutral-800 bg-slate-50/50 dark:bg-[#1c1c1e]/50">
                Day & Date
              </th>
              <th v-for="slot in timeSlots" :key="slot" class="p-2 text-[10px] font-black text-slate-400 dark:text-neutral-500 uppercase border-b border-slate-100 dark:border-neutral-800 bg-slate-50/50 dark:bg-[#1c1c1e]/50 text-center">
                {{ slot.split(' ')[0] }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="dayObj in weekDays" :key="dayObj.key" class="border-b border-slate-100 dark:border-neutral-800 last:border-0">
              <td class="p-3 text-xs font-black text-slate-900 dark:text-white border-r border-slate-100 dark:border-neutral-800 bg-slate-50/30 dark:bg-[#1c1c1e]/30 whitespace-nowrap">
                {{ dayObj.fullLabel }}
              </td>
              <td v-for="slot in timeSlots" :key="slot" class="p-1.5 text-center">
                <button 
                  @click="toggleSlot(dayObj.key, slot)"
                  type="button"
                  class="w-full py-3 rounded-xl transition-all border text-xs font-black min-h-[44px] cursor-pointer"
                  :class="isSlotFree(dayObj.key, slot) 
                    ? 'bg-emerald-50 dark:bg-emerald-950/40 border-emerald-500 text-emerald-700 dark:text-emerald-400 shadow-xs' 
                    : 'bg-slate-50 dark:bg-[#1c1c1e] border-slate-200 dark:border-neutral-800 text-slate-400 dark:text-neutral-500 hover:bg-slate-100 dark:hover:bg-neutral-800'"
                >
                  {{ isSlotFree(dayObj.key, slot) ? '✓ FREE' : 'Unavailable' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- EDIT PROFILE DETAILS MODAL -->
    <div v-if="showEditProfileModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#121214] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <h3 class="font-black text-lg text-slate-900 dark:text-white">Edit Profile & Security</h3>
          <button @click="showEditProfileModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div class="space-y-3">
          <div>
            <label for="edit-name" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Full Name</label>
            <input id="edit-name" v-model="editFullName" type="text" class="w-full p-3 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
          </div>

          <div>
            <label for="edit-instrument" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Instrument Played</label>
            <select id="edit-instrument" v-model="editInstrument" class="w-full p-3 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
              <option value="trumpet">Trumpet</option>
              <option value="trombone">Trombone</option>
              <option value="saxophone">Saxophone</option>
              <option value="drums">Drums / Percussion</option>
              <option value="flute">Flute</option>
              <option value="clarinet">Clarinet</option>
            </select>
          </div>

          <div>
            <label for="edit-phone" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Contact Number</label>
            <input id="edit-phone" v-model="editContactNumber" type="tel" class="w-full p-3 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
          </div>

          <div>
            <label for="edit-pass" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">New Password (Optional)</label>
            <input id="edit-pass" v-model="editPassword" type="password" placeholder="Leave blank to keep current" class="w-full p-3 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
          </div>
        </div>

        <div class="flex space-x-2 pt-2">
          <button @click="showEditProfileModal = false" type="button" class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer">Cancel</button>
          <button @click="handleUpdateProfile" :disabled="isUpdatingProfile" type="button" class="flex-1 py-3 bg-yellow-400 font-black text-xs text-slate-900 rounded-xl shadow-md min-h-[44px] cursor-pointer">
            {{ isUpdatingProfile ? 'Saving...' : 'Save Edits' }}
          </button>
        </div>
      </div>
    </div>

  </div>
</template>
