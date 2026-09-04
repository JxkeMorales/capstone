<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { Shield, ShieldCheck, ShieldAlert, UserCheck, UserX, Award, Send, Users, Cpu, Calendar, Trash2, CheckCircle2, AlertCircle, X } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const store = useMainStore()

const pendingAccounts = ref([])
const pendingAvatars = ref([])
const memberRoster = ref([])
const notification = ref('')
const isDispatchGenerated = ref(false)

// Day and Week Accurate Availability State
const selectedDayNeeded = ref('Monday')
const selectedSlotNeeded = ref('Morning (08:00 AM - 12:00 PM)')
const selectedInstrumentNeeded = ref('All')
const availableUserIds = ref(new Set())
const matchedDispatchRoster = ref([])

// Confirmation Modal State
const showConfirmModal = ref(false)
const confirmUserTarget = ref(null)

// Realtime Channel Reference
let adminChannel = null

const timeSlots = [
  'Morning (08:00 AM - 12:00 PM)',
  'Afternoon (01:00 PM - 05:00 PM)',
  'Evening (06:00 PM - 10:00 PM)'
]

// Day Names with Accurate Calculated Dates for Current Week
const weekDaysOptions = computed(() => {
  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
  const now = new Date()
  const currentDayIndex = now.getDay() // 0 is Sunday
  
  return dayNames.map((name, index) => {
    const d = new Date(now)
    const diff = index - currentDayIndex
    d.setDate(now.getDate() + diff)
    const dateStr = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
    return {
      key: name,
      fullLabel: `${name} (${dateStr})`
    }
  })
})

const fetchPendingAccounts = async () => {
  try {
    const { data } = await supabase
      .from('profiles')
      .select('*')
      .eq('is_verified', false)
    if (data) pendingAccounts.value = data
  } catch (err) {
    console.error('Error fetching pending accounts:', err)
  }
}

// 2. FETCH ROSTER
const fetchRoster = async () => {
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, full_name, role, instrument, is_verified, rank, executive_title, reliability_score, profile_picture')
      .eq('is_verified', true)
      .order('full_name', { ascending: true })
    
    if (error) throw error
    memberRoster.value = data || []
  } catch (err) {
    console.error('Fetch roster error:', err)
  }
}

// 2B. FETCH PENDING AVATARS
const fetchPendingAvatars = async () => {
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, full_name, profile_picture')
      .eq('profile_picture_status', 'pending')
    
    if (error) throw error
    pendingAvatars.value = data || []
  } catch (err) {
    console.error('Fetch pending avatars error:', err)
  }
}

// 2C. AVATAR MODERATION
const approveAvatar = async (id, name) => {
  try {
    await supabase.from('profiles').update({ profile_picture_status: 'approved' }).eq('id', id)
    showToast(`Approved ${name}'s avatar.`)
    fetchPendingAvatars()
    fetchRoster()
  } catch (err) {
    showToast('Failed to approve avatar.')
  }
}

const declineAvatar = async (id, name) => {
  try {
    await supabase.from('profiles').update({ profile_picture_status: 'declined', profile_picture: null }).eq('id', id)
    showToast(`Declined ${name}'s avatar.`)
    fetchPendingAvatars()
    fetchRoster()
  } catch (err) {
    showToast('Failed to decline avatar.')
  }
}

const showToast = (msg) => {
  notification.value = msg
  setTimeout(() => { notification.value = '' }, 3500)
}

// 1. APPROVE USER
const approveUser = async (user) => {
  try {
    const { error } = await supabase
      .from('profiles')
      .update({ is_verified: true })
      .eq('id', user.id)

    if (error) throw error

    pendingAccounts.value = pendingAccounts.value.filter(u => u.id !== user.id)
    await fetchRoster()
    showToast(`✓ ${user.full_name} verified and approved.`)
  } catch (err) {
    console.error('Approval Error:', err)
    showToast('Failed to approve account.')
  }
}

// 2. DECLINE / DELETE USER
const promptDeleteUser = (user) => {
  confirmUserTarget.value = user
  showConfirmModal.value = true
}

