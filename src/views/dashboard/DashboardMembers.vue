<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { 
  Users, 
  Search, 
  Award, 
  Music, 
  Shield, 
  ShieldCheck, 
  UserX, 
  Filter, 
  X, 
  Calendar, 
  Trash2, 
  CheckCircle2, 
  AlertCircle, 
  Settings,
  SlidersHorizontal,
  ChevronRight,
  UserCheck,
  Star,
  RefreshCw
} from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { useUIStore } from '@/stores/ui'
import { supabase } from '@/supabase'
import { initRealtimeSync, broadcastSync } from '@/utils/realtime'

const store = useMainStore()
const uiStore = useUIStore()

const searchQuery = ref('')
const activeSectionFilter = ref('All')
const activeTierFilter = ref('all') // 'all' | 'officers' | 'senior' | 'junior'
const members = ref([])
const isLoading = ref(true)
const loadError = ref(null)
const toastMessage = ref('')

// Availability Modal Sheet State
const showAvailabilityModal = ref(false)
const selectedMemberForAvailability = ref(null)
const memberAvailabilitySlots = ref([])
const isLoadingAvailability = ref(false)

// Super Admin Musician Management Modal State
const showManageModal = ref(false)
const editingMember = ref(null)
const managePositionId = ref('member')
const manageInstrument = ref('Clarinet')
const manageRank = ref('Junior')
const isSavingManage = ref(false)

// Delete Confirmation Modal State
const showDeleteModal = ref(false)
const confirmDeleteTarget = ref(null)

// Realtime Channel Reference
let membersChannel = null

// UNIFIED SYSTEM POSITIONS (MATCHES SUPABASE DATABASE ENUMS PERFECTLY)
const POSITIONS = [
  { id: 'member', label: 'Regular Musician', role: 'member', title: null, color: 'slate', badge: 'Musician' },
  { id: 'majorette', label: 'Majorette', role: 'member', title: null, color: 'rose', badge: 'Majorette' },
  { id: 'flag_bearer', label: 'Color Guard / Flag', role: 'member', title: null, color: 'pink', badge: 'Color Guard' },
  { id: 'president', label: 'Band President', role: 'executive', title: 'president', color: 'amber', badge: 'Band President' },
  { id: 'vice_president', label: 'Band Vice President', role: 'executive', title: 'vice_president', color: 'amber', badge: 'Band Vice President' },
  { id: 'secretary', label: 'Band Secretary', role: 'secretary_admin', title: null, color: 'indigo', badge: 'Band Secretary' },
  { id: 'treasurer', label: 'Band Treasurer', role: 'executive', title: 'treasurer', color: 'emerald', badge: 'Band Treasurer' },
  { id: 'auditor', label: 'Band Auditor', role: 'executive', title: 'auditor', color: 'purple', badge: 'Band Auditor' },
  { id: 'resident_conductor', label: 'Resident Conductor', role: 'executive', title: 'resident_conductor', color: 'amber', badge: 'Resident Conductor' },
  { id: 'band_manager', label: 'Band Manager', role: 'executive', title: 'band_manager', color: 'cyan', badge: 'Band Manager' },
  { id: 'coordinator', label: 'Band Coordinator', role: 'executive', title: 'coordinator', color: 'teal', badge: 'Band Coordinator' },
  { id: 'super_admin', label: 'IT Super Admin', role: 'super_admin', title: null, color: 'rose', badge: 'IT Super Admin' }
]

// HIERARCHICAL EXECUTIVE OFFICER POSTS (Pinned Leadership at top)
const leadershipPosts = [
  { key: 'president', title: 'Band President' },
  { key: 'vice_president', title: 'Band Vice President' },
  { key: 'secretary', title: 'Band Secretary' },
  { key: 'treasurer', title: 'Band Treasurer' },
  { key: 'auditor', title: 'Band Auditor' },
  { key: 'resident_conductor', title: 'Resident Conductor' },
  { key: 'band_manager', title: 'Band Manager' },
  { key: 'coordinator', title: 'Band Coordinator' }
]

// FULL INSTRUMENT LIST
const instrumentList = [
  'Clarinet', 
  'Bass Clarinet',
  'Flute', 
  'Piccolo',
  'French Horn', 
  'Tenor Sax',
  'Alto Sax', 
  'Baritone Sax',
  'Trumpet', 
  'Trombone', 
  'Bass Trombone',
  'Baritone / Euphonium', 
  'Bass / Tuba', 
  'Bass Drum',
  'Snare Drum', 
  'Cymbals',
  'Majorette',
  'Color Guard / Flag'
]

const showToast = (msg, type = 'info') => {
  uiStore.addToast({
    title: 'Directory Update',
    message: msg,
    type: type === 'error' ? 'error' : msg.startsWith('✓') ? 'success' : 'info'
  })
}

// TITLE NORMALIZER
const normalizeTitle = (str) => {
  if (!str) return ''
  const s = str.toLowerCase().trim()
  if (s.includes('majorette')) return 'majorette'
  if (s.includes('flag') || s.includes('guard')) return 'flag_bearer'
  if (s.includes('vice')) return 'vice_president'
  if (s.includes('pres')) return 'president'
  if (s.includes('sec')) return 'secretary'
  if (s.includes('treas')) return 'treasurer'
  if (s.includes('audit')) return 'auditor'
  if (s.includes('conduct')) return 'resident_conductor'
  if (s.includes('manag')) return 'band_manager'
  if (s.includes('coord')) return 'coordinator'
  return s.replace(/\s+/g, '_')
}

// GET THE UNIFIED POSITION ID FOR ANY MEMBER
const getMemberPositionId = (member) => {
  if (member.role === 'super_admin') return 'super_admin'
  if (member.role === 'secretary_admin') return 'secretary'
  const t = normalizeTitle(member.executive_title)
  if (t === 'president') return 'president'
  if (t === 'vice_president') return 'vice_president'
  if (t === 'treasurer') return 'treasurer'
  if (t === 'auditor') return 'auditor'
  if (t === 'resident_conductor') return 'resident_conductor'
  if (t === 'band_manager') return 'band_manager'
  if (t === 'coordinator') return 'coordinator'
  if (t === 'majorette' || (member.instrument || '').toLowerCase().includes('majorette')) return 'majorette'
  if (t === 'flag_bearer' || (member.instrument || '').toLowerCase().includes('flag') || (member.instrument || '').toLowerCase().includes('guard')) return 'flag_bearer'
  return 'member'
}

const getMemberPosition = (member) => {
  const posId = getMemberPositionId(member)
  return POSITIONS.find(p => p.id === posId) || POSITIONS[0]
}

