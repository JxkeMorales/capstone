<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { Calendar, MapPin, CheckCircle, XCircle, Bell, MessageSquare, ShieldCheck, TrendingUp, User, Plus, ShieldAlert, X, AlertCircle, Trash2, Smartphone, FileText, Users, UserCheck, UserX, History, Clock, ChevronRight } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'
import { initRealtimeSync } from '@/utils/realtime'

const store = useMainStore()

const pendingAccounts = ref([])
const rawEvents = ref([])
const announcements = ref([])
const isLoading = ref(true)
const activeEventsTab = ref('upcoming')
const activeAnnouncementTab = ref('recent') // 'upcoming' | 'past'

// Realtime Channel & Sync References
let homeChannel = null
let syncBroadcast = null
let pollTimer = null

// Modal States
const showAnnouncementModal = ref(false)
const showEventModal = ref(false)
const isSubmitting = ref(false)

// Custom Confirm Modal State
const showConfirmModal = ref(false)
const confirmActionType = ref('')
const confirmTargetId = ref(null)

// Toast Notification
const toastMsg = ref('')
const showToast = (msg) => {
  toastMsg.value = msg
  setTimeout(() => { toastMsg.value = '' }, 3500)
}

// Announcement Form
const newAnnTitle = ref('')
const newAnnContent = ref('')

// Event Form
const newEvTitle = ref('')
const newEvType = ref('Ensayo / Practice') 
const newEvDate = ref('')
const newEvTime = ref('14:00')
const newEvLocation = ref('')

const eventTypeOptions = [
  'Practice & Rehearsal (Ensayo)',
  'Wake & Vigil Service (Bantay / Lamay)',
  'Funeral March & Interment (Libing)',
  'Civic Parade & Exhibition (Parada)',
  'Religious Feast Procession (Prusisyon)',
  'Band General Meeting (Pulong)'
]

// AUTOMATIC DATE FILTERING LOGIC
const getTodayStart = () => {
  const d = new Date()
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

// Upcoming events (today or future), sorted by creation date descending (newest posts first) as requested
const upcomingEvents = computed(() => {
  const todayStart = getTodayStart()
  return rawEvents.value
    .filter(ev => new Date(ev.rawDate).getTime() >= todayStart)
    .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0))
})

// Past events (completed), sorted chronologically descending (most recent first)
const recentAnnouncements = computed(() => {
  const sevenDaysAgo = Date.now() - (7 * 24 * 60 * 60 * 1000)
  return announcements.value.filter(a => new Date(a.rawDate).getTime() >= sevenDaysAgo)
})

const archivedAnnouncements = computed(() => {
  const sevenDaysAgo = Date.now() - (7 * 24 * 60 * 60 * 1000)
  return announcements.value.filter(a => new Date(a.rawDate).getTime() < sevenDaysAgo)
})

const displayedAnnouncements = computed(() => {
  return activeAnnouncementTab.value === 'recent' ? recentAnnouncements.value : archivedAnnouncements.value
})

const pastEvents = computed(() => {
  const todayStart = getTodayStart()
  return rawEvents.value
    .filter(ev => new Date(ev.rawDate).getTime() < todayStart)
    .sort((a, b) => new Date(b.rawDate) - new Date(a.rawDate))
})

const notifyOtherTabs = (eventType) => {
  if (syncBroadcast) {
    try { syncBroadcast.postMessage({ type: eventType, time: Date.now() }) } catch(e){}
  }
}

const fetchHomeData = async (skipCache = false) => {
  if (!skipCache) {
    isLoading.value = true
    const cachedAnn = localStorage.getItem('smartband_announcements_cache')
    const cachedEv = localStorage.getItem('smartband_raw_events_cache')
    if (cachedAnn) {
      try { announcements.value = JSON.parse(cachedAnn) } catch(e){}
    }
    if (cachedEv) {
      try { rawEvents.value = JSON.parse(cachedEv) } catch(e){}
    }
  }

  try {
    // 1. Fetch all events
    const { data: eventData } = await supabase
      .from('events')
      .select('*')
      .order('created_at', { ascending: false })

    if (eventData) {
      let rsvpMap = {}
      if (store.user) {
        const { data: rsvpData } = await supabase
          .from('event_rsvps')
          .select('event_id, status')
          .eq('user_id', store.user.id)
        if (rsvpData) {
          rsvpData.forEach(r => { rsvpMap[r.event_id] = r.status })
        }
      }

      rawEvents.value = eventData.map(ev => {
        const evDate = new Date(ev.event_date)
        return {
          id: ev.id,
          rawDate: ev.event_date,
          title: ev.title,
          date: evDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }),
          time: evDate.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
          location: ev.location,
          type: ev.event_type,
          rsvpStatus: rsvpMap[ev.id] || null,
          createdAt: ev.created_at
        }
      })
      localStorage.setItem('smartband_raw_events_cache', JSON.stringify(rawEvents.value))
    }

    // 2. Fetch announcements
    const { data: annData } = await supabase
      .from('announcements')
      .select('*, author:profiles(full_name)')
      .order('created_at', { ascending: false })

    if (annData) {
      announcements.value = annData.map(a => ({
        id: a.id,
        author: a.author?.full_name || 'Band Officer',
        date: new Date(a.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
        title: a.title,
        rawDate: a.created_at,
        content: a.content
      }))
      localStorage.setItem('smartband_announcements_cache', JSON.stringify(announcements.value))
    }

    // 3. Fetch pending accounts for Super Admin
    if (store.canApproveAccounts) {
      const { data: pendingData } = await supabase
        .from('profiles')
        .select('*')
        .eq('is_verified', false)
      if (pendingData) pendingAccounts.value = pendingData
    }
  } catch (err) {
    console.error('Error fetching home data:', err)
  } finally {
    isLoading.value = false
  }
}

