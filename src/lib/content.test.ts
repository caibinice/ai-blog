import { describe, expect, it } from 'vitest'
import { articleMeta, getArticle, listArticles } from './articles'
import { localizedPath, type Locale } from './i18n'

describe('localized static content', () => {
  const locales: Locale[] = ['zh', 'en', 'ja']

  it.each(locales)('ships all five articles in %s', (locale) => {
    const articles = listArticles(locale)
    expect(articles).toHaveLength(5)
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
})
