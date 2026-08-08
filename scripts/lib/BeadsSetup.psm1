Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ManagedFileNames = @('AGENTS.md', 'hooks.json', 'config.toml')

function ConvertTo-CanonicalJsonValue {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        $keys = @($Value.Keys)
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        foreach ($key in $keys) {
            $result[[string]$key] = ConvertTo-CanonicalJsonValue -Value $Value[$key]
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $items.Add((ConvertTo-CanonicalJsonValue -Value $item))
        }
        return ,@($items)
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        $names = @($Value.PSObject.Properties.Name)
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
        foreach ($name in $names) {
            $result[$name] = ConvertTo-CanonicalJsonValue -Value $Value.PSObject.Properties[$name].Value
        }
        return $result
    }
    return $Value
}
function Write-Utf8JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $InputObject
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $canonicalValue = ConvertTo-CanonicalJsonValue -Value $InputObject
    $json = $canonicalValue | ConvertTo-Json -Depth 100
    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::ReadAllText($temporaryPath) | ConvertFrom-Json | Out-Null
        [System.IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Get-JsonProperty {
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return $InputObject.PSObject.Properties[$Name]
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        $Value
    )

    $property = Get-JsonProperty -InputObject $InputObject -Name $Name
    if ($null -eq $property) {
        $InputObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else {
        $property.Value = $Value
    }
}

function Remove-JsonProperty {
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -ne (Get-JsonProperty -InputObject $InputObject -Name $Name)) {
        $InputObject.PSObject.Properties.Remove($Name)
    }
}

function Read-HooksFile {
    param(
        [Parameter(Mandatory)]
        [string]$HooksPath
    )

    if (-not (Test-Path -LiteralPath $HooksPath)) {
        return [pscustomobject]@{
            description = 'Codex lifecycle hooks.'
            hooks = [pscustomobject]@{}
        }
    }

    $content = [System.IO.File]::ReadAllText($HooksPath)
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "hooks.jsonが空です: $HooksPath"
    }

    $configuration = $content | ConvertFrom-Json
    if ($configuration -is [System.Array]) {
        throw "hooks.jsonのルートはオブジェクトである必要があります: $HooksPath"
    }

    $hooksProperty = Get-JsonProperty -InputObject $configuration -Name 'hooks'
    if ($null -eq $hooksProperty) {
        Set-JsonProperty -InputObject $configuration -Name 'hooks' -Value ([pscustomobject]@{})
    }
    elseif ($null -eq $hooksProperty.Value -or $hooksProperty.Value -is [System.Array]) {
        throw "hooks.jsonのhooksはオブジェクトである必要があります: $HooksPath"
    }

    return $configuration
}

function Add-BeadsStopHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HooksPath,

        [Parameter(Mandatory)]
        [string]$Command
    )

    $configuration = Read-HooksFile -HooksPath $HooksPath
    $stopProperty = Get-JsonProperty -InputObject $configuration.hooks -Name 'Stop'
    $groups = if ($null -eq $stopProperty) { @() } else { @($stopProperty.Value) }

    foreach ($group in $groups) {
        $handlersProperty = Get-JsonProperty -InputObject $group -Name 'hooks'
        if ($null -eq $handlersProperty) {
            continue
        }

        foreach ($handler in @($handlersProperty.Value)) {
            $commandProperty = Get-JsonProperty -InputObject $handler -Name 'command'
            if ($null -ne $commandProperty -and $commandProperty.Value -eq $Command) {
                Write-Utf8JsonFile -Path $HooksPath -InputObject $configuration
                return
            }
        }
    }

    $managedGroup = [pscustomobject]@{
        hooks = @(
            [pscustomobject]@{
                type = 'command'
                command = $Command
                timeout = 30
                statusMessage = 'Checking Beads progress'
            }
        )
    }

    Set-JsonProperty -InputObject $configuration.hooks -Name 'Stop' -Value (@($groups) + @($managedGroup))
    Write-Utf8JsonFile -Path $HooksPath -InputObject $configuration
}

function Remove-BeadsStopHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HooksPath,

        [Parameter(Mandatory)]
        [string]$Command
    )

    if (-not (Test-Path -LiteralPath $HooksPath)) {
        return
    }

    $configuration = Read-HooksFile -HooksPath $HooksPath
    $stopProperty = Get-JsonProperty -InputObject $configuration.hooks -Name 'Stop'
    if ($null -eq $stopProperty) {
        return
    }

    $remainingGroups = [System.Collections.Generic.List[object]]::new()
    $changed = $false
    foreach ($group in @($stopProperty.Value)) {
        $handlersProperty = Get-JsonProperty -InputObject $group -Name 'hooks'
        if ($null -eq $handlersProperty) {
            $remainingGroups.Add($group)
            continue
        }

        $remainingHandlers = @(
            foreach ($handler in @($handlersProperty.Value)) {
                $commandProperty = Get-JsonProperty -InputObject $handler -Name 'command'
                if ($null -ne $commandProperty -and $commandProperty.Value -eq $Command) {
                    $changed = $true
                }
                else {
                    $handler
                }
            }
        )

        if ($remainingHandlers.Count -gt 0) {
            Set-JsonProperty -InputObject $group -Name 'hooks' -Value $remainingHandlers
            $remainingGroups.Add($group)
        }
    }

    if (-not $changed) {
        return
    }

    if ($remainingGroups.Count -eq 0) {
        Remove-JsonProperty -InputObject $configuration.hooks -Name 'Stop'
    }
    else {
        Set-JsonProperty -InputObject $configuration.hooks -Name 'Stop' -Value @($remainingGroups)
    }

    Write-Utf8JsonFile -Path $HooksPath -InputObject $configuration
}

