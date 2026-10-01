import type { Locale } from './i18n'

export interface ProjectCard {
  key: string
  title: Record<Locale, string>
  description: Record<Locale, string>
  path: string
  image: string
  stack: string[]
  accent: string
}

export const projects: ProjectCard[] = [
  {
    key: 'parking',
    title: { zh: '智慧停车三维数字孪生', en: '3D Smart Parking', ja: 'スマート駐車場デジタルツイン' },
    description: {
      zh: '把园区三维场景、泊位态势、区域导航和告警交互连接起来，提供触控友好的轻量手机版。',
      en: 'An interactive campus twin with occupancy, zone navigation, demo alerts, and a lightweight touch-first mobile view.',
      ja: '園区の3D表示、駐車状況、エリア移動、通知を統合。タッチ操作に適した軽量モバイル版も提供。',
    },
    path: '/smartParking/',
    image: '/images/project-parking.png',
    stack: ['Angular', 'Babylon.js', 'WebGPU', 'glTF'],
    accent: '#14b8a6',
  },
  {
    key: 'quant',
    title: { zh: 'AI 量化研究舱', en: 'AI Quant Research Cockpit', ja: 'AIクオンツ研究コックピット' },
    description: {
      zh: '把行情、财务、舆情、因子、回测和学习路径放进同一条可审计的研究闭环。',
      en: 'An auditable research loop for market data, fundamentals, sentiment, factors, backtests, and learning.',
      ja: '市場データ、財務、センチメント、因子、バックテスト、学習を監査可能な研究ループに統合。',
    },
    path: '/quant/',
    image: '/images/project-quant.png',
    stack: ['React', 'FastAPI', 'MySQL', 'DeepSeek'],
    accent: '#6d5dfc',
  },
  {
    key: 'crossborder',
    title: { zh: '跨境电商趋势报告', en: 'Cross-border Trend Report', ja: '越境ECトレンドレポート' },
    description: {
      zh: '从多源商品、搜索趋势和汇率中形成可追溯的选品日报与利润判断。',
      en: 'Traceable product discovery and margin analysis from multi-source catalogs, trends, and exchange rates.',
      ja: '複数の商品ソース、検索トレンド、為替から、追跡可能な商品選定と利益分析を生成。',
    },
    path: '/crossBorderTrend/',
    image: '/images/project-crossborder.png',
    stack: ['Vue', 'Spring Boot', 'MySQL', 'DeepSeek'],
    accent: '#0ea5a0',
  },
  {
    key: 'cockpit',
    title: { zh: '企业智能座舱', en: 'Enterprise AI Cockpit', ja: 'エンタープライズAIコックピット' },
    description: {
      zh: '让企业知识、向量检索、实时流式回答和经营图表在一个工作台中形成证据链。',
      en: 'A single workspace connecting enterprise knowledge, vector retrieval, streaming answers, and business charts.',
      ja: '企業知識、ベクトル検索、ストリーミング回答、経営チャートを一つの証拠チェーンへ。',
    },
    path: '/smartCockpit/',
    image: '/images/project-cockpit.png',
    stack: ['Vue', 'WebFlux', 'Spring AI', 'pgvector'],
    accent: '#ec4899',
  },
]
