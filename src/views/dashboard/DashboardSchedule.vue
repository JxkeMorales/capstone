<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { Calendar, MapPin, Clock, Filter, CheckCircle2, XCircle, AlertCircle, Plus, Users, X, Trash2, UserCheck, UserX, History, ChevronDown } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const store = useMainStore()

const currentMonthName = ref('August 2026')
const activeFilters = ref(['All'])
const tempFilters = ref(['All'])
const showFilterMenu = ref(false)

const openFilter = () => {
  tempFilters.value = [...activeFilters.value]
  showFilterMenu.value = true
}

const toggleTempFilter = (sec) => {
  if (sec === 'All') {
    tempFilters.value = ['All']
    return
  }
  if (tempFilters.value.includes('All')) {
    tempFilters.value = tempFilters.value.filter(f => f !== 'All')
  }
  if (tempFilters.value.includes(sec)) {
    tempFilters.value = tempFilters.value.filter(f => f !== sec)
    if (tempFilters.value.length === 0) tempFilters.value = ['All']
  } else {
    tempFilters.value.push(sec)
  }
}

const applyFilters = () => {
  activeFilters.value = [...tempFilters.value]
  showFilterMenu.value = false
}
const activeScheduleTab = ref('upcoming')
const rawEvents = ref([])
const isLoading = ref(true)

// Realtime Channel & Sync References
let scheduleChannel = null
let syncBroadcast = null
let pollTimer = null

// Toast Notification State
const toastMessage = ref('')
const showToastNotification = (msg) => {
  toastMessage.value = msg
  setTimeout(() => { toastMessage.value = '' }, 3500)
}

// Attendance Tracker Modal State (Secretary / Admin)
const showAttendanceModal = ref(false)
const selectedEventForAttendance = ref(null)
const attendingMembersList = ref([])
const declinedMembersList = ref([])
const isLoadingAttendance = ref(false)

// Roll Call Modal State (Secretary)
const showRollCallModal = ref(false)
const selectedEventForRollCall = ref(null)
const memberRosterForRollCall = ref([])
const rollCallState = ref({})
const isSavingRollCall = ref(false)

// Delete Confirm Modal State
const showDeleteConfirmModal = ref(false)
const targetEventIdToDelete = ref(null)

const filterCategories = [
  'All', 
  'Practice & Rehearsal (Ensayo)', 
  'Wake & Vigil (Bantay / Lamay)', 
  'Funeral March (Libing)', 
  'Civic Parade (Parada)', 
  'Feast Procession (Prusisyon)',
  'Band Meeting (Pulong)'
]

const getTodayStart = () => {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

const upcomingEvents = computed(() => {
  const todayStart = getTodayStart()
  return rawEvents.value
    .filter(ev => new Date(ev.rawDate).getTime() >= todayStart)
    .sort((a, b) => new Date(a.rawDate) - new Date(b.rawDate))
})

const pastEvents = computed(() => {
  const todayStart = getTodayStart()
  return rawEvents.value
    .filter(ev => new Date(ev.rawDate).getTime() < todayStart)
    .sort((a, b) => new Date(b.rawDate) - new Date(a.rawDate))
})

const displayedEvents = computed(() => {
  const targetList = activeScheduleTab.value === 'upcoming' ? upcomingEvents.value : pastEvents.value
  if (activeFilter.value === 'All') return targetList
  const key = activeFilter.value.toLowerCase().split('/')[0].split('(')[0].trim()
  return targetList.filter(e => e.type.toLowerCase().includes(key))
})

const notifyOtherTabs = (eventType) => {
  if (syncBroadcast) {
    try { syncBroadcast.postMessage({ type: eventType, time: Date.now() }) } catch(e){}
  }
}

const fetchEvents = async (skipCache = false) => {
  if (!skipCache) {
    isLoading.value = true
    const cachedEvents = localStorage.getItem('smartband_raw_events_cache')
    if (cachedEvents) {
      try { rawEvents.value = JSON.parse(cachedEvents) } catch (e) {}
    }
  }

  try {
    const { data } = await supabase
      .from('events')
      .select('*')
      .order('event_date', { ascending: true })

    if (data) {
      rawEvents.value = data.map(ev => {
        const dateObj = new Date(ev.event_date)
        return {
          id: ev.id,
          rawDate: ev.event_date,
          title: ev.title,
          type: ev.event_type,
          date: dateObj.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }),
          time: dateObj.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
          location: ev.location,
          dayNum: dateObj.getDate()
        }
      })
      localStorage.setItem('smartband_raw_events_cache', JSON.stringify(rawEvents.value))
    }
  } catch (err) {
    console.error('Error fetching events:', err)
  } finally {
    isLoading.value = false
  }
}

