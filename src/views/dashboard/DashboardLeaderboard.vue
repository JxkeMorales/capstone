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
  <div class="p-4 sm:p-6 space-y-6 max-w-5xl mx-auto">
    
    <header class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 pt-1 border-b border-slate-200/80 dark:border-neutral-800 pb-4">
      <div>
        <p class="text-xs font-medium text-slate-500 dark:text-neutral-400">Attendance Analytics</p>
        <h1 class="text-2xl font-bold text-slate-900 dark:text-neutral-100">Reliability & Ranks</h1>
      </div>
      <span v-if="store.canViewExecutiveAnalytics" class="text-xs font-medium bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-300 border border-slate-200 dark:border-neutral-700 px-3 py-1 rounded-full flex items-center self-start sm:self-auto">
        <BarChart3 class="w-3.5 h-3.5 mr-1 text-slate-500 dark:text-neutral-400" /> Analytics Active
      </span>
    </header>

    <!-- Personal Reliability Dashboard -->
    <section class="bg-white dark:bg-[#202124] rounded-2xl p-6 shadow-xs border border-slate-200/80 dark:border-neutral-800">
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <span class="text-xs font-medium text-slate-500 dark:text-neutral-400 uppercase tracking-wider">My Reliability Score</span>
          <div class="flex items-baseline mt-1">
            <span class="text-4xl sm:text-5xl font-bold text-slate-900 dark:text-neutral-100 leading-none">{{ store.profile?.reliability_score || 100 }}</span>
            <span class="text-lg font-semibold text-slate-400 dark:text-neutral-500 ml-1">%</span>
          </div>
        </div>
        <div class="bg-slate-50 dark:bg-[#2d2f31] px-4 py-2 rounded-full border border-slate-200/80 dark:border-neutral-700 flex items-center space-x-2">
          <Trophy class="w-4 h-4 text-slate-700 dark:text-neutral-300" />
          <span class="text-xs font-semibold text-slate-700 dark:text-neutral-200">{{ store.profile?.rank || 'Junior' }} Rank</span>
        </div>
      </div>

      <div class="mt-5 flex items-start text-xs text-slate-600 dark:text-neutral-400 bg-slate-50 dark:bg-[#282a2c] p-3.5 rounded-xl border border-slate-200/60 dark:border-neutral-700/60">
        <AlertTriangle class="w-4 h-4 text-slate-500 dark:text-neutral-400 mr-2 flex-shrink-0 mt-0.5" />
        <p class="leading-relaxed">Scores above 85% earn Senior status and priority selection for paid municipal engagements and performances.</p>
      </div>
    </section>

    <!-- "PA-IMPORTANTE" ATTENDANCE BEHAVIOR MONITOR (Executive & Secretary) -->
    <section v-if="store.canViewExecutiveAnalytics && paImportanteList.length > 0" class="bg-white dark:bg-[#202124] border border-rose-200/80 dark:border-rose-900/40 rounded-2xl p-5 space-y-4 shadow-xs">
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-2 text-rose-700 dark:text-rose-400">
          <UserX class="w-4 h-4" />
          <h2 class="font-semibold text-sm">Attendance Exception Monitor</h2>
        </div>
        <span class="text-xs font-medium bg-rose-50 dark:bg-rose-950/40 text-rose-700 dark:text-rose-400 border border-rose-200 dark:border-rose-900/40 px-3 py-0.5 rounded-full">
          {{ paImportanteList.length }} Flagged
        </span>
      </div>

      <p class="text-xs text-slate-500 dark:text-neutral-400 leading-relaxed">
        Musicians flagged for confirming attendance but failing to attend verified roll calls without filing a formal excuse.
      </p>

      <div class="space-y-2">
        <div v-for="item in paImportanteList" :key="item.id" class="bg-slate-50 dark:bg-[#282a2c] p-3 rounded-xl border border-slate-200/70 dark:border-neutral-700/70 flex items-center justify-between">
          <div class="flex items-center space-x-3">
            <img v-if="item.profile_picture" :src="item.profile_picture" class="w-8 h-8 rounded-full object-cover border border-slate-200 dark:border-neutral-700 flex-shrink-0" />
            <div v-else class="w-8 h-8 rounded-full bg-slate-200 dark:bg-neutral-700 text-slate-700 dark:text-neutral-300 font-bold text-xs flex items-center justify-center flex-shrink-0">
              {{ item.avatar }}
            </div>
            <div>
              <p class="font-medium text-xs text-slate-900 dark:text-neutral-100">{{ item.name }} ({{ item.section }})</p>
              <p class="text-[11px] text-rose-600 dark:text-rose-400 font-medium">Reliability: {{ item.score }}%</p>
            </div>
          </div>
          <button 
            v-if="store.canPromoteMembers"
            @click="toggleMemberRank(item)" 
            class="px-3 py-1.5 bg-slate-900 hover:bg-slate-800 dark:bg-neutral-100 dark:hover:bg-white text-white dark:text-slate-900 font-medium text-xs rounded-full cursor-pointer transition-colors min-h-[36px]"
          >
            Demote
          </button>
        </div>
      </div>
    </section>

    <!-- Leaderboard Roster -->
    <section class="space-y-3">
      <div class="flex items-center justify-between px-1">
        <h2 class="text-xs font-semibold text-slate-500 dark:text-neutral-400 uppercase tracking-wider">Verified Band Roster</h2>
      </div>

      <div class="bg-white dark:bg-[#202124] rounded-2xl shadow-xs border border-slate-200/80 dark:border-neutral-800 overflow-hidden divide-y divide-slate-100 dark:divide-neutral-800/80">
        <div v-if="leaderboard.length > 0">
          <div 
            v-for="(member, index) in leaderboard" 
            :key="member.id"
            class="flex items-center p-3.5 hover:bg-slate-50/60 dark:hover:bg-[#282a2c]/60 transition-colors"
            :class="member.id === store.user?.id ? 'bg-slate-50 dark:bg-[#282a2c]' : ''"
          >
            <!-- Rank Number -->
            <div class="w-7 text-center font-bold text-xs text-slate-400 dark:text-neutral-500 mr-2">
              {{ index + 1 }}
            </div>
            
            <!-- Avatar -->
            <img v-if="member.profile_picture" :src="member.profile_picture" class="w-9 h-9 rounded-full object-cover mr-3 flex-shrink-0 border border-slate-200/60 dark:border-neutral-700 shadow-xs" />
            <div v-else class="w-9 h-9 rounded-full bg-slate-100 dark:bg-[#2d2f31] flex items-center justify-center font-bold text-xs text-slate-700 dark:text-neutral-300 mr-3 flex-shrink-0 border border-slate-200/60 dark:border-neutral-700 shadow-xs">
              {{ member.avatar }}
            </div>
            
            <!-- Info -->
            <div class="flex-1 min-w-0 pr-2">
              <h3 class="font-medium text-sm text-slate-900 dark:text-neutral-100 truncate flex items-center">
                <span>{{ member.name }}</span>
                <Trophy v-if="index === 0" class="w-3.5 h-3.5 text-amber-500 ml-1.5 flex-shrink-0" />
              </h3>
              <div class="flex items-center space-x-2 mt-0.5">
                <span class="text-xs text-slate-500 dark:text-neutral-400">{{ member.section }}</span>
                <span class="text-[10px] font-semibold px-2 py-0.5 rounded-full" :class="member.rank === 'Senior' ? 'bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-200 border border-slate-200 dark:border-neutral-700' : 'bg-slate-100/60 dark:bg-neutral-800/60 text-slate-500 dark:text-neutral-400'">
                  {{ member.rank }}
                </span>
              </div>
            </div>

            <!-- Secretary Rank Toggle -->
            <button 
              v-if="store.canPromoteMembers && member.id !== store.user?.id"
              @click="toggleMemberRank(member)"
              type="button"
              class="mr-3 text-xs font-medium px-3 py-1.5 bg-slate-100 dark:bg-[#2d2f31] text-slate-700 dark:text-neutral-300 hover:bg-slate-200 dark:hover:bg-[#383a3d] rounded-full transition-colors border border-slate-200 dark:border-neutral-700 flex items-center cursor-pointer min-h-[36px]"
            >
              <ChevronUp class="w-3 h-3 mr-1" /> {{ member.rank === 'Junior' ? 'Promote' : 'Demote' }}
            </button>
            
            <!-- Score -->
            <div class="text-right flex-shrink-0 pr-1">
              <span class="text-base font-bold text-slate-900 dark:text-neutral-100">{{ member.score }}<span class="text-xs font-normal text-slate-400 dark:text-neutral-500">%</span></span>
            </div>
          </div>
        </div>

        <div v-else class="p-8 text-center text-xs font-medium text-slate-400 dark:text-neutral-500">
          No verified members found yet. When Super Admin verifies accounts, they will appear here.
        </div>
      </div>
    </section>

  </div>
</template>
