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
  <div class="space-y-6 max-w-[1200px] mx-auto">
    
    <!-- Top Header (M3 Headline & Action Buttons) -->
    <header class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pt-1 border-b border-[var(--md-outline-variant)]/30 pb-4">
      <div>
        <p class="text-xs font-medium text-[var(--md-on-surface-variant)]">Account Management</p>
        <h1 class="text-2xl sm:text-3xl font-bold text-[var(--md-on-surface)] tracking-tight">My Profile</h1>
      </div>
      <div class="flex flex-wrap items-center gap-2 w-full sm:w-auto">
        <button 
          @click="openEditProfile('profile')"
          type="button"
          class="m3-btn-tonal flex-1 sm:flex-initial min-h-[40px] text-xs font-semibold px-4 cursor-pointer flex items-center justify-center"
        >
          <Settings class="w-4 h-4 mr-1.5 text-[var(--md-on-surface-variant)]" /> Profile Settings
        </button>
        <button 
          @click="triggerSignOut"
          type="button"
          class="m3-btn-outlined border-[var(--md-error)]/40 text-[var(--md-error)] hover:bg-[var(--md-error-container)]/20 flex-1 sm:flex-initial min-h-[40px] text-xs font-semibold px-4 cursor-pointer flex items-center justify-center"
          aria-label="Sign Out of Account"
        >
          <LogOut class="w-4 h-4 mr-1.5" /> Sign Out
        </button>
      </div>
    </header>

    <!-- Profile Info Card (Official M3 Elevated Card) -->
    <section class="m3-card-elevated p-4 sm:p-6 border border-[var(--md-outline-variant)]/40 rounded-2xl space-y-4">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div class="flex items-center space-x-3.5 min-w-0 flex-1">
          
          <!-- Avatar with Upload Indicator (Keyboard Accessible via label & focusable file input) -->
          <label 
            class="relative w-16 h-16 sm:w-18 sm:h-18 flex-shrink-0 group cursor-pointer rounded-full block focus-within:ring-2 focus-within:ring-amber-500 focus-within:ring-offset-2"
            title="Upload new profile picture"
          >
            <input 
              type="file" 
              accept="image/jpeg, image/png, image/webp" 
              @change="handleFileUpload" 
              class="sr-only" 
              ref="fileInput" 
              aria-label="Upload profile photo"
            />
            
            <template v-if="store.profile?.profile_picture && !imgLoadError">
              <img :src="store.profile.profile_picture" @error="imgLoadError = true" alt="Avatar" width="72" height="72" class="w-full h-full object-cover rounded-full border-2 border-[var(--md-outline-variant)] shadow-xs" />
              <div v-if="store.profile.profile_picture_status === 'pending'" class="absolute -bottom-1 -right-1 bg-amber-500 text-white text-[9px] font-bold px-1.5 py-0.5 rounded-full border-2 border-[var(--md-surface)] uppercase">Pending</div>
              <div v-else-if="store.profile.profile_picture_status === 'declined'" class="absolute -bottom-1 -right-1 bg-rose-500 text-white text-[9px] font-bold px-1.5 py-0.5 rounded-full border-2 border-[var(--md-surface)] uppercase">Declined</div>
              <div v-else-if="store.profile.profile_picture_status === 'approved'" class="absolute -bottom-1 -right-1 bg-emerald-600 text-white p-0.5 rounded-full border-2 border-[var(--md-surface)]" title="Approved">
                <Check class="w-3.5 h-3.5 stroke-[2.5]" />
              </div>
            </template>
            <template v-else>
              <div class="w-full h-full rounded-full bg-[var(--md-primary)] text-[var(--md-on-primary)] flex items-center justify-center text-lg sm:text-xl font-bold shadow-xs">
                {{ store.profile?.full_name ? store.profile.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB' }}
              </div>
            </template>
            
            <!-- Hover Overlay -->
            <div class="absolute inset-0 bg-black/40 rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
               <Camera v-if="!isUploading" class="w-5 h-5 text-white" />
               <Loader2 v-else class="w-5 h-5 text-white animate-spin" />
            </div>
          </label>

          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-1.5">
              <h2 class="text-lg sm:text-xl font-bold text-[var(--md-on-surface)] leading-tight">
                {{ store.profile?.full_name || 'Member' }}
              </h2>
              <span v-if="store.profile?.is_verified" class="m3-chip m3-chip-info h-6 px-2.5 text-xs font-semibold">
                Verified Musician
              </span>
              <span v-else class="m3-chip m3-chip-rsvp h-6 px-2.5 text-xs font-semibold">
                Pending Verification
              </span>
            </div>

            <div class="text-xs font-medium text-[var(--md-on-surface-variant)] mt-1.5 flex flex-wrap items-center gap-1.5 capitalize">
              <span class="flex items-center">
                <Music class="w-3.5 h-3.5 mr-1 text-[var(--md-outline)] shrink-0" />
                {{ store.profile?.instrument || 'Musician' }}
              </span>
              <span>•</span>
              <span class="m3-chip m3-chip-assist h-6 px-2.5 text-xs">{{ store.profile?.rank || 'Junior' }} Rank</span>
            </div>
          </div>
        </div>

        <button 
          @click="openEditProfile('profile')"
          type="button"
          class="m3-btn-tonal text-xs px-4 min-h-[40px] flex items-center justify-center self-start sm:self-center shrink-0 cursor-pointer"
          aria-label="Edit Profile Details"
          title="Edit Profile Settings"
        >
          <Edit3 class="w-3.5 h-3.5 mr-1.5" />
          <span>Edit Details</span>
        </button>
      </div>

      <!-- Quick Metadata Grid (WCAG High-Contrast Surface) -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5 pt-2 border-t border-[var(--md-outline-variant)]/30">
        <div class="flex items-center text-xs text-[var(--md-on-surface-variant)] bg-[var(--md-surface-container-low)] p-3 rounded-2xl border border-[var(--md-outline-variant)]/30 font-medium">
          <Phone class="w-4 h-4 mr-2.5 text-[var(--md-outline)] flex-shrink-0" />
          <span>{{ store.profile?.contact_number || store.profile?.email || 'No contact specified' }}</span>
        </div>
        <div class="flex items-center text-xs text-[var(--md-on-surface-variant)] bg-[var(--md-surface-container-low)] p-3 rounded-2xl border border-[var(--md-outline-variant)]/30 font-medium">
          <Activity class="w-4 h-4 mr-2.5 text-[var(--md-outline)] flex-shrink-0" />
          <span>Reliability: <strong class="text-[var(--md-on-surface)]">{{ store.profile?.reliability_score || 100 }}%</strong></span>
        </div>
      </div>
    </section>

    <!-- Dynamic Weekly Availability Grid with Exact Dates (M3 Outlined Card) -->
    <section class="space-y-3">
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 px-1">
        <div>
          <h2 class="text-xs font-semibold text-[var(--md-on-surface-variant)] uppercase tracking-wider flex items-center">
            <Calendar class="w-3.5 h-3.5 mr-1.5 text-[var(--md-outline)]" /> Weekly Schedule Availability
          </h2>
          <p class="text-[11px] text-[var(--md-on-surface-variant)] mt-0.5">Toggle slots when you are available for band rehearsals, parades, and gigs.</p>
        </div>
        <button 
          @click="saveAvailability" 
          :disabled="isSaving"
          class="m3-btn-filled w-full sm:w-auto min-h-[40px] px-5 text-xs font-semibold cursor-pointer shrink-0"
        >
          <CheckCircle2 v-if="saveSuccess" class="w-4 h-4 mr-1.5" />
          {{ isSaving ? 'Saving...' : saveSuccess ? 'Saved ✓' : 'Save Availability' }}
        </button>
      </div>

      <!-- MOBILE VIEW: STACKED DAY CARDS (Hidden on Tablet/Desktop) -->
      <div class="block md:hidden space-y-2.5">
        <div 
          v-for="d in weekDays" 
          :key="d.key" 
          class="p-3.5 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 space-y-2"
        >
          <div class="flex items-center justify-between">
            <span class="font-bold text-xs text-[var(--md-on-surface)] uppercase tracking-wide">{{ d.name }}</span>
            <span class="text-[11px] text-[var(--md-on-surface-variant)]">{{ d.dateLabel }}</span>
          </div>

          <div class="grid grid-cols-3 gap-2">
            <button 
              v-for="slot in timeSlots" 
              :key="slot"
              @click="toggleSlot(d.key, slot)"
              type="button"
              :aria-label="`Toggle ${d.name} ${slot}`"
              class="py-2.5 px-1 rounded-xl font-semibold text-xs transition-all cursor-pointer min-h-[44px] flex flex-col items-center justify-center border"
              :class="isSlotFree(d.key, slot) 
                ? 'bg-[var(--md-primary)] text-[var(--md-on-primary)] border-transparent shadow-xs' 
                : 'bg-[var(--md-surface)] text-[var(--md-on-surface-variant)] border-[var(--md-outline-variant)]/40 hover:bg-[var(--md-surface-container-high)]'"
            >
              <span class="text-[10px] font-medium opacity-80 leading-none mb-1">{{ slot.split(' ')[0] }}</span>
              <div class="flex items-center gap-1 leading-none">
                <Check v-if="isSlotFree(d.key, slot)" class="w-3 h-3 stroke-[3]" />
                <span class="text-[11px]">{{ isSlotFree(d.key, slot) ? 'FREE' : '—' }}</span>
              </div>
            </button>
          </div>
        </div>
      </div>

      <!-- DESKTOP VIEW: FULL WEEKLY MATRIX TABLE (Hidden on Mobile) -->
      <div class="hidden md:block m3-card-outlined rounded-2xl p-5 border border-[var(--md-outline-variant)]/40 overflow-x-auto">
        <table class="w-full text-center border-collapse">
          <thead>
            <tr>
              <th class="p-2.5 text-left text-[11px] font-semibold text-[var(--md-on-surface-variant)] uppercase tracking-wider">Time Slot</th>
              <th v-for="d in weekDays" :key="d.key" class="p-2 text-[11px] font-semibold text-[var(--md-on-surface)]">
                <div class="uppercase">{{ d.name }}</div>
                <div class="text-[9px] font-normal text-[var(--md-on-surface-variant)] lowercase">{{ d.dateLabel }}</div>
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[var(--md-outline-variant)]/20">
            <tr v-for="slot in timeSlots" :key="slot">
              <td class="p-2.5 text-left text-xs font-medium text-[var(--md-on-surface-variant)] whitespace-nowrap">
                <Clock class="w-3.5 h-3.5 inline mr-1 text-[var(--md-outline)]" />
                {{ slot.split(' ')[0] }}
              </td>
              <td v-for="d in weekDays" :key="d.key" class="p-1">
                <button 
                  @click="toggleSlot(d.key, slot)"
                  type="button"
                  :aria-label="`Toggle ${d.name} ${slot}`"
                  class="w-full py-2.5 rounded-full font-semibold text-xs transition-colors cursor-pointer min-h-[44px] flex items-center justify-center gap-1 border"
                  :class="isSlotFree(d.key, slot) 
                    ? 'bg-[var(--md-primary)] text-[var(--md-on-primary)] border-transparent shadow-2xs' 
                    : 'bg-[var(--md-surface-container)] text-[var(--md-on-surface-variant)] border-transparent hover:bg-[var(--md-surface-container-high)]'"
                >
                  <Check v-if="isSlotFree(d.key, slot)" class="w-3.5 h-3.5 stroke-[3]" />
                  <span>{{ isSlotFree(d.key, slot) ? 'FREE' : '—' }}</span>
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- COMPLETE POP-UP SETTINGS MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showEditProfileModal" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="settings-modal-title"
      @keydown.escape="showEditProfileModal = false"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-3 sm:p-4"
    >
      <div class="m3-surface-modal bg-[var(--md-surface-container-high)] text-[var(--md-on-surface)] border border-[var(--md-outline-variant)]/60 rounded-[28px] p-5 sm:p-6 max-w-lg w-full space-y-4 shadow-xl text-left max-h-[88vh] flex flex-col">
        
        <!-- Modal Header -->
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/30 pb-3">
          <div class="flex items-center space-x-2">
            <Settings class="w-5 h-5 text-[var(--md-on-surface-variant)]" />
            <h3 id="settings-modal-title" class="font-bold text-base text-[var(--md-on-surface)]">Profile & Settings</h3>
          </div>
          <button @click="showEditProfileModal = false" class="min-w-[48px] min-h-[48px] rounded-full text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container)] transition-colors flex items-center justify-center cursor-pointer" aria-label="Close modal">
            <X class="w-5 h-5" />
          </button>
        </div>

        <!-- Setting Navigation Tabs (Official M3 Segmented Button - Non-Wrapping Grid) -->
        <div class="grid grid-cols-3 p-1 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 text-xs font-medium w-full">
          <button 
            type="button" 
            @click="activeSettingsTab = 'profile'"
            class="py-2.5 px-1 rounded-xl transition-all cursor-pointer text-center min-h-[40px] flex items-center justify-center"
            :class="activeSettingsTab === 'profile' 
              ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
              : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Profile
          </button>
          <button 
            type="button" 
            @click="activeSettingsTab = 'availability'"
            class="py-2.5 px-1 rounded-xl transition-all cursor-pointer text-center min-h-[40px] flex items-center justify-center"
            :class="activeSettingsTab === 'availability' 
              ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
              : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Availability
          </button>
          <button 
            type="button" 
            @click="activeSettingsTab = 'security'"
            class="py-2.5 px-1 rounded-xl transition-all cursor-pointer text-center min-h-[40px] flex items-center justify-center"
            :class="activeSettingsTab === 'security' 
              ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
              : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
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
              <label for="profile-edit-name" class="text-xs font-medium text-[var(--md-on-surface)]">Full Name</label>
              <input 
                id="profile-edit-name"
                v-model="editFullName" 
                type="text" 
                class="w-full px-4 py-3 bg-[var(--md-surface-container-lowest)] border border-[var(--md-outline-variant)] rounded-2xl text-xs font-medium text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-primary)]"
              >
            </div>

            <!-- Primary Instrument -->
            <div class="space-y-1.5 text-left">
              <label for="profile-edit-primary-inst" class="text-xs font-medium text-[var(--md-on-surface)]">Primary Instrument</label>
              <select 
                id="profile-edit-primary-inst"
                v-model="editPrimaryInstrument" 
                class="w-full px-4 py-3 bg-[var(--md-surface-container-lowest)] border border-[var(--md-outline-variant)] rounded-2xl text-xs font-medium text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-primary)] cursor-pointer"
              >
                <option v-for="inst in instrumentList" :key="inst" :value="inst">{{ inst }}</option>
              </select>
            </div>

            <!-- Secondary Instrument -->
            <div class="space-y-1.5 text-left">
              <label for="profile-edit-secondary-inst" class="text-xs font-medium text-[var(--md-on-surface)]">Secondary Instrument (Optional)</label>
              <select 
                id="profile-edit-secondary-inst"
                v-model="editSecondaryInstrument" 
                class="w-full px-4 py-3 bg-[var(--md-surface-container-lowest)] border border-[var(--md-outline-variant)] rounded-2xl text-xs font-medium text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-primary)] cursor-pointer"
              >
                <option value="None / N/A">None / N/A</option>
                <option v-for="inst in instrumentList" :key="inst" :value="inst">{{ inst }}</option>
              </select>
            </div>

            <!-- Philippine Mobile Phone Number -->
            <div class="space-y-1.5 text-left">
              <div class="flex justify-between items-center">
                <label for="profile-edit-phone" class="text-xs font-medium text-[var(--md-on-surface)]">Mobile Phone Number</label>
                <span class="text-[10px] font-medium" :class="editContactNumber.length === 11 && editContactNumber.startsWith('09') ? 'text-emerald-600 dark:text-emerald-400' : 'text-[var(--md-on-surface-variant)]'">
                  {{ editContactNumber.length }}/11 digits
                </span>
              </div>
              <input 
                id="profile-edit-phone"
                :value="editContactNumber" 
                @input="handlePhoneEditInput" 
                type="tel" 
                maxlength="11"
                placeholder="09XXXXXXXXX"
                class="w-full px-4 py-3 bg-[var(--md-surface-container-lowest)] border rounded-2xl text-xs font-medium text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-primary)]"
                :class="!isEditPhoneValid ? 'border-[var(--md-error)]' : 'border-[var(--md-outline-variant)]'"
              >
              <p class="text-[10px] text-[var(--md-on-surface-variant)]">Format: 11-digit Philippine mobile number starting with 09.</p>
            </div>
          </div>

          <!-- TAB 2: AVAILABILITY GRID (Settings Pop-up integration) -->
          <div v-else-if="activeSettingsTab === 'availability'" class="space-y-3">
            <div class="p-3.5 rounded-2xl bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)]/30 text-xs text-[var(--md-on-surface-variant)]">
              <p class="font-semibold text-[var(--md-on-surface)]">Weekly Schedule Availability</p>
              <p class="text-[11px] mt-0.5">Toggle slots between FREE and busy. The Band Secretary uses this grid to schedule gigs and check musician availability.</p>
            </div>

            <div class="rounded-2xl border border-[var(--md-outline-variant)]/40 overflow-x-auto bg-[var(--md-surface-container-low)]">
              <table class="w-full text-center border-collapse text-xs">
                <thead class="bg-[var(--md-surface-container)] border-b border-[var(--md-outline-variant)]/30">
                  <tr>
                    <th class="p-2.5 text-left text-[10px] font-semibold text-[var(--md-on-surface-variant)] uppercase">Slot</th>
                    <th v-for="d in weekDays" :key="d.key" class="p-2.5 text-[10px] font-semibold text-[var(--md-on-surface)]">
                      {{ d.name }}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-[var(--md-outline-variant)]/20">
                  <tr v-for="slot in timeSlots" :key="slot">
                    <td class="p-2.5 text-left font-medium text-[var(--md-on-surface-variant)] text-[11px] whitespace-nowrap">
                      {{ slot.split(' ')[0] }}
                    </td>
                    <td v-for="d in weekDays" :key="d.key" class="p-1">
                      <button 
                        @click="toggleSlot(d.key, slot)"
                        type="button"
                        class="w-full py-2.5 rounded-full font-semibold text-[11px] transition-colors cursor-pointer min-h-[40px] flex items-center justify-center gap-0.5"
                        :class="isSlotFree(d.key, slot) 
                          ? 'bg-[var(--md-primary)] text-[var(--md-on-primary)] shadow-2xs' 
                          : 'bg-[var(--md-surface-container-high)] text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-highest)]'"
                      >
                        <Check v-if="isSlotFree(d.key, slot)" class="w-3 h-3 stroke-[3]" />
                        <span>{{ isSlotFree(d.key, slot) ? 'FREE' : '—' }}</span>
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
              class="m3-btn-filled w-full min-h-[48px] text-xs font-semibold cursor-pointer"
            >
              <CheckCircle2 v-if="saveSuccess" class="w-4 h-4 mr-1.5" />
              {{ isSaving ? 'Saving Grid...' : saveSuccess ? 'Saved ✓' : 'Save Availability Grid' }}
            </button>
          </div>

          <!-- TAB 3: PASSWORD CHANGE -->
          <div v-else-if="activeSettingsTab === 'security'" class="space-y-4">
            <div class="space-y-1.5">
              <label class="text-xs font-medium text-[var(--md-on-surface)]">New Password</label>
              <div class="relative">
                <input 
                  v-model="newPassword" 
                  :type="showNewPass ? 'text' : 'password'" 
                  placeholder="At least 8 characters"
                  class="w-full px-4 py-3 pr-12 bg-[var(--md-surface-container-lowest)] border border-[var(--md-outline-variant)] rounded-2xl text-xs font-medium text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-primary)]"
                >
                <button type="button" @click="showNewPass = !showNewPass" class="absolute inset-y-0 right-0 pr-3 flex items-center text-[var(--md-on-surface-variant)] min-w-[48px] justify-center cursor-pointer">
                  <Eye v-if="!showNewPass" class="w-4 h-4" />
                  <EyeOff v-else class="w-4 h-4" />
                </button>
              </div>
            </div>

            <div class="space-y-1.5">
              <label class="text-xs font-medium text-[var(--md-on-surface)]">Confirm New Password</label>
              <div class="relative">
                <input 
                  v-model="confirmPassword" 
                  :type="showConfirmPass ? 'text' : 'password'" 
                  placeholder="Re-type new password"
                  class="w-full px-4 py-3 pr-12 bg-[var(--md-surface-container-lowest)] border border-[var(--md-outline-variant)] rounded-2xl text-xs font-medium text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-primary)]"
                >
                <button type="button" @click="showConfirmPass = !showConfirmPass" class="absolute inset-y-0 right-0 pr-3 flex items-center text-[var(--md-on-surface-variant)] min-w-[48px] justify-center cursor-pointer">
                  <Eye v-if="!showConfirmPass" class="w-4 h-4" />
                  <EyeOff v-else class="w-4 h-4" />
                </button>
              </div>
            </div>

            <p v-if="newPassword && newPassword === confirmPassword" class="text-xs font-medium text-emerald-600 dark:text-emerald-400">
              ✓ Passwords match
            </p>
            <p v-if="passwordChangeError" class="text-xs font-medium text-[var(--md-error)]">
              {{ passwordChangeError }}
            </p>
          </div>

        </div>

        <!-- Modal Footer Actions -->
        <div class="flex space-x-2 pt-3 border-t border-[var(--md-outline-variant)]/30">
          <button 
            @click="showEditProfileModal = false" 
            type="button" 
            class="m3-btn-tonal flex-1 min-h-[48px] text-xs font-semibold cursor-pointer"
          >
            Close
          </button>
          <button 
            @click="handleUpdateProfile" 
            :disabled="isUpdatingProfile" 
            type="button" 
            class="m3-btn-filled flex-1 min-h-[48px] text-xs font-semibold cursor-pointer"
          >
            {{ isUpdatingProfile ? 'Saving...' : 'Save Settings' }}
          </button>
        </div>

      </div>
    </div>

    <!-- SIGN OUT CONFIRMATION MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showSignOutModal" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="signout-modal-title"
      @keydown.escape="showSignOutModal = false"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4"
    >
      <div class="m3-surface-modal bg-[var(--md-surface-container-high)] text-[var(--md-on-surface)] border border-[var(--md-outline-variant)]/60 rounded-[28px] p-6 max-w-sm w-full space-y-4 shadow-xl text-center">
        <div class="w-12 h-12 rounded-full bg-[var(--md-surface-container)] flex items-center justify-center mx-auto text-[var(--md-on-surface)]">
          <LogOut class="w-5 h-5 text-[var(--md-error)]" />
        </div>
        <div class="space-y-1">
          <h3 id="signout-modal-title" class="font-bold text-base text-[var(--md-on-surface)]">Sign Out of SmartBand?</h3>
          <p class="text-xs text-[var(--md-on-surface-variant)] font-normal">Are you sure you want to sign out? You will need to log back in to access event schedules and receive operational alarms.</p>
        </div>
        <div class="grid grid-cols-2 gap-3 pt-2">
          <button 
            @click="showSignOutModal = false" 
            type="button" 
            class="m3-btn-tonal min-h-[48px] text-xs font-semibold cursor-pointer"
          >
            Cancel
          </button>
          <button 
            @click="handleSignOut" 
            type="button" 
            class="m3-btn-filled bg-[var(--md-error)] text-white hover:bg-rose-700 min-h-[48px] text-xs font-semibold cursor-pointer"
          >
            Sign Out
          </button>
        </div>
      </div>
    </div>

  </div>
</template>
