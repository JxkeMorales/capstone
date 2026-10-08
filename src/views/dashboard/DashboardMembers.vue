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
  Crown,
  Settings,
  SlidersHorizontal,
  ChevronRight,
  UserCheck,
  Star
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

// FETCH ROSTER
const fetchRoster = async (skipCache = false) => {
  if (!skipCache) {
    isLoading.value = true
    const cached = localStorage.getItem('smartband_members_roster_cache')
    if (cached) {
      try { members.value = JSON.parse(cached) } catch (e) {}
    }
  }

  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('is_verified', true)
      .order('full_name', { ascending: true })

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

      localStorage.setItem('smartband_members_roster_cache', JSON.stringify(members.value))
    }
  } catch (err) {
    console.error('Error fetching roster:', err)
  } finally {
    isLoading.value = false
  }
}

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
    // 1. Single Officer Enforcement: Clear previous holder in local memory & DB if leadership post
    const isLeadershipPost = ['president', 'vice_president', 'secretary', 'treasurer'].includes(newPos.id)
    if (isLeadershipPost) {
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
  <div class="space-y-6 max-w-7xl mx-auto">
    
    <!-- Top Header -->
    <header class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pb-4 border-b border-slate-200/80 dark:border-neutral-800">
      <div>
        <div class="flex items-center space-x-2">
          <span class="text-xs font-medium text-slate-500 dark:text-neutral-400">
            {{ store.isOfficerOrAdmin ? 'Band Directory & Ranks' : 'Band Directory' }}
          </span>
          <span v-if="store.isSuperAdmin" class="text-[10px] font-medium bg-rose-50 text-rose-700 dark:bg-rose-950/40 dark:text-rose-400 px-2.5 py-0.5 rounded-full border border-rose-200/60 dark:border-rose-900/40">
            Admin
          </span>
          <span v-else-if="store.isOfficerOrAdmin" class="text-[10px] font-medium bg-slate-100 dark:bg-neutral-800 text-slate-700 dark:text-neutral-300 px-2.5 py-0.5 rounded-full">
            Officer
          </span>
        </div>
        <h1 class="text-2xl font-bold text-slate-900 dark:text-white tracking-tight">
          Musician Registry
        </h1>
        <p v-if="!store.isOfficerOrAdmin" class="text-xs text-slate-500 dark:text-neutral-400 font-normal">
          Official roster of band members and instrument sections.
        </p>
      </div>

      <div class="flex items-center space-x-2">
        <RouterLink 
          to="/dashboard/leaderboard"
          class="text-xs font-medium text-slate-700 dark:text-neutral-200 bg-white dark:bg-[#202124] hover:bg-slate-50 dark:hover:bg-[#282a2c] px-3.5 py-1.5 rounded-full border border-slate-200 dark:border-neutral-800 shadow-xs flex items-center space-x-1.5 transition-colors cursor-pointer min-h-[36px]"
        >
          <Award class="w-3.5 h-3.5 text-amber-500" />
          <span>Reliability &amp; Ranks</span>
        </RouterLink>
        <span class="text-xs font-medium text-slate-600 dark:text-neutral-400 bg-white dark:bg-[#202124] px-3.5 py-1.5 rounded-full border border-slate-200 dark:border-neutral-800 shadow-xs">
          {{ members.length }} Musicians
        </span>
      </div>
    </header>

    <!-- 1. PINNED ACTIVE EXECUTIVE OFFICERS (ONLY CURRENTLY APPOINTED OFFICERS) -->
    <section v-if="pinnedLeadership.length > 0" class="space-y-3" aria-label="Band Leadership">
      <div class="flex items-center justify-between px-1">
        <div class="flex items-center space-x-2">
          <Crown class="w-4 h-4 text-amber-500" />
          <h2 class="text-xs font-semibold text-slate-700 dark:text-neutral-300">
            Band Leadership &amp; Executive Officers
          </h2>
        </div>
        <span class="text-[11px] font-medium text-slate-400 dark:text-neutral-500">
          {{ pinnedLeadership.length }} Active {{ pinnedLeadership.length === 1 ? 'Officer' : 'Officers' }}
        </span>
      </div>

      <!-- Responsive Grid for Active Officers -->
      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3.5">
        <div 
          v-for="pos in pinnedLeadership" 
          :key="pos.key"
          class="bg-white dark:bg-[#202124] rounded-3xl p-4 border border-slate-200/90 dark:border-neutral-800 shadow-xs flex flex-col justify-between"
        >
          <div>
            <!-- Officer Title Badge -->
            <div class="flex items-center justify-between gap-2 mb-3">
              <span class="text-[10px] font-medium px-2.5 py-0.5 rounded-full bg-slate-900 text-white dark:bg-white dark:text-slate-900 shadow-xs">
                {{ pos.title }}
              </span>
              <span class="text-[10px] font-medium text-emerald-700 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-950/40 px-2 py-0.5 rounded-full border border-emerald-200/60 dark:border-emerald-800/40">
                Active
              </span>
            </div>

            <!-- Officer Profile Details -->
            <div class="flex items-start space-x-3">
              <div class="w-12 h-12 rounded-full overflow-hidden flex-shrink-0 border border-slate-200 dark:border-neutral-700 bg-slate-100 dark:bg-neutral-800 text-slate-700 dark:text-neutral-300 flex items-center justify-center font-bold text-sm">
                <img v-if="pos.officer.profile_picture" :src="pos.officer.profile_picture" :alt="pos.officer.name" class="w-full h-full object-cover" />
                <span v-else>{{ pos.officer.avatar }}</span>
              </div>
              <div class="min-w-0 flex-1">
                <h3 class="font-bold text-sm text-slate-900 dark:text-white truncate leading-tight">
                  {{ pos.officer.name }}
                </h3>
                <p class="text-xs text-slate-500 dark:text-neutral-400 flex items-center mt-1 truncate capitalize font-medium">
                  <Music class="w-3 h-3 mr-1 text-slate-400 shrink-0" />
                  {{ pos.officer.instrument }}
                </p>
                <!-- Only visible to Officers & Admins -->
                <div v-if="store.isOfficerOrAdmin" class="flex items-center space-x-1.5 mt-2">
                  <span class="text-[10px] font-medium px-2 py-0.5 rounded-full bg-slate-100 dark:bg-neutral-800 text-slate-600 dark:text-neutral-300">
                    {{ pos.officer.rank }}
                  </span>
                  <span class="text-[10px] font-medium text-slate-500 dark:text-neutral-400">
                    {{ pos.officer.reliability }}% Score
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!-- Bottom Actions (Only for Officers & Admins) -->
          <div v-if="store.isOfficerOrAdmin" class="pt-3 mt-3 border-t border-slate-100 dark:border-neutral-800/80 flex items-center justify-between">
            <button 
              @click="openAvailabilityView(pos.officer)"
              type="button"
              class="text-xs font-medium text-slate-600 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white flex items-center cursor-pointer min-h-[30px]"
            >
              <Calendar class="w-3 h-3 mr-1" /> Availability
            </button>

            <button 
              v-if="store.isSuperAdmin"
              @click="openManageModal(pos.officer)"
              type="button"
              class="text-xs font-medium text-slate-600 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white flex items-center cursor-pointer min-h-[30px]"
            >
              <Settings class="w-3 h-3 mr-1" /> Manage
            </button>
          </div>
        </div>
      </div>
    </section>

    <!-- 2. "PA-IMPORTANTE" ATTENDANCE BEHAVIOR MONITOR (< 85%) -->
    <section v-if="store.canPromoteMembers && paImportanteList.length > 0" class="bg-rose-50/50 dark:bg-rose-950/20 border border-rose-200/70 dark:border-rose-900/40 rounded-3xl p-4 sm:p-5 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2 text-rose-700 dark:text-rose-400">
          <UserX class="w-4 h-4" />
          <h2 class="font-semibold text-xs sm:text-sm">Attendance Review List</h2>
        </div>
        <span class="text-xs font-medium bg-rose-100 dark:bg-rose-900/60 text-rose-800 dark:text-rose-200 px-2.5 py-0.5 rounded-full">
          {{ paImportanteList.length }} Below 85%
        </span>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2.5">
        <div 
          v-for="item in paImportanteList" 
          :key="item.id" 
          class="bg-white dark:bg-[#202124] p-3 rounded-2xl border border-slate-200/80 dark:border-neutral-800 flex items-center justify-between shadow-xs"
        >
          <div class="flex items-center space-x-2.5 min-w-0 pr-2">
            <div class="w-8 h-8 rounded-full bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 font-bold text-xs flex items-center justify-center shrink-0">
              {{ item.avatar }}
            </div>
            <div class="min-w-0">
              <p class="font-semibold text-xs text-slate-900 dark:text-white truncate">{{ item.name }}</p>
              <p class="text-[10px] text-rose-600 dark:text-rose-400 font-medium">{{ item.reliability }}% • {{ item.instrument }}</p>
            </div>
          </div>
          <button 
            v-if="store.isSuperAdmin"
            @click="openManageModal(item)"
            type="button"
            class="px-3 py-1 bg-slate-100 hover:bg-slate-200 dark:bg-neutral-800 dark:hover:bg-neutral-700 text-slate-700 dark:text-neutral-300 font-medium text-xs rounded-full shrink-0 cursor-pointer min-h-[30px]"
          >
            Manage
          </button>
        </div>
      </div>
    </section>

    <!-- 3. SEARCH & DYNAMIC FILTER BAR -->
    <div class="flex flex-col md:flex-row items-stretch md:items-center justify-between gap-3">
      <!-- Search Input -->
      <div class="relative flex-1 max-w-md">
        <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-slate-400">
          <Search class="w-4 h-4" />
        </div>
        <input 
          v-model="searchQuery"
          type="text" 
          placeholder="Search by name or instrument..."
          class="w-full pl-10 pr-4 py-2 bg-white dark:bg-[#202124] border border-slate-200 dark:border-neutral-800 rounded-full text-slate-900 dark:text-white placeholder-slate-400 text-xs font-normal shadow-xs min-h-[38px] focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600"
        />
      </div>

      <!-- Quick Category Pills (Responsive Wrapping) -->
      <div class="flex flex-wrap items-center gap-2">
        <!-- Instrument Section Dropdown -->
        <select 
          v-model="activeSectionFilter" 
          class="bg-white dark:bg-[#202124] text-slate-800 dark:text-white font-medium text-xs rounded-full px-3.5 py-1.5 border border-slate-200 dark:border-neutral-800 shadow-xs min-h-[38px] cursor-pointer shrink-0 focus:outline-none"
        >
          <option value="All">All Sections</option>
          <option v-for="sec in instrumentList" :key="sec" :value="sec">{{ sec }}</option>
        </select>

        <!-- Tier Filter Buttons (Senior/Junior filtered for officers only) -->
        <div v-if="store.isOfficerOrAdmin" class="flex rounded-full bg-slate-100 dark:bg-[#18191a] p-1 text-xs font-medium border border-slate-200/60 dark:border-neutral-800 shrink-0">
          <button 
            type="button" 
            @click="activeTierFilter = 'all'"
            class="px-3 py-1 rounded-full transition-all cursor-pointer"
            :class="activeTierFilter === 'all' ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 hover:text-slate-900 dark:hover:text-white'"
          >
            All
          </button>
          <button 
            type="button" 
            @click="activeTierFilter = 'officers'"
            class="px-3 py-1 rounded-full transition-all cursor-pointer"
            :class="activeTierFilter === 'officers' ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 hover:text-slate-900 dark:hover:text-white'"
          >
            Officers
          </button>
          <button 
            type="button" 
            @click="activeTierFilter = 'senior'"
            class="px-3 py-1 rounded-full transition-all cursor-pointer"
            :class="activeTierFilter === 'senior' ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 hover:text-slate-900 dark:hover:text-white'"
          >
            Senior
          </button>
          <button 
            type="button" 
            @click="activeTierFilter = 'junior'"
            class="px-3 py-1 rounded-full transition-all cursor-pointer"
            :class="activeTierFilter === 'junior' ? 'bg-white dark:bg-[#2d2f31] text-slate-900 dark:text-white shadow-xs font-semibold' : 'text-slate-500 hover:text-slate-900 dark:hover:text-white'"
          >
            Junior
          </button>
        </div>
      </div>
    </div>

    <!-- 4. CLEAN, HIGH-CONTRAST MUSICIAN DIRECTORY (DESKTOP / TABLET TABLE) -->
    <section class="space-y-3" aria-label="Musician Directory Roster">
      <div class="flex items-center justify-between px-1">
        <span class="text-xs font-semibold text-slate-700 dark:text-neutral-300">
          Master Directory ({{ sortedRoster.length }})
        </span>
        <span v-if="sortedRoster.length > 10" class="text-[10px] text-slate-400 dark:text-neutral-500">
          Scrollable table enabled
        </span>
      </div>

      <!-- DESKTOP / TABLET VIEW (TABLE WITH HORIZONTAL OVERFLOW SCROLLING) -->
      <div 
        class="hidden md:block bg-white dark:bg-[#202124] rounded-3xl shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-x-auto"
        :class="sortedRoster.length > 10 ? 'max-h-[560px] overflow-y-auto' : ''"
      >
        <table class="w-full text-left border-collapse text-xs">
          <!-- Sticky Header (Table 4: 48px Header Height) -->
          <thead class="sticky top-0 bg-slate-50 dark:bg-[#1e1f20] border-b border-slate-200 dark:border-[#2d3035] z-10 font-semibold text-slate-500 dark:text-neutral-400 text-xs h-12">
            <tr>
              <th scope="col" class="py-3 px-4">Musician</th>
              <th scope="col" class="py-3 px-4">Section / Instrument</th>
              <th scope="col" class="py-3 px-4">Role</th>
              <th v-if="store.isOfficerOrAdmin" scope="col" class="py-3 px-4">Rank</th>
              <th v-if="store.isOfficerOrAdmin" scope="col" class="py-3 px-4">Reliability</th>
              <th v-if="store.isOfficerOrAdmin" scope="col" class="py-3 px-4 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100 dark:divide-[#2d3035]">
            <tr 
              v-for="member in sortedRoster" 
              :key="member.id"
              class="transition-colors hover:bg-slate-50/70 dark:hover:bg-[#282a2c]/60 min-h-[48px]"
            >
              <!-- Musician Name & Avatar -->
              <td class="py-3.5 px-4">
                <div class="flex items-center space-x-3">
                  <div class="w-9 h-9 rounded-full overflow-hidden flex-shrink-0 border border-slate-200 dark:border-[#2d3035] bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-300 flex items-center justify-center font-bold text-xs">
                    <img v-if="member.profile_picture" :src="member.profile_picture" :alt="member.name" class="w-full h-full object-cover" />
                    <span v-else>{{ member.avatar }}</span>
                  </div>
                  <div class="min-w-0">
                    <span class="font-semibold text-slate-900 dark:text-white text-xs truncate block">
                      {{ member.name }}
                    </span>
                    <span v-if="store.isOfficerOrAdmin" class="text-[11px] text-slate-400 dark:text-neutral-500 truncate block">
                      {{ member.contact || 'Registered Member' }}
                    </span>
                    <span v-else class="text-[11px] text-slate-400 dark:text-neutral-500 truncate block">
                      Verified Member
                    </span>
                  </div>
                </div>
              </td>

              <!-- Section / Instrument -->
              <td class="py-3.5 px-4">
                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full bg-slate-100 dark:bg-[#2d3035] text-slate-700 dark:text-neutral-300 font-medium text-xs capitalize">
                  <Music class="w-3.5 h-3.5 mr-1 text-slate-400" />
                  {{ member.instrument }}
                </span>
              </td>

              <!-- Unified Position / Leadership Role Badge -->
              <td class="py-3.5 px-4">
                <span 
                  v-if="getMemberPositionId(member) === 'super_admin'" 
                  class="inline-flex items-center text-[10px] font-medium bg-rose-50 text-rose-700 dark:bg-rose-950/40 dark:text-rose-400 px-2.5 py-0.5 rounded-full border border-rose-200/60 dark:border-rose-900/40"
                >
                  <ShieldCheck class="w-3.5 h-3.5 mr-1" /> Super Admin
                </span>
                <span 
                  v-else-if="getMemberPositionId(member) !== 'member'" 
                  class="inline-flex items-center text-[10px] font-medium bg-slate-900 text-white dark:bg-white dark:text-slate-900 px-2.5 py-0.5 rounded-full shadow-xs"
                >
                  <Crown class="w-3.5 h-3.5 mr-1 text-amber-300" /> {{ getMemberPosition(member).badge }}
                </span>
                <span 
                  v-else 
                  class="inline-flex items-center text-[10px] font-normal text-slate-500 dark:text-neutral-400 bg-slate-100 dark:bg-[#2d3035] px-2.5 py-0.5 rounded-full"
                >
                  Musician
                </span>
              </td>

              <!-- Rank (Officers & Admins Only) -->
              <td v-if="store.isOfficerOrAdmin" class="py-3.5 px-4">
                <span 
                  class="text-[10px] font-medium px-2 py-0.5 rounded-full inline-flex items-center"
                  :class="member.rank === 'Senior' 
                    ? 'bg-slate-100 dark:bg-[#2d3035] text-slate-800 dark:text-neutral-200' 
                    : 'bg-slate-50 dark:bg-[#18191a] text-slate-500 dark:text-neutral-400'"
                >
                  <Award class="w-3.5 h-3.5 mr-1 text-slate-400" /> {{ member.rank }}
                </span>
              </td>

              <!-- Reliability (Officers & Admins Only) -->
              <td v-if="store.isOfficerOrAdmin" class="py-3.5 px-4">
                <div class="flex items-center space-x-1.5">
                  <span 
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    :class="member.reliability >= 90 ? 'bg-emerald-500' : member.reliability >= 80 ? 'bg-blue-500' : 'bg-rose-500'"
                  ></span>
                  <span class="font-medium text-xs text-slate-900 dark:text-white">
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
                    class="p-2 text-slate-500 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-[#2d3035] rounded-full transition-colors cursor-pointer min-w-[38px] min-h-[38px] flex items-center justify-center"
                    title="View Weekly Availability"
                  >
                    <Calendar class="w-4 h-4" />
                  </button>

                  <!-- Super Admin Manage Button -->
                  <button 
                    v-if="store.isSuperAdmin"
                    @click="openManageModal(member)"
                    type="button"
                    class="px-3.5 py-1.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-slate-100 text-white dark:text-slate-900 font-medium text-xs rounded-full shadow-xs flex items-center transition-all cursor-pointer min-h-[36px]"
                  >
                    <Settings class="w-3.5 h-3.5 mr-1" /> Manage
                  </button>
                </div>
              </td>
            </tr>

            <tr v-if="sortedRoster.length === 0">
              <td :colspan="store.isOfficerOrAdmin ? 6 : 3" class="py-10 text-center text-slate-400 font-medium">
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
          class="bg-white dark:bg-[#1e1f20] rounded-3xl p-4 shadow-xs border border-slate-200/80 dark:border-[#2d3035] space-y-3"
        >
          <!-- Top Row: Musician Identity -->
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center space-x-3 min-w-0">
              <div class="w-10 h-10 rounded-full overflow-hidden flex-shrink-0 border border-slate-200 dark:border-[#2d3035] bg-slate-100 dark:bg-[#2d3035] text-slate-700 dark:text-neutral-300 flex items-center justify-center font-bold text-xs">
                <img v-if="member.profile_picture" :src="member.profile_picture" :alt="member.name" class="w-full h-full object-cover" />
                <span v-else>{{ member.avatar }}</span>
              </div>
              <div class="min-w-0">
                <h3 class="font-bold text-sm text-slate-900 dark:text-white truncate">
                  {{ member.name }}
                </h3>
                <div class="flex items-center space-x-1.5 mt-0.5 flex-wrap">
                  <span 
                    v-if="getMemberPositionId(member) !== 'member'" 
                    class="text-[9px] font-medium bg-slate-900 text-white dark:bg-white dark:text-slate-900 px-2 py-0.5 rounded-full shadow-xs"
                  >
                    {{ getMemberPosition(member).badge }}
                  </span>
                  <span class="text-xs text-slate-500 dark:text-neutral-400 capitalize">
                    {{ member.instrument }}
                  </span>
                </div>
              </div>
            </div>

            <!-- Rank & Reliability: Officers & Admins Only -->
            <div v-if="store.isOfficerOrAdmin" class="text-right shrink-0">
              <span class="text-[10px] font-medium px-2 py-0.5 rounded-full bg-slate-100 dark:bg-[#2d3035] text-slate-600 dark:text-neutral-400">
                {{ member.rank }}
              </span>
              <p class="text-[11px] font-medium text-slate-700 dark:text-neutral-300 mt-1">{{ member.reliability }}%</p>
            </div>
          </div>

          <!-- Bottom Actions Bar (Officers & Admins Only) -->
          <div v-if="store.isOfficerOrAdmin" class="pt-2.5 border-t border-slate-100 dark:border-[#2d3035] flex items-center justify-between">
            <button 
              @click="openAvailabilityView(member)"
              type="button"
              class="text-xs font-medium text-slate-600 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white flex items-center cursor-pointer min-h-[44px] px-2"
            >
              <Calendar class="w-4 h-4 mr-1.5" /> Availability
            </button>

            <button 
              v-if="store.isSuperAdmin"
              @click="openManageModal(member)"
              type="button"
              class="px-4 py-2 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-slate-100 text-white dark:text-slate-900 font-medium text-xs rounded-full shadow-xs flex items-center cursor-pointer min-h-[44px]"
            >
              <Settings class="w-3.5 h-3.5 mr-1.5" /> Manage
            </button>
          </div>
        </div>

        <div v-if="sortedRoster.length === 0" class="bg-white dark:bg-[#1e1f20] rounded-3xl p-8 text-center border border-slate-200 dark:border-[#2d3035]">
          <Users class="w-8 h-8 text-slate-400 mx-auto mb-2 opacity-60" />
          <p class="text-xs font-medium text-slate-500">No musicians match your search or filter.</p>
        </div>
      </div>
    </section>

    <!-- 5. ALL-IN-ONE MUSICIAN MANAGEMENT MODAL (SUPER ADMIN ONLY) (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showManageModal && editingMember" class="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-[#2d3035] rounded-3xl p-6 max-w-md w-full space-y-4 shadow-xl text-left max-h-[90vh] flex flex-col">
        
        <!-- Modal Header with Musician Info -->
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-[#2d3035] pb-3">
          <div class="flex items-center space-x-3 min-w-0 pr-2">
            <div class="w-10 h-10 rounded-full overflow-hidden bg-slate-100 dark:bg-[#2d3035] text-slate-700 dark:text-neutral-300 flex items-center justify-center font-bold text-sm shrink-0">
              <img v-if="editingMember.profile_picture" :src="editingMember.profile_picture" :alt="editingMember.name" class="w-full h-full object-cover" />
              <span v-else>{{ editingMember.avatar }}</span>
            </div>
            <div class="min-w-0">
              <span class="text-[10px] text-slate-400 dark:text-neutral-500 uppercase tracking-wider">Manage Musician</span>
              <h3 class="font-bold text-base text-slate-900 dark:text-white truncate">{{ editingMember.name }}</h3>
            </div>
          </div>
          <button @click="showManageModal = false" class="text-slate-400 hover:text-slate-600 dark:hover:text-white min-w-[48px] min-h-[48px] flex items-center justify-center cursor-pointer rounded-full hover:bg-slate-100 dark:hover:bg-[#2d3035]" aria-label="Close modal">
            <X class="w-5 h-5" />
          </button>
        </div>

        <!-- Modal Form Body -->
        <div class="space-y-4 overflow-y-auto flex-1 pr-1">
          
          <!-- UNIFIED ROLE & LEADERSHIP POSITION SELECTOR -->
          <div>
            <label class="block text-xs font-medium text-slate-700 dark:text-neutral-300 mb-1 flex items-center">
              <Crown class="w-3.5 h-3.5 mr-1 text-amber-500" /> Position &amp; Leadership
            </label>
            <select 
              v-model="managePositionId"
              class="w-full p-3 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-[#2d3035] rounded-xl text-xs text-slate-900 dark:text-white min-h-[48px] focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600 cursor-pointer"
            >
              <option v-for="pos in POSITIONS" :key="pos.id" :value="pos.id">
                {{ pos.label }}
              </option>
            </select>
            <p class="text-[11px] text-slate-400 dark:text-neutral-500 mt-1">
              Leadership posts are strictly single-officer appointments. Assigning a post automatically unassigns any previous holder.
            </p>
          </div>

          <!-- INSTRUMENT SECTION -->
          <div>
            <label class="block text-xs font-medium text-slate-700 dark:text-neutral-300 mb-1 flex items-center">
              <Music class="w-3.5 h-3.5 mr-1 text-slate-400" /> Instrument Section
            </label>
            <select 
              v-model="manageInstrument"
              class="w-full p-3 bg-slate-50 dark:bg-[#18191a] border border-slate-200 dark:border-[#2d3035] rounded-xl text-xs text-slate-900 dark:text-white min-h-[48px] focus:outline-none focus:border-slate-400 dark:focus:border-neutral-600 cursor-pointer"
            >
              <option v-for="sec in instrumentList" :key="sec" :value="sec">{{ sec }}</option>
            </select>
          </div>

          <!-- MUSICIAN RANK TOGGLE -->
          <div>
            <label class="block text-xs font-medium text-slate-700 dark:text-neutral-300 mb-1 flex items-center">
              <Award class="w-3.5 h-3.5 mr-1 text-slate-400" /> Musician Rank
            </label>
            <div class="grid grid-cols-2 gap-2">
              <button 
                type="button" 
                @click="manageRank = 'Junior'"
                class="py-2.5 px-3 rounded-full border text-xs font-medium transition-all flex items-center justify-center cursor-pointer min-h-[44px]"
                :class="manageRank === 'Junior' 
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900 border-transparent shadow-xs' 
                  : 'bg-slate-50 dark:bg-[#18191a] text-slate-600 dark:text-neutral-400 border-slate-200 dark:border-[#2d3035]'"
              >
                Junior Rank
              </button>
              <button 
                type="button" 
                @click="manageRank = 'Senior'"
                class="py-2.5 px-3 rounded-full border text-xs font-medium transition-all flex items-center justify-center cursor-pointer min-h-[44px]"
                :class="manageRank === 'Senior' 
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900 border-transparent shadow-xs' 
                  : 'bg-slate-50 dark:bg-[#18191a] text-slate-600 dark:text-neutral-400 border-slate-200 dark:border-[#2d3035]'"
              >
                Senior Rank
              </button>
            </div>
          </div>

          <!-- DANGER ZONE: DELETE ACCOUNT -->
          <div v-if="editingMember.role !== 'super_admin' && editingMember.id !== store.user?.id" class="pt-3 border-t border-slate-100 dark:border-[#2d3035]">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-xs font-medium text-rose-600 dark:text-rose-400">Account Deletion</p>
                <p class="text-[11px] text-slate-400">Permanently remove this musician from registry</p>
              </div>
              <button 
                @click="promptDeleteMember(editingMember)"
                type="button"
                class="px-4 py-2 border border-rose-200 dark:border-rose-900/40 text-rose-600 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/30 font-medium text-xs rounded-full cursor-pointer min-h-[40px]"
              >
                Delete Account
              </button>
            </div>
          </div>

        </div>

        <!-- Modal Footer Actions -->
        <div class="flex space-x-2 pt-3 border-t border-slate-100 dark:border-[#2d3035]">
          <button 
            @click="showManageModal = false" 
            type="button" 
            class="flex-1 py-2.5 border border-slate-200 dark:border-[#2d3035] font-medium text-xs rounded-full text-slate-600 dark:text-neutral-300 hover:bg-slate-100 dark:hover:bg-[#2d3035] min-h-[48px] cursor-pointer"
          >
            Cancel
          </button>
          <button 
            @click="saveMemberManagement" 
            :disabled="isSavingManage"
            type="button" 
            class="flex-1 py-2.5 bg-slate-900 hover:bg-slate-800 dark:bg-white dark:hover:bg-slate-100 font-semibold text-xs text-white dark:text-slate-900 rounded-full shadow-xs min-h-[48px] cursor-pointer disabled:opacity-50"
          >
            {{ isSavingManage ? 'Saving...' : 'Save Changes' }}
          </button>
        </div>

      </div>
    </div>

    <!-- 6. MEMBER AVAILABILITY MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showAvailabilityModal" class="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-[#2d3035] rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-xl text-left">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-[#2d3035] pb-3">
          <div>
            <span class="text-[10px] text-slate-400 dark:text-neutral-500 uppercase tracking-wider">Availability Overview</span>
            <h3 class="font-bold text-base text-slate-900 dark:text-white truncate">{{ selectedMemberForAvailability?.name }}</h3>
          </div>
          <button @click="showAvailabilityModal = false" class="text-slate-400 hover:text-slate-600 dark:hover:text-white min-w-[48px] min-h-[48px] flex items-center justify-center cursor-pointer rounded-full hover:bg-slate-100 dark:hover:bg-[#2d3035]" aria-label="Close modal">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div class="space-y-3">
          <p class="text-xs text-slate-500 dark:text-neutral-400">
            Active weekly free slots registered by this musician:
          </p>

          <div v-if="isLoadingAvailability" class="py-6 text-center text-xs font-medium text-slate-400">
            Checking schedule...
          </div>

          <div v-else-if="memberAvailabilitySlots.length > 0" class="flex flex-wrap gap-1.5 max-h-48 overflow-y-auto pr-1">
            <span 
              v-for="slot in memberAvailabilitySlots" 
              :key="slot" 
              class="text-xs font-medium bg-emerald-50 dark:bg-emerald-950/30 text-emerald-700 dark:text-emerald-400 px-3 py-1.5 rounded-full border border-emerald-200/60 dark:border-emerald-800/40"
            >
              ✓ {{ slot }}
            </span>
          </div>

          <div v-else class="p-4 bg-slate-50 dark:bg-[#18191a] rounded-2xl text-center text-xs text-slate-400 font-medium space-y-1">
            <p>No active free slots registered for this week yet.</p>
            <p v-if="selectedMemberForAvailability?.id === store.user?.id" class="text-[11px] text-slate-500 dark:text-neutral-400">
              You can set your weekly slots in Profile Settings.
            </p>
          </div>
        </div>

        <div class="pt-2">
          <button 
            @click="showAvailabilityModal = false" 
            type="button" 
            class="w-full py-2.5 bg-slate-100 dark:bg-[#2d3035] hover:bg-slate-200 dark:hover:bg-[#383a3d] font-medium text-xs rounded-full text-slate-700 dark:text-neutral-200 cursor-pointer min-h-[48px]"
          >
            Close
          </button>
        </div>
      </div>
    </div>

    <!-- 7. SUPER ADMIN DELETE CONFIRMATION MODAL (M3 Dialog - Flat Scrim Overlay, Zero Blur) -->
    <div v-if="showDeleteModal" class="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1e1f20] border border-slate-200 dark:border-[#2d3035] rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-xl text-center">
        <div class="w-12 h-12 rounded-full bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        
        <div>
          <h3 class="font-bold text-base text-slate-900 dark:text-white leading-tight">Delete Musician Account?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 mt-1.5 leading-relaxed">
            Are you sure you want to permanently delete <strong class="text-slate-900 dark:text-white">{{ confirmDeleteTarget?.name }}</strong>? This action cannot be undone.
          </p>
        </div>

        <div class="flex space-x-2 pt-2">
          <button 
            @click="showDeleteModal = false; confirmDeleteTarget = null" 
            type="button" 
            class="flex-1 py-2.5 border border-slate-200 dark:border-[#2d3035] font-medium text-xs rounded-full text-slate-600 dark:text-neutral-300 hover:bg-slate-100 dark:hover:bg-[#2d3035] min-h-[48px] cursor-pointer"
          >
            Cancel
          </button>
          <button 
            @click="executeDeleteMember" 
            type="button" 
            class="flex-1 py-2.5 bg-rose-600 hover:bg-rose-700 font-semibold text-xs text-white rounded-full shadow-xs min-h-[48px] cursor-pointer"
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
