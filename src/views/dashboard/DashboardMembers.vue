<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { Users, Search, Award, TrendingUp, Music, Shield, MoreVertical, X, Calendar, CheckCircle2, UserX, AlertTriangle, Filter, ChevronDown } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const store = useMainStore()

const searchQuery = ref('')
const activeFilter = ref('All')
const members = ref([])
const isLoading = ref(true)

// Member Edit / Availability Modal Sheet State
const showMemberEditModal = ref(false)
const selectedMember = ref(null)
const memberAvailabilitySlots = ref([])
const editRank = ref('Junior')
const editInstrument = ref('trumpet')
const editExecutiveTitle = ref('')
const isSavingMember = ref(false)

// Realtime Channel Reference
let membersChannel = null

// FULL MUNICIPAL BAND SECTION LIST FOR DIRECTORY FILTERING
const sections = [
  'All', 
  'Clarinet', 
  'Bass Clarinet',
  'Flute', 
  'Piccolo',
  'French Horn', 
  'Tenor Sax',
  'Sax (Alto Sax)', 
  'Baritone Sax',
  'Trumpet', 
  'Trombone', 
  'Bass Trombone',
  'Baritone / Euphonium', 
  'Bass / Tuba', 
  'Bass Drum',
  'Snare Drum / Drums', 
  'Cymbals'
]

// "PA-IMPORTANTE" ATTENDANCE LIST (Reliability < 85%)
const paImportanteList = computed(() => {
  return members.value.filter(m => (m.reliability || 100) < 85)
})

const filteredMembers = computed(() => {
  return members.value.filter(member => {
    const matchesSearch = member.name.toLowerCase().includes(searchQuery.value.toLowerCase()) ||
                          member.instrument.toLowerCase().includes(searchQuery.value.toLowerCase()) ||
                          (member.role && member.role.toLowerCase().includes(searchQuery.value.toLowerCase())) ||
                          (member.executive_title && member.executive_title.toLowerCase().includes(searchQuery.value.toLowerCase()))
    
    if (activeFilter.value === 'All') return matchesSearch
    
    const filterKey = activeFilter.value.toLowerCase().split('(')[0].trim()
    const matchesSection = member.instrument.toLowerCase().includes(filterKey)
    
    return matchesSearch && matchesSection
  })
})

