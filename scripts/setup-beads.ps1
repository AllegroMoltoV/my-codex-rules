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

function Get-BackupFileState {
    param(
        [string]$ManifestPath,
        [string]$Name
    )

    if (-not [System.IO.File]::Exists($ManifestPath)) {
        throw "バックアップ記録がありません: $ManifestPath"
    }
    $manifest = [System.IO.File]::ReadAllText($ManifestPath) | ConvertFrom-Json
    $entries = @($manifest.files | Where-Object { [string]$_.name -eq $Name })
    if ($entries.Count -ne 1) {
        throw "バックアップ記録の対象を一意に確認できません: $Name"
    }
    $existed = [bool]$entries[0].existed
    $digest = $null
    if ($existed) {
        $backupPath = Join-Path (Join-Path (Split-Path -Parent $ManifestPath) 'files') $Name
        $digest = Get-FileDigest -Path $backupPath
        if ([string]::IsNullOrWhiteSpace($digest)) {
            throw "バックアップファイルがありません: $backupPath"
        }
    }
    return [pscustomobject]@{
        Existed = $existed
        Digest = $digest
    }
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

function Copy-TreeBytes {
    param(
        [string]$Source,
        [string]$Destination
    )

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
}

function New-TreeSnapshot {
    param(
        [string]$Path,
        [string]$SnapshotRoot,
        [string]$Name
    )

    $backupPath = Join-Path $SnapshotRoot $Name
    $existed = [System.IO.Directory]::Exists($Path)
    if ($existed) {
        Copy-TreeBytes -Source $Path -Destination $backupPath
    }
    return [pscustomobject]@{
        DestinationPath = $Path
        BackupPath = $backupPath
        Existed = $existed
    }
}

function Restore-TreeSnapshot {
    param($Snapshot)

    if ([System.IO.Directory]::Exists($Snapshot.DestinationPath)) {
        Remove-Item -LiteralPath $Snapshot.DestinationPath -Recurse -Force
    }
    if ([bool]$Snapshot.Existed) {
        Copy-TreeBytes -Source $Snapshot.BackupPath -Destination $Snapshot.DestinationPath
    }
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
$globalOverridePath = Join-Path $paths.CodexHome 'AGENTS.override.md'
if ([System.IO.File]::Exists($globalOverridePath) -and (Get-Item -LiteralPath $globalOverridePath).Length -gt 0) {
    throw "非空のAGENTS.override.mdがあるため変更しません。このファイルが同階層のAGENTS.mdを隠します。内容を統合するか退避してください: $globalOverridePath"
}
$sourceRulesPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'rules\AGENTS.md'
$sourceSkillPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\project-bootstrap'
$sourceWritingSkillPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\japanese-technical-writing'
$sourceNudgePath = Join-Path $PSScriptRoot 'beads-stop-nudge.ps1'
if (-not [System.IO.File]::Exists($sourceRulesPath)) {
    throw "グローバルルールがありません: $sourceRulesPath"
}
if (-not [System.IO.Directory]::Exists($sourceSkillPath)) {
    throw "project-bootstrapスキルがありません: $sourceSkillPath"
}
if (-not [System.IO.Directory]::Exists($sourceWritingSkillPath)) {
    throw "japanese-technical-writingスキルがありません: $sourceWritingSkillPath"
}
if (-not [System.IO.File]::Exists($sourceNudgePath)) {
    throw "記録漏れ通知スクリプトがありません: $sourceNudgePath"
}

[System.IO.Directory]::CreateDirectory($paths.CodexHome) | Out-Null
$previousState = $null
if ([System.IO.File]::Exists($paths.StatePath)) {
    $previousState = [System.IO.File]::ReadAllText($paths.StatePath) | ConvertFrom-Json
}

$expectedGlobalAgentsKnown = $false
$expectedGlobalAgentsExisted = $false
$expectedGlobalAgentsDigest = $null
$stateWasRestored = (
    $null -ne $previousState -and
    $null -ne $previousState.PSObject.Properties['installed'] -and
    -not [bool]$previousState.installed -and
    $null -ne $previousState.PSObject.Properties['restored_at'] -and
    $null -ne $previousState.PSObject.Properties['backup_manifest']
)
if ($stateWasRestored) {
    $backupAgentsState = Get-BackupFileState -ManifestPath ([string]$previousState.backup_manifest) -Name 'AGENTS.md'
    $expectedGlobalAgentsKnown = $true
    $expectedGlobalAgentsExisted = [bool]$backupAgentsState.Existed
    $expectedGlobalAgentsDigest = [string]$backupAgentsState.Digest
}
elseif (
    $null -ne $previousState -and
    $null -ne $previousState.PSObject.Properties['global_agents_digest'] -and
    -not [string]::IsNullOrWhiteSpace([string]$previousState.global_agents_digest)
) {
    $expectedGlobalAgentsKnown = $true
    $expectedGlobalAgentsExisted = $true
    $expectedGlobalAgentsDigest = [string]$previousState.global_agents_digest
}
if ($expectedGlobalAgentsKnown) {
    $currentGlobalAgentsExists = [System.IO.File]::Exists($globalAgentsPath)
    $currentGlobalAgentsDigest = Get-FileDigest -Path $globalAgentsPath
    if (
        $currentGlobalAgentsExists -ne $expectedGlobalAgentsExisted -or
        ($expectedGlobalAgentsExisted -and $currentGlobalAgentsDigest -ne $expectedGlobalAgentsDigest)
    ) {
        throw "導入後に変更されたグローバルAGENTS.mdは上書きしません: $globalAgentsPath"
    }
}

$expectedSkillDigest = if (
    $null -ne $previousState -and
    $null -ne $previousState.PSObject.Properties['project_bootstrap_digest']
) { [string]$previousState.project_bootstrap_digest } else { $null }
if ([System.IO.Directory]::Exists($paths.ProjectBootstrapPath)) {
    $existingSkillDigest = Get-TreeDigest -Path $paths.ProjectBootstrapPath
    if ([string]::IsNullOrWhiteSpace($expectedSkillDigest) -or $existingSkillDigest -ne $expectedSkillDigest) {
        throw "既存のproject-bootstrapスキルは管理対象と確認できないため変更しません: $($paths.ProjectBootstrapPath)"
    }
}

$expectedWritingSkillDigest = if (
    $null -ne $previousState -and
    $null -ne $previousState.PSObject.Properties['japanese_technical_writing_digest']
) { [string]$previousState.japanese_technical_writing_digest } else { $null }
if ([System.IO.Directory]::Exists($paths.JapaneseTechnicalWritingPath)) {
    $existingWritingSkillDigest = Get-TreeDigest -Path $paths.JapaneseTechnicalWritingPath
    if ([string]::IsNullOrWhiteSpace($expectedWritingSkillDigest) -or $existingWritingSkillDigest -ne $expectedWritingSkillDigest) {
        throw "既存のjapanese-technical-writingスキルは管理対象と確認できないため変更しません: $($paths.JapaneseTechnicalWritingPath)"
    }
}

$rollbackRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('my-codex-rules-setup-rollback-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($rollbackRoot) | Out-Null
$rollbackManifest = New-BeadsBackup -CodexHome $paths.CodexHome -BackupRoot (Join-Path $rollbackRoot 'codex-files')
$treeSnapshots = @(
    New-TreeSnapshot -Path $paths.RuntimeRoot -SnapshotRoot $rollbackRoot -Name 'runtime'
    New-TreeSnapshot -Path $paths.BeadsSkillPath -SnapshotRoot $rollbackRoot -Name 'beads-skill'
    New-TreeSnapshot -Path $paths.ProjectBootstrapPath -SnapshotRoot $rollbackRoot -Name 'project-bootstrap'
    New-TreeSnapshot -Path $paths.JapaneseTechnicalWritingPath -SnapshotRoot $rollbackRoot -Name 'japanese-technical-writing'
)
$wasInstalled = (
    $null -ne $previousState -and
    $null -ne $previousState.PSObject.Properties['installed'] -and
    [bool]$previousState.installed
)
$backupManifest = $null
$officialSetupStarted = $false
$rollbackFailed = $false
try {
    if (
        $null -ne $previousState -and
        $null -ne $previousState.PSObject.Properties['backup_manifest'] -and
        -not [string]::IsNullOrWhiteSpace([string]$previousState.backup_manifest)
    ) {
        $backupManifest = [string]$previousState.backup_manifest
    }
    else {
        $backupDirectory = Join-Path $paths.BackupRoot ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffffffZ') + '-' + [guid]::NewGuid().ToString('N'))
        $backupManifest = New-BeadsBackup -CodexHome $paths.CodexHome -BackupRoot $backupDirectory
    }

    [System.IO.File]::WriteAllBytes($globalAgentsPath, [System.IO.File]::ReadAllBytes($sourceRulesPath))
    $approvalDefaults = Add-CodexApprovalDefaults -ConfigPath (Join-Path $paths.CodexHome 'config.toml')
    if ($approvalDefaults.ApprovalPolicyExisted -and -not $approvalDefaults.ApprovalPolicyMatchesDefault) {
        Write-Warning '既存のapproval_policyを保持しました。on-requestではないためAuto-reviewが有効にならない可能性があります。'
    }
    if ($approvalDefaults.ApprovalsReviewerExisted -and -not $approvalDefaults.ApprovalsReviewerMatchesDefault) {
        Write-Warning '既存のapprovals_reviewerを保持しました。auto_reviewではないため承認は利用者へ送られます。'
    }

    Invoke-IsolatedBd -Arguments @('metrics', 'off')
    $officialSetupStarted = $true
    Invoke-IsolatedBd -Arguments @('setup', 'codex', '--global')

    [System.IO.Directory]::CreateDirectory($paths.RuntimeRoot) | Out-Null
    [System.IO.File]::WriteAllBytes($paths.NudgeScriptPath, [System.IO.File]::ReadAllBytes($sourceNudgePath))
    $hookCommand = 'pwsh -NoProfile -File "' + $paths.NudgeScriptPath + '"'
    Add-BeadsStopHook -HooksPath $paths.HooksPath -Command $hookCommand

    $skillDigest = Copy-OwnedTree -Source $sourceSkillPath -Destination $paths.ProjectBootstrapPath -ExpectedDigest $expectedSkillDigest
    $writingSkillDigest = Copy-OwnedTree -Source $sourceWritingSkillPath -Destination $paths.JapaneseTechnicalWritingPath -ExpectedDigest $expectedWritingSkillDigest
    $state = [pscustomobject]@{
        version = 3
        installed = $true
        installed_at = [DateTimeOffset]::UtcNow.ToString('o')
        home_path = $paths.HomePath
        codex_home = $paths.CodexHome
        backup_manifest = $backupManifest
        hook_command = $hookCommand
        global_agents_digest = Get-FileDigest -Path $globalAgentsPath
        nudge_digest = Get-FileDigest -Path $paths.NudgeScriptPath
        project_bootstrap_digest = $skillDigest
        japanese_technical_writing_digest = $writingSkillDigest
        dependency_versions = $versions
    }
    Write-Utf8JsonFile -Path $paths.StatePath -InputObject $state
}
catch {
    $setupError = $_
    if ($officialSetupStarted -and -not $wasInstalled) {
        try {
            Invoke-IsolatedBd -Arguments @('setup', 'codex', '--global', '--remove')
        }
        catch {
            $rollbackFailed = $true
            Write-Warning '公式Codex統合の取り消しに失敗しました。一時退避を保持しています。'
        }
    }
    try {
        Restore-BeadsBackup -ManifestPath $rollbackManifest
    }
    catch {
        $rollbackFailed = $true
        Write-Warning 'Codex設定を開始直前の状態へ戻せませんでした。'
    }
    foreach ($snapshot in $treeSnapshots) {
        try {
            Restore-TreeSnapshot -Snapshot $snapshot
        }
        catch {
            $rollbackFailed = $true
            Write-Warning "管理ディレクトリを開始直前の状態へ戻せませんでした: $($snapshot.DestinationPath)"
        }
    }
    if (-not $rollbackFailed -and [System.IO.Directory]::Exists($rollbackRoot)) {
        Remove-Item -LiteralPath $rollbackRoot -Recurse -Force
    }
    elseif ($rollbackFailed) {
        Write-Warning "手動復旧用の一時退避を保持しました: $rollbackRoot"
    }
    throw $setupError
}

if ([System.IO.Directory]::Exists($rollbackRoot)) {
    Remove-Item -LiteralPath $rollbackRoot -Recurse -Force
}

Write-Host '共通ルール、2つのスキル、Auto-review、BeadsのCodex統合を設定しました。'
Write-Host "bd: $($versions.bd)"
Write-Host "jq: $($versions.jq)"
Write-Host "codex: $($versions.codex)"
Write-Host 'Codexで/hooksを開き、追加されたフックを確認して信頼してください。'