// "PA-IMPORTANTE" LOW RELIABILITY LIST (< 85%)
const paImportanteList = computed(() => {
  return members.value.filter(m => (m.reliability || 100) < 85)
})

// PINNED ACTIVE EXECUTIVE OFFICERS (ONLY APPOINTED OFFICERS - NO BLANK TABS)
const pinnedLeadership = computed(() => {
  return leadershipPosts
    .map(post => {
      const officer = members.value.find(m => {
        const pId = getMemberPositionId(m)
        return pId === post.key
      })
      return {
        ...post,
        officer: officer || null
      }
    })
    .filter(p => p.officer !== null)
})

// FILTERED MEMBERS
const filteredMembers = computed(() => {
  return members.value.filter(member => {
    // Search query match
    const q = searchQuery.value.toLowerCase().trim()
    if (q) {
      const pos = getMemberPosition(member)
      const matches = 
        (member.name && member.name.toLowerCase().includes(q)) ||
        (member.instrument && member.instrument.toLowerCase().includes(q)) ||
        pos.label.toLowerCase().includes(q)
      if (!matches) return false
    }

    // Section filter
    if (activeSectionFilter.value !== 'All') {
      const filterKey = activeSectionFilter.value.toLowerCase()
      if (!member.instrument || !member.instrument.toLowerCase().includes(filterKey)) {
        return false
      }
    }

    // Tier filter
    if (activeTierFilter.value === 'officers') {
      const pId = getMemberPositionId(member)
      if (pId === 'member') return false
    } else if (activeTierFilter.value === 'senior') {
      if (member.rank !== 'Senior') return false
    } else if (activeTierFilter.value === 'junior') {
      if (member.rank !== 'Junior') return false
    }

    return true
  })
})

// SORTED ROSTER (IT Admin -> Officers -> Senior -> Junior -> Alphabetical)
const sortedRoster = computed(() => {
  const getPriority = (m) => {
    const pId = getMemberPositionId(m)
    if (pId === 'super_admin') return 1
    if (pId === 'president') return 2
    if (pId === 'vice_president') return 3
    if (pId === 'secretary') return 4
    if (pId === 'treasurer') return 5
    if (pId === 'auditor') return 6
    if (pId === 'resident_conductor') return 7
    if (pId === 'band_manager') return 8
    if (m.rank === 'Senior') return 9
    return 10
  }

  return [...filteredMembers.value].sort((a, b) => {
    const pA = getPriority(a)
    const pB = getPriority(b)
    if (pA !== pB) return pA - pB
    return (a.name || '').localeCompare(b.name || '')
  })
})

// PAGINATION STATE (Item 30: Server-side paging 50/page)
const PAGE_SIZE = 50
const currentPage = ref(0)
const hasMoreMembers = ref(false)
const isLoadingMore = ref(false)

// FETCH ROSTER
const fetchRoster = async (skipCache = false) => {
  if (!skipCache) {
    isLoading.value = true
    loadError.value = null
    const cached = localStorage.getItem('smartband_members_roster_cache')
    if (cached) {
      try { members.value = JSON.parse(cached) } catch (e) {}
    }
  }

  currentPage.value = 0
  try {
    const { data, error, count } = await supabase
      .from('profiles')
      .select('*', { count: 'exact' })
      .eq('is_verified', true)
      .order('full_name', { ascending: true })
      .range(0, PAGE_SIZE - 1)

    if (error) throw error

    if (data) {
      members.value = data.map(m => ({
        id: m.id,
        name: m.full_name || 'Unnamed Musician',
        instrument: m.instrument || 'Clarinet',
        rank: m.rank || 'Junior',
        role: m.role || 'member',
        executive_title: m.executive_title || null,
        reliability: m.reliability_score ?? 100,
        contact: m.contact_number || m.email || '',
        avatar: m.full_name ? m.full_name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase() : 'MB',
        profile_picture: m.profile_picture || null
      }))

      hasMoreMembers.value = (count ? members.value.length < count : data.length === PAGE_SIZE)
      localStorage.setItem('smartband_members_roster_cache', JSON.stringify(members.value))
    }
  } catch (err) {
    console.error('Error fetching roster:', err)
    loadError.value = 'Failed to load member roster from server. Please verify your connection.'
  } finally {
    isLoading.value = false
  }
}

const loadMoreMembers = async () => {
  if (isLoadingMore.value || !hasMoreMembers.value) return
  isLoadingMore.value = true
  try {
    const nextPage = currentPage.value + 1
    const from = nextPage * PAGE_SIZE
    const to = from + PAGE_SIZE - 1
    const { data, error, count } = await supabase
      .from('profiles')
      .select('*', { count: 'exact' })
      .eq('is_verified', true)
      .order('full_name', { ascending: true })
      .range(from, to)

    if (error) throw error
    if (data && data.length > 0) {
      const newItems = data.map(m => ({
        id: m.id,
        name: m.full_name || 'Unnamed Musician',
        instrument: m.instrument || 'Clarinet',
        rank: m.rank || 'Junior',
        role: m.role || 'member',
        executive_title: m.executive_title || null,
        reliability: m.reliability_score ?? 100,
        contact: m.contact_number || m.email || '',
        avatar: m.full_name ? m.full_name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase() : 'MB',
        profile_picture: m.profile_picture || null
      }))
      members.value = [...members.value, ...newItems]
      currentPage.value = nextPage
      hasMoreMembers.value = (count ? members.value.length < count : data.length === PAGE_SIZE)
      localStorage.setItem('smartband_members_roster_cache', JSON.stringify(members.value))
    } else {
      hasMoreMembers.value = false
    }
  } catch (err) {
    console.error('Error loading more members:', err)
  } finally {
    isLoadingMore.value = false
  }
}

// SINGLE OFFICER HOLDER HELPERS
const getOfficerHolder = (posId) => {
  if (['member', 'majorette', 'flag_bearer', 'super_admin'].includes(posId)) return null
  return members.value.find(m => getMemberPositionId(m) === posId)
}

const getOfficerHolderText = (posId) => {
  const holder = getOfficerHolder(posId)
  if (!holder) return ''
  if (editingMember.value && holder.id === editingMember.value.id) return ' (Currently this member)'
  return ` (Held by: ${holder.name})`
}

const currentHolderWarning = computed(() => {
  if (!editingMember.value || !managePositionId.value) return ''
  const holder = getOfficerHolder(managePositionId.value)
  if (holder && holder.id !== editingMember.value.id) {
    return `Note: This post is currently held by ${holder.name}. Saving will assign this post here and return ${holder.name} to Musician.`
  }
  return ''
})

// OPEN MANAGE MUSICIAN MODAL (SUPER ADMIN)
const openManageModal = (member) => {
  editingMember.value = member
  managePositionId.value = getMemberPositionId(member)
  manageInstrument.value = member.instrument || 'Clarinet'
  manageRank.value = member.rank || 'Junior'
  showManageModal.value = true
}

