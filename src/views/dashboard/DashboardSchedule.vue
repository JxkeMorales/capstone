<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { Calendar, MapPin, Clock, Filter, CheckCircle2, XCircle, AlertCircle, Plus, Users, X, Trash2, UserCheck, UserX, History, ChevronDown } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'
import { initRealtimeSync, broadcastSync } from '@/utils/realtime'

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

// Attendance Tracker & Roll-Call Roster State (Secretary / Admin)
const showAttendanceModal = ref(false)
const selectedEventForAttendance = ref(null)
const rollCallRoster = ref([])
const isLoadingAttendance = ref(false)
const isBatchMarking = ref(false)
const attendanceTabFilter = ref('all') // 'all' | 'attending' | 'declined' | 'unconfirmed'

// Schedule New Gig State (Secretary / Super Admin)
const showAddEventModal = ref(false)
const isSavingEvent = ref(false)
const newEventForm = ref({
  title: '',
  event_type: 'Practice & Rehearsal (Ensayo)',
  event_date: '',
  location: '',
  budget_estimate: 0
})

const saveNewEvent = async () => {
  if (!newEventForm.value.title.trim() || !newEventForm.value.event_date || !newEventForm.value.location.trim()) {
    showToastNotification('Please enter event title, date/time, and location.')
    return
  }

  isSavingEvent.value = true
  try {
    const { error } = await supabase
      .from('events')
      .insert({
        title: newEventForm.value.title.trim(),
        event_type: newEventForm.value.event_type,
        event_date: new Date(newEventForm.value.event_date).toISOString(),
        location: newEventForm.value.location.trim(),
        budget_estimate: Number(newEventForm.value.budget_estimate) || 0
      })
      .select()
      .single()

    if (error) throw error

    showToastNotification('✓ New gig scheduled & announced to all musicians!')
    showAddEventModal.value = false
    newEventForm.value = {
      title: '',
      event_type: 'Practice & Rehearsal (Ensayo)',
      event_date: '',
      location: '',
      budget_estimate: 0
    }
    await fetchEvents(true)
    notifyOtherTabs('NEW_EVENT_SCHEDULED')
  } catch (err) {
    console.error('Error saving event:', err)
    showToastNotification('Failed to schedule event: ' + (err.message || 'Error'))
  } finally {
    isSavingEvent.value = false
  }
}

const filteredRollCallRoster = computed(() => {
  if (attendanceTabFilter.value === 'attending') {
    return rollCallRoster.value.filter(m => m.initialRsvp === 'attending' || m.currentStatus === 'present' || m.currentStatus === 'absent')
  }
  if (attendanceTabFilter.value === 'declined') {
    return rollCallRoster.value.filter(m => m.initialRsvp === 'declined')
  }
  if (attendanceTabFilter.value === 'unconfirmed') {
    return rollCallRoster.value.filter(m => m.initialRsvp === 'none')
  }
  return rollCallRoster.value
})

const attendanceCounts = computed(() => {
  const total = rollCallRoster.value.length
  const attending = rollCallRoster.value.filter(m => m.initialRsvp === 'attending' || m.currentStatus === 'present' || m.currentStatus === 'absent').length
  const declined = rollCallRoster.value.filter(m => m.initialRsvp === 'declined').length
  const unconfirmed = rollCallRoster.value.filter(m => m.initialRsvp === 'none').length
  const present = rollCallRoster.value.filter(m => m.currentStatus === 'present').length
  const absent = rollCallRoster.value.filter(m => m.currentStatus === 'absent').length
  const excused = rollCallRoster.value.filter(m => m.currentStatus === 'excused').length
  return { total, attending, declined, unconfirmed, present, absent, excused }
})

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
  if (activeFilters.value.includes('All')) return targetList
  
  return targetList.filter(e => {
    return activeFilters.value.some(filterItem => {
      const key = filterItem.toLowerCase().split('/')[0].split('(')[0].trim()
      return e.type.toLowerCase().includes(key)
    })
  })
})

