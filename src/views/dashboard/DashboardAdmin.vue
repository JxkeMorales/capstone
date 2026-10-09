<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { 
  Shield, 
  ShieldAlert, 
  UserCheck, 
  Send, 
  Cpu, 
  Calendar, 
  Trash2, 
  CheckCircle2, 
  AlertCircle, 
  X, 
  BarChart3, 
  FileText,
  Activity,
  Sparkles,
  Printer,
  TrendingUp,
  AlertTriangle,
  Award,
  Crown,
  Search,
  CheckCircle,
  XCircle,
  Users,
  Clock,
  MapPin,
  Filter,
  Download,
  Loader2,
  RotateCcw
} from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useUIStore } from '@/stores/ui'
import { useRouter } from 'vue-router'
import { supabase } from '@/supabase'
import { initRealtimeSync, broadcastSync } from '@/utils/realtime'
import { sendPushNotification } from '@/utils/push'
import { getBandLogoBase64 } from '@/utils/pdfExport'

const store = useMainStore()
const uiStore = useUIStore()
const router = useRouter()

// Sub-Tab Switcher State ('operations' | 'reports')
const activeTab = ref('operations')

const pendingAccounts = ref([])
const pendingAvatars = ref([])
const memberRoster = ref([])
const isDispatchGenerated = ref(false)

// Day and Week Accurate Availability State
const dayNamesList = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
const todayDayIndex = new Date().getDay()
const selectedDayNeeded = ref(dayNamesList[todayDayIndex])
const selectedSlotNeeded = ref('Morning (08:00 AM - 12:00 PM)')
const selectedInstrumentNeeded = ref('All')
const availableUserIds = ref(new Set())
const matchedDispatchRoster = ref([])

// Confirmation Modal State (for pending account delete)
const showConfirmModal = ref(false)
const confirmUserTarget = ref(null)

// Realtime Channel References & Live Sync
let cleanupSync = null
let autoSyncTimer = null

const timeSlots = [
  'Morning (08:00 AM - 12:00 PM)',
  'Afternoon (01:00 PM - 05:00 PM)',
  'Evening (06:00 PM - 10:00 PM)'
]

// Day Names with Accurate Calculated Dates for Current Week
const weekDaysOptions = computed(() => {
  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
  const now = new Date()
  const todayMidnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  const currentDayIndex = now.getDay() // 0 is Sunday
  
  return dayNames.map((name, index) => {
    const d = new Date(now)
    const diff = index - currentDayIndex
    d.setDate(now.getDate() + diff)
    const targetMidnight = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
    const isPast = targetMidnight < todayMidnight
    const isToday = targetMidnight === todayMidnight
    const dateStr = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
    
    let suffix = ''
    if (isToday) {
      suffix = ' • Today'
    } else if (isPast) {
      suffix = ' (Past - Disabled)'
    }

    return {
      key: name,
      fullLabel: `${name} (${dateStr})${suffix}`,
      isPast,
      isToday
    }
  })
})

const isSelectedDayPast = computed(() => {
  const opt = weekDaysOptions.value.find(d => d.key === selectedDayNeeded.value)
  return opt ? opt.isPast : false
})

const showToast = (msg, type = 'info') => {
  uiStore.addToast({
    title: 'Admin Operations',
    message: msg,
    type: type === 'error' ? 'error' : msg.startsWith('✓') ? 'success' : 'info'
  })
}

// 1. FETCH PENDING ACCOUNTS
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

// 2. FETCH ROSTER (FOR AVAILABILITY CHECKER)
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

// 3. FETCH PENDING AVATARS
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

// 4. AVATAR MODERATION
const approveAvatar = async (id, name) => {
  try {
    await supabase.from('profiles').update({ profile_picture_status: 'approved' }).eq('id', id)
    showToast(`Approved ${name}'s avatar.`)
    fetchPendingAvatars()
    fetchRoster()
    if (store.user && store.user.id === id) {
      if (store.profile) {
        store.profile.profile_picture_status = 'approved'
        try {
          localStorage.setItem('smartband_user_profile_cache', JSON.stringify(store.profile))
        } catch (e) {}
      }
    }
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
    if (store.user && store.user.id === id) {
      if (store.profile) {
        store.profile.profile_picture_status = 'declined'
        store.profile.profile_picture = null
        try {
          localStorage.setItem('smartband_user_profile_cache', JSON.stringify(store.profile))
        } catch (e) {}
      }
    }
  } catch (err) {
    showToast('Failed to decline avatar.')
  }
}

// 5. APPROVE UNVERIFIED ACCOUNT
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
    await broadcastSync('account_status_changed', { userId: user.id, status: 'verified', full_name: user.full_name })
  } catch (err) {
    console.error('Approval Error:', err)
    showToast('Failed to approve account.')
  }
}

// 6. PROMPT DECLINE / DELETE UNVERIFIED ACCOUNT
const promptDeleteUser = (user) => {
  confirmUserTarget.value = user
  showConfirmModal.value = true
}

const executeRejectAndDeleteUser = async () => {
  if (!confirmUserTarget.value) return
  const target = confirmUserTarget.value

  try {
    try {
      await supabase.rpc('delete_user_account', { target_user_id: target.id })
    } catch (rpcErr) {
      console.warn('RPC delete user fallback notice:', rpcErr)
    }

    const { error } = await supabase.from('profiles').delete().eq('id', target.id)
    if (error) throw error

    pendingAccounts.value = pendingAccounts.value.filter(u => u.id !== target.id)
    memberRoster.value = memberRoster.value.filter(u => u.id !== target.id)
    showToast(`Removed ${target.full_name}.`)
    await broadcastSync('account_status_changed', { userId: target.id, status: 'rejected', full_name: target.full_name })
  } catch (err) {
    console.error('Delete Error:', err)
    showToast('Failed to delete registration.', 'error')
  } finally {
    showConfirmModal.value = false
    confirmUserTarget.value = null
  }
}

// 7. AVAILABILITY CHECKER
const runAvailabilityCheck = async () => {
  const selectedOpt = weekDaysOptions.value.find(d => d.key === selectedDayNeeded.value)
  if (selectedOpt && selectedOpt.isPast) {
    showToast('Cannot check availability for a past date. Please select today or an upcoming day.')
    return
  }

  try {
    const slotShort = selectedSlotNeeded.value.split(' ')[0]
    const { data: availData, error } = await supabase
      .from('member_availability')
      .select('*')
      .ilike('day_of_week', selectedDayNeeded.value)
      .eq('time_slot', slotShort)

    if (error) console.warn('Availability query notice:', error)

    const freeRecords = availData ? availData.filter(a => a.is_free !== false && a.is_available !== false) : []
    availableUserIds.value = new Set(freeRecords.map(a => a.user_id))

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

// 8. RE-NOTIFICATION DISPATCH WITH BROADCAST SYNC
const isAlertingUnconfirmed = ref(false)

const triggerReNotifications = async () => {
  if (isAlertingUnconfirmed.value) return
  isAlertingUnconfirmed.value = true

  const alertTitle = '🚨 Urgent: Confirm Your Attendance'
  const alertMsg = 'The Band Secretary requests all musicians confirm attendance for upcoming gigs immediately.'
  const senderName = store.profile?.full_name || 'Band Secretary'

  try {
    // 1. Direct real-time WebSocket broadcast to all connected members and remote devices
    try {
      const broadcastPayload = {
        title: alertTitle,
        message: alertMsg,
        sender: senderName,
        senderId: store.user?.id || null
      }
      await broadcastSync('rsvp_reminder', broadcastPayload)
    } catch (wsErr) {
      console.warn('Realtime broadcast error:', wsErr)
    }

    // 2. Create official announcement for activity feed and offline members
    try {
      await supabase
        .from('announcements')
        .insert({
          author_id: store.user?.id || null,
          title: '🚨 Urgent: Attendance Confirmation Required',
          content: 'The Band Secretary requests all unconfirmed musicians and auxiliary members to check upcoming event schedules and confirm if they are attending or not attending immediately.',
          category: 'Urgent Call-to-Action'
        })
    } catch (annErr) {
      console.warn('Announcement creation note:', annErr)
    }

    // 3. Dispatch background Web Push to closed devices (phones/PCs)
    sendPushNotification({
      title: alertTitle,
      message: alertMsg,
      url: '/dashboard',
      senderId: store.user?.id
    })

    showToast('✓ Attendance reminder notifications dispatched to all devices successfully.')
  } catch (err) {
    console.error('Error dispatching reminder alerts:', err)
    showToast('Failed to dispatch some reminder notifications.')
  } finally {
    isAlertingUnconfirmed.value = false
  }
}

// 9. DATA ANALYTICS & MASTER REPORT GENERATION ENGINE
const allEvents = ref([])
const allRsvps = ref([])
const allProfiles = ref([])
const isLoadingAnalytics = ref(false)

const analyticsSearchQuery = ref('')
const analyticsSectionFilter = ref('All')
const analyticsSortBy = ref('flakes_desc') // 'flakes_desc' | 'reliability_asc' | 'reliability_desc' | 'name'

// Report Generator Configuration (Super Admin Only)
const selectedReportType = ref('all_members')
const selectedRoleFilter = ref('member')
const selectedEventTypeFilter = ref('Practice & Rehearsal (Ensayo)')
const selectedSpecificEventId = ref('')

const reportTypeOptions = [
  { id: 'all_members', label: '1. List of All Band Members' },
  { id: 'active_members', label: '2. List of All Active Band Members' },
  { id: 'inactive_members', label: '3. List of All Inactive Band Members' },
  { id: 'members_by_role', label: '4. List of All Band Members Filtered by Roles' },
  { id: 'officers', label: '5. List of Band Leadership & Officers' },
  { id: 'all_schedules', label: '6. List of All Band Schedules & Gigs' },
  { id: 'schedules_by_type', label: '7. List of Schedules Filtered by Types' },
  { id: 'past_events', label: '8. Past Events & Gigs History Report' },
  { id: 'event_attendance', label: '9. Specific Event Roll-Call & Attendance Report' }
]

const eventTypeOptions = [
  'Practice & Rehearsal (Ensayo)',
  'Civic Parade (Parada)',
  'Feast Procession (Prusisyon)',
  'Funeral March (Libing)',
  'Wake & Vigil (Bantay / Lamay)',
  'Band Meeting (Pulong)'
]

const sectionOptions = [
  'All',
  'Clarinet',
  'Saxophone',
  'Trumpet',
  'Trombone',
  'Flute',
  'Horn',
  'Tuba',
  'Percussion'
]

const fetchAnalyticsAndReportsData = async () => {
  isLoadingAnalytics.value = true
  try {
    const PAGE_SIZE = 50
    const [eventsRes, rsvpsRes, profilesRes] = await Promise.all([
      supabase.from('events').select('*').order('event_date', { ascending: false }).limit(PAGE_SIZE),
      supabase.from('event_rsvps').select('*').limit(250),
      supabase.from('profiles').select('*').order('full_name', { ascending: true }).limit(PAGE_SIZE)
    ])

    if (eventsRes.data) {
      allEvents.value = eventsRes.data
      if (!selectedSpecificEventId.value && eventsRes.data.length > 0) {
        selectedSpecificEventId.value = eventsRes.data[0].id
      }
    }
    if (rsvpsRes.data) allRsvps.value = rsvpsRes.data
    if (profilesRes.data) allProfiles.value = profilesRes.data
  } catch (err) {
    console.error('Error loading analytics dataset:', err)
  } finally {
    isLoadingAnalytics.value = false
  }
}

// Reset Analytics & Reports State
const isResettingAnalytics = ref(false)
const showResetAnalyticsModal = ref(false)

const resetAnalyticsFilters = () => {
  analyticsSearchQuery.value = ''
  analyticsSectionFilter.value = 'All'
  analyticsSortBy.value = 'flakes_desc'
  selectedReportType.value = 'all_members'
  selectedRoleFilter.value = 'member'
  selectedEventTypeFilter.value = 'Practice & Rehearsal (Ensayo)'
  if (allEvents.value.length > 0) {
    selectedSpecificEventId.value = allEvents.value[0].id
  } else {
    selectedSpecificEventId.value = ''
  }
  showToast('✓ Reports and analytics filters reset to default.')
}

const executeResetReportsAndAnalytics = async () => {
  if (isResettingAnalytics.value) return
  isResettingAnalytics.value = true

  try {
    let rpcSuccess = false
    // 1. Try atomic PostgreSQL RPC first
    try {
      const { data, error } = await supabase.rpc('reset_analytics_and_attendance')
      if (!error && data?.success) {
        rpcSuccess = true
      } else if (error) {
        console.warn('RPC reset notice, proceeding with direct queries:', error)
      }
    } catch (rpcErr) {
      console.warn('RPC invocation notice:', rpcErr)
    }

    // 2. Direct fallback for table operations if RPC is not installed
    if (!rpcSuccess) {
      const { error: rsvpErr } = await supabase
        .from('event_rsvps')
        .delete()
        .not('id', 'is', null)
      if (rsvpErr) console.warn('RSVP direct delete notice:', rsvpErr)

      const { error: profErr } = await supabase
        .from('profiles')
        .update({ reliability_score: 100 })
        .not('id', 'is', null)
      if (profErr) console.warn('Profiles reliability score update notice:', profErr)
    }

    // 3. Clear local storage caches
    try {
      localStorage.removeItem('smartband_leaderboard_cache')
      const keysToRemove = []
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i)
        if (k && (k.startsWith('smartband_rsvp_') || k.startsWith('smartband_rsvp_excuse_'))) {
          keysToRemove.push(k)
        }
      }
      keysToRemove.forEach(k => localStorage.removeItem(k))
    } catch (lsErr) {
      console.warn('Local storage cache clean notice:', lsErr)
    }

    // 4. Reset in-memory filter states
    resetAnalyticsFilters()

    // 5. Invalidate and re-fetch fresh data
    allRsvps.value = []
    await Promise.all([
      fetchAnalyticsAndReportsData(),
      fetchRoster()
    ])

    // Update current store profile if affected
    if (store.profile) {
      store.profile.reliability_score = 100
      try {
        localStorage.setItem('smartband_user_profile_cache', JSON.stringify(store.profile))
      } catch (e) {}
    }

    // 6. Broadcast Realtime Sync to all other devices & tabs
    await broadcastSync('analytics_reset', { timestamp: Date.now() })
    await broadcastSync('account_status_changed', { type: 'bulk_reliability_reset' })

    showToast('✓ Reports and attendance analytics successfully reset. All reliability scores restored to 100%.')
  } catch (err) {
    console.error('Error resetting reports and analytics:', err)
    showToast('Failed to reset some analytics records.', 'error')
  } finally {
    isResettingAnalytics.value = false
    showResetAnalyticsModal.value = false
  }
}