const openAttendanceTracker = async (ev) => {
  selectedEventForAttendance.value = ev
  showAttendanceModal.value = true
  isLoadingAttendance.value = true
  attendingMembersList.value = []
  declinedMembersList.value = []

  try {
    const { data: rsvps } = await supabase
      .from('event_rsvps')
      .select('status, profiles:user_id(full_name, instrument)')
      .eq('event_id', ev.id)

    if (rsvps) {
      rsvps.forEach(r => {
        const memberInfo = {
          name: r.profiles?.full_name || 'Member',
          instrument: r.profiles?.instrument || 'Musician'
        }
        if (r.status === 'attending' || r.status === 'present') {
          attendingMembersList.value.push(memberInfo)
        } else if (r.status === 'declined' || r.status === 'absent') {
          declinedMembersList.value.push(memberInfo)
        }
      })
    }
  } catch (e) {
    console.error('Error fetching attendance:', e)
  } finally {
    isLoadingAttendance.value = false
  }
}

const openRollCall = async (ev) => {
  selectedEventForRollCall.value = ev
  showRollCallModal.value = true

  const { data: roster } = await supabase.from('profiles').select('*').eq('is_verified', true)
  if (roster) {
    memberRosterForRollCall.value = roster
    const initialState = {}
    roster.forEach(m => { initialState[m.id] = 'present' })
    rollCallState.value = initialState
  }
}

const saveRollCall = async () => {
  if (!selectedEventForRollCall.value) return
  isSavingRollCall.value = true

  try {
    const logs = Object.entries(rollCallState.value).map(([userId, status]) => ({
      event_id: selectedEventForRollCall.value.id,
      user_id: userId,
      status: status
    }))

    await supabase.from('event_rsvps').upsert(logs, { onConflict: 'event_id,user_id' })
    notifyOtherTabs('RSVP_CHANGED')
    showRollCallModal.value = false
    showToastNotification('Official Roll Call logged successfully!')
  } catch (err) {
    console.error('Error saving roll call:', err)
    showToastNotification('Failed to save roll call.')
  } finally {
    isSavingRollCall.value = false
  }
}

const promptDeleteEvent = (id) => {
  targetEventIdToDelete.value = id
  showDeleteConfirmModal.value = true
}

const executeDeleteEvent = async () => {
  const id = targetEventIdToDelete.value
  if (!id) return

  const { error } = await supabase.from('events').delete().eq('id', id)
  if (!error) {
    rawEvents.value = rawEvents.value.filter(e => e.id !== id)
    localStorage.setItem('smartband_raw_events_cache', JSON.stringify(rawEvents.value))
    notifyOtherTabs('EVENT_CHANGED')
    showToastNotification('Event deleted successfully.')
  }
  showDeleteConfirmModal.value = false
  targetEventIdToDelete.value = null
}

onMounted(() => {
  fetchEvents()

  if ('BroadcastChannel' in window) {
    syncBroadcast = new BroadcastChannel('smartband_live_sync')
    syncBroadcast.onmessage = () => {
      fetchEvents(true)
      if (showAttendanceModal.value && selectedEventForAttendance.value) {
        openAttendanceTracker(selectedEventForAttendance.value)
      }
    }
  }

  scheduleChannel = supabase
    .channel('schedule-realtime-v4')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'events' }, () => {
      fetchEvents(true)
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'event_rsvps' }, () => {
      fetchEvents(true)
      if (showAttendanceModal.value && selectedEventForAttendance.value) {
        openAttendanceTracker(selectedEventForAttendance.value)
      }
    })
    .subscribe()

  pollTimer = setInterval(() => {
    fetchEvents(true)
  }, 6000)
})

