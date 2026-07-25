import { ViteSSG } from 'vite-ssg'
import App from './App.vue'
import { routes } from './router'
import './styles/main.css'

export const createApp = ViteSSG(
  App,
  { routes, scrollBehavior: () => ({ top: 0, behavior: 'smooth' }) },
  ({ router }) => {
    router.beforeEach((to) => {
      const locale = String(to.meta.locale || 'zh')
      if (typeof document !== 'undefined') {
        document.documentElement.lang = locale === 'zh' ? 'zh-CN' : locale
      }
    })
  },
)
