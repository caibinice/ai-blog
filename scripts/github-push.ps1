param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('blog', 'quant', 'crossborder', 'cockpit')]
  [string]$Project,
  [string]$Message = '',
  [string[]]$Files = @(),
  [string]$Proxy = 'http://127.0.0.1:20808',
  [switch]$ValidateOnly,
  [switch]$PushOnly
)

$ErrorActionPreference = 'Stop'
$blogRoot = Split-Path -Parent $PSScriptRoot
$codesRoot = Split-Path -Parent $blogRoot
$definitions = @{
  blog = @{ Directory = 'ai-blog'; Branch = 'main'; Namespace = 'blog' }
  quant = @{ Directory = 'ai-quantitative-trading'; Branch = 'main'; Namespace = 'quant' }
  crossborder = @{ Directory = 'crossborder-trend-report'; Branch = 'main'; Namespace = 'crossborder' }
  cockpit = @{ Directory = 'enterprise-ai-cockpit'; Branch = 'main'; Namespace = 'cockpit' }
}
$definition = $definitions[$Project]
$projectRoot = Join-Path $codesRoot $definition.Directory
$credentialsPath = Join-Path $blogRoot 'credentials.txt'

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

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.git'))) {
  throw "项目不存在或不是 Git 仓库：$projectRoot"
}
if (-not (Test-Path -LiteralPath $credentialsPath)) {
  throw "缺少共享凭据：$credentialsPath"
}
$credentials = Import-IniFile -Path $credentialsPath
$token = ''
foreach ($section in @("$($definition.Namespace).github", 'github')) {
  if ($credentials.ContainsKey($section) -and $credentials[$section].ContainsKey('token')) {
    $token = $credentials[$section]['token']
    break
  }
}
if ([string]::IsNullOrWhiteSpace($token)) {
  throw '共享 credentials.txt 缺少 [github] token。'
}
$githubSection = if ($credentials.ContainsKey("$($definition.Namespace).github")) {
  $credentials["$($definition.Namespace).github"]
} elseif ($credentials.ContainsKey('github')) {
  $credentials['github']
} else {
  @{}
}
$gitUserName = if ($githubSection.ContainsKey('user_name') -and -not [string]::IsNullOrWhiteSpace($githubSection['user_name'])) {
  $githubSection['user_name']
} else {
  'caibinice'
}
$gitUserEmail = if ($githubSection.ContainsKey('user_email') -and -not [string]::IsNullOrWhiteSpace($githubSection['user_email'])) {
  $githubSection['user_email']
} else {
  'caibinice@users.noreply.github.com'
}
$branch = (& git -C $projectRoot branch --show-current).Trim()
if ($branch -ne $definition.Branch) {
  throw "$Project 当前分支为 $branch，应为 $($definition.Branch)。"
}

$basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))
$gitEnvironmentNames = @(
  'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0',
  'GIT_CONFIG_KEY_1', 'GIT_CONFIG_VALUE_1',
  'GIT_CONFIG_KEY_2', 'GIT_CONFIG_VALUE_2',
  'GIT_CONFIG_KEY_3', 'GIT_CONFIG_VALUE_3'
)
$previousEnvironment = @{}
foreach ($name in $gitEnvironmentNames) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
  $env:GIT_CONFIG_COUNT = '4'
  $env:GIT_CONFIG_KEY_0 = 'http.proxy'
  $env:GIT_CONFIG_VALUE_0 = $Proxy
  $env:GIT_CONFIG_KEY_1 = 'http.https://github.com/.extraheader'
  $env:GIT_CONFIG_VALUE_1 = "AUTHORIZATION: basic $basic"
  $env:GIT_CONFIG_KEY_2 = 'user.name'
  $env:GIT_CONFIG_VALUE_2 = $gitUserName
  $env:GIT_CONFIG_KEY_3 = 'user.email'
  $env:GIT_CONFIG_VALUE_3 = $gitUserEmail

  & git -C $projectRoot fetch origin $definition.Branch
  if ($LASTEXITCODE -ne 0) { throw 'GitHub fetch 失败。' }
  $divergenceText = ((& git -C $projectRoot rev-list --left-right --count "HEAD...origin/$($definition.Branch)") -join ' ').Trim()
  $divergence = $divergenceText -split '\s+'
  $localAhead = [int]$divergence[0]
  $remoteAhead = [int]$divergence[1]
  if ($remoteAhead -gt 0) {
    throw "远端领先 $remoteAhead 个提交，请先执行 bootstrap-workspace.ps1 -Sync。"
  }
  if ($ValidateOnly) {
    Write-Host "OK project=$Project branch=$branch localAhead=$localAhead remoteAhead=$remoteAhead token=loaded proxy=$Proxy"
    return
  }
  if ($PushOnly) {
    if ($localAhead -eq 0) {
      Write-Host "$Project 已与远端同步，无需推送。"
      return
    }
  } else {
    if ($localAhead -gt 0) {
      throw "本地已有 $localAhead 个未推送提交；请先用 -PushOnly 推送或人工确认。"
    }
    if ([string]::IsNullOrWhiteSpace($Message) -or $Files.Count -eq 0) {
      throw '提交模式必须同时提供 -Message 和明确的 -Files。'
    }
    & git -C $projectRoot diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
      throw '仓库已有暂存内容；为避免混入无关修改，请先处理暂存区。'
    }
    & git -C $projectRoot add -- @Files
    if ($LASTEXITCODE -ne 0) { throw '暂存指定文件失败。' }
    & git -C $projectRoot diff --cached --quiet
    if ($LASTEXITCODE -eq 0) { throw '指定文件没有可提交的变化。' }
    & git -C $projectRoot diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw '暂存内容检查失败。' }
    & git -C $projectRoot commit -m $Message
    if ($LASTEXITCODE -ne 0) { throw 'Git 提交失败。' }
  }
  & git -C $projectRoot push origin $definition.Branch
  if ($LASTEXITCODE -ne 0) { throw 'GitHub 推送失败。' }
  $revision = (& git -C $projectRoot rev-parse --short HEAD).Trim()
  Write-Host "Pushed project=$Project branch=$branch commit=$revision" -ForegroundColor Green
} finally {
  foreach ($name in $gitEnvironmentNames) {
    [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
  }
}
