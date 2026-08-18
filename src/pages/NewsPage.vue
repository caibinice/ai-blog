<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { ArrowUpRight, ChevronLeft, ChevronRight, Clock3 } from 'lucide-vue-next'
import { useHead } from '@unhead/vue'
import { localeTags } from '../lib/i18n'
import { useLocale } from '../lib/useLocale'

interface NewsItem {
  title: string
  source: string
  url: string
  publishedAt: string
}

interface NewsSource {
  name: string
  count: number
}

interface NewsResponse {
  items: NewsItem[]
  sources: NewsSource[]
  page: number
  pageSize: number
  total: number
  totalPages: number
  updatedAt: string | null
}

const { locale, t } = useLocale()
const items = ref<NewsItem[]>([])
const sources = ref<NewsSource[]>([])
const selectedSource = ref('')
const page = ref(1)
const total = ref(0)
const totalPages = ref(0)
const updatedAt = ref<string | null>(null)
const loading = ref(false)
const error = ref(false)
let requestId = 0

async function load() {
  const currentRequest = ++requestId
  loading.value = true
  error.value = false
  try {
    const params = new URLSearchParams({
      page: String(page.value),
      pageSize: '10',
    })
    if (selectedSource.value) params.set('source', selectedSource.value)
    const response = await fetch(`/api/blog/news?${params}`)
    if (!response.ok) throw new Error('news unavailable')
    const body = await response.json() as NewsResponse
    if (currentRequest !== requestId) return
    items.value = body.items
    sources.value = body.sources
    page.value = body.page
    total.value = body.total
    totalPages.value = body.totalPages
    updatedAt.value = body.updatedAt
  } catch {
    if (currentRequest === requestId) error.value = true
  } finally {
    if (currentRequest === requestId) loading.value = false
  }
}

function goToPage(target: number) {
  if (target < 1 || target > totalPages.value || target === page.value) return
  page.value = target
  void load()
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  window.scrollTo({ top: 0, behavior: reducedMotion ? 'auto' : 'smooth' })
}

const formattedUpdatedAt = computed(() => {
  if (!updatedAt.value) return ''
  return new Intl.DateTimeFormat(localeTags[locale.value], {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(updatedAt.value))
})

watch(selectedSource, () => {
  page.value = 1
  void load()
})

onMounted(() => void load())
useHead(computed(() => ({ title: `${t.value.newsTitle} · ${t.value.tabBrand}` })))
</script>

<template>
  <section class="page-section section-shell">
    <header class="page-heading">
      <p class="eyebrow">{{ t.feedsEyebrow }}</p>
      <h1>{{ t.newsTitle }}</h1>
      <p>{{ t.newsBody }}</p>
    </header>
    <div class="news-controls glass-panel">
      <label class="news-source-filter">
        <span>{{ t.newsSource }}</span>
        <select v-model="selectedSource" :disabled="loading && !sources.length">
          <option value="">{{ t.allSources }}</option>
          <option v-for="source in sources" :key="source.name" :value="source.name">
            {{ source.name }} ({{ source.count }})
          </option>
        </select>
      </label>
      <div class="news-cadence">
        <Clock3 :size="17" />
        <div>
          <span>{{ t.newsCadence }}</span>
          <small v-if="formattedUpdatedAt">{{ t.lastUpdated }}：{{ formattedUpdatedAt }}</small>
        </div>
      </div>
    </div>
    <p v-if="error && items.length" class="news-inline-error">{{ t.unavailable }}</p>
    <div v-if="loading && !items.length" class="news-skeleton">
      <div v-for="index in 6" :key="index" class="skeleton-card glass-panel" />
    </div>
    <div v-else-if="error && !items.length" class="empty-state glass-panel">{{ t.unavailable }}</div>
    <div v-else-if="!items.length" class="empty-state glass-panel">{{ t.noRecentNews }}</div>
    <div v-else class="news-list" :class="{ 'is-loading': loading }" :aria-busy="loading">
      <a v-for="item in items" :key="`${item.source}-${item.url}`" class="news-item glass-panel" :href="item.url" target="_blank" rel="noreferrer">
        <div>
          <span class="source-label">{{ item.source }}</span>
          <h2>{{ item.title }}</h2>
          <time :datetime="item.publishedAt">{{ new Date(item.publishedAt).toLocaleDateString(localeTags[locale]) }}</time>
        </div>
        <ArrowUpRight :size="20" />
      </a>
    </div>
    <nav v-if="totalPages > 1" class="news-pagination" :aria-label="t.newsPagination">
      <button
        class="secondary-button compact-button"
        type="button"
        :disabled="loading || page <= 1"
        @click="goToPage(page - 1)"
      >
        <ChevronLeft :size="16" /> {{ t.previousPage }}
      </button>
      <span aria-live="polite">{{ page }} / {{ totalPages }} · {{ total }}</span>
      <button
        class="secondary-button compact-button"
        type="button"
        :disabled="loading || page >= totalPages"
        @click="goToPage(page + 1)"
      >
        {{ t.nextPage }} <ChevronRight :size="16" />
      </button>
    </nav>
  </section>
</template>
