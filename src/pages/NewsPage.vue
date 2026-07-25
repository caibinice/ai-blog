<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ArrowUpRight, RefreshCcw } from 'lucide-vue-next'
import { useHead } from '@unhead/vue'
import { localeTags } from '../lib/i18n'
import { useLocale } from '../lib/useLocale'

interface NewsItem {
  title: string
  source: string
  url: string
  publishedAt: string
}

const { locale, t } = useLocale()
const items = ref<NewsItem[]>([])
const loading = ref(false)
const error = ref(false)

async function load() {
  loading.value = true
  error.value = false
  try {
    const response = await fetch('/api/blog/news?limit=12')
    if (!response.ok) throw new Error('news unavailable')
    const body = await response.json() as { items: NewsItem[] }
    items.value = body.items
  } catch {
    error.value = true
  } finally {
    loading.value = false
  }
}

onMounted(load)
useHead(computed(() => ({ title: `${t.value.newsTitle} · Fish` })))
</script>

<template>
  <section class="page-section section-shell">
    <header class="page-heading page-heading-row">
      <div>
        <p class="eyebrow">{{ t.feedsEyebrow }}</p>
        <h1>{{ t.newsTitle }}</h1>
        <p>{{ t.newsBody }}</p>
      </div>
      <button class="secondary-button compact-button" type="button" :disabled="loading" @click="load">
        <RefreshCcw :size="16" :class="{ spinning: loading }" /> {{ t.refresh }}
      </button>
    </header>
    <div v-if="loading && !items.length" class="news-skeleton">
      <div v-for="index in 6" :key="index" class="skeleton-card glass-panel" />
    </div>
    <div v-else-if="error && !items.length" class="empty-state glass-panel">{{ t.unavailable }}</div>
    <div v-else class="news-list">
      <a v-for="item in items" :key="`${item.source}-${item.url}`" class="news-item glass-panel" :href="item.url" target="_blank" rel="noreferrer">
        <div>
          <span class="source-label">{{ item.source }}</span>
          <h2>{{ item.title }}</h2>
          <time :datetime="item.publishedAt">{{ new Date(item.publishedAt).toLocaleDateString(localeTags[locale]) }}</time>
        </div>
        <ArrowUpRight :size="20" />
      </a>
    </div>
  </section>
</template>
