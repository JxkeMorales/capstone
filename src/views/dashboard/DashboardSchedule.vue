<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { Calendar, MapPin, Clock, Filter, CheckCircle2, XCircle, AlertCircle, Plus, Users, X, Trash2, UserCheck, UserX, History, ChevronDown, Download, Send, RefreshCw } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useUIStore } from '@/stores/ui'
import { supabase } from '@/supabase'
import { initRealtimeSync, broadcastSync } from '@/utils/realtime'
import { generateEventAttendancePdf } from '@/utils/pdfExport'
import { sendPushNotification } from '@/utils/push'

const store = useMainStore()
const uiStore = useUIStore()

const currentMonthName = computed(() => {
  return new Date().toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
})
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
const loadError = ref(null)

// Realtime Sync References
let pollTimer = null

// Global Toast Notification Helper
const showToastNotification = (msg, type = 'info') => {
  uiStore.addToast({
    title: 'Schedule Alert',
    message: msg,
    type: type === 'error' ? 'error' : msg.startsWith('✓') ? 'success' : 'info'
  })
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
  location: ''
})

// IT Expert Recommendation (P[1133] & P[1148]): Past Date Prevention Validation
const minDateTimeNow = computed(() => new Date(Date.now() - 60000).toISOString().slice(0, 16))

