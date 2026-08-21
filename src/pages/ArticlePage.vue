<script setup lang="ts">
import { computed } from 'vue'
import { ArrowLeft, ArrowUpRight, Clock3 } from 'lucide-vue-next'
import MarkdownIt from 'markdown-it'
import { useHead } from '@unhead/vue'
import { getArticle } from '../lib/articles'
import { localizedPath } from '../lib/i18n'
import { useLocale } from '../lib/useLocale'

const props = defineProps<{ slug: string }>()
const { locale, t } = useLocale()
const article = computed(() => getArticle(locale.value, props.slug))
const md = new MarkdownIt({ html: false, linkify: true, typographer: true })
md.renderer.rules.table_open = () => (
  `<div class="article-table-wrap" role="region" aria-label="${md.utils.escapeHtml(t.value.articleTable)}" tabindex="0"><table>`
)
md.renderer.rules.table_close = () => '</table></div>'
const defaultLinkOpen = md.renderer.rules.link_open
md.renderer.rules.link_open = (tokens, index, options, env, self) => {
  tokens[index].attrSet('target', '_blank')
  tokens[index].attrSet('rel', 'noopener noreferrer')
  return defaultLinkOpen
    ? defaultLinkOpen(tokens, index, options, env, self)
    : self.renderToken(tokens, index, options)
}
const rendered = computed(() => article.value ? md.render(article.value.body) : '')

useHead(computed(() => ({
  meta: article.value ? [
    { name: 'description', content: article.value.excerpt },
    { property: 'og:title', content: article.value.title },
    { property: 'og:description', content: article.value.excerpt },
    { property: 'og:type', content: 'article' },
    { property: 'article:published_time', content: article.value.date },
    { property: 'og:image', content: '/og.png' },
  ] : [],
})))
</script>

<template>
  <article v-if="article" class="article-page section-shell">
    <RouterLink class="back-link" :to="localizedPath(locale, '/articles')"><ArrowLeft :size="17" /> {{ t.back }}</RouterLink>
    <header class="article-header">
      <div class="tag-row">
        <span v-for="tag in article.tags" :key="tag">{{ tag }}</span>
      </div>
      <h1>{{ article.title }}</h1>
      <p>{{ article.excerpt }}</p>
      <div class="article-meta article-meta-large">
        <time :datetime="article.date">{{ t.published }} {{ article.date }}</time>
        <span><Clock3 :size="15" /> {{ article.readingMinutes }} {{ t.readingTime }}</span>
      </div>
    </header>
    <div class="article-prose glass-panel" v-html="rendered" />
    <a v-if="article.projectPath" class="project-cta glass-panel" :href="article.projectPath" target="_blank" rel="noopener noreferrer">
      <span>{{ t.viewProject }}</span>
      <ArrowUpRight :size="20" />
    </a>
  </article>
  <section v-else class="page-section section-shell">
    <h1>{{ t.articleNotFound }}</h1>
  </section>
</template>
