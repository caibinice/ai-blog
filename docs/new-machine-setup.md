# 新机器四仓库复现指南

目标是让开发机只保留四个 Git 仓库和一份不进 Git 的共享
`ai-blog/credentials.txt`。`.deploy/`、虚拟环境、`node_modules`、构建产物
和操作令牌都由脚本重建，不需要从旧机器复制。

## 1. 基础工具

- PowerShell 7、Git。
- Node.js 20.19+（推荐 22 LTS）与 npm。
- 64 位 Python 3.11+。
- JDK 17、Maven 3.9+。
- 本地 v2rayN HTTP 代理默认监听 `127.0.0.1:20808`。

四个仓库必须放在同一父目录，并保留下面的目录名。父目录不强制是
`D:\codes`：

```text
<codes-root>/
├── ai-blog/                  main
├── ai-quantum/               agent/research-infrastructure
├── crossborder-trend-report/ main
└── ai-agent-rag-demo/        main
```

量化仓库不是从默认分支运行，必须检出表中的
`agent/research-infrastructure`。

## 2. 克隆与同步

先克隆博客，然后可由统一脚本克隆其余仓库：

```powershell
Set-Location D:\codes
git -c http.proxy=http://127.0.0.1:20808 clone `
  https://github.com/caibinice/ai-blog.git ai-blog

pwsh -File .\ai-blog\scripts\bootstrap-workspace.ps1 `
  -CodesRoot D:\codes -CloneMissing -Sync -SkipCredentialValidation
```

也可以手工 clone；量化项目要显式使用：

```powershell
git clone --branch agent/research-infrastructure --single-branch `
  https://github.com/caibinice/ai-quantitative-trading.git ai-quantum
```

## 3. 只复制一份凭据

把旧机器的真实文件安全复制到：

```text
<codes-root>/ai-blog/credentials.txt
```

不要再复制到三个兄弟项目。项目根目录出现本地 `credentials.txt` 时，会
把它视为该项目的完整覆盖；只有本地文件不存在时才使用博客共享命名空间。
完整脱敏结构见 `credentials.example.txt`，至少应包含：

- `[github]`：GitHub token。
- `[remote.ssh]`：生产服务器连接。
- `[platform.action]`：三项目网页敏感操作的统一口令。
- `quant.*`、`crossborder.*`、`cockpit.*`：数据库、模型和数据源配置。

凭据复制完成后执行一次完整校验与依赖安装：

```powershell
pwsh -File .\ai-blog\scripts\bootstrap-workspace.ps1 `
  -CodesRoot D:\codes -Sync -InstallDependencies
```

脚本只输出段和键是否齐全，不输出任何值。真实凭据、`.deploy/` 和各类
coding-agent 目录均被 `.gitignore` 排除。

## 4. 构建与发布

统一发布入口：

```powershell
Set-Location D:\codes\ai-blog
pwsh -File scripts\deploy.ps1
```

只验证与发布完全相同的四仓库本地构建链、不连接服务器时使用：

```powershell
pwsh -File scripts\deploy.ps1 -BuildOnly
```

第一次发布会使用 `[platform.action] password` 生成本机忽略的签名密钥；
换机器后重新生成会让旧浏览器的短期会话失效，但不会改变操作密码和数据。
服务器环境文件会随发布重新下发，因此不需要复制旧机器的 `.deploy/`。

只发布博客或座舱时分别使用：

```powershell
pwsh -File D:\codes\ai-blog\scripts\deploy-blog.ps1

Set-Location D:\codes\ai-agent-rag-demo
& D:\codes\ai-quantum\.venv\Scripts\python.exe `
  scripts\remote\deploy_cockpit.py
```

## 5. 统一提交与推送

共享脚本从 `[github] token` 读取认证，只为单次 Git 命令设置代理和
Authorization header，不把 token 写进 remote URL 或 Git 配置。必须明确列出
要提交的文件，避免把其他 agent 或个人文件混入提交：

```powershell
pwsh -File D:\codes\ai-blog\scripts\github-push.ps1 `
  -Project cockpit `
  -Message 'docs: clarify reproducible workspace setup' `
  -Files @('README.md', 'docs/production-deployment.md')
```

`-Project` 可选 `blog`、`quant`、`crossborder`、`cockpit`。脚本会检查固定
分支、先 fetch 并拒绝覆盖远端新提交；仅推送已有本地提交时使用
`-PushOnly`，只检查认证和同步状态时使用 `-ValidateOnly`。
提交作者默认使用公开的 `caibinice` 和 GitHub noreply 地址，仅对当前脚本
进程生效；需要覆盖时在 `[github]` 增加 `user_name`、`user_email`，无需设置
新机器的全局 Git 配置。

## 6. 迁移验收清单

```powershell
# 四仓库、固定分支、工具与共享凭据
pwsh -File D:\codes\ai-blog\scripts\bootstrap-workspace.ps1

# GitHub token/代理链路（不会提交或推送）
pwsh -File D:\codes\ai-blog\scripts\github-push.ps1 `
  -Project blog -ValidateOnly

# 各项目质量门禁
pwsh -File D:\codes\ai-quantum\scripts\check.ps1
npm --prefix D:\codes\ai-blog run build
mvn -f D:\codes\crossborder-trend-report\backend\pom.xml test
mvn -f D:\codes\ai-agent-rag-demo\backend\pom.xml test
```
