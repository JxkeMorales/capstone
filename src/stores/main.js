import { defineStore } from 'pinia'
import { supabase } from '../supabase'

export const useMainStore = defineStore('main', {
  state: () => ({
    user: null,
    profile: null,
    isLoading: false,
    
    // RBAC Tier State for UI simulation / testing:
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
    
    async fetchProfile() {
      if (!this.user) return
      const { data } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', this.user.id)
        .single()
      if (data) {
        this.profile = data
        this.currentRole = data.role || 'member'
        this.executiveTitle = data.executive_title || null
      }
    },
    
    async signOut() {
      await supabase.auth.signOut()
      this.user = null
      this.profile = null
      this.currentRole = 'member'
    }
  }
})