// MEMBER ATTENDANCE MATRIX & FLAKE DETECTION (Math Calculation)
const memberAnalyticsMatrix = computed(() => {
  const rsvpByMember = new Map()
  allRsvps.value.forEach(r => {
    if (!rsvpByMember.has(r.user_id)) rsvpByMember.set(r.user_id, [])
    rsvpByMember.get(r.user_id).push(r)
  })

  return memberRoster.value.map(m => {
    const userRsvps = rsvpByMember.get(m.id) || []
    
    // Promised: records where member committed to attend
    const promised = userRsvps.filter(r => r.status === 'attending' || r.status === 'present' || r.status === 'absent')
    const promisedCount = promised.length
    
    // Attended: verified present
    const attendedCount = userRsvps.filter(r => r.status === 'present').length
    
    // Flakes / Unexcused No-Shows: committed 'attending' but verified 'absent'
    const flakeCount = userRsvps.filter(r => r.status === 'absent').length
    
    // Follow-Through Rate %: (Attended / Promised) * 100
    const followThroughRate = promisedCount > 0 ? Math.round((attendedCount / promisedCount) * 100) : 100
    
    // Reliability Score calculation
    const calculatedScore = Math.max(0, 100 - (flakeCount * 10))
    const score = m.reliability_score !== undefined && m.reliability_score !== null ? m.reliability_score : calculatedScore

    let riskTier = 'Reliable'
    let riskColor = 'emerald'
    if (flakeCount >= 2 || score < 75) {
      riskTier = 'High No-Show Risk'
      riskColor = 'rose'
    } else if (flakeCount === 1 || score < 90) {
      riskTier = 'Moderate Risk'
      riskColor = 'amber'
    }

    return {
      id: m.id,
      name: m.full_name,
      instrument: m.instrument || 'Clarinet',
      rank: m.rank || 'Junior',
      role: m.role || 'member',
      executive_title: m.executive_title,
      promisedCount,
      attendedCount,
      flakeCount,
      followThroughRate,
      reliabilityScore: score,
      riskTier,
      riskColor
    }
  })
})

const filteredAnalyticsMatrix = computed(() => {
  let list = memberAnalyticsMatrix.value

  if (analyticsSearchQuery.value.trim()) {
    const q = analyticsSearchQuery.value.toLowerCase()
    list = list.filter(m => m.name.toLowerCase().includes(q) || m.instrument.toLowerCase().includes(q))
  }

  if (analyticsSectionFilter.value !== 'All') {
    const sec = analyticsSectionFilter.value.toLowerCase()
    list = list.filter(m => m.instrument.toLowerCase().includes(sec))
  }

  return [...list].sort((a, b) => {
    if (analyticsSortBy.value === 'flakes_desc') {
      return (b.flakeCount - a.flakeCount) || (a.reliabilityScore - b.reliabilityScore)
    }
    if (analyticsSortBy.value === 'reliability_asc') {
      return a.reliabilityScore - b.reliabilityScore
    }
    if (analyticsSortBy.value === 'reliability_desc') {
      return b.reliabilityScore - a.reliabilityScore
    }
    if (analyticsSortBy.value === 'name') {
      return a.name.localeCompare(b.name)
    }
    return 0
  })
})

const analyticsSummary = computed(() => {
  const list = memberAnalyticsMatrix.value
  if (list.length === 0) {
    return { avgReliability: 100, totalFlakes: 0, avgFollowThrough: 100, highRiskCount: 0 }
  }
  const totalFlakes = list.reduce((sum, m) => sum + m.flakeCount, 0)
  const avgReliability = Math.round(list.reduce((sum, m) => sum + m.reliabilityScore, 0) / list.length)
  const avgFollowThrough = Math.round(list.reduce((sum, m) => sum + m.followThroughRate, 0) / list.length)
  const highRiskCount = list.filter(m => m.flakeCount >= 2 || m.reliabilityScore < 75).length
  return { avgReliability, totalFlakes, avgFollowThrough, highRiskCount }
})

// SECTION TURNOUT BREAKDOWN
const sectionStats = computed(() => {
  const list = memberAnalyticsMatrix.value
  const woodwindNames = ['clarinet', 'flute', 'sax', 'piccolo']
  const brassNames = ['trumpet', 'trombone', 'horn', 'tuba', 'baritone', 'euphonium']
  const percussionNames = ['drum', 'cymbals', 'snare', 'bass drum']
  const auxiliaryNames = ['majorette', 'flag', 'guard']

  const getStats = (matchers) => {
    const members = list.filter(m => matchers.some(term => (m.instrument || '').toLowerCase().includes(term)))
    const promised = members.reduce((sum, m) => sum + (m.promisedCount || 0), 0)
    const attended = members.reduce((sum, m) => sum + (m.attendedCount || 0), 0)
    const flakes = members.reduce((sum, m) => sum + (m.flakeCount || 0), 0)
    
    let rate = 0
    let displayRate = 'N/A'
    if (members.length === 0) {
      displayRate = 'N/A'
      rate = 0
    } else if (promised === 0) {
      displayRate = 'N/A (No Gigs)'
      rate = 100
    } else {
      rate = Math.round((attended / promised) * 100)
      displayRate = `${rate}%`
    }

    return { count: members.length, promised, attended, flakes, rate, displayRate }
  }

  return {
    woodwinds: getStats(woodwindNames),
    brass: getStats(brassNames),
    percussion: getStats(percussionNames),
    auxiliary: getStats(auxiliaryNames)
  }
})

