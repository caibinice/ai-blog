# 同机部署与回滚

博客是 Vite SSG 静态产物，根路径公开；服务器不安装 Node 或 Maven。
统一 Nginx 配置同时托管：

- `/`：博客。
- `/quant/`：AI 量化，Basic Auth。
- `/crossBorderTrend/`：公开前台，管理区使用项目 JWT。
- `/smartCockpit/`：智能座舱，复用量化 Basic Auth。

本地运行 `pwsh -File scripts/deploy.ps1` 会执行博客检查、两个 Java 项目
测试/打包，并上传静态文件和 JAR。release 分别位于各自
`/opt/.../releases/<timestamp-commit>`；`current` 软链接原子切换，最近
保留五版。服务器仅安装 OpenJDK 17 headless。

环境文件和管理令牌在 `/opt/.../shared`，本地副本位于忽略的
`.deploy/`。回滚时将对应项目的 `current` 指向上一 release，修复其
`www/<path>` 软链接并重启对应服务。切换 Nginx 前必须执行
`nginx -t`。

发布完成后会启动一次性 5 分钟资源采样，不增加常驻监控。如果命中
“任一 CPU/内存超过 80%，或两者同时超过 70%”，先停用智能座舱；再次
超阈值再停用跨境后端。结果写入博客 `runtime-status.json`。

生产混淆只提高直接阅读业务 chunk 的成本。公开仓库里的 Vue 源码和
Markdown 文章本来就是公开内容，混淆不能被当作秘密保护。
