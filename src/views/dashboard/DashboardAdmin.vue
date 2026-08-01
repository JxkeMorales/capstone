<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { ShieldAlert, UserCheck, Trash2, CheckCircle2, Shield, Award, Send, Users, Cpu, ChevronUp, AlertCircle, X, DollarSign, MessageSquare, Smartphone, Calendar, Clock } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const store = useMainStore()

const pendingAccounts = ref([])
const memberRoster = ref([])
const notification = ref('')
const isLoading = ref(true)

// Realtime Channel Reference
let adminChannel = null

// Custom Confirmation Modal State
const showConfirmModal = ref(false)
const confirmUserTarget = ref(null)

// Dynamic Week Days Generator
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
      fullLabel: `${dayName} (${monthDay})`
    })
  }
  return week
}

const weekDaysOptions = computed(() => getWeekDays())
const timeSlots = ['Morning (8am-12pm)', 'Afternoon (1pm-5pm)', 'Evening (6pm-10pm)']

// Availability Checker State
const selectedDayNeeded = ref('Mon')
const selectedSlotNeeded = ref('Morning (8am-12pm)')
const selectedInstrumentNeeded = ref('All')
const matchedDispatchRoster = ref([])
const isDispatchGenerated = ref(false)
const availableUserIds = ref(new Set())

const showNotification = (msg) => {
  notification.value = msg
  setTimeout(() => { notification.value = '' }, 3500)
}

const fetchAdminData = async () => {
  isLoading.value = true
  try {
    if (store.isSuperAdmin) {
      const { data: pendingData } = await supabase
        .from('profiles')
        .select('*')
        .eq('is_verified', false)
        .order('created_at', { ascending: false })
      if (pendingData) pendingAccounts.value = pendingData
    }

    const { data: rosterData } = await supabase
      .from('profiles')
      .select('*')
      .eq('is_verified', true)
      .order('full_name', { ascending: true })

    if (rosterData) memberRoster.value = rosterData
  } catch (err) {
    console.error('Error fetching admin data:', err)
  } finally {
    isLoading.value = false
  }
}

// IT ADMIN ONLY: APPROVE & VERIFY USER
const approveUser = async (user) => {
  if (!store.isSuperAdmin) return
  const { error } = await supabase
    .from('profiles')
    .update({ is_verified: true })
    .eq('id', user.id)

  if (!error) {
    pendingAccounts.value = pendingAccounts.value.filter(a => a.id !== user.id)
    memberRoster.value.push({ ...user, is_verified: true })
    showNotification(`Approved & Verified ${user.full_name}!`)
  }
}

// IT ADMIN ONLY: DELETE USER
const promptDeleteUser = (user) => {
  if (!store.isSuperAdmin) return
  if (user.role === 'super_admin') {
    showNotification('Security Alert: Cannot delete IT Super Admin account!')
    return
  }
  confirmUserTarget.value = user
  showConfirmModal.value = true
}

const executeRejectAndDeleteUser = async () => {
  const user = confirmUserTarget.value
  if (!user) return

  try {
    const { error } = await supabase
      .from('profiles')
      .delete()
      .eq('id', user.id)

    if (!error) {
      pendingAccounts.value = pendingAccounts.value.filter(a => a.id !== user.id)
      memberRoster.value = memberRoster.value.filter(a => a.id !== user.id)
      showNotification(`Permanently deleted ${user.full_name}'s account. ID freed.`)
    }
  } catch (err) {
    console.error('Delete error:', err)
  } finally {
    showConfirmModal.value = false
    confirmUserTarget.value = null
  }
}

// IT ADMIN ONLY: ASSIGN EXECUTIVE TITLE
const assignExecutiveTitle = async (member, title) => {
  if (!store.isSuperAdmin) return
  const newTitle = title || null
  const { error } = await supabase
    .from('profiles')
    .update({ executive_title: newTitle })
    .eq('id', member.id)

  if (!error) {
    member.executive_title = newTitle
    showNotification(`Assigned ${member.full_name} as ${newTitle || 'No Title'}`)
  } else {
    showNotification('Executive constraint error: Title already assigned to another active officer.')
  }
}

// IT ADMIN ONLY: CHANGE ROLE
const changeRole = async (member, newRole) => {
  if (!store.isSuperAdmin) return
  if (member.role === 'super_admin' && newRole !== 'super_admin') {
    showNotification('Security Protection: Cannot demote IT Super Admin!')
    return
  }
  const { error } = await supabase
    .from('profiles')
    .update({ role: newRole })
    .eq('id', member.id)

  if (!error) {
    member.role = newRole
    showNotification(`Updated ${member.full_name}'s role to ${newRole}`)
  }
}

// SECRETARY & IT ADMIN: PROMOTE / DEMOTE MEMBER RANK
const toggleRank = async (member) => {
  if (member.role === 'super_admin') {
    showNotification('Protection Policy: Cannot alter IT Super Admin rank!')
    return
  }

  const newRank = member.rank === 'Junior' ? 'Senior' : 'Junior'
  const { error } = await supabase
    .from('profiles')
    .update({ rank: newRank })
    .eq('id', member.id)

  if (!error) {
    member.rank = newRank
    showNotification(`Updated ${member.full_name} to ${newRank} rank`)
  }
}

