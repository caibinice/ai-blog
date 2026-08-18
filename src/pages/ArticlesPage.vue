<script setup lang="ts">
import { computed } from 'vue'
import { ChevronLeft, ChevronRight } from 'lucide-vue-next'
import { useHead } from '@unhead/vue'
import ArticleCard from '../components/ArticleCard.vue'
import { articlePageCount, listArticlePage } from '../lib/articles'
import { localizedPath } from '../lib/i18n'
import { useLocale } from '../lib/useLocale'

const props = withDefaults(defineProps<{ page?: number }>(), { page: 1 })
const { locale, t } = useLocale()
const currentPage = computed(() => Math.min(articlePageCount(), Math.max(1, props.page)))
const totalPages = articlePageCount()
const articles = computed(() => listArticlePage(locale.value, currentPage.value))
const pagePath = (page: number) => localizedPath(locale.value, page <= 1 ? '/articles' : `/articles/page/${page}`)
useHead(computed(() => ({
  title: `${t.value.nav.articles}${currentPage.value > 1 ? ` · ${t.value.pageLabel} ${currentPage.value}` : ''} · ${t.value.tabBrand}`,
})))
</script>

<template>
  <section class="page-section section-shell">
    <header class="page-heading">
      <p class="eyebrow">{{ t.writingEyebrow }}</p>
      <h1>{{ t.allWriting }}</h1>
      <p>{{ t.writingBody }}</p>
    </header>
    <div class="article-grid">
      <ArticleCard v-for="article in articles" :key="article.slug" :article="article" :locale="locale" :reading-label="t.readingTime" />
    </div>
    <nav v-if="totalPages > 1" class="article-pagination" :aria-label="t.articlePagination">
      <RouterLink
        class="secondary-button compact-button"
        :class="{ 'is-disabled': currentPage <= 1 }"
        :aria-disabled="currentPage <= 1"
        :tabindex="currentPage <= 1 ? -1 : undefined"
        :to="pagePath(Math.max(1, currentPage - 1))"
      >
        <ChevronLeft :size="16" /> {{ t.previousPage }}
      </RouterLink>
      <span>{{ t.pageLabel }} {{ currentPage }} / {{ totalPages }}</span>
      <RouterLink
        class="secondary-button compact-button"
        :class="{ 'is-disabled': currentPage >= totalPages }"
        :aria-disabled="currentPage >= totalPages"
        :tabindex="currentPage >= totalPages ? -1 : undefined"
        :to="pagePath(Math.min(totalPages, currentPage + 1))"
      >
        {{ t.nextPage }} <ChevronRight :size="16" />
      </RouterLink>
    </nav>
  </section>
</template>
