<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { ArrowUp } from 'lucide-vue-next'
import { useLocale } from '../lib/useLocale'

const { t } = useLocale()
const visible = ref(false)
let animationFrame: number | undefined

function updateVisibility() {
  if (animationFrame !== undefined) return
  animationFrame = window.requestAnimationFrame(() => {
    visible.value = window.scrollY > Math.max(480, window.innerHeight * 0.65)
    animationFrame = undefined
  })
}

function scrollToTop() {
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  window.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' })
}

onMounted(() => {
  updateVisibility()
  window.addEventListener('scroll', updateVisibility, { passive: true })
})

onBeforeUnmount(() => {
  window.removeEventListener('scroll', updateVisibility)
  if (animationFrame !== undefined) window.cancelAnimationFrame(animationFrame)
})
</script>

<template>
  <Transition name="back-to-top">
    <button
      v-if="visible"
      class="back-to-top"
      type="button"
      :aria-label="t.backToTop"
      :title="t.backToTop"
      @click="scrollToTop"
    >
      <ArrowUp :size="21" :stroke-width="2.4" />
    </button>
  </Transition>
</template>