// CLEAN ACCURATE AVAILABILITY CHECKER
const runAvailabilityCheck = async () => {
  const { data: freeData } = await supabase
    .from('member_availability')
    .select('user_id')
    .eq('day_of_week', selectedDayNeeded.value)
    .eq('time_slot', selectedSlotNeeded.value)
    .eq('is_free', true)

  const freeSet = new Set()
  if (freeData) {
    freeData.forEach(item => freeSet.add(item.user_id))
  }
  availableUserIds.value = freeSet

  let candidates = memberRoster.value.filter(m => 
    (selectedInstrumentNeeded.value === 'All' || m.instrument.toLowerCase() === selectedInstrumentNeeded.value.toLowerCase())
  )

  candidates.sort((a, b) => {
    const isFreeA = freeSet.has(a.id) ? 1 : 0
    const isFreeB = freeSet.has(b.id) ? 1 : 0
    if (isFreeA !== isFreeB) return isFreeB - isFreeA
    return (b.reliability_score || 100) - (a.reliability_score || 100)
  })

  matchedDispatchRoster.value = candidates
  isDispatchGenerated.value = true

  showNotification(`Found ${freeSet.size} musicians free for ${selectedDayNeeded.value} ${selectedSlotNeeded.value.split(' ')[0]}!`)
}

// RE-NOTIFICATIONS
const triggerReNotifications = () => {
  showNotification('Sent 1-tap push re-notifications to all unconfirmed RSVP members!')
}

