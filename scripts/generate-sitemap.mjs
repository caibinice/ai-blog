import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve('dist')
const origin = process.env.SITE_ORIGIN || 'https://101.132.78.217'
const paths = []

function walk(directory, prefix = '') {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const relative = path.posix.join(prefix, entry.name)
    if (entry.isDirectory() && entry.name !== '.vite') {
      walk(path.join(directory, entry.name), relative)
    }
    if (entry.isFile() && entry.name.endsWith('.html')) {
      const withoutExtension = relative.slice(0, -'.html'.length)
      const route = withoutExtension === 'index'
        ? '/'
        : `/${withoutExtension.replace(/\/index$/, '')}`
      paths.push(route)
    }
  }
}

walk(root)
const urls = [...new Set(paths)]
  .filter((route) => !route.startsWith('/manage/') && route !== '/404/')
  .sort()
  .map((route) => `  <url><loc>${origin}${route === '/' ? '/' : route}</loc></url>`)
  .join('\n')
fs.writeFileSync(path.join(root, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`)
fs.writeFileSync(path.join(root, 'robots.txt'), `User-agent: *\nAllow: /\nDisallow: /manage/\nSitemap: ${origin}/sitemap.xml\n`)
fs.rmSync(path.join(root, '.vite'), { recursive: true, force: true })
