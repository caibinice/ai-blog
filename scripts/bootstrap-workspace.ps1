param(
  [string]$CodesRoot = '',
  [string]$Proxy = 'http://127.0.0.1:20808',
  [switch]$CloneMissing,
  [switch]$Sync,
  [switch]$InstallDependencies,
  [switch]$SkipCredentialValidation
)

$ErrorActionPreference = 'Stop'
$blogRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CodesRoot)) {
  $CodesRoot = Split-Path -Parent $blogRoot
}
$CodesRoot = [IO.Path]::GetFullPath($CodesRoot)

$projects = @(
  [pscustomobject]@{
    Name = 'blog'; Directory = 'ai-blog'; Branch = 'main'
    Remote = 'https://github.com/caibinice/ai-blog.git'
  },
  [pscustomobject]@{
    Name = 'quant'; Directory = 'ai-quantitative-trading'; Branch = 'main'
    Remote = 'https://github.com/caibinice/ai-quantitative-trading.git'
  },
  [pscustomobject]@{
    Name = 'crossborder'; Directory = 'crossborder-trend-report'; Branch = 'main'
    Remote = 'https://github.com/caibinice/crossborder-trend-report.git'
  },
  [pscustomobject]@{
    Name = 'cockpit'; Directory = 'enterprise-ai-cockpit'; Branch = 'main'
    Remote = 'https://github.com/caibinice/enterprise-ai-cockpit.git'
  }
)

function Assert-Command {
  param([Parameter(Mandatory = $true)][string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "缺少命令 $Name。请先按 docs/new-machine-setup.md 安装基础工具。"
  }
}

function Normalize-GitRemote {
  param([Parameter(Mandatory = $true)][string]$Value)
  return ($Value.Trim().TrimEnd('/') -replace '\.git$', '').ToLowerInvariant()
}

function Import-IniFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  $result = @{}
  $section = ''
  foreach ($original in Get-Content -LiteralPath $Path -Encoding UTF8) {
    $line = $original.Trim()
    if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
    if ($line -match '^\[(.+)\]$') {
      $section = $Matches[1].Trim().ToLowerInvariant()
      if (-not $result.ContainsKey($section)) { $result[$section] = @{} }
      continue
    }
    $parts = $line.Split('=', 2)
    if ($parts.Count -eq 2 -and $section) {
      $result[$section][$parts[0].Trim().ToLowerInvariant()] = $parts[1].Trim()
    }
  }
  return $result
}

function Assert-CredentialSection {
  param(
    [Parameter(Mandatory = $true)]$Credentials,
    [Parameter(Mandatory = $true)][string[]]$Sections,
    [Parameter(Mandatory = $true)][string[]]$Keys
  )
  $resolved = $null
  foreach ($candidate in $Sections) {
    $normalized = $candidate.ToLowerInvariant()
    if ($Credentials.ContainsKey($normalized)) {
      $resolved = $Credentials[$normalized]
      break
    }
  }
  if ($null -eq $resolved) {
    throw "credentials.txt 缺少 [$($Sections[0])]。"
  }
  foreach ($key in $Keys) {
    $normalizedKey = $key.ToLowerInvariant()
    $value = if ($resolved.ContainsKey($normalizedKey)) { $resolved[$normalizedKey] } else { '' }
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '(?i)^(<.*>|.*placeholder.*|.*example.*|your[-_].*|.*-token)$') {
      throw "credentials.txt 的 [$($Sections[0])] $key 未配置。"
    }
  }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw '需要 PowerShell 7 或更高版本。'
}
foreach ($command in @('git', 'node', 'npm', 'python', 'java', 'mvn')) {
  Assert-Command -Name $command
}
$nodeVersion = (& node --version).TrimStart('v')
if ([version]$nodeVersion -lt [version]'20.19.0') {
  throw "Node.js 版本过低：$nodeVersion；至少需要 20.19，推荐 22 LTS。"
}
$pythonVersionText = & python --version 2>&1
if ($pythonVersionText -notmatch '(\d+)\.(\d+)') {
  throw '无法识别 Python 版本。'
}
if ([int]$Matches[1] -lt 3 -or ([int]$Matches[1] -eq 3 -and [int]$Matches[2] -lt 11)) {
  throw "Python 版本过低：$pythonVersionText；至少需要 3.11。"
}