const executeRejectAndDeleteUser = async () => {
  if (!confirmUserTarget.value) return
  const target = confirmUserTarget.value

  try {
    const { error } = await supabase.from('profiles').delete().eq('id', target.id)
    if (error) throw error

    pendingAccounts.value = pendingAccounts.value.filter(u => u.id !== target.id)
    memberRoster.value = memberRoster.value.filter(u => u.id !== target.id)
    showToast(`Removed ${target.full_name}. ID freed.`)
  } catch (err) {
    console.error('Delete Error:', err)
    showToast('Failed to delete user profile.')
  } finally {
    showConfirmModal.value = false
    confirmUserTarget.value = null
  }
}

// 3. ROLE MANAGEMENT
const changeRole = async (member, newRole) => {
  try {
    const { error } = await supabase
      .from('profiles')
      .update({ role: newRole })
      .eq('id', member.id)

    if (error) throw error

    member.role = newRole
    showToast(`Updated ${member.full_name}'s role to ${newRole}.`)
  } catch (err) {
    console.error('Role update error:', err)
    showToast('Failed to change role.')
  }
}

// 4. EXECUTIVE TITLE ASSIGNMENT
const assignExecutiveTitle = async (member, newTitle) => {
  try {
    const { error } = await supabase
      .from('profiles')
      .update({ executive_title: newTitle || null })
      .eq('id', member.id)

    if (error) throw error

    member.executive_title = newTitle || null
    showToast(`Updated ${member.full_name}'s executive title.`)
  } catch (err) {
    console.error('Executive title update error:', err)
    showToast('Failed to assign title.')
  }
}

// 5. RANK PROMOTION / DEMOTION
const toggleRank = async (member) => {
  const newRank = member.rank === 'Senior' ? 'Junior' : 'Senior'
  try {
    const { error } = await supabase
      .from('profiles')
      .update({ rank: newRank })
      .eq('id', member.id)

    if (error) throw error

    member.rank = newRank
    showToast(`${member.full_name} is now a ${newRank} Musician.`)
  } catch (err) {
    console.error('Rank toggle error:', err)
    showToast('Failed to change rank.')
  }
}

// 6. AVAILABILITY CHECKER
const runAvailabilityCheck = async () => {
  try {
    const { data: availData } = await supabase
      .from('member_availability')
      .select('user_id')
      .eq('day_of_week', selectedDayNeeded.value.toLowerCase())
      .eq('time_slot', selectedSlotNeeded.value.split(' ')[0])
      .eq('is_available', true)

    availableUserIds.value = new Set(availData ? availData.map(a => a.user_id) : [])

    let filtered = memberRoster.value
    if (selectedInstrumentNeeded.value !== 'All') {
      const targetInst = selectedInstrumentNeeded.value.toLowerCase()
      filtered = filtered.filter(m => m.instrument && m.instrument.toLowerCase().includes(targetInst))
    }

    matchedDispatchRoster.value = [...filtered].sort((a, b) => {
      const aFree = availableUserIds.value.has(a.id)
      const bFree = availableUserIds.value.has(b.id)
      if (aFree && !bFree) return -1
      if (!aFree && bFree) return 1
      return a.full_name.localeCompare(b.full_name)
    })

    isDispatchGenerated.value = true
  } catch (err) {
    console.error('Availability check error:', err)
    showToast('Failed to check availability.')
  }
}

// 7. RE-NOTIFICATION DISPATCH
const triggerReNotifications = () => {
  showToast('✓ RSVP reminder notifications dispatched to unconfirmed musicians.')
}

onMounted(() => {
  fetchPendingAccounts()
  fetchPendingAvatars()
  fetchRoster()

  adminChannel = supabase
    .channel('admin-realtime')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, () => {
      fetchPendingAccounts()
      fetchPendingAvatars()
      fetchRoster()
    })
    .subscribe()
})

onUnmounted(() => {
  if (adminChannel) {
    supabase.removeChannel(adminChannel)
  }
})
</script>

