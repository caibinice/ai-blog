<script setup lang="ts">
import { computed } from 'vue'
import { ArrowRight, Github, MapPin, Sparkles } from 'lucide-vue-next'
import { useHead } from '@unhead/vue'
import ArticleCard from '../components/ArticleCard.vue'
import ProjectGrid from '../components/ProjectGrid.vue'
import { listArticles } from '../lib/articles'
import { localizedPath } from '../lib/i18n'
import { useLocale } from '../lib/useLocale'

const { locale, t } = useLocale()
const latest = computed(() => listArticles(locale.value).slice(-3).reverse())

useHead(computed(() => ({
  title: `Fish · ${t.value.role}`,
  meta: [
    { name: 'description', content: t.value.heroBody },
    { property: 'og:title', content: `Fish · ${t.value.role}` },
    { property: 'og:description', content: t.value.heroBody },
    { property: 'og:image', content: '/og.png' },
    { name: 'twitter:card', content: 'summary_large_image' },
  ],
})))
</script>

<template>
  <div>
    <section class="hero section-shell">
      <div class="hero-orb hero-orb-one" aria-hidden="true" />
      <div class="hero-orb hero-orb-two" aria-hidden="true" />
      <div class="hero-copy">
        <p class="eyebrow"><Sparkles :size="15" /> {{ t.heroEyebrow }}</p>
        <h1>{{ t.heroTitle }}</h1>
        <p class="hero-body">{{ t.heroBody }}</p>
        <div class="hero-actions">
          <RouterLink class="primary-button" :to="localizedPath(locale, '/articles')">
            {{ t.readWriting }} <ArrowRight :size="18" />
          </RouterLink>
          <RouterLink class="secondary-button" :to="localizedPath(locale, '/projects')">
            {{ t.exploreProjects }}
          </RouterLink>
        </div>
        <div class="hero-facts">
          <span><MapPin :size="15" /> {{ t.location }}</span>
          <a href="https://github.com/caibinice" target="_blank" rel="noreferrer"><Github :size="15" /> @caibinice</a>
        </div>
      </div>
      <aside class="signal-card glass-panel" :aria-label="t.currentFocus">
        <div class="signal-top">
          <span class="signal-dot" />
          <small>{{ t.currentFocus }}</small>
          <span>2026</span>
        </div>
        <div class="signal-visual" aria-hidden="true">
          <span v-for="index in 12" :key="index" :style="{ height: `${20 + ((index * 17) % 64)}%` }" />
        </div>
        <h2>{{ t.focusTitle }}</h2>
        <p>{{ t.focusBody }}</p>
      </aside>
    </section>

    <section class="content-section section-shell">
      <div class="section-heading">
        <div>
          <p class="eyebrow">{{ t.journalEyebrow }}</p>
          <h2>{{ t.latestWriting }}</h2>
        </div>
        <RouterLink :to="localizedPath(locale, '/articles')">{{ t.allWriting }} <ArrowRight :size="17" /></RouterLink>
      </div>
      <div class="article-grid">
        <ArticleCard v-for="article in latest" :key="article.slug" :article="article" :locale="locale" :reading-label="t.readingTime" />
      </div>
    </section>

    <section class="content-section section-shell">
      <div class="section-heading">
        <div>
          <p class="eyebrow">{{ t.labsEyebrow }}</p>
          <h2>{{ t.projectTitle }}</h2>
          <p>{{ t.projectBody }}</p>
        </div>
      </div>
      <ProjectGrid />
    </section>
  </div>
</template>
