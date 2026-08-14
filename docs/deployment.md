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
目录名放在同一父目录；四个仓库都使用 `main`。发布脚本启动时会先验证
目录、origin、分支、基础工具和
共享凭据，并在缺少依赖时提示先运行统一 bootstrap。

## 域名、HTTPS 与 ICP

生产主站固定为 `https://caibinice.com`，证书同时包含
`caibinice.com` 与 `www.caibinice.com`；HTTP 和 `www` HTTPS 请求统一
301 到主站。`https://101.132.78.217` 继续使用单独的短期 IP 证书，作为
备案期间的运维备用入口。服务器位于中国内地的阿里云实例时仍应完成域名
ICP 备案；仅完成 A 记录解析并不代表所有公网链路都会持续放行。

```powershell
curl.exe --noproxy "*" -I `
  http://caibinice.com/.well-known/acme-challenge/preflight
```

备案前可通过 DNS-01 TXT 验证签发域名证书，这项验证只依赖 DNS 控制权，
与 80/443 端口是否已放行无关。当前证书目录为
`/opt/ai-quantitative-trading/shared/letsencrypt/live/caibinice.com`，同时覆盖
根域名与 `www`。统一 Nginx 为域名证书和 IP 证书设置独立 TLS server，
公共路由位于 `/etc/nginx/snippets/ai-platform-routes.conf`。

在 AliDNS 最小权限 API 凭据接入前，手工 DNS-01 域名证书设置为
`autorenew = False`，避免定时任务等待人工 TXT 记录；到期前需要再次手工
验证或接入 AliDNS 自动化后重新启用。`ai-quant-cert-renew.timer` 继续负责
短期 IP 证书，运行时间为北京时间 03:17 和 12:17，避开 DeepSeek 峰值
计价时段。

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