New-Item -ItemType Directory -Force -Path $CodesRoot | Out-Null
foreach ($project in $projects) {
  $projectRoot = Join-Path $CodesRoot $project.Directory
  if (-not (Test-Path -LiteralPath $projectRoot)) {
    if (-not $CloneMissing) {
      throw "缺少 $projectRoot。使用 -CloneMissing 自动克隆。"
    }
    & git -c "http.proxy=$Proxy" clone --branch $project.Branch --single-branch $project.Remote $projectRoot
    if ($LASTEXITCODE -ne 0) { throw "克隆 $($project.Name) 失败。" }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.git'))) {
    throw "$projectRoot 不是 Git 仓库。"
  }
  $origin = (& git -C $projectRoot remote get-url origin).Trim()
  if ((Normalize-GitRemote $origin) -ne (Normalize-GitRemote $project.Remote)) {
    throw "$($project.Name) origin 不符合预期：$origin"
  }
  $trackedChanges = @(& git -C $projectRoot status --porcelain --untracked-files=no)
  $branch = (& git -C $projectRoot branch --show-current).Trim()
  if ($branch -ne $project.Branch) {
    if (-not $Sync) {
      throw "$($project.Name) 当前分支为 $branch，应为 $($project.Branch)。"
    }
    if ($trackedChanges.Count) {
      throw "$($project.Name) 有未提交的跟踪文件修改，不能自动切换分支。"
    }
    & git -C $projectRoot switch $project.Branch
    if ($LASTEXITCODE -ne 0) { throw "切换 $($project.Name) 分支失败。" }
  }
  if ($Sync) {
    if ($trackedChanges.Count) {
      throw "$($project.Name) 有未提交的跟踪文件修改，不能自动同步。"
    }
    & git -C $projectRoot -c "http.proxy=$Proxy" fetch origin $project.Branch
    if ($LASTEXITCODE -ne 0) { throw "获取 $($project.Name) 远端更新失败。" }
    & git -C $projectRoot -c "http.proxy=$Proxy" pull --ff-only origin $project.Branch
    if ($LASTEXITCODE -ne 0) { throw "同步 $($project.Name) 失败。" }
  }
  Write-Host "OK repo=$($project.Directory) branch=$($project.Branch)"
}

$sharedCredentials = Join-Path $CodesRoot 'ai-blog\credentials.txt'
if (-not $SkipCredentialValidation) {
  if (-not (Test-Path -LiteralPath $sharedCredentials)) {
    throw "缺少共享凭据：$sharedCredentials"
  }
  $credentials = Import-IniFile -Path $sharedCredentials
  Assert-CredentialSection $credentials @('github') @('token')
  Assert-CredentialSection $credentials @('remote.ssh') @('host', 'port', 'user', 'password', 'root_password')
  Assert-CredentialSection $credentials @('platform.action') @('password')
  Assert-CredentialSection $credentials @('quant.mysql.remote', 'mysql.remote') @('host', 'port', 'database', 'user', 'password')
  Assert-CredentialSection $credentials @('crossborder.mysql.remote') @('host', 'port', 'database', 'user', 'password')
  Assert-CredentialSection $credentials @('crossborder.rakuten.api') @('application_id', 'access_key', 'affiliate_id')
  Assert-CredentialSection $credentials @('cockpit.mysql.remote') @('host', 'port', 'database', 'user', 'password')
  Assert-CredentialSection $credentials @('cockpit.postgresql.vector') @('host', 'port', 'database', 'user', 'password')
  Assert-CredentialSection $credentials @('cockpit.deepseek.api', 'deepseek.api') @('base-url', 'api-key', 'model')
  Assert-CredentialSection $credentials @('cockpit.amap.api') @('api-key')
  Write-Host 'OK credentials=shared namespaces validated (values hidden)'
}

if ($InstallDependencies) {
  Push-Location (Join-Path $CodesRoot 'ai-blog')
  try { npm ci --no-audit --no-fund; if ($LASTEXITCODE -ne 0) { throw '博客依赖安装失败。' } } finally { Pop-Location }

  & (Join-Path $CodesRoot 'ai-quantitative-trading\scripts\setup.ps1')
  if ($LASTEXITCODE -ne 0) { throw '量化项目依赖安装失败。' }

  foreach ($directory in @('crossborder-trend-report', 'enterprise-ai-cockpit')) {
    Push-Location (Join-Path $CodesRoot "$directory\frontend")
    try { npm ci --no-audit --no-fund; if ($LASTEXITCODE -ne 0) { throw "$directory 前端依赖安装失败。" } } finally { Pop-Location }
  }
  Write-Host 'OK dependencies=installed from lock files'
}

Write-Host "Workspace ready: $CodesRoot" -ForegroundColor Green
