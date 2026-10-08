<script setup>
import { ref, onMounted, computed, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { User, Phone, Music, Activity, Clock, CheckCircle2, Check, LogOut, Edit3, KeyRound, Eye, EyeOff, X, Calendar, AlertCircle, Camera, Loader2, Settings, ShieldCheck } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useUIStore } from '@/stores/ui'
import { supabase } from '@/supabase'
import { broadcastSync } from '@/utils/realtime'

const router = useRouter()
const route = useRoute()
const store = useMainStore()
const uiStore = useUIStore()

const isSaving = ref(false)
const saveSuccess = ref(false)
const availability = ref({})

// Settings Pop-up Modal State
const showEditProfileModal = ref(false)
const activeSettingsTab = ref('profile') // 'profile' | 'availability' | 'security'
const editFullName = ref('')
const editPrimaryInstrument = ref('')
const editSecondaryInstrument = ref('None / N/A')
const editContactNumber = ref('')
const isUpdatingProfile = ref(false)

// Sign Out Confirmation Warning State
const showSignOutModal = ref(false)

// Password Change State within Settings
const showPasswordSection = ref(true)
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
  'Cymbals',
  'Majorette',
  'Color Guard / Flag'
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

    const { error: upsertErr } = await supabase
      .from('member_availability')
      .upsert(rows, { onConflict: 'user_id,day_of_week,time_slot' })

    if (upsertErr) {
      // Fallback: delete existing for user and insert fresh
      await supabase.from('member_availability').delete().eq('user_id', store.user.id)
      const { error: insertErr } = await supabase.from('member_availability').insert(rows)
      if (insertErr) throw insertErr
    }

    saveSuccess.value = true
    setTimeout(() => { saveSuccess.value = false }, 3000)
    broadcastSync('availability_changed', { userId: store.user.id })
    uiStore.addToast({ title: 'Availability Saved', message: 'Your weekly availability has been updated.', type: 'success' })
  } catch (err) {
    console.error('Save availability error:', err)
    uiStore.addToast({ title: 'Save Failed', message: 'Failed to save availability.', type: 'error' })
  } finally {
    isSaving.value = false
  }
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
    broadcastSync('account_status_changed', { userId: store.user.id, type: 'profile_updated' })
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

const triggerSignOut = () => {
  showSignOutModal.value = true
}

const handleSignOut = async () => {
  showSignOutModal.value = false
  await store.signOut()
  router.push('/')
}

