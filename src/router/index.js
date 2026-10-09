import { createRouter, createWebHistory } from 'vue-router'
import { nextTick } from 'vue'
import { supabase } from '../supabase'
import { useMainStore } from '../stores/main'

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'landing',
      component: () => import('../views/LandingView.vue'),
      meta: { title: 'Welcome' }
    },
    {
      path: '/home',
      redirect: '/dashboard'
    },
    {
      path: '/login',
      name: 'login',
      component: () => import('../views/HomeView.vue'),
      meta: { title: 'Sign In' }
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
          meta: { requiresAuth: true, title: 'Home' }
        },
        {
          path: 'schedule',
          name: 'dashboard-schedule',
          component: () => import('../views/dashboard/DashboardSchedule.vue'),
          meta: { requiresAuth: true, title: 'Events' }
        },
        {
          path: 'leaderboard',
          name: 'dashboard-leaderboard',
          component: () => import('../views/dashboard/DashboardLeaderboard.vue'),
          meta: { requiresAuth: true, title: 'Leaderboard' }
        },
        {
          path: 'members',
          name: 'dashboard-members',
          component: () => import('../views/dashboard/DashboardMembers.vue'),
          meta: { requiresAuth: true, title: 'Roster' }
        },
        {
          path: 'profile',
          name: 'dashboard-profile',
          component: () => import('../views/dashboard/DashboardProfile.vue'),
          meta: { requiresAuth: true, title: 'Profile' }
        },
        {
          path: 'admin',
          name: 'dashboard-admin',
          component: () => import('../views/dashboard/DashboardAdmin.vue'),
          meta: { requiresAuth: true, title: 'Operations & Moderation' }
        }
      ]
    },
    // Global Catch-all redirect to home for any undefined/unknown routes
    {
      path: '/:pathMatch(.*)*',
      name: 'not-found',
      component: () => import('../views/NotFoundView.vue'),
      meta: { title: 'Page Not Found' }
    }
  ]
})

router.beforeEach(async (to, from) => {
  const requiresAuth = to.matched.some(record => record.meta.requiresAuth)
  const store = useMainStore()

  try {
    const { data: { session } } = await supabase.auth.getSession()

    if (requiresAuth) {
      if (!session) {
        return '/'
      }

      if (!store.user) {
        store.user = session.user
      }
      
      const profile = await store.fetchProfile()

      // Block unverified standard members from accessing dashboard
      if (profile && profile.is_verified === false && profile.role === 'member') {
        await supabase.auth.signOut()
        store.user = null
        store.profile = null
        return '/login'
      }

      // Authorize access to /dashboard/admin strictly to leadership
      if (to.name === 'dashboard-admin') {
        const canAccessAdmin = ['super_admin', 'secretary_admin', 'executive'].includes(store.currentRole)
        if (!canAccessAdmin) {
          return '/dashboard'
        }
      }

      return true
    } else {
      // If user is already authenticated and visits public landing '/' or '/login'
      if (session && (to.path === '/' || to.path === '/login')) {
        if (!store.user) {
          store.user = session.user
        }
        const profile = await store.fetchProfile()
        if (profile && profile.is_verified === false && profile.role === 'member') {
          await supabase.auth.signOut()
          store.user = null
          store.profile = null
          return true
        }
        return '/dashboard'
      }
      return true
    }
  } catch (err) {
    console.error('Navigation guard error:', err)
    if (requiresAuth) {
      return '/'
    }
    return true
  }
})

// Update document title and manage focus on SPA route transition (WCAG 2.4.2 & 2.4.3)
router.afterEach((to) => {
  const pageTitle = to.meta?.title || 'Band Portal'
  document.title = `${pageTitle} — SmartBand`

  nextTick(() => {
    const mainHeading = document.querySelector('main h1, h1')
    if (mainHeading) {
      mainHeading.setAttribute('tabindex', '-1')
      mainHeading.focus({ preventScroll: true })
    }
  })
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
