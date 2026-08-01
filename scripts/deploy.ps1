param(
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Codes = Split-Path -Parent $Root
$Python = Join-Path $Codes 'ai-quantum\.venv\Scripts\python.exe'

& (Join-Path $Root 'scripts\bootstrap-workspace.ps1') -CodesRoot $Codes
if ($LASTEXITCODE -ne 0) { throw '四仓库工作区检查失败。' }

if (-not (Test-Path -LiteralPath $Python)) {
    throw '缺少 ai-quantum\.venv。请先运行 scripts\bootstrap-workspace.ps1 -InstallDependencies。'
}

Push-Location $Root
try {
    npm ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw '博客依赖安装失败。' }
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
Push-Location (Join-Path $Codes 'crossborder-trend-report\frontend')
try {
    npm ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw '跨境项目前端依赖安装失败。' }
    npm test
    if ($LASTEXITCODE -ne 0) { throw '跨境项目前端测试失败。' }
    npm run build
    if ($LASTEXITCODE -ne 0) { throw '跨境项目前端构建失败。' }
} finally {
    Pop-Location
}
& mvn -q -f (Join-Path $Codes 'ai-agent-rag-demo\backend\pom.xml') package
if ($LASTEXITCODE -ne 0) { throw '智能座舱 Maven 打包失败。' }
Push-Location (Join-Path $Codes 'ai-agent-rag-demo\frontend')
try {
    npm ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw '智能座舱前端依赖安装失败。' }
    npm run build
    if ($LASTEXITCODE -ne 0) { throw '智能座舱前端构建失败。' }
} finally {
    Pop-Location
}

if ($BuildOnly) {
    & (Join-Path $Codes 'ai-quantum\scripts\deploy.ps1') -BuildOnly
    if ($LASTEXITCODE -ne 0) { throw '量化项目本地检查失败。' }
    Write-Host '四仓库本地构建与测试完成，未连接远程服务器。' -ForegroundColor Green
    return
}

& $Python (Join-Path $Root 'scripts\remote\deploy.py') --prepare-only
if ($LASTEXITCODE -ne 0) { throw '本地部署密钥准备失败。' }

& (Join-Path $Codes 'ai-quantum\scripts\deploy.ps1')
if ($LASTEXITCODE -ne 0) { throw '量化项目发布失败。' }

& $Python (Join-Path $Root 'scripts\remote\deploy.py')
if ($LASTEXITCODE -ne 0) { throw '博客与 Java 项目发布失败。' }