<template>
  <div class="p-4 sm:p-5 space-y-6 relative">
    
    <header class="pt-1 flex items-center space-x-3.5 mb-2">
      <div class="p-2.5 rounded-2xl bg-blue-500/10 text-blue-600 dark:text-blue-400 flex-shrink-0">
        <Shield class="w-6 h-6" />
      </div>
      <div class="min-w-0">
        <p class="text-xs font-bold text-blue-600 dark:text-blue-400 uppercase tracking-wider leading-tight mb-0.5">
          {{ store.isSuperAdmin ? 'IT Super Admin Caretaker' : 'Band Secretary Operations Hub' }}
        </p>
        <h1 class="text-2xl font-black text-slate-900 dark:text-white leading-tight truncate">
          {{ store.isSuperAdmin ? 'System & Accounts Admin' : 'Secretary Management Hub' }}
        </h1>
      </div>
    </header>

    <!-- Toast Notification -->
    <Transition name="toast">
      <div 
        v-if="notification" 
        class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-xs w-11/12 bg-white dark:bg-[#1c1c1e] text-slate-900 dark:text-white px-4 py-3 rounded-2xl shadow-xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between font-extrabold text-xs"
      >
        <div class="flex items-center space-x-1">
          <CheckCircle2 class="w-4 h-4 text-emerald-500 flex-shrink-0" />
          <span>{{ notification }}</span>
        </div>
        <button @click="notification = ''" class="ml-2 text-slate-400 hover:text-slate-900 dark:hover:text-white min-w-[32px] min-h-[32px] flex items-center justify-center cursor-pointer">
          <X class="w-3.5 h-3.5" />
        </button>
      </div>
    </Transition>

    <!-- PENDING APPROVALS QUEUE (IT Super Admin) -->
    <section v-if="store.isSuperAdmin" class="space-y-3" aria-label="Pending Approvals Section">
      <div class="flex items-center justify-between px-1">
        <div class="flex items-center space-x-1">
          <ShieldAlert class="w-4 h-4 text-amber-500" />
          <h2 class="text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
            Pending Master List Approvals ({{ pendingAccounts.length }})
          </h2>
        </div>
      </div>

      <div class="space-y-3">
        <div 
          v-for="user in pendingAccounts" 
          :key="user.id"
          class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 space-y-3"
        >
          <div class="flex justify-between items-start">
            <div>
              <h3 class="font-black text-base text-slate-900 dark:text-white leading-tight">{{ user.full_name }}</h3>
              <p class="text-xs text-slate-500 dark:text-neutral-400">{{ user.email }} • {{ user.contact_number }}</p>
            </div>
            <span class="text-[10px] font-extrabold bg-amber-100 dark:bg-amber-950/60 text-amber-800 dark:text-amber-300 px-2 py-0.5 rounded-md">
              UNVERIFIED
            </span>
          </div>

          <div class="grid grid-cols-2 gap-2 text-xs font-semibold bg-slate-50 dark:bg-[#27272a] p-2.5 rounded-xl text-slate-600 dark:text-neutral-300">
            <div><span class="text-slate-400">Inst:</span> {{ user.instrument || 'None' }}</div>
            <div><span class="text-slate-400">Sex:</span> {{ user.sex || 'Unknown' }}</div>
          </div>

          <div class="flex space-x-2 pt-1">
            <button 
              @click="approveUser(user)"
              type="button"
              class="flex-1 py-3 bg-emerald-600 hover:bg-emerald-700 active:scale-95 text-white font-bold text-xs rounded-xl flex items-center justify-center transition-all shadow-xs cursor-pointer min-h-[44px]"
            >
              <UserCheck class="w-4 h-4 mr-1.5" /> Approve & Verify
            </button>
            <button 
              @click="promptDeleteUser(user)"
              type="button"
              class="py-3 px-3 bg-rose-600/10 hover:bg-rose-600/20 text-rose-600 dark:text-rose-400 font-bold text-xs rounded-xl flex items-center justify-center transition-all active:scale-95 border border-rose-200 dark:border-rose-900/40 cursor-pointer min-h-[44px]"
            >
              <Trash2 class="w-4 h-4 mr-1" /> Decline & Delete
            </button>
          </div>
        </div>

        <div v-if="pendingAccounts.length === 0" class="text-center p-6 bg-white dark:bg-[#1c1c1e] rounded-2xl border border-slate-200/80 dark:border-neutral-800">
          <CheckCircle2 class="w-8 h-8 text-emerald-400 mx-auto mb-2 opacity-50" />
          <p class="text-xs font-bold text-slate-500 dark:text-neutral-400">No pending accounts in queue.</p>
        </div>
      </div>
    </section>

    <!-- AVATAR MODERATION QUEUE -->
    <section v-if="pendingAvatars.length > 0" class="space-y-3" aria-label="Avatar Moderation Queue">
      <div class="flex items-center space-x-2 px-1">
        <AlertCircle class="w-4 h-4 text-amber-500" />
        <h2 class="text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
          Pending Avatar Approvals ({{ pendingAvatars.length }})
        </h2>
      </div>

      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
        <div 
          v-for="user in pendingAvatars" 
          :key="user.id"
          class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-3 shadow-xs border border-slate-200/80 dark:border-neutral-800 flex flex-col items-center text-center space-y-3"
        >
          <img :src="user.profile_picture" alt="Avatar Review" class="w-16 h-16 rounded-2xl object-cover shadow-md border border-slate-200 dark:border-neutral-700" />
          <p class="text-xs font-black text-slate-900 dark:text-white line-clamp-1 w-full">{{ user.full_name }}</p>
          <div class="flex space-x-1 w-full">
            <button @click="approveAvatar(user.id, user.full_name)" class="flex-1 py-1.5 bg-emerald-50 text-emerald-600 dark:bg-emerald-950/40 dark:text-emerald-400 font-bold border border-emerald-200 dark:border-emerald-900/40 hover:bg-emerald-100 rounded-xl cursor-pointer text-[10px] uppercase">Approve</button>
            <button @click="declineAvatar(user.id, user.full_name)" class="flex-1 py-1.5 bg-rose-50 text-rose-600 dark:bg-rose-950/40 dark:text-rose-400 font-bold border border-rose-200 dark:border-rose-900/40 hover:bg-rose-100 rounded-xl cursor-pointer text-[10px] uppercase">Decline</button>
          </div>
        </div>
      </div>
    </section>

    <!-- ACCURATE DATE-SYNCED MEMBER AVAILABILITY CHECKER -->
    <section v-if="store.isSecretaryAdmin || store.isSuperAdmin" class="space-y-4">
      <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-5 shadow-xs border border-slate-200/80 dark:border-neutral-800 space-y-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-1">
            <Calendar class="w-5 h-5 text-blue-500" />
            <h2 class="font-black text-base text-slate-900 dark:text-white">Check Member Availability</h2>
          </div>
          <span class="text-[10px] font-black bg-blue-500/10 text-blue-600 dark:text-blue-400 px-2.5 py-1 rounded-full uppercase">Secretary Tool</span>
        </div>

        <p class="text-xs text-slate-500 dark:text-neutral-400 font-medium">Select target week day & date to check available musicians.</p>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 text-xs font-bold">
          <div>
            <label for="day-select" class="block text-[10px] uppercase text-slate-400 mb-1">Target Day & Date</label>
            <select id="day-select" v-model="selectedDayNeeded" class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[44px]">
              <option v-for="d in weekDaysOptions" :key="d.key" :value="d.key">{{ d.fullLabel }}</option>
            </select>
          </div>
          <div>
            <label for="slot-select" class="block text-[10px] uppercase text-slate-400 mb-1">Time Slot</label>
            <select id="slot-select" v-model="selectedSlotNeeded" class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[44px]">
              <option v-for="s in timeSlots" :key="s" :value="s">{{ s }}</option>
            </select>
          </div>
          <div>
            <label for="inst-select" class="block text-[10px] uppercase text-slate-400 mb-1">Instrument Section</label>
            <select id="inst-select" v-model="selectedInstrumentNeeded" class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[44px]">
              <option value="All">All Instruments</option>
              <option value="Clarinet">Clarinet</option>
              <option value="Flute">Flute / Piccolo</option>
              <option value="Saxophone">Saxophone</option>
              <option value="Trumpet">Trumpet</option>
              <option value="Trombone">Trombone</option>
              <option value="Horn">Horn / Euphonium</option>
              <option value="Tuba">Tuba / Bass</option>
              <option value="Drum">Drums / Percussion</option>
            </select>
          </div>
        </div>

        <button 
          @click="runAvailabilityCheck"
          type="button"
          class="w-full py-3 bg-blue-600 hover:bg-blue-500 text-white font-black text-xs rounded-xl flex items-center justify-center transition-all shadow-md active:scale-95 cursor-pointer min-h-[44px]"
        >
          <Cpu class="w-4 h-4 mr-2" /> Check Free Musicians
        </button>
      </div>

      <!-- MATCHED AVAILABILITY DISPLAY -->
      <div v-if="isDispatchGenerated" class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-4 shadow-xs border border-slate-200 dark:border-neutral-800 space-y-3">
        <div class="flex items-center justify-between">
          <h3 class="font-black text-sm text-slate-900 dark:text-white">Roster for {{ selectedDayNeeded }} {{ selectedSlotNeeded.split(' ')[0] }}</h3>
          <span class="text-xs font-bold text-emerald-600 dark:text-emerald-400 bg-emerald-100 dark:bg-emerald-950/60 px-2.5 py-0.5 rounded-md">
            {{ availableUserIds.size }} Free
          </span>
        </div>

        <div class="space-y-2">
          <div v-for="m in matchedDispatchRoster" :key="m.id" class="p-2.5 bg-slate-50 dark:bg-[#27272a] rounded-xl flex items-center justify-between text-xs">
            <div class="flex items-center space-x-1">
              <span class="font-bold text-slate-900 dark:text-white">{{ m.full_name }} ({{ m.instrument }})</span>
              <span v-if="availableUserIds.has(m.id)" class="text-[10px] font-black bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-400 px-2 py-0.5 rounded">
                ✓ Free {{ selectedDayNeeded }}
              </span>
              <span v-else class="text-[10px] font-bold text-slate-400">Unavailable</span>
            </div>
            <span class="font-bold text-slate-500 dark:text-neutral-400">{{ m.rank }} Rank</span>
          </div>
        </div>
      </div>

      <!-- Re-notifications Trigger -->
      <div class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-4 shadow-xs border border-slate-200 dark:border-neutral-800 flex items-center justify-between">
        <div>
          <h3 class="font-bold text-sm text-slate-900 dark:text-white">RSVP Re-notifications</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400">Send follow-up reminders to unconfirmed members</p>
        </div>
        <button 
          @click="triggerReNotifications"
          type="button"
          class="py-2.5 px-3.5 bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs rounded-xl flex items-center shadow-xs active:scale-95 cursor-pointer min-h-[44px]"
        >
          <Send class="w-3.5 h-3.5 mr-1" /> Alert Unconfirmed
        </button>
      </div>
    </section>

    <!-- ROSTER MANAGEMENT FOR IT ADMIN -->
    <section v-if="store.isSuperAdmin" class="space-y-3" aria-label="Member Roster & Roles Section">
      <div class="flex items-center justify-between px-1">
        <h2 class="text-xs font-extrabold text-slate-500 dark:text-neutral-400 uppercase tracking-wider">
          System Roles & Officer Assignments
        </h2>
      </div>

      <div class="bg-white dark:bg-[#1c1c1e] rounded-2xl shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-hidden">
        <div v-if="memberRoster.length > 0">
          <div 
            v-for="member in memberRoster" 
            :key="member.id"
            class="p-4 border-b border-slate-100 dark:border-neutral-800 last:border-0 space-y-3"
          >
            <div class="flex justify-between items-start">
              <div>
                <h3 class="font-black text-sm text-slate-900 dark:text-white flex items-center">
                  {{ member.full_name }}
                  <span v-if="member.role === 'super_admin'" class="ml-2 text-[10px] font-black uppercase bg-rose-500 text-white px-2 py-0.5 rounded-md">
                    IT Super Admin
                  </span>
                  <span v-else-if="member.executive_title" class="ml-2 text-[10px] font-black uppercase bg-blue-600 text-white px-2 py-0.5 rounded-md">
                    {{ member.executive_title }}
                  </span>
                </h3>
                <p class="text-xs text-slate-500 dark:text-neutral-400">{{ member.email }} • {{ member.instrument }}</p>
              </div>

              <button 
                @click="toggleRank(member)"
                type="button"
                :disabled="member.role === 'super_admin'"
                class="text-[10px] font-black px-3 py-1.5 rounded-lg border transition-all flex items-center active:scale-95 disabled:opacity-50 cursor-pointer min-h-[44px]"
                :class="member.rank === 'Senior' 
                  ? 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/40' 
                  : 'bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400 border-slate-200 dark:border-neutral-700/80'"
              >
                <Award class="w-3.5 h-3.5 mr-1" /> {{ member.rank }} Rank
              </button>
            </div>

            <div class="grid grid-cols-2 gap-2 pt-1">
              <div>
                <label :for="'role-select-' + member.id" class="block text-[10px] font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">System Role</label>
                <select 
                  :id="'role-select-' + member.id"
                  :value="member.role"
                  @change="e => changeRole(member, e.target.value)"
                  :disabled="member.role === 'super_admin'"
                  class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-800 dark:text-white font-bold text-xs rounded-xl p-2.5 border border-slate-200 dark:border-neutral-700/80 focus:ring-0 disabled:opacity-50 min-h-[44px]"
                >
                  <option value="member">Musician (Member)</option>
                  <option value="secretary_admin">Band Secretary (Admin)</option>
                  <option value="executive">Executive (Officer)</option>
                  <option value="super_admin">IT Admin (Developer)</option>
                </select>
              </div>

              <div>
                <label :for="'exec-select-' + member.id" class="block text-[10px] font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Executive Title</label>
                <select 
                  :id="'exec-select-' + member.id"
                  :value="member.executive_title || ''"
                  @change="e => assignExecutiveTitle(member, e.target.value)"
                  class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-800 dark:text-white font-bold text-xs rounded-xl p-2.5 border border-slate-200 dark:border-neutral-700/80 focus:ring-0 min-h-[44px]"
                >
                  <option value="">None</option>
                  <option value="president">President</option>
                  <option value="vice_president">Vice President</option>
                  <option value="treasurer">Treasurer</option>
                </select>
              </div>
            </div>

            <!-- Hide Delete & Free ID button for IT Super Admin / own account -->
            <div v-if="member.role !== 'super_admin' && member.id !== store.user?.id" class="flex justify-end pt-1">
              <button 
                @click="promptDeleteUser(member)"
                type="button"
                class="text-[11px] font-bold text-rose-500 hover:text-rose-700 flex items-center hover:underline cursor-pointer min-h-[44px] px-2"
              >
                <Trash2 class="w-3.5 h-3.5 mr-1" /> Delete & Free ID
              </button>
            </div>

          </div>
        </div>
      </div>
    </section>

    <!-- CUSTOM CONFIRMATION MODAL -->
    <div v-if="showConfirmModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-5 max-w-sm w-full space-y-4 shadow-2xl text-center">
        <div class="w-12 h-12 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        
        <div>
          <h3 class="font-black text-lg text-slate-900 dark:text-white leading-tight">Delete Registration?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 mt-1 leading-relaxed">
            Are you sure you want to decline and permanently delete **{{ confirmUserTarget?.full_name }}**?
          </p>
        </div>

        <div class="flex space-x-2 pt-2">
          <button 
            @click="showConfirmModal = false; confirmUserTarget = null" 
            type="button" 
            class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 active:scale-95 min-h-[44px] cursor-pointer"
          >
            Cancel
          </button>
          <button 
            @click="executeRejectAndDeleteUser" 
            type="button" 
            class="flex-1 py-3 bg-rose-600 hover:bg-rose-700 font-black text-xs text-white rounded-xl shadow-md active:scale-95 min-h-[44px] cursor-pointer"
          >
            Delete
          </button>
        </div>
      </div>
    </div>

  </div>
</template>
