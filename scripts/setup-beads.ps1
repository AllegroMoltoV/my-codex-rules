[CmdletBinding()]
param(
    [string]$HomePath = $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }),
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HomePath '.codex' }),
    [string]$BdCommand = 'bd',
    [string]$JqCommand = 'jq',
    [string]$CodexCommand = 'codex'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'lib\BeadsSetup.psm1'
Import-Module $modulePath -Force

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
    if (-not [System.IO.File]::Exists($Path)) {
        return $null
    }
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($Path)))
}

function Get-TreeDigest {
    param([string]$Path)
    if (-not [System.IO.Directory]::Exists($Path)) {
        return $null
    }
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

function Copy-OwnedTree {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$ExpectedDigest
    )

    if ([System.IO.Directory]::Exists($Destination)) {
        $currentDigest = Get-TreeDigest -Path $Destination
        if ([string]::IsNullOrWhiteSpace($ExpectedDigest) -or $currentDigest -ne $ExpectedDigest) {
            throw "管理対象と確認できない既存ディレクトリは上書きしません: $Destination"
        }
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }

    [System.IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach ($directory in [System.IO.Directory]::GetDirectories($Source, '*', [System.IO.SearchOption]::AllDirectories)) {
        $relative = [System.IO.Path]::GetRelativePath($Source, $directory)
        [System.IO.Directory]::CreateDirectory((Join-Path $Destination $relative)) | Out-Null
    }
    foreach ($file in [System.IO.Directory]::GetFiles($Source, '*', [System.IO.SearchOption]::AllDirectories)) {
        $relative = [System.IO.Path]::GetRelativePath($Source, $file)
        $target = Join-Path $Destination $relative
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($file))
    }
    return Get-TreeDigest -Path $Destination
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7以降が必要です。'
}

$dependencies = @($BdCommand, $JqCommand, $CodexCommand)
foreach ($dependency in $dependencies) {
    if (-not (Test-ExternalCommand -Name $dependency)) {
        throw "依存コマンドが見つかりません: $dependency"
    }
}

$versions = [ordered]@{}
foreach ($entry in @(
    [pscustomobject]@{ Name = 'bd'; Command = $BdCommand },
    [pscustomobject]@{ Name = 'jq'; Command = $JqCommand },
    [pscustomobject]@{ Name = 'codex'; Command = $CodexCommand }
)) {
    $versionOutput = & $entry.Command --version
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($versionOutput -join ' '))) {
        throw "版を確認できません: $($entry.Name)"
    }
    $versions[$entry.Name] = ($versionOutput -join ' ').Trim()
}

$paths = Get-BeadsManagedPaths -HomePath $HomePath -CodexHome $CodexHome
$globalAgentsPath = Join-Path $paths.CodexHome 'AGENTS.md'
$sourceRulesPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'rules\AGENTS.md'
$sourceSkillPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\project-bootstrap'
$sourceNudgePath = Join-Path $PSScriptRoot 'beads-stop-nudge.ps1'
if (-not [System.IO.File]::Exists($sourceRulesPath)) {
    throw "グローバルルールがありません: $sourceRulesPath"
}
if (-not [System.IO.Directory]::Exists($sourceSkillPath)) {
    throw "project-bootstrapスキルがありません: $sourceSkillPath"
}
if (-not [System.IO.File]::Exists($sourceNudgePath)) {
    throw "記録漏れ通知スクリプトがありません: $sourceNudgePath"
}

[System.IO.Directory]::CreateDirectory($paths.CodexHome) | Out-Null
$previousState = $null
if ([System.IO.File]::Exists($paths.StatePath)) {
    $previousState = [System.IO.File]::ReadAllText($paths.StatePath) | ConvertFrom-Json
}

$expectedGlobalAgentsDigest = $null
if (
    $null -ne $previousState -and
    [bool]$previousState.installed -and
    $null -ne $previousState.PSObject.Properties['global_agents_digest']
) {
    $expectedGlobalAgentsDigest = [string]$previousState.global_agents_digest
}
if (-not [string]::IsNullOrWhiteSpace($expectedGlobalAgentsDigest)) {
    $currentGlobalAgentsDigest = Get-FileDigest -Path $globalAgentsPath
    if ($currentGlobalAgentsDigest -ne $expectedGlobalAgentsDigest) {
        throw "導入後に変更されたグローバルAGENTS.mdは上書きしません: $globalAgentsPath"
    }
}

