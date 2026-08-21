<script setup lang="ts">
import ProjectGrid from '../components/ProjectGrid.vue'
import { useLocale } from '../lib/useLocale'

const { t } = useLocale()
</script>

<template>
  <section class="page-section section-shell">
    <header class="page-heading">
      <p class="eyebrow">{{ t.projectsEyebrow }}</p>
      <h1>{{ t.projectTitle }}</h1>
      <p>{{ t.projectBody }}</p>
    </header>
    <ProjectGrid />
  </section>
</template>