// GENERATED PDF REPORT DATA (Matched exactly to user requirements)
const generatedReportData = computed(() => {
  const type = selectedReportType.value
  
  if (type === 'all_members') {
    return {
      title: 'LIST OF ALL BAND MEMBERS',
      subtitle: 'Complete official registry of all registered musicians and accounts',
      columns: ['#', 'Full Name', 'Instrument / Section', 'Rank', 'Appointed Role', 'Verification Status'],
      rows: allProfiles.value.map((m, idx) => [
        idx + 1,
        m.full_name,
        m.instrument || 'Clarinet',
        m.rank || 'Junior',
        m.executive_title ? `Executive (${m.executive_title.replace('_', ' ').toUpperCase()})` : m.role === 'secretary_admin' ? 'Band Secretary' : m.role === 'super_admin' ? 'IT Super Admin' : 'Musician',
        m.is_verified ? 'Active & Verified' : 'Pending Physical Verification'
      ])
    }
  }

  if (type === 'active_members') {
    const active = allProfiles.value.filter(m => m.is_verified)
    return {
      title: 'LIST OF ALL ACTIVE BAND MEMBERS',
      subtitle: 'Official roster of verified musicians currently in active service',
      columns: ['#', 'Full Name', 'Instrument / Section', 'Rank', 'Reliability Score (%)'],
      rows: active.map((m, idx) => [
        idx + 1,
        m.full_name,
        m.instrument || 'Clarinet',
        m.rank || 'Junior',
        `${m.reliability_score || 100}%`
      ])
    }
  }

  if (type === 'inactive_members') {
    const inactive = allProfiles.value.filter(m => !m.is_verified)
    return {
      title: 'LIST OF INACTIVE / PENDING BAND MEMBERS',
      subtitle: 'Unverified registrants pending physical verification and Super Admin approval',
      columns: ['#', 'Full Name', 'Email Contact', 'Instrument', 'Registration Date', 'Status'],
      rows: inactive.map((m, idx) => [
        idx + 1,
        m.full_name,
        m.email || 'N/A',
        m.instrument || 'N/A',
        new Date(m.created_at).toLocaleDateString(),
        'Pending Super Admin Approval'
      ])
    }
  }

  if (type === 'members_by_role') {
    const targetRole = selectedRoleFilter.value
    const filtered = allProfiles.value.filter(m => m.role === targetRole)
    const roleLabels = {
      super_admin: 'IT Super Admin',
      secretary_admin: 'Band Secretary',
      executive: 'Executive Officers',
      member: 'Regular Musicians'
    }
    return {
      title: `LIST OF BAND MEMBERS FILTERED BY ROLE: ${roleLabels[targetRole]?.toUpperCase() || targetRole.toUpperCase()}`,
      subtitle: `Roster members categorized by appointed operational tier`,
      columns: ['#', 'Full Name', 'Instrument', 'Rank', 'Officer Title', 'Status'],
      rows: filtered.map((m, idx) => [
        idx + 1,
        m.full_name,
        m.instrument || 'Clarinet',
        m.rank || 'Junior',
        m.executive_title ? m.executive_title.replace('_', ' ').toUpperCase() : 'None',
        m.is_verified ? 'Active' : 'Pending'
      ])
    }
  }

  if (type === 'officers') {
    const officers = allProfiles.value.filter(m => 
      m.role === 'super_admin' || m.role === 'secretary_admin' || m.role === 'executive'
    )
    return {
      title: 'LIST OF BAND LEADERSHIP & EXECUTIVE OFFICERS',
      subtitle: 'Official roster of appointed municipal band administrators and executives',
      columns: ['#', 'Officer Name', 'Official Appointed Post', 'Instrument', 'Rank', 'Contact Line'],
      rows: officers.map((m, idx) => [
        idx + 1,
        m.full_name,
        m.role === 'super_admin' ? 'IT Super Admin' : m.role === 'secretary_admin' ? 'Band Secretary' : `Band ${m.executive_title ? m.executive_title.replace('_', ' ').toUpperCase() : 'Executive'}`,
        m.instrument || 'Clarinet',
        m.rank || 'Senior',
        m.contact_number || 'Official Record'
      ])
    }
  }

  if (type === 'all_schedules') {
    return {
      title: 'LIST OF ALL BAND SCHEDULES & GIGS',
      subtitle: 'Complete official calendar log of rehearsals, parades, processions, and gigs',
      columns: ['#', 'Event Title', 'Event Category', 'Date & Time', 'Location', 'Turnout Status'],
      rows: allEvents.value.map((e, idx) => [
        idx + 1,
        e.title,
        e.event_type,
        new Date(e.event_date).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' }),
        e.location,
        new Date(e.event_date) < new Date() ? 'Completed' : 'Scheduled'
      ])
    }
  }

  if (type === 'schedules_by_type') {
    const targetType = selectedEventTypeFilter.value
    const filtered = allEvents.value.filter(e => e.event_type === targetType)
    return {
      title: `LIST OF SCHEDULES FILTERED BY TYPE: ${targetType.toUpperCase()}`,
      subtitle: `Master log of events strictly matching category "${targetType}"`,
      columns: ['#', 'Event Title', 'Date & Time', 'Location', 'Status'],
      rows: filtered.map((e, idx) => [
        idx + 1,
        e.title,
        new Date(e.event_date).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' }),
        e.location,
        new Date(e.event_date) < new Date() ? 'Completed' : 'Scheduled'
      ])
    }
  }

  if (type === 'past_events') {
    const past = allEvents.value
      .filter(e => new Date(e.event_date) < new Date())
      .sort((a, b) => new Date(b.event_date) - new Date(a.event_date))

    return {
      title: 'OFFICIAL PAST EVENTS & GIGS HISTORY REPORT',
      subtitle: 'Archived log of completed rehearsals, parades, and municipal services with turnout tallies',
      columns: ['#', 'Event Title', 'Category', 'Date Completed', 'Location', 'Attendance Turnout'],
      rows: past.map((e, idx) => {
        const evRsvps = allRsvps.value.filter(r => r.event_id === e.id)
        const present = evRsvps.filter(r => r.status === 'present').length
        const flakes = evRsvps.filter(r => r.status === 'absent').length
        const turnout = `${present} Present ${flakes > 0 ? `(${flakes} No-Shows)` : ''}`
        return [
          idx + 1,
          e.title,
          e.event_type || 'Gig',
          new Date(e.event_date).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' }),
          e.location || 'Municipal Bandstand',
          turnout
        ]
      })
    }
  }

  if (type === 'event_attendance') {
    const targetEvent = allEvents.value.find(e => e.id === selectedSpecificEventId.value) || allEvents.value[0]
    if (!targetEvent) {
      return {
        title: 'SPECIFIC EVENT ROLL-CALL & ATTENDANCE REPORT',
        subtitle: 'No events found in schedule database',
        columns: ['#', 'Musician Name', 'Section / Instrument', 'Rank', 'Attendance Status', 'Attendance Response'],
        rows: []
      }
    }

    const eventRsvps = allRsvps.value.filter(r => r.event_id === targetEvent.id)
    const verifiedMembers = allProfiles.value.filter(m => m.is_verified)

    const statusWeight = (status) => {
      if (status === 'present') return 1
      if (status === 'excused' || status === 'declined') return 2
      if (status === 'absent') return 3
      return 4
    }

    const memberRows = verifiedMembers.map(m => {
      const rsvp = eventRsvps.find(r => r.user_id === m.id)
      const st = rsvp?.status || 'none'
      let statusLabel = 'Unconfirmed'
      let rsvpNote = 'No Response'

      if (st === 'present') {
        statusLabel = 'Present (Attended)'
        rsvpNote = 'Confirmed & Present'
      } else if (st === 'absent') {
        statusLabel = 'Absent (No-Show)'
        rsvpNote = 'Failed Call-Time'
      } else if (st === 'excused') {
        statusLabel = 'Excused / Unavailable'
        rsvpNote = 'Authorized Absence'
      } else if (st === 'declined') {
        statusLabel = 'Unavailable (Declined)'
        rsvpNote = 'Declined Invitation'
      } else if (st === 'attending') {
        statusLabel = 'Committed (Pending)'
        rsvpNote = 'Will Attend'
      }

      return {
        member: m,
        weight: statusWeight(st),
        statusLabel,
        rsvpNote
      }
    }).sort((a, b) => {
      if (a.weight !== b.weight) return a.weight - b.weight
      return (a.member.full_name || '').localeCompare(b.member.full_name || '')
    })

    const presentCount = memberRows.filter(r => r.statusLabel.startsWith('Present')).length
    const absentCount = memberRows.filter(r => r.statusLabel.startsWith('Absent')).length
    const excusedCount = memberRows.filter(r => r.statusLabel.includes('Excused') || r.statusLabel.includes('Unavailable')).length

    return {
      title: `EVENT ROLL-CALL & ATTENDANCE: ${targetEvent.title.toUpperCase()}`,
      subtitle: `${targetEvent.event_type} • ${new Date(targetEvent.event_date).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })} • ${targetEvent.location || 'Municipal'} [Present: ${presentCount} | Absent: ${absentCount} | Excused: ${excusedCount}]`,
      columns: ['#', 'Musician Name', 'Section / Instrument', 'Rank', 'Attendance Status', 'Attendance Response'],
      rows: memberRows.map((item, idx) => [
        idx + 1,
        item.member.full_name,
        item.member.instrument || 'Clarinet',
        item.member.rank || 'Junior',
        item.statusLabel,
        item.rsvpNote
      ])
    }
  }

  return { title: 'OFFICIAL REPORT', subtitle: '', columns: [], rows: [] }
})

const isGeneratingPdf = ref(false)

// Clear, human-readable file names for each administrative report
const getReportFilename = () => {
  const type = selectedReportType.value
  const dateStamp = new Date().toISOString().split('T')[0]
  
  switch (type) {
    case 'all_members':
      return `Penaranda_Band_All_Members_${dateStamp}.pdf`
    case 'active_members':
      return `Penaranda_Band_Active_Members_${dateStamp}.pdf`
    case 'inactive_members':
      return `Penaranda_Band_Pending_Members_${dateStamp}.pdf`
    case 'members_by_role': {
      const roleMap = {
        member: 'Musicians',
        secretary_admin: 'Secretary',
        executive: 'Executives',
        super_admin: 'SuperAdmin'
      }
      const roleName = roleMap[selectedRoleFilter.value] || selectedRoleFilter.value
      return `Penaranda_Band_Members_Role_${roleName}_${dateStamp}.pdf`
    }
    case 'officers':
      return `Penaranda_Band_Officers_Leadership_${dateStamp}.pdf`
    case 'all_schedules':
      return `Penaranda_Band_All_Schedules_Gigs_${dateStamp}.pdf`
    case 'schedules_by_type': {
      const typeClean = (selectedEventTypeFilter.value || 'Gigs')
        .split('(')[0]
        .trim()
        .replace(/[^a-zA-Z0-9]/g, '_')
        .replace(/^_+|_+$/g, '')
      return `Penaranda_Band_Schedules_${typeClean}_${dateStamp}.pdf`
    }
    case 'past_events':
      return `Penaranda_Band_Past_Events_History_${dateStamp}.pdf`
    case 'event_attendance': {
      const targetEvent = allEvents.value.find(e => e.id === selectedSpecificEventId.value) || allEvents.value[0]
      const evName = (targetEvent?.title || 'Event').replace(/[^a-zA-Z0-9]/g, '_').slice(0, 25)
      return `Penaranda_Band_Attendance_${evName}_${dateStamp}.pdf`
    }
    default:
      return `Penaranda_Band_Report_${dateStamp}.pdf`
  }
}

// Direct PDF File Download using jsPDF & autoTable
const downloadPdfReport = async () => {
  isGeneratingPdf.value = true
  try {
    const [jsPDFModule, autoTableModule] = await Promise.all([
      import('jspdf'),
      import('jspdf-autotable')
    ])
    const jsPDF = jsPDFModule.default || jsPDFModule.jsPDF || jsPDFModule
    const autoTable = autoTableModule.default || autoTableModule

    const doc = new jsPDF({
      orientation: 'portrait',
      unit: 'pt',
      format: 'a4'
    })

    const pageWidth = doc.internal.pageSize.getWidth()
    const pageHeight = doc.internal.pageSize.getHeight()

    // 1. Header with Peñaranda Band 1870 Crest Logo
    const logoBase64 = await getBandLogoBase64()
    if (logoBase64) {
      try {
        doc.addImage(logoBase64, 'JPEG', 40, 26, 42, 48)
      } catch (e) {
        console.warn('Logo embed error in PDF:', e)
      }
    }

    const headerLeft = logoBase64 ? 94 : 40
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(14)
    doc.setTextColor(15, 23, 42)
    doc.text('PEÑARANDA MARCHING BAND 1870', headerLeft, 42)

    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8.5)
    doc.setTextColor(100, 116, 139)
    doc.text('Peñaranda, Nueva Ecija • Established 1870 • Municipal Music Unit', headerLeft, 55)
    doc.text('Official Administrative Document & Music Operations System', headerLeft, 67)

    // Divider Line
    doc.setDrawColor(203, 213, 225)
    doc.setLineWidth(1)
    doc.line(40, 82, pageWidth - 40, 82)

    // 2. Document Title & Subtitle
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(11)
    doc.setTextColor(15, 23, 42)
    doc.text(generatedReportData.value.title, pageWidth / 2, 98, { align: 'center' })

    if (generatedReportData.value.subtitle) {
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(8)
      doc.setTextColor(100, 116, 139)
      doc.text(generatedReportData.value.subtitle, pageWidth / 2, 110, { align: 'center' })
    }

    // 3. Metadata Row (Minimal clean box)
    const metaY = 124
    doc.setFillColor(250, 250, 250)
    doc.setDrawColor(203, 213, 225)
    doc.setLineWidth(0.5)
    doc.roundedRect(40, metaY - 10, pageWidth - 80, 20, 3, 3, 'FD')

    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8)
    doc.setTextColor(51, 65, 85)
    doc.text(`Date: ${new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}`, 48, metaY + 3)
    doc.text(`Doc Ref: PMB1870-REP-${new Date().getFullYear()}-${generatedReportData.value.rows.length}R`, pageWidth / 2, metaY + 3, { align: 'center' })
    doc.text(`Total Records: ${generatedReportData.value.rows.length}`, pageWidth - 48, metaY + 3, { align: 'right' })

    // 4. Clean Minimal Data Table (Pure white, no alternating gray)
    autoTable(doc, {
      startY: 142,
      head: [generatedReportData.value.columns],
      body: generatedReportData.value.rows.length > 0 
        ? generatedReportData.value.rows 
        : [['-', 'No records found in database query', ...Array(Math.max(0, generatedReportData.value.columns.length - 2)).fill('')]],
      theme: 'plain',
      headStyles: {
        fillColor: [248, 250, 252],
        textColor: [15, 23, 42],
        fontStyle: 'bold',
        fontSize: 8.5,
        lineColor: [203, 213, 225],
        lineWidth: 0.75,
        halign: 'left'
      },
      styles: {
        font: 'helvetica',
        fontSize: 8,
        textColor: [30, 41, 59],
        fillColor: [255, 255, 255], // Pure white rows, NOT alternating gray
        lineColor: [226, 232, 240], // Light hairline border
        lineWidth: 0.5,
        cellPadding: 5.5
      },
      alternateRowStyles: {
        fillColor: [255, 255, 255] // Pure white
      },
      columnStyles: {
        0: { halign: 'center', cellWidth: 26 }
      },
      margin: { left: 40, right: 40 },
      didDrawPage: (data) => {
        doc.setFont('helvetica', 'italic')
        doc.setFontSize(7.5)
        doc.setTextColor(148, 163, 184)
        doc.text(
          `Peñaranda Marching Band 1870 — Official Document — Page ${data.pageNumber}`,
          pageWidth / 2,
          pageHeight - 18,
          { align: 'center' }
        )
      }
    })

    // 5. Signatories Block (placed on the final page)
    const finalY = doc.lastAutoTable.finalY + 30
    if (finalY < pageHeight - 65) {
      doc.setDrawColor(51, 65, 85)
      doc.setLineWidth(0.75)

      const leftX = 130
      const rightX = pageWidth - 130

      doc.line(leftX - 50, finalY, leftX + 50, finalY)
      doc.setFont('helvetica', 'bold')
      doc.setFontSize(8.5)
      doc.setTextColor(15, 23, 42)
      doc.text(store.profile?.full_name || 'IT Super Admin', leftX, finalY + 11, { align: 'center' })
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(7.5)
      doc.setTextColor(100, 116, 139)
      doc.text('Prepared by (IT Super Admin)', leftX, finalY + 21, { align: 'center' })

      doc.line(rightX - 50, finalY, rightX + 50, finalY)
      doc.setFont('helvetica', 'bold')
      doc.setFontSize(8.5)
      doc.setTextColor(15, 23, 42)
      doc.text('Executive Board / Conductor', rightX, finalY + 11, { align: 'center' })
      doc.setFont('helvetica', 'normal')
      doc.setFontSize(7.5)
      doc.setTextColor(100, 116, 139)
      doc.text('Approved by (Peñaranda Marching Band 1870)', rightX, finalY + 21, { align: 'center' })
    }

    // 6. Direct File Download Trigger with guaranteed filename & .pdf extension
    const filename = getReportFilename()
    const pdfBlob = new Blob([doc.output('blob')], { type: 'application/pdf' })
    const blobUrl = URL.createObjectURL(pdfBlob)

    const downloadLink = document.createElement('a')
    downloadLink.href = blobUrl
    downloadLink.download = filename
    downloadLink.target = '_self'
    downloadLink.style.display = 'none'

    // Must be added to document body for Chromium/Edge/Firefox to respect the download attribute
    document.body.appendChild(downloadLink)
    downloadLink.click()

    setTimeout(() => {
      if (document.body.contains(downloadLink)) {
        document.body.removeChild(downloadLink)
      }
      URL.revokeObjectURL(blobUrl)
    }, 2000)

    showToast(`✓ Downloaded ${filename}`)
  } catch (err) {
    console.error('Error downloading PDF:', err)
    showToast('Failed to generate PDF download.')
  } finally {
    isGeneratingPdf.value = false
  }
}

