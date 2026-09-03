<script setup>
import { ref, onMounted } from 'vue'
import { Trophy, Activity, CheckCircle2, AlertTriangle, BarChart3, ChevronUp, UserX, AlertCircle } from 'lucide-vue-next'
import { useMainStore } from '@/stores/main'
import { supabase } from '@/supabase'

const store = useMainStore()
const leaderboard = ref([])
const paImportanteList = ref([])
const isLoading = ref(true)

const fetchLeaderboard = async () => {
  isLoading.value = true
  try {
    const { data } = await supabase
      .from('public_roster')
      .select('*')
      .order('reliability_score', { ascending: false })

    if (data) {
      leaderboard.value = data.map(m => ({
        id: m.id,
        name: m.full_name,
        section: m.instrument || 'Musician',
        score: m.reliability_score || 100,
        rank: m.rank || 'Junior',
        avatar: m.full_name ? m.full_name.split(' ').map(n => n[0]).join('').slice(0,2).toUpperCase() : 'MB',
        profile_picture: m.profile_picture || null
      }))

      // Flag "Pa-Importante" behavior: Members with reliability score < 80% or low attendance
      paImportanteList.value = leaderboard.value.filter(m => m.score < 85)
    }
  } catch (err) {
    console.error('Error fetching leaderboard:', err)
  } finally {
    isLoading.value = false
  }
}

const toggleMemberRank = async (member) => {
  const newRank = member.rank === 'Junior' ? 'Senior' : 'Junior'
  const { error } = await supabase
    .from('profiles')
    .update({ rank: newRank })
    .eq('id', member.id)

  if (!error) {
    member.rank = newRank
  }
}

onMounted(() => {
  fetchLeaderboard()
})
</script>

