<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Languages, Menu, MoonStar, Palette, Sparkles, Sun, X } from 'lucide-vue-next'
import { localizedPath, localePrefixes, type Locale } from '../lib/i18n'
import { useLocale } from '../lib/useLocale'
import { type Theme, useTheme } from '../lib/useTheme'

const route = useRoute()
const router = useRouter()
const { locale, t } = useLocale()
const { theme, setTheme } = useTheme()
const open = ref(false)
const themeOpen = ref(false)
const languageOpen = ref(false)

const nav = computed(() => [
  { label: t.value.nav.home, path: localizedPath(locale.value) },
  { label: t.value.nav.articles, path: localizedPath(locale.value, '/articles') },
  { label: t.value.nav.projects, path: localizedPath(locale.value, '/projects') },
  { label: t.value.nav.news, path: localizedPath(locale.value, '/news') },
  { label: t.value.nav.guestbook, path: localizedPath(locale.value, '/guestbook') },
])

const themeItems = computed<{ id: Theme; label: string; icon: typeof Sun }[]>(() => [
  { id: 'bright', label: t.value.themeBright, icon: Sun },
  { id: 'tech-black', label: t.value.themeTechBlack, icon: MoonStar },
  { id: 'cute-pink', label: t.value.themeCutePink, icon: Sparkles },
])

function setLanguage(target: Locale) {
  let path = route.path
  for (const prefix of ['/en', '/ja']) {
    if (path === prefix) path = '/'
    else if (path.startsWith(`${prefix}/`)) path = path.slice(prefix.length)
  }
  const next = `${localePrefixes[target]}${path === '/' ? '' : path}` || '/'
  languageOpen.value = false
  open.value = false
  void router.push(next)
}

function closeMenus() {
  themeOpen.value = false
  languageOpen.value = false
}
</script>

<template>
  <header class="site-header">
    <nav class="nav-shell glass-panel" :aria-label="t.primaryNavigation">
      <RouterLink class="brand" :to="localizedPath(locale)" @pointerdown="closeMenus">
        <span class="brand-mark" aria-hidden="true">
          <img src="/fish-avatar.png" alt="" />
        </span>
        <span>
          <strong>{{ t.brand }}</strong>
          <small>{{ t.role }}</small>
        </span>
      </RouterLink>

      <div class="desktop-nav">
        <RouterLink v-for="item in nav" :key="item.path" :to="item.path" class="nav-link">
          {{ item.label }}
        </RouterLink>
      </div>

      <div class="nav-actions">
        <div class="popover-wrap">
          <button class="icon-button" type="button" :aria-label="t.chooseTheme" :aria-expanded="themeOpen" @click="themeOpen = !themeOpen; languageOpen = false">
            <Palette :size="18" />
          </button>
          <Transition name="popover">
            <div v-if="themeOpen" class="popover glass-panel theme-popover">
              <button
                v-for="item in themeItems"
                :key="item.id"
                type="button"
                :class="{ active: theme === item.id }"
                @click="setTheme(item.id); themeOpen = false"
              >
                <component :is="item.icon" :size="16" />
                {{ item.label }}
              </button>
            </div>
          </Transition>
        </div>

        <div class="popover-wrap">
          <button class="icon-button" type="button" :aria-label="t.chooseLanguage" :aria-expanded="languageOpen" @click="languageOpen = !languageOpen; themeOpen = false">
            <Languages :size="18" />
          </button>
          <Transition name="popover">
            <div v-if="languageOpen" class="popover glass-panel language-popover">
              <button :class="{ active: locale === 'zh' }" type="button" @click="setLanguage('zh')">中文</button>
              <button :class="{ active: locale === 'en' }" type="button" @click="setLanguage('en')">English</button>
              <button :class="{ active: locale === 'ja' }" type="button" @click="setLanguage('ja')">日本語</button>
            </div>
          </Transition>
        </div>

        <button class="icon-button mobile-menu-button" type="button" :aria-label="t.toggleMenu" :aria-expanded="open" @click="open = !open; closeMenus()">
          <X v-if="open" :size="19" />
          <Menu v-else :size="19" />
        </button>
      </div>
    </nav>

    <Transition name="sheet">
      <nav v-if="open" class="mobile-nav glass-panel" :aria-label="t.mobileNavigation">
        <RouterLink v-for="item in nav" :key="item.path" :to="item.path" @click="open = false">
          {{ item.label }}
        </RouterLink>
      </nav>
    </Transition>
  </header>
</template>