// Attendance Roll-Call Roster State (Secretary / Admin)
const showAttendanceModal = ref(false)
const selectedEventForAttendance = ref(null)
const rollCallRoster = ref([])
const isLoadingAttendance = ref(false)
const isBatchMarking = ref(false)
const attendanceTabFilter = ref('all') // 'all' | 'attending' | 'declined' | 'unconfirmed'

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

// RECALCULATE MEMBER RELIABILITY SCORE UPON ATTENDANCE UPDATE
const updateMemberReliabilityScore = async (userId) => {
  try {
    const { data: pastRsvps } = await supabase
      .from('event_rsvps')
      .select('status, events(event_date)')
      .eq('user_id', userId)

    if (!pastRsvps) return

    // Flakes: Events where member RSVP'd or was expected, but marked 'absent'
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
    // 1. Fetch all verified roster members
    const { data: members, error: memErr } = await supabase
      .from('profiles')
      .select('id, full_name, instrument, rank, role, profile_picture')
      .eq('is_verified', true)
      .order('full_name', { ascending: true })

    if (memErr) throw memErr

    // 2. Fetch existing RSVPs / roll-call records for this event
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
        currentStatus: st, // 'attending' | 'declined' | 'present' | 'absent' | 'excused' | 'none'
        isSaving: false
      }
    }).sort((a, b) => {
      const order = { attending: 0, declined: 1, none: 2 }
      return (order[a.initialRsvp] ?? 3) - (order[b.initialRsvp] ?? 3)
    })
  } catch (err) {
    console.error('Error fetching attendance roster:', err)
    showToast('Failed to load attendance roster.')
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
    showToast(`✓ Marked ${member.name} as ${newStatus.toUpperCase()}`)
  } catch (err) {
    console.error('Error setting attendance:', err)
    member.currentStatus = prevStatus
    showToast(`Failed to update attendance: ${err.message || 'Database error'}`)
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
      showToast('All attending members are already marked Present.')
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
    showToast(`✓ Marked ${targetMembers.length} attending members as Present!`)
  } catch (err) {
    console.error('Batch attendance error:', err)
    showToast('Failed to batch-update attendance.')
  } finally {
    isBatchMarking.value = false
  }
}

// POST ANNOUNCEMENT WITH INSTANT LOCAL UPDATE + SYNC BROADCAST
const handleCreateAnnouncement = async () => {
  if (!newAnnTitle.value || !newAnnContent.value || !store.user) return
  isSubmitting.value = true

  try {
    const { data, error } = await supabase
      .from('announcements')
      .insert({
        title: newAnnTitle.value.trim(),
        content: newAnnContent.value.trim(),
        author_id: store.user.id
      })
      .select('*, author:profiles(full_name)')
      .single()

    if (error) throw error

    if (data) {
      const newAnn = {
        id: data.id,
        author: data.author?.full_name || store.profile?.full_name || 'Band Officer',
        date: new Date(data.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
        title: data.title,
        content: data.content
      }

      announcements.value = [newAnn, ...announcements.value.filter(a => a.id !== data.id)]
      localStorage.setItem('smartband_announcements_cache', JSON.stringify(announcements.value))

      notifyOtherTabs('ANNOUNCEMENT_CHANGED')

      // Trigger Web Push Notification via Edge Function
      try {
        await supabase.functions.invoke('push-announcement', {
          body: { record: data }
        })
      } catch (pushErr) {
        console.warn('Failed to trigger web push:', pushErr)
      }

      newAnnTitle.value = ''
      newAnnContent.value = ''
      showAnnouncementModal.value = false
      showToast('Announcement posted successfully!')
    }
  } catch (err) {
    console.error('Error creating announcement:', err)
    showToast('Failed to post announcement.')
  } finally {
    isSubmitting.value = false
  }
}

// SCHEDULE EVENT WITH INSTANT LOCAL LIST ADDITION
const handleCreateEvent = async () => {
  if (!newEvTitle.value) {
    showToast('Please enter an event title.')
    return
  }
  if (!newEvDate.value) {
    showToast('Please select an event date.')
    return
  }
  if (!newEvLocation.value) {
    showToast('Please specify a location.')
    return
  }
  if (!store.user) return
  isSubmitting.value = true

  try {
    const fullDateTime = new Date(`${newEvDate.value}T${newEvTime.value}`).toISOString()
    const { data, error } = await supabase
      .from('events')
      .insert({
        title: newEvTitle.value.trim(),
        event_type: newEvType.value,
        event_date: fullDateTime,
        location: newEvLocation.value.trim()
      })
      .select('*')
      .single()

    if (error) throw error

    if (data) {
      const evDate = new Date(data.event_date)
      const newEv = {
        id: data.id,
        rawDate: data.event_date,
        title: data.title,
        date: evDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }),
        time: evDate.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
        location: data.location,
        type: data.event_type,
        rsvpStatus: null,
        createdAt: data.created_at
      }

      rawEvents.value = [...rawEvents.value.filter(e => e.id !== data.id), newEv]
      localStorage.setItem('smartband_raw_events_cache', JSON.stringify(rawEvents.value))

      notifyOtherTabs('EVENT_CHANGED')

      newEvTitle.value = ''
      newEvDate.value = ''
      newEvLocation.value = ''
      showEventModal.value = false
      showToast('Event scheduled successfully!')
    }
  } catch (err) {
    console.error('Error creating event:', err)
    showToast('Failed to schedule event.')
  } finally {
    isSubmitting.value = false
  }
}

