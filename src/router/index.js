import { createRouter, createWebHistory } from 'vue-router'
import { supabase } from '../supabase'
import { useMainStore } from '../stores/main'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'landing',
      component: () => import('../views/LandingView.vue')
    },
    {
      path: '/home',
      redirect: '/dashboard'
    },
    {
      path: '/login',
      name: 'login',
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
    },
    // Global Catch-all redirect to home for any undefined/unknown routes
    {
      path: '/:pathMatch(.*)*',
      name: 'not-found',
      component: () => import('../views/NotFoundView.vue')
    }
  ]
})

router.beforeEach(async (to, from, next) => {
  const requiresAuth = to.matched.some(record => record.meta.requiresAuth)
  const store = useMainStore()

  try {
    const { data: { session } } = await supabase.auth.getSession()

    if (requiresAuth) {
      if (!session) {
        return next('/')
      } else {
        if (!store.user) {
          store.user = session.user
          await store.fetchProfile(true)
        }
        return next()
      }
    } else {
      // If user is already authenticated and visits public landing '/' or '/login', forward to '/dashboard'
      if (session && (to.path === '/' || to.path === '/login')) {
        if (!store.user) {
          store.user = session.user
          await store.fetchProfile(true)
        }
        return next('/dashboard')
      }
      return next()
    }
  } catch (err) {
    console.error('Navigation guard error:', err)
    if (requiresAuth) {
      return next('/')
    }
    return next()
  }
})

// Auto-reload latest assets when Vercel deploys and replaces dynamic chunk modules
router.onError((error, to) => {
  const isChunkError = 
    error?.message?.includes('Failed to fetch dynamically imported module') ||
    error?.message?.includes('Importing a module script failed') ||
    error?.name === 'ChunkLoadError'

  if (isChunkError) {
    console.warn('New deployment detected, reloading latest application assets...', error)
    if (to?.fullPath) {
      window.location.href = to.fullPath
    } else {
      window.location.reload()
    }
  }
})

export default router