const notifyOtherTabs = (eventType) => {
  broadcastSync(eventType)
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

// RECALCULATE MEMBER RELIABILITY SCORE UPON ATTENDANCE UPDATE
const updateMemberReliabilityScore = async (userId) => {
  try {
    const { data: pastRsvps } = await supabase
      .from('event_rsvps')
      .select('status, events(event_date)')
      .eq('user_id', userId)

    if (!pastRsvps) return

    const flakes = pastRsvps.filter(r => r.status === 'absent').length
    const calculatedScore = Math.max(0, 100 - (flakes * 10))

    await supabase
      .from('profiles')
      .update({ reliability_score: calculatedScore })
      .eq('id', userId)
  } catch (err) {
    console.warn('Reliability update notice:', err)
  }
}

// OPEN EVENT ATTENDANCE ROLL-CALL TRACKER
const openAttendanceTracker = async (ev) => {
  selectedEventForAttendance.value = ev
  showAttendanceModal.value = true
  isLoadingAttendance.value = true
  attendanceTabFilter.value = 'all'
  rollCallRoster.value = []

  try {
    const { data: members, error: memErr } = await supabase
      .from('profiles')
      .select('id, full_name, instrument, rank, role, profile_picture')
      .eq('is_verified', true)
      .order('full_name', { ascending: true })

    if (memErr) throw memErr

    const { data: rsvps, error: rsvpErr } = await supabase
      .from('event_rsvps')
      .select('id, user_id, status')
      .eq('event_id', ev.id)

    if (rsvpErr) throw rsvpErr

    const rsvpMap = new Map()
    if (rsvps) {
      rsvps.forEach(r => rsvpMap.set(r.user_id, r.status))
    }

    rollCallRoster.value = (members || []).map(m => {
      const st = rsvpMap.get(m.id) || 'none'
      let initRsvp = 'none'
      if (st === 'attending' || st === 'present' || st === 'absent') {
        initRsvp = 'attending'
      } else if (st === 'declined') {
        initRsvp = 'declined'
      }
      return {
        userId: m.id,
        name: m.full_name,
        instrument: m.instrument || 'Musician',
        rank: m.rank || 'Junior',
        role: m.role || 'member',
        avatar: m.full_name ? m.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB',
        profile_picture: m.profile_picture,
        initialRsvp: initRsvp,
        currentStatus: st,
        isSaving: false
      }
    }).sort((a, b) => {
      const order = { attending: 0, declined: 1, none: 2 }
      return (order[a.initialRsvp] ?? 3) - (order[b.initialRsvp] ?? 3)
    })
  } catch (err) {
    console.error('Error fetching attendance roster:', err)
    showToastNotification('Failed to load attendance roster.')
  } finally {
    isLoadingAttendance.value = false
  }
}

// TOGGLE OR SET ATTENDANCE STATUS FOR A SINGLE MUSICIAN
const setMemberAttendance = async (member, newStatus) => {
  if (member.isSaving || !selectedEventForAttendance.value) return
  member.isSaving = true
  const prevStatus = member.currentStatus
  member.currentStatus = newStatus

  try {
    const { error } = await supabase
      .from('event_rsvps')
      .upsert({
        event_id: selectedEventForAttendance.value.id,
        user_id: member.userId,
        status: newStatus,
        updated_at: new Date().toISOString()
      }, { onConflict: 'event_id,user_id' })

    if (error) throw error

    await updateMemberReliabilityScore(member.userId)
    notifyOtherTabs('ATTENDANCE_UPDATED')
    showToastNotification(`✓ Marked ${member.name} as ${newStatus.toUpperCase()}`)
  } catch (err) {
    console.error('Error setting attendance:', err)
    member.currentStatus = prevStatus
    showToastNotification(`Failed to update attendance: ${err.message || 'Database error'}`)
  } finally {
    member.isSaving = false
  }
}

// BATCH QUICK-ACTION: MARK ALL ATTENDING AS PRESENT
const markAllAttendingAsPresent = async () => {
  if (isBatchMarking.value || !selectedEventForAttendance.value) return
  isBatchMarking.value = true

  try {
    const targetMembers = rollCallRoster.value.filter(m => 
      m.initialRsvp === 'attending' && m.currentStatus !== 'present'
    )

    if (targetMembers.length === 0) {
      showToastNotification('All attending members are already marked Present.')
      return
    }

    const updates = targetMembers.map(m => ({
      event_id: selectedEventForAttendance.value.id,
      user_id: m.userId,
      status: 'present',
      updated_at: new Date().toISOString()
    }))

    const { error } = await supabase
      .from('event_rsvps')
      .upsert(updates, { onConflict: 'event_id,user_id' })

    if (error) throw error

    targetMembers.forEach(m => {
      m.currentStatus = 'present'
    })

    await Promise.all(targetMembers.map(m => updateMemberReliabilityScore(m.userId)))
    notifyOtherTabs('ATTENDANCE_UPDATED')
    showToastNotification(`✓ Marked ${targetMembers.length} attending members as Present!`)
  } catch (err) {
    console.error('Batch attendance error:', err)
    showToastNotification('Failed to batch-update attendance.')
  } finally {
    isBatchMarking.value = false
  }
}

const promptDeleteEvent = (id) => {
  targetEventIdToDelete.value = id
  showDeleteConfirmModal.value = true
}

const executeDeleteEvent = async () => {
  const id = targetEventIdToDelete.value
  if (!id) return

  try {
    const { data, error } = await supabase.from('events').delete().eq('id', id).select()
    if (error) {
      showToastNotification(`Error deleting event: ${error.message}`)
      return
    }
    if (!data || data.length === 0) {
      showToastNotification('Could not delete event. Database permission denied.')
      return
    }
    rawEvents.value = rawEvents.value.filter(e => e.id !== id)
    localStorage.setItem('smartband_raw_events_cache', JSON.stringify(rawEvents.value))
    notifyOtherTabs('EVENT_CHANGED')
    showToastNotification('Event deleted successfully.')
  } catch (err) {
    showToastNotification(`Error: ${err?.message || 'Failed to delete event'}`)
  } finally {
    showDeleteConfirmModal.value = false
    targetEventIdToDelete.value = null
  }
}

let cleanupSync = null

onMounted(() => {
  fetchEvents()

  cleanupSync = initRealtimeSync((event) => {
    fetchEvents(true)
    if (showAttendanceModal.value && selectedEventForAttendance.value) {
      openAttendanceTracker(selectedEventForAttendance.value)
    }
  })

  window.addEventListener('focus', () => fetchEvents(true))

  pollTimer = setInterval(() => {
    fetchEvents(true)
  }, 4000)
})

onUnmounted(() => {
  if (cleanupSync) cleanupSync()
  if (pollTimer) clearInterval(pollTimer)
  window.removeEventListener('focus', () => fetchEvents(true))
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

    <header class="pt-1 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-2">
      <div class="flex items-center space-x-3.5">
        <div class="p-2.5 rounded-2xl bg-blue-500/10 text-blue-600 dark:text-blue-400 shadow-xs flex-shrink-0">
          <Calendar class="w-5 h-5" />
        </div>
        <div class="min-w-0">
          <p class="text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase tracking-wider leading-tight mb-0.5">Calendar & Logs</p>
          <h1 class="text-2xl font-black text-slate-900 dark:text-white leading-tight truncate">Schedule & Events</h1>
        </div>
      </div>

      <!-- Schedule New Gig Button for Secretary & Admin -->
      <button 
        v-if="store.canManageEvents"
        @click="showAddEventModal = true"
        type="button"
        class="px-4 py-2.5 bg-blue-600 hover:bg-blue-500 text-white font-black text-xs rounded-xl shadow-md flex items-center space-x-2 transition-all active:scale-95 cursor-pointer self-start sm:self-auto min-h-[44px] shrink-0"
      >
        <Plus class="w-4 h-4" />
        <span>Schedule New Gig</span>
      </button>
    </header>

    <!-- Schedule Tab Switcher (Upcoming vs Past Gigs) -->
    <div class="flex flex-wrap items-center justify-between gap-2 bg-white dark:bg-[#1c1c1e] p-2 rounded-2xl border border-slate-200/80 dark:border-neutral-800 shadow-xs">
      <div class="flex flex-wrap items-center gap-1.5 w-full sm:w-auto">
        <button 
          @click="activeScheduleTab = 'upcoming'"
          type="button"
          class="flex-1 sm:flex-none px-3.5 py-2 rounded-xl text-xs font-black transition-all cursor-pointer min-h-[40px] flex items-center justify-center"
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
          class="flex-1 sm:flex-none px-3.5 py-2 rounded-xl text-xs font-black transition-all cursor-pointer min-h-[40px] flex items-center justify-center"
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
          <div class="flex flex-col sm:flex-row sm:items-start justify-between gap-2.5">
            <div class="min-w-0 flex-1">
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
            
            <div class="flex items-center space-x-1.5 self-end sm:self-auto shrink-0">
              <!-- Secretary RSVP Attendance Tracker & Roll Call Trigger -->
              <button 
                v-if="store.canConductRollCall || store.canManageEvents" 
                @click="openAttendanceTracker(ev)" 
                type="button" 
                class="px-3 py-1.5 bg-slate-100 dark:bg-[#27272a] text-slate-800 dark:text-slate-200 font-extrabold text-[11px] rounded-lg shadow-xs hover:bg-slate-200 dark:hover:bg-[#323238] flex items-center cursor-pointer min-h-[40px]"
                aria-label="Attendance & Roll Call Log"
              >
                <Users class="w-3.5 h-3.5 mr-1" /> Roll Call Log
              </button>

              <!-- Secretary / Admin Delete Button -->
              <button 
                v-if="store.canManageEvents" 
                @click="promptDeleteEvent(ev.id)" 
                type="button" 
                class="p-2 rounded-lg bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 hover:bg-rose-100 min-w-[40px] min-h-[40px] flex items-center justify-center cursor-pointer"
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

    <!-- SECRETARY / ADMIN EVENT RSVP ATTENDANCE TRACKER & ROLL-CALL MODAL -->
    <div v-if="showAttendanceModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-3 sm:p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-4 sm:p-6 max-w-md sm:max-w-lg w-full space-y-4 shadow-2xl text-left max-h-[90vh] flex flex-col">
        
        <!-- Modal Header -->
        <div class="flex items-start justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="min-w-0 pr-2">
            <div class="flex items-center space-x-1 mb-1">
              <span class="text-[10px] font-black uppercase tracking-wider px-2 py-0.5 rounded bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-400">
                {{ selectedEventForAttendance?.type || 'Event' }}
              </span>
              <span class="text-[10px] font-bold text-slate-400 dark:text-neutral-500">Roll-Call Log</span>
            </div>
            <h3 class="font-black text-lg text-slate-900 dark:text-white truncate">
              {{ selectedEventForAttendance?.title }}
            </h3>
            <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">
              {{ selectedEventForAttendance?.date }} at {{ selectedEventForAttendance?.time }} • {{ selectedEventForAttendance?.location }}
            </p>
          </div>
          <button @click="showAttendanceModal = false" class="text-slate-400 hover:text-white min-w-[40px] min-h-[40px] flex items-center justify-center cursor-pointer">
            <X class="w-5 h-5" />
          </button>
        </div>

        <!-- Quick Summary Metrics & Batch Action -->
        <div class="bg-slate-50 dark:bg-[#27272a] p-3 rounded-2xl border border-slate-200/80 dark:border-neutral-700/80 space-y-2.5">
          <div class="flex items-center justify-between text-xs">
            <span class="font-bold text-slate-600 dark:text-neutral-300">Turnout Tally</span>
            <div class="flex items-center space-x-2 font-black text-[11px]">
              <span class="text-emerald-600 dark:text-emerald-400">{{ attendanceCounts.present }} Present</span>
              <span>•</span>
              <span class="text-rose-600 dark:text-rose-400">{{ attendanceCounts.absent }} Absent (No-Show)</span>
              <span>•</span>
              <span class="text-amber-600 dark:text-amber-400">{{ attendanceCounts.excused }} Excused</span>
            </div>
          </div>

          <button 
            v-if="store.canConductRollCall"
            @click="markAllAttendingAsPresent" 
            :disabled="isBatchMarking"
            type="button" 
            class="w-full py-2 px-3 bg-emerald-600 hover:bg-emerald-500 text-white font-extrabold text-xs rounded-xl shadow-xs flex items-center justify-center space-x-1.5 cursor-pointer active:scale-98 transition-all disabled:opacity-50 min-h-[38px]"
          >
            <CheckCircle class="w-4 h-4" />
            <span>{{ isBatchMarking ? 'Updating Attendance...' : '⚡ Mark All Attending as Present' }}</span>
          </button>
        </div>

        <!-- Filter Sub-Tabs -->
        <div class="flex items-center space-x-1 p-1 bg-slate-100 dark:bg-[#27272a] rounded-xl text-[11px] font-bold overflow-x-auto">
          <button 
            @click="attendanceTabFilter = 'all'"
            type="button"
            class="px-2.5 py-1.5 rounded-lg transition-all whitespace-nowrap cursor-pointer"
            :class="attendanceTabFilter === 'all' ? 'bg-white dark:bg-[#1c1c1e] text-blue-600 dark:text-blue-400 shadow-xs font-black' : 'text-slate-500 hover:text-slate-900 dark:text-neutral-400'"
          >
            All ({{ attendanceCounts.total }})
          </button>
          <button 
            @click="attendanceTabFilter = 'attending'"
            type="button"
            class="px-2.5 py-1.5 rounded-lg transition-all whitespace-nowrap cursor-pointer"
            :class="attendanceTabFilter === 'attending' ? 'bg-white dark:bg-[#1c1c1e] text-emerald-600 dark:text-emerald-400 shadow-xs font-black' : 'text-slate-500 hover:text-slate-900 dark:text-neutral-400'"
          >
            RSVP Attending ({{ attendanceCounts.attending }})
          </button>
          <button 
            @click="attendanceTabFilter = 'declined'"
            type="button"
            class="px-2.5 py-1.5 rounded-lg transition-all whitespace-nowrap cursor-pointer"
            :class="attendanceTabFilter === 'declined' ? 'bg-white dark:bg-[#1c1c1e] text-rose-600 dark:text-rose-400 shadow-xs font-black' : 'text-slate-500 hover:text-slate-900 dark:text-neutral-400'"
          >
            Declined ({{ attendanceCounts.declined }})
          </button>
          <button 
            @click="attendanceTabFilter = 'unconfirmed'"
            type="button"
            class="px-2.5 py-1.5 rounded-lg transition-all whitespace-nowrap cursor-pointer"
            :class="attendanceTabFilter === 'unconfirmed' ? 'bg-white dark:bg-[#1c1c1e] text-slate-800 dark:text-white shadow-xs font-black' : 'text-slate-500 hover:text-slate-900 dark:text-neutral-400'"
          >
            No Response ({{ attendanceCounts.unconfirmed }})
          </button>
        </div>

        <!-- Attendance Roster List -->
        <div v-if="isLoadingAttendance" class="py-12 text-center text-xs font-bold text-slate-400">
          Loading band attendance roster...
        </div>

        <div v-else class="overflow-y-auto flex-1 space-y-2 pr-1">
          <div 
            v-for="member in filteredRollCallRoster" 
            :key="member.userId"
            class="p-3 bg-white dark:bg-[#27272a] rounded-2xl border border-slate-200/80 dark:border-neutral-700/80 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2.5 shadow-xs transition-colors"
            :class="{
              'border-l-4 border-l-emerald-500': member.currentStatus === 'present',
              'border-l-4 border-l-rose-500': member.currentStatus === 'absent',
              'border-l-4 border-l-amber-500': member.currentStatus === 'excused'
            }"
          >
            <!-- Member Details -->
            <div class="flex items-center space-x-2.5 min-w-0">
              <div class="w-9 h-9 rounded-xl overflow-hidden bg-blue-600 text-white flex items-center justify-center font-black text-xs flex-shrink-0">
                <img v-if="member.profile_picture" :src="member.profile_picture" alt="" class="w-full h-full object-cover" />
                <span v-else>{{ member.avatar }}</span>
              </div>
              <div class="min-w-0">
                <p class="font-extrabold text-xs text-slate-900 dark:text-white truncate">
                  {{ member.name }}
                </p>
                <div class="flex items-center space-x-1.5 mt-0.5">
                  <span class="text-[10px] font-bold text-slate-500 dark:text-neutral-400 capitalize">
                    {{ member.instrument }}
                  </span>
                  <span>•</span>
                  <!-- Initial RSVP Tag -->
                  <span 
                    class="text-[9px] font-black uppercase px-1.5 py-0.2 rounded"
                    :class="{
                      'bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-300': member.initialRsvp === 'attending',
                      'bg-slate-200 dark:bg-neutral-800 text-slate-600 dark:text-neutral-400': member.initialRsvp === 'declined',
                      'bg-amber-100 dark:bg-amber-950/60 text-amber-800 dark:text-amber-300': member.initialRsvp === 'none'
                    }"
                  >
                    {{ member.initialRsvp === 'attending' ? 'RSVP: Attending' : member.initialRsvp === 'declined' ? 'RSVP: Declined' : 'No RSVP' }}
                  </span>
                </div>
              </div>
            </div>

            <!-- Roll-Call Action Controls -->
            <div v-if="store.canConductRollCall" class="flex items-center space-x-1.5 flex-shrink-0 self-end sm:self-center">
              <!-- Present Button -->
              <button 
                @click="setMemberAttendance(member, 'present')"
                :disabled="member.isSaving"
                type="button"
                class="px-2.5 py-1.5 rounded-lg text-xs font-black transition-all cursor-pointer min-h-[34px] flex items-center"
                :class="member.currentStatus === 'present' 
                  ? 'bg-emerald-600 text-white shadow-xs' 
                  : 'bg-slate-100 dark:bg-[#1c1c1e] text-slate-600 dark:text-neutral-300 hover:bg-emerald-50 hover:text-emerald-700 dark:hover:bg-emerald-950/40'"
                title="Mark Present"
              >
                <CheckCircle class="w-3.5 h-3.5 mr-1" /> Present
              </button>

              <!-- Absent / Flake Button -->
              <button 
                @click="setMemberAttendance(member, 'absent')"
                :disabled="member.isSaving"
                type="button"
                class="px-2.5 py-1.5 rounded-lg text-xs font-black transition-all cursor-pointer min-h-[34px] flex items-center"
                :class="member.currentStatus === 'absent' 
                  ? 'bg-rose-600 text-white shadow-xs' 
                  : 'bg-slate-100 dark:bg-[#1c1c1e] text-slate-600 dark:text-neutral-300 hover:bg-rose-50 hover:text-rose-700 dark:hover:bg-rose-950/40'"
                title="Mark Absent / No-Show"
              >
                <XCircle class="w-3.5 h-3.5 mr-1" /> Absent
              </button>

              <!-- Excused Button -->
              <button 
                @click="setMemberAttendance(member, 'excused')"
                :disabled="member.isSaving"
                type="button"
                class="px-2.5 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer min-h-[34px] flex items-center"
                :class="member.currentStatus === 'excused' 
                  ? 'bg-amber-500 text-white shadow-xs font-black' 
                  : 'bg-slate-100 dark:bg-[#1c1c1e] text-slate-500 dark:text-neutral-400 hover:bg-amber-50 hover:text-amber-700 dark:hover:bg-amber-950/40'"
                title="Mark Excused Absence"
              >
                Excused
              </button>
            </div>

            <!-- Read-Only Status Tag for Regular Viewers -->
            <div v-else class="flex items-center space-x-1">
              <span 
                class="px-2.5 py-1 rounded-lg text-[11px] font-black uppercase tracking-wider"
                :class="{
                  'bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300': member.currentStatus === 'present',
                  'bg-rose-100 text-rose-800 dark:bg-rose-950 dark:text-rose-300': member.currentStatus === 'absent',
                  'bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300': member.currentStatus === 'excused',
                  'bg-slate-100 text-slate-600 dark:bg-neutral-800 dark:text-neutral-400': !['present', 'absent', 'excused'].includes(member.currentStatus)
                }"
              >
                {{ member.currentStatus }}
              </span>
            </div>

          </div>

          <div v-if="filteredRollCallRoster.length === 0" class="py-8 text-center text-xs text-slate-400">
            No musicians match this filter category.
          </div>
        </div>

        <div class="pt-3 border-t border-slate-100 dark:border-neutral-800 flex justify-end">
          <button 
            @click="showAttendanceModal = false" 
            type="button" 
            class="w-full py-3 bg-slate-900 hover:bg-black dark:bg-neutral-800 dark:hover:bg-neutral-700 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer"
          >
            Done / Close Roster
          </button>
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

    <!-- SCHEDULE NEW GIG MODAL (Secretary & Admin) -->
    <div v-if="showAddEventModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-3 sm:p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-5 sm:p-6 max-w-md w-full space-y-4 shadow-2xl text-left">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-2.5">
            <div class="p-2 rounded-xl bg-blue-500/10 text-blue-600 dark:text-blue-400">
              <Calendar class="w-5 h-5" />
            </div>
            <div>
              <h3 class="font-black text-base text-slate-900 dark:text-white leading-tight">Schedule New Band Gig</h3>
              <p class="text-[11px] text-slate-500 dark:text-neutral-400">Announces event and cross-references musician availability</p>
            </div>
          </div>
          <button @click="showAddEventModal = false" class="text-slate-400 hover:text-slate-900 dark:hover:text-white min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer">
            <X class="w-5 h-5" />
          </button>
        </div>

        <form @submit.prevent="saveNewEvent" class="space-y-3.5 text-xs font-bold">
          <div>
            <label for="new-event-title" class="block text-[10px] uppercase text-slate-400 mb-1">Event / Gig Title *</label>
            <input 
              id="new-event-title"
              v-model="newEventForm.title" 
              type="text" 
              placeholder="e.g., Grand Fiesta Procession - Sta. Maria" 
              required
              class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[42px]"
            />
          </div>

          <div>
            <label for="new-event-type" class="block text-[10px] uppercase text-slate-400 mb-1">Event Category *</label>
            <select 
              id="new-event-type"
              v-model="newEventForm.event_type" 
              class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[42px]"
            >
              <option value="Practice & Rehearsal (Ensayo)">Practice & Rehearsal (Ensayo)</option>
              <option value="Civic Parade (Parada)">Civic Parade (Parada)</option>
              <option value="Feast Procession (Prusisyon)">Feast Procession (Prusisyon)</option>
              <option value="Funeral March (Libing)">Funeral March (Libing)</option>
              <option value="Wake & Vigil (Bantay / Lamay)">Wake & Vigil (Bantay / Lamay)</option>
              <option value="Band Meeting (Pulong)">Band Meeting (Pulong)</option>
            </select>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label for="new-event-date" class="block text-[10px] uppercase text-slate-400 mb-1">Date & Time *</label>
              <input 
                id="new-event-date"
                v-model="newEventForm.event_date" 
                type="datetime-local" 
                required
                class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-2.5 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[42px]"
              />
            </div>
            <div>
              <label for="new-event-budget" class="block text-[10px] uppercase text-slate-400 mb-1">Budget / Compensation (₱)</label>
              <input 
                id="new-event-budget"
                v-model.number="newEventForm.budget_estimate" 
                type="number" 
                min="0"
                step="50"
                placeholder="0.00" 
                class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-2.5 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[42px]"
              />
            </div>
          </div>

          <div>
            <label for="new-event-loc" class="block text-[10px] uppercase text-slate-400 mb-1">Location & Assembly Point *</label>
            <input 
              id="new-event-loc"
              v-model="newEventForm.location" 
              type="text" 
              placeholder="e.g., Town Plaza Gazebo / Bandhouse" 
              required
              class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[42px]"
            />
          </div>

          <div class="flex space-x-2 pt-2 border-t border-slate-100 dark:border-neutral-800">
            <button 
              @click="showAddEventModal = false" 
              type="button" 
              class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 cursor-pointer min-h-[44px]"
            >
              Cancel
            </button>
            <button 
              type="submit" 
              :disabled="isSavingEvent"
              class="flex-1 py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md cursor-pointer disabled:opacity-50 min-h-[44px]"
            >
              {{ isSavingEvent ? 'Announcing...' : 'Save & Announce Gig' }}
            </button>
          </div>
        </form>
      </div>
    </div>

  </div>
</template>
