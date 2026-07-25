<script setup lang="ts">
import { computed } from 'vue'
import { useHead } from '@unhead/vue'
import ArticleCard from '../components/ArticleCard.vue'
import { listArticles } from '../lib/articles'
import { useLocale } from '../lib/useLocale'

const { locale, t } = useLocale()
const articles = computed(() => listArticles(locale.value).slice().reverse())
useHead(computed(() => ({ title: `${t.value.nav.articles} · Fish` })))
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
  </section>
</template>
