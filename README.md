# Fish · AI Engineering Notes

Fish 的多语言个人博客：用工程经验连接量化研究、数据智能与企业级
AI。Vue 3 + TypeScript + Vite SSG 构建，服务器只托管静态文件。

## 功能

- 中文根路径，英文 `/en/`、日文 `/ja/`，共五篇三语首发文章。
- `bright`、`tech-black`、`cute-pink` 三套持久化主题。
- 首页、文章、项目、官方 AI 动态、匿名留言和隐藏管理页。
- 预渲染 metadata、分享图、站点地图；支持减少动效、减少透明度和高
  对比度偏好。
- 留言与 AI 新闻复用 AI 量化 FastAPI/MySQL，不运行额外博客后端。

## 本地开发

```powershell
npm install
npm run typecheck
npm test
npm run build
npm run dev
```

DeepSeek 只在开发阶段生成静态翻译：

```powershell
pwsh -File scripts/translate-content.ps1
```

真实凭据统一存放在被忽略的 `credentials.txt`，并支持项目命名空间。
兄弟项目存在自己的 `credentials.txt` 时优先使用本地文件；本地文件缺失
时读取博客共享文件。可从现有三个项目的本地配置安全同步，脚本不会输出
任何值：

```powershell
pwsh -File scripts/sync-shared-credentials.ps1
```

脱敏结构见 [`credentials.example.txt`](credentials.example.txt)。DeepSeek
token 只在本地翻译或部署阶段读取，不进入浏览器。
生产构建关闭 source map，仅保守混淆自有业务 chunk；vendor 不混淆。

## 部署

统一 Nginx、Java 内存上限、release 与回滚说明见
[`docs/deployment.md`](docs/deployment.md)。默认生产地址：
[https://101.132.78.217/](https://101.132.78.217/)。

## License

[MIT](LICENSE)
