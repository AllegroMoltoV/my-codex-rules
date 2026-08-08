[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TargetPath,
    [switch]$NoBeads,
    [string]$BdCommand = 'bd',
    [string]$GitCommand = 'git'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CommandAvailable {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Copy-TemplateIfMissing {
    param(
        [string]$Source,
        [string]$Destination
    )
    if ([System.IO.File]::Exists($Destination)) {
        return
    }
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Destination)) | Out-Null
    [System.IO.File]::WriteAllBytes($Destination, [System.IO.File]::ReadAllBytes($Source))
}

function Add-ExcludeEntries {
    param(
        [string]$ExcludePath,
        [string]$TemplatePath
    )
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $ExcludePath)) | Out-Null
    $existingLines = if ([System.IO.File]::Exists($ExcludePath)) { @([System.IO.File]::ReadAllLines($ExcludePath)) } else { @() }
    $comparison = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $existingLines) {
        [void]$comparison.Add($line.Trim())
    }
    $newLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($TemplatePath)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }
        if ($comparison.Add($trimmed)) {
            $newLines.Add($trimmed)
        }
    }
    if ($newLines.Count -eq 0) {
        return
    }
    $combined = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $existingLines) { $combined.Add($line) }
    if ($combined.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($combined[$combined.Count - 1])) {
        $combined.Add('')
    }
    $combined.Add('# my-codex-rules local files')
    foreach ($line in $newLines) { $combined.Add($line) }
    [System.IO.File]::WriteAllText($ExcludePath, (($combined -join [Environment]::NewLine) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

$target = [System.IO.Path]::GetFullPath($TargetPath)
if (-not [System.IO.Directory]::Exists($target)) {
    throw "対象ディレクトリがありません: $target"
}
if (-not (Test-CommandAvailable -Name $GitCommand)) {
    throw "gitコマンドが見つかりません: $GitCommand"
}

$gitMarker = Join-Path $target '.git'
if (-not [System.IO.Directory]::Exists($gitMarker) -and -not [System.IO.File]::Exists($gitMarker)) {
    $originalLocation = Get-Location
    try {
        Set-Location -LiteralPath $target
        & $GitCommand init -b main
        if ($LASTEXITCODE -ne 0) {
            throw 'git initに失敗しました。'
        }
    }
    finally {
        Set-Location -LiteralPath $originalLocation
    }
}

$assetsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets'
$agentsTemplate = Join-Path $assetsPath 'AGENTS.md'
$initTemplate = Join-Path $assetsPath 'INIT.md'
$excludeTemplate = Join-Path $assetsPath 'exclude'
foreach ($template in @($agentsTemplate, $initTemplate, $excludeTemplate)) {
    if (-not [System.IO.File]::Exists($template)) {
        throw "配布テンプレートがありません: $template"
    }
}

foreach ($directory in @(
    '.appendix',
    '.tmp',
    '.logs',
    '.prompts',
    '.prompts\PLANS',
    '.prompts\DISCUSSIONS',
    '.prompts\INSPECTIONS',
    'docs',
    'docs\reports',
    'docs\logs'
)) {
    [System.IO.Directory]::CreateDirectory((Join-Path $target $directory)) | Out-Null
}

Copy-TemplateIfMissing -Source $agentsTemplate -Destination (Join-Path $target 'AGENTS.md')
Copy-TemplateIfMissing -Source $initTemplate -Destination (Join-Path $target '.prompts\INIT.md')

$indexPath = Join-Path $target 'docs\INDEX.md'
if (-not [System.IO.File]::Exists($indexPath)) {
    $index = "# 文書索引`n`n## reports`n`n調査結果と検証結果を保存します。`n`n## logs`n`n再確認が必要な実行ログを保存します。`n"
    [System.IO.File]::WriteAllText($indexPath, $index, [System.Text.UTF8Encoding]::new($false))
}

$excludePath = $null
if ([System.IO.Directory]::Exists($gitMarker)) {
    $excludePath = Join-Path $gitMarker 'info\exclude'
}
else {
    $originalLocation = Get-Location
    try {
        Set-Location -LiteralPath $target
        $resolvedExclude = & $GitCommand rev-parse --git-path info/exclude
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($resolvedExclude -join ''))) {
            throw '.git/info/excludeの場所を解決できません。'
        }
        $excludePath = [System.IO.Path]::GetFullPath((Join-Path $target ($resolvedExclude -join '')))
    }
    finally {
        Set-Location -LiteralPath $originalLocation
    }
}
Add-ExcludeEntries -ExcludePath $excludePath -TemplatePath $excludeTemplate

$optOutPath = Join-Path $target '.beads-optout'
if (-not $NoBeads -and -not [System.IO.File]::Exists($optOutPath)) {
    if (-not (Test-CommandAvailable -Name $BdCommand)) {
        throw "bdコマンドが見つかりません: $BdCommand"
    }
    $originalLocation = Get-Location
    try {
        Set-Location -LiteralPath $target
        & $BdCommand init --stealth --skip-agents --non-interactive --init-if-missing
        if ($LASTEXITCODE -ne 0) {
            throw 'Beadsの初期化に失敗しました。'
        }
    }
    finally {
        Set-Location -LiteralPath $originalLocation
    }
}

Write-Host "プロジェクト初期セットアップを完了しました: $target"
