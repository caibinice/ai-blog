<script setup lang="ts">
import SiteHeader from './components/SiteHeader.vue'
import SiteFooter from './components/SiteFooter.vue'
import { useLocale } from './lib/useLocale'

const { t } = useLocale()
</script>

<template>
  <div class="site-shell">
    <a class="skip-link" href="#main-content">{{ t.skipToContent }}</a>
    <SiteHeader />
    <main id="main-content">
      <RouterView v-slot="{ Component, route }">
        <Transition name="page" mode="out-in">
          <component :is="Component" :key="route.fullPath" />
        </Transition>
      </RouterView>
    </main>
    <SiteFooter />
  </div>
</template>