const openEditProfile = (initialTab = 'profile') => {
  activeSettingsTab.value = initialTab
  editFullName.value = store.profile?.full_name || ''
  const currentInst = store.profile?.instrument || ''
  
  if (currentInst.includes(' + ')) {
    const parts = currentInst.split(' + ')
    editPrimaryInstrument.value = instrumentList.includes(parts[0]) ? parts[0] : 'Trumpet'
    editSecondaryInstrument.value = instrumentList.includes(parts[1]) ? parts[1] : 'None / N/A'
  } else {
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
  newPassword.value = ''
  confirmPassword.value = ''
  passwordChangeSuccess.value = false
  passwordChangeError.value = ''
  showEditProfileModal.value = true
}

const imgLoadError = ref(false)

watch(() => store.profile?.profile_picture, () => {
  imgLoadError.value = false
})

onMounted(async () => {
  fetchAvailability()
  imgLoadError.value = false
  await store.fetchProfile(true)
  if (route.query.settings === 'true' || route.query.modal === 'true') {
    openEditProfile()
  } else if (window.location.hash.includes('type=recovery') || route.query.type === 'recovery') {
    openEditProfile('security')
  }
})

// ==========================================
// AVATAR UPLOAD LOGIC
// ==========================================
const fileInput = ref(null)
const isUploading = ref(false)

const triggerFileUpload = () => {
  if (fileInput.value) fileInput.value.click()
}

const handleFileUpload = async (event) => {
  const file = event.target.files[0]
  if (!file) return

  if (file.size > 5 * 1024 * 1024) {
    uiStore.addToast({ title: 'File too large', message: 'Please upload an image smaller than 5MB.', type: 'error' })
    return
  }

  isUploading.value = true
  imgLoadError.value = false
  try {
    const fileExt = file.name.split('.').pop()
    const fileName = `${store.user.id}/avatar.${fileExt}`
    
    const { error: uploadError } = await supabase.storage
      .from('avatars')
      .upload(fileName, file, { upsert: true })

    if (uploadError) throw uploadError

    const { data: publicUrlData } = supabase.storage
      .from('avatars')
      .getPublicUrl(fileName)
      
    // Cache bust URL
    const finalUrl = publicUrlData.publicUrl + '?t=' + Date.now()
      
    const { error: updateError } = await supabase
      .from('profiles')
      .update({ 
        profile_picture: finalUrl, 
        profile_picture_status: 'pending' 
      })
      .eq('id', store.user.id)

    if (updateError) throw updateError

    if (store.profile) {
      store.profile.profile_picture = finalUrl
      store.profile.profile_picture_status = 'pending'
      try {
        localStorage.setItem('smartband_user_profile_cache', JSON.stringify(store.profile))
      } catch (e) {}
    }
    
    broadcastSync('account_status_changed', { userId: store.user.id, type: 'avatar_uploaded' })
    uiStore.addToast({ title: 'Photo Uploaded', message: 'Your picture was sent for Admin approval.', type: 'info' })
  } catch (error) {
    console.error('Avatar upload error:', error)
    uiStore.addToast({ title: 'Upload Failed', message: error.message || 'Could not upload image.', type: 'error' })
  } finally {
    isUploading.value = false
    event.target.value = ''
  }
}
</script>

<template>
  <div class="p-4 sm:p-6 space-y-6 max-w-5xl mx-auto">
    
    <header class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pt-1 border-b border-slate-200/80 dark:border-neutral-800 pb-4">
      <div>
        <p class="text-xs font-medium text-slate-500 dark:text-neutral-400">Account Management</p>
        <h1 class="text-2xl font-bold text-slate-900 dark:text-neutral-100">My Profile</h1>
      </div>
      <div class="flex items-center space-x-2 self-start sm:self-auto">
        <button 
          @click="openEditProfile('profile')"
          type="button"
          class="text-xs font-medium text-slate-700 dark:text-neutral-200 bg-white dark:bg-[#202124] border border-slate-200 dark:border-neutral-700 px-4 py-2 rounded-full flex items-center hover:bg-slate-50 dark:hover:bg-[#2d2f31] transition-colors min-h-[40px] cursor-pointer shadow-xs"
        >
          <Settings class="w-3.5 h-3.5 mr-1.5 text-slate-500 dark:text-neutral-400" /> Profile Settings
        </button>
        <button 
          @click="triggerSignOut"
          type="button"
          class="text-xs font-medium text-rose-600 dark:text-rose-400 bg-white dark:bg-[#202124] border border-slate-200 dark:border-neutral-700 px-4 py-2 rounded-full flex items-center hover:bg-rose-50 dark:hover:bg-rose-950/30 transition-colors min-h-[40px] cursor-pointer shadow-xs"
          aria-label="Sign Out of Account"
        >
          <LogOut class="w-3.5 h-3.5 mr-1.5" /> Sign Out
        </button>
      </div>
    </header>

    <!-- Profile Info Card with Edit Trigger -->
    <section class="bg-white dark:bg-[#202124] rounded-2xl p-6 shadow-xs border border-slate-200/80 dark:border-neutral-800">
      <div class="flex items-center justify-between mb-5">
        <div class="flex items-center space-x-4 min-w-0 pr-2">
          
          <div class="relative w-16 h-16 flex-shrink-0 group cursor-pointer" @click="triggerFileUpload">
            <input type="file" accept="image/jpeg, image/png, image/webp" @change="handleFileUpload" class="hidden" ref="fileInput" />
            
            <template v-if="store.profile?.profile_picture && !imgLoadError">
              <img :src="store.profile.profile_picture" @error="imgLoadError = true" alt="Avatar" class="w-full h-full object-cover rounded-full border border-slate-200 dark:border-neutral-700 shadow-xs" />
              <div v-if="store.profile.profile_picture_status === 'pending'" class="absolute -bottom-1 -right-1 bg-amber-500 text-white text-[9px] font-bold px-1.5 py-0.2 rounded-full border-2 border-white dark:border-[#202124] uppercase">Pending</div>
              <div v-else-if="store.profile.profile_picture_status === 'declined'" class="absolute -bottom-1 -right-1 bg-rose-500 text-white text-[9px] font-bold px-1.5 py-0.2 rounded-full border-2 border-white dark:border-[#202124] uppercase">Declined</div>
              <div v-else-if="store.profile.profile_picture_status === 'approved'" class="absolute -bottom-1 -right-1 bg-emerald-600 text-white p-0.5 rounded-full border-2 border-white dark:border-[#202124]" title="Approved">
                <Check class="w-3 h-3 stroke-[2.5]" />
              </div>
            </template>
            <template v-else>
              <div class="w-full h-full rounded-full bg-slate-900 dark:bg-white text-white dark:text-slate-900 flex items-center justify-center text-lg font-bold">
                {{ store.profile?.full_name ? store.profile.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB' }}
              </div>
            </template>
            
            <!-- Hover Overlay -->
            <div class="absolute inset-0 bg-black/40 rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
               <Camera v-if="!isUploading" class="w-5 h-5 text-white" />
               <Loader2 v-else class="w-5 h-5 text-white animate-spin" />
            </div>
          </div>

          <div class="min-w-0">
            <h2 class="text-lg font-bold text-slate-900 dark:text-neutral-100 truncate">
              {{ store.profile?.full_name || 'Member' }}
            </h2>
            <p class="text-xs font-medium text-slate-500 dark:text-neutral-400 mt-0.5 capitalize">
              {{ store.profile?.instrument || 'Musician' }} • {{ store.profile?.rank || 'Junior' }} Rank
            </p>
          </div>
        </div>

        <button 
          @click="openEditProfile('profile')"
          type="button"
          class="p-2.5 bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-300 hover:bg-slate-200 dark:hover:bg-[#383a3d] rounded-full transition-colors min-w-[40px] min-h-[40px] flex items-center justify-center cursor-pointer border border-slate-200 dark:border-neutral-700"
          aria-label="Edit Profile Details"
          title="Edit Profile Settings"
        >
          <Edit3 class="w-4 h-4" />
        </button>
      </div>

      <div class="space-y-2 pt-2 border-t border-slate-100 dark:border-neutral-800">
        <div class="flex items-center text-xs text-slate-600 dark:text-neutral-400 font-medium">
          <Phone class="w-3.5 h-3.5 mr-2.5 text-slate-400 dark:text-neutral-500 flex-shrink-0" />
          <span>{{ store.profile?.contact_number || store.profile?.email || 'No contact specified' }}</span>
        </div>
        <div class="flex items-center text-xs text-slate-600 dark:text-neutral-400 font-medium">
          <Activity class="w-3.5 h-3.5 mr-2.5 text-slate-400 dark:text-neutral-500 flex-shrink-0" />
          <span>Verification Status: {{ store.profile?.is_verified ? 'Verified Member' : 'Pending Verification' }}</span>
        </div>
      </div>
    </section>

    <!-- Dynamic Weekly Availability Grid with Exact Dates -->
    <section class="space-y-3">
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-end gap-2 px-1">
        <div>
          <h2 class="text-xs font-semibold text-slate-500 dark:text-neutral-400 uppercase tracking-wider flex items-center">
            <Calendar class="w-3.5 h-3.5 mr-1.5 text-slate-500 dark:text-neutral-400" /> Weekly Availability Grid
          </h2>
          <p class="text-[11px] text-slate-400 dark:text-neutral-500 mt-0.5">Toggle slots when you are available. Saved directly to the roster.</p>
        </div>
        <button 
          @click="saveAvailability" 
          :disabled="isSaving"
          class="px-4 py-2 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-neutral-100 text-white dark:text-slate-900 font-medium text-xs rounded-full shadow-xs active:scale-95 transition-all flex items-center min-h-[38px] cursor-pointer"
        >
          <CheckCircle2 v-if="saveSuccess" class="w-3.5 h-3.5 mr-1" />
          {{ isSaving ? 'Saving...' : saveSuccess ? 'Saved' : 'Save Availability' }}
        </button>
      </div>

      <div class="bg-white dark:bg-[#202124] rounded-2xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-x-auto">
        <table class="w-full text-center border-collapse">
          <thead>
            <tr>
              <th class="p-2 text-left text-[11px] font-semibold text-slate-400 uppercase tracking-wider">Time Slot</th>
              <th v-for="d in weekDays" :key="d.key" class="p-2 text-[11px] font-semibold text-slate-700 dark:text-neutral-200">
                <div class="uppercase">{{ d.name }}</div>
                <div class="text-[9px] font-normal text-slate-400 lowercase">{{ d.dateLabel }}</div>
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100 dark:divide-neutral-800/60">
            <tr v-for="slot in timeSlots" :key="slot">
              <td class="p-2 text-left text-xs font-medium text-slate-600 dark:text-neutral-400 whitespace-nowrap">
                <Clock class="w-3 h-3 inline mr-1 text-slate-400" />
                {{ slot.split(' ')[0] }}
              </td>
              <td v-for="d in weekDays" :key="d.key" class="p-1">
                <button 
                  @click="toggleSlot(d.key, slot)"
                  type="button"
                  :aria-label="`Toggle ${d.name} ${slot}`"
                  class="w-full py-2 rounded-full font-medium text-xs transition-colors cursor-pointer min-h-[36px] flex items-center justify-center"
                  :class="isSlotFree(d.key, slot) 
                    ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900' 
                    : 'bg-slate-100 dark:bg-[#2d2f31] text-slate-400 dark:text-neutral-500 hover:bg-slate-200 dark:hover:bg-[#383a3d]'"
                >
                  {{ isSlotFree(d.key, slot) ? 'FREE' : '—' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- COMPLETE POP-UP SETTINGS MODAL (Profile, Phone, Instruments, Password, Availability Grid) (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showEditProfileModal" class="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-[#2d3035] rounded-3xl p-5 sm:p-6 max-w-lg w-full space-y-4 shadow-xl text-left max-h-[88vh] flex flex-col">
        
        <!-- Modal Header -->
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-[#2d3035] pb-3">
          <div class="flex items-center space-x-2">
            <Settings class="w-5 h-5 text-slate-600 dark:text-neutral-400" />
            <h3 class="font-bold text-base text-slate-900 dark:text-neutral-100">Profile & Settings</h3>
          </div>
          <button @click="showEditProfileModal = false" class="text-slate-400 hover:text-slate-900 dark:hover:text-white min-w-[48px] min-h-[48px] flex items-center justify-center cursor-pointer rounded-full hover:bg-slate-100 dark:hover:bg-[#2d2f31]" aria-label="Close modal">
            <X class="w-5 h-5" />
          </button>
        </div>

        <!-- Setting Navigation Tabs (Segmented Pill Switcher) -->
        <div class="flex rounded-full bg-slate-100 dark:bg-[#2d2f31] p-1 gap-1 border border-slate-200/60 dark:border-[#2d3035]">
          <button 
            type="button" 
            @click="activeSettingsTab = 'profile'"
            class="flex-1 py-2 rounded-full text-xs font-medium transition-all cursor-pointer text-center min-h-[40px]"
            :class="activeSettingsTab === 'profile' ? 'bg-white dark:bg-[#1e1f20] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 dark:text-neutral-400'"
          >
            Profile
          </button>
          <button 
            type="button" 
            @click="activeSettingsTab = 'availability'"
            class="flex-1 py-2 rounded-full text-xs font-medium transition-all cursor-pointer text-center min-h-[40px]"
            :class="activeSettingsTab === 'availability' ? 'bg-white dark:bg-[#1e1f20] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 dark:text-neutral-400'"
          >
            Availability
          </button>
          <button 
            type="button" 
            @click="activeSettingsTab = 'security'"
            class="flex-1 py-2 rounded-full text-xs font-medium transition-all cursor-pointer text-center min-h-[40px]"
            :class="activeSettingsTab === 'security' ? 'bg-white dark:bg-[#1e1f20] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 dark:text-neutral-400'"
          >
            Password
          </button>
        </div>

        <!-- TAB CONTENT AREA -->
        <div class="overflow-y-auto flex-1 space-y-4 pr-1">

          <!-- TAB 1: PROFILE, PHONE & INSTRUMENTS -->
          <div v-if="activeSettingsTab === 'profile'" class="space-y-4">
            <!-- Full Name -->
            <div class="space-y-1.5 text-left">
              <label class="text-xs font-medium text-slate-700 dark:text-neutral-300">Full Name</label>
              <input 
                v-model="editFullName" 
                type="text" 
                class="w-full px-3.5 py-3 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-[#2d3035] rounded-xl text-xs font-medium text-slate-900 dark:text-white min-h-[48px] focus:outline-none focus:border-slate-400"
              >
            </div>

            <!-- Primary Instrument -->
            <div class="space-y-1.5 text-left">
              <label class="text-xs font-medium text-slate-700 dark:text-neutral-300">Primary Instrument</label>
              <select 
                v-model="editPrimaryInstrument" 
                class="w-full px-3.5 py-3 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-[#2d3035] rounded-xl text-xs font-medium text-slate-900 dark:text-white min-h-[48px] focus:outline-none focus:border-slate-400 cursor-pointer"
              >
                <option v-for="inst in instrumentList" :key="inst" :value="inst">{{ inst }}</option>
              </select>
            </div>

            <!-- Secondary Instrument -->
            <div class="space-y-1.5 text-left">
              <label class="text-xs font-medium text-slate-700 dark:text-neutral-300">Secondary Instrument (Optional)</label>
              <select 
                v-model="editSecondaryInstrument" 
                class="w-full px-3.5 py-3 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-[#2d3035] rounded-xl text-xs font-medium text-slate-900 dark:text-white min-h-[48px] focus:outline-none focus:border-slate-400 cursor-pointer"
              >
                <option value="None / N/A">None / N/A</option>
                <option v-for="inst in instrumentList" :key="inst" :value="inst">{{ inst }}</option>
              </select>
            </div>

            <!-- Philippine Mobile Phone Number -->
            <div class="space-y-1.5 text-left">
              <div class="flex justify-between items-center">
                <label class="text-xs font-medium text-slate-700 dark:text-neutral-300">Phone Number (11 digits)</label>
                <span class="text-[10px] font-medium" :class="editContactNumber.length === 11 && editContactNumber.startsWith('09') ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-400'">
                  {{ editContactNumber.length }}/11
                </span>
              </div>
              <input 
                :value="editContactNumber" 
                @input="handlePhoneEditInput" 
                type="tel" 
                maxlength="11"
                placeholder="09123456789"
                class="w-full px-3.5 py-3 bg-slate-50 dark:bg-[#18191a] border rounded-xl text-xs font-medium text-slate-900 dark:text-white min-h-[48px] focus:outline-none focus:border-slate-400"
                :class="!isEditPhoneValid ? 'border-rose-500' : 'border-slate-200 dark:border-[#2d3035]'"
              >
            </div>
          </div>

          <!-- TAB 2: AVAILABILITY GRID (Settings Pop-up integration) -->
          <div v-else-if="activeSettingsTab === 'availability'" class="space-y-3">
            <div class="p-3.5 rounded-2xl bg-slate-50 dark:bg-[#18191a] border border-slate-200/80 dark:border-[#2d3035] text-xs text-slate-600 dark:text-neutral-400">
              <p class="font-medium text-slate-900 dark:text-neutral-200">Weekly Schedule Availability</p>
              <p class="text-[11px] mt-0.5">Toggle slots between FREE and busy. The Band Secretary uses this grid to schedule gigs and check musician availability.</p>
            </div>

            <div class="rounded-2xl border border-slate-200 dark:border-[#2d3035] overflow-x-auto">
              <table class="w-full text-center border-collapse text-xs">
                <thead class="bg-slate-50 dark:bg-[#18191a] border-b border-slate-200 dark:border-[#2d3035]">
                  <tr>
                    <th class="p-2.5 text-left text-[10px] font-semibold text-slate-400 uppercase">Slot</th>
                    <th v-for="d in weekDays" :key="d.key" class="p-2.5 text-[10px] font-semibold text-slate-700 dark:text-neutral-200">
                      {{ d.name }}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-100 dark:divide-[#2d3035]">
                  <tr v-for="slot in timeSlots" :key="slot">
                    <td class="p-2.5 text-left font-medium text-slate-600 dark:text-neutral-400 text-[11px] whitespace-nowrap">
                      {{ slot.split(' ')[0] }}
                    </td>
                    <td v-for="d in weekDays" :key="d.key" class="p-1">
                      <button 
                        @click="toggleSlot(d.key, slot)"
                        type="button"
                        class="w-full py-2 rounded-full font-medium text-[10px] transition-colors cursor-pointer min-h-[36px] flex items-center justify-center"
                        :class="isSlotFree(d.key, slot) 
                          ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900' 
                          : 'bg-slate-100 dark:bg-[#2d2f31] text-slate-400 hover:bg-slate-200 dark:hover:bg-[#383a3d]'"
                      >
                        {{ isSlotFree(d.key, slot) ? 'FREE' : '—' }}
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <button 
              @click="saveAvailability" 
              :disabled="isSaving"
              type="button" 
              class="w-full py-2.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-neutral-100 text-white dark:text-slate-900 font-medium text-xs rounded-full shadow-xs transition-colors flex items-center justify-center min-h-[48px] cursor-pointer"
            >
              <CheckCircle2 v-if="saveSuccess" class="w-4 h-4 mr-1.5" />
              {{ isSaving ? 'Saving Grid...' : saveSuccess ? 'Saved' : 'Save Availability Grid' }}
            </button>
          </div>

          <!-- TAB 3: PASSWORD CHANGE -->
          <div v-else-if="activeSettingsTab === 'security'" class="space-y-4">
            <div class="space-y-1.5">
              <label class="text-xs font-medium text-slate-700 dark:text-neutral-300">New Password</label>
              <div class="relative">
                <input 
                  v-model="newPassword" 
                  :type="showNewPass ? 'text' : 'password'" 
                  placeholder="Min. 8 characters"
                  class="w-full px-3.5 py-3 pr-10 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-[#2d3035] rounded-xl text-xs font-medium text-slate-900 dark:text-white min-h-[48px] focus:outline-none focus:border-slate-400"
                >
                <button type="button" @click="showNewPass = !showNewPass" class="absolute inset-y-0 right-0 pr-3 flex items-center text-slate-400 min-w-[48px] justify-center cursor-pointer">
                  <Eye v-if="!showNewPass" class="w-4 h-4" />
                  <EyeOff v-else class="w-4 h-4" />
                </button>
              </div>
            </div>

            <div class="space-y-1.5">
              <label class="text-xs font-medium text-slate-700 dark:text-neutral-300">Confirm New Password</label>
              <div class="relative">
                <input 
                  v-model="confirmPassword" 
                  :type="showConfirmPass ? 'text' : 'password'" 
                  placeholder="Re-type new password"
                  class="w-full px-3.5 py-3 pr-10 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-[#2d3035] rounded-xl text-xs font-medium text-slate-900 dark:text-white min-h-[48px] focus:outline-none focus:border-slate-400"
                >
                <button type="button" @click="showConfirmPass = !showConfirmPass" class="absolute inset-y-0 right-0 pr-3 flex items-center text-slate-400 min-w-[48px] justify-center cursor-pointer">
                  <Eye v-if="!showConfirmPass" class="w-4 h-4" />
                  <EyeOff v-else class="w-4 h-4" />
                </button>
              </div>
            </div>

            <p v-if="newPassword && newPassword === confirmPassword" class="text-xs font-medium text-emerald-600 dark:text-emerald-400">
              ✓ Passwords match
            </p>
            <p v-if="passwordChangeError" class="text-xs font-medium text-rose-500">
              {{ passwordChangeError }}
            </p>
          </div>

        </div>

        <!-- Modal Footer Actions -->
        <div class="flex space-x-2 pt-3 border-t border-slate-100 dark:border-[#2d3035]">
          <button 
            @click="showEditProfileModal = false" 
            type="button" 
            class="flex-1 py-2.5 bg-slate-100 dark:bg-[#2d2f31] font-medium text-xs rounded-full text-slate-700 dark:text-neutral-300 min-h-[48px] cursor-pointer hover:bg-slate-200 dark:hover:bg-[#383a3d] transition-colors"
          >
            Close
          </button>
          <button 
            @click="handleUpdateProfile" 
            :disabled="isUpdatingProfile" 
            type="button" 
            class="flex-1 py-2.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-neutral-100 font-medium text-xs text-white dark:text-slate-900 rounded-full shadow-xs min-h-[48px] cursor-pointer transition-colors"
          >
            {{ isUpdatingProfile ? 'Saving...' : 'Save Settings' }}
          </button>
        </div>

      </div>
    </div>

    <!-- SIGN OUT CONFIRMATION MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showSignOutModal" class="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-[#2d3035] rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-xl text-center">
        <div class="w-12 h-12 rounded-full bg-slate-100 dark:bg-[#2d2f31] flex items-center justify-center mx-auto text-slate-700 dark:text-neutral-300">
          <LogOut class="w-5 h-5" />
        </div>
        <div class="space-y-1">
          <h3 class="font-bold text-base text-slate-900 dark:text-neutral-100">Sign Out of SmartBand?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 font-normal">Are you sure you want to sign out? You will need to log back in to access event schedules and receive operational alarms.</p>
        </div>
        <div class="grid grid-cols-2 gap-3 pt-2">
          <button 
            @click="showSignOutModal = false" 
            type="button" 
            class="py-2.5 px-4 bg-slate-100 hover:bg-slate-200 dark:bg-[#2d2f31] dark:hover:bg-[#383a3d] text-slate-700 dark:text-neutral-200 font-medium text-xs rounded-full min-h-[48px] cursor-pointer transition-colors"
          >
            Cancel
          </button>
          <button 
            @click="handleSignOut" 
            type="button" 
            class="py-2.5 px-4 bg-rose-600 hover:bg-rose-500 text-white font-medium text-xs rounded-full shadow-xs min-h-[48px] cursor-pointer transition-colors"
          >
            Sign Out
          </button>
        </div>
      </div>
    </div>

  </div>
</template>
