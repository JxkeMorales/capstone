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
import { supabase } from '@/supabase'

const store = useMainStore()

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
  { id: 'president', label: 'Band President', role: 'executive', title: 'president', color: 'amber', badge: 'Band President' },
  { id: 'vice_president', label: 'Band Vice President', role: 'executive', title: 'vice_president', color: 'amber', badge: 'Band Vice President' },
  { id: 'secretary', label: 'Band Secretary', role: 'secretary_admin', title: null, color: 'indigo', badge: 'Band Secretary' },
  { id: 'treasurer', label: 'Band Treasurer', role: 'executive', title: 'treasurer', color: 'emerald', badge: 'Band Treasurer' },
  { id: 'super_admin', label: 'IT Super Admin', role: 'super_admin', title: null, color: 'rose', badge: 'IT Super Admin' }
]

// HIERARCHICAL EXECUTIVE OFFICER POSTS (Pinned Leadership at top)
const leadershipPosts = [
  { key: 'president', title: 'Band President' },
  { key: 'vice_president', title: 'Band Vice President' },
  { key: 'secretary', title: 'Band Secretary' },
  { key: 'treasurer', title: 'Band Treasurer' },
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
  'Cymbals'
]

const showToast = (msg) => {
  toastMessage.value = msg
  setTimeout(() => { toastMessage.value = '' }, 3500)
}