// SAVE MUSICIAN MANAGEMENT CHANGES (ALL-IN-ONE CLEAN HANDLER)
const saveMemberManagement = async () => {
  if (!editingMember.value) return
  isSavingManage.value = true

  const member = editingMember.value
  const newPos = POSITIONS.find(p => p.id === managePositionId.value) || POSITIONS[0]
  let newInst = manageInstrument.value
  const newRk = manageRank.value

  if (newPos.id === 'majorette' && !newInst.toLowerCase().includes('majorette')) {
    newInst = 'Majorette'
  } else if (newPos.id === 'flag_bearer' && !newInst.toLowerCase().includes('flag')) {
    newInst = 'Color Guard / Flag'
  }

  const execTitleToSave = newPos.role === 'executive' ? newPos.title : null

  try {
    // 1. Single Officer Enforcement: Clear previous holder if officer post
    const isOfficerPost = ['president', 'vice_president', 'secretary', 'treasurer', 'auditor', 'resident_conductor', 'band_manager', 'coordinator'].includes(newPos.id)
    if (isOfficerPost) {
      const prevHolder = members.value.find(m => m.id !== member.id && getMemberPositionId(m) === newPos.id)
      if (prevHolder) {
        prevHolder.executive_title = null
        prevHolder.role = 'member'
        await supabase.from('profiles').update({ executive_title: null, role: 'member' }).eq('id', prevHolder.id)
      }
    }

    // 2. Immediate reactive update in memory for 0ms UI feedback
    member.role = newPos.role
    member.executive_title = execTitleToSave
    member.instrument = newInst
    member.rank = newRk
    members.value = [...members.value]

    // 3. Persist to Supabase
    const { error } = await supabase
      .from('profiles')
      .update({
        role: newPos.role,
        executive_title: execTitleToSave,
        instrument: newInst,
        rank: newRk
      })
      .eq('id', member.id)

    if (error) throw error

    showToast(`✓ Updated ${member.name} (${newPos.label} • ${newInst} • ${newRk}).`)
    showManageModal.value = false
    await broadcastSync('account_status_changed', { userId: member.id })
    await fetchRoster(true)
  } catch (err) {
    console.error('Error saving member changes:', err)
    if (err?.code === '22P02') {
      showToast('Database Notice: Please run supabase/comprehensive_fix.sql in Supabase SQL Editor to update role enums.')
    } else {
      showToast(`Error: ${err?.message || 'Failed to save changes.'}`)
    }
    await fetchRoster(true)
  } finally {
    isSavingManage.value = false
  }
}

// DELETE MEMBER ACCOUNT (SUPER ADMIN)
const promptDeleteMember = (member) => {
  confirmDeleteTarget.value = member
  showDeleteModal.value = true
}

const executeDeleteMember = async () => {
  if (!confirmDeleteTarget.value) return
  const target = confirmDeleteTarget.value

  try {
    try {
      await supabase.rpc('delete_user_account', { target_user_id: target.id })
    } catch (rpcErr) {
      console.warn('RPC delete member fallback notice:', rpcErr)
    }

    const { data, error } = await supabase
      .from('profiles')
      .delete()
      .eq('id', target.id)
      .select()

    if (error) throw error
    if (!data || data.length === 0) {
      throw new Error('Database permission denied. Only Super Admin can delete member accounts.')
    }

    members.value = members.value.filter(m => m.id !== target.id)
    showToast(`Permanently deleted ${target.name}.`)
    await broadcastSync('account_status_changed', { userId: target.id })
    if (showManageModal.value && editingMember.value?.id === target.id) {
      showManageModal.value = false
    }
  } catch (err) {
    console.error('Delete member error:', err)
    showToast(`Failed to delete member: ${err.message || 'Database error'}`)
  } finally {
    showDeleteModal.value = false
    confirmDeleteTarget.value = null
  }
}

// VIEW MEMBER AVAILABILITY
const openAvailabilityView = async (member) => {
  selectedMemberForAvailability.value = member
  showAvailabilityModal.value = true
  memberAvailabilitySlots.value = []
  isLoadingAvailability.value = true

  try {
    const { data, error } = await supabase
      .from('member_availability')
      .select('*')
      .eq('user_id', member.id)

    if (error) throw error

    if (data && data.length > 0) {
      const freeSlots = data.filter(d => d.is_free !== false && d.is_available !== false)
      const dayOrder = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
      const sorted = [...freeSlots].sort((a, b) => {
        const idxA = dayOrder.indexOf((a.day_of_week || '').toLowerCase())
        const idxB = dayOrder.indexOf((b.day_of_week || '').toLowerCase())
        return idxA - idxB
      })

      memberAvailabilitySlots.value = sorted.map(d => {
        const rawDay = d.day_of_week || ''
        const day = rawDay ? rawDay.charAt(0).toUpperCase() + rawDay.slice(1).toLowerCase() : 'Any Day'
        return `${day} • ${d.time_slot || 'All Day'}`
      })
    }
  } catch (err) {
    console.error('Availability fetch error:', err)
  } finally {
    isLoadingAvailability.value = false
  }
}

let cleanupSync = null
let autoSyncTimer = null

const onWindowFocus = () => {
  fetchRoster(true)
}