const printReport = () => {
  window.print()
}

const refreshAllAdminData = async () => {
  await Promise.allSettled([
    fetchPendingAccounts(),
    fetchPendingAvatars(),
    fetchRoster(),
    fetchAnalyticsAndReportsData()
  ])
}

onMounted(async () => {
  await store.fetchProfile()
  if (!['super_admin', 'secretary_admin', 'executive'].includes(store.currentRole)) {
    uiStore.addToast({
      title: 'Restricted Access',
      message: 'You do not have administrative permissions to view this hub.',
      type: 'warning'
    })
    router.push('/dashboard')
    return
  }

  if (store.isExecutive) {
    activeTab.value = 'reports'
  }
  refreshAllAdminData()

  // 1. Centralized Master Realtime Sync (WebSockets + Cross-Tab)
  cleanupSync = initRealtimeSync((event, payload) => {
    refreshAllAdminData()
    if (event === 'new_registration') {
      showToast(`🔔 New Member Registration: ${payload?.full_name || 'A musician'} applied for verification!`)
    }
  })

  // 2. Window focus listener (re-fetch as soon as admin switches back to tab)
  window.addEventListener('focus', refreshAllAdminData)

  // 3. Mobile-optimized auto-poll fallback (pauses in background to save battery/CPU)
  autoSyncTimer = setInterval(() => {
    if (typeof document !== 'undefined' && !document.hidden) {
      refreshAllAdminData()
    }
  }, 12000)
})

onUnmounted(() => {
  if (cleanupSync) {
    cleanupSync()
  }
  if (autoSyncTimer) {
    clearInterval(autoSyncTimer)
  }
  window.removeEventListener('focus', refreshAllAdminData)
})
</script>