<template>
  <div class="p-4 sm:p-5 space-y-6">
    
    <header class="pt-1 flex items-center justify-between">
      <div>
        <p class="text-xs font-bold text-slate-400 dark:text-neutral-500 uppercase tracking-wider">Attendance Analytics</p>
        <h1 class="text-2xl font-black text-slate-900 dark:text-white">Reliability & Ranks</h1>
      </div>
      <span v-if="store.canViewExecutiveAnalytics" class="text-xs font-black bg-blue-100 dark:bg-blue-950/60 text-blue-700 dark:text-blue-400 border dark:border-blue-800/40 px-2.5 py-1.5 rounded-xl flex items-center">
        <BarChart3 class="w-3.5 h-3.5 mr-1" /> Analytics Active
      </span>
    </header>

    <!-- Personal Reliability Dashboard -->
    <section class="bg-gradient-to-br from-neutral-900 via-[#121212] to-black rounded-3xl p-5 shadow-lg relative overflow-hidden text-white border border-neutral-800">
      <div class="absolute -right-8 -bottom-8 w-36 h-36 bg-yellow-400 opacity-20 rounded-full blur-2xl pointer-events-none"></div>
      
      <div class="relative z-10">
        <div class="flex justify-between items-start mb-4">
          <div>
            <span class="text-xs font-bold text-neutral-400 uppercase tracking-wider">My Reliability Score</span>
            <div class="flex items-baseline mt-1">
              <span class="text-5xl font-black text-yellow-400 leading-none">{{ store.profile?.reliability_score || 100 }}</span>
              <span class="text-xl font-extrabold text-yellow-400/80 ml-0.5">%</span>
            </div>
          </div>
          <div class="bg-white/10 dark:bg-neutral-800/80 px-3.5 py-2.5 rounded-2xl border border-white/10 dark:border-neutral-700/60 backdrop-blur-sm flex flex-col items-center">
            <Trophy class="w-5 h-5 text-yellow-400 mb-0.5" />
            <span class="text-xs font-black text-slate-200 dark:text-neutral-200">{{ store.profile?.rank || 'Junior' }} Rank</span>
          </div>
        </div>

        <div class="mt-4 flex items-start text-xs font-medium text-neutral-300 bg-black/40 p-3 rounded-2xl border border-neutral-800">
          <AlertTriangle class="w-4 h-4 text-yellow-400 mr-2 flex-shrink-0 mt-0.5" />
          <p class="leading-snug">Scores above 85% earn Senior status and priority selection for paid gigs.</p>
        </div>
      </div>
    </section>

    <!-- "PA-IMPORTANTE" ATTENDANCE BEHAVIOR MONITOR (Executive & Secretary) -->
    <section v-if="store.canViewExecutiveAnalytics && paImportanteList.length > 0" class="bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-900/50 rounded-3xl p-4 space-y-3">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2 text-red-700 dark:text-red-300">
          <UserX class="w-5 h-5" />
          <h2 class="font-extrabold text-sm uppercase tracking-wider">"Pa-Importante" Attendance Monitor</h2>
        </div>
        <span class="text-xs font-black bg-red-200 dark:bg-red-900/80 text-red-900 dark:text-red-200 px-2.5 py-0.5 rounded-full">
          {{ paImportanteList.length }} Flagged
        </span>
      </div>

      <p class="text-xs text-slate-600 dark:text-neutral-400 leading-relaxed">
        Members flagged for RSVPing "Will Attend" but failing to show up during roll calls. Use for promotion & gig allocation decisions.
      </p>

      <div class="space-y-2">
        <div v-for="item in paImportanteList" :key="item.id" class="bg-white dark:bg-[#121212] p-3 rounded-2xl border border-slate-200 dark:border-neutral-800 flex items-center justify-between">
          <div class="flex items-center space-x-2.5">
            <img v-if="item.profile_picture" :src="item.profile_picture" class="w-8 h-8 rounded-full object-cover border border-red-200 dark:border-red-900/50 flex-shrink-0" />
            <div v-else class="w-8 h-8 rounded-full bg-red-100 dark:bg-red-950/60 text-red-600 dark:text-red-400 font-bold text-xs flex items-center justify-center flex-shrink-0">
              {{ item.avatar }}
            </div>
            <div>
              <p class="font-bold text-xs text-slate-900 dark:text-white">{{ item.name }} ({{ item.section }})</p>
              <p class="text-[10px] text-red-500 font-extrabold">Low Reliability: {{ item.score }}%</p>
            </div>
          </div>
          <button 
            v-if="store.canPromoteMembers"
            @click="toggleMemberRank(item)" 
            class="px-2.5 py-1 bg-amber-500 hover:bg-amber-600 text-slate-900 font-extrabold text-[10px] rounded-lg min-h-[36px] cursor-pointer"
          >
            Demote Rank
          </button>
        </div>
      </div>
    </section>

    <!-- Leaderboard Roster -->
    <section class="space-y-3">
      <div class="flex items-center justify-between px-1">
        <h2 class="text-xs font-extrabold text-slate-500 dark:text-neutral-400 uppercase tracking-wider">Verified Band Roster</h2>
      </div>

      <div class="bg-white dark:bg-[#121212] rounded-2xl shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-hidden">
        <div v-if="leaderboard.length > 0">
          <div 
            v-for="(member, index) in leaderboard" 
            :key="member.id"
            class="flex items-center p-3.5 border-b border-slate-100 dark:border-neutral-800/80 last:border-0"
            :class="member.id === store.user?.id ? 'bg-yellow-50 dark:bg-yellow-400/5' : ''"
          >
            <!-- Rank Number -->
            <div class="w-6 text-center font-black text-sm text-slate-400 dark:text-neutral-500 mr-2">
              {{ index + 1 }}
            </div>
            
            <!-- Avatar -->
            <img v-if="member.profile_picture" :src="member.profile_picture" class="w-10 h-10 rounded-full object-cover mr-3 flex-shrink-0 border border-slate-200/60 dark:border-neutral-800 shadow-xs" />
            <div v-else class="w-10 h-10 rounded-full bg-slate-100 dark:bg-[#1c1c1e] flex items-center justify-center font-bold text-sm text-slate-700 dark:text-neutral-200 mr-3 flex-shrink-0 border border-slate-200/60 dark:border-neutral-800 shadow-xs">
              {{ member.avatar }}
            </div>
            
            <!-- Info -->
            <div class="flex-1 min-w-0 pr-2">
              <h3 class="font-bold text-sm text-slate-900 dark:text-white truncate flex items-center">
                <span>{{ member.name }}</span>
                <Trophy v-if="index === 0" class="w-3.5 h-3.5 text-yellow-500 ml-1.5 flex-shrink-0" />
              </h3>
              <div class="flex items-center space-x-2 mt-0.5">
                <span class="text-xs text-slate-500 dark:text-neutral-400 font-medium">{{ member.section }}</span>
                <span class="text-[10px] font-extrabold px-1.5 py-0.2 rounded" :class="member.rank === 'Senior' ? 'bg-yellow-100 dark:bg-yellow-950/60 text-yellow-700 dark:text-yellow-400' : 'bg-slate-100 dark:bg-neutral-800 text-slate-600 dark:text-neutral-400'">
                  {{ member.rank }}
                </span>
              </div>
            </div>

            <!-- Secretary Rank Toggle -->
            <button 
              v-if="store.canPromoteMembers && member.id !== store.user?.id"
              @click="toggleMemberRank(member)"
              type="button"
              class="mr-2 text-[10px] font-extrabold px-2.5 py-1 bg-slate-100 dark:bg-[#1c1c1e] text-slate-700 dark:text-neutral-300 hover:bg-yellow-400 hover:text-slate-900 rounded-lg transition-colors border border-slate-200 dark:border-neutral-800 flex items-center cursor-pointer min-h-[44px]"
            >
              <ChevronUp class="w-3 h-3 mr-0.5" /> {{ member.rank === 'Junior' ? 'Promote' : 'Demote' }}
            </button>
            
            <!-- Score -->
            <div class="text-right flex-shrink-0">
              <span class="text-base font-black text-slate-900 dark:text-white">{{ member.score }}<span class="text-xs font-bold text-slate-400 dark:text-neutral-500">%</span></span>
            </div>
          </div>
        </div>

        <div v-else class="p-6 text-center text-xs font-bold text-slate-400 dark:text-neutral-500">
          No verified members found yet. When Super Admin verifies accounts, they will appear here!
        </div>
      </div>
    </section>

  </div>
</template>
