param(
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Codes = Split-Path -Parent $Root
$Python = Join-Path $Codes 'ai-quantitative-trading\.venv\Scripts\python.exe'

& (Join-Path $Root 'scripts\bootstrap-workspace.ps1') -CodesRoot $Codes
if ($LASTEXITCODE -ne 0) { throw '四仓库工作区检查失败。' }
if (-not (Test-Path -LiteralPath $Python)) {
    throw '缺少 ai-quantitative-trading\.venv。请先运行 scripts\bootstrap-workspace.ps1 -InstallDependencies。'
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
    if ($LASTEXITCODE -ne 0) { throw '博客构建失败。' }
    if ($BuildOnly) {
        Write-Host '博客本地构建完成，未连接远程服务器。' -ForegroundColor Green
        return
    }
    & $Python (Join-Path $Root 'scripts\remote\deploy_blog.py')
    if ($LASTEXITCODE -ne 0) { throw '博客静态发布失败。' }
} finally {
    Pop-Location
}