function New-BeadsBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CodexHome,

        [Parameter(Mandatory)]
        [string]$BackupRoot
    )

    $resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
    $resolvedBackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)
    if (Test-Path -LiteralPath $resolvedBackupRoot) {
        $existingItems = [System.IO.Directory]::GetFileSystemEntries($resolvedBackupRoot)
        if ($existingItems.Count -gt 0) {
            throw "バックアップ先が空ではありません: $resolvedBackupRoot"
        }
    }

    [System.IO.Directory]::CreateDirectory($resolvedBackupRoot) | Out-Null
    $filesDirectory = Join-Path $resolvedBackupRoot 'files'
    [System.IO.Directory]::CreateDirectory($filesDirectory) | Out-Null
    $entries = [System.Collections.Generic.List[object]]::new()

    foreach ($name in $script:ManagedFileNames) {
        $sourcePath = Join-Path $resolvedCodexHome $name
        $backupPath = Join-Path $filesDirectory $name
        $exists = [System.IO.File]::Exists($sourcePath)
        if ($exists) {
            [System.IO.File]::WriteAllBytes($backupPath, [System.IO.File]::ReadAllBytes($sourcePath))
        }

        $entries.Add([pscustomobject]@{
            name = $name
            existed = $exists
        })
    }

    $manifest = [pscustomobject]@{
        version = 1
        codex_home = $resolvedCodexHome
        created_at = [DateTimeOffset]::UtcNow.ToString('o')
        files = @($entries)
    }
    $manifestPath = Join-Path $resolvedBackupRoot 'manifest.json'
    Write-Utf8JsonFile -Path $manifestPath -InputObject $manifest
    return $manifestPath
}

function Restore-BeadsBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    $resolvedManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
    if (-not [System.IO.File]::Exists($resolvedManifestPath)) {
        throw "バックアップ記録がありません: $resolvedManifestPath"
    }

    $manifest = [System.IO.File]::ReadAllText($resolvedManifestPath) | ConvertFrom-Json
    if ($manifest.version -ne 1) {
        throw "未対応のバックアップ形式です: $($manifest.version)"
    }

    $codexHome = [System.IO.Path]::GetFullPath([string]$manifest.codex_home)
    [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
    $backupRoot = Split-Path -Parent $resolvedManifestPath
    $seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in @($manifest.files)) {
        $name = [string]$entry.name
        if ($script:ManagedFileNames -notcontains $name -or -not $seenNames.Add($name)) {
            throw "不正なバックアップ対象名です: $name"
        }

        $destinationPath = Join-Path $codexHome $name
        if ([bool]$entry.existed) {
            $backupPath = Join-Path (Join-Path $backupRoot 'files') $name
            if (-not [System.IO.File]::Exists($backupPath)) {
                throw "バックアップファイルがありません: $backupPath"
            }
            [System.IO.File]::WriteAllBytes($destinationPath, [System.IO.File]::ReadAllBytes($backupPath))
        }
        elseif ([System.IO.File]::Exists($destinationPath)) {
            Remove-Item -LiteralPath $destinationPath -Force
        }
    }

    if ($seenNames.Count -ne $script:ManagedFileNames.Count) {
        throw 'バックアップ記録に必要な対象がそろっていません。'
    }
}

function Test-ExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-BeadsManagedPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HomePath,

        [Parameter(Mandatory)]
        [string]$CodexHome
    )

    $resolvedHome = [System.IO.Path]::GetFullPath($HomePath)
    $resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
    $runtimeRoot = Join-Path $resolvedCodexHome 'my-codex-rules-beads'
    return [pscustomobject]@{
        HomePath = $resolvedHome
        CodexHome = $resolvedCodexHome
        HooksPath = Join-Path $resolvedCodexHome 'hooks.json'
        RuntimeRoot = $runtimeRoot
        NudgeScriptPath = Join-Path $runtimeRoot 'beads-stop-nudge.ps1'
        StatePath = Join-Path $runtimeRoot 'state.json'
        BackupRoot = Join-Path $runtimeRoot 'backup'
        ProjectBootstrapPath = Join-Path $resolvedHome '.agents\skills\project-bootstrap'
    }
}

Export-ModuleMember -Function @(
    'Add-BeadsStopHook',
    'Get-BeadsManagedPaths',
    'New-BeadsBackup',
    'Remove-BeadsStopHook',
    'Restore-BeadsBackup',
    'Test-ExternalCommand',
    'Write-Utf8JsonFile'
)
