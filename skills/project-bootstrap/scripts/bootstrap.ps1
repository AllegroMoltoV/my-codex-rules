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

function Add-ExcludeEntries {
    param(
        [string]$ExcludePath,
        [string]$TemplatePath
    )
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $ExcludePath)) | Out-Null
    $existingLines = if ([System.IO.File]::Exists($ExcludePath)) { @([System.IO.File]::ReadAllLines($ExcludePath)) } else { @() }
    $comparison = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
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
$excludeTemplate = Join-Path $assetsPath 'exclude'
foreach ($template in @($excludeTemplate)) {
    if (-not [System.IO.File]::Exists($template)) {
        throw "配布テンプレートがありません: $template"
    }
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
        $excludeValue = $resolvedExclude -join ''
        $excludePath = if ([System.IO.Path]::IsPathRooted($excludeValue)) {
            $excludeValue
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $target $excludeValue))
        }
    }
    finally {
        Set-Location -LiteralPath $originalLocation
    }
}
Add-ExcludeEntries -ExcludePath $excludePath -TemplatePath $excludeTemplate

$originalLocation = Get-Location
try {
    Set-Location -LiteralPath $target
    foreach ($reportPath in @('.reports/INDEX.md', '.reports/report.md')) {
        & $GitCommand check-ignore -q -- $reportPath
        if ($LASTEXITCODE -ne 0) {
            throw "Git の除外を確認できないため、調査記録を書き込みません: $reportPath"
        }
    }
}
finally {
    Set-Location -LiteralPath $originalLocation
}

foreach ($directory in @(
    '.appendix',
    '.tmp',
    '.logs',
    '.prompts',
    '.prompts\PLANS',
    '.prompts\DISCUSSIONS',
    '.prompts\INSPECTIONS',
    '.reports'
)) {
    [System.IO.Directory]::CreateDirectory((Join-Path $target $directory)) | Out-Null
}

$indexPath = Join-Path $target '.reports\INDEX.md'
if (-not [System.IO.File]::Exists($indexPath)) {
    $index = "# 文書索引`n`n調査レポートと保存する価値がある実行ログを、このディレクトリへ保存します。Git の追跡対象には含めません。生の実行ログは .logs/ に保存します。`n"
    [System.IO.File]::WriteAllText($indexPath, $index, [System.Text.UTF8Encoding]::new($false))
}

$optOutPath = Join-Path $target '.beads-optout'
if (-not $NoBeads -and -not [System.IO.File]::Exists($optOutPath)) {
    if (-not (Test-CommandAvailable -Name $BdCommand)) {
        throw "bdコマンドが見つかりません: $BdCommand"
    }
    $originalLocation = Get-Location
    try {
        Set-Location -LiteralPath $target
        $beadsRole = @(& $GitCommand config --local --get beads.role)
        if ($LASTEXITCODE -notin @(0, 1)) {
            throw 'Gitのローカルbeads.roleを確認できません。'
        }
        if ([string]::IsNullOrWhiteSpace(($beadsRole -join ''))) {
            & $GitCommand config --local beads.role maintainer
            if ($LASTEXITCODE -ne 0) {
                throw 'Gitのローカルbeads.roleを設定できません。'
            }
        }
        & $BdCommand init --stealth --skip-agents --non-interactive --init-if-missing
        if ($LASTEXITCODE -ne 0) {
            throw 'Beadsの初期化に失敗しました。'
        }
        & $BdCommand config set no-git-ops false
        if ($LASTEXITCODE -ne 0) {
            throw 'BeadsのGit操作制限を解除できません。'
        }
    }
    finally {
        Set-Location -LiteralPath $originalLocation
    }
}

Write-Host "プロジェクト初期セットアップを完了しました: $target"
