<script setup lang="ts">
import { ArrowUpRight, Clock3 } from 'lucide-vue-next'
import type { Article } from '../lib/articles'
import { localizedPath, type Locale } from '../lib/i18n'

defineProps<{ article: Article; locale: Locale; readingLabel: string }>()
</script>

<template>
  <RouterLink class="article-card glass-panel" :to="localizedPath(locale, `/articles/${article.slug}`)">
    <div class="article-meta">
      <time :datetime="article.date">{{ article.date }}</time>
      <span><Clock3 :size="14" /> {{ article.readingMinutes }} {{ readingLabel }}</span>
    </div>
    <h3>{{ article.title }}</h3>
    <p>{{ article.excerpt }}</p>
    <div class="card-footer">
      <div class="tag-row">
        <span v-for="tag in article.tags" :key="tag">{{ tag }}</span>
      </div>
      <ArrowUpRight :size="19" />
    </div>
  </RouterLink>
</template>
