param(
  [string]$TargetPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$codesRoot = Split-Path -Parent $repoRoot
if ([string]::IsNullOrWhiteSpace($TargetPath)) {
  $TargetPath = Join-Path $repoRoot 'credentials.txt'
}

function Import-IniFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  $result = [ordered]@{}
  $section = ''
  foreach ($original in Get-Content -LiteralPath $Path) {
    $line = $original.Trim()
    if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) {
      continue
    }
    if ($line -match '^\[(.+)\]$') {
      $section = $Matches[1].Trim()
      if (-not $result.Contains($section)) {
        $result[$section] = [ordered]@{}
      }
      continue
    }
    $parts = $line.Split('=', 2)
    if ($parts.Count -eq 2 -and $section) {
      $result[$section][$parts[0].Trim()] = $parts[1].Trim()
    }
  }
  return $result
}

function Copy-IniSection {
  param(
    [Parameter(Mandatory = $true)]$Source,
    [Parameter(Mandatory = $true)][string]$SourceName,
    [Parameter(Mandatory = $true)]$Destination,
    [Parameter(Mandatory = $true)][string]$DestinationName
  )

  if ($Source.Contains($SourceName)) {
    $Destination[$DestinationName] = [ordered]@{}
    foreach ($key in $Source[$SourceName].Keys) {
      $Destination[$DestinationName][$key] = $Source[$SourceName][$key]
    }
  }
}

$projects = @(
  [pscustomobject]@{
    Namespace = 'quant'
    Path = Join-Path $codesRoot 'ai-quantitative-trading\credentials.txt'
  },
  [pscustomobject]@{
    Namespace = 'crossborder'
    Path = Join-Path $codesRoot 'crossborder-trend-report\credentials.txt'
  },
  [pscustomobject]@{
    Namespace = 'cockpit'
    Path = Join-Path $codesRoot 'enterprise-ai-cockpit\credentials.txt'
  }
)

$loaded = [ordered]@{}
foreach ($project in $projects) {
  if (Test-Path -LiteralPath $project.Path) {
    $loaded[$project.Namespace] = Import-IniFile -Path $project.Path
  }
}
if ($loaded.Count -eq 0) {
  throw 'No project-local credentials.txt files were found.'
}

$shared = [ordered]@{}
foreach ($section in @('remote.ssh', 'github', 'deepseek.api')) {
  foreach ($namespace in @('quant', 'cockpit', 'crossborder')) {
    if ($loaded.Contains($namespace) -and $loaded[$namespace].Contains($section)) {
      Copy-IniSection `
        -Source $loaded[$namespace] `
        -SourceName $section `
        -Destination $shared `
        -DestinationName $section
      break
    }
  }
}

# The operation password belongs to the shared platform rather than one project.
# Preserve it from an existing shared file, or migrate it from the ignored local
# deployment state once. Token signing secrets stay in .deploy and are not copied.
$existingTarget = if (Test-Path -LiteralPath $TargetPath) {
  Import-IniFile -Path $TargetPath
} else {
  [ordered]@{}
}
if ($existingTarget.Contains('platform.action')) {
  Copy-IniSection `
    -Source $existingTarget `
    -SourceName 'platform.action' `
    -Destination $shared `
    -DestinationName 'platform.action'
} else {
  $actionAuthPath = Join-Path $repoRoot '.deploy\action-auth.json'
  if (Test-Path -LiteralPath $actionAuthPath) {
    $actionAuth = Get-Content -LiteralPath $actionAuthPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($actionAuth.password)) {
      $shared['platform.action'] = [ordered]@{ password = $actionAuth.password }
    }
  }
}

foreach ($namespace in $loaded.Keys) {
  foreach ($section in $loaded[$namespace].Keys) {
    Copy-IniSection `
      -Source $loaded[$namespace] `
      -SourceName $section `
      -Destination $shared `
      -DestinationName "$namespace.$section"
  }
}

$relativeTarget = [System.IO.Path]::GetRelativePath($repoRoot, $TargetPath)
git -C $repoRoot check-ignore --quiet -- $relativeTarget
if ($LASTEXITCODE -ne 0) {
  throw "Refusing to write a credential file that is not ignored by Git: $TargetPath"
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Generated from project-local ignored credential files.')
$lines.Add('# Local project credentials take precedence; this file is the shared fallback.')
$lines.Add('')
foreach ($section in $shared.Keys) {
  $lines.Add("[$section]")
  foreach ($key in $shared[$section].Keys) {
    $lines.Add("$key=$($shared[$section][$key])")
  }
  $lines.Add('')
}

[System.IO.File]::WriteAllText(
  $TargetPath,
  ($lines -join "`n"),
  [System.Text.UTF8Encoding]::new($false)
)
Write-Output "Shared credentials updated with $($shared.Count) sections; values were not printed."