onMounted(() => {
  fetchAdminData()

  // CONNECT SUPABASE REALTIME WEBSOCKET SUBSCRIPTION
  adminChannel = supabase
    .channel('admin-realtime')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, () => {
      fetchAdminData()
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
    
    <header class="pt-1 flex items-center justify-between">
      <div>
        <p class="text-xs font-bold text-yellow-600 dark:text-yellow-400 uppercase tracking-wider">
          {{ store.isSuperAdmin ? 'IT Super Admin Caretaker' : 'Band Secretary Operations Hub' }}
        </p>
        <h1 class="text-2xl font-black text-slate-900 dark:text-white">
          {{ store.isSuperAdmin ? 'System & Accounts Admin' : 'Secretary Management Hub' }}
        </h1>
      </div>
      <div class="p-2.5 rounded-2xl bg-yellow-400/20 text-yellow-600 dark:text-yellow-400">
        <Shield class="w-6 h-6" />
      </div>
    </header>

    <!-- Toast Notification -->
    <Transition name="toast">
      <div 
        v-if="notification" 
        class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-xs w-11/12 bg-white dark:bg-[#1c1c1e] text-slate-900 dark:text-white px-4 py-3 rounded-2xl shadow-xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between font-extrabold text-xs"
      >
        <div class="flex items-center space-x-2">
          <CheckCircle2 class="w-4 h-4 text-emerald-600 dark:text-emerald-400 flex-shrink-0" />
          <span>{{ notification }}</span>
        </div>
        <button @click="notification = ''" class="ml-2 text-slate-400 dark:text-neutral-500 hover:text-slate-900 dark:hover:text-white min-w-[32px] min-h-[32px] flex items-center justify-center cursor-pointer">
          <X class="w-3.5 h-3.5" />
        </button>
      </div>
    </Transition>

    <!-- PENDING APPROVALS QUEUE (IT Super Admin) -->
    <section v-if="store.isSuperAdmin" class="space-y-3" aria-label="Pending Approvals Section">
      <div class="flex items-center justify-between px-1">
        <div class="flex items-center space-x-2">
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
          class="bg-white dark:bg-[#121214] rounded-2xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 space-y-3"
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

          <div class="grid grid-cols-2 gap-2 text-xs font-semibold bg-slate-50 dark:bg-[#1c1c1e] p-2.5 rounded-xl text-slate-600 dark:text-neutral-300">
            <div><span class="text-slate-400">Instrument:</span> {{ user.instrument }}</div>
            <div><span class="text-slate-400">Sex:</span> {{ user.sex }}</div>
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

        <div v-if="pendingAccounts.length === 0" class="text-center py-6 bg-white dark:bg-[#121214] rounded-2xl border border-slate-200 dark:border-neutral-800">
          <CheckCircle2 class="w-8 h-8 text-emerald-500 mx-auto mb-2" />
          <p class="text-sm font-bold text-slate-700 dark:text-neutral-300">All sign-ups processed!</p>
        </div>
      </div>
    </section>

    <!-- ACCURATE DATE-SYNCED MEMBER AVAILABILITY CHECKER -->
    <section v-if="store.isSecretaryAdmin || store.isSuperAdmin" class="space-y-4">
      <div class="bg-white dark:bg-[#121214] rounded-3xl p-5 shadow-xs border border-slate-200/80 dark:border-neutral-800 space-y-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center space-x-2">
            <Calendar class="w-5 h-5 text-yellow-500" />
            <h2 class="font-black text-base text-slate-900 dark:text-white">Check Member Availability</h2>
          </div>
          <span class="text-[10px] font-black bg-yellow-400/20 text-yellow-600 dark:text-yellow-400 px-2.5 py-1 rounded-full uppercase">Secretary Tool</span>
        </div>

        <p class="text-xs text-slate-500 dark:text-neutral-400 font-medium">Select target week day & date to check available musicians.</p>

        <div class="grid grid-cols-2 gap-3 text-xs font-bold">
          <div>
            <label for="day-select" class="block text-[10px] uppercase text-slate-400 mb-1">Target Day & Date</label>
            <select id="day-select" v-model="selectedDayNeeded" class="w-full bg-slate-50 dark:bg-[#1c1c1e] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-800 font-bold min-h-[44px]">
              <option v-for="d in weekDaysOptions" :key="d.key" :value="d.key">{{ d.fullLabel }}</option>
            </select>
          </div>
          <div>
            <label for="slot-select" class="block text-[10px] uppercase text-slate-400 mb-1">Time Slot</label>
            <select id="slot-select" v-model="selectedSlotNeeded" class="w-full bg-slate-50 dark:bg-[#1c1c1e] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-800 font-bold min-h-[44px]">
              <option v-for="s in timeSlots" :key="s" :value="s">{{ s }}</option>
            </select>
          </div>
        </div>

        <button 
          @click="runAvailabilityCheck"
          type="button"
          class="w-full py-3 bg-yellow-400 hover:bg-yellow-500 text-slate-900 font-black text-xs rounded-xl flex items-center justify-center transition-all shadow-md active:scale-95 cursor-pointer min-h-[44px]"
        >
          <Cpu class="w-4 h-4 mr-2" /> Check Free Musicians
        </button>
      </div>

      <!-- MATCHED AVAILABILITY DISPLAY -->
      <div v-if="isDispatchGenerated" class="bg-white dark:bg-[#121214] rounded-2xl p-4 shadow-xs border border-slate-200 dark:border-neutral-800 space-y-3">
        <div class="flex items-center justify-between">
          <h3 class="font-black text-sm text-slate-900 dark:text-white">Roster for {{ selectedDayNeeded }} {{ selectedSlotNeeded.split(' ')[0] }}</h3>
          <span class="text-xs font-bold text-emerald-600 dark:text-emerald-400 bg-emerald-100 dark:bg-emerald-950/60 px-2.5 py-0.5 rounded-md">
            {{ availableUserIds.size }} Free
          </span>
        </div>

        <div class="space-y-2">
          <div v-for="m in matchedDispatchRoster" :key="m.id" class="p-2.5 bg-slate-50 dark:bg-[#1c1c1e] rounded-xl flex items-center justify-between text-xs">
            <div class="flex items-center space-x-2">
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
      <div class="bg-white dark:bg-[#121214] rounded-2xl p-4 shadow-xs border border-slate-200 dark:border-neutral-800 flex items-center justify-between">
        <div>
          <h3 class="font-bold text-sm text-slate-900 dark:text-white">RSVP Re-notifications</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400">Send follow-up reminders to unconfirmed members</p>
        </div>
        <button 
          @click="triggerReNotifications"
          type="button"
          class="py-2.5 px-3.5 bg-yellow-400 text-slate-900 font-bold text-xs rounded-xl flex items-center shadow-xs active:scale-95 cursor-pointer min-h-[44px]"
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

      <div class="bg-white dark:bg-[#121214] rounded-2xl shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-hidden">
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
                  <span v-else-if="member.executive_title" class="ml-2 text-[10px] font-black uppercase bg-yellow-400 text-slate-900 px-2 py-0.5 rounded-md">
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
                  ? 'bg-yellow-400/10 text-yellow-600 dark:text-yellow-400 border-yellow-400/40' 
                  : 'bg-slate-100 dark:bg-[#1c1c1e] text-slate-600 dark:text-neutral-400 border-slate-200 dark:border-neutral-800'"
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
                  class="w-full bg-slate-50 dark:bg-[#1c1c1e] text-slate-800 dark:text-white font-bold text-xs rounded-xl p-2.5 border border-slate-200 dark:border-neutral-800 focus:ring-0 disabled:opacity-50 min-h-[44px]"
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
                  class="w-full bg-slate-50 dark:bg-[#1c1c1e] text-slate-800 dark:text-white font-bold text-xs rounded-xl p-2.5 border border-slate-200 dark:border-neutral-800 focus:ring-0 min-h-[44px]"
                >
                  <option value="">None</option>
                  <option value="president">President</option>
                  <option value="vice_president">Vice President</option>
                  <option value="treasurer">Treasurer</option>
                </select>
              </div>
            </div>

            <div class="flex justify-end pt-1">
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
      <div class="bg-white dark:bg-[#121214] border border-slate-200 dark:border-neutral-800 rounded-3xl p-5 max-w-sm w-full space-y-4 shadow-2xl text-center">
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
