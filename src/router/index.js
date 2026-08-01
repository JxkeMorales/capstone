import { createRouter, createWebHistory } from 'vue-router'
import HomeView from '../views/HomeView.vue'
import DashboardLayout from '../components/layout/DashboardLayout.vue'
import DashboardHome from '../views/dashboard/DashboardHome.vue'
import DashboardSchedule from '../views/dashboard/DashboardSchedule.vue'
import DashboardMembers from '../views/dashboard/DashboardMembers.vue'
import DashboardProfile from '../views/dashboard/DashboardProfile.vue'
import DashboardAdmin from '../views/dashboard/DashboardAdmin.vue'
import { supabase } from '../supabase'
import { useMainStore } from '../stores/main'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: HomeView
    },
    {
      path: '/dashboard',
      component: DashboardLayout,
      meta: { requiresAuth: true },
      children: [
        {
          path: '',
          name: 'dashboard-home',
          component: DashboardHome,
          meta: { requiresAuth: true }
        },
        {
          path: 'schedule',
          name: 'dashboard-schedule',
          component: DashboardSchedule,
          meta: { requiresAuth: true }
        },
        {
          path: 'leaderboard',
          redirect: '/dashboard/members'
        },
        {
          path: 'members',
          name: 'dashboard-members',
          component: DashboardMembers,
          meta: { requiresAuth: true }
        },
        {
          path: 'profile',
          name: 'dashboard-profile',
          component: DashboardProfile,
          meta: { requiresAuth: true }
        },
        {
          path: 'admin',
          name: 'dashboard-admin',
          component: DashboardAdmin,
          meta: { requiresAuth: true }
        }
      ]
    }
  ]
})

router.beforeEach(async (to, from, next) => {
  const requiresAuth = to.matched.some(record => record.meta.requiresAuth)
  const store = useMainStore()

  if (requiresAuth) {
    const { data: { session } } = await supabase.auth.getSession()

    if (!session) {
      next({ name: 'home' })
    } else {
      if (!store.user) {
        store.user = session.user
        await store.fetchProfile()
      }
      next()
    }
  } else {
    next()
  }
})

export default router
