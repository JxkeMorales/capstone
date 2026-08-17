import { defineStore } from 'pinia'
import { supabase } from '../supabase'

export const useMainStore = defineStore('main', {
  state: () => ({
    user: null,
    profile: null,
    isLoading: false,
    _profilePromise: null,
    
    // RBAC Tier State:
    // 'member' (Standard Member)
    // 'secretary_admin' (Admin / Band Secretary)
    // 'executive' (President, VP, Treasurer)
    // 'super_admin' (IT Admin / Developer)
    currentRole: 'member', 
    executiveTitle: null, // 'president', 'vice_president', 'treasurer'
  }),
  
  getters: {
    // Permission Matrix Getters
    isSuperAdmin: (state) => state.currentRole === 'super_admin',
    isSecretaryAdmin: (state) => state.currentRole === 'secretary_admin',
    isExecutive: (state) => state.currentRole === 'executive',
    isStandardMember: (state) => state.currentRole === 'member',
    
    // Feature Permissions
    canApproveAccounts: (state) => state.currentRole === 'super_admin',
    canAssignAdminRoles: (state) => state.currentRole === 'super_admin',
    
    canManageEvents: (state) => state.currentRole === 'secretary_admin',
    canManageAnnouncements: (state) => state.currentRole === 'secretary_admin',
    canPromoteMembers: (state) => state.currentRole === 'secretary_admin',
    canConductRollCall: (state) => state.currentRole === 'secretary_admin',
    canUseSchedulingAlgorithm: (state) => state.currentRole === 'secretary_admin',
    
    canViewExecutiveAnalytics: (state) => ['secretary_admin', 'executive', 'super_admin'].includes(state.currentRole),
    canViewBudgetInfo: (state) => ['executive', 'secretary_admin'].includes(state.currentRole),
  },
  
  actions: {
    setRole(role, title = null) {
      this.currentRole = role
      this.executiveTitle = title
    },
    
    async fetchSession() {
      // 1. Instant offline retrieval from local cache
      try {
        const cachedProfile = localStorage.getItem('smartband_user_profile_cache')
        if (cachedProfile) {
          const parsed = JSON.parse(cachedProfile)
          this.profile = parsed
          this.currentRole = parsed.role || 'member'
          this.executiveTitle = parsed.executive_title || null
        }
      } catch (e) {
        console.warn('Local storage not accessible in this context')
      }

      this.isLoading = true
      try {
        const { data: { session } } = await supabase.auth.getSession()
        this.user = session?.user || null
        if (this.user) {
          await this.fetchProfile()
        }
      } catch (err) {
        console.warn('Supabase auth session check offline/fallback mode')
      } finally {
        this.isLoading = false
      }
    },
    
    async fetchProfile(force = false) {
      if (!this.user) return null

      // If profile is already in memory and force is false, return immediately (0ms, 0 network calls!)
      if (this.profile && !force) {
        return this.profile
      }

      // If a fetch request is already in flight, reuse the same pending Promise (Deduplicate concurrent requests)
      if (this._profilePromise && !force) {
        return this._profilePromise
      }

      this._profilePromise = (async () => {
        try {
          const { data } = await supabase
            .from('profiles')
            .select('*')
            .eq('id', this.user.id)
            .single()
          if (data) {
            this.profile = data
            this.currentRole = data.role || 'member'
            this.executiveTitle = data.executive_title || null
            try {
              localStorage.setItem('smartband_user_profile_cache', JSON.stringify(data))
            } catch (e) {}
          }
          return this.profile
        } catch (err) {
          console.error('Error fetching user profile:', err)
          return this.profile
        } finally {
          this._profilePromise = null
        }
      })()

      return this._profilePromise
    },
    
    async signOut() {
      await supabase.auth.signOut()
      this.user = null
      this.profile = null
      this.currentRole = 'member'
      try {
        localStorage.removeItem('smartband_user_profile_cache')
      } catch (e) {}
    }
  }
})
