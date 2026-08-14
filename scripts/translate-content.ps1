param(
    [string]$CredentialsPath = '',
    [string]$Proxy = 'http://127.0.0.1:20808',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CredentialsPath)) {
    $shared = Join-Path $repoRoot 'credentials.txt'
    $legacy = Join-Path (Split-Path $repoRoot -Parent) 'ai-quantitative-trading\credentials.txt'
    $CredentialsPath = if (Test-Path -LiteralPath $shared) { $shared } else { $legacy }
}
$Root = Split-Path -Parent $PSScriptRoot

function Read-IniSection {
    param([string]$Path, [string]$Section)
    $values = @{}
    $current = ''
    foreach ($raw in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            $current = $line.Substring(1, $line.Length - 2)
            continue
        }
        if ($current -eq $Section -and $line.Contains('=')) {
            $parts = $line.Split('=', 2)
            $values[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
    return $values
}

function Invoke-Translation {
    param([string]$Text, [string]$Language, [ValidateSet('markdown', 'json')][string]$Format)
    $instruction = if ($Format -eq 'markdown') {
        "Translate the following Chinese Markdown into $Language. Preserve the YAML front matter keys, Markdown structure, code, URLs, project paths, product names, and technical identifiers. Translate title and excerpt values. Keep the first-person beginner voice natural and restrained. Return only the complete translated Markdown without code fences."
    } else {
        "Translate every Chinese string value in the following JSON into $Language. Preserve all keys, nesting, product names, and the literal brand Fish. Return valid JSON only, without code fences or commentary."
    }
    $payload = @{
        model = $script:Model
        thinking = @{ type = 'enabled' }
        reasoning_effort = 'max'
        messages = @(
            @{ role = 'system'; content = 'You are a careful technical editor for a multilingual personal engineering blog.' }
            @{ role = 'user'; content = "$instruction`n`n$Text" }
        )
    } | ConvertTo-Json -Depth 8
    $invokeParams = @{
        Uri = "$($script:BaseUrl.TrimEnd('/'))/chat/completions"
        Method = 'Post'
        Headers = @{ Authorization = "Bearer $script:ApiKey" }
        ContentType = 'application/json; charset=utf-8'
        Body = [Text.Encoding]::UTF8.GetBytes($payload)
        TimeoutSec = 180
    }
    if ($Proxy) { $invokeParams.Proxy = $Proxy }
    $response = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $response = Invoke-RestMethod @invokeParams
            break
        } catch {
            if ($attempt -eq 3) { throw }
            Write-Warning "DeepSeek request failed (attempt $attempt/3); retrying in $($attempt * 2)s."
            Start-Sleep -Seconds ($attempt * 2)
        }
    }
    $content = [string]$response.choices[0].message.content
    $content = $content.Trim()
    if ($content.StartsWith('```')) {
        $content = $content -replace '^```(?:markdown|json)?\s*', '' -replace '\s*```$', ''
    }
    return $content.Trim()
}

if (-not (Test-Path -LiteralPath $CredentialsPath)) {
    throw "Credentials file not found: $CredentialsPath"
}
$deepseek = Read-IniSection -Path $CredentialsPath -Section 'deepseek.api'
$script:ApiKey = $deepseek['api-key']
$script:BaseUrl = if ($deepseek['base-url']) { $deepseek['base-url'] } else { 'https://api.deepseek.com' }
$script:Model = if ($deepseek['model']) { $deepseek['model'] } else { 'deepseek-v4-flash' }
if (-not $script:ApiKey) { throw 'deepseek.api api-key is missing.' }

$targets = @(
    @{ Code = 'en'; Language = 'English' },
    @{ Code = 'ja'; Language = 'Japanese' }
)

foreach ($target in $targets) {
    $uiDestination = Join-Path $Root "src\content\$($target.Code)\ui.json"
    if ($Force -or -not (Test-Path -LiteralPath $uiDestination) -or (Get-Item $uiDestination).Length -lt 200) {
        $sourceUi = Get-Content -Raw -LiteralPath (Join-Path $Root 'src\content\zh\ui.json') -Encoding UTF8
        $translatedUi = Invoke-Translation -Text $sourceUi -Language $target.Language -Format json
        $null = $translatedUi | ConvertFrom-Json
        Set-Content -LiteralPath $uiDestination -Value $translatedUi -Encoding UTF8
        Write-Host "Translated UI -> $($target.Code)"
    }

    foreach ($source in Get-ChildItem -LiteralPath (Join-Path $Root 'src\content\zh') -Filter '*.md') {
        $destination = Join-Path $Root "src\content\$($target.Code)\$($source.Name)"
        if (-not $Force -and (Test-Path -LiteralPath $destination) -and (Get-Item $destination).Length -ge 200) {
            Write-Host "Skipped existing $($source.Name) -> $($target.Code)"
            continue
        }
        $translated = Invoke-Translation -Text (Get-Content -Raw -LiteralPath $source.FullName -Encoding UTF8) -Language $target.Language -Format markdown
        if ($translated -notmatch '^---' -or $translated -notmatch '/(quant|crossBorderTrend|smartCockpit)/') {
            throw "Translation validation failed for $($source.Name) ($($target.Code))."
        }
        Set-Content -LiteralPath $destination -Value $translated -Encoding UTF8
        Write-Host "Translated $($source.Name) -> $($target.Code)"
    }
}
