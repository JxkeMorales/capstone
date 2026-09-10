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
  Download
} from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'
import jsPDF from 'jspdf'
import autoTable from 'jspdf-autotable'

const store = useMainStore()

// Sub-Tab Switcher State ('operations' | 'reports')
const activeTab = ref('operations')

const pendingAccounts = ref([])
const pendingAvatars = ref([])
const memberRoster = ref([])
const notification = ref('')
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

const showToast = (msg) => {
  notification.value = msg
  setTimeout(() => { notification.value = '' }, 3500)
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
    const { error } = await supabase.from('profiles').delete().eq('id', target.id)
    if (error) throw error

    pendingAccounts.value = pendingAccounts.value.filter(u => u.id !== target.id)
    memberRoster.value = memberRoster.value.filter(u => u.id !== target.id)
    showToast(`Removed ${target.full_name}.`)
  } catch (err) {
    console.error('Delete Error:', err)
    showToast('Failed to delete registration.')
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
const triggerReNotifications = async () => {
  // Local inter-tab broadcast
  if ('BroadcastChannel' in window) {
    const ch = new BroadcastChannel('smartband_live_sync')
    ch.postMessage({ 
      type: 'RSVP_REMINDER_BROADCAST', 
      title: '🚨 Urgent RSVP Call-to-Action!',
      message: 'The Band Secretary requests all musicians confirm attendance for upcoming gigs.',
      timestamp: Date.now() 
    })
    ch.close()
  }

  // Supabase Realtime Broadcast to notify any remote devices/clients in real-time
  try {
    const alertChan = supabase.channel('smartband-broadcast-alerts')
    alertChan.subscribe(async (status) => {
      if (status === 'SUBSCRIBED') {
        await alertChan.send({
          type: 'broadcast',
          event: 'rsvp_reminder',
          payload: {
            title: '🚨 Urgent RSVP Call-to-Action!',
            message: 'The Band Secretary requests all musicians confirm attendance for upcoming gigs immediately.',
            sender: store.profile?.full_name || 'Band Secretary'
          }
        })
        supabase.removeChannel(alertChan)
      }
    })
  } catch (e) {
    console.warn('Realtime broadcast error:', e)
  }

  showToast('✓ RSVP reminder notifications dispatched to unconfirmed musicians.')
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

const reportTypeOptions = [
  { id: 'all_members', label: '1. List of All Band Members' },
  { id: 'active_members', label: '2. List of All Active Band Members' },
  { id: 'inactive_members', label: '3. List of All Inactive Band Members' },
  { id: 'members_by_role', label: '4. List of All Band Members Filtered by Roles' },
  { id: 'officers', label: '5. List of Band Leadership & Officers' },
  { id: 'all_schedules', label: '6. List of All Band Schedules & Gigs' },
  { id: 'schedules_by_type', label: '7. List of Schedules Filtered by Types' }
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
    const [eventsRes, rsvpsRes, profilesRes] = await Promise.all([
      supabase.from('events').select('*').order('event_date', { ascending: false }),
      supabase.from('event_rsvps').select('*'),
      supabase.from('profiles').select('*').order('full_name', { ascending: true })
    ])

    if (eventsRes.data) allEvents.value = eventsRes.data
    if (rsvpsRes.data) allRsvps.value = rsvpsRes.data
    if (profilesRes.data) allProfiles.value = profilesRes.data
  } catch (err) {
    console.error('Error loading analytics dataset:', err)
  } finally {
    isLoadingAnalytics.value = false
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

  const getStats = (matchers) => {
    const members = list.filter(m => matchers.some(term => m.instrument.toLowerCase().includes(term)))
    const promised = members.reduce((sum, m) => sum + m.promisedCount, 0)
    const attended = members.reduce((sum, m) => sum + m.attendedCount, 0)
    const flakes = members.reduce((sum, m) => sum + m.flakeCount, 0)
    const rate = promised > 0 ? Math.round((attended / promised) * 100) : 100
    return { count: members.length, promised, attended, flakes, rate }
  }

  return {
    woodwinds: getStats(woodwindNames),
    brass: getStats(brassNames),
    percussion: getStats(percussionNames)
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
    default:
      return `Penaranda_Band_Report_${dateStamp}.pdf`
  }
}

// Direct PDF File Download using jsPDF & autoTable
const downloadPdfReport = () => {
  isGeneratingPdf.value = true
  try {
    const doc = new jsPDF({
      orientation: 'portrait',
      unit: 'pt',
      format: 'a4'
    })

    const pageWidth = doc.internal.pageSize.getWidth()
    const pageHeight = doc.internal.pageSize.getHeight()

    // 1. Header: PEÑARANDA MARCHING BAND 1870
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(15)
    doc.setTextColor(15, 23, 42)
    doc.text('PEÑARANDA MARCHING BAND 1870', pageWidth / 2, 45, { align: 'center' })

    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8.5)
    doc.setTextColor(100, 116, 139)
    doc.text('Peñaranda, Nueva Ecija • Established 1870', pageWidth / 2, 58, { align: 'center' })

    // Divider Line
    doc.setDrawColor(30, 41, 59)
    doc.setLineWidth(1.5)
    doc.line(40, 68, pageWidth - 40, 68)

    // 2. Document Title & Subtitle
    doc.setFont('helvetica', 'bold')
    doc.setFontSize(11)
    doc.setTextColor(15, 23, 42)
    doc.text(generatedReportData.value.title, pageWidth / 2, 88, { align: 'center' })

    if (generatedReportData.value.subtitle) {
      doc.setFont('helvetica', 'italic')
      doc.setFontSize(8)
      doc.setTextColor(100, 116, 139)
      doc.text(generatedReportData.value.subtitle, pageWidth / 2, 100, { align: 'center' })
    }

    // 3. Metadata Row
    const metaY = 114
    doc.setFillColor(248, 250, 252)
    doc.setDrawColor(203, 213, 225)
    doc.setLineWidth(0.5)
    doc.roundedRect(40, metaY - 10, pageWidth - 80, 18, 3, 3, 'FD')

    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8)
    doc.setTextColor(51, 65, 85)
    doc.text(`Date: ${new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}`, 48, metaY + 2)
    doc.text(`Doc Ref: PMB1870-REP-${new Date().getFullYear()}-${generatedReportData.value.rows.length}R`, pageWidth / 2, metaY + 2, { align: 'center' })
    doc.text(`Total Records: ${generatedReportData.value.rows.length}`, pageWidth - 48, metaY + 2, { align: 'right' })

    // 4. Clean Standard Data Table
    autoTable(doc, {
      startY: 128,
      head: [generatedReportData.value.columns],
      body: generatedReportData.value.rows.length > 0 ? generatedReportData.value.rows : [['-', 'No records found in database query', '', '', '']],
      theme: 'grid',
      headStyles: {
        fillColor: [241, 245, 249],
        textColor: [15, 23, 42],
        fontStyle: 'bold',
        fontSize: 8.5,
        lineColor: [203, 213, 225],
        lineWidth: 0.5,
        halign: 'left'
      },
      styles: {
        font: 'helvetica',
        fontSize: 8,
        textColor: [30, 41, 59],
        lineColor: [226, 232, 240],
        lineWidth: 0.5,
        cellPadding: 5
      },
      alternateRowStyles: {
        fillColor: [248, 250, 252]
      },
      columnStyles: {
        0: { halign: 'center', cellWidth: 28 }
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

onMounted(() => {
  if (store.isExecutive) {
    activeTab.value = 'reports'
  }
  fetchPendingAccounts()
  fetchPendingAvatars()
  fetchRoster()
  fetchAnalyticsAndReportsData()

  adminChannel = supabase
    .channel('admin-realtime')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, () => {
      fetchPendingAccounts()
      fetchPendingAvatars()
      fetchRoster()
      fetchAnalyticsAndReportsData()
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'event_rsvps' }, () => {
      fetchAnalyticsAndReportsData()
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'events' }, () => {
      fetchAnalyticsAndReportsData()
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
  <div class="p-4 sm:p-6 space-y-6 max-w-7xl mx-auto relative">
    
    <!-- Header -->
    <header class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pt-1 border-b border-slate-200/80 dark:border-neutral-800 pb-4">
      <div class="flex items-center space-x-3.5">
        <div class="p-2.5 rounded-2xl bg-blue-500/10 text-blue-600 dark:text-blue-400 flex-shrink-0">
          <Shield class="w-6 h-6" />
        </div>
        <div class="min-w-0">
          <p class="text-xs font-bold text-blue-600 dark:text-blue-400 uppercase tracking-wider leading-tight mb-0.5">
            {{ store.isSuperAdmin ? 'IT Super Admin Management' : 'Band Operations Hub' }}
          </p>
          <h1 class="text-2xl sm:text-3xl font-black text-slate-900 dark:text-white leading-tight truncate">
            Admin Operations
          </h1>
        </div>
      </div>

      <!-- Tab Switcher: Operations vs Reports -->
      <div class="flex rounded-2xl bg-slate-100 dark:bg-[#27272a] p-1.5 text-xs font-bold border border-slate-200/80 dark:border-neutral-800">
        <button 
          type="button" 
          @click="activeTab = 'operations'"
          class="flex items-center space-x-2 px-4 py-2 rounded-xl transition-all cursor-pointer"
          :class="activeTab === 'operations' 
            ? 'bg-white dark:bg-[#1c1c1e] text-blue-600 dark:text-blue-400 shadow-sm font-black' 
            : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
        >
          <Activity class="w-4 h-4" />
          <span>Operations Hub</span>
        </button>

        <button 
          type="button" 
          @click="activeTab = 'reports'"
          class="flex items-center space-x-2 px-4 py-2 rounded-xl transition-all cursor-pointer"
          :class="activeTab === 'reports' 
            ? 'bg-white dark:bg-[#1c1c1e] text-blue-600 dark:text-blue-400 shadow-sm font-black' 
            : 'text-slate-500 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white'"
        >
          <BarChart3 class="w-4 h-4" />
          <span>Reports & Analytics</span>
        </button>
      </div>
    </header>

    <!-- Toast Notification -->
    <Transition name="toast">
      <div 
        v-if="notification" 
        class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-xs sm:max-w-md w-11/12 bg-white dark:bg-[#1c1c1e] text-slate-900 dark:text-white px-4 py-3 rounded-2xl shadow-xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between font-bold text-xs"
      >
        <div class="flex items-center space-x-2 min-w-0 pr-2">
          <CheckCircle2 class="w-4 h-4 text-emerald-500 flex-shrink-0" />
          <span class="truncate">{{ notification }}</span>
        </div>
        <button @click="notification = ''" class="ml-2 text-slate-400 hover:text-slate-900 dark:hover:text-white min-w-[28px] min-h-[28px] flex items-center justify-center cursor-pointer">
          <X class="w-3.5 h-3.5" />
        </button>
      </div>
    </Transition>

    <!-- TAB 1: OPERATIONS HUB -->
    <div v-if="activeTab === 'operations'" class="space-y-6">

      <!-- 1. ACCURATE DATE-SYNCED MEMBER AVAILABILITY CHECKER -->
      <section v-if="store.isSecretaryAdmin || store.isSuperAdmin" class="space-y-4">
        <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-5 sm:p-6 shadow-xs border border-slate-200/80 dark:border-neutral-800 space-y-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-2.5">
              <Calendar class="w-5 h-5 text-blue-500" />
              <h2 class="font-black text-base text-slate-900 dark:text-white">Check Member Availability</h2>
            </div>
            <span class="text-[10px] font-black bg-blue-500/10 text-blue-600 dark:text-blue-400 px-3 py-1 rounded-full uppercase tracking-wider">
              Operations Tool
            </span>
          </div>

          <p class="text-xs text-slate-500 dark:text-neutral-400 font-medium">
            Select target weekday & date to cross-reference available musicians for upcoming gigs and rehearsals.
          </p>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 text-xs font-bold">
            <div>
              <label for="day-select" class="block text-[10px] uppercase text-slate-400 mb-1.5">Target Day & Date</label>
              <select 
                id="day-select" 
                v-model="selectedDayNeeded" 
                class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[44px] cursor-pointer"
              >
                <option 
                  v-for="d in weekDaysOptions" 
                  :key="d.key" 
                  :value="d.key"
                  :disabled="d.isPast"
                  :class="d.isPast ? 'text-slate-400 dark:text-neutral-500 bg-slate-100 dark:bg-neutral-800/80 italic' : 'text-slate-900 dark:text-white font-bold'"
                >
                  {{ d.fullLabel }}
                </option>
              </select>
            </div>
            <div>
              <label for="slot-select" class="block text-[10px] uppercase text-slate-400 mb-1.5">Time Slot</label>
              <select id="slot-select" v-model="selectedSlotNeeded" class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700/80 font-bold min-h-[44px]">
                <option v-for="s in timeSlots" :key="s" :value="s">{{ s }}</option>
              </select>
            </div>
            <div>
              <label for="inst-select" class="block text-[10px] uppercase text-slate-400 mb-1.5">Instrument Section</label>
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

          <p v-if="isSelectedDayPast" class="text-[11px] text-amber-500 dark:text-amber-400 font-bold flex items-center">
            <AlertTriangle class="w-3.5 h-3.5 mr-1.5 shrink-0 inline" /> Selected day has already passed and cannot be checked. Please choose today or an upcoming day.
          </p>

          <button 
            @click="runAvailabilityCheck"
            type="button"
            :disabled="isSelectedDayPast"
            class="w-full py-3.5 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed text-white font-black text-xs rounded-xl flex items-center justify-center transition-all shadow-md active:scale-95 cursor-pointer min-h-[44px]"
          >
            <Cpu class="w-4 h-4 mr-2" /> Check Available Musicians
          </button>
        </div>

        <!-- MATCHED AVAILABILITY DISPLAY -->
        <div v-if="isDispatchGenerated" class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-5 shadow-xs border border-slate-200 dark:border-neutral-800 space-y-3">
          <div class="flex items-center justify-between">
            <h3 class="font-black text-sm text-slate-900 dark:text-white">Roster for {{ selectedDayNeeded }} ({{ selectedSlotNeeded.split(' ')[0] }})</h3>
            <span class="text-xs font-bold text-emerald-600 dark:text-emerald-400 bg-emerald-100 dark:bg-emerald-950/60 px-3 py-1 rounded-lg">
              {{ availableUserIds.size }} Available
            </span>
          </div>

          <div class="space-y-2 max-h-[300px] overflow-y-auto pr-1">
            <div v-for="m in matchedDispatchRoster" :key="m.id" class="p-3 bg-slate-50 dark:bg-[#27272a] rounded-2xl flex items-center justify-between text-xs">
              <div class="flex items-center space-x-2">
                <span class="font-bold text-slate-900 dark:text-white">{{ m.full_name }} ({{ m.instrument }})</span>
                <span v-if="availableUserIds.has(m.id)" class="text-[10px] font-black bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-400 px-2.5 py-0.5 rounded">
                  ✓ Free
                </span>
                <span v-else class="text-[10px] font-bold text-slate-400">Unavailable</span>
              </div>
              <span class="font-bold text-slate-500 dark:text-neutral-400">{{ m.rank }}</span>
            </div>
          </div>
        </div>

        <!-- 2. RSVP RE-NOTIFICATIONS -->
        <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-5 shadow-xs border border-slate-200 dark:border-neutral-800 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div>
            <h3 class="font-bold text-sm text-slate-900 dark:text-white">RSVP Re-notifications</h3>
            <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">Send follow-up reminder alerts to unconfirmed musicians</p>
          </div>
          <button 
            @click="triggerReNotifications"
            type="button"
            class="py-3 px-4 bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs rounded-xl flex items-center justify-center shadow-xs active:scale-95 cursor-pointer min-h-[44px]"
          >
            <Send class="w-4 h-4 mr-2" /> Alert Unconfirmed
          </button>
        </div>
      </section>

      <!-- 3. PENDING MASTER LIST APPROVALS QUEUE (IT Super Admin) -->
      <section v-if="store.isSuperAdmin" class="space-y-3" aria-label="Pending Approvals Section">
        <div class="flex items-center justify-between px-1">
          <div class="flex items-center space-x-2">
            <ShieldAlert class="w-4 h-4 text-amber-500" />
            <h2 class="text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
              Pending Master List Approvals ({{ pendingAccounts.length }})
            </h2>
          </div>
          <span v-if="pendingAccounts.length > 3" class="text-[10px] font-bold text-slate-400 dark:text-neutral-500">
            Scroll for more
          </span>
        </div>

        <div :class="pendingAccounts.length > 3 ? 'max-h-[400px] overflow-y-auto pr-1 space-y-3' : 'space-y-3'">
          <div 
            v-for="user in pendingAccounts" 
            :key="user.id"
            class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 sm:p-5 shadow-xs border border-slate-200/80 dark:border-neutral-800 space-y-3"
          >
            <div class="flex justify-between items-start">
              <div>
                <h3 class="font-black text-base text-slate-900 dark:text-white leading-tight">{{ user.full_name }}</h3>
                <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">{{ user.email }} • {{ user.contact_number }}</p>
              </div>
              <span class="text-[10px] font-extrabold bg-amber-100 dark:bg-amber-950/60 text-amber-800 dark:text-amber-300 px-2.5 py-1 rounded-lg">
                UNVERIFIED
              </span>
            </div>

            <div class="grid grid-cols-2 gap-2 text-xs font-semibold bg-slate-50 dark:bg-[#27272a] p-3 rounded-2xl text-slate-600 dark:text-neutral-300">
              <div><span class="text-slate-400">Section:</span> {{ user.instrument || 'None' }}</div>
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
                class="py-3 px-4 bg-rose-600/10 hover:bg-rose-600/20 text-rose-600 dark:text-rose-400 font-bold text-xs rounded-xl flex items-center justify-center transition-all active:scale-95 border border-rose-200 dark:border-rose-900/40 cursor-pointer min-h-[44px]"
              >
                <Trash2 class="w-4 h-4 mr-1" /> Decline
              </button>
            </div>
          </div>

          <div v-if="pendingAccounts.length === 0" class="text-center p-8 bg-white dark:bg-[#1c1c1e] rounded-3xl border border-slate-200/80 dark:border-neutral-800">
            <CheckCircle2 class="w-8 h-8 text-emerald-400 mx-auto mb-2 opacity-50" />
            <p class="text-xs font-bold text-slate-500 dark:text-neutral-400">No pending accounts in queue.</p>
          </div>
        </div>
      </section>

      <!-- 4. PENDING AVATARS APPROVAL QUEUE -->
      <section v-if="pendingAvatars.length > 0" class="space-y-3" aria-label="Avatar Moderation Queue">
        <div class="flex items-center justify-between px-1">
          <div class="flex items-center space-x-2">
            <AlertCircle class="w-4 h-4 text-amber-500" />
            <h2 class="text-xs font-extrabold text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
              Pending Avatar Approvals ({{ pendingAvatars.length }})
            </h2>
          </div>
          <span v-if="pendingAvatars.length > 3" class="text-[10px] font-bold text-slate-400 dark:text-neutral-500">
            Scroll for more
          </span>
        </div>

        <div :class="pendingAvatars.length > 3 ? 'max-h-[380px] overflow-y-auto pr-1' : ''">
          <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
            <div 
              v-for="user in pendingAvatars" 
              :key="user.id"
              class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-3.5 shadow-xs border border-slate-200/80 dark:border-neutral-800 flex flex-col items-center text-center space-y-2.5"
            >
              <img :src="user.profile_picture" alt="Avatar Review" class="w-16 h-16 rounded-2xl object-cover shadow-md border border-slate-200 dark:border-neutral-700" />
              <p class="text-xs font-black text-slate-900 dark:text-white line-clamp-1 w-full">{{ user.full_name }}</p>
              <div class="flex space-x-1.5 w-full">
                <button @click="approveAvatar(user.id, user.full_name)" class="flex-1 py-1.5 bg-emerald-50 text-emerald-600 dark:bg-emerald-950/40 dark:text-emerald-400 font-bold border border-emerald-200 dark:border-emerald-900/40 hover:bg-emerald-100 rounded-xl cursor-pointer text-[10px] uppercase">Approve</button>
                <button @click="declineAvatar(user.id, user.full_name)" class="flex-1 py-1.5 bg-rose-50 text-rose-600 dark:bg-rose-950/40 dark:text-rose-400 font-bold border border-rose-200 dark:border-rose-900/40 hover:bg-rose-100 rounded-xl cursor-pointer text-[10px] uppercase">Decline</button>
              </div>
            </div>
          </div>
        </div>
      </section>

    </div>

    <!-- TAB 2: REPORTS & ANALYTICS -->
    <div v-else-if="activeTab === 'reports'" class="space-y-8">
      
      <!-- 1. EXECUTIVE ATTENDANCE & FLAKE ANALYTICS DASHBOARD -->
      <section class="space-y-6 no-print">
        <!-- Section Header -->
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 border-b border-slate-200/80 dark:border-neutral-800 pb-3">
          <div>
            <div class="flex items-center space-x-2">
              <BarChart3 class="w-5 h-5 text-blue-500" />
              <h2 class="text-lg font-black text-slate-900 dark:text-white">Band Attendance & Reliability Analytics</h2>
            </div>
            <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">
              Live calculated follow-through metrics, section turnout rates, and unexcused no-show flake penalties.
            </p>
          </div>
          <span class="inline-flex items-center space-x-1.5 px-3 py-1 rounded-full bg-blue-500/10 text-blue-600 dark:text-blue-400 text-xs font-black uppercase tracking-wider self-start sm:self-auto">
            <Sparkles class="w-3.5 h-3.5" />
            <span>Executive Insights</span>
          </span>
        </div>

        <!-- 4 KPI Summary Cards -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3.5">
          <!-- KPI 1: Band Reliability Score -->
          <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 sm:p-5 border border-slate-200/80 dark:border-neutral-800 shadow-xs space-y-2">
            <div class="flex items-center justify-between text-xs font-bold text-slate-500 dark:text-neutral-400">
              <span>Avg Reliability</span>
              <Award class="w-4 h-4 text-emerald-500" />
            </div>
            <div class="flex items-baseline space-x-2">
              <span class="text-2xl sm:text-3xl font-black text-slate-900 dark:text-white">
                {{ analyticsSummary.avgReliability }}%
              </span>
              <span class="text-[10px] font-extrabold text-emerald-600 dark:text-emerald-400">Roster Avg</span>
            </div>
            <!-- Progress Bar -->
            <div class="w-full bg-slate-100 dark:bg-neutral-800 h-1.5 rounded-full overflow-hidden">
              <div 
                class="h-full rounded-full transition-all duration-500" 
                :class="analyticsSummary.avgReliability >= 85 ? 'bg-emerald-500' : analyticsSummary.avgReliability >= 70 ? 'bg-amber-500' : 'bg-rose-500'"
                :style="{ width: `${analyticsSummary.avgReliability}%` }"
              ></div>
            </div>
          </div>

          <!-- KPI 2: Total Unexcused No-Shows -->
          <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 sm:p-5 border border-slate-200/80 dark:border-neutral-800 shadow-xs space-y-2">
            <div class="flex items-center justify-between text-xs font-bold text-slate-500 dark:text-neutral-400">
              <span>Unexcused No-Shows</span>
              <AlertTriangle class="w-4 h-4 text-rose-500" />
            </div>
            <div class="flex items-baseline space-x-2">
              <span class="text-2xl sm:text-3xl font-black text-rose-600 dark:text-rose-400">
                {{ analyticsSummary.totalFlakes }}
              </span>
              <span class="text-[10px] font-bold text-slate-400">Promised vs Absent</span>
            </div>
            <p class="text-[11px] font-bold text-slate-500 dark:text-neutral-400">
              -10% penalty per unexcused no-show
            </p>
          </div>

          <!-- KPI 3: Follow-Through Rate -->
          <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 sm:p-5 border border-slate-200/80 dark:border-neutral-800 shadow-xs space-y-2">
            <div class="flex items-center justify-between text-xs font-bold text-slate-500 dark:text-neutral-400">
              <span>Commitment Rate</span>
              <TrendingUp class="w-4 h-4 text-blue-500" />
            </div>
            <div class="flex items-baseline space-x-2">
              <span class="text-2xl sm:text-3xl font-black text-blue-600 dark:text-blue-400">
                {{ analyticsSummary.avgFollowThrough }}%
              </span>
              <span class="text-[10px] font-extrabold text-blue-600 dark:text-blue-400">Turnout</span>
            </div>
            <div class="w-full bg-slate-100 dark:bg-neutral-800 h-1.5 rounded-full overflow-hidden">
              <div 
                class="bg-blue-500 h-full rounded-full transition-all duration-500" 
                :style="{ width: `${analyticsSummary.avgFollowThrough}%` }"
              ></div>
            </div>
          </div>

          <!-- KPI 4: High No-Show Risk Members -->
          <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 sm:p-5 border border-slate-200/80 dark:border-neutral-800 shadow-xs space-y-2">
            <div class="flex items-center justify-between text-xs font-bold text-slate-500 dark:text-neutral-400">
              <span>Attendance Risk</span>
              <ShieldAlert class="w-4 h-4 text-amber-500" />
            </div>
            <div class="flex items-baseline space-x-2">
              <span class="text-2xl sm:text-3xl font-black text-amber-600 dark:text-amber-400">
                {{ analyticsSummary.highRiskCount }}
              </span>
              <span class="text-[10px] font-bold text-slate-400">Flagged Musicians</span>
            </div>
            <p class="text-[11px] font-bold text-slate-500 dark:text-neutral-400">
              Members with multiple misses
            </p>
          </div>
        </div>

        <!-- Section Turnout Breakdown Cards -->
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3.5">
          <!-- Woodwinds -->
          <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 border border-slate-200/80 dark:border-neutral-800 shadow-xs space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-black text-slate-900 dark:text-white uppercase tracking-wider">Woodwinds Section</span>
              <span class="text-[10px] font-black bg-blue-500/10 text-blue-600 dark:text-blue-400 px-2 py-0.5 rounded-full">
                {{ sectionStats.woodwinds.count }} Members
              </span>
            </div>
            <div class="flex items-baseline justify-between text-xs">
              <span class="text-slate-500 dark:text-neutral-400 font-bold">Turnout Rate</span>
              <span class="font-black text-slate-900 dark:text-white">{{ sectionStats.woodwinds.rate }}%</span>
            </div>
            <div class="w-full bg-slate-100 dark:bg-neutral-800 h-1.5 rounded-full overflow-hidden">
              <div class="bg-blue-500 h-full rounded-full" :style="{ width: `${sectionStats.woodwinds.rate}%` }"></div>
            </div>
            <div class="flex items-center justify-between text-[11px] font-bold text-slate-400">
              <span>Attended: {{ sectionStats.woodwinds.attended }} / {{ sectionStats.woodwinds.promised }}</span>
              <span :class="sectionStats.woodwinds.flakes > 0 ? 'text-rose-500 font-black' : 'text-emerald-500'">
                {{ sectionStats.woodwinds.flakes }} No-Shows
              </span>
            </div>
          </div>

          <!-- Brass -->
          <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 border border-slate-200/80 dark:border-neutral-800 shadow-xs space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-black text-slate-900 dark:text-white uppercase tracking-wider">Brass Section</span>
              <span class="text-[10px] font-black bg-amber-500/10 text-amber-600 dark:text-amber-400 px-2 py-0.5 rounded-full">
                {{ sectionStats.brass.count }} Members
              </span>
            </div>
            <div class="flex items-baseline justify-between text-xs">
              <span class="text-slate-500 dark:text-neutral-400 font-bold">Turnout Rate</span>
              <span class="font-black text-slate-900 dark:text-white">{{ sectionStats.brass.rate }}%</span>
            </div>
            <div class="w-full bg-slate-100 dark:bg-neutral-800 h-1.5 rounded-full overflow-hidden">
              <div class="bg-amber-500 h-full rounded-full" :style="{ width: `${sectionStats.brass.rate}%` }"></div>
            </div>
            <div class="flex items-center justify-between text-[11px] font-bold text-slate-400">
              <span>Attended: {{ sectionStats.brass.attended }} / {{ sectionStats.brass.promised }}</span>
              <span :class="sectionStats.brass.flakes > 0 ? 'text-rose-500 font-black' : 'text-emerald-500'">
                {{ sectionStats.brass.flakes }} No-Shows
              </span>
            </div>
          </div>

          <!-- Percussion -->
          <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 border border-slate-200/80 dark:border-neutral-800 shadow-xs space-y-2">
            <div class="flex items-center justify-between">
              <span class="text-xs font-black text-slate-900 dark:text-white uppercase tracking-wider">Percussion Section</span>
              <span class="text-[10px] font-black bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 px-2 py-0.5 rounded-full">
                {{ sectionStats.percussion.count }} Members
              </span>
            </div>
            <div class="flex items-baseline justify-between text-xs">
              <span class="text-slate-500 dark:text-neutral-400 font-bold">Turnout Rate</span>
              <span class="font-black text-slate-900 dark:text-white">{{ sectionStats.percussion.rate }}%</span>
            </div>
            <div class="w-full bg-slate-100 dark:bg-neutral-800 h-1.5 rounded-full overflow-hidden">
              <div class="bg-emerald-500 h-full rounded-full" :style="{ width: `${sectionStats.percussion.rate}%` }"></div>
            </div>
            <div class="flex items-center justify-between text-[11px] font-bold text-slate-400">
              <span>Attended: {{ sectionStats.percussion.attended }} / {{ sectionStats.percussion.promised }}</span>
              <span :class="sectionStats.percussion.flakes > 0 ? 'text-rose-500 font-black' : 'text-emerald-500'">
                {{ sectionStats.percussion.flakes }} No-Shows
              </span>
            </div>
          </div>
        </div>

        <!-- Interactive Excel-Style Attendance Matrix Table -->
        <div class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-5 sm:p-6 border border-slate-200/80 dark:border-neutral-800 shadow-xs space-y-4">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div>
              <h3 class="font-black text-base text-slate-900 dark:text-white">Musician Attendance & Commitment Matrix</h3>
              <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">
                Individual attendance track record, verified turnout, unexcused no-show counts, and reliability standings.
              </p>
            </div>

            <!-- Search and Filter Controls -->
            <div class="flex flex-wrap items-center gap-2">
              <!-- Search -->
              <div class="relative min-w-[160px]">
                <Search class="w-3.5 h-3.5 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                <input 
                  v-model="analyticsSearchQuery" 
                  type="text" 
                  placeholder="Search musician..."
                  class="w-full pl-8 pr-3 py-1.5 bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl text-xs border border-slate-200 dark:border-neutral-700 font-bold focus:outline-none focus:border-blue-500 min-h-[38px]"
                />
              </div>

              <!-- Section Filter -->
              <select 
                v-model="analyticsSectionFilter" 
                class="bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl px-3 py-1.5 text-xs border border-slate-200 dark:border-neutral-700 font-bold min-h-[38px]"
              >
                <option v-for="sec in sectionOptions" :key="sec" :value="sec">{{ sec === 'All' ? 'All Sections' : sec }}</option>
              </select>

              <!-- Sort Order -->
              <select 
                v-model="analyticsSortBy" 
                class="bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl px-3 py-1.5 text-xs border border-slate-200 dark:border-neutral-700 font-bold min-h-[38px]"
              >
                <option value="flakes_desc">Sort: Most No-Shows First</option>
                <option value="reliability_asc">Sort: Lowest Reliability First</option>
                <option value="reliability_desc">Sort: Highest Reliability First</option>
                <option value="name">Sort: Musician Name (A-Z)</option>
              </select>
            </div>
          </div>

          <!-- Table -->
          <div class="overflow-x-auto rounded-2xl border border-slate-200/80 dark:border-neutral-700/80">
            <table class="w-full text-left text-xs">
              <thead class="bg-slate-50 dark:bg-[#27272a] text-slate-600 dark:text-neutral-300 font-black uppercase text-[10px] tracking-wider border-b border-slate-200 dark:border-neutral-700">
                <tr>
                  <th class="px-3 py-3 w-10 text-center">#</th>
                  <th class="px-4 py-3">Musician</th>
                  <th class="px-3 py-3">Role / Post</th>
                  <th class="px-3 py-3 text-center">Promised</th>
                  <th class="px-3 py-3 text-center">Attended</th>
                  <th class="px-3 py-3 text-center">No-Shows</th>
                  <th class="px-3 py-3 text-center">Follow-Through</th>
                  <th class="px-3 py-3 text-center">Reliability Score</th>
                  <th class="px-3 py-3 text-center">Attendance Status</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100 dark:divide-neutral-800">
                <tr 
                  v-for="(member, idx) in filteredAnalyticsMatrix" 
                  :key="member.id"
                  class="hover:bg-slate-50/80 dark:hover:bg-neutral-800/50 transition-colors"
                  :class="{ 'bg-rose-50/40 dark:bg-rose-950/20': member.flakeCount >= 2 }"
                >
                  <td class="px-3 py-3 text-center font-bold text-slate-400">{{ idx + 1 }}</td>
                  
                  <!-- Musician & Instrument -->
                  <td class="px-4 py-3">
                    <div class="font-black text-slate-900 dark:text-white leading-tight">
                      {{ member.name }}
                    </div>
                    <div class="flex items-center space-x-1.5 mt-0.5 text-[11px] font-bold text-slate-500 dark:text-neutral-400 capitalize">
                      <span>{{ member.instrument }}</span>
                      <span>•</span>
                      <span>{{ member.rank }}</span>
                    </div>
                  </td>

                  <!-- Role / Title -->
                  <td class="px-3 py-3 font-bold text-slate-600 dark:text-neutral-300 whitespace-nowrap">
                    <span v-if="member.role === 'super_admin'" class="text-blue-600 dark:text-blue-400 font-black">IT Super Admin</span>
                    <span v-else-if="member.role === 'secretary_admin'" class="text-amber-600 dark:text-amber-400 font-black">Band Secretary</span>
                    <span v-else-if="member.executive_title" class="text-purple-600 dark:text-purple-400 font-black capitalize">
                      {{ member.executive_title.replace('_', ' ') }}
                    </span>
                    <span v-else class="text-slate-500 dark:text-neutral-400">Musician</span>
                  </td>

                  <!-- Promised Gigs -->
                  <td class="px-3 py-3 text-center font-bold text-slate-700 dark:text-neutral-300">
                    <span class="px-2 py-0.5 rounded-full bg-blue-50 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300 font-extrabold">
                      {{ member.promisedCount }}
                    </span>
                  </td>

                  <!-- Attended Gigs -->
                  <td class="px-3 py-3 text-center font-bold text-emerald-600 dark:text-emerald-400">
                    <span class="px-2 py-0.5 rounded-full bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300 font-extrabold">
                      {{ member.attendedCount }}
                    </span>
                  </td>

                  <!-- No-Shows (Promised vs Absent) -->
                  <td class="px-3 py-3 text-center font-extrabold">
                    <span 
                      class="px-2 py-0.5 rounded-full font-black text-xs inline-flex items-center space-x-1"
                      :class="member.flakeCount > 0 ? 'bg-rose-100 dark:bg-rose-950/60 text-rose-700 dark:text-rose-300' : 'bg-slate-100 dark:bg-[#27272a] text-slate-500'"
                    >
                      <AlertTriangle v-if="member.flakeCount > 0" class="w-3 h-3 text-rose-500 inline mr-0.5" />
                      <span>{{ member.flakeCount }}</span>
                    </span>
                  </td>

                  <!-- Follow-Through % -->
                  <td class="px-3 py-3 text-center font-black text-slate-800 dark:text-neutral-200">
                    {{ member.followThroughRate }}%
                  </td>

                  <!-- Reliability Score -->
                  <td class="px-3 py-3 text-center">
                    <div class="inline-flex flex-col items-center">
                      <span 
                        class="font-black text-xs"
                        :class="member.reliabilityScore >= 85 ? 'text-emerald-600 dark:text-emerald-400' : member.reliabilityScore >= 70 ? 'text-amber-600 dark:text-amber-400' : 'text-rose-600 dark:text-rose-400'"
                      >
                        {{ member.reliabilityScore }}%
                      </span>
                      <div class="w-14 bg-slate-100 dark:bg-neutral-800 h-1 rounded-full overflow-hidden mt-1">
                        <div 
                          class="h-full rounded-full"
                          :class="member.reliabilityScore >= 85 ? 'bg-emerald-500' : member.reliabilityScore >= 70 ? 'bg-amber-500' : 'bg-rose-500'"
                          :style="{ width: `${member.reliabilityScore}%` }"
                        ></div>
                      </div>
                    </div>
                  </td>

                  <!-- Risk Badge -->
                  <td class="px-3 py-3 text-center whitespace-nowrap">
                    <span 
                      class="text-[10px] font-black uppercase tracking-wider px-2.5 py-1 rounded-full"
                      :class="{
                        'bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-400': member.riskTier === 'Reliable',
                        'bg-amber-100 dark:bg-amber-950/60 text-amber-700 dark:text-amber-400': member.riskTier === 'Moderate Risk',
                        'bg-rose-100 dark:bg-rose-950/60 text-rose-700 dark:text-rose-400': member.riskTier === 'High No-Show Risk'
                      }"
                    >
                      {{ member.riskTier }}
                    </span>
                  </td>
                </tr>

                <tr v-if="filteredAnalyticsMatrix.length === 0">
                  <td colspan="9" class="py-8 text-center text-slate-400 font-bold">
                    No musicians matched your search or section filters.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <!-- 2. OFFICIAL PDF REPORTS GENERATOR (DEDICATED TO SUPER ADMIN) -->
      <section v-if="store.isSuperAdmin" class="space-y-6 pt-4 border-t border-slate-200/80 dark:border-neutral-800">
        
        <!-- Controls & Header (Hidden when printing) -->
        <div class="no-print bg-white dark:bg-[#1c1c1e] rounded-3xl p-5 sm:p-6 border border-slate-200/80 dark:border-neutral-800 shadow-xs space-y-4">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
            <div>
              <div class="flex items-center space-x-2">
                <FileText class="w-5 h-5 text-blue-600 dark:text-blue-400" />
                <h3 class="font-black text-lg text-slate-900 dark:text-white">Official Band Administrative Reports</h3>
              </div>
              <p class="text-xs text-slate-500 dark:text-neutral-400 mt-0.5">
                Generate and print standardized official PDF documents with municipal letterheads, data tables, and signatories.
              </p>
            </div>

            <!-- Direct PDF Download & Print Action Buttons -->
            <div class="flex items-center space-x-2">
              <button 
                @click="downloadPdfReport" 
                :disabled="isGeneratingPdf"
                type="button" 
                class="px-5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white font-black text-xs rounded-xl shadow-md flex items-center justify-center space-x-2 transition-all active:scale-95 cursor-pointer min-h-[44px] disabled:opacity-50"
              >
                <Download class="w-4 h-4" />
                <span>{{ isGeneratingPdf ? 'Downloading...' : 'Download PDF' }}</span>
              </button>

              <button 
                @click="printReport" 
                type="button" 
                class="px-4 py-2.5 bg-slate-100 hover:bg-slate-200 dark:bg-[#27272a] dark:hover:bg-[#323238] text-slate-700 dark:text-neutral-200 font-bold text-xs rounded-xl border border-slate-200 dark:border-neutral-700 flex items-center justify-center space-x-1.5 transition-all active:scale-95 cursor-pointer min-h-[44px]"
                title="Open browser print / print-to-PDF dialog"
              >
                <Printer class="w-4 h-4" />
                <span>Print Dialog</span>
              </button>
            </div>
          </div>

          <!-- Report Selector & Sub-Filters -->
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-2">
            <!-- Report Type Selection -->
            <div class="sm:col-span-2">
              <label for="report-type-select" class="block text-[10px] uppercase font-bold text-slate-400 mb-1.5">
                Select Report Document
              </label>
              <select 
                id="report-type-select"
                v-model="selectedReportType" 
                class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700 font-bold text-xs min-h-[44px]"
              >
                <option v-for="opt in reportTypeOptions" :key="opt.id" :value="opt.id">{{ opt.label }}</option>
              </select>
            </div>

            <!-- Sub-Filter for Role (If report 4 selected) -->
            <div v-if="selectedReportType === 'members_by_role'">
              <label for="role-filter-select" class="block text-[10px] uppercase font-bold text-slate-400 mb-1.5">
                Filter by Role
              </label>
              <select 
                id="role-filter-select"
                v-model="selectedRoleFilter" 
                class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700 font-bold text-xs min-h-[44px]"
              >
                <option value="member">Regular Musicians</option>
                <option value="executive">Executive Officers</option>
                <option value="secretary_admin">Band Secretary</option>
                <option value="super_admin">IT Super Admin</option>
              </select>
            </div>

            <!-- Sub-Filter for Event Category (If report 7 selected) -->
            <div v-if="selectedReportType === 'schedules_by_type'">
              <label for="event-filter-select" class="block text-[10px] uppercase font-bold text-slate-400 mb-1.5">
                Filter by Event Category
              </label>
              <select 
                id="event-filter-select"
                v-model="selectedEventTypeFilter" 
                class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-900 dark:text-white rounded-xl p-3 border border-slate-200 dark:border-neutral-700 font-bold text-xs min-h-[44px]"
              >
                <option v-for="t in eventTypeOptions" :key="t" :value="t">{{ t }}</option>
              </select>
            </div>
          </div>
        </div>

        <!-- PRINTABLE OFFICIAL PDF SHEET PREVIEW -->
        <div 
          id="printable-report" 
          class="bg-white text-slate-900 rounded-2xl p-8 sm:p-12 border border-slate-300 shadow-md space-y-5 max-w-4xl mx-auto printable-sheet"
        >
          <!-- Standard Official Letterhead Header -->
          <div class="text-center pb-3 border-b-2 border-slate-800">
            <h1 class="text-2xl font-black text-slate-900 tracking-wider uppercase">
              PEÑARANDA MARCHING BAND 1870
            </h1>
            <p class="text-[11px] uppercase tracking-widest text-slate-600 font-bold mt-0.5">
              Peñaranda, Nueva Ecija • Established 1870
            </p>
          </div>

          <!-- Document Title & Subtitle -->
          <div class="text-center space-y-1 pt-1">
            <h2 class="text-lg font-black text-slate-950 uppercase tracking-wide">
              {{ generatedReportData.title }}
            </h2>
            <p class="text-xs text-slate-600 font-normal italic">
              {{ generatedReportData.subtitle }}
            </p>
          </div>

          <!-- Standard Document Metadata Row -->
          <div class="flex flex-wrap items-center justify-between text-xs text-slate-700 border border-slate-300 bg-slate-50/80 px-4 py-2.5 rounded-lg font-medium">
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

          <!-- Standard Data Grid Table -->
          <div class="overflow-x-auto">
            <table class="w-full text-left text-xs border-collapse border border-slate-300">
              <thead>
                <tr class="bg-slate-100 text-slate-900 text-[11px] font-bold uppercase tracking-wider">
                  <th 
                    v-for="col in generatedReportData.columns" 
                    :key="col" 
                    class="py-2.5 px-3 border border-slate-300"
                    :class="{ 'text-center w-12': col === '#' }"
                  >
                    {{ col }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-200">
                <tr 
                  v-for="(row, rIdx) in generatedReportData.rows" 
                  :key="rIdx"
                  class="even:bg-slate-50/60 hover:bg-slate-100/50"
                >
                  <td 
                    v-for="(cell, cIdx) in row" 
                    :key="cIdx" 
                    class="py-2 px-3 border border-slate-300 text-slate-800 font-medium"
                    :class="{ 'text-center font-bold text-slate-600': cIdx === 0 }"
                  >
                    {{ cell }}
                  </td>
                </tr>

                <tr v-if="generatedReportData.rows.length === 0">
                  <td :colspan="generatedReportData.columns.length" class="py-8 text-center text-slate-400 font-bold border border-slate-300">
                    No matching records found in database registry for this report query.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- Total Count Footer Line -->
          <div class="flex items-center justify-between text-xs text-slate-600 border-t border-slate-300 pt-2 font-medium">
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
      <section v-else class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-6 border border-slate-200/80 dark:border-neutral-800 shadow-xs text-center space-y-2 no-print">
        <div class="w-10 h-10 rounded-2xl bg-blue-500/10 text-blue-600 dark:text-blue-400 flex items-center justify-center mx-auto">
          <Shield class="w-5 h-5" />
        </div>
        <h4 class="font-black text-sm text-slate-900 dark:text-white">Super Admin Official Reports Generator</h4>
        <p class="text-xs text-slate-500 dark:text-neutral-400 max-w-md mx-auto">
          Official printable master administrative reports generation is restricted to the Super Admin. Executives and Section Leaders have full interactive access to the Attendance & Flake Analytics Matrix above.
        </p>
      </section>

    </div>

    <!-- CUSTOM CONFIRMATION MODAL -->
    <div v-if="showConfirmModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-center">
        <div class="w-12 h-12 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        
        <div>
          <h3 class="font-black text-lg text-slate-900 dark:text-white leading-tight">Decline Registration?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 mt-1 leading-relaxed">
            Are you sure you want to permanently decline and remove <strong>{{ confirmUserTarget?.full_name }}</strong>?
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
            Decline
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
