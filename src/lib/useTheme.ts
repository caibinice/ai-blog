import { ref } from 'vue'

export type Theme = 'bright' | 'tech-black' | 'cute-pink'
export const themes: Theme[] = ['bright', 'tech-black', 'cute-pink']

const currentTheme = ref<Theme>('bright')
let initialized = false

function applyTheme(theme: Theme) {
  currentTheme.value = theme
  if (typeof document !== 'undefined') document.documentElement.dataset.theme = theme
  if (typeof localStorage !== 'undefined') localStorage.setItem('fish-theme', theme)
}

export function useTheme() {
  if (!initialized && typeof window !== 'undefined') {
    initialized = true
    const stored = localStorage.getItem('fish-theme') as Theme | null
    applyTheme(stored && themes.includes(stored) ? stored : 'bright')
  }
  return { theme: currentTheme, setTheme: applyTheme, themes }
}
