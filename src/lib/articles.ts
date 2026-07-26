import type { Locale } from './i18n'

export interface ArticleMeta {
  slug: string
  date: string
  tags: string[]
  projectPath?: string
}

export interface Article extends ArticleMeta {
  title: string
  excerpt: string
  body: string
  readingMinutes: number
}

export const articleMeta: ArticleMeta[] = [
  { slug: 'ai-quant-system', date: '2025-06-18', tags: ['AI', 'Quant', 'FastAPI'], projectPath: '/quant/' },
  { slug: 'trust-the-backtest', date: '2025-09-06', tags: ['Backtest', 'Learning', 'Risk'] },
  { slug: 'cross-border-trends', date: '2025-11-22', tags: ['Commerce', 'Data', 'Spring'], projectPath: '/crossBorderTrend/' },
  { slug: 'llm-sentiment-walk-forward', date: '2026-02-14', tags: ['LLM', 'Sentiment', 'Walk-forward'], projectPath: '/quant/' },
  { slug: 'enterprise-ai-cockpit', date: '2026-05-02', tags: ['RAG', 'Spring AI', 'pgvector'], projectPath: '/smartCockpit/' },
  { slug: 'multi-branch-feature-migration', date: '2026-07-15', tags: ['Git', 'Cherry-pick', 'Deployment'] },
]

const modules = import.meta.glob('../content/**/*.md', {
  eager: true,
  query: '?raw',
  import: 'default',
}) as Record<string, string>

function parseDocument(raw: string) {
  const normalized = raw.replace(/\r\n/g, '\n')
  const match = normalized.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/)
  if (!match) throw new Error('Invalid article front matter')
  const header = Object.fromEntries(
    match[1].split('\n').map((line) => {
      const index = line.indexOf(':')
      return [line.slice(0, index).trim(), line.slice(index + 1).trim()]
    }),
  )
  return { title: header.title, excerpt: header.excerpt, body: match[2].trim() }
}

export function getArticle(locale: Locale, slug: string): Article | undefined {
  const meta = articleMeta.find((item) => item.slug === slug)
  if (!meta) return undefined
  const entry = Object.entries(modules).find(([path]) => path.endsWith(`/${locale}/${slug}.md`))
  if (!entry) return undefined
  const document = parseDocument(entry[1])
  const wordCount = locale === 'zh'
    ? document.body.replace(/\s/g, '').length
    : document.body.split(/\s+/).length
  return { ...meta, ...document, readingMinutes: Math.max(4, Math.ceil(wordCount / (locale === 'zh' ? 420 : 220))) }
}

export function listArticles(locale: Locale): Article[] {
  return articleMeta.map((item) => getArticle(locale, item.slug)).filter((item): item is Article => Boolean(item))
}
