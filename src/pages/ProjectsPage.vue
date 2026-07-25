<script setup lang="ts">
import { computed } from 'vue'
import { useHead } from '@unhead/vue'
import ProjectGrid from '../components/ProjectGrid.vue'
import { useLocale } from '../lib/useLocale'

const { t } = useLocale()
useHead(computed(() => ({ title: `${t.value.nav.projects} · Fish` })))
</script>

<template>
  <section class="page-section section-shell">
    <header class="page-heading">
      <p class="eyebrow">PROJECTS</p>
      <h1>{{ t.projectTitle }}</h1>
      <p>{{ t.projectBody }}</p>
    </header>
    <ProjectGrid />
  </section>
</template>