onUnmounted(() => {
  if (scheduleChannel) supabase.removeChannel(scheduleChannel)
  if (syncBroadcast) syncBroadcast.close()
  if (pollTimer) clearInterval(pollTimer)
})
</script>

<template>
  <div class="p-4 sm:p-5 space-y-6 relative">
    
    <!-- Floating Toast Notification -->
    <Transition name="toast">
      <div 
        v-if="toastMessage" 
        class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-xs w-11/12 bg-white dark:bg-[#1c1c1e] text-slate-900 dark:text-white px-4 py-3 rounded-2xl shadow-xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between font-extrabold text-xs"
        role="status"
        aria-live="polite"
      >
        <div class="flex items-center space-x-1">
          <CheckCircle2 class="w-4 h-4 text-emerald-500 flex-shrink-0" />
          <span>{{ toastMessage }}</span>
        </div>
        <button @click="toastMessage = ''" class="ml-2 text-slate-400 hover:text-slate-900 dark:hover:text-white min-w-[32px] min-h-[32px] flex items-center justify-center cursor-pointer" aria-label="Close Toast">
          <X class="w-3.5 h-3.5" />
        </button>
      </div>
    </Transition>

    <header class="pt-1 flex items-center space-x-3.5 mb-2">
      <div class="p-2.5 rounded-2xl bg-blue-500/10 text-blue-600 dark:text-blue-400 shadow-xs flex-shrink-0">
        <Calendar class="w-5 h-5" />
      </div>
      <div class="min-w-0">
        <p class="text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase tracking-wider leading-tight mb-0.5">Calendar & Logs</p>
        <h1 class="text-2xl font-black text-slate-900 dark:text-white leading-tight truncate">Schedule & Events</h1>
      </div>
    </header>

    <!-- Schedule Tab Switcher (Upcoming vs Past Gigs) -->
    <div class="flex items-center justify-between bg-white dark:bg-[#1c1c1e] p-2 rounded-2xl border border-slate-200/80 dark:border-neutral-800 shadow-xs">
      <div class="flex items-center space-x-1.5">
        <button 
          @click="activeScheduleTab = 'upcoming'"
          type="button"
          class="px-4 py-2 rounded-xl text-xs font-black transition-all cursor-pointer min-h-[40px] flex items-center"
          :class="activeScheduleTab === 'upcoming' 
            ? 'bg-blue-600 text-white shadow-xs' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#27272a]'"
        >
          <Calendar class="w-4 h-4 mr-1.5" />
          <span>Upcoming Gigs ({{ upcomingEvents.length }})</span>
        </button>

        <button 
          @click="activeScheduleTab = 'past'"
          type="button"
          class="px-4 py-2 rounded-xl text-xs font-black transition-all cursor-pointer min-h-[40px] flex items-center"
          :class="activeScheduleTab === 'past' 
            ? 'bg-blue-600 text-white shadow-xs' 
            : 'text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#27272a]'"
        >
          <History class="w-4 h-4 mr-1.5" />
          <span>Past Gigs ({{ pastEvents.length }})</span>
        </button>
      </div>

      <span class="text-xs font-extrabold text-slate-400 dark:text-neutral-500 pr-2 hidden sm:inline">
        {{ rawEvents.length }} Total Records
      </span>
    </div>

    <!-- Multi-Select Filter Button -->
    <div class="relative z-10 inline-block w-auto mt-1 mb-2">
      <button 
        @click="openFilter"
        type="button"
        class="flex items-center justify-center w-[44px] h-[44px] bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-2xl text-slate-600 dark:text-neutral-400 hover:bg-slate-50 dark:hover:bg-[#27272a] transition-all shadow-xs cursor-pointer"
        aria-label="Filter Events"
      >
        <Filter class="w-5 h-5" :class="{ 'text-blue-600 dark:text-blue-400': !activeFilters.includes('All') }" />
        <div v-if="!activeFilters.includes('All')" class="absolute top-2.5 right-2.5 w-2 h-2 bg-blue-500 rounded-full border-2 border-white dark:border-[#1c1c1e]"></div>
      </button>

      <!-- Filter Dropdown Menu -->
      <div v-if="showFilterMenu" class="absolute left-0 mt-2 w-56 bg-white dark:bg-[#27272a] rounded-2xl shadow-xl border border-slate-200 dark:border-neutral-800 overflow-hidden z-50">
        <div class="p-3 bg-slate-50 dark:bg-[#1c1c1e] border-b border-slate-200 dark:border-neutral-800">
          <h3 class="text-xs font-bold text-slate-500 dark:text-neutral-400 uppercase tracking-wider">Filter Events</h3>
        </div>
        <div class="max-h-60 overflow-y-auto p-2 space-y-1">
          <label 
            v-for="filter in filterCategories" 
            :key="filter"
            class="flex items-center space-x-3 px-3 py-2 rounded-xl hover:bg-slate-50 dark:hover:bg-[#1c1c1e] cursor-pointer transition-colors"
          >
            <input 
              type="checkbox" 
              :checked="tempFilters.includes(filter)"
              @change="toggleTempFilter(filter)"
              class="w-4 h-4 rounded border-slate-300 text-blue-600 focus:ring-blue-500 dark:bg-neutral-800 dark:border-neutral-700 cursor-pointer"
            >
            <span class="text-sm font-semibold text-slate-700 dark:text-neutral-300">{{ filter === 'All' ? 'Select All' : filter }}</span>
          </label>
        </div>
        <div class="p-3 bg-slate-50 dark:bg-[#1c1c1e] border-t border-slate-200 dark:border-neutral-800 flex items-center justify-end space-x-2">
          <button @click="showFilterMenu = false" class="px-4 py-2 text-xs font-bold text-slate-500 hover:text-slate-700 dark:text-neutral-400 dark:hover:text-neutral-200 transition-colors cursor-pointer">Cancel</button>
          <button @click="applyFilters" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-xl text-xs font-black transition-colors shadow-xs cursor-pointer">Apply</button>
        </div>
      </div>
    </div>

    <!-- Events List -->
    <section class="space-y-3" aria-label="Events Feed">
      <div v-if="displayedEvents.length > 0" class="space-y-3">
        <div 
          v-for="ev in displayedEvents" 
          :key="ev.id"
          class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 space-y-3"
        >
          <div class="flex justify-between items-start">
            <div>
              <div class="flex items-center space-x-1">
                <span class="text-[10px] font-black uppercase tracking-wider px-2 py-0.5 rounded bg-blue-500/10 text-blue-600 dark:text-blue-400">
                  {{ ev.type }}
                </span>
                <span v-if="activeScheduleTab === 'past'" class="text-[10px] font-extrabold px-2 py-0.5 rounded bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-400">
                  ✓ Completed
                </span>
              </div>
              <h3 class="font-black text-base text-slate-900 dark:text-white mt-1.5 leading-tight">{{ ev.title }}</h3>
            </div>
            
            <div class="flex items-center space-x-1.5">
              <!-- Secretary RSVP Attendance Tracker Trigger -->
              <button 
                v-if="store.canConductRollCall || store.canManageEvents" 
                @click="openAttendanceTracker(ev)" 
                type="button" 
                class="px-2.5 py-1.5 bg-slate-100 dark:bg-[#27272a] text-slate-800 dark:text-slate-200 font-extrabold text-[11px] rounded-lg shadow-xs hover:bg-slate-200 dark:hover:bg-[#323238] flex items-center cursor-pointer min-h-[44px]"
                aria-label="View RSVP Attendees"
              >
                <Users class="w-3.5 h-3.5 mr-1" /> Attendees
              </button>

              <!-- Secretary Roll Call Trigger -->
              <button 
                v-if="store.canConductRollCall" 
                @click="openRollCall(ev)" 
                type="button" 
                class="px-2.5 py-1.5 bg-blue-600 hover:bg-blue-500 text-white font-extrabold text-[11px] rounded-lg shadow-xs active:scale-95 flex items-center cursor-pointer min-h-[44px]"
                aria-label="Conduct Roll Call"
              >
                Roll Call
              </button>

              <!-- Secretary / Admin Delete Button -->
              <button 
                v-if="store.canManageEvents" 
                @click="promptDeleteEvent(ev.id)" 
                type="button" 
                class="p-2 rounded-lg bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 hover:bg-rose-100 min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"
                title="Delete Event"
              >
                <Trash2 class="w-4 h-4" />
              </button>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-2 text-xs font-bold text-slate-600 dark:text-neutral-300 bg-slate-50 dark:bg-[#27272a] p-2.5 rounded-xl">
            <div class="flex items-center"><Calendar class="w-3.5 h-3.5 mr-1.5 text-slate-400" /> {{ ev.date }}</div>
            <div class="flex items-center"><Clock class="w-3.5 h-3.5 mr-1.5 text-slate-400" /> {{ ev.time }}</div>
            <div class="col-span-2 flex items-center"><MapPin class="w-3.5 h-3.5 mr-1.5 text-slate-400" /> {{ ev.location }}</div>
          </div>
        </div>
      </div>

      <div v-else class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-8 text-center border border-slate-200 dark:border-neutral-800">
        <Calendar class="w-8 h-8 text-slate-400 dark:text-neutral-500 mx-auto mb-2" />
        <p class="text-sm font-bold text-slate-700 dark:text-neutral-300">
          {{ activeScheduleTab === 'upcoming' ? 'No upcoming events scheduled in this category.' : 'No past events found in this category.' }}
        </p>
      </div>
    </section>

    <!-- SECRETARY / ADMIN EVENT RSVP ATTENDANCE TRACKER MODAL -->
    <div v-if="showAttendanceModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left max-h-[85vh] flex flex-col">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div>
            <span class="text-[10px] font-black text-blue-500 uppercase">RSVP Attendance Tracker</span>
            <h3 class="font-black text-base text-slate-900 dark:text-white truncate">{{ selectedEventForAttendance?.title }}</h3>
          </div>
          <button @click="showAttendanceModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div v-if="isLoadingAttendance" class="py-6 text-center text-xs font-bold text-slate-400">Loading attendee responses...</div>

        <div v-else class="overflow-y-auto flex-1 space-y-4 pr-1">
          <!-- Attending List -->
          <div class="space-y-2">
            <div class="flex items-center space-x-1.5 text-xs font-black text-emerald-600 dark:text-emerald-400">
              <UserCheck class="w-4 h-4" />
              <span>Confirmed Attending / Present ({{ attendingMembersList.length }})</span>
            </div>
            <div v-if="attendingMembersList.length > 0" class="space-y-1.5">
              <div v-for="m in attendingMembersList" :key="m.name" class="p-2 bg-emerald-50 dark:bg-emerald-950/30 border border-emerald-200 dark:border-emerald-900/40 rounded-xl text-xs flex justify-between">
                <span class="font-bold text-emerald-700 dark:text-emerald-400">{{ m.name }}</span>
                <span class="text-slate-500 capitalize">{{ m.instrument }}</span>
              </div>
            </div>
            <p v-else class="text-[11px] text-slate-400">No members confirmed attending yet.</p>
          </div>

          <!-- Declined List -->
          <div class="space-y-2 pt-2 border-t border-slate-100 dark:border-neutral-800">
            <div class="flex items-center space-x-1.5 text-xs font-black text-rose-600 dark:text-rose-400">
              <UserX class="w-4 h-4" />
              <span>Declined / Absent ({{ declinedMembersList.length }})</span>
            </div>
            <div v-if="declinedMembersList.length > 0" class="space-y-1.5">
              <div v-for="m in declinedMembersList" :key="m.name" class="p-2 bg-rose-50 dark:bg-rose-950/30 border border-rose-200 dark:border-rose-900/40 rounded-xl text-xs flex justify-between">
                <span class="font-bold text-rose-700 dark:text-rose-400">{{ m.name }}</span>
                <span class="text-slate-500 capitalize">{{ m.instrument }}</span>
              </div>
            </div>
            <p v-else class="text-[11px] text-slate-400">No members declined.</p>
          </div>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800">
          <button @click="showAttendanceModal = false" type="button" class="w-full py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer">
            Close
          </button>
        </div>
      </div>
    </div>

    <!-- ROLL CALL MODAL -->
    <div v-if="showRollCallModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-5 max-w-sm w-full space-y-4 shadow-2xl">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-2">
          <div>
            <span class="text-[10px] font-black text-blue-500 uppercase">Official Roll Call</span>
            <h3 class="font-black text-base text-slate-900 dark:text-white truncate">{{ selectedEventForRollCall?.title }}</h3>
          </div>
          <button @click="showRollCallModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer" aria-label="Close Modal"><X class="w-5 h-5" /></button>
        </div>

        <div class="max-h-60 overflow-y-auto space-y-2 pr-1">
          <div v-for="mem in memberRosterForRollCall" :key="mem.id" class="flex items-center justify-between bg-slate-50 dark:bg-[#27272a] p-2.5 rounded-xl text-xs font-bold">
            <span class="text-slate-900 dark:text-white truncate max-w-[120px]">{{ mem.full_name }}</span>
            <div class="flex space-x-1">
              <button @click="rollCallState[mem.id] = 'present'" :class="rollCallState[mem.id] === 'present' ? 'bg-emerald-600 text-white' : 'bg-slate-200 dark:bg-[#323238] text-slate-500 dark:text-neutral-400'" class="px-2 py-1 rounded text-[10px] font-bold min-h-[36px]">Present</button>
              <button @click="rollCallState[mem.id] = 'absent'" :class="rollCallState[mem.id] === 'absent' ? 'bg-rose-600 text-white' : 'bg-slate-200 dark:bg-[#323238] text-slate-500 dark:text-neutral-400'" class="px-2 py-1 rounded text-[10px] font-bold min-h-[36px]">Absent</button>
              <button @click="rollCallState[mem.id] = 'excused'" :class="rollCallState[mem.id] === 'excused' ? 'bg-amber-600 text-white' : 'bg-slate-200 dark:bg-[#323238] text-slate-500 dark:text-neutral-400'" class="px-2 py-1 rounded text-[10px] font-bold min-h-[36px]">Excused</button>
            </div>
          </div>
        </div>

        <div class="flex space-x-2 pt-2">
          <button @click="showRollCallModal = false" class="flex-1 py-3 bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 font-bold text-xs border border-rose-200 dark:border-rose-900/40 hover:bg-rose-100 rounded-xl min-h-[44px] cursor-pointer">Cancel</button>
          <button @click="saveRollCall" :disabled="isSavingRollCall" class="flex-1 py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer">Save Roll Call</button>
        </div>
      </div>
    </div>

    <!-- DELETE CONFIRM MODAL -->
    <div v-if="showDeleteConfirmModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-5 max-w-sm w-full space-y-4 shadow-2xl text-center">
        <div class="w-12 h-12 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        <div>
          <h3 class="font-black text-lg text-slate-900 dark:text-white leading-tight">Delete Event?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 mt-1 leading-relaxed">
            Are you sure you want to delete this scheduled event?
          </p>
        </div>
        <div class="flex space-x-2 pt-2">
          <button @click="showDeleteConfirmModal = false; targetEventIdToDelete = null" type="button" class="flex-1 py-3 bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 font-bold text-xs border border-rose-200 dark:border-rose-900/40 hover:bg-rose-100 rounded-xl min-h-[44px] cursor-pointer">Cancel</button>
          <button @click="executeDeleteEvent" type="button" class="flex-1 py-3 bg-rose-600 hover:bg-rose-700 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer">Delete</button>
        </div>
      </div>
    </div>

  </div>
</template>
