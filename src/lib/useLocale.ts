import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { copy, type Locale } from './i18n'

export function useLocale() {
  const route = useRoute()
  const locale = computed(() => (route.meta.locale || 'zh') as Locale)
  const t = computed(() => copy[locale.value])
  return { locale, t }
}
