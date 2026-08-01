# 同机部署与回滚

博客是 Vite SSG 静态产物，根路径公开；服务器不安装 Node 或 Maven。
统一 Nginx 配置同时托管：

- `/`：博客。
- `/quant/`：AI 量化公开查看，采集、AI、回测和配置写操作使用后端短期令牌。
- `/crossBorderTrend/`：公开前台，采集使用操作令牌，管理区使用项目 JWT。
- `/smartCockpit/`：智能座舱公开查看，聊天、上传和报告等操作使用后端短期令牌。

本地运行 `pwsh -File scripts/deploy.ps1` 会按 lockfile 重装三个前端依赖，
执行博客检查、两个 Java 项目测试/打包及各自前端生产构建，再上传静态文件
和 JAR。release 分别位于各自
`/opt/.../releases/<timestamp-commit>`；`current` 软链接原子切换，最近
保留五版。服务器仅安装 OpenJDK 17 headless。

发布机必须按 [`new-machine-setup.md`](new-machine-setup.md) 将四个仓库以固定
目录名放在同一父目录；量化仓库使用 `agent/research-infrastructure`，其余
三个使用 `main`。发布脚本启动时会先验证目录、origin、分支、基础工具和
共享凭据，并在缺少依赖时提示先运行统一 bootstrap。

环境文件和管理令牌在 `/opt/.../shared`，统一操作口令及签名密钥的本地
副本位于忽略的 `.deploy/action-auth.json`。口令不进入前端、README 或
Git。数据库、模型、Rakuten 和 SSH 等真实凭据默认从博客根目录下被忽略
的 `credentials.txt` 读取；某个项目根目录存在自己的 `credentials.txt`
时，本地文件完整覆盖该项目的共享配置。共享文件中的项目专属段使用
`quant.*`、`crossborder.*`、`cockpit.*` 前缀。
`[platform.action] password` 提供首次部署所需的统一操作口令；本机签名
密钥仍只生成在 `.deploy/`，无需跨机器复制。

回滚时将对应项目的 `current` 指向上一 release，修复其
`www/<path>` 软链接并重启对应服务。切换 Nginx 前必须执行
`nginx -t`。

发布完成后会启动一次性 5 分钟资源采样，不增加常驻监控。如果命中
“任一 CPU/内存超过 80%，或两者同时超过 70%”，先停用智能座舱；再次
超阈值再停用跨境后端。结果写入博客 `runtime-status.json`。

生产混淆只提高直接阅读业务 chunk 的成本。公开仓库里的 Vue 源码和
Markdown 文章本来就是公开内容，混淆不能被当作秘密保护。
