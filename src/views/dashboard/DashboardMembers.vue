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
  Eye,
  Edit2
} from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const store = useMainStore()

const searchQuery = ref('')
const activeFilters = ref(['All'])
const tempFilters = ref(['All'])
const showFilterMenu = ref(false)
const members = ref([])
const isLoading = ref(true)
const toastMessage = ref('')

// Availability Modal Sheet State
const showAvailabilityModal = ref(false)
const selectedMember = ref(null)
const memberAvailabilitySlots = ref([])
const isLoadingAvailability = ref(false)

// Delete Confirmation Modal State
const showDeleteModal = ref(false)
const confirmDeleteTarget = ref(null)

// Realtime Channel Reference
let membersChannel = null

// 7 HIERARCHICAL EXECUTIVE OFFICER POSITIONS
const executivePositions = [
  { key: 'president', title: 'Band President', shortTitle: 'President' },
  { key: 'vice_president', title: 'Band Vice President', shortTitle: 'Vice President' },
  { key: 'secretary', title: 'Band Secretary', shortTitle: 'Secretary' },
  { key: 'treasurer', title: 'Band Treasurer', shortTitle: 'Treasurer' },
  { key: 'auditor', title: 'Band Auditor', shortTitle: 'Auditor' },
  { key: 'resident_conductor', title: 'Resident Conductor', shortTitle: 'Conductor' },
  { key: 'band_manager', title: 'Band Manager', shortTitle: 'Manager' },
]