<template>
  <div class="space-y-6 max-w-[1200px] mx-auto relative">
    
    <!-- Header -->
    <header class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pt-1 border-b border-slate-200/80 dark:border-neutral-800 pb-4">
      <div class="flex items-center space-x-3">
        <div class="p-2.5 rounded-full bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-300 flex-shrink-0 border border-slate-200 dark:border-neutral-700">
          <Shield class="w-5 h-5" />
        </div>
        <div class="min-w-0">
          <p class="text-xs font-medium text-slate-500 dark:text-neutral-400">
            {{ store.isSuperAdmin ? 'IT Administration' : 'Band Operations' }}
          </p>
          <h1 class="text-2xl font-bold text-slate-900 dark:text-neutral-100 leading-tight truncate">
            Admin Management
          </h1>
        </div>
      </div>

      <!-- Tab Switcher: Operations vs Reports (Segmented Pill Switcher) -->
      <div class="flex rounded-full bg-slate-100 dark:bg-[#2d2f31] p-1 text-xs font-medium border border-slate-200/80 dark:border-[#2d3035] w-full sm:w-auto gap-1 self-start sm:self-auto">
        <button 
          type="button" 
          @click="activeTab = 'operations'"
          class="flex-1 sm:flex-none flex items-center justify-center space-x-2 px-5 py-2.5 rounded-full transition-all cursor-pointer min-h-[44px]"
          :class="activeTab === 'operations' 
            ? 'bg-white dark:bg-[#1e1f20] text-slate-900 dark:text-white shadow-xs font-semibold' 
            : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
        >
          <Activity class="w-4 h-4" />
          <span>Operations Hub</span>
        </button>

        <button 
          type="button" 
          @click="activeTab = 'reports'"
          class="flex-1 sm:flex-none flex items-center justify-center space-x-2 px-5 py-2.5 rounded-full transition-all cursor-pointer min-h-[44px]"
          :class="activeTab === 'reports' 
            ? 'bg-white dark:bg-[#1e1f20] text-slate-900 dark:text-white shadow-xs font-semibold' 
            : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
        >
          <BarChart3 class="w-4 h-4" />
          <span>Reports & Analytics</span>
        </button>
      </div>
    </header>

    <!-- TAB 1: OPERATIONS HUB -->
    <div v-if="activeTab === 'operations'" class="space-y-6">

      <!-- 1. ACCURATE DATE-SYNCED MEMBER AVAILABILITY CHECKER -->
      <section v-if="store.isSecretaryAdmin || store.isSuperAdmin" class="space-y-4">
        <div class="bg-white dark:bg-[#1e1f20] rounded-2xl p-5 sm:p-6 shadow-xs border border-slate-200/80 dark:border-[#2d3035] space-y-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-2">
              <Calendar class="w-4 h-4 text-slate-500 dark:text-neutral-400" />
              <h2 class="font-bold text-base text-slate-900 dark:text-neutral-100">Check Member Availability</h2>
            </div>
            <span class="text-[11px] font-medium bg-slate-100 dark:bg-[#2d2f31] text-slate-600 dark:text-neutral-300 border border-slate-200 dark:border-[#2d3035] px-3 py-1 rounded-full">
              Operations Tool
            </span>
          </div>

          <p class="text-xs text-slate-500 dark:text-neutral-400 font-normal">
            Cross-reference available musicians for upcoming gigs and rehearsals by day, time slot, and section.
          </p>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 text-xs">
            <div>
              <label for="day-select" class="block text-[11px] font-medium text-slate-500 dark:text-neutral-400 mb-1.5">Target Day & Date</label>
              <select 
                id="day-select" 
                v-model="selectedDayNeeded" 
                class="w-full bg-slate-50 dark:bg-[#2d2f31] text-slate-900 dark:text-white rounded-xl px-3.5 py-3 border border-slate-200 dark:border-[#2d3035] font-medium min-h-[48px] cursor-pointer focus:outline-none focus:border-slate-400"
              >
                <option 
                  v-for="d in weekDaysOptions" 
                  :key="d.key" 
                  :value="d.key"
                  :disabled="d.isPast"
                  :class="d.isPast ? 'text-slate-400 dark:text-neutral-500 bg-slate-100 dark:bg-neutral-800/80 italic' : 'text-slate-900 dark:text-white font-medium'"
                >
                  {{ d.fullLabel }}
                </option>
              </select>
            </div>
            <div>
              <label for="slot-select" class="block text-[11px] font-medium text-slate-500 dark:text-neutral-400 mb-1.5">Time Slot</label>
              <select id="slot-select" v-model="selectedSlotNeeded" class="w-full bg-slate-50 dark:bg-[#2d2f31] text-slate-900 dark:text-white rounded-xl px-3.5 py-3 border border-slate-200 dark:border-[#2d3035] font-medium min-h-[48px] focus:outline-none focus:border-slate-400 cursor-pointer">
                <option v-for="s in timeSlots" :key="s" :value="s">{{ s }}</option>
              </select>
            </div>
            <div>
              <label for="inst-select" class="block text-[11px] font-medium text-slate-500 dark:text-neutral-400 mb-1.5">Instrument Section</label>
              <select id="inst-select" v-model="selectedInstrumentNeeded" class="w-full bg-slate-50 dark:bg-[#2d2f31] text-slate-900 dark:text-white rounded-xl px-3.5 py-3 border border-slate-200 dark:border-[#2d3035] font-medium min-h-[48px] focus:outline-none focus:border-slate-400 cursor-pointer">
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

          <p v-if="isSelectedDayPast" class="text-[11px] text-amber-800 dark:text-amber-400 font-medium flex items-center">
            <AlertTriangle class="w-3.5 h-3.5 mr-1.5 shrink-0 inline" /> Selected day has already passed and cannot be checked. Please choose today or an upcoming day.
          </p>

          <button 
            @click="runAvailabilityCheck" 
            type="button" 
            :disabled="isSelectedDayPast"
            class="w-full py-2.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-neutral-100 disabled:opacity-50 disabled:cursor-not-allowed text-white dark:text-slate-900 font-medium text-xs rounded-full flex items-center justify-center transition-colors shadow-xs active:scale-95 cursor-pointer min-h-[48px]"
          >
            <Cpu class="w-4 h-4 mr-2" /> Check Available Musicians
          </button>
        </div>

        <!-- MATCHED AVAILABILITY DISPLAY -->
        <div v-if="isDispatchGenerated" class="bg-white dark:bg-[#1e1f20] rounded-2xl p-5 shadow-xs border border-slate-200 dark:border-[#2d3035] space-y-3">
          <div class="flex items-center justify-between">
            <h3 class="font-bold text-sm text-slate-900 dark:text-neutral-100">Roster for {{ selectedDayNeeded }} ({{ selectedSlotNeeded.split(' ')[0] }})</h3>
            <span class="text-xs font-medium text-slate-700 dark:text-neutral-200 bg-slate-100 dark:bg-[#2d2f31] border border-slate-200 dark:border-[#2d3035] px-3 py-1 rounded-full">
              {{ availableUserIds.size }} Available
            </span>
          </div>

          <div class="space-y-1.5 max-h-[300px] overflow-y-auto pr-1 divide-y divide-slate-100 dark:divide-[#2d3035]">
            <div v-for="m in matchedDispatchRoster" :key="m.id" class="py-2.5 flex items-center justify-between text-xs">
              <div class="flex items-center space-x-2">
                <span class="font-medium text-slate-900 dark:text-neutral-100">{{ m.full_name }} ({{ m.instrument }})</span>
                <span v-if="availableUserIds.has(m.id)" class="text-[10px] font-medium bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-400 border border-emerald-200 dark:border-emerald-900/40 px-2 py-0.5 rounded-full">
                  Free
                </span>
                <span v-else class="text-[10px] font-normal text-slate-600 dark:text-neutral-400">Unavailable</span>
              </div>
              <span class="text-slate-500 dark:text-neutral-400 font-medium">{{ m.rank }}</span>
            </div>
          </div>
        </div>

        <!-- 2. ATTENDANCE REMINDERS -->
        <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-5 sm:p-6 shadow-xs border border-slate-200/80 dark:border-[#2d3442] flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div>
            <h3 class="font-bold text-sm text-slate-900 dark:text-neutral-100">Attendance Reminders</h3>
            <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">Send a notification reminder to musicians who have unconfirmed attendance status.</p>
          </div>
          <button 
            @click="triggerReNotifications" 
            :disabled="isAlertingUnconfirmed" 
            type="button" 
            class="py-2 px-5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-neutral-100 disabled:opacity-50 text-white dark:text-slate-900 font-medium text-xs rounded-full flex items-center justify-center shadow-xs active:scale-95 cursor-pointer min-h-[48px] shrink-0 transition-colors"
          >
            <Loader2 v-if="isAlertingUnconfirmed" class="w-4 h-4 mr-2 animate-spin" />
            <Send v-else class="w-4 h-4 mr-2" />
            {{ isAlertingUnconfirmed ? 'Dispatching...' : 'Alert Unconfirmed' }}
          </button>
        </div>
      </section>

      <!-- 3. PENDING MASTER LIST APPROVALS QUEUE (IT Super Admin) -->
      <section v-if="store.isSuperAdmin" class="space-y-3" aria-label="Pending Approvals Section">
        <div class="flex items-center justify-between px-1">
          <div class="flex items-center space-x-2">
            <ShieldAlert class="w-4 h-4 text-amber-500" />
            <h2 class="text-xs font-semibold text-slate-600 dark:text-neutral-300 uppercase tracking-wider">
              Pending Registrations ({{ pendingAccounts.length }})
            </h2>
          </div>
          <span v-if="pendingAccounts.length > 3" class="text-[10px] font-normal text-slate-600 dark:text-neutral-400">
            Scroll for more
          </span>
        </div>

        <div :class="pendingAccounts.length > 3 ? 'max-h-[400px] overflow-y-auto pr-1 space-y-3' : 'space-y-3'">
          <div 
            v-for="user in pendingAccounts" 
            :key="user.id" 
            class="bg-white dark:bg-[#1e1f20] rounded-2xl p-5 shadow-xs border border-slate-200/80 dark:border-[#2d3035] space-y-3"
          >
            <div class="flex justify-between items-start">
              <div>
                <h3 class="font-bold text-sm text-slate-900 dark:text-neutral-100 leading-tight">{{ user.full_name }}</h3>
                <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">{{ user.email }} • {{ user.contact_number }}</p>
              </div>
              <span class="text-[10px] font-medium bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-400 border border-amber-200 dark:border-amber-900/40 px-2.5 py-0.5 rounded-full">
                UNVERIFIED
              </span>
            </div>

            <div class="grid grid-cols-2 gap-2 text-xs bg-slate-50 dark:bg-[#18191a] p-3 rounded-2xl text-slate-600 dark:text-neutral-300 border border-slate-100 dark:border-[#2d3035]">
              <div><span class="text-slate-600 dark:text-neutral-400">Section:</span> {{ user.instrument || 'None' }}</div>
              <div><span class="text-slate-600 dark:text-neutral-400">Sex:</span> {{ user.sex || 'Unknown' }}</div>
            </div>

            <div class="flex space-x-2 pt-1">
              <button 
                @click="approveUser(user)" 
                type="button" 
                class="flex-1 py-2 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-neutral-100 active:scale-95 text-white dark:text-slate-900 font-medium text-xs rounded-full flex items-center justify-center transition-colors shadow-xs cursor-pointer min-h-[44px]"
              >
                <UserCheck class="w-4 h-4 mr-1.5" /> Approve & Verify
              </button>
              <button 
                @click="promptDeleteUser(user)" 
                type="button" 
                class="py-2 px-4 bg-white dark:bg-[#1e1f20] hover:bg-rose-50 dark:hover:bg-rose-950/30 text-rose-600 dark:text-rose-400 font-medium text-xs rounded-full flex items-center justify-center transition-colors border border-slate-200 dark:border-[#2d3035] cursor-pointer min-h-[44px]"
              >
                <Trash2 class="w-4 h-4 mr-1.5" /> Decline
              </button>
            </div>
          </div>

          <div v-if="pendingAccounts.length === 0" class="text-center p-8 bg-white dark:bg-[#1e1f20] rounded-2xl border border-slate-200/80 dark:border-[#2d3035] space-y-3">
            <CheckCircle2 class="w-6 h-6 text-slate-400 mx-auto" />
            <p class="text-xs font-medium text-slate-500 dark:text-neutral-400">No pending accounts in queue.</p>
            <button 
              @click="fetchPendingAccounts" 
              type="button" 
              class="m3-btn-tonal text-xs min-h-[40px] px-4 inline-flex items-center"
            >
              <RotateCcw class="w-3.5 h-3.5 mr-1.5" /> Check for New Registrations
            </button>
          </div>
        </div>
      </section>

      <!-- 4. PENDING AVATARS APPROVAL QUEUE -->
      <section v-if="pendingAvatars.length > 0" class="space-y-3" aria-label="Avatar Moderation Queue">
        <div class="flex items-center justify-between px-1">
          <div class="flex items-center space-x-2">
            <AlertCircle class="w-4 h-4 text-amber-500" />
            <h2 class="text-xs font-semibold text-slate-600 dark:text-neutral-300 uppercase tracking-wider">
              Pending Avatar Approvals ({{ pendingAvatars.length }})
            </h2>
          </div>
          <span v-if="pendingAvatars.length > 3" class="text-[10px] font-normal text-slate-400 dark:text-neutral-500">
            Scroll for more
          </span>
        </div>

        <div :class="pendingAvatars.length > 3 ? 'max-h-[380px] overflow-y-auto pr-1' : ''">
          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
            <div 
              v-for="user in pendingAvatars" 
              :key="user.id"
              class="bg-white dark:bg-[#202124] rounded-2xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 flex flex-col items-center text-center space-y-2.5"
            >
              <img :src="user.profile_picture" alt="Avatar Review" width="56" height="56" loading="lazy" class="w-14 h-14 rounded-full object-cover border border-slate-200 dark:border-neutral-700 shadow-xs" />
              <p class="text-xs font-medium text-slate-900 dark:text-neutral-100 line-clamp-1 w-full">{{ user.full_name }}</p>
              <div class="flex space-x-1.5 w-full">
                <button @click="approveAvatar(user.id, user.full_name)" class="flex-1 py-1.5 bg-slate-900 text-white dark:bg-white dark:text-slate-900 font-medium hover:bg-slate-800 rounded-full cursor-pointer text-[10px] transition-colors">Approve</button>
                <button @click="declineAvatar(user.id, user.full_name)" class="flex-1 py-1.5 bg-slate-100 text-rose-600 dark:bg-[#2d2f31] dark:text-rose-400 font-medium border border-slate-200 dark:border-neutral-700 hover:bg-rose-50 rounded-full cursor-pointer text-[10px] transition-colors">Decline</button>
              </div>
            </div>
          </div>
        </div>
      </section>

    </div>

    <!-- TAB 2: REPORTS & ANALYTICS -->
    <div v-else-if="activeTab === 'reports'" class="space-y-6">
      
      <!-- 1. EXECUTIVE ATTENDANCE & FLAKE ANALYTICS DASHBOARD -->
      <section class="space-y-5 no-print">
        <!-- Section Header -->
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 border-b border-slate-200/80 dark:border-[#2d3442] pb-3">
          <div>
            <div class="flex items-center space-x-2">
              <BarChart3 class="w-4 h-4 text-amber-500" />
              <h2 class="text-base font-bold text-slate-900 dark:text-neutral-100">Attendance &amp; Reliability Analytics</h2>
            </div>
            <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">
              Live follow-through metrics, section turnout rates, and verified attendance standings.
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2 self-start sm:self-auto">
            <button
              v-if="store.isSuperAdmin || store.isSecretaryAdmin"
              @click="showResetAnalyticsModal = true"
              type="button"
              class="px-4 py-2 bg-rose-50 hover:bg-rose-100 dark:bg-rose-950/30 dark:hover:bg-rose-950/50 text-rose-700 dark:text-rose-400 border border-rose-200 dark:border-rose-900/40 rounded-full text-xs font-semibold flex items-center space-x-1.5 transition-colors cursor-pointer min-h-[44px]"
              title="Reset all attendance logs, roll-call records, and restore reliability scores to 100%"
            >
              <RotateCcw class="w-3.5 h-3.5 text-rose-600 dark:text-rose-400" />
              <span>Reset Analytics Data</span>
            </button>
            <span class="inline-flex items-center space-x-1.5 px-3 py-2 rounded-full bg-slate-100 dark:bg-[#242933] text-slate-700 dark:text-neutral-300 border border-slate-200 dark:border-[#2d3442] text-xs font-medium min-h-[44px]">
              <Sparkles class="w-3.5 h-3.5 text-amber-500" />
              <span>Executive Insights</span>
            </span>
          </div>
        </div>

        <!-- 4 KPI Summary Cards -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3.5">
          <!-- KPI 1: Band Reliability Score -->
          <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-4 sm:p-5 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-2">
            <div class="flex items-center justify-between text-xs font-medium text-slate-500 dark:text-neutral-400">
              <span>Avg Reliability</span>
              <Award class="w-4 h-4 text-slate-500 dark:text-neutral-400" />
            </div>
            <div class="flex items-baseline space-x-1.5">
              <span class="text-2xl sm:text-3xl font-bold text-slate-900 dark:text-neutral-100">
                {{ analyticsSummary.avgReliability }}%
              </span>
              <span class="text-[10px] font-normal text-slate-600 dark:text-neutral-400">Roster Avg</span>
            </div>
            <!-- Progress Bar -->
            <div class="w-full bg-slate-100 dark:bg-[#242933] h-1.5 rounded-full overflow-hidden">
              <div 
                class="h-full rounded-full transition-all duration-500 bg-slate-900 dark:bg-white" 
                :style="{ width: `${analyticsSummary.avgReliability}%` }"
              ></div>
            </div>
          </div>

          <!-- KPI 2: Total Unexcused No-Shows -->
          <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-4 sm:p-5 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-2">
            <div class="flex items-center justify-between text-xs font-medium text-slate-500 dark:text-neutral-400">
              <span>Unexcused No-Shows</span>
              <AlertTriangle class="w-4 h-4 text-rose-600 dark:text-rose-400" />
            </div>
            <div class="flex items-baseline space-x-1.5">
              <span class="text-2xl sm:text-3xl font-bold text-rose-600 dark:text-rose-400">
                {{ analyticsSummary.totalFlakes }}
              </span>
              <span class="text-[10px] font-normal text-slate-600 dark:text-neutral-400">Total Flagged</span>
            </div>
            <p class="text-[11px] text-slate-500 dark:text-neutral-400">
              -10% penalty per unexcused no-show
            </p>
          </div>

          <!-- KPI 3: Follow-Through Rate -->
          <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-4 sm:p-5 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-2">
            <div class="flex items-center justify-between text-xs font-medium text-slate-500 dark:text-neutral-400">
              <span>Commitment Rate</span>
              <TrendingUp class="w-4 h-4 text-slate-500 dark:text-neutral-400" />
            </div>
            <div class="flex items-baseline space-x-1.5">
              <span class="text-2xl sm:text-3xl font-bold text-slate-900 dark:text-neutral-100">
                {{ analyticsSummary.avgFollowThrough }}%
              </span>
              <span class="text-[10px] font-normal text-slate-600 dark:text-neutral-400">Turnout</span>
            </div>
            <div class="w-full bg-slate-100 dark:bg-[#242933] h-1.5 rounded-full overflow-hidden">
              <div 
                class="bg-slate-900 dark:bg-white h-full rounded-full transition-all duration-500" 
                :style="{ width: `${analyticsSummary.avgFollowThrough}%` }"
              ></div>
            </div>
          </div>

          <!-- KPI 4: High No-Show Risk Members -->
          <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-4 sm:p-5 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-2">
            <div class="flex items-center justify-between text-xs font-medium text-slate-500 dark:text-neutral-400">
              <span>Attendance Risk</span>
              <ShieldAlert class="w-4 h-4 text-amber-500" />
            </div>
            <div class="flex items-baseline space-x-1.5">
              <span class="text-2xl sm:text-3xl font-bold text-amber-800 dark:text-amber-400">
                {{ analyticsSummary.highRiskCount }}
              </span>
              <span class="text-[10px] font-normal text-slate-600 dark:text-neutral-400">Flagged</span>
            </div>
            <p class="text-[11px] text-slate-500 dark:text-neutral-400">
              Members with multiple misses
            </p>
          </div>
        </div>

        <!-- Section Turnout Breakdown Cards -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3.5">
          <!-- Woodwinds -->
          <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-4 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-semibold text-slate-900 dark:text-neutral-100 uppercase tracking-wider">Woodwinds</span>
              <span class="text-[10px] font-medium bg-slate-100 dark:bg-[#242933] text-slate-700 dark:text-neutral-300 border border-slate-200 dark:border-[#2d3442] px-2 py-0.5 rounded-full">
                {{ sectionStats.woodwinds.count }} Members
              </span>
            </div>
            <div class="flex items-baseline justify-between text-xs">
              <span class="text-slate-500 dark:text-neutral-400">Turnout Rate</span>
              <span class="font-bold text-slate-900 dark:text-neutral-100">{{ sectionStats.woodwinds.displayRate }}</span>
            </div>
            <div class="w-full bg-slate-100 dark:bg-[#242933] h-1.5 rounded-full overflow-hidden">
              <div class="bg-slate-900 dark:bg-white h-full rounded-full" :style="{ width: `${sectionStats.woodwinds.rate || 0}%` }"></div>
            </div>
            <div class="flex items-center justify-between text-[11px] text-slate-600 dark:text-neutral-400">
              <span>Attended: {{ sectionStats.woodwinds.attended }} / {{ sectionStats.woodwinds.promised }}</span>
              <span :class="sectionStats.woodwinds.flakes > 0 ? 'text-rose-600 dark:text-rose-400 font-medium' : 'text-emerald-700 dark:text-emerald-400'">
                {{ sectionStats.woodwinds.flakes }} No-Shows
              </span>
            </div>
          </div>

          <!-- Brass -->
          <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-4 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-semibold text-slate-900 dark:text-neutral-100 uppercase tracking-wider">Brass</span>
              <span class="text-[10px] font-medium bg-slate-100 dark:bg-[#242933] text-slate-700 dark:text-neutral-300 border border-slate-200 dark:border-[#2d3442] px-2 py-0.5 rounded-full">
                {{ sectionStats.brass.count }} Members
              </span>
            </div>
            <div class="flex items-baseline justify-between text-xs">
              <span class="text-slate-500 dark:text-neutral-400">Turnout Rate</span>
              <span class="font-bold text-slate-900 dark:text-neutral-100">{{ sectionStats.brass.displayRate }}</span>
            </div>
            <div class="w-full bg-slate-100 dark:bg-[#242933] h-1.5 rounded-full overflow-hidden">
              <div class="bg-slate-900 dark:bg-white h-full rounded-full" :style="{ width: `${sectionStats.brass.rate || 0}%` }"></div>
            </div>
            <div class="flex items-center justify-between text-[11px] text-slate-600 dark:text-neutral-400">
              <span>Attended: {{ sectionStats.brass.attended }} / {{ sectionStats.brass.promised }}</span>
              <span :class="sectionStats.brass.flakes > 0 ? 'text-rose-600 dark:text-rose-400 font-medium' : 'text-emerald-700 dark:text-emerald-400'">
                {{ sectionStats.brass.flakes }} No-Shows
              </span>
            </div>
          </div>

          <!-- Percussion -->
          <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-4 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-semibold text-slate-900 dark:text-neutral-100 uppercase tracking-wider">Percussion</span>
              <span class="text-[10px] font-medium bg-slate-100 dark:bg-[#242933] text-slate-700 dark:text-neutral-300 border border-slate-200 dark:border-[#2d3442] px-2 py-0.5 rounded-full">
                {{ sectionStats.percussion.count }} Members
              </span>
            </div>
            <div class="flex items-baseline justify-between text-xs">
              <span class="text-slate-500 dark:text-neutral-400">Turnout Rate</span>
              <span class="font-bold text-slate-900 dark:text-neutral-100">{{ sectionStats.percussion.displayRate }}</span>
            </div>
            <div class="w-full bg-slate-100 dark:bg-[#242933] h-1.5 rounded-full overflow-hidden">
              <div class="bg-slate-900 dark:bg-white h-full rounded-full" :style="{ width: `${sectionStats.percussion.rate || 0}%` }"></div>
            </div>
            <div class="flex items-center justify-between text-[11px] text-slate-600 dark:text-neutral-400">
              <span>Attended: {{ sectionStats.percussion.attended }} / {{ sectionStats.percussion.promised }}</span>
              <span :class="sectionStats.percussion.flakes > 0 ? 'text-rose-600 dark:text-rose-400 font-medium' : 'text-emerald-700 dark:text-emerald-400'">
                {{ sectionStats.percussion.flakes }} No-Shows
              </span>
            </div>
          </div>

          <!-- Majorette & Color Guard (Auxiliary) -->
          <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-4 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-semibold text-slate-900 dark:text-neutral-100 uppercase tracking-wider">Majorette & Guard</span>
              <span class="text-[10px] font-medium bg-slate-100 dark:bg-[#242933] text-slate-700 dark:text-neutral-300 border border-slate-200 dark:border-[#2d3442] px-2 py-0.5 rounded-full">
                {{ sectionStats.auxiliary.count }} Members
              </span>
            </div>
            <div class="flex items-baseline justify-between text-xs">
              <span class="text-slate-500 dark:text-neutral-400">Turnout Rate</span>
              <span class="font-bold text-slate-900 dark:text-neutral-100">{{ sectionStats.auxiliary.displayRate }}</span>
            </div>
            <div class="w-full bg-slate-100 dark:bg-[#242933] h-1.5 rounded-full overflow-hidden">
              <div class="bg-slate-900 dark:bg-white h-full rounded-full" :style="{ width: `${sectionStats.auxiliary.rate || 0}%` }"></div>
            </div>
            <div class="flex items-center justify-between text-[11px] text-slate-600 dark:text-neutral-400">
              <span>Attended: {{ sectionStats.auxiliary.attended }} / {{ sectionStats.auxiliary.promised }}</span>
              <span :class="sectionStats.auxiliary.flakes > 0 ? 'text-rose-600 dark:text-rose-400 font-medium' : 'text-emerald-700 dark:text-emerald-400'">
                {{ sectionStats.auxiliary.flakes }} No-Shows
              </span>
            </div>
          </div>
        </div>

        <!-- Interactive Attendance & Commitment Matrix Table -->
        <div class="bg-white dark:bg-[#1a1e26] rounded-2xl p-5 sm:p-6 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-4">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div>
              <h3 class="font-bold text-base text-slate-900 dark:text-neutral-100">Musician Attendance &amp; Commitment Matrix</h3>
              <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">
                Track record, verified turnout, unexcused no-show counts, and reliability standings.
              </p>
            </div>

            <!-- Search and Filter Controls (Responsive Grid with Reset Filters) -->
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2 w-full pt-1">
              <!-- Search -->
              <div class="relative w-full">
                <label for="analytics-search-input" class="sr-only">Search musician by name or section</label>
                <Search class="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-500 dark:text-neutral-400" />
                <input 
                  id="analytics-search-input"
                  v-model="analyticsSearchQuery" 
                  type="text" 
                  placeholder="Search musician..."
                  class="w-full pl-9 pr-3.5 py-2.5 bg-slate-50 dark:bg-[#242933] text-slate-900 dark:text-white rounded-full text-xs border border-slate-200 dark:border-[#2d3442] font-medium focus:outline-none focus:border-slate-400 min-h-[44px]"
                />
              </div>

              <!-- Section Filter -->
              <div>
                <label for="analytics-section-filter" class="sr-only">Filter musicians by section</label>
                <select 
                  id="analytics-section-filter"
                  v-model="analyticsSectionFilter" 
                  class="w-full bg-slate-50 dark:bg-[#242933] text-slate-900 dark:text-white rounded-full px-4 py-2.5 text-xs border border-slate-200 dark:border-[#2d3442] font-medium min-h-[44px] cursor-pointer focus:outline-none focus:border-slate-400"
                >
                  <option v-for="sec in sectionOptions" :key="sec" :value="sec">{{ sec === 'All' ? 'All Sections' : sec }}</option>
                </select>
              </div>

              <!-- Sort Order -->
              <div>
                <label for="analytics-sort-select" class="sr-only">Sort musicians by attendance or reliability</label>
                <select 
                  id="analytics-sort-select"
                  v-model="analyticsSortBy" 
                  class="w-full bg-slate-50 dark:bg-[#242933] text-slate-900 dark:text-white rounded-full px-4 py-2.5 text-xs border border-slate-200 dark:border-[#2d3442] font-medium min-h-[44px] cursor-pointer focus:outline-none focus:border-slate-400"
                >
                  <option value="flakes_desc">Sort: Most No-Shows First</option>
                  <option value="reliability_asc">Sort: Lowest Reliability First</option>
                  <option value="reliability_desc">Sort: Highest Reliability First</option>
                  <option value="name">Sort: Musician Name (A-Z)</option>
                </select>
              </div>

              <!-- Reset Filters Action Button -->
              <button 
                @click="resetAnalyticsFilters"
                type="button"
                class="w-full flex items-center justify-center space-x-1.5 px-3 py-2.5 bg-slate-100 hover:bg-slate-200 dark:bg-[#242933] dark:hover:bg-[#2e3440] text-slate-700 dark:text-neutral-300 rounded-full text-xs font-semibold border border-slate-200 dark:border-[#2d3442] min-h-[44px] transition-colors cursor-pointer"
                title="Reset search and filters to default"
              >
                <RotateCcw class="w-3.5 h-3.5 text-slate-500 dark:text-neutral-400" />
                <span>Reset Filters</span>
              </button>
            </div>
          </div>

          <!-- MOBILE VIEW: RESPONSIVE ANALYTICS CARDS (Hidden on Desktop/Tablet) -->
          <div class="block md:hidden space-y-3">
            <div 
              v-for="(member, idx) in filteredAnalyticsMatrix" 
              :key="member.id"
              class="bg-white dark:bg-[#1e232d] p-4 rounded-2xl border border-slate-200/80 dark:border-[#2d3442] space-y-3 shadow-xs"
              :class="{ 'border-rose-300 dark:border-rose-900/50 bg-rose-50/20': member.flakeCount >= 2 }"
            >
              <div class="flex items-start justify-between gap-2">
                <div>
                  <div class="font-bold text-sm text-slate-900 dark:text-neutral-100 flex items-center gap-1.5">
                    <span class="text-xs text-slate-400">#{{ idx + 1 }}</span>
                    <span>{{ member.name }}</span>
                  </div>
                  <div class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5 capitalize">
                    {{ member.instrument }} • {{ member.rank }}
                  </div>
                </div>
                <span 
                  class="text-[10px] font-semibold px-2.5 py-0.5 rounded-full border shrink-0"
                  :class="{
                    'bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-300 border-slate-200 dark:border-neutral-700': member.riskTier === 'Reliable',
                    'bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-400 border-amber-200 dark:border-amber-900/40': member.riskTier === 'Moderate Risk',
                    'bg-rose-50 dark:bg-rose-950/40 text-rose-700 dark:text-rose-400 border-rose-200 dark:border-rose-900/40': member.riskTier === 'High No-Show Risk'
                  }"
                >
                  {{ member.riskTier }}
                </span>
              </div>

              <div class="grid grid-cols-4 gap-2 pt-2 border-t border-slate-100 dark:border-[#2d3442] text-center text-xs">
                <div>
                  <span class="block text-[10px] text-slate-400 uppercase">RSVPs</span>
                  <span class="font-semibold text-slate-800 dark:text-neutral-200">{{ member.promisedCount }}</span>
                </div>
                <div>
                  <span class="block text-[10px] text-slate-400 uppercase">Present</span>
                  <span class="font-semibold text-emerald-700 dark:text-emerald-400">{{ member.attendedCount }}</span>
                </div>
                <div>
                  <span class="block text-[10px] text-slate-400 uppercase">No-Shows</span>
                  <span class="font-semibold" :class="member.flakeCount > 0 ? 'text-rose-600' : 'text-slate-800 dark:text-neutral-200'">{{ member.flakeCount }}</span>
                </div>
                <div>
                  <span class="block text-[10px] text-slate-400 uppercase">Reliability</span>
                  <span class="font-bold text-slate-900 dark:text-white">{{ member.reliabilityScore }}%</span>
                </div>
              </div>
            </div>

            <div v-if="filteredAnalyticsMatrix.length === 0" class="py-8 text-center text-slate-600 dark:text-neutral-400 font-medium">
              <p class="mb-2">No musicians matched your search or section filters.</p>
              <button 
                @click="resetAnalyticsFilters" 
                type="button" 
                class="m3-btn-tonal text-xs min-h-[36px] px-3.5 inline-flex items-center"
              >
                <RotateCcw class="w-3.5 h-3.5 mr-1.5" /> Reset Filters
              </button>
            </div>
          </div>

          <!-- DESKTOP VIEW: DATA TABLE (Hidden on Mobile) -->
          <div class="hidden md:block overflow-x-auto rounded-2xl border border-slate-200/80 dark:border-[#2d3442]">
            <table class="w-full text-left text-xs">
              <thead class="bg-slate-50 dark:bg-[#242933] text-slate-500 dark:text-neutral-400 font-semibold uppercase text-xs tracking-wider border-b border-slate-200 dark:border-[#2d3442] h-12">
                <tr>
                  <th class="px-3 py-2.5 w-10 text-center">#</th>
                  <th class="px-4 py-2.5">Musician</th>
                  <th class="px-3 py-2.5">Role</th>
                  <th class="px-3 py-2.5 text-center">Promised</th>
                  <th class="px-3 py-2.5 text-center">Attended</th>
                  <th class="px-3 py-2.5 text-center">No-Shows</th>
                  <th class="px-3 py-2.5 text-center">Follow-Through</th>
                  <th class="px-3 py-2.5 text-center">Reliability</th>
                  <th class="px-3 py-2.5 text-center">Status</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100 dark:divide-[#2d3442]">
                <tr 
                  v-for="(member, idx) in filteredAnalyticsMatrix" 
                  :key="member.id"
                  class="hover:bg-slate-50/60 dark:hover:bg-[#242933]/60 transition-colors"
                  :class="{ 'bg-rose-50/30 dark:bg-rose-950/10': member.flakeCount >= 2 }"
                >
                  <td class="px-3 py-2.5 text-center font-normal text-slate-600 dark:text-neutral-400">{{ idx + 1 }}</td>
                  
                  <!-- Musician & Instrument -->
                  <td class="px-4 py-2.5">
                    <div class="font-medium text-slate-900 dark:text-neutral-100 leading-tight">
                      {{ member.name }}
                    </div>
                    <div class="flex items-center space-x-1.5 mt-0.5 text-[11px] text-slate-500 dark:text-neutral-400 capitalize">
                      <span>{{ member.instrument }}</span>
                      <span>•</span>
                      <span>{{ member.rank }}</span>
                    </div>
                  </td>

                  <!-- Role / Title -->
                  <td class="px-3 py-2.5 text-slate-600 dark:text-neutral-300 whitespace-nowrap font-medium">
                    <span v-if="member.role === 'super_admin'" class="text-slate-900 dark:text-white font-semibold">IT Super Admin</span>
                    <span v-else-if="member.role === 'secretary_admin'" class="text-slate-800 dark:text-neutral-200 font-semibold">Band Secretary</span>
                    <span v-else-if="member.executive_title" class="text-slate-800 dark:text-neutral-200 capitalize">
                      {{ member.executive_title.replace('_', ' ') }}
                    </span>
                    <span v-else class="text-slate-500 dark:text-neutral-400">Musician</span>
                  </td>

                  <!-- Promised Gigs -->
                  <td class="px-3 py-2.5 text-center font-medium text-slate-700 dark:text-neutral-300">
                    <span class="px-2 py-0.5 rounded-full bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-300">
                      {{ member.promisedCount }}
                    </span>
                  </td>

                  <!-- Attended Gigs -->
                  <td class="px-3 py-2.5 text-center font-medium text-slate-700 dark:text-neutral-300">
                    <span class="px-2 py-0.5 rounded-full bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-300">
                      {{ member.attendedCount }}
                    </span>
                  </td>

                  <!-- No-Shows (Promised vs Absent) -->
                  <td class="px-3 py-2.5 text-center">
                    <span 
                      class="px-2 py-0.5 rounded-full text-xs inline-flex items-center space-x-1 font-medium"
                      :class="member.flakeCount > 0 ? 'bg-rose-50 dark:bg-rose-950/40 text-rose-700 dark:text-rose-400 border border-rose-200 dark:border-rose-900/40' : 'text-slate-600 dark:text-neutral-400'"
                    >
                      <AlertTriangle v-if="member.flakeCount > 0" class="w-3 h-3 text-rose-600 dark:text-rose-400 inline mr-0.5" />
                      <span>{{ member.flakeCount }}</span>
                    </span>
                  </td>

                  <!-- Follow-Through % -->
                  <td class="px-3 py-2.5 text-center font-medium text-slate-800 dark:text-neutral-200">
                    {{ member.followThroughRate }}%
                  </td>

                  <!-- Reliability Score -->
                  <td class="px-3 py-2.5 text-center">
                    <div class="inline-flex flex-col items-center">
                      <span 
                        class="font-semibold text-xs text-slate-900 dark:text-neutral-100"
                      >
                        {{ member.reliabilityScore }}%
                      </span>
                      <div class="w-12 bg-slate-100 dark:bg-neutral-800 h-1 rounded-full overflow-hidden mt-1">
                        <div 
                          class="h-full rounded-full bg-slate-900 dark:bg-white" 
                          :style="{ width: `${member.reliabilityScore}%` }"
                        ></div>
                      </div>
                    </div>
                  </td>

                  <!-- Risk Badge -->
                  <td class="px-3 py-2.5 text-center whitespace-nowrap">
                    <span 
                      class="text-[10px] font-medium px-2.5 py-0.5 rounded-full border"
                      :class="{
                        'bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-300 border-slate-200 dark:border-neutral-700': member.riskTier === 'Reliable',
                        'bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-400 border-amber-200 dark:border-amber-900/40': member.riskTier === 'Moderate Risk',
                        'bg-rose-50 dark:bg-rose-950/40 text-rose-700 dark:text-rose-400 border-rose-200 dark:border-rose-900/40': member.riskTier === 'High No-Show Risk'
                      }"
                    >
                      {{ member.riskTier }}
                    </span>
                  </td>
                </tr>

                <tr v-if="filteredAnalyticsMatrix.length === 0">
                  <td colspan="9" class="py-8 text-center text-slate-600 dark:text-neutral-400 font-medium">
                    <p class="mb-2">No musicians matched your search or section filters.</p>
                    <button 
                      @click="resetAnalyticsFilters" 
                      type="button" 
                      class="m3-btn-tonal text-xs min-h-[36px] px-3.5 inline-flex items-center"
                    >
                      <RotateCcw class="w-3.5 h-3.5 mr-1.5" /> Reset Filters
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <!-- 2. OFFICIAL PDF REPORTS GENERATOR (DEDICATED TO SUPER ADMIN) -->
      <section v-if="store.isSuperAdmin" class="space-y-6 pt-4 border-t border-slate-200/80 dark:border-[#2d3442]">
        
        <!-- Controls & Header (Hidden when printing) -->
        <div class="no-print bg-white dark:bg-[#1a1e26] rounded-2xl p-5 sm:p-6 border border-slate-200/80 dark:border-[#2d3442] shadow-xs space-y-4">
          <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3.5">
            <div>
              <div class="flex items-center space-x-2">
                <FileText class="w-4 h-4 text-amber-500 shrink-0" />
                <h3 class="font-bold text-base text-slate-900 dark:text-neutral-100">Official Band Reports</h3>
              </div>
              <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">
                Generate and print standardized official PDF documents with letterheads, data tables, and signatories.
              </p>
            </div>

            <!-- Direct PDF Download & Print Action Buttons -->
            <div class="flex flex-wrap items-center gap-2 shrink-0 w-full sm:w-auto">
              <button 
                @click="downloadPdfReport" 
                :disabled="isGeneratingPdf"
                type="button" 
                class="flex-1 sm:flex-none px-5 py-2.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-neutral-100 text-white dark:text-slate-900 font-medium text-xs rounded-full shadow-xs flex items-center justify-center space-x-2 transition-colors active:scale-95 cursor-pointer min-h-[44px] sm:min-h-[48px] disabled:opacity-50"
              >
                <Download class="w-4 h-4" />
                <span>{{ isGeneratingPdf ? 'Downloading...' : 'Download PDF' }}</span>
              </button>

              <button 
                @click="printReport" 
                type="button" 
                class="flex-1 sm:flex-none px-5 py-2.5 bg-slate-100 hover:bg-slate-200 dark:bg-[#242933] dark:hover:bg-[#2e3440] text-slate-700 dark:text-neutral-200 font-medium text-xs rounded-full border border-slate-200 dark:border-[#2d3442] flex items-center justify-center space-x-2 transition-colors active:scale-95 cursor-pointer min-h-[44px] sm:min-h-[48px]"
                title="Open browser print dialog"
              >
                <Printer class="w-4 h-4" />
                <span>Print Dialog</span>
              </button>

              <button 
                @click="showResetAnalyticsModal = true"
                type="button" 
                class="flex-1 sm:flex-none px-4 py-2.5 bg-rose-50 hover:bg-rose-100 dark:bg-rose-950/30 dark:hover:bg-rose-950/50 text-rose-700 dark:text-rose-400 font-medium text-xs rounded-full border border-rose-200 dark:border-rose-900/40 flex items-center justify-center space-x-1.5 transition-colors active:scale-95 cursor-pointer min-h-[44px] sm:min-h-[48px]"
                title="Reset all reports and attendance data"
              >
                <RotateCcw class="w-4 h-4 text-rose-600 dark:text-rose-400" />
                <span>Reset Data</span>
              </button>
            </div>
          </div>

          <!-- Report Selector & Sub-Filters -->
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-2">
            <!-- Report Type Selection -->
            <div class="sm:col-span-2">
              <label for="report-type-select" class="block text-[11px] font-medium text-slate-500 dark:text-neutral-400 mb-1.5">
                Select Report Document
              </label>
              <select 
                id="report-type-select"
                v-model="selectedReportType" 
                class="w-full bg-slate-50 dark:bg-[#242933] text-slate-900 dark:text-white rounded-xl px-3.5 py-3 border border-slate-200 dark:border-[#2d3442] font-medium text-xs min-h-[48px] focus:outline-none focus:border-slate-400 cursor-pointer"
              >
                <option v-for="opt in reportTypeOptions" :key="opt.id" :value="opt.id">{{ opt.label }}</option>
              </select>
            </div>

            <!-- Sub-Filter for Role (If report 4 selected) -->
            <div v-if="selectedReportType === 'members_by_role'">
              <label for="role-filter-select" class="block text-[11px] font-medium text-slate-500 dark:text-neutral-400 mb-1.5">
                Filter by Role
              </label>
              <select 
                id="role-filter-select"
                v-model="selectedRoleFilter" 
                class="w-full bg-slate-50 dark:bg-[#242933] text-slate-900 dark:text-white rounded-xl px-3.5 py-3 border border-slate-200 dark:border-[#2d3442] font-medium text-xs min-h-[48px] focus:outline-none focus:border-slate-400 cursor-pointer"
              >
                <option value="member">Regular Musicians</option>
                <option value="executive">Executive Officers</option>
                <option value="secretary_admin">Band Secretary</option>
                <option value="super_admin">IT Super Admin</option>
              </select>
            </div>

            <!-- Sub-Filter for Event Category (If report 7 selected) -->
            <div v-if="selectedReportType === 'schedules_by_type'">
              <label for="event-filter-select" class="block text-[11px] font-medium text-slate-500 dark:text-neutral-400 mb-1.5">
                Filter by Event Category
              </label>
              <select 
                id="event-filter-select"
                v-model="selectedEventTypeFilter" 
                class="w-full bg-slate-50 dark:bg-[#242933] text-slate-900 dark:text-white rounded-xl px-3.5 py-3 border border-slate-200 dark:border-[#2d3442] font-medium text-xs min-h-[48px] focus:outline-none focus:border-slate-400 cursor-pointer"
              >
                <option v-for="t in eventTypeOptions" :key="t" :value="t">{{ t }}</option>
              </select>
            </div>

            <!-- Sub-Filter for Specific Event (If report 9 selected) -->
            <div v-if="selectedReportType === 'event_attendance'">
              <label for="event-specific-select" class="block text-[11px] font-medium text-slate-500 dark:text-neutral-400 mb-1.5">
                Select Specific Event
              </label>
              <select 
                id="event-specific-select"
                v-model="selectedSpecificEventId" 
                class="w-full bg-slate-50 dark:bg-[#242933] text-slate-900 dark:text-white rounded-xl px-3.5 py-3 border border-slate-200 dark:border-[#2d3442] font-medium text-xs min-h-[48px] focus:outline-none focus:border-slate-400 cursor-pointer"
              >
                <option value="">-- Latest / Select Event --</option>
                <option v-for="ev in allEvents" :key="ev.id" :value="ev.id">
                  {{ ev.title }} ({{ new Date(ev.event_date).toLocaleDateString() }})
                </option>
              </select>
            </div>
          </div>
        </div>

        <!-- PRINTABLE OFFICIAL PDF SHEET PREVIEW -->
        <div 
          id="printable-report" 
          class="bg-white text-slate-900 rounded-2xl p-8 sm:p-12 border border-slate-200 shadow-xs space-y-5 max-w-4xl mx-auto printable-sheet"
        >
          <!-- Standard Official Letterhead Header with Crest Logo -->
          <div class="text-center pb-3 border-b-2 border-slate-800">
            <div class="w-16 h-18 mx-auto mb-2 flex items-center justify-center">
              <img src="/band1870logo.jpg" alt="Peñaranda Band 1870" width="64" height="72" loading="lazy" class="w-full h-full object-contain" />
            </div>
            <h1 class="text-2xl font-bold text-slate-900 tracking-wider uppercase">
              PEÑARANDA MARCHING BAND 1870
            </h1>
            <p class="text-[11px] uppercase tracking-widest text-slate-600 font-medium mt-0.5">
              Peñaranda, Nueva Ecija • Established 1870 • Municipal Music Unit
            </p>
          </div>

          <!-- Document Title & Subtitle -->
          <div class="text-center space-y-1 pt-1">
            <h2 class="text-lg font-bold text-slate-950 uppercase tracking-wide">
              {{ generatedReportData.title }}
            </h2>
            <p class="text-xs text-slate-600 font-normal italic">
              {{ generatedReportData.subtitle }}
            </p>
          </div>

          <!-- Standard Document Metadata Row -->
          <div class="flex flex-wrap items-center justify-between text-xs text-slate-700 border border-slate-200 bg-slate-50/80 px-4 py-2.5 rounded-lg font-medium">
            <div>
              <span class="text-slate-500">Date Generated: </span>
              <strong>{{ new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' }) }}</strong>
            </div>
            <div>
              <span class="text-slate-500">Document Ref: </span>
              <strong class="font-mono">PMB1870-REP-{{ new Date().getFullYear() }}-{{ generatedReportData.rows.length }}R</strong>
            </div>
            <div>
              <span class="text-slate-500">Total Records: </span>
              <strong>{{ generatedReportData.rows.length }}</strong>
            </div>
          </div>

          <!-- Standard Data Grid Table (Pure white rows, minimal lines) -->
          <div class="overflow-x-auto">
            <table class="w-full text-left text-xs border-collapse border border-slate-200">
              <thead>
                <tr class="bg-slate-50 text-slate-900 text-[11px] font-semibold uppercase tracking-wider">
                  <th 
                    v-for="col in generatedReportData.columns" 
                    :key="col" 
                    class="py-2 px-3 border border-slate-200"
                    :class="{ 'text-center w-12': col === '#' }"
                  >
                    {{ col }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100">
                <tr 
                  v-for="(row, rIdx) in generatedReportData.rows" 
                  :key="rIdx"
                  class="bg-white hover:bg-slate-50/70"
                >
                  <td 
                    v-for="(cell, cIdx) in row" 
                    :key="cIdx" 
                    class="py-2 px-3 border border-slate-200 text-slate-800 font-normal"
                    :class="{ 'text-center font-medium text-slate-600': cIdx === 0 }"
                  >
                    {{ cell }}
                  </td>
                </tr>

                <tr v-if="generatedReportData.rows.length === 0">
                  <td :colspan="generatedReportData.columns.length" class="py-8 text-center text-slate-600 dark:text-neutral-400 font-medium border border-slate-200">
                    No matching records found in database registry for this report query.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- Total Count Footer Line -->
          <div class="flex items-center justify-between text-xs text-slate-600 border-t border-slate-200 pt-2 font-medium">
            <span>Total Records Listed: <strong>{{ generatedReportData.rows.length }}</strong></span>
            <span class="text-[11px] text-slate-500 italic">Official Record of Peñaranda Marching Band 1870</span>
          </div>

          <!-- Standard Signatories Block -->
          <div class="pt-8 grid grid-cols-2 gap-10 text-center text-xs">
            <div class="space-y-1">
              <div class="w-48 mx-auto border-b border-slate-900 pb-1">
                <p class="font-bold text-slate-900 uppercase">
                  {{ store.profile?.full_name || 'IT Super Admin' }}
                </p>
              </div>
              <p class="text-[11px] font-medium text-slate-600">Prepared by (IT Super Admin)</p>
            </div>

            <div class="space-y-1">
              <div class="w-48 mx-auto border-b border-slate-900 pb-1">
                <p class="font-bold text-slate-900 uppercase">
                  Executive Board / Conductor
                </p>
              </div>
              <p class="text-[11px] font-medium text-slate-600">Approved by (Peñaranda Marching Band 1870)</p>
            </div>
          </div>
        </div>
      </section>

      <!-- Non-Super-Admin Notice for Reports Section -->
      <section v-else class="bg-white dark:bg-[#202124] rounded-2xl p-6 border border-slate-200/80 dark:border-neutral-800 shadow-xs text-center space-y-2 no-print">
        <div class="w-10 h-10 rounded-full bg-slate-100 dark:bg-[#2d2f31] text-slate-600 dark:text-neutral-400 flex items-center justify-center mx-auto">
          <Shield class="w-5 h-5" />
        </div>
        <h4 class="font-bold text-sm text-slate-900 dark:text-neutral-100">Super Admin Official Reports Generator</h4>
        <p class="text-xs text-slate-500 dark:text-neutral-400 max-w-md mx-auto">
          Official printable master administrative reports generation is restricted to the Super Admin. Executives and Section Leaders have full interactive access to the Attendance & Flake Analytics Matrix above.
        </p>
      </section>

    </div>

    <!-- CUSTOM CONFIRMATION MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showConfirmModal" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="confirm-decline-modal-title"
      @keydown.escape="showConfirmModal = false; confirmUserTarget = null"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4"
    >
      <div class="m3-surface-modal border border-slate-200/80 dark:border-[#2d3442] rounded-[28px] p-6 max-w-sm w-full space-y-4 shadow-xl text-center">
        <div class="w-12 h-12 rounded-full bg-slate-100 dark:bg-[#242933] text-slate-700 dark:text-neutral-300 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        
        <div>
          <h3 id="confirm-decline-modal-title" class="font-bold text-base text-slate-900 dark:text-neutral-100 leading-tight">Decline Registration?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 mt-1 leading-relaxed">
            Are you sure you want to permanently decline and remove <strong>{{ confirmUserTarget?.full_name }}</strong>?
          </p>
        </div>

        <div class="flex space-x-2 pt-2">
          <button 
            @click="showConfirmModal = false; confirmUserTarget = null" 
            type="button" 
            class="flex-1 py-2.5 bg-slate-100 hover:bg-slate-200 dark:bg-[#242933] dark:hover:bg-[#2e3440] font-medium text-xs rounded-full text-slate-700 dark:text-neutral-200 min-h-[48px] cursor-pointer transition-colors"
          >
            Cancel
          </button>
          <button 
            @click="executeRejectAndDeleteUser" 
            type="button" 
            class="flex-1 py-2.5 bg-rose-600 hover:bg-rose-500 font-medium text-xs text-white rounded-full shadow-xs min-h-[48px] cursor-pointer transition-colors"
          >
            Decline
          </button>
        </div>
      </div>
    </div>

    <!-- RESET REPORTS & ANALYTICS CONFIRMATION MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showResetAnalyticsModal" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="reset-analytics-modal-title"
      @keydown.escape="showResetAnalyticsModal = false"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4"
    >
      <div class="m3-surface-modal border border-slate-200/80 dark:border-[#2d3442] rounded-[28px] p-6 max-w-md w-full space-y-4 shadow-xl text-center">
        <div class="w-12 h-12 rounded-full bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto border border-rose-200 dark:border-rose-900/40">
          <RotateCcw class="w-6 h-6" />
        </div>
        
        <div class="space-y-1.5">
          <h3 id="reset-analytics-modal-title" class="font-bold text-lg text-slate-900 dark:text-neutral-100 leading-tight">Reset Reports &amp; Analytics?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 leading-relaxed">
            This will wipe all recorded event attendance responses, clear roll-call records, and restore <strong>all musician reliability scores back to 100%</strong>.
          </p>
          <div class="p-3 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900/40 rounded-xl text-left text-amber-800 dark:text-amber-300 text-[11px] space-y-1 mt-2">
            <p class="font-semibold flex items-center"><AlertTriangle class="w-3.5 h-3.5 mr-1 text-amber-700 shrink-0" /> Important Warning:</p>
            <p>• All event attendance history will be deleted.</p>
            <p>• Member attendance matrix and flake detections will reset to 0.</p>
            <p>• This action cannot be reversed.</p>
          </div>
        </div>

        <div class="flex space-x-2 pt-2">
          <button 
            @click="showResetAnalyticsModal = false" 
            :disabled="isResettingAnalytics"
            type="button" 
            class="flex-1 py-2.5 bg-slate-100 hover:bg-slate-200 dark:bg-[#242933] dark:hover:bg-[#2e3440] font-medium text-xs rounded-full text-slate-700 dark:text-neutral-200 min-h-[48px] cursor-pointer transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button 
            @click="executeResetReportsAndAnalytics" 
            :disabled="isResettingAnalytics"
            type="button" 
            class="flex-1 py-2.5 bg-rose-600 hover:bg-rose-700 text-white font-medium text-xs rounded-full flex items-center justify-center shadow-xs cursor-pointer min-h-[48px] transition-colors disabled:opacity-50"
          >
            <Loader2 v-if="isResettingAnalytics" class="w-4 h-4 mr-1.5 animate-spin" />
            <RotateCcw v-else class="w-4 h-4 mr-1.5" />
            <span>{{ isResettingAnalytics ? 'Resetting...' : 'Yes, Reset Data' }}</span>
          </button>
        </div>
      </div>
    </div>

  </div>
</template>

<style scoped>
.toast-enter-active,
.toast-leave-active {
  transition: all 0.25s ease;
}
.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translate(-50%, -12px);
}

/* Dedicated Clean Print Styles for Official PDF Export */
@media print {
  /* Hide all dashboard chrome, sidebar, navbars, buttons, headers, search inputs, toasts */
  body {
    background-color: #ffffff !important;
    color: #000000 !important;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif !important;
  }

  :global(aside),
  :global(header),
  :global(nav),
  :global(.no-print),
  .no-print,
  button,
  select,
  input {
    display: none !important;
  }

  /* Expand printable report sheet */
  #printable-report {
    display: block !important;
    position: static !important;
    width: 100% !important;
    max-width: 100% !important;
    margin: 0 !important;
    padding: 24px !important;
    background-color: #ffffff !important;
    color: #000000 !important;
    box-shadow: none !important;
    border: none !important;
  }

  #printable-report * {
    color: #000000 !important;
    background-color: transparent !important;
  }

  #printable-report table {
    width: 100% !important;
    border-collapse: collapse !important;
  }

  #printable-report th {
    background-color: #f1f5f9 !important;
    color: #0f172a !important;
    border: 1px solid #475569 !important;
    padding: 8px 10px !important;
    font-weight: 800 !important;
    font-size: 10pt !important;
    text-transform: uppercase !important;
  }

  #printable-report td {
    border: 1px solid #cbd5e1 !important;
    padding: 8px 10px !important;
    font-size: 9.5pt !important;
  }

  #printable-report tr {
    page-break-inside: avoid !important;
  }
}
</style>
