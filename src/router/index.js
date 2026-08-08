import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../supabase'
import { useMainStore } from '../stores/main'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: () => import('../views/HomeView.vue')
    },
    {
      path: '/dashboard',
      component: () => import('../components/layout/DashboardLayout.vue'),
      meta: { requiresAuth: true },
      children: [
        {
          path: '',
          name: 'dashboard-home',
          component: () => import('../views/dashboard/DashboardHome.vue'),
          meta: { requiresAuth: true }
        },
        {
          path: 'schedule',
          name: 'dashboard-schedule',
          component: () => import('../views/dashboard/DashboardSchedule.vue'),
          meta: { requiresAuth: true }
        },
        {
          path: 'leaderboard',
          redirect: '/dashboard/members'
        },
        {
          path: 'members',
          name: 'dashboard-members',
          component: () => import('../views/dashboard/DashboardMembers.vue'),
          meta: { requiresAuth: true }
        },
        {
          path: 'profile',
          name: 'dashboard-profile',
          component: () => import('../views/dashboard/DashboardProfile.vue'),
          meta: { requiresAuth: true }
        },
        {
          path: 'admin',
          name: 'dashboard-admin',
          component: () => import('../views/dashboard/DashboardAdmin.vue'),
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
