<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { Calendar, MapPin, CheckCircle, XCircle, Bell, MessageSquare, ShieldCheck, TrendingUp, User, Plus, ShieldAlert, X, AlertCircle, Trash2, Smartphone, FileText, Users, UserCheck, UserX, History, Clock, ChevronRight } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const store = useMainStore()

const pendingAccounts = ref([])
const rawEvents = ref([])
const announcements = ref([])
const isLoading = ref(true)
const activeEventsTab = ref('upcoming') // 'upcoming' | 'past'

// Realtime Channel & Sync References
let homeChannel = null
let syncBroadcast = null
let pollTimer = null

// Attendance Tracker Modal State (Secretary / Admin)
const showAttendanceModal = ref(false)
const selectedEventForAttendance = ref(null)
const attendingMembersList = ref([])
const declinedMembersList = ref([])
const isLoadingAttendance = ref(false)

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

// OPEN EVENT ATTENDANCE TRACKER
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
  if (!newEvTitle.value || !newEvDate.value || !newEvLocation.value) return
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
    const { error } = await supabase.from('announcements').delete().eq('id', id)
    if (!error) {
      announcements.value = announcements.value.filter(a => a.id !== id)
      localStorage.setItem('smartband_announcements_cache', JSON.stringify(announcements.value))
      notifyOtherTabs('ANNOUNCEMENT_CHANGED')
      showToast('Announcement deleted.')
    }
  } else if (confirmActionType.value === 'delete_event') {
    const { error } = await supabase.from('events').delete().eq('id', id)
    if (!error) {
      rawEvents.value = rawEvents.value.filter(e => e.id !== id)
      localStorage.setItem('smartband_raw_events_cache', JSON.stringify(rawEvents.value))
      notifyOtherTabs('EVENT_CHANGED')
      showToast('Event deleted.')
    }
  } else if (confirmActionType.value === 'reject_account') {
    const { error } = await supabase.from('profiles').delete().eq('id', id)
    if (!error) {
      pendingAccounts.value = pendingAccounts.value.filter(a => a.id !== id)
      notifyOtherTabs('PROFILE_CHANGED')
      showToast('Registration declined & erased.')
    }
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

onMounted(() => {
  fetchHomeData()

  // 1. Inter-Tab / Inter-Window Native BroadcastChannel Sync
  if ('BroadcastChannel' in window) {
    syncBroadcast = new BroadcastChannel('smartband_live_sync')
    syncBroadcast.onmessage = () => {
      fetchHomeData(true)
      if (showAttendanceModal.value && selectedEventForAttendance.value) {
        openAttendanceTracker(selectedEventForAttendance.value)
      }
    }
  }

  // 2. Supabase Realtime WebSocket Channel
  homeChannel = supabase
    .channel('home-realtime-v5')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'announcements' }, () => {
      fetchHomeData(true)
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'events' }, () => {
      fetchHomeData(true)
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'event_rsvps' }, () => {
      fetchHomeData(true)
      if (showAttendanceModal.value && selectedEventForAttendance.value) {
        openAttendanceTracker(selectedEventForAttendance.value)
      }
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, () => {
      fetchHomeData(true)
    })
    .subscribe()

  // 3. Silent Auto-Polling Fallback (Every 6 seconds)
  pollTimer = setInterval(() => {
    fetchHomeData(true)
  }, 6000)
})