// FULL MUNICIPAL BAND SECTION LIST FOR DIRECTORY FILTERING & ADMIN INSTRUMENT SELECTION
const sections = [
  'All', 
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

// TITLE NORMALIZER (Tolerates uppercase, spaces, or prefixed titles in DB)
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

// FILTER HANDLERS
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

// "PA-IMPORTANTE" ATTENDANCE LIST (Reliability < 85%)
const paImportanteList = computed(() => {
  return members.value.filter(m => (m.reliability || 100) < 85)
})

// PINNED EXECUTIVE OFFICERS COMPUTED (STRICTLY ACTIVE ONLY - NO BLANK TABS)
const pinnedLeadership = computed(() => {
  return executivePositions
    .map(pos => {
      const officer = members.value.find(m => {
        if (pos.key === 'secretary') {
          return normalizeTitle(m.executive_title) === 'secretary' || m.role === 'secretary_admin'
        }
        return normalizeTitle(m.executive_title) === pos.key
      })
      return {
        ...pos,
        officer: officer || null
      }
    })
    .filter(pos => pos.officer !== null) // Strictly filters out vacant positions so no blank cards appear
})

// FILTERED MEMBERS ROSTER
const filteredMembers = computed(() => {
  return members.value.filter(member => {
    const q = searchQuery.value.toLowerCase().trim()
    const matchesSearch = !q || 
      (member.name && member.name.toLowerCase().includes(q)) ||
      (member.instrument && member.instrument.toLowerCase().includes(q)) ||
      (member.role && member.role.toLowerCase().includes(q)) ||
      (member.executive_title && member.executive_title.toLowerCase().includes(q))
    
    if (!matchesSearch) return false
    if (activeFilters.value.includes('All')) return true
    
    return activeFilters.value.some(filterItem => {
      const filterKey = filterItem.toLowerCase().split('(')[0].trim()
      return member.instrument && member.instrument.toLowerCase().includes(filterKey)
    })
  })
})

// SORTED ROSTER (Hierarchy: Super Admin -> Pinned Officers -> Senior -> Junior -> Alphabetical)
const sortedRoster = computed(() => {
  const getRankPriority = (m) => {
    if (m.role === 'super_admin') return 1
    const t = normalizeTitle(m.executive_title)
    if (t === 'president') return 2
    if (t === 'vice_president') return 3
    if (m.role === 'secretary_admin' || t === 'secretary') return 4
    if (t === 'treasurer') return 5
    if (t === 'auditor') return 6
    if (t === 'resident_conductor') return 7
    if (t === 'band_manager') return 8
    if (m.executive_title) return 9
    if (m.rank === 'Senior') return 10
    return 11
  }

  return [...filteredMembers.value].sort((a, b) => {
    const pA = getRankPriority(a)
    const pB = getRankPriority(b)
    if (pA !== pB) return pA - pB
    return (a.name || '').localeCompare(b.name || '')
  })
})

// FETCH ROSTER
const fetchRoster = async (skipCache = false) => {
  if (!skipCache) {
    isLoading.value = true
    const cachedRoster = localStorage.getItem('smartband_members_roster_cache')
    if (cachedRoster) {
      try {
        members.value = JSON.parse(cachedRoster)
      } catch (e) {}
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

// SUPER ADMIN: CHANGE SYSTEM ROLE
const changeRole = async (member, newRole) => {
  try {
    const prevRole = member.role
    const prevTitle = member.executive_title

    if (newRole === 'secretary_admin') {
      // Demote previous secretary if any in local state
      members.value.forEach(m => {
        if (m.id !== member.id && (m.role === 'secretary_admin' || normalizeTitle(m.executive_title) === 'secretary')) {
          m.role = 'member'
          m.executive_title = null
        }
      })
      member.role = 'secretary_admin'
      member.executive_title = 'secretary'
    } else if (newRole === 'member') {
      member.role = 'member'
      member.executive_title = null
    } else {
      member.role = newRole
    }

    // Force reactive re-render immediately
    members.value = [...members.value]

    // Sync to Supabase in background
    if (newRole === 'secretary_admin') {
      const prevSec = members.value.find(m => m.id !== member.id && (m.role === 'secretary_admin' || normalizeTitle(m.executive_title) === 'secretary'))
      if (prevSec) {
        await supabase.from('profiles').update({ role: 'member', executive_title: null }).eq('id', prevSec.id)
      }
      await supabase.from('profiles').update({ role: 'secretary_admin', executive_title: 'secretary' }).eq('id', member.id)
    } else if (newRole === 'member') {
      await supabase.from('profiles').update({ role: 'member', executive_title: null }).eq('id', member.id)
    } else {
      await supabase.from('profiles').update({ role: newRole }).eq('id', member.id)
    }

    showToast(`Updated ${member.name}'s role to ${newRole.replace('_', ' ')}.`)
    await fetchRoster(true)
  } catch (err) {
    console.error('Role update error:', err)
    showToast('Failed to change role.')
    await fetchRoster(true)
  }
}

// SUPER ADMIN: ASSIGN EXECUTIVE TITLE (Single Officer Appointment + Instant Reactive Sync)
const assignExecutiveTitle = async (member, newTitle) => {
  try {
    const formattedTitle = newTitle ? normalizeTitle(newTitle) : null

    // 1. Optimistically update local state immediately so pinnedLeadership updates in 0ms!
    if (formattedTitle) {
      members.value.forEach(m => {
        if (m.id !== member.id && normalizeTitle(m.executive_title) === formattedTitle) {
          m.executive_title = null
          if (m.role === 'secretary_admin' || m.role === 'executive') m.role = 'member'
        }
      })
    }

    let targetRole = member.role
    if (formattedTitle === 'secretary') {
      targetRole = 'secretary_admin'
    } else if (['president', 'vice_president', 'treasurer', 'auditor', 'resident_conductor', 'band_manager'].includes(formattedTitle)) {
      if (member.role !== 'super_admin') {
        targetRole = 'executive'
      }
    } else if (!formattedTitle && (member.role === 'secretary_admin' || member.role === 'executive')) {
      targetRole = 'member'
    }

    member.executive_title = formattedTitle
    member.role = targetRole
    members.value = [...members.value] // Force Vue reactivity trigger

    // 2. Persist to Supabase
    if (formattedTitle) {
      const prevHolder = members.value.find(m => m.id !== member.id && normalizeTitle(m.executive_title) === formattedTitle)
      if (prevHolder) {
        await supabase.from('profiles').update({ executive_title: null, role: prevHolder.role }).eq('id', prevHolder.id)
      }
    }

    const { error } = await supabase
      .from('profiles')
      .update({ executive_title: formattedTitle, role: targetRole })
      .eq('id', member.id)

    if (error) throw error

    const titleLabel = formattedTitle ? formattedTitle.replace('_', ' ').toUpperCase() : 'Regular Musician'
    showToast(`Assigned ${member.name} as ${titleLabel}.`)
    await fetchRoster(true)
  } catch (err) {
    console.error('Executive title update error:', err)
    showToast('Failed to assign officer title.')
    await fetchRoster(true)
  }
}

// SUPER ADMIN: CHANGE USER INSTRUMENT
const changeInstrument = async (member, newInstrument) => {
  try {
    const oldInstrument = member.instrument
    member.instrument = newInstrument
    members.value = [...members.value]

    const { error } = await supabase
      .from('profiles')
      .update({ instrument: newInstrument })
      .eq('id', member.id)

    if (error) {
      member.instrument = oldInstrument
      members.value = [...members.value]
      throw error
    }

    showToast(`Updated ${member.name}'s instrument to ${newInstrument}.`)
    await fetchRoster(true)
  } catch (err) {
    console.error('Instrument update error:', err)
    showToast('Failed to update instrument.')
    await fetchRoster(true)
  }
}

// TOGGLE RANK (JUNIOR / SENIOR)
const toggleMemberRank = async (member) => {
  const newRank = member.rank === 'Senior' ? 'Junior' : 'Senior'
  try {
    member.rank = newRank
    members.value = [...members.value]

    const { error } = await supabase
      .from('profiles')
      .update({ rank: newRank })
      .eq('id', member.id)

    if (error) throw error

    showToast(`${member.name} is now a ${newRank} Musician.`)
    await fetchRoster(true)
  } catch (err) {
    console.error('Rank toggle error:', err)
    showToast('Failed to change rank.')
    await fetchRoster(true)
  }
}

// DELETE MEMBER ACCOUNT (SUPER ADMIN ONLY)
const promptDeleteMember = (member) => {
  confirmDeleteTarget.value = member
  showDeleteModal.value = true
}

const executeDeleteMember = async () => {
  if (!confirmDeleteTarget.value) return
  const target = confirmDeleteTarget.value

  try {
    const { error } = await supabase
      .from('profiles')
      .delete()
      .eq('id', target.id)

    if (error) throw error

    members.value = members.value.filter(m => m.id !== target.id)
    showToast(`Permanently deleted ${target.name}.`)
  } catch (err) {
    console.error('Delete member error:', err)
    showToast('Failed to delete member account.')
  } finally {
    showDeleteModal.value = false
    confirmDeleteTarget.value = null
  }
}

// VIEW MEMBER AVAILABILITY (QUERIES ALL COLUMNS TOLERATING is_free & is_available)
const openAvailabilityView = async (member) => {
  selectedMember.value = member
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
      // Tolerate both is_free and is_available schema variants
      const freeSlots = data.filter(d => d.is_free !== false && d.is_available !== false)
      
      const dayOrder = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
      const sortedSlots = [...freeSlots].sort((a, b) => {
        const idxA = dayOrder.indexOf((a.day_of_week || '').toLowerCase())
        const idxB = dayOrder.indexOf((b.day_of_week || '').toLowerCase())
        return idxA - idxB
      })

      memberAvailabilitySlots.value = sortedSlots.map(d => {
        const rawDay = d.day_of_week || ''
        const day = rawDay ? rawDay.charAt(0).toUpperCase() + rawDay.slice(1).toLowerCase() : 'Any Day'
        return `${day} • ${d.time_slot || 'All Day'}`
      })
    }
  } catch (err) {
    console.error('Error fetching member availability:', err)
  } finally {
    isLoadingAvailability.value = false
  }
}

onMounted(() => {
  fetchRoster()

  membersChannel = supabase
    .channel('members-realtime')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, () => {
      fetchRoster(true)
    })
    .subscribe()
})

onUnmounted(() => {
  if (membersChannel) {
    supabase.removeChannel(membersChannel)
  }
})
</script>

<template>
  <div class="p-4 sm:p-6 space-y-6 max-w-7xl mx-auto">
    
    <!-- Top Header -->
    <header class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pt-1 border-b border-slate-200/80 dark:border-neutral-800 pb-4">
      <div class="flex items-center space-x-3.5">
        <div class="p-2.5 rounded-2xl bg-blue-500/10 text-blue-600 dark:text-blue-400 shadow-xs flex-shrink-0">
          <Users class="w-6 h-6" />
        </div>
        <div class="min-w-0">
          <div class="flex items-center space-x-2">
            <p class="text-xs font-bold text-blue-600 dark:text-blue-400 uppercase tracking-wider leading-tight">Band Directory & Registry</p>
            <span v-if="store.isSuperAdmin" class="text-[10px] font-black uppercase bg-rose-500 text-white px-2 py-0.5 rounded-full">
              Super Admin Control
            </span>
          </div>
          <h1 class="text-2xl sm:text-3xl font-black text-slate-900 dark:text-white leading-tight truncate">Band Roster</h1>
        </div>
      </div>

      <div class="flex items-center space-x-2">
        <span class="text-xs font-bold text-slate-500 dark:text-neutral-400 bg-slate-100 dark:bg-[#27272a] px-3 py-1.5 rounded-xl border border-slate-200 dark:border-neutral-800">
          {{ members.length }} Verified Musicians
        </span>
      </div>
    </header>

    <!-- Toast Notification -->
    <Transition name="toast">
      <div 
        v-if="toastMessage" 
        class="fixed top-16 left-1/2 -translate-x-1/2 z-50 max-w-xs sm:max-w-md w-11/12 bg-white dark:bg-[#1c1c1e] text-slate-900 dark:text-white px-4 py-3 rounded-2xl shadow-xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between font-bold text-xs"
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

    <!-- 1. PINNED ACTIVE EXECUTIVE OFFICERS CARDS (NO BLANK TABS, NO '(7 Posts)') -->
    <section v-if="pinnedLeadership.length > 0" class="space-y-3" aria-label="Executive Leadership Section">
      <div class="flex items-center justify-between px-1">
        <div class="flex items-center space-x-2">
          <Crown class="w-4 h-4 text-amber-500" />
          <h2 class="text-xs font-extrabold uppercase tracking-wider text-slate-700 dark:text-neutral-300">
            Band Leadership & Executive Officers
          </h2>
        </div>
        <span class="text-[11px] font-bold text-slate-400 dark:text-neutral-500">
          {{ pinnedLeadership.length }} Active {{ pinnedLeadership.length === 1 ? 'Officer' : 'Officers' }}
        </span>
      </div>

      <!-- Responsive Grid: Only Active Appointed Officers Rendered -->
      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3.5">
        <div 
          v-for="pos in pinnedLeadership" 
          :key="pos.key"
          class="rounded-3xl p-4 border transition-all duration-200 flex flex-col justify-between bg-white dark:bg-[#1c1c1e] border-slate-200/90 dark:border-neutral-800 shadow-sm hover:border-blue-500/50"
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

            <!-- Musician Details -->
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

          <!-- Bottom Action for Officer Card -->
          <div class="pt-3 mt-3 border-t border-slate-100 dark:border-neutral-800/80 flex items-center justify-between">
            <button 
              @click="openAvailabilityView(pos.officer)"
              type="button"
              class="text-[11px] font-bold text-blue-600 dark:text-blue-400 hover:underline flex items-center cursor-pointer min-h-[32px]"
            >
              <Calendar class="w-3 h-3 mr-1" /> View Availability
            </button>
            <span v-if="pos.officer.role === 'secretary_admin'" class="text-[9px] font-black uppercase text-indigo-500">
              Operations Lead
            </span>
          </div>
        </div>
      </div>
    </section>

    <!-- 2. "PA-IMPORTANTE" ATTENDANCE BEHAVIOR MONITOR (Reliability < 85%) -->
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

      <p class="text-xs text-slate-600 dark:text-neutral-400 leading-relaxed font-medium">
        Musicians with low attendance reliability. Secretary and Super Admin can demote rank or coordinate call-time follow-ups.
      </p>

      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2.5 pt-1">
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
            @click="toggleMemberRank(item)" 
            type="button"
            class="px-2.5 py-1.5 bg-amber-500/10 hover:bg-amber-500/20 text-amber-700 dark:text-amber-400 font-black text-[10px] rounded-xl border border-amber-300 dark:border-amber-800/40 shrink-0 cursor-pointer min-h-[36px]"
            title="Click to toggle Rank"
          >
            Demote
          </button>
        </div>
      </div>
    </section>

    <!-- 3. SEARCH & SECTION FILTER BAR -->
    <div class="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3 pt-2">
      <!-- Search Input -->
      <div class="relative flex-1 max-w-lg">
        <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-slate-400">
          <Search class="w-4 h-4" />
        </div>
        <input 
          v-model="searchQuery"
          type="text" 
          placeholder="Search by musician name, instrument, role, or title..."
          class="w-full pl-10 pr-4 py-3 bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-2xl text-slate-900 dark:text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 text-xs font-bold shadow-xs min-h-[44px]"
        />
      </div>

      <!-- Filter Button & Active Filter Badges -->
      <div class="flex items-center space-x-2">
        <div class="relative">
          <button 
            @click="openFilter"
            type="button"
            class="flex items-center space-x-2 px-4 py-3 bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-2xl text-slate-700 dark:text-neutral-300 hover:bg-slate-50 dark:hover:bg-[#27272a] text-xs font-bold shadow-xs cursor-pointer min-h-[44px]"
          >
            <Filter class="w-4 h-4" :class="{ 'text-blue-600 dark:text-blue-400': !activeFilters.includes('All') }" />
            <span>Section Filter</span>
            <span v-if="!activeFilters.includes('All')" class="w-2 h-2 bg-blue-600 rounded-full"></span>
          </button>

          <!-- Filter Dropdown Menu -->
          <div v-if="showFilterMenu" class="absolute right-0 mt-2 w-64 bg-white dark:bg-[#27272a] rounded-3xl shadow-2xl border border-slate-200 dark:border-neutral-800 overflow-hidden z-30">
            <div class="p-3.5 bg-slate-50 dark:bg-[#1c1c1e] border-b border-slate-200 dark:border-neutral-800 flex items-center justify-between">
              <h3 class="text-xs font-black text-slate-700 dark:text-neutral-300 uppercase tracking-wider">Filter by Instrument</h3>
              <button @click="showFilterMenu = false" class="text-slate-400 hover:text-slate-700 dark:hover:text-white"><X class="w-4 h-4" /></button>
            </div>
            <div class="max-h-64 overflow-y-auto p-2 space-y-1">
              <label 
                v-for="sec in sections" 
                :key="sec"
                class="flex items-center space-x-3 px-3 py-2 rounded-xl hover:bg-slate-100/70 dark:hover:bg-[#1c1c1e] cursor-pointer transition-colors"
              >
                <input 
                  type="checkbox" 
                  :checked="tempFilters.includes(sec)"
                  @change="toggleTempFilter(sec)"
                  class="w-4 h-4 rounded border-slate-300 text-blue-600 focus:ring-blue-500 dark:bg-neutral-800 dark:border-neutral-700 cursor-pointer"
                >
                <span class="text-xs font-bold text-slate-700 dark:text-neutral-200">{{ sec === 'All' ? 'All Sections' : sec }}</span>
              </label>
            </div>
            <div class="p-3 bg-slate-50 dark:bg-[#1c1c1e] border-t border-slate-200 dark:border-neutral-800 flex items-center justify-end space-x-2">
              <button @click="showFilterMenu = false" class="px-3 py-2 text-xs font-bold text-slate-500 hover:text-slate-700 dark:hover:text-neutral-200 cursor-pointer">Cancel</button>
              <button @click="applyFilters" class="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-black transition-colors shadow-xs cursor-pointer">Apply Filter</button>
            </div>
          </div>
        </div>

        <button 
          v-if="!activeFilters.includes('All')"
          @click="activeFilters = ['All']"
          class="text-xs font-bold text-blue-600 dark:text-blue-400 hover:underline px-2 cursor-pointer"
        >
          Reset Filter
        </button>
      </div>
    </div>

    <!-- 4. DYNAMIC MEMBER ROSTER (TABLE ON DESKTOP & TABLET, CARDS ON MOBILE) -->
    <section class="space-y-3" aria-label="Member Directory List">
      <div class="flex items-center justify-between px-1">
        <span class="text-xs font-extrabold text-slate-600 dark:text-neutral-400 uppercase tracking-wider">
          Musician Master Directory ({{ sortedRoster.length }})
        </span>
        <span v-if="sortedRoster.length > 10" class="text-[10px] font-bold text-slate-400 dark:text-neutral-500">
          Scroll container enabled ({{ sortedRoster.length }} total)
        </span>
      </div>

      <!-- DESKTOP & TABLET VIEW: SLEEK HIGH-CONTRAST DATA TABLE (Hidden on Mobile) -->
      <div 
        class="hidden md:block bg-white dark:bg-[#1c1c1e] rounded-3xl shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-hidden"
        :class="sortedRoster.length > 10 ? 'max-h-[540px] overflow-y-auto' : ''"
      >
        <table class="w-full text-left border-collapse text-xs">
          <!-- Sticky Header -->
          <thead class="sticky top-0 bg-slate-50 dark:bg-[#27272a] border-b border-slate-200 dark:border-neutral-800 z-10 font-black text-slate-500 dark:text-neutral-400 uppercase tracking-wider text-[10px]">
            <tr>
              <th scope="col" class="py-3.5 px-4">Musician</th>
              <th scope="col" class="py-3.5 px-4">Section / Instrument</th>
              <th scope="col" class="py-3.5 px-4">Rank</th>
              <th scope="col" class="py-3.5 px-4">Reliability</th>
              <th v-if="store.isSuperAdmin" scope="col" class="py-3.5 px-4">Role & Officer Title (Super Admin)</th>
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
              <td class="py-3.5 px-4">
                <div class="flex items-center space-x-3">
                  <div class="w-9 h-9 rounded-xl overflow-hidden flex-shrink-0 border border-slate-200 dark:border-neutral-700 bg-blue-600 text-white flex items-center justify-center font-black text-xs shadow-xs">
                    <img v-if="member.profile_picture" :src="member.profile_picture" :alt="member.name" class="w-full h-full object-cover" />
                    <span v-else>{{ member.avatar }}</span>
                  </div>
                  <div class="min-w-0">
                    <div class="flex items-center space-x-1.5 flex-wrap">
                      <span class="font-black text-slate-900 dark:text-white text-xs truncate max-w-[160px] lg:max-w-none">
                        {{ member.name }}
                      </span>
                      <!-- Role Badges -->
                      <span v-if="member.role === 'super_admin'" class="text-[9px] font-black uppercase bg-rose-500 text-white px-2 py-0.5 rounded-md">
                        IT Admin
                      </span>
                      <span v-else-if="member.executive_title" class="text-[9px] font-black uppercase bg-blue-600 text-white px-2 py-0.5 rounded-md">
                        {{ member.executive_title.replace('_', ' ') }}
                      </span>
                      <span v-else-if="member.role === 'secretary_admin'" class="text-[9px] font-black uppercase bg-indigo-600 text-white px-2 py-0.5 rounded-md">
                        Secretary
                      </span>
                    </div>
                  </div>
                </div>
              </td>

              <!-- Section / Instrument (Editable by Super Admin) -->
              <td class="py-3.5 px-4">
                <select 
                  v-if="store.isSuperAdmin"
                  :value="member.instrument"
                  @change="e => changeInstrument(member, e.target.value)"
                  class="bg-slate-50 dark:bg-[#27272a] text-slate-800 dark:text-white font-bold text-xs rounded-xl p-2 border border-slate-200 dark:border-neutral-700/80 min-h-[36px] max-w-[170px] cursor-pointer"
                  title="Change Musician Instrument Section"
                >
                  <option v-for="sec in sections.filter(s => s !== 'All')" :key="sec" :value="sec">
                    {{ sec }}
                  </option>
                </select>
                <span v-else class="font-bold text-slate-700 dark:text-neutral-300 capitalize">
                  {{ member.instrument }}
                </span>
              </td>

              <!-- Rank (Toggleable if Super Admin) -->
              <td class="py-3.5 px-4">
                <button 
                  v-if="store.isSuperAdmin"
                  @click="toggleMemberRank(member)"
                  type="button"
                  :disabled="member.role === 'super_admin'"
                  class="text-[10px] font-black px-2.5 py-1 rounded-lg border transition-all flex items-center active:scale-95 disabled:opacity-50 cursor-pointer"
                  :class="member.rank === 'Senior' 
                    ? 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/40' 
                    : 'bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400 border-slate-200 dark:border-neutral-700/80'"
                  title="Click to toggle Junior / Senior rank"
                >
                  <Award class="w-3 h-3 mr-1" /> {{ member.rank }}
                </button>
                <span 
                  v-else 
                  class="text-[10px] font-black px-2.5 py-1 rounded-lg"
                  :class="member.rank === 'Senior' ? 'bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-300' : 'bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400'"
                >
                  {{ member.rank }}
                </span>
              </td>

              <!-- Reliability -->
              <td class="py-3.5 px-4">
                <span 
                  class="font-extrabold text-[11px] px-2 py-0.5 rounded-md"
                  :class="member.reliability >= 90 ? 'text-emerald-600 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-950/40' : member.reliability >= 80 ? 'text-blue-600 dark:text-blue-400 bg-blue-50 dark:bg-blue-950/40' : 'text-rose-600 dark:text-rose-400 bg-rose-50 dark:bg-rose-950/40'"
                >
                  {{ member.reliability }}%
                </span>
              </td>

              <!-- Super Admin Controls (Role & Title Selectors) -->
              <td v-if="store.isSuperAdmin" class="py-3.5 px-4">
                <div class="flex items-center space-x-2">
                  <!-- Role Selector -->
                  <select 
                    :value="member.role"
                    @change="e => changeRole(member, e.target.value)"
                    :disabled="member.role === 'super_admin' && member.id !== store.user?.id"
                    class="bg-slate-50 dark:bg-[#27272a] text-slate-800 dark:text-white font-bold text-xs rounded-xl p-2 border border-slate-200 dark:border-neutral-700/80 min-h-[36px]"
                    title="Change System Role"
                  >
                    <option value="member">Musician (Member)</option>
                    <option value="secretary_admin">Band Secretary (Admin)</option>
                    <option value="executive">Executive Officer</option>
                    <option value="super_admin">IT Super Admin</option>
                  </select>

                  <!-- Executive Title Selector -->
                  <select 
                    :value="normalizeTitle(member.executive_title) || ''"
                    @change="e => assignExecutiveTitle(member, e.target.value)"
                    class="bg-slate-50 dark:bg-[#27272a] text-slate-800 dark:text-white font-bold text-xs rounded-xl p-2 border border-slate-200 dark:border-neutral-700/80 min-h-[36px]"
                    title="Assign Executive Officer Title"
                  >
                    <option value="">None (Regular Musician)</option>
                    <option value="president">Band President</option>
                    <option value="vice_president">Band Vice President</option>
                    <option value="secretary">Band Secretary</option>
                    <option value="treasurer">Band Treasurer</option>
                    <option value="auditor">Band Auditor</option>
                    <option value="resident_conductor">Resident Conductor</option>
                    <option value="band_manager">Band Manager</option>
                  </select>
                </div>
              </td>

              <!-- Actions -->
              <td class="py-3.5 px-4 text-right">
                <div class="flex items-center justify-end space-x-1.5">
                  <button 
                    @click="openAvailabilityView(member)"
                    type="button"
                    class="p-2 text-slate-500 hover:text-blue-600 dark:hover:text-blue-400 hover:bg-blue-50 dark:hover:bg-blue-950/40 rounded-xl transition-colors cursor-pointer min-w-[36px] min-h-[36px] flex items-center justify-center"
                    title="View Availability Slots"
                  >
                    <Calendar class="w-4 h-4" />
                  </button>

                  <button 
                    v-if="store.isSuperAdmin && member.role !== 'super_admin' && member.id !== store.user?.id"
                    @click="promptDeleteMember(member)"
                    type="button"
                    class="p-2 text-rose-500 hover:text-rose-700 hover:bg-rose-50 dark:hover:bg-rose-950/40 rounded-xl transition-colors cursor-pointer min-w-[36px] min-h-[36px] flex items-center justify-center"
                    title="Delete Musician Account"
                  >
                    <Trash2 class="w-4 h-4" />
                  </button>
                </div>
              </td>
            </tr>

            <tr v-if="sortedRoster.length === 0">
              <td :colspan="store.isSuperAdmin ? 6 : 5" class="py-8 text-center text-slate-400 font-bold">
                No musicians match your search or section filter.
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- MOBILE VIEW: DYNAMIC CARDS (Hidden on Tablet/Desktop) -->
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
              <div class="w-10 h-10 rounded-2xl overflow-hidden flex-shrink-0 border border-slate-200 dark:border-neutral-700 bg-blue-600 text-white flex items-center justify-center font-black text-xs shadow-xs">
                <img v-if="member.profile_picture" :src="member.profile_picture" :alt="member.name" class="w-full h-full object-cover" />
                <span v-else>{{ member.avatar }}</span>
              </div>
              <div class="min-w-0">
                <div class="flex items-center space-x-1.5 flex-wrap">
                  <h3 class="font-black text-sm text-slate-900 dark:text-white truncate">
                    {{ member.name }}
                  </h3>
                  <!-- Badge -->
                  <span v-if="member.role === 'super_admin'" class="text-[9px] font-black uppercase bg-rose-500 text-white px-2 py-0.5 rounded">
                    IT Admin
                  </span>
                  <span v-else-if="member.executive_title" class="text-[9px] font-black uppercase bg-blue-600 text-white px-2 py-0.5 rounded">
                    {{ member.executive_title.replace('_', ' ') }}
                  </span>
                </div>
                <p class="text-xs text-slate-500 dark:text-neutral-400 capitalize mt-0.5">
                  {{ member.instrument }}
                </p>
              </div>
            </div>

            <div class="text-right shrink-0">
              <span class="text-[10px] font-extrabold px-2 py-0.5 rounded" :class="member.rank === 'Senior' ? 'bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-400' : 'bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400'">
                {{ member.rank }}
              </span>
              <p class="text-[11px] font-black text-slate-900 dark:text-white mt-1">{{ member.reliability }}% Score</p>
            </div>
          </div>

          <!-- Bottom Actions / Super Admin Mobile Controls -->
          <div v-if="store.isSuperAdmin" class="pt-2 border-t border-slate-100 dark:border-neutral-800 space-y-2">
            <div class="grid grid-cols-2 gap-2">
              <div>
                <label class="block text-[9px] font-bold text-slate-400 uppercase mb-1">System Role</label>
                <select 
                  :value="member.role"
                  @change="e => changeRole(member, e.target.value)"
                  :disabled="member.role === 'super_admin' && member.id !== store.user?.id"
                  class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-800 dark:text-white font-bold text-[11px] rounded-xl p-2 border border-slate-200 dark:border-neutral-700/80 min-h-[38px]"
                >
                  <option value="member">Musician</option>
                  <option value="secretary_admin">Secretary</option>
                  <option value="executive">Executive</option>
                  <option value="super_admin">IT Admin</option>
                </select>
              </div>

              <div>
                <label class="block text-[9px] font-bold text-slate-400 uppercase mb-1">Officer Title</label>
                <select 
                  :value="normalizeTitle(member.executive_title) || ''"
                  @change="e => assignExecutiveTitle(member, e.target.value)"
                  class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-800 dark:text-white font-bold text-[11px] rounded-xl p-2 border border-slate-200 dark:border-neutral-700/80 min-h-[38px]"
                >
                  <option value="">None</option>
                  <option value="president">President</option>
                  <option value="vice_president">Vice Pres</option>
                  <option value="secretary">Secretary</option>
                  <option value="treasurer">Treasurer</option>
                  <option value="auditor">Auditor</option>
                  <option value="resident_conductor">Conductor</option>
                  <option value="band_manager">Manager</option>
                </select>
              </div>

              <!-- Instrument Select for Super Admin on Mobile -->
              <div class="col-span-2">
                <label class="block text-[9px] font-bold text-slate-400 uppercase mb-1">Instrument Section</label>
                <select 
                  :value="member.instrument"
                  @change="e => changeInstrument(member, e.target.value)"
                  class="w-full bg-slate-50 dark:bg-[#27272a] text-slate-800 dark:text-white font-bold text-[11px] rounded-xl p-2 border border-slate-200 dark:border-neutral-700/80 min-h-[38px]"
                >
                  <option v-for="sec in sections.filter(s => s !== 'All')" :key="sec" :value="sec">
                    {{ sec }}
                  </option>
                </select>
              </div>
            </div>

            <div class="flex items-center justify-between pt-1">
              <button 
                @click="toggleMemberRank(member)"
                type="button"
                :disabled="member.role === 'super_admin'"
                class="text-[11px] font-bold text-blue-600 dark:text-blue-400 flex items-center min-h-[36px] cursor-pointer"
              >
                <Award class="w-3.5 h-3.5 mr-1" /> Toggle {{ member.rank === 'Senior' ? 'Junior' : 'Senior' }}
              </button>

              <div class="flex items-center space-x-2">
                <button 
                  @click="openAvailabilityView(member)"
                  type="button"
                  class="text-[11px] font-bold text-slate-600 dark:text-neutral-400 flex items-center px-2 py-1 bg-slate-100 dark:bg-[#27272a] rounded-lg min-h-[36px] cursor-pointer"
                >
                  <Calendar class="w-3.5 h-3.5 mr-1" /> Availability
                </button>

                <button 
                  v-if="member.role !== 'super_admin' && member.id !== store.user?.id"
                  @click="promptDeleteMember(member)"
                  type="button"
                  class="text-[11px] font-bold text-rose-500 hover:text-rose-700 flex items-center px-2 py-1 bg-rose-50 dark:bg-rose-950/40 rounded-lg min-h-[36px] cursor-pointer"
                >
                  <Trash2 class="w-3.5 h-3.5 mr-1" /> Delete
                </button>
              </div>
            </div>
          </div>

          <!-- Non-Super Admin Mobile Bottom Bar -->
          <div v-else class="pt-2 border-t border-slate-100 dark:border-neutral-800 flex items-center justify-between">
            <button 
              @click="openAvailabilityView(member)"
              type="button"
              class="text-xs font-bold text-blue-600 dark:text-blue-400 flex items-center cursor-pointer min-h-[36px]"
            >
              <Calendar class="w-3.5 h-3.5 mr-1" /> View Availability Slots
            </button>
          </div>
        </div>

        <div v-if="sortedRoster.length === 0" class="bg-white dark:bg-[#1c1c1e] rounded-3xl p-8 text-center border border-slate-200 dark:border-neutral-800">
          <Users class="w-8 h-8 text-slate-400 mx-auto mb-2 opacity-60" />
          <p class="text-xs font-bold text-slate-500">No musicians match your filter.</p>
        </div>
      </div>
    </section>

    <!-- 5. MEMBER AVAILABILITY MODAL -->
    <div v-if="showAvailabilityModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div>
            <span class="text-[10px] font-black text-blue-500 uppercase tracking-wider">Availability Overview</span>
            <h3 class="font-black text-base text-slate-900 dark:text-white truncate">{{ selectedMember?.name }}</h3>
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
            <p v-if="selectedMember?.id === store.user?.id" class="text-[11px] text-blue-500">
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

    <!-- 6. SUPER ADMIN DELETE CONFIRMATION MODAL -->
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