// TITLE NORMALIZER
const normalizeTitle = (str) => {
  if (!str) return ''
  const s = str.toLowerCase().trim()
  if (s.includes('vice')) return 'vice_president'
  if (s.includes('pres')) return 'president'
  if (s.includes('sec')) return 'secretary'
  if (s.includes('treas')) return 'treasurer'
  if (s.includes('audit')) return 'auditor'
  if (s.includes('conduct')) return 'resident_conductor'
  if (s.includes('manag')) return 'band_manager'
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
  const newInst = manageInstrument.value
  const newRk = manageRank.value

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
    member.executive_title = newPos.title
    member.instrument = newInst
    member.rank = newRk
    members.value = [...members.value]

    // 3. Persist to Supabase
    const { error } = await supabase
      .from('profiles')
      .update({
        role: newPos.role,
        executive_title: newPos.title,
        instrument: newInst,
        rank: newRk
      })
      .eq('id', member.id)

    if (error) throw error

    showToast(`✓ Updated ${member.name} (${newPos.label} • ${newInst} • ${newRk}).`)
    showManageModal.value = false
    await fetchRoster(true)
  } catch (err) {
    console.error('Error saving member changes:', err)
    showToast(`Error: ${err?.message || 'Failed to save changes.'}`)
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

let membersBroadcast = null

const onWindowFocus = () => {
  fetchRoster(true)
}

onMounted(() => {
  fetchRoster()

  // 1. Supabase Realtime Channel
  membersChannel = supabase
    .channel('members-realtime-directory')
    .on('broadcast', { event: 'new_registration' }, () => {
      fetchRoster(true)
    })
    .on('broadcast', { event: 'account_status_changed' }, () => {
      fetchRoster(true)
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, () => {
      fetchRoster(true)
    })
    .subscribe()

  // 2. Inter-tab local broadcast
  if ('BroadcastChannel' in window) {
    membersBroadcast = new BroadcastChannel('smartband_live_sync')
    membersBroadcast.onmessage = (e) => {
      if (e.data?.type === 'NEW_REGISTRATION' || e.data?.type === 'ACCOUNT_STATUS_CHANGED') {
        fetchRoster(true)
      }
    }
  }

  window.addEventListener('focus', onWindowFocus)
})

onUnmounted(() => {
  if (membersChannel) {
    supabase.removeChannel(membersChannel)
  }
  if (membersBroadcast) {
    membersBroadcast.close()
  }
  window.removeEventListener('focus', onWindowFocus)
})
</script>

<template>
  <div class="p-4 sm:p-6 lg:p-8 space-y-6 max-w-7xl mx-auto">
    
    <!-- Top Header -->
    <header class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pb-4 border-b border-slate-200/80 dark:border-neutral-800/80">
      <div class="flex items-center space-x-3.5">
        <div class="p-2.5 rounded-2xl bg-blue-500/10 text-blue-600 dark:text-blue-400 flex-shrink-0 shadow-xs">
          <Users class="w-6 h-6" />
        </div>
        <div class="min-w-0">
          <div class="flex items-center space-x-2">
            <span class="text-xs font-bold text-blue-600 dark:text-blue-400 uppercase tracking-wider">Band Directory</span>
            <span v-if="store.isSuperAdmin" class="text-[10px] font-black uppercase bg-rose-500 text-white px-2.5 py-0.5 rounded-full">
              Super Admin Mode
            </span>
          </div>
          <h1 class="text-2xl sm:text-3xl font-black text-slate-900 dark:text-white leading-tight truncate">
            Musician Registry
          </h1>
        </div>
      </div>

      <div class="flex items-center space-x-2">
        <span class="text-xs font-bold text-slate-500 dark:text-neutral-400 bg-slate-100 dark:bg-[#27272a] px-3.5 py-1.5 rounded-xl border border-slate-200 dark:border-neutral-800">
          {{ members.length }} Verified Musicians
        </span>
      </div>
    </header>

    <!-- Toast Notification -->
    <Transition name="toast">
      <div 
        v-if="toastMessage" 
        class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-md w-11/12 bg-white dark:bg-[#1c1c1e] text-slate-900 dark:text-white px-4 py-3 rounded-2xl shadow-2xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between font-bold text-xs"
      >
        <div class="flex items-center space-x-2 min-w-0 pr-2">
          <CheckCircle2 class="w-4 h-4 text-emerald-500 flex-shrink-0" />
          <span class="truncate">{{ toastMessage }}</span>
        </div>
        <button @click="toastMessage = ''" class="text-slate-400 hover:text-slate-900 dark:hover:text-white min-w-[28px] min-h-[28px] flex items-center justify-center cursor-pointer">
          <X class="w-3.5 h-3.5" />
        </button>
      </div>
    </Transition>

    <!-- 1. PINNED ACTIVE EXECUTIVE OFFICERS (ONLY CURRENTLY APPOINTED OFFICERS) -->
    <section v-if="pinnedLeadership.length > 0" class="space-y-3" aria-label="Band Leadership">
      <div class="flex items-center justify-between px-1">
        <div class="flex items-center space-x-2">
          <Crown class="w-4 h-4 text-amber-500" />
          <h2 class="text-xs font-black uppercase tracking-wider text-slate-700 dark:text-neutral-300">
            Band Leadership & Executive Officers
          </h2>
        </div>
        <span class="text-[11px] font-bold text-slate-400 dark:text-neutral-500">
          {{ pinnedLeadership.length }} Active {{ pinnedLeadership.length === 1 ? 'Officer' : 'Officers' }}
        </span>
      </div>

      <!-- Responsive Grid for Active Officers -->
      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3.5">
        <div 
          v-for="pos in pinnedLeadership" 
          :key="pos.key"
          class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 border border-slate-200/90 dark:border-neutral-800 shadow-xs hover:border-blue-500/40 transition-all flex flex-col justify-between"
        >
          <div>
            <!-- Officer Title Badge -->
            <div class="flex items-center justify-between gap-2 mb-3">
              <span class="text-[10px] font-black uppercase px-2.5 py-1 rounded-lg tracking-wider bg-blue-600 text-white shadow-xs">
                {{ pos.title }}
              </span>
              <span class="text-[10px] font-bold text-emerald-600 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-950/60 px-2 py-0.5 rounded-md">
                Active
              </span>
            </div>

            <!-- Officer Profile Details -->
            <div class="flex items-start space-x-3">
              <div class="w-12 h-12 rounded-2xl overflow-hidden flex-shrink-0 border border-slate-200 dark:border-neutral-700 bg-blue-600 text-white flex items-center justify-center font-black text-sm shadow-xs">
                <img v-if="pos.officer.profile_picture" :src="pos.officer.profile_picture" :alt="pos.officer.name" class="w-full h-full object-cover" />
                <span v-else>{{ pos.officer.avatar }}</span>
              </div>
              <div class="min-w-0 flex-1">
                <h3 class="font-black text-sm text-slate-900 dark:text-white truncate leading-tight">
                  {{ pos.officer.name }}
                </h3>
                <p class="text-xs text-slate-500 dark:text-neutral-400 flex items-center mt-1 truncate capitalize font-medium">
                  <Music class="w-3 h-3 mr-1 text-slate-400 shrink-0" />
                  {{ pos.officer.instrument }}
                </p>
                <div class="flex items-center space-x-1.5 mt-2">
                  <span class="text-[9px] font-extrabold px-2 py-0.5 rounded bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-300">
                    {{ pos.officer.rank }}
                  </span>
                  <span class="text-[9px] font-extrabold text-blue-600 dark:text-blue-400">
                    {{ pos.officer.reliability }}% Score
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!-- Bottom Actions -->
          <div class="pt-3 mt-3 border-t border-slate-100 dark:border-neutral-800/80 flex items-center justify-between">
            <button 
              @click="openAvailabilityView(pos.officer)"
              type="button"
              class="text-[11px] font-bold text-blue-600 dark:text-blue-400 hover:underline flex items-center cursor-pointer min-h-[32px]"
            >
              <Calendar class="w-3 h-3 mr-1" /> Availability
            </button>

            <button 
              v-if="store.isSuperAdmin"
              @click="openManageModal(pos.officer)"
              type="button"
              class="text-[11px] font-bold text-slate-600 dark:text-neutral-400 hover:text-slate-900 dark:hover:text-white flex items-center cursor-pointer min-h-[32px]"
            >
              <Settings class="w-3 h-3 mr-1" /> Manage
            </button>
          </div>
        </div>
      </div>
    </section>

    <!-- 2. "PA-IMPORTANTE" ATTENDANCE BEHAVIOR MONITOR (< 85%) -->
    <section v-if="store.canPromoteMembers && paImportanteList.length > 0" class="bg-rose-50 dark:bg-rose-950/20 border border-rose-200/80 dark:border-rose-900/40 rounded-3xl p-4 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2 text-rose-700 dark:text-rose-400">
          <UserX class="w-5 h-5" />
          <h2 class="font-black text-xs uppercase tracking-wider">"Pa-Importante" Attendance Monitor</h2>
        </div>
        <span class="text-[11px] font-black bg-rose-200 dark:bg-rose-900/80 text-rose-900 dark:text-rose-200 px-2.5 py-0.5 rounded-full">
          {{ paImportanteList.length }} Below 85%
        </span>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2.5">
        <div 
          v-for="item in paImportanteList" 
          :key="item.id" 
          class="bg-white dark:bg-[#1c1c1e] p-3 rounded-2xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between shadow-xs"
        >
          <div class="flex items-center space-x-2.5 min-w-0 pr-2">
            <div class="w-8 h-8 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 dark:text-rose-400 font-bold text-xs flex items-center justify-center shrink-0">
              {{ item.avatar }}
            </div>
            <div class="min-w-0">
              <p class="font-bold text-xs text-slate-900 dark:text-white truncate">{{ item.name }}</p>
              <p class="text-[10px] text-rose-500 font-extrabold">{{ item.reliability }}% Score • {{ item.instrument }}</p>
            </div>
          </div>
          <button 
            v-if="store.isSuperAdmin"
            @click="openManageModal(item)"
            type="button"
            class="px-2.5 py-1 bg-amber-500/10 hover:bg-amber-500/20 text-amber-700 dark:text-amber-400 font-black text-[10px] rounded-xl border border-amber-300 dark:border-amber-800/40 shrink-0 cursor-pointer min-h-[34px]"
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
          placeholder="Search by name, instrument, or title..."
          class="w-full pl-10 pr-4 py-2.5 bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-2xl text-slate-900 dark:text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 text-xs font-bold shadow-xs min-h-[42px]"
        />
      </div>

      <!-- Quick Category Pills (Responsive Wrapping) -->
      <div class="flex flex-wrap items-center gap-2">
        <!-- Instrument Section Dropdown -->
        <select 
          v-model="activeSectionFilter" 
          class="bg-white dark:bg-[#1c1c1e] text-slate-800 dark:text-white font-bold text-xs rounded-2xl px-3 py-2 border border-slate-200 dark:border-neutral-800 shadow-xs min-h-[42px] cursor-pointer shrink-0"
        >
          <option value="All">All Sections</option>
          <option v-for="sec in instrumentList" :key="sec" :value="sec">{{ sec }}</option>
        </select>

        <!-- Tier Filter Buttons -->
        <div class="flex rounded-2xl bg-slate-100 dark:bg-[#27272a] p-1 text-xs font-bold border border-slate-200/80 dark:border-neutral-800 shrink-0">
          <button 
            type="button" 
            @click="activeTierFilter = 'all'"
            class="px-3 py-1.5 rounded-xl transition-all cursor-pointer"
            :class="activeTierFilter === 'all' ? 'bg-white dark:bg-[#1c1c1e] text-blue-600 dark:text-blue-400 shadow-xs font-black' : 'text-slate-500 hover:text-slate-900 dark:hover:text-white'"
          >
            All
          </button>
          <button 
            type="button" 
            @click="activeTierFilter = 'officers'"
            class="px-3 py-1.5 rounded-xl transition-all cursor-pointer"
            :class="activeTierFilter === 'officers' ? 'bg-white dark:bg-[#1c1c1e] text-blue-600 dark:text-blue-400 shadow-xs font-black' : 'text-slate-500 hover:text-slate-900 dark:hover:text-white'"
          >
            Officers
          </button>
          <button 
            type="button" 
            @click="activeTierFilter = 'senior'"
            class="px-3 py-1.5 rounded-xl transition-all cursor-pointer"
            :class="activeTierFilter === 'senior' ? 'bg-white dark:bg-[#1c1c1e] text-blue-600 dark:text-blue-400 shadow-xs font-black' : 'text-slate-500 hover:text-slate-900 dark:hover:text-white'"
          >
            Senior
          </button>
          <button 
            type="button" 
            @click="activeTierFilter = 'junior'"
            class="px-3 py-1.5 rounded-xl transition-all cursor-pointer"
            :class="activeTierFilter === 'junior' ? 'bg-white dark:bg-[#1c1c1e] text-blue-600 dark:text-blue-400 shadow-xs font-black' : 'text-slate-500 hover:text-slate-900 dark:hover:text-white'"
          >
            Junior
          </button>
        </div>
      </div>
    </div>

    <!-- 4. CLEAN, HIGH-CONTRAST MUSICIAN DIRECTORY (DESKTOP / TABLET TABLE) -->
    <section class="space-y-3" aria-label="Musician Directory Roster">
      <div class="flex items-center justify-between px-1">
        <span class="text-xs font-black text-slate-700 dark:text-neutral-300 uppercase tracking-wider">
          Musician Master Directory ({{ sortedRoster.length }})
        </span>
        <span v-if="sortedRoster.length > 10" class="text-[10px] font-bold text-slate-400 dark:text-neutral-500">
          Scrollable table enabled
        </span>
      </div>

      <!-- DESKTOP / TABLET VIEW (TABLE WITH HORIZONTAL OVERFLOW SCROLLING) -->
      <div 
        class="hidden md:block bg-white dark:bg-[#1c1c1e] rounded-3xl shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-x-auto"
        :class="sortedRoster.length > 10 ? 'max-h-[560px] overflow-y-auto' : ''"
      >
        <table class="w-full text-left border-collapse text-xs">
          <!-- Sticky Header -->
          <thead class="sticky top-0 bg-slate-50/95 dark:bg-[#27272a]/95 backdrop-blur-xs border-b border-slate-200 dark:border-neutral-800 z-10 font-black text-slate-500 dark:text-neutral-400 uppercase tracking-wider text-[10px]">
            <tr>
              <th scope="col" class="py-3.5 px-4">Musician</th>
              <th scope="col" class="py-3.5 px-4">Section / Instrument</th>
              <th scope="col" class="py-3.5 px-4">Role & Leadership</th>
              <th scope="col" class="py-3.5 px-4">Rank</th>
              <th scope="col" class="py-3.5 px-4">Reliability</th>
              <th scope="col" class="py-3.5 px-4 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100 dark:divide-neutral-800/80">
            <tr 
              v-for="member in sortedRoster" 
              :key="member.id"
              class="transition-colors hover:bg-slate-50/70 dark:hover:bg-neutral-800/40"
              :class="member.role === 'super_admin' ? 'bg-rose-50/20 dark:bg-rose-950/10' : member.executive_title ? 'bg-blue-50/20 dark:bg-blue-950/10' : ''"
            >
              <!-- Musician Name & Avatar -->
              <td class="py-3 px-4">
                <div class="flex items-center space-x-3">
                  <div class="w-9 h-9 rounded-2xl overflow-hidden flex-shrink-0 border border-slate-200 dark:border-neutral-700 bg-blue-600 text-white flex items-center justify-center font-black text-xs shadow-xs">
                    <img v-if="member.profile_picture" :src="member.profile_picture" :alt="member.name" class="w-full h-full object-cover" />
                    <span v-else>{{ member.avatar }}</span>
                  </div>
                  <div class="min-w-0">
                    <span class="font-black text-slate-900 dark:text-white text-xs truncate block">
                      {{ member.name }}
                    </span>
                    <span class="text-[11px] text-slate-400 dark:text-neutral-500 truncate block">
                      {{ member.contact || 'Registered Member' }}
                    </span>
                  </div>
                </div>
              </td>

              <!-- Section / Instrument -->
              <td class="py-3 px-4">
                <span class="inline-flex items-center px-2.5 py-1 rounded-xl bg-slate-100 dark:bg-[#27272a] text-slate-800 dark:text-neutral-200 font-bold text-xs capitalize">
                  <Music class="w-3 h-3 mr-1 text-slate-400" />
                  {{ member.instrument }}
                </span>
              </td>

              <!-- Unified Position / Leadership Role Badge -->
              <td class="py-3 px-4">
                <span 
                  v-if="getMemberPositionId(member) === 'super_admin'" 
                  class="inline-flex items-center text-[10px] font-black uppercase bg-rose-500 text-white px-2.5 py-1 rounded-lg tracking-wider"
                >
                  <ShieldCheck class="w-3 h-3 mr-1" /> IT Super Admin
                </span>
                <span 
                  v-else-if="getMemberPositionId(member) !== 'member'" 
                  class="inline-flex items-center text-[10px] font-black uppercase bg-blue-600 text-white px-2.5 py-1 rounded-lg tracking-wider shadow-xs"
                >
                  <Crown class="w-3 h-3 mr-1 text-amber-300" /> {{ getMemberPosition(member).badge }}
                </span>
                <span 
                  v-else 
                  class="inline-flex items-center text-[10px] font-bold text-slate-500 dark:text-neutral-400 bg-slate-100 dark:bg-[#27272a] px-2.5 py-1 rounded-lg"
                >
                  Musician
                </span>
              </td>

              <!-- Rank -->
              <td class="py-3 px-4">
                <span 
                  class="text-[10px] font-black px-2.5 py-1 rounded-lg border inline-flex items-center"
                  :class="member.rank === 'Senior' 
                    ? 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/30' 
                    : 'bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400 border-slate-200 dark:border-neutral-700/80'"
                >
                  <Award class="w-3 h-3 mr-1" /> {{ member.rank }}
                </span>
              </td>

              <!-- Reliability -->
              <td class="py-3 px-4">
                <div class="flex items-center space-x-1.5">
                  <span 
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    :class="member.reliability >= 90 ? 'bg-emerald-500' : member.reliability >= 80 ? 'bg-blue-500' : 'bg-rose-500'"
                  ></span>
                  <span class="font-extrabold text-xs text-slate-900 dark:text-white">
                    {{ member.reliability }}%
                  </span>
                </div>
              </td>

              <!-- Actions (Clean Buttons - No Messy Dropdowns) -->
              <td class="py-3 px-4 text-right">
                <div class="flex items-center justify-end space-x-2">
                  <!-- View Availability -->
                  <button 
                    @click="openAvailabilityView(member)"
                    type="button"
                    class="p-2 text-slate-500 hover:text-blue-600 dark:hover:text-blue-400 hover:bg-blue-50 dark:hover:bg-blue-950/40 rounded-xl transition-colors cursor-pointer min-w-[36px] min-h-[36px] flex items-center justify-center"
                    title="View Weekly Availability"
                  >
                    <Calendar class="w-4 h-4" />
                  </button>

                  <!-- Super Admin Manage Button -->
                  <button 
                    v-if="store.isSuperAdmin"
                    @click="openManageModal(member)"
                    type="button"
                    class="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs rounded-xl shadow-xs flex items-center transition-all cursor-pointer min-h-[36px]"
                  >
                    <Settings class="w-3.5 h-3.5 mr-1" /> Manage
                  </button>
                </div>
              </td>
            </tr>

            <tr v-if="sortedRoster.length === 0">
              <td colspan="6" class="py-10 text-center text-slate-400 font-bold">
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
          class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 space-y-3"
          :class="member.role === 'super_admin' ? 'border-l-4 border-l-rose-500' : member.executive_title ? 'border-l-4 border-l-blue-600' : ''"
        >
          <!-- Top Row: Musician Identity -->
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center space-x-3 min-w-0">
              <div class="w-11 h-11 rounded-2xl overflow-hidden flex-shrink-0 border border-slate-200 dark:border-neutral-700 bg-blue-600 text-white flex items-center justify-center font-black text-xs shadow-xs">
                <img v-if="member.profile_picture" :src="member.profile_picture" :alt="member.name" class="w-full h-full object-cover" />
                <span v-else>{{ member.avatar }}</span>
              </div>
              <div class="min-w-0">
                <h3 class="font-black text-sm text-slate-900 dark:text-white truncate">
                  {{ member.name }}
                </h3>
                <div class="flex items-center space-x-1.5 mt-0.5 flex-wrap">
                  <span 
                    v-if="getMemberPositionId(member) !== 'member'" 
                    class="text-[9px] font-black uppercase bg-blue-600 text-white px-2 py-0.5 rounded shadow-xs"
                  >
                    {{ getMemberPosition(member).badge }}
                  </span>
                  <span class="text-xs text-slate-500 dark:text-neutral-400 capitalize">
                    {{ member.instrument }}
                  </span>
                </div>
              </div>
            </div>

            <div class="text-right shrink-0">
              <span class="text-[10px] font-extrabold px-2 py-0.5 rounded" :class="member.rank === 'Senior' ? 'bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-400' : 'bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400'">
                {{ member.rank }}
              </span>
              <p class="text-[11px] font-black text-slate-900 dark:text-white mt-1">{{ member.reliability }}% Score</p>
            </div>
          </div>

          <!-- Bottom Actions Bar -->
          <div class="pt-2.5 border-t border-slate-100 dark:border-neutral-800 flex items-center justify-between">
            <button 
              @click="openAvailabilityView(member)"
              type="button"
              class="text-xs font-bold text-blue-600 dark:text-blue-400 flex items-center cursor-pointer min-h-[36px]"
            >
              <Calendar class="w-3.5 h-3.5 mr-1" /> View Availability
            </button>

            <button 
              v-if="store.isSuperAdmin"
              @click="openManageModal(member)"
              type="button"
              class="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs rounded-xl shadow-xs flex items-center cursor-pointer min-h-[36px]"
            >
              <Settings class="w-3.5 h-3.5 mr-1" /> Manage
            </button>
          </div>
        </div>

        <div v-if="sortedRoster.length === 0" class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-8 text-center border border-slate-200 dark:border-neutral-800">
          <Users class="w-8 h-8 text-slate-400 mx-auto mb-2 opacity-60" />
          <p class="text-xs font-bold text-slate-500">No musicians match your search or filter.</p>
        </div>
      </div>
    </section>

    <!-- 5. ALL-IN-ONE MUSICIAN MANAGEMENT MODAL (SUPER ADMIN ONLY) -->
    <div v-if="showManageModal && editingMember" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-md w-full space-y-5 shadow-2xl text-left max-h-[90vh] flex flex-col">
        
        <!-- Modal Header with Musician Info -->
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div class="flex items-center space-x-3 min-w-0 pr-2">
            <div class="w-11 h-11 rounded-2xl overflow-hidden bg-blue-600 text-white flex items-center justify-center font-black text-sm shrink-0 shadow-xs">
              <img v-if="editingMember.profile_picture" :src="editingMember.profile_picture" :alt="editingMember.name" class="w-full h-full object-cover" />
              <span v-else>{{ editingMember.avatar }}</span>
            </div>
            <div class="min-w-0">
              <span class="text-[10px] font-black uppercase text-blue-500 tracking-wider">Manage Member Profile</span>
              <h3 class="font-black text-base text-slate-900 dark:text-white truncate">{{ editingMember.name }}</h3>
            </div>
          </div>
          <button @click="showManageModal = false" class="text-slate-400 hover:text-white min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer">
            <X class="w-5 h-5" />
          </button>
        </div>

        <!-- Modal Form Body -->
        <div class="space-y-4 overflow-y-auto flex-1 pr-1">
          
          <!-- UNIFIED ROLE & LEADERSHIP POSITION SELECTOR -->
          <div>
            <label class="block text-xs font-black uppercase text-slate-700 dark:text-neutral-300 mb-1.5 flex items-center">
              <Crown class="w-3.5 h-3.5 mr-1 text-amber-500" /> Official Position & Leadership
            </label>
            <select 
              v-model="managePositionId"
              class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-2xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
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
            <label class="block text-xs font-black uppercase text-slate-700 dark:text-neutral-300 mb-1.5 flex items-center">
              <Music class="w-3.5 h-3.5 mr-1 text-blue-500" /> Instrument Section
            </label>
            <select 
              v-model="manageInstrument"
              class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-2xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]"
            >
              <option v-for="sec in instrumentList" :key="sec" :value="sec">{{ sec }}</option>
            </select>
          </div>

          <!-- MUSICIAN RANK TOGGLE -->
          <div>
            <label class="block text-xs font-black uppercase text-slate-700 dark:text-neutral-300 mb-1.5 flex items-center">
              <Award class="w-3.5 h-3.5 mr-1 text-indigo-500" /> Musician Rank
            </label>
            <div class="grid grid-cols-2 gap-2">
              <button 
                type="button" 
                @click="manageRank = 'Junior'"
                class="py-2.5 px-3 rounded-xl border text-xs font-black transition-all flex items-center justify-center cursor-pointer min-h-[40px]"
                :class="manageRank === 'Junior' 
                  ? 'bg-slate-900 text-white dark:bg-white dark:text-slate-900 border-transparent shadow-xs' 
                  : 'bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400 border-slate-200 dark:border-neutral-700'"
              >
                Junior Rank
              </button>
              <button 
                type="button" 
                @click="manageRank = 'Senior'"
                class="py-2.5 px-3 rounded-xl border text-xs font-black transition-all flex items-center justify-center cursor-pointer min-h-[40px]"
                :class="manageRank === 'Senior' 
                  ? 'bg-blue-600 text-white border-transparent shadow-xs' 
                  : 'bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400 border-slate-200 dark:border-neutral-700'"
              >
                Senior Rank
              </button>
            </div>
          </div>

          <!-- DANGER ZONE: DELETE ACCOUNT -->
          <div v-if="editingMember.role !== 'super_admin' && editingMember.id !== store.user?.id" class="pt-3 border-t border-slate-100 dark:border-neutral-800">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-xs font-bold text-rose-600 dark:text-rose-400">Account Deletion</p>
                <p class="text-[11px] text-slate-400">Permanently remove this musician from registry</p>
              </div>
              <button 
                @click="promptDeleteMember(editingMember)"
                type="button"
                class="px-3 py-1.5 bg-rose-50 text-rose-600 hover:bg-rose-100 dark:bg-rose-950/40 dark:text-rose-400 font-bold text-xs rounded-xl border border-rose-200 dark:border-rose-900/40 cursor-pointer min-h-[36px]"
              >
                Delete Account
              </button>
            </div>
          </div>

        </div>

        <!-- Modal Footer Actions -->
        <div class="flex space-x-2 pt-3 border-t border-slate-100 dark:border-neutral-800">
          <button 
            @click="showManageModal = false" 
            type="button" 
            class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 active:scale-95 min-h-[44px] cursor-pointer"
          >
            Cancel
          </button>
          <button 
            @click="saveMemberManagement" 
            :disabled="isSavingManage"
            type="button" 
            class="flex-1 py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md active:scale-95 min-h-[44px] cursor-pointer disabled:opacity-50"
          >
            {{ isSavingManage ? 'Saving...' : 'Save Changes' }}
          </button>
        </div>

      </div>
    </div>

    <!-- 6. MEMBER AVAILABILITY MODAL -->
    <div v-if="showAvailabilityModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div>
            <span class="text-[10px] font-black text-blue-500 uppercase tracking-wider">Availability Overview</span>
            <h3 class="font-black text-base text-slate-900 dark:text-white truncate">{{ selectedMemberForAvailability?.name }}</h3>
          </div>
          <button @click="showAvailabilityModal = false" class="text-slate-400 hover:text-white min-w-[36px] min-h-[36px] flex items-center justify-center cursor-pointer">
            <X class="w-5 h-5" />
          </button>
        </div>

        <div class="space-y-3">
          <p class="text-xs text-slate-500 dark:text-neutral-400 font-medium">
            Active weekly free slots registered by this musician:
          </p>

          <div v-if="isLoadingAvailability" class="py-6 text-center text-xs font-bold text-slate-400">
            Checking schedule...
          </div>

          <div v-else-if="memberAvailabilitySlots.length > 0" class="flex flex-wrap gap-2 max-h-48 overflow-y-auto pr-1">
            <span 
              v-for="slot in memberAvailabilitySlots" 
              :key="slot" 
              class="text-[11px] font-black bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-400 px-3 py-1.5 rounded-xl border border-emerald-300 dark:border-emerald-800/40 shadow-xs"
            >
              ✓ {{ slot }}
            </span>
          </div>

          <div v-else class="p-4 bg-slate-50 dark:bg-[#27272a] rounded-2xl text-center text-xs text-slate-400 font-bold space-y-1">
            <p>No active free slots registered for this week yet.</p>
            <p v-if="selectedMemberForAvailability?.id === store.user?.id" class="text-[11px] text-blue-500">
              You can set your weekly slots in Profile Settings.
            </p>
          </div>
        </div>

        <div class="pt-2">
          <button 
            @click="showAvailabilityModal = false" 
            type="button" 
            class="w-full py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 active:scale-95 cursor-pointer min-h-[44px]"
          >
            Close
          </button>
        </div>
      </div>
    </div>

    <!-- 7. SUPER ADMIN DELETE CONFIRMATION MODAL -->
    <div v-if="showDeleteModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-center">
        <div class="w-12 h-12 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 dark:text-rose-400 flex items-center justify-center mx-auto">
          <AlertCircle class="w-6 h-6" />
        </div>
        
        <div>
          <h3 class="font-black text-lg text-slate-900 dark:text-white leading-tight">Delete Musician Account?</h3>
          <p class="text-xs text-slate-500 dark:text-neutral-400 mt-1.5 leading-relaxed">
            Are you sure you want to permanently delete <strong class="text-slate-900 dark:text-white">{{ confirmDeleteTarget?.name }}</strong>? This action cannot be undone.
          </p>
        </div>

        <div class="flex space-x-2 pt-2">
          <button 
            @click="showDeleteModal = false; confirmDeleteTarget = null" 
            type="button" 
            class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 active:scale-95 min-h-[44px] cursor-pointer"
          >
            Cancel
          </button>
          <button 
            @click="executeDeleteMember" 
            type="button" 
            class="flex-1 py-3 bg-rose-600 hover:bg-rose-700 font-black text-xs text-white rounded-xl shadow-md active:scale-95 min-h-[44px] cursor-pointer"
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
