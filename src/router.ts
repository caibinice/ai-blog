import type { RouteRecordRaw } from 'vue-router'
import type { Locale } from './lib/i18n'
import { articleMeta, articlePageCount } from './lib/articles'
import HomePage from './pages/HomePage.vue'
import ArticlesPage from './pages/ArticlesPage.vue'
import ArticlePage from './pages/ArticlePage.vue'
import ProjectsPage from './pages/ProjectsPage.vue'
import NewsPage from './pages/NewsPage.vue'
import GuestbookPage from './pages/GuestbookPage.vue'
import ManageCommentsPage from './pages/ManageCommentsPage.vue'
import NotFoundPage from './pages/NotFoundPage.vue'

const localizedRoutes: RouteRecordRaw[] = []
for (const locale of ['zh', 'en', 'ja'] as Locale[]) {
  const prefix = locale === 'zh' ? '' : `/${locale}`
  const meta = { locale }
  localizedRoutes.push(
    { path: prefix || '/', name: `home-${locale}`, component: HomePage, meta },
    { path: `${prefix}/articles`, name: `articles-${locale}`, component: ArticlesPage, props: { page: 1 }, meta },
    { path: `${prefix}/projects`, name: `projects-${locale}`, component: ProjectsPage, meta },
    { path: `${prefix}/news`, name: `news-${locale}`, component: NewsPage, meta },
    { path: `${prefix}/guestbook`, name: `guestbook-${locale}`, component: GuestbookPage, meta },
  )
  for (let page = 2; page <= articlePageCount(); page += 1) {
    localizedRoutes.push({
      path: `${prefix}/articles/page/${page}`,
      name: `articles-${locale}-page-${page}`,
      component: ArticlesPage,
      props: { page },
      meta,
    })
  }
  for (const article of articleMeta) {
    localizedRoutes.push({
      path: `${prefix}/articles/${article.slug}`,
      name: `article-${locale}-${article.slug}`,
      component: ArticlePage,
      props: { slug: article.slug },
      meta,
    })
  }
}

export const routes: RouteRecordRaw[] = [
  ...localizedRoutes,
  { path: '/manage/comments', name: 'manage-comments', component: ManageCommentsPage, meta: { locale: 'zh' } },
  { path: '/en/:pathMatch(.*)*', name: 'not-found-en', component: NotFoundPage, meta: { locale: 'en' } },
  { path: '/ja/:pathMatch(.*)*', name: 'not-found-ja', component: NotFoundPage, meta: { locale: 'ja' } },
  { path: '/:pathMatch(.*)*', name: 'not-found', component: NotFoundPage, meta: { locale: 'zh' } },
]