$expectedSkillDigest = if ($null -ne $previousState -and [bool]$previousState.installed) { [string]$previousState.project_bootstrap_digest } else { $null }
if ([System.IO.Directory]::Exists($paths.ProjectBootstrapPath)) {
    $existingSkillDigest = Get-TreeDigest -Path $paths.ProjectBootstrapPath
    if ([string]::IsNullOrWhiteSpace($expectedSkillDigest) -or $existingSkillDigest -ne $expectedSkillDigest) {
        throw "既存のproject-bootstrapスキルは管理対象と確認できないため変更しません: $($paths.ProjectBootstrapPath)"
    }
}

$backupManifest = $null
if (
    $null -ne $previousState -and
    [bool]$previousState.installed -and
    -not [string]::IsNullOrWhiteSpace($expectedGlobalAgentsDigest)
) {
    $backupManifest = [string]$previousState.backup_manifest
}
else {
    $backupDirectory = Join-Path $paths.BackupRoot ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffffffZ') + '-' + [guid]::NewGuid().ToString('N'))
    $backupManifest = New-BeadsBackup -CodexHome $paths.CodexHome -BackupRoot $backupDirectory
}

$officialSetupStarted = $false
$skillCopied = $false
try {
    [System.IO.File]::WriteAllBytes($globalAgentsPath, [System.IO.File]::ReadAllBytes($sourceRulesPath))
    Invoke-IsolatedBd -Arguments @('metrics', 'off')
    $officialSetupStarted = $true
    Invoke-IsolatedBd -Arguments @('setup', 'codex', '--global')

    [System.IO.Directory]::CreateDirectory($paths.RuntimeRoot) | Out-Null
    [System.IO.File]::WriteAllBytes($paths.NudgeScriptPath, [System.IO.File]::ReadAllBytes($sourceNudgePath))
    $hookCommand = 'pwsh -NoProfile -File "' + $paths.NudgeScriptPath + '"'
    Add-BeadsStopHook -HooksPath $paths.HooksPath -Command $hookCommand

    $skillDigest = Copy-OwnedTree -Source $sourceSkillPath -Destination $paths.ProjectBootstrapPath -ExpectedDigest $expectedSkillDigest
    $skillCopied = $true
    $state = [pscustomobject]@{
        version = 2
        installed = $true
        installed_at = [DateTimeOffset]::UtcNow.ToString('o')
        home_path = $paths.HomePath
        codex_home = $paths.CodexHome
        backup_manifest = $backupManifest
        hook_command = $hookCommand
        global_agents_digest = Get-FileDigest -Path $globalAgentsPath
        nudge_digest = Get-FileDigest -Path $paths.NudgeScriptPath
        project_bootstrap_digest = $skillDigest
        dependency_versions = $versions
    }
    Write-Utf8JsonFile -Path $paths.StatePath -InputObject $state
}
catch {
    $setupError = $_
    if ($officialSetupStarted) {
        try {
            Invoke-IsolatedBd -Arguments @('setup', 'codex', '--global', '--remove')
        }
        catch {
            Write-Warning '公式Codex統合のロールバックに失敗しました。バックアップは保持しています。'
        }
    }
    try {
        Restore-BeadsBackup -ManifestPath $backupManifest
    }
    catch {
        Write-Warning 'Codex設定のバックアップ復元に失敗しました。'
    }
    if ($skillCopied -and [System.IO.Directory]::Exists($paths.ProjectBootstrapPath)) {
        Remove-Item -LiteralPath $paths.ProjectBootstrapPath -Recurse -Force
    }
    throw $setupError
}

Write-Host '共通ルール、project-bootstrap、BeadsのCodex統合を設定しました。'
Write-Host "bd: $($versions.bd)"
Write-Host "jq: $($versions.jq)"
Write-Host "codex: $($versions.codex)"
Write-Host 'Codexで/hooksを開き、追加されたフックを確認して信頼してください。'
