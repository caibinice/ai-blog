import { describe, expect, it } from 'vitest'
import { articleMeta, articlePageCount, getArticle, listArticlePage, listArticles } from './articles'
import { copy, localizedPath, type Locale } from './i18n'

describe('localized static content', () => {
  const locales: Locale[] = ['zh', 'en', 'ja']

  it.each(locales)('ships every registered article in %s', (locale) => {
    const articles = listArticles(locale)
    expect(articles).toHaveLength(articleMeta.length)
    expect(articles.map(({ slug }) => slug)).toEqual(articleMeta.map(({ slug }) => slug))
    expect(articles.every(({ title, excerpt, body }) => title && excerpt && body.length > 500)).toBe(true)
  })

  it.each(locales)('builds deterministic static article pages in %s', (locale) => {
    expect(articlePageCount()).toBe(2)
    expect(listArticlePage(locale, 1)).toHaveLength(6)
    expect(listArticlePage(locale, 1)[0].slug).toBe('agent-node-monitoring-replay')
    expect(listArticlePage(locale, 2).map(({ slug }) => slug)).toEqual(['multi-branch-feature-migration', 'enterprise-ai-cockpit', 'llm-sentiment-walk-forward', 'cross-border-trends', 'trust-the-backtest', 'ai-quant-system'])
  })

  it('keeps the requested writing dates and cockpit case links', () => {
    expect(getArticle('zh', 'agent-workflow-orchestration')?.date).toBe('2026-10-06')
    expect(getArticle('zh', 'agent-node-monitoring-replay')?.date).toBe('2026-10-15')
    for (const locale of locales) {
      for (const slug of ['agent-workflow-orchestration', 'agent-node-monitoring-replay']) {
        expect(getArticle(locale, slug)?.body).toContain('/smartCockpit/workflow')
        expect(getArticle(locale, slug)?.body).toContain('/images/cockpit-agent-')
      }
    }
  })

  it('keeps project navigation in every translated article', () => {
    for (const locale of locales) {
      for (const meta of articleMeta.filter(({ projectPath }) => projectPath)) {
        expect(getArticle(locale, meta.slug)?.body).toContain(meta.projectPath)
      }
    }
  })

  it('describes the complete cockpit graph before the two deep dives', () => {
    for (const locale of locales) {
      const workflow = getArticle(locale, 'agent-workflow-orchestration')!.body
      expect(workflow).toContain('/images/cockpit-agent-overview.png')
      for (const term of ['ReplaceStrategy', 'tool_plan', 'tool_execute', 'multi_plan', 'multi_review']) {
        expect(workflow).toContain(term)
      }
      const monitoring = getArticle(locale, 'agent-node-monitoring-replay')!.body
      for (const term of ['vision', 'retrieve', 'requery', 'report_mcp', 'human_reply', 'run.resumed']) {
        expect(monitoring).toContain(term)
      }
    }
  })

  it('builds shareable locale paths', () => {
    expect(localizedPath('zh', '/articles')).toBe('/articles')
    expect(localizedPath('en', '/articles')).toBe('/en/articles')
    expect(localizedPath('ja', '/articles')).toBe('/ja/articles')
  })

  it('keeps the complete interface copy aligned across languages', () => {
    const keys = Object.keys(copy.zh).sort()
    expect(Object.keys(copy.en).sort()).toEqual(keys)
    expect(Object.keys(copy.ja).sort()).toEqual(keys)
    expect(JSON.stringify(copy)).not.toMatch(/tokyo/i)
    expect(new Set([copy.zh.writingBody, copy.en.writingBody, copy.ja.writingBody]).size).toBe(3)
    expect(new Set([copy.zh.footerTagline, copy.en.footerTagline, copy.ja.footerTagline]).size).toBe(3)
  })

  it('keeps Fish as the visible name and localizes only the browser tab brand', () => {
    expect([copy.zh.brand, copy.en.brand, copy.ja.brand]).toEqual(['Fish', 'Fish', 'Fish'])
    expect([copy.zh.tabBrand, copy.en.tabBrand, copy.ja.tabBrand]).toEqual(['鱼非鱼', 'Fish', 'Fish'])
  })
})
