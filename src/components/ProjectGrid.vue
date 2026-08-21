<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ArrowUpRight, CirclePause, CirclePlay } from 'lucide-vue-next'
import { projects } from '../lib/projects'
import { useLocale } from '../lib/useLocale'

interface RuntimeStatus {
  projects?: Record<string, { state?: string }>
}

const { locale, t } = useLocale()
const runtime = ref<RuntimeStatus>({})
const cards = computed(() => projects.map((project) => ({
  ...project,
  status: runtime.value.projects?.[project.key]?.state === 'paused' ? 'paused' : 'live',
})))
const projectAlt = (title: string) => t.value.projectScreenshot.replace('{title}', title)

onMounted(async () => {
  try {
    const response = await fetch('/runtime-status.json', { cache: 'no-store' })
    if (response.ok) runtime.value = await response.json() as RuntimeStatus
  } catch {
    // Static status is optional locally.
  }
})
</script>

<template>
  <div class="project-grid">
    <a v-for="project in cards" :key="project.key" class="project-card glass-panel" :href="project.path" target="_blank" rel="noopener noreferrer">
      <div class="project-image" :class="{ 'project-image-contain': project.key === 'cockpit' }" :style="{ '--project-accent': project.accent }">
        <img :src="project.image" :alt="projectAlt(project.title[locale])" loading="lazy" />
        <span class="status-pill" :class="project.status">
          <CirclePause v-if="project.status === 'paused'" :size="13" />
          <CirclePlay v-else :size="13" />
          {{ project.status === 'paused' ? t.paused : t.live }}
        </span>
      </div>
      <div class="project-copy">
        <div>
          <h3>{{ project.title[locale] }}</h3>
          <p>{{ project.description[locale] }}</p>
        </div>
        <div class="project-bottom">
          <div class="tag-row">
            <span v-for="item in project.stack" :key="item">{{ item }}</span>
          </div>
          <span class="project-link">{{ t.visitProject }} <ArrowUpRight :size="17" /></span>
        </div>
      </div>
    </a>
  </div>
</template>
