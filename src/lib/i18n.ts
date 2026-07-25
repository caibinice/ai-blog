import zh from '../content/zh/ui.json'
import en from '../content/en/ui.json'
import ja from '../content/ja/ui.json'

export type Locale = 'zh' | 'en' | 'ja'

export const localePrefixes: Record<Locale, string> = {
  zh: '',
  en: '/en',
  ja: '/ja',
}

export const copy = { zh, en, ja } as const
export const localeTags: Record<Locale, string> = {
  zh: 'zh-CN',
  en: 'en-US',
  ja: 'ja-JP',
}

export function localizedPath(locale: Locale, path = ''): string {
  const suffix = path === '/' ? '' : path
  return `${localePrefixes[locale]}${suffix}` || '/'
}