onUnmounted(() => {
  if (homeChannel) supabase.removeChannel(homeChannel)
  if (syncBroadcast) syncBroadcast.close()
  if (pollTimer) clearInterval(pollTimer)
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
        <div class="flex items-center space-x-2">
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
        <div class="flex items-center space-x-2">
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
        <div class="w-12 h-12 rounded-2xl bg-blue-500/10 text-blue-600 dark:text-blue-400 flex items-center justify-center flex-shrink-0">
          <ShieldCheck class="w-7 h-7" />
        </div>
        <div>
          <div class="flex items-center space-x-2">
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
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6 items-start">
      
      <!-- AUTOMATIC EVENTS & GIGS SECTION -->
      <section class="space-y-3">
        <div class="flex items-center justify-between px-1">
          <!-- Upcoming vs Past Gigs Tab Pill Toggle -->
          <div class="flex items-center space-x-1.5 p-1 bg-slate-200/70 dark:bg-[#27272a] rounded-xl text-xs font-bold">
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

          <button v-if="store.canManageEvents" @click="showEventModal = true" type="button" class="text-xs font-black text-blue-600 dark:text-blue-400 flex items-center hover:underline cursor-pointer min-h-[44px]">
            <Plus class="w-3.5 h-3.5 mr-0.5" /> Schedule Event
          </button>
        </div>

        <!-- 1. UPCOMING EVENTS TAB VIEW -->
        <div v-if="activeEventsTab === 'upcoming'">
          <div v-if="upcomingEvents.length > 0" class="space-y-3">
            <div 
              v-for="ev in upcomingEvents" 
              :key="ev.id"
              class="bg-slate-900 dark:bg-[#18181b] rounded-3xl p-5 shadow-lg relative overflow-hidden text-white border border-slate-800 dark:border-neutral-800"
            >
              <div class="relative z-10">
                <div class="flex items-center justify-between mb-3">
                  <span class="inline-block px-3 py-1 bg-white/15 backdrop-blur-sm rounded-full text-xs font-black uppercase tracking-wider text-white">
                    {{ ev.type }}
                  </span>
                  
                  <div class="flex items-center space-x-1.5">
                    <button v-if="store.canConductRollCall || store.canManageEvents" @click="openAttendanceTracker(ev)" class="px-2.5 py-1 bg-white/20 hover:bg-white/30 text-white font-extrabold text-[11px] rounded-full flex items-center cursor-pointer min-h-[36px]">
                      <Users class="w-3.5 h-3.5 mr-1" /> Attendees
                    </button>
                    <button v-if="store.canManageEvents" @click="promptDeleteEvent(ev.id)" class="p-1 rounded-full bg-rose-600 text-white hover:bg-rose-700 cursor-pointer" title="Delete Event">
                      <Trash2 class="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
                
                <h3 class="text-xl font-black mb-2 leading-tight text-white">{{ ev.title }}</h3>
                
                <div class="space-y-1.5 mb-4 text-xs font-bold opacity-90">
                  <div class="flex items-center">
                    <Calendar class="w-3.5 h-3.5 mr-2 flex-shrink-0 opacity-80" />
                    <span>{{ ev.date }} at {{ ev.time }}</span>
                  </div>
                  <div class="flex items-center">
                    <MapPin class="w-3.5 h-3.5 mr-2 flex-shrink-0 opacity-80" />
                    <span>{{ ev.location }}</span>
                  </div>
                </div>

                <!-- RSVP Action Buttons -->
                <div v-if="!ev.rsvpStatus" class="grid grid-cols-2 gap-2">
                  <button 
                    @click="rsvp(ev, 'attending')"
                    type="button"
                    class="bg-white hover:bg-slate-100 text-blue-900 font-black py-2.5 px-2 rounded-xl flex items-center justify-center transition-all active:scale-95 shadow-md text-xs cursor-pointer min-h-[44px]"
                  >
                    <CheckCircle class="w-4 h-4 mr-1.5 text-emerald-600" />
                    <span>I Will Attend</span>
                  </button>
                  <button 
                    @click="rsvp(ev, 'declined')"
                    type="button"
                    class="bg-white/20 hover:bg-white/30 text-white font-bold py-2.5 px-2 rounded-xl flex items-center justify-center transition-all active:scale-95 text-xs cursor-pointer min-h-[44px]"
                  >
                    <XCircle class="w-4 h-4 mr-1.5 text-rose-300" />
                    <span>Cannot Attend</span>
                  </button>
                </div>
                
                <!-- Color-Coded Confirmed RSVP Status -->
                <div v-else class="flex items-center justify-between p-2.5 bg-black/20 rounded-xl backdrop-blur-sm">
                  <span class="font-black text-xs uppercase tracking-wider" :class="ev.rsvpStatus === 'attending' ? 'text-emerald-300' : 'text-rose-300'">
                    {{ ev.rsvpStatus === 'attending' ? '✓ Confirmed Attending' : '✗ Declined' }}
                  </span>
                  <button @click="ev.rsvpStatus = null" class="text-xs underline font-bold text-white/80 hover:text-white cursor-pointer min-h-[36px]">Change</button>
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
                  <div class="flex items-center space-x-2">
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
        <div class="flex items-center justify-between px-1">
          <h2 class="text-xs font-extrabold text-slate-500 dark:text-neutral-400 uppercase tracking-wider">
            Announcements ({{ announcements.length }})
          </h2>
          <button v-if="store.canManageAnnouncements" @click="showAnnouncementModal = true" type="button" class="text-xs font-black text-blue-600 dark:text-blue-400 flex items-center hover:underline cursor-pointer min-h-[44px]">
            <Plus class="w-3.5 h-3.5 mr-0.5" /> Post Announcement
          </button>
        </div>
        
        <div v-if="announcements.length > 0" class="space-y-3">
          <article 
            v-for="post in announcements" 
            :key="post.id"
            class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 hover:border-blue-500/50 transition-colors"
          >
            <div class="flex justify-between items-start mb-2">
              <h3 class="font-bold text-base text-slate-900 dark:text-white leading-snug">{{ post.title }}</h3>
              <div class="flex items-center space-x-2">
                <span class="text-[11px] font-semibold text-slate-400 dark:text-neutral-500 whitespace-nowrap">{{ post.date }}</span>
                <button v-if="store.canManageAnnouncements" @click="promptDeleteAnnouncement(post.id)" class="text-rose-500 hover:text-rose-700 cursor-pointer p-1" title="Delete Announcement">
                  <Trash2 class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
            <p class="text-slate-600 dark:text-neutral-300 text-xs sm:text-sm line-clamp-3 mb-3 leading-relaxed">
              {{ post.content }}
            </p>
            <div class="flex items-center justify-between pt-2 border-t border-slate-100 dark:border-neutral-800">
              <span class="text-xs font-semibold text-slate-500 dark:text-neutral-400 flex items-center">
                <User class="w-3.5 h-3.5 mr-1 text-slate-400 dark:text-neutral-500" />
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
          <button @click="showAnnouncementModal = false" class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer">Cancel</button>
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
          <button @click="showEventModal = false" class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer">Cancel</button>
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
          <button @click="showConfirmModal = false; confirmTargetId = null" type="button" class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer">Cancel</button>
          <button @click="executeConfirmedAction" type="button" class="flex-1 py-3 bg-rose-600 hover:bg-rose-700 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer">Proceed</button>
        </div>
      </div>
    </div>

  </div>
</template>
