<script setup lang="ts">
import { Home } from 'lucide-vue-next'
</script>

<template>
  <section class="not-found section-shell">
    <span>404</span>
    <h1>This path drifted out of sample.</h1>
    <RouterLink class="primary-button" to="/"><Home :size="17" /> Back home</RouterLink>
  </section>
</template>
