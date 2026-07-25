$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Python = Join-Path (Split-Path -Parent $Root) 'ai-quantum\.venv\Scripts\python.exe'

Push-Location $Root
try {
    npm run typecheck
    if ($LASTEXITCODE -ne 0) { throw '博客类型检查失败。' }
    npm test
    if ($LASTEXITCODE -ne 0) { throw '博客测试失败。' }
    npm run build
    if ($LASTEXITCODE -ne 0) { throw '博客构建失败。' }
    & $Python (Join-Path $Root 'scripts\remote\deploy_blog.py')
    if ($LASTEXITCODE -ne 0) { throw '博客静态发布失败。' }
} finally {
    Pop-Location
}