onMounted(() => {
  fetchRoster()

  // 1. Centralized Master Realtime Sync (WebSockets + Inter-Tab)
  cleanupSync = initRealtimeSync(() => {
    fetchRoster(true)
  })

  window.addEventListener('focus', onWindowFocus)

  // 2. Mobile-optimized auto-poll fallback (pauses in background to save battery/CPU)
  autoSyncTimer = setInterval(() => {
    if (typeof document !== 'undefined' && !document.hidden) {
      fetchRoster(true)
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
  window.removeEventListener('focus', onWindowFocus)
})
</script>

<template>
  <div class="space-y-6 max-w-[1200px] mx-auto">
    
    <!-- Top Header -->
    <header class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pb-4 border-b border-[var(--md-outline-variant)]/40">
      <div>
        <div class="flex items-center space-x-2">
          <span class="text-xs font-medium text-[var(--md-on-surface-variant)]">
            {{ store.isOfficerOrAdmin ? 'Band Directory & Ranks' : 'Band Directory' }}
          </span>
          <span v-if="store.isSuperAdmin" class="m3-chip m3-chip-urgent h-6 px-2.5 text-xs font-semibold">
            Admin
          </span>
          <span v-else-if="store.isOfficerOrAdmin" class="m3-chip m3-chip-rsvp h-6 px-2.5 text-xs font-semibold">
            Officer
          </span>
        </div>
        <h1 class="text-2xl font-bold text-[var(--md-on-surface)] tracking-tight">
          Musician Registry
        </h1>
        <p v-if="!store.isOfficerOrAdmin" class="text-xs text-[var(--md-on-surface-variant)] font-normal">
          Official roster of band members and instrument sections.
        </p>
      </div>

      <div class="flex items-center space-x-2">
        <RouterLink 
          to="/dashboard/leaderboard"
          class="m3-btn-outlined min-h-[44px] text-xs font-semibold px-4 flex items-center space-x-1.5 cursor-pointer"
        >
          <Award class="w-4 h-4 text-amber-500" />
          <span>Reliability &amp; Ranks</span>
        </RouterLink>
        <span class="m3-chip m3-chip-assist h-11 text-xs px-3.5 font-semibold rounded-full">
          {{ members.length }} Musicians
        </span>
      </div>
    </header>

    <!-- 1. PINNED ACTIVE EXECUTIVE OFFICERS (ONLY CURRENTLY APPOINTED OFFICERS) -->
    <section v-if="pinnedLeadership.length > 0" class="space-y-3" aria-label="Band Officers">
      <div class="flex items-center justify-between px-1">
        <div class="flex items-center space-x-2">
          <ShieldCheck class="w-4 h-4 text-amber-800 dark:text-amber-400" />
          <h2 class="text-xs font-semibold text-[var(--md-on-surface)]">
            Band Officers
          </h2>
        </div>
        <span class="text-[11px] font-medium text-[var(--md-on-surface-variant)]">
          {{ pinnedLeadership.length }} Active {{ pinnedLeadership.length === 1 ? 'Officer' : 'Officers' }}
        </span>
      </div>

      <!-- Responsive Grid for Active Officers -->
      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3.5">
        <div 
          v-for="pos in pinnedLeadership" 
          :key="pos.key"
          class="m3-card-elevated p-4 border border-[var(--md-outline-variant)]/40 shadow-xs flex flex-col justify-between"
        >
          <div>
            <!-- Officer Title Badge (Subtle M3 Tonal Chip) -->
            <div class="flex items-center justify-between gap-2 mb-3">
              <span class="m3-chip m3-chip-rsvp h-7 text-xs px-3">
                <ShieldCheck class="w-3.5 h-3.5 mr-1 text-amber-800 dark:text-amber-400" />
                {{ pos.title }}
              </span>
              <span class="m3-chip m3-chip-info h-6 text-xs px-2.5 font-semibold">
                Active
              </span>
            </div>

            <!-- Officer Profile Details -->
            <div class="flex items-start space-x-3">
              <div class="w-12 h-12 rounded-full overflow-hidden flex-shrink-0 border border-[var(--md-outline-variant)] bg-[var(--md-surface-container)] text-[var(--md-on-surface)] flex items-center justify-center font-bold text-sm">
                <img v-if="pos.officer.profile_picture" :src="pos.officer.profile_picture" :alt="pos.officer.name" width="48" height="48" loading="lazy" class="w-full h-full object-cover" />
                <span v-else>{{ pos.officer.avatar }}</span>
              </div>
              <div class="min-w-0 flex-1">
                <h3 class="font-bold text-sm text-[var(--md-on-surface)] truncate leading-tight">
                  {{ pos.officer.name }}
                </h3>
                <p class="text-xs text-[var(--md-on-surface-variant)] flex items-center mt-1 truncate capitalize font-medium">
                  <Music class="w-3.5 h-3.5 mr-1 text-[var(--md-outline)] shrink-0" />
                  {{ pos.officer.instrument }}
                </p>
                <!-- Only visible to Officers & Admins -->
                <div v-if="store.isOfficerOrAdmin" class="flex items-center space-x-1.5 mt-2">
                  <span class="m3-chip m3-chip-neutral h-6 text-xs px-2.5">
                    {{ pos.officer.rank }}
                  </span>
                  <span class="text-[10px] font-semibold text-[var(--md-on-surface-variant)]">
                    {{ pos.officer.reliability }}% Score
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!-- Bottom Actions (Only for Officers & Admins) -->
          <div v-if="store.isOfficerOrAdmin" class="pt-3 mt-3 border-t border-[var(--md-outline-variant)]/30 flex items-center justify-between">
            <button 
              @click="openAvailabilityView(pos.officer)"
              type="button"
              class="m3-btn-text text-xs font-semibold px-2.5 min-h-[44px] flex items-center text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]"
            >
              <Calendar class="w-3.5 h-3.5 mr-1" /> Availability
            </button>

            <button 
              v-if="store.isSuperAdmin"
              @click="openManageModal(pos.officer)"
              type="button"
              class="m3-btn-text text-xs font-semibold px-2.5 min-h-[44px] flex items-center text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]"
            >
              <Settings class="w-3.5 h-3.5 mr-1" /> Manage
            </button>
          </div>
        </div>
      </div>
    </section>

    <!-- 2. ATTENDANCE BEHAVIOR REVIEW (< 85%) -->
    <section v-if="store.canPromoteMembers && paImportanteList.length > 0" class="bg-[var(--md-surface-container)] border border-rose-500/30 rounded-2xl p-4 sm:p-5 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2 text-rose-600 dark:text-rose-400">
          <UserX class="w-4 h-4" />
          <h2 class="font-semibold text-xs sm:text-sm">Attendance Review (Frequent Absences)</h2>
        </div>
        <span class="m3-chip m3-chip-urgent h-7 text-xs px-3 font-semibold">
          {{ paImportanteList.length }} Below 85%
        </span>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2.5">
        <div 
          v-for="item in paImportanteList" 
          :key="item.id" 
          class="bg-[var(--md-surface)] p-3 rounded-2xl border border-[var(--md-outline-variant)]/60 flex items-center justify-between shadow-xs"
        >
          <div class="flex items-center space-x-2.5 min-w-0 pr-2">
            <div class="w-8 h-8 rounded-full bg-rose-500/15 text-rose-600 dark:text-rose-400 font-bold text-xs flex items-center justify-center shrink-0">
              {{ item.avatar }}
            </div>
            <div class="min-w-0">
              <p class="font-semibold text-xs text-[var(--md-on-surface)] truncate">{{ item.name }}</p>
              <p class="text-[10px] text-rose-600 dark:text-rose-400 font-semibold">{{ item.reliability }}% • {{ item.instrument }}</p>
            </div>
          </div>
          <button 
            v-if="store.isSuperAdmin"
            @click="openManageModal(item)"
            type="button"
            class="m3-btn-tonal text-xs min-h-[44px] px-4 font-semibold shrink-0"
          >
            Manage
          </button>
        </div>
      </div>
    </section>

    <!-- 3. SEARCH & DYNAMIC FILTER BAR (Material 3 Search Bar) -->
    <div class="flex flex-col md:flex-row items-stretch md:items-center justify-between gap-3">
      <!-- Search Input -->
      <div class="relative flex-1 max-w-md">
        <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-[var(--md-outline)]">
          <Search class="w-4 h-4" />
        </div>
        <input 
          v-model="searchQuery"
          type="text" 
          placeholder="Search by name or instrument..."
          class="w-full pl-10 pr-4 py-2 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-full text-[var(--md-on-surface)] placeholder-[var(--md-outline)] text-xs font-normal shadow-xs min-h-[48px] focus:outline-none focus:border-[var(--md-outline)]"
        />
      </div>

      <!-- Quick Category Pills (Responsive Wrapping) -->
      <div class="flex flex-wrap items-center gap-2">
        <!-- Instrument Section Dropdown -->
        <select 
          v-model="activeSectionFilter" 
          class="bg-[var(--md-surface-container)] text-[var(--md-on-surface)] font-medium text-xs rounded-full px-4 py-2 border border-[var(--md-outline-variant)] shadow-xs min-h-[48px] cursor-pointer shrink-0 focus:outline-none"
        >
          <option value="All">All Sections</option>
          <option v-for="sec in instrumentList" :key="sec" :value="sec">{{ sec }}</option>
        </select>

        <!-- Tier Filter Buttons (Senior/Junior filtered for officers only) -->
        <div v-if="store.isOfficerOrAdmin" class="flex rounded-full bg-[var(--md-surface-container)] p-1 text-xs font-medium border border-[var(--md-outline-variant)]/60 shrink-0">
          <button 
            type="button" 
            @click="activeTierFilter = 'all'"
            class="px-3.5 py-1.5 rounded-full transition-all cursor-pointer min-h-[40px]"
            :class="activeTierFilter === 'all' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            All
          </button>
          <button 
            type="button" 
            @click="activeTierFilter = 'officers'"
            class="px-3.5 py-1.5 rounded-full transition-all cursor-pointer min-h-[40px]"
            :class="activeTierFilter === 'officers' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Officers
          </button>
          <button 
            type="button" 
            @click="activeTierFilter = 'senior'"
            class="px-3.5 py-1.5 rounded-full transition-all cursor-pointer min-h-[40px]"
            :class="activeTierFilter === 'senior' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Senior
          </button>
          <button 
            type="button" 
            @click="activeTierFilter = 'junior'"
            class="px-3.5 py-1.5 rounded-full transition-all cursor-pointer min-h-[40px]"
            :class="activeTierFilter === 'junior' ? 'bg-[var(--md-surface)] text-[var(--md-on-surface)] shadow-xs font-semibold' : 'text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)]'"
          >
            Junior
          </button>
        </div>
      </div>
    </div>

    <!-- 4. CLEAN, HIGH-CONTRAST MUSICIAN DIRECTORY (DESKTOP / TABLET TABLE) -->
    <section class="space-y-3" aria-label="Musician Directory Roster">
      <div class="flex items-center justify-between px-1">
        <span class="text-xs font-semibold text-[var(--md-on-surface)]">
          Master Directory ({{ sortedRoster.length }})
        </span>
        <span v-if="sortedRoster.length > 10" class="text-[10px] text-[var(--md-outline)]">
          Scrollable table enabled
        </span>
      </div>

      <!-- 1. Skeleton Loading State (Item 20) -->
      <div v-if="isLoading" class="m3-card-outlined p-5 space-y-4">
        <div v-for="i in 5" :key="i" class="flex items-center justify-between animate-pulse py-2">
          <div class="flex items-center space-x-3 flex-1">
            <div class="w-10 h-10 rounded-full bg-slate-200 dark:bg-neutral-800 shrink-0"></div>
            <div class="space-y-1.5 flex-1">
              <div class="h-4 bg-slate-200 dark:bg-neutral-800 rounded w-1/3"></div>
              <div class="h-3 bg-slate-200 dark:bg-neutral-800 rounded w-1/4"></div>
            </div>
          </div>
          <div class="h-6 w-20 bg-slate-200 dark:bg-neutral-800 rounded-full"></div>
        </div>
      </div>

      <!-- 2. Error State with Retry CTA (Item 21) -->
      <div v-else-if="loadError" class="m3-card-outlined p-8 text-center space-y-3 border-rose-300 dark:border-rose-900/50">
        <AlertCircle class="w-8 h-8 text-rose-600 dark:text-rose-400 mx-auto" />
        <h3 class="text-sm font-bold text-slate-900 dark:text-neutral-100">Unable to Load Musician Directory</h3>
        <p class="text-xs text-slate-600 dark:text-neutral-400 max-w-sm mx-auto">{{ loadError }}</p>
        <button @click="fetchRoster(true)" type="button" class="m3-btn-filled text-xs min-h-[40px] px-5 inline-flex items-center mx-auto">
          <RefreshCw class="w-3.5 h-3.5 mr-1.5" /> Retry Connection
        </button>
      </div>

      <!-- 3. Roster Present (Desktop + Mobile) -->
      <div v-else-if="sortedRoster.length > 0">
        <!-- DESKTOP / TABLET VIEW (TABLE WITH HORIZONTAL OVERFLOW SCROLLING) -->
        <div 
          class="hidden md:block m3-card-outlined overflow-hidden border border-[var(--md-outline-variant)]/60 rounded-2xl"
          :class="sortedRoster.length > 10 ? 'max-h-[560px] overflow-y-auto' : ''"
        >
        <table class="w-full text-left border-collapse text-xs">
          <!-- Sticky Header (Table 4: 48px Header Height) -->
          <thead class="sticky top-0 bg-[var(--md-surface-container)] border-b border-[var(--md-outline-variant)]/40 z-10 font-semibold text-[var(--md-on-surface-variant)] text-xs h-12">
            <tr>
              <th scope="col" class="py-3 px-4">Musician</th>
              <th scope="col" class="py-3 px-4">Section / Instrument</th>
              <th scope="col" class="py-3 px-4">Role</th>
              <th v-if="store.isOfficerOrAdmin" scope="col" class="py-3 px-4">Rank</th>
              <th v-if="store.isOfficerOrAdmin" scope="col" class="py-3 px-4">Reliability</th>
              <th v-if="store.isOfficerOrAdmin" scope="col" class="py-3 px-4 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[var(--md-outline-variant)]/30">
            <tr 
              v-for="member in sortedRoster" 
              :key="member.id"
              class="transition-colors hover:bg-[var(--md-surface-container)]/50 min-h-[48px]"
            >
              <!-- Musician Name & Avatar -->
              <td class="py-3.5 px-4">
                <div class="flex items-center space-x-3">
                  <div class="w-9 h-9 rounded-full overflow-hidden flex-shrink-0 border border-[var(--md-outline-variant)] bg-[var(--md-surface-container)] text-[var(--md-on-surface)] flex items-center justify-center font-bold text-xs">
                    <img v-if="member.profile_picture" :src="member.profile_picture" :alt="member.name" width="36" height="36" loading="lazy" class="w-full h-full object-cover" />
                    <span v-else>{{ member.avatar }}</span>
                  </div>
                  <div class="min-w-0">
                    <span class="font-semibold text-[var(--md-on-surface)] text-xs truncate block">
                      {{ member.name }}
                    </span>
                    <span v-if="store.isOfficerOrAdmin" class="text-[11px] text-[var(--md-on-surface-variant)] truncate block">
                      {{ member.contact || 'Registered Member' }}
                    </span>
                    <span v-else class="text-[11px] text-[var(--md-on-surface-variant)] truncate block">
                      Verified Member
                    </span>
                  </div>
                </div>
              </td>

              <!-- Section / Instrument -->
              <td class="py-3.5 px-4">
                <span class="m3-chip m3-chip-neutral h-7 text-xs px-3 inline-flex items-center capitalize">
                  <Music class="w-3.5 h-3.5 mr-1 text-[var(--md-outline)]" />
                  {{ member.instrument }}
                </span>
              </td>

              <!-- Unified Position / Officer Role Badge -->
              <td class="py-3.5 px-4">
                <span 
                  v-if="getMemberPositionId(member) === 'super_admin'" 
                  class="m3-chip m3-chip-urgent h-7 text-xs px-3 inline-flex items-center font-semibold"
                >
                  <ShieldCheck class="w-3.5 h-3.5 mr-1" /> Super Admin
                </span>
                <span 
                  v-else-if="getMemberPositionId(member) !== 'member'" 
                  class="m3-chip m3-chip-rsvp h-7 text-xs px-3 inline-flex items-center font-semibold"
                >
                  <ShieldCheck class="w-3.5 h-3.5 mr-1 text-amber-800 dark:text-amber-400" /> {{ getMemberPosition(member).badge }}
                </span>
                <span 
                  v-else 
                  class="m3-chip m3-chip-assist h-7 text-xs px-3 inline-flex items-center font-normal"
                >
                  Musician
                </span>
              </td>

              <!-- Rank (Officers & Admins Only) -->
              <td v-if="store.isOfficerOrAdmin" class="py-3.5 px-4">
                <span 
                  class="m3-chip m3-chip-neutral h-7 text-xs px-3 inline-flex items-center"
                >
                  <Award class="w-3.5 h-3.5 mr-1 text-[var(--md-outline)]" /> {{ member.rank }}
                </span>
              </td>

              <!-- Reliability (Officers & Admins Only) -->
              <td v-if="store.isOfficerOrAdmin" class="py-3.5 px-4">
                <div class="flex items-center space-x-1.5">
                  <span 
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    :class="member.reliability >= 90 ? 'bg-emerald-500' : member.reliability >= 80 ? 'bg-blue-500' : 'bg-rose-500'"
                  ></span>
                  <span class="font-semibold text-xs text-[var(--md-on-surface)]">
                    {{ member.reliability }}%
                  </span>
                </div>
              </td>

              <!-- Actions (Officers & Admins Only) -->
              <td v-if="store.isOfficerOrAdmin" class="py-3.5 px-4 text-right">
                <div class="flex items-center justify-end space-x-1.5">
                  <!-- View Availability -->
                  <button 
                    @click="openAvailabilityView(member)"
                    type="button"
                    class="p-2 text-[var(--md-on-surface-variant)] hover:text-[var(--md-on-surface)] hover:bg-[var(--md-surface-container)] rounded-full transition-colors cursor-pointer min-w-[44px] min-h-[44px] flex items-center justify-center"
                    title="View Weekly Availability"
                  >
                    <Calendar class="w-4 h-4" />
                  </button>

                  <!-- Super Admin Manage Button -->
                  <button 
                    v-if="store.isSuperAdmin"
                    @click="openManageModal(member)"
                    type="button"
                    class="m3-btn-filled text-xs min-h-[44px] px-4 font-semibold"
                  >
                    <Settings class="w-3.5 h-3.5 mr-1" /> Manage
                  </button>
                </div>
              </td>
            </tr>

            <tr v-if="sortedRoster.length === 0">
              <td :colspan="store.isOfficerOrAdmin ? 6 : 3" class="py-10 text-center text-[var(--md-outline)] font-medium">
                No musicians match your search or filter.
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- MOBILE VIEW: CLEAN MEMBER CARDS (Hidden on Desktop/Tablet) -->
      <div 
        class="block md:hidden space-y-3"
        :class="sortedRoster.length > 10 ? 'max-h-[540px] overflow-y-auto pr-1' : ''"
      >
        <div 
          v-for="member in sortedRoster" 
          :key="member.id"
          class="m3-card-elevated p-4 border border-[var(--md-outline-variant)]/40 rounded-2xl space-y-3"
        >
          <!-- Top Row: Musician Identity -->
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center space-x-3 min-w-0">
              <div class="w-10 h-10 rounded-full overflow-hidden flex-shrink-0 border border-[var(--md-outline-variant)] bg-[var(--md-surface-container)] text-[var(--md-on-surface)] flex items-center justify-center font-bold text-xs">
                <img v-if="member.profile_picture" :src="member.profile_picture" :alt="member.name" width="40" height="40" loading="lazy" class="w-full h-full object-cover" />
                <span v-else>{{ member.avatar }}</span>
              </div>
              <div class="min-w-0">
                <h3 class="font-bold text-sm text-[var(--md-on-surface)] truncate">
                  {{ member.name }}
                </h3>
                <div class="flex items-center space-x-1.5 mt-0.5 flex-wrap">
                  <span 
                    v-if="getMemberPositionId(member) !== 'member'" 
                    class="m3-chip m3-chip-rsvp h-6 text-xs px-2.5 font-semibold inline-flex items-center"
                  >
                    <ShieldCheck class="w-3 h-3 mr-1 text-amber-800 dark:text-amber-400" />
                    {{ getMemberPosition(member).badge }}
                  </span>
                  <span class="text-xs text-[var(--md-on-surface-variant)] capitalize font-medium">
                    {{ member.instrument }}
                  </span>
                </div>
              </div>
            </div>

            <!-- Rank & Reliability: Officers & Admins Only -->
            <div v-if="store.isOfficerOrAdmin" class="text-right shrink-0">
              <span class="m3-chip m3-chip-neutral h-6 text-xs px-2.5">
                {{ member.rank }}
              </span>
              <p class="text-[11px] font-semibold text-[var(--md-on-surface)] mt-1">{{ member.reliability }}%</p>
            </div>
          </div>

          <!-- Bottom Actions Bar (Officers & Admins Only) -->
          <div v-if="store.isOfficerOrAdmin" class="pt-2.5 border-t border-[var(--md-outline-variant)]/30 flex items-center justify-between">
            <button 
              @click="openAvailabilityView(member)"
              type="button"
              class="m3-btn-tonal text-xs font-semibold min-h-[44px] px-3.5 flex items-center"
            >
              <Calendar class="w-4 h-4 mr-1.5" /> Availability
            </button>

            <button 
              v-if="store.isSuperAdmin"
              @click="openManageModal(member)"
              type="button"
              class="m3-btn-filled text-xs font-semibold min-h-[44px] px-4 flex items-center"
            >
              <Settings class="w-3.5 h-3.5 mr-1.5" /> Manage
            </button>
          </div>
        </div>
      </div>

      <!-- Pagination: Server-side Load More (Item 30) -->
      <div v-if="hasMoreMembers" class="pt-4 text-center">
        <button 
          @click="loadMoreMembers" 
          :disabled="isLoadingMore"
          type="button" 
          class="m3-btn-outlined text-xs min-h-[40px] px-6 inline-flex items-center mx-auto"
        >
          <RefreshCw v-if="isLoadingMore" class="w-3.5 h-3.5 mr-1.5 animate-spin" />
          <span>{{ isLoadingMore ? 'Loading More Musicians...' : 'Load More Musicians (50)' }}</span>
        </button>
      </div>
      </div>

      <!-- 4. Empty State with CTA (Item 22) -->
      <div v-else class="m3-card-outlined p-8 text-center space-y-3">
        <div class="w-12 h-12 rounded-full bg-[var(--md-surface-container)] flex items-center justify-center mx-auto text-[var(--md-outline)]">
          <Users class="w-6 h-6" />
        </div>
        <div>
          <h3 class="text-sm font-bold text-[var(--md-on-surface)]">No Musicians Found</h3>
          <p class="text-xs text-[var(--md-on-surface-variant)] mt-1 max-w-sm mx-auto">
            {{ searchQuery || activeSectionFilter !== 'All' || activeTierFilter !== 'all' ? 'No musicians match your current search query or section filter.' : 'Verified band musicians will appear here once approved by Super Admin.' }}
          </p>
        </div>
        <button 
          v-if="searchQuery || activeSectionFilter !== 'All' || activeTierFilter !== 'all'"
          @click="searchQuery = ''; activeSectionFilter = 'All'; activeTierFilter = 'all'" 
          type="button" 
          class="m3-btn-filled text-xs min-h-[40px] px-5 inline-flex items-center mx-auto"
        >
          Reset Filters
        </button>
        <button 
          v-else 
          @click="fetchRoster(true)" 
          type="button" 
          class="m3-btn-outlined text-xs min-h-[40px] px-5 inline-flex items-center mx-auto"
        >
          <RefreshCw class="w-3.5 h-3.5 mr-1.5" /> Refresh Roster
        </button>
      </div>
    </section>

    <!-- 5. ALL-IN-ONE MUSICIAN MANAGEMENT MODAL (SUPER ADMIN ONLY) (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showManageModal && editingMember" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="manage-musician-modal-title"
      @keydown.escape="showManageModal = false"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4"
    >
      <div class="m3-surface-modal p-6 max-w-md w-full space-y-4 shadow-xl text-left max-h-[90vh] flex flex-col">
        
        <!-- Modal Header with Musician Info -->
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/40 pb-3">
          <div class="flex items-center space-x-3 min-w-0 pr-2">
            <div class="w-10 h-10 rounded-full overflow-hidden bg-[var(--md-surface-container)] text-[var(--md-on-surface)] flex items-center justify-center font-bold text-sm shrink-0 border border-[var(--md-outline-variant)]">
              <img v-if="editingMember.profile_picture" :src="editingMember.profile_picture" :alt="editingMember.name" width="40" height="40" loading="lazy" class="w-full h-full object-cover" />
              <span v-else>{{ editingMember.avatar }}</span>
            </div>
            <div class="min-w-0">
              <span class="text-[10px] text-[var(--md-outline)] uppercase tracking-wider font-semibold">Manage Musician</span>
              <h3 id="manage-musician-modal-title" class="font-bold text-base text-[var(--md-on-surface)] truncate">{{ editingMember.name }}</h3>
            </div>
          </div>
          <button @click="showManageModal = false" type="button" class="text-[var(--md-outline)] hover:text-[var(--md-on-surface)] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer rounded-full hover:bg-[var(--md-surface-container)]" aria-label="Close modal">
            <X class="w-5 h-5" />
          </button>
        </div>

        <!-- Modal Form Body -->
        <div class="space-y-4 overflow-y-auto flex-1 pr-1">
          
          <!-- UNIFIED ROLE & OFFICER POSITION SELECTOR -->
          <div>
            <label for="manage-position-select" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1 flex items-center">
              <ShieldCheck class="w-3.5 h-3.5 mr-1 text-amber-500" /> Position &amp; Officer Role
            </label>
            <select 
              id="manage-position-select"
              v-model="managePositionId"
              class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)] cursor-pointer"
            >
              <option v-for="pos in POSITIONS" :key="pos.id" :value="pos.id">
                {{ pos.label }}{{ getOfficerHolderText(pos.id) }}
              </option>
            </select>
            <p v-if="currentHolderWarning" class="text-[11px] text-amber-800 dark:text-amber-400 mt-1 font-medium flex items-center">
              <AlertCircle class="w-3 h-3 mr-1 shrink-0" />
              {{ currentHolderWarning }}
            </p>
            <p v-else class="text-[11px] text-[var(--md-on-surface-variant)] mt-1">
              Officer posts are single-officer appointments. Assigning a post automatically moves any previous holder back to Musician.
            </p>
          </div>

          <!-- INSTRUMENT SECTION -->
          <div>
            <label for="manage-instrument-select" class="block text-xs font-medium text-[var(--md-on-surface)] mb-1 flex items-center">
              <Music class="w-3.5 h-3.5 mr-1 text-[var(--md-outline)]" /> Instrument Section
            </label>
            <select 
              id="manage-instrument-select"
              v-model="manageInstrument"
              class="w-full p-3 bg-[var(--md-surface-container)] border border-[var(--md-outline-variant)] rounded-xl text-xs text-[var(--md-on-surface)] min-h-[48px] focus:outline-none focus:border-[var(--md-outline)] cursor-pointer"
            >
              <option v-for="sec in instrumentList" :key="sec" :value="sec">{{ sec }}</option>
            </select>
          </div>

          <!-- MUSICIAN RANK TOGGLE -->
          <div>
            <label class="block text-xs font-medium text-[var(--md-on-surface)] mb-1 flex items-center">
              <Award class="w-3.5 h-3.5 mr-1 text-[var(--md-outline)]" /> Musician Rank
            </label>
            <div class="grid grid-cols-2 gap-2">
              <button 
                type="button" 
                @click="manageRank = 'Junior'"
                class="py-2.5 px-3 rounded-full border text-xs font-semibold transition-all flex items-center justify-center cursor-pointer min-h-[44px]"
                :class="manageRank === 'Junior' 
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900 border-transparent shadow-xs' 
                  : 'bg-[var(--md-surface-container)] text-[var(--md-on-surface-variant)] border-[var(--md-outline-variant)]'"
              >
                Junior Rank
              </button>
              <button 
                type="button" 
                @click="manageRank = 'Senior'"
                class="py-2.5 px-3 rounded-full border text-xs font-semibold transition-all flex items-center justify-center cursor-pointer min-h-[44px]"
                :class="manageRank === 'Senior' 
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900 border-transparent shadow-xs' 
                  : 'bg-[var(--md-surface-container)] text-[var(--md-on-surface-variant)] border-[var(--md-outline-variant)]'"
              >
                Senior Rank
              </button>
            </div>
          </div>

          <!-- DANGER ZONE: DELETE ACCOUNT -->
          <div v-if="editingMember.role !== 'super_admin' && editingMember.id !== store.user?.id" class="pt-3 border-t border-[var(--md-outline-variant)]/40">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-xs font-semibold text-rose-600 dark:text-rose-400">Account Deletion</p>
                <p class="text-[11px] text-[var(--md-on-surface-variant)]">Permanently remove this musician from registry</p>
              </div>
              <button 
                @click="promptDeleteMember(editingMember)"
                type="button"
                class="m3-btn-outlined text-xs min-h-[44px] px-4 font-semibold text-rose-600 dark:text-rose-400 border-rose-300 dark:border-rose-900/50 hover:bg-rose-50 dark:hover:bg-rose-950/20"
              >
                Delete Account
              </button>
            </div>
          </div>

        </div>

        <!-- Modal Footer Actions -->
        <div class="flex space-x-2 pt-3 border-t border-[var(--md-outline-variant)]/40">
          <button 
            @click="showManageModal = false" 
            type="button" 
            class="m3-btn-outlined flex-1 min-h-[48px]"
          >
            Cancel
          </button>
          <button 
            @click="saveMemberManagement" 
            :disabled="isSavingManage"
            type="button" 
            class="m3-btn-filled flex-1 min-h-[48px] disabled:opacity-50"
          >
            {{ isSavingManage ? 'Saving...' : 'Save Changes' }}
          </button>
        </div>

      </div>
    </div>

    <!-- 6. MEMBER AVAILABILITY MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showAvailabilityModal" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="availability-modal-title"
      @keydown.escape="showAvailabilityModal = false"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4"
    >
      <div class="m3-surface-modal p-6 max-w-sm sm:max-w-md w-full space-y-4 shadow-xl text-left">
        <div class="flex items-center justify-between border-b border-[var(--md-outline-variant)]/40 pb-3">
          <div>
            <span class="text-[10px] text-[var(--md-outline)] uppercase tracking-wider font-semibold">Availability Overview</span>
            <h3 id="availability-modal-title" class="font-bold text-base text-[var(--md-on-surface)] truncate">{{ selectedMemberForAvailability?.name }}</h3>
          </div>
          <button @click="showAvailabilityModal = false" type="button" class="text-[var(--md-outline)] hover:text-[var(--md-on-surface)] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer rounded-full hover:bg-[var(--md-surface-container)]" aria-label="Close modal">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div class="space-y-3">
          <p class="text-xs text-[var(--md-on-surface-variant)]">
            Active weekly free slots registered by this musician:
          </p>

          <div v-if="isLoadingAvailability" class="py-6 text-center text-xs font-medium text-[var(--md-outline)]">
            Checking schedule...
          </div>

          <div v-else-if="memberAvailabilitySlots.length > 0" class="flex flex-wrap gap-1.5 max-h-48 overflow-y-auto pr-1">
            <span 
              v-for="slot in memberAvailabilitySlots" 
              :key="slot" 
              class="m3-chip m3-chip-info h-8 text-xs px-3 rounded-full font-medium"
            >
              ✓ {{ slot }}
            </span>
          </div>

          <div v-else class="p-4 bg-[var(--md-surface-container)] rounded-2xl text-center text-xs text-[var(--md-on-surface-variant)] font-medium space-y-1">
            <p>No active free slots registered for this week yet.</p>
            <p v-if="selectedMemberForAvailability?.id === store.user?.id" class="text-[11px] text-[var(--md-outline)]">
              You can set your weekly slots in Profile Settings.
            </p>
          </div>
        </div>

        <div class="pt-2">
          <button 
            @click="showAvailabilityModal = false" 
            type="button" 
            class="m3-btn-filled w-full min-h-[48px] text-xs font-semibold"
          >
            Close
          </button>
        </div>
      </div>
    </div>

    <!-- 7. SUPER ADMIN DELETE CONFIRMATION MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div 
      v-if="showDeleteModal" 
      role="dialog"
      aria-modal="true"
      aria-labelledby="delete-musician-modal-title"
      @keydown.escape="showDeleteModal = false; confirmDeleteTarget = null"
      class="fixed inset-0 m3-scrim-overlay z-50 flex items-center justify-center p-4"
    >
      <div class="m3-surface-modal p-6 max-w-sm w-full space-y-4 shadow-xl text-center">
        <div class="w-12 h-12 rounded-full bg-rose-500/15 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        
        <div>
          <h3 id="delete-musician-modal-title" class="font-bold text-base text-[var(--md-on-surface)] leading-tight">Delete Musician Account?</h3>
          <p class="text-xs text-[var(--md-on-surface-variant)] mt-1.5 leading-relaxed">
            Are you sure you want to permanently delete <strong class="text-[var(--md-on-surface)]">{{ confirmDeleteTarget?.name }}</strong>? This action cannot be undone.
          </p>
        </div>

        <div class="flex space-x-2 pt-2">
          <button 
            @click="showDeleteModal = false; confirmDeleteTarget = null" 
            type="button" 
            class="m3-btn-outlined flex-1 min-h-[48px]"
          >
            Cancel
          </button>
          <button 
            @click="executeDeleteMember" 
            type="button" 
            class="m3-btn-filled flex-1 min-h-[48px] bg-rose-600 hover:bg-rose-700 text-white"
          >
            Delete
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
</style>