const saveNewEvent = async () => {
  if (!newEventForm.value.title.trim() || !newEventForm.value.event_date || !newEventForm.value.location.trim()) {
    showToastNotification('Please enter event title, date/time, and location.', 'error')
    return
  }

  // Validate date is not in the past
  if (new Date(newEventForm.value.event_date).getTime() < Date.now() - 120000) {
    showToastNotification('Event date cannot be in the past. Please select today or a future date.', 'error')
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
        location: newEventForm.value.location.trim()
      })
      .select()
      .single()

    if (error) throw error

    const savedTitle = newEventForm.value.title.trim()
    const savedType = newEventForm.value.event_type
    const savedDate = new Date(newEventForm.value.event_date).toLocaleDateString()

    showToastNotification('✓ New gig scheduled & announced to all musicians!')
    showAddEventModal.value = false
    newEventForm.value = {
      title: '',
      event_type: 'Practice & Rehearsal (Ensayo)',
      event_date: '',
      location: ''
    }
    await fetchEvents(true)
    notifyOtherTabs('NEW_EVENT_SCHEDULED')

    // Dispatch background Web Push to closed devices
    sendPushNotification({
      title: `🎷 New Event: ${savedTitle}`,
      message: `${savedType} on ${savedDate}. Please confirm your attendance!`,
      url: '/dashboard/schedule',
      senderId: store.user?.id
    })
  } catch (err) {
    console.error('Error saving event:', err)
    showToastNotification('Failed to schedule event: ' + (err.message || 'Error'), 'error')
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

const myAcceptedEvents = computed(() => {
  const todayStart = getTodayStart()
  return rawEvents.value
    .filter(ev => new Date(ev.rawDate).getTime() >= todayStart && ev.rsvpStatus === 'attending')
    .sort((a, b) => new Date(a.rawDate) - new Date(b.rawDate))
})

const displayedEvents = computed(() => {
  const targetList = activeScheduleTab.value === 'upcoming' 
    ? upcomingEvents.value 
    : activeScheduleTab.value === 'accepted' 
      ? myAcceptedEvents.value 
      : pastEvents.value
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
    loadError.value = null
    const cachedEvents = localStorage.getItem('smartband_schedule_events_cache') || localStorage.getItem('smartband_raw_events_cache')
    if (cachedEvents) {
      try {
        const parsed = JSON.parse(cachedEvents)
        rawEvents.value = parsed.map(ev => ({
          ...ev,
          rsvpStatus: localStorage.getItem(`smartband_rsvp_${ev.id}`) || ev.rsvpStatus || null
        }))
      } catch (e) {}
    }
  }

  try {
    const { data, error } = await supabase
      .from('events')
      .select('*')
      .order('event_date', { ascending: true })

    if (error) throw error

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
          dayNum: dateObj.getDate(),
          createdAt: ev.created_at,
          rsvpStatus: localStorage.getItem(`smartband_rsvp_${ev.id}`) || null
        }
      })
      localStorage.setItem('smartband_schedule_events_cache', JSON.stringify(rawEvents.value))
      localStorage.setItem('smartband_raw_events_cache', JSON.stringify(rawEvents.value))
    }
  } catch (err) {
    console.error('Error fetching events:', err)
    loadError.value = 'Failed to load schedule from server. Please verify your connection.'
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
      rsvps.forEach(r => rsvpMap.set(r.user_id, { 
        status: r.status, 
        excuse: localStorage.getItem(`smartband_rsvp_excuse_${r.event_id || ev.id}`) || null 
      }))
    }

    rollCallRoster.value = (members || []).map(m => {
      const record = rsvpMap.get(m.id)
      const st = record?.status || 'none'
      const excuse = record?.excuse || null
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
        excuseJustification: excuse,
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

// EXPORT MINIMAL OFFICIAL ATTENDANCE PDF FOR THIS SPECIFIC EVENT
const isExportingAttendancePdf = ref(false)
const handleExportAttendancePdf = async () => {
  if (!selectedEventForAttendance.value || isExportingAttendancePdf.value) return
  isExportingAttendancePdf.value = true
  try {
    const filename = await generateEventAttendancePdf({
      event: selectedEventForAttendance.value,
      roster: rollCallRoster.value,
      preparedByName: store.profile?.full_name || 'Band Secretary'
    })
    showToastNotification(`✓ Downloaded ${filename}`)
  } catch (err) {
    console.error('Attendance export error:', err)
    showToastNotification('Failed to export attendance PDF.')
  } finally {
    isExportingAttendancePdf.value = false
  }
}

// ALERT UNCONFIRMED MEMBERS FOR THIS SPECIFIC EVENT
const isAlertingEventUnconfirmed = ref(false)

const alertUnconfirmedForEvent = async () => {
  if (!selectedEventForAttendance.value || isAlertingEventUnconfirmed.value) return
  isAlertingEventUnconfirmed.value = true

  const ev = selectedEventForAttendance.value
  const alertTitle = `🚨 Urgent Attendance Reminder: ${ev.title}`
  const alertMsg = `Please confirm if you are attending or not attending for ${ev.title} on ${ev.date || 'upcoming schedule'} at ${ev.location || 'designated venue'}.`
  const senderName = store.profile?.full_name || 'Band Secretary'

  try {
    // 1. Direct real-time WebSocket broadcast to all connected members and remote devices
    try {
      const alertChan = supabase.channel('smartband-broadcast-alerts', { config: { broadcast: { ack: true } } })
      const broadcastPayload = {
        title: alertTitle,
        message: alertMsg,
        sender: senderName,
        senderId: store.user?.id || null
      }

      if (alertChan.state === 'joined') {
        await alertChan.send({ type: 'broadcast', event: 'rsvp_reminder', payload: broadcastPayload })
      } else {
        await new Promise((resolve) => {
          let done = false
          alertChan.subscribe(async (status) => {
            if (status === 'SUBSCRIBED' && !done) {
              done = true
              await alertChan.send({ type: 'broadcast', event: 'rsvp_reminder', payload: broadcastPayload })
              resolve()
            }
          })
          setTimeout(() => {
            if (!done) {
              done = true
              resolve()
            }
          }, 2000)
        })
      }
    } catch (e) {
      console.warn('Realtime broadcast notice:', e)
    }

    // 2. Create official announcement for activity feed and offline members
    try {
      await supabase.from('announcements').insert({
        author_id: store.user?.id || null,
        title: alertTitle,
        content: alertMsg,
        category: 'Urgent Call-to-Action'
      })
    } catch (e) {}

    // 3. Dispatch background Web Push to closed devices (phones/PCs)
    sendPushNotification({
      title: alertTitle,
      message: alertMsg,
      url: '/dashboard/schedule',
      senderId: store.user?.id
    })

    showToastNotification(`✓ Attendance reminder sent to ${attendanceCounts.value.unconfirmed} pending members!`)
  } catch (err) {
    showToastNotification('Failed to send reminder alerts.')
  } finally {
    isAlertingEventUnconfirmed.value = false
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
    localStorage.setItem('smartband_schedule_events_cache', JSON.stringify(rawEvents.value))
    notifyOtherTabs('EVENT_CHANGED')
    showToastNotification('Event deleted successfully.')
  } catch (err) {
    showToastNotification(`Error: ${err?.message || 'Failed to delete event'}`, 'error')
  } finally {
    showDeleteConfirmModal.value = false
    targetEventIdToDelete.value = null
  }
}

let cleanupSync = null

const handleVisibilityOrFocus = () => {
  if (!document.hidden) {
    fetchEvents(true)
  }
}

const handleLiveScheduleEvent = () => {
  fetchEvents(true)
}

onMounted(() => {
  fetchEvents()

  cleanupSync = initRealtimeSync((event) => {
    fetchEvents(true)
    if (showAttendanceModal.value && selectedEventForAttendance.value) {
      openAttendanceTracker(selectedEventForAttendance.value)
    }
  })

  window.addEventListener('smartband_event_changed', handleLiveScheduleEvent)
  window.addEventListener('focus', handleVisibilityOrFocus)
  document.addEventListener('visibilitychange', handleVisibilityOrFocus)

  pollTimer = setInterval(() => {
    if (!document.hidden) {
      fetchEvents(true)
    }
  }, 12000)
})

onUnmounted(() => {
  if (cleanupSync) cleanupSync()
  if (pollTimer) clearInterval(pollTimer)
  window.removeEventListener('smartband_event_changed', handleLiveScheduleEvent)
  window.removeEventListener('focus', handleVisibilityOrFocus)
  document.removeEventListener('visibilitychange', handleVisibilityOrFocus)
})
</script>

<template>
  <div class="space-y-6 relative">

    <header class="pt-1 flex items-center justify-between gap-3 mb-2">
      <div>
        <p class="text-xs font-medium text-[var(--md-on-surface-variant)]">Calendar &amp; Logs</p>
        <h1 class="text-xl sm:text-2xl font-bold text-[var(--md-on-surface)] tracking-tight">Schedule &amp; Events</h1>
      </div>

      <!-- Schedule New Gig Button for Secretary & Admin (M3 Filled Button - 44px) -->
      <button 
        v-if="store.canManageEvents" 
        @click="showAddEventModal = true"
        type="button"
        aria-haspopup="dialog"
        :aria-expanded="showAddEventModal"
        class="m3-btn-filled min-h-[44px] text-xs font-semibold px-4 sm:px-5 shrink-0"
      >
        <Plus class="w-4 h-4 mr-1.5" />
        <span>Schedule Gig</span>
      </button>
    </header>

    <!-- Schedule Tab Switcher & Filter Row -->
    <div class="flex items-center gap-2">
      <!-- 3-Segment Switcher (Grid cols 3, flex-1) -->
      <div class="grid grid-cols-3 flex-1 p-1 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 text-xs font-medium">
        <button 
          @click="activeScheduleTab = 'upcoming'"
          type="button"
          class="py-2.5 px-1 rounded-xl transition-all cursor-pointer min-h-[44px] flex items-center justify-center text-center"
          :class="activeScheduleTab === 'upcoming' 
            ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
            : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
        >
          <Calendar class="w-3.5 h-3.5 mr-1 text-[var(--md-primary)] shrink-0" />
          <span class="truncate">Upcoming ({{ upcomingEvents.length }})</span>
        </button>

        <button 
          @click="activeScheduleTab = 'accepted'"
          type="button"
          class="py-2.5 px-1 rounded-xl transition-all cursor-pointer min-h-[44px] flex items-center justify-center text-center"
          :class="activeScheduleTab === 'accepted' 
            ? 'bg-[var(--md-surface)] text-emerald-700 dark:text-emerald-400 shadow-xs font-semibold' 
            : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
        >
          <CheckCircle2 class="w-3.5 h-3.5 mr-1 text-emerald-700 dark:text-emerald-400 shrink-0" />
          <span class="truncate">Attending ({{ myAcceptedEvents.length }})</span>
        </button>

        <button 
          @click="activeScheduleTab = 'past'"
          type="button"
          class="py-2.5 px-1 rounded-xl transition-all cursor-pointer min-h-[44px] flex items-center justify-center text-center"
          :class="activeScheduleTab === 'past' 
            ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
            : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
        >
          <History class="w-3.5 h-3.5 mr-1 text-[var(--md-outline)] shrink-0" />
          <span class="truncate">Past ({{ pastEvents.length }})</span>
        </button>
      </div>

      <!-- Filter Button -->
      <div class="relative inline-block shrink-0">
        <button 
          @click="openFilter"
          type="button"
          class="flex items-center space-x-1.5 px-3.5 sm:px-4 py-2 bg-[var(--md-surface-container)] hover:bg-[var(--md-surface-container-high)] border border-[var(--md-outline-variant)]/40 rounded-2xl text-[var(--md-on-surface)] transition-all text-xs font-medium min-h-[44px] cursor-pointer shadow-xs"
          aria-label="Filter Events"
        >
          <Filter class="w-4 h-4" :class="{ 'text-[var(--md-primary)]': !activeFilters.includes('All') }" />
          <span class="hidden sm:inline">Filter</span>
          <span v-if="!activeFilters.includes('All')" class="w-2 h-2 bg-[var(--md-primary)] rounded-full"></span>
        </button>

        <!-- Filter Dropdown Menu -->
        <div v-if="showFilterMenu" class="absolute right-0 mt-2 w-64 bg-[var(--md-surface-container-high)] rounded-2xl shadow-xl border border-[var(--md-outline-variant)]/60 overflow-hidden z-50 p-2">
          <div class="px-3 py-2 border-b border-[var(--md-outline-variant)]/30">
            <p class="text-xs font-semibold text-[var(--md-on-surface)]">Filter by Category</p>
          </div>
          <div class="max-h-60 overflow-y-auto p-1 space-y-1">
            <label 
              v-for="filter in filterCategories" 
              :key="filter"
              class="flex items-center space-x-2.5 px-3 py-2.5 rounded-xl hover:bg-[var(--md-surface-container)] cursor-pointer transition-colors"
            >
              <input 
                type="checkbox" 
                :checked="tempFilters.includes(filter)"
                @change="toggleTempFilter(filter)"
                class="w-4 h-4 rounded border-[var(--md-outline)] text-[var(--md-primary)] focus:ring-0 cursor-pointer"
              >
              <span class="text-xs font-medium text-[var(--md-on-surface)]">{{ filter === 'All' ? 'Select All' : filter }}</span>
            </label>
          </div>
          <div class="p-2 border-t border-[var(--md-outline-variant)]/30 flex items-center justify-end space-x-2">
            <button @click="showFilterMenu = false" type="button" class="m3-btn-text text-xs min-h-[40px] px-3">Cancel</button>
            <button @click="applyFilters" type="button" class="m3-btn-filled text-xs min-h-[40px] px-4">Apply</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Events List -->
    <section class="space-y-3" aria-label="Events Feed">
      <!-- 1. Skeleton Loading State (Item 20) -->
      <div v-if="isLoading" class="space-y-3">
        <div v-for="i in 3" :key="i" class="m3-card-elevated p-5 space-y-3.5 border border-[var(--md-outline-variant)]/40 animate-pulse">
          <div class="flex justify-between items-start">
            <div class="space-y-2 flex-1">
              <div class="h-5 w-24 bg-slate-200 dark:bg-neutral-800 rounded-md"></div>
              <div class="h-5 bg-slate-200 dark:bg-neutral-800 rounded w-1/2"></div>
            </div>
            <div class="h-8 w-28 bg-slate-200 dark:bg-neutral-800 rounded-full shrink-0"></div>
          </div>
          <div class="grid grid-cols-2 gap-2 bg-[var(--md-surface-container)] p-3 rounded-2xl border border-[var(--md-outline-variant)]/30">
            <div class="h-4 bg-slate-200 dark:bg-neutral-800 rounded w-3/4"></div>
            <div class="h-4 bg-slate-200 dark:bg-neutral-800 rounded w-1/2"></div>
            <div class="col-span-2 h-4 bg-slate-200 dark:bg-neutral-800 rounded w-2/3"></div>
          </div>
        </div>
      </div>

      <!-- 2. Error State with Retry CTA (Item 21) -->
      <div v-else-if="loadError" class="m3-card-outlined p-8 text-center space-y-3 border-rose-300 dark:border-rose-900/50">
        <AlertCircle class="w-8 h-8 text-rose-600 dark:text-rose-400 mx-auto" />
        <h3 class="text-sm font-bold text-slate-900 dark:text-neutral-100">Unable to Load Schedule</h3>
        <p class="text-xs text-slate-600 dark:text-neutral-400 max-w-sm mx-auto">{{ loadError }}</p>
        <button @click="fetchEvents(true)" type="button" class="m3-btn-filled text-xs min-h-[40px] px-5 inline-flex items-center mx-auto">
          <RefreshCw class="w-3.5 h-3.5 mr-1.5" /> Retry Connection
        </button>
      </div>

      <!-- 3. Events List -->
      <div v-else-if="displayedEvents.length > 0" class="space-y-3">
        <div 
          v-for="ev in displayedEvents" 
          :key="ev.id"
          class="m3-card-elevated p-5 space-y-3.5 border border-[var(--md-outline-variant)]/40 hover:shadow-md transition-all"
        >
          <div class="flex flex-col sm:flex-row sm:items-start justify-between gap-2.5">
            <div class="min-w-0 flex-1">
              <div class="flex items-center space-x-1.5">
                <span class="m3-chip m3-chip-assist h-7 text-xs px-3">
                  {{ ev.type }}
                </span>
                <span v-if="activeScheduleTab === 'past'" class="m3-chip m3-chip-neutral h-7 text-xs px-3">
                  Completed
                </span>
              </div>
              <h2 class="font-bold text-base text-[var(--md-on-surface)] mt-1 leading-snug">{{ ev.title }}</h2>
            </div>
            
            <div class="flex items-center space-x-1.5 self-end sm:self-auto shrink-0">
              <!-- Secretary Attendance Tracker & Attendance Check Trigger -->
              <button 
                v-if="store.canConductRollCall || store.canManageEvents" 
                @click="openAttendanceTracker(ev)" 
                type="button" 
                class="m3-btn-tonal text-xs px-3.5 min-h-[44px] flex items-center"
                aria-label="Attendance Check"
              >
                <Users class="w-4 h-4 mr-1.5" /> Attendance Check
              </button>

              <!-- Secretary / Admin Delete Button -->
              <button 
                v-if="store.canManageEvents" 
                @click="promptDeleteEvent(ev.id)" 
                type="button" 
                class="p-2 rounded-full text-[var(--md-outline)] hover:text-rose-600 dark:hover:text-rose-400 hover:bg-[var(--md-surface-container-high)] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer transition-colors"
                title="Delete Event"
              >
                <Trash2 class="w-4 h-4" />
              </button>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-2 text-xs font-medium text-[var(--md-on-surface-variant)] bg-[var(--md-surface-container)] p-3 rounded-2xl border border-[var(--md-outline-variant)]/30">
            <div class="flex items-center"><Calendar class="w-3.5 h-3.5 mr-1.5 text-[var(--md-outline)]" /> {{ ev.date }}</div>
            <div class="flex items-center"><Clock class="w-3.5 h-3.5 mr-1.5 text-[var(--md-outline)]" /> {{ ev.time }}</div>
            <div class="col-span-2 flex items-center"><MapPin class="w-3.5 h-3.5 mr-1.5 text-[var(--md-outline)]" /> {{ ev.location }}</div>
          </div>
        </div>
      </div>

      <!-- 4. Empty State with CTA (Item 22) -->
      <div v-else class="m3-card-outlined p-8 text-center space-y-3">
        <div class="w-12 h-12 rounded-full bg-[var(--md-surface-container)] flex items-center justify-center mx-auto text-[var(--md-outline)]">
          <Calendar class="w-6 h-6" />
        </div>
        <div>
          <h3 class="text-sm font-bold text-[var(--md-on-surface)]">
            {{ activeScheduleTab === 'upcoming' ? 'No Upcoming Events Scheduled' : activeScheduleTab === 'accepted' ? 'No Accepted Events' : 'No Past Events Found' }}
          </h3>
          <p class="text-xs text-[var(--md-on-surface-variant)] mt-1 max-w-sm mx-auto">
            {{ activeScheduleTab === 'upcoming' ? 'New rehearsals, church gigs, and parades will appear here once scheduled.' : activeScheduleTab === 'accepted' ? 'RSVP "Attending" to any upcoming gig to add it to your personal schedule.' : 'Archived historical events will appear after completion.' }}
          </p>
        </div>
        <button 
          v-if="store.canManageEvents && activeScheduleTab === 'upcoming'" 
          @click="showAddEventModal = true" 
          type="button" 
          class="m3-btn-filled text-xs min-h-[40px] px-5 inline-flex items-center mx-auto"
        >
          <Plus class="w-3.5 h-3.5 mr-1.5" /> Schedule New Event
        </button>
        <button 
          v-else-if="activeScheduleTab === 'accepted'"
          @click="activeScheduleTab = 'upcoming'"
          type="button"
          class="m3-btn-filled text-xs min-h-[40px] px-5 inline-flex items-center mx-auto"
        >
          Browse Upcoming Events
        </button>
        <button 
          v-else 
          @click="fetchEvents(true)" 
          type="button" 
          class="m3-btn-outlined text-xs min-h-[40px] px-5 inline-flex items-center mx-auto"
        >
          <RefreshCw class="w-3.5 h-3.5 mr-1.5" /> Refresh Schedule
        </button>
      </div>
    </section>

    <!-- SECRETARY / ADMIN EVENT ATTENDANCE CHECK MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showAttendanceModal" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="attendance-modal-title"
      @keydown.escape="showAttendanceModal = false"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-3 sm:p-4"
    >
      <div class="m3-surface-modal p-4 sm:p-6 max-w-md sm:max-w-lg w-full space-y-4 shadow-xl text-left max-h-[90vh] flex flex-col">
        
        <!-- Modal Header -->
        <div class="flex items-start justify-between border-b border-[var(--md-outline-variant)]/40 pb-3">
          <div class="min-w-0 pr-2">
            <div class="flex items-center space-x-1.5 mb-1">
              <span class="m3-chip m3-chip-assist h-7 text-xs px-3">
                {{ selectedEventForAttendance?.type || 'Event' }}
              </span>
              <span class="text-[10px] text-[var(--md-outline)] font-medium">Attendance Check Log</span>
            </div>
            <h3 id="attendance-modal-title" class="font-bold text-base text-[var(--md-on-surface)] truncate">
              {{ selectedEventForAttendance?.title }}
            </h3>
            <p class="text-xs text-[var(--md-on-surface-variant)] mt-0.5">
              {{ selectedEventForAttendance?.date }} at {{ selectedEventForAttendance?.time }} • {{ selectedEventForAttendance?.location }}
            </p>
          </div>
          <button @click="showAttendanceModal = false" type="button" class="text-[var(--md-outline)] hover:text-[var(--md-on-surface)] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer rounded-full hover:bg-[var(--md-surface-container)]" aria-label="Close modal">
            <X class="w-5 h-5" />
          </button>
        </div>

        <!-- Quick Summary Metrics & Batch Action -->
        <div class="bg-[var(--md-surface-container)] p-3.5 rounded-2xl border border-[var(--md-outline-variant)]/40 space-y-3">
          <div class="flex items-center justify-between text-xs">
            <span class="font-semibold text-[var(--md-on-surface)]">Turnout Tally</span>
            <div class="flex items-center space-x-2 font-medium text-[11px]">
              <span class="text-emerald-700 dark:text-emerald-400 font-semibold">{{ attendanceCounts.present }} Present</span>
              <span>•</span>
              <span class="text-rose-600 dark:text-rose-400 font-semibold">{{ attendanceCounts.absent }} Absent</span>
              <span>•</span>
              <span class="text-amber-800 dark:text-amber-400 font-semibold">{{ attendanceCounts.excused }} Excused</span>
            </div>
          </div>

          <div class="flex items-center gap-2">
            <button 
              v-if="store.canConductRollCall"
              @click="markAllAttendingAsPresent" 
              :disabled="isBatchMarking"
              type="button" 
              class="m3-btn-filled text-xs flex-1 min-h-[44px]"
            >
              <CheckCircle2 class="w-4 h-4 mr-1.5" />
              <span>{{ isBatchMarking ? 'Updating...' : 'Mark Attending as Present' }}</span>
            </button>

            <button 
              v-if="store.canConductRollCall && attendanceCounts.unconfirmed > 0"
              @click="alertUnconfirmedForEvent"
              :disabled="isAlertingEventUnconfirmed"
              type="button" 
              class="m3-btn-tonal text-xs font-semibold min-h-[44px] px-3.5 bg-amber-500/15 text-amber-800 dark:text-amber-300 border border-amber-500/30"
              title="Send attendance reminder to pending members for this event"
            >
              <Send class="w-4 h-4 mr-1.5" />
              <span>{{ isAlertingEventUnconfirmed ? 'Alerting...' : `Remind (${attendanceCounts.unconfirmed})` }}</span>
            </button>

            <button 
              @click="handleExportAttendancePdf"
              :disabled="isExportingAttendancePdf"
              type="button" 
              class="m3-btn-outlined text-xs min-h-[44px] px-3.5 shrink-0"
              title="Export official printable attendance sheet PDF"
            >
              <Download class="w-4 h-4 mr-1.5" />
              <span>{{ isExportingAttendancePdf ? 'Exporting...' : 'Export PDF' }}</span>
            </button>
          </div>
        </div>

        <!-- Filter Sub-Tabs (Pill Chips) -->
        <div class="flex items-center space-x-1 p-1 bg-[var(--md-surface-container)] rounded-full text-xs font-medium overflow-x-auto border border-[var(--md-outline-variant)]/40">
          <button 
            @click="attendanceTabFilter = 'all'"
            type="button"
            class="px-3.5 py-2 rounded-full transition-all whitespace-nowrap cursor-pointer min-h-[38px]"
            :class="attendanceTabFilter === 'all' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            All ({{ attendanceCounts.total }})
          </button>
          <button 
            @click="attendanceTabFilter = 'attending'"
            type="button"
            class="px-3.5 py-2 rounded-full transition-all whitespace-nowrap cursor-pointer min-h-[38px]"
            :class="attendanceTabFilter === 'attending' ? 'bg-[var(--md-surface)] text-emerald-700 dark:text-emerald-400 shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Attending ({{ attendanceCounts.attending }})
          </button>
          <button 
            @click="attendanceTabFilter = 'declined'"
            type="button"
            class="px-3.5 py-2 rounded-full transition-all whitespace-nowrap cursor-pointer min-h-[38px]"
            :class="attendanceTabFilter === 'declined' ? 'bg-[var(--md-surface)] text-rose-600 dark:text-rose-400 shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Declined ({{ attendanceCounts.declined }})
          </button>
          <button 
            @click="attendanceTabFilter = 'unconfirmed'"
            type="button"
            class="px-3.5 py-2 rounded-full transition-all whitespace-nowrap cursor-pointer min-h-[38px]"
            :class="attendanceTabFilter === 'unconfirmed' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Pending ({{ attendanceCounts.unconfirmed }})
          </button>
        </div>

        <!-- Attendance Roster List -->
        <div v-if="isLoadingAttendance" class="py-12 text-center text-xs font-medium text-[var(--md-outline)]">
          Loading band attendance roster...
        </div>

        <div v-else class="overflow-y-auto flex-1 space-y-2 pr-1">
          <div 
            v-for="member in filteredRollCallRoster" 
            :key="member.userId"
            class="p-3 bg-[var(--md-surface)] rounded-2xl border border-[var(--md-outline-variant)]/60 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2.5 shadow-xs transition-colors"
          >
            <!-- Member Details -->
            <div class="flex items-center space-x-2.5 min-w-0">
              <div class="w-9 h-9 rounded-full overflow-hidden bg-[var(--md-surface-container)] text-[var(--md-on-surface)] flex items-center justify-center font-bold text-xs flex-shrink-0 border border-[var(--md-outline-variant)]">
                <img v-if="member.profile_picture" :src="member.profile_picture" alt="" width="36" height="36" loading="lazy" class="w-full h-full object-cover" />
                <span v-else>{{ member.avatar }}</span>
              </div>
              <div class="min-w-0">
                <p class="font-semibold text-xs text-[var(--md-on-surface)] truncate">
                  {{ member.name }}
                </p>
                <div class="flex items-center space-x-1.5 mt-0.5">
                  <span class="text-[11px] text-[var(--md-on-surface-variant)] capitalize">
                    {{ member.instrument }}
                  </span>
                  <span>•</span>
                  <!-- Initial Attendance Status Tag -->
                  <span 
                    class="text-[10px] font-medium px-2 py-0.5 rounded-full"
                    :class="{
                      'bg-emerald-500/15 text-emerald-700 dark:text-emerald-400': member.initialRsvp === 'attending',
                      'bg-[var(--md-surface-container)] text-[var(--md-on-surface-variant)]': member.initialRsvp === 'declined',
                      'bg-amber-500/15 text-amber-800 dark:text-amber-300': member.initialRsvp === 'none'
                    }"
                  >
                    {{ member.initialRsvp === 'attending' ? 'Attending' : member.initialRsvp === 'declined' ? 'Declined' : 'Pending' }}
                  </span>
                </div>
                <!-- Excuse Justification (Table 19) -->
                <p v-if="member.excuseJustification" class="text-[10px] text-amber-700 dark:text-amber-400 italic truncate max-w-[220px] mt-0.5" :title="member.excuseJustification">
                  Excuse: {{ member.excuseJustification }}
                </p>
              </div>
            </div>

            <!-- Attendance Action Controls (WCAG 44px Touch Targets) -->
            <div v-if="store.canConductRollCall" class="flex items-center space-x-1.5 flex-shrink-0 self-end sm:self-center">
              <!-- Present Button -->
              <button 
                @click="setMemberAttendance(member, 'present')"
                :disabled="member.isSaving"
                type="button"
                class="px-3 py-2 rounded-full text-xs font-semibold transition-all cursor-pointer min-h-[44px] flex items-center"
                :class="member.currentStatus === 'present' 
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900 shadow-xs' 
                  : 'bg-[var(--md-surface-container)] text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)]'"
                title="Mark Present"
              >
                <CheckCircle2 class="w-3.5 h-3.5 mr-1 text-emerald-500" /> Present
              </button>

              <!-- Absent Button -->
              <button 
                @click="setMemberAttendance(member, 'absent')"
                :disabled="member.isSaving"
                type="button"
                class="px-3 py-2 rounded-full text-xs font-semibold transition-all cursor-pointer min-h-[44px] flex items-center"
                :class="member.currentStatus === 'absent' 
                  ? 'bg-rose-600 text-white shadow-xs' 
                  : 'bg-[var(--md-surface-container)] text-[var(--md-on-surface-variant)] hover:bg-rose-50 hover:text-rose-700 dark:hover:bg-rose-950/40'"
                title="Mark Absent"
              >
                <XCircle class="w-3.5 h-3.5 mr-1" /> Absent
              </button>

              <!-- Excused Button -->
              <button 
                @click="setMemberAttendance(member, 'excused')"
                :disabled="member.isSaving"
                type="button"
                class="px-3 py-2 rounded-full text-xs font-semibold transition-all cursor-pointer min-h-[44px] flex items-center"
                :class="member.currentStatus === 'excused' 
                  ? 'bg-amber-600 text-white shadow-xs' 
                  : 'bg-[var(--md-surface-container)] text-[var(--md-on-surface-variant)] hover:bg-amber-50 hover:text-amber-700 dark:hover:bg-amber-950/40'"
                title="Mark Excused Absence"
              >
                Excused
              </button>
            </div>

            <!-- Read-Only Status Tag for Regular Viewers -->
            <div v-else class="flex items-center space-x-1">
              <span 
                class="px-2.5 py-0.5 rounded-full text-[10px] font-medium capitalize"
                :class="{
                  'bg-emerald-500/15 text-emerald-700 dark:text-emerald-300': member.currentStatus === 'present',
                  'bg-rose-500/15 text-rose-700 dark:text-rose-300': member.currentStatus === 'absent',
                  'bg-amber-500/15 text-amber-700 dark:text-amber-300': member.currentStatus === 'excused',
                  'bg-[var(--md-surface-container)] text-[var(--md-on-surface-variant)]': !['present', 'absent', 'excused'].includes(member.currentStatus)
                }"
              >
                {{ member.currentStatus }}
              </span>
            </div>

          </div>

          <div v-if="filteredRollCallRoster.length === 0" class="py-8 text-center text-xs text-[var(--md-outline)]">
            No musicians match this filter category.
          </div>
        </div>

        <div class="pt-3 border-t border-[var(--md-outline-variant)]/40 flex justify-end">
          <button 
            @click="showAttendanceModal = false" 
            type="button" 
            class="m3-btn-filled w-full min-h-[48px] text-xs font-semibold"
          >
            Close Roster
          </button>
        </div>
      </div>
    </div>

    <!-- DELETE CONFIRM MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showDeleteConfirmModal" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="delete-event-modal-title"
      @keydown.escape="showDeleteConfirmModal = false; targetEventIdToDelete = null"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4"
    >
      <div class="m3-surface-modal p-6 max-w-sm w-full space-y-4 shadow-xl text-center">
        <div class="w-12 h-12 rounded-full bg-rose-500/15 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        <div>
          <h3 id="delete-event-modal-title" class="font-bold text-base text-[var(--md-on-surface)] leading-tight">Delete Event?</h3>
          <p class="text-xs text-[var(--md-on-surface-variant)] mt-1 leading-relaxed">
            Are you sure you want to delete this scheduled event?
          </p>
        </div>
        <div class="flex space-x-2 pt-2">
          <button @click="showDeleteConfirmModal = false; targetEventIdToDelete = null" type="button" class="m3-btn-outlined flex-1 min-h-[48px]">Cancel</button>
          <button @click="executeDeleteEvent" type="button" class="m3-btn-filled flex-1 min-h-[48px] bg-rose-600 hover:bg-rose-700 text-white">Delete</button>
        </div>
      </div>
    </div>

    <!-- SCHEDULE NEW GIG MODAL (Secretary & Admin) (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showAddEventModal" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-event-modal-title"
      @keydown.escape="showAddEventModal = false"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-3 sm:p-4"
    >
      <div class="m3-surface-modal p-6 max-w-md w-full space-y-4 shadow-xl text-left">
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/40 pb-3">
          <div class="flex items-center space-x-2">
            <Calendar class="w-5 h-5 text-[var(--md-primary)]" />
            <div>
              <h3 id="add-event-modal-title" class="font-bold text-base text-[var(--md-on-surface)] leading-tight">Schedule Band Gig</h3>
              <p class="text-[11px] text-[var(--md-on-surface-variant)]">Announces event and cross-references musician availability</p>
            </div>
          </div>
          <button @click="showAddEventModal = false" type="button" class="text-[var(--md-outline)] hover:text-[var(--md-on-surface)] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer rounded-full hover:bg-[var(--md-surface-container)]" aria-label="Close modal">
            <X class="w-5 h-5" />
          </button>
        </div>

        <form @submit.prevent="saveNewEvent" class="space-y-3.5 text-xs">
          <div>
            <label for="new-event-title" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Event / Gig Title *</label>
            <input 
              id="new-event-title"
              v-model="newEventForm.title" 
              type="text" 
              placeholder="e.g., Grand Fiesta Procession - Sta. Maria" 
              required
              class="w-full bg-[var(--md-surface-container)] text-[var(--md-on-surface)] rounded-xl p-3 border border-[var(--md-outline-variant)] text-xs min-h-[48px] focus:outline-none focus:border-[var(--md-outline)]"
            />
          </div>

          <div>
            <label for="new-event-type" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Event Category *</label>
            <select 
              id="new-event-type"
              v-model="newEventForm.event_type" 
              class="w-full bg-[var(--md-surface-container)] text-[var(--md-on-surface)] rounded-xl p-3 border border-[var(--md-outline-variant)] text-xs min-h-[48px] focus:outline-none focus:border-[var(--md-outline)] cursor-pointer"
            >
              <option value="Practice & Rehearsal (Ensayo)">Practice &amp; Rehearsal (Ensayo)</option>
              <option value="Civic Parade (Parada)">Civic Parade (Parada)</option>
              <option value="Feast Procession (Prusisyon)">Feast Procession (Prusisyon)</option>
              <option value="Funeral March (Libing)">Funeral March (Libing)</option>
              <option value="Wake & Vigil (Bantay / Lamay)">Wake &amp; Vigil (Bantay / Lamay)</option>
              <option value="Band Meeting (Pulong)">Band Meeting (Pulong)</option>
            </select>
          </div>

          <div>
            <label for="new-event-date" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Date &amp; Time *</label>
            <input 
              id="new-event-date"
              v-model="newEventForm.event_date" 
              type="datetime-local" 
              :min="minDateTimeNow"
              required
              class="w-full bg-[var(--md-surface-container)] text-[var(--md-on-surface)] rounded-xl p-3 border border-[var(--md-outline-variant)] text-xs min-h-[48px] focus:outline-none focus:border-[var(--md-outline)] cursor-pointer"
            />
          </div>

          <div>
            <label for="new-event-loc" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Location &amp; Assembly Point *</label>
            <input 
              id="new-event-loc"
              v-model="newEventForm.location" 
              type="text" 
              placeholder="e.g., Town Plaza Gazebo / Bandhouse" 
              required
              class="w-full bg-[var(--md-surface-container)] text-[var(--md-on-surface)] rounded-xl p-3 border border-[var(--md-outline-variant)] text-xs min-h-[48px] focus:outline-none focus:border-[var(--md-outline)]"
            />
          </div>

          <div class="flex space-x-2 pt-2 border-t border-[var(--md-outline-variant)]/40">
            <button 
              @click="showAddEventModal = false" 
              type="button" 
              class="m3-btn-outlined flex-1 min-h-[48px]"
            >
              Cancel
            </button>
            <button 
              type="submit" 
              :disabled="isSavingEvent"
              class="m3-btn-filled flex-1 min-h-[48px] disabled:opacity-50"
            >
              {{ isSavingEvent ? 'Announcing...' : 'Save & Announce' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