const sortedAndFilteredRoster = computed(() => {
  return [...filteredMembers.value].sort((a, b) => {
    if (a.executive_title && !b.executive_title) return -1
    if (!a.executive_title && b.executive_title) return 1
    if (a.role === 'super_admin' && b.role !== 'super_admin') return -1
    if (a.role !== 'super_admin' && b.role === 'super_admin') return 1
    if (a.rank === 'Senior' && b.rank !== 'Senior') return -1
    if (a.rank !== 'Senior' && b.rank === 'Senior') return 1
    return a.name.localeCompare(b.name)
  })
})

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
    const { data } = await supabase
      .from('profiles')
      .select('*')
      .eq('is_verified', true)
      .order('full_name', { ascending: true })

    if (data) {
      members.value = data.map(m => ({
        id: m.id,
        name: m.full_name,
        instrument: m.instrument || 'Musician',
        rank: m.rank || 'Junior',
        role: m.role || 'member',
        executive_title: m.executive_title || null,
        reliability: m.reliability_score || 100,
        avatar: m.full_name ? m.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB',
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

const openMemberEdit = async (member) => {
  selectedMember.value = member
  editRank.value = member.rank || 'Junior'
  editInstrument.value = member.instrument || 'trumpet'
  editExecutiveTitle.value = member.executive_title || ''
  showMemberEditModal.value = true
  memberAvailabilitySlots.value = []

  try {
    const { data } = await supabase
      .from('member_availability')
      .select('day_of_week, time_slot, is_available')
      .eq('user_id', member.id)
      .eq('is_available', true)

    if (data && data.length > 0) {
      memberAvailabilitySlots.value = data.map(d => `${d.day_of_week.toUpperCase()} (${d.time_slot})`)
    }
  } catch (err) {
    console.error('Error fetching member availability:', err)
  }
}

const saveMemberEdits = async () => {
  if (!selectedMember.value) return
  isSavingMember.value = true

  try {
    const updates = {
      rank: editRank.value,
      instrument: editInstrument.value
    }
    if (store.isSuperAdmin) {
      updates.executive_title = editExecutiveTitle.value || null
    }

    const { error } = await supabase
      .from('profiles')
      .update(updates)
      .eq('id', selectedMember.value.id)

    if (!error) {
      selectedMember.value.rank = editRank.value
      selectedMember.value.instrument = editInstrument.value
      selectedMember.value.executive_title = editExecutiveTitle.value || null
      showMemberEditModal.value = false
      await fetchRoster(true)
    }
  } catch (err) {
    console.error('Error saving member edits:', err)
  } finally {
    isSavingMember.value = false
  }
}

const toggleMemberRank = async (member) => {
  const newRank = member.rank === 'Senior' ? 'Junior' : 'Senior'
  const { error } = await supabase
    .from('profiles')
    .update({ rank: newRank })
    .eq('id', member.id)

  if (!error) {
    member.rank = newRank
    await fetchRoster(true)
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
  <div class="p-4 sm:p-5 space-y-6">
    
    <header class="pt-1 flex items-center justify-between">
      <div>
        <p class="text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase tracking-wider">Band Directory & Availability</p>
        <h1 class="text-2xl font-black text-slate-900 dark:text-white">Band Roster</h1>
      </div>
      <div class="p-2.5 rounded-2xl bg-blue-500/10 text-blue-600 dark:text-blue-400 shadow-xs">
        <Users class="w-5 h-5" />
      </div>
    </header>

    <!-- Search Bar for All Users -->
    <div class="relative">
      <div class="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-slate-400 dark:text-neutral-500">
        <Search class="w-4 h-4" />
      </div>
      <input 
        v-model="searchQuery"
        type="text" 
        placeholder="Search by name, instrument, role, or title..."
        class="w-full pl-10 pr-4 py-3 bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-2xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-all text-xs font-semibold shadow-xs min-h-[44px]"
      >
    </div>

    <!-- "PA-IMPORTANTE" ATTENDANCE BEHAVIOR MONITOR -->
    <section v-if="store.canPromoteMembers && paImportanteList.length > 0" class="bg-rose-50 dark:bg-rose-950/30 border border-rose-200 dark:border-rose-900/50 rounded-3xl p-4 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2 text-rose-700 dark:text-rose-300">
          <UserX class="w-5 h-5" />
          <h2 class="font-extrabold text-xs uppercase tracking-wider">"Pa-Importante" Attendance Monitor</h2>
        </div>
        <span class="text-[11px] font-black bg-rose-200 dark:bg-rose-900/80 text-rose-900 dark:text-rose-200 px-2.5 py-0.5 rounded-full">
          {{ paImportanteList.length }} Low Score
        </span>
      </div>

      <p class="text-[11px] text-slate-600 dark:text-neutral-400 leading-relaxed">
        Members with reliability scores under 85%. Use for promotion or gig prioritization decisions.
      </p>

      <div class="space-y-2">
        <div v-for="item in paImportanteList" :key="item.id" class="bg-white dark:bg-[#1c1c1e] p-3 rounded-2xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between">
          <div class="flex items-center space-x-2.5">
            <div class="w-8 h-8 rounded-full bg-rose-100 dark:bg-rose-950/60 text-rose-600 dark:text-rose-400 font-bold text-xs flex items-center justify-center">
              {{ item.avatar }}
            </div>
            <div>
              <p class="font-bold text-xs text-slate-900 dark:text-white">{{ item.name }} ({{ item.instrument }})</p>
              <p class="text-[10px] text-rose-500 font-extrabold">Score: {{ item.reliability }}%</p>
            </div>
          </div>
          <button 
            @click="toggleMemberRank(item)" 
            class="px-2.5 py-1.5 bg-amber-500 hover:bg-amber-600 text-slate-900 font-extrabold text-[10px] rounded-lg min-h-[36px] cursor-pointer"
          >
            Demote Rank
          </button>
        </div>
      </div>
    </section>

    <!-- Section Filter Dropdown -->
    <div class="relative z-10 inline-block w-auto mt-1 mb-2">
      <div class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none">
        <Filter class="w-4 h-4 text-slate-400" />
      </div>
      <select 
        v-model="activeFilter"
        class="w-auto min-w-[200px] bg-white dark:bg-[#1c1c1e] border border-slate-200/80 dark:border-neutral-800 text-slate-900 dark:text-white text-sm font-bold rounded-2xl focus:ring-blue-500 focus:border-blue-500 block pl-10 pr-10 p-2.5 appearance-none cursor-pointer shadow-xs min-h-[44px]"
        aria-label="Filter members by section"
      >
        <option v-for="sec in sections" :key="sec" :value="sec">{{ sec === 'All' ? 'All Sections' : sec }}</option>
      </select>
      <div class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none">
        <ChevronDown class="w-4 h-4 text-slate-400" />
      </div>
    </div>

    <!-- Member Directory List (Lighter Matte Black) -->
    <section class="space-y-3">
      <div v-if="sortedAndFilteredRoster.length > 0" class="grid grid-cols-1 gap-3">
        <div 
          v-for="member in sortedAndFilteredRoster" 
          :key="member.id"
          class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 flex items-center justify-between"
          :class="member.executive_title ? 'border-l-4 border-l-blue-600' : ''"
        >
          <div class="flex items-center space-x-3 min-w-0 pr-2">
            <div 
              v-if="member.profile_picture"
              class="w-11 h-11 rounded-2xl flex-shrink-0 overflow-hidden shadow-xs border"
              :class="member.executive_title ? 'border-blue-500 shadow-md' : 'border-slate-200 dark:border-neutral-700'"
            >
              <img :src="member.profile_picture" alt="Avatar" class="w-full h-full object-cover" />
            </div>
            <div 
              v-else
              class="w-11 h-11 rounded-2xl flex items-center justify-center font-black text-sm flex-shrink-0 border"
              :class="member.executive_title ? 'bg-blue-600 text-white border-blue-500 shadow-md' : 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/20'"
            >
              {{ member.avatar }}
            </div>
            <div class="min-w-0">
              <h3 class="font-bold text-sm text-slate-900 dark:text-white truncate flex items-center flex-wrap">
                <span>{{ member.name }}</span>
                <span v-if="member.executive_title" class="ml-2 text-[9px] font-black uppercase bg-blue-600 text-white px-2 py-0.5 rounded shadow-xs">
                  {{ member.executive_title }}
                </span>
                <span v-else-if="member.role === 'super_admin'" class="ml-2 text-[9px] font-black uppercase bg-rose-500 text-white px-2 py-0.5 rounded">
                  IT Admin
                </span>
              </h3>
              <p class="text-xs text-slate-500 dark:text-neutral-400 font-medium flex items-center mt-0.5 capitalize">
                <Music class="w-3 h-3 mr-1 text-slate-400" />
                {{ member.instrument }}
              </p>
            </div>
          </div>

          <div class="flex items-center space-x-1">
            <div class="text-right flex-shrink-0">
              <span class="text-[10px] font-extrabold px-2 py-0.5 rounded-md" :class="member.rank === 'Senior' ? 'bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-400 border border-blue-300 dark:border-blue-800/40' : 'bg-slate-100 dark:bg-[#27272a] text-slate-600 dark:text-neutral-400'">
                {{ member.rank }} Rank
              </span>
              <p class="text-[11px] font-black text-slate-900 dark:text-white mt-1">{{ member.reliability }}% Score</p>
            </div>

            <!-- Secretary / Admin 3-Dot Management Button -->
            <button 
              v-if="store.canPromoteMembers || store.isSuperAdmin"
              @click="openMemberEdit(member)"
              type="button"
              class="p-2 rounded-xl text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-[#27272a] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"
              aria-label="Manage Member Details & Availability"
            >
              <MoreVertical class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      <div v-else class="bg-white dark:bg-[#1c1c1e] rounded-2xl p-8 text-center border border-slate-200 dark:border-neutral-800">
        <Users class="w-8 h-8 text-slate-400 dark:text-neutral-500 mx-auto mb-2" />
        <p class="text-sm font-bold text-slate-700 dark:text-neutral-300">No verified members found in this search.</p>
      </div>
    </section>

    <!-- SECRETARY / ADMIN MEMBER EDIT & AVAILABILITY OVERVIEW MODAL SHEET -->
    <div v-if="showMemberEditModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left max-h-[85vh] flex flex-col">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div>
            <span class="text-[10px] font-black text-blue-500 uppercase">Member Profile & Availability</span>
            <h3 class="font-black text-base text-slate-900 dark:text-white truncate">{{ selectedMember?.name }}</h3>
          </div>
          <button @click="showMemberEditModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div class="overflow-y-auto flex-1 space-y-4 pr-1">
          
          <!-- Member's Weekly Free Slots Display -->
          <div class="p-3 bg-blue-500/10 border border-blue-500/30 rounded-2xl space-y-2">
            <div class="flex items-center space-x-1.5 text-xs font-black text-blue-600 dark:text-blue-400">
              <Calendar class="w-4 h-4" />
              <span>Weekly Free Availability Slots</span>
            </div>
            
            <div v-if="memberAvailabilitySlots.length > 0" class="flex flex-wrap gap-1.5">
              <span v-for="slot in memberAvailabilitySlots" :key="slot" class="text-[10px] font-black bg-emerald-100 dark:bg-emerald-950/60 text-emerald-700 dark:text-emerald-400 px-2 py-0.5 rounded-md border border-emerald-300 dark:border-emerald-800/40">
                ✓ {{ slot }}
              </span>
            </div>
            
            <p v-else class="text-[11px] text-slate-500 dark:text-neutral-400 font-medium">No free slots specified by member for this week yet.</p>
          </div>

          <!-- Officer Controls -->
          <div class="space-y-3">
            <div>
              <label for="mod-rank" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Member Rank</label>
              <select id="mod-rank" v-model="editRank" class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
                <option value="Junior">Junior Rank</option>
                <option value="Senior">Senior Rank</option>
              </select>
            </div>

            <div>
              <label for="mod-instrument" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Instrument Section</label>
              <select id="mod-instrument" v-model="editInstrument" class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
                <option v-for="sec in sections.filter(s => s !== 'All')" :key="sec" :value="sec">{{ sec }}</option>
              </select>
            </div>

            <div v-if="store.isSuperAdmin">
              <label for="mod-exec" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Executive Officer Title (IT Admin Only)</label>
              <select id="mod-exec" v-model="editExecutiveTitle" class="w-full p-3 bg-slate-50 dark:bg-[#27272a] border border-slate-200 dark:border-neutral-700/80 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
                <option value="">None</option>
                <option value="president">President</option>
                <option value="vice_president">Vice President</option>
                <option value="treasurer">Treasurer</option>
              </select>
            </div>
          </div>

        </div>

        <div class="flex space-x-2 pt-2 border-t border-slate-100 dark:border-neutral-800">
          <button @click="showMemberEditModal = false" type="button" class="flex-1 py-3 bg-rose-50 dark:bg-rose-950/40 text-rose-600 dark:text-rose-400 font-bold text-xs border border-rose-200 dark:border-rose-900/40 hover:bg-rose-100 rounded-xl min-h-[44px] cursor-pointer">Cancel</button>
          <button @click="saveMemberEdits" :disabled="isSavingMember" type="button" class="flex-1 py-3 bg-blue-600 hover:bg-blue-500 font-black text-xs text-white rounded-xl shadow-md min-h-[44px] cursor-pointer">Save Changes</button>
        </div>
      </div>
    </div>

  </div>
</template>

<style scoped>
.hide-scrollbar::-webkit-scrollbar {
  display: none;
}
.hide-scrollbar {
  -ms-overflow-style: none;
  scrollbar-width: none;
}
</style>