const promptDeleteAnnouncement = (id) => {
  confirmActionType.value = 'delete_announcement'
  confirmTargetId.value = id
  showConfirmModal.value = true
}

const promptDeleteEvent = (id) => {
  confirmActionType.value = 'delete_event'
  confirmTargetId.value = id
  showConfirmModal.value = true
}

const promptRejectAccount = (id) => {
  confirmActionType.value = 'reject_account'
  confirmTargetId.value = id
  showConfirmModal.value = true
}

const executeConfirmedAction = async () => {
  const id = confirmTargetId.value
  if (!id) return

  if (confirmActionType.value === 'delete_announcement') {
    const { data, error } = await supabase.from('announcements').delete().eq('id', id).select()
    if (error) {
      showToast(`Error deleting announcement: ${error.message}`)
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    if (!data || data.length === 0) {
      showToast('Could not delete announcement. Database permission denied.')
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    announcements.value = announcements.value.filter(a => a.id !== id)
    localStorage.setItem('smartband_announcements_cache', JSON.stringify(announcements.value))
    notifyOtherTabs('ANNOUNCEMENT_CHANGED')
    showToast('Announcement deleted.')
  } else if (confirmActionType.value === 'delete_event') {
    const { data, error } = await supabase.from('events').delete().eq('id', id).select()
    if (error) {
      showToast(`Error deleting event: ${error.message}`)
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    if (!data || data.length === 0) {
      showToast('Could not delete event. Database permission denied.')
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    rawEvents.value = rawEvents.value.filter(e => e.id !== id)
    localStorage.setItem('smartband_raw_events_cache', JSON.stringify(rawEvents.value))
    notifyOtherTabs('EVENT_CHANGED')
    showToast('Event deleted.')
  } else if (confirmActionType.value === 'reject_account') {
    const { data, error } = await supabase.from('profiles').delete().eq('id', id).select()
    if (error) {
      showToast(`Error declining account: ${error.message}`)
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    if (!data || data.length === 0) {
      showToast('Could not decline account. Database permission denied.')
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    pendingAccounts.value = pendingAccounts.value.filter(a => a.id !== id)
    notifyOtherTabs('PROFILE_CHANGED')
    showToast('Registration declined & erased.')
  }

  showConfirmModal.value = false
  confirmTargetId.value = null
}

const approveAccount = async (id) => {
  const { error } = await supabase.from('profiles').update({ is_verified: true }).eq('id', id)
  if (!error) {
    pendingAccounts.value = pendingAccounts.value.filter(a => a.id !== id)
    notifyOtherTabs('PROFILE_CHANGED')
    showToast('Account approved & verified!')
  }
}

const rsvp = async (eventObj, status) => {
  if (!eventObj || !store.user) return
  const prevStatus = eventObj.rsvpStatus
  eventObj.rsvpStatus = status
  
  localStorage.setItem(`smartband_rsvp_${eventObj.id}`, status)
  
  try {
    const { error } = await supabase
      .from('event_rsvps')
      .upsert(
        {
          event_id: eventObj.id,
          user_id: store.user.id,
          status: status,
          updated_at: new Date().toISOString()
        },
        { onConflict: 'event_id,user_id' }
      )

    if (error) {
      console.error('RSVP upsert error:', error)
      eventObj.rsvpStatus = prevStatus
      throw error
    }

    notifyOtherTabs('RSVP_CHANGED')
    showToast(status === 'attending' ? 'RSVP Confirmed!' : 'RSVP Declined.')

    // If Secretary / Admin attendance modal is open, refresh it immediately!
    if (showAttendanceModal.value && selectedEventForAttendance.value?.id === eventObj.id) {
      openAttendanceTracker(selectedEventForAttendance.value)
    }
  } catch(e) {
    console.error('RSVP error:', e)
    showToast('Failed to update RSVP.')
  }
}

let cleanupSync = null

const handleVisibilityOrFocus = () => {
  if (!document.hidden) {
    fetchHomeData(true)
  }
}

onMounted(() => {
  fetchHomeData()

  // 1. Centralized Master Realtime Sync (WebSockets + Inter-Tab)
  cleanupSync = initRealtimeSync((event) => {
    fetchHomeData(true)
    if (showAttendanceModal.value && selectedEventForAttendance.value) {
      openAttendanceTracker(selectedEventForAttendance.value)
    }
  })

  // 2. Optimized Auto-Polling Fallback (Every 12s, paused if backgrounded)
  pollTimer = setInterval(() => {
    if (!document.hidden) {
      fetchHomeData(true)
    }
  }, 12000)

  window.addEventListener('focus', handleVisibilityOrFocus)
  document.addEventListener('visibilitychange', handleVisibilityOrFocus)
})

onUnmounted(() => {
  if (cleanupSync) cleanupSync()
  if (pollTimer) clearInterval(pollTimer)
  window.removeEventListener('focus', handleVisibilityOrFocus)
  document.removeEventListener('visibilitychange', handleVisibilityOrFocus)
})
</script>

<template>
  <div class="space-y-6 relative">
    
    <!-- Toast Notification -->
    <Transition name="toast">
      <div 
        v-if="toastMsg" 
        class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-xs w-11/12 bg-white dark:bg-[#1c1c1e] text-slate-900 dark:text-white px-4 py-3 rounded-2xl shadow-xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between font-extrabold text-xs"
        role="status"
        aria-live="polite"
      >
        <div class="flex items-center space-x-1">
          <CheckCircle class="w-4 h-4 text-emerald-600 dark:text-emerald-400 flex-shrink-0" />
          <span>{{ toastMsg }}</span>
        </div>
        <button @click="toastMsg = ''" class="ml-2 text-slate-400 dark:text-neutral-500 hover:text-slate-900 dark:hover:text-white min-w-[32px] min-h-[32px] flex items-center justify-center cursor-pointer" aria-label="Close Toast">
          <X class="w-3.5 h-3.5" />
        </button>
      </div>
    </Transition>

    <!-- Clean Header Title -->
    <div class="flex items-center justify-between pt-1">
      <div>
        <p class="text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase tracking-wider">
          {{ store.currentRole === 'super_admin' ? 'IT Super Admin' : store.currentRole === 'secretary_admin' ? 'Band Secretary' : 'Welcome back' }}
        </p>
        <h1 class="text-2xl lg:text-3xl font-black text-slate-900 dark:text-white">Home Dashboard</h1>
      </div>
    </div>

    <!-- PENDING APPROVALS QUEUE (Super Admin Only) -->
    <section v-if="store.canApproveAccounts && pendingAccounts.length > 0" class="bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-900/60 rounded-2xl p-4 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-1">
          <ShieldAlert class="w-5 h-5 text-amber-600 dark:text-amber-400" />
          <h2 class="font-extrabold text-sm text-slate-900 dark:text-amber-200">Pending Master List Approvals</h2>
        </div>
        <span class="text-xs font-black bg-amber-200 dark:bg-amber-900/80 text-amber-900 dark:text-amber-200 px-2.5 py-0.5 rounded-full">
          {{ pendingAccounts.length }} Pending
        </span>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div v-for="acc in pendingAccounts" :key="acc.id" class="bg-white dark:bg-[#1c1c1e] p-3 rounded-xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between">
          <div>
            <p class="font-bold text-xs text-slate-900 dark:text-white">{{ acc.full_name }} ({{ acc.instrument }})</p>
            <p class="text-[11px] text-slate-400 dark:text-neutral-500">{{ acc.email }}</p>
          </div>
          <div class="flex space-x-1.5">
            <button @click="approveAccount(acc.id)" class="px-3 py-1.5 bg-emerald-600 text-white font-bold text-xs rounded-lg cursor-pointer min-h-[36px]">Approve</button>
            <button @click="promptRejectAccount(acc.id)" class="px-3 py-1.5 bg-rose-600 text-white font-bold text-xs rounded-lg cursor-pointer min-h-[36px]">Decline</button>
          </div>
        </div>
      </div>
    </section>

    <!-- Member Profile Summary Card (Lighter Matte Black) -->
    <div class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-4 sm:p-5 shadow-xs border border-slate-200/80 dark:border-neutral-800 flex items-center justify-between">
      <div class="flex items-center space-x-3.5">
        <div class="w-12 h-12 rounded-2xl overflow-hidden flex-shrink-0 border border-slate-200 dark:border-neutral-700 shadow-xs relative">
          <img v-if="store.profile?.profile_picture" 
               :src="store.profile.profile_picture" 
               alt="Avatar" 
               class="w-full h-full object-cover" />
          <div v-else class="w-full h-full bg-blue-600 text-white flex items-center justify-center font-black text-sm">
            {{ store.profile?.full_name ? store.profile.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB' }}
          </div>
        </div>
        <div>
          <div class="flex items-center space-x-1">
            <span class="font-bold text-slate-900 dark:text-white text-base lg:text-lg leading-tight">
              {{ store.profile?.full_name || 'Band Member' }}
            </span>
            <span v-if="store.profile?.is_verified" class="text-[10px] font-extrabold bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-400 px-2 py-0.5 rounded border dark:border-emerald-800/40">VERIFIED</span>
            <span v-else class="text-[10px] font-extrabold bg-amber-100 dark:bg-amber-950/60 text-amber-700 dark:text-amber-400 px-2 py-0.5 rounded border dark:border-amber-800/40">PENDING</span>
          </div>
          <p class="text-xs text-slate-500 dark:text-neutral-400 flex items-center mt-1 font-medium capitalize">
            <TrendingUp class="w-3.5 h-3.5 mr-1 text-emerald-500 flex-shrink-0" />
            {{ store.profile?.rank || 'Junior' }} Rank • {{ store.profile?.reliability_score || 100 }}% Reliability
          </p>
        </div>
      </div>
    </div>

    <!-- RESPONSIVE GRID ON DESKTOP -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 items-start">
      
      <!-- AUTOMATIC EVENTS & GIGS SECTION -->
      <section class="space-y-3">
        <div class="flex flex-wrap items-center justify-between gap-2 px-1">
          <!-- Upcoming vs Past Gigs Tab Pill Toggle -->
          <div class="flex items-center space-x-1.5 p-1 bg-slate-200/70 dark:bg-[#27272a] rounded-xl text-xs font-bold shrink-0">
            <button 
              @click="activeEventsTab = 'upcoming'"
              type="button"
              class="px-3 py-1.5 rounded-lg transition-all min-h-[36px] flex items-center cursor-pointer"
              :class="activeEventsTab === 'upcoming' 
                ? 'bg-blue-600 text-white shadow-xs font-black' 
                : 'text-slate-500 dark:text-neutral-400 hover:text-slate-800 dark:hover:text-neutral-200'"
            >
              <Calendar class="w-3.5 h-3.5 mr-1 text-white" />
              <span>Upcoming ({{ upcomingEvents.length }})</span>
            </button>

            <button 
              @click="activeEventsTab = 'past'"
              type="button"
              class="px-3 py-1.5 rounded-lg transition-all min-h-[36px] flex items-center cursor-pointer"
              :class="activeEventsTab === 'past' 
                ? 'bg-blue-600 text-white shadow-xs font-black' 
                : 'text-slate-500 dark:text-neutral-400 hover:text-slate-800 dark:hover:text-neutral-200'"
            >
              <History class="w-3.5 h-3.5 mr-1 text-slate-400" />
              <span>Past Gigs ({{ pastEvents.length }})</span>
            </button>
          </div>

          <button 
            v-if="store.canManageEvents" 
            @click="showEventModal = true" 
            type="button" 
            class="text-xs font-black text-blue-600 dark:text-blue-400 bg-blue-50 dark:bg-blue-950/40 hover:bg-blue-100 dark:hover:bg-blue-900/60 px-3 py-1.5 rounded-xl flex items-center transition-all cursor-pointer min-h-[36px] shrink-0 shadow-xs"
          >
            <Plus class="w-3.5 h-3.5 mr-1" /> Schedule Event
          </button>
        </div>

        <!-- 1. UPCOMING EVENTS TAB VIEW -->
        <div v-if="activeEventsTab === 'upcoming'">
          <div v-if="upcomingEvents.length > 0" class="space-y-3">
            <div 
              v-for="ev in upcomingEvents" 
              :key="ev.id"
              class="bg-white dark:bg-[#18181b] rounded-3xl p-5 shadow-sm dark:shadow-lg relative overflow-hidden border border-slate-200/90 dark:border-neutral-800 border-l-4 border-l-blue-600 dark:border-l-blue-500"
            >
              <div class="relative z-10">
                <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
                  <span class="inline-block px-3 py-1 bg-blue-50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300 rounded-full text-xs font-black uppercase tracking-wider border border-blue-100 dark:border-blue-900/50">
                    {{ ev.type }}
                  </span>
                  
                  <div class="flex items-center space-x-1.5 shrink-0">
                    <button v-if="store.canConductRollCall || store.canManageEvents" @click="openAttendanceTracker(ev)" class="px-2.5 py-1 bg-slate-100 hover:bg-slate-200 dark:bg-white/10 dark:hover:bg-white/20 text-slate-700 dark:text-white font-extrabold text-[11px] rounded-full flex items-center cursor-pointer min-h-[36px] transition-colors">
                      <Users class="w-3.5 h-3.5 mr-1" /> Attendees
                    </button>
                    <button v-if="store.canManageEvents" @click="promptDeleteEvent(ev.id)" class="p-1.5 rounded-full bg-rose-600 text-white hover:bg-rose-700 cursor-pointer min-w-[36px] min-h-[36px] flex items-center justify-center transition-colors" title="Delete Event">
                      <Trash2 class="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
                
                <h3 class="text-xl font-black mb-2 leading-tight text-slate-900 dark:text-white">{{ ev.title }}</h3>
                
                <div class="space-y-1.5 mb-4 text-xs font-bold text-slate-600 dark:text-neutral-300">
                  <div class="flex items-center">
                    <Calendar class="w-3.5 h-3.5 mr-2 flex-shrink-0 text-slate-400 dark:text-neutral-400" />
                    <span>{{ ev.date }} at {{ ev.time }}</span>
                  </div>
                  <div class="flex items-center">
                    <MapPin class="w-3.5 h-3.5 mr-2 flex-shrink-0 text-slate-400 dark:text-neutral-400" />
                    <span>{{ ev.location }}</span>
                  </div>
                </div>

                <!-- RSVP Action Buttons -->
                <div v-if="!ev.rsvpStatus" class="grid grid-cols-2 gap-2">
                  <button 
                    @click="rsvp(ev, 'attending')"
                    type="button"
                    class="bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white font-black py-2.5 px-2 rounded-xl flex items-center justify-center transition-all active:scale-95 shadow-sm text-xs cursor-pointer min-h-[44px]"
                  >
                    <CheckCircle class="w-4 h-4 mr-1.5 text-emerald-300" />
                    <span>I Will Attend</span>
                  </button>
                  <button 
                    @click="rsvp(ev, 'declined')"
                    type="button"
                    class="bg-slate-100 hover:bg-slate-200 dark:bg-[#27272a] dark:hover:bg-[#323236] text-slate-700 dark:text-white font-bold py-2.5 px-2 rounded-xl flex items-center justify-center transition-all active:scale-95 text-xs cursor-pointer min-h-[44px] border border-slate-200/80 dark:border-neutral-700/60"
                  >
                    <XCircle class="w-4 h-4 mr-1.5 text-rose-500 dark:text-rose-400" />
                    <span>Cannot Attend</span>
                  </button>
                </div>
                
                <!-- Color-Coded Confirmed RSVP Status -->
                <div v-else class="flex items-center justify-between p-2.5 bg-slate-50 dark:bg-neutral-900/80 border border-slate-200/80 dark:border-neutral-800 rounded-xl">
                  <span class="font-black text-xs uppercase tracking-wider" :class="ev.rsvpStatus === 'attending' ? 'text-emerald-700 dark:text-emerald-400' : 'text-rose-700 dark:text-rose-400'">
                    {{ ev.rsvpStatus === 'attending' ? '✓ Confirmed Attending' : '✗ Declined' }}
                  </span>
                  <button @click="ev.rsvpStatus = null" class="text-xs underline font-bold text-slate-500 hover:text-slate-900 dark:text-neutral-400 dark:hover:text-white cursor-pointer min-h-[36px]">Change</button>
                </div>
              </div>
            </div>
          </div>

          <div v-else class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-6 text-center border border-slate-200/80 dark:border-neutral-800">
            <Calendar class="w-8 h-8 text-slate-400 dark:text-neutral-500 mx-auto mb-2" />
            <p class="text-sm font-bold text-slate-700 dark:text-neutral-300">No upcoming events scheduled right now.</p>
            <p class="text-xs text-slate-400 dark:text-neutral-500 mt-1">Past events have been automatically archived to the Past Gigs tab.</p>
          </div>
        </div>

        <!-- 2. PAST GIGS HISTORY TAB VIEW (Automatically Archived) -->
        <div v-else-if="activeEventsTab === 'past'">
          <div v-if="pastEvents.length > 0" class="space-y-3">
            <div 
              v-for="ev in pastEvents" 
              :key="ev.id"
              class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 space-y-3"
            >
              <div class="flex items-start justify-between">
                <div>
                  <div class="flex items-center space-x-1">
                    <span class="text-[10px] font-black uppercase tracking-wider px-2 py-0.5 rounded bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400">
                      {{ ev.type }}
                    </span>
                    <span class="text-[10px] font-extrabold px-2 py-0.5 rounded bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-400">
                      ✓ Completed
                    </span>
                  </div>
                  <h3 class="font-bold text-base text-slate-900 dark:text-white mt-1 leading-snug">{{ ev.title }}</h3>
                </div>

                <div class="flex items-center space-x-1.5">
                  <button 
                    v-if="store.canConductRollCall || store.canManageEvents" 
                    @click="openAttendanceTracker(ev)" 
                    class="px-2.5 py-1.5 bg-slate-100 dark:bg-[#27272a] text-slate-800 dark:text-slate-200 font-extrabold text-[11px] rounded-lg shadow-xs hover:bg-slate-200 flex items-center cursor-pointer min-h-[36px]"
                  >
                    <Users class="w-3.5 h-3.5 mr-1" /> Log
                  </button>
                  <button 
                    v-if="store.canManageEvents" 
                    @click="promptDeleteEvent(ev.id)" 
                    class="p-1 text-rose-500 hover:text-rose-700 cursor-pointer min-w-[36px] min-h-[36px] flex items-center justify-center"
                    title="Delete Record"
                  >
                    <Trash2 class="w-3.5 h-3.5" />
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

          <div v-else class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-6 text-center border border-slate-200/80 dark:border-neutral-800">
            <History class="w-8 h-8 text-slate-400 dark:text-neutral-500 mx-auto mb-2" />
            <p class="text-sm font-bold text-slate-700 dark:text-neutral-300">No past gigs recorded yet.</p>
          </div>
        </div>
      </section>

      <!-- Announcements Section -->
      <section class="space-y-3">
        <div class="flex flex-wrap items-center justify-between gap-2 px-1">
          <!-- Announcements Tab Pill Toggle -->
          <div class="flex items-center space-x-1.5 p-1 bg-slate-200/70 dark:bg-[#27272a] rounded-xl text-xs font-bold shrink-0">
            <button 
              @click="activeAnnouncementTab = 'recent'"
              type="button"
              class="px-3 py-1.5 rounded-lg transition-all min-h-[36px] flex items-center cursor-pointer"
              :class="activeAnnouncementTab === 'recent' 
                ? 'bg-blue-600 text-white shadow-xs font-black' 
                : 'text-slate-500 dark:text-neutral-400 hover:text-slate-800 dark:hover:text-neutral-200'"
            >
              <Bell class="w-3.5 h-3.5 mr-1" :class="activeAnnouncementTab === 'recent' ? 'text-white' : 'text-blue-600 dark:text-blue-400'" />
              <span>Recent ({{ recentAnnouncements.length }})</span>
            </button>

            <button 
              @click="activeAnnouncementTab = 'archived'"
              type="button"
              class="px-3 py-1.5 rounded-lg transition-all min-h-[36px] flex items-center cursor-pointer"
              :class="activeAnnouncementTab === 'archived' 
                ? 'bg-blue-600 text-white shadow-xs font-black' 
                : 'text-slate-500 dark:text-neutral-400 hover:text-slate-800 dark:hover:text-neutral-200'"
            >
              <History class="w-3.5 h-3.5 mr-1" :class="activeAnnouncementTab === 'archived' ? 'text-white' : 'text-slate-400'" />
              <span>Archived ({{ archivedAnnouncements.length }})</span>
            </button>
          </div>

          <button 
            v-if="store.canManageAnnouncements" 
            @click="showAnnouncementModal = true" 
            type="button" 
            class="text-xs font-black text-blue-600 dark:text-blue-400 bg-blue-50 dark:bg-blue-950/40 hover:bg-blue-100 dark:hover:bg-blue-900/60 px-3 py-1.5 rounded-xl flex items-center transition-all cursor-pointer min-h-[36px] shrink-0 shadow-xs"
          >
            <Plus class="w-3.5 h-3.5 mr-1" /> Post
          </button>
        </div>
        
        <div v-if="displayedAnnouncements.length > 0" class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-5 shadow-sm border border-slate-200/80 dark:border-neutral-800 flex flex-col max-h-[300px] overflow-y-auto">
          <article 
            v-for="(post, index) in displayedAnnouncements" 
            :key="post.id"
            class="py-4 first:pt-0 last:pb-0"
            :class="{ 'border-b border-slate-100 dark:border-neutral-800/80': index !== displayedAnnouncements.length - 1 }"
          >
            <div class="flex justify-between items-start mb-1.5">
              <h3 class="font-bold text-base text-slate-900 dark:text-white leading-snug">{{ post.title }}</h3>
              <div class="flex items-center space-x-1">
                <span class="text-[11px] font-semibold text-slate-400 dark:text-neutral-500 whitespace-nowrap">{{ post.date }}</span>
                <button v-if="store.canManageAnnouncements" @click="promptDeleteAnnouncement(post.id)" class="text-rose-500 hover:text-rose-700 cursor-pointer p-1" title="Delete Announcement">
                  <Trash2 class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
            <p class="text-slate-600 dark:text-neutral-300 text-sm mb-2.5 leading-relaxed whitespace-pre-wrap">
              {{ post.content }}
            </p>
            <div class="flex items-center justify-between mt-1">
              <span class="text-xs font-semibold text-slate-500 dark:text-neutral-400 flex items-center">
                <User class="w-3.5 h-3.5 mr-1.5 text-slate-400 dark:text-neutral-500" />
                {{ post.author }}
              </span>
            </div>
          </article>
        </div>

        <div v-else class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-6 text-center border border-slate-200/80 dark:border-neutral-800">
          <p class="text-sm font-bold text-slate-700 dark:text-neutral-300">No announcements posted yet.</p>
        </div>
      </section>

    </div>

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

    <!-- CREATE ANNOUNCEMENT MODAL (Lighter Matte Black) -->
    <div v-if="showAnnouncementModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-5 max-w-sm w-full space-y-4 shadow-2xl">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-2">
          <h3 class="font-black text-lg text-slate-900 dark:text-white">Post Announcement</h3>
          <button @click="showAnnouncementModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>
        <div class="space-y-3 text-left">
          <div>
            <label for="ann-title-in" class="block text-xs font-bold text-slate-400 dark:text-neutral-400 uppercase mb-1">Title</label>
            <input id="ann-title-in" v-model="newAnnTitle" type="text" placeholder="e.g. Call Time for Town Procession" class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
          </div>
          <div>
            <label for="ann-content-in" class="block text-xs font-bold text-slate-400 dark:text-neutral-400 uppercase mb-1">Content</label>
            <textarea id="ann-content-in" v-model="newAnnContent" rows="4" placeholder="Write full details..." class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-medium text-slate-900 dark:text-white"></textarea>
          </div>
        </div>
        <div class="flex space-x-2 pt-2">
          <button @click="showAnnouncementModal = false" class="flex-1 py-3 bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 font-bold text-xs border border-rose-200 dark:border-rose-900/40 hover:bg-rose-100 rounded-xl min-h-[44px] cursor-pointer">Cancel</button>
          <button @click="handleCreateAnnouncement" :disabled="isSubmitting" class="flex-1 py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer">Post</button>
        </div>
      </div>
    </div>

    <!-- CREATE EVENT MODAL (Lighter Matte Black) -->
    <div v-if="showEventModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-5 max-w-sm w-full space-y-4 shadow-2xl">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-2">
          <h3 class="font-black text-lg text-slate-900 dark:text-white">Schedule Event</h3>
          <button @click="showEventModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>
        <div class="space-y-3 text-left">
          <div>
            <label for="ev-title-in" class="block text-xs font-bold text-slate-400 dark:text-neutral-400 uppercase mb-1">Event Title</label>
            <input id="ev-title-in" v-model="newEvTitle" type="text" placeholder="e.g. Town Fiesta Parade" class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
          </div>
          <div>
            <label for="ev-type-in" class="block text-xs font-bold text-slate-400 dark:text-neutral-400 uppercase mb-1">Event Type</label>
            <select id="ev-type-in" v-model="newEvType" class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
              <option v-for="opt in eventTypeOptions" :key="opt" :value="opt">{{ opt }}</option>
            </select>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label for="ev-date-in" class="block text-xs font-bold text-slate-400 dark:text-neutral-400 uppercase mb-1">Date</label>
              <input id="ev-date-in" v-model="newEvDate" type="date" class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
            </div>
            <div>
              <label for="ev-time-in" class="block text-xs font-bold text-slate-400 dark:text-neutral-400 uppercase mb-1">Time</label>
              <input id="ev-time-in" v-model="newEvTime" type="time" class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
            </div>
          </div>
          <div>
            <label for="ev-loc-in" class="block text-xs font-bold text-slate-400 dark:text-neutral-400 uppercase mb-1">Location</label>
            <input id="ev-loc-in" v-model="newEvLocation" type="text" placeholder="e.g. Town Plaza / Band Hall" class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
          </div>
        </div>
        <div class="flex space-x-2 pt-2">
          <button @click="showEventModal = false" class="flex-1 py-3 bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 font-bold text-xs border border-rose-200 dark:border-rose-900/40 hover:bg-rose-100 rounded-xl min-h-[44px] cursor-pointer">Cancel</button>
          <button @click="handleCreateEvent" :disabled="isSubmitting" class="flex-1 py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer">Schedule</button>
        </div>
      </div>
    </div>

    <!-- CONFIRM MODAL -->
    <div v-if="showConfirmModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-5 max-w-sm w-full space-y-4 shadow-2xl text-center">
        <div class="w-12 h-12 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        <div>
          <h3 class="font-black text-lg text-slate-900 dark:text-white leading-tight">Confirm Action?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 mt-1 leading-relaxed">
            Are you sure you want to proceed?
          </p>
        </div>
        <div class="flex space-x-2 pt-2">
          <button @click="showConfirmModal = false; confirmTargetId = null" type="button" class="flex-1 py-3 bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 font-bold text-xs border border-rose-200 dark:border-rose-900/40 hover:bg-rose-100 rounded-xl min-h-[44px] cursor-pointer">Cancel</button>
          <button @click="executeConfirmedAction" type="button" class="flex-1 py-3 bg-rose-600 hover:bg-rose-700 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer">Proceed</button>
        </div>
      </div>
    </div>

  </div>
</template>
