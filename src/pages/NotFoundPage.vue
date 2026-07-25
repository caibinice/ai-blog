<script setup lang="ts">
import { Home } from 'lucide-vue-next'
import { localizedPath } from '../lib/i18n'
import { useLocale } from '../lib/useLocale'

const { locale, t } = useLocale()
</script>

<template>
  <section class="not-found section-shell">
    <span>404</span>
    <h1>{{ t.notFoundTitle }}</h1>
    <RouterLink class="primary-button" :to="localizedPath(locale)"><Home :size="17" /> {{ t.backHome }}</RouterLink>
  </section>
</template>
