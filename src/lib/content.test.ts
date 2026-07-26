import { describe, expect, it } from 'vitest'
import { articleMeta, getArticle, listArticles } from './articles'
import { copy, localizedPath, type Locale } from './i18n'

describe('localized static content', () => {
  const locales: Locale[] = ['zh', 'en', 'ja']

  it.each(locales)('ships all six articles in %s', (locale) => {
    const articles = listArticles(locale)
    expect(articles).toHaveLength(6)
    expect(articles.map(({ slug }) => slug)).toEqual(articleMeta.map(({ slug }) => slug))
    expect(articles.every(({ title, excerpt, body }) => title && excerpt && body.length > 500)).toBe(true)
  })

  it('keeps project navigation in every translated article', () => {
    for (const locale of locales) {
      for (const meta of articleMeta.filter(({ projectPath }) => projectPath)) {
        expect(getArticle(locale, meta.slug)?.body).toContain(meta.projectPath)
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
})
