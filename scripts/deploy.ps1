$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Codes = Split-Path -Parent $Root
$Python = Join-Path $Codes 'ai-quantum\.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $Python)) {
    throw '缺少 ai-quantum\.venv，无法使用既有安全 SSH 发布工具。'
}

Push-Location $Root
try {
    npm run typecheck
    if ($LASTEXITCODE -ne 0) { throw '博客类型检查失败。' }
    npm test
    if ($LASTEXITCODE -ne 0) { throw '博客测试失败。' }
    npm run build
    if ($LASTEXITCODE -ne 0) { throw '博客生产构建失败。' }
} finally {
    Pop-Location
}

& mvn -q -f (Join-Path $Codes 'crossborder-trend-report\backend\pom.xml') package
if ($LASTEXITCODE -ne 0) { throw '跨境项目 Maven 打包失败。' }
& mvn -q -f (Join-Path $Codes 'ai-agent-rag-demo\backend\pom.xml') package
if ($LASTEXITCODE -ne 0) { throw '智能座舱 Maven 打包失败。' }

& $Python (Join-Path $Root 'scripts\remote\deploy.py') --prepare-only
if ($LASTEXITCODE -ne 0) { throw '本地部署密钥准备失败。' }

& (Join-Path $Codes 'ai-quantum\scripts\deploy.ps1')
if ($LASTEXITCODE -ne 0) { throw '量化项目发布失败。' }

& $Python (Join-Path $Root 'scripts\remote\deploy.py')
if ($LASTEXITCODE -ne 0) { throw '博客与 Java 项目发布失败。' }
