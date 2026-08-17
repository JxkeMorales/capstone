<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { Users, Music, Activity, Search, MoreVertical, Award, Shield, X, CheckCircle2, UserX, AlertTriangle, ChevronUp, Calendar } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const store = useMainStore()
const roster = ref([])
const paImportanteList = ref([])
const activeFilter = ref('All')
const selectedDayFilter = ref('All')
const searchQuery = ref('')
const isLoading = ref(true)

// Realtime Channel Reference
let membersChannel = null

// Member Edit & Availability Overview Modal State
const showMemberEditModal = ref(false)
const selectedMember = ref(null)
const memberAvailabilitySlots = ref([])
const editRank = ref('Junior')
const editInstrument = ref('Trumpet')
const editExecutiveTitle = ref('')
const isSavingMember = ref(false)

const sections = [
  'All', 
  'Officers', 
  'Clarinet', 
  'Flute', 
  'Saxophone', 
  'Trumpet', 
  'Trombone', 
  'Horn / Euphonium', 
  'Tuba / Bass', 
  'Percussion / Drums'
]
const weekDays = ['All', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

const fetchRoster = async (skipCache = false) => {
  if (!skipCache) {
    isLoading.value = true
    const cachedRoster = localStorage.getItem('smartband_roster_cache')
    if (cachedRoster) {
      try {
        roster.value = JSON.parse(cachedRoster)
        paImportanteList.value = roster.value.filter(m => m.reliability < 85)
      } catch (e) {}
    }
  }

  try {
    const { data } = await supabase
      .from('public_roster')
      .select('*')
      .order('full_name', { ascending: true })

    if (data) {
      roster.value = data.map(m => ({
        id: m.id,
        name: m.full_name,
        email: m.email || '',
        instrument: m.instrument || 'Musician',
        rank: m.rank || 'Junior',
        executive_title: m.executive_title || null,
        role: m.role || 'member',
        reliability: m.reliability_score || 100,
        avatar: m.full_name ? m.full_name.split(' ').map(n=>n[0]).join('').slice(0,2).toUpperCase() : 'MB'
      }))

      paImportanteList.value = roster.value.filter(m => m.reliability < 85)
      localStorage.setItem('smartband_roster_cache', JSON.stringify(roster.value))
    }
  } catch (err) {
    console.error('Error fetching roster:', err)
  } finally {
    isLoading.value = false
  }
}

// Executive Officers (President, VP, Secretary, Treasurer) and IT Admin Pinned to Top
const sortedAndFilteredRoster = computed(() => {
  let list = roster.value.filter(m => {
    let matchesSection = false
    if (activeFilter.value === 'All') {
      matchesSection = true
    } else if (activeFilter.value === 'Officers') {
      matchesSection = !!(m.executive_title || m.role === 'secretary_admin' || m.role === 'super_admin')
    } else {
      const filterKey = activeFilter.value.toLowerCase().split('/')[0].trim()
      matchesSection = m.instrument.toLowerCase().includes(filterKey)
    }

    const q = searchQuery.value.toLowerCase()
    const matchesSearch = m.name.toLowerCase().includes(q) 
      || m.instrument.toLowerCase().includes(q)
      || (m.executive_title && m.executive_title.toLowerCase().includes(q))
      || (m.role && m.role.toLowerCase().includes(q))

    return matchesSection && matchesSearch
  })

  const officerWeight = (m) => {
    const t = (m.executive_title || '').toLowerCase()
    if (t === 'president') return 1
    if (t === 'vice_president' || t === 'vice president') return 2
    if (t === 'secretary' || m.role === 'secretary_admin') return 3
    if (t === 'treasurer') return 4
    if (m.role === 'super_admin') return 5
    return 10
  }

  return list.sort((a, b) => {
    const weightA = officerWeight(a)
    const weightB = officerWeight(b)
    if (weightA !== weightB) return weightA - weightB
    return a.name.localeCompare(b.name)
  })
})

// OPEN MEMBER EDIT & FETCH MEMBER'S WEEKLY AVAILABILITY SLOTS
const openMemberEdit = async (member) => {
  selectedMember.value = member
  editRank.value = member.rank
  editInstrument.value = member.instrument.toLowerCase()
  editExecutiveTitle.value = member.executive_title || ''
  memberAvailabilitySlots.value = []
  showMemberEditModal.value = true

  try {
    const { data: avail } = await supabase
      .from('member_availability')
      .select('day_of_week, time_slot')
      .eq('user_id', member.id)
      .eq('is_free', true)

    if (avail) {
      memberAvailabilitySlots.value = avail.map(a => `${a.day_of_week} ${a.time_slot.split(' ')[0]}`)
    }
  } catch (e) {
    console.error(e)
  }
}

// SAVE MEMBER EDITS
const saveMemberEdits = async () => {
  if (!selectedMember.value) return
  isSavingMember.value = true

  try {
    const updatePayload = {
      rank: editRank.value,
      instrument: editInstrument.value
    }

    if (store.isSuperAdmin) {
      updatePayload.executive_title = editExecutiveTitle.value || null
    }

    const { error } = await supabase
      .from('profiles')
      .update(updatePayload)
      .eq('id', selectedMember.value.id)

    if (error) throw error

    selectedMember.value.rank = editRank.value
    selectedMember.value.instrument = editInstrument.value
    if (store.isSuperAdmin) {
      selectedMember.value.executive_title = editExecutiveTitle.value || null
    }

    localStorage.setItem('smartband_roster_cache', JSON.stringify(roster.value))
    showMemberEditModal.value = false
    alert(`Updated ${selectedMember.value.name}'s details successfully!`)
  } catch (err) {
    console.error('Error updating member:', err)
    alert(err?.message || 'Failed to update member.')
  } finally {
    isSavingMember.value = false
  }
}

// FAST TOGGLE RANK
const toggleMemberRank = async (member) => {
  const newRank = member.rank === 'Junior' ? 'Senior' : 'Junior'
  const { error } = await supabase
    .from('profiles')
    .update({ rank: newRank })
    .eq('id', member.id)

  if (!error) {
    member.rank = newRank
    localStorage.setItem('smartband_roster_cache', JSON.stringify(roster.value))
  }
}

onMounted(() => {
  fetchRoster()

  // CONNECT SUPABASE REALTIME WEBSOCKET SUBSCRIPTION
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
      <div class="p-2.5 rounded-2xl bg-white dark:bg-[#121214] border border-slate-200 dark:border-neutral-800 text-yellow-500 shadow-xs">
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
        class="w-full pl-10 pr-4 py-3 bg-white dark:bg-[#121214] border border-slate-200 dark:border-neutral-800 rounded-2xl text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-neutral-500 focus:outline-none focus:ring-2 focus:ring-yellow-400 transition-all text-xs font-semibold shadow-xs min-h-[44px]"
      >
    </div>

    <!-- "PA-IMPORTANTE" ATTENDANCE BEHAVIOR MONITOR -->
    <section v-if="store.canPromoteMembers && paImportanteList.length > 0" class="bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-900/50 rounded-3xl p-4 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2 text-red-700 dark:text-red-300">
          <UserX class="w-5 h-5" />
          <h2 class="font-extrabold text-xs uppercase tracking-wider">"Pa-Importante" Attendance Monitor</h2>
        </div>
        <span class="text-[11px] font-black bg-red-200 dark:bg-red-900/80 text-red-900 dark:text-red-200 px-2.5 py-0.5 rounded-full">
          {{ paImportanteList.length }} Low Score
        </span>
      </div>

      <p class="text-[11px] text-slate-600 dark:text-neutral-400 leading-relaxed">
        Members with reliability scores under 85%. Use for promotion or gig prioritization decisions.
      </p>

      <div class="space-y-2">
        <div v-for="item in paImportanteList" :key="item.id" class="bg-white dark:bg-[#121214] p-3 rounded-2xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between">
          <div class="flex items-center space-x-2.5">
            <div class="w-8 h-8 rounded-full bg-red-100 dark:bg-red-950/60 text-red-600 dark:text-red-400 font-bold text-xs flex items-center justify-center">
              {{ item.avatar }}
            </div>
            <div>
              <p class="font-bold text-xs text-slate-900 dark:text-white">{{ item.name }} ({{ item.instrument }})</p>
              <p class="text-[10px] text-red-500 font-extrabold">Score: {{ item.reliability }}%</p>
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

    <!-- Section Filter Pills -->
    <div class="flex overflow-x-auto hide-scrollbar space-x-2 pb-1" role="tablist">
      <button 
        v-for="sec in sections" 
        :key="sec"
        @click="activeFilter = sec"
        type="button"
        role="tab"
        :aria-selected="activeFilter === sec"
        class="px-3.5 py-2 rounded-xl text-xs font-bold whitespace-nowrap transition-all active:scale-95 cursor-pointer min-h-[44px] flex items-center"
        :class="activeFilter === sec 
          ? 'bg-slate-900 dark:bg-white text-white dark:text-black shadow-xs' 
          : 'bg-white dark:bg-[#121214] text-slate-600 dark:text-neutral-400 hover:bg-slate-100 dark:hover:bg-[#1c1c1e] border border-slate-200/80 dark:border-neutral-800'"
      >
        {{ sec }}
      </button>
    </div>

    <!-- Member Directory List -->
    <section class="space-y-3">
      <div v-if="sortedAndFilteredRoster.length > 0" class="grid grid-cols-1 gap-3">
        <div 
          v-for="member in sortedAndFilteredRoster" 
          :key="member.id"
          class="bg-white dark:bg-[#121214] rounded-2xl p-4 shadow-xs border border-slate-200/80 dark:border-neutral-800 flex items-center justify-between"
          :class="member.executive_title ? 'border-l-4 border-l-yellow-400' : ''"
        >
          <div class="flex items-center space-x-3 min-w-0 pr-2">
            <div 
              class="w-11 h-11 rounded-2xl flex items-center justify-center font-black text-sm flex-shrink-0 border"
              :class="member.executive_title ? 'bg-yellow-400 text-slate-900 border-yellow-500 shadow-md' : 'bg-yellow-400/20 text-slate-900 dark:text-yellow-400 border-yellow-400/30'"
            >
              {{ member.avatar }}
            </div>
            <div class="min-w-0">
              <h3 class="font-bold text-sm text-slate-900 dark:text-white truncate flex items-center flex-wrap">
                <span>{{ member.name }}</span>
                <span v-if="member.executive_title" class="ml-2 text-[9px] font-black uppercase bg-yellow-400 text-slate-900 px-2 py-0.5 rounded shadow-xs">
                  {{ member.executive_title }}
                </span>
                <span v-else-if="member.role === 'super_admin'" class="ml-2 text-[9px] font-black uppercase bg-red-500 text-white px-2 py-0.5 rounded">
                  IT Admin
                </span>
              </h3>
              <p class="text-xs text-slate-500 dark:text-neutral-400 font-medium flex items-center mt-0.5 capitalize">
                <Music class="w-3 h-3 mr-1 text-slate-400" />
                {{ member.instrument }}
              </p>
            </div>
          </div>

          <div class="flex items-center space-x-2">
            <div class="text-right flex-shrink-0">
              <span class="text-[10px] font-extrabold px-2 py-0.5 rounded-md" :class="member.rank === 'Senior' ? 'bg-yellow-100 dark:bg-yellow-950/60 text-yellow-700 dark:text-yellow-400' : 'bg-slate-100 dark:bg-[#1c1c1e] text-slate-600 dark:text-neutral-400'">
                {{ member.rank }} Rank
              </span>
              <p class="text-[11px] font-black text-slate-900 dark:text-white mt-1">{{ member.reliability }}% Score</p>
            </div>

            <!-- Secretary / Admin 3-Dot Management Button -->
            <button 
              v-if="store.canPromoteMembers || store.isSuperAdmin"
              @click="openMemberEdit(member)"
              type="button"
              class="p-2 rounded-xl text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-[#1c1c1e] min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"
              aria-label="Manage Member Details & Availability"
            >
              <MoreVertical class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      <div v-else class="bg-white dark:bg-[#121214] rounded-2xl p-8 text-center border border-slate-200 dark:border-neutral-800">
        <Users class="w-8 h-8 text-slate-400 dark:text-neutral-500 mx-auto mb-2" />
        <p class="text-sm font-bold text-slate-700 dark:text-neutral-300">No verified members found in this search.</p>
      </div>
    </section>

    <!-- SECRETARY / ADMIN MEMBER EDIT & AVAILABILITY OVERVIEW MODAL SHEET -->
    <div v-if="showMemberEditModal" class="fixed inset-0 bg-black/80 backdrop-blur-xs z-50 flex items-center justify-center p-4">
      <div class="bg-white dark:bg-[#121214] border border-slate-200 dark:border-neutral-800 rounded-3xl p-6 max-w-sm w-full space-y-4 shadow-2xl text-left max-h-[85vh] flex flex-col">
        <div class="flex items-center justify-between border-b border-slate-100 dark:border-neutral-800 pb-3">
          <div>
            <span class="text-[10px] font-black text-yellow-500 uppercase">Member Profile & Availability</span>
            <h3 class="font-black text-base text-slate-900 dark:text-white truncate">{{ selectedMember?.name }}</h3>
          </div>
          <button @click="showMemberEditModal = false" class="text-slate-400 hover:text-white min-w-[44px] min-h-[44px] flex items-center justify-center cursor-pointer"><X class="w-5 h-5" /></button>
        </div>

        <div class="overflow-y-auto flex-1 space-y-4 pr-1">
          
          <!-- Member's Weekly Free Slots Display -->
          <div class="p-3 bg-yellow-400/10 border border-yellow-400/30 rounded-2xl space-y-2">
            <div class="flex items-center space-x-1.5 text-xs font-black text-yellow-600 dark:text-yellow-400">
              <Calendar class="w-4 h-4" />
              <span>Weekly Free Availability Slots</span>
            </div>
            
            <div v-if="memberAvailabilitySlots.length > 0" class="flex flex-wrap gap-1.5">
              <span v-for="slot in memberAvailabilitySlots" :key="slot" class="text-[10px] font-black bg-green-100 dark:bg-green-950/60 text-green-700 dark:text-green-400 px-2 py-0.5 rounded-md border border-green-300 dark:border-green-800/40">
                ✓ {{ slot }}
              </span>
            </div>
            
            <p v-else class="text-[11px] text-slate-500 dark:text-neutral-400 font-medium">No free slots specified by member for this week yet.</p>
          </div>

          <!-- Officer Controls -->
          <div class="space-y-3">
            <div>
              <label for="mod-rank" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Member Rank</label>
              <select id="mod-rank" v-model="editRank" class="w-full p-3 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
                <option value="Junior">Junior Rank</option>
                <option value="Senior">Senior Rank</option>
              </select>
            </div>

            <div>
              <label for="mod-instrument" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Instrument Section</label>
              <select id="mod-instrument" v-model="editInstrument" class="w-full p-3 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
                <option value="trumpet">Trumpet</option>
                <option value="trombone">Trombone</option>
                <option value="saxophone">Saxophone</option>
                <option value="drums">Drums / Percussion</option>
                <option value="flute">Flute</option>
                <option value="clarinet">Clarinet</option>
              </select>
            </div>

            <div v-if="store.isSuperAdmin">
              <label for="mod-exec" class="block text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase mb-1">Executive Officer Title (IT Admin Only)</label>
              <select id="mod-exec" v-model="editExecutiveTitle" class="w-full p-3 bg-slate-50 dark:bg-[#1c1c1e] border border-slate-200 dark:border-neutral-800 rounded-xl text-xs font-bold text-slate-900 dark:text-white min-h-[44px]">
                <option value="">None</option>
                <option value="president">President</option>
                <option value="vice_president">Vice President</option>
                <option value="treasurer">Treasurer</option>
              </select>
            </div>
          </div>

        </div>

        <div class="flex space-x-2 pt-2 border-t border-slate-100 dark:border-neutral-800">
          <button @click="showMemberEditModal = false" type="button" class="flex-1 py-3 bg-slate-100 dark:bg-[#27272a] font-bold text-xs rounded-xl text-slate-700 dark:text-neutral-300 min-h-[44px] cursor-pointer">Cancel</button>
          <button @click="saveMemberEdits" :disabled="isSavingMember" type="button" class="flex-1 py-3 bg-yellow-400 font-black text-xs text-slate-900 rounded-xl shadow-md min-h-[44px] cursor-pointer">Save Changes</button>
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
