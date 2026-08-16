[CmdletBinding()]
param(
    [switch]$Restore,
    [string]$HomePath = $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }),
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HomePath '.codex' }),
    [string]$BdCommand = 'bd'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\BeadsSetup.psm1') -Force

function Invoke-IsolatedBd {
    param([string[]]$Arguments)
    $originalHome = $env:HOME
    $originalUserProfile = $env:USERPROFILE
    $originalCodexHome = $env:CODEX_HOME
    try {
        $env:HOME = $HomePath
        $env:USERPROFILE = $HomePath
        $env:CODEX_HOME = $CodexHome
        & $BdCommand @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "bdコマンドが失敗しました: $($Arguments -join ' ')"
        }
    }
    finally {
        $env:HOME = $originalHome
        $env:USERPROFILE = $originalUserProfile
        $env:CODEX_HOME = $originalCodexHome
    }
}

function Get-FileDigest {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($Path)))
}

function Get-TreeDigest {
    param([string]$Path)
    if (-not [System.IO.Directory]::Exists($Path)) { return $null }
    $builder = [System.Text.StringBuilder]::new()
    $files = [System.IO.Directory]::GetFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)
    [Array]::Sort($files, [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        [void]$builder.Append([System.IO.Path]::GetRelativePath($Path, $file).Replace('\', '/'))
        [void]$builder.Append("`n")
        [void]$builder.Append((Get-FileDigest -Path $file))
        [void]$builder.Append("`n")
    }
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($builder.ToString())))
}

if (-not (Test-ExternalCommand -Name $BdCommand)) {
    throw "依存コマンドが見つかりません: $BdCommand"
}

$paths = Get-BeadsManagedPaths -HomePath $HomePath -CodexHome $CodexHome
$state = $null
if ([System.IO.File]::Exists($paths.StatePath)) {
    $state = [System.IO.File]::ReadAllText($paths.StatePath) | ConvertFrom-Json
}
if ($Restore -and $null -eq $state) {
    throw "復元に必要な状態記録がありません: $($paths.StatePath)"
}

Invoke-IsolatedBd -Arguments @('setup', 'codex', '--global', '--remove')

$hookCommand = if ($null -ne $state) { [string]$state.hook_command } else { 'pwsh -NoProfile -File "' + $paths.NudgeScriptPath + '"' }
Remove-BeadsStopHook -HooksPath $paths.HooksPath -Command $hookCommand

if ($null -ne $state -and [System.IO.Directory]::Exists($paths.ProjectBootstrapPath)) {
    $currentSkillDigest = Get-TreeDigest -Path $paths.ProjectBootstrapPath
    if ($currentSkillDigest -eq [string]$state.project_bootstrap_digest) {
        Remove-Item -LiteralPath $paths.ProjectBootstrapPath -Recurse -Force
    }
    else {
        Write-Warning "利用者の変更を検出したためスキルを削除しません: $($paths.ProjectBootstrapPath)"
    }
}

if (
    $null -ne $state -and
    $null -ne $state.PSObject.Properties['japanese_technical_writing_digest'] -and
    [System.IO.Directory]::Exists($paths.JapaneseTechnicalWritingPath)
) {
    $currentWritingSkillDigest = Get-TreeDigest -Path $paths.JapaneseTechnicalWritingPath
    if ($currentWritingSkillDigest -eq [string]$state.japanese_technical_writing_digest) {
        Remove-Item -LiteralPath $paths.JapaneseTechnicalWritingPath -Recurse -Force
    }
    else {
        Write-Warning "利用者の変更を検出したためスキルを削除しません: $($paths.JapaneseTechnicalWritingPath)"
    }
}

if ($null -ne $state -and [System.IO.File]::Exists($paths.NudgeScriptPath)) {
    $currentNudgeDigest = Get-FileDigest -Path $paths.NudgeScriptPath
    if ($currentNudgeDigest -eq [string]$state.nudge_digest) {
        Remove-Item -LiteralPath $paths.NudgeScriptPath -Force
    }
    else {
        Write-Warning "利用者の変更を検出したため通知スクリプトを削除しません: $($paths.NudgeScriptPath)"
    }
}

if ($Restore) {
    Write-Warning 'セットアップ後に加えたCodex設定は、バックアップ復元により失われます。'
    Restore-BeadsBackup -ManifestPath ([string]$state.backup_manifest)
    $state.installed = $false
    $state | Add-Member -NotePropertyName restored_at -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
    Write-Utf8JsonFile -Path $paths.StatePath -InputObject $state
    Write-Host 'Beads統合を取り消し、導入前のCodex設定を復元しました。'
}
elseif ($null -ne $state) {
    $state.installed = $false
    $state | Add-Member -NotePropertyName removed_at -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
    Write-Utf8JsonFile -Path $paths.StatePath -InputObject $state
    Write-Host 'Beads管理要素を削除しました。バックアップは保持しています。'
}
else {
    Write-Host '公式Beads統合の削除を確認しました。独自管理状態はありませんでした。'
}
