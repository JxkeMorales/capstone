<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { Calendar, MapPin, CheckCircle, XCircle, Bell, MessageSquare, ShieldCheck, TrendingUp, User, Plus, ShieldAlert, X, AlertCircle, Trash2, Smartphone, FileText, Users, UserCheck, UserX, History, Clock, ChevronRight, Download, AlertTriangle, Volume2, Check, CalendarCheck, RefreshCw } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useUIStore } from '@/stores/ui'
import { supabase } from '@/supabase'
import { initRealtimeSync, broadcastSync } from '@/utils/realtime'
import { generateEventAttendancePdf } from '@/utils/pdfExport'
import { requestPushPermission, sendPushNotification } from '@/utils/push'

const store = useMainStore()
const uiStore = useUIStore()

const pendingAccounts = ref([])
const rawEvents = ref([])
const announcements = ref([])
const isLoading = ref(true)
const loadError = ref(null)
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

// Global Toast Notification
const showToast = (msg, type = 'info') => {
  uiStore.addToast({
    title: 'Dashboard Alert',
    message: msg,
    type: type === 'error' ? 'error' : msg.startsWith('✓') ? 'success' : 'info'
  })
}

// Announcement Form (ISO/IEC 25010 Urgency Tiers & Section Dispatch)
const newAnnTitle = ref('')
const newAnnContent = ref('')
const newAnnPriority = ref('HIGH') // 'HIGH' | 'MEDIUM' | 'LOW'
const newAnnTargetSection = ref('all') // 'all' | 'woodwinds' | 'brass' | 'percussion' | 'officers'

// TC-05 Two-Way Message Acknowledgment State
const userAcknowledgments = ref({})

// Excuse Justification State (Table 19 tbl_event_rsvps)
const showExcuseModal = ref(false)
const eventForExcuse = ref(null)
const selectedExcusePill = ref('School / Exam Conflict')
const customExcuseNote = ref('')
const isSubmittingExcuse = ref(false)
const excusePills = [
  'School / Exam Conflict',
  'Work Shift / Livelihood',
  'Illness / Medical Reason',
  'Family Emergency',
  'Out of Town / Travel',
  'Other Reason'
]

// Push permission state
const pushPermission = ref(typeof Notification !== 'undefined' ? Notification.permission : 'default')

// Event Form
const newEvTitle = ref('')
const newEvType = ref('Ensayo / Practice') 
const newEvDate = ref('')
const newEvTime = ref('14:00')
const newEvLocation = ref('')

// IT Expert Recommendation (P[1133] & P[1148]): Past Date Prevention Validation
const minDateToday = computed(() => {
  const d = new Date()
  const year = d.getFullYear()
  const month = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
})

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

// Dedicated view of events the current user accepted/confirmed attendance for
const myAcceptedEvents = computed(() => {
  const todayStart = getTodayStart()
  return rawEvents.value
    .filter(ev => new Date(ev.rawDate).getTime() >= todayStart && ev.rsvpStatus === 'attending')
    .sort((a, b) => new Date(a.rawDate) - new Date(b.rawDate))
})

const notifyOtherTabs = (eventType, payload = {}) => {
  broadcastSync(eventType, payload)
}

// READ-THROUGH CACHE (Item 31: offline-first render cache then revalidate)
const loadHomeFromCache = () => {
  try {
    const cachedEvents = localStorage.getItem('smartband_home_events_cache')
    const cachedAnn = localStorage.getItem('smartband_home_announcements_cache')
    let hasCachedContent = false
    if (cachedEvents) {
      rawEvents.value = JSON.parse(cachedEvents)
      hasCachedContent = true
    }
    if (cachedAnn) {
      announcements.value = JSON.parse(cachedAnn)
      hasCachedContent = true
    }
    return hasCachedContent
  } catch (e) {
    return false
  }
}

// PAGINATION STATE (Item 30: Server-side paging 50/page)
const EVENTS_PAGE_SIZE = 50
const eventsPage = ref(0)
const hasMoreEvents = ref(false)
const isLoadingMoreEvents = ref(false)

const ANN_PAGE_SIZE = 50
const annPage = ref(0)
const hasMoreAnn = ref(false)
const isLoadingMoreAnn = ref(false)

const fetchHomeData = async (skipCache = false) => {
  let hadCache = false
  if (!skipCache) {
    hadCache = loadHomeFromCache()
    if (!hadCache) {
      isLoading.value = true
    }
    loadError.value = null
  }

  eventsPage.value = 0
  annPage.value = 0

  try {
    // 1. Fetch events with pagination (50/page)
    const { data: eventData, error: evErr, count: evCount } = await supabase
      .from('events')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(0, EVENTS_PAGE_SIZE - 1)

    if (evErr) throw evErr

    if (eventData) {
      let rsvpMap = {}
      if (store.user) {
        const { data: rsvpData } = await supabase
          .from('event_rsvps')
          .select('event_id, status')
          .eq('user_id', store.user.id)
        if (rsvpData) {
          rsvpData.forEach(r => {
            rsvpMap[r.event_id] = { 
              status: r.status, 
              excuse: localStorage.getItem(`smartband_rsvp_excuse_${r.event_id}`) || null 
            }
          })
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
          rsvpStatus: rsvpMap[ev.id]?.status || localStorage.getItem(`smartband_rsvp_${ev.id}`) || null,
          excuseJustification: rsvpMap[ev.id]?.excuse || localStorage.getItem(`smartband_rsvp_excuse_${ev.id}`) || null,
          createdAt: ev.created_at
        }
      })

      hasMoreEvents.value = (evCount ? rawEvents.value.length < evCount : eventData.length === EVENTS_PAGE_SIZE)
      try {
        localStorage.setItem('smartband_home_events_cache', JSON.stringify(rawEvents.value))
      } catch (e) {}
    }

    // 2. Fetch announcements with pagination (50/page)
    const { data: annData, error: annErr, count: annCount } = await supabase
      .from('announcements')
      .select('*, author:profiles(full_name)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(0, ANN_PAGE_SIZE - 1)

    if (annErr) throw annErr

    if (annData) {
      announcements.value = annData.map(a => ({
        id: a.id,
        author: a.author?.full_name || 'Band Officer',
        date: new Date(a.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
        title: a.title,
        rawDate: a.created_at,
        content: a.content,
        priority: a.priority || (a.category && a.category.toLowerCase().includes('urgent') ? 'HIGH' : a.category) || 'HIGH',
        category: a.category || 'General',
        targetSection: a.target_section || 'all',
        ackCount: 0
      }))

      hasMoreAnn.value = (annCount ? announcements.value.length < annCount : annData.length === ANN_PAGE_SIZE)
      try {
        localStorage.setItem('smartband_home_announcements_cache', JSON.stringify(announcements.value))
      } catch (e) {}
    }

    // 2b. Fetch Acknowledgment counts & user acknowledgments (TC-05 Two-Way Tracking)
    try {
      if (store.user?.id) {
        const cachedAcks = localStorage.getItem(`smartband_ack_${store.user.id}`)
        if (cachedAcks) {
          userAcknowledgments.value = JSON.parse(cachedAcks)
        }
      }
    } catch (e) {}

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
    if (!hadCache && rawEvents.value.length === 0 && announcements.value.length === 0) {
      loadError.value = 'Failed to load schedule or announcements. Please verify your connection.'
    }
  } finally {
    isLoading.value = false
  }
}

const loadMoreEvents = async () => {
  if (isLoadingMoreEvents.value || !hasMoreEvents.value) return
  isLoadingMoreEvents.value = true
  try {
    const nextPage = eventsPage.value + 1
    const from = nextPage * EVENTS_PAGE_SIZE
    const to = from + EVENTS_PAGE_SIZE - 1

    const { data: eventData, error: evErr, count: evCount } = await supabase
      .from('events')
      .select('*', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to)

    if (evErr) throw evErr
    if (eventData && eventData.length > 0) {
      let rsvpMap = {}
      if (store.user) {
        const { data: rsvpData } = await supabase
          .from('event_rsvps')
          .select('event_id, status')
          .eq('user_id', store.user.id)
        if (rsvpData) {
          rsvpData.forEach(r => {
            rsvpMap[r.event_id] = { 
              status: r.status, 
              excuse: localStorage.getItem(`smartband_rsvp_excuse_${r.event_id}`) || null 
            }
          })
        }
      }

      const newEvents = eventData.map(ev => {
        const evDate = new Date(ev.event_date)
        return {
          id: ev.id,
          rawDate: ev.event_date,
          title: ev.title,
          date: evDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }),
          time: evDate.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
          location: ev.location,
          type: ev.event_type,
          rsvpStatus: rsvpMap[ev.id]?.status || localStorage.getItem(`smartband_rsvp_${ev.id}`) || null,
          excuseJustification: rsvpMap[ev.id]?.excuse || localStorage.getItem(`smartband_rsvp_excuse_${ev.id}`) || null,
          createdAt: ev.created_at
        }
      })

      rawEvents.value = [...rawEvents.value, ...newEvents]
      eventsPage.value = nextPage
      hasMoreEvents.value = (evCount ? rawEvents.value.length < evCount : eventData.length === EVENTS_PAGE_SIZE)
      try {
        localStorage.setItem('smartband_home_events_cache', JSON.stringify(rawEvents.value))
      } catch (e) {}
    } else {
      hasMoreEvents.value = false
    }
  } catch (err) {
    console.error('Error loading more events:', err)
  } finally {
    isLoadingMoreEvents.value = false
  }
}

const loadMoreAnnouncements = async () => {
  if (isLoadingMoreAnn.value || !hasMoreAnn.value) return
  isLoadingMoreAnn.value = true
  try {
    const nextPage = annPage.value + 1
    const from = nextPage * ANN_PAGE_SIZE
    const to = from + ANN_PAGE_SIZE - 1

    const { data: annData, error: annErr, count: annCount } = await supabase
      .from('announcements')
      .select('*, author:profiles(full_name)', { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(from, to)

    if (annErr) throw annErr
    if (annData && annData.length > 0) {
      const newAnn = annData.map(a => ({
        id: a.id,
        author: a.author?.full_name || 'Band Officer',
        date: new Date(a.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
        title: a.title,
        rawDate: a.created_at,
        content: a.content,
        priority: a.priority || (a.category && a.category.toLowerCase().includes('urgent') ? 'HIGH' : a.category) || 'HIGH',
        category: a.category || 'General',
        targetSection: a.target_section || 'all',
        ackCount: 0
      }))

      announcements.value = [...announcements.value, ...newAnn]
      annPage.value = nextPage
      hasMoreAnn.value = (annCount ? announcements.value.length < annCount : annData.length === ANN_PAGE_SIZE)
      try {
        localStorage.setItem('smartband_home_announcements_cache', JSON.stringify(announcements.value))
      } catch (e) {}
    } else {
      hasMoreAnn.value = false
    }
  } catch (err) {
    console.error('Error loading more announcements:', err)
  } finally {
    isLoadingMoreAnn.value = false
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
    let { data: rsvps, error: rsvpErr } = await supabase
      .from('event_rsvps')
      .select('id, user_id, status, excuse_justification')
      .eq('event_id', ev.id)

    if (rsvpErr && rsvpErr.message && rsvpErr.message.includes('excuse_justification')) {
      const fallback = await supabase
        .from('event_rsvps')
        .select('id, user_id, status')
        .eq('event_id', ev.id)
      rsvps = fallback.data
      rsvpErr = fallback.error
    }

    if (rsvpErr) throw rsvpErr

    const rsvpMap = new Map()
    if (rsvps) {
      rsvps.forEach(r => rsvpMap.set(r.user_id, { 
        status: r.status, 
        excuse: r.excuse_justification || localStorage.getItem(`smartband_rsvp_excuse_${r.event_id || ev.id}`) || null 
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
        currentStatus: st, // 'attending' | 'declined' | 'present' | 'absent' | 'excused' | 'none'
        excuseJustification: excuse,
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
    showToast(`✓ Downloaded ${filename}`)
  } catch (err) {
    console.error('Attendance export error:', err)
    showToast('Failed to export attendance PDF.')
  } finally {
    isExportingAttendancePdf.value = false
  }
}

// POST ANNOUNCEMENT WITH INSTANT LOCAL UPDATE + SYNC BROADCAST (ISO/IEC 25010 & TC-04)
const handleCreateAnnouncement = async () => {
  if (!newAnnTitle.value || !newAnnContent.value || !store.user) return
  isSubmitting.value = true

  try {
    const priorityVal = newAnnPriority.value || 'HIGH'
    const targetSec = newAnnTargetSection.value || 'all'

    const { data, error } = await supabase
      .from('announcements')
      .insert({
        title: newAnnTitle.value.trim(),
        content: newAnnContent.value.trim(),
        author_id: store.user.id,
        category: priorityVal
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
        content: data.content,
        rawDate: data.created_at,
        priority: data.priority || priorityVal,
        targetSection: data.target_section || targetSec,
        ackCount: 0
      }

      announcements.value = [newAnn, ...announcements.value.filter(a => a.id !== data.id)]

      // TC-04 & ISO/IEC 25010 Safety: Acoustic Brass Fanfare Siren Alert for Urgent Call-Time
      if (priorityVal === 'HIGH') {
        uiStore.playCallTimeFanfare()
      }

      notifyOtherTabs('ANNOUNCEMENT_CHANGED')

      // Dispatch background Web Push to closed devices
      sendPushNotification({
        title: priorityVal === 'HIGH' ? `🚨 CALL-TIME ALERT: ${newAnn.title}` : `📢 ${newAnn.title}`,
        message: newAnn.content,
        url: '/dashboard',
        senderId: store.user?.id
      })

      newAnnTitle.value = ''
      newAnnContent.value = ''
      newAnnPriority.value = 'HIGH'
      newAnnTargetSection.value = 'all'
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
  // IT EXPERT RECOMMENDATION (P[1133] & P[1148]): Past Date Prevention Validation
  if (newEvDate.value < minDateToday.value) {
    showToast('Event date cannot be in the past. Please select today or a future date.', 'error')
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
        excuseJustification: null,
        createdAt: data.created_at
      }

      rawEvents.value = [...rawEvents.value.filter(e => e.id !== data.id), newEv]

      notifyOtherTabs('EVENT_CHANGED')

      // Dispatch background Web Push to closed devices
      sendPushNotification({
        title: `🎷 New Event: ${newEv.title}`,
        message: `${newEv.type} at ${newEv.location} (${newEv.date}). Confirm your RSVP!`,
        url: '/dashboard',
        senderId: store.user?.id
      })

      newEvTitle.value = ''
      newEvDate.value = ''
      newEvLocation.value = ''
      showEventModal.value = false
      showToast('Event scheduled successfully!')
    }
  } catch (err) {
    console.error('Error creating event:', err)
    showToast('Failed to schedule event.', 'error')
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
      showToast(`Error deleting announcement: ${error.message}`, 'error')
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    if (!data || data.length === 0) {
      showToast('Could not delete announcement. Database permission denied.', 'error')
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    announcements.value = announcements.value.filter(a => a.id !== id)
    notifyOtherTabs('ANNOUNCEMENT_CHANGED')
    showToast('Announcement deleted.')
  } else if (confirmActionType.value === 'delete_event') {
    const { data, error } = await supabase.from('events').delete().eq('id', id).select()
    if (error) {
      showToast(`Error deleting event: ${error.message}`, 'error')
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    if (!data || data.length === 0) {
      showToast('Could not delete event. Database permission denied.', 'error')
      showConfirmModal.value = false
      confirmTargetId.value = null
      return
    }
    rawEvents.value = rawEvents.value.filter(e => e.id !== id)
    notifyOtherTabs('EVENT_CHANGED')
    showToast('Event deleted.')
  } else if (confirmActionType.value === 'reject_account') {
    try {
      await supabase.rpc('delete_user_account', { target_user_id: id })
    } catch (rpcErr) {
      console.warn('RPC delete fallback notice:', rpcErr)
    }
    const { data, error } = await supabase.from('profiles').delete().eq('id', id).select()
    if (error) {
      showToast(`Error declining account: ${error.message}`, 'error')
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

// EXCUSE JUSTIFICATION WORKFLOW (Table 19 tbl_event_rsvps)
const promptDeclineWithExcuse = (ev) => {
  eventForExcuse.value = ev
  selectedExcusePill.value = 'School / Exam Conflict'
  customExcuseNote.value = ''
  showExcuseModal.value = true
}

const confirmDeclineWithExcuse = async () => {
  if (!eventForExcuse.value) return
  isSubmittingExcuse.value = true
  const justification = customExcuseNote.value.trim()
    ? `${selectedExcusePill.value} - ${customExcuseNote.value.trim()}`
    : selectedExcusePill.value

  await rsvp(eventForExcuse.value, 'declined', justification)
  showExcuseModal.value = false
  eventForExcuse.value = null
  isSubmittingExcuse.value = false
}

const rsvp = async (eventObj, status, excuseJustification = null) => {
  if (!eventObj || !store.user) return
  const prevStatus = eventObj.rsvpStatus
  const prevExcuse = eventObj.excuseJustification
  eventObj.rsvpStatus = status
  eventObj.excuseJustification = excuseJustification
  
  localStorage.setItem(`smartband_rsvp_${eventObj.id}`, status)
  if (excuseJustification) {
    localStorage.setItem(`smartband_rsvp_excuse_${eventObj.id}`, excuseJustification)
  }
  
  rawEvents.value = rawEvents.value.map(e => e.id === eventObj.id ? { ...e, rsvpStatus: status, excuseJustification } : e)
  
  try {
    const payload = {
      event_id: eventObj.id,
      user_id: store.user.id,
      status: status,
      updated_at: new Date().toISOString()
    }
    if (excuseJustification !== null) {
      payload.excuse_justification = excuseJustification
    }

    let { error } = await supabase
      .from('event_rsvps')
      .upsert(payload, { onConflict: 'event_id,user_id' })

    // Schema fallback: If excuse_justification column does not exist yet, retry without it
    if (error && error.message && (error.message.includes('excuse_justification') || error.code === 'PGRST204')) {
      const fallbackPayload = {
        event_id: eventObj.id,
        user_id: store.user.id,
        status: status,
        updated_at: new Date().toISOString()
      }
      const retry = await supabase
        .from('event_rsvps')
        .upsert(fallbackPayload, { onConflict: 'event_id,user_id' })
      error = retry.error
    }

    if (error) {
      console.error('RSVP upsert error:', error)
      eventObj.rsvpStatus = prevStatus
      eventObj.excuseJustification = prevExcuse
      rawEvents.value = rawEvents.value.map(e => e.id === eventObj.id ? { ...e, rsvpStatus: prevStatus, excuseJustification: prevExcuse } : e)
      throw error
    }

    notifyOtherTabs('RSVP_CHANGED')
    showToast(status === 'attending' ? '✓ Attendance Confirmed: Attending' : '✓ Absence Excuse Recorded', 'success')

    // If Secretary / Admin attendance modal is open, refresh it immediately!
    if (showAttendanceModal.value && selectedEventForAttendance.value?.id === eventObj.id) {
      openAttendanceTracker(selectedEventForAttendance.value)
    }
  } catch(e) {
    console.error('RSVP error:', e)
    showToast('Failed to update RSVP.')
  }
}

// TC-05 TWO-WAY MESSAGE ACKNOWLEDGMENT & RESPONSE LATENCY TRACKING
const loadLocalAcknowledgments = () => {
  if (!store.user) return
  try {
    const saved = localStorage.getItem(`smartband_ack_${store.user.id}`)
    if (saved) {
      userAcknowledgments.value = { ...userAcknowledgments.value, ...JSON.parse(saved) }
    }
  } catch (e) {
    console.warn('Ack load error:', e)
  }
}

const isAcknowledged = (annId) => {
  return !!userAcknowledgments.value[annId]
}

const getAckLatency = (annId) => {
  return userAcknowledgments.value[annId]?.formattedLatency || ''
}

const isUrgentAnnouncement = (post) => {
  if (!post) return false
  const p = (post.priority || '').toString().toUpperCase()
  const c = (post.category || '').toString().toLowerCase()
  const t = (post.title || '').toString().toLowerCase()
  return p === 'HIGH' || p === 'URGENT' || c.includes('urgent') || t.includes('urgent') || t.includes('🚨') || t.includes('alert')
}

const isRsvpAnnouncement = (post) => {
  if (!post) return false
  const c = (post.category || '').toString().toLowerCase()
  const t = (post.title || '').toString().toLowerCase()
  const body = (post.content || '').toString().toLowerCase()
  return c.includes('rsvp') || t.includes('rsvp') || t.includes('attendance') || body.includes('rsvp') || body.includes('confirm their rsvp') || body.includes('attendance')
}

const scrollToEvents = () => {
  activeEventsTab.value = 'upcoming'
  const evSec = document.getElementById('events-section')
  if (evSec) {
    evSec.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }
}

const handleAnnouncementAction = (post) => {
  if (!post) return
  if (isRsvpAnnouncement(post)) {
    handleAcknowledgeAnnouncement(post)
    scrollToEvents()
    showToast('Navigating to Upcoming Gigs for RSVP confirmation', 'info')
  } else {
    handleAcknowledgeAnnouncement(post)
  }
}

const handleAcknowledgeAnnouncement = async (ann) => {
  if (!ann || !store.user) return
  if (isAcknowledged(ann.id)) return

  const pubTime = new Date(ann.rawDate || Date.now()).getTime()
  const now = Date.now()
  const latencySeconds = Math.max(1, Math.round((now - pubTime) / 1000))
  let formattedLatency = ''
  if (latencySeconds < 60) {
    formattedLatency = `${latencySeconds}s`
  } else if (latencySeconds < 3600) {
    formattedLatency = `${Math.round(latencySeconds / 60)}m`
  } else if (latencySeconds < 86400) {
    formattedLatency = `${Math.round(latencySeconds / 3600)}h`
  } else {
    formattedLatency = `${Math.round(latencySeconds / 86400)}d`
  }

  const ackRecord = {
    ackAt: new Date().toISOString(),
    latencySeconds,
    formattedLatency
  }

  userAcknowledgments.value[ann.id] = ackRecord
  ann.ackCount = (ann.ackCount || 0) + 1

  // Save locally in persistent browser storage
  try {
    localStorage.setItem(`smartband_ack_${store.user.id}`, JSON.stringify(userAcknowledgments.value))
  } catch (e) {}

  notifyOtherTabs('ANNOUNCEMENT_ACKNOWLEDGED', { annId: ann.id })
  showToast(`✓ Acknowledged "${ann.title}"`, 'success')
}

// INSTANT REALTIME EVENT LISTENER (0ms latency for newly scheduled events on members' dashboards)
const handleLiveEventUpdate = (e) => {
  const payload = e?.detail || {}
  const eventType = payload.eventType || 'INSERT'
  const record = payload.new || payload

  if (record && record.id) {
    if (eventType === 'DELETE') {
      rawEvents.value = rawEvents.value.filter(x => x.id !== record.id)
    } else {
      const evDate = new Date(record.event_date)
      const formattedEv = {
        id: record.id,
        rawDate: record.event_date,
        title: record.title,
        date: evDate.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }),
        time: evDate.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }),
        location: record.location,
        type: record.event_type,
        rsvpStatus: localStorage.getItem(`smartband_rsvp_${record.id}`) || null,
        createdAt: record.created_at || new Date().toISOString()
      }
      const exists = rawEvents.value.some(x => x.id === record.id)
      if (exists) {
        rawEvents.value = rawEvents.value.map(x => x.id === record.id ? formattedEv : x)
      } else {
        rawEvents.value = [formattedEv, ...rawEvents.value]
      }
    }
  }
  fetchHomeData(true)
}

let cleanupSync = null

const handleVisibilityOrFocus = () => {
  if (!document.hidden) {
    fetchHomeData(true)
  }
}

onMounted(() => {
  loadLocalAcknowledgments()
  fetchHomeData()

  // Initialize push notification permission state
  requestPushPermission().then(perm => {
    pushPermission.value = perm
  })

  // 1. Centralized Master Realtime Sync (WebSockets + Inter-Tab)
  cleanupSync = initRealtimeSync((event) => {
    fetchHomeData(true)
    if (showAttendanceModal.value && selectedEventForAttendance.value) {
      openAttendanceTracker(selectedEventForAttendance.value)
    }
  })

  // 2. Direct Window Realtime Event Listener for instant display of new events
  window.addEventListener('smartband_event_changed', handleLiveEventUpdate)

  // 3. Optimized Auto-Polling Fallback (Every 12s, paused if backgrounded)
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
  window.removeEventListener('smartband_event_changed', handleLiveEventUpdate)
  window.removeEventListener('focus', handleVisibilityOrFocus)
  document.removeEventListener('visibilitychange', handleVisibilityOrFocus)
})
</script>

<template>
  <div class="space-y-6 relative">
    
    <!-- Clean Header Title -->
    <div class="flex items-center justify-between pt-1">
      <div>
        <p class="text-xs font-medium text-[var(--md-on-surface-variant)]">
          {{ store.currentRole === 'super_admin' ? 'IT Super Admin' : store.currentRole === 'secretary_admin' ? 'Band Secretary' : 'Welcome back' }}
        </p>
        <h1 class="text-2xl font-bold text-[var(--md-on-surface)] tracking-tight">Dashboard</h1>
      </div>
    </div>

    <!-- PENDING APPROVALS QUEUE (Super Admin Only) -->
    <section v-if="store.canApproveAccounts && pendingAccounts.length > 0" class="bg-[var(--md-surface-container)] border border-amber-500/30 dark:border-amber-500/20 rounded-2xl p-4 sm:p-5 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2">
          <ShieldAlert class="w-4 h-4 text-amber-600 dark:text-amber-400" />
          <h2 class="font-semibold text-xs sm:text-sm text-[var(--md-on-surface)]">Pending Master List Approvals</h2>
        </div>
        <span class="text-xs font-semibold bg-amber-500/15 text-amber-800 dark:text-amber-300 border border-amber-500/30 px-3 py-1 rounded-full">
          {{ pendingAccounts.length }} Pending
        </span>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div v-for="acc in pendingAccounts" :key="acc.id" class="bg-[var(--md-surface)] p-3.5 rounded-2xl border border-[var(--md-outline-variant)]/60 flex items-center justify-between shadow-xs">
          <div>
            <p class="font-semibold text-xs text-[var(--md-on-surface)]">{{ acc.full_name }} ({{ acc.instrument }})</p>
            <p class="text-[11px] text-[var(--md-on-surface-variant)]">{{ acc.email }}</p>
          </div>
          <div class="flex items-center space-x-2">
            <button @click="approveAccount(acc.id)" type="button" class="m3-btn-filled text-xs px-4 min-h-[44px]">Approve</button>
            <button @click="promptRejectAccount(acc.id)" type="button" class="m3-btn-outlined text-xs px-4 min-h-[44px] text-rose-600 dark:text-rose-400 border-rose-300 dark:border-rose-900/50 hover:bg-rose-50 dark:hover:bg-rose-950/20">Decline</button>
          </div>
        </div>
      </div>
    </section>

    <!-- Member Profile Summary Card (Official M3 Outlined Card) -->
    <div class="m3-card-outlined p-4 sm:p-5 flex items-center justify-between">
      <div class="flex items-center space-x-3.5">
        <div class="w-12 h-12 rounded-full overflow-hidden flex-shrink-0 border border-[var(--md-outline-variant)] relative bg-[var(--md-surface-container)]">
          <img v-if="store.profile?.profile_picture" 
               :src="store.profile.profile_picture" 
               alt="Avatar" 
               width="48"
               height="48"
               class="w-full h-full object-cover" />
          <div v-else class="w-full h-full text-[var(--md-on-surface)] flex items-center justify-center font-bold text-sm">
            {{ store.profile?.full_name ? store.profile.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB' }}
          </div>
        </div>
        <div>
          <div class="flex items-center space-x-2">
            <span class="font-bold text-[var(--md-on-surface)] text-base leading-tight">
              {{ store.profile?.full_name || 'Band Member' }}
            </span>
            <span v-if="store.profile?.is_verified" class="m3-chip m3-chip-info h-7 px-3 text-xs font-semibold">Verified</span>
            <span v-else class="m3-chip m3-chip-rsvp h-7 px-3 text-xs font-semibold">Pending</span>
            <span v-if="!store.profile?.is_verified" class="m3-chip m3-chip-assist h-7 px-3 text-xs">
              {{ pushPermission === 'granted' ? 'Push ✓' : pushPermission === 'denied' ? 'Push ×' : 'Push ⚠' }}
            </span>
          </div>
          <p class="text-xs text-[var(--md-on-surface-variant)] flex items-center mt-1 font-medium capitalize">
            <TrendingUp class="w-3.5 h-3.5 mr-1 text-emerald-600 dark:text-emerald-400 flex-shrink-0" />
            {{ store.profile?.rank || 'Junior' }} Rank • {{ store.profile?.reliability_score || 100 }}% Reliability
          </p>
        </div>
      </div>
    </div>

    <!-- RESPONSIVE GRID ON DESKTOP -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 items-start">
      
      <!-- AUTOMATIC EVENTS & GIGS SECTION -->
      <section id="events-section" class="space-y-3">
        <div class="flex items-center justify-between gap-2 px-1">
          <div>
            <h2 class="text-base sm:text-lg font-bold text-[var(--md-on-surface)] tracking-tight">Events &amp; Call-Times</h2>
          </div>
          <button 
            v-if="store.canManageEvents" 
            @click="showEventModal = true" 
            type="button" 
            class="m3-btn-outlined min-h-[44px] text-xs px-4 font-semibold shrink-0"
          >
            <Plus class="w-4 h-4 mr-1.5" /> Schedule Event
          </button>
        </div>

        <!-- Upcoming vs Attending vs Past Segmented Control (Zero wrap full width) -->
        <div class="grid grid-cols-3 p-1 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 text-xs font-medium w-full">
          <button 
            @click="activeEventsTab = 'upcoming'"
            type="button"
            class="py-2.5 px-1 rounded-xl transition-all min-h-[44px] flex items-center justify-center cursor-pointer text-center"
            :class="activeEventsTab === 'upcoming' 
              ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
              : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            <Calendar class="w-3.5 h-3.5 mr-1 text-[var(--md-primary)] shrink-0" />
            <span class="truncate">Upcoming ({{ upcomingEvents.length }})</span>
          </button>

          <!-- Dedicated View for User's Accepted Gigs -->
          <button 
            @click="activeEventsTab = 'accepted'"
            type="button"
            class="py-2.5 px-1 rounded-xl transition-all min-h-[44px] flex items-center justify-center cursor-pointer text-center"
            :class="activeEventsTab === 'accepted' 
              ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
              : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            <CheckCircle class="w-3.5 h-3.5 mr-1 text-emerald-600 dark:text-emerald-400 shrink-0" />
            <span class="truncate">Attending ({{ myAcceptedEvents.length }})</span>
          </button>

          <button 
            @click="activeEventsTab = 'past'"
            type="button"
            class="py-2.5 px-1 rounded-xl transition-all min-h-[44px] flex items-center justify-center cursor-pointer text-center"
            :class="activeEventsTab === 'past' 
              ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
              : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            <History class="w-3.5 h-3.5 mr-1 text-[var(--md-outline)] shrink-0" />
            <span class="truncate">Past ({{ pastEvents.length }})</span>
          </button>
        </div>

        <!-- 1. UPCOMING EVENTS TAB VIEW -->
        <div v-if="activeEventsTab === 'upcoming'">
          <div v-if="upcomingEvents.length > 0" class="space-y-3">
            <div 
              v-for="ev in upcomingEvents" 
              :key="ev.id"
              class="m3-card-elevated p-5 relative overflow-hidden border border-[var(--md-outline-variant)]/40 hover:shadow-md transition-all"
            >
              <div class="relative z-10">
                <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
                  <span class="m3-chip m3-chip-assist h-7 text-xs px-3">
                    {{ ev.type }}
                  </span>
                  
                  <div class="flex items-center space-x-1.5 shrink-0">
                    <button 
                      v-if="store.canConductRollCall || store.canManageEvents" 
                      @click="openAttendanceTracker(ev)" 
                      type="button"
                      class="m3-btn-tonal text-xs px-3.5 min-h-[44px] flex items-center"
                    >
                      <Users class="w-3.5 h-3.5 mr-1.5" /> Attendance Check
                    </button>
                    <button 
                      v-if="store.canManageEvents" 
                      @click="promptDeleteEvent(ev.id)" 
                      type="button"
                      aria-label="Delete Event" 
                      class="p-2 rounded-full text-[var(--md-outline)] hover:text-[var(--md-error)] hover:bg-[var(--md-surface-container-high)] cursor-pointer min-w-[44px] min-h-[44px] flex items-center justify-center transition-colors" 
                      title="Delete Event"
                    >
                      <Trash2 class="w-4 h-4" />
                    </button>
                  </div>
                </div>
                
                <h3 class="text-lg font-bold mb-2 leading-snug text-[var(--md-on-surface)]">{{ ev.title }}</h3>
                
                <div class="space-y-1 mb-4 text-xs font-medium text-[var(--md-on-surface-variant)]">
                  <div class="flex items-center">
                    <Calendar class="w-3.5 h-3.5 mr-2 flex-shrink-0 text-[var(--md-outline)]" />
                    <span>{{ ev.date }} at {{ ev.time }}</span>
                  </div>
                  <div class="flex items-center">
                    <MapPin class="w-3.5 h-3.5 mr-2 flex-shrink-0 text-[var(--md-outline)]" />
                    <span>{{ ev.location }}</span>
                  </div>
                </div>

                <!-- Attendance Action Buttons (Official M3 Filled & Outlined Buttons - WCAG 44px) -->
                <div v-if="!ev.rsvpStatus" class="grid grid-cols-2 gap-2 pt-1">
                  <button 
                    @click="rsvp(ev, 'attending')"
                    type="button"
                    aria-label="Confirm attendance for this event"
                    class="m3-btn-filled text-xs font-semibold py-2.5 px-4 min-h-[44px]"
                  >
                    <CheckCircle class="w-4 h-4 mr-1.5" />
                    <span>Attending</span>
                  </button>
                  <button 
                    @click="promptDeclineWithExcuse(ev)"
                    type="button"
                    aria-label="Cannot attend event and submit excuse justification"
                    class="m3-btn-outlined text-xs font-semibold py-2.5 px-4 min-h-[44px]"
                  >
                    <XCircle class="w-4 h-4 mr-1.5 text-[var(--md-error)]" />
                    <span>Not Attending</span>
                  </button>
                </div>
                
                <!-- Color-Coded Confirmed Attendance Status with Excuse Details -->
                <div v-else class="p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)]/40 rounded-xl space-y-1">
                  <div class="flex items-center justify-between">
                    <span class="font-medium text-xs flex items-center" :class="ev.rsvpStatus === 'attending' ? 'text-emerald-700 dark:text-emerald-400' : 'text-[var(--md-error)]'">
                      <CheckCircle v-if="ev.rsvpStatus === 'attending'" class="w-4 h-4 mr-1.5" />
                      <XCircle v-else class="w-4 h-4 mr-1.5" />
                      {{ ev.rsvpStatus === 'attending' ? 'Attending' : 'Not Attending' }}
                    </span>
                    <button @click="ev.rsvpStatus = null" aria-label="Change Attendance Status" class="m3-btn-text text-xs min-h-[44px] px-3 font-medium text-[var(--md-primary)] hover:underline">Change</button>
                  </div>
                  <p v-if="ev.rsvpStatus === 'declined' && ev.excuseJustification" class="text-[11px] text-[var(--md-on-surface-variant)] italic">
                    Reason: {{ ev.excuseJustification }}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <div v-else class="m3-card-outlined p-8 text-center">
            <Calendar class="w-8 h-8 text-[var(--md-outline)] mx-auto mb-2" />
            <p class="text-sm font-semibold text-[var(--md-on-surface)]">No upcoming events scheduled.</p>
            <p class="text-xs text-[var(--md-on-surface-variant)] mt-1">Past events are automatically archived in the Past tab.</p>
          </div>
        </div>

        <!-- 2. DEDICATED VIEW FOR USER'S ACCEPTED EVENTS -->
        <div v-else-if="activeEventsTab === 'accepted'">
          <div v-if="myAcceptedEvents.length > 0" class="space-y-3">
            <div 
              v-for="ev in myAcceptedEvents" 
              :key="ev.id"
              class="m3-card-elevated p-5 relative overflow-hidden border border-[var(--md-outline-variant)]/40 hover:shadow-md transition-all"
            >
              <div class="relative z-10">
                <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
                  <div class="flex flex-wrap items-center gap-1.5">
                    <span class="m3-chip m3-chip-assist h-7 text-xs px-3">
                      {{ ev.type }}
                    </span>
                    <span class="m3-chip m3-chip-info h-7 text-xs px-3 font-semibold">
                      ✓ Confirmed
                    </span>
                  </div>
                  
                  <div class="flex items-center space-x-1.5 shrink-0">
                    <button 
                      v-if="store.canConductRollCall || store.canManageEvents" 
                      @click="openAttendanceTracker(ev)" 
                      type="button"
                      class="m3-btn-tonal text-xs px-3.5 min-h-[44px] flex items-center"
                    >
                      <Users class="w-3.5 h-3.5 mr-1.5" /> Attendance Check
                    </button>
                  </div>
                </div>
                
                <h3 class="text-lg font-bold mb-2 leading-snug text-[var(--md-on-surface)]">{{ ev.title }}</h3>
                
                <div class="space-y-1 mb-4 text-xs font-medium text-[var(--md-on-surface-variant)]">
                  <div class="flex items-center">
                    <Calendar class="w-3.5 h-3.5 mr-2 flex-shrink-0 text-[var(--md-outline)]" />
                    <span>{{ ev.date }} at {{ ev.time }}</span>
                  </div>
                  <div class="flex items-center">
                    <MapPin class="w-3.5 h-3.5 mr-2 flex-shrink-0 text-[var(--md-outline)]" />
                    <span>{{ ev.location }}</span>
                  </div>
                </div>

                <!-- Confirmed Status Banner & Change Option -->
                <div class="flex items-center justify-between p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)]/40 rounded-xl">
                  <div class="flex items-center space-x-2 text-[var(--md-on-surface)]">
                    <CheckCircle class="w-4 h-4 text-emerald-600 dark:text-emerald-400 flex-shrink-0" />
                    <span class="font-medium text-xs">You are scheduled to attend this call-time.</span>
                  </div>
                  <button @click="ev.rsvpStatus = null" type="button" class="m3-btn-text text-xs min-h-[44px] px-3 font-medium text-[var(--md-primary)] hover:underline">Change</button>
                </div>
              </div>
            </div>
          </div>

          <div v-else class="m3-card-outlined p-8 text-center space-y-3">
            <div class="w-10 h-10 rounded-full bg-[var(--md-surface-container-high)] text-[var(--md-outline)] mx-auto flex items-center justify-center">
              <CheckCircle class="w-5 h-5" />
            </div>
            <p class="text-sm font-semibold text-[var(--md-on-surface)]">No accepted events on your schedule yet.</p>
            <p class="text-xs text-[var(--md-on-surface-variant)] max-w-sm mx-auto">
              Browse the <strong>Upcoming</strong> tab and click <strong>"Attending"</strong> to add gigs to your schedule.
            </p>
            <button @click="activeEventsTab = 'upcoming'" type="button" class="m3-btn-filled text-xs min-h-[44px] px-5">
              View Upcoming Events
            </button>
          </div>
        </div>

        <!-- 3. PAST GIGS HISTORY TAB VIEW (Automatically Archived) -->
        <div v-else-if="activeEventsTab === 'past'">
          <div v-if="pastEvents.length > 0" class="space-y-3">
            <div 
              v-for="ev in pastEvents" 
              :key="ev.id"
              class="m3-card-elevated p-4 sm:p-5 border border-[var(--md-outline-variant)]/40 space-y-3 hover:shadow-md transition-all"
            >
              <div class="flex items-start justify-between">
                <div>
                  <div class="flex items-center space-x-1.5">
                    <span class="m3-chip m3-chip-assist h-7 text-xs px-3">
                      {{ ev.type }}
                    </span>
                    <span class="m3-chip m3-chip-neutral h-7 text-xs px-3">
                      Completed
                    </span>
                  </div>
                  <h3 class="font-bold text-base text-[var(--md-on-surface)] mt-1 leading-snug">{{ ev.title }}</h3>
                </div>

                <div class="flex items-center space-x-1.5">
                  <button 
                    v-if="store.canConductRollCall || store.canManageEvents" 
                    @click="openAttendanceTracker(ev)" 
                    type="button"
                    class="m3-btn-tonal text-xs px-3.5 min-h-[44px] flex items-center"
                  >
                    <Users class="w-3.5 h-3.5 mr-1.5" /> Log
                  </button>
                  <button 
                    v-if="store.canManageEvents" 
                    @click="promptDeleteEvent(ev.id)" 
                    type="button"
                    aria-label="Delete Event"
                    class="p-2 rounded-full text-[var(--md-outline)] hover:text-[var(--md-error)] cursor-pointer min-w-[44px] min-h-[44px] flex items-center justify-center transition-colors hover:bg-[var(--md-surface-container-high)]"
                    title="Delete Record"
                  >
                    <Trash2 class="w-4 h-4" />
                  </button>
                </div>
              </div>

              <div class="grid grid-cols-2 gap-2 text-xs font-medium text-[var(--md-on-surface-variant)] bg-[var(--md-surface-container)] p-3 rounded-xl">
                <div class="flex items-center"><Calendar class="w-3.5 h-3.5 mr-1.5 text-[var(--md-outline)]" /> {{ ev.date }}</div>
                <div class="flex items-center"><Clock class="w-3.5 h-3.5 mr-1.5 text-[var(--md-outline)]" /> {{ ev.time }}</div>
                <div class="col-span-2 flex items-center"><MapPin class="w-3.5 h-3.5 mr-1.5 text-[var(--md-outline)]" /> {{ ev.location }}</div>
              </div>
            </div>
          </div>

          <div v-else class="m3-card-outlined p-8 text-center">
            <History class="w-8 h-8 text-[var(--md-outline)] mx-auto mb-2" />
            <p class="text-sm font-semibold text-[var(--md-on-surface)]">No past gigs recorded yet.</p>
          </div>

          <!-- Pagination: Server-side Load More Events (Item 30) -->
          <div v-if="hasMoreEvents" class="pt-2 text-center">
            <button 
              @click="loadMoreEvents" 
              :disabled="isLoadingMoreEvents"
              type="button" 
              class="m3-btn-outlined text-xs min-h-[40px] px-6 inline-flex items-center mx-auto"
            >
              <RefreshCw v-if="isLoadingMoreEvents" class="w-3.5 h-3.5 mr-1.5 animate-spin" />
              <span>{{ isLoadingMoreEvents ? 'Loading More Events...' : 'Load More Events (50)' }}</span>
            </button>
          </div>
        </div>
      </section>

      <!-- Announcements Section -->
      <section class="space-y-3">
        <div class="flex items-center justify-between gap-2 px-1">
          <div>
            <h2 class="text-base sm:text-lg font-bold text-[var(--md-on-surface)] tracking-tight">Notice Board</h2>
          </div>
          <button 
            v-if="store.canManageAnnouncements" 
            @click="showAnnouncementModal = true" 
            type="button" 
            class="m3-btn-outlined min-h-[44px] text-xs px-4 font-semibold shrink-0"
          >
            <Plus class="w-4 h-4 mr-1.5" /> Post Notice
          </button>
        </div>

        <!-- Announcements Tab Pill Toggle (Full Width Grid 2-cols) -->
        <div class="grid grid-cols-2 p-1 bg-[var(--md-surface-container)] rounded-2xl border border-[var(--md-outline-variant)]/40 text-xs font-medium w-full">
          <button 
            @click="activeAnnouncementTab = 'recent'"
            type="button"
            class="py-2.5 px-2 rounded-xl transition-all min-h-[44px] flex items-center justify-center cursor-pointer text-center"
            :class="activeAnnouncementTab === 'recent' 
              ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
              : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            <Bell class="w-3.5 h-3.5 mr-1.5 text-[var(--md-primary)] shrink-0" />
            <span class="truncate">Recent ({{ recentAnnouncements.length }})</span>
          </button>

          <button 
            @click="activeAnnouncementTab = 'archived'"
            type="button"
            class="py-2.5 px-2 rounded-xl transition-all min-h-[44px] flex items-center justify-center cursor-pointer text-center"
            :class="activeAnnouncementTab === 'archived' 
              ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' 
              : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            <History class="w-3.5 h-3.5 mr-1.5 text-[var(--md-outline)] shrink-0" />
            <span class="truncate">Archived ({{ archivedAnnouncements.length }})</span>
          </button>
        </div>

        <!-- 1. Skeleton Loading State (Item 20) -->
        <div v-if="isLoading" class="m3-card-outlined p-4 sm:p-5 space-y-3">
          <div v-for="i in 3" :key="i" class="m3-card-elevated p-4 rounded-2xl animate-pulse space-y-3 border border-[var(--md-outline-variant)]/40">
            <div class="flex items-center space-x-2">
              <div class="h-5 w-20 bg-slate-200 dark:bg-neutral-800 rounded-md"></div>
              <div class="h-5 w-16 bg-slate-200 dark:bg-neutral-800 rounded-md"></div>
            </div>
            <div class="h-4 bg-slate-200 dark:bg-neutral-800 rounded w-3/4"></div>
            <div class="h-3 bg-slate-200 dark:bg-neutral-800 rounded w-full"></div>
            <div class="h-3 bg-slate-200 dark:bg-neutral-800 rounded w-2/3"></div>
          </div>
        </div>

        <!-- 2. Error State with Retry CTA (Item 21) -->
        <div v-else-if="loadError" class="m3-card-outlined p-6 text-center space-y-3 border-rose-300 dark:border-rose-900/50">
          <AlertCircle class="w-8 h-8 text-rose-600 dark:text-rose-400 mx-auto" />
          <h3 class="text-sm font-bold text-slate-900 dark:text-neutral-100">Unable to Load Announcements</h3>
          <p class="text-xs text-slate-600 dark:text-neutral-400 max-w-sm mx-auto">{{ loadError }}</p>
          <button @click="fetchHomeData(true)" type="button" class="m3-btn-filled text-xs min-h-[40px] px-5 inline-flex items-center mx-auto">
            <RefreshCw class="w-3.5 h-3.5 mr-1.5" /> Retry Connection
          </button>
        </div>

        <div v-else-if="displayedAnnouncements.length > 0" class="m3-card-outlined p-4 sm:p-5 shadow-xs flex flex-col max-h-[460px] overflow-y-auto space-y-3">
          <article 
            v-for="post in displayedAnnouncements" 
            :key="post.id"
            class="m3-card-elevated p-4 sm:p-5 border border-[var(--md-outline-variant)]/40 transition-all hover:shadow-md"
          >
            <!-- Urgency & Target Section Chips (Official M3 Chips: 8dp Radius, 32dp Height) -->
            <div class="flex items-center justify-between gap-2 mb-2.5">
              <div class="flex flex-wrap items-center gap-1.5">
                <!-- Action Required M3 Chip -->
                <span 
                  v-if="isRsvpAnnouncement(post)" 
                  class="m3-chip m3-chip-urgent"
                >
                  <AlertTriangle class="w-4 h-4 text-[var(--md-error)]" />
                  <span>Action Required</span>
                </span>
                
                <!-- Attendance Notice M3 Chip -->
                <span 
                  v-if="isRsvpAnnouncement(post)" 
                  class="m3-chip m3-chip-rsvp"
                >
                  <CalendarCheck class="w-4 h-4 text-[var(--md-tertiary)]" />
                  <span>Attendance Notice</span>
                </span>

                <!-- General High Urgency -->
                <span 
                  v-else-if="isUrgentAnnouncement(post)" 
                  class="m3-chip m3-chip-urgent"
                >
                  <AlertTriangle class="w-4 h-4 text-[var(--md-error)]" />
                  <span>High Urgency</span>
                </span>

                <!-- Medium Priority -->
                <span 
                  v-else-if="post.priority === 'MEDIUM'" 
                  class="m3-chip m3-chip-rsvp"
                >
                  <span>Medium Priority</span>
                </span>

                <!-- General Informational Notice -->
                <span 
                  v-else 
                  class="m3-chip m3-chip-assist"
                >
                  <span>General Notice</span>
                </span>

                <!-- Target Section M3 Chip -->
                <span 
                  v-if="post.targetSection && post.targetSection !== 'all'"
                  class="m3-chip m3-chip-info capitalize"
                >
                  {{ post.targetSection }}
                </span>
              </div>

              <div class="flex items-center space-x-1.5 shrink-0">
                <span class="text-xs font-medium text-[var(--md-on-surface-variant)]">{{ post.date }}</span>
                <button 
                  v-if="store.canManageAnnouncements" 
                  @click="promptDeleteAnnouncement(post.id)" 
                  type="button"
                  aria-label="Delete Announcement"
                  class="text-[var(--md-outline)] hover:text-[var(--md-error)] cursor-pointer p-2 rounded-full min-w-[44px] min-h-[44px] flex items-center justify-center transition-colors hover:bg-[var(--md-surface-container-high)]" 
                  title="Delete Announcement"
                >
                  <Trash2 class="w-4 h-4" />
                </button>
              </div>
            </div>

            <h3 class="font-semibold text-base sm:text-lg text-[var(--md-on-surface)] leading-snug mb-1.5">{{ post.title }}</h3>
            <p class="text-xs sm:text-sm text-[var(--md-on-surface-variant)] leading-relaxed mb-3.5 whitespace-pre-wrap">
              {{ post.content }}
            </p>

            <!-- Bottom Row: Author & Two-Way Acknowledgment (TC-05 & SOP 2.4) -->
            <div class="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-[var(--md-outline-variant)]/30">
              <span class="text-xs font-medium text-[var(--md-on-surface-variant)] flex items-center">
                <User class="w-3.5 h-3.5 mr-1.5 text-[var(--md-outline)]" />
                {{ post.author }}
                <span v-if="post.ackCount > 0" class="text-[11px] text-[var(--md-outline)] font-normal ml-2">
                  ({{ post.ackCount }} read)
                </span>
              </span>

              <!-- High-Contrast Action Triggers (Official M3 Buttons) -->
              <div class="flex items-center space-x-2">
                <!-- State 1: Action Required (Not yet read / confirmed) -->
                <template v-if="!isAcknowledged(post.id)">
                  <!-- If notice demands an attendance confirmation, show direct Action Trigger -->
                  <button 
                    v-if="isRsvpAnnouncement(post)"
                    @click="handleAnnouncementAction(post)" 
                    type="button" 
                    aria-label="Confirm attendance for upcoming events" 
                    class="m3-btn-filled text-xs font-semibold px-5 min-h-[44px]"
                  >
                    <CalendarCheck class="w-4 h-4 mr-1.5" />
                    <span>Confirm Attendance</span>
                  </button>

                  <!-- Standard Notice Mark as Read Button -->
                  <button 
                    v-else 
                    @click="handleAcknowledgeAnnouncement(post)" 
                    type="button" 
                    aria-label="Mark notice as read" 
                    class="m3-btn-filled text-xs font-semibold px-5 min-h-[44px]"
                  >
                    <Check class="w-4 h-4 mr-1.5" />
                    <span>Mark as Read</span>
                  </button>
                </template>

                <!-- State 2: Already Confirmed / Read -->
                <template v-else>
                  <span class="m3-chip m3-chip-info font-semibold h-10 px-4 rounded-full">
                    <Check class="w-4 h-4 mr-1.5 text-emerald-600 dark:text-emerald-400" />
                    <span>{{ isRsvpAnnouncement(post) ? 'Confirmed' : 'Read' }}</span>
                  </span>

                  <!-- Secondary View Schedule link button for attendance notices -->
                  <button 
                    v-if="isRsvpAnnouncement(post)"
                    @click="scrollToEvents"
                    type="button" 
                    aria-label="View upcoming schedules" 
                    class="m3-btn-outlined text-xs font-semibold px-4 min-h-[44px]"
                  >
                    <Calendar class="w-3.5 h-3.5 mr-1.5" />
                    <span>View Schedule</span>
                  </button>
                </template>
              </div>
            </div>
          </article>

          <!-- Pagination: Server-side Load More Announcements (Item 30) -->
          <div v-if="hasMoreAnn" class="pt-2 text-center">
            <button 
              @click="loadMoreAnnouncements" 
              :disabled="isLoadingMoreAnn"
              type="button" 
              class="m3-btn-outlined text-xs min-h-[40px] px-6 inline-flex items-center mx-auto"
            >
              <RefreshCw v-if="isLoadingMoreAnn" class="w-3.5 h-3.5 mr-1.5 animate-spin" />
              <span>{{ isLoadingMoreAnn ? 'Loading More Notices...' : 'Load More Notices (50)' }}</span>
            </button>
          </div>
        </div>

        <!-- 4. Empty State with CTA (Item 22) -->
        <div v-else class="m3-card-outlined p-8 text-center space-y-3">
          <div class="w-12 h-12 rounded-full bg-[var(--md-surface-container)] flex items-center justify-center mx-auto text-[var(--md-outline)]">
            <Bell class="w-6 h-6" />
          </div>
          <div>
            <h3 class="text-sm font-bold text-[var(--md-on-surface)]">No Announcements Posted Yet</h3>
            <p class="text-xs text-[var(--md-on-surface-variant)] mt-1 max-w-sm mx-auto">
              Broadcast urgent call-times, marching rehearsals, and uniform guidelines to the band.
            </p>
          </div>
          <button 
            v-if="store.canPostAnnouncements" 
            @click="showAnnouncementModal = true" 
            type="button" 
            class="m3-btn-filled text-xs min-h-[40px] px-5 inline-flex items-center mx-auto"
          >
            <Plus class="w-3.5 h-3.5 mr-1.5" /> Post Announcement
          </button>
          <button 
            v-else 
            @click="fetchHomeData(true)" 
            type="button" 
            class="m3-btn-outlined text-xs min-h-[40px] px-5 inline-flex items-center mx-auto"
          >
            <RefreshCw class="w-3.5 h-3.5 mr-1.5" /> Check for Updates
          </button>
        </div>
      </section>

    </div>

    <!-- SECRETARY / ADMIN EVENT ATTENDANCE TRACKER & ATTENDANCE CHECK MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showAttendanceModal" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-3 sm:p-4" @click.self="showAttendanceModal = false">
      <div 
        role="dialog" 
        aria-modal="true" 
        aria-labelledby="attendance-modal-title"
        tabindex="-1"
        @keydown.escape="showAttendanceModal = false"
        class="m3-surface-modal p-4 sm:p-6 max-w-md sm:max-w-lg w-full space-y-4 shadow-xl text-left max-h-[90vh] flex flex-col"
      >
        
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
          <button @click="showAttendanceModal = false" type="button" aria-label="Close modal" class="text-[var(--md-outline)] hover:text-[var(--md-on-surface)] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer rounded-full hover:bg-[var(--md-surface-container)]">
            <X class="w-4 h-4" />
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
              <CheckCircle class="w-4 h-4 mr-1.5" />
              <span>{{ isBatchMarking ? 'Updating...' : 'Mark Attending as Present' }}</span>
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
            :class="attendanceTabFilter === 'attending' ? 'bg-[var(--md-surface)] text-emerald-600 dark:text-emerald-400 shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
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
                <CheckCircle class="w-3.5 h-3.5 mr-1 text-emerald-500" /> Present
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

    <!-- CREATE ANNOUNCEMENT MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showAnnouncementModal" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4" @click.self="showAnnouncementModal = false">
      <div 
        role="dialog" 
        aria-modal="true" 
        aria-labelledby="announcement-modal-title"
        tabindex="-1"
        @keydown.escape="showAnnouncementModal = false"
        class="m3-surface-modal p-6 max-w-sm sm:max-w-md w-full space-y-4 shadow-xl text-left"
      >
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/40 pb-2">
          <div>
            <h3 id="announcement-modal-title" class="font-bold text-base text-[var(--md-on-surface)]">Post Announcement</h3>
            <p class="text-[11px] text-[var(--md-on-surface-variant)]">Broadcasts to musician dashboards &amp; closed devices</p>
          </div>
          <button @click="showAnnouncementModal = false" type="button" aria-label="Close modal" class="text-[var(--md-outline)] hover:text-[var(--md-on-surface)] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer rounded-full hover:bg-[var(--md-surface-container)]">
            <X class="w-4 h-4" />
          </button>
        </div>
        <div class="space-y-3">
          <div>
            <label for="ann-priority-in" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Urgency Level *</label>
            <select id="ann-priority-in" v-model="newAnnPriority" class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)] cursor-pointer">
              <option value="HIGH">🚨 High Urgency (Triggers Brass Fanfare Siren)</option>
              <option value="MEDIUM">⚠️ Medium (Standard Notice / Rehearsal Update)</option>
              <option value="LOW">ℹ️ Low (General Band Announcement)</option>
            </select>
          </div>
          <div>
            <label for="ann-target-in" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Target Section *</label>
            <select id="ann-target-in" v-model="newAnnTargetSection" class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)] cursor-pointer">
              <option value="all">All Sections (Entire Marching Band)</option>
              <option value="woodwinds">Woodwinds (Clarinet, Flute, Saxophone)</option>
              <option value="brass">Brass (Trumpet, Trombone, Euphonium, Tuba)</option>
              <option value="percussion">Percussion (Snare, Bass Drum, Cymbals)</option>
              <option value="officers">Officers &amp; Section Leaders</option>
            </select>
          </div>
          <div>
            <label for="ann-title-in" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Title</label>
            <input id="ann-title-in" v-model="newAnnTitle" type="text" placeholder="e.g. Call Time for Town Procession" class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)]">
          </div>
          <div>
            <label for="ann-content-in" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Content</label>
            <textarea id="ann-content-in" v-model="newAnnContent" rows="3" placeholder="Write full call-time details..." class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] focus:outline-none focus:border-[var(--md-outline)]"></textarea>
          </div>
        </div>
        <div class="flex space-x-2 pt-2">
          <button @click="showAnnouncementModal = false" type="button" class="m3-btn-outlined flex-1 min-h-[48px]">Cancel</button>
          <button @click="handleCreateAnnouncement" :disabled="isSubmitting" type="button" class="m3-btn-filled flex-1 min-h-[48px]">
            {{ isSubmitting ? 'Posting...' : 'Post Notice' }}
          </button>
        </div>
      </div>
    </div>

    <!-- CREATE EVENT MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showEventModal" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4" @click.self="showEventModal = false">
      <div 
        role="dialog" 
        aria-modal="true" 
        aria-labelledby="event-modal-title"
        tabindex="-1"
        @keydown.escape="showEventModal = false"
        class="m3-surface-modal p-6 max-w-sm sm:max-w-md w-full space-y-4 shadow-xl text-left"
      >
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/40 pb-2">
          <h3 id="event-modal-title" class="font-bold text-base text-[var(--md-on-surface)]">Schedule Event</h3>
          <button @click="showEventModal = false" type="button" aria-label="Close modal" class="text-[var(--md-outline)] hover:text-[var(--md-on-surface)] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer rounded-full hover:bg-[var(--md-surface-container)]">
            <X class="w-4 h-4" />
          </button>
        </div>
        <div class="space-y-3">
          <div>
            <label for="ev-title-in" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Event Title</label>
            <input id="ev-title-in" v-model="newEvTitle" type="text" placeholder="e.g. Town Fiesta Parade" class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)]">
          </div>
          <div>
            <label for="ev-type-in" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Event Type</label>
            <select id="ev-type-in" v-model="newEvType" class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)] cursor-pointer">
              <option v-for="opt in eventTypeOptions" :key="opt" :value="opt">{{ opt }}</option>
            </select>
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label for="ev-date-in" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Date</label>
              <input id="ev-date-in" v-model="newEvDate" type="date" :min="minDateToday" class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)]">
            </div>
            <div>
              <label for="ev-time-in" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Time</label>
              <input id="ev-time-in" v-model="newEvTime" type="time" class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)]">
            </div>
          </div>
          <div>
            <label for="ev-loc-in" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Location</label>
            <input id="ev-loc-in" v-model="newEvLocation" type="text" placeholder="e.g. Town Plaza / Band Hall" class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)]">
          </div>
        </div>
        <div class="flex space-x-2 pt-2">
          <button @click="showEventModal = false" type="button" class="m3-btn-outlined flex-1 min-h-[48px]">Cancel</button>
          <button @click="handleCreateEvent" :disabled="isSubmitting" type="button" class="m3-btn-filled flex-1 min-h-[48px]">
            {{ isSubmitting ? 'Scheduling...' : 'Schedule' }}
          </button>
        </div>
      </div>
    </div>

    <!-- EXCUSE JUSTIFICATION MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showExcuseModal" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4" @click.self="showExcuseModal = false">
      <div 
        role="dialog" 
        aria-modal="true" 
        aria-labelledby="excuse-modal-title"
        tabindex="-1"
        @keydown.escape="showExcuseModal = false"
        class="m3-surface-modal p-6 max-w-sm sm:max-w-md w-full space-y-4 shadow-xl text-left"
      >
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/40 pb-2">
          <div>
            <h3 id="excuse-modal-title" class="font-bold text-base text-[var(--md-on-surface)]">Submit Absence Excuse</h3>
            <p class="text-[11px] text-[var(--md-on-surface-variant)]">Required for official band attendance log</p>
          </div>
          <button @click="showExcuseModal = false" type="button" aria-label="Close excuse modal" class="text-[var(--md-outline)] hover:text-[var(--md-on-surface)] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer rounded-full hover:bg-[var(--md-surface-container)]">
            <X class="w-4 h-4" />
          </button>
        </div>
        
        <div class="space-y-3">
          <p class="text-xs text-[var(--md-on-surface-variant)]">
            Declining call-time for: <strong class="text-[var(--md-on-surface)]">{{ eventForExcuse?.title }}</strong>
          </p>

          <div>
            <label class="block text-xs font-medium text-[var(--md-on-surface)] mb-1.5">Primary Reason</label>
            <div class="flex flex-wrap gap-1.5">
              <button 
                v-for="pill in excusePills" 
                :key="pill"
                type="button"
                @click="selectedExcusePill = pill"
                class="px-3 py-2 rounded-full text-xs font-medium transition-all cursor-pointer min-h-[40px]"
                :class="selectedExcusePill === pill 
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900 shadow-xs font-semibold' 
                  : 'bg-[var(--md-surface-container)] text-[var(--md-on-surface-variant)] hover:bg-[var(--md-surface-container-high)]'"
              >
                {{ pill }}
              </button>
            </div>
          </div>

          <div>
            <label for="excuse-note" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1">Additional Explanation (Optional)</label>
            <textarea 
              id="excuse-note" 
              v-model="customExcuseNote" 
              rows="3" 
              placeholder="e.g. Scheduled college midterm exam until 6:00 PM..." 
              class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] focus:outline-none focus:border-[var(--md-outline)]"></textarea>
          </div>
        </div>

        <div class="flex space-x-2 pt-2">
          <button @click="showExcuseModal = false" type="button" class="m3-btn-outlined flex-1 min-h-[48px]">Cancel</button>
          <button @click="confirmDeclineWithExcuse" :disabled="isSubmittingExcuse" type="button" class="m3-btn-filled flex-1 min-h-[48px] bg-rose-600 hover:bg-rose-700 text-white">
            {{ isSubmittingExcuse ? 'Submitting...' : 'Confirm Excuse' }}
          </button>
        </div>
      </div>
    </div>

    <!-- CONFIRM MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showConfirmModal" class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4" @click.self="showConfirmModal = false; confirmTargetId = null">
      <div 
        role="dialog" 
        aria-modal="true" 
        aria-labelledby="confirm-modal-title"
        tabindex="-1"
        @keydown.escape="showConfirmModal = false; confirmTargetId = null"
        class="m3-surface-modal p-6 max-w-sm w-full space-y-4 shadow-xl text-center"
      >
        <div class="w-12 h-12 rounded-full bg-rose-500/15 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        <div>
          <h3 id="confirm-modal-title" class="font-bold text-base text-[var(--md-on-surface)] leading-tight">Confirm Action?</h3>
          <p class="text-xs text-[var(--md-on-surface-variant)] mt-1 leading-relaxed">
            Are you sure you want to proceed?
          </p>
        </div>
        <div class="flex space-x-2 pt-2">
          <button @click="showConfirmModal = false; confirmTargetId = null" type="button" class="m3-btn-outlined flex-1 min-h-[48px]">Cancel</button>
          <button @click="executeConfirmedAction" type="button" class="m3-btn-filled flex-1 min-h-[48px] bg-rose-600 hover:bg-rose-700 text-white">Proceed</button>
        </div>
      </div>
    </div>

  </div>
</template>
